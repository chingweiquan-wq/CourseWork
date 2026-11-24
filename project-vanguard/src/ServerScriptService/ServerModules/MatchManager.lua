--!strict
-- MatchManager: owns the life-cycle of every running match.
-- PreMatch -> Live -> Ended -> players returned to lobby, map unloaded.
-- Phase 2: records eliminations (K/D/A, streaks, first blood), duel kill limit, team-kill tiebreak.
-- Phase 4: Scores = Hold-the-Core % (ObjectiveService), ObjTime per player, MVP, ranked team balancing,
-- PlayerLeft event (RankedService applies leave penalties).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local MapConfig = require(ReplicatedStorage.Modules.MapConfig)
local MapService = require(script.Parent.MapService)
local SpawnService = require(script.Parent.SpawnService)

local Remotes = ReplicatedStorage.Remotes
local MatchState = Remotes.MatchState :: RemoteEvent
local KillFeed = Remotes.KillFeed :: RemoteEvent

export type Match = {
	Id: string,
	Mode: string,
	MapId: string,
	Slot: number,
	Map: Model,
	Players: { Player },
	TeamOf: { [Player]: string },
	Scores: { [string]: number },
	Stats: { [Player]: { Kills: number, Deaths: number, Assists: number, ObjTime: number } },
	TeamKills: { [string]: number },
	FirstBloodTaken: boolean,
	Streaks: { [Player]: { Streak: number, Chain: number, LastKill: number } },
	State: string,
	EndsAt: number,
	Abandoned: boolean,
	Winner: string?,
	EndReason: string?,
	Extra: { [string]: any }, -- scratch space for other services (ranked expectations, etc.)
}

local MatchManager = {}

local matches: { [string]: Match } = {}
local matchOfPlayer: { [Player]: Match } = {}
local listeners: { [string]: { (...any) -> () } } = { Started = {}, Live = {}, Ended = {}, PlayerLeft = {} }

-- Lets other services (combat, dummies, later abilities/rewards) react to match events without circular requires.
-- Events: Started(match), Live(match), Ended(match), PlayerLeft(match, player, team)
function MatchManager.On(eventName: string, fn: (...any) -> ())
	table.insert(listeners[eventName], fn)
end

local function emit(eventName: string, ...: any)
	for _, fn in ipairs(listeners[eventName]) do
		task.spawn(fn, ...)
	end
end

local STAT_ATTRS = { "MatchKills", "MatchDeaths", "MatchAssists", "Streak" }
local function setStatAttrs(p: Player, match: Match?)
	if not match then
		for _, a in ipairs(STAT_ATTRS) do p:SetAttribute(a, nil) end
		return
	end
	local s = match.Stats[p]
	local st = match.Streaks[p]
	if not s or not st then return end
	p:SetAttribute("MatchKills", s.Kills)
	p:SetAttribute("MatchDeaths", s.Deaths)
	p:SetAttribute("MatchAssists", s.Assists)
	p:SetAttribute("Streak", st.Streak)
end

local function now(): number
	return workspace:GetServerTimeNow()
end

local function spawnGroupFor(match: Match, player: Player): string
	if GameConfig.Modes[match.Mode].TeamBased then
		return match.TeamOf[player]
	end
	return "FFA"
end

local function placeInMatch(player: Player, match: Match)
	local character = player.Character
	if not character then return end
	local markers = MapService.GetSpawnPoints(match.Map, spawnGroupFor(match, player))
	SpawnService.PlaceAtRandom(character, markers)
	if match.State == "PreMatch" then
		SpawnService.SetFrozen(character, true)
	end
end

local function teamPayload(match: Match)
	local teams = {}
	for p, team in pairs(match.TeamOf) do
		teams[team] = teams[team] or {}
		table.insert(teams[team], p.DisplayName)
	end
	return teams
end

local function broadcast(match: Match, payload: { [string]: any })
	payload.MatchId = match.Id
	payload.Mode = match.Mode
	payload.MapId = match.MapId
	payload.Scores = match.Scores
	payload.EndsAt = match.EndsAt
	payload.Teams = teamPayload(match)
	for _, p in ipairs(match.Players) do
		local personal = table.clone(payload)
		personal.YourTeam = match.TeamOf[p]
		MatchState:FireClient(p, personal)
	end
end

