# Project Aether — Development Reference

System-by-system reference for working on the project: what exists, where
it lives, which numbers came from the design docs and which were invented,
and the open design gaps. Godot 4.7.1, GDScript, first-person 3D with an
endgame-first structure (a Hub with a Reality Engine leading into
instanced Figment maps, no campaign yet). The player-facing overview is
`README.md`.

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

**UI style (v4.33)**: everything draws through `ui/theme/AetherStyle.gd` (palette, fonts, plates, dividers, dials) and the project theme `ui/theme/aether_theme.tres` (regenerate with `Godot --headless --path . --script res://tools/build_ui_theme.gd` after changing `build_theme()`). Full-screen menus use `layer = AetherStyle.SCREEN_LAYER` plus `AetherStyle.style_screen(self)`, and the HUD hides while one is open. Tooltips are drawn by the `TooltipFollow` autoload, not Godot's popup (its delay is set out of reach): it reads the hovered control's tooltip every frame, so a tooltip shows at once, swaps the moment the cursor crosses into another slot, follows the cursor and rebuilds every 0.25s to track changes. Controls still supply content through `tooltip_text`/`_get_tooltip()` and `_make_custom_tooltip()`. Scene changes go through the `LoadingScreen` autoload (`LoadingScreen.change_scene(path)`): a threaded load behind a plate with the destination, a tip and a progress bar. `tests/ui_capture/shot.sh` screenshots UI states.

