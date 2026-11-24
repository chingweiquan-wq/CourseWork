-- AudioController (Phase 7): music, announcer, kill-streak banners and combat/ability sounds.
-- Everything it reacts to comes from the server (MatchState, KillFeed, HitConfirm, CombatFx, AbilityFx,
-- objective attributes), so the callouts can't be faked by a client. Purely cosmetic.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local Modules = ReplicatedStorage:WaitForChild("Modules")
local AudioConfig = require(Modules:WaitForChild("AudioConfig"))
local MapConfig = require(Modules:WaitForChild("MapConfig"))
local WeaponConfig = require(Modules:WaitForChild("WeaponConfig"))
local UI = require(Modules:WaitForChild("UIStyle"))
local Sfx = require(Modules:WaitForChild("Sfx"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local MatchState = Remotes:WaitForChild("MatchState")
local KillFeed = Remotes:WaitForChild("KillFeed")
local HitConfirm = Remotes:WaitForChild("HitConfirm")
local CombatFx = Remotes:WaitForChild("CombatFx")
local AbilityFx = Remotes:WaitForChild("AbilityFx")
local TokensEarned = Remotes:WaitForChild("TokensEarned")

---------------------------------------------------------------- saved volumes
for _, kind in ipairs({ "Music", "Sfx", "Announcer" }) do
	local attr = "Vol" .. kind
	local function apply()
		local v = player:GetAttribute(attr)
		if typeof(v) == "number" then Sfx.SetVolume(kind, v) end
	end
	player:GetAttributeChangedSignal(attr):Connect(apply)
	apply()
end

---------------------------------------------------------------- voice lines (generated up front)
-- most common lines first; the rest follow in the background
local preload = { AudioConfig.Special.Fight.Voice, AudioConfig.MultiKill[2].Voice, AudioConfig.Special.FirstBlood.Voice, AudioConfig.Special.Victory.Voice, AudioConfig.Special.Defeat.Voice }
for _, group in ipairs({ AudioConfig.MultiKill, AudioConfig.Streak, AudioConfig.Special }) do
	for _, l in pairs(group) do if l.Voice and not table.find(preload, l.Voice) then table.insert(preload, l.Voice) end end
end
task.spawn(Sfx.PreloadLines, preload)

---------------------------------------------------------------- music
local function matchTrack(mapId: string?)
	local tracks = AudioConfig.Music.Match
	local index = 1
	if mapId then
		-- stable map -> track pairing so each arena has its own theme
		local order = {}
		for id in pairs(MapConfig.Maps) do table.insert(order, id) end
		table.sort(order)
		for i, id in ipairs(order) do if id == mapId then index = ((i - 1) % #tracks) + 1 end end
	end
	return tracks[index]
end

Sfx.Music(AudioConfig.Music.Lobby)

---------------------------------------------------------------- banner (kill streaks / multi-kills)
local gui = Instance.new("ScreenGui")
gui.Name = "StreakUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 30
gui.Parent = player:WaitForChild("PlayerGui")

local holder = Instance.new("Frame")
holder.Name = "Banner"
holder.BackgroundTransparency = 1
holder.AnchorPoint = Vector2.new(0.5, 0.5)
holder.Position = UDim2.fromScale(0.5, 0.3)
holder.Size = UDim2.fromScale(0.5, 0.12)
holder.Visible = false
holder.Parent = gui
local holderScale = Instance.new("UIScale"); holderScale.Parent = holder

local bigText = UI.Label({ Parent = holder, Text = "", Font = UI.Fonts.Title, Size = UDim2.fromScale(1, 0.72), Position = UDim2.fromScale(0, 0), MaxSize = 72, StrokeSize = 4 })
local subText = UI.Label({ Parent = holder, Text = "", Font = UI.Fonts.Bold, Size = UDim2.fromScale(1, 0.28), Position = UDim2.fromScale(0, 0.72), MaxSize = 24, StrokeSize = 2 })
local bar = Instance.new("Frame"); bar.BorderSizePixel = 0; bar.AnchorPoint = Vector2.new(0.5, 0.5)
bar.Position = UDim2.fromScale(0.5, 0.7); bar.Size = UDim2.fromScale(0.6, 0.03); bar.Parent = holder

-- low-poly neon shards that burst out of the banner
local function shards(color: Color3)
	for i = 1, 10 do
		local s = Instance.new("Frame")
		s.BorderSizePixel = 0
		s.BackgroundColor3 = color
		s.AnchorPoint = Vector2.new(0.5, 0.5)
		s.Position = UDim2.fromScale(0.5, 0.35)
		s.Size = UDim2.fromOffset(math.random(10, 26), math.random(4, 8))
		s.Rotation = math.random(0, 360)
		s.ZIndex = 0
		s.Parent = holder
		local a = (i / 10) * math.pi * 2 + math.random() * 0.4
		local goal = UDim2.fromScale(0.5 + math.cos(a) * (0.35 + math.random() * 0.25), 0.35 + math.sin(a) * (1.2 + math.random()))
		TweenService:Create(s, TweenInfo.new(0.55, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Position = goal, Rotation = s.Rotation + math.random(-180, 180), BackgroundTransparency = 1 }):Play()
		Debris:AddItem(s, 0.6)
	end
end

local queue: { { [string]: any } } = {}
local showing = false

local function showNext()
	if showing then return end
	local item = table.remove(queue, 1)
	if not item then return end
	showing = true
	holder.Visible = true
	bigText.Text = item.Text
	bigText.TextColor3 = item.Color
	bigText.TextTransparency = 0
	subText.Text = item.Sub or ""
	subText.TextColor3 = Color3.new(1, 1, 1)
	subText.TextTransparency = 0
	bar.BackgroundColor3 = item.Color
	bar.BackgroundTransparency = 0
	bar.Size = UDim2.fromScale(0, 0.03)
	holderScale.Scale = 2.4
	TweenService:Create(holderScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(bar, TweenInfo.new(0.4, Enum.EasingStyle.Quart), { Size = UDim2.fromScale(0.6, 0.03) }):Play()
	shards(item.Color)
	Sfx.Play("StreakSting")
	if item.Voice then Sfx.Announce(item.Voice) end
	task.delay(1.5, function()
		local fade = TweenInfo.new(0.3)
		TweenService:Create(bigText, fade, { TextTransparency = 1 }):Play()
		TweenService:Create(subText, fade, { TextTransparency = 1 }):Play()
		TweenService:Create(bar, fade, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(holderScale, fade, { Scale = 0.85 }):Play()
		task.wait(0.32)
		holder.Visible = false
		showing = false
		showNext()
	end)
end

local function callout(item: { [string]: any })
	if #queue >= 3 then table.remove(queue, 1) end -- never let callouts lag far behind the action
	table.insert(queue, item)
	showNext()
end

-- small one-line notice for other players' streaks (no voice)
local function notice(text: string, color: Color3)
	local l = UI.Label({ Parent = gui, Text = text, Font = UI.Fonts.Bold, Color = color, Size = UDim2.fromScale(0.4, 0.035), Position = UDim2.fromScale(0.5, 0.2), AnchorPoint = Vector2.new(0.5, 0.5), MaxSize = 22, StrokeSize = 2 })
	UI.PopIn(l)
	task.delay(2.5, function()
		TweenService:Create(l, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
		Debris:AddItem(l, 0.45)
	end)
end

local function highest(tbl: { [number]: any }, n: number): any
	local best, bestN = nil, 0
	for k, v in pairs(tbl) do if n >= k and k > bestN then best, bestN = v, k end end
	return best, bestN
end

KillFeed.OnClientEvent:Connect(function(data)
	if typeof(data) ~= "table" then return end
	local streak = tonumber(data.Streak) or 0
	local chain = tonumber(data.Chain) or 0
	if data.KillerUserId == player.UserId then
		if data.FirstBlood then callout(AudioConfig.Special.FirstBlood) end
		if (tonumber(data.VictimStreak) or 0) >= AudioConfig.ShutdownAt then
			local s = AudioConfig.Special.Shutdown
			callout({ Text = s.Text, Voice = s.Voice, Color = s.Color, Sub = string.format("Ended %s's %d-kill streak", tostring(data.Victim), data.VictimStreak) })
		end
		local multi = chain >= 2 and highest(AudioConfig.MultiKill, chain) or nil
		local st = AudioConfig.Streak[streak] -- streak callouts fire exactly on the milestone
		if multi then
			callout({ Text = multi.Text, Voice = multi.Voice, Color = multi.Color, Sub = st and (st.Text .. "  -  " .. streak .. " KILL STREAK") or nil })
		elseif st then
			callout({ Text = st.Text, Voice = st.Voice, Color = st.Color, Sub = streak .. " KILL STREAK" })
		end
	elseif data.Killer then
		local st = AudioConfig.Streak[streak]
		if st and streak >= 5 then notice(string.format("%s is %s", data.Killer, st.Text), st.Color) end
		if (tonumber(data.VictimStreak) or 0) >= 5 then notice(string.format("%s shut down %s", data.Killer, tostring(data.Victim)), AudioConfig.Special.Shutdown.Color) end
	end
end)

---------------------------------------------------------------- match flow
local myTeam: string? = nil
MatchState.OnClientEvent:Connect(function(data)
	if typeof(data) ~= "table" then return end
	if data.State == "PreMatch" then
		myTeam = data.YourTeam
		Sfx.DuckMusic(1)
		Sfx.Music(matchTrack(data.MapId))
		Sfx.Play("Whoosh")
		Sfx.Play("Countdown")
	elseif data.State == "Live" and data.Event == nil then
		Sfx.Play("Fight")
		Sfx.Announce(AudioConfig.Special.Fight.Voice)
	elseif data.State == "Ended" then
		Sfx.DuckMusic(AudioConfig.Music.DuckDuringResults)
		if data.Winner == nil then
			Sfx.Play("Defeat", { Pitch = 1.4 })
			Sfx.Announce(AudioConfig.Special.Draw.Voice)
		elseif data.Winner == data.YourTeam then
			Sfx.Play("Victory")
			Sfx.Announce(AudioConfig.Special.Victory.Voice)
		else
			Sfx.Play("Defeat")
			Sfx.Announce(AudioConfig.Special.Defeat.Voice)
		end
	elseif data.State == "Lobby" then
		myTeam = nil
		queue = {}
		Sfx.DuckMusic(1)
		Sfx.Music(AudioConfig.Music.Lobby)
	end
end)

-- Hold the Core: voice when the core flips, soft tick while you stand on it
local lastObjState: any = nil
local lastObjVoice = 0
player:GetAttributeChangedSignal("ObjState"):Connect(function()
	local state = player:GetAttribute("ObjState")
	local mine = player:GetAttribute("Team") or myTeam
	if state ~= lastObjState and os.clock() - lastObjVoice > 5 and mine then
		if state == mine then
			Sfx.Announce(AudioConfig.Special.CoreCaptured.Voice); lastObjVoice = os.clock()
		elseif (state == "Alpha" or state == "Bravo") and lastObjState == mine then
			Sfx.Announce(AudioConfig.Special.CoreLost.Voice); lastObjVoice = os.clock()
		end
	end
	lastObjState = state
end)
task.spawn(function()
	while true do
		task.wait(1)
		if player:GetAttribute("ObjOnPoint") == true then Sfx.Play("CoreTick") end
	end
end)

---------------------------------------------------------------- combat feedback
HitConfirm.OnClientEvent:Connect(function(data)
	if typeof(data) ~= "table" then return end
	if data.Killed then Sfx.Play("KillConfirm")
	elseif data.Headshot then Sfx.Play("Headshot")
	else Sfx.Play("HitMarker") end
end)

-- other players' shots, heard in 3D (your own shots play instantly in CombatController)
CombatFx.OnClientEvent:Connect(function(data)
	if typeof(data) ~= "table" then return end
	local w = WeaponConfig.Weapons[data.Weapon]
	if not w then return end
	local mine = data.Shooter == player.UserId
	if (data.Type == "Shot" or data.Type == "Projectile" or data.Type == "Melee") and not mine and typeof(data.From) == "Vector3" then
		Sfx.Play("Fire_" .. w.Id, { Position = data.From })
	elseif data.Type == "Impact" and typeof(data.Position) == "Vector3" then
		Sfx.Play((data.Radius or 0) > 0 and "Explosion" or "Impact", { Position = data.Position })
	end
end)

local ABILITY_SOUNDS = { Explosion = "Explosion", Shockwave = "Shockwave", HealRing = "Heal", Ping = "Cast", Zap = "Zap", Blink = "Blink", Puff = "Cast" }
AbilityFx.OnClientEvent:Connect(function(data)
	if typeof(data) ~= "table" then return end
	if data.Type == "UltCast" then
		Sfx.Play("Ultimate", { Volume = data.Owner == player.UserId and 1 or 0.5 })
		return
	end
	local name = ABILITY_SOUNDS[data.Type]
	local pos = typeof(data.Position) == "Vector3" and data.Position or (typeof(data.To) == "Vector3" and data.To or nil)
	if name and pos then Sfx.Play(name, { Position = pos }) end
end)

TokensEarned.OnClientEvent:Connect(function(data)
	if typeof(data) == "table" and (tonumber(data.Total) or 0) > 0 then
		task.delay(0.8, function() Sfx.Play("Tokens") end)
	end
end)

-- taking damage
local function watchHealth(char: Model)
	local hum = char:WaitForChild("Humanoid", 10) :: Humanoid?
	if not hum then return end
	local last = hum.Health
	local lastSound = 0
	hum.HealthChanged:Connect(function(h)
		if h < last - 1 and h > 0 and os.clock() - lastSound > 0.15 then
			lastSound = os.clock()
			Sfx.Play("Hurt")
		end
		last = h
	end)
end
if player.Character then task.spawn(watchHealth, player.Character) end
player.CharacterAdded:Connect(watchHealth)
