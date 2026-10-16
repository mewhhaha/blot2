# Portable query records

Task 019 serializes the complete query records that already have a portable
graph: completed principal proofs and ready optimizer outputs. Both travel
inside [backend checkpoints](src/backend/backend_checkpoint.zig) through the
bounded [dependency format](src/reuse/dependency_format.zig). This record
follows
[the typed query contract](QUERY_TABLE.md#portable-representation-and-compatibility).
The compiler milestone is `ea4a7f3ef23ebf8506fe85eefa24f51ee65c3024`;
qualification is recorded below.

## Typed sections

[portable_query.zig](src/reuse/portable_query.zig) defines one section per
archive: a header `{version, kind, schema, claim}` followed by complete records
of that claim. The section interpretation version is 1. Each claim fixes its
query kind and schema.

| Claim                      | Kind         | Schema | Archive                                                      |
| -------------------------- | ------------ | -----: | ------------------------------------------------------------ |
| `principal_complete_proof` | `principal`  |      1 | [principal archive](src/reuse/principal_archive.zig), key v3 |
| `optimizer_output`         | `executable` |      1 | [optimizer capture](src/reuse/optimized_archive.zig), key v2 |

Decoding requires the exact header. A different section version reports
`UnsupportedVersion`; a different kind, schema or claim reports
`SchemaMismatch`. The dependency format's reflected schema digest separately
rejects any change of record shape, and its own envelope version stays 1. No
reader reinterprets an older receipt or another claim. The backend checkpoint
key moved to version 2 (version 3 since task 020 adds the semantic owner), so
earlier checkpoints are stale before their inner archives are read.

Records contain validated artifact ordinals only. Native handles, positions,
fingerprints, allocator capacity, solver IDs, Session-local template handles and
`building` states never enter the wire. Decoding rebuilds native indexes from
owned payloads.

## Represented and declined kinds

| Query owner                                              | Portable       | Reason                                                                                           |
| -------------------------------------------------------- | -------------- | ------------------------------------------------------------------------------------------------ |
| Principal proof with complete dynamic observations       | Yes            | Archived source image, evidence graph and observations are revalidated against the current owner |
| Principal exact-source proof without observations        | No             | Another process cannot re-establish its dynamic inputs                                           |
| Source-description and open-residual principal templates | No             | Session-local source templates, never completed proofs                                           |
| Refinement receipts                                      | No             | Owner-local; recomputed after restart                                                            |
| Selected specialization                                  | Yes (task 020) | Replayed through a [persisted semantic owner](SEMANTIC_ARTIFACTS.md)                             |
| Canonical specialization                                 | No             | Session-local plans; recomputed                                                                  |
| Revision inputs and checked-Core certificates            | No             | Native validation images; dependency/interface validation reruns authoritatively                 |
| Executable fragments                                     | No             | Reference emission pools and replay jobs that checkpoints do not own                             |
| Optimizer outputs of a sealed table                      | Yes            | The archive owns the complete machine inputs; the matcher still compares them with fresh code    |
| Evaluated values                                         | Never          | A separate operational claim; no interface or source certificate authorizes it                   |

Declined kinds are simply absent from the wire and recomputed after restart.

## Principal records

A record is `{key: {target, options}, dependencies, result: {types, rows}}`.
Dependencies are the existing ordered scalar reads, plain-nominal reads, plain
publications and call publications. Only records with complete observations and
no selected implementations are encoded. Target, scalar-read and call units and
bindings name the archived source image. Evidence and row IDs name the archive's
own evidence graph.

Before an Archive is exposed, decoding validates:

- the evidence graph: primitives occupy IDs 0–5, every type edge names an
  earlier node as hash-consed publication guarantees, product/record/nominal
  spans stay in bounds, record names and nominal units are nonzero, only
  function/demand/provider nodes carry rows and those rows exist, row zero is
  empty, and every row label and operation argument exists;
- one record per target, matching the producer's first-proof publication;
- targets inside the image with nonzero bindings;
- nonzero, unique type-mapping variables with nonzero in-bounds evidence, and
  unique row mappings with in-bounds rows;
- unique scalar reads of valid bindings with primitive evidence;
- unique plain reads, and unique publications whose prior state was observed;
- unique call publications of valid bindings with nonzero in-bounds evidence.

Nominal identities, effect operations and plain-nominal keys may name builtin
declarations in the reserved unit `maxInt(u32)`, outside the source image.
Decoding therefore checks only their internal consistency; the Reader validates
each one against the receiving units before import or publication.

The Reader is unchanged after decoding. It matches the ordered module stamps and
namespace, builds its lazy table, checks dynamic observations, imports type/row
and call graphs into the receiving owner, validates nominal memo keys, then
publishes atomically. Cross-space type/row cycles cannot be expressed by node
order alone; the importer's depth and work bounds decline them.

## Optimizer records

A record is
`{key: {source, tier, arena}, dependencies: {callees, parameters,
invalidates, owned_result_bytes}, result: {function}}`.
The snapshot also owns the captured machine inputs, outputs, signatures, imports
and globals, plus a `sealed` flag. An unsealed or saturated producer table
encodes no records and decodes as an unsealed capture that declines all reuse.

Decoding validates every ordinal before exposing the Capture:

- signature parameter types, import signatures, global types and the arena's
  function and global indexes;
- each entry's signature, parameter and lifetime arity, and readiness;
- every source and output body: direct-call, import, indirect-signature, global
  and local operands; block types; SIMD lanes; and structured control, where
  `else` appears once inside an open `if`, `end` closes an open frame, branch
  labels stay within the open frames and every frame closes;
- for a sealed table, exactly one record per ready entry in ascending order,
  each equal to the facts derived from that entry: source and result ordinal,
  tier, arena, ordered call operands, lifetime parameters, invalidation and
  owned result bytes.

Records then publish in wire order through the table's prepare/publish
transaction. Bucket fingerprints are recomputed from the decoded machine input.
Table limits still apply, and saturation leaves the capture unsealed. The
matcher's same-position and relocation gates are unchanged.

## Failure contract

The envelope checks magic, envelope version, schema, compiler/settings key,
payload length, checksum, element and depth limits. A decode returns either a
fully validated owner or releases every allocation; allocation-failure sweeps
cover decoding, index construction, import and publication.

- Automatic CLI and project-server restart caches treat every decode failure as
  a miss and compile afresh.
- An explicit project-server checkpoint keeps its contract: a non-OOM decode
  failure is an optional-candidate miss, and OOM propagates.
- Dependency artifacts (`--dependencies`) are not query archives here; their
  typed load errors are unchanged.

Corrupt or incompatible checkpoints never replace the last-good revision, and
structurally invalid ordinals or control never reach emission.

## Qualification on 10 October 2026

The baseline is `e018d8db2f88f8211f344ec1d64f3c28f760925d` (task 018 plus its
qualification record), rebuilt locally with
`zig build install compiler-identity -Doptimize=fast`: compiler SHA-256
`8a758ae24b5662d0896bf86cb3c9f3e8a6ad5a1f2dd98868de2c68871d99afba`, 417-file
input map `b73c20ad4ffa862e40c1e0612d5724497a5788b7fb3f47bf90a85b828ab7809f`.
The cloud task-018 binary (`d6e06bd7…`) and earlier cloud pins are absent from
this machine; this rebuilt binary is a separate comparison, not that artifact.
The candidate release compiler is SHA-256
`69e8692e88c0e49fa63e25fe3d42100dcec085ee048bb900acb2d2c2ac36f0d5`, 419-file map
`368c0ad70739d783feaaeea84ff331e3cf70985bccb8fb957a0c12bc68e8c9ce`.
[The pins](qualification/portable-queries-pins.json) retain both compilers,
probes, drivers, workloads, loads and machine conditions.

Completed checks:

- Zig 0.17.0 was checked before every build batch. `deno task test:compiler`
  passes the full LLVM native suite and **624** executed guest/client tests.
  `deno task lint:zig` reports zero findings across 303 Zig files with the
  analyzer at its CI pin `756bfd5`.
- 31 focused `portable` native tests pass. New laws cover typed headers,
  envelope identity/version/length/integrity, every principal record and
  evidence check, builtin identities, optimizer ordinals and control, record
  order/coverage/equality, unsealed and saturated tables, and exact rebuilt
  indexes. Existing allocation-failure sweeps cover decoding, index
  construction, import and publication.
- Six mutants each weaken one validator: target uniqueness, backward evidence
  edges, observed publications, local operands, `else` placement and recorded
  call ordinals. A focused law kills every one.
- [The example restart law](tests/portable_query_restart.test.ts) builds every
  public example fresh, populates its CLI cache and restarts. Each restart must
  load, reproduce the fresh Wasm, reuse every optimizer body and decline no
  principal record. It exposed and now guards a rejected first design that
  bounded builtin nominal units by the source image.
- The process-boundary checkpoint test round-trips both kinds through the
  project server, compares fresh behavior, and falls back cleanly for an unknown
  envelope version and corrupt bytes.

### Measurements

[The restart driver](qualification/portable_queries_restart.ts) ran 31
alternating rounds over 13 public examples and five generated principal
workloads: 3,348 CLI builds, fresh/population/restart for each compiler. CPU is
child user+system rusage from `wait4`. Every phase of both compilers emits the
same Wasm, every restart loads its cache, principal hits and optimizer reuse are
equal, and allocation counters are deterministic. Raw distributions are in
[the restart CSV](qualification/portable-queries-restart.csv).

| Measure                                      | Result                                                        |
| -------------------------------------------- | ------------------------------------------------------------- |
| Checkpoint size, public examples             | +9.6% to +19.6%; optimizer records repeat call/lifetime facts |
| Checkpoint size, principal-only workloads    | +37 bytes of section headers                                  |
| Population requested allocation              | +98 to +74,514 bytes, at most +0.90%                          |
| Restart requested allocation                 | +510 to +102,857 bytes, at most +1.15%                        |
| Peak requested memory                        | Unchanged in every phase                                      |
| Median CPU geomean, fresh/population/restart | 0.979 / 0.984 / 1.030                                         |

The fresh path is code-identical, yet its per-workload ratios range 0.640–1.336.
Whole-process CPU of 6–20 ms builds on this interactive host therefore cannot
resolve the change, and no CLI speedup or slowdown is claimed.

[The decode probe](qualification/portable_queries_decode_probe.zig), built with
LLVM `-OReleaseFast` against each tree, decodes each compiler's own checkpoint
400 times per round for 11 alternating rounds
([driver](qualification/portable_queries_decode.ts),
[CSV](qualification/portable-queries-decode.csv)). Median process-CPU decode
cost rises by a geometric mean of **1.156×**: −6 µs (requests) to +47 µs (ecs,
350→397 µs). Requested decode allocation rises 7.5–39%, the largest relative
changes on 1–2 KB checkpoints. The added decode cost stays below 0.25% of each
workload's median restart CPU. During the probe and the synthetic
`bench:compile` parity run, a concurrent Playwright headless Chromium held host
load near 15–16 on 16 CPUs; one-minute load was 3.2–4.8 during the restart
driver. Scheduling was SCHED_OTHER, nice 0, unpinned, with the schedutil
governor and boost enabled.
`deno task bench:compile --workload synthetic --runs 7 --restart-cache` verified
identical Wasm across compilers and fresh/retained/restart phases; its 10 ms CPU
resolution is not used as evidence.

## Remaining scope

- Task 020 represents selected/canonical specialization, capture, provider,
  generative and other semantic graphs for process-boundary persistence.
  Refinement, local templates, source validation and executable fragments stay
  owner-local and recompute after restart.
- Decoded machine bodies are checked for ordinals and structured control, not
  re-typechecked. A forged body with valid ordinals but inconsistent stack types
  still requires a matching checksum and compiler identity, and the host's Wasm
  validator remains the final check.
- Cross-space type/row cycles are bounded by importer depth and work rather than
  rejected during decoding.
- Principal reuse in a fresh session still admits a record only while its
  validated-call set is empty, so box-style workloads reuse one record in both
  compilers. That input gate is unchanged.
- Duplicated optimizer facts cost checkpoint bytes; decoding verifies them
  against the machine inputs rather than trusting either copy.
- The private gdev snapshot does not match the local `../gdev` checkout, so the
  application-wide gate in tasks 002 and 084 remains unmeasured.
