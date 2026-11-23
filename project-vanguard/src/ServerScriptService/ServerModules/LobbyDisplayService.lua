--!strict
-- LobbyDisplayService: the lobby's physical, icon-based displays and step-on queue pads.
--  * Queue pads (Workspace.Lobby.QueuePads, attribute QueueMode): stand on a pad to join that queue,
--    step off to leave it (only if you joined via the pad). Same server-validated Matchmaking as the PLAY menu.
--  * Floating pad screens + the big mode board above the pads show live "players / max" and countdowns.
--  * Leaderboard signs get headers with icons (rows are filled by LeaderboardService in Phase 8).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local IconConfig = require(ReplicatedStorage.Modules.IconConfig)
local Matchmaking = require(script.Parent.Matchmaking)
local MatchManager = require(script.Parent.MatchManager)

local LobbyDisplayService = {}

local FONT = Enum.Font.FredokaOne
local MODE_COLORS = {
	Casual = Color3.fromRGB(0, 170, 255),
	Ranked = Color3.fromRGB(170, 70, 255),
	Duel = Color3.fromRGB(255, 120, 40),
}

local function stroke(parent: Instance, thickness: number)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness
	s.Color = Color3.new(0, 0, 0)
	s.Parent = parent
end

local function label(parent: Instance, text: string, size: UDim2, pos: UDim2, color: Color3?): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Font = FONT
	t.Text = text
	t.TextColor3 = color or Color3.new(1, 1, 1)
	t.TextScaled = true
	t.Size = size
	t.Position = pos
	stroke(t, 3)
	t.Parent = parent
	return t
end

local function icon(parent: Instance, name: string, size: UDim2, pos: UDim2): ImageLabel
	local i = Instance.new("ImageLabel")
	i.Name = name .. "Icon"
	i.BackgroundTransparency = 1
	i.Image = IconConfig.Get(name)
	i.ScaleType = Enum.ScaleType.Fit
	i.Size = size
	i.Position = pos
	i.Parent = parent
	return i
end

-- which face of a part points toward a world position
local function faceToward(part: BasePart, target: Vector3): Enum.NormalId
	local best, bestDot = Enum.NormalId.Front, -math.huge
	local dir = (target - part.Position).Unit
	for _, face in ipairs(Enum.NormalId:GetEnumItems()) do
		local n = part.CFrame:VectorToWorldSpace(Vector3.FromNormalId(face))
		local d = n:Dot(dir)
		if d > bestDot then best, bestDot = face, d end
	end
	return best
end

local function clearDecals(model: Instance)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Decal") or d:IsA("SelectionBox") or d:IsA("Sound") then d:Destroy() end
	end
end

local padScreens: { [string]: { Count: TextLabel, Status: TextLabel } } = {}
local boardCounts: { [string]: TextLabel } = {}

local function buildPadScreen(pad: BasePart, modeId: string)
	local mode = GameConfig.Modes[modeId]
	local anchor = Instance.new("Attachment")
	anchor.Name = "ScreenAnchor"
	anchor.Position = Vector3.new(0, 12, 0)
	anchor.Parent = pad
	local bb = Instance.new("BillboardGui")
	bb.Name = "PadScreen"
	bb.Size = UDim2.fromScale(18, 12)
	bb.LightInfluence = 0
	bb.MaxDistance = 160
	bb.Adornee = anchor
	bb.Parent = pad
	icon(bb, IconConfig.ModeIcon[modeId], UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.25, 0))
	label(bb, mode.DisplayName, UDim2.fromScale(1, 0.18), UDim2.fromScale(0, 0.5), MODE_COLORS[modeId])
	local count = label(bb, "0/" .. mode.MaxPlayers, UDim2.fromScale(1, 0.22), UDim2.fromScale(0, 0.68))
	local status = label(bb, "STAND HERE TO QUEUE", UDim2.fromScale(1, 0.1), UDim2.fromScale(0, 0.9), Color3.fromRGB(255, 220, 80))
	padScreens[modeId] = { Count = count, Status = status }
