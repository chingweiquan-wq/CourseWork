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
		Id = "Casual", DisplayName = "CASUAL", Description = "Hold the Core: control the ring to fill your meter. First to 100% wins.",
		TeamBased = true, MinPlayers = 4, MaxPlayers = 10, MaxPerTeam = 5, Ranked = false,
		MatchDuration = 300, RespawnTime = 5,
	},
	Ranked = {
		Id = "Ranked", DisplayName = "RANKED", Description = "Hold the Core with your rank on the line. Winning earns RP.",
		TeamBased = true, MinPlayers = 4, MaxPlayers = 10, MaxPerTeam = 5, Ranked = true,
		MatchDuration = 300, RespawnTime = 6,
	},
	Duel = {
		Id = "Duel", DisplayName = "1v1 DUEL", Description = "First to 5 eliminations wins.",
		TeamBased = false, MinPlayers = 2, MaxPlayers = 2, MaxPerTeam = 1, Ranked = false,
		MatchDuration = 240, RespawnTime = 3, KillsToWin = 5,
	},
	-- Phase 9: solo 1v1 against a bot. No ranked rating, no tokens, no leaderboard kills.
	Practice = {
		Id = "Practice", DisplayName = "1v1 PRACTICE", Description = "Warm up 1v1 against a bot. First to 5 eliminations. No rewards.",
		TeamBased = false, MinPlayers = 1, MaxPlayers = 1, MaxPerTeam = 1, Ranked = false,
		MatchDuration = 240, RespawnTime = 3, KillsToWin = 5, Bots = 1, NoRewards = true, QueueCountdown = 2,
	},
}
GameConfig.ModeOrder = { "Casual", "Ranked", "Duel", "Practice" }

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
	StreakWindow = 8,          -- seconds allowed between kills to keep a multi-kill going (DOUBLE KILL etc.)
	OriginTolerance = 8,       -- max studs between a shot's claimed origin and the shooter's head (must also be in line of sight)
	HitTolerance = 8,          -- max studs between a claimed hit point and the target's current position
	HeadshotTolerance = 1.5,   -- extra studs a claimed HEAD hit may be off the ray before it counts as a body hit
	CooldownTolerance = 0.8,   -- accept shots at 80% of the cooldown to absorb network jitter
	MaxShotsPerSecond = 20,    -- hard cap regardless of weapon
	StudioTrainingDummies = 2, -- enemy dummies spawned when testing solo in Studio (0 = off)
}

GameConfig.Abilities = {
	UltPassivePerSecond = 6.8, -- (x1.7) ult charge points gained per second just by being alive in a live match
	ChargePerDamage = 1.7,     -- ult points per point of damage dealt (x1.7 = ult charges 70% faster)
	ChargePerHeal = 1.7,       -- ult points per point of healing done
	AimRayLength = 120,        -- max distance used when an ability needs an aim point
	StudioFastUlt = true,      -- Studio solo testing only: ult charges 10x faster so it can be tested quickly
}

-- Hold the Core (Casual + Ranked): stand in the map's ring with no enemies to fill your team's meter.
GameConfig.Objective = {
	SecondsToWin = 90,        -- one player holding alone fills 0 -> 100% in this many seconds
	ExtraPlayerBonus = 0.15,  -- each extra teammate on the core adds +15% speed...
	MaxSpeedMult = 1.6,       -- ...up to this cap
	TickRate = 0.25,          -- server update interval (seconds)
	HeightAbove = 14,         -- how high above the ring still counts as "on the core"
	HeightBelow = 3,
}

-- Ranked: saved with DataStore. Winning decides rating; kills do not.
GameConfig.Ranked = {
	Season = 1,
	SeasonName = "SEASON 1",
	StartRating = 450,        -- SILVER II
	K = 40,                   -- max swing for a 50/50 match is +/-20, upsets swing more
	MinGain = 8,              -- a win is always worth at least this much
	MinLoss = 8,              -- a loss always costs at least this much
	LeavePenalty = 10,        -- extra RP lost for leaving a ranked match early
	SeasonResetBlend = 0.5,   -- new season rating = halfway between old rating and StartRating
	HistorySize = 10,         -- match history entries kept per player (all modes)
	AutosaveSeconds = 60,
	LockTimeout = 150,        -- a session lock older than this is treated as stale
	LeaderboardRefresh = 60,
}

