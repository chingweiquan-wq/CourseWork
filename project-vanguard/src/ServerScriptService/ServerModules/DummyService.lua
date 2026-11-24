--!strict
-- DummyService: STUDIO TESTING ONLY. When one person tests a match alone in Studio, spawns enemy
-- training dummies that strafe around so weapons, damage, kills and the kill feed can be tested.
-- Never runs in live servers (GameConfig.IsStudio is false there).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local MatchManager = require(script.Parent.MatchManager)
local MapService = require(script.Parent.MapService)
local CombatService = require(script.Parent.CombatService)

local DummyService = {}

local function enabledFor(match: any): boolean
	return GameConfig.IsStudio and GameConfig.StudioSoloTesting and GameConfig.Combat.StudioTrainingDummies > 0 and #match.Players == 1 and #(match.Bots or {}) == 0 -- Phase 9: no dummies when bots play
end

local function spawnDummy(match: any, folder: Folder, team: string, spawnGroup: string, index: number)
	if match.State == "Ended" or not folder.Parent then return end
	local desc = Instance.new("HumanoidDescription")
	local col = Color3.fromRGB(200, 70, 90)
	desc.HeadColor = col; desc.TorsoColor = Color3.fromRGB(50, 50, 60); desc.LeftArmColor = col; desc.RightArmColor = col
	desc.LeftLegColor = Color3.fromRGB(50, 50, 60); desc.RightLegColor = Color3.fromRGB(50, 50, 60)
	local dummy = Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	dummy.Name = "TrainingDummy" .. index
	dummy:SetAttribute("IsDummy", true)
	dummy:SetAttribute("Team", team)
	dummy:SetAttribute("MatchId", match.Id)
	dummy:SetAttribute("DisplayName", "Training Dummy")
	local hum = dummy:FindFirstChildOfClass("Humanoid") :: Humanoid
	hum.MaxHealth = 200
	hum.Health = 200
	hum.WalkSpeed = 10
	hum.DisplayName = "Training Dummy"
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOn
	local markers = MapService.GetSpawnPoints(match.Map, spawnGroup)
	if #markers == 0 then return end
	local marker = markers[((index - 1) % #markers) + 1]
	dummy:PivotTo(marker.CFrame + Vector3.new(0, 4, 0))
	dummy.Parent = folder
	CombatService.WatchDeath(dummy, hum)

	-- small side-to-side strafe on the spawn deck (stays on the platform on floating maps)
	local home = marker.Position
	task.spawn(function()
		local side = 1
		while dummy.Parent and hum.Health > 0 do
			hum:MoveTo(home + marker.CFrame.RightVector * 4 * side)
			side = -side
			task.wait(2.5)
		end
	end)

	hum.Died:Connect(function()
		task.wait(3)
		if dummy.Parent then dummy:Destroy() end
		spawnDummy(match, folder, team, spawnGroup, index)
	end)
end

function DummyService.Init()
	MatchManager.On("Started", function(match)
		if not enabledFor(match) then return end
		local folder = Instance.new("Folder")
		folder.Name = "Dummies"
		folder.Parent = match.Map
		local playerTeam = match.TeamOf[match.Players[1]]
		local team, group
		if GameConfig.Modes[match.Mode].TeamBased then
			team = (playerTeam == "Alpha") and "Bravo" or "Alpha"
			group = team
		else
			team, group = "DummyTeam", "FFA"
		end
		for i = 1, GameConfig.Combat.StudioTrainingDummies do
			spawnDummy(match, folder, team, group, i)
		end
		print(string.format("[DummyService] Spawned %d training dummies (Studio only)", GameConfig.Combat.StudioTrainingDummies))
	end)
end

return DummyService
