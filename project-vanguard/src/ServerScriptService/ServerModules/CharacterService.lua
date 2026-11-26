--!strict
-- CharacterService: owns character spawning for the whole game.
--  * Roblox auto-respawn is OFF; we respawn with per-mode timers (GameConfig.Modes[*].RespawnTime).
--  * In a match: applies the selected hero's health/speed, attaches the weapon model, gives spawn protection.
--  * Hero selection is validated here (only unlocked heroes, only outside a live match).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local HeroConfig = require(ReplicatedStorage.Modules.HeroConfig)
local WeaponConfig = require(ReplicatedStorage.Modules.WeaponConfig)
local SkinConfig = require(ReplicatedStorage.Modules.SkinConfig)
local SkinVisuals = require(ReplicatedStorage.Modules.SkinVisuals)
local MatchManager = require(script.Parent.MatchManager)
local LobbyService = require(script.Parent.LobbyService)

local Remotes = ReplicatedStorage.Remotes
local SelectHero = Remotes.SelectHero :: RemoteEvent
local Notify = Remotes.Notify :: RemoteEvent

local CharacterService = {}
local applyHeroLook: (Model, string) -> ()
local spawnedCallbacks: { (Player, Model, boolean) -> () } = {}

-- fn(player, character, inMatch) runs after the character is fully set up
function CharacterService.OnSpawned(fn: (Player, Model, boolean) -> ())
	table.insert(spawnedCallbacks, fn)
end

function CharacterService.GetHeroId(player: Player): string
	local id = player:GetAttribute("Hero")
	if typeof(id) == "string" and HeroConfig.Heroes[id] then return id end
	return HeroConfig.StarterHeroes[1]
end

-- ForgeGUI-generated 3D assets live in ReplicatedStorage.HeroAssets (Weapons / Helmets / Statues).
-- Each model's PivotOffset is its mount point (weapon grip / helmet centre), with -Z = forward.
local HeroAssets = ReplicatedStorage:FindFirstChild("HeroAssets")

local function weldModel(template: Model, anchorPart: BasePart, offset: CFrame, name: string, parent: Instance, skinId: string?)
	local clone = template:Clone()
	clone.Name = name
	SkinVisuals.Apply(clone, skinId) -- cosmetic only; no-op for the default look
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false; d.CanCollide = false; d.CanQuery = false; d.CanTouch = false; d.Massless = true
		end
	end
	clone:PivotTo(anchorPart.CFrame * offset)
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BasePart") then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = anchorPart; weld.Part1 = d; weld.Parent = d
		end
	end
	clone.Parent = parent
	return clone
end

-- Where each weapon is held. Blades are dual-wielded; the gauntlet sits on the forearm.
local WEAPON_MOUNTS = {
	EnergyBlades = { { "RightHand", CFrame.new(0, -0.2, 0) }, { "LeftHand", CFrame.new(0, -0.2, 0) } },
	LightningGauntlet = { { "RightLowerArm", CFrame.new(0, 0, 0) } },
}
local DEFAULT_MOUNT = { { "RightHand", CFrame.new(0, -0.15, -0.2) } }

local function buildWorldWeapon(character: Model, weaponId: string, skinId: string?)
	local w = WeaponConfig.Weapons[weaponId]
	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	if not w or not hand or not hand:IsA("BasePart") then return end
	for _, c in ipairs(character:GetChildren()) do
		if c.Name == "WeaponModel" then c:Destroy() end
	end

	local template = HeroAssets and HeroAssets.Weapons:FindFirstChild(weaponId)
	if template then
		for _, mount in ipairs(WEAPON_MOUNTS[weaponId] or DEFAULT_MOUNT) do
			local part = character:FindFirstChild(mount[1])
			if part and part:IsA("BasePart") then
				weldModel(template :: Model, part, mount[2], "WeaponModel", character, skinId)
			end
		end
		return
	end
	-- fallback: simple block weapon (used only if a 3D model is missing)

	local model = Instance.new("Model")
	model.Name = "WeaponModel"
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = w.ViewSize
	body.Color = Color3.fromRGB(35, 38, 48)
	body.Material = Enum.Material.Metal
	body.CanCollide = false; body.CanQuery = false; body.CanTouch = false; body.Massless = true
	body.CFrame = hand.CFrame * CFrame.new(0, -0.15, -w.ViewSize.Z / 2 + 0.3)
	body.Parent = model
	local glow = Instance.new("Part")
	glow.Name = "Glow"
	glow.Size = Vector3.new(w.ViewSize.X + 0.05, 0.12, w.ViewSize.Z * 0.7)
	glow.Color = w.Color
	glow.Material = Enum.Material.Neon
	glow.CanCollide = false; glow.CanQuery = false; glow.CanTouch = false; glow.Massless = true
	glow.CFrame = body.CFrame * CFrame.new(0, w.ViewSize.Y / 2, 0)
	glow.Parent = model
	for _, p in ipairs({ body, glow }) do
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = hand; weld.Part1 = p; weld.Parent = p
	end
	model.Parent = character
