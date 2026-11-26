--!strict
-- ProductConfig: Roblox developer products (Robux purchases).
-- Create each product in the Creator Dashboard (your experience -> Monetization -> Developer Products),
-- set its Robux price there, then paste the product ID below. 0 = not set up yet (the Robux button stays hidden).
-- Weapon skins (Phase 6) are Robux-only: one developer product per skin (Uncommon R$25, Legendary R$99).
local ProductConfig = {}

ProductConfig.HeroProducts = {
	Vex = 3736044012,
	Titan = 3736044068,
	Shade = 3736044075,
	Volt = 3736044079,
	Jeric = 3736044083,
	Forge = 3736044089,
	Echo = 3736044106,
}

ProductConfig.SkinProducts = {
	BurstRifle_Arctic = 3736044119,
	PrecisionRifle_Arctic = 3736044126,
	HeavyCannon_Arctic = 3736044133,
	MedicalProjector_Arctic = 3736044142,
	EnergyBlades_Arctic = 3736044149,
	LightningGauntlet_Arctic = 3736044158,
	BurstRifle_Gold = 3736044165,
	HeavyCannon_Gold = 3736044172,
	LightningGauntlet_Gold = 3736044181,
	PrecisionRifle_Void = 3736044186,
	MedicalProjector_Void = 3736044188,
	EnergyBlades_Void = 3736044193,
	Scattergun_Arctic = 3736365341,
	RivetGun_Arctic = 3736365345,
	PulseSMG_Arctic = 3736365349,
	Scattergun_Inferno = 3736365354,
	RivetGun_Inferno = 3736365360,
	PulseSMG_Inferno = 3736365362,
}

-- Token packs (Robux -> tokens). The Starter pack can be bought once per account (enforced on the server).
ProductConfig.TokenPacks = {
	{ Id = "Starter", Tokens = 500, Robux = 1, ProductId = 3736046453, OneTime = true },
	{ Id = "Pack500", Tokens = 500, Robux = 49, ProductId = 3736046458 },
	{ Id = "Pack1200", Tokens = 1200, Robux = 99, ProductId = 3736046462 },
	{ Id = "Pack2600", Tokens = 2600, Robux = 199, ProductId = 3736046464 },
	{ Id = "Pack7000", Tokens = 7000, Robux = 499, ProductId = 3736046469, BestValue = true },
}

return ProductConfig
