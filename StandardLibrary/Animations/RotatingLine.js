/*{
  "LASERSCRIPT": "1.0",
  "NAME": "Rotating Line",
  "INPUTS": [
    { "NAME": "length", "TYPE": "float", "DEFAULT": 1.0, "MIN": 0.0, "MAX": 2.0 },
    { "NAME": "speed", "TYPE": "float", "DEFAULT": 1.0, "MIN": -10.0, "MAX": 10.0 },
    { "NAME": "color", "TYPE": "color", "DEFAULT": [1.0, 1.0, 1.0, 1.0] }
  ]
}*/

let angle = 0;
let previousTime;

function read(context, inputs, output) {
  if (previousTime === undefined) angle = context.time * inputs.speed;
  else angle += (context.time - previousTime) * inputs.speed;
  previousTime = context.time;

  const half = inputs.length / 2;
  const x = half * Math.cos(angle), y = half * Math.sin(angle);
  output.line(1, [-x, -y], [x, y], inputs.color);
}
