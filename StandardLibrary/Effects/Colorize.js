/*{
  "LASERSCRIPT": "1.0",
  "NAME": "Colorize",
  "INPUTS": [
    { "NAME": "source", "TYPE": "laser" },
    { "NAME": "color", "TYPE": "color", "DEFAULT": [1.0, 1.0, 1.0, 1.0] },
    { "NAME": "mix", "TYPE": "float", "DEFAULT": 1.0, "MIN": 0.0, "MAX": 1.0 }
  ]
}*/

function read(context, inputs, output) {
  const source = inputs.source;
  if (source === undefined) return;

  output.addStream(source);
  for (let vertex = 0; vertex < output.vertexCount; vertex++) {
    if (output.modes[vertex] === Mode.blank) continue;
    const index = vertex * 8;
    for (let channel = 0; channel < 4; channel++)
      output.values[index + 4 + channel] = lerp(output.values[index + 4 + channel], inputs.color[channel], inputs.mix);
  }
}
