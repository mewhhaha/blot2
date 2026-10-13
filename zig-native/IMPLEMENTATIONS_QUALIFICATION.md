# Implementation declarations and evidence

Task 056 implements the declaration, coherence and selection rules in
[associated contracts](ASSOCIATED_CONTRACTS.md). The combined release gate
passes at local commit `10fab46`. The earlier isolated development record
remains in `/var/tmp/blot2-implementations-056-port-ec6a2ae`; it is not release
evidence.

## Checked behavior

Contextual `impl` declarations own their explicit parameters, finite heads,
prerequisites, associated equations and ordinary lambda methods. Declaration
checking includes unused members, orphan ownership, visibility and overlap.
Matching chooses a unique head before checking its prerequisites; it never
selects another implementation after the chosen head fails.

Logical given evidence remains principal. Concrete selection owns flat proof
graphs with original producer/member identities, associated substitutions and
method signatures. Exact callback rows survive source and compiled imports;
ordinary larger invocation ambients remain valid. Selection does not evaluate a
method or force its captures.

Portable interfaces use wire version 4. Admission checks binder kinds/scopes,
head and row recipes, complete methods, original producers, visibility,
coherence, proof cycles, method-template schemes and paired synthetic bodies.
Required evidence rejects malformed imports before publication. Optional body
and executable receipts decline incomplete implementation read sets.

Native and client diagnostics share recorded selection facts. They retain at
most four candidate origins, eight explanation steps and 256-byte spellings
within the existing 2,048-byte cap. Private candidates outside the active
context stay hidden. Source-less dependencies retain producer/member identity
and omit unavailable positions. Empty optional fields are omitted consistently
from direct JSON and client-normalized diagnostics.

## Correctness evidence

The isolated port passed 76 native laws, including exhaustive allocation-failure
sweeps, source/compiled operation arguments, private helpers, method callbacks,
owned diagnostics and forged portable evidence. Its final inputs and failures
remain under `build/bench/implementations056/` in that isolated checkout.

Root integration additionally exercises a separately compiled intermediate
facade forwarding an imported generic `ArraySource` and an opaque identity. The
consumer uses the original identities after both producer owners are gone.
Sixteen focused native laws pass. The merged host/editor generation checks pass,
including Tree-sitter corpus, highlights and public examples.

The first combined gate passed all 1,610 native laws, then failed its guest
phase on an existing generic effect-alias regression. A complete guest sweep
also identified an obsolete symbolic-row rejection and inconsistent empty
optional diagnostic fields. Those three failures are repaired. Ordinary guest
preflight then passed 988 tests; 38 fixture tests initially used the wrong
development output directory. The corrected fixture layout passes all 44
fixture-related checks. The final combined gate passes 1,624 native laws, 1,030
guest/client tests and 977 exhaustive allocation-failure sweeps. The analyzer
reports zero findings across 373 files. See the
[merged qualification](CONTINUATION_QUALIFICATION.md) for exact source/binary
pins and the intervening worklist repair.

## Cost evidence

The [merged qualification](CONTINUATION_QUALIFICATION.md) records the exact
final LLVM/Fast compiler, seven-pair distributions, failures and raw evidence
paths. These costs include iterator, body-cutoff and scoped-effect changes.

Seven repetitions cover projection DAG depths 4–64, disjoint heads 8–64 and
prerequisite chains 4–64: 98 successful whole-check samples, all with zero live
requested storage after teardown. Median CPU grows from 0.733 to 6.352 ms for
projection DAGs, 0.728 to 1.831 ms for disjoint heads, and 0.730 to 1.249 ms for
prerequisite chains. Whole-source preparation includes catalog work and is
polynomial; linear scaling is not claimed. The previous compiler cannot accept
these declarations, so no equivalent old-feature timing exists.

A separate 98-sample lifecycle covers both compilation tiers through fresh
builds, body edits, equation edits, failed overlaps, restoration, no-op and
portable restart. Results, diagnostics and bytes match independent fresh builds;
executed answers change between 42 and 43, and restart loads its portable
candidate.

Thirteen public programs take 1.0435–1.0636 times baseline compiler CPU in seven
alternating pairs. Captured fresh/edit/revert paired medians are
1.1164/1.0923/1.0938, with a broad fresh distribution. No general compiler
speedup is claimed. Those regressions remain in task 084's performance scope.

## Remaining boundaries

Task 056 is complete. General body receipt admission, iterator allocation
elimination, scoped capability contracts, constant graph retention and tracing
removal retain their separate tasks. Implementation declarations do not grant
scoped authority or admit incomplete optional receipts.
