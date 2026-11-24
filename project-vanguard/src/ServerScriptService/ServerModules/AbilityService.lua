--!strict
-- AbilityService: server authority for Dash (Shift), Skill (E) and Ultimate (Q).
--  * Cooldowns and ultimate charge live ONLY here; the client just asks "use slot X, aiming here".
--  * Ultimate charge: damage dealt + healing done + a slow passive trickle. No charge while an ult is active.
--  * Each hero's ability logic is a module in AbilityModules; balance numbers come from HeroConfig.
--  * Shared helpers (damage, heal, slow, knockback, buffs, reveal, zones, aim point) are passed to modules as `ctx`.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local HeroConfig = require(ReplicatedStorage.Modules.HeroConfig)
local MatchManager = require(script.Parent.MatchManager)
local CombatService = require(script.Parent.CombatService)
local CharacterService = require(script.Parent.CharacterService)

local Remotes = ReplicatedStorage.Remotes
local UseAbility = Remotes.UseAbility :: RemoteEvent
local AbilityFx = Remotes.AbilityFx :: RemoteEvent
local RevealRemote = Remotes.Reveal :: RemoteEvent
local KnockbackRemote = Remotes.Knockback :: RemoteEvent
local HitConfirm = Remotes.HitConfirm :: RemoteEvent

local AbilityService = {}

type Buff = { DamageMult: number?, FireRateMult: number?, SpeedAdd: number?, Expires: number }
type State = {
	MatchId: string?,
	Ready: { [string]: number },
	Charge: number,
	UltActive: boolean,
	Buffs: { [string]: Buff },
	LastUse: number,
}

local states: { [Player]: State } = {}
local slows: { [Humanoid]: { [string]: { Mult: number, Expires: number } } } = {}
local modules: { [string]: any } = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function getState(p: Player): State
	local st = states[p]
	if not st then
		st = { MatchId = nil, Ready = { Dash = 0, Skill = 0 }, Charge = 0, UltActive = false, Buffs = {}, LastUse = 0 }
		states[p] = st
	end
	return st
end

local function heroOf(p: Player)
	return HeroConfig.Heroes[CharacterService.GetHeroId(p)]
end

local function chargeMax(p: Player): number
	return heroOf(p).Abilities.Ultimate.Charge
end

local function publish(p: Player)
	local st = getState(p)
	p:SetAttribute("Ready_Dash", st.Ready.Dash)
	p:SetAttribute("Ready_Skill", st.Ready.Skill)
	p:SetAttribute("UltCharge", math.clamp(st.Charge / chargeMax(p), 0, 1))
	p:SetAttribute("UltActive", st.UltActive)
	local m = AbilityService.GetModifiers(p)
	p:SetAttribute("FireRateMult", m.FireRateMult)
end

local function addCharge(p: Player, amount: number)
	local st = getState(p)
	if st.UltActive or amount <= 0 then return end
	local match = MatchManager.GetMatch(p)
	if not match or match.State ~= "Live" then return end
	if GameConfig.IsStudio and GameConfig.StudioSoloTesting and GameConfig.Abilities.StudioFastUlt then amount *= 10 end
	st.Charge = math.min(chargeMax(p), st.Charge + amount)
	p:SetAttribute("UltCharge", st.Charge / chargeMax(p))
end

---------------------------------------------------------------- modifiers / speed
function AbilityService.GetModifiers(p: Player): { DamageMult: number, FireRateMult: number }
	local st = states[p]
	local dmg, rate = 1, 1
	if st then
		local t = now()
		for _, b in pairs(st.Buffs) do
			if b.Expires > t then
				dmg *= b.DamageMult or 1
				rate *= b.FireRateMult or 1
			end
		end
	end
	return { DamageMult = dmg, FireRateMult = rate }
end

local function recomputeSpeed(hum: Humanoid)
	if hum.Health <= 0 then return end
	local base = hum:GetAttribute("BaseWalkSpeed") :: number?
	if not base then
		base = hum.WalkSpeed
		hum:SetAttribute("BaseWalkSpeed", base)
	end
	local t = now()
	local add = 0
	local p = Players:GetPlayerFromCharacter(hum.Parent)
	if p and states[p] then
		for _, b in pairs(states[p].Buffs) do
			if b.Expires > t then add += b.SpeedAdd or 0 end
		end
	end
	local mult = 1
	local list = slows[hum]
	if list then
		for id, s in pairs(list) do
			if s.Expires > t then mult = math.min(mult, s.Mult) else list[id] = nil end
		end
		if next(list) == nil then slows[hum] = nil end -- audit fix: don't keep dead humanoids referenced
	end
	hum.WalkSpeed = ((base :: number) + add) * mult
