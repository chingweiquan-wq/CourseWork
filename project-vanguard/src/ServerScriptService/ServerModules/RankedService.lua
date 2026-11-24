--!strict
-- RankedService: saved player records (ranked rating, season, match history) + rating changes + leaderboard.
--
-- Saving (DataStore "VG_PlayerData", key "u_<UserId>"):
--   * loaded on join with a session lock (stops two servers overwriting each other), retried with backoff
--   * saved after every match, every AutosaveSeconds, on leave (lock released) and on shutdown (BindToClose)
--   * if loading fails the profile is marked unusable: ranked queue is blocked and nothing is saved,
--     so a DataStore outage can never wipe a player's rank
--   * Studio uses separate "STUDIO_" stores so testing never touches live data
--
-- Rating (anti-exploit: all decided here from MatchManager's results; clients never send results):
--   * team expectation is fixed when the match starts (Elo on team average rating)
--   * win/loss decides the change; kills do not. Wins always give >= MinGain, losses cost >= MinLoss
--   * leaving a live ranked match = immediate loss + LeavePenalty
--   * abandoned/empty matches change nothing
--
-- The same saved record also holds Data.Progress (tokens, heroes, stats, daily streak, Robux receipts);
-- ProgressionService reads and changes it through GetData / MarkDirty / SaveNow below.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local RankConfig = require(ReplicatedStorage.Modules.RankConfig)
local HeroConfig = require(ReplicatedStorage.Modules.HeroConfig)
local SkinConfig = require(ReplicatedStorage.Modules.SkinConfig)
local AudioConfig = require(ReplicatedStorage.Modules.AudioConfig)
local MatchManager = require(script.Parent.MatchManager)

local Cfg = GameConfig.Ranked
local Remotes = ReplicatedStorage.Remotes
local RankUpdate = Remotes.RankUpdate :: RemoteEvent

local PREFIX = RunService:IsStudio() and "STUDIO_" or ""
local DATA_VERSION = 1
local JOB_ID = (game.JobId ~= "" and game.JobId) or ("studio-" .. tostring(math.random(1, 1e9)))

local dataStore = DataStoreService:GetDataStore(PREFIX .. "VG_PlayerData")
local boardStore = DataStoreService:GetOrderedDataStore(PREFIX .. "VG_RankedBoard_S" .. Cfg.Season)

type HistoryEntry = { T: number, Mode: string, Map: string, Result: string, K: number, D: number, A: number, Delta: number? }
type RankedData = { Season: number, Rating: number, Peak: number, Wins: number, Losses: number, Draws: number, Played: number, PastSeasons: { any } }
type ProgressData = {
	Tokens: number, Unlocked: { [string]: boolean }, Selected: string,
	Stats: { Kills: number, PlayerKills: number, Deaths: number, Assists: number, Matches: number, Wins: number, Losses: number, TokensEarned: number },
	Daily: { LastDay: number, Streak: number },
	RobuxSpent: number, Receipts: { [string]: number },
	Skins: { Owned: { [string]: boolean }, Equipped: { [string]: string } },
	Settings: { [string]: number },
}
type PlayerData = { Version: number, Ranked: RankedData, Progress: ProgressData, History: { HistoryEntry }, Lock: { Job: string, Time: number }? }
type Profile = { Data: PlayerData, Usable: boolean, Dirty: boolean }

local profiles: { [Player]: Profile } = {}
local loadedListeners: { (Player, any) -> () } = {}

local RankedService = {}

---------------------------------------------------------------- data shape
local function newData(): PlayerData
	return {
		Version = DATA_VERSION,
		Ranked = { Season = Cfg.Season, Rating = Cfg.StartRating, Peak = Cfg.StartRating, Wins = 0, Losses = 0, Draws = 0, Played = 0, PastSeasons = {} },
		Progress = nil :: any, -- filled by reconcile
		History = {},
		Lock = nil,
	}
end

-- Fill missing fields (older saves) and apply the soft reset when a new season starts.
local function reconcile(data: any): PlayerData
	if typeof(data) ~= "table" then data = newData() end
	data.Version = DATA_VERSION
	data.History = typeof(data.History) == "table" and data.History or {}
	local r = typeof(data.Ranked) == "table" and data.Ranked or {}
	r.Rating = tonumber(r.Rating) or Cfg.StartRating
	r.Peak = tonumber(r.Peak) or r.Rating
	r.Wins = tonumber(r.Wins) or 0
	r.Losses = tonumber(r.Losses) or 0
	r.Draws = tonumber(r.Draws) or 0
	r.Played = tonumber(r.Played) or 0
	r.PastSeasons = typeof(r.PastSeasons) == "table" and r.PastSeasons or {}
	r.Season = tonumber(r.Season) or Cfg.Season
	if r.Season ~= Cfg.Season then
		table.insert(r.PastSeasons, { Season = r.Season, Rating = r.Rating, Peak = r.Peak, Wins = r.Wins, Losses = r.Losses })
		r.Rating = math.floor(r.Rating + (Cfg.StartRating - r.Rating) * Cfg.SeasonResetBlend)
		r.Peak = r.Rating
		r.Wins, r.Losses, r.Draws, r.Played = 0, 0, 0, 0
		r.Season = Cfg.Season
	end
	data.Ranked = r

	local pr = typeof(data.Progress) == "table" and data.Progress or {}
	pr.Tokens = math.max(0, math.floor(tonumber(pr.Tokens) or GameConfig.Progression.StartingTokens))
	pr.Unlocked = typeof(pr.Unlocked) == "table" and pr.Unlocked or {}
	for _, id in ipairs(HeroConfig.StarterHeroes) do pr.Unlocked[id] = true end -- starters are always owned
	for id in pairs(pr.Unlocked) do
		if not HeroConfig.Heroes[id] then pr.Unlocked[id] = nil end -- removed heroes
	end
	pr.Selected = (typeof(pr.Selected) == "string" and pr.Unlocked[pr.Selected]) and pr.Selected or HeroConfig.StarterHeroes[1]
	local st = typeof(pr.Stats) == "table" and pr.Stats or {}
	for _, k in ipairs({ "Kills", "PlayerKills", "Deaths", "Assists", "Matches", "Wins", "Losses", "TokensEarned" }) do st[k] = tonumber(st[k]) or 0 end
	pr.Stats = st
	local daily = typeof(pr.Daily) == "table" and pr.Daily or {}
	pr.Daily = { LastDay = tonumber(daily.LastDay) or 0, Streak = tonumber(daily.Streak) or 0 }
	pr.RobuxSpent = tonumber(pr.RobuxSpent) or 0
	pr.Receipts = typeof(pr.Receipts) == "table" and pr.Receipts or {}
	local sk = typeof(pr.Skins) == "table" and pr.Skins or {}
	sk.Owned = typeof(sk.Owned) == "table" and sk.Owned or {}
	sk.Equipped = typeof(sk.Equipped) == "table" and sk.Equipped or {}
	for id in pairs(sk.Owned) do
		if not SkinConfig.Skins[id] then sk.Owned[id] = nil end -- removed skins
	end
	for weapon, id in pairs(sk.Equipped) do
		local skin = SkinConfig.Skins[id]
		if not skin or skin.Weapon ~= weapon or not sk.Owned[id] then sk.Equipped[weapon] = nil end
	end
	pr.Skins = sk
	-- Phase 7: saved audio volumes (0..1), validated again by SettingsService on every change
	local st = typeof(pr.Settings) == "table" and pr.Settings or {}
	local settings = {}
	for k, default in pairs(AudioConfig.DefaultVolumes) do
		local v = st[k]
		settings[k] = (typeof(v) == "number" and v == v) and math.clamp(v, 0, 1) or default
	end
	settings.HideSpending = (st.HideSpending == 1) and 1 or 0 -- Phase 8: hide me on TOP SUPPORTERS
	pr.Settings = settings
	data.Progress = pr
	return data
end

local function key(player: Player): string
	return "u_" .. player.UserId
end

-- Retries with exponential backoff; returns ok, result.
local function withRetry<T>(fn: () -> T, attempts: number?): (boolean, any)
	local tries = attempts or 4
	local lastErr = nil
	for i = 1, tries do
		local ok, result = pcall(fn)
		if ok then return true, result end
		lastErr = result
		task.wait(2 ^ (i - 1))
	end
	return false, lastErr
end

---------------------------------------------------------------- attributes (what clients can see)
local function publish(player: Player)
	local profile = profiles[player]
	if not profile or player.Parent ~= Players then return end
	local r = profile.Data.Ranked
	local info = RankConfig.Get(r.Rating)
	player:SetAttribute("Rating", r.Rating)
	player:SetAttribute("RankName", info.Name)
	player:SetAttribute("RankTier", info.Tier.Id)
	player:SetAttribute("RankProgress", info.Progress)
	player:SetAttribute("RankedWins", r.Wins)
	player:SetAttribute("RankedLosses", r.Losses)
	player:SetAttribute("RankedReady", profile.Usable)
end

---------------------------------------------------------------- load / save
local function load(player: Player)
	local profile: Profile = { Data = newData(), Usable = false, Dirty = false }
	profiles[player] = profile
	for attempt = 1, 6 do
		local lockedElsewhere = false
		local ok, result = withRetry(function()
			return dataStore:UpdateAsync(key(player), function(old)
				local data = reconcile(old)
				local lock = data.Lock
				-- another live server still owns this player: don't take over yet (unless the lock is stale or we're out of patience)
				if lock and lock.Job ~= JOB_ID and os.time() - lock.Time < Cfg.LockTimeout and attempt < 6 then
					lockedElsewhere = true
					return nil -- cancel write
				end
				data.Lock = { Job = JOB_ID, Time = os.time() }
				return data
			end)
		end, 3)
		if player.Parent ~= Players then
			-- audit fix: they left while loading; release the lock we may have just taken
			if ok and not lockedElsewhere and result then
				pcall(function()
					dataStore:UpdateAsync(key(player), function(old)
						if typeof(old) == "table" and old.Lock and old.Lock.Job == JOB_ID then
							old.Lock = nil
							return old
						end
						return nil
					end)
				end)
			end
			return
		end
		if ok and not lockedElsewhere and result then
			profile.Data = reconcile(result)
			profile.Usable = true
			publish(player)
			for _, fn in ipairs(loadedListeners) do task.spawn(fn, player, profile.Data) end
			return
		end
		if not ok then break end
		task.wait(5) -- previous server is still saving; try again
	end
	warn("[RankedService] could not load data for " .. player.Name .. " - ranked disabled for this session")
	publish(player)
	Remotes.Notify:FireClient(player, "Your ranked data couldn't load. Ranked is unavailable this session.")
