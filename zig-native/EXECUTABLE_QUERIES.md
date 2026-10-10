# Executable reuse queries

Task 018 adapts symbolic fragment replay and optimized machine-body relocation
to the common complete-record table. Qualification completed on 10 October 2026
against the task 017 compiler. The compiler milestone is
`a604cc1644d120430b0d853be9dcd9b8eab3e93f`.

## Complete claims and graph owners

`executable_query.zig` supplies two typed executable adapters. Their tables use
the common builder, dependency owner, result owner, bounded position index and
prepare/publish transaction. The immutable `artifact_capture.Capture` owns the
fragment table, while its optional `optimized_bodies.Capture` owns the optimizer
table. A record's numeric graph ordinals belong exclusively to that capture's
owned pools, job journal or machine-input arrays. Moving a capture transfers the
whole owner. No allocator address, native pointer, solver variable or
cross-owner assumption enters a key. Query handles and index capacity are local
metadata; portable query serialization remains task 019.

| Adapter   | Complete inputs and observations                                                                                                                                                                                                            | Owned result                                                                                   |
| --------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| Fragment  | Full tagged Request, including selected layout/evidence, ordered parameters/effects, capture/template/static-value and staging terms; ordered inline-body and static-read observations; rooted chronological replay-job subtree             | Function and complete job ordinals in the sealed emission and owned metadata                   |
| Optimizer | Capture-owned exact machine function; compilation tier and arena representation; ordered direct-call roots, completed parameter/lifetime/escape/result-byte facts; exact signatures, imports and global machine types rooted in the capture | Ready output ordinal, including an explicit complete null output that uses the captured source |

Ordered dependency arrays are separately owned by records. Referenced evidence,
instructions, call graphs, static values, signatures, operation catalogs and
chronological publications remain owned by the capture. Table payload statistics
count the separately allocated read arrays; table capacity counts record and
index buffers. These figures exclude the graph containers they reference.
Tracked total requested/peak/retained memory includes both containers and query
tables. A record count alone does not establish a reuse hit.

## Publication and bounds

The optimizer captures mandatory inputs before optimization. The assembler
records completed outputs in ascending source-function order after joining its
workers. It seals the query table after the code section is assembled. Skipped
physical aliases remain machine inputs and never become completed results.
`output_ready = true` with a null optimized body is a valid result. Failed
assembly releases the private capture; a successful retained revision is the
external publication boundary. Archive decoding rebuilds the same local table
from structurally validated owned inputs and outputs.

Fragment sealing happens after assembly, owned-pool capture, journal sealing,
function freezing and complete job/function pairing checks. Records follow
`pools.functions` order. Unsupported or nonreusable jobs remain captured for
ordinary reconstruction and force affected executable consumers to rebuild. The
result's cleanup owner is installed before sealing so every allocation failure
releases the candidate while preserving the prior revision.

Each table uses the common defaults: 4,096 records, 16 MiB separately owned
dependency payload, 2 MiB retained table/index capacity, and 4,096 lookup
positions. Payload limits are checked before allocating copied read arrays.
Capacity preparation also bounds transient growth while an older buffer is live.
Saturation leaves the table incomplete and declines all reuse from that table,
including the optimizer's same-position path. Mandatory graph inputs remain
owned for normal compilation. Real allocation failures propagate as OOM.

## Exact executable admission

Fragment buckets narrow named binding or closure catalog candidates. Source unit
translation still checks canonical producer identity. Oldest-first lookup
preserves the existing first-valid order. `Importer.matches` compares the
complete imported request, selected evidence, capture and static-value graph.
Inline-body dependencies and static reads are re-admitted before ordinary job
preflight checks every chronological child, executable operand, operation,
template and solved result. Changed bodies can never be admitted solely because
their interfaces match. Scalar constant replay keeps its live completed-value,
exact scalar-bit and layout checks; admission does not demand evaluation.

Optimizer buckets use the normalized local-body fingerprint, which omits direct
callee ordinals only to permit relocation. Exact machine instructions, raw
immediates, parameter/result types and local types remain authoritative. The
same-position path requires a complete indexed record, exact source and policy,
and completed lifetime observations. Relocation keeps newest-first original
ordinal order and the existing 64-candidate budget. Its bounded recursive walk
checks every reachable body pair, lifetime summary, signature, import and global
type before translating calls. The arena recycle exception stays explicitly
guarded. A hash match or unchanged source signature cannot authorize a result.

