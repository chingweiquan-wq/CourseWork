--========================================================
-- HealthBar_DarkTech.client.lua  |  DevPanels
-- Version: V1.2  (Smooth Fill + LagBar Fix + Damage FX + Mobile + Dynamic Heartbeat)
-- Creator: (you)
--
-- UPDATE V1.2 (IMPORTANT)
--   ✅ Removed “revive/shine” effect (no heal shine / no idle shine)
--   ✅ Fixed “red remainder on 0 HP” (LagBar hides instantly when dead)
--   ✅ Added dynamic heartbeat:
--       - Heart always “beats” slowly at high HP
--       - Beats faster + slightly stronger at low HP
--       - Stops + resets at 0 HP (clean death state)
--   ✅ Premium bar look via animated gradient drift (subtle, non-distracting)
--
-- WHAT THIS SCRIPT DOES
--   • Builds a Dark-Tech HealthBar UI by script (no external assets required)
--   • Anchors bottom-left (mobile-friendly with UIScale)
--   • Reads player Humanoid Health + MaxHealth
--   • Smoothly animates health bar size (front bar)
--   • Shows a “LagBar” behind (damage delay feedback)
--   • Damage feedback: stroke flash + subtle shake
--   • Low HP warning glow (only when alive)
--   • Dynamic heart beat based on HP %
--
-- WHERE TO PUT IT
--   StarterGui > HealthBar (ScreenGui) > LocalScript
--
-- REQUIREMENTS
--   • Player Character must contain a Humanoid
--
-- BUYER QUICK EDITS
--   • Colors: stroke/bar/lagBar
--   • Sizes: root.Size, root.Position
--   • Low HP threshold: (pct <= 0.25)
--========================================================

-- Services: used for players, tweens, render updates, and CoreGui changes
local Players = game:GetService("Players") -- Provides LocalPlayer and character events
local TweenService = game:GetService("TweenService") -- Smooth animations (tweens)
local RunService = game:GetService("RunService") -- Per-frame updates (for scaling/loops)
local StarterGui = game:GetService("StarterGui") -- To disable default Roblox health UI

-- Player references
local player = Players.LocalPlayer -- The client player running this LocalScript

-- GUI references
local gui = script.Parent -- The ScreenGui this script is inside
gui.ResetOnSpawn = false -- Keeps UI persistent across respawns
gui.IgnoreGuiInset = true -- Ignores top bar inset (clean positioning)

-- Hide default Roblox health UI so only custom bar shows
pcall(function() -- pcall avoids hard error if SetCoreGuiEnabled fails in some contexts
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false) -- Disable default health
end)

-- =========================
-- UI BUILD (Created entirely by script)
-- =========================

-- Root container frame (the whole health bar background)
local root = Instance.new("Frame") -- Main wrapper
root.Name = "Root" -- Helpful name in Explorer
root.Parent = gui -- Put it inside the ScreenGui
root.AnchorPoint = Vector2.new(0, 1) -- Bottom-left anchoring behavior
root.Position = UDim2.new(0, 18, 1, -18) -- Bottom-left offset (padding)
root.Size = UDim2.new(0, 340, 0, 74) -- Overall size of the UI
root.BackgroundColor3 = Color3.fromRGB(15, 18, 26) -- Dark tech background
root.BackgroundTransparency = 0.15 -- Slight transparency for style
root.BorderSizePixel = 0 -- No Roblox default border

-- Rounded corners for root
Instance.new("UICorner", root).CornerRadius = UDim.new(0, 20) -- Smooth rounded shape

-- Outline stroke around root
local stroke = Instance.new("UIStroke", root) -- Outer border
stroke.Color = Color3.fromRGB(90, 220, 255) -- Cyan tech outline
stroke.Thickness = 2 -- Border thickness
stroke.Transparency = 0.7 -- Semi-transparent, premium feel

-- Padding inside root so inner content doesn't touch edges
local pad = Instance.new("UIPadding", root) -- Inner padding component
pad.PaddingTop = UDim.new(0, 10) -- Top padding
pad.PaddingBottom = UDim.new(0, 10) -- Bottom padding
pad.PaddingLeft = UDim.new(0, 10) -- Left padding
pad.PaddingRight = UDim.new(0, 10) -- Right padding

-- Mobile-friendly scaling
local uiScale = Instance.new("UIScale", root) -- Scales entire root for different screens
uiScale.Scale = 1 -- Default scale (desktop)

