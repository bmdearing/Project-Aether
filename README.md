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
Normal attacks cycle through per-weapon swing types
(`WEAPON_TYPE_COMBO_POSES`) so repeated attacks read as a combo instead
of the same cut every time - Greatsword alternates two horizontal sweeps
only (no diagonal mixed in, so it reads as one consistent windmill, not
two unrelated motions), anything else gets a 3-pose diagonal+horizontal
mix. Swing timing/arc size are both per-weapon-type
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
Pressing Attack while active fires `PlayerMeleeAttack.try_special_attack()`
instead of a normal swing - a bigger, slower, harder-hitting version of
the swing (1.8x motion value, 1.4x duration, 1.1x arc) using a
weapon-specific pose (`WEAPON_TYPE_SPECIAL_POSE`): Greatsword gets an
exaggerated horizontal `BIG_SWEEP`, Dagger gets a `DASH_THRUST` that also
fires a real forward `Player.try_special_dash()` (sharing the same
dash state/cooldown as the Shift-tap dash, not a separate free resource)
before the stab lands. Ranged weapons aim instead - the camera FOV zooms
in while held, and firing while aimed deals 1.4x damage (no
spread/accuracy system exists to tighten instead). `StanceComponent.gd`
is unrelated - that's an enemy poise/posture bar, not this.

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
Kinetic, and a `flat_enigma` implicit instead of crit chance, so
equipping it both hits harder for its own damage type AND raises the
Enigma that scales Esoteric spells - through the existing generic
`flat_<stat>` affix system, which already sums from whichever weapon
slot an item sits in, no new "conduit" mechanic needed). Every melee type
now has a genuinely distinct swing/punch/thrust pose, not just a scaled
copy of another weapon's motion (`PlayerMeleeAttack.
WEAPON_TYPE_COMBO_POSES`/`WEAPON_TYPE_SPECIAL_POSE`), and ranged weapons
finally have a fire-reaction animation too (`PlayerRangedAttack.
_play_fire_animation()`, cosmetic only - doesn't touch the instant-fire
timing). Real 3D models exist for Greatsword/Dagger/Bow/Staff
(`Player.WEAPON_MODEL_SCENES`, from the same purchased low-poly pack);
Service Pistol/Rapier/Gauntlet have no matching model in that pack and
fall back to the tinted placeholder box. No caster weapon that gates an
innate *ability* exists yet, and spellcasting itself remains entirely
independent of the weapon slot - Gauntlet boosts spell damage by raising
a stat, it doesn't grant or modify which spells you can cast. A `StatSheet`
(Vitality/Strength/Instinct/Arcane/Enigma/Intellect) — **all six now drive
something** (Section 12's Per-Point Values table): Strength/Arcane/Enigma
scale Physical/Elemental/Esoteric damage two ways at once, both doc-sourced
and both stacking — as the "Main Stat" (`Constants.DAMAGE_TYPE_MAIN_STAT`,
Section 10), their raw point value multiplies directly into
`DamageCalculator`'s Stat Scaling Grade term, **and** separately, per
Section 12's own Per-Point Values table, each point is also worth a flat
+1% increased damage of that same category (`Weapon`/`Ability._base_hit()`
folds `stat_value` straight into the `increased_percents` pool at 1:1) —
this second piece was documented in `Constants.STAT_GLOSSARY` from early
on but never actually wired up until a user report that these stats
weren't giving the "% increased damage… not a high amount" the doc
describes (2026-08-30 fix). Vitality raises max Health + Life regen;
Instinct raises Crit Chance + Attack/Cast/Move speed; Intellect raises
Crit Damage + max Mana + Mana regen. Per Section 12 ("all stats come from
gear... no manual allocation on level up"), stats only grow from equipped
gear now — `EquipmentComponent.compute_stat_bonuses()` sums every equipped
item's `flat_<stat>` affixes into `StatSheet.equipment_bonus`, recomputed
on every equip/unequip.

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

**Combat formula** (`systems/combat/DamageCalculator.gd`): implements the
Section 11 formula (`Base Damage x Motion Value x Stat Value x Scaling-Grade
Fraction x Mastery x Increased% x More multipliers`), now followed by a
**Critical Strike System** (also Section 11, doc-exact numbers): base crit
chance is fixed per weapon/spell type (`Constants.WEAPON_BASE_CRIT_CHANCE`,
2%-8%), multiplied by Instinct; a crit deals 150% damage, multiplied by
Intellect. `Weapon`/`Ability` each expose `predict_damage()` (an
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
- **Flame Jets** is a timed channel (not ground-targeted) that re-aims at
  wherever the camera is CURRENTLY looking every tick and slows the
  player to 0.4x movement speed for the channel's duration.
- **Winter's Eye** launches a slow orb toward the target point that
  ticks proximity Cold damage + Chill to nearby enemies as it travels
  (an approximation of "a spiral of icicles" - ticks, not literal spawned
  sub-projectiles), then detonates for a burst hit on arrival.
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
per `Constants.STATUS_EFFECT_DAMAGE_TYPE`). Vitality's Resilience/DoT
mitigation and Intellect's Debuff effectiveness (Section 12) are wired
through it too — Resilience reduces Ignite's tick damage, the applying
side's Intellect extends Chill/Electrocute/Unraveling's duration. Stunned
targets have their `EnemyMeleeAttack`/`EnemyRangedAttack` state machine
paused (Enemy side) or lose jump/parry/attack input (Player side). Active
effects show as a colored chip row top-left on `PlayerHUD` and as small
floating dots above an Enemy's head. Bleed/Armor Shred/Stagger-Stun and
Scorch/Aetherburn/Pallid aren't modeled yet — see gaps below.

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

Holding **Alt** while hovering opens an *advanced* card instead
(`AdvancedTooltip.gd`) — a real HOLD now (matches Path of Exile's actual
behavior, confirmed by request before redesigning this): release Alt and
it closes, same as every other hold-modifier in this project, unless the
mouse has moved onto the card itself (still reading/clicking through it),
in which case it closes once the mouse leaves the card instead. The
previous version stayed pinned open until Esc/outside-click regardless of
Alt, which read as sticky/unintuitive - user-reported. Rolled affixes
show their full tier range, and stat keywords are clickable, printing
that stat's Section 12 per-point value inline. Weapon/ability cards
include a live "Predicted Damage" number computed from the player's
current stats (`Weapon.predict_damage()`/`Ability.predict_damage()` — the
exact formula real attacks/casts use, so the number can't drift from
reality).

**Fate Board** (`systems/fate_board/`, `ui/fate_board_editor/`, Section
10): grid Slate placement gated by an Aether budget, flood-fill chain
detection with tiered bonuses (`Constants.CHAIN_BONUS_TIERS`, doc-exact).
UI is a bounded 32x32 window (not the doc's "effectively unlimited"
board), opens with `P`. The palette shows the hand-authored
`data/slates/instances/` samples (11 now - see below) as an always-
available catalog, plus every real `SlateRoller` drop in
`GameState.owned_slates` - those are finite: placing one removes it from
the palette until it's pulled back off the board.

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

**Slates now do something** - three real, mechanical pathways out of the
Fate Board, all landing on `StatSheet` and consumed by the existing
damage formula with no changes needed there:
1. **Stat contribution** (Section 10's "Stats Per Tile" - doc-exact: 1.7
   Main Stat/tile keyed by the Slate's tag via the same
   `Constants.DAMAGE_TYPE_MAIN_STAT` table weapons/abilities already
   scale against, 0.8 Random Stat/tile, 5+ tile Slates only) sums across
   every PLACED Slate into `StatSheet.slate_bonus`, same channel gear's
   `flat_<stat>` affixes already use.
2. **Mastery** (Section 10/23: "tag-specific... multiplying weapon
   scaling grade effectiveness for that tag") is granted by a Slate's own
   "mastery" modifier. `StatSheet.mastery_by_tag` existed and was already
   read by `Weapon`/`Ability` damage rolls since early in this project -
   nothing had ever populated it until now.
3. **Chain Bonus** amplifies by Mastery (`ChainCalculator.
   amplify_by_mastery()` - "Mastery... multiplying the per-tile chain
   bonus rate") and the result feeds `Weapon`/`Ability._base_hit()`'s
   `increased_percents` as real "increased damage" for that tag's
   category - the same formula parameter every damage roll already
   accepted but nothing had ever passed anything into before this.

Whether a Slate's own stat rolls should ALSO be chain-amplified is
explicitly unresolved in Section 10 itself ("deferred pending balance
evaluation") - not implemented, matching that stated deferral rather
than guessing. **`SlateRoller`** (mirrors `ItemRoller`/`BrandRoller`)
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
`entities/interactables/spell_test_shop/`, `ui/shop/ShopScreen.gd`): two
more Hub interactables, same walk-up-and-`E` pattern as the Reality Engine.
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
`flat_<stat>` affixes (Vitality/Strength/Instinct/Arcane/Enigma/
Intellect) are real now, not descriptive-only — they're the only source
of stat growth in the game (see Player section above); `flat_ward` and
the 4 `*_resistance_pct` affixes are real too as of Patch v3.2 (Ward
pool size, Resistance mitigation - see the Combat formula section
above); the damage/armor increased-% affixes are still descriptive-only
(see flagged gap).
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
this). **Shard of Tharsis**: corrupts an item per Section 20's own
"Possible Corruption Outcomes" list (new modifier, rerolled ranges,
sockets added/removed, etc.) — every corruption attempt also rolls the
doc's "chance to retain craftable/corruptible status," which can
permanently lock an item out of any further Cube craft or corruption.
Every probability/priority-order choice below the doc's own named
mechanics is this project's invented placeholder (Section 24 explicitly
defers "Cube combination rules," "Brand rarity tiers," and "Corruption
probability distribution" to a future design pass) — see flagged gap.

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
than jumping straight to a smaller-looking ratio - a Gold counter, and an
active-weapon indicator that flashes whenever the equipped weapon
changes),
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
    `StatusEffectComponent` (Ignite/Chill/Freeze/Electrocute/Unraveling,
    Section 09) - `PlayerAbilityCast._cast()` applies each ability's
    listed effect(s) to every enemy it hits.
13. **Figments have no doc-sourced affix table** (none could exist - this
    whole system is invented, not doc content at all) — the affix pool
    and tier curve (`FigmentRoller.gd`) are invented throughout, including
    the drop-scaling curve (`roll_for_drop()`) and the Empower Gold cost
    (`CraftingSystem.EMPOWER_FIGMENT_GOLD_COST`). Selection/inspection UI
    is real now (see the Hub section above) - this gap is narrower than
    it used to be.
14. **Vitality's Resilience/DoT mitigation and Intellect's Debuff
    effectiveness are now wired** (`Player.get_dot_mitigation()` /
    `DamageCalculator.dot_mitigation()`, and
    `StatusEffectComponent._debuff_effectiveness_multiplier()`
    respectively - see `StatusEffectComponent`), now that a real DoT/
    debuff system (status effects) exists for them to modify. **Instinct's
    Stamina pool + dodge-roll/Active-Blocking is still NOT wired** - no
    Stamina/dodge/block-charge mechanic exists. Strength's Stagger
    effect/Stun Recovery are similarly unwired - no stagger/stun-duration
    mechanic exists (Electrocute/Freeze's stun is currently a flat,
    invented duration, not modified by either stat).
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
    own `WEAPON_TYPE_META` table. Each tier's doc "Implicit" text is
    folded into `flavor_text` as flavor rather than a real `ItemAffix` -
    `ItemRoller.roll()` always wipes and re-rolls `affixes` on every roll
    regardless of base, so a "persistent implicit" affix would never
    survive a roll anyway (same pre-existing behavior every hand-authored
    base's own implicit already had). `flat_<stat>` roll affixes are real
    (summed into `StatSheet` - see the Player section above), and
    `flat_ward`/the 4 Resistance affixes joined them as of Patch v3.2, but
    the damage/armor increased-% affixes (`physical_dmg_increased`,
    `flat_armor`, etc.) are still descriptive-only — no aggregation of
    those into the damage/armor formulas exists yet. The Crafting pass
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
    actually be socketed into it yet.
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
    Stats Per Tile formula (1.7/0.8/2.5), Main Stat by Tag table, and
    Slate Size/Rarity brackets are all doc-exact and transcribed
    verbatim; everything `SlateRoller` decides beyond those (which shape
    template within a size bracket, Hybrid chance, Mastery's value range
    and how often a 5+ tile Slate additionally rolls one, Aether cost)
    has no doc-sourced formula - Section 10 states the mechanics and
    axes, not their exact acquisition curve, same "Deferred Design"
    pattern as Crafting (gap #25). Two specific interpretive calls worth
    flagging on their own: **(a)** a Slate's own "mastery" modifier grants
    Mastery to its primary tag only, even on a Hybrid Slate - the doc's
    "full bonus to both" wording for Hybrids describes chain-EXTENSION
    specifically (Section 10), not a Slate's own static modifier lines,
    which the doc doesn't address either way. **(b)** Chain Bonus's own
    output (after Mastery amplification) is treated as "increased damage"
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
