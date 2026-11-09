# Goose compiler experiment

This is a source port of the compiler in `../compiler/`. The Zig source and
installed compiler remain the oracle; the ordinary Blot toolchain still uses
them. `oracle.json` pins the source and executable used for later comparisons.
The remote tag `goose-port-oracle-156f84b` preserves that Zig source baseline.
Language changes now follow [RFC #46's Zig-first migration](../docs/language/NEXT_MIGRATION.md).
Named module functions are mirrored in the parser and checker sources; only
the parser has executed qualification. The original oracle pin is unchanged.

Every compiler-algorithm module has a first source pass. The complete import
graph parses under upstream Goose; type and lifetime checking are being
repaired. No successful full compiler executable or parity result exists yet.
Native request rollback, staged cache publication and scoped runtime observation
now have component tests. Their complete compiler integration and retained
workload qualification remain pending.

The module map follows the Zig implementation. Goose contexts borrow typed
tables owned by their callers; numeric identities survive growth. Errors travel
as explicit trailing results. Native adapters cover scalar representation and
OS operations, without delegating compilation to Zig.

The target is the same supported syntax and diagnostics, checker/evaluator
behavior, both Wasm backends and reuse behavior. The public `blot-zig-project` server uses
protocol 1; guest session protocol is 2 and the private worker protocol is 2.
Guest ABI 8 and existing storage budgets remain the owned backend contract.

`source-correspondence.json` inventories the pinned native source and records
writing status. `port-notes/` contains the owners' exact remaining scope and
shared constructor contracts. See [the compilation frontier](port-notes/compilation.md)
for current checks and remaining build work.

The native entry is now source-written in `src/main.goose`, with concrete CLI
pipelines and process worker dispatch under `src/driver/`. `build.py` regenerates
`src/source_identity.goose` from the actual Goose sources, native host support,
build options, selected Goose/C compiler binaries and emitted Goose runtime.
Actual builds require `--stdlib` and fingerprint that selected tree. Additional
package trees can be pinned with `--resource-root`. It emits C
with a C-host header and links the ordinary Goose runtime plus the scalar/OS
adapter; it never invokes the Zig oracle. Reusable runtime and platform objects
are keyed by their actual source text, C compiler and flags.

The first build exposed source syntax failures. Those parser failures are
repaired; full compilation remains in progress. The build entry is `python3 build.py --goose /path/to/goose --cc clang --stdlib /path/to/stdlib`.
Development defaults to Goose `-O0` and C `-O0`; `--release` selects `-O2` for
both. Each stage saves a log and timing receipt and has a 30-second default limit,
adjustable with `--stage-timeout SECONDS`. `--total-timeout` caps the whole
attempt at 300 seconds by default. Failed emission stops three seconds after
its first diagnostic. Cancellation terminates the process group; failed stages
preserve existing cached objects and the previous executable.
`--identity-only` writes a source-only fingerprint without starting a compiler;
that is not a qualified build identity. Active payload, retained pool capacity and scratch metrics stay null with
explicit unavailable coverage. The optional private `--runtime-observer` build
reports pool operation totals and virtual region reservations separately.
[The component receipt](../benchmarks/evidence/qualification/2026-11-08-goose-runtime-observer.json)
pins the hook coverage and tests; these counters are not current live memory.

An optional private bootstrap-checker experiment is reproducible with
`python3 compiler-goose/tools/build_goose_checker.py`. It requires the pinned
sibling Goose source/build and Clang 23.1.4, copies and patches privately, and
prints its cached binary path as JSON. Pass that path explicitly to `--goose`;
the installed compiler and ordinary toolchain remain unchanged. The default
cumulative expansion bound stays 100,000 cloned nodes. The explicit
`--expansion-node-limit 1000000` candidate raises that bound for this large port;
the separate tail-shape traversal bound stays 100,000. Its measured
improvement is for an older failing prefix, not completed compiler builds; see
the compilation frontier for exact evidence and limits.

Batch production diagnostics with `python3 compiler-goose/tools/check_engines.py`.
It checks five real entry paths in parallel (`--jobs N` controls concurrency),
collecting independent frontiers in one pass. `--engines check lower` selects a
subset. The diagnostic tool is built automatically when absent; its explicit
partial mode emits no compiler and never replaces the normal full build gate.

Run the checked engine laws with
`python3 compiler-goose/tools/test_engines.py`. They compile live coalescing, interning, scalar owner-frame and parser sources
to C and execute them using cached runtime/platform objects.
Commands, source hashes and timings are saved under
`build/goose-port/engine-tests/`; these laws do not qualify the whole compiler.

Private build experiments are opt-in. `--reachable-program` skips standalone
checking of unused Goose bodies while preserving signatures, externs, executable
roots and final lifetime checks. `--stable-closures` reuses successful complete
type-graph walks; cold synthetic queries regress 2.54x, while descendant reuse
improves. No completed compiler speedup is claimed. `GOOSE_CHECKER_PROFILE=1`
reports phase and cache work. These modes preserve installed/sibling tools.
