--!strict
-- ObjectiveService: "Hold the Core" for team modes (Casual + Ranked).
-- Each map has a flat cylinder part named "Objective". It is dressed as a holographic ring.
-- Server-only logic, every TickRate seconds:
--   * only one team alive inside the ring -> that team's meter fills (SecondsToWin for one player,
--     faster with more teammates, capped)
--   * both teams inside -> CONTESTED, nobody gains
--   * first team to 100% wins; at time-up the higher % wins (MatchManager tiebreaks on eliminations)
-- Clients only read replicated attributes: ObjAlpha / ObjBravo (0-100), ObjState, ObjOnPoint.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local MatchManager = require(script.Parent.MatchManager)

local Cfg = GameConfig.Objective

local ObjectiveService = {}

type CoreState = {
	Match: any,
	Part: BasePart,
	Center: Vector3,
	Radius: number,
	FloorY: number,
	Progress: { [string]: number },
	State: string,
	Ring: { BasePart },
	LastSent: { [string]: any },
}

local cores: { [string]: CoreState } = {}

local NEUTRAL = Color3.fromRGB(200, 215, 255)
local CONTESTED = Color3.fromRGB(255, 210, 60)
local SEGMENTS = 40

local function stateColor(state: string): Color3
	if state == "Contested" then return CONTESTED end
	local team = GameConfig.Teams[state]
	return team and team.Color or NEUTRAL
end

-- Holographic ring: the objective disc becomes a faint force-field floor and a neon rim is built from segments.
local function dressCore(part: BasePart): ({ BasePart }, Vector3, number, number)
	-- the cylinder's axis is its X axis; the round faces have diameter Size.Y
	local radius = math.min(part.Size.Y, part.Size.Z) / 2
	local up = part.CFrame.RightVector
	if math.abs(up.Y) < 0.5 then up = Vector3.yAxis end
	local center = part.Position
	local floorY = center.Y + part.Size.X / 2
	part.Material = Enum.Material.ForceField
	part.Color = NEUTRAL
	part.Transparency = 0.55
	part.CanCollide = false
	part.CastShadow = false

	local folder = Instance.new("Folder")
	folder.Name = "CoreRing"
	folder.Parent = part.Parent
	local ring = {}
	local segLen = 2 * math.pi * radius / SEGMENTS * 1.08
	for i = 1, SEGMENTS do
		local a = (i / SEGMENTS) * math.pi * 2
		local pos = Vector3.new(center.X + math.cos(a) * radius, floorY + 0.1, center.Z + math.sin(a) * radius)
		local seg = Instance.new("Part")
		seg.Name = "RingSegment"
		seg.Anchored = true; seg.CanCollide = false; seg.CanQuery = false; seg.CanTouch = false; seg.CastShadow = false
		seg.Material = Enum.Material.Neon
		seg.Color = NEUTRAL
		seg.Size = Vector3.new(0.5, 0.25, segLen)
		-- tangent to the circle
		seg.CFrame = CFrame.lookAt(pos, pos + Vector3.new(-math.sin(a), 0, math.cos(a)))
		seg.Parent = folder
		table.insert(ring, seg)
	end
	-- a soft glow so the ring lights the floor around it
	local glow = Instance.new("PointLight")
	glow.Name = "CoreGlow"
	glow.Range = radius * 1.2
	glow.Brightness = 0.8
	glow.Color = NEUTRAL
	glow.Shadows = false
	glow.Parent = part
	return ring, center, radius, floorY
end

local function paint(core: CoreState, color: Color3)
	core.Part.Color = color
	for _, seg in ipairs(core.Ring) do seg.Color = color end
	local glow = core.Part:FindFirstChild("CoreGlow") :: PointLight?
	if glow then glow.Color = color end
end

