class LaserScript {}

function allocateLaserArray(type, count) {
  if (type === "float64") return new Float64Array(count);
  if (type === "uint16") return new Uint16Array(count);
  if (type === "uint32") return new Uint32Array(count);
  throw new TypeError("Invalid buffer type");
}

class Laser3DStream {
  constructor(allocate = allocateLaserArray) {
    this.allocate = allocate;
    this.values = allocate("float64", 8 * 16);
    this.modes = allocate("uint16", 16);
    this.shapes = allocate("uint32", 3 * 4);
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
      const next = this.allocate("uint32", this.shapes.length * 2);
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
      const modes = this.allocate("uint16", this.modes.length * 2);
      const values = this.allocate("float64", this.values.length * 2);
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

  addStream(input) {
    if (!Number.isInteger(input.vertexCount) || input.vertexCount < 0 || input.vertexCount > 0xffffffff ||
        !Number.isInteger(input.shapeCount) || input.shapeCount < 0 || input.shapeCount > 0xffffffff ||
        !(input.values instanceof Float64Array) || input.values.length < input.vertexCount * 8 ||
        !(input.modes instanceof Uint16Array) || input.modes.length < input.vertexCount ||
        !(input.shapes instanceof Uint32Array) || input.shapes.length < input.shapeCount * 3)
      throw new TypeError("Invalid input stream");
    const vertices = this.vertexCount + input.vertexCount;
    const shapes = this.shapeCount + input.shapeCount;
    if (vertices > 0xffffffff || shapes > 0xffffffff) throw new RangeError("Stream too large");
    if (this.modes.length < vertices) {
      const size = Math.max(vertices, this.modes.length * 2);
      const modes = this.allocate("uint16", size);
      const values = this.allocate("float64", size * 8);
      modes.set(this.modes); values.set(this.values);
      this.modes = modes; this.values = values;
    }
    if (this.shapes.length < shapes * 3) {
      const next = this.allocate("uint32", Math.max(shapes * 3, this.shapes.length * 2));
      next.set(this.shapes); this.shapes = next;
    }
    this.values.set(input.values.subarray(0, input.vertexCount * 8), this.vertexCount * 8);
    this.modes.set(input.modes.subarray(0, input.vertexCount), this.vertexCount);
    for (let i = 0; i < input.shapeCount; i++) {
      const source = i * 3, target = (this.shapeCount + i) * 3;
      const start = input.shapes[source + 1], length = input.shapes[source + 2];
      if (start > input.vertexCount || length > input.vertexCount - start)
        throw new RangeError("Invalid shape range");
      this.shapes[target] = input.shapes[source];
      this.shapes[target + 1] = start + this.vertexCount;
      this.shapes[target + 2] = length;
    }
    this.vertexCount = vertices;
    this.shapeCount = shapes;
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

class Laser3DInput {
  constructor() {
    this.values = new Float64Array(8 * 16);
    this.modes = new Uint16Array(16);
    this.shapes = new Uint32Array(3 * 4);
    this.vertexCount = 0;
    this.shapeCount = 0;
  }

  prepare(vertexCount, shapeCount) {
    if (this.modes.length < vertexCount) {
      const size = Math.max(vertexCount, this.modes.length * 2);
      this.modes = new Uint16Array(size);
      this.values = new Float64Array(size * 8);
    }
    if (this.shapes.length < shapeCount * 3)
      this.shapes = new Uint32Array(Math.max(shapeCount * 3, this.shapes.length * 2));
    this.vertexCount = vertexCount;
    this.shapeCount = shapeCount;
  }

  *[Symbol.iterator]() {
    for (let shape = 0; shape < this.shapeCount; shape++) {
      const offset = shape * 3;
      const vertices = [];
      const start = this.shapes[offset + 1];
      const end = start + this.shapes[offset + 2];
      for (let index = start; index < end; index++) {
        const i = index * 8;
        vertices.push({
          position: [this.values[i], this.values[i + 1], this.values[i + 2], this.values[i + 3]],
          rgba: [this.values[i + 4], this.values[i + 5], this.values[i + 6], this.values[i + 7]],
          mode: this.modes[index],
        });
      }
      yield { id: this.shapes[offset], vertices };
    }
  }
}
