--!strict
-- StreakFxController: the more you kill without dying, the more the screen reacts.
--  * screen-edge glow that gets stronger and changes colour with your streak (cyan -> gold -> orange -> red -> magenta)
--  * every kill: a short, small camera shake + a slight zoom punch (both grow a little with the streak, but stay small)
-- Streak = consecutive kills this life; it resets when you die. Visual only.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local KillFeed = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("KillFeed")

local TIERS = {
	{ At = 1, Color = Color3.fromRGB(0, 220, 255), Alpha = 0.88 },
	{ At = 2, Color = Color3.fromRGB(255, 200, 60), Alpha = 0.8 },
	{ At = 3, Color = Color3.fromRGB(255, 140, 40), Alpha = 0.72 },
	{ At = 5, Color = Color3.fromRGB(255, 60, 70), Alpha = 0.64 },
	{ At = 8, Color = Color3.fromRGB(255, 60, 200), Alpha = 0.56 },
}

local gui = Instance.new("ScreenGui")
gui.Name = "StreakFxUI"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 2
gui.Parent = player:WaitForChild("PlayerGui")

local edges: { Frame } = {}
for _, e in ipairs({
	{ UDim2.fromScale(0.12, 1), UDim2.fromScale(0, 0), 0 },
	{ UDim2.fromScale(0.12, 1), UDim2.fromScale(0.88, 0), 180 },
	{ UDim2.fromScale(1, 0.14), UDim2.fromScale(0, 0), 90 },
	{ UDim2.fromScale(1, 0.14), UDim2.fromScale(0, 0.86), 270 },
}) do
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundTransparency = 1
	f.Size = e[1]; f.Position = e[2]
	local g = Instance.new("UIGradient")
	g.Rotation = e[3]
	g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	g.Parent = f
	f.Parent = gui
	table.insert(edges, f)
end

local streak = 0
local baseAlpha = 1 -- resting edge transparency for the current streak (1 = off)
local flashUntil = 0

local function tierFor(n: number)
	local best = nil
	for _, t in ipairs(TIERS) do if n >= t.At then best = t end end
	return best
end

local function setStreak(n: number)
	streak = n
	local t = tierFor(n)
	baseAlpha = t and t.Alpha or 1
	for _, f in ipairs(edges) do if t then f.BackgroundColor3 = t.Color end end
end

-- small shake: a few frames of tiny random rotation on top of the normal camera
local shakeLeft, shakeAmp = 0, 0
RunService:BindToRenderStep("VG_StreakShake", Enum.RenderPriority.Camera.Value + 2, function(dt)
	-- edges: pulse gently while on a streak; flash brighter right after a kill
	local now = os.clock()
	local alpha = baseAlpha
	if baseAlpha < 1 then alpha = baseAlpha + math.sin(now * 4) * 0.03 end
	if now < flashUntil then alpha = math.min(alpha, baseAlpha - 0.25 * ((flashUntil - now) / 0.35)) end
	for _, f in ipairs(edges) do f.BackgroundTransparency = math.clamp(alpha, 0, 1) end
	if shakeLeft > 0 then
		shakeLeft -= dt
		local k = math.max(shakeLeft, 0) / 0.22
		local cam = workspace.CurrentCamera
		cam.CFrame = cam.CFrame * CFrame.Angles(math.rad((math.random() - 0.5) * shakeAmp * k), math.rad((math.random() - 0.5) * shakeAmp * k), 0)
	end
end)

local function punch(n: number)
	-- shake: 0.6 deg at 1 kill, up to 1.6 deg at high streaks (kept small on purpose)
	shakeAmp = math.min(0.6 + n * 0.15, 1.6)
	shakeLeft = 0.22
	flashUntil = os.clock() + 0.35
	-- zoom punch: narrow the view a touch, then ease back (skipped while aiming so the scope stays steady)
	if player:GetAttribute("Aiming") == true then return end
	local cam = workspace.CurrentCamera
	local base = cam.FieldOfView
	local amount = math.min(2 + n * 0.5, 5)
	TweenService:Create(cam, TweenInfo.new(0.06), { FieldOfView = base - amount }):Play()
	task.delay(0.08, function()
		TweenService:Create(cam, TweenInfo.new(0.3, Enum.EasingStyle.Quad), { FieldOfView = base }):Play()
	end)
end

KillFeed.OnClientEvent:Connect(function(data)
	if typeof(data) ~= "table" then return end
	if data.KillerUserId == player.UserId then
		local n = tonumber(data.Streak) or (streak + 1)
		setStreak(n)
		punch(n)
	elseif data.VictimUserId == player.UserId then
		setStreak(0)
	end
end)

-- streak ends when you die (and when you leave a match)
local function watch(char: Model)
	local hum = char:WaitForChild("Humanoid", 10) :: Humanoid?
	if hum then hum.Died:Connect(function() setStreak(0) end) end
end
if player.Character then task.spawn(watch, player.Character) end
player.CharacterAdded:Connect(watch)
player:GetAttributeChangedSignal("MatchId"):Connect(function()
	if not player:GetAttribute("MatchId") then setStreak(0) end
end)
