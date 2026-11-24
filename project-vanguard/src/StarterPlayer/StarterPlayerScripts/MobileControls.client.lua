-- MobileControls (Phase 9): on-screen buttons for touch devices (phones / tablets).
-- Shown only on touch screens and only during a match: a big hold-to-fire button, Reload, and the three
-- hero abilities (with their icons + cooldown dimming). Buttons sit above Roblox's own jump button.
-- They go through InputBridge, so they use exactly the same client code (and server checks) as PC input.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

if not UserInputService.TouchEnabled then return end -- PC / console: nothing to do

local player = Players.LocalPlayer
local Modules = ReplicatedStorage:WaitForChild("Modules")
local InputBridge = require(Modules:WaitForChild("InputBridge"))
local HeroConfig = require(Modules:WaitForChild("HeroConfig"))
local IconConfig = require(Modules:WaitForChild("IconConfig"))
local UI = require(Modules:WaitForChild("UIStyle"))
local C = UI.Colors

local gui = Instance.new("ScreenGui")
gui.Name = "MobileControls"
gui.ResetOnSpawn = false
gui.DisplayOrder = 5
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

-- sizes follow the screen height so they stay thumb-sized on every phone
local function circle(name: string, size: number, pos: UDim2, color: Color3, text: string?): (ImageButton, TextLabel)
	local b = Instance.new("ImageButton")
	b.Name = name
	b.AnchorPoint = Vector2.new(0.5, 0.5)
	b.Size = UDim2.fromScale(size, size)
	b.Position = pos
	b.BackgroundColor3 = C.Panel
	b.BackgroundTransparency = 0.25
	b.AutoButtonColor = false
	b.ImageTransparency = 0
	b.ScaleType = Enum.ScaleType.Fit
	b:SetAttribute("NoPolish", true) -- no hover sounds on touch buttons
	local ar = Instance.new("UIAspectRatioConstraint"); ar.AspectRatio = 1; ar.DominantAxis = Enum.DominantAxis.Height; ar.Parent = b
	local cr = Instance.new("UICorner"); cr.CornerRadius = UDim.new(0.5, 0); cr.Parent = b
	local st = Instance.new("UIStroke"); st.Color = color; st.Thickness = 3; st.Parent = b
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0.18, 0); pad.PaddingBottom = UDim.new(0.18, 0); pad.PaddingLeft = UDim.new(0.18, 0); pad.PaddingRight = UDim.new(0.18, 0)
	pad.Parent = b
	local label = UI.Label({ Parent = b, Text = text or "", Font = UI.Fonts.Title, Color = color, Size = UDim2.fromScale(1, 1), MaxSize = 30, StrokeSize = 2 })
	b.Parent = gui
	return b, label
end

-- layout (scale of screen height; X positions are scale of width, right side)
local fireBtn = circle("Fire", 0.2, UDim2.new(0.86, 0, 0.6, 0), C.Red, "FIRE")
local reloadBtn = circle("Reload", 0.1, UDim2.new(0.75, 0, 0.72, 0), C.Subtext, "R")
local dashBtn = circle("Dash", 0.12, UDim2.new(0.73, 0, 0.5, 0), C.Cyan)
local skillBtn = circle("Skill", 0.12, UDim2.new(0.8, 0, 0.36, 0), C.Green)
local ultBtn = circle("Ultimate", 0.14, UDim2.new(0.92, 0, 0.32, 0), C.Gold)
local abilityButtons = { Dash = dashBtn, Skill = skillBtn, Ultimate = ultBtn }

-- hold-to-fire (auto/burst weapons keep firing while held)
fireBtn.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
		fireBtn.BackgroundTransparency = 0
		InputBridge.SetFire(true)
	end
end)
fireBtn.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
		fireBtn.BackgroundTransparency = 0.25
		InputBridge.SetFire(false)
	end
end)
reloadBtn.Activated:Connect(function() InputBridge.PressReload() end)
for slot, b in pairs(abilityButtons) do
	b.Activated:Connect(function() InputBridge.PressAbility(slot) end)
end

-- hero icons for the ability buttons
local function refreshIcons()
	local heroId = player:GetAttribute("Hero")
	local hero = typeof(heroId) == "string" and HeroConfig.Heroes[heroId]
	if not hero then return end
	for slot, b in pairs(abilityButtons) do
		local cfg = hero.Abilities[slot]
		b.Image = cfg and IconConfig.Get(cfg.Icon) or ""
	end
end
player:GetAttributeChangedSignal("Hero"):Connect(refreshIcons)
refreshIcons()

-- only during matches; release the trigger when hidden so nothing keeps firing
local function refreshVisible()
	local inMatch = player:GetAttribute("MatchId") ~= nil
	gui.Enabled = inMatch
	if not inMatch then InputBridge.SetFire(false) end
end
player:GetAttributeChangedSignal("MatchId"):Connect(refreshVisible)
refreshVisible()

-- cooldown dimming (cheap: 10 times a second)
local acc = 0
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc < 0.1 or not gui.Enabled then return end
	acc = 0
	local now = workspace:GetServerTimeNow()
	for slot, b in pairs(abilityButtons) do
		local ready = now >= (tonumber(player:GetAttribute("Ready_" .. slot)) or 0)
		b.ImageTransparency = ready and 0 or 0.6
		b.BackgroundTransparency = ready and 0.25 or 0.6
	end
end)
