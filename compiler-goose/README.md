# Goose compiler experiment

This is a source port of the compiler in `../compiler/`. The Zig source and
installed compiler remain the oracle; the ordinary Blot toolchain still uses
them. `oracle.json` pins the source and executable used for later comparisons.
The remote tag `goose-port-oracle-156f84b` preserves that Zig source baseline.

Every compiler-algorithm module has a first source pass. The complete import
graph parses under upstream Goose; type and lifetime checking are being
repaired. No successful full compiler executable or parity result exists yet.
Recoverable allocation failure and runtime retention/observation also remain
unfinished production requirements.

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
both. Each subprocess stage reports its elapsed time and has a 30-second limit,
adjustable with `--stage-timeout SECONDS`. A timeout terminates the stage's
process group; failed object/link stages leave existing cached objects and the
previous executable intact.
`--identity-only` writes a source-only fingerprint without starting a compiler;
that is not a qualified build identity. Allocation metrics stay null with
`coverage: "unavailable"` until real runtime allocation observations exist.

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

Run the checked engine laws with
`python3 compiler-goose/tools/test_engines.py`. They compile live coalescing, interning, scalar owner-frame and parser sources
to C and execute them using cached runtime/platform objects.
Commands, source hashes and timings are saved under
`build/goose-port/engine-tests/`; these laws do not qualify the whole compiler.
