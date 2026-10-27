# Private ordered static source-to-target experiment

This bounded experiment accepts the existing nonempty tuple-array subset and
runs one compiler-owned `ScheduledWork` in order: retained source/aggregate
and scalar parsing (phase 1), independent source/tree replay (2), scalar
execution (3), explicitly skipped proof phase (4), result shape checks (5),
source/image retention and association (6), and exact target-byte checking
(7). It refuses to publish bytes on a failed phase, semantic ceiling, source
byte telemetry overflow, primitive failure, target telemetry overflow or
source/target mismatch. Success requires the schedule to be complete. The
static primitive-step/byte budgets still apply separately.

The copied scalar and aggregate parsers charge source-byte telemetry before
their explicit source retention copies. The phase-2 verifier checks every
retained scalar tree against the corresponding exact source component rather
than invoking the phase-1 parser from phase 2. The target verifier
independently reconstructs the fixed private module, records one target visit
per compared target byte, and checks exact target bytes; its standalone helper
requires an already source-verified image. The resulting private Wasm module
has unexported static memory and a bounded test read interface.

This is **not a complete C09 receipt or public compiler admission**. It uses a
fixed narrow array subset and the existing scheduler, which checks phase
ordering but does not prove that every possible required visit occurred. The
parser/validator/evaluator include the explicit meters from `static_b` and
`static_ag`; some metadata, implicit copies/allocations, runtime F32 helpers,
output data comparisons/copies, target reconstruction and encoding helpers,
module dependencies, generic types/layouts, proof and resource traversals,
manifest and public ABI work remain unmetered. The target byte counter is
telemetry, not an additional semantic limit. Its meter and initial work state
are compiler-owned test inputs, not authenticated artifacts.

The optimized two-entry aggregate cache is not connected to this ordered path;
there is no cold/cache equivalence or performance claim for this pipeline.
The separate JavaScript index adapter is an instance-isolation model, not
K1's erased `Domain`/`Index` authority. No M12/M13 or complete K1 claim is
made.
