--!strict
-- WeaponConfig: every primary weapon's balance numbers in one place.
-- Type: "Hitscan" (instant ray), "Projectile" (server-simulated travel), "Melee" (server cone check)
-- FireMode: "Semi" (one shot per click), "Auto" (hold), "Burst" (BurstCount shots per click)
-- Cooldown = seconds between shots (for Burst: between bursts). Spread = cone half-angle in degrees.
-- Pellets (Hitscan only): one shot fires Pellets rays in a FIXED pattern (see PelletDirs) so client and server agree.
-- MagSize 0 = no ammo (melee). Skins (Phase 6) change visuals only; they never touch these numbers.
local WeaponConfig = {}

WeaponConfig.Weapons = {
	BurstRifle = {
		Id = "BurstRifle", DisplayName = "Burst Rifle", Type = "Hitscan", FireMode = "Burst",
		Damage = 18, HeadshotMultiplier = 2, Range = 300, Spread = 0.7,
		BurstCount = 3, BurstInterval = 0.07, Cooldown = 0.42,
		MagSize = 24, ReloadTime = 1.6,
		Color = Color3.fromRGB(255, 140, 40), TracerColor = Color3.fromRGB(255, 190, 90), ViewSize = Vector3.new(0.35, 0.4, 2.2),
	},
	PrecisionRifle = {
		Id = "PrecisionRifle", DisplayName = "Precision Rifle", Type = "Hitscan", FireMode = "Semi",
		Damage = 80, HeadshotMultiplier = 2, Range = 600, Spread = 0,
		Cooldown = 1.1, MagSize = 5, ReloadTime = 2.2,
		Color = Color3.fromRGB(150, 90, 255), TracerColor = Color3.fromRGB(200, 160, 255), ViewSize = Vector3.new(0.3, 0.35, 3.2),
	},
	HeavyCannon = {
		Id = "HeavyCannon", DisplayName = "Heavy Cannon", Type = "Projectile", FireMode = "Semi",
		Damage = 50, HeadshotMultiplier = 1, Range = 260, Spread = 0.5,
		ProjectileSpeed = 140, ProjectileSize = 1.2, SplashDamage = 25, SplashRadius = 7,
		Cooldown = 0.85, MagSize = 8, ReloadTime = 2.4,
		Color = Color3.fromRGB(90, 200, 120), TracerColor = Color3.fromRGB(150, 255, 170), ViewSize = Vector3.new(0.7, 0.7, 2.4),
	},
	MedicalProjector = {
		Id = "MedicalProjector", DisplayName = "Medical Projector", Type = "Projectile", FireMode = "Auto",
		Damage = 18, HeadshotMultiplier = 1.5, Range = 240, Spread = 0.8,
		ProjectileSpeed = 220, ProjectileSize = 0.5, SplashDamage = 0, SplashRadius = 0,
		Cooldown = 0.2, MagSize = 30, ReloadTime = 1.5,
		Color = Color3.fromRGB(80, 255, 200), TracerColor = Color3.fromRGB(150, 255, 220), ViewSize = Vector3.new(0.4, 0.45, 1.8),
	},
	EnergyBlades = {
		Id = "EnergyBlades", DisplayName = "Dual Energy Blades", Type = "Melee", FireMode = "Auto",
		Damage = 38, HeadshotMultiplier = 1, Range = 9, ConeDot = 0.45,
		Cooldown = 0.45, MagSize = 0, ReloadTime = 0,
		Color = Color3.fromRGB(170, 120, 255), TracerColor = Color3.fromRGB(200, 160, 255), ViewSize = Vector3.new(0.15, 0.25, 2.6),
	},
	LightningGauntlet = {
		Id = "LightningGauntlet", DisplayName = "Lightning Gauntlet", Type = "Hitscan", FireMode = "Auto",
		Damage = 9, HeadshotMultiplier = 1, Range = 70, Spread = 1.4,
		Cooldown = 0.09, MagSize = 60, ReloadTime = 1.8,
		Color = Color3.fromRGB(255, 230, 60), TracerColor = Color3.fromRGB(255, 245, 140), ViewSize = Vector3.new(0.8, 0.8, 1.2),
	},
	Scattergun = {
		Id = "Scattergun", DisplayName = "Scattergun", Type = "Hitscan", FireMode = "Semi",
		Damage = 12, HeadshotMultiplier = 1.5, Range = 48, Spread = 0, Pellets = 8, PelletSpread = 4.5,
		Cooldown = 0.75, MagSize = 6, ReloadTime = 2.0,
		Color = Color3.fromRGB(255, 60, 70), TracerColor = Color3.fromRGB(255, 130, 130), ViewSize = Vector3.new(0.3, 0.4, 2.4),
	},
	RivetGun = {
		Id = "RivetGun", DisplayName = "Rivet Gun", Type = "Projectile", FireMode = "Auto",
		Damage = 15, HeadshotMultiplier = 1.5, Range = 220, Spread = 1,
		ProjectileSpeed = 260, ProjectileSize = 0.4, SplashDamage = 0, SplashRadius = 0,
		Cooldown = 0.15, MagSize = 32, ReloadTime = 1.8,
		Color = Color3.fromRGB(60, 140, 255), TracerColor = Color3.fromRGB(140, 190, 255), ViewSize = Vector3.new(0.35, 0.5, 2.2),
	},
	PulseSMG = {
		Id = "PulseSMG", DisplayName = "Pulse SMG", Type = "Hitscan", FireMode = "Auto",
		Damage = 9, HeadshotMultiplier = 1.6, Range = 140, Spread = 1.6,
		Cooldown = 0.075, MagSize = 40, ReloadTime = 1.6,
		Color = Color3.fromRGB(255, 80, 190), TracerColor = Color3.fromRGB(255, 160, 220), ViewSize = Vector3.new(0.3, 0.4, 1.9),
	},
}

-- Fixed shotgun pattern around `dir`: one centre pellet + a ring of (Pellets - 1) at PelletSpread degrees.
function WeaponConfig.PelletDirs(dir: Vector3, w: any): { Vector3 }
	local out = { dir }
	local n = (w.Pellets or 1) - 1
	if n <= 0 then return out end
	local cf = CFrame.lookAt(Vector3.zero, dir)
	local spread = math.rad(w.PelletSpread or 4)
	for i = 1, n do
		local a = (i / n) * math.pi * 2
		local rot = CFrame.Angles(math.sin(a) * spread, math.cos(a) * spread, 0)
		table.insert(out, (cf * rot).LookVector)
	end
	return out
end

return WeaponConfig
