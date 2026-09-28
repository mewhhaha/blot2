# Memory and concurrency experiments

Starting point: `29bc94d0320d1ca35c47ee7b3695e587a01a8daf`; its compiler code is
identical to `e18ad178d9aea326dad4d8d626b688f25805a191`. The preceding commit
only recorded this experiment plan. All comparisons use the same actual OxCaml
5.2.0+ox toolchain and default build flags.

## Retained changes

Character words are now immediate 64-bit-runtime integers, with explicit U32
conversion at existing scalar boundaries. Unicode order and validation, raw
32-bit character values, F32 bits, and the wire protocol are preserved. Text
construction allocates one 24-byte cons cell per character instead of a cons
cell plus a boxed Int32. U32 ordering, division and remainder use exact native
integer arithmetic instead of intermediate Int64 boxes; comparison paths carry
checked strict zero-allocation annotations.

Request frames remain packed bytes. The string scanner validates in forward
order, then builds the result backward without temporary cursors or reversed
strings. It never stores a frame slice in the syntax or published session.
Response output validates its complete plan before writing, then uses at most 64
KiB of private buffering instead of one complete response-sized buffer.

Tail-modulo-constructor string append and OCaml 5 list append copy one spine,
not two. OCaml 4 retains its stack-safe fallback. Right-associated string joins
avoid repeatedly copying a growing prefix; direct map/set traversals avoid
intermediate binding pairs. No mutable global interning table was introduced.

The bootstrap migration now checks every destination before writing any file,
and refuses to overwrite differing native sources. Reproduction belongs in a new
`--output` directory, not over the optimized implementation.

## Concurrency experiments

The original scheduler is retained. Both experimental pools passed the original
fork/join tests, a real concurrent-domain rendezvous, and 564 new stress checks
covering saturation, uneven nested forks, exception ordering, child joins, and
reuse. Correctness alone did not justify replacing the pool.

A LIFO queue with separate work/completion conditions and fewer success-result
wrappers slowed native requests by 5.5% in a 12-workload, four-requested-worker,
three-pair exploratory comparison. A FIFO version of the same changes initially
improved that metric by 8.2%, but a seven-pair confirmation instead slowed it by
4.8%. End-to-end timings were close to flat and mixed across workloads. These
are variable shared-machine measurements, not evidence for a scheduler speedup.

The production pool still uses its explicitly synchronized legacy Domain
boundary. This pass does not claim mode-checked parallelism, lock-free work
stealing, or an exhaustive idiomatic redesign. Stack-local IR, symbol interning,
unboxed IR products, alternative GC policies, and a mode-checked pool need
separate lifetime and workload experiments; they have not been implemented here.

## Native checks

The retained candidate locally passed 39,283 memory/scalar checks, 1,174
streaming checks, 564 scheduler stress checks, and 3 bootstrap overwrite checks,
in addition to the existing native runtime, name/allocation, Wasm-byte,
concurrency, framing, and build checks. No existing source regression test was
rewritten. Final whole-source comparisons and paired measurements are recorded
in the follow-up result update rather than inferred from these unit checks.

The scanner unit experiment compares against the old allocation-heavy scanner
adapted to the same immediate-character representation: 176 to 24 allocated
bytes per character. This is an isolated operation, not total compiler memory.
Text construction measures 48 to 24 bytes per character against the preceding
representation; copying a list/text spine measures 48 to 24 bytes per element.

## Reproduce

Build the starting point in a separate checkout and retain its native binary.
Build the candidate with the same compiler and flags. Do not run builds or test
suites concurrently with the paired timing experiment.

```sh
make -C compiler/oxcaml test test-build bench-names
deno run -A compiler/oxcaml/bench_compare.ts \
  /path/to/baseline/blotc compiler/oxcaml/_build/blotc \
  build/memory-pairs.json 7 1,4
deno run -A compiler/oxcaml/memory_fixtures.ts build/memory-frames
python3 compiler/oxcaml/bench_frames.py \
  /path/to/baseline/blotc compiler/oxcaml/_build/blotc \
  build/memory-frames build/memory-rss.json
```

The RSS harness requires Linux and `/usr/bin/time`. It compares exact framed
outputs and executable/input hashes. Its peak RSS is for the native process, not
Deno or the whole application. CPU/wall samples include native startup and pipe
I/O but exclude parsing; the paired TypeScript harness records frontend,
full-source, pre-encoded, and incremental phases separately. CI exercises both
harnesses with identical executables, without noisy performance thresholds.
