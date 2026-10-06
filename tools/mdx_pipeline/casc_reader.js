// Minimal read-only CASC reader for a local Warcraft III Reforged install
// (no CDN, no encryption). Resolves file paths through the TVFS root.
const fs = require("fs");
const path = require("path");
const zlib = require("zlib");

const EKEY_INDEX_BYTES = 9;
const DATA_HEADER_BYTES = 30;

class CascStorage {
  constructor(installDir) {
    this.dataDir = path.join(installDir, "Data");
    const buildInfo = fs.readFileSync(path.join(installDir, ".build.info"), "utf8").trim().split(/\r?\n/);
    const headers = buildInfo[0].split("|").map((h) => h.split("!")[0]);
    const row = buildInfo.find((line, i) => i > 0 && line.split("|")[headers.indexOf("Active")] === "1") || buildInfo[1];
    this.buildKey = row.split("|")[headers.indexOf("Build Key")];
    this.buildConfig = this._readConfig(this.buildKey);
    this._loadIndices();
    this._fds = new Map();
  }

  _readConfig(key) {
    const text = fs.readFileSync(path.join(this.dataDir, "config", key.slice(0, 2), key.slice(2, 4), key), "utf8");
    const config = {};
    for (const line of text.split(/\r?\n/)) {
      const m = line.match(/^([\w-]+)\s*=\s*(.*)$/);
      if (m) config[m[1]] = m[2].split(" ");
    }
    return config;
  }

  // Latest .idx per bucket (file name = 2 hex bucket + 8 hex version).
  _loadIndices() {
    const latest = new Map();
    for (const file of fs.readdirSync(path.join(this.dataDir, "data"))) {
      const m = file.match(/^([0-9a-f]{2})([0-9a-f]{8})\.idx$/i);
      if (!m) continue;
      const version = parseInt(m[2], 16);
      if (!latest.has(m[1]) || latest.get(m[1]).version < version) latest.set(m[1], { file, version });
    }
    this.index = new Map();
    for (const { file } of latest.values()) {
      const buf = fs.readFileSync(path.join(this.dataDir, "data", file));
      const headerSize = buf.readUInt32LE(0);
      let pos = 8 + headerSize;
      pos = (pos + 15) & ~15;
      const entriesSize = buf.readUInt32LE(pos);
      pos += 8;
      const end = pos + entriesSize;
      for (; pos + 18 <= end; pos += 18) {
        const ekey = buf.toString("hex", pos, pos + EKEY_INDEX_BYTES);
        const hi = buf[pos + 9];
        const lo = buf.readUInt32BE(pos + 10);
        const archive = (hi << 2) | (lo >>> 30);
        const offset = lo & 0x3fffffff;
        const size = buf.readUInt32LE(pos + 14);
        if (!this.index.has(ekey)) this.index.set(ekey, { archive, offset, size });
      }
    }
  }

  _fd(archive) {
    if (!this._fds.has(archive)) {
      const name = `data.${String(archive).padStart(3, "0")}`;
      this._fds.set(archive, fs.openSync(path.join(this.dataDir, "data", name), "r"));
    }
    return this._fds.get(archive);
  }

  hasEKey(ekey) {
    return this.index.has(ekey.slice(0, EKEY_INDEX_BYTES * 2).toLowerCase());
  }

  // Decoded file contents for an encoding key (hex), or null if not stored locally.
  readByEKey(ekey) {
    const entry = this.index.get(ekey.slice(0, EKEY_INDEX_BYTES * 2).toLowerCase());
    if (!entry) return null;
    const raw = Buffer.alloc(entry.size);
    fs.readSync(this._fd(entry.archive), raw, 0, entry.size, entry.offset);
    return decodeBLTE(raw.subarray(DATA_HEADER_BYTES));
  }

  // Map of lowercased path -> array of span EKeys (hex), built from the TVFS
  // root. Nested VFS tables (the vfs-N entries) are expanded with ":" between
  // levels, matching CascLib paths like "war3.w3mod:units/...".
  listFiles() {
    if (this._files) return this._files;
    const vfsKeys = new Map();
    for (const [key, value] of Object.entries(this.buildConfig)) {
      if (/^vfs-\d+$/.test(key)) vfsKeys.set(value[1].slice(0, EKEY_INDEX_BYTES * 2), value[1]);
    }
    this._files = new Map();
    this._parseTvfs(this.readByEKey(this.buildConfig["vfs-root"][1]), "", vfsKeys, 0);
    return this._files;
  }

