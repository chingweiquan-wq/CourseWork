--!strict
-- GameConfig: central tunables for PROJECT VANGUARD. Change values here, not in scripts.
local RunService = game:GetService("RunService")

local GameConfig = {}

GameConfig.GameTitle = "PROJECT VANGUARD"

-- Studio test helper: lets a single tester queue alone in Studio playtests.
-- Has NO effect in live servers (RunService:IsStudio() is false there).
GameConfig.StudioSoloTesting = true
GameConfig.IsStudio = RunService:IsStudio()

GameConfig.Modes = {
	Casual = {
		Id = "Casual", DisplayName = "CASUAL", Description = "5v5 objective control. Starts from 2v2.",
		TeamBased = true, MinPlayers = 4, MaxPlayers = 10, MaxPerTeam = 5, Ranked = false,
		MatchDuration = 300, RespawnTime = 5,
	},
	Ranked = {
		Id = "Ranked", DisplayName = "RANKED", Description = "Competitive control. Rating on the line.",
		TeamBased = true, MinPlayers = 4, MaxPlayers = 10, MaxPerTeam = 5, Ranked = true,
		MatchDuration = 300, RespawnTime = 6,
	},
	Duel = {
		Id = "Duel", DisplayName = "1v1 DUEL", Description = "First to 5 eliminations wins.",
		TeamBased = false, MinPlayers = 2, MaxPlayers = 2, MaxPerTeam = 1, Ranked = false,
		MatchDuration = 240, RespawnTime = 3, KillsToWin = 5,
	},
}
GameConfig.ModeOrder = { "Casual", "Ranked", "Duel" }

GameConfig.Teams = {
	Alpha = { Name = "ALPHA", Color = Color3.fromRGB(0, 200, 255) },
	Bravo = { Name = "BRAVO", Color = Color3.fromRGB(255, 70, 110) },
}

GameConfig.Queue = {
	Countdown = 15,          -- seconds once minimum players are reached
	FullLobbyCountdown = 5,  -- shortened countdown when the queue is full
	RequestCooldown = 0.75,  -- anti-spam between queue requests
}

GameConfig.Match = {
	PreMatchSeconds = 5,     -- freeze/intro before the match starts
	PostMatchSeconds = 8,    -- results screen before returning to lobby
	MaxConcurrentMatches = 4,
	SlotSpacing = 1500,      -- studs between concurrently loaded maps
	StudioMatchDuration = 120,
}

GameConfig.Lobby = {
	ShopTeleportCooldown = 2,
	RespawnTime = 2,
}

GameConfig.Combat = {
	SpawnProtection = 2,       -- seconds of ForceField after spawning in a match
	AssistWindow = 10,         -- damage within this many seconds before a kill earns an assist
	StreakWindow = 12,         -- seconds allowed between kills to keep a multi-kill going (announcements: Phase 7)
	OriginTolerance = 14,      -- max studs between a shot's claimed origin and the shooter's head
	HitTolerance = 8,          -- max studs between a claimed hit point and the target's current position
	CooldownTolerance = 0.8,   -- accept shots at 80% of the cooldown to absorb network jitter
	MaxShotsPerSecond = 20,    -- hard cap regardless of weapon
	StudioTrainingDummies = 2, -- enemy dummies spawned when testing solo in Studio (0 = off)
}

GameConfig.Abilities = {
	UltPassivePerSecond = 4,   -- ult charge points gained per second just by being alive in a live match
	ChargePerDamage = 1,       -- ult points per point of damage dealt
	ChargePerHeal = 1,         -- ult points per point of healing done
	AimRayLength = 120,        -- max distance used when an ability needs an aim point
	StudioFastUlt = true,      -- Studio solo testing only: ult charges 10x faster so it can be tested quickly
}

function GameConfig.GetMinPlayers(modeId: string): number
	local mode = GameConfig.Modes[modeId]
	if GameConfig.IsStudio and GameConfig.StudioSoloTesting then
		return 1
	end
	return mode.MinPlayers
end

return GameConfig
