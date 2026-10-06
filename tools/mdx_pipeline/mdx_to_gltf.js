// MDX (Warcraft III / Reforged) -> glTF (.glb) converter.
//
// Built against war3-model's own source (dist/war3-model.cjs), not the
// classic-MDX community docs, since this is a Reforged-format file
// (Version 1200) and the skin-weight/pivot conventions differ from the
// older format most write-ups describe. Two load-bearing facts, both
// confirmed by reading war3-model's ModelRenderer.updateNode()/vertex
// shader rather than assumed:
//
// 1. Skin weights: each vertex has 8 bytes - 4 joint-index bytes (raw
//    uint8, indexing model.Nodes BY ObjectId - not model.Bones, and not
//    a per-geoset remap) followed by 4 weight bytes (uint8, /255 for the
//    normalized float weight). Maps directly onto glTF's JOINTS_0/
//    WEIGHTS_0 vec4-u8 accessors with zero remapping, AS LONG AS this
//    exporter's glTF node array preserves the same ObjectId-indexed
//    ordering as model.Nodes.
//
// 2. Bind pose: MDX's own updateNode() computes each node's per-frame
//    local matrix as Translate(pivot)*Translate(T)*Rotate(R)*Scale(S)*
//    Translate(-pivot). At rest (T=0,R=identity,S=1 - true whenever a
//    node has no keyframes for that channel) this ALWAYS collapses to
//    Identity, for every node, regardless of pivot value (a translate-
//    to-pivot then straight back cancels with nothing in between). That
//    means every joint's bind-pose world matrix is Identity, so every
//    glTF inverseBindMatrix is Identity too, and every joint's REST/
//    default TRS in the glTF node hierarchy is also identity - the
//    pivot only matters for baking each ANIMATED frame's delta matrix
//    (see mdx_to_gltf_anim.js), not for the static skeleton structure
//    built here.
//
// Stage 1: geometry + skeleton + skin (verified structurally and via a
// real windowed screenshot before Stage 2 was built on top of it).
// Stage 2 (2026-08-30): animation baking - see buildAnimations() below.
// Each MDX Sequence becomes one glTF animation, sampled at a fixed rate
// (not the source keyframe times directly - simpler and more robust than
// trying to preserve exact keyframe timing/tangents across the axis
// conversion). GlobalSeqId-scoped channels (independent looping tracks)
// are scoped out - see buildAnimations()'s own header comment.

const fs = require("fs");
const path = require("path");
const { mat4, quat } = require("gl-matrix");
const { loadModel } = require("./mdx_load");
const { buildSidecar } = require("./mdx_sidecar");

// WC3/MDX is Z-up, right-handed. glTF is Y-up, right-handed, -Z forward.
// Standard Z-up -> Y-up conversion preserving handedness: (x,y,z) -> (x,z,-y).
// Flagged for visual verification (windowed screenshot), not derived from
// an authoritative source - this is the standard conversion but WC3's
// exact forward axis wasn't independently confirmed here.
function convertVec3(v) {
  return [v[0], v[2], -v[1]];
}

// Same axis remap applied to a quaternion (x,y,z,w) -> (x,z,-y,w).
function convertQuat(q) {
  return [q[0], q[2], -q[1], q[3]];
}

// Scale is a magnitude, not a direction - the axis SWAP still applies
// (an X-axis stretch is still an X-axis stretch after remapping which
// output axis is "up"), but the sign flip on the swapped axis must NOT
// (a negative scale would mirror the mesh). Kept separate from
// convertVec3 for exactly that reason.
function convertScale(v) {
  return [v[0], v[2], v[1]];
}

class BufferBuilder {
  constructor() {
    this.chunks = [];
    this.byteLength = 0;
  }
  // Appends a typed array, 4-byte aligning the START of this chunk
  // (glTF/GLB accessor byteOffset alignment requirement for most
  // component types) by inserting zero padding before it if needed.
  add(typedArray) {
    const padding = (4 - (this.byteLength % 4)) % 4;
    if (padding > 0) {
      this.chunks.push(new Uint8Array(padding));
      this.byteLength += padding;
    }
    const byteOffset = this.byteLength;
    const bytes = new Uint8Array(typedArray.buffer, typedArray.byteOffset, typedArray.byteLength);
    this.chunks.push(bytes);
    this.byteLength += bytes.byteLength;
    return { byteOffset, byteLength: bytes.byteLength };
  }
  toArrayBuffer() {
    const out = new Uint8Array(this.byteLength);
    let offset = 0;
    for (const chunk of this.chunks) {
      out.set(chunk, offset);
      offset += chunk.byteLength;
    }
    return out.buffer;
  }
}

