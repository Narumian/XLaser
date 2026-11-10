class LaserScript {}

class Laser3DStream {
  constructor() {
    this.values = new Float64Array(8 * 16);
    this.modes = new Uint16Array(16);
    this.shapes = new Uint32Array(3 * 4);
    this.vertexCount = 0;
    this.shapeCount = 0;
  }

  reset() {
    this.vertexCount = 0;
    this.shapeCount = 0;
  }

  beginShape(id) {
    if (!Number.isInteger(id) || id < 0 || id > 0xffffffff)
      throw new RangeError("Invalid shape ID");
    if (this.shapeCount >= 0xffffffff) throw new RangeError("Too many shapes");
    if ((this.shapeCount + 1) * 3 > this.shapes.length) {
      const next = new Uint32Array(this.shapes.length * 2);
      next.set(this.shapes);
      this.shapes = next;
    }
    const offset = this.shapeCount * 3;
    this.shapes[offset] = id;
    this.shapes[offset + 1] = this.vertexCount;
    this.shapes[offset + 2] = 0;
    this.shapeCount++;
  }

  addVertex(x, y, z, w, r, g, b, a, mode) {
    if (this.shapeCount === 0) throw new Error("A shape must be started first");
    if (this.vertexCount >= 0xffffffff) throw new RangeError("Too many vertices");
    if (!Number.isFinite(x) || !Number.isFinite(y) || !Number.isFinite(z) || !Number.isFinite(w) ||
        !Number.isFinite(r) || !Number.isFinite(g) || !Number.isFinite(b) || !Number.isFinite(a) ||
        !Number.isInteger(mode) || mode < 0 || mode > 2)
      throw new TypeError("Invalid vertex");
    if (this.vertexCount >= this.modes.length) {
      const modes = new Uint16Array(this.modes.length * 2);
      const values = new Float64Array(this.values.length * 2);
      modes.set(this.modes);
      values.set(this.values);
      this.modes = modes;
      this.values = values;
    }
    const index = this.vertexCount;
    const offset = index * 8;
    this.values[offset] = x; this.values[offset + 1] = y;
    this.values[offset + 2] = z; this.values[offset + 3] = w;
    this.values[offset + 4] = r; this.values[offset + 5] = g;
    this.values[offset + 6] = b; this.values[offset + 7] = a;
    this.modes[index] = mode;
    this.vertexCount++;
    this.shapes[(this.shapeCount - 1) * 3 + 2]++;
  }

  addShape(id, vertices) {
    this.beginShape(id);
    for (const vertex of vertices) {
      if (!Array.isArray(vertex.position) || vertex.position.length !== 4 ||
          !Array.isArray(vertex.rgba) || vertex.rgba.length !== 4)
        throw new TypeError("Invalid vertex");
      this.addVertex(...vertex.position, ...vertex.rgba, vertex.mode);
    }
  }
}
