// Back-fills fields added to the sidecar format (per-sequence move_speed,
// per-geoset lod) into every existing .mdxmeta.json under assets/models,
// without reconverting the .glb.
const fs = require("fs");
const path = require("path");
const { loadModel } = require("./mdx_load");

const root = path.resolve(__dirname, "../../assets/models");
function walk(dir, out) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (e.name.endsWith(".mdxmeta.json")) out.push(p);
  }
  return out;
}
let patched = 0;
for (const metaPath of walk(root, [])) {
  const mdx = metaPath.replace(/\.mdxmeta\.json$/, ".mdx");
  if (!fs.existsSync(mdx)) continue;
  const meta = JSON.parse(fs.readFileSync(metaPath, "utf8"));
  const model = loadModel(mdx);
  for (const seq of meta.sequences) {
    const src = model.Sequences.find((s) => s.Name === seq.name);
    seq.move_speed = ((src && src.MoveSpeed) || 0) * meta.scale;
  }
  for (const g of meta.geosets) g.lod = (model.Geosets[g.index] && model.Geosets[g.index].LevelOfDetail) || 0;
  fs.writeFileSync(metaPath, JSON.stringify(meta, null, 2));
  patched++;
}
console.log(`patched ${patched} sidecars`);
