-- UIPolish (Phase 7): UI transitions and button feedback for every interface in PlayerGui.
--  * Every button: hover + click sound; buttons without their own animation also get a press bounce.
--  * Every modal (a "Dim" frame holding a "Window"): background fades in, open sound.
--  * Isaac's shop window pops in.
--  * Deploy / return-to-lobby: a full-screen neon scanline wipe.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Sfx = require(Modules:WaitForChild("Sfx"))
local UI = require(Modules:WaitForChild("UIStyle"))
local MatchState = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("MatchState")

local hooked: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local BOUNCE_IN = TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local PRESS = TweenInfo.new(0.07, Enum.EasingStyle.Quad)

---------------------------------------------------------------- buttons
local function hookButton(b: GuiButton)
	if hooked[b] then return end
	hooked[b] = true
	local hasOwnAnim = b:FindFirstChildWhichIsA("UIScale", true) ~= nil or b:GetAttribute("NoPolish") == true
	local scale: UIScale? = nil
	if not hasOwnAnim then
		local s = Instance.new("UIScale")
		s.Name = "PolishScale"
		s.Parent = b
		scale = s
	end
	b.MouseEnter:Connect(function()
		Sfx.Play("UIHover")
		if scale then TweenService:Create(scale, BOUNCE_IN, { Scale = 1.05 }):Play() end
	end)
	b.MouseLeave:Connect(function()
		if scale then TweenService:Create(scale, BOUNCE_IN, { Scale = 1 }):Play() end
	end)
	b.MouseButton1Down:Connect(function()
		if scale then TweenService:Create(scale, PRESS, { Scale = 0.93 }):Play() end
	end)
	b.MouseButton1Up:Connect(function()
		if scale then TweenService:Create(scale, BOUNCE_IN, { Scale = 1.05 }):Play() end
	end)
	b.Activated:Connect(function() Sfx.Play("UIClick") end)
end

---------------------------------------------------------------- modals
local function hookModal(dim: Frame)
	if hooked[dim] then return end
	hooked[dim] = true
	local target = dim.BackgroundTransparency
	dim:GetPropertyChangedSignal("Visible"):Connect(function()
		if dim.Visible then
			Sfx.Play("UIOpen")
			dim.BackgroundTransparency = 1
			TweenService:Create(dim, TweenInfo.new(0.2), { BackgroundTransparency = target }):Play()
		end
	end)
end

local function hookShopFrame(f: GuiObject)
	if hooked[f] then return end
	hooked[f] = true
	f:GetPropertyChangedSignal("Visible"):Connect(function()
		if f.Visible then
			Sfx.Play("UIOpen")
			UI.PopIn(f)
		end
	end)
end

local function consider(d: Instance)
	if d:IsA("GuiButton") then
		hookButton(d)
	elseif d:IsA("Frame") and d.Name ~= "Window" and d:FindFirstChild("Window") then
		hookModal(d)
	elseif d:IsA("GuiObject") and d.Name == "ShopFrame" then
		hookShopFrame(d)
	end
end

for _, d in ipairs(playerGui:GetDescendants()) do consider(d) end
playerGui.DescendantAdded:Connect(function(d)
	task.defer(consider, d) -- let the creator finish setting it up (children, attributes) first
	if d.Name == "Window" and d.Parent then task.defer(consider, d.Parent) end
end)

---------------------------------------------------------------- deploy / return wipe
local wipeGui = Instance.new("ScreenGui")
wipeGui.Name = "TransitionUI"
wipeGui.IgnoreGuiInset = true
wipeGui.ResetOnSpawn = false
wipeGui.DisplayOrder = 50
wipeGui.Parent = playerGui

local cover = Instance.new("Frame")
cover.Name = "Cover"
cover.Size = UDim2.fromScale(1, 1)
cover.BackgroundColor3 = Color3.fromRGB(6, 8, 14)
cover.BackgroundTransparency = 1
cover.BorderSizePixel = 0
cover.Parent = wipeGui
local line = Instance.new("Frame")
line.Name = "Scanline"
line.AnchorPoint = Vector2.new(0, 0.5)
line.Size = UDim2.new(1, 0, 0, 4)
line.BorderSizePixel = 0
line.BackgroundColor3 = Color3.fromRGB(0, 220, 255)
line.BackgroundTransparency = 1
line.Parent = wipeGui
local glow = Instance.new("UIGradient")
glow.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1) })
glow.Parent = line
local caption = UI.Label({ Parent = wipeGui, Text = "", Font = UI.Fonts.Title, Color = Color3.fromRGB(0, 220, 255), Size = UDim2.fromScale(0.5, 0.06), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), MaxSize = 40, StrokeSize = 2 })
caption.TextTransparency = 1
local captionStroke = caption:FindFirstChildOfClass("UIStroke")
if captionStroke then captionStroke.Transparency = 1 end

local wipeToken = 0
local function wipe(text: string, color: Color3)
	wipeToken += 1
	local token = wipeToken
	cover.BackgroundTransparency = 0
	caption.Text = text
	caption.TextColor3 = color
	caption.TextTransparency = 0
	if captionStroke then captionStroke.Transparency = 0 end
	line.BackgroundColor3 = color
	line.BackgroundTransparency = 0
	line.Position = UDim2.fromScale(0, 0)
	TweenService:Create(line, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { Position = UDim2.fromScale(0, 1) }):Play()
	task.delay(0.35, function()
		if token ~= wipeToken then return end
		local out = TweenInfo.new(0.5, Enum.EasingStyle.Quad)
		TweenService:Create(cover, out, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(caption, out, { TextTransparency = 1 }):Play()
		if captionStroke then TweenService:Create(captionStroke, out, { Transparency = 1 }):Play() end
		TweenService:Create(line, out, { BackgroundTransparency = 1 }):Play()
	end)
end

MatchState.OnClientEvent:Connect(function(data)
	if typeof(data) ~= "table" then return end
	if data.State == "PreMatch" then
		wipe("DEPLOYING", Color3.fromRGB(0, 220, 255))
	elseif data.State == "Lobby" then
		wipe("RETURNING TO BASE", Color3.fromRGB(255, 60, 170))
	end
end)
