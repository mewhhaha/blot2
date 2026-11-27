# Four route queries in a browser frame

The headless browser executed Gdev's original four ordered route queries on 20 November 2026. Every measured frame checked the complete applied result bit for bit against the ordinary batched guest entry. Prepared Web Workers used isolated guests and transferable numeric buffers. The worker path includes splitting work, posting and waiting, assembling every result and selecting the winning route. The direct control calls the existing Gdev `serial_shared` entry. Two additional workers doing sustained routing supplied the contention condition.

| Other busy workers | Pool size | Direct p50 / p95 / p99 ms | Worker p50 / p95 / p99 ms | Pool setup ms | Pool linear memory MiB |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 0 | 1 | 0.370 / 0.440 / 0.735 | 0.595 / 0.845 / 1.150 | 19.53 | 47.1 |
| 0 | 2 | 0.365 / 0.490 / 0.575 | 0.525 / 0.645 / 0.695 | 17.09 | 94.1 |
| 0 | 4 | 0.310 / 0.490 / 0.525 | 0.510 / 1.760 / 2.325 | 18.52 | 188.2 |
| 0 | 8 | 0.335 / 0.420 / 0.580 | 0.430 / 0.680 / 1.020 | 70.79 | 376.5 |
| 2 | 1 | 0.310 / 0.335 / 0.350 | 0.550 / 0.650 / 0.705 | 14.38 | 47.1 |
| 2 | 2 | 0.300 / 0.345 / 0.460 | 0.455 / 0.620 / 0.820 | 13.43 | 94.1 |
| 2 | 4 | 0.310 / 0.350 / 0.405 | 0.405 / 0.555 / 0.855 | 19.46 | 188.2 |
| 2 | 8 | 0.305 / 0.355 / 0.395 | 0.390 / 0.505 / 0.600 | 24.47 | 376.5 |

Four queries occupy at most four workers. An eight-worker pool still pays startup and linear memory for eight instances. Workers lost to the direct path at every median. These figures measure work within an animation frame. The raw samples also record the interval to the next animation callback, the first execution in each mode, the direct fixed-row control, shard dispatch, join, and application. Across modes headless Chrome scheduled frames at roughly 16.7–66.7 ms. This fixture runs routing and world-result selection without a game renderer. High percentiles summarize 101 frames per cell.

The measured module is 43,704 bytes, SHA-256 `02c5435658143507729872b6b6636b1a4e9e479cc7c0e01296b8a59aec2f2a69`. It uses Gdev `54f299a` and Ink `77697fe`. Reproduce from the Squid root with a local Chrome executable.

```sh
SQUID_ROUTE_WASM=build/routes.wasm deno run -A benchmarks/language/spark_spawn.ts ../gdev compiler-goose/build/squidc-goose
python3 benchmarks/language/bench_browser_routes.py --chrome /path/to/chrome --wasm build/routes.wasm --output build/browser-routes.json.gz
```

[Raw frames, Chrome version, affinity and cold setup](../evidence/measurements/spark-browser/routes.json.gz)

## Compiling and editing the fixtures

The native Squid compiler built the 23-module Gdev route fixture in **167.4 ms**
from a fresh session. Editing the spawned route planner's initializer took
**20.2 ms** and rechecked one module. The two-module scalar fixture took
**72.5 ms** fresh and **10.0 ms** after changing the multiplier inside
its spark. These are medians across six sessions per fixture. Both directions
of each edit produced the same Wasm as a fresh build of that source. The
edited entry point returned the expected value in all 24 executions.

Reproduce with `deno run -A benchmarks/language/spark_compile.ts ../gdev`.
[Individual builds, module counts and hashes](../evidence/measurements/2026-11-20-spark-compile.json)
