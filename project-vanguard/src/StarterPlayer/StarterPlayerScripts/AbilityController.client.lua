-- AbilityController: Shift / E / Q input, client-side dash movement, ability visuals and the ability HUD.
-- The server (AbilityService) owns cooldowns, ult charge, damage and healing. This script only asks
-- "use slot X aiming here" and draws feedback. Keys come from ControlConfig.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local Modules = ReplicatedStorage:WaitForChild("Modules")
local HeroConfig = require(Modules:WaitForChild("HeroConfig"))
local ControlConfig = require(Modules:WaitForChild("ControlConfig"))
local Sfx = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Sfx"))
local IconConfig = require(Modules:WaitForChild("IconConfig"))
local UI = require(Modules:WaitForChild("UIStyle"))
local C = UI.Colors
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local UseAbility = Remotes:WaitForChild("UseAbility")
local AbilityFx = Remotes:WaitForChild("AbilityFx")
local Reveal = Remotes:WaitForChild("Reveal")
local Knockback = Remotes:WaitForChild("Knockback")

local fxFolder = Instance.new("Folder")
fxFolder.Name = "LocalAbilityFx"
fxFolder.Parent = workspace

local SLOTS = { "Dash", "Skill", "Ultimate" }

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function hero()
	local id = player:GetAttribute("Hero")
	return id and HeroConfig.Heroes[id] or nil
end

local function humanoid(): Humanoid?
	local c = player.Character
	return c and c:FindFirstChildOfClass("Humanoid")
end

local function canUse(): boolean
	local hum = humanoid()
	return player:GetAttribute("CombatEnabled") == true and hum ~= nil and hum.Health > 0 and hero() ~= nil
end

local function isReady(slot: string): boolean
	if slot == "Ultimate" then
		return (player:GetAttribute("UltCharge") or 0) >= 1 and player:GetAttribute("UltActive") ~= true
	end
	return serverNow() >= (player:GetAttribute("Ready_" .. slot) or 0)
end

---------------------------------------------------------------- generic fx helpers
local function fxPart(shape: Enum.PartType, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.CastShadow = false
	p.Shape = shape; p.Size = size; p.CFrame = cf; p.Color = color
	p.Material = mat or Enum.Material.Neon
	p.Parent = fxFolder
	return p
end

local function burst(pos: Vector3, radius: number, color: Color3, t: number, mat: Enum.Material?)
	local ball = fxPart(Enum.PartType.Ball, Vector3.one, CFrame.new(pos), color, mat)
	ball.Transparency = 0.25
	TweenService:Create(ball, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.one * radius * 2, Transparency = 1 }):Play()
	Debris:AddItem(ball, t + 0.05)
end

local function ring(pos: Vector3, radius: number, color: Color3, t: number)
	local r = fxPart(Enum.PartType.Cylinder, Vector3.new(0.3, 1, 1), CFrame.new(pos + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90)), color)
	r.Transparency = 0.2
	TweenService:Create(r, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.3, radius * 2, radius * 2), Transparency = 1 }):Play()
	Debris:AddItem(r, t + 0.05)
end

local function fovPunch(amount: number)
	local cam = workspace.CurrentCamera
	local base = cam.FieldOfView
	TweenService:Create(cam, TweenInfo.new(0.08), { FieldOfView = base + amount }):Play()
	task.delay(0.12, function()
		TweenService:Create(cam, TweenInfo.new(0.25), { FieldOfView = base }):Play()
	end)
end

local function afterimages(root: BasePart, color: Color3, count: number, spacing: number)
	task.spawn(function()
		for _ = 1, count do
			if not root.Parent then return end
			local ghost = fxPart(Enum.PartType.Block, Vector3.new(2, 4.5, 1), root.CFrame, color)
			ghost.Transparency = 0.5
			TweenService:Create(ghost, TweenInfo.new(0.35), { Transparency = 1, Size = Vector3.new(2.4, 5, 0.2) }):Play()
			Debris:AddItem(ghost, 0.4)
			task.wait(spacing)
		end
	end)
