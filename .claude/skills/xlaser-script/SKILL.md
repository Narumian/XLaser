---
name: xlaser-script
description: Write, run, preview, test and benchmark LaserScript assets (.js single files and .ls packages) for XLaser. Use when creating or editing a laser animation or effect script, looking at what it draws, checking that it runs on the JavaScriptCore/V8 engines, or measuring read() performance with LaserScriptBench, XLaserInputBench or XLaserV8Bench.
---

# XLaser LaserScript

A LaserScript asset is JavaScript that the host calls once per read to write 3D laser shapes into a buffer. This skill covers writing one, previewing it, running it, and benchmarking it. It does not restate the spec.

## Source of truth

Read these before writing. Do not copy their content into scripts, comments or this skill; they change.

- `Protocol.md`: asset metadata, input types, read context, output/input/buffer rules, precision, errors.
- `JavaScriptProtocol.md`: the JS file format, header, input value shapes, helpers, `.ls` packages.
- `Sources/XLaser/Resources/LaserScript.js`: the real runtime. When a doc and this file disagree, the code wins. Check here for what `output.*`, `Vertex`, `Color`, `Mode` actually do.
- `StandardLibrary/CONVENTION.md`: how library assets are laid out, named, headed and written (Japanese). Follow it when adding or changing anything under `StandardLibrary/`.
- `README.md` is not to be edited by agents unless the user asks.

## Writing an asset

1. Start from the closest existing asset, not from scratch.
   - Generator: `StandardLibrary/Animations/*.js`.
   - Effect that takes a `laser` input: `StandardLibrary/Effects/Rotate.js` (`output.addStream(inputs.source)`, then edit `output.values` in place).
   - Every helper and output call in one place: `Debug/Helpers.js`.
2. The file starts with a `/*{ ... }*/` JSON header (`LASERSCRIPT` version, `NAME`, `INPUTS`, ...) and defines `read(context, inputs, output)`.
3. Declare every input in `INPUTS` with `TYPE`, and `DEFAULT`/`MIN`/`MAX` for numbers. When the host supplies no value, a declared input falls back to its `DEFAULT`; with no `DEFAULT` it is absent, so guard those (`laser`, `image`, `audio` and `audioFFT` inputs never have defaults).
4. Put loop-invariant work outside the per-vertex loop and state in module-level `let` only when the effect really needs history. State persists across reads and is lost when the engine is reinitialised after an error.

Pitfalls worth remembering:

- A vertex is 8 floats (position xyzw, color rgba) plus a mode. `Mode.blank`, `Mode.dwell` and `Mode.normal` are the only modes. Reserved-but-unwritten modes default to `blank`.
- After `output.reserveVertices(n)` you must `output.commitVertices(count)`. An uncommitted reservation fails the read.
- Growing the buffer (`reserve`, or any append that grows it) invalidates earlier `output.values` / `output.modes` views. Re-fetch them after growth.
- Inputs are read-only and valid only during the current read. Never mutate them or keep a reference.
- Output is valid until the next read begins. `frameLength` is a hint, not a limit.
- Values are Float32. Compare with a tolerance around 1e-6, never 1e-12.
- A thrown error fails the read; the host may reinitialise the asset. Throw `Error`s for bad input instead of producing garbage.

## Previewing an asset

`XLaserPreview` runs an asset and renders what it wrote to a PNG, so you can look at it. Run it after every non-trivial change to a script, then open the PNG with the Read tool and compare it with what the script was meant to draw.

```bash
swift run -c release XLaserPreview StandardLibrary/Animations/PulsingCircle.js --times 0,0.25,0.5,0.75 --out preview.png
```

- Several reads become a grid of tiles in the given order (`--times a,b,c`, or `--frames N --duration SECONDS`). They run in order on one engine, so assets that keep state between reads look the way they do in playback. Do not assume read `t=1` equals a fresh read at 1.
- `--input name=value` sets a declared input (vectors and colors as `1,0,0,1`). An unknown name fails and lists the declared ones.
- An effect needs something to chew on: `--laser source=StandardLibrary/Animations/RotatingLine.js` feeds another asset's output into the laser input `source`. Without it the tool says the input is not fed.
- `--blanks` also draws blanked moves in dark gray, which shows where the beam travels while off. `--size`, `--columns`, `--sample-rate`, `--frame-length`, `--engine auto|jsc|v8` are available. `--help` lists everything.
- `--yaw DEG` and `--pitch DEG` turn the view, so 3D assets can be inspected from the side. Use them whenever an asset uses z: at the default view z is invisible. Positive yaw swings the far (+z) side to the right, positive pitch swings it up. Look from at least two angles (for example `--yaw 35 --pitch 20` and `--yaw 90`) before concluding a 3D shape is right.
- `--shape 2,4` draws and reports only those shape IDs; use it to isolate one shape of a busy buffer.
- Write previews to the scratchpad or another throwaway path, not into the repository.

Reading the report. It prints one line per read, then one line per shape (up to 12 shapes, or all with `--shapes`): ID, start index, vertex count per mode, and the x/y/z extent. Check it before the picture:

- `empty output`, or every vertex blank, is a script bug, not a rendering bug.
- `outside-unit-cube` means vertices beyond -1...1 on some axis. They are clipped in the picture, and in playback the projection clamps or cuts them depending on the screen mode.
- `non-finite` means NaN or infinity was written. Fix the script.
- Per-shape notes flag empty shapes, single-vertex shapes and shapes with nothing lit. Shape IDs used more than once are reported too. The buffer allows duplicates and the preview draws them as separate shapes, but the ID is what identifies a shape, so reuse one only on purpose.

