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
behavior, both Wasm backends, reuse/caches and project session protocol 2.
Guest ABI 8 and existing storage budgets remain the owned backend contract.

`source-correspondence.json` inventories the pinned native source and records
writing status. `port-notes/` contains the owners' exact remaining scope and
shared constructor contracts. The current checkpoint is source-only; major
engines, the CLI/session driver and other modules are still being written.
