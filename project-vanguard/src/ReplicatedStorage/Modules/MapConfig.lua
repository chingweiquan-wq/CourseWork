--!strict
-- MapConfig: one entry per map. To add a map: build it in ServerStorage.Maps
-- (with Spawns/Alpha, Spawns/Bravo, Spawns/FFA, Objective) and add an entry here.
local MapConfig = {}

MapConfig.Maps = {
	NeonDistrict = {
		Id = "NeonDistrict", DisplayName = "NEON DISTRICT", Size = "Small",
		Description = "Night-time future city. Tight alleys, rooftops, plaza capture point.",
		Modes = { Casual = true, Ranked = true, Duel = true },
		ObjectiveName = "Plaza Point",
		MusicSoundName = "Music_NeonDistrict", -- placeholder Sound in SoundService.Music (Phase 7)
		Lighting = { ClockTime = 0.2, Brightness = 1, Ambient = Color3.fromRGB(60, 40, 90), OutdoorAmbient = Color3.fromRGB(70, 50, 110), FogColor = Color3.fromRGB(30, 10, 50), FogEnd = 600, ExposureCompensation = 0,
			Effects = { Bloom = { Intensity = 0.6, Threshold = 1.0, Size = 24 }, Atmosphere = { Density = 0.3, Haze = 1.2, Glare = 0.1 } } },
	},
	IronfallBase = {
		Id = "IronfallBase", DisplayName = "IRONFALL BASE", Size = "Medium",
		Description = "Military industrial facility. Catwalks, bunkers, command zone.",
		Modes = { Casual = true, Ranked = true, Duel = false },
		ObjectiveName = "Command Zone",
		MusicSoundName = "Music_IronfallBase",
		Lighting = { ClockTime = 17.6, Brightness = 1.6, Ambient = Color3.fromRGB(80, 72, 64), OutdoorAmbient = Color3.fromRGB(105, 90, 75), FogColor = Color3.fromRGB(150, 120, 90), FogEnd = 900, ExposureCompensation = -0.2,
			Effects = { Bloom = { Intensity = 0.35, Threshold = 1.2, Size = 20 }, Atmosphere = { Density = 0.3, Haze = 1.0, Glare = 0.2 } } },
	},
	SkylineCore = {
		Id = "SkylineCore", DisplayName = "SKYLINE CORE", Size = "Medium",
		Description = "Floating energy facility. Bridges, platforms, central core.",
		Modes = { Casual = true, Ranked = true, Duel = true },
		ObjectiveName = "Energy Core",
		MusicSoundName = "Music_SkylineCore",
		Lighting = { ClockTime = 16.5, Brightness = 1.3, Ambient = Color3.fromRGB(70, 80, 100), OutdoorAmbient = Color3.fromRGB(85, 95, 120), FogColor = Color3.fromRGB(120, 145, 185), FogEnd = 1500, ExposureCompensation = -0.6,
			Effects = { Bloom = { Intensity = 0.25, Threshold = 1.4, Size = 18 }, Atmosphere = { Density = 0.35, Haze = 0.6, Glare = 0 } } },
	},
}
MapConfig.MapOrder = { "NeonDistrict", "IronfallBase", "SkylineCore" }

-- Lobby = spaceship hangar interior (dark gunmetal, lit by ceiling panels; space visible through windows)
MapConfig.LobbyLighting = { ClockTime = 0, Brightness = 1, Ambient = Color3.fromRGB(78, 82, 102), OutdoorAmbient = Color3.fromRGB(62, 66, 88), FogColor = Color3.fromRGB(20, 25, 45), FogEnd = 2000, ExposureCompensation = -0.1,
	Effects = { Bloom = { Intensity = 0.35, Threshold = 1.3, Size = 20 }, Atmosphere = { Density = 0.25, Haze = 0.8, Glare = 0 } } }

function MapConfig.GetMapsForMode(modeId: string): { string }
	local list = {}
	for _, id in ipairs(MapConfig.MapOrder) do
		if MapConfig.Maps[id].Modes[modeId] then table.insert(list, id) end
	end
	return list
end

return MapConfig
