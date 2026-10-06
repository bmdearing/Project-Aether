// Spike: confirm war3-model can actually parse the real Reforged .mdx file
// we have, before building the full glTF exporter around it. Not part of
// the pipeline itself - a one-off sanity check.
const fs = require("fs");
const path = require("path");
const war3 = require("war3-model");

const mdxPath = process.argv[2]
  ? path.resolve(process.argv[2])
  : path.resolve(__dirname, "../../assets/models/Arator the Redeemer/Arator_Midnights.mdx");

const buffer = fs.readFileSync(mdxPath);
const arrayBuffer = buffer.buffer.slice(
  buffer.byteOffset,
  buffer.byteOffset + buffer.byteLength
);

const model = war3.parseMDX(arrayBuffer);

console.log("Version:", model.Version);
console.log("Name:", model.Info.Name);
console.log("Geosets:", model.Geosets.length);
model.Geosets.forEach((g, i) => {
  console.log(
    `  Geoset ${i}: verts=${g.Vertices.length / 3} faces=${g.Faces.length / 3} ` +
    `uvChannels=${g.TVertices.length} hasSkinWeights=${!!g.SkinWeights} hasTangents=${!!g.Tangents} materialId=${g.MaterialID} name=${g.Name || ""}`
  );
});
console.log("Bones:", model.Bones.length);
console.log("Nodes (all):", model.Nodes.length);
console.log("Helpers:", model.Helpers.length);
console.log("PivotPoints:", model.PivotPoints.length);
console.log("Sequences:", model.Sequences.length);
model.Sequences.forEach((s) => {
  console.log(`  Seq: ${s.Name} interval=[${s.Interval[0]},${s.Interval[1]}]`);
});
console.log("Textures:", model.Textures.length);
model.Textures.forEach((t, i) => console.log(`  Texture ${i}: ${t.Image}`));
console.log("Materials:", model.Materials.length);
model.Materials.forEach((m, i) => {
  console.log(`  Material ${i}: layers=${m.Layers.length}`);
  m.Layers.forEach((l, li) => {
    console.log(
      `    Layer ${li}: TextureID=${JSON.stringify(l.TextureID)} NormalTextureID=${JSON.stringify(l.NormalTextureID)} ORMTextureID=${JSON.stringify(l.ORMTextureID)} EmissiveTextureID=${JSON.stringify(l.EmissiveTextureID)}`
    );
  });
});
