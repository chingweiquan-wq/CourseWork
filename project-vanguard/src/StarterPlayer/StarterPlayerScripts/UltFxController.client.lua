--!strict
-- UltFxController: everything you SEE when a hero fires their ultimate (visual only, never gameplay).
--  * Burst on activation (everyone in the match): expanding neon ring, light pillar, flash light, spark burst
--  * Aura while the ult is active (everyone): rising hero-coloured motes, spinning ground ring, outline glow
--  * Your own ult only: coloured screen-edge glow + a big readable callout with the ult's name
-- Triggered by the server's "UltCast" AbilityFx event; the aura lasts while the caster's UltActive
-- attribute is true (instant ultimates get a short aura).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local Modules = ReplicatedStorage:WaitForChild("Modules")
local HeroConfig = require(Modules:WaitForChild("HeroConfig"))
local UI = require(Modules:WaitForChild("UIStyle"))
local AbilityFx = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("AbilityFx")

local MIN_AURA, MAX_AURA = 1.6, 15
local SPARK = "rbxasset://textures/particles/sparkles_main.dds"

local fxFolder = Instance.new("Folder")
fxFolder.Name = "UltFx"
fxFolder.Parent = workspace

local function fxPart(shape: Enum.PartType, size: Vector3, cf: CFrame, color: Color3): Part
	local p = Instance.new("Part")
	p.Shape = shape
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.Neon
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = fxFolder
	return p
end

---------------------------------------------------------------- burst (activation)
local function burst(root: BasePart, color: Color3)
	local pos = root.Position
	local ground = pos - Vector3.new(0, 2.8, 0)
	-- expanding ground ring
	local ring = fxPart(Enum.PartType.Cylinder, Vector3.new(0.25, 2, 2), CFrame.new(ground) * CFrame.Angles(0, 0, math.rad(90)), color)
	ring.Transparency = 0.15
	TweenService:Create(ring, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.1, 26, 26), Transparency = 1 }):Play()
	Debris:AddItem(ring, 0.55)
	-- light pillar shooting up
	local pillar = fxPart(Enum.PartType.Cylinder, Vector3.new(1, 3, 3), CFrame.new(ground + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, 0, math.rad(90)), color)
	pillar.Transparency = 0.3
	TweenService:Create(pillar, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(26, 1.2, 1.2), CFrame = CFrame.new(ground + Vector3.new(0, 13, 0)) * CFrame.Angles(0, 0, math.rad(90)), Transparency = 1,
	}):Play()
	Debris:AddItem(pillar, 0.5)
	-- flash light + sparks
	local holder = Instance.new("Attachment")
	holder.Parent = root
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 24
	light.Brightness = 6
	light.Parent = holder
	TweenService:Create(light, TweenInfo.new(0.6), { Brightness = 0 }):Play()
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = SPARK
	sparks.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
	sparks.Lifetime = NumberRange.new(0.4, 0.8)
	sparks.Speed = NumberRange.new(18, 32)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Drag = 4
	sparks.Rate = 0
	sparks.Parent = holder
	sparks:Emit(45)
	Debris:AddItem(holder, 1)
end

