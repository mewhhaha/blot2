# Owned iterator and constant receipt checkpoint

Local compiler `6a57437` qualifies a bounded part of tasks047/086. Both tasks
remain open. No push or private-source publication occurred.

Implementation tree `885c7d8a8461d404990a309d89d095fceb24e85f`; compiler source
`b9d9208f0938ab2111a913328a8b0992792623c3`; Zig0.17.0, standard LLVM/Fast.
Executable SHA256:
`904b1ac1558ae3d5c9b1c11744f6cf45a096297753b4b8e572fc4bb99935adb2`. Identity:
`fed7cd0992260a600cf4421f95c095e3ef9407f5438439ca9a1d1ed0e493d3db`. Immutable
binary, patch and gate pins: `build/bench/joint-047-086-qualified/`. Measured
reports and their hashes: `build/bench/joint-047-086-repaired/`.

## Behavior and validation

Exact reference fields in private scalar-replacement groups use independent
locals and reusable function-frame roots. Copies read all predecessors before
writing destinations. Unknown fields, captures and escapes keep heap storage.
Bounded straight-line producers expose up to four small allocations. Late module
ownership failure rebuilds immutable source without owning-field optimization;
scalar-only modules retain their original symbolic guards. Mutable
exported/imported tables and shared code disable the owning context.

Checked flat packed List cursor families use four private locals and the
canonical collection as their owning carrier. Published cursors, snapshots,
reference/plain-word layouts and unsupported control retain ordinary storage.
Constructor-body observations participate in retained/portable validity.

Constants reuse owned scalar/primitive-collection outcomes only after exact
read, input, fuel and resource validation. Principal preparation, final type
validation and slot publication remain ordinary. Ready partial Array-member
judgments have separate complete observations. Member receipts are omitted from
the portable closure schema; valid older closure records remain usable.
A128-step floor and early compound-head decline remove unprofitable dedicated
receipt bookkeeping from the captured project.

`deno task test:compiler` passes the full native/OOM suite and973 guest/client
tests, including all eight unchanged budgets. `deno task lint:zig`:355 files,
zero findings. Both codegen tiers, sync/JSPI rejection and recovery, changed
constructors, fresh/retained/checkpoint output and source fuel are covered.
Changed TypeScript tests pass formatting checks.

Two failures remain preserved. The initial blanket ownership retry broke one
scalar-only reuse law; the narrowed correction passes. The corrected compiler's
first full guest run passed972/973; the wire contract omitted the added
`constantReceipts` counter object. Its updated42-law protocol suite and final
full gate pass with compiler source/binary unchanged. The final gate reuses the
successful native cache, rather than claiming a second native execution.

## Measured costs

Guest counts use instrumented copies; CPU uses ordinary output. These scopes are
separate from compiler requested allocation and process RSS.

| 4096-row workload                    | Incoming | Candidate |
| ------------------------------------ | -------: | --------: |
| Array cursor objects                 |     4098 |         1 |
| Array cursor requested payload bytes |    81940 |     16388 |
| Array cursor median CPU ms           |  0.29625 |  0.045375 |
| Generic range/map/take objects       |    57350 |     53254 |
| Generic requested payload bytes      |   442416 |    409648 |
| Generic median CPU ms                |   3.3145 |    3.0925 |
| Scalar cursor median CPU ms          | 0.023875 |  0.023875 |

Thirty-one alternating warmed release pairs run on CPU7. Roots, leases and live
profiling payload are zero after shutdown. Ordinary ownership controls remain
at128KiB; sync/JSPI cycle CPU ratios are0.9206/0.9129. Other ownership controls
span0.9776–1.0211; no universal runtime gain is claimed.

Three complete F32 record/tuple batches retain every supported width, oracle,
16384 rows and31 alternating pairs of16 traversals. Largest median-of-three
cursor ratios against reconstructed boxed are0.9473 records and0.9515 tuples.
The isolated U32 boxed tail remains unresolved; it is not closed by these F32
results. Packed geometry/memory and public representation are unchanged.

Seven public-example pairs preserve diagnostics, semantic work, per-binary
determinism and zero teardown. CPU ratios span0.9725–1.0149; requested
allocation deltas128–484092B; peak deltas zero. Seven synthetic
fresh/retained/restart pairs have exact bytes and no reported problems. Seven
public outputs intentionally change under the new runtime lowering.

Seven constant/member process pairs on CPU6 retain exact bytes and source fuel.

| Class, candidate/control CPU |  Fresh |   Edit | Revert |
| ---------------------------- | -----: | -----: | -----: |
| Scalar                       | 1.0039 | 0.9879 | 0.9851 |
| Qualified scalar             | 0.9989 | 0.9803 | 0.9749 |
| Literal Array control        | 0.9989 | 1.0054 | 1.0045 |
| Computed Array               | 1.0142 | 0.9929 | 0.9847 |
| Small member control         | 1.0042 | 1.0056 | 1.0165 |
| Deep member                  | 1.0119 | 0.9474 | 0.9145 |
| Captured93-unit project      | 1.0282 | 1.0491 | 1.0475 |

The captured project records zero constant receipts, lookups, payload and graph
indexes. Per-compiler fresh/retained/revert bytes and source fuel match; changed
runtime lowering explains cross-compiler bytes. Its roughly5% retained CPU
regression is disclosed: assembly rises about72 to129ms because late ownership
failure prepares the module twice. This checkpoint establishes no project-level
constant payoff or100ms edit target. The captured input is distinct from the
historical400ms workload and remains private.

## Remaining work

Generic tagged step objects, other adapters and U32 packed cursor tails remain
for047. Projection and word-position followups are separate unqualified slices.
086 still needs growth/enclosing judgments, escaping typed-view publication,
broader relocation/serialized-data retention and portable member authority. 035
still needs complete tracing removal and its historical CPU acceptance. The
early source-conflict fallback experiment is also separate; it cannot be
credited to this binary. [Iteration costs](ITERATION_COST.md) distinguishes
fresh source builds, retained edits and cache reuse.