end

local function save(player: Player, release: boolean): boolean
	local profile = profiles[player]
	if not profile or not profile.Usable then return false end
	local snapshot = profile.Data
	local cancelled = false
	local ok, err = withRetry(function()
		return dataStore:UpdateAsync(key(player), function(old)
			local current = typeof(old) == "table" and old or nil
			local lock = current and current.Lock
			if lock and lock.Job ~= JOB_ID and os.time() - lock.Time < Cfg.LockTimeout then
				cancelled = true
				return nil -- someone else owns the record now; never overwrite it
			end
			cancelled = false
			local out = table.clone(snapshot)
			out.Lock = (not release) and { Job = JOB_ID, Time = os.time() } or nil
			return out
		end)
	end)
	if ok and cancelled then
		-- audit fix: another server took this player's session. Nothing was written, so stop using this
		-- copy (no purchases/rewards can be "saved" into the void) and send the player to rejoin.
		ok = false
		profile.Usable = false
		warn("[RankedService] lost session lock for " .. player.Name .. " - not saving")
		if not release and player.Parent == Players then
			task.defer(function() player:Kick("Your data was opened in another server. Please rejoin.") end)
		end
	elseif ok then
		profile.Dirty = false
	else
		warn("[RankedService] save failed for " .. player.Name .. ": " .. tostring(err))
	end
	-- leaderboard: only players who have finished a ranked match this season
	if ok and snapshot.Ranked.Played > 0 then
		pcall(function() boardStore:SetAsync(tostring(player.UserId), math.floor(snapshot.Ranked.Rating)) end)
	end
	return ok
