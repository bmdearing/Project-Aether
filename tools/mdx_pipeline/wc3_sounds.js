// Extracts named WC3 sounds (.ogg) from the local install into the project.
//   node wc3_sounds.js <manifest.json>
// manifest: {"out_dir": "assets/sfx/x", "sounds": {"name": "casc/rel/path.ogg", ...}}
const fs = require("fs");
const path = require("path");
const { CascStorage } = require("./casc_reader");
const manifest = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
const root = path.resolve(__dirname, "../..");
const s = new CascStorage(require("./models.json").wc3_install);
const keys = [...s.listFiles().keys()].filter((k) => /\.ogg$/i.test(k) && !k.includes("_locales/"));
const out = path.join(root, manifest.out_dir);
fs.mkdirSync(out, { recursive: true });
for (const [name, rel] of Object.entries(manifest.sounds)) {
  // Prefer the HD (Reforged) copy, then the default one.
  const hits = keys.filter((k) => k.endsWith(":" + rel)).sort((a, b) => (b.includes("_hd.w3mod") ? 1 : 0) - (a.includes("_hd.w3mod") ? 1 : 0));
  const data = hits.length ? s.readFile(hits[0]) : null;
  if (!data) { console.log("not found:", rel); continue; }
  fs.writeFileSync(path.join(out, name + ".ogg"), data);
  console.log(`${name}.ogg <- ${hits[0]} (${data.length} bytes)`);
}
s.close();
