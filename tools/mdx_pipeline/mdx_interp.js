// Keyframe evaluation matching war3-model's renderer (dist/war3-model.cjs,
// renderer/interp.ts + modelInterp.ts), which isn't exported. Unlike
// mdx_to_gltf.js's evalVec3, this keeps Hermite/Bezier tangents and WC3's
// per-sequence windowing: only keys inside the playing sequence's interval
// count, and a track with no key in it falls back to the default value.
const { quat } = require("gl-matrix");

const LineType = { DontInterp: 0, Linear: 1, Hermite: 2, Bezier: 3 };

function findKeyframes(av, frame, from, to) {
  const keys = av.Keys;
  let first = 0;
  let count = keys.length;
  if (count === 0 || keys[0].Frame > to || keys[count - 1].Frame < from) return null;
  while (count > 0) {
    const step = count >> 1;
    if (keys[first + step].Frame <= frame) {
      first += step + 1;
      count -= step + 1;
    } else count = step;
  }
  if (first === keys.length || keys[first].Frame > to) {
    return first > 0 && keys[first - 1].Frame >= from ? [keys[first - 1], keys[first - 1]] : null;
  }
  if (first === 0 || keys[first - 1].Frame < from) {
    return keys[first].Frame <= to ? [keys[first], keys[first]] : null;
  }
  return [keys[first - 1], keys[first]];
}

function bezier(a, outTan, inTan, b, t) {
  const it = 1 - t;
  return a * it * it * it + outTan * 3 * t * it * it + inTan * 3 * t * t * it + b * t * t * t;
}

function hermite(a, outTan, inTan, b, t) {
  const t2 = t * t;
  return a * (t2 * (2 * t - 3) + 1) + outTan * (t2 * (t - 2) + t) + inTan * (t2 * (t - 1)) + b * (t2 * (3 - 2 * t));
}

// Component-wise value of a scalar/vector track. Returns null when no key applies.
function evalComponents(av, frame, from, to) {
  const pair = findKeyframes(av, frame, from, to);
  if (!pair) return null;
  const [l, r] = pair;
  if (l.Frame === r.Frame || av.LineType === LineType.DontInterp) return Array.from(l.Vector);
  const t = (frame - l.Frame) / (r.Frame - l.Frame);
  const out = new Array(l.Vector.length);
  for (let c = 0; c < out.length; ++c) {
    if (av.LineType === LineType.Bezier) out[c] = bezier(l.Vector[c], l.OutTan[c], r.InTan[c], r.Vector[c], t);
    else if (av.LineType === LineType.Hermite) out[c] = hermite(l.Vector[c], l.OutTan[c], r.InTan[c], r.Vector[c], t);
    else out[c] = l.Vector[c] + (r.Vector[c] - l.Vector[c]) * t;
  }
  return out;
}

function evalQuat(av, frame, from, to) {
  const pair = findKeyframes(av, frame, from, to);
  if (!pair) return null;
  const [l, r] = pair;
  if (l.Frame === r.Frame || av.LineType === LineType.DontInterp) return Array.from(l.Vector);
  const t = (frame - l.Frame) / (r.Frame - l.Frame);
  const out = quat.create();
  if (av.LineType === LineType.Hermite || av.LineType === LineType.Bezier) {
    quat.sqlerp(out, l.Vector, l.OutTan, r.InTan, r.Vector, t);
  } else {
    quat.slerp(out, l.Vector, r.Vector, t);
  }
  return Array.from(out);
}

// Window [from, to] and local frame for a track at absolute frame `frame`
// of sequence `seq`; global-sequence tracks run on their own looping clock.
function windowFor(av, model, seq, frame, globalFrame) {
  if (typeof av.GlobalSeqId === "number") {
    const length = model.GlobalSequences[av.GlobalSeqId] || 0;
    return { frame: length > 0 ? globalFrame % length : 0, from: 0, to: length };
  }
  return { frame, from: seq.Interval[0], to: seq.Interval[1] };
}

function isAnimated(av) {
  return !!(av && typeof av === "object" && Array.isArray(av.Keys) && av.Keys.length > 0);
}

module.exports = { evalComponents, evalQuat, windowFor, isAnimated, LineType };
