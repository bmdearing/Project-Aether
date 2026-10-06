// Rewrites a wrong dwPitchOrLinearSize in block-compressed .dds headers,
// which Godot's DDS loader rejects (some exporters write a pitch there).
// Pixel data is untouched. Usage: node fix_dds_headers.js <dir> [--dry-run]
const fs = require("fs");
const path = require("path");

const DDSD_LINEARSIZE = 0x80000;
const BLOCK_BYTES = { DXT1: 8, ATI1: 8, BC4U: 8, DXT3: 16, DXT5: 16, ATI2: 16, BC5U: 16 };

function walk(dir) {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((e) =>
    e.isDirectory() ? walk(path.join(dir, e.name)) : [path.join(dir, e.name)]);
}

const [, , dirArg, flag] = process.argv;
if (!dirArg) {
  console.error("Usage: node fix_dds_headers.js <dir> [--dry-run]");
  process.exit(1);
}
for (const file of walk(path.resolve(dirArg)).filter((f) => /\.dds$/i.test(f))) {
  const buf = fs.readFileSync(file);
  if (buf.toString("latin1", 0, 4) !== "DDS ") continue;
  const flags = buf.readUInt32LE(8);
  const height = buf.readUInt32LE(12);
  const width = buf.readUInt32LE(16);
  const blockBytes = BLOCK_BYTES[buf.toString("latin1", 84, 88)];
  if (!blockBytes || !(flags & DDSD_LINEARSIZE)) continue;
  const expected = Math.max(1, Math.ceil(width / 4)) * Math.max(1, Math.ceil(height / 4)) * blockBytes;
  const actual = buf.readUInt32LE(20);
  if (actual === expected) continue;
  console.log(`${path.basename(file)}: ${actual} -> ${expected}`);
  if (flag !== "--dry-run") {
    buf.writeUInt32LE(expected, 20);
    fs.writeFileSync(file, buf);
  }
}
