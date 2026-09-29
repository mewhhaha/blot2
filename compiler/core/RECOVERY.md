# Native core checkpoints

## Recovered remote input

Remote base: `457b7963a96bd1e48d62d83e59b7d4371279e761` on PR #7.
The source archive's Git tree was reconstructed and matched exactly:
`ae9ed76806796f77e25c980e20eb4e2c37015cca`.

The recovered 72-module semantic bridge now builds with OCaml 5.3.0.
It is the complete existing compiler implementation with the native storage
changes, not the completed level-solver / typed-instance redesign.
The default Bend compiler and source semantics are unchanged.

The recovered build passed 985 existing tests, zero failures, two privileged
scheduling skips, and 901 mirrored source operations with no mismatch against
the merged-main Bend reference. These are a fresh validation of the recovered
files, not a reuse of a result from the lost checkout.

## Durable publication

`checkpoint.py` requires committed source and verifies every compiler input,
all generated native modules, and the executable against the build manifest.
It packages source, generated modules, executable, checksums and supplied logs
together. Test outcomes remain in the logs/reports; packaging does not certify
that a failing test passed. `--base COMMIT` adds an incremental Git bundle.

The existing Core checkpoint workflow captures source for every branch push.
The Native typed core workflow separately builds and tests the actual new native
compiler and uploads its artifact even when validation fails. This is distinct
from the inherited Bend-only workflows, which do not validate the native core.

Source snapshots stay in Git; executables and generated code stay in artifacts.
No automatic merge is configured. A session without GitHub write access can
produce verifiable local commits and bundles, but cannot claim remote publication.
