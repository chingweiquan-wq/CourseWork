-- SkinFXController: animates Legendary weapon skins on this client (cheap, nothing sent over the network).
-- Aura shells tagged "SkinFX" drift between their FxA / FxB colours; skin lights pulse gently.
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

RunService.RenderStepped:Connect(function()
	local t = os.clock()
	local wave = (math.sin(t * 2.2) + 1) / 2 -- 0..1
	for _, inst in ipairs(CollectionService:GetTagged("SkinFX")) do
		if inst:IsA("BasePart") then
			local a, b = inst:GetAttribute("FxA"), inst:GetAttribute("FxB")
			if typeof(a) == "Color3" and typeof(b) == "Color3" then
				inst.Color = a:Lerp(b, wave)
			end
		elseif inst:IsA("PointLight") then
			inst.Brightness = 0.6 + wave * 0.9
		end
	end
end)
