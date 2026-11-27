# Standard library performance

Use the [language guide](../docs/language/guide.md) and
[owned-storage profile](../docs/compiler/SCOPED_STORAGE.md) for current contracts.
The rewrite is unfinished: ordinary pure modules can still select ABI 3. Check
the actual guest manifest before attributing measurements to owned storage.
Earlier counted-runtime/List-layout measurements and optimizer details remain in
[the pinned historical document](https://github.com/mewhhaha/squid-lang/blob/4b594a129df6683c900021f355dd771a3de4a311/std/PERFORMANCE.md).

## Collections and ownership

Use `Array a` (`#[a]`) for dynamic contiguous rows and `#[N; a]` when the
length is statically fixed. Current arrays have checked contiguous row storage;
in-place element writes and length mutations (`@storage.push`, `@storage.pop`,
`@storage.truncate`) require unique ownership. Use `@storage.copy` when an
independent snapshot is needed, and `freeze` (`*T`) for O(1) read-only sharing.

Collection-producing helpers may copy substantial rows. Keep input and output
owners' simultaneous live extents within the configured plan. Preserve
overflow, range and lifetime checks instead of increasing capacities to pass a
workload.

`prefix_sums` scans in input order into one independent destination. Array
`indices`, `filter` and `filter_map` append into a local `Array` and return it
directly. `concat` and `flatten` preserve ordering and length-overflow checks.

## Effects and numerical behavior

Folds preserve reducer effects. `any`/`all` stop at the first deciding element;
empty inputs return false/true without calling the predicate. Construction
callbacks retain their documented purity requirements. Known callbacks remain
subject to checked owner and effect evidence.

`Maybe.unwrap_or_else` and `Result.unwrap_or_else` defer fallbacks; `unwrap_or`
is eager. Local supported demands evaluate at most once per invocation. Skipped
work must not introduce effects or traps. Exact support and escape limits are in
the owned-storage profile.

Preserve F32 operation order, signed zero, NaNs, full-width U32 values and SIMD
lane contracts. A vectorized or cached implementation needs independent
numerical witnesses. Do not infer allocation or runtime cost from source
spelling, inlining or a small synthetic fixture.

## Measurements

Qualify correctness before timing. Pair each compiler with its standard library
and record executable/hello identities, source/settings digests, Wasm hash,
actual ABI, host/engine version, workload sizes and measurement boundary.
Release measurements use the qualified release compiler, not native-backend safe
development builds. See
[application qualification](../tasks/121-qualify-and-measure-owned-applications.md).

Keep guest runtime, declared/committed memory, compiler CPU, requested
allocation and process RSS separate. Fixed ABI 8 memory includes reserved
regions; committed pages are not live object bytes or cumulative allocation.
Preserve original warmups, samples, independent references and exact result
checks. Fixture speedups do not establish whole-application speedups.

Retained compilation is a separate measurement from cold compilation. Keep a
project session open across edits; distinguish population, first edit, later
edit, no-op and process restart. Failed edits must preserve the preceding good
revision. Existing benchmark harnesses retain useful workloads, but each result
qualifies its exact backend and candidate rather than the unfinished rewrite.
