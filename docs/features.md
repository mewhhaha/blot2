# K1 scope

The normative scope is [K1-LANG](spec/LANG.md),
[K1-MEM](spec/MEM.md) and [K1-CORE](spec/CORE.md).
Qualification status belongs to [the implementation ledger](../IMPLEMENTATION.md).

| Area | Implemented representation |
| --- | --- |
| Syntax | Explicit return and value-block break; finite loops/carries; formatter and editor grammar |
| Types | Scalars, bounded products/sums, transparent acyclic aliases, exact affine Result |
| Interfaces | Complete public effects/resources, explicit rank-1 generic boundaries, uniform dictionaries |
| Proofs | Finite versioned fragment, exact SSA/branch facts, required bounds and arithmetic evidence |
| Storage | Fixed pool/frame arenas, affine destinations/builders, immutable Views and stored Index brands |
| Packages | Existential Nat/Domain/Region witnesses, fresh openings, relational graph examples |
| Callables | Share captures, Many/Once usage, scoped environments, finite depth/frame contracts |
| Ownership | Single-backing Owned payloads, lexical borrowing, explicit close and failure cleanup |
| Staging | Bounded required-static evaluation, immutable arrays/products/callable environments |
| Host | Scalar exports and validated copy-only Plain-array bridge; explicit failure statuses |
| Artifacts | Bounded canonical Core, independent admission, local executable rebuilding |
| Reuse | Current-process exact receipts; changed complete interfaces/static observations invalidate consumers |
| Optimization | Bounded R01–R12 kernel and release-only scalar inlining; independent candidate validation and baseline fallback on optional limits |
| Measurements | Phase/work counters, separate guest telemetry, fresh/retained/scaling and build-iteration harnesses |

K1 deliberately excludes runtime strings, recursive data/calls, higher-rank
parameters, polymorphic recursion, arbitrary host imports, exceptions/tasks,
effect handlers, implicit managed storage, memory growth and zero-copy or
asynchronous host access. These are language boundaries, not unfinished silent
fallbacks. Unsupported source receives a diagnostic.

`--opt=release` adds bounded direct scalar inlining to the R01–R12 kernel.
Its initial eligibility and fixed budgets are documented in
[the shared contract](CONTRACT.md#bounded-release-inlining). Scalar replacement,
fusion and SIMD remain optional future work under C10/I03. Compiler jobs are internally single-threaded; the gate also compares
four independent concurrent jobs. There is no persistent source-admission
cache: restarting checks source afresh, while explicit source-less Core inputs
use independent artifact admission and locally generated Wasm.

On this user-requested clean rewrite branch, K1 is the sole edition. The old
compiler and its legacy edition remain on `main`; there is no mixed managed
ABI call path. Linux is the exercised compiler/OS/fault-injection platform.
