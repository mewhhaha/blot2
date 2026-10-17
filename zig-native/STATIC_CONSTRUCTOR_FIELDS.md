# Private tagged iterator steps

Task 047 remains open. This isolated continuation of the tail checkpoint admits
private tagged steps when their empty alternative and allocated alternative have
an exact checked field layout and a common activation lifetime.

The empty constructor's tag and zero payload are symbolic ownership facts beside
its static address. They participate in ordinary body comparison and portable
optimizer meaning, so replacement never reads module data or infers pointers
from numeric bits. The public representation stays unchanged. Unknown uses,
captures, returns and inconsistent field roles keep their heap values.

One allocation site and its empty alternatives may share a root only when they
are mutually exclusive producers in one bounded value block. An if uses opposite
arms; a do block permits earlier empty returns that branch straight out before
the allocation. No nested loop revisits the producer, and every admitted alias
stays in the same enclosing loop activation. Forks and carries outside that
activation keep independent storage. Nonescaping field copies retain independent
scalar locals; only their identical owning edge shares the proven root.

A tagged join without this proof retains its ordinary cell. The initial
count-only candidate removed allocations but multiplied root publication and
regressed guest CPU. Its binary, samples and profiling logs remain preserved
under the ignored `build/bench/adapter-state/` directory. An intermediate
matcher read static bytes without a complete optimizer dependency; it was
replaced by exact symbolic tag bits before acceptance. A copied configure-cache
identity anomaly is preserved separately; the final release forces
reconfiguration and checks the current source identity.

The isolated qualification record, exact source delta and pins live in
`/var/tmp/blot2-adapter-state-047/build/bench/adapter-state/`. The parent owns
the merged full native/guest/analyzer gate. This change removes admitted tagged
step cells; child tuples, cursors and other adapter state still retain
allocations. It establishes neither task 047 completion nor a general compiler
speedup.

## Focused qualification

The incoming staged tree is`bed55d052070a63e053c8eca83ac87e329742bbc`, on
`cf5bc84313bd0cd0e3d184b6e7604c12cabae3f1`. Final Zig 0.17.0 LLVM/Fast release
SHA256 is`75724f53dfbec6c0b25464151ad80ab849c724e8fded14dd4cffbfb60133314e`;
source identity
is`50389ca4379e77644db11e9c74c02a49123d84a81a2d7fe5cb8715a0165515cc`. The pinned
incoming release
is`e1a589345926064356315c4b48867395dabc9d38eec181f09ce9332157e9151f`.

At 4096 rows, the range/map/take pipeline removes 12288 allocations: 49158→36870
objects and 393264→294960 requested payload bytes. One warm ownership journal
remains 4 KiB after reset; both variants have zero roots and leases. Profiling
copies measure counts; ordinary guest modules measure CPU. Thirty-one
alternating CPU 7 pairs after 20 warmups, 16 calls per sample, improve all ten
adapter controls. Candidate/control ratios are range 0.8529, map 0.9033, filter
0.9227, take 0.7987, take_while 0.9330, enumerate 0.8951, zip 0.8581, zip_strict
0.8936, windows 0.9407 and range/map/take 0.9184. Committed memory matches.

All 62 U32/F32 record/tuple packed-width controls reproduce exact incoming Wasm
bytes; their preserved full all-width runtime samples remain unchanged controls.
The final release has the same adapter bytes as the earlier Safe and LLVM
instruction-equivalent screens. Focused 18 native laws/OOM, 24 guest groups, 8
unchanged compile budgets and 366 analyzer files/zero findings pass. The
separate stage-chain rejection/recovery controls also pass; their 3m31s cost is
not a necessary iterator gate. Test-only source-name/pattern errors and
unsuccessful profiling/identity setup remain in the ignored evidence.

Seven retained compiler pairs preserve fresh/retained/revert bytes and source
fuel. Populate/no-op/edit/revert CPU medians are 19.253/0.185/8.809/7.740 ms
incoming and 19.587/0.183/8.694/7.809 ms candidate. Seven pairs across 13 public
examples preserve bytes and per-binary determinism; CPU ratios span
0.9552–0.9791. Requested compiler allocation increases 0–140096B, peak increases
0–512B and teardown is zero. Small-program timing is not a general compiler gain
or a captured-project qualification. Final combined release qualification
remains with the parent.

## Merged checkpoint, 13 October 2026

Local `10fab46` qualifies this admitted slice with 1,624 native laws, 1,030
executed guests, 977 exhaustive failure sweeps and zero analyzer findings across
373 files. [Merged qualification](CONTINUATION_QUALIFICATION.md) records the
exact source/binary pins, measured costs and still-open scope. Isolated clocks
above remain separate from the final combined release measurements.

The subsequent [private child-field checkpoint](PRIVATE_CHILD_FIELDS.md) records
its separate source boundary, broader elimination and cold compiler tradeoff.
