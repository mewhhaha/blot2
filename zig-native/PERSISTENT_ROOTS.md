# Persistent roots

Task 032 extends [typed RC](SHARED_RC.md) with synchronous source and invocation
roots. It keeps the nonmoving tracer and the public scalar/numeric Array value
set. [The ownership design](SHARED_OWNERSHIP.md) still assigns host suspension
to 033, localized cycle collection to 034 and tracing-removal qualification
to 035.

## Counted owners

Every admitted allocation starts with one counted owner. Its former tracer lease
belongs to a journal slot until a local lifetime release, frame close or
teardown consumes it. Ordinary fields and copied root slots retain
independently.

The 32-byte object header and 244-word List leaf capacity do not grow in 032.
The reserved `candidate_prev` word points to the original owner's slot while its
lease exists. Lease consumption clears both links before decrement/destruction.
The cycle collector must reuse that word only after this phase ends.

A journal page has a scalar 4064-byte payload, a previous-page link and 507
8-byte slots: value and frame identity. Only values are roots. Frame identities
and page links are allocator bookkeeping. With its 32-byte header, a page fills
the 4096-byte allocation class exactly. Empty suffix pages are recycled; the
base page is reusable until instance teardown.

A call reserves one marker before opening its frame. Allocation reserves a slot
before publishing storage. At close the marker becomes the caller result owner:
a fresh original owner moves into it, while a borrowed child retains before the
callee suffix retires. The marker's frame link already names the caller. Close
keeps an owning marker and pops an empty one. Scalar and static results need no
owning slot. Frame close clears slots before release and uses the existing
iterative destructor. Empty-page retirement returns to the close loop before it
inspects the next marker, including when a return spans several journal pages.

Loop carries have stable slots in the parent frame. Stores retain the
replacement before dropping the old version. Each iteration separately holds its
incoming reference versions; closing an iteration cannot invalidate an older
lexical alias used later in that iteration. Packed List traversal closes each
logical row, not just each leaf. Breaks publish all outgoing carries before
closing the scopes they leave; reference returns move through those scopes.

A local lifetime summary transfers a single allocation only when its result has
no owning fields or embedded aliases. Loading a closure environment borrows the
child; freeing its descriptor before the indirect call would destroy that child.
Returned owning graphs instead remain in counted frame slots until consumption
and frame retirement. This restriction does not select tracing fallback. A
checked owning field whose child lacks local allocation provenance also keeps
its parent alive through consumption. Scalar replacement retains aggregates with
owning fields until it can publish equivalent counted roots for their children.
Scalar-only snapshots still use scalar replacement, including pointer-looking
integers.

Scope directives name locals even though they have no machine stack effect.
Inlining relocates those IDs, including packed slot/value pairs. Scalar
replacement preserves published heap identities; lifetime analysis treats
publication and reference scope exits as owning escapes.

## Persistent and static storage

A module-owned typed Array holds checked reference globals and mutable static
reference fields. Global cells and static memo/cache words are handles into that
owner table. Scalar fields have zero table entries, including pointer-looking
integers. Startup allocates the table before running initializers; initializer
frames close while the table keeps published graphs alive.

Static fields are registered with their checked role and relocated with their
static data. Demand status is scalar; its cached result uses the demanded type.
A List descriptor's leaf cache is a reference and its base/immutable fields are
scalars. A static reference store updates its owner-table edge before publishing
the physical word. Unknown static roles decline whole-module admission.

Root-mode tracing enumerates physical allocator blocks, scans typed owning
fields and marks journal values. It skips the conservative raw static-word scan.
Fallback modules retain that scan. Allocator links and owner tokens never count
as child edges. Tracing still reclaims unreachable cycles; this change does not
implement the 034 trial-deletion queue.

Optimizer captures record checked result roles, entry status, parameter roles,
annotation counts, root mode and owner-table word count. That last context is
required because start lowering embeds the table allocation size. Positional and
relocated matches reject changed context. Portable receipts validate closure /
function and suspension / demand pairs separately. Full emission replay restores
entry status after successful export publication.

## Invocation boundary

Admitted modules declare ownership revision 2, mode 2 and guest ABI 3. The value
ABI remains Unit, U32, F32, Bool, Array U32 and Array F32. ABI 2 remains
supported. ABI 3 adds private `blot:ownership_enter` and
`blot:ownership_leave(i32)` hooks; the guest validates their exact Wasm
signatures before calling either.

