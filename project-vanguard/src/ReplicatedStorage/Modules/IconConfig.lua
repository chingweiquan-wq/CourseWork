--!strict
-- IconConfig: every UI/world icon in one place. Icons were generated with ForgeGUI and uploaded to
-- the game owner's Roblox account. To swap an icon, change its asset id here only.
local IconConfig = {}

IconConfig.Ids = {
	Play = "106634061628141",
	Shop = "103279728212592",
	Characters = "119250421642959",
	Settings = "87109201868780",
	Token = "105872760032040",
	Ranked = "133878068683445",
	Casual = "88050685745802",
	Duel = "98435619843706",
	Trophy = "80517952068124",
	Gem = "87580998029472",

	-- Ability icons (HeroConfig ability .Icon names)
	Rift_Dash = "126004906821064",
	Rift_Skill = "86878014728340",
	Rift_Ult = "127024007702651",
	Vex_Dash = "138460534473136",
	Vex_Skill = "91199664476401",
	Vex_Ult = "85208245870970",
	Titan_Dash = "83322635555873",
	Titan_Skill = "125717275567757",
	Titan_Ult = "73706323385349",
	Solace_Dash = "138236841962355",
	Solace_Skill = "133544830726676",
	Solace_Ult = "80095091914840",
	Shade_Dash = "92618253730414",
	Shade_Skill = "137004610150545",
	Shade_Ult = "117471626880316",
	Volt_Dash = "138912186086636",
	Volt_Skill = "140166817563143",
	Volt_Ult = "103708582166332",
	-- Jeric / Forge / Echo: their own icons are drawn (project-vanguard/assets/icons) but not uploaded yet;
	-- until then they borrow the closest existing icon. Replace these ids after uploading.
	Jeric_Dash = "126004906821064",
	Jeric_Skill = "133544830726676",
	Jeric_Ult = "127024007702651",
	Forge_Dash = "138912186086636",
	Forge_Skill = "91199664476401",
	Forge_Ult = "125717275567757",
	Echo_Dash = "92618253730414",
	Echo_Skill = "85208245870970",
	Echo_Ult = "103708582166332",
}

-- Game modes -> icon names
IconConfig.ModeIcon = { Casual = "Casual", Ranked = "Ranked", Duel = "Duel", Practice = "Duel" }

function IconConfig.Get(name: string): string
	local id = IconConfig.Ids[name]
	if id and id ~= "" then
		return "rbxassetid://" .. id
	end
	return ""
end

return IconConfig
