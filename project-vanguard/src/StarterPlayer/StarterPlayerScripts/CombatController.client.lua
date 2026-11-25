-- CombatController: weapon input, first-person viewmodel, recoil and all combat visuals.
-- It never decides damage: it sends Fire(origin, direction, claimedHitPart) and the server validates.
-- Controls (PC): Left Mouse = fire, R = reload. Abilities (Shift/E/Q) arrive in Phase 3.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local WeaponConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("WeaponConfig"))
local SkinConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("SkinConfig"))
local SkinVisuals = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("SkinVisuals"))
local Sfx = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Sfx"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local FireRemote = Remotes:WaitForChild("Fire")
local ReloadRemote = Remotes:WaitForChild("Reload")
local CombatFx = Remotes:WaitForChild("CombatFx")

local Controls = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ControlConfig")).Binds

local fxFolder = Instance.new("Folder")
fxFolder.Name = "LocalCombatFx"
fxFolder.Parent = workspace

local mouseDown = false
local lastShot = 0
local bursting = false
local localAmmo = 0
local recoil = 0
-- aiming down sights (hold right-click / mobile AIM button)
local aimHeld = false
local aimBlend = 0 -- 0 = hip, 1 = fully aimed
local aimSent = false
local fovTouched = false
local SetAim = Remotes:WaitForChild("SetAim", 10)
local HIP_FOV = 80
local viewmodel: Model? = nil
local viewmodelWeapon: string? = nil
-- Phase 7 viewmodel animation state
local equipStart = 0
local reloadBlend = 0
local castKick = 0

local function getWeapon()
	local id = player:GetAttribute("WeaponId")
	return id and WeaponConfig.Weapons[id] or nil
end

local function getHumanoid(): Humanoid?
	local char = player.Character
	return char and char:FindFirstChildOfClass("Humanoid")
end

local function canAttack(): boolean
	local hum = getHumanoid()
	return player:GetAttribute("CombatEnabled") == true and hum ~= nil and hum.Health > 0 and getWeapon() ~= nil
end

---------------------------------------------------------------- visuals
local function fxPart(size: Vector3, cf: CFrame, color: Color3, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Size = size
	p.CFrame = cf
	if shape then p.Shape = shape end
	p.Parent = fxFolder
	return p
end

local function fade(p: BasePart, t: number, grow: Vector3?)
	local goal: { [string]: any } = { Transparency = 1 }
	if grow then goal.Size = grow end
	TweenService:Create(p, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal):Play()
	Debris:AddItem(p, t + 0.05)
end

local function tracer(from: Vector3, to: Vector3, color: Color3, width: number)
	local dist = (to - from).Magnitude
	if dist < 0.5 then return end
	local cf = CFrame.lookAt((from + to) / 2, to)
	-- bright white-hot core + wider coloured glow around it
	local core = fxPart(Vector3.new(width * 0.5, width * 0.5, dist), cf, color:Lerp(Color3.new(1, 1, 1), 0.6))
	core.Transparency = 0.05
	fade(core, 0.1)
	local glow = fxPart(Vector3.new(width * 2.6, width * 2.6, dist), cf, color)
	glow.Transparency = 0.7
	fade(glow, 0.16)
end

-- Phase 7: neon low-poly shards. Thin glowing blocks fly out from a point and shrink away.
-- dir = main direction (nil = all around), spread 0..1 = how far they wander off it.
local function shards(pos: Vector3, dir: Vector3?, color: Color3, count: number, dist: number, size: number, spread: number?)
	for _ = 1, count do
		local rnd = Vector3.new(math.random() * 2 - 1, math.random() * 2 - 1, math.random() * 2 - 1)
		if rnd.Magnitude < 0.05 then rnd = Vector3.yAxis end
		local d = dir and (dir.Unit + rnd.Unit * (spread or 0.6)) or rnd
		d = d.Unit
		local s = size * (0.6 + math.random() * 0.7)
		local p = fxPart(Vector3.new(s * 0.45, s * 0.45, s * 1.8), CFrame.lookAt(pos, pos + d) * CFrame.Angles(0, 0, math.random() * 3), color)
		local travel = dist * (0.6 + math.random() * 0.6)
		local goal = CFrame.lookAt(pos + d * travel, pos + d * (travel + 1)) * CFrame.Angles(0, 0, math.random() * 3)
		local t = 0.14 + math.random() * 0.12
		TweenService:Create(p, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = goal, Size = Vector3.one * 0.03, Transparency = 1 }):Play()
		Debris:AddItem(p, t + 0.05)
	end
