--!strict
-- AudioConfig: every sound, music track, announcer line and animation id in one place (Phase 7).
-- Music: licensed Roblox Creator Store tracks (APM / DistroKid). SFX: Roblox's built-in client sounds
-- (rbxasset://sounds/...), reshaped per weapon with pitch/volume so nothing is ripped from other games.
-- Announcer: Roblox text-to-speech (AudioTextToSpeech), so the voice lines are original.
local AudioConfig = {}

local S = "rbxasset://sounds/"

AudioConfig.Music = {
	FadeTime = 1.6,
	Lobby = { Id = "rbxassetid://90877360907319", Volume = 0.45, Name = "Dark Tension Underscore" },
	-- one action track per map (falls back to the first one for unknown maps)
	Match = {
		{ Id = "rbxassetid://124322235887282", Volume = 0.32, Name = "Ion Pulse" },
		{ Id = "rbxassetid://122002451189572", Volume = 0.32, Name = "Into The Abyss" },
		{ Id = "rbxassetid://137051100244643", Volume = 0.32, Name = "They Come From Hell" },
		{ Id = "rbxassetid://9042065692", Volume = 0.32, Name = "The Future Is Us" },
	},
	DuckDuringResults = 0.35, -- music volume multiplier while the results screen is up
}

export type SfxDef = { Id: string, Volume: number?, Pitch: number?, Jitter: number?, Max: number?, Distortion: number? }

-- Max = most copies of the same sound allowed at once (stops autofire from stacking hundreds of sounds)
AudioConfig.Sfx = {
	-- UI
	UIHover = { Id = S .. "switch.wav", Volume = 0.18, Pitch = 1.7, Max = 2 },
	UIClick = { Id = S .. "clickfast.wav", Volume = 0.45, Pitch = 1.15, Max = 2 },
	UIOpen = { Id = S .. "SWITCH3.wav", Volume = 0.35, Pitch = 0.9, Max = 1 },
	UIClose = { Id = S .. "SWITCH3.wav", Volume = 0.3, Pitch = 0.7, Max = 1 },
	Tokens = { Id = S .. "electronicpingshort.wav", Volume = 0.4, Pitch = 1.6, Max = 2 },
	Purchase = { Id = S .. "victory.wav", Volume = 0.45, Pitch = 1.25, Max = 1 },
	Error = { Id = S .. "bass.wav", Volume = 0.35, Pitch = 0.6, Max = 1 },

	-- weapons (fired by the shooter locally, by everyone else in 3D at the shot)
	Fire_BurstRifle = { Id = S .. "paintball.wav", Volume = 0.42, Pitch = 1.55, Jitter = 0.06, Max = 6, Distortion = 0.25 },
	Fire_PrecisionRifle = { Id = S .. "Shoulder fired rocket.wav", Volume = 0.55, Pitch = 1.6, Jitter = 0.03, Max = 3, Distortion = 0.35 },
	Fire_HeavyCannon = { Id = S .. "Launching rocket.wav", Volume = 0.5, Pitch = 1.25, Jitter = 0.05, Max = 3 },
	Fire_MedicalProjector = { Id = S .. "electronicpingshort.wav", Volume = 0.3, Pitch = 1.35, Jitter = 0.08, Max = 5 },
	Fire_EnergyBlades = { Id = S .. "swordslash.wav", Volume = 0.45, Pitch = 1.2, Jitter = 0.1, Max = 4 },
	Fire_LightningGauntlet = { Id = S .. "flashbulb.wav", Volume = 0.45, Pitch = 0.75, Jitter = 0.08, Max = 5, Distortion = 0.4 },
	Reload = { Id = S .. "unsheath.wav", Volume = 0.4, Pitch = 1.3, Max = 1 },
	ReloadDone = { Id = S .. "SWITCH3.wav", Volume = 0.45, Pitch = 1.2, Max = 1 },
	Equip = { Id = S .. "unsheath.wav", Volume = 0.3, Pitch = 1.6, Max = 1 },

	-- feedback
	HitMarker = { Id = S .. "Kerplunk.wav", Volume = 0.35, Pitch = 2.4, Max = 3 },
	Headshot = { Id = S .. "electronicpingshort.wav", Volume = 0.4, Pitch = 1.9, Max = 2 },
	KillConfirm = { Id = S .. "bass.wav", Volume = 0.55, Pitch = 1.6, Max = 2 },
	Hurt = { Id = S .. "hit.wav", Volume = 0.4, Pitch = 0.85, Jitter = 0.1, Max = 2 },
	Impact = { Id = S .. "collide.wav", Volume = 0.25, Pitch = 1.8, Jitter = 0.15, Max = 4 },
	Death = { Id = S .. "glassbreak.wav", Volume = 0.45, Pitch = 1.5, Max = 3 },

	-- abilities
	Dash = { Id = S .. "swordlunge.wav", Volume = 0.5, Pitch = 0.75, Max = 2 },
	Cast = { Id = S .. "flashbulb.wav", Volume = 0.45, Pitch = 1.2, Max = 3 },
	Explosion = { Id = S .. "impact_explosion_03.mp3", Volume = 0.55, Pitch = 1.1, Jitter = 0.08, Max = 3 },
	Shockwave = { Id = S .. "bass.wav", Volume = 0.7, Pitch = 0.7, Max = 2 },
	Heal = { Id = S .. "electronicpingshort.wav", Volume = 0.35, Pitch = 0.85, Max = 2 },
	Blink = { Id = S .. "swordlunge.wav", Volume = 0.45, Pitch = 1.4, Max = 2 },
	Zap = { Id = S .. "flashbulb.wav", Volume = 0.4, Pitch = 0.6, Jitter = 0.1, Max = 3, Distortion = 0.5 },
	Ultimate = { Id = S .. "Launching rocket.wav", Volume = 0.6, Pitch = 0.6, Max = 2 },

	-- match flow
	Countdown = { Id = S .. "switch.wav", Volume = 0.5, Pitch = 1.0, Max = 1 },
	Fight = { Id = S .. "bass.wav", Volume = 0.7, Pitch = 1.0, Max = 1 },
	CoreTick = { Id = S .. "electronicpingshort.wav", Volume = 0.18, Pitch = 0.7, Max = 1 },
	Victory = { Id = S .. "victory.wav", Volume = 0.7, Pitch = 1.0, Max = 1 },
	Defeat = { Id = S .. "bass.wav", Volume = 0.6, Pitch = 0.45, Max = 1 },
	StreakSting = { Id = S .. "victory.wav", Volume = 0.45, Pitch = 1.5, Max = 1 },
	Whoosh = { Id = S .. "swordlunge.wav", Volume = 0.35, Pitch = 0.55, Max = 1 },
}

-- 3D sounds: heard up to this many studs away
AudioConfig.RollOff = { Min = 12, Max = 220 }

-- Announcer (text-to-speech). VoiceId 1-10; lower pitch = deeper voice.
AudioConfig.Announcer = {
	VoiceId = "2",
	Pitch = -0.25,
	Speed = 1.0,
	Volume = 1.6,
	Reverb = true,
}

-- Kill streak / multi-kill callouts. Multi-kill = kills chained inside GameConfig.Combat.StreakWindow.
-- Colours are the banner colours (low tiers cyan -> highest gold).
AudioConfig.MultiKill = {
	[2] = { Text = "DOUBLE KILL", Voice = "Double kill!", Color = Color3.fromRGB(0, 220, 255) },
	[3] = { Text = "TRIPLE KILL", Voice = "Triple kill!", Color = Color3.fromRGB(170, 90, 255) },
	[4] = { Text = "QUAD KILL", Voice = "Quad kill!", Color = Color3.fromRGB(255, 60, 170) },
	[5] = { Text = "TEAM WIPE", Voice = "Team wipe!", Color = Color3.fromRGB(255, 190, 50) },
}
AudioConfig.Streak = {
	[3] = { Text = "ON FIRE", Voice = "On fire!", Color = Color3.fromRGB(255, 140, 40) },
	[5] = { Text = "UNSTOPPABLE", Voice = "Unstoppable!", Color = Color3.fromRGB(255, 60, 170) },
	[7] = { Text = "DOMINATING", Voice = "Dominating!", Color = Color3.fromRGB(170, 90, 255) },
	[10] = { Text = "VANGUARD", Voice = "You are the Vanguard!", Color = Color3.fromRGB(255, 190, 50) },
}
AudioConfig.Special = {
	FirstBlood = { Text = "FIRST BLOOD", Voice = "First blood!", Color = Color3.fromRGB(255, 60, 60) },
	Shutdown = { Text = "SHUTDOWN", Voice = "Shutdown!", Color = Color3.fromRGB(0, 220, 255) },
	Fight = { Voice = "Fight!" },
	Victory = { Voice = "Victory!" },
	Defeat = { Voice = "Defeat." },
	Draw = { Voice = "Draw." },
	CoreCaptured = { Voice = "Core secured." },
	CoreLost = { Voice = "Core lost." },
}
AudioConfig.ShutdownAt = 3 -- killing someone on this streak or more = SHUTDOWN

-- R15 animations (generated with Roblox animation generation, published to the place owner)
AudioConfig.Animations = {
	Victory = "rbxassetid://119211766006771",
	Defeat = "rbxassetid://81209983275231",
	Cast = "rbxassetid://110060267421595",
	Ultimate = "rbxassetid://129990550403893",
	Emote = "rbxassetid://89182451294788",
}

-- saved volume settings (0..1); the server validates and stores these
AudioConfig.DefaultVolumes = { Music = 0.6, Sfx = 0.8, Announcer = 0.9 }

return AudioConfig
