# MDX -> glTF pipeline

Converts Warcraft III Reforged `.mdx` models (like `assets/models/Arator the
Redeemer/Arator_Midnights.mdx`) into `.glb` files Godot can import natively.
Godot has zero built-in support for `.mdx`; this bridges that gap using
[`war3-model`](https://github.com/4eb0da/war3-model), an npm library that
parses both classic and Reforged MDX (confirmed against this project's real
Reforged file, not assumed).

This directory sits outside Godot's asset scan (`.gdignore`) - `node_modules`
and generated `.glb` files here are gitignored (see the project root
`.gitignore`), not part of the game itself.

## Setup

Node.js is required (installed via `winget install OpenJS.NodeJS` on this
machine, 2026-08-30 - if `node`/`npm` aren't on PATH in a given shell, use
the full path: `C:\Program Files\nodejs\node.exe`).

```
npm install
```

## Usage

```
node mdx_to_gltf.js <input.mdx> <output.glb> [scale] [--no-anim]
```

`--no-anim` skips animation baking (Stage 2, below) if you only need
geometry/skeleton/skin - mainly useful for faster iteration while debugging
the base rig, since animation baking is the slower step.

`scale` is optional (default 1.0) - Reforged assets are commonly authored at
a much larger internal unit scale than classic WC3. There's no universal
"correct" factor, it needs visual tuning per model against something of
known scale (this project's Player capsule is 1.8 units tall) - **and
verified visually**, not just trusted as a number. Two real bugs already
came from getting this wrong:

- **Calibrate against the actual mesh bounding box, not the MDX's own
  declared `Info.MinimumExtent`/`MaximumExtent`.** That metadata can be
  loose/padded - Arator's declared extents span ~220x142x288 units, but
  the real mesh bounds (measured via a structural test after export) are
  ~98x114x87. The first scale choice (`0.0066`) was picked against the
  wrong number and rendered far too small in actual gameplay before this
  was caught. `0.02` (against the real ~114-unit height) reads as an
  appropriately larger-than-the-player boss.
- **The scale is applied to a plain wrapper node ("ModelRoot"), not to
  a skeleton joint node.** A joint node's `scale` gets absorbed into
  Godot's internal `Skeleton3D` bone data on import rather than staying a
  literal scene-tree transform - setting it there silently does nothing
  to the actual skinned render, regardless of the value. If you're
  touching this code, don't scale anything inside `skeleton.roots`
  directly.

Example:
```
node mdx_to_gltf.js "../../assets/models/Arator the Redeemer/Arator_Midnights.mdx" out.glb 0.02
```

Then copy/move the `.glb` into `assets/` somewhere under Godot's scan and it
imports like any other 3D scene (`--headless --import` forces a full import
pass without opening the editor UI, if verifying from a script/CI-like
context rather than the editor itself).

## What's implemented (Stage 1, 2026-08-30)

Geometry, skeleton, and skinning - verified both structurally (a scratch
test confirmed exact vertex/joint/mesh counts against the source file) and
**visually** (a real windowed screenshot of the imported model in Godot: a
correctly-proportioned, upright, untextured character holding a sword, no
mesh tearing or twisted limbs). See `mdx_to_gltf.js`'s own header comment for
the two load-bearing facts this was built against (skin weight byte layout,
bind-pose math) - both confirmed by reading `war3-model`'s actual rendering
source, not assumed from general MDX documentation, since this is a Reforged
(v1200) file with a different convention than classic WC3 write-ups describe.

`inspect_bones.js`/`inspect_extents.js` are the diagnostic scripts used to
confirm the skin-weight/bind-pose math and the scale issue respectively -
kept as reusable inspection utilities for the next model dropped into this
pipeline, not one-off throwaways. `spike.js` is the original parse-and-dump
sanity check (geosets/bones/sequences/textures/materials) - run it first on
any new `.mdx` to see its structure before converting.

## What's implemented (Stage 2, 2026-08-30)

Animation baking. Each MDX Sequence becomes one glTF animation - every
animated node's per-frame LOCAL matrix (`Translate(pivot)*Translate(T)*
Rotate(R)*Scale(S)*Translate(-pivot)`, confirmed against `war3-model`'s
`updateNode()`) is sampled at a fixed 30Hz rate across the Sequence's frame
interval, decomposed into T/R/S via `gl-matrix` (a `war3-model` transitive
dependency - it exposes the exact same `fromRotationTranslationScaleOrigin`
function `war3-model`'s own renderer uses, plus `getTranslation`/
`getRotation`/`getScaling` for the decomposition side, so this isn't
hand-rolled math), and axis/scale-converted per component
(`convertVec3`/`convertQuat`/`convertScale` - note scale uses a different
conversion than position/rotation: axes still swap, but magnitudes never
get sign-flipped). `GlobalSeqId`-scoped channels (independent looping
tracks - idle blinking, cloth sway - layered on top of whichever Sequence
is active) are scoped out - their default/rest value is used throughout
instead. WC3's Hermite/Bezier interpolation (`LineType`) is approximated as
linear - most of this model's own channels are already `LineType` Linear in
practice, checked directly against the file.

Verified both structurally (an `AnimationPlayer`/`Animation` resource
count/name/track check) and **visually** - two real windowed screenshots,
one mid-`Walk 1` (clear stride, correct cloth/robe flow) and one mid-
`Attack 1` (full weapon follow-through, torso twist into the swing) - no
mesh tearing or exploded geometry in either. `loop_mode` isn't set by the
importer (Godot's own default is `LOOP_NONE` for every imported
`Animation`) - that's a gameplay decision, so it's left to be set at
runtime by whatever wires these up (see `FigmentBoss.gd`'s own
`_setup_animation_player()` for the convention: loop the idle/walk clips,
leave attack/death one-shot).

## Not yet implemented

- **Materials/textures.** Deliberately left out of the `.glb` (glTF's
  texture model expects PNG/JPEG, not `.dds`, and Godot already imports
  `.dds` natively) - each exported mesh carries `extras.mdxMaterialId`
  linking back to `model.Materials[id]`/`model.Textures[]` so a Godot-side
  script can build `ORMMaterial3D` resources (a literal match for this
  asset's Diffuse/Normal/Emissive/ORM texture packing) and assign them by
  geoset. Not written yet. Only 4 of this model's 9 materials reference
  textures actually present in `assets/models/Arator the Redeemer/` - the
  other 5 geosets belong to other base Reforged rigs merged into this one
  (Anasterian Sunstrider, High Elf Archmage, High Elf Runner) and will stay
  untextured, same placeholder-art treatment the rest of this project
  already gives missing art.
