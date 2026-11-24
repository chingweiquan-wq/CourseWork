--!strict
-- SettingsService: saved per-player audio settings (Phase 7).
--  * Stored in Data.Progress.Settings { Music, Sfx, Announcer } (RankedService record, numbers 0..1).
--  * Published as attributes VolMusic / VolSfx / VolAnnouncer so the client applies them on join.
--  * SaveSettings (RemoteFunction) validates every value (type, NaN, range) and is rate-limited.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local AudioConfig = require(ReplicatedStorage.Modules.AudioConfig)
local RankedService = require(script.Parent.RankedService)

local SaveSettings = ReplicatedStorage.Remotes.SaveSettings :: RemoteFunction

local KINDS = { "Music", "Sfx", "Announcer" }
local COOLDOWN = 0.5

local SettingsService = {}
local lastSave: { [Player]: number } = {}

local function publish(player: Player, s: { [string]: number })
	for _, k in ipairs(KINDS) do player:SetAttribute("Vol" .. k, s[k]) end
end

local function clean(v: any, default: number): number
	if typeof(v) ~= "number" or v ~= v then return default end
	return math.clamp(math.floor(v * 100 + 0.5) / 100, 0, 1)
end

function SettingsService.Init()
	RankedService.OnLoaded(function(player, data)
		publish(player, data.Progress.Settings)
	end)

	SaveSettings.OnServerInvoke = function(player: Player, req: any)
		if typeof(req) ~= "table" then return { Ok = false, Reason = "Bad request" } end
		local t = os.clock()
		if lastSave[player] and t - lastSave[player] < COOLDOWN then return { Ok = false, Reason = "Slow down" } end
		lastSave[player] = t
		local data = RankedService.GetData(player)
		if not data then return { Ok = false, Reason = "Profile still loading" } end
		local s = data.Progress.Settings
		for _, k in ipairs(KINDS) do
			if req[k] ~= nil then s[k] = clean(req[k], s[k]) end
		end
		publish(player, s)
		RankedService.MarkDirty(player)
		return { Ok = true }
	end

	Players.PlayerRemoving:Connect(function(p) lastSave[p] = nil end)
end

return SettingsService
