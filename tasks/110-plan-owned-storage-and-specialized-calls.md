# 110 — Plan owned storage and specialized calls

## Status and scope

- **Status:** In progress — scalar, fixed-array destination and closed inline
  aggregate and readonly descriptor calls execute; general callback ABI and SCC
  planning remain incomplete.
- **Dependencies:** Agree the runtime region interface with its owner first;
  task 112 can proceed after the early interface handoff below.
- **Context:** [Task index](STORAGE_REWRITE.md) and
  [conversion review](../zig-native/STORAGE_REWRITE_REVIEW.md).
- **Outcome:** A checked storage plan drives reusable direct Wasm functions,
  with explicit result destinations and no counted allocation fallback.

## File ownership

Own new `zig-native/src/backend/storage_plan.zig` and `storage_calls.zig`, plus
`zig-native/src/backend/storage_liveness.zig`. Initially this task alone edits
`zig-native/src/backend/scoped_backend.zig`; hand that file to the integrator
after the first integration batch. Other agents propose integration changes
through their owned modules. Own focused native witnesses in new
`zig-native/src/backend/storage_plan_tests.zig` and `storage_calls_tests.zig`.
The integrator owns test registration, shared execution fixtures and gates.

## Early interface handoff

Publish the following concrete Zig declarations and ownership comments before
compilation. Give runtime and task 112 owners enough examples to implement
against them; agree revisions together rather than editing their files.

1. Owned plan IDs for layouts, values, owners, regions, functions and exits.
   Borrowed Core views never survive the plan's construction lifetime.
2. A value layout distinguishes scalars, fixed aggregates, pool descriptors,
   immutable sequence descriptors, borrows and compile-time callable evidence.
   Root sets and physical layout are separate evidence.
3. Region operations open, allocate, mark, rewind and close stable storage;
   caller destinations and temporary regions have distinct roles.
4. Exit records identify normally completing values, function returns, breaks
   and continues, and their exact cleanup/transfer obligations. Never paths
   supply no synthetic result value.
5. A specialization key includes exact source/target identity, concrete layouts,
   checked type/effect evidence, static callback identities and all static
   capture/argument evidence affecting the body. Runtime captures are explicit
   parameters; matching capture layouts alone cannot equate different static
   captures. Its summary records borrowed roots, fresh result destinations,
   possible writes and scratch requirements.
6. An emitter interface consumes completed plan records. Task 112 provides
   layout/control/collection planning through these IDs, without owning calls.

## Implementation steps

- Extract root propagation, scope exits and call protection from the mutable
  Wasm generator. Keep immutable Core/type validation independent and mandatory.
- Preserve complete possible roots at branches, stored elements and captures.
  Keep pending operands live while evaluating subsequent operands.
- Emit each admitted specialization once. Pass result destination regions from
  the caller; a callee's temporary region cannot become its result destination.
- Return descriptors and fixed fields using an explicit internal ABI. Transfer
  newly allocated results to caller destinations; borrowing an input preserves
  its exact origin rather than manufacturing a new owner.
- Close callee scratch on all normal exits. Keep suspended invocations alive
  until Foreign settlement; recover trap-abandoned scratch at invocation entry.
- Specialize known callbacks into direct calls, including partial applications
  with nonescaping scalar/borrow captures. Reject runtime-selected targets,
  callable storage and escaping invocation-local captures or demands.
- Analyze recursive call SCCs before emission. Reject recursive owning
  allocations/results and recursive growable scratch. Inspect the selected
  application slice before admitting scalar recursion; record either a bounded
  scalar ABI or an explicit initial rejection, without promising old parity.
- Reject general effect handlers/resumptions and language tasks with source
  diagnostics. Keep ordinary Foreign capability calls and host worker transport.
- Bound plan construction and specialization growth; exhaustion produces an
  owned diagnostic, never guessed roots or a counted-backend retry.

## Acceptance and integration

A helper returning `#[42]` uses caller storage; repeated calls reuse scratch. A
helper returning a borrow into its own local array is rejected. A known callback
capturing a caller view remains valid through the entire call, while a later
argument cannot shrink that view's owner. Two concrete generic layouts produce
reusable specializations rather than repeated expanded bodies. An early return
closes scratch while preserving transferred result storage. Recursive owner
allocation, escaping captures and runtime callback arrays fail before Wasm
publication. Allocation failure destroys unpublished plan evidence.

Write these as a compact family of semantic witnesses, not one test per edit.
Implement in batches and hand the integrator code plus the agreed API changes.
Do not compile after every edit or run private exhaustive gates. The integrator
runs the shared native/Wasm batch, then the required final compiler gate and Zig
lint for the integrated candidate, using Zig 0.17 and `-Dllvm=false`.

## Integration evidence, 2026-10-30

Closed inline record/nominal leaves now flatten parameters into Wasm words and
write aggregate results to a caller-owned slot. The caller loads the result into
locals, closes that owner and rewinds its scratch mark before continuing. The
admission walk rejects storage operations, unknown calls, callable fields and
unresolved generic layouts; those still use the existing checked planner.

The native laws prove helper reuse, including descriptor arguments from
independent owners. Executed-Wasm laws cover mixed integer/float fields, early
returns, 100,000 calls, checked links/views, local optional owners and
subsequent entry reuse. The focused call/record/capacity family passes 22 laws.
The complete 2,646-test native inventory compiles, and 36 selected native
storage laws passed in the latest shared check; that check stopped at a
corrected Markdown format failure, so it is not full qualification.

Completed source proofs and immutable catalog selections are reused only within
one compilation. Captured type environments are deduplicated, and dependent
field results/shared callback type variables are resolved before allocation.
These are semantic witnesses; physical word counts do not choose source types. A
subsequent change removes unrelated generic caller history from cache keys for
the already-proven closed leaf ABIs. Its new reuse law awaits the next shared
check. General reusable callbacks/borrowed results and recursive SCC admission
are still incomplete.

A subsequent source batch admits acyclic direct callees inside closed
inline-data helpers. Every reached header has closed plain parameters/results
and pure rows; generic headers, indirect calls, owning allocations and active
cycles decline. The called subtree is emitted once for the outer helper's
reusable ABI. Source authority remains independently checked. Native reuse/cycle
and the existing 100,000-call aggregate result witness await the next shared
build. This does not complete generic callback ABI or recursive SCC planning.

### Readonly callback captures

Reusable closures now accept scalar and readonly Array/Ref/Link/View descriptor
captures with plain element layouts. The exact checked capture/input/result
types and descriptor modes identify code; runtime owner IDs, epochs and offsets
remain parameters. Caller loop reads are registered before cache lookup,
including hits. The native reuse witness passes; executed offset, independent
owner, updated content and bounds/trap recovery witnesses pass in the 20-law
call/host batch. General static callback arguments, owning results and extracted
storage planning remain unfinished.

Selected calls and expression syntax now have separate limits of 128. A finite
44-helper chain executes, 130 active selected calls reject, and deeply nested
parenthesized syntax retains the parser's earlier rejection. Total expression
work limits are unchanged. The actual physics callback path exposed a
caller/captured type-environment collision. Composite type references now keep
their immutable captured substitution context while formal callee inference
remains separate. Nested active `Maybe.map`, independent nominal instances and
dependent empty-owner readers pass in the 22-law call/host batch and the shared
development family. Actual physics now reaches the existing expression-work
bound; general selected pure call specialization is the next integration slice.
