--!strict
-- BotService (Phase 9): server-run bots that play the real heroes.
--  * Used to fill Casual matches (GameConfig.Bots.CasualFillTo) and for 1v1 Practice. Never in Ranked/Duel.
--  * Each bot is a record in match.Bots (created by MatchManager) + a hero character model in
--    match.Map.Bots. They wear the hero look + weapon (CharacterService.DressAsHero), use the same weapon
--    numbers, raycasts, shields, projectiles and kill credit as players (CombatService.BotAttack), and hold /
--    contest the core (ObjectiveService counts them).
--  * Brain (every Bots.ThinkRate): pick the nearest visible enemy -> wait the reaction time -> aim with the
--    difficulty's aim error (leading projectiles), burst/auto/semi fire, reload. Move with pathfinding to the
--    core (or the enemy in 1v1), strafe while fighting, jump when stuck.
--  * Difficulty presets live in GameConfig.Bots.Presets ("Easy" / "Normal" / "Hard").
--  * Bot physics are owned by the server (SetNetworkOwner(nil)) so no client can move them.
--  * Bot kills/deaths show in the kill feed and results, but never count for leaderboards or MVP.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local HeroConfig = require(ReplicatedStorage.Modules.HeroConfig)
local WeaponConfig = require(ReplicatedStorage.Modules.WeaponConfig)
local MatchManager = require(script.Parent.MatchManager)
local MapService = require(script.Parent.MapService)
local SpawnService = require(script.Parent.SpawnService)
local CombatService = require(script.Parent.CombatService)
local CharacterService = require(script.Parent.CharacterService)

local Cfg = GameConfig.Bots

-- Roblox's default R15 movement animations (so bots don't slide around in a T-pose)
local ANIMS = {
	Idle = "rbxassetid://507766388",
	Walk = "rbxassetid://507777826",
	Run = "rbxassetid://913376220",
	Jump = "rbxassetid://507765000",
	Fall = "rbxassetid://507767968",
}

local BotService = {}

type Brain = {
	Bot: any,
	Match: any,
	Model: Model,
	Hum: Humanoid,
	Root: BasePart,
	Head: BasePart,
	Weapon: any,
	Ammo: number,
	ReloadUntil: number,
	NextShot: number,
	Target: any?,
	TargetSince: number,
	Waypoints: { PathWaypoint },
	WpIndex: number,
	PathGoal: Vector3?,
	NextPath: number,
	Pathing: boolean,
	StrafeSign: number,
	NextStrafeFlip: number,
	LastPos: Vector3,
	LastMoveCheck: number,
	CorePoint: Vector3?,
	Tracks: { [string]: AnimationTrack },
}

local brains: { Brain } = {}

local function preset(): any
	return Cfg.Presets[Cfg.Difficulty] or Cfg.Presets.Normal
end

---------------------------------------------------------------- helpers
local function corePosition(match: any): Vector3?
	local obj = match.Map and match.Map:FindFirstChild("Objective", true)
	if obj and obj:IsA("BasePart") then return obj.Position end
	return nil
end

local function randomCorePoint(match: any): Vector3?
	local obj = match.Map and match.Map:FindFirstChild("Objective", true)
	if not obj or not obj:IsA("BasePart") then return nil end
	local c = obj.Position
	local r = math.max(obj.Size.X, obj.Size.Z) / 2
	local a = math.random() * math.pi * 2
	local d = math.random() * r * 0.55
	return c + Vector3.new(math.cos(a) * d, 0, math.sin(a) * d)
end

-- random direction inside a cone of `deg` degrees around dir
local function spread(dir: Vector3, deg: number): Vector3
	if deg <= 0 then return dir end
	local cf = CFrame.lookAt(Vector3.zero, dir)
	local angle = math.rad(deg) * math.sqrt(math.random())
	local roll = math.random() * math.pi * 2
	return (cf * CFrame.Angles(0, 0, roll) * CFrame.Angles(angle, 0, 0)).LookVector
end

local function visible(brain: Brain, target: any): boolean
	local troot = target.Model:FindFirstChild("Head") or target.Model:FindFirstChild("HumanoidRootPart")
	if not troot then return false end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { brain.Model, target.Model }
	params.IgnoreWater = true
	local origin = brain.Head.Position
	local hit = workspace:Raycast(origin, (troot :: BasePart).Position - origin, params)
	return hit == nil
end

local function playMoveAnim(brain: Brain, name: string)
	for n, t in pairs(brain.Tracks) do
		if n == name then
			if not t.IsPlaying then t:Play(0.15) end
		elseif t.IsPlaying and n ~= "Jump" then
			t:Stop(0.15)
		end
	end
end

---------------------------------------------------------------- spawning
local spawnBot: (any, any) -> ()

