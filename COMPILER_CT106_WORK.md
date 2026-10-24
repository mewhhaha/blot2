# CT106 experiment ledger

This records all 86 suggestions in the [CT105 review](COMPILER_REVIEW_CT105.md). The [qualified CT106 implementation and measurements](zig-native/CT106_QUALIFICATION.md) are installed locally. Implemented work, rejected trials, conditional alternatives and remaining work are explicit; this is not a claim that 86 compiler features were implemented.

| # | Disposition | Evidence / boundary |
| - | - | - |
| 1 | Implemented | Precise graph failure, first pair/tag, depth and remaining work; the observed failure was incidental constructor sharing. |
| 2 | Implemented | Exclusive query prepare/scan/source/import/match/validate/publish clocks and chain statistics. |
| 3 | Partial | Arena requested/provided/reused/fresh/remap capacity, discard counts, and small-heap occupancy added. These do not cover every allocator owner. |
| 4 | Partial | All-thread request PMU comparison and future/retained-thread collector controls pass. Internal-phase and model-specific cache/TLB counters remain open. |
| 5 | Measured | Seven unpinned release pairs plus opposite-order five-core/SMT-set screens, with load/frequency snapshots. No affinity default changed. |
| 6 | Measured | Separate first literal, unseen literals, body, reverts, no-op, error and recovery cases; controls are explicit. |
| 7 | Measured | 200 distinct edits, 232 requests, 12 sampled fresh controls passed. Additional profiled runs distinguish capacity from residency; not a proof of indefinite stability or every cache reaching saturation. |
| 8 | Measured | Five historical synthetic programs and nine explicit wide-record/effect, deep-closure, shared-DAG, multi-module and small-program cases pass three-pair fresh/retained controls. All 36 runtime executions pass. Most timings are below useful CPU-tick resolution. |
| 9 | Implemented | Generation-guarded operation argument certificates reduce actual height checks from about 76M to 1.8M on the fresh workload. |
| 10 | Implemented | Bounded closed-argument shapes select exact oldest-match chains: 90.45M candidate inspections become 0.74M. Hash collisions still require equality. |
| 11 | Conditional | Dense certificates remain: no touched-density or cache-level evidence yet justifies a paged representation. |
| 12 | Remaining | Exact-epoch row hits remain zero in the workload; an isolated cache ablation has not been completed. |
| 13 | Implemented | First-successor and last-write cutoffs avoid forward walks for immediate and future cursors. Long interior chains still use the original chronological walk. |
| 14 | Implemented | Wide label multisets use temporary counts, retaining duplicate multiplicity and argument validation; small rows keep the allocation-free path. |
| 15 | Implemented | Wide records index field names while preserving the original first-match semantics. |
| 16 | Implemented | Certified closed DAG pairs are deduplicated; open/cyclic graphs retain bounded validation. |
| 17 | Remaining | No free-variable summary cache added. Exact substitution-generation ownership and construction cost still need attribution. |
| 18 | Remaining | Composite-resolution miss reasons and associativity are not yet instrumented or changed. |
| 19 | Conditional | No cross-call occurs cache added without repeated-query and mutation-validity evidence. |
| 20 | Conditional | Operation fingerprints and closed-node facts provide a bounded local experiment. A canonical composite store/substitution-overlay replacement is not implemented. |
| 21 | Implemented | Bounded exact-ID watcher traversal skips repeated shared nodes; collisions conservatively repeat work and projection accounting remains intact. |
| 22 | Conditional | No tiny-list/set transition: watcher key comparisons have not been shown to dominate whole-build CPU. |
| 23 | Rejected experiment | A bounded write-key coalescer observed zero duplicates on fresh/literal/body builds. Its extra state was removed; prototype retained as evidence. |
| 24 | Implemented | Exactly unchanged ordered frontiers retain their existing links. Changed frontiers still use the original full registration path. |
| 25 | Measured | Ready-word scans and subscriber visits are counted; no extra summary layer added without a measured CPU benefit. |
| 26 | Implemented | Row variables have per-lexical-scope links; sharing no longer scans the entire region map or builds a copied key list. |
| 27 | Remaining | Large quantified-variable/closed-row membership summaries are not implemented. |
| 28 | Partial | Residual region counts, query stages and updated literal CPU stacks are available. A full per-caller region census and eliminated residual region family remain open. |
| 29 | Implemented | Selected-query buckets include options/depth. Candidate count is unchanged on this workload, so no lookup speedup is claimed. |
| 30 | Implemented | Canonical-specialization bucket keys include mode/expected/options/depth within the same owner; exact capture and alias checks remain authoritative. |
| 31 | Partial | Canonical request/candidate/hit counters added. Existing eligibility guards remain; no speculative source-only prefilter was installed. |
| 32 | Implemented | Optional canonical replay admission is checked before copying replay arrays; final admission and allocation failure remain distinct. |
| 33 | Implemented | Validated dense unit IDs use direct lookup; sparse, duplicate and implicit IDs retain the original first-match fallback. |
| 34 | Conditional | No admission policy based on guessed value per byte. Bounded existing limits stay in place until reuse value is measured. |
| 35 | Partial | Nested reads use bounded containing-declaration indexes, including suspension bodies. Ambiguity/caps fall back to whole-module observation. |
| 36 | Stopped at boundary | Two narrowing attempts exposed each declaration's own changed source position. Numeric identity and executable provenance were not relaxed; a stronger origin correspondence is required. |
| 37 | Remaining | No new cross-query receipt-validation memo added; source/configuration/observation identity remains necessary. |
| 38 | Partial | Small semantic/effect import temporaries use stack-first storage. A new cross-replay import deduplication cache is not implemented. |
| 39 | Partial | Small fallback import arrays avoid heap allocation. A broader touched-ID scratch conversion is not implemented. |
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
| 56 | Partial | Operation chain and selected-query bucket statistics are available. General hash-map probe/tombstone instrumentation remains open. |
| 57 | Implemented | Dense unit lookup has a verified sparse/duplicate fallback. No arrays are allocated to arbitrary external IDs. |
| 58 | Partial | Import scratch and local reservations remove known copies; weighted literal memcpy self share is about 3%. Full allocation-site copy attribution remains open. |
| 59 | Conditional | No tag specialization or branch hints without branch-distribution evidence. |
| 60 | Conditional | Candidate-chain removal precedes prefetch experiments. No latency or independent-work evidence currently justifies prefetching. |
| 61 | Measured | Two/four semantic workers admit 281 jobs in 14 fresh-game batches but do not improve ordinary edits. Four workers regress devtools CPU 5.4%; recording remains the dominant eligibility blocker. Serial default retained. |
| 62 | Conditional | Dependency-ready queue changes wait for a useful eligible semantic workload; current SCC and publication ordering remain intact. |
| 63 | Conditional | Private proof-log parallelism needs a new deterministic publication contract; recording/refinement guards remain intact. |
| 64 | Remaining | Compact/heavy-first backend job scheduling has not been implemented or isolated in a timing trial. |
| 65 | Partial | New hardware collection includes future workers and weighted stacks account for thread CPU. No false-sharing or per-worker finish-time claim. |
| 66 | Remaining | No new backend lifetime/RC-plan cache added; surrounding ownership facts remain part of any future key. |
| 67 | Not triggered | The observed frontend failure was constructor sharing, not depth/work exhaustion. An iterative walker was therefore not the appropriate fix. |
| 68 | Implemented | Equal immutable constructors may have different sharing; type and row variables still require injective correspondence. |
| 69 | Conditional | Exact interface comparisons remain authoritative. No new interface-only fingerprint bypasses catalogs or hidden dependencies. |
| 70 | Partial | Existing validated owners remain honored; first-edit frontend validation drops to one module. No new general frozen-subgraph certificate cache. |
| 71 | Measured | New weighted stacks retain SROA attribution. No additional optimizer cache was introduced without a safe changed-function key. |
| 72 | Remaining | Encoded body/section reuse is not implemented; exact function/type/global/table relocations and output ordering still need an owned correspondence. |
| 73 | Conditional | Asset concatenation remains only on the asset path. The non-asset direct Wasm reply is preserved; no unconditional copy saving is claimed. |
| 74 | Conditional | Both existing codegen tiers are tested. No consumer delta protocol or incomplete full-output replacement was introduced. |
| 75 | Measured | All 20 complete fixed-family edit/check cycles pass: 25.35 s median, 27.64 s observed p95, 27.78 s maximum. Production/test identities, exact native inventory and every source restoration pass; full qualification stays separate. |
| 76 | Measured | Actual Zig report: LLVM emission 220.884 s of 227.759 s; parse/sema/generic counts and raw frames retained. Full collector replay and incomplete-stream rejection controls pass. |
| 77 | Not selected | The trace assigns about 97% of release wall time to LLVM emission. No erased-interface runtime tradeoff is justified by the much smaller declaration stage. |
| 78 | Partial | Production import allocations reduced without weakening fault laws. Final exhaustive execution records 1,669 OOM sweeps and takes 648.72 s; no paired gate-speed claim. |
| 79 | Conditional | Final four-shard durations span 599–649 s with existing per-law weighting. No scheduling redesign is justified by that limited headroom. |
| 80 | Implemented | Stable compilation caches and Safe/noLLVM remain. A discovered stale configuration digest is repaired by recomputing build configuration; retained/fresh identities now agree. |
| 81 | Conditional | A first-class dependency-query graph requires stable declaration origins and exact negative reads. The source-position boundary is documented, not bypassed. |
| 82 | Conditional | Shared immutable IR/evidence is an architectural alternative to copying; no cross-owner numeric IDs or borrowed references were substituted for imports. |
| 83 | Conditional | Resumable inference requires exact edit locality and reversible solver provenance. The present principal-origin decline prevents claiming that prerequisite. |
| 84 | Partial | Frontend constructor correspondence, containing-declaration reads and executable validity stay separate and are documented in CONTRACT.md. |
| 85 | Not selected | The stated priority is ordinary edits producing complete builds. No new incomplete interactive product is presented as a sub-second compile. |
| 86 | Not selected | Existing restart caching remains separate from changed-edit performance. No new module service is needed to evaluate the current ordinary-edit goal. |
