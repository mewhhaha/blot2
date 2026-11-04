# Numeric scopes and checked row products

Task 041 extends ordinary source SIMD admission. The optimizer retains the
immutable source body and owns every transformed body through failure. No
library name, guessed pointer layout or reducer algebra grants admission.

## Proof boundaries

Counted numeric Array construction now admits private U32/F32 locals and
unconditional lexical block returns. Every written kernel local must be defined
before its first read on each iteration, and have no access outside the kernel.
Parameters, loop-carried state and observable outer writes decline. The existing
count-minus-index bounds proof selects complete four-element runs and leaves the
original scalar tail. Conditional control, memory reads, effects, integer
division/traps and reductions remain ordinary.

The expression proof uses fixed scratch: 128 caller locals, 256 expression
nodes, 16 lexical blocks, six nested calls and 1024 instruction visits. A
private-local proof scans at most 4096 function instructions. A branch may exit
only a proved lexical block inside the kernel; escaping caller control declines.
Skipping unreachable instructions still consumes the proof budget.

Four F32 products from the same checked complete v128 row load and the same
unchanged factor may share one `f32x4.mul`. Each distinct lane must occur once;
the factor and address must match exactly. The first original load stays at its
original position, preserving bounds and trap timing. Every scalar addition
stays in written order. This does not vectorize or regroup a reduction.

The row scan is bounded to 96 instructions per candidate and 4096 per function.
Stores, calls, local writes, control edges, unproved operations, changed factors
and incomplete/duplicate lanes decline. Complete loads already come from the
checked row view or explicit SIMD path. Partial rows and unsupported ownership
layouts retain their ordinary lowering. Both passes are optional in the
development tier.

The joint optimizer interpretation is v9 with `numeric-scopes`, `row-products`,
`forwarded-roots` and `paired-state`; previous optimizer artifacts cannot supply
the new interpretation.

## Executable laws

Native laws require vector stores/products in the actual exported source
function, unchanged Core, exact scalar-add order, conservative declines and
owned output through every allocation failure. Guest laws compare both tiers:
lengths 0–5 and lane/leaf boundaries, U32 wrapping, F32 cancellation/subnormals/
NaNs/infinities/signed zero, record/tuple widths 1–16, Array/List slices, saved
snapshots under pressure, effects, trapping division and recovery. Helper edits
that change vectorizable arithmetic into division compare fresh/retained bytes
and checkpoint restart behavior. Existing row-fusion and explicit-SIMD laws
remain exercised.

An initial guest helper moved temporary files to the system directory. Eleven
older fixtures use repository-relative std imports, so that candidate failed
with missing-file diagnostics. The corrected helper creates the repository build
directory on demand and retains those relative paths. The failed gate and 29-law
focused recovery stay separate. There is no release-build prerequisite for a
fresh development worktree.

## Measured costs

The ordinary baseline is the qualified 040 LLVM/Fast compiler
`9ea894d41e157824dd951e5f92827284da98c59af47c8b5831ebd04623688b21`. The joint
024/035/041 compiler is
`fa471c093d2aaab35fbbbb66c8c1a518c07cbb5586e129143c95db8ff8572387`, 43,325,536
bytes, identity
`f5e382b030f5786409c846c2724b1e1c149f8b500c6518dcbe9347a44da074f6`. Compiler
source is `30c9709fb8e3f176f7bb1bc7250f89a2d78bdd8f`.

CPU 7 measurements use unmodified production Wasm, 100,000 elements, 12 warmups,
31 alternating pairs and 16 calls per sample. Entries return scalars so ABI
array copying does not obscure guest execution. The unequal-factor control
declines the row transformation.

| Optimized workload | Baseline CPU ms | Joint CPU ms | Ratio | Wasm bytes old/new |
| ------------------ | --------------: | -----------: | ----: | ------------------ |
| Integer scopes     |         .097875 |      .049063 | .5013 | 6620 /6746         |
| F32 scopes         |         .073250 |      .041875 | .5717 | 6645 /6778         |
| Array row4         |         .126125 |      .105313 | .8350 | 6834 /6814         |
| Array row8         |         .127250 |      .106500 | .8369 | 6889 /6869         |
| Array row16        |         .129688 |      .117313 | .9046 | 7004 /6984         |
| List row4          |         .109500 |      .099938 | .9127 | 11288 /11268       |
| List row8          |         .112750 |      .101438 | .8997 | 11371 /11351       |
| List row16         |         .126375 |      .120500 | .9535 | 11541 /11521       |
| Unequal factors    |         .129438 |      .129188 | .9981 | 6834 /6834         |

Committed guest memory is identical in every pair: generators 655,360 bytes;
Array widths 4/8/16 are 2,228,224 /4,325,376 /8,519,680 bytes; List widths
4/8/16 are 1,900,544 /3,735,552 /7,405,568 bytes. No memory reduction is
claimed. Development and unequal-factor artifacts are byte-identical across
compilers.

Three earlier isolated batched screens retain integer ratios .3489–.3497 and F32
ratios .5728–.5734; Array 4/8 .8336–.8383, List 4/8 .9051–.9139. Widest List
ratios vary .9271–1.0402. Identical development Wasm also varies at the widest
shape, so no reliable widest-List speedup or general runtime bound is claimed.
That provisional isolated binary is preserved; it predates a deprecated-bitset
spelling correction and is not the accepted joint compiler.

Seven joint fresh/20-edit pairs measure optimized fresh wall 5.256→5.308 ms,
20-edit wall 97.158→99.205 ms and child CPU 50→50 ms. Development fresh wall
4.949→4.861 ms, 20-edit wall 95.231→93.933 ms and child CPU 50→50 ms. Fresh
child CPU is below the 10 ms tick resolution. Every retained output equals its
matching fresh/restarted output within each compiler; all graceful closes report
zero live bytes. These small clocks establish no compiler speedup.

Seven public cold pairs over 13 examples preserve diagnostics, semantic/prepared
counters, per-compiler output stability and zero teardown. CPU ratios are
.9966–1.0173, requested allocation deltas−227,737..0 bytes and peak deltas zero.
Eight public Wasm outputs intentionally change; five remain byte-identical.
Synthetic fresh/retained/restart output is byte-identical across compilers.

Implementation `850793f`, tree `ee33b8b58c9cd979405d7ba10bd9864d27dacf46`,
passes `deno task test:compiler`: the complete native suite, 936 guest/client
tests and all eight unchanged allocation budgets. Zig 0.17.0 analyzer checks 350
files with zero findings. The corrected full gate takes 4m5s for guest
execution; the unchanged native/build steps reuse the passing first gate.

Exact distributions, compilers, harness pins, source trees, full-gate logs and
failure records live under ignored `build/bench/joint-024-035-041/`; isolated
screens are in `build/bench/numeric-simd-041/`. Tasks 024/035 retain their
broader open gates.
