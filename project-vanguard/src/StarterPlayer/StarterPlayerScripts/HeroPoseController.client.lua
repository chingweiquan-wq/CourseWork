--!strict
-- HeroPoseController: makes heroes visibly hold their weapon and aim it.
-- Hero bodies (attribute HeroBody, set by CharacterService) are rigged from the lobby statues, whose arms
-- are bound in the weapon-grip pose with the weapon in the mesh. Every frame, after the Animator runs, we:
--   * keep the arms in that grip (a little of the walk/run swing is kept so they don't look frozen)
--   * tilt the upper body + head with the aim pitch (own camera for you, AimPitch attribute for others)
-- Ability/emote/victory animations (Action priority or higher) take over the arms while they play.
-- Weapon holds: each hero's arms are driven by IK (IKControl) into that hero's own carry pose while
-- idle/running, and snap up into a firing pose when they shoot or aim (HoldConfig has every style).
-- Also:
--   * firing kick: when a hero shoots, their upper body and arms jolt by the weapon's weight (melee = twist)
--   * size feel: footsteps sound heavier on big heroes and lighter on small ones, tanks land with a thud
--     ring (+ a small camera shake for you), and your first-person camera sits at your hero's eye height
-- Visual only, runs on every client for every hero in view. Also reports your own pitch to the server.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local AimPitch = Remotes:WaitForChild("AimPitch") :: UnreliableRemoteEvent
local CombatFx = Remotes:WaitForChild("CombatFx") :: RemoteEvent
local HoldConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("HoldConfig"))

local ARM_JOINTS = {
	{ "RightUpperArm", "RightShoulder" }, { "RightLowerArm", "RightElbow" }, { "RightHand", "RightWrist" },
	{ "LeftUpperArm", "LeftShoulder" }, { "LeftLowerArm", "LeftElbow" }, { "LeftHand", "LeftWrist" },
}
local ARM_SWING_KEEP = 0.12 -- how much of the walk animation still moves the arms
local TORSO_SHARE, NECK_SHARE = 0.65, 0.35 -- how the aim pitch is split between waist and neck

-- firing kick per weapon (radians of upper-body jolt); melee weapons twist instead
local KICK = {
	PrecisionRifle = 0.32, HeavyCannon = 0.3, Scattergun = 0.28, RivetGun = 0.16, LightningGauntlet = 0.14,
	BurstRifle = 0.09, PulseSMG = 0.06, MedicalProjector = 0.04, EnergyBlades = 0.35,
}
local MELEE = { EnergyBlades = true }
-- ability/emote/victory tracks take the arms over; NOT Core (walk/run), whose enum value is higher than Action
local ACTION_PRIORITY = {
	[Enum.AnimationPriority.Action] = true, [Enum.AnimationPriority.Action2] = true,
	[Enum.AnimationPriority.Action3] = true, [Enum.AnimationPriority.Action4] = true,
}
local KICK_MAX, KICK_RECOVER = 0.45, 11 -- cap, and how fast it settles (per second)
local BASE_HEIGHT = 5.6 -- standard hero height; bigger/smaller heroes sound and land heavier/lighter

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
	shoulders: { Joint },
	kick: number,
	melee: boolean,
	height: number,
	pitch: number,
	actionUntil: number,
	nextActionCheck: number,
	hold: HoldConfig.Hold?,
	ikR: IKControl?,
	ikL: IKControl?,
	rTarget: Attachment?,
	lTarget: Attachment?,
	raise: number,
	lastShot: number,
	limits: { BallSocketConstraint }?, -- arm joint limits switched off while IK holds the weapon
	leftRel: CFrame?, -- two-handed: support grip relative to the right grip (constant)
	leftShoulder: Vector3?, -- torso space
	leftReach: number?,
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
	rig.shoulders = {}
	for _, n in ipairs({ "RightShoulder", "LeftShoulder" }) do
		local j = joint(model, n == "RightShoulder" and "RightUpperArm" or "LeftUpperArm", n)
		if j then table.insert(rig.shoulders, j) end
	end
end
local function needsResolve(rig: Rig): boolean
	if #rig.arms < #ARM_JOINTS or not rig.waist or not rig.neck or not rig.animator then return true end
	if not rig.waist.Parent or not rig.neck.Parent then return true end
	for _, j in ipairs(rig.arms) do if not j.Parent then return true end end
	return false
end

