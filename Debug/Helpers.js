/*{
  "LASERSCRIPT": "1.0",
  "NAME": "Debug Helpers"
}*/

function read(context, inputs, output) {
  if (clamp(4, 0, 3) !== 3 || lerp(1, 3, 0.5) !== 2 || map(5, 0, 10, 0, 1) !== 0.5 ||
      Math.abs(radians(180) - Math.PI) > 1e-12 || Math.abs(degrees(Math.PI) - 180) > 1e-12 ||
      JSON.stringify(vec2(1, 2)) !== '[1,2]' || JSON.stringify(vec3(1, 2, 3)) !== '[1,2,3]' ||
      JSON.stringify(vec4(1, 2, 3, 4)) !== '[1,2,3,4]' || phase(-0.25, 1) !== 0.75 ||
      Math.abs(wave.sine(0.25) - 1) > 1e-12 || wave.triangle(0.5) !== 1 ||
      wave.saw(0.25) !== -0.5 || wave.square(0.75) !== -1)
    throw new Error("Invalid helpers");
  const original = Vertex(1, 2, 3, Color.rgb(0, 1, 0), Mode.normal);
  const vertex = original.withPosition(2, 3, 4).withColor(Color.hsv(0, 1, 1)).withMode(Mode.dwell);
  const matrix = { rows: 4, columns: 4, values: [1,0,0,10, 0,1,0,20, 0,0,1,30, 0,0,0,1] };
  const moved = vertex.transformed(matrix), blank = moved.blanked();
  if (JSON.stringify(moved.position) !== '[12,23,34,1]' || moved.mode !== Mode.dwell ||
      JSON.stringify(blank.rgba) !== '[0,0,0,0]' || blank.mode !== Mode.blank || original.position[0] !== 1)
    throw new Error("Invalid vertex");
  output.reserve(12, 32);
  output.line(1, vec2(0, 0), vec2(1, 0), Color.white);
  output.polyline(2, [vec2(0, 0), vec3(0, 1, 2)], Color.black);
  output.polygon(3, [vec2(0, 0), vec2(1, 0), vec2(0, 1)], Color.white);
  output.circle(4, vec2(0, 0), 1, 4, Color.white);
  output.rectangle(5, vec2(0, 0), vec2(2, 2), Color.white);
  output.beginShape(6);
  output.addVertex(moved);
  output.addVertices(new Float64Array([0,0,0,1,1,1,1,1, 1,0,0,1,1,1,1,1]), new Uint16Array([Mode.normal, Mode.blank]));
  output.beginShape(7);
  const start = output.reserveVertices(3), k = start * 8;
  output.values.set([0.5, 0.25, 0, 1, 1, 1, 1, 1], k);
  output.modes[start] = Mode.normal;
  output.commitVertices(2);
}
