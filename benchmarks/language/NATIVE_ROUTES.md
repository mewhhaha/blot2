# Native route stage breakdown

The Pen fixture measured host snapshot preparation, job admission, queue latency,
blocking receive, result assembly and route selection on the same ABI 8 module
used for the [browser comparison](BROWSER_ROUTES.md). The copied path keeps the
one-shot sandbox per job. The direct control calls Gdev's existing
`serial_shared` entry for four routes and `routes` once for 128 queries.
Eleven alternating direct and copied samples follow four warmups in each cell.
Every output is compared bit for bit with the direct answer. No renderer runs.

| CPU affinity | Queries | Workers | Direct total µs | Copied total µs | Host snapshot µs direct / copied | Admission µs | Slowest job queue µs | Receive µs | Assembly µs | Apply µs | Payload copies B direct / copied |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| unrestricted | 4 | 1 | 280.89 | 536.31 | 0.04 / 0.87 | 3.05 | 5.07 | 513.64 | 0.86 | 16.78 | 4,696 / 21,216 |
| unrestricted | 128 | 1 | 10976.96 | 9642.07 | 1.85 / 2.43 | 4.70 | 7244.87 | 9620.76 | 8.93 | 0.34 | 402,952 / 603,680 |
| unrestricted | 4 | 2 | 281.48 | 439.43 | 0.04 / 0.97 | 3.06 | 8.94 | 415.76 | 1.29 | 16.62 | 4,696 / 21,224 |
| unrestricted | 128 | 2 | 8515.89 | 7125.86 | 1.25 / 2.56 | 4.17 | 3563.41 | 7105.30 | 15.62 | 0.27 | 402,952 / 603,680 |
| unrestricted | 4 | 4 | 284.50 | 1339.69 | 0.05 / 1.51 | 4.22 | 25.86 | 1304.16 | 2.17 | 18.30 | 4,696 / 21,240 |
| unrestricted | 128 | 4 | 8427.12 | 5934.48 | 1.23 / 2.52 | 4.66 | 37.28 | 5909.89 | 12.95 | 0.21 | 402,952 / 603,680 |
| unrestricted | 4 | 8 | 283.59 | 1847.50 | 0.04 / 1.37 | 4.16 | 28.80 | 1818.86 | 2.16 | 17.54 | 4,696 / 21,240 |
| unrestricted | 128 | 8 | 8611.43 | 6917.82 | 1.51 / 3.38 | 5.73 | 83.04 | 6879.57 | 19.62 | 0.50 | 402,952 / 603,712 |
| two physical cores | 4 | 1 | 542.55 | 547.04 | 0.08 / 1.08 | 3.67 | 5.67 | 508.21 | 1.29 | 31.63 | 4,696 / 21,216 |
| two physical cores | 128 | 1 | 13873.36 | 10412.48 | 2.42 / 3.89 | 7.55 | 7551.59 | 10381.33 | 11.93 | 0.43 | 402,952 / 603,680 |
| two physical cores | 4 | 2 | 272.38 | 722.76 | 0.04 / 1.48 | 4.00 | 9.69 | 693.88 | 1.84 | 17.55 | 4,696 / 21,224 |
| two physical cores | 128 | 2 | 8311.49 | 6067.76 | 1.78 / 3.15 | 6.48 | 3073.33 | 6018.61 | 18.96 | 0.56 | 402,952 / 603,680 |
| two physical cores | 4 | 4 | 279.73 | 1424.80 | 0.05 / 1.81 | 4.77 | 780.70 | 1382.13 | 3.17 | 19.16 | 4,696 / 21,240 |
| two physical cores | 128 | 4 | 8296.54 | 5999.65 | 1.63 / 2.83 | 5.07 | 2209.31 | 5968.34 | 15.35 | 0.51 | 402,952 / 603,680 |
| two physical cores | 4 | 8 | 273.61 | 1661.20 | 0.05 / 1.92 | 5.15 | 933.03 | 1620.46 | 3.90 | 19.82 | 4,696 / 21,240 |
| two physical cores | 128 | 8 | 8270.91 | 7408.78 | 1.64 / 3.51 | 6.00 | 5224.99 | 7371.30 | 18.54 | 0.53 | 402,952 / 603,712 |

Each column is a median. Admission includes validation and submissions. Queue
latency runs from submit to worker start. Receive sums time inside channel
receives, overlapping job queueing and execution. The raw trace also records
each job's sandbox construction, guest call and disposal as one span. The
direct entry fuses geometry construction, route computation and selection in
one timed call. At 128 queries the fixture returns ordered lanes, so host
application just checks their shape.

Host snapshot timing covers constructing the seed/query packets from immutable
host data. The seed is already a scalar for the four-route direct control. Each
successful guest call builds the small fixture geometry within the timed call.
No production world snapshot is extracted. The copy columns count numeric
payload bytes for each site, including the two host transfers, guest ABI
unpack and pack, result assembly and selection. Packet headers, kernel work
and memory-system traffic are excluded. The worker channel moves Rust vectors
without duplicating their buffers.

## Forced recovery

In a separate four-route sample, the driver submits one empty ABI packet so the
guest traps on its seed lookup. It waits for the submitted batch, discards every
reply and computes the whole answer from the original input via `serial_shared`.
Each run sees one Wasm trap and a bit-exact recovered result. This tests the
recovery cost in the fixture. The Pen worker receives still block without a
deadline.

| CPU affinity | Workers | Receive µs | Direct recovery µs | Total µs | Payload copies B attempt / recovery |
|---|---:|---:|---:|---:|---:|
| unrestricted | 1 | 201.53 | 345.82 | 559.72 | 16 / 4,696 |
| unrestricted | 2 | 432.98 | 282.20 | 721.90 | 6,312 / 4,696 |
| unrestricted | 4 | 1295.71 | 278.79 | 1590.95 | 9,472 / 4,696 |
| unrestricted | 8 | 1901.13 | 571.26 | 2374.62 | 9,472 / 4,696 |
| two physical cores | 1 | 401.73 | 409.05 | 877.25 | 16 / 4,696 |
| two physical cores | 2 | 599.52 | 276.12 | 888.50 | 6,312 / 4,696 |
| two physical cores | 4 | 1119.61 | 280.81 | 1418.48 | 9,472 / 4,696 |
| two physical cores | 8 | 1182.79 | 281.64 | 1483.18 | 9,472 / 4,696 |

## Reproduce

These diagnostic timings were collected separately from the
[untraced comparison](../evidence/measurements/2026-11-20-spark-process-drivers.json).
The trace uses Pen `360f2c4`, Rust 1.99.0, Wasmtime 49.0.3 and the debug host
profile on a Ryzen 7 3800X. The restricted run uses CPU 0 and CPU 1, two
physical cores. Module SHA-256 is `02c5435658143507729872b6b6636b1a4e9e479cc7c0e01296b8a59aec2f2a69`.

From the Pen checkout, using the route fixture built by Squid's
[`spark_spawn.ts`](spark_spawn.ts) with `SQUID_ROUTE_WASM` set to the path below.

```sh
cargo build -p squid-host --example compare_routes
target/debug/examples/compare_routes ../squid-lang/build/issue-qualification/routes-final.wasm --stages
taskset -c 0,1 target/debug/examples/compare_routes ../squid-lang/build/issue-qualification/routes-final.wasm --stages
```

[Per-job timings, per-site copy counts and paired samples](../evidence/measurements/2026-11-20-native-route-stages.raw.json.gz)
