# Patch Notes

Chronological log of what changed and why — bugs found, root causes,
judgment calls made without stopping to ask. `README.md` describes the
project as it stands today; this file is the history of how it got
there. Most recent first.

---

## 2026-10-06 — v4.17: Storm title background, Hub nebula sky (user request)

- Title background rebuilt (`MainMenuBackground.gd` + `menu_*` shaders): storm sky with warped clouds, silver-lined edges and a haloed moon (beams toned down on request); layered ridges with moonlit rims and mist; a lake with a glittering moon path and rain ripples; a Dalaran spire on a crag; two rain layers; forked lightning bolts synced to the thunder that light the clouds, lake and ridges; slow camera drift.
- Bolt was invisible at range: the sky sphere used `depth_draw_never`, which moves a material into the transparent pass, where the sphere (centred near the camera) sorted after the bolt and painted over it. The sky now uses normal depth.
- Hub: `nexus_nebula.gdshader` on a sky sphere - a nebula band (3D noise, no seams) arcing across the void with dust lanes and bright cores, a second violet cloud, and stars crowding into the band.

---

## 2026-10-06 — v4.16: Main menu overhaul (user request)

Left-column title screen over the animated background: dark gradient, large gold title, text buttons that turn gold and slide on hover with a staggered fade-in, fade from black, gold-framed Settings/About panels, version tag. Menu and Hub music raised from -10 to -5 dB.

---

## 2026-10-06 — v4.15: Memory Nexus Hub, LOD fix (user request)

The user asked whether the Hub could look like Path of Exile's Synthesis
Memory Nexus (three reference screenshots) and then to "make this the best
looking piece possible."

- Built `levels/hub/MemoryNexus.gd` + five shaders (`nexus_*`). The key
  look - platform edges dissolving into blue-bordered flakes over a void -
  is a signed-distance union of circles/capsules evaluated in the floor
  shader, the same shapes the collision uses. Renderer is GL
  Compatibility, so no volumetrics: depth comes from fog matched to the
  background colour, glow, CPU particles and additive shafts.
- Props: a new "nexus" doodad kit (Circle of Power, Waygate, Arcane
  Vault, Magic Vault, treasure chest, crates, tome, crystal lamp, Dalaran
  ruin crystals, colonnade, broken columns, Icecrown crystals, Violet
  Hold spires) plus Dalaran marble grounds, pulled from the local WC3
  install. Iterated through in-engine viewport snapshots; tuning passes
  dimmed the far void plane (it read as a blue floor), shrank particles,
  softened the parquet contrast, warmed the floor.
- The Arcane Observatory centrepiece looked broken. Root cause was
  general: Reforged models carry LOD 1-3 copies of every mesh and the
  wrappers drew all of them stacked (z-fighting). The sidecar now records
  each geoset's `LevelOfDetail` (`patch_sidecars.js` back-filled all 94)
  and `build_mdx_wrappers.gd` hides LOD > 0. This also fixes Teron
  (Threshold Knight), the Zombie Footman and most dungeon/desert doodads.
  The user then asked to drop the observatory anyway; a floating crystal
  formation replaced it.
- Screenshot method changed: one desktop capture grabbed the user's screen
  instead of the game window (it was deleted right away). Snapshots now come from
  `get_viewport().get_texture()` inside Godot - no desktop access at all.
- KillBox: no Life penalty outside a map (detected via the new
  "generated_map" group instead of `current_scene`).
- Tests: Hub checks added to `tests/v414/` (solid ground at spawn, every
  interactable and the dais; the void is open).

---

## 2026-10-06 — v4.14: spell levels, map layouts, new enemies, combat fixes (user request)

A batch request covering enemy feel, melee hitboxes, settings, portals, a
balance pass, new enemy models, a kill box, a spell overhaul and new map
layouts per Figment type.

**Enemies**
- Attack lock: enemies were sliding into the player during their own
  wind-up. `Enemy.is_attack_locked()` roots them from the wind-up start
  (melee telegraph/strike, ranged windup) until the Attack animation
  state ends, so the follow-through doesn't slide either.
- Foot sliding: WC3 walk clips are authored for a ground speed (the MDX
  sequence `MoveSpeed`, e.g. 270 units/s = 4.86 m/s for the bandits) while
  our units move at 2.5-4 m/s, so legs cycled ~40% too fast. The sidecar
  now records `move_speed` per sequence (`mdx_sidecar.js`; existing
  sidecars patched by `patch_sidecar_speeds.js` without reconverting), the
  wrapper builder writes it to `MdxModel.clip_move_speeds`, and
  `EnemyAnimationController` stretches the Walk/Run node timeline to
  actual speed / authored speed. Retiming is skipped for <8% changes
  since it remaps the cycle's phase. Models without MoveSpeed (golems,
  Mindbender, Priestess) use `AnimationSet.walk_clip_speed` (270 x scale).
- New models converted and set up (heights tuned against the 1.8 m player
  via the sidecar bounds): Zombie Footman became the existing, model-less
  Hollowed Shambler; Nathrezim -> Legion Dreadknight; the three Arcane
  Golems -> Synod Warden/Ember/Aether Golems; Mindbender and Priestess of
  the Damned -> a new Veilborne faction (the roster doc lists the
  Veilborne Choir as "without models this round"); Xalatath -> a second
  Pinnacle boss (melee + Entropic bolts beyond 5 m). Faction/stat choices
  are judgment calls. Melee and ranged components on one enemy no longer
  start attacks while the other is mid-attack.
- The wrapper rebuild re-saved every doodad wrapper with new
  `unique_id`s only; those were reverted to keep the diff clean.

**Player combat**
- Melee used one small sphere on the blade and resolved the first body it
  touched. It now sweeps a per-weapon-family arc in front of the camera
  every Strike frame (reach, half-angle, splash share, target cap), with
  a line-of-sight ray that only walls block. Primary target (nearest the
  crosshair) takes full damage and gets Riposte/headshot/hit feedback;
  others take 40-75% splash (100% on a charged attack).
- Casting is only interrupted by a stun now (`StatusEffectComponent`
  `is_stunned()` on effect applied), not by any damage taken.

**Spells**
- Ranks (0-5, gold) replaced by levels 1-20 costing gold + Crystallized
  Aether (2 Aether at level 1, 120 for 19 -> 20, curve exponent 1.6;
  gold 20 x level^1.4). Old saves' ranks convert to level rank + 1.
- Each spell has its own level-1 damage range (hand-tuned against the new
  mob health; DoT/field spells per tick) growing 9.5%/level. Conduit
  `spell_power_min/max` removed from the script and all 108 Conduit
  `.tres` files; a Conduit's local increased Spell damage still applies.
  The "requires a Conduit" card line is gone - cards state the damage.
- Tags (Area, Projectile, Duration, Limit, Channelling, Movement,
  Utility + Spell + damage type) gate modifiers that were previously
  summed but never read: increased Area damage, AoE radius, Skill Effect
  Duration (field spells and Frost Armor), Projectile Speed (bolts), Mana
  cost reduction, Cooldown Recovery. Levels past 20 (from gear's
  existing "+N to level of Spells" affixes, which used to give +8%
  effectiveness each) grant over-cap bonuses per tag.
- Crystallized Aether drops on its own 18% roll per kill; the Hub's
  Spell Testing Shop hands out 100 for testing.

**Maps** - only Dungeon keeps the room grid. New `MapLayout` rules per
Figment type: Dunes is one open field (no interior walls) with dune
mounds, a ridge boundary and a boss dune crest; Badlands is a canyon of
basins joined by narrow passes between jagged cliffs, with a boss mesa.
Both still produce a `MapGraph`, so spawning, the Map screen and portals
work unchanged. Boss spawn height was 0.95 m above its platform (carried
over from the Vault code; enemy origins are at the feet) - fixed for
every layout after the user spotted it in a screenshot.

**Other fixes**
- Portal appeared half-sunk: it was placed at the player's feet minus
  1 m. Now ray-cast onto the floor under the spot.
- Settings: the pause menu had none. A shared `SettingsPanel` (title
  screen + pause menu) adds Field of View and V-Sync and saves to
  `user://settings.cfg`, so New Game no longer wipes settings.
- Kill box autoload: fallen enemies die, a fallen player is returned to
  the last solid ground with a 15% Life penalty (killing the player for a
  geometry gap felt wrong).
- Balance: mob health was still x1.5 from the old conduit spell tuning;
  a level-1 standard mob took ~16 s to kill with the starter weapon.
  Health table cut to 30/55/110/280/1600, damage trimmed slightly,
  FigmentBoss 1760 -> 700 Life (now +35% per tier, previously no tier
  scaling at all) and 61.6 -> 40 per hit.

Tests: new `tests/v414/` (77 checks); roster test extended to the new
units; all existing suites pass.

---

## 2026-10-06 — Crafting, Inventory, Stash & Portals Rev2 (Claude Code brief)

Built the three-phase brief from `documents/Aether_Crafting_Inventory_Rev2.docx`. Rev2 replaces Section 20's Cube with Orbs (do the operation), Brands (steer it) and Edicts (restrict it), and adds a footprint inventory, a Hub stash and portals.
- **Conflicts and decisions (asked before building):** the Cube was built alongside first, then retired; `ItemAffix` stays the rolled-modifier type (gained `def`/`group`/`anchored`); corruption now always ends crafting (the 20% retain-craftable roll is gone); drops keep rolling 0..max sockets, so the Orb of Opening only works on an unopened item with 0 sockets; the "one of every base" inventory catalogue was dropped for the 12x6 footprint grid, reversing the earlier uniform-1x1 choice.
- **Phase 1, Orbs:** `CraftingResolver` with a side-effect-free `preview()` (exact per-modifier/tier chances, groundwork for the future crafting guide) and an `apply()` that validates fully first, so a failed craft spends no Orb, Brand or tolerance. Seedable RNG for tests. Recasting only removes a modifier that can be replaced, which keeps preview odds exact. Added `MISSING_CURRENCY` to the brief's error list.
- **Real pools:** rather than copying `ItemRoller.AFFIX_POOL` and the weapon affix library into a separate file that could drift, `GearModifierPool` builds ModifierDefs from them with the same eligibility rules drops use; item level gates top tiers like `_roll_tier()`. `SlateModifierPool` does the same from the Slate affix stubs. AFFIX_POOL has no prefix/suffix, so a keyword list decides.
- **Phase 2, grid and stash:** `GridInventory` (footprints from `data/inventory/footprints.tres`, no rotation, currency stacks to 100) and `Stash` (4 general tabs + Currency + Slate). Then moved the real game onto it: `owned_loot`/`owned_slates`/`inventory_slot_assignment` are gone; equipped gear and placed Slates live off-grid; equip swaps undo if displaced gear can't fit; full inventory leaves loot on the ground; shops refund when there's no room. Saves migrate (`SaveManager.INVENTORY_VERSION` 2) - old saves also kept equipped items inside `owned_loot`, matched against the equipment refs so nothing is duplicated. Placed Slates are now saved in full instead of by index.
- **Bugs found on the way:** `ItemSerializer` never saved `sockets` or `quality`, nor weapon affixes' `damage_type`/`is_generic`/`is_local`, so a rolled weapon's damage bucketing changed after a reload. All saved now.
- **Inventory doesn't pause:** combat input (attack, parry, abilities, stance, weapon swap) is ignored while the cursor is visible, otherwise a click in the inventory also fired the weapon.
- **Phase 3, portals:** maps now generate from a stored seed (`seed()` before generation, `randomize()` after), so leaving saves only the seed, defeated enemies (by spawn order), ground loot, portal/player spots and the Figment. Verified by rebuilding three maps and comparing every surviving enemy's unit, rarity/affixes and spawn point. Surviving enemies come back at full health in their spawn spots. Death or entering a new map ends the run. Added a walk-up Stash chest and screen in the Hub.
- **Cube retired:** removed `craft_cube`, `BrandCombinationResolver`, the Brand item class and 26 Brand files, `BrandRoller`, the Brand Shop and the Brand rarity constants. Enemies drop Orbs/Brands/Edicts as currency pickups instead (placeholder weights). Old Brands in saves convert on load (`ItemSerializer.LEGACY_BRAND_CURRENCY`). The Crafting screen (K) was rebuilt around Orbs, Brands and Edicts; Slate drops now start Common (Aether cost unchanged).
- **Test harness gotcha:** a GDScript runtime error aborts only the current function and the run still exits 0, so every new suite counts finished test functions. A Variant-inferred `:=` is a parse error here and makes a headless scene hang - always pass `--quit-after`.
- Verified: `tests/crafting/test_crafting` 1238 checks, `test_real_pools` 111, `tests/inventory/test_inventory` 74, `test_inventory_game` 31, `tests/portal/test_portal` 67, `tests/test_roster_ammo.gd` passing; MainMenu/Hub/GeneratedMap/TestArena/PinnacleArena load clean.

## 2026-10-06 — Dungeon and Desert tilesets (user request)

Built the first two families from the Tileset Plan doc: Dungeon (Cellblock, Undercroft, Mine, Foundry Pit, one palette each, per the user's decision) and Desert (Dunes, Badlands). A Figment rolls its style at random.
- **Kits:** `tools/mdx_pipeline/doodads.json` lists each family's doodads by placement role (archway, wall, floor, cluster, light, support) and its ground textures. `extract_doodads.js` pulls only those from the local WC3 install (48 models + textures, 26 ground sheets). The build wrapper tool now also writes doodad wrappers (no AnimationTree).
- **Converter fixes found on the way:**
  - The doodads are a newer MDX revision (v1800). Their light records carry 28 extra bytes (v1200's carried 4), so the loader now drops everything up to the first animation keyword. A camera chunk also broke `war3-model`; cameras are dropped before parsing.
  - v1800 static doodads store all-zero skin weights and rely on classic matrix groups. Every vertex collapsed and nothing rendered. Zero-weight vertices now bind fully to their group's first node.
  - `barrensthorns0.mdx` in the game data is an empty placeholder; the converter now refuses geometry-less models.
- **Ground shader:** 2048-wide WC3 sheets hold 16 full variants in their right half; 1024 transition sheets only have cells 0 and 15 full (measured by alpha coverage). One variant per world cell, with textureGrad to avoid mip seams. Walls reuse it with axis projection; the first pass smeared wall tops until they got their own top-down projection.
- **Look checks:** windowed first-person and room shots of all six styles. The first Dungeon pass was too dark to fight in; ambient and light energies were raised. WC3 standing torches are about 1.1 m at unit scale, so wall lights are scaled 1.8x. Their fire was WC3 particles, which don't convert, so a flickering omni light stands in.
- **Figments:** `FigmentItem.tileset_id` is rolled, saved and shown on the card ("Area: Cellblock (Dungeon)"). Figments are now named "<Style> Figment"; the old "Tier N Figment" name went stale when empowered.
- **Size:** the two kits add about 356 MB, mostly 4K-ish textures. Downscaling stand-in textures is a cheap later option.
- Verified: `tests/test_roster_ammo.gd` now also checks every style and its doodads, rolled Figments' styles and save/load, and a dressed map in each style. 1041 checks, 0 failed.

## 2026-10-06 — Animation-only attack telegraphs (user request)

The yellow wind-up flash (and the Lord's element-tinted flash) is gone; attacks read from the animation.
- `Enemy.begin_attack_telegraph(windup_sec)` now only starts the attack clip. `update_attack_telegraph()`, `end_attack_telegraph()`, `_apply_mesh_color()`, `_set_placeholder_color()`, `telegraph_color` and `_model_meshes` were removed, along with their calls in `EnemyMeleeAttack`/`EnemyRangedAttack`.
- `EnemyAnimationController.play_attack(windup_sec)` stretches the Attack state's clip (`use_custom_timeline` + `stretch_time_scale`) so the frame at `AnimationSet.attack_hit_fraction` lands when the wind-up ends - the moment the melee strike resolves or the projectile fires. Speed is clamped to 0.4x-2x.
- If a previous swing's follow-through is still playing, the Attack state restarts instead of pulsing: there's no Attack -> Attack transition, so a pulse could be missed.
- Hit fractions were checked by rendering every model frozen at that frame: 0.45 lands on contact for most; the Javelineer's throw and the Brigand's stab release at 0.4.
- Test: each unit's hit frame lands within 0.01 s of its wind-up end and no material override is applied (876 checks, 0 failed).

## 2026-10-05 — Enemy Roster v1 + Ammo Store (Claude Code brief)

Brief: `documents/Aether_EnemyRoster_AmmoStore_ClaudeCode_Brief.md`; unit data from *Enemy Roster & Factions*.

**Models (`tools/mdx_pipeline/`):**
- All 10 models are converted through `models.json` + `convert_all.js`. Scales: bandits 0.018 (1.8-2.9 m, the Chieftain is mounted), Exarch 0.018, Adjudicator/Vindicator/Knight 0.02, Lord 0.033 (6 m). Every model's front is +X, so every definition uses `model_yaw_offset` -PI/2 (checked visually).
- `heropaladin.mdx` didn't parse: `war3-model` rejects its Reforged light record (4 extra bytes). `mdx_load.js` strips them; lights aren't exported.
- Import found NaN quaternions: baking decomposed zero-scale keys (WC3 hides bones that way). R and S now come straight from the evaluated channels. Empty geosets (Teron) are skipped.
- The Brigand's sword geoset pads unused skin slots with joint 255 (skeleton has 144 bones). That triggered Godot's `bs > sbs` error every frame; unused slots are now written as joint 0.
- `Decay*`/`Cinematic*` sequences aren't baked anymore (bandit .glb 17-29 MB -> 3-6 MB).
- WC3 hides corpse/alternate geosets through geoset alpha. The sidecar records visibility per clip and `MdxModel.gd` applies it, or corpses would render on every live bandit.

**Textures:**
- Each conversion writes a `.mdxmeta.json` sidecar (geoset -> textures, blend mode, visibility). `tools/build_mdx_wrappers.tscn` builds the 10 wrapper scenes and their materials from it. Arator now goes through the same path; its hardcoded geoset table is gone.
- Godot 4.7.1 loads the .dds files natively, including the BC5 normals and ORM maps. 12 Omniknight files had a wrong DDS linear-size header field and were refused; `fix_dds_headers.js` repaired them in place (user choice). Pixel data is untouched.
- First renders showed the Vindicator/Exarch blown-out white: Godot's default emission operator adds the emission color to the texture, so the color must be black.
- The bandits, the Chieftain, much of Teron and parts of Arator/Candace/Progenitor referenced base-game Reforged textures that weren't shipped. CascLib's Node bindings couldn't build (no C++ toolchain), so `casc_reader.js` is a small read-only CASC/TVFS reader. `wc3_textures.js` uses it to pull only the referenced files from the local install (142 files, none missing). `convert_all.js` does this automatically, so future stand-in models need no manual texture work. **No untextured geosets remain.**
- Duplicate clips in the source models: Vindicator `Attack 2` = `Attack 1` (and `Base`, `Stand 3` = `Stand 1`); Javelineer/Brigand/Enforcer `Stand Hit 1` = `Stand 1` and `Death Fire 1` = `Death 1`. The Javelineer has no `Attack 2`, so it matches the Brigand's assumed clip set. Adjudicator clips: Stand 1-3, Walk 1, Attack 1/2, Spell 1, Death 1, Dissipate; it has no hit or channel clip.

**Code:**
- `EnemyDefinition.model_yaw_offset` / `is_ranged`. `Enemy._install_model()` was split out of `_apply_model()` so FigmentBoss can reuse the Chieftain definition's model at 1.5x.
- `EnemyAnimationController._apply_loop_modes()` loops idle/walk/run and plays one-shots once. Hit/stagger are no-ops without a clip: the idle fallback loops, so the HitReact state never reached its end transition and the unit got stuck in it.
- Retired GlassCannon/MobileBruiser/HeavyHitter, `glass_cannon.tres`, `Constants.EnemyArchetype` and `Enemy.archetype`. FigmentBoss keeps its old effective numbers as constants (1760 HP, 61.6 dmg, 250 XP, 120 Gold).
- Packs: `Constants.ENEMY_PACKS_NORMAL` / `ENEMY_PACKS_VAULT_ELITE`, rolled by `EnemyRoster.roll_pack()`.
- Lord of the Elements: Fire -> Cold -> Lightning per attack, with the flash tinted through the new `Enemy.telegraph_color`. PinnacleArena spawns Player + boss + UI (F6-testable).
- AmmoStore (Hub): one press = full resupply. It cancels a reload via the new `PlayerRangedAttack.cancel_reload()` and emits `ammo_changed` so the HUD re-reads the magazine.
- Now-unreferenced UAL resources (kept): `UALHumanoidModel.tscn`, `ual_humanoid.tres`, `ual_humanoid_ranged.tres`, and `UAL1_Standard.glb` through that wrapper.

**Verified:** `tests/test_roster_ammo.gd` (`--headless --script`): 853 checks, 0 failed. It covers definition health/damage scaling, both unit scenes x 10 definitions (model, AnimationTree, AnimationSet, every clip name, loop modes), the Lord's element cycle, 20 GeneratedMap runs (all roster enemies plus exactly one FigmentBoss, no engine errors), the 4 ammo-store cases plus reload cancel, and no references to the retired names. Windowed screenshots: every model idle and mid-attack next to a 1.8 m capsule, TestArena with all 9 units, the Pinnacle Arena with the Lord, and the FigmentBoss.

## 2026-09-27 — Item card shows one value, item mods only (user feedback)

The v4.10 card showed two values, "base → modified" (e.g. Flicker Knife "Piercing Damage: 2 to 5 → 3 to 8"). The modified range also included the character's Strength, so it turned blue even on an item with no mods. Now:
- Every value line shows one value: the item's own number in white, or in blue when a mod on the item changes it. The modified value replaces the base one; it doesn't sit next to it.
- The damage line no longer applies Strength; only the item's local increased Weapon Damage.
- Real per-hit damage with Strength is still on the character screen (Main Hand/Offhand Damage). Combat is unchanged: Strength and local mods both still apply to hits.
- Verified: an unmodded Flicker Knife reads "2 to 5" / "8%" in white; with +50% local damage/crit it reads "3 to 8" / "12%" in blue.

## 2026-09-27 — Implementation Brief v4.10: Local Weapon Mods + Item Card + Fate Board Polish + Tooltip

**1. `_get_stat_contribution()`:** already gone. It was deleted in v4.8, and the card has shown ranges since the per-hit range change. Nothing to fix.

**2. Local weapon mods:**
- `ItemAffix.is_local` was added, and 5 affix files were created:
  - `generic/`: `local_increased_weapon_damage` (prefix, 10-24%), `local_increased_attack_speed` (suffix, 8-18%), `local_increased_crit_chance` (suffix, 10-30%).
  - `conduit/`: `local_increased_spell_damage` (prefix, 10-24%), `local_increased_cast_speed` (suffix, 8-18%), filtered to the 9 Conduit type keys.
- Tier-1 values as specified; the existing tier decay applies.
- **Eligibility uses `Weapon.is_conduit`, not the type key:** Conduit locals only roll on real Conduits and the others only on martial weapons (`ItemRoller.CONDUIT_LOCAL_KEYS`). The brief's filter-only rule let Conduit locals roll on `worn_staff.tres`, a melee "Staff" that shares the Conduit staff line's key; the test caught it.
- One of each per weapon is already guaranteed by the no-duplicate pick.
- Rolled and saved affixes are recognized by their `local_` stat key. `is_local` is only read at roll time; `ItemSerializer` doesn't save it and doesn't need to.
- **Local Weapon Damage and local Crit apply to the weapon's own hits (user decision):** `Weapon._base_hit()` multiplies by `get_local_multiplier("local_increased_weapon_damage")`, and crit rolls against `get_local_crit_chance()`. Neither ever touches the global StatSheet pools. Local Attack Speed, Spell Damage and Cast Speed are display-only, per the brief.

**3/4. Item card:**
- Weapon damage: "Kinetic Damage: 10 to 14 → 21 to 29" — the raw range in white, then blue with Strength x local Weapon Damage.
- Crit Chance, Spell Power, and (only when a local mod exists) Attack Speed and Cast Speed use the same white → blue line via the new `_add_value_line()`/`_add_weapon_value_lines()`. They moved out of the plain-string `_item_stat_lines()`.
- "Base Crit Chance" is now "Crit Chance"; there were no other "Base " labels.
- This replaces the single darker-grey range from the 2026-09-27 color request. The brief specifies white base + blue modified.
- The Attack Speed line appears only when modified. Weapons have no attack speed stat, so a "1.00" line on every card would carry no information.
- Spell cards keep their single per-cast range line.
- The character screen's crit summary uses the local crit chance too.

**5. Fate Board:**
- There was no background grid shader to change. The shader already discards empty cells, and `_draw_walls()` already skips same-Slate edges. The visible lines inside Slates came from the nebula shader: each cell sampled noise in its own local UV with a random per-cell phase (a seam at every cell edge), plus a per-cell edge vignette.
- Noise and stars are now sampled in board space, and the vignette only darkens edges whose neighbor isn't the same color, so each Slate reads as one shape.
- `DEFAULT_ZOOM` 1.5 -> 2.2 and `ZOOM_MAX` 3.0 -> 4.0.
- Checked in a real window: two saved Slates render seamlessly, and the grid shows only on empty cells.

**6. Tooltip (profiled, per the brief):** `display_item()` took 8.9 ms per card. `_stat_sheet_for_card()` called `get_tree()` on the not-yet-in-tree tooltip card, which returns null but prints an engine error with a GDScript backtrace, twice per build and on every hover. Guarding with `is_inside_tree()` brought it to **1.5 ms per card (6x faster)**. Instantiating the card itself costs 0.03 ms. Caching wasn't changed: Godot frees the tooltip node on hide, as the brief noted, and a 1.5 ms build doesn't need it.

**Verified:**
- 6000 random drops: all 5 locals roll, none on the wrong weapon class, no duplicates, descriptions formatted. 400 Worn Staff rolls had no Conduit locals.
- +20% local damage scales the hit range by exactly 1.2.
- +50% local crit makes crit chance exactly 1.5x base before Agility/gear.
- Local spell damage doesn't change spell damage.
- Both cards and the Fate Board were checked in a real window. Hub loads clean.

## 2026-09-27 — Per-hit damage ranges (user request)

Weapon and spell damage is now a real "min to max" range rolled on every hit, instead of one fixed number:
- **Weapons:** `Weapon.roll_damage()` rolls the base damage uniformly within `base_damage_min`..`base_damage_max` each hit.
- **Spells:** `Ability.roll_damage()` rolls the equipped Conduit's spell power within `spell_power_min`..`spell_power_max` each cast. `StatSheet.conduit_spell_power` became `conduit_spell_power_range` (a Vector2).
- Stats, motion value, grade, chain bonus and crit apply on top as before.
- `predict_damage()` uses the range midpoint. That's the exact average, since damage is linear in the base and the roll is uniform. The new `predict_damage_range()` returns the non-crit min/max for display.
- **The per-drop roll is gone:** `ItemRoller` no longer rolls `rolled_base_damage`/`rolled_spell_power`. The fields stay only so older saves and `.tres` files still load. Two drops of the same base now share the same range; affixes differentiate them. Data check: all 651 weapons have min < max, and every Conduit has a spell power range.

**Display:**
- Weapon cards: "Kinetic Damage: 18 to 25" (the range x Strength, whole numbers, both in the grey from the earlier color change). This replaces "base → boosted".
- Conduit cards: always "Spell Power: X to Y".
- Spell cards get a damage line for the first time: "Cold Damage: 46 to 67" (per cast, non-crit, with the equipped Conduit), or "requires a Conduit". Non-damaging abilities (Blink, Purge) get none.
- Character screen: Main Hand/Offhand Damage is now a range at that weapon's motion value.

**Verified** (headless, 9 checks):
- 3000 Greatsword hits span the full 17.5-24.5 range and stay inside it.
- `predict_damage_range` matches.
- Card text for the weapon, Conduit, spell with and without a Conduit, and Blink.
- Spell casts never fall below the range minimum.
- The character screen shows a range.

## 2026-09-24 — Implementation Brief v4.9: Post-Rewrite Cleanup + Slate Chain Stat Amplification

Much of this brief was written against the pre-v4.8 code and had already been applied:
- Item 1 (grade ranges, mob health x1.5) was the v4.8 follow-up retune.
- Item 4 (`get_attack_power_from_stats()`) was already deleted and its callers updated.
- The StatSheet/StatSummaryBuilder/ItemCard/SlateRoller Mastery code and the `DAMAGE_TYPE_MAIN_STAT` fallback were already done.

**Done here:**
- **`DamageCalculator.calculate()` lost its `mastery_bonus` parameter** (the brief now allows the signature change). `power = base + stat_value x grade_multiplier`. `mastery_bonus`/`effective_grade_multiplier` were dropped from `breakdown` (nothing read them); `DamageResult` is unchanged. Both callers (`Weapon`/`Ability._base_hit()`) were updated. The file header now describes how weapons and spells use the two halves of the power term.
- **Supercharge removed:** `StatSheet.supercharged_stat`/`SUPERCHARGE_MULTIPLIER`, the `get_stat()` branch, and the character screen row. No `.tres` set it.
- **Slate stats:** `MAIN_STAT_PER_TILE` 1.7 -> 0.6 and `RANDOM_STAT_PER_TILE` 0.8 -> 0.3. The new `ChainCalculator.slate_stat_bonuses(board, chains)` gives `Player` its `slate_bonus`. Each placed Slate's `flat_strength/agility/intellect` lines are multiplied by (1 + the bonus of the chain it's in), and every other modifier is untouched. The chain formula and `compute_chains()`/`bonus_by_tag()` output are unchanged.
- **A lone Slate is its own chain.** The chain formula counts a Slate's own tiles, so an unconnected 11-tile Slate gets 11% (6.6 x 1.11 = 7.33), not the 0% the brief's second example assumed. This is kept consistent with the damage chain bonus, which has always counted lone Slates. **Confirmed as intended (user decision).**
- **Existing Slates keep their old values:** the per-tile cut only affects newly rolled Slates. The 7 hand-authored palette Slates (`.tres`, left alone per the brief) and Slates already in saves keep their 1.7/0.8-era values and now also get chain amplification on top.
- `FateBoard.compute_stat_bonuses()` (unamplified) was left unused at first because the brief put `FateBoard.gd` off-limits. **Follow-up (user decision): deleted as dead code.**
- Weapon `_base_hit()` has the brief's scaling_grade comment; the `DAMAGE_TYPE_MAIN_STAT` mention in `weapon.gd` is gone.
- **README** was updated: the stat section, per-point values, both damage formulas, Mastery/Supercharge removal, and Slate chain amplification. Several passages that had been stale since v3.8 were also fixed: Resilience is gear-only, and Debuff effectiveness is a flat 1.0 with no stat behind it.

**Greps:**
- Supercharge: 0.
- `get_attack_power_from_stats`: 0.
- Mastery: only `SlateSerializer`'s old-save drop of "mastery" modifiers, which is required.
- prowess/finesse/resolve: only the `ItemSerializer` save-migration map, which is required. The rest are the verb "resolve" (`_resolved_this_swing`, `enemy_attack_resolved`, `resolve_tags`...), which the brief's exclusion list doesn't catch.

**Verified** (headless, 12 checks):
- New grade ranges and mob health.
- Supercharge/Mastery/attack-power members gone.
- `calculate()` gives base + stat x grade.
- A lone 11-tile Slate gives 7.326 Agility.
- A 7-tile Slate in a 40-tile Piercing chain: the chain bonus is 35%, stat = 5.67, the special modifier isn't in `slate_bonus`, and the damage chain bonus is unchanged at 0.35.
- The character screen renders with no Supercharged/Mastery/Attack Power rows.
- Hub loads clean.

## 2026-09-24 — Implementation Brief v4.8: Stat Rename + Weapon/Spell Formula Rewrite

Prowess/Finesse/Resolve were renamed Strength/Agility/Intellect everywhere: the enum, StatSheet fields, requirements, affix keys, UI, and data. Every stat effect is now a percentage: Strength gives +1% weapon base damage and +4 Life per point; Agility gives +1% increased Attack Speed, Evasion and Crit Chance; Intellect gives +1% spell damage and Ward, plus +3 Mana.

**Formulas:**
- Weapons: `base x (1 + Str%) x MV x increased x more`. `calculate()` gets `stat_value = 0.0`, so `scaling_grade` no longer affects weapon damage (it's still shown in Alt info).
- Spells: `Conduit SP x (1 + Int%) x grade x MV x increased x more` (user choice, overriding the brief's section 4). This is done by passing the boosted spell power to `calculate()` as `stat_value` with a base of 0, so the grade multiplies it. With no Conduit equipped, spells deal 0 damage, as intended (user decision).
- **Mastery was removed entirely (user decision):** `StatSheet.mastery_by_tag`/`get_mastery()`, `FateBoard.compute_mastery_bonuses()`, SlateRoller's Mastery modifiers, and the Mastery rows on the character screen. `ChainCalculator.amplify_by_mastery()` became `bonus_by_tag()` (a plain per-tag sum). `calculate()` keeps its `mastery_bonus` parameter; every caller passes 0.0. Small (2-4 tile) rolled Slates used to get only a Mastery modifier, so they now have no modifier lines and serve purely as chain links.
- Agility's attack speed feeds `Player.get_action_speed_multiplier()` directly (same bracket as gear `attack_speed`), not through a cached `agility_attack_speed_bonus` field. That multiplier also scales ability cooldowns, as gear attack speed already did.
- `get_attack_power_from_stats()` was deleted rather than left returning 0.0; all its callers were updated.

**Data** (`tools/repair_v48_stat_rename.gd`, idempotent, 754 files changed):
- 776 requirement fields.
- 864 `primary/secondary_scaling_stat` values.
- All `flat_*`/`generic_of_*` stat keys and affix ids.
- `player_baseline.tres` (4 Strength / 7 Agility / 4 Intellect; it lives in `data/stats/instances/`, not the path the brief gave).
- "+N Prowess" descriptions, plus "Prowess Pendant" -> "Strength Pendant" and "Resolve Rune Shield" -> "Intellect Rune Shield".
- The three `generic_of_*` affix files were renamed with `git mv`.
- 3 Mastery modifiers were stripped from palette Slates.
- **All 7 hand-authored palette Slates still used pre-v3.8 six-stat keys** (`flat_vitality`/`instinct`/`arcane`/`enigma`), which `repair_stat_migration.gd` had missed, so they gave no stats. After this rename, their `flat_strength`/`flat_intellect` keys would have gone live and the rest stayed dead, so all of them were mapped with v3.8's own rule (Vitality->Strength, Instinct->Agility, Arcane/Enigma->Intellect). **The palette Slates now grant stats**; e.g. Aetheric Conduit gives +12.5 Intellect.
- Old saves are migrated on load (`ItemSerializer.migrate_stat_key()`/`migrate_stat_text()`, reused by `SlateSerializer`, which also drops "mastery" modifiers). Verified against the real save: 47 items and 4 Slates came through clean.
- Re-runnable tools (`repair_item_requirements`, `generate_weapon_affixes`, the bow/conduit line generators) were updated. `repair_stat_migration.gd`/`repair_implicit_affixes.gd` are already-applied six-stat migrations and now carry a "do not re-run" header; they keep the old names as a historical record.

**Also fixed:** `SlateSerializer.from_dict()`'s empty-shape fallback assigned an untyped `[Vector2i.ZERO]` to a typed array, which throws. It's latent (real saves always have shapes); the test hit it.

**Brief's grep report:** checks 2 and 3 (`.tres` requirement fields and `flat_*` keys) have 0 hits. Check 1 (`.gd`) is 0 in game code. The only remaining hits are intentional: the save-migration maps, the v4.8 repair tool's rename tables, and the two historical tools. `finesse_crit_bonus` keeps its name, per the brief. The verb "resolve" (`_resolve_hit`, `BrandCombinationResolver`, etc.) matches that grep but is unrelated and untouched.

**Balance impact (flagged, not changed):**
- The grade ranges were tuned in v4.6 as a coefficient on a stat value. As a direct multiplier on spell power, they cut most spells hard. The mid-range multipliers are A 0.95 / B 0.63 / C 0.35 / D 0.20 / E 0.10, and 13 of 20 abilities are C or below. For example, a D-grade spell on a 21 SP Conduit with 14 Intellect did 21 + 14 x 0.2 = 23.8 power before and does 21 x 1.14 x 0.2 = 4.8 now (-80%). An A-grade spell goes up slightly.
- Weapons move less, since the grade is gone from the formula. The Crude Greatsword (D grade, 12 base) at 85 Strength goes from 12 + 85 x 0.2 = 29 to 12 x 1.85 = 22.1. B-grade weapons at the same Strength lose about 66%. Mob health from v4.6 was balanced against the old numbers.

**Follow-up retune (user decision), in response to the above:**
- `GRADE_MULTIPLIER_RANGES` is now a pure spell-quality multiplier: S 1.4-1.8, A 1.1-1.4, B 0.85-1.1, C 0.65-0.85, D 0.45-0.65, E 0.25-0.45. Mid-range values are 1.6 / 1.25 / 0.975 / 0.75 / 0.55 / 0.35. The earlier D-grade example becomes 21 x 1.14 x 0.55 = 13.2 (was 23.8 before v4.8, 4.8 right after it).
- `MOB_BASE_HEALTH` x1.5: light 83 (82.5 rounded up), standard 150, heavy 300, elite 750, boss 4500. The mob level curve (growth per level, +2 levels per tier) and tier scaling are unchanged. This also makes enemies tougher against weapons, which lost damage in v4.8 rather than gaining it.

**Not updated:** `README.md` still describes Prowess/Finesse/Resolve and Mastery (24 mentions).

**Verified** (headless, 4.7.1, 24 checks inside `GeneratedMap` with the real save loaded):
- Renamed baseline/enum.
- Save migration.
- Life = base + 4/Str; Mana = base + 3/Int.
- Action speed, Evasion, crit and Ward include the stats.
- Weapon damage matches `base x (1+Str%) x MV x chain` exactly, and changing the grade has no effect.
- A spell with no Conduit does 0; a spell with a Conduit matches `SP x (1+Int%) x grade x MV` exactly.
- Rolled items and Slates only use new keys.
- A placed palette Slate grants Intellect.
- Requirements load and display.
- The weapon card shows "12 → 22.1".
- The character screen shows STRENGTH/AGILITY/INTELLECT with Weapon/Spell Damage rows and no Mastery.
- Hub loads clean.

## 2026-09-24 — Implementation Brief v4.7: Bug Fix Pass

Items 1-10 were done; item 11 was dropped (see below). Where the brief's approach didn't fit the code, the goal was kept and the method adapted.

**Where the brief didn't match the code:**
- **Level stats (1):** +0.6 Prowess/Finesse/Resolve per level above 1, from `GameState.get_level_stat_bonus()` = `(player_level - 1) x 0.6`, and not from saved `base_prowess`-style counters. It's derived, so there's no save field, it can't drift from the level, and existing saves get their bonus right away (level 17 = +9.6). It goes into a new `StatSheet.level_bonus`, which `get_stat()` adds, and not into `stat_sheet.prowess += ...`. That field belongs to the shared `player_baseline.tres`, and `_apply_derived_stats()` runs on every equip, so the brief's version would have stacked the bonus again each time. The character screen already shows `get_stat()`, so its totals include the level bonus with no further change.
- **Aggro (2):** enemies have no state machine and no aggro method, only a distance check in `_update_chase()`. `take_damage()` already marked combat (`_last_combat_msec`) before its dodge roll. The chase gate ignored that, so any hit from outside `chase_range`, landed or dodged, never pulled the enemy. The chase (and model facing) now also runs while `is_in_combat()` (the existing 5 s grace). Side effect: an enemy now keeps chasing for up to 5 s after the player leaves its range.
- **Crafting refresh (3):** the root cause was object identity, not a missing signal. `_apply_saved_loadout()` rebuilt every equipped rolled item from its saved dict (`from_dict`) on each scene load, so after one Hub/Map transition the equipped copy and its `owned_loot` twin were different objects. The Cube crafts the twin and never touched the equipped copy. `_resolve_equipment_ref()` now reuses the matching `owned_loot` instance (both sides compared through `to_dict()`). `item_stats_changed` already existed but had no listener; `craft_cube`, `corrupt`, `infuse` and `shrive` now emit it. If the item is equipped, Player re-runs `_on_equipment_changed()` and re-syncs `equipment_refs`, so the saved snapshot isn't stale either. `is_item_equipped()`/`refresh_item_stats()` don't exist; the existing equip path is reused.
- **Corruption (4):** a CORRUPTED badge sits beside the ITEM badge. The Shard's result message already showed in the Cube's status label. `ItemRoller` rolled Uncommon 0-2 and Rare 0-6 affixes, so a colored item with no mods was possible. The minimum is now 1, and if the eligible pool comes up empty the item falls back to Common.
- **Crosshair (5):** hidden whenever the mouse isn't captured, and not through `ui_opened`/`ui_closed` signals with an open-panel count. All ~10 panels (inventory, character, Fate Board, crafting, abilities, map, shop, pause, death) already release the mouse on open and recapture it on close, so capture state is the shared signal. That needed no per-panel edits and there's no count to desync. `Crosshair` runs with `PROCESS_MODE_ALWAYS` because panels pause the tree.
- **Inventory arrangement (6):** grid keys were `obj:<instance_id>`, which change on every load, so saving them as the brief suggested would never restore anything. Keys are now `item:<item_id>#<n>` (n = occurrence among same-id `owned_loot` entries, which is never reordered) plus the existing `brand:<id>`. `_slot_assignment` is now a property backed by `GameState.inventory_slot_assignment`, which is saved and reset on New Game. Keys for items no longer owned are pruned on each build.
- **Slate tooltips (7):** `FateBoardGrid` draws every cell itself, with no per-cell nodes, so the tooltip uses the grid's own `_get_tooltip()` (returns the hovered `placement_id`) and `_make_custom_tooltip()` (the same ItemCard the palette uses). It's hidden while a Slate is held for placement.
- **Mob counter (8):** `enemy_died` is new and fires from `health.died` directly, so `FigmentBoss` (which awaits its death animation before `super._on_died()`) still counts immediately. `GeneratedMap` tracks what it spawned. The label is top-left under the status chips (top-center is the boss bar, top-right the debug overlay). It shows once `GeneratedMap` reports a count, not when `active_map != null`: a standalone (F6) map has no `active_map` but should still show it, and the Hub never reports.
- **Bow draw (9):** bow base `.tres` files bake `cycle_time = 0` and were off-limits, so `RANGED_PROFILES` alone would have done nothing. The new `Weapon.get_draw_time()` reads the profile (Shortbow/Bow 0.6 s, Longbow 1.0 s) for ARROW weapons only. `PlayerRangedAttack` applies it for SEMI_AUTO, and the item card shows "Draw: Xs".
- **Damage numbers (10):** new `ui/damage_number/`. `take_damage()` gained `is_dot`, passed only by the Ignite tick (the only DoT). Ward-absorbed amounts show at half alpha, slightly higher. Crit is always false for now, as the brief allows. Ground effects (Flame Wall, Caltrops, etc.) are direct hits and do show numbers on each tick.
- **Figments in inventory (11): not changed (user decision).** Figments reach `owned_loot` on purpose (6% enemy drop plus boss drops; the Reality Engine and Cube Empower use them), and players should be able to store and view them in the inventory. They stay in the grid, draggable like any other entry, and clicking one still gives the "used at the Reality Engine" message.

**Verified** (headless, 4.7.1, scene-load test inside `GeneratedMap`, 35 checks):
- Level-up adds exactly +0.6 to each stat and +1.2 max life; the baseline resource is untouched.
- The counter reads 11/11, then 10/11 after a kill.
- An enemy outside chase range stays idle, then chases after a dodged hit.
- A direct hit spawns a number; a DoT tick doesn't; numbers free themselves.
- Adding +7 Prowess to an equipped helm updates stats and `equipment_refs`, and refs resolve to the owned instance both in-session and after a JSON round-trip.
- The badge shows only when the item is corrupted, and 0 of 1657 colored rolls had no mods.
- Draw times are 0.6/1.0/0.6/0; a bow shot starts a 0.6 s draw that then ends; a pistol is unaffected; the card shows "Draw: 1s".
- The Slate tooltip returns the placement id and an ItemCard.
- Keys are stable, and a dragged slot survives a rebuild and a JSON round-trip.
- Hub and GeneratedMap load with no errors.

**Not verified:** the crosshair toggle. Headless mode can't capture the mouse (mouse mode stays VISIBLE), so only the hidden state was seen.

## 2026-09-22 — Implementation Brief v4.6: Damage Scaling Rebalance + Enemy Mitigation

Grade multipliers cut about 2.5x (S 1.2–1.6 … E 0.07–0.12). Greatsword MV 1.35 → 1.1, charged multiplier 1.8 → 1.6, Riposte multiplier 3.0 → 1.4. A Greatsword Riposte at S grade, 60 stat and 140 base now rolls about 552 (it was about 1633). Mob curve: growth 0.12 → 0.15, base health light/standard/heavy/boss 55/100/200/3000 (it was 80/150/280/2000), and Map tier now adds +2 mob levels per tier instead of +1. Enemies now have Ward (`EnemyDefinition.ward_percent` of max health, set at spawn, no regen, rescaled when tier or rarity changes max health), armor, and evasion.

**Where the brief didn't match the code:**
- `mob_level`/`archetype_category`, the `MOB_*` constants and the level helpers already existed from v4.5. The values were updated in place instead of adding duplicates.
- Enemy armor uses a flat `armor / (armor + 1000)` (user decision), not the player's hit-size-dependent `physical_mitigation(armor, hit)`. The brief's call `physical_mitigation(armor_value)` didn't match that function's signature, and at first the player curve was tried: it cut small hits much harder than the brief's 3%/7%/17% targets (a Glass Cannon jab needed about 9.6 hits instead of about 7). The flat curve gives 2.9% / 7.4% / 16.7% for 30 / 80 / 200 armor.
- **Evasion is opt-in (`take_damage(..., can_evade = true)`)** and doesn't key off `not is_spell`. Most ability callers (BlackHole, Caltrops, PiercingBolt, Frost Armor retaliation, etc.) never pass `is_spell`, so following the brief literally would let enemies dodge spells. Only the melee swing (`PlayerMeleeAttack._deal_damage`) and player projectiles pass `true`. Ripostes, Water Slices riders and DoT ticks can't be dodged. `take_damage()` now returns `false` on a dodge, so those two callers skip stance damage, `damage_dealt`, hit markers and hitstop. `DebugOverlay` logs dodges.
- A hit fully absorbed by Ward plays the quieter hit sound and no hit-react.

**Verified** (headless, 4.7.1): health 55/100/260, Ward 0/10/39, dodge 61/17/0 per 1000 (formula 5%/2%/0%). Spells and non-evadable hits were never dodged, Fire ignores armor, and Ward absorbs before health. A tier-3 Soldier (level 7) has 380 HP and 57 Ward. `GeneratedMap.tscn` loads with no errors.

**Known gaps:** there's no enemy Ward UI, so the health bar doesn't show the pool. Armor penetration and Physical Shred (`get_effective_armor()`) aren't applied against enemies because `take_damage()` has no attacker stats. Only Glass Cannon uses a definition, so Shambler and Soldier values are data only (as in v4.5).

## 2026-09-22 — Implementation Brief v4.5: Shop Standalone Fix + Mob Level Scaling

Shop: `GearShop._roll_stock()` now floors its `ItemRoller.roll()` item level at `MIN_SHOP_ITEM_LEVEL` (5) instead of using `GameState.player_level` directly, so a standalone/level-1 session doesn't get an empty pool. `GameState.initialize_standalone()` (called from `GeneratedMap._ready()` for a direct F6 launch) sets `player_level = 5`, `gold = 1000000`; the floor matches that so standalone-shop items are never above what the player can equip. `flat_armor` was rolling onto gear and doing nothing (not in `MISC_BONUS_KEYS`, same bug `flat_evasion` had in v4.4); `EquipmentComponent.get_total_armor()` now sums it the same way.

Mob level: `EnemyDefinition` gained `mob_level`/`archetype_category`; `Enemy._apply_definition()` derives health/damage from `Constants.MOB_BASE_HEALTH`/`MOB_BASE_DAMAGE` by category x `(1 + growth * (level - 1))` instead of the definition's raw `base_health`/`base_damage`. In a Figment, `_apply_map_modifiers()` re-derives health from `definition.mob_level + tier - 1` and applies `enemy_health_multiplier` (a Figment affix roll) on top — `TIER_HEALTH_GROWTH_PER_TIER` was removed (user decision) since the level curve already grows health per tier; keeping both would have double-counted it. Damage/reward have no level-curve counterpart yet, so `TIER_DAMAGE_GROWTH_PER_TIER`/`TIER_REWARD_GROWTH_PER_TIER` are unchanged.

**Known gaps (user-acknowledged, not fixed here):**
- Only `GlassCannon.tscn` actually references an `EnemyDefinition` (`glass_cannon.tres`). `HeavyHitter` and `MobileBruiser` have no definition and keep their own hardcoded health/damage, unaffected by the mob level curve or its tier scaling — pending an `EnemyDefinition` wiring pass for those two archetypes.
- `hollowed_shambler.tres` and `directorate_soldier.tres` (both updated with `mob_level`/`archetype_category`) exist as data but aren't referenced by any scene yet, so nothing in the live game reads them.

## 2026-09-20 — Implementation Brief v4.4: Evasion

Dodge (`evasion / (evasion + 3800)`, cap 65%), Deflection chance (`/ (+ 2333)`, cap 75%) and Deflection mitigation (`/ (+ 13000)`, cap 35%) added to `DamageCalculator` exactly as specified, and rolled at the top of `Player.take_damage()` (after the parry-invulnerability early-out, before the Physical->Elemental shift): Dodge negates an attack hit (and can't interrupt a cast); otherwise Deflection may reduce it.

**Where the brief didn't match the code:**
- `flat_evasion` was NOT "already summed": it wasn't in `MISC_BONUS_KEYS`, so it rolled onto gear and did nothing (v4.0's comment calling it "already real" was wrong; `flat_armor` is in the same state and is untouched here). It's now in the list; `increased_evasion` was listed but unread. `EquipmentComponent.get_total_evasion()` = (sum of `evasion_value` on helmet/body/gloves/boots/shield + flat) x (1 + increased). `EquipmentComponent` has no `stat_sheet`, so it reads its own `compute_misc_bonuses()` instead of the brief's `stat_sheet.get_misc_bonus()`. Finesse's +2/point is added after the gear multiplier (`StatSheet.get_total_evasion(equipment)`), as specified.
- **`source is Ability` can never be true** (`source` is a Node, Ability is a Resource), and `source` can't distinguish a DoT tick from an attack either: ignite ticks call `Player.take_damage(..., _ignite_source)` with the attacking enemy as source, so they'd have been evaded, violating the DO NOT. `take_damage()` now takes a `hit_kind` (`Player.HitKind` ATTACK/SPELL/DOT), default ATTACK so `EnemyMeleeAttack` needed no edit; `StatusEffectComponent`'s Player tick passes DOT, and `Projectile.is_spell_projectile` selects SPELL. **Nothing sets `is_spell_projectile` yet and enemies have no spells**, so the spell branch is correct but not reachable in the live game. Any future caller that doesn't pass a kind is treated as an attack.
- The Evasion display/tooltip lives in `StatSummaryBuilder` (shared with the Inventory stats column), not `CharacterScreen.gd`. It shows the live total and a tooltip with the derived Dodge/Deflection percentages. The brief's item 8 (an "evasion tooltip on the item card") has no counterpart: no such tooltip exists, so nothing further was done.
- `evasion_to_spells` (v4.0, still unwired) is left as is; spells already get the full Deflection roll, so it has nothing to add.

**Known side effects (not changed - `EnemyMeleeAttack` was off-limits):** Frost Armor retaliation and the debug log's "attack landed" line still fire on a melee hit that was Dodged, since `_resolve_hit()` can't see the dodge. Blocks and dodges don't stack in the log.

**Verified** (2000 hits each, 0 / 1900 / 3800 evasion): dodge 0% / 34.3% / 49.9% (formula 33.3% / 50%); spells never dodged, deflected 44.7% / 64.5% (formula 44.9% / 62%); DoT never touched; attack deflection is rolled only on non-dodged hits (30% / 31%); caps 0.65 / 0.75 / 0.35 at 1e9 evasion; gear (100 + 50 flat) x 1.2 = 180.

## 2026-09-20 — Implementation Brief v4.3: Bug Fix Pass

Every file the brief named was read first; where its names or premises didn't match, the behavior was adapted rather than the code copied.

**Block chance / Block Threshold**
- `Shield.block_chance` (a fraction) existed but nothing read it. Block is rolled in the new `Player.try_block_melee_hit()`, called from `EnemyMeleeAttack._resolve_hit()` after the parry check. Not inside `Player.take_damage()`: that function has no `is_spell`/`is_dot` (the brief's signature doesn't exist) and is also the entry for projectiles and DoT ticks, which must not block. Melee is the only path that calls it. A blocked hit deals no damage and skips Frost Armor retaliation, like a parry. Cap 75%; `hit_blocked(defender)` added to `EventBus`.
- `equipment.get_offhand()` doesn't exist; it's `equipment.offhand as Shield`. "of Steadying" (`block_chance_bonus`, whole percent points) routes through the `misc_bonus` mechanism like the v4.0 mods, via `StatSheet.get_block_chance_bonus()`.
- **Block Threshold** existed only in `Shield.gd`, `ItemSerializer`, the shield card, 54 shield `.tres` and the base-type generator. `StatSheet`, `DamageCalculator`, `ItemRoller`, `Constants` and `StatSummaryBuilder` had nothing to remove. 18 shields' flavor text also said "Block Threshold" (reworded to Block Chance). The shield card printed `block_chance` with `%.0f%%` of the raw fraction (0.08 -> "0%"); now x100.
- **"of Warding"** was not on shields: it was a v3.9 `data/affixes/weapons/exclusive/` file that only `Weapon` rolls read, so it never rolled on anything. Replaced by `excl_of_steadying.tres` and a real `AFFIX_POOL` entry (that's the path shields actually roll from). The brief's per-tier table (T1 8-10, T2 6-7, T3 4-5, T4 2-3, gated at ilvl 74/56/38/20) can't be expressed: the project deliberately uses one global 5-tier decay curve and has no per-affix tier tables. It uses T1 8-10 and the standard decay.
- Baseline `block_chance` was set from the brief's item-level table on all 100 shields. **That flattens the doc-sourced per-line values** (Buckler 0.08 ... Pavise 0.33) into 15-28%.

**Throwables:** `EXCLUDED_ITEM_TYPES` applied when `ItemRoller` builds its candidate cache. The brief's `item_type` field doesn't exist; matching is on `base_line_id` ("throwing_knives_line1", "grenade_line1"...). The shop stocks via `ItemRoller.roll()`, so it needed no separate filter. 0 throwables in 6000 rolls; `.tres` files untouched.

**Sockets:** one existing system already capped sockets: `CraftingSystem.SOCKET_CAP_BY_SLOT` (per equip slot, doc Section 15; body armour 6, amulet 1, weapons 6 regardless of hand count, its own comment admitted the gap). Replaced by `Constants.MAX_SOCKETS_BY_CATEGORY` + `ItemRoller.get_socket_category()/get_socket_cap()`, used by the roll, Bore, and Corruption's add-socket outcomes. **The brief's values differ from the Section 15 table** (body armour 6 -> 4, amulet 1 -> 2, ...). It is a ceiling only: each base's own tier-scaled `max_sockets` is kept (low-tier bases still roll fewer sockets), which is why `roll()` clamps `item.max_sockets` rather than rolling from the category table. A two-handed Staff is a conduit, so it takes the conduit cap (3), following the brief's category function. `tools/repair_v43_shields_sockets.gd` capped 216 socket fields across the base files (never raised); `generate_base_types.gd` now applies the cap so regeneration doesn't bring it back.

**Item card:** the "(Tier N)" is baked into `ItemAffix.description` at roll time (`ItemRoller` x2, `CraftingSystem` x2), not built by the card, and `ItemAffix.display_name` is the affix name, not its value line. The main view strips the suffix at display time (so already-saved items are fixed too); Alt Info now lists affixes with tiers. Implicits never show one.

**Fate Board:** a `ScrollContainer` around a fixed-size Control, no camera. Scaling that Control would leave the scroll range wrong (containers size from minimum size, not scale), so zoom resizes the cells (`_cell_px = 20 * zoom`, default 1.5, 0.5-3.0, cursor-anchored). The board opens centred on the anchor cell (`FateBoard.ANCHOR_CELL` 75,75).

**Debug overlay:** `Label` -> scrolling `RichTextLabel` (`add_text`, not `append_text`, because "[CRIT]" would parse as BBCode); oldest lines dropped past 200 instead of clearing everything; names via `get_display_name()`, the player stays "YOU" (the log's existing convention); stance handler removed; blocked hits logged. Wheel scrolling needs the mouse released (Esc), as before.

**Ammo drops (item 8):** already in `Enemy._maybe_drop_loot()` since v4.2 and working, so nothing was added. Measured over 1500 kills: 137 ammo pickups (about 15% of the kills that reach that roll, since tome/brand/consumable/slate/figment rolls come first), all the equipped weapon's type. The existing `_get_preferred_ammo_type()` (which also checks the other weapon set) was kept over the brief's simpler one.

**Cast failure:** `ability_cast_failed` reasons are display strings ("Not enough Mana", "On cooldown"), not the brief's keys, so they're shown as-is. `CastTimeHandler.interrupt()` did not emit it; now emits "Interrupted". A second silent failure found: casting while already winding up spent mana and started the cooldown, then `try_cast()` refused. Now refused up front with "Already casting". The slot flash and reason text are in `AbilityBar` (it owns the slot controls; the brief's `PlayerHUD.ability_slots` doesn't exist).

**Character screen:** `StatSummaryBuilder` (shared with the Inventory stats column) gets four resistance rows via `StatSheet.get_resistance()` (already includes gear and all-elemental; the brief's `*_resistance_bonus` fields don't exist) and the listed tooltips, used verbatim as the brief required. Some describe things the game doesn't do: Evasion has no mitigation formula anywhere in this project, and resistances don't scale Chill/Freeze/Electrocute.

**Also fixed (v4.0 bug):** `retaliate_on_block`'s description has no `%d`; formatting it is a script error that aborted the whole `ItemRoller.roll()` (a shield rolling it produced no item). Found by rolling 6000 items. `ItemRoller.format_desc()` now guards all three formatting sites.

## 2026-09-20 — Implementation Brief v4.2: Ranged Ammo, Magazines, Fire Modes, SFX

**Brief assumptions that didn't match the project:**
- **Save/load lives in `SaveManager`** (JSON), not `GameState`. Ammo reserves are saved there; JSON stringifies the enum keys, so `AmmoInventory.deserialize()` converts them back and keeps starting amounts for any type an older save lacks. `GameState.reset_to_defaults()` (New Game) resets ammo.
- **Rolled weapons are rebuilt field by field** by `ItemSerializer`, so the new fields would have been lost on every save/load (a rolled shotgun coming back as a default semi-auto pistol). Added them to the serializer, plus a fallback for saves that predate them: the brief's table now lives in `Weapon.RANGED_PROFILES` and `apply_ranged_profile()` fills the fields from `weapon_type`. `tools/apply_ranged_weapon_stats.gd` reads the same table.
- **No weapon-equipped hook and no reload key existed.** The brief's `_on_weapon_equipped` (refill the magazine on equip) would have been a free refill by swapping weapon sets, and contradicts its own "no auto-reload on swap". The loaded count is `Weapon.current_magazine` (runtime only; -1 reads as full, so a fresh weapon starts loaded), swapping cancels a reload in progress and touches nothing else. Reload is a new `reload` input on R; R is also `fate_board_rotate`, which is safe because that editor pauses the tree.
- **The brief's `_fire_one` consumed reserve ammo per shot AND reload consumed it again**, and its own DO NOT says not to gate fire on reserve. Firing spends only the magazine; reloading pulls from the reserve.
- **Autoload scripts can't share a `class_name` with their singleton** (`AmmoInventory`, `AudioManager`, `SoundLib` have none). Bows have `magazine_size = 0`, which the brief's code would have treated as permanently empty; they're special-cased.
- **The brief's weapon keys (`service_pistol`...) map to the real `weapon_type` strings** ("Service Pistol"...). 236 files updated (all ranged weapons); the one legacy `worn_bow` ("Bow") isn't in the table and takes the Shortbow row.
- `player.equipment.get_weapon_set_b_primary()` doesn't exist; the other set is `primary_weapons[1 - active_weapon_set]`. Bows-only loadouts drop no ammo; a bow in one set and a firearm in the other drops the firearm's type.
- Ammo pickups are a new `AmmoPack` item; `LootPickup` adds them straight to `AmmoInventory` instead of the inventory. The 15% ammo roll sits just before the gear roll, so no earlier drop's odds changed.

**Behavior:** pump shotgun reloads one shell per `cycle_time` and firing mid-reload stops it (needs a loaded shell); full auto fires from a held-input path; bolt/lever/revolver/crossbow/pump block on `cycle_time`; a full magazine won't reload; empty with no reserve plays the dry click and never the fire sound. Spread is sampled inside an ellipse (full width sideways, half up/down), so no pellet exceeds the stated half-angle; aiming halves it. Damage of one shot is split across pellets, each rolling its own crit.

**Sound:** `AudioManager` (8-player pool), `SoundLib`, `SoundLibrary` resource (all slots empty - the game is silent until `data/sound/sound_library.tres` is populated). Wired: fire, dry click, reload/cycle/shell insert, projectile impact (flesh for Enemy/Player, else stone; join group `surface_metal`/`surface_wood` to change), melee swing (Whip added to blade; Gauntlet to blunt; Shock Lance to pierce - the brief's lists missed them), enemy hit and death.

**Verified** with a scratch scene (deleted): magazine/reserve accounting, auto-reload, partial reload, dry fire, 10-pellet pump with shell-by-shell reload and interrupt, ~10 shots/s SMG, bolt cycle, bow (infinite, no magazine), swap cancelling a reload, ammo JSON round trip, serializer round trip and old-save fallback, smart drop type, pickup, HUD text, spread cone (max 12.0 deg of 16, aimed 7.2 of 8). Not verified: anything by ear or by eye - no audio exists, and the HUD layout and fire animations at full-auto rate haven't been looked at in a window.

## 2026-09-20 — Implementation Brief v4.1: Enemy Animation Pipeline

**Brief assumptions that didn't match the project:**
- **Arator's "broken textures / wrong animation"** was already solved in code: `FigmentBoss.gd` builds ORM materials per geoset and drives idle/walk/attack/death from real combat state. Rendered in a window to confirm both. Not done: material extraction and an import post-script (the script's `scale = 0.01` would have double-shrunk him, since the exporter already bakes 0.02). The one real problem was orientation, and it wasn't an import issue - **no enemy in the project ever turned toward the player**.
- **UAL clip names** in the brief (`Punching`, `HitReact`, `Stagger`, `Dying`, `Run`) don't exist. Real UAL1 names: `Idle`, `Walk`, `Jog_Fwd`, `Punch_Jab`, `Punch_Cross`, `Hit_Chest`, `Hit_Head`, `Death01`, `Spell_Simple_Shoot`. UAL has no dedicated stagger clip (UAL2 has `Hit_Knockback`); `Hit_Head` stands in. Clips must be read with the 4.7.1 binary - 4.5.1 imports 0 animations from these files.
- Godot's state machine has no "Any" state and transitions can't read a float `speed`, so `HumanoidAnimTree.tscn` (generated by `tools/generate_humanoid_anim_tree.gd`) has one condition-gated transition per source state, and `EnemyAnimationController.set_speed()` converts speed to `moving/stopped/running/walking` booleans. The tree's state machine resource is shared between scene instances, so the controller duplicates it per enemy.

**Added:** `AnimationSet`, `EnemyDefinition`, `EnemyAnimationController`, `HumanoidAnimTree.tscn`, `UALHumanoidModel.tscn`, three definitions (`glass_cannon`, `hollowed_shambler`, `directorate_soldier`), two animation sets (`ual_humanoid`, `ual_humanoid_ranged`). `Enemy.gd` gained `_apply_definition()`, `_apply_model()`, model turning toward the player (`model_forward_yaw_offset`: 0 for glTF/UAL +Z models, -PI/2 for Arator, whose front is his local +X. My first pass judged this from renders and used PI, which was wrong; the nose-bone direction measured against the direction to the player in a running scene is within 1-4 degrees at -PI/2), hit-react (throttled to 600ms), stagger on composure break, attack clip at telegraph start, and a death clip with a 1.5s linger (corpse leaves the `enemy` group and drops collision immediately). GlassCannon is fully definition-driven and uses `ual_humanoid_ranged` (a ranged enemy punching looked wrong).

**Camera/HUD:** `CameraSway` (roll/pitch lag + walking bob) on the player camera; bob uses `v_offset`/`h_offset` rather than `position` because `PlayerMeleeAttack`'s hit-shake tweens `position` from a captured start value and would fight a per-frame write. Vignette in `PlayerHUD`: off at full health in normal play (brief's DO NOT, which contradicts its own "normal = 0.3" line - flip `VIGNETTE_NORMAL_INTENSITY` to change), 0.35 in a Figment, ramps to 0.6 and red below 30% life, 0.5 flash on damage.

**Not wired:** definition fields `armor_value`/`evasion_value` (enemies have no mitigation model), spawn fields and rarity weights (no spawner reads them; `EnemyRarityComponent` rolls its own), the two faction definitions have no model yet.

## 2026-09-07 — Implementation Brief v4.0: Full Mod Pool Framework

Extracted the real Patch v4.0 doc (`documents/Project_Aether_Patch_v4_0.docx`)
rather than trust the brief's paraphrase - it changed the scope
significantly. Researched every guessed file/method name via a background
agent before touching anything (several were wrong, consistent with this
whole session's pattern): `WardComponent` has no `Constants.WARD_REGEN_
DELAY` or `_get_effective_delay()` and no link to a StatSheet at all;
`Ability.gd` has no `is_spell` field; `Player.take_damage()`'s third arg
is `source: Node`, not `is_spell`; `HealthComponent` has no `take_damage()`
(real name `apply_damage()`); `Weapon.gd` has no `secondary_scaling_grade`.
`ParryRiposteHandler.gd` was the one file name the brief got exactly right.

**Priority 6 (Alt Info restore) needed nothing** - it was never removed.
Confirmed by reading `ItemCard._input()`/`_render_alt_info()` directly:
hold-to-show, release-to-hide, inline content swap, no second card,
exactly as the brief itself describes as the desired end state. Skipped
entirely rather than touch already-correct code.

**Priority 1 - Ward Delay.** `WardComponent.REGEN_DELAY_SECONDS` (2.0) ->
`BASE_REGEN_DELAY_SECONDS` (4.0) + `REGEN_DELAY_FLOOR_SECONDS` (2.0),
`regen_delay_reduction` pushed in by `Player._apply_derived_stats()` the
same way `restoration_multiplier` already is (WardComponent has no
StatSheet reference of its own to read directly). Verified: 0 reduction
-> 4.0s, 1.0 reduction -> 3.0s, 10.0 reduction -> clamps to the 2.0s floor.

**Priorities 2/3 - ~50 new stat_keys, architectural deviation from the
brief's own literal ask.** Did NOT add ~50 individual `var` fields to
StatSheet.gd. Routed almost everything through `misc_bonus` instead - the
SAME existing Dictionary mechanism this project already uses for exactly
this shape of stat (`max_life`/`attack_speed`/`crit_damage`/etc.), extended
via `EquipmentComponent.MISC_BONUS_KEYS`. Several of the brief's own
listed stat_keys (`attack_speed`, `cast_speed`, `cooldown_recovery_rate`,
`flat_armor`, `flat_evasion`, `flat_ward`) turned out to be ALREADY real
and working under those exact names - adding parallel dedicated fields
for those would have silently double-counted them or forked into two
divergent code paths for the same effect. Added thin getter methods to
StatSheet.gd (`get_penetration()`, `get_physical_shred()`, `get_phys_
damage_shift()`, `get_skill_level_bonus()`, `get_ailment_*_bonus()`, etc.)
only where real combination logic was needed, matching the file's own
existing `get_crit_damage_bonus()` precedent.

**v3.9/v4.0 stat_key overlaps, resolved per "v4.0 supersedes on
conflict."** The doc's own "Physical Hit Build Mod Pool" restates 3 of
Patch v3.9's already-generated weapon affixes under new canonical names
with the same T1 values (`kinetic_impacting`/`piercing_lancing`/
`explosive_detonating` -> `increased_kinetic_damage`/`increased_piercing_
damage`/`increased_explosive_damage`) - renamed those 3 `.tres` files'
`stat_key`/`affix_id` rather than creating duplicates. Removed the old
v3.8-era generic `physical_dmg_increased` AFFIX_POOL entry (superseded by
the new doc-exact `increased_physical_damage`, 28-34% vs its own invented
16-20%). The 4 resistance affixes got a SECOND, "_pct"-less naming
(`fire_resistance` alongside `fire_resistance_pct`) - both now map into
the same `EquipmentComponent.RESISTANCE_AFFIX_KEYS` bucket rather than
migrating the 4 named rings' hand-authored implicits to the new name (a
real, unnecessary risk for zero benefit - both spellings already work).
New `all_elemental_resistance` (Fire/Cold/Lightning only, not Esoteric)
adds to all three buckets at once. `crit_damage_increased` (v4.0) and
the pre-existing `crit_damage` (v3.8c) both feed `get_crit_damage_bonus()`
now, treated as synonyms.

**Wired into real game systems** (verified via scratch tests, not just
code reading): Penetration/Physical Shred as real `DamageCalculator.
get_effective_resistance()`/`get_effective_armor()` functions (see gap
below for why they're not live-called yet); Player's own damage intake
(`take_damage()`) now handles % Physical damage taken as Elemental
(splits one hit into several typed sub-hits before mitigation), % Damage
from Mana before Life, reduced-damage-taken per category, and % of Armor
applying to Elemental hits; Ward on Parry and Increased Parry Window
Duration in `ParryRiposteHandler.gd` (window duration compounds with the
existing stance-based multiplier); Increased/Critical-Chance Riposte via
a temporary `finesse_crit_bonus` bump around one `roll_damage()` call
(no signature change needed anywhere); Skill Level scaling in `Ability.
_base_hit()` as a final-damage multiplier (8%/level, invented per the
brief's own "subject to balance tuning") rather than touching
`DamageCalculator.calculate()`'s signature; DoT Multiplier + Faster
Ailment Tick Rate in `StatusEffectComponent._apply_ignite()`, reading the
CASTER's StatSheet (not the DoT-carrier's - Enemies have no StatSheet to
read regardless), preserving total DoT damage while shortening the
interval per the doc; Increased Retaliation Damage in the one real
retaliation trigger that exists (`trigger_frost_armor_retaliation()`).

**Affix pool**: ~90 new AFFIX_POOL entries covering every remaining v4.0
mod pool (Ailment/Physical Hit/Spell Hit/Ranged/Parry/Healing/Offensive/
Retaliation/Defensive/Armor Base/Amulet Exclusive), doc-exact T1 values,
`_pool_for()` extended with new optional `slots` (Constants.EquipmentSlot
array) and `weapon_kind` ("melee"/"ranged"/"conduit", via `Weapon.
is_ranged`/`is_conduit`) filters - the granular slot-eligibility gating
`_pool_for()` never had before this patch.

**Real, honest gaps left open rather than forced or silently dropped**:
- **Penetration/Physical Shred have no live caller.** Enemy.gd has NO
  Armor or Resistance value anywhere in this project (only Resistance
  SHRED, a bonus damage-taken multiplier, not a mitigatable base value) -
  and Enemy files are explicitly on this same patch's own "Files to Leave
  Alone" list. The functions are real and tested; wiring them in requires
  giving enemies a real Armor/Resistance stat first, a bigger change than
  this patch's stated scope.
- **`evasion_to_spells` is inert.** This project's Evasion has no
  mitigation formula anywhere yet (a pre-existing, long-flagged gap) -
  there's nothing for this mod to redirect a percentage FROM.
- **Ailment application is still unconditional**, not chance-based.
  Every `applies_status_effects` hit in this project already applies
  100% of the time - `ailment_chance_[type]`/`ailment_ignore_chance` are
  real, queryable data, but the doc's own "Design Principles" describes a
  genuinely different application model (crits auto-apply, non-crits need
  invested chance) that would change how EVERY existing ability with
  `applies_status_effects` behaves - a real redesign, not a stat-wiring
  task, left for a dedicated pass.
- **`retaliate_on_block` has no consumer.** No general "passive block
  triggers a counterattack" mechanic exists to hook a binary mod into -
  the only retaliation trigger in this project is Frost Armor's own
  spell-bound one, which doesn't involve blocking at all.
- **New general-pool weapon mods (ailment/physical-hit/parry/etc.) are
  reachable via Cube crafting but not initial loot rolls.** `ItemRoller.
  roll()` still routes ALL weapon rolls through the Patch v3.9 damage-
  type-specific `.tres` library exclusively (`_roll_weapon_affixes()`),
  never the general `AFFIX_POOL` these new entries live in - only Cube
  crafting's `_pool_for_brand_tag()` path reaches them for weapons.
  Integrating the two weapon-affix sources at initial-roll time is a real
  follow-up, not attempted here given the added complexity to the
  existing prefix/suffix-cap logic.

Verified via 3 separate scratch tests (Ward delay/floor, misc_bonus
routing for a representative sample of new keys, penetration/shred
functions, resistance key unification, Ignite DoT-multiplier/tick-rate
math) plus headless loads of MainMenu/Hub/GeneratedMap - all clean.

## 2026-09-07 — Bug Fix: Finesse Crit Chance Should Be Multiplicative, Not Flat Additive

User-reported: Finesse's "+1% increased Critical Strike Chance per point"
was being applied as flat additive percentage points instead. The
addition itself doesn't happen where the user pointed - `StatSheet.
get_crit_chance_from_stats()` never took `base_crit_chance` as an input
at all, it only ever returned the raw Finesse fraction (`Finesse * 0.01`).
The actual `base + bonus` combination lives in `DamageCalculator.
get_crit_chance(base_crit_chance, finesse_crit_bonus)`, so that's where
the fix went: `base_crit_chance * (1.0 + finesse_crit_bonus)` instead of
`base_crit_chance + finesse_crit_bonus`. `finesse_crit_bonus` itself is
unchanged (still `Finesse * 0.01`, still pushed once per equipment change
via `Player._apply_derived_stats()`) - only how it combines with a
weapon/ability's own base crit chance changed. Verified with a scratch
test: 5% base + 7 Finesse now yields 5.35% (`0.05 * 1.07`), not the old
12% (`0.05 + 0.07`).

## 2026-09-07 — Bug Fixes: Duplicate Affix stat_keys, Unformatted Affix Descriptions

Two user-reported bugs from screenshots, both traced to real code before
fixing.

**Duplicate stat_keys.** Not actually in `ItemRoller.roll()` (verified via
its own earlier scratch test - already correct by construction, pool
entries are taken from a shuffled array without replacement, can't repeat
within one call). The real bug was in `CraftingSystem._random_affix_for()`
(used by both a single Cube add, `_add_weighted_affix()`, and a full
reroll, `_render()`) - it picked `pool[randi() % pool.size()]` with zero
awareness of what was already on the item, so casting the same category
Brand repeatedly (or a `_render()` reroll landing on the same stat_key
twice across different slots) could put e.g. three separate "+Prowess"
affixes on one item, exactly as the reported screenshots showed. Fixed by
adding an `exclude_keys` param that filters the pool before picking;
`_add_weighted_affix()` passes every `stat_key` already on the item,
`_render()` accumulates keys as it rebuilds the affix list slot by slot.
Verified with a scratch test: 40 repeated Cube crafts against the same
weapon with the same Brand produced exactly 2 affixes (the only 2
eligible for that category) and stopped cleanly instead of duplicating.

**Unformatted affix descriptions.** The Patch v3.9 weapon affix `.tres`
files' `description` field (`tools/generate_weapon_affixes.gd`) was
plain descriptive text with no value placeholder at all (e.g. "% increased
Kinetic damage") - `ItemRoller._roll_weapon_affixes()` then appended
"(Tier N)" onto that verbatim, so the card only ever showed the tier
label with no actual rolled number, exactly as reported. The OLD
`AFFIX_POOL` system never had this bug - its own `desc` entries always
carried a real `%d`/`%s` placeholder, substituted via `entry["desc"] %
round(value)` before the tier suffix is appended; the new weapon pool's
generator just never gave its descriptions the same placeholder. Fixed
both sides: regenerated all 96 `.tres` files with a real `%d%%`/`+%d`/
`%.1f%%` placeholder per affix (matching each one's actual doc-given
unit - flat stat/resource affixes get `+%d`, percentages get `%d%%`, the
2 Critical Strike Chance affixes keep the doc's own decimal precision via
`%.1f%%`), and `_roll_weapon_affixes()` now substitutes the rolled value
before appending the tier suffix, identical to the old system's own
pattern. Verified with a scratch test: sampled rolled descriptions now
read "28% increased Spell damage (Tier 2)" etc., not "(Tier 2)" alone.

## 2026-09-06 — Implementation Brief v3.9: Crafting Rarity, Weapon Affix Library, Enemy Rarity System

Extracted the real Patch v3.9 design doc (`documents/Project_Aether_Patch_v3_9.docx`) rather than trusting the brief's own paraphrase, since two things in it turned out incomplete or in conflict with the live codebase - flagged both to the user via AskUserQuestion before writing any code, per this session's standing rule.

**Priority 1 - Crafting Rarity Update.** `CraftingSystem._update_item_rarity(item)` (the brief's own file guess, `CraftingCube.gd`, doesn't exist - `CraftingSystem.gd` is the real one) recomputes rarity from `get_prefix_count() + get_suffix_count()` after every successful `craft_cube()` call (one funnel point covers every add/remove/reroll operation - `_add_weighted_affix()`/`_render()`/`_rectify()`/`_excise()`/`_cleave()`/`_sever()` all dispatch through it) - 0 affixes -> Common, 1-2 -> Uncommon, 3+ -> Rare, matching both the brief's own snippet and the doc's exact table. Unique/Mythic/`is_corrupted` items are never reclassified. New `EventBus.item_rarity_changed(item)` fires only when the rarity actually changes; `ItemCard.display_item()` now connects to it and re-renders (skipped while Alt Info is showing) so a card left open through a craft stays visually current instead of only updating on the next hover. Verified with a scratch test: 3 affixes added directly -> Common to Rare, signal fires with the new value.

**Priority 2 - Weapon Affix Library, 96 new `.tres` files.** The doc gives every affix's Tier-1 value range and Tier-1 item level, but never T2 and up for any of them - asked the user how to handle that gap rather than fabricating a table under "do not invent values." Per their direction: `data/affixes/weapons/<type>/*.tres` (9 damage types + generic + base-type-exclusive, `tools/generate_weapon_affixes.gd`, one-shot generator matching this project's established pattern for bulk `.tres` content) store ONLY the doc's real Tier-1 `value_min`/`value_max`/`min_item_level` - `ItemRoller`'s existing `TIER_DECAY`/`_tier_range()` scaling (the same mechanism every pre-existing `AFFIX_POOL` entry already relies on for exactly this "doc gives Tier 1 only" situation) derives weaker rolls at lower item levels, no invented numbers stored anywhere. `ItemAffix` gained `weapon_type_filter: Array[String]` (empty = universal). `ItemRoller.roll()` now branches: Weapons pull from this new pool (generic + damage-type-matching + base-type-exclusive, split into real prefix/suffix pools capped at 3 each, no duplicate `stat_key`s, gated by `min_item_level <= power_level`); every other item category keeps using the untouched original `AFFIX_POOL` path. Two corrections to the brief's own reading of the doc: "Conduit Only"/"Ranged Only" exclusives aren't tied to a fixed base-type list the way Rapier/Saber etc. are, so their `weapon_type_filter` uses the real conduit/ranged type keys already established in `tools/repair_item_requirements.gd`'s `WEAPON_STAT_MAP`. Verified with a scratch test across 400 rolls: 65 Rare weapons, 191 affixes total, zero duplicate keys, zero prefix/suffix-cap violations, correct tier-decay scaling on sampled values.

**Priority 3 - Enemy Rarity System, built alongside the existing `EnemyRank`, per user direction.** The brief's `EnemyRarity { NORMAL, ELITE, CHAMPION, ASCENDANT }` looked, at first read, like it might duplicate `Constants.EnemyRank { NORMAL, MAGIC, RARE, BOSS }` (already real, already spawn-weighted, already driving loot item-level) - asked the user rather than guessing whether to merge or separate them. Per their answer: `EnemyRank` is completely untouched (still drives loot item-level exactly as before); the new `EnemyRarity` is an independent second axis added via `EnemyRarityComponent` (`entities/components/`) and `EnemyAffix` (`data/enemies/`) - an enemy can be e.g. both `EnemyRank.MAGIC` and `EnemyRarity.ELITE` at once, the two never interact.
- **Stat scaling deliberately isn't in `EnemyRarityComponent._ready()`** the way the brief's own snippet does it - this project has a well-documented recurring bug where a CHILD node's `_ready()` runs before its PARENT's, and `Enemy.gd` already works around it for its own map-tier health scaling via a `call_deferred("_apply_map_modifiers")` specifically "so archetype subclasses' own health.max_health isn't overwritten." The component instead exposes pure query methods (`get_health_multiplier()`/`get_damage_multiplier()`); `Enemy._apply_map_modifiers()`/`get_outgoing_damage_multiplier()` call them at the already-correct, already-deferred time, and no longer early-return when there's no active Map (rarity scaling should still apply in the Hub). Values: Elite 1.5x/1.2x, Champion 3.0x/1.6x, Ascendant 8.0x/2.4x health/damage - invented (the doc names no numbers, Section 24-style deferred balance, same footing as every other invented growth curve already in this file).
- **A second, real timing bug caught by actually running it, not just reasoning about it**: the aura placeholder's `get_parent().add_child(light)`, called from `EnemyRarityComponent._ready()` while its parent Enemy was still mid-`add_child()` in `GeneratedMap._spawn_enemy_at()`, threw "Parent node is busy setting up children" on every single spawn in a real headless run of `GeneratedMap.tscn`. Fixed with `add_child.call_deferred(light)`.
- Spawn weights (`Constants.ENEMY_RARITY_SPAWN_WEIGHTS`, 75/20/4/1) live in `Constants.gd` as the brief's own "read from config, not hardcoded" ask - same role `ENEMY_RANK_SPAWN_WEIGHTS` already plays for the other axis. `GeneratedMap._spawn_enemy_at()` calls `EnemyRarityComponent.roll_and_attach(enemy)` before `add_child(enemy)`.
- 4 starter `EnemyAffix` .tres seeded exactly as specified: `dreamer` (Champion, Entropic damage + Figment drop conversion), `pack_aggressive` (Elite/Pack), `champion_aura_damage` (Champion), `ascendant_resilient` (Ascendant). Champion/Ascendant roll 1-2 from their own pool, Elite rolls 1 from the Pack pool, Normal rolls none - verified over 120 real spawns (weights 75/20/4/1): all 4 tiers observed, health/damage multipliers and name colors matched Constants exactly for every tier.
- Name color wired into the REAL enemy nameplate system, `ui/player_hud/EnemyHealthBar.gd`/`PlayerHUD.gd` (no `HealthBarUI` node exists on Enemy itself - health bars are pooled, PlayerHUD-owned Controls positioned every frame, not per-enemy children, per that file's own header). New `EnemyHealthBar.set_name_color()`; `PlayerHUD._update_enemy_health_bars()` reads the enemy's `EnemyRarityComponent` (if any) and applies it.
- Drop conversion is a real, wired stub, not fully implemented, per the brief's own DO NOT: `Enemy._maybe_drop_loot()` checks for a `converts_drops` affix first and short-circuits the entire normal cascade (all-or-nothing, matching the doc) into `_drop_converted()`, which for `"figments"` reuses the existing, already-working `FigmentRoller.roll_for_drop()` rather than half-building a second Figment-rolling path - Item Rarity/Quantity bonus is real, aggregated data (`EnemyRarityComponent.get_effective_rarity_bonus()/get_effective_quantity_bonus()`) but not yet fed into that roll.
- **Left as a known gap, not implemented this pass**: the doc's "Ascendant... Boss-style health bar with damage trail" - Ascendant enemies still get the regular floating `EnemyHealthBar` (now correctly colored orange), not `BossHealthBar`. The existing boss-bar is a `EnemyRank.BOSS`-gated singleton (one at a time, top-of-screen); routing Ascendant-rarity-but-not-Boss-rank enemies through the same slot raises a real question (what happens if both are in combat at once) the doc/brief don't resolve, so it was left alone rather than rushed.
- Champion aura mechanics and drop-conversion tier/count scaling remain visual-placeholder/stub only, per the brief's own explicit DO NOT list.

## 2026-09-06 — Bug Fix: Weapons Silently Destroyed on Every Save

User-reported: "Inventory is not persisting between saves — items are
being lost on save/load." Diagnosed with real logging first, not a guess
- added `[SAVE]`/`[LOAD]`/`[APPLY]` instrumentation to `SaveManager.
save_game()`/`load_game()` and `InventoryScreen._build_stack_entries()`,
then reproduced with a real `ItemRoller`-rolled weapon + a ring in
`GameState.owned_loot` through an actual `save_game()` -> `load_game()`
round trip.

**Root cause, found from the logs, not guessed**: `data/items/item_
serializer.gd:54` (`to_dict()`) read `item.base_damage` on a `Weapon` -
a field that hasn't existed since `Weapon.gd` split it into `base_damage_
min`/`base_damage_max`/`rolled_base_damage` (`get_base_damage()` as the
accessor) in an earlier patch; `item_serializer.gd` was never updated to
match. The property access throws a runtime error that ABORTS the rest
of `to_dict()` and returns `{}` (Dictionary's default) instead of the
dict built so far - confirmed directly in the logs: `[SAVE]` still
reported "2 dicts serialized" (the empty dict still got appended), and
the saved JSON held a literal `{}` in the weapon's slot. On load, `from_
dict({})` hits its own `if d.is_empty(): return null` guard immediately,
and the null gets filtered out before reconstruction - the weapon is
gone. Same stale field on the read side too (`item.base_damage = d.get
(...)`), though in practice it's never reached since `to_dict()` never
produces real weapon data to begin with.

**Scope**: every Weapon in `owned_loot` on every save, 100% reproducible,
not intermittent. Every other item type (Armor/Shield/Brand/FigmentItem/
plain Item) round-trips fine - they never touch this code path. This is
likely also why armor/shield-only inventories "worked" while anyone
carrying a spare weapon in their bag would silently lose it.

**Fix**: `to_dict()` now writes `base_damage_min`/`base_damage_max`/
`rolled_base_damage`; `from_dict()` restores all three (`get_base_
damage()` already exists as the accessor everywhere downstream needs the
effective value - no new field needed). Verified with a second real
round trip: a rolled weapon's `base_damage_min`/`max`/`rolled_base_
damage`/`get_base_damage()` all match exactly before and after. Removed
the diagnostic logging once the round trip passed clean, per the user's
own "keep it until it passes" instruction.

## 2026-09-06 — Implementation Brief v3.8d: Requirements Display, Damage Label, Card Null Fix

**Priority 1 - `_stat_sheet_for_card()` null fix, root cause narrower than
reported.** Not really "player node not in the scene tree (shop, menu
contexts)" - `ItemSlotButton._make_custom_tooltip()` calls `display_item()`
on a freshly-`instantiate()`'d `ItemCard` BEFORE returning it, i.e. before
Godot's tooltip system ever adds the card to the SceneTree - so
`get_tree()` itself is null at that exact moment for EVERY hover, not
just ones with no Player. The brief's own proposed fix (`get_tree().
get_first_node_in_group("player")`, then check if `player` is null) still
crashes on that unconditional `get_tree()` call before ever reaching its
own null check - confirmed by reproducing the exact crash in a scratch
test. Fixed by checking `get_tree()` itself first, then falling back to
`GameState.player_stat_sheet` (the same instance `Player.gd` assigns
itself to at boot) exactly as the brief intended. Verified: a Worn Rapier
against a fresh 4-Prowess baseline now correctly shows a 3.6 stat
contribution with zero Player node anywhere in the tree.

**Priorities 2/3 - Level & Stat Requirements, added alongside (not
replacing) the existing system.** `Item.gd` already had a REAL, ENFORCED
requirement gate (`stat_requirement`/`stat_requirement_value`, one stat
only, checked by `EquipmentComponent._requirement_block_reason()` on
every `equip()`) using `item_level` itself as the level gate at full 1:1
scaling - not missing, as the brief assumed. What that system genuinely
can't do is gate on TWO stats at once (several weapon types here need a
primary + secondary), which the brief's 3 separate `prowess_requirement`/
`finesse_requirement`/`resolve_requirement` int fields do support. Added
those plus `level_requirement` to `Item.gd`, explicitly marked display-
only and left the old fields and `_requirement_block_reason()` completely
untouched, per the brief's own "enforcement is a separate pass" DO NOT.
**Flagging for the user**: the new `level_requirement` table is
deliberately more lenient than raw `item_level` (e.g. item_level 84 ->
`level_requirement` 80, but the ACTIVE gate still checks the real
`item_level` of 84) - until a future pass repoints enforcement at the new
fields, the card's displayed requirement and the actual equip-block will
disagree for roughly 750 of the ~1000 generated items (every one with
`item_level > 10`). This mismatch is an inherent, known consequence of a
deliberate two-pass rollout the brief itself describes, not a bug in this
pass - flagging the size of it since it's larger than "temporary rough
edge" might suggest.

New `tools/repair_item_requirements.gd` (GDScript + `ResourceSaver`, same
pattern as every other `repair_*.gd` here - not the brief's own "Python,
batch approach" snippet, which has no way to read/write a `.tres`
Resource at all) populated all 1004 items: 751 weapons/shields got real
stat requirements (0 unmapped - every real weapon/shield type resolved),
253 armor/accessories got `level_requirement` only. Two corrections to
the brief's own `WEAPON_STAT_MAP`: **(1)** "gauntlet" - Worn Gauntlet's
own weapon type - is missing from every one of the brief's lists
entirely; mapped to single Resolve, matching its established v3.8
identity as this project's first conduit-flavored weapon (Aetheric
damage, `flat_resolve` implicit), consistent with every other main-hand
conduit (wand/staff/athame/spell_gauntlet) already being single-Resolve.
**(2)** the brief's prose calls out "battle_rifle (high damage line)" and
"crossbow (bleed line)" as Prowess+Finesse dual-stat, contradicting its
own single-Prowess/single-Finesse entries for those same two ids in its
own executable `WEAPON_STAT_MAP` - no per-line table exists to actually
tell which specific lines would differ (unlike `repair_weapon_lines.gd`'s
real per-line table), so the repair script follows the brief's own
literal, executable dict: both stay single-stat across every line.

**Priority 4 - weapon card label.** "X Attack Power" -> "X Damage" in
both `_build_attack_power_lines()` label lines (the primary line and the
scaffolding-only "gain_as_damage" conversion line).

**Priority 5 - requirement display.** Alt Info panel now shows "Requires
Level N" / "Requires A Prowess / B Finesse / ..." (only non-zero stats
listed) for both Weapon and generic Item, replacing the old single-stat
"Requires: N StatName" line that read off the OLD `stat_requirement`
field (kept `Item Level: N` as-is - distinct concept, tier/roll context,
not the same number as the new `level_requirement`). Main card shows the
same two lines in red at the bottom, AND tints the border/badge/title
red, but only when `_check_requirements_met()` returns false - nothing
shown at all when requirements are met. That check reads `GameState.
player_level` (kept live-synced by `Player._on_leveled_up()`, so this
still gives a real answer in the same shop/menu contexts Priority 1's fix
targets) and the same `_stat_sheet_for_card()` used everywhere else on
this card, rather than requiring a live `Player` reference the way the
brief's own snippet did.

## 2026-09-06 — Bug Fix: Item Card's Attack Power Bonus Missing Mastery

User-reported: "the blue number on the item card isn't being properly
updated with how much damage you get from your Attack Power." `ItemCard.
_get_stat_contribution()` (the blue bonus number next to a weapon's
Attack Power line) computed `stat_ap * grade_mult` only - `Weapon.
_base_hit()`'s real formula (`DamageCalculator.calculate()`) applies
Mastery on top: `effective_grade_multiplier = grade_multiplier * (1.0 +
mastery_bonus)`. The card's number was correct at zero Mastery for the
weapon's damage type, but understated the real contribution - and never
moved - once Fate Board Slates gave that tag any Mastery. Fixed by
resolving the weapon's effective damage type (infused if set, else
native, same as `_base_hit()`) and folding `stat_sheet.get_mastery()`
into the multiplier the same way. Verified with a scratch test: a
weapon with 0.5 Mastery on its damage type now shows the same number the
real formula independently computes (13.5, not the pre-fix 9.0).

## 2026-09-06 — Implementation Brief v3.8c: Crit Damage Fix, Starting Gold, Brand Shop

Third stat-system bug report in a row - researched against the real code
first, as always. Almost the entire "Constants.gd stat system fix"
priority turned out to already be correct (done in v3.8, verified again
in v3.8b): the enum, `STAT_NAME`/`STAT_GLOSSARY`/`DAMAGE_TYPE_MAIN_STAT`,
`get_attack_power_from_stats()`/`get_spell_power_from_stats()`/`get_crit_
chance_from_stats()`, `Weapon`/`Ability._base_hit()`, `Player._apply_
derived_stats()`, and `player_baseline.tres` all already matched the
brief's own proposed code byte-for-byte in most cases. A repo-wide grep
for every old `Stat.*` enum reference found zero live hits - two comment-
only mentions in one-shot, already-run generator scripts (`generate_bow_
lines.gd`, `generate_conduit_lines.gd`) were renamed for cleanliness, no
behavior change.

**The one real bug**: gear's `crit_damage` affix (rolled by `ItemRoller`,
"+15-20% increased Critical Strike Damage") was never actually applied.
`EquipmentComponent.MISC_BONUS_KEYS` didn't include `"crit_damage"`, so
`compute_misc_bonuses()` silently dropped every such affix, and all 3
call sites of `DamageCalculator.get_crit_damage_multiplier()` (`ability.
gd`, `weapon.gd`, `StatSummaryBuilder.gd`) called it with no argument,
always taking its default 0.0 bonus. Fixed by adding `"crit_damage"` to
`MISC_BONUS_KEYS`, adding `StatSheet.get_crit_damage_bonus()` (converts
the summed percent-unit affix total to a fraction), and passing it at all
3 call sites. Did NOT adopt the brief's own proposed `get_crit_damage_
bonus()` body (`equipment_bonus.get("crit_damage", 0.0)`) - `equipment_
bonus` is keyed by `Constants.Stat` enum for the 3 core stats only,
`crit_damage` lives in the separate `misc_bonus` dict alongside max_life/
attack_speed/etc.; the brief's version would have compiled fine and
silently kept the bug alive. Verified with a scratch test: a `+18%`
`crit_damage` affix now correctly yields a `1.77` multiplier
(`1.5 * 1.18`) instead of a flat `1.5`.

**Starting Gold.** `GameState.reset_to_defaults()` (the real new-game
initializer, called from `MainMenu._on_new_game_pressed()` - no separate
`_initialize_new_game()` exists) now sets `gold = 1000000` instead of `0`.
`SaveManager.load_game()` (Continue) already restores `gold` from the
save JSON and never touches `reset_to_defaults()`, so the brief's own
"don't reset gold when continuing" caveat needed no change.

**Brand Shop.** New Hub interactable (`entities/interactables/brand_shop/
BrandShop.gd`+`.tscn`), same proximity-and-`E` pattern as `GearShop`/
`SpellTestShop`, placed at `(0, 0, -8)`. Reuses the Hub's existing shared
`ShopScreen` via `open_with()` rather than building a second shop UI from
scratch (`ShopScreen` already handles the gold check/deduct/button-
disable/ItemCard-hover-tooltip machinery both other shops use) - added
one small extension, an optional `"repeatable"` entry flag, so Brand
rows stay buyable after a purchase instead of `ShopScreen`'s normal
permanent post-purchase disable (GearShop/SpellTestShop entries don't set
it, so their behavior is unchanged). Sources its brand list from the real
`Constants.BRAND_RARITIES` (26 ids, one per `data/brands/instances/
*.tres`) instead of the brief's own hardcoded price table, which named 2
brands that don't exist in this project at all (`amalgam`, `facsimile`/
`imbue` - explicitly cut per `Brand.gd`'s own header, no `BrandRarity.
LEGENDARY` entries exist to price) and one with a wrong id (`hollow_brand`
vs the real `hollow`) - deriving the list from `Constants` means it can
never drift from what's actually purchasable. Price by `BrandRarity` tier
(Common 50/Uncommon 200/Rare 800/Legendary 5000, per the brief) - a real
Legendary Brand would price correctly if one is ever added back. Also
skipped the brief's proposed `ItemAffix`-based grant (`is_brand = true`
on a new `ItemAffix`) - real Brands are `Item` subclasses (`Brand extends
Item`, loaded from their own `.tres` files), not affixes; `ItemAffix.
is_brand` exists but nothing in the project reads it. `_buy()` instead
`load()`s and `duplicate()`s the real Brand resource and appends it to
`GameState.owned_loot`, the same mechanism `LootPickup`/`GearShop` already
use. Added `EventBus.brand_purchased(brand_id)`/`gold_spent(amount)` per
the brief, emitted from `_buy()` - no consumer yet, same "real emit site,
no listener required" footing `brand_consumed` already had. Verified with
a scratch test: purchase grants a correctly-typed, independently-
duplicated `Brand` instance and fires both signals; all 26
`BRAND_RARITIES` ids resolve to a real file.

## 2026-09-06 — Implementation Brief v3.8b: Post-v3.8 Bug Sweep + Channel/Spark/Winter's Eye Reworks

Follow-up brief framed as bug reports against what v3.8 just shipped, plus
several new mechanics. Researched every claim against the real code before
touching anything (this session's standing rule) - three of the brief's
own root-cause claims turned out wrong or already-fixed, one bug was real
but mis-located, and one investigation surfaced a second, more systemic
bug the brief didn't know about.

**Priority 1 - stat bugs.**
- **1a "Prowess not providing Attack Power"** - `Weapon._base_hit()` /
  `StatSheet.get_attack_power_from_stats()` were already correct. The
  real cause was 1c below: gear implicits granting Prowess/Finesse/
  Resolve were silently non-functional, which reads the same as "my
  stat isn't doing anything."
- **1b starting stats** - `data/stats/instances/player_baseline.tres`
  had `prowess=finesse=resolve=10` (a v3.8 placeholder) instead of the
  intended `prowess=4, finesse=7, resolve=4`. Fixed.
- **1c/1d stale implicit stat keys + names, and a second bug found
  underneath.** v3.8's own `repair_stat_migration.gd` only remapped
  `Item.stat_requirement`/`Weapon.scaling_stat` - it never touched
  `ItemAffix.stat_key`/`description` on hand-authored implicits (Frayed
  Belt, Vitality Pendant, Tarnished Ring, Worn Gauntlet still read
  `flat_strength`/`flat_vitality`/`flat_instinct`/`flat_enigma`, which
  `EquipmentComponent.AFFIX_STAT_KEYS` no longer recognizes - contributed
  nothing while still showing old text). While fixing this, found that
  **all 14** hand-authored items with a single affix (those 4 plus the 5
  named rings and 5 starter weapons) never actually set `ItemAffix.
  is_implicit = true` on it, despite their own description text saying
  "(implicit)" - `is_implicit` defaulted to `false`, so ItemCard's
  implicit/explicit split (which reads the flag, not the string) rendered
  every one of them as an explicit mod. New `tools/repair_implicit_
  affixes.gd` (same one-shot pattern as `repair_weapon_lines.gd`) fixed
  both across all 4 item directories: 14 affixes flagged `is_implicit`,
  4 stat keys remapped (value preserved, per the brief - except Tarnished
  Ring, see Priority 4), 2 display names renamed (Vitality Pendant ->
  Prowess Pendant; a `gen_rune_shield_arcane_rune_shield.tres` surfaced by
  the same scan, "Arcane Rune Shield" -> "Resolve Rune Shield", same old-
  stat-name pattern).

**Priority 2 - weapon set persistence, real root cause found via data-flow
tracing (not guessing, as the brief demanded).** `EquipmentComponent.
get_all_equipped_refs()` (feeds `GameState.equipment_refs` via `sync_
equipment()`) deliberately excludes `primary_weapon`/`offhand` - those
live only in `GameState.weapon_set_refs`, written only by `sync_weapon_
sets()`. That call existed at exactly two places: the Set A/B toggle
button and the in-game tap-X-to-swap handler - **never** on a plain
equip/unequip. So equipping a new weapon into the currently-active set
(the common case) updated the live `EquipmentComponent` correctly but
never touched `GameState.weapon_set_refs`; the next zone transition's
`Player._apply_saved_loadout()` read the stale array and re-equipped the
OLD weapon. Confirmed with a real scratch test (equip -> sync_equipment
only -> stale; add sync_weapon_sets -> correct; fresh EquipmentComponent
restored from GameState -> weapon survives) before and after the fix.
Fixed by having `InventoryScreen._on_item_selected()`/`_on_doll_slot_
pressed()` also call `GameState.sync_weapon_sets()`. This is also why the
same symptom kept getting reported as "already fixed" in earlier
patches - every previous investigation checked whether `_apply_saved_
loadout()` correctly READ `weapon_set_refs` (it does) without checking
whether ordinary equipping ever WROTE to it (it didn't).

**Priority 3 - item border color, real bug found in 3 places, none of
them ItemCard.gd.** `ItemCard._render_item()`'s border was already
correctly rarity-based. The actual bug (weapon slot buttons coloring by
damage type instead of rarity) was duplicated in `InventoryScreen.
_item_color()`, `CraftingScreen._item_color()`, and `GearShop.
_item_color()` - all three fixed to rarity-only. Left `ItemCard.
_render_ability()`'s damage-type border alone - that one is intentional
(v3.8's own design rationale: distinguishing spells by element), and the
brief's examples were all item types, not abilities.

**Priority 4 - ring implicits.** All 5 rings already carry an implicit
(4 resistance, 1 stat) once the Priority 1c `is_implicit` fix above
landed - "Tarnished Ring has no implicit" was the same bug as 1c, not a
missing implicit. Its value (18, calibrated for the old 6-stat system) was
still out of range for the brief's new ring-implicit tiers, so it was
re-rolled fresh under that spec instead of just remapped: item_level 1 ->
Low tier -> +4 Finesse (implicit).

**Priority 5 - ItemCard mod ordering/coloring.** `_render_item()` now
places sockets before implicits, implicits in gold (`IMPLICIT_COLOR`)
instead of blue, and the dividing line only between implicit and explicit
groups when both are non-empty (never before implicits, never at all if
either group is empty).

**Priority 6 - Character Screen.** Removed the stale six-stat `HintLabel`
paragraph; added a `PrimaryStatsRow` of large PROWESS/FINESSE/RESOLVE
labels above the columns. The existing column labels (Prowess/Attack
Power/Main Hand Damage/Main Hand Crit, Finesse/Evasion/Max Health/Life
Regen/Max Ward/Armor, Resolve/Spell Power/Max Mana/Mana Regen/Move+Sprint+
Action Speed) already matched the brief's spec exactly - no relabeling
needed. "Live on gear equip/unequip" is automatic since `PauseMenu.
_toggle_screen()` never allows this screen and InventoryScreen open at
the same time.

**Priority 7 - XP bar trail.** Added a second shader-material layer
(`_xp_trail_clip`, brightened `modulate`) behind the existing fill that
snaps instantly to the new ratio on every XP gain, while the existing
fill tweens up to meet it - inverse of the health bar's damage trail, as
specified.

**Priority 8 - Flame Jets channel rework.** Was a fixed-duration channel
started on cast (deliberately, per v3.8's own comment, to avoid a bigger
resource-model change). Now genuinely hold-to-channel: cuts off
immediately (no grace tick) on key release or Mana hitting 0, and drains
`CHANNEL_MANA_DRAIN_PERCENT` (8%) of its resource cost every `CHANNEL_
MANA_DRAIN_INTERVAL` (0.15s) while held, on top of the existing upfront
cost. Scoped to real player-held casts only - Slate auto-cast Flame Jets
(explicitly zero-resource-cost) skips both the hold-check and the drain.
`CastTimeHandler` already fires CHANNELED abilities' `_cast()` immediately
with no interruptible windup, so "not interruptible by damage" needed no
change.

**Priority 9 - Winter's Eye.** Already had a working periodic-tick-while-
traveling architecture (contrary to the brief's "deals burst damage on
arrival" framing) - updated to the brief's new constants (`ORB_SPEED` 8.0,
`SHARD_RADIUS` 6.0, `MAX_DURATION` 3.0), capped each tick to the `MAX_
SHARDS_PER_TICK` (3) nearest enemies instead of hitting everyone in
radius, and added a cosmetic spin while traveling.

**Priority 10 - Spark rework + Shock.** New non-stacking Shock status
effect (`StatusEffectComponent`, same `_apply_timed()` pattern as
Electrocute/Unraveling/Slow): +20% Lightning damage taken, 4s, refresh-
on-reapply, no stun. Wired into `Enemy.take_damage()` via `get_shock_
multiplier()`. `spark.tres` now applies `"shock"` instead of
`"electrocute"` - Thunder Javelin/Thunder Sweep keep Electrocute,
unchanged. `SparkCrawler` already had working nearest-enemy seeking
(contrary to the brief's "moves randomly" framing) - reworked from an
instant heading-snap to a lerped `TURN_SPEED`-gated turn, and added
random wandering when no enemy is in range (previously held a fixed
heading).

**Priority 11 - Flame Wall reticle.** The shared aiming reticle was one
reusable circular Torus mesh for every ground-targeted ability, including
Flame Wall - which is actually a `BoxMesh` wall (width x `WALL_THICKNESS`,
oriented perpendicular to the caster->target line, per `FlameWallField.
gd`). `PlayerAbilityCast._show_reticle()`/`_update_reticle()` now swap in
a matching flat rectangle (reading `FlameWallField.WALL_THICKNESS`
directly rather than duplicating it) with the same `look_at()` orientation
FlameWallField itself uses, for Flame Wall specifically.

**Priority 12 - Shock in Constants.** Added `"shock": DamageType.
LIGHTNING` to `STATUS_EFFECT_DAMAGE_TYPE` and `"shock": "Shocked"` to
`STATUS_EFFECT_NAME`.

## 2026-09-06 — Implementation Brief v3.8: Six Stats to Three, Weapon/Spell Card Redesign

User pasted "Implementation Brief v3.8" (a zone-transition performance
fix, collapsing the six-stat system to three, weapon/spell card
redesigns, and an Alt-hold revision). The stat rewrite alone touched 13
`.gd` files plus a ~1000-file data migration - the largest single brief
this project has taken on. Researched first, as established this
session, and found the brief's own Priority 1 root cause disproven by a
direct empirical test - flagged before writing any code, alongside two
real architectural questions the stat rewrite raised.

**Priority 1 (ItemRoller autoload) - skipped, confirmed with the user.**
The claimed root cause ("static vars reset every scene change in
Godot") was tested directly: a static var on a `class_name RefCounted`
script, bumped in one scene, checked in a second after a real
`get_tree().change_scene_to_file()` call - it persisted correctly (1,
not reset to 0). `ItemRoller._candidate_meta_cache` is a `Dictionary`
guarded by `if _candidate_meta_cache.is_empty(): _build_candidate_meta_
cache()`, and nothing anywhere clears it, so it already only builds once
per process lifetime. Third brief in a row with a disproven root-cause
claim (weapon-set persistence in v3.6b, ItemDatabase eager-loading in
v3.7, this one) - user agreed to skip rather than build a fix for a bug
that isn't there.

**Priority 2 (six stats to three) - two real forks, confirmed with the
user before touching ~1000 files.** Vitality/Strength/Instinct/Arcane/
Enigma/Intellect collapse to Prowess/Finesse/Resolve. The brief's own
per-line damage formula snippets turned out to be exactly what
`DamageCalculator.calculate()` already computes internally (`power :=
base + stat_value * effective_grade_multiplier`) - "DO NOT change
calculate()'s signature" reconciles cleanly once read that way: only
what `Weapon._base_hit()`/`Ability._base_hit()` pass AS `stat_value`
changes (now `get_attack_power_from_stats()`/`get_spell_power_from_
stats()`, always Prowess/Resolve regardless of damage type - a real
simplification versus the old per-damage-type stat lookup), `calculate()`
itself is untouched.

1. **Data migration.** Every already-generated item's `stat_requirement`
   (an int under the OLD 6-value enum, silently reinterpreted as a
   different stat under a 3-value one - the exact class of bug already
   caught once with `EquipmentSlot` in Patch v3.5) and every weapon's
   `primary_scaling_stat`/`secondary_scaling_stat` (Patch v3.6b strings
   like "instinct," now naming stats that don't exist) needed a real
   remap, not just renumbering. Proposed and got sign-off on: Vitality/
   Strength -> Prowess, Instinct -> Finesse, Arcane/Enigma/Intellect ->
   Resolve - mirrors the brief's own damage-type reassignment for the 4
   stats it covers. New `tools/repair_stat_migration.gd` ran across all
   4 item directories - 1004 items scanned, 913 `stat_requirement` values
   and 644 scaling-stat strings remapped. Unlike Patch v3.7's
   `base_damage` repair, `stat_requirement`'s field name/type didn't
   change, so a plain `load()`/re-save sufficed - Godot doesn't validate
   an enum-typed property's stored int against the enum's current range,
   so the OLD value round-trips through `load()` intact to remap.
2. **Crit chance/damage formula.** `DamageCalculator.get_crit_chance()`/
   `get_crit_damage_multiplier()` had their own hardcoded per-point
   formulas separate from `calculate()` (which the brief protects), and
   Intellect (crit damage's old source) isn't a stat anymore at all.
   Confirmed: crit chance becomes additive (`base_crit_chance +
   StatSheet.get_crit_chance_from_stats()`, replacing the old `x(1 +
   instinct*0.03)` multiplicative one), crit damage multiplier drops to a
   flat 1.5x with an optional bonus-fraction param defaulting to 0.0 -
   purely gear-affix-driven going forward (`crit_damage` is a "removed
   expression" per the brief's own list), no consumer wired to it yet.

**"Removed expressions" (max_life, life_regen, max_mana, mana_regen,
attack_speed, cast_speed, move_speed, crit_damage, debuff_effectiveness,
resilience, stamina) - real, judgment-scoped wiring, not blanket
"add and forget."** `EquipmentComponent.compute_misc_bonuses()` (new,
mirrors `compute_resistance_bonuses()`) sums these into `StatSheet.
misc_bonus`. Six got REAL consumers because something already,
actively depended on their old stat-derived value and would otherwise
have silently broken: `max_life`/`life_regen` (Health), `max_mana`/
`mana_regen` (Mana), `flat_resilience` (already existed, pre-v3.8,
previously fully decorative - now real, replacing Vitality's DoT-
mitigation role), and `attack_speed`/`move_speed` (`Player.get_action_
speed_multiplier()`/`get_move_speed_multiplier()`, both load-bearing
multipliers used throughout combat/movement that would have been left
calling a compile-broken `Constants.Stat.INSTINCT` otherwise - found
these two only because the FIRST headless compile check after editing
`Constants.gd` surfaced them as real "Cannot find member INSTINCT"
parse errors, not because a grep caught them ahead of time). `cast_speed`
feeds Patch v3.7's existing `StatSheet.cast_speed_bonus` field directly.
`crit_damage`/`debuff_effectiveness`/`stamina` (and `move_speed`'s own
pool entry once attack/move speed's split was decided) stay descriptive-
only in `ItemRoller.AFFIX_POOL` - same "real affix, no formula to feed
it yet" footing every other under-specified pool entry in this project
already has (flat_evasion, the 4 resistance affixes, skill_cooldown_
reduced). `StatusEffectComponent._debuff_effectiveness_multiplier()` now
returns a flat 1.0 (was Intellect-derived) since debuff_effectiveness
has no wired consumer.

**A real bug caught only by the headless compile check, not a grep.**
Two live, load-bearing references to `Constants.Stat.INSTINCT` in
`Player.gd` (`get_move_speed_multiplier()`/`get_action_speed_multiplier()`)
weren't in the brief's own suggested `grep -rn "VITALITY\|STRENGTH\|..."`
research pass results the FIRST time through, since they were further
down the file than the block already fixed - the first post-edit
headless load surfaced them immediately as parse errors ("Cannot find
member INSTINCT"), cascading into ~20 unrelated-looking compile failures
across the whole dependency graph until traced back to the two real
lines. A second full-project grep (this time for bare `.vitality`/
`.strength`/etc. field access, not just `Constants.Stat.X`) caught one
more real one - `Player._ready()`'s own fallback `StatSheet.new()`
default-value block - before the migration script ran.

**Priority 3 (Weapon card redesign).** Border-color-by-rarity turned out
to already be true for the Item card type (`display_item()` already used
`Constants.ITEM_RARITY_COLOR`, not damage type - only the Ability card
uses an element color, and Priority 4 doesn't ask to change that) - no
change needed there. New Attack Power display (white base + blue stat
bonus, `_build_attack_power_lines()`/`_get_stat_contribution()` mirroring
`Weapon._base_hit()`'s own formula so the card can't drift from a real
swing) replaces the old flat damage line. Scaling Grade moved to Alt
Info. Socket count text replaced with real socket art (`SocketRow`, an
inner `Control` subclass with its own `_draw()`) - required a genuine
new `Item.sockets` field (Patch v3.6b's `max_sockets`-does-double-duty
model couldn't represent "filled vs. empty" at all): `max_sockets` stays
the item type's overall CAP (raised by Bore/Corruption, completely
unchanged), `sockets` is how many of those a specific rolled instance
actually has (`ItemRoller.roll()`, 0 to `max_sockets` inclusive, same
"the base sets a ceiling, the roll picks a point under it" shape affix
tiers already use) - chosen specifically because it coexists with the
existing Bore/Corruption code with zero changes there, instead of
re-plumbing a tested system for a UI-only requirement.

**Priority 4 (Spell card redesign).** Motion Value and Predicted Damage
removed from the main ability card (Scaling Grade moved to Alt Info
too); Cast Type added (reusing Patch v3.7's `Ability.cast_type`); status
effects now show their real display name (`Constants.STATUS_EFFECT_
NAME`) instead of the raw id, which the card was silently doing wrong
before this pass touched it.

**Priority 5 (Alt Info revision) - a real behavioral removal, not just a
content change.** The old Alt-hold system (`autoloads/AdvancedTooltip.gd`,
a whole second `CanvasLayer` with its own floating `ItemCard` instance,
click-to-pin, full tier ranges, clickable stat glossary links) is gone
entirely - deleted, unregistered from `project.godot`'s autoload list.
`ItemCard.gd` now listens for Alt directly via its own `_input()` while
Godot's native tooltip system is already showing it, and swaps its OWN
content between the normal card and a new, much narrower Alt Info panel
(Scaling Grade, Primary/Secondary Scaling, Item Level, stat requirement)
in place - no second window, no clicks, release Alt and it swaps back.
Caught and fixed a bug in the brief's own Alt Info snippet along the way:
`if item.stat_requirement > 0` would silently skip the line for a
Prowess (0) requirement - fixed to `!= -1`, matching the "-1 means no
requirement" sentinel already used everywhere else in this project.

Verified with a scratch functional test (not just scene-load checks) -
26/26 checks passed, covering the new derived-stat formulas, the crit
formula, real damage rolls end-to-end through both Weapon and Ability,
the data migration's actual output, `compute_misc_bonuses()`, the socket
roll, `ItemCard` building real content for both an item and an ability,
the Alt Info in-place swap, and `AdvancedTooltip`'s full removal. Full
headless regression sweep across `Hub`/`TestArena`/`PinnacleArena`/
`InventoryScreen`/`CraftingScreen`/`FateBoardEditor`/`CharacterScreen`/
`AbilitiesScreen` came back clean.

---

## 2026-09-02 (newest) — Implementation Brief v3.7: Spell Power Floor, Cast Times, Damage Ranges

User pasted "Implementation Brief v3.7" (7 priorities: spell damage fix,
cast_type system, Cast Speed stat, a weapon-set persistence bug, damage
roll ranges, load-time optimization, dynamic stat cards). Researched
first, as established this session, and found the biggest reconciliation
need yet - two of the seven priorities described bugs/premises that
don't reproduce against the real code, and a third needed a materially
different mechanism than specified to avoid a 15+-call-site refactor.
All three were raised via AskUserQuestion before writing anything.

**Priority 4 (weapon set persistence) - skipped, confirmed with the
user.** `Player._apply_saved_loadout()` (Player.gd:304) already does
`equipment.active_weapon_set = GameState.active_weapon_set`, positioned
correctly after both weapon sets' items are equipped - this exact fix
already exists, dated to the dual-weapon-set work in Patch v3.4/v3.5.
`GameState.save_state()`/`restore_state()` and `EquipmentComponent.
weapon_set_a`/`weapon_set_b` (the brief's own proposed fix target) don't
exist in this codebase at all - the real persistence already runs
through `sync_weapon_sets()`/`weapon_set_refs`/`active_weapon_set`,
fully wired since Patch v3.5. User agreed to skip rather than build a
fix for a bug that isn't there.

**Priority 6 (ItemDatabase / lazy loading) - skipped, confirmed with the
user.** The stated root cause ("640+ .tres files preloaded eagerly at
startup") doesn't hold - zero `preload()` calls exist for any item
resource anywhere in this project; items already load lazily via
`load()`. The one real cost found (`ItemRoller` building its ~750-file
metadata cache on first loot roll, not at startup) is a different,
narrower thing than what was described. User agreed not to add a new
autoload for a problem that isn't there.

**Priority 1 (spell damage floor) - built with a lower-blast-radius
mechanism than specified, confirmed with the user first.** The "single-
digit spell damage" root cause is real and already documented in this
codebase's own history: Implementation Brief v3.3 deliberately gave
spells `base_weapon_damage = 0` in `DamageCalculator.calculate()` (no
floor), and this brief's fix (a Conduit spell-power floor) is the right
shape - but its own mechanism (`caster.get_active_conduit()`, threaded
through every `Ability.predict_damage()`/`roll_damage()` call) would
have touched 15+ call sites across `PlayerAbilityCast.gd` and 6
`entities/effects/*_field/*.gd` scripts. Built instead as `StatSheet.
conduit_spell_power`, recomputed by `Player._on_equipment_changed()`
from `equipment.primary_weapon` (checked for `is_conduit`, per user
direction - offhand Conduits don't contribute) - the same "cache on
StatSheet, zero call-site changes" pattern `equipment_bonus`/
`increased_damage_generic` already established. `Ability._base_hit()`
now passes `stat_sheet.conduit_spell_power` instead of a hardcoded `0.0`
into the unchanged, existing `DamageCalculator.calculate()` - the "More
multiplier pipeline" stayed completely untouched, per the brief's own
DO-NOT.

**Priority 2 (cast_type system).** `Ability.gd` gained `cast_type`
(INSTANT/CAST_TIME/CHANNELED)/`base_cast_time`/`base_recovery_time`/
`channel_duration`. New `entities/player/CastTimeHandler.gd` component
on Player, wired into `PlayerAbilityCast._try_cast()` at the one real
choke point that function already has (after mana/cooldown checks pass,
before the actual per-ability `_cast()` dispatch) - INSTANT and
CHANNELED both complete synchronously with zero behavior change (several
abilities, e.g. Flame Jets, already run their own bespoke channel loop
entirely separately, untouched); only CAST_TIME abilities (Comet 1.2s,
Winter's Eye 0.8s, Meteor 1.6s, Black Hole 1.0s - the 4 real matches from
the brief's table that exist in this project; "purity_from_within"/
"blinkstrike" don't) actually gain a real, interruptible windup.
`Player.take_damage()` interrupts a CAST_TIME cast - `is_casting()` is
only ever true mid-CAST_TIME by construction (INSTANT/CHANNELED never
set it), so this can't accidentally interrupt either of those, no extra
type check needed, satisfying the brief's own DO-NOT for free.

**A real `@onready`-ordering bug, caught by the headless load check, not
by reading the diff.** The first pass had `PlayerAbilityCast._ready()`
connect to `_player.cast_time_handler.cast_completed` directly - crashed
with "Invalid access... on a base object of type 'Nil'" on every scene
load, since Godot calls a child's `_ready()` before its parent's, and
`cast_time_handler` (a `Player` `@onready` var, PlayerAbilityCast's own
sibling) isn't resolved yet when PlayerAbilityCast (a child of Player)
runs its own `_ready()`. Exactly the "Godot @onready timing bugs" class
this project has hit before - fixed by moving the connection into
`Player._ready()` itself, which runs last (after every child's own
`_ready()`), so both components are guaranteed live there.

**Priority 3 (Cast Speed stat).** `StatSheet` gained `cast_speed_bonus`/
`cooldown_recovery_rate` (both additive percentage pools, recalculated
every stat refresh, never cached) plus `get_effective_cast_time()`/
`get_effective_cooldown()`/`apply_cast_speed_to_cooldown_conversion()`.
Divides by `(1.0 + bonus / 100.0)`, not the brief's own literal
`(1.0 + cast_speed_bonus)` - that formula only works if the stat were a
raw fraction (0.20), but `Constants.CAST_SPEED_TIERS` (added, 5 tiers)
and the whole rest of this project treat percentage stats as raw numbers
like 20.0 - another internal inconsistency in the brief itself, caught
and fixed the same way DamageCalculator/every other percentage pool in
this codebase already works. One new Slate Affix Pool stub added
(`spell_cast_speed_to_cooldown_recovery.tres`, tag "spell") for the
Cast Speed -> Cooldown Recovery conversion Slate mod - not wired to any
consumer yet, same "data before mechanic" footing as every other Slate
Affix Pool stub.

**Priority 5 (damage roll ranges).** `Weapon.gd`'s single `base_damage`
replaced with `base_damage_min`/`base_damage_max`/`rolled_base_damage`
(`get_base_damage()` returns the rolled value if set, else the range's
midpoint) - and the same pattern for a Conduit's `spell_power_min`/
`spell_power_max`/`rolled_spell_power`/`get_spell_power()`. `ItemRoller.
roll()` now rolls both on an actual drop. New `tools/
repair_damage_ranges.gd` split every one of 651 real weapon `.tres`
files' old `base_damage` into `±15%` min/max (Conduits got `spell_power_
min`/`max` set from the same source value too, since Patch v3.6b's
Conduit generator used `base_damage` to mean Spell Power before this
field existed) - caught its own bug before running: 17 of 651 files had
`base_damage` exactly matching the class's old default (10.0), which
Godot never serializes, so "no `base_damage` line in the file" had to
mean 10.0, not 0, or those 17 items would have silently ended up with a
broken 0/0 range. `Weapon._base_hit()` now calls `get_base_damage()`
instead of reading the removed field directly.

**Priority 7 (dynamic stat cards).** `ItemCard.gd` (the real file - no
`ItemTooltip.gd`/`BaseItem`/`ArmorItem` exist in this project) now shows
the rolled damage/spell power value when one exists, falling back to the
range display otherwise; implicits now render in their own section above
the rolled-affix list, matching Section 18's own implicit/explicit
distinction; the scaling grade line now also shows `primary_scaling_
stat` (e.g. "A Instinct") using the existing `Constants.ScalingGrade.
keys()[grade]` lookup rather than adding a redundant new `grade_to_
letter()` function that would return the exact same letters. The brief's
"must update on stat/equip changes via EventBus" turned out to already
be satisfied by construction, not by wiring new signals - `ItemCard` is
rebuilt fresh (`display_item()` called anew) every single hover via
Godot's `_make_custom_tooltip()` hook, so it already reads live instance
data on every show; no caching/staleness to fix.

Verified with a scratch functional test (not just scene-load checks) -
24/24 checks passed, covering the conduit spell-power floor, all three
CastType behaviors (including the interrupt/no-interrupt distinction),
Cast Speed's conversion math, the damage-range repair's real output, and
ItemRoller's new rolling. Full headless regression sweep across `Hub`/
`TestArena`/`PinnacleArena`/`InventoryScreen`/`CraftingScreen`/
`FateBoardEditor` came back clean.

---

## 2026-09-02 (newer) — Implementation Brief v3.6b: Weapon Line Repair, Bows, Conduits, Ascendant

User pasted "Implementation Brief v3.6b" - two systemic bugs across every
Section-25-generated weapon (`scaling_grade` stuck at C regardless of
line identity; implicits stored as inert `flavor_text` prose instead of
real affixes), plus new Shortbow/Longbow/Conduit weapon lines and a new
Tier-3 corruption outcome.

**A real architecture question, asked before touching any of 500+
files.** The brief's own repair table lists up to TWO (stat, grade) pairs
per line (e.g. `rapier_line1: [("instinct", 1), ("strength", 3)]`), but
`Weapon.scaling_grade` is a single field, and the stat it governs is
derived from damage type (`Constants.DAMAGE_TYPE_MAIN_STAT`) - which
doesn't even reach Instinct or Vitality at all today. Worse, the table's
first-listed stat routinely DIDN'T match a line's real damage-type-implied
stat (rapiers are native Piercing -> Strength, but the table leads with
Instinct) - meaning the brief assumes a real per-weapon-line multi-stat
scaling model this project doesn't have, and `DamageCalculator.gd` was
explicitly off-limits to build one in. Asked rather than guessed, since
getting this wrong would mean redoing the repair across every weapon
file. User direction: only the FIRST tuple's grade sets the real
`scaling_grade` field; every tuple's stat name becomes new, purely
descriptive `Weapon.primary_scaling_stat`/`secondary_scaling_stat`
metadata, not wired into damage calculation at all - multi-stat scaling
stays a future system.

**Repair script** (`tools/repair_weapon_lines.gd`, run via `tools/
repair_weapon_lines.tscn`) - a GDScript tool script, not the brief's own
"Python preferred," since this project has zero Python tooling and
`ResourceSaver.save()`/`load()` can rewrite real `.tres` Resources
directly rather than hand-parsing Godot's resource text format; same
one-shot-generator convention as `tools/generate_base_types.gd`. Verified
the brief's own 64-line table against every real `base_line_id` in
`data/weapons/instances/*.tres` before running it (exact match, no
missing/extra lines) and confirmed all 511 weapon files were clean in
git before running, so a mistake would be trivially recoverable. Repaired
504 files (the other 7 are hand-authored pre-Section-25 singles with no
`base_line_id`, correctly skipped); an S-grade line (`grades[0][1] == 0`)
gets its `flavor_text`'s `"- Implicit: ..."` suffix stripped and no affix
added, everything else gets a real `ItemAffix` (`is_implicit = true`,
`stat_key`/`value` from the table, `display_name` from the table's
`rename` or a humanized `stat_key`) appended to `affixes`, with the same
suffix stripped off `flavor_text` so the implicit isn't duplicated as
both prose and data. Idempotent - safe to re-run.

**Shortbow & Longbow** (`tools/generate_bow_lines.gd`, 32 new files: 16
each, 2 lines × 8 tiers). Same field conventions as every other generated
weapon - `base_damage` from the brief's own per-tier range averages
(matching `generate_base_types.gd`'s own `_parse_range_avg()`),
`native_damage_type` = Piercing (matching the existing hand-authored
`worn_bow.tres`), `stat_requirement` = Strength at 0.5/item_level (the
established formula, confirmed against real crossbow tier data before
reuse). Tier display names are simple, shared placeholders - the brief
explicitly scopes real naming to a separate pass.

**Conduits** (`tools/generate_conduit_lines.gd`, 108 new files: 9 types
× 2 lines × 6 tiers). `Weapon.gd` gained `is_conduit`/
`conduit_stance_type`/`spell_page_tag`/`unleash_copy_count`. "Spell
power" maps onto the existing `base_damage` field rather than a new one -
Conduits are still real `Weapon` instances routed through the same equip
system even though actual spellcasting is independent of the weapon slot
(`WeaponStance.gd`'s own header already noted this). `native_damage_type`
(Aetheric) and `is_two_handed` (true only for Staff) both follow the one
real precedent already in the project (`worn_staff.tres`) rather than
inventing a new scheme - every other Conduit type stays one-handed so a
main-hand + offhand pair is actually equippable together, matching the
whole point of having separate Rod/Grimoire/Tome/Talisman/Fetish offhand
foci. Only Rod line 1 was explicitly called "lower spell power" in the
brief - applied a 60% reduction (this project's own invented number,
flagged as such) to just that one line, not the rest of the offhand
types, since the brief didn't say to.

**Ascendant** (new Tier-3/Major corruption outcome, `CorruptionOutcome.
Ascendant`, registered in `CorruptionSystem._MAJOR`): upgrades a Weapon's
`scaling_grade` by one step (B->A, etc.), near-misses (logged, not an
error) on an already-S-grade Weapon or any non-Weapon Item, and emits
the new `EventBus.grade_ascended` signal. The brief's own "pick one
random scaling grade stat" reduces to "the only one there is" given this
project's single-`scaling_grade`-field reality established above.

Verified with a scratch functional test (not just scene-load checks) -
23/23 checks passed on the first run, confirming the repair script's
real output (grades, affixes, stripped flavor_text), all four new
weapon families' field values, offhand-Conduit equip routing (Patch
v3.5's `is_offhand` routing exercised against real new data), and
Ascendant's upgrade/near-miss/signal behavior. Full headless regression
sweep across `Hub`/`TestArena`/`PinnacleArena`/`InventoryScreen`/
`CraftingScreen`/`FateBoardEditor` came back clean.

---

## 2026-09-02 — Implementation Brief v3.6: Slate Affix Pool, Cube Combinations, Shard of Tharsis Rework

User pasted "Implementation Brief v3.6" (a new Slate affix pool, richer
Cube Brand-combination logic, and a 4-tier Shard of Tharsis corruption
model). Priorities 2 and 3 (the Cube, the Shard) turned out to already
exist in full - `CraftingSystem.craft_cube()`/`corrupt()`, wired into a
real, working `ui/crafting/CraftingScreen.gd` - using a materially
different design (a single weighted category-tag pick instead of named
brand-pair/triple combinations; a flat 8-outcome corruption list instead
of a tiered, named-outcome one). The existing version's own comments
already flagged itself as an "invented placeholder" pending exactly this
kind of real design pass (Section 24 "Deferred Design"), so - confirmed
via AskUserQuestion rather than assumed - this became a rewrite of that
placeholder logic, not a second parallel system. Brief's own file names
(`BaseItem`, a `brand_id`-string-keyed `CraftingCube`) didn't match this
project's real classes (`Item`, `Brand.item_id`/`category_tag`) either,
same reconciliation pattern as every brief before this one.

**Slate Affix Pool** (Priority 1, genuinely new - no existing
equivalent): `data/items/SlateAffix.gd` extends `ItemAffix` (tag/
is_conditional/condition_description/is_behavior_modifier), and
`systems/crafting/SlateAffixPool.gd` is a lazily-scanned static pool over
`data/slates/affix_pool/*.tres` - same directory-scan-and-cache
convention as `ItemRoller`/`BrandRoller`, not a true autoload (nothing
here needs to be a persistent Node). 36 stub `.tres` files (3 per tag x
12 tags: the 9 real `Constants.DamageType` values plus "spell"/"attack"/
"generic", matching `Slate.category_tag_override`'s existing precedent
for non-damage-type tags) generated via a new `tools/
generate_slate_affix_stubs.gd` tool script, same one-shot-generator
pattern as `tools/generate_base_types.gd`. `Constants.DAMAGE_TYPE_TAGS`
added (lowercase string -> `DamageType` enum) since nothing mapped
between the two before this. Not used by any real hand-authored Slate
yet - those still carry their own fixed `SlateModifier` list; this is
scaffolding for a future procedural Slate-affix roll.

**The Cube** (Priority 2): new `systems/crafting/
BrandCombinationResolver.gd`, keyed on real `Brand.item_id` (this
project's 26 actual Brand instances), not the brief's own assumed
`brand_id` values - "hollow_brand" doesn't exist, the real id is
"hollow"; "distill"'s real `category_tag` is "resource" not "mana";
"hone"/"inscribe" share the SAME real tag ("skills"), not separate
"attack"/"spell" tags the brief assumed. Rather than inventing new
"hybrid_armor_evasion"-style pool names with no real data behind them,
every recognized combination resolves to a LIST of real
`ItemRoller.AFFIX_POOL` tags to union-roll from instead - Anneal+
Attenuate rolls from the combined armor+evasion pool, Calcine+Galvanic+
Quench from fire+cold+lightning, etc. Same Brand x3 caps the roll at
Tier 3-or-better (this project's Tier 1 is best, opposite the brief's
own "T1-T3 floor" phrasing, which reads as a minimum in a
higher-is-better scheme - translated to a cap, not a floor).
Unrecognized combinations still fall back to the original weighted-
any-present-tag pick, unchanged.

Two of the brief's own Brand reassignments were NOT applied, deliberately:
Refine (kept as its existing, doc-sourced "boost every affix's value"
behavior, not repointed at a new `quality` field) and Rectify (kept as
"reroll existing affix values," not repurposed into "upgrade one affix's
tier"). Both are already doc-referenced, tested mechanics with real
Brand `flavor_text` describing them to players - silently redefining an
established identity is different from filling in a genuinely
unspecified number, so these two were left alone. `Item.quality`
(0-30) still got added as the brief asked, just left unwired to Refine -
inert scaffolding for a future mechanic, not a redefinition of a working
one.

**Shard of Tharsis** (Priority 3): new `CorruptionSystem.gd`/
`CorruptionOutcome.gd` replace the flat 8-outcome weighted list with the
brief's 4-tier model (Minor 55% / Significant 30% / Major 12% / Extreme
3%), all 22 named outcomes implemented as-listed (none added, matching
the brief's own DO-NOT). `CraftingSystem.corrupt()` is now a thin
wrapper delegating to `CorruptionSystem.corrupt()`, so `CraftingScreen.
gd`'s existing Dictionary-shaped call site needed zero changes. The
existing `Item.is_craftable`/`RETAIN_CRAFTABLE_CHANCE` gate (a SEPARATE
restriction beyond "already corrupted," already wired into the Cube too)
was kept alongside the new tier model rather than replaced - the brief's
own `corrupt()` only checked `is_corrupted`, it didn't mention this gate
at all, so dropping it would have been a real regression to already-
working Cube behavior. Adapted field/API names throughout: `sockets` ->
`max_sockets` (this project already uses that one field as both current
and cap), `implicit_count()` -> `get_implicit_count()`, a 10-tier bound
-> `ItemRoller.TIER_COUNT` (5, this project's real tier count).
`Unmade`'s "elevated item level, capped at 91" turned out to already
match this project's real generated-catalog ceiling exactly (`tools/
generate_base_types.gd`'s highest tier) - not an arbitrary number
carried over blind.

`GearAffixPool` (the brief's own stub target for Convert/Aetheric Surge)
was NOT built as a stub - a real, working equivalent already exists
(`ItemRoller.AFFIX_POOL` + `_pool_for_brand_tag()`, the same pool the
Cube's own category-Brand rolls already draw from), so those two outcomes
call it directly instead of a no-op placeholder. `ImplicitPool`/
`SpecialCorruptionPool`/`UniquePool` ARE genuinely new (no existing
equivalent anywhere) and stayed real stubs per the brief - each logs a
`push_warning()` and returns null/empty.

**Veiltouch** (Major-tier outcome) is the one real gear/Slate crossover -
pulls a random `SlateAffix` (falling back across `Constants.
DAMAGE_TYPE_TAGS.keys()`, not `.values()` as the brief's own snippet
had it - that would have passed a raw `DamageType` int where
`SlateAffixPool.get_random_affix()` expects a string tag, a bug in the
brief itself caught while translating it), duplicates it onto the item
as a real explicit `ItemAffix`, and marks the item via `set_meta()` so it
can only trigger once per item, exactly as specified.

Verified with a scratch functional test (not just scene-load checks) -
27/27 checks passed, catching one real bug along the way:
`BrandCombinationResolver.resolve_tags()`'s declared `-> Array[String]`
return type crashed at runtime on its own `Dictionary`-sourced return
values, since a GDScript `const Dictionary`'s Array values are untyped
`Array`, not `Array[String]`, even when every element inside is a
String - fixed with an explicit copy-into-typed-array helper. Full
headless regression sweep across `CraftingScreen`/`Hub`/`TestArena`/
`PinnacleArena`/`InventoryScreen`/`FateBoardEditor` came back clean.

---

## 2026-09-01 (newer) — Implementation Brief v3.5: Slot Cuts, Throwable Stacks, Affix Scaffolding, Brand Rarity

User pasted "Implementation Brief v3.5" (rings 4→2, cut Sidearm/Conduit/
Secondary as equipment slots, throwables become inventory stacks, affix
data-structure scaffolding, Brand rarity/drop weights). Like v3.3/v3.4
before it, the brief's own file names and assumed slot model didn't match
what's actually built here - researched first (as established this
session), found two real reconciliation points, and used AskUserQuestion
rather than guessing:

1. **Sidearm isn't its own slot** - it's the 3rd slot inside the existing
   two-full-weapon-SET system (tap X swaps Set A/B, each holding Primary/
   Sidearm/Offhand, built per an earlier v3.4 user request). User
   confirmed: collapse each set to just Primary+Offhand, keep the A/B
   swap feature. Sidearm/Conduit weapon types now equip into Primary or
   Offhand based on hand type, same as the brief asked.
2. **`Affix.gd` would have duplicated the existing `ItemAffix`** class,
   already used in 29 files (ItemRoller, EquipmentComponent, StatSheet,
   CraftingSystem, tooltip UI, dozens of `.tres` instances). User
   confirmed: extend `ItemAffix` in place instead of building a parallel
   class and migrating everything to a 3-way array split.

Also found, by actually checking file names/enum values/existing
instances before writing anything: `EquipmentScreen.tscn` doesn't exist
(the real screen is `ui/inventory/InventoryScreen.tscn`); `PlayerEquipment.
gd` doesn't exist (`EquipmentComponent.gd`); `BaseItem.gd` doesn't exist
(`Item`, in `item.gd`); Brands and the Cube/CraftingSystem already exist
in full (the brief's own Brand list matches this project's `data/brands/
instances/` almost exactly, only Brand rarity weighting was actually
missing); zero Wand/Athame/Rod/Tome/Fetish/Charm/Grimoire/Talisman weapon
instances exist yet (only a single hand-authored `worn_staff.tres`), so
the brief's `is_main_hand`/`is_offhand` mapping had nothing real to touch
beyond the field additions themselves; every existing weapon `.tres`
already sat at `equip_slot = PRIMARY_WEAPON` regardless of type, so no
data migration was needed for weapons at all.

**Rings 4 → 2.** `EquipmentComponent.rings` shrank from a 4-slot array to
2; `_equip_ring()` was already generic over `rings.size()`, no change
needed there. `InventoryScreen`'s paper doll dropped `RingBottomLeft`/
`RingBottomRight`, keeping `RingTopLeft`/`RingTopRight` (renamed to
`RingLeft`/`RingRight`) - already symmetric, one per side, with zero
layout changes needed.

**Sidearm/Conduit/Secondary cut as slots.** `EquipmentComponent` lost
`sidearm_weapons`, `conduit`, `secondary_throwable` entirely. `offhands`
widened from `Array[Shield]` to `Array[Item]` so an offhand-type Weapon
(a future Rod/Tome/etc.) can sit there alongside a Shield - `get_total_
armor()`/`compute_ward_bonus()` guard with `is Shield` since a Weapon
offhand item has no `armor_value`/`ward_value`. `Weapon` gained `is_main_
hand`/`is_offhand`; `equip()` now special-cases `item is Weapon` and
routes by those fields before falling through to the general `equip_slot`
match (which still governs every non-weapon slot, unchanged).
`InventoryScreen`'s `ExtraRow` (Sidearm/Conduit/Secondary buttons) is
gone outright - equipping was already generic (`_on_item_selected()`
calls `equipment.equip(item)` with no explicit target slot; doll buttons
were always just display + unequip targets), so removing the row is the
entire UI-side change.

**A real bug caught by testing, not by reading the diff:** the first pass
just deleted the 3 retired `Constants.EquipmentSlot` enum entries
outright and let Godot renumber everything after them (OFFHAND 6→5,
AMULET 9→6, BELT 10→7, RING 11→8). `Item.equip_slot` is stored as a raw
int in every `.tres` file - Shields/Amulets/Belts/Rings included - so
this silently repointed every one of those files' stored slot at whatever
enum entry happened to land on that number now, without touching the
files themselves. A scratch functional test (equip real rings through
`EquipmentComponent`, not just load-check the scene) caught it
immediately - rings stopped equipping at all, since their stored int (11)
no longer matched any live enum value. Fixed by pinning every surviving
entry to its ORIGINAL explicit int (`OFFHAND = 6`, `AMULET = 9`, etc.)
instead of letting the enum renumber - `SIDEARM_WEAPON`(5)/`CONDUIT`(7)/
`SECONDARY_THROWABLE`(8) are simply retired, not reassigned. Also
incidentally found (not touched, out of scope): 15 pre-existing
`data/items/instances/gen_grenade_*.tres` items authored at the old
`SECONDARY_THROWABLE`(8) slot - now permanently unequippable, which is
correct given throwables aren't equipment anymore, but they were never
converted into real `ThrowableStack` instances either since the brief
only asked for the resource shape, not a content migration.

**Throwable stacks.** New `data/items/ThrowableStack.gd` exactly per the
brief (quantity/max_stack/can_use()/consume()). `Player.active_throwable`
+ `use_throwable()`, bound to a new `throw_secondary` input action
(middle mouse - no existing "secondary action" key actually existed in
this project's input map to reuse, despite the brief's phrasing).
`EventBus.throwable_used` fires on consume; `PlayerHUD` shows an icon +
count in the top-right corner (mirroring the top-left status-effect row),
showing "0" plainly rather than hiding. How a stack gets acquired or
selected as active is explicitly out of scope here (no crafting/
acquisition system invented, per the brief's own DO-NOT list) - starts
null.

**Affix scaffolding**, via the extend-in-place path: `ItemAffix` gained
`affix_id`/`display_name`/`min_item_level`/`is_generic`/`damage_type`/
`is_implicit`. `Item` gained `get_prefix_count()`/`get_suffix_count()`/
`get_implicit_count()`/`can_add_prefix()`/`can_add_suffix()` (Rare+ gate
for a 3rd prefix/suffix, matching the brief's own `rarity >= 2`) as
filters over the existing single `affixes` array rather than a 3-way
split - zero migration for the 29 files already reading `affixes`.
`StatSheet` gained `apply_affix()` as a single dispatch point (reusing
`EquipmentComponent.AFFIX_STAT_KEYS`/`RESISTANCE_AFFIX_KEYS` rather than
duplicating those tables) plus new `increased_damage_generic`/
`increased_damage_by_type` buckets, wired in additively alongside (not
replacing) the existing `compute_stat_bonuses()`/`compute_resistance_
bonuses()` pipeline - zero regression risk to the two stat categories
that already worked, since nothing currently generates an
`"increased_damage"`-keyed affix for the new buckets to consume yet
anyway (`ItemRoller` affix generation is explicitly a separate pass, per
the brief).

**Brand rarity.** `Constants.BrandRarity`/`BRAND_RARITIES`/
`BRAND_DROP_WEIGHTS` added, mapped 1:1 against the brief's own list minus
Facsimile/Amalgam/Imbue (never implemented as real Brand instances in
this project - see `Brand.gd`'s own header). `BrandRoller.roll()` now
rolls a rarity tier weighted by `BRAND_DROP_WEIGHTS` first, then picks
uniformly within that tier, replacing the previous fully-uniform pick
across every Brand regardless of power.

Verified with a scratch functional test exercising real `EquipmentComponent`/
`StatSheet`/`Item`/`Player`/`BrandRoller` calls (not just scene-load
checks) - 25/25 checks passed after the enum fix above. Full headless
regression sweep across `Hub`/`TestArena`/`PinnacleArena`/
`InventoryScreen`/`CraftingScreen`/`FateBoardEditor` came back clean.

---

## 2026-09-01 — Comment Trim, Navigable Fate Board, Clean Slate Shapes

**Comment verbosity.** User: "I need you to work on not over-commenting a
lot. Theres a LOT of line bloat from comments about how I've asked you to
do this for a certain thing." Going forward, code comments explain what
something does and how it works, not "user asked for X on date Y" - that
history belongs here, not in the source.

**Fate Board made large and navigable.** User: "Make the Fate Board large
and navigable. Make it so that you can hold LMB to move it around and
look around the board. And utilize RMB to 'drop' a slate from the held
item so you aren't holding it for too long." `FateBoardGrid.GRID_SIZE`
went from 32 to 150 (`ANCHOR_CELL` recentered to (75, 75) to match), and
its `_gui_input()` gained click-vs-drag disambiguation: an LMB press
records its start position, and if a subsequent motion event (with the
left button in its `button_mask`) moves past a 6px threshold, the grid
switches into panning the parent `ScrollContainer`'s scroll offset
directly instead of ever firing `cell_clicked` on release. RMB drops the
currently-held Slate (`drop_requested` signal, new) when one is pending,
or falls back to its old remove-at-cell behavior when nothing is held.

**Clean Slate shapes.** User: "any make it a clean shape for self
contained slates, but show the walls for separate slates. As in if I put
in one slate, its one solid shape instead of 7 squares in a shape."
`_draw_walls()` now only draws a grid line on a cell edge when the two
cells it separates belong to different placements (or one side is
empty) - two cells from the same placed Slate read as one solid shape
with no internal lines.

Verified with a scratch scene-load test (`FateBoardGrid._gui_input()`
called directly with synthetic `InputEventMouseButton`/`InputEventMouseMotion`
objects) - caught two real GDScript gotchas along the way, both in the
test harness rather than the actual code: lambda closures
(`func(): flag = true`) capture local variables **by value**, not by
reference, so a plain bool local never reflected a signal firing inside
one - fixed by capturing a single-element array instead, which is a
reference type. And an initial drag-pan check dragged in the direction
that would push `scroll_horizontal` negative from its starting 0, which
correctly clamps back to 0 and looked like a no-op - fixed by dragging
the other way, which has room to move. All 7 checks pass; full headless
regression sweep across `FateBoardEditor.tscn`, `Hub.tscn`,
`TestArena.tscn`, and `PinnacleArena.tscn` came back clean.

---

## 2026-08-31 (even newer) — Damage-Trail Tween on Health Bars, Cleaner Boss Fill

User: "tween with damage on the health bars, with the damaged portions
being a lighter color" + "for the boss health bar... let's make the fill
more clean." Both bars gained the classic WoW-style health bar behavior:
the main fill drops instantly to the new (lower) value, while a wider,
lighter "trailing" sliver stays behind at the OLD value and drains down
to catch up over 0.45s - a heal snaps both together instead, since
there's no damage to trail behind. `EnemyHealthBar` draws it as a second,
wider rect underneath the main fill; `BossHealthBar` feeds a second
`trailing_fraction` shader uniform. The boss bar's fill also dropped its
blocky hash-noise "vein" texture (the actual "not clean" culprit) for a
smooth vertical gradient - kept the pulsing glow at the fill edge, which
read as a good "menacing" touch rather than noise.

**A real, if inconclusive, bug hunt along the way:** the first
implementation used a `Tween`/`tween_method()` for the drain animation
(matching this project's existing XP-bar-fill pattern in `PlayerHUD.gd`).
It silently never worked - the tween was created successfully, reported
`is_valid() == true`, the `MethodTweener` came back non-null, yet its
callback never fired even once across 400 headless frames, confirmed
with a debug print. A minimal isolated diagnostic (a bare `Node`
creating a tween in its own `_ready()`) worked perfectly in the same
environment, so the issue was somehow specific to creating the tween
inside a method call on a dynamically-instantiated `Control` rather than
a scene-tree-rooted `Node`'s own `_ready()` - never fully root-caused.
Not chased further because the fix was simpler than the investigation
would have been: `_process(delta)`-driven linear interpolation, which is
already this exact file set's own established pattern (`HitMarker.gd`
right next to these two uses a timer in `_process()`, not a Tween).
Verified with a scratch test - flagged one real timing-measurement
lesson in the process: `SceneTreeTimer` waits and `_process(delta)`
accumulation are both real-wall-clock-based and agree with each other
given enough real elapsed time, but a short wait (0.5s) checked
immediately on resume can read a still-mid-flight interpolation as
"stuck" when it's actually just not finished yet - not a bug, just too
tight a margin between two independently-real-time-based waits. Confirmed
by widening the wait to 2s: the trail reached its exact target.

---

## 2026-08-31 (newest) — 8-State Hit Markers, Enemy Health Bars, Boss Bar

**Hit marker redesign**, per a user reference image laying out the full
state matrix (the old marker only had 3 states: white/gold/nothing).
Color now encodes WHERE a non-kill hit landed (white = normal body, gold
= weakpoint) - but a KILL is always red regardless of where, so red needs
its own sub-encoding: a small perpendicular tick on each arm marks a roll
crit (used by all 3 colors), and a wider gap right at the center marks a
weakpoint (only shown on kills - white/gold already carry "weakpoint" via
color for non-kills, so a non-kill weakpoint hit doesn't also need the
gap). 8 total distinct glyphs, matching the reference image's own count
exactly (2 white + 2 gold + 4 red). `EventBus.hit_landed` grew from one
bool to three (`is_critical`, `is_critical_spot`, `is_kill`) - `is_kill`
is computed at each real hit-resolution call site (`PlayerMeleeAttack.
_deal_damage()`, its own Riposte branch, `Projectile._hit_enemy()`) by
checking `target.health.is_alive()` immediately after `take_damage()`,
since `HealthComponent.apply_damage()` updates `current_health`
synchronously before returning - no separate "was this the killing blow"
tracking needed.

**Enemy health bars.** New `EnemyHealthBar.gd` - a floating world-
projected bar + name label, shown per enemy when either the crosshair is
aimed at them (a camera-forward raycast, same pattern `PlayerAbilityCast.
_get_ground_target_point()` already uses) or they're "in combat"
(`Enemy.is_in_combat()`, new: within `chase_range` of the player - the
same distance the chase state machine already gates on, so "losing track
of me" is just leaving that range, no separate concept invented - OR has
taken damage in the last 5 seconds). Positioned every frame via
`Camera3D.unproject_position()`, hidden via `is_position_behind()` -
matches this project's established `_draw()`-based HUD convention
(StatOrb/Crosshair/HitMarker) rather than a Label3D/SubViewport approach.
Enemies never had a display name before this - `Enemy.display_name`
(archetype subclasses set a readable string: "Glass Cannon"/"Mobile
Bruiser"/"Heavy Hitter"/"Arator the Redeemer", falling back to the node's
own Godot name if never set) plus `get_display_name()`.

**Boss health bar.** Fixed top-center, wider, its own animated
`canvas_item` shader (same technique `StatOrb.gd` established earlier
this session) - a marbled/veined dark-red fill with a pulsing glow right
at the fill edge, instead of `EnemyHealthBar`'s plain rect fill, since
"stylized and menacing" is explicitly a visual-quality ask. Triggered by
`Enemy.rank == Constants.EnemyRank.BOSS` - the only boss-tier concept
that exists in this project (added 2026-08-30 for loot-level gating);
"Pinnacle boss" and "uber boss" both read as that same rank for now, this
project has nothing that distinguishes them from each other yet. Caught
and fixed a real, previously-unnoticed bug while wiring this up:
`FigmentBoss` (the one existing boss encounter, in the Figment Vault)
never actually set `rank = BOSS` - it was silently getting a RANDOMLY
ROLLED rank (Normal/Magic/Rare) like any other enemy ever since the rank
system was added, meaning its loot was never actually dropping at the
correct +5-level boss tier either. Fixed by setting `rank = 3` directly
in `FigmentBoss.tscn` (before `_ready()` runs, same mechanism every other
boss-flagged scene is meant to use) - a real correctness fix that had
nothing to do with the health bar feature itself, just surfaced by
building something that finally reads `rank` in a way where the bug was
visible.

All verified with a scratch test (7/7): display names resolve correctly,
a fresh enemy starts out of combat, `take_damage()` marks it in-combat,
the 5-second grace window correctly decays back out, `FigmentBoss` is now
correctly BOSS-ranked with its name, and both bar classes compute/accept
values without error. Visual confirmation of the on-screen appearance
was NOT completed this pass - two attempts to screenshot the running game
both failed to actually bring its window to the foreground (the first
attempt accidentally captured this session's own chat window instead,
deleted immediately without further action; the second confirmed via an
explicit title check beforehand that focus had landed on an unrelated
Chrome window instead, so no screenshot was taken at all that time). The
underlying logic is verified, the pixels aren't - worth a real playtest.

---

## 2026-08-31 (later) — Implementation Brief v3.4: Crosshair, Critical Spots, Dual Weapon Sets, Stance Behaviors

Second brief in a row with real mismatches against the actual codebase -
same lesson as v3.3 (see README gap #34), applied again: researched
before writing anything, found several concrete inaccuracies, presented
them plainly, and got direction on the two that were genuine forks
(weapon-swap scope, Conduit routing) rather than guessing.

**What didn't match reality:** `ui/hud/HUD.tscn` doesn't exist (real path:
`ui/player_hud/`). `DamageCalculator` has no `target`/`hit_position`
concept - it's a stateless formula utility; real hit resolution (and the
actual `target` reference) lives in `PlayerMeleeAttack._deal_damage()`/
`Projectile._hit_enemy()`. No `hit_position` exists anywhere - melee and
ranged hits are both plain Area3D body-overlap checks, not raycasts.
Enemies are unshaped placeholder capsules with no bones/skeleton.
"Shortbow"/"Longbow" don't exist in this project's weapon catalog at all
(all-firearms-plus-Wand/Staff setting). No "weapon swap" feature or
`weapon_swap` input action existed despite the brief calling it
"existing." Section 7 re-introduced the dedicated Conduit-slot design the
user explicitly rejected earlier this session ("Conduits are not a slot").

**Crosshair + Hit Markers** (Sections 1-2): static always-on cross
(`Crosshair.gd`) and a 3-state hit marker (`HitMarker.gd`, white/gold/
nothing) built into `PlayerHUD.gd` at the real path. `EventBus.hit_landed`
is emitted from the actual hit-resolution call sites instead of
`DamageCalculator` (which can't see a target at all) - `PlayerMeleeAttack.
_deal_damage()` for melee (including Riposte, always gold) and
`Projectile._hit_enemy()` for ranged (player-sourced shots only).

**Critical Spot System** (Section 3): adapted from the brief's
`hit_position`-based check to an area-overlap one that actually fits this
project - each `Enemy.tscn` gained a `HeadZone` Area3D (small sphere near
the capsule's top), and `Enemy.is_critical_spot_hit(attacking_area)`
checks whether the attacking hitbox/projectile is ALSO currently
overlapping it. +25% damage, gold hit marker, same as a normal crit.
Verified directly with a real `Area3D` probe positioned at the HeadZone
(detected) and 50 units away (not detected).

**Dual Weapon Sets + Tap/Hold X** (Section 4, user-expanded well beyond
the brief's own ask): the brief assumed weapon-swap-on-tap already
existed; it didn't, so this became real new functionality - "Let players
have 2 sets of a main hand/off hand weapon... properly show which set is
worn in the inventory screen." `EquipmentComponent.primary_weapon`/
`sidearm_weapon`/`offhand` are now COMPUTED properties (get/set) over new
`Array[Weapon]`/`Array[Shield]` backing fields of size 2, indexed by
`active_weapon_set` - every existing caller (`get_active_weapon()`,
`get_total_armor()`, `compute_ward_bonus()`, stat aggregation, visuals)
kept working completely unchanged, since they were always just reading/
writing "the field," which now transparently routes to whichever set is
active. `equip()`/`unequip()`/`get_equipped()` gained an optional
`weapon_set` param for targeting a specific set explicitly (InventoryScreen's
new toggle button, and restoring a save's own two sets by index).
`GameState.weapon_set_refs`/`active_weapon_set` persist both sets
separately from the general `equipment_refs` (which now excludes weapon
slots entirely - a flat "everything active" list can't represent an
INACTIVE set's own items). Bound a real `weapon_swap` input action to X
(wasn't in the Input Map before this). Tap swaps the active set; holding
past 0.25s instead toggles the stance PAGE (Section 4's OTHER ask,
`WeaponStance.toggle_stance_page()`, named that instead of the brief's
own `toggle_stance()` since this file already overloads "stance" for the
RMB-hold concept). InventoryScreen shows "Weapon Set: A/B (worn)" next to
the existing paper-doll, which needed zero changes itself - it was always
reading through `get_equipped()`, which now automatically reflects
whichever set is active. Verified: two sets independently hold different
weapons, the getter correctly follows the active index both directions,
`get_all_equipped_refs()` no longer leaks weapon-slot items, and
`get_weapon_set_refs()` returns the right ref per set.

**Ranged/Melee Stance Behaviors** (Sections 5-6): `StanceBehavior` split
into `RangedStanceBehavior`/`MeleeStanceBehavior` subclasses (each adding
its own descriptive `stance_type` enum - not redeclaring
`move_speed_multiplier` in the subclass despite the brief's own snippet
doing so, since GDScript doesn't support a subclass re-declaring a
parent's exported var). Melee: 9 real weapon types x 2 pages = 18 new
`.tres` files, each weapon's page keyed by `weapon_type`/`weapon_type +
"_b"` - `WeaponStance._resolve_behavior()` now takes the whole Weapon and
checks the page-B key first. Ranged: the brief asks for one `.tres` per
weapon LINE (not per bare type) - a single `weapon_type` dictionary key
can't hold more than one behavior, so ranged instances store their real
`base_line_id` (Section 25's own line identifier) in the inherited
`weapon_type` field instead, and resolution tries the equipped weapon's
own `base_line_id` before falling back to its plain type name. A small
generator (`tools/generate_ranged_stances.gd`, same one-shot-tool
convention as Section 25's own generator) scanned every real generated
ranged weapon and produced 26 real per-line `.tres` files (Shortbow/
Longbow's 2 dual-stance types skipped - they don't exist). Only Rapier
(already real since v3.3, plus a new PARRY_READY page B at 2.0x window)
and Cutlass's Water Slices got real behavioral logic, per the brief's own
scope limit - Water Slices deals 40% of the hit's own damage again as a
separate Cold instance while that stance page is active (exact formula
the brief gave, `EventBus.damage_applied` doesn't exist in this project
so reused the existing `damage_dealt` signal instead). Dagger's STEALTH
page is data-only (no enemy-detection-radius hook exists to build a real
stealth effect against, and the brief gave no formula for it unlike Water
Slices) - flagged as a real gap, not silently dropped.

**Section 7 (Caster page 2)**, per user direction ("route by weapon_type
instead"): the toggle architecture (`active_page`, `toggle_stance_page()`,
page-aware `_resolve_behavior()`) is generic enough to cover this without
any Conduit-specific code at all - a future caster weapon's page-B
`StanceBehavior` would just be authored as `"<WeaponType>_b"`, resolved
by the same mechanism every melee weapon's page B already uses. No
Conduit-slot/offhand-spell-page code was written, matching both the
user's routing direction and the brief's own "spell page content is
deferred" scope.

All verified with a scratch test isolated from the real save file (11/11
checks) plus a direct `Area3D` probe test for critical-spot overlap (2/2).
One screenshot mid-verification accidentally captured this session's own
chat window instead of the game (a foreground-focus mixup, not a game
bug) - deleted immediately without further action, and visual
confirmation of the crosshair/stance indicator's on-screen appearance was
left incomplete as a result; the underlying logic is verified, the pixels
weren't.

---

## 2026-08-31 — Implementation Brief v3.3: Damage Formula, Jab/Thrust/Charged Merge

User provided a written design document ("Implementation Brief v3.3") with
explicit "Files to Create/Modify/Leave Alone" lists. Before touching
anything, checked the brief against the actual codebase - it describes
`WeaponStance` and `PlayerMeleeAttack` as new/stub components to create at
new paths (`entities/player/`), but both already exist, more developed
than the brief assumes: `systems/combat/WeaponStance.gd` already has
right-click stance, arm-pose integration, and ranged FOV zoom;
`systems/combat/PlayerMeleeAttack.gd` already has a real Windup/Strike/
Recovery state machine, per-weapon motion values/durations/intensities,
and a combo-pose system the brief's own "DO NOT: add combo systems" line
directly contradicts. Creating the brief's files at its literal paths
would have hit a hard Godot conflict (two scripts both declaring
`class_name WeaponStance`) and silently deleted real, screenshot-verified
work from earlier passes. Asked the user how to reconcile it rather than
picking a side - answer: merge the brief's new ideas into the EXISTING
files, preserve arm-pose integration and per-weapon motion value
architecture, but DO replace the combo-index cycling with the brief's
literal 3-attack model (no attack chains).

**Damage formula - BREAKING CHANGE, done exactly as specified.** Old
formula multiplied a stat-scaled term into base_weapon_damage
(`base_weapon_damage x motion_value x (stat_value x grade_scale x (1 +
mastery)) x increased x more`), producing damage in the thousands at
level 1. New formula is additive: `Attack Power = base_weapon_damage +
(stat_value x grade_multiplier)`, `Spell Power` is the same formula with
`base_weapon_damage = 0`. `Constants.SCALING_RANGES` renamed to
`GRADE_MULTIPLIER_RANGES` with entirely new value ranges (S: 1.5-2.0 ->
3.0-4.0, etc. - a different unit, not a tuning pass). One fix beyond the
brief's own listed files: `Ability._base_hit()` used to pass `1.0` as
`base_weapon_damage` (a multiplicative-identity placeholder under the old
formula, since a spell has no weapon) - under the new ADDITIVE formula
that would silently add +1 flat damage to every spell hit, so it now
passes `0.0`. Verified via scratch test: a Grade C weapon with 10
Strength now deals ~18.7 damage (sane), not thousands; Ice Pulse at 0
Arcane deals exactly 0 (no leftover flat base).

**Jab / standard thrust / charged thrust**, merged into the existing
`PlayerMeleeAttack.gd`/`Player.gd` rather than replacing them:
`Player._handle_attack_input()` tracks LMB hold time for melee weapons
outside stance - release under 0.6s fires `try_light_jab()` (motion value
x0.6), release at or past 0.6s fires `try_standard_thrust()` (x1.0, the
same power/timing every attack already had before this brief - this
"replaces" the old single attack in name only). Charged thrust (stance +
LMB press, x1.8) is a rename of the pre-existing `try_special_attack()`,
unchanged mechanically. All three multipliers apply on TOP of the
existing per-weapon `WEAPON_TYPE_MOTION_VALUE` base (user direction -
preserve that architecture) rather than replacing it, matching how the
1.8x charged multiplier already worked before this brief. The old
`_combo_index`-cycling `WEAPON_TYPE_COMBO_POSES` (repeated presses
rotating through a weapon's pose list) is gone, per user direction to
honor the brief's "no combo systems" line - each weapon's former 2-pose
list is repurposed as a FIXED per-attack-type pose instead (`WEAPON_TYPE_
JAB_POSE`/`WEAPON_TYPE_THRUST_POSE`, index 0/1 of the old list), so the
per-weapon pose variety already authored survives, it just no longer
cycles over time.

**StanceBehavior resource** (`data/stance/StanceBehavior.gd`, brand new,
matches the brief exactly) - `move_speed_multiplier`/`parry_window_
multiplier`/an unused `stance_animation` slot, resolved by the active
weapon's `weapon_type` from a dir-scanned `data/stance/instances/`
(same convention `PlayerAbilityCast`/`TomeRoller` already use). Only
`rapier_stance.tres` exists (0.8 move speed, 1.5x parry window), per the
brief's own explicit scope - every other weapon type falls back to
`WeaponStance`'s hardcoded 0.75 default. Wired into `Player._effective_
speed()` (new multiplier source) and `ParryRiposteHandler.start_parry_
window()` (window duration only - damage/Ward restore/Composure damage
from a parry are unaffected, per the brief's own scope note).

**Explicitly skipped: Section 6 (ArmRig placeholder animation methods).**
The brief frames arm rig animation as unbuilt ("invisible - architecture
only, no visible output yet") and asks for no-op `play_attack()`/
`play_stance_enter()`/`play_stance_exit()` stubs. `PlayerArmRig.gd`
already has real, working, screenshot-verified procedural animation
(`play_attack_swing()`, `enter_ready_pose()`, `exit_ready_pose()`, a full
3-bone shoulder/elbow/wrist chain) built over several earlier passes -
adding no-op stubs with different names would just be dead code shadowing
better functionality that already exists. Left `PlayerArmRig.gd`
untouched.

`melee_attack_executed` signal added to `EventBus.gd` per the brief's own
file list, emitted from `PlayerMeleeAttack._deal_damage()` alongside (not
instead of) the existing `damage_dealt` - carries `motion_value` so a
future consumer can tell attack types apart, which `damage_dealt` alone
can't do. Not consumed anywhere yet.

Verified end to end with a scratch test (not just a headless load check):
damage formula sanity, Spell Power's zero-base fix, the Grade Multiplier
table's new values, `try_light_jab()`/`try_standard_thrust()` correctly
setting attack type, Rapier's `StanceBehavior` resolving on stance entry,
its 0.8 move-speed multiplier reading correctly, and its 1.5x parry
window multiplier correctly widening `0.25s -> 0.375s`. All 8 checks
passed clean.

---

## 2026-08-30 (newest) — Leveling Is Actually Hard Now, Aether Per Level

**XP curve steepened.** User: "experience requirement should increase the
more you level up. It shouldn't be so easy to level up I think." The
6%/level curve from the previous pass (chosen specifically to fix an
*unreachable* 25%/level curve) turned out to have overcorrected the other
way - technically climbable to level 100, but early levels felt trivial.
Follow-up gave an exact target instead of another guess: "Make level 99's
requirement 1 below the unsigned integer limit" - i.e.
`xp_to_next_level()` at level=99 (the last real threshold this system
ever computes; level 100 is `MAX_LEVEL`, no further one needed) should
equal `4294967295 - 1 = 4294967294` exactly. Solved algebraically
(`100 * growth^98 = 4294967294`) rather than picked by feel - works out
to `growth = 1.196430141231720`, ~19.64%/level. Precision mattered here:
a first pass at the constant (10 decimal digits) was accurate to only
~11 XP out of 4.3 billion at level 99 - close, but the 98th-power
amplifies any rounding error, so it failed a scratch test's exact-match
assertion. Recomputed at full double precision (15 digits) and it landed
dead-on.

**Aether now scales with level.** User: "You should also gain 2 points
of Aether for the Fate Board every time you level up. Start with 10 at
level 1." Replaced the previous flat `aether_capacity = 30` with
`FateBoard.capacity_for_level(level) = 10 + (level - 1) * 2`, kept in
sync by `Player._apply_saved_experience()` (initial sync, whatever level
a save restored at) and `_on_leveled_up()` (every level-up thereafter).
One real edge case caught before it shipped, same class of bug as the
equip-requirement one two passes ago: `Player._apply_saved_fate_board()`
restores a save's placed Slates via `FateBoard.place_slate()`, which
enforces the Aether budget - since capacity is now level-derived instead
of a flat 30, a save with placements that fit under the OLD flat budget
could fail to restore under a lower level-derived one. Gave `place_slate()`
a `bypass_budget` param, `true` only from that one restore call site -
same "a save always restores cleanly" principle as `EquipmentComponent.
equip()`'s own `bypass_requirements`.

Both verified with a scratch test isolated from the real local save file
(a fresh standalone `ExperienceComponent`/`FateBoard` pair, not the real
`Player.tscn`) specifically so the assertions weren't skewed by whatever
level that save happens to be sitting at - level 99's requirement matches
the target exactly, and `capacity_for_level()` / the level-up signal both
check out (10 -> 12 after one level-up).

---

## 2026-08-30 (latest) — Ward Was Actually Broken, Requirements, Orb Shaders

Four separate user reports/requests in one pass:

**"Let's not add all of the new high level items to the player's
inventory at the start."** `InventoryScreen._scan_owned_items()` has
always freely listed every file in `data/{armor,shields,weapons,items}/
instances/` as an "own one of each hand-authored base" testing
convenience - fine at ~14 files, not at the ~853 Section 25 added.
Filtered to `base_line_id == ""` (every pre-Section-25 hand-authored
single; every generated tier has a real one) so the debug catalog goes
back to its original small set. Same question came up for Slates
(`FateBoardEditor`'s palette had the identical always-available pattern
for its 11 hand-authored samples) - user confirmed after a re-ask (an
earlier answer was an accidental click while scrolling): gate Slates the
same way, real `GameState.owned_slates` only. Abilities turned out to
already be correctly earned-only (`GameState.owned_ability_ids` defaults
empty, `AbilitiesScreen` already filters against it) - checked, no change
needed there.

**Level + stat requirements.** Invented (no doc-sourced requirement
system exists). `Item.item_level` (already existed, drives loot-tier
selection) doubles as the level requirement - one number, one meaning,
not a separate field. Added `stat_requirement`/`stat_requirement_value`;
the generator assigns every weapon its own damage-type main stat
(mirroring `Constants.DAMAGE_TYPE_MAIN_STAT`) and every armor/shield
Vitality (invented "physical toughness" gate, armor has no damage type of
its own to key off), scaled at 0.5/level - reachable off 2 pieces of
`flat_<stat>` gear at Tier 1 rolls even at level 91. Throwables get no
stat requirement, just the level one. Enforced in `EquipmentComponent.
equip()` (same spot the existing two-handed-conflict check already lived,
reusing the existing `equip_failed` signal so `InventoryScreen`'s
"Can't equip: %s" line needed no changes). Regenerated all 853 items to
carry the new fields. One real edge case caught before it shipped:
`Player._apply_saved_loadout()` restoring a previous save hit this exact
gate immediately (the actual live save file had `gen_helmet_void_cowl.tres`
equipped - clearly obtained through the now-fixed inventory-catalog
exploit, since level 2 shouldn't be near a level-90-ish piece) - a save
should always restore cleanly, so `equip()` gained a `bypass_requirements`
param, `true` only from that one call site.

**"Ward is not actually being applied to the character anymore."** Real
regression, not a rarity issue. `EquipmentComponent.compute_flat_ward_bonus()`
only ever summed rolled `flat_ward` AFFIXES - it never read `Armor.
ward_value`/`Shield.ward_value` (the base stat field Section 25's
generator populates directly, matching how `get_total_armor()` already
sums `armor_value`). ~170 armor pieces went straight from generation to
having a real, prominent "Ward: 461"-style tooltip line that silently did
nothing on equip. Renamed to `compute_ward_bonus()` and made it sum both
the base `ward_value` across every equipped Armor/Shield slot AND any
rolled `flat_ward` affixes, additively. Verified with a scratch test
against the real save's own equipped gear (helmet + body armour) -
`compute_ward_bonus()` correctly summed both pieces' `ward_value` (342 +
846 = 1188), confirmed via a live screenshot showing "Ward 1325/1426" on
the HUD.

**Orb shaders.** "Make a shader for the Life orb, Mana orb, and Ward
shield on the life orb to make them look interesting" - `StatOrb.gd` was
pure `Control._draw()` (draw_circle/draw_colored_polygon/draw_rect,
explicitly "no-shader placeholder-art style" per its own prior header).
Replaced with a single `canvas_item` `ShaderMaterial` on a `ColorRect`
sized to exactly `radius*2` (so `UV` maps cleanly to the circle) -
animated wavy waterline (two overlaid sine waves, different frequency/
speed so it doesn't read as one mechanical oscillation), a liquid depth
gradient below the waterline, a bright surface-glow band right at the
waterline, a soft fresnel rim glow, and the border ring - for both the
main fill and the inset Ward strip independently. `fraction`/
`ward_fraction`/every color are shader uniforms updated from `set_value()`/
`set_ward_value()`, unchanged public API. Follow-up: "make the orbs a bit
larger... that part of the UI doesn't match the rest" - radius 46 -> 58,
`PlayerHUD.ORB_HEIGHT` and the label font size bumped to match.

**Two real bugs caught by screenshotting, not just reading the diff:**
(1) `##` GDScript-style doc-comments inside the shader code string don't
compile - GLSL/Godot Shading Language only has `//`. Fixed before ever
reaching the user, headless load caught it immediately. (2) The Ward
strip rendered pure white instead of its intended blue-violet tint on the
first screenshot - `PlayerHUD` sets `_life_orb.ward_color = WARD_COLOR`
*after* `_build_orb()` already returned (and therefore after `_ready()`
already ran and snapshotted the old default into the shader uniform once).
The old `_draw()`-based version never had this bug because `_draw()`
re-reads `self.ward_color` fresh on every redraw; a shader uniform is a
one-time push, not a live read. Fixed by turning `fill_color`/`bg_color`/
`border_color`/`ward_color` into real property setters that push to the
shader material on every assignment, not just at `_ready()` - a second
screenshot confirmed the correct color.

---

## 2026-08-30 (even later) — The First Pinnacle Boss Arena

User: "A Diablo 3 Belial style arena where its a crescent shape and the
boss stands in the center of the crescent. Build an invisible wall so
that players cannot fall off. Build the arena first, and then we'll
figure out how to get there. Feel free to use shaders to make it as
terrifying as possible." Scoped to exactly that - `levels/pinnacle_boss/
PinnacleArena.tscn` is the arena and nothing else; no boss logic, no
Player/enemy instances, nothing wiring it into the game's actual flow yet.

Built procedurally in `PinnacleArena.gd`'s `_ready()` (same convention
`GeneratedMap.gd` already uses for its own floor/wall geometry) rather
than hand-authored in the `.tscn`, since a crescent/lune shape isn't
expressible with this project's usual BoxShape3D-per-piece approach.
First real use of `CSGShape3D` in the project - a Boolean geometry op
that also generates matching collision via `use_collision`. Construction:
two same-radius circles (26m), one at the origin, one offset 9m along
+Z, subtracted - a small offset relative to the radius is what makes the
remaining sliver thin and uniformly curved rather than a fat D-shape with
one bite taken out. The invisible boundary wall (a separate `use_
collision=true, visible=false` CSG tree) traces the SAME two circles as
full 360° rings rather than just the crescent's own two arcs - the extra
wall length past the crescent's ends has no floor near it and is never in
the player's way, but a full ring is far simpler to build than tracing
the exact lune boundary.

**Two real bugs caught by actually looking, not just reading the code -
same lesson as the arm-rig animation saga earlier this session:**
(1) `CSGCylinder3D` defaults to 8-sided geometry - a first screenshot
showed the "crescent" as a sharp angular chevron/wedge, not a curve, on
every circle in the scene (floor and both wall rings). Fixed by setting
`sides = 64` on all six cylinders. (2) The first lighting pass was
technically "atmospheric" but genuinely unplayable-dark - a screenshot
from a normal eye-level angle showed almost nothing but a thin red sliver
at the very bottom of frame. Brightened ambient light energy (0.35 ->
0.9), directional light energy (0.5 -> 1.4), thinned the fog by ~4x, and
lightened the floor shader's unlit base stone color - "terrifying" needs
to read as contrast between dark stone and glowing cracks/embers, not a
scene so dim nothing is visible at all.

The floor's cracked-obsidian look is a hand-written `ShaderMaterial`
(voronoi-cell edge cracks, pulsing emissive glow) rather than a texture
asset - no matching texture exists, and a shader keeps it fully self-
contained. Also added dim red ambient/fog, a warm-red directional light,
an ember glow point light near the boss spot, and a `GPUParticles3D`
ember drift for atmosphere.

**Verification, actually done, not assumed:** the crescent shape was
confirmed via a real top-down screenshot (windowed launch + window-
cropped screen capture, this project's established procedure) before and
after the `sides` fix - the difference between the two is stark. The
invisible wall was verified FUNCTIONALLY, not just visually - a scratch
physics test spawned a `CharacterBody3D` near each edge (outer rim and
inner cutout) and drove it outward with `move_and_slide()` for 120
physics frames each; both stopped at the wall's actual radius rather than
crossing into the void. First attempt at the inner-cutout test reported a
false FAIL - the rig's start position was miscalculated and it began
already inside the removed cutout region with no floor under it at all
(not a wall bug, a test-setup bug); fixed the start z and both tests pass
clean.

`BossSpawnPoint`/`PlayerSpawnPoint` are just `Marker3D`s for a future pass
to read - no boss encounter, no way to reach this arena from the game's
normal flow yet, exactly as scoped.

---

## 2026-08-30 (later) — Cooldown Cap, Two New Spells, Level 100, and the Real Section 25 Item System

Several independent requests bundled into one pass:

**Cooldown Reduction cap.** No CDR stat existed before this - Instinct's
Action/Cast Speed and Ability.rank's own -4%/rank were the only cooldown
levers, and nothing capped their combination. Added `Constants.
MAX_COOLDOWN_REDUCTION = 0.75` and `Ability.get_final_cooldown()`, which
clamps the combined reduction so a cooldown can never drop below 25% of
its authored value. `PlayerAbilityCast` now calls this instead of dividing
raw.

**Ability cooldown tuning.** Ice Pulse 2.5s -> 1.5s, Static Discharge 2.0s
-> 1.5s, Thunder Javelin 2.0s -> 5.0s (user-specified exact values, not a
blanket "spammable" pass).

**Two new spells.** Spark (Lightning): 3 ground-crawling projectiles
(`SparkCrawler.gd`) that re-target the nearest enemy every frame and can
re-hit the same target every 0.15s (no lock-on, no per-target hit cap
otherwise). Tornado (Physical/Kinetic): a `TornadoField` that seeks the
nearest enemy within 14m (falling back to a slower random wander only when
nothing's in range - user follow-up: "it wants to go up into enemies and
not just wander randomly"), capped at 3 concurrent instances via a
`tornado_field` group count check in `PlayerAbilityCast._try_cast()`.

**Level cap 100.** The XP curve's growth rate was the real problem, not
just the missing cap - 25%/level compounded to ~10^11 XP by level 100.
Changed to 6%/level (genre-standard) and added `MAX_LEVEL = 100`;
`PlayerHUD` shows "MAX LEVEL" with a full bar once reached instead of an
XP fraction that would otherwise sit frozen at a huge denominator.

**The real Section 25 item system.** This was the big one. User asked for
more weapon/armor base types "as detailed" - reading the actual doc
(Section 25) revealed it's not a short list, it's a full tiered catalog:
27 weapon types, 4 armor slots, 8 shield lines, 5 throwable lines, each
split into 2-4 "Lines" of 2-10 named tiers apiece (~750+ individual items
with real names/levels/damage-armor ranges). A prior session had already
read this and explicitly deferred it (README gap #18) as too large for
that pass. Asked the user directly whether to keep doing one representative
item per type (today's existing pattern), build the full system, or skip
it - they chose the full system, plus their own formula for which tier a
kill should drop: "White mobs are the area level, blue mobs are the area
+1, rare mobs are the area +2 levels, bosses are the area +5 levels."

Built `tools/generate_base_types.gd` - a headless one-shot generator (kept
in the repo as a real tool, not scratch) that parses the design doc's own
extracted Section 25 text and writes one `.tres` per tier directly into
`data/weapons|armor|shields/instances/` and `data/items/instances/`
(throwables). Parsing challenge: the doc's Word tables come through as one
cell's text per line with no delimiters and inconsistent column counts per
line (weapons are Tier/Name/Level/Base Damage; some armor/shield lines add
a second Armor/Evasion/Ward column, or Block Chance/Threshold) - solved
generically by recording whichever run of known column-label lines follows
each "Line N —" header, then reading that many lines per row until a line
isn't a valid Tier integer. Ran clean on the first real attempt after one
type-inference fix: **853 items generated, 0 skipped rows** (508 weapons,
171 armor, 99 shields, 75 throwables).

Added `Item.item_level`/`Item.base_line_id` so `ItemRoller._pick_base_item()`
can pick, per doc "Line", the single highest-item_level tier still at or
below a roll's target level - "always the current best base this level has
unlocked," the same ilvl-gated-base principle PoE-style tiered items
follow - then rolls uniformly among every line's current pick plus the
untagged pre-existing hand-authored singles. Added a lazy static
`_candidate_meta_cache` in `ItemRoller` after measuring the naive approach
(reloading and re-scanning ~850 files on every single roll) would have
been a real per-kill hitch - warm rolls now cost ~1.4ms each after a
~260ms one-time first-roll cost, verified via a scratch perf test.

Added `Constants.EnemyRank` (White/Blue/Rare/Boss, fully invented - no
doc-sourced enemy rank system exists) purely to give the new item_level
gating something to key off: `Enemy._compute_item_level()` = area level
(Map tier) + the killer's own rank offset, exactly the user's formula.
Regular enemies roll Normal/Magic/Rare at spawn off an invented 80/16/4
weight table; Boss is never auto-rolled, reserved for an explicit boss
encounter's own scene (see the Pinnacle boss work, next entry). Explicitly
scoped to item-level gating only - no stat scaling or visual tint by rank,
since nothing asked for that and Enemy's `_base_color` hook is already
spoken for.

Weapon type -> native_damage_type/is_two_handed/is_ranged has no doc
source (Section 25 never pairs them), so it's an invented-but-consistent
guess per type's real-world shape, documented in the generator's own
`WEAPON_TYPE_META` table. Also transcribed the doc's real "Base Crit
Chance by Weapon Type" table into `Constants.WEAPON_BASE_CRIT_CHANCE` for
all 27 types while reading that section (previously only 4 types were
filled in from earlier ad-hoc additions). Shield gained `evasion_value`/
`ward_value` fields (descriptive-only, matching Armor's existing
non-aggregated evasion_value/ward_value) so Buckler/Rune Shield/Warded
Barrier-style lines that lead with Evasion or Ward instead of Armor could
be represented at all.

**Bugs hit and fixed along the way** (same class both times - GDScript
can't infer a `:=` variable's type when either operand is untyped/Variant):
`Ability.get_final_cooldown()`'s `get_effective_cooldown() / max(...)`
(max() returns Variant) and `ItemRoller._build_candidate_meta_cache()`'s
`dir_path + file_name` (dir_path was an untyped loop var over a `const`
array literal) both needed an explicit `: float`/`: String` annotation to
compile - caught by the project's standard headless scene-load check
before ever reaching the user.

---

## 2026-08-30 (the actual last one) — The Windup Pose Was Invisible

User: "Yeah, its still the exact same for both of them? I'm not sure what
you've changed here honestly." Third report in this same saga, and the
one that finally found the real problem.

**Checked with a real side-by-side comparison this time, not another
round of math.** Screenshotted the actual windup and strike poses for
both Rapier (`DASH_THRUST`) and Gauntlet (`JAB`) after the previous
pass's fix (wrist-dominant vs elbow-dominant rotation, meant to give
each a different "which joint moves" signature). The strike poses
looked reasonable. **The windup poses were flat-out invisible in both
cases** - the weapon had swung completely off-screen. That's the actual
explanation for "still the exact same": the player never sees the
windup/retraction phase at all, only a snap-into-view at strike, which
looks identical regardless of what pose data drives it, because the part
that was supposed to look different was never on screen.

Root cause: concentrating most of the rotation onto a single bone (30
degrees on the hand for `DASH_THRUST`, 32 on the elbow for `JAB`) swings
that bone's whole downstream chain through a much wider arc than
spreading the same total rotation across multiple joints - a lesson the
previous pass's own forward-kinematics sweep had the data for (single-
axis 30-degree tests routinely produced 0.5+ unit position swings) but
the conclusion wasn't connected to "will this still be in frame" at the
time. Brought both back down to roughly the same total magnitude an
earlier, screenshot-confirmed-visible version had used, keeping the
wrist-vs-elbow dominance split (still different joints, just not enough
rotation on either to leave the frame).

**Also fixed while investigating**: `BoxMesh_blade` (the generic
placeholder both Rapier and Gauntlet fall back to - see the "Four New
Weapon Base Types" entry above for why neither has a real model) was a
nearly-square 8x8cm rod. A shape that symmetric barely shows any
silhouette change under rotation at all, which was very likely
compounding the "looks the same" problem on top of the invisible-windup
bug - flattened to an actual blade profile (16cm x 2.5cm cross-section)
so orientation changes are visually legible regardless of which pose is
driving them.

Verified: headless load clean; this time with real screenshots of both
weapons' windup poses confirmed genuinely visible and in distinctly
different on-screen positions from each other and from rest (not just
numeric deltas trusted on faith). Still not verified: the live in-motion
tween itself, same limitation as every pass in this saga - no practical
way to capture a moving mid-swing frame, so confidence here is "the two
endpoints are now both visible and different," not "the full animation
has been watched and confirmed to look right."

---

## 2026-08-30 (truly finally later) — Fixed DASH_THRUST/JAB: They Were Moving Backward

User report: "the rapier still just slashes upward, no twisting to point
at enemies and stab right now" - followed shortly by "It really seems
like none of the animations changed at all?"

**The second report was checked, not assumed.** A scratch probe dumped
every weapon's actual dispatched pose set, rotation values, intensity,
and duration side by side - Greatsword/Dagger/Rapier/Gauntlet all
resolved genuinely different data (`SWEEP_RIGHT`/`CLEAVE`/`DASH_THRUST`/
`JAB` respectively, with different numbers). The per-weapon dispatch
logic from the previous two passes was never broken. What actually
happened: `DASH_THRUST` (Rapier's entire moveset, half of Dagger's) and
`JAB` (Gauntlet's entire moveset) were both moving the weapon the wrong
way, badly enough that every weapon using them looked like the same
generic "swing up and back" regardless of the pose data being correctly
distinct underneath - explaining both reports as one root cause.

**Root cause, found by measurement, not by re-guessing the same way
twice.** A scratch probe compared the equipped weapon's actual camera-
local position before and after applying `DASH_THRUST`'s strike pose:
the origin moved to LESS negative Z (toward the camera) and sharply
positive Y (upward) - the pose was pulling the blade up and back, the
exact opposite of a thrust, and exactly what "slashes upward" describes.
A forward-kinematics sweep (every bone, every axis, +30/-30 degrees,
each measured the same way) mapped how this specific rig's geometry
actually responds to rotation - and turned up a deeper fact: `HAND_POS`
sits at the real measured weapon grip (already near this arm's full
natural reach - see that constant's own history), so essentially *no*
rotation pushes the hand further forward than rest. A thrust can't be
"reach past rest," because there's nowhere left to reach.

**The fix**: windup RETRACTS (pulls the arm back and up, away from the
target - verified ~0.68 units back, ~0.47 up), strike SNAPS BACK toward
rest (verified to land ~0.12 units *past* rest, i.e. slightly more
extended, not less). The felt "explosive thrust" comes from that
relative retract-then-release (~0.8 units forward + ~0.7 units downward
between windup and strike), not from ever exceeding rest's own reach by
much. Applied the same fix to `JAB` (Gauntlet's punch had the identical
X-axis-dominant assumption baked in, never separately verified). A first
attempt at fixing `DASH_THRUST` alone (Y-axis/yaw-dominant, twisting the
blade to face forward) was a real improvement over the original but
still imperfect on screenshot review - superseded by this retract-
release redesign once the deeper "REST is already near full reach" fact
was found.

Verified: headless load clean; screenshots of both the windup pose
(visibly retracted/tucked, distinct from rest) and the strike pose
(visibly back near the normal held position, using Dagger's real blade
model rather than Rapier/Gauntlet's placeholder box for a clearer read)
confirm the two ends of the motion are now genuinely different and in
the right relationship to each other. Not verified: the live in-between
tween motion itself (no practical way to capture a moving mid-swing
frame) - the numeric before/after measurements are what's actually
confirmed, not a full recording of the animation in motion.

---

## 2026-08-30 (finally later) — Per-Weapon Animation Variety, Gauntlet as a Conduit

Two user follow-ups on the new weapon base types: "the animations are all
the same for all of the weapons," and "I was also hoping gauntlet would
be a spell type conduit weapon as well." A third message mid-investigation
clarified the second: "Conduits are not a slot, they can be a primary or
offhand weapon just like the others" - ruling out
`EquipmentComponent.conduit`/`EquipmentSlot.CONDUIT` (a real but
completely unused field/slot pair) as the mechanism.

**Animation variety.** Root cause: the per-weapon-type dicts built for
Rapier/Bow/Staff/Gauntlet mostly reused existing pose sets wholesale -
Rapier/Dagger/Gauntlet all fell back to the same default 3-pose combo,
and ranged weapons (`PlayerRangedAttack.gd`) had no animation at ALL,
just an instant fire-and-cooldown. Three new pose sets in
`PlayerArmRig.gd`: `JAB` (elbow-extension-dominant, not shoulder-arc-
dominant like every sword pose - a punch actually straightens the arm,
it doesn't swing it around the shoulder), and `RECOIL`/`BOW_RELEASE` for
`PlayerRangedAttack._play_fire_animation()` (new - reuses
`PlayerArmRig.play_attack_swing()`, purely cosmetic, layered on top of
the unchanged instant-fire model, not gating or delaying the shot).
`WEAPON_TYPE_COMBO_POSES` now covers every melee type distinctly: Rapier
is a pure thruster (single-pose "combo," always `DASH_THRUST`, no
cycling - a rapier doesn't really slash), Dagger alternates slash/stab,
Gauntlet always `JAB`s. Gauntlet's special pose also changed from
`DASH_THRUST` to `JAB` (scaled bigger via the existing intensity/duration
multipliers) - a special should feel like a BIGGER version of a weapon's
own identity, not switch motion families entirely.

Caught mid-fix by a scratch test (asserting every weapon's combo pose
*list* is distinct, not just checking names): Staff had been silently
sharing Greatsword's exact `[SWEEP_RIGHT, SWEEP_LEFT]` pair from the
previous pass. Added a fourth new pose pair, `TWIRL_RIGHT`/`TWIRL_LEFT`
(wrist-rotation-dominant - a spin, not Greatsword's shoulder-driven heavy
cleave) so Staff has its own identity too.

**Gauntlet as a conduit.** Redesigned rather than mechanically extended -
no new code needed at all, because the systems already supported it:
`native_damage_type` changed from Kinetic to Aetheric (its punches
channel Esoteric energy now, not blunt physical), and its implicit affix
changed from `crit_chance_increased` to `flat_enigma` (+18) - Enigma is
Aetheric/Entropic/Pale's main stat (`Constants.DAMAGE_TYPE_MAIN_STAT`),
so this is internally coherent: the weapon's own damage type and its
stat bonus reinforce each other, the same way Greatsword's
`physical_dmg_increased` implicit already matches its own Kinetic type.
(First pass used `flat_arcane` - wrong stat, Arcane governs Elemental/
Fire-Cold-Lightning, not Aetheric; caught and fixed before finalizing by
actually checking `DAMAGE_TYPE_MAIN_STAT` instead of assuming.)
`EquipmentComponent.compute_stat_bonuses()` already sums `flat_<stat>`
affixes from `get_all_equipped_items()`, which already includes both
`primary_weapon` and `sidearm_weapon` - so Gauntlet functions as a
spell-boosting item regardless of which of the two weapon slots it's
equipped into, exactly matching "primary or offhand... just like the
others," entirely through the existing generic stat system. `equip_slot`
still targets `PRIMARY_WEAPON` only, same as every other weapon in the
project (nothing currently supports choosing which weapon slot an item
goes into) - the day that UI exists, Gauntlet works as a sidearm with
zero further changes needed, since the stat aggregation already doesn't
care which slot it's in.

Verified: headless load clean; a 6-check scratch test confirms all 5
melee weapons now have genuinely distinct combo pose lists, Gauntlet's
special is `JAB`, Gauntlet deals Aetheric damage, equipping it raises
Enigma by exactly 18, Bow/Pistol use different fire poses, and firing the
Bow now actually moves the (invisible) arm rig bones where it previously
did nothing at all.

---

## 2026-08-30 (still yet later) — Four New Weapon Base Types

User: "Lets do rapier, bow, staff, gauntlet if possible?" - following up
on a discussion about whether the project was blocked waiting for more
weapon models. It wasn't: `assets/models/pack1` (the purchased low-poly
pack already backing Greatsword/Dagger) has ~30 more unused models,
including a real Bow and Wizard Staff. Checked before writing anything -
**no Rapier or Gauntlet model exists in the pack** (confirmed via a full
directory listing, not assumed); both new weapons use the same tinted-
placeholder-box fallback Service Pistol already uses for the same reason,
rather than guessing a wrong-shaped stand-in model.

Four new `.tres` instances in `data/weapons/instances/` (`worn_rapier`,
`worn_bow`, `worn_staff`, `worn_gauntlet`) - no registration needed
beyond the file itself, since `ItemRoller.BASE_ITEM_DIRS` already scans
that whole directory dynamically for loot drops and Gear Shop stock
(verified: all 4 turned up across 1500 `ItemRoller.roll()` calls).
`Player.WEAPON_MODEL_SCENES` gained `"Bow"`/`"Staff"` entries (real FBX
models); `Constants.WEAPON_BASE_CRIT_CHANCE` gained `"Rapier": 0.08`/
`"Gauntlet": 0.06` (precision weapons); `PlayerMeleeAttack.gd`'s four
per-weapon-type dicts (motion value, swing duration/intensity, special
pose, combo pose) gained entries for the three melee ones (Bow is
ranged, never reaches that class) - this is exactly the extensibility
these dicts were built for back when only Greatsword/Dagger existed.

**Rapier finally gets its "real" mapping**: `WEAPON_TYPE_SPECIAL_POSE`
had `"Dagger": DASH_THRUST` as an explicitly-flagged stand-in ("a rapier
might dash and thrust in one direction" - no Rapier item existed yet).
Rapier now has its own entry alongside Dagger's (both keep it - a quick
dagger lunge is just as fitting, no need to take it away). Staff reuses
`BIG_SWEEP` (a staff sweep) and gets Greatsword's `[SWEEP_RIGHT,
SWEEP_LEFT]` combo-pose treatment (a twirling staff, not a diagonal
cut). Gauntlet also reuses `DASH_THRUST` - "draw back, extend straight
out" reads as a punch as well as a stab.

Tuning (fully invented, no doc source, same status as every other
per-weapon-type entry in this file): Rapier and Gauntlet are fast/light
(motion value 0.55/0.5, duration 0.65x/0.55x - Gauntlet is now the
fastest weapon in the game); Staff sits at baseline weight (motion value
1.0, duration 1.4x, a bit heavier than a one-handed weapon since it's
marked two-handed). Bow and Staff are both `is_two_handed = true`
(clears the shield/sidearm slot on equip, and - now that the arm mesh
itself is hidden - harmlessly builds an invisible off-hand IK chain same
as Greatsword). `WeaponStance` needed zero changes - it already branches
purely on `weapon.is_ranged`, so Bow automatically gets the aim-zoom
branch and the other three automatically get the GUARD-pose/special-
attack branch.

**Not done**: no new icon art - all 4 have empty `icon_path`, same
precedent as Service Pistol ("the icon pack is dark-fantasy with no
firearm art" - here, no rapier/gauntlet/bow/staff icons were verified to
exist either, and guessing a mismatched icon seemed worse than none).
`PlayerRangedAttack.gd` is still fully weapon-type-agnostic, so Bow
currently fires identically to the pistol mechanically (same cooldown,
same aim-bonus math) - just different visuals; a real
draw-and-release-feel for the bow would be its own follow-up.

Verified: headless load clean; a 27-check scratch test covering all 4
weapons' equip/dispatch/motion-value/special-pose/two-handed/stance-mode
behavior, plus loot-pool reachability, all passed; screenshots confirm
the Bow and Staff models render at a plausible size/orientation using the
existing (sword-tuned) weapon-model transform, not broken or absurdly
scaled.

---

## 2026-08-30 (latest) — XP Bar Fill Tween

User request: "When a player gains experience, we should tween between
the experience bar that they had to the experience that they end up at.
Just to show it filling up."

`PlayerHUD._on_xp_changed()` was setting `anchor_right` on the fill-clip
`Control` directly (instant snap) - now tweens it (0.5s, sine ease-out).
`ExperienceComponent.add_xp()` only emits `xp_changed` once per call even
if it crossed a level (it loops internally, firing after the loop) - a
level-up shows up here as `needed` having changed since the last call.
When that happens, the HUD fills the OLD bar the rest of the way to 1.0
first, snaps back to empty, then fills toward the new remainder - the
classic "level up" bar animation - rather than jumping straight to
whatever (probably smaller-looking) ratio the new level starts at. A
sentinel (`_xp_last_needed = -1.0`) keeps the very first update (HUD
just built, possibly from a loaded save already mid-level) an instant
snap rather than an animation from empty.

Verified with a 4-check scratch test: a normal gain doesn't snap
instantly and settles at the correct ratio, and a gain large enough to
force exactly one level-up visibly passes through a full (1.0) bar before
settling at the correct post-level-up ratio. (Headless test note: had to
poll by real elapsed time via `Time.get_ticks_msec()` rather than a fixed
process-frame count - headless mode runs frames uncapped, so a fixed
frame count doesn't correspond to a fixed amount of tween-relevant time.)

---

## 2026-08-30 (yet later) — Arm Mesh Disabled (Weapon-Only, For Now)

After the IK fix above, asked the user directly whether the visible arm
geometry was worth the trouble: it had been the single biggest source of
bugs/iteration all session (invisible mesh, wrong grip anchor, blending
into the floor, the stance pose swinging off-screen, the off-hand losing
the sword) relative to what it actually added, since the "weighty swing"
feel reads through the weapon's own arc/timing/hitstop, not through
rendering the arm. User agreed: "Yeah, lets do that then."

`PlayerArmRig.SHOW_ARM_MESH` (new, `false`) gates the `MeshInstance3D`
creation in `_build_arm()` - the Skeleton3D/bone chain, the weapon's
`BoneAttachment3D`, and the off-hand's 2-bone IK all still run exactly as
before (harmlessly, on now-invisible bones), so the swing itself,
per-weapon timing/pose-mix, stance, and two-handed off-hand tracking are
all unaffected - only the rendered arm/glove geometry is skipped. The
mesh-generation code (`_build_mesh()`, `_add_tapered_box()`, `_quad()`,
`_build_material()`) was left in place rather than deleted, given how
much tuning went into it - flip `SHOW_ARM_MESH` back to `true` to bring
it back later.

Verified: headless load clean; screenshot confirms the equipped weapon
(tested with Dagger) still renders and holds its position with no arm
geometry attached.

---

## 2026-08-30 (even later) — Two-Handed Second Arm, Sweep Variety, Weapon Stance

User follow-up on the arm rig work above: "Two handed weapons should
clearly need two hands, so see if you can add the second arm and also
feel free to sweep from side to side as well... I'm also hoping to add a
stance for melee weapons, holding right click puts you in a stance that
preps you for heavier or special attacks... This can also work for caster
weapons to do an innate ability... This will also work for ranged weapons
to aim their weapons."

**Investigated before writing anything** (right-click binding, existing
block/parry, weapon roster, `is_two_handed`, naming collisions): right
mouse button was completely unbound; Parry is a timed F-key press, not a
hold-to-block, so no conflict. `Weapon.is_two_handed` already exists and
is already enforced in `EquipmentComponent` (a two-handed primary clears
sidearm/offhand automatically) - no new equip-rule logic needed. Only
three weapon `.tres` instances exist in the whole project: Greatsword
(two-handed), Dagger, Service Pistol (ranged) - no Rapier, no caster
weapon of any kind. `StanceComponent.gd` already means something
unrelated (enemy poise/posture bar) - the new player-held mode is
`WeaponStance.gd`, deliberately a different name.

**Second arm** (`PlayerArmRig.gd`, `set_two_handed()`): the single-arm
rig was refactored to build N independent 3-bone chains (an inner `_Arm`
helper class) instead of one hardcoded skeleton. `Player._update_active_
weapon_visual()` calls `arm_rig.set_two_handed(weapon.is_two_handed)` on
every equip change. The off-hand arm has no weapon/hand-attachment of its
own - it reaches to a secondary grip point near the primary hand
(`OFFHAND_HAND_POS`) and plays whatever pose the primary arm is playing
(same rotation values, not mirrored - both hands move together on a real
two-handed grip). Screenshot-verified: both arms visibly converge on the
Greatsword's grip.

**Swing variety**: `PlayerArmRig` now holds 5 pose sets (`PoseSet` enum) -
the original diagonal `CLEAVE` plus two new horizontal `SWEEP_RIGHT`/
`SWEEP_LEFT` slashes. Normal attacks cycle through all three
(`NORMAL_COMBO_POSES`) each successive press instead of playing the same
cut every time. `play_attack_swing()` now blends from whatever pose is
*currently* applied rather than always starting from rest, so combo
attacks and stance-to-swing transitions don't visually snap.

**Weapon stance** (`WeaponStance.gd`, new component on Player, right
mouse via the new `stance` input action): holding right-click enters a
per-weapon mode. Melee holds a weapon-specific "ready" pose
(`PlayerArmRig.enter_ready_pose()` - the special's own windup pose, held
indefinitely instead of auto-returning); pressing Attack while active
calls `PlayerMeleeAttack.try_special_attack()` instead of a normal swing.
Two new pose sets exist just for specials: `BIG_SWEEP` (Greatsword - an
exaggerated version of the horizontal sweep) and `DASH_THRUST` (Dagger -
arm draws back then extends straight out). Specials deal 1.8x motion
value over 1.4x duration with a 1.25x bigger arc than a normal swing of
that weapon (`SPECIAL_MOTION_VALUE_MULTIPLIER`/`SPECIAL_DURATION_
MULTIPLIER`/`SPECIAL_INTENSITY_MULTIPLIER`). Dagger's special also calls
`Player.try_special_dash()`, a thin wrapper around the existing Shift-tap
Dash sharing its exact same cooldown/state (deliberately not a separate
free dash resource) - best-effort: the thrust still lands even if the
dash itself is on cooldown, just without the lunge. Ranged weapons get a
different `WeaponStance` branch entirely: no pose, just a camera FOV
tween down to 55° while held (`AIM_FOV`), and `PlayerRangedAttack.
try_attack(aimed)` now takes an `aimed` flag worth a flat 1.4x damage
multiplier when firing while zoomed - there's no spread/accuracy system
in this project to tighten instead, so this is a damage reward rather
than a real precision mechanic.

**Explicitly not built - no backing content exists yet**: a Rapier's
dash-and-thrust (mapped onto Dagger instead, as the closest existing
light one-handed weapon - `WEAPON_TYPE_SPECIAL_POSE` just needs a new
entry once a real Rapier item exists) and a caster weapon's innate
ability (no equippable item in this project identifies as a caster
weapon at all - spellcasting via `PlayerAbilityCast.gd` is entirely
independent of the weapon slot, and the `conduit` equipment slot exists
but nothing reads it - there's nothing for a `Mode.CASTER` branch to key
off yet).

Verified: headless scene loads clean throughout; an 11-check scratch test
covering off-hand-arm construction, combo cycling, stance pose changes,
and special-attack motion-value/duration/state-machine behavior all
passed; two real screenshots (Greatsword two-handed grip, Greatsword
stance ready pose) confirm both visually read as intended. Not
exhaustively screenshot-verified: the exact angles of `SWEEP_RIGHT`/
`SWEEP_LEFT`/`DASH_THRUST` and the off-hand grip's precise placement -
these are plausible numbers in the same spirit as the primary arm's own
first-pass placement, not confirmed correct the way the primary grip
connection and the two-handed convergence were. Both of the un-verified
pieces broke, per the very next user report - see below.

---

## 2026-08-30 (still later) — Stance Pose Bug, Slower Greatsword Sweeps

User report with a screen recording: "The first person animations still
don't feel right for great sword, slower side to side cleaves would look
good. And the stance does not put you in a proper stance, it makes the
sword and arms disappear to the sides. You should poise your sword ready
in that position attached" (a reference screenshot of a held-ready blade,
clearly on-screen and forward-facing).

**Root cause, found by re-deriving the math rather than guessing**:
`WeaponStance`'s melee branch was reusing the special attack's own
windup pose (`get_special_pose_set()`) at `get_special_intensity()` -
`_effective_swing_intensity()` (1.3 for Greatsword) times
`SPECIAL_INTENSITY_MULTIPLIER` (1.25) = 1.625x. Applied to `BIG_SWEEP`'s
windup shoulder yaw (70°), that's ~114° of shoulder rotation - well past
enough to swing the sword and arm out past the edge of the screen. This
exactly matches "makes the sword and arms disappear to the sides" and
was never screenshot-verified in the previous pass (flagged as such at
the time - see above).

**Fix**: stance and "the attack that stance preps" are no longer the same
pose. New `PlayerArmRig.PoseSet.GUARD` - a small, mostly rest-adjacent
raise (nothing like BIG_SWEEP's magnitude) - is what `WeaponStance` now
holds, always at intensity 1.0 (no per-weapon or special scaling at all),
so this class of bug can't recur regardless of how big a future special's
own pose gets. `BIG_SWEEP`'s own base angles were also independently
halved and `SPECIAL_INTENSITY_MULTIPLIER` lowered to 1.1, so the special
*attack* itself (not just the stance hold) stays framed too. Screenshot
confirms the sword now stays clearly on-screen, angled up and across the
body, while held.

**Greatsword normal swing**: two changes. `WEAPON_TYPE_SWING_DURATION_
MULT["Greatsword"]` raised again, 1.85x -> 2.4x - "still don't feel
right" even after the previous slowdown pass. More importantly, Greatsword
no longer mixes in the diagonal `CLEAVE` - alternating a vertical cut and
a horizontal sweep every other attack read as two unrelated motions
rather than one weapon's combo, not what "slower side to side cleaves"
was asking for. `WEAPON_TYPE_COMBO_POSES` (new, same minimal-table-plus-
DEFAULT convention as the rest of this file) lets Greatsword cycle only
`SWEEP_RIGHT`/`SWEEP_LEFT` while everything else keeps the full 3-pose
variety.

Verified: headless loads clean; the GUARD-pose fix screenshot-confirmed.
The Greatsword timing/pose-mix change was not re-verified with a live
recording (no practical way to time-capture a mid-swing frame reliably) -
if the "feel" still isn't right, that's the piece most likely to need
another pass.

**Same-turn follow-up**: "The issue is that the other hand lets go of the
sword, and that looks awkward." Root cause: the off-hand arm was applying
the exact same bone ROTATION values as the primary arm (see the previous
entry above), but the two arms have different shoulder positions and
different rest bone-chain shapes - identical rotations from different
rest poses swing the two hands along completely different arcs, so the
off-hand visibly drifted away from the weapon during any swing.

Replaced rotation-sharing with a real analytic 2-bone IK
(`PlayerArmRig._solve_offhand_ik()`, law-of-cosines shoulder/elbow solve)
that targets the PRIMARY hand's actual current position each frame (plus
a small static offset toward the grip's pommel side). First IK attempt
mirrored the off-hand's shoulder all the way across camera-center
(~1.5 units from the primary hand's own area) and was numerically
unreachable through most of a real swing (a scratch test measuring
hand-to-hand drift came back ~0.58 units off - caught before ever taking
a screenshot). Moved the off-hand shoulder to a modest "shoulder width"
step from the primary shoulder instead of a full mirror, which helped but
still wasn't enough reach on its own (peak required distance ~1.34 units
vs. ~0.93 max reach) - added `OFFHAND_TRACKING_DAMPING` (0.5) so the IK's
target only follows half of the primary hand's actual displacement from
rest, guaranteeing it stays within reach at the cost of not being a
perfectly rigid grip-lock. Re-verified numerically after each change
(final: hands stay within ~0.57 units of each other throughout a full
swing, down from as much as ~1.5+ before) rather than re-guessing by eye.

---

First piece of the deferred Dark Messiah-style animation engine pass, built
on the user's own go-ahead after reviewing a concept sketch. The Player
still has no imported skeleton/body asset, so this is entirely procedural:
`PlayerArmRig.gd` builds a low-poly arm mesh at runtime with `SurfaceTool`
(4 tapered-box segments - shoulder cuff, upper arm, forearm, hand/glove)
and a real 3-bone `Skeleton3D` chain (UpperArm -> Forearm -> Hand), rigidly
skinned (each segment bound 100% to one bone, no weight blending - matches
the faceted low-poly look rather than needing a real weight-painting pass).
The existing `WeaponMesh` (still authored in `Player.tscn`, still driven by
`Player._update_weapon_model()` exactly as before) reparents onto the Hand
bone's `BoneAttachment3D` at `_ready()` via `reparent(..., true)`, so its
resting position/rotation is unchanged - only its parent, and therefore its
behavior during a swing, changes.

`PlayerMeleeAttack._play_swing()` now calls `PlayerArmRig.play_attack_swing()`
instead of tweening the flat `WeaponSocket` node's rotation - three bones
move independently through invented windup/strike/recovery poses (shoulder
pulls back and up, elbow bends tighter, then snaps forward past neutral
with the elbow extending and a wrist flick), giving the swing real
anticipation and follow-through instead of one rigid rotation. Ranged
attacks are unaffected (`weapon_socket` itself no longer moves at all,
where it previously did during melee swings too, incidentally).

**Two real bugs caught by screenshot verification, not code reading** (see
`reference_windowed_screenshot_capture` memory) - headless scene loads and
a scratch bone-rotation test both passed cleanly the whole time, but the
rig was invisible in an actual windowed capture:
1. First attempt anchored the bone chain near the `WeaponSocket` origin
   instead of out at the weapon's actual authored position - the arm and
   the weapon ended up nearly a meter apart in depth, with the arm itself
   sitting close enough to the camera to be an off-frame sliver. Fixed by
   anchoring the Hand bone at the weapon mesh's own original local
   position and building the rest of the chain back from there.
2. A hand-built `Skin` resource (manually inverting each bone's rest
   transform for the bind pose) was replaced with `MeshInstance3D`'s
   built-in auto-generated skin (leave `skin` null, it derives bind poses
   from the skeleton's own rest pose) - the manual version's bind-pose
   transform convention was never actually verified against this engine
   version, and switching to the built-in generator removes the whole
   class of "inverted twice or not at all" bugs. This alone didn't fix
   visibility though - the real cause of "invisible" turned out to be
   unrelated (next line).
3. Not a bug exactly, but nearly shipped as one: the placeholder material
   was an unshaded muted brown that blended almost perfectly into
   TestArena's own brown floor/wall geometry - confirmed by temporarily
   swapping in loud magenta, which made the (correctly-shaped, correctly-
   positioned) mesh immediately obvious. Final material is a real lit
   steel-blue-gray so facet shading actually reads as faceted instead of
   flattening into one undifferentiated mass.

Idle sway/bob, the right-click stance/moveset system, kicks, and the sword/
dagger/cast-specific animations are all still deferred - this pass is only
the rig itself plus the melee swing wired onto it.

**Follow-up (same day): grip connection + greatsword weight.** User
screenshot showed the arm floating with zero visual connection to the
sword, and called the swing "far too fast along with the animation." Two
separate fixes:
1. The Hand bone had been anchored to `WeaponMesh`'s own (near-empty)
   pivot node, not the actual weapon model - `Player._update_weapon_model()`
   nests the real weapon scene under `WeaponMesh` with its own extra
   `Vector3(0.4, -0.4, 0.35)` offset for a "held" look, so the two were
   ~0.5 units apart. Measured the real grip position at runtime
   (`arm_rig.to_local(_weapon_model.global_transform.origin)`, a temporary
   debug print, removed once confirmed) instead of computing it by hand -
   two prior placements had both looked plausible on paper and were both
   wrong. `HAND_POS` now sits exactly at the measured grip, which also
   fixes the swing's rotation pivot landing at empty space instead of the
   weapon itself.
2. Swing timing/weight is now per-weapon-type
   (`WEAPON_TYPE_SWING_DURATION_MULT`, `WEAPON_TYPE_SWING_INTENSITY` in
   `PlayerMeleeAttack.gd`) instead of one fixed speed for every weapon -
   Greatsword now swings ~1.85x slower with a ~1.3x bigger arc (total
   swing ~0.9s, up from 0.37s flat before), Dagger stays quick (~0.75x
   duration, ~0.85x arc). The base (no-match) durations themselves were
   also raised - even a Dagger-less default felt too fast. `PlayerArmRig`'s
   pose choreography also changed: windup now ends with a brief held
   anticipation beat instead of flowing straight into the strike, and the
   strike eases in (slow start, fast finish - a heavy object overcoming
   its own inertia) instead of easing out (a flick).

A large combined pass. The user's own message bundled ~18 asks including a
full animation/stance/dash "engine" (Dark Messiah-style) - that piece was
explicitly scoped OUT of this pass by the user's own choice (recommended
option: "well-scoped items first, animation engine as its own pass"),
since the Player has no skeleton/body at all (just a weapon prop on the
camera) and building real movesets needs its own design conversation
first. Everything below is what shipped instead.

**Crafting: Brand over-consumption bug, two layers deep.** User report:
"I only have one of a brand but I can add it multiple times." The
palette's one button per Brand type was bound to a single representative
owned Resource - clicking it twice queued that SAME reference twice.
`CraftingSystem.MAX_SAME_BRAND` (2, doc-exact) allowed it with only 1
real copy owned, and even with 2 genuinely owned copies, consumption
(`GameState.owned_loot.erase(brand)` once per queued entry, reference-
equality) would only ever remove 1 real copy - the second `erase()` call
silently found nothing left to remove. Fixed at the root via a new
`_next_unqueued_owned_copy()` that queues genuinely distinct owned
objects instead of the same reference. Verified with a 7-check test
covering the 1-owned/2-owned/3-owned cases directly.

**Crafting: hover tooltips.** User: "Let me hover over Owned Items... and
Consumables... to see what I'm looking at." Neither the Owned Items rows
nor the Consumables row (a bare `Label`, no tooltip mechanism at all)
showed anything on hover before. Both (plus the Brands list, previously
just a flat `tooltip_text` string) now use `ItemSlotButton`, the same
rich `ItemCard` hover mechanism Inventory/Fate Board/Abilities already
share.

**Counter damage.** User: "If you melee attack an enemy while they are
mid attack animation, you deal Counter damage and deal 15% more damage."
New `EnemyMeleeAttack.is_attacking()`/`EnemyRangedAttack.is_attacking()`
(their own Telegraph-or-Strike / Windup states) checked in
`PlayerMeleeAttack._deal_damage()` before the Riposte branch - a real hit
during that window multiplies damage by 1.15 and fires a new
`EventBus.counter_hit` signal (logged in the debug overlay, same
convention `riposte_executed` already gets).

**Dash.** User: "Tapping shift and a direction should allow players to
dash in a direction." Reuses the `sprint` action (already bound to
Shift) rather than a new binding - `just_pressed` fires once on the
initial keydown regardless of hold duration, so a tap dashes and
continuing to hold still sprints normally afterward. A fixed-impulse
burst that decays, same shape as the existing Slide mechanic, on a 1s
cooldown.

**Movement speed reduced while melee attacking.** User request, exact
wording. `PlayerMeleeAttack.get_move_speed_multiplier()` (0.5x for the
whole Windup-through-Recovery window, not just the instant Strike) now
feeds `Player._effective_speed()` alongside the existing Instinct/status-
effect multipliers.

**Nine spell mechanic rewrites**, each replacing the generic instant-AoE-
at-cast-point every ability used until now with a real, distinct
mechanic per the user's own description of each:
- **Black Hole**: "shouldn't be a DoT, but deals Entropic damage every
  .25 seconds" - no more instant hit at cast, `BlackHoleField` now ticks
  real damage (fresh `roll_damage()` each tick, crit varies) every 0.25s
  to anything in its pull radius, including an enemy pulled all the way
  to the center (a `dist < 0.05` guard meant only to protect the pull
  math's normalize was accidentally also skipping damage there -
  caught by the test suite, fixed).
- **Caltrops**: now actually slows, via a new generic `"slow"` status
  effect (`StatusEffectComponent.gd`) independent of Cold's own Chill -
  reusing Chill for a Physical/Piercing effect would have been a
  thematic mismatch. Refreshed every damage tick while an enemy stands
  in the field.
- **Cinder Lance / Thunder Javelin**: "should throw a spear... at a
  crosshair, this should pierce" / "should work like Cinder Lance." Both
  now fire a real traveling `PiercingBolt` (new shared effect, doesn't
  `queue_free()` on its first hit like the ranged-weapon `Projectile.gd`
  does) aimed at the camera's forward direction. Thunder Javelin's own
  tuning was brought down to Cinder Lance's tier (was notably better on
  every axis - faster cooldown, better grade - despite being asked to
  "work like" it) rather than left to quietly outclass it.
- **Flame Jets**: "flamethrower type spell, slowing the character down
  and throwing flames at what the player is looking at." A new timed
  channel (`PlayerAbilityCast`'s own state, not a persistent scene) that
  re-aims at the camera's CURRENT forward direction every tick (not
  locked at cast time) and applies a 0.4x move-speed multiplier for the
  channel's duration, read by `Player._effective_speed()` the same way
  the melee attack-speed penalty above is.
- **Winter's Eye**: "throw out a sphere of ice that shoot a spiral of
  icicles at enemies around it" - a new `WintersEyeOrb` travels from the
  player toward the target point, ticking proximity damage+Chill to
  nearby enemies as it goes (the "icicles" are approximated as ticks
  rather than literal spawned sub-projectiles - flagged, a scope call
  given everything else in this pass), then detonates for a burst hit on
  arrival.
- **Thunder Sweep**: "fire out bolts of lightning along the floor
  originating from the player" - 8 `PiercingBolt`s spawned radiating
  outward in a full circle, flattened to the horizontal plane (a ground
  bolt shouldn't inherit camera pitch the way a crosshair-aimed one
  should). Cooldown raised slightly (3s -> 4s) since it can hit several
  enemies at once at each one's full damage, unlike the single-target
  spells sharing that same cooldown tier.
- **Flame Wall** (new spell, not doc-sourced - invented per the user's
  own description, no Section 26 entry exists for it): a ground-targeted
  wall, oriented perpendicular to the caster->target direction. Ignites
  on entry (once per pass, not per physics frame a stationary enemy sits
  in it) and separately ticks direct damage to anything currently inside.
- **Frost Armor retaliation** (user-reported bug: "Frost Armor doesn't
  properly deal cold retaliation damage to enemies when they melee
  attack the player"): it never had a retaliation mechanic at all before
  this, just the same generic instant AoE every other ability started
  with. Now a pure self-buff at cast (no AoE hit) - `EnemyMeleeAttack.
  _resolve_hit()` calls `PlayerAbilityCast.trigger_frost_armor_
  retaliation()` at the exact moment a melee strike lands on the player,
  dealing a real Cold hit + Chill back at the attacker, matching the
  doc's own wording exactly ("Enemies that strike in melee range trigger
  a Retaliation Damage burst of Cold damage. Applies Chill on
  retaliation hit.").

**Motion value review.** Applied per-weapon-type differentiation to the
melee system too, per the user's own request ("faster movesets... lower
motion value, while slower weapons like the greatsword will have a
higher motion value") - `PlayerMeleeAttack.WEAPON_TYPE_MOTION_VALUE`
(Dagger 0.65, Greatsword 1.35, same minimal-table-plus-DEFAULT convention
`Constants.WEAPON_BASE_CRIT_CHANCE` already uses). `StatSummaryBuilder.
gd`'s "Predicted Damage" preview was updated to read the same per-weapon
value - it explicitly promises to never drift from what a real swing
deals, so it had to follow this change too, not just `PlayerMeleeAttack.
gd` itself. Reviewed every ability's motion_value/scaling_grade/cooldown
together for internal consistency; adjusted Thunder Javelin (see above)
and Thunder Sweep's cooldown - the rest already read consistently with
the doc's own "low motion value = fast/chainable, high = slow/committed"
framing and were left alone.

Verified in stages throughout rather than all at once at the end - a
17-check combat test (dash/attack-speed/Counter damage) and a 22-check
spell test (one per new mechanic: no-instant-hit, periodic ticks, pierce-
through, retaliation, channel damage+slow, radiating bolt count, orb
travel, wall ignite+DoT), both including cleanup/regression checks for
the systems they touched. The spell test also caught two real test-
methodology bugs worth remembering: `Area3D.body_entered` only fires from
genuine engine physics steps (`await get_tree().physics_frame`), not from
manually calling `_physics_process()` in a loop - the proximity-check
effects (Black Hole/Caltrops) don't care since they scan
`get_nodes_in_group("enemy")` directly with no real collision query
involved, but `PiercingBolt` absolutely does.

## 2026-08-30 (later still) — Boss Animations: Stage 2 of the MDX Pipeline

User: "Let's work on animations for the first boss now" - the pipeline's
own README had this scoped as "not yet implemented" with the math worked
out but unwritten. Built it.

**Baking.** Each MDX Sequence becomes one glTF animation
(`tools/mdx_pipeline/mdx_to_gltf.js`'s `buildAnimations()`). Every
animated node's per-frame LOCAL matrix (`Translate(pivot)*Translate(T)*
Rotate(R)*Scale(S)*Translate(-pivot)` - the same formula confirmed
against `war3-model`'s `updateNode()` in the Stage 1 entry above) is
sampled at a fixed 30Hz across the Sequence's frame interval and
decomposed into T/R/S. Used `gl-matrix` for the composition/decomposition
math rather than hand-rolling it - it's already a `war3-model` transitive
dependency, and its `mat4.fromRotationTranslationScaleOrigin` is the
literal same function `war3-model`'s own renderer calls, which removed a
lot of the risk a hand-rolled version would have carried.
`GlobalSeqId`-scoped channels (independent looping tracks - idle
blinking, cloth sway) are scoped out, same "no real spec need
established" reasoning as other simplifications in this pipeline.

**Caught and fixed a real bug in the same pass**: `usableAnimVector()`'s
first draft had an operator-precedence bug (`a && b && c && d === null ||
e === undefined ? f : null` - `&&` binds tighter than `||`, so this
didn't parse as intended and would throw on any node missing a channel
entirely, i.e. most of them). Fixed before ever running it, by writing it
as plain sequential `if` returns instead of a single dense expression.

**Wired into the boss's actual combat state machine**
(`FigmentBoss.gd`), not just exported and left inert: idle/walk selection
off `Enemy`'s own chase velocity (extracted into a new
`_update_animation_state()`, split out from `_physics_process()`
specifically so it's testable without a real Player in the scene for
`Enemy._update_chase()` to steer against), `Attack 1` on
`begin_attack_telegraph()` (layered alongside the inherited color-flash,
not replacing it - both fire), and `Death 1` played to completion via
`await animation_finished` before `_on_died()`'s inherited cleanup/
`queue_free()` runs - the one enemy in this project where death isn't
instant. `loop_mode` (Godot's glTF importer leaves every animation at its
default `LOOP_NONE`) is set at runtime for the two looping clips
(idle/walk) - a gameplay decision, deliberately not baked into the export
step itself.

**Verified in three passes**, learning directly from the scale bug above
(a structural pass alone wasn't enough there): a 14-check structural test
covering the full idle<->walk<->attack<->death state transitions (all
passed after fixing one test bug of its own - the test tried calling the
full `_physics_process()` with a manually-set `velocity`, not realizing
`Enemy._update_chase()` immediately zeroes it back out with no Player in
the scratch scene; switched the test to call the newly-extracted
`_update_animation_state()` directly), then two real windowed screenshots
- one mid-`Walk 1` (clean stride, correct cloth/robe flow, no tearing)
and one mid-`Attack 1` (full weapon follow-through, torso twisted into
the swing) - both confirming the bake is visually correct, not just
structurally present.

## 2026-08-30 — Arator the Redeemer is the First Figment Boss (New MDX->glTF Pipeline)

User dropped a Warcraft III Reforged model pack ("Arator the Redeemer" -
`.mdx` + `.dds` files) into `assets/models/` and asked to build an import
pipeline, then to make it the first Figment boss. Godot has zero native
`.mdx` support, so this is a from-scratch converter
(`tools/mdx_pipeline/mdx_to_gltf.js`), built on
[`war3-model`](https://github.com/4eb0da/war3-model) (an npm library that
parses both classic and Reforged MDX - confirmed against this real
Reforged v1200 file, not assumed from classic-MDX docs, which describe a
different convention). Node.js was installed via `winget` for this
(wasn't present on the machine at all).

The two facts the exporter's math depends on were confirmed by reading
`war3-model`'s own rendering source, not general MDX write-ups: skin
weight bytes (4 joint-index + 4 weight bytes/vertex, indices referencing
the full Nodes array by ObjectId) and the bind-pose math (MDX's
`Translate(pivot)*Translate(T)*Rotate(R)*Scale(S)*Translate(-pivot)`
formula collapses to Identity at rest for every node regardless of pivot
value - so every glTF inverseBindMatrix and rest-pose joint transform is
just Identity, a clean mapping with no per-node special-casing needed).
Verified in three passes: structurally (exact vertex/joint/mesh counts
matched the source file), visually via a real windowed screenshot
(correctly-proportioned, upright, no mesh tearing), and again after wiring
materials (see below).

Deliberately scoped to geometry + skeleton + skinning only for this pass -
no animation baking (the math is worked out, documented in
`tools/mdx_pipeline/README.md`, just not written), and no materials baked
into the glTF itself (glTF wants PNG/JPEG; Godot already imports `.dds`
natively and has `ORMMaterial3D`, a literal match for this asset's
Diffuse/Normal/Emissive/ORM packing, so fighting glTF's texture model
would have bought nothing).

**Wired into `FigmentBoss`**: the placeholder capsule mesh is hidden
(`visible = false`, not deleted - `Enemy.gd`'s telegraph-flash code looks
up `$MeshInstance3D` by exact node name), the real Arator model sits
alongside it as a sibling instance. Materials assigned Godot-side,
hardcoded to this specific model's known 9-geoset order (this model is a
composite rig merging pieces from other base Reforged models this project
has no textures for - those 3 geosets get a flat gray placeholder instead,
same "missing asset, flagged" treatment as everywhere else in this
project; 2 more are diffuse-only since their Normal/ORM references point
at base-game paths not present here). `FigmentBoss._apply_mesh_color()`
overrides the base single-mesh telegraph-flash to work across every real
mesh instead, flashing to a flat color and restoring the real textures
correctly (verified: a scratch test confirmed the exact live surface
materials before/during/after a simulated telegraph). No animation yet -
the boss stands in its natural (not T-pose) bind pose, which reads fine
since no other enemy in this project has skeletal animation either.

Caught two real bugs during verification, both fixed before this reached
the user: (1) the scratch viewing scene's floor `StaticBody3D` had a mesh
but no `CollisionShape3D`, so the boss fell straight through under gravity
(user caught this from a screenshot before I'd even finished diagnosing
it myself); (2) a cleanup command that broadly pattern-matched
`.godot/imported/` cache entries by name to delete scratch-test leftovers
also matched and deleted the REAL permanent asset's cache, breaking every
scene referencing `FigmentBoss.tscn` until a routine post-change headless
sweep caught it and a plain `--headless --import` fixed it.

### 2026-08-30 (later same day) — Fixed: Boss Rendered Far Too Small In Real Gameplay

User report, from an actual gameplay screenshot: the boss was tiny next
to the level geometry. Two compounding bugs, both fixed:

1. **Wrong calibration source.** The exporter's `scale` argument was
   picked (0.0066) against the MDX file's own *declared*
   `Info.MinimumExtent`/`MaximumExtent` (~220x142x288 units), assumed to
   be the model's real bounds. That metadata turned out to be loose/
   padded, not tight - a structural test run earlier in the same session
   had already measured the ACTUAL mesh bounding box at ~98x114x87 units,
   a very different number that was never cross-checked against the
   scale choice. Recalibrated against the real number instead (0.02,
   targeting a height a bit taller than the Player's own 1.8-unit
   capsule - appropriate for a boss).
2. **The scale wasn't even reaching the render.** Independently of the
   number being wrong, the mechanism was broken: `scale` was applied
   directly to a skeleton joint node (also listed in the skin's `joints`
   array). Godot's glTF importer absorbs a joint node's transform into
   internal `Skeleton3D` bone data rather than preserving it as a literal
   scene-tree `Node3D` transform - so the scale factor silently never
   affected the actual skinned render at all, regardless of what value it
   was set to. Two rounds of scratch-test diagnostics missed this (both
   accidentally measured the wrong thing - a mesh instance's own identity
   node transform, then a skeleton's rest-pose bone positions, which are
   all Identity by this model's own bind-pose design - see the entry
   above). Fixed properly by introducing a plain, non-joint "ModelRoot"
   wrapper node that both the skeleton and every mesh instance sit under,
   with the scale applied there instead - not ambiguous with skeleton-
   internal data, and verified this time by an actual visual comparison
   against a reference capsule of known height (1.8) in the same shot,
   not just a printed number.

## 2026-08-30 — Slate System Overhaul, HUD Redesign, Section 26 Spells

Seven user-directed changes in one pass.

**Fate Board layout now persists.** User report: "Slates do not persist
between scenes, they need to stay on the character." Root cause:
`Player._ready()` unconditionally built a fresh, empty `FateBoard.new()`
every scene load (Player is a fresh instance every Hub<->Map reload) -
`GameState` had no serializable record of *which Slate sits where* to
restore from, only ownership. `FateBoard.place_slate()`/`remove_slate()`
now call `GameState.sync_fate_board()` on every change (mirroring
`sync_equipment()`/`sync_ability_loadout()`'s existing pattern);
`Player._apply_saved_fate_board()` restores from `GameState.
fate_board_placements` the same way `_apply_saved_loadout()` already
does. A palette Slate (loaded from `data/slates/instances/`) is
referenced by its `resource_path`; a rolled `owned_slates` drop (no path)
by array index - preserves the exact object identity `FateBoardEditor`'s
single-use-ownership check already depends on rather than reconstructing
a duplicate. Persisted through `SaveManager` too, so it survives an app
restart, not just a scene change. Verified with 3 scratch tests (16 + 8 +
6 checks, all passed): connection-requirement edge cases, the full
`FateBoardEditor` UI placement flow including a Spell Slate's designation
picker, and a real `SaveManager.save_game()`/`load_game()` round-trip -
the real save file at `user://savegame.json` was backed up before that
last test ran and restored immediately after, since `save_game()` writes
for real.

**Slates must now connect.** User direction: "Slates should have to
connect with each other, not be placed freely." `FateBoard.can_place()`
now rejects any placement that isn't orthogonally adjacent to (or
overlapping) an already-placed Slate or a new `FateBoard.ANCHOR_CELL`
(board center, always counts as "placed" so an empty board has a legal
first move) - invented, no doc-given board origin exists (Section 10
calls the board "effectively unlimited"). Only enforced at placement
time; removing a Slate that orphans others from the anchor is allowed,
not retroactively blocked - a simplification the doc doesn't speak to
either way. `FateBoardEditor`'s status line now explains *why* a
placement failed in plain text instead of the raw `insufficient_aether`/
`cell_occupied`/`not_connected` string.

**Animated, type-colored Slate backgrounds.** User reference image: a
moving, color-shifting nebula texture per Slate type. New canvas shader
(`ui/fate_board_editor/slate_nebula.gdshader`) - hand-rolled hash-based
value noise (no external noise texture exists in this project), layered
and time-scrolled with a per-cell phase offset so a run of same-tag
Slates doesn't scroll as one flat blob, tinted by `Constants.
DAMAGE_TYPE_COLOR`, with sparse twinkling stars. Applied via a
`cell_data` texture `FateBoardGrid.gd` rebuilds only when placements
actually change, not on every hover-driven redraw. This is a deliberate,
flagged exception to the project's usual no-shader placeholder-art
convention (see `StatOrb.gd`'s header) - motion was the actual content
requested, and a CPU `_draw()` loop redrawing noise every frame would
have been both slower and far more code.

**Ward orb redesigned.** User direction: "Ward should appear as a fill
from top to bottom covering only 20% of the Life orb, oriented to the
right." Replaced the old outer-ring-around-the-rim design
(`StatOrb.set_ring_value()`/`_ring_fraction`/`ring_color`, all renamed to
`set_ward_value()`/`_ward_fraction`/`ward_color`) with an inset vertical
band along the orb's right edge, 20% of its diameter wide, clipped to the
circle's own curve at every scanline and filling/draining top-to-bottom
via the exact same `waterline_y` formula the main Life liquid fill
already used - same visual language, different placement.

**XP bar redesigned.** User direction: "mostly yellow/gold/orange... look
dynamic and move with visible stars in the bar when its filled." Replaced
the static 6-color rainbow `GradientTexture1D` with a `ColorRect` running
a new shader (`ui/player_hud/xp_bar.gdshader`) - a drifting warm gold/
amber/deep-orange blend, a sweeping highlight band, a slow noise-based
cloud texture, and twinkling stars. The bar's existing shrinking-clip-
window reveal mechanic (unchanged) already only shows the filled portion
of whatever's drawn underneath, so "stars only in the filled part" came
for free with no extra masking logic needed.

**Section 26, "Ability Staging Ground", found and mined.** Requested: a
spell list from the docs, implemented as much as possible. A docx-
extraction search (this project's established fallback for content the
PDF reader misses) surfaced a real, dense spell list the existing 9
abilities were never actually checked against - Ice Pulse/Comet/Winter's
Eye/Frost Armor really are doc-sourced, but Cinder Lance/Inferno/Static
Discharge/Stormcall/Entropic Decay are invented names from before this
section was found. Flagged as a conflict per user instruction ("for any
conflicts please ask me"); user chose to keep both sets rather than
retire the invented five. Added 8 new doc-sourced abilities: Flame Jets
and Meteor (Fire - Meteor reuses Comet's own fall-and-impact VFX outright
as the same mechanic, just Fire-colored), Thunder Javelin (small-radius
ground-target approximating "single target focus" - this project's cast
model has no discrete single-target lock) and Thunder Sweep (Lightning),
Black Hole (Entropic - a real 2.5s pull toward center via a new
`BlackHoleField` effect scene, on top of a deliberately thin instant hit
per the doc's own "low direct damage"), Caltrops (Physical - a new
`CaltropsField` effect scene dealing repeat Piercing damage over 5s; the
doc's "and are slowed" half is scoped out, since reusing Cold's Chill for
a Physical effect would be a thematic mismatch and no type-agnostic slow
exists), and Blink/Purge (Utility - the only two abilities with zero
damage component, special-cased in `PlayerAbilityCast._cast()`'s early
returns rather than forced through the generic enemy-damage loop; Blink
raycasts the player forward up to 8m, Purge clears the player's own
active debuffs via a new `StatusEffectComponent.clear_all_effects()` -
Purge's enemy-buff-stripping half isn't built, since no enemy-buff system
exists to strip anything from). Not built: Purity From Within (needs a
persistent toggle/channel ability archetype), Blinkstrike (needs a
weapon-scaled special dispatch outside the generic Ability damage model),
Conduit/Prowess (both explicitly "(Passive)" in the doc - no passive-node
system exists for a hotbar to grant).

**Slate-designated spells.** Requested: a Slate mechanic that binds to a
player-owned Tome/spell and interacts with it (trigger/buff/modify/
autocast). Found real doc grounding for exactly the autocast case -
Section 10's Unique Slate "The Unbound Chorus" ("Designate one Spell
skill - that skill automatically triggers when its cooldown expires"),
already present as inert flavor data (`unbound_chorus.tres`) with no
runtime mechanism reading it. Built the general framework - `Slate.
requires_spell_designation`, a `FateBoardEditor` picker over the player's
owned Abilities (not just the 4-slot hotbar), `FateBoard.PlacedSlateData.
designated_ability_id` (persisted) - and one concrete implementation on
top of it: `PlayerAbilityCast._process_slate_autocasts()` fires the
designated ability automatically once its cooldown reaches 0, at the
doc's own 60% damage, no resource cost, no Riposte/Composure interaction,
all three straight off The Unbound Chorus's own modifier list. Buff/
retrigger/modify variants are explicitly out of scope for now - no doc
example exists for those, so building them now would be pure invention
with nothing to implement against.

**Bug caught during verification, fixed in the same pass:** the new
Blink ability's wall-raycast originated at the player's own
`global_position` (feet/floor height) - a horizontal ray started exactly
at floor level immediately self-intersects the floor collider, reporting
a 0-distance "hit" and zeroing out every blink. Fixed by raycasting from
camera height instead, same as the existing ground-target aim raycast
already does. Caught by `scratch_big_test.gd`'s own Blink check before
this reached the user.

## 2026-08-30 — Fixed: Resistance Bounds Set, Strength/Arcane/Enigma's Missing "% Increased Damage" Per-Point Bonus Wired Up

Two related user directions in one pass: "The floor for resistances
should be -200%, the ceiling for resistances should be 95%" and "All of
the stats should be giving % increased damage for their respective
category and not a high amount."

**Resistance floor/ceiling.** `DamageCalculator.resistance_mitigation()`
previously had an invented 75% cap and an intentionally uncapped floor
(so Resistance Shred, patch v3.2, could push it arbitrarily negative).
Neither the Master doc nor either patch gives an exact number for this -
patch v3.2 only says Resistance Shred "can reduce Resistance below zero"
with no floor stated. Replaced with user-set `RESISTANCE_FLOOR := -200.0`
/ `RESISTANCE_CEILING := 95.0`, both applied via a single `clamp()` on the
resistance percent before converting to a mitigation fraction - shared by
both `Player.take_damage()` and `Enemy.take_damage()`, the only two call
sites.

**Strength/Arcane/Enigma's per-point "% increased damage."** Checked
Section 12's "The Six Stats — Per Point Values" table (docx-extracted,
`documents/Project_Aether_Master_v3.docx`) against what's actually
implemented: the table gives Strength +1% increased Physical damage per
point, Arcane +1% increased Elemental damage per point, Enigma +1%
increased Esoteric damage per point - `Constants.STAT_GLOSSARY` already
had this exact text as a tooltip string, but `Weapon`/`Ability._base_hit()`
never actually added it to the `increased_percents` pool DamageCalculator
consumes. What WAS implemented is a separate, also-doc-real mechanic:
Section 10's "Main Stat by Tag" table, where the same stat's raw point
value multiplies directly into the Stat Scaling Grade term (`stat_value *
effective_scale`) - this is likely what the user was seeing as "a high
amount," since a high-Grade weapon (S-grade: 150-200% of stat value) with
a stacked main stat scales hard through that channel alone, with the
doc's own separate, modest 1%-per-point "increased" bonus never actually
applying on top. Both mechanics are doc-real and meant to stack (Section
10 governs weapon/ability scaling; Section 12 lists universal per-point
stat effects) - so the fix wasn't replacing the scaling role, only adding
the missing modest layer: `increased_percents` in both `_base_hit()`s now
includes `stat_value` directly (1 raw point = 1%, matching the doc's flat
rate exactly, no invented multiplier).
- Verified with a 6-check test: resistance -500% clamps to -200% (mitigation
  -2.0); resistance 150% clamps to 95% (mitigation 0.95); in-bounds
  resistance values (-50%, 40%) pass through unchanged; 0 Strength still
  gives 0 damage (increased% can't manufacture damage from a zero
  scaling base, same property as the earlier Ward fix); and a direct
  `DamageCalculator.calculate()` comparison confirmed +50% increased (50
  Strength points) multiplies final damage by exactly 1.5x. All 6 passed.
  `TestArena` still loads clean.

## 2026-08-30 — Fixed: Fresh Characters Started With 900 Ward From Nowhere

User report: "Why do I start with 900 ward? ... Ward should only come
from your armor" - correct catch. The Ward/Resistance patch pass gave
every character a flat 300 base + 60 per Enigma point (invented, meant
to land near Patch v3.2's own "Low 800-1200" target band) regardless of
equipped gear - a completely ungeared character (baseline Enigma 10) got
`300 + 10*60 = 900` Ward for existing, with zero items actually granting
any of it.

User clarified further mid-fix: Ward should come from armor AND Enigma,
but Enigma should apply as an INCREASED% multiplier on the armor's own
flat Ward, not contribute its own flat amount - so zero Ward-granting
gear still means zero Ward no matter how much Enigma investment exists
(a multiplier on 0 is 0).

- Removed the flat base/per-Enigma-point constants entirely.
  `Player._apply_derived_stats()` now computes `ward.set_max_ward(
  equipment.compute_flat_ward_bonus() * (1.0 + enigma *
  WARD_INCREASED_PER_ENIGMA))` - `flat_ward` gear affixes are the only
  base, Enigma only scales what's already there. `WARD_INCREASED_PER_
  ENIGMA` (2%/point) is invented - no doc-exact rate exists for this
  specific multiplier (the patch's only exact Enigma/Ward number is the
  separate restoration-RATE one, untouched by this fix).
  `Player.tscn`'s `WardComponent.max_ward` default reset from 300 to 0
  to match (functionally inert either way - `_apply_derived_stats()`
  overwrites it at boot - but 300 was actively misleading to read).
- Verified with a 4-check test: a fresh character with starting gear
  (no `flat_ward` anywhere in this project's starting loadout) now has
  exactly 0 max Ward; artificially high Enigma with zero Ward gear still
  gives exactly 0 (proving the multiplier can't manufacture Ward from
  nothing); a real armor piece with a 200 `flat_ward` affix at 0 Enigma
  gives exactly 200; the same armor at 25 Enigma gives exactly 300 (200 x
  1.5, confirming the multiplicative math) - all 4 passed. `TestArena`
  still loads clean.

## 2026-08-30 — Fixed: Entering a Figment Froze the Game

User report: "I entered my first Figment, and the game froze" - a real
regression from the previous turn's Reality Engine selection-screen work.

Root cause: `RealityEngine._enter()` called `get_tree().change_scene_to_
file(GameState.MAP_SCENE)` without first clearing `get_tree().paused`.
The OLD Map Device flow rolled and traveled directly from an
`_unhandled_input` callback, never pausing anything - but the NEW
selection screen (`ShopScreen`, opened to let the player pick a Figment)
pauses the tree like every other menu in this project, and `_enter()`
never unpaused before leaving. `paused` is a `SceneTree`-level flag that
survives a scene change, so the new `GeneratedMap` loaded already paused -
every node without `PROCESS_MODE_ALWAYS` (the Player, every enemy) simply
never ran. This is a known, previously-fixed class of bug in this exact
project (`DeathScreen`/`MainMenu`/`PauseMenu` all carry the identical
`get_tree().paused = false` line before their own `change_scene_to_file()`
calls, with a comment explicitly warning about it) - a
`grep -rn change_scene_to_file` across every `.gd` file confirmed
`RealityEngine.gd` was the only of 7 call sites missing it.

Added the missing line, in the same position as the other 6 already-
correct sites. Verified by direct code inspection (a one-line ordering
fix matching an established, already-proven pattern used successfully 6
other places in this codebase) plus a fresh `Hub`/`GeneratedMap` clean-
load sanity check - a dynamic regression test that actually exercises
`_enter()` was attempted but abandoned: `change_scene_to_file()` tore
down the test's own node before the test script could inspect
post-call state, which is itself consistent with the scene change now
actually completing promptly rather than hanging.

## 2026-08-30 — Main Menu: Fixed the Invisible Lightning Bug, Added Trees

User reported "I haven't seen lightning flashes" on the Main Menu -
turned out to be two real, compounding bugs, not just rare timing.

- **Bug 1**: `night_sky.gdshader`'s flash blend was damped by
  `clamp(dir.y * 0.5 + 0.6, 0.0, 1.0)`, weighted toward straight-up
  (`dir.y` near 1) and weak near the horizon - exactly where
  `MainMenuBackground`'s camera actually points (a near-flat forward
  look, mountains filling most of the frame). The flash was real and
  firing, just mostly happening off-screen above where the player could
  see. Floored the falloff instead of scaling toward zero.
- **Bug 2**: `_on_thunder_started()` only boosted the `DirectionalLight3D`'s
  energy, but `MountainRange`/the new `TreeSilhouette` both use
  `SHADING_MODE_UNSHADED` materials (a deliberate choice for the cheap
  flat-silhouette trick) - unshaded materials ignore scene lighting
  entirely, so the light boost never touched them. The flash was
  sky-shader-only, and the sky is a thin band above a frame mostly full
  of unlit mountain silhouette. `MainMenuBackground` now tracks every
  registered silhouette material + its base color and lerps each one's
  albedo directly during a flash, alongside the sky and the light.
- Also tightened the thunder interval (14-32s → 6-16s, `ProceduralThunder`'s
  class default) and added a quick second flicker ~0.12s after the first -
  real lightning rarely reads as one clean fade.
- **Added trees** (`TreeSilhouette.gd`, new, user request): a foreground
  band of 22 procedural conifer silhouettes - trunk + 3 narrowing
  triangular tiers, same `SurfaceTool` flat-facing-camera trick
  `MountainRange` already uses, scaled/seeded per-tree for variety. Adds
  a 3rd depth layer to the existing far/near mountain parallax.
- Verified with a 50-check test: silhouette registration count (2
  mountains + 22 trees), a full flash provably brightening every single
  one of them (not just the sky), flash-intensity-0 restoring every
  material to its EXACT original color (no drift), the tightened thunder
  interval, and every tree's position landing inside its configured band -
  all 50 passed. `MainMenu.tscn` still loads clean. Did not additionally
  verify with a live screenshot this pass (a Godot editor session was
  already open, which the established capture procedure needs to be the
  only running instance) - the automated checks directly prove the
  mechanism (materials actually change color, trees actually exist at
  the right positions), but exact framing/scale is still worth a look
  next session.

## 2026-08-30 — Figments/Reality Engine: Rename, Selection UI, Drops, Empowering, Bosses, Figment Tree Scaffold

## 2026-08-30 — Figments/Reality Engine: Rename, Selection UI, Drops, Empowering, Bosses, Figment Tree Scaffold

User asked for a large bundle: rename "Map" items/device to "Figments"/
"Reality Engine," make Figments selectable (not auto-roll-and-commit),
droppable, craftable-to-be-harder, scaled, and give each a boss whose
death "completes" it - plus a Figment Tree scaffold to spend completion
points. None of this is doc-sourced (Section 24 doesn't even list an
endgame loop as designed) - a from-scratch invented system throughout.

- **Renamed for real**: `data/maps/map_item.gd`/`map_roller.gd` →
  `data/figments/figment_item.gd`/`figment_roller.gd`
  (`MapItem`→`FigmentItem`, `MapRoller`→`FigmentRoller`);
  `entities/interactables/map_device/MapDevice.gd`/`.tscn` →
  `entities/interactables/reality_engine/RealityEngine.gd`/`.tscn`
  (`MapDevice`→`RealityEngine`). Real `git mv`s, not just new files -
  history follows. `GameState.active_map` keeps its field name (still
  means "the Map's active modifiers") but its type is now `FigmentItem`.
  The unrelated `MapScreen`/`GeneratedMap`/`MapGraph` (the `M`-key
  room-graph viewer and the dungeon-level generator) are untouched -
  different "Map" meaning entirely, not what was asked to rename.
- **Real selection UI**: the Reality Engine no longer auto-rolls and
  commits on `E` - it opens a list (reuses `ShopScreen`, the exact same
  generic list-purchase UI GearShop/SpellTestShop already share, plus one
  small addition - an optional per-row `button_label` override so "Enter"
  reads right instead of "Take") of every owned Figment, plus an
  always-available free Tier 1 offer so there's never a hard floor on
  playing before any Figment has dropped.
- **Droppable**: `Enemy._maybe_drop_loot()` gained a 6% Figment roll
  (`FigmentRoller.roll_for_drop()`, tier scaled near the killing Map's
  own tier ± 1, clamped to a new `MAX_TIER` of 10) - reuses `_spawn_pickup()`
  directly since `FigmentItem` already extends `Item`, no new pickup
  field needed (unlike Slates, which needed one). `ItemSerializer` gained
  a `FigmentItem` branch so dropped/owned Figments actually survive a
  save/load, and `InventoryScreen._is_equippable()` now excludes
  `FigmentItem` - without this it would have hit the exact same "click
  silently clears your real equipment" bug the Brand/consumable pass
  fixed two turns ago (`equip_slot` defaults to HELMET on every `Item`
  subclass that doesn't set one).
- **Craftable (harder)**: `CraftingSystem.empower_figment()` - a
  dedicated action, not routed through the Brand/Cube system at all
  (a Figment's affixes are enemy/loot multipliers, not the flat_<stat>/
  damage-% pool Brands roll against, so the generic Cube path doesn't
  apply semantically). `CraftingScreen` shows a Gold-gated "Empower"
  button instead of the normal Cube UI when the selected item is a
  Figment - raises tier by 1 and re-rolls/strengthens one affix via a new
  `FigmentRoller.strengthen()`.
- **Boss + completion**: `FigmentBoss` (new archetype, `entities/enemies/
  figment_boss/`) - roughly an 8x-health/2.2x-damage/10x-reward
  `HeavyHitter`, spawned in the Vault room's platform slot in place of the
  old reward `GlassCannon` ("one Vault per Map" already guarantees
  exactly one, so it's the natural home for the one guaranteed boss too,
  zero extra map-generation plumbing needed). Its death fires a new
  `EventBus.figment_completed` signal.
- **Figment Tree scaffolding** (`systems/figment_tree/`, deliberately
  NOT a full system per the request's own "prepare legs" framing):
  `FigmentTreeNode` (Resource: id/name/cost/prerequisite/a stub
  `effect_key`) + `FigmentTree` (5 hand-authored nodes, real
  `can_unlock()`/`unlock()` validation against a new
  `GameState.figment_tree_points` - `GameState._on_figment_completed()`
  grants 1 point per completed Figment's tier). No UI screen exists yet,
  and no node's `effect_key` is wired into anything mechanical - both
  explicitly left for later.
- Verified with a 52-check real scene-load test: the roller's tier/drop-
  scaling/clamping, Empower's exact tier/affix effects, a full
  `ItemSerializer` round-trip, the Reality Engine's entry-building logic,
  a real `FigmentBoss` vs. a real `HeavyHitter`'s stats side by side, the
  boss's death actually emitting `figment_completed` with the right
  Figment attached, points accumulating by tier, the Tree's full unlock/
  prerequisite/re-purchase-refusal logic, the Inventory equip-guard
  regression check, and the Crafting screen's Empower button end-to-end
  (Gold spent, tier raised) - all 52 passed. `Hub`/`TestArena`/
  `GeneratedMap` all still load clean, including `GeneratedMap` now
  spawning a real `FigmentBoss` in its Vault room.

## 2026-08-30 — Crafting: Preview a Brand's Possible Rolls Before Committing

User asked for it directly: clicking a Brand in the Crafting screen
should show what it can actually roll, not just add it to the Cube
blind. Added `CraftingScreen._show_brand_preview()`, wired into the
existing click handler (still adds the Brand to the Cube too, unchanged) -
for a Damage/Defensive/Umbrella Brand it lists every entry
`ItemRoller._pool_for_brand_tag()` would actually draw from for the
currently selected item (the exact same pool a real craft rolls against,
so the preview can't promise something a craft wouldn't produce); for a
Utility/Special Brand (Render, Cleave, Binder, ...) it shows the Brand's
function description instead, since those don't roll from a pool at all.
Verified with a 4-check test (real pool entries shown, a placeholder
value not a fake rolled number, no leaked printf tokens, a Utility
Brand's description shown instead) - all 4 passed.

## 2026-08-30 — Tooltip UX Overhaul, Distinct Stat Cards, Stance Tuning

User reported three UX issues in one pass: the Alt-hold advanced tooltip
felt sticky/unintuitive, hover tooltips weren't fast enough, and Item/
Slate/Ability cards were hard to tell apart at a glance. Asked
specifically to check how Path of Exile 2 and Victoria 3 handle
Alt-hold tooltips before redesigning - PoE2 confirmed via search: Alt is
a genuine HOLD modifier (release it, the info goes away), not a
click-to-pin toggle, which is what this project actually had.

- **`AdvancedTooltip`/`ItemSlotButton` rewritten**: Alt press-while-
  hovered still opens the card, but Alt release now closes it too -
  unless the mouse has moved onto the card itself (so a player can still
  one-handed-hold-Alt-then-mouse-onto-the-card to click through mod-tier
  ranges/glossary links), in which case it closes once the mouse leaves
  the card instead. The old version stayed pinned open until Esc/
  outside-click regardless of Alt state - the actual "sticky" bug.
- **Tooltip delay dropped from 0.15s to 0.03s** (`project.godot`,
  `timers/tooltip_delay_sec`) for a near-instant feel.
- **`ItemCard` gained a real type-distinction system**: Item/Slate/
  Ability cards previously differed only by a rarity-colored border - a
  Rare Item and a Rare Slate rendered with the literal same border color
  (both rarity enums map RARE to yellow), user-caught. Now each type
  layers 3 independent, asset-free cues: a colored type badge ("ITEM"/
  "SLATE"/"SPELL", drawn first so it's the first thing seen), a distinct
  corner-radius/border-width silhouette (Item sharp, Slate rounded +
  thicker border, Ability the roundest of the three - no gear has soft
  corners, only spells do), and a faint background tint. Slate's badge
  uses a fixed color independent of the Slate's own rarity, so a Common
  and a Mythic Slate both still read as "Slate" instantly. Ability cards
  are now colored by the ability's own damage type instead of one flat
  blue for every spell regardless of element - a free improvement beyond
  what was asked: spells are now distinguishable from EACH OTHER too, not
  just from items/Slates.
- **`StanceComponent.apply_attack_stance_damage()` reduced by 80%**
  (`ATTACK_STANCE_DAMAGE_MULTIPLIER = 0.2`) - user-reported: ordinary
  attacks were depleting Stance so fast that Composure Break triggered
  almost immediately, drowning out Parry's intended role as the primary
  Stance-break tool (Section 07: "depleted primarily through successful
  Parries"). `apply_parry_damage()` (used by real Parries) is untouched,
  still full-strength.
- Verified with a 16-check real scene-load test: the exact stance-
  reduction math, Item vs. Slate cards sharing a rarity color but
  differing in every other cue, an Ability card's border matching its own
  damage type, each card's badge text/color, and the full Alt hold/
  release/mouse-over-card state machine - all 16 passed. `TestArena`
  still loads clean.
---

## 2026-08-30 — Design Patch v3.2: Ward/Resistance System Overhaul

User dropped a new design doc (`Project_Aether_Patch_v3_2.docx`) into
`documents/` as part of a larger request and asked for it to be read and
applied. Extracted and read it in full before touching code (177 lines,
short enough to read start to finish) - a complete revision of Ward,
adds a real Resistance system, removes Scorch, adds Resistance Shred.

- **`WardComponent` rewritten**: absorbs ALL damage types now (the old
  Esoteric-only restriction is gone), no mitigation of its own (pure
  buffer). Real regen for the first time ever - 2s delay after any hit
  (reset by every subsequent hit), then 4% of max Ward/second, +5% on
  kill (`Enemy._on_died()`), +15% on Parry (unchanged ratio, still
  invented - no exact number given for Parry specifically even though
  passive/on-kill are now doc-exact). Every restoration source scales by
  a new `restoration_multiplier` (Enigma +1%/point, "Ward Restoration is
  a unified stat").
- **Ward pool size** now has a real formula (`Player._apply_derived_stats()`):
  invented base + Enigma scaling landing baseline near the patch's "Low"
  band, plus `flat_ward` gear affixes - which existed since early in this
  project but were purely descriptive (README gap #18) until this patch
  gave Ward a formula to feed.
- **Resistance System** (new): `StatSheet.equipment_resistance` (Fire/
  Cold/Lightning/Esoteric - the last unifying Aetheric/Entropic/Pale per
  the patch), summed from 4 new `ItemRoller.AFFIX_POOL` entries
  (doc-exact 11-27% range, matching the patch's own Ring implicits) and
  reusing the Crafting system's existing `Temper` Brand category. Added
  the 4 named Resistance Rings (Ember/Frost/Volt/Void) as real items.
  `DamageCalculator.resistance_mitigation()` mirrors `physical_mitigation()`'s
  role for Elemental/Esoteric damage - capped at 75% (this project's own
  invented ceiling, the patch caps nothing explicitly) but with no floor,
  so Resistance Shred can push it negative.
- **Order of operations rewritten** in `Player.take_damage()`: Armor
  (Physical) or Resistance (Elemental/Esoteric) mitigates first, then
  Ward absorbs whatever's left regardless of type, then Health. Ignite's
  existing Resilience mitigation (`StatusEffectComponent._tick_ignite()`)
  now stacks with Fire Resistance automatically, for free - it already
  routed through `take_damage()`.
- **Resistance Shred** (new mechanic, `StatusEffectComponent`):
  diminishing-returns stacking verified against the patch's own worked
  example (20%/15%/10% -> 32.5%, confirmed each source beyond the first
  contributes at half of its OWN value, not a compounding chain). Wired
  into both `Player.take_damage()` and `Enemy.take_damage()` - enemies
  have no Resistance stat of their own, but "0% base - shred%" is still
  real negative Resistance, which is the patch's own primary framing for
  the mechanic (shredding an enemy). No current applier exists - the
  patch introduces it via a Throwable-focused Unique this project can't
  build yet (no Throwable weapon category).
- **Scorch**: the patch removes it as a universal status effect. Nothing
  to remove in this project - Scorch was never implemented in the first
  place (already scoped out of `StatusEffectComponent`'s original pass
  as needing a Fire-channel mechanic that doesn't exist).
- Verified with an 18-check real scene-load test: Ward absorbing every
  damage category, regen's delay/rate timing, `set_max_ward()`'s
  missing-value preservation, the resistance formula at its cap and past
  zero, Shred's exact stacking math, a full `Player.take_damage()` pass
  proving Resistance actually reduces what reaches Ward, a real `Enemy`
  taking exactly 20% more Fire damage after a Shred application, and
  gear affixes reaching both `compute_resistance_bonuses()` and
  `compute_flat_ward_bonus()` - all 18 passed. `TestArena`/`Hub`/
  `GeneratedMap` all still load clean.

## 2026-08-30 — Slate System Expansion: Real Stats, Mastery, Chain Damage, a Roller

User asked to expand the Slate system; a survey turned up that placing
Slates, computing chains, and tracking Aether budget all worked and
updated the UI live, but NONE of it reached `StatSheet`/`DamageCalculator`
- the whole Fate Board was a placement puzzle with no combat effect.
User picked all three offered directions: wire Slate output into
gameplay, add a real acquisition path (a `SlateRoller`), and author more
content.

Re-read Section 10 from the docx-extracted design doc rather than
guessing at the mechanics - found doc-exact numbers for the Chain Bonus
tiers (already transcribed correctly in `Constants.CHAIN_BONUS_TIERS`
from an earlier pass), a "Stats Per Tile" formula (1.7 Main Stat/tile +
0.8 Random Stat/tile, 5+ tile Slates only), a Main Stat by Tag table
(matches `Constants.DAMAGE_TYPE_MAIN_STAT`, already in the project for
weapon/ability scaling), and Mastery's real definition: "tag-specific...
multiplying both the per-tile chain bonus rate AND weapon scaling grade
effectiveness for that tag" - the causality is Mastery amplifies chain
bonus, not the reverse (an earlier assumption while planning this that
the doc corrected on a careful re-read).

- **`StatSheet` gained `slate_bonus`/`chain_bonus_by_tag`** alongside the
  existing (but never-populated) `mastery_by_tag`. `FateBoard.
  compute_stat_bonuses()` sums every placed Slate's `flat_<stat>`
  modifiers into the first, reusing `EquipmentComponent.AFFIX_STAT_KEYS`
  so a Slate modifier means exactly what a gear affix already means.
  `FateBoard.compute_mastery_bonuses()` sums "mastery" modifiers by tag
  into the second - `Weapon`/`Ability._base_hit()` were ALREADY reading
  `stat_sheet.get_mastery(damage_type)` into the damage formula's
  scaling-grade multiplier since early in this project; nothing had ever
  written to it. Just adding a source made Mastery real with zero changes
  to the damage formula itself.
- **`ChainCalculator.amplify_by_mastery()`** (new): takes raw per-tag
  chain results and each tag's Mastery, returns `(1 + mastery)`-amplified
  bonus per tag - kept separate from `compute_chains()` so the raw board
  geometry stays usable without a `StatSheet` (`FateBoardEditor`'s own
  chain label still shows the unamplified numbers). The amplified result
  feeds `Weapon`/`Ability._base_hit()`'s `increased_percents` parameter -
  every damage roll already accepted this array, nothing had ever passed
  anything into it. Whether a Slate's own STAT rolls should also be
  chain-amplified is explicitly unresolved in the doc itself ("deferred
  pending balance evaluation") - left unamplified, matching that stated
  deferral rather than guessing past it.
- **`Player._apply_fate_board_bonuses()`** (new): listens to
  `EventBus.slate_placed`/`slate_removed` (both already emitted by
  `FateBoard`, nothing new needed there) and recomputes all three
  StatSheet fields plus `_apply_derived_stats()`, so a placed Slate's
  Vitality immediately affects max Health the same frame, same as
  equipping gear already does.
- **`SlateRoller`** (new, mirrors `ItemRoller`/`BrandRoller`): rolls all
  five of Section 10's axes. Tag/Hybrid/shape (a small invented template
  pool spanning 2-11 tiles) are randomized; the stat formula is NOT
  rolled in a range once size is chosen - it's the doc's own deterministic
  per-tile formula. Small (2-4 tile) Slates get a Mastery modifier
  instead of stats, matching the doc's "no stat contribution... pure
  modifier expression" - an invented reading of what that modifier
  actually IS, since the doc never says. Dropped as loot (`Enemy.gd`,
  10% chance/kill, same flat-independent convention as Tomes/Brands) via
  a new `LootPickup.slate` field (Slate doesn't extend Item, so it needed
  its own field alongside `item`) and two new EventBus signals
  (`slate_dropped`/`slate_picked_up` - `loot_dropped`/`loot_picked_up`
  are typed to `Item`, which Slate isn't).
- **`GameState.owned_slates` + `SlateSerializer`** (new): real Slate
  ownership now persists across saves, same full-data rationale as
  `owned_loot`/`ItemSerializer`. `FateBoardEditor`'s palette now shows
  the hand-authored catalog (unlimited, unchanged) PLUS every owned
  rolled Slate NOT currently placed (`_is_slate_available()`) - a rolled
  Slate is single-use until pulled back off the board, unlike the
  catalog's infinite samples. Fate Board LAYOUT (which Slate sits where)
  still isn't saved (unchanged, existing gap) - only ownership is.
- **9 new hand-authored Slates** (`data/slates/instances/`) spanning 7 of
  the 9 damage tags, both stat-formula and Mastery-only variants, and one
  Hybrid (Cold/Fire) - the project's first Slate content beyond the
  original 2 samples.
- Found and fixed one real bug while building this: `SlateRoller`'s
  shape templates are plain untyped `Array`s (a GDScript const
  array-of-arrays literal doesn't infer `Array[Vector2i]` for the inner
  arrays), so a direct assignment to `Slate.shape_cells` crashed with a
  type error on every roll - fixed with an explicit element-by-element
  copy into a typed array.
- Verified with a 183-check real scene-load test: stat/Mastery
  aggregation, chain-amplification math at an exact value, live
  `EventBus`-driven `StatSheet` updates on a real `Player` (place a
  Slate, watch Strength rise; remove it, watch it revert), an end-to-end
  proof that a chain bonus multiplies actual predicted weapon damage by
  exactly the expected ratio (and does NOT leak across tags), `SlateRoller`
  output respecting every doc bracket/formula across 40 rolls,
  `SlateSerializer` round-trips, and the palette's single-use gating -
  all 183 passed. `TestArena`/`Hub`/`GeneratedMap` all still load clean.

## 2026-08-29 — Real Per-Cell Inventory Positioning (the Swap Fix Wasn't Enough)

User tried the swap fix from the previous entry and it still wasn't
right: dropping on an empty cell across the grid landed the item right
next to the other real items instead of in the exact cell dropped on,
and everything in between visibly slid over. Root cause the swap fix
didn't address: the grid was still backed by a plain ordered list
(`GameState.owned_loot`'s array order, or `_stack_entries`' derived
order) - "drop on empty slot 30" and "drop on empty slot 8" were
indistinguishable to that model, both just meaning "append to the end of
the real items." A list can't represent a gap; only real per-cell
position tracking can.

- **`InventoryScreen._slot_assignment`** (new): entry key -> the grid
  cell the player actually put it in, relative to `_draggable_start_index`
  so the whole real-items region can slide as a block if the catalog's
  shown count changes without invalidating stored positions. `_resolve_
  slots()` places every entry at its remembered cell if free, otherwise
  the lowest free cell in entry order (so a never-touched item still
  just fills in left-to-right/top-to-bottom, unchanged from before).
  Entry keys: Brands key off `"brand:<item_id>"` (intentional - that's
  exactly what makes duplicates stack into one entry); everything else
  keys off its own Resource's `get_instance_id()`, since `item_id` alone
  isn't unique per-instance for non-rolled items (two separately-dropped
  Infusion Stones share `item_id` but must NOT merge the way Brands do).
- **`GameState.owned_loot`'s own array order is no longer touched by
  dragging at all** - the previous swap-fix version still flattened
  reordered entries back into it; now only `_slot_assignment` changes,
  which is simpler and also happens to make the whole equipped-item-
  position-preservation dance from the last entry moot (nothing reorders
  the array, so there's nothing to preserve against).
- Position is intentionally session-local, not persisted (`GameState`
  never sees `_slot_assignment`) - README flagged gap #26. Doing better
  would need a real save-stable per-item id, which doesn't exist yet
  (`ItemSerializer.from_dict()` reconstructs fresh Resource objects with
  new instance ids on every load) - flagged rather than guessed at.
- Verified with a 25-check rewrite of the previous test, including the
  literal bug report as its own case (drag to a far empty cell, assert it
  lands exactly there AND every other real item's slot is provably
  untouched), plus occupied-slot swap, position surviving a plain rebuild
  with no changes (simulating close/reopen), and confirming
  `GameState.owned_loot`'s order truly never changes anymore - all 25
  passed. `TestArena`/`Hub`/`GeneratedMap` all still load clean.

## 2026-08-29 — Inventory Drag Now Swaps Instead of Inserting

User caught this in play immediately: dragging an item onto a slot was
inserting it just before that slot's original position (the previous
entry's design), which shoved every later slot down by one instead of
actually placing the dragged item where it was dropped.

- **`InventoryScreen._on_item_drag_dropped()` rewritten as a real swap**:
  the display order (`_stack_entries`) is swapped at the entry level
  first (source and target trade places, full stop), then flattened back
  into `GameState.owned_loot`'s UNEQUIPPED positions only - equipped
  items keep their own absolute array index untouched throughout (their
  relative order was never meaningful to anything downstream; only the
  unequipped order the player actually sees needs to stay stable).
  Dropping past the last real slot (empty padding, nothing to swap with)
  still moves the dragged stack to the end, same as before.
- Verified with an updated 20-check version of the previous test:
  single-item swap, whole-Brand-stack swap, drop-on-empty-padding, and a
  new check that an equipped item's exact array position survives an
  unrelated swap elsewhere in the list - all 20 passed.
  `TestArena`/`Hub` reload clean.

## 2026-08-29 — Rearrangeable Inventory + Stacking Brands (+ an Equip-Click Bug Fix)

User asked for two things: a moveable/rearrangeable inventory grid, and
Brands that stack instead of taking one slot per drop.

- **`ItemSlotButton` gained opt-in drag-and-drop** (`draggable`, off by
  default): `_get_drag_data()`/`_can_drop_data()`/`_drop_data()` are
  Godot's own native Control drag API, emitting a new
  `item_drag_dropped(source_index, target_index)` signal off each
  button's own index in its parent container. Off by default so Fate
  Board/Abilities/Shop's own `ItemSlotButton` usages are untouched -
  only `InventoryScreen` turns it on.
- **`InventoryScreen`'s grid is now rearrangeable**: dragging a slot onto
  another reorders `GameState.owned_loot` directly (remove the dragged
  stack, reinsert just before the target's original position) - no new
  save-format field needed, array order was already part of `SaveManager`'s
  existing save data. Only real owned_loot entries are draggable; the
  directory-scanned "one of each hand-authored base" catalog always sits
  first, fixed, un-draggable and un-targetable (its scan order isn't
  something the player owns to rearrange).
- **Brands now stack**: `InventoryScreen._build_stack_entries()` groups
  identical Brands (same `item_id` - fungible crafting currency, not
  unique rolled gear) into one grid slot showing a count ("Impel x3")
  instead of one slot per drop, and the whole stack drags as one block.
  Everything else (weapons, armor, unique rolled items, crafting
  consumables) stays one slot per item, unchanged.
- **Found and fixed a real bug while touching this code**: clicking any
  grid slot called `EquipmentComponent.equip(item)` unconditionally.
  Brands and the 3 crafting consumables (added to `owned_loot` two turns
  ago) default to `equip_slot = HELMET` (an inherited-but-meaningless
  field, same as `MapItem` already notes for itself) - clicking one in
  the inventory silently cleared whatever the player actually had
  equipped in that slot (`item as Armor` safe-casts to `null` for a
  non-Armor type, so `helmet = null`). Added `InventoryScreen.
  _is_equippable()` to gate the click handler; a Brand/consumable click
  now shows a status message pointing at the Crafting screen instead.
- Verified with a 17-check real scene-load test reusing `TestArena.tscn`
  (stack counts and `loot_indices`, grid button text, single-item and
  whole-stack drag reordering producing the exact expected
  `GameState.owned_loot` order, and - the regression check - equipping a
  helmet then clicking a Brand and confirming the helmet stays equipped)
  - all 17 passed. `TestArena`/`Hub`/`GeneratedMap` all still load clean.

## 2026-08-29 — Enemy Tier Scaling + Crafting System (The Cube, Brands, Corruption)

User asked for two things: enemies that scale with the Map's tier, and
the Crafting system from Section 20 of the design doc.

**Enemy tier scaling** (`Enemy.gd`): `MapItem.tier` already fed
`enemy_health_multiplier`/`enemy_damage_multiplier` indirectly through
`MapRoller`'s random affix rolls, but neither is guaranteed to land on a
given Map - two Tier 5 Maps could end up no tougher than two Tier 1 Maps
by chance. Added a deterministic curve on top (+15% health/+10% damage/
+20% XP+Gold per tier above 1, invented, Section 24 defers Map/tier
balance entirely) so tier always matters regardless of what affixes rolled.

**Crafting System** (`systems/crafting/CraftingSystem.gd`, `ui/crafting/`,
`data/brands/`, hotkey `K`): pulled Section 20 and Section 14/15's Cube/
Socket content from the docx-extracted design doc rather than guessing -
found a full "Three distinct crafting methods" table (The Cube/Brand
combinations, Infusion/Shrivening Stone, Shard of Tharsis) plus a named
Brand list (~29 entries) and a Corruption outcomes list, but also found
Section 24 ("Deferred Design") explicitly listing "Cube combination
rules," "Brand rarity tiers," and "Corruption probability distribution"
as NOT YET DESIGNED by the doc itself - not a gap in this project's
reading, a gap the doc names about itself. Built all three methods with
this project's own invented placeholders for those specific unresolved
pieces, flagged throughout (README gap #25), same convention as every
other deferred-design gap already in this project.

- **`Brand`** (new `Item` subclass, `data/brands/brand.gd`): 24 of the
  doc's ~29 named Brands exist as real `.tres` instances (all 9 Damage
  Type, all 5 Defensive Type, all 4 Umbrella, all 6 Crafting Utility, plus
  Binder/Rectify from Special/Rare) - Facsimile/Amalgam/Imbue cut, each
  being its own separate mechanic (duplication, mod-pool merging, a new
  "powerful implicit" pool) with no natural home here. Dropped as loot
  only (`BrandRoller.gd`, same flat-chance convention as Skill Tomes) -
  wired into `Enemy._maybe_drop_loot()` alongside a new, rarer roll for
  Infusion Stone/Shrivening Stone/Shard of Tharsis (`data/consumables/`).
- **`ItemRoller.AFFIX_POOL` extended** with a `brand_tags` field per
  entry (which Brand category can draw it) and 4 new descriptive-only
  entries (Evasion/Resistance/Resilience/skill cooldown) so every Brand
  category has something real to roll - same "descriptive-only, not
  aggregated into a formula" caveat flat_armor/flat_ward already carried
  (gap #18), just extended, not a new gap.
- **`CraftingSystem.craft_cube()`**: no utility/special Brand present ->
  category Brands (Damage/Defensive/Umbrella) add one new weighted affix,
  a Brand placed twice just doubling that category's odds (covers "max 2
  of the same Brand" without a separate stacking rule). With a utility
  Brand present, Render/Refine/Cleave/Excise/Bore/Sever each do their
  doc-described thing for real - Cleave locks one modifier (player-chosen,
  click an affix row in the UI) and rerolls the rest, a second Cleave
  risking destruction; Sever, combined with a category Brand in the same
  craft, permanently seals that tag, with Binder protecting the seal from
  a second Sever's undo-chance. When several utility Brands are placed
  together (undefined by the doc), a fixed invented priority order decides
  which one governs - documented, not silently arbitrary.
- **Infusion/Shrivening Stone**: finally wire `Weapon.infused_damage_type`,
  which existed unused since early in the project - Infusion rerolls it to
  a random type other than native, Shrivening clears it.
- **Shard of Tharsis**: `CraftingSystem.corrupt()` rolls one of Section
  20's own 8 listed outcomes (weighted, invented), and separately rolls
  the doc's stated "chance to retain craftable/corruptible status" -
  failing that roll sets a new `Item.is_craftable = false`, permanently
  blocking any further Cube craft or corruption on that item.
- **`CraftingScreen`** (new, built in code like `PlayerHUD` rather than a
  hand-laid-out `.tscn` - three columns: owned target items, the Cube
  itself, owned Brands/consumables). Deliberately restricted to
  `GameState.owned_loot` only, never the hand-authored "one of each base"
  list `InventoryScreen` shows for convenience - those are shared
  `load()`-cached Resources, and crafting one in place would have
  permanently corrupted that base `.tres` for the rest of the session
  (including future `ItemRoller.roll()` picks from it). Wired into
  `PauseMenu`'s existing hotkey router (`open_crafting`, `K`) and every
  scene that already carries the other menu screens (`Hub.tscn`,
  `GeneratedMap.gd`'s `UI_SCENES`, `TestArena.tscn`).
- Verified with a 89-check real scene-load test: tier scaling's exact
  growth curve at tier 1 and tier 5, every Cube function (including a
  50-iteration loop confirming Cleave's destroy chance actually fires),
  Sever's tag-sealing blocking a later add, Binder's consumption
  exemption, the max-2-same-Brand and is_craftable gates, Infuse/Shrive,
  Corruption's outcome variety and its craftable-retention odds across 20
  fresh items, and full `ItemSerializer` round-trips for `Brand` and the
  4 new `Item` fields (`cleave_count`, `sealed_tags`, `is_corrupted`,
  `is_craftable`) - all 89 passed. `Hub`/`GeneratedMap`/`TestArena` all
  still load clean with the new scenes/nodes wired in.

## 2026-08-29 — Status Effect System (Ignite, Chill/Freeze, Electrocute, Unraveling)

User asked what to build next; agreed on a status-effect system since
`Ability.applies_status_effects` already existed on 6 of 9 spells but did
nothing (flagged gap #12), and it's the natural unlock for two more
standing gaps (Vitality's Resilience/DoT mitigation, Intellect's Debuff
effectiveness - gap #14). Pulled Section 09's real effect table from the
docx-extracted design doc rather than inventing names - it lists 11
effects across Physical/Elemental/Esoteric; scoped this pass to the 5
with a real applier today (Ignite/Chill/Freeze/Electrocute/Unraveling -
all Elemental/Esoteric, matching the spells that already declare them).
Physical family (Bleed/Armor Shred/Stagger-Stun) has no weapon-side proc
mechanic and Scorch/Aetherburn/Pallid have no Fire-channel/Aetheric/Pale
ability yet - both left for `StatusEffectComponent` to grow into later.
Blind is explicitly deferred in the patch doc itself, not modeled at all.

- **`StatusEffectComponent`** (new, `entities/components/`): bidirectional
  by design (attached to both `Player.tscn` and `Enemy.tscn`) even though
  only Player→Enemy is exercised today - no enemy currently applies an
  effect, but the component doesn't care which side owns it. Ignite ticks
  Fire DoT damage over 4s (50% of the triggering hit, spread across 8
  ticks); Chill slows move/action speed 30% and a 3rd application within
  its own window escalates to Freeze (full immobilization) instead of
  just refreshing; Electrocute is a flat stun; Unraveling raises Esoteric
  damage taken 25%. All durations/magnitudes are invented - the doc gives
  qualitative behavior only, no numbers (flagged gap #24).
- **Resilience/Debuff effectiveness wired for real**: `Player.resilience`
  (Vitality × 3, doc-exact) feeds `DamageCalculator.dot_mitigation()`
  (`Resilience / (Resilience + 2000)`, soft-capped 50%, also doc-exact)
  to reduce Ignite ticks. The *applying* side's Intellect stat extends
  Chill/Electrocute/Unraveling's duration by 1.5%/point (also doc-exact).
  Renamed two ability instances' effect ids to match Section 09's actual
  terminology now that it's been read (`stormcall.tres`/
  `static_discharge.tres`: `"shock"` -> `"electrocute"`;
  `entropic_decay.tres`: `"weaken"` -> `"unraveling"`).
- **Combat-loop integration**: `PlayerAbilityCast._cast()` now applies
  each hit ability's `applies_status_effects` to every enemy it damages.
  `Player.take_damage()`/`Enemy.take_damage()` both run damage through
  `get_damage_taken_multiplier()` (Unraveling). Stunned (Electrocute/
  Freeze) enemies have `EnemyMeleeAttack`/`EnemyRangedAttack`'s state
  machine paused, not reset, at the top of their own `_physics_process()`
  - a frozen mid-telegraph enemy resumes exactly where it left off, not
  from Idle. Stunned Player loses jump/parry/attack input for the same
  physics tick movement already zeroes out through the existing
  `_effective_speed()` chain.
- **Visual feedback**: small colored dots above an Enemy's head (one per
  active effect, tag color reused from `Constants.DAMAGE_TYPE_COLOR` via
  the effect's underlying damage type) sit below the existing riposte
  indicator. `PlayerHUD` gained a matching top-left chip row for the
  player's own active effects, built/removed live off two new
  `EventBus` signals (`status_effect_applied` already existed unused;
  added `status_effect_expired`). `DebugOverlay` logs both.
- Verified with a 21-check real scene-load test (Ignite DoT ticking +
  natural expiry, Chill→Freeze escalation, movement zeroing, Electrocute
  pausing a mid-telegraph `EnemyMeleeAttack` and resuming after, Unraveling's
  damage multiplier applied on both Player and Enemy `take_damage()`,
  Resilience mitigation's formula at 3 points including its own soft cap)
  - all 21 passed. `Hub`/`GeneratedMap`/`TestArena` all still load clean.

## 2026-08-29 — Real 3D Weapon Models (Greatsword, Dagger)

User asked why the weapon models weren't rendering yet - last entry
explicitly deferred this as too risky to rush, but with the screenshot
capability already proven out, went back and actually did it.

- **`Player._update_weapon_model()`**: keyed by `Weapon.weapon_type`
  (`WEAPON_MODEL_SCENES` - "Greatsword" -> `Great_Sword.fbx`, "Dagger" ->
  `Dagger.fbx`), instances the real FBX scene as a child of `weapon_mesh`
  and clears `weapon_mesh.mesh` so the placeholder box doesn't render
  behind it. Anything unmapped (currently just "Service Pistol" - no
  firearm exists in this melee-focused pack) falls back to exactly the
  old tinted placeholder blade, `_placeholder_blade_mesh` cached once at
  `_ready()` so it can always be restored.
- **Not tinted like the placeholder was** - inspected the imported
  meshes first and found each already has 3 real baked materials (Wood/
  Metal/Dark Metal, flat-colored, no textures needed) - flattening that
  to one damage-type color would look worse than what it replaces, so
  real models keep their own material entirely.
- **Pose tuned by actually looking at it**, not by guessing blind: four
  screenshot iterations (scale 1.0 -> 0.45, rotation guessed wrong twice
  before landing on one where the blade genuinely points up with the
  grip down, position pushed hard toward the bottom-right since the
  original socket offset was tuned for a tiny placeholder box and barely
  moves a life-sized sword's apparent screen position at that distance).
  Landed on a real, presentable "held weapon" pose - not pixel-perfect
  AAA placement, flagged as worth the user's own live nudging for final
  polish rather than more blind iteration.
- Verified via a real scene-load test (5 checks): the real model shows
  and melee still deals damage at the same tuned range, swapping to the
  unmapped pistol correctly restores the tinted placeholder, swapping to
  the dagger shows its own model, and repeated swaps don't leak old
  model instances (exactly `AttackHitbox` + one current model every time).

---

## 2026-08-29 — Real Item Icons + 6 New Items Filling Empty Equipment Slots

User dropped a large batch of purchased/free assets into `assets/`
(1080 files: ~1000 dark-fantasy item icon sprites, 36 low-poly weapon
FBX models, and two full character-animation GLB/FBX libraries with a
rigged mannequin) and asked me to import and use whatever fits.

- **Confirmed Godot 4.7.1 imports FBX/GLB natively** (via ufbx) - no
  Blender/conversion step needed. Ran a full project (re)import (1080
  assets) with zero errors across every category.
- **Real item icons, finally** (`Item.icon_path: String`, not a
  `Texture2D` reference - keeps `ItemSerializer`'s plain-Dictionary
  rolled-item save data JSON-safe). `ItemSlotButton` now shows the icon
  as a child `TextureRect` whenever `item.icon_path` is set, everywhere
  a slot button already existed (inventory grid, paper-doll, shop rows) -
  zero changes needed at any of those call sites, since they all already
  just set `.item = ...`. Falls back to exactly the old colored-square
  look for anything without an icon yet. `ItemCard`'s tooltip also shows
  a small icon next to the title now.
- **Picked icons for all 5 existing hand-authored items** (crude_
  greatsword, padded_coat, guardians_kite_shield, vitality_pendant) by
  actually looking at candidate sprites first, not guessing blindly.
  **`worn_pistol` intentionally has no icon** - this is a dark-fantasy
  icon pack, no firearm exists in it; showing a mismatched sword/wand
  icon for a gun would be worse than the honest color-square fallback,
  so it's flagged as a real gap rather than silently faked.
- **6 new hand-authored items, each with a real icon**, filling
  equipment slots that had *zero* items before this (confirmed by
  listing every `instances/` folder - Helmet/Gloves/Boots/Ring/Belt were
  completely empty, meaning those paper-doll slots could never be
  filled by anything): Worn Dagger (1H melee, Piercing), Battered Helm,
  Worn Gauntlets, Scuffed Boots, Tarnished Ring (+18 Instinct), Frayed
  Belt (+18 Strength). All discovered automatically by `ItemRoller`'s
  existing directory scan - no roller code changes needed, confirmed via
  a 200-roll test that all 6 actually surface as loot.
- **Deliberately did not attempt** the first-person weapon mesh swap
  (FBX models imported cleanly and are ready, but correctly calibrating
  pivot/scale/orientation against `PlayerMeleeAttack`'s already-tuned
  hitbox reach needs real visual iteration I didn't want to rush into a
  broken state) or the character-animation library (a full rigged
  skeleton + `AnimationPlayer`/`AnimationTree` setup is a fundamentally
  new kind of system this project has never had - a much bigger,
  separate undertaking than "wire up an icon"). Both are flagged here
  rather than silently ignored or half-attempted.
- Verified via a real scene-load test (20 checks: every new item loads
  with the right slot + a real loadable icon texture, `icon_path`
  survives an `ItemSerializer` round-trip, `ItemSlotButton` correctly
  shows/hides the icon, the new items equip through the real
  `EquipmentComponent`, and all 6 show up in `ItemRoller` rolls) plus a
  windowed screenshot confirming the icons actually render cleanly in
  both the inventory grid and the equipped paper-doll slots.

---

## 2026-08-29 — Bespoke Cast VFX for Comet, Inferno, Stormcall

User asked for the three ground-targeted spells to have their own
distinct impact effects instead of the generic expanding ring every
ability shares: an ice ball smashing down for Comet, a fire pillar for
Inferno, a lightning strike for Stormcall.

- **`CometImpact`** (`entities/effects/comet_impact/`): an icy sphere
  falls from 8m up (`TRANS_QUAD`/`EASE_IN`, so it accelerates like
  gravity) and lands at the cast point in ~0.32s, then bursts into a
  one-shot `CPUParticles3D` spray of small ice-shard cubes plus the
  existing ring VFX for the ground shockwave.
- **`InfernoPillar`** (`entities/effects/inferno_pillar/`): a
  translucent fire-colored cylinder scales up from nothing to a 4.5m
  column in 0.15s, holds briefly, then fades while overshooting slightly
  taller - plus embers (`CPUParticles3D`, spherical emission, drifting
  upward) bursting from the base.
- **`StormcallBolt`** (`entities/effects/stormcall_bolt/`): a jagged
  bolt - two crossed vertical quads following a randomized zigzag path,
  same ridge-building `SurfaceTool` technique `MountainRange.gd` already
  uses for its silhouettes, just vertical - flashes in and fades in
  ~0.2s total (real lightning doesn't loiter), plus the ring shockwave.
- **Wiring**: `PlayerAbilityCast._play_range_effect()` now looks up
  `ability.ability_id` in a small scene dictionary, falling back to the
  original generic `AbilityRangeEffect` ring for every ability that
  isn't one of these three - untouched otherwise.
- All three VFX are purely visual and don't gate the actual damage
  timing - the hit already lands the instant `_cast()` runs, same as
  before; the fall/rise/flash is a payoff you see for a hit that already
  landed, not a delay before it happens. Flagged in each script's own
  header rather than silently decoupled.
- Verified via a real scene-load test: casting each of the three spawns
  the correct effect class (not the generic ring), and a normal ability
  (Ice Pulse) still spawns the original ring untouched. **Not verified
  visually** - these are sub-second transient effects I can't easily
  catch mid-animation with a screenshot the way a static UI layout can
  be confirmed; the particle counts/colors/timing are unverified in
  practice and worth a look.

---

## 2026-08-29 — Ground-Targeted Spells (Comet, Inferno, Stormcall)

User asked for hold-to-aim targeting on select spells: hold the hotkey,
a ring shows where it'll land, release to cast there.

- **`Ability.is_ground_targeted`** (new field, `true` on comet/inferno/
  stormcall only) - opt-in per ability since most abilities' generic
  self-centered-nova execution doesn't read as "aim a spot."
  `PlayerAbilityCast._on_ability_pressed()` branches on it: a normal
  ability still casts instantly on press (unchanged); a targeted one
  enters an aiming state instead of casting immediately.
- **Targeting ray**: `_get_ground_target_point()` raycasts from the
  camera along its forward direction (this is first-person with a fixed
  center crosshair, so no mouse-position math needed) against the
  physics world - floor, walls, or an enemy's own collision all work as
  a target surface. Aiming at open sky (nothing hit) falls back to
  projecting onto a horizontal plane at the player's own feet height,
  capped at 30m either way so there's always a defined point.
  Re-raycasts every physics frame while held so the ring tracks where
  the camera is currently aimed, not just where it started.
- **Reticle**: a flat `TorusMesh` ring sized to the ability's radius,
  colored by its damage type (reusing the same "flat colored ring"
  language `AbilityRangeEffect`'s cast VFX already established), shown
  on press and hidden on release - not a new visual language, just
  reused.
- **Mana/cooldown are checked and spent on release, not on press** - a
  targeted cast only actually commits once it fires, same as any other
  cast only ever fires once its checks pass. Only one targeting session
  can be active at a time; pressing a second targeted ability's key
  mid-aim is ignored until the first releases.
- `_cast()`/`_play_range_effect()` now take an explicit `cast_position`
  instead of always reading the player's own position - the mechanism
  every ability already shares, just no longer hardcoded to the caster.
- Verified via a real scene-load test (11 checks): holding shows the
  reticle without casting, the reticle tracks an enemy 12m away (well
  outside any self-centered nova's reach), releasing casts exactly there
  and starts the cooldown, and a normal (non-targeted) ability is
  completely unaffected - still fires instantly on press as before.

---

## 2026-08-29 — Riposte Redesign, 5 New Spells, Upgrade Costs, Combat Feel Pass

Large batch: a real Riposte mechanic (previously dead/unused API), a red
flashing "riposte-able" indicator on enemies, 5 new spells across
Fire/Lightning/Entropic, Gold-cost spell upgrades, XP bar layout v2 (full
width, inline text), melee reach/timing tuned further, and faster jump
falls.

- **Riposte, actually wired up for the first time**: `ParryRiposteHandler.
  execute_riposte()`/`can_riposte()` existed since early this project but
  were never called from anywhere (confirmed via a full-project grep) -
  gated on `_riposte_available_target`, only ever set by a successful
  Parry, so an enemy broken by plain attrition damage could never be
  riposted even though `ComposureComponent.is_broken` was already true.
  Redesigned per the user's actual description ("melee attack an enemy
  whose stance is broken to riposte them"): `PlayerMeleeAttack._deal_damage()`
  now checks `composure.is_broken` before rolling a normal hit, and routes
  to `execute_riposte()` instead - 3x motion value, and the damage still
  gets `ComposureComponent`'s existing "+50% damage taken while broken"
  multiplier for free since the break doesn't end until after the hit
  lands. Grants the player 1s of invulnerability
  (`ParryRiposteHandler.is_invulnerable`, checked first thing in `Player.
  take_damage()`) and ends the target's broken state early (consumed, not
  looped). Bigger hitstop/camera-shake than a normal hit for the "finishing
  blow" feel.
- **Red flashing riposte indicator**: `Enemy.gd` builds a small unshaded
  red sphere above the head (hidden by default), shown and blinked via a
  looping `Tween` while `ComposureComponent.is_broken` (new `broken_state_
  started` signal, paired with the existing `broken_state_ended`).
- **5 new spells** (`data/abilities/instances/`): Cinder Lance + Inferno
  (Fire), Static Discharge + Stormcall (Lightning), Entropic Decay
  (Entropic) - same generic-nova execution every ability already uses, so
  no engine code needed beyond authoring the .tres data (9 spells total
  now, up from the single Cold kit).
- **Spell upgrades now cost Gold**: `Ability.get_upgrade_cost()`
  (20 + 15/rank, invented) - `AbilitiesScreen`'s Upgrade button shows the
  cost and disables when unaffordable, not just when maxed. Resolves
  README's old gap #13 ("no cost gating").
- **XP bar v2**: per more specific direction from the user's actual GW2
  reference - spans from just past the level badge to near the right
  screen edge now (not just matching the ability-bar-group's own
  narrower width, which the first pass used), and the XP text sits
  inline on the bar itself (white with a black outline for contrast
  against every gradient color it crosses) instead of floating above it.
  **Found and fixed a real bug while screenshotting this**: the gradient
  texture's `Gradient.colors` was set to 6 colors without also setting a
  matching 6-entry `.offsets` array, leaving it mismatched against the
  default 2-entry offsets - rendered as a garbled/reversed spectrum
  instead of the intended blue-to-red sweep.
- **Melee reach and timing, tuned further**: still short of "should
  strike as far as they should" per the user - blade reach extended
  again (weapon mesh 0.55m -> 0.85m out from the socket, hitbox radius
  0.45 -> 0.55) and windup/strike/recovery cut roughly in half
  (0.2/0.15/0.3s -> 0.1/0.12/0.15s) for a snappier swing-to-ready cycle.
- **Jump falls faster**: `Player._physics_process()` now applies 1.7x
  gravity only while falling (`velocity.y < 0`), not while rising - a
  standard snappier-arc trick that doesn't touch the ascent, so it
  doesn't affect the already-tuned Vault gap-clearing math.
- Verified via two real scene-load tests (13 checks: riposte damage/
  invulnerability/expiry, all 5 new ability ids load, upgrade cost/
  afford-gating/spend-on-upgrade) plus two windowed screenshots (one
  caught the gradient bug above, the second confirmed the fix and the
  new XP bar layout).

---

## 2026-08-29 — Illegible Item-Slot Text (Real Screenshot Diagnosis)

User asked why I couldn't take screenshots to see the game myself. Turns
out this session does have real desktop access (confirmed by capturing
actual screen bounds and a live NVIDIA GPU in a launched process) - not
something to have assumed, and the first attempt over-captured the whole
desktop including private content, which got deleted immediately. Second
attempt (find the Godot window by process name, capture only its own
rect after bringing it to the foreground) worked cleanly and showed the
actual bug: on light item-slot colors (Common-rarity white, some rolled
rarities), the button text was nearly invisible.

- **Root cause**: `_apply_button_color()`-style helpers across the UI set
  a `StyleBoxFlat` background per item/ability/weapon color but never set
  a matching `font_color` - so every colored slot used the same default
  theme text color regardless of how light or dark its background was.
  Confirmed as a systemic copy-pasted pattern, not a one-off: found in
  `InventoryScreen.gd`, `PlayerHUD.gd`'s weapon icon, `AbilityBar.gd`,
  `ShopScreen.gd`, and `AbilitiesScreen.gd` (two call sites).
- **Fix**: new `Constants.get_contrasting_text_color(bg: Color) -> Color`
  (luminance-based black/white pick) called alongside every one of those
  stylebox overrides, setting `font_color`/`font_hover_color`/
  `font_pressed_color` (and `font_disabled_color` where relevant) to
  match.
- Verified two ways: a real scene-load headless run (no errors), and -
  for the first time this session - an actual screenshot of the running
  windowed game showing the fix (dark text now reads clearly against the
  light "Vitality"/"Guardia" slots that were previously illegible).

---

## 2026-08-29 — GW2-Style XP Bar: Below the Ability Bar, Level Badge, Gradient Fill

User shared a Guild Wars 2 screenshot and asked for the XP bar to match
that layout: below the ability bar near the very bottom of the screen,
the player's level shown at the far left, and a multi-color bar instead
of one flat color.

- **Position**: moved from above the Life/Mana orbs + ability bar row to
  below them, in the ~20px gap between that row and the true screen edge.
- **Level badge**: a small square readout sits just left of the bar's own
  left edge (outside its fillable area, not inside it) - GW2 overlaps its
  level circle onto the start of the bar the same way. Updates via the
  same `xp_changed` handler that was already reading `experience.level`,
  since that signal always fires after `ExperienceComponent.add_xp()`'s
  own level-up processing completes.
- **Gradient fill**: `_xp_fill_clip` (`clip_contents=true`, width grows
  with fill fraction) now clips a *fixed-width* `TextureRect` showing a
  `GradientTexture1D` (blue -> teal -> green -> yellow -> orange -> red)
  instead of stretching a texture to fit the growing bar - so the color
  at a given point along the bar stays put as XP fills in, matching how
  GW2's bar actually reveals color rather than remixing it. The exact
  color stops are an invented placeholder spectrum, not a real GW2 color
  match (couldn't inspect their actual asset).
- Verified via a real scene-load test (Hub.tscn, `Player.experience.
  add_xp()`) - badge starts at 1, fill fraction grows correctly, a level-
  up both updates `ExperienceComponent.level` and the badge text, fill
  fraction stays in [0,1] across the rollover. 6/6 checks passed.

---

## 2026-08-29 — Menu Music, Cloud Cover, Moon Fix

User supplied a real track (`assets/music/lament.mp3`) and asked for
clouds in the night sky plus a moon.

- **Menu music**: `MainMenu.gd._play_music()` loads the mp3 at runtime
  (`load()`, not `preload()` - the file had no `.import` config yet
  until Godot's asset pipeline processed it, and `preload()` resolves at
  script parse time, before that's guaranteed), sets `AudioStreamMP3.loop
  = true`, and plays it on a new `MusicPlayer` node. Default Master bus,
  so it already respects the existing volume slider; `volume_db = -10`
  so it sits under the rain/thunder rather than over it.
- **Moon was actually never visible**: `night_sky.gdshader`'s original
  `moon_direction` (0.3, 0.6, -0.5) sat ~50 degrees off the camera's
  forward direction - entirely outside the ~30-degree half-FOV cone, so
  it never rendered on screen despite existing in code. Moved it to
  (0.2, 0.2, -0.95), inside the visible frustum (up and slightly right,
  above the mountain line), and bumped `moon_size` up for a more
  deliberate focal point.
- **Clouds**: added a 4-octave value-noise fbm to the same shader,
  projected onto the same gnomonic sky-plane the stars use, slowly
  drifting via a `TIME`-scaled offset. `cloud_coverage` thresholds the
  noise so higher values mean thicker cloud, not just more of it. Clouds
  occlude the stars/moon underneath them (density scales down their
  contribution) and pick up a lighter tint near the moon's direction, as
  if catching its light on their edges.
- Verified via a real scene-load headless run - shader compiles, music
  loads and plays with no errors. Same benign forced-quit resource
  warnings as before (the abrupt `--quit-after N` kill doesn't free an
  in-progress `AudioStreamPlaybackMP3`/`AudioStreamGeneratorPlayback`
  gracefully; confirmed via `--verbose` that's the entire list, nothing
  else). **Still not verified visually or audibly** - can't confirm from
  here whether the moon's new position/size reads well, the cloud
  density/speed feels right, or the mix level against rain/thunder is
  balanced.

---

## 2026-08-29 — Procedural Night-Storm Main Menu Background + Night Sky Shader

User asked for a Main Menu backdrop: a mountain landscape, rain (visual
+ sound), thunder, and a night sky shader. This project has zero
external art/audio assets anywhere, so everything here is generated at
runtime rather than authored/imported content - consistent with the
rest of the project's placeholder-art convention, just extended to audio
for the first time.

- **Structure**: `MainMenu.tscn`'s old flat `ColorRect` background is
  now a `SubViewportContainer`/`SubViewport` rendering a real 3D scene
  behind the existing 2D menu buttons (which are otherwise completely
  untouched - `MainMenu.gd` needed no changes). A `Vignette` ColorRect
  (30% black, `mouse_filter=IGNORE`) sits between the 3D view and the
  buttons for text contrast.
- **`shaders/night_sky.gdshader`**: a spatial `unshaded` shader on a
  flipped-normals `SphereMesh` skydome - vertical gradient, a hashed
  procedural star field (no texture), a soft moon glow, and a
  `flash_intensity` uniform for lightning.
- **Mountains**: `MountainRange.gd` procedurally builds a jagged
  silhouette "flat" per instance (a `SurfaceTool` ridge strip, unshaded
  flat color, no back/sides) - same layered-cutout trick 2D games use
  for parallax backdrops. Two layers (far/darker, near/lighter) for depth.
- **Rain**: a `CPUParticles3D` emitting thin unshaded translucent box
  streaks from a wide box above the camera, falling with gravity + a
  slight sideways drift.
- **Rain/thunder audio, fully synthesized at runtime**: `ProceduralRain.gd`
  and `ProceduralThunder.gd` push samples into an `AudioStreamGenerator`
  every `_process()` frame rather than playing an audio file - rain is a
  continuous low-pass-filtered white noise wash, thunder is periodic
  (random 14-32s interval) rumble bursts with a fading envelope and a
  heavier low-pass for a deeper tone. Both play on the default Master
  bus, so they already respect the existing `GameState.master_volume`
  slider with no extra wiring. `ProceduralThunder.thunder_started` syncs
  a lightning flash (tweens the sky shader's `flash_intensity` + a brief
  `DirectionalLight3D` energy spike) to the same moment the rumble starts.
- Verified via a real scene-load headless run: shader compiles, no
  script errors, only a benign `AudioStreamGeneratorPlayback` leak
  warning from the abrupt `--quit-after N` process kill (expected -
  same non-issue class as this project's other headless-quit artifacts,
  not a real leak during a normal scene-tree teardown). **Not
  verified visually or audibly** - headless mode can confirm it loads
  and runs without erroring, not what the mountains/rain/sky actually
  look like or the noise/rumble actually sound like. Worth a real look
  and a listen before calling the tuning (colors, mountain proportions,
  rain density, audio levels/timbre) final.

---

## 2026-08-29 — Weapon-Update Bugs, Liquid Orb Fill, Melee Hitbox Reach

User reported the bottom-right weapon indicator and the 3D weapon model
both "don't update properly," the Life/Mana orbs should fill top-to-
bottom instead of sweeping like a clock, and melee "does not properly
hit enemies."

- **Root cause of both weapon-update bugs**: the Primary/Sidearm
  "active weapon slot" toggle (`V` key, `Player._swap_active_weapon()`)
  was left over from before last session's change that moved ranged
  weapons (pistols) into `PRIMARY_WEAPON` alongside melee weapons -
  nothing in the project equips into `SIDEARM_WEAPON` anymore, so
  pressing V (or having previously toggled to it) made both the weapon
  mesh and the HUD indicator show nothing, and equipping a new weapon
  from the Inventory screen never updated the HUD icon at all (it only
  refreshed on the now-largely-dead `V` swap). Removed the toggle
  entirely: `get_active_weapon()` is now just `equipment.primary_weapon`,
  and `EventBus.weapon_swapped` fires from `Player._on_equipment_changed()`
  whenever the active weapon actually changes (tracked via
  `_last_active_weapon`), not just on a manual swap - so both the mesh
  and the HUD indicator update on every real weapon change, and an
  unrelated equip (a ring, armor, etc.) doesn't spuriously re-fire the
  signal. Removed the now-dead `swap_weapon` input action and its README
  documentation.
- **Melee hitbox actually reaches enemies now**: the `AttackHitbox`
  sphere sat essentially AT `WeaponSocket`'s own rotation pivot (offset
  ~0.05m), so the swing's rotation barely moved it in world space
  regardless of the animated arc, and the sphere sat only ~0.6m from the
  camera - short of where an enemy stops to attack (Enemy.stop_distance
  2.3, capsule radius 0.45, i.e. ~1.85m from the camera to its surface).
  Moved `WeaponMesh` (and its child `AttackHitbox`) 0.55m further out
  along the socket's local -Z, both extending base reach to ~1.6-1.9m
  from the camera AND giving the swing's rotation real leverage to sweep
  the hitbox through an actual arc. Bumped the hitbox radius 0.35->0.45
  to match enemy capsule radius. Verified via a real scene-load test
  (Player + HeavyHitter, `try_attack()` at 1.3m/1.9m gaps) - both now
  connect. **Found and fixed a real latent engine error along the way**:
  `_on_hitbox_body_entered()` set `_hitbox.monitoring = false`
  synchronously from inside the hitbox's own `body_entered` callback,
  which Godot disallows ("Function blocked during in/out signal") -
  this error only ever surfaced now because the hit was reliably
  connecting for the first time; fixed with `set_deferred("monitoring",
  false)`.
- **Orb fill direction**: `StatOrb._draw_liquid_fill()` replaces the
  earlier radial pie sweep - computes the exact circular segment below a
  rising/falling waterline (`y = r - 2r*fraction` in local coordinates)
  instead of a clock-style wedge, so the orb drains from the top down
  like a liquid gauge, matching the user's expectation and standard ARPG
  orb HUDs.

---

## 2026-08-29 — Fullscreen Fix, Orb HUD, Wider Stats Panel, Notched XP Bar

User reported the game looks wrong (stretched/wrong aspect) when going
fullscreen, and asked for a HUD redesign: Life/Mana as orbs flanking the
ability bar (Ward as a ring on the Life orb, "HP" renamed "Life"), a
wider stats panel (was visibly truncating text in a screenshot), and an
XP bar with 10%-notch tick marks.

- **Fullscreen aspect fix**: `project.godot` had no `[display]` section
  at all - added one (`window/size/viewport_width/height=1920x1080`,
  `window/stretch/mode="canvas_items"`, `window/stretch/aspect="expand"`)
  so the game scales to fill any monitor's resolution/aspect ratio
  without distortion or black bars, the standard Godot fix for this
  symptom. Untested against the user's actual monitor (no way to drive
  the real windowed game from here) - flag if it's still off.
- **Life/Mana orbs**: new `ui/player_hud/StatOrb.gd` (a `Control` with a
  hand-drawn radial pie fill via `_draw()`/`draw_colored_polygon()` -
  same no-shader placeholder-art convention as everything else) replaces
  the old stacked Health/Mana/Ward bars. Life and Mana orbs now flank
  `AbilityBar`'s slot row at the bottom-center of the screen. Ward
  renders as a colored ring around the Life orb's rim (fills clockwise
  same as the pie) rather than its own bar - visually "on top of" Life
  per the request. "HP" is now "Life" on the orb label.
- **Notched XP bar**: new `ui/player_hud/NotchedBar.gd`, a thin
  `_draw()`-only overlay drawing 9 interior tick lines at each 10%
  boundary, layered on top of the existing fill bar - spans the combined
  width of the Life orb + ability bar + Mana orb, sitting just above them.
- **Wider stats panel**: `InventoryScreen.tscn`'s `StatsPanel` minimum
  width was `230` - too narrow for lines like "Main Hand Crit 100%
  chance / 150% dmg", which were getting cut off at the panel edge (seen
  in the user's screenshot). Widened to `360`.
- **DebugOverlay moved off the stats panel**: same screenshot showed
  `DebugOverlay`'s always-on text overlapping the stats panel's header -
  both were anchored to the top-left corner. Re-anchored `DebugOverlay`
  to the top-right corner instead, out of the way of any left-docked
  screen.

---

## 2026-08-29 — Advanced Tooltips, Inventory Relayout, Weapon-Slot Flexibility, Comment Trim

User asked for an Alt-hover "advanced" tooltip mode, faster tooltips,
equipped items hidden from the inventory grid, a relaid-out
Inventory/Character screen (stats left, grid center, paper-doll right),
Main Hand/Offhand crit display instead of Melee/Ranged, pistols equippable
to the main hand (replacing a two-hander), a shield-render bug fix, and a
project-wide comment-trim pass.

- **Advanced tooltip (Alt-hover)**: new `AdvancedTooltip` autoload
  (`autoloads/AdvancedTooltip.gd`) shows a pinned `ItemCard` that stays
  open until dismissed (`Esc`, an outside click, or its own close
  button) instead of Godot's native hide-on-mouse-leave tooltip - lets
  the player move around and read it. `ItemSlotButton._input()` watches
  for `KEY_ALT` while hovered. `ItemCard.gd`'s `display_item/slate/
  ability()` gained an `advanced` param that adds the close button and,
  for rolled affixes, a full tier range (`ItemAffix.tier/value_min/
  value_max`, now rolled by `ItemRoller` and persisted by
  `ItemSerializer`) plus clickable stat keywords
  (`Constants.STAT_GLOSSARY`) that print the stat's Section 12 per-point
  value inline via `meta_clicked`.
- **Faster tooltips**: `project.godot`'s `[gui] timers/tooltip_delay_sec`
  dropped from Godot's default `0.5` to `0.15`.
- **Inventory relayout**: `InventoryScreen.tscn` is now a 3-column
  `StatsPanel | InventoryPanel | PaperDoll`, so equipping something
  shows the stat change immediately without switching screens. The new
  stats column is shared with `CharacterScreen` via `StatSummaryBuilder.gd`
  (`ui/character_screen/`) rather than duplicated logic in each screen.
  Anything currently equipped is filtered out of the grid entirely -
  it only shows on the paper-doll.
- **Main Hand / Offhand crit display**: `StatSummaryBuilder` now reports
  Main Hand/Offhand Damage + Crit (keyed by equip slot) instead of
  Melee/Ranged - ranged weapons in the main hand now show a real crit
  line, which they previously had none of.
- **Pistols equip to the main hand**: added `Weapon.is_ranged: bool`,
  decoupling melee/ranged attack dispatch from equip slot.
  `worn_pistol.tres`'s `equip_slot` moved from Sidearm to
  `PRIMARY_WEAPON`, so equipping it naturally displaces a two-handed
  weapon via the existing single-slot-replacement rule - no special-case
  code needed. `PlayerMeleeAttack`/`PlayerRangedAttack`/`Player._physics_process()`
  now dispatch off `get_active_weapon().is_ranged` rather than a
  hardcoded slot.
- **Shield-not-rendering-on-first-equip, fixed**: `_update_shield_mesh()`/
  `_update_active_weapon_visual()` were only ever called from
  `Player._ready()` and weapon-swap, never from an ordinary mid-session
  equip via the Inventory screen. Wired into `Player._on_equipment_changed()`
  (already listening to `EquipmentComponent.equipment_changed`), so any
  equip now refreshes both visuals.
- **Comment trim**: pass across the highest-comment-density files in the
  project (`item_roller.gd`, `Player.gd`, `Enemy.gd`, `GameState.gd`,
  `Constants.gd`, `EquipmentComponent.gd`, `PauseMenu.gd`, `MapGraph.gd`,
  `PlayerHUD.gd`, `SaveManager.gd`, and ~20 more) - condensed multi-
  paragraph header comments and inline asides down to concise WHY-only
  notes, no functional changes. Verified via a full class-cache rebuild
  and real scene-load checks on `MainMenu`/`Hub`/`GeneratedMap`/
  `TestArena` afterward.

---

## 2026-08-29 — Stat Wiring, Critical Strikes, Tiered Affixes, Crouch/Slide, Player Jump Fix

User asked to review the six stats and "actually plug them in," build
tiered rolled-stat affixes, add crouch/slide, and fix the player's jump
(a specific room type - the Vault - was impossible to enter). Converted
both design PDFs to `.docx` and extracted plain text via `unzip` +
`sed` (PDF text search had been unreliable) to check what the docs
actually specify before inventing anything - Section 12 "Stat System"
turned out to have a complete "Six Stats — Per Point Values" table and a
full Critical Strike System with exact per-weapon-type base values, none
of which had been read before this session.

- **Real conflict found and resolved with the user**: Section 12 states
  explicitly *"All stats come from gear, Slates, Jewels, and infusions —
  no manual allocation on level up."* The previous session had built
  exactly that (a level-up stat-point-spending UI on the Character
  Screen). Asked the user directly rather than silently overriding
  either the doc or the earlier work; they chose doc-accuracy. Removed
  `StatSheet.unspent_points`/`allocate_point()`/`STAT_POINTS_PER_LEVEL`/
  `POINT_VALUE` entirely, along with the now-dead `GameState.
  saved_stat_sheet_data` persistence path it needed (raw stat values
  never change post-spawn anymore, so there's nothing to save/restore -
  `player_baseline.tres`'s flat defaults are permanently fixed). Leveling
  still exists (invented XP curve, already flagged) but no longer grants
  anything mechanical - `GameState.player_level` now doubles as a rough
  "how strong should this loot be" signal for the Hub's GearShop, which
  has no Map-tier context of its own to use instead.
- **Gear is now the real (and only) source of stat growth.**
  `EquipmentComponent.compute_stat_bonuses()` sums every equipped item's
  `flat_<stat>` affixes into a `Constants.Stat -> float` total; a new
  `equipment_changed` signal (fired on every successful equip()/
  unequip()) drives `StatSheet.set_equipment_bonus()` via `Player.
  _on_equipment_changed()`, so `StatSheet.get_stat()` always reflects
  current gear without any caller needing to know that.
- **Vitality/Instinct/Intellect actually do something now** (Section 12
  per-point values, doc-exact): Vitality -> `+2 Life`/point +
  `+0.1 Life regen/sec`/point (new `HealthComponent.regen_per_second` +
  `_process()` tick, plus `set_max_health()` that heals by the delta on
  an increase rather than just inflating the denominator). Intellect ->
  `+2 Mana`/point + `+0.1 Mana regen/sec`/point (on top of
  `ManaComponent`'s existing flat base regen). Instinct -> Action Speed,
  split by doc-given per-type rates: `+0.5%` Move speed/point
  (`Player.get_move_speed_multiplier()`), `+1%` Attack/Cast speed/point
  (`Player.get_action_speed_multiplier()`, divides
  `PlayerMeleeAttack`'s windup/strike/recovery, `PlayerRangedAttack`'s
  fire cooldown, and Ability cooldowns - faster gear-tuned characters
  attack more often, not just deal more damage per hit). Deferred,
  flagged: Vitality's Resilience/DoT mitigation, Instinct's Stamina pool
  + dodge-roll/Active-Blocking, Intellect's Debuff effectiveness - none
  have a supporting system built (no DoT/status-effect system, no
  Stamina mechanic, no debuff-magnitude system), so there's nothing yet
  for that part of the stat to modify.
- **Critical Strike System** (`DamageCalculator.get_crit_chance()`/
  `get_crit_damage_multiplier()`/`apply_crit()`/`get_expected_damage()`),
  doc-exact: base crit chance fixed per weapon/spell type (2%-8% per the
  doc's own table; `Constants.WEAPON_BASE_CRIT_CHANCE` keyed by
  `weapon_type` string, transcribed for the 2 weapon types this project
  actually has - Greatsword 4%, Service Pistol 6%, both confirmed exact
  matches to the doc), multiplied by Instinct (+3%/point); 150% base
  crit damage, multiplied by Intellect (+1%/point). `Weapon`/`Ability`
  each gained `roll_damage()` (an actual random crit roll, used by real
  attacks/casts - each `PlayerAbilityCast` AoE target rolls
  independently, not one shared roll for the whole nova) alongside the
  existing `predict_damage()` (now an expected-value blend via
  `get_expected_damage()`, so the stat card shows one stable number
  instead of jittering between two on every hover). `EventBus.
  damage_dealt` gained an `is_critical` parameter; `DebugOverlay` tags
  crits `[CRIT]` in its combat log. Ability crit chance is thematic
  guesswork (abilities don't carry the doc's "spell type" classification
  since all 4 still execute as a generic nova - flagged, pre-existing
  gap).
- **Tiered rolled affixes** (`ItemRoller.gd`): 5 tiers per affix, Tier 1
  best, each tier's range ~80% of the tier above - loosely modeled on
  the doc's own mod-tier tables' shape (e.g. Section 16's Flat Armor Mod
  Tiers has 11 real tiers with a comparable step-down), though this
  project uses one consistent tier count for every affix rather than
  transcribing each mod's real doc table. Which tier a roll can reach is
  gated by a new `power_level` parameter (the active Map's `tier` in
  real gameplay, player level as a Hub-only fallback for GearShop stock)
  - entirely invented gating, the doc defines tier ranges but never what
  unlocks access to them. Also fixed rarity -> affix count to match
  Section 18's real table exactly (was `1/2/3` fixed; now Common always
  `0`, Uncommon `0-2`, Rare `0-6`, matching the doc's own "Rarity
  determined by base quality, not affix count" - a Rare item genuinely
  can roll with few or no affixes now).
- **Loot/equipment persistence extended to full item data.**
  `data/items/item_serializer.gd` (`to_dict()`/`from_dict()`, branches
  on a stored `"class"` tag since GDScript static funcs aren't
  polymorphic) already existed from last session for `owned_loot`;
  `EquipmentComponent.get_all_equipped_paths()` (String-only) became
  `get_all_equipped_refs()` (String path OR Dictionary per slot) so
  equipping a *rolled* item with real stat affixes actually keeps
  contributing its stat bonus across scene transitions and saves, not
  just showing up in inventory.
- **Crouch & Slide** (user-requested, no doc-sourced design for either):
  hold Ctrl to crouch - `CollisionShape3D`'s `CapsuleShape3D.height`
  smoothly interpolates down (`move_toward`, anchored at the feet so it
  shrinks from the top, not centered - otherwise crouching would sink
  the player into the floor), camera lowers to match, move speed drops.
  Tap Ctrl while sprinting and moving to slide instead - launches along
  the current heading at `SLIDE_SPEED` (or current sprint speed if
  faster), decelerating to crouch speed over `SLIDE_DURATION`; jumping
  or leaving the floor cancels it immediately; ends into a crouch if
  Ctrl is still held, otherwise stands back up. No headroom/ceiling
  check on standing up - every generated room is a simple open box,
  nothing low enough to clip into yet, flagged for whenever that
  changes.
- **Player jump fix**: `Player.jump_velocity` bumped `4.5 -> 7.0` -
  the actual root cause of "a certain room type stops us from entering"
  (the Vault): its jump gap (3m) + raised platform (1.2m) needs the
  jump arc to have risen 1.2m by the time the 3m gap is crossed, not
  just enough hangtime×speed to cover the horizontal distance -
  math showed 4.5 fell meaningfully short even at full sprint. Matches
  the value `Enemy.jump_velocity` was already independently tuned to
  last session for the identical reason - confirmed via a real-scene
  headless test (driving actual `sprint`/`move_forward`/`jump` Input
  actions, not teleporting) that both walking and sprinting now clear it
  with real margin, across 6 consecutive random Vault placements.
- Verified via two real-scene-load test runners (16 + 1 checks, all
  passing): gear-derived Vitality/Intellect/Instinct bonuses apply and
  revert correctly on equip/unequip, the Crit System's observed crit
  rate and average rolled damage both match their theoretical values
  within statistical tolerance over hundreds of trials, rarity/affix-
  count/tier-gating all match their intended tables, crouch shrinks the
  collision capsule, sprint+crouch+moving triggers a slide that
  decelerates and ends correctly, and the player jump clears the Vault.

## 2026-08-29 — Loot Persistence, GearShop Restock, Gold Drops, Stat Allocation

User picked four items off a backlog offered at end of the previous
session, in order: fix rolled-loot/equipment persistence, GearShop
restock, gold as a real drop instead of an instant grant, and stat
allocation.

- **Rolled-item/equipment persistence fixed.** New
  `data/items/item_serializer.gd` (`ItemSerializer.to_dict()`/
  `from_dict()`) serializes an Item's full data (base fields +
  Weapon/Armor/Shield-specific fields + affixes), branching on a stored
  `"class"` tag since GDScript static funcs aren't polymorphic.
  `EquipmentComponent.get_all_equipped_paths()` (String-only) became
  `get_all_equipped_refs()` (`Array` of String *or* Dictionary per
  slot - a path for hand-authored items, a full `ItemSerializer` dict
  for anything with an empty `resource_path`, i.e. rolled loot).
  `GameState.equipment_paths` renamed `equipment_refs` to match;
  `Player._apply_saved_loadout()` now branches per entry instead of
  assuming everything is a loadable path.
  `GameState.owned_loot`/the equipped-rolled-item case are now both
  covered by `SaveManager` (previously `owned_loot` wasn't saved to disk
  at all, and an equipped rolled item silently reverted to empty on the
  very next Hub<->Map scene transition, not just an app restart, since
  `Player._apply_saved_loadout()` runs on every scene load). Verified
  via a real-scene-load test: equipping a rolled item produces a
  Dictionary ref, `owned_loot` and the equipped ref both survive an
  actual `SaveManager.save_game()`/`load_game()` round trip, and calling
  `_apply_saved_loadout()` again correctly reconstructs the rolled item
  from scratch.
- **GearShop restock**: `ShopScreen.open_with()` gained an optional
  `action` parameter (a single button above the item list, distinct from
  per-item "Buy" - GearShop's "Reroll Stock", invented `15` Gold).
  SpellTestShop doesn't pass one (nothing to reroll there). Verified the
  button deducts Gold and the stock array is actually different
  afterward, not just re-displayed.
- **Gold drops as visible pickups**: new `entities/pickups/gold_pickup/`
  (`GoldPickup.gd`, same auto-pickup-on-touch/bob-and-spin convention as
  `LootPickup.gd`, placeholder spinning coin mesh). `Enemy._drop_gold()`
  now spawns one instead of `GameState.gold += gold_reward` running
  instantly and invisibly on death. Verified Gold is genuinely 0 right
  after a kill and only changes once the pickup is actually touched.
- **Stat allocation**: `StatSheet.get_stat()` no longer auto-adds
  `(level-1) * STAT_GROWTH_PER_LEVEL` to every stat - leveling now
  grants `unspent_points` (`STAT_POINTS_PER_LEVEL`, invented `3`/level)
  instead, spent via the new `StatSheet.allocate_point(stat)`
  (`POINT_VALUE`, invented `+4`/point) on whichever of the 6 stats the
  player picks. `CharacterScreen.gd` shows an "Unspent Stat Points: N"
  label and a "+" button next to each of the 6 stat lines whenever
  `unspent_points > 0`, refreshing in place on click. Needed its own
  persistence path since `StatSheet` had none before this: `to_dict()`/
  `apply_dict()` + `GameState.saved_stat_sheet_data` (same "GameState
  holds raw data, Player applies it at `_ready()`" pattern equipment/
  ability loadout already use), and `GameState.reset_to_defaults()`
  explicitly resets `player_baseline.tres`'s mutated fields back to
  their authored defaults on New Game (same shared-cached-Resource
  gotcha `Ability.rank` already needed this treatment for). Verified
  leveling grants points, `allocate_point()` raises only the targeted
  stat by exactly `POINT_VALUE` and leaves the others untouched, the
  Character Screen shows the button, and the full stat sheet (allocated
  values + level + unspent points) round-trips through an actual
  save/load.
- All four verified together via one real-scene-load test runner (see
  `reference_godot_headless_verification` in project memory for why
  that method over `--script` mode) - 12 checks, all passing.

## 2026-08-29 — Map Screen, Skill Tomes, Gold, Shops

User asked for four things together: a Map screen (`M`), removing the
free starting spells in favor of lootable Skill Tomes, a Hub gear shop,
and a free "every spell" shop for testing.

- **Map screen** (`ui/map_screen/`, hotkey `M`/`open_map`): `MapView.gd`
  (a `Control` with its own `_draw()`) renders `GeneratedMap.graph`
  directly as a room grid with connection lines, colored by role
  (start/vault/normal) with the player's current room outlined -
  `MapScreen.gd` just owns open/close/hotkey state and resolves
  `get_tree().current_scene` to a `GeneratedMap` each time it opens.
  Shows "No map data" in the Hub/TestArena (static hand-built scenes,
  no graph) instead of erroring. Dispatched from `PauseMenu.gd`'s
  existing central hotkey handler, same as P/B/N/C.
- **Abilities are no longer free at game start.** Per Patch v3.1's Skill
  System replacement ("skills come exclusively from loot-dropped Skill
  Tomes... not an allocatable node web"),
  `GameState.DEFAULT_ABILITY_LOADOUT_PATHS` is now 4 empty strings
  instead of the old hardcoded Cold kit, and `AbilitiesScreen.gd`'s
  "owned" list is filtered to `GameState.owned_ability_ids` instead of
  showing every `.tres` under `data/abilities/instances/` as a free
  "owns one of each" stand-in. New `data/abilities/skill_tome.gd`
  (`SkillTome extends Item`) + `data/abilities/tome_roller.gd`
  (`TomeRoller.roll_for_unowned()`, synthesizes a Tome referencing a
  random ability the player doesn't already own - no pre-authored Tome
  `.tres` files needed). `Enemy._maybe_drop_loot()` gained an
  independent, flat invented `8%` Tome-drop check (separate from the
  existing gear-drop roll) before the existing gear-drop roll;
  `LootPickup.gd` branches on `item is SkillTome` to unlock the ability
  into `GameState.owned_ability_ids` instead of adding to
  `GameState.owned_loot`. **Does not implement the doc's literal
  "socketed into weapon slots" mechanic** - there's no functioning
  socket system anywhere in this project - just the acquisition half,
  flagged in the README.
- **Gold**: new invented currency (`GameState.gold`), no doc-sourced
  economy exists anywhere in this project (Ability upgrading/Map
  affixes were already flagged as free/uncosted before this).
  `Enemy.gold_reward` (per-archetype, same relative-toughness scaling as
  `xp_reward`) grants it on death. Persisted by `SaveManager` (a plain
  int, no path-serialization problem like rolled Items have). Shown on
  `PlayerHUD` via a small polled label (no natural `*_changed` signal
  source, same tradeoff `AbilityBar`'s cooldown readout already makes).
- **GearShop** (`entities/interactables/gear_shop/`) and **SpellTestShop**
  (`entities/interactables/spell_test_shop/`): two new Hub interactables,
  same walk-up-and-`E` proximity pattern as the Map Device. GearShop
  rolls 6 `ItemRoller` items once per Hub visit, priced by rarity
  (invented `COST_BY_RARITY`), bought items removed from that visit's
  stock (no restock mechanic yet). SpellTestShop lists every ability for
  free - an explicit debug/testing tool per direct user request, not
  designed game content, bypassing the Tome-drop acquisition path
  entirely. Both share one new generic `ui/shop/ShopScreen.gd`
  (`open_with(title, entries)`, each entry a label/cost/color/callback +
  optional Item/Ability for the `ItemSlotButton` hover tooltip) instead
  of each building its own list UI.
  - **Bug found and fixed**: both shop interactables cached their
    `ShopScreen` reference via a `get_first_node_in_group()` lookup in
    their own `_ready()` - but they're declared *before* `ShopScreen` in
    `Hub.tscn`, and Godot readies siblings in declaration order, so the
    lookup always found nothing (same bug class as this project's
    `@onready` parent/child timing issues, just between siblings this
    time - see `feedback_godot_onready_timing` in project memory). Fixed
    by resolving it lazily on first actual use instead of caching a
    possibly-stale `_ready()`-time reference.
- **Testing note**: the `--script`-mode SceneTree headless harness this
  project normally uses for quick tests showed much worse autoload
  compile-ordering noise than usual this session (nearly the whole
  project's scripts failing to compile on the first pass, not just the
  documented benign one-or-two-line quirk) once the test script declared
  many new custom-class-typed variables (`GearShop`, `ShopScreen`, etc.)
  - static type annotations force GDScript to eagerly compile the
    referenced class, which transitively touches `GameState`/`EventBus`
    much earlier and more broadly than a `load()` call alone does.
    Switched to the more reliable method this project's own reference
    memory already recommends for anything beyond a trivial check: a
    real scene (`[gd_scene]` instancing the actual Hub/GeneratedMap with
    a small test-runner script as a child) loaded via
    `--path . res://test_scene.tscn`, not `--script`. This also caught a
    real, unrelated finding: a stale `user://savegame.json` on this dev
    machine (leftover from earlier test sessions, matching XP/level
    values from that testing) was loading 4 old default abilities at
    boot, which looked like a bug in the "zero starting abilities"
    change until checked against `MainMenu.gd`'s actual New-Game reset
    flow - the save file was cleared for a clean test, not a game bug.
- Verified via the real-scene-load test runner: zero abilities equipped
  at a fresh boot, a Tome drop + pickup correctly unlocks exactly one
  ability (and only that one shows in `AbilitiesScreen`), a GearShop
  purchase deducts the right Gold and adds the item to `owned_loot`,
  SpellTestShop grants every ability for free without touching Gold, and
  MapScreen correctly distinguishes "real graph data" (`GeneratedMap`,
  resolved player cell) from "no data" (Hub).

## 2026-08-29 — Item/Loot Generation

Third piece of the user's combined ask this session ("item generation
for loot and maps"). Map-item rolling already existed (`MapRoller.gd`,
an earlier session); this closes the actual gear-loot half.

- **`data/items/item_roller.gd`** (new, mirrors `MapRoller.gd`'s
  shape): `ItemRoller.roll(loot_rarity_multiplier)` duplicates a random
  existing hand-authored base item (weapon/armor/shield/accessory) and
  re-rolls only its rarity + a fresh affix list, rather than building a
  fully procedural item-shape system — Item.gd's own header already
  flagged full procedural rolling as deferred design before this pass,
  and every hand-authored item's affixes were already descriptive-only
  (no gear-affix aggregation into `StatSheet` exists anywhere in this
  project), so rolled ones being the same isn't a new gap. Rarity odds
  shift with `loot_rarity_multiplier` — this finally makes that MapItem
  field do something; it (and `loot_quantity_multiplier`) were
  previously tracked on rolled Maps but completely inert.
- **`entities/pickups/loot_pickup/`** (new): a floating/bobbing
  placeholder sphere colored by rarity, auto-picked-up on touch (a
  judgment call — fits how often gear drops during combat better than a
  keypress/prompt flow like the Map Device's, but is a different UX
  pattern than that). `Enemy.gd` gained `xp_reward`'s loot counterpart:
  a `_maybe_drop_loot()` call in `_on_died()`, invented 35% base chance
  scaled by `loot_quantity_multiplier`, spawning one `LootPickup` at the
  death position when it hits.
- **`GameState.owned_loot: Array[Item]`**: session-only pool of picked-up
  rolled items. `InventoryScreen` now rebuilds its grid every time it
  opens (previously built once at `_ready()`) so newly picked-up loot
  actually shows up, combined with the existing directory-scanned
  hand-authored "owns one of each" stand-in items — same click-to-equip
  flow either way, `EquipmentComponent.equip()` doesn't care where an
  Item came from.
  - **Flagged, not fixed**: rolled loot doesn't survive a Hub<->Map
    scene transition or save/reload once equipped. `Resource.duplicate()`
    (what `ItemRoller.roll()` uses to avoid mutating the shared cached
    base) produces a Resource with no `resource_path`, and
    `SaveManager`'s entire equipment-persistence mechanism
    (`GameState.equipment_paths`) only knows how to round-trip items by
    path — an equipped rolled item silently reverts to empty on the next
    transition, same as any item with an empty path would. Fixing this
    for real needs `SaveManager` to serialize full item data, not just a
    path - a bigger persistence-format change than this pass's scope.
  - `DebugOverlay` now also logs loot drops (item name + rarity) and
    level-ups, alongside its existing damage/chain/ability log lines.
- Verified with a headless test: 200 rolls all produced valid
  items (non-empty id/name, no `resource_path`, well-formed affixes)
  with a real rarity spread; a higher `loot_rarity_multiplier`
  measurably skewed the average rolled rarity upward over 150 rolls
  each; killing enough enemies reliably spawned at least one
  `LootPickup`; walking into one added it to `GameState.owned_loot` and
  freed the pickup; `InventoryScreen`'s grid, once (re)opened, actually
  contained a button for the picked-up item.

## 2026-08-29 — XP, Leveling, Stat Growth

User asked to "start working on the RPG part of this more" — experience,
leveling, and stat gain, alongside gap-jumping and loot generation.

- **`entities/components/ExperienceComponent.gd`** (new, attached to
  `Player.tscn`): `level`/`xp` fields, `add_xp()` loops (not a single
  `if`) so one large gain can cross multiple level thresholds in a
  single call, `leveled_up`/`xp_changed` signals. XP curve
  (`XP_BASE=100`, 25% growth per level) is invented — no leveling system
  is doc-sourced anywhere in the referenced sections.
- **No stat-allocation UI was built.** "Gain stats" is implemented as
  automatic flat growth to every `StatSheet` stat per level
  (`StatSheet.level` + `STAT_GROWTH_PER_LEVEL`, baked into
  `get_stat()`) rather than spendable points — the simplest
  interpretation that fits the ask without inventing a whole allocation
  screen in the same pass. A real allocation UI is natural follow-up
  work, not a scope gap being hidden.
- **`Enemy.gd` gained `xp_reward`** (invented, loosely scaled by
  archetype toughness: `HeavyHitter` 25, `MobileBruiser` 18,
  `GlassCannon` 12), granted to the player on `_on_died()`.
- **Cross-scene persistence**: same problem equipment/ability loadout
  already solved — `Player` is a fresh instance every Hub<->Map scene
  load, so `GameState.player_level`/`player_xp` mirror the live
  `ExperienceComponent` (written on every XP change, read back at
  `Player._apply_saved_experience()`), and `SaveManager` now persists
  both across app restarts too.
- **UI**: `PlayerHUD` gained a 4th bar ("Lv N - current/needed XP",
  reusing the existing bar-builder helper). `CharacterScreen`'s Misc
  column now shows Level and XP.
- Verified with a headless test: a single `HeavyHitter` kill grants
  exactly its `xp_reward`, `GameState` correctly mirrors the live
  component, enough kills to cross 100 XP actually leveled the player
  up, `STRENGTH` (and every other stat) measurably increased afterward
  via `stat_sheet.get_stat()`, and `stat_sheet.level` stayed in sync
  with `experience.level`.
  - Minor harness-only hiccup while writing this test, not a game bug:
    a `preload()` for an Enemy-derived scene resolves at *compile time*,
    which in this headless `--script`-mode runner happens before
    autoloads (`GameState`/`EventBus`) are registered — cascaded into
    `Enemy.gd` itself failing to compile. Switching to a runtime
    `load()` inside the test function fixed it; a real scene-file load
    (`--path . res://Scene.tscn`, how the actual game boots) was
    unaffected the whole time. See
    `reference_godot_headless_verification` in project memory.

## 2026-08-29 — Doorway Floor Gaps, Enemy Gap-Jumping

User reported "enemies falling to their death more than dying to me."
Two separate bugs turned out to be involved, plus a design gap in the
jump-arc math discovered while verifying the fix.

- **Bug found: every doorway in every generated Map had a missing floor
  segment, not just the Vault's intentional jump gap.** `ROOM_FOOTPRINT`
  (13m) is smaller than `CELL_SIZE` (16m, the spacing between adjacent
  rooms) — walls correctly opened a doorway-width gap, but nothing was
  ever built to bridge the resulting 3m floor gap between two connected
  rooms' footprints. This is almost certainly the primary cause of the
  report: chasing through *any* doorway dropped an enemy (or the player)
  into an unfloored void with no safety net, on every single connection
  in every generated layout. Fixed with a new
  `GeneratedMap._build_doorway_bridges()` that builds one floor bridge
  per connection, sized to exactly close the gap (each connection
  processed once via a canonical pair key, not twice from both rooms'
  side). Verified with a dedicated raycast-based test sampling 5 points
  along the doorway path for all 74 connections across 10 random
  layouts — all confirmed solid floor after the fix (none were, before
  it).
- **Enemy gap-jump behavior**: `Enemy.gd` had no awareness of gaps at
  all before this — chasing an enemy across the Vault's intentional
  jump gap just walked it straight off the edge. New
  `_check_gap_jump()` probes ahead with a raycast; if the floor ahead is
  missing, it ray-marches forward to measure the actual gap width *and*
  the landing floor's height (not hardcoded — stays correct if gap
  sizes or platform heights ever change), then solves the real
  projectile-motion question: given this archetype's `move_speed` and
  `jump_velocity`, does the arc's height at the moment it reaches the
  far edge clear the landing height, with margin? If yes, it jumps
  (`velocity.y = jump_velocity`); if not, it stops at the edge instead
  of walking off it. `jump_velocity` (7.0, up from an initial guess of
  5.5) is invented, tuned specifically against the Vault's 3m gap + 1.2m
  platform rise via testing (see below) — HeavyHitter (`move_speed`
  1.8) still correctly can't clear it even at this value, since its
  bottleneck is horizontal speed, not airtime.
  - **Bug found while first testing this: mid-air kiting reversal.**
    `_update_chase()` recalculated horizontal velocity every physics
    frame unconditionally, including mid-jump — so a kiting enemy
    (`retreat_distance > 0`, i.e. `GlassCannon`) sailing across a gap
    would have its distance-to-player shrink mid-flight, cross into
    retreat range, and get its horizontal velocity reversed *while
    airborne*, steering it back over the open gap instead of landing.
    Fixed with a `_gap_jumping` flag that suppresses chase/retreat
    velocity recalculation until the enemy is back on the floor.
  - **Design gap found via testing, not a bug in the fix above: the
    original jump check only verified horizontal clear distance,
    ignoring that the Vault's platform sits 1.2m higher than the main
    floor.** Enemies fast enough to cross the gap horizontally were
    still below 1.2m of arc height by the time they reached the
    platform's edge, so they slammed into its vertical face mid-flight
    and got knocked back instead of landing — repeating the same failed
    attempt indefinitely. Rewrote the check to solve for arc height at
    the landing point's actual horizontal distance and compare against
    the *measured* rise (works for a drop, a rise, or level ground, not
    just this one gap), and raised `jump_velocity` so the "Fast"
    melee archetype (`MobileBruiser`) can actually clear it — a ranged
    kiter (`GlassCannon`) never needs to, since it fights from range
    and correctly just holds at its own `stop_distance` short of the
    edge instead.
  - Verified with a dedicated headless test across 8+ random Vault
    placements: `HeavyHitter` always correctly blocked at the edge,
    `MobileBruiser` always correctly clears the gap and lands safely,
    `GlassCannon` always correctly holds at range without needing to
    cross — none of the three ever fall through the world. Getting a
    trustworthy version of this test took several iterations: an
    initial version compared a world coordinate against a room-local
    offset without adding the room's origin; a version placing all
    three enemies on the same X line let the one that stops earliest
    (`GlassCannon`) physically block the others approaching from
    behind, which looked exactly like a failed jump but was really
    enemies colliding with each other (fixed by giving each its own
    spawn lane); and the map's own auto-spawned enemies (every
    non-start room gets some, the Vault gets extra) could stand in a
    controlled test enemy's path too (fixed by clearing them before
    placing the controlled ones).

## 2026-08-29 — Procedural Map Generation

User asked for "properly generated maps that feel different, with walls,
jumps, interesting things that pop up," followed by asset import as a
separate next phase.

- **`systems/level_generation/MapGraph.gd`**: pure-data room-and-
  connection graph, no `Node3D`/geometry at all — deliberately separated
  from the geometry builder so the generation *algorithm* can be tested
  in complete isolation, and so a later asset-import pass only has to
  change how rooms are rendered, never how they're laid out. Randomized
  Prim's-style spanning-tree growth from a start cell on a 5x5 grid
  (`ROOM_COUNT_MIN`/`MAX` 7-10) — guarantees every room is reachable
  since it *is* a spanning tree. The room with the greatest graph
  distance from start becomes the Vault (denser enemies + a jump
  platform). Verified with a 200-trial stress test: room count in range,
  full BFS reachability, every connection symmetric and to an orthogonal
  grid neighbor only, vault always distinct from start.
- **`levels/generated_map/GeneratedMap.gd`**: turns the graph into actual
  geometry — `BoxMesh`/`PlaneMesh` placeholder primitives (no real art
  yet), real `StaticBody3D` collision on every wall/floor. Each room
  boundary is either a solid wall or has a centered doorway gap where a
  connection exists. The Vault room's floor splits into a main section
  (y=0) and an elevated platform (y=1.2), separated by a jump gap, with a
  full-footprint safety floor a shallow 0.5m below the whole room so a
  missed jump is a small stumble, not a fall through the world — a
  deliberate safety margin given none of this can be visually playtested
  here. `GameState.MAP_SCENE` now points here instead of
  `TestArena.tscn`, which stays in the repo as a static hand-built
  sandbox for direct editor testing.
- **Bug found: `is_connected(a, b)` collided with `RefCounted`/`Object`'s
  built-in `is_connected(signal, callable)`**, which Godot rejects as an
  incompatible override — a hard compile error caught immediately by the
  first headless test run. Renamed to `has_connection()`.
- **Bug found and fixed before it ever shipped: UI would have found a
  null Player on every generated map.** `GeneratedMap`'s root script
  spawns `Player` from its own `_ready()`, but Godot readies children
  *before* parents — so if the UI suite (`AbilityBar`, `PlayerHUD`, etc.)
  were static `.tscn` children like `Hub.tscn`/`TestArena.tscn` use,
  every one of them would run its own one-time
  `get_tree().get_first_node_in_group("player")` lookup *before* the
  parent's `_ready()` ever got to spawn the Player — since the Player's
  spawn position depends on the generated layout and can't be known
  until generation runs. Caught by reasoning about the ordering before
  ever testing it (same bug class as three earlier ones this project has
  hit), not by a failing test. Fixed by instantiating the entire UI suite
  in code instead of as static scene children, added via `add_child()`
  strictly *after* `_spawn_player()` — a node added to an already-live
  tree runs its `_ready()` synchronously as part of that `add_child()`
  call, so by the time each UI script's lookup runs, the Player already
  exists and is already in the `"player"` group. Verified directly: a
  15-trial test confirmed `AbilityBar`/`PlayerHUD` both found a valid
  Player reference on every trial, across 15 different random layouts,
  plus a real physics shape-overlap query confirming the player spawn
  point never lands inside a wall's collision shape.

## 2026-08-29 — Documentation Cleanup

User asked for the README to be cleaned up and a dedicated patch-notes
file created to track changes going forward. `README.md` had grown to
over 1000 lines as a de facto changelog (every bug's root cause, every
judgment call's full reasoning, appended chronologically) — split into
this file (the history) and a rewritten `README.md` (~200 lines, current
state only: what's implemented, flagged gaps, controls, how to open the
project). Flagged-gap numbers were renumbered in the process — resolved
gaps were dropped rather than kept as strikethrough clutter.

## 2026-08-29 — Character Screen, Predicted Damage, Ability Range VFX

- **Character Screen** (user-requested): `ui/character_screen/`, opens
  via a new hotkey (`C`). Three columns, as asked — Offense (Strength/
  Arcane/Enigma, Predicted Melee/Ranged Damage), Defense (Vitality/
  Instinct, Max Health, Max Ward, Armor), Misc (Intellect, Max Mana,
  Move/Sprint Speed, Mastery bonuses/Supercharged stat if set). The
  screen's hint text says outright that only Strength/Arcane/Enigma
  actually drive anything (`Constants.DAMAGE_TYPE_MAIN_STAT`) —
  Vitality/Instinct/Intellect are shown (the user asked for "all of the
  player's stats") but aren't wired to any formula anywhere in the
  project; hiding them would've just been a different kind of dishonesty
  than showing them without the caveat. Confirmed by grepping the whole
  project for every use of `Constants.Stat.VITALITY`/`INSTINCT`/
  `INTELLECT` before building this — only `StatSheet.get_stat()` itself
  references them.
- **`Weapon.gd` gained `predict_damage(motion_value, stat_sheet)`**,
  mirroring `Ability.predict_damage()`. `PlayerMeleeAttack._deal_damage()`/
  `PlayerRangedAttack._fire()` were refactored to call it instead of each
  inlining the same `DamageCalculator` wiring — verified end-to-end with
  a headless test that actual melee damage dealt matches the predicted
  number exactly (`54.60` both ways).
- **Per-spell range VFX + predicted damage for abilities**: abilities
  previously all shared one `PlayerAbilityCast.nova_radius` constant —
  replaced with a `radius` field on `Ability.gd` itself (Frost Armor
  melee-short at `3m`, Comet `4m`, Ice Pulse `5m`, Winter's Eye wide at
  `7m` — invented, loosely sized off flavor text). New
  `entities/effects/ability_range_effect/AbilityRangeEffect.gd`: a flat
  `TorusMesh` ring, colored by damage type, that expands from the caster
  out to the ability's actual radius and fades on cast — procedural
  `Tween`, same approach as `PlayerMeleeAttack`'s swing. `Ability.gd`
  gained `predict_damage(stat_sheet)` — the exact `DamageCalculator` call
  `PlayerAbilityCast._cast()` uses, centralized so the "Predicted Damage"
  line on the stat card can't drift from what casting actually deals.
  Verified with a headless test that cast Ice Pulse and confirmed actual
  damage matched the prediction exactly.
- **Bug found: every enemy's actual toughness had been wrong since
  `HealthComponent` was written.** Surfaced by the diagnostic test
  written to confirm predicted-vs-actual damage matched — it printed
  `current_health` for all three archetypes and they were all `100.0`,
  which shouldn't be possible given `HeavyHitter`/`MobileBruiser`/
  `GlassCannon` set `220`/`180`/`60`. Root cause: `HealthComponent` is a
  **child** of `Enemy`, and Godot readies children before parents — the
  archetype subclasses set `health.max_health` via GDScript in their own
  `_ready()`, which runs *after* `HealthComponent`'s own `_ready()`
  (`current_health = max_health`) already fired, so `current_health` was
  always capturing the class default (`100.0`), never the archetype's
  real value. `HeavyHitter`/`MobileBruiser` (max above 100) had been
  dying far too easily; `GlassCannon` (max 60, below 100) had been
  tankier than intended. `Player` was unaffected — `Player.tscn` sets
  `max_health` as a static node property, applied before any `_ready()`
  runs, not via code. Fixed the same way as the earlier `EnemyMeleeAttack`
  parent-`@onready` bug: deferred via `call_deferred` so it runs after
  every `_ready()` that frame (including the archetype override) has
  finished. Verified with a headless test that all three archetypes now
  report their correct distinct `current_health` on spawn.

## 2026-08-29 — Save/Load, Player HUD

- **Save/Load** (user-requested): `autoloads/SaveManager.gd`, a single
  JSON file at `user://savegame.json`. Building this surfaced that
  `GameState` needed to become the actual live source of truth for the
  current loadout, not just a save-file mirror — `Player` is a fresh
  instance every Hub<->Map scene reload, and nothing was carrying
  equipment/ability state across that transition before now (silently
  resetting to the hardcoded starting kit every time, unnoticed until
  this work). `GameState.equipment_paths`/`ability_loadout_paths`/
  `ability_ranks` fix both problems at once: written by
  `InventoryScreen`/`AbilitiesScreen` after every equip/unequip/upgrade
  (`GameState.sync_equipment()`/`sync_ability_loadout()`), read by
  `Player._apply_saved_loadout()` at `_ready()`.
  - Save triggers: not a periodic timer — `SaveManager.save_game()` is
    called at every `change_scene_to_file()` away from gameplay and every
    quit (`PauseMenu`, `DeathScreen`, `MainMenu`, `MapDevice`), guarded
    internally as a no-op until `GameState.game_started`.
  - Continue vs. New Game now actually differ: `SaveManager.load_game()`
    runs at boot (before `MainMenu` ever shows) and populates `GameState`
    directly, so Continue is gated on `SaveManager.has_save()`. New Game
    calls `GameState.reset_to_defaults()` and deletes the save file.
  - **Bug found and fixed while wiring this up**: `Player.tscn` used to
    set `primary_weapon`/`sidearm_weapon` as raw static properties,
    silently bypassing `EquipmentComponent.equip()`'s two-handed rule (a
    two-handed primary should clear the sidearm/offhand — Section 13).
    Routing the default loadout through the real `equip()` call (needed
    for save/load and cross-scene persistence to share one consistent
    path) correctly enforced that rule for the first time, and
    `crude_greatsword` (two-handed) + `worn_pistol` as a default Sidearm
    turned out to be a genuinely invalid combination that had been
    silently tolerated since the scaffold's first commit — caught
    immediately by a headless test run (`push_warning` on boot). Fixed by
    dropping `worn_pistol.tres` from `DEFAULT_EQUIPMENT_PATHS`, matching
    the precedent already set for `guardians_kite_shield.tres` ("would be
    a no-op with a 2H weapon"). `worn_pistol.tres` is still equippable
    via Inventory once the two-handed primary is unequipped.
  - Scope, deliberately limited: equipment, ability loadout + ranks, and
    settings only. Not saved: Fate Board layout, current Health/Ward/Mana
    or player position, `GameState.active_map`.
  - Verified with a headless test: saved a changed ability loadout +
    rank, reset `GameState` to simulate a fresh app launch, reloaded from
    disk, then spawned a **brand-new** `Player` instance (with the
    ability resource's cached `rank` also reset) and confirmed it
    correctly re-applied the saved rank.
- **Player HUD** (user-requested: "see health, mana, what weapon is
  equipped, show what it looks like when they swap"): `ui/player_hud/`.
  Health/Mana/Ward as colored fill bars (`WardComponent` gained a
  `ward_changed` signal to match Health/Mana's existing push-update
  pattern), plus a weapon indicator that flashes/scale-punches on swap
  (new `EventBus.weapon_swapped` signal) — reusing `ItemSlotButton` for
  the weapon icon, so hovering it shows the same stat card weapons show
  everywhere else.
  - Timing bug avoided, not just fixed: the HUD's *initial* bar values
    are read via `call_deferred()`, not inline in `_ready()` —
    `HealthComponent`'s own `current_health` assignment is itself
    deferred (see above), so reading it synchronously from a sibling
    node's `_ready()` would have caught it a frame too early and shown 0
    HP momentarily. Verified via headless test that the HUD shows full
    HP/MP immediately on spawn.

## 2026-08-29 — Rollable Map Items

- **Rollable Map items** (user-requested): `data/maps/map_item.gd`
  (`MapItem extends Item`) carries `tier`, `enemy_damage_multiplier`,
  `enemy_health_multiplier`, `loot_quantity_multiplier`,
  `loot_rarity_multiplier`, and an `affixes: Array[ItemAffix]` — reusing
  `ItemAffix.gd`'s existing shape. `data/maps/map_roller.gd` rolls one on
  demand (`MapRoller.roll(tier)`): picks `1 + tier/2` affixes (capped at
  the 4-entry pool), each scaled by `1.0 + tier * 0.1`. No map-item table
  exists anywhere in the referenced docs — both the affix pool and tier
  curve are invented.
  - Wired into the Map Device: interacting calls `MapRoller.roll(map_tier)`
    and stores the result in `GameState.active_map` before loading the
    Map. No selection/inspection step — roll and commit in one keypress.
  - `enemy_damage_multiplier`/`enemy_health_multiplier` are real, verified
    end-to-end with a `--script`-mode test: `Enemy.gd` applies the health
    multiplier via `call_deferred("_apply_map_modifiers")` (deferred
    because archetype subclasses set `health.max_health` *after* calling
    `super._ready()`). Confirmed with a fixed 2x-health/1.5x-damage roll
    that all three archetypes scaled exactly as expected.
  - `loot_quantity_multiplier`/`loot_rarity_multiplier` are tracked and
    shown on the item's stat card but currently inert — no loot-generation
    system exists anywhere in this project. The stat card says so
    explicitly.
  - `DebugOverlay` now prints the active Map's roll on load, and also
    logs ability casts/failed-cast reasons.

## 2026-08-29 — Ability Bar, Casting, and Equip/Upgrade Menu

- **`entities/components/ManaComponent.gd`**: a new resource pool
  (`Player.mana`) `Ability.resource_cost` draws from. No documented Mana
  design exists in the referenced doc sections — a slow passive regen
  (`5/s`) is an invented default.
- **`systems/abilities/AbilityLoadoutComponent.gd`**: 4 equip slots, same
  "owns one of each" stand-in as `EquipmentComponent`. Player equips all
  4 existing Cold abilities by default.
- **`systems/abilities/PlayerAbilityCast.gd`**: casts on `1`-`4`,
  checking/consuming Mana and cooldown. Execution is deliberately generic
  for every ability — consume cost, start cooldown, deal
  `DamageCalculator`-computed damage to every `Enemy` within a radius of
  the player (a self-centered nova), **not** each ability's actual
  described mechanic (Comet's targeted drop, Winter's Eye's traveling
  orb, Frost Armor's melee-retaliation trigger). First-pass simplification
  so the bar's cooldown/cost readouts and the equip/upgrade menu mean
  something end to end rather than being inert UI.
- **`Ability.gd` gained a `rank` field** (0-`MAX_RANK` 5, `+10%` Motion
  Value / `-4%` cooldown per rank) — no upgrade/leveling system exists in
  the referenced docs, so the whole mechanic is invented. Rank lives on
  the shared loaded `.tres`, so upgrading persists for the running
  session.
- **`ui/ability_bar/AbilityBar.gd`**: always-on HUD, 4 slots built in
  code. Icon colored by damage type, a top-down cooldown-wipe overlay,
  remaining-cooldown seconds, and the Mana cost per slot, refreshing live
  via `AbilityLoadoutComponent.loadout_changed`.
- **`ui/abilities/AbilitiesScreen.gd`**: opens via hotkey `N`, no
  `PauseMenu` button. List-based — each owned ability needs an Upgrade
  button and rank readout, which doesn't fit a plain icon grid. Click an
  owned ability to equip it into the first open slot
  (`equip_first_open()`, mirrors `EquipmentComponent._equip_ring()`'s
  fallback pattern).
- **`ItemCard`/`ItemSlotButton` extended to a third type** —
  `display_ability()` alongside `display_item()`/`display_slate()`, so
  hovering an ability anywhere shows the same rich stat card items/Slates
  get.

## 2026-08-29 — Main Menu, Hub, and the Endgame Loop

User asked for a "proper level design" pass: endgame-first structure, no
campaign yet.

- **`ui/main_menu/MainMenu.tscn`** is now `project.godot`'s
  `run/main_scene`, replacing direct-boot into `TestArena.tscn`. Continue
  Game / New Game / Settings / About / Quit Game.
  - Settings: mouse sensitivity, fullscreen toggle (real, immediately
    testable), master volume (wired to the engine's Master bus, though
    there's zero audio content anywhere in the project yet).
- **`levels/hub/Hub.tscn`**: a small non-combat room carrying its own
  `Player` and the same UI suite `TestArena.tscn` has (`DebugOverlay`,
  `FateBoardEditor`, `InventoryScreen`, `PauseMenu`). No `DeathScreen` —
  nothing in the Hub can damage the player.
- **`entities/interactables/map_device/MapDevice.gd`**: a PoE-style map
  device — stand in its `ProximityArea` and press `interact` (`E`) to
  load `GameState.MAP_SCENE`. Placeholder visual: an unshaded, emissive
  teal orb on a solid pedestal, with a `Label3D` prompt that only shows
  while in range. Only one map exists — `TestArena.tscn`, reused as-is
  via `GameState.MAP_SCENE` rather than renamed.
- **Leaving a map**: no auto-return on clearing enemies (no "map
  complete" detection) — leaving is manual, via a new "Return to Hub"
  button on `PauseMenu` (`show_return_to_hub` export, `false` in the
  Hub). `PauseMenu` also gained "Quit to Main Menu." `DeathScreen`'s
  "Restart" was renamed "Return to Hub" and now loads the Hub instead of
  reloading the same map in place. Both `PauseMenu` and `DeathScreen`
  clear `get_tree().paused` before calling `change_scene_to_file()` —
  that flag is SceneTree-level and otherwise carries over, freezing the
  next scene's `Player`/enemies on arrival.
- **`PauseMenu` trimmed + a Return-to-Hub hotkey (`T`)**: user
  feedback — Inventory/Fate Board buttons removed from the pause menu;
  hotkey-only now (`P`/`B`), same as they already partly were. `T`
  triggers "Return to Hub" directly from gameplay.

## 2026-08-29 — PoE-Style Stat Cards

- **PoE-style stat cards** for items and Slates, user-requested from a
  reference screenshot. `ui/item_card/ItemCard.gd` is a builder, not a
  fixed template — branches on `Weapon`/`Armor`/`Shield`/generic `Item`
  vs `Slate` to show the fields that actually exist on each, title+border
  colored by rarity (`Constants.ITEM_RARITY_COLOR` / new
  `Constants.SLATE_RARITY_COLOR` — the latter didn't exist before, since
  only `ItemRarity` had a doc-sourced color column). Every line pulled
  straight from existing data — no new mechanics invented.
  `ui/item_card/ItemSlotButton.gd` (a `Button` subclass) wires this in
  via Godot's own `_make_custom_tooltip()` hook.
- **Bug found: stat cards broke tooltips badly enough to jam the
  screen.** Hovering any item/Slate slot right after the stat-card
  feature landed left the Inventory/Fate Board screens stuck covering
  everything, even after closing them. Root cause: `ItemCard.gd` resolved
  its content container via `@onready var content: VBoxContainer =
  $Margin/Content`, but `ItemSlotButton._make_custom_tooltip()` calls
  `card.display_item()` immediately after `ITEM_CARD_SCENE.instantiate()`
  — **before** the card is ever added to a `SceneTree`. `@onready` vars
  only get assigned on `NOTIFICATION_READY` (tree-entry), so `content`
  was still `null`, and every tooltip attempt threw inside
  `_clear()`/`_add_title()` etc., which looks to be what left Godot's
  tooltip popup stuck in a broken state. Fixed by replacing the
  `@onready` var with an on-demand `_content() -> VBoxContainer: return
  $Margin/Content` lookup — `$NodePath` resolution works immediately
  after `instantiate()` regardless of tree membership.
- Separately, also fixed: a stale global class-name cache. `ItemCard.gd`/
  `ItemSlotButton.gd` were written directly to disk (outside the Godot
  editor), so `.godot/global_script_class_cache.cfg` hadn't been rebuilt
  to include them, cascading into `InventoryScreen`/`FateBoardEditor`/
  `PauseMenu` all failing to compile — those screens never ran `_ready()`
  (which sets `visible = false`), so they defaulted to visible on launch.
  Fixed by running Godot headlessly in editor mode to force a rescan.
  This is now a documented, repeatable verification technique (see
  `reference_godot_headless_verification` in project memory) — a real
  Godot binary on this machine can be run with
  `--headless --editor --path . --quit-after N` to rebuild the class
  cache, and `--headless --path . res://path/To/Scene.tscn --quit-after N`
  to catch load-time script errors before ever opening the editor.

## 2026-08-28/29 — Player Stats, Enemy AI, Death & Restart

- **Enemies chase the player**: `Enemy.gd` drives its own movement every
  physics frame (`chase_range`/`stop_distance`/`retreat_distance`, tuned
  per archetype) — `move_speed` was declared from the start but never
  used for movement until now. Decoupled from attack components: `Enemy`
  only handles translation, `EnemyMeleeAttack`/`EnemyRangedAttack`
  independently decide *when to attack*. No facing/rotation (capsule
  placeholder mesh is rotationally symmetric), no pathfinding.
- **`GlassCannon` rebuilt as a ranged kiting skirmisher**, replacing its
  melee attack from a session before — new
  `systems/combat/EnemyRangedAttack.gd` fires the same `Projectile.tscn`
  `PlayerRangedAttack` uses. A deliberate design call, not requested
  verbatim: "Fast + Lethal... dies quickly" reads at least as well as a
  kiting archer as a melee rusher, and keeps the three archetypes
  distinct by engagement style. Required generalizing `Projectile.gd`,
  which only ever damaged `Enemy` bodies before — it now branches on
  `source is Player` to decide whether to damage the first `Enemy` or the
  `Player` it touches, with enemy-sourced hits running through
  `ParryRiposteHandler.attempt_parry()` first. Had to spawn the
  projectile offset forward of the shooter — spawning at the enemy's own
  center would land inside the shooter's own collision shape and
  self-trigger `body_entered`.
- **Player death + restart**: `Player.gd` connects `HealthComponent.died`
  and forwards it to `EventBus.player_died`. `DeathScreen.tscn` listens,
  pauses the tree, shows the cursor, offers Restart or Quit.
- **Bug found: player melee/ranged damage was always exactly 0.**
  `DamageCalculator.calculate()`'s `scaled_stat_damage := stat_value *
  effective_scale` feeds directly into `final_damage` as a multiplied
  term, and `Player.stat_sheet` was always a blank `StatSheet.new()`
  (every stat defaults to `0.0`) — so `stat_value` was always `0`, making
  `final_damage` always `0` regardless of weapon, motion value, or
  scaling grade. True since `PlayerMeleeAttack`/`PlayerRangedAttack` were
  first wired up; invisible until stats were actually being populated.
  Fixed by giving `Player.tscn` a real default `stat_sheet`
  (`data/stats/instances/player_baseline.tres`, flat `10.0` across all
  six stats — an invented testing baseline).
- **Bug found: the real reason enemy melee attacks weren't landing.**
  `EnemyMeleeAttack` is a **child** node of `Enemy` in every archetype's
  `.tscn`, and Godot readies children before their parent. `_ready()` was
  reading `_enemy.attack_hitbox` — an `@onready var` declared on `Enemy`
  itself — but `Enemy`'s own `_ready()` (and its onready-var assignment)
  hadn't run yet at that point. `_hitbox` ended up silently `null` for
  the node's entire lifetime, on both the old `body_entered` version and
  a polling rewrite that came first (see below) — every `if _hitbox:`
  guard just quietly no-opped. Fixed by moving the hitbox lookup out of
  `_ready()` into `call_deferred("_setup_hitbox")`.
- **Also fixed (before the above, and insufficient on its own): enemy
  melee attacks relied on `Area3D.body_entered`**, which only fires on a
  *fresh* overlap transition. Idle's aggro check used the same
  `attack_range` (2.5) as the hitbox's own radius, so the player was
  essentially always already standing inside the static sphere by the
  time Strike flipped `monitoring` on — nothing left to "enter." Fixed by
  polling `get_overlapping_bodies()` every physics frame during Strike
  instead.
- **`GlassCannon` and `MobileBruiser` given real melee attacks** — both
  were harmless dummies until then (only `HeavyHitter` had one), tuned
  per their Trinity Rule description since the doc gives archetype
  behavior (Section 21) but no per-archetype numbers.

## 2026-08-28 — Inventory Grid + Paper-Doll Equipment UI

User supplied two reference screenshots: a plain uniform grid of square
slots, and a Diablo/PoE-style silhouette equipment layout.

- **`ui/inventory/InventoryScreen.gd`** reworked from a flat button list
  into a **slot-based grid inventory** + **paper-doll equipment diagram**.
  Left panel: a `GridContainer` (5 columns, padded to a minimum 35 cells).
  Right panel: `PrimaryWeapon`/`Offhand` as tall slots flanking a center
  column (Helmet -> Amulet -> Body Armour -> Belt -> Gloves/Boots), 4
  Rings split two-and-two on the flanking columns,
  `Sidearm`/`Conduit`/`Secondary` in a small row above the helmet (no
  natural doll position for a 3rd/4th weapon slot). Still placeholder-art
  — every slot is a colored square, not an icon. This is a **uniform
  grid**, not the Tetris-grid Satchel (Section 14) — confirmed with the
  user rather than silently guessed.

## Earlier — Initial 3D Scaffold and Core Combat Loop

- **Correction from v0.1**: the first pass of this scaffold was built
  top-down 2D. That was wrong — this is a first-person ARPG. Rebuilt:
  `Player` (`CharacterBody3D` + head/camera rig + mouse look), `Enemy`
  base and all three archetypes (capsule placeholder meshes, color-coded
  per archetype), `TestArena` (3D room). Unaffected by the rework:
  `Constants`, `EventBus`, `GameState`, `FateBoard`, `ChainCalculator`,
  Slate/Modifier/Ability/Weapon resources, `DamageCalculator`,
  Stance/Composure/ParryRiposte logic, `StatSheet`, `HealthComponent`,
  `WardComponent` — none of that cares about camera perspective.
- **First-person controller**: WASD relative to body facing, mouse look
  with clamped vertical range, jump, sprint.
- **Fate Board + placement UI**: `FateBoard.gd` (grid placement + Aether
  budget) and `ChainCalculator.gd` (flood-fill chain detection), with a
  real UI in `ui/fate_board_editor/` — a bounded 32x32 window into the
  "effectively unlimited" board Section 10 describes (a pannable/infinite
  canvas wasn't worth building to validate the math).
- **Slate + Ability data models**: `Slate.gd`/`SlateModifier.gd` with two
  hand-authored instances; `Ability.gd` with a hand-authored Cold kit
  (Ice Pulse, Comet, Winter's Eye, Frost Armor, Section 26).
- **Combat loop core**: `StanceComponent`, `ComposureComponent`,
  `ParryRiposteHandler`, `DamageCalculator` (full Section 11 formula).
- **`HeavyHitter`'s first enemy attack**: `EnemyMeleeAttack.gd` (Idle ->
  Telegraph -> Strike -> Recovery). Telegraph flashes the capsule to a
  warning color that eases back to normal — the color's *return* is the
  "hit is coming" cue.
- **Debug overlay + Pause menu**: numeric readout of Aether/chains/
  damage/parries/Stance/Composure; Esc pause with Resume/Inventory/Fate
  Board/Quit.
- **Items & Equipment data model**: `Item.gd`/`Armor.gd`/`Shield.gd`/
  `Weapon.gd` (refactored onto `Item`), `EquipmentComponent.gd`
  enforcing the two-handed rule. Original list-based Inventory UI.
- **Armor mitigation**: `EquipmentComponent.get_total_armor()` +
  `DamageCalculator.physical_mitigation()` (Section 16), applied only to
  Physical-category damage before Ward/Health.
- **Player melee attack + attack feel**: `PlayerMeleeAttack.gd` (Idle ->
  Windup -> Strike -> Recovery), real `Area3D` hitbox swept through the
  swing arc. Placeholder blade swings via procedural `Tween` (not a baked
  `AnimationPlayer` — more reliable to author without the visual editor),
  landed hits trigger camera shake + hitstop.
- **Shield visual + ranged weapons + weapon swapping**:
  `PlayerRangedAttack.gd` fires `Projectile.tscn`; `V` swaps between
  Primary and Sidearm.
- **`EnemyMeleeAttack` upgraded to a real `Area3D` hitbox**, a static
  sphere on the base `Enemy.tscn`.

### Bugs fixed
- `project.godot` had no `[autoload]` section — `Constants`/`EventBus`/
  `GameState` were referenced everywhere as globals but never registered
  as singletons, so the entire project failed to parse.
- `ComposureComponent.get_damage_multiplier()` applied its Break bonus to
  *all* incoming damage; Section 07 explicitly excludes spells.
- `DamageCalculator.calculate()`'s `base_scale := lerp(...)` inferred
  `Variant` (the builtin `lerp()` is polymorphic over
  float/Vector2/Vector3/Color), which Godot 4.7 hard-errors on for `:=`
  declarations. Fixed by explicitly typing `base_scale: float`.
- **Root cause of a long-standing weapon-not-visible bug**: `#` comment
  lines inside a `.tscn` `[node]` block are unreliable in this Godot
  version — one right after a `[node ...]` header silently drops the
  property on the very next line (`WeaponSocket`'s position was parsing
  as `(0,0,0)` the entire time, sitting exactly at the camera's own
  position), and one at the *end* of a block could even break the parse
  of subsequent node declarations entirely. Found by instantiating
  `Player.tscn` with temporary diagnostic prints and reading back actual
  runtime position values, since reasoning about the transform math alone
  couldn't catch a parser-level bug. Fix: `.tscn` `[node]` blocks in this
  project now carry no `#` comments at all (confirmed via a full-project
  grep — this was the only file with any).
