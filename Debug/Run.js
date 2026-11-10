const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const assert = require("node:assert/strict");

const source = fs.readFileSync(path.join(__dirname, "RotatingLine.js"), "utf8");
const header = /^\/\*([\s\S]*?)\*\//.exec(source);
if (!header) throw new Error("Missing JSON header");
const metadata = JSON.parse(header[1]);
if (!metadata.LASERSCRIPT) throw new Error("Missing LaserScript version");

const script = vm.createContext({});
const runtime = fs.readFileSync(path.join(__dirname, "../Sources/XLaser/Resources/LaserScript.js"), "utf8");
vm.runInContext(runtime, script, { filename: "LaserScript.js" });
vm.runInContext(source, script, { filename: "RotatingLine.js" });
if (typeof script.read !== "function") throw new Error("Missing read function");

const output = vm.runInContext("new Laser3DBuffer()", script);

function read(time, speed) {
  output.reset();
  try {
    script.read({ sampleRate: 30000, frameLength: 1000, time }, { speed }, output);
    return { x: output.values[8], y: output.values[9] };
  } catch (error) {
    output.reset();
    throw error;
  }
}

for (const [time, speed, expectedAngle] of [[0, 1, 0], [1, 1, 1], [1, 2, 1], [2, 2, 3]]) {
  const vertex = read(time, speed);
  assert.ok(Math.abs(vertex.x - Math.cos(expectedAngle)) < 1e-12);
  assert.ok(Math.abs(vertex.y - Math.sin(expectedAngle)) < 1e-12);
  console.log(JSON.stringify({ time, speed, vertex }));
}
