/*{
  "LASERSCRIPT": "1.0",
  "NAME": "Debug Rotating Line"
}*/

function read(context, input, output) {
  const x = Math.cos(context.time);
  const y = Math.sin(context.time);
  output.addShape(1, [
    { position: [-x, -y, 0, 1], rgba: [1, 1, 1, 1], mode: 0 },
    { position: [x, y, 0, 1], rgba: [1, 1, 1, 1], mode: 0 },
  ]);
}
