// Caps .dds texture resolution under assets/models/ by dropping top mip
// levels. Each mip is already a filtered, block-compressed downscale, so this
// is lossless beyond the resolution cut: no re-encoding. Godot ships .dds
// files as-is, so on-disk size is build size.
// Usage: node texture_budget.js [dir] [--dry-run]
const fs = require("fs");
const path = require("path");

// Longest-side caps (px) per texture role. Ground sheets are atlases of
// 256 px cells seen right at the player's feet, so their colour and normal
// maps keep full resolution.
const BUDGET = {
  model: { diffuse: 1024, normal: 1024, orm: 512, emissive: 512 },
  ground: { diffuse: Infinity, normal: Infinity, orm: 1024, emissive: 512 },
};

const BLOCK_BYTES = { DXT1: 8, ATI1: 8, BC4U: 8, DXT3: 16, DXT5: 16, ATI2: 16, BC5U: 16 };
const DDSD_MIPMAPCOUNT = 0x20000;
const DDSD_LINEARSIZE = 0x80000;

function role(file) {
  const name = path.basename(file).toLowerCase();
  if (/normal/.test(name)) return "normal";
  if (/(^|_)orm[._]/.test(name)) return "orm";
  if (/emm?issive|_emis[._]|glow/.test(name)) return "emissive";
  return "diffuse";
}

function category(file) {
  return /[\\/]ground[\\/]/i.test(file) ? "ground" : "model";
}

function levelBytes(w, h, blockBytes) {
  return Math.max(1, Math.ceil(w / 4)) * Math.max(1, Math.ceil(h / 4)) * blockBytes;
}

// Returns the shrunk file contents, or null when already within budget or
// not a format this can cut (uncompressed, DX10 header, single mip level).
function shrink(buf, cap) {
  if (buf.toString("latin1", 0, 4) !== "DDS ") return null;
  const blockBytes = BLOCK_BYTES[buf.toString("latin1", 84, 88)];
  if (!blockBytes) return null;
  let h = buf.readUInt32LE(12);
  let w = buf.readUInt32LE(16);
  let mips = Math.max(1, buf.readUInt32LE(28));
  let offset = 128;
  let drop = 0;
  while (Math.max(w, h) > cap && mips - drop > 1) {
    offset += levelBytes(w, h, blockBytes);
    w = Math.max(1, w >> 1);
    h = Math.max(1, h >> 1);
    drop++;
  }
  if (drop === 0) return null;
  const header = Buffer.from(buf.subarray(0, 128));
  header.writeUInt32LE(h, 12);
  header.writeUInt32LE(w, 16);
  header.writeUInt32LE(levelBytes(w, h, blockBytes), 20);
  header.writeUInt32LE(mips - drop, 28);
  header.writeUInt32LE(header.readUInt32LE(8) | DDSD_LINEARSIZE | (mips - drop > 1 ? DDSD_MIPMAPCOUNT : 0), 8);
  return Buffer.concat([header, buf.subarray(offset)]);
}

function walk(dir) {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((e) =>
    e.isDirectory() ? walk(path.join(dir, e.name)) : [path.join(dir, e.name)]);
}

function apply(dir, dryRun = false) {
  let before = 0;
  let after = 0;
  let changed = 0;
  for (const file of walk(dir).filter((f) => /\.dds$/i.test(f))) {
    const buf = fs.readFileSync(file);
    const out = shrink(buf, BUDGET[category(file)][role(file)]);
    before += buf.length;
    after += out ? out.length : buf.length;
    if (!out) continue;
    changed++;
    if (!dryRun) fs.writeFileSync(file, out);
  }
  return { before, after, changed };
}

if (require.main === module) {
  const args = process.argv.slice(2);
  const dryRun = args.includes("--dry-run");
  const dir = path.resolve(args.find((a) => !a.startsWith("--")) || path.join(__dirname, "../../assets/models"));
  const { before, after, changed } = apply(dir, dryRun);
  const mb = (n) => (n / 1048576).toFixed(0);
  console.log(`${dryRun ? "[dry run] " : ""}${changed} textures cut: ${mb(before)} MB -> ${mb(after)} MB`);
}

module.exports = { apply, shrink, BUDGET };
