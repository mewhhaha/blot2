# Implementation declarations and evidence

Task 056 implements the declaration, coherence and selection rules in
[associated contracts](ASSOCIATED_CONTRACTS.md). The combined release gate is
still pending. The earlier isolated development record remains in
`/var/tmp/blot2-implementations-056-port-ec6a2ae`; it is not release evidence.

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
fixture-related checks. These runs do not replace the final full gate.

## Cost evidence

Root evidence is under `build/bench/continuation-20261013/`. The first frozen
candidate is tree `e6706c39d913d1d76054d9b8f43843d239f63865`, with LLVM/Fast
compiler SHA-256
`202857aaf440fa2f65d3fd34c139439318c1a3e83f4ee022fdd644366f9d73ad`. These
measurements describe that combined candidate, including iterator and
scoped-effect changes, rather than isolating task 056.

Seven repetitions cover projection DAG depths 4–64, disjoint heads 8–64 and
prerequisite chains 4–64: 98 successful whole-check samples, all with zero live
requested storage after teardown. Median CPU grows from 0.658 to 6.391 ms for
projection DAGs, 0.616 to 1.759 ms for disjoint heads, and 0.598 to 1.201 ms for
prerequisite chains. Whole-source preparation includes catalog work and is
polynomial; it is not claimed to scale linearly. The prior compiler cannot
accept these declarations, so no equivalent old-feature timing exists.

A separate 98-sample lifecycle run covers both compilation tiers through fresh
builds, body edits, equation edits, failed overlaps, restoration, no-op and
portable restart. Results/diagnostics/bytes match independent fresh builds;
executed answers change between 42 and 43 as expected, and restart loads its
portable candidate.

Thirteen ordinary public programs take 1.004–1.026 times baseline compiler CPU
in seven alternating pairs. The private captured project regresses by about
15–18% in fresh/edit/revert compilation. Profiling attributes substantial extra
work to symbolic effect-row resolution; root is qualifying its correction
separately. No general compiler speedup or final release acceptance is claimed.

## Remaining release work

Freeze the corrected combined source, run the full compiler gate and analyzer,
then repeat affected cost measurements on its exact LLVM/Fast binary. Record
that pin and the final costs here before marking task 056 complete. General body
receipt admission, iterator allocation elimination, scoped capabilities and
tracing removal retain their own task boundaries.