local function shuffle<T>(list: { T }): { T }
	local copy = table.clone(list)
	for i = #copy, 2, -1 do
		local j = math.random(1, i)
		copy[i], copy[j] = copy[j], copy[i]
	end
	return copy
end

-- Alternating assignment guarantees team sizes never differ by more than one.
-- Ranked: players are sorted by rating and snake-drafted (A B B A A B ...) so team averages stay close.
local SNAKE = { "Alpha", "Bravo", "Bravo", "Alpha" }
local function assignTeams(match: Match, players: { Player })
	local mode = GameConfig.Modes[match.Mode]
	local shuffled = shuffle(players)
	if mode.Ranked then
		table.sort(shuffled, function(a, b)
			return (tonumber(a:GetAttribute("Rating")) or 0) > (tonumber(b:GetAttribute("Rating")) or 0)
		end)
		for i, p in ipairs(shuffled) do
			local team = SNAKE[((i - 1) % 4) + 1]
			match.TeamOf[p] = team
		end
		match.Scores.Alpha = 0
		match.Scores.Bravo = 0
		return
	end
	for i, p in ipairs(shuffled) do
		local team
		if mode.TeamBased then
			team = (i % 2 == 1) and "Alpha" or "Bravo"
		else
			team = "Solo" .. i
		end
		match.TeamOf[p] = team
		match.Scores[team] = match.Scores[team] or 0
	end
	if mode.TeamBased then
		match.Scores.Alpha = match.Scores.Alpha or 0
		match.Scores.Bravo = match.Scores.Bravo or 0
	end
end

function MatchManager.IsInMatch(player: Player): boolean
	return matchOfPlayer[player] ~= nil
end

function MatchManager.GetMatch(player: Player): Match?
	return matchOfPlayer[player]
end

function MatchManager.AddScore(match: Match, team: string, amount: number)
	if match.State ~= "Live" then return end
	match.Scores[team] = (match.Scores[team] or 0) + amount
	broadcast(match, { State = "Live", Event = "Score" })
end

local function bestOf(values: { [string]: number }): string?
	local best, bestScore, tie = nil, -math.huge, false
	for team, score in pairs(values) do
		if score > bestScore then best, bestScore, tie = team, score, false
		elseif score == bestScore then tie = true end
	end
	if tie then return nil end
	return best
end

-- Objective % decides; team eliminations break ties.
local function determineWinner(match: Match): string?
	return bestOf(match.Scores) or bestOf(match.TeamKills)
end

function MatchManager.GetMatchById(id: string?): Match?
	if not id then return nil end
	return matches[id]
end

-- Called by CombatService whenever a combatant dies inside a match.
-- killer may be nil (fell off the map with no recent attacker). victim is nil for training dummies.
function MatchManager.RecordElimination(match: Match, killer: Player?, victim: Player?, victimName: string, assisters: { Player }, weaponName: string?, headshot: boolean?)
	if match.State ~= "Live" then return end
	local t = now()
	local payload: { [string]: any } = {
		Victim = victimName,
		VictimTeam = victim and match.TeamOf[victim] or nil,
		Weapon = weaponName or "Environment",
		Headshot = headshot == true,
	}

	if victim and match.Stats[victim] then
		payload.VictimStreak = match.Streaks[victim].Streak -- for SHUTDOWN callouts (Phase 7)
		match.Stats[victim].Deaths += 1
		match.Streaks[victim].Streak = 0
		match.Streaks[victim].Chain = 0
		setStatAttrs(victim, match)
	end

	if killer and killer ~= victim and match.Stats[killer] then
		local s = match.Stats[killer]
		local st = match.Streaks[killer]
		s.Kills += 1
		st.Streak += 1
		if t - st.LastKill <= GameConfig.Combat.StreakWindow then st.Chain += 1 else st.Chain = 1 end
		st.LastKill = t
		local team = match.TeamOf[killer]
		match.TeamKills[team] = (match.TeamKills[team] or 0) + 1
		setStatAttrs(killer, match)
		payload.Killer = killer.DisplayName
		payload.KillerUserId = killer.UserId
		payload.KillerTeam = team
		payload.Streak = st.Streak
		payload.Chain = st.Chain
		if not match.FirstBloodTaken then
			match.FirstBloodTaken = true
			payload.FirstBlood = true
		end
	end

	local assistNames = {}
	for _, a in ipairs(assisters) do
		if a ~= killer and a ~= victim and match.Stats[a] then
			match.Stats[a].Assists += 1
			setStatAttrs(a, match)
			table.insert(assistNames, a.DisplayName)
		end
	end
	payload.Assists = assistNames
	payload.VictimUserId = victim and victim.UserId or nil
	payload.TeamKills = match.TeamKills

	for _, p in ipairs(match.Players) do
		KillFeed:FireClient(p, payload)
	end

	-- Duel: first to KillsToWin
	local mode = GameConfig.Modes[match.Mode]
	if killer and mode.KillsToWin and match.Stats[killer] and match.Stats[killer].Kills >= mode.KillsToWin then
		MatchManager.EndMatch(match, "KillLimit", match.TeamOf[killer])
	end