end

local function flash(pos: Vector3, color: Color3, size: number, dir: Vector3?)
	local p = fxPart(Vector3.one * size * 0.7, CFrame.new(pos) * CFrame.Angles(math.random() * 3, math.random() * 3, 0), color)
	local light = Instance.new("PointLight")
	light.Color = color; light.Range = 12; light.Brightness = 5; light.Parent = p
	fade(p, 0.07)
	-- star-shaped muzzle flash: two crossed neon blades
	if dir then
		local base = CFrame.lookAt(pos, pos + dir)
		for i = 0, 1 do
			local blade = fxPart(Vector3.new(size * 0.12, size * 1.1, size * 0.12), base * CFrame.Angles(0, 0, math.rad(45 + i * 90)), color:Lerp(Color3.new(1, 1, 1), 0.4))
			blade.Transparency = 0.1
			fade(blade, 0.06)
		end
	end
	shards(pos, dir, color, 4, 1.6, size * 0.35, 0.45)
end

local function impact(pos: Vector3, color: Color3, radius: number)
	local size = radius > 0 and radius * 2 or 1.2
	local p = fxPart(Vector3.one * (size * 0.3), CFrame.new(pos), color, Enum.PartType.Ball)
	p.Transparency = radius > 0 and 0.2 or 0.4
	fade(p, radius > 0 and 0.35 or 0.15, Vector3.one * size)
	if radius > 0 then
		shards(pos, nil, color, 10, radius * 1.1, 0.7)
	else
		shards(pos, nil, color, 4, 1.6, 0.22)
	end
end

local function slash(origin: Vector3, dir: Vector3, color: Color3)
	local cf = CFrame.lookAt(origin, origin + dir)
	for i = -2, 2 do
		local seg = fxPart(Vector3.new(0.15, 0.15, 2.2), cf * CFrame.Angles(0, math.rad(i * 18), 0) * CFrame.new(0, 0, -3.5), color)
		seg.Transparency = 0.2
		fade(seg, 0.18)
	end
end

-- visual-only projectiles (the server simulates the real ones)
type VisualProjectile = { Part: BasePart, Pos: Vector3, Vel: Vector3, Travelled: number, Range: number }
local visuals: { [any]: VisualProjectile } = {}
local visualKey = 0

local function visualParams(): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local list: { Instance } = { fxFolder, workspace.CurrentCamera }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then table.insert(list, p.Character) end
	end
	params.FilterDescendantsInstances = list
	return params
end

-- bullet / projectile colour: a Legendary skin tints the shooter's tracers (purely visual)
local function tracerColorFor(userId: number?, w: any): Color3
	local shooter = userId and Players:GetPlayerByUserId(userId) or nil
	return SkinVisuals.TracerColor(SkinConfig.EquippedFor(shooter, w.Id), w.TracerColor)
end

local function startVisualProjectile(key: any, from: Vector3, vel: Vector3, w: any, color: Color3?)
	local col = color or w.TracerColor
	local p = fxPart(Vector3.one * (w.ProjectileSize or 0.5), CFrame.new(from), col, Enum.PartType.Ball)
	local light = Instance.new("PointLight")
	light.Color = col; light.Range = 6; light.Brightness = 2; light.Parent = p
	visuals[key] = { Part = p, Pos = from, Vel = vel, Travelled = 0, Range = w.Range }
end

local function stopVisual(key: any)
	local v = visuals[key]
	if v then
		v.Part:Destroy()
		visuals[key] = nil
	end
end

