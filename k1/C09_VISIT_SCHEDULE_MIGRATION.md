# Private scalar work schedule correction

This is an experimental accounting correction, not a new K1 semantic policy
or a complete C09 receipt. The supported public semantic identifier remains
`K1-SEM-POLICY-1`. Public K1 admission remains fenced.

The previous metered `syntax::validate_impl` charged a node and its parent
edge, then read the parent node without a second node charge. The correction
charges that referenced parent node before its dereference. It leaves
`validate_budget`'s unmetered compatibility model unchanged. For the source
`let f: U32 -> U32 = fn x => return x\n`, the existing private scheduled
fixture reports 815 semantic visits; the correction reports 827. The 12 added
visits are six parent reads in each of two required syntax validations. A
remaining budget of 815 visits changes from success to `k1_semantic_limit`;
827 succeeds and 826 fails with no output. This is a correction to an
undercount and an observable source-budget change near the existing limit.
Do not call it receipt-preserving or publish it silently under a stale key.

The private scalar traversal schedule is marked as `2`
inside the trusted process. This number identifies an implementation schedule;
it is not a normative K1 policy, versioned artifact schema, proof, public API,
or authority from source/host data. `session_retained::Entry` records the
revision only when a newly compiled job completes, and a warm hit must match
it exactly. Missing (`0`), old (`1`) and unknown schedule IDs all decline the
optional hit and recompute fresh source, while keeping the normative policy
identifier unchanged. The tests create a structurally plausible 815
visit historical receipt and show it cannot hit a schedule-2 entry; fresh
recompilation gives 827 visits. The version field alone is not an integrity
seal: `Session` and its entries are mutable Goose data and must remain owned by
trusted compiler code. It must not be accepted from a serialized cache,
caller, artifact, or untrusted receipt. There is currently no persistent or
cross-process C09 receipt here, so there is no existing persisted cache format
to migrate; imported claims remain ignored.

Before extending this to real reusable records: freeze a reviewed event
catalogue and schedule identity for every declaration kind, not merely scalar;
key actual cache records by full compiler-owned policy, implementation schedule,
source/dependency and ABI identities; exact-match dependencies and observations;
refuse unknown/legacy/malformed records without interpreting their counts;
recompute source using a fresh owner when no authenticated current receipt
exists. A hash is only a lookup candidate. Optional cache validation exhaustion
must fall back to fresh checking without changing the source verdict. Test
cold/warm, tiers, worker counts, cancellation and last-good-revision retention
under both acceptance and exhaustion. Never rewrite an old total as a new one.

Interpretation of node and edge inspection needs independent policy review.
The current prototype copies a whole node when its node charge succeeds. For
this experiment, reading stored scalar fields, including checking whether an
optional edge is present, is part of that node inspection. Validating or
following a represented parent/reference/target is an edge inspection and
must happen after its edge charge; dereferencing a different node requires a
separate node charge. This is a proposed private interpretation, not a claim
that the project's eventual C09 wording has already frozen it. Malformed
arenas still have unresolved edge-visit and diagnostic precedence:
`syntax::validate_impl` charges target edges based on node tags, and
`parser::exact` uses expected rather than represented links. Review and test
these cases before claiming an exact represented-edge schedule.

Source-byte work is a separate unresolved telemetry problem. UTF-8, token and
trivia scanning, parser recognizers, source/name comparisons and target-name
verification currently omit byte reads. The source size remains bounded at
16 MiB. Instrument actual logical byte inspections including lookahead,
short-circuit behavior and repeated passes with checked `u64` overflow and
per-phase attribution; do not charge one semantic visit per byte or create a
new input-size limit. A proposed optimized implementation may batch local
telemetry increments only if it proves exact totals, overflow-before-read
behavior and identical diagnostics. Measure its overhead against the existing
cold/warm full compiler corpus after correctness is established; no performance
improvement or full-compiler comparison follows from this prototype.

Focused tests: `schedule_v2_test.goose` and
`schedule_cache_test.goose` at Goose `-O0`/`-O2`, plus existing
`parser_work_test.goose` and `scalar_scheduled_test.goose` at both levels.
These are focused private tests, not full K1 or performance qualification.
