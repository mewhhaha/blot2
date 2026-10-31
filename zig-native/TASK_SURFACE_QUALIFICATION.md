> Historical language-task design/qualification. The greenfield owned-storage
> model retires this surface. Do not implement the remaining task roadmap or
> restore task adapters; use copied-packet host workers instead. Current work is
> in [the storage rewrite](../tasks/STORAGE_REWRITE.md).

# Task surface qualification, 23 October 2026

This continuation of `87ba3f6` implements ordinary scope wrappers, exact
explicit spawn wrappers and task tuple collection. It does not complete
[issue #25's remaining program](../FINISH_PLAN.md).

## Qualified behavior

Spark group selection happens during checking and follows the exact group
binding, including when its spelling is shadowed. Ordinary scope callbacks
have a once, universally quantified region contract. Aliases, renamed imports,
curried wrappers and identity forwarding preserve that contract.

An exact `func group => return func action => return @task.spawn group action` helper preserves
its checked contract through aliases, imports and stored partial calls. The
completed call checks the actual action's captures against its selected group.
Its private partial-call representation is not a general indirect callable.

`|(first, second)|` collects task results in written order. Stored tuples and
direct generic receive helpers preserve the same behavior. A task returning a
tuple retains its ordinary payload. Admission establishes the complete set of
dependencies before execution. Partial results and resource journals remain
owned until every selected task succeeds or cleanup releases them. The
compiler supports one to sixteen handles per tuple; the host bridge separately
bounds untrusted ABI counts at 4096.

The regressions cover source and frozen Core admission, capture transfer,
affine consumption, region escape, retained edit/revert behavior, runtime
ownership and both synchronous and JSPI execution. Existing higher-rank,
checkpoint and persistent-demand tests also run unchanged.

## Verification

The complete gate passed in 658.68 seconds. All 2,536 native tests executed
with exhaustive allocation-failure sweeps in four shards, with no skips,
failures, leaks or logged errors. The release guest/client suite passed 1,645
tests, alongside 48 smoke checks, 54 harness checks and 15 preflight regressions.
The same 1,645 guest/client tests also passed against the development compiler.
Zig analyzer reports zero findings across 517 source files plus the fixture
module. Repository TypeScript checks, formatting and all six editor tests pass.

The LLVM release build took 197.43 seconds, native execution took 582.65
seconds and the release guest suite took 25.33 seconds; release compilation and
native execution overlapped. These are qualification timings, not a performance
comparison.

[Raw evidence](measurements/task-surface-2026-10-23.tar.gz) includes the final
gate, native shard records, JUnit reports, source and executable hashes, lint
and TypeScript results, installation checks and the earlier failed gate log.
Archive SHA-256:
`e8ac799c934c791e1ad853c21d10333416655ce8ee3ca23b3bacc756882c2db6`.

The final gate uses Zig 0.17.0 and Deno 2.9.7. Native tests compile with
Safe/noLLVM; the release compiler uses LLVM. Each build batch checks
`zig version`. The gate command is:

```sh
deno task test:compiler --resume --native-shards 4 \
  --budget-seconds 1800 --phase-seconds 1200 \
  --preflight zig-native/tests/task_surface_execution.test.ts \
  --preflight zig-native/tests/demand_completion_execution.test.ts \
  --preflight zig-native/tests/quantified_execution.test.ts \
  --timings-dir /absolute/path/to/task-surface-release-frozen-20261023
```

This host uses writable `ZIG_GLOBAL_CACHE_DIR` and `ZIG_LOCAL_CACHE_DIR`
directories under the repository's `build/`. The command runs from
`build/qualification-snapshot/blot2`: compiler sources are linked to the same
checkout, scripts and package files are identical copies, and the sibling gdev
corpus is a frozen copy of 78 `.blot` files. The archive records those files'
hashes. It does not redistribute the private application sources.

## Local installation

The verified release is installed as `~/.local/bin/blot` and
`~/.local/bin/blotc`. The CLI embeds its matching native compiler, parser,
standard library and language guide. The packaged compiler's decompressed hash
matches the standalone native executable. The previous installed binaries are
preserved under `build/install/previous`.

Both the staged and installed CLI pass an out-of-checkout check of the embedded
guide, formatter, standard prelude and the README's task example. That example
returns 42 in synchronous and JSPI guests. The raw native compiler also builds
the example and produces 42. See the
[installation commands](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/README.md#build-and-use).

## Repairs during verification

An early candidate tried to map all stored callback rows against a consumer's
layout. The existing checkpoint allocation-failure regression rejected a pure
implementation under a wider consumer row. The persistent-demand guest checks
also exposed an incompatible duplicate effect-row mapping. Static row inference
is now restricted to the task scope callback types that require it, and returned
function rows retain their existing covariance rules.

Applying the whole contextual function constraint before closure certification
changed an existing universal-function error from `rank_mismatch` to
`type_mismatch`. Certification now resolves only the contextual effect row at
that point. The established rank validation and diagnostic remain intact.

Another native run completed every test but was invalidated because the sibling
application changed during execution in another thread. That run is not final
qualification evidence. The final gate uses the frozen corpus described above.
The isolated checkout initially used linked package configuration and standard
library paths; package-boundary tests correctly rejected that arrangement.
Identical local copies restore the ordinary package layout.

No expected diagnostics, runtime assertions or allocation-failure sweeps were
weakened to make these checks pass.

## Remaining scope

Implicit caller-region propagation, general higher-order spawn forwarding,
nontrivial generic receiver bodies, streams, select-one receives, channels,
scoped nonlocal exits, purity certification and CPU worker transport remain
unfinished. Iterator and compiler performance targets also remain open. This
record makes no new application-performance claim and closes no upstream issue.

See [the language guide](https://github.com/mewhhaha/blot2/blob/e2fbe95b4ece3e2d4fd442d95274bb6156815705/compiler/guide.md#structured-tasks),
[the task contract](STRUCTURED_CONCURRENCY.md),
[the task ABI](https://github.com/mewhhaha/blot2/blob/4b594a129df6683c900021f355dd771a3de4a311/compiler/guest-abi.md#structured-task-extension) and
[the continuation plan](../CONTINUE.md).
