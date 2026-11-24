-- ECHO (Recon): Zip Line / Sonar Pulse / Resonance. Numbers: HeroConfig.Heroes.Echo.Abilities
local Echo = {}
local PINK = Color3.fromRGB(255, 80, 190)

function Echo.Dash(ctx, p, cfg, input)
	return true -- client-driven dash
end

local function modelsOf(list: { any }): { Model }
	local out = {}
	for _, c in ipairs(list) do table.insert(out, c.Model) end
	return out
end

function Echo.Skill(ctx, p, cfg, input)
	local root = ctx.Root(p)
	if not root then return false end
	local found = ctx.Within(ctx.Enemies(p), root.Position, cfg.Radius, cfg.Radius)
	ctx.Reveal(p, modelsOf(found), cfg.RevealTime)
	ctx.Fx(p, { Type = "Ping", Position = root.Position - Vector3.new(0, 2.5, 0), Radius = cfg.Radius, Color = PINK })
	return true
end

function Echo.Ultimate(ctx, p, cfg, input)
	if not ctx.Root(p) then return false end
	ctx.SetUltActive(p, cfg.Pulses * cfg.Interval)
	local char = p.Character
	task.spawn(function()
		for _ = 1, cfg.Pulses do
			local root = ctx.Root(p)
			if not root or p.Character ~= char then return end
			local center = root.Position
			local hit = ctx.Within(ctx.Enemies(p), center, cfg.Radius, 10)
			for _, c in ipairs(hit) do
				ctx.Damage(p, c, cfg.Damage, cfg.Name)
				ctx.Slow(c, "Resonance", cfg.SlowMult, cfg.SlowTime)
			end
			ctx.Reveal(p, modelsOf(hit), cfg.Interval + 1)
			ctx.Fx(p, { Type = "Explosion", Position = center - Vector3.new(0, 2, 0), Radius = cfg.Radius * 0.6, Color = PINK }) -- no camera shake on every pulse
			task.wait(cfg.Interval)
		end
	end)
	return true
end

return Echo
