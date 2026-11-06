// Shared MDX loader. war3-model 4.0.1 rejects some Reforged (v1200) light
// records that carry extra bytes after the fixed light fields (e.g.
// heropaladin.mdx, the v1800 doodads) and some camera records. Neither is exported,
// so they're fixed up before parsing rather than patching node_modules.
const fs = require("fs");
const war3 = require("war3-model");

const LIGHT_FIXED_BYTES = 44; // type, attenuation x2, color x3, intensity, amb color x3, amb intensity
// Chunks dropped before parsing: war3-model misreads some Reforged camera
// records (dungeonarchway1.mdx), and cameras are neither exported nor nodes.
const DROPPED_CHUNKS = new Set(["CAMS"]);
const LIGHT_TRACKS = new Set(["KLAV", "KLAC", "KLAI", "KLBC", "KLBI", "KLAS", "KLAE"]);

function stripLightExtras(buf) {
  const out = [];
  let pos = 4; // "MDLX"
  out.push(buf.subarray(0, 4));
  while (pos + 8 <= buf.length) {
    const tag = buf.toString("latin1", pos, pos + 4);
    const size = buf.readUInt32LE(pos + 4);
    const body = buf.subarray(pos + 8, pos + 8 + size);
    pos += 8 + size;
    if (DROPPED_CHUNKS.has(tag)) continue;
    if (tag !== "LITE") {
      out.push(buf.subarray(pos - 8 - size, pos));
      continue;
    }
    const lights = [];
    let q = 0;
    while (q < body.length) {
      const lightSize = body.readUInt32LE(q);
      const light = Buffer.from(body.subarray(q, q + lightSize));
      const fixedStart = 4 + light.readUInt32LE(4);
      const extraAt = fixedStart + LIGHT_FIXED_BYTES;
      // Newer versions append extra fields (4 bytes in v1200, 28 in v1800)
      // before the animation tracks; drop up to the first track keyword.
      let tracksAt = extraAt;
      while (tracksAt < lightSize && !LIGHT_TRACKS.has(light.toString("latin1", tracksAt, tracksAt + 4))) tracksAt += 4;
      if (tracksAt > extraAt) {
        const fixed = Buffer.concat([light.subarray(0, extraAt), light.subarray(tracksAt)]);
        fixed.writeUInt32LE(fixed.length, 0);
        lights.push(fixed);
      } else {
        lights.push(light);
      }
      q += lightSize;
    }
    const newBody = Buffer.concat(lights);
    const header = Buffer.alloc(8);
    header.write("LITE", 0, "latin1");
    header.writeUInt32LE(newBody.length, 4);
    out.push(header, newBody);
  }
  return Buffer.concat(out);
}

// Blizzard's v1800 unit models count SKIN in 16-bit values: each vertex is
// 4 u16 joint indices + 4 u16 weights (16 bytes), where war3-model reads the
// count as bytes (4 u8 joints + 4 u8 weights). Repack such chunks to the u8
// layout. Detected by UVAS following at 2*count instead of at count.
function repackWideSkins(buf) {
  const out = [buf.subarray(0, 4)];
  let pos = 4;
  while (pos + 8 <= buf.length) {
    const tag = buf.toString("latin1", pos, pos + 4);
    const size = buf.readUInt32LE(pos + 4);
    const chunk = buf.subarray(pos, pos + 8 + size);
    pos += 8 + size;
    if (tag !== "GEOS") {
      out.push(chunk);
      continue;
    }
    const body = chunk.subarray(8);
    const geosets = [];
    let q = 0;
    while (q < body.length) {
      const gsize = body.readUInt32LE(q);
      geosets.push(repackGeosetSkin(Buffer.from(body.subarray(q, q + gsize))));
      q += gsize;
    }
    const newBody = Buffer.concat(geosets);
    const header = Buffer.alloc(8);
    header.write("GEOS", 0, "latin1");
    header.writeUInt32LE(newBody.length, 4);
    out.push(header, newBody);
  }
  return Buffer.concat(out);
}

function repackGeosetSkin(g) {
  let at = g.indexOf("SKIN", 4, "latin1");
  while (at >= 0) {
    const n = g.readUInt32LE(at + 4);
    const narrowNext = g.toString("latin1", at + 8 + n, at + 12 + n);
    const wideNext = g.toString("latin1", at + 8 + 2 * n, at + 12 + 2 * n);
    if (narrowNext !== "UVAS" && wideNext === "UVAS" && n % 8 === 0) {
      const packed = Buffer.alloc(n);
      for (let v = 0; v < n / 8; ++v) {
        for (let c = 0; c < 8; ++c) packed[v * 8 + c] = Math.min(g.readUInt16LE(at + 8 + v * 16 + c * 2), 255);
      }
      const fixed = Buffer.concat([g.subarray(0, at + 8), packed, g.subarray(at + 8 + 2 * n)]);
      fixed.writeUInt32LE(fixed.length, 0);
      return fixed;
    }
    if (narrowNext === "UVAS") return g;
    at = g.indexOf("SKIN", at + 4, "latin1");
  }
  return g;
}

function loadModel(mdxPath) {
  const buffer = repackWideSkins(stripLightExtras(fs.readFileSync(mdxPath)));
  const arrayBuffer = buffer.buffer.slice(buffer.byteOffset, buffer.byteOffset + buffer.byteLength);
  return war3.parseMDX(arrayBuffer);
}

module.exports = { loadModel, stripLightExtras };
