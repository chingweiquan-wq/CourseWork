-- Main: the single server entry point. Boots every service in dependency order.
local ServerModules = game:GetService("ServerScriptService").ServerModules

local MapService = require(ServerModules.MapService)
local MatchManager = require(ServerModules.MatchManager)
local Matchmaking = require(ServerModules.Matchmaking)
local LobbyService = require(ServerModules.LobbyService)
local CharacterService = require(ServerModules.CharacterService)
local CombatService = require(ServerModules.CombatService)
local DummyService = require(ServerModules.DummyService)
local LobbyDisplayService = require(ServerModules.LobbyDisplayService)
local AbilityService = require(ServerModules.AbilityService)
local ObjectiveService = require(ServerModules.ObjectiveService)
local RankedService = require(ServerModules.RankedService)
local ProgressionService = require(ServerModules.ProgressionService)

MapService.Init()
MatchManager.Init()
Matchmaking.Init()
LobbyService.Init()
CombatService.Init()   -- registers its OnSpawned hook before characters load
AbilityService.Init()  -- hooks into combat (buffs, ult charge) and character spawns
ObjectiveService.Init() -- Hold the Core (Casual + Ranked)
RankedService.Init()    -- saved rank, season, match history, leaderboard
ProgressionService.Init() -- tokens, hero unlocks (tokens + Robux), daily streak, lifetime stats
DummyService.Init()
LobbyDisplayService.Init()
CharacterService.Init() -- loads characters last (auto-respawn is off)

print("[PROJECT VANGUARD] Server ready - Phase 5")
