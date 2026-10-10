// Spell-effect converter: a classic WC3 effect model (.mdx) -> the .glb its
// geosets need (via mdx_to_gltf.js) plus a .fx.json sidecar carrying what
// glTF can't: particle emitters (ParticleEmitter2), layer blend modes, layer
// and geoset alpha/color tracks and texture (UV) animation. Read at runtime by
// entities/effects/mdx_effect/MdxEffect.gd.
//
// Use the classic SD models (war3.w3mod:abilities/...). The Reforged HD copies
// of spell effects are PopcornFX references (.pkfx) with no usable data.
//
// Tracks are sampled at SAMPLE_HZ per sequence with war3-model's own
// interpolation (mdx_interp.js). Encoding, decoded by MdxEffect.gd:
//   constant         -> number or [components]
//   per sequence     -> { "n": components, "seq": [[flat samples], ...] }
//   global sequence  -> { "n": components, "global": seconds, "v": [flat samples] }
// Everything is converted to Godot axes (Y-up) and multiplied by `scale`.
//
// Usage: node mdx_fx.js <effect.mdx> [scale]
// Writes <effect>.glb (when the model has geosets) and <effect>.fx.json beside it.
// Ribbon emitters, event objects (spawned models, splats, sounds) and texture
// rotation/scaling are not converted yet.
const fs = require("fs");
const path = require("path");
const { mat4, vec3 } = require("gl-matrix");
const { loadModel, convert } = require("./mdx_to_gltf");
const { loadLinks, resPath } = require("./dedupe_textures");
const { evalComponents, evalQuat, windowFor, isAnimated } = require("./mdx_interp");

const SAMPLE_HZ = 30;
const STEP_MS = 1000 / SAMPLE_HZ;
const DEFAULT_SCALE = 0.02;
const FLAG_LINE_EMITTER = 0x20000;
const FLAG_MODEL_SPACE = 0x80000;
const FLAG_XY_QUAD = 0x100000;
const SHADING_TWO_SIDED = 16;

// WC3 Z-up -> Godot Y-up: (x, y, z) -> (x, z, -y), as in mdx_to_gltf.js.
const AXIS = mat4.fromValues(1, 0, 0, 0, 0, 0, -1, 0, 0, 1, 0, 0, 0, 0, 0, 1);
const AXIS_INV = mat4.invert(mat4.create(), AXIS);

function toGodot(v) {
  return [v[0], v[2], -v[1]];
}

function sampleTimes(seq) {
  const out = [];
  for (let f = seq.Interval[0]; f < seq.Interval[1]; f += STEP_MS) out.push(f);
  out.push(seq.Interval[1]);
  return out;
}

// Samples a scalar/vector track. `map` turns raw components into exported ones.
function track(model, av, fallback, map = (v) => v) {
  if (!isAnimated(av)) {
    const raw = av === undefined || av === null ? fallback : typeof av === "number" ? [av] : Array.from(av);
    const v = map(raw);
    return v.length === 1 ? round(v[0]) : v.map(round);
  }
  const n = map(fallback).length;
  if (typeof av.GlobalSeqId === "number") {
    const length = model.GlobalSequences[av.GlobalSeqId] || 0;
    const v = [];
    for (let f = 0; f <= length; f += STEP_MS) {
      v.push(...map(evalComponents(av, f, 0, length) || fallback));
    }
    return { n, global: length / 1000, v: v.map(round) };
  }
  const seq = model.Sequences.map((s) =>
    sampleTimes(s).flatMap((f) => map(evalComponents(av, f, s.Interval[0], s.Interval[1]) || fallback)).map(round)
  );
  return collapse({ n, seq });
}

// A per-sequence track whose samples are all equal becomes a constant.
function collapse(t) {
  const first = t.seq.find((s) => s.length)?.slice(0, t.n);
  if (!first) return t;
  for (const s of t.seq) {
    for (let i = 0; i < s.length; ++i) if (s[i] !== first[i % t.n]) return t;
  }
  return t.n === 1 ? first[0] : first;
}

function round(x) {
  return Math.round(x * 1e4) / 1e4;
}