end

---------------------------------------------------------------- ctx: helpers handed to hero modules
local ctx = {}
AbilityService.Ctx = ctx
ctx.Config = GameConfig
ctx.Now = now

function ctx.GetMatch(p: Player)
	return MatchManager.GetMatch(p)
end

function ctx.Root(p: Player): BasePart?
	local c = p.Character
	return c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- living enemies of p in its match (players + Studio dummies)
function ctx.Enemies(p: Player)
	local match = MatchManager.GetMatch(p)
	if not match then return {} end
	local out = {}
	for _, c in ipairs(CombatService.GetCombatantsInMatch(match)) do
		if c.Humanoid.Health > 0 and CombatService.IsEnemy(p, c) then table.insert(out, c) end
	end
	return out
end

-- living allies of p, including p
function ctx.Allies(p: Player)
	local match = MatchManager.GetMatch(p)
	if not match then return {} end
	local out = {}
	for _, c in ipairs(CombatService.GetCombatantsInMatch(match)) do
		if c.Humanoid.Health > 0 and (c.Player == p or (c.Team ~= nil and c.Team == p:GetAttribute("Team"))) then table.insert(out, c) end
	end
	return out
end

function ctx.Within(list: { any }, center: Vector3, radius: number, maxHeight: number?): { any }
	local out = {}
	for _, c in ipairs(list) do
		local r = c.Model:FindFirstChild("HumanoidRootPart") :: BasePart?
		if r then
			local d = r.Position - center
			if Vector3.new(d.X, 0, d.Z).Magnitude <= radius and math.abs(d.Y) <= (maxHeight or radius) then
				table.insert(out, c)
			end
		end
	end
	return out
end

function ctx.Damage(p: Player, target: any, amount: number, abilityName: string)
	CombatService.ApplyDamage(p, target, amount, abilityName, false)
end

function ctx.Heal(p: Player, target: any, amount: number): number
	local hum = target.Humanoid :: Humanoid
	if hum.Health <= 0 then return 0 end
	local before = hum.Health
	hum.Health = math.min(hum.MaxHealth, before + amount)
	local healed = hum.Health - before
	if healed > 0 then
		addCharge(p, healed * GameConfig.Abilities.ChargePerHeal)
		HitConfirm:FireClient(p, { Damage = math.floor(healed + 0.5), Heal = true })
	end
	return healed
end

function ctx.Knockback(target: any, velocity: Vector3)
	if target.Player then
		KnockbackRemote:FireClient(target.Player, velocity) -- players own their character physics
	else
		local r = target.Model:FindFirstChild("HumanoidRootPart") :: BasePart?
		if r then r.AssemblyLinearVelocity = velocity end
	end
end

function ctx.Slow(target: any, id: string, mult: number, duration: number)
	local hum = target.Humanoid :: Humanoid
	if not slows[hum] then
		hum.Destroying:Connect(function() slows[hum] = nil end)
	end
	slows[hum] = slows[hum] or {}
	slows[hum][id] = { Mult = mult, Expires = now() + duration }
	recomputeSpeed(hum)
	task.delay(duration + 0.05, function()
		if hum.Parent then recomputeSpeed(hum) end
	end)
end

function ctx.AddBuff(p: Player, id: string, buff: { [string]: any }, duration: number)
	local st = getState(p)
	st.Buffs[id] = { DamageMult = buff.DamageMult, FireRateMult = buff.FireRateMult, SpeedAdd = buff.SpeedAdd, Expires = now() + duration }
	local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
	if hum then recomputeSpeed(hum) end
	publish(p)
	task.delay(duration + 0.05, function()
		local b = st.Buffs[id]
		if b and b.Expires <= now() then st.Buffs[id] = nil end
		local h = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
		if h then recomputeSpeed(h) end
		if p.Parent then publish(p) end
	end)
end

-- Ultimate "active" window: blocks charge gain and shows a hero-coloured glow on the character
function ctx.SetUltActive(p: Player, duration: number)
	local st = getState(p)
	st.UltActive = true
	publish(p)
	local char = p.Character
	local glow: Highlight? = nil
	if char then
		glow = Instance.new("Highlight")
		glow.Name = "UltGlow"
		glow.FillColor = heroOf(p).Color
		glow.FillTransparency = 0.75
		glow.OutlineColor = heroOf(p).Color
		glow.DepthMode = Enum.HighlightDepthMode.Occluded
		glow.Parent = char
	end
	task.delay(duration, function()
		st.UltActive = false
		if glow then glow:Destroy() end
		if p.Parent then publish(p) end
	end)