function minMax(floatArray, componentCount) {
  const min = new Array(componentCount).fill(Infinity);
  const max = new Array(componentCount).fill(-Infinity);
  for (let i = 0; i < floatArray.length; i += componentCount) {
    for (let c = 0; c < componentCount; ++c) {
      const v = floatArray[i + c];
      if (v < min[c]) min[c] = v;
      if (v > max[c]) max[c] = v;
    }
  }
  return { min, max };
}

function buildGeometry(model, gltf, buffers, bufferViews, accessors) {
  const meshes = [];
  for (let gi = 0; gi < model.Geosets.length; ++gi) {
    const geoset = model.Geosets[gi];
    const vertCount = geoset.Vertices.length / 3;
    if (vertCount === 0 || geoset.Faces.length === 0) continue; // glTF rejects empty accessors

    // Positions/normals - axis-converted per-vertex (Float32).
    const positions = new Float32Array(vertCount * 3);
    const normals = new Float32Array(vertCount * 3);
    for (let v = 0; v < vertCount; ++v) {
      const p = convertVec3(geoset.Vertices.subarray(v * 3, v * 3 + 3));
      const n = convertVec3(geoset.Normals.subarray(v * 3, v * 3 + 3));
      positions.set(p, v * 3);
      normals.set(n, v * 3);
    }

    // UV0 - glTF and MDX both use top-left-origin UVs, no flip expected;
    // flagged for visual confirmation same as the axis conversion above.
    const uvs = geoset.TVertices[0] ? Float32Array.from(geoset.TVertices[0]) : new Float32Array(vertCount * 2);

    // Tangent: MDX stores vec4 (xyz + handedness w) per vertex already -
    // direct match for glTF's TANGENT accessor, only needs axis conversion
    // on the xyz part (w is a sign, left untouched).
    let tangents = null;
    if (geoset.Tangents && geoset.Tangents.length === vertCount * 4) {
      tangents = new Float32Array(vertCount * 4);
      for (let v = 0; v < vertCount; ++v) {
        const t = geoset.Tangents.subarray(v * 4, v * 4 + 3);
        const converted = convertVec3(t);
        tangents[v * 4] = converted[0];
        tangents[v * 4 + 1] = converted[1];
        tangents[v * 4 + 2] = converted[2];
        tangents[v * 4 + 3] = geoset.Tangents[v * 4 + 3];
      }
    }

    // Joints/weights - direct byte-layout match (see file header), just
    // split the interleaved 8-byte blocks into two vec4<u8> streams.
    let joints = null;
    let weights = null;
    if (geoset.SkinWeights && geoset.SkinWeights.length === vertCount * 8) {
      joints = new Uint8Array(vertCount * 4);
      weights = new Uint8Array(vertCount * 4);
      for (let v = 0; v < vertCount; ++v) {
        for (let c = 0; c < 4; ++c) {
          const joint = geoset.SkinWeights[v * 8 + c];
          const weight = geoset.SkinWeights[v * 8 + 4 + c];
          // Unused slots can carry padding indices (e.g. 255) past the
          // skeleton, which Godot rejects even at zero weight.
          const valid = weight > 0 && joint < model.Nodes.length;
          joints[v * 4 + c] = valid ? joint : 0;
          weights[v * 4 + c] = valid ? weight : 0;
        }
      }
    }

    const indices = geoset.Faces; // already Uint16Array triangle list

    const posView = buffers.add(positions);
    const normView = buffers.add(normals);
    const uvView = buffers.add(uvs);
    const idxView = buffers.add(indices);

    const posViewIdx = bufferViews.push({ buffer: 0, byteOffset: posView.byteOffset, byteLength: posView.byteLength, target: 34962 }) - 1;
    const normViewIdx = bufferViews.push({ buffer: 0, byteOffset: normView.byteOffset, byteLength: normView.byteLength, target: 34962 }) - 1;
    const uvViewIdx = bufferViews.push({ buffer: 0, byteOffset: uvView.byteOffset, byteLength: uvView.byteLength, target: 34962 }) - 1;
    const idxViewIdx = bufferViews.push({ buffer: 0, byteOffset: idxView.byteOffset, byteLength: idxView.byteLength, target: 34963 }) - 1;

    const posMinMax = minMax(positions, 3);
    const posAccessor = accessors.push({
      bufferView: posViewIdx, componentType: 5126, count: vertCount, type: "VEC3",
      min: posMinMax.min, max: posMinMax.max,
    }) - 1;
    const normAccessor = accessors.push({ bufferView: normViewIdx, componentType: 5126, count: vertCount, type: "VEC3" }) - 1;
    const uvAccessor = accessors.push({ bufferView: uvViewIdx, componentType: 5126, count: vertCount, type: "VEC2" }) - 1;
    const idxAccessor = accessors.push({ bufferView: idxViewIdx, componentType: 5123, count: indices.length, type: "SCALAR" }) - 1;

    const attributes = { POSITION: posAccessor, NORMAL: normAccessor, TEXCOORD_0: uvAccessor };

    if (tangents) {
      const tanView = buffers.add(tangents);
      const tanViewIdx = bufferViews.push({ buffer: 0, byteOffset: tanView.byteOffset, byteLength: tanView.byteLength, target: 34962 }) - 1;
      attributes.TANGENT = accessors.push({ bufferView: tanViewIdx, componentType: 5126, count: vertCount, type: "VEC4" }) - 1;
    }
    if (joints && weights) {
      const jointsView = buffers.add(joints);
      const weightsView = buffers.add(weights);
      const jointsViewIdx = bufferViews.push({ buffer: 0, byteOffset: jointsView.byteOffset, byteLength: jointsView.byteLength, target: 34962 }) - 1;
      const weightsViewIdx = bufferViews.push({ buffer: 0, byteOffset: weightsView.byteOffset, byteLength: weightsView.byteLength, target: 34962 }) - 1;
      attributes.JOINTS_0 = accessors.push({ bufferView: jointsViewIdx, componentType: 5121, count: vertCount, type: "VEC4" }) - 1;
      attributes.WEIGHTS_0 = accessors.push({ bufferView: weightsViewIdx, componentType: 5121, normalized: true, count: vertCount, type: "VEC4" }) - 1;
    }

    meshes.push({
      // No `material` index here - Stage 1 exports geometry/skin only.
      // mdxMaterialId (stashed in extras) is the real link back to
      // model.Materials[geoset.MaterialID], consumed by a Godot-side
      // script assigning ORMMaterial3D resources instead (see this
      // folder's README) - avoids fighting glTF's PNG/JPEG-oriented
      // texture model when Godot already imports these .dds files
      // natively and has a purpose-built ORMMaterial3D for this exact
      // Diffuse/Normal/Emissive/ORM texture layout.
      name: geoset.Name || `Geoset_${gi}`,
      primitives: [{ attributes, indices: idxAccessor, mode: 4 }],
      extras: { mdxMaterialId: geoset.MaterialID, mdxGeosetIndex: gi },
    });
  }
  return meshes;
}

