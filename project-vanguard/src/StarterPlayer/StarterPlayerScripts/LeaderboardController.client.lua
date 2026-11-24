-- LeaderboardController (Phase 8): draws the MOST KILLS and TOP SUPPORTERS lists on the lobby boards.
-- The server builds each board's frame + header (LobbyDisplayService) and sends the data
-- (LeaderboardService -> LeaderboardData). Each client renders the top 25 as an auto-scrolling list
-- with medal rows and avatar headshots, plus a highlighted "YOU" line only that player sees.
-- Display only: nothing here can change a score.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameConfig = require(Modules:WaitForChild("GameConfig"))
local LeaderboardData = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("LeaderboardData")

local Cfg = GameConfig.Leaderboards
local FONT = Enum.Font.FredokaOne
local VISIBLE_ROWS = 8
local SCROLL_SPEED = 14 -- pixels per second
local PAUSE = 3
local MEDAL = { Color3.fromRGB(255, 205, 60), Color3.fromRGB(210, 220, 235), Color3.fromRGB(215, 135, 70) }
local MEDAL_BG = { Color3.fromRGB(52, 44, 16), Color3.fromRGB(38, 42, 52), Color3.fromRGB(48, 32, 22) }
local ROW_BG = Color3.fromRGB(24, 28, 44)
local CYAN = Color3.fromRGB(0, 220, 255)

local function commas(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

local function valueText(board: string, v: number): string
	if board == "Robux" then return "R$ " .. commas(v) end
	return commas(v)
end

local function label(parent: Instance, text: string, size: UDim2, pos: UDim2, color: Color3?, align: Enum.TextXAlignment?): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Font = FONT
	t.Text = text
	t.TextColor3 = color or Color3.new(1, 1, 1)
	t.TextScaled = true
	t.TextXAlignment = align or Enum.TextXAlignment.Center
	t.Size = size
	t.Position = pos
	local s = Instance.new("UIStroke"); s.Thickness = 2; s.Parent = t
	t.Parent = parent
	return t
end

type BoardUI = { Scroll: ScrollingFrame, Rows: { Frame }, You: Frame, YouText: TextLabel, YouValue: TextLabel, Empty: TextLabel, RowH: number }
local boards: { [string]: BoardUI } = {}
local lists: { [string]: { any } } = {}
local selfInfo: any = nil

---------------------------------------------------------------- build one overlay
local function makeRow(parent: Instance, rowH: number, i: number): Frame
	local r = Instance.new("Frame")
	r.Name = "Row" .. i
	r.LayoutOrder = i
	r.Size = UDim2.new(1, 0, 0, rowH - 4)
	r.BackgroundColor3 = i <= 3 and MEDAL_BG[i] or ROW_BG
	r.BorderSizePixel = 0
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0.3, 0); c.Parent = r
	if i <= 3 then
		local st = Instance.new("UIStroke"); st.Color = MEDAL[i]; st.Thickness = 2; st.Transparency = 0.2
		st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; st.Parent = r
	end
	label(r, "#" .. i, UDim2.fromScale(0.11, 0.8), UDim2.fromScale(0.01, 0.1), i <= 3 and MEDAL[i] or Color3.fromRGB(200, 210, 235)).Name = "Rank"
	local head = Instance.new("ImageLabel")
	head.Name = "Head"
	head.BackgroundColor3 = Color3.fromRGB(14, 16, 28)
	head.Size = UDim2.fromScale(0.08, 0.84)
	head.Position = UDim2.fromScale(0.125, 0.08)
	local ar = Instance.new("UIAspectRatioConstraint"); ar.AspectRatio = 1; ar.DominantAxis = Enum.DominantAxis.Height; ar.Parent = head
	local hc = Instance.new("UICorner"); hc.CornerRadius = UDim.new(0.5, 0); hc.Parent = head
	local hs = Instance.new("UIStroke"); hs.Color = i <= 3 and MEDAL[i] or CYAN; hs.Thickness = 1.5; hs.Transparency = 0.3; hs.Parent = head
	head.Parent = r
	label(head, "?", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), CYAN).Name = "Anon"
	label(r, "---", UDim2.fromScale(0.46, 0.7), UDim2.fromScale(0.225, 0.15), nil, Enum.TextXAlignment.Left).Name = "PlayerName"
	label(r, "-", UDim2.fromScale(0.3, 0.7), UDim2.fromScale(0.68, 0.15), nil, Enum.TextXAlignment.Right).Name = "Value"
	r.Parent = parent
	return r
end

