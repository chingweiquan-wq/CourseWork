-- CombatHUD: in-match combat interface, built inside MatchUI (so it hides automatically in the lobby).
-- Crosshair, hit markers + damage numbers, health, ammo/reload, K/D/A, kill feed, death screen, damage flash.
-- Everything shown comes from server-set attributes/remotes; nothing here affects gameplay.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local Modules = ReplicatedStorage:WaitForChild("Modules")
local UI = require(Modules:WaitForChild("UIStyle"))
local HeroConfig = require(Modules:WaitForChild("HeroConfig"))
local WeaponConfig = require(Modules:WaitForChild("WeaponConfig"))
local GameConfig = require(Modules:WaitForChild("GameConfig"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local HitConfirm = Remotes:WaitForChild("HitConfirm")
local KillFeed = Remotes:WaitForChild("KillFeed")
local C = UI.Colors

local gui = player:WaitForChild("PlayerGui"):WaitForChild("MatchUI")

local root = Instance.new("Frame")
root.Name = "CombatHUD"
root.Size = UDim2.fromScale(1, 1)
root.BackgroundTransparency = 1
root.Parent = gui

---------------------------------------------------------------- damage vignette
local vignette = Instance.new("Frame")
vignette.Name = "DamageFlash"
vignette.Size = UDim2.fromScale(1, 1)
vignette.BackgroundColor3 = Color3.fromRGB(255, 30, 60)
vignette.BackgroundTransparency = 1
vignette.ZIndex = 0
vignette.Parent = root
local vg = Instance.new("UIGradient")
vg.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(0.5, 1), NumberSequenceKeypoint.new(1, 0.2) })
vg.Parent = vignette

---------------------------------------------------------------- crosshair
local cross = Instance.new("Frame")
cross.Name = "Crosshair"
cross.AnchorPoint = Vector2.new(0.5, 0.5)
cross.Position = UDim2.fromScale(0.5, 0.5)
cross.Size = UDim2.fromOffset(40, 40)
cross.BackgroundTransparency = 1
cross.Parent = root
local function line(size: UDim2, pos: UDim2, parent: Instance, color: Color3?): Frame
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Size = size; f.Position = pos
	f.BackgroundColor3 = color or Color3.new(1, 1, 1)
	f.BorderSizePixel = 0
	local s = Instance.new("UIStroke"); s.Thickness = 1; s.Color = Color3.new(0, 0, 0); s.Transparency = 0.5; s.Parent = f
	f.Parent = parent
	return f
end
line(UDim2.fromOffset(3, 3), UDim2.fromScale(0.5, 0.5), cross, C.Cyan)
line(UDim2.fromOffset(2, 9), UDim2.new(0.5, 0, 0.5, -11), cross)
line(UDim2.fromOffset(2, 9), UDim2.new(0.5, 0, 0.5, 11), cross)
line(UDim2.fromOffset(9, 2), UDim2.new(0.5, -11, 0.5, 0), cross)
line(UDim2.fromOffset(9, 2), UDim2.new(0.5, 11, 0.5, 0), cross)

-- hit marker (X shape)
local hitMarker = Instance.new("Frame")
hitMarker.Name = "HitMarker"
hitMarker.AnchorPoint = Vector2.new(0.5, 0.5)
hitMarker.Position = UDim2.fromScale(0.5, 0.5)
hitMarker.Size = UDim2.fromOffset(36, 36)
hitMarker.BackgroundTransparency = 1
hitMarker.Visible = false
hitMarker.Parent = root
local hmLines = {}
for i, a in ipairs({ 45, -45, 135, -135 }) do
	local r = math.rad(a)
	local f = line(UDim2.fromOffset(10, 2), UDim2.new(0.5, math.cos(r) * 12, 0.5, math.sin(r) * 12), hitMarker)
	f.Rotation = a
	hmLines[i] = f
end
local damageText = UI.Label({ Parent = root, Name = "DamageNumber", Text = "", Font = UI.Fonts.Title, Size = UDim2.fromOffset(120, 30), Position = UDim2.new(0.5, 40, 0.5, -40), AnchorPoint = Vector2.new(0, 0.5), AlignX = Enum.TextXAlignment.Left, MaxSize = 26 })
local hitToken = 0

HitConfirm.OnClientEvent:Connect(function(data)
	if typeof(data) ~= "table" then return end
	hitToken += 1
	local token = hitToken
	local color = data.Killed and C.Red or (data.Headshot and C.Gold or Color3.new(1, 1, 1))
	for _, f in ipairs(hmLines) do f.BackgroundColor3 = color end
	hitMarker.Size = UDim2.fromOffset(data.Killed and 48 or 36, data.Killed and 48 or 36)
	hitMarker.Visible = true
	damageText.Text = (data.Headshot and "" or "") .. tostring(data.Damage) .. (data.Killed and "  ELIMINATED" or "")
	damageText.TextColor3 = color
	damageText.TextTransparency = 0
	task.delay(0.15, function() if token == hitToken then hitMarker.Visible = false end end)
	task.delay(0.6, function()
		if token == hitToken then TweenService:Create(damageText, TweenInfo.new(0.3), { TextTransparency = 1 }):Play() end
	end)
end)

