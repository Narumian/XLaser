# LaserScript Protocol

## Single-file asset

- A single-file LaserScript asset must use the `.js` extension.
- The file must be valid JavaScript.
- The file must begin with a JavaScript block comment containing a JSON object as its header.
- The header must identify the file as a LaserScript asset and specify its LaserScript protocol version.

For example (the header key, version, and function name are illustrative):

```javascript
/*{
  "LASERSCRIPT": "1.0"
}*/

function render(context) {
  // LaserScript implementation
}
```

## Directory package

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

## Read context

For each read, the host must provide:

- `sampleRate`: the intended output rate in points per second.
- `frameLength`: the desired number of output points for that read.

Both values are hints. The asset is not required to produce exactly `frameLength` points. The host is responsible for any final adjustment required by the output.

## Output

The host provides a reusable output buffer for the asset to write into. The output represents 3D shapes before projection, with semantics aligned with XLive's `Laser3DStream`.

The output supports a variable number of shapes and vertices. `frameLength` is a hint, not a strict output limit.

## Input

An asset's laser inputs use the same 3D shape semantics as its output, aligned with `Laser3DStream`. Each read operates on the shape data provided for that read.

## Vertex precision

Position and color components use 64-bit floating-point values.

## Execution errors

If a read fails, its output must not be used and the asset must stop. The host may reinitialize the asset before running it again.
