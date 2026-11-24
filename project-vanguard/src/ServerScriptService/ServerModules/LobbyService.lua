--!strict
-- LobbyService: Shop navigation to Isaac, Isaac's interaction prompt, and lobby profile data.
-- Profile data comes from ProgressionService (saved tokens, owned heroes, selected hero, daily streak).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local MatchManager = require(script.Parent.MatchManager)
local ProgressionService = require(script.Parent.ProgressionService)

local Remotes = ReplicatedStorage.Remotes
local ShopNavigate = Remotes.ShopNavigate :: RemoteEvent
local OpenShop = Remotes.OpenShop :: RemoteEvent
local GetLobbyData = Remotes.GetLobbyData :: RemoteFunction

local LobbyService = {}
local lastShopTeleport: { [Player]: number } = {}

function LobbyService.GetProfile(player: Player)
	local profile = ProgressionService.GetProfile(player)
	profile.Rank = player:GetAttribute("RankName") or "Unranked"
	return profile
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
