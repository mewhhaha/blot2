# Resolved calls

Task 025 separates call selection from Wasm instruction emission. Before it,
[the emitter](src/core_backend.zig) chose targets, walked the closures applied
to further arguments and derived indirect call signatures while it was already
emitting a call's instructions, and indirect closure calls typed their table
entry from the machine types of the argument and result values. The milestones
are `b0c9168` and `29aaa98`.

## Plans

[resolved_call.zig](src/resolved_call.zig) defines what preparation hands to
emission:

- `Named`: a named call's specialization `Key` (target, parameter and result
  layouts, effect rows, templates) and an `Arrow` for every argument past the
  callee's parameters.
- `Applied`: a selected method or resolver target taken either as a direct
  specialization or through a callable wrapper, how many arguments it
  consumes, and the arrows of the closures applied afterwards.
- `Arrow`: a closure's semantic interface, from the callee's own type:
  parameter and result layouts and the latent effect row.

The emitter adds `StaticClosurePlan` for a statically known anonymous closure:
its closure identity, captured values, interface layout and specialized
mappings and rows, refined against the caller's argument signature.

## Rules

- Every source call is prepared before its first instruction: named calls
  (`prepareNamedCall`), operator methods (`prepareDispatch`), resolver
  operations (`prepareResolverCall`, before the resolver expression itself is
  emitted), closures called through their table entry and `run`
  (`prepareIndirect`) and statically known closures (`prepareStaticClosure`).
  Callable templates select their template and interface before their
  instructions as before.
- Indirect `call_indirect` signatures come from the callee's arrow, never from
  the machine types of the values passed.
- Preparation reports an unresolved call before any of its instructions, at the
  call's own node.
- Creating or reusing a function index stays at the point emission reaches it,
  so function order, type interning order and every emitted byte are unchanged.
  Whether to inline also stays with emission, because it depends on the code
  already emitted.
- Work counters (`prepared_named_calls`, `prepared_dispatch_calls`,
  `prepared_resolver_calls`, `prepared_indirect_calls`,
  `prepared_static_closures`, `prepared_extra_applications`) count prepared
  calls by shape.

## Qualification on 11 October 2026

- Zig 0.17.0 before every build batch. `deno task test:compiler` passes the full
  LLVM native suite and 641 guest/client tests; `deno task lint:zig` reports
  zero findings across 311 files.
- Every public example, the synthetic `bench:compile` corpus in every phase
  (fresh, population, first and later edits, no-op) and the frozen gdev copy
  emit byte-identical Wasm before and after (gdev SHA-256 `3158216b…def0`,
  840,534 bytes).
- [A process law](tests/resolved_calls.test.ts) executes named calls,
  closures typed by their callee, a closure held by a constant, an operator
  method that returns a closure and resolver binds through edits, with
  retained builds equal to fresh ones and fresh builds counting each shape
  through preparation. A build that logged prepared static closures showed the
  typed-path laws (`typed_path_execution.test.ts`) preparing 154 of them.
- On gdev a retained edit prepares 1,718 named, 513 operator and 76 indirect
  calls.

## Remaining scope

- Plans are prepared per call and dropped after emission; a resolved body that
  stores them, with control flow and ownership, is tasks 026–028.
- Lowering splits arguments past a named callee's parameters into separate
  applications, so the named over-application arrows are prepared but not
  reached by any example or by gdev.
- Partially applied and recovered known calls are prepared only for inlining;
  when not inlined they fall through to template or indirect preparation.
