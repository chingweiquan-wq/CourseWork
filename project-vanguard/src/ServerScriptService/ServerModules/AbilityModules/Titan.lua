-- TITAN (Tank): Shoulder Charge / Fortress Shield / Groundbreaker
local CollectionService = game:GetService("CollectionService")
local Titan = {}

function Titan.Dash(ctx, p, cfg, input)
	-- the client moves Titan; the server checks for enemies in front during the charge window
	local hit = {}
	local look = Vector3.new(input.Dir.X, 0, input.Dir.Z)
	look = look.Magnitude > 0.05 and look.Unit or Vector3.new(0, 0, -1)
	task.spawn(function()
		local t = 0
		local window = cfg.Movement.Time + 0.15
		while t < window do
			local root = ctx.Root(p)
			if not root then return end
			for _, c in ipairs(ctx.Within(ctx.Enemies(p), root.Position, cfg.HitRadius, 6)) do
				if not hit[c.Model] then
					hit[c.Model] = true
					ctx.Damage(p, c, cfg.Damage, cfg.Name)
					ctx.Knockback(c, look * cfg.Knockback + Vector3.new(0, 25, 0))
				end
			end
			t += task.wait(0.05)
		end
	end)
	return true
end

function Titan.Skill(ctx, p, cfg, input)
	local root = ctx.Root(p)
	local folder = ctx.ObjectFolder(p)
	if not root or not folder then return false end
	local look = Vector3.new(input.Dir.X, 0, input.Dir.Z)
	look = look.Magnitude > 0.05 and look.Unit or root.CFrame.LookVector
	local center = root.Position + look * 5 + Vector3.new(0, cfg.Height / 2 - 2.5, 0)
	local shield = Instance.new("Part")
	shield.Name = "FortressShield"
	shield.Size = Vector3.new(cfg.Width, cfg.Height, 1.2)
	shield.CFrame = CFrame.lookAt(center, center + look)
	shield.Material = Enum.Material.ForceField
	shield.Color = Color3.fromRGB(90, 220, 140)
	shield.Anchored = true; shield.CanCollide = false; shield.CanQuery = true; shield.CanTouch = false
	shield:SetAttribute("Team", p:GetAttribute("Team"))
	shield:SetAttribute("MatchId", p:GetAttribute("MatchId"))
	shield:SetAttribute("ShieldHealth", cfg.Health)
	shield:SetAttribute("MaxHealth", cfg.Health)
	CollectionService:AddTag(shield, "Shield")
	shield.Parent = folder
	task.delay(cfg.Duration, function() if shield.Parent then shield:Destroy() end end)
	return true
end

function Titan.Ultimate(ctx, p, cfg, input)
	local root = ctx.Root(p)
	if not root then return false end
	local center = root.Position - Vector3.new(0, 2.5, 0)
	ctx.SetUltActive(p, 1)
	ctx.Fx(p, { Type = "Shockwave", Position = center, Radius = cfg.Radius, Color = Color3.fromRGB(120, 230, 140) })
	for _, c in ipairs(ctx.Within(ctx.Enemies(p), center, cfg.Radius, 10)) do
		local r = c.Model.HumanoidRootPart
		local offset = r.Position - center
		local flat = Vector3.new(offset.X, 0, offset.Z)
		local away = flat.Magnitude > 0.1 and flat.Unit or Vector3.new(0, 0, 1)
		local falloff = 1 - 0.4 * math.clamp(flat.Magnitude / cfg.Radius, 0, 1)
		ctx.Damage(p, c, cfg.Damage * falloff, cfg.Name)
		ctx.Knockback(c, away * cfg.Knockback * 0.6 + Vector3.new(0, cfg.Knockback * 0.7, 0))
		ctx.Slow(c, "Groundbreaker", cfg.SlowMult, cfg.SlowTime)
	end
	return true
end

return Titan
