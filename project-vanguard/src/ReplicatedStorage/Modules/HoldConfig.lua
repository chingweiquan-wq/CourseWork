--!strict
-- HoldConfig: how each hero holds their weapon (used by HeroPoseController, which drives the arms with IK).
--
-- Positions are where the right hand's grip goes, in UpperTorso space for a 5.6-stud hero
-- (X = right, Y = up, -Z = forward); they scale with the hero's height.
-- Angles (degrees) aim the weapon: Pitch < 0 = barrel down, Yaw > 0 = barrel swings to the hero's left
-- (across the chest), Roll tilts the weapon sideways.
--   Carry : idle / walking / running
--   Fire  : raised while shooting or aiming down sights (snaps up, eases back ~0.7s after the last shot)
-- Left hand:
--   "Keep"  stays on the weapon where the statue held it (two-handed guns - keeps the mesh in one piece)
--   "Free"  goes to LeftCarry / LeftFire (torso space) - one-handed weapons and melee
-- Kind "Melee": both hands are placed by position only (blades, gauntlet).
-- Lean (degrees): extra forward (+) / back (-) tilt of the upper body. Bob: weapon bounce while running.
export type Pose = { Pos: Vector3, Pitch: number, Yaw: number, Roll: number }
export type Hold = {
	Style: string,
	Kind: string, -- "Gun" | "Melee"
	Left: string, -- "Keep" | "Free"
	Carry: Pose,
	Fire: Pose,
	LeftCarry: Vector3?,
	LeftFire: Vector3?,
	Lean: number?,
	Bob: number?,
	Sparks: string?, -- hand that crackles with electricity ("RightHand" / "LeftHand")
	GripFix: Vector3?, -- degrees (pitch, yaw, roll): lines the sculpted weapon up with the aim, tuned by eye
}

local function P(x: number, y: number, z: number, pitch: number, yaw: number, roll: number): Pose
	return { Pos = Vector3.new(x, y, z), Pitch = pitch, Yaw = yaw, Roll = roll }
end

local HoldConfig = {}

HoldConfig.Heroes = {
	-- Assault: textbook low-ready, both hands, snaps to the shoulder to fire
	Rift = { Style = "Low ready", Kind = "Gun", Left = "Keep",
		Carry = P(0.45, -0.45, -0.9, -28, 18, 0), Fire = P(0.45, 0.3, -0.95, 0, 0, 0), Bob = 0.06 },
	-- Sniper: long rifle diagonally across the chest, muzzle low-left; shouldered to shoot
	Vex = { Style = "Sniper port arms", Kind = "Gun", Left = "Keep",
		Carry = P(0.5, -0.3, -0.65, -18, 40, -10), Fire = P(0.42, 0.35, -0.8, 0, 0, 0), Bob = 0.05 },
	-- Tank: the arm cannon stays at the hip, other hand braced under it, slight lean back
	Titan = { Style = "Hip cannon", Kind = "Gun", Left = "Free",
		Carry = P(0.75, -0.95, -1.0, -8, 4, 0), Fire = P(0.7, -0.65, -1.15, 0, 0, 0),
		LeftCarry = Vector3.new(0.15, -0.95, -1.2), LeftFire = Vector3.new(0.15, -0.7, -1.35), Lean = -4, Bob = 0.09 },
	-- Support: healing staff carried two-handed and level in front, thrust forward to project
	Solace = { Style = "Healer's reach", Kind = "Gun", Left = "Keep",
		Carry = P(0.6, -0.3, -0.95, -12, 25, 0), Fire = P(0.5, 0.1, -1.35, 0, 0, 0), Bob = 0.04 },
	-- Assassin: reverse-grip blades swept back low (ninja run); both blades forward to strike
	Shade = { Style = "Ninja sweep", Kind = "Melee", Left = "Free",
		Carry = P(0.95, -0.85, 0.55, 0, 0, 0), Fire = P(0.45, 0.05, -1.25, 0, 0, 0),
		LeftCarry = Vector3.new(-0.95, -0.85, 0.55), LeftFire = Vector3.new(-0.45, -0.05, -1.25), Lean = 12, Bob = 0.07 },
	-- Controller: gauntlet (left hand) fist cocked at the chest, right hand crackling at the side; punches to cast
	Volt = { Style = "Charged fist", Kind = "Melee", Left = "Free",
		Carry = P(0.95, -0.35, -0.7, 0, 0, 0), Fire = P(0.8, -0.15, -0.9, 0, 0, 0),
		LeftCarry = Vector3.new(-0.7, 0.05, -0.85), LeftFire = Vector3.new(-0.45, 0.25, -1.7), Lean = 5, Bob = 0.06, Sparks = "RightHand" },
	-- Duelist: shotgun at the hip, pump hand forward under the barrel, aggressive forward lean
	Jeric = { Style = "Hip shotgun", Kind = "Gun", Left = "Free",
		Carry = P(0.6, -0.75, -0.85, -12, 14, 0), Fire = P(0.5, -0.45, -1.05, 0, 0, 0),
		LeftCarry = Vector3.new(0.15, -0.8, -1.3), LeftFire = Vector3.new(0.25, -0.5, -1.55), Lean = 10, Bob = 0.08 },
	-- Engineer: rivet gun one-handed, arm relaxed low; snaps straight out to fire. Other hand free at the side
	Forge = { Style = "One-hand rivet", Kind = "Gun", Left = "Free",
		Carry = P(0.85, -0.6, -0.95, -32, 0, 0), Fire = P(0.75, 0.3, -1.55, 0, 0, 0),
		LeftCarry = Vector3.new(-0.95, -1.0, -0.2), LeftFire = Vector3.new(-0.9, -0.75, -0.4), Bob = 0.06 },
	-- Recon: compact SMG tucked high and close, both hands, ready to snap fire
	Echo = { Style = "High tuck", Kind = "Gun", Left = "Keep",
		Carry = P(0.35, 0.1, -0.75, -18, 10, 0), Fire = P(0.35, 0.32, -0.9, 0, 0, 0), Bob = 0.05 },
} :: { [string]: Hold }

HoldConfig.BASE_HEIGHT = 5.6
HoldConfig.RAISE_SPEED = 16 -- snappy (per second)
HoldConfig.LOWER_DELAY = 0.7 -- seconds after the last shot before lowering back to carry

function HoldConfig.Get(heroId: string?): Hold?
	return heroId and HoldConfig.Heroes[heroId] or nil
end

return HoldConfig
