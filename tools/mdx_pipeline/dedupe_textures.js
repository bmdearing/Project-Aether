// Removes byte-identical .dds copies under assets/models/ (the same base-game
// texture extracted next to every model that uses it). One copy is kept and
// every reference is pointed at it: res:// paths in scenes/resources/scripts,
// and sidecar texture entries, which then hold the kept file's res:// path
// instead of a basename. texture_links.json records removed -> kept so later
// conversions (mdx_sidecar.js) resolve a removed copy to the kept one.
// Usage: node dedupe_textures.js [--dry-run]
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");

const root = path.resolve(__dirname, "../..");
const modelsDir = path.join(root, "assets/models");
const linksPath = path.join(__dirname, "texture_links.json");
const TEXT_EXT = /\.(tscn|tres|gd|gdshader)$/;
const SKIP_DIRS = new Set([".git", ".godot", "node_modules", "builds"]);

function walk(dir) {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((e) => {
    if (e.isDirectory()) return SKIP_DIRS.has(e.name) ? [] : walk(path.join(dir, e.name));
    return [path.join(dir, e.name)];
  });
}

const resPath = (file) => "res://" + path.relative(root, file).split(path.sep).join("/");
const loadLinks = () => (fs.existsSync(linksPath) ? JSON.parse(fs.readFileSync(linksPath, "utf8")) : {});

function dedupe(dryRun = false) {
  const links = loadLinks();
  const targets = new Set(Object.values(links));
  const groups = new Map();
  for (const file of walk(modelsDir).filter((f) => /\.dds$/i.test(f))) {
    const hash = crypto.createHash("md5").update(fs.readFileSync(file)).digest("hex");
    if (!groups.has(hash)) groups.set(hash, []);
    groups.get(hash).push(resPath(file));
  }
  const removed = {};
  let bytes = 0;
  for (const paths of groups.values()) {
    if (paths.length < 2) continue;
    // Keep an existing link target so earlier links stay valid, else the first path.
    paths.sort();
    const keep = paths.find((p) => targets.has(p)) || paths[0];
    for (const p of paths) if (p !== keep) removed[p] = keep;
  }
  Object.assign(links, removed);
  // Re-point links whose target was itself just removed.
  for (const [from, to] of Object.entries(links)) links[from] = removed[to] || to;

  // Scenes, resources and scripts referencing a removed copy by path.
  const refs = Object.keys(links);
  let edited = 0;
  for (const file of walk(root).filter((f) => TEXT_EXT.test(f))) {
    const text = fs.readFileSync(file, "utf8");
    let out = text;
    for (const from of refs) if (out.includes(from)) out = out.split(from).join(links[from]);
    if (out === text) continue;
    edited++;
    if (!dryRun) fs.writeFileSync(file, out);
  }
  // Sidecars name their textures by basename, relative to the model's folder.
  for (const file of walk(modelsDir).filter((f) => f.endsWith(".mdxmeta.json"))) {
    const meta = JSON.parse(fs.readFileSync(file, "utf8"));
    const dir = resPath(path.dirname(file)) + "/";
    let changed = false;
    for (const g of meta.geosets) {
      for (const [slot, name] of Object.entries(g.textures)) {
        const target = name && !name.startsWith("res://") ? links[dir + name] : null;
        if (!target) continue;
        g.textures[slot] = target;
        changed = true;
      }
    }
    if (!changed) continue;
    edited++;
    if (!dryRun) fs.writeFileSync(file, JSON.stringify(meta, null, 2));
  }

  for (const p of Object.keys(removed)) {
    const file = path.join(root, p.slice("res://".length));
    bytes += fs.statSync(file).size;
    if (dryRun) continue;
    fs.unlinkSync(file);
    if (fs.existsSync(file + ".uid")) fs.unlinkSync(file + ".uid");
  }
  if (!dryRun) {
    const sorted = Object.fromEntries(Object.entries(links).sort(([a], [b]) => a.localeCompare(b)));
    fs.writeFileSync(linksPath, JSON.stringify(sorted, null, 2) + "\n");
  }
  return { removed: Object.keys(removed).length, bytes, edited };
}

if (require.main === module) {
  const dryRun = process.argv.includes("--dry-run");
  const { removed, bytes, edited } = dedupe(dryRun);
  console.log(`${dryRun ? "[dry run] " : ""}${removed} duplicate textures removed (${(bytes / 1048576).toFixed(0)} MB), ${edited} files re-pointed`);
}

module.exports = { dedupe, loadLinks, resPath };
