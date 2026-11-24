-- DeathFXController (Phase 7): "digital dissolve" when any combatant is eliminated.
-- The body turns into its team colour from the feet up and breaks into small neon pixel cubes that drift
-- upward and fade. Runs on every client for every character (players + training dummies). Cosmetic only:
-- it changes local copies of the parts; the server still owns the character and its respawn.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameConfig = require(Modules:WaitForChild("GameConfig"))
local Sfx = require(Modules:WaitForChild("Sfx"))

local DURATION = 1.1
local PIXELS_PER_PART = 3
local MAX_PIXELS = 40
local NEUTRAL = Color3.fromRGB(255, 60, 60)

local fx = Instance.new("Folder")
fx.Name = "DeathFx"
fx.Parent = workspace

local function teamColor(model: Model): Color3
	local plr = Players:GetPlayerFromCharacter(model)
	local team = plr and plr:GetAttribute("Team") or model:GetAttribute("Team")
	local t = typeof(team) == "string" and GameConfig.Teams[team]
	return t and t.Color or NEUTRAL
end

local function pixel(at: Vector3, color: Color3)
	local p = Instance.new("Part")
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	local s = 0.2 + math.random() * 0.25
	p.Size = Vector3.new(s, s, s)
	p.CFrame = CFrame.new(at) * CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
	p.Parent = fx
	local rise = Vector3.new((math.random() - 0.5) * 2.5, 2.5 + math.random() * 3, (math.random() - 0.5) * 2.5)
	local t = 0.7 + math.random() * 0.6
	TweenService:Create(p, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		CFrame = p.CFrame * CFrame.Angles(math.random() * 3, math.random() * 3, 0) + rise,
		Size = Vector3.one * 0.05,
		Transparency = 1,
	}):Play()
	Debris:AddItem(p, t + 0.05)
end

local function dissolve(model: Model)
	if model:GetAttribute("Dissolving") then return end
	model:SetAttribute("Dissolving", true) -- local only (client attribute)
	local color = teamColor(model)
	local parts: { BasePart } = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" and d.Transparency < 1 then
			table.insert(parts, d)
		elseif d:IsA("Decal") or d:IsA("Texture") then
			TweenService:Create(d, TweenInfo.new(0.3), { Transparency = 1 }):Play()
		elseif d:IsA("SurfaceAppearance") then
			d:Destroy() -- lets the team colour show through
		elseif d:IsA("BillboardGui") or d:IsA("ParticleEmitter") or d:IsA("Beam") then
			pcall(function() (d :: any).Enabled = false end)
		end
	end
	if #parts == 0 then return end
	-- feet first
	local minY, maxY = math.huge, -math.huge
	for _, p in ipairs(parts) do minY = math.min(minY, p.Position.Y); maxY = math.max(maxY, p.Position.Y) end
	local span = math.max(maxY - minY, 0.1)

	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	Sfx.Play("Death", { Position = root and root.Position or parts[1].Position })

	local budget = MAX_PIXELS
	for _, p in ipairs(parts) do
		local delayT = ((p.Position.Y - minY) / span) * (DURATION * 0.5)
		task.delay(delayT, function()
			if not p.Parent then return end
			p.Material = Enum.Material.Neon
			p.Color = color
			if p:IsA("MeshPart") then pcall(function() (p :: any).TextureID = "" end) end
			local sm = p:FindFirstChildOfClass("SpecialMesh")
			if sm then sm.TextureId = "" end
			TweenService:Create(p, TweenInfo.new(DURATION * 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1 }):Play()
			for _ = 1, PIXELS_PER_PART do
				if budget <= 0 then break end
				budget -= 1
				local half = p.Size * 0.5
				local offset = Vector3.new((math.random() * 2 - 1) * half.X, (math.random() * 2 - 1) * half.Y, (math.random() * 2 - 1) * half.Z)
				pixel((p.CFrame * CFrame.new(offset)).Position, color)
			end
		end)
	end
end

local function watch(model: Model)
	local hum = model:FindFirstChildOfClass("Humanoid") or model:WaitForChild("Humanoid", 10)
	if not hum or not hum:IsA("Humanoid") then return end
	hum.Died:Connect(function() dissolve(model) end)
end

-- players
local function onPlayer(p: Player)
	if p.Character then task.spawn(watch, p.Character) end
	p.CharacterAdded:Connect(watch)
end
for _, p in ipairs(Players:GetPlayers()) do onPlayer(p) end
Players.PlayerAdded:Connect(onPlayer)

-- training dummies and any other humanoid model added at runtime (not player characters)
local function onModel(m: Instance)
	if m:IsA("Humanoid") and m.Parent and m.Parent:IsA("Model") and not Players:GetPlayerFromCharacter(m.Parent) then
		local model = m.Parent :: Model
		m.Died:Connect(function() dissolve(model) end)
	end
end
for _, d in ipairs(workspace:GetDescendants()) do onModel(d) end
workspace.DescendantAdded:Connect(onModel)
