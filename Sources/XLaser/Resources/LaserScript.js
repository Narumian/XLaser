class LaserScript {}

const Mode = Object.freeze({ normal: 0, dwell: 1, blank: 2 });

function Color(r = 1, g = 1, b = 1, a = 1) { return [r, g, b, a]; }
Color.rgb = Color;
Color.hsv = function(h, s, v, a = 1) {
  const turn = ((h % 1) + 1) % 1 * 6;
  const sector = Math.floor(turn), f = turn - sector;
  const p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s);
  switch (sector) {
    case 0: return Color(v, t, p, a);
    case 1: return Color(q, v, p, a);
    case 2: return Color(p, v, t, a);
    case 3: return Color(p, q, v, a);
    case 4: return Color(t, p, v, a);
    default: return Color(v, p, q, a);
  }
};
Color.black = Object.freeze([0, 0, 0, 1]);
Color.white = Object.freeze([1, 1, 1, 1]);

function Vertex(x = 0, y = 0, z = 0, color = Color.white, mode = Mode.normal) {
  if (!(this instanceof Vertex)) return new Vertex(x, y, z, color, mode);
  if ((!Array.isArray(color) && !ArrayBuffer.isView(color)) || color.length !== 4)
    throw new TypeError("Invalid color");
  this.position = [x, y, z, 1];
  this.rgba = Array.from(color);
  this.mode = mode;
}
Vertex.prototype.withPosition = function(x, y, z = this.position[2]) {
  const result = Vertex(x, y, z, this.rgba, this.mode);
  result.position[3] = this.position[3];
  return result;
};
Vertex.prototype.withColor = function(color) {
  const result = Vertex(this.position[0], this.position[1], this.position[2], color, this.mode);
  result.position[3] = this.position[3];
  return result;
};
Vertex.prototype.withMode = function(mode) {
  const result = this.withPosition(...this.position.slice(0, 3));
  result.mode = mode;
  return result;
};
Vertex.prototype.blanked = function() { return this.withColor([0, 0, 0, 0]).withMode(Mode.blank); };
Vertex.prototype.transformed = function(matrix) {
  if (matrix && matrix.rows === 4 && matrix.columns === 4) matrix = matrix.values;
  if ((!Array.isArray(matrix) && !ArrayBuffer.isView(matrix)) || matrix.length !== 16)
    throw new TypeError("Expected a 4x4 matrix");
  const result = this.withPosition(...this.position.slice(0, 3));
  for (let row = 0; row < 4; row++)
    result.position[row] = matrix[row * 4] * this.position[0] + matrix[row * 4 + 1] * this.position[1] +
                           matrix[row * 4 + 2] * this.position[2] + matrix[row * 4 + 3] * this.position[3];
  return result;
};

function clamp(value, min, max) { return Math.min(max, Math.max(min, value)); }
function lerp(a, b, t) { return a + (b - a) * t; }
function map(value, inMin, inMax, outMin, outMax) {
  if (inMin === inMax) throw new RangeError("Input range must not be empty");
  return lerp(outMin, outMax, (value - inMin) / (inMax - inMin));
}
function radians(degrees) { return degrees * Math.PI / 180; }
function degrees(radians) { return radians * 180 / Math.PI; }
function vec2(x = 0, y = 0) { return [x, y]; }
function vec3(x = 0, y = 0, z = 0) { return [x, y, z]; }
function vec4(x = 0, y = 0, z = 0, w = 0) { return [x, y, z, w]; }
function phase(time, period) {
  if (!Number.isFinite(time) || !Number.isFinite(period) || period <= 0)
    throw new RangeError("Invalid period or time");
  return ((time / period) % 1 + 1) % 1;
}
const wave = Object.freeze({
  sine: p => Math.sin(2 * Math.PI * p),
  triangle: p => 1 - 4 * Math.abs(phase(p, 1) - 0.5),
  saw: p => 2 * phase(p, 1) - 1,
  square: p => phase(p, 1) < 0.5 ? 1 : -1,
});

