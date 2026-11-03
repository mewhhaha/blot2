# Goose direct Wasm comparison

Run translated LangArena kernels against the sibling Goose compiler's direct
Wasm backend. Both artifacts execute in the same Node/V8, checking every
checksum. All seven adapted cases are attempted: four original-numeric pairs, an
explicit Mandelbrot F32 control, and two sorting ports blocked by owned-storage
recursion. Original F64 Mandelbrot and the other 43 catalog tasks remain outside
paired coverage. The custom eight-lane `Hash::SHA256` task is not cryptographic
SHA-256.

[Expanded survey, 2026-11-03](results/2026-11-03-expanded.md) records current
pairs, failed builds and diagnostic source controls. The
[fixed-span checkpoint](results/2026-11-03-fixed-spans.md) and
[original baseline](results/2026-11-03.md) retain preceding results. With
Matplotlib installed, `python3 scripts/bench/goose/charts.py` regenerates the
README's SVG charts from pinned evidence without running benchmarks.

```sh
python3 scripts/bench/goose/compare.py \
  --node /path/to/node-v24.22.1 \
  --output build/bench/goose-comparison
```

Requires installed release `zig-native/zig-out/bin/blotc` and
`../goose-to-wasm/build/bin/goose` with its adjacent `stdlib`. No compiler
rebuild is performed. Use `--blotc`, `--goose-root`, `--goose`, `--node` and
`--deno` to select installations. Each output directory must be new or empty.

Defaults: five fresh builds per case/backend for each of cold source and a
revision edit; one process warmup and five measured runtime samples; official
`test` and explicitly bounded runtime profiles. All children have a hard
30-second cap. A failing runtime cell is stopped after its first failure, while
other cells finish. Failed/timed-out cells never receive a performance score.
The default survey currently exits nonzero with partial results because both
Blot sorting builds are unsupported. Use `--cases sieve mandelbrot_f32` (or
other supported cases) for a fully runnable subset. Build diagnostics are
retained as structured data, not missing or zero timings.

Use `--profiles run` to request unchanged official production iteration counts.
The first production pilot hit the cap on all three Blot programs. That evidence
is retained separately; bounded results do not replace it.

| Bounded case   | Production problem size | Measured iterations | Kernel warmups |
| -------------- | ----------------------: | ------------------: | -------------: |
| Fannkuch       |                   n = 8 |                   8 |              2 |
| CRC32          |         1,000,000 bytes |                   4 |              1 |
| Custom hash    |         1,000,000 bytes |                  64 |             13 |
| Sieve          |         limit 3,000,000 |                   4 |              1 |
| Merge sort     |        400,000 elements |                   4 |              1 |
| Quicksort      |        400,000 elements |                   4 |              1 |
| Mandelbrot F32 |               400 × 400 |                   4 |              1 |

Only the repetition counts change. The kernels, production input sizes, fixed
buffer capacities and cumulative checksum state across warmup remain intact.
`reference.py` independently checks official small and production checksums,
then generates bounded expectations. CRC uses Python's zlib; the other oracles
use independent implementations. Run it separately with:

```sh
python3 scripts/bench/goose/reference.py
```

Cold compilation measures complete fresh driver process wall time with artifact
caches disabled; OS and installed-library caches remain warm. Blot uses the
optimized codegen tier, with compilation profiling disabled. Pass
`--profile-backend` only for a diagnostic run; allocation counting and detailed
clocks change compile costs. Goose uses
`--backend direct
-O2 --no-cache --offline`. Driver/native phase measurements
are retained separately. The revision edit changes an observable export/exit
value from 0 to 1 and must change the Wasm bytes while preserving the kernel
checksum. It also uses a fresh uncached process; this does not measure
retained-session edits.

Runtime clocks surround the guest's measured loop. Preparation, kernel warmup,
engine compilation, instantiation, output and checksum validation stay outside.
There are no host calls per element. Blot crosses its Array U32 capability ABI
twice for the clock; Goose crosses two scalar imports. The measured Blot region
includes the start reply and stop request packet costs. These are translated
program comparisons including their ABI costs, not isolated instruction tests.
Both processes parse the common TypeScript host; process wall is not the
standalone Goose runner's startup score. Engine compile/instantiate and entry
times have separate fields. V8 is the only engine measured here.

Blot uses nonnegative U32 indices and wrapping checksum arithmetic instead of
Goose's wider scalar plumbing. Hash inputs retain identical byte values, but use
U32 elements instead of Goose's U8 elements. Owner metadata, checks and language
ABI also differ. Sieve flags and retained Mandelbrot bytes also use U32 versus
U8. Both Mandelbrot sources explicitly use F32, with per-operation rounding
checked by the independent oracle; the original F64 result differs. Sorting
ports accept only the official 100,000/400,000 sizes, where their exact integer
RNG conversion matches every Goose F64 RNG state. They preserve the recursive
algorithms and remain runtime-unqualified until the backend supports them. No
algorithm shortcut removes unused digest lanes: all eight lanes and the complete
32-byte digest remain in both sources. These differences must accompany runtime
and output-size comparisons. The tiny source fixtures do not establish Gdev
performance or large-source compiler throughput.

Builds finish before runtime measurements. Runtime samples pair both backends
with seeded shuffled order. Reports include individual observations, median,
MAD, quartiles, sizes and paired ratios. Ratios require at least five valid
pairs and median kernel regions of at least 10ms in both programs. Small-input
rows are correctness evidence only. Measurements run on a shared host; inspect
dispersion before interpreting close results.

The runner freezes both installed compiler binaries, Goose's standard library
and its original JavaScript runtime. It records compiler SHA-256,
source/host/std hashes, tool versions, CPU affinity and checkout state. An
installed binary is not assumed to match a dirty checkout. Inputs are checked
again at completion. Only private staged sources are edited. Sibling source and
generated outputs are untouched.

Outputs:

- `report.json`: full raw observations, driver profiles, commands and logs.
- `summary.json`: portable evidence with timing observations and fingerprints.
- `report.md`: readable tables and coverage/failure notes.
- `frozen/`, `sources/`, `builds/`, `qualification/`, `runtime/`: exact local
  artifacts and per-child command/stdout/stderr evidence.

The ports preserve the upstream MIT attribution in
[ports/LICENSE](ports/LICENSE). The new recursive sorting ports expose an actual
owned-backend restriction; their failures and lack of runtime scores remain
visible. The original F64 workload is not replaced by the separately labelled
F32 control.

Independent checksum and precision regression tests:

```sh
python3 -m unittest discover -s scripts/bench/goose -p test_reference.py
```
