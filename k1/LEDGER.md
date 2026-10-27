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
| K1-03 proofs and Index | Not complete | Narrow source-bound guarded arithmetic and finite fact models exist; general source authority, complete evidence, exact required proofs and Index remain. |
| K1-04 scoped storage and particle | Not complete | Pool and builder models and hand-emitted Wasm particle experiments exist. Source lowering, checked ownership/loan preconditions, typed failure cleanup, global ownership validation and the I08 acceptance workload remain. |
| K1-05 relational packages | Not complete | A private stored-endpoint witness exists; generative domain, source ownership and package laws remain. |
| K1-06 functions and frames | Not complete | A narrow captured-closure witness exists; general capture, placement and finite resource contracts remain. |
| K1-07 ownership and bridge | Not complete | Narrow Owned and copy-bridge witnesses exist; full whole-region authority, loans, host ABI and runtime integration remain. |
| K1-08 generics and staging | Not complete | A narrow generic identity/dictionary witness exists; rank-one uniform ABI, general obligations and required static evaluation remain. |
| K1-09 optimization and reuse | Not complete | A partial scalar session has in-process reuse and target revalidation; general rewrites, authenticated work/dependencies and transactional failure laws remain. |
| K1-10 rollout and qualification | Not started | Full corpus, migration, fault sweeps, code inspection, performance and rollout gate remain. |

## Additional experimental models

An executed private Wasm pool/builder experiment and a closed source-linked
particle projection exercise scoped storage and complete-row publication. The
particle target remains pinned to a fixed fixture and assumes trusted owner and
loan context; it does not qualify source admission or prove the I08 invariant
for general K1 programs. A private
fixed-U32 copy bridge is exercised as both a native model and an emitted Wasm
fixture; neither is the complete M12 bridge or qualified host API. A retained
scalar snapshot experiment checks exact observations and simulated rollback
but recompletes every source; the separate scalar session below implements a
limited in-process warm path. Allocation-failure atomicity is not established.
The private flow parser has expanded expression and lexical
break coverage; a separate narrow Bool-to-U32 slice checks names and types and
emits Wasm, while general resolution, effects and lowering remain. A Linux
descriptor-relative source resolver can read below a trusted live package root;
it is not yet integrated with project configuration or an import graph, and
its platform, mutable-file and handle-lifetime limits are documented in
`SOURCE_RESOLVER.md`.

A private project-graph loader records exact import observations and stages
source revisions. It is not a module compiler, a coherent filesystem snapshot,
an authenticated dependency graph or an allocation-failure guarantee. The
tagged source path delegates to independently checked scalar or restricted
finite-loop representations; it is not a general shared expression/loop IR.

Further private slices exercise checked stored graph endpoints, a source-bound
U32-capture closure with indirect Wasm calls, a scalar Owned lifecycle model,
and a rank-one generic identity with bounded layout dictionaries. They are
restricted experiments, not completed K1-05 through K1-08: graph identities
and the Owned model's shared clock are trusted local bookkeeping; the closure
uses a synthetic fixed frame; and generic dictionary/slot authority and the
full ABI are absent. General source checking, provenance, cross-package
authority and the required runtime integration remain open.

A private guarded array-read fragment binds its proof to a supplied view,
index, length, version and true edge; those identities remain trusted fixture
inputs rather than K1 binding or loan authority. A separate private guarded
increment path checks source and successor evidence before emitting Wasm.
These paths do not implement general bounds reasoning or the particle loop.
The formal View/read and loan-forwarding experiments derive exact parameter
identities from source and recheck the declared obligations; they do not
establish a live external capability or enable an executable View ABI.

The unified scalar source path now supports one source-backed successor proof
on the true edge of `x < U32.MAX`. Separate private iteration, generalized
ownership and bounded requirement-graph slices check source and structural
evidence, but do not implement the general type/effect/loan system or complete
proof policy. Their local limits are not K1 language limits.