// World matrix of a node at one frame, war3-model's updateNode() formula.
function nodeMatrix(model, node, seq, frame) {
  const local = mat4.create();
  const t = componentsAt(model, node.Translation, seq, frame) || [0, 0, 0];
  const s = componentsAt(model, node.Scaling, seq, frame) || [1, 1, 1];
  let r = [0, 0, 0, 1];
  if (isAnimated(node.Rotation)) {
    const w = windowFor(node.Rotation, model, seq, frame, frame - seq.Interval[0]);
    r = evalQuat(node.Rotation, w.frame, w.from, w.to) || r;
  }
  mat4.fromRotationTranslationScaleOrigin(local, r, t, s, node.PivotPoint);
  const parent = node.Parent !== null && node.Parent !== undefined ? model.Nodes[node.Parent] : null;
  return parent ? mat4.multiply(local, nodeMatrix(model, parent, seq, frame), local) : local;
}

function componentsAt(model, av, seq, frame) {
  if (!isAnimated(av)) return null;
  const w = windowFor(av, model, seq, frame, frame - seq.Interval[0]);
  return evalComponents(av, w.frame, w.from, w.to);
}

function chainAnimated(model, node) {
  for (let n = node; n; n = n.Parent !== null && n.Parent !== undefined ? model.Nodes[n.Parent] : null) {
    if (isAnimated(n.Translation) || isAnimated(n.Rotation) || isAnimated(n.Scaling)) return true;
  }
  return false;
}

// WC3 world matrix -> Godot basis columns + origin (12 floats), origin scaled.
function godotMatrix(m, scale) {
  const g = mat4.multiply(mat4.create(), AXIS, mat4.multiply(mat4.create(), m, AXIS_INV));
  return [g[0], g[1], g[2], g[4], g[5], g[6], g[8], g[9], g[10], g[12] * scale, g[13] * scale, g[14] * scale].map(round);
}

function matrixTrack(model, node, scale) {
  if (!chainAnimated(model, node)) return godotMatrix(nodeMatrix(model, node, model.Sequences[0], 0), scale);
  return {
    n: 12,
    seq: model.Sequences.map((s) => sampleTimes(s).flatMap((f) => godotMatrix(nodeMatrix(model, node, s, f), scale))),
  };
}

function textureFile(model, id, modelDir, listing) {
  const tex = model.Textures[id];
  if (!tex || !tex.Image) return null;
  const stem = tex.Image.split(/[\\/]/).pop().replace(/\.[^.]+$/, "").toLowerCase();
  const local = listing.find((f) => f.toLowerCase() === `${stem}.dds`);
  if (local) return local;
  const key = `${resPath(modelDir)}/${stem}.dds`.toLowerCase();
  const linked = Object.entries(loadLinks()).find(([from]) => from.toLowerCase() === key);
  return linked ? linked[1] : null;
}

function textureIdOf(value) {
  if (typeof value === "number") return value;
  if (value && value.Keys && value.Keys.length) return value.Keys[0].Vector[0];
  return null;
}

function buildGeosets(model, textures) {
  return model.Geosets.map((g, gi) => {
    const material = model.Materials[g.MaterialID];
    const anim = (model.GeosetAnims || []).find((a) => a.GeosetId === gi);
    const layers = material.Layers.map((layer) => {
      const texAnim = typeof layer.TVertexAnimId === "number" ? model.TextureAnims[layer.TVertexAnimId] : null;
      return {
        texture: textures[textureIdOf(layer.TextureID)] ?? null,
        filter: layer.FilterMode || 0,
        two_sided: !!((layer.Shading || 0) & SHADING_TWO_SIDED),
        alpha: track(model, layer.Alpha, [1]),
        // WC3 texture translation is a UV offset; only x/y matter.
        uv: texAnim ? track(model, texAnim.Translation, [0, 0, 0], (v) => [v[0], v[1]]) : 0,
      };
    });
    return {
      index: gi,
      layers,
      alpha: track(model, anim ? anim.Alpha : undefined, [1]),
      color: track(model, anim ? anim.Color : undefined, [1, 1, 1]),
    };
  });
}