Leave outcome 0 closes a successful invocation; 1 closes failed frames; 2
releases module roots and journal pages. Numeric results are copied to host
storage before leave. Numeric inputs acquire counted scalar owners before the
call. Guest cleanup runs on success and traps, including partial
frame-reservation failure. Teardown invalidates the instance; hosts must discard
it afterwards.

Raw scalar entries recover an earlier trapped raw scalar call before starting
the next invocation. Raw Array inputs/outputs retain their existing allocation
group until explicit `blot:reset`; a raw host must reset that group. The guest
client closes its own invocation before reset, while module owners survive.

Examples:

- Parent owns child twice; a callee returns that child. The callee retains its
  result slot, closes its frame, and the caller can still read either parent
  field. Dropping parent removes two edges; dropping the result removes the
  last.
- A loop replaces Array A with B while retaining `before = A`. The carry slot
  owns B, the iteration slot holds A, and `before` keeps its original owner.
  Discarded iteration allocations retire before the next backedge.
- A ready demand retains an old Array after State is rebound. State drops its
  old edge; the demand's cached field remains strong. Repeated forcing reads the
  same graph. Dropping the demand removes that cached edge.

## Admission and qualification

Admission is whole-module. Checked synchronous Arrays, Lists, records, closures,
demands, State, startup references and static memo/cache fields have the counted
route. Host-reference/import graphs, unknown value roles, unsupported root-carry
shapes and unproven memory writes use the complete tracing fallback. Internal
root encoding currently declines functions with 8192 or more locals/parameters
and carries wider than 32 words; it adds no source-language limit. Pure modules
without allocation or mutable static roots need no journal.

Focused native laws cover fresh/retained/checkpoint/full-replay Wasm equality,
unchanged Core, static table geometry, typed zero initialization, exact static
roles and allocation failures. Executed-Wasm laws cover duplicate children,
overlapping copies, million-node iterative destruction, returned aliases, loop
breaks/returns, startup closures, ready demands reached through State,
List/Array/record snapshots, static caches, public Arrays and failed
reservation. The existing startup/demand/State/GC/Foreign fallback laws remain
exercised.

The root integration runs the mandatory combined compiler/analyzer gate before
commit. This isolated milestone does not claim an all-program qualification,
host/JSPI ownership or tracing removal. The nested 90-row unbounded
counterexample and the stricter CPU/memory gates in [SHARED_RC.md](SHARED_RC.md)
and task 035 remain required; task 032 does not erase the material 031 RC costs.

## Isolated qualification

The incoming 031 tree is `09652da9cae1aea86815aa77a2553d45c12b2be4`. Zig 0.17.0
Fast / LLVM builds were compared on the same source and edited source. The
baseline executable SHA-256 is
`c072c67a05f2397f07a03e35ef031ae4ed5efdf083828eb69bf8a775538239af`; the root
candidate is `8fc6e3498b5695c3ef5c067fb1aac7d1fff201fca0c7db0b959736c6a25a3d6b`.
Its build-generated compiler identity is
`534cea6650760e75826090bab2812c212f669db62435035af316bdc8f90c8493`.

Twenty paired measured rounds followed two discarded compiler rounds. Runtime
rounds alternated order, warmed each function with 100,000 calls, then discarded
five of 25 rounds. Times are process CPU medians. The Array batch has 20,000
calls; the List batch has 2,000. Compilation preserved `nativeWorkSteps` in
every pair. These are focused workloads, not a whole-program performance claim.

| Workload              |       031 | Root candidate | Change |
| --------------------- | --------: | -------------: | -----: |
| Fresh compile         |  7.238 ms |       7.348 ms |  +1.5% |
| Retained edit         |  2.891 ms |       3.072 ms |  +6.2% |
| Reference Array batch |  6.217 ms |       9.118 ms | +46.7% |
| Persistent List batch | 29.993 ms |      31.289 ms |  +4.3% |

