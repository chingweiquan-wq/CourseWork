-- build_hold_rigs.lua  (run in Studio's Edit datamodel after build_hero_bodies.lua; safe to re-run)
-- Prepares each hero body in ReplicatedStorage.HeroAssets.Bodies for the IK weapon holds (HeroPoseController):
--   RightHand.VG_GunGrip   attachment at the grip whose LookVector runs along the weapon (barrel direction)
--                          and whose UpVector is the weapon's "up" - the IK points this where the hero aims
--   RightHand.VG_LeftHold  attachment = where the left hand sat relative to the right hand in the statue pose;
--                          two-handed heroes keep the left hand there so the weapon (split across both hand
--                          meshes) stays in one piece
-- Weapon axis per hero (checked against front close-ups of every statue):
--   Hands   : grip -> left hand (the support hand is on the barrel)          Rift, Vex, Echo, Solace (staff)
--   Forearm : elbow -> hand (the cannon is the forearm)                      Titan
--   Vector3 : the weapon's direction in the statue pose (world space)         Jeric (pistol grip pointing down),
--                                                                             Forge (rivet gun raised, pointing up)
--   (Shade, Volt: melee - hands are steered by position only, no axis needed)
local RS = game:GetService("ReplicatedStorage")
local AXIS: { [string]: any } = {
	Rift = "Hands", Vex = "Hands", Echo = "Hands", Solace = "Hands", Titan = "Forearm",
	Jeric = Vector3.new(0, -1, -0.15).Unit, Forge = Vector3.new(0.23, 0.97, -0.1).Unit,
}

local report = {}
for _, body in ipairs(RS.HeroAssets.Bodies:GetChildren()) do
	local rh, lh, rla = body:FindFirstChild("RightHand"), body:FindFirstChild("LeftHand"), body:FindFirstChild("RightLowerArm")
	if not (rh and lh and rla) then continue end
	for _, n in ipairs({ "VG_GunGrip", "VG_LeftHold" }) do
		local old = rh:FindFirstChild(n)
		if old then old:Destroy() end
	end
	local gripAtt = rh:FindFirstChild("RightGripAttachment") :: Attachment?
	local gripLocal = gripAtt and gripAtt.Position or Vector3.zero
	local gripWorld = rh.CFrame:PointToWorldSpace(gripLocal)

	local mode = AXIS[body.Name]
	local axisWorld: Vector3? = nil
	if typeof(mode) == "Vector3" then
		axisWorld = mode
	elseif mode == "Hands" then
		axisWorld = (lh.Position - gripWorld).Unit
	elseif mode == "Forearm" then
		local elbow = rla:FindFirstChild("RightElbowRigAttachment") :: Attachment?
		local from = elbow and elbow.WorldPosition or rla.Position
		axisWorld = (rh.Position - from).Unit
	end

	local grip = Instance.new("Attachment")
	grip.Name = "VG_GunGrip"
	local axisLocal = axisWorld and rh.CFrame:VectorToObjectSpace(axisWorld) or Vector3.new(0, 0, -1)
	-- weapon "up" = the statue's world up, made perpendicular to the barrel
	local upLocal = rh.CFrame:VectorToObjectSpace(Vector3.yAxis)
	upLocal = (upLocal - axisLocal * upLocal:Dot(axisLocal))
	if upLocal.Magnitude < 0.1 then upLocal = rh.CFrame:VectorToObjectSpace(Vector3.new(0, 0, 1)) end -- weapon points straight up/down: use the statue's back as "up"
	upLocal = upLocal.Unit
	grip.CFrame = CFrame.lookAt(gripLocal, gripLocal + axisLocal, upLocal)
	grip.Parent = rh

	local left = Instance.new("Attachment")
	left.Name = "VG_LeftHold"
	left.CFrame = rh.CFrame:ToObjectSpace(lh.CFrame)
	left.Parent = rh

	table.insert(report, string.format("%s %s axis(%.2f,%.2f,%.2f) left %.2f", body.Name, tostring(mode or "melee"), axisLocal.X, axisLocal.Y, axisLocal.Z, left.Position.Magnitude))
end
return table.concat(report, "\n")
