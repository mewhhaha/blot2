# Native core checkpoints

## Recovered remote input

Remote base: `457b7963a96bd1e48d62d83e59b7d4371279e761` on PR #7. The source
archive's Git tree was reconstructed and matched exactly:
`ae9ed76806796f77e25c980e20eb4e2c37015cca`.

The recovered 72-module semantic bridge now builds with OCaml 5.3.0. It is the
complete existing compiler implementation with the native storage changes, not
the completed level-solver / typed-instance redesign. The default Bend compiler
and source semantics are unchanged.

The recovered build passed 985 existing tests, zero failures, two privileged
scheduling skips, and 901 mirrored source operations with no mismatch against
the merged-main Bend reference. These are a fresh validation of the recovered
files, not a reuse of a result from the lost checkout.

## Durable publication

`checkpoint.py` requires committed source and verifies every compiler input, all
generated native modules, and the executable against the build manifest. It
packages source, generated modules, executable, checksums and supplied logs
together. Test outcomes remain in the logs/reports; packaging does not certify
that a failing test passed. `--base COMMIT` adds an incremental Git bundle.

The existing Core checkpoint workflow captures source for every branch push. The
Native typed core workflow separately builds and tests the actual new native
compiler and uploads its artifact even when validation fails. This is distinct
from the inherited Bend-only workflows, which do not validate the native core.

Source snapshots stay in Git; executables and generated code stay in artifacts.
No automatic merge is configured. A session without GitHub write access can
produce verifiable local commits and bundles, but cannot claim remote
publication.

## Type-graph checkpoint

`core_levels.ml` adds the rollback-safe, level-aware checking kernel and an
independent randomized test oracle. It is compiled and tested with the native
core but is not substituted for the existing source inference engine yet. See
TYPE_GRAPH.md for its contract, validation and remaining integration work.

## Integrated graph verification checkpoint

The native executable can now check real source/incremental-session unification
constraints beside the existing solver. It records explicit comparisons and
unsupported/resource-limited cases, and aborts on a disagreement. Counter files
are updated before response publication, so idle process disposal cannot erase
completed evidence. Normal framed output and quiet EOF remain unchanged.

The new graph is still a migration verifier, not the authoritative source
solver. Typed per-expression bodies, instance-driven specialization and the new
semantic dependency/linking pipeline are not implemented by this checkpoint.

## Restorable checkpoints

Packaging and builds share one lock. Each artifact also checks the build inputs
against the immutable Git archive and carries its raw commit object. The
recovery test restores an exact tree/commit and an optional fast-forward bundle,
runs the standalone saved executable, and checks that changed source, generated
modules, executables and dirty working trees are rejected by the packager.

See PROGRESS.md for the final local suite results and the exact boundary between
the verified graph and the still-authoritative compatibility solver.
