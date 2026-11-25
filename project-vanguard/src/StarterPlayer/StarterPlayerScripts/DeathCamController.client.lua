--!strict
-- DeathCamController: when you are eliminated you see through your KILLER'S eyes until you respawn.
--  * desaturated picture + red screen edges
--  * killer card (name, hero, weapon, HP left), damage breakdown (who hit you, how much), respawn countdown
--  * SPACE skips back to your own camera
-- The server sends the facts (CombatService -> "DeathCam" remote); this script only displays them.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer
local Modules = ReplicatedStorage:WaitForChild("Modules")
local HeroConfig = require(Modules:WaitForChild("HeroConfig"))
local UI = require(Modules:WaitForChild("UIStyle"))
local C = UI.Colors
local DeathCam = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("DeathCam")

local START_DELAY = 0.7 -- let the dissolve on your own body play first

---------------------------------------------------------------- screen
local gui = Instance.new("ScreenGui")
gui.Name = "DeathCamUI"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 9
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

-- red vignette: four edge strips fading toward the centre
for _, e in ipairs({
	{ UDim2.fromScale(0.16, 1), UDim2.fromScale(0, 0), 0 },
	{ UDim2.fromScale(0.16, 1), UDim2.fromScale(0.84, 0), 180 },
	{ UDim2.fromScale(1, 0.2), UDim2.fromScale(0, 0), 90 },
	{ UDim2.fromScale(1, 0.2), UDim2.fromScale(0, 0.8), 270 },
}) do
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundColor3 = Color3.fromRGB(200, 20, 40)
	f.BackgroundTransparency = 0.35
	f.Size = e[1]; f.Position = e[2]
	local g = Instance.new("UIGradient")
	g.Rotation = e[3]
	g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	g.Parent = f
	f.Parent = gui
end

local title = UI.Label({ Parent = gui, Text = "ELIMINATED", Font = UI.Fonts.Title, Color = Color3.fromRGB(255, 70, 90), Size = UDim2.fromScale(0.5, 0.07), Position = UDim2.fromScale(0.5, 0.27), AnchorPoint = Vector2.new(0.5, 0.5), MaxSize = 54, StrokeSize = 3 })
local subtitle = UI.Label({ Parent = gui, Text = "", Font = UI.Fonts.Bold, Size = UDim2.fromScale(0.5, 0.035), Position = UDim2.fromScale(0.5, 0.325), AnchorPoint = Vector2.new(0.5, 0.5), MaxSize = 22, Rich = true })

-- killer card (bottom-left)
local card = UI.Panel({ Parent = gui, Name = "Killer", Size = UDim2.fromScale(0.26, 0.15), Position = UDim2.fromScale(0.03, 0.8), AnchorPoint = Vector2.new(0, 1), Color = C.Bg, Transparency = 0.15, Stroke = Color3.fromRGB(255, 70, 90), Corner = 12 })
UI.Label({ Parent = card, Text = "KILLED BY", Font = UI.Fonts.Bold, Color = C.Subtext, Size = UDim2.fromScale(0.9, 0.18), Position = UDim2.fromScale(0.05, 0.06), AlignX = Enum.TextXAlignment.Left, MaxSize = 16 })
local kName = UI.Label({ Parent = card, Text = "", Font = UI.Fonts.Title, Size = UDim2.fromScale(0.9, 0.28), Position = UDim2.fromScale(0.05, 0.22), AlignX = Enum.TextXAlignment.Left, MaxSize = 30, Rich = true })
local kWeapon = UI.Label({ Parent = card, Text = "", Font = UI.Fonts.Bold, Color = C.Subtext, Size = UDim2.fromScale(0.9, 0.17), Position = UDim2.fromScale(0.05, 0.5), AlignX = Enum.TextXAlignment.Left, MaxSize = 16, Rich = true })
local hpBack = UI.Panel({ Parent = card, Name = "HP", Size = UDim2.fromScale(0.9, 0.12), Position = UDim2.fromScale(0.05, 0.76), Color = C.PanelLight, Transparency = 0, Corner = 4 })
local hpFill = UI.Panel({ Parent = hpBack, Name = "Fill", Size = UDim2.fromScale(1, 1), Color = C.Green, Transparency = 0, Corner = 4 })
local hpText = UI.Label({ Parent = hpBack, Text = "", Font = UI.Fonts.Title, Size = UDim2.fromScale(1, 1.3), Position = UDim2.fromScale(0, -0.15), MaxSize = 14, StrokeSize = 1.5 })
hpText.ZIndex = 3

