// Per-model sidecar JSON written next to each .glb: geoset -> texture files,
// blend mode and per-sequence visibility. Read by tools/build_mdx_wrappers.gd
// (materials) and MdxModel.gd at runtime (visibility).
const fs = require("fs");
const path = require("path");
const { loadLinks, resPath } = require("./dedupe_textures");

// Reforged pre-1200 (v1000) materials list one texture per layer in a fixed
// slot order; v1200 puts every slot on a single layer as explicit IDs.
const V1000_SLOT_LAYERS = { diffuse: 0, normal: 1, orm: 2, emissive: 3 };
const ALPHA_SAMPLES = 12;
const VISIBLE_MEAN_ALPHA = 0.5;
const STAND_PATTERN = /^Stand 1$/i;

function textureSlots(model, material) {
  const layers = material.Layers;
  if (layers.length === 1 && layers[0].NormalTextureID !== undefined) {
    const l = layers[0];
    return { diffuse: l.TextureID, normal: l.NormalTextureID, orm: l.ORMTextureID, emissive: l.EmissiveTextureID };
  }
  const slots = {};
  for (const [slot, idx] of Object.entries(V1000_SLOT_LAYERS)) {
    slots[slot] = layers[idx] ? layers[idx].TextureID : undefined;
  }
  return slots;
}

function textureIdOf(value) {
  // TextureID can be an AnimVector (flipbook); its first key is the rest texture.
  if (typeof value === "number") return value;
  if (value && value.Keys && value.Keys.length) return value.Keys[0].Vector[0];
  return undefined;
}

function resolveTexture(model, id, modelDir, dirListing) {
  if (id === undefined || id === null) return { file: null, source: null };
  const tex = model.Textures[id];
  if (!tex || !tex.Image) return { file: null, source: null };
  const base = tex.Image.split(/[\\/]/).pop();
  const stem = base.replace(/\.[^.]+$/, "");
  const match = dirListing.find((f) => f.toLowerCase() === `${stem}.dds`.toLowerCase());
  // A copy removed by dedupe_textures.js resolves to the kept file's res:// path.
  const dir = resPath(modelDir).toLowerCase() + "/";
  const linked = match ? null : Object.entries(loadLinks()).find(([from]) => from.toLowerCase() === `${dir}${stem}.dds`.toLowerCase());
  return { file: match || (linked && linked[1]) || null, source: tex.Image };
}

function alphaAt(anim, frame) {
  if (anim === undefined || anim === null) return 1;
  if (typeof anim === "number") return anim;
  if (!anim.Keys || anim.Keys.length === 0) return 1;
  if (anim.GlobalSeqId !== null && anim.GlobalSeqId !== undefined) return anim.Keys[0].Vector[0];
  let value = anim.Keys[0].Vector[0];
  for (const key of anim.Keys) {
    if (key.Frame <= frame) value = key.Vector[0];
    else break;
  }
  return value;
}

function sequenceVisibility(model, geosetIndex, seq) {
  const ga = (model.GeosetAnims || []).find((g) => g.GeosetId === geosetIndex);
  if (!ga) return true;
  let total = 0;
  for (let i = 0; i < ALPHA_SAMPLES; ++i) {
    const frame = seq.Interval[0] + ((seq.Interval[1] - seq.Interval[0]) * (i + 0.5)) / ALPHA_SAMPLES;
    total += alphaAt(ga.Alpha, frame);
  }
  return total / ALPHA_SAMPLES > VISIBLE_MEAN_ALPHA;
}

function buildSidecar(model, mdxPath, scale) {
  const modelDir = path.dirname(mdxPath);
  const dirListing = fs.readdirSync(modelDir);
  const sequences = model.Sequences.map((s) => ({
    name: s.Name,
    start: s.Interval[0],
    end: s.Interval[1],
    // WC3 ground speed the clip is authored for, in exported metres/sec.
    move_speed: (s.MoveSpeed || 0) * scale,
    duplicate_of: null,
  }));
  sequences.forEach((s, i) => {
    const earlier = sequences.slice(0, i).find((o) => o.start === s.start && o.end === s.end);
    if (earlier) s.duplicate_of = earlier.name;
  });

  const standSeq = model.Sequences.find((s) => STAND_PATTERN.test(s.Name)) || model.Sequences[0];
  const geosets = model.Geosets.map((g, gi) => {
    const material = model.Materials[g.MaterialID];
    const layer0 = material.Layers[0] || {};
    const slots = textureSlots(model, material);
    const textures = {};
    const sources = {};
    const missing = [];
    for (const slot of Object.keys(V1000_SLOT_LAYERS)) {
      const r = resolveTexture(model, textureIdOf(slots[slot]), modelDir, dirListing);
      textures[slot] = r.file;
      sources[slot] = r.source;
      if (!r.file && r.source && !/Black32|EnvironmentMap/i.test(r.source)) missing.push(`${slot}: ${r.source}`);
    }
    const visibility = {};
    for (const seq of model.Sequences) visibility[seq.Name] = sequenceVisibility(model, gi, seq);
    return {
      index: gi,
      name: g.Name || "",
      // Reforged ships LOD 1-3 copies of each mesh; only LOD 0 is drawn.
      lod: g.LevelOfDetail || 0,
      material_id: g.MaterialID,
      filter_mode: layer0.FilterMode || 0,
      two_sided: !!((layer0.Shading || 0) & 16),
      unshaded: !!((layer0.Shading || 0) & 1),
      textures,
      sources,
      missing,
      visibility,
    };
  });

  // Bounds of the geosets shown in the idle pose, in exported (Y-up) metres.
  const min = [Infinity, Infinity, Infinity];
  const max = [-Infinity, -Infinity, -Infinity];
  model.Geosets.forEach((g, gi) => {
    if (standSeq && !sequenceVisibility(model, gi, standSeq)) return;
    for (let v = 0; v < g.Vertices.length; v += 3) {
      const p = [g.Vertices[v], g.Vertices[v + 2], -g.Vertices[v + 1]];
      for (let c = 0; c < 3; ++c) {
        if (p[c] < min[c]) min[c] = p[c];
        if (p[c] > max[c]) max[c] = p[c];
      }
    }
  });
  const scaled = (a) => a.map((x) => x * scale);

  return {
    source: path.basename(mdxPath),
    version: model.Version,
    scale,
    idle_sequence: standSeq ? standSeq.Name : null,
    bounds: { min: scaled(min), max: scaled(max), height: (max[1] - min[1]) * scale },
    sequences,
    geosets,
  };
}

module.exports = { buildSidecar };
