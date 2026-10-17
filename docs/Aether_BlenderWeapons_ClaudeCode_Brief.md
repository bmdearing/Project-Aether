# Claude Code Brief — Wire Blender weapon models into the viewmodel

## Goal
Every weapon type uses its Blender-built `.glb` in first person instead of the Kickin It pack FBX or the primitive builders in `WeaponModelLibrary`. If a `.glb` is missing, fall back to the current model.

## What already exists
- `assets/models/weapons/*.glb`: 50 files.
  - Melee (17): Mace, War Pick, Rapier, Shortsword, Saber, Cutlass, Dagger, Athame, Greatsword, Claymore, Greataxe, Spear, Shock Lance, Halberd, Staff, Whip, Wand.
  - Fist (3, plus a left-hand variant of each): Gauntlet, Pressure Fist, Spell Gauntlet.
  - Ranged (14): Service Pistol, Revolver, Machine Pistol, Submachine Gun, Battle Rifle, Bolt Action Rifle, Lever Action Rifle, Machine Gun, Pump Action Shotgun, Loaded Shotgun, Crossbow, Bow, Longbow, Shortbow.
  - Off-hand foci (5): Rod, Tome, Grimoire, Fetish, Talisman. Family `focus`, keyed by `weapon_type`.
  - Shields (8): `shield_<base>.glb` for buckler, kite, tower, great, spiked, rune, warded, pavise. Family `shield`. Their manifest `weapon_type` holds the base name, which is the same value `build_offhand` takes from `base_line_id.get_slice("_", 0)`.
  - The Infusion Grenade is intentionally not built yet.
- `assets/models/weapons/weapons_manifest.json`: one entry per file. Every entry has `file`, `weapon_type`, `family` and `hide_hand`. Entries also have whichever of these markers apply: `offhand_grip`, `muzzle`, `bow_tip_top`, `bow_tip_bottom`. All marker values are already in Godot grip-space coordinates.
- `tools/blender/build_melee_weapons.py`: the source script for all 37. Re-running it in Blender rebuilds and re-exports every model and the manifest.
- `entities/player/viewmodel/WeaponModelLibrary.gd` already has `AETHER_MODEL`, `AETHER_MELEE` (Mace, War Pick, Rapier only) and `_mount_aether()`. Build on this; don't add a second loader.

## Conventions baked into every .glb
- Every model, including guns, the crossbow and gauntlets, is exported already in grip space: origin = the hand, tip/barrel along +Y, face/top along +Z, strike side along +X. Mount it under `inner` with an identity transform, set `forward_authored = false`, and never apply `FORWARD_TO_TIP` to a `.glb`.
- The guns and crossbow were built from the exact dimensions and marker positions of the current `_build_*` functions. Muzzle and offhand positions in the manifest match today's metadata, so arm poses and muzzle flashes should line up unchanged.
- Bows contain no string. PlayerArmRig draws the string and arrow from `bow_tip_top`, `bow_tip_bottom` and `offhand_grip`, exactly as it does now.
- Markers also exist as empty nodes named `offhand_grip`, `muzzle`, `bow_tip_*`. Blender may add a `.NNN` suffix to these names, so match by prefix. The manifest is the source of truth; the nodes are only a visual check.
- Material `accent` is a placeholder glow. Override it per weapon with the damage-type glow (`Constants.DAMAGE_TYPE_COLOR`, the same as `_glow()`).
- Orbs (Staff, Wand, Spell Gauntlet) and glow rings (Shock Lance) are part of the mesh. Skip the `PACK_ORB` / `_glow_orb` additions when a `.glb` is mounted.

## Tasks
1. Load `weapons_manifest.json` once (cached in a static var) and build the `weapon_type` → entry lookup from it, replacing the hard-coded `AETHER_MELEE` dict.
2. In `build()`, check the manifest before any of the existing branches. If the type's file exists, mount it with `_mount_aether`. Then set the meta values `offhand_grip`, `muzzle`, `bow_tip_top`, `bow_tip_bottom` from the manifest when present, and `hide_hand` when it's true.
3. `build_left_gauntlet()` → mount the matching `*_left.glb` when it exists. It's keyed in the manifest as `"<type> (left)"`.
3b. `build_offhand()`:
   - Foci: mount the `.glb` whose `weapon_type` matches.
   - Shields: mount the `family == "shield"` entry whose `weapon_type` equals the base string.
   - Shields have a material named `trim` on the strap plate. Override it with the rarity colour exactly as `_build_shield` does now (`_flat(trim.darkened(0.3), 0.6, 0.2)`).
   - Off-hand models are already in the same space the current `_build_shield` / `_build_rod` etc. use, so mount them with an identity transform.
4. In `_mount_aether`, replace any material named `accent` on each surface with `_glow(accent_color)`. Keep cast shadows off.
5. Keep the existing `_build_*` gun/bow functions and the pack paths as the fallback. Don't change `FAMILY` or the PlayerArmRig clips.

## Check in the TestArena
- Melee: the hand sits on the grip, the blade points along the swing, and two-handers put the left hand on the second grip.
- Guns: the muzzle flash spawns at the barrel tip, the left hand lands on the foregrip, and the sights sit on top.
- Bows: the drawn string meets both limb tips.
- Fist weapons: no duplicate hand, and the left gauntlet appears.
- Shields and foci: they sit in the left hand like the current placeholders, the shield face points away from the camera, and the strap plate takes the rarity colour.
- Glow parts take the weapon's damage-type colour.
- Report any weapon that reads as too big or too small in first person. Fix sizes in the Blender script and re-export, not with code-side scale fudges.