---------------------------------------------------------------- health (bottom-left)
-- The bottom-left health BAR is the Premium Health Bar kit (StarterGui.HealthBar). This small card above it
-- only shows the current hero's name and HP numbers.
local healthPanel = UI.Panel({ Parent = root, Name = "HeroCard", Size = UDim2.fromScale(0.16, 0.05), Position = UDim2.fromScale(0.02, 0.82), AnchorPoint = Vector2.new(0, 1), Color = C.Bg, Transparency = 0.4 })
healthPanel.Visible = false -- the Premium Health Bar kit already shows HP; hero name is shown on the ammo panel
local heroLabel = UI.Label({ Parent = healthPanel, Text = "", Font = UI.Fonts.Title, Size = UDim2.fromScale(0.55, 0.8), Position = UDim2.fromScale(0.05, 0.1), AlignX = Enum.TextXAlignment.Left, MaxSize = 22, StrokeSize = 2 })
local hpText = UI.Label({ Parent = healthPanel, Text = "", Font = UI.Fonts.Title, Size = UDim2.fromScale(0.38, 0.8), Position = UDim2.fromScale(0.58, 0.1), AlignX = Enum.TextXAlignment.Right, MaxSize = 22, StrokeSize = 2 })

---------------------------------------------------------------- ammo (bottom-right)
local ammoPanel = UI.Panel({ Parent = root, Name = "Ammo", Size = UDim2.fromScale(0.18, 0.1), Position = UDim2.fromScale(0.98, 0.97), AnchorPoint = Vector2.new(1, 1), Stroke = C.Gold, Transparency = 0.25 })
local ammoText = UI.Label({ Parent = ammoPanel, Text = "", Font = UI.Fonts.Title, Size = UDim2.fromScale(0.9, 0.55), Position = UDim2.fromScale(0.05, 0.05), AlignX = Enum.TextXAlignment.Right, MaxSize = 40, Rich = true })
local weaponLabel = UI.Label({ Parent = ammoPanel, Text = "", Font = UI.Fonts.Bold, Color = C.Subtext, Size = UDim2.fromScale(0.9, 0.3), Position = UDim2.fromScale(0.05, 0.62), AlignX = Enum.TextXAlignment.Right, MaxSize = 16 })

---------------------------------------------------------------- K/D/A (top-right)
local kdaPanel = UI.Panel({ Parent = root, Name = "KDA", Size = UDim2.fromScale(0.16, 0.05), Position = UDim2.fromScale(0.98, 0.03), AnchorPoint = Vector2.new(1, 0), Stroke = C.Magenta, Transparency = 0.25 })
local kdaText = UI.Label({ Parent = kdaPanel, Text = "", Font = UI.Fonts.Title, Size = UDim2.fromScale(0.9, 0.7), Position = UDim2.fromScale(0.05, 0.15), MaxSize = 20, Rich = true })

---------------------------------------------------------------- kill feed (right, under K/D/A)
local feed = Instance.new("Frame")
feed.Name = "KillFeed"
feed.BackgroundTransparency = 1
feed.Size = UDim2.fromScale(0.3, 0.28)
feed.Position = UDim2.fromScale(0.98, 0.1)
feed.AnchorPoint = Vector2.new(1, 0)
feed.Parent = root
local feedLayout = Instance.new("UIListLayout")
feedLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
feedLayout.Padding = UDim.new(0, 4)
feedLayout.SortOrder = Enum.SortOrder.LayoutOrder
feedLayout.Parent = feed
local feedOrder = 0

local function teamHex(team: string?): string
	local t = team and GameConfig.Teams[team]
	local c = t and t.Color or C.Gold
	return string.format("#%02x%02x%02x", math.floor(c.R * 255), math.floor(c.G * 255), math.floor(c.B * 255))
end

---------------------------------------------------------------- death screen
local deathPanel = UI.Panel({ Parent = root, Name = "DeathScreen", Size = UDim2.fromScale(0.36, 0.13), Position = UDim2.fromScale(0.5, 0.7), AnchorPoint = Vector2.new(0.5, 0.5), Stroke = C.Red, Transparency = 0.15 })
deathPanel.Visible = false
local deathTitle = UI.Label({ Parent = deathPanel, Text = "ELIMINATED", Font = UI.Fonts.Title, Color = C.Red, Size = UDim2.fromScale(0.9, 0.45), Position = UDim2.fromScale(0.05, 0.08), MaxSize = 36 })
local deathSub = UI.Label({ Parent = deathPanel, Text = "", Font = UI.Fonts.Bold, Color = C.Subtext, Size = UDim2.fromScale(0.9, 0.35), Position = UDim2.fromScale(0.05, 0.56), MaxSize = 20 })
local lastKiller = ""

