# Claude Code Brief — Wire Blender melee models into the viewmodel

## Goal
Every melee weapon type uses its Blender-built `.glb` in first person instead of the Kickin It pack FBX or the primitive builders. If a `.glb` is missing, fall back to the current model.

## What already exists
- `assets/models/weapons/*.glb`: 17 weapon types plus left-hand variants of the 3 gauntlets (23 files).
- `assets/models/weapons/weapons_manifest.json`: one entry per file with `file`, `weapon_type`, `family`, `hide_hand`, and `offhand_grip` (on two-handers only, already in Godot grip-space coordinates).
- `tools/blender/build_melee_weapons.py`: the source script. Re-running it in Blender rebuilds and re-exports every model and the manifest.
- `entities/player/viewmodel/WeaponModelLibrary.gd` already has `AETHER_MODEL`, `AETHER_MELEE` (Mace, War Pick, Rapier only) and `_mount_aether()`. Build on this; don't add a second loader.

## Conventions baked into every .glb
- The models are already in grip space: origin = the closed hand, tip along +Y, face along +Z, strike side along +X. Mount them under `inner` with an identity transform, and don't apply `FORWARD_TO_TIP`.
- Gauntlets are authored in grip space too. For them, `forward_authored` must be false.
- Two-handers also contain an empty node whose name starts with `offhand_grip`. The manifest value is the source of truth; the node is only a visual check.
- Material `accent` is a placeholder glow. Override it per weapon with the damage-type glow (`Constants.DAMAGE_TYPE_COLOR`, the same as `_glow()`).
- Orbs (Staff, Wand, Spell Gauntlet) and glow rings (Shock Lance) are part of the mesh. Skip the `PACK_ORB` / `_glow_orb` additions when a `.glb` is mounted.

## Tasks
1. Load `weapons_manifest.json` once (cached in a static var) and build the type → entry lookup from it, replacing the hard-coded `AETHER_MELEE` dict.
2. In `build()`, any type found in the manifest whose file exists → `_mount_aether`. Set the `offhand_grip` meta from the manifest and `hide_hand` when it's true.
3. `build_left_gauntlet()` → mount the matching `*_left.glb` when it exists. It's keyed in the manifest as `"<type> (left)"`.
4. In `_mount_aether`, replace any material named `accent` on each surface with `_glow(accent_color)`. Keep cast shadows off.
5. Don't change `FAMILY`, the PlayerArmRig clips or the pack fallback paths.

## Check in the TestArena
- Equip each type and check: the hand sits on the grip, the blade points along the swing, and two-handers put the left hand on the second grip.
- Fist weapons: no duplicate hand, and the left gauntlet appears.
- Glow parts take the weapon's damage-type colour.
- Report any weapon that reads as too big or too small in first person. Fix sizes in the Blender script and re-export, not with code-side scale fudges.
