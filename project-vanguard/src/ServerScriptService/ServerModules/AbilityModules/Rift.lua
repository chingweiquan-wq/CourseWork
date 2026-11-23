-- RIFT (Assault): Combat Dash / Pulse Grenade / Overdrive. Numbers: HeroConfig.Heroes.Rift.Abilities
local RunService = game:GetService("RunService")
local Rift = {}

function Rift.Dash(ctx, p, cfg, input)
	return true -- pure movement: the client performs the dash, the server only gates the cooldown
end

function Rift.Skill(ctx, p, cfg, input)
	local head = p.Character and p.Character:FindFirstChild("Head")
	local folder = ctx.ObjectFolder(p)
	if not head or not folder then return false end
	local g = Instance.new("Part")
	g.Name = "PulseGrenade"; g.Shape = Enum.PartType.Ball; g.Size = Vector3.one * 1.2
	g.Material = Enum.Material.Neon; g.Color = Color3.fromRGB(255, 140, 40)
	g.Anchored = true; g.CanCollide = false; g.CanQuery = false; g.CanTouch = false
	local light = Instance.new("PointLight"); light.Color = g.Color; light.Range = 10; light.Brightness = 3; light.Parent = g
	local pos = head.Position + input.Dir * 2
	local vel = input.Dir * cfg.ThrowSpeed + Vector3.new(0, 14, 0)
	g.CFrame = CFrame.new(pos); g.Parent = folder
	local params = ctx.GeometryParams(p)
	task.spawn(function()
		local t, landed = 0, false
		while t < cfg.Fuse do
			local dt = RunService.Heartbeat:Wait()
			t += dt
			-- contact fuse: a grenade that reaches an enemy goes off immediately
			if #ctx.Within(ctx.Enemies(p), pos, cfg.ContactRadius, cfg.ContactRadius + 2) > 0 then break end
			if not landed then
				vel += Vector3.new(0, -workspace.Gravity * 0.6, 0) * dt
				local step = vel * dt
				local hit = workspace:Raycast(pos, step, params)
				if hit then pos = hit.Position + hit.Normal * 0.6; landed = true else pos += step end
				g.CFrame = CFrame.new(pos)
			end
		end
		for _, c in ipairs(ctx.Within(ctx.Enemies(p), pos, cfg.Radius, cfg.Radius)) do
			local d = (c.Model.HumanoidRootPart.Position - pos).Magnitude
			ctx.Damage(p, c, cfg.Damage * (1 - 0.5 * math.clamp(d / cfg.Radius, 0, 1)), cfg.Name)
		end
		ctx.Fx(p, { Type = "Explosion", Position = pos, Radius = cfg.Radius, Color = g.Color })
		g:Destroy()
	end)
	return true
end

function Rift.Ultimate(ctx, p, cfg, input)
	ctx.AddBuff(p, "Overdrive", { DamageMult = cfg.DamageMult, FireRateMult = cfg.FireRateMult }, cfg.Duration)
	ctx.SetUltActive(p, cfg.Duration)
	return true
end

return Rift