function buildSkeleton(model, gltfNodes) {
  // model.Nodes is ALREADY indexed by ObjectId (model.Nodes[objectId] =
  // node, see war3-model's parser) - iterate it directly so glTF node
  // index === MDX ObjectId === JOINTS_0 index, with zero remapping.
  const nodeStartIndex = gltfNodes.length;
  const childrenByIndex = new Map();
  for (let i = 0; i < model.Nodes.length; ++i) {
    const node = model.Nodes[i];
    gltfNodes.push({
      name: node ? node.Name : `_unused_${i}`,
      translation: [0, 0, 0],
      rotation: [0, 0, 0, 1],
      scale: [1, 1, 1],
    });
    if (node && (node.Parent || node.Parent === 0)) {
      const list = childrenByIndex.get(node.Parent) || [];
      list.push(nodeStartIndex + i);
      childrenByIndex.set(node.Parent, list);
    }
  }
  for (const [parentObjectId, children] of childrenByIndex) {
    gltfNodes[nodeStartIndex + parentObjectId].children = children;
  }
  const roots = [];
  for (let i = 0; i < model.Nodes.length; ++i) {
    const node = model.Nodes[i];
    if (node && !(node.Parent || node.Parent === 0)) roots.push(nodeStartIndex + i);
  }
  return { nodeStartIndex, roots, count: model.Nodes.length };
}

