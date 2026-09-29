# Bend compiler architecture redesign

PR #7 stays in Bend. Its baseline is merged main
`5c2640493987c4b8c2335b7b05ad99b654689ac4`.

The OCaml experiment is preserved on `archive/ocaml-typed-core` at
`407a691e18883e5782adf49f03d4c0fa5d6d026a`. This branch removes that
experiment from the proposed source tree without rewriting its history.
There is no new compiler implementation language, native bridge, or fallback.
The existing TypeScript parser/host and Wasm ABI remain unchanged.

## Work model

Keep immutable, exact semantic results in the Bend pipeline instead of
reconstructing them at the next stage. A checking task owns its inference state;
independent declaration groups can use Bend's existing fork/join scheduling.
No shared mutable solver or generated-C/JavaScript patch is introduced.

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

## Checkpoints

The Bend redesign checkpoint workflow archives the exact committed source and
its checksum on every push, independently of compiler validation. Tests and
performance results must name their exact source and toolchain. Source-to-Wasm
time, compiler-build time, cache hits, and generated-program runtime are separate
measurements. No speedup is claimed by this direction-setting checkpoint.
