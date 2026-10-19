# Module abstraction implementation qualification

The implementation follows [module abstraction](MODULE_ABSTRACTION.md).
Declarations remain public by default; sparse AST traits add contextual privacy
and opaque declarations without growing every syntax node. Selective forwarding
uses the existing module graph and preserves declaration kind and original
producer. Opaque declarations reuse ordinary constructor checking, matching and
nominal identity; imported semantic catalogs omit their payloads and
constructors.

Editor queries keep source locations separate from opaque nominal name handles;
imported completion exposes neither private names nor representation fields.

An owned compact descriptor supplies exact machine type and ownership, including
variable selection through public structured type parameters. Bounded proofs
check the defining Core payload; unknown/exhausted recipes decline emission.
Scalar/reference wrappers erase to their payload without a tag, cell or extra
reference. Public graph/predicate scans and delayed generic dispatch enforce
privacy before executable emission. No new solver pointer escapes into Core,
public interfaces, storage contracts or artifacts.

Dependency wire version is 2; dependency settings and backend checkpoint
settings are versioned separately. Old schemas rebuild. Principal snapshots
retain positional tombstones for private declarations but remove their names,
type roots, associated members and private parameter patterns. The executable
owner remains available for legitimate specialization. Artifact admission
rejects private promotion, mismatched opaque identity/ABI, duplicate nominal
identities and forwarding to unreachable producers. Failed candidates retain
last-good owners and output.

## Focused checks

Zig 0.17.0 was checked before every build batch. The focused native run passed
37 laws (module abstraction, allocation-budget and editor completion filters),
the LLVM executed- Wasm run passed 31 laws, and the analyzer checked 339 files
with zero findings. The parent owns the mandatory combined full
compiler/analyzer gate before integration; this isolated handoff makes no
full-gate claim.

Focused native laws cover construction, alias/namespace privacy, distinct
producers, forwarding of every declaration kind, public signature/predicate
escapes, fixed nominal name identity, source/compiled ownership, forged storage
contracts and private constructor promotion. Deterministic allocation-failure
sweeps cover decode/validation/re-encoding/relocation and opaque revision
publication; failed publication leaves prior owner pointers, artifact stamp and
revision intact, then succeeds on retry. Existing allocation-budget laws pass.

Executed-Wasm checks cover U32/F32 bits, negative zero/NaN/infinity, generic and
structured parameters, callable constructors, reference aliases/projections,
staged aggregate scalar relocation, scalar-to-reference representation edits
with unchanged public signatures, Foreign callback capture, scalar heap absence,
direct/forwarded source and compiled imports, checkpoint process restart, failed
revisions and recovery. Delayed generic fields and private associated arithmetic
decline outside their producer. Legacy constructor, alias, contract,
shaped-parameter, dependency and checkpoint suites remain exercised.

## Measurements

The release was built in `zig-native/` with Zig 0.17.0 using
`zig build install -Doptimize=fast --prefix zig-out` (LLVM enabled by the build
rules). The incoming release baseline is
`272f028932b0cc563049fe7e5f6f51139304f0ae4cf7213351fd55f5f5f7a127`; the
candidate is `cfafd394694d2394ef299ef9eeab12699949678da5623e5936d3175c67dcfcd6`.

Seven alternating compiler pairs on CPU 6 use `scripts/bench_compile.ts`,
`--workload synthetic --restart-cache --runs 7`. Baseline/candidate and
fresh/retained Wasm are identical; fresh work counters are identical. Median CPU
milliseconds and fresh requested bytes are:

| Workload         | Fresh CPU baseline → candidate | Restart CPU baseline → candidate | Requested bytes baseline → candidate |
| ---------------- | ------------------------------ | -------------------------------- | ------------------------------------ |
| Mono chain 128   | 13 → 14                        | 14 → 14                          | 8,169,536 → 8,178,258                |
| Generic chain 64 | 14 → 14                        | 14 → 14                          | 8,377,859 → 8,378,597                |
| Diamond 8        | 8 → 8                          | 8 → 8                            | 4,169,608 → 4,170,306                |
| Fanout 128       | 25 → 25                        | 25 → 26                          | 16,161,168 → 16,169,866              |

Fresh requested bytes rise 0.009–0.107%; peak live bytes rise 0.007–0.096%.
Retained population/edit median wall ratios span 0.864–1.041; noop medians span
0.415–0.637 ms. Retained CPU ticks are 10 ms, so zero/tied medians do not
establish small gains or losses. Host load was 11.37 → 11.42 while the parent
gate used other cores; these short loaded samples are cost evidence, not a
speedup claim.

