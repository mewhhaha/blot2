# Next compiler levers

This records the investigation at the checkpoint below. See the
[implementation follow-up](COMPILER_IMPLEMENTATION_FOLLOWUP.md) for subsequent
changes and validation.

2026-09-24. Checkpoint **`97e85036ed4f5dab805098d49f933c111735de8c`** retains
the compiler work, tests, laws, proofs and previous investigations. The required
`BEND_NO_TELEMETRY=1 bend PROOF.bend` passed before that commit. All 278
compared source/generated files still matched the previously validated frozen
snapshot; the previous 696 compiler/transformer tests, 24 gdev tests and 104 API
differential operations therefore apply to those unchanged files. This round
used three `gpt-6-sol` agents at `xhigh`, with coordinator review and a separate
name-comparison census. Experiments are isolated under
`build/next-lever-study/`; production compiler and gdev source are unchanged.

## Recommendation

The next large experiment should **evaluate known builder structure before
creating and inferring all its specialized helper bodies**, using retained typed
source bodies and explicit selection/provider evidence. Couple that with
compact, owned inference regions and integer identities. There is now direct
evidence of quadratic clone production in the actual gdev builder, beyond the
earlier synthetic fixed-schema experiments.

There is also useful concurrency hidden inside one serial inference call. A
guarded batch of 88 declarations is a reasonable smaller prototype. Merely
reassigning the current runtime tasks has an optimistic ceiling of about 9% of
pool time in the measured four-worker trace.

No experiment in this round establishes a 100–200 ms full compile. The frozen
installed compiler remains around **1.18 seconds per fresh-process compile
call**, with a warm filesystem. This timing includes frontend preparation,
encoding, transport, native compilation and response decoding; process startup
and project loading are separate.

## 1. Avoid generating a quadratic specialization frontier

The actual gdev builder performs eight snapshot insertions: five resources and
three component registrations. Two helpers, `Entry.contains` and `Type.eq`, each
produce 28 clones. Isolated copies of the complete gdev source with one and two
additional distinct resources establish the scaling:

| Insertions | Checked functions | `Entry.contains` clones | `Type.eq` clones |
| ---------: | ----------------: | ----------------------: | ---------------: |
|          8 |               821 |                      28 |               28 |
|          9 |               854 |                      36 |               36 |
|         10 |               890 |                      45 |               45 |

Both families follow **`n(n−1)/2`**: each new registration traverses the
existing type schema. All three projects pass the generated-JS semantic
analysis, including constant evaluation. These are structural experiments, not
native timings; copied module paths also change nominal identities.

Across the unchanged gdev workload, 12 directly identified builder origins
account for 109 clone names, 209 body-inference entries, and 19,338 of 49,834
recursively counted clone body-node exposures (**38.8%**). This percentage is
not a CPU-time share. The two schema helpers alone account for 56 clones and 112
body-inference entries.

At the end of current compilation, the evaluated `sandbox` is already a finite
value: 18 world cells, 22 scope closures, nine checkpoint closures and ten
system entries. The opportunity is to represent that known structure earlier,
before generic AST expansion and repeated checking have paid for every prefix.

### Architecture and first implementation slice

1. Independently check source SCCs and retain principal typed bodies, deferred
   obligations and exact dependencies. Caller-constrained schemes are not
   reusable principal evidence.
2. Partially evaluate known const construction into typed residual code. Carry
   ordered schema witnesses, world cells, checkpoint actions, system closures,
   lexical provider identities and captured values in a compact representation.
3. Solve concrete nominal/associated/operation choices once and carry that
   evidence into emission and final validation. Unknown values and unsupported
   const cycles use the current path.

Start with the exact checked schema-comparison chain. When its witnesses are
known, select the same branch without inferring each copied comparison helper.
The first success criterion is removal of those 112 inference entries with
matching checked interfaces, constants, diagnostics and executable behavior.
Preserving emitted placeholder functions initially can make exact Wasm parity an
additional guard. Then extend to world/snapshot/provider construction.

Preserve duplicate-registration failure and order, full nominal type equality,
fresh lexical providers, runtime exemplar captures, system order and unused
source validation. A narrow first recognizer must be guarded by exact checked
bodies and catalog dependencies; matching library names alone is unsound. The
long-term design is a general typed partial evaluator, so ordinary user-defined
abstractions benefit from the same mechanism.

The earlier [ECS schema experiment](ECS_SCHEMA_EXPERIMENT.md) already suggested
an explicit schema boundary. Its older 18-cell fixtures measured 460 ms native
CPU for the builder and 370/350/90 ms for progressively more explicit forms;
those fixtures omit most gdev features and use an older compiler. This round
adds the real application value, exact clone origins and the 28/36/45 scaling
test. It proposes a compiler transformation preserving the builder API; it does
not establish a new native speedup or full-application rewrite parity.

Details and reproduction:
[staging report](../build/next-lever-study/redesign/REPORT.md).

## 2. Split the inference work that the scheduler cannot see

In the frozen four-worker trace, 38 fork/join turns occupy 1,157.2 ms. Summing
each turn's longest indivisible runtime step gives 1,056.9 ms. Even perfect
placement of the **same steps behind the same barriers** could remove at most
100.4 ms (**8.7% of pool time**), assuming zero scheduling/merge overhead.
Changing task boundaries or eliminating barriers can change this bound.

One long step includes `sandbox` shared-constant specialization. Its expanded
bundle contains 138 functions and one constant. The declaration dependency graph
has 139 singleton SCCs and level widths **88/25/11/9/5/1**, yet
`Mono.infer_pending` sends the whole bundle to one `G.infer_component` call with
a shared solver state. All declarations form one weakly connected region.

