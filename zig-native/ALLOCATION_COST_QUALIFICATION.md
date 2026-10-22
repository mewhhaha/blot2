# Allocation-cost qualification for issue #17

The source-level report is opt-in: `blotc build-project ENTRY OUTPUT.wasm
--explain-allocations` emits one `array_costs` JSON record after a successful
build. It uses the same Core ownership proof as array-edit emission. The report
locates recognized edit expressions in UTF-8 byte offsets, gives the reuse or
copy-required proof decision and its reason, lists entry sites first, and caps
output at 256 sites with an `omitted` count. It does not claim to count actual
allocations: it examines checked Core edits whether or not an entry reaches
them, and a later Wasm optimization may erase a copy. The executed-Wasm law
checks an exclusive edit and an observed old version at their exact source
spans, compares their allocator traffic, and confirms the flag leaves Wasm
bytes unchanged. The native ownership law includes full allocation-failure
sweeps with explanation enabled.

`zig-native/tests/allocation_cost_matrix.test.ts` runs 100 calls per case and
checks results, rounded arena allocation bytes, retains and releases. The
compiler is the Zig development backend; the `codegenTier` column selects the
guest Wasm optimization tier. These are allocator size-class traffic figures,
not live memory or exact payload copies. The current matrix uses compiler
SHA-256 `41cfde8ea65fe2fc889a55c345c0f46a164f2153d506e0f50e66ebeb0e03c7bb`,
source file SHA-256 `1b1624eed838146f5562fab3ac2d4b52a6c859dec18f3db93d142c3bd797ca6f`,
prelude SHA-256 `677ccf723198511a812a5d7539512253197df9842cd07d1da9749d137262006e`
and `std/array` SHA-256 `1a11c8ef63fc18fec2515889efc8fdf0fa3030db59e061b43f38c8f0ea506be1`.
Reproduce with `deno test --no-config --allow-read --allow-write --allow-run
zig-native/tests/allocation_cost_matrix.test.ts --
zig-native/zig-out-dev/bin/blotc`.

| Source form, 100 calls | Development bytes | Optimized bytes |
| --- | ---: | ---: |
| Direct structural record projection | 4,800 | 0 |
| Separate structural helper | 4,800 | 0 |
| Named callback | 4,800 | 0 |
| Inline callback | 4,800 | 0 |
| Generic callback through `apply` | 4,800 | 4,800 |
| Nominal `#Box` construction and reader | 9,600 | 9,600 |

The generic and nominal rows are current conservative costs, not promises
that all such calls allocate. At this fixture's optimized tier the compiler
eliminates the small structural/callback allocations but retains one rounded
48-byte allocation per generic callback call and two rounded allocations per
nominal call. Development tier retains the structural allocation as well.
Naming the callback does not cause the generic cliff; passing it through the
generic `apply` path does. Those rows identify remaining optimization work.

| Collection form, 100 calls | 32 elements | 128 elements | 512 elements |
| --- | ---: | ---: | ---: |
| Exclusive List append builder | 51,200 | 204,800 | 460,800 |
| Fixed-size Array generate | 19,200 | 76,800 | 409,600 |
| Direct Array indexed update loop | 19,200 | 76,800 | 409,600 |
| Forwarded Array indexed update loop | 19,200 | 76,800 | 409,600 |
| Array update loop retaining old version | 633,600 | 9,907,200 | 210,124,800 |

These collection rows are the same in both tiers. The List builder and Array
generator have roughly proportional allocator traffic across sizes, allowing
for allocator size classes and List leaf growth. The retained-snapshot path
copies a growing full Array on every update and rises much faster. The source
report identifies this as `copy_required` at the edit with reason
`nonexclusive_predecessor`; the exclusive update is `reuse_eligible`. The
compiler guide specifies the exclusive List builder and fixed-size Array
generator as documented construction choices.

The before/after runtime improvement for forwarded collection edits is pinned
separately in `COLLECTION_WRAPPER_QUALIFICATION.md`: the baseline and candidate
compiler hashes, source/prelude hashes, alternating measurements and limitations
are recorded there. This report and its flag add observability, not a new
runtime optimization, so no new speedup is claimed.

Final qualification passed the full compiler gate: 2,506 native tests with
exhaustive allocation-failure sweeps, the LLVM release build, 1,630 guest
tests, packaging and the harness. The native run took 541 seconds with four
shards. A first run reached the harness's 600-second phase limit while one
shard was still active; rerunning the same candidate with a 900-second phase
limit passed. Zig lint reported zero findings, and the two TypeScript fixtures
passed formatting, lint and type checking.
