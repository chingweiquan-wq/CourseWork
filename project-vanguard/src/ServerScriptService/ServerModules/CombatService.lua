--!strict
-- CombatService: server-authoritative weapons.
-- The client only says "I fired from here, in this direction (and I think I hit this part)".
-- The server checks: alive, in a live match, not reloading, has ammo, fire-rate, origin near the head,
-- valid direction, target is an enemy, target really is near that ray, and nothing solid is in the way.
-- Damage, deaths, kill credit, assists and ammo are all decided here.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local WeaponConfig = require(ReplicatedStorage.Modules.WeaponConfig)
local MatchManager = require(script.Parent.MatchManager)
local CharacterService = require(script.Parent.CharacterService)

local Remotes = ReplicatedStorage.Remotes
local FireRemote = Remotes.Fire :: RemoteEvent
local ReloadRemote = Remotes.Reload :: RemoteEvent
local CombatFx = Remotes.CombatFx :: RemoteEvent
local HitConfirm = Remotes.HitConfirm :: RemoteEvent

local CombatConfig = GameConfig.Combat

export type Combatant = {
	Model: Model,
	Humanoid: Humanoid,
	Player: Player?,
	Team: string?,
	MatchId: string?,
}

type WeaponState = {
	WeaponId: string,
	Ammo: number,
	Reloading: boolean,
	ReloadToken: number,
	LastShot: number,
	BurstCount: number,
	ShotTimes: { number },
}

local CombatService = {}

local states: { [Player]: WeaponState } = {}
-- damageLog[victimModel][attackerPlayer] = { Time, Weapon, Headshot }
local damageLog: { [Model]: { [Player]: { Time: number, Weapon: string, Headshot: boolean } } } = {}
local damageListeners: { (Player, Combatant, number) -> () } = {}
local attackListeners: { (Player) -> () } = {}
-- Phase 3: AbilityService supplies buff multipliers (Overdrive, Deadeye, Nightfall...)
local modifierProvider: ((Player) -> { DamageMult: number, FireRateMult: number })? = nil

function CombatService.SetModifierProvider(fn: (Player) -> { DamageMult: number, FireRateMult: number })
	modifierProvider = fn
end

function CombatService.OnAttack(fn: (Player) -> ())
	table.insert(attackListeners, fn)
end

local function mods(player: Player): { DamageMult: number, FireRateMult: number }
	if modifierProvider then return modifierProvider(player) end
	return { DamageMult = 1, FireRateMult = 1 }
end

