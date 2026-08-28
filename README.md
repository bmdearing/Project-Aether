# Project Aether — Godot Scaffold (v0.2, First-Person)

Vertical Slice Brief v0.1 scaffold. Godot 4.3, GDScript, **true first-person
3D** (Borderlands-style: camera in head, no visible player body, weapon
socket for a future viewmodel).

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
- **Fate Board**: `FateBoard.gd` (grid placement + Aether budget) and
  `ChainCalculator.gd` (flood-fill chain detection + tiered bonus math)
- **Slate data model**: `Slate.gd` + `SlateModifier.gd`, with two
  hand-authored instances (`sample_entropic_slate.tres`, `unbound_chorus.tres`)
- **Combat loop**: `StanceComponent`, `ComposureComponent`,
  `ParryRiposteHandler`, `DamageCalculator` (full Section 11 formula) — all
  camera-agnostic
- **Entities**: `Player` (first-person) + `Enemy` base with three Trinity
  Rule archetype subclasses, each a distinct colored capsule (yellow Glass
  Cannon, blue Mobile Bruiser, dark red Heavy Hitter) as placeholder visuals
- **Debug overlay**: numeric readout of Aether budget, chain bonuses, damage
  dealt — no art needed to validate formulas

## Controls (current bindings)

| Action | Key |
|---|---|
| Move | WASD |
| Look | Mouse |
| Sprint | Shift |
| Jump | Space |
| Parry | F |
| Attack (unwired) | Left Mouse |
| Release/recapture mouse | Esc |

## Flagged design gaps (need your call, not resolved unilaterally)

1. **Chain scoping**: `ChainCalculator` assumes chains are computed *per tag*
   (same-tag adjacency), since Mastery is explicitly tag-specific and Hybrid
   Slates "bridge two chains." The World Doc doesn't say this outright.
2. **Non-damage-type Slate tags**: "The Unbound Chorus" has Tag: Spell, which
   isn't one of the 9 damage types. Added `category_tag_override` on `Slate`
   as a stopgap rather than inventing a tag taxonomy.
3. **Ward restore-on-parry ratio**: placeholder 15% of max Ward — the World
   Doc explicitly defers this number to playtesting.
4. **Stance depletion weights** by damage category are approximated
   (Physical 1.0 / Elemental 0.6 / Esoteric 0.35) from ordinal guidance only.
5. **New, first-person-specific gap**: how melee "weight" (Pillar 2) reads in
   first-person without a visible body is unresolved — likely camera shake +
   hitstop + viewmodel animation once art exists, but the vertical slice has
   none of that wired yet. Worth a design pass before the next combat task.

## Explicitly not built yet (per Vertical Slice Brief scope)

Crafting (Cube/Brands/Corruption), procedural loot rolling, full 9-damage-type
coverage, Jewelry/Gems/Sockets, co-op, enemy AI (enemies are static dummies),
viewmodel/weapon visuals, attack input handling.

## Opening this project

1. Install Godot 4.3+ (GL Compatibility renderer for broad hardware support
   during prototyping).
2. Open `project.godot` from the Godot project manager.
3. Run scene: `levels/test_arena/TestArena.tscn` (already set as main scene).
4. You should see a floor plane, three colored capsules (enemies) ahead of
   the player's starting position, and be able to walk/look around
   immediately — mouse is captured on scene start.

## Suggested next Claude Code session

1. Wire one enemy attack (telegraph → hitbox → `attempt_parry` check) so the
   Parry → Stance → Composure Break → Riposte loop is actually playable. In
   first-person, "telegraph" likely means a visual/audio cue plus maybe a
   camera-space reticle change, since the player can't see the enemy's full
   body wind-up the way third-person Bloodborne combat reads tells.
2. Resolve flagged gap #5 above before building much more combat feel —
   worth a short design conversation on how melee weight communicates in
   first-person.
3. Populate `data/abilities/instances/` with the 3-4 abilities from the
   brief (recommend Ice Pulse, Comet, Frost Armor as a coherent Cold kit).
4. Build the Fate Board placement UI in `ui/fate_board_editor/` on top of the
   already-functional `FateBoard`/`ChainCalculator` logic — this will be a
   2D/UI overlay regardless of the 3D world, likely a pause-menu screen.
5. Add 5-8 more hand-authored `.tres` Slates following the pattern in
   `sample_entropic_slate.tres`.