Compilation tier and arena representation are explicit optimizer policy terms.
Worker counts and physical machine-code sharing affect preparation and emission
placement; retained optimizer outputs are symbolic pre-relocation bodies, so
those choices do not grant new executable validity. Existing deterministic
parallel/tier/sharing laws still apply. Semantic query gates retain their
separate claims and cannot certify executable records.

## Qualification on 10 October 2026

The baseline is task 017 at `089efb0b9b29504513bc0808fb20992b09c53f89`,
`build/bench/cloud-principal-graphs/candidate-source-validation/`, compiler hash
`5058f69f10640780061bb7a8cd093a9164dc789ff806ce1bc48b1ce0a9921356`, identity
`23035481dc651f09728b2636b90d5eb1c8a78939b11896947cc396592f7c904c`. The
immutable candidate is `candidate-executable-queries/`, compiler hash
`d6e06bd771805833dae1ea62657f188bc3c1fd3f05f39fe76a2186b85546e0a9`, identity
`03de8c4a03bf1fa7de85fef284123ecb0b06a8254e10de2949f5a3a1f43291ef`. The
candidate's 415-file compiler/guest map has sorted compact JSON digest
`e480200caf99dd8c67096d2e29eceb64bafc54b49530f88a9e9e58c32baadea8`. Earlier
qualified pins were preserved.

Completed checks:

- Zig 0.17.0 was checked before every build batch. Final
  `deno task test:compiler` passes the full LLVM native suite and 623 executed
  guest/client tests, including synchronous and JSPI cases.
- `deno task lint:zig` reports zero findings across 302 files;
  `deno task package:check` passes its publication dry run.
- The broad focused batch passes 160 tests, covering retained source/capture,
  static staging, demands, cache/checkpoint, ownership, parallel optimizer and
  allocation failures. The final focused batch passes 26 tests, including
  optimizer sealing, nullable outputs, alias gaps, candidate order, recursive
  relocation, transitive escape changes and fragment budget refusal.
- [The standalone prefix law](qualification/executable_queries_prefix.zig)
  builds with `-fno-llvm -Osafe` against the frozen candidate library. Real
  optimizer and retained-project captures each publish one record and saturate
  at the next record. Both decline all reuse, match fresh Wasm and release every
  tracked allocation. This directly exercises the incomplete-prefix guard.
- Strict comparison passes 626 cases / 3,756 invocations across baseline,
  default and workers 1/2/4/8: 433 successful cases, identical ordered
  diagnostics and Wasm, zero acceptance differences. Execution passes 192 guests
  and 10,362 calls.
- Retained qualification passes 27 workloads / 2,106 revision samples / 648
  guests / 41,208 calls. Three additional refinement workloads pass 234 samples,
  72 guests and 12,312 calls. Empty/row principal controls pass 156 samples, 48
  guests and 96 reads. These include no-ops, body/capture edits, unused-source
  rejection, correction, reversion and exported-checkpoint restart.
- [The executable behavior scenario](qualification/executable_queries_behavior.ts)
  passes five policies: baseline, candidate default, development, physical
  sharing, and four workers. Its 80 samples include 75 guests and 225 calls,
  every successful revision compared with a fresh build. A U32-to-U32 imported
  callee changes its body while keeping its signature; execution reflects the
  edit. All three default entry-edit rounds reuse one fragment and one optimized
  body. Failed unused declarations preserve recovery and checkpoint parity.

The measurements and full distributions live in
[fresh CSV](qualification/executable-queries-fresh.csv),
[retained CSV](qualification/executable-queries-retained.csv) and
[pins](qualification/executable-queries-pins.json). Pins retain executable,
identity, source/test, native-driver, library, fixture/dependency, helper and
report hashes. Native driver binaries are
`698690e9ac48c7fc0afe25c28d6da4565ccf332cab2cae435535d57fd1a4fe68` (baseline)
and `46109757c1cf734ddabda0841c04ce0091e5b16ab07fb71d26c1fda216712fff`
(candidate). Both compile the identical
[probe](qualification/executable_queries_probe.zig) with LLVM
`zig build-exe ... -OReleaseFast` under Zig 0.17.0.

