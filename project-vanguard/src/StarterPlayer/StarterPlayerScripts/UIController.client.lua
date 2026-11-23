-- UIController: builds and drives every Phase 1 interface.
-- ScreenGuis created: LobbyUI, CharacterUI, ShopUI, MatchUI, MatchResultUI, NotifyUI.
-- The client only REQUESTS actions (queue, shop teleport); the server decides everything.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameConfig = require(Modules.GameConfig)
local MapConfig = require(Modules.MapConfig)
local HeroConfig = require(Modules.HeroConfig)
local UI = require(Modules.UIStyle)
local IconConfig = require(Modules.IconConfig)
local C = UI.Colors

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local QueueRequest = Remotes:WaitForChild("QueueRequest")
local QueueUpdate = Remotes:WaitForChild("QueueUpdate")
local MatchState = Remotes:WaitForChild("MatchState")
local ShopNavigate = Remotes:WaitForChild("ShopNavigate")
local OpenShop = Remotes:WaitForChild("OpenShop")
local Notify = Remotes:WaitForChild("Notify")
local GetLobbyData = Remotes:WaitForChild("GetLobbyData")
local SelectHero = Remotes:WaitForChild("SelectHero")

local profile = { Tokens = 0, UnlockedHeroes = HeroConfig.StarterHeroes, SelectedHero = HeroConfig.StarterHeroes[1], Rank = "Unranked" }
local queueState = { InQueue = false }
local inMatch = false
local openPanel: GuiObject? = nil

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