---------------------------------------------------------------- shields (Titan's Fortress Shield, future barriers)
-- A shield is any BasePart tagged "Shield" with attributes Team, MatchId, ShieldHealth.
-- Your own team's shots pass through it; enemy shots are absorbed and damage it.
local function friendlyShields(player: Player): { Instance }
	local list = {}
	local team = player:GetAttribute("Team")
	local matchId = player:GetAttribute("MatchId")
	for _, s in ipairs(CollectionService:GetTagged("Shield")) do
		if s:GetAttribute("MatchId") == matchId and s:GetAttribute("Team") == team then table.insert(list, s) end
	end
	return list
end

local function isEnemyShield(player: Player, inst: Instance?): boolean
	return inst ~= nil and CollectionService:HasTag(inst, "Shield") and inst:GetAttribute("MatchId") == player:GetAttribute("MatchId")
		and inst:GetAttribute("Team") ~= player:GetAttribute("Team")
end

function CombatService.DamageShield(attacker: Player, shield: BasePart, amount: number)
	local hp = (shield:GetAttribute("ShieldHealth") :: number? or 0) - amount
	shield:SetAttribute("ShieldHealth", hp)
	HitConfirm:FireClient(attacker, { Damage = math.floor(amount + 0.5), Shield = true })
	if hp <= 0 then shield:Destroy() end
end

local function shotExclusions(player: Player, character: Model, extra: { Instance }?): { Instance }
	local list: { Instance } = { character }
	for _, s in ipairs(friendlyShields(player)) do table.insert(list, s) end
	if extra then for _, e in ipairs(extra) do table.insert(list, e) end end
	return list
end

local projectileId = 0
type Projectile = { Id: number, Shooter: Player, Weapon: any, Pos: Vector3, Vel: Vector3, Travelled: number, Ignore: { Instance }, MatchId: string }
local projectiles: { Projectile } = {}

---------------------------------------------------------------- helpers
function CombatService.OnDamageDealt(fn: (Player, Combatant, number) -> ())
	table.insert(damageListeners, fn) -- Phase 3: ultimate charge hooks in here
end

function CombatService.GetCombatant(inst: Instance?): Combatant?
	local node = inst
	while node and node ~= workspace do
		if node:IsA("Model") then
			local hum = node:FindFirstChildOfClass("Humanoid")
			if hum then
				local plr = Players:GetPlayerFromCharacter(node)
				local team = if plr then plr:GetAttribute("Team") else node:GetAttribute("Team")
				local matchId = if plr then plr:GetAttribute("MatchId") else node:GetAttribute("MatchId")
				return { Model = node, Humanoid = hum, Player = plr, Team = team :: string?, MatchId = matchId :: string? }
			end
		end
		node = node.Parent
	end
	return nil
end

function CombatService.IsEnemy(attacker: Player, target: Combatant): boolean
	if target.Player == attacker then return false end
	local matchId = attacker:GetAttribute("MatchId")
	if not matchId or target.MatchId ~= matchId then return false end
	local myTeam = attacker:GetAttribute("Team")
	return target.Team ~= nil and target.Team ~= myTeam -- friendly-fire prevention
end

function CombatService.GetCombatantsInMatch(match: any): { Combatant }
	local list = {}
	for _, p in ipairs(match.Players) do
		local c = p.Character and CombatService.GetCombatant(p.Character:FindFirstChild("HumanoidRootPart"))
		if c then table.insert(list, c) end
	end
	local dummies = match.Map and match.Map:FindFirstChild("Dummies")
	if dummies then
		for _, m in ipairs(dummies:GetChildren()) do
			local c = CombatService.GetCombatant(m:FindFirstChild("HumanoidRootPart"))
			if c then table.insert(list, c) end
		end
	end
	return list
end

local function isHeadPart(part: BasePart): boolean
	if part.Name == "Head" then return true end
	local acc = part.Parent
	if acc and acc:IsA("Accessory") then
		local t = acc.AccessoryType
		return t == Enum.AccessoryType.Hat or t == Enum.AccessoryType.Hair or t == Enum.AccessoryType.Face
	end
	return false
end

local function setAmmoAttrs(player: Player, st: WeaponState)
	player:SetAttribute("Ammo", st.Ammo)
	player:SetAttribute("Reloading", st.Reloading)
end

local function geometryParams(exclude: { Instance }): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	params.IgnoreWater = true
	return params
end

local function matchPlayersFx(matchId: string, payload: { [string]: any })
	local match = MatchManager.GetMatchById(matchId)
	if not match then return end
	for _, p in ipairs(match.Players) do
		CombatFx:FireClient(p, payload)
	end
end

---------------------------------------------------------------- damage
function CombatService.ApplyDamage(attacker: Player, target: Combatant, amount: number, weaponName: string, headshot: boolean)
	local hum = target.Humanoid
	if hum.Health <= 0 or amount <= 0 then return end
	if target.Model:FindFirstChildOfClass("ForceField") then return end -- spawn protection
	local log = damageLog[target.Model]
	if not log then
		log = {}
		damageLog[target.Model] = log
	end
	log[attacker] = { Time = os.clock(), Weapon = weaponName, Headshot = headshot }
	local before = hum.Health
	hum.Health = math.max(0, before - amount)
	local dealt = before - hum.Health
	HitConfirm:FireClient(attacker, { Damage = math.floor(dealt + 0.5), Headshot = headshot, Killed = hum.Health <= 0 })
	for _, fn in ipairs(damageListeners) do task.spawn(fn, attacker, target, dealt) end
end

-- Every combatant humanoid (players + dummies) is watched so ANY death (weapons, falling) is credited.
function CombatService.WatchDeath(model: Model, humanoid: Humanoid)
	damageLog[model] = nil
	local handled = false
	humanoid.Died:Connect(function()
		if handled then return end
		handled = true
		local victimPlayer = Players:GetPlayerFromCharacter(model)
		local matchId = if victimPlayer then victimPlayer:GetAttribute("MatchId") else model:GetAttribute("MatchId")
		local match = MatchManager.GetMatchById(matchId :: string?)
		local log = damageLog[model] or {}
		damageLog[model] = nil
		if not match then return end

		local t = os.clock()
		local killer: Player? = nil
		local latest = -math.huge
		local assisters = {}
		for attacker, entry in pairs(log) do
			if attacker.Parent == Players and t - entry.Time <= CombatConfig.AssistWindow then
				table.insert(assisters, attacker)
				if entry.Time > latest then latest = entry.Time; killer = attacker end
			end
		end
		local entry = killer and log[killer]
		local victimName = if victimPlayer then victimPlayer.DisplayName else (model:GetAttribute("DisplayName") or model.Name)
		MatchManager.RecordElimination(match, killer, victimPlayer, victimName :: string, assisters, entry and entry.Weapon or nil, entry and entry.Headshot or false)
	end)
end

---------------------------------------------------------------- reload
local function startReload(player: Player)
	local st = states[player]
	if not st or st.Reloading then return end
	local w = WeaponConfig.Weapons[st.WeaponId]
	if not w or w.MagSize <= 0 or st.Ammo >= w.MagSize then return end
	st.Reloading = true
	st.ReloadToken += 1
	local token = st.ReloadToken
	setAmmoAttrs(player, st)
	task.delay(w.ReloadTime, function()
		if states[player] == st and st.ReloadToken == token and st.Reloading then
			st.Ammo = w.MagSize
			st.Reloading = false
			setAmmoAttrs(player, st)
		end
	end)
end

---------------------------------------------------------------- fire validation
local function canFire(player: Player, st: WeaponState, w: any): boolean
	if st.Reloading then return false end
	if w.MagSize > 0 and st.Ammo <= 0 then return false end
	local rate = math.max(mods(player).FireRateMult, 0.1)
	local cooldown = w.Cooldown / rate
	local t = os.clock()
	-- hard cap: shots in the last second
	local recent = st.ShotTimes
	while #recent > 0 and t - recent[1] > 1 do table.remove(recent, 1) end
	if #recent >= CombatConfig.MaxShotsPerSecond then return false end

	local since = t - st.LastShot
	local tol = CombatConfig.CooldownTolerance
	if w.FireMode == "Burst" then
		if since >= cooldown * tol then
			st.BurstCount = 1
		elseif st.BurstCount < w.BurstCount and since >= w.BurstInterval * 0.5 then
			st.BurstCount += 1
		else
			return false
		end
	elseif since < cooldown * tol then
		return false
	end
	st.LastShot = t
	table.insert(recent, t)
	return true
end

local function validRay(origin: any, direction: any, head: BasePart): boolean
	if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then return false end
	if origin ~= origin or direction ~= direction then return false end -- NaN
	local mag = direction.Magnitude
	if mag < 0.95 or mag > 1.05 then return false end
	return (origin - head.Position).Magnitude <= CombatConfig.OriginTolerance
end

---------------------------------------------------------------- hitscan
local function doHitscan(player: Player, character: Model, w: any, origin: Vector3, dir: Vector3, claimedPart: any, matchId: string)
	local params = geometryParams(shotExclusions(player, character))
	local endPoint = origin + dir * w.Range
	local hitPart: BasePart? = nil
	local target: Combatant? = nil

	-- 1) The client's claim (favours the shooter, but every claim is checked)
	if typeof(claimedPart) == "Instance" and claimedPart:IsA("BasePart") and claimedPart:IsDescendantOf(workspace) then
		local c = CombatService.GetCombatant(claimedPart)
		if c and CombatService.IsEnemy(player, c) and c.Humanoid.Health > 0 then
			local toTarget = claimedPart.Position - origin
			local along = toTarget:Dot(dir)
			local perp = (toTarget - dir * along).Magnitude
			if along > 0 and along <= w.Range + 4 and perp <= CombatConfig.HitTolerance then
				-- line of sight: nothing solid between origin and the target (characters excluded)
				local losParams = geometryParams(shotExclusions(player, character, { c.Model }))
				local block = workspace:Raycast(origin, toTarget, losParams)
				if not block or (block.Position - origin).Magnitude >= toTarget.Magnitude - 1.5 then
					hitPart = claimedPart
					target = c
					endPoint = origin + dir * along
				end
			end
		end
	end

	-- 2) Otherwise the server's own ray decides
	if not target then
		local result = workspace:Raycast(origin, dir * w.Range, params)
		if result and isEnemyShield(player, result.Instance) then
			CombatService.DamageShield(player, result.Instance :: BasePart, w.Damage * mods(player).DamageMult)
			matchPlayersFx(matchId, { Type = "Shot", Shooter = player.UserId, Weapon = w.Id, From = origin, To = result.Position })
			return
		end
		if result then
			endPoint = result.Position
			local c = CombatService.GetCombatant(result.Instance)
			if c and CombatService.IsEnemy(player, c) and c.Humanoid.Health > 0 then
				hitPart = result.Instance :: BasePart
				target = c
			end
		end
	end

	if target and hitPart then
		local headshot = isHeadPart(hitPart) and w.HeadshotMultiplier > 1
		local dmg = w.Damage * (headshot and w.HeadshotMultiplier or 1) * mods(player).DamageMult
		CombatService.ApplyDamage(player, target, dmg, w.DisplayName, headshot)
	end
	matchPlayersFx(matchId, { Type = "Shot", Shooter = player.UserId, Weapon = w.Id, From = origin, To = endPoint })