end

function MatchManager.GetRespawnTime(player: Player): number
	local match = matchOfPlayer[player]
	if match then return GameConfig.Modes[match.Mode].RespawnTime end
	return GameConfig.Lobby.RespawnTime
end

-- MVP: best impact score, taken from the winning side when there is one.
-- Objective time and assists count, so supports and core holders can earn it too.
local function mvpScore(s: { Kills: number, Deaths: number, Assists: number, ObjTime: number }): number
	return s.Kills * 100 + s.Assists * 50 + s.ObjTime * 8 - s.Deaths * 20
end

local function pickMvp(match: Match, winner: string?): Player?
	local best, bestScore = nil, -math.huge
	for _, p in ipairs(match.Players) do
		local s = match.Stats[p]
		if s and (winner == nil or match.TeamOf[p] == winner) then
			local score = mvpScore(s)
			if score > bestScore then best, bestScore = p, score end
		end
	end
	return best
end

function MatchManager.EndMatch(match: Match, reason: string, forcedWinner: string?)
	if match.State == "Ended" then return end
	match.State = "Ended"
	local winner = forcedWinner or determineWinner(match)
	match.Winner = winner
	match.EndReason = reason
	for _, p in ipairs(match.Players) do p:SetAttribute("CombatEnabled", false) end
	local statsByName = {}
	for p, s in pairs(match.Stats) do
		if match.TeamOf[p] then
			statsByName[p.DisplayName] = { Kills = s.Kills, Deaths = s.Deaths, Assists = s.Assists, ObjTime = math.floor(s.ObjTime), Team = match.TeamOf[p] }
		end
	end
	local mvp = pickMvp(match, winner)
	match.Extra.MvpUserId = mvp and mvp.UserId or nil -- ProgressionService pays the MVP bonus
	local mvpPayload = nil
	if mvp then
		local s = match.Stats[mvp]
		mvpPayload = { Name = mvp.DisplayName, UserId = mvp.UserId, Hero = mvp:GetAttribute("Hero"), Team = match.TeamOf[mvp],
			Kills = s.Kills, Deaths = s.Deaths, Assists = s.Assists, ObjTime = math.floor(s.ObjTime) }
	end
	broadcast(match, { State = "Ended", Winner = winner, Reason = reason, Abandoned = match.Abandoned, TeamKills = match.TeamKills, Stats = statsByName, MVP = mvpPayload })
	emit("Ended", match)
	print(string.format("[MatchManager] Match %s ended (%s). Winner: %s", match.Id, reason, tostring(winner)))

	task.delay(GameConfig.Match.PostMatchSeconds, function()
		for _, p in ipairs(match.Players) do
			matchOfPlayer[p] = nil
			if p.Parent == Players then
				p:SetAttribute("MatchId", nil)
				p:SetAttribute("Team", nil)
				p:SetAttribute("MatchMode", nil)
				setStatAttrs(p, nil)
				MatchState:FireClient(p, { State = "Lobby" })
				p:LoadCharacter() -- respawns at a lobby SpawnLocation
			end
		end
		MapService.Unload(match.Slot)
		matches[match.Id] = nil
	end)
end

local function runMatch(match: Match)
	local mode = GameConfig.Modes[match.Mode]
	task.wait(GameConfig.Match.PreMatchSeconds)
	if match.State ~= "PreMatch" then return end

	local duration = (GameConfig.IsStudio and GameConfig.StudioSoloTesting) and GameConfig.Match.StudioMatchDuration or mode.MatchDuration
	match.State = "Live"
	match.EndsAt = now() + duration
	for _, p in ipairs(match.Players) do
		SpawnService.SetFrozen(p.Character, false)
		p:SetAttribute("CombatEnabled", true)
	end
	broadcast(match, { State = "Live" })
	emit("Live", match)

	while match.State == "Live" and now() < match.EndsAt do
		task.wait(0.5)
	end
	if match.State == "Live" then
		MatchManager.EndMatch(match, "TimeUp")
	end