The Array per-call increase is about 145 ns. A separate 20,000-call boundary
probe measured an empty scalar entry at 18.5 ns on 031 and 122.5 ns with roots.
One reference Array call has nine retains on both routes; 031 leaves four
original leases until reset, whereas the root route has zero outstanding leases,
13 releases and four destructions. The journal/frame work and actual retirement
replace that deferred lifetime. The short preliminary batch had unstable warm-up
costs; the table uses the explicit warm-up and longer Array batches. This cost
is material and does not satisfy the later tracing-removal CPU gate.

Compiler p10–p90 CPU ranges were 6.909–7.940 / 6.979–7.800 ms fresh and
2.790–3.157 / 2.900–3.446 ms retained (baseline / candidate). Runtime ranges
were 6.111–7.070 / 9.022–12.681 ms for Arrays and 29.685–30.701 / 30.736–31.825
ms for Lists. Linux load averages were 5.44 / 4.74 / 6.28 during compiler
sampling and 4.45–4.49 / 4.48–4.49 / 5.96 during the final runtime batch. The
process CPU clock reduces scheduling noise; it does not eliminate shared-machine
interference.

Repeated-call memory probes used public numeric Array exports so memory was
observable. All 031 probes consequently declared the existing public-Array
tracing fallback; the candidate declared revision 2, mode 2. After warming:

| Graph                                                 | 031 fallback | Root candidate | Repetition                        |
| ----------------------------------------------------- | -----------: | -------------: | --------------------------------- |
| Nested Arrays / persistent Lists                      |      128 KiB |        128 KiB | 100 paired calls                  |
| Reference carry loop                                  |    3,200 KiB |        128 KiB | 100 × 5,000 and 50,000 iterations |
| Startup closure / ready demand + 32,768-word pressure |      384 KiB |        384 KiB | 100 paired calls                  |
| Guest numeric Array copies + startup reads            |      128 KiB |        128 KiB | 100 paired calls                  |

Memory stayed at its warmed size. The carry-loop route retired 5,555,202 objects
and ended with zero roots and leases. The startup route retained exactly one
module-table root/lease; teardown removed it and retired the remaining six
objects. Wasm linear memory does not shrink on teardown. This measures reuse and
retirement, not returned OS pages. Journal storage added an 8192-byte base
class with a 4096-byte payload; pages now use one 4096-byte block. Header,
Array layout and 244-word List geometry are unchanged from 031, so those
earlier costs are separate from this root extension.

Focused checks passed: eight source ownership/plateau laws (seven at both
codegen tiers), 11 checked RC execution laws, 45 startup/demand/State/GC/Foreign
fallback laws, all eight unchanged compilation budgets, guest manifest/signature
checks, source fresh/retained OOM sweeps, portable archive checks and exact
fresh / retained / checkpoint / full-replay Wasm comparisons. The analyzer
checked 330 files with zero findings. The mandatory full gate belongs to the
root integration batch. No fixture-only or always-traced route is used as source
admission evidence.

Reproduction data and pinned harnesses are retained outside source control in
`build/bench/persistent-roots/{compiler-cost,runtime-cost,boundary-cost,memory-cost,summary,source-manifest}.json`
and `measure_{compiler.py,runtime.ts,boundary.ts,memory.ts}`. The cost Wasm
SHA-256 values are
`4551b53d167ae3697cc15f7afa82e2826b6d85bba6f496e58c13d95785b70393` (baseline,
7747 bytes) and
`fd4d5a912fd0eb4a2afd1771266e9412c571c8548ada4ff22b259f7d7ee332d2` (candidate,
9129 bytes). Host/JSPI ownership, localized cycles, the nested 90-row unbounded
memory counterexample and the 035 final CPU/memory gates remain open.

## Joint integration with symbolic reuse and local memos

The isolated qualification above predates the 029 / 037 merge. The joint route
keeps the v3 optimizer schema, import names, full globals, table references,
signatures and complete transitive positional/relocation proofs. Root mode and
owner-table size gate either Matcher route; checked result role and entry status
participate in local equality and candidate hashes, including callee
propagation.

A reference local memo first forced inside a callee loop needs an owner outside
that iteration. Its slot is reserved in the caller frame when the memo is
created. The first force retains that slot before publishing readiness. Nested
forwarding memos own independent slots; iteration close can then remove the
original allocation owner without invalidating the cached result. The forwarding
chain is recovered from each memo's caller; the redundant 8-byte Emitter parent
link is removed. Tracing packets continue to carry these memo references on the
fallback route.

