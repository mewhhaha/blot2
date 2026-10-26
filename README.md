# Blot K1 — Goose rewrite

A clean implementation of [issue #37](https://github.com/mewhhaha/blot2/issues/37)
in [Goose](https://github.com/aardappel/goose), on `rewrite/goose-k1`.
The previous Zig compiler is preserved on `main`.

**The implementation passes its frozen release gate; performance qualification
is pending.** The [implementation ledger](IMPLEMENTATION.md) records evidence
and remaining work. The
[versioned specification](docs/spec/INDEX.md) defines the language and ABI.

The compiler checks explicit storage ownership, initialized lengths, integer
arithmetic and collection identities before lowering. It emits WebAssembly
with fixed memory, bounded frames, uniform generic bodies and no runtime
reference counting or garbage collector. Serialized Core is independently
validated; a disk artifact cannot authorize skipping source checks.

## Build and use

```sh
scripts/bootstrap-goose.sh
scripts/build.sh
build/blot check examples/identity.blot --language=k1 --timings
build/blot build examples/identity.blot -o build/identity.wasm
scripts/check.sh
scripts/check.sh --release
```

The pinned Goose revision is `a108677d300cb0e8bbb842c35a353abe67a20c6c`.
Set `GOOSE` to an existing compatible executable to avoid bootstrapping.
Building requires CMake and a C++ compiler for Goose, then Clang for the
compiler executable. Deno runs host and emitted-Wasm tests; Node/npm run the
pinned TextMate/Oniguruma editor gate. Linux is the
currently exercised platform, including real arena-allocation fault injection.

A complete scalar export declares effects and resource bounds:

```blot
pub let identity: U32 -> U32 ! {} resources {depth: 1, frame: 0} =
  fn value => return value
```

Ordinary U32 arithmetic needs checked preconditions. For modular arithmetic,
use explicit operations such as `U32.wrapping_add`. Functions return explicitly;
value blocks use `break`. See [the language guide](docs/guide.md) and
[examples](examples/) for loops, arrays, callbacks and owned storage.

Raw scalar exports check numeric preconditions and canonical Bool inputs before
source execution. Invalid input traps; callers must discard that instance.
The copy-only array bridge instead reports invalid input through its status API.

The particle example uses the copy-only host array bridge:

```sh
build/blot build examples/particles.blot -o build/particles.wasm \
  --bridge-config=examples/particles.json --opt=off --timings
```

[host/blot.ts](host/blot.ts) validates the manifest, copies values across the
boundary, rejects reentry and permanently disables an instance after an
unexpected Wasm trap. Memory and raw descriptors remain private. Zero-sized
array elements use `{length: count}` rather than allocating an array of units.

## Repeated edits

`build/blot serve` reads one JSON build request per line and writes one JSON
result per line. A request has `input`, `output`, and optionally `package_root`,
`export`, `bridge_config`, `opt`, `cancel_file`, `trace` and `telemetry`:

```json
{"input":"examples/identity.blot","output":"build/identity.wasm","package_root":"."}
```

The process retains its last successful checked revision. Exact declaration
text, actual name lookups and complete dependency interfaces govern reuse.
Changing a callee body can preserve its callers' checked bodies; lowering binds
calls to the current callee. Static evaluation also depends on executed bodies.
The response reports `completed_bodies`, `reused_bodies`, `revision` and timings.
Failed and cancelled builds preserve the last output and successful revision.
It also reports semantic/validation visits, retained bytes, completed modules,
active completion regions and downstream completion attempts. The last two
remain zero after admission. `--trace` reports phase/module progress on stderr.

Reuse is conservative: unresolved inferred resource interfaces can decline it.
The current cache keeps one complete revision, bounded by the 16 MiB artifact
limit and 16,384 receipts, below the 128 MiB retained-payload ceiling. It is
process-local; `inspect FILE.bk1` validates an external object but does not import
its receipt into the trusted source cache.

## Other commands and verification

```sh
build/blot format examples/identity.blot
build/blot migrate old-program.blot
build/blot complete builder.
build/blot build examples/identity.blot -o build/identity.wasm \
  --emit-core=build/identity.bk1
build/blot inspect build/identity.bk1
build/blot rebuild build/identity.bk1 -o build/rebuilt.wasm
```

Migration produces a syntax-aware review report. See the
[complete migration example](docs/migration.md), including an imported generic
helper and its copy-only host. Optional optimization is selected with
`--opt=off|fast|release`; enabled transformations are bounded and revalidated.
Release-only inlining, fusion and SIMD remain future optional work; both enabled
tiers currently use the R01–R12 kernel. `rebuild` independently admits required
Core and regenerates Wasm locally, without source files or trusted disk receipts.

Build with `--telemetry` to collect reservations/failures, releases/resets,
backing/frame/result high-water bytes, initialized/copied bytes, source calls and
loop iterations. `host.telemetry()` returns an immutable BigInt snapshot.
Instrumentation has separate geometry and is excluded from ordinary timing
measurements. See [the measurement methodology](benchmarks/README.md).

`scripts/check.sh` discovers the complete current native inventory, verifies
start/end timing evidence, builds the compiler and runs executed-Wasm, host,
retained-session and allocation-failure suites. Logs belong in `test-results/`.
The gate checks source hashes before/after and writes
`test-results/qualification.json`; changes during the run invalidate it.
Passing that inventory is separate from finishing every specification law.
The particle test inspects the actual baseline loop for four F32 loads, two
stores, two multiplies, two adds and no calls inside the loop.

Earlier compiler benchmark numbers do not qualify this rewrite. No speedup or
sub-second project-build claim is made until the specified scaling and edit
workloads have been measured with complete metadata.

The [scope table](docs/features.md), [operation registry](docs/REGISTRY.md),
[diagnostic catalogue](docs/DIAGNOSTICS.md) and
[shared ownership contracts](docs/CONTRACT.md) describe the implementation.