---------------------------------------------------------------- aura (while active)
local function aura(caster: Player, char: Model, root: BasePart, color: Color3)
	local holder = Instance.new("Attachment")
	holder.Name = "UltAura"
	holder.Position = Vector3.new(0, -1.5, 0)
	holder.Parent = root
	local motes = Instance.new("ParticleEmitter")
	motes.Texture = SPARK
	motes.Color = ColorSequence.new(color)
	motes.LightEmission = 1
	motes.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
	motes.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	motes.Lifetime = NumberRange.new(0.8, 1.3)
	motes.Speed = NumberRange.new(3, 6)
	motes.SpreadAngle = Vector2.new(15, 15)
	motes.EmissionDirection = Enum.NormalId.Top
	motes.Acceleration = Vector3.new(0, 2, 0)
	motes.Rate = 28
	motes.Parent = holder
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 10
	light.Brightness = 1.5
	light.Parent = holder
	-- the server adds an outline glow for timed ultimates; add one for instant ones so every ult reads the same
	local glow: Highlight? = nil
	if not char:FindFirstChild("UltGlow") then
		local g = Instance.new("Highlight")
		g.FillColor = color
		g.FillTransparency = 0.8
		g.OutlineColor = color
		g.DepthMode = Enum.HighlightDepthMode.Occluded
		g.Parent = char
		glow = g
	end
	-- faint ground disc + six neon orbs orbiting the hero's feet (reads as a ring without hiding the floor)
	local ring = fxPart(Enum.PartType.Cylinder, Vector3.new(0.06, 6.5, 6.5), root.CFrame, color)
	ring.Transparency = 0.88
	local orbs: { Part } = {}
	for i = 1, 6 do
		local o = fxPart(Enum.PartType.Ball, Vector3.one * 0.45, root.CFrame, color)
		o.Transparency = 0.1
		orbs[i] = o
	end
	local started = os.clock()
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local age = os.clock() - started
		local active = caster:GetAttribute("UltActive") == true
		if not root.Parent or (age > MIN_AURA and not active) or age > MAX_AURA then
			conn:Disconnect()
			motes.Enabled = false
			TweenService:Create(ring, TweenInfo.new(0.3), { Transparency = 1 }):Play()
			TweenService:Create(light, TweenInfo.new(0.3), { Brightness = 0 }):Play()
			Debris:AddItem(ring, 0.35)
			for _, o in ipairs(orbs) do
				TweenService:Create(o, TweenInfo.new(0.3), { Transparency = 1, Size = Vector3.one * 0.1 }):Play()
				Debris:AddItem(o, 0.35)
			end
			Debris:AddItem(holder, 1.4)
			if glow then glow:Destroy() end
			return
		end
		local feet = root.Position - Vector3.new(0, 2.9, 0)
		ring.CFrame = CFrame.new(feet) * CFrame.Angles(0, 0, math.rad(90))
		ring.Transparency = 0.86 + math.sin(age * 6) * 0.04
		for i, o in ipairs(orbs) do
			local a = age * 2.4 + i * (math.pi * 2 / #orbs)
			o.CFrame = CFrame.new(feet + Vector3.new(math.cos(a) * 3.1, 0.35 + math.sin(age * 4 + i) * 0.25, math.sin(a) * 3.1))
		end
	end)
end

---------------------------------------------------------------- your own screen: edge glow + callout
local screen = Instance.new("ScreenGui")
screen.Name = "UltFxUI"
screen.IgnoreGuiInset = true
screen.ResetOnSpawn = false
screen.DisplayOrder = 8
screen.Parent = player:WaitForChild("PlayerGui")

-- four edge strips with a gradient that fades toward the centre (never covers the crosshair)
local edges: { Frame } = {}
local function edge(size: UDim2, pos: UDim2, rotation: number)
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.Size = size
	f.Position = pos
	f.BackgroundTransparency = 1
	f.Parent = screen
	local g = Instance.new("UIGradient")
	g.Rotation = rotation
	g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	g.Parent = f
	table.insert(edges, f)
end
edge(UDim2.fromScale(0.14, 1), UDim2.fromScale(0, 0), 0) -- left: opaque at x=0
edge(UDim2.fromScale(0.14, 1), UDim2.fromScale(0.86, 0), 180) -- right
edge(UDim2.fromScale(1, 0.16), UDim2.fromScale(0, 0), 90) -- top
edge(UDim2.fromScale(1, 0.16), UDim2.fromScale(0, 0.84), 270) -- bottom

local flash = Instance.new("Frame")
flash.Size = UDim2.fromScale(1, 1)
flash.BorderSizePixel = 0
flash.BackgroundTransparency = 1
flash.Parent = screen

