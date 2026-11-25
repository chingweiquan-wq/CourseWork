--!strict
-- ProgressionService: TOKENS economy, hero unlocks (tokens + Robux), 7-day daily login streak, lifetime stats.
-- Everything here is server-authoritative; clients can only ASK (buy hero X, claim daily, prompt Robux purchase).
--
-- Match tokens (Ended): finish + win bonus + MVP bonus, x RankedMultiplier in ranked.
--   * no tokens for empty/forfeited (abandoned) matches
--   * AFK check: a player must be active (moving, or standing on the core) for MinActiveFraction of the match
-- Hero unlocks: tokens via BuyHero (RemoteFunction) or Robux via developer products (ProductConfig).
-- Robux: ProcessReceipt is idempotent - each PurchaseId is stored in the saved record, and the purchase is only
--   reported as granted after that record has been saved, so Roblox retries if a save fails.
-- Saved data lives in RankedService's record (Data.Progress).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local HeroConfig = require(ReplicatedStorage.Modules.HeroConfig)
local ProductConfig = require(ReplicatedStorage.Modules.ProductConfig)
local MatchManager = require(script.Parent.MatchManager)
local RankedService = require(script.Parent.RankedService)

local Cfg = GameConfig.Progression
local Remotes = ReplicatedStorage.Remotes
local BuyHero = Remotes.BuyHero :: RemoteFunction
local BuyHeroRobux = Remotes.BuyHeroRobux :: RemoteEvent
local ClaimDaily = Remotes.ClaimDaily :: RemoteFunction
local TokensEarned = Remotes.TokensEarned :: RemoteEvent
local Notify = Remotes.Notify :: RemoteEvent

local ProgressionService = {}

local lastRequest: { [Player]: number } = {}
-- activity[matchId][player] = { Active = seconds, LastPos = Vector3? }
type Activity = { Active: number, LastPos: Vector3? }
local tracked: { [string]: { Match: any, LiveSeconds: number, Players: { [Player]: Activity } } } = {}

---------------------------------------------------------------- helpers
local function today(): number
	return math.floor(os.time() / 86400) -- UTC day number
end

local function unlockedList(pr: any): { string }
	local list = {}
	for _, id in ipairs(HeroConfig.HeroOrder) do
		if pr.Unlocked[id] then table.insert(list, id) end
	end
	return list
end

local function publish(player: Player)
	local data = RankedService.GetData(player)
	if not data or player.Parent ~= Players then return end
	local pr = data.Progress
	player:SetAttribute("Tokens", pr.Tokens)
	player:SetAttribute("UnlockedHeroes", table.concat(unlockedList(pr), ","))
	player:SetAttribute("StarterPackBought", pr.StarterPackBought == true)
end

local function rateLimited(player: Player): boolean
	local t = os.clock()
	if lastRequest[player] and t - lastRequest[player] < Cfg.BuyCooldown then return true end
	lastRequest[player] = t
	return false
end

local function saveSoon(player: Player)
	RankedService.MarkDirty(player)
	task.spawn(RankedService.SaveNow, player)
end