local function onCore(core: CoreState, root: BasePart): boolean
	local p = root.Position
	local dx, dz = p.X - core.Center.X, p.Z - core.Center.Z
	if dx * dx + dz * dz > core.Radius * core.Radius then return false end
	return p.Y >= core.FloorY - Cfg.HeightBelow and p.Y <= core.FloorY + Cfg.HeightAbove
end

local function publish(core: CoreState, onPointSet: { [Player]: boolean })
	local a = math.floor(core.Progress.Alpha)
	local b = math.floor(core.Progress.Bravo)
	local match = core.Match
	match.Scores.Alpha = a
	match.Scores.Bravo = b
	for _, p in ipairs(match.Players) do
		if p.Parent == Players then
			p:SetAttribute("ObjAlpha", a)
			p:SetAttribute("ObjBravo", b)
			p:SetAttribute("ObjState", core.State)
			p:SetAttribute("ObjOnPoint", onPointSet[p] == true)
		end
	end
end

local function step(core: CoreState, dt: number)
	local match = core.Match
	if match.State ~= "Live" then return end
	local present: { [string]: { Player } } = { Alpha = {}, Bravo = {} }
	local onPointSet: { [Player]: boolean } = {}
	for _, p in ipairs(match.Players) do
		local team = match.TeamOf[p]
		local char = p.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if team and present[team] and hum and hum.Health > 0 and root and onCore(core, root) then
			table.insert(present[team], p)
			onPointSet[p] = true
		end
	end
	local nA, nB = #present.Alpha, #present.Bravo
	local state
	if nA > 0 and nB > 0 then
		state = "Contested"
	elseif nA > 0 or nB > 0 then
		local team = nA > 0 and "Alpha" or "Bravo"
		local n = math.max(nA, nB)
		local mult = math.min(1 + (n - 1) * Cfg.ExtraPlayerBonus, Cfg.MaxSpeedMult)
		core.Progress[team] = math.min(100, core.Progress[team] + (100 / Cfg.SecondsToWin) * mult * dt)
		state = team
	else
		state = "Neutral"
	end
	-- objective time counts for anyone standing on the core (holding or contesting)
	for p in pairs(onPointSet) do
		local s = match.Stats[p]
		if s then s.ObjTime += dt end
	end
	if state ~= core.State then
		core.State = state
		paint(core, stateColor(state))
	end
	publish(core, onPointSet)
	for _, team in ipairs({ "Alpha", "Bravo" }) do
		if core.Progress[team] >= 100 then
			MatchManager.EndMatch(match, "Objective", team)
			return
		end
	end
end

local function clearAttrs(players: { Player })
	for _, p in ipairs(players) do
		if p.Parent == Players then
			for _, a in ipairs({ "ObjAlpha", "ObjBravo", "ObjState", "ObjOnPoint" }) do p:SetAttribute(a, nil) end
		end
	end
end

function ObjectiveService.Init()
	MatchManager.On("Started", function(match)
		local mode = GameConfig.Modes[match.Mode]
		if not mode.TeamBased then return end
		local part = match.Map:FindFirstChild("Objective")
		if not part or not part:IsA("BasePart") then
			warn("[ObjectiveService] map has no Objective part: " .. match.MapId)
			return
		end
		local ring, center, radius, floorY = dressCore(part)
		local core: CoreState = {
			Match = match, Part = part, Center = center, Radius = radius, FloorY = floorY,
			Progress = { Alpha = 0, Bravo = 0 }, State = "Neutral", Ring = ring, LastSent = {},
		}
		cores[match.Id] = core
		publish(core, {})
	end)
	MatchManager.On("Ended", function(match)
		if cores[match.Id] then
			cores[match.Id] = nil
			clearAttrs(match.Players)
		end
	end)
	MatchManager.On("PlayerLeft", function(_match, player)
		clearAttrs({ player })
	end)
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(Cfg.TickRate)
			local t = os.clock()
			local dt = math.min(t - last, 1)
			last = t
			for _, core in pairs(cores) do
				step(core, dt)
			end
		end
	end)
end

return ObjectiveService
