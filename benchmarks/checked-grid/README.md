# Checked array and grid workloads

This suite compares Squid and safe Rust kernels in Pen's release Wasmtime engine. Trees walks four sightlines from each cell. Hills runs a reverse breadth-first search with a fixed-capacity queue. The other fixtures isolate scalar reads, initialized writes, local views, rectangular text parsing and packet overhead.

Run from the Squid checkout with Rust 1.99.0 and its wasm32-unknown-unknown target. Use Pen commit `3a6a531` or a descendant with the packet measurement example.

```sh
(cd ../pen && cargo build --locked --release -p squid-host --example measure_packets)
python3 benchmarks/tools/bench_checked_grid.py --out build/checked-grid
```

Use `--baseline /path/to/second/squidc-goose` to compare compiler revisions in the same randomized rounds. On Linux, prefix the Python invocation with `taskset -c N` to pin the compiler and guest processes. Each mode compiles and loads its own AOT artifact from identical Wasm. The first invocation is timed separately. Warm guest time includes ABI decoding inside the exported solve function. The host measures reset, allocation and input copying before the call, then measures output copying, verification and invocation cleanup after it. Rust receives the same scalar packet. Its text adapter narrows validated ASCII input for its rectangular parser. Neither grid uses private puzzle inputs.

The default seven rounds each use a fresh process per kernel, implementation and engine mode. Five warmups precede 25 measured calls on the same instance. The 120 × 120 grid is first, followed by small result and trap witnesses. Each trap case is followed by a valid call on the same instance. The suite also times fresh Squid compiler processes separately. See `samples.json.gz` for hashes, exact witnesses, per-call and cold-stage times, peak process RSS and guest linear memory. `summary.json` gives medians and nearest-rank p95s. Individual cold process and compile measurements have fewer observations than steady guest time.

Inspect an artifact directly with `objdump -d --no-show-raw-insn build/checked-grid/trees-squid-inline1.cwasm`. The named function symbols include the Squid function name. A static call count measures emitted instructions. The guest timer measures their runtime effect.

[Measurements and application checks](../../tasks/121-qualify-and-measure-owned-applications.md#checked-arrays-and-release-inlining)