-- damage breakdown (right side)
local dmgPanel = UI.Panel({ Parent = gui, Name = "Damage", Size = UDim2.fromScale(0.22, 0.3), Position = UDim2.fromScale(0.97, 0.5), AnchorPoint = Vector2.new(1, 0.5), Color = C.Bg, Transparency = 0.2, Stroke = C.Subtext, Corner = 12 })
UI.Label({ Parent = dmgPanel, Text = "DAMAGE TAKEN", Font = UI.Fonts.Title, Color = Color3.fromRGB(255, 70, 90), Size = UDim2.fromScale(0.9, 0.12), Position = UDim2.fromScale(0.05, 0.04), AlignX = Enum.TextXAlignment.Left, MaxSize = 20 })
local rows: { TextLabel } = {}
for i = 1, 5 do
	rows[i] = UI.Label({ Parent = dmgPanel, Text = "", Font = UI.Fonts.Bold, Size = UDim2.fromScale(0.9, 0.12), Position = UDim2.fromScale(0.05, 0.05 + i * 0.15), AlignX = Enum.TextXAlignment.Left, MaxSize = 18, Rich = true })
end

-- countdown + skip hint (bottom centre)
local countdown = UI.Label({ Parent = gui, Text = "", Font = UI.Fonts.Title, Size = UDim2.fromScale(0.4, 0.05), Position = UDim2.fromScale(0.5, 0.86), AnchorPoint = Vector2.new(0.5, 0.5), MaxSize = 34, StrokeSize = 2.5 })
UI.Label({ Parent = gui, Text = "Press SPACE to skip", Font = UI.Fonts.Bold, Color = C.Subtext, Size = UDim2.fromScale(0.3, 0.03), Position = UDim2.fromScale(0.5, 0.91), AnchorPoint = Vector2.new(0.5, 0.5), MaxSize = 18 })

local cc = Instance.new("ColorCorrectionEffect")
cc.Name = "DeathCamCC"
cc.Enabled = false
cc.Parent = Lighting

local function hex(c: Color3): string
	return string.format("#%02x%02x%02x", math.floor(c.R * 255), math.floor(c.G * 255), math.floor(c.B * 255))
end

---------------------------------------------------------------- run / stop
local active = 0 -- token; bumping it ends the current death cam
local camConn: RBXScriptConnection? = nil

-- the normal match HUD pieces that would overlap the death cam (old death box, ability bar)
local function matchHud(name: string): GuiObject?
	local mui = player.PlayerGui:FindFirstChild("MatchUI")
	return mui and mui:FindFirstChild(name, true) :: GuiObject?
end

local function stop()
	active += 1
	local bar = matchHud("AbilityBar")
	if bar then bar.Visible = true end
	if camConn then camConn:Disconnect(); camConn = nil end
	gui.Enabled = false
	TweenService:Create(cc, TweenInfo.new(0.3), { Saturation = 0, TintColor = Color3.new(1, 1, 1) }):Play()
	task.delay(0.3, function() if not gui.Enabled then cc.Enabled = false end end)
	local cam = workspace.CurrentCamera
	if cam.CameraType == Enum.CameraType.Scriptable then cam.CameraType = Enum.CameraType.Custom end
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then cam.CameraSubject = hum end
end

