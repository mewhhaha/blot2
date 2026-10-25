# Zig compiler

The [CT116 frontend update](CT116_QUALIFICATION.md) adds requirement dependency
reuse, immutable imported sharing metadata, indexed inference membership and
four-worker checking of independent fresh modules. `frontendWorkers` /
`--frontend-workers` selects 1–16 workers; retained edits keep their existing
cutoff path. Canonical imported graphs are still copied. The
[root README](../README.md#idiomatic-blot-and-rust-benchmarks) includes eighteen
idiomatic Blot/Rust compile-time and same-engine Wasm runtime benchmarks. CT110
remains installed; preserved concurrent array work is outside the frozen CT116
qualification.

This is Blot's production compiler, written directly in Zig 0.17.0. It owns
lexing, parsing, type/effect inference, staging, incremental revisions and Wasm
emission. It is the only Blot compiler; there is no TypeScript fallback or Bend
runtime dependency. The TypeScript host tools and their Baba formatter parser
are described in [compiler/README.md](../compiler/README.md).

From the repository root:

```sh
deno task build:compiler
deno task test:compiler
```

Without Deno, build in this directory with
`zig build install compiler-identity -Doptimize=fast -Dllvm=true` for a final
release. Development always uses Zig's native backend without LLVM: build with
`zig build install compiler-identity -Doptimize=safe -Dllvm=false --prefix zig-out-dev`.
Run development native tests with
`zig build test -Doptimize=safe -Dllvm=false --prefix zig-out-native-dev`; the
runner sets the fixture working directory. Use `deno task test:compiler:dev`
from the root for Safe/noLLVM development and focused laws. Add
`-Dllvm=false --prefix zig-out-native-dev` to a development
`zig build test-compile -Doptimize=safe` to build the native test binary
separately. Native tests import immutable inputs through the `fixtures` module
rooted at `fixtures/root.zig`; production builds have no fixture-module
dependency. All 126 Blot fixtures and both frozen oracle files live outside
`src/`. Their relocation byte manifest and focused discovery checks are in
`build/bench/finish-rest-20261015/fixture-relocation/`. The full gate still
qualifies the final combined source. For full native qualification,
`zig build test -Doptimize=safe -Dllvm=false
--prefix zig-out-native-dev -Doom-profile=true -Dtest-force-run=true --summary all`
reports allocation-failure sweep timings while running the full suite. Native
unit tests always compile with Zig's backend. The installed executable supports
`--test=EXACT_INVENTORY_NAME`, and records individual durations, leaks, logged
errors and allocation-failure mode as `BLOT_NATIVE_TEST` JSON.
`deno task check:dev --area static-sharing` runs a bounded development family
with sampled allocation faults; full execution remains exhaustive by default.
`--list-areas` also lists syntax, type/effect, retained body-checking,
numeric-aggregate and structured-task families. Use `--area tasks` while
changing task-region, receive and ownership contracts. The full Deno gate
compiles once, then directly launches one to four native shards, verifies every
inventory entry and records their actual overlap. Shard logs and completion
records participate in verified resume evidence.

For smaller native builds, use `-Dtest-suite=syntax`, `types` or `runtime` with
`test` or `test-compile`. The default `all` remains the complete production
suite. `deno task test:compiler:dev --native-suite types` selects a Safe/noLLVM
check. Reserve LLVM for the actual final release compiler and release
performance measurements.

Use `deno task bench:compiler-build --out build/bench/build-next` from the
repository root to measure isolated cache initialization, compiler/native
builds, source edits and reverts. The
[initial build measurements](../COMPILE_MEASUREMENTS.md) record roughly 3.4 s
real compiler edits and a 4.64 s warm development cycle; the expanded
development family below is measured separately. Keep ordinary writable Zig
caches; explicit incremental mode did not improve the measured edit cycle.
[Build hills](../BUILD_HILLS.md) track the remaining iteration and qualification
costs separately from [application compile hills](../COMPILE_HILLS.md).

The [CT110 qualification](CT110_QUALIFICATION.md) records seven alternating
release pairs against CT109 with identical Wasm. Paired CPU improves 2.9% fresh,
4.4% for literal edits and 3.0% for body edits. Shared-host wall medians are
**7.335 / 3.034 / 5.035 s** respectively. Two-second and sub-second ordinary
edits remain open.

Frontend reuse checks one module on the first edit. Shared effect-label proofs,
temporary graph buffers and structural import memoization remove repeated work,
but literal/body inference still opens 2,934 / 7,216 regions. Three expensive
body principals retain dependencies on inferred requirements. Peak RSS is
essentially unchanged. The
[architecture review](../COMPILER_ARCHITECTURE_REVIEW.md) recommends stable
semantic interfaces, reusable elaborated bodies and a cheaper development
specialization policy. These remain proposals. The
[86-item ledger](../COMPILER_CT109_LEDGER.md) keeps partial and conditional work
explicit.

The [CT111 work record](../COMPILER_CT111_WORK.md) records the bounded
follow-up: optional written result requirements, inferred-interface proofs,
retained source graphs, fragment indexing and inference-stage measurements. Its
frozen snapshot passes 2,584 exhaustive native laws, 1,659 release guests, 48
smoke tests and 57 tooling checks. Completed elaborated bodies and the
development generic ABI are still unimplemented; all five architectural
recommendations remain incomplete. The [final screen](CT111_QUALIFICATION.md)
shows no performance improvement; CT110 remains installed.

The [CT112 follow-up](CT112_QUALIFICATION.md) restores completed closure and
capture proofs across exact query replay. Its frozen candidate passes 2,586
exhaustive native laws, 1,660 release guests, 48 smoke tests, 57 tooling checks
and the selected zero-lint development check. Three release pairs report lower
edit times and higher fresh CPU, while deterministic work falls only slightly.
This screen does not establish a repeatable speedup. The installed compiler is
unchanged; the general elaborated-body boundary remains unfinished.

The [qualified CT113 follow-up](CT113_QUALIFICATION.md) adds a bounded request
census and raises the refinement cache to 8,192 records. Three release pairs
measure fresh gdev compilation at 7.55 → 7.08 s (paired CPU -5.2%); literal/body
edits remain about 3.0/5.2 s. It retains about 4.82 MiB more cache storage and
passes 2,587 exhaustive native laws, 1,660 release guests, 48 smoke and 57
tooling checks, plus the selected zero-lint development check. Missing
call-proof provenance remains an architectural bottleneck; unsuccessful recheck
trials were removed. CT110 remains installed.

The [CT114 frontend changes](CT114_QUALIFICATION.md) reduce checking allocation
requests by 27.0% and requested bytes by 17.6%. The instrumented frontend median
is 1.872 → 1.784 s in three alternating pairs; this does not establish an
unprofiled latency improvement. The frozen candidate passes 2,589 exhaustive
native laws, 1,660 release guests, 48 smoke tests, 57 tooling checks and zero
Zig lint findings. The fresh sub-second target remains open. See
[the architecture review](../COMPILER_FRONTEND_REVIEW.md) for the larger
changes. CT110 remains installed.

The matching CT110 CLI and native compiler are installed locally. Its gate
passes 2,576 exhaustive native laws, 1,656 guest checks, 48 smoke checks and 57
tooling checks, with zero Zig lint findings. See the
[development-cycle measurements](../DEVELOPMENT_TURNAROUND.md) and
[measurement tools](../scripts/bench/README.md).

`blotc build ENTRY OUTPUT.wasm --prelude std/prelude.blot --std-root std`
compiles a project. `dependencies ENTRY OUTPUT.blotdep` produces reusable typed
dependencies. `serve-project` serves the framed retained-project protocol used
by [the client](PROJECT_CLIENT.md). The client `inferenceBudget` setting and
native `--inference-budget` option control ordinary inference and associated
work through checking and evaluation. See [budget accounting](PROJECT_CLIENT.md)
and the [associated-work qualification](ASSOCIATED_WORK_QUALIFICATION.md).

The language distinguishes chunked `List a` from contiguous `Array a`. Indexing
and indexed rebinding are array-only. Shared list edits copy the affected tree
path and leaf; proven exclusive end edits reuse storage. See the
[collection guide](../compiler/guide.md#lists-arrays-and-libraries).

Structured tasks support checked ordinary scope wrappers, exact explicit spawn
wrappers through aliases/imports/partial calls, and generic task receives over
one handle or a tuple of up to sixteen handles. Frozen Core validates capture
transfer at the actual spawn call. Collection retains partial results until all
selected tasks succeed or cleanup completes. See
[structured concurrency](STRUCTURED_CONCURRENCY.md) for the implemented
contracts and remaining language/runtime work. The repository
[installation instructions](../README.md#build-and-use) install both the raw
compiler and a CLI containing its matching release binary.

[Architecture](ARCHITECTURE.md), [ownership contract](CONTRACT.md),
[validation and performance](STATUS.md).

The approved `result "member" Input Output` predicate expresses destination
selection in a complete written interface; see the
[qualified bindings guide](../compiler/guide.md#qualified-bindings). Existing
inferred conversions remain valid.