end

-- In matches players look like their hero: avatar hats/clothes come off, the body takes the hero's
-- colours, and the hero's ForgeGUI helmet goes on the head. Faces and animations are kept.
local BODY_DARK = Color3.fromRGB(32, 34, 44)
function applyHeroLook(character: Model, heroId: string)
	local hero = HeroConfig.Heroes[heroId]
	for _, c in ipairs(character:GetChildren()) do
		if c:IsA("Accessory") or c:IsA("Shirt") or c:IsA("Pants") or c:IsA("ShirtGraphic") then c:Destroy() end
	end
	local accent = hero.Color
	for _, part in ipairs(character:GetChildren()) do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			local n = part.Name
			if n:find("Arm") or n:find("Hand") then
				part.Color = accent
			elseif n == "Head" then
				part.Color = Color3.fromRGB(205, 165, 130)
			else
				part.Color = BODY_DARK
			end
		end
	end
	local bc = character:FindFirstChildOfClass("BodyColors")
	if bc then bc:Destroy() end -- stop BodyColors from overriding the hero colours
	local head = character:FindFirstChild("Head")
	local helmet = HeroAssets and HeroAssets.Helmets:FindFirstChild(heroId)
	if head and head:IsA("BasePart") and helmet then
		weldModel(helmet :: Model, head, CFrame.new(0, 0.2, 0), "HeroHelmet", character)
	end
end

-- Hero bodies: each lobby statue rigged as an R15 body (ReplicatedStorage.HeroAssets.Bodies.<HeroId>,
-- built by tools/build_hero_bodies.lua, pre-scaled by role). The statue's own weapon is part of the body
-- mesh and its arms are rigged in the grip pose, so the hero is visibly holding their weapon; the client
-- HeroPoseController keeps the arms in that grip and tilts the upper body with the player's aim.
local BODY_PARTS = {
	Head = Enum.BodyPartR15.Head, UpperTorso = Enum.BodyPartR15.UpperTorso, LowerTorso = Enum.BodyPartR15.LowerTorso,
	LeftUpperArm = Enum.BodyPartR15.LeftUpperArm, LeftLowerArm = Enum.BodyPartR15.LeftLowerArm, LeftHand = Enum.BodyPartR15.LeftHand,
	RightUpperArm = Enum.BodyPartR15.RightUpperArm, RightLowerArm = Enum.BodyPartR15.RightLowerArm, RightHand = Enum.BodyPartR15.RightHand,
	LeftUpperLeg = Enum.BodyPartR15.LeftUpperLeg, LeftLowerLeg = Enum.BodyPartR15.LeftLowerLeg, LeftFoot = Enum.BodyPartR15.LeftFoot,
	RightUpperLeg = Enum.BodyPartR15.RightUpperLeg, RightLowerLeg = Enum.BodyPartR15.RightLowerLeg, RightFoot = Enum.BodyPartR15.RightFoot,
}
local function applyHeroBody(character: Model, heroId: string): boolean
	local bodies = HeroAssets and HeroAssets:FindFirstChild("Bodies")
	local template = bodies and bodies:FindFirstChild(heroId) :: Model?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not template or not humanoid or humanoid.RigType ~= Enum.HumanoidRigType.R15 then return false end
	local tHum = template:FindFirstChildOfClass("Humanoid")
	humanoid.AutomaticScalingEnabled = false -- the template is already the right size
	for _, c in ipairs(character:GetChildren()) do
		if c:IsA("Accessory") or c:IsA("Clothing") or c:IsA("ShirtGraphic") or c:IsA("BodyColors") or c:IsA("CharacterMesh") then
			c:Destroy()
		end
	end
	local clone = template:Clone()
	local ok = true
	for name, enum in pairs(BODY_PARTS) do
		local part = clone:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			for _, j in ipairs(part:GetChildren()) do if j:IsA("JointInstance") then j:Destroy() end end
			part.Anchored = false
			part.Parent = nil
			local replaced = pcall(function() humanoid:ReplaceBodyPartR15(enum, part) end)
			ok = ok and replaced
		end
	end
	-- match the root part to the template so the feet sit on the ground at the template's hip height
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local tRoot = clone:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root and tRoot then
		root.Size = tRoot.Size
		local a, ta = root:FindFirstChild("RootRigAttachment") :: Attachment?, tRoot:FindFirstChild("RootRigAttachment") :: Attachment?
		if a and ta then a.CFrame = ta.CFrame end
	end
	clone:Destroy()
	if tHum then humanoid.HipHeight = tHum.HipHeight end
	humanoid:BuildRigFromAttachments()
	character:SetAttribute("HeroBody", heroId)
	return ok
