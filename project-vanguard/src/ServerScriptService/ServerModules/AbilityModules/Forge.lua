-- FORGE (Engineer): Thruster Hop / Sentry Turret / Siege Sentry. Numbers: HeroConfig.Heroes.Forge.Abilities
-- Turrets are server objects: they pick the nearest enemy they can see and deal damage on a fixed interval.
local Forge = {}
local STEEL = Color3.fromRGB(60, 140, 255)
local DARK = Color3.fromRGB(34, 38, 50)

function Forge.Dash(ctx, p, cfg, input)
	return true -- client-driven hop
end

local function part(props: { [string]: any }, parent: Instance): Part
	local x = Instance.new("Part")
	x.Anchored = true; x.CanCollide = false; x.CanQuery = false; x.CanTouch = false
	x.TopSurface = Enum.SurfaceType.Smooth; x.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do (x :: any)[k] = v end
	x.Parent = parent
	return x
end

-- low-poly turret: base, swivel head, barrel and a neon eye; returns the model and an "aim" function
local function buildTurret(name: string, pos: Vector3, scale: number, owner: Player, folder: Instance)
	local m = Instance.new("Model")
	m.Name = name
	m:SetAttribute("Owner", owner.UserId)
	part({ Name = "Base", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 3, 3) * scale, CFrame = CFrame.new(pos + Vector3.new(0, 0.3 * scale, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = DARK, Material = Enum.Material.Metal }, m)
	part({ Name = "Post", Size = Vector3.new(0.6, 1.6, 0.6) * scale, CFrame = CFrame.new(pos + Vector3.new(0, 1.3 * scale, 0)), Color = DARK, Material = Enum.Material.Metal }, m)
	part({ Name = "Ring", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.15, 3.2, 3.2) * scale, CFrame = CFrame.new(pos + Vector3.new(0, 0.62 * scale, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = STEEL, Material = Enum.Material.Neon }, m)
	local pivot = pos + Vector3.new(0, 2.3 * scale, 0)
	local head = part({ Name = "Head", Size = Vector3.new(1.6, 1.1, 1.8) * scale, Color = DARK, Material = Enum.Material.Metal }, m)
	local barrel = part({ Name = "Barrel", Size = Vector3.new(0.35, 0.35, 1.8) * scale, Color = Color3.fromRGB(20, 22, 30), Material = Enum.Material.Metal }, m)
	local eye = part({ Name = "Eye", Size = Vector3.new(0.9, 0.25, 0.1) * scale, Color = STEEL, Material = Enum.Material.Neon }, m)
	local light = Instance.new("PointLight"); light.Color = STEEL; light.Range = 8 * scale; light.Brightness = 2; light.Parent = eye
	local function aim(dir: Vector3)
		local flat = Vector3.new(dir.X, 0, dir.Z)
		if flat.Magnitude < 0.05 then flat = Vector3.new(0, 0, -1) end
		local cf = CFrame.lookAt(pivot, pivot + flat)
		head.CFrame = cf
		barrel.CFrame = cf * CFrame.new(0, 0, -1.6 * scale)
		eye.CFrame = cf * CFrame.new(0, 0.1 * scale, -0.91 * scale)
	end
	m.Parent = folder
	return m, aim, function() return barrel.CFrame * Vector3.new(0, 0, -0.9 * scale) end
end

local function deploy(ctx, p: Player, cfg, input, name: string, scale: number): boolean
	local point = ctx.AimPoint(p, input.Dir, cfg.Range)
	local folder = ctx.ObjectFolder(p)
	if not point or not folder then return false end
	-- one of each turret type per Forge: a new one replaces the old one
	for _, old in ipairs(folder:GetChildren()) do
		if old.Name == name and old:GetAttribute("Owner") == p.UserId then old:Destroy() end
	end
	local look = Vector3.new(input.Dir.X, 0, input.Dir.Z)
	local model, aim, muzzle = buildTurret(name, point, scale, p, folder)
	aim(look)
	local params = ctx.GeometryParams(p)
	ctx.RunZone(cfg.Duration, cfg.Interval, function()
		local from = muzzle()
		local best, bestDist = nil, cfg.TargetRange
		for _, c in ipairs(ctx.Enemies(p)) do
			local r = c.Model:FindFirstChild("HumanoidRootPart") :: BasePart?
			if r then
				local d = (r.Position - from).Magnitude
				-- must be in range and visible (walls block turret fire)
				if d < bestDist and not workspace:Raycast(from, r.Position - from, params) then
					best, bestDist = c, d
				end
			end
		end
		if best then
			local to = best.Model.HumanoidRootPart.Position
			aim(to - from)
			ctx.Damage(p, best, cfg.Damage, cfg.Name)
			ctx.Fx(p, { Type = "Beam", From = muzzle(), To = to, Color = STEEL, Width = 0.18 * scale })
		end
	end, function() return model.Parent ~= nil and p.Parent ~= nil end)
	task.delay(cfg.Duration, function() if model.Parent then model:Destroy() end end)
	return true
end

function Forge.Skill(ctx, p, cfg, input)
	return deploy(ctx, p, cfg, input, "SentryTurret", 1)
end

function Forge.Ultimate(ctx, p, cfg, input)
	local ok = deploy(ctx, p, cfg, input, "SiegeSentry", 1.7)
	if ok then ctx.SetUltActive(p, cfg.Duration) end
	return ok
end

return Forge