local setupSizeFeel: (Rig) -> ()
local function track(model: Model)
	if rigs[model] or not model:GetAttribute("HeroBody") then return end
	local rig: Rig = { model = model, arms = {}, shoulders = {}, nextResolve = 0, pitch = 0, actionUntil = 0, nextActionCheck = 0, kick = 0, melee = false, height = model:GetExtentsSize().Y,
		hold = HoldConfig.Get(model:GetAttribute("HeroBody") :: string?), raise = 0, lastShot = -99 }
	resolve(rig)
	rigs[model] = rig
	task.spawn(setupSizeFeel, rig)
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
task.defer(function() -- deferred: runs after the whole script (and setupSizeFeel) has loaded
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("Humanoid") and d.Parent and d.Parent:IsA("Model") then watch(d.Parent :: Model) end
	end
end)



---------------------------------------------------------------- weapon holds (IK)
-- Local-only IK rig per hero: targets live on the UpperTorso so the hold moves with the body.
local IK_NAMES = { "VG_IK_R", "VG_IK_L" }
local ATT_NAMES = { "VG_RTarget", "VG_LTarget", "VG_RPole", "VG_LPole" }
local function ikReady(rig: Rig): boolean
	return rig.ikR ~= nil and (rig.ikR :: IKControl).Parent ~= nil and rig.rTarget ~= nil and (rig.rTarget :: Attachment).Parent ~= nil
end
local function setupIK(rig: Rig)
	local model, hold = rig.model, rig.hold
	local hum = model:FindFirstChildOfClass("Humanoid")
	local torso = model:FindFirstChild("UpperTorso") :: BasePart?
	local rua, lua_ = model:FindFirstChild("RightUpperArm"), model:FindFirstChild("LeftUpperArm")
	local rh, lh = model:FindFirstChild("RightHand") :: BasePart?, model:FindFirstChild("LeftHand") :: BasePart?
	if not (hold and hum and torso and rua and lua_ and rh and lh and hum:FindFirstChildOfClass("Animator")) then return end
	for _, n in ipairs(IK_NAMES) do local o = hum:FindFirstChild(n); if o then o:Destroy() end end
	for _, n in ipairs(ATT_NAMES) do local o = torso:FindFirstChild(n); if o then o:Destroy() end end
	local s = rig.height / HoldConfig.BASE_HEIGHT
	local function att(name: string, pos: Vector3): Attachment
		local a = Instance.new("Attachment")
		a.Name = name
		a.Position = pos
		a.Parent = torso
		return a
	end
	local rT, lT = att("VG_RTarget", Vector3.zero), att("VG_LTarget", Vector3.zero)
	local rP, lP = att("VG_RPole", Vector3.new(1.7, -1.7, 0.9) * s), att("VG_LPole", Vector3.new(-1.7, -1.7, 0.9) * s)

	local rla = model:FindFirstChild("RightLowerArm")
	local grip = rh:FindFirstChild("VG_GunGrip") or (rla and rla:FindFirstChild("VG_GunGrip")) -- forearm weapons (Forge) grip on the forearm
	local ikR = Instance.new("IKControl")
	ikR.Name = "VG_IK_R"
	ikR.ChainRoot = rua
	if hold.Kind == "Gun" and grip then
		ikR.Type = Enum.IKControlType.Transform
		ikR.EndEffector = grip
	else
		ikR.Type = Enum.IKControlType.Position
		ikR.EndEffector = rh
	end
	ikR.Target = rT
	ikR.Pole = rP
	ikR.Priority = 2
	ikR.SmoothTime = 0
	ikR.Parent = hum

	local ikL = Instance.new("IKControl")
	ikL.Name = "VG_IK_L"
	ikL.ChainRoot = lua_
	ikL.EndEffector = lh
	local keep = rh:FindFirstChild("VG_LeftHold")
	if hold.Left == "Keep" and keep then
		ikL.Type = Enum.IKControlType.Transform -- the left hand rides on the weapon exactly where the statue held it
		ikL.Target = keep
	else
		ikL.Type = Enum.IKControlType.Position
		ikL.Target = lT
	end
	ikL.Pole = lP
	ikL.Priority = 1
	ikL.SmoothTime = 0
	ikL.Parent = hum

	local sparkHand = hold.Sparks and model:FindFirstChild(hold.Sparks)
	if sparkHand and not sparkHand:FindFirstChild("VG_Sparks") then
		local a = Instance.new("Attachment")
		a.Name = "VG_Sparks"
		a.Parent = sparkHand
		local pe = Instance.new("ParticleEmitter")
		pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		pe.Color = ColorSequence.new(Color3.fromRGB(120, 220, 255), Color3.fromRGB(255, 255, 255))
		pe.LightEmission = 1
		pe.Rate = 18
		pe.Lifetime = NumberRange.new(0.15, 0.3)
		pe.Speed = NumberRange.new(2, 4)
		pe.SpreadAngle = Vector2.new(180, 180)
		pe.Size = NumberSequence.new(0.18, 0)
		pe.Parent = a
	end
	rig.ikR, rig.ikL, rig.rTarget, rig.lTarget = ikR, ikL, rT, lT
	-- two-handed reach: remember where the support grip sits relative to the right grip, and how far the left
	-- arm reaches, so the weapon can be slid into reach every frame (otherwise the left hand falls off it)
	rig.leftRel, rig.leftShoulder, rig.leftReach = nil, nil, nil
	if grip and grip:IsA("Attachment") and keep and keep:IsA("Attachment") and hold.Left == "Keep" and grip.Parent == rh then
		local sh = torso:FindFirstChild("LeftShoulderRigAttachment") :: Attachment?
		local luaElbow = lua_:FindFirstChild("LeftElbowRigAttachment") :: Attachment?
		local lla = model:FindFirstChild("LeftLowerArm")
		local llaElbow = lla and lla:FindFirstChild("LeftElbowRigAttachment") :: Attachment?
		local llaWrist = lla and lla:FindFirstChild("LeftWristRigAttachment") :: Attachment?
		local lhWrist = lh:FindFirstChild("LeftWristRigAttachment") :: Attachment?
		local shU = lua_:FindFirstChild("LeftShoulderRigAttachment") :: Attachment?
		if sh and luaElbow and llaElbow and llaWrist and lhWrist and shU then
			rig.leftRel = (grip :: Attachment).CFrame:Inverse() * (keep :: Attachment).CFrame
			rig.leftShoulder = sh.Position
			rig.leftReach = (luaElbow.Position - shU.Position).Magnitude + (llaWrist.Position - llaElbow.Position).Magnitude + lhWrist.Position.Magnitude
		end
	end
	-- The statue bodies carry ragdoll joint limits measured from the statue pose (wrist +-30 deg, elbow 20 deg);
	-- IK respects them, which stops the arms reaching a proper hold. Switch them off locally while alive.
	local limits = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BallSocketConstraint") and d.Parent and (d.Parent.Name:find("Arm") or d.Parent.Name:find("Hand")) and d.LimitsEnabled then
			d.LimitsEnabled = false
			d.TwistLimitsEnabled = false
			table.insert(limits, d)
		end
	end
	rig.limits = limits