// Stage 2: animation baking.
//
// war3-model's own updateNode() computes each node's per-frame LOCAL
// matrix as Translate(pivot)*Translate(T)*Rotate(R)*Scale(S)*
// Translate(-pivot), then WORLD = parent.WORLD * LOCAL. That per-node
// LOCAL matrix (evaluated at a given frame) is directly usable as this
// node's glTF LOCAL (parent-relative) transform for that frame too - no
// further adjustment needed, since glTF's own hierarchy composes the
// exact same way (child.world = parent.world * child.local) and the
// REST pose this exporter already emits for every joint is Identity
// (see file header) - matching what the same formula collapses to at
// T=0/R=identity/S=1. So: bake this LOCAL matrix per node per sampled
// frame, decompose into T/R/S, axis-convert each component, done.
//
// GlobalSeqId-scoped channels (independent looping tracks - idle
// blinking, cloth sway - that run on their own separate global timeline
// regardless of which named Sequence is active) are treated as absent
// for this bake (their default/rest value is used throughout) - a
// second, independent animation layer most engines handle via a
// separate "always playing" track, out of scope for a first pass. No
// doc/spec need was established for this project specifically.
const SAMPLE_RATE_HZ = 30;
// Corpse-decay (60 s each) and portrait/cinematic sequences have no gameplay
// use and would dominate file size, so they are not baked.
const SKIPPED_SEQUENCE_PATTERN = /^(Decay|Cinematic)/i;
const DEFAULT_TRANSLATION = [0, 0, 0];
const DEFAULT_ROTATION = [0, 0, 0, 1];
const DEFAULT_SCALE = [1, 1, 1];

function usableAnimVector(av) {
  if (!av || !av.Keys || av.Keys.length === 0) return null;
  if (av.GlobalSeqId !== null && av.GlobalSeqId !== undefined) return null; // scoped out, see file header
  return av;
}

// Linear interpolation between the two keyframes bracketing frameMs.
// WC3's own LineType (DontInterp/Linear/Hermite/Bezier) is collapsed to
// just step-vs-linear here - Hermite/Bezier tangent data (InTan/OutTan)
// is present on this model's keys but approximated as linear, flagged as
// a simplification (most of this model's own channels are already
// LineType Linear in practice, checked directly against the real file).
function evalVec3(av, frameMs, fallback) {
  const usable = usableAnimVector(av);
  if (!usable) return fallback.slice();
  const keys = usable.Keys;
  if (frameMs <= keys[0].Frame) return Array.from(keys[0].Vector);
  if (frameMs >= keys[keys.length - 1].Frame) return Array.from(keys[keys.length - 1].Vector);
  for (let i = 0; i < keys.length - 1; ++i) {
    const a = keys[i], b = keys[i + 1];
    if (frameMs >= a.Frame && frameMs <= b.Frame) {
      if (usable.LineType === 0 || b.Frame === a.Frame) return Array.from(a.Vector);
      const t = (frameMs - a.Frame) / (b.Frame - a.Frame);
      const out = new Array(a.Vector.length);
      for (let c = 0; c < a.Vector.length; ++c) out[c] = a.Vector[c] + (b.Vector[c] - a.Vector[c]) * t;
      return out;
    }
  }
  return fallback.slice();
}

function evalQuat(av, frameMs, fallback) {
  const usable = usableAnimVector(av);
  if (!usable) return fallback.slice();
  const keys = usable.Keys;
  if (frameMs <= keys[0].Frame) return Array.from(keys[0].Vector);
  if (frameMs >= keys[keys.length - 1].Frame) return Array.from(keys[keys.length - 1].Vector);
  for (let i = 0; i < keys.length - 1; ++i) {
    const a = keys[i], b = keys[i + 1];
    if (frameMs >= a.Frame && frameMs <= b.Frame) {
      if (usable.LineType === 0 || b.Frame === a.Frame) return Array.from(a.Vector);
      const t = (frameMs - a.Frame) / (b.Frame - a.Frame);
      const out = quat.create();
      quat.slerp(out, a.Vector, b.Vector, t);
      return Array.from(out);
    }
  }
  return fallback.slice();
}

