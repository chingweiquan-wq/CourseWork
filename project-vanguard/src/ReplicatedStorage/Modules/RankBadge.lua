--!strict
-- RankBadge: low-poly 3D rank badges built from parts, shown live in ViewportFrames (no image uploads).
-- Shared by client UI (profile card, results, history, head tags) and server (leaderboard sign).
--
-- Each tier adds parts on top of the one before:
--   Bronze   shield + gem
--   Silver   + side fins
--   Gold     + small wings
--   Platinum + bigger wings
--   Diamond  + crystal wings
--   Master   + spike crown
--   Vanguard + crossed energy blades
-- Badges face -Z; the viewport camera sits in front of them.
local RunService = game:GetService("RunService")

local RankBadge = {}

type Style = {
	Metal: Color3, Panel: Color3, Rim: Color3, Gem: Color3,
	Fins: boolean, Wings: number, CrystalWings: boolean, Crown: boolean, Blades: boolean,
}

local STYLES: { [string]: Style } = {
	Bronze = { Metal = Color3.fromRGB(160, 96, 52), Panel = Color3.fromRGB(110, 62, 34), Rim = Color3.fromRGB(215, 110, 45), Gem = Color3.fromRGB(255, 130, 50),
		Fins = false, Wings = 0, CrystalWings = false, Crown = false, Blades = false },
	Silver = { Metal = Color3.fromRGB(190, 200, 215), Panel = Color3.fromRGB(120, 130, 150), Rim = Color3.fromRGB(200, 235, 255), Gem = Color3.fromRGB(140, 215, 255),
		Fins = true, Wings = 0, CrystalWings = false, Crown = false, Blades = false },
	Gold = { Metal = Color3.fromRGB(235, 180, 45), Panel = Color3.fromRGB(165, 115, 25), Rim = Color3.fromRGB(255, 225, 110), Gem = Color3.fromRGB(255, 235, 90),
		Fins = false, Wings = 1, CrystalWings = false, Crown = false, Blades = false },
	Platinum = { Metal = Color3.fromRGB(160, 225, 215), Panel = Color3.fromRGB(70, 140, 135), Rim = Color3.fromRGB(80, 255, 230), Gem = Color3.fromRGB(60, 245, 225),
		Fins = false, Wings = 1.15, CrystalWings = false, Crown = false, Blades = false },
	Diamond = { Metal = Color3.fromRGB(120, 170, 240), Panel = Color3.fromRGB(50, 80, 160), Rim = Color3.fromRGB(110, 190, 255), Gem = Color3.fromRGB(190, 235, 255),
		Fins = false, Wings = 1.3, CrystalWings = true, Crown = false, Blades = false },
	Master = { Metal = Color3.fromRGB(70, 45, 105), Panel = Color3.fromRGB(35, 22, 55), Rim = Color3.fromRGB(190, 100, 255), Gem = Color3.fromRGB(205, 120, 255),
		Fins = false, Wings = 1.3, CrystalWings = false, Crown = true, Blades = false },
	Vanguard = { Metal = Color3.fromRGB(45, 32, 38), Panel = Color3.fromRGB(110, 25, 30), Rim = Color3.fromRGB(255, 195, 70), Gem = Color3.fromRGB(255, 45, 60),
		Fins = false, Wings = 1.45, CrystalWings = false, Crown = true, Blades = true },
}