`scripts/bench_module_abstraction.ts` compares transparent and opaque F32 sum
and reference alias operations, using 15 alternating pairs, 100 warmups and 64
calls/sample on CPU 6. Scalar median CPU is 83.344 → 83.016 μs/call (paired
ratio median/p90 0.9976/1.0058); reference median CPU is 3.734 → 3.703 μs/call
(paired ratio 1.0000/1.0317). Whole modules differ: 190 → 228 scalar bytes and
3,373 → 3,404 reference bytes. No whole-module parity or runtime gain is
claimed. The scalar no-memory law proves heap absence for that case; exact
operation-body and allocation-traffic qualification across all wrappers remains
task 053.

Raw distributions, source/Wasm/binary hashes and commands are retained in
`build/bench/module-abstraction/{compile,erasure,pins.json}`. Focused commands
are `zig build test -Dllvm=false -Doptimize=safe` with module abstraction,
budget and editor completion query filters; the ten selected executed-Wasm files
run with `deno test --allow-all`; `deno task lint:zig` uses the qualified
analyzer.

## Limits and next qualification

Task 053/024 still owns semantic cutoffs across unrelated private insertion,
private declaration relocation and alpha-renamed parameters. This implementation
keeps exact positional interface/catalog comparisons; such edits may
conservatively recheck callers. The executed edit laws require fresh output and
diagnostic parity, not semantic reuse. Private body changes with an unchanged
public interface still retain ordinary exact executable dependency checks.

Deep, exhausted or unresolved ABI proofs decline emission rather than guess a
machine/ownership type. Forwarding and public scans retain fixed graph budgets.
Namespace-wide exports are outside the reviewed syntax. These limits preserve
language access rules and artifact admission.

The incoming base predates task 032's result roles and root journals. After
integration, rerun the scalar/reference/callback, aggregate and retained
ownership laws against those new result/capture/root-slot rules; this handoff
cannot qualify that later representation by itself.

## Host syntax and editor compatibility

The separate tooling correction updates `grammar.baba`, Baba island metadata and
same-width contextual markers; it preserves private/opaque/export as ordinary
binding and parameter names outside declaration headers. Constructor-pattern
lambda parameters and typed parameters have distinct recognition paths. The
formatter remains unchanged and verifies the resulting CST before publishing.

Run `deno task generate:parser`, then the syntax/formatter tests with the pinned
052 compiler argument. All 14 laws pass, including original/formatted opaque
source and selective-forwarding project Wasm equality, public example/std
formatting, CRLF/origin preservation, contextual names and reserved-marker
rejection. `deno check` and no-config formatting checks pass.

The qualified Tree-sitter 0.27.1 CLI generates from `grammar.js` with ABI 14.
`deno task check:editor` passes four corpus parses, all 14 highlight fixtures
(including 20 new assertions) and public example parsing;
`deno task test:editor` passes six Helix laws. Contextual highlights preserve
bare export/private/opaque identifiers. No generated output was hand-edited. The
input-only patch requires both generator tasks before host/editor validation.

Fifteen alternating CPU-6 formatter pairs on `examples/syntax.blot` preserve
identical formatted text. Median CPU is 41.636 → 49.008 ms; paired median/p90
ratios are 1.0824/1.5455 (host load 4.86). This short screen includes frontend
creation and variable JIT/GC costs; it shows additional host cost, not a
speedup. The generated parser plan grows 726,137 → 780,662 bytes. Native
compiler sources and the pinned LLVM binary are unchanged by this correction.
Raw commands and samples are in `build/bench/module-abstraction/tooling/`.

## Integrated qualification — 12 October 2026

Local implementation `f184dde` jointly qualifies tasks 052, 033 and 038 and
records the reviewed 054 specification. Its staged tree is
`1431522db1bd9b93b1e0b3f3f69949e2122aa5e6`; the compiler source tree used for
the build is `310d60ce85a8ebe26f3c9f4d48fc35811fd98a94`. The intervening changes
correct the raw dependency-header test to version 2 and format two client tests;
compiler inputs are unchanged. The standard Zig 0.17.0 LLVM Fast build has
SHA-256 `5c689ad5caad6952f1c4643f5c40e10d6e41bcf819bf016f751ac105d82020a1`, size
40,838,704 bytes and compiler identity
`bb6bda62bee29cebe741d9f3baf9b8184cc722a1691c109ecc43e1feef2f1ed5`.

The required `deno task test:compiler` passes all 1,400 native laws and 871
guest/client laws. All eight unchanged release allocation budgets pass.
`ZIG_ANALYZER=build/tools/zig-analyzer/zig-out/bin/zig-analyzer deno task lint:zig`
checks 343 files with zero findings. Host syntax/formatter, generated parser,
Tree-sitter corpus/highlights and Helix checks above also pass. Native
deterministic OOM and executed source/compiled/checkpoint laws exercise the
combined representation, roots, callbacks and privacy rules.

