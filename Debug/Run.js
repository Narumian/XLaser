const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const source = fs.readFileSync(path.join(__dirname, "RotatingLine.js"), "utf8");
const header = /^\/\*([\s\S]*?)\*\//.exec(source);
if (!header) throw new Error("Missing JSON header");
const metadata = JSON.parse(header[1]);
if (!metadata.LASERSCRIPT) throw new Error("Missing LaserScript version");

const script = vm.createContext({});
vm.runInContext(source, script, { filename: "RotatingLine.js" });
if (typeof script.read !== "function") throw new Error("Missing read function");

const output = {
  shapes: [],
  addShape(id, vertices) { this.shapes.push({ id, vertices }); },
};

function read(time) {
  output.shapes.length = 0;
  try {
    script.read({ sampleRate: 30000, frameLength: 1000, time }, [], output);
    return output.shapes;
  } catch (error) {
    output.shapes.length = 0;
    throw error;
  }
}

for (const time of [0, Math.PI / 2]) {
  console.log(JSON.stringify({ time, shapes: read(time) }, null, 2));
}
