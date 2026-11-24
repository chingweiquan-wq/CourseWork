--!strict
-- SkinVisuals: turns a weapon model into a skinned one. Used for the world weapon (server), the first-person
-- viewmodel and the shop / inventory previews (client). Purely visual: every added part has no collision,
-- no queries and no touch, so hit detection is exactly the same as the default weapon.
--
-- Themes:
--   Arctic (Uncommon)  frosty white body + thin icy-blue glass sheen
--   Gold   (Legendary) polished gold + animated glowing gold aura + soft light, gold tracers
--   Void   (Legendary) see-through violet crystal + animated violet/cyan aura + light, violet tracers
-- Animated parts are tagged "SkinFX"; SkinFXController (client) shifts their colour and pulses the light.
local CollectionService = game:GetService("CollectionService")

local SkinConfig = require(script.Parent.SkinConfig)

local SkinVisuals = {}

export type Theme = {
	Material: Enum.Material, Color: Color3, Reflectance: number?, Transparency: number?,
	Shell: { Material: Enum.Material, Color: Color3, Transparency: number, Scale: number }?,
	ShiftA: Color3?, ShiftB: Color3?, -- animated aura colours
	Light: Color3?,
	Tracer: Color3?,
}

SkinVisuals.Themes = {
	Arctic = {
		Material = Enum.Material.Snow, Color = Color3.fromRGB(226, 233, 242),
		Shell = { Material = Enum.Material.Glass, Color = Color3.fromRGB(150, 210, 255), Transparency = 0.72, Scale = 1.012 },
	},
	Gold = {
		Material = Enum.Material.Metal, Color = Color3.fromRGB(240, 186, 48), Reflectance = 0.3,
		Shell = { Material = Enum.Material.ForceField, Color = Color3.fromRGB(255, 215, 90), Transparency = 0, Scale = 1.035 },
		ShiftA = Color3.fromRGB(255, 200, 60), ShiftB = Color3.fromRGB(255, 250, 215),
		Light = Color3.fromRGB(255, 210, 100),
		Tracer = Color3.fromRGB(255, 205, 70),
	},
	Void = {
		Material = Enum.Material.Glass, Color = Color3.fromRGB(95, 45, 170), Transparency = 0.12,
		Shell = { Material = Enum.Material.ForceField, Color = Color3.fromRGB(170, 90, 255), Transparency = 0, Scale = 1.045 },
		ShiftA = Color3.fromRGB(170, 90, 255), ShiftB = Color3.fromRGB(80, 200, 255),
		Light = Color3.fromRGB(170, 110, 255),
		Tracer = Color3.fromRGB(185, 110, 255),
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

return SkinVisuals
