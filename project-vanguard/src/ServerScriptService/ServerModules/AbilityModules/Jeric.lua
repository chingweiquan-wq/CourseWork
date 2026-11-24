-- JERIC (Duelist): Lunge / Adrenal Surge / Last Stand. Numbers: HeroConfig.Heroes.Jeric.Abilities
local Jeric = {}
local CRIMSON = Color3.fromRGB(255, 60, 70)

function Jeric.Dash(ctx, p, cfg, input)
	return true -- client-driven lunge; the server only gates the cooldown
end

local function selfCombatant(p: Player)
	local char = p.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return nil end
	return { Model = char, Humanoid = hum, Player = p }
end

function Jeric.Skill(ctx, p, cfg, input)
	local me = selfCombatant(p)
	local root = ctx.Root(p)
	if not me or not root then return false end
	ctx.Heal(p, me, cfg.Heal)
	ctx.AddBuff(p, "AdrenalSurge", { SpeedAdd = cfg.SpeedAdd }, cfg.Duration)
	ctx.Fx(p, { Type = "HealRing", Position = root.Position, Radius = 6, Color = CRIMSON })
	return true
end

function Jeric.Ultimate(ctx, p, cfg, input)
	if not selfCombatant(p) then return false end
	ctx.AddBuff(p, "LastStand", { DamageMult = cfg.DamageMult, FireRateMult = cfg.FireRateMult }, cfg.Duration)
	ctx.SetUltActive(p, cfg.Duration)
	local char = p.Character
	ctx.RunZone(cfg.Duration, 0.5, function(dt)
		local me = selfCombatant(p)
		if me then ctx.Heal(p, me, cfg.HealPerSecond * dt) end
	end, function() return p.Parent ~= nil and p.Character == char end)
	return true
end

return Jeric