RunService.Heartbeat:Connect(function(dt)
	if next(visuals) == nil then return end
	local params = visualParams()
	for key, v in pairs(visuals) do
		local step = v.Vel * dt
		local hit = workspace:Raycast(v.Pos, step, params)
		if hit or v.Travelled >= v.Range then
			stopVisual(key)
		else
			v.Pos += step
			v.Travelled += step.Magnitude
			v.Part.CFrame = CFrame.new(v.Pos)
		end
	end
end)

---------------------------------------------------------------- viewmodel
local function destroyViewmodel()
	if viewmodel then viewmodel:Destroy() end
	viewmodel = nil
	viewmodelWeapon = nil
end

local HeroAssets = ReplicatedStorage:WaitForChild("HeroAssets", 5)
local VIEWMODEL_SCALE = 0.55

-- First-person weapon from the ForgeGUI 3D model (pivot = grip, -Z = forward).
local function buildModelViewmodel(w: any, template: Model): Model
	local model = Instance.new("Model")
	model.Name = "Viewmodel"
	local function addCopy(offset: CFrame)
		local c = template:Clone()
		SkinVisuals.Apply(c, SkinConfig.EquippedFor(player, w.Id)) -- equipped skin on the first-person weapon
		for _, d in ipairs(c:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = true; d.CanCollide = false; d.CanQuery = false; d.CanTouch = false; d.CastShadow = false
			end
		end
		c:ScaleTo(VIEWMODEL_SCALE)
		c:PivotTo(offset)
		for _, d in ipairs(c:GetChildren()) do d.Parent = model end
		c:Destroy()
	end
	addCopy(CFrame.new())
	if w.Id == "EnergyBlades" then addCopy(CFrame.new(-1.1, 0, 0)) end -- second blade in the left hand
	local muzzle = Instance.new("Part")
	muzzle.Name = "Muzzle"; muzzle.Size = Vector3.one * 0.1; muzzle.Transparency = 1
	muzzle.Anchored = true; muzzle.CanCollide = false; muzzle.CanQuery = false; muzzle.CanTouch = false
	muzzle.CFrame = CFrame.new(0, 0, -(template:GetAttribute("MuzzleDistance") or 1) * VIEWMODEL_SCALE)
	muzzle.Parent = model
	local pivot = Instance.new("Part")
	pivot.Name = "Pivot"; pivot.Size = Vector3.one * 0.1; pivot.Transparency = 1
	pivot.Anchored = true; pivot.CanCollide = false; pivot.CanQuery = false; pivot.CanTouch = false
	pivot.CFrame = CFrame.new()
	pivot.Parent = model
	local fill = Instance.new("PointLight") -- keeps the weapon readable on dark maps
	fill.Range = 5; fill.Brightness = 1.4; fill.Shadows = false; fill.Parent = pivot
	model.PrimaryPart = pivot
	return model
end

local function buildViewmodel(w: any)
	destroyViewmodel()
	local template = HeroAssets and HeroAssets:FindFirstChild("Weapons") and HeroAssets.Weapons:FindFirstChild(w.Id)
	if template then
		local m = buildModelViewmodel(w, template :: Model)
		m.Parent = workspace.CurrentCamera
		viewmodel = m
		viewmodelWeapon = w.Id
		equipStart = os.clock()
		Sfx.Play("Equip")
		return
	end
	-- fallback: simple block weapon if the 3D model is missing
	local model = Instance.new("Model")
	model.Name = "Viewmodel"
	local function vmPart(name: string, size: Vector3, offset: CFrame, color: Color3, mat: Enum.Material)
		local p = Instance.new("Part")
		p.Name = name; p.Size = size; p.Color = color; p.Material = mat
		p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.CastShadow = false
		p.CFrame = offset
		p.Parent = model
		return p
	end
	local s = w.ViewSize * 0.5 -- viewmodel is drawn close to the camera, so it is scaled down
	local body = vmPart("Body", s, CFrame.new(), Color3.fromRGB(35, 38, 48), Enum.Material.Metal)
	vmPart("Glow", Vector3.new(s.X * 0.4, 0.03, s.Z * 0.6), CFrame.new(0, s.Y / 2, 0), w.Color, Enum.Material.Neon)
	vmPart("Grip", Vector3.new(s.X * 0.8, 0.6, 0.35), CFrame.new(0, -s.Y / 2 - 0.25, s.Z * 0.2), Color3.fromRGB(25, 25, 32), Enum.Material.Metal)
	local muzzle = vmPart("Muzzle", Vector3.new(0.1, 0.1, 0.1), CFrame.new(0, 0, -s.Z / 2), w.Color, Enum.Material.Neon)
	muzzle.Transparency = 1
	if w.Type == "Melee" then
		-- second blade for the dual-blade weapon
		vmPart("Blade2", s, CFrame.new(-1.1, 0, 0), Color3.fromRGB(35, 38, 48), Enum.Material.Metal)
		vmPart("Glow2", Vector3.new(s.X * 0.4, 0.03, s.Z * 0.9), CFrame.new(-1.1, s.Y / 2, 0), w.Color, Enum.Material.Neon)
	end
	model.PrimaryPart = body
	model.Parent = workspace.CurrentCamera
	viewmodel = model
	viewmodelWeapon = w.Id
end

local function muzzlePosition(): Vector3
	if viewmodel and viewmodel:FindFirstChild("Muzzle") then
		return (viewmodel :: any).Muzzle.Position
	end
	return workspace.CurrentCamera.CFrame.Position
end

-- rebuild the first-person weapon when the equipped skin changes
player:GetAttributeChangedSignal("EquippedSkins"):Connect(function()
	if viewmodel then destroyViewmodel() end
end)

RunService.RenderStepped:Connect(function(dt)
	local w = getWeapon()
	local hum = getHumanoid()
	local show = w ~= nil and hum ~= nil and hum.Health > 0 and player.CameraMode == Enum.CameraMode.LockFirstPerson
	if show then
		if viewmodelWeapon ~= w.Id then buildViewmodel(w) end
		recoil = math.max(0, recoil - dt * 6)
		local cam = workspace.CurrentCamera
		local bob = hum.MoveDirection.Magnitude > 0 and math.sin(os.clock() * 9) * 0.04 or 0
		local offset = CFrame.new(0.8, -0.62 + bob, -1.55 + recoil * 0.15) * CFrame.Angles(recoil * 0.1, math.rad(9), 0)
		if w.Type == "Melee" then offset = CFrame.new(0.6, -0.55 + bob, -1.4) * CFrame.Angles(math.rad(-20) + recoil * 0.5, math.rad(10), 0) end
		-- Phase 7 animation layers: equip swing-in, reload dip + tilt, ability cast push, walk sway
		local reloading = player:GetAttribute("Reloading") == true
		reloadBlend += ((reloading and 1 or 0) - reloadBlend) * math.min(dt * 12, 1)
		castKick = math.max(0, castKick - dt * 4)
		local e = math.clamp((os.clock() - equipStart) / 0.35, 0, 1)
		local equip = 1 - (1 - e) ^ 3
		local moving = hum.MoveDirection.Magnitude > 0
		local sway = moving and math.cos(os.clock() * 4.5) * 0.03 or 0
		offset = offset
			* CFrame.new(sway, -0.7 * (1 - equip) - 0.3 * reloadBlend, 0.1 * reloadBlend - 0.25 * castKick)
			* CFrame.Angles(math.rad(-55) * (1 - equip) + math.rad(-30) * reloadBlend + math.rad(12) * castKick, 0, math.rad(28) * reloadBlend)
		-- aiming: slide the gun to the centre of the screen (and hide it behind the sniper scope)
		if aimBlend > 0 and w.Type ~= "Melee" then
			local centre = CFrame.new(0, -0.42, -1.25 + recoil * 0.12) * CFrame.Angles(recoil * 0.06, 0, 0)
			offset = offset:Lerp(centre, aimBlend)
			if w.Scope and aimBlend > 0.85 then offset *= CFrame.new(0, -3, 0) end
		end
		local vm: Model = viewmodel :: Model
		vm:PivotTo(cam.CFrame * offset)
	elseif viewmodel then
		destroyViewmodel()
	end
end)

---------------------------------------------------------------- firing
local function clientParams(): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character :: Instance, fxFolder, workspace.CurrentCamera }
	return params
