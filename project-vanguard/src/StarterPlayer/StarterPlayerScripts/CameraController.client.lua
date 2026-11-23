-- CameraController: first-person while alive in a live/pre-match, normal third-person in the lobby,
-- while dead, and on the results screen.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local MATCH_FOV = 80
local LOBBY_FOV = 70

local function shouldBeFirstPerson(): boolean
	if not player:GetAttribute("MatchId") then return false end
	local gui = player:FindFirstChild("PlayerGui")
	local result = gui and gui:FindFirstChild("MatchResultUI")
	if result and (result :: ScreenGui).Enabled then return false end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0
end

local current: boolean? = nil
local function update()
	local fp = shouldBeFirstPerson()
	if fp == current then return end
	current = fp
	camera = workspace.CurrentCamera
	if fp then
		player.CameraMode = Enum.CameraMode.LockFirstPerson
		camera.FieldOfView = MATCH_FOV
		UserInputService.MouseIconEnabled = false -- the HUD draws its own crosshair
	else
		player.CameraMode = Enum.CameraMode.Classic
		player.CameraMinZoomDistance = 0.5
		if player:GetAttribute("MatchId") == nil then
			player.CameraMaxZoomDistance = 30
		end
		camera.FieldOfView = LOBBY_FOV
		UserInputService.MouseIconEnabled = true
		-- pull the camera back out of the head after leaving first person
		player.CameraMinZoomDistance = 8
		task.defer(function() player.CameraMinZoomDistance = 0.5 end)
	end
end

while true do
	update()
	task.wait(0.2)
end
