--!strict
-- LobbyService: Shop navigation to Isaac, Isaac's interaction prompt, and lobby profile data.
-- Profile data is a Phase 1 placeholder; Phase 5 replaces GetProfile with DataService (DataStore-backed).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local HeroConfig = require(ReplicatedStorage.Modules.HeroConfig)
local MatchManager = require(script.Parent.MatchManager)

local Remotes = ReplicatedStorage.Remotes
local ShopNavigate = Remotes.ShopNavigate :: RemoteEvent
local OpenShop = Remotes.OpenShop :: RemoteEvent
local GetLobbyData = Remotes.GetLobbyData :: RemoteFunction

local LobbyService = {}
local lastShopTeleport: { [Player]: number } = {}

function LobbyService.GetProfile(player: Player)
	-- PLACEHOLDER until DataService (Phase 5). Not saved.
	-- Studio solo testing unlocks every hero so all weapons can be tested; live servers use starter heroes only.
	local unlocked = table.clone(HeroConfig.StarterHeroes)
	if GameConfig.IsStudio and GameConfig.StudioSoloTesting then
		unlocked = table.clone(HeroConfig.HeroOrder)
	end
	local selected = player:GetAttribute("Hero")
	if typeof(selected) ~= "string" or not table.find(unlocked, selected) then
		selected = HeroConfig.StarterHeroes[1]
	end
	return {
		Tokens = 0,
		UnlockedHeroes = unlocked,
		SelectedHero = selected,
		Rank = "Unranked",
		IsPlaceholder = true,
	}
end

function LobbyService.Init()
	local lobby = workspace:WaitForChild("Lobby")
	local shopArea = lobby:WaitForChild("ShopArea")
	local teleportMarker = shopArea:WaitForChild("ShopTeleport") :: BasePart
	local isaac = shopArea:WaitForChild("Isaac") :: Model
	local prompt = isaac:FindFirstChildWhichIsA("ProximityPrompt", true) :: ProximityPrompt

	ShopNavigate.OnServerEvent:Connect(function(player: Player)
		if MatchManager.IsInMatch(player) then return end
		local t = os.clock()
		if lastShopTeleport[player] and t - lastShopTeleport[player] < GameConfig.Lobby.ShopTeleportCooldown then return end
		lastShopTeleport[player] = t
		local character = player.Character
		if character and character:FindFirstChild("HumanoidRootPart") then
			character:PivotTo(teleportMarker.CFrame + Vector3.new(0, 3, 0))
		end
	end)

	prompt.Triggered:Connect(function(player: Player)
		if MatchManager.IsInMatch(player) then return end
		OpenShop:FireClient(player)
	end)

	GetLobbyData.OnServerInvoke = function(player: Player)
		return LobbyService.GetProfile(player)
	end

	Players.PlayerRemoving:Connect(function(p) lastShopTeleport[p] = nil end)
end

return LobbyService
