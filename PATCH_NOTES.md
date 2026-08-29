# Patch Notes

Chronological log of what changed and why — bugs found, root causes,
judgment calls made without stopping to ask. `README.md` describes the
project as it stands today; this file is the history of how it got
there. Most recent first.

---

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