DeathCam.OnClientEvent:Connect(function(info)
	if typeof(info) ~= "table" then return end
	active += 1
	local token = active
	task.wait(START_DELAY)
	if token ~= active then return end

	-- text
	local h = typeof(info.KillerHero) == "string" and HeroConfig.Heroes[info.KillerHero] or nil
	local col = h and h.Color or Color3.fromRGB(255, 70, 90)
	if info.KillerName then
		kName.Text = string.format("<font color=\"%s\">%s</font>", hex(col), string.upper(tostring(info.KillerName)))
		kWeapon.Text = string.format("%s  -  %s%s", h and h.DisplayName or "?", tostring(info.Weapon or "?"), info.Headshot and "  <font color=\"#ffc83c\">HEADSHOT</font>" or "")
		subtitle.Text = string.format("Watching <font color=\"%s\">%s</font>", hex(col), tostring(info.KillerName))
		card.Visible = true
	else
		subtitle.Text = "You were eliminated"
		card.Visible = false
	end
	local list = typeof(info.Breakdown) == "table" and info.Breakdown or {}
	for i, row in ipairs(rows) do
		local b = list[i]
		if b then
			local bh = typeof(b.Hero) == "string" and HeroConfig.Heroes[b.Hero] or nil
			row.Text = string.format("<font color=\"%s\">%s</font>  <font color=\"#8c96b9\">%s</font>   <font color=\"#ff5a6e\">%d</font>%s",
				hex(bh and bh.Color or C.Text), tostring(b.Name), bh and bh.DisplayName or "", tonumber(b.Damage) or 0, b.Killer and "  <font color=\"#ffc83c\">KILL</font>" or "")
		else
			row.Text = ""
		end
	end
	dmgPanel.Visible = #list > 0

	-- screen filter
	cc.Enabled = true
	cc.Saturation = 0; cc.TintColor = Color3.new(1, 1, 1)
	TweenService:Create(cc, TweenInfo.new(0.5), { Saturation = -0.8, TintColor = Color3.fromRGB(255, 225, 225) }):Play()
	gui.Enabled = true

	-- killer's view: camera sits at the killer's eyes, looking where their body faces
	local killerModel = typeof(info.KillerModel) == "Instance" and info.KillerModel :: Model or nil
	local cam = workspace.CurrentCamera
	local lastCF = cam.CFrame
	local endsAt = os.clock() + math.max(0, (tonumber(info.Respawn) or 5) - START_DELAY)
	if camConn then camConn:Disconnect() end
	local hidden: { BasePart } = {}
	camConn = RunService.RenderStepped:Connect(function()
		if token ~= active then return end
		local ds, bar = matchHud("DeathScreen"), matchHud("AbilityBar")
		if ds then ds.Visible = false end
		if bar then bar.Visible = false end
		local respawnAt = player:GetAttribute("RespawnAt") -- same server timer the match HUD uses
		local left = if typeof(respawnAt) == "number" then respawnAt - workspace:GetServerTimeNow() else endsAt - os.clock()
		countdown.Text = left > 0 and string.format("Respawning in %d", math.ceil(left)) or "Respawning..."
		local head = killerModel and killerModel.Parent and killerModel:FindFirstChild("Head") :: BasePart?
		local root = killerModel and killerModel.Parent and killerModel:FindFirstChild("HumanoidRootPart") :: BasePart?
		local kHum = killerModel and killerModel:FindFirstChildOfClass("Humanoid")
		if kHum and kHum.MaxHealth > 0 then
			local frac = math.clamp(kHum.Health / kHum.MaxHealth, 0, 1)
			hpFill.Size = UDim2.fromScale(frac, 1)
			hpFill.BackgroundColor3 = frac > 0.5 and C.Green or (frac > 0.25 and C.Gold or Color3.fromRGB(255, 70, 90))
			hpText.Text = string.format("%d / %d HP", math.ceil(kHum.Health), kHum.MaxHealth)
		end
		if head and root and kHum and kHum.Health > 0 then
			cam.CameraType = Enum.CameraType.Scriptable
			local eye = head.Position + Vector3.new(0, 0.3, 0)
			lastCF = CFrame.lookAt(eye, eye + root.CFrame.LookVector)
			cam.CFrame = lastCF
			-- hide the killer's own body from their eyes (it would block the view)
			if #hidden == 0 then
				for _, d in ipairs(killerModel:GetDescendants()) do
					if d:IsA("BasePart") then table.insert(hidden, d) end
				end
			end
			for _, p in ipairs(hidden) do p.LocalTransparencyModifier = 1 end
		else
			-- killer died or left: hold the last view
			cam.CameraType = Enum.CameraType.Scriptable
			cam.CFrame = lastCF
		end
	end)
	-- restore the killer's visibility when we finish
	local myToken = token
	task.spawn(function()
		while active == myToken do task.wait(0.1) end
		for _, p in ipairs(hidden) do if p.Parent then p.LocalTransparencyModifier = 0 end end
	end)
end)

-- end on respawn or SPACE
player.CharacterAdded:Connect(function() if gui.Enabled or camConn then stop() end end)
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.Space and gui.Enabled then stop() end
end)
