# Source and revision validation records

Task 017 moves successful revision input owners and frozen-Core validation
certificates onto `semantic_query_table.OwnedRecord(.source_validation)`. The
implementation is qualified on 10 October 2026; the local milestone revision
will be recorded after commit.

There are two typed claims with separate owners. A revision input record owns
exact settings and source/import observations; a Core validation record owns
exact checked graph, namespace and foreign-bound images. Neither provides a
semantic answer, executable fragment or evaluated value. The authoritative
source, dependency/interface, principal and executable gates still run.

## Captured revision inputs

`revision_inputs.Snapshot` remains the mutable input provider during
acquisition. It owns all seven project options, ordered aliases, canonical path
observations, raw file bytes and ordered `(source, request, outcome)` import
resolutions. A failed non-OOM observation is memoized for the same attempt; OOM
is propagated. The loader consumes those same captured facts even if the
filesystem changes.

After successful preparation and emission, `Snapshot.freeze` transfers its
existing buffers into a distinct `Frozen` owner. The common record key owns
settings, its dependencies own the observation arrays, and its result records
acquisition counts. Overlay buffers remain separately owned request provenance.
The transfer allocates nothing and copies no source bytes. The mutable provider
becomes invalid. Rejected attempts keep their diagnostic result and mutable
Snapshot; they cannot publish a frozen successful revision.

A borrowed `View` exposes exact immutable observations to both owners without
exposing provider operations. Unchanged-output admission still requires current
seed admission, entry/output/policy identity, the entry's canonical path and raw
bytes, every setting and alias in order, and re-observation of every captured
path/file/import. Empty previous file sets and any failed previous observation
force ordinary preparation. Successful compilation can retain an auxiliary
failed read observed during a rejected fast path; that observation remains
explicit and cannot certify unchanged-input admission.

The revision owns one record directly, so no optional hash table, index or new
cache quota governs its mandatory captured source buffers. Existing project and
overlay input limits remain authoritative. Candidate discard and session
teardown release each owner once. Commit moves already prepared owners without
allocation or filesystem reads; failed candidates preserve the last-good record.

## Checked Core dependency records

`dependency_certificate.Certificate.record` has a `ContextImage` key, owned
namespace/module dependencies, and a validation-only checked marker. Its context
records every foreign owner unit and binding count, the symbol dictionary bound
and the optional source-length bound observed by frozen validation. Exhaustive
context field handling prevents a newly added validator input from being
omitted.

Dependencies retain the exact namespace stream and ordered module records. Each
module records its unit ordinal, producer path, checked stamp and the complete
structural Core stream. This includes type/effect graphs, nominal and catalog
identities/order, binding IDs, declaration/import references, source metadata,
constructor order and all executable tables. Exact stream equality excludes
native addresses and padding. A deliberately unchanged public stamp cannot hide
changed graph contents; hashes are not equality proofs.

`Gate.freezeValidation` records only a successfully validated immutable current
owner whose pins match that owner's modules. Certificate matching rechecks the
context and namespace; per-module admission rechecks ordinal, producer path,
stamp and exact graph. Changed current graphs or foreign contexts still receive
authoritative validation. A certificate cannot turn catalog equality into
principal proof validity or bypass body/value/executable admission.

The certificate belongs to artifact `Pools`, whose caller retains immutable
Core. It stays separate from the revision input owner. `shared_query_gate`
retains its existing exact Pools/Core/allocator pairing and dimension checks.
Shared Gate leases own operational arrays; their owner pointers do not enter
canonical records, and their counters do not count validation work a second
time.

A single immutable Pools owner has at most one certificate, so it owns the
common record directly without a bucket index. Optional certificate payload
retention uses the common default 16 MiB owned-byte budget across context/module
arrays, namespace bytes, paths and complete graph images. Saturation declines
certificate retention and later runs ordinary validation. Actual OOM aborts the
candidate; partial images/module arrays are cleaned without mutating the
previous owner. Each construction buffer is also capped by its remaining
encoded-byte budget. Growth can temporarily hold both previous and replacement
buffers; the budget is a logical retained-payload bound, not process RSS or a
whole-compilation peak-memory limit. Completed images own exact-length slices.