end
local function restoreLimits(rig: Rig) -- back on for the death ragdoll
	if not rig.limits then return end
	for _, d in ipairs(rig.limits :: { BallSocketConstraint }) do
		if d.Parent then d.LimitsEnabled = true; d.TwistLimitsEnabled = true end
	end
	rig.limits = nil
end

local function poseCF(p: HoldConfig.Pose, s: number): CFrame
	return CFrame.new(p.Pos * s) * CFrame.Angles(0, math.rad(p.Yaw), 0) * CFrame.Angles(math.rad(p.Pitch), 0, 0) * CFrame.Angles(0, 0, math.rad(p.Roll))
end

-- runs before the Animator solves IK each frame
RunService.PreAnimation:Connect(function(dt)
	local now = os.clock()
	for model, rig in pairs(rigs) do
		local hold = rig.hold
		if not hold or not model.Parent then continue end
		if not ikReady(rig) then
			if now >= rig.nextResolve then setupIK(rig) end
			if not ikReady(rig) then continue end
		end
		local hum = model:FindFirstChildOfClass("Humanoid")
		local alive = hum ~= nil and hum.Health > 0
		if not alive then restoreLimits(rig) end
		local active = alive and now >= rig.actionUntil
		;(rig.ikR :: IKControl).Enabled = active
		;(rig.ikL :: IKControl).Enabled = active
		if not active then continue end

		local owner = Players:GetPlayerFromCharacter(model)
		local aiming = owner ~= nil and owner:GetAttribute("Aiming") == true
		local want = (aiming or now - rig.lastShot < HoldConfig.LOWER_DELAY) and 1 or 0
		rig.raise += (want - rig.raise) * math.min(1, dt * HoldConfig.RAISE_SPEED)

		local s = rig.height / HoldConfig.BASE_HEIGHT
		local target = poseCF(hold.Carry, s):Lerp(poseCF(hold.Fire, s), rig.raise)
		-- running bob (less when raised)
		local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
		local v = root and root.AssemblyLinearVelocity or Vector3.zero
		local moving = math.clamp(Vector3.new(v.X, 0, v.Z).Magnitude / 16, 0, 1.3)
		local bob = (hold.Bob or 0.05) * s * moving * (1 - rig.raise * 0.7)
		local phase = now * 11
		local bobOffset = Vector3.new(math.sin(phase) * bob * 0.5, math.abs(math.sin(phase)) * bob, 0)
		target = target + bobOffset
		-- follow the aim: the torso already takes TORSO_SHARE of the pitch, the arms take the rest
		local pivot = Vector3.new(0.6, 0.45, 0) * s
		local extra = rig.pitch * (1 - TORSO_SHARE)
		target = CFrame.new(pivot) * CFrame.Angles(extra, 0, 0) * CFrame.new(-pivot) * target
		-- firing kick: the weapon jumps back and up
		if rig.kick > 0.005 and hold.Kind == "Gun" then
			target = target * CFrame.new(0, 0, rig.kick * 0.6) * CFrame.Angles(rig.kick * 0.8, 0, 0)
		end
		if hold.GripFix then -- per-hero correction between the grip frame and the sculpted weapon
			local g = hold.GripFix :: Vector3
			target = target * CFrame.Angles(0, math.rad(g.Y), 0) * CFrame.Angles(math.rad(g.X), 0, 0) * CFrame.Angles(0, 0, math.rad(g.Z))
		end
		-- two-handed: slide the weapon toward the left shoulder until the support grip is within the left arm's reach
		if rig.leftRel and rig.leftShoulder and rig.leftReach then
			local leftPos = (target * (rig.leftRel :: CFrame)).Position
			local d = leftPos - (rig.leftShoulder :: Vector3)
			local limit = (rig.leftReach :: number) * 0.92
			if d.Magnitude > limit then
				target = target - d.Unit * (d.Magnitude - limit)
			end
		end
		;(rig.rTarget :: Attachment).CFrame = target
		if rig.lTarget and hold.LeftCarry then
			local l = hold.LeftCarry:Lerp(hold.LeftFire or hold.LeftCarry, rig.raise) * s
			;(rig.lTarget :: Attachment).CFrame = CFrame.new(l + bobOffset * 0.6)
		end
	end
end)

