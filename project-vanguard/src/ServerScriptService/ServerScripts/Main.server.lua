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

MapService.Init()
MatchManager.Init()
Matchmaking.Init()
LobbyService.Init()
CombatService.Init()   -- registers its OnSpawned hook before characters load
AbilityService.Init()  -- hooks into combat (buffs, ult charge) and character spawns
DummyService.Init()
LobbyDisplayService.Init()
CharacterService.Init() -- loads characters last (auto-respawn is off)

print("[PROJECT VANGUARD] Server ready - Phase 3")
