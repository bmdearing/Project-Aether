# Patch Notes

Chronological log of what changed and why — bugs found, root causes,
judgment calls made without stopping to ask. `README.md` describes the
project as it stands today; this file is the history of how it got
there. Most recent first.

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
