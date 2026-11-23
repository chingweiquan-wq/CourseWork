--!strict
-- SpawnService: places characters at lobby or map spawn points.
-- Lobby uses real SpawnLocations (Workspace.Lobby.Spawns). Map spawns are plain marker parts.
local SpawnService = {}

local function waitForRoot(character: Model): BasePart?
	local root = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart", 5)
	return root :: BasePart?
end

function SpawnService.PlaceAt(character: Model, marker: BasePart)
	local root = waitForRoot(character)
	if not root then return end
	local offset = Vector3.new(math.random(-3, 3), 4, math.random(-3, 3))
	character:PivotTo(CFrame.new(marker.Position + offset) * marker.CFrame.Rotation)
end

function SpawnService.PlaceAtRandom(character: Model, markers: { BasePart })
	if #markers == 0 then
		warn("[SpawnService] No spawn markers available")
		return
	end
	SpawnService.PlaceAt(character, markers[math.random(1, #markers)])
end

function SpawnService.SetFrozen(character: Model?, frozen: boolean)
	if not character then return end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then root.Anchored = frozen end
end

return SpawnService