end

---------------------------------------------------------------- results
local function addHistory(profile: Profile, entry: HistoryEntry)
	table.insert(profile.Data.History, 1, entry)
	while #profile.Data.History > Cfg.HistorySize do table.remove(profile.Data.History) end
	profile.Dirty = true
end

local function expectedScore(mine: number, theirs: number): number
	return 1 / (1 + 10 ^ ((theirs - mine) / 400))
end

-- result: 1 win, 0.5 draw, 0 loss
local function ratingDelta(result: number, expected: number): number
	local d = math.floor(Cfg.K * (result - expected) + 0.5)
	if result == 1 then d = math.max(d, Cfg.MinGain) end
	if result == 0 then d = math.min(d, -Cfg.MinLoss) end
	return d
end

local function applyRating(player: Player, delta: number, result: string, match: any)
	local profile = profiles[player]
	if not profile or not profile.Usable then return end
	local r = profile.Data.Ranked
	local oldRating = r.Rating
	local oldRank = RankConfig.Get(oldRating)
	r.Rating = math.max(0, r.Rating + delta)
	r.Peak = math.max(r.Peak, r.Rating)
	r.Played += 1
	if result == "W" then r.Wins += 1 elseif result == "L" then r.Losses += 1 else r.Draws += 1 end
	profile.Dirty = true
	local newRank = RankConfig.Get(r.Rating)
	publish(player)
	if player.Parent == Players then
		RankUpdate:FireClient(player, {
			Old = oldRating, New = r.Rating, Delta = r.Rating - oldRating,
			OldRank = oldRank.Name, NewRank = newRank.Name, Tier = newRank.Tier.Id,
			Progress = newRank.Progress,
			Promoted = newRank.Name ~= oldRank.Name and r.Rating > oldRating,
			Demoted = newRank.Name ~= oldRank.Name and r.Rating < oldRating,
			Season = Cfg.SeasonName,
		})
	end
