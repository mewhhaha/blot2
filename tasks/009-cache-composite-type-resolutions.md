# 009 — Cache composite type resolutions

## Status, dependencies, and originating requirements

- **Status:** In progress — an isolated dependency-certificate prototype is
  being tested; no production change or completion is claimed.
- **Dependencies:** None.
- **Originating requirements:** PLAN: Hill 5 / solver hot paths. Sources:
  [PLAN.md](../PLAN.md).
- **Execution:** Follow the
  [task order and completion rules](README.md#completion-rules).

## Outcome

Extend dependency-aware resolution caching from variables to composite types
without changing chronological substitution semantics.

## Starting point

[types.zig](../zig-native/src/types.zig) has node-local variable certificates;
[resolution_cache.zig](../zig-native/src/resolution_cache.zig) and
[epoch_resolution_cache.zig](../zig-native/src/epoch_resolution_cache.zig)
support generation checks. Current composite resolution still loses reuse across
unrelated writes; occurs-DAG traversal is already complete.

## Implementation checklist

- [ ] Record the type/effect dependencies of composite answers and validate only
      relevant writes within the correct chronological window.
- [ ] Revoke cached answers on rollback, physical edits, owner/depth changes and
      saturated clocks; distinguish fresh variable/effect identities.
- [ ] Keep certificate metadata solver-local and ensure failed cache growth
      leaves existing answers intact.

## Validation

Use `zig version` before each build batch (Zig 0.17.0). For compiler changes,
run `deno task test:compiler` and `deno task lint:zig` from the repository root
before the local milestone commit. Use the
[shared validation](README.md#shared-validation) commands for focused
development and the scenarios below.

- Compare cached resolution with ordinary traversal over generated histories,
  historical windows, unrelated writes, aliases and shared DAGs.
- Exercise rollback/recycled IDs, physical type and effect mutation, clock
  saturation and allocation failures.
- Measure resolve visits, cold CPU and requested allocation; do not revive the
  previously rejected closed-cache prototype without new evidence.

## Acceptance criteria

- [ ] Composite cache hits survive unrelated writes and every invalidating
      mutation produces the same answer as ordinary traversal.
- [ ] Ownership and OOM laws pass and paired measurements demonstrate the
      retained cache is justified.
- [ ] Applicable checks pass and completion evidence records remaining
      limitations honestly.

## Completion evidence

- Commit: the future-alias correctness fix is qualified independently; the
  composite cache remains unlanded. Its full compiler gate passes the native
  suite and 595 guest/client tests, with zero analyzer findings across 287
  files. The pinned release and logs are in the
  [durable cache record](../zig-native/RESOLUTION_CACHING.md).
- The fix is committed as `8a40c1a`. The later composite candidate removes a
  release-only visit-counter cost and fixes its empty-owner analyzer warning;
  288 files then have zero findings. Seven no-cache pairs still measure 959/971
  ms baseline/candidate fresh CPU, with equal population and edit medians.
  Restart CPU measures 638/659 ms across seven pairs. Its full native suite and
  all 595 guest/client tests pass; the cost still does not justify landing it. A
  bounded warmup admission experiment passes twenty focused native checks and
  the analyzer. Seven pairs measure 943/935 ms cold CPU but 630/652 ms process
  restart, with matching Wasm and lower allocation. That repeated restart cost
  keeps it unaccepted. A later lazy-activation probe passes focused native
  checks and the analyzer. Its seven no-cache pairs measure 947/946 ms cold CPU,
  while restart pairs measure 631/648 ms restart CPU and 983/1,026 ms cold
  population. Byte comparisons pass, but these costs also leave the candidate
  unaccepted. No composite implementation is accepted by those measurements.
- Validation: the isolated fourth candidate passes 55 native resolution and
  ownership laws and 14 executed-Wasm laws. Generated histories, physical edits,
  rollback, future views, saturation and allocation failures are covered. The
  differential comparison passes 305 cases (610 invocations) with identical
  diagnostics and Wasm. The full compiler gate passes the native suite and 595
  guest/client tests. The analyzer found an empty-owner overwrite, corrected in
  the later candidate.
- Comparison: seven alternating pairs measured 944/957 ms fresh CPU, 1,100/1,100
  ms dependency population, 250/260 ms first edit and 230/210 ms subsequent
  edit, baseline/candidate. Fresh requested allocation fell from 321,026,930 to
  320,341,190 bytes. A separate seven-pair restart batch measured 1,042/1,049 ms
  cold population and 640/673 ms process restart. These are loaded-host
  observations, without a compiler-speed claim. Same-compiler and cross-compiler
  Wasm comparisons passed. The later release-counter and ownership correction
  has the cold/restart costs recorded above.
- Remaining limitations: the candidate admits bounded frontiers only in solver
  stores using closed-graph certificates. Ordinary resolution handles larger
  frontiers. No production composite-cache change has landed. The discovered
  future-alias correctness correction is qualified separately in `8a40c1a`.
- Durable record: [resolution caching](../zig-native/RESOLUTION_CACHING.md)
  records the contract, counterexample, rejected candidates, pins and results.
- Isolated work: `/tmp/blot-composite-cache-prototype/` tests bounded
  certificates that retain unresolved type/effect frontiers and revoke future
  variable views when the shared clock advances. It starts from current main,
  not the previously rejected closed-cache implementation. The complete task
  remains open until the remaining correctness and cost gates pass.
