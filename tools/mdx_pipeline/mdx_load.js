// Shared MDX loader. war3-model 4.0.1 rejects some Reforged (v1200) light
// records that carry 4 extra bytes after the fixed light fields (e.g.
// heropaladin.mdx's LITE chunk). Lights aren't exported, so those bytes are
// stripped before parsing rather than patching node_modules.
const fs = require("fs");
const war3 = require("war3-model");

const LIGHT_FIXED_BYTES = 44; // type, attenuation x2, color x3, intensity, amb color x3, amb intensity

function stripLightExtras(buf) {
  const out = [];
  let pos = 4; // "MDLX"
  out.push(buf.subarray(0, 4));
  while (pos + 8 <= buf.length) {
    const tag = buf.toString("latin1", pos, pos + 4);
    const size = buf.readUInt32LE(pos + 4);
    const body = buf.subarray(pos + 8, pos + 8 + size);
    pos += 8 + size;
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
      const hasExtra = lightSize >= extraAt + 4 && light.toString("latin1", extraAt, extraAt + 2) !== "KL";
      if (hasExtra) {
        const fixed = Buffer.concat([light.subarray(0, extraAt), light.subarray(extraAt + 4)]);
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

function loadModel(mdxPath) {
  const buffer = stripLightExtras(fs.readFileSync(mdxPath));
  const arrayBuffer = buffer.buffer.slice(buffer.byteOffset, buffer.byteOffset + buffer.byteLength);
  return war3.parseMDX(arrayBuffer);
}

module.exports = { loadModel, stripLightExtras };
