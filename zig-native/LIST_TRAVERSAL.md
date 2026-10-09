# List traversal qualification

This record preserves the implementation boundary, measurements and remaining
work for packed List traversal. It supplements the public
[collection guidance](../std/PERFORMANCE.md) and the
[ownership contract](CONTRACT.md).

## Direct-loop span check

The List span experiment started from `632b461`, with the task inventory added
at `cb212f4`. It changes only the checked packed-row read in direct List loops.
Other row reads, including cursor extraction, keep their existing checks.

A direct loop resolves a nonempty immutable leaf before reading its row. Its
locals retain that leaf's allocation base, start word and exclusive end word.
The loop already proves that the row starts inside this span. `readListRow`
therefore needs only to check whether the entire row ends in the same leaf. Rows
crossing leaves retain checked per-word lookup. List storage bounds make the end
addition safe from unsigned overflow. The row still receives owned storage; this
change introduces no borrowed interior pointer.

Keeping the span in loop locals matters: a nested traversal can replace the List
descriptor's lookup cache, and a nested collecting loop can move the allocation
frontier. The immutable leaf remains reachable through the List. The span end is
reset each time the source loop starts, including when it is inside another
loop. No library names, user types or source spelling select the optimization.

### Pinned inputs

The ignored prototype remains at `build/experiments/list-span-source/`. Its only
changed existing source files were `src/core_backend.zig` and
`src/collection_tests.zig`; it also added `tests/list_span_execution.test.ts`.
The production port formats the two tests without changing their semantics.

| Input                                      | SHA-256                                                            |
| ------------------------------------------ | ------------------------------------------------------------------ |
| Packed main baseline executable            | `4abce406794c6ce6f6a9cad5e206bc981677205ade5a4b2d8111128d8ac0f1e3` |
| Experimental release executable            | `fb34ef7acf8575feeeb60d03e5b99f5cab3dc5cfb4a3de203c1b583ad0113cf1` |
| Production port executable                 | `034d660ce38691df9a18c895ab228c4d0a76d618aa1969117d16604e06ee2833` |
| Baseline compiler-identity file            | `66ab1d30f803e86341cfae61e41aedc247b6ffe7127f1c707d23e8fb0104853a` |
| Experimental compiler-identity file        | `65674e7fbd1593e5d1e2b5a0029898b3cda55c8542e8c87cc506f06220f147e0` |
| Production port compiler-identity file     | `454c9f8d22559647ee571c274cbbaed9c967ae7c252127f5c64ce32bedc811cc` |
| Experimental `core_backend.zig`            | `a4f33391a7800b22656f8f72271b053dc13828893261f27e389e0e393b6d2f48` |
| Experimental `collection_tests.zig`        | `3135b979fc7c1254e631e9a8a5535bfe360a2d57f4e42395dd754b5db694858d` |
| Experimental `list_span_execution.test.ts` | `07a0682624e3bd4140c27f996545879742518e3238b56c8bf329520c0f4034b2` |

The packed baseline was copied to `build/bench/list-span-baseline/` before the
production build. It matched the main executable at the start of qualification.
These are separate from the older boxed baseline,
`build/compiler-hills/final/blotc`, whose executable hash is
`150c2b032b43490434ba99c0bd91911de4bc8723fa3d4e4cf803d0f8fb88c413`. Its role and
provenance are recorded in the preserved packed-row qualification at
`build/compiler-hills/packed-rows-final/identity.json` and
`build/compiler-hills/qualified-packed-rows/runtime-qualified/report.json`.

### Validation

Qualification uses Zig 0.17.0 and Deno 2.9.7 (V8 15.0.245.2-rusty). Logs, raw
samples, input identities and differential artifacts are under the ignored
`build/bench/list-span-qualified/` directory. No private workload source is
included in this record.

- The focused executed-Wasm batch passed all 17 tests: the new span test,
  packed-row execution and revisions, cursor forks, and collection execution.
  Widths 1–16 include zero, one and two rows; either side of the first leaf
  boundary; multiple leaves; and 1,000 rows. Nested traversals, early break,
  sliced/appended snapshots, F32 values, effects and reference fallbacks are
  covered by this batch.
- The experimental source analyzer checked 285 Zig files with zero findings.
- A differential batch made 610 compiler invocations across 305 fixture/guide
  cases. It compared success, diagnostics, constant steps, code instances,
  deterministic work counters and teardown ownership. There were no semantic
  mismatches. All successful Wasm outputs matched except the guide's loop
  example, which shrank from 5,144 to 5,124 bytes. That 20-byte change is the
  intended direct packed-loop check removal.