The private scalar session can reuse a prior in-process result after checking
exact source, observations, plan and emitted bytes. It depends on exclusive
trusted ownership of the session and receipt; that boundary is not enforced by
Goose namespaces, and receipt tampering is not authenticated. Its work meter
and dependency discovery are incomplete, so this is not qualified K1 reuse.

Additional private components cover source-checked static scalar evaluation,
formatter round trips, direct-call effect/resource summaries, cross-module
interface observations and generated F32 particle expressions. The formatter
is not wired into the edition-aware CLI or editor grammar; static calls,
general module lowering, complete effects/resources and the canonical host ABI
remain unsupported. Particle NaN tests check arithmetic NaN classification,
not the full permitted payload/sign set.

The scalar fixture uses an experimental shared work meter; the separate
fixtures do not yet share it. The meter has no compiler-wide integration or
durable receipt. The private checked-add fixture now discharges its scoped
proof edges after the last consumer, but its parser and encoder remain
unmetered and its handles are not portable. The public-interface model checks a narrow candidate
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

A clean combined Goose fixture run passed (exit 0) at `-O0` and `-O2` with
the previous-first private dispatcher, source-derived closed ownership chain
and actual private leaf-runtime reservation and restore. Source and
documentation hashes remained unchanged. The sampled dispatcher comparison
shows accepted-case timings overlapping parity with the earlier private route,
while rejected cases took 1.22–2.33 times as long; the record includes raw
samples. These paths do not establish general ownership, public ABI, engine
stack capacity, trap recovery or complete C09.

A clean combined Goose fixture run passed (exit 0) at `-O0` and `-O2` after
the private primary-first dispatcher, source-derived Owned fixture and direct
scalar Wasm encoder were integrated. It includes prior-output comparisons,
source/Core/target forgery and failure controls, loan and move tests, exact
budget checks, bytewise encoder parity and executed Wasm. Source and
documentation hashes remained unchanged during the run. These remain bounded
fixtures; general capability authority, public ABI, allocation-failure handling
and complete C09 are not qualified.

A clean combined Goose fixture run passed (exit 0) at `-O0` and `-O2` with
the branch-sensitive short-circuit proofs and private leaf-resource planning.
It includes prior-output compatibility, deep 118–127 operand chains,
forged-cycle rejection, source/target mutation controls and resource-boundary
execution. Source and documentation hashes remained unchanged during the
run. The leaf check relies on trusted capacity inputs and does not establish
runtime reservation, a general call graph, M11, public ABI or full C09.

The source-gated fixed-caller copy checker passed focused `-O0` and `-O2`
tests after the combined run below. They exercised 342 count/offset copies per
level and rejected eleven valid-Wasm loop mutations as well as individual-byte
mutations and truncations. The checker depends on initialized ingress,
allocator and descriptor geometry and a protected private instance; it is not
a general capability, M11 or trap-cleanup proof.

A clean combined Goose fixture run passed (exit 0) at `-O0` and `-O2` with
the private U32/Bool scalar/loop arena, bounded short-circuit and arithmetic
paths, old-first dispatcher, narrow guard proof and private scalar host
fixture. It includes independent source/target mutation checks, generated
execution, prior-output comparisons, and host preflight and poison tests.
Source and documentation hashes remained unchanged during the run. These
fixtures do not qualify the public ABI, general resources or complete C09;
the short-circuit proof still rejects some valid guarded expressions.

After the Zig lint cleanup, `deno task lint:zig` passed with zero findings
across 531 source files and one analyzer fixture. The unfiltered legacy
compiler gate also passed with Zig 0.17.0 and the native backend, using four
native shards and the full allocation-failure mode: 2,607 native inventory
tests and the guest tests. This validates the changed legacy files, not the
incomplete Goose K1 implementation.

A combined Goose fixture run passed (exit 0) at `-O0` and `-O2` after
integrating the private scalar/loop arena, source-to-target caller binding and
the versioned private work-schedule correction. It includes independent
source, target and mutation controls, generated loop execution and stale
receipt fallback tests. Source and documentation inputs remained unchanged;
the suite regenerated its ignored `k1/build/blot-k1` executable. These are
bounded private paths, not public ABI, general loans or full C09 qualification.

