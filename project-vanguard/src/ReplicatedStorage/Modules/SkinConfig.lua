--!strict
-- SkinConfig: the weapon-skin catalog (cosmetic only - skins never change damage, range, speed or hitboxes).
-- Each weapon's normal look is its default skin (no entry needed).
-- Add a skin: give it an Id, the Weapon it belongs to, a Rarity and a Theme (see SkinVisuals), then create a
-- developer product for it and paste the product ID into ProductConfig.SkinProducts.
local SkinConfig = {}

export type Rarity = { Id: string, Name: string, Color: Color3, PriceRobux: number, Order: number }
export type Skin = { Id: string, Weapon: string, Name: string, Rarity: string, Theme: string }

SkinConfig.Rarities = {
	Uncommon = { Id = "Uncommon", Name = "UNCOMMON", Color = Color3.fromRGB(90, 200, 255), PriceRobux = 25, Order = 1 },
	Legendary = { Id = "Legendary", Name = "LEGENDARY", Color = Color3.fromRGB(255, 190, 50), PriceRobux = 99, Order = 2 },
} :: { [string]: Rarity }

-- Weapon display names (match WeaponConfig ids)
SkinConfig.WeaponNames = {
	BurstRifle = "Burst Rifle",
	PrecisionRifle = "Precision Rifle",
	HeavyCannon = "Heavy Cannon",
	MedicalProjector = "Medical Projector",
	EnergyBlades = "Energy Blades",
	LightningGauntlet = "Lightning Gauntlet",
}
SkinConfig.WeaponOrder = { "BurstRifle", "PrecisionRifle", "HeavyCannon", "MedicalProjector", "EnergyBlades", "LightningGauntlet" }

SkinConfig.Skins = {
	-- Uncommon: Arctic camo (white and grey with icy blue sheen)
	BurstRifle_Arctic = { Id = "BurstRifle_Arctic", Weapon = "BurstRifle", Name = "Arctic Burst", Rarity = "Uncommon", Theme = "Arctic" },
	PrecisionRifle_Arctic = { Id = "PrecisionRifle_Arctic", Weapon = "PrecisionRifle", Name = "Arctic Precision", Rarity = "Uncommon", Theme = "Arctic" },
	HeavyCannon_Arctic = { Id = "HeavyCannon_Arctic", Weapon = "HeavyCannon", Name = "Arctic Cannon", Rarity = "Uncommon", Theme = "Arctic" },
	MedicalProjector_Arctic = { Id = "MedicalProjector_Arctic", Weapon = "MedicalProjector", Name = "Arctic Projector", Rarity = "Uncommon", Theme = "Arctic" },
	EnergyBlades_Arctic = { Id = "EnergyBlades_Arctic", Weapon = "EnergyBlades", Name = "Arctic Blades", Rarity = "Uncommon", Theme = "Arctic" },
	LightningGauntlet_Arctic = { Id = "LightningGauntlet_Arctic", Weapon = "LightningGauntlet", Name = "Arctic Gauntlet", Rarity = "Uncommon", Theme = "Arctic" },
	-- Legendary: Royal Gold
	BurstRifle_Gold = { Id = "BurstRifle_Gold", Weapon = "BurstRifle", Name = "Royal Gold Burst", Rarity = "Legendary", Theme = "Gold" },
	HeavyCannon_Gold = { Id = "HeavyCannon_Gold", Weapon = "HeavyCannon", Name = "Royal Gold Cannon", Rarity = "Legendary", Theme = "Gold" },
	LightningGauntlet_Gold = { Id = "LightningGauntlet_Gold", Weapon = "LightningGauntlet", Name = "Royal Gold Gauntlet", Rarity = "Legendary", Theme = "Gold" },
	-- Legendary: Crystal Void
	PrecisionRifle_Void = { Id = "PrecisionRifle_Void", Weapon = "PrecisionRifle", Name = "Void Crystal Rifle", Rarity = "Legendary", Theme = "Void" },
	MedicalProjector_Void = { Id = "MedicalProjector_Void", Weapon = "MedicalProjector", Name = "Void Crystal Projector", Rarity = "Legendary", Theme = "Void" },
	EnergyBlades_Void = { Id = "EnergyBlades_Void", Weapon = "EnergyBlades", Name = "Void Crystal Blades", Rarity = "Legendary", Theme = "Void" },
} :: { [string]: Skin }

-- Skins for one weapon, Uncommon first.
function SkinConfig.ForWeapon(weaponId: string): { Skin }
	local list = {}
	for _, s in pairs(SkinConfig.Skins) do
		if s.Weapon == weaponId then table.insert(list, s) end
	end
	table.sort(list, function(a, b) return SkinConfig.Rarities[a.Rarity].Order < SkinConfig.Rarities[b.Rarity].Order end)
	return list
end

-- All skins in shop order (by weapon, then rarity).
function SkinConfig.All(): { Skin }
	local list = {}
	for _, w in ipairs(SkinConfig.WeaponOrder) do
		for _, s in ipairs(SkinConfig.ForWeapon(w)) do table.insert(list, s) end
	end
	return list
end

-- Equipped skins travel as a player attribute: "BurstRifle=BurstRifle_Gold;HeavyCannon=HeavyCannon_Arctic"
function SkinConfig.Encode(equipped: { [string]: string }): string
	local parts = {}
	for _, w in ipairs(SkinConfig.WeaponOrder) do
		if equipped[w] then table.insert(parts, w .. "=" .. equipped[w]) end
	end
	return table.concat(parts, ";")
end

function SkinConfig.Decode(text: any): { [string]: string }
	local out = {}
	if typeof(text) ~= "string" then return out end
	for _, pair in ipairs(string.split(text, ";")) do
		local w, s = string.match(pair, "^(%w+)=(%w+_?%w*)$")
		if w and s and SkinConfig.Skins[s] and SkinConfig.Skins[s].Weapon == w then out[w] = s end
	end
	return out
end

-- Skin a player has equipped on a weapon (nil = default look). Reads the server-set attribute.
function SkinConfig.EquippedFor(player: Player?, weaponId: string): string?
	if not player then return nil end
	return SkinConfig.Decode(player:GetAttribute("EquippedSkins"))[weaponId]
end

return SkinConfig