end

local function spreadDirection(look: Vector3, degrees: number): Vector3
	if degrees <= 0 then return look end
	local angle = math.rad(degrees) * math.sqrt(math.random())
	local theta = math.random() * math.pi * 2
	return (CFrame.lookAt(Vector3.zero, look) * CFrame.Angles(math.cos(theta) * angle, math.sin(theta) * angle, 0)).LookVector
end

local function requestReload()
	local w = getWeapon()
	if not w or w.MagSize <= 0 or player:GetAttribute("Reloading") then return end
	if localAmmo >= w.MagSize then return end
	ReloadRemote:FireServer()
end

local function fireOnce(): boolean
	local w = getWeapon()
	if not w or not canAttack() then return false end
	if w.MagSize > 0 then
		if player:GetAttribute("Reloading") then return false end
		if localAmmo <= 0 then requestReload() return false end
		localAmmo -= 1
	end
	local cam = workspace.CurrentCamera
	local origin = cam.CFrame.Position
	local dir = spreadDirection(cam.CFrame.LookVector, (w.Spread or 0) * (1 - aimBlend * (1 - WeaponConfig.Aim.SpreadMult)))
	local muzzle = muzzlePosition()
	local tcol = tracerColorFor(player.UserId, w)

	if w.Type == "Hitscan" and w.Pellets then
		-- shotgun: draw the same fixed pellet pattern the server uses; the server decides the hits
		for _, d in ipairs(WeaponConfig.PelletDirs(dir, w)) do
			local result = workspace:Raycast(origin, d * w.Range, clientParams())
			local to = result and result.Position or origin + d * w.Range
			tracer(muzzle, to, tcol, 0.05)
			if result then impact(to, tcol, 0) end
		end
		FireRemote:FireServer(origin, dir)
	elseif w.Type == "Hitscan" then
		local result = workspace:Raycast(origin, dir * w.Range, clientParams())
		local to = result and result.Position or origin + dir * w.Range
		tracer(muzzle, to, tcol, w.Damage >= 50 and 0.14 or 0.06)
		if result then impact(to, tcol, 0) end
		FireRemote:FireServer(origin, dir, result and result.Instance or nil)
	elseif w.Type == "Projectile" then
		FireRemote:FireServer(origin, dir)
		visualKey += 1
		startVisualProjectile("local" .. visualKey, muzzle, dir * w.ProjectileSpeed, w, tcol)
	elseif w.Type == "Melee" then
		FireRemote:FireServer(origin, dir)
		slash(origin - Vector3.new(0, 0.5, 0), Vector3.new(dir.X, 0, dir.Z), w.Color)
	end
	if w.Type ~= "Melee" then flash(muzzle, tcol, 0.6, dir) end
	Sfx.Play("Fire_" .. w.Id)

	-- recoil: viewmodel kick + small camera kick (bigger for heavy single shots)
	local kick = (w.Damage >= 50 or w.Pellets) and 1.6 or (w.Type == "Melee" and 0 or 0.35)
	recoil = math.min(recoil + (w.Type == "Melee" and 1 or 0.6), 2)
	if kick > 0 then
		cam.CFrame = cam.CFrame * CFrame.Angles(math.rad(kick), 0, 0)
	end
	return true
