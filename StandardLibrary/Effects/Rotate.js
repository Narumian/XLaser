/*{
  "LASERSCRIPT": "1.0",
  "NAME": "Rotate",
  "INPUTS": [
    { "NAME": "source", "TYPE": "laser" },
    { "NAME": "angle", "TYPE": "float", "DEFAULT": 0.0, "MIN": -360.0, "MAX": 360.0 }
  ]
}*/

function read(context, inputs, output) {
  const source = inputs.source;
  if (source === undefined) return;

  const angle = radians(inputs.angle), c = Math.cos(angle), s = Math.sin(angle);
  output.addStream(source);
  for (let vertex = 0; vertex < output.vertexCount; vertex++) {
    const index = vertex * 8, x = output.values[index], y = output.values[index + 1];
    output.values[index] = x * c - y * s;
    output.values[index + 1] = x * s + y * c;
  }
}
