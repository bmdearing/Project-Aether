# Project Aether — Godot Scaffold (v0.2, First-Person)

Vertical Slice Brief v0.1 scaffold. Godot 4.7.1, GDScript, **true first-person
3D** (Borderlands-style: camera in head, no visible player body, weapon
socket for a future viewmodel).

## Design source

`documents/` holds the canonical design docs: `Project_Aether_Master_v3.pdf`
(Unified World & Design Document v3.0) and `Project_Aether_Patch_v3_1.pdf`
(supersedes v3.0 on any conflict — most notably it replaces the Skill System
section: skills now come exclusively from loot-dropped Skill Tomes socketed
into weapon slots, not an allocatable node web). Check these before
inventing numbers or resolving a flagged gap — most of the scaffold's
constants (scaling grade ranges, chain bonus tiers, damage type/category
mapping, Trinity Rule archetypes) were already pulled from this source and
match it exactly.

## Recent fixes

- **Stat cards broke tooltips badly enough to jam the screen** — hovering
  any item/Slate slot right after the stat-card feature landed left the
  Inventory/Fate Board screens stuck covering everything, even after
  closing them. Root cause: `ItemCard.gd` resolved its content container
  via `@onready var content: VBoxContainer = $Margin/Content`, but
  `ItemSlotButton._make_custom_tooltip()` calls `card.display_item()`
  immediately after `ITEM_CARD_SCENE.instantiate()` — **before** the card
  is ever added to a `SceneTree`. `@onready` vars only get assigned on
  `NOTIFICATION_READY` (tree-entry), so `content` was still `null` at that
  point, and every tooltip attempt threw inside `_clear()`/`_add_title()`
  etc., which looks to be what left Godot's tooltip popup stuck in a
  broken state on top of everything else. Fixed by replacing the
  `@onready` var with a `_content() -> VBoxContainer: return $Margin/Content`
  lookup called on demand — `$NodePath` resolution works immediately after
  `instantiate()` regardless of tree membership (the node hierarchy is
  already fully built in memory; only tree-lifecycle notifications like
  `_ready()` are deferred), unlike `@onready`'s assignment timing.
- **Player melee/ranged damage was always exactly 0**, found while wiring
  up real player stats. `DamageCalculator.calculate()`'s
  `scaled_stat_damage := stat_value * effective_scale` feeds directly into
  `final_damage` as a multiplied term, and `Player.stat_sheet` was always a
  blank `StatSheet.new()` (every stat defaults to `0.0`, and nothing ever
  set them) — so `stat_value` was always `0`, making `final_damage` always
  `0` regardless of weapon, motion value, or scaling grade. This has been
  true since `PlayerMeleeAttack`/`PlayerRangedAttack` were first wired up;
  invisible until now because there was no debug-overlay signal
  distinguishing "0 damage dealt" from "no hit landed," and no reason to
  suspect it until stats were actually being populated. Fixed by giving
  `Player.tscn` a real default `stat_sheet`
  (`data/stats/instances/player_baseline.tres`) — see "What's implemented."
- **The real reason enemy melee attacks weren't landing, found after the
  polling fix below still didn't help**: `EnemyMeleeAttack` is a **child**
  node of `Enemy` in every archetype's `.tscn`, and Godot readies children
  before their parent. `_ready()` was reading `_enemy.attack_hitbox` — an
  `@onready var` declared on `Enemy` itself — but `Enemy`'s own `_ready()`
  (and its onready-var assignment) hadn't run yet at that point, since the
  child (`EnemyMeleeAttack`) always readies first. `_hitbox` ended up
  silently `null` for the node's entire lifetime, on both the old
  `body_entered` version and the polling rewrite below — every
  `if _hitbox:` guard just quietly no-opped, so monitoring never turned on
  and nothing was ever there to poll. Fixed by moving the hitbox lookup out
  of `_ready()` into a `call_deferred("_setup_hitbox")`, which runs after
  the whole scene tree (including `Enemy._ready()`) has finished readying.
- **Enemy melee attacks were never actually landing**: `EnemyMeleeAttack`'s
  Strike relied on `Area3D.body_entered`, but that signal only fires on a
  *fresh* overlap transition. Idle's aggro check uses the same
  `attack_range` (2.5) as the hitbox's own radius, so the player is
  essentially always already standing inside the static sphere by the time
  Strike flips `monitoring` on — there's nothing left to "enter." Unlike
  `PlayerMeleeAttack`'s swept blade hitbox (which starts outside the enemy
  and sweeps in, so a real enter transition happens), a static sphere
  centered on a stationary target needs an explicit "who's inside right
  now" check, not an edge-triggered signal. Fixed by polling
  `get_overlapping_bodies()` every physics frame during Strike instead of
  listening for `body_entered`; the `body_entered` connection is removed
  since polling covers both the already-inside and enters-during-strike
  cases. Found right after wiring `GlassCannon`/`MobileBruiser` attacks (see
  "What's implemented"), but affected `HeavyHitter` from the start.
- `project.godot` had **no `[autoload]` section** — `Constants`, `EventBus`,
  and `GameState` were referenced everywhere as globals but never registered
  as singletons, so the entire project failed to parse. Fixed.