end

local function statsOf(match: any, player: Player): (number, number, number)
	local s = match.Stats[player]
	if not s then return 0, 0, 0 end
	return s.Kills, s.Deaths, s.Assists
end

local function onStarted(match: any)
	if not GameConfig.Modes[match.Mode].Ranked then return end
	-- freeze each team's expectation now, so later leavers can't change it
	local sums, counts = { Alpha = 0, Bravo = 0 }, { Alpha = 0, Bravo = 0 }
	for p, team in pairs(match.TeamOf) do
		local profile = profiles[p]
		local rating = profile and profile.Data.Ranked.Rating or Cfg.StartRating
		sums[team] += rating
		counts[team] += 1
	end
	local avgA = counts.Alpha > 0 and sums.Alpha / counts.Alpha or Cfg.StartRating
	local avgB = counts.Bravo > 0 and sums.Bravo / counts.Bravo or avgA -- Studio solo: no opponents -> even odds
	local eA = expectedScore(avgA, avgB)
	match.Extra.RankedExpected = { Alpha = eA, Bravo = 1 - eA }
	match.Extra.RankedSettled = {}
end

local function onPlayerLeft(match: any, player: Player, team: string?)
	local profile = profiles[player]
	if not profile or not team then return end
	local k, d, a = statsOf(match, player)
	local entry: HistoryEntry = { T = os.time(), Mode = match.Mode, Map = match.MapId, Result = "Left", K = k, D = d, A = a, Delta = nil }
	if GameConfig.Modes[match.Mode].Ranked and match.Extra.RankedExpected and not match.Extra.RankedSettled[player.UserId] then
		match.Extra.RankedSettled[player.UserId] = true
		local delta = ratingDelta(0, match.Extra.RankedExpected[team]) - Cfg.LeavePenalty
		applyRating(player, delta, "L", match)
		entry.Delta = delta
	end
	addHistory(profile, entry)
end

local function onEnded(match: any)
	local mode = GameConfig.Modes[match.Mode]
	if match.EndReason == "Empty" then return end
	local winner = match.Winner
	for _, p in ipairs(match.Players) do
		local profile = profiles[p]
		local team = match.TeamOf[p]
		if profile and team then
			local resultText = winner == nil and "D" or (winner == team and "W" or "L")
			local k, d, a = statsOf(match, p)
			local entry: HistoryEntry = { T = os.time(), Mode = match.Mode, Map = match.MapId, Result = resultText, K = k, D = d, A = a, Delta = nil }
			-- audit fix: a forfeit (Abandoned) gives the remaining side no RP, so alts can't be used to farm rating
			if mode.Ranked and match.Extra.RankedExpected and not match.Extra.RankedSettled[p.UserId] and not match.Abandoned then
				match.Extra.RankedSettled[p.UserId] = true
				local result = resultText == "W" and 1 or (resultText == "L" and 0 or 0.5)
				local delta = ratingDelta(result, match.Extra.RankedExpected[team])
				applyRating(p, delta, resultText, match)
				entry.Delta = delta
			end
			addHistory(profile, entry)
			task.spawn(save, p, false)
		end
	end