end

local function tryTrigger()
	local w = getWeapon()
	if not w or not canAttack() then return end
	local t = os.clock()
	-- ultimates like Overdrive raise fire rate; the server publishes the multiplier
	local cooldown = w.Cooldown / math.max(player:GetAttribute("FireRateMult") or 1, 0.1)
	if w.FireMode == "Burst" then
		if bursting or t - lastShot < cooldown then return end
		bursting = true
		task.spawn(function()
			for i = 1, w.BurstCount do
				if not fireOnce() then break end
				if i < w.BurstCount then task.wait(w.BurstInterval) end
			end
			lastShot = os.clock()
			bursting = false
		end)
	elseif t - lastShot >= cooldown then
		if fireOnce() then lastShot = t end
	end
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.UserInputType == Controls.Fire then
		mouseDown = true
		tryTrigger()
	elseif input.KeyCode == Controls.Reload then
		requestReload()
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Controls.Fire then mouseDown = false end
	if input.UserInputType == Enum.UserInputType.MouseButton2 then aimHeld = false end
end)
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.UserInputType == Enum.UserInputType.MouseButton2 then aimHeld = true end
end)

-- sniper scope overlay: black frame with a round lens and a thin crosshair
local scopeGui = Instance.new("ScreenGui")
scopeGui.Name = "ScopeUI"; scopeGui.IgnoreGuiInset = true; scopeGui.ResetOnSpawn = false; scopeGui.DisplayOrder = 3; scopeGui.Enabled = false
scopeGui.Parent = player:WaitForChild("PlayerGui")
local lens = Instance.new("Frame")
lens.Name = "Lens"; lens.AnchorPoint = Vector2.new(0.5, 0.5); lens.Position = UDim2.fromScale(0.5, 0.5)
lens.Size = UDim2.fromScale(0.8, 0.8); lens.BackgroundTransparency = 1; lens.Parent = scopeGui
local lensAspect = Instance.new("UIAspectRatioConstraint"); lensAspect.Parent = lens
local ring = Instance.new("UIStroke"); ring.Thickness = 3000; ring.Color = Color3.new(0, 0, 0); ring.Parent = lens -- huge stroke = black outside the lens
local lensCorner = Instance.new("UICorner"); lensCorner.CornerRadius = UDim.new(0.5, 0); lensCorner.Parent = lens
local glassRim = Instance.new("Frame"); glassRim.Size = UDim2.fromScale(1, 1); glassRim.BackgroundTransparency = 1; glassRim.Parent = lens
local rimStroke = Instance.new("UIStroke"); rimStroke.Thickness = 3; rimStroke.Color = Color3.fromRGB(160, 90, 255); rimStroke.Parent = glassRim
local rimCorner = Instance.new("UICorner"); rimCorner.CornerRadius = UDim.new(0.5, 0); rimCorner.Parent = glassRim
for _, sz in ipairs({ { UDim2.new(1, 0, 0, 1), UDim2.fromScale(0, 0.5) }, { UDim2.new(0, 1, 1, 0), UDim2.fromScale(0.5, 0) } }) do
	local line = Instance.new("Frame"); line.BorderSizePixel = 0; line.BackgroundColor3 = Color3.new(0, 0, 0); line.BackgroundTransparency = 0.2
	line.Size = sz[1]; line.Position = sz[2]; line.Parent = lens
