# Frontend architecture toward one second

The later [CT115 module census](COMPILER_BIG_LEVERS.md) sharpens the order of
work: `game.blot` accounts for 34.5% of checker CPU and 91.5% of selected
generic requirement candidates. Investigate repeated generalization along its
builder chain first. Four modeled module workers reduce checking from 1.30 to
0.80 s, but leave the whole frontend around 1.24 s; this is a scheduling
estimate, not an implemented speedup. Direct immutable imports remain a separate
target.

The first CT114 changes reduce temporary allocation and remove unused sharing
analysis. They leave the main algorithms intact. The sub-second target needs
less repeated semantic work, not a replacement parser. See
[the implementation record](COMPILER_CT114_WORK.md) and
[phase measurements](COMPILE_MEASUREMENTS.md).

Zig is the only compiler. Baba serves the TypeScript formatter and derive source
generator. The native frontend already spends only 36 ms lexing and parsing the
measured gdev project. No syntax change is proposed here.

## 1. Instantiate directly from immutable producer interfaces

Today `check.zig:importScheme` recursively imports shared callees, freshens all
scheme variables, copies the type/obligation graph, and recomputes its sharing
summary in each consumer. `instantiate` or `shareScheme` subsequently freshens
the imported scheme again for an actual use. The first copy also happens for
imports that this consumer never directly reads.

Across 189 modules, the counters record 90,541 imported schemes and 7,089
directly read imported bindings. Header preparation takes 28.1% of sampled
project-check CPU, including 23.2% in scheme import. These inclusive shares
overlap. Unread bindings are not automatically unnecessary: transitive shared
callees, dispatch, coherence and published aliases also consume their facts.

Change the representation so an imported binding initially names an immutable
producer interface and a binding ordinal. Instantiation reads that producer
graph and creates only the consumer's private type/effect variables and needed
constraints. Keep exported alias identities and catalog/coherence lookup
available without copying every scheme into the consumer's mutable store.

```mermaid
flowchart LR
    A[Check producer once] --> B[Owned immutable interface]
    B --> C[Consumer import handle]
    C --> D[Actual use or semantic demand]
    D --> E[Private consumer instantiation]
```

The producer should also publish public-variable and requirement membership as
positions in its quantifier lists. The current frozen principal interface does
not carry `SchemeSummary`, so consumers reconstruct this analysis. A portable
summary needs exact validation at the package boundary; arbitrary stored flags
cannot authorize sharing. Keep ordinary recomputation available when a complete
summary is absent. Changing a serialized interface requires a format/identity
change and restart-cache rejection laws.

This must eliminate the intermediate copy. Deferring identical copies until
lowering or freezing only moves the clock. Start with ordinary value imports,
then shared callee references and catalog members. Continue checking every
source declaration, including unused ones. Preserve alias provenance, private
quantifier identity, associated-method priority, effect labels, diagnostic order
and recursive component boundaries. Separate mutable solver ownership from
immutable module leases rather than borrowing a producer solver.

Measure producer graph nodes, consumer materialized nodes, transitive demands,
and public-summary imports/recomputations. Compare whole-frontend CPU and
memory, not only `collectModuleHeaders` time.

The existing `SchemeInterface`, `Callees` and `F.Source` readers already
describe producer graphs from live checked modules and frozen interfaces. Reuse
that boundary. The representation change belongs at `Binding`: distinguish a
local solver scheme from an external interface handle instead of assigning every
external binding a local `T.Id`. Route `instantiate`, `shareScheme` and
`expandUse` through that distinction. Shared callee identities need producer
unit/binding relocation at demand, with stable handles for transitive callees.
Audit all consumers of `Binding.ty` and `Binding.scheme`, including retained
body capture, lowering and freezing, before enabling the path. A zero
placeholder that later code treats as a real type would be an unsound shortcut.

Start with a private differential execution option for ordinary imports. Compare
the original and direct-instantiation paths on independent generic uses, effect
rows, aliases, recursive modules, rejected revisions and allocation failures.
Require fewer total materialized nodes and copied bytes across the entire
frontend before extending the representation to shared callees and catalogs.

## 2. Maintain requirement dependencies while checking a body

The current generalizer scans 3,421,572 pending positions across 9,281 schemes.
It selects 641,867 requirements and asks about 1,929,526 type components, each
through separate type-variable and row-variable discovery. Generic scheme
construction accounts for 27.1% of sampled checker CPU, with candidate analysis
at 23.9%; these overlap.