end

---------------------------------------------------------------- dash movement (client owns its character physics)
local function doDash(cfg: any): boolean
	local m = cfg.Movement
	if not m or m.Type ~= "Dash" then return false end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = humanoid()
	if not root or not hum then return false end
	local cam = workspace.CurrentCamera
	local look = Vector3.new(cam.CFrame.LookVector.X, 0, cam.CFrame.LookVector.Z)
	look = look.Magnitude > 0.05 and look.Unit or root.CFrame.LookVector
	local dir = look
	if m.Dir == "Move" and hum.MoveDirection.Magnitude > 0.1 then
		dir = Vector3.new(hum.MoveDirection.X, 0, hum.MoveDirection.Z).Unit
	end
	local att = Instance.new("Attachment")
	att.Name = "DashAttachment"
	att.Parent = root
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = att
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.MaxForce = 4e5
	lv.VectorVelocity = dir * m.Speed
	lv.Parent = root
	Debris:AddItem(lv, m.Time)
	Debris:AddItem(att, m.Time)
	fovPunch(10)
	Sfx.Play("Dash")
	local h = hero()
	afterimages(root, h and h.Color or C.Cyan, 3, m.Time / 3)
	return true
end

---------------------------------------------------------------- HUD (built inside MatchUI so it only shows in matches)
local matchGui = player:WaitForChild("PlayerGui"):WaitForChild("MatchUI")
local bar = Instance.new("Frame")
bar.Name = "AbilityBar"
bar.BackgroundTransparency = 1
bar.AnchorPoint = Vector2.new(0.5, 1)
bar.Position = UDim2.fromScale(0.5, 0.965)
bar.Size = UDim2.fromScale(0.32, 0.19)
bar.Parent = matchGui
local barAspect = Instance.new("UIAspectRatioConstraint")
barAspect.AspectRatio = 3.6
barAspect.Parent = bar
local barList = Instance.new("UIListLayout")
barList.FillDirection = Enum.FillDirection.Horizontal
barList.HorizontalAlignment = Enum.HorizontalAlignment.Center
barList.VerticalAlignment = Enum.VerticalAlignment.Bottom
barList.Padding = UDim.new(0.04, 0)
barList.SortOrder = Enum.SortOrder.LayoutOrder
barList.Parent = bar

type Slot = { Frame: Frame, Icon: ImageLabel, Cover: Frame, Timer: TextLabel, Stroke: UIStroke, Fill: Frame?, Name: TextLabel, Scale: UIScale }
local slots: { [string]: Slot } = {}