A clean combined Goose fixture run passed (exit 0) at `-O0` and `-O2`
with the private typed scalar Core, branch-aware direct fixed-caller lowering,
and source-instantiated tuple generic fixtures. It includes source and Core
forgery controls, independent target checks and executed Wasm tests. Source and
documentation hashes were unchanged during the run. These fixed profiles do
not establish general ownership, callable resources, M10/M11/M12/M13 or full
C09, and public K1 admission remains disabled.

A C09 audit also found an uncharged parent-node read in the private syntax
verifier. A scratch correction changes one scalar fixture's measured visits
from 815 to 827 and requires a private schedule revision and fresh fallback for
old cache entries. Source-byte telemetry and other required traversals remain
incomplete; the scratch correction is not included in this checkpoint.

A combined Goose fixture run passed (exit 0) after connecting the lexical
U32-to-Bool predicate to the private callable dispatcher. It covers `-O0` and
`-O2`, source/proof/target forgery, generated execution and a 64-case
compatibility matrix for earlier supported callables. The fallback preserves
generic prior diagnostics for some rejected lexical forms; resource, ABI,
M13 and C09 qualification remain open.

A combined Goose fixture run passed (exit 0) with a source-derived, checked
bridge Core required by the private fixed caller emitter and a lexical
U32-to-Bool proof/target path. It covers `-O0`/`-O2`, forged Core and source,
target mutations, wire/failure oracles and generated predicate execution.
The caller lowerer remains fixed-template and its erased `space.end` depends on
the private runtime model; the predicate path is not yet integrated into the
general callable dispatcher. General loans, public ABI, M11 and C09 remain
unqualified.

A combined Goose fixture run passed (exit 0) with a private U32-to-Bool
predicate path and a source-linked primitive schema/dictionary subset. It
includes `-O0`/`-O2`, forged type/source/schema and Wasm execution controls.
The predicate supports only a restricted body without local bindings; the
primitive schemas do not cover M10 or authenticate runtime slots and loans.
Resource contracts and public ABI/admission remain unqualified.

A fresh combined Goose fixture run passed (exit 0) with private U32/Bool
callables, the independent Bool target decoder, selected static layout
metering, and optional solver-free audit generation. It covers `-O0`/`-O2`,
source/Core/target forgery, canonical Bool execution, counter boundaries and
fail-closed audit controls. An earlier run was interrupted (exit 130) after
shared files changed during execution; it is not a passing gate. Raw Bool
callers must supply 0 or 1, resource bounds are not proved, and the layout
meter and optional audit do not qualify C09, M11, ABI or public admission.

A combined Goose fixture run passed (exit 0) with additional actual F32,
image-copy and comparison metering and independently transcribed selected ABI
anchors. It includes `-O0`/`-O2`, arbitrary-bit F32 differential, byte-mutation
and work-cutoff controls. The ABI anchors cover only selected provisional
records and all admissions remain closed. Runtime allocation/serialization,
metadata and other required traversals remain unmetered, so this is neither a
complete C09 receipt nor a qualified M10 ABI.

A combined Goose fixture run passed (exit 0) with an independent bounded Wasm
decoder for the private joined scalar/loop driver, the limited `Fn` spelling,
worker range checks, conditional frame composition and target-work metering.
It covers `-O0`/`-O2`, valid-Wasm instruction mutations, execution, long inputs
and work-boundary controls. The driver now uses the decoder instead of a
second emission. These remain private subsets; complete M13, M11, C09, source
loans and public ABI/admission are not qualified.

A combined Goose fixture run passed (exit 0) with the private joined scalar
driver, ordered static-work path, fixed-target helper controls and adapter
control-flow checks. It covers `-O0`/`-O2`, Wasm execution, source and target
forgery, ordered work boundaries and helper failure tests. The driver remains
private and its target association currently re-emits with the same producer;
the ordered work and fixed helper checks do not qualify full C09 or general
ownership, M11 or ABI admission.

