--!strict
-- ProductConfig: Roblox developer products (Robux purchases).
-- Create each product in the Creator Dashboard (your experience -> Monetization -> Developer Products),
-- set its Robux price there, then paste the product ID below. 0 = not set up yet (the Robux button stays hidden).
-- Weapon skins (Phase 6) are Robux-only: one developer product per skin (Uncommon R$25, Legendary R$99).
local ProductConfig = {}

ProductConfig.HeroProducts = {
	Vex = 0,
	Titan = 0,
	Shade = 0,
	Volt = 0,
	Jeric = 0,
	Forge = 0,
	Echo = 0,
}

ProductConfig.SkinProducts = {
	BurstRifle_Arctic = 0,
	PrecisionRifle_Arctic = 0,
	HeavyCannon_Arctic = 0,
	MedicalProjector_Arctic = 0,
	EnergyBlades_Arctic = 0,
	LightningGauntlet_Arctic = 0,
	BurstRifle_Gold = 0,
	HeavyCannon_Gold = 0,
	LightningGauntlet_Gold = 0,
	PrecisionRifle_Void = 0,
	MedicalProjector_Void = 0,
	EnergyBlades_Void = 0,
}

return ProductConfig
