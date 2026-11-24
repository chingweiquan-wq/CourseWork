--!strict
-- LeaderboardService (Phase 8): the persistent MOST KILLS and TOP SUPPORTERS boards.
--  * Kills: lifetime kills of REAL players only (training dummies don't count). Counted the moment the
--    server records the elimination (MatchManager "PlayerKill"), saved in Data.Progress.Stats.PlayerKills.
--  * Robux: Data.Progress.RobuxSpent, which only grows inside ProgressionService's ProcessReceipt after a
--    product is granted (Roblox's own receipt, de-duplicated by PurchaseId). Failed/cancelled buys never
--    reach it, and nothing outside this game's receipts is counted.
--  * Privacy: players can hide themselves from TOP SUPPORTERS (Settings). The flag rides in the score
--    itself (stored = spent * 2 + hidden) so the board needs no extra DataStore reads; hidden rows show
--    as "Anonymous" and their UserId is never sent to clients.
--  * Budget: every RefreshSeconds one SetAsync per player whose score changed, plus one GetSortedAsync
--    per board. Scores are also written when a player leaves and when the server shuts down.
--  * Clients get the top lists (LeaderboardData "Boards") and their own rank/score ("Self").
--  * The top 3 of each board stand on top of it as 3D avatars (anonymous = hologram mannequin).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local AudioConfig = require(ReplicatedStorage.Modules.AudioConfig)
local RankedService = require(script.Parent.RankedService)
local MatchManager = require(script.Parent.MatchManager)

local Cfg = GameConfig.Leaderboards
local LeaderboardData = ReplicatedStorage.Remotes.LeaderboardData :: RemoteEvent

local PREFIX = RunService:IsStudio() and "STUDIO_" or ""
local stores: { [string]: OrderedDataStore } = {}
for id, b in pairs(Cfg.Boards) do stores[id] = DataStoreService:GetOrderedDataStore(PREFIX .. b.Store) end

type Entry = { Rank: number, UserId: number?, Name: string, Value: number }

local LeaderboardService = {}

-- latest lists: shown (top Show) and the full fetched ranking (UserId -> rank) for own-rank lookups
local shown: { [string]: { Entry } } = { Kills = {}, Robux = {} }
local rankOf: { [string]: { [number]: number } } = { Kills = {}, Robux = {} }
local hiddenIds: { [number]: boolean } = {} -- Robux entries flagged hidden (server-only knowledge)
local lastWritten: { [Player]: { [string]: number } } = {}

---------------------------------------------------------------- scores
local function scoreOf(data: any, board: string): number
	local pr = data.Progress
	if board == "Kills" then
		return math.max(0, math.floor(tonumber(pr.Stats.PlayerKills) or 0))
	end
	local spent = math.max(0, math.floor(tonumber(pr.RobuxSpent) or 0))
	local hidden = (pr.Settings and pr.Settings.HideSpending == 1) and 1 or 0
	return spent * 2 + hidden
end

local function displayValue(board: string, stored: number): number
	return board == "Robux" and math.floor(stored / 2) or stored
end

local function writeScores(player: Player, data: any?)
	data = data or RankedService.GetData(player)
	if not data then return end
	local written = lastWritten[player] or {}
	lastWritten[player] = written
	for board, store in pairs(stores) do
		local v = scoreOf(data, board)
		-- only players with something to show, and only when the score changed (saves DataStore budget)
		if displayValue(board, v) > 0 and written[board] ~= v then
			local ok, err = pcall(function() store:SetAsync(tostring(player.UserId), v) end)
			if ok then written[board] = v else warn("[LeaderboardService] write failed: " .. tostring(err)) end
		end
	end
end

---------------------------------------------------------------- names
local nameCache: { [number]: string } = {}
local function nameOf(userId: number): string
	if nameCache[userId] then return nameCache[userId] end
	local online = Players:GetPlayerByUserId(userId)
	if online then nameCache[userId] = online.DisplayName return online.DisplayName end
	local ok, name = pcall(function() return Players:GetNameFromUserIdAsync(userId) end)
	nameCache[userId] = ok and name or ("Player " .. userId)
	return nameCache[userId]
end

---------------------------------------------------------------- self line (rank + own score), sent only to that player
local function sendSelf(player: Player)
	local data = RankedService.GetData(player)
	if not data then return end
	local out = {}
	for board in pairs(stores) do
		out[board] = { Rank = rankOf[board][player.UserId], Value = displayValue(board, scoreOf(data, board)) }
	end
	out.Hidden = data.Progress.Settings and data.Progress.Settings.HideSpending == 1 or false
	LeaderboardData:FireClient(player, "Self", out)
end

local function publicLists()
	local out = {}
	for board, list in pairs(shown) do
		local copy = {}
		for i, e in ipairs(list) do
			copy[i] = { Rank = e.Rank, UserId = e.UserId, Name = e.Name, Value = e.Value }
		end
		out[board] = copy
	end
	return out
end

---------------------------------------------------------------- podium: top 3 avatars standing on each board
local podiumCache: { [string]: Model } = {} -- template avatars by key ("u<id>" or "anon")
local podiumShown: { [string]: string } = {} -- board -> signature of what's standing there now

local function findSign(board: string): BasePart?
	local lobby = workspace:FindFirstChild("Lobby")
	local s = lobby and lobby:FindFirstChild(board .. "Board", true)
	return (s and s:IsA("BasePart")) and s or nil
end

local function avatarTemplate(userId: number?): Model?
	local key = userId and ("u" .. userId) or "anon"
	if podiumCache[key] then return podiumCache[key] end
	local ok, model = pcall(function()
		if userId then return Players:CreateHumanoidModelFromUserId(userId) end
		return Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15)
	end)
	if not ok or not model then return nil end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Script") or d:IsA("LocalScript") then d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = false; d.CanCollide = false; d.CanQuery = false; d.CanTouch = false; d.Massless = true
			if not userId then -- anonymous: a cyan hologram mannequin
				d.Material = Enum.Material.ForceField
				d.Color = Color3.fromRGB(0, 220, 255)
			end
		elseif not userId and (d:IsA("Decal") or d:IsA("Accessory") or d:IsA("Clothing") or d:IsA("ShirtGraphic")) then
			d:Destroy()
		end
	end
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum.BreakJointsOnDeath = false
		hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
		if not hum:FindFirstChildOfClass("Animator") then Instance.new("Animator").Parent = hum end
	end
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then root.Anchored = true; model.PrimaryPart = root end
	podiumCache[key] = model
	return model
end

-- classic podium as seen from the lobby: #2 on the left, #1 in the middle (tallest), #3 on the right
local SPOTS = { { Offset = 0, Lift = 0.8, Anim = "Victory" }, { Offset = 3.6, Lift = 0.4, Anim = "Emote" }, { Offset = -3.6, Lift = 0, Anim = "Emote" } }
local MEDAL = { Color3.fromRGB(255, 205, 60), Color3.fromRGB(210, 220, 235), Color3.fromRGB(215, 135, 70) }

local function buildPodium(board: string)
	local sign = findSign(board)
	if not sign then return end
	local list = shown[board]
	local sig = {}
	for i = 1, 3 do local e = list[i]; sig[i] = e and (e.UserId and tostring(e.UserId) or "anon") or "-" end
	local signature = table.concat(sig, ",")
	if podiumShown[board] == signature then return end
	podiumShown[board] = signature

	local folder = sign.Parent:FindFirstChild(board .. "Podium")
	if folder then folder:Destroy() end
	local f = Instance.new("Folder")
	f.Name = board .. "Podium"
	f.Parent = sign.Parent

	-- the board's front faces the lobby; stand the avatars on a ledge along its top edge, facing out
	local gui = sign:FindFirstChild("BoardGui") :: SurfaceGui?
	local face = gui and gui.Face or Enum.NormalId.Front
	local front = sign.CFrame:VectorToWorldSpace(Vector3.FromNormalId(face))
	front = Vector3.new(front.X, 0, front.Z).Unit
	local along = front:Cross(Vector3.yAxis).Unit
	local top = sign.Position + Vector3.new(0, sign.Size.Y / 2, 0)

	local ledge = Instance.new("Part")
	ledge.Name = "Ledge"
	ledge.Anchored = true; ledge.CanCollide = false; ledge.CanQuery = false; ledge.CanTouch = false
	ledge.Material = Enum.Material.Neon
	ledge.Color = Cfg.Boards[board].Color
	ledge.Size = Vector3.new(12, 0.3, 2.2)
	ledge.CFrame = CFrame.lookAt(top + Vector3.new(0, 0.15, 0), top + Vector3.new(0, 0.15, 0) + front)
	ledge.Parent = f

	for i, spot in ipairs(SPOTS) do
		local e = list[i]
		if e then
			local base = top + along * spot.Offset + Vector3.new(0, 0.3, 0)
			local step = Instance.new("Part")
			step.Name = "Step" .. i
			step.Anchored = true; step.CanCollide = false; step.CanQuery = false; step.CanTouch = false
			step.Material = Enum.Material.Neon
			step.Color = MEDAL[i]
			step.Size = Vector3.new(2.6, spot.Lift + 0.2, 2.2)
			step.CFrame = CFrame.lookAt(base + Vector3.new(0, (spot.Lift + 0.2) / 2, 0), base + Vector3.new(0, (spot.Lift + 0.2) / 2, 0) + front)
			step.Parent = f
			local tmpl = avatarTemplate(e.UserId)
			if tmpl then
				local m = tmpl:Clone()
				m.Name = board .. "Top" .. i
				local hum = m:FindFirstChildOfClass("Humanoid")
				local hip = hum and (hum.HipHeight + (m.PrimaryPart and m.PrimaryPart.Size.Y / 2 or 1)) or 3
				local feet = base + Vector3.new(0, spot.Lift + 0.2, 0)
				m:PivotTo(CFrame.lookAt(feet + Vector3.new(0, hip, 0), feet + Vector3.new(0, hip, 0) + front))
				m.Parent = f
				-- nameplate
				local bb = Instance.new("BillboardGui")
				bb.Size = UDim2.fromScale(4.5, 1.1)
				bb.StudsOffsetWorldSpace = Vector3.new(0, 3.4, 0)
				bb.LightInfluence = 0
				bb.MaxDistance = 120
				bb.Adornee = m.PrimaryPart
				bb.Parent = m
				local t = Instance.new("TextLabel")
				t.BackgroundTransparency = 1
				t.Size = UDim2.fromScale(1, 1)
				t.Font = Enum.Font.FredokaOne
				t.TextScaled = true
				t.TextColor3 = MEDAL[i]
				t.Text = "#" .. i .. "  " .. e.Name
				local st = Instance.new("UIStroke"); st.Thickness = 2; st.Parent = t
				t.Parent = bb
				-- idle celebration loop (Phase 7 animations)
				local animator = hum and hum:FindFirstChildOfClass("Animator")
				if animator then
					local a = Instance.new("Animation")
					a.AnimationId = (AudioConfig.Animations :: any)[spot.Anim]
					local ok, track = pcall(function() return animator:LoadAnimation(a) end)
					if ok and track then
						track.Looped = true
						task.delay(i * 0.7, function() if m.Parent then track:Play(0.3, 1, 0.8) end end)
					end
				end
			end
		end
	end
end

---------------------------------------------------------------- refresh (read the boards)
local function readBoard(board: string)
	local ok, pages = pcall(function() return stores[board]:GetSortedAsync(false, Cfg.Fetch) end)
	if not ok then warn("[LeaderboardService] read failed for " .. board .. ": " .. tostring(pages)) return end
	local page = (pages :: any):GetCurrentPage()
	local ranks = {}
	local list: { Entry } = {}
	for i, item in ipairs(page) do
		local userId = tonumber(item.key)
		if userId then
			ranks[userId] = i
			local value = displayValue(board, item.value)
			local hidden = board == "Robux" and item.value % 2 == 1
			if board == "Robux" then hiddenIds[userId] = hidden or nil end
			if i <= Cfg.Show and value > 0 then
				table.insert(list, { Rank = i, UserId = (not hidden) and userId or nil, Name = hidden and "Anonymous" or nameOf(userId), Value = value })
			end
		end
	end
	rankOf[board] = ranks
	shown[board] = list
end

local refreshing = false
local function refreshAll()
	if refreshing then return end
	refreshing = true
	for _, p in ipairs(Players:GetPlayers()) do writeScores(p) end
	for board in pairs(stores) do readBoard(board) end
	LeaderboardData:FireAllClients("Boards", publicLists())
	for _, p in ipairs(Players:GetPlayers()) do task.spawn(sendSelf, p) end
	for board in pairs(stores) do task.spawn(buildPodium, board) end
	refreshing = false
end

---------------------------------------------------------------- privacy toggle: hide/unhide right away on boards already shown
local lastHidden: { [Player]: boolean } = {}
local privacyPending: { [Player]: boolean } = {}
local function applyPrivacy(player: Player)
	local data = RankedService.GetData(player)
	if not data then return end
	local hidden = data.Progress.Settings.HideSpending == 1
	if lastHidden[player] == hidden then return end
	lastHidden[player] = hidden
	for _, e in ipairs(shown.Robux) do
		if rankOf.Robux[player.UserId] == e.Rank then
			e.UserId = (not hidden) and player.UserId or nil
			e.Name = hidden and "Anonymous" or player.DisplayName
		end
	end
	sendSelf(player)
	-- audit fix: one pending broadcast + one pending write per player, so toggling can't spam
	-- server-wide broadcasts, podium rebuilds or OrderedDataStore writes
	if not privacyPending[player] then
		privacyPending[player] = true
		task.delay(3, function()
			LeaderboardData:FireAllClients("Boards", publicLists())
			buildPodium("Robux")
		end)
		task.delay(10, function()
			privacyPending[player] = nil
			if player.Parent == Players then writeScores(player) end
		end)
	end
end

---------------------------------------------------------------- public
function LeaderboardService.Init()
	-- count real-player kills the moment they happen
	MatchManager.On("PlayerKill", function(_match, killer: Player, _victim: Player)
		local data = RankedService.GetData(killer)
		if not data then return end
		local st = data.Progress.Stats
		st.PlayerKills = (tonumber(st.PlayerKills) or 0) + 1
		RankedService.MarkDirty(killer)
		sendSelf(killer)
	end)

	RankedService.OnLoaded(function(player, data)
		lastWritten[player] = {}
		lastHidden[player] = data.Progress.Settings.HideSpending == 1
		LeaderboardData:FireClient(player, "Boards", publicLists())
		sendSelf(player)
		player:GetAttributeChangedSignal("HideSpending"):Connect(function() applyPrivacy(player) end)
	end)

	Players.PlayerRemoving:Connect(function(p)
		local data = RankedService.GetData(p) -- still available: RankedService releases the profile a moment later
		if data then task.spawn(writeScores, p, data) end
		task.delay(15, function() lastWritten[p] = nil; lastHidden[p] = nil; privacyPending[p] = nil end)
	end)

	game:BindToClose(function()
		for _, p in ipairs(Players:GetPlayers()) do task.spawn(writeScores, p) end
		task.wait(2)
	end)

	task.spawn(function()
		task.wait(Cfg.FirstRefreshDelay)
		while true do
			refreshAll()
			task.wait(Cfg.RefreshSeconds)
		end
	end)

	-- Studio-only QA hook (never exists on live servers): solo playtests can't produce real-player kills
	-- or real Robux receipts, so this lets a tester add them to their own Studio profile and force a refresh.
	if RunService:IsStudio() then
		local hook = Instance.new("BindableFunction")
		hook.Name = "VG_LeaderboardTest"
		hook.OnInvoke = function(action: string, target: Player?, amount: number?)
			if action == "Refresh" then refreshAll() return true end
			local data = target and RankedService.GetData(target)
			if not data or not target then return false end
			if action == "AddKills" then
				data.Progress.Stats.PlayerKills += math.floor(amount or 1)
			elseif action == "AddRobux" then
				data.Progress.RobuxSpent += math.floor(amount or 0)
			end
			RankedService.MarkDirty(target)
			sendSelf(target)
			return true
		end
		hook.Parent = game:GetService("ServerStorage")
	end
end

-- for tests / admin tools: force an immediate refresh (still rate-limited by `refreshing`)
function LeaderboardService.RefreshNow()
	task.spawn(refreshAll)
end

return LeaderboardService