end
local dot = Instance.new("Frame"); dot.AnchorPoint = Vector2.new(0.5, 0.5); dot.Position = UDim2.fromScale(0.5, 0.5); dot.Size = UDim2.fromOffset(5, 5)
dot.BackgroundColor3 = Color3.fromRGB(255, 60, 90); dot.BorderSizePixel = 0; dot.Parent = lens
local dotCorner = Instance.new("UICorner"); dotCorner.CornerRadius = UDim.new(1, 0); dotCorner.Parent = dot

-- aim blend, zoom, server speed penalty
RunService.RenderStepped:Connect(function(dt)
	local w = getWeapon()
	local hum = getHumanoid()
	local canAim = w ~= nil and not w.NoAim and w.Type ~= "Melee" and hum ~= nil and hum.Health > 0
		and player.CameraMode == Enum.CameraMode.LockFirstPerson and player:GetAttribute("Reloading") ~= true
	local want = aimHeld and canAim
	aimBlend += ((want and 1 or 0) - aimBlend) * math.min(dt * 14, 1)
	if aimBlend < 0.01 then aimBlend = 0 end
	if want ~= aimSent and SetAim then
		aimSent = want
		SetAim:FireServer(want)
	end
	local cam = workspace.CurrentCamera
	if aimBlend > 0 and w then
		local target = w.AimFov or WeaponConfig.Aim.Fov
		cam.FieldOfView = HIP_FOV + (target - HIP_FOV) * aimBlend
		fovTouched = true
	elseif fovTouched then
		fovTouched = false
		if player.CameraMode == Enum.CameraMode.LockFirstPerson then cam.FieldOfView = HIP_FOV end
	end
	scopeGui.Enabled = w ~= nil and w.Scope == true and aimBlend > 0.85
end)

