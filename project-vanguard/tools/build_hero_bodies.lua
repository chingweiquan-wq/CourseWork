-- build_hero_bodies.lua  (run in Studio's Edit datamodel; safe to re-run)
-- Turns the rigged statues in ServerStorage.HeroBodiesRaw (made with Studio's Auto Setup Avatar, setup type
-- Development, from ReplicatedStorage.HeroAssets.Statues) into the in-game hero bodies in HeroAssets.Bodies, scaled by role:
-- tanks are bigger (bigger hitbox, more HP), assassins/recon smaller.
local RS = game:GetService("ReplicatedStorage")
local HeroConfig = require(RS.Modules.HeroConfig)
local assets = RS.HeroAssets
local raw = game:GetService("ServerStorage").HeroBodiesRaw

local BASE_HEIGHT = 5.6 -- studs, feet to top of head (a default Roblox avatar is about 5.3)
local ROLE_SCALE = { Tank = 1.18, Assassin = 0.92, Recon = 0.95, Sniper = 0.98 } -- everything else 1.0

local out = assets:FindFirstChild("Bodies") or Instance.new("Folder")
out.Name = "Bodies"
out.Parent = assets

local report = {}
for _, src in ipairs(raw:GetChildren()) do
	local hero = HeroConfig.Heroes[src.Name]
	if src:IsA("Model") and hero then
		local old = out:FindFirstChild(src.Name)
		if old then old:Destroy() end
		local m = src:Clone()
		local _, size = m:GetBoundingBox()
		local target = BASE_HEIGHT * (ROLE_SCALE[hero.Role] or 1)
		m:ScaleTo(m:GetScale() * target / size.Y)
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = false
				d.CastShadow = true
				if d:IsA("MeshPart") then d.CollisionFidelity = Enum.CollisionFidelity.Box end
			end
		end
		-- hip height = gap between the root part's bottom and the soles, so feet land on the floor
		local cf, sz = m:GetBoundingBox()
		local hrp = m.HumanoidRootPart
		m.Humanoid.HipHeight = (hrp.Position.Y - hrp.Size.Y / 2) - (cf.Position.Y - sz.Y / 2)
		m.Parent = out
		local _, s2 = m:GetBoundingBox()
		table.insert(report, string.format("%s %.2f (hip %.2f)", src.Name, s2.Y, m.Humanoid.HipHeight))
	end
end
return table.concat(report, ", ")
