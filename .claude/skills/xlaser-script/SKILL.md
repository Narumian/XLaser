---
name: xlaser-script
description: Write, run, test and benchmark LaserScript assets (.js single files and .ls packages) for XLaser. Use when creating or editing a laser animation or effect script, checking that it runs on the JavaScriptCore/V8 engines, or measuring read() performance with LaserScriptBench, XLaserInputBench or XLaserV8Bench.
---

# XLaser LaserScript

A LaserScript asset is JavaScript that the host calls once per read to write 3D laser shapes into a buffer. This skill covers writing one, running it, and benchmarking it. It does not restate the spec.

## Source of truth

Read these before writing. Do not copy their content into scripts, comments or this skill; they change.

- `Protocol.md`: asset metadata, input types, read context, output/input/buffer rules, precision, errors.
- `JavaScriptProtocol.md`: the JS file format, header, input value shapes, helpers, `.ls` packages.
- `Sources/XLaser/Resources/LaserScript.js`: the real runtime. When a doc and this file disagree, the code wins. Check here for what `output.*`, `Vertex`, `Color`, `Mode` actually do.
- `README.md` is not to be edited by agents.

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
