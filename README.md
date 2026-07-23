# Project Aether — Godot Scaffold

Vertical Slice Brief v0.1 scaffold. Godot 4.3, GDScript, 2D (top-down)
placeholder rendering — no art yet by design, per the "Endgame First" /
"Start Minimal" philosophy in the World & Design Document.

## What's implemented (functional, untested in-editor)

- **Autoloads**: `Constants` (damage types, stats, chain bonus tiers, scaling
  ranges), `EventBus` (global signals), `GameState` (session state)
- **Fate Board**: `FateBoard.gd` (grid placement + Aether budget) and
  `ChainCalculator.gd` (flood-fill chain detection + tiered bonus math)
- **Slate data model**: `Slate.gd` + `SlateModifier.gd`, with two hand-authored
  instances (`sample_entropic_slate.tres`, `unbound_chorus.tres`)
- **Combat loop**: `StanceComponent`, `ComposureComponent`,
  `ParryRiposteHandler`, `DamageCalculator` (full Section 11 formula)
- **Entities**: `Player` + `Enemy` base with three Trinity Rule archetype
  subclasses (GlassCannon, MobileBruiser, HeavyHitter)
- **Debug overlay**: numeric readout of Aether budget, chain bonuses, damage
  dealt — no art needed to validate formulas

## Flagged design gaps (need your call, not resolved unilaterally)

1. **Chain scoping**: `ChainCalculator` assumes chains are computed *per tag*
   (same-tag adjacency), since Mastery is explicitly tag-specific and Hybrid
   Slates "bridge two chains." The World Doc doesn't say this outright —
   flagging the interpretation before more systems depend on it.
2. **Non-damage-type Slate tags**: "The Unbound Chorus" has Tag: Spell, which
   isn't one of the 9 damage types. Added `category_tag_override` on `Slate`
   as a stopgap rather than inventing a tag taxonomy.
3. **Ward restore-on-parry ratio**: World Doc defers the Ward numerical
   formula to playtesting. `WardComponent.restore_on_parry_success()` uses a
   placeholder 15% of max Ward — clearly marked, needs your number.
4. **Stance depletion weights** by damage category are approximated
   (Physical 1.0 / Elemental 0.6 / Esoteric 0.35) since the doc gives ordinal
   guidance (Blunt/Explosive strong, ranged moderate, Occult/Spell weakest)
   but no numbers.

## Explicitly not built yet (per Vertical Slice Brief scope)

Crafting (Cube/Brands/Corruption), procedural loot rolling, full 9-damage-type
coverage, Jewelry/Gems/Sockets, co-op.

## Opening this project

1. Install Godot 4.3+ (this scaffold targets the GL Compatibility renderer
   for broad hardware support during prototyping).
2. Open `project.godot` from the Godot project manager.
3. Run scene: `levels/test_arena/TestArena.tscn` (set as main scene).
4. WASD to move, Space to open a Parry window (no attacker AI wired yet —
   next Claude Code pass should add a basic enemy attack + telegraph so the
   Parry window has something to react to).

## Suggested next Claude Code session

1. Wire one enemy attack (telegraph → hitbox → `attempt_parry` check) so the
   Parry → Stance → Composure Break → Riposte loop is actually playable.
2. Populate `data/abilities/instances/` with the 3-4 abilities from the brief
   (recommend Ice Pulse, Comet, Frost Armor as a coherent Cold kit).
3. Build the Fate Board placement UI in `ui/fate_board_editor/` on top of the
   already-functional `FateBoard`/`ChainCalculator` logic.
4. Add 5-8 more hand-authored `.tres` Slates following the pattern in
   `sample_entropic_slate.tres`.
