# Iterator state qualification

Task [047](../tasks/047-eliminate-generic-iterator-state.md) remains open. The
first checkpoint, `cb3ebec`, removes eligible scalar-only local objects. Generic
adapters and packed List cursors still require separate qualification.

## Scalar local state

Scalar replacement accepts an ownership journal reference only when every
allocation in that copy/version group has an exact scalar layout. Reference,
erased and unknown fields retain heap storage. Calls, captures, returns,
incomplete initialization and unsupported control keep the ordinary fallback. No
source type or adapter name selects this optimization.

Each admitted snapshot receives independent field locals. Copies read all source
fields before writing destinations; demanded fields propagate backwards through
copies and loop carries. F32 fields retain their bits. Replaced objects use zero
as their private address. Their acyclic marker and anonymous journal slot are
removed; scope boundaries and carry-slot clearing retain their original order.
Demand-force markers still prevent replacement.

The companion callable change stores a single checked reference argument
directly in a named partial application's descriptor. Scalar/erased arguments
and later multiple-argument environments retain ordinary storage. Static
serialization, fresh/retained/restart emission and pointer-looking scalar laws
use the same selected layout rule. See
[tracing replacement](TRACING_REPLACEMENT.md).

## Qualified checkpoint

Zig 0.17.0; standard LLVM/Fast release; full native/OOM suite and **965**
guest/client tests pass, including both codegen tiers and all eight unchanged
allocation budgets. The analyzer checks 351 Zig files with zero findings. New
laws cover scalar snapshots, branch exits, nested activations, captured and
reference fallback, sync/JSPI suspension, rejection and subsequent recovery.

The implementation tree is `e8525b1d36c5c30bc81f971d59b296787a83f6cd`; compiler
source is `feefe32c716a268ece1c46171a44f8ad3cd6b6ed`. Executable SHA-256 is
`7c5c3068284f423f0bdd341b1b3b17dc2ee812591146a362b67c3b6a87b9cc2f`, with
identity `8a8562d7e77af1b050fa7cd2fac00e1fb9a64c260d889d42e7cab4fd956c501d`.
Ignored evidence and exact source/harness/report pins live under
`build/bench/iterators-047/`, especially `release/pins.json`.

The same 4,096-step record cursor drops 4,097 object allocations to zero after
journal warmup, and 12,293 slot reservations to 4,100. Both versions preserve
values and finish with zero roots, leases and live profiling payload at
shutdown. Thirty-one alternating warmed release pairs on CPU 7 measure 0.269 to
0.023 ms median guest CPU. This is a scalar record cursor, not a generic adapter
result. The range/map/take control still makes 57,350 allocations; its timing
does not establish adapter elimination.

Seven alternating compiler pairs across 13 public examples preserve diagnostics,
semantic work and per-binary determinism. CPU ratios span 0.9624–1.0321,
requested allocation deltas 0–9,441 bytes, peak deltas zero and teardown zero.
Four synthetic workloads preserve cross-compiler/fresh/retained/restart bytes
and compared counters. No general compiler gain is claimed.

Merged ordinary ownership controls remain flat at 128 KiB. Twenty-five
alternating pairs, discarding five, measure cycle CPU 16.064 to 13.868 ms
synchronously and 16.161 to 13.933 ms with JSPI. Other control ratios span
0.9848–1.0120. The callable implementation's isolated release measurements
remain separate in the tracing record; neither closes task 035's full removal
gate.

## Remaining work

Reference-bearing generic state needs equivalent owned roots, complete producer
exposure and measured benefits before admission. Packed List cursors need
independent private progress, bounded sequential leaf traversal and all-width
comparison with the reconstructed boxed reference. Published cursors, forks,
saved rows, cross-leaf rows, effects and reference fallbacks must remain exact.
Nothing is pushed and rejected/provisional artifacts remain preserved.

## Owning-field and packed cursor checkpoint

Compiler6a57437 adds reusable roots for exact private reference fields and
bounded producer exposure, plus four-local checked packed List cursor families.
The [merged qualification](ITERATOR_CONSTANTS_QUALIFICATION.md) records actual
release counts, CPU/compiler costs, full native/973 guests and355-file zero
analyzer. Array cursors lose4097 objects; range/map/take loses4096. Repeated F32
all-width cursors qualify; U32 boxed tails and other tagged adapters remain
open. Late ownership rollback keeps ordinary source bodies and scalar-only reuse
exact. Projection and word-progress experiments remain separate.
