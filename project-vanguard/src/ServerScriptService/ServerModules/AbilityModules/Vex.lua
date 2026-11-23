-- VEX (Sniper): Phase Slide / Sensor Trap / Deadeye Protocol
local Vex = {}

function Vex.Dash(ctx, p, cfg, input)
	return true -- client-driven slide
end

function Vex.Skill(ctx, p, cfg, input)
	local point = ctx.AimPoint(p, input.Dir, cfg.Range)
	local folder = ctx.ObjectFolder(p)
	if not point or not folder then return false end
	local device = Instance.new("Part")
	device.Name = "SensorTrap"; device.Shape = Enum.PartType.Cylinder; device.Size = Vector3.new(0.8, 2.2, 2.2)
	device.CFrame = CFrame.new(point + Vector3.new(0, 0.4, 0)) * CFrame.Angles(0, 0, math.rad(90))
	device.Color = Color3.fromRGB(40, 30, 60); device.Material = Enum.Material.Metal
	device.Anchored = true; device.CanCollide = false; device.CanQuery = false; device.CanTouch = false
	device.Parent = folder
	local eye = Instance.new("Part")
	eye.Name = "Eye"; eye.Shape = Enum.PartType.Ball; eye.Size = Vector3.one * 0.9
	eye.CFrame = CFrame.new(point + Vector3.new(0, 1.1, 0)); eye.Color = Color3.fromRGB(180, 110, 255); eye.Material = Enum.Material.Neon
	eye.Anchored = true; eye.CanCollide = false; eye.CanQuery = false; eye.CanTouch = false
	eye.Parent = device
	local light = Instance.new("PointLight"); light.Color = eye.Color; light.Range = 12; light.Parent = eye
	ctx.RunZone(cfg.Duration, 0.5, function()
		local models = {}
		for _, c in ipairs(ctx.Within(ctx.Enemies(p), point, cfg.Radius, cfg.Radius)) do table.insert(models, c.Model) end
		ctx.Reveal(p, models, 0.75)
		ctx.Fx(p, { Type = "Ping", Position = point, Radius = cfg.Radius, Color = eye.Color })
	end, function() return device.Parent ~= nil end)
	task.delay(cfg.Duration, function() device:Destroy() end)
	return true
end

function Vex.Ultimate(ctx, p, cfg, input)
	ctx.AddBuff(p, "Deadeye", { DamageMult = cfg.DamageMult, FireRateMult = cfg.FireRateMult }, cfg.Duration)
	ctx.SetUltActive(p, cfg.Duration)
	return true
end

return Vex
