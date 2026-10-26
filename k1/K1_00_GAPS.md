# K1-00 and public scalar admission: pending work

**Status: pending. K1-00 has not been completed or qualified.** This document
maps a narrow scalar path; it does not claim the implementation of issue #37.
The normative handoff is [the issue index](https://github.com/mewhhaha/blot2/issues/37)
and its [compiler](https://github.com/mewhhaha/blot2/issues/38),
[execution](https://github.com/mewhhaha/blot2/issues/39),
[language](https://github.com/mewhhaha/blot2/issues/40), and
[memory](https://github.com/mewhhaha/blot2/issues/41) parts. The reviewed
baseline is `1e39b5d8a4268b9edf769c2813d5231abe1c963b`.

The distinction matters: K1-00 calls for a scalar fixture and its specified
admission and corruption tests. A public scalar `check`/`build` path must also
meet the applicable contracts of the other parts. The private fixture and its
test-only exports are neither a completed K1 artifact nor a public host API.
See the current [ledger](LEDGER.md), [prototype contract](CONTRACT.md) and
[fixture README](README.md). Public K1 check/build must remain fenced until
the applicable contracts below are established; legacy remains the default.

## Implementation sequence

1. **Edition and source boundary.** Carry the explicit `k1` selection and
   semantic/optimization/ABI versions in request and project metadata. Reject
   unknown editions and unsupported source before lowering, with no legacy
   fallback. Support an appropriately narrow `pub let` scalar declaration
   with its complete types, effects and finite resource bounds; private fixture
   declarations alone do not define public exports. `check` and `build` must
   agree on admission. Record the supported and deferred subset and the
   operation registry without claiming other K1 operations.

2. **Completion and independent validation.** Construct immutable, owned
   CheckedInterface, CheckedFunction and LoweringPlan records for the supported
   subset, with stable producer/interface identity, selected operation IDs,
   types, effects, explicit exits, resources, required evidence and source
   origins. Destroy or detach mutable completion state before independent
   validation. Validate operands, dominance, types, contracts, resources and
   exact evidence. Do not use a cached success flag as authority. Install the
   downstream general-inference prohibition at its creation seam and test
   creation, active-region balance and completed-region counters. A path with
   no solver should demonstrate that invariant rather than assume it.

3. **Portable headers and ABI identity.** Define versioned, deterministic,
   bounded encodings of the completed artifacts. Check edition, schema and
   policy compatibility and lengths before allocating or following payload
   offsets; independently validate decoded contents. Include exact producer
   identity and semantic/body dependencies. Use canonical numbering, fixed
   endian encoding and sorted external references, with BLAKE3 over canonical
   bytes; keep source origins separate. A digest is not a substitute for
   structural validation. Compute the M10 ABI hash over the versioned
   primitive schemas, layouts, owner/dictionary representations, call
   convention, limits and host wire schema. Require the same hash in the
   interface, implementation, manifest and certificate; bind a separate
   module-geometry hash into the certificate. The experimental
   [SC01](artifact.goose) and [SC02](artifact_v2.goose) containers are not
   completed K1 artifacts.

4. **Required work accounting.** Share a compiler-owned per-declaration
   semantic budget across required AST, Core, type, evidence and other
   specified traversals; separately enforce proof and static limits and report
   the correct exhaustion category. Charge the same logical work on warm and
   cold paths. Work receipts cannot be forged by imported bytes or shared
   across unrelated source owners. The isolated [checked-add proof](add_proof.goose)
   currently meters only its own prototype work; its mutable counter and
   fixed local IDs do not establish portable provenance.

5. **Manifest, runtime roles and certificate.** Build the complete checked
   M03 memory map, including static/dictionary data, control, owner entries,
   bitmap, frame arena, host windows, pool, padding and the one-GiB bound.
   Emit a fixed-size Wasm memory with no `memory.grow`. Establish the callable
   resource bound and export frame preflight before source effects. Validate
   the M13 structural certificate, imports, helper dependencies, operation
   identities and memory accesses; reject legacy managed helpers. The
   fixture's [Wasm encoder](wasm.goose) and geometry metadata are not that
   manifest or certificate.

6. **Scalar exports and publication.** Define and validate the public scalar
   host boundary for checked `pub` declarations. Do not expose the private
   fixture's canonical `(environment, argument)` entry as a public ABI without
   establishing the wrapper and host contract. Once both `check` and `build`
   use the same admitted semantic artifact, enable explicit K1 CLI dispatch.
   Publish files atomically after validation, preserve earlier outputs on
   failures, and reject source/output aliasing. Package a matching executable
   for the installed CLI or keep its explicit unavailable error. The later
   M12 copy-only array bridge and whole-region ownership remain K1-07 work;
   scalar admission must not claim them.

7. **Evidence and gates.** Test the accepted and rejected scalar corpus,
   unsupported syntax, edition mismatch and forged/malformed headers before
   unsafe decoding; run executed Wasm witnesses with optional optimization
   off and on. Record the fixture inventory and required phase trace, marking
   an empty static or optimization phase as skipped rather than implying work.
   Exercise failure publication and actual artifact decoding, and verify the
   structural no-managed-helper certificate. Record exact source and toolchain
   identities and run the repository's required lint and unfiltered compiler
   gate. The [ledger](LEDGER.md#validation-evidence) records the current
   baseline lint failure and incomplete full gate; neither is a pass.

## Questions requiring an explicit resolution

- M12 states that scalar-only exports are the first milestone, but describes
  the array bridge's public wire entry in detail. Confirm the intended scalar
  host-facing entry and validation contract before selecting one; the internal
  callable convention in M10 alone does not establish the host API.
- M12 requires zero padding and permits overlapping input ranges. Clarify
  whether every unreferenced gap/trailing input byte is canonical padding, or
  only representation-required padding; the isolated
  [host bridge planner](host_bridge.goose) currently chooses the former.
- The Goose implementation is separate from the legacy Zig compiler. Adapt
  phase/inference instrumentation and native regression coverage to the actual
  Goose seam while still satisfying the repository's required gates; a renamed
  or unused legacy counter is not evidence for the new path.

These questions do not authorize weakening a normative guarantee. Record a
minimal counterexample and explicit amendment where the specification leaves a
sound representation or boundary unresolved.
