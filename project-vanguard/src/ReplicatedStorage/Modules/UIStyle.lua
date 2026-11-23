--!strict
-- UIStyle: shared look-and-feel helpers so every menu matches (dark panels, neon strokes, tweened hovers).
local TweenService = game:GetService("TweenService")

local UIStyle = {}

UIStyle.Colors = {
	Bg = Color3.fromRGB(12, 14, 24),
	Panel = Color3.fromRGB(20, 24, 38),
	PanelLight = Color3.fromRGB(32, 38, 60),
	Text = Color3.fromRGB(230, 236, 255),
	Subtext = Color3.fromRGB(140, 150, 185),
	Cyan = Color3.fromRGB(0, 220, 255),
	Magenta = Color3.fromRGB(255, 60, 200),
	Gold = Color3.fromRGB(255, 200, 60),
	Green = Color3.fromRGB(80, 255, 160),
	Red = Color3.fromRGB(255, 70, 110),
}
-- Chunky cartoon font with black outlines (matches popular Roblox shooter lobbies)
UIStyle.Fonts = { Title = Enum.Font.FredokaOne, Bold = Enum.Font.FredokaOne, Body = Enum.Font.GothamBold }

local IconConfig = require(script.Parent.IconConfig)

function UIStyle.Corner(parent: Instance, px: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, px or 10)
	c.Parent = parent
	return c
end

function UIStyle.Stroke(parent: Instance, color: Color3, thickness: number?, transparency: number?)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness or 2
	s.Transparency = transparency or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

function UIStyle.Panel(props: { [string]: any }): Frame
	local f = Instance.new("Frame")
	f.BackgroundColor3 = props.Color or UIStyle.Colors.Panel
	f.BackgroundTransparency = props.Transparency or 0.1
	f.BorderSizePixel = 0
	f.Size = props.Size or UDim2.fromScale(0.5, 0.5)
	f.Position = props.Position or UDim2.new()
	f.AnchorPoint = props.AnchorPoint or Vector2.zero
	f.Name = props.Name or "Panel"
	UIStyle.Corner(f, props.Corner)
	if props.Stroke then UIStyle.Stroke(f, props.Stroke, props.StrokeThickness, 0.2) end
	f.Parent = props.Parent
	return f
end

function UIStyle.Label(props: { [string]: any }): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Text = props.Text or ""
	t.TextColor3 = props.Color or UIStyle.Colors.Text
	t.Font = props.Font or UIStyle.Fonts.Bold
	t.TextScaled = true
	t.Size = props.Size or UDim2.fromScale(1, 0.1)
	t.Position = props.Position or UDim2.new()
	t.AnchorPoint = props.AnchorPoint or Vector2.zero
	t.TextXAlignment = props.AlignX or Enum.TextXAlignment.Center
	t.TextYAlignment = props.AlignY or Enum.TextYAlignment.Center
	t.TextWrapped = true
	t.Name = props.Name or "Label"
	t.RichText = props.Rich or false
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = props.MaxSize or 48
	c.Parent = t
	if props.NoStroke ~= true and t.Font == Enum.Font.FredokaOne then
		local s = Instance.new("UIStroke")
		s.Thickness = props.StrokeSize or 1.5
		s.Color = Color3.new(0, 0, 0)
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		s.Parent = t
	end
	t.Parent = props.Parent
	return t
end

