# JavaScript Asset Protocol

## JavaScript single-file asset

- A single-file LaserScript asset must use the `.js` extension.
- The file must be valid JavaScript.
- The file must begin with a JavaScript block comment containing a JSON object as its header.
- The header must identify the file as a LaserScript asset and specify its LaserScript protocol version.
- The asset must define a `read(context, inputs, output)` function. The host calls it for each read, providing the read context, inputs, and output buffer.
- Inputs are accessed by their declared names, for example `inputs.speed`.
- `int` and `long` inputs are JavaScript numbers in the safe integer range. `vec2` and `point2D` use two-element arrays; `vec3` uses three elements, and `vec4` and `color` use four.
- `enum` is a safe integer and `event` is a boolean indicating an event for the current read.
- `array` is a JavaScript array. `matrix` is an object with `rows`, `columns`, and a row-major `values` array.
- `image` has `width`, `height`, and an RGBA `Uint8Array` named `rgba`. `audio` has `sampleRate`, `channels`, and an interleaved `Float32Array` named `samples`. `audioFFT` has `sampleRate`, `fftSize`, and a `Float32Array` named `bins`.

For example (the header key and version are illustrative):

```javascript
/*{
  "LASERSCRIPT": "1.0",
  "NAME": "Adjustable Point",
  "DESCRIPTION": "A point with an adjustable horizontal position.",
  "CATEGORIES": ["Graphic"],
  "TAGS": ["point"],
  "AUTHOR": "Example Author",
  "LICENSE": "MIT",
  "ID": "example.adjustable-point",
  "VERSION": "1.0",
  "INPUTS": [
    { "NAME": "x", "TYPE": "float", "LABEL": "Horizontal position", "DESCRIPTION": "Position along the X axis.", "UNIT": "normalized", "DEFAULT": 0.0, "MIN": -1.0, "MAX": 1.0 }
  ]
}*/

function read(context, inputs, output) {
  output.beginShape(0);
  output.addVertex(inputs.x ?? 0, 0, 0, 1, 1, 1, 1, 1, 0);
}
```

## JavaScript helpers

- `Vertex(x, y, z, color, mode)` creates a vertex with defaults `z = 0`, white color, and `Mode.normal`. Its `withPosition`, `withColor`, `withMode`, `blanked`, and `transformed` methods return new vertices. `transformed` accepts a row-major 4×4 array or matrix input.
- `Color(r, g, b, a)`, `Color.rgb`, `Color.hsv`, `Color.black`, `Color.white`, and `Mode.normal`, `Mode.dwell`, `Mode.blank` are available.
- `output.reserve(shapes, vertices)` reserves capacity. `output.addVertex` accepts a vertex or eight components and an optional mode; `output.addVertices` appends an interleaved `Float32Array` and an optional `Uint16Array` of modes to the current shape. Omitted modes default to `Mode.normal`.
- After `output.beginShape(id)`, `output.reserveVertices(count)` returns the starting vertex index. Write all eight position and color components for each completed vertex into `output.values`, then call `output.commitVertices(count)` with the completed prefix length. Reserved modes default to `Mode.blank`; write `output.modes` to make a point normal or dwell. An uncommitted reservation fails the read. A capacity increase invalidates earlier views.
- `output.beginShape(id, options)` and `output.addStream(input, options)` accept an optional `options` object with `matrix` and `color`. `matrix` is a row-major 4×4 array, typed array, or matrix input and is the model matrix of the shape; `color` is a four-element RGBA tint. Omitted fields are identity and white. With `addStream`, the options apply to every appended shape.
- `output.shapeMatrices` is a `Float32Array` holding 16 row-major values per shape, and `output.shapeColors` is a `Float32Array` holding 4 values per shape. Index them by shape number. A capacity increase invalidates earlier views.
- `output.line`, `output.polyline`, `output.polygon`, `output.circle`, and `output.rectangle` append shapes. Polygons, circles, and rectangles are closed.
- `clamp`, `lerp`, `map`, `radians`, `degrees`, `vec2`, `vec3`, `vec4`, `phase`, and `wave.sine`, `wave.triangle`, `wave.saw`, `wave.square` are available. `phase(time, period)` returns a value in `[0, 1)` for a positive period; wave functions take phase in turns and return values in `[-1, 1]`.

## JavaScript directory package

- A directory package must have the `.ls` extension.
- The package must contain `main.js` at its root as its entry point.
- `main.js` must follow the single-file asset requirements above.
- A `manifest.json` file is not required.

For example:

```text
MyEffect.ls/
├── main.js
├── effects/
│   └── rotate.js
└── resources/
    └── ...
```