local function onBotDied(match: any, bot: any, model: Model)
	bot.Alive = false
	for i = #brains, 1, -1 do
		if brains[i].Model == model then table.remove(brains, i) end
	end
	task.delay(3, function() if model.Parent then model:Destroy() end end)
	local respawn = GameConfig.Modes[match.Mode].RespawnTime
	task.delay(respawn, function()
		if match.State == "Live" and MatchManager.GetMatchById(match.Id) == match then
			spawnBot(match, bot)
		end
	end)
end

function spawnBot(match: any, bot: any)
	local folder = match.Map and match.Map:FindFirstChild("Bots")
	if not folder then return end
	local hero = HeroConfig.Heroes[bot.HeroId]
	local w = hero and WeaponConfig.Weapons[hero.WeaponId]
	if not hero or not w then return end

	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15)
	end)
	if not ok or not model then warn("[BotService] could not build bot model") return end
	model.Name = bot.Name
	model:SetAttribute("IsBot", true)
	model:SetAttribute("Team", bot.Team)
	model:SetAttribute("MatchId", match.Id)
	model:SetAttribute("DisplayName", bot.Name)
	model:SetAttribute("Hero", bot.HeroId)
	local hum = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	hum.DisplayName = bot.Name
	hum.MaxHealth = hero.Stats.Health
	hum.Health = hero.Stats.Health
	hum.WalkSpeed = hero.Stats.WalkSpeed
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.DisplayWhenDamaged
	hum.BreakJointsOnDeath = true
	CharacterService.DressAsHero(model, bot.HeroId)

	local group = GameConfig.Modes[match.Mode].TeamBased and bot.Team or "FFA"
	local markers = MapService.GetSpawnPoints(match.Map, group)
	model.Parent = folder
	SpawnService.PlaceAtRandom(model, markers)
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	local head = model:FindFirstChild("Head") :: BasePart
	pcall(function() root:SetNetworkOwner(nil) end) -- server owns bot physics
	if match.State == "PreMatch" then root.Anchored = true end

	local ff = Instance.new("ForceField")
	ff.Visible = true
	ff.Parent = model
	task.delay(GameConfig.Combat.SpawnProtection, function() if ff.Parent then ff:Destroy() end end)

	bot.Model = model
	bot.Alive = true
	CombatService.WatchDeath(model, hum)
	hum.Died:Connect(function() onBotDied(match, bot, model) end)

	-- movement animations
	local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = hum
	local tracks = {}
	for name, id in pairs(ANIMS) do
		local a = Instance.new("Animation")
		a.AnimationId = id
		local okT, track = pcall(function() return animator:LoadAnimation(a) end)
		if okT and track then
			track.Priority = Enum.AnimationPriority.Core
			track.Looped = name ~= "Jump"
			tracks[name] = track
		end
	end

	local brain: Brain = {
		Bot = bot, Match = match, Model = model, Hum = hum, Root = root, Head = head, Weapon = w,
		Ammo = w.MagSize, ReloadUntil = 0, NextShot = 0, Target = nil, TargetSince = 0,
		Waypoints = {}, WpIndex = 1, PathGoal = nil, NextPath = 0, Pathing = false,
		StrafeSign = 1, NextStrafeFlip = 0, LastPos = root.Position, LastMoveCheck = os.clock(),
		CorePoint = randomCorePoint(match), Tracks = tracks,
	}
	table.insert(brains, brain)
	hum.Running:Connect(function(speed)
		playMoveAnim(brain, speed > 12 and "Run" or (speed > 0.5 and "Walk" or "Idle"))
	end)
	hum.StateChanged:Connect(function(_, new)
		if new == Enum.HumanoidStateType.Jumping and tracks.Jump then tracks.Jump:Play(0.1)
		elseif new == Enum.HumanoidStateType.Freefall then playMoveAnim(brain, "Fall") end
	end)
	playMoveAnim(brain, "Idle")
end

---------------------------------------------------------------- brain
local function computePath(brain: Brain, goal: Vector3)
	if brain.Pathing then return end
	brain.Pathing = true
	brain.NextPath = os.clock() + 1.5
	task.spawn(function()
		local path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = true, WaypointSpacing = 6 })
		local ok = pcall(function() path:ComputeAsync(brain.Root.Position, goal) end)
		brain.Pathing = false
		if ok and path.Status == Enum.PathStatus.Success then
			brain.Waypoints = path:GetWaypoints()
			brain.WpIndex = math.min(2, #brain.Waypoints)
			brain.PathGoal = goal
		else
			brain.Waypoints = {}
			brain.PathGoal = nil
		end
	end)
end