end

local function buildModeBoard(board: BasePart)
	local center = Vector3.new(board.Position.X, board.Position.Y, 0)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "ModeBoard"
	gui.Face = faceToward(board, center)
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0
	gui.Brightness = 1.5
	gui.Parent = board
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(8, 14, 32)
	bg.Parent = gui
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(Color3.fromRGB(20, 60, 140), Color3.fromRGB(6, 10, 28))
	grad.Rotation = 90
	grad.Parent = bg
	label(bg, "DEPLOY", UDim2.fromScale(0.6, 0.16), UDim2.fromScale(0.2, 0.03), Color3.fromRGB(120, 220, 255))
	for i, modeId in ipairs(GameConfig.ModeOrder) do
		local col = Instance.new("Frame")
		col.BackgroundTransparency = 1
		col.Size = UDim2.fromScale(0.32, 0.78)
		col.Position = UDim2.fromScale(0.01 + (i - 1) * 0.33, 0.2)
		col.Parent = bg
		icon(col, IconConfig.ModeIcon[modeId], UDim2.fromScale(0.8, 0.5), UDim2.fromScale(0.1, 0))
		label(col, GameConfig.Modes[modeId].DisplayName, UDim2.fromScale(1, 0.17), UDim2.fromScale(0, 0.52), MODE_COLORS[modeId])
		boardCounts[modeId] = label(col, "0/" .. GameConfig.Modes[modeId].MaxPlayers, UDim2.fromScale(1, 0.25), UDim2.fromScale(0, 0.72))
	end
end

local function buildSign(sign: BasePart, iconName: string, title: string, color: Color3)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "BoardGui"
	gui.Face = faceToward(sign, Vector3.new(0, sign.Position.Y, 0))
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Parent = sign
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(10, 12, 24)
	bg.Parent = gui
	icon(bg, iconName, UDim2.fromScale(0.3, 0.22), UDim2.fromScale(0.03, 0.01))
	label(bg, title, UDim2.fromScale(0.64, 0.16), UDim2.fromScale(0.34, 0.04), color)
	local rows = Instance.new("Frame")
	rows.Name = "Rows"
	rows.BackgroundTransparency = 1
	rows.Size = UDim2.fromScale(0.94, 0.74)
	rows.Position = UDim2.fromScale(0.03, 0.24)
	rows.Parent = bg
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0.01, 0)
	list.SortOrder = Enum.SortOrder.LayoutOrder -- keep #1..#10 in number order (name order would put Row10 after Row1)
	list.Parent = rows
	for i = 1, 10 do
		local r = Instance.new("Frame")
		r.Name = "Row" .. i
		r.LayoutOrder = i
		r.Size = UDim2.fromScale(1, 0.09)
		r.BackgroundColor3 = i <= 3 and Color3.fromRGB(40, 36, 20) or Color3.fromRGB(24, 28, 44)
		r.Parent = rows
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0.3, 0); c.Parent = r
		label(r, "#" .. i, UDim2.fromScale(0.14, 1), UDim2.fromScale(0.02, 0), i == 1 and Color3.fromRGB(255, 210, 60) or Color3.fromRGB(200, 210, 235)).Name = "Rank"
		label(r, "---", UDim2.fromScale(0.56, 0.8), UDim2.fromScale(0.18, 0.1)).Name = "PlayerName"
		label(r, "-", UDim2.fromScale(0.24, 0.8), UDim2.fromScale(0.74, 0.1), color).Name = "Value"
	end
end

local function refresh()
	local now = workspace:GetServerTimeNow()
	for _, modeId in ipairs(GameConfig.ModeOrder) do
		local n = Matchmaking.GetQueueCount(modeId)
		local max = GameConfig.Modes[modeId].MaxPlayers
		local text = n .. "/" .. max
		if boardCounts[modeId] then boardCounts[modeId].Text = text end
		local ps = padScreens[modeId]
		if ps then
			ps.Count.Text = text
			local ends = Matchmaking.GetCountdownEndsAt(modeId)
			if ends then
				ps.Status.Text = "STARTING IN " .. math.max(0, math.ceil(ends - now))
			elseif n > 0 then
				ps.Status.Text = "WAITING FOR PLAYERS"
			else
				ps.Status.Text = "STAND HERE TO QUEUE"
			end
		end
	end
