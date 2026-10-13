# Private iterator child fields

Task 047 remains open. This checkpoint extends the tagged-state tree
`52262dd89654b15f8b6451197ab312bcb4587932` with checked private child fields,
journal-only collection carriers and conservative root-cost admission. It does
not complete strict zip, windows or opaque callback value-pair elimination.

## Proof and fallback

A typed read of a nonempty product/record or boxed nominal carries an exact
symbolic fact. Private copies may include an absent zero alternative only when
every read has this fact. Field locals remain independent across snapshots and
forks. Full initialization, fixed offsets, checked field roles and ordinary
escape restrictions still apply. Unknown/unmarked reads retain heap storage. F
32 copies retain their raw bits. Consumed empty-constructor facts disappear with
the old address; inserted scalar tags cannot become stale constructor facts on a
later pass.

Compiler collection carriers duplicate existing journal edges. An exact marker
admits only known scalar/reference fields with no demand memo roots, in owning
mode. Only the first/root argument to collect/recycle is admitted. A read,
escape, partial initialization or unknown layout keeps the carrier and every
stored child. Deferred child escapes also preserve chains of rejected carriers.

An extra field-root publication is unnecessary when all writes/copies are zero,
explicit module static addresses, or initial annotated allocations already held
by the function frame before any source scope/control starts. Branch results,
parallel copies and default-zero cycles participate in the value-flow proof.
Scalar-looking addresses and table references grant no static/ownership fact.
Machine-observed root slots remain.

Replacement continues while allocation sites decrease. The final candidate's
extra publications must be fewer than twice its removed allocation sites in each
unchanged loop. Cadence-only carriers and one-time allocations cannot pay for
per-pull work. More than 64 loops or 256 control frames keeps the established
scalar/activation optimization. This is a measured profitability bound, separate
from the correctness proofs. Unrestricted strict/windows candidates reduced
counts but regressed CPU 15%/12%; they remain preserved and rejected.

## Frozen focused qualification

Zig 0.17.0, ordinary LLVM/Fast release. Binary SHA-256:
`10ec8bcdec55446bbd1518f51e23320ad8ded9a49a371feb186934f0ae94e091`. Compiler
identity: `6eacf189e2f18303e84182188c90b0262a0502876769f4fd99d8b316cb1e9f3b`.
Pinned incoming binary:
`75724f53dfbec6c0b25464151ad80ab849c724e8fded14dd4cffbfb60133314e`. Evidence,
rejected candidates, harnesses and exact source pins live in
`/var/tmp/blot2-adapter-children-047/build/bench/adapter-children/`.

At 4096 rows, profiling copies measure physical allocations/payload separately
from ordinary-module CPU. Thirty-one alternating CPU 7 pairs follow 20 warmups,
with 16 calls per sample. All return-value oracles, committed memory and
teardown checks pass.

| Adapter           | Objects before→after | Payload bytes before→after | CPU ratio |
| ----------------- | -------------------: | -------------------------: | --------: |
| range             |              12290→0 |                    98320→0 |     .0353 |
| map               |              24580→0 |                   196640→0 |     .0173 |
| filter            |              20484→0 |                   163872→0 |     .0315 |
| take              |              12292→0 |                    98336→0 |     .0197 |
| take_while        |              14345→2 |                  114756→12 |     .0178 |
| enumerate         |           32772→8192 |               245792→49152 |     .3589 |
| zip               |           22537→4096 |               172104→24576 |     .2619 |
| zip_strict        |          49158→49158 |              376880→376880 |    1.0097 |
| windows           |          81894→81894 |            1277540→1277540 |     .9719 |
| map/take pipeline |              36870→0 |                   294960→0 |     .0111 |

TakeWhile's two objects belong to its captured predicate's creation; per-pull
iterator state is absent. Range/map/filter/take/takeWhile/pipeline publish zero
field roots. Enumerate/zip retain value/callback-related allocations. Strict
counts are unchanged. Windows root stores fall 167879→143315 while its objects
remain unchanged. Every managed module finishes with zero roots/leases and one 4
KiB journal page retained after reset; the journal is separate from payload.

All 62 U32/F32 record/tuple width cases reproduce exact incoming Wasm bytes. New
16384 row CPU comparisons use 20 warmups/31 paired samples, one traversal per
sample; these are unchanged-machine controls, not new packed performance gains.
Physical allocator profiles for 124 fold/cursor cases preserve answers, counts
and requested bytes. After the preceding fold warms the instance, cursor calls
make one fixed 32-byte setup allocation across all widths; there are no per-row
cursor allocations. These fixtures use legacy ownership fallback: journal
root/lease counters are unavailable, not zero. Their cumulative profiling
counters are not live-memory measurements. The parent owns the independent
boxed-baseline/repeat 16 qualification.

Focused 27 native tests include 11 SROA laws/10 complete allocator-failure
sweeps and one new symbolic-fact law. Focused 26 guests,8 unchanged allocation
budgets and 366 analyzer files/zero findings pass. Guest laws cover chained
forks, saved steps/windows, dynamic reference elements, pressure, effects, early
exit, retained/replay edits, both codegen tiers and existing JSPI
rejection/rebind controls. Initial fixture mistakes and the corrected
unchecked-size finding are preserved; the final release includes the checked
addition.

## Compiler cost and next work

Seven pairs across 13 public examples preserve per-binary determinism and
checked semantic counters. Arrays, generic effects and lists change machine
bytes; other examples retain them. CPU ratios span.9521–1.0148. Requested
allocations increase 0–943501 bytes; public peak increases 0–8844 bytes and
teardown is zero. The ten-adapter synthetic adds 505903 requested bytes and
268355 peak bytes.

Seven retained synthetic pairs preserve fresh/edit/revert bytes within each
compiler and source fuel. Populate CPU 18.705→23.700 ms adds 4.995 ms/26.7%;
edit 8.099→8.190 ms, revert 7.172→7.324 ms, no-op.152→.174 ms. No-op semantic
work remains zero. This cold backend cost is explicit and accepted as a tradeoff
for the runtime reduction; no general compiler speedup or captured-project
qualification is claimed. The next compiler-cost hill is attributing this extra
5 ms and avoiding broad child analysis on unchanged/ineligible bodies.

The parent owns the merged full compiler gate. This isolated checkpoint makes no
full-task completion, commit, push or captured-project claim. Remaining
strict/windows state and escaped callback values keep their ordinary storage.
