--!strict
-- InputBridge (Phase 9): lets on-screen touch buttons (MobileControls) drive the same code paths as the
-- mouse / keyboard. CombatController listens for Fire/Reload, AbilityController for Ability.
-- Client-only and cosmetic-free: it only forwards button presses; the server still validates everything.
local InputBridge = {}

local fire = Instance.new("BindableEvent")
local reload = Instance.new("BindableEvent")
local ability = Instance.new("BindableEvent")
local aim = Instance.new("BindableEvent")

InputBridge.FireChanged = fire.Event   -- (down: boolean)
InputBridge.Reload = reload.Event      -- ()
InputBridge.Ability = ability.Event    -- (slot: "Dash" | "Skill" | "Ultimate")
InputBridge.AimChanged = aim.Event    -- (on: boolean)

function InputBridge.SetFire(down: boolean) fire:Fire(down) end
function InputBridge.PressReload() reload:Fire() end
function InputBridge.PressAbility(slot: string) ability:Fire(slot) end
function InputBridge.SetAim(on: boolean) aim:Fire(on) end

return InputBridge