-- Function to scale based on screen width (simple responsive behavior)
local function applyScale()
	local cam = workspace.CurrentCamera -- Current rendering camera
	if not cam then return end -- If no camera yet, do nothing
	local w = cam.ViewportSize.X -- Screen width in pixels
	local target = 1 -- Default scale
	if w < 700 then -- Small screens (phones)
		target = 0.85 -- Scale down a bit
	elseif w < 900 then -- Tablets/smaller window
		target = 0.95 -- Slight scale down
	end
	uiScale.Scale = target -- Apply scale
end

applyScale() -- Apply once at start
RunService.RenderStepped:Connect(applyScale) -- Update on resize / device changes

-- Left icon container (heart background)
local iconWrap = Instance.new("Frame") -- Icon frame
iconWrap.Name = "IconWrap" -- Helpful name
iconWrap.Parent = root -- Inside root
iconWrap.Size = UDim2.new(0, 54, 0, 54) -- Icon box size
iconWrap.BackgroundColor3 = Color3.fromRGB(20, 24, 34) -- Slightly lighter than root
iconWrap.BackgroundTransparency = 0.10 -- Subtle transparency
iconWrap.BorderSizePixel = 0 -- No border

-- Rounded corners for iconWrap
Instance.new("UICorner", iconWrap).CornerRadius = UDim.new(0, 18) -- Round icon box

-- Outline for iconWrap
local iconStroke = Instance.new("UIStroke", iconWrap) -- Border around heart box
iconStroke.Color = Color3.fromRGB(90, 220, 255) -- Cyan outline
iconStroke.Thickness = 2 -- Thickness
iconStroke.Transparency = 0.55 -- Slightly more visible than root

-- Heart icon (text-based so no external assets needed)
local heart = Instance.new("TextLabel") -- Heart icon label
heart.Parent = iconWrap -- Put inside iconWrap
heart.BackgroundTransparency = 1 -- No label background
heart.Size = UDim2.new(1, 0, 1, 0) -- Fill iconWrap
heart.Font = Enum.Font.GothamBlack -- Bold, clean font
heart.Text = "❤" -- Heart character
heart.TextSize = 30 -- Icon size
heart.TextColor3 = Color3.fromRGB(255, 90, 100) -- Pinkish red heart

-- Scale controller for heartbeat animation
local heartScale = Instance.new("UIScale") -- Scale component for heart
heartScale.Parent = heart -- Attach to heart label
heartScale.Scale = 1 -- Default size

-- Bar container frame (holds lag bar + actual bar)
local barWrap = Instance.new("Frame") -- Health bar wrapper
barWrap.Name = "BarWrap" -- Helpful name
barWrap.Parent = root -- Inside root
barWrap.Position = UDim2.new(0, 64, 0, 8) -- Right of heart + top aligned
barWrap.Size = UDim2.new(1, -64, 0, 30) -- Takes remaining width
barWrap.BackgroundColor3 = Color3.fromRGB(10, 12, 18) -- Deep background
barWrap.BackgroundTransparency = 0.10 -- Subtle transparency
barWrap.BorderSizePixel = 0 -- No border

-- Rounded corners for barWrap
Instance.new("UICorner", barWrap).CornerRadius = UDim.new(0, 14) -- Rounded bar container

-- Subtle stroke on bar background
local barBackStroke = Instance.new("UIStroke", barWrap) -- Border around bar container
barBackStroke.Color = Color3.fromRGB(40, 46, 66) -- Dark border
barBackStroke.Thickness = 2 -- Thickness
barBackStroke.Transparency = 0.6 -- Subtle

-- Lag bar (damage delay effect) - sits behind main bar
local lagBar = Instance.new("Frame") -- Lag bar frame
lagBar.Name = "LagBar" -- Helpful name
lagBar.Parent = barWrap -- Inside barWrap
lagBar.Size = UDim2.new(1, 0, 1, 0) -- Start full width (will be set)
lagBar.BackgroundColor3 = Color3.fromRGB(255, 170, 80) -- Orange damage trail
lagBar.BackgroundTransparency = 0.35 -- Semi-transparent
lagBar.BorderSizePixel = 0 -- No border

-- Rounded corners for lagBar
Instance.new("UICorner", lagBar).CornerRadius = UDim.new(0, 14) -- Rounded lag bar

