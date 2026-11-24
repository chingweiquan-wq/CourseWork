-- AnimationController (Phase 7): character animations.
--  * Skill cast / Ultimate: played only after the server ACCEPTS the ability (Ready_Skill moves into the
--    future, or the server's UltCast effect names us), so a spammed key never animates a rejected cast.
--  * Results screen: the camera swings round to face your hero, who plays a victory or defeat animation.
--  * Lobby: press G to salute.
-- Animations played on your own character replicate to everyone else through the Animator.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local Modules = ReplicatedStorage:WaitForChild("Modules")
local AudioConfig = require(Modules:WaitForChild("AudioConfig"))
local Sfx = require(Modules:WaitForChild("Sfx"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local MatchState = Remotes:WaitForChild("MatchState")
local AbilityFx = Remotes:WaitForChild("AbilityFx")

local EMOTE_KEY = require(Modules:WaitForChild("ControlConfig")).Binds.Emote
local tracks: { [string]: AnimationTrack } = {}

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function load(char: Model)
	table.clear(tracks)
	local hum = char:WaitForChild("Humanoid", 10) :: Humanoid?
	if not hum then return end
	local animator = hum:FindFirstChildOfClass("Animator") or hum:WaitForChild("Animator", 5)
	if not animator or not animator:IsA("Animator") then return end
	if hum.RigType ~= Enum.HumanoidRigType.R15 then return end -- the generated clips are R15
	for name, id in pairs(AudioConfig.Animations) do
		local a = Instance.new("Animation")
		a.AnimationId = id
		local ok, track = pcall(function() return animator:LoadAnimation(a) end)
		if ok and track then
			track.Priority = (name == "Victory" or name == "Defeat" or name == "Emote") and Enum.AnimationPriority.Action2 or Enum.AnimationPriority.Action
			track.Looped = false
			tracks[name] = track
		end
	end
end

local function play(name: string, fade: number?, speed: number?)
	local t = tracks[name]
	if not t then return end
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return end
	for n, other in pairs(tracks) do if n ~= name and other.IsPlaying then other:Stop(0.1) end end
	t:Play(fade or 0.1, 1, speed or 1)
end

if player.Character then task.spawn(load, player.Character) end
player.CharacterAdded:Connect(load)

---------------------------------------------------------------- abilities (server-confirmed)
player:GetAttributeChangedSignal("Ready_Skill"):Connect(function()
	local readyAt = player:GetAttribute("Ready_Skill")
	if typeof(readyAt) == "number" and readyAt > serverNow() + 0.2 then
		play("Cast", 0.05, 1.3)
		Sfx.Play("Cast")
	end
end)
AbilityFx.OnClientEvent:Connect(function(data)
	if typeof(data) == "table" and data.Type == "UltCast" and data.Owner == player.UserId then play("Ultimate", 0.05, 1.2) end
end)

---------------------------------------------------------------- results pose + camera
local posing = false
local orbitConn: RBXScriptConnection? = nil

local function stopPose()
	posing = false
	if orbitConn then orbitConn:Disconnect(); orbitConn = nil end
	local cam = Workspace.CurrentCamera
	if cam.CameraType == Enum.CameraType.Scriptable then cam.CameraType = Enum.CameraType.Custom end
	for _, n in ipairs({ "Victory", "Defeat" }) do
		local t = tracks[n]
		if t and t.IsPlaying then t:Stop(0.3) end
	end
end

local function pose(won: boolean?)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not root or not hum or hum.Health <= 0 then return end
	posing = true
	task.wait(0.35) -- let the camera leave first person
	if not posing then return end
	play(won == false and "Defeat" or "Victory", 0.2)
	local cam = Workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Scriptable
	local start = os.clock()
	orbitConn = RunService.RenderStepped:Connect(function()
		if not root.Parent then stopPose() return end
		local t = os.clock() - start
		local ease = 1 - math.exp(-t * 2.5)
		local angle = math.rad(-25 + 25 * ease + math.sin(t * 0.4) * 8)
		local focus = root.Position + Vector3.new(0, 1.2, 0)
		local front = root.CFrame * CFrame.Angles(0, angle, 0)
		local dist = 13 - 5 * ease
		cam.CFrame = CFrame.lookAt(focus + front.LookVector * dist + Vector3.new(0, 1.5, 0), focus)
	end)
end

MatchState.OnClientEvent:Connect(function(data)
	if typeof(data) ~= "table" then return end
	if data.State == "Ended" then
		local won: boolean? = nil
		if data.Winner ~= nil then won = data.Winner == data.YourTeam end
		task.spawn(pose, won)
	elseif data.State == "Lobby" or data.State == "PreMatch" then
		stopPose()
	end
end)
player.CharacterRemoving:Connect(stopPose)

---------------------------------------------------------------- lobby emote
local lastEmote = 0
UserInputService.InputBegan:Connect(function(input, processed)
	if processed or input.KeyCode ~= EMOTE_KEY then return end
	if player:GetAttribute("MatchId") ~= nil then return end
	if os.clock() - lastEmote < 2.5 then return end
	lastEmote = os.clock()
	play("Emote", 0.15)
end)