function nodeHasAnimation(node) {
  return !!(usableAnimVector(node.Translation) || usableAnimVector(node.Rotation) || usableAnimVector(node.Scaling));
}

// The LOCAL delta matrix for one node at one absolute frame (ms) -
// Translate(pivot)*Translate(T)*Rotate(R)*Scale(S)*Translate(-pivot),
// matching war3-model's updateNode() exactly (see file-level comment).
function bakeLocalMatrix(node, frameMs) {
  const t = evalVec3(node.Translation, frameMs, DEFAULT_TRANSLATION);
  const r = evalQuat(node.Rotation, frameMs, DEFAULT_ROTATION);
  const s = evalVec3(node.Scaling, frameMs, DEFAULT_SCALE);
  const out = mat4.create();
  mat4.fromRotationTranslationScaleOrigin(out, r, t, s, node.PivotPoint);
  return out;
}

function buildAnimations(model, skeleton, gltfNodes, buffers, bufferViews, accessors) {
  const animations = [];
  const animatedNodeIndices = [];
  for (let i = 0; i < model.Nodes.length; ++i) {
    const node = model.Nodes[i];
    if (node && nodeHasAnimation(node)) animatedNodeIndices.push(i);
  }

  for (const seq of model.Sequences) {
    if (SKIPPED_SEQUENCE_PATTERN.test(seq.Name)) continue;
    const startMs = seq.Interval[0];
    const endMs = seq.Interval[1];
    const durationMs = Math.max(endMs - startMs, 1);
    const stepMs = 1000 / SAMPLE_RATE_HZ;
    const sampleCount = Math.max(2, Math.ceil(durationMs / stepMs) + 1);
    const times = new Float32Array(sampleCount);
    for (let i = 0; i < sampleCount; ++i) {
      const frameMs = Math.min(startMs + i * stepMs, endMs);
      times[i] = (frameMs - startMs) / 1000;
    }

    const channels = [];
    const samplers = [];
    const timeView = buffers.add(times);
    const timeViewIdx = bufferViews.push({ buffer: 0, byteOffset: timeView.byteOffset, byteLength: timeView.byteLength }) - 1;
    const timeAccessor = accessors.push({
      bufferView: timeViewIdx, componentType: 5126, count: sampleCount, type: "SCALAR",
      min: [times[0]], max: [times[sampleCount - 1]],
    }) - 1;

    for (const nodeIdx of animatedNodeIndices) {
      const node = model.Nodes[nodeIdx];
      const translations = new Float32Array(sampleCount * 3);
      const rotations = new Float32Array(sampleCount * 4);
      const scales = new Float32Array(sampleCount * 3);
      for (let i = 0; i < sampleCount; ++i) {
        const frameMs = Math.min(startMs + i * stepMs, endMs);
        const local = bakeLocalMatrix(node, frameMs);
        const t = mat4.getTranslation([0, 0, 0], local);
        // Linear part is exactly R*S, so R and S are taken from the
        // evaluated channels rather than decomposed - decomposing a
        // zero-scale key (WC3's way of hiding a bone) yields NaN rotations.
        const r = quat.normalize([0, 0, 0, 1], evalQuat(node.Rotation, frameMs, DEFAULT_ROTATION));
        const s = evalVec3(node.Scaling, frameMs, DEFAULT_SCALE);
        translations.set(convertVec3(t), i * 3);
        rotations.set(convertQuat(r), i * 4);
        scales.set(convertScale(s), i * 3);
      }

      const gltfNodeIdx = skeleton.nodeStartIndex + nodeIdx;
      const tView = buffers.add(translations);
      const tViewIdx = bufferViews.push({ buffer: 0, byteOffset: tView.byteOffset, byteLength: tView.byteLength }) - 1;
      const tAccessor = accessors.push({ bufferView: tViewIdx, componentType: 5126, count: sampleCount, type: "VEC3" }) - 1;
      samplers.push({ input: timeAccessor, output: tAccessor, interpolation: "LINEAR" });
      channels.push({ sampler: samplers.length - 1, target: { node: gltfNodeIdx, path: "translation" } });

      const rView = buffers.add(rotations);
      const rViewIdx = bufferViews.push({ buffer: 0, byteOffset: rView.byteOffset, byteLength: rView.byteLength }) - 1;
      const rAccessor = accessors.push({ bufferView: rViewIdx, componentType: 5126, count: sampleCount, type: "VEC4" }) - 1;
      samplers.push({ input: timeAccessor, output: rAccessor, interpolation: "LINEAR" });
      channels.push({ sampler: samplers.length - 1, target: { node: gltfNodeIdx, path: "rotation" } });

      const sView = buffers.add(scales);
      const sViewIdx = bufferViews.push({ buffer: 0, byteOffset: sView.byteOffset, byteLength: sView.byteLength }) - 1;
      const sAccessor = accessors.push({ bufferView: sViewIdx, componentType: 5126, count: sampleCount, type: "VEC3" }) - 1;
      samplers.push({ input: timeAccessor, output: sAccessor, interpolation: "LINEAR" });
      channels.push({ sampler: samplers.length - 1, target: { node: gltfNodeIdx, path: "scale" } });
    }

    animations.push({ name: seq.Name, channels, samplers });
  }

  return animations;
}

