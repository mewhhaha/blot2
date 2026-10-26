# K1 Goose implementation ledger

Target: [issue #37](https://github.com/mewhhaha/blot2/issues/37), K1 revision 1.
Reviewed and starting baseline: `1e39b5d8a4268b9edf769c2813d5231abe1c963b`.
Implementation is an experimental Goose path alongside the legacy compiler;
legacy remains default. This ledger records evidence, not completion claims.

| Task | State | Evidence / remaining work |
| --- | --- | --- |
| K1-00 shared scalar contract | In progress | `k1/CONTRACT.md` defines a deliberately narrow coordination seam. The experimental scalar fixture can emit and execute a narrow Wasm module. Catalog labels and a narrow operation registry exist; complete operation coverage, canonical identities in requests and durable artifact headers, owned checked artifacts, independent artifact validation and the complete fixture inventory and phase trace still require implementation and tests. Checking strings at the fixture boundary is not artifact-header validation. The private driver now bounds file reads at 16 MiB and probes one extra byte to reject oversize inputs. This alone does not qualify the prototype for untrusted inputs. |
| K1-01 syntax and completion | Not complete | The private fixture additionally builds and checks an owned lexer-to-scalar syntax snapshot. Full grammar, explicit exits, formatter/editor and round-trip laws remain. |
| K1-02 checked scalar Core | Not complete | The private scalar driver validates transient value-only interface, function and lowering-plan records. Canonical owned artifacts, full independent validation, stable identity, proof/effect/resource data and post-sealing inference guard remain. |
| K1-03 proofs and Index | Not complete | A standalone bounded ordering graph model trusts caller-supplied facts; source authority, independently validated evidence, exact required proofs and Index remain. |
| K1-04 scoped storage and particle | Not complete | A standalone pool-state model is tested with trusted slot/bitmap state. Runtime integration, ownership/loan preconditions, destinations/builders, failure paths and executed Wasm particle remain. |
| K1-05 relational packages | Not started | Generative domain and stored endpoint laws remain. |
| K1-06 functions and frames | Not started | Closure capture, placement and finite resource contracts remain. |
| K1-07 ownership and bridge | Not started | Whole-region Owned and copy-only host bridge remain. |
| K1-08 generics and staging | Not started | Rank-one uniform ABI, dictionaries and required static evaluator remain. |
| K1-09 optimization and reuse | Not started | Bounded revalidated rewrites, cache and transactional failure laws remain. |
| K1-10 rollout and qualification | Not started | Full corpus, migration, fault sweeps, code inspection, performance and rollout gate remain. |

## Additional experimental models

The scalar fixture uses an experimental shared work meter; the separate
fixtures do not yet share it. The meter has no compiler-wide integration or
durable receipt. The existing add-proof fixture does not discharge proof edges
by scope, so it can over-reject. The public-interface model checks a narrow candidate
and producer tuple but does not publish a complete interface or establish its
portable hash and dependencies. The manifest validator checks in-memory
geometry only, with local choices for empty regions and minimal page count; it
does not decode artifacts or validate ABI hashes, runtime roles, executable
provenance, certificates, or every conforming memory layout. The private
interface-envelope candidate checks canonical bytes against a caller-selected
identity and hash; it does not authenticate either, validate source semantics,
ABI hashes, work receipts or executable bytes, or admit public declarations.

After independent review, `GOOSE=/tmp/k1-goose/build/goose
GOOSE_HOME=/tmp/k1-goose-home ./k1/test.sh` passed (exit 0) with the work,
public-interface and geometry models at O0/O2; the separately added
interface-envelope candidate test also passed at O0/O2. This is focused test
evidence, not full K1 qualification.

## Validation evidence

On this working-tree revision, `GOOSE=/tmp/k1-goose/build/goose
GOOSE_HOME=/tmp/k1-goose-home sh k1/test.sh` passed (exit 0), including the
registered Goose `-O0`/`-O2` component tests and Node execution witnesses.
The suite includes the independently checked fixed ABI record component,
source identity model, flow syntax/completion model, scheduled scalar work
model, and adversarial Core and Wasm graph tests. These are private models;
they do not complete public K1 admission, the ABI profile, semantic-work
accounting, or rollout qualification. A preceding run failed to compile an
oversized snapshot test; that test was corrected before the passing run.
The source identity model does not open paths or establish filesystem authority.
The scheduled scalar pipeline is not wired into the CLI, and byte telemetry
remains incomplete. The fixed ABI records are a proposed component, not a
complete profile or ABI digest.

The persistent scalar validator test was run with
`GOOSE_HOME=/tmp/k1-goose-home /tmp/k1-goose/build/goose run k1/test_validate.goose --debug`
(exit 0) against Goose pinned revision `a108677d300cb0e8bbb842c35a353abe67a20c6c`.
It accepted an identity and a U32 maximum constant and rejected forged
operand spans, an unbound parameter, mismatched literal, invalid kind, and
mismatched edition, semantic policy, optimization policy, and ABI. It also
rejects reserved binders, bare CR, and malformed UTF-8 (including comments),
while accepting a valid non-ASCII comment and CRLF.
This is narrow development evidence, not the K1-00 inventory or full gate.

The isolated public-scalar frontend checks candidate `pub let` declarations,
including explicit effects and declared resource bounds, and independently
verifies source correspondence. It does not publish a completed interface or
enable public K1 admission. Goose BLAKE3 known vectors are tested separately
from any artifact admission; a digest does not establish validity or provenance.

The scalar fixture now also exercises explicit function-body and value-block
forms from SYN-A01 through independent checking and Wasm execution; invalid
break targets are rejected. An additional lexer-to-owned-syntax pass checks
the same accepted scalar source after source/Core validation. A disagreement
is an internal error; this is not a general parser or a complete completion
judgment. `k1/artifact.goose` provides a bounded experimental
scalar container and checks version labels before payload decoding. Its tests
exercise truncated objects, forged header bytes and fields, and source mismatch.
It is not a serialized K1 CheckedFunction, ABI hash, or structural certificate.
The private module fixture parses and separately validates owned source and
transient Core before Wasm emission. It supports at most 256 U32-to-U32
functions, direct calls and bitwise AND, rejects recursion and call depth above
128, and exports private functions only for testing. It is not general module
admission, a host bridge, or a portable artifact. The scalar fixture uses one
fresh, partial work meter for its source, owned syntax, Core, plan, emission,
geometry and independent Wasm-byte checks, including U32 bitwise-and and
unsigned comparison. The control fixture separately tests explicit-return
branches and short-circuit Bool operations with canonical Bool inputs. The
source-bound public-scalar interface, function and plan envelopes and owned
snapshot are private experiments with caller-supplied, unauthenticated identity
and ABI values. None establishes complete K1 work accounting, public admission,
ABI certification, or portable artifact authority. The
bounded layout geometry, builder, ordering graph, and pool-state models are
exercised in isolation; they do not establish semantic types, source facts,
ownership, loans, or runtime qualification. A private Wasm pool guest fixture
is also executed independently; it exports memory for tests, does not validate
forged cross-owner metadata, and is not a runtime certificate. The builder model relies on a
single shared clock and compiler-proven destination and loan authority. The experimental catalog covers version
labels, diagnostic categories and only the three scalar fixture operations;
it is not the complete K1 operation registry. A private `add-fixture` exercises AddFits for a parameter plus zero and
revalidates its source, proof and plan before emitting i32.add. Its fixed
owner/scope and mutable work counters cannot establish cross-compile provenance;
the rest of the compiler does not share a complete semantic traversal meter.
No cache/imported proof is admitted and this does not establish K1-03 coverage.

On the same baseline, `GOOSE=/tmp/k1-goose/build/goose
GOOSE_HOME=/tmp/k1-goose-home ./k1/test.sh` passed (exit 0), including Goose
BLAKE3 vectors and public-scalar candidate checks at O0/O2, exact-limit,
one-byte-over-limit and missing-file input checks, as did
`deno test --allow-read --allow-write --allow-run compiler/cli_k1.test.ts`
and `deno check compiler/cli.ts compiler/installed_cli.ts`. Separately,
`ZIG=/workspace/.tools/zig-x86_64-linux-0.17.0/zig
ZIG_GLOBAL_CACHE_DIR=/tmp/k1-zig-cache ZIG_LOCAL_CACHE_DIR=/tmp/k1-zig-local
GOOSE=/tmp/k1-goose/build/goose GOOSE_HOME=/tmp/k1-goose-home
./k1/test_blake3.sh` passed the offline Zig-vs-Goose differential at O0/O2.
The oracle is test-only and Zig reported `0.17.0`. `deno task lint:zig` failed (exit 1) with 22 findings in unchanged
baseline Zig files; the CI-pinned analyzer produces the same findings. An
unfiltered `deno task test:compiler` run was interrupted during smoke-build
(exit 130). A subsequent unfiltered run passed smoke and harness but exhausted
the native-run 600-second budget (exit 124); it is not a passing gate. The
supported four-shard retry also exhausted the same native-run budget (exit 124)
after its smoke and harness stages passed. Neither run qualifies as a pass.
A later full, unfiltered legacy compiler run passed with Zig 0.17.0:
`deno task test:compiler --native-shards 4 --phase-seconds 7200 --budget-seconds 10800`.
It completed all 2,606 native tests and guest tests in 1,335 seconds;
`build/bench/iteration/timings.json` contains the timing artifact. This is
evidence for the existing compiler, not qualification of the Goose K1 path.
The Zig lint findings remain unresolved.

Add exact
commands, tool versions, exit statuses, fixture/law IDs and source commit as work
proceeds. Repository `AGENTS.md` requires Zig 0.17.0, checking `zig version`
before build batches, native development/testing with `-Dllvm=false`, and both
`deno task lint:zig` and unfiltered `deno task test:compiler` before compiler
commits. A sampled or interrupted run is not a pass. Goose-specific build and
execution evidence is also required. Do not represent absent or historical
evidence as current qualification.
