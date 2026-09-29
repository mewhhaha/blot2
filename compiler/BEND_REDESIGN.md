# Bend compiler architecture redesign

PR #7 stays in Bend. Its baseline is merged main
`5c2640493987c4b8c2335b7b05ad99b654689ac4`.

The OCaml experiment is preserved on `archive/ocaml-typed-core` at
`407a691e18883e5782adf49f03d4c0fa5d6d026a`. This branch removes that experiment
from the proposed source tree without rewriting its history. There is no new
compiler implementation language, native bridge, or fallback. The existing
TypeScript parser/host and Wasm ABI remain unchanged.

## Work model

Keep immutable, exact semantic results in the Bend pipeline instead of
reconstructing them at the next stage. A checking task owns its inference state;
independent declaration groups can use Bend's existing fork/join scheduling. No
shared mutable solver or generated-C/JavaScript patch is introduced.

The intended migration is:

1. Retain validated dependency and checking plans, with exact source ownership.
2. Keep checked generic bodies and residual type/effect requirements together.
3. Resolve and deduplicate complete specialization instances before expansion.
4. Invalidate semantic results by body, interface, lookup-catalog, and captured
   dependencies, rather than treating all changes as a whole-program request.
5. Emit from retained checked results and measure complete source compilation.

Only implemented, tested stages may be described as complete. Unused source
still requires validation. Recursive groups, nominal identity, scoped effect
multiplicity, diagnostics, fuel limits, and failed-edit rollback remain part of
the compatibility contract. Hash equality alone is never proof of equivalence.

## Implemented: checked-result handoff

`Core.Prepared` now distinguishes an unchecked/transformed module from an exact
module that has already passed checking. In the no-template path,
`Mono.prepare_initial_templates` can retain the whole initial checked result.
`CheckScheduler.check_prepared` consumes it without rebuilding the final module
dependency graph, SCC plan, catalogs, queues, or certificate index.

The handoff requires exact ordered body/catalog equality with the checked
snapshot, no deferred source forms, and no unresolved use/interface predicates.
Same names, matching signatures or hash equality are not sufficient. Any
transformation or unproved requirement keeps the original checking path. Initial
validation of all declarations, entry verification, constant evaluation, Wasm
emission, and incremental-session behavior remain in place.

This is a source-pipeline stage boundary, not a result-cache hit or a new
runtime. Four focused regression tests compare it with ordinary final checking,
require that the handoff actually executes, and reject changed bodies, source
sites, catalogs, and unresolved requirements. The three constructor-level laws
are not a proof of the entire compiler. Full native parity and performance are
separate validation gates; no speedup is established by the implementation
alone.

## Checkpoints

The Bend redesign checkpoint workflow archives the exact committed source and
its checksum on every push, independently of compiler validation. Tests and
performance results must name their exact source and toolchain. Source-to-Wasm
time, compiler-build time, cache hits, and generated-program runtime are
separate measurements. No speedup is claimed by this direction-setting
checkpoint.
