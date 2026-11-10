# JavaScript Asset Protocol

## JavaScript single-file asset

- A single-file LaserScript asset must use the `.js` extension.
- The file must be valid JavaScript.
- The file must begin with a JavaScript block comment containing a JSON object as its header.
- The header must identify the file as a LaserScript asset and specify its LaserScript protocol version.
- The asset must define a `read(context, inputs, output)` function. The host calls it for each read, providing the read context, inputs, and output buffer.
- Inputs are accessed by their declared names, for example `inputs.speed`.

For example (the header key and version are illustrative):

```javascript
/*{
  "LASERSCRIPT": "1.0",
  "INPUTS": [
    { "NAME": "speed", "TYPE": "float", "DEFAULT": 1.0, "MIN": 0.0, "MAX": 10.0 }
  ]
}*/

function read(context, inputs, output) {
  output.beginShape(0);
  output.addVertex(inputs.speed ?? 1, 0, 0, 1, 1, 1, 1, 1, 0);
}
```

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