  _parseTvfs(buf, prefix, vfsKeys, depth) {
    if (buf.toString("latin1", 0, 4) !== "TVFS") throw new Error("not TVFS");
    const ekeySize = buf[6];
    const flags = buf.readInt32BE(8);
    const pathOff = buf.readUInt32BE(12), pathSize = buf.readUInt32BE(16);
    const vfsOff = buf.readUInt32BE(20);
    const cftOff = buf.readUInt32BE(28), cftSize = buf.readUInt32BE(32);
    const cftOffBytes = cftSize > 0xffffff ? 4 : cftSize > 0xffff ? 3 : cftSize > 0xff ? 2 : 1;
    const includesCKey = (flags & 1) !== 0;

    const resolveFile = (vfsEntryOff) => {
      let p = vfsOff + vfsEntryOff;
      const spanCount = buf[p++];
      const ekeys = [];
      for (let i = 0; i < spanCount; ++i) {
        p += 8; // content offset + length
        const cft = buf.readUIntBE(p, cftOffBytes);
        p += cftOffBytes;
        const c = cftOff + cft;
        ekeys.push(buf.toString("hex", c, c + ekeySize));
      }
      void includesCKey;
      return ekeys;
    };

    const walk = (start, end, name) => {
      let p = start;
      // A name fragment with no node value is a prefix of the next valued
      // entry only (implying a separator), not of every later sibling.
      let pending = "";
      while (p < end) {
        let part = "";
        if (buf[p] === 0) { part += "/"; p++; }
        if (p < end && buf[p] !== 0xff) {
          const len = buf[p++];
          part += buf.toString("latin1", p, p + len);
          p += len;
        }
        if (p < end && buf[p] === 0) { part += "/"; p++; }
        if (p < end && buf[p] === 0xff) {
          const value = buf.readUInt32BE(p + 1);
          p += 5;
          const full = name + pending + part;
          pending = "";
          if (value & 0x80000000) {
            const size = (value & 0x7fffffff) - 4;
            walk(p, p + size, full);
            p += size;
          } else {
            const ekeys = resolveFile(value);
            const sub = ekeys.length === 1 && vfsKeys.get(ekeys[0]);
            if (sub && depth < 4) {
              this._parseTvfs(this.readByEKey(sub), prefix + full.replace(/\/+$/, "") + ":", vfsKeys, depth + 1);
            } else {
              this._files.set((prefix + full).replace(/\/+/g, "/").toLowerCase(), ekeys);
            }
          }
        } else {
          pending += part + "/";
        }
      }
    };
    walk(pathOff, pathOff + pathSize, "");
  }

  readFile(filePath) {
    const ekeys = this.listFiles().get(filePath.toLowerCase().replace(/\\/g, "/"));
    if (!ekeys) return null;
    const parts = ekeys.map((k) => this.readByEKey(k));
    return parts.some((p) => p === null) ? null : Buffer.concat(parts);
  }

  close() {
    for (const fd of this._fds.values()) fs.closeSync(fd);
    this._fds.clear();
  }
}

function decodeBLTE(buf) {
  if (buf.toString("latin1", 0, 4) !== "BLTE") throw new Error("not BLTE");
  const headerSize = buf.readUInt32BE(4);
  const chunks = [];
  if (headerSize === 0) {
    chunks.push({ data: buf.subarray(8) });
  } else {
    const count = buf.readUIntBE(9, 3); // byte 8 is a flags byte
    let pos = headerSize;
    for (let i = 0; i < count; ++i) {
      const compSize = buf.readUInt32BE(12 + i * 24);
      chunks.push({ data: buf.subarray(pos, pos + compSize) });
      pos += compSize;
    }
  }
  return Buffer.concat(chunks.map(({ data }) => decodeChunk(data)));
}

function decodeChunk(data) {
  const mode = String.fromCharCode(data[0]);
  if (mode === "N") return data.subarray(1);
  if (mode === "Z") return zlib.inflateSync(data.subarray(1));
  if (mode === "E") throw new Error("encrypted BLTE chunk");
  if (mode === "F") return decodeBLTE(data.subarray(1));
  throw new Error(`unknown BLTE chunk mode ${mode}`);
}

module.exports = { CascStorage, decodeBLTE };
