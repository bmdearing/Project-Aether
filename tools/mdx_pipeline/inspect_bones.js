const fs = require("fs");
const path = require("path");
const war3 = require("war3-model");

const mdxPath = path.resolve(__dirname, "../../assets/models/Arator the Redeemer/Arator_Midnights.mdx");
const buffer = fs.readFileSync(mdxPath);
const arrayBuffer = buffer.buffer.slice(buffer.byteOffset, buffer.byteOffset + buffer.byteLength);
const model = war3.parseMDX(arrayBuffer);

console.log("--- Nodes (first 15) ---");
model.Nodes.slice(0, 15).forEach((n, i) => {
  console.log(`${i}: ObjectId=${n.ObjectId} Parent=${n.Parent} Name="${n.Name}" hasTranslation=${!!n.Translation} hasRotation=${!!n.Rotation} hasScaling=${!!n.Scaling}`);
});
console.log("--- Bones (first 10) ---");
model.Bones.slice(0, 10).forEach((b, i) => {
  console.log(`${i}: ObjectId=${b.ObjectId} Parent=${b.Parent} Name="${b.Name}" GeosetId=${b.GeosetId}`);
});
console.log("Geoset0 SkinWeights length:", model.Geosets[0].SkinWeights.length, "verts:", model.Geosets[0].Vertices.length / 3);
console.log("Geoset0 first 16 SkinWeights bytes:", Array.from(model.Geosets[0].SkinWeights.slice(0, 16)));
console.log("Geoset0 VertexGroup length:", model.Geosets[0].VertexGroup.length, "first 8:", Array.from(model.Geosets[0].VertexGroup.slice(0,8)));
console.log("Geoset0 Groups (first 5):", JSON.stringify(model.Geosets[0].Groups.slice(0,5)));
console.log("Geoset0 Tangents length:", model.Geosets[0].Tangents.length, "expect verts*4=", (model.Geosets[0].Vertices.length/3)*4);

const seq = model.Sequences[0];
const bone0WithAnim = model.Bones.find(b => b.Translation || b.Rotation);
console.log("--- Example animated bone ---");
if (bone0WithAnim) {
  console.log("Name:", bone0WithAnim.Name);
  if (bone0WithAnim.Rotation) {
    console.log("Rotation LineType:", bone0WithAnim.Rotation.LineType, "GlobalSeqId:", bone0WithAnim.Rotation.GlobalSeqId, "num keys:", bone0WithAnim.Rotation.Keys.length);
    console.log("First 3 rotation keys:", JSON.stringify(bone0WithAnim.Rotation.Keys.slice(0,3).map(k => ({Frame: k.Frame, Vector: Array.from(k.Vector)}))));
  }
}