end

-- Returns true if the match started. On false the caller should return players to the queue.
function MatchManager.StartMatch(modeId: string, players: { Player }): boolean
	local mode = GameConfig.Modes[modeId]
	if not mode then return false end

	local valid = {}
	for _, p in ipairs(players) do
		if p.Parent == Players and not matchOfPlayer[p] then table.insert(valid, p) end
	end
	if #valid < GameConfig.GetMinPlayers(modeId) then return false end

	local mapId = MapService.PickMap(modeId)
	if not mapId then return false end
	local map, slot = MapService.Load(mapId)
	if not map or not slot then return false end

	-- Falling off floating maps (Skyline Core) eliminates the player. Connection dies with the map.
	local killZone = map:FindFirstChild("KillZone")
	if killZone and killZone:IsA("BasePart") then
		killZone.Touched:Connect(function(hit)
			local hum = hit.Parent and hit.Parent:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 then hum.Health = 0 end
		end)
	end

	local match: Match = {
		Id = HttpService:GenerateGUID(false),
		Mode = modeId,
		MapId = mapId,
		Slot = slot,
		Map = map,
		Players = valid,
		TeamOf = {},
		Scores = {},
		Stats = {},
		TeamKills = {},
		FirstBloodTaken = false,
		Streaks = {},
		State = "PreMatch",
		EndsAt = now() + GameConfig.Match.PreMatchSeconds,
		Abandoned = false,
		Winner = nil,
		EndReason = nil,
		Extra = {},
	}
	assignTeams(match, valid)
	matches[match.Id] = match

	for _, p in ipairs(valid) do
		matchOfPlayer[p] = match
		match.Stats[p] = { Kills = 0, Deaths = 0, Assists = 0, ObjTime = 0 }
		match.Streaks[p] = { Streak = 0, Chain = 0, LastKill = -math.huge }
		setStatAttrs(p, match)
		p:SetAttribute("CombatEnabled", false)
		p:SetAttribute("MatchId", match.Id)
		p:SetAttribute("Team", match.TeamOf[p])
		p:SetAttribute("MatchMode", modeId)
		p:LoadCharacter() -- CharacterAdded hook below moves them onto the map
	end

	print(string.format("[MatchManager] Starting %s on %s with %d players (slot %d)", modeId, MapConfig.Maps[mapId].DisplayName, #valid, slot))
	broadcast(match, { State = "PreMatch" })
	emit("Started", match)
	task.spawn(runMatch, match)
	return true
end

local function onPlayerLeft(player: Player)
	local match = matchOfPlayer[player]
	matchOfPlayer[player] = nil
	if not match or match.State == "Ended" then return end

	local idx = table.find(match.Players, player)
	if idx then table.remove(match.Players, idx) end
	local leftTeam = match.TeamOf[player]
	match.TeamOf[player] = nil
	emit("PlayerLeft", match, player, leftTeam)

	-- If a side is now empty, the remaining side wins by forfeit.
	local remaining: { [string]: number } = {}
	for _, team in pairs(match.TeamOf) do remaining[team] = (remaining[team] or 0) + 1 end
	local sideCount, lastTeam = 0, nil
	for team in pairs(remaining) do sideCount += 1; lastTeam = team end
	if #match.Players == 0 then
		match.Abandoned = true
		MatchManager.EndMatch(match, "Empty")
	elseif sideCount < 2 and not (GameConfig.IsStudio and GameConfig.StudioSoloTesting and sideCount >= 1) then
		match.Abandoned = true -- Phase 5: no token/rank rewards for abandoned matches
		MatchManager.EndMatch(match, "Forfeit", lastTeam)
	end
end

function MatchManager.Init()
	local function hook(player: Player)
		player.CharacterAdded:Connect(function()
			local match = matchOfPlayer[player]
			if match and match.State ~= "Ended" then
				task.defer(placeInMatch, player, match)
			end
		end)
	end
	for _, p in ipairs(Players:GetPlayers()) do hook(p) end
	Players.PlayerAdded:Connect(hook)
	Players.PlayerRemoving:Connect(onPlayerLeft)
end

return MatchManager
