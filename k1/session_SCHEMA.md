# Private in-process scalar retention fixture

`session_retained.goose` provides actual optional reuse of the private
scheduled scalar fixture. On a cold request it runs `scalar_scheduled::run`,
retains an owned copy of the exact source, generated/checked Wasm, ordered
observations and that successful job's partial work receipt, and publishes a
new active cell. An exact warm request independently rechecks the stored plan
against source and checks every executable Wasm section before returning an
owned copy of the retained bytes. It does not invoke `scalar_scheduled::run`
again. The test checks the compiler-run counter and executes the warm bytes.
The separate `session_target_exact` checker compares the deterministic private
custom metadata bytes exactly, after executable/geometry validation. This
metadata is not authority and neither check authenticates arbitrary Wasm.

Only the trusted compiler may own or access a `Session`. Source programs,
serialized records and external clients must never receive its reference or
write its fields. Goose namespaces have no privacy: this access boundary is a
required integration condition, not language-enforced immutability. The
receipt and target are trusted only because this session created them after a
successful checked run and exposes no mutable lease through its result. An
external claim is ignored and cannot create an entry, supply work counts or
Wasm, or replace fresh checking. On a malformed plan or executable target the
optional hit is declined and fresh code is rebuilt. A disk/imported receipt
therefore never becomes a current-process seal through this API.

The warm target recheck starts from the retained completion meter and records
its added semantic visits separately in `validation_semantic`. Custom metadata
section visits are additionally counted as target telemetry; target-byte reads
and optional plan construction remain incompletely instrumented. If this optional
recheck exhausts the partial meter, the hit is declined and the ordinary fresh
path runs; optional reuse must not reject a valid fresh request. The fresh
retention path derives a plan with an extra unmetered parser pass before its
target recheck, so this telemetry does not constitute complete C09 accounting.

A hit requires exact source bytes, the current fixed semantic-policy string,
and exact ordered positive/negative observations. The trusted query engine
must supply a complete, authoritative observation sequence; this fixture does
not discover module, provider, origin, static or recursion dependencies. The
observations are test data for this private scalar fixture, which has no
imports. Changed positive facts and absent-to-present facts invalidate the
entry. An incomplete or falsely supplied list could cause an unsound hit if a
future caller made this an authority without first building the real query
engine. The fixed source, target, record and observation limits are private
retention limits, not language limits. An over-limit successful check returns
fresh unretained bytes; the caller must use those bytes and cannot treat the old
retained revision as the new result.

The implementation holds two fixed-size cells and writes the inactive cell
before switching the active index. Input failure and three explicit test
interruptions preserve the previously active revision. Fixed cells avoid
resizable clear-before-copy at this publication point, but there is no lock,
concurrent-reader protocol, OS allocation-failure recovery or asynchronous
cancellation mechanism. Goose allocation or stack failure can abort the
process. These tests are not an OOM-atomic or concurrent publication proof.

The saved `ScheduledWork` is an incomplete scalar-fixture work receipt: public
source admission, effects, ownership, proofs, source/target byte telemetry and
other mandatory C09 work are not all integrated. It must not authorize a K1
cache hit or demonstrate full policy-equivalent exhaustion behavior. To reach
that boundary, complete and validate all mandatory charges, seal records behind
an actual compiler-owned immutable lifecycle, authenticate dependencies and
policy/ABI identity, and qualify cold/warm outcomes and fault cleanup. The
current test's forged external cheap receipt with invalid source only checks
that this API ignores the claim; it is not the full SEC-04 exhaustion law.