local function dailyState(pr: any): { [string]: any }
	local d = today()
	local canClaim = pr.Daily.LastDay < d
	-- the streak continues only if yesterday was claimed; after day 7 it starts over
	local nextStreak = (pr.Daily.LastDay == d - 1 and pr.Daily.Streak < #Cfg.Daily) and pr.Daily.Streak + 1 or 1
	if not canClaim then nextStreak = pr.Daily.Streak end
	return { CanClaim = canClaim, Day = nextStreak, Rewards = Cfg.Daily, SecondsToReset = (d + 1) * 86400 - os.time() }
end

---------------------------------------------------------------- profile for the lobby UI (LobbyService.GetProfile)
function ProgressionService.GetProfile(player: Player): { [string]: any }
	local data = RankedService.GetData(player)
	if not data then
		-- not loaded yet (or failed): starters only, nothing can be bought
		return {
			Tokens = 0, UnlockedHeroes = table.clone(HeroConfig.StarterHeroes),
			SelectedHero = HeroConfig.StarterHeroes[1], Loading = true,
		}
	end
	local pr = data.Progress
	return {
		Tokens = pr.Tokens,
		UnlockedHeroes = unlockedList(pr),
		SelectedHero = pr.Selected,
		Daily = dailyState(pr),
		Stats = table.clone(pr.Stats),
		Loading = false,
	}
end

function ProgressionService.IsUnlocked(player: Player, heroId: string): boolean
	local data = RankedService.GetData(player)
	if data then return data.Progress.Unlocked[heroId] == true end
	return table.find(HeroConfig.StarterHeroes, heroId) ~= nil
end

---------------------------------------------------------------- token hero purchase
local function buyHero(player: Player, heroId: any): { [string]: any }
	if rateLimited(player) then return { Ok = false, Reason = "Slow down" } end
	if typeof(heroId) ~= "string" or not HeroConfig.Heroes[heroId] then return { Ok = false, Reason = "Unknown hero" } end
	local data = RankedService.GetData(player)
	if not data then return { Ok = false, Reason = "Your data is still loading" } end
	local pr = data.Progress
	local hero = HeroConfig.Heroes[heroId]
	if pr.Unlocked[heroId] then return { Ok = false, Reason = "You already own " .. hero.DisplayName } end
	local price = math.floor(tonumber(hero.Price) or 0)
	if price <= 0 then return { Ok = false, Reason = "Not for sale" } end
	if pr.Tokens < price then return { Ok = false, Reason = string.format("You need %d more tokens", price - pr.Tokens) } end
	pr.Tokens -= price
	pr.Unlocked[heroId] = true
	publish(player)
	saveSoon(player)
	return { Ok = true, Hero = heroId, Tokens = pr.Tokens }
end

---------------------------------------------------------------- daily streak
local function claimDaily(player: Player): { [string]: any }
	if rateLimited(player) then return { Ok = false, Reason = "Slow down" } end
	local data = RankedService.GetData(player)
	if not data then return { Ok = false, Reason = "Your data is still loading" } end
	local pr = data.Progress
	local state = dailyState(pr)
	if not state.CanClaim then return { Ok = false, Reason = "Already claimed today", Daily = state } end
	local amount = Cfg.Daily[state.Day]
	pr.Daily.LastDay = today()
	pr.Daily.Streak = state.Day
	pr.Tokens += amount
	pr.Stats.TokensEarned += amount
	publish(player)
	saveSoon(player)
	return { Ok = true, Amount = amount, Day = state.Day, Tokens = pr.Tokens, Daily = dailyState(pr) }
end

---------------------------------------------------------------- Robux (developer products)
type ReceiptHandler = (player: Player, receipt: any, data: any) -> boolean
local productHandlers: { [number]: ReceiptHandler } = {}

-- Phase 6 (weapon skins) registers its products here; only one ProcessReceipt can exist per game.
function ProgressionService.RegisterProduct(productId: number, handler: ReceiptHandler)
	if productId and productId > 0 then productHandlers[productId] = handler end
end

local function heroForProduct(productId: number): string?
	for heroId, id in pairs(ProductConfig.HeroProducts) do
		if id == productId then return heroId end
	end
	return nil
end

local function rememberReceipt(pr: any, purchaseId: string)
	pr.Receipts[purchaseId] = os.time()
	local count = 0
	local oldestId, oldestT = nil, math.huge
	for id, t in pairs(pr.Receipts) do
		count += 1
		if t < oldestT then oldestId, oldestT = id, t end
	end
	if count > Cfg.ReceiptsKept and oldestId then pr.Receipts[oldestId] = nil end
end

-- audit fix: receipts granted in memory whose save failed. Roblox retries the receipt; we must not report
-- PurchaseGranted until a save actually succeeds.
local unsavedReceipts: { [Player]: { [string]: boolean } } = {}
Players.PlayerRemoving:Connect(function(p) unsavedReceipts[p] = nil end)

local function processReceipt(receipt: any): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then return Enum.ProductPurchaseDecision.NotProcessedYet end -- Roblox retries next time they join
	local data = RankedService.GetData(player)
	if not data then return Enum.ProductPurchaseDecision.NotProcessedYet end
	local pr = data.Progress
	local purchaseId = tostring(receipt.PurchaseId)
	if pr.Receipts[purchaseId] then
		-- already granted; only confirm once it's really saved
		local pending = unsavedReceipts[player]
		if pending and pending[purchaseId] then
			if not RankedService.SaveNow(player) then return Enum.ProductPurchaseDecision.NotProcessedYet end
			pending[purchaseId] = nil
		end
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local handler = productHandlers[receipt.ProductId]
	if not handler then
		warn("[ProgressionService] unknown developer product " .. tostring(receipt.ProductId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if not handler(player, receipt, data) then return Enum.ProductPurchaseDecision.NotProcessedYet end
	rememberReceipt(pr, purchaseId)
	pr.RobuxSpent += tonumber(receipt.CurrencySpent) or 0
	publish(player)
	if not RankedService.SaveNow(player) then
		-- granted in memory + receipt remembered (a retry can't double-grant), but NOT saved yet:
		-- the retry path above will only confirm after a successful save
		unsavedReceipts[player] = unsavedReceipts[player] or {}
		unsavedReceipts[player][purchaseId] = true
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

---------------------------------------------------------------- match rewards
local function onLive(match: any)
	local entry = { Match = match, LiveSeconds = 0, Players = {} }
	for _, p in ipairs(match.Players) do entry.Players[p] = { Active = 0, LastPos = nil } end
	tracked[match.Id] = entry
end

local function sampleActivity()
	for _, entry in pairs(tracked) do
		local match = entry.Match
		if match.State == "Live" then
			entry.LiveSeconds += Cfg.ActivitySample
			for p, act in pairs(entry.Players) do
				local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if root then
					local pos = root.Position
					local moved = act.LastPos ~= nil and (pos - act.LastPos).Magnitude >= Cfg.ActiveMoveStuds
					if moved or p:GetAttribute("ObjOnPoint") == true then act.Active += Cfg.ActivitySample end
					act.LastPos = pos
				end
			end
		end
	end
end

local function isActive(entry: any, player: Player): boolean
	if not entry or entry.LiveSeconds < Cfg.MinTrackedSeconds then return true end
	local act = entry.Players[player]
	if not act then return false end
	local s = entry.Match.Stats[player]
	if s and (s.Kills + s.Assists) > 0 then return true end -- fighting counts as active
	return act.Active / entry.LiveSeconds >= Cfg.MinActiveFraction
end

local function onEnded(match: any)
	local entry = tracked[match.Id]
	tracked[match.Id] = nil
	if match.EndReason == "Empty" then return end
	local mode = GameConfig.Modes[match.Mode]
	for _, p in ipairs(match.Players) do
		local data = RankedService.GetData(p)
		local team = match.TeamOf[p]
		if data and team then
			local pr = data.Progress
			local s = match.Stats[p]
			local won = match.Winner ~= nil and match.Winner == team
			local lost = match.Winner ~= nil and not won
			-- lifetime stats count every finished match
			pr.Stats.Matches += 1
			if won then pr.Stats.Wins += 1 elseif lost then pr.Stats.Losses += 1 end
			if s then
				pr.Stats.Kills += s.Kills
				pr.Stats.Deaths += s.Deaths
				pr.Stats.Assists += s.Assists
			end
			-- tokens
			local lines = {}
			local total = 0
			local reason = nil
			if mode.NoRewards then
				reason = "Practice match - no tokens" -- Phase 9: 1v1 Practice vs a bot
			elseif match.Abandoned then
				reason = "Abandoned match - no tokens"
			elseif not isActive(entry, p) then
				reason = "You were inactive - no tokens"
			else
				local r = Cfg.Rewards
				table.insert(lines, { "Match", r.Complete })
				if won then table.insert(lines, { "Win", r.Win }) end
				if match.Extra.MvpUserId == p.UserId then table.insert(lines, { "MVP", r.MVP }) end
				for _, l in ipairs(lines) do total += l[2] end
				if mode.Ranked then
					local bonus = math.floor(total * Cfg.RankedMultiplier) - total
					if bonus > 0 then table.insert(lines, { "Ranked", bonus }); total += bonus end
				end
				pr.Tokens += total
				pr.Stats.TokensEarned += total
			end
			publish(p)
			RankedService.MarkDirty(p)
			TokensEarned:FireClient(p, { Total = total, Lines = lines, Reason = reason, Tokens = pr.Tokens })
		end
	end
end

---------------------------------------------------------------- init
function ProgressionService.Init()
	RankedService.OnLoaded(function(player, data)
		-- the game's owner gets every hero (for testing); applies in Studio and in the live game,
		-- and only to the account that owns the experience
		if game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId then
			local granted = false
			for _, id in ipairs(HeroConfig.HeroOrder) do
				if not data.Progress.Unlocked[id] then
					data.Progress.Unlocked[id] = true
					granted = true
				end
			end
			if granted then RankedService.MarkDirty(player) end
		end
		publish(player)
		-- restore the saved hero selection (only outside matches)
		if not MatchManager.IsInMatch(player) and data.Progress.Unlocked[data.Progress.Selected] then
			player:SetAttribute("Hero", data.Progress.Selected)
		end
		player:SetAttribute("DailyReady", dailyState(data.Progress).CanClaim)
	end)

	-- remember the selected hero (CharacterService only sets "Hero" after checking ownership)
	local function watchSelection(p: Player)
		p:GetAttributeChangedSignal("Hero"):Connect(function()
			local data = RankedService.GetData(p)
			local h = p:GetAttribute("Hero")
			if data and typeof(h) == "string" and data.Progress.Unlocked[h] and data.Progress.Selected ~= h then
				data.Progress.Selected = h
				RankedService.MarkDirty(p)
			end
		end)
	end
	for _, p in ipairs(Players:GetPlayers()) do watchSelection(p) end
	Players.PlayerAdded:Connect(watchSelection)
	Players.PlayerRemoving:Connect(function(p) lastRequest[p] = nil end)

	BuyHero.OnServerInvoke = buyHero
	ClaimDaily.OnServerInvoke = function(player: Player)
		local result = claimDaily(player)
		if result.Ok then player:SetAttribute("DailyReady", false) end
		return result
	end

	-- Robux: the client only asks; the server checks ownership and shows the Roblox purchase prompt itself
	BuyHeroRobux.OnServerEvent:Connect(function(player: Player, heroId: any)
		if rateLimited(player) then return end
		if typeof(heroId) ~= "string" or not HeroConfig.Heroes[heroId] then return end
		local productId = ProductConfig.HeroProducts[heroId]
		if not productId or productId <= 0 then
			Notify:FireClient(player, "Robux purchase for this hero isn't set up yet")
			return
		end
		if ProgressionService.IsUnlocked(player, heroId) then
			Notify:FireClient(player, "You already own " .. HeroConfig.Heroes[heroId].DisplayName)
			return
		end
		MarketplaceService:PromptProductPurchase(player, productId)
	end)
	for heroId, productId in pairs(ProductConfig.HeroProducts) do
		ProgressionService.RegisterProduct(productId, function(player, _receipt, data)
			if data.Progress.Unlocked[heroId] then
				-- audit fix: bought with tokens while the Robux prompt was open -> give the token price back
				local refund = HeroConfig.Heroes[heroId].Price or 0
				data.Progress.Tokens += refund
				Notify:FireClient(player, string.format("You already owned %s - %d tokens added instead.", HeroConfig.Heroes[heroId].DisplayName, refund))
				return true
			end
			data.Progress.Unlocked[heroId] = true
			Notify:FireClient(player, HeroConfig.Heroes[heroId].DisplayName .. " unlocked! Thanks for your support.")
			return true
		end)
	end
	-- token packs: the client asks for a pack id; the server checks it (and the one-time rule) and prompts
	local BuyTokens = Remotes:FindFirstChild("BuyTokens") :: RemoteEvent?
	if not BuyTokens then
		local r = Instance.new("RemoteEvent")
		r.Name = "BuyTokens"
		r.Parent = Remotes
		BuyTokens = r
	end
	local packById = {}
	for _, pack in ipairs(ProductConfig.TokenPacks) do packById[pack.Id] = pack end
	;(BuyTokens :: RemoteEvent).OnServerEvent:Connect(function(player: Player, packId: any)
		if rateLimited(player) then return end
		local pack = typeof(packId) == "string" and packById[packId] or nil
		if not pack or not pack.ProductId or pack.ProductId <= 0 then return end
		local data = RankedService.GetData(player)
		if not data then
			Notify:FireClient(player, "Your profile is still loading - try again in a moment")
			return
		end
		if pack.OneTime and data.Progress.StarterPackBought then
			Notify:FireClient(player, "You've already claimed the Starter Pack")
			return
		end
		MarketplaceService:PromptProductPurchase(player, pack.ProductId)
	end)
	for _, pack in ipairs(ProductConfig.TokenPacks) do
		ProgressionService.RegisterProduct(pack.ProductId, function(player, _receipt, data)
			-- always grant what was paid for (a duplicate one-time buy that slipped through still gets its tokens)
			data.Progress.Tokens += pack.Tokens
			if pack.OneTime then data.Progress.StarterPackBought = true end
			Notify:FireClient(player, string.format("+%d tokens! Thanks for your support.", pack.Tokens))
			return true
		end)
	end
	MarketplaceService.ProcessReceipt = processReceipt

	MatchManager.On("Live", onLive)
	MatchManager.On("Ended", onEnded)
	task.spawn(function()
		while true do
			task.wait(Cfg.ActivitySample)
			sampleActivity()
		end
	end)
end

return ProgressionService