KillFeed.OnClientEvent:Connect(function(data)
	if typeof(data) ~= "table" then return end
	feedOrder += 1
	local killerPart = data.Killer and string.format("<font color=\"%s\">%s</font>", teamHex(data.KillerTeam), data.Killer) or ""
	local victimPart = string.format("<font color=\"%s\">%s</font>", teamHex(data.VictimTeam or (data.KillerTeam == "Alpha" and "Bravo" or "Alpha")), data.Victim or "?")
	local mid = data.Killer and string.format("  [%s%s]  ", data.Weapon or "", data.Headshot and " HS" or "") or "  fell  "
	local text = killerPart .. mid .. victimPart
	if data.FirstBlood then text = "<font color=\"#ffc83c\">FIRST BLOOD</font>  " .. text end
	local entry = UI.Panel({ Parent = feed, Size = UDim2.fromScale(1, 0.15), Color = C.Bg, Transparency = 0.35, Corner = 6 })
	entry.LayoutOrder = -feedOrder -- newest on top
	if data.KillerUserId == player.UserId then UI.Stroke(entry, C.Gold, 1.5, 0.2) end
	UI.Label({ Parent = entry, Text = text, Rich = true, Font = UI.Fonts.Bold, Size = UDim2.fromScale(0.94, 0.8), Position = UDim2.fromScale(0.03, 0.1), AlignX = Enum.TextXAlignment.Right, MaxSize = 18 })
	local entries = {}
	for _, c in ipairs(feed:GetChildren()) do if c:IsA("Frame") then table.insert(entries, c) end end
	if #entries > 5 then
		table.sort(entries, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
		entries[#entries]:Destroy()
	end
	task.delay(6, function() if entry.Parent then entry:Destroy() end end)

	if data.VictimUserId == player.UserId then
		lastKiller = data.Killer or ""
	end
end)

---------------------------------------------------------------- per-frame updates
local lastHealth = 0
RunService.RenderStepped:Connect(function()
	if not gui.Enabled then return end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local alive = hum ~= nil and hum.Health > 0

	-- health
	if hum then
		hpText.Text = string.format("%d / %d", math.ceil(hum.Health), hum.MaxHealth)
		if hum.Health < lastHealth - 0.5 then
			vignette.BackgroundTransparency = 0.55
			TweenService:Create(vignette, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
		end
		lastHealth = hum.Health
	end
	local heroId = player:GetAttribute("Hero")
	local hero = heroId and HeroConfig.Heroes[heroId]
	heroLabel.Text = hero and hero.DisplayName or ""
	heroLabel.TextColor3 = hero and hero.Color or C.Text

	-- ammo
	local w = WeaponConfig.Weapons[player:GetAttribute("WeaponId") or ""]
	if w then
		weaponLabel.Text = (hero and (hero.DisplayName .. "  -  ") or "") .. string.upper(w.DisplayName)
		if w.MagSize <= 0 then
			ammoText.Text = "MELEE"
		elseif player:GetAttribute("Reloading") then
			ammoText.Text = "<font color=\"#ffc83c\">RELOADING</font>"
		else
			local a = player:GetAttribute("Ammo") or 0
			local col = a <= math.ceil(w.MagSize * 0.25) and "#ff466e" or "#e6ecff"
			ammoText.Text = string.format("<font color=\"%s\">%d</font><font color=\"#8c96b9\"> / %d</font>", col, a, w.MagSize)
		end
	end

	-- K/D/A
	kdaText.Text = string.format("K <font color=\"#00dcff\">%d</font>   D <font color=\"#ff466e\">%d</font>   A <font color=\"#ffc83c\">%d</font>",
		player:GetAttribute("MatchKills") or 0, player:GetAttribute("MatchDeaths") or 0, player:GetAttribute("MatchAssists") or 0)

	-- crosshair + death screen
	cross.Visible = alive and player:GetAttribute("CombatEnabled") ~= nil
	local respawnAt = player:GetAttribute("RespawnAt")
	if not alive and typeof(respawnAt) == "number" then
		deathPanel.Visible = true
		deathTitle.Text = lastKiller ~= "" and ("ELIMINATED BY " .. string.upper(lastKiller)) or "ELIMINATED"
		deathSub.Text = string.format("Respawning in %d", math.max(0, math.ceil(respawnAt - workspace:GetServerTimeNow())))
	else
		deathPanel.Visible = false
		if alive then lastKiller = "" end
	end
end)
