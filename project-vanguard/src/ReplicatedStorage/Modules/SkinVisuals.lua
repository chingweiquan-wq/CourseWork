--!strict
-- SkinVisuals: turns a weapon model into a skinned one. Used for the world weapon (server), the first-person
-- viewmodel and the shop / inventory previews (client). Purely visual: every added part has no collision,
-- no queries and no touch, so hit detection is exactly the same as the default weapon.
--
-- Themes:
--   Arctic (Uncommon)  frosty white body + thin icy-blue glass sheen
--   Gold   (Legendary) polished gold + animated glowing gold aura + soft light, gold tracers
--   Void   (Legendary) see-through violet crystal + animated violet/cyan aura + light, violet tracers
--   Inferno(Legendary) molten cracked-lava metal + animated orange/yellow aura + light, fire tracers
-- Animated parts are tagged "SkinFX"; SkinFXController (client) shifts their colour and pulses the light.
-- Each theme also has an Fx style used by SkinFX (client): themed muzzle flash, hit sparks and kill burst,
-- plus a body aura (ApplyAura, server) on the hero's weapon hand that every player sees.
-- Uncommon themes stay subtle (Loud = false); Legendary themes get the full show (Loud = true).
local CollectionService = game:GetService("CollectionService")

local SkinConfig = require(script.Parent.SkinConfig)

local SkinVisuals = {}

export type Theme = {
	Material: Enum.Material, Color: Color3, Reflectance: number?, Transparency: number?,
	Shell: { Material: Enum.Material, Color: Color3, Transparency: number, Scale: number }?,
	ShiftA: Color3?, ShiftB: Color3?, -- animated aura colours
	Light: Color3?,
	Tracer: Color3?,
	Fx: string?, -- "Frost" | "Gold" | "Void" | "Inferno": style of hit sparks / kill burst / aura
	Loud: boolean?, -- Legendary: bigger particles, coins/shards/flames, kill burst, aura light
	FxColor: Color3?, -- main colour of the effects
	FxColor2: Color3?, -- secondary colour
}

SkinVisuals.Themes = {
	Arctic = {
		Material = Enum.Material.Snow, Color = Color3.fromRGB(226, 233, 242),
		Shell = { Material = Enum.Material.Glass, Color = Color3.fromRGB(150, 210, 255), Transparency = 0.72, Scale = 1.012 },
		Tracer = Color3.fromRGB(175, 225, 255),
		Fx = "Frost", Loud = false, FxColor = Color3.fromRGB(190, 235, 255), FxColor2 = Color3.fromRGB(255, 255, 255),
	},
	Gold = {
		Material = Enum.Material.Metal, Color = Color3.fromRGB(240, 186, 48), Reflectance = 0.3,
		Shell = { Material = Enum.Material.ForceField, Color = Color3.fromRGB(255, 215, 90), Transparency = 0, Scale = 1.035 },
		ShiftA = Color3.fromRGB(255, 200, 60), ShiftB = Color3.fromRGB(255, 250, 215),
		Light = Color3.fromRGB(255, 210, 100),
		Tracer = Color3.fromRGB(255, 205, 70),
		Fx = "Gold", Loud = true, FxColor = Color3.fromRGB(255, 200, 50), FxColor2 = Color3.fromRGB(255, 245, 200),
	},
	Void = {
		Material = Enum.Material.Glass, Color = Color3.fromRGB(95, 45, 170), Transparency = 0.12,
		Shell = { Material = Enum.Material.ForceField, Color = Color3.fromRGB(170, 90, 255), Transparency = 0, Scale = 1.045 },
		ShiftA = Color3.fromRGB(170, 90, 255), ShiftB = Color3.fromRGB(80, 200, 255),
		Light = Color3.fromRGB(170, 110, 255),
		Tracer = Color3.fromRGB(185, 110, 255),
		Fx = "Void", Loud = true, FxColor = Color3.fromRGB(170, 90, 255), FxColor2 = Color3.fromRGB(80, 210, 255),
	},
	Inferno = {
		Material = Enum.Material.CrackedLava, Color = Color3.fromRGB(255, 95, 30),
		Shell = { Material = Enum.Material.ForceField, Color = Color3.fromRGB(255, 120, 30), Transparency = 0, Scale = 1.04 },
		ShiftA = Color3.fromRGB(255, 70, 20), ShiftB = Color3.fromRGB(255, 210, 70),
		Light = Color3.fromRGB(255, 130, 50),
		Tracer = Color3.fromRGB(255, 120, 40),
		Fx = "Inferno", Loud = true, FxColor = Color3.fromRGB(255, 110, 30), FxColor2 = Color3.fromRGB(255, 220, 90),
	},
} :: { [string]: Theme }

local SKIP = { Muzzle = true, Pivot = true }

function SkinVisuals.GetTheme(skinId: string?): Theme?
	local skin = skinId and SkinConfig.Skins[skinId]
	return skin and SkinVisuals.Themes[skin.Theme] or nil
end