- The native filter passed: 16 tests, comprising 15 suite discovery tests and
  `packed List span emission preserves immutable Core under allocation failure`.
  The targeted test uses explicit `@u32.add` intrinsics, so its source requires
  no implicit prelude. It compares the frozen Core stamp after both successful
  emission and the exhaustive failing-allocation sweep.
- All 488 successful differential Wasm modules passed `WebAssembly.validate`.
  Executing both versions of the changed guide module returned 45 for
  `sum_to 10`, 26 for `weighted` and 5 for `first_five`.
- The production source analyzer also checked 285 files with zero findings.
  `deno task test:compiler` passed the full native suite and all 590
  guest/client tests after the production port.

### Runtime measurements

`scripts/bench_packed_rows.ts` used ten warmups and 25 alternating samples for
each compiler. Values and guest-memory page counts matched for every fixture.
The machine was loaded; process CPU is reported separately from wall time.

| Fixture              | Baseline CPU, ms | Span CPU, ms | Baseline wall, ms | Span wall, ms |
| -------------------- | ---------------: | -----------: | ----------------: | ------------: |
| Retained Array rows  |            0.145 |        0.143 |            0.1444 |        0.1411 |
| Retained List rows   |            0.401 |        0.303 |            0.3983 |        0.3004 |
| Retained List cursor |            0.548 |        0.525 |            0.5593 |        0.5222 |
| Generated Array rows |            2.572 |        2.537 |            2.6660 |        2.6053 |
| Comprehension rows   |           20.173 |       20.355 |           24.8836 |       24.9186 |
| Indexed Array rows   |            0.290 |        0.292 |            0.2934 |        0.2979 |
| List round trip      |            4.294 |        4.278 |            4.8381 |        4.9273 |
| Reference rows       |            1.290 |        1.258 |            1.3210 |        1.2859 |

Only the retained List-row fixture changed Wasm, from 5,420 to 5,400 bytes. Its
committed guest memory stayed at 1,441,792 bytes. The measured CPU reduction is
about 24%; unchanged fixtures do not establish additional improvements.

`scripts/bench_runtime_costs.ts` also passed all 13 workloads with each
executable (1,000 warmups, 31 samples of 16 calls). Both compilers emitted the
same module, SHA-256
`a64ee782e4dbc0702495d587206aa55f1ff7995ae83026a787e222601b5a421c`. Requested
compiler allocation was 8,905,356 bytes, peak requested memory was 2,155,291
bytes and teardown live bytes were zero for both. Guest memory matched per
workload. Timing variation for this identical module is not a speedup.

### Compiler measurements and decision

Seven alternating pairs used the frozen 394,294-byte gdev workload. The first
batch enabled an isolated restart cache; a separate batch disabled persistence
for ordinary fresh compilation. Every cross-compiler and same-compiler
fresh/retained/restart Wasm comparison passed without disabling byte checks.

| Measurement                           |           Packed baseline CPU, ms | Span CPU, ms |
| ------------------------------------- | --------------------------------: | -----------: |
| Fresh, persistence disabled           |                               938 |          940 |
| Retained population                   |                             1,070 |        1,070 |
| First retained literal edit           |                               240 |          240 |
| Subsequent edit/revert                |                               220 |          220 |
| No-op                                 | Below 10-ms accounting resolution |           10 |
| Cold cache population, separate batch |                             1,051 |        1,048 |
| Process restart, separate batch       |                               657 |          645 |

With persistence disabled, both requested 321,239,456 bytes cumulatively and
peaked at 78,947,905 requested live bytes. Both had 2,036 inference regions,
8,041 scopes in the largest region, 35,215 constraint visits and 42,410 occurs
visits. Cold cache population requested 386,068,597 bytes and peaked at
125,685,698 bytes in the baseline; cache serialization is additional work, not
ordinary fresh compilation.

Host load was 31–46 on 16 CPUs during the restart batch and 52–34 during the
no-cache batch. These absolute timings cannot replace the earlier qualified
647-ms baseline. No compiler speedup is claimed. Raw records are in `compile/`
and `compile-no-cache/` beneath the qualification directory.

Decision: merge the bounded direct-loop span change. The production release,
native suite, all 590 guest/client tests and zero-finding analyzer gate passed.
The changed guide module and packed-row fixture execute correctly; all other
qualified differential and gdev outputs preserve their required byte equality.
The prototype and its baselines remain available for comparison.

The full read-only List regression remains open. This experiment improves one
three-field fixture against the packed baseline and leaves cursor emission
unchanged. Closing the regression requires paired measurements against the
preserved boxed compiler over every supported row width, with boundary,
snapshot, nested-loop and cursor coverage. Neither this result nor the older
1.9× fold / 1.5× cursor measurements prove that broader gate has passed.
