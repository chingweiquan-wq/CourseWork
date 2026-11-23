-- SHADE (Assassin): Shadow Blink / Cloak / Nightfall
local Shade = {}
local SHADOW = Color3.fromRGB(150, 90, 255)

function Shade.Dash(ctx, p, cfg, input)
	-- server-side teleport: walls are respected, distance is capped by HeroConfig
	local root = ctx.Root(p)
	if not root then return false end
	local dir = Vector3.new(input.Dir.X, 0, input.Dir.Z)
	if dir.Magnitude < 0.05 then return false end
	dir = dir.Unit
	local dist = cfg.Movement.Distance
	local hit = workspace:Raycast(root.Position, dir * dist, ctx.GeometryParams(p))
	if hit then dist = math.max(0, hit.Distance - 2.5) end
	if dist < 2 then return false end
	local from = root.Position
	local dest = from + dir * dist
	p.Character:PivotTo(CFrame.lookAt(dest, dest + dir))
	ctx.Fx(p, { Type = "Blink", From = from, To = dest, Color = SHADOW })
	return true
end

function Shade.Skill(ctx, p, cfg, input)
	ctx.SetCloak(p, cfg.Transparency, cfg.Duration)
	local root = ctx.Root(p)
	if root then ctx.Fx(p, { Type = "Puff", Position = root.Position, Color = SHADOW }) end
	return true
end

function Shade.Ultimate(ctx, p, cfg, input)
	ctx.AddBuff(p, "Nightfall", { DamageMult = cfg.DamageMult, FireRateMult = cfg.FireRateMult, SpeedAdd = cfg.SpeedAdd }, cfg.Duration)
	ctx.SetUltActive(p, cfg.Duration)
	return true
end

return Shade
