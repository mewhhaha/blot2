# Goose compiler experiment

This is a source port of the compiler in `../compiler/`. The Zig source and
installed compiler remain the oracle; the ordinary Blot toolchain still uses
them. `oracle.json` pins the source and executable used for later comparisons.
The remote tag `goose-port-oracle-156f84b` preserves that Zig source baseline.

The current phase is **writing**. The complete production port comes before
compilation, execution or differential verification. Files present here are
unverified source, not evidence of compiler parity.

The module map follows the Zig implementation. Goose contexts borrow typed
tables owned by their callers; numeric identities survive growth. Errors travel
as explicit trailing results. Native adapters cover scalar representation and
OS operations, without delegating compilation to Zig.

The experiment preserves supported syntax and diagnostics, checker/evaluator
behavior, both Wasm backends and reuse/caches. The public `blot-zig-project` server uses
protocol 1; guest session protocol is 2 and the private worker protocol is 2.
Guest ABI 8 and existing storage budgets remain the owned backend contract.

`source-correspondence.json` inventories the pinned native source and records
writing status. `port-notes/` contains the owners' exact remaining scope and
shared constructor contracts. The current checkpoint is source-only; remaining
production modules and shared integration adapters are still being written.

The native entry is now source-written in `src/main.goose`, with concrete CLI
pipelines and process worker dispatch under `src/driver/`. `build.py` regenerates
`src/source_identity.goose` from the actual Goose sources, native host support,
build options, selected Goose/C compiler binaries and emitted Goose runtime.
External stdlib/package trees can be pinned with `--resource-root`. It emits C
with a C-host header and links the ordinary Goose runtime plus the scalar/OS
adapter; it never invokes the Zig oracle. Reusable runtime and platform objects
are keyed by their actual source text, C compiler and flags.

The build has not been run during the source-writing phase. Once that phase is
complete, the build entry is `python3 build.py --goose /path/to/goose --cc clang`.
Development defaults to Goose `-O0` and C `-O0`; `--release` selects `-O2` for
both. Each subprocess stage reports its elapsed time and has a 30-second limit,
adjustable with `--stage-timeout SECONDS`. A timeout terminates the stage's
process group; failed object/link stages leave existing cached objects and the
previous executable intact.
`--identity-only` writes a source-only fingerprint without starting a compiler;
that is not a qualified build identity. Allocation metrics stay null with
`coverage: "unavailable"` until real runtime allocation observations exist.
