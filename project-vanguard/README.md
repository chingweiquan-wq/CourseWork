# PROJECT VANGUARD

Roblox multiplayer hero shooter. This folder is a script backup taken from Roblox Studio after each phase.
The live game lives in Studio (place 90633802455621); models, maps and UI are not in this backup, only code.

## Phase status
| Phase | Status |
|---|---|
| 1 Foundation (lobby, queue, matches, maps) | Done |
| 2 Combat (server-authoritative weapons, K/D/A, kill feed) | Done |
| 3 Abilities (Dash / Skill / Ultimate for 6 heroes) | Done |
| Visual pass (darker lighting, 3D weapons, helmets, lobby statues) | Done |
| 4 Game modes, objective scoring, ranked | Not started |

## Layout
`src/` mirrors the Studio tree:
- `*.lua` = ModuleScript, `*.server.lua` = Script, `*.client.lua` = LocalScript.

## 3D assets (ForgeGUI, published to @Kikyo333666)
| Hero | Weapon | Weapon asset | Helmet asset | Statue asset |
|---|---|---|---|---|
| Rift | BurstRifle | 102947790244307 | 109539925961297 | 102262028340414 |
| Vex | PrecisionRifle | 119759193185264 | 111745486269117 | 84516404995547 |
| Titan | HeavyCannon | 96381441014382 | 116714257663536 | 85329290152464 |
| Solace | MedicalProjector | 90456627656317 | 135114278623034 | 83184559794545 |
| Shade | EnergyBlades | 126864263657869 | 118045143643235 | 105146199611860 |
| Volt | LightningGauntlet | 117517941331379 | 133295735736093 | 138525194415718 |

Third-party kits included in `src/StarterGui`: Premium Health Bar, Clean Shop GUI (by @roary16).
