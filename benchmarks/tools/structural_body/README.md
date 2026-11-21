# Replaying a structural Gdev edit

This Linux benchmark keeps a direct-backend generator alive, lowers a changed
named function against the new checked modules, and assembles a complete Wasm
image. Each trial starts from its own baseline and compares its output with a
separate fresh Gdev build. The experiment is isolated from the project server.

From the Blot repository root, with the patched Goose toolchain and profiled
Blot compiler already built, run

```sh
python3 benchmarks/tools/structural_body/build.py
deno run -A benchmarks/tools/structural_body/capture.ts
python3 benchmarks/tools/structural_body/run.py --rounds 12
```

The workload uses Gdev `cc4bbbf`, Ink `77697fe`, and the 293-module Main
graph. Set `BLOT_COMPILER` to select another capture executable. Capture writes
source overlays to fresh compiler sessions and keeps the sibling trees intact.
The capture library reads the completed worker queue using the matching
compiler's native queue layout. Each capture also compiles its overlay with the
ordinary executable and validates the complete Wasm.

The runner alternates timing order, emits results in a new temporary directory
per trial, and checks the initial and edited images against the capture. An
accepted trial must produce identical bytes. A rejected trial must produce
no candidate. The runner records timings in `build/structural-body/runs.json.gz`
and medians, compiler identity, and body differences in `summary.json`.

`compareNs` covers the comparison of already decoded modules and edit selection.
`replayNs` includes repairing revision-local type mappings, checking lookup
order, and assembling accepted images. `fullNs` times a fresh emission in the
same instrumented binary with tracing disabled. Capture, decoding, retaining
the initial generator, oracle comparison and file I/O are outside those timers.
