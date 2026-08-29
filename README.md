# Project Aether — Godot Scaffold (v0.2, First-Person)

Vertical Slice Brief v0.1 scaffold. Godot 4.7.1, GDScript, **true first-person
3D** (Borderlands-style: camera in head, no visible player body, weapon
socket for a future viewmodel). Endgame-first structure — a Hub with a Map
Device leading into instanced maps, no campaign yet.

See **`PATCH_NOTES.md`** for the history of how the project got here — bugs
found and fixed, judgment calls made, reasoning behind non-obvious choices.
This file describes the project as it stands today.

## Design source

`documents/` holds the canonical design docs: `Project_Aether_Master_v3.pdf`
(Unified World & Design Document v3.0) and `Project_Aether_Patch_v3_1.pdf`
(supersedes v3.0 on any conflict — most notably it replaces the Skill System
section: skills come exclusively from loot-dropped Skill Tomes socketed into
weapon slots, not an allocatable node web). Check these before inventing
numbers or resolving a flagged gap — most of the scaffold's constants
(scaling grade ranges, chain bonus tiers, damage type/category mapping,
Trinity Rule archetypes) were pulled from this source and match it exactly.

## What's implemented

**Player** (`entities/player/Player.gd`): first-person `CharacterBody3D`
(WASD relative to body facing, mouse look, jump, sprint). Melee (`V` to
select Primary) and ranged (Sidearm) attacks, each a real swept/static
`Area3D` hitbox driving `DamageCalculator`. Parry (`F`) via
`ParryRiposteHandler`. Health/Ward/Mana resource components. A `StatSheet`
(Vitality/Strength/Instinct/Arcane/Enigma/Intellect) — only
Strength/Arcane/Enigma currently drive anything (they scale
Physical/Elemental/Esoteric damage respectively, `Constants.DAMAGE_TYPE_MAIN_STAT`).

**Combat formula** (`systems/combat/DamageCalculator.gd`): implements the
Section 11 formula (`Base Damage x Motion Value x Stat Value x Scaling-Grade
Fraction x Mastery x Increased% x More multipliers`). Armor mitigates
Physical damage (`Armor / (Armor + 6 x Hit Damage)`, Section 16) before Ward
absorbs the Esoteric portion and the remainder hits Health.

**Enemies** (`entities/enemies/`): three Trinity Rule archetypes (Section
21) — `HeavyHitter` and `MobileBruiser` are melee brawlers
(`EnemyMeleeAttack`, real swept-radius `Area3D` hitbox), `GlassCannon` is a
ranged kiting skirmisher (`EnemyRangedAttack`, fires `Projectile.tscn`,
holds distance and backs off if the player closes in). All three chase the
player (`Enemy.gd`, `chase_range`/`stop_distance`/`retreat_distance`), no
pathfinding.