`validation_image.Image` stores the structural framing bytes themselves.
Matching walks the current typed input with constant comparison workspace; it
does not parse or trust persisted graph indexes. This native framing is local.
Incoming dependency/interface and checkpoint envelopes retain their current
schema and full validators. Portable query encoding and complete semantic
persistence are tasks 019 and 020; this migration does not serialize native
images or Gate leases.

## Qualification on 10 October 2026

The immutable candidate is
`build/bench/cloud-principal-graphs/candidate-source-validation/`: compiler
SHA-256 `5058f69f10640780061bb7a8cd093a9164dc789ff806ce1bc48b1ce0a9921356`,
identity `23035481dc651f09728b2636b90d5eb1c8a78939b11896947cc396592f7c904c`, and
the 414-file Zig/guest input map digest
`d2c208558cd097650d65e93710b73fa29cc2ded3496f98459588b1a7267159ae`. The task-016
baseline at `913a59f308fc58b6b3aad0197903149f16c780c4` is
`candidate-specialization-principal`, compiler
`1e6bbc8e4c951c0b2b9388f3edcc51730158a281e80a99bb4f79ef81cea580da` and identity
`cc2684845fd95500767e26465b0f47edc11e4f76792eb36336484d321080bd04`. Neither pin
was overwritten. Native driver hashes are
`1775babd525194f5603e8e452449d84a061fbfb431aa691f47eec475b1fbb90d` (baseline)
and `b3204b64746db4257248f3d77a6e232eb10402c9366cc85aec0864e6c56baea0`
(candidate). Both compiled the identical
[durable probe](qualification/source_validation_probe.zig), hash
`2db68ad8ac3b851c96f6cc4fb12c59f5ebf5d106df23557a04602151bb371868`, with LLVM
`zig build-exe ... -Ofast` under Zig 0.17.0.

Completed gates:

- `zig version` reports 0.17.0 before each build batch.
- `deno task test:compiler` passes full LLVM native execution and 623 executed
  guest/client tests, including synchronous and JSPI cases.
- `deno task lint:zig` reports 301 files and zero findings.
- `deno task package:check` passes its package dry run.
- Final focused batch passes 31 tests, including exact moved-buffer ownership,
  allocation failures, unchanged-output and commit behavior, source/alias/import
  observations, namespace/order/path/graph mutations with unchanged stamps,
  symbol/source/foreign bounds and budget refusal. The preceding broader batch
  passes 227 source/revision, retained-catalog, frozen-Core,
  dependency/interface, checkpoint and recovery laws; the full gate covers the
  final instrumentation and bounded writer as well.
- 626 cases / 3,756 compiler invocations across baseline, default and workers
  1/2/4/8 preserve ordered diagnostics and Wasm bytes; 433 cases succeed. The
  execution subset passes 192 guests / 10,362 calls.
- 27 retained workloads pass 2,106 revision samples, 648 guests and 41,208
  calls; three refinement workloads add 234 samples, 72 guests and 12,312 calls.
  Two principal-proof controls add 156 samples, 48 guests and 96 constant reads,
  with positive edit/restart principal hits. All cover failed unused source,
  correction, revert, fresh parity and checkpoint restart under six policies.

Raw local evidence uses the `source-validation-` prefix in
`build/bench/cloud-principal-graphs/`. The final logs are `full-gate-v1`,
`analyzer-v2`, `package-check-v1`, `focused-v5` and `proofs-v2`. Earlier
unqualified logs include a corrected type-size compile error and a missing
copied proof fixture; those runs do not supply completion evidence.

## CPU, allocation and retained storage

Complete distributions and source/library/helper/report maps are durable in
[fresh CSV](qualification/source-validation-queries-fresh.csv),
[retained CSV](qualification/source-validation-queries-retained.csv) and
[pins](qualification/source-validation-queries-pins.json). The CSV has 172 fresh
and 210 retained/CLI rows. Public CLI fields unavailable for query storage or
validation work are explicitly null. The native probe records actual committed
input/certificate owners separately from per-attempt counters; overlay request
provenance is excluded from its logical input payload and included in total
tracked live memory.