- `ComposureComponent.get_damage_multiplier()` applied its Break bonus to
  *all* incoming damage; Section 07 explicitly excludes spells ("increased
  damage taken from attacks and skills, not spells"). Both it and
  `Enemy.take_damage()` now take an `is_spell` param (defaults to `false`,
  non-breaking — nothing calls `Enemy.take_damage` yet since attack input is
  still unwired).
- `DamageCalculator.calculate()`'s `base_scale := lerp(...)` inferred
  `Variant` (the builtin `lerp()` is polymorphic over float/Vector2/Vector3/
  Color, so its return type isn't statically narrowed even with float
  inputs), which Godot 4.7 hard-errors on for `:=` declarations. Dormant
  since the scaffold's first commit — nothing had ever referenced
  `DamageCalculator` by static type, so the file was never actually
  compiled during a headless load until `Player.gd` started calling
  `DamageCalculator.physical_mitigation()` (see below). Fixed by explicitly
  typing `base_scale: float`, which also resolved the type-inference errors
  it was cascading into `effective_scale`/`scaled_stat_damage`.
- **Root cause of the weapon-not-visible bug, finally found**: `#` comment
  lines inside a `.tscn` `[node]` block are unreliable in this Godot
  version — one placed right after a `[node ...]` header silently drops
  the property on the very next line (confirmed: `WeaponSocket`'s
  `position = Vector3(0.25, -0.2, -0.6)` was parsing as `(0, 0, 0)` the
  entire time, meaning it sat exactly at the camera's own position, inside
  the near clip plane — invisible regardless of size, color, or shading),
  and one placed at the *end* of a block can even break the parse of
  **subsequent node declarations entirely** (`ShieldMesh` and
  `HealthComponent` stopped existing at runtime after one was added there,
  confirmed via `get_node()` failing on both). This wasn't something either
  of the two previous fix attempts (orientation, then unshaded material)
  could have caught — both were correct changes given the position data
  the file *appeared* to contain, but the position was never actually
  reaching the running scene. Found by instantiating `Player.tscn` inside
  the real project boot with temporary diagnostic prints and reading back
  the actual runtime `position`/`global_position` values, since reasoning
  about the transform math alone (done twice) couldn't have caught a
  parser-level bug. **Fix: `.tscn` `[node]` blocks in this project now
  carry no `#` comments at all** — this was the only file in the project
  that had any (confirmed via a full-project grep), so nothing else needed
  auditing. Comments on `.gd` scripts are unaffected; this is specific to
  the `.tscn` text-resource format.

## Correction from v0.1

The first pass of this scaffold was built top-down 2D. That was wrong — this
is a first-person ARPG. Everything below reflects the corrected 3D version.
Rebuilt: Player (CharacterBody3D + head/camera rig + mouse look), Enemy base
and all three archetypes (CharacterBody3D + capsule placeholder meshes,
color-coded per archetype since there's no art yet), TestArena (3D room with
floor, lighting, WorldEnvironment). Unaffected by the rework: Constants,
EventBus, GameState, FateBoard, ChainCalculator, Slate/Modifier/Ability/
Weapon resources, DamageCalculator, Stance/Composure/ParryRiposte logic,
StatSheet, HealthComponent, WardComponent — none of that cares about camera
perspective.

## What's implemented (functional, untested in-editor)

- **First-person controller**: WASD relative to body facing (not camera
  pitch), mouse look with clamped vertical range, jump, sprint, Esc to
  release mouse cursor
- **Fate Board + placement UI**: `FateBoard.gd` (grid placement + Aether
  budget) and `ChainCalculator.gd` (flood-fill chain detection + tiered bonus
  math), now with a real UI in `ui/fate_board_editor/` — `FateBoardGrid.gd`
  custom-draws a **bounded 32x32 window** into the board (Section 10 calls the
  real board "effectively unlimited," gated by Aether not space; a
  pannable/infinite canvas wasn't worth building to validate the math) with a
  green/red hover preview, `R`/`Q` to rotate/flip before placing, right-click
  to remove. The palette lists every `.tres` under `data/slates/instances/`
  as a stand-in for the not-yet-built Satchel/loot system — as if the player
  owns one of each. Placing/removing recomputes chains and now actually
  fires `EventBus.chain_recalculated` (declared since the start, never
  emitted before). Opens via a "Fate Board" button in the pause menu.
- **Slate data model**: `Slate.gd` + `SlateModifier.gd`, with two
  hand-authored instances (`sample_entropic_slate.tres`, `unbound_chorus.tres`)
- **Ability data model**: `Ability.gd`, with a coherent Cold kit hand-authored
  from Section 26's Ability Staging Ground — `ice_pulse.tres`, `comet.tres`,
  `winters_eye.tres`, `frost_armor.tres` in `data/abilities/instances/`.
  `damage_type`/description text is doc-sourced; `motion_value`,
  `scaling_grade`, `cooldown_seconds`, and `resource_cost` are placeholder
  tuning (relative to each ability's described weight) since the doc never
  gives per-ability numbers, only the formula they plug into. Not yet wired
  to anything castable — no ability-execution system exists yet.
- **Combat loop**: `StanceComponent`, `ComposureComponent`,
  `ParryRiposteHandler`, `DamageCalculator` (full Section 11 formula) — all
  camera-agnostic. The loop is now actually playable end to end (see below).
- **Entities**: `Player` (first-person) + `Enemy` base with three Trinity
  Rule archetype subclasses, each a distinct colored capsule (yellow Glass
  Cannon, blue Mobile Bruiser, dark red Heavy Hitter) as placeholder visuals
- **One enemy attack**: `HeavyHitter` threatens the player via
  `EnemyMeleeAttack.gd` (Idle → Telegraph → Strike → Recovery, distance-based
  — no physical hitbox yet since nothing moves or animates). Telegraph
  flashes the capsule to a warning color that eases back to normal over the
  telegraph window — the color's *return* is the "hit is coming now" cue,
  since there's no animation yet. Strike either lands (damage to Player, Ward
  absorbs the Esoteric portion first) or gets parried (Stance damage to the
  enemy instead) depending on whether `attempt_parry()` fires during the
  window. GlassCannon/MobileBruiser are still harmless dummies.
- **Debug overlay**: numeric readout of Aether budget, chain bonuses, damage
  dealt, parries, Stance damage, and Composure breaks — no art needed to
  validate formulas or the combat loop
- **Pause menu**: `ui/pause_menu/` — Esc pauses the tree, releases the mouse,
  and shows Resume/Inventory/Fate Board/Quit to Desktop. First of the menu
  family (main menu still unbuilt).
- **Items & Equipment data model**: `Item.gd` (base: id/name/rarity/
  `equip_slot`/sockets/`affixes`) in `data/items/`, with `Armor.gd`
  (`data/armor/`) and `Shield.gd` (`data/shields/`) extending it, and
  `Weapon.gd` refactored onto it too (`weapon_slot: String` → the shared
  `equip_slot` enum, plus a new `is_two_handed`). `EquipmentComponent.gd`
  (`systems/equipment/`) is a Player-attachable Node holding a full loadout
  per Section 13 (4 armor pieces, 2 weapon slots + offhand + Conduit +
  Secondary, Amulet/Belt/4 Rings) — `equip()` enforces the two-handed rule
  (equipping one clears sidearm + offhand). Player now equips
  `crude_greatsword.tres` (two-handed) + `padded_coat.tres` by default;
  `guardians_kite_shield.tres` also exists as a proven sample but isn't
  equipped by default since it'd be a no-op with a 2H weapon. Deliberately
  **not** a loot system — no procedural affix rolling, no Gem/Jewel effects
  (only a socket *count*), no Section 25 item-table content. Matches
  Section 24's own "all item mod pools" deferral.
- **Inventory & Equipment UI**: `ui/inventory/` — user-requested rework from
  the original flat-list version into a **slot-based grid inventory** +
  **paper-doll equipment diagram**, matching two ARPG reference screenshots
  (a plain uniform grid of square slots, and a Diablo/PoE-style silhouette
  layout with the weapons flanking a center torso column). Left panel is a
  `GridContainer` (5 columns, padded to a minimum 35 cells so it reads as a
  real inventory rather than an exact-fit list) scanning the same
  `data/{armor,shields,weapons,items}/instances/` "owns one of each"
  stand-in as before — click a filled cell to equip. Right panel is the
  paper-doll: `PrimaryWeapon`/`Offhand` are tall slots flanking a center
  column (Helmet → Amulet → Body Armour → Belt → Gloves/Boots), with the 4
  Rings split two-and-two on the flanking columns and `Sidearm`/`Conduit`/
  `Secondary` in a small row above the helmet (no natural doll position for
  a 3rd/4th weapon slot without real art to arrange around — most ARPGs
  fold those into "weapon swap", but Section 13 models them as distinct
  equip slots). Still placeholder-art, per gap #8 below: every slot is a
  colored square, not an icon — `Constants.DAMAGE_TYPE_COLOR` for weapons,
  `Constants.ITEM_RARITY_COLOR` for everything else (same color language
  `WeaponMesh`/`SidearmMesh`/`ShieldMesh` already use on the Player model),
  with the item's name/rarity in a tooltip. This is a **uniform grid**, not
  the Tetris-grid Satchel (Section 14) — `Item.gd` still has no
  width/height footprint field, a deliberate scope call confirmed with the
  user rather than a silent guess (see gap #7). The two-handed conflict
  still surfaces via `EquipmentComponent.equip_failed` (mirrors
  `FateBoard.placement_failed`). Opens via an "Inventory" button in the
  pause menu.
- **Armor mitigation wired into `Player.take_damage()`**: new
  `EquipmentComponent.get_total_armor()` (sums `armor_value` across
  helmet/body/gloves/boots/offhand) feeds a new
  `DamageCalculator.physical_mitigation(armor, hit_damage)` implementing
  Section 16's `Armor / (Armor + 6 x Hit Damage)`, applied only to Physical-
  category damage before Ward/Health. The doc splits Kinetic (full %) /
  Piercing (partial) / Explosive (flat) mitigation behavior but never gives
  a concrete ratio for the Piercing/Explosive cases, so all three currently
  get the same full-percentage formula — flagged below, not silently
  guessed. Evasion (Dodge/Deflection) and Ward's real 5-bracket system are
  still unwired — Ward keeps its existing simple absorb-first flow.
- **Player melee attack**: `systems/combat/PlayerMeleeAttack.gd` — the
  `attack` action is finally wired (Idle → Windup → Strike → Recovery,
  input-triggered counterpart to `EnemyMeleeAttack.gd`'s state shape). This
  is the first thing that calls `DamageCalculator.calculate()` with a real
  equipped `Weapon` + `StatSheet` (main stat resolved via new
  `Constants.DAMAGE_TYPE_MAIN_STAT`, Section 10) and the first thing to
  exercise `StanceComponent.apply_attack_stance_damage()`, which had sat
  unused since it was written. Hit detection is a **real `Area3D`**
  (`Player.attack_hitbox`, child of the blade mesh so it physically sweeps
  through the swing arc) — `body_entered` filtered by an `Enemy` cast
  rather than new collision layers, since nothing else in the project uses
  custom layers yet and everything defaults to layer 1 (the cast safely
  ignores the floor/self, returns `null` for non-`Enemy` bodies). Replaced
  the original range+cone placeholder, which was never actually swept
  through space. No Slate/gear stat aggregation feeds in yet (empty
  Increased/More pools) — that aggregation system doesn't exist.
  `motion_value` is a flat placeholder constant, standing in for a "Basic
  Attack" skill that doesn't exist since there's no skill system yet.
  `Weapon` gained a `scaling_grade` field the formula needs (nothing had
  set one before since nothing called `calculate()` with a real weapon).
  `EnemyMeleeAttack` still uses its original distance-only placeholder —
  not given the same `Area3D` treatment yet.
- **Attack feel**: a placeholder blade (`WeaponMesh`, colored by the
  equipped weapon's damage type) swings via a procedural `Tween` on
  `WeaponSocket` — not a baked `AnimationPlayer`, since hand-authoring
  `Animation` keyframes in text format without the visual editor is
  fragile; a `Tween` arc produces the same result and is far more reliable
  to author as code. The swing `Tween`'s out-motion spans the *entire*
  windup (not just part of it) so the blade — and its `attack_hitbox` —
  arrives at full extension exactly as Strike begins and monitoring turns
  on, instead of already retracting by the time hit detection was active.
  Landed hits trigger a brief camera-shake `Tween` and a hitstop
  (`Engine.time_scale` dip via a `create_timer(..., ignore_time_scale=true)`
  so the un-freeze timer isn't itself slowed by the freeze it creates).
  Directly resolves gap #5 below (first-person melee weight).
- **Weapon/shield visibility** — the actual bug was a `.tscn` comment
  parser issue, not geometry (see "Recent fixes" above for the full story).
  `WeaponSocket`'s position was silently never applying, so it sat exactly
  at the camera's position the whole time regardless of orientation, size,
  or material — no amount of geometry tuning could have fixed it. Now
  confirmed via runtime diagnostic reads (not just static reasoning) that
  `weapon_mesh`'s position relative to the camera is exactly what was
  authored. The orientation/unshaded-material changes from the first two
  passes are still in place and still reasonable (vertical blade, tilted,
  unshaded so lighting can't hide it) but weren't the actual fix. Still not
  independently confirmed *visually* in the real editor (no display in
  this environment) — worth a direct look now that the root cause is
  actually fixed.
- **Shield visual**: mirrors the weapon treatment — a new `ShieldSocket`/
  `ShieldMesh` (a flattened `CylinderMesh` disc) on the left, symmetric to
  `WeaponSocket`. Visibility and color both driven by
  `EquipmentComponent.offhand`: hidden whenever it's empty (no shield
  equipped, or cleared by a two-handed weapon), and colored by the new
  `Constants.ITEM_RARITY_COLOR` (Section 18's White/Blue/Yellow/Orange/Peach
  rarity column) rather than a damage type — `Shield` isn't tied to one of
  the 9 damage types the way `Weapon` is, so rarity was the nearest
  doc-sourced axis to key a placeholder color off of. Same static-at-`_ready()`
  limitation as the weapon mesh (no live re-sync on equip change).
- **Debug overlay now records damage direction**: `_on_damage_dealt`
  previously printed a bare `Dmg: X (type N)` with no indication of who
  hit whom, so there was no way to tell a player-dealt hit from one taken.
  Now prints `YOU dealt X <type> dmg to <target>` when `source is Player`,
  and `<source> dealt X <type> dmg to <target>` otherwise (damage type
  resolved to its name via `Constants.DAMAGE_TYPE_NAME`, not a raw int).
- **Ranged weapons + weapon swapping**: `systems/combat/PlayerRangedAttack.gd`
  fires `entities/projectile/Projectile.tscn` — a straight-line `Area3D`
  (no gravity/arc), colored by damage type same as the other placeholder
  meshes, that self-destructs on hitting an `Enemy` (dealing damage) or
  anything else (just stops), or after a 3s lifetime. Damage is computed
  once at fire time from the equipped `sidearm_weapon` + `StatSheet` (same
  `DamageCalculator` shape `PlayerMeleeAttack._deal_damage()` established)
  and baked into the projectile, so a weapon swap mid-flight can't
  retroactively change an already-fired shot. `V` swaps `Player`'s active
  weapon slot between Primary and Sidearm — `attack` routes to
  `PlayerMeleeAttack` or `PlayerRangedAttack` accordingly, and a new
  `SidearmMesh` (distinct shape from the blade, not a recolor of it) shows
  in its place. Player now equips `worn_pistol.tres` (Section 25 Service
  Pistol Line 1 Tier 1) as sidearm by default so this is immediately
  testable. Only Primary/Sidearm are wired — Conduit and Secondary
  (Throwable) equip slots still have no attack behind them.
- **`EnemyMeleeAttack` upgraded to a real `Area3D` hitbox**, same
  treatment `PlayerMeleeAttack` already got. Unlike the player's
  blade-swept hitbox, this one is a **static** sphere
  (`Enemy.attack_hitbox`, now on the base `Enemy.tscn` so all three
  archetypes have it) centered on the enemy — enemies don't move or
  rotate to face the player yet, so there's nothing to sweep it through.
  Radius (`2.5`) is a scene-level constant, not driven by
  `EnemyMeleeAttack.attack_range` per instance the way the old distance
  check was — mutating a shared `.tscn` sub-resource's shape at runtime
  risks affecting other enemy instances, since sub-resources aren't
  guaranteed distinct per instantiation. The `Idle` state's proximity
  check (aggro range) is unchanged — that was never the placeholder being
  replaced, only `Strike`'s hit resolution was.
- **`GlassCannon` and `MobileBruiser` now threaten the player too** — both
  were harmless dummies until now (only `HeavyHitter` had a `MeleeAttack`
  child). Same `EnemyMeleeAttack` component, tuned per their Trinity Rule
  description since the doc gives archetype *behavior* (Section 21) but no
  per-archetype attack numbers: `GlassCannon` (Fast + Lethal) gets a short
  `telegraph_duration` (`0.6`, harder to react to/parry) and short
  `recovery_duration` (`0.7`, attacks again quickly); `MobileBruiser` (Fast
  + Tanky) gets a similarly short telegraph (`0.75`) but the lowest
  `damage_amount` (`14`, "lower individual damage" per its doc
  description). `HeavyHitter`'s existing numbers (`telegraph 1.1` /
  `damage 28`) are unchanged and now read as the slow-but-devastating
  anchor between the two. `MobileBruiser`/`HeavyHitter` still share the
  same static (non-swept) sphere hitbox and KINETIC damage type —
  `GlassCannon` was later moved off melee entirely, see below. All tuning
  here is placeholder/invented, not doc-sourced, same as gap #6's Ability
  numbers.
- **Enemies chase the player**: `Enemy.gd` now drives its own movement
  every physics frame (`chase_range`/`stop_distance`/`retreat_distance`,
  all exported and tuned per archetype) instead of standing still —
  `move_speed` was declared from the start but never actually used for
  movement until now. Deliberately decoupled from the attack components:
  `Enemy` only handles translation toward/away from the player,
  `EnemyMeleeAttack`/`EnemyRangedAttack` independently decide *when to
  attack* off their own range checks, same compositional split
  `PlayerMeleeAttack`/`PlayerRangedAttack` already have from `Player`. No
  facing/rotation yet — the capsule placeholder mesh is rotationally
  symmetric so there'd be nothing to see. No pathfinding either (straight-
  line toward the player only) — fine for TestArena's one open room, would
  need real navigation if obstacles are ever added.
- **`GlassCannon` rebuilt as a ranged kiting skirmisher**, replacing its
  melee attack from the session before — new
  `systems/combat/EnemyRangedAttack.gd` (Idle → Windup → Fire → Cooldown,
  same telegraph shape as `EnemyMeleeAttack`) fires the same
  `Projectile.tscn` `PlayerRangedAttack` uses, aimed at the player's
  position at the moment Windup completes (not homing). Paired with a high
  `stop_distance` (`7.0`) and a `retreat_distance` (`4.5`) on `Enemy`, so it
  holds near its `fire_range` (`9.0`) and backs away rather than sitting in
  melee reach where its low health folds instantly — a deliberate design
  call (not requested verbatim): "Fast + Lethal... dies quickly" reads at
  least as well as a kiting archer as a melee rusher, and it keeps all
  three archetypes distinct by *engagement style*, not just numbers.
  `HeavyHitter`/`MobileBruiser` stay melee brawlers. Required generalizing
  `Projectile.gd`, which only ever damaged `Enemy` bodies before — it now
  branches on `source is Player` to decide whether to damage the first
  `Enemy` or the `Player` it touches, and an enemy-sourced hit now runs
  through `ParryRiposteHandler.attempt_parry()` first, same as
  `EnemyMeleeAttack.Strike` — parrying was never actually melee-specific in
  the API, just never exercised from a projectile before. Had to spawn the
  projectile offset forward of the shooter (`0.7` along the fire
  direction, past the enemy's own `0.45`-radius capsule) — spawning at the
  enemy's own center (as originally written) would've put it inside the
  shooter's own collision shape and self-triggered `body_entered`
  immediately; `PlayerRangedAttack` never hit this because `WeaponSocket`
  is already forward of Player's capsule.
- **Player death + restart**: `Player.gd` now connects
  `HealthComponent.died` (previously only `Enemy` did) and forwards it to
  a new `EventBus.player_died` signal. `ui/death_screen/DeathScreen.tscn`
  listens for it, pauses the tree, shows the mouse cursor, and offers
  Restart (`get_tree().reload_current_scene()` — the simplest possible run
  reset for a vertical slice with no save/load layer) or Quit. Not a
  `blocking_menu` screen like `PauseMenu`/`FateBoardEditor`/
  `InventoryScreen` — nothing to toggle or Esc out of once you're dead.
- **Player `StatSheet` finally has real numbers**: new
  `data/stats/instances/player_baseline.tres` (Vitality/Strength/Instinct/
  Arcane/Enigma/Intellect all `10.0` — an invented flat testing baseline,
  matching `StatSheet.gd`'s own header comment that vertical-slice values
  "are set directly for testing the damage formula in isolation," not a
  doc-sourced number), assigned as `Player.tscn`'s default `stat_sheet`.
  This is what actually fixes the always-0-damage bug above — `Player.gd`'s
  code-fallback path (`stat_sheet == null`) mirrors the same values so
  nothing silently breaks if a future scene forgets to assign the
  resource. Nothing else currently reads `StatSheet` — enemies deal damage
  via flat exported `damage_amount` values, not stat scaling, so there's
  no equivalent gap on their side to fix.
- **PoE-style stat cards** for items and Slates, user-requested from a
  reference screenshot. `ui/item_card/ItemCard.gd` is a builder, not a
  fixed template — it branches on `Weapon`/`Armor`/`Shield`/generic `Item`
  vs `Slate` to show the fields that actually exist on each (damage/
  scaling grade for weapons, armor/evasion/ward for armor, block for
  shields, size/Aether cost/hybrid-chain info for Slates), title+border
  colored by rarity (`Constants.ITEM_RARITY_COLOR` /
  new `Constants.SLATE_RARITY_COLOR` — the latter didn't exist before,
  since only `ItemRarity` had a doc-sourced color column; `SlateRarity`'s
  is invented, reusing the same 5 colors plus one new violet for its extra
  `VERY_RARE` tier). Every line is pulled straight from existing data —
  `ItemAffix`/`SlateModifier.description` are already player-facing text —
  no new mechanics invented (no level-requirement line, since `Item.gd`
  has no such field).
  `ui/item_card/ItemSlotButton.gd` (a `Button` subclass) wires this in via
  Godot's own `_make_custom_tooltip()` hook — hovering any occupied slot
  shows the real card instead of Godot's plain-text tooltip, with
  positioning/hover-delay/auto-hide all handled by the engine, not custom
  code. Both `InventoryScreen` (grid + all 15 paper-doll slots) and
  `FateBoardEditor` (Slate palette) now use `ItemSlotButton` instead of
  plain `Button`. Building this surfaced that Slate rarity never had a
  color table at all (only `ItemRarity` did) — `FateBoardGrid`'s own grid
  rendering still doesn't use rarity color anywhere, worth revisiting for
  consistency once the grid gets any further visual pass.

## Controls (current bindings)

| Action | Key |
|---|---|
| Move | WASD |
| Look | Mouse |
| Sprint | Shift |
| Jump | Space |
| Parry | F |
| Attack (melee or ranged, depending on active weapon) | Left Mouse |
| Swap active weapon (Primary / Sidearm) | V |
| Pause menu (Resume / Inventory / Fate Board / Quit) | Esc |
| Open Fate Board directly | P |
| Open Inventory directly | B |
| Rotate pending Slate *(Fate Board editor only)* | R |
| Flip pending Slate *(Fate Board editor only)* | Q |

P/B work from anywhere — gameplay, the pause menu, or the other screen —
and jump straight to their target, closing whatever else was open. Pressing
the same key again while already on that screen closes it. All routed
through `PauseMenu._toggle_screen()`, the single place that knows how to
switch between the pause menu and the "blocking_menu" group screens
(`FateBoardEditor`, `InventoryScreen`) without stacking two open at once.

## Flagged design gaps (need your call, not resolved unilaterally)

Resolved against the design docs (`documents/`):

1. ~~Chain scoping~~ — confirmed. Section 10's Mastery system and Hybrid
   Slates ("bridging two chains") only make sense if chains are per-tag,
   exactly what `ChainCalculator` assumes.
2. ~~Non-damage-type Slate tags~~ — confirmed intentional, not a stopgap.
   Patch v3.1's Flame Wall example uses "A Spell Slate modifier" right
   alongside Fire Slate modifiers. `category_tag_override` stays as the
   mechanism, just no longer flagged as a guess.

Still open:

3. **Ward restore-on-parry ratio**: placeholder 15% of max Ward — Section
   07/16 both confirm this is deferred to playtesting, no number given.
4. **Stance depletion weights**: the *ordering* is now confirmed (Blunt/
   Explosive strong → Piercing/ranged moderate → Spells weakest, Section 07 +
   glossary), but still no percentages anywhere, so Physical 1.0 / Elemental
   0.6 / Esoteric 0.35 remains a well-justified guess, not a canonical value.
5. **First-person melee weight** (Pillar 2) — partially addressed.
   `PlayerMeleeAttack` now does camera shake + hitstop + a swinging
   placeholder blade (see "What's implemented"), which is the mechanical
   answer, but the docs are still camera-agnostic on *how it should feel*
   (timing, intensity), and there's still no real viewmodel. Worth a design
   pass once art exists to actually tune it, rather than the current
   arbitrary constants.
6. **Ability numeric tuning**: `motion_value`, `scaling_grade`,
   `cooldown_seconds`, `resource_cost` on the four new Ability instances are
   invented (relative to each ability's described weight) — the doc gives
   the damage formula and flavor text but never per-ability numbers.
7. **Fate Board UI is a bounded 32x32 window**, not the "effectively
   unlimited" board Section 10 describes — a deliberate scope cut (see
   "What's implemented"), not a misreading. Revisit with real pan/zoom if a
   Slate loadout ever needs more room than that.
8. ~~Inventory UI is a flat list~~ — partially addressed: it's now a
   slot-based **uniform grid** + paper-doll equipment diagram (see "What's
   implemented"), not the flat list, but still not the Tetris-grid Satchel
   (Section 14) — `Item.gd` has no width/height footprint field, and the
   user explicitly confirmed uniform 1x1 cells over building real
   footprint packing when this was reworked. Revisit with real footprint
   fields + a packing algorithm (similar to what the Fate Board editor
   already does for Slates) if item size ever needs to matter for
   something beyond equip/unequip.
9. **Armor mitigation applies one formula to all Physical damage types**:
   Section 16 says Kinetic gets it "full," Piercing "partial," Explosive as
   a "flat reduction," but gives no ratio for the latter two, so
   `DamageCalculator.physical_mitigation()` currently treats all three the
   same. Needs either a design call or playtesting data to differentiate.
10. **`PlayerMeleeAttack`'s `motion_value`/hitbox radius (`0.35`)/swing arc/
    windup-strike-recovery timings are all invented placeholders**, not
    doc-sourced — there's no "Basic Attack" skill defined anywhere to pull
    real numbers from (Section 11 motion values live on skills, not bare
    weapons). Reach in particular needs real playtesting to tune — no way
    to feel out "does this look like it should have hit" without the
    editor.
11. **Single-target melee, no cleave**: `PlayerMeleeAttack` stops
    monitoring after the first `Enemy` its hitbox touches, not all of
    them — Section 25's AoE/reach weapon mods (Halberd's "+20% AoE
    radius," Whip's "+24% AoE radius," etc.) aren't modeled. Fine for a
    single starting Greatsword, will need revisiting once weapon variety
    matters.
12. ~~`EnemyMeleeAttack` still uses its original distance-only placeholder~~
    — stale, already resolved (see "What's implemented" item 15 and #6
    above): it has the same `Area3D` hitbox `PlayerMeleeAttack` uses, just
    static rather than swept.
13. **Player `StatSheet` baseline (`10.0` flat across all six stats),
    enemy chase/kite numbers (`chase_range`/`stop_distance`/
    `retreat_distance`), and `EnemyRangedAttack`'s `fire_range`/
    `windup_duration`/`cooldown_duration`/`damage_amount` are all invented
    placeholders**, not doc-sourced — same category as gap #6/#10. The doc
    doesn't specify baseline character stats for the vertical slice
    (per-slate/gear stat totals are the real system, Section 10), and has
    nothing on enemy movement/kiting behavior at all (Section 21's Trinity
    Rule covers combat role, not locomotion). Needs playtesting to tune,
    not a doc lookup.
14. **Turning `GlassCannon` into a ranged kiter (vs. keeping it a melee
    rusher) was a judgment call, not something explicitly requested** — see
    "What's implemented" for the reasoning (genre convention + archetype
    differentiation by engagement style). Worth confirming this is the
    direction wanted before building more content around it (e.g. more
    ranged-archetype variety, or itemization that assumes GlassCannon
    behaves a specific way).

## Explicitly not built yet (per Vertical Slice Brief scope)

Crafting (Cube/Brands/Corruption), procedural loot rolling, full 9-damage-type
coverage, Jewelry/Gems/Sockets, co-op, real viewmodel/weapon art (placeholder
primitives only). Attack input is now wired for Primary/Sidearm (melee +
ranged) — Conduit and Secondary (Throwable) still have no attack behind
them. Enemies are no longer static dummies (see "What's implemented") —
they chase and attack, but it's still just a distance-driven state
machine, not pathfinding/navigation (no obstacle avoidance — TestArena is
one open room, so nothing to path around yet) or any higher-level
behavior tree.

## Opening this project

1. Install Godot 4.7.1+ (GL Compatibility renderer for broad hardware support
   during prototyping).
2. Open `project.godot` from the Godot project manager.
3. Run scene: `levels/test_arena/TestArena.tscn` (already set as main scene).
4. You should see a floor plane, three colored capsules (enemies) ahead of
   the player's starting position, and be able to walk/look around
   immediately — mouse is captured on scene start.

## Suggested next Claude Code session

1. ~~Wire one enemy attack (telegraph → hitbox → `attempt_parry` check)~~ —
   done. `HeavyHitter` now telegraphs (color flash) and strikes; the
   Parry → Stance → Composure Break loop is playable and visible via the
   debug overlay. `execute_riposte()` is still unwired (needs an Ability
   resource — see #3 below), and the telegraph is a flat-color flash rather
   than the camera-shake/hitstop/viewmodel feel described in gap #5, since
   that's explicitly a design conversation, not a code task.
2. Resolve flagged gap #5 above before building much more combat feel —
   worth a short design conversation on how melee weight communicates in
   first-person.
3. ~~Populate `data/abilities/instances/` with the 3-4 abilities from the
   brief~~ — done. Ice Pulse, Comet, Winter's Eye, and Frost Armor
   (Section 26's Cold kit) are hand-authored. Still no ability-execution
   system to actually cast one, and `execute_riposte()` stays unwired until
   there's an input path that passes a `can_trigger_riposte` Ability in.
4. ~~Build the Fate Board placement UI~~ — done, see "What's implemented."
   Bounded 32x32 grid, palette scanned from `data/slates/instances/`, opens
   from the pause menu. Real pan/zoom and a real Satchel/loot source for the
   palette are still open (gap #7).
5. Add 5-8 more hand-authored `.tres` Slates following the pattern in
   `sample_entropic_slate.tres` — now visible/placeable immediately, since
   the editor palette scans the directory rather than hardcoding a list.
6. ~~Extend `EnemyMeleeAttack` (or give GlassCannon/MobileBruiser their own
   tuned instances of it) once more than one enemy should threaten the
   player~~ — done. Both now have their own tuned `MeleeAttack` child; see
   "What's implemented."
7. ~~Items/Equipment data model~~ — done, see "What's implemented."
   `Item`/`Armor`/`Shield`/`Weapon` + `EquipmentComponent`.
8. Main menu — flagged by the user as wanted, not yet started.
9. ~~Inventory UI~~ — done, see "What's implemented." List-based (gap #8),
   opens from the pause menu, equip/unequip both work and are visible
   live. The Satchel's real grid-packing is still open if item footprint
   ever needs to matter.
10. ~~Wire equipped gear into the actual damage/defense math~~ — partially
    done. `EquipmentComponent.get_total_armor()` +
    `DamageCalculator.physical_mitigation()` (Section 16) now reduce
    Physical damage to the Player by equipped Armor before Ward/Health —
    see "What's implemented" and gap #9. Weapon `base_damage` still isn't
    read anywhere, since there's no player-attack input path to exercise
    it yet (see #13 below).
11. ~~Bind Fate Board/Inventory to direct hotkeys~~ — done. `P`/`B`, routed
    through `PauseMenu._toggle_screen()`. See "Controls."
12. **User-requested, "eventually"/"when possible" — not yet scheduled:**
    - **Fate Board as a real square board.** Current grid is a fixed 32x32
      window (gap #7); user wants an actual square-shaped board rather than
      this arbitrary bounded rectangle. Needs a decision on real size and
      whether pan/zoom comes with it.
    - ~~ARPG-style equipment slot art.~~ — done, see "What's implemented."
      `InventoryScreen`'s equipment panel is now a paper-doll layout
      (`PrimaryWeapon`/`Offhand` flanking a center torso column), matching
      the Diablo/PoE-style arrangement the user asked for. Still no real
      icon art — slots are colored squares (rarity/damage-type color) with
      a tooltip, same placeholder convention as the weapon/shield meshes —
      revisit the visual treatment (not the layout) once real slot icons
      exist.
13. ~~Player melee attack + simple attack visuals~~ — done, see "What's
    implemented." `attack` is wired end to end (`PlayerMeleeAttack.gd`):
    swing, hit detection, real `DamageCalculator` + `Weapon` damage,
    `StanceComponent` depletion, camera shake, hitstop. Used `Tween`
    instead of `AnimationPlayer` for the swing/shake (gaps list doesn't
    need a new entry for this — it's a straight implementation-technique
    call, not a doc ambiguity). Gaps #10/#11 cover what's still invented/
    unmodeled (placeholder timings, no cleave).
14. ~~Ranged weapons + projectiles~~ — done, see "What's implemented."
    `PlayerRangedAttack.gd` + `Projectile.tscn`, `V` to swap to Sidearm.
    Conduit and Secondary (Throwable) still have nothing behind them —
    same pattern would extend to both once there's a reason to (Conduit
    is spell-cast, Secondary is a consumable-count throwable, neither is
    "just another ranged weapon" mechanically).
15. ~~`EnemyMeleeAttack` real hitbox~~ — done, see "What's implemented."
    Static `Area3D` sphere on the base `Enemy.tscn`, same
    `body_entered`-filtered-by-cast pattern as `PlayerMeleeAttack`. Radius
    is a scene constant (gap noted in "What's implemented"), not yet
    per-archetype-tunable.
16. Weapon-swap visual/audio feedback is currently just an instant mesh
    swap — no swap animation/delay. Reasonable for a first pass; revisit
    alongside gap #5 (melee weight) if swapping ever needs its own "feel."
