--!strict
-- LobbyAmbience: client-only animation for the lobby decor (Workspace.Lobby.Decor, built by tools/build_lobby_decor.lua).
--   VG_Spin      : part/model spins around Y (attr Spin rad/s, optional SpinX rad/s) and bobs (attr Bob studs)
--   VG_Drone     : drone model circling (attrs CenterX, CenterZ, Radius, Height, Speed)
--   VG_Ticker    : TextLabel news ticker scrolling right-to-left
--   VG_HeroCycle : TextLabel on the lobby TV cycling through every hero (sibling "HeroRole" shows the role)
-- Purely visual, nothing replicates. Skipped while the camera is far from the lobby (i.e. in a match).
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local HeroConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("HeroConfig"))

local LOBBY_CENTER = Vector3.new(0, 0, 0)
local ACTIVE_RANGE = 450

type Item = { inst: Instance, base: CFrame, phase: number }
local spins: { [Instance]: Item } = {}
local drones: { [Instance]: Item } = {}

local function pivotOf(inst: Instance): CFrame?
	if inst:IsA("Model") then return inst:GetPivot() end
	if inst:IsA("BasePart") then return inst.CFrame end
	return nil
end
local function setPivot(inst: Instance, cf: CFrame)
	if inst:IsA("Model") then inst:PivotTo(cf) elseif inst:IsA("BasePart") then inst.CFrame = cf end
end

local function watch(tag: string, store: { [Instance]: Item })
	local function add(inst: Instance)
		local cf = pivotOf(inst)
		if cf then store[inst] = { inst = inst, base = cf, phase = math.random() * math.pi * 2 } end
	end
	for _, inst in ipairs(CollectionService:GetTagged(tag)) do add(inst) end
	CollectionService:GetInstanceAddedSignal(tag):Connect(add)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(inst) store[inst] = nil end)
end
watch("VG_Spin", spins)
watch("VG_Drone", drones)

RunService.RenderStepped:Connect(function()
	local cam = workspace.CurrentCamera
	if not cam or (cam.CFrame.Position - LOBBY_CENTER).Magnitude > ACTIVE_RANGE then return end
	local t = os.clock()
	for inst, it in pairs(spins) do
		local spin = (inst:GetAttribute("Spin") :: number?) or 0.5
		local spinX = (inst:GetAttribute("SpinX") :: number?) or 0
		local bob = (inst:GetAttribute("Bob") :: number?) or 0
		local pos = it.base.Position + Vector3.new(0, math.sin(t * 1.4 + it.phase) * bob, 0)
		setPivot(inst, CFrame.new(pos) * CFrame.Angles(0, t * spin, 0) * CFrame.Angles(t * spinX, 0, 0) * (it.base - it.base.Position))
	end
	for inst, it in pairs(drones) do
		local cx = (inst:GetAttribute("CenterX") :: number?) or 0
		local cz = (inst:GetAttribute("CenterZ") :: number?) or 0
		local r = (inst:GetAttribute("Radius") :: number?) or 20
		local h = (inst:GetAttribute("Height") :: number?) or 30
		local sp = (inst:GetAttribute("Speed") :: number?) or 0.3
		local a = t * sp + it.phase
		local pos = Vector3.new(cx + math.cos(a) * r, h + math.sin(t * 2 + it.phase) * 0.6, cz + math.sin(a) * r)
		local ahead = Vector3.new(cx + math.cos(a + 0.05 * math.sign(sp)) * r, pos.Y, cz + math.sin(a + 0.05 * math.sign(sp)) * r)
		setPivot(inst, CFrame.lookAt(pos, ahead) * CFrame.Angles(math.rad(-8), 0, math.rad(math.sin(t * 1.3) * 6)))
	end
end)

-- news ticker
task.spawn(function()
	while true do
		for _, lbl in ipairs(CollectionService:GetTagged("VG_Ticker")) do
			if lbl:IsA("TextLabel") and lbl.Parent and lbl.Parent:IsA("GuiObject") then
				local parentW = (lbl.Parent :: GuiObject).AbsoluteSize.X
				local w = lbl.AbsoluteSize.X
				if parentW > 0 and w > 0 then
					local x = lbl.Position.X.Offset - 3
					if x < -w then x = parentW end
					lbl.Position = UDim2.new(0, x, 0, 0)
				end
			end
		end
		task.wait(1 / 30)
	end
end)

-- hero spotlight on the lobby TV
task.spawn(function()
	local i = 0
	while true do
		i = i % #HeroConfig.HeroOrder + 1
		local h = HeroConfig.Heroes[HeroConfig.HeroOrder[i]]
		for _, lbl in ipairs(CollectionService:GetTagged("VG_HeroCycle")) do
			if lbl:IsA("TextLabel") and h then
				lbl.Text = h.DisplayName
				lbl.TextColor3 = h.Color
				local role = lbl.Parent and lbl.Parent:FindFirstChild("HeroRole")
				if role and role:IsA("TextLabel") then role.Text = string.upper(h.Role) .. "  -  " .. string.upper(h.Weapon) end
			end
		end
		task.wait(3.5)
	end
end)