local function moveTowards(brain: Brain, goal: Vector3)
	local dist = (goal - brain.Root.Position).Magnitude
	if dist < 14 then
		brain.Waypoints = {}
		brain.Hum:MoveTo(goal)
		return
	end
	if (not brain.PathGoal or (brain.PathGoal - goal).Magnitude > 8 or os.clock() >= brain.NextPath) then
		computePath(brain, goal)
	end
	local wp = brain.Waypoints[brain.WpIndex]
	if wp then
		if (wp.Position - brain.Root.Position).Magnitude < 4 then
			brain.WpIndex += 1
			wp = brain.Waypoints[brain.WpIndex]
		end
		if wp then
			brain.Hum:MoveTo(wp.Position)
			if wp.Action == Enum.PathWaypointAction.Jump then brain.Hum.Jump = true end
			return
		end
	end
	brain.Hum:MoveTo(goal) -- no path yet: head straight there
end

local function pickTarget(brain: Brain, p: any): any?
	local best, bestDist = nil, math.huge
	local candidates = {}
	for _, c in ipairs(CombatService.GetCombatantsInMatch(brain.Match)) do
		if c.Humanoid.Health > 0 and CombatService.IsBotEnemy(brain.Bot, c) then
			local troot = c.Model:FindFirstChild("HumanoidRootPart") :: BasePart?
			if troot then
				local d = (troot.Position - brain.Root.Position).Magnitude
				if d <= p.Sight then table.insert(candidates, { C = c, D = d }) end
			end
		end
	end
	table.sort(candidates, function(a, b) return a.D < b.D end)
	for i = 1, math.min(3, #candidates) do -- only line-of-sight check the closest few (cheap)
		local cand = candidates[i]
		if visible(brain, cand.C) and cand.D < bestDist then best, bestDist = cand.C, cand.D end
	end
	return best
end

local function nearestEnemyAnywhere(brain: Brain): Vector3?
	local best, bestDist = nil, math.huge
	for _, c in ipairs(CombatService.GetCombatantsInMatch(brain.Match)) do
		if c.Humanoid.Health > 0 and CombatService.IsBotEnemy(brain.Bot, c) then
			local troot = c.Model:FindFirstChild("HumanoidRootPart") :: BasePart?
			if troot then
				local d = (troot.Position - brain.Root.Position).Magnitude
				if d < bestDist then best, bestDist = troot.Position, d end
			end
		end
	end
	return best
end

local function shoot(brain: Brain, target: any, p: any)
	local w = brain.Weapon
	local t = os.clock()
	if t < brain.NextShot or t < brain.ReloadUntil then return end
	local troot = target.Model:FindFirstChild("HumanoidRootPart") :: BasePart?
	local thead = target.Model:FindFirstChild("Head") :: BasePart?
	if not troot then return end
	local dist = (troot.Position - brain.Root.Position).Magnitude
	if dist > w.Range * (w.Type == "Melee" and 0.9 or 1) then return end

	local function fireOnce()
		if not brain.Model.Parent or brain.Hum.Health <= 0 or not troot.Parent then return end
		local aimPart = (thead and math.random() < p.Headshot) and thead or troot
		local aim = aimPart.Position
		if w.Type == "Projectile" and w.ProjectileSpeed then
			aim += troot.AssemblyLinearVelocity * ((aim - brain.Head.Position).Magnitude / w.ProjectileSpeed) -- lead
		end
		local origin = brain.Head.Position + (aim - brain.Head.Position).Unit * 1.5
		local dir = spread((aim - origin).Unit, p.AimError + (w.Spread or 0))
		CombatService.BotAttack(brain.Bot, w, origin, dir)
	end

	if w.FireMode == "Burst" then
		local n = math.min(w.BurstCount or 1, w.MagSize > 0 and brain.Ammo or 99)
		for i = 0, n - 1 do task.delay(i * (w.BurstInterval or 0.07), fireOnce) end
		if w.MagSize > 0 then brain.Ammo -= n end
	else
		fireOnce()
		if w.MagSize > 0 then brain.Ammo -= 1 end
	end
	brain.NextShot = t + w.Cooldown / p.FireRate
	if w.MagSize > 0 and brain.Ammo <= 0 then
		brain.ReloadUntil = t + w.ReloadTime
		brain.Ammo = w.MagSize
	end
end

local function think(brain: Brain)
	local match = brain.Match
	if match.State ~= "Live" or brain.Hum.Health <= 0 or not brain.Model.Parent then return end
	local p = preset()
	local now = os.clock()
	local root = brain.Root
	if root.Anchored then root.Anchored = false end

	-- target + reaction time
	local target = pickTarget(brain, p)
	-- compare by model: pickTarget builds a fresh record each think, the reaction timer must only
	-- restart when the bot actually switches to a different enemy
	local prevModel = brain.Target and brain.Target.Model
	if (target and target.Model) ~= prevModel then
		brain.TargetSince = now
	end
	brain.Target = target

	local teamMode = GameConfig.Modes[match.Mode].TeamBased
	local core = teamMode and corePosition(match) or nil
	if target then
		local troot = target.Model:FindFirstChild("HumanoidRootPart") :: BasePart
		local toT = troot.Position - root.Position
		local flat = Vector3.new(toT.X, 0, toT.Z)
		-- face the target while fighting
		brain.Hum.AutoRotate = false
		if flat.Magnitude > 0.1 then
			root.CFrame = CFrame.lookAt(root.Position, root.Position + flat.Unit)
		end
		if now - brain.TargetSince >= p.Reaction then shoot(brain, target, p) end

		local w = brain.Weapon
		local ideal = w.Type == "Melee" and 3 or math.min(w.Range * 0.5, 55)
		if flat.Magnitude > ideal + 6 then
			moveTowards(brain, troot.Position) -- close the gap
		else
			if now >= brain.NextStrafeFlip then
				brain.StrafeSign = (math.random() < 0.5) and -1 or 1
				brain.NextStrafeFlip = now + 0.8 + math.random() * 1.4
			end
			local side = flat.Magnitude > 0.1 and flat.Unit:Cross(Vector3.yAxis) or Vector3.xAxis
			local strafe = (math.random() < p.Strafe) and side * brain.StrafeSign * 8 or Vector3.zero
			-- in Hold the Core, drift towards the core while fighting
			local drift = Vector3.zero
			if core and (core - root.Position).Magnitude > 12 then drift = (core - root.Position).Unit * 6 end
			brain.Hum:MoveTo(root.Position + strafe + drift)
		end
	else
		brain.Hum.AutoRotate = true
		local goal: Vector3? = nil
		if teamMode then
			if not brain.CorePoint or (core and (brain.CorePoint - root.Position).Magnitude < 3) then
				brain.CorePoint = randomCorePoint(match) -- wander around the core once there
			end
			goal = brain.CorePoint
		else
			goal = nearestEnemyAnywhere(brain) -- 1v1: hunt the player
		end
		if goal then moveTowards(brain, goal) end
	end

	-- stuck: jump and re-plan
	if now - brain.LastMoveCheck >= 1.5 then
		if (root.Position - brain.LastPos).Magnitude < 1 then
			brain.Hum.Jump = true
			brain.NextPath = 0
			brain.PathGoal = nil
		end
		brain.LastPos = root.Position
		brain.LastMoveCheck = now
	end
end

---------------------------------------------------------------- lifecycle
function BotService.Init()
	MatchManager.On("Started", function(match)
		if #(match.Bots or {}) == 0 then return end
		local folder = Instance.new("Folder")
		folder.Name = "Bots"
		folder.Parent = match.Map
		for _, bot in ipairs(match.Bots) do
			task.spawn(spawnBot, match, bot)
		end
		print(string.format("[BotService] %d bots joined %s (%s)", #match.Bots, match.Mode, Cfg.Difficulty))
	end)
	MatchManager.On("Ended", function(match)
		for i = #brains, 1, -1 do
			if brains[i].Match == match then
				brains[i].Hum:MoveTo(brains[i].Root.Position)
				table.remove(brains, i)
			end
		end
	end)

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < Cfg.ThinkRate then return end
		acc = 0
		for i = #brains, 1, -1 do
			local b = brains[i]
			if not b.Model.Parent then
				table.remove(brains, i)
			else
				local ok, err = pcall(think, b)
				if not ok then warn("[BotService] think error: " .. tostring(err)) end
			end
		end
	end)

	-- Studio-only QA hook (never created on live servers): start test matches of any size
	if GameConfig.IsStudio then
		local hook = Instance.new("BindableFunction")
		hook.Name = "VG_BotTest"
		hook.OnInvoke = function(action: string, a: any, b: any, c: any)
			if action == "Start" then
				-- a = player, b = mode, c = total fighters (player + bots)
				return MatchManager.StartMatch(b, { a }, { Bots = (c or 2) - 1 })
			elseif action == "End" then
				local m = MatchManager.GetMatch(a)
				if m then MatchManager.EndMatch(m, "Test") return true end
				return false
			elseif action == "Difficulty" then
				if Cfg.Presets[a] then Cfg.Difficulty = a return true end
				return false
			elseif action == "Brains" then
				local out = {}
				for _, br in ipairs(brains) do
					table.insert(out, string.format("%s %s %s hp=%d target=%s", br.Bot.Name, br.Bot.Team, br.Bot.HeroId, br.Hum.Health, br.Target and br.Target.Model.Name or "-"))
				end
				return out
			end
			return nil
		end
		hook.Parent = game:GetService("ServerStorage")
	end
end

return BotService