function convert(mdxPath, outPath, scale = 1.0, bakeAnimations = true) {
  const model = loadModel(mdxPath);

  const buffers = new BufferBuilder();
  const bufferViews = [];
  const accessors = [];
  const gltfNodes = [];

  const meshes = buildGeometry(model, null, buffers, bufferViews, accessors);
  const skeleton = buildSkeleton(model, gltfNodes);

  // Identity inverseBindMatrices for every joint (see file header for why
  // this is correct for MDX's own delta-transform skinning convention).
  const jointCount = skeleton.count;
  const ibmFloats = new Float32Array(jointCount * 16);
  const identity16 = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1];
  for (let j = 0; j < jointCount; ++j) ibmFloats.set(identity16, j * 16);
  const ibmView = buffers.add(ibmFloats);
  const ibmViewIdx = bufferViews.push({ buffer: 0, byteOffset: ibmView.byteOffset, byteLength: ibmView.byteLength }) - 1;
  const ibmAccessor = accessors.push({ bufferView: ibmViewIdx, componentType: 5126, count: jointCount, type: "MAT4" }) - 1;

  const joints = [];
  for (let i = 0; i < jointCount; ++i) joints.push(skeleton.nodeStartIndex + i);
  const skin = { joints, inverseBindMatrices: ibmAccessor, skeleton: skeleton.nodeStartIndex + skeleton.roots[0] };

  // One mesh-instance node per Geoset, skinned, sitting alongside (not
  // under) the skeleton root - MaterialID is carried in mesh.extras for a
  // separate Godot-side script to consume (see README in this folder).
  const meshNodeIndices = [];
  const meshNodesStart = gltfNodes.length;
  meshes.forEach((mesh, mi) => {
    // Index-based node name so Godot-side material/visibility lookups
    // (the sidecar JSON) don't depend on geoset names, which repeat or are blank.
    gltfNodes.push({ name: `Geoset_${mesh.extras.mdxGeosetIndex}`, mesh: mi, skin: 0 });
    meshNodeIndices.push(meshNodesStart + mi);
  });

  // Reforged assets are commonly authored at a much larger internal unit
  // scale than classic WC3. IMPORTANT: this scale is applied to a plain
  // wrapper node, NOT to a skeleton joint/bone node directly - an earlier
  // version set .scale on skeleton.roots[0] (a node also listed in
  // skin.joints), which Godot's glTF importer absorbs into internal
  // Skeleton3D bone data rather than keeping as a literal scene-tree
  // Node3D transform. That made the actual in-game result silently NOT
  // match this scale factor at all (caught by the user: the boss
  // rendered far too small in real gameplay, not just "needs a bigger
  // number" - the whole mechanism wasn't reaching the skeleton). A
  // wrapper that isn't itself a joint sidesteps this ambiguity entirely
  // - both the skeleton and every mesh instance sit under it as plain
  // children, so it survives import as an ordinary, verifiable node
  // scale. No authoritative "correct" factor exists for Reforged assets
  // in general - this needs visual tuning against something of known
  // scale (this project's Player capsule is 1.8 tall), not a value to
  // trust blindly; this model's own declared MinimumExtent/MaximumExtent
  // (~220x142x288 units) turned out to be loose/padded metadata, NOT the
  // actual tight mesh bounds (~98x114x87, from a real structural test) -
  // calibrate scale against the latter, not the former.
  const wrapperIndex = gltfNodes.length;
  gltfNodes.push({
    name: "ModelRoot",
    children: [...skeleton.roots, ...meshNodeIndices],
    scale: [scale, scale, scale],
  });

  const sceneRoots = [wrapperIndex];

  const animations = bakeAnimations
    ? buildAnimations(model, skeleton, gltfNodes, buffers, bufferViews, accessors)
    : [];

  const gltf = {
    asset: { version: "2.0", generator: "Project Aether mdx_to_gltf.js" },
    scene: 0,
    scenes: [{ nodes: sceneRoots }],
    nodes: gltfNodes,
    meshes,
    skins: [skin],
    buffers: [{ byteLength: buffers.byteLength }],
    bufferViews,
    accessors,
  };
  if (animations.length > 0) gltf.animations = animations;

  writeGLB(gltf, buffers.toArrayBuffer(), outPath);
  console.log(`Wrote ${outPath}`);
  const sidecar = buildSidecar(model, mdxPath, scale);
  const sidecarPath = outPath.replace(/\.glb$/i, ".mdxmeta.json");
  fs.writeFileSync(sidecarPath, JSON.stringify(sidecar, null, 2));
  console.log(`Wrote ${sidecarPath}`);
  console.log(`  height ${sidecar.bounds.height.toFixed(3)} m at scale ${scale}`);
  console.log(`  ${meshes.length} meshes, ${jointCount} joints, ${buffers.byteLength} bytes of buffer data`);
  if (animations.length > 0) {
    console.log(`  ${animations.length} animations: ${animations.map((a) => a.name).join(", ")}`);
  }
}

