// Fills SoundLibrary slots and ambience loops with Warcraft III sounds from
// the local install (wc3_library.json says which file goes where).
//   node wc3_library.js            extract + rewrite data/sound/sound_library.tres
// Each slot's files are written to <out_dir>/<slot>_<n>.ogg; the slot's line
// in sound_library.tres is replaced and ext_resources nothing uses any more
// are dropped. Ambience loops overwrite assets/sfx/ambience/<id>.ogg.
// Afterwards run Godot --headless --path . --import.
const fs = require("fs");
const path = require("path");
const { CascStorage } = require("./casc_reader");

const root = path.resolve(__dirname, "../..");
const manifest = JSON.parse(fs.readFileSync(path.join(__dirname, "wc3_library.json"), "utf8"));
const LIB = path.join(root, "data/sound/sound_library.tres");
const ARRAY_SLOTS = new Set();
for (const m of fs.readFileSync(path.join(root, "data/sound/SoundLibrary.gd"), "utf8").matchAll(/@export var (\w+): Array\[AudioStream\]/g)) ARRAY_SLOTS.add(m[1]);

const storage = new CascStorage(require("./models.json").wc3_install);
const keys = [...storage.listFiles().keys()].filter((k) => /\.ogg$/i.test(k) && !k.includes("_locales/"));

function read(rel) {
  const hits = keys.filter((k) => k.endsWith(":" + rel)).sort((a, b) => (b.includes("_hd.w3mod") ? 1 : 0) - (a.includes("_hd.w3mod") ? 1 : 0));
  const data = hits.length ? storage.readFile(hits[0]) : null;
  if (!data) throw new Error("not in the install: " + rel);
  return data;
}

// ---- Slots ----
const outDir = path.join(root, manifest.out_dir);
fs.mkdirSync(outDir, { recursive: true });
let tres = fs.readFileSync(LIB, "utf8").replace(/\r\n/g, "\n");
const header = tres.slice(0, tres.indexOf("[resource]"));
let body = tres.slice(tres.indexOf("[resource]"));
const extLines = header.split("\n").filter((l) => l.startsWith("[ext_resource"));
const newExt = [];
let nextId = 1;
const usedIds = new Set(extLines.map((l) => l.match(/id="([^"]+)"/)[1]));
const newId = () => { while (usedIds.has("w" + nextId)) nextId++; usedIds.add("w" + nextId); return "w" + nextId; };

for (const [slot, files] of Object.entries(manifest.slots)) {
  const ids = files.map((rel, i) => {
    const name = files.length > 1 ? `${slot}_${String(i + 1).padStart(2, "0")}.ogg` : `${slot}.ogg`;
    fs.writeFileSync(path.join(outDir, name), read(rel));
    const id = newId();
    newExt.push(`[ext_resource type="AudioStream" path="res://${manifest.out_dir}/${name}" id="${id}"]`);
    return id;
  });
  const value = ARRAY_SLOTS.has(slot)
    ? `Array[AudioStream]([${ids.map((id) => `ExtResource("${id}")`).join(", ")}])`
    : `ExtResource("${ids[0]}")`;
  const line = `${slot} = ${value}`;
  const re = new RegExp(`^${slot} = .*$`, "m");
  body = re.test(body) ? body.replace(re, line) : body.replace(/\n*$/, `\n${line}\n`);
  console.log(`${slot}: ${files.length}`);
}

// Drop ext_resources nothing references any more.
const allExt = [...extLines, ...newExt];
const kept = allExt.filter((l) => {
  const id = l.match(/id="([^"]+)"/)[1];
  return l.includes('type="Script"') || body.includes(`ExtResource("${id}")`);
});
const first = header.split("\n")[0].replace(/load_steps=\d+/, `load_steps=${kept.length + 1}`);
tres = `${first}\n\n${kept.join("\n")}\n\n${body.replace(/\n*$/, "\n")}`;
fs.writeFileSync(LIB, tres);
console.log(`sound_library.tres: ${kept.length} ext_resources (${allExt.length - kept.length} dropped)`);

// ---- Ambience ----
for (const [id, rel] of Object.entries(manifest.ambience || {})) {
  fs.writeFileSync(path.join(root, manifest.ambience_dir, id + ".ogg"), read(rel));
  console.log(`ambience ${id} <- ${rel}`);
}
storage.close();