What the picture is. An orthographic view of the shapes as the asset wrote them, before any projection, masking, dwell/blank insertion or scanner settings. x is right, y up, z away from the viewer; the vertex `w` is ignored. The dim cube is -1...1 on every axis, with its axes: positive x, y and z halves in red, green and blue. The drawing shrinks when a turned cube would not fit, so compare sizes only within one picture. There is no depth shading, so nearer and farther parts look alike; turn the view to tell them apart.

Drawing rules. A segment is drawn from the previous vertex of a shape to each vertex that is not blank, in that vertex's color (no gradient between vertices). Blank vertices draw nothing. Dwell vertices are large dots. Nothing joins two shapes. Color is `rgb * alpha` limited to 0...1 on black; overlapping lines keep the brighter value instead of adding up, and no gamma is applied, so brightness will not match a real scanner. The picture does not show how the beam sweeps in time, flicker, or what a scanner does to sharp corners. Use it to judge shape, size, color, blanking, shape structure and motion across reads; do not use it to judge point density or output timing.

## Running an asset

Pick the narrowest check that answers the question. All commands run from the `XLaser` package root.

```bash
swift test --filter XLaserTests          # buffer, input resolver, descriptor (portable)
swift test --filter XLaserAppleTests     # JavaScriptCore engine, runs Debug/ and StandardLibrary assets
swift test --filter XLaserV8Tests        # only meaningful when V8 is enabled (see below)
```

- To test a new asset, add a test beside the existing ones in `Tests/XLaserAppleTests/JavaScriptCoreEngineTests.swift`: load the `.js`, make a `JavaScriptCoreEngine(source:)`, call `read(context:inputs:output:)` with a `LaserReadContext` and a `Laser3DBuffer`, then assert on `output.withUnsafeBuffers { shapes, values, modes in ... }`. Check `engine.descriptor` for header parsing.
- Put throwaway assets in `Debug/`. The Apple tests already load `Debug/RotatingLine.js` and `Debug/Helpers.js` by path.
- `node Debug/Run.js` runs `Debug/RotatingLine.js` in a Node `vm` against the real `LaserScript.js` runtime. It is a fast loop without a Swift build, but it is a separate harness: confirm anything important in the Swift tests too. Its assertions must use Float32 tolerance; if it fails with a tiny numeric difference, the tolerance is the problem, not the script.
- Standard library assets live in `StandardLibrary/Animations` and `StandardLibrary/Effects` (`LaserStandardLibrary.urls(in:)` lists the `.js` files). Adding a file there ships it.

### V8

V8 is optional and off by default. `V8Engine.isAvailable` is false and V8 tests/benchmarks silently do nothing unless the package is built with all of:

```bash
XLASER_V8_INCLUDE=<v8 include dir> XLASER_V8_LIBRARY=<path to libv8 monolith> XLASER_V8_CXX_FLAGS="<extra flags>" swift test --filter XLaserV8Tests
```

If the benchmark output has no `V8` rows, V8 was not enabled. That is not a failure. Do not claim a V8 result you did not see.

## Benchmarking

Always use release builds. Debug builds are meaningless for timing.

| Target | What it measures | Command |
|---|---|---|
| `XLaserInputBench` | Main benchmark. Many scenarios, per engine, median and p95 in ms | `swift run -c release XLaserInputBench` |
| `LaserScriptBench` | Quick JavaScriptCore check: passthrough and generate, 10 shapes x 1000 vertices | `swift run -c release LaserScriptBench` |
| `XLaserV8Bench` | V8 passthrough only (needs V8 enabled) | `swift run -c release XLaserV8Bench` |

`XLaserInputBench` prints CSV: `engine,scenario,iterations,median_ms,p95_ms`, one row per engine per scenario. Narrow it with a substring filter:

```bash
XLASER_BENCH_FILTER=generate_1k swift run -c release XLaserInputBench
```

Scenarios cover: a 1-vertex baseline, six parameters (passed, declared, defaulted), laser passthrough at 1k and 10k vertices, five ways to generate 1k vertices (`addVertex` loop, direct typed-array writes, `reserveVertices`+`commitVertices`, the same with a bulk `modes.fill`, and `addVertices` batch), and image (512 and 1080p RGBA), audio and FFT inputs.

Reading the numbers:

- Compare scenarios only within one run on one machine, and engines only on the same scenario. Absolute ms do not transfer between machines.
- The point-by-point `output.addVertex` path is several times slower than reserve/commit, direct writes or batch `addVertices`. If a hot asset loops over `addVertex`, move it to one of the faster paths and re-measure.
- Every scenario validates its output (vertex count, and for `generate_*` the shape table and sample values). A thrown `invalidOutput` means the engine or runtime produced the wrong result, so fix correctness before reading any timing.
- Run on an otherwise idle machine, and repeat once. If median and p95 are far apart, the run was noisy.

### Benchmarking a new asset or scenario

- To time one asset, add a `Scenario` to `Tools/InputBench/main.swift` with `source`, `inputs`, expected `vertices`, `iterations` and `warmup`. Give it a distinctive name so `XLASER_BENCH_FILTER` can isolate it, and include an output check the way the existing scenarios do.
- Keep loop-heavy scenarios at 500+ iterations with 100+ warmup reads so JIT warm-up is excluded.
- Before and after an optimisation, run the same filtered command both times and quote both rows. Do not quote numbers from memory.

## Reporting

When you finish, say which commands you actually ran, whether V8 was enabled, and which numbers you measured. Say plainly if a check could not run (for example, V8 unavailable).
