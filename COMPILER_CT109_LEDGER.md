# CT109 disposition of all 86 review proposals

Follow-up: [CT110](zig-native/CT110_QUALIFICATION.md) adds shared effect-list
proofs, temporary buffers and bounded admission work. Its measured latency gains
are modest; inferred-requirement principals, repeated solves and graph matching
remain. The architectural qualifications in this CT109 ledger still apply.

This extends [CT106](COMPILER_CT106_WORK.md) against the original
[86-proposal review](COMPILER_REVIEW_CT105.md). The review includes conditional
experiments and alternative architectures, not 86 mandatory optimizations.
Implemented entries below describe code. The full Candidate 10 gate passes;
seven release pairs and held-out execution controls pass. The final 200-distinct-edit memory series also passes.
Rows inherited from CT106 retain their original evidence and limits.

All eight rows previously marked “Remaining” have now been implemented or
experimentally evaluated. This does **not** mean all partial or conditional
architectures are complete, or that the two-second/sub-second targets are met.
See [the work record](COMPILER_CT109_WORK.md) for rejected trials and exact pins.

| # | Current disposition | Evidence / boundary |
| - | - | - |
| 1 | Implemented | Precise graph failure, first pair/tag, depth and remaining work; the observed failure was incidental constructor sharing. |
| 2 | Implemented | Exclusive query prepare/scan/source/import/match/validate/publish clocks and chain statistics. |
| 3 | Partial | Adds per-caller solver/scratch requested bytes, allocation counts, source-projection scratch and retained optimizer/encoding capacity. Physical per-owner peak/copy attribution is not complete. |
| 4 | Partial | All-thread request PMU comparison and future/retained-thread collector controls pass. Internal-phase and model-specific cache/TLB counters remain open. |
| 5 | Measured | Seven unpinned release pairs plus opposite-order five-core/SMT-set screens, with load/frequency snapshots. No affinity default changed. |
| 6 | Measured | Separate first literal, unseen literals, body, reverts, no-op, error and recovery cases; controls are explicit. |
| 7 | Measured; qualified | Candidate 10 passes 232 requests over 200 distinct edits with 12 sampled fresh controls, no-ops, errors, recovery and restoration. Idle RSS is 521 MiB; lifetime HWM 773.92 MiB. Unsampled revisions lack independent fresh controls; this does not bound an indefinite session. |
| 8 | Measured; qualified | Three alternating pairs cover 11 held-out cases, including lexical generic schemes at widths 32/64. All exact output controls and 44 independent original/edited Wasm executions pass. |
| 9 | Implemented | Generation-guarded operation argument certificates reduce actual height checks from about 76M to 1.8M on the fresh workload. |
| 10 | Implemented | Bounded closed-argument shapes select exact oldest-match chains: 90.45M candidate inspections become 0.74M. Hash collisions still require equality. |
| 11 | Conditional | Dense certificates remain: no touched-density or cache-level evidence yet justifies a paged representation. |
| 12 | Measured; policy retained | Three alternating row-cache-off pairs preserve output but regress first-literal/revert CPU about 7%; keep caching. Probe, collision, context and stale-history counts are implemented. |
| 13 | Implemented | First-successor and last-write cutoffs avoid forward walks for immediate and future cursors. Long interior chains still use the original chronological walk. |
| 14 | Implemented | Wide label multisets use temporary counts, retaining duplicate multiplicity and argument validation; small rows keep the allocation-free path. |
| 15 | Implemented | Wide records index field names while preserving the original first-match semantics. |
| 16 | Implemented | Certified closed DAG pairs are deduplicated; open/cyclic graphs retain bounded validation. |
| 17 | Rejected experiment | Bounded exact-generation free-variable summaries produced two hits from 20,974 type queries and zero from 20,845 row queries. Removed; source and measurement preserved. |
| 18 | Measured; policy retained | Composite miss reasons are instrumented. Same-capacity two-way trial saves only 184 probes out of 3.83M; ordinary-edit benefit is not established. Keep the 16-slot direct map. |
| 19 | Conditional | No cross-call occurs cache added without repeated-query and mutation-validity evidence. |
| 20 | Conditional | Operation fingerprints and closed-node facts provide a bounded local experiment. A canonical composite store/substitution-overlay replacement is not implemented. |
| 21 | Implemented | Bounded exact-ID watcher traversal skips repeated shared nodes; collisions conservatively repeat work and projection accounting remains intact. |
| 22 | Conditional | No tiny-list/set transition: watcher key comparisons have not been shown to dominate whole-build CPU. |
| 23 | Rejected experiment | A bounded write-key coalescer observed zero duplicates on fresh/literal/body builds. Its extra state was removed; prototype retained as evidence. |
| 24 | Implemented | Exactly unchanged ordered frontiers retain their existing links. Changed frontiers still use the original full registration path. |
| 25 | Measured | Ready-word scans and subscriber visits are counted; no extra summary layer added without a measured CPU benefit. |
| 26 | Implemented | Row variables have per-lexical-scope links; sharing no longer scans the entire region map or builds a copied key list. |
| 27 | Implemented; qualified | Owner/span-keyed sorted summaries for immutable lists above 16 entries, bounded to 64 lists / 16,384 IDs. OOM/identity/saturation laws and wide lexical generic fixtures exercise it. |
| 28 | Partial | A bounded 32-caller census now attributes regions, scopes, nodes and requested bytes. Residual owned-code, specialization, source-interface and closure regions remain; no eliminated family is claimed. |
| 29 | Implemented | Selected-query buckets include options/depth. Candidate count is unchanged on this workload, so no lookup speedup is claimed. |
| 30 | Implemented | Canonical-specialization bucket keys include mode/expected/options/depth within the same owner; exact capture and alias checks remain authoritative. |
| 31 | Implemented; qualified | Unsupported direct canonical captures decline before full key construction. Nested capture checks remain; the pending-demand law proves saved construction and unchanged evaluation. Zero gdev prefilter calls. |
| 32 | Implemented | Optional canonical replay admission is checked before copying replay arrays; final admission and allocation failure remain distinct. |
| 33 | Implemented | Validated dense unit IDs use direct lookup; sparse, duplicate and implicit IDs retain the original first-match fallback. |
| 34 | Conditional | No admission policy based on guessed value per byte. Bounded existing limits stay in place until reuse value is measured. |
| 35 | Implemented within exact boundary | Checked-scheme reads with no obligations record a separate interface observation. Actual body reads remain exact. Portable key v8, ownership, bounds, OOM, errors/recovery and executed-Wasm laws cover the new surface. |
| 36 | Partial | Unique declaration names at matching binding ordinals and uniform relative positions admit one more body principal (17/20). Duplicate/moved identities decline. Three consumed-body dependencies remain. |
| 37 | Implemented; qualified | Memoizes only immutable source admission in bounded owner-pair plans. Dynamic configuration, budgets, observed values, negative reads and proof validation still run. |
| 38 | Measured; rejected experiment | Import census shows 4.006M fragment memo hits but only 734 new nodes. A 2 KiB hot cache avoids 4.005M lookups but does not establish ordinary-edit benefit; body CPU worsens about 5% in the three-pair screen. Removed. Cross-owner sharing remains conditional. |
| 39 | Implemented within measured scope | Static capture matching uses existing sparse QueryScratch with exact owner/generator/session/gate guards. Projection traversal reuses generation-tagged arrays and stack per changed module. Rollovers, declines and OOM are covered. |
| 40 | Conditional | Owned contiguous replay payload transfer remains an alternative; preserving small borrowed lifetimes is preferable to retaining whole snapshots without evidence. |
| 41 | Rejected experiment | Finer arena bins reduced some peak capacity but increased requested/provided growth and failed the target. Original bins restored. |
| 42 | Conditional | Larger-bin borrowing is not enabled; the measured bin experiment did not establish a beneficial fragmentation/retention tradeoff. |
| 43 | Conditional | The bounded one-slot pool remains. No multi-slot pool is justified by a measured overlap/hit-size benefit yet. |
| 44 | Measured | Oversized arena discards and discarded bytes are now counted. The 64 MiB retention cap remains after the capacity experiment failed its target. |
| 45 | Implemented | Small traversal-only semantic/artifact import buffers use stack-first allocators and release locally; durable outputs retain their existing owner. |
| 46 | Implemented | Import lists reserve from exact local child/label bounds. No speculative maximum-capacity reservation or wholesale chunk conversion. |
| 47 | Measured | Small-heap slab/free/unused/rounded-live capacities stabilize by edit 10 in the profiled window. Growing slab capacity does not explain the RSS rise; idle trimming not installed. |
| 48 | Conditional | No allocator lock redesign without contention attribution. Profile-only occupancy traversal locks briefly; allocation/free gain no per-call instrumentation. |
| 49 | Conditional | Mapping stays under the existing heap lock until refill contention is established; no speculative concurrent publication protocol. |
| 50 | Conditional | Worker output cloning remains; transferable allocations need an owner narrower than a whole worker arena. |
| 51 | Conditional | No broad hot/cold layout rewrite without cache-line evidence. Local dense indexes and bounded scratch changes are the implemented layout work. |
| 52 | Conditional | No huge-page or placement policy changed. Fixed virtual capacity with increasing residency does not establish a TLB bottleneck. |
| 53 | Rejected experiment | Same-source host-native LLVM screen regresses first-literal CPU 7.1% and literal-revert CPU 6.2%. Portable baseline targeting remains unchanged. |
| 54 | Conditional | No BOLT tool is installed and no Zig PGO build integration was established. Training/layout changes remain a separate reproducible-build project. |
| 55 | Measured | closedHeight disassembly confirms repeated generation/physical-owner loads. Caller certificates remove repeated checks; no blanket forced inlining. |
| 56 | Partial | Operation/query/composite/row work is attributed, and import memo hits/new nodes are counted. General hash-table tombstone/probe instrumentation is still absent. |
| 57 | Implemented | Dense unit lookup has a verified sparse/duplicate fallback. No arrays are allocated to arbitrary external IDs. |
| 58 | Partial | Sparse capture/projection scratch avoids repeated full clearing. Asset framing removes the aggregate server reply copy: 2 × 8 MiB fixture lowers edit HWM by about 18 MiB. General copy-site attribution remains open. |
| 59 | Conditional | No tag specialization or branch hints without branch-distribution evidence. |
| 60 | Conditional | Candidate-chain removal precedes prefetch experiments. No latency or independent-work evidence currently justifies prefetching. |
| 61 | Measured | Two/four semantic workers admit 281 jobs in 14 fresh-game batches but do not improve ordinary edits. Four workers regress devtools CPU 5.4%; recording remains the dominant eligibility blocker. Serial default retained. |
| 62 | Conditional | Dependency-ready queue changes wait for a useful eligible semantic workload; current SCC and publication ordering remain intact. |
| 63 | Conditional | Private proof-log parallelism needs a new deterministic publication contract; recording/refinement guards remain intact. |
| 64 | Implemented; qualified | Backend workers consume a compact heavy-first queue of actual optimization/RC jobs. Ties, publication and failure selection remain deterministic. Worker wall and Linux CPU intervals are measured separately. |
| 65 | Partial | Private per-worker jobs/instructions, finish times and Linux thread CPU are implemented. Observed finish spread around 0.1 ms does not establish false sharing; no padding or worker increase adopted. |
| 66 | Implemented; qualified | Retains final optimized-body RC verdicts under exact graph/summary and arena/cohort/helper-role correspondence. Module-wide ownership admission remains separate. |
| 67 | Not triggered | The observed frontend failure was constructor sharing, not depth/work exhaustion. An iterative walker was therefore not the appropriate fix. |
| 68 | Implemented | Equal immutable constructors may have different sharing; type and row variables still require injective correspondence. |
| 69 | Implemented within exact boundary | Obligation-free checked-interface observations compare the existing exact callable identity, schemes, rows, flags and catalogs. No hash-only admission or executable/value authority is granted. |
| 70 | Partial | Source-validation owner work is counted separately from retained zero-work leases; generation-tagged projection scratch avoids repeated full clearing. General frozen-subgraph certificates remain conditional. |
| 71 | Implemented; qualified | A 4,096-record generic cap prevented the 8,550-body optimizer capture from sealing. Its own bounded 16,384-record / 8 MiB index enables unchanged-function optimization reuse; generic limits stay unchanged. |
| 72 | Implemented; qualified | Retains unchanged encoded function bodies under exact physical ordinal, index mapping and complete emission context. Both payload and allocated capacity are capped at 8 MiB; full sections/output remain mandatory. |
| 73 | Implemented; measured | Segmented asset replies retain owners through flush and validate summed lengths first. Five alternating pairs / 40 requests pass independent asset hashes and runtime oracles. Fresh HWM 48.99 → 32.07 MiB; edit 69.32 → 51.24 MiB. |
| 74 | Conditional | Both existing codegen tiers are tested. No consumer delta protocol or incomplete full-output replacement was introduced. |
| 75 | Measured | All 20 complete fixed-family edit/check cycles pass: 25.35 s median, 27.64 s observed p95, 27.78 s maximum. Production/test identities, exact native inventory and every source restoration pass; full qualification stays separate. |
| 76 | Measured | Actual Zig report: LLVM emission 220.884 s of 227.759 s; parse/sema/generic counts and raw frames retained. Full collector replay and incomplete-stream rejection controls pass. |
| 77 | Not selected | The trace assigns about 97% of release wall time to LLVM emission. No erased-interface runtime tradeoff is justified by the much smaller declaration stage. |
| 78 | Qualified | Candidate 10 passes all 2,573 native laws with complete allocation-failure sweeps in four isolated shards (1,672 completed profiles / 812,228 scenario executions), plus 1,656 guest tests. Sampled development checks remain separate. |
| 79 | Conditional | CT109 four-shard durations span 630–651 s with existing per-law weighting. No scheduling redesign is justified by that limited headroom. |
| 80 | Implemented | Stable compilation caches and Safe/noLLVM remain. A discovered stale configuration digest is repaired by recomputing build configuration; retained/fresh identities now agree. |
| 81 | Partial prerequisite; architecture conditional | Stable named origins and explicit interface/body observations now exist. A unified dependency query graph with exact negative reads, cycles and deterministic invalidation is not implemented. |
| 82 | Conditional; not selected for current hotspot | Four million repeated fragment queries import only 734 new nodes. That evidence prioritizes memo lookup over replacing ownership with a shared IR. A broader immutable owner design remains an alternative. |
| 83 | Conditional | Resumable inference is not implemented. Three real body dependencies and residual solver work remain; precise constraint/substitution invalidation requires a separate ownership design and locality evidence. |
| 84 | Implemented within current reuse layers | CONTRACT.md distinguishes declaration identity, checked interface, consumed body, evaluated value and executable authority. New checked-interface observations do not grant stronger products; layers are not replaced with a unified query service. |
| 85 | Not selected | The stated priority is ordinary edits producing complete builds. No new incomplete interactive product is presented as a sub-second compile. |
| 86 | Not selected | Existing restart caching remains separate from changed-edit performance. No new module service is needed to evaluate the current ordinary-edit goal. |
