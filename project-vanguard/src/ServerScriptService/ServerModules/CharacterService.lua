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

local function weldModel(template: Model, anchorPart: BasePart, offset: CFrame, name: string, parent: Instance)
	local clone = template:Clone()
	clone.Name = name
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

local function buildWorldWeapon(character: Model, weaponId: string)
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
				weldModel(template :: Model, part, mount[2], "WeaponModel", character)
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
		applyHeroLook(character, heroId)
		buildWorldWeapon(character, hero.WeaponId)
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
