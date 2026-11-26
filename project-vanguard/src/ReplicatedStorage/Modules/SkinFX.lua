--!strict
-- SkinFX (client): extra effects for weapon skins, on top of the normal combat effects.
--   Muzzle(pos, dir, skinId)  themed flash ring at the barrel
--   Impact(pos, skinId)       themed hit sparks (gold coins / void shards / embers / frost)
--   Kill(pos, skinId)         themed burst where a victim of a skinned weapon falls
-- Uncommon skins (Loud = false) get a small, tasteful version; Legendary skins get the full show.
-- Everything is local neon parts that fade out; nothing touches gameplay or the network.
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local SkinVisuals = require(script.Parent.SkinVisuals)

local SkinFX = {}

local folder = workspace:FindFirstChild("SkinFxParts") or Instance.new("Folder")
folder.Name = "SkinFxParts"
folder.Parent = workspace

local function part(size: Vector3, cf: CFrame, color: Color3, shape: Enum.PartType?, mat: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.CastShadow = false
	p.Material = mat or Enum.Material.Neon
	p.Color = color
	p.Size = size
	p.CFrame = cf
	if shape then p.Shape = shape end
	p.Parent = folder
	return p
end

local function tween(p: Instance, t: number, goal: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	TweenService:Create(p, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), goal):Play()
end

local function randUnit(): Vector3
	local v = Vector3.new(math.random() * 2 - 1, math.random() * 2 - 1, math.random() * 2 - 1)
	return v.Magnitude < 0.05 and Vector3.yAxis or v.Unit
end

local function light(p: BasePart, color: Color3, range: number, brightness: number, t: number)
	local l = Instance.new("PointLight")
	l.Color = color; l.Range = range; l.Brightness = brightness; l.Shadows = false
	l.Parent = p
	tween(l, t, { Brightness = 0 })
end

-- a flat ring that expands along the ground (or facing `normal`)
local function ring(pos: Vector3, color: Color3, from: number, to: number, t: number, normal: Vector3?)
	local n = normal or Vector3.yAxis
	local cf = CFrame.lookAt(pos, pos + n) * CFrame.Angles(0, math.pi / 2, 0)
	local r = part(Vector3.new(0.12, from, from), cf, color, Enum.PartType.Cylinder)
	r.Transparency = 0.25
	tween(r, t, { Size = Vector3.new(0.05, to, to), Transparency = 1 })
	Debris:AddItem(r, t + 0.05)
end

-- pieces that fly out, optionally fall with gravity, spin and fade
local function burst(pos: Vector3, count: number, color: Color3, color2: Color3, size: Vector3, speed: number, t: number, gravity: number, shape: Enum.PartType?, up: number?)
	for i = 1, count do
		local d = randUnit()
		if up then d = (d + Vector3.new(0, up, 0)).Unit end
		local c = (i % 2 == 0) and color2 or color
		local p = part(size * (0.7 + math.random() * 0.6), CFrame.new(pos) * CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6), c, shape)
		local v = d * speed * (0.6 + math.random() * 0.7)
		local tt = t * (0.8 + math.random() * 0.4)
		-- two-step arc: rise along v, then drop by gravity
		local mid = pos + v * tt * 0.5 + Vector3.new(0, -gravity * (tt * 0.5) ^ 2 * 0.5, 0)
		local fin = pos + v * tt + Vector3.new(0, -gravity * tt ^ 2 * 0.5, 0)
		local spin = CFrame.Angles(math.random() * 8, math.random() * 8, math.random() * 8)
		tween(p, tt * 0.5, { CFrame = CFrame.new(mid) * spin }, Enum.EasingStyle.Sine)
		task.delay(tt * 0.5, function()
			if p.Parent then tween(p, tt * 0.5, { CFrame = CFrame.new(fin) * spin * spin, Transparency = 1, Size = p.Size * 0.4 }, Enum.EasingStyle.Sine, Enum.EasingDirection.In) end
		end)
		Debris:AddItem(p, tt + 0.1)
	end
end

local function themeOf(skinId: string?): SkinVisuals.Theme?
	local th = SkinVisuals.GetTheme(skinId)
	if th and th.Fx then return th end
	return nil
end

function SkinFX.Muzzle(pos: Vector3, dir: Vector3, skinId: string?)
	local th = themeOf(skinId)
	if not th then return end
	local c1 = th.FxColor or th.Color
	if th.Loud then
		ring(pos, c1, 0.3, 2.2, 0.14, dir)
		if th.Fx == "Inferno" then
			burst(pos, 3, c1, th.FxColor2 or c1, Vector3.one * 0.18, 9, 0.25, -4, Enum.PartType.Ball)
		elseif th.Fx == "Gold" then
			burst(pos, 2, c1, th.FxColor2 or c1, Vector3.new(0.3, 0.06, 0.3), 7, 0.3, 20, Enum.PartType.Cylinder)
		elseif th.Fx == "Void" then
			burst(pos, 3, c1, th.FxColor2 or c1, Vector3.new(0.1, 0.1, 0.4), 6, 0.2, 0)
		end
	else
		ring(pos, c1, 0.2, 1.1, 0.1, dir)
	end
