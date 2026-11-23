-- SOLACE (Support): Healing Glide / Healing Pulse / Sanctuary
local Solace = {}
local HEAL_COLOR = Color3.fromRGB(80, 255, 200)

function Solace.Dash(ctx, p, cfg, input)
	local healed = {}
	local function pulse()
		local root = ctx.Root(p)
		if not root then return end
		for _, c in ipairs(ctx.Within(ctx.Allies(p), root.Position, cfg.Radius, 8)) do
			if not healed[c.Model] then
				healed[c.Model] = true
				ctx.Heal(p, c, cfg.Heal)
			end
		end
		ctx.Fx(p, { Type = "HealRing", Position = root.Position, Radius = cfg.Radius, Color = HEAL_COLOR })
	end
	pulse()
	task.delay(cfg.Movement.Time, pulse) -- also heals allies passed during the glide
	return true
end

function Solace.Skill(ctx, p, cfg, input)
	local root = ctx.Root(p)
	if not root then return false end
	for _, c in ipairs(ctx.Within(ctx.Allies(p), root.Position, cfg.Radius, 10)) do
		ctx.Heal(p, c, cfg.Heal)
	end
	ctx.Fx(p, { Type = "HealRing", Position = root.Position, Radius = cfg.Radius, Color = HEAL_COLOR })
	return true
end

function Solace.Ultimate(ctx, p, cfg, input)
	local root = ctx.Root(p)
	if not root then return false end
	local center = root.Position - Vector3.new(0, 2.8, 0)
	local zone = ctx.ZonePart(p, "Sanctuary", center, cfg.Radius, HEAL_COLOR)
	if not zone then return false end
	ctx.SetUltActive(p, cfg.Duration)
	ctx.RunZone(cfg.Duration, 0.5, function(dt)
		for _, c in ipairs(ctx.Within(ctx.Allies(p), center, cfg.Radius, 10)) do
			ctx.Heal(p, c, cfg.HealPerSecond * dt)
		end
	end, function() return zone.Parent ~= nil and p.Parent ~= nil end)
	task.delay(cfg.Duration, function() zone:Destroy() end)
	return true
end

return Solace