function allocateLaserArray(type, count) {
  if (type === "float32") return new Float32Array(count);
  if (type === "uint16") return new Uint16Array(count);
  if (type === "uint32") return new Uint32Array(count);
  throw new TypeError("Invalid buffer type");
}

class Laser3DBuffer {
  constructor(allocate = allocateLaserArray) {
    this.allocate = allocate;
    this.values = allocate("float32", 8 * 16);
    this.modes = allocate("uint16", 16);
    this.shapes = allocate("uint32", 3 * 4);
    this.shapeMatrices = allocate("float32", 16 * 4);
    this.shapeColors = allocate("float32", 4 * 4);
    this.vertexCount = 0;
    this.shapeCount = 0;
    this.reservation = null;
  }

  ensureShapeCapacity(count) {
    if (this.shapes.length >= count * 3) return;
    const capacity = Math.max(count, (this.shapes.length / 3) * 2);
    const shapes = this.allocate("uint32", capacity * 3);
    const matrices = this.allocate("float32", capacity * 16);
    const colors = this.allocate("float32", capacity * 4);
    shapes.set(this.shapes); matrices.set(this.shapeMatrices); colors.set(this.shapeColors);
    this.shapes = shapes; this.shapeMatrices = matrices; this.shapeColors = colors;
  }

  parseShapeOptions(options) {
    if (options === undefined || options === null) return null;
    if (typeof options !== "object") throw new TypeError("Invalid shape options");
    let matrix = options.matrix, color = options.color;
    if (matrix !== undefined) {
      if (matrix !== null && matrix.rows === 4 && matrix.columns === 4) matrix = matrix.values;
      if ((!Array.isArray(matrix) && !ArrayBuffer.isView(matrix)) || matrix.length !== 16)
        throw new TypeError("Expected a 4x4 matrix");
      for (let i = 0; i < 16; i++) if (!Number.isFinite(matrix[i])) throw new TypeError("Invalid matrix");
    }
    if (color !== undefined) {
      if ((!Array.isArray(color) && !ArrayBuffer.isView(color)) || color.length !== 4)
        throw new TypeError("Invalid color");
      for (let i = 0; i < 4; i++) if (!Number.isFinite(color[i])) throw new TypeError("Invalid color");
    }
    return { matrix, color };
  }

  writeShapeOptions(shape, parsed) {
    const m = shape * 16, c = shape * 4;
    const matrix = parsed === null ? undefined : parsed.matrix, color = parsed === null ? undefined : parsed.color;
    for (let i = 0; i < 16; i++) this.shapeMatrices[m + i] = matrix === undefined ? (i % 5 === 0 ? 1 : 0) : matrix[i];
    for (let i = 0; i < 4; i++) this.shapeColors[c + i] = color === undefined ? 1 : color[i];
  }

  reset() {
    this.vertexCount = 0;
    this.shapeCount = 0;
    this.reservation = null;
  }

  finishRead() {
    if (this.reservation !== null) throw new Error("Uncommitted vertices");
  }

  reserve(shapes, vertices) {
    if (!Number.isInteger(shapes) || shapes < 0 || shapes > 0xffffffff ||
        !Number.isInteger(vertices) || vertices < 0 || vertices > 0xffffffff)
      throw new RangeError("Invalid buffer capacity");
    this.ensureShapeCapacity(shapes);
    if (this.modes.length < vertices) {
      const size = Math.min(0xffffffff, Math.max(vertices, this.modes.length * 2));
      const modes = this.allocate("uint16", size);
      const values = this.allocate("float32", size * 8);
      modes.set(this.modes); values.set(this.values);
      this.modes = modes; this.values = values;
    }
  }

  reserveVertices(count) {
    if (this.reservation !== null) throw new Error("Vertices are already reserved");
    if (this.shapeCount === 0) throw new Error("A shape must be started first");
    if (!Number.isInteger(count) || count < 0 || count > 0xffffffff - this.vertexCount)
      throw new RangeError("Invalid vertex count");
    const start = this.vertexCount;
    this.reserve(this.shapeCount, start + count);
    this.values.fill(0, start * 8, (start + count) * 8);
    this.modes.fill(Mode.blank, start, start + count);
    this.reservation = count;
    return start;
  }