The graph alone does not make the jobs independent. Different callers can
constrain the same pending callee's signature or effect row, and this pass does
not generalize each declaration independently. The narrower first batch has
additional observed evidence:

- The 88 zero-dependency jobs reference no other pending generated declaration.
- All 259 imported ordinary shape bindings are closed or fully quantified.
- The pending declarations' seeded types contain 884 free IDs, with none shared
  between two declarations' own seeded bindings.
- Inferring each of the 88 jobs separately against the actual seeded environment
  succeeds. Their 1,269 new substitution writes touch no other declaration's
  seeded variables and no unowned preexisting variable.

This is a dynamic independence probe on one workload, **not a merged parallel
compiler**. These jobs cover 43.3% of a syntax-cost proxy for the initial shared
inference pass, not 43.3% of compilation time. The dependent 51 jobs and later
selection/rewrite work remain.

A correct prototype needs disjoint fresh-ID allocation or rebasing, preserved
function/catalog context, original substitution and error ordering, and one
final shared solve/generalization boundary. Validate read/write ownership; fall
back or replay on a conflict. The 88 jobs need not be contiguous in declaration
order: stage parallel results, then commit or replay at their original
positions, unless commuting constraints have been proved. Rebase inference IDs
throughout types, rows, obligations and annotations; preserve relocated
expression and choice identities. The current probe checks write keys, not full
read/write conflicts or equivalence of merged results. Include siblings that
require incompatible types or State rows from one monomorphic helper: separate
success must not hide the serial compiler's error. Independent review confirmed
these constraints.

The phase trace also shows higher cost in the shared serial region with four
workers than with one. Its cause is not established; shared ownership overhead
is a hypothesis, not a measured attribution. This strengthens the case for
worker-owned compact inference data when adding concurrency.

Details, exact-output diagnostic and reproduction:
[concurrency report](../build/next-lever-study/parallel/REPORT.md).

## 3. Reuse dependency information and index environments

The generated-JS structural census records 845 dependency-graph builds and
193,973 dependency expression visits, across only 59,229 distinct expression
objects. A memo keyed by exact expression object and traversal fuel hits on
2,892 of 4,633 requests and reduces visits to 67,175 (**65.4% fewer**), with the
exact checked module hash preserved. This is a JS oracle experiment, not a
native speedup.

Repeated graph construction accounts for much of the overlap. Another source is
`G.declaration_bindings`, which rediscovers expression references during
inference even when the checking planner already has them. Reference summaries
should survive with the exact immutable declaration/body they describe.

An isolated Bend candidate threads existing validated dependency nodes through
group inference and reuses the current declaration's reference list. Calls
without such a graph keep the existing scan. This candidate covers a narrower
slice than the broad JS memo: it does not remove repeated `Groups.plan` graph
construction, and finding the declaration's graph node still scans a list.

Five alternating fresh-process native pairs, with one worker and identical
192,168-byte Wasm in all ten runs, give a **negative result**:

| Median metric | Frozen baseline | Reference-reuse candidate |
| ------------- | --------------: | ------------------------: |
| Compile call  |      1,171.5 ms |                1,172.0 ms |
| Native CPU    |        1,140 ms |                  1,130 ms |
| Peak RSS      |      49,444 KiB |                50,464 KiB |

Candidate-minus-control wall differences are −61.6, −22.7, +2.4, +17.0 and +0.4
ms; the early pairs are warm-order sensitive. The 10 ms median CPU change is one
measurement tick. There is no repeatable wall-time gain, so this narrow change
should not be integrated as a performance improvement. The larger JS memo
remains unmeasured natively. Successful code generation and exact gdev Wasm do
not substitute for the full compiler/proof gates for a production change.

Details and reproduction:
[work-reduction report](../build/next-lever-study/work/REPORT.md).

## 4. Replace repeated name comparisons with integer identities

A separate stateless JS census counts **5,230,737 `Model.name_equal` calls**
over only **6,283 distinct string values**, while preserving the exact checked
module hash. Longest compared names are 100 UTF-16 units; there is no evidence
of gigantic structural identity strings in this workload.

Intern names once at the lowered IR boundary. Use `SymbolId`s and indexed
environments throughout checking/specialization, keeping full identity checks at
interning and a reverse table for diagnostics/output. Equality replacement alone
still leaves the same linked-list scans and ownership traffic. This fits the
compact owned-region design from the
[representation study](COMPILER_REPRESENTATION_STUDY.md).

This census does not measure native string loads: native pointer equality can
skip content comparisons. The prior native profile's 10.8% String-equality self
samples are supporting evidence, not a forecast of savings from interning. No
native interning implementation or timing is claimed here.

Details and reproduction:
[name census](../build/next-lever-study/names/REPORT.md).

## Decision

Prioritize a **typed staging and compact inference** implementation slice, with
eliminated helper inference as a falsifiable first milestone. Try the guarded
88-job batch once ownership and merge boundaries are explicit. Integer
identities and direct indexed environments support that representation change.
The narrow graph-reference reuse prototype should be deprioritized after its
negative native result. Further task placement tuning has limited measured
headroom with today's step boundaries.

The previous phase census leaves about 273 ms native CPU even under the
impossible assumption that all specialization and final checking disappear.
Those remaining phases can also improve; the figure is not a lower bound on a
redesigned compiler. It does show why 100–200 ms requires reductions throughout
the pipeline, beyond another local unification or scheduling optimization.