function buildEmitters(model, textures, scale) {
  const scaled = (v) => v.map((x) => x * scale);
  return (model.ParticleEmitters2 || []).map((e) => {
    const node = model.Nodes[e.ObjectId];
    // Squirt emitters fire EmissionRate particles once per key instead of a rate.
    const bursts = e.Squirt && isAnimated(e.EmissionRate)
      ? model.Sequences.map((s) => e.EmissionRate.Keys
        .filter((k) => k.Frame >= s.Interval[0] && k.Frame <= s.Interval[1] && k.Vector[0] > 0)
        .map((k) => [round((k.Frame - s.Interval[0]) / 1000), Math.round(k.Vector[0])]))
      : null;
    return {
      name: e.Name,
      texture: textures[e.TextureID] ?? null,
      filter: e.FilterMode || 0,
      rows: e.Rows || 1,
      columns: e.Columns || 1,
      head: !!(e.FrameFlags & 1),
      tail: !!(e.FrameFlags & 2),
      lifespan: round(e.LifeSpan),
      time_mid: round(e.Time),
      tail_length: round(e.TailLength),
      colors: e.SegmentColor.map((c, i) => [...Array.from(c).map(round), round(e.Alpha[i] / 255)]),
      scaling: Array.from(e.ParticleScaling).map((x) => round(x * scale)),
      uv_head: [...e.LifeSpanUVAnim.slice(0, 2), ...e.DecayUVAnim.slice(0, 2)].map(Number),
      uv_tail: [...e.TailUVAnim.slice(0, 2), ...e.TailDecayUVAnim.slice(0, 2)].map(Number),
      xy_quad: !!(e.Flags & FLAG_XY_QUAD),
      model_space: !!(e.Flags & FLAG_MODEL_SPACE),
      line_emitter: !!(e.Flags & FLAG_LINE_EMITTER),
      priority: e.PriorityPlane || 0,
      pivot: toGodot(e.PivotPoint).map((x) => round(x * scale)),
      matrix: matrixTrack(model, node, scale),
      bursts,
      emission: bursts ? 0 : track(model, e.EmissionRate, [0]),
      speed: track(model, e.Speed, [0], scaled),
      variation: track(model, e.Variation, [0]),
      latitude: track(model, e.Latitude, [0]),
      gravity: track(model, e.Gravity, [0], scaled),
      width: track(model, e.Width, [0], scaled),
      length: track(model, e.Length, [0], scaled),
      visibility: track(model, e.Visibility, [1]),
    };
  });
}

function convertEffect(mdxPath, scale = DEFAULT_SCALE) {
  const model = loadModel(mdxPath);
  const modelDir = path.dirname(mdxPath);
  const listing = fs.readdirSync(modelDir);
  const textures = model.Textures.map((_, i) => textureFile(model, i, modelDir, listing));
  const base = mdxPath.replace(/\.mdx$/i, "");
  const hasGeometry = model.Geosets.length > 0;
  if (hasGeometry) convert(mdxPath, `${base}.glb`, scale, true);

  const fx = {
    source: path.basename(mdxPath),
    scale,
    sample_hz: SAMPLE_HZ,
    model: hasGeometry ? `${path.basename(base)}.glb` : null,
    sequences: model.Sequences.map((s) => ({ name: s.Name, start: s.Interval[0], end: s.Interval[1] })),
    textures,
    geosets: buildGeosets(model, textures),
    emitters: buildEmitters(model, textures, scale),
  };
  fs.writeFileSync(`${base}.fx.json`, JSON.stringify(fx));
  const missing = model.Textures.map((t, i) => (textures[i] ? null : t.Image)).filter((t) => t);
  console.log(`Wrote ${base}.fx.json: ${fx.geosets.length} geosets, ${fx.emitters.length} emitters, sequences ${fx.sequences.map((s) => s.name).join("/")}`);
  if (missing.length) console.log(`  missing textures: ${missing.join(", ")}`);
  if ((model.RibbonEmitters || []).length) console.log(`  ${model.RibbonEmitters.length} ribbon emitters skipped (not supported yet)`);
  return fx;
}

if (require.main === module) {
  const [, , mdxArg, scaleArg] = process.argv;
  if (!mdxArg) {
    console.error("Usage: node mdx_fx.js <effect.mdx> [scale]");
    process.exit(1);
  }
  convertEffect(path.resolve(mdxArg), scaleArg ? parseFloat(scaleArg) : DEFAULT_SCALE);
}

module.exports = { convertEffect };
