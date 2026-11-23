--!strict
-- Matchmaking: server-authoritative queues for Casual / Ranked / Duel.
-- Clients may only ask to Join(mode) or Leave; everything else is decided here.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local MatchManager = require(script.Parent.MatchManager)

local Remotes = ReplicatedStorage.Remotes
local QueueRequest = Remotes.QueueRequest :: RemoteEvent
local QueueUpdate = Remotes.QueueUpdate :: RemoteEvent
local Notify = Remotes.Notify :: RemoteEvent

local Matchmaking = {}

local queues: { [string]: { Player } } = {}
local countdownEndsAt: { [string]: number? } = {}
local queueOf: { [Player]: string } = {}
local lastRequest: { [Player]: number } = {}

for _, modeId in ipairs(GameConfig.ModeOrder) do
	queues[modeId] = {}
end

local function now(): number
	return workspace:GetServerTimeNow()
end

local function sendUpdate(modeId: string)
	local q = queues[modeId]
	local mode = GameConfig.Modes[modeId]
	for _, p in ipairs(q) do
		QueueUpdate:FireClient(p, {
			InQueue = true,
			Mode = modeId,
			Count = #q,
			Needed = GameConfig.GetMinPlayers(modeId),
			Max = mode.MaxPlayers,
			CountdownEndsAt = countdownEndsAt[modeId],
		})
	end
end

function Matchmaking.Leave(player: Player, silent: boolean?)
	local modeId = queueOf[player]
	if not modeId then return end
	queueOf[player] = nil
	local q = queues[modeId]
	local idx = table.find(q, player)
	if idx then table.remove(q, idx) end
	if #q < GameConfig.GetMinPlayers(modeId) then
		countdownEndsAt[modeId] = nil
	end
	if not silent and player.Parent == Players then
		QueueUpdate:FireClient(player, { InQueue = false })
	end
	sendUpdate(modeId)
end

function Matchmaking.Join(player: Player, modeId: any)
	if typeof(modeId) ~= "string" or not GameConfig.Modes[modeId] then return end
	if MatchManager.IsInMatch(player) then
		Notify:FireClient(player, "You are already in a match.")
		return
	end
	if queueOf[player] == modeId then return end
	if queueOf[player] then Matchmaking.Leave(player, true) end
	queueOf[player] = modeId
	table.insert(queues[modeId], player)
	sendUpdate(modeId)
end

function Matchmaking.GetModeOf(player: Player): string?
	return queueOf[player]
end

function Matchmaking.GetQueueCount(modeId: string): number
	local q = queues[modeId]
	return q and #q or 0
end

function Matchmaking.GetCountdownEndsAt(modeId: string): number?
	return countdownEndsAt[modeId]
end

local function tick()
	for _, modeId in ipairs(GameConfig.ModeOrder) do
		local q = queues[modeId]
		local mode = GameConfig.Modes[modeId]
		local minPlayers = GameConfig.GetMinPlayers(modeId)
		local changed = false

		if #q >= minPlayers then
			local t = now()
			if not countdownEndsAt[modeId] then
				countdownEndsAt[modeId] = t + GameConfig.Queue.Countdown
				changed = true
			end
			if #q >= mode.MaxPlayers then
				local short = t + GameConfig.Queue.FullLobbyCountdown
				if (countdownEndsAt[modeId] :: number) > short then
					countdownEndsAt[modeId] = short
					changed = true
				end
			end
			if t >= (countdownEndsAt[modeId] :: number) then
				-- Take up to MaxPlayers from the front of the queue (first come, first served).
				local group = {}
				while #group < mode.MaxPlayers and #q > 0 do
					local p = table.remove(q, 1) :: Player
					queueOf[p] = nil
					table.insert(group, p)
				end
				countdownEndsAt[modeId] = nil
				local ok = MatchManager.StartMatch(modeId, group)
				if ok then
					for _, p in ipairs(group) do
						QueueUpdate:FireClient(p, { InQueue = false, MatchFound = true })
					end
				else
					-- No free arena or players left: put them back at the front of the queue.
					for i = #group, 1, -1 do
						local p = group[i]
						if p.Parent == Players and not MatchManager.IsInMatch(p) then
							table.insert(q, 1, p)
							queueOf[p] = modeId
							Notify:FireClient(p, "All arenas are busy - you keep your place in the queue.")
						end
					end
				end
				changed = true
			end
		elseif countdownEndsAt[modeId] then
			countdownEndsAt[modeId] = nil
			changed = true
		end

		if changed then sendUpdate(modeId) end
	end
end

function Matchmaking.Init()
	QueueRequest.OnServerEvent:Connect(function(player: Player, action: any, modeId: any)
		local t = os.clock()
		if lastRequest[player] and t - lastRequest[player] < GameConfig.Queue.RequestCooldown then return end
		lastRequest[player] = t
		if action == "Join" then
			Matchmaking.Join(player, modeId)
		elseif action == "Leave" then
			Matchmaking.Leave(player)
		end
	end)
	Players.PlayerRemoving:Connect(function(p)
		Matchmaking.Leave(p, true)
		lastRequest[p] = nil
	end)
	task.spawn(function()
		while true do
			tick()
			task.wait(0.5)
		end
	end)
end

return Matchmaking
