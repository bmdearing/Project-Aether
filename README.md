# Project Aether — Godot Scaffold (v0.2, First-Person)

Vertical Slice Brief v0.1 scaffold. Godot 4.7.1, GDScript, **true first-person
3D** (Borderlands-style: camera in head, no visible player body, weapon
socket for a future viewmodel). Endgame-first structure — a Hub with a
Reality Engine leading into instanced Figment maps, no campaign yet.

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
hit. **Counter damage** (2026-08-30, user request, exact wording): melee-
attacking an enemy while ITS OWN attack is mid-swing (`EnemyMeleeAttack`/
`EnemyRangedAttack.is_attacking()` - Telegraph-or-Strike / Windup) instead
deals a flat +15% bonus, a separate, smaller bonus than Riposte's -
`EventBus.counter_hit` fires alongside the normal hit rather than
replacing it (checked first, since Riposte only applies to a Composure-
broken enemy - the two conditions don't usually overlap). Health/Ward/Mana
resource components.

**First-person arm rig** (`entities/player/player_arm/PlayerArmRig.gd`,
2026-08-30): **the arm mesh itself is currently disabled**
(`SHOW_ARM_MESH = false`, user call - the visible geometry had been the
single biggest source of bugs/iteration relative to what it added, since
the weighty-swing feel reads through the weapon's own arc/timing/hitstop
rather than through rendering an arm; only the equipped weapon shows,
still fully driven by the bone rig below). A procedural low-poly arm - no
imported skeleton/body asset,
the mesh is built at runtime with `SurfaceTool` and rigged to a real
3-bone `Skeleton3D` chain (shoulder/elbow/wrist), rigidly skinned (each
segment bound 100% to one bone). The equipped weapon's actual visual
mounts on the wrist bone (measured at runtime, not hand-placed - see the
script's own comments for two earlier placements that looked plausible
and were wrong), so a swing rotates a real bone chain instead of tweening
one rigid socket node. **Two-handed weapons get a second arm**
(`Weapon.is_two_handed`, user request) - an unarmed off-hand chain that
tracks the primary hand's actual current position with a real 2-bone IK
solve (`_solve_offhand_ik()`, damped to 50% of the primary hand's actual
displacement so the target always stays in reach - a straight rotation-
share was tried first and looked "awkward," like the off-hand let go of
the sword, since two arms with different shoulder positions and bone
lengths swing along different arcs even given identical rotations).
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
bigger arc than the baseline, a Dagger faster/tighter. Idle sway/bob, the
right-click stance/moveset "engine" in full, kicks, and sword/dagger/
cast-specific animations are all still future work - this is the rig
plus the melee swing riding on it, not a complete animation system.

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
- **Intellect**: +1% increased spell damage (a multiplier on Conduit spell
  power) and Ward, plus +3 Mana per point.

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
- **Spells:** `Conduit spell power x (1 + Int%) x grade multiplier x
  Motion Value x (1 + sum Increased%) x product(More)`. With no Conduit
  equipped, spells deal 0 damage.

`calculate()` computes `power = base + stat_value x grade_multiplier`:
weapons pass their Strength-boosted base with `stat_value = 0.0`, spells
pass base 0 with the Intellect-boosted spell power as `stat_value`.
`GRADE_MULTIPLIER_RANGES` is therefore a spell-quality multiplier (S
1.4-1.8 down to E 0.25-0.45). Increased% is one additive pool (the Chain
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
CastTimeHandler.gd`, taking damage cancels it and refunds nothing), or
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
(`CometImpact`/`InfernoPillar`/`StormcallBolt`). Abilities can be upgraded
(`rank`, 0-5) via the Abilities screen (`N`) for Gold, boosting Motion
Value and reducing cooldown. `ui/ability_bar/` shows equipped abilities
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
floating dots above an Enemy's head. Bleed/Armor Shred/Stagger-Stun and
Scorch/Aetherburn/Pallid aren't modeled yet — see gaps below.

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
currently equipped), and a paper-doll equipment diagram (right, weapons
flanking a center torso column, one ring on each side). Items with a
real `icon_path` (`assets/sprites/` - a purchased dark-fantasy icon
pack) show that icon via `ItemSlotButton`; anything without one yet
still falls back to a colored square (rarity or damage-type color).
`worn_pistol` deliberately has no icon - no firearm exists in that
asset pack.

**Throwable Stacks** (`data/items/ThrowableStack.gd`, Patch v3.5 Section
3): a stackable inventory consumable, not an equipment slot - `Player.
active_throwable` holds the currently selected stack, `use_throwable()`
(bound to middle-mouse, the new `throw_secondary` action) consumes one
and fires `EventBus.throwable_used`. `PlayerHUD` shows an icon + count in
the top-right corner, "0" shown plainly rather than hidden when empty.
How a stack gets acquired/selected is out of scope for this pass (no
crafting/acquisition system invented, per the brief) - starts null.

**The inventory grid is rearrangeable** - drag a slot onto an EMPTY cell
and it moves there, exactly, full stop; drag it onto an OCCUPIED cell and
the two swap (native Godot `Control` drag-and-drop, `ItemSlotButton.
draggable` opt-in so Fate Board/Abilities/Shop's own buttons are
unaffected). Real per-cell positioning (`InventoryScreen._slot_assignment`),
not a reordered list - two earlier versions got this wrong (insert-before-
target bumped every later slot down by one; a naive "empty means append"
fallback dragged every item between the source and the actual empty cell
along with it) before landing on real per-cell placement, both caught by
the user in play. Position is session-local (not saved - only ownership
is; a flagged gap, revisit if this needs to survive a reload).
`GameState.owned_loot`'s own array order is never touched by dragging at
all now - only which grid cell each entry renders in changes.
Only real drops are draggable - the directory-scanned "one of each base"
catalog always sits first and can't be picked up or targeted, since its
scan order isn't something the player actually owns to rearrange. **Brand
stacks**: identical Brands (fungible crafting currency, not unique rolled
gear - see Crafting above) group into one slot with a count ("Impel x3")
instead of one slot per drop, and drag as a whole block. Clicking a Brand
or crafting consumable in the grid no longer tries to equip it (both have
a meaningless leftover `equip_slot` default that, before this, silently
cleared whatever was actually equipped in that slot - a real bug, not
just a missing feature) - it shows a status message pointing at the
Crafting screen instead.

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
cast rolls the equipped Conduit's spell power within
`spell_power_min`..`spell_power_max` (`Weapon`/`Ability.roll_damage()`);
stats, motion value, chain bonus and crit apply on top. The old single
per-drop roll (`rolled_base_damage`/`rolled_spell_power`) is unused.
Weapon cards show "X Damage: min to max" (the range with the current
Strength multiplier, in a darker grey, per damage type present -
`ItemCard._build_attack_power_lines()`); spell cards show the same for a
cast (`Ability.predict_damage_range()`), or "requires a Conduit"; the
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
1. **Stat contribution** (Section 10's "Stats Per Tile": 0.6 Main
   Stat/tile keyed by the Slate's tag via `Constants.
   DAMAGE_TYPE_MAIN_STAT`, 0.3 Random Stat/tile, 5+ tile Slates only -
   v4.9 cut these from 1.7/0.8) sums across every PLACED Slate into
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
design decision. **`SlateRoller`** (mirrors `ItemRoller`/`BrandRoller`)
rolls all five of Section 10's axes - Tag, Shape (from a small invented
template pool, freely rotated/flipped at placement), Size (the doc's own
2-4/5-9/10-11 tile brackets, each with its own rarity band and design
identity), Modifier Count, and Modifier Values (the stat formula above is
deterministic per tile count, not randomized) - and drops as loot (10%
chance per kill, same flat-independent-roll convention as Tomes/Brands).

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
selecting one in the Crafting screen (`K`) shows an "Empower" action
(Gold-gated, `CraftingSystem.empower_figment()`) that raises its tier and
strengthens its rolls, making it harder on purpose. Leaving a Map is
manual (Pause menu's "Return to Hub," or death).

**Figments now have a boss, and killing it "completes" the Figment.**
`FigmentBoss` (`entities/enemies/figment_boss/`) is a from-scratch archetype
(no boss design exists anywhere in the doc - Section 24 flags "Boss
design philosophy" as undesigned there too) - roughly an 8x-health,
2.2x-damage, 10x-reward `HeavyHitter`, spawned in the Vault room's
platform slot (replacing the old reward `GlassCannon` there - "one Vault
per Map" already guarantees exactly one, making it the natural home for
the one guaranteed boss too). Its death fires `EventBus.figment_completed`,
which feeds Figment Tree points (see below).

**The boss has a real model now, not the placeholder capsule every other
enemy still uses** (2026-08-30, user-provided asset: "Arator the
Redeemer," a Warcraft III Reforged character pack dropped into
`assets/models/`). Godot has no native `.mdx` support, so a from-scratch
converter was built (`tools/mdx_pipeline/`, its own README has the full
technical writeup) using `war3-model` (an npm library that parses both
classic and Reforged MDX) to export geometry + a 144-bone skeleton +
skinning to `.glb`, which Godot imports natively. Materials are assigned
Godot-side rather than baked into the glTF - Godot already imports the
`.dds` textures natively and has `ORMMaterial3D`, a direct match for this
asset's Diffuse/Normal/Emissive/ORM packing - hardcoded to this specific
model's known 9-geoset order in `FigmentBoss.gd` (this model is a
composite rig merging pieces from other base Reforged models this project
has no textures for; those geosets get a flat gray placeholder instead,
same treatment as any other missing art here). `FigmentBoss._apply_mesh_
color()` overrides the base single-mesh telegraph-flash (Section 07's
attack-readability signal) to work across every real mesh on the model
instead. **The boss now animates** (2026-08-30) - all 13 of the model's
sequences are baked into the `.glb` (see the pipeline's own README for the
exact math), and `FigmentBoss.gd` drives 4 of them through the boss's real
combat state machine: an idle/walk blend off `Enemy`'s own chase velocity
(`Base`/`Walk 1`, looping), `Attack 1` on `begin_attack_telegraph()`
(alongside the inherited color-flash, not replacing it), and `Death 1`
played to completion before the base class's cleanup/`queue_free()` -
the one enemy in this project where dying doesn't happen instantly, since
it's the only one with a real death animation to show first. The other 9
sequences (Stand 2/3, Stand Ready 1, Stand Victory 1, Spell 1, Stand
Channel 1, Dissipate) have no real trigger in this project's current
combat model and are left unused rather than wired to something that
wouldn't be meaningful - every other enemy in this project is still
unanimated, so this remains the one exception, not a new baseline.

**Enemies also scale deterministically off the Map's own `tier`**
(`Enemy._apply_map_modifiers()`/`get_outgoing_damage_multiplier()`), on
top of the Figment's own `enemy_health_multiplier`/`enemy_damage_multiplier`
affixes. Those affixes are only a *probabilistic* bonus (`FigmentRoller`
doesn't guarantee either one rolls onto a given Figment), so two Tier 5
Figments could otherwise end up just as tough as two Tier 1 Figments by
chance alone — tier itself now always makes enemies tougher, harder-
hitting, and more rewarding (XP/Gold scale too). Invented growth curve
(+15% health/+10% damage/+20% XP+Gold per tier above 1) — not doc-
sourced, Section 24 defers Map/tier balance entirely.

**Enemy Rarity** (`entities/components/EnemyRarityComponent.gd`,
`data/enemies/EnemyAffix.gd`, Patch v3.9, 2026-09-06): a SECOND, fully
independent tier axis from `Constants.EnemyRank` above — Rank still
drives loot item-level exactly as before; Rarity (`NORMAL`/`ELITE`/
`CHAMPION`/`ASCENDANT`, spawn-weighted via `Constants.
ENEMY_RARITY_SPAWN_WEIGHTS`, rolled by `GeneratedMap._spawn_enemy_at()`)
drives health/damage multipliers (invented: 1.5x/1.2x, 3.0x/1.6x,
8.0x/2.4x for Elite/Champion/Ascendant), name color on the floating
health bar (blue/yellow/orange), and rolled `EnemyAffix` .tres resources
(`data/enemies/affixes/` — 4 starters seeded: `dreamer`, `pack_aggressive`,
`champion_aura_damage`, `ascendant_resilient`). Stat scaling is applied
from `Enemy._apply_map_modifiers()`/`get_outgoing_damage_multiplier()`,
not the component's own `_ready()` — the exact same child-before-parent
`_ready()` ordering bug this project has been bitten by before would
otherwise apply. Champion auras and drop-conversion tier/count scaling
are visual-placeholder/stub only; Ascendant still uses the regular
floating health bar, not the Boss-style one the doc describes (a real
gap, flagged in `PATCH_NOTES.md` — routing a non-Boss-rank enemy through
the singleton `BossHealthBar` slot needs a real answer for what happens
if a real Boss is also in combat, which nothing has specified yet).

**Figment Tree** (`systems/figment_tree/`) - scaffolding only, per direct
request ("prepare legs for a Figment Tree ... not "build it"). A real,
tested data model (`FigmentTreeNode`) and unlock/validation logic
(`FigmentTree.can_unlock()`/`unlock()`, spending `GameState.
figment_tree_points` - 1 point per completed Figment's tier, invented
rate) against 5 hand-authored stub nodes with prerequisite gating. No UI
screen exists to spend points through yet, and no node's `effect_key`
(e.g. `"figment_loot_quantity"`) is wired into `FigmentRoller` or loot
generation - both explicitly left for a future pass.

**Shops** (`entities/interactables/gear_shop/`,
`entities/interactables/spell_test_shop/`,
`entities/interactables/brand_shop/`, `ui/shop/ShopScreen.gd`): three Hub
interactables, same walk-up-and-`E` pattern as the Reality Engine.
**GearShop** sells 6 `ItemRoller`-rolled items per Hub visit for Gold (a
brand-new invented currency — see gap below), cost scaled by rolled
rarity, plus a "Reroll Stock" action button (invented `15` Gold) to
refresh the offered items on demand without leaving. **SpellTestShop**
lists every ability under `data/abilities/instances/` for free — an
explicit testing/debug tool (user-requested), not a designed economy
feature, so you can unlock everything without grinding Tome drops while
testing other systems. **BrandShop** (2026-09-06, dev/testing convenience)
sells all 26 real Brands (`Constants.BRAND_RARITIES`) for Gold, priced by
rarity tier (Common 50/Uncommon 200/Rare 800), unlimited quantity — every
row stays buyable after a purchase instead of the normal one-and-done
disable, via a `"repeatable"` entry flag `ShopScreen` now supports. All
three share one generic `ShopScreen` (caller supplies the entries + a buy
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
exclusives — transcribed directly from the Patch v3.9 doc's own Tier-1
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
`GameState.owned_loot` (persisted, including full data for pathless
rolled items — see Save/Load below) and shows up in `InventoryScreen`'s
grid, fully equippable and now safe to keep equipped across scene
transitions/saves; a Tome unlocks its ability into
`GameState.owned_ability_ids` and shows up in `AbilitiesScreen`.

**Crafting** (`systems/crafting/CraftingSystem.gd`, `ui/crafting/`,
`data/brands/`, `K`, Section 20): the doc's three distinct crafting
methods, all real. **The Cube**: place one owned item + up to 8 Brands
(this project's uniform 1x1 inventory means every item costs exactly one
of the 3x3 grid's 9 cells), hit Craft. **Can't queue more of a Brand than
you actually own** (2026-08-30 bug fix, user report: "I only have one of
a brand but I can add it multiple times") - the palette's one button per
Brand type used to queue the SAME representative owned object on every
click, which let `CraftingSystem.MAX_SAME_BRAND`'s per-craft cap of 2
silently over-consume (crafting with "2 queued" while only 1 was ever
actually owned, since the second reference never matched a second real
object at consumption time) - fixed by queuing genuinely distinct owned
objects instead. **Owned Items and Consumables now show a real hover
card** too (2026-08-30, user-reported gap) - both were previously either
a plain `Button`/`Label` with no tooltip at all, now `ItemSlotButton`
like everywhere else in this project's UI. 24 of the doc's ~29 named Brands
exist (all 9 Damage Type, all 5 Defensive Type, all 4 Umbrella, all 6
Crafting Utility, plus Binder/Rectify from Special/Rare — Facsimile/
Amalgam/Imbue are cut, see gap below), dropped as loot only
(`BrandRoller.gd`, same flat-chance convention as Skill Tomes). A Damage/
Defensive/Umbrella Brand alone adds one new modifier weighted toward its
category (reusing `ItemRoller.AFFIX_POOL`, now tagged per category — see
gap below for which categories are still descriptive-only). **Clicking
any Brand previews what it can actually do** to the selected item before
you commit it to the Cube - for a category Brand, the real list pulled
from `ItemRoller._pool_for_brand_tag()` (the exact pool a craft would
roll against, so the preview can never promise something a craft
wouldn't produce); for a Utility/Special Brand (no pool to roll from,
just a fixed action), its function description instead. Render/
Refine/Cleave/Excise/Bore/Sever do their doc-described thing for real
(Cleave locks one modifier and risks destroying the item on a second use;
Sever, combined with a category Brand, permanently seals that tag from
ever rolling on the item again); Binder exempts every other Brand in the
craft from consumption. **Infusion/Shrivening Stone**: reroll or clear a
weapon's `infused_damage_type` (the field already existed, unused, before
this). **Rarity now updates live as you craft** (Patch v3.9,
`CraftingSystem._update_item_rarity()`, called once per successful
`craft_cube()`) — 0 affixes white/Common, 1-2 blue/Uncommon, 3+ yellow/
Rare, recomputed after every add/remove/reroll; Unique/Mythic/corrupted
items never reclassify. `EventBus.item_rarity_changed` keeps a hovered
item's `ItemCard` border/title color live through the craft instead of
only updating on the next hover.

**Named Brand combinations** (Patch v3.6, `systems/crafting/
BrandCombinationResolver.gd`): placing specific Brand pairs/triples
together now rolls from a deliberately combined pool instead of just
diluting the odds between separately-weighted tags — Anneal+Attenuate
pulls from the combined armor+evasion pool, Calcine+Galvanic+Quench from
fire+cold+lightning, and so on for 7 pairs and 5 triples. Same Brand x3
also caps the roll at Tier 3 or better (this project's Tier 1 is always
best). Any other combination still falls back to the original weighted-
any-present-tag pick, unchanged.

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
explicit modifier, once per item. Every corruption attempt still also
rolls the doc's "chance to retain craftable/corruptible status," which
can permanently lock an item out of any further Cube craft or
corruption — kept from the previous implementation alongside the new
tier model, not replaced by it.

**Slate Affix Pool** (Patch v3.6, new — `data/items/SlateAffix.gd`,
`systems/crafting/SlateAffixPool.gd`, `data/slates/affix_pool/`): a
tag-organized pool of rollable Slate modifiers, entirely separate from
gear's own `ItemRoller.AFFIX_POOL` — the only crossover is Veiltouch
above. Currently 36 hand-generated stubs (3 per tag × 12 tags: the 9 real
damage types plus spell/attack/generic), not real design — scaffolding
for a future procedural Slate-affix roll. Hand-authored Slates still use
their own fixed `SlateModifier` list, untouched by any of this.

Every probability/priority-order choice below the doc's own named
mechanics is still this project's invented placeholder (Section 24
explicitly defers "Cube combination rules," "Brand rarity tiers," and
"Corruption probability distribution" to a future design pass) — Patch
v3.6 is exactly that pass for the Cube's own combination rules and
Corruption's own outcome model specifically, everything else flagged
below is still open.

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
above, 2026-08-30 fix), ability loadout + ranks, player level/XP, Gold,
unlocked ability ids, and settings — not current Health/Ward/Mana,
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
| Weapon stance (hold) - preps a special melee attack or aims (ranged) | Right Mouse |
| Cast equipped ability (slot 1-4) - hold + release to aim for Comet/Inferno/Stormcall | 1 / 2 / 3 / 4 |
| Pause menu (Resume / Return to Hub / Quit) | Esc |
| Return to Hub directly (no pause menu needed) | T |
| Open Fate Board directly | P |
| Open Inventory directly | B |
| Open Abilities (equip/upgrade) directly | N |
| Open Character Screen directly | C |
| Open Map Screen directly | M |
| Open Crafting (The Cube) directly | K |
| Rotate pending Slate *(Fate Board editor only)* | R |
| Flip pending Slate *(Fate Board editor only)* | Q |
| Interact *(Reality Engine, Hub only)* | E |

P/B/N/C/M/K work from anywhere — gameplay, the pause menu, or another such
screen — and jump straight to their target, closing whatever else was
open. Pressing the same key again while already on that screen closes it.
None of the six have a `PauseMenu` button — hotkey-only.

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
3. **First-person melee weight** (Pillar 2): camera shake + hitstop +
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
11. **Reality Engine / Hub scope cuts**: a real Figment-selection UI now
    exists (reuses `ShopScreen` - see the Hub section above), but leaving
    a Map is still always manual, not triggered by clearing enemies or
    completing the boss (killing the boss only fires
    `EventBus.figment_completed` for Figment Tree points - it doesn't
    end the run); Settings has exactly three real options. Master volume
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
    range's midpoint otherwise) - Conduits got the same treatment for
    `spell_power_min`/`max`/`rolled_spell_power`, the base floor a
    Conduit contributes to spell damage (`StatSheet.conduit_spell_power`,
    recomputed whenever the equipped primary weapon changes). The Crafting pass
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
25. **Crafting's Cube combination rules and Corruption probabilities are
    entirely invented** — Section 24 ("Deferred Design") explicitly says
    so itself ("Cube combination rules — how many Brands per combination,
    fixed vs variable slots," "Corruption probability distribution —
    outcome weightings," "Maximum modifier count per item — balance
    dependent" are all listed there as not yet designed, not just missed
    by this project). `CraftingSystem.FUNCTION_PRIORITY` (which Brand
    function governs a craft when several are placed together),
    `MAX_AFFIXES` (6, reusing Section 18's own "Rare: 0-6" ceiling),
    `CLEAVE_DESTROY_CHANCE`/`SEVER_UNDO_CHANCE`/`REFINE_BOOST_PERCENT`/
    `RETAIN_CRAFTABLE_CHANCE`, and `CORRUPTION_OUTCOMES`' weights are all
    this project's own placeholders for those specific gaps. Facsimile
    (item duplication), Amalgam (merging two items' mods), and Imbue (a
    new "powerful implicit" pool) are cut from the Special/Rare Brand
    list — each is its own separate mechanic with no natural home in the
    systems this pass touches. Vestiges (boss-exclusive mod pools) aren't
    modeled — this project has no boss encounters to drop one. Corruption
    and Bore both touch `Item.max_sockets`, but per gap #21 nothing can
    actually be socketed into it yet. Brand rarity/drop weighting is real
    now (Patch v3.5, `Constants.BrandRarity`/`BRAND_DROP_WEIGHTS`,
    `BrandRoller.roll()`) — Brands used to drop uniformly regardless of
    power. `ItemAffix` also grew prefix/suffix/implicit-count helpers and
    `is_generic`/`damage_type` fields (`Item.get_prefix_count()` etc.,
    `StatSheet.apply_affix()`) as pure data scaffolding for a future
    Cube/`ItemRoller` pass — nothing generates or reads these new fields
    yet, same "shape only" footing as the rest of this list.
26. **Inventory slot arrangement doesn't survive a save/reload** -
    `InventoryScreen._slot_assignment` (which grid cell each item/Brand
    stack renders in) lives on the screen instance itself, not
    `GameState`, so it resets whenever the scene reloads (returning to
    Hub, entering a Map, loading a save). `GameState.owned_loot` - actual
    *ownership* - is unaffected and still persists exactly as before;
    only the player's chosen layout is session-local. Not requested, and
    keying a persistent version to something stable across a save's
    item-reconstruction (`ItemSerializer.from_dict()` builds fresh
    Resource objects with new instance ids every load) would need a real
    per-item save-stable id that doesn't exist yet - flagged rather than
    guessed at.
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
    since nothing else asked for it and Enemy's existing `_base_color`
    hook is already spoken for by archetype identity + attack telegraphs.
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
31. **`levels/pinnacle_boss/PinnacleArena.tscn` exists but isn't wired
    into the game anywhere yet** - a Belial-style crescent arena (user
    request 2026-08-30), built and verified (crescent shape confirmed by
    screenshot, invisible boundary collision confirmed by a scratch
    physics test - see `PATCH_NOTES.md`), but there's no boss encounter,
    no Map/Hub entry point, and no way to reach it from normal play. First
    use of `CSGShape3D` in the project (every other level's floor is a
    simple plane/box) - a crescent/lune shape isn't expressible with the
    usual approach. `BossSpawnPoint`/`PlayerSpawnPoint` are bare
    `Marker3D`s for a future pass to read.
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
pool + dodge-roll/Active-Blocking mechanic (Instinct's per-point Stamina
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
11 effects. Crafting (`CraftingSystem`, flagged gap #25) now exists too -
The Cube, Infusion/Shrivening Stone, and Shard of Tharsis are all real,
minus Facsimile/Amalgam/Imbue and Vestiges (no boss encounters to drop one).

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