The incoming release is the earlier qualified `2798ff9` artifact, SHA-256
`b802365944a69db01df83442db960a8fd7b717828f7cbb1ac5aba2b661d80d17`. Seven
alternating CPU-6 pairs cover all 13 public examples with restart caching
explicitly disabled and checked absent. Public median CPU ratios range
1.0042–1.0292; requested-byte deltas range −312 to +39,350 and peak deltas +376
to +960. Every teardown has zero live requested bytes. No overall speedup is
established. Twelve modules intentionally change Wasm for counted ownership
helpers; the scalar module stays byte equal, and each variant is stable across
its seven repeats. Semantic/prepared counters match except the exact
`requests.blot` allocation-role correction, 19 → 20, caused by proper
Request/Pair reference classification. The harness permits only that change.

Seven further alternating pairs cover four synthetic graphs through fresh,
population, edit/revert, no-op and checkpoint restart. All cross-variant and
within-variant Wasm comparisons pass, including edited output against fresh
edited builds; the harness reports no problems. Median process CPU is:

| Workload         | Fresh baseline → candidate | Restart baseline → candidate |
| ---------------- | -------------------------- | ---------------------------- |
| Mono chain 128   | 13 → 13 ms                 | 12 → 13 ms                   |
| Generic chain 64 | 12 → 12 ms                 | 12 → 12 ms                   |
| Diamond 8        | 7 → 8 ms                   | 7 → 7 ms                     |
| Fanout 128       | 24 → 23 ms                 | 24 → 24 ms                   |

Retained CPU uses coarse 10-ms ticks; tied/zero phases do not establish small
gains or losses. Public load was 4.09; synthetic load was 3.73 → 3.91. A
separate cached public run remains supplemental evidence, not the cold result.
These combined costs do not replace the focused callback improvement or close
the host-call CPU gate recorded in
[suspended ownership](SUSPENDED_OWNERSHIP.md).

Rejected attempts remain separate: `e2492ea4…` failed native compilation at an
incorrect test result field and exceeded the fanout budget by 4,856 bytes;
`bb85a4e0…` passed budgets but failed two of 1,400 native laws. Removing
redundant export producer-name fields restored allocation headroom without
weakening original-target/visibility checks. The privacy gate now permits unused
public lexical-table growth while rejecting private bits in any unmatched tail;
an old local-name fixture now checks its deliberately redacted name by original
binding ordinal. The first final-binary gate passed native laws but failed four
guest assertions expecting dependency version 1. Updating that raw-wire
assertion to version 2 yields the passing required gate above.

Immutable binaries, complete hashes, correction patches, rejected logs,
allocation results and raw distributions remain under ignored
`build/bench/joint-052-033-038-054/`. Accepted evidence is
`qualified/{binary-pins.json,compiler-gate.log}` and
`final/{analyzer.log,budgets-early.log,public-cold/,public-summary.json,synthetic/}`.
Tasks 024/053 still own broader semantic cutoffs and wrapper-operation
qualification; tasks 034/035 own complete cycle reclamation and final tracing
removal. No push or whole-program completion is claimed.

## Current closed-row screen, 19 October 2026

A release screen on the `0f531509…` compiler uses an opaque producer, an
unchanged forwarding module and an unchanged entry, with persistence disabled.
All seven edits match fresh bytes and execute the expected result. The body
control, parameter alpha-renaming and a private record-field rename each reuse
both semantic callers. Inserting an unrelated private declaration before the
opaque type, relocating a private declaration, changing U32 storage to F32, and
changing it to an Array representation still recheck both callers.

| Edit                                     | Intermediate / entry reused | Body elaborations |
| ---------------------------------------- | --------------------------- | ----------------: |
| Private body control                     | 1 / 1                       |                 3 |
| Private declaration inserted before type | 0 / 0                       |                 6 |
| Private declaration moved                | 0 / 0                       |                 5 |
| Parameter alpha-renamed                  | 1 / 1                       |                 3 |
| Opaque U32 storage changed to F32        | 0 / 0                       |                 4 |
| Private field renamed                    | 1 / 1                       |                 3 |
| Opaque storage gains a reference         | 0 / 0                       |                 4 |

The screen is source-only optimized codegen, not the complete source/archive/
checkpoint acceptance matrix. It does not close task 053. Its raw work records
are `build/bench/task053-current-screen/results.json`.

Current cutoff comparison includes positional principal slots and exact external
binding targets, so declaration movement cannot be admitted merely by ignoring
private fields. The backend layout store resolves opaque physical storage
through the current producer modules (`layout.Store.opaque_sources`). That
boundary is relevant to separating semantic equality from changed ABI and
ownership recipes, but any broader reuse still needs fresh-output, changed
storage, failed-publication and allocation-failure laws. Existing guards remain
in force; no screen result is a reason to relax them.