local function makeSlot(slot: string, order: number, big: boolean): Slot
	local f = Instance.new("Frame")
	f.Name = slot
	f.LayoutOrder = order
	f.Size = big and UDim2.fromScale(0.34, 1) or UDim2.fromScale(0.27, 0.8)
	f.BackgroundColor3 = C.Bg
	f.BackgroundTransparency = 0.2
	f.ClipsDescendants = false
	UI.Corner(f, 12)
	local ar = Instance.new("UIAspectRatioConstraint"); ar.AspectRatio = 1; ar.Parent = f
	local stroke = UI.Stroke(f, C.Subtext, big and 3 or 2, 0.3)
	local fill: Frame? = nil
	if big then
		fill = Instance.new("Frame")
		fill.Name = "Charge"
		fill.AnchorPoint = Vector2.new(0, 1)
		fill.Position = UDim2.fromScale(0, 1)
		fill.Size = UDim2.fromScale(1, 0)
		fill.BackgroundColor3 = C.Gold
		fill.BackgroundTransparency = 0.45
		fill.BorderSizePixel = 0
		UI.Corner(fill, 12)
		fill.Parent = f
	end
	local icon = UI.Icon({ Parent = f, Icon = "", Size = UDim2.fromScale(0.86, 0.86), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 3 })
	local cover = Instance.new("Frame")
	cover.Name = "Cooldown"
	cover.AnchorPoint = Vector2.new(0, 1)
	cover.Position = UDim2.fromScale(0, 1)
	cover.Size = UDim2.fromScale(1, 0)
	cover.BackgroundColor3 = Color3.new(0, 0, 0)
	cover.BackgroundTransparency = 0.35
	cover.ZIndex = 4
	UI.Corner(cover, 12)
	cover.Parent = f
	local timer = UI.Label({ Parent = f, Text = "", Font = UI.Fonts.Title, Size = UDim2.fromScale(0.9, 0.45), Position = UDim2.fromScale(0.05, 0.27), MaxSize = big and 34 or 28, StrokeSize = 2.5 })
	timer.ZIndex = 5
	local key = UI.Panel({ Parent = f, Name = "Key", Size = UDim2.fromScale(big and 0.42 or 0.5, 0.26), Position = UDim2.fromScale(0.5, 1.02), AnchorPoint = Vector2.new(0.5, 0.5), Color = Color3.fromRGB(240, 240, 250), Transparency = 0, Corner = 6 })
	key.ZIndex = 6
	local keyText = UI.Label({ Parent = key, Text = ControlConfig.Labels[slot], Font = UI.Fonts.Title, Color = Color3.fromRGB(20, 22, 30), Size = UDim2.fromScale(0.9, 0.85), Position = UDim2.fromScale(0.05, 0.08), MaxSize = 20, NoStroke = true })
	keyText.ZIndex = 7
	local name = UI.Label({ Parent = f, Text = "", Font = UI.Fonts.Title, Size = UDim2.fromScale(1.6, 0.2), Position = UDim2.fromScale(-0.3, -0.24), MaxSize = 16, StrokeSize = 1.5 })
	name.ZIndex = 7
	local scale = Instance.new("UIScale"); scale.Parent = f
	f.Parent = bar
	return { Frame = f, Icon = icon, Cover = cover, Timer = timer, Stroke = stroke, Fill = fill, Name = name, Scale = scale }
end

slots.Dash = makeSlot("Dash", 1, false)
slots.Skill = makeSlot("Skill", 2, false)
slots.Ultimate = makeSlot("Ultimate", 3, true)

local shownHero: string? = nil
local function refreshIcons()
	local h = hero()
	if not h or shownHero == h.Id then return end
	shownHero = h.Id
	for _, slot in ipairs(SLOTS) do
		local cfg = h.Abilities[slot]
		local s = slots[slot]
		s.Icon.Image = IconConfig.Get(cfg.Icon)
		-- only the ultimate shows its name above the slot (keeps the bar readable on small screens)
		s.Name.Text = slot == "Ultimate" and cfg.Name or ""
	end
	if slots.Ultimate.Fill then slots.Ultimate.Fill.BackgroundColor3 = h.Color end
end

local function bump(slot: string, ok: boolean)
	local s = slots[slot]
	if ok then
		s.Scale.Scale = 1.18
		TweenService:Create(s.Scale, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	else
		-- not ready: small shake
		local base = s.Frame.Rotation
		for _, r in ipairs({ -6, 6, -3, 0 }) do
			s.Frame.Rotation = base + r
			task.wait(0.03)
		end
	end
end

-- big centre banner when YOU cast an ultimate; small line when someone else does
local banner = UI.Label({ Parent = matchGui, Name = "UltBanner", Text = "", Font = UI.Fonts.Title, Size = UDim2.fromScale(0.6, 0.09), Position = UDim2.fromScale(0.5, 0.24), AnchorPoint = Vector2.new(0.5, 0.5), MaxSize = 72, StrokeSize = 4 })
banner.TextTransparency = 1
local function showBanner(text: string, color: Color3, big: boolean)
	banner.Text = text
	banner.TextColor3 = color
	banner.TextTransparency = 0
	local sc = banner:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	sc.Parent = banner
	sc.Scale = big and 1.6 or 0.6
	TweenService:Create(sc, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = big and 1 or 0.55 }):Play()
	task.delay(1.6, function()
		if banner.Text == text then TweenService:Create(banner, TweenInfo.new(0.4), { TextTransparency = 1 }):Play() end
	end)