end

-- Reveal enemy models to p's whole team (Vex's Sensor Trap). Clients draw a local Highlight.
function ctx.Reveal(p: Player, models: { Model }, duration: number)
	local match = MatchManager.GetMatch(p)
	if not match or #models == 0 then return end
	local team = p:GetAttribute("Team")
	for _, mate in ipairs(match.Players) do
		if mate == p or (team and mate:GetAttribute("Team") == team) then
			RevealRemote:FireClient(mate, models, duration)
		end
	end
end

function ctx.Fx(p: Player, payload: { [string]: any })
	local match = MatchManager.GetMatch(p)
	if not match then return end
	payload.Owner = p.UserId
	payload.Hero = CharacterService.GetHeroId(p)
	for _, mate in ipairs(match.Players) do
		AbilityFx:FireClient(mate, payload)
	end
end

-- Folder inside the match map for ability objects (cleaned up automatically when the map unloads)
function ctx.ObjectFolder(p: Player): Instance?
	local match = MatchManager.GetMatch(p)
	if not match or not match.Map then return nil end
	local f = match.Map:FindFirstChild("AbilityObjects")
	if not f then
		f = Instance.new("Folder")
		f.Name = "AbilityObjects"
		f.Parent = match.Map
	end
	return f
end

function ctx.GeometryParams(p: Player): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local list: { Instance } = {}
	local match = MatchManager.GetMatch(p)
	if match then
		for _, c in ipairs(CombatService.GetCombatantsInMatch(match)) do table.insert(list, c.Model) end
		local objs = match.Map and match.Map:FindFirstChild("AbilityObjects")
		if objs then table.insert(list, objs) end
	end
	if p.Character then table.insert(list, p.Character) end
	params.FilterDescendantsInstances = list
	return params
end

-- Server-side aim point: ray from the head along the (validated) aim direction, dropped to the ground.
function ctx.AimPoint(p: Player, dir: Vector3, range: number): Vector3?
	local head = p.Character and p.Character:FindFirstChild("Head") :: BasePart?
	if not head then return nil end
	local params = ctx.GeometryParams(p)
	local hit = workspace:Raycast(head.Position, dir * range, params)
	local point = hit and (hit.Position + hit.Normal * 0.5) or (head.Position + dir * range)
	local down = workspace:Raycast(point + Vector3.new(0, 2, 0), Vector3.new(0, -80, 0), params)
	if down then return down.Position end
	return nil -- nothing to stand on (e.g. aiming into the void on Skyline Core)
end

-- Repeating area effect (Arc Field, Storm Core, Sanctuary). tick(dt) runs every `interval` for `duration`.
function ctx.RunZone(duration: number, interval: number, tick: (number) -> (), alive: () -> boolean)
	task.spawn(function()
		local elapsed = 0
		while elapsed < duration and alive() do
			tick(interval)
			task.wait(interval)
			elapsed += interval
		end
	end)
end

function ctx.ZonePart(p: Player, name: string, center: Vector3, radius: number, color: Color3): Part?
	local folder = ctx.ObjectFolder(p)
	if not folder then return nil end
	local zone = Instance.new("Part")
	zone.Name = name
	zone.Shape = Enum.PartType.Cylinder
	zone.Size = Vector3.new(0.4, radius * 2, radius * 2)
	zone.CFrame = CFrame.new(center + Vector3.new(0, 0.25, 0)) * CFrame.Angles(0, 0, math.rad(90))
	zone.Anchored = true; zone.CanCollide = false; zone.CanQuery = false; zone.CanTouch = false
	zone.Material = Enum.Material.Neon
	zone.Color = color
	zone.Transparency = 0.55
	zone.Parent = folder
	local dome = Instance.new("Part")
	dome.Name = name .. "Dome"
	dome.Shape = Enum.PartType.Ball
	dome.Size = Vector3.one * radius * 2
	dome.CFrame = CFrame.new(center)
	dome.Anchored = true; dome.CanCollide = false; dome.CanQuery = false; dome.CanTouch = false
	dome.Material = Enum.Material.ForceField
	dome.Color = color
	dome.Transparency = 0.2
	dome.Parent = zone
	local light = Instance.new("PointLight")
	light.Color = color; light.Range = radius * 1.5; light.Brightness = 2
	light.Parent = zone
	return zone
end

---------------------------------------------------------------- cloak (used by Shade; broken by attacking)
local cloaked: { [Player]: { [Instance]: number } } = {}