---------------------------------------------------------------- size feel
-- footsteps: deeper + louder for big heroes, lighter + quieter for small ones (Roblox's own "Running" sound)
local function tuneFootsteps(rig: Rig)
	local root = rig.model:FindFirstChild("HumanoidRootPart")
	local running = root and root:FindFirstChild("Running")
	if not running or not running:IsA("Sound") then return false end
	if running:FindFirstChild("HeroStep") then return true end
	local size = rig.height / BASE_HEIGHT
	local pitch = Instance.new("PitchShiftSoundEffect")
	pitch.Name = "HeroStep"
	pitch.Octave = math.clamp(1 / size ^ 1.4, 0.75, 1.25)
	pitch.Parent = running
	if size > 1.08 then
		local eq = Instance.new("EqualizerSoundEffect")
		eq.Name = "HeroStepBass"
		eq.LowGain = 7; eq.MidGain = 0; eq.HighGain = -6
		eq.Parent = running
	end
	running.Volume = math.clamp(running.Volume * size ^ 2.5, 0.2, 1.2)
	return true
end

-- heavy landing: a dust ring at the feet for big heroes (everyone sees it) + a small shake for yourself
local function landingRing(at: Vector3, radius: number)
	local p = Instance.new("Part")
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.CastShadow = false
	p.Shape = Enum.PartType.Cylinder
	p.Material = Enum.Material.Neon
	p.Color = Color3.fromRGB(200, 220, 255)
	p.Transparency = 0.4
	p.Size = Vector3.new(0.15, 1, 1)
	p.CFrame = CFrame.new(at) * CFrame.Angles(0, 0, math.pi / 2)
	p.Parent = workspace
	TweenService:Create(p, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.05, radius * 2, radius * 2), Transparency = 1 }):Play()
	Debris:AddItem(p, 0.5)
end
local shakeLeft, shakeAmp = 0, 0
RunService:BindToRenderStep("VG_LandShake", Enum.RenderPriority.Camera.Value + 3, function(dt)
	if shakeLeft <= 0 then return end
	shakeLeft -= dt
	local a = shakeAmp * math.max(shakeLeft, 0) / 0.25
	local cam = workspace.CurrentCamera
	cam.CFrame = cam.CFrame * CFrame.new((math.random() - 0.5) * a, (math.random() - 0.5) * a, 0)
end)