The isolated fresh batch alternates 15 pairs across 86 workloads (2,580
cache-off compiler children). Geometric mean median CPU ratio is 1.0037, wall
ratio 1.0011; requested allocation is unchanged on every workload. The largest
CPU ratio is 1.1295 for the tiny refinement8 control (896→1,012 microseconds).
This establishes near-neutral overall fresh cost, not a general speedup.

Seven alternating retained pairs cover 15 workloads: 210 native drivers, 17,640
prepare/commit/digest/cleanup phases and 630 separate fresh/cache/restart CLI
builds. Every workload/phase reaches a fixed retained-live plateau; every driver
and CLI compilation tears down to zero tracked bytes. Repeated native phases
execute the full preparation, output digest, commit and candidate cleanup;
fixture setup and JSON emission are excluded. Fresh CLI CPU uses child user plus
system `getrusage`; native phases use process user plus system `getrusage`.

Two positive multi-module controls edit only the entry module. On steady edits
and reverts, the candidate reports exactly two reused dependency validations and
zero fresh dependency validations. The first edit validates both modules and
publishes a certificate; the following revert reuses it. No-op attempts report
zero validation work and retain the already committed certificate. Input payload
and capacity are identical to baseline for every paired retained sample.

| Workload / steady edit | CPU baseline→candidate (µs) | Requested bytes baseline→candidate | Peak live bytes baseline→candidate |
| ---------------------- | --------------------------- | ---------------------------------- | ---------------------------------- |
| positive validation32  | 393→448                     | 414,990→490,739                    | 470,831→542,825                    |
| positive validation128 | 614→700                     | 646,671→788,904                    | 736,955→886,488                    |
| wide captures128       | 3,531.5→3,642               | 3,810,311→3,946,972                | 1,876,735→2,018,420                |
| changed dependency128  | 2,076.5→2,315.5             | 2,390,405→2,532,649                | 1,106,386→1,170,036                |
| jobs128                | 3,212.5→3,395               | 3,853,908→4,057,688                | 1,284,823→1,393,905                |
| refinement128          | 2,571→2,672                 | 3,000,865→3,201,107                | 1,635,894→1,820,926                |

Exact certificate payload is 30,914 bytes (validation32) and 64,068 bytes
(validation128), compared with the old 96-byte bound/digest certificate. These
owners plateau. Across all retained controls the largest certificate payload is
83,542 bytes, below the 16 MiB bound. Input storage is unchanged: the positive
controls retain respectively 3,408/7,724 payload bytes and 488 capacity bytes.
The largest steady-edit allocation ratio is validation128, +22.00%; its CPU
increase is +14.01%. This is the measured cost of stronger exact validation
images. Small empty/row principal controls request 83,023→92,627 and
84,230→93,813 bytes, with edit CPU 105→106 and 126→118 microseconds. No retained
allocation reduction or overall retained speedup is claimed.

Fresh/restart CLI builds do not retain these native certificates. Positive
restart CPU is 2,116→2,074 microseconds (32) and 3,202→3,282 (128); wide128
restart is 5,285→5,142. No-op totals include the held exact certificate even
though their per-attempt native validation counters and new certificate storage
are zero. The CSV preserves each phase separately.

All three measurement windows use SCHED_OTHER, nice 0, affinity CPUs 0–4 and a
four-CPU quota, with no new quota throttling. One-minute load is 0.804→1.001
(fresh), 0.471→0.588 (main retained), and 0.289→0.289 (proof controls).
Measurements ran after builds and semantic gates finished, without another CPU
benchmark running concurrently. These are requested compiler-memory and CPU
measurements, not process RSS or guest allocation claims.

## Remaining boundaries

Mutable acquisition/error memoization stays revision-local; singleton records
have no bucket index. Source bytes, namespace and graph images retain their
separate lifetimes and validity claims. Whole incoming dependency/interface
validation remains authoritative rather than being replaced by a certificate.
Native images are not portable artifacts; task 019 owns their wire projection.
Unsupported/over-budget certificates rerun validation, and the serial worker
policy remains unchanged. The private frozen gdev snapshot and original boxed
binary remain unavailable; this task does not close task 002 or final task 084.