end

---------------------------------------------------------------- melee
local function doMelee(player: Player, character: Model, w: any, dir: Vector3, matchId: string)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local match = MatchManager.GetMatchById(matchId)
	if not root or not match then return end
	local flatDir = Vector3.new(dir.X, 0, dir.Z)
	flatDir = if flatDir.Magnitude > 0.05 then flatDir.Unit else root.CFrame.LookVector
	local best: Combatant? = nil
	local bestDist = math.huge
	for _, c in ipairs(CombatService.GetCombatantsInMatch(match)) do
		if CombatService.IsEnemy(player, c) and c.Humanoid.Health > 0 then
			local troot = c.Model:FindFirstChild("HumanoidRootPart") :: BasePart?
			if troot then
				local offset = troot.Position - root.Position
				local dist = offset.Magnitude
				local flat = Vector3.new(offset.X, 0, offset.Z)
				if dist <= w.Range and math.abs(offset.Y) < 6 and (flat.Magnitude < 1 or flat.Unit:Dot(flatDir) >= w.ConeDot) and dist < bestDist then
					local block = workspace:Raycast(root.Position, offset, geometryParams({ character, c.Model }))
					if not block then best = c; bestDist = dist end
				end
			end
		end
	end
	if best then
		CombatService.ApplyDamage(player, best, w.Damage * mods(player).DamageMult, w.DisplayName, false)
	end
	matchPlayersFx(matchId, { Type = "Melee", Shooter = player.UserId, Weapon = w.Id, From = root.Position, Dir = flatDir })