function setupSizeFeel(rig: Rig)
	local model = rig.model
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	task.wait(0.3) -- let every body part arrive before measuring
	if not model.Parent then return end
	rig.height = model:GetExtentsSize().Y
	-- footsteps (the sound is created a moment after spawn)
	for _ = 1, 20 do
		if not model.Parent or tuneFootsteps(rig) then break end
		task.wait(0.25)
	end
	-- tanks land heavy
	if rig.height / BASE_HEIGHT > 1.08 then
		local fallSpeed = 0
		hum.StateChanged:Connect(function(_, new)
			local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not root then return end
			if new == Enum.HumanoidStateType.Freefall then
				fallSpeed = 0
			elseif new == Enum.HumanoidStateType.Landed and fallSpeed > 22 then
				landingRing(root.Position - Vector3.new(0, hum.HipHeight + root.Size.Y / 2 - 0.1, 0), math.clamp(fallSpeed / 5, 5, 10))
				if model == player.Character then
					shakeLeft, shakeAmp = 0.25, math.clamp(fallSpeed / 120, 0.12, 0.35)
				end
			end
		end)
		local hb: RBXScriptConnection
		hb = RunService.Heartbeat:Connect(function()
			if not model.Parent then hb:Disconnect() return end
			local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root and hum:GetState() == Enum.HumanoidStateType.Freefall then
				fallSpeed = math.max(fallSpeed, -root.AssemblyLinearVelocity.Y)
			end
		end)
	end
	-- your own first-person camera at your hero's eye height (Roblox puts it 2 studs above the root part
	-- for unscaled R15 bodies, which is too low for Titan and too high for Shade)
	if model == player.Character then
		task.wait(0.2)
		local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
		local head = model:FindFirstChild("Head") :: BasePart?
		if root and head and model.Parent then
			local eye = root.CFrame:PointToObjectSpace(head.Position).Y + head.Size.Y * 0.12
			hum.CameraOffset = Vector3.new(0, eye - 2, 0)
		end
	end
end

---------------------------------------------------------------- firing kick (other players + bots)
local function rigNear(pos: Vector3): Rig?
	local best, bestD = nil, 6
	for _, rig in pairs(rigs) do
		local root = rig.model:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local d = (root.Position - pos).Magnitude
			if d < bestD then best, bestD = rig, d end
		end
	end
	return best
end
CombatFx.OnClientEvent:Connect(function(data)
	if typeof(data) ~= "table" then return end
	if data.Type ~= "Shot" and data.Type ~= "Projectile" and data.Type ~= "Melee" then return end
	if data.Shooter == player.UserId then return end -- you are in first person; your viewmodel already kicks
	local amount = KICK[data.Weapon]
	if not amount then return end
	local rig: Rig? = nil
	local shooter = typeof(data.Shooter) == "number" and data.Shooter > 0 and Players:GetPlayerByUserId(data.Shooter) or nil
	if shooter and shooter.Character then rig = rigs[shooter.Character] end
	if not rig and typeof(data.From) == "Vector3" then rig = rigNear(data.From) end -- bots
	if rig then
		rig.melee = MELEE[data.Weapon] == true
		rig.kick = math.min(rig.kick + amount, KICK_MAX)
		rig.lastShot = os.clock() -- raises the weapon into the firing pose
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
				if ACTION_PRIORITY[t.Priority] and t.WeightCurrent > 0.3 then
					rig.actionUntil = now + 0.2
				end
			end
		end
		local target = if model == myChar then ownPitch() else ((model:GetAttribute("AimPitch") :: number?) or 0)
		rig.pitch += (target - rig.pitch) * math.min(1, dt * 14)
		rig.kick *= math.exp(-dt * KICK_RECOVER)
		if now < rig.actionUntil then continue end
		local usesIK = rig.hold ~= nil and ikReady(rig)
		if not usesIK then -- no hold style: keep the statue's arm pose (IK rigs are posed by the IK instead)
			for _, m in ipairs(rig.arms) do
				m.Transform = CFrame.identity:Lerp(m.Transform, ARM_SWING_KEEP)
			end
		end
		local k = rig.kick
		if k > 0.005 and not rig.melee and not usesIK then
			for _, sh in ipairs(rig.shoulders) do sh.Transform = CFrame.Angles(k * 0.9, 0, 0) * sh.Transform end -- gun rises
		end
		if rig.waist then
			local lean = rig.hold and math.rad(rig.hold.Lean or 0) * (1 - rig.raise * 0.5) or 0
			local waist = CFrame.Angles(rig.pitch * TORSO_SHARE - lean, 0, 0)
			if k > 0.005 then
				waist = if rig.melee then waist * CFrame.Angles(-k * 0.3, k, 0) else waist * CFrame.Angles(k * 0.6, 0, 0)
			end
			rig.waist.Transform = waist
		end
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