local function part(model: Model, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, transparency: number?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.Reflectance = material == Enum.Material.Metal and 0.15 or 0
	p.Transparency = transparency or 0
	p.Parent = model
	return p
end

local D45 = CFrame.Angles(0, 0, math.rad(45))

-- classic shield silhouette = a wide block on top of a 45-degree diamond (gives the low-poly pointed base)
local function shield(model: Model, prefix: string, s: number, z: number, depth: number, color: Color3, material: Enum.Material)
	part(model, prefix .. "Top", Vector3.new(3.1 * s, 1.8 * s, depth), CFrame.new(0, 0.5 * s, z), color, material)
	part(model, prefix .. "Point", Vector3.new(2.2 * s, 2.2 * s, depth), CFrame.new(0, -0.2 * s, z) * D45, color, material)
end

function RankBadge.Build(tierId: string): Model
	local st = STYLES[tierId] or STYLES.Bronze
	local model = Instance.new("Model")
	model.Name = "RankBadge_" .. tierId

	-- crossed energy blades sit behind everything
	if st.Blades then
		for _, side in ipairs({ -1, 1 }) do
			local rot = CFrame.Angles(0, 0, math.rad(35 * side))
			part(model, "Blade", Vector3.new(0.28, 5.6, 0.12), CFrame.new(0, 0.2, 0.55) * rot, Color3.fromRGB(255, 60, 70), Enum.Material.Neon)
			part(model, "Hilt", Vector3.new(0.55, 0.9, 0.2), CFrame.new(0, 0.2, 0.55) * rot * CFrame.new(0, -3.1, 0), st.Rim, Enum.Material.Metal)
		end
	end

	-- glowing rim behind the shield, then metal body, darker inner panel
	shield(model, "Rim", 1.13, 0.22, 0.3, st.Rim, Enum.Material.Neon)
	shield(model, "Body", 1, 0, 0.5, st.Metal, Enum.Material.Metal)
	shield(model, "Panel", 0.72, -0.3, 0.15, st.Panel, Enum.Material.Metal)
	-- centre ridge adds a faceted, low-poly highlight line
	part(model, "Ridge", Vector3.new(0.14, 2.6, 0.1), CFrame.new(0, 0.05, -0.4), st.Metal:Lerp(Color3.new(1, 1, 1), 0.35), Enum.Material.Metal)

	-- gem: rotated block (diamond facet) + small sparkle
	part(model, "GemBack", Vector3.new(1.15, 1.15, 0.3), CFrame.new(0, 0.25, -0.45) * D45, st.Rim:Lerp(Color3.new(0, 0, 0), 0.3), Enum.Material.Metal)
	part(model, "Gem", Vector3.new(0.85, 0.85, 0.35), CFrame.new(0, 0.25, -0.62) * D45, st.Gem, Enum.Material.Neon)
	part(model, "Sparkle", Vector3.new(0.18, 0.18, 0.05), CFrame.new(-0.16, 0.42, -0.82) * D45, Color3.new(1, 1, 1), Enum.Material.Neon, 0.15)

	-- Silver: side fins
	if st.Fins then
		for _, side in ipairs({ -1, 1 }) do
			part(model, "Fin", Vector3.new(0.45, 1.5, 0.3), CFrame.new(1.85 * side, 0.65, 0.05) * CFrame.Angles(0, 0, math.rad(-22 * side)), st.Metal, Enum.Material.Metal)
			part(model, "FinEdge", Vector3.new(0.15, 1.5, 0.32), CFrame.new(2.05 * side, 0.7, 0.05) * CFrame.Angles(0, 0, math.rad(-22 * side)), st.Rim, Enum.Material.Neon)
		end
	end

	-- Gold+: wings made of 3 angled feathers per side, longer each tier
	if st.Wings > 0 then
		local w = st.Wings
		local mat = st.CrystalWings and Enum.Material.Glass or Enum.Material.Metal
		local col = st.CrystalWings and Color3.fromRGB(170, 215, 255) or st.Metal
		for _, side in ipairs({ -1, 1 }) do
			for i = 1, 3 do
				-- feathers grow from the shield's upper corner and fan up and outward (top one longest)
				local len = (2.5 - 0.4 * i) * w
				local a = math.rad(24 + 21 * (i - 1))
				local root = Vector3.new(side * 1.3, 0.35 + 0.12 * i, 0.12)
				local dir = Vector3.new(math.sin(a) * side, math.cos(a), 0)
				local cf = CFrame.new(root + dir * (len / 2)) * CFrame.Angles(0, 0, -a * side)
				part(model, "Feather", Vector3.new(0.42, len, 0.22), cf, col, mat, st.CrystalWings and 0.15 or 0)
				part(model, "FeatherEdge", Vector3.new(0.1, len * 0.92, 0.24), cf * CFrame.new(0.2 * side, 0, 0), st.Rim, Enum.Material.Neon)
			end
		end
	end

	-- Master+: spike crown on top
	if st.Crown then
		part(model, "CrownMid", Vector3.new(0.75, 0.75, 0.35), CFrame.new(0, 1.75, 0) * D45, st.Rim, Enum.Material.Neon)
		for _, side in ipairs({ -1, 1 }) do
			part(model, "CrownSide", Vector3.new(0.5, 0.5, 0.3), CFrame.new(0.85 * side, 1.55, 0) * D45, st.Rim, Enum.Material.Metal)
		end
		part(model, "CrownBand", Vector3.new(2.3, 0.22, 0.4), CFrame.new(0, 1.4, 0), st.Rim, Enum.Material.Metal)
	end

	model.WorldPivot = CFrame.new() -- pivot at the shield centre so it can sway in place
	return model
end

export type BadgeView = {
	Frame: ViewportFrame,
	Set: (tierId: string?) -> (),
}

-- ViewportFrame showing a badge. props: Parent, Size, Position, AnchorPoint, ZIndex, Spin (gentle sway), Name
function RankBadge.Viewport(props: { [string]: any }): BadgeView
	local vf = Instance.new("ViewportFrame")
	vf.Name = props.Name or "RankBadge"
	vf.BackgroundTransparency = 1
	vf.Size = props.Size or UDim2.fromScale(1, 1)
	vf.Position = props.Position or UDim2.new()
	vf.AnchorPoint = props.AnchorPoint or Vector2.zero
	vf.ZIndex = props.ZIndex or 2
	vf.Ambient = Color3.fromRGB(150, 150, 165)
	vf.LightColor = Color3.fromRGB(255, 250, 240)
	vf.LightDirection = Vector3.new(0.45, -0.6, 1)
	local ar = Instance.new("UIAspectRatioConstraint")
	ar.AspectRatio = 1
	ar.Parent = vf
	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	cam.Parent = vf
	vf.CurrentCamera = cam
	vf.Parent = props.Parent

	local current: Model? = nil
	local currentTier: string? = nil
	local function set(tierId: string?)
		if tierId == currentTier then return end
		currentTier = tierId
		if current then current:Destroy(); current = nil end
		vf.Visible = tierId ~= nil
		if not tierId then return end
		local m = RankBadge.Build(tierId)
		local box, size = m:GetBoundingBox()
		local c = box.Position
		local fit = math.max(size.X, size.Y) * 0.5 / math.tan(math.rad(cam.FieldOfView / 2)) * 1.08
		cam.CFrame = CFrame.lookAt(Vector3.new(c.X, c.Y, -fit - 1), Vector3.new(c.X, c.Y, 0))
		m.Parent = vf
		current = m
	end

	if props.Spin and RunService:IsClient() then
		local conn: RBXScriptConnection
		conn = RunService.RenderStepped:Connect(function()
			if not vf.Parent then conn:Disconnect(); return end
			if current and vf.Visible then
				current:PivotTo(CFrame.Angles(0, math.sin(os.clock() * 1.6) * math.rad(28), 0))
			end
		end)
	end

	return { Frame = vf, Set = set }
end

return RankBadge
