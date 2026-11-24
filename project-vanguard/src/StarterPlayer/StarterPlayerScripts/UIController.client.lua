-- UIController: builds and drives every Phase 1 interface.
-- ScreenGuis created: LobbyUI, CharacterUI, ShopUI, MatchUI, MatchResultUI, NotifyUI.
-- The client only REQUESTS actions (queue, shop teleport); the server decides everything.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local MarketplaceService = game:GetService("MarketplaceService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameConfig = require(Modules.GameConfig)
local MapConfig = require(Modules.MapConfig)
local HeroConfig = require(Modules.HeroConfig)
local UI = require(Modules.UIStyle)
local IconConfig = require(Modules.IconConfig)
local RankConfig = require(Modules.RankConfig)
local RankBadge = require(Modules.RankBadge)
local ProductConfig = require(Modules.ProductConfig)
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
local RankUpdate = Remotes:WaitForChild("RankUpdate")
local GetMatchHistory = Remotes:WaitForChild("GetMatchHistory")
local BuyHero = Remotes:WaitForChild("BuyHero")
local BuyHeroRobux = Remotes:WaitForChild("BuyHeroRobux")
local ClaimDaily = Remotes:WaitForChild("ClaimDaily")
local TokensEarned = Remotes:WaitForChild("TokensEarned")

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
local rankBadge = UI.Icon({ Parent = header, Icon = "Ranked", Size = UDim2.fromScale(0.26, 1.15), Position = UDim2.fromScale(0.01, -0.08) })
local historyHit = Instance.new("TextButton") -- click the profile card to open match history
historyHit.Name = "OpenHistory"; historyHit.Text = ""; historyHit.BackgroundTransparency = 1; historyHit.Size = UDim2.fromScale(1, 1); historyHit.ZIndex = 5; historyHit.Parent = header
-- 3D rank badge (gently sways); the flat Ranked icon only shows until the rank has loaded
local profileBadge = RankBadge.Viewport({ Parent = header, Name = "RankBadge3D", Size = UDim2.fromScale(0.3, 1.3), Position = UDim2.fromScale(-0.01, -0.15), ZIndex = 3, Spin = true })
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

local function hex(c: Color3): string
	return string.format("#%02x%02x%02x", math.floor(c.R * 255), math.floor(c.G * 255), math.floor(c.B * 255))
end

-- rank shown everywhere comes from server-set attributes (Rating), never from the client
local function currentRank(): (string, Color3, string?)
	local rating = player:GetAttribute("Rating")
	if typeof(rating) ~= "number" then return "UNRANKED", C.Subtext, nil end
	local info = RankConfig.Get(rating)
	return info.Name, info.Tier.Color, info.Tier.Icon
end

local function refreshProfile()
	local rankName, rankColor, rankIcon = currentRank()
	profileLabel.Text = string.format("<font color=\"%s\">%s</font>  -  <font color=\"#00dcff\">%s</font>", hex(rankColor), rankName, string.upper(profile.SelectedHero))
	local rating = player:GetAttribute("Rating")
	local tierId = typeof(rating) == "number" and RankConfig.Get(rating).Tier.Id or nil
	profileBadge.Set(tierId)
	rankBadge.Visible = tierId == nil
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
	if modeId == "Ranked" then
		local yourRank = UI.Label({ Parent = card, Name = "YourRank", Text = "", Font = UI.Fonts.Title, Color = C.Gold, Size = UDim2.fromScale(0.86, 0.055), Position = UDim2.fromScale(0.07, 0.785), MaxSize = 18, Rich = true })
		local function updateRankLine()
			local rating = player:GetAttribute("Rating")
			if typeof(rating) == "number" then
				local info = RankConfig.Get(rating)
				yourRank.Text = string.format("YOUR RANK: <font color=\"%s\">%s</font>  (%d RP)", hex(info.Tier.Color), info.Name, rating)
			else
				yourRank.Text = "YOUR RANK: loading..."
			end
		end
		player:GetAttributeChangedSignal("Rating"):Connect(updateRankLine)
		updateRankLine()
	end
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

-- Buying a hero with tokens: click once to see the price, click again within 3s to confirm.
-- The server re-checks everything (price, balance, ownership) and saves the unlock.
local confirmAt: { [string]: number } = {}
local buying = false
local function purchaseHero(id: string)
	local h = HeroConfig.Heroes[id]
	if isUnlocked(id) then
		SelectHero:FireServer(id) -- the server validates ownership and sets the "Hero" attribute
		return
	end
	if buying then return end
	local tokens = profile.Tokens
	if tokens < h.Price then
		toast(string.format("You need %d more tokens for %s", h.Price - tokens, h.DisplayName), C.Gold)
		return
	end
	if not confirmAt[id] or os.clock() - confirmAt[id] > 3 then
		confirmAt[id] = os.clock()
		toast(string.format("Click again to unlock %s for %d tokens", h.DisplayName, h.Price), C.Gold)
		return
	end
	confirmAt[id] = nil
	buying = true
	local ok, res = pcall(function() return BuyHero:InvokeServer(id) end)
	buying = false
	if ok and typeof(res) == "table" and res.Ok then
		toast("HERO UNLOCKED: " .. h.DisplayName, h.Color)
	else
		toast((ok and typeof(res) == "table" and res.Reason) or "Purchase failed - try again", C.Red)
	end
end

dAction.MouseButton1Click:Connect(function()
	purchaseHero(viewedHero)
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
		shopText.Text = table.concat(lines, "\n") .. "\n\n<font color=\"#8c96b9\">Buy heroes from the Heroes menu.</font>"
	elseif name == "WEAPON SKINS" then
		shopText.Text = "Cosmetic weapon skins (Robux only, no gameplay advantage).\n\n<font color=\"#8c96b9\">Catalog, previews and secure purchases go live in Phase 6.</font>"
	else
		shopText.Text = string.format("Balance: <font color=\"#ffc83c\">%d TOKENS</font>\n\nEarn tokens by finishing matches (+%d), winning (+%d), MVP (+%d) and your daily login streak.", profile.Tokens, GameConfig.Progression.Rewards.Complete, GameConfig.Progression.Rewards.Win, GameConfig.Progression.Rewards.MVP)
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
-- Hold the Core meter: Alpha fills from the left, Bravo from the right; status line underneath
local objFrame = UI.Panel({ Parent = matchGui, Name = "CoreMeter", Size = UDim2.fromScale(0.36, 0.022), Position = UDim2.fromScale(0.5, 0.127), AnchorPoint = Vector2.new(0.5, 0), Color = C.Bg, Transparency = 0.25, Corner = 6 })
objFrame.Visible = false
local alphaHalf = Instance.new("Frame"); alphaHalf.BackgroundTransparency = 1; alphaHalf.Size = UDim2.fromScale(0.495, 1); alphaHalf.Parent = objFrame
local bravoHalf = Instance.new("Frame"); bravoHalf.BackgroundTransparency = 1; bravoHalf.Size = UDim2.fromScale(0.495, 1); bravoHalf.Position = UDim2.fromScale(0.505, 0); bravoHalf.Parent = objFrame
local alphaFill = UI.Panel({ Parent = alphaHalf, Name = "AlphaFill", Size = UDim2.fromScale(0, 1), Color = GameConfig.Teams.Alpha.Color, Transparency = 0, Corner = 6 })
local bravoFill = UI.Panel({ Parent = bravoHalf, Name = "BravoFill", Size = UDim2.fromScale(0, 1), Position = UDim2.fromScale(1, 0), AnchorPoint = Vector2.new(1, 0), Color = GameConfig.Teams.Bravo.Color, Transparency = 0, Corner = 6 })
local objStatus = UI.Label({ Parent = matchGui, Name = "CoreStatus", Text = "", Font = UI.Fonts.Title, Size = UDim2.fromScale(0.3, 0.032), Position = UDim2.fromScale(0.5, 0.152), AnchorPoint = Vector2.new(0.5, 0), MaxSize = 22 })
objStatus.Visible = false
local teamTag = UI.Label({ Parent = matchGui, Text = "", Font = UI.Fonts.Title, Size = UDim2.fromScale(0.2, 0.035), Position = UDim2.fromScale(0.5, 0.188), AnchorPoint = Vector2.new(0.5, 0), MaxSize = 20 })
local centerMsg = UI.Label({ Parent = matchGui, Text = "", Font = UI.Fonts.Title, Size = UDim2.fromScale(0.6, 0.1), Position = UDim2.fromScale(0.5, 0.32), AnchorPoint = Vector2.new(0.5, 0.5), MaxSize = 64, Color = C.Cyan })

local resultGui = UI.ScreenGui("MatchResultUI", playerGui, 20)
resultGui.Enabled = false
local resultBg = Instance.new("Frame"); resultBg.Size = UDim2.fromScale(1, 1); resultBg.BackgroundColor3 = Color3.new(0, 0, 0); resultBg.BackgroundTransparency = 0.35; resultBg.Parent = resultGui
local resultTitle = UI.Label({ Parent = resultBg, Text = "VICTORY", Font = UI.Fonts.Title, Size = UDim2.fromScale(0.6, 0.16), Position = UDim2.fromScale(0.5, 0.36), AnchorPoint = Vector2.new(0.5, 0.5), MaxSize = 110 })
local resultSub = UI.Label({ Parent = resultBg, Text = "", Font = UI.Fonts.Bold, Color = C.Subtext, Size = UDim2.fromScale(0.6, 0.16), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), MaxSize = 24 })
local resultRank = UI.Label({ Parent = resultBg, Name = "RankChange", Text = "", Font = UI.Fonts.Title, Size = UDim2.fromScale(0.6, 0.05), Position = UDim2.fromScale(0.5, 0.715), AnchorPoint = Vector2.new(0.5, 0.5), MaxSize = 32, Rich = true, StrokeSize = 2.5 })
local resultBadge = RankBadge.Viewport({ Parent = resultBg, Name = "RankBadge3D", Size = UDim2.fromScale(0.12, 0.11), Position = UDim2.fromScale(0.5, 0.635), AnchorPoint = Vector2.new(0.5, 0.5), Spin = true })
resultBadge.Set(nil)
-- MVP card
local mvpCard = UI.Panel({ Parent = resultBg, Name = "MVP", Size = UDim2.fromScale(0.34, 0.17), Position = UDim2.fromScale(0.5, 0.84), AnchorPoint = Vector2.new(0.5, 0.5), Color = C.Bg, Transparency = 0.1, Stroke = C.Gold, StrokeThickness = 3, Corner = 14 })
local mvpAspect = Instance.new("UIAspectRatioConstraint"); mvpAspect.AspectRatio = 3.6; mvpAspect.Parent = mvpCard
local mvpPhoto = Instance.new("ImageLabel"); mvpPhoto.Name = "Photo"; mvpPhoto.BackgroundColor3 = C.Panel; mvpPhoto.Size = UDim2.fromScale(0.24, 0.84); mvpPhoto.Position = UDim2.fromScale(0.03, 0.08); mvpPhoto.Parent = mvpCard
UI.Corner(mvpPhoto, 12)
UI.Label({ Parent = mvpCard, Text = "MVP", Font = UI.Fonts.Title, Color = C.Gold, Size = UDim2.fromScale(0.25, 0.3), Position = UDim2.fromScale(0.3, 0.06), AlignX = Enum.TextXAlignment.Left, MaxSize = 30, StrokeSize = 2.5 })
local mvpName = UI.Label({ Parent = mvpCard, Text = "", Font = UI.Fonts.Title, Size = UDim2.fromScale(0.52, 0.28), Position = UDim2.fromScale(0.3, 0.34), AlignX = Enum.TextXAlignment.Left, MaxSize = 30, Rich = true, StrokeSize = 2 })
local mvpStats = UI.Label({ Parent = mvpCard, Text = "", Font = UI.Fonts.Bold, Color = C.Subtext, Size = UDim2.fromScale(0.68, 0.24), Position = UDim2.fromScale(0.3, 0.66), AlignX = Enum.TextXAlignment.Left, MaxSize = 20 })
UI.Icon({ Parent = mvpCard, Icon = "Trophy", Size = UDim2.fromScale(0.16, 0.6), Position = UDim2.fromScale(0.98, 0.04), AnchorPoint = Vector2.new(1, 0), ZIndex = 3 })
local bannerScale = Instance.new("UIScale"); bannerScale.Parent = resultTitle

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
		local mode = GameConfig.Modes[data.Mode]
		local pct = (mode and mode.TeamBased) and "%" or ""
		alphaScore.Text = tostring(data.Scores.Alpha or 0) .. pct
		bravoScore.Text = tostring(data.Scores.Bravo or 0) .. pct
	end
end

-- live core meter from server attributes
local function renderCore()
	local a = player:GetAttribute("ObjAlpha")
	local b = player:GetAttribute("ObjBravo")
	local state = player:GetAttribute("ObjState")
	local show = typeof(a) == "number" and typeof(b) == "number"
	objFrame.Visible = show
	objStatus.Visible = show
	if not show then return end
	alphaFill.Size = UDim2.fromScale(a / 100, 1)
	bravoFill.Size = UDim2.fromScale(b / 100, 1)
	alphaScore.Text = a .. "%"
	bravoScore.Text = b .. "%"
	local mine = player:GetAttribute("Team")
	local onPoint = player:GetAttribute("ObjOnPoint") == true
	if state == "Contested" then
		objStatus.Text = "CORE CONTESTED"; objStatus.TextColor3 = C.Gold
	elseif state == mine then
		objStatus.Text = onPoint and "CAPTURING THE CORE" or "YOUR TEAM HOLDS THE CORE"; objStatus.TextColor3 = C.Green
	elseif state == "Alpha" or state == "Bravo" then
		objStatus.Text = "ENEMY HOLDS THE CORE"; objStatus.TextColor3 = C.Red
	else
		objStatus.Text = "CORE NEUTRAL - TAKE IT"; objStatus.TextColor3 = C.Text
	end
end
for _, attr in ipairs({ "ObjAlpha", "ObjBravo", "ObjState", "ObjOnPoint" }) do
	player:GetAttributeChangedSignal(attr):Connect(renderCore)
end

local resultBaseText = ""
TokensEarned.OnClientEvent:Connect(function(data)
	if typeof(data) ~= "table" then return end
	local line
	if typeof(data.Reason) == "string" then
		line = data.Reason
	else
		local parts = {}
		for _, l in ipairs(data.Lines or {}) do table.insert(parts, string.format("%s +%d", tostring(l[1]), tonumber(l[2]) or 0)) end
		line = string.format("TOKENS +%d   (%s)", tonumber(data.Total) or 0, table.concat(parts, ", "))
	end
	resultSub.Text = resultBaseText ~= "" and (resultBaseText .. "\n" .. line) or line
end)

local lastRankUpdate: { [string]: any }? = nil
local function renderRankLine()
	local r = lastRankUpdate
	if not r then resultRank.Text = ""; resultBadge.Set(nil); return end
	local info = RankConfig.Get(r.New)
	resultBadge.Set(info.Tier.Id)
	local sign = r.Delta >= 0 and "+" or ""
	local deltaColor = r.Delta >= 0 and "#50ffa0" or "#ff466e"
	local extra = r.Promoted and "  RANK UP!" or (r.Demoted and "  RANK DOWN" or "")
	resultRank.Text = string.format("<font color=\"%s\">%s</font>  %d RP  <font color=\"%s\">(%s%d)</font>%s", hex(info.Tier.Color), info.Name, r.New, deltaColor, sign, r.Delta, extra)
end
RankUpdate.OnClientEvent:Connect(function(data)
	if typeof(data) ~= "table" or typeof(data.New) ~= "number" or typeof(data.Delta) ~= "number" then return end
	lastRankUpdate = data
	renderRankLine()
	refreshProfile()
	if data.Promoted then toast("RANK UP! " .. tostring(data.NewRank), C.Gold) end
end)

local function showMvp(mvp: { [string]: any }?)
	mvpCard.Visible = mvp ~= nil
	if not mvp then return end
	local hero = HeroConfig.Heroes[mvp.Hero or ""]
	local teamCfg = GameConfig.Teams[mvp.Team or ""]
	local nameColor = teamCfg and teamCfg.Color or C.Gold
	local heroText = hero and ("  <font color=\"" .. hex(hero.Color) .. "\">" .. string.upper(hero.DisplayName) .. "</font>") or ""
	mvpName.Text = string.format("<font color=\"%s\">%s</font>%s", hex(nameColor), tostring(mvp.Name), heroText)
	local obj = (mvp.ObjTime or 0) > 0 and string.format("  -  %ds on core", mvp.ObjTime) or ""
	mvpStats.Text = string.format("%d / %d / %d  K/D/A%s", mvp.Kills or 0, mvp.Deaths or 0, mvp.Assists or 0, obj)
	mvpPhoto.Image = ""
	task.spawn(function()
		local ok, img = pcall(function()
			return Players:GetUserThumbnailAsync(mvp.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
		end)
		if ok then mvpPhoto.Image = img end
	end)
	UI.PopIn(mvpCard)
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
		renderCore()
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
		local endedMode = GameConfig.Modes[data.Mode]
		lastRankUpdate = nil -- the ranked result arrives a moment later via RankUpdate
		resultBadge.Set(nil)
		resultRank.Text = (endedMode and endedMode.Ranked and not data.Abandoned) and "Updating rank..." or ""
		local won = data.Winner ~= nil and data.Winner == data.YourTeam
		local winTeam = GameConfig.Teams[data.Winner or ""]
		if data.Winner == nil then
			resultTitle.Text = "DRAW"; resultTitle.TextColor3 = C.Gold
		elseif won then
			resultTitle.Text = "VICTORY"; resultTitle.TextColor3 = winTeam and winTeam.Color or C.Gold
		else
			resultTitle.Text = "DEFEAT"; resultTitle.TextColor3 = C.Red
		end
		-- banner slam-in
		bannerScale.Scale = 2.2
		TweenService:Create(bannerScale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		showMvp(data.MVP)
		renderScores(data) -- final % (the live meter attributes are cleared when the match ends)
		local reasonText = ({ TimeUp = "Time expired", Forfeit = "Opponents left the match", Empty = "Match abandoned", KillLimit = "Kill limit reached", Objective = (winTeam and winTeam.Name or "?") .. " captured the core" })[data.Reason] or tostring(data.Reason)
		local mode = GameConfig.Modes[data.Mode]
		local scoreLine = ""
		if mode and mode.TeamBased then
			local tk = data.TeamKills or {}
			scoreLine = string.format("CORE  ALPHA %d%%  -  %d%% BRAVO   (eliminations %d - %d)", data.Scores.Alpha or 0, data.Scores.Bravo or 0, tk.Alpha or 0, tk.Bravo or 0)
		end
		local mine = data.Stats and data.Stats[player.DisplayName]
		local statLine = mine and string.format("YOUR STATS:  %d kills  /  %d deaths  /  %d assists", mine.Kills, mine.Deaths, mine.Assists) or ""
		resultSub.Text = string.format("%s\n%s\n%s", reasonText, scoreLine, statLine)
		resultBaseText = resultSub.Text
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

---------------------------------------------------------------- MATCH HISTORY (click the profile card)
local historyDim, historyBody = makeModal(lobbyGui, "MATCH HISTORY", C.Magenta)
historyDim.Name = "HistoryMenu"
local historyBadge = RankBadge.Viewport({ Parent = historyBody, Name = "RankBadge3D", Size = UDim2.fromScale(0.08, 0.11), Position = UDim2.fromScale(0, -0.01), Spin = true })
local seasonLine = UI.Label({ Parent = historyBody, Name = "Season", Text = "", Font = UI.Fonts.Title, Size = UDim2.fromScale(0.9, 0.09), Position = UDim2.fromScale(0.08, 0), AlignX = Enum.TextXAlignment.Left, MaxSize = 26, Rich = true })
local historyList = Instance.new("Frame"); historyList.Name = "List"; historyList.BackgroundTransparency = 1
historyList.Size = UDim2.fromScale(1, 0.88); historyList.Position = UDim2.fromScale(0, 0.12); historyList.Parent = historyBody
local hl = Instance.new("UIListLayout"); hl.Padding = UDim.new(0.012, 0); hl.SortOrder = Enum.SortOrder.LayoutOrder; hl.Parent = historyList
local RESULT_STYLE = { W = { "WIN", C.Green }, L = { "LOSS", C.Red }, D = { "DRAW", C.Gold }, Left = { "LEFT", C.Subtext } }

local function openHistory()
	for _, c in ipairs(historyList:GetChildren()) do if c:IsA("Frame") then c:Destroy() end end
	local rating = player:GetAttribute("Rating")
	if typeof(rating) == "number" then
		local info = RankConfig.Get(rating)
		historyBadge.Set(info.Tier.Id)
		seasonLine.Text = string.format("%s  -  <font color=\"%s\">%s</font>  %d RP   <font color=\"#8c96b9\">%d W / %d L</font>", GameConfig.Ranked.SeasonName, hex(info.Tier.Color), info.Name, rating, player:GetAttribute("RankedWins") or 0, player:GetAttribute("RankedLosses") or 0)
	else
		seasonLine.Text = GameConfig.Ranked.SeasonName .. "  -  rank loading..."
	end
	showModal(historyDim)
	local ok, list = pcall(function() return GetMatchHistory:InvokeServer() end)
	if not ok or typeof(list) ~= "table" or #list == 0 then
		local empty = UI.Panel({ Parent = historyList, Size = UDim2.fromScale(1, 0.12), Color = C.Panel })
		UI.Label({ Parent = empty, Text = "No matches yet - go play!", Font = UI.Fonts.Bold, Color = C.Subtext, Size = UDim2.fromScale(1, 0.7), Position = UDim2.fromScale(0, 0.15), MaxSize = 22 })
		return
	end
	for i, e in ipairs(list) do
		local style = RESULT_STYLE[e.Result] or RESULT_STYLE.D
		local row = UI.Panel({ Parent = historyList, Name = "Row" .. i, Size = UDim2.fromScale(1, 0.088), Color = C.Panel, Transparency = 0.1, Stroke = style[2] })
		row.LayoutOrder = i
		UI.Label({ Parent = row, Text = style[1], Font = UI.Fonts.Title, Color = style[2], Size = UDim2.fromScale(0.12, 0.8), Position = UDim2.fromScale(0.01, 0.1), MaxSize = 24 })
		local mode = GameConfig.Modes[e.Mode]
		local map = MapConfig.Maps[e.Map]
		UI.Label({ Parent = row, Text = string.format("%s  -  %s", mode and mode.DisplayName or tostring(e.Mode), map and map.DisplayName or tostring(e.Map)), Font = UI.Fonts.Bold, Size = UDim2.fromScale(0.42, 0.7), Position = UDim2.fromScale(0.14, 0.15), AlignX = Enum.TextXAlignment.Left, MaxSize = 20 })
		UI.Label({ Parent = row, Text = string.format("%d / %d / %d", e.K or 0, e.D or 0, e.A or 0), Font = UI.Fonts.Bold, Color = C.Subtext, Size = UDim2.fromScale(0.16, 0.7), Position = UDim2.fromScale(0.57, 0.15), MaxSize = 20 })
		local deltaText = ""
		if typeof(e.Delta) == "number" then deltaText = string.format("<font color=\"%s\">%s%d RP</font>", e.Delta >= 0 and "#50ffa0" or "#ff466e", e.Delta >= 0 and "+" or "", e.Delta) end
		UI.Label({ Parent = row, Text = deltaText, Font = UI.Fonts.Title, Size = UDim2.fromScale(0.13, 0.7), Position = UDim2.fromScale(0.73, 0.15), MaxSize = 20, Rich = true })
		local ago = typeof(e.T) == "number" and math.max(0, os.time() - e.T) or 0
		local agoText = ago < 3600 and (math.floor(ago / 60) .. "m ago") or (ago < 86400 and (math.floor(ago / 3600) .. "h ago") or (math.floor(ago / 86400) .. "d ago"))
		UI.Label({ Parent = row, Text = agoText, Font = UI.Fonts.Bold, Color = C.Subtext, Size = UDim2.fromScale(0.12, 0.6), Position = UDim2.fromScale(0.87, 0.2), MaxSize = 16 })
	end
end
historyHit.MouseButton1Click:Connect(openHistory)

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

local HeroAssets = ReplicatedStorage:WaitForChild("HeroAssets", 5)
local kitItems: { [string]: { Buy: TextButton, Robux: TextButton?, Stroke: UIStroke? } } = {}
local robuxPrices: { [string]: number } = {}

-- 3D hero statue inside a shop card (replaces the kit's placeholder image)
local function statueView(holder: GuiObject, heroId: string)
	local vf = Instance.new("ViewportFrame")
	vf.Name = "Statue"
	vf.BackgroundTransparency = 1
	vf.Size = holder.Size
	vf.Position = holder.Position
	vf.AnchorPoint = holder.AnchorPoint
	vf.ZIndex = holder.ZIndex
	vf.Ambient = Color3.fromRGB(150, 150, 170)
	vf.LightDirection = Vector3.new(0.4, -0.6, 1)
	local cam = Instance.new("Camera")
	cam.FieldOfView = 40
	cam.CFrame = CFrame.lookAt(Vector3.new(0, 4.3, -13), Vector3.new(0, 4, 0))
	cam.Parent = vf
	vf.CurrentCamera = cam
	local tpl = HeroAssets and HeroAssets:FindFirstChild("Statues") and HeroAssets.Statues:FindFirstChild(heroId)
	if tpl then
		local m = tpl:Clone()
		m:PivotTo(CFrame.new())
		m.Parent = vf
	end
	vf.Parent = holder.Parent
	holder.Visible = false
end

local function refreshKitItems()
	for id, refs in pairs(kitItems) do
		local h = HeroConfig.Heroes[id]
		local owned = isUnlocked(id)
		if owned then
			refs.Buy.Text = profile.SelectedHero == id and "SELECTED" or "SELECT"
			refs.Buy.BackgroundColor3 = C.Green
		else
			refs.Buy.Text = h.Price .. " TOKENS"
			refs.Buy.BackgroundColor3 = profile.Tokens >= h.Price and C.Gold or Color3.fromRGB(120, 110, 80)
		end
		if refs.Robux then
			refs.Robux.Visible = not owned
			refs.Robux.Text = robuxPrices[id] and ("R$ " .. robuxPrices[id]) or "R$ ..."
		end
		-- full-width token button when there is no Robux option
		local fullWidth = owned or refs.Robux == nil
		refs.Buy.Size = fullWidth and refs.Buy:GetAttribute("FullSize") or refs.Buy:GetAttribute("HalfSize")
	end
end

-- Dark neon look to match the lobby (keeps the kit's layout and animations)
local function restyleKit()
	kitFrame.ImageTransparency = 1
	kitFrame.BackgroundColor3 = C.Bg
	kitFrame.BackgroundTransparency = 0.04
	UI.Corner(kitFrame, 18)
	UI.Stroke(kitFrame, C.Cyan, 3, 0)
	local label = kitFrame:FindFirstChild("ShopLabel") :: TextLabel?
	if label then
		label.TextColor3 = C.Gold
		label.Font = UI.Fonts.Title
	end
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
	restyleKit()
	for i, id in ipairs(HeroConfig.HeroOrder) do
		local h = HeroConfig.Heroes[id]
		local item = template:Clone()
		item.Name = "hero_" .. id
		item.LayoutOrder = i
		item.BackgroundColor3 = C.Panel
		local stroke = item:FindFirstChildOfClass("UIStroke")
		if stroke then stroke.Color = h.Color; stroke.Thickness = 2 end
		item.TextLabel.Text = h.DisplayName
		item.TextLabel.TextColor3 = h.Color
		item.TextLabel.Font = UI.Fonts.Title
		for _, img in ipairs(item:GetChildren()) do
			if img:IsA("ImageLabel") then
				if img.Image:find("GuiImagePlaceholder") then
					statueView(img, id)
				else
					img.Visible = false -- the kit's Robux coin decoration
				end
			end
		end
		local buy = item:FindFirstChild("Buy") :: TextButton
		buy.TextColor3 = C.Bg
		buy.Font = UI.Fonts.Title
		local buyStroke = buy:FindFirstChildOfClass("UIStroke")
		if buyStroke then buyStroke.Enabled = false end -- the kit's thick black outline hides small text
		-- split the kit's single button into TOKENS | R$ when a Robux product exists for this hero
		local full = buy.Size
		local half = UDim2.new(full.X.Scale * 0.48, full.X.Offset * 0.48, full.Y.Scale, full.Y.Offset)
		buy:SetAttribute("FullSize", full)
		buy:SetAttribute("HalfSize", half)
		local robux: TextButton? = nil
		local productId = ProductConfig.HeroProducts[id]
		if productId and productId > 0 then
			-- anchor both buttons at the kit button's left edge so they sit side by side
			local leftX = UDim.new(buy.Position.X.Scale - buy.AnchorPoint.X * full.X.Scale, buy.Position.X.Offset - buy.AnchorPoint.X * full.X.Offset)
			buy.AnchorPoint = Vector2.new(0, buy.AnchorPoint.Y)
			buy.Position = UDim2.new(leftX, buy.Position.Y)
			local r = buy:Clone()
			r.Name = "BuyRobux"
			r.Size = half
			r.Position = UDim2.new(leftX.Scale + full.X.Scale * 0.52, leftX.Offset + full.X.Offset * 0.52, buy.Position.Y.Scale, buy.Position.Y.Offset)
			r.BackgroundColor3 = Color3.fromRGB(0, 176, 111)
			r.TextColor3 = Color3.new(1, 1, 1)
			r.Parent = item
			r.MouseButton1Click:Connect(function()
				if isUnlocked(id) then return end
				BuyHeroRobux:FireServer(id) -- the server checks ownership and shows Roblox's purchase prompt
			end)
			robux = r
			task.spawn(function()
				local ok, info = pcall(function() return MarketplaceService:GetProductInfo(productId, Enum.InfoType.Product) end)
				if ok and info and info.PriceInRobux then
					robuxPrices[id] = info.PriceInRobux
					refreshKitItems()
				end
			end)
		end
		buy.MouseButton1Click:Connect(function() purchaseHero(id) end)
		kitItems[id] = { Buy = buy, Robux = robux, Stroke = stroke }
		item.Parent = items
	end
	refreshKitItems()
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
player:GetAttributeChangedSignal("Rating"):Connect(refreshProfile)

-- tokens and owned heroes come from server-set attributes, so the UI updates the moment anything changes
local function syncProgress()
	local t = player:GetAttribute("Tokens")
	if typeof(t) == "number" then profile.Tokens = t end
	local u = player:GetAttribute("UnlockedHeroes")
	if typeof(u) == "string" and u ~= "" then profile.UnlockedHeroes = string.split(u, ",") end
	tokenLabel.Text = tostring(profile.Tokens)
	refreshCards()
	showHero(viewedHero)
	refreshKitItems()
end
player:GetAttributeChangedSignal("Tokens"):Connect(syncProgress)
player:GetAttributeChangedSignal("UnlockedHeroes"):Connect(syncProgress)

---------------------------------------------------------------- DAILY REWARD (7-day streak calendar)
local dailyGui = UI.ScreenGui("DailyUI", playerGui, 12)
local dailyDim, dailyBody = makeModal(dailyGui, "DAILY REWARD", C.Gold)
dailyDim.Name = "DailyMenu"
local dailyHint = UI.Label({ Parent = dailyBody, Name = "Hint", Text = "", Font = UI.Fonts.Bold, Color = C.Subtext, Size = UDim2.fromScale(1, 0.08), Position = UDim2.fromScale(0, 0), MaxSize = 22 })
local dayRow = Instance.new("Frame"); dayRow.Name = "Days"; dayRow.BackgroundTransparency = 1
dayRow.Size = UDim2.fromScale(1, 0.6); dayRow.Position = UDim2.fromScale(0, 0.12); dayRow.Parent = dailyBody
local dayList = Instance.new("UIListLayout"); dayList.FillDirection = Enum.FillDirection.Horizontal
dayList.HorizontalAlignment = Enum.HorizontalAlignment.Center; dayList.VerticalAlignment = Enum.VerticalAlignment.Center
dayList.Padding = UDim.new(0.012, 0); dayList.SortOrder = Enum.SortOrder.LayoutOrder; dayList.Parent = dayRow
local claimBtn = UI.Button({ Parent = dailyBody, Name = "Claim", Text = "CLAIM", Size = UDim2.fromScale(0.36, 0.14), Position = UDim2.fromScale(0.5, 0.82), AnchorPoint = Vector2.new(0.5, 0), Accent = C.Gold, MaxSize = 30 })
local dayCards: { { Frame: Frame, Stroke: UIStroke, Check: TextLabel, Scale: UIScale } } = {}
for i, amount in ipairs(GameConfig.Progression.Daily) do
	local big = i == #GameConfig.Progression.Daily
	local card = UI.Panel({ Parent = dayRow, Name = "Day" .. i, Size = UDim2.fromScale(big and 0.155 or 0.122, big and 1 or 0.88), Color = C.Panel, Corner = 12 })
	card.LayoutOrder = i
	local stroke = UI.Stroke(card, C.Subtext, 2, 0.3)
	UI.Label({ Parent = card, Text = "DAY " .. i, Font = UI.Fonts.Title, Size = UDim2.fromScale(0.9, 0.17), Position = UDim2.fromScale(0.05, 0.05), MaxSize = 22 })
	UI.Icon({ Parent = card, Icon = "Token", Size = UDim2.fromScale(0.62, 0.42), Position = UDim2.fromScale(0.5, 0.48), AnchorPoint = Vector2.new(0.5, 0.5) })
	UI.Label({ Parent = card, Text = tostring(amount), Font = UI.Fonts.Title, Color = C.Gold, Size = UDim2.fromScale(0.9, 0.2), Position = UDim2.fromScale(0.05, 0.74), MaxSize = 30 })
	local check = UI.Label({ Parent = card, Name = "Check", Text = "CLAIMED", Font = UI.Fonts.Title, Color = C.Green, Size = UDim2.fromScale(1.1, 0.2), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), MaxSize = 20, StrokeSize = 2.5 })
	check.Rotation = -18
	check.ZIndex = 5
	local sc = Instance.new("UIScale"); sc.Parent = card
	dayCards[i] = { Frame = card, Stroke = stroke, Check = check, Scale = sc }
end

local dailyState: { [string]: any }? = nil
local function renderDaily()
	local d = dailyState
	if not d then return end
	local current = tonumber(d.Day) or 1
	for i, c in ipairs(dayCards) do
		local claimed = (d.CanClaim and i < current) or (not d.CanClaim and i <= current)
		local isToday = d.CanClaim and i == current
		c.Check.Visible = claimed
		c.Frame.BackgroundTransparency = claimed and 0.5 or 0
		c.Stroke.Color = isToday and C.Gold or (claimed and C.Green or C.Subtext)
		c.Stroke.Thickness = isToday and 4 or 2
		c.Scale.Scale = isToday and 1.08 or 1
	end
	if d.CanClaim then
		claimBtn.Text = string.format("CLAIM +%d", GameConfig.Progression.Daily[current] or 0)
		dailyHint.Text = current == 1 and "Log in every day to build your streak - day 7 pays the most!" or string.format("Day %d streak - keep it going!", current)
	else
		local hours = math.max(1, math.ceil((tonumber(d.SecondsToReset) or 0) / 3600))
		claimBtn.Text = "COME BACK TOMORROW"
		dailyHint.Text = string.format("Next reward in about %d hour%s. Miss a day and the streak restarts.", hours, hours == 1 and "" or "s")
	end
end

local claiming = false
claimBtn.MouseButton1Click:Connect(function()
	if claiming or not dailyState or not dailyState.CanClaim then return end
	claiming = true
	local ok, res = pcall(function() return ClaimDaily:InvokeServer() end)
	claiming = false
	if ok and typeof(res) == "table" then
		if res.Daily then dailyState = res.Daily end
		renderDaily()
		if res.Ok then
			toast(string.format("+%d TOKENS - Day %d reward", res.Amount, res.Day), C.Gold)
			task.delay(1.2, function() if dailyDim.Visible and openPanel == dailyDim then dailyDim.Visible = false; openPanel = nil end end)
		elseif res.Reason then
			toast(res.Reason, C.Subtext)
		end
	end
end)

local dailyShown = false
local function maybeShowDaily()
	if dailyShown or inMatch then return end
	local ok, data = pcall(function() return GetLobbyData:InvokeServer() end)
	if ok and typeof(data) == "table" and typeof(data.Daily) == "table" and data.Daily.CanClaim then
		dailyShown = true
		dailyState = data.Daily
		renderDaily()
		showModal(dailyDim)
	end
end
player:GetAttributeChangedSignal("DailyReady"):Connect(function()
	if player:GetAttribute("DailyReady") == true then maybeShowDaily() end
end)

refreshProfile()
refreshCards()
showHero(viewedHero)
syncProgress()
if player:GetAttribute("DailyReady") == true then task.defer(maybeShowDaily) end
if player:GetAttribute("Hero") then profile.SelectedHero = player:GetAttribute("Hero"); refreshProfile(); refreshCards() end
applyLighting(MapConfig.LobbyLighting)