function writeGLB(gltfJson, binaryArrayBuffer, outPath) {
  const jsonStr = JSON.stringify(gltfJson);
  let jsonBytes = Buffer.from(jsonStr, "utf8");
  const jsonPad = (4 - (jsonBytes.length % 4)) % 4;
  if (jsonPad > 0) jsonBytes = Buffer.concat([jsonBytes, Buffer.alloc(jsonPad, 0x20)]);

  let binBytes = Buffer.from(binaryArrayBuffer);
  const binPad = (4 - (binBytes.length % 4)) % 4;
  if (binPad > 0) binBytes = Buffer.concat([binBytes, Buffer.alloc(binPad, 0)]);

  const jsonChunkHeader = Buffer.alloc(8);
  jsonChunkHeader.writeUInt32LE(jsonBytes.length, 0);
  jsonChunkHeader.writeUInt32LE(0x4e4f534a, 4); // "JSON"

  const binChunkHeader = Buffer.alloc(8);
  binChunkHeader.writeUInt32LE(binBytes.length, 0);
  binChunkHeader.writeUInt32LE(0x004e4942, 4); // "BIN\0"

  const totalLength = 12 + jsonChunkHeader.length + jsonBytes.length + binChunkHeader.length + binBytes.length;
  const header = Buffer.alloc(12);
  header.writeUInt32LE(0x46546c67, 0); // "glTF"
  header.writeUInt32LE(2, 4);
  header.writeUInt32LE(totalLength, 8);

  const glb = Buffer.concat([header, jsonChunkHeader, jsonBytes, binChunkHeader, binBytes]);
  fs.writeFileSync(outPath, glb);
}

if (require.main === module) {
  const [, , mdxArg, outArg, scaleArg, noAnimArg] = process.argv;
  if (!mdxArg || !outArg) {
    console.error("Usage: node mdx_to_gltf.js <input.mdx> <output.glb> [scale] [--no-anim]");
    process.exit(1);
  }
  const bakeAnimations = noAnimArg !== "--no-anim";
  convert(path.resolve(mdxArg), path.resolve(outArg), scaleArg ? parseFloat(scaleArg) : 1.0, bakeAnimations);
}

module.exports = { convert, loadModel, convertVec3, convertQuat, convertScale, BufferBuilder };
