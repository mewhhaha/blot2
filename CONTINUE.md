# Continue the Goose compiler experiment

Finish ownership repairs, build the actual complete C/header/native compiler,
then qualify CLI/server, request OOM/retry and retention against Zig.
**No whole compiler artifact exists.** Helper laws never substitute for
integration; never forward Goose requests to the Zig oracle.

## Current frontier

Actual whole160 stops after **157.07s**, with unchanged source and no artifacts:

- `backend/storage_global_footprint.goose:92`: a borrowed slot slice is stored in
  the completed cache (§9.2).
- `backend/resolved_body.goose:60`: saved effect identities may retain payloads,
  published through `eval/purity_type_key.goose:59` (§5.1).

See [the exact whole receipt](benchmarks/evidence/qualification/2026-11-10-goose-whole160.json.gz).
The preceding visitor and frozen Module publication failures are cleared. Their
affected laws pass in **17.94s**: parameter traversal order/deduplication,
foreign/whole/depth/unsupported fallbacks, result-owner independence and adopted
fresh/cloned nested Module payloads across Frame/reclamation. See
[the executed pair](benchmarks/evidence/qualification/2026-11-10-goose-parameter-frozen-module-laws.json.gz).

Current selected163 takes 56.41s and clears FunctionPlanInput publication. The
next boundary is scoped_backend2426: a Core child-ID view held across recursive
expression evaluation (§5.2). A coherent Core-view traversal repair is next.

Planning requests now contain scalar unit IDs and ranges into existing graph,
evidence and recursive-access owners, plus the existing rejection slot. They
retain no module/graph/key headers; observations reborrow unchanged existing
runs. No new pool, copy or clone. The durable snapshot/cache/footprint trio passes
**17.38s**. Actual Input<Value> checks through the old request frontier;
full generator runtime remains pending. Inventory now 31 laws, not yet run together.
See [the scalar request receipt](benchmarks/evidence/qualification/2026-11-10-goose-scalar-plan-input-family.json.gz)
and [production trio](benchmarks/evidence/qualification/2026-11-10-goose-scalar-plan-input-laws.json.gz).

The cache/effect-key pair passes 14.68s; transitive cache/Frame coverage passes 7.56s.
Footprint cache publication reifies existing slot/node runs. Effect scratch owns
already-required encodings and scalar text ranges, preserving exact order/bytes
without more successful text copies/allocations. Encodings stay live through
sort/emit; scratch headers grow 8B/entry. Exact scopes remain in the receipt index.

Six affected production laws pass together in **67.46s**: proof leases,
diagnostics, semantic outcomes, worker pins, key cache and resolved bodies.
A final diagnostic-OOM correction follows; the production diagnostic law then
passes in **6.55s**, including failed-ensure preservation. These are bounded
family checks. The latest complete30 helper inventory is **221.34s** at
`f0a602bc`, before these repairs. Exact closures and native C/link/runtime results:
[affected six](benchmarks/evidence/qualification/2026-11-10-goose-active-child-six.json.gz),
[final diagnostic law](benchmarks/evidence/qualification/2026-11-10-goose-diagnostic-restore-final.json.gz),
[complete30](benchmarks/evidence/qualification/2026-11-10-goose-complete30.json.gz).

## Source contracts and qualification limits

- PlanConstruction owns scratch data. The active child stays at one Generator
  address through all phases, is cleaned up once, and the parent is restored
  once. Native miniature controls cover phase errors, diagnostics, max_stacks,
  counters and dormant aliases; actual generator runtime remains pending.
- Arena traversals retain scalar ranges and reload elements across growth.
  QueryScratch retains checked owner/generation/lease keys, not invocation borrows.
- Query replay preserves the destination allocation slot and reconstitutes its
  owned Judgment. Exact workspace source/catalog accessors check existing owners.
- Recorder event publication and stable compaction use existing named pools and
  Query slots. Mixed-event order, coalescing, Frame/readback and cleanup pass.
- Panic messages use the existing Session diagnostic owner. Speculative probes
  skip prior diagnostics and discard failed probe messages. Receipt tape backs
  up text separately from scalar/fixed metadata; fresh owned restoration reserves
  capacity before mutation and preserves the original operation error priority.
  Native leaf ownership laws pass; full probe/tape runtime remains pending.
- Key equality compares evidence contents. Declined caches share storage_calls
  own/release; duplicate copying and its pool are removed. No compatibility API.
- Imported gates use their existing copied identity and close before that owner.
  Producer retirement passes, but the actual factory Frame fixture remains
  rejected. Known unqualified legacy API: host_cleanup_shapes.copyFields.

Receipts, historical checkpoints and failed experiments remain indexed in
[the completion frontier](benchmarks/evidence/qualification/2026-11-09-goose-completion-frontier.json).

## Tooling and remaining delivery

Use the pinned private checker at
`build/goose-port/argcopy-experiment-20261110/goose`, SHA256
`c2b24b697acfff54f5e89fb7eeb024fc2e528ff46e7582faf7714662d3067632`.
Its optional copied-argument recipe has 21 lifetime controls; exact storage identity,
deep reads and recursive conservatism remain intact. Installed Goose and 678 are
unchanged. The separate store-origin diagnostic binary is off-tree and never
promoted. Do not relax checks or clear live owners to hide failures.

Selected roots are partial, check-only paths. Scoped uses invalid empty Core;
it never qualifies runtime. Regenerate adapters once for layouts, fully await
completion, then freeze source. Repair cap 120s, final emission 180s, whole 300s;
stop 3s after an actual diagnostic. Never lift caps to conceal unfinished work.

After an actual executable exists, run `compiler-goose/tools/qualify_compiler.ts`
with that executable and `compiler/zig-out-native-fast/bin/blotc`. Eight matching
Zig baseline fixtures pass; Goose CLI/server/OOM/retry/retention have not run.
Fake entry/component controls do not qualify those paths. Missing live bytes are
not zero. Preserve compiler/ and sibling assets, ABI 8/session 2 and named owners.
Language tasks remain retired; copied-packet host workers remain.

Zig source is unchanged. Its prior full gate is incomplete: all 2974 laws compile
without LLVM, but release compilation hit 120s after 94 laws / 65 full sweeps. Smoke,
harness and zero-finding lint pass. Do not rebuild that release per Goose edit.
Named-function source migration is checkpointed, not fresh Main/frame coverage.
Historical Main 9,203,613B/5.523s belongs to its older release; no reliable compile
speed gain. Subsecond compilation, sub-five-second Main and 1–2MB remain unmet.
Preserve remaining requirements in [the storage task](tasks/STORAGE_REWRITE.md)
and [the language migration](docs/language/NEXT_MIGRATION.md). Environment
publication/upstream messages require explicit requests. Astra for concrete
snags only; never Terra.
