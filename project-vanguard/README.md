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
| 7 Audio & polish: music, TTS announcer + kill streaks, SFX, animations, UI transitions, neon VFX, saved volume settings | Done |
| 8 Leaderboards: MOST KILLS + TOP SUPPORTERS (persistent, top 25, podium avatars, privacy opt-out) | Done |
| 9 Testing & optimization: hero bots (Casual fill + 1v1 Practice), code audit fixes, mobile controls, test matrix | Done |

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

## Audio & polish (Phase 7)
- Music: lobby "Dark Tension Underscore"; one action track per map (APM / DistroKid licensed library tracks). Crossfades, ducks on results.
- SFX: Roblox built-in sounds reshaped per weapon (pitch/distortion) - no ripped game audio. Your shots play instantly, others' in 3D.
- Announcer: Roblox text-to-speech (original voice). Double/Triple/Quad Kill, Team Wipe, On Fire (3), Unstoppable (5), Dominating (7), Vanguard (10), First Blood, Shutdown, Fight/Victory/Defeat, Core secured/lost.
- Animations (R15, generated + published): skill cast, ultimate, victory, defeat, lobby salute (G). Cast plays only after the server accepts the ability.
- VFX: neon low-poly shard muzzle flashes/impacts, digital-dissolve deaths in team colour, viewmodel equip/reload/cast motion.
- UI: button hover/click sounds + bounce, modal fade in/out, deploy/return scanline wipe.
- Settings (dock): Music / SFX / Announcer sliders, saved in the profile (`Progress.Settings`), validated server-side. Tunables in `AudioConfig`.

## Leaderboards (Phase 8)
- Hall of Fame wall: MOST KILLS and TOP SUPPORTERS stand either side of the Ranked board (models `KillsSign` / `RobuxSign`; the old far-wall signs are parked in `ServerStorage.UnusedLobby`).
- OrderedDataStores `VG_Board_Kills` / `VG_Board_Robux` (Studio uses `STUDIO_`). Every 5 min: write changed scores, read top 100, show top 25 (auto-scroll), exact "YOU #n" line up to #100.
- Kills = real players only (`Progress.Stats.PlayerKills`, counted at the elimination). Robux = `Progress.RobuxSpent`, only increased by granted ProcessReceipt purchases.
- Privacy: Settings > "TOP SUPPORTERS: HIDDEN" shows you as Anonymous (hologram on the podium). Stored as `spent*2 + hidden`, no extra reads.
- Top 3 of each board stand on top of it as animated avatars. Tunables: `GameConfig.Leaderboards`.
- Studio-only QA hook `ServerStorage.VG_LeaderboardTest` (AddKills / AddRobux / Refresh) - not created on live servers.

## Bots, security & mobile (Phase 9)
- **Bots** (`BotService`): play the real heroes, tagged `[BOT]`. Fill Casual to 5v5 (`GameConfig.Bots.CasualFillTo`; a lone Casual queue starts with bots after `CasualFillAfter` s) and power **1v1 Practice** (no tokens). Never in Ranked/Duel, never give leaderboard kills, never MVP.
- Difficulty: `GameConfig.Bots.Difficulty` = Easy / Normal / Hard (presets: reaction, aim error, fire rate, headshot %, sight, strafe).
- Bots use the same server weapon code as players (`CombatService.BotAttack`), hold/contest the core, pathfind, strafe, respawn; server owns their physics.
- **Security fixes** from the code audit: server-checked headshots, shot origin must be visible from the head (8 studs max), fire-rate token bucket, `MovementGuard` pulls back teleports, receipts only confirmed after a real save, lost session lock = no fake saves, ranked forfeits give no RP, lock released if a player leaves mid-load, refund tokens if a hero is bought twice, leak + spam fixes.
- **Mobile**: `MobileControls` (touch only, in matches): hold-to-fire, reload, dash/skill/ultimate with hero icons + cooldown dimming, via `InputBridge`.
- Studio-only QA hooks: `ServerStorage.VG_BotTest` (Start mode N / End / Difficulty / Brains), `VG_LeaderboardTest`.
- Known limits: weapon spread is applied by the client (small advantage for exploiters with 0 spread); Robux products need `developer-product:write` permission (or manual creation) before they can be created.

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

### Phase 9.1 - Lobby cleanup + Character Select redesign
- Removed the duplicate shop NPC (kept "Isaac Shopkeeper"; the extra one is parked in ServerStorage.UnusedLobby).
- Hall of Fame boards (Top Supporters / Top Ranked / Most Kills) moved onto the back window wall, facing the spawn row.
- Lobby hero statues turned to face into the room; the tree blocking the walkway moved aside.
- Character Select rebuilt from the mockup: 3D statue portrait cards (name, role, Selected / Available / token price),
  hero sheet with "NAME - ROLE", "WEAPON - HP - SPD", description, ABILITIES rows with key badges (LMB/SHIFT/E/Q)
  and a SELECT CHARACTER / UNLOCK button. Portraits re-clone once their meshes finish loading.

### Phase 9.2 - Three new heroes (Jeric, Forge, Echo)
Models made with Roblox Studio's AI mesh generator (no ForgeGUI): statue, helmet and weapon per hero,
stored in ReplicatedStorage.HeroAssets like the first six. All unlock for 2000 tokens (Robux once products exist).
| Hero | Role | Weapon | Dash / Skill / Ultimate |
|---|---|---|---|
| JERIC | Duelist | Scattergun (8-pellet shotgun, 250 HP) | Lunge / Adrenal Surge (heal + speed) / Last Stand (dmg, fire rate, regen) |
| FORGE | Engineer | Rivet Gun (auto projectile, 225 HP) | Thruster Hop / Sentry Turret / Siege Sentry |
| ECHO | Recon | Pulse SMG (fast auto, 175 HP, speed 20) | Zip Line / Sonar Pulse (team reveal) / Resonance (4 damaging, slowing pulses) |
- Shotgun pellets use a fixed shared pattern (WeaponConfig.PelletDirs); the server casts every pellet itself and sums damage per target. Bots use the same code.
- Turrets: server objects that shoot the nearest visible enemy; walls block them; one of each type per Forge.
- Character Select is now a 3x3 grid; lobby showcase has 9 statues.
- Ability icons are drawn in assets/icons; until they are uploaded, IconConfig borrows the closest existing icons.

### Phase 9.3 - Ultimate effects, Solace sound, owner unlock, icon reliability
- UltFxController (new): every ultimate gets a burst (neon ring, light pillar, flash, sparks) and an aura while active
  (rising motes, orbiting orbs, outline glow) for everyone; the caster also gets a hero-coloured screen-edge glow and
  an "ULTIMATE / <NAME>" callout. Visual only.
- Solace's Medical Projector now plays a soft energy hum (pitched-down ping + EQ roll-off + chorus via new Sfx options Soft/Chorus).
- The game owner's account (game.CreatorId) has every hero unlocked, in Studio and live.
- HUD ability icons are preloaded in the lobby and re-requested if an image is slow to arrive.
