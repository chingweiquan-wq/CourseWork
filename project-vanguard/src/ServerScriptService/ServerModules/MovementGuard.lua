--!strict
-- MovementGuard (Phase 9 audit fix): stops teleport exploits in matches.
-- Players own their character physics, so an exploiter could move their character anywhere (behind a target
-- for melee, onto the core, into a group for an ability). Every SAMPLE seconds the server compares how far
-- each in-match character moved horizontally with what is possible:
--   walking (WalkSpeed x time x slack) + a burst allowance right after a dash/blink, knockback or a hit.
-- Moves far beyond that are clear teleports: the character is pulled back to its last valid position.
-- Thresholds are deliberately generous so lag spikes and legit abilities never trigger it.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local MatchManager = require(script.Parent.MatchManager)

local SAMPLE = 0.25
local SLACK = 1.6          -- walking speed multiplier tolerance
local MARGIN = 20          -- extra studs before anything counts as a teleport
local BURST = 32           -- allowance after a dash / blink / knockback (longest legit move is ~27 studs)
local BURST_WINDOW = 1.2   -- seconds the burst allowance lasts

local MovementGuard = {}

type Track = { Last: Vector3, BurstUntil: number, Strikes: number }
local tracks: { [Player]: Track } = {}

local function root(p: Player): BasePart?
	local c = p.Character
	local r = c and c:FindFirstChild("HumanoidRootPart")
	return (r and r:IsA("BasePart")) and r or nil
end

-- anything that legitimately moves a player fast opens a short burst window
function MovementGuard.AllowBurst(p: Player)
	local t = tracks[p]
	if t then t.BurstUntil = os.clock() + BURST_WINDOW end
end

local function reset(p: Player)
	local r = root(p)
	tracks[p] = { Last = r and r.Position or Vector3.zero, BurstUntil = os.clock() + 2, Strikes = 0 }
end

function MovementGuard.Init()
	local function hook(p: Player)
		p.CharacterAdded:Connect(function(char)
			tracks[p] = nil
			task.defer(function()
				reset(p)
				local hum = char:WaitForChild("Humanoid", 5) :: Humanoid?
				if hum then
					local last = hum.Health
					hum.HealthChanged:Connect(function(h)
						if h < last then MovementGuard.AllowBurst(p) end -- knockback usually comes with damage
						last = h
					end)
				end
			end)
		end)
		-- dash / blink accepted by the server (cooldown attribute jumps into the future)
		p:GetAttributeChangedSignal("Ready_Dash"):Connect(function() MovementGuard.AllowBurst(p) end)
		p:GetAttributeChangedSignal("Ready_Ultimate"):Connect(function() MovementGuard.AllowBurst(p) end)
	end
	for _, p in ipairs(Players:GetPlayers()) do hook(p) end
	Players.PlayerAdded:Connect(hook)
	Players.PlayerRemoving:Connect(function(p) tracks[p] = nil end)

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < SAMPLE then return end
		local elapsed = acc
		acc = 0
		local now = os.clock()
		for _, p in ipairs(Players:GetPlayers()) do
			local t = tracks[p]
			local r = root(p)
			local match = MatchManager.GetMatch(p)
			local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
			if t and r and hum and match and match.State == "Live" and hum.Health > 0 and not r.Anchored then
				local pos = r.Position
				local flat = Vector3.new(pos.X - t.Last.X, 0, pos.Z - t.Last.Z).Magnitude
				local allowed = hum.WalkSpeed * elapsed * SLACK + MARGIN + (now < t.BurstUntil and BURST or 0)
				if flat > allowed then
					t.Strikes += 1
					r.AssemblyLinearVelocity = Vector3.zero
					p.Character:PivotTo(CFrame.new(t.Last) * r.CFrame.Rotation)
					if t.Strikes == 1 or t.Strikes % 10 == 0 then
						warn(string.format("[MovementGuard] %s moved %.0f studs in %.2fs (allowed %.0f) - pulled back (strike %d)", p.Name, flat, elapsed, allowed, t.Strikes))
					end
				else
					t.Last = pos
				end
			elseif t and r then
				t.Last = r.Position -- outside live matches (lobby, frozen pre-match) just follow the player
			end
		end
	end)
end

return MovementGuard