end

function SkinFX.Impact(pos: Vector3, skinId: string?)
	local th = themeOf(skinId)
	if not th then return end
	local c1, c2 = th.FxColor or th.Color, th.FxColor2 or Color3.new(1, 1, 1)
	if not th.Loud then
		burst(pos, 3, c1, c2, Vector3.new(0.12, 0.12, 0.3), 5, 0.25, 6) -- a few frost flecks
		return
	end
	if th.Fx == "Gold" then
		burst(pos, 4, c1, c2, Vector3.new(0.35, 0.07, 0.35), 8, 0.45, 26, Enum.PartType.Cylinder, 0.8) -- little coins
	elseif th.Fx == "Void" then
		local orb = part(Vector3.one * 0.9, CFrame.new(pos), Color3.fromRGB(25, 5, 45), Enum.PartType.Ball)
		tween(orb, 0.22, { Size = Vector3.one * 0.05, Transparency = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.In) -- tiny implosion
		Debris:AddItem(orb, 0.3)
		burst(pos, 4, c1, c2, Vector3.new(0.1, 0.1, 0.45), 7, 0.3, 0)
	elseif th.Fx == "Inferno" then
		burst(pos, 5, c1, c2, Vector3.one * 0.2, 6, 0.5, -6, Enum.PartType.Ball, 0.6) -- embers float up
	end
end

function SkinFX.Kill(pos: Vector3, skinId: string?)
	local th = themeOf(skinId)
	if not th then return end
	local c1, c2 = th.FxColor or th.Color, th.FxColor2 or Color3.new(1, 1, 1)
	local ground = pos - Vector3.new(0, 2.6, 0)
	if not th.Loud then
		-- Uncommon (Frost): a crisp ice burst and a frost ring
		ring(ground, c1, 1, 9, 0.45)
		burst(pos, 10, c1, c2, Vector3.new(0.2, 0.2, 0.7), 10, 0.5, 10)
		return
	end
	local core = part(Vector3.one * 1.5, CFrame.new(pos), c1, Enum.PartType.Ball)
	core.Transparency = 0.2
	light(core, c1, 18, 6, 0.9)
	ring(ground, c1, 1, 16, 0.6)
	ring(pos, c2, 1, 10, 0.45, Vector3.new(0, 0.3, 1))
	if th.Fx == "Gold" then
		-- jackpot: a fountain of spinning gold coins + glitter
		tween(core, 0.5, { Size = Vector3.one * 6, Transparency = 1 })
		burst(pos, 22, c1, c2, Vector3.new(0.6, 0.1, 0.6), 16, 1.1, 34, Enum.PartType.Cylinder, 1.6)
		burst(pos, 14, c2, c1, Vector3.one * 0.18, 9, 0.7, 4, Enum.PartType.Ball)
	elseif th.Fx == "Void" then
		-- implosion: everything gets sucked into a dark core, then crystal shards fire out
		local dark = part(Vector3.one * 7, CFrame.new(pos), Color3.fromRGB(20, 0, 40), Enum.PartType.Ball, Enum.Material.ForceField)
		tween(dark, 0.35, { Size = Vector3.one * 0.3 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		Debris:AddItem(dark, 0.4)
		tween(core, 0.35, { Size = Vector3.one * 0.2 })
		task.delay(0.35, function()
			if core.Parent then tween(core, 0.4, { Size = Vector3.one * 5, Transparency = 1 }) end
			burst(pos, 18, c1, c2, Vector3.new(0.2, 0.2, 1.1), 18, 0.6, 0)
			ring(pos, c1, 0.5, 12, 0.4, Vector3.xAxis)
		end)
	elseif th.Fx == "Inferno" then
		-- eruption: a pillar of fire, embers raining up, a burning ring on the floor
		tween(core, 0.5, { Size = Vector3.one * 5, Transparency = 1 })
		local pillar = part(Vector3.new(10, 2.5, 2.5), CFrame.new(ground + Vector3.new(0, 5, 0)) * CFrame.Angles(0, 0, math.pi / 2), c1, Enum.PartType.Cylinder)
		pillar.Transparency = 0.3
		tween(pillar, 0.6, { Size = Vector3.new(14, 0.2, 0.2), Transparency = 1, CFrame = pillar.CFrame + Vector3.new(0, 3, 0) })
		Debris:AddItem(pillar, 0.7)
		burst(pos, 24, c1, c2, Vector3.one * 0.3, 10, 1.0, -8, Enum.PartType.Ball, 1.2)
		ring(ground, c2, 2, 12, 0.8)
	end
	Debris:AddItem(core, 1)
end

return SkinFX
