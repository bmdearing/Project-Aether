// Converts classic WC3 .blp textures to .png next to the model, so Godot can
// import them (it has no BLP loader). The sidecar resolves a texture to a .png
// when no .dds of the same name exists.
//
//   node blp_to_png.js <dir> [--flatten]
//
// Every .blp under <dir> is converted. --flatten writes PNGs from subfolders
// (e.g. war3mapImported/) into <dir> itself, since the sidecar matches
// textures by basename in the model's own folder.
const fs = require("fs");
const path = require("path");
const zlib = require("zlib");
const { decodeBLP, getBLPImageData } = require("war3-model");

const CRC_TABLE = new Uint32Array(256).map((_, n) => {
  let c = n;
  for (let k = 0; k < 8; ++k) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  return c >>> 0;
});

function crc32(buf) {
  let c = 0xffffffff;
  for (const b of buf) c = CRC_TABLE[(c ^ b) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  const body = Buffer.concat([Buffer.from(type, "ascii"), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body));
  return Buffer.concat([len, body, crc]);
}

function encodePng(width, height, rgba) {
  const header = Buffer.alloc(13);
  header.writeUInt32BE(width, 0);
  header.writeUInt32BE(height, 4);
  header[8] = 8; // bit depth
  header[9] = 6; // RGBA
  const raw = Buffer.alloc((width * 4 + 1) * height);
  for (let y = 0; y < height; ++y) {
    raw[y * (width * 4 + 1)] = 0; // filter: none
    Buffer.from(rgba.buffer, rgba.byteOffset + y * width * 4, width * 4).copy(raw, y * (width * 4 + 1) + 1);
  }
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk("IHDR", header),
    chunk("IDAT", zlib.deflateSync(raw, { level: 9 })),
    chunk("IEND", Buffer.alloc(0)),
  ]);
}

function convert(blpPath, pngPath) {
  const bytes = fs.readFileSync(blpPath);
  const blp = decodeBLP(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength));
  const image = getBLPImageData(blp, 0);
  // BLP without an alpha channel decodes alpha as 0; force it opaque.
  const rgba = new Uint8Array(image.data);
  if (!blp.alphaBits) for (let i = 3; i < rgba.length; i += 4) rgba[i] = 255;
  fs.writeFileSync(pngPath, encodePng(image.width, image.height, rgba));
  return `${image.width}x${image.height} alpha=${blp.alphaBits}`;
}

function walk(dir) {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((e) =>
    e.isDirectory() ? walk(path.join(dir, e.name)) : e.name.toLowerCase().endsWith(".blp") ? [path.join(dir, e.name)] : []);
}

if (require.main === module) {
  const [dir, ...flags] = process.argv.slice(2);
  if (!dir) {
    console.error("usage: node blp_to_png.js <dir> [--flatten]");
    process.exit(1);
  }
  const flatten = flags.includes("--flatten");
  for (const blpPath of walk(dir)) {
    const outDir = flatten ? dir : path.dirname(blpPath);
    const pngPath = path.join(outDir, path.basename(blpPath).replace(/\.blp$/i, ".png"));
    console.log(`${path.relative(dir, blpPath)} -> ${path.relative(dir, pngPath)} (${convert(blpPath, pngPath)})`);
  }
}

module.exports = { convert };
