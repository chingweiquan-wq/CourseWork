-- VOLT (Controller): Electric Surge / Arc Field / Storm Core
local Volt = {}
local ELECTRIC = Color3.fromRGB(255, 230, 60)

function Volt.Dash(ctx, p, cfg, input)
	return true -- client-driven surge
end

local function field(ctx, p, cfg, input, name, color)
	local point = ctx.AimPoint(p, input.Dir, cfg.Range)
	if not point then return false end
	local zone = ctx.ZonePart(p, name, point, cfg.Radius, color)
	if not zone then return false end
	ctx.RunZone(cfg.Duration, 0.5, function(dt)
		for _, c in ipairs(ctx.Within(ctx.Enemies(p), point, cfg.Radius, 10)) do
			ctx.Damage(p, c, cfg.DamagePerSecond * dt, cfg.Name)
			ctx.Slow(c, name, cfg.SlowMult, 0.7)
		end
		ctx.Fx(p, { Type = "Zap", Position = point, Radius = cfg.Radius, Color = color })
	end, function() return zone.Parent ~= nil and p.Parent ~= nil end)
	task.delay(cfg.Duration, function() zone:Destroy() end)
	return true
end

function Volt.Skill(ctx, p, cfg, input)
	return field(ctx, p, cfg, input, "ArcField", ELECTRIC)
end

function Volt.Ultimate(ctx, p, cfg, input)
	local ok = field(ctx, p, cfg, input, "StormCore", Color3.fromRGB(255, 200, 40))
	if ok then ctx.SetUltActive(p, cfg.Duration) end
	return ok
end

return Volt