end

---------------------------------------------------------------- projectiles
local function explode(proj: Projectile, pos: Vector3, direct: Combatant?)
	local w = proj.Weapon
	local mult = mods(proj.Shooter).DamageMult
	if direct and CombatService.IsEnemy(proj.Shooter, direct) then
		CombatService.ApplyDamage(proj.Shooter, direct, w.Damage * mult, w.DisplayName, false)
	end
	if w.SplashRadius and w.SplashRadius > 0 and w.SplashDamage > 0 then
		local match = MatchManager.GetMatchById(proj.MatchId)
		if match then
			for _, c in ipairs(CombatService.GetCombatantsInMatch(match)) do
				if c ~= direct and (not direct or c.Model ~= direct.Model) and CombatService.IsEnemy(proj.Shooter, c) then
					local troot = c.Model:FindFirstChild("HumanoidRootPart") :: BasePart?
					if troot then
						local d = (troot.Position - pos).Magnitude
						if d <= w.SplashRadius then
							local falloff = 1 - 0.5 * (d / w.SplashRadius) -- 100% at centre, 50% at edge
							CombatService.ApplyDamage(proj.Shooter, c, w.SplashDamage * falloff * mult, w.DisplayName, false)
						end
					end
				end
			end
		end
	end
	matchPlayersFx(proj.MatchId, { Type = "Impact", Id = proj.Id, Weapon = w.Id, Position = pos, Radius = w.SplashRadius or 0 })
end

local function spawnProjectile(player: Player, character: Model, w: any, origin: Vector3, dir: Vector3, matchId: string)
	projectileId += 1
	local proj: Projectile = {
		Id = projectileId, Shooter = player, Weapon = w, Pos = origin, Vel = dir * w.ProjectileSpeed,
		Travelled = 0, Ignore = { character }, MatchId = matchId,
	}
	table.insert(projectiles, proj)
	matchPlayersFx(matchId, { Type = "Projectile", Id = proj.Id, Shooter = player.UserId, Weapon = w.Id, From = origin, Velocity = proj.Vel })
end

