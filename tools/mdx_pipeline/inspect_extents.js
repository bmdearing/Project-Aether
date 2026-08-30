const fs = require("fs");
const path = require("path");
const war3 = require("war3-model");
const mdxPath = path.resolve(__dirname, "../../assets/models/Arator the Redeemer/Arator_Midnights.mdx");
const buffer = fs.readFileSync(mdxPath);
const arrayBuffer = buffer.buffer.slice(buffer.byteOffset, buffer.byteOffset + buffer.byteLength);
const model = war3.parseMDX(arrayBuffer);

console.log("Model Info MinimumExtent:", Array.from(model.Info.MinimumExtent));
console.log("Model Info MaximumExtent:", Array.from(model.Info.MaximumExtent));
console.log("Model Info BoundsRadius:", model.Info.BoundsRadius);

model.Geosets.forEach((g, i) => {
  console.log(`Geoset ${i} name="${g.Name}" MinimumExtent=${Array.from(g.MinimumExtent)} MaximumExtent=${Array.from(g.MaximumExtent)} BoundsRadius=${g.BoundsRadius}`);
});
