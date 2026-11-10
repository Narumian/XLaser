/*{
  "LASERSCRIPT": "1.0",
  "NAME": "Debug Rotating Line",
  "INPUTS": [
    { "NAME": "speed", "TYPE": "float", "DEFAULT": 1.0 }
  ]
}*/

let angle = 0;
let previousTime;

function read(context, inputs, output) {
  if (previousTime === undefined) angle = context.time * (inputs.speed ?? 1);
  else angle += (context.time - previousTime) * (inputs.speed ?? 1);
  previousTime = context.time;
  const x = Math.cos(angle);
  const y = Math.sin(angle);
  output.addShape(1, [
    { position: [-x, -y, 0, 1], rgba: [1, 1, 1, 1], mode: 0 },
    { position: [x, y, 0, 1], rgba: [1, 1, 1, 1], mode: 0 },
  ]);
}
