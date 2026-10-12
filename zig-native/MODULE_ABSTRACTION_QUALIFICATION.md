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
