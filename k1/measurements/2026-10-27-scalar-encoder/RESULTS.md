# Private scalar Wasm encoder experiment

The scheduled private scalar fixture can encode its fixed Wasm sections directly
instead of staging separate temporary code, export, memory and custom-section
buffers. The checked source, semantic charges, plan validation and independent
target verifier still run. This change is limited to that private encoder; it is
not a full compiler speedup, public ABI or complete C09 implementation.

A 15-pair exploratory campaign and a separate 51-pair repeat compared native
Goose `-O2` baseline and candidate binaries. Each sample ran repeated private
scheduled scalar compilations in one fresh process: 2,000 iterations for the
short case, 100 for a 16 KiB ASCII comment, and four for each 1 MiB input.
Timing includes process startup and one source-file read per sample and excludes
compiler self-build; files are in the warm filesystem cache. Each process
checked output length, checksum, semantic count and target-visit count. Separate
before/after runs compared the actual emitted bytes, statuses and tracked
per-phase counters at every semantic budget cutoff for identity, binary and
several invalid cases, and compared bytes/counters on a 1 MiB identifier.
Independent O0/O2 tests compare the original and direct encoders around ULEB
length boundaries and 2 MiB bodies. These checks do not establish full C09,
allocation-failure atomicity or a public target certificate.

The 51-pair repeat, five warmup rounds, CPU 0, reported the following after /
before ratios, with p10/p90 linearly interpolated:

| Workload | Before median | After median | Ratio median | Ratio p10–p90 | Faster pairs |
| --- | ---: | ---: | ---: | ---: | ---: |
| Short identity, 2,000 compilations | 20.687 ms | 20.683 ms | 0.998 | 0.974–1.032 | 28/51 |
| 1 MiB exported identifier, four compilations | 74.217 ms | 71.024 ms | 0.953 | 0.934–0.979 | 50/51 |

For the long-name case the baseline-first median ratio was 0.952 (26 pairs),
candidate-first 0.955 (25 pairs), and first/last campaign halves 0.950/0.957.
This suggests a narrow long-identifier improvement with some temporal
sensitivity. The ordinary case overlaps parity. The exploratory 15-pair
campaign also included 16 KiB/1 MiB ASCII comments and 1 MiB dense/mixed UTF-8
comments; their median ratios ranged from 0.983 to 0.998, with distributions
that overlap parity. It reported 0.963 for the 1 MiB identifier (p10–p90
0.945–1.018). The name workload is an extreme size control, not a typical
project. Neither campaign shows a broad source-compilation improvement.

Cgroup throttling count and throttled time did not increase during either
campaign; the accompanying snapshots preserve all counters. Other-host load,
CPU scheduling and frequency changes were not controlled. Both binaries ran on
one allowed logical CPU of an AMD EPYC 7763; their SHA-256 hashes were:

- Baseline: `b7366cd852b44176a0f97a0da6cd37d51cb88d5f3bfc255e4107feb9d6f4003e`
- Candidate: `9bf23a29dbbfb6b839ba0b99fb714500660c0fdb7e615a054fdbc657c66a635e`

`encoder-speed-results.json` and `encoder-repeat-results.json` contain all raw
samples, source hashes, counters and invocation metadata; the two corresponding
Python scripts are preserved as run. Their `scope` JSON field incorrectly says
“optimized UTF-8 ASCII detection”: it is stale text from a previously rejected
experiment. The hashes and measured binaries above are for the direct Wasm
encoder; the separate UTF-8 unrolling candidate was not integrated because it
regressed ASCII and mixed Unicode workloads. The raw JSON is left unchanged.

The snapshot includes the benchmark driver and the two changed encoder sources,
plus hashes for the scratch Goose sources. It does not include the complete
source snapshot, compiler binaries, Goose standard library or C toolchain;
those hashes alone cannot reconstruct or authenticate the original builds.
Physical byte reads and allocation work were not metered, and direct assembly
changes them. Existing source-byte and target-byte telemetry remains incomplete;
unchanged semantic/phase counters do not establish physical-work parity.
