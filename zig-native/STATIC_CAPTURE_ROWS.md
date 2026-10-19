# Stored callback rows in static captures

When a static nominal value stores a pure callback, capturing that value may
instantiate the callback at a wider checked effect row. The evaluator reopens
covariant rows in the stored payload before fixing the nominal argument, as the
checker does for each use. Nominal arguments retain their ordinary invariance.

The fix is in `ClosureRegion.addAggregate` in
[`core_eval.zig`](src/eval/core_eval.zig), implementation commit `f6a2942`.
The executed two-module regression is
[`static_capture_row_execution.test.ts`](tests/static_capture_row_execution.test.ts).

## Qualification, 19 October 2026

The original local Ink `v0`, `v1` and `v3` files were lost. The owner authorized
replacement inputs built against the full Ink ECS library. Their public replay
harness is
[`qualify_static_capture_rows.ts`](../scripts/qualify_static_capture_rows.ts).
Ink is pinned to `1a291a1b90b9197e6a9fc327f52d77bf965d8cf3`.

The candidate is the previously qualified LLVM release from source `e29dd0d`,
executable SHA-256
`0f531509c7316dfb318510c668152f4c2bdbb48d188863f1d4c3d82362823aa3`.
That source's forced gate executed 2,470 native laws with zero skips, failures,
leaks or logged errors, including the nominal invariance laws in
[`types_tests.zig`](src/check/types_tests.zig). Its 1,556 guest/client checks
include the committed static-capture regression. See
[cloud qualification](CLOUD_QUALIFICATION.md).

The control is the exact parent of the fix,
`05401a95c26650af911cb66b94ae1fe97d56eac9`, built with Zig 0.17.0 using
`zig build install -Doptimize=safe -Dllvm=false -j2 --prefix zig-out` and its
own standard library. Its executable SHA-256 is
`b62f5e255a8739652367b17347fa348426c35b7bae40d869c5a58820df6697a1`.
The archived source tree is `37f37b642a4dda1bba8e271fd0a5b05ad68565b8`.

| Replacement input | Pre-fix build | Qualified candidate |
| --- | --- | --- |
| `one_resource` | `effect_mismatch` | Builds and executes |
| `two_resources` | `effect_mismatch` | Builds and executes |
| `snapshot_resource` | Builds | Builds and executes |

Each input passes development and optimized guest code generation, initial,
edited and reverted builds, and byte-exact comparisons with fresh builds.
Reverts recover the initial bytes. All 18 phases execute 103 calls each:
**1,854 checked calls**. The two-resource edit changes the observed result from
9.75 to 10; snapshot calls return the checkpointed input. Every candidate module
has ownership protocol header `[2, 2, 0]`. The scalar guest API reports zero
visible memory; private heap usage is not measured by this qualification.

Reproduce from the repository root, using the pinned control checkout and built
compiler described above:

```sh
deno run --allow-all scripts/qualify_static_capture_rows.ts \
  --before-root build/bench/task108-pins/source-05401a95c266 \
  --output build/bench/static-capture-rows
```

The output directory must be new. The harness records every Ink library and
standard-library input, generated input, compiler and harness hash. Verified raw
evidence is `build/bench/task108-parent-qualified/results.json`, SHA-256
`321975b1024b08c20193250208d8e7e3f3065ee2cb345f5e0403af098dbc7eed`.
The harness SHA-256 is
`14c475eac100f6b7eef07038c6efc577b5d6cec74d8392fa031edac50b85dc75`.

These are recreated acceptance inputs. The missing original files and their
reported earlier results remain historical evidence. Later module-cutoff work
requires its own compiler qualification.
