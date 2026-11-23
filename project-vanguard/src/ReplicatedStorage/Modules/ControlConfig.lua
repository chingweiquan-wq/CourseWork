--!strict
-- ControlConfig: all PC keybinds in one place. Change a key here and every script follows.
-- (A settings menu to rebind keys can write to this table later.)
local ControlConfig = {}

ControlConfig.Binds = {
	Fire = Enum.UserInputType.MouseButton1,
	Reload = Enum.KeyCode.R,
	Dash = Enum.KeyCode.LeftShift,
	Skill = Enum.KeyCode.E,
	Ultimate = Enum.KeyCode.Q,
	Jump = Enum.KeyCode.Space, -- handled by Roblox's default controls
}

-- Short labels drawn on the ability HUD
ControlConfig.Labels = {
	Dash = "SHIFT",
	Skill = "E",
	Ultimate = "Q",
	Reload = "R",
}

return ControlConfig
