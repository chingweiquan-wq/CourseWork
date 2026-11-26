-- build_hold_rigs.lua  (run in Studio's Edit datamodel after build_hero_bodies.lua; safe to re-run)
-- Prepares each hero body in ReplicatedStorage.HeroAssets.Bodies for the IK weapon holds (HeroPoseController):
--   VG_GunGrip   attachment whose LookVector runs along the weapon (towards the muzzle) and UpVector is the
--                weapon's "up"; the IK points it where the hero aims. On the RightHand, except Forge (forearm).
--   VG_LeftHold  (RightHand) where the left hand sat relative to the right hand in the statue pose; two-handed
--                heroes keep the left hand there so the weapon (split across both hand meshes) stays in one piece.
-- How the weapon direction was found (checked against front/side close-ups of every statue):
--   Tip     : from the right grip to the farthest mesh point of the hands (the muzzle)   Rift, Vex, Echo, Solace
--             measured on the unscaled bodies in ServerStorage.HeroBodiesRaw, which keep precise collision
--   Forearm : elbow -> hand, the cannon is the forearm                                     Titan
--   Vector  : fixed direction in the statue pose                                           Jeric (gun points down)
--   ForgeArm: Forge's tool is skinned to the raised forearm, so the IK steers the forearm (effector at the wrist)
--   (Shade, Volt: melee - hands are steered by position only, no axis needed)
local RS = game:GetService("ReplicatedStorage")
local SS = game:GetService("ServerStorage")
local MODE: { [string]: any } = {
	Rift = "Tip", Vex = "Tip", Echo = "Tip", Solace = "Tip", Titan = "Forearm", Forge = "ForgeArm",
	Jeric = Vector3.new(0, -1, -0.15).Unit,
}

local function sample(part: BasePart, n: number, pts: { Vector3 })
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { part }
	local R = part.Size.Magnitude
	for _ = 1, n do
		local dir = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5).Unit
		local hit = workspace:Raycast(part.Position + dir * R, -dir * R * 2, params)
		if hit then table.insert(pts, hit.Position) end
	end
end

-- weapon tip direction, measured on a temporary copy of the raw (precise-collision) body
local function tipAxisLocal(id: string): Vector3?
	local src = SS:FindFirstChild("HeroBodiesRaw") and SS.HeroBodiesRaw:FindFirstChild(id)
	if not src then return nil end
	local b = src:Clone()
	for _, d in ipairs(b:GetDescendants()) do if d:IsA("BasePart") then d.Anchored = true end end
	b.Parent = workspace
	b:PivotTo(CFrame.new(0, 500, 0))
	local pts = {}
	sample(b.RightHand, 900, pts)
	sample(b.LeftHand, 900, pts)
	local grip = b.RightHand.RightGripAttachment.WorldPosition
	local tip, best = nil, 0
	for _, p in ipairs(pts) do
		local d = (p - grip).Magnitude
		if d > best then tip, best = p, d end
	end
	local axis = tip and b.RightHand.CFrame:VectorToObjectSpace((tip - grip).Unit) or nil
	b:Destroy()
	return axis -- local to the right hand; the scaled template has the same orientation
end

local report = {}
for _, body in ipairs(RS.HeroAssets.Bodies:GetChildren()) do
	local id = body.Name
	local rh, lh, rla = body:FindFirstChild("RightHand"), body:FindFirstChild("LeftHand"), body:FindFirstChild("RightLowerArm")
	if not (rh and lh and rla) then continue end
	for _, p in ipairs({ rh, rla }) do
		for _, n in ipairs({ "VG_GunGrip", "VG_LeftHold" }) do
			local o = p:FindFirstChild(n)
			if o then o:Destroy() end
		end
	end
	local mode = MODE[id]
	local part: BasePart = rh
	local gripAtt = rh:FindFirstChild("RightGripAttachment") :: Attachment?
	local pos = gripAtt and gripAtt.Position or Vector3.zero
	local axisLocal: Vector3? = nil
	if mode == "Tip" then
		axisLocal = tipAxisLocal(id)
	elseif mode == "Forearm" then
		local elbow = rla:FindFirstChild("RightElbowRigAttachment") :: Attachment?
		axisLocal = rh.CFrame:VectorToObjectSpace((rh.Position - (elbow and elbow.WorldPosition or rla.Position)).Unit)
	elseif mode == "ForgeArm" then
		part = rla
		local elbow = rla:FindFirstChild("RightElbowRigAttachment") :: Attachment?
		local wrist = rla:FindFirstChild("RightWristRigAttachment") :: Attachment?
		pos = wrist and wrist.Position or Vector3.zero
		local from = elbow and elbow.WorldPosition or rla.Position
		local to = wrist and wrist.WorldPosition or rh.Position
		axisLocal = rla.CFrame:VectorToObjectSpace((to - from).Unit)
	elseif typeof(mode) == "Vector3" then
		axisLocal = rh.CFrame:VectorToObjectSpace(mode)
	end
	local axis = axisLocal or Vector3.new(0, 0, -1)
	local function flat(v: Vector3): Vector3 return v - axis * v:Dot(axis) end
	local up = flat(part.CFrame:VectorToObjectSpace(Vector3.yAxis))
	if up.Magnitude < 0.1 then up = flat(part.CFrame:VectorToObjectSpace(Vector3.zAxis)) end -- weapon points straight up/down
	local grip = Instance.new("Attachment")
	grip.Name = "VG_GunGrip"
	grip.CFrame = CFrame.lookAt(pos, pos + axis, up.Unit)
	grip.Parent = part

	local left = Instance.new("Attachment")
	left.Name = "VG_LeftHold"
	left.CFrame = rh.CFrame:ToObjectSpace(lh.CFrame)
	left.Parent = rh

	local w = part.CFrame:VectorToWorldSpace(axis)
	table.insert(report, string.format("%s %s on %s (%.2f,%.2f,%.2f)", id, tostring(mode or "melee"), part.Name, w.X, w.Y, w.Z))
end
return table.concat(report, "\n")
