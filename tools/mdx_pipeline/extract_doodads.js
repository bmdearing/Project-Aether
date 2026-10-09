// Extracts each tileset family in doodads.json from the local WC3 install:
// doodad models (+ their textures, converted to .glb + sidecar) and ground
// textures. Only the listed files are pulled. Rerunning skips files that
// already exist. Usage: node extract_doodads.js [family ...]
const fs = require("fs");
const path = require("path");
const { convert } = require("./mdx_to_gltf");
const { TextureFetcher } = require("./wc3_textures");
const manifest = require("./doodads.json");
const { wc3_install: installDir } = require("./models.json");

const root = path.resolve(__dirname, "../..");
const MOD_PREFIX = "war3.w3mod:_hd.w3mod:";
const GROUND_PREFIX = MOD_PREFIX + "terrainart/";
const GROUND_MAPS = ["diffuse", "normal", "orm"];

const only = process.argv.slice(2);
const fetcher = new TextureFetcher(installDir);
const storage = fetcher.storage;

function writeIfMissing(file, cascPath) {
  if (fs.existsSync(file)) return true;
  const data = storage.readFile(cascPath);
  if (!data) {
    console.log(`  not in the install: ${cascPath}`);
    return false;
  }
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, data);
  return true;
}

for (const [family, kit] of Object.entries(manifest.families)) {
  if (only.length && !only.includes(family)) continue;
  console.log(`== ${family}`);
  const dir = path.join(root, kit.dir);
  for (const [role, models] of Object.entries(kit.roles)) {
    for (const cascRel of models) {
      const mdx = path.join(dir, path.basename(cascRel));
      if (!writeIfMissing(mdx, MOD_PREFIX + cascRel)) continue;
      const { unresolved } = fetcher.fetchForModel(mdx);
      unresolved.forEach((u) => console.log(`  texture not found: ${u}`));
      const glb = mdx.replace(/\.mdx$/i, ".glb");
      if (!fs.existsSync(glb)) convert(mdx, glb, kit.scale, true);
      console.log(`  ${role}: ${path.basename(mdx)}`);
    }
  }
  // Models drawn with a WC3 replaceable texture (trees) have no texture of
  // their own: every untextured geoset gets the one named in kit.replaceable.
  for (const [model, stem] of Object.entries(kit.replaceable || {})) {
    const metaPath = path.join(dir, model.replace(/.mdx$/i, ".mdxmeta.json"));
    if (!fs.existsSync(metaPath)) continue;
    const base = path.basename(stem);
    for (const map of GROUND_MAPS) writeIfMissing(path.join(dir, `${base}_${map}.dds`), `${MOD_PREFIX}${stem}_${map}.dds`);
    const meta = JSON.parse(fs.readFileSync(metaPath, "utf8"));
    for (const g of meta.geosets) {
      if (g.textures.diffuse) continue;
      for (const map of GROUND_MAPS) g.textures[map] = `${base}_${map}.dds`;
    }
    fs.writeFileSync(metaPath, JSON.stringify(meta, null, 2));
    console.log(`  replaceable: ${model} -> ${base}`);
  }
  const grounds = manifest.grounds[family];
  for (const layout of ["wide", "narrow"]) {
    for (const ground of grounds[layout]) {
      for (const map of GROUND_MAPS) {
        const name = `${path.basename(ground)}_${map}.dds`;
        writeIfMissing(path.join(dir, "ground", name), `${GROUND_PREFIX}${ground}_${map}.dds`);
      }
    }
  }
}
fetcher.close();
// Cap texture resolution and drop duplicate copies (see README: Texture budget).
require("./texture_budget").apply(path.join(root, "assets/models"));
require("./dedupe_textures").dedupe();
