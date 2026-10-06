// Adds per-sequence move_speed to existing .mdxmeta.json sidecars without
// reconverting the .glb (convert_all.js writes it for new conversions).
const fs = require("fs");
const path = require("path");
const { loadModel } = require("./mdx_load");
const manifest = require("./models.json");

const root = path.resolve(__dirname, "../..");
for (const entry of manifest.models) {
  const mdx = path.join(root, entry.mdx);
  const metaPath = mdx.replace(/\.mdx$/i, ".mdxmeta.json");
  if (!fs.existsSync(metaPath)) continue;
  const meta = JSON.parse(fs.readFileSync(metaPath, "utf8"));
  const model = loadModel(mdx);
  for (const seq of meta.sequences) {
    const src = model.Sequences.find((s) => s.Name === seq.name);
    seq.move_speed = ((src && src.MoveSpeed) || 0) * meta.scale;
  }
  fs.writeFileSync(metaPath, JSON.stringify(meta, null, 2));
  console.log(entry.unit, meta.sequences.filter((s) => s.move_speed > 0).map((s) => `${s.name}=${s.move_speed.toFixed(2)}`).join(" "));
}