end

---------------------------------------------------------------- leaderboard sign (Workspace.Lobby ... RankedBoard)
local nameCache: { [number]: string } = {}
local function nameOf(userId: number): string
	if nameCache[userId] then return nameCache[userId] end
	local ok, name = pcall(function() return Players:GetNameFromUserIdAsync(userId) end)
	nameCache[userId] = ok and name or ("Player " .. userId)
	return nameCache[userId]
end

local function refreshBoard()
	local sign = workspace:FindFirstChild("Lobby") and workspace.Lobby:FindFirstChild("RankedBoard", true)
	local gui = sign and sign:FindFirstChild("BoardGui")
	local rows = gui and gui:FindFirstChild("Rows", true)
	if not rows then return end
	local ok, pages = pcall(function() return boardStore:GetSortedAsync(false, 10) end)
	if not ok then return end
	local list = pages:GetCurrentPage()
	for i = 1, 10 do
		local row = rows:FindFirstChild("Row" .. i)
		if row then
			local item = list[i]
			local nameLabel = row:FindFirstChild("PlayerName") :: TextLabel?
			local valueLabel = row:FindFirstChild("Value") :: TextLabel?
			if nameLabel and valueLabel then
				-- leave room for the 3D badge each client draws between the name and the rank (RankBadgeController)
				nameLabel.Size = UDim2.fromScale(0.44, 0.8)
				if item then
					local info = RankConfig.Get(item.value)
					nameLabel.Text = nameOf(tonumber(item.key) or 0)
					valueLabel.Text = info.Name
					valueLabel.TextColor3 = info.Tier.Color
					row:SetAttribute("Tier", info.Tier.Id)
				else
					nameLabel.Text = "---"
					valueLabel.Text = "-"
					row:SetAttribute("Tier", nil)
				end
			end
		end
	end
end

---------------------------------------------------------------- public
function RankedService.IsReady(player: Player): boolean
	local p = profiles[player]
	return p ~= nil and p.Usable
end

-- Saved record access for other services (nil until loaded, or if loading failed).
function RankedService.GetData(player: Player): PlayerData?
	local p = profiles[player]
	return (p and p.Usable) and p.Data or nil
end

function RankedService.MarkDirty(player: Player)
	local p = profiles[player]
	if p then p.Dirty = true end
end

-- Saves immediately (yields). Returns true when the write succeeded. Used for Robux receipts.
function RankedService.SaveNow(player: Player): boolean
	return save(player, false)
end

-- fn(player, data) after a player's record has loaded successfully
function RankedService.OnLoaded(fn: (Player, any) -> ())
	table.insert(loadedListeners, fn)
	for p, prof in pairs(profiles) do
		if prof.Usable then task.spawn(fn, p, prof.Data) end
	end
end

function RankedService.GetHistory(player: Player): { HistoryEntry }
	local p = profiles[player]
	return p and p.Data.History or {}
end

function RankedService.Init()
	local function onJoin(p: Player) task.spawn(load, p) end
	for _, p in ipairs(Players:GetPlayers()) do onJoin(p) end
	Players.PlayerAdded:Connect(onJoin)
	Players.PlayerRemoving:Connect(function(p)
		task.wait(0.2) -- let MatchManager's PlayerLeft (leave penalty) run first
		save(p, true)
		profiles[p] = nil
	end)

	MatchManager.On("Started", onStarted)
	MatchManager.On("PlayerLeft", onPlayerLeft)
	MatchManager.On("Ended", onEnded)

	-- match history for the client (read-only)
	local getHistory = Remotes:FindFirstChild("GetMatchHistory") :: RemoteFunction?
	if getHistory then
		getHistory.OnServerInvoke = function(p: Player)
			local list = {}
			for _, e in ipairs(RankedService.GetHistory(p)) do table.insert(list, table.clone(e)) end
			return list
		end
	end

	task.spawn(function()
		while true do
			task.wait(Cfg.AutosaveSeconds)
			for p in pairs(profiles) do task.spawn(save, p, false) end
		end
	end)
	task.spawn(function()
		task.wait(5)
		while true do
			refreshBoard()
			task.wait(Cfg.LeaderboardRefresh)
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for p in pairs(profiles) do
			pending += 1
			task.spawn(function()
				save(p, true)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do task.wait(0.2) end
	end)
end

return RankedService
