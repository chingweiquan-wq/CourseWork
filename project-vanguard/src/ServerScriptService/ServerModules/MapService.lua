--!strict
-- MapService: clones map templates from ServerStorage.Maps into numbered arena slots
-- so several matches can run at once on one server, and cleans them up afterwards.
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local MapConfig = require(ReplicatedStorage.Modules.MapConfig)

local MapService = {}

local activeFolder: Folder
local slots: { [number]: Model } = {}

function MapService.Init()
	local f = workspace:FindFirstChild("ActiveMaps")
	if not f then
		f = Instance.new("Folder")
		f.Name = "ActiveMaps"
		f.Parent = workspace
	end
	activeFolder = f :: Folder
end

function MapService.PickMap(modeId: string): string?
	local options = MapConfig.GetMapsForMode(modeId)
	if #options == 0 then return nil end
	return options[math.random(1, #options)]
end

-- Returns the loaded map model and its slot index, or nil if no slot/template is available.
function MapService.Load(mapId: string): (Model?, number?)
	local template = ServerStorage.Maps:FindFirstChild(mapId)
	if not template or not MapConfig.Maps[mapId] then
		warn("[MapService] Missing map template:", mapId)
		return nil, nil
	end
	local slot: number? = nil
	for i = 1, GameConfig.Match.MaxConcurrentMatches do
		if not slots[i] then slot = i break end
	end
	if not slot then
		warn("[MapService] All arena slots are busy")
		return nil, nil
	end
	local map = (template :: Model):Clone()
	map.Name = string.format("%s_Slot%d", mapId, slot)
	map:SetAttribute("MapId", mapId)
	map:SetAttribute("Slot", slot)
	map:PivotTo(CFrame.new(slot * GameConfig.Match.SlotSpacing, 0, 0))
	map.Parent = activeFolder
	slots[slot] = map
	return map, slot
end

function MapService.Unload(slot: number)
	local map = slots[slot]
	if map then
		map:Destroy()
		slots[slot] = nil
	end
end

-- groupName: "Alpha", "Bravo" or "FFA"
function MapService.GetSpawnPoints(map: Model, groupName: string): { BasePart }
	local list = {}
	local spawns = map:FindFirstChild("Spawns")
	local group = spawns and spawns:FindFirstChild(groupName)
	if group then
		for _, p in ipairs(group:GetChildren()) do
			if p:IsA("BasePart") then table.insert(list, p) end
		end
	end
	return list
end

return MapService