-- Bullet trail colour for a weapon with a skin (falls back to the weapon's own colour).
function SkinVisuals.TracerColor(skinId: string?, default: Color3): Color3
	local theme = SkinVisuals.GetTheme(skinId)
	return (theme and theme.Tracer) or default
end

-- Restyle every visible part of `model`. Call right after cloning the weapon template,
-- before it is scaled, welded or parented.
function SkinVisuals.Apply(model: Instance, skinId: string?)
	local theme = SkinVisuals.GetTheme(skinId)
	if not theme then return end
	local parts = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and not SKIP[d.Name] and d.Transparency < 1 then table.insert(parts, d) end
	end
	for i, part in ipairs(parts) do
		for _, c in ipairs(part:GetChildren()) do
			if c:IsA("SurfaceAppearance") or c:IsA("Texture") or c:IsA("Decal") then c:Destroy() end
		end
		if part:IsA("MeshPart") then part.TextureID = "" end
		part.Material = theme.Material
		part.Color = theme.Color
		part.Reflectance = theme.Reflectance or 0
		part.Transparency = theme.Transparency or 0
		part.CastShadow = false

		local sh = theme.Shell
		if sh then
			local shell = part:Clone()
			shell:ClearAllChildren()
			shell.Name = "SkinShell"
			shell.Size = part.Size * sh.Scale
			shell.CFrame = part.CFrame
			shell.Material = sh.Material
			shell.Color = sh.Color
			shell.Transparency = sh.Transparency
			shell.Reflectance = 0
			shell.CanCollide = false; shell.CanQuery = false; shell.CanTouch = false; shell.Massless = true
			shell.Parent = part.Parent
			if theme.ShiftA and theme.ShiftB then
				shell:SetAttribute("FxA", theme.ShiftA)
				shell:SetAttribute("FxB", theme.ShiftB)
				CollectionService:AddTag(shell, "SkinFX")
			end
		end
		if theme.Light and i == 1 then
			local light = Instance.new("PointLight")
			light.Name = "SkinLight"
			light.Color = theme.Light
			light.Range = 5
			light.Brightness = 1
			light.Shadows = false
			light.Parent = part
			CollectionService:AddTag(light, "SkinFX")
		end
	end
end

-- Body aura: glowing particles around the hero's weapon hand so everyone can see your skin, now that the
-- weapon is part of the hero body. Built on the server (replicates). Uncommon = a few soft sparkles;
-- Legendary = dense themed particles + a light. Removes any previous aura first.
local AURA_TEXTURE = {
	Frost = "rbxasset://textures/particles/sparkles_main.dds",
	Gold = "rbxasset://textures/particles/sparkles_main.dds",
	Void = "rbxasset://textures/particles/sparkles_main.dds",
	Inferno = "rbxasset://textures/particles/fire_main.dds",
}
function SkinVisuals.ApplyAura(character: Model, skinId: string?)
	for _, d in ipairs(character:GetDescendants()) do
		if d.Name == "SkinAura" then d:Destroy() end
	end
	local theme = SkinVisuals.GetTheme(skinId)
	if not theme or not theme.Fx then return end
	local loud = theme.Loud == true
	local c1, c2 = theme.FxColor or theme.Color, theme.FxColor2 or Color3.new(1, 1, 1)
	for _, handName in ipairs({ "RightHand", "LeftHand" }) do
		local hand = character:FindFirstChild(handName)
		if hand and hand:IsA("BasePart") and (loud or handName == "RightHand") then
			local att = Instance.new("Attachment")
			att.Name = "SkinAura"
			att.Parent = hand
			local pe = Instance.new("ParticleEmitter")
			pe.Name = "SkinAura"
			pe.Texture = AURA_TEXTURE[theme.Fx] or AURA_TEXTURE.Gold
			pe.Color = ColorSequence.new(c1, c2)
			pe.LightEmission = 1
			pe.LightInfluence = 0
			pe.Rate = loud and 14 or 4
			pe.Lifetime = NumberRange.new(0.5, loud and 1.1 or 0.8)
			pe.Speed = NumberRange.new(0.4, loud and 1.6 or 0.8)
			pe.SpreadAngle = Vector2.new(180, 180)
			pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, loud and 0.35 or 0.22), NumberSequenceKeypoint.new(1, 0) })
			pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
			pe.Rotation = NumberRange.new(0, 360)
			pe.RotSpeed = NumberRange.new(-90, 90)
			if theme.Fx == "Inferno" then
				pe.Acceleration = Vector3.new(0, 3, 0) -- flames lick upwards
			elseif theme.Fx == "Void" then
				pe.Acceleration = Vector3.new(0, -0.5, 0)
				pe.Drag = 2
			elseif theme.Fx == "Gold" then
				pe.Acceleration = Vector3.new(0, -2, 0) -- glitter falls
			end
			pe.Parent = att
			if loud and handName == "RightHand" then
				local light = Instance.new("PointLight")
				light.Name = "SkinAura"
				light.Color = theme.Light or c1
				light.Range = 7
				light.Brightness = 1.2
				light.Shadows = false
				light.Parent = hand
				CollectionService:AddTag(light, "SkinFX") -- pulses with the weapon aura
			end
		end
	end
end

return SkinVisuals