local function stepProjectiles(dt: number)
	for i = #projectiles, 1, -1 do
		local proj = projectiles[i]
		local step = proj.Vel * dt
		local remove = false
		local params = geometryParams(shotExclusions(proj.Shooter, proj.Ignore[1] :: Model, proj.Ignore))
		local result = workspace:Raycast(proj.Pos, step, params)
		if result and isEnemyShield(proj.Shooter, result.Instance) then
			CombatService.DamageShield(proj.Shooter, result.Instance :: BasePart, proj.Weapon.Damage * mods(proj.Shooter).DamageMult)
			matchPlayersFx(proj.MatchId, { Type = "Impact", Id = proj.Id, Weapon = proj.Weapon.Id, Position = result.Position, Radius = 0 })
			table.remove(projectiles, i)
			continue
		end
		if result then
			local c = CombatService.GetCombatant(result.Instance)
			if c and not CombatService.IsEnemy(proj.Shooter, c) then
				-- passes through teammates and the shooter
				table.insert(proj.Ignore, c.Model)
			else
				explode(proj, result.Position, c)
				remove = true
			end
		end
		if not remove then
			proj.Pos += step
			proj.Travelled += step.Magnitude
			if proj.Travelled >= proj.Weapon.Range or proj.Shooter.Parent ~= Players or not MatchManager.GetMatchById(proj.MatchId) then
				if proj.Shooter.Parent == Players and MatchManager.GetMatchById(proj.MatchId) then
					matchPlayersFx(proj.MatchId, { Type = "Impact", Id = proj.Id, Weapon = proj.Weapon.Id, Position = proj.Pos, Radius = 0 })
				end
				remove = true
			end
		end
		if remove then table.remove(projectiles, i) end
	end
end

---------------------------------------------------------------- remote handlers
local function onFire(player: Player, origin: any, direction: any, claimedPart: any)
	if player:GetAttribute("CombatEnabled") ~= true then return end
	local matchId = player:GetAttribute("MatchId")
	local match = MatchManager.GetMatchById(matchId :: string?)
	if not match or match.State ~= "Live" then return end
	local character = player.Character
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	local head = character and character:FindFirstChild("Head") :: BasePart?
	if not character or not hum or hum.Health <= 0 or not head then return end
	local st = states[player]
	if not st then return end
	local w = WeaponConfig.Weapons[st.WeaponId]
	if not w then return end
	if not validRay(origin, direction, head) then return end
	if not canFire(player, st, w) then return end
	local dir = (direction :: Vector3).Unit

	if w.MagSize > 0 then
		st.Ammo -= 1
		setAmmoAttrs(player, st)
	end
	-- attacking ends your own spawn protection (and Shade's cloak, via the OnAttack hook)
	local ff = character:FindFirstChildOfClass("ForceField")
	if ff then ff:Destroy() end
	for _, fn in ipairs(attackListeners) do task.spawn(fn, player) end

	if w.Type == "Hitscan" then
		doHitscan(player, character, w, origin, dir, claimedPart, matchId :: string)
	elseif w.Type == "Projectile" then
		spawnProjectile(player, character, w, origin, dir, matchId :: string)
	elseif w.Type == "Melee" then
		doMelee(player, character, w, dir, matchId :: string)
	end

	if w.MagSize > 0 and st.Ammo <= 0 then startReload(player) end
end

function CombatService.Init()
	FireRemote.OnServerEvent:Connect(onFire)
	ReloadRemote.OnServerEvent:Connect(function(player)
		if player:GetAttribute("MatchId") then startReload(player) end
	end)

	CharacterService.OnSpawned(function(player, character, inMatch)
		local hum = character:FindFirstChildOfClass("Humanoid")
		if hum then CombatService.WatchDeath(character, hum) end
		if inMatch then
			local weaponId = player:GetAttribute("WeaponId") :: string
			local w = WeaponConfig.Weapons[weaponId]
			if w then
				local st: WeaponState = { WeaponId = weaponId, Ammo = w.MagSize, Reloading = false, ReloadToken = 0, LastShot = 0, BurstCount = 0, ShotTimes = {} }
				states[player] = st
				setAmmoAttrs(player, st)
			end
		else
			states[player] = nil
			player:SetAttribute("Ammo", nil)
			player:SetAttribute("Reloading", nil)
		end
	end)

	Players.PlayerRemoving:Connect(function(p)
		states[p] = nil
		for _, log in pairs(damageLog) do log[p] = nil end
	end)

	RunService.Heartbeat:Connect(stepProjectiles)
end

return CombatService
