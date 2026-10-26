# Private retained scalar and observation experiments

These modules exercise pieces of C11 against the existing narrow public-scalar
snapshot. They are not K1 retained-project admission, portable reuse, artifact
storage, a work receipt, or a filesystem/package resolver.

`retained_scalar::attempt` checks source and constructs a fresh owned snapshot
on every request. An optional caller-supplied candidate is accepted as an exact
match only if source, producer tuple, ABI, interface, function, and plan all
match the freshly constructed bytes and its independent source validation also
succeeds. Malformed or stale optional candidates are declined; a malformed fresh
result is an internal error. The scalar Wasm output is regenerated locally and
no externally supplied executable is admitted. This adds no cache speedup: a
candidate cannot avoid fresh work or provide a trusted work receipt.
The negative-only `attempt_untrusted` seam models an imported zero-work claim;
the counters and policy string are ignored, including for an exact candidate.
Its tests supply a cheap-looking claim with both invalid source and a forced
invalid fresh artifact, checking that neither can be published. This is not an
exhaustion-parity test: public-scalar checking has no complete C09 meter yet.

The revision holds one owned snapshot and a generation. Source rejection and
explicit test failpoints before admission, after recognition, after fresh
construction, and before publication preserve the prior generation and bytes.
The corrupt-fresh failpoint simulates an internal compiler defect. The
publication-failure failpoint is checked immediately before mutation. These
controls do not model real process OOM, allocation failure during copy, async
cancellation, host filesystem writes, locking, or concurrent readers. In
particular, the current whole-resizable replacement clears its old contents
before constructing its new copy; do not treat this model as OOM-atomic.

`retained_observations::compare` compares an ordered sequence of positive and
negative observations against caller-provided current facts using exact kind,
key, presence, and value bytes. Interface, body, static value, ABI, capture,
provider, origin, compiler policy, and recursion fact kinds remain distinct.
The comparison declines unsupported or malformed records, ambiguous matching
current entries, changes, byte-work exhaustion, and more than 4,096 logical
candidate/observation visits. It allocates no comparison records. The byte
counter is the sum of compared key/value pair lengths, not actual processor byte
reads. Comparisons have an additional 128 MiB optional byte-work ceiling.

The caller must establish that observations are complete and ordered, that
current facts are authoritative, and that mandatory policy, imported producer,
negative lookup, and resource dependencies are included. Empty observations
are not proof that a reusable artifact has no dependencies. A matching hash
or successful observation comparison alone never admits an artifact. No
producer identity is derived from an untrusted path or cache record.

## Prerequisites for actual source-backed reuse

1. Instrument the whole public frontend and its source, Core, interface,
   proof, effect and resource checks with one versioned declaration-wide C09
   work owner. Today `public_frontend::parse` builds Core and calls unmetered
   checking; `public_snapshot::validate` calls that parser again. The private
   scheduled scalar driver covers a different non-public projection and its
   meter omits required classes of work. Replaying its partial counters for a
   public declaration would make the reported policy and verdict unsound.
2. Seal the completed semantic object and exact required-work receipt inside
   a trusted current-process owner whose records cannot be changed through
   caller-held references. Bind source bytes, producer tuple, edition, policy,
   ABI and ordered positive/negative dependency observations. A mutable
   `work::ScheduledWork`, deserialized claim, candidate digest, or externally
   supplied snapshot must never acquire that authority by matching a header.
3. On a retained hit, compare the complete source and every required
   dependency under bounded optional admission, then use the sealed receipt
   under its exact policy and independently validate structural limits. Any
   required replay or verification visits must still be charged according to
   C09; equal digests are candidate selectors only. A disk/imported claim must
   run fresh required source admission before it can be promoted. A changed
   observation, invalid optional object, unsupported comparison or optional
   cache budget exhaustion falls back to correct fresh work.
4. Keep trusted completed Core/plan separate from executable provenance.
   Rebuild executable bytes from admitted checked input or use separately
   established exact build provenance; structural Core validity cannot
   authenticate caller-supplied Wasm. Test forged cheap receipts against a
   source that exhausts genuine required checking once that source path exists.
5. Stage replacement in separately owned storage with an allocation/error
   interface that can report failure while the old generation remains live.
   Publish one synchronized immutable revision only after every check and
   allocation succeeds. The present Goose whole-resizable replacement is
   clear-before-copy and cannot establish this OOM/concurrency guarantee.
