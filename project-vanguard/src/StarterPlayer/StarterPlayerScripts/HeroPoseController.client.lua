--!strict
-- HeroPoseController: makes heroes visibly hold their weapon and aim it.
-- Hero bodies (attribute HeroBody, set by CharacterService) are rigged from the lobby statues, whose arms
-- are bound in the weapon-grip pose with the weapon in the mesh. Every frame, after the Animator runs, we:
--   * keep the arms in that grip (a little of the walk/run swing is kept so they don't look frozen)
--   * tilt the upper body + head with the aim pitch (own camera for you, AimPitch attribute for others)
-- Ability/emote/victory animations (Action priority or higher) take over the arms while they play.
-- Visual only, runs on every client for every hero in view. Also reports your own pitch to the server.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local AimPitch = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("AimPitch") :: UnreliableRemoteEvent

local ARM_JOINTS = {
	{ "RightUpperArm", "RightShoulder" }, { "RightLowerArm", "RightElbow" }, { "RightHand", "RightWrist" },
	{ "LeftUpperArm", "LeftShoulder" }, { "LeftLowerArm", "LeftElbow" }, { "LeftHand", "LeftWrist" },
}
local ARM_SWING_KEEP = 0.12 -- how much of the walk animation still moves the arms
local TORSO_SHARE, NECK_SHARE = 0.65, 0.35 -- how the aim pitch is split between waist and neck

-- Joints are Motor6Ds on classic rigs and AnimationConstraints on the newer avatar joint system;
-- both expose .Transform, which the Animator writes and we override afterwards.
type Joint = any
type Rig = {
	model: Model,
	arms: { Joint },
	waist: Joint?,
	neck: Joint?,
	animator: Animator?,
	nextResolve: number,
	pitch: number,
	actionUntil: number,
	nextActionCheck: number,
}
local rigs: { [Model]: Rig } = {}

local function joint(model: Model, partName: string, jointName: string): Joint?
	local part = model:FindFirstChild(partName)
	local j = part and part:FindFirstChild(jointName)
	if j and (j:IsA("Motor6D") or j:IsA("AnimationConstraint")) then return j end
	return nil
end

-- joints can replicate after the model, and are rebuilt when the body is swapped, so look them up lazily
local function resolve(rig: Rig)
	local model = rig.model
	local arms = {}
	for _, a in ipairs(ARM_JOINTS) do
		local j = joint(model, a[1], a[2])
		if j then table.insert(arms, j) end
	end
	rig.arms = arms
	rig.waist = joint(model, "UpperTorso", "Waist")
	rig.neck = joint(model, "Head", "Neck")
	local hum = model:FindFirstChildOfClass("Humanoid")
	rig.animator = hum and hum:FindFirstChildOfClass("Animator")
end
local function needsResolve(rig: Rig): boolean
	if #rig.arms < #ARM_JOINTS or not rig.waist or not rig.neck or not rig.animator then return true end
	if not rig.waist.Parent or not rig.neck.Parent then return true end
	for _, j in ipairs(rig.arms) do if not j.Parent then return true end end
	return false
end

local function track(model: Model)
	if rigs[model] or not model:GetAttribute("HeroBody") then return end
	local rig: Rig = { model = model, arms = {}, nextResolve = 0, pitch = 0, actionUntil = 0, nextActionCheck = 0 }
	resolve(rig)
	rigs[model] = rig
	model.AncestryChanged:Connect(function(_, parent)
		if not parent then rigs[model] = nil end
	end)
end

local watched: { [Model]: boolean } = {}
local function watch(model: Model)
	if watched[model] then return end
	watched[model] = true
	track(model)
	model:GetAttributeChangedSignal("HeroBody"):Connect(function() track(model) end)
	model.AncestryChanged:Connect(function(_, parent) if not parent then watched[model] = nil end end)
end
-- characters (players) and bots: anything in Workspace with a Humanoid
workspace.DescendantAdded:Connect(function(d)
	if d:IsA("Humanoid") and d.Parent and d.Parent:IsA("Model") then watch(d.Parent :: Model) end
end)
task.spawn(function()
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("Humanoid") and d.Parent and d.Parent:IsA("Model") then watch(d.Parent :: Model) end
	end
end)

local function ownPitch(): number
	local cam = workspace.CurrentCamera
	if not cam then return 0 end
	return math.asin(math.clamp(cam.CFrame.LookVector.Y, -1, 1))
end

RunService.PreSimulation:Connect(function(dt)
	local now = os.clock()
	local myChar = player.Character
	for model, rig in pairs(rigs) do
		if not model.Parent then rigs[model] = nil; continue end
		local hum = model:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 then continue end
		if now >= rig.nextResolve and needsResolve(rig) then
			rig.nextResolve = now + 0.5
			resolve(rig)
		end
		-- is an ability/emote animation using the arms right now?
		if now >= rig.nextActionCheck and rig.animator then
			rig.nextActionCheck = now + 0.15
			for _, t in ipairs((rig.animator :: Animator):GetPlayingAnimationTracks()) do
				if t.Priority.Value >= Enum.AnimationPriority.Action.Value and t.WeightCurrent > 0.3 then
					rig.actionUntil = now + 0.2
				end
			end
		end
		local target = if model == myChar then ownPitch() else ((model:GetAttribute("AimPitch") :: number?) or 0)
		rig.pitch += (target - rig.pitch) * math.min(1, dt * 14)
		if now < rig.actionUntil then continue end
		for _, m in ipairs(rig.arms) do
			m.Transform = CFrame.identity:Lerp(m.Transform, ARM_SWING_KEEP)
		end
		if rig.waist then rig.waist.Transform = CFrame.Angles(rig.pitch * TORSO_SHARE, 0, 0) end
		if rig.neck then rig.neck.Transform = CFrame.Angles(rig.pitch * NECK_SHARE, 0, 0) end
	end
end)

-- report my aim pitch ~10x a second while I'm a hero in a match
task.spawn(function()
	local last = 999
	while true do
		task.wait(0.1)
		local char = player.Character
		if char and char:GetAttribute("HeroBody") then
			local p = ownPitch()
			if math.abs(p - last) > 0.03 then
				last = p
				AimPitch:FireServer(p)
			end
		end
	end
end)
