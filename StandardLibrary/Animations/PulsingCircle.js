/*{
  "LASERSCRIPT": "1.0",
  "NAME": "Pulsing Circle",
  "INPUTS": [
    { "NAME": "radius", "TYPE": "float", "DEFAULT": 0.5, "MIN": 0.0, "MAX": 1.0 },
    { "NAME": "depth", "TYPE": "float", "DEFAULT": 0.5, "MIN": 0.0, "MAX": 1.0 },
    { "NAME": "speed", "TYPE": "float", "DEFAULT": 0.5, "MIN": -10.0, "MAX": 10.0 },
    { "NAME": "segments", "TYPE": "int", "DEFAULT": 64, "MIN": 3, "MAX": 1024 },
    { "NAME": "color", "TYPE": "color", "DEFAULT": [1.0, 1.0, 1.0, 1.0] }
  ]
}*/

let cycles = 0;
let previousTime;

function read(context, inputs, output) {
  if (previousTime === undefined) cycles = context.time * inputs.speed;
  else cycles += (context.time - previousTime) * inputs.speed;
  previousTime = context.time;

  const radius = inputs.radius * (1 - inputs.depth * (1 - wave.sine(cycles)) / 2);
  output.circle(1, [0, 0], radius, inputs.segments, inputs.color);
}
