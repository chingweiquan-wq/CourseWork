--!strict
-- SkinService: weapon-skin ownership, equipping and Robux purchases (server-authoritative).
--  * Owned + equipped skins are saved in Data.Progress.Skins (RankedService record).
--  * Clients see them through attributes: OwnedSkins ("id,id,..") and EquippedSkins (SkinConfig.Encode).
--  * Skins are Robux-only: BuySkin asks the server, which checks the product and ownership and then shows
--    Roblox's purchase prompt. The grant happens in ProgressionService's single ProcessReceipt
--    (idempotent, saved before it reports success).
--  * Equipping is validated (exists, fits that weapon, owned). Equipped skins appear the next time the
--    weapon is built (spawn); they never change combat stats.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local SkinConfig = require(ReplicatedStorage.Modules.SkinConfig)
local ProductConfig = require(ReplicatedStorage.Modules.ProductConfig)
local RankedService = require(script.Parent.RankedService)
local ProgressionService = require(script.Parent.ProgressionService)

local Cfg = GameConfig.Cosmetics
local Remotes = ReplicatedStorage.Remotes
local EquipSkin = Remotes.EquipSkin :: RemoteFunction
local BuySkin = Remotes.BuySkin :: RemoteEvent
local Notify = Remotes.Notify :: RemoteEvent

local STUDIO_ALL = RunService:IsStudio() and Cfg.StudioOwnAllSkins

local SkinService = {}
local lastRequest: { [Player]: number } = {}

local function owns(data: any, skinId: string): boolean
	return STUDIO_ALL or data.Progress.Skins.Owned[skinId] == true
end

local function publish(player: Player)
	local data = RankedService.GetData(player)
	if not data or player.Parent ~= Players then return end
	local owned = {}
	for _, s in ipairs(SkinConfig.All()) do
		if owns(data, s.Id) then table.insert(owned, s.Id) end
	end
	player:SetAttribute("OwnedSkins", table.concat(owned, ","))
	player:SetAttribute("EquippedSkins", SkinConfig.Encode(data.Progress.Skins.Equipped))
end

local function rateLimited(player: Player): boolean
	local t = os.clock()
	if lastRequest[player] and t - lastRequest[player] < Cfg.EquipCooldown then return true end
	lastRequest[player] = t
	return false
end

-- weaponId + skinId equips; weaponId + nil goes back to the default look
local function equip(player: Player, weaponId: any, skinId: any): { [string]: any }
	if rateLimited(player) then return { Ok = false, Reason = "Slow down" } end
	if typeof(weaponId) ~= "string" or not SkinConfig.WeaponNames[weaponId] then return { Ok = false, Reason = "Unknown weapon" } end
	local data = RankedService.GetData(player)
	if not data then return { Ok = false, Reason = "Your data is still loading" } end
	local equipped = data.Progress.Skins.Equipped
	if skinId == nil then
		equipped[weaponId] = nil
	else
		if typeof(skinId) ~= "string" then return { Ok = false, Reason = "Unknown skin" } end
		local skin = SkinConfig.Skins[skinId]
		if not skin or skin.Weapon ~= weaponId then return { Ok = false, Reason = "That skin doesn't fit this weapon" } end
		if not owns(data, skinId) then return { Ok = false, Reason = "You don't own " .. skin.Name } end
		equipped[weaponId] = skinId
	end
	RankedService.MarkDirty(player)
	publish(player)
	return { Ok = true, Weapon = weaponId, Skin = equipped[weaponId] }
end

function SkinService.Init()
	RankedService.OnLoaded(function(player) publish(player) end)
	Players.PlayerRemoving:Connect(function(p) lastRequest[p] = nil end)

	EquipSkin.OnServerInvoke = equip

	BuySkin.OnServerEvent:Connect(function(player: Player, skinId: any)
		if rateLimited(player) then return end
		if typeof(skinId) ~= "string" or not SkinConfig.Skins[skinId] then return end
		local data = RankedService.GetData(player)
		if not data then
			Notify:FireClient(player, "Your data is still loading - try again in a moment")
			return
		end
		if data.Progress.Skins.Owned[skinId] then
			Notify:FireClient(player, "You already own " .. SkinConfig.Skins[skinId].Name)
			return
		end
		local productId = ProductConfig.SkinProducts[skinId]
		if not productId or productId <= 0 then
			Notify:FireClient(player, "This skin isn't on sale yet")
			return
		end
		MarketplaceService:PromptProductPurchase(player, productId)
	end)

	for skinId, productId in pairs(ProductConfig.SkinProducts) do
		ProgressionService.RegisterProduct(productId, function(player, _receipt, data)
			local skin = SkinConfig.Skins[skinId]
			if not skin then return false end
			local sk = data.Progress.Skins
			sk.Owned[skinId] = true
			if not sk.Equipped[skin.Weapon] then sk.Equipped[skin.Weapon] = skinId end -- first skin for that weapon: wear it
			publish(player)
			Notify:FireClient(player, skin.Name .. " unlocked! Equip it from your Inventory.")
			return true
		end)
	end
end

return SkinService