end

-- Pad presence: players inside a pad's volume join; leaving the volume leaves (if the pad queued them).
local padQueued: { [Player]: string } = {}
local function playersOnPad(pad: BasePart): { [Player]: boolean }
	local inside = {}
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local chars = {}
	for _, p in ipairs(Players:GetPlayers()) do if p.Character then table.insert(chars, p.Character) end end
	params.FilterDescendantsInstances = chars
	local parts = workspace:GetPartBoundsInBox(pad.CFrame * CFrame.new(0, 4, 0), Vector3.new(pad.Size.X, 8, pad.Size.Z), params)
	for _, part in ipairs(parts) do
		if part.Name == "HumanoidRootPart" then
			local p = Players:GetPlayerFromCharacter(part.Parent)
			if p then inside[p] = true end
		end
	end
	return inside
end

local function padTick(pads: { BasePart })
	local seen: { [Player]: string } = {}
	for _, pad in ipairs(pads) do
		local modeId = pad:GetAttribute("QueueMode") :: string
		for p in pairs(playersOnPad(pad)) do
			seen[p] = modeId
			if not MatchManager.IsInMatch(p) and Matchmaking.GetModeOf(p) ~= modeId then
				Matchmaking.Join(p, modeId)
				padQueued[p] = modeId
			end
		end
	end
	for p, modeId in pairs(padQueued) do
		if seen[p] ~= modeId then
			padQueued[p] = nil
			if p.Parent == Players and Matchmaking.GetModeOf(p) == modeId then
				Matchmaking.Leave(p)
			end
		end
	end
end

function LobbyDisplayService.Init()
	local lobby = workspace:WaitForChild("Lobby")
	local L = lobby:WaitForChild("Hangar"):WaitForChild("PermaLobby")
	local pads = {}
	for _, pad in ipairs(lobby:WaitForChild("QueuePads"):GetChildren()) do
		if pad:IsA("BasePart") and pad:GetAttribute("QueueMode") then
			table.insert(pads, pad)
			buildPadScreen(pad, pad:GetAttribute("QueueMode") :: string)
		end
	end
	local board = L:FindFirstChild("Board1")
	if board then
		clearDecals(board)
		buildModeBoard(board:FindFirstChild("Board") :: BasePart)
	end
	local kills = L:FindFirstChild("WhatsNewSign")
	if kills then
		clearDecals(kills)
		local s = kills:FindFirstChild("Sign") :: BasePart
		s.Name = "KillsBoard"
		buildSign(s, "Trophy", "MOST KILLS", Color3.fromRGB(255, 210, 60))
	end
	local robux = L:FindFirstChild("HowToSign")
	if robux then
		clearDecals(robux)
		local s = robux:FindFirstChild("Sign") :: BasePart
		s.Name = "RobuxBoard"
		buildSign(s, "Gem", "TOP SUPPORTERS", Color3.fromRGB(90, 255, 140))
	end
	local join = L:FindFirstChild("JoinGameSign")
	if join then
		clearDecals(join)
		local s = join:FindFirstChild("Sign") :: BasePart?
		if s then
			s.Name = "RankedBoard" -- rows filled by RankedService
			buildSign(s, "Ranked", "TOP RANKED  -  " .. GameConfig.Ranked.SeasonName, Color3.fromRGB(200, 120, 255))
		end
	end

	Players.PlayerRemoving:Connect(function(p) padQueued[p] = nil end)
	task.spawn(function()
		while true do
			padTick(pads)
			refresh()
			task.wait(0.3)
		end
	end)
end

return LobbyDisplayService