**Player** (`entities/player/Player.gd`): first-person `CharacterBody3D`
(WASD relative to body facing, mouse look, jump, sprint, crouch, slide).
Melee or ranged attack, dispatched automatically by whatever's equipped
in `PRIMARY_WEAPON` (`Weapon.is_ranged`), each a real swept/static
`Area3D` hitbox driving `DamageCalculator`. Parry (`F`) via
`ParryRiposteHandler`, which also handles Riposte: melee-attacking an
enemy while its Composure is broken (see Enemies below) deals 3x motion
value and grants 1 second of player invulnerability instead of a normal
hit. **Counter damage** (2026-08-30, user request, exact wording): melee-
attacking an enemy while ITS OWN attack is mid-swing (`EnemyMeleeAttack`/
`EnemyRangedAttack.is_attacking()` - Telegraph-or-Strike / Windup) instead
deals a flat +15% bonus, a separate, smaller bonus than Riposte's -
`EventBus.counter_hit` fires alongside the normal hit rather than
replacing it (checked first, since Riposte only applies to a Composure-
broken enemy - the two conditions don't usually overlap). Health/Ward/Mana
resource components.

**First-person viewmodel** (`entities/player/player_arm/PlayerArmRig.gd`,
`entities/player/viewmodel/WeaponModelLibrary.gd`, v4.24): every weapon
type has a model (pack FBX or built from primitives), gripped at a handle
position measured from the mesh. Gloved hands and sleeves; two-handers
put the second hand on a second grip, off-hand shields/foci sit in the
left hand, gauntlets show both fists. Poses are hand position + tip
direction + face direction; attack clips are keyframed per weapon family
(light/heavy/charged) and timed to `PlayerMeleeAttack`'s phases. Ranged
gets recoil, muzzle flash, reload and a live bowstring; spells get a cast
gesture. A procedural layer adds mouse sway, walk bob, sprint tuck,
landing dip and equip raise. The shield model only rises while
`ShieldBlock.is_raised`. `tests/viewmodel/capture_viewmodel.tscn` renders
contact sheets of animations for review (needs a window).

**Three distinct melee attacks** (Implementation Brief v3.3 Section 2,
2026-08-31, merged into this existing system rather than a rewrite - see
the flagged gap below): light jab (LMB tap, released under 0.6s hold,
motion value x0.6, a quicker swing), standard thrust (LMB held >=0.6s
then released, x1.0 - the same power/timing every attack already had
before the brief), and charged thrust (stance + LMB press, x1.8,
unchanged mechanically from the pre-brief "special attack," just renamed
- see Weapon Stance below). All three multipliers apply on top of the
existing per-weapon `WEAPON_TYPE_MOTION_VALUE` base. Replaces the old
combo-index cycling (`WEAPON_TYPE_COMBO_POSES`, repeated presses rotating
through a weapon's pose list) - the brief explicitly doesn't want a combo
system, so each weapon's former pose list is now a FIXED pose per attack
type instead (`WEAPON_TYPE_JAB_POSE`/`WEAPON_TYPE_THRUST_POSE` - Greatsword's
two sweeps still exist, one's just always the jab and the other's always
the thrust now, no alternation). Swing timing/arc size are both per-weapon-type
(`WEAPON_TYPE_SWING_DURATION_MULT`/`WEAPON_TYPE_SWING_INTENSITY` in
`PlayerMeleeAttack.gd`) - a Greatsword swings ~2.4x slower with a ~1.3x
bigger arc than the baseline, Dagger/Rapier/Gauntlet close to baseline
with tighter arcs. Every phase has a floor (`MIN_WINDUP`/`MIN_STRIKE`/
`MIN_RECOVERY`) that attack speed can't go below. Hits land only in the
back 40% of Strike (`STRIKE_CONTACT_START`), when the blade is crossing
the screen; impact (hitstop length, camera kick, enemy knockback, the
forward lunge) scales with `_swing_weight()`. Enemies flash white and get
shoved on every hit (`Enemy.flash_hit()`/`apply_knockback()`, bosses take
a quarter of the shove). Idle sway/bob, the
right-click stance/moveset "engine" in full, kicks, and sword/dagger/
cast-specific animations are all still future work - this is the rig
plus the melee swing riding on it, not a complete animation system.

**Raised shield** (`systems/combat/ShieldBlock.gd`, v4.26): with a shield
equipped and the inventory Behaviors tab on "Raise Shield" (the default),
RMB raises the shield instead of the weapon stance. Frontal hits are
negated and drain player Composure (bar under the crosshair, `ComposureBar`);
empty Composure breaks the guard with a 1 s `guard_break` stun. Stance names
and descriptions for the Behaviors tab and HUD live in `data/stance/StanceInfo.gd`.

**Charged stance attacks** (`systems/combat/StanceAttack.gd`, v4.27): in
stance, hold LMB to charge the active page's `MeleeStanceBehavior` and
release to fire. Rapier, Spear, Greatsword, Mace, Shock Lance, Pressure Fist
and Whip have their Stance A built; all tuning lives on the behavior
resources' "Charged attack" fields. Stances without one keep the instant
special.

**Caster stances** (`systems/combat/CasterStance.gd`, v4.31): conduits
replace the weapon stance - Spell Library (keys 1-4 cast the Stance Page,
loadout slots 5-8), Unleash, Stance Buff, Mana Stars and Battlemage, from
each conduit line's `conduit_stance_type`, `spell_page_modifier` and
`stance_buff`. Wands fire bolts on LMB; Rods are passive.

**Ranged aim stances** (v4.30): one `RangedStanceBehavior` per ranged
weapon type (`data/stance/instances/ranged_*.tres`, Patch v3.4 table),
applied by `PlayerRangedAttack` while RMB aims. Shortbow and Longbow have a
second page.

**Instant stances** (v4.29): Water Slices, Sweep, Armor Pierce, Hooking
Strike, Entangle, Repulse, Slice and Dice and Stealth fire on the LMB press
in stance (`StanceAttack.try_instant()`), tuned by the behavior's
"Instant stance" fields. Stealth also scales enemy detection
(`Enemy._detection_range()`).

**Held stances** (`systems/combat/StanceDefense.gd`, v4.28): Guard,
Fortify, Phalanx and Brace apply while RMB holds the stance, from the
behavior's "Held stance" fields. The parry stances use
`parry_window_multiplier` in `ParryRiposteHandler`.

**Weapon stance** (`systems/combat/WeaponStance.gd`, hold Right Mouse,
2026-08-30 user request): preps a per-weapon special. Melee holds a
dedicated `PoseSet.GUARD` - small, mostly rest-adjacent, always played at
intensity 1.0 regardless of weapon - while held, so the weapon stays
clearly visible and forward-facing (a first version reused the special
attack's own big windup pose at an even further boosted intensity, which
swung the sword/arm ~114 degrees around the shoulder and off past the
edge of the screen - user report, fixed by giving stance its own much
smaller pose entirely rather than reusing an attack pose at any scale).
Pressing Attack while active fires `PlayerMeleeAttack.try_charged_thrust()`
(renamed from `try_special_attack()`, 2026-08-31, same mechanic) instead
of a normal swing - a bigger, slower, harder-hitting version of
the swing (1.8x motion value, 1.4x duration, 1.1x arc) using a
weapon-specific pose (`WEAPON_TYPE_SPECIAL_POSE`): Greatsword gets an
exaggerated horizontal `BIG_SWEEP`, Dagger gets a `DASH_THRUST` that also
fires a real forward `Player.try_special_dash()` (sharing the same
dash state/cooldown as the Shift-tap dash, not a separate free resource)
before the stab lands. Ranged weapons aim instead - the camera FOV zooms
in while held, and firing while aimed deals 1.4x damage (no
spread/accuracy system exists to tighten instead). `StanceComponent.gd`
is unrelated - that's an enemy poise/posture bar, not this.

**StanceBehavior** (`data/stance/StanceBehavior.gd`, Implementation Brief
v3.3 Section 4, 2026-08-31): per-weapon-type stance tuning - a move speed
multiplier while stance is active (new: `WeaponStance.get_move_speed_
multiplier()`, now folded into `Player._effective_speed()`) and a parry
window multiplier (new: `ParryRiposteHandler.start_parry_window()` reads
it - only the window DURATION changes, not parry's damage/Ward restore/
Composure effects). Resolved by the active weapon's `weapon_type` from a
dir-scanned `data/stance/instances/`. Only `rapier_stance.tres` exists
(0.8x move speed, 1.5x parry window) - every other weapon type falls back
to a hardcoded 0.75x move speed and an unwidened parry window, per the
brief's own explicit scope (no other weapon types get one yet).

**Weapon base types** (`data/weapons/instances/*.tres`, dynamically
scanned by `ItemRoller.BASE_ITEM_DIRS` for loot drops/Gear Shop stock -
no other registration needed to make a new one obtainable): Greatsword
(two-handed), Dagger, Service Pistol (ranged), and four more added
2026-08-30 - Rapier (fast/light, a pure thruster - always plays
`DASH_THRUST`, the "real" owner of that pose now that a Rapier item
exists), Bow (ranged, two-handed, real model, its own `BOW_RELEASE`
draw-and-loose fire animation), Staff (two-handed, its own `TWIRL_RIGHT`/
`TWIRL_LEFT` wrist-driven combo - not a shoulder-driven cleave like
Greatsword - and reuses `BIG_SWEEP` for its special), and **Gauntlet**
(the fastest weapon in the game, always `JAB`s - an elbow-extension-
driven punch, not a blade-swing pose at all - and doubles as this
project's first conduit-flavored weapon: Aetheric damage instead of
Kinetic, and a `flat_intellect` implicit instead of crit chance, so
equipping it both hits harder for its own damage type AND raises the
Intellect that scales spells - through the existing generic
`flat_<stat>` affix system, which already sums from whichever weapon
slot an item sits in, no new "conduit" mechanic needed). Every melee type
now has a genuinely distinct swing/punch/thrust pose, not just a scaled
copy of another weapon's motion (`PlayerMeleeAttack.
WEAPON_TYPE_JAB_POSE`/`WEAPON_TYPE_THRUST_POSE`/`WEAPON_TYPE_SPECIAL_POSE`),
and ranged weapons
finally have a fire-reaction animation too (`PlayerRangedAttack.
_play_fire_animation()`, cosmetic only - doesn't touch the instant-fire
timing). Real 3D models exist for Greatsword/Dagger/Bow/Staff
(`Player.WEAPON_MODEL_SCENES`, from the same purchased low-poly pack);
Service Pistol/Rapier/Gauntlet have no matching model in that pack and
fall back to the tinted placeholder box. No caster weapon that gates an
innate *ability* exists yet, and spellcasting itself remains entirely
independent of the weapon slot - Gauntlet boosts spell damage by raising
a stat, it doesn't grant or modify which spells you can cast. A `StatSheet`
has three stats, **Strength/Agility/Intellect** (v4.8; Prowess/Finesse/
Resolve before that, and the original six Vitality/Strength/Instinct/
Arcane/Enigma/Intellect before v3.8). Every stat effect is a percentage,
regardless of the weapon/ability's own damage type:
- **Strength**: +1% increased weapon base damage and +4 Life per point.
- **Agility**: +1% increased Attack Speed, Evasion and Critical Strike
  Chance per point (each in the same increased% bracket as gear's own
  bonus; attack speed also shortens ability cooldowns via
  `Player.get_action_speed_multiplier()`).
- **Intellect**: +1% increased spell damage and Ward, plus +3 Mana per point.

`Constants.DAMAGE_TYPE_MAIN_STAT` doesn't feed damage; it only picks a
rolled Slate's Main Stat line. **Mastery and Supercharge were removed**
(v4.8/v4.9). Regen, cast/move speed and Resilience are gear-affix-only
(`StatSheet.misc_bonus`, `EquipmentComponent.compute_misc_bonuses()`);
Crit Damage/Debuff Effectiveness/Stamina are real `ItemRoller.AFFIX_POOL`
entries with no consumer wired up yet. There's no manual allocation on
level up. Stats come from four sources summed in `StatSheet.get_stat()`:
the fixed baseline (`player_baseline.tres`), +0.6 each per level above 1
(`GameState.get_level_stat_bonus()`), gear `flat_<stat>` affixes
(`EquipmentComponent.compute_stat_bonuses()`), and placed Slates' stat
lines, each amplified by `(1 + its chain's bonus)` (`ChainCalculator.
slate_stat_bonuses()`).

**Crouch & Slide** (`entities/player/Player.gd`, `Ctrl`): both invented,
no doc-sourced design exists for either. Hold Ctrl to crouch (shrinks the
collision capsule + lowers the camera, smoothly interpolated, slower move
speed). Tap Ctrl while sprinting and moving to slide instead — a burst of
speed along the current heading that decays over half a second, ending
into a crouch if Ctrl is still held or standing back up otherwise. No
headroom/ceiling check on standing up — every generated room is a simple
open box, nothing low enough to clip into yet.

**Dash** (2026-08-30, user request, exact wording: "Tapping shift and a
direction should allow players to dash in a direction"): reuses the
`sprint` action (already bound to Shift) instead of a new binding -
`just_pressed` fires once on the initial keydown regardless of how long
the key stays down afterward, so a tap dashes and continuing to hold
still sprints normally on top of it. A fixed-impulse burst that decays,
same shape as Slide above, on a 1s cooldown; works in the air and while
stationary alike (Slide requires sprinting + a floor). **Movement speed
is also reduced while melee attacking** (user request, exact wording) -
0.5x for the whole Windup-through-Recovery window of a swing, not just
the instant Strike - and while channeling Flame Jets (0.4x, see Abilities
below) - both read through `Player._effective_speed()` the same way
Instinct/status-effect speed modifiers already do.

**Combat formula** (`systems/combat/DamageCalculator.gd`, v4.8):
- **Weapons:** `base x (1 + Str%) x Motion Value x (1 + sum Increased%)
  x product(More)`. `scaling_grade` has no effect on weapon damage; it's
  shown in Alt info and can be degraded by the Shard of Tharsis.
- **Spells (v4.14):** `the spell's own base damage at its level x
  (1 + sum Increased%) x product(More)`. Each spell has a unique level-1
  range (`Ability.base_damage_min/max`) that grows 7% per level (compounding),
  compounding. Increased% takes Intellect (1%/pt), the Chain Bonus,
  increased Spell damage, the equipped Conduit's local Spell damage, and
  whatever the spell's tags let in (e.g. increased Area damage for Area
  spells). Conduits no longer carry flat spell power; spells work with no
  Conduit at all.

`calculate()` computes `power = base + stat_value x grade_multiplier`;
both weapons and spells now pass their base with `stat_value = 0.0`, so
`scaling_grade` (and an ability's legacy `motion_value`) no longer
affects damage. Increased% is one additive pool (the Chain
Bonus feeds it per damage tag); More multipliers stack. Followed by a
**Critical Strike System** (also Section 11, doc-exact numbers): base crit
chance is fixed per weapon/spell type (`Constants.WEAPON_BASE_CRIT_CHANCE`,
2%-8%), multiplied by (1 + Agility% + gear increased crit); a crit deals
150% damage plus gear crit damage. `Weapon`/`Ability` each expose `predict_damage()` (an
expected-value blend for stat-card display, doesn't jitter between hover
peeks) and `roll_damage()` (an actual random crit roll, used by real
attacks/casts). Order of operations (Patch v3.2, superseding the Master
doc's Ward-bracket design): Armor mitigates Physical damage (`Armor /
(Armor + 6 x Hit Damage)`, Section 16), Resistance mitigates Elemental/
Esoteric damage (`fire_resistance_pct`/`cold_resistance_pct`/
`lightning_resistance_pct`/`esoteric_resistance_pct` gear affixes, the
last unifying Aetheric/Entropic/Pale per the patch) - then Ward absorbs
whatever's left **regardless of damage type** (the old Esoteric-only
restriction is gone) before the remainder hits Health.

**Ward** (`entities/components/WardComponent.gd`, Patch v3.2): a pure
buffer with no mitigation of its own, now with real regen - a 2s delay
after any hit (reset by every subsequent hit), then 4% of max Ward/second
passive, +5% on every kill, +15% on a successful Parry (that ratio
predates the patch, still invented - see flagged gap). Every restoration
source scales by the same Enigma-driven `restoration_multiplier` (+1%
per point, "Ward Restoration is a unified stat"). **Pool size comes from
armor only** - each equipped Armor/Shield's own base `ward_value` plus any
rolled `flat_ward` affixes (`EquipmentComponent.compute_ward_bonus()`,
renamed 2026-08-30 from `compute_flat_ward_bonus()` after a user bug
report - it only ever summed the affix, never the base `ward_value` field
Section 25's generator populates on ~170 armor pieces, so equipping one
silently granted zero Ward despite a real, prominent tooltip line saying
otherwise; see flagged gap for the rest of that pass), no baseline pool at all -
Enigma applies as an INCREASED% multiplier on top of that base (2%/point,
invented rate - no doc-exact number exists for this specific multiplier),
not its own flat contribution, so zero Ward-granting gear means zero
Ward regardless of Enigma investment. (An earlier pass gave every
character a flat base + a flat per-Enigma-point bonus, so a fresh,
completely ungeared character started with 900 Ward out of nowhere -
user-caught, fixed.) **Resistance Shred** (patch
addition: reduces a target's Resistance for 8s, diminishing-returns
stacking - highest source full value, every other at half its own value)
is implemented as a real, tested mechanic
(`StatusEffectComponent.apply_resistance_shred()`) with no current
applier - the patch introduces it via a Throwable-focused Unique this
project can't build yet (no Throwable weapon category exists).

**Enemies** (`entities/enemies/`, `data/enemies/`): the Enemy Roster v1
from *Project Aether — Enemy Roster & Factions* (`documents/`), plus the
v4.14 additions below. Regular units are each an `EnemyDefinition` (`data/enemies/definitions/`) on
one of two generic scenes: `units/MeleeUnit.tscn` (`EnemyMeleeAttack`) or
`units/RangedUnit.tscn` (`EnemyRangedAttack`, picked by
`EnemyDefinition.is_ranged`). `EnemyRoster.create_unit(id)` builds one.
Health and damage come from `archetype_category` + `mob_level` through
`Constants.MOB_BASE_*`; every other number is a playtest placeholder.

| Unit | Faction | Category / level | Damage | Attack |
|---|---|---|---|---|
| Unchartered Cutthroat | unchartered | light 1 | Kinetic | melee |
| Unchartered Javelineer | unchartered | light 1 | Piercing | ranged (kites) |
| Unchartered Brigand | unchartered | standard 1 | Piercing | melee |
| Unchartered Enforcer | unchartered | heavy 2 | Kinetic | melee |
| Unchartered Chieftain | unchartered | elite 3 | Kinetic | melee |
| Directorate Adjudicator | directorate | elite 3 | Kinetic | melee, 15% Ward |
| Synod Vindicator | synod | elite 4 | Aetheric | melee, 25% Ward |
| Synod Exarch | synod | elite 4 | Cold | ranged (kites), 30% Ward |
| Legion Threshold Knight | karvis_legion | elite 5 | Pale | melee, 20% Ward |
| Hollowed Shambler (Zombie Footman model) | hollowed | standard 1 | Kinetic | melee, packs of 3-5 |
| Legion Dreadknight (Nathrezim) | karvis_legion | elite 5 | Entropic | melee, 15% Ward |
| Synod Warden / Ember / Aether Golem (Arcane Golems) | synod | heavy 3 | Kinetic / Fire / Aetheric | melee, armored, Ward |
| Veilborne Mindbender | veilborne | standard 2 | Entropic | ranged (kites) |
| Veilborne Cantor (Priestess of the Damned) | veilborne | elite 4 | Pale | ranged (kites), 25% Ward |

Xalatath (`entities/enemies/xalatath/`) is a second Pinnacle boss:
melee up close, Entropic bolts beyond 5 m (`EnemyRangedAttack.min_range`).
`PinnacleArena` picks one of its bosses at random.

Only basic attacks exist: no pack roles, synergies, status riders, blocks,
spells or channels yet. `GeneratedMap` spawns packs from
`Constants.ENEMY_PACKS_NORMAL` (Unchartered, Hollowed, Synod golem and
Veilborne packs); the boss room holds only its FigmentBoss. The Vindicator,
Dreadknight and Cantor spawn as Ascendants (Enemy Rarity, below). `TestArena` has one
of each unit in a row. `directorate_soldier.tres` has no model and isn't
spawned.

**Attack lock**: an enemy is rooted from the start of its attack wind-up
until its attack animation finishes (`Enemy.is_attack_locked()`).
**Animation speed**: walk/run playback is scaled to actual ground speed
over the clip's authored speed (MDX sequence MoveSpeed, carried into
`MdxModel.clip_move_speeds` by the wrapper builder, or
`AnimationSet.walk_clip_speed` when the MDX has none), so feet don't slide.
**Kill box** (`autoloads/KillBox.gd`, every scene): an enemy that falls
below y = -25 dies (normal rewards); the player is put back on the last
ground they stood on and loses 15% of max Life.
**Mob balance (v4.14)**: `Constants.MOB_BASE_HEALTH` light 30 / standard
55 / heavy 110 / elite 280 / boss 1600 (a level-1 standard mob is ~4 hits
from the starter Crude Greatsword); `MOB_BASE_DAMAGE` 5/9/15/24/45. The
FigmentBoss has 700 Life and hits for 40 at level 1, scaled by Area Level.

All units chase the player (`chase_range`/`stop_distance`/
`retreat_distance`), no pathfinding, and are gap-aware:
`_check_gap_jump()` raycasts the gap ahead and only jumps
(`jump_velocity` 7.0) if the unit's speed can clear it.

**Attack telegraphs are the animation itself** - no color flash. When a
wind-up starts, `EnemyAnimationController.play_attack()` time-stretches the
attack clip (`AnimationNodeAnimation` custom timeline) so its hit frame
(`AnimationSet.attack_hit_fraction`, 0.45 default, 0.4 for the
Javelineer/Brigand) lands exactly when the strike resolves or the shot
fires - a longer wind-up reads as a slower, bigger swing. Playback speed is
clamped to 0.4x-2x. A red flashing
sphere above the head means its `ComposureComponent` is broken
(Riposte-able).

**Enemy models** (`entities/enemies/models/`): Warcraft III stand-ins
converted by `tools/mdx_pipeline/` (see its README). Each unit has a wrapper
scene (`<Unit>Model.tscn`: the `.glb` + a `HumanoidAnimTree`, rooted on
`MdxModel.gd`) generated by `tools/build_mdx_wrappers.tscn`, which builds
`ORMMaterial3D`/`StandardMaterial3D` per geoset from the model's `.dds`
files. `MdxModel` also shows/hides geosets per playing clip (WC3 hides
corpse and alternate parts through geoset alpha). Clips map through one
`AnimationSet` per unit (`data/enemies/animation_sets/`); idle/walk loop
and one-shots don't (`EnemyAnimationController._apply_loop_modes()`). A
unit with no hit-reaction clip doesn't flinch. `EnemyDefinition.
model_yaw_offset` turns each model's front (+X for every converted model)
to +Z. Base-game textures a model references but doesn't ship are
extracted from the local Warcraft III Reforged install by the pipeline
(`models.json`'s `wc3_install`), so every geoset of all ten models is
textured.

**Abilities** (`systems/abilities/`, `data/abilities/`): 18 hand-authored
spells (17 + Flame Wall, invented, see below). 9 predate this README's
own doc-checking convention (Ice Pulse, Comet, Winter's Eye, Frost Armor
- real Section 26 names - alongside Cinder Lance, Inferno, Static
Discharge, Stormcall, Entropic Decay, invented, never in the doc - user
direction: keep both sets, don't retire the invented five). The other 8
are transcribed from Section 26, "Ability Staging Ground" (a real doc
section a prior PDF-based pass never found): Flame Jets, Meteor (Fire),
Thunder Javelin, Thunder Sweep (Lightning), Black Hole (Entropic),
Caltrops (Physical), Blink and Purge (Utility). Cast on `1`-`4`
(`PlayerAbilityCast`), drawing from a Mana pool (`ManaComponent`).

**Cast types** (Patch v3.7, `Ability.cast_type`): INSTANT (everything by
default), CAST_TIME (Comet 1.2s/Winter's Eye 0.8s/Meteor 1.6s/Black Hole
1.0s - a real, interruptible windup via `entities/player/
CastTimeHandler.gd`; only a stun (Freeze/Electrocute) cancels it - plain
damage doesn't - and nothing is refunded), or
CHANNELED (Flame Jets - already its own bespoke channel loop in
`PlayerAbilityCast.gd`, untouched; the CastType exists for future use but
currently behaves exactly like INSTANT, channeled cast-speed interaction
is explicitly deferred). Cast Speed (`StatSheet.cast_speed_bonus`) speeds
up a CAST_TIME windup; Cooldown Recovery Rate (`cooldown_recovery_rate`)
speeds up cooldowns - deliberately separate pools, Cast Speed never
touches cooldowns or weapon attack speed, only a Slate mod (stub, no real
instance yet) can convert some Cast Speed into Cooldown Recovery.

**Most abilities still execute as a self-centered damage nova** sized by
`radius`, on press. **A growing set of exceptions now have their own real
mechanic** (2026-08-30 pass, per the user's own description of each -
see `PATCH_NOTES.md` for the full writeup of what changed and why):
- **Black Hole** pulls enemies toward its center for 2.5s (real physics,
  not visual) AND ticks real Entropic damage every 0.25s to anything in
  the pull radius - no instant hit at cast anymore.
- **Caltrops** ticks Piercing damage every 0.5s to anything standing in
  its field AND applies a new generic `"slow"` status effect
  (`StatusEffectComponent.gd`, independent of Cold's own Chill).
- **Cinder Lance** and **Thunder Javelin** fire a real traveling,
  PIERCING bolt (`PiercingBolt`, new shared effect - unlike the ranged-
  weapon `Projectile.gd`, doesn't stop at its first hit) aimed at the
  camera's crosshair.
- **Flame Jets** is a real hold-to-channel (not ground-targeted): re-aims
  at wherever the camera is CURRENTLY looking every tick, slows the
  player to 0.4x movement speed, and drains 8% of its Mana cost every
  0.15s while held on top of its upfront cost - cuts off immediately (no
  grace tick) the instant the key releases or Mana hits 0. Not
  interruptible by taking damage (`CastTimeHandler` fires CHANNELED
  abilities immediately, with no windup to interrupt).
- **Winter's Eye** launches a fast orb toward the target point that ticks
  proximity Cold damage + Chill to the nearest 3 enemies within range as
  it travels (an approximation of "a spiral of icicles" - ticks, not
  literal spawned sub-projectiles, spinning cosmetically as it goes),
  then detonates for a burst hit on arrival or after 3s, whichever comes
  first.
- **Thunder Sweep** fires 8 `PiercingBolt`s radiating outward in a full
  circle from the player, flattened to the ground plane.
- **Flame Wall** (new, invented - no Section 26 entry exists for it):
  ground-targeted, spawns a wall oriented perpendicular to the caster-
  >target line; Ignites enemies on entry, ticks damage to anything
  standing inside.
- **Frost Armor** is a pure self-buff at cast (no AoE hit) - for 8s,
  every enemy melee strike that lands on the player triggers a real Cold
  retaliation burst + Chill back at the attacker
  (`EnemyMeleeAttack._resolve_hit()` -> `PlayerAbilityCast.
  trigger_frost_armor_retaliation()`), matching the doc's own wording
  exactly. Previously had no retaliation mechanic at all.
- **Blink and Purge deal no damage at all** ("No attack component" per
  the doc for both) - Blink raycasts the player forward up to 8m
  (stopping short of a wall), Purge clears every debuff currently on the
  player; Purge's other half (stripping buffs from surrounding enemies)
  isn't built - no enemy-buff system exists in this project to strip
  anything from.

Every other ability (Comet, Inferno, Stormcall, Meteor, Ice Pulse, Static
Discharge, Entropic Decay, Winter's Eye's own detonation, Flame Jets'
`applies_status_effects`, etc.) still uses the generic instant-nova path,
several with a bespoke cast VFX instead of the generic expanding ring
(`CometImpact`/`InfernoPillar`/`StormcallBolt`).

**Spell levels (v4.14)**: spells go from level 1 to 20, raised on the
Abilities screen (`N`) for Gold plus **Crystallized Aether** (a currency
that drops on its own 18% roll per kill, 1-3 + rank/tier bonus). Aether
cost is 2 at level 1 and curves up to 120 for 19 -> 20
(`Ability.get_upgrade_aether_cost()`). Gear's "+N to level of (Fire/...)
Spells" adds levels on top and can go past 20; each level over 20 grants
3% more damage and 1% reduced cooldown, plus 2% Area (Area tag), 3%
Duration (Duration tag), 3% Projectile Speed (Projectile tag) and +1 Limit
per 4 levels (Limit tag). **Tags** (`Ability.tags`: Area of Effect,
Projectile, Duration, Limit, Channelling, Movement, Utility, plus Spell and
the damage type) decide which modifiers apply: increased Area damage /
AoE radius, Skill Effect Duration, Projectile Speed, Mana cost reduction
and Cooldown Recovery all read them. **Limits** (Tornado 3, Black Hole 1,
Flame Wall 2, Caltrops 3): casting past the limit removes the oldest
instance. **Cooldowns (v4.32)**: only Blink and Purge keep one; every other
spell is limited by Mana plus a short shared cast recovery
(`Ability.base_recovery_time`, 0.3s, scaled by cast speed). Flame Jets
channels for as long as the key is held and Mana lasts. Slate auto-cast
fires at most every 2s. **Status chance**: each spell rolls
`Ability.status_chance` per hit for each of its statuses, plus the
caster's "+% chance to cause X" gear (`StatusEffectComponent.try_apply()`);
weapon hits roll gear chance alone (`roll_gear_ailments()`). Gear chance only
works through hits of the matching damage (`AILMENT_DAMAGE_TYPES`: Ignite
Fire, Chill Cold, Shock/Electrocute Lightning, Unraveling Entropic,
Aetherburn Aetheric, Pallid Pale, Bleed any physical). Stance riders
that aren't ailments (Armor Shred, Suppressed, Slow, Entangle) always land.
`ui/ability_bar/` shows equipped abilities
with a cooldown wipe and Mana cost; `ui/abilities/AbilitiesScreen.gd` is
the equip/upgrade menu.
**The player starts with zero abilities** — per Patch v3.1's Skill
System replacement, every ability has to be unlocked via a `SkillTome`
drop (see Loot generation below) before it shows up in the Abilities
screen at all. The Hub's SpellTestShop unlocks every ability for free,
for testing without grinding drops. **Not built from Section 26**:
Purity From Within (a Fire self-damage-drain aura that also buffs other
spells - needs a persistent toggle/channel ability archetype beyond what
Flame Jets' own timed channel covers), Blinkstrike (teleport-to-enemy + a
strike scaled by the equipped melee weapon rather than the Ability's own
scaling - breaks the generic damage model every other ability shares),
and Conduit/Prowess (both explicitly "(Passive)" in the doc - no passive-
node system exists outside gear/Slates/Stats).

**Status Effects** (`entities/components/StatusEffectComponent.gd`,
Section 09): bidirectional — a copy lives on both Player and Enemy, so any
future enemy-side applier works with zero new plumbing. Covers Ignite
(Fire DoT, ticks over 4s), Chill (Cold, -30% move/action speed, 3
applications escalate to Freeze), Freeze (full immobilization), Electrocute
(Lightning stun/stagger), and Unraveling (Entropic, +25% Esoteric damage
taken) — the 5 effects with a real applier today, via each spell's
`applies_status_effects` (see Abilities above). **A 6th, `"slow"`, was
added 2026-08-30** for Caltrops specifically (-35% move/action speed,
stacks multiplicatively with Chill if somehow both are active) - not
doc-named, invented because reusing Chill for a Physical/Piercing effect
would have been a thematic mismatch (Chill is explicitly Cold-flavored
per `Constants.STATUS_EFFECT_DAMAGE_TYPE`). **A 7th, `"shock"`, was added
2026-09-06** for Spark specifically (Lightning, +20% Lightning damage
taken for 4s, non-stacking/refresh-on-reapply, no stun) - Spark applies
Shock instead of Electrocute now; Thunder Javelin/Thunder Sweep still
apply Electrocute, unchanged. Resilience (gear-affix-only, `flat_
resilience`) reduces Ignite's tick damage; Debuff effectiveness has a
hook (`StatusEffectComponent._debuff_effectiveness_multiplier()`) but is
a flat 1.0 since no stat drives it anymore. Stunned
targets have their `EnemyMeleeAttack`/`EnemyRangedAttack` state machine
paused (Enemy side) or lose jump/parry/attack input (Player side). Active
effects show as a colored chip row top-left on `PlayerHUD` and as small
floating dots above an Enemy's head. **Scorch** (v4.21): +6% Fire damage
taken per stack, max 5, 4s - from Flame Jets, Flame Wall and Cinder Lance.
Bleed/Armor Shred/Stagger-Stun and Aetherburn/Pallid aren't modeled yet — see gaps below.

**Equipment & Items** (`data/items/`, `data/armor/`, `data/shields/`,
`data/weapons/`, `systems/equipment/EquipmentComponent.gd`): Section 13
equip slots (Helmet/Body Armour/Gloves/Boots/Primary Weapon/Offhand/
Amulet/Belt/2 Rings), two-handed-weapon-clears-offhand rule enforced.
`Weapon.is_ranged` decouples melee/ranged attack dispatch from equip slot,
so a pistol (or any ranged weapon) equips to `PRIMARY_WEAPON` like a
two-hander and naturally replaces one. Patch v3.5 (2026-09-01) cut
Sidearm/Conduit/Secondary as their own slots - any weapon now routes into
Primary or Offhand via `Weapon.is_main_hand`/`is_offhand` instead
(`EquipmentComponent.equip()`), and rings dropped from 4 to 2. Throwables
are no longer equipment at all - see the Throwable Stack entry below.
`ui/inventory/InventoryScreen.gd` (`B`) is a 3-column layout: a live
stats column (left), a slot-grid inventory (center, excluding anything
currently equipped), and a paper-doll equipment diagram laid out like
Path of Exile's (`InventoryScreen._layout_doll()`: every slot is its item
footprint in inventory cells, weapons 2x4 flanking the body column). Every
Item, Slate and currency id draws as a code-drawn vector icon
(`ui/icons/IconArt.gd`, shown by the `ItemIcon` Control in the grid,
`ItemSlotButton`, and the HUD weapon plate), fitted at its footprint aspect.
New item types or currency ids need an arm in `IconArt._draw_key()`;
unknown ones fall back to a gold orb with their first letter.
Abilities route to `ui/icons/SpellArt.gd` (one function per ability_id, used by
the HUD AbilityBar, the Abilities screen and Skill Tome covers); a new spell
needs an arm there or it shows its damage type's glyph.

**Throwable Stacks** (`data/items/ThrowableStack.gd`, Patch v3.5 Section
3): a stackable inventory consumable, not an equipment slot - `Player.
active_throwable` holds the currently selected stack, `use_throwable()`
(bound to middle-mouse, the new `throw_secondary` action) consumes one
and fires `EventBus.throwable_used`. `PlayerHUD` shows an icon + count in
the top-right corner, "0" shown plainly rather than hidden when empty.
How a stack gets acquired/selected is out of scope for this pass (no
crafting/acquisition system invented, per the brief) - starts null.

**Inventory**: see "Crafting, inventory, stash & portals" below.

**Stat cards** (`ui/item_card/`): hovering any item, Slate, or ability
anywhere in the UI shows a rich PoE-style card (stats, affixes, flavor
text, rarity-colored border) via `ItemCard.gd` + `ItemSlotButton.gd`
(wired through Godot's `_make_custom_tooltip()` hook, `0.03s` delay - was
`0.15s`, dropped further for a near-instant feel per user request).
**Item/Slate/Ability cards each have a distinct silhouette** now, not
just a rarity-colored border - a Rare Item and a Rare Slate used to look
identical at a glance (same rarity-color palette collision, user-caught).
Each type layers 3 independent cues: a colored type badge ("ITEM"/
"SLATE"/"SPELL", the first thing drawn), a corner-radius/border-width
"shape" (Item sharp, Slate rounded + thicker border, Ability roundest of
the three), and a faint background tint. Ability cards are also now
colored by the ability's own damage type instead of one flat blue for
every spell regardless of element - a spell's card is now recognizable
both as "a spell" AND as "which element" on sight.

Holding **Alt** while a card is showing swaps its content to **Alt
Info** in place (Patch v3.8, `ItemCard.gd`'s own `_input()`) - Scaling
Grade, Primary/Secondary Scaling, Item Level, and stat requirement for a
weapon; Scaling Grade and Motion Value for an ability. Release Alt and it
swaps back to the normal card, same native tooltip window the whole time
- no second popup, no click-to-pin, no clickable glossary links or full
tier ranges anymore. Replaces the previous `AdvancedTooltip.gd` autoload
(a real second `CanvasLayer` with its own floating card, deleted
entirely) - that version's own "release Alt closes it, unless the mouse
is over the card" hold behavior is gone along with it; Alt Info has
nothing to hover onto since it's the same card, not a second window.

**Damage is a per-hit range.** Every weapon hit rolls its base damage
uniformly within `base_damage_min`..`base_damage_max`, and every spell
cast rolls the spell's own base damage range at its level
(`Weapon`/`Ability.roll_damage()`); stats, motion value, chain bonus and
crit apply on top. The old single per-drop roll (`rolled_base_damage`)
is unused.
Weapon cards show one "X Damage: min to max" per damage type present -
the item's own range, in white, or in blue with the item's local increased
Weapon Damage applied (`ItemCard._build_attack_power_lines()`). The
character's Strength is not on the card; the character screen's Main
Hand Damage includes it. Crit Chance/Spell Damage/Attack Speed/Cast Speed
follow the same rule - one value, blue when a **local mod** changes it
(v4.10, `local_*` stat keys in `data/affixes/weapons/generic|conduit/`:
local Weapon Damage and Crit apply to that weapon's own hits via
`Weapon._base_hit()`, local Attack Speed to that weapon's attacks, and a
primary Conduit's local Spell Damage and Cast Speed to every spell). Spell
cards show "Level N", the tag line, the spell's base damage (blue with
modifiers applied), and any over-cap bonuses; the
character screen's Main Hand/Offhand Damage shows the per-hit range at
that weapon's motion value.
Scaling Grade moved to Alt Info; the old socket-count text line was
replaced with real socket art (small filled/outline circles, `ItemCard.
SocketRow`) - `Item.sockets` (Patch v3.8, how many of an item type's
`max_sockets` a specific rolled instance actually has, rolled 0..
max_sockets on drop) is genuinely new, `max_sockets` itself (the type's
overall cap, raised by Bore/Corruption) is unchanged. **Ability cards**
drop Motion Value and Predicted Damage entirely (never meant to be
player-facing) and gain a Cast Type line (Patch v3.7's `Ability.
cast_type` - "Instant"/"X.Xs Cast"/"Channeled").

**Fate Board** (`systems/fate_board/`, `ui/fate_board_editor/`, Section
10): grid Slate placement gated by an Aether budget, flood-fill chain
detection with tiered bonuses (`Constants.CHAIN_BONUS_TIERS`, doc-exact).
UI is a 150x150 grid inside a `ScrollContainer` (2026-09-01, up from a
bounded 32x32 window - much closer to the doc's "effectively unlimited"
board, though still technically bounded), opens with `P`. Hold LMB and
drag to pan around the board; a plain click (no drag) still places or
removes a Slate. RMB drops the currently held Slate if one is pending,
or removes whatever's at the clicked cell otherwise. Two cells that
belong to the same placed Slate render with no line between them (one
solid shape); a line is still drawn between different Slates, or against
empty space. The palette shows the hand-authored `data/slates/instances/`
samples (11 now - see below) as an always-available catalog, plus every
real `SlateRoller` drop in `GameState.owned_slates` - those are finite:
placing one removes it from the palette until it's pulled back off the
board.

**Layout now persists** (2026-08-30, user-reported: "Slates do not
persist between scenes, they need to stay on the character") - Player is
a fresh instance every Hub<->Map reload, and `FateBoard` used to be
recreated empty every single time (`Player._ready()` unconditionally did
`FateBoard.new()` with nothing to restore it from - the Fate Board's own
`aether_used`/`placements` state was live-only, never synced anywhere).
`FateBoard.place_slate()`/`remove_slate()` now call `GameState.
sync_fate_board()` on every change, persisted the same way equipment/
ability loadout already are (`GameState.fate_board_placements`,
`SaveManager` save/load) and restored by a new `Player._apply_saved_
fate_board()` alongside the existing loadout restore. This supersedes the
older "only ownership persists, not layout" design note that used to be
in `SaveManager.gd`.

**Slates must now connect** (2026-08-30, user direction: "Slates should
have to connect with each other, not be placed freely") - every placement
must be orthogonally adjacent to (or overlap) either an already-placed
Slate or `FateBoard.ANCHOR_CELL`, a fixed cell at the board's center that
always counts as "already placed" so an empty board still has one legal
starting point. Only enforced at placement time, not re-checked on
removal - removing a Slate that leaves others "orphaned" from the anchor
is allowed (an invented simplification; the doc doesn't specify either
way). `FateBoardEditor`'s status line now explains *why* a placement
failed (insufficient Aether / cell occupied / not connected) instead of
printing the raw internal reason string.

**Slates now have an animated background** (2026-08-30, user reference
image: moving color-shifting nebula texture per Slate type) - a canvas
shader (`ui/fate_board_editor/slate_nebula.gdshader`) renders a drifting,
per-cell-phase-offset noise field tinted by `Constants.DAMAGE_TYPE_COLOR`
with sparse twinkling stars, sampling a small `cell_data` texture
`FateBoardGrid.gd` rebuilds only when placements actually change (not on
every hover-driven redraw). This was the first deliberate exception to
this project's earlier no-shader placeholder-art convention - motion is
the actual content being asked for here, not just a static color, and a
CPU `_draw()` loop redrawing hand-rolled noise across every occupied cell
every frame would be both slower and far more code than the GPU doing the
same thing. `StatOrb.gd`'s Life/Mana/Ward orbs joined it 2026-08-30 (user
request: "make a shader for the Life orb, Mana orb, and Ward shield... to
make them look interesting") - a single `canvas_item` `ShaderMaterial` on
a `ColorRect` sized to exactly the circle's own diameter (so `UV` maps
cleanly onto it) replaced the old `_draw()`-based liquid fill entirely,
adding an animated wavy waterline, a liquid depth gradient, a surface-
glow highlight, and a soft fresnel rim glow that a flat
`draw_colored_polygon()` fill couldn't produce. The "no-shader" framing
is now more historical than descriptive - not a hard rule any more, just
what most of the UI still happens to look like.

**Spell-designated Slates** (Section 10's Unique "The Unbound Chorus":
"Designate one Spell skill - that skill automatically triggers when its
cooldown expires") - `Slate.requires_spell_designation` marks a Slate as
needing one of the player's owned Abilities bound to it before it can be
placed; `FateBoardEditor` shows a picker (any owned Ability, not just
what's in the 4-slot hotbar - the whole point of a Slate-granted cast is
it doesn't cost a hotbar slot) and the choice is stored on
`FateBoard.PlacedSlateData.designated_ability_id`, persisted the same way
the rest of the layout is. `PlayerAbilityCast._process_slate_autocasts()`
fires the designated ability automatically once its cooldown (tracked in
the same `_cooldowns` dict a real press would use) reaches 0, at the
doc's own reduced 60% damage, no resource cost, no Riposte/Composure
interaction - all three straight off The Unbound Chorus's own modifier
list (`unbound_chorus.tres`), not generic behavior. This is scoped to
exactly that one doc-sourced mechanic; other interaction types a Slate
could have with a designated spell (buff it, retrigger it on some other
condition, modify it) would need their own concrete Slate designs to
build against, same as this one did - none exist in the doc yet.

**Slates now do something** - two mechanical pathways out of the Fate
Board, both landing on `StatSheet`:
1. **Stat contribution** (Section 10's "Stats Per Tile": 0.3 Main
   Stat/tile keyed by the Slate's tag via `Constants.
   DAMAGE_TYPE_MAIN_STAT`, 0.15 Random Stat/tile, 5+ tile Slates only -
   v4.9 cut these from 1.7/0.8 to 0.6/0.3, v4.53 halved them again so
   chains carry more of a board's attributes) sums across every PLACED Slate into
   `StatSheet.slate_bonus`, same channel gear's `flat_<stat>` affixes
   use. Since v4.9 each Slate's stat lines are multiplied by (1 + the
   bonus of the chain it sits in) (`ChainCalculator.
   slate_stat_bonuses()`); non-stat modifiers are never amplified. A
   lone Slate counts as its own chain (its own tile count).
2. **Chain Bonus** (`ChainCalculator.bonus_by_tag()`) feeds `Weapon`/
   `Ability._base_hit()`'s `increased_percents` as real "increased
   damage" for that tag's category.

Mastery (a third pathway, amplifying scaling grade and chain bonus) was
removed in v4.8. Section 10 itself leaves chain amplification of stat
rolls "deferred pending balance evaluation"; v4.9 implements it as a
design decision. **`SlateRoller`** (mirrors `ItemRoller`)
rolls all five of Section 10's axes - Tag, Shape (from a small invented
template pool, freely rotated/flipped at placement), Size (the doc's own
2-4/5-9/10-11 tile brackets, each with its own rarity band and design
identity), Modifier Count, and Modifier Values (the stat formula above is
deterministic per tile count, not randomized) - and drops as loot (10%
chance per kill, same flat-independent-roll convention as Tomes/Brands).

**The Hub is a Memory Nexus** (`levels/hub/MemoryNexus.gd`, built in code
at load, modelled on Path of Exile's Synthesis hub): marble platforms in
a black void. The walkable area is one signed-distance shape (`CIRCLES`
+ `BRIDGES`) shared by the collision and `shaders/nexus_floor.gdshader`:
two-tone Dalaran marble parquet with gold inlay rings inside, breaking
into Voronoi flakes with glowing blue borders toward the edge. Centre:
the Circle of Power waypoint (spawn). North: a stepped dais (one smooth
convex collider under the visible steps) with the Reality Engine on a
broken column, under a floating, turning crystal formation and rune
ring. West/east "stabiliser" platforms with rotating rune circles
(`nexus_runes.gdshader`) and colonnades hold the vendors and stash,
dressed with WC3 models (Arcane Vault, crates, Magic Vault with a
floating tome, treasure chest). South: the Waygate, where the return
portal opens. The void has glowing-crack platform undersides
(`nexus_crust.gdshader`), drifting islands and Dalaran spires, light
shafts, rising motes and flakes peeling off the edges, over a faint
far-below web (`nexus_void_sea.gdshader`). Falling off just returns you
to the last solid ground (no penalty in the Hub). Props are the "nexus"
kit in `tools/mdx_pipeline/doodads.json`.

**Hub, Figments, and the Reality Engine** (`levels/hub/`,
`entities/interactables/reality_engine/`, `data/figments/`): `MainMenu.tscn`
(project's main scene) leads to `Hub.tscn`, a non-combat room. This whole
system is entirely invented - no doc content covers it at all (Section
24 lists "Endgame content loop" as explicitly not designed either).
Walk up to the Reality Engine (renamed from "Map Device" per user
request) and press `E` to choose a **Figment** (renamed from "Map" -
`FigmentItem`, `data/figments/`, tier-scaled enemy-damage/enemy-health/
loot-quantity/loot-rarity affixes) and enter the procedurally generated
Map it configures. The selection screen (reuses `ShopScreen`, the same
generic list UI GearShop/SpellTestShop already share) lists every owned
Figment plus an always-available free Tier 1 offer, so there's never a
hard floor on playing even before any Figment has dropped. **Figments are
now droppable** (`Enemy.gd`, 6% chance/kill, scaled near the killing
Map's own tier via `FigmentRoller.roll_for_drop()`) and **craftable** -
right-clicking one in the Inventory empowers it
(Gold-gated, `CraftingSystem.empower_figment()`) that raises its tier and
strengthens its rolls, making it harder on purpose. Tiers, mods and the tree are described below. Leaving a Map is
manual (Pause menu's "Return to Hub," or death).

**Figments have a boss, and killing it "completes" the Figment.**
`FigmentBoss` (`entities/enemies/figment_boss/`, shown as "Figment
Chieftain") is an invented first pass (Section 24 flags boss design as
undesigned): 1760 health, 61.6-damage melee hits, 250 XP and 120 Gold, on
the Unchartered Chieftain's model at 1.5x scale. One spawns on every
Vault's platform. Its death fires `EventBus.figment_completed`, which
feeds Figment Tree points (see below).

**Lord of the Elements** (`entities/enemies/lord_of_the_elements/`): the
first Pinnacle boss, spawned at `PinnacleArena`'s `BossSpawnPoint` with
`rank = BOSS`. Each attack takes the next element in a Fire -> Cold ->
Lightning cycle. The active element's orb (`ElementOrb`) can be overloaded,
dropping that element for 20 s; his spells react with each other
(`ElementReactions`: steam, chained lightning, shattered ice); Cataclysm is
survivable only in the sigil two casts ahead; in phase 3 he lands and fights
with parryable per-element combos. The Herald (`Xalatath`, `MawArena`) and
Ataras (`SandArena`) are described in PATCH_NOTES v4.48, v4.69 and v4.70.

**Area Level** (`systems/figment_tree/AreaLevel.gd`, v4.75, user design):
the one number a Figment's monsters, drops and XP follow; player level
never feeds monster stats (it gates equipping and the XP gap). Depths 1-23
(Fragmented Reality's levelling stage) are Area Level 1-67, Tier N is
68 + N (69-89), Pinnacles are 90. Monster level = Area Level for every unit
(flattened); health and damage compound per level (`HEALTH_GROWTH` 1.037,
`DAMAGE_GROWTH` 1.021, tuned with `tests/balance/probe_power_curve`), with
Figment mods, rarity and boss mods on top. Drops use Area Level + rank
bonus as item level. XP: credited at the player's level times
`xp_multiplier()` (zone 7 + 10% of level: below tapers to 0, above up to
+20%). The levelling stage: `FigmentItem.depth`, `FigmentRoller.roll_depth()`,
`FigmentProgress.levelling_complete()`/`max_drop_depth()`,
`GameState.depth_cleared`; the Reality Engine's free run is the next Depth
until Depth 23 is cleared, then Tier 1. The Campaign skips the stage.

**Enemy Rarity** (`entities/components/EnemyRarityComponent.gd`,
`data/enemies/EnemyAffix.gd`, `data/enemies/affixes/`; Patch v3.9 plus user
direction 2026-10-09): a tier axis separate from `Constants.EnemyRank`
above (Rank still only drives drop item level). Rolled **per pack** in
`GeneratedMap._spawn_pack()` (`Constants.ENEMY_PACK_RARITY_WEIGHTS`
70/20/8/2); bosses and summons are Normal.
  - **Normal**: no modifiers.
  - **Elite** (blue): the whole pack is Elite and shares one pack affix that
    every member carries: Driven, Swift, Ironclad, Frenzied (survivors
    enrage when a packmate dies), Volatile (explodes after a ground warning
    when it dies), Frostbitten / Searing (hits Chill / Ignite), Bloodthirsty
    (leech and regeneration). ×1.5 Life, ×1.2 damage.
  - **Champion** (yellow): one leader of an otherwise Normal pack, with one
    real aura (Warlord's Presence, Haste, Fortitude, Renewal) that applies its
    stat lines to every enemy within 10 m, the Champion included and whether
    or not they spawned with it (a ring on the ground marks the reach), plus a
    50% chance of a second Champion affix (Dreamer, Bulwark or another aura).
    ×3 Life, ×1.6 damage.
  - **Ascendant** (orange): a Synod Vindicator, Legion Dreadknight or
    Veilborne Cantor (`ASCENDANT_UNITS`) with up to two Normal escorts and
    two affixes from its own pool: Unyielding, Juggernaut (ignores slows,
    stuns, staggers, knockback), Arcane Shell (Ward that refills), Empowered,
    Soul Eater (stronger as enemies die nearby), Blink Strike (teleports
    beside you), Frost Nova (telegraphed Chilling nova), Archon (spawns as two
    that split its Life, each dealing 65% of its damage). ×3 Life and ×1.5
    damage on top of an elite-class unit. Shown on the boss-style bar while
    no boss is fighting you.
    Each also casts its unit's own spells (`AscendantSpells.SPELLBOOKS`,
    run by a phaseless `BossBrain` with `require_sight`: only in combat,
    only with a clear line to you, 3.5 s between spells). Vindicator
    (Aetheric): Judgement, Consecrate, Vindicate. Dreadknight (Entropic):
    Dread Grasp, Blight Pool, Death March. Cantor (Pale): Pale Litany,
    Hollow Choir, Call the Veil (two Mindbenders). Listed on the Monsters
    wiki page.
Affixes are data: stat lines (more damage/Life, move/attack speed, damage
taken, regeneration, Ward, leech, on-hit status, unstoppable), an optional
aura, and a `mechanic` id the component runs. Health bars list each rare
enemy's affixes. Stat scaling is read by `Enemy` (`rarity_component`), not
applied in the component's own `_ready()` (children ready before parents).

**Figment tiers, bands and mods** (`data/figments/figment_mods.gd`,
`FigmentRoller`, v4.72, user design): tiers 1-21 in three bands, Low (1-7),
Mid (8-14) and High (15-21). Mods come from three pools, and each band opens
one more: Low rolls Pool I only (1-3 mods), Mid rolls I-II (2-5) and High
rolls I-III (4-7). Values grow 5% per tier within a band. Every mod adds
Pack Size, Item Quantity and Item Rarity (`FigmentItem.recompute_rewards()`).
Easy mods pay mostly in Pack Size, hard ones in Quantity/Rarity.
  - **Pool I:** monster Movement Speed, Area of Effect, Cast Speed; more Boss Life.
  - **Pool II:** monster Attack Speed, Crit Chance and Crit Damage (monsters
    can't crit without it; x1.5 base), extra Projectiles; more Boss Area and
    Boss Speed (cast, attack and move).
  - **Pool III:** monster Damage, damage conversion (30-50% to a random
    Fire/Cold/Lightning/Aetheric/Entropic/Pale, split and mitigated separately
    in `Player.take_damage()`); more Boss Damage.
`boss_*` mods hit the Figment boss and Ascendants (`Enemy.is_map_boss_target()`).
Enemy hooks: `Enemy.map_mod()`, `get_area_multiplier()`, `get_cast_speed_multiplier()`,
`get_extra_projectiles()`, `roll_crit()`, `get_map_conversion()`. BossBrain casts
a scaled copy of each ability (`_scaled()`): radius x area, telegraph / cast speed
(never below 60% of the original), plus extra volley projectiles. Pack Size adds
copies of a pack's own units (`GeneratedMap._grow_pack()`). Figments rolled
before v4.72 keep their old monster damage/life multipliers. Empowering one
strips those legacy mods.

**Endgame progression** (`systems/figment_tree/FigmentProgress.gd`): every
completion is recorded per style and tier (`GameState.figment_completions`,
"style:tier"). Each style is worth three Figment Tree points, one for its
first clear in each band (14 styles x 3 = 42; v4.72 user change from one per
tier). Figments drop, and can
be empowered, at most one tier above the highest tier completed, so tiers open
one at a time. The free Reality Engine run is always Tier 1. `MILESTONES` is
the frame for the endgame story. Its texts are placeholders: the premise is
only that the Reality Engine is rebuilding one scattered memory, and whose it is
and the final encounter once every band of every style is cleared are still to be designed.

**Figment Tree** (`systems/figment_tree/FigmentTree.gd`, screen
`ui/figment_tree/`, `L` / Tab menu): a passive tree that steers what spawns in
Figments. The root is always allocated; a node needs a link to an allocated
node; a refund is free as long as everything else still reaches the root;
"Refund All" clears it. 83 nodes in six sectors (small nodes 1 point,
notables 2-3): **Terrain** (style family weights for dropped Figments, plus
notables that add Quantity in that family), **Factions** (pack weights for
Unchartered/Hollowed/Synod/Veilborne packs, plus notables that add Rarity
against that faction), **Monsters** (Pack Size and Elite/Champion/Ascendant
weights; Ascendancy gives them an extra drop roll), **Rewards** (drop chance
per category: currency, Slates, jewels/Lenses, uniques, gear), **Encounters**
(extra chests, chest loot, boss Gold/XP, boss drop rolls, extra Maw Fragment
chance), **Figments** (Figment drop chance, a chance for a dropped Figment to
roll a tier up, and Deeper Reality: +1 mod). Effects are summed by
`FigmentTree.effect(key)` and apply only inside a Figment. Known gap: changing
the tree while a portal back into a Figment is open can reshuffle that map's
packs when it is rebuilt.

**Shops** (`entities/interactables/gear_shop/`,
`entities/interactables/spell_test_shop/`,
`entities/interactables/brand_shop/`, `ui/shop/ShopScreen.gd`): three Hub
interactables, same walk-up-and-`E` pattern as the Reality Engine.
**GearShop** sells 6 `ItemRoller`-rolled items per Hub visit for Gold (a
brand-new invented currency — see gap below), cost scaled by rolled
rarity, plus a "Reroll Stock" action button (invented `15` Gold) to
refresh the offered items on demand without leaving. **AmmoStore**
(`entities/interactables/ammo_store/`) has no menu: one `E` press buys a
full resupply - every reserve but Arrow topped up to
`AmmoInventory.STARTING_AMMO` (never reduced if above it) and every
magazine in both weapon sets filled, priced per round by
`Constants.AMMO_ROUND_COST` (placeholders). The prompt shows the live
cost; short on Gold buys nothing. **SpellTestShop**
lists every ability under `data/abilities/instances/` for free — an
explicit testing/debug tool (user-requested), not a designed economy
feature, so you can unlock everything without grinding Tome drops while
testing other systems. (The old BrandShop was removed with the Cube in
Rev2 - Brands drop as loot only.) The shops share one generic `ShopScreen` (caller supplies the entries + a buy
callback, plus an optional single "action" button for GearShop's reroll —
same "one shared screen" shape `ItemCard` already uses for item/slate/
ability display). New-game starting Gold is 1,000,000 (2026-09-06, dev/
testing convenience — `GameState.reset_to_defaults()`; Continue restores
whatever a save actually has).

**Loot generation** (`data/items/item_roller.gd`,
`data/abilities/tome_roller.gd`, `entities/pickups/loot_pickup/`,
`entities/pickups/gold_pickup/`): killing an enemy can drop up to six
different things (Gold, Gear, a Skill Tome, a Brand, a crafting
consumable, or a Slate — first match wins, "one drop max per kill" per
the existing convention). **Gold**: `Enemy.gold_reward` (per-archetype, invented)
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
**Weapons roll from a separate, real affix library as of Patch v3.9**
(`data/affixes/weapons/<type>/*.tres`, 96 files across the 9 damage types
+ generic + base-type-exclusive, `ItemAffix.weapon_type_filter` gates the
exclusives by type key or by kind, "melee"/"ranged"/"conduit" — transcribed directly from the Patch v3.9 doc's own Tier-1
tables) instead of the generic `AFFIX_POOL` below for Rare weapons
specifically — split into real prefix/suffix pools (max 3 each, no
duplicate `stat_key`s), still scaled through the exact same tier-decay
mechanism as everything else since the doc never gives tiers past T1.
Every other item category (Armor/Shield/accessories) still rolls from
`AFFIX_POOL` unchanged.
`flat_<stat>` affixes (`flat_strength`/`flat_agility`/`flat_intellect`)
are real, not descriptive-only — gear's stat source (see Player section
above); `flat_ward` and the 4 `*_resistance_pct`
affixes are real too as of Patch v3.2 (Ward pool size, Resistance
mitigation - see the Combat formula section above); the damage/armor
increased-% affixes are still descriptive-only (see flagged gap).
**Skill Tomes**: a separate, flat invented `8%` chance (not scaled by
loot_quantity) rolls a `SkillTome` for a random ability the player
doesn't already own (`TomeRoller.gd`) — per Patch v3.1's Skill System,
abilities are no longer freely available, they have to be found this way
(or granted by the SpellTestShop). Gear/Tomes both spawn as a
`LootPickup` — a floating/bobbing placeholder sphere colored by rarity,
auto-picked-up on touch (a judgment call, see gap below). Gear lands in
the footprint grid (`GameState.inventory`, persisted in full) and is
equippable from `InventoryScreen`, or stays on the ground if there's no room; a Tome unlocks its ability into
`GameState.owned_ability_ids` and shows up in `AbilitiesScreen`.

**Crafting, inventory, stash & portals** (Crafting & Inventory Rev2,
`documents/Aether_Crafting_Inventory_Rev2.docx`; replaces Section 20's Cube).
- **Orbs** (`systems/crafting/CraftingResolver.gd`): Quickening, Grafting,
  Elevation, Forging, Ascendant, Recasting, Severance, Absolution, Anchoring,
  Tempering, Opening, Reckoning. `preview()` has no side effects and gives
  every possible modifier/tier with its exact chance; `apply()` validates
  first, so a failed craft consumes nothing. Rarity limits: gear 1/1
  Uncommon, 3/3 Rare; Slates 1/1, 2/2. Unique/Mythic aren't Orb-craftable;
  corrupted items only take Opening and Tempering.
- **Modifier pools**: real gear rolls from `GearModifierPool` (built from
  `ItemRoller.AFFIX_POOL` and the weapon affix library with the same
  eligibility rules drops use, 5 tiers gated by item level). Each slot has
  a role through `AFFIX_POOL`'s `slots` lists (v4.55): Gloves and Rings
  offence, Amulet build-defining, Helmet caster/utility, Body and Shield
  major defence, Boots mobility, Belt sustain; attributes, Resilience, Life
  and resistances are filler everywhere; Slates from
  `SlateModifierPool` (their own tags only: a Cold Slate rolls Cold
  modifiers, a Fire/Cold Hybrid Fire and Cold ones; each damage type and
  Spell has 2 prefixes and 3 suffixes so Forging's 4 always fit). Gear and
  Slate pools never mix. Test content can register its own pools.
- **Aether Tolerance** (Slates only): each Slate rolls a crafting budget on
  drop; each Orb spends a random amount; at 0 the Slate is finished. Gear
  has no budget and can be crafted indefinitely.
- **Brands & Edicts** (`data/crafting/brands/`, `edicts/`): 20 tag Brands,
  Prefix/Suffix, Preservation, and Vestige support; tags combine (Fire +
  Cold needs both). Tag and positional Brands narrow both what an Orb adds
  and which existing modifier Severance, Absolution, Recasting (removed and
  added) and Anchoring pick; Reckoning and Tempering ignore them. A modifier
  with no `def` (drop-rolled, or loaded from a save) gets its tags from the
  matching pool def (`CraftingResolver.affix_tags()`). `GearModifierPool`
  derives tags for lines with none of their own: ailment lines take their
  ailment's damage types, plus life, critical, resistance, armour, mana.
  Brands must be carried and activated
  (`ActiveBrands`; one no longer carried drops out); Edicts sit on the item
  until its next resolved craft.
  All player-facing names/errors live in `data/crafting/currency_text.tres`.
- **Crafting in the Inventory** (the old K screen is gone): right-click a
  Brand to activate it (red border, applies to the next Orb); right-click an
  Orb, Edict or stone to pick it up (gold border), then click a grid item or
  paper-doll slot to use it - hovering an item first previews the Orb: its
  card marks each modifier the Orb would remove, replace, anchor or reroll
  (with the chance) and dims the safe ones, then lists what it can add
  (`CraftPreview.affected`, `ItemCard.craft_preview_for`). Reckoning on a
  Lens also rerolls its radius modifier's value. Esc or right-clicking the currency again puts it back.
  Hand-authored starting gear must be unequipped first (it becomes its own
  copy). Right-clicking a Figment empowers it. Currency drops from enemies
  as loot pickups; currency tooltips explain each one.
- **Inventory (B)**: a 14x7 footprint grid (`GridInventory`,
  `GameState.inventory`), no rotation; currency stacks to 100 per cell.
  Right-click to equip (displaced gear goes back into the grid, or the swap is
  undone if it can't fit), click the paper doll to unequip; left-drag moves.
  The stats column only shows after C (C while the inventory is open toggles
  it; opening the inventory from the Character screen keeps it). Doesn't pause
  the game; combat input is ignored while the cursor is showing. Full
  inventory leaves pickups on the ground ("Inventory full" on the HUD).
- **Stash**: the chest in the Hub (E) opens 4 general tabs plus Currency and
  Slate tabs; drag between sides or right-click to send. Orbs work on
  stash items; Brands must be carried. F6 opens a debug grid view with
  test-loot buttons.
- **Portals**: T opens a portal in a generated map; walking in saves the
  map (seed, defeated enemies, loot on the ground, portal spot, Figment)
  to `GameState.portal_map_state` and the save file, and the Hub's return
  portal rebuilds it exactly. Unlimited (`Constants.MAX_PORTALS = -1`).
  The run ends on death or when a new map is entered.
- **Throwables** are on hold (Rev2): `ThrowableStack.gd`, the Player/HUD
  throwable hooks and the throwable item data are still present but unused.

**Infusion/Shrivening Stone** reroll or clear a weapon's
`infused_damage_type`.

**Shard of Tharsis** (Patch v3.6 rework, `systems/crafting/
CorruptionSystem.gd`/`CorruptionOutcome.gd`): corrupts an item by rolling
one of 4 severity tiers (Minor 55% / Significant 30% / Major 12% /
Extreme 3%), then one of that tier's named outcomes (22 total — socket/
implicit/tier changes at Minor, special affixes and defensive auras at
Significant, item-defining outcomes like Hollow/Inversion/Veiltouch/
**Ascendant** (Patch v3.6b - upgrades a Weapon's `scaling_grade` one step,
e.g. B→A; near-misses, logged not erroring, on an already-S weapon or any
non-Weapon item) at Major, run-defining ones like Transcendent/Unmade at
Extreme). Replaces the previous flat 8-outcome weighted list. **Veiltouch**
(Major) is the
one real gear/Slate crossover in this project — pulls a random Slate
Affix Pool entry (see below) and grafts it onto the item as a real
explicit modifier, once per item. A corrupted item can't be corrupted again, and Orbs only allow Opening
and Tempering on it (Rev2).

**Slate Affix Pool** (Patch v3.6, new — `data/items/SlateAffix.gd`,
`systems/crafting/SlateAffixPool.gd`, `data/slates/affix_pool/`): a
tag-organized pool of rollable Slate modifiers, entirely separate from
gear's own `ItemRoller.AFFIX_POOL` — the only crossover is Veiltouch
above. Currently 36 hand-generated stubs (3 per tag × 12 tags: the 9 real
damage types plus spell/attack/generic), not real design — scaffolding
for a future procedural Slate-affix roll. Hand-authored Slates still use
their own fixed `SlateModifier` list, untouched by any of this.

**Map screen** (`ui/map_screen/`, `M`): a top-down schematic of the
current generated Map's room graph — start room green, Vault gold, your
current room outlined — reading `GeneratedMap.graph` directly (the same
`MapGraph` data used to build the real geometry, no re-derivation). Shows
a "no map data" message in the Hub/TestArena instead of erroring, since
those are static hand-built scenes with no such graph.

**Procedural map generation** (`systems/level_generation/MapGraph.gd`,
`levels/generated_map/GeneratedMap.gd`): a fresh, differently-shaped Map
every time you enter one — no fixed seed. **Each Figment type has its own
layout rules** (`MapLayout`, chosen by `MapTileset.layout`), and each style
then reshapes its kind through the tileset's Layout fields (grid size, room
count, how winding the graph is, room sizes, corridor width, wall height,
pillar chance, cave outcrops, mound count/size, pass width, cliff height),
so styles of one kind play differently (v4.51):
  - **Dungeon** - `rooms`: rooms of varied rectangular size joined by
    walled corridors. Cellblock: many small cells on long narrow corridors,
    bushy with dead ends. Undercroft: few huge pillared halls, 6.5 m walls.
    Mine: a long winding chain of rough rooms with rock outcrops along the
    walls. Foundry Pit: big halls with 7.5 m walls. Frozen Crypt (Snow):
    mid-sized colonnaded rooms.
  - **Open field** (Dunes, Tundra, Frostwood): one open field, no interior
    walls. A cell grid (`MapGraph.generate_full_grid()`) drives spawning
    and the Map screen; the start is the middle of one edge and the
    Vault is the far side. Walkable mounds (Tundra: big rolling hills;
    Frostwood: nearly flat, dense trees via `scatter_scale`), ridges plus
    an invisible wall around the edge, 1-2 packs per cell, the boss on a
    raised crest with two ramps.
  - **Streets** (City: Residence, Downtown, Trainyard, Harbor; v4.73):
    `StreetBuilder`. Cells are junctions, plazas, the start square or the boss
    courtyard; connections are streets. Each edge has a wall 2.5 m back and
    buildings fronting the street (`MapTileset.buildings`/`landmarks`,
    `building_scale`), lamps, props, steam vents, rails (`rails`) and a
    waterfront (`waterfront`). Park is an open field with `building_boundary`.
  - **Canyon** (Badlands, Glacier Pass): open basins on a spanning tree,
    separated by jagged cliff lines. Connected basins meet through one
    pass; Glacier Pass is a long winding chain with narrower passes and
    taller ice cliffs. The boss stands on a mesa with ramps. Geometry for
    both open layouts is `TerrainBuilder.gd`.
The rest of this section describes the Dungeon (`rooms`) layout. Split into two layers on
purpose: `MapGraph.gd` is pure data (no `Node3D`, no geometry) — a
randomized spanning-tree room-and-corridor layout on a grid,
guaranteeing every room is reachable from the start room. `GeneratedMap.gd`
turns that graph into actual walls/floors (simple `BoxMesh`/`PlaneMesh`
pieces), dressed by the Figment's tileset style (below). The generation
*algorithm* doesn't know or care what the rooms are made of.
  - **Rooms and corridors**: each room is centred in its grid cell with a
    footprint rolled from the style's range (`room_half`); walls sit just
    outside the floor with a doorway wherever a connection exists, and
    every connection is a walled corridor from doorway to doorway. Cells
    are sized so a corridor always fits between the biggest room and the
    boss room. Big enough rooms may get four pillars, and big rooms hold a
    second pack.
  - **Boss room** (the Vault, farthest from the start): larger than the
    style's biggest room, one flat floor with nothing to fall into (the
    old jump-gap platform trapped bosses), four pillars, and a glowing
    altar opposite the entrance. Killing the boss opens a portal home on
    the altar (`boss_portal_point`; the top of the dais in open layouts),
    outside the portal limit.
  - **Tilesets** (`data/tilesets/`, plan: the Tileset Plan doc): each
    Figment rolls a random `MapTileset` style (`FigmentItem.tileset_id`,
    named "<Style> Figment"; older Figments get a random one on entry).
    Built so far: Dungeon (Cellblock, Undercroft, Mine, Foundry Pit),
    Desert (Dunes, Badlands) and Snow (Tundra, Frostwood, Glacier Pass,
    Frozen Crypt). A style sets the floor and wall WC3 ground
    textures (`shaders/wc3_ground.gdshader` picks one of the sheet's
    variant tiles per 2.3 m cell, with noise patches of a second ground),
    the doodads, and the light, fog and sun. `RoomDresser` places an arch
    fitted to every doorway, props backed against walls clear of doorways,
    torches/braziers with a `FlickerLight`, corner clusters, and floor
    props. Every prop claims its footprint, and nothing is placed over
    another prop, a pillar, the altar, a doorway, the doorway-to-doorway
    lanes or the pack area. Trees collide only at the trunk.
    Doodads are WC3 models extracted by `tools/mdx_pipeline/
    extract_doodads.js` (`doodads.json`; `replaceable` names the WC3
    replaceable texture for models like trees) into `assets/models/doodads/`,
    with wrappers in `entities/environment/doodads/`. Beach/Shore/Strand
    and the other coastal Desert styles need water and aren't built.
  - `levels/test_arena/TestArena.tscn` still exists as a static hand-built
    sandbox for direct-from-editor testing, but the Reality Engine no longer
    sends you there — `GameState.MAP_SCENE` now points at
    `GeneratedMap.tscn`.

**Character Screen** (`ui/character_screen/`, `C`): a large STRENGTH/
AGILITY/INTELLECT row up top (PoE-style, always live), then all three
`StatSheet` stats split into Offense/Defense/Misc, plus Predicted Main
Hand/Offhand Damage and Crit Chance/Damage (crit-inclusive, keyed by
equip slot so a ranged weapon in the main hand shows a real crit line),
Life/Mana regen, Action/Move Speed, and current Level/XP — built via
`StatSummaryBuilder.gd`, shared with the Inventory screen's own stats
column. Read-only — stats only change by equipping different gear
(Section 12), there's no allocation UI here.

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
path), owned rolled loot, Fate Board layout including any Spell Slate's
designated ability (`GameState.fate_board_placements` - see Fate Board
above, 2026-08-30 fix), ability loadout + spell levels (old saves' ranks
convert to level rank + 1), player level/XP, Gold, unlocked ability ids
— not current Health/Ward/Mana,
player position, or map state. `StatSheet`'s raw values
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
ridge flat) **plus a foreground tree band** (`TreeSilhouette.gd`, new -
22 procedural conifer silhouettes, same flat-facing-camera trick, scaled/
seeded per-tree so a cluster doesn't look copy-pasted - user request: "add
trees to the landscape"), a night sky (`shaders/night_sky.gdshader`:
hashed stars, a moon, drifting cloud cover that occludes them, and a
lightning-flash uniform), falling rain (`CPUParticles3D`), and rain/
thunder audio synthesized at runtime sample-by-sample
(`systems/audio/ProceduralRain.gd`/`ProceduralThunder.gd` push into an
`AudioStreamGenerator` - no audio files needed for those). Thunder fires
at random intervals (tightened to 6-16s) and syncs a light flash to the
rumble - **the flash itself was a real, user-caught bug**: the shader
damped it to near-zero exactly where the camera actually looks (it only
read strongly near the sky's zenith, off-screen given the camera's
near-flat forward angle), and boosting the moonlight's energy never
touched the mountains/trees at all since both use unshaded flat-color
materials that ignore scene lighting entirely - the flash was
sky-only and essentially invisible in practice. Fixed on both fronts
(`MainMenuBackground._set_flash()` now also lerps every registered
silhouette material's own albedo directly) plus a quick second flicker
for realism. Menu music (`MainMenu.gd`) loops `assets/music/lament.mp3` -
the one real audio asset in the project, everything else here is
generated.

**Menus & HUD**: `MainMenu` (Continue/New Game/Settings/About/Quit),
`PauseMenu` (`Esc` — Resume/Return to Hub/Quit; Inventory/Fate
Board/Abilities/Character/Map are hotkey-only, not buttons),
`DeathScreen` (on `HealthComponent.died`, offers Return to Hub or Quit),
`ui/player_hud/` (always-on Life/Mana orbs flanking the ability bar -
Ward renders as an inset vertical strip along the right edge of the Life
orb, 20% of its width, filling/draining top-to-bottom same as the main
Life liquid fill (`StatOrb.set_ward_value()`, 2026-08-30, replacing the
previous outer-ring design per user direction) - a notched XP bar
spanning from the level badge at the far left to near the right screen
edge, its text inline on the bar itself (GW2-style layout), now a moving
yellow/gold/orange gradient with twinkling stars visible in the filled
portion (`xp_bar.gdshader`, 2026-08-30, replacing the previous static
6-color rainbow gradient per user direction) - the fill now tweens from
its old value to its new one on every XP gain instead of snapping
(`PlayerHUD._on_xp_changed()`, 0.5s), and a level-up crossing plays the
fill-to-full, snap-back-to-empty, fill-to-new-remainder sequence rather
than jumping straight to a smaller-looking ratio. **2026-09-06:** a
second, brighter trail layer (`_xp_trail_clip`) now snaps instantly to
the new ratio on every gain while the main fill tweens up to meet it -
inverse of the health bar's damage trail (main drops instantly, trail
lingers) - a Gold counter, and an active-weapon indicator that flashes
whenever the equipped weapon changes),
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
| Weapon stance (hold) - preps a special melee attack, aims (ranged), or raises a shield if Behaviors is set to Raise Shield | Right Mouse |
| Reload | R |
| Swap weapon set (tap) / stance page (hold) | X |
| Cast equipped ability (slot 1-4) - hold + release to aim for Comet/Inferno/Stormcall | 1 / 2 / 3 / 4 |
| Pause menu (Resume / Return to Hub through a portal / Quit) | Esc |
| Open a portal to the Hub (generated maps; elsewhere returns directly) | T |
| Open Fate Board directly | P |
| Open Inventory directly | B |
| Open Abilities (equip/upgrade) directly | N |
| Open Character Screen directly | C |
| Open Map Screen directly | M |
| Open Figment Tree directly | L |
| Rotate pending Slate *(Fate Board editor only)* | R |
| Flip pending Slate *(Fate Board editor only)* | Q |
| Interact *(Reality Engine, shops, Stash chest - Hub only)* | E |
| Debug grid inventory / stash view | F6 |

P/B/N/C/M work from anywhere — gameplay, the pause menu, or another such
screen — and jump straight to their target, closing whatever else was
open. Pressing the same key again while already on that screen closes it.
C while the inventory is open toggles its stats column instead. None of the five have a `PauseMenu` button — hotkey-only.

## Flagged design gaps (need your call, not resolved unilaterally)

1. **Ward restore-on-parry ratio**: placeholder 15% of max Ward — Section
   07/16 both confirm this is deferred to playtesting, no number given.
   Patch v3.2 gives real numbers for passive regen (4%/s) and on-kill
   (5%) but not Parry specifically, so this one placeholder survives the
   patch unchanged. Also invented and doc-unsupported: Ward's `flat_ward`-
   only pool-size model and its `+2%` per-Enigma-point multiplier (user
   direction, overriding the patch's own "scales through gear rolls AND
   Enigma investment" wording, which read as Enigma contributing its own
   flat share - the patch's 3 target bands, Low 800-1200/Moderate
   2000-3000/High 4000-6000, were never hit by either version and aren't
   being targeted anymore, since a fresh character now starts at exactly
   0 Ward with no Ward-granting gear); Resistance's mitigation floor/
   ceiling (-200%/95% - the patch caps neither explicitly, only that
   Resistance Shred can push Resistance negative; these two numbers are
   user-set directly, 2026-08-30, replacing this project's own earlier
   invented 75%-cap/uncapped-floor placeholder).
2. **Stance depletion weights**: ordering is confirmed (Blunt/Explosive
   strong -> Piercing/ranged moderate -> Spells weakest), but no
   percentages anywhere, so Physical 1.0 / Elemental 0.6 / Esoteric 0.35
   remains a well-justified guess. On top of those category weights,
   ordinary attacks now also carry a flat `ATTACK_STANCE_DAMAGE_
   MULTIPLIER` of 0.2 (`StanceComponent.gd`) - user-reported feel issue,
   ordinary hits were breaking Composure almost immediately and drowning
   out Parry's own dedicated role as the primary Stance-break tool
   (Section 07). Parry's own `apply_parry_damage()` is untouched by this,
   still full-strength.
3. **First-person melee weight** (Pillar 2): camera shake/kick + hitstop +
   a swinging weapon (a real model for Greatsword/Dagger now, still the
   placeholder blade for anything else) exist, but the docs are
   camera-agnostic on *how it should feel* (timing, intensity), and the
   real model's pose was tuned by eye via screenshots, not exact
   hand-placement - worth your own live nudging for final polish.
4. **Ability numeric tuning**: `motion_value`, `scaling_grade`,
   `cooldown_seconds`, `resource_cost`, `radius` on every Ability instance
   (17 now, including the 8 Section 26 additions from 2026-08-30) are
   invented (relative to each ability's described weight) — the doc gives
   the damage formula and flavor text but never per-ability numbers.
5. **Fate Board UI is a bounded 150x150 grid with pan** (2026-09-01, up
   from 32x32), not the doc's literal "effectively unlimited" board — a
   deliberate scope cut, though large enough that hitting the edge in
   practice is unlikely.
6. **Inventory footprints come from a data table**
   (`data/inventory/footprints.tres`); Crossbow, Bow and Gauntlet aren't
   in the doc's table, so they're guessed (3x2, 3x2, 2x2). Anything not in
   the table (Figments, Tomes, consumables, currency) is 1x1.
7. **Armor mitigation applies one formula to all Physical damage types**:
   Section 16 says Kinetic gets it "full," Piercing "partial," Explosive
   a "flat reduction," but gives no ratio for the latter two.
8. **`PlayerMeleeAttack`'s swing arcs/timings are invented placeholders.**
   Each swing sweeps a per-family arc (thrust/slash/heavy/whip/fist:
   reach, half-angle, splash share, target cap - `SWING_SHAPES`) every
   Strike frame with line of sight; the enemy nearest the crosshair takes
   full damage, the rest the splash share (50-75%, 100% on a charged
   attack). Numbers need playtesting.
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
10. **Enemy Roster v1 defaults (the brief's open questions, not decided)**:
    FigmentBoss uses the Chieftain model at boss scale - a *mounted*
    rider, so it reads as horse + rider; `AMMO_ROUND_COST` values are
    placeholders; the ammo store tops up to `STARTING_AMMO` (no separate
    max-reserve cap); the Lord's element order is Fire -> Cold ->
    Lightning; unit scale is set per model in
    `tools/mdx_pipeline/models.json`. Unit XP/Gold rewards are invented
    too. Every unit keeps `Enemy.tscn`'s 1.9 m collision capsule
    regardless of model size, so the 6 m Lord and the ~4.3 m FigmentBoss
    can be walked into visually.
11. **Reality Engine / Hub scope cuts**: a real Figment-selection UI now
    exists (reuses `ShopScreen` - see the Hub section above), but leaving
    a Map is still always manual, not triggered by clearing enemies or
    completing the boss (killing the boss fires
    `EventBus.figment_completed` for Figment Tree points and opens a
    portal home on the boss room's altar, but doesn't end the run). Settings (title screen and pause menu, shared
    `SettingsPanel`, saved to `user://settings.cfg` by `GameSettings` so
    New Game doesn't reset them): Mouse Sensitivity, Field of View,
    Master Volume, Fullscreen, V-Sync, plus a Controls tab that rebinds every
    gameplay action to one key or mouse button (`GameSettings.REMAPPABLE`;
    a key taken from another action swaps over; Reset to Defaults). "Press E"
    prompts follow the Interact binding. Master volume
    now has real audio to affect (Main Menu music + procedural rain/
    thunder, see the Main Menu background section above) but nothing
    plays in the Hub/Map yet.
12. **Ability casting is still a generic AoE-at-cast-point hit for every
    ability** (3 of 9 add ground-targeting + bespoke impact VFX - Comet,
    Inferno, Stormcall - but even those deal generic AoE damage on
    landing, not their actual described mechanics: Comet's "massively
    increased damage against Chilled/Frozen enemies," Winter's Eye's
    traveling orb, Frost Armor's melee-retaliation trigger).
    `applies_status_effects` IS now wired though - see
    `StatusEffectComponent` (Ignite/Chill/Freeze/Electrocute/Unraveling/
    Shock, Section 09) - `PlayerAbilityCast._cast()` applies each
    ability's listed effect(s) to every enemy it hits.
13. **Figments have no doc-sourced affix table** (none could exist - this
    whole system is invented, not doc content at all) — the affix pool
    and tier curve (`FigmentRoller.gd`) are invented throughout, including
    the drop-scaling curve (`roll_for_drop()`) and the Empower Gold cost
    (`CraftingSystem.EMPOWER_FIGMENT_GOLD_COST`). Selection/inspection UI
    is real now (see the Hub section above) - this gap is narrower than
    it used to be.
14. **Resilience/DoT mitigation is wired, Debuff effectiveness isn't**
    (`Player.get_dot_mitigation()`/`DamageCalculator.dot_mitigation()`
    from gear `flat_resilience`; `StatusEffectComponent.
    _debuff_effectiveness_multiplier()` is a flat 1.0 - the old six-stat
    Intellect that drove it is gone). A Stamina pool/dodge-roll, Stagger
    and Stun Recovery are also unwired - no such mechanics exist
    (Electrocute/Freeze's stun is a flat, invented duration).
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
18. **Loot generation picks a real base item and re-rolls rarity +
    affixes, rather than generating a truly procedural item shape** —
    `ItemRoller.roll()` picks a real base (weapon type, damage type,
    scaling grade, armor values, etc.). As of the 2026-08-30 pass, that
    base pool IS Section 25's real tiered catalog — no longer deferred.
    `tools/generate_base_types.gd` (a headless one-shot generator, kept
    in the repo as a real tool, not scratch) parses the design doc's own
    Section 25 text and writes one `.tres` per tier straight into
    `data/weapons|armor|shields/instances/` and `data/items/instances/`
    (throwables) — ~853 generated bases across all 27 doc-detailed weapon
    types, 4 armor slots, 8 shield lines, and 5 throwable lines, each
    tagged with a real `item_level` (the tier's own doc "Level") and
    `base_line_id` (which doc "Line" it belongs to). `ItemRoller.
    _pick_base_item()` now takes a target item level, keeps only the
    single highest-item_level tier per line that's still at or below it,
    and rolls uniformly among those plus the untagged pre-existing
    hand-authored singles - "always the current best base this level has
    unlocked," per-line, same principle PoE-style ilvl-gated bases follow.
    `Enemy._compute_item_level()` derives that target from the Map's
    area level plus the killer's own rank offset (see gap #29 below).
    Per-tier "Base Damage"/"Base Armor" columns are doc-exact (averaged
    across their range); native_damage_type/is_two_handed/is_ranged per
    weapon type are an invented-but-consistent guess (the doc never pairs
    weapon type -> damage type anywhere) documented in the generator's
    own `WEAPON_TYPE_META` table. Each tier's doc "Implicit" was
    originally folded into `flavor_text` as flavor rather than a real
    `ItemAffix` - Patch v3.6b's repair pass (`tools/repair_weapon_lines.
    gd`) converted 504 weapon base files' implicits into real `ItemAffix`
    entries (`is_implicit = true`), but this is still descriptive for
    anything reached via a loot drop specifically: `ItemRoller.roll()`
    always wipes and re-rolls `affixes` on every roll regardless of base
    (see its own comment), so the base file's now-real implicit still
    doesn't survive onto a rolled copy - same pre-existing behavior every
    implicit already had, not a regression from the repair. It's real
    data now, just not yet reachable through the one path (loot rolls)
    that actually reaches the player. `flat_<stat>` roll affixes are real
    (summed into `StatSheet` - see the Player section above), and
    `flat_ward`/the 4 Resistance affixes joined them as of Patch v3.2, but
    the damage/armor increased-% affixes (`physical_dmg_increased`,
    `flat_armor`, etc.) are still descriptive-only — no aggregation of
    those into the damage/armor formulas exists yet. Patch v3.6b also
    fixed `scaling_grade` itself, which every one of those ~853 generated
    weapons had stuck at C regardless of line identity - now set per-line
    from Implementation Brief v3.6b's own table, real and consumed by
    `DamageCalculator` exactly as before. That table listed up to two
    (stat, grade) pairs per line, implying real per-weapon-line multi-
    stat scaling - out of scope here (confirmed with the user first):
    only the grade number is real, the stat names are stored as new,
    purely descriptive `Weapon.primary_scaling_stat`/
    `secondary_scaling_stat` fields, not wired into damage calculation.
    Shortbow/Longbow (32 files) and 9 Conduit (caster weapon) types -
    Wand/Staff/Athame/Spell Gauntlet main-hand, Rod/Grimoire/Tome/
    Talisman/Fetish offhand (108 files, `Weapon.is_conduit`/
    `conduit_stance_type`/`spell_page_tag`/`unleash_copy_count`) - were
    generated the same way, extending this same catalog. Patch v3.7
    replaced every weapon's single `base_damage` with a real roll range
    (`base_damage_min`/`max`, `rolled_base_damage` set by `ItemRoller.
    roll()` on an actual drop, `get_base_damage()` falls back to the
    range's midpoint otherwise). Conduit spell power was removed in
    v4.14 (spells carry their own base damage). The Crafting pass
    (gap #25) extended this same pool with 4 more descriptive-only
    entries (Evasion/Resistance/Resilience/skill cooldown) so every Brand
    category has *something* real to roll - same gap, just wider now, not
    a new one. Shield gained `evasion_value`/`ward_value` fields
    alongside its original `armor_value` (matching Armor's existing
    hybrid shape) so Buckler/Rune Shield/Warded Barrier-style lines that
    lead with Evasion or Ward instead of Armor could be represented at
    all - like Armor's own evasion_value/ward_value, these are
    descriptive-only, not aggregated (only `armor_value` is real, summed
    in `EquipmentComponent.compute_stat_bonuses()`).
19. **Loot pickup is auto-pickup-on-touch, not a manual pickup/prompt**
    — a judgment call, not requested verbatim; fits how often gear
    would drop during combat better than a keypress flow, but is a
    different UX than the Reality Engine's "walk up, press E" pattern used
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
    socket system anywhere in this project (`Item.max_sockets` is now
    settable — Bore/Corruption, Section 20 — but nothing can be socketed
    INTO it yet; Gems/Jewels are still explicitly not-built-yet), so
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
24. **`StatusEffectComponent` only covers 5 of Section 09's 11 status
    effects** — Ignite/Chill/Freeze/Electrocute/Unraveling, the ones with
    a real applier today (`Ability.applies_status_effects` on the
    elemental/esoteric spells). Bleed/Armor Shred/Stagger-Stun (Physical
    family) have no weapon-side proc mechanic and Scorch/Aetherburn/
    Pallid have no Fire-channel/Aetheric/Pale ability yet, so both groups
    are left for the component to grow into once a real source exists.
    Blind is deliberately not modeled at all — the patch doc itself defers
    its mechanical expression, not just this project. Every duration/
    magnitude/stack-threshold inside the component (Ignite's 4s DoT
    dealing 50% of the triggering hit, Chill's 30% slow, 3 stacks to
    Freeze, Electrocute's 0.8s stun, Unraveling's +25% Esoteric damage
    taken) is invented — the doc names each effect and its qualitative
    behavior only, no numbers, same as every other unspecified-tuning gap
    on this list.
25. **Orb crafting numbers are placeholders** (Crafting & Inventory Rev2
    leaves them open): Aether Tolerance starting ranges and per-Orb cost
    ranges (`Constants.STARTING_TOLERANCE_*`, `TOLERANCE_COST`), Orb tier
    roll weights (`GEAR_TIER_WEIGHTS`/`SLATE_TIER_WEIGHTS`), currency drop
    weights (`CURRENCY_DROP_WEIGHTS`, 12% per kill), inventory/stash sizes,
    and the quality cap of 20. Defaults taken for the doc's open questions:
    no Slate tier cap by size (`SLATE_TIER_CAP_BY_SIZE` empty), the Shard of
    Tharsis spends no tolerance, one anchored modifier per item. Judgment
    calls: AFFIX_POOL entries have no prefix/suffix of their own, so
    `GearModifierPool.SUFFIX_KEYWORDS` decides; Reckoning rerolls anchored
    modifiers too; Absolution under a positional Brand or Edict removes only
    what's allowed and drops to the lowest rarity that still fits; several
    active Vestiges combine their pools; Preservation is only consumed when
    another Brand applied. Quality doesn't raise modifier values yet. Slate
    modifiers (`data/slates/affix_pool/`) are still stubs, so crafted Slate
    modifiers don't feed any stat. No real Vestiges exist yet (no boss pools).
    Old Cube Brands in a save convert on load
    (`ItemSerializer.LEGACY_BRAND_CURRENCY`; e.g. Calcine -> Fire Brand,
    Cleave -> Orb of Anchoring, Binder -> Preservation Brand, Sever -> Orb of
    Absolution). Corruption outcome probabilities are still invented.
26. *(Resolved in Rev2: the inventory layout is saved with the footprint grid.)*
27. **The Slate System's numeric/probabilistic choices beyond Section
    10's own doc-exact numbers are invented** - the Chain Bonus tiers,
    Main Stat by Tag table, and Slate Size/Rarity brackets are doc-exact
    and transcribed verbatim; the Stats Per Tile values were doc-exact
    (1.7/0.8) until v4.9 cut them to 0.6/0.3 to pair with chain
    amplification. Everything `SlateRoller` decides beyond those (which
    shape template within a size bracket, Hybrid chance, Aether cost) has
    no doc-sourced formula - Section 10 states the mechanics and axes,
    not their exact acquisition curve, same "Deferred Design" pattern as
    Crafting (gap #25). One interpretive call worth flagging on its own:
    Chain Bonus's output is treated as "increased damage"
    for that tag's category, feeding the same `increased_percents` slot
    every damage roll already accepted - the doc names the Chain Bonus
    System and gives its numbers but never states what the resulting
    percentage actually modifies; "increased damage of that tag" is the
    most natural reading given everything else about it (a per-tag
    bonus from a tag-scoped build-customization system), not a
    transcription of doc text. Fate Board LAYOUT itself now saves too
    (2026-08-30 fix, see Fate Board above) - both it and
    `GameState.owned_slates` (real Slate ownership) persist.
28. **Enemy rank (White/Blue/Rare/Boss) is a brand-new, fully invented
    system** - no doc-sourced enemy rarity/rank design exists anywhere
    referenced. Added 2026-08-30 specifically to give loot's new
    `item_level` gating (gap #18) something meaningful to key off per
    kill, per the user's own formula ("White mobs are the area level,
    blue mobs are the area +1, rare mobs are the area +2 levels, bosses
    are the area +5 levels" - see `Constants.ENEMY_RANK_ITEM_LEVEL_
    OFFSET`). Regular enemies roll Normal/Magic/Rare at spawn off an
    invented weight table (80/16/4, genre-standard shape, not doc-
    sourced); Boss is never auto-rolled, only set explicitly by a boss
    encounter's own scene. Deliberately scoped to item-level gating only
    - no stat scaling (health/damage) or visual tint by rank exists yet,
    since nothing else asked for it.
29. **Leveling's XP curve has been retuned twice and MAX_LEVEL (100) now
    exists** (`ExperienceComponent`, 2026-08-30 user requests) - the
    original 25%/level curve compounded to an unreachable ~10^11 XP by
    level 100; replaced with 6%/level to make level 100 actually
    climbable; then replaced again with ~19.64%/level after user feedback
    that 6% made leveling "too easy." The current rate isn't a round
    invented number - it's solved algebraically so level 99's requirement
    (the last one this system ever computes) lands on an exact user-given
    target, `4294967295 - 1` (1 below the unsigned 32-bit int limit).
    Still fully invented in the sense that no doc-sourced curve exists
    (gap #17) - just precisely pinned instead of picked by feel.
    `add_xp()` discards XP gained past MAX_LEVEL rather than banking it.
30. **Fate Board Aether budget now scales with player level** (`FateBoard.
    capacity_for_level()`, 2026-08-30 user request: "gain 2 points of
    Aether... every time you level up. Start with 10 at level 1") -
    replaces the previous flat `aether_capacity = 30`. Fully invented, no
    doc-sourced acquisition curve exists (Section 10 just calls the board
    "effectively unlimited," gated by Aether) - same "Deferred Design"
    footing as `SlateRoller`'s other invented numbers (gap #27).
31. **`levels/pinnacle_boss/PinnacleArena.tscn` isn't reachable from
    normal play** - a Belial-style crescent arena (`CSGShape3D` floor and
    invisible boundary). It spawns the Player, the Lord of the Elements and
    the UI suite itself, so it runs standalone (F6), but no Map/Hub entry
    point exists yet.
32. **Item level/stat requirements are a brand-new, fully invented
    equip-gate system** (2026-08-30) - no doc-sourced requirement system
    exists. `Item.item_level` (already existed for loot-tier selection)
    doubles as the level requirement; `stat_requirement`/
    `stat_requirement_value` are new fields the Section 25 generator fills
    in per item (a weapon's own damage-type main stat, or Vitality for
    armor/shields which have no damage type to key off, at 0.5 per
    `item_level`) - throwables get no stat requirement. Enforced in
    `EquipmentComponent.equip()`, bypassed only when `Player.
    _apply_saved_loadout()` restores a previous save (a save should
    always restore cleanly even if a later balance change or edge case
    would otherwise block it). The ~14 pre-Section-25 hand-authored items
    were left untouched (`stat_requirement == -1`, `item_level` defaults
    to 1) - trivially satisfied either way, not worth a retrofit.
    **2026-09-06 (Patch v3.8d):** a SECOND, parallel requirement system
    was added on top - `Item.level_requirement`/`strength_requirement`/
    `agility_requirement`/`intellect_requirement`, populated by `tools/
    repair_item_requirements.gd` from a more lenient level-bracket table
    and (unlike the field above) able to require two stats on the same
    item. Display-only for now (shown on `ItemCard`, red when unmet) -
    the ORIGINAL `stat_requirement`/`item_level` pair above is still the
    only one `EquipmentComponent._requirement_block_reason()` actually
    enforces, and the two systems' numbers genuinely disagree for most
    generated items (e.g. `item_level` 84 blocks equipping below character
    level 84; the new field displays "Requires Level 80") until a future
    pass repoints enforcement at the new fields.
33. **The "own one of everything" debug/testing catalogs (Inventory
    and Fate Board) now only cover the ORIGINAL small hand-authored sets,
    not Section 25's generated catalog** - user report (2026-08-30):
    "let's not add all of the new high level items to the player's
    inventory at the start." `InventoryScreen._scan_owned_items()`
    filters to `base_line_id == ""` (every generated tier has a real
    line id, every pre-Section-25 single doesn't). The same always-
    available pattern existed for `FateBoardEditor`'s Slate palette (11
    hand-authored samples, unrelated to Section 25, just the same
    convention) - user confirmed removing it too, so the palette now
    shows only real `GameState.owned_slates` drops. `AbilitiesScreen` was
    checked against the same concern and found already correctly earned-
    only (`GameState.owned_ability_ids` defaults empty) - no change
    needed there.
34. **"Implementation Brief v3.3" (a written design doc the user provided
    2026-08-31) described `WeaponStance`/`PlayerMeleeAttack` as new/stub
    components to create at new paths, but both already existed, more
    developed than the brief assumed** - see PATCH_NOTES.md's own entry
    for the full reconciliation. Net result: the brief's new ideas (the
    additive damage formula, `StanceBehavior`, jab/thrust/charged attack
    types) are merged into the EXISTING files at their existing paths,
    not the brief's literal new ones; the existing per-weapon motion
    value/duration/intensity/arm-pose architecture and Windup/Strike/
    Recovery state machine survived intact; the old combo-index cycling
    did NOT survive (removed per user direction, honoring the brief's own
    "no combo systems" line). The brief's Section 6 (ArmRig no-op
    animation placeholder methods, framed as if arm animation were
    unbuilt) was skipped entirely - real, working, screenshot-verified
    procedural animation already exists on `PlayerArmRig.gd` from earlier
    passes, so adding differently-named no-op stubs would just be dead
    code. If a future brief/patch document arrives, check it against the
    actual current file contents before implementing anything from it
    verbatim - this is the second time in this project's history a
    design document's assumptions about what already exists have turned
    out to be stale (see gap #18's own Section 25 history for the first).
35. **"Implementation Brief v3.4" (2026-08-31) had the same stale-
    assumptions problem as v3.3, a third confirmation this is a real
    pattern with these documents, not a one-off** - `ui/hud/HUD.tscn`
    doesn't exist (real path `ui/player_hud/`), no `hit_position`/
    `is_conduit`/weapon-swap input action/feature existed anywhere, and
    "Shortbow"/"Longbow" aren't real weapon types in this project's
    all-firearms-plus-Wand/Staff catalog. See PATCH_NOTES.md's own entry
    for the full reconciliation - crosshair/hit markers/critical spots
    (adapted to this project's actual Area3D-overlap hit detection, no
    real hit_position anywhere to check a point against), dual weapon
    sets (`EquipmentComponent.primary_weapon`/etc. are now computed
    properties over a 2-element array, user-expanded well beyond the
    brief's own ask once the "existing" swap feature turned out not to
    exist), and per-line ranged/per-type melee `StanceBehavior` data.
    Section 7 (Caster page 2) was rerouted by weapon_type per user
    direction rather than the brief's own Conduit-slot design, which
    conflicted with an explicit earlier decision this session ("Conduits
    are not a slot"). Only Rapier and Cutlass's Water Slices got real
    stance behavioral logic - everything else is data + an enum tag,
    exactly the brief's own scope limit ("stub the behavior methods, full
    implementation per stance is a separate pass"). Dagger's STEALTH page
    is one exception to that limit worth calling out on its own - the
    brief's wording allows it to have real logic, but gives no formula
    for it (unlike Water Slices, which came with exact code), and no
    enemy-detection-radius hook exists in this project to hang a real
    stealth mechanic off of - left as data-only, a genuine gap rather
    than an invented mechanic with no spec behind it.
36. **Hit markers redesigned to an 8-state matrix, enemy health bars, and
    a stylized boss health bar are all brand-new** (2026-08-31, user
    reference image + request) - see PATCH_NOTES.md's own entry for the
    full detail. `Enemy.is_in_combat()` (within `chase_range` OR damaged
    in the last 5s) and `Enemy.display_name`/`get_display_name()` are new
    concepts with no prior equivalent. The boss health bar keys off
    `Constants.EnemyRank.BOSS` - "Pinnacle boss" and "uber boss" both read
    as that one existing rank for now, nothing in this project
    distinguishes them from each other yet. Building this surfaced a real,
    unrelated pre-existing bug: `FigmentBoss` never actually set
    `rank = BOSS` (fixed directly in `FigmentBoss.tscn`) - it had been
    getting a randomly-rolled rank like any other enemy since the rank
    system was added 2026-08-30, meaning its loot was silently never
    dropping at the correct +5-level boss tier either.

## Explicitly not built yet (per Vertical Slice Brief scope)

A Gem/Jewel/weapon-socket system (Skill Tomes unlock abilities directly
instead — see flagged gaps; Crafting's Bore/Corruption can now raise
`Item.max_sockets`, but nothing can be socketed into it yet), a Stamina
pool + dodge-roll (active blocking exists via `ShieldBlock`, spending Composure in its place; Instinct's per-point Stamina
value has nothing to spend into yet), full 9-damage-type coverage, co-op,
any skeletal character animation (`assets/animations/` has two full
rigged animation libraries + a mannequin imported cleanly, but there's no
`AnimationPlayer`/`AnimationTree`/skeleton pipeline anywhere in this
project yet - a much bigger, separate undertaking than everything else
in this list), Conduit/Secondary (Throwable) attack input, save
persistence for mid-map state (Fate Board layout now saves - see Fate
Board above), pathfinding/
navigation for enemies (fine today — every generated room is an open box,
nothing to path around within one). A status-effect system now exists
(`StatusEffectComponent`, flagged gap #24) but only for 5 of Section 09's
11 effects. Crafting now runs on Orbs, Brands and Edicts (Crafting &
Inventory Rev2, see "Crafting, inventory, stash & portals" above).

## Opening this project

1. Install Godot 4.7.1+ (GL Compatibility renderer for broad hardware
   support during prototyping).
2. Open `project.godot` from the Godot project manager.
3. Run the project (F5) — `ui/main_menu/MainMenu.tscn` is the main scene.
   "New Game" (or "Continue Game" once a save exists) drops you into
   `levels/hub/Hub.tscn`; walk up to the Reality Engine and press `E` to enter
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