A combined Goose fixture run passed (exit 0) with the guarded caller, a
fixed-target machine decoder and caller-flow witness, conditional frame model,
and shared aggregate work-meter prototype. It includes `-O0`/`-O2`, target
mutation, frame-frontier, wire/cleanup, forged proof and work-boundary controls.
The machine path and selected slot checks do not establish M11 depth or a
complete frame bound; the caller's helper/loan authority and C09 remain
unqualified.

A combined Goose fixture run passed (exit 0) with the private in-module caller,
actual scalar lexer/source-byte metering and provisional operation registry.
It covers `-O0`/`-O2`, target-byte and truncation rejection, wire and cleanup
oracles, lexer parity, work-counter boundaries and ABI candidate mutations.
The caller still requires a trusted private runtime; its fixed frame and
general loans are not qualified. Metering and the operation inventory remain
partial and do not establish C09 or the M10 ABI.

A combined Goose fixture run passed (exit 0) with the private public-shaped
scalar/loop source seam, branch-aware source-local builder plan, metered scalar
helpers and partial ABI inventory. The run covers `-O0`/`-O2`, forged source
and Core, independent digest, execution and work-boundary controls. Original
source-span portable Core, full C09, general loans, qualified ABI and public
admission remain incomplete; the private ABI inventory is not the M10 hash.

A combined Goose fixture run passed (exit 0) with the private source-order
wire/manifest candidate, import-free one-module adapter and worker, and optional
static-evaluation cache. It includes `-O0`/`-O2`, independent source/target,
wire, frame, partial-trap, F32 and 500-program cache differential controls.
The manifest remains ineligible for public M12; caller loans, the complete
frame bound, ABI and C09 are not qualified. The paired cache measurement and
its limits, including a unique-input regression, are in `static_fast_SCOPE.md`.

A combined Goose fixture run passed (exit 0) with the fixed source-only
record/Dest/Result adapter and a private Wasm frame-arena witness. It covers
`-O0`/`-O2`, target-byte mutation, frame boundary and owner lifecycle controls,
including zero-byte owners. The adapter has no qualified canonical lowering;
its public eligibility is false. The frame witness's 768-byte allowance is
not a derived M11 bound, and general loans, ABI and typed trap cleanup remain
unqualified.

A combined Goose fixture run passed (exit 0) with the checked source and
conditional transition gate, a private live-Wasm instance and fixed-window
fixture, and immutable static-array publication. It covers `-O0`/`-O2`,
independent generated oracles, source/target forgery, hostile input and
failure paths. The window's frame preflight is modeled, the live adapter
trusts its host and runtime, and the static index identity is a host model.
These checks do not qualify general K1 loans, M12, C09 or public admission.

A combined Goose fixture run passed (exit 0) after connecting the I08
source/type/bounds representation to its independently checked operation
trace and Wasm target, adding canonical builder-use checks, and evaluating
restricted pure calls inside static products. The `-O0`/`-O2` run includes
forgery controls and an independent F32 execution oracle. These remain private
subsets: source association and structural builder use do not establish live
runtime loans, dynamic versions, complete C09 accounting, or the host ABI.

A combined Goose fixture run passed (exit 0) after adding the I08 source
syntax, type-shape and formal-bound checks and bounded static products and
pure calls. It runs these checks at `-O0` and `-O2` alongside the prior
fixtures, adversarial tests and Wasm execution. The new I08 checks do not
admit executable code or establish live loans; static Domain/global publication
and full semantic-work accounting remain unimplemented.

A further combined Goose fixture run passed (exit 0) with source-bound formal
View proofs and forwarding, a locally allocated singleton View, scalar call
chains, and a same-owner range model and one-region host bridge. The run covers
`-O0` and `-O2`, independent adversarial checks, and execution of the private
Wasm worker. These cases use bounded, trusted models and do not establish
general loan provenance, frame preflight, the full M12 ABI, or public K1
admission.

A further combined Goose fixture run passed (exit 0) with mixed-loop fact
checks, multi-entry linking, the private host-copy witness and the corrected
particle-order tests. It includes `-O0`/`-O2`, independent oracles and Wasm
execution; it is not full K1 or ABI qualification.