## Measured costs

Fifteen alternating pairs over 86 workloads produce 2,580 fresh CLI samples. The
geometric mean of paired median CPU ratios is **1.00063×**, wall **1.00220×**,
and requested allocation **1.00000×** on every workload. The worst fresh CPU
pair is nested128, 16,043→17,491 microseconds (1.0903×). These samples do not
establish a general speedup.

Seventeen retained workloads, seven alternating pairs and 21 rounds of four
phases produce **238 native driver runs / 19,992 preparation phases**, plus
**714 fresh/cache-population/restart CLI runs**. All paired Wasm digests match,
all per-phase committed live-memory plateaus are stable, and every native/CLI
teardown is zero. The native timer includes preparation, digest, commit and
candidate cleanup; it excludes fixture setup and JSON reporting. Per-compilation
work and actual committed table storage are separate fields. Public CLI fields
that are unavailable remain null in the CSV.

| Steady edit workload | CPU microseconds, baseline→candidate | Requested bytes, baseline→candidate | Peak live bytes, baseline→candidate |
| -------------------- | ------------------------------------ | ----------------------------------- | ----------------------------------- |
| executable32         | 216→221.5                            | 199,661→206,061                     | 168,942→177,326                     |
| executable128        | 454→413                              | 443,280→449,680                     | 452,673→461,057                     |
| wide captures128     | 3,560→3,504                          | 3,946,972→3,977,424                 | 2,018,420→2,047,700                 |
| dependency128        | 2,215→2,249.5                        | 2,532,649→2,539,697                 | 1,170,036→1,176,316                 |
| jobs128              | 3,382.5→3,392.5                      | 4,057,688→4,065,108                 | 1,393,905→1,403,273                 |
| refinement128        | 2,693.5→2,809                        | 3,201,107→3,455,167                 | 1,820,926→2,091,080                 |
| empty principal      | 115→111                              | 92,657→93,265                       | 43,717→43,717                       |
| row principal        | 121.5→117                            | 93,844→94,452                       | 51,032→51,032                       |

Both executable32/128 positive fixtures reuse one fragment and one optimized
body on every steady edit/revert in both variants. The candidate holds two
fragment records (zero copied payload, 3,616 capacity bytes) and three optimizer
records (48 payload, 2,336 capacity bytes). Its committed requested live memory
increases by 6,000 bytes: 75,636→81,636 for width32 and 202,418→208,418 for
width128. No-ops report zero executable work while retaining those tables;
requested allocation grows by 608 bytes for the larger result/candidate owner,
with measured median CPU 33→33 and 42→41 microseconds.

The largest measured tables occur in refinement128: 129 fragment records, 1,032
payload and 59,672 capacity bytes; 258 optimizer records, 3,612 payload and
74,008 capacity bytes. Total retained requested live memory rises
803,549→941,873 bytes. Its steady-edit requested allocation grows **7.94%**, CPU
**4.29%**, and peak requested memory **14.84%**. These are measured migration
costs. The copied dependency arrays and retained indexes do not justify an
allocation-reduction or overall retained-speedup claim.

Both executable fixtures' cache population adds 5,998 requested bytes and
restart adds 8,382; measured restart CPU is 1,247→1,306 microseconds (width32)
and 1,966→1,955 (width128). Restart rebuilds native indexes from owned archive
inputs; it does not persist allocator capacity or native handles.

The three CPU windows ran sequentially after all builds/tests/execution gates,
under SCHED_OTHER, nice 0, affinity 0–4 and a four-CPU quota. No throttling was
added. One-minute loads were 0.021→0.355 (fresh), 0.213→0.573 (retained), and
0.221→0.221 (principal controls). RSS and guest memory are separate quantities
and are not inferred from compiler requested-memory counters.

## Remaining scope

Task 019 versions and validates portable query representation; task 020 extends
supported semantic graphs. Current archive domains and their existing gates
remain intact in this migration. Zero-function principal controls have no
optimizer query results; their empty optimizer owner is unsealed and cannot
authorize reuse. Unsupported fragment jobs remain fresh, and table saturation
conservatively declines the whole table.

Private frozen gdev and the original historical boxed compiler remain
unavailable, as recorded in task 002. Repository and synthetic qualification
cannot close that external gate. Remote CI qualification remains task 082.