end

RunService.RenderStepped:Connect(function()
	if not matchGui.Enabled then return end
	refreshIcons()
	local h = hero()
	if not h then return end
	local t = serverNow()
	for _, slot in ipairs({ "Dash", "Skill" }) do
		local s = slots[slot]
		local readyAt = player:GetAttribute("Ready_" .. slot) or 0
		local left = readyAt - t
		local cd = h.Abilities[slot].Cooldown
		if left > 0 then
			s.Cover.Size = UDim2.fromScale(1, math.clamp(left / cd, 0, 1))
			s.Timer.Text = left >= 1 and tostring(math.ceil(left)) or string.format("%.1f", left)
			s.Stroke.Color = C.Subtext
			s.Icon.ImageTransparency = 0.35
		else
			s.Cover.Size = UDim2.fromScale(1, 0)
			s.Timer.Text = ""
			s.Stroke.Color = Color3.new(1, 1, 1)
			s.Icon.ImageTransparency = 0
		end
	end
	local u = slots.Ultimate
	local charge = player:GetAttribute("UltCharge") or 0
	local active = player:GetAttribute("UltActive") == true
	if u.Fill then u.Fill.Size = UDim2.fromScale(1, charge) end
	if active then
		u.Timer.Text = "ACTIVE"
		u.Stroke.Color = h.Color
		u.Icon.ImageTransparency = 0
	elseif charge >= 1 then
		u.Timer.Text = ""
		u.Stroke.Color = C.Gold
		u.Stroke.Thickness = 3 + math.abs(math.sin(os.clock() * 5)) * 3 -- ready pulse
		u.Icon.ImageTransparency = 0
	else
		u.Timer.Text = math.floor(charge * 100) .. "%"
		u.Stroke.Color = C.Subtext
		u.Stroke.Thickness = 3
		u.Icon.ImageTransparency = 0.4
	end
end)

---------------------------------------------------------------- input
local lastPress: { [string]: number } = {}
local function use(slot: string)
	if not canUse() then return end
	if not isReady(slot) then task.spawn(bump, slot, false) return end
	if lastPress[slot] and os.clock() - lastPress[slot] < 0.3 then return end
	lastPress[slot] = os.clock()
	local h = hero()
	local cfg = h.Abilities[slot]
	if slot == "Dash" then doDash(cfg) end
	UseAbility:FireServer(slot, workspace.CurrentCamera.CFrame.LookVector)
	task.spawn(bump, slot, true)
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == ControlConfig.Binds.Dash then use("Dash")
	elseif input.KeyCode == ControlConfig.Binds.Skill then use("Skill")
	elseif input.KeyCode == ControlConfig.Binds.Ultimate then use("Ultimate") end
end)
-- Phase 9: touch buttons (MobileControls) use the same path
require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("InputBridge")).Ability:Connect(function(slot: string)
	if slot == "Dash" or slot == "Skill" or slot == "Ultimate" then use(slot) end
end)