A combined Goose fixture run passed (exit 0) after correcting the particle
workers to evaluate both row fields before either store, connecting the mixed
scalar/loop path and source-bound relation proofs, and adding the linked scalar
fixture. The run includes `-O0`/`-O2`, structural instruction-order checks,
test-only traps before stores, independent oracles and Wasm execution. These
remain restricted experiments, not complete K1 qualification.

A further combined Goose fixture run passed (exit 0) after adding the private
formatter, scalar static evaluator, source-linked particle lowering, effect
summary and cross-module interface tests. It includes `-O0`/`-O2`, independent
oracles and Wasm execution; it does not qualify their complete K1 counterparts.
In particular the particle arithmetic-NaN witnesses test NaN classification,
not the entire permitted payload and sign set.

A combined Goose fixture run passed (exit 0) after adding the tagged
scalar/loop path, source-linked particle worker, private project graph,
multi-schema wire model and source-bound successor refinements. Tests include
Goose `-O0`/`-O2`, independent oracles and Wasm execution. Trusted fixture
contexts, incomplete work accounting and the other limitations above remain;
this is not the full K1 qualification gate.

A further combined Goose fixture run passed (exit 0) after integrating the
unified guarded-increment path and adding source-bound proofgraph, iteration
syntax/completion and generalized ownership tests at `-O0` and `-O2`. These
remain bounded private subsets without complete K1 source admission. A later
private session benchmark and its precise limits are recorded in
`session_BENCHMARK.md`.

A combined Goose fixture run passed (exit 0) after connecting the unified U32
source path and adding the scoped fact graph, carry-loop, branch-aware affine
model and hardened private session checks. The run includes Goose `-O0`/`-O2`,
independent oracles and Wasm execution. The fixed-source and trusted-state
limits above still apply; this is not full K1 qualification.

A further combined Goose fixture run passed (exit 0) after adding guarded
reads, increment evidence, the source-bound Owned program and U32 local
bindings. The driver executes the locals subset; some diagnostics still use
private numeric statuses without complete source spans. The general language,
shared accounting, host ABI and rollout gates remain incomplete.

A further `GOOSE=/tmp/k1-goose/build/goose GOOSE_HOME=/tmp/k1-goose-home
sh k1/test.sh` run passed (exit 0) after adding the graph, closure, Owned and
generic fixture laws at both optimization levels. The limits recorded above
still apply, and this does not establish their milestone qualification.

A subsequent working-tree run of `GOOSE=/tmp/k1-goose/build/goose
GOOSE_HOME=/tmp/k1-goose-home sh k1/test.sh` passed (exit 0), including the
private whole-declaration flow path, scoped checked-add proof, source resolver,
F32 expression oracle, pool/builder and particle Wasm witnesses, and copy-bridge
fixtures at `-O0` and `-O2`. This remains a fixture suite, not the K1 rollout
gate. The public K1 build and check commands remain unavailable.

At checkpoint `55310e1dd29e769155e9a4d86a750a614169f245`, `GOOSE=/tmp/k1-goose/build/goose
GOOSE_HOME=/tmp/k1-goose-home sh k1/test.sh` passed (exit 0), including the
registered Goose `-O0`/`-O2` component tests and Node execution witnesses.
The suite includes the independently checked fixed ABI record component,
source identity model, flow syntax/completion model, scheduled scalar work
model, and adversarial Core and Wasm graph tests. These are private models;
they do not complete public K1 admission, the ABI profile, semantic-work
accounting, or rollout qualification. A preceding run failed to compile an
oversized snapshot test; that test was corrected before the passing run.
The source identity model does not open paths or establish filesystem authority.
The scheduled scalar pipeline is now wired into the private CLI fixture, and
byte telemetry remains incomplete. The fixed ABI records are a proposed component, not a
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
labels, diagnostic categories and a few scalar fixture operations;
it is not the complete K1 operation registry. A private `add-fixture` exercises AddFits for a parameter plus zero and
revalidates its source, proof and plan before emitting i32.add. Its job-local
scope handles and mutable work counters cannot establish cross-compile provenance;
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
