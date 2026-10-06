// Converts every model in models.json (or only the units named on the
// command line), writing <name>.glb + <name>.mdxmeta.json next to each .mdx.
// If models.json names a wc3_install, missing base-game textures are pulled
// from it first (see wc3_textures.js).
const fs = require("fs");
const path = require("path");
const { convert } = require("./mdx_to_gltf");
const manifest = require("./models.json");

const root = path.resolve(__dirname, "../..");
const only = process.argv.slice(2);
const entries = manifest.models.filter((e) => !only.length || only.includes(e.unit));

let fetcher = null;
if (manifest.wc3_install && fs.existsSync(path.join(manifest.wc3_install, ".build.info"))) {
  const { TextureFetcher } = require("./wc3_textures");
  fetcher = new TextureFetcher(manifest.wc3_install);
} else if (manifest.wc3_install) {
  console.warn(`wc3_install not found (${manifest.wc3_install}) - skipping texture extraction`);
}

for (const entry of entries) {
  const mdx = path.join(root, entry.mdx);
  const out = mdx.replace(/.mdx$/i, ".glb");
  console.log(`== ${entry.unit}`);
  if (fetcher) {
    const { fetched, unresolved } = fetcher.fetchForModel(mdx);
    console.log(`  textures: ${fetched.length} extracted, ${unresolved.length} not in the install`);
    unresolved.forEach((u) => console.log(`    not found: ${u}`));
  }
  convert(mdx, out, entry.scale, true);
}
if (fetcher) fetcher.close();