local function build(board: string, sign: BasePart)
	local serverGui = sign:WaitForChild("BoardGui", 30) :: SurfaceGui?
	if not serverGui then return end
	local b = Cfg.Boards[board]
	local gui = Instance.new("SurfaceGui")
	gui.Name = board .. "BoardList"
	gui.Adornee = sign
	gui.Face = serverGui.Face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = serverGui.PixelsPerStud
	gui.LightInfluence = 0
	gui.ZOffset = 1
	gui.MaxDistance = 250
	gui.ResetOnSpawn = false
	gui.Parent = playerGui

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "List"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromScale(0.03, 0.24)
	scroll.Size = UDim2.fromScale(0.94, 0.62)
	scroll.ScrollBarThickness = 4
	scroll.ScrollBarImageColor3 = b.Color
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 4)
	layout.Parent = scroll

	task.wait() -- let AbsoluteSize resolve
	local rowH = math.max(math.floor(scroll.AbsoluteSize.Y / VISIBLE_ROWS), 24)
	local rows = {}
	for i = 1, Cfg.Show do
		local r = makeRow(scroll, rowH, i)
		r.Visible = false
		rows[i] = r
	end
	local empty = label(gui, "No entries yet - be the first!", UDim2.fromScale(0.8, 0.08), UDim2.fromScale(0.1, 0.45), Color3.fromRGB(160, 170, 200))
	empty.Name = "Empty"

	-- YOU line
	local you = Instance.new("Frame")
	you.Name = "You"
	you.BackgroundColor3 = Color3.fromRGB(10, 40, 56)
	you.BorderSizePixel = 0
	you.Position = UDim2.fromScale(0.03, 0.875)
	you.Size = UDim2.fromScale(0.94, 0.1)
	local yc = Instance.new("UICorner"); yc.CornerRadius = UDim.new(0.3, 0); yc.Parent = you
	local ys = Instance.new("UIStroke"); ys.Color = CYAN; ys.Thickness = 2; ys.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; ys.Parent = you
	you.Parent = gui
	local youText = label(you, "YOU", UDim2.fromScale(0.62, 0.75), UDim2.fromScale(0.03, 0.12), CYAN, Enum.TextXAlignment.Left)
	local youValue = label(you, "", UDim2.fromScale(0.33, 0.75), UDim2.fromScale(0.64, 0.12), Color3.new(1, 1, 1), Enum.TextXAlignment.Right)

	boards[board] = { Scroll = scroll, Rows = rows, You = you, YouText = youText, YouValue = youValue, Empty = empty, RowH = rowH }
end

---------------------------------------------------------------- fill
local function render(board: string)
	local ui = boards[board]
	if not ui then return end
	local list = lists[board] or {}
	for i, r in ipairs(ui.Rows) do
		local e = list[i]
		r.Visible = e ~= nil
		if e then
			local name = r:FindFirstChild("PlayerName") :: TextLabel
			local value = r:FindFirstChild("Value") :: TextLabel
			local rank = r:FindFirstChild("Rank") :: TextLabel
			local head = r:FindFirstChild("Head") :: ImageLabel
			rank.Text = "#" .. tostring(e.Rank)
			name.Text = tostring(e.Name)
			name.TextColor3 = (e.UserId == player.UserId) and CYAN or Color3.new(1, 1, 1)
			value.Text = valueText(board, tonumber(e.Value) or 0)
			value.TextColor3 = (i <= 3) and MEDAL[i] or Cfg.Boards[board].Color
			local uid = tonumber(e.UserId)
			head.Image = uid and string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=60&h=60", uid) or ""
			local anon = head:FindFirstChild("Anon") :: TextLabel
			anon.Visible = uid == nil
		end
	end
	ui.Empty.Visible = #list == 0

	local mine = selfInfo and selfInfo[board]
	local rankText, valText
	if not mine then
		rankText, valText = "YOU", "..."
	else
		local v = tonumber(mine.Value) or 0
		if v <= 0 then
			rankText = board == "Kills" and "YOU  -  get a kill to join the board" or "YOU  -  not on the board yet"
			valText = ""
		else
			local r = tonumber(mine.Rank)
			rankText = "YOU   " .. (r and ("#" .. r) or (Cfg.Fetch .. "+"))
			if board == "Robux" and selfInfo.Hidden then rankText ..= "  (hidden)" end
			valText = valueText(board, v)
		end
	end
	ui.YouText.Text = rankText
	ui.YouValue.Text = valText
end

local function renderAll()
	for board in pairs(boards) do render(board) end
end

LeaderboardData.OnClientEvent:Connect(function(kind, data)
	if typeof(data) ~= "table" then return end
	if kind == "Boards" then
		for board, list in pairs(data) do
			if Cfg.Boards[board] and typeof(list) == "table" then lists[board] = list end
		end
		renderAll()
	elseif kind == "Self" then
		selfInfo = data
		renderAll()
	end
end)

---------------------------------------------------------------- auto-scroll (down slowly, pause, glide back to the top)
local scrollState: { [string]: { Phase: string, T: number } } = {}
RunService.Heartbeat:Connect(function(dt)
	for board, ui in pairs(boards) do
		local s = ui.Scroll
		local maxY = math.max(0, s.AbsoluteCanvasSize.Y - s.AbsoluteWindowSize.Y)
		local st = scrollState[board]
		if not st then st = { Phase = "Wait", T = 0 }; scrollState[board] = st end
		if maxY <= 1 then
			s.CanvasPosition = Vector2.zero
			continue
		end
		st.T += dt
		if st.Phase == "Wait" then
			if st.T >= PAUSE then st.Phase = "Down"; st.T = 0 end
		elseif st.Phase == "Down" then
			local y = math.min(maxY, s.CanvasPosition.Y + SCROLL_SPEED * dt)
			s.CanvasPosition = Vector2.new(0, y)
			if y >= maxY then st.Phase = "Bottom"; st.T = 0 end
		elseif st.Phase == "Bottom" then
			if st.T >= PAUSE then
				st.Phase = "Back"; st.T = 0
				TweenService:Create(s, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { CanvasPosition = Vector2.zero }):Play()
			end
		elseif st.Phase == "Back" then
			if st.T >= 1.3 then st.Phase = "Wait"; st.T = 0 end
		end
	end
end)

---------------------------------------------------------------- find the boards (renamed by the server at startup)
task.spawn(function()
	local lobby = workspace:WaitForChild("Lobby")
	for _, board in ipairs(Cfg.BoardOrder) do
		task.spawn(function()
			local sign: Instance? = nil
			for _ = 1, 120 do
				sign = lobby:FindFirstChild(board .. "Board", true)
				if sign then break end
				task.wait(0.5)
			end
			if sign and sign:IsA("BasePart") then
				build(board, sign)
				render(board)
			end
		end)
	end
end)