function ctx.SetCloak(p: Player, transparency: number, duration: number)
	local char = p.Character
	if not char then return end
	local saved: { [Instance]: number } = {}
	for _, d in ipairs(char:GetDescendants()) do
		if (d:IsA("BasePart") and d.Name ~= "HumanoidRootPart") or d:IsA("Decal") then
			local item: any = d
			saved[d] = item.Transparency
			item.Transparency = math.max(item.Transparency, transparency)
		end
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None end
	cloaked[p] = saved
	p:SetAttribute("Cloaked", true)
	task.delay(duration, function() AbilityService.BreakCloak(p) end)
end

function AbilityService.BreakCloak(p: Player)
	local saved = cloaked[p]
	if not saved then return end
	cloaked[p] = nil
	for inst, t in pairs(saved) do
		if inst.Parent then (inst :: any).Transparency = t end
	end
	local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
	if hum then hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer end
	p:SetAttribute("Cloaked", false)
end

---------------------------------------------------------------- the remote
local VALID_SLOTS = { Dash = true, Skill = true, Ultimate = true }

local function onUse(p: Player, slot: any, aimDir: any)
	if typeof(slot) ~= "string" or not VALID_SLOTS[slot] then return end
	if typeof(aimDir) ~= "Vector3" or aimDir ~= aimDir then return end
	local mag = aimDir.Magnitude
	if mag < 0.9 or mag > 1.1 then return end
	if p:GetAttribute("CombatEnabled") ~= true then return end
	local match = MatchManager.GetMatch(p)
	if not match or match.State ~= "Live" then return end
	local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return end

	local st = getState(p)
	local t = now()
	if t - st.LastUse < 0.15 then return end -- spam guard
	local heroId = CharacterService.GetHeroId(p)
	local cfg = HeroConfig.Heroes[heroId].Abilities[slot]
	local mod = modules[heroId]
	local fn = mod and mod[slot]
	if not cfg or not fn then return end

	if slot == "Ultimate" then
		if st.Charge < cfg.Charge or st.UltActive then return end -- no free ultimates
	elseif t < (st.Ready[slot] or 0) - 0.1 then
		return -- still on cooldown (0.1s grace for latency)
	end

	st.LastUse = t
	local ok = fn(ctx, p, cfg, { Dir = (aimDir :: Vector3).Unit })
	if ok == false then return end -- e.g. no valid ground to place a field: no cooldown spent

	if slot == "Ultimate" then
		st.Charge = 0
		ctx.Fx(p, { Type = "UltCast", Name = cfg.Name, Player = p.DisplayName })
	else
		st.Ready[slot] = t + cfg.Cooldown
	end
	publish(p)
end

function AbilityService.Init()
	for _, heroId in ipairs(HeroConfig.HeroOrder) do
		local m = script.Parent.AbilityModules:FindFirstChild(heroId)
		if m then modules[heroId] = require(m) else warn("[AbilityService] Missing ability module for", heroId) end
	end

	CombatService.SetModifierProvider(AbilityService.GetModifiers)
	CombatService.OnAttack(function(p) AbilityService.BreakCloak(p) end)
	CombatService.OnDamageDealt(function(p, _target, dealt)
		addCharge(p, dealt * GameConfig.Abilities.ChargePerDamage)
	end)

	CharacterService.OnSpawned(function(p, character, inMatch)
		local st = getState(p)
		local matchId = p:GetAttribute("MatchId") :: string?
		if not inMatch or st.MatchId ~= matchId then
			-- new match (or back in lobby): fresh cooldowns and empty ultimate
			st.MatchId = matchId
			st.Ready = { Dash = 0, Skill = 0 }
			st.Charge = 0
		end
		st.Buffs = {}
		st.UltActive = false
		cloaked[p] = nil
		p:SetAttribute("Cloaked", false)
		local hum = character:FindFirstChildOfClass("Humanoid")
		if hum then hum:SetAttribute("BaseWalkSpeed", hum.WalkSpeed) end
		publish(p)
	end)

	UseAbility.OnServerEvent:Connect(onUse)
	Players.PlayerRemoving:Connect(function(p)
		states[p] = nil
		cloaked[p] = nil
	end)

	-- passive ult charge
	task.spawn(function()
		while true do
			task.wait(1)
			for _, p in ipairs(Players:GetPlayers()) do
				local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
				if hum and hum.Health > 0 and p:GetAttribute("CombatEnabled") == true then
					addCharge(p, GameConfig.Abilities.UltPassivePerSecond)
				end
			end
		end
	end)
end

return AbilityService
