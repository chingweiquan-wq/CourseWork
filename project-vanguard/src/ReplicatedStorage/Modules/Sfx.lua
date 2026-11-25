--!strict
-- Sfx: client-side audio player (Phase 7). Required by every LocalScript that makes noise, so they all
-- share one set of volume groups, one music player and one announcer voice.
--   Sfx.Play(name, { Position = Vector3?, Volume = number?, Pitch = number? })  -> 2D, or 3D at Position
--   Sfx.Music(track)            crossfade to a track from AudioConfig.Music (nil = silence)
--   Sfx.DuckMusic(mult)         temporarily lower the music (results screen)
--   Sfx.Announce(text)          speak a line with the announcer voice (text-to-speech)
--   Sfx.SetVolume(kind, 0..1)   kind = "Music" | "Sfx" | "Announcer"
-- Purely cosmetic: nothing here talks to the server.
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local AudioConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("AudioConfig"))

local Sfx = {}
if not RunService:IsClient() then return Sfx end

local volumes = table.clone(AudioConfig.DefaultVolumes)

local function makeGroup(name: string): SoundGroup
	local g = SoundService:FindFirstChild("VG_" .. name)
	if g and g:IsA("SoundGroup") then return g end
	local ng = Instance.new("SoundGroup")
	ng.Name = "VG_" .. name
	ng.Parent = SoundService
	return ng
end
local musicGroup = makeGroup("Music")
local sfxGroup = makeGroup("Sfx")
musicGroup.Volume = volumes.Music
sfxGroup.Volume = volumes.Sfx

local holder3d = Instance.new("Folder")
holder3d.Name = "VG_Sound3D"
holder3d.Parent = workspace

---------------------------------------------------------------- one-shot sounds
local active: { [string]: number } = {}

function Sfx.Play(name: string, opts: { Position: Vector3?, Volume: number?, Pitch: number? }?): Sound?
	local def = (AudioConfig.Sfx :: any)[name]
	if not def then return nil end
	if (active[name] or 0) >= (def.Max or 4) then return nil end
	local o = opts or {}
	local s = Instance.new("Sound")
	s.Name = name
	s.SoundId = def.Id
	s.Volume = (def.Volume or 0.5) * (o.Volume or 1)
	local jitter = def.Jitter or 0
	s.PlaybackSpeed = (def.Pitch or 1) * (o.Pitch or 1) * (1 + (math.random() * 2 - 1) * jitter)
	s.SoundGroup = sfxGroup
	if def.Distortion then
		local d = Instance.new("DistortionSoundEffect")
		d.Level = def.Distortion
		d.Parent = s
	end
	-- Soft = roll off the highs (EQ) so a sound becomes a muffled "whum"; Chorus = wide, shimmering energy
	if def.Soft then
		local eq = Instance.new("EqualizerSoundEffect")
		eq.HighGain = -def.Soft
		eq.MidGain = -def.Soft * 0.4
		eq.LowGain = 4
		eq.Parent = s
	end
	if def.Chorus then
		local ch = Instance.new("ChorusSoundEffect")
		ch.Mix = def.Chorus
		ch.Depth = 0.25
		ch.Rate = 3
		ch.Parent = s
	end
	local container: Instance = SoundService
	local anchor: BasePart? = nil
	if o.Position then
		local p = Instance.new("Part")
		p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
		p.Transparency = 1; p.Size = Vector3.one * 0.1
		p.CFrame = CFrame.new(o.Position)
		p.Parent = holder3d
		s.RollOffMode = Enum.RollOffMode.InverseTapered
		s.RollOffMinDistance = AudioConfig.RollOff.Min
		s.RollOffMaxDistance = AudioConfig.RollOff.Max
		anchor = p
		container = p
	end
	s.Parent = container
	active[name] = (active[name] or 0) + 1
	local done = false
	local function finish()
		if done then return end
		done = true
		active[name] = math.max(0, (active[name] or 1) - 1)
		if anchor then anchor:Destroy() else s:Destroy() end
	end
	s.Ended:Once(finish)
	task.delay(8, finish) -- safety net if a sound never reports Ended
	s:Play()
	return s
end

---------------------------------------------------------------- music (two players, crossfaded)
local musicA = Instance.new("Sound"); musicA.Name = "VG_MusicA"; musicA.Looped = true; musicA.SoundGroup = musicGroup; musicA.Parent = SoundService
local musicB = Instance.new("Sound"); musicB.Name = "VG_MusicB"; musicB.Looped = true; musicB.SoundGroup = musicGroup; musicB.Parent = SoundService
local current: Sound? = nil
local currentId: string? = nil
local currentBase = 0
local duck = 1

local function fadeTo(s: Sound, vol: number, t: number)
	TweenService:Create(s, TweenInfo.new(t, Enum.EasingStyle.Sine), { Volume = vol }):Play()
end

