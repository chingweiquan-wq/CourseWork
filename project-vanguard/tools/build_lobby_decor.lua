-- build_lobby_decor.lua  (run in Studio's Edit datamodel; safe to re-run)
-- Organises the lobby into clear zones and fills it with neon sci-fi decor.
--   Centre  : SPAWN PLAZA  - hologram centrepiece, spawns in a ring around it
--   North   : ARMORY (west)  |  SHOP (centre)  |  PLAY / vote pads (east)
--   South   : HEROES (west)  |  HALL OF FAME (centre)  |  LOUNGE (east)
-- Everything new lives in Workspace.Lobby.Decor. Existing models are only moved, never deleted.
-- Animation (spin / bob / drones / TV) is client-side in StarterPlayerScripts/LobbyAmbience.
local CS = game:GetService("CollectionService")
local RS = game:GetService("ReplicatedStorage")
local Lobby = workspace.Lobby
local P = Lobby.Hangar.PermaLobby
local HeroConfig = require(RS.Modules.HeroConfig)
local GameConfig = require(RS.Modules.GameConfig)

local old = Lobby:FindFirstChild("Decor")
if old then old:Destroy() end
local D = Instance.new("Model")
D.Name = "Decor"
D.Parent = Lobby
local function group(name: string)
	local m = Instance.new("Model"); m.Name = name; m.Parent = D; return m
end

local C = {
	cyan = Color3.fromRGB(0, 220, 255), mag = Color3.fromRGB(255, 60, 200), gold = Color3.fromRGB(255, 200, 60),
	purple = Color3.fromRGB(170, 90, 255), green = Color3.fromRGB(90, 255, 140), orange = Color3.fromRGB(255, 140, 40),
	red = Color3.fromRGB(255, 60, 70), metal = Color3.fromRGB(30, 32, 44), dark = Color3.fromRGB(14, 15, 22),
	cable = Color3.fromRGB(55, 58, 70),
}
local CEILING = 48.5
local FONT = Font.fromEnum(Enum.Font.GothamBlack)
local FONT2 = Font.fromEnum(Enum.Font.GothamBold)

local floorParams = RaycastParams.new()
floorParams.FilterType = Enum.RaycastFilterType.Include
floorParams.FilterDescendantsInstances = { P.Floors }
local function floorY(x: number, z: number): number
	local r = workspace:Raycast(Vector3.new(x, 45, z), Vector3.new(0, -80, 0), floorParams)
	return r and r.Position.Y or 0
end

local function part(parent, size, cf, color, mat, extra)
	local p = Instance.new("Part")
	p.Anchored = true; p.Size = size; p.CFrame = cf; p.Color = color
	p.Material = mat or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
	p.CastShadow = false
	if extra then for k, v in pairs(extra) do (p :: any)[k] = v end end
	p.Parent = parent
	return p
end
local function neon(parent, size, cf, color, extra)
	local e = extra or {}
	if e.CanCollide == nil then e.CanCollide = false end
	e.CanQuery = false; e.CanTouch = false
	return part(parent, size, cf, color, Enum.Material.Neon, e)
end
local function text(p: BasePart, face, str: string, color: Color3, o: any?)
	o = o or {}
	local g = Instance.new("SurfaceGui")
	g.Face = face; g.LightInfluence = 0; g.Brightness = o.bright or 1.6
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud; g.PixelsPerStud = o.pps or 20 -- low on purpose: keeps all signs inside the SurfaceGui texture budget
	g.MaxDistance = 400
	g.Parent = p
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = o.size or UDim2.fromScale(1, 1); t.Position = o.pos or UDim2.new()
	t.TextScaled = true; t.FontFace = o.font or FONT; t.Text = str; t.TextColor3 = color
	t.Parent = g
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.06, 0); pad.PaddingRight = UDim.new(0.06, 0)
	pad.PaddingTop = UDim.new(0.14, 0); pad.PaddingBottom = UDim.new(0.14, 0)
	pad.Parent = t
	return g, t
end
local function frame(parent, cf: CFrame, w: number, h: number, depth: number, color: Color3, th: number?)
	th = th or 0.35
	neon(parent, Vector3.new(w + th, th, depth), cf * CFrame.new(0, h / 2, 0), color)
	neon(parent, Vector3.new(w + th, th, depth), cf * CFrame.new(0, -h / 2, 0), color)
	neon(parent, Vector3.new(th, h, depth), cf * CFrame.new(w / 2, 0, 0), color)
	neon(parent, Vector3.new(th, h, depth), cf * CFrame.new(-w / 2, 0, 0), color)