-- Actual health bar (front bar)
local bar = Instance.new("Frame") -- Main health fill
bar.Name = "Bar" -- Helpful name
bar.Parent = barWrap -- Inside barWrap
bar.Size = UDim2.new(1, 0, 1, 0) -- Start full width
bar.BackgroundColor3 = Color3.fromRGB(80, 255, 140) -- Default green
bar.BackgroundTransparency = 0 -- Opaque
bar.BorderSizePixel = 0 -- No border

-- Rounded corners for main bar
Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 14) -- Rounded fill

-- Static gloss overlay for depth (not animated)
local gloss = Instance.new("Frame") -- Gloss layer
gloss.Parent = bar -- On top of fill
gloss.BackgroundColor3 = Color3.fromRGB(255, 255, 255) -- White highlight
gloss.BackgroundTransparency = 0.88 -- Very subtle
gloss.BorderSizePixel = 0 -- No border
gloss.Size = UDim2.new(1, 0, 0.45, 0) -- Top portion only

-- Rounded corners for gloss (matches bar)
Instance.new("UICorner", gloss).CornerRadius = UDim.new(0, 14) -- Same rounding

-- Gradient fill for premium look
local barGrad = Instance.new("UIGradient") -- Gradient component
barGrad.Parent = bar -- Attach to bar
barGrad.Rotation = 0 -- Horizontal gradient
barGrad.Color = ColorSequence.new{ -- Default green-ish gradient
	ColorSequenceKeypoint.new(0, Color3.fromRGB(40, 255, 210)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 255, 140)),
}
barGrad.Offset = Vector2.new(0, 0) -- Starting offset

-- Text label showing "current/max" health
local valueLabel = Instance.new("TextLabel") -- Health value text
valueLabel.Name = "Value" -- Helpful name
valueLabel.Parent = root -- Inside root
valueLabel.Position = UDim2.new(0, 64, 0, 42) -- Under the bar
valueLabel.Size = UDim2.new(1, -64, 0, 22) -- Full width minus heart
valueLabel.BackgroundTransparency = 1 -- No background
valueLabel.Font = Enum.Font.GothamBold -- Clean bold font
valueLabel.Text = "0/0" -- Default
valueLabel.TextSize = 18 -- Readable size
valueLabel.TextXAlignment = Enum.TextXAlignment.Left -- Left aligned
valueLabel.TextColor3 = Color3.fromRGB(220, 245, 255) -- Light tech text

-- Warning glow behind root for low HP
local warningGlow = Instance.new("Frame") -- Glow overlay
warningGlow.Name = "WarningGlow" -- Helpful name
warningGlow.Parent = root -- Behind/under root
warningGlow.BackgroundColor3 = Color3.fromRGB(255, 60, 80) -- Red glow
warningGlow.BackgroundTransparency = 1 -- Hidden by default
warningGlow.BorderSizePixel = 0 -- No border
warningGlow.Size = UDim2.new(1, 0, 1, 0) -- Same size as root
warningGlow.ZIndex = root.ZIndex - 1 -- Render behind root
Instance.new("UICorner", warningGlow).CornerRadius = UDim.new(0, 20) -- Same rounding

-- =========================
-- TWEEN HELPERS (smooth animations)
-- =========================

-- Helper to create and play tweens quickly
local function tween(obj, ti, props)
	local t = TweenService:Create(obj, ti, props) -- Build tween
	t:Play() -- Start tween
	return t -- Return tween for Completed:Wait if needed
end

-- Tween presets
local tiFast = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out) -- Snappy
local tiSmooth = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out) -- Smooth
local tiLag = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out) -- Slow catch-up

-- =========================
-- VISUAL FX (damage flash + warning)
-- =========================

-- Quick feedback on damage: stroke flash + tiny shake
local function damageFlash()
	tween(stroke, tiFast, {Transparency = 0.25}) -- Highlight border
	tween(iconStroke, tiFast, {Transparency = 0.20}) -- Highlight icon border
	tween(root, tiFast, {Position = UDim2.new(0, 21, 1, -20)}) -- Tiny nudge (shake)

	task.delay(0.08, function() -- Reset shortly after
		tween(stroke, tiFast, {Transparency = 0.7}) -- Back to normal
		tween(iconStroke, tiFast, {Transparency = 0.55}) -- Back to normal
		tween(root, tiFast, {Position = UDim2.new(0, 18, 1, -18)}) -- Back to base pos
	end)
end