-- callout: hero-coloured bar with the ult name in white
local callout = Instance.new("Frame")
callout.Name = "Callout"
callout.AnchorPoint = Vector2.new(0.5, 0.5)
callout.Position = UDim2.fromScale(0.5, 0.33) -- below the mode label, above the crosshair
callout.Size = UDim2.fromScale(0.5, 0.11)
callout.BorderSizePixel = 0
callout.BackgroundTransparency = 1
callout.Parent = screen
local barGrad = Instance.new("UIGradient")
barGrad.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.25), NumberSequenceKeypoint.new(0.8, 0.25), NumberSequenceKeypoint.new(1, 1),
})
barGrad.Parent = callout
local small = UI.Label({ Parent = callout, Text = "ULTIMATE", Font = UI.Fonts.Bold, Size = UDim2.fromScale(1, 0.28), Position = UDim2.fromScale(0, 0.04), MaxSize = 18, StrokeSize = 1.5 })
local big = UI.Label({ Parent = callout, Text = "", Font = UI.Fonts.Title, Size = UDim2.fromScale(1, 0.62), Position = UDim2.fromScale(0, 0.32), MaxSize = 56, StrokeSize = 3 })
big.TextColor3 = Color3.new(1, 1, 1)
local calloutScale = Instance.new("UIScale")
calloutScale.Parent = callout

local function setCallout(alpha: number)
	callout.BackgroundTransparency = alpha
	small.TextTransparency = alpha
	big.TextTransparency = alpha
	for _, s in ipairs({ small, big }) do
		local st = s:FindFirstChildOfClass("UIStroke")
		if st then st.Transparency = alpha end
	end
end
setCallout(1)

local ownToken = 0
local function ownUlt(name: string, color: Color3)
	ownToken += 1
	local token = ownToken
	-- callout
	callout.BackgroundColor3 = color
	big.Text = string.upper(name)
	local stroke = big:FindFirstChildOfClass("UIStroke")
	if stroke then stroke.Color = color:Lerp(Color3.new(0, 0, 0), 0.55) end
	setCallout(0)
	calloutScale.Scale = 1.5
	TweenService:Create(calloutScale, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	task.delay(1.6, function()
		if ownToken ~= token then return end
		local v = Instance.new("NumberValue")
		v.Value = 0
		v.Changed:Connect(function(a) setCallout(a) end)
		local tw = TweenService:Create(v, TweenInfo.new(0.45), { Value = 1 })
		tw:Play()
		tw.Completed:Connect(function() v:Destroy() end)
	end)
	-- quick colour flash
	flash.BackgroundColor3 = color
	flash.BackgroundTransparency = 0.7
	TweenService:Create(flash, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
	-- edge glow pulses while the ult is active
	for _, f in ipairs(edges) do f.BackgroundColor3 = color end
	local started = os.clock()
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local age = os.clock() - started
		local active = player:GetAttribute("UltActive") == true
		if ownToken ~= token or (age > MIN_AURA and not active) or age > MAX_AURA then
			conn:Disconnect()
			if ownToken == token then
				for _, f in ipairs(edges) do TweenService:Create(f, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play() end
			end
			return
		end
		-- bold but readable: strongest right after casting, then a gentle pulse
		local base = math.clamp(0.35 + age * 0.25, 0.35, 0.6)
		local a = base + math.sin(age * 5) * 0.06
		for _, f in ipairs(edges) do f.BackgroundTransparency = a end
	end)
end

---------------------------------------------------------------- trigger
AbilityFx.OnClientEvent:Connect(function(data)
	if typeof(data) ~= "table" or data.Type ~= "UltCast" then return end
	local caster = typeof(data.Owner) == "number" and Players:GetPlayerByUserId(data.Owner) or nil
	local h = HeroConfig.Heroes[data.Hero]
	local color = h and h.Color or Color3.fromRGB(255, 200, 60)
	if caster == player then
		ownUlt(typeof(data.Name) == "string" and data.Name or "ULTIMATE", color)
	end
	local char = caster and caster.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if caster and char and root then
		burst(root, color)
		aura(caster, char, root, color)
	end
end)