  commitVertices(count) {
    if (this.reservation === null) throw new Error("No vertices are reserved");
    if (!Number.isInteger(count) || count < 0 || count > this.reservation)
      throw new RangeError("Invalid vertex count");
    this.vertexCount += count;
    this.shapes[(this.shapeCount - 1) * 3 + 2] += count;
    this.reservation = null;
  }

  beginShape(id, options) {
    if (this.reservation !== null) throw new Error("Uncommitted vertices");
    if (!Number.isInteger(id) || id < 0 || id > 0xffffffff)
      throw new RangeError("Invalid shape ID");
    if (this.shapeCount >= 0xffffffff) throw new RangeError("Too many shapes");
    const parsed = this.parseShapeOptions(options);
    this.ensureShapeCapacity(this.shapeCount + 1);
    const offset = this.shapeCount * 3;
    this.shapes[offset] = id;
    this.shapes[offset + 1] = this.vertexCount;
    this.shapes[offset + 2] = 0;
    this.writeShapeOptions(this.shapeCount, parsed);
    this.shapeCount++;
  }

  addVertex(x, y, z, w, r, g, b, a, mode = Mode.normal) {
    if (this.reservation !== null) throw new Error("Uncommitted vertices");
    if (arguments.length === 1 && x !== null && typeof x === "object") {
      const vertex = x;
      if (!Array.isArray(vertex.position) || vertex.position.length !== 4 ||
          !Array.isArray(vertex.rgba) || vertex.rgba.length !== 4)
        throw new TypeError("Invalid vertex");
      [x, y, z, w] = vertex.position;
      [r, g, b, a] = vertex.rgba;
      mode = vertex.mode === undefined ? Mode.normal : vertex.mode;
    }
    if (this.shapeCount === 0) throw new Error("A shape must be started first");
    if (this.vertexCount >= 0xffffffff) throw new RangeError("Too many vertices");
    if (!Number.isFinite(x) || !Number.isFinite(y) || !Number.isFinite(z) || !Number.isFinite(w) ||
        !Number.isFinite(r) || !Number.isFinite(g) || !Number.isFinite(b) || !Number.isFinite(a) ||
        !Number.isInteger(mode) || mode < 0 || mode > 2)
      throw new TypeError("Invalid vertex");
    if (this.vertexCount >= this.modes.length) {
      const modes = this.allocate("uint16", this.modes.length * 2);
      const values = this.allocate("float32", this.values.length * 2);
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

  addVertices(values, modes) {
    if (this.reservation !== null) throw new Error("Uncommitted vertices");
    if (this.shapeCount === 0) throw new Error("A shape must be started first");
    if (!(values instanceof Float32Array) || values.length % 8 !== 0 ||
        (modes !== undefined && (!(modes instanceof Uint16Array) || values.length !== modes.length * 8)))
      throw new TypeError("Invalid vertex buffers");
    const start = this.vertexCount, count = values.length / 8;
    if (count > 0xffffffff - start) throw new RangeError("Too many vertices");
    this.reserve(this.shapeCount, start + count);
    this.values.set(values, start * 8);
    if (modes === undefined) this.modes.fill(Mode.normal, start, start + count);
    else this.modes.set(modes, start);
    this.vertexCount += count;
    this.shapes[(this.shapeCount - 1) * 3 + 2] += count;
  }

  addStream(input, options) {
    if (this.reservation !== null) throw new Error("Uncommitted vertices");
    if (!Number.isInteger(input.vertexCount) || input.vertexCount < 0 || input.vertexCount > 0xffffffff ||
        !Number.isInteger(input.shapeCount) || input.shapeCount < 0 || input.shapeCount > 0xffffffff ||
        !(input.values instanceof Float32Array) || input.values.length < input.vertexCount * 8 ||
        !(input.modes instanceof Uint16Array) || input.modes.length < input.vertexCount ||
        !(input.shapes instanceof Uint32Array) || input.shapes.length < input.shapeCount * 3)
      throw new TypeError("Invalid input stream");
    const vertices = this.vertexCount + input.vertexCount;
    const shapes = this.shapeCount + input.shapeCount;
    if (vertices > 0xffffffff || shapes > 0xffffffff) throw new RangeError("Stream too large");
    const parsed = this.parseShapeOptions(options);
    if (this.modes.length < vertices) {
      const size = Math.max(vertices, this.modes.length * 2);
      const modes = this.allocate("uint16", size);
      const values = this.allocate("float32", size * 8);
      modes.set(this.modes); values.set(this.values);
      this.modes = modes; this.values = values;
    }
    this.ensureShapeCapacity(shapes);
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
      this.writeShapeOptions(this.shapeCount + i, parsed);
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

  pathPoint(point, color) {
    if (point && point.position !== undefined) {
      if (color === undefined) this.addVertex(point);
      else {
        if ((!Array.isArray(color) && !ArrayBuffer.isView(color)) || color.length !== 4)
          throw new TypeError("Invalid color");
        this.addVertex(...point.position, ...color, point.mode);
      }
      return;
    }
    if ((!Array.isArray(point) && !ArrayBuffer.isView(point)) || point.length < 2 || point.length > 4)
      throw new TypeError("Invalid point");
    const rgba = color === undefined ? Color.white : color;
    if ((!Array.isArray(rgba) && !ArrayBuffer.isView(rgba)) || rgba.length !== 4)
      throw new TypeError("Invalid color");
    this.addVertex(point[0], point[1], point[2] ?? 0, point[3] ?? 1, ...rgba, Mode.normal);
  }

  line(id, from, to, color) { this.polyline(id, [from, to], color); }

  polyline(id, points, color) {
    this.beginShape(id);
    for (const point of points) this.pathPoint(point, color);
  }

  polygon(id, points, color) {
    this.beginShape(id);
    let first;
    for (const point of points) {
      if (first === undefined) first = point;
      this.pathPoint(point, color);
    }
    if (first !== undefined) this.pathPoint(first, color);
  }

  circle(id, center, radius, segments = 64, color) {
    if ((!Array.isArray(center) && !ArrayBuffer.isView(center)) || center.length < 2 || center.length > 3 ||
        !Number.isFinite(radius) || radius < 0 || !Number.isInteger(segments) || segments < 3 || segments >= 0xffffffff)
      throw new RangeError("Invalid circle");
    this.beginShape(id);
    for (let index = 0; index <= segments; index++) {
      const angle = 2 * Math.PI * (index === segments ? 0 : index) / segments;
      this.pathPoint([center[0] + radius * Math.cos(angle), center[1] + radius * Math.sin(angle), center[2] ?? 0], color);
    }
  }

  rectangle(id, center, size, color) {
    if ((!Array.isArray(center) && !ArrayBuffer.isView(center)) || center.length < 2 || center.length > 3 ||
        (!Array.isArray(size) && !ArrayBuffer.isView(size)) || size.length !== 2 ||
        !Number.isFinite(size[0]) || !Number.isFinite(size[1]) || size[0] < 0 || size[1] < 0)
      throw new RangeError("Invalid rectangle");
    const x = center[0], y = center[1], z = center[2] ?? 0, w = size[0] / 2, h = size[1] / 2;
    this.polygon(id, [[x-w,y-h,z], [x+w,y-h,z], [x+w,y+h,z], [x-w,y+h,z]], color);
  }
}

class Laser3DInput {
  constructor() {
    this.values = new Float32Array(8 * 16);
    this.modes = new Uint16Array(16);
    this.shapes = new Uint32Array(3 * 4);
    this.vertexCount = 0;
    this.shapeCount = 0;
  }

  prepare(vertexCount, shapeCount) {
    if (this.modes.length < vertexCount) {
      const size = Math.max(vertexCount, this.modes.length * 2);
      this.modes = new Uint16Array(size);
      this.values = new Float32Array(size * 8);
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