-- Phase 9: touch buttons (MobileControls) feed the same trigger + reload logic
local InputBridge = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("InputBridge"))
InputBridge.FireChanged:Connect(function(down: boolean)
	mouseDown = down
	if down then tryTrigger() end
end)
InputBridge.Reload:Connect(function() requestReload() end)
InputBridge.AimChanged:Connect(function(on: boolean) aimHeld = on end)

RunService.Heartbeat:Connect(function()
	if not mouseDown then return end
	local w = getWeapon()
	if w and (w.FireMode == "Auto" or w.FireMode == "Burst") then tryTrigger() end
end)

---------------------------------------------------------------- ammo sync with server truth
local function syncAmmo()
	local a = player:GetAttribute("Ammo")
	if typeof(a) == "number" then localAmmo = a end
end
player:GetAttributeChangedSignal("Ammo"):Connect(function()
	local a = player:GetAttribute("Ammo")
	if typeof(a) ~= "number" then return end
	local w = getWeapon()
	-- Lower = server consumed/rejected shots. Higher is only accepted on a full magazine (reload/respawn),
	-- so a late update never hands back shots we already fired locally.
	if a < localAmmo or (w and a >= w.MagSize) then localAmmo = a end
end)
player:GetAttributeChangedSignal("Reloading"):Connect(function()
	if player:GetAttribute("Reloading") then
		Sfx.Play("Reload")
	else
		syncAmmo()
		if viewmodel then Sfx.Play("ReloadDone") end
	end
end)
-- viewmodel push when the server accepts a Skill / Ultimate
player:GetAttributeChangedSignal("Ready_Skill"):Connect(function()
	local readyAt = player:GetAttribute("Ready_Skill")
	if typeof(readyAt) == "number" and readyAt > workspace:GetServerTimeNow() + 0.2 then castKick = 1 end
end)
player:GetAttributeChangedSignal("UltActive"):Connect(function()
	if player:GetAttribute("UltActive") == true then castKick = 1 end
end)
player:GetAttributeChangedSignal("WeaponId"):Connect(syncAmmo)
player.CharacterAdded:Connect(function()
	mouseDown = false
	bursting = false
	task.wait(0.2)
	syncAmmo()
end)

---------------------------------------------------------------- effects from other players (server broadcast)
CombatFx.OnClientEvent:Connect(function(data)
	if typeof(data) ~= "table" then return end
	local w = WeaponConfig.Weapons[data.Weapon]
	if not w then return end
	local mine = data.Shooter == player.UserId
	local tcol = tracerColorFor(data.Shooter, w)
	if data.Type == "Shot" and not mine and typeof(data.Pellets) == "table" then
		for _, to in ipairs(data.Pellets) do
			if typeof(to) == "Vector3" then
				tracer(data.From, to, tcol, 0.05)
				impact(to, tcol, 0)
			end
		end
	elseif data.Type == "Shot" and not mine then
		tracer(data.From, data.To, tcol, w.Damage >= 50 and 0.14 or 0.06)
		impact(data.To, tcol, 0)
	elseif data.Type == "Projectile" and not mine then
		startVisualProjectile(data.Id, data.From, data.Velocity, w, tcol)
	elseif data.Type == "Impact" then
		stopVisual(data.Id)
		impact(data.Position, tcol, data.Radius or 0)
	elseif data.Type == "Melee" and not mine then
		slash(data.From, data.Dir, w.Color)
	end
end)