function Sfx.Music(track: { Id: string, Volume: number }?)
	local t = AudioConfig.Music.FadeTime
	if track and track.Id == currentId then return end
	if current then
		local old = current
		fadeTo(old, 0, t)
		task.delay(t + 0.05, function() if old ~= current then old:Stop() end end)
	end
	if not track then current = nil; currentId = nil return end
	local nxt = (current == musicA) and musicB or musicA
	nxt:Stop()
	nxt.SoundId = track.Id
	nxt.Volume = 0
	nxt.TimePosition = 0
	nxt:Play()
	current = nxt
	currentId = track.Id
	currentBase = track.Volume
	fadeTo(nxt, currentBase * duck, t)
end

function Sfx.DuckMusic(mult: number)
	duck = mult
	if current then fadeTo(current, currentBase * duck, 0.6) end
end

function Sfx.CurrentMusic(): string?
	return currentId
end

---------------------------------------------------------------- announcer (text-to-speech -> reverb -> fader -> speakers)
local Ann = AudioConfig.Announcer
local fader: any = nil
local firstStage: any = nil
local lines: { [string]: any } = {}
local speaking: any = nil

local function wire(from: Instance, to: Instance)
	local w = Instance.new("Wire")
	w.SourceInstance = from
	w.TargetInstance = to
	w.Parent = from
end

local ok = pcall(function()
	local out = Instance.new("AudioDeviceOutput")
	out.Name = "VG_AnnouncerOut"
	out.Parent = SoundService
	fader = Instance.new("AudioFader")
	fader.Name = "VG_AnnouncerFader"
	fader.Volume = volumes.Announcer * Ann.Volume
	fader.Parent = SoundService
	wire(fader, out)
	firstStage = fader
	if Ann.Reverb then
		local rev = Instance.new("AudioReverb")
		rev.Name = "VG_AnnouncerReverb"
		pcall(function()
			rev.DecayTime = 0.7
			rev.WetLevel = -14
			rev.DryLevel = 0
		end)
		rev.Parent = SoundService
		wire(rev, fader)
		firstStage = rev
	end
end)
if not ok then warn("[Sfx] announcer audio graph unavailable; voice lines disabled") end

-- Text-to-speech generation is rate-limited per client, so lines load one at a time through a queue
-- (retrying after a pause when the limit is hit) instead of all at once.
local loadQueue: { any } = {}
local pumping = false

local function pump()
	if pumping then return end
	pumping = true
	task.spawn(function()
		local failures = 0
		while #loadQueue > 0 do
			local tts = table.remove(loadQueue, 1)
			if tts.Parent and tts.TimeLength <= 0 then
				pcall(function() tts:LoadAsync() end)
				if tts.TimeLength <= 0 then
					failures += 1
					if failures <= 40 then table.insert(loadQueue, tts) end
					task.wait(math.min(1.5 * failures, 8)) -- back off while rate-limited
				else
					failures = 0
					task.wait(1) -- pace requests so we stay under the text-to-speech rate limit
				end
			end
		end
		pumping = false
	end)
end

local function getLine(text: string): any
	local l = lines[text]
	if l then return l end
	if not firstStage then return nil end
	local tts = Instance.new("AudioTextToSpeech")
	tts.Name = "Line"
	tts.Text = text
	pcall(function()
		tts.VoiceId = Ann.VoiceId
		tts.Pitch = Ann.Pitch
		tts.Speed = Ann.Speed
	end)
	tts.Parent = SoundService
	wire(tts, firstStage)
	lines[text] = tts
	table.insert(loadQueue, tts)
	pump()
	return tts
end

-- generate voice lines ahead of time (in order: put the most common lines first)
function Sfx.PreloadLines(texts: { string })
	for _, t in ipairs(texts) do getLine(t) end
end

function Sfx.Announce(text: string)
	local tts = getLine(text)
	if not tts then return end
	if speaking and speaking ~= tts then pcall(function() speaking:Stop() end) end
	speaking = tts
	task.spawn(function()
		if tts.TimeLength <= 0 then
			-- not generated yet: jump the queue and give it a moment; a late callout is skipped, not delayed
			local i = table.find(loadQueue, tts)
			if i then table.remove(loadQueue, i) end
			table.insert(loadQueue, 1, tts)
			pump()
			local t0 = os.clock()
			while tts.TimeLength <= 0 and os.clock() - t0 < 1.5 do task.wait(0.1) end
			if tts.TimeLength <= 0 or speaking ~= tts then return end
		end
		pcall(function()
			tts.TimePosition = 0
			tts:Play()
		end)
	end)
end

function Sfx.VoiceStatus(): (number, number)
	local ready, total = 0, 0
	for _, l in pairs(lines) do total += 1; if l.TimeLength > 0 then ready += 1 end end
	return ready, total
end

---------------------------------------------------------------- volumes
function Sfx.SetVolume(kind: string, v: number)
	v = math.clamp(v, 0, 1)
	volumes[kind] = v
	if kind == "Music" then musicGroup.Volume = v
	elseif kind == "Sfx" then sfxGroup.Volume = v
	elseif kind == "Announcer" and fader then fader.Volume = v * Ann.Volume end
end

function Sfx.GetVolume(kind: string): number
	return volumes[kind] or 1
end

return Sfx
