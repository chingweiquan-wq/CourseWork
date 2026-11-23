--!strict
-- HeroConfig: display data + ALL balance numbers for every hero and ability.
-- Ability LOGIC lives in ServerScriptService.ServerModules.AbilityModules.<Hero>; tune numbers here only.
--
-- Dash.Movement (client-driven movement, server-gated cooldown):
--   Type "Dash"  : velocity burst. Dir "Look" = camera facing (flat), "Move" = WASD direction (falls back to look)
--   Type "Blink" : server teleport up to Distance studs (walls are respected)
local HeroConfig = {}

HeroConfig.StarterHeroes = { "Rift", "Solace" } -- free for every new player

HeroConfig.Heroes = {
	Rift = {
		Id = "Rift", DisplayName = "RIFT", Role = "Assault", Weapon = "Burst Rifle", WeaponId = "BurstRifle", Color = Color3.fromRGB(255, 140, 40),
		Description = "Aggressive frontline damage dealer.", Price = 0,
		Stats = { Health = 225, WalkSpeed = 18 },
		Abilities = {
			Primary = { Name = "Burst Fire", Text = "Fires a 3-round burst." },
			Dash = { Name = "Combat Dash", Text = "Quick dash to dodge fire.", Icon = "Rift_Dash", Cooldown = 6,
				Movement = { Type = "Dash", Dir = "Move", Speed = 85, Time = 0.2 } },
			Skill = { Name = "Pulse Grenade", Text = "Lobbed grenade that explodes after a short fuse.", Icon = "Rift_Skill", Cooldown = 10,
				Damage = 60, Radius = 9, Fuse = 1.2, ThrowSpeed = 48, ContactRadius = 3 },
			Ultimate = { Name = "Overdrive", Text = "Faster fire rate and more damage.", Icon = "Rift_Ult", Charge = 1800,
				Duration = 6, DamageMult = 1.25, FireRateMult = 1.6 },
		},
	},
	Vex = {
		Id = "Vex", DisplayName = "VEX", Role = "Sniper", Weapon = "Precision Rifle", WeaponId = "PrecisionRifle", Color = Color3.fromRGB(150, 90, 255),
		Description = "Long-range eliminations.", Price = 1500,
		Stats = { Health = 175, WalkSpeed = 17 },
		Abilities = {
			Primary = { Name = "Precision Shot", Text = "High-damage single shot." },
			Dash = { Name = "Phase Slide", Text = "Low, fast slide to reposition.", Icon = "Vex_Dash", Cooldown = 7,
				Movement = { Type = "Dash", Dir = "Move", Speed = 75, Time = 0.32 } },
			Skill = { Name = "Sensor Trap", Text = "Device that reveals nearby enemies to your team.", Icon = "Vex_Skill", Cooldown = 14,
				Range = 45, Radius = 24, Duration = 10 },
			Ultimate = { Name = "Deadeye Protocol", Text = "Empowered, faster precision shots.", Icon = "Vex_Ult", Charge = 2000,
				Duration = 6, DamageMult = 1.35, FireRateMult = 1.5 },
		},
	},
	Titan = {
		Id = "Titan", DisplayName = "TITAN", Role = "Tank", Weapon = "Heavy Cannon", WeaponId = "HeavyCannon", Color = Color3.fromRGB(90, 200, 120),
		Description = "Frontline tank and defensive protector.", Price = 1500,
		Stats = { Health = 450, WalkSpeed = 15 },
		Abilities = {
			Primary = { Name = "Cannon Shell", Text = "Slow heavy projectiles with splash." },
			Dash = { Name = "Shoulder Charge", Text = "Charge forward, damaging and pushing enemies.", Icon = "Titan_Dash", Cooldown = 8,
				Movement = { Type = "Dash", Dir = "Look", Speed = 60, Time = 0.45 }, Damage = 30, HitRadius = 6, Knockback = 60 },
			Skill = { Name = "Fortress Shield", Text = "Deploys a barrier that blocks enemy fire.", Icon = "Titan_Skill", Cooldown = 12,
				Health = 600, Duration = 7, Width = 14, Height = 10 },
			Ultimate = { Name = "Groundbreaker", Text = "Slam that damages, launches and slows enemies.", Icon = "Titan_Ult", Charge = 2200,
				Damage = 90, Radius = 16, Knockback = 70, SlowMult = 0.5, SlowTime = 2.5 },
		},
	},
	Solace = {
		Id = "Solace", DisplayName = "SOLACE", Role = "Support", Weapon = "Medical Projector", WeaponId = "MedicalProjector", Color = Color3.fromRGB(80, 255, 200),
		Description = "Healing and team support.", Price = 0,
		Stats = { Health = 200, WalkSpeed = 17 },
		Abilities = {
			Primary = { Name = "Energy Bolt", Text = "Fires energy bolts." },
			Dash = { Name = "Healing Glide", Text = "Glide forward, healing nearby allies.", Icon = "Solace_Dash", Cooldown = 8,
				Movement = { Type = "Dash", Dir = "Move", Speed = 65, Time = 0.3 }, Heal = 25, Radius = 12 },
			Skill = { Name = "Healing Pulse", Text = "Heals you and nearby teammates.", Icon = "Solace_Skill", Cooldown = 10,
				Heal = 60, Radius = 18 },
			Ultimate = { Name = "Sanctuary", Text = "Zone that rapidly heals allies inside.", Icon = "Solace_Ult", Charge = 2000,
				Duration = 8, Radius = 16, HealPerSecond = 35 },
		},
	},
	Shade = {
		Id = "Shade", DisplayName = "SHADE", Role = "Assassin", Weapon = "Dual Energy Blades", WeaponId = "EnergyBlades", Color = Color3.fromRGB(70, 70, 90),
		Description = "Flanking and close-range eliminations.", Price = 2000,
		Stats = { Health = 175, WalkSpeed = 20 },
		Abilities = {
			Primary = { Name = "Blade Flurry", Text = "Fast melee strikes." },
			Dash = { Name = "Shadow Blink", Text = "Instantly teleport a short distance.", Icon = "Shade_Dash", Cooldown = 7,
				Movement = { Type = "Blink", Distance = 20 } },
			Skill = { Name = "Cloak", Text = "Nearly invisible for a few seconds. Attacking breaks it.", Icon = "Shade_Skill", Cooldown = 14,
				Duration = 4, Transparency = 0.9 },
			Ultimate = { Name = "Nightfall", Text = "Faster movement and stronger blades.", Icon = "Shade_Ult", Charge = 1900,
				Duration = 6, SpeedAdd = 8, DamageMult = 1.5, FireRateMult = 1.4 },
		},
	},
	Volt = {
		Id = "Volt", DisplayName = "VOLT", Role = "Controller", Weapon = "Lightning Gauntlet", WeaponId = "LightningGauntlet", Color = Color3.fromRGB(255, 230, 60),
		Description = "Area control and enemy disruption.", Price = 2000,
		Stats = { Health = 200, WalkSpeed = 17 },
		Abilities = {
			Primary = { Name = "Arc Bolt", Text = "Fires electric energy." },
			Dash = { Name = "Electric Surge", Text = "Zip quickly in any direction.", Icon = "Volt_Dash", Cooldown = 7,
				Movement = { Type = "Dash", Dir = "Move", Speed = 90, Time = 0.2 } },
			Skill = { Name = "Arc Field", Text = "Electric field that slows and damages enemies.", Icon = "Volt_Skill", Cooldown = 12,
				Range = 40, Radius = 10, Duration = 5, DamagePerSecond = 14, SlowMult = 0.6 },
			Ultimate = { Name = "Storm Core", Text = "Huge storm zone that shreds enemies.", Icon = "Volt_Ult", Charge = 2100,
				Range = 50, Radius = 20, Duration = 6, DamagePerSecond = 28, SlowMult = 0.7 },
		},
	},
}
HeroConfig.HeroOrder = { "Rift", "Vex", "Titan", "Solace", "Shade", "Volt" }
HeroConfig.AbilitySlots = { "Dash", "Skill", "Ultimate" }

return HeroConfig