---------------------------------------------------------------- server-driven effects
AbilityFx.OnClientEvent:Connect(function(data)
	if typeof(data) ~= "table" then return end
	local color = typeof(data.Color) == "Color3" and data.Color or C.Cyan
	if data.Type == "Explosion" then
		burst(data.Position, data.Radius, color, 0.35)
		ring(data.Position, data.Radius * 1.2, color, 0.45)
	elseif data.Type == "Shockwave" then
		ring(data.Position, data.Radius, color, 0.5)
		burst(data.Position, data.Radius * 0.6, color, 0.3, Enum.Material.ForceField)
		local cam = workspace.CurrentCamera
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root and (root.Position - data.Position).Magnitude < data.Radius * 2 then
			for i = 1, 6 do -- camera shake
				cam.CFrame = cam.CFrame * CFrame.Angles(math.rad(math.random(-10, 10) / 10), math.rad(math.random(-10, 10) / 10), 0)
				task.wait(0.02)
			end
		end
	elseif data.Type == "HealRing" then
		ring(data.Position - Vector3.new(0, 2.5, 0), data.Radius, color, 0.5)
	elseif data.Type == "Ping" then
		ring(data.Position, data.Radius, color, 0.6)
	elseif data.Type == "Zap" then
		for _ = 1, 3 do
			local a = math.random() * math.pi * 2
			local r = math.random() * data.Radius
			local p = data.Position + Vector3.new(math.cos(a) * r, 0.5, math.sin(a) * r)
			local bolt = fxPart(Enum.PartType.Block, Vector3.new(0.25, 6, 0.25), CFrame.new(p + Vector3.new(0, 3, 0)) * CFrame.Angles(math.random() * 0.6, 0, math.random() * 0.6), color)
			TweenService:Create(bolt, TweenInfo.new(0.2), { Transparency = 1 }):Play()
			Debris:AddItem(bolt, 0.25)
		end
	elseif data.Type == "Blink" then
		burst(data.From, 3, color, 0.3)
		burst(data.To, 3, color, 0.3)
		local dist = (data.To - data.From).Magnitude
		if dist > 0.5 then
			local streak = fxPart(Enum.PartType.Block, Vector3.new(0.4, 0.4, dist), CFrame.lookAt((data.From + data.To) / 2, data.To), color)
			TweenService:Create(streak, TweenInfo.new(0.25), { Transparency = 1 }):Play()
			Debris:AddItem(streak, 0.3)
		end
		if data.Owner == player.UserId then fovPunch(14) end
	elseif data.Type == "Beam" and typeof(data.From) == "Vector3" and typeof(data.To) == "Vector3" then
		-- Forge's turrets: short neon tracer
		local dist = (data.To - data.From).Magnitude
		if dist > 0.5 then
			local w = typeof(data.Width) == "number" and data.Width or 0.18
			local beam = fxPart(Enum.PartType.Block, Vector3.new(w, w, dist), CFrame.lookAt((data.From + data.To) / 2, data.To), color)
			TweenService:Create(beam, TweenInfo.new(0.12), { Transparency = 1 }):Play()
			Debris:AddItem(beam, 0.15)
		end
	elseif data.Type == "Puff" then
		burst(data.Position, 4, color, 0.4, Enum.Material.ForceField)
	elseif data.Type == "UltCast" then
		local h = HeroConfig.Heroes[data.Hero]
		local col = h and h.Color or C.Gold
		if data.Owner == player.UserId then
			showBanner(string.upper(data.Name) .. "!", col, true)
			fovPunch(8)
		else
			showBanner(string.format("%s: %s", data.Player or "?", string.upper(data.Name)), col, false)
		end
	end
end)

-- Vex's Sensor Trap: outline revealed enemies (visible through walls) for this player only
Reveal.OnClientEvent:Connect(function(models, duration)
	if typeof(models) ~= "table" then return end
	for _, m in ipairs(models) do
		if typeof(m) == "Instance" and m:IsA("Model") and m.Parent then
			local hl = m:FindFirstChild("VexReveal") :: Highlight?
			if not hl then
				hl = Instance.new("Highlight")
				hl.Name = "VexReveal"
				hl.FillTransparency = 0.8
				hl.FillColor = Color3.fromRGB(180, 110, 255)
				hl.OutlineColor = Color3.fromRGB(210, 160, 255)
				hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
				hl.Parent = m
			end
			local stamp = os.clock()
			local outline: Highlight = hl :: Highlight
			outline:SetAttribute("Stamp", stamp)
			task.delay(tonumber(duration) or 0.75, function()
				if hl and hl.Parent and hl:GetAttribute("Stamp") == stamp then hl:Destroy() end
			end)
		end
	end
end)

-- knockback from Titan (players own their physics, so the server asks us to apply it)
Knockback.OnClientEvent:Connect(function(velocity)
	if typeof(velocity) ~= "Vector3" or velocity.Magnitude > 200 then return end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = humanoid()
	if root and hum then
		hum:ChangeState(Enum.HumanoidStateType.Freefall)
		root.AssemblyLinearVelocity = velocity
	end
end)