end
local function cable(parent, from: Vector3)
	local len = CEILING - from.Y
	part(parent, Vector3.new(0.15, len, 0.15), CFrame.new(from + Vector3.new(0, len / 2, 0)), C.cable, Enum.Material.Metal, { CanCollide = false, CanQuery = false })
end
-- hanging zone sign, readable from both sides; `face` = direction the front looks toward the readers
local function hangSign(name: string, str: string, color: Color3, pos: Vector3, width: number, face: Vector3)
	local m = group("Sign_" .. name)
	local h = 5.5
	local cf = CFrame.lookAt(pos, pos + face)
	local back = part(m, Vector3.new(width, h, 0.6), cf, C.dark, Enum.Material.Metal, { CanCollide = false, CanQuery = false })
	frame(m, cf, width, h, 0.7, color)
	text(back, Enum.NormalId.Front, str, color)
	text(back, Enum.NormalId.Back, str, color)
	for _, sx in ipairs({ -width / 2 + 1.5, width / 2 - 1.5 }) do cable(m, (cf * CFrame.new(sx, h / 2, 0)).Position) end
	return m
end
-- corner brackets marking a zone on the floor
local function brackets(parent, cx: number, cz: number, w: number, d: number, color: Color3)
	local y = floorY(cx, cz) + 0.06
	local L = 6
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			local x, z = cx + sx * w / 2, cz + sz * d / 2
			neon(parent, Vector3.new(L, 0.12, 0.6), CFrame.new(x - sx * L / 2, y, z), color)
			neon(parent, Vector3.new(0.6, 0.12, L), CFrame.new(x, y, z - sz * L / 2), color)
		end
	end
end
-- big text painted on the floor; `up` = direction the top of the letters points
local function floorLabel(parent, str: string, color: Color3, x: number, z: number, w: number, up: Vector3)
	local y = floorY(x, z) + 0.06
	local p = part(parent, Vector3.new(w, 0.1, w / 4), CFrame.lookAt(Vector3.new(x, y, z), Vector3.new(x, y, z) + up), C.dark,
		Enum.Material.SmoothPlastic, { Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false })
	p.Name = "FloorLabel_" .. str
	text(p, Enum.NormalId.Top, str, color, { bright = 1.2, pps = 16 })
	return p
end
local function crate(parent, pos: Vector3, s: number, color: Color3, rot: number?)
	local cf = CFrame.new(pos + Vector3.new(0, s / 2, 0)) * CFrame.Angles(0, rot or 0, 0)
	part(parent, Vector3.new(s, s, s), cf, C.metal, Enum.Material.DiamondPlate, { CanCollide = true })
	neon(parent, Vector3.new(s + 0.1, 0.25, s + 0.1), cf * CFrame.new(0, s * 0.18, 0), color)
end
local function crateStack(parent, x: number, z: number, color: Color3)
	local y = floorY(x, z)
	crate(parent, Vector3.new(x, y, z), 4, color, 0.1)
	crate(parent, Vector3.new(x + 4.4, y, z + 0.3), 4, color, -0.08)
	crate(parent, Vector3.new(x + 2.2, y + 4, z), 3.6, color, 0.35)
end
local function moveModelTo(model: Model, x: number, z: number, rotY: number?)
	local pivot = model:GetPivot()
	local bb, size = model:GetBoundingBox()
	local rot = CFrame.Angles(0, rotY or 0, 0)
	local target = CFrame.new(x, floorY(x, z), z)
	-- keep the model's bottom on the floor, centred on (x, z)
	local rel = bb:ToObjectSpace(pivot)
	local newBB = target * rot * CFrame.new(0, size.Y / 2, 0) * (bb - bb.Position)
	model:PivotTo(newBB * rel)
end

---------------------------------------------------------------- 1. reorganise existing pieces
-- Spawns: ring around the plaza centre (they used to sit in a line)
local CENTER = Vector3.new(0, floorY(0, 0), 0)
local spawns = Lobby.Spawns:GetChildren()
table.sort(spawns, function(a, b) return a.Name < b.Name end)
for i, sp in ipairs(spawns) do
	if sp:IsA("BasePart") then
		local a = math.rad(30 + (i - 1) * 60)
		local pos = Vector3.new(math.cos(a) * 15, sp.Position.Y, math.sin(a) * 15)
		-- face outwards so you spawn looking at the zones
		sp.CFrame = CFrame.lookAt(pos, Vector3.new(pos.X * 2, pos.Y, pos.Z * 2))
	end
