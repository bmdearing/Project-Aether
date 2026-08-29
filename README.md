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
(WASD relative to body facing, mouse look, jump, sprint, crouch, slide).
Melee or ranged attack, dispatched automatically by whatever's equipped
in `PRIMARY_WEAPON` (`Weapon.is_ranged`), each a real swept/static
`Area3D` hitbox driving `DamageCalculator`. Parry (`F`) via
`ParryRiposteHandler`, which also handles Riposte: melee-attacking an
enemy while its Composure is broken (see Enemies below) deals 3x motion
value and grants 1 second of player invulnerability instead of a normal
hit. Health/Ward/Mana resource components. A `StatSheet`
(Vitality/Strength/Instinct/Arcane/Enigma/Intellect) — **all six now drive
something** (Section 12's Per-Point Values table): Strength/Arcane/Enigma
scale Physical/Elemental/Esoteric damage
(`Constants.DAMAGE_TYPE_MAIN_STAT`); Vitality raises max Health + Life
regen; Instinct raises Crit Chance + Attack/Cast/Move speed; Intellect
raises Crit Damage + max Mana + Mana regen. Per Section 12 ("all stats
come from gear... no manual allocation on level up"), stats only grow
from equipped gear now — `EquipmentComponent.compute_stat_bonuses()`
sums every equipped item's `flat_<stat>` affixes into
`StatSheet.equipment_bonus`, recomputed on every equip/unequip.

**Crouch & Slide** (`entities/player/Player.gd`, `Ctrl`): both invented,
no doc-sourced design exists for either. Hold Ctrl to crouch (shrinks the
collision capsule + lowers the camera, smoothly interpolated, slower move
speed). Tap Ctrl while sprinting and moving to slide instead — a burst of
speed along the current heading that decays over half a second, ending
into a crouch if Ctrl is still held or standing back up otherwise. No
headroom/ceiling check on standing up — every generated room is a simple
open box, nothing low enough to clip into yet.

**Combat formula** (`systems/combat/DamageCalculator.gd`): implements the
Section 11 formula (`Base Damage x Motion Value x Stat Value x Scaling-Grade
Fraction x Mastery x Increased% x More multipliers`), now followed by a
**Critical Strike System** (also Section 11, doc-exact numbers): base crit
chance is fixed per weapon/spell type (`Constants.WEAPON_BASE_CRIT_CHANCE`,
2%-8%), multiplied by Instinct; a crit deals 150% damage, multiplied by
Intellect. `Weapon`/`Ability` each expose `predict_damage()` (an
expected-value blend for stat-card display, doesn't jitter between hover
peeks) and `roll_damage()` (an actual random crit roll, used by real
attacks/casts). Armor mitigates Physical damage
(`Armor / (Armor + 6 x Hit Damage)`, Section 16) before Ward absorbs the
Esoteric portion and the remainder hits Health.

**Enemies** (`entities/enemies/`): three Trinity Rule archetypes (Section
21) — `HeavyHitter` and `MobileBruiser` are melee brawlers
(`EnemyMeleeAttack`, real swept-radius `Area3D` hitbox), `GlassCannon` is a
ranged kiting skirmisher (`EnemyRangedAttack`, fires `Projectile.tscn`,
holds distance and backs off if the player closes in). All three chase the
player (`Enemy.gd`, `chase_range`/`stop_distance`/`retreat_distance`), no
pathfinding. They're also gap-aware: `_check_gap_jump()` measures a real
gap's width and landing height ahead via raycast and only jumps
(`jump_velocity`, an invented `7.0`) if the archetype's speed can
physically clear it — `MobileBruiser` clears the Vault's jump gap,
`HeavyHitter` is too slow and gets walled off by it (both intentional),
`GlassCannon` never needs to since it fights from range. A red flashing
sphere appears above an enemy's head whenever its `ComposureComponent` is
broken — the on-screen signal that it's Riposte-able.

**Abilities** (`systems/abilities/`, `data/abilities/`): 9 hand-authored
spells across Fire/Cold/Lightning/Entropic (Ice Pulse, Comet, Winter's
Eye, Frost Armor, Cinder Lance, Inferno, Static Discharge, Stormcall,
Entropic Decay). Cast on `1`-`4` (`PlayerAbilityCast`), drawing from a
Mana pool (`ManaComponent`). Most abilities execute as a self-centered
damage nova sized by its own `radius`, on press — not yet each ability's
actual described mechanic (see gaps below). Three (`Ability.
is_ground_targeted`: Comet, Inferno, Stormcall) are hold-to-aim instead —
holding the key shows a ground ring tracking a camera raycast, releasing
casts centered there rather than on the player. Those three also get a
bespoke cast VFX instead of the generic expanding ring every other
ability shares - a falling ice ball that shatters (`CometImpact`), an
erupting fire column (`InfernoPillar`), and a jagged lightning strike
(`StormcallBolt`), all in `entities/effects/`. Abilities can be
upgraded (`rank`, 0-5) via the Abilities screen (`N`) for Gold
(`Ability.get_upgrade_cost()`, scaling per rank), boosting Motion Value
and reducing cooldown. `ui/ability_bar/` shows equipped abilities with a
cooldown wipe and Mana cost; `ui/abilities/AbilitiesScreen.gd` is the
equip/upgrade menu.
**The player starts with zero abilities** — per Patch v3.1's Skill
System replacement ("skills come exclusively from loot-dropped Skill
Tomes"), every ability now has to be unlocked via a `SkillTome` drop (see
Loot generation below) before it shows up in the Abilities screen at all.
The Hub's SpellTestShop (see Shops below) unlocks every ability for free,
for testing without grinding drops.

**Equipment & Items** (`data/items/`, `data/armor/`, `data/shields/`,
`data/weapons/`, `systems/equipment/EquipmentComponent.gd`): Section 13
equip slots, two-handed-weapon-clears-sidearm/offhand rule enforced.
`Weapon.is_ranged` decouples melee/ranged attack dispatch from equip slot,
so a pistol (or any ranged weapon) equips to `PRIMARY_WEAPON` like a
two-hander and naturally replaces one, rather than needing its own
Sidearm-only slot. `ui/inventory/InventoryScreen.gd` (`B`) is a 3-column
layout: a live stats column (left), a slot-grid inventory (center,
excluding anything currently equipped), and a paper-doll equipment
diagram (right, weapons flanking a center torso column). Items with a
real `icon_path` (`assets/sprites/` - a purchased dark-fantasy icon
pack) show that icon via `ItemSlotButton`; anything without one yet
still falls back to a colored square (rarity or damage-type color).
`worn_pistol` deliberately has no icon - no firearm exists in that
asset pack.

**Stat cards** (`ui/item_card/`): hovering any item, Slate, or ability
anywhere in the UI shows a rich PoE-style card (stats, affixes, flavor
text, rarity-colored border) via `ItemCard.gd` + `ItemSlotButton.gd`
(wired through Godot's `_make_custom_tooltip()` hook, `0.15s` delay).
Holding **Alt** while hovering opens an *advanced* card instead
(`AdvancedTooltip.gd`) — pinned open until dismissed (Esc/outside-click/
close button) rather than hiding when the mouse leaves, so it can be read
while moving. Rolled affixes show their full tier range, and stat
keywords are clickable, printing that stat's Section 12 per-point value
inline. Weapon/ability cards include a live "Predicted Damage" number
computed from the player's current stats (`Weapon.predict_damage()`/
`Ability.predict_damage()` — the exact formula real attacks/casts use, so
the number can't drift from reality).

**Fate Board** (`systems/fate_board/`, `ui/fate_board_editor/`, Section
10): grid Slate placement gated by an Aether budget, flood-fill chain
detection with tiered bonuses. UI is a bounded 32x32 window (not the
doc's "effectively unlimited" board), palette scanned live from
`data/slates/instances/`. Opens with `P`.

**Hub, Maps, and the Map Device** (`levels/hub/`,
`entities/interactables/map_device/`): `MainMenu.tscn` (project's main
scene) leads to `Hub.tscn`, a non-combat room. Walk up to the Map Device
and press `E` to roll a `MapItem` (`data/maps/`, tier-scaled
enemy-damage/enemy-health/loot-quantity/loot-rarity affixes) and enter a
procedurally generated Map. Leaving is manual (Pause menu's "Return to
Hub," or death).

**Shops** (`entities/interactables/gear_shop/`,
`entities/interactables/spell_test_shop/`, `ui/shop/ShopScreen.gd`): two
more Hub interactables, same walk-up-and-`E` pattern as the Map Device.
**GearShop** sells 6 `ItemRoller`-rolled items per Hub visit for Gold (a
brand-new invented currency — see gap below), cost scaled by rolled
rarity, plus a "Reroll Stock" action button (invented `15` Gold) to
refresh the offered items on demand without leaving. **SpellTestShop**
lists every ability under `data/abilities/instances/` for free — an
explicit testing/debug tool (user-requested), not a designed economy
feature, so you can unlock everything without grinding Tome drops while
testing other systems. Both share one generic `ShopScreen` (caller
supplies the entries + a buy callback, plus an optional single "action"
button for GearShop's reroll — same "one shared screen" shape `ItemCard`
already uses for item/slate/ability display).

**Loot generation** (`data/items/item_roller.gd`,
`data/abilities/tome_roller.gd`, `entities/pickups/loot_pickup/`,
`entities/pickups/gold_pickup/`): killing an enemy can drop up to three
different things. **Gold**: `Enemy.gold_reward` (per-archetype, invented)
spawns as a visible `GoldPickup` — a small spinning coin, auto-picked-up
on touch — rather than being granted instantly. **Gear**: invented `35%`
base chance, scaled by the active Map's `loot_quantity_multiplier`
(previously tracked but inert, now real) — `ItemRoller.roll()` duplicates
one of the existing hand-authored base items (a real weapon, armor piece,
shield, or accessory — see gap below for why) and re-rolls its rarity +
affixes. Rarity -> affix count now matches Section 18's real table
exactly (Common 0, Uncommon 0-2, Rare 0-6 — a Rare item genuinely can
roll with few or no affixes, per the doc's own "Rarity determined by
base quality, not affix count"), skewed toward higher rarity by the
Map's `loot_rarity_multiplier` (also previously inert, now real). Affix
*values* roll in 5 tiers (Tier 1 best, each ~80% of the tier above —
loosely modeled on the doc's own mod-tier tables' shape, e.g. Section
16's Flat Armor Mod Tiers), gated by a `power_level` (the active Map's
`tier`, or player level as a fallback for the Hub's GearShop) — higher
power unlocks access to better tiers, not a guaranteed roll of one.
`flat_<stat>` affixes (Vitality/Strength/Instinct/Arcane/Enigma/
Intellect) are real now, not descriptive-only — they're the only source
of stat growth in the game (see Player section above); the
damage/armor/ward affixes are still descriptive-only (see flagged gap).
**Skill Tomes**: a separate, flat invented `8%` chance (not scaled by
loot_quantity) rolls a `SkillTome` for a random ability the player
doesn't already own (`TomeRoller.gd`) — per Patch v3.1's Skill System,
abilities are no longer freely available, they have to be found this way
(or granted by the SpellTestShop). Gear/Tomes both spawn as a
`LootPickup` — a floating/bobbing placeholder sphere colored by rarity,
auto-picked-up on touch (a judgment call, see gap below). Gear lands in
`GameState.owned_loot` (persisted, including full data for pathless
rolled items — see Save/Load below) and shows up in `InventoryScreen`'s
grid, fully equippable and now safe to keep equipped across scene
transitions/saves; a Tome unlocks its ability into
`GameState.owned_ability_ids` and shows up in `AbilitiesScreen`.

**Map screen** (`ui/map_screen/`, `M`): a top-down schematic of the
current generated Map's room graph — start room green, Vault gold, your
current room outlined — reading `GeneratedMap.graph` directly (the same
`MapGraph` data used to build the real geometry, no re-derivation). Shows
a "no map data" message in the Hub/TestArena instead of erroring, since
those are static hand-built scenes with no such graph.

**Procedural map generation** (`systems/level_generation/MapGraph.gd`,
`levels/generated_map/GeneratedMap.gd`): a fresh, differently-shaped Map
every time you enter one — no fixed seed. Split into two layers on
purpose: `MapGraph.gd` is pure data (no `Node3D`, no geometry) — a
randomized spanning-tree room-and-corridor layout on a 5x5 grid,
guaranteeing every room is reachable from the start room. `GeneratedMap.gd`
turns that graph into actual walls/floors (`BoxMesh`/`PlaneMesh`
placeholder primitives, no real art yet). This separation means a later
asset-import pass only has to change the geometry builder — the
generation *algorithm* doesn't know or care what the rooms are made of.
  - **Walls**: every room boundary is either solid or has a doorway gap
    where a connection exists, built from real `StaticBody3D` collision,
    not just open floor. Every doorway also gets a floor bridge closing
    the footprint-to-footprint gap between adjacent rooms
    (`_build_doorway_bridges()`) — the room footprint (13m) is smaller
    than the grid spacing (16m), so without this every doorway in every
    map had an unfloored gap, not just the Vault's intentional one.
  - **Jumps**: the Vault room (farthest room from the start, by graph
    distance) has a split floor — a gap the player must jump across to
    reach an elevated platform. A full-footprint safety floor sits a
    shallow 0.5m below the whole room, so a missed jump is a small
    stumble, never a fall through the world.
  - **"Interesting things that pop up"**: the Vault room gets 3 enemies
    instead of 1, plus one more standing on the jump platform — a
    real risk/reward set-piece, not just a random room like the rest.
  - `levels/test_arena/TestArena.tscn` still exists as a static hand-built
    sandbox for direct-from-editor testing, but the Map Device no longer
    sends you there — `GameState.MAP_SCENE` now points at
    `GeneratedMap.tscn`.

**Character Screen** (`ui/character_screen/`, `C`): all six `StatSheet`
stats split into Offense/Defense/Misc, plus Predicted Main Hand/Offhand
Damage and Crit Chance/Damage (crit-inclusive, keyed by equip slot so a
ranged weapon in the main hand shows a real crit line), Life/Mana regen,
Action/Move Speed, and current Level/XP — built via `StatSummaryBuilder.gd`,
shared with the Inventory screen's own stats column. Read-only — stats
only change by equipping different gear (Section 12), there's no
allocation UI here.

**Experience & Leveling** (`entities/components/ExperienceComponent.gd`):
killing an enemy grants XP (`Enemy.xp_reward`, tuned per archetype).
Leveling up (invented curve: `100 * 1.25^(level-1)` XP per level) no
longer grants stat points — Section 12 explicitly rules out level-up
allocation ("all stats come from gear... no manual allocation on level
up"), so a level's only remaining effect is display (`PlayerHUD`'s 4th
bar, "Lv N", and the Character Screen) plus standing in for a Map-tier
signal when the Hub's GearShop rolls its stock (no Map context exists
there). Persists across Hub<->Map scene reloads and app restarts the
same way equipment/ability loadout does (`GameState.player_level`/
`player_xp`, `SaveManager`).

**Save/Load** (`autoloads/SaveManager.gd`): single JSON file at
`user://savegame.json`. Persists equipment (including full data for
rolled/pathless items via `data/items/item_serializer.gd`, not just a
path), owned rolled loot, ability loadout + ranks, player level/XP, Gold,
unlocked ability ids, and settings — not Fate Board layout, current
Health/Ward/Mana, player position, or map state. `StatSheet`'s raw values
need no save path of their own — Section 12 means they never change from
`player_baseline.tres`'s fixed defaults, and the gear-derived bonus on
top is re-summed live from the (already-saved) equipment on every load.
Saves at
every meaningful transition point (leaving the Hub, quitting), not a
timer. `GameState` (`autoloads/GameState.gd`) is the live in-session
source of truth for the same data, so gear/abilities/gold/level/rolled
loot also survive ordinary Hub<->Map scene transitions, not just app
restarts — a rolled item's `resource_path` is empty
(`Resource.duplicate()`), so `EquipmentComponent.get_all_equipped_refs()`
stores either a path (hand-authored items) or a full `ItemSerializer`
dict per equipped slot, whichever the item actually has.

**Main Menu background** (`levels/main_menu_background/`): a procedural
night-storm scene rendered into a `SubViewport` behind the menu buttons -
layered mountain silhouettes (`MountainRange.gd`, a `SurfaceTool`-built
ridge flat), a night sky (`shaders/night_sky.gdshader`: hashed stars, a
moon, drifting cloud cover that occludes them, and a lightning-flash
uniform), falling rain (`CPUParticles3D`), and rain/thunder audio
synthesized at runtime sample-by-sample
(`systems/audio/ProceduralRain.gd`/`ProceduralThunder.gd` push into an
`AudioStreamGenerator` - no audio files needed for those). Thunder fires
at random intervals and syncs a light flash to the rumble. Menu music
(`MainMenu.gd`) loops `assets/music/lament.mp3` - the one real audio
asset in the project, everything else here is generated.

**Menus & HUD**: `MainMenu` (Continue/New Game/Settings/About/Quit),
`PauseMenu` (`Esc` — Resume/Return to Hub/Quit; Inventory/Fate
Board/Abilities/Character/Map are hotkey-only, not buttons),
`DeathScreen` (on `HealthComponent.died`, offers Return to Hub or Quit),
`ui/player_hud/` (always-on Life/Mana orbs flanking the ability bar - Ward
renders as a ring around the Life orb - a notched, multi-color-gradient
XP bar spanning from the level badge at the far left to near the right
screen edge, its text inline on the bar itself (GW2-style layout), a Gold
counter, and an active-weapon indicator that flashes whenever the
equipped weapon changes),
`ui/debug/DebugOverlay.gd` (numeric
readout of damage/chains/casts/parries — no art needed to validate
formulas).

## Controls (current bindings)

| Action | Key |
|---|---|
| Move | WASD |
| Look | Mouse |
| Sprint | Shift |
| Jump | Space |
| Crouch (hold) / Slide (tap while sprinting + moving) | Ctrl |
| Parry | F |
| Attack (melee or ranged, depending on active weapon) | Left Mouse |
| Cast equipped ability (slot 1-4) - hold + release to aim for Comet/Inferno/Stormcall | 1 / 2 / 3 / 4 |
| Pause menu (Resume / Return to Hub / Quit) | Esc |
| Return to Hub directly (no pause menu needed) | T |
| Open Fate Board directly | P |
| Open Inventory directly | B |
| Open Abilities (equip/upgrade) directly | N |
| Open Character Screen directly | C |
| Open Map Screen directly | M |
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
   a swinging weapon (a real model for Greatsword/Dagger now, still the
   placeholder blade for anything else) exist, but the docs are
   camera-agnostic on *how it should feel* (timing, intensity), and the
   real model's pose was tuned by eye via screenshots, not exact
   hand-placement - worth your own live nudging for final polish.
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
   `EnemyRangedAttack` tuning, and both Player's and enemies'
   `jump_velocity` (`7.0`, matched to each other) are all invented
   placeholders**, not doc-sourced — the doc doesn't specify baseline
   character stats for the vertical slice, or anything about
   enemy/player movement/kiting/jumping behavior. Both were tuned
   specifically so a sprinting (or even just walking) character can
   clear the Vault's particular gap (3m wide, 1.2m rise) with real
   margin — if either the gap or the rise ever change, this may need
   retuning or the jump may start failing again.
10. **Turning `GlassCannon` into a ranged kiter (vs. a melee rusher) was
    a judgment call, not something explicitly requested** — genre
    convention + archetype differentiation by engagement style. Worth
    confirming before building more content that assumes it.
11. **Map Device / Hub scope cuts**: no map-selection UI or map-item
    economy (the device rolls and commits in one keypress); leaving a
    map is always manual, not triggered by clearing enemies; Settings
    has exactly three real options. Master volume now has real audio to
    affect (Main Menu music + procedural rain/thunder, see the Main Menu
    background section above) but nothing plays in the Hub/Map yet.
12. **Ability casting is one generic self-centered nova for all 4
    abilities**, not their actual described mechanics (Comet's targeted
    drop, Winter's Eye's traveling orb, Frost Armor's melee-retaliation
    trigger). `applies_status_effects` (chill, etc.) also isn't wired to
    anything — no status-effect system exists to apply/track it.
13. **Map items have no selection/inspection UI and no doc-sourced affix
    table** — the Map Device rolls and commits in one keypress; the
    affix pool and tier curve are invented.
14. **Vitality's Resilience/DoT mitigation, Instinct's Stamina pool +
    dodge-roll/Active-Blocking, and Intellect's Debuff effectiveness are
    NOT wired**, even though the rest of each stat's Section 12
    expression now is — none of the three has a supporting system built
    anywhere in this project (no DoT/status-effect system, no
    Stamina/dodge/block-charge mechanic, no debuff-magnitude system), so
    there's nothing yet for that portion of the stat to modify. Strength's
    Stagger effect/Stun Recovery are similarly unwired for the same
    reason (no stagger/stun mechanic exists).
15. **Critical Strike System's per-ability base crit chance is thematic
    guesswork, not a real mechanical distinction** — the doc keys base
    crit chance off "spell type" (single target/AoE/channeled/etc.),
    but abilities in this project don't carry that classification (all 4
    execute as the same generic self-centered nova, gap #12 below), so
    each `Ability.base_crit_chance` was hand-picked per instance based on
    which doc category its flavor text loosely resembles. Weapon crit
    chance is the real thing, doc-exact, keyed by `weapon_type` string
    (`Constants.WEAPON_BASE_CRIT_CHANCE`) - just only transcribed for the
    2 weapon types this project actually has (Greatsword, Service
    Pistol) out of the doc's ~55-entry table.
16. **Affix tier-gating (`ItemRoller._roll_tier()`) is entirely
    invented** — the doc defines the tier VALUE RANGES themselves (real
    Section 16/18 data, e.g. Flat Armor Mod Tiers), but never specifies
    what determines which tiers a given roll can reach. Gated by
    `power_level` (Map tier, or player level as a Hub-only fallback) with
    a simple "one tier better per power point" curve, not derived from
    anything doc-sourced.
17. **XP/leveling has no doc-sourced design to follow at all** — the
    referenced sections don't define a leveling system, so the XP curve
    and `xp_reward` per archetype are invented from genre convention.
    Leveling grants no stat points (Section 12 explicitly rules that
    out - see the Player section above) and now has no mechanical effect
    beyond display and standing in as GearShop's stock-quality signal.
18. **Loot generation duplicates hand-authored base items rather than
    generating a truly procedural item shape** — `ItemRoller.roll()`
    picks a real base (weapon type, damage type, scaling grade, armor
    values, etc.) and only re-rolls rarity + affixes, since Section 25's
    full item tables were already flagged as deferred design before this
    pass. `flat_<stat>` affixes are real (summed into `StatSheet` - see
    the Player section above), but the damage/armor/ward affixes
    (`physical_dmg_increased`, `flat_armor`, etc.) are still
    descriptive-only — no aggregation of those into the damage/armor
    formulas exists yet, only the 6 core stats got wired this pass.
19. **Loot pickup is auto-pickup-on-touch, not a manual pickup/prompt**
    — a judgment call, not requested verbatim; fits how often gear
    would drop during combat better than a keypress flow, but is a
    different UX than the Map Device's "walk up, press E" pattern used
    elsewhere in this project.
20. **Map generation parameters are invented, not doc-sourced** — grid
    size (5x5), room count (7-10), doorway width, jump-gap size, and the
    "one Vault per map" rule are standard roguelike-generation choices,
    not pulled from any section of the design docs (there's no dungeon-
    layout spec in them at all). Only one "interesting room" type exists
    (the Vault) — more variety (traps, shrines, multiple set-piece types)
    is natural follow-up work, not a doc gap. Rooms are also currently
    uniform single-grid-cell boxes with no elevation variety beyond the
    Vault's jump — flagged as a deliberate first-pass scope cut, not a
    misreading, given how much riskier untested geometry math gets
    without the ability to visually playtest here.
21. **Skill Tomes unlock an ability into `AbilitiesScreen`, they don't
    implement Patch v3.1's literal "socketed into weapon slots"
    mechanic** — the patch doc actually describes a fairly detailed
    system (3 skill slots per weapon, Tomes socketed per-weapon, up to 9
    skills with both weapon slots filled), but there's no functioning
    socket system anywhere in this project (`Item.max_sockets` isn't
    wired to anything, Gems/Jewels are explicitly not-built-yet), so
    this pass only builds the acquisition half of the doc's replacement
    Skill System (a flat "owns it or doesn't" unlock), not the
    per-weapon-slot socketing half.
22. **Gold is a brand-new invented currency with no doc-sourced economy
    to follow** — granted by `Enemy.gold_reward` (per-archetype, same
    relative-toughness scaling as `xp_reward`), spent at the GearShop.
    `GearShop.COST_BY_RARITY`/`REROLL_COST` are similarly invented, not
    derived from anything.
23. **SpellTestShop is an explicit debug/testing tool, not designed
    game content** — grants every ability for free per direct user
    request ("for testing purposes"); it bypasses the SkillTome
    acquisition path entirely and isn't meant to represent real
    in-fiction economy the way GearShop is.

## Explicitly not built yet (per Vertical Slice Brief scope)

Crafting (Cube/Brands/Corruption), a Gem/Jewel/weapon-socket system (Skill
Tomes unlock abilities directly instead — see flagged gaps), a Stamina pool +
dodge-roll/Active-Blocking mechanic (Instinct's per-point Stamina value has
nothing to spend into yet), full 9-damage-type coverage, co-op, any
skeletal character animation (`assets/animations/` has two full rigged
animation libraries + a mannequin imported cleanly, but there's no
`AnimationPlayer`/`AnimationTree`/skeleton pipeline anywhere in this
project yet - a much bigger, separate undertaking than everything else
in this list), Conduit/Secondary (Throwable) attack input, a status-effect system (also
blocks Vitality's DoT mitigation and Intellect's Debuff effectiveness
from doing anything), save persistence for Fate Board layout or mid-map
state, pathfinding/navigation for enemies (fine today — every generated
room is an open box, nothing to path around within one).

## Opening this project

1. Install Godot 4.7.1+ (GL Compatibility renderer for broad hardware
   support during prototyping).
2. Open `project.godot` from the Godot project manager.
3. Run the project (F5) — `ui/main_menu/MainMenu.tscn` is the main scene.
   "New Game" (or "Continue Game" once a save exists) drops you into
   `levels/hub/Hub.tscn`; walk up to the Map Device and press `E` to enter
   a freshly generated Map (`levels/generated_map/GeneratedMap.tscn`,
   different every time — see "Procedural map generation"). To iterate
   directly on enemy/combat work without going through the menu each
   time, you can still open and run `Hub.tscn` or the older static
   `TestArena.tscn` sandbox directly from the editor (F6) — both work
   standalone.
4. In a generated Map you should see several connected rooms with real
   walls, one or more enemies per room, and a Vault room (denser enemies,
   a jump-gap to an elevated platform) somewhere in the layout — walk/look
   around immediately, mouse is captured on scene start.

## Exporting

`export_presets.cfg` (gitignored — machine-local, not committed) has two
64-bit presets, each a single embedded-pck executable: **Windows
Desktop** -> `builds/windows/ProjectAether.exe` and **Linux** ->
`builds/linux/ProjectAether.x86_64` (`builds/` is gitignored too). Both
require Godot 4.7.1's export templates installed (Editor menu: Editor ->
Manage Export Templates). To export from the command line:
```
godot --headless --export-release "Windows Desktop" "builds/windows/ProjectAether.exe"
godot --headless --export-release "Linux" "builds/linux/ProjectAether.x86_64"
```