end

-- Phase 9: bots wear the same hero look + weapon model as players (default skins).
function CharacterService.DressAsHero(model: Model, heroId: string)
	local hero = HeroConfig.Heroes[heroId]
	if not hero then return end
	if not applyHeroBody(model, heroId) then
		applyHeroLook(model, heroId)
		buildWorldWeapon(model, hero.WeaponId, nil)
	end
end

local function setupCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid then return end
	local match = MatchManager.GetMatch(player)
	local inMatch = match ~= nil and match.State ~= "Ended"

	if inMatch then
		local heroId = CharacterService.GetHeroId(player)
		local hero = HeroConfig.Heroes[heroId]
		humanoid.MaxHealth = hero.Stats.Health
		humanoid.Health = hero.Stats.Health
		humanoid.WalkSpeed = hero.Stats.WalkSpeed
		player:SetAttribute("WeaponId", hero.WeaponId)
		character:WaitForChild("RightHand", 5)
		if not applyHeroBody(character, heroId) then -- fallback: recoloured avatar + helmet + welded weapon
			applyHeroLook(character, heroId)
			buildWorldWeapon(character, hero.WeaponId, SkinConfig.EquippedFor(player, hero.WeaponId))
		end
		local ff = Instance.new("ForceField")
		ff.Visible = true
		ff.Parent = character
		task.delay(GameConfig.Combat.SpawnProtection, function()
			if ff.Parent then ff:Destroy() end
		end)
	else
		humanoid.MaxHealth = 100
		humanoid.Health = 100
		humanoid.WalkSpeed = 16
		player:SetAttribute("WeaponId", nil)
	end

	humanoid.BreakJointsOnDeath = true
	humanoid.Died:Connect(function()
		local delayTime = MatchManager.GetRespawnTime(player)
		player:SetAttribute("RespawnAt", workspace:GetServerTimeNow() + delayTime)
		task.delay(delayTime, function()
			-- Only respawn if nothing else (e.g. match end) already gave them a new character.
			if player.Parent == Players and player.Character == character then
				player:LoadCharacter()
			end
		end)
	end)

	for _, fn in ipairs(spawnedCallbacks) do
		task.spawn(fn, player, character, inMatch)
	end
end

function CharacterService.Init()
	Players.CharacterAutoLoads = false

	local function onPlayer(player: Player)
		player:SetAttribute("Hero", LobbyService.GetProfile(player).SelectedHero)
		player.CharacterAdded:Connect(function(character)
			player:SetAttribute("RespawnAt", nil)
			setupCharacter(player, character)
		end)
		if not player.Character then player:LoadCharacter() end
	end
	for _, p in ipairs(Players:GetPlayers()) do task.spawn(onPlayer, p) end
	Players.PlayerAdded:Connect(onPlayer)

	-- Aim pitch: each client reports where it is looking up/down (~10x a second) so everyone else can see
	-- the hero aim. Visual only; clamped and rate-limited, stored on the character for HeroPoseController.
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local aimEvent = remotes:FindFirstChild("AimPitch") :: UnreliableRemoteEvent?
	if not aimEvent then
		local r = Instance.new("UnreliableRemoteEvent")
		r.Name = "AimPitch"
		r.Parent = remotes
		aimEvent = r
	end
	assert(aimEvent)
	local lastAim: { [Player]: number } = {}
	aimEvent.OnServerEvent:Connect(function(player: Player, pitch: any)
		if typeof(pitch) ~= "number" or pitch ~= pitch then return end
		local now = os.clock()
		if lastAim[player] and now - lastAim[player] < 0.05 then return end
		lastAim[player] = now
		local char = player.Character
		if char then char:SetAttribute("AimPitch", math.clamp(pitch, -1.3, 1.3)) end
	end)
	Players.PlayerRemoving:Connect(function(p) lastAim[p] = nil end)

	SelectHero.OnServerEvent:Connect(function(player: Player, heroId: any)
		if typeof(heroId) ~= "string" or not HeroConfig.Heroes[heroId] then return end
		if MatchManager.IsInMatch(player) then
			Notify:FireClient(player, "Hero changes are locked during a match.")
			return
		end
		local profile = LobbyService.GetProfile(player)
		if not table.find(profile.UnlockedHeroes, heroId) then
			Notify:FireClient(player, "You haven't unlocked that hero yet.")
			return
		end
		player:SetAttribute("Hero", heroId)
	end)
end

return CharacterService
