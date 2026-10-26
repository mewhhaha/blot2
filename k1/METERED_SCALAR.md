# Opt-in scalar work accounting

This is an intermediate implementation of the work design in `WORK_SCHEMA.md`,
not K1 policy qualification or an admission boundary. The private scalar
`fixture` path uses one fresh compiler-owned meter, while public K1 commands
remain fenced. A meter is mutable state for one declaration; it is never loaded
from a caller, artifact, cache or host.

`frontend::parse_scalar_with_work(source, meter)` charges each nontrivia token
before passing it to the scalar parser and each suite newline used as a
structural delimiter. Blank lines, comments and EOF are not Core or AST nodes
and do not spend the semantic-node ceiling. Source size and UTF-8 are checked
before parsing. Status 12 indicates semantic exhaustion; 13 indicates invalid
internal accounting. `frontend::parse_scalar` remains the compatibility path.
Raw byte-scanning telemetry, including UTF-8, trivia, lookahead and literal
reads, is not yet instrumented. The source-size ceiling still bounds each scan.

`validate::scalar_v2_with_work` independently re-recognizes scalar source and
checks Core with the same caller-owned meter. It charges its meaningful source
token visits in phase 2 and Core-record/value-edge visits in phase 5; empty
fixed slots are bounded representation fields, not Core nodes. Each repeated
validation charges its visits again. It returns 0 for valid, 1 for invalid,
2 for incompatible identifiers, 3 for semantic exhaustion and 4 for internal
accounting failure. The existing `scalar_v2` entry retains compatibility.
`scalar_v2_with_work_at_phase` attributes a repeated required check to the
specified later phase rather than to the original source/Core phases.

The opt-in `parser::parse_with_work` / `verify_with_work` path builds and
independently checks an owned syntax snapshot with the same meter. The
`scalar_core_metered` builder and checker charge bounded Core creation and
validation; `scalar_plan_metered` and `scalar_wasm_metered` charge the private
plan and emission traversals. The separately implemented
`wasm_scalar_validation_metered` checks source, plan, selected geometry and
the actual emitted bytes, recharging required source/Core/layout visits in
phase 7. It tracks parsed target records in `target_visits` separately; those
byte-format records are not silently treated as source semantic nodes.
Its target byte-read telemetry remains uninstrumented. The private scalar
verifier's source-name byte comparison is also not reflected in
`source_byte_reads`. The private scalar
driver connects these APIs as one measured job and does not output bytes until
the independent target verifier succeeds. This does not enable public K1.

`add_source_metered::validate_source` adds the exact `x + 0` source/Core check
to that meter. `add_proof_metered::AddJob` owns both the meter and one-build
control state. Its proof construction precharges the actual four term records,
three evidence nodes and two prerequisite links; revalidation in phases 5–7
precharges every node and prerequisite before inspecting it. Exactly one proof
construction is supported per job; general distinct-term interning is not yet
implemented. The five proof edges stay live until the job is discarded. Its
mutable counters and fixture-local identities cannot authenticate a caller,
source, imported artifact or cross-compile proof. Failed construction returns
no proof; discard the entire failed job rather than resetting its budget.

Focused laws exercise shared exact-at-limit and one-over behavior, repeated
validation, proof-versus-semantic exhaustion, malformed evidence and a missing
charge before a forged prerequisite. Long comments and blank lines verify that
byte count is not silently reinterpreted as semantic-node work. These laws run
at Goose `-O0` and `-O2`.

`work::ScheduledWork` is an opt-in owner with seven ordered phases.
The proof phase can be explicitly skipped; all other phases must be entered
and completed in order. Ordering errors and limit failures make that owner
terminal. Once started, its owned meter checks the active phase for every
`work::charge`, including calls made by existing meter-accepting helpers.
`scalar_scheduled::run` connects that owner to the private scalar parser, Core,
plan, geometry, emitter and verifier. It splits parser construction from its
internal verification so both existing independent checks execute in phase 2.
Tests compare emitted bytes and all phase counts with the compatibility
pipeline and exhaust every semantic budget point; no bytes return on failure.
The private command-line scalar fixture uses this scheduled driver. This
mechanism does not prove that a phase performed all mandatory checks and does
not prevent trusted internal code from altering its in-memory meter.

The separate `proof_scopes::Job` experiment tracks active and peak fact and
prerequisite edges in its own meter. Facts remain live until their scope closes;
children must close first and dependent facts discharge in reverse construction
order. Generation-tagged, job-local handles reject stale and unrelated-scope
references. A fact supports at most two prerequisites. A failed job is terminal
and partial scratch constructions are not published. This is accounting
machinery only: handles are not cross-job or artifact authority. The scoped
checked-add path independently validates its proof and uses this job through
its final consumer; the private add-fixture driver now uses that path. Its
parser and Wasm encoder still perform unmetered work, and it uses a
compatibility meter rather than the phase scheduler. Successful tests do not
establish complete proof accounting.

The separate module, checked-add and control-flow fixtures do not yet use
the scheduled scalar job. Some helpers, type/effect/usage traversal, static evaluation,
source and target byte telemetry, and target encoding remain outside the
partial scalar accounting. The checked-add fixture integrates scope-safe edge
discharge but not the opt-in phase scheduler. No complete receipt, cache
equivalence, fault qualification, required telemetry or public K1 admission is
claimed. The production path must integrate and test each remaining required
traversal before a shared semantic budget can be reported as established.