-- Low HP glow behind root (only when alive)
local function lowHpWarn(enable: boolean)
	if enable then
		tween(warningGlow, TweenInfo.new(0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {BackgroundTransparency = 0.85}) -- Show
	else
		tween(warningGlow, TweenInfo.new(0.25, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {BackgroundTransparency = 1}) -- Hide
	end
end

-- =========================
-- HEALTH STATE + UI UPDATES
-- =========================

local humanoid: Humanoid? = nil -- Bound humanoid reference
local lastHealth = 0 -- Previous health value for change detection

-- Update bar colors + gradient based on health percentage
local function setBarColor(pct: number)
	if pct > 0.55 then -- High health
		bar.BackgroundColor3 = Color3.fromRGB(80, 255, 140) -- Green
		barGrad.Color = ColorSequence.new{
			ColorSequenceKeypoint.new(0, Color3.fromRGB(40, 255, 210)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 255, 140)),
		}
	elseif pct > 0.25 then -- Mid health
		bar.BackgroundColor3 = Color3.fromRGB(255, 210, 90) -- Yellow
		barGrad.Color = ColorSequence.new{
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 230, 120)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 190, 80)),
		}
	else -- Low health
		bar.BackgroundColor3 = Color3.fromRGB(255, 90, 100) -- Red
		barGrad.Color = ColorSequence.new{
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 140, 150)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 70, 90)),
		}
	end
end

-- Set lag bar size with a crucial FIX:
-- when pct <= 0, hide lag bar completely to avoid the “red remainder” look
local function setLagBarPct(pct: number, animated: boolean)
	pct = math.clamp(pct, 0, 1) -- Clamp to valid range
	if pct <= 0 then -- Dead / empty
		lagBar.Size = UDim2.new(0, 0, 1, 0) -- Force empty
		lagBar.Visible = false -- Hide completely
		return -- Exit
	end
	lagBar.Visible = true -- Ensure visible when > 0
	if animated then -- Smooth catch-up
		tween(lagBar, tiLag, {Size = UDim2.new(pct, 0, 1, 0)}) -- Animate size
	else -- Immediate set
		lagBar.Size = UDim2.new(pct, 0, 1, 0) -- Set size
	end
end

-- Set main bar size (smooth or instant)
local function setBarPct(pct: number, animated: boolean)
	pct = math.clamp(pct, 0, 1) -- Clamp
	if animated then
		tween(bar, tiSmooth, {Size = UDim2.new(pct, 0, 1, 0)}) -- Smooth size change
	else
		bar.Size = UDim2.new(pct, 0, 1, 0) -- Instant change
	end
end

-- Full UI update based on current + max health
local function updateUI(cur: number, max: number, instant: boolean)
	if max <= 0 then return end -- Avoid division by zero

	cur = math.max(cur, 0) -- Never below 0
	local pct = math.clamp(cur / max, 0, 1) -- Percent health

	valueLabel.Text = string.format("%d/%d", math.floor(cur + 0.5), math.floor(max + 0.5)) -- Update text
	setBarColor(pct) -- Update colors

	setBarPct(pct, not instant) -- Update main bar (smooth unless instant)
	if instant then
		setLagBarPct(pct, false) -- Align lag bar instantly on first bind
	end

	-- Low HP glow only when alive and low
	if pct > 0 and pct <= 0.25 then
		lowHpWarn(true) -- Show warning
	else
		lowHpWarn(false) -- Hide warning
	end

	-- Death look: slightly fade fill when empty (clean)
	if pct <= 0 then
		tween(bar, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = 0.25}) -- Fade a bit
	else
		tween(bar, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = 0}) -- Full visible
	end
end

-- =========================
-- HUMANOID BINDING
-- =========================

