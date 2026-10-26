# Experimental Goose K1 scalar fixture

This directory is an early, intentionally incomplete experiment for issue #37.
Its private fixtures accept a narrow scalar subset, and the resulting bytes are
test fixtures, not qualified K1 artifacts. The public `check` and `build` commands
reject K1; the existing compiler remains the default. See [CONTRACT.md](CONTRACT.md)
and [LEDGER.md](LEDGER.md) for supported syntax and outstanding work.

Build Goose at the pinned upstream revision `a108677d300cb0e8bbb842c35a353abe67a20c6c`
using its documented CMake instructions (CMake 3.27 or later and a C++20
compiler are required). The optional graphics and physics packages are not
needed. For example, in a separate scratch directory:

```sh
git clone https://github.com/aardappel/goose.git
git -C goose checkout a108677d300cb0e8bbb842c35a353abe67a20c6c
cmake -S goose -B goose/build -DCMAKE_BUILD_TYPE=Release
cmake --build goose/build --config Release
```

With the resulting Goose executable on `PATH`, from the repository root:

```sh
./k1/build.sh
./k1/test.sh
```

Alternatively set `GOOSE` to the absolute path of that executable. Both scripts
use `k1/build/goose-home` for Goose's generated files unless `GOOSE_HOME` is
already set. `test.sh` also requires Node.js and uses a temporary directory
for its generated test fixtures. It runs Goose-only BLAKE3 known vectors and
candidate-only public-scalar frontend tests at `-O0` and `-O2`, plus lexer,
owned-syntax, scalar frontend, validator, Core, lowering-plan and artifact-container
laws, and standalone
layout, builder, pool-state, ordering graph and narrow catalog models. It tests
private scalar and pool Wasm fixtures in Node and exercises driver and rejection
paths, including short-return, body-block and value-block scalar forms.
Passing these tests does not constitute K1 qualification. The public-scalar
frontend remains a candidate parser and verifier; it does not publish an
interface or enable public K1 admission.

An optional offline differential compares the Goose BLAKE3 implementation
against the Zig 0.17.0 standard library oracle:

```sh
ZIG=/absolute/path/to/zig GOOSE=/absolute/path/to/goose ./k1/test_blake3.sh
```

The oracle is test-only. Neither the Goose implementation nor the compiler
uses Zig at runtime; `test.sh` does not require the Zig oracle.

The internal driver accepts `k1/build/blot-k1 fixture INPUT [--trace]`,
`module-fixture`, `add-fixture`, `control-fixture`, `flow-fixture`,
`locals-fixture`, and `public-fixture`
with the same arguments. All write hex-encoded
experimental Wasm to standard output and optional phase messages to standard
error; none writes an output file. Only use them for fixture testing. The
module fixture supports up to 256 top-level U32-to-U32 functions with direct
calls, U32 atoms and bitwise AND. Call depth is limited to 128; recursion,
Bool functions, imports, captures and other syntax are rejected. Its private
function exports are test instrumentation, not the public K1 host bridge.
The checked-add fixture supports only a U32 parameter plus literal zero and
revalidates its proof and plan within one invocation, then discharges its
active proof edges. Its job-local handles and mutable work counters do not
establish cross-compile provenance, and the
full semantic-work meter is not implemented; it cannot certify cached or
imported proofs or claim K1-03 qualification. The scalar fixture uses one fresh
work meter and phase scheduler across its implemented parser, Core, source
validation, lowering and emitted-byte checks. This is partial accounting, not
a complete K1 work receipt: byte telemetry and other required traversals remain
open. The public-declaration fixture rebuilds and validates source-bound
interface, function and plan snapshots before emission, but uses synthetic
package, module and ABI identities and does not perform public admission.
The flow fixture handles a narrow complete Bool-to-U32 declaration with
explicit returns, nested branches and short-circuit Boolean expressions. Its
test caller must supply canonical Bool values; it is not a host ABI.
The locals fixture handles a narrow U32 declaration with scoped immutable
bindings, nested branches, explicit returns and checked or explicitly wrapping
arithmetic. A separate tagged alternative handles a bounded finite-loop
subset, including a restricted shared scalar-expression/loop representation.
Their accepted proofs and limitations are described in
`unified_schema.md` and `compiler_schema.md`.
A separate thin-entry fixture exercises a scalar worker and canonical adapter;
it does not define the public host protocol. Complete lowering plans and portable
checked artifacts remain absent. The builder, pool and ordering graph models are
isolated and do not establish source, ownership, loan or runtime guarantees.
The separately executed pool guest exports memory only for testing, does not
validate forged cross-owner metadata, and is not a runtime certificate. A small
C I/O adapter reads at most 16 MiB and probes one additional byte to reject larger files; the test suite exercises the limit and
read errors. This prototype is not qualified for untrusted inputs and does not
provide a general K1 compiler, ABI manifest, or portable checked artifact.

`python3 k1/bench_scalar.py --legacy PATH_TO_ZIG_BLOTC --k1 k1/build/blot-k1`
alternates fresh processes on an identity function and validates five outputs
in Node.js. It prints raw wall-time samples, binary hashes and output hashes.
Build the legacy executable from the source revision being compared and record
its toolchain separately. The private K1 fixture and the legacy compiler perform
different work and publish through different protocols, so their timings are
not an implementation or qualification comparison of the full languages.
