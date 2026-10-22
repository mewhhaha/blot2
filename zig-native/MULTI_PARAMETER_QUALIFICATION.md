# Multi-parameter and named-call qualification

Issue #22 permits `fn a b => body` as source shorthand for
`fn a => fn b => body`. The final result annotation belongs to the last
stage. Calls remain left-associative, so partial application and higher-order
use have exactly the same lowering as the explicit form. A record parameter
provides named fields at a call site; the field names belong to its public
type. Field expressions run once in written order. Code that must perform
effects between curried stages keeps the explicit nested form.

The executed-Wasm tests cover four same-typed arguments, partial application,
a generic callback, record field reordering, effect order across positional and
record arguments, an effectful first stage, exact generated-size and allocation
parity with explicit currying in both tiers, and positioned unknown/duplicate
field diagnostics. The parser and formatter laws cover the AST chain and final
result annotation; the editor corpus covers parameter-list highlighting and
parsing. The combined full compiler gate passed 2,505 native tests with full
allocation-failure sweeps and 1,622 guest tests. Zig lint reported zero
findings; all eight editor corpus parses succeeded.

The named-record comparison calls a four-scalar helper 100 times. The
positional form used zero rounded allocator bytes in both tiers. The record
form used 4,800 rounded bytes in the development tier and zero in the optimized
tier. A bounded inliner now exposes small, direct scalar-record readers to
scalar replacement in the optimized tier. It preserves traps, field evaluation
order, retained aliases, and the allocation observer, as verified in both-tier
executed-Wasm tests. This is a narrow improvement for issue #17; its broader
source cost model and collection work remain open.

The pinned before/after LLVM release benchmark is reproducible with
`scripts/bench_scalar_record_reader.ts BASELINE CANDIDATE OUTPUT_DIRECTORY`
under `deno run --allow-read --allow-write --allow-run`. It uses exact baseline
source `6bcf00a`, nine alternating fresh compiler-process pairs, and 31
alternating runtime pairs of 500,000 guest calls after warmup. The JSON report
pins the compiler, source, and generated Wasm SHA-256 hashes.

| Metric (median) | Baseline | Candidate |
| --- | ---: | ---: |
| Guest-call wall time per 500,000 calls | 40.39 ms | 26.78 ms |
| Paired candidate/baseline runtime ratio | — | 0.664 |
| Compiler-reported build time | 1.810 ms | 1.659 ms |
| Generated Wasm bytes | 6,768 | 6,881 |
| Compiler allocation requests | 1,094 | 1,085 |
| Guest rounded allocation bytes per 100 calls | 4,800 | 0 |

The release compiler SHA-256 hashes are `752b20ef093ecfe83bbcdf09ddf586d6a64a7e31bd05d7fa8cef1f6879f7d27d`
and `5793a89967f1922c72ef39592014677cf4ab278b8146058076f0b42259e27673`;
the source hash is `16dfd91eb2e26957ff99a77d837e93ba8a85e811fae9476646d744250f78b057`.
The Wasm hashes are `5f758b48152113b40ba7fa1c736d57b50e0c4d716c2b9dcdc4758fe6bc1c5a06`
and `a9aed824d9fc105b3d3ae24512cd6dfcfedad57b008ffbe5942679a831f329a7`.
The runtime result applies to this direct four-field helper, including guest
call overhead; it is not a general application speed claim. The short compiler
build times do not establish a compile-time speedup.
