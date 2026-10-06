// Pulls the base-game textures a model references but doesn't ship with
// (e.g. "Units/Creeps/Brigand/Unit_Brigand_Main_Diffuse.tif") out of a local
// Warcraft III Reforged install, as .dds files next to the model. Only the
// referenced files are extracted.
// Usage: node wc3_textures.js <wc3_install_dir> <model.mdx> [...more .mdx]
const fs = require("fs");
const path = require("path");
const { CascStorage } = require("./casc_reader");
const { loadModel } = require("./mdx_load");

// Reforged keeps game-ready textures in the _hd/_de mods; cutscene copies are a fallback.
const MOD_PREFIXES = ["war3.w3mod:_hd.w3mod:", "war3.w3mod:_de.w3mod:", "war3.w3mod:"];
const SKIP = /(^|[\\/])(black32|white|environmentmap)\.[a-z]+$/i;

function normalize(texturePath) {
  return texturePath.replace(/\\/g, "/").toLowerCase().replace(/\.[a-z0-9]+$/, ".dds");
}

class TextureFetcher {
  constructor(installDir) {
    this.storage = new CascStorage(installDir);
    this.files = this.storage.listFiles();
    this.byName = new Map();
    for (const key of this.files.keys()) {
      if (!key.endsWith(".dds")) continue;
      const base = key.slice(key.lastIndexOf("/") + 1);
      if (!this.byName.has(base)) this.byName.set(base, []);
      this.byName.get(base).push(key);
    }
  }

  // CASC path for a model's texture reference, or null.
  resolve(texturePath) {
    const rel = normalize(texturePath);
    for (const prefix of MOD_PREFIXES) {
      if (this.files.has(prefix + rel)) return prefix + rel;
    }
    const candidates = (this.byName.get(rel.slice(rel.lastIndexOf("/") + 1)) || [])
      .filter((k) => !k.includes("_locales/"));
    candidates.sort((a, b) => rank(a) - rank(b));
    return candidates[0] || null;
  }

  // Extracts every referenced texture missing from the model's folder.
  // Returns { fetched: [...], unresolved: [...] }.
  fetchForModel(mdxPath) {
    const model = loadModel(mdxPath);
    const dir = path.dirname(mdxPath);
    const present = new Set(fs.readdirSync(dir).map((f) => f.toLowerCase()));
    const fetched = [];
    const unresolved = [];
    for (const tex of model.Textures) {
      if (!tex.Image || SKIP.test(tex.Image)) continue;
      const fileName = path.basename(normalize(tex.Image));
      if (present.has(fileName)) continue;
      const caseInsensitiveLocal = fs.readdirSync(dir).find((f) => f.toLowerCase() === fileName);
      if (caseInsensitiveLocal) continue;
      const cascPath = this.resolve(tex.Image);
      const data = cascPath ? this.storage.readFile(cascPath) : null;
      if (!data) {
        unresolved.push(tex.Image);
        continue;
      }
      fs.writeFileSync(path.join(dir, fileName), data);
      present.add(fileName);
      fetched.push(`${fileName} <- ${cascPath}`);
    }
    return { fetched, unresolved };
  }

  close() {
    this.storage.close();
  }
}

function rank(key) {
  if (key.includes(":_hd.w3mod:") && !key.includes("cutscenes/")) return 0;
  if (key.includes(":_de.w3mod:")) return 1;
  if (key.includes("cutscenes/")) return 3;
  return 2;
}

if (require.main === module) {
  const [, , installDir, ...models] = process.argv;
  if (!installDir || models.length === 0) {
    console.error("Usage: node wc3_textures.js <wc3_install_dir> <model.mdx> [...]");
    process.exit(1);
  }
  const fetcher = new TextureFetcher(installDir);
  for (const m of models) {
    const { fetched, unresolved } = fetcher.fetchForModel(path.resolve(m));
    console.log(`${path.basename(m)}: ${fetched.length} fetched, ${unresolved.length} unresolved`);
    unresolved.forEach((u) => console.log(`  unresolved: ${u}`));
  }
  fetcher.close();
}

module.exports = { TextureFetcher };