**Abilities** (`systems/abilities/`, `data/abilities/`): a hand-authored
Cold kit (Ice Pulse, Comet, Winter's Eye, Frost Armor, Section 26 flavor).
Cast on `1`-`4` (`PlayerAbilityCast`), drawing from a Mana pool
(`ManaComponent`). Every ability currently executes as a self-centered
damage nova sized by its own `radius` — not yet each ability's actual
described mechanic (see gaps below). Abilities can be upgraded (`rank`,
0-5) via the Abilities screen (`N`), boosting Motion Value and reducing
cooldown. `ui/ability_bar/` shows equipped abilities with a cooldown wipe
and Mana cost; `ui/abilities/AbilitiesScreen.gd` is the equip/upgrade menu.

**Equipment & Items** (`data/items/`, `data/armor/`, `data/shields/`,
`data/weapons/`, `systems/equipment/EquipmentComponent.gd`): Section 13
equip slots, two-handed-weapon-clears-sidearm/offhand rule enforced.
`ui/inventory/InventoryScreen.gd` (`B`) is a slot-grid inventory + a
paper-doll equipment diagram (weapons flanking a center torso column).
Placeholder-art throughout — every item is a colored square (rarity or
damage-type color), not an icon.

**Stat cards** (`ui/item_card/`): hovering any item, Slate, or ability
anywhere in the UI shows a rich PoE-style card (stats, affixes, flavor
text, rarity-colored border) via `ItemCard.gd` + `ItemSlotButton.gd`
(wired through Godot's `_make_custom_tooltip()` hook). Weapon/ability cards
include a live "Predicted Damage" number computed from the player's current
stats (`Weapon.predict_damage()`/`Ability.predict_damage()` — the exact
formula real attacks/casts use, so the number can't drift from reality).

**Fate Board** (`systems/fate_board/`, `ui/fate_board_editor/`, Section
10): grid Slate placement gated by an Aether budget, flood-fill chain
detection with tiered bonuses. UI is a bounded 32x32 window (not the
doc's "effectively unlimited" board), palette scanned live from
`data/slates/instances/`. Opens with `P`.

**Hub, Maps, and the Map Device** (`levels/hub/`,
`entities/interactables/map_device/`): `MainMenu.tscn` (project's main
scene) leads to `Hub.tscn`, a non-combat room. Walk up to the Map Device
and press `E` to roll a `MapItem` (`data/maps/`, tier-scaled
enemy-damage/enemy-health/loot-quantity/loot-rarity affixes — the latter
two are tracked but currently inert, no loot-generation system exists) and
enter `TestArena.tscn` as "the Map." Only one map exists so far. Leaving is
manual (Pause menu's "Return to Hub," or death).

**Character Screen** (`ui/character_screen/`, `C`): all six `StatSheet`
stats split into Offense/Defense/Misc, plus Predicted Melee/Ranged Damage.
States plainly that Vitality/Instinct/Intellect don't affect anything yet.

**Save/Load** (`autoloads/SaveManager.gd`): single JSON file at
`user://savegame.json`. Persists equipment, ability loadout + ranks, and
settings — not Fate Board layout, current Health/Ward/Mana, player
position, or map state. Saves at every meaningful transition point (leaving
the Hub, quitting), not a timer. `GameState` (`autoloads/GameState.gd`) is
the live in-session source of truth for the same data, so gear/abilities
also survive ordinary Hub<->Map scene transitions, not just app restarts.

**Menus & HUD**: `MainMenu` (Continue/New Game/Settings/About/Quit),
`PauseMenu` (`Esc` — Resume/Return to Hub/Quit; Inventory/Fate
Board/Abilities/Character are hotkey-only, not buttons),
`DeathScreen` (on `HealthComponent.died`, offers Return to Hub or Quit),
`ui/player_hud/` (always-on Health/Mana/Ward bars + an active-weapon
indicator that flashes on swap), `ui/debug/DebugOverlay.gd` (numeric
readout of damage/chains/casts/parries — no art needed to validate
formulas).

## Controls (current bindings)

| Action | Key |
|---|---|
| Move | WASD |
| Look | Mouse |
| Sprint | Shift |
| Jump | Space |
| Parry | F |
| Attack (melee or ranged, depending on active weapon) | Left Mouse |
| Cast equipped ability (slot 1-4) | 1 / 2 / 3 / 4 |
| Swap active weapon (Primary / Sidearm) | V |
| Pause menu (Resume / Return to Hub / Quit) | Esc |
| Return to Hub directly (no pause menu needed) | T |
| Open Fate Board directly | P |
| Open Inventory directly | B |
| Open Abilities (equip/upgrade) directly | N |
| Open Character Screen directly | C |
| Rotate pending Slate *(Fate Board editor only)* | R |
| Flip pending Slate *(Fate Board editor only)* | Q |
| Interact *(Map Device, Hub only)* | E |

P/B/N/C work from anywhere — gameplay, the pause menu, or another such
screen — and jump straight to their target, closing whatever else was
open. Pressing the same key again while already on that screen closes it.
None of the four have a `PauseMenu` button — hotkey-only.

## Flagged design gaps (need your call, not resolved unilaterally)

1. **Ward restore-on-parry ratio**: placeholder 15% of max Ward — Section
   07/16 both confirm this is deferred to playtesting, no number given.
2. **Stance depletion weights**: ordering is confirmed (Blunt/Explosive
   strong -> Piercing/ranged moderate -> Spells weakest), but no
   percentages anywhere, so Physical 1.0 / Elemental 0.6 / Esoteric 0.35
   remains a well-justified guess.
3. **First-person melee weight** (Pillar 2): camera shake + hitstop +
   swinging placeholder blade exist, but the docs are camera-agnostic on
   *how it should feel* (timing, intensity), and there's no real
   viewmodel. Worth a design pass once art exists.
4. **Ability numeric tuning**: `motion_value`, `scaling_grade`,
   `cooldown_seconds`, `resource_cost`, `radius` on the four Ability
   instances are invented (relative to each ability's described weight) —
   the doc gives the damage formula and flavor text but never per-ability
   numbers.
5. **Fate Board UI is a bounded 32x32 window**, not the "effectively
   unlimited" board Section 10 describes — a deliberate scope cut.
   Revisit with real pan/zoom if a Slate loadout ever needs more room.
6. **Inventory is a uniform 1x1 grid**, not the Tetris-footprint Satchel
   (Section 14) — `Item.gd` has no width/height field. Confirmed with the
   user as the right scope, not a silent guess.
7. **Armor mitigation applies one formula to all Physical damage types**:
   Section 16 says Kinetic gets it "full," Piercing "partial," Explosive
   a "flat reduction," but gives no ratio for the latter two.
8. **`PlayerMeleeAttack`'s hitbox radius/swing arc/timings are invented
   placeholders**, and melee is single-target only (no cleave/AoE weapon
   mods modeled) — fine for one starting Greatsword, needs revisiting
   once weapon variety matters.
9. **Player `StatSheet` baseline (flat `10.0`), enemy chase/kite numbers,
   and `EnemyRangedAttack` tuning are all invented placeholders**, not
   doc-sourced — the doc doesn't specify baseline character stats for the
   vertical slice, or anything about enemy movement/kiting behavior.
10. **Turning `GlassCannon` into a ranged kiter (vs. a melee rusher) was
    a judgment call, not something explicitly requested** — genre
    convention + archetype differentiation by engagement style. Worth
    confirming before building more content that assumes it.
11. **Map Device / Hub scope cuts**: only one map exists, so no
    map-selection UI or map-item economy; leaving a map is always
    manual, not triggered by clearing enemies; Settings has exactly
    three real options and master volume has nothing audible to affect
    yet (no audio content anywhere in the project).
12. **Ability casting is one generic self-centered nova for all 4
    abilities**, not their actual described mechanics (Comet's targeted
    drop, Winter's Eye's traveling orb, Frost Armor's melee-retaliation
    trigger). `applies_status_effects` (chill, etc.) also isn't wired to
    anything — no status-effect system exists to apply/track it.
13. **Ability upgrading has no cost gating** — free and unlimited, just
    rank-capped at 5. No currency/economy exists for it to spend from.
14. **Map items have no selection/inspection UI and no doc-sourced affix
    table** — the Map Device rolls and commits in one keypress; the
    affix pool and tier curve are invented.
15. **Vitality/Instinct/Intellect don't affect anything** — confirmed by
    grepping the whole project. Only Strength/Arcane/Enigma do anything.
    Health/Ward/Mana max values are flat exported constants, not derived
    from any stat.

## Explicitly not built yet (per Vertical Slice Brief scope)

Crafting (Cube/Brands/Corruption), procedural loot rolling, full 9-damage-type
coverage, Jewelry/Gems/Sockets, co-op, real viewmodel/weapon art (placeholder
primitives only), Conduit/Secondary (Throwable) attack input, a status-effect
system, save persistence for Fate Board layout or mid-map state, pathfinding/
navigation for enemies (fine today — `TestArena` is one open room).

## Opening this project

1. Install Godot 4.7.1+ (GL Compatibility renderer for broad hardware
   support during prototyping).
2. Open `project.godot` from the Godot project manager.
3. Run the project (F5) — `ui/main_menu/MainMenu.tscn` is the main scene.
   "New Game" (or "Continue Game" once a save exists) drops you into
   `levels/hub/Hub.tscn`; walk up to the Map Device and press `E` to enter
   `levels/test_arena/TestArena.tscn` (the one map that exists so far). To
   iterate directly on map/enemy work without going through the menu each
   time, you can still open and run `TestArena.tscn` (or `Hub.tscn`)
   directly from the editor (F6) — both work standalone.
4. In the Map you should see a floor plane, three colored capsules
   (enemies) ahead of the player's starting position, and be able to
   walk/look around immediately — mouse is captured on scene start.