end
-- Hall of Fame boards: centre them on the carpet with even gaps (rotation unchanged - they already face the hall)
local hof = { { P.KillsSign, -20 }, { P.JoinGameSign, 0 }, { P.RobuxSign, 20 } }
for _, e in ipairs(hof) do
	local m: Model = e[1]
	local pv = m:GetPivot()
	m:PivotTo(CFrame.new(e[2], pv.Position.Y, 96) * (pv - pv.Position))
end
-- Clear the hero statue row: the planter and a tree were standing in the middle of it
moveModelTo(P.Planters.Planter_SouthWest, -142, 0)
moveModelTo(P.Trees.Tree_SouthWest, 40, 90)
-- Lounge: bring the west sofa set over to the east lounge (it blocked the Hall of Fame)
moveModelTo(P.Furniture, 98, 58)
moveModelTo(P.Doodads.Doodad_SouthEast, 78, 94)

---------------------------------------------------------------- 2. SPAWN PLAZA + hologram centrepiece
do
	local m = group("SpawnPlaza")
	local y = CENTER.Y
	neon(m, Vector3.new(0.5, 17, 17), CFrame.new(0, y + 0.25, 0) * CFrame.Angles(0, 0, math.pi / 2), C.cyan, { Shape = Enum.PartType.Cylinder, CanCollide = true })
	part(m, Vector3.new(1.2, 16, 16), CFrame.new(0, y + 0.6, 0) * CFrame.Angles(0, 0, math.pi / 2), C.metal, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	neon(m, Vector3.new(0.1, 7, 7), CFrame.new(0, y + 1.25, 0) * CFrame.Angles(0, 0, math.pi / 2), C.mag, { Shape = Enum.PartType.Cylinder, Transparency = 0.2 })
	neon(m, Vector3.new(15, 2.4, 2.4), CFrame.new(0, y + 8.7, 0) * CFrame.Angles(0, 0, math.pi / 2), C.cyan, { Shape = Enum.PartType.Cylinder, Transparency = 0.82 })
	-- floor ring around the plaza
	local R, N = 19.3, 40
	for i = 1, N do
		local a = (i / N) * math.pi * 2
		local seg = 2 * R * math.sin(math.pi / N) * 0.7
		neon(m, Vector3.new(seg, 0.1, 0.5), CFrame.new(math.cos(a) * R, y + 0.05, math.sin(a) * R) * CFrame.Angles(0, -a + math.pi / 2, 0), C.cyan, { Transparency = 0.25 })
	end
	-- spinning core: neon crystal inside a force-field shell
	local core = neon(m, Vector3.new(3.6, 3.6, 3.6), CFrame.new(0, y + 11, 0) * CFrame.Angles(math.rad(45), 0, math.rad(35)), C.mag)
	core.Name = "HoloCore"; core:SetAttribute("Spin", 0.9); core:SetAttribute("SpinX", 0.4); core:SetAttribute("Bob", 0.8)
	CS:AddTag(core, "VG_Spin")
	local light = Instance.new("PointLight"); light.Color = C.mag; light.Range = 22; light.Brightness = 1.6; light.Parent = core
	local shell = part(m, Vector3.new(6, 6, 6), core.CFrame, C.cyan, Enum.Material.ForceField, { CanCollide = false, CanQuery = false })
	shell.Name = "HoloShell"; shell:SetAttribute("Spin", -0.5); shell:SetAttribute("SpinX", -0.3); shell:SetAttribute("Bob", 0.8)
	CS:AddTag(shell, "VG_Spin")
	-- two orbit rings made of neon segments
	local function ring(name, radius, tilt, color, spin)
		local r = Instance.new("Model"); r.Name = name; r.Parent = m
		local n = 28
		for i = 1, n do
			local a = (i / n) * math.pi * 2
			neon(r, Vector3.new(2 * radius * math.sin(math.pi / n) * 0.75, 0.35, 0.35),
				CFrame.new(0, y + 11, 0) * CFrame.Angles(tilt, 0, 0) * CFrame.new(math.cos(a) * radius, 0, math.sin(a) * radius) * CFrame.Angles(0, -a + math.pi / 2, 0), color)
		end
		r.WorldPivot = CFrame.new(0, y + 11, 0) * CFrame.Angles(tilt, 0, 0)
		r:SetAttribute("Spin", spin)
		CS:AddTag(r, "VG_Spin")
	end
	ring("HoloRingA", 6.5, math.rad(12), C.cyan, 0.6)
	ring("HoloRingB", 8.2, math.rad(-22), C.purple, -0.4)
	-- floating title
	local anchor = part(m, Vector3.new(1, 1, 1), CFrame.new(0, y + 19.5, 0), C.dark, nil, { Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false })
	anchor.Name = "HoloTitle"
	local bb = Instance.new("BillboardGui"); bb.Size = UDim2.new(26, 0, 7, 0); bb.LightInfluence = 0; bb.MaxDistance = 350; bb.Parent = anchor
	local t1 = Instance.new("TextLabel"); t1.BackgroundTransparency = 1; t1.Size = UDim2.fromScale(1, 0.68); t1.TextScaled = true
	t1.FontFace = FONT; t1.Text = "PROJECT VANGUARD"; t1.TextColor3 = C.cyan; t1.Parent = bb
	local s1 = Instance.new("UIStroke"); s1.Color = Color3.fromRGB(0, 40, 70); s1.Thickness = 3; s1.Parent = t1
	local t2 = Instance.new("TextLabel"); t2.BackgroundTransparency = 1; t2.Position = UDim2.fromScale(0, 0.68); t2.Size = UDim2.fromScale(1, 0.32)
	t2.TextScaled = true; t2.FontFace = FONT2; t2.TextColor3 = C.mag; t2.Parent = bb
	t2.Text = (GameConfig.Ranked and GameConfig.Ranked.SeasonName) and ("RANKED  " .. tostring(GameConfig.Ranked.SeasonName)) or "9 HEROES  -  CHOOSE YOURS"
end

---------------------------------------------------------------- 3. NORTH: SHOP and PLAY
do
	local m = group("ShopZone")
	hangSign("Shop", "SHOP", C.gold, Vector3.new(1, 24, -49), 16, Vector3.new(0, 0, 1))
	brackets(m, 1, -60, 30, 26, C.gold)
	crateStack(m, -24, -70, C.gold)
	crateStack(m, 18, -74, C.gold)
end
do
	local m = group("PlayZone")
	hangSign("Play", "PLAY", C.cyan, Vector3.new(72, 25, -47), 24, Vector3.new(0, 0, 1))
	floorLabel(m, "PLAY", C.cyan, 72, -14, 18, Vector3.new(0, 0, -1))
	-- pylons either side of the vote pads
	for _, x in ipairs({ 27, 117 }) do
		local y = floorY(x, -64)
		part(m, Vector3.new(2.2, 14, 2.2), CFrame.new(x, y + 7, -64), C.metal, Enum.Material.Metal, { CanCollide = true })
		neon(m, Vector3.new(0.5, 12, 2.4), CFrame.new(x, y + 7, -64), C.cyan)
		neon(m, Vector3.new(3, 0.6, 3), CFrame.new(x, y + 14.3, -64), C.cyan)
	end
	crateStack(m, 148, -86, C.cyan)
end

---------------------------------------------------------------- 4. NORTH-WEST: ARMORY (all 9 hero weapons on a display wall)
do
	local m = group("Armory")
	hangSign("Armory", "ARMORY", C.orange, Vector3.new(-90, 25, -47), 22, Vector3.new(0, 0, 1))
	floorLabel(m, "ARMORY", C.orange, -90, -14, 20, Vector3.new(0, 0, -1))
	local x0, x1, zW = -140, -40, -62
	local y = floorY(-90, zW)
	local W = x1 - x0
	part(m, Vector3.new(W, 13, 1.2), CFrame.new((x0 + x1) / 2, y + 6.5, zW), C.metal, Enum.Material.Metal, { CanCollide = true })
	neon(m, Vector3.new(W, 0.4, 1.4), CFrame.new((x0 + x1) / 2, y + 13, zW), C.orange)
	neon(m, Vector3.new(W, 0.3, 1.4), CFrame.new((x0 + x1) / 2, y + 0.4, zW), C.orange)
	local order = HeroConfig.HeroOrder
	local slot = W / #order
	for i, id in ipairs(order) do
		local h = HeroConfig.Heroes and HeroConfig.Heroes[id] or HeroConfig[id]
		local x = x0 + slot * (i - 0.5)
		local front = zW + 0.6
		local plaqueCF = CFrame.new(x, y + 7.5, front + 0.15)
		local plaque = part(m, Vector3.new(slot - 1.6, 6.5, 0.3), plaqueCF, C.dark, Enum.Material.SmoothPlastic, { CanCollide = false })
		frame(m, plaqueCF, slot - 1.6, 6.5, 0.4, h.Color, 0.25)
		local glow = Instance.new("SurfaceLight"); glow.Face = Enum.NormalId.Back; glow.Color = h.Color
		glow.Brightness = 1.4; glow.Range = 7; glow.Angle = 70; glow.Parent = plaque
		local lab = part(m, Vector3.new(slot - 1.6, 2, 0.2), CFrame.new(x, y + 3, front + 0.1), C.dark, nil, { CanCollide = false })
		text(lab, Enum.NormalId.Back, h.DisplayName .. "\n" .. string.upper(h.Weapon), h.Color, { font = FONT2 })
		local src = RS.HeroAssets.Weapons:FindFirstChild(h.WeaponId)
		if src then
			local w = src:Clone()
			for _, d in ipairs(w:GetDescendants()) do
				if d:IsA("Script") or d:IsA("LocalScript") then d:Destroy()
				elseif d:IsA("BasePart") then d.Anchored = true; d.CanCollide = false; d.CanQuery = false; d.CanTouch = false end
			end
			w.Parent = m
			w:ScaleTo(w:GetScale() * 2.1)
			w:PivotTo(CFrame.new(x, y + 7.5, front + 1.8) * CFrame.Angles(0, -math.pi / 2, 0))
			local bb = w:GetBoundingBox()
			w:PivotTo(w:GetPivot() + (Vector3.new(x, y + 7.5, front + 1.8) - bb.Position))
		end
	end
	-- holo table with a spinning weapon
	local ty = floorY(-90, -40)
	part(m, Vector3.new(3, 8, 8), CFrame.new(-90, ty + 1.5, -40) * CFrame.Angles(0, 0, math.pi / 2), C.metal, Enum.Material.Metal, { Shape = Enum.PartType.Cylinder, CanCollide = true })
	neon(m, Vector3.new(0.4, 8.4, 8.4), CFrame.new(-90, ty + 2.9, -40) * CFrame.Angles(0, 0, math.pi / 2), C.orange, { Shape = Enum.PartType.Cylinder })
	neon(m, Vector3.new(4, 3, 3), CFrame.new(-90, ty + 5, -40) * CFrame.Angles(0, 0, math.pi / 2), C.orange, { Shape = Enum.PartType.Cylinder, Transparency = 0.85 })
	local src = RS.HeroAssets.Weapons:FindFirstChild("Scattergun")
	if src then
		local w = src:Clone()
		for _, d in ipairs(w:GetDescendants()) do
			if d:IsA("Script") or d:IsA("LocalScript") then d:Destroy()
			elseif d:IsA("BasePart") then d.Anchored = true; d.CanCollide = false; d.CanQuery = false; d.CanTouch = false end
		end
		w.Name = "HoloWeapon"; w.Parent = m
		w:ScaleTo(w:GetScale() * 2.6)
		w:PivotTo(CFrame.new(-90, ty + 6.5, -40))
		local bb = w:GetBoundingBox()
		w:PivotTo(w:GetPivot() + (Vector3.new(-90, ty + 6.5, -40) - bb.Position))
		w:SetAttribute("Spin", 0.7); w:SetAttribute("Bob", 0.4)
		CS:AddTag(w, "VG_Spin")
	end
	crateStack(m, -36, -70, C.orange)
	crateStack(m, -150, -56, C.orange)
end

---------------------------------------------------------------- 5. SOUTH: HEROES, HALL OF FAME, LOUNGE
do
	local m = group("HeroHall")
	hangSign("Heroes", "HEROES", C.mag, Vector3.new(-98, 25, 64), 22, Vector3.new(0, 0, -1))
	floorLabel(m, "HEROES", C.mag, -98, 14, 20, Vector3.new(0, 0, 1))
	-- neon trail running in front of the statue row
	local pts = {}
	for _, s in ipairs(Lobby.HeroShowcase:GetChildren()) do
		if s:IsA("Model") and s.Name:find("^Statue_") then table.insert(pts, s:GetPivot().Position) end
	end
	table.sort(pts, function(a, b) return a.X < b.X end)
	for i = 1, #pts - 1 do
		local a = Vector3.new(pts[i].X, floorY(pts[i].X, pts[i].Z - 6) + 0.06, pts[i].Z - 6)
		local b = Vector3.new(pts[i + 1].X, floorY(pts[i + 1].X, pts[i + 1].Z - 6) + 0.06, pts[i + 1].Z - 6)
		neon(m, Vector3.new(0.5, 0.1, (b - a).Magnitude + 0.5), CFrame.lookAt((a + b) / 2, b), C.mag)
	end
end
do
	local m = group("HallOfFame")
	hangSign("HallOfFame", "HALL OF FAME", C.purple, Vector3.new(0, 26.5, 91), 30, Vector3.new(0, 0, -1))
	-- purple carpet from the plaza to the boards
	local y = floorY(0, 55)
	part(m, Vector3.new(12, 0.1, 62), CFrame.new(0, y + 0.05, 55), Color3.fromRGB(45, 20, 70), Enum.Material.Fabric, { CanCollide = false })
	neon(m, Vector3.new(0.4, 0.12, 62), CFrame.new(-6.2, y + 0.06, 55), C.purple)
	neon(m, Vector3.new(0.4, 0.12, 62), CFrame.new(6.2, y + 0.06, 55), C.purple)
	-- velvet-rope posts along the carpet
	for z = 30, 80, 10 do
		for _, sx in ipairs({ -7.5, 7.5 }) do
			part(m, Vector3.new(0.5, 3, 0.5), CFrame.new(sx, y + 1.5, z), C.gold, Enum.Material.Metal, { CanCollide = false })
			neon(m, Vector3.new(0.8, 0.8, 0.8), CFrame.new(sx, y + 3.2, z), C.purple, { Shape = Enum.PartType.Ball })
		end
	end
end
do
	local m = group("Lounge")
	hangSign("Lounge", "LOUNGE", C.green, Vector3.new(118, 25, 30), 22, Vector3.new(0, 0, -1))
	floorLabel(m, "LOUNGE", C.green, 118, 14, 20, Vector3.new(0, 0, 1))
	-- arcade cabinets on the east wall
	local games = { { "NEON RUSH", C.cyan }, { "VOLT DASH", C.gold }, { "HEADSHOT 3000", C.mag } }
	for i, g in ipairs(games) do
		local z = 62 + i * 8
		local y = floorY(176, z)
		local base = CFrame.new(176, y, z) * CFrame.Angles(0, math.pi / 2, 0) -- front faces -X (into the room)
		part(m, Vector3.new(4.2, 8.5, 3.6), base * CFrame.new(0, 4.25, 0), C.metal, Enum.Material.Metal, { CanCollide = true })
		local scr = part(m, Vector3.new(3.4, 2.6, 0.2), base * CFrame.new(0, 5.6, -1.85) * CFrame.Angles(math.rad(-12), 0, 0), C.dark, Enum.Material.Glass, { CanCollide = false })
		text(scr, Enum.NormalId.Front, g[1], g[2], { font = FONT })
		neon(m, Vector3.new(4.2, 1.1, 0.5), base * CFrame.new(0, 7.9, -1.7), g[2])
		part(m, Vector3.new(4.2, 0.5, 1.6), base * CFrame.new(0, 3.6, -2.4), C.dark, Enum.Material.Metal, { CanCollide = false })
		neon(m, Vector3.new(0.5, 0.5, 0.5), base * CFrame.new(-1, 4, -2.6), C.red, { Shape = Enum.PartType.Ball })
		neon(m, Vector3.new(0.5, 0.5, 0.5), base * CFrame.new(0.8, 4, -2.6), C.cyan, { Shape = Enum.PartType.Ball })
		neon(m, Vector3.new(0.2, 8.5, 3.7), base * CFrame.new(-2.15, 4.25, 0), g[2])
		neon(m, Vector3.new(0.2, 8.5, 3.7), base * CFrame.new(2.15, 4.25, 0), g[2])
	end
	-- vending machines by the window
	for i, v in ipairs({ { "ENERGY", C.cyan }, { "NEON COLA", C.mag } }) do
		local x = 156 + i * 7
		local y = floorY(x, 96)
		local base = CFrame.new(x, y, 96) -- front faces -Z
		part(m, Vector3.new(6, 10, 4), base * CFrame.new(0, 5, 0), C.metal, Enum.Material.Metal, { CanCollide = true })
		local face = neon(m, Vector3.new(4.6, 6.5, 0.2), base * CFrame.new(0, 6, -2.05), v[2], { Transparency = 0.35 })
		text(face, Enum.NormalId.Front, v[1], Color3.new(1, 1, 1), { font = FONT })
		part(m, Vector3.new(4.6, 1.6, 0.3), base * CFrame.new(0, 1.6, -2.05), C.dark, nil, { CanCollide = false })
	end
	-- hanging screen: VANGUARD TV with a hero spotlight and a scrolling news ticker (animated by LobbyAmbience)
	local tvCF = CFrame.lookAt(Vector3.new(128, 20, 96), Vector3.new(128, 20, 0))
	local tv = part(m, Vector3.new(24, 13.5, 0.6), tvCF, C.dark, Enum.Material.Glass, { CanCollide = false, CanQuery = false })
	tv.Name = "VanguardTV"
	frame(m, tvCF, 24, 13.5, 0.7, C.green)
	for _, sx in ipairs({ -10, 10 }) do cable(m, (tvCF * CFrame.new(sx, 6.75, 0)).Position) end
	local g = Instance.new("SurfaceGui"); g.Face = Enum.NormalId.Front; g.LightInfluence = 0; g.Brightness = 1.5
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud; g.PixelsPerStud = 30; g.ClipsDescendants = true; g.Parent = tv
	local bg = Instance.new("Frame"); bg.Size = UDim2.fromScale(1, 1); bg.BackgroundColor3 = Color3.fromRGB(8, 10, 18); bg.Parent = g
	local grad = Instance.new("UIGradient"); grad.Rotation = 90
	grad.Color = ColorSequence.new(Color3.fromRGB(20, 30, 60), Color3.fromRGB(6, 6, 12)); grad.Parent = bg
	local function lbl(name, pos, size, str, color, font)
		local t = Instance.new("TextLabel"); t.Name = name; t.BackgroundTransparency = 1; t.Position = pos; t.Size = size
		t.TextScaled = true; t.FontFace = font; t.Text = str; t.TextColor3 = color; t.Parent = bg
		return t
	end
	lbl("Header", UDim2.fromScale(0.04, 0.04), UDim2.fromScale(0.6, 0.12), "VANGUARD TV  -  HERO SPOTLIGHT", C.green, FONT2).TextXAlignment = Enum.TextXAlignment.Left
	local live = lbl("Live", UDim2.fromScale(0.82, 0.04), UDim2.fromScale(0.14, 0.12), "LIVE", C.red, FONT)
	live.TextXAlignment = Enum.TextXAlignment.Right
	local name = lbl("HeroName", UDim2.fromScale(0.05, 0.24), UDim2.fromScale(0.9, 0.34), "VANGUARD", C.cyan, FONT)
	local role = lbl("HeroRole", UDim2.fromScale(0.05, 0.58), UDim2.fromScale(0.9, 0.14), "", Color3.new(1, 1, 1), FONT2)
	CS:AddTag(name, "VG_HeroCycle"); role:SetAttribute("Role", true)
	local bar = Instance.new("Frame"); bar.Name = "TickerBar"; bar.Position = UDim2.fromScale(0, 0.82); bar.Size = UDim2.fromScale(1, 0.18)
	bar.BackgroundColor3 = C.green; bar.BackgroundTransparency = 0.75; bar.ClipsDescendants = true; bar.Parent = bg
	local tick = Instance.new("TextLabel"); tick.Name = "Ticker"; tick.BackgroundTransparency = 1; tick.AutomaticSize = Enum.AutomaticSize.X
	tick.Size = UDim2.fromScale(0, 1); tick.TextSize = 40; tick.FontFace = FONT2; tick.TextColor3 = Color3.new(1, 1, 1); tick.Parent = bar
	tick.Text = "WELCOME TO PROJECT VANGUARD   //   NEW HEROES: JERIC, FORGE & ECHO   //   STAND ON A PAD TO VOTE FOR A MODE   //   CLIMB THE RANKED LADDER   //   VISIT THE SHOP FOR SKINS & TOKENS   //"
	CS:AddTag(tick, "VG_Ticker")
	crateStack(m, 82, 30, C.green)
end

---------------------------------------------------------------- 6. AMBIENCE: banners, wall ads, drones
do
	local m = group("Banners")
	local colors = { C.cyan, C.mag, C.gold, C.purple }
	local i = 0
	for _, x in ipairs({ -130, -65, 65, 130 }) do
		for _, z in ipairs({ -25, 25 }) do
			i += 1
			local col = colors[(i - 1) % #colors + 1]
			local cf = CFrame.new(x, 36, z) * CFrame.Angles(0, math.pi / 2, 0) -- faces along the hall
			local b = part(m, Vector3.new(5, 13, 0.25), cf, C.dark, Enum.Material.Fabric, { CanCollide = false, CanQuery = false })
			neon(m, Vector3.new(5.4, 0.5, 0.35), cf * CFrame.new(0, 6.5, 0), C.cable)
			neon(m, Vector3.new(5, 1.2, 0.3), cf * CFrame.new(0, -6, 0), col)
			neon(m, Vector3.new(0.3, 13, 0.3), cf * CFrame.new(-2.5, 0, 0), col)
			neon(m, Vector3.new(0.3, 13, 0.3), cf * CFrame.new(2.5, 0, 0), col)
			text(b, Enum.NormalId.Front, "V", col, { size = UDim2.fromScale(1, 0.5), pos = UDim2.fromScale(0, 0.12) })
			text(b, Enum.NormalId.Back, "V", col, { size = UDim2.fromScale(1, 0.5), pos = UDim2.fromScale(0, 0.12) })
			cable(m, (cf * CFrame.new(-2, 6.75, 0)).Position)
			cable(m, (cf * CFrame.new(2, 6.75, 0)).Position)
		end
	end
end
do
	local m = group("WallAds")
	local function ad(x: number, y: number, title: string, sub: string, color: Color3)
		local cf = CFrame.lookAt(Vector3.new(x, y, -97.4), Vector3.new(x, y, 0))
		local p = part(m, Vector3.new(20, 9, 0.4), cf, C.dark, Enum.Material.Glass, { CanCollide = false, CanQuery = false })
		frame(m, cf, 20, 9, 0.5, color)
		text(p, Enum.NormalId.Front, title, color, { size = UDim2.fromScale(1, 0.62) })
		text(p, Enum.NormalId.Front, sub, Color3.new(1, 1, 1), { size = UDim2.fromScale(1, 0.36), pos = UDim2.fromScale(0, 0.6), font = FONT2 })
	end
	ad(140, 24, "NEW HEROES", "JERIC  -  FORGE  -  ECHO", C.mag)
	ad(5, 31, "RANKED", "CLIMB TO THE TOP", C.purple)
end
do
	local m = group("Drones")
	local paths = { { 0, 0, 30, 34, 0.25 }, { -95, 30, 24, 30, -0.3 }, { 100, -40, 26, 32, 0.28 } }
	for i, pth in ipairs(paths) do
		local d = Instance.new("Model"); d.Name = "Drone" .. i; d.Parent = m
		local c = CFrame.new(pth[1] + pth[3], pth[4], pth[2])
		local body = part(d, Vector3.new(2.2, 0.8, 2.2), c, C.metal, Enum.Material.Metal, { CanCollide = false, CanQuery = false })
		d.PrimaryPart = body
		neon(d, Vector3.new(0.7, 0.7, 0.7), c * CFrame.new(0, -0.2, -1.15), C.cyan, { Shape = Enum.PartType.Ball })
		for _, o in ipairs({ { 1.5, 1.5 }, { -1.5, 1.5 }, { 1.5, -1.5 }, { -1.5, -1.5 } }) do
			part(d, Vector3.new(0.2, 0.2, 1.4), c * CFrame.new(o[1] * 0.6, 0.1, o[2] * 0.6) * CFrame.Angles(0, math.atan2(o[1], o[2]), 0), C.metal, nil, { CanCollide = false, CanQuery = false })
			neon(d, Vector3.new(0.1, 1.6, 1.6), c * CFrame.new(o[1], 0.45, o[2]) * CFrame.Angles(0, 0, math.pi / 2), C.cyan, { Shape = Enum.PartType.Cylinder, Transparency = 0.6 })
		end
		local l = Instance.new("SpotLight"); l.Face = Enum.NormalId.Bottom; l.Angle = 50; l.Range = 30; l.Brightness = 1.2; l.Color = C.cyan; l.Parent = body
		d:SetAttribute("CenterX", pth[1]); d:SetAttribute("CenterZ", pth[2]); d:SetAttribute("Radius", pth[3])
		d:SetAttribute("Height", pth[4]); d:SetAttribute("Speed", pth[5])
		CS:AddTag(d, "VG_Drone")
	end
end

local n = 0
for _, x in ipairs(D:GetDescendants()) do if x:IsA("BasePart") then n += 1 end end
return "Decor parts: " .. n
