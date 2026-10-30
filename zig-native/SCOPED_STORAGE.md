# Scoped storage migration

This work changes the original Zig compiler.

The [conversion review](STORAGE_REWRITE_REVIEW.md) and
[implementation tasks](../tasks/STORAGE_REWRITE.md) describe the remaining
greenfield replacement. They are a plan; executable support below remains the
current implementation until those tasks land.

All array literals use `#[...]`; lists use `[...]`. The destination type chooses
an array's length capability:

```text
let fixed: Array U32 = #[42]
let growing: GrowArray U32 = #[42]
let resizable: ResizeArray U32 = #[42]
let empty: GrowArray U32 = #[]
```

An annotation, function parameter or result can provide that context. An
unannotated literal defaults to `Array`. An existing value never silently changes
mode. The earlier `#[>]`, `#[><]`, and mode-bar literal proposals are superseded.
Fixed length does not mean compile-time-known length. Element writes are separate
from length changes. `$` constructors, `#run`, and `#do:` are implemented; `#if`
with selected-branch checking remains planned.

The borrowing spellings are `&T` / `&value` for one value, `&[T]` /
`&items[start..end]` for a range, and `^T` / `^items[index]` for a pool-relative
link. The named types `Ref T`, `View T` and `Link T` mean the same things when not
shadowed by a declared type. Symbolic spellings always select the compiler type;
existing user-defined types named `Link` remain ordinary data types.
Ranges are half-open; their length is a snapshot, so growth does not extend an
existing view. Links retain the target pool identity. None of these values owns
the target or extends its lifetime.

## Executable source profile

`scoped_backend.zig` selects this path for a compilation containing a scoped
storage type or operation. Reached unsupported forms fail before Wasm is
published. Ordinary programs still use the original backend. **The complete
memory-model replacement is not finished:** the new planner is not yet the
language default, and the remaining work below is required before that switch.

The executable path now uses `runtime/data_stacks.zig`. It supports Unit, Bool,
U32 and F32, fixed-layout tuples, structural records and single-constructor
nominal records stored inline in arrays, including positional and named
destructuring. Direct named calls, statically known callbacks, partial
applications and generic call layouts work across source modules. Range/forever
loops currently carry scalars. Blocks, branches and closed scalar `#run`/`#do`
are supported. Records preserve source evaluation order and use UTF-8
field-name order for physical storage. General runtime function values cannot
be stored in arrays or exported as callbacks.

Local scalar demands use invocation-local cache flags and scalar locals. They
evaluate once even when several branches force them, preserving the prelude's
`&&`/`||` short-circuit behavior without heap memo cells. Demands created by an
invocation cannot escape it; aggregate demand results remain unsupported.

The operations remain compiler intrinsics: `@storage.push`, `pop`, `truncate`,
`freeze`, `copy`, `length`, `read`, `load` and `write`. Ordinary indexing reads
arrays and views. Copy creates an independent owner; aliases share explicit
writes. Freeze consumes the length-change capability across every possible
alias while preserving element access. Borrowed arguments to a call are kept
live while its other arguments are evaluated.

Inline record assignment copies the record's scalar fields. An array descriptor
still identifies the same owner: `rows[index].field := value` writes that place
through every array alias. It evaluates indices once, checks the selected
element before the RHS, and preserves sibling writes made by the RHS. The
selected extent cannot shrink during the update. `@array.set` also writes
through its owner. Fixed-array generation, fill, concatenation, append/prepend
and slicing construct independent arrays; generation can therefore express an
explicit snapshot. Array growth itself uses `@storage.push` on a capable owner.

## Application lifetime and host transport

Reachable top-level arrays with literal initializers own permanent slots in
each Wasm instance. Their scalar and inline-record elements survive exported
calls. Initializers publish only after completion; a failed initializer can be
retried. Invocation-local slots are recovered on the next call after a trap.
Computed global initializers and arrays nested in global records remain pending.

Numeric Array U32/F32 arguments, results and ordinary Foreign callbacks use
the existing browser/Pen packet format with independent transport scratch.
Every crossing copies data; no application pointer or borrow is exposed to the
host. JSPI suspension retains the invocation's stacks until settlement. The
guest adapter excludes reentry and disposal while that invocation is pending.
Host exceptions release the invocation boundary for recovery on the next call.

The project service retains complete Wasm output and checks all recorded
inputs before reusing it. Changed source rebuilds the data-stack module; this
path does not manufacture old per-function ownership artifacts or checkpoints.
Pen's normal compiler plugin and native host execute the owned-pool fixture.

