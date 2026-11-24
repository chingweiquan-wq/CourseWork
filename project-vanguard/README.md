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
| 4 Game modes: Hold the Core, ranked (saved, 7 tiers), match history, MVP results | Done |
| 5 Progression: tokens, hero unlocks (tokens + Robux), daily 7-day streak, Isaac shop, saving | Done |
| 6 Cosmetics: 12 weapon skins (Arctic / Royal Gold / Void), inventory, shop SKINS tab, Robux skin purchases | Done |
| 7 Audio & polish | Not started |

## Ranked
- Saved in DataStore `VG_PlayerData` (Studio uses `STUDIO_` stores). Start 450 RP (Silver II), 100 RP per division.
- Bronze/Silver/Gold/Platinum/Diamond have III-II-I; Master 1500+, Vanguard 1800+. Tunables in `GameConfig.Ranked`.

## Tokens
- Finish +40, win +30, MVP +10, ranked x1.25. No tokens for abandoned matches or AFK players (active < 30% of the match).
- Daily streak: 50, 75, 100, 125, 150, 200, 300 (resets at 00:00 UTC = 8am Malaysia time).
- Robux hero purchases: put developer product IDs in `ReplicatedStorage/Modules/ProductConfig.lua`.

## Weapon skins
- 2 per weapon: Arctic (Uncommon, R$25) and a Legendary (R$99): Royal Gold for Burst/Heavy Cannon/Gauntlet, Void for Precision/Medical/Blades.
- Legendaries have animated glowing trims and coloured tracers. Equip from the Skins dock button or buy in Isaac's shop SKINS tab.
- Robux skin purchases: put developer product IDs in `ProductConfig.SkinProducts`. In Studio every skin counts as owned (`GameConfig.Cosmetics.StudioOwnAllSkins`); live servers don't.

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