-- Progression (Phase 5): TOKENS economy, daily streak, anti-farm. All rewards are decided on the server.
GameConfig.Progression = {
	StartingTokens = 0,
	Rewards = { Complete = 40, Win = 30, MVP = 10, FirstMatch = 2000 }, -- per finished match (+ one-time FirstMatch bonus)
	RankedMultiplier = 1.25,  -- ranked matches pay a bit more
	MinActiveFraction = 0.3,  -- AFK check: must be moving / on the core for 30% of the match to earn tokens
	ActivitySample = 2,       -- seconds between activity samples
	ActiveMoveStuds = 4,      -- moving at least this far between samples counts as active
	MinTrackedSeconds = 20,   -- matches shorter than this skip the AFK check
	Daily = { 50, 75, 100, 125, 150, 200, 300 }, -- 7-day login streak, then it repeats
	BuyCooldown = 0.5,        -- seconds between purchase requests
	ReceiptsKept = 100,       -- Robux receipt IDs remembered per player (stops double-granting)
}

-- Cosmetics (Phase 6): weapon skins are Robux-only and purely visual.
GameConfig.Cosmetics = {
	StudioOwnAllSkins = true, -- Studio playtests only: every skin counts as owned (not saved) so they can be previewed/equipped
	EquipCooldown = 0.3,
}

-- Phase 9: bots. They play the real heroes (tagged [BOT]), fill Casual and power 1v1 Practice.
-- Never in Ranked or Duel, never give leaderboard kills (only real-player kills count there).
GameConfig.Bots = {
	Difficulty = "Normal",   -- "Easy" | "Normal" | "Hard"  (change here to retune every bot)
	MaxPerMatch = 9,
	CasualFillTo = 10,       -- Casual matches are topped up with bots to this many fighters (5v5)
	CasualFillAfter = 20,    -- seconds a lone Casual queue waits for real players before bots fill in
	ThinkRate = 0.15,        -- seconds between bot decisions
	Presets = {
		--        reaction  aim error (deg)  fire-rate x  headshot %  sight range  strafe
		Easy   = { Reaction = 0.85, AimError = 6.0, FireRate = 0.6, Headshot = 0.05, Sight = 110, Strafe = 0.3 },
		Normal = { Reaction = 0.5,  AimError = 3.5, FireRate = 0.8, Headshot = 0.12, Sight = 170, Strafe = 0.6 },
		Hard   = { Reaction = 0.28, AimError = 1.8, FireRate = 1.0, Headshot = 0.25, Sight = 240, Strafe = 0.85 },
	},
}

function GameConfig.GetMinPlayers(modeId: string): number
	local mode = GameConfig.Modes[modeId]
	if GameConfig.IsStudio and GameConfig.StudioSoloTesting then
		return 1
	end
	return mode.MinPlayers
end

-- Phase 8: lobby leaderboards (Hall of Fame wall beside the Ranked board)
GameConfig.Leaderboards = {
	RefreshSeconds = 300, -- write changed scores + read the top lists every 5 minutes (light on DataStore budgets)
	Show = 25,            -- rows on each board (auto-scrolling)
	Fetch = 100,          -- how deep we read, so players up to #100 see their exact rank
	FirstRefreshDelay = 8,
	Boards = {
		Kills = { Title = "MOST KILLS", Icon = "Trophy", Color = Color3.fromRGB(255, 210, 60), Unit = "kills", Store = "VG_Board_Kills" },
		Robux = { Title = "TOP SUPPORTERS", Icon = "Gem", Color = Color3.fromRGB(90, 255, 140), Unit = "R$", Store = "VG_Board_Robux" },
	},
	BoardOrder = { "Kills", "Robux" },
}

return GameConfig