The agreed concurrency scope keeps isolated host worker jobs, prepared worker
sessions and ordinary data queues. Language task scopes, spawn, spark/receive,
join and cancellation are excluded from the new model and rejected there.
Their legacy compiler/host implementation still needs deletion as part of
removing the old backend. Ordinary Foreign suspension remains supported.

## Data stacks and lifetime checking

The compiler assigns the lowest available stack slot to each owner. A slot's
addresses never move. Appending extends the initialized extent; there is no
4096-word array reservation and no relocation. Scope exit releases temporary
owners, including on return, loop break and continue. Sequential helper calls
and loop iterations reuse their slots. An owned result preserves its assigned
stack and transfers its lifetime to the caller. Blocks can return arrays and
records, and branches retain every possible root behind a selected value.

The current planner assigns one stack to each simultaneous array owner. Packing
several completed variable-sized values into one data stack is still pending.
Each stack has a 1 MiB bound; Wasm memory is 64 KiB of metadata plus the compiled
maximum stack count times 1 MiB, with at most 255 slots. Initial and maximum
memory sizes are equal. Bounds, arithmetic overflow, overlapping growth and
exhaustion trap before publishing a change. A later invocation recovers storage
after a trap. Generation numbers never wrap; exhaustion traps instead of
reviving an old descriptor.

Borrow admission tracks owner identities through aliases, branch joins,
records, stored elements, known callback captures and calls. Borrowed results
cannot outlive their owners, including references hidden inside returned
records or arrays. Writing a borrow into an older owner is rejected. Owners
returned together in a record are promoted before checking its borrowed fields.
Roots stored in array elements are conservatively joined across writes.

Local use counts allow shrinking after the final use of an element reference
or view. Outer borrows used in a loop remain live across its backedge. Captured
borrows, pending call arguments and borrows stored in live arrays also prevent
shrinking. This is conservative: stored-root history and some caller borrows
remain live longer than strictly necessary. Freeze is likewise conservative
across branches. None of these checks substitutes for immutable Core type
validation; the source body and storage-operation evidence are independently
validated before emission.

The new path contains no counted allocator, retain/release hooks or collector.
The old `runtime/scoped_storage.zig` remains a low-level reservation fixture,
not the runtime emitted for these source programs. The existing
`region_runtime.zig` is a counted-heap optimization; the evaluator's
`region_arena.zig` is host compiler scratch. Neither proves the new source
storage contract.

## Remaining rewrite

The following are not implemented by the new source path and must not be
advertised as complete:

- Variable-sized inline elements, single resizable aggregate tails, nominal
  graph-node layouts, and sequential traversal of variable-sized elements.
- Complete source admission for lists, sum-type patterns, recursive functions,
  all generic layout instances, effects and the remaining collection APIs.
- Computed/global aggregate initialization, aggregate loop carries and the
  complete Ink/Gdev world and component-pool migration. Host packets support
  numeric arrays; arbitrary records and borrowed host pointers are excluded.
- Packing completed values on shared stacks, reusable function specialization
  with destination-stack parameters, and tighter root/last-use summaries.
- Making this planner the default and removing the legacy counted backend,
  followed by full compiler and browser/Pen qualification.

The previous agreed cuts remain: no arbitrary runtime escaping closures,
escaping memoized demands, or general task execution. Unsupported forms produce
a diagnostic, not a counted-heap fallback. The old application storage has not
yet been replaced in Ink/Gdev, and no new gameplay performance claim is made.

## Relative links

Goose's typed relative references are relevant to graph/tree storage:
https://aardappel.github.io/goose/#links-narrower-than-pointers . A link does not
own its target. The containing storage owns all nodes, so graph cycles do not
require reference counting. Pool-relative links need the exact target pool's
identity and lifetime, not just an integer offset. Self-relative links additionally
restrict moving or copying individual records; moving a complete verified image
is a different operation. Neither representation authorizes arbitrary pointer
construction or access to uninitialized/truncated elements.

Wasm32 pointers are already four bytes, so a U32 link is not a pointer-width
optimization on this target. Narrower links and verified image loading are
later extensions. Preserve explicit scope identity and initialized extents in
the foundation so links can build on it without a second ownership model.

## Evidence

Native allocation-failure laws exercise runtime construction, source publication,
inline record layouts, joined roots and immutable type evidence. Executed-Wasm
laws cover growth beyond the old capacity limit, slot reuse across 5000 loop
iterations, overflow/exhaustion, stale generations, stable addresses, inline
records with links, F32 fields, loop exits, owned block/branch results, aliases,
known callbacks, partial applications and borrowed-result rejection.

`deno task check:dev --area scoped-storage` compiles the complete native inventory
and runs this explicit regression family with sampled allocation faults, Wasm
execution and local checks. A development pass is not full release qualification.