-- Bind to a humanoid and connect health events
local function bindHumanoid(h: Humanoid)
	humanoid = h -- Store reference
	lastHealth = h.Health -- Save initial

	updateUI(h.Health, h.MaxHealth, true) -- Initial paint (instant)

	-- When health changes (damage/heal)
	h.HealthChanged:Connect(function(newHealth)
		if not humanoid then return end -- Safety
		local max = humanoid.MaxHealth -- Current max
		local prev = lastHealth -- Previous
		lastHealth = newHealth -- Update stored

		updateUI(newHealth, max, false) -- Update UI smoothly

		local pctNew = math.clamp(math.max(newHealth, 0) / max, 0, 1) -- New percent
		local pctPrev = math.clamp(math.max(prev, 0) / max, 0, 1) -- Prev percent

		if newHealth < prev then -- DAMAGE case
			damageFlash() -- Hit feedback

			if pctNew <= 0 then -- If dead now
				setLagBarPct(0, false) -- Kill lag bar instantly (fix)
				return -- Done
			end

			-- Hold lag bar at previous percent briefly
			setLagBarPct(pctPrev, false) -- Set lag to old value immediately

			-- Then ease it down after short delay
			task.delay(0.08, function()
				if humanoid then -- Safety check
					local nowPct = math.clamp(math.max(humanoid.Health, 0) / humanoid.MaxHealth, 0, 1) -- Current
					setLagBarPct(nowPct, true) -- Animate lag down to current
				end
			end)
		else
			-- HEAL case: we intentionally do NOT do “revive/shine” effects
			-- Keep lag bar synced immediately (clean)
			setLagBarPct(pctNew, false) -- Snap lag to new value
		end
	end)

	-- If MaxHealth changes (buffs/debuffs)
	h:GetPropertyChangedSignal("MaxHealth"):Connect(function()
		if not humanoid then return end -- Safety
		updateUI(humanoid.Health, humanoid.MaxHealth, false) -- Recompute percent + UI

		local pct = math.clamp(math.max(humanoid.Health, 0) / humanoid.MaxHealth, 0, 1) -- Current percent
		if pct <= 0 then
			setLagBarPct(0, false) -- Hide lag on 0
		else
			setLagBarPct(pct, true) -- Animate to new percent
		end
	end)
end

-- Find Humanoid in a character and bind it
local function tryBindFromCharacter(char: Model)
	local h = char:FindFirstChildOfClass("Humanoid") -- Try immediate
	if not h then
		h = char:WaitForChild("Humanoid", 10) -- Wait up to 10s
	end
	if h and h:IsA("Humanoid") then
		bindHumanoid(h) -- Bind
	else
		warn("HealthBar: No Humanoid found.") -- Debug warning
	end
end

-- Re-bind when character respawns
player.CharacterAdded:Connect(function(char)
	task.wait(0.05) -- Small delay to ensure Humanoid exists
	tryBindFromCharacter(char) -- Bind new character
end)

-- Bind immediately if already spawned
if player.Character then
	tryBindFromCharacter(player.Character) -- Bind now
end

-- =========================
-- PREMIUM MOTION: GRADIENT DRIFT (subtle)
-- =========================

-- Loop to slowly move gradient offset left/right for life in the bar
task.spawn(function()
	while bar and bar.Parent do -- While UI exists
		local t1 = tween(barGrad, TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {Offset = Vector2.new(0.12, 0)}) -- Move right
		t1.Completed:Wait() -- Wait finish
		local t2 = tween(barGrad, TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {Offset = Vector2.new(-0.12, 0)}) -- Move left
		t2.Completed:Wait() -- Wait finish
	end
end)

-- =========================
-- HEART BEAT: ALWAYS (faster at low HP), stop on 0
-- =========================

-- Loop that continuously “beats” the heart with variable speed based on HP percentage
task.spawn(function()
	while gui and gui.Parent do -- While ScreenGui exists
		task.wait(0.05) -- Small pacing

		if humanoid and humanoid.MaxHealth > 0 then -- Only if bound
			local pct = humanoid.Health / humanoid.MaxHealth -- Health percentage

			if pct <= 0 then -- Dead
				-- Reset heart scale and pause (no pulsing while dead)
				if math.abs(heartScale.Scale - 1) > 0.01 then -- If not normal size
					tween(heartScale, TweenInfo.new(0.15, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {Scale = 1}) -- Reset
				end
				task.wait(0.25) -- Pause while dead
			else
				-- Speed mapping:
				-- Higher HP => slower beat, lower HP => faster beat
				local beat = 0.22 + (pct * 0.65) -- 0.22..0.87 seconds for a full beat cycle
				local upTime = beat * 0.45 -- Time for “expand”
				local downTime = beat * 0.55 -- Time for “contract”

				-- Amplitude mapping:
				-- Low HP => stronger pulse
				local amp = 1.04 + (1 - pct) * 0.06 -- 1.04..1.10

				-- Expand (heartbeat up)
				local up = tween(heartScale, TweenInfo.new(upTime, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {Scale = amp})
				up.Completed:Wait() -- Wait finish

				-- Contract (heartbeat down)
				local down = tween(heartScale, TweenInfo.new(downTime, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {Scale = 1})
				down.Completed:Wait() -- Wait finish
			end
		else
			task.wait(0.25) -- If no humanoid yet, wait
		end
	end
end)