---------------------------------------------------------------- NOTIFY
local notifyGui = UI.ScreenGui("NotifyUI", playerGui, 50)
local function toast(text: string, color: Color3?)
	local f = UI.Panel({ Parent = notifyGui, Size = UDim2.fromScale(0.34, 0.06), Position = UDim2.fromScale(0.5, 0.86), AnchorPoint = Vector2.new(0.5, 0.5), Stroke = color or C.Cyan, Transparency = 0.05 })
	UI.Label({ Parent = f, Text = text, Size = UDim2.fromScale(0.94, 0.7), Position = UDim2.fromScale(0.03, 0.15), MaxSize = 22, Font = UI.Fonts.Bold })
	UI.PopIn(f)
	task.delay(3, function()
		TweenService:Create(f, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
		for _, d in ipairs(f:GetDescendants()) do
			if d:IsA("TextLabel") then TweenService:Create(d, TweenInfo.new(0.3), { TextTransparency = 1 }):Play() end
			if d:IsA("UIStroke") then TweenService:Create(d, TweenInfo.new(0.3), { Transparency = 1 }):Play() end
		end
		task.wait(0.35)
		f:Destroy()
	end)
end
Notify.OnClientEvent:Connect(function(msg) if typeof(msg) == "string" then toast(msg, C.Gold) end end)

---------------------------------------------------------------- LOBBY UI
local lobbyGui = UI.ScreenGui("LobbyUI", playerGui, 5)

-- top-left: profile card (rank badge icon + name + rank/hero)
local header = UI.Panel({ Parent = lobbyGui, Name = "Profile", Size = UDim2.fromScale(0.22, 0.09), Position = UDim2.fromScale(0.015, 0.11), Color = C.Bg, Transparency = 0.35, Corner = 12 })
UI.Icon({ Parent = header, Icon = "Ranked", Size = UDim2.fromScale(0.26, 1.15), Position = UDim2.fromScale(0.01, -0.08) })
UI.Label({ Parent = header, Text = player.DisplayName, Font = UI.Fonts.Title, Size = UDim2.fromScale(0.7, 0.48), Position = UDim2.fromScale(0.28, 0.06), AlignX = Enum.TextXAlignment.Left, MaxSize = 30, StrokeSize = 2 })
local profileLabel = UI.Label({ Parent = header, Text = "", Font = UI.Fonts.Bold, Color = C.Subtext, Size = UDim2.fromScale(0.7, 0.36), Position = UDim2.fromScale(0.28, 0.56), AlignX = Enum.TextXAlignment.Left, MaxSize = 20, Rich = true })

-- top-centre: token counter (coin icon + amount + green plus), like the reference lobby
local tokenPill = UI.Panel({ Parent = lobbyGui, Name = "Tokens", Size = UDim2.fromScale(0.15, 0.065), Position = UDim2.fromScale(0.5, 0.03), AnchorPoint = Vector2.new(0.5, 0), Color = C.Bg, Transparency = 0.3, Corner = 10 })
UI.Icon({ Parent = tokenPill, Icon = "Token", Size = UDim2.fromScale(0.36, 1.6), Position = UDim2.fromScale(-0.14, -0.3) })
local tokenLabel = UI.Label({ Parent = tokenPill, Text = "0", Font = UI.Fonts.Title, Size = UDim2.fromScale(0.46, 0.8), Position = UDim2.fromScale(0.24, 0.1), MaxSize = 34, StrokeSize = 2.5 })
local plusBtn = Instance.new("TextButton")
plusBtn.Name = "AddTokens"; plusBtn.Text = "+"; plusBtn.Font = UI.Fonts.Title; plusBtn.TextScaled = true; plusBtn.TextColor3 = Color3.new(1, 1, 1)
plusBtn.BackgroundColor3 = Color3.fromRGB(80, 220, 60); plusBtn.Size = UDim2.fromScale(0.2, 0.76); plusBtn.Position = UDim2.fromScale(0.76, 0.12); plusBtn.AutoButtonColor = true
UI.Corner(plusBtn, 6); UI.Stroke(plusBtn, Color3.fromRGB(20, 80, 10), 2, 0)
plusBtn.Parent = tokenPill

-- bottom dock: icon buttons with outlined labels
local dock = UI.Panel({ Parent = lobbyGui, Name = "Dock", Size = UDim2.fromScale(0.36, 0.15), Position = UDim2.fromScale(0.5, 0.985), AnchorPoint = Vector2.new(0.5, 1), Color = C.Bg, Transparency = 0.45, Corner = 14 })
local dockList = Instance.new("UIListLayout")
dockList.FillDirection = Enum.FillDirection.Horizontal; dockList.HorizontalAlignment = Enum.HorizontalAlignment.Center
dockList.VerticalAlignment = Enum.VerticalAlignment.Center; dockList.Padding = UDim.new(0.06, 0); dockList.SortOrder = Enum.SortOrder.LayoutOrder
dockList.Parent = dock
local dockAspect = Instance.new("UIAspectRatioConstraint"); dockAspect.AspectRatio = 4; dockAspect.Parent = dock
local charBtn = UI.DockButton({ Parent = dock, Name = "Characters", Icon = "Characters", Text = "Heroes", Size = UDim2.fromScale(0.22, 0.86), Order = 1 })
local shopBtn = UI.DockButton({ Parent = dock, Name = "Shop", Icon = "Shop", Text = "Shop", Size = UDim2.fromScale(0.22, 0.86), Order = 2 })
local settingsBtn = UI.DockButton({ Parent = dock, Name = "Settings", Icon = "Settings", Text = "Settings", Size = UDim2.fromScale(0.22, 0.86), Order = 3 })

-- big green PLAY button sitting on top of the dock
local playBtn = Instance.new("TextButton")
playBtn.Name = "Play"; playBtn.Text = "PLAY"; playBtn.Font = UI.Fonts.Title; playBtn.TextScaled = true; playBtn.TextColor3 = Color3.new(1, 1, 1)
playBtn.BackgroundColor3 = Color3.fromRGB(110, 230, 60); playBtn.AutoButtonColor = false
playBtn.Size = UDim2.fromScale(0.16, 0.075); playBtn.Position = UDim2.fromScale(0.5, 0.835); playBtn.AnchorPoint = Vector2.new(0.5, 1)
UI.Corner(playBtn, 10)
local playStroke = Instance.new("UIStroke"); playStroke.Thickness = 3; playStroke.Color = Color3.fromRGB(30, 90, 10); playStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; playStroke.Parent = playBtn
local playTextStroke = Instance.new("UIStroke"); playTextStroke.Thickness = 2.5; playTextStroke.Color = Color3.fromRGB(20, 60, 5); playTextStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual; playTextStroke.Parent = playBtn
local playGrad = Instance.new("UIGradient"); playGrad.Color = ColorSequence.new(Color3.fromRGB(170, 255, 110), Color3.fromRGB(60, 190, 30)); playGrad.Rotation = 90; playGrad.Parent = playBtn
local playPad = Instance.new("UIPadding"); playPad.PaddingTop = UDim.new(0.12, 0); playPad.PaddingBottom = UDim.new(0.12, 0); playPad.PaddingLeft = UDim.new(0.3, 0); playPad.Parent = playBtn
UI.Icon({ Parent = playBtn, Icon = "Play", Size = UDim2.fromScale(0.5, 1.9), Position = UDim2.fromScale(-0.5, -0.5) })
local playScale = Instance.new("UIScale"); playScale.Parent = playBtn
playBtn.MouseEnter:Connect(function() TweenService:Create(playScale, TweenInfo.new(0.15, Enum.EasingStyle.Back), { Scale = 1.08 }):Play() end)
playBtn.MouseLeave:Connect(function() TweenService:Create(playScale, TweenInfo.new(0.15), { Scale = 1 }):Play() end)
playBtn.Parent = lobbyGui

-- gentle idle pulse on PLAY so it reads as the main action
task.spawn(function()
	while playBtn.Parent do
		TweenService:Create(playStroke, TweenInfo.new(0.9, Enum.EasingStyle.Sine), { Thickness = 5 }):Play()
		task.wait(0.9)
		TweenService:Create(playStroke, TweenInfo.new(0.9, Enum.EasingStyle.Sine), { Thickness = 3 }):Play()
		task.wait(0.9)
	end
end)

-- queue status bar (top center)
local queueBar = UI.Panel({ Parent = lobbyGui, Name = "QueueStatus", Size = UDim2.fromScale(0.32, 0.09), Position = UDim2.fromScale(0.5, 0.115), AnchorPoint = Vector2.new(0.5, 0), Stroke = C.Cyan, Transparency = 0.1 })
queueBar.Visible = false
local queueTitle = UI.Label({ Parent = queueBar, Text = "SEARCHING", Font = UI.Fonts.Title, Color = C.Cyan, Size = UDim2.fromScale(0.68, 0.5), Position = UDim2.fromScale(0.04, 0.06), AlignX = Enum.TextXAlignment.Left, MaxSize = 26 })
local queueInfo = UI.Label({ Parent = queueBar, Text = "", Font = UI.Fonts.Bold, Color = C.Subtext, Size = UDim2.fromScale(0.68, 0.36), Position = UDim2.fromScale(0.04, 0.58), AlignX = Enum.TextXAlignment.Left, MaxSize = 18 })
local cancelBtn = UI.Button({ Parent = queueBar, Name = "Cancel", Text = "CANCEL", Size = UDim2.fromScale(0.24, 0.64), Position = UDim2.fromScale(0.96, 0.5), AnchorPoint = Vector2.new(1, 0.5), Accent = C.Red, MaxSize = 20 })

local function refreshProfile()
	profileLabel.Text = string.format("<font color=\"#c88cff\">%s</font>  -  <font color=\"#00dcff\">%s</font>", string.upper(profile.Rank), string.upper(profile.SelectedHero))
	tokenLabel.Text = tostring(profile.Tokens)
end

---------------------------------------------------------------- MODAL HELPER
local function makeModal(gui: ScreenGui, title: string, accent: Color3): (Frame, Frame)
	local dim = Instance.new("Frame")
	dim.Name = "Dim"; dim.Size = UDim2.fromScale(1, 1); dim.BackgroundColor3 = Color3.new(0, 0, 0); dim.BackgroundTransparency = 0.45; dim.Visible = false; dim.Parent = gui
	local win = UI.Panel({ Parent = dim, Name = "Window", Size = UDim2.fromScale(0.7, 0.72), Position = UDim2.fromScale(0.5, 0.52), AnchorPoint = Vector2.new(0.5, 0.5), Stroke = accent, Color = C.Bg, Transparency = 0.04, Corner = 14 })
	local ar = Instance.new("UIAspectRatioConstraint"); ar.AspectRatio = 1.75; ar.Parent = win
	UI.Label({ Parent = win, Text = title, Font = UI.Fonts.Title, Color = accent, Size = UDim2.fromScale(0.6, 0.09), Position = UDim2.fromScale(0.03, 0.03), AlignX = Enum.TextXAlignment.Left, MaxSize = 40 })
	local close = UI.Button({ Parent = win, Name = "Close", Text = "X", Size = UDim2.fromScale(0.05, 0.085), Position = UDim2.fromScale(0.975, 0.03), AnchorPoint = Vector2.new(1, 0), Accent = C.Red, MaxSize = 26 })
	close.MouseButton1Click:Connect(function()
		dim.Visible = false
		if openPanel == dim then openPanel = nil end
	end)
	local body = Instance.new("Frame"); body.Name = "Body"; body.BackgroundTransparency = 1
	body.Size = UDim2.fromScale(0.94, 0.8); body.Position = UDim2.fromScale(0.03, 0.16); body.Parent = win
	return dim, body
end

local function showModal(dim: Frame)
	if openPanel and openPanel ~= dim then (openPanel :: GuiObject).Visible = false end
	openPanel = dim
	dim.Visible = true
	UI.PopIn(dim:FindFirstChild("Window") :: GuiObject)
end

---------------------------------------------------------------- PLAY MENU
local playDim, playBody = makeModal(lobbyGui, "SELECT MODE", C.Cyan)
playDim.Name = "PlayMenu"
local modeAccents = { Casual = C.Cyan, Ranked = C.Magenta, Duel = C.Gold }
for i, modeId in ipairs(GameConfig.ModeOrder) do
	local mode = GameConfig.Modes[modeId]
	local accent = modeAccents[modeId]
	local card = UI.Panel({ Parent = playBody, Name = modeId, Size = UDim2.fromScale(0.31, 0.95), Position = UDim2.fromScale((i - 1) * 0.345, 0), Stroke = accent, Color = C.Panel, Transparency = 0.05 })
	local cardGrad = Instance.new("UIGradient"); cardGrad.Color = ColorSequence.new(accent:Lerp(Color3.new(0, 0, 0), 0.55), C.Panel); cardGrad.Rotation = 90; cardGrad.Parent = card
	UI.Icon({ Parent = card, Icon = IconConfig.ModeIcon[modeId], Size = UDim2.fromScale(0.6, 0.36), Position = UDim2.fromScale(0.2, 0.02) })
	UI.Label({ Parent = card, Text = mode.DisplayName, Font = UI.Fonts.Title, Color = accent, Size = UDim2.fromScale(0.9, 0.11), Position = UDim2.fromScale(0.05, 0.38), MaxSize = 38, StrokeSize = 2.5 })
	local teamText = mode.TeamBased and string.format("%d-%d players  -  up to %dv%d", mode.MinPlayers, mode.MaxPlayers, mode.MaxPerTeam, mode.MaxPerTeam) or "2 players  -  free-for-all"
	UI.Label({ Parent = card, Text = teamText, Font = UI.Fonts.Bold, Color = C.Subtext, Size = UDim2.fromScale(0.9, 0.07), Position = UDim2.fromScale(0.05, 0.5), MaxSize = 18 })
	UI.Label({ Parent = card, Text = mode.Description, Font = UI.Fonts.Body, Color = C.Text, Size = UDim2.fromScale(0.86, 0.14), Position = UDim2.fromScale(0.07, 0.58), MaxSize = 18 })
	local maps = {}
	for _, id in ipairs(MapConfig.GetMapsForMode(modeId)) do table.insert(maps, MapConfig.Maps[id].DisplayName) end
	UI.Label({ Parent = card, Text = table.concat(maps, "  -  "), Font = UI.Fonts.Bold, Color = C.Subtext, Size = UDim2.fromScale(0.86, 0.06), Position = UDim2.fromScale(0.07, 0.73), MaxSize = 14 })
	local q = UI.Button({ Parent = card, Name = "Queue", Text = "QUEUE", Size = UDim2.fromScale(0.8, 0.13), Position = UDim2.fromScale(0.5, 0.92), AnchorPoint = Vector2.new(0.5, 1), Accent = accent, MaxSize = 28 })
	q.MouseButton1Click:Connect(function()
		QueueRequest:FireServer("Join", modeId)
		playDim.Visible = false
		openPanel = nil
	end)
end

---------------------------------------------------------------- CHARACTERS
local charGui = UI.ScreenGui("CharacterUI", playerGui, 10)
local charDim, charBody = makeModal(charGui, "CHARACTERS", C.Magenta)
local grid = Instance.new("Frame"); grid.Name = "Grid"; grid.BackgroundTransparency = 1; grid.Size = UDim2.fromScale(0.5, 1); grid.Parent = charBody
local gl = Instance.new("UIGridLayout"); gl.CellSize = UDim2.fromScale(0.31, 0.46); gl.CellPadding = UDim2.fromScale(0.03, 0.04); gl.SortOrder = Enum.SortOrder.LayoutOrder; gl.Parent = grid
local detail = UI.Panel({ Parent = charBody, Name = "Detail", Size = UDim2.fromScale(0.47, 1), Position = UDim2.fromScale(0.53, 0), Color = C.Panel, Stroke = C.Magenta })
local dName = UI.Label({ Parent = detail, Text = "", Font = UI.Fonts.Title, Size = UDim2.fromScale(0.9, 0.11), Position = UDim2.fromScale(0.05, 0.03), AlignX = Enum.TextXAlignment.Left, MaxSize = 40 })
local dMeta = UI.Label({ Parent = detail, Text = "", Font = UI.Fonts.Bold, Color = C.Subtext, Size = UDim2.fromScale(0.9, 0.07), Position = UDim2.fromScale(0.05, 0.14), AlignX = Enum.TextXAlignment.Left, MaxSize = 18, Rich = true })
local dDesc = UI.Label({ Parent = detail, Text = "", Font = UI.Fonts.Body, Size = UDim2.fromScale(0.9, 0.07), Position = UDim2.fromScale(0.05, 0.22), AlignX = Enum.TextXAlignment.Left, MaxSize = 18 })
local dAbil = UI.Label({ Parent = detail, Text = "", Font = UI.Fonts.Body, Size = UDim2.fromScale(0.9, 0.48), Position = UDim2.fromScale(0.05, 0.3), AlignX = Enum.TextXAlignment.Left, AlignY = Enum.TextYAlignment.Top, MaxSize = 17, Rich = true })
local dStatus = UI.Label({ Parent = detail, Text = "", Font = UI.Fonts.Title, Size = UDim2.fromScale(0.5, 0.08), Position = UDim2.fromScale(0.05, 0.86), AlignX = Enum.TextXAlignment.Left, MaxSize = 22 })
local dAction = UI.Button({ Parent = detail, Name = "Action", Text = "SELECT", Size = UDim2.fromScale(0.38, 0.1), Position = UDim2.fromScale(0.95, 0.95), AnchorPoint = Vector2.new(1, 1), Accent = C.Magenta, MaxSize = 24 })
local viewedHero = HeroConfig.HeroOrder[1]

local function isUnlocked(id: string): boolean
	return table.find(profile.UnlockedHeroes, id) ~= nil
end

local function showHero(id: string)
	viewedHero = id
	local h = HeroConfig.Heroes[id]
	dName.Text = h.DisplayName; dName.TextColor3 = h.Color
	dMeta.Text = string.format("%s  |  %s  |  HP %d  |  SPD %d", string.upper(h.Role), h.Weapon, h.Stats.Health, h.Stats.WalkSpeed)
	dDesc.Text = h.Description
	local a = h.Abilities
	dAbil.Text = string.format(
		"<b>LMB  %s</b>\n%s\n\n<b>SHIFT  %s</b>  (%ds)\n%s\n\n<b>E  %s</b>  (%ds)\n%s\n\n<b>Q  %s</b>  (ULT)\n%s",
		a.Primary.Name, a.Primary.Text, a.Dash.Name, a.Dash.Cooldown, a.Dash.Text, a.Skill.Name, a.Skill.Cooldown, a.Skill.Text, a.Ultimate.Name, a.Ultimate.Text)
	if isUnlocked(id) then
		dStatus.Text = (profile.SelectedHero == id) and "SELECTED" or "UNLOCKED"
		dStatus.TextColor3 = C.Green
		dAction.Text = "SELECT"
	else
		dStatus.Text = string.format("LOCKED  -  %d TOKENS", h.Price)
		dStatus.TextColor3 = C.Gold
		dAction.Text = "BUY"
	end
end

for i, id in ipairs(HeroConfig.HeroOrder) do
	local h = HeroConfig.Heroes[id]
	local card = UI.Button({ Parent = grid, Name = id, Text = "", Accent = h.Color, Color = C.Panel })
	card.LayoutOrder = i
	local swatch = UI.Panel({ Parent = card, Size = UDim2.fromScale(1, 0.55), Color = h.Color, Transparency = 0.35, Corner = 6 })
	swatch.Active = false
	UI.Label({ Parent = swatch, Text = string.sub(h.DisplayName, 1, 1), Font = UI.Fonts.Title, Size = UDim2.fromScale(1, 0.9), MaxSize = 60 })
	UI.Label({ Parent = card, Text = h.DisplayName, Font = UI.Fonts.Title, Size = UDim2.fromScale(1, 0.2), Position = UDim2.fromScale(0, 0.6), MaxSize = 24 })
	UI.Label({ Parent = card, Name = "Sub", Text = "", Font = UI.Fonts.Bold, Color = C.Subtext, Size = UDim2.fromScale(1, 0.16), Position = UDim2.fromScale(0, 0.82), MaxSize = 14 })
	card.MouseButton1Click:Connect(function() showHero(id) end)
end

local function refreshCards()
	for _, id in ipairs(HeroConfig.HeroOrder) do
		local h = HeroConfig.Heroes[id]
		local card = grid:FindFirstChild(id)
		local sub = card and card:FindFirstChild("Sub")
		if sub then
			if profile.SelectedHero == id then
				sub.Text = "SELECTED"
			elseif isUnlocked(id) then
				sub.Text = string.upper(h.Role)
			else
				sub.Text = "LOCKED  " .. h.Price
			end
		end
	end
end

dAction.MouseButton1Click:Connect(function()
	if isUnlocked(viewedHero) then
		-- the server validates ownership and sets the "Hero" attribute (saving arrives in Phase 5)
		SelectHero:FireServer(viewedHero)
	else
		toast("Hero purchasing unlocks in Phase 5 (token economy)", C.Gold)
	end
end)

---------------------------------------------------------------- SHOP (opened by Isaac)
local shopGui = UI.ScreenGui("ShopUI", playerGui, 10)
local shopDim, shopBody = makeModal(shopGui, "ISAAC'S ARMORY", C.Gold)
local tabs = { "HEROES", "WEAPON SKINS", "TOKENS" }
local shopContent = UI.Panel({ Parent = shopBody, Name = "Content", Size = UDim2.fromScale(1, 0.82), Position = UDim2.fromScale(0, 0.18), Color = C.Panel, Stroke = C.Gold })
local shopText = UI.Label({ Parent = shopContent, Text = "", Font = UI.Fonts.Bold, Size = UDim2.fromScale(0.92, 0.86), Position = UDim2.fromScale(0.04, 0.07), AlignX = Enum.TextXAlignment.Left, AlignY = Enum.TextYAlignment.Top, MaxSize = 22, Rich = true })
local function showTab(name: string)
	if name == "HEROES" then
		local lines = {}
		for _, id in ipairs(HeroConfig.HeroOrder) do
			local h = HeroConfig.Heroes[id]
			table.insert(lines, string.format("%s  -  %s  -  %s", h.DisplayName, h.Role, isUnlocked(id) and "<font color=\"#50ffa0\">OWNED</font>" or ("<font color=\"#ffc83c\">" .. h.Price .. " TOKENS</font>")))
		end
		shopText.Text = table.concat(lines, "\n") .. "\n\n<font color=\"#8c96b9\">Purchasing goes live in Phase 5.</font>"
	elseif name == "WEAPON SKINS" then
		shopText.Text = "Cosmetic weapon skins (Robux only, no gameplay advantage).\n\n<font color=\"#8c96b9\">Catalog, previews and secure purchases go live in Phase 6.</font>"
	else
		shopText.Text = string.format("Balance: <font color=\"#ffc83c\">%d TOKENS</font>\n\nEarn tokens by completing and winning matches.\n\n<font color=\"#8c96b9\">Token rewards go live in Phase 5.</font>", profile.Tokens)
	end
end
for i, name in ipairs(tabs) do
	local t = UI.Button({ Parent = shopBody, Name = name, Text = name, Size = UDim2.fromScale(0.3, 0.13), Position = UDim2.fromScale((i - 1) * 0.35, 0), Accent = C.Gold, MaxSize = 24 })
	t.MouseButton1Click:Connect(function() showTab(name) end)
end

---------------------------------------------------------------- MATCH HUD + RESULT
local matchGui = UI.ScreenGui("MatchUI", playerGui, 4)
matchGui.Enabled = false
local hudTop = UI.Panel({ Parent = matchGui, Name = "TopBar", Size = UDim2.fromScale(0.36, 0.1), Position = UDim2.fromScale(0.5, 0.02), AnchorPoint = Vector2.new(0.5, 0), Stroke = C.Cyan, Transparency = 0.2 })
local alphaScore = UI.Label({ Parent = hudTop, Text = "0", Font = UI.Fonts.Title, Color = GameConfig.Teams.Alpha.Color, Size = UDim2.fromScale(0.2, 0.7), Position = UDim2.fromScale(0.03, 0.15), MaxSize = 40 })
local bravoScore = UI.Label({ Parent = hudTop, Text = "0", Font = UI.Fonts.Title, Color = GameConfig.Teams.Bravo.Color, Size = UDim2.fromScale(0.2, 0.7), Position = UDim2.fromScale(0.77, 0.15), MaxSize = 40 })
local timerLabel = UI.Label({ Parent = hudTop, Text = "0:00", Font = UI.Fonts.Title, Size = UDim2.fromScale(0.5, 0.5), Position = UDim2.fromScale(0.25, 0.05), MaxSize = 34 })
local mapLabel = UI.Label({ Parent = hudTop, Text = "", Font = UI.Fonts.Bold, Color = C.Subtext, Size = UDim2.fromScale(0.5, 0.35), Position = UDim2.fromScale(0.25, 0.58), MaxSize = 16 })
local teamTag = UI.Label({ Parent = matchGui, Text = "", Font = UI.Fonts.Title, Size = UDim2.fromScale(0.2, 0.04), Position = UDim2.fromScale(0.5, 0.13), AnchorPoint = Vector2.new(0.5, 0), MaxSize = 22 })
local centerMsg = UI.Label({ Parent = matchGui, Text = "", Font = UI.Fonts.Title, Size = UDim2.fromScale(0.6, 0.1), Position = UDim2.fromScale(0.5, 0.32), AnchorPoint = Vector2.new(0.5, 0.5), MaxSize = 64, Color = C.Cyan })

local resultGui = UI.ScreenGui("MatchResultUI", playerGui, 20)
resultGui.Enabled = false
local resultBg = Instance.new("Frame"); resultBg.Size = UDim2.fromScale(1, 1); resultBg.BackgroundColor3 = Color3.new(0, 0, 0); resultBg.BackgroundTransparency = 0.35; resultBg.Parent = resultGui
local resultTitle = UI.Label({ Parent = resultBg, Text = "VICTORY", Font = UI.Fonts.Title, Size = UDim2.fromScale(0.6, 0.16), Position = UDim2.fromScale(0.5, 0.36), AnchorPoint = Vector2.new(0.5, 0.5), MaxSize = 110 })
local resultSub = UI.Label({ Parent = resultBg, Text = "", Font = UI.Fonts.Bold, Color = C.Subtext, Size = UDim2.fromScale(0.6, 0.18), Position = UDim2.fromScale(0.5, 0.56), AnchorPoint = Vector2.new(0.5, 0.5), MaxSize = 26 })

local currentMatch: { [string]: any }? = nil

-- Per-map lighting: Lighting properties plus post effects (bloom / atmosphere) so bright maps don't blow out.
local EFFECT_CLASSES = { Bloom = "BloomEffect", Atmosphere = "Atmosphere", ColorCorrection = "ColorCorrectionEffect" }
local function applyLighting(settings: { [string]: any })
	for k, v in pairs(settings) do
		if k == "Effects" then
			for name, props in pairs(v) do
				local effect = Lighting:FindFirstChildOfClass(EFFECT_CLASSES[name])
				if effect then
					for prop, value in pairs(props) do
						pcall(function() (effect :: any)[prop] = value end)
					end
				end
			end
		else
			pcall(function() (Lighting :: any)[k] = v end)
		end
	end
end

local function setInMatch(state: boolean)
	inMatch = state
	lobbyGui.Enabled = not state
	charGui.Enabled = not state
	shopGui.Enabled = not state
	if kitShop then kitShop.Enabled = not state end
	matchGui.Enabled = state
	local hb = playerGui:FindFirstChild("HealthBar")
	if hb then hb.Enabled = state end -- Premium Health Bar kit: matches only
	if state and openPanel then (openPanel :: GuiObject).Visible = false; openPanel = nil end
end

local function renderScores(data)
	if data.Scores then
		alphaScore.Text = tostring(data.Scores.Alpha or 0)
		bravoScore.Text = tostring(data.Scores.Bravo or 0)
	end
end

MatchState.OnClientEvent:Connect(function(data)
	if typeof(data) ~= "table" then return end
	if data.State == "PreMatch" then
		currentMatch = data
		setInMatch(true)
		resultGui.Enabled = false
		queueBar.Visible = false
		local mapInfo = MapConfig.Maps[data.MapId]
		if mapInfo then applyLighting(mapInfo.Lighting) end
		local mode = GameConfig.Modes[data.Mode]
		local teamBased = mode ~= nil and mode.TeamBased
		alphaScore.Visible = teamBased
		bravoScore.Visible = teamBased
		mapLabel.Text = string.format("%s  |  %s", mapInfo and mapInfo.DisplayName or "?", mode and mode.DisplayName or "")
		local team = data.YourTeam or ""
		local tcfg = GameConfig.Teams[team]
		teamTag.Text = tcfg and ("TEAM " .. tcfg.Name) or "FREE FOR ALL"
		teamTag.TextColor3 = tcfg and tcfg.Color or C.Gold
		renderScores(data)
		centerMsg.Text = "GET READY"
	elseif data.State == "Live" then
		currentMatch = data
		renderScores(data)
		if data.Event == nil then
			centerMsg.Text = "FIGHT!"
			task.delay(1.5, function() if centerMsg.Text == "FIGHT!" then centerMsg.Text = "" end end)
		end
	elseif data.State == "Ended" then
		currentMatch = nil
		centerMsg.Text = ""
		resultGui.Enabled = true
		local won = data.Winner ~= nil and data.Winner == data.YourTeam
		if data.Winner == nil then
			resultTitle.Text = "DRAW"; resultTitle.TextColor3 = C.Gold
		elseif won then
			resultTitle.Text = "VICTORY"; resultTitle.TextColor3 = C.Cyan
		else
			resultTitle.Text = "DEFEAT"; resultTitle.TextColor3 = C.Red
		end
		local reasonText = ({ TimeUp = "Time expired", Forfeit = "Opponents left the match", Empty = "Match abandoned", KillLimit = "Kill limit reached" })[data.Reason] or tostring(data.Reason)
		local mode = GameConfig.Modes[data.Mode]
		local scoreLine = ""
		if mode and mode.TeamBased then
			local tk = data.TeamKills or {}
			scoreLine = string.format("ALPHA %d  -  %d BRAVO   (eliminations %d - %d)", data.Scores.Alpha or 0, data.Scores.Bravo or 0, tk.Alpha or 0, tk.Bravo or 0)
		end
		local mine = data.Stats and data.Stats[player.DisplayName]
		local statLine = mine and string.format("YOUR STATS:  %d kills  /  %d deaths  /  %d assists", mine.Kills, mine.Deaths, mine.Assists) or ""
		resultSub.Text = string.format("%s\n%s\n%s\nReturning to lobby...", reasonText, scoreLine, statLine)
	elseif data.State == "Lobby" then
		currentMatch = nil
		resultGui.Enabled = false
		setInMatch(false)
		applyLighting(MapConfig.LobbyLighting)
	end
end)

---------------------------------------------------------------- QUEUE STATUS
QueueUpdate.OnClientEvent:Connect(function(data)
	if typeof(data) ~= "table" then return end
	queueState = data
	if data.InQueue then
		queueBar.Visible = true
		playBtn.Text = "IN QUEUE"
	else
		queueBar.Visible = false
		playBtn.Text = "PLAY"
		if data.MatchFound then toast("Match found! Deploying...", C.Green) end
	end
end)

RunService.Heartbeat:Connect(function()
	if queueState.InQueue then
		local mode = GameConfig.Modes[queueState.Mode]
		local modeName = mode and mode.DisplayName or ""
		if queueState.CountdownEndsAt then
			local left = math.max(0, math.ceil(queueState.CountdownEndsAt - serverNow()))
			queueTitle.Text = string.format("MATCH STARTING  %ds", left)
		else
			queueTitle.Text = "SEARCHING..."
		end
		queueInfo.Text = string.format("%s  |  %d / %d players (min %d)", modeName, queueState.Count or 0, queueState.Max or 0, queueState.Needed or 0)
	end
	if inMatch and currentMatch and currentMatch.EndsAt then
		local left = math.max(0, currentMatch.EndsAt - serverNow())
		timerLabel.Text = string.format("%d:%02d", math.floor(left / 60), math.floor(left % 60))
		if currentMatch.State == "PreMatch" then centerMsg.Text = string.format("GET READY  %d", math.ceil(left)) end
	end
end)

---------------------------------------------------------------- BUTTON WIRING
playBtn.MouseButton1Click:Connect(function()
	if queueState.InQueue then toast("Already in queue - cancel first to switch modes", C.Cyan) return end
	showModal(playDim)
end)
cancelBtn.MouseButton1Click:Connect(function() QueueRequest:FireServer("Leave") end)
shopBtn.MouseButton1Click:Connect(function()
	ShopNavigate:FireServer()
	toast("Isaac is at the Armory - walk up and press F", C.Gold)
end)
charBtn.MouseButton1Click:Connect(function()
	showHero(viewedHero)
	showModal(charDim)
end)
settingsBtn.MouseButton1Click:Connect(function() toast("Settings arrive in a later phase", C.Subtext) end)
plusBtn.MouseButton1Click:Connect(function() toast("Token packs arrive with Robux purchases (Phase 6)", C.Gold) end)
-- Isaac's shop window uses the Clean Shop GUI kit (UI by @roary16), filled with hero offers.
local kitShop = playerGui:WaitForChild("IsaacShopUI", 10)
local kitFrame = kitShop and kitShop:FindFirstChild("ShopFrame")
local kitOpenSize = kitFrame and kitFrame.Size
local kitPopulated = false
if kitFrame then
	-- hide PLAY + dock while the shop window is open so they don't overlap
	kitFrame:GetPropertyChangedSignal("Visible"):Connect(function()
		playBtn.Visible = not kitFrame.Visible
		dock.Visible = not kitFrame.Visible
	end)
end

local function populateKitShop()
	if not kitFrame then return end
	local items = kitFrame:FindFirstChild("Items")
	local template = items and items:FindFirstChild("item1")
	if not template then return end
	template = template:Clone()
	for _, c in ipairs(items:GetChildren()) do
		if c:IsA("Frame") and c.Name:match("^item") then c:Destroy() end
	end
	kitFrame.ShopLabel.Text = "Isaac's Armory"
	for i, id in ipairs(HeroConfig.HeroOrder) do
		local h = HeroConfig.Heroes[id]
		local item = template:Clone()
		item.Name = "hero_" .. id
		item.LayoutOrder = i
		item.TextLabel.Text = h.DisplayName
		for _, img in ipairs(item:GetChildren()) do
			if img:IsA("ImageLabel") and img.Image:find("GuiImagePlaceholder") then
				img.Image = IconConfig.Get("Characters")
				img.ImageColor3 = Color3.new(1, 1, 1):Lerp(h.Color, 0.45)
				img.BackgroundTransparency = 1
			end
		end
		local buy = item:FindFirstChild("Buy") :: TextButton
		if isUnlocked(id) then
			buy.Text = "OWNED"
		else
			buy.Text = h.Price .. " Tokens"
		end
		buy.MouseButton1Click:Connect(function()
			if isUnlocked(id) then
				toast(h.DisplayName .. " is already yours - select it in Heroes", C.Green)
			else
				toast("Hero purchasing unlocks in Phase 5 (token economy)", C.Gold)
			end
		end)
		item.Parent = items
	end
	if not kitFrame:FindFirstChild("Credit") then
		local credit = UI.Label({ Parent = kitFrame, Name = "Credit", Text = "Shop UI by @roary16", Font = UI.Fonts.Body, Color = C.Subtext, Size = UDim2.fromScale(0.4, 0.04), Position = UDim2.fromScale(0.58, 0.95), MaxSize = 12, NoStroke = true })
		credit.TextXAlignment = Enum.TextXAlignment.Right
	end
	kitPopulated = true
end

OpenShop.OnClientEvent:Connect(function()
	if kitFrame and kitOpenSize then
		if not kitPopulated then populateKitShop() end
		kitFrame.Size = UDim2.new(0, 0, 0, 0)
		kitFrame.Visible = true
		local tween = TweenService:Create(kitFrame, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = kitOpenSize })
		tween.Completed:Connect(function()
			-- the kit uses fixed 200px cells; fit 3 hero cards per row on any screen size
			local items = kitFrame:FindFirstChild("Items")
			local grid = items and items:FindFirstChildOfClass("UIGridLayout")
			if grid and items.AbsoluteSize.X > 0 then
				local cell = math.floor((items.AbsoluteSize.X - 30) / 3)
				grid.CellSize = UDim2.fromOffset(cell, cell)
			end
		end)
		tween:Play()
	else
		showTab("HEROES")
		showModal(shopDim)
	end
end)

---------------------------------------------------------------- INIT
local ok, data = pcall(function() return GetLobbyData:InvokeServer() end)
if ok and typeof(data) == "table" then
	profile = data
end
local function onHeroAttr()
	local h = player:GetAttribute("Hero")
	if typeof(h) == "string" and HeroConfig.Heroes[h] then
		local changed = profile.SelectedHero ~= h
		profile.SelectedHero = h
		refreshProfile()
		refreshCards()
		showHero(viewedHero)
		if changed then toast(HeroConfig.Heroes[h].DisplayName .. " selected", C.Magenta) end
	end
end
player:GetAttributeChangedSignal("Hero"):Connect(onHeroAttr)

refreshProfile()
refreshCards()
showHero(viewedHero)
if player:GetAttribute("Hero") then profile.SelectedHero = player:GetAttribute("Hero"); refreshProfile(); refreshCards() end
applyLighting(MapConfig.LobbyLighting)