The integration regression repeatedly forces an Array memo across 5,000
iterations with small recycled Arrays and large allocation pressure. It checks
mode 2 admission, exact contents, at least two retired objects per iteration,
zero roots/leases after raw reset, and independent guest calls. This additional
owner publication belongs to the joint integration, not the measured isolated
executable pin above. The combined full gate and release comparison are recorded
below.

## Integrated qualification (12 October 2026)

Local implementation `2798ff9` combines 029, 032 and 037 with the bpm client.
The frozen incoming revision is `1ad8f15f0cfaba16ec06482fd03f7f8f4f53525f`; its
qualified staged tree is `6064c8e2d114bfb39ab3c78d5c0b295f51f1be15`. The Fast /
LLVM release uses Zig 0.17.0 and `deno task build:compiler`. Its executable
SHA-256 is `b802365944a69db01df83442db960a8fd7b717828f7cbb1ac5aba2b661d80d17`
(40,334,040 bytes); compiler identity is
`235678a0c5e11747e6562a85e6da53d8627b791d7a267e6534f716d41e2b31a1`.

`deno task test:compiler` passes the complete Safe / LLVM native suite and 844
executed-Wasm/client laws, including all eight unchanged compile-allocation
budgets. The pinned analyzer checks 339 Zig files with zero findings. Focused
integration adds 41 symbolic/memo/root native laws, 19 ownership/OOM laws and 17
executed persistent-root/local-memo laws. Deno checking, formatting,
standalone-host compilation and `deno publish --dry-run --allow-dirty` pass;
nothing is published or pushed.

Carry owners now belong to the existing active loop targets. Their slices own
only reference-carry entries; scalar emitters carry no root-map allocation. The
first integration attempts exceeded the fanout allocation budget through
metadata added to every Emitter. Removing that redundant storage restores the
unchanged budget. The failed/interrupted candidates remain distinct from the
qualified executable above. The first budget-passing integration still failed
one native and twenty guest laws; it is not qualification evidence. The final
corrections derive arena-helper admission from the runtime fields, decline
single-allocation lifetime summaries for returned owning graphs, relocate
scope-local directives with inlined locals, preserve owning SROA fields and
unknown-child parent provenance, and retain borrowed AVL pivots until their new
parent edge publishes. Existing failed laws are unchanged. Ninety-six affected
executed laws pass, including new repeated curried/State/rotation retirement
checks. These fixes add neither a blanket tracing fallback nor a budget change.

Seven alternating CPU-7 release pairs over 13 public examples produce 182 rows.
Diagnostics, constant work, code instances, callable wrappers and the previous
prepared/role counters match. Each compiler emits stable bytes across repeats;
032 intentionally adds ownership helpers, so cross-compiler Wasm differs in 12
examples. Scalar Wasm is identical. Requested allocation changes by −18,717 to
201,912 bytes; peak deltas are zero and teardown live bytes are zero. CPU median
ratios span 0.990–1.011 at load 1.17; no general speedup is claimed.

Seven alternating pairs over four synthetic workloads include fresh processes,
cache restart, population, first/later edits and no-op. Cross-compiler bytes and
each compiler's fresh/retained/restart bytes are identical, with no unexpected
problems. Fresh CPU medians match; restart ratios span 1.000–1.050. The retained
process clock has 10 ms resolution, so many small phases cannot establish a
timing change. These combined measurements do not attribute a cost to one
isolated task.

Raw pins, harnesses, distributions, failed attempts and gate logs are retained
in ignored `build/bench/joint-029-032-037-bpm/`. Public reproduction uses its
`compare_public.py`; synthetic reproduction uses
`deno task bench:compile
--workload synthetic --runs 7 --restart-cache --allow-wasm-diff`.
Baseline is `build/bench/symbolic-body-reuse/blotc-baseline` (SHA-256
`272f028932b0cc563049fe7e5f6f51139304f0ae4cf7213351fd55f5f5f7a127`); qualified
candidate is `corrected/blotc-candidate` in the joint evidence directory. The
corrected public and synthetic samples are under `corrected/`.

The isolated runtime measurements above remain tied to their original pins. In
particular, the +46.7% short reference-Array batch cost is material. Host and
JSPI roots (033), cycles (034), tracing removal and its final CPU/memory gates
(035) remain open. Completing 032 does not qualify those later tasks.
