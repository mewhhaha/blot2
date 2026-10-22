# Allocation-cost qualification for issue #17

The source-level report is opt-in: `blotc build-project ENTRY OUTPUT.wasm
--explain-allocations` emits `allocation_sites` and `array_costs` JSON records
after a successful build. `allocation_sites` maps allocator calls from source
emission back to their responsible expressions; the nominal `#Box` fixture has
both an aggregate and a constructor storage site. They are pre-optimization
candidates, not observed guest allocations, and runtime-helper allocations
without source coordinates are outside this report. `array_costs` uses the same
Core ownership proof as array-edit emission. The report
locates recognized edit expressions in UTF-8 byte offsets, gives the reuse or
copy-required proof decision and its reason, lists entry sites first, and caps
output at 256 sites with an `omitted` count. It does not claim to count actual
allocations: it examines checked Core edits whether or not an entry reaches
them, and a later Wasm optimization may erase a copy. The executed-Wasm law
checks an exclusive edit and an observed old version at their exact source
spans, locates both nominal constructor storage sites, compares allocator
traffic, and confirms the flag leaves Wasm bytes unchanged. The native
ownership law includes full allocation-failure
sweeps with explanation enabled.

`zig-native/tests/allocation_cost_matrix.test.ts` runs 100 calls per case and
checks results, rounded arena allocation bytes, retains and releases. The
compiler is the Zig development backend; the `codegenTier` column selects the
guest Wasm optimization tier. These are allocator size-class traffic figures,
not live memory or exact payload copies. The current matrix uses compiler
SHA-256 `50c8e19291388a008ef51cc4f3793fdaca603080e1c9ebde1dff9123420cb2c7`,
source file SHA-256 `b2142ab06eb796ed5a909509954221ffe76a442161982d950703676b65cb6cfd`,
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
| Generic callback through `apply` | 4,800 | 0 |
| Alias of the global callback through `apply` | 4,800 | 0 |
| Locally bound callback through `apply` | 4,800 | 0 |
| Nominal `#Box` construction and reader | 9,600 | 9,600 |

The global named and alias rows previously allocated 4,800 rounded bytes per
100 calls with development compiler SHA-256
`a362ba461b9ea108b452689a625d7a160d7d2780444e48a5f2e1617531c1e8a6`
and source SHA-256
`93e715f799bb8834cceb40335648472e58b67fa528732501f03e1ba154c83893`.
The new bounded proof admits one direct callable adapter leading to a proved
scalar reader. Two inline steps expose its loads to scalar replacement, so the
same global path now has zero optimized allocator traffic. This is an
allocator-traffic result, not a measured CPU speedup. Development codegen
still retains the structural allocation. The nominal `#Box` path retains two
rounded allocations per call; its constructor storage and aggregate storage
are both reported as source allocation candidates. Dynamically unknown
callbacks retain their conservative call boundary.

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
are recorded there. The source report remains observational; the adapter
inlining change above is separately qualified by allocator traffic, with no
CPU speedup claimed.

The source report was identical across a fresh build and a restarted cached
build of the same fixture. The adapter change passed the full compiler gate:
2,506 native tests with exhaustive allocation-failure sweeps, the LLVM release
build, 1,630 guest tests, packaging and the harness. The native run took 625
seconds with four shards and a 900-second phase limit; the release build took
280 seconds and guests took 40 seconds. Zig lint reported zero findings. The
TypeScript matrix passed formatting, lint and type checking.