-- Image icon from IconConfig (falls back to nothing if the id isn't set yet)
function UIStyle.Icon(props: { [string]: any }): ImageLabel
	local i = Instance.new("ImageLabel")
	i.Name = (props.Icon or "Icon") .. "Icon"
	i.BackgroundTransparency = 1
	i.Image = IconConfig.Get(props.Icon)
	i.ScaleType = Enum.ScaleType.Fit
	i.Size = props.Size or UDim2.fromScale(1, 1)
	i.Position = props.Position or UDim2.new()
	i.AnchorPoint = props.AnchorPoint or Vector2.zero
	i.ZIndex = props.ZIndex or 2
	i.Parent = props.Parent
	return i
end

-- Dock item: big icon with a bouncy hover and an outlined label underneath
function UIStyle.DockButton(props: { [string]: any }): ImageButton
	local b = Instance.new("ImageButton")
	b.Name = props.Name or "DockButton"
	b.BackgroundTransparency = 1
	b.Image = ""
	b.Size = props.Size or UDim2.fromScale(0.2, 1)
	b.LayoutOrder = props.Order or 0
	local icon = UIStyle.Icon({ Parent = b, Icon = props.Icon, Size = UDim2.fromScale(1, 0.74), Position = UDim2.fromScale(0, 0) })
	UIStyle.Label({ Parent = b, Text = props.Text or "", Font = UIStyle.Fonts.Title, Size = UDim2.fromScale(1.3, 0.28), Position = UDim2.fromScale(-0.15, 0.72), MaxSize = 28, StrokeSize = 2.5 })
	local scale = Instance.new("UIScale")
	scale.Parent = icon
	local info = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	b.MouseEnter:Connect(function()
		TweenService:Create(scale, info, { Scale = 1.15 }):Play()
		TweenService:Create(icon, info, { Rotation = -6 }):Play()
	end)
	b.MouseLeave:Connect(function()
		TweenService:Create(scale, info, { Scale = 1 }):Play()
		TweenService:Create(icon, info, { Rotation = 0 }):Play()
	end)
	b.MouseButton1Down:Connect(function() TweenService:Create(scale, TweenInfo.new(0.08), { Scale = 0.9 }):Play() end)
	b.MouseButton1Up:Connect(function() TweenService:Create(scale, info, { Scale = 1.15 }):Play() end)
	b.Parent = props.Parent
	return b
end

function UIStyle.Button(props: { [string]: any }): TextButton
	local accent: Color3 = props.Accent or UIStyle.Colors.Cyan
	local b = Instance.new("TextButton")
	b.AutoButtonColor = false
	b.BackgroundColor3 = props.Color or UIStyle.Colors.PanelLight
	b.BackgroundTransparency = 0.05
	b.BorderSizePixel = 0
	b.Text = props.Text or ""
	b.TextColor3 = props.TextColor or UIStyle.Colors.Text
	b.Font = props.Font or UIStyle.Fonts.Title
	b.TextScaled = true
	b.Size = props.Size or UDim2.fromScale(0.2, 0.08)
	b.Position = props.Position or UDim2.new()
	b.AnchorPoint = props.AnchorPoint or Vector2.zero
	b.Name = props.Name or "Button"
	UIStyle.Corner(b, props.Corner or 8)
	local stroke = UIStyle.Stroke(b, accent, 2, 0.35)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0.18, 0); pad.PaddingBottom = UDim.new(0.18, 0)
	pad.PaddingLeft = UDim.new(0.04, 0); pad.PaddingRight = UDim.new(0.04, 0)
	pad.Parent = b
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = props.MaxSize or 32
	c.Parent = b
	local base = b.BackgroundColor3
	local info = TweenInfo.new(0.15, Enum.EasingStyle.Quad)
	b.MouseEnter:Connect(function()
		TweenService:Create(b, info, { BackgroundColor3 = base:Lerp(accent, 0.25) }):Play()
		TweenService:Create(stroke, info, { Transparency = 0 }):Play()
	end)
	b.MouseLeave:Connect(function()
		TweenService:Create(b, info, { BackgroundColor3 = base }):Play()
		TweenService:Create(stroke, info, { Transparency = 0.35 }):Play()
	end)
	b.Parent = props.Parent
	return b
end

function UIStyle.ScreenGui(name: string, parent: Instance, order: number?): ScreenGui
	local g = Instance.new("ScreenGui")
	g.Name = name
	g.ResetOnSpawn = false
	g.IgnoreGuiInset = true
	g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	g.DisplayOrder = order or 0
	g.Parent = parent
	return g
end

function UIStyle.PopIn(frame: GuiObject)
	frame.Visible = true
	local scale = frame:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Parent = frame
	scale.Scale = 0.9
	TweenService:Create(scale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

return UIStyle