A small cache keyed by current numeric type root does not solve this. The
rejected CT114 trial hits 161,744 times but saves only twelve graph visits. Most
useful queries arrive at different roots or changed histories.

Represent each pending requirement once, with its type/row dependency frontier
and a generation. Index requirements by owning declaration and lexical scope.
Type/effect writes mark only affected requirements dirty; local generalization
uses the current dependency component instead of rediscovering every pending
requirement's variables. Existing solver worklist techniques are a starting
point, not an authority to reuse a stale answer.

Preserve chronological views: dependencies include lower-bound cursors,
unresolved row tails, operation arguments, associated equations and future clock
observations. Rollback must revoke watches before IDs are recycled. Process
ready requirements in the existing source order so failure diagnostics and
left-preferred dispatch remain stable. Local polymorphism and computed-value
restrictions still need their answer before subsequent uses; delaying every
decision until the end of a module would change inference behavior.

Measure distinct requirements, dirty recomputations, frontier updates and peak
watch storage. Require reduced graph visits on real edits and fresh builds;
another large cache with mostly trivial hits is not an improvement.

Use one explicit dependency-query contract before introducing persistent
watchers. The existing type-variable traversal first resolves a graph, whereas
the row-variable traversal walks historical `(node, cursor)` views without
materializing normalized copies. They also enforce projection and depth budgets.
Combining their loops or identifying answers by a raw node ID alone is not a
valid simplification. A common collector must preserve both observations,
operation-instance dependencies, result order and limit behavior. Benchmark a
single-generalization version before retaining its dependency state across
solver writes.

## 3. Construct and validate immutable frontend output once

The starting release profile spends 138 ms lowering, 82 ms freezing and 112 ms
validating. Freezing requests about 203 MB over 769,000 allocation requests;
these are traffic counters, not retained bytes or RSS.

Review the boundaries between owned checked bodies, Core construction and frozen
interfaces. Reuse immutable module data through explicit leases, and combine
structural construction/validation where the builder can establish the exact
invariant while producing a table. Preserve semantic, capability and proof
validation; it is not interchangeable with an index-bounds check. External
packages and restart archives still require full admission checks. Internal
validation receipts must come from an owning constructor, never an unchecked
caller flag.

Measure bytes copied by each boundary and the number of validations of each
immutable object. Reject changes that merely transfer work into backend
preparation or retain obsolete solver histories.

## Measure the dependency critical path before adding module workers

`project_check.zig` currently calls `checkOrdered` serially in dependency order.
The four codegen workers used by the benchmark do not parallelize this loop.
Independent module checks are another possible latency lever once producer
interfaces have clear immutable ownership.

CT115 now records per-module CPU/wall cost and dependency edges: 189 modules,
1,604 edges and a 24-module critical chain costing 797 ms. Four modeled workers
take 798 ms; eight take 797 ms. The nearly saturated critical chain makes
reducing `game.blot`'s 447 ms check more valuable than adding further workers.
See [the model and assumptions](COMPILER_BIG_LEVERS.md). Shared-state isolation
and real scheduling overhead remain unmeasured implementation work.

The current engine shares the symbol pool, resolution/associated budgets,
diagnostic order and retained-revision publication. Worker isolation must
account for all four. Keep deterministic publication and first-diagnostic
behavior, and do not grant each worker a fresh copy of the project's inference
budget. Profile counters would also need worker-local collection and merging
after join; the present thread-local phase profile measures the serial
coordinator. This is a conditional architectural option, not an implemented
speedup or a reason to postpone eliminating repeated work.

## Acceptance

Use the same frozen source manifest and exact Wasm pins. Separate fresh process
builds, ordinary edits, reverts, rejected edits and restarts. Run the native
ownership/allocation laws and executed-Wasm regressions, including independent
generic uses, effect rows, recursive imports and stale-interface rejection.

Target less than 1,000 ms for the complete fresh frontend, not just parsing or
the checker. Report instrumented phase clocks separately from alternating
unprofiled whole-build CPU/wall measurements: reducing allocations also reduces
profiling overhead. Keep a small-project control and bounded retained memory.
The original 1.678 s phase profile would require checking near 599 ms if every
other phase stayed fixed. Those numbers are a target calculation, not a forecast
for the proposed architecture.
