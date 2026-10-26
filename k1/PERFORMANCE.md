# K1 performance evidence and remaining work

This records a private-fixture investigation, not K1 qualification or a
comparison proving that K1 is faster than the existing compiler. Issue #37's
performance methodology requires equivalent programs, the full relevant
contracts, paired measurements, correctness witnesses and retained/cold cases.
The current K1 public compiler, arrays, host bridge and retained project server
are incomplete, so those comparisons cannot yet be made.

## Redundant validation work in the private module fixture

For `N` distinct declarations, the original prototype compared each new name
with all earlier names during parsing. Each complete source verification and
each complete Core/emitter structural validation repeated its own distinct-name
scan. The private driver invoked full source verification four times: once in
`parse`, once directly, once in `to_core`, and once in `verify_core`. It also
ran two Core validations and one emitter structural validation. For distinct
names, this gave eight triangular duplicate scans, or `4*N*(N-1)` name
comparisons, excluding lookup, graph, token and byte work. The prototype's
256-declaration cap means these are counts over its **bounded supported
range**, not an unbounded K1 complexity claim. Comparisons can additionally
read a shared identifier prefix, so their byte cost depends on name length.

The scratch candidate retains the initial parse check, a complete independent
source-to-Core check after construction, and the emitter's structural check. It
removes the extra direct verification and the builder's redundant verification
on this private path. The ordinary `to_core` entry still validates its input;
the construction-only helper grants no authority, bounds its input, and its
output must be independently validated before emission. Its source and Core
checks are not portable artifact authentication. At that point it did not
remove the remaining quadratic duplicate-name scans.

For the following evidence, a test-only counter increment was inserted at each
iteration of the declaration-name duplicate loops: the parser and source
verifier in `module_frontend.goose`, the validator in `module_core.goose`, and
the emitter's `structural` validator in `module_wasm.goose`. The driver printed
those three counters after emission. Instrumentation was applied to scratch
copies, not the production path. The inputs were generated exactly as
`let f{i}: U32 -> U32 = fn x => return x\n`, for each `i` from zero to `N-1`,
and compiled using `blot-k1 module-fixture INPUT --trace`. The counts are:

| N | Original frontend / Core / emitter | Original total | Candidate frontend / Core / emitter | Candidate total |
| ---: | --- | ---: | --- | ---: |
| 32 | 2,480 / 992 / 496 | 3,968 | 1,488 / 992 / 496 | 2,976 |
| 64 | 10,080 / 4,032 / 2,016 | 16,128 | 6,048 / 4,032 / 2,016 | 12,096 |
| 128 | 40,640 / 16,256 / 8,128 | 65,024 | 24,384 / 16,256 / 8,128 | 48,768 |
| 256 | 163,200 / 65,280 / 32,640 | 261,120 | 97,920 / 65,280 / 32,640 | 195,840 |

The counts show 25% fewer **duplicate comparisons** for this input family;
they do not establish a 25% reduction in elapsed time or a speedup over the
legacy compiler. A separate instrumented 128-function call chain reported
four versus two full source-validation entries. In a 25-case scratch parity
check, including chains, independent functions, recursion, duplicate names,
unbound names, malformed UTF-8 and unsupported syntax, original and candidate
had identical exit codes, diagnostics, traces and Wasm bytes. The candidate's
Goose fixture suite passed, including forged Core/source cases at `-O0` and
`-O2`. These checks do not establish the full K1 work-meter or admission laws.

The source files used for this scratch comparison had SHA-256:

- Original `module_frontend.goose`: `9fcf8bb221ac7d6ca16367b033c11f05d2e6b8507716fb64232bcdcd9e042256`.
- Original `main.goose`: `d5f7153edc5306d6c0c342275e92f9562367e66d5b42fe968a52ca4f89fa2219`.
- Scratch candidate `module_frontend.goose`: `3d4950c22fa2d849e8fe37322f69384e4402a8f932696f083477a0e5b365193e`.
- Scratch candidate `main.goose`: `34b25e9ec87c214765b862da056116ee1a6879577ee49d774a47ff8ae948766d`.

The integrated files may contain additional changes; re-run the same tests and
counters against the exact candidate before using these numbers for a review.

## Scalar Wasm structure is not a runtime benchmark

A source-pinned legacy release compiler built with Zig 0.17.0,
`-Doptimize=fast -Dllvm=true`, produced an exported U32 identity body with
bytes `00 20 00 0b` (zero local declarations, `local.get 0`, `end`). The
experimental K1 thin identity export has the identical body. Neither body can
use fewer Wasm instructions for this identity under that calling convention.
The surrounding modules differ, and engine compilation, inlining, instantiation,
host calls and measurement noise can still change elapsed time. Identical body
bytes do not prove a measured tie or establish a universal speed limit for
other programs.

For U32 bitwise AND with 255, the legacy internal worker and the experimental
K1 thin worker both have body bytes `00 20 00 41 ff 01 71 0b`. The legacy
export includes a forwarding wrapper, which a Wasm engine may inline; that
possibility was not measured. The K1 thin entry is test-only and is not the
qualified K1 host bridge. The comparison says nothing about array traversal,
scoped storage, allocation or no-reference-counting workloads.

## Architecture and measurement still required

The original fixture scanned declaration tables and walked call chains from
every root. Its private parser now uses a deterministic AVL name index and an
iterative graph traversal. Its separate source verifier now uses its own
bottom-up name sort and reverse-edge graph traversal; it does not reuse the
producer's index as authority. The target structural validator now independently
sorts exact names using a bounded heap and checks each call's depth against its
target; strictly decreasing positive depths rule out cycles. The Core validator
now independently sorts exact names with a bounded heap and uses memoized
three-state graph walks, preserving the original per-function diagnostic order.
These paths are bounded by the prototype's 256-function and 128-depth caps,
but they are not a scalable general K1 frontend. Independent validation must
still check its own graph at the
immutable-owner boundary and charge required work. A hash or a mutable
`validated` flag must never substitute for admission.

The existing verifier also copies and re-lexes per-declaration projections,
and the fixture copies source into separate owners. A canonical owned source
and syntax graph, shared through checked immutable leases, can avoid repeated
copying while preserving exact source identity and failure cleanup. Exact-byte
comparison remains necessary where the specification requires it; a digest is
only a lookup aid. None of these changes establishes a speedup without
measurement.

The current Goose fixture has no qualified `serve-project` protocol, completed
interface/body cache, transactionally retained revision, or dependency-based
invalidation. The legacy `scripts/bench_compile.ts` measures fresh sessions,
unchanged checks and edit/revert scenarios through that protocol; it cannot be
used for a valid retained comparison until the K1 path implements equivalent
behavior. Cold compiler measurement must also compare equivalent source
semantics and output guarantees, rather than the current hex fixture against a
legacy compiler that writes a complete output file and JSON.

After K1 supports representative equivalent programs, benchmark the reviewed
release baseline and candidate on pinned toolchains and the same host. Use
counterbalanced paired runs, separate instrumentation from timing, retain raw
samples and report medians and dispersion, resource counters, cold/warm/edit
states, output checksums, and engine/host settings. Include the issue's
unoptimized particle projection, empty and full-capacity controls, higher-order
and generic cases, and the legacy compiler's synthetic compile corpus adapted
without changing semantics. Do not run timing tests concurrently with the full
compiler gate. The missing retained protocol, completed artifacts and runtime
must be built before those requested comparisons can run; their absence does
not prove that Goose cannot outperform the legacy compiler, or that an
architecture change alone guarantees a speedup. No end-to-end
K1-versus-legacy result or speedup has been established here.

## Private parser index and call-graph experiment

A scratch prototype, subsequently integrated into the private v3 parser,
replaces only the parser's name scans with a
deterministic AVL index and its per-root cycle/depth walks with a single
iterative color/depth traversal. It checks exact source bytes on name
comparison and collects all cycles before
reporting excess depth. At the time of these measurements the independently
authored source verifier, Core validator and emitter validator remained
unchanged and contained their own bounded quadratic checks. The source
verifier, Core validator and target structural validator have since been
separately optimized using the independent algorithms described above; none
of these later changes was part of the timing samples. The
prototype is not integrated into the shared public compiler or qualified for
K1 admission.

Test-only counters incremented once per parser name-order comparison and once
per graph node visit or depth-unwind step. On the same independent-function
inputs described above, parser duplicate comparisons changed as follows:

| N | Original parser comparisons | Scratch indexed parser comparisons |
| ---: | ---: | ---: |
| 32 | 496 | 133 |
| 64 | 2,016 | 335 |
| 128 | 8,128 | 801 |
| 256 | 32,640 | 1,854 |

For a 128-function single-call chain, the original parser's cycle and depth
walks recorded 16,384 node/edge steps; the scratch graph walk recorded 255
visits/unwind steps. These are **different explicitly described logical event
counts**, not elapsed-time results or a complete accounting receipt. Graph
processing is O(N+E) for this one-outgoing-edge subset after fixed-size
scratch initialization; indexing takes O(log N) name comparisons per lookup or
insert, with byte work depending on identifier lengths. The existing 256-node
and 128-depth fixture bounds still apply.

An independent test-only AVL tree walk checked full ancestor ordering,
reachability, node heights and balance after every insertion of 256 ascending,
reverse and permuted long-prefix names. Existing cycle, depth, forged-record and
frontend tests passed with Goose debug checks at `-O0` and `-O2`. A separate
159-source differential included declaration-order variations, random acyclic
graphs, cycles, a recursion-versus-depth priority case and malformed byte
mutations; old and scratch fixtures produced identical exit codes, diagnostics,
traces and Wasm bytes. An independent review also compared status and every
declaration field across 350 generated programs and their one-byte mutations,
plus long-common-prefix name controls. It found an oversized direct-helper
trap, which was fixed by guarding the input before fixed scratch indexing.
The indexed-parser change was subsequently measured on the limited private
fixtures in the B-to-C comparison below; those samples do not establish a
general speedup. It cannot be described as policy-compliant: the existing
prototype has no integrated declaration-wide C09 meter. Index comparisons,
rotations and graph visits
must be charged under the shared meter before public admission; byte-scanning
work also needs bounded accounting without silently changing which source
sizes the semantic policy accepts.

After the A/B/C timing snapshot described below, the source verifier was
separately changed to rebuild name ordering with a bottom-up merge sort and
recompute call depths through its own reverse-edge leaf queue. It does not
reuse the parser's AVL index or graph decisions. Test-only instrumentation
across the two source-verification passes recorded 2,942 name comparisons for
256 distinct leaves, versus 65,280 pairwise duplicate checks in the earlier
verifier. On a 128-function chain, the new verifier recorded 1,020 graph
operations, counting both graph construction and queue node/edge work; the
earlier two root-walk passes visited 16,512 nodes. These different event
definitions illustrate traversal shape, not an elapsed-time ratio. The later
Core and target validator changes have not been benchmarked.

The independent verifier tests cover invalid and duplicate spans, direct
helper limits, cycles, forged targets, 128/129 depth, 1,000 random/forged
graphs against a separate model and 400 positive DAGs. An old/new differential
also mutated every signed declaration field across seven boundary values and
every source byte in generated modules at `-O0` and `-O2`. These tests do not
replace a shared semantic-work meter or full K1 qualification. No timing for
this later verifier change is included in the samples below.

The target structural gate's tests compare against the previous pairwise-name
and per-root graph checks, including 800 positive DAGs, forged depths, cycles,
long shared prefixes and distant duplicate names at `-O0` and `-O2`. Independent
scratch review also checked 1,200 random and forged graphs against the prior
implementation. These are correctness checks, not timing measurements.

The Core validator's adversarial tests use a separate per-root graph oracle,
including 800 random graphs, forged records, depth limits and disconnected
cycle/diagnostic ordering cases. Scratch differential tests matched the prior
validator at `-O0` and `-O2`; a separate review tested 500 randomized name sets
against a pairwise oracle, including embedded zero bytes and invalid spans.

## Measured private-fixture samples

After the legacy native gate stopped, the previously described 4-to-2
verification change and parser-index change were measured separately. All
three binaries came from one Goose source snapshot at pinned Goose revision
`a108677d300cb0e8bbb842c35a353abe67a20c6c`. Control A retained four source
verifications and linear parser scans; B retained two verifications and linear
parser scans; C retained two verifications and the AVL/graph parser. The
independent verifier optimization added **after** these measurements is not
included. The bodies and diagnostics compared here are private fixture behavior,
not public K1 compilation.

The host was Linux x86-64, AMD EPYC 7763, four cgroup CPU cores and Node
v24.19.0. Each row uses four warmups followed by 31 alternating fresh-process
pairs. The harness checks exact generated Wasm hashes for both binaries in
every pair and executes independent Node witnesses for each workload. Ratios
are candidate elapsed time divided by control elapsed time; lower is faster.
The p10/p90 columns describe the spread of the paired sample ratios, not a
confidence interval.

| Private fixture workload | B/A median (p10–p90) | C/B median (p10–p90) |
| --- | ---: | ---: |
| 1-function chain | 1.027 (0.943–1.116) | 1.050 (0.828–1.244) |
| 16-function chain | 0.946 (0.798–1.101) | 1.038 (0.837–1.213) |
| 64-function chain | 0.854 (0.726–1.027) | 0.956 (0.753–1.157) |
| 128-function chain | 0.817 (0.727–0.922) | 0.961 (0.834–1.082) |
| 256 independent functions | 0.741 (0.658–0.787) | 0.937 (0.822–1.054) |
| One function with a 1 MiB comment | 0.701 (0.662–0.746) | 0.998 (0.889–1.084) |

The source-validation change is observable on the larger fixture cases; the
index-only samples overlap 1.0 throughout this small corpus. Do not infer a
general compiler speedup from either result. The benchmark includes process
startup, bounded input, checking, lowering and hex output, and it does not
exercise the required public API, project sessions, complete artifacts or
full K1 work accounting. The results include all samples, including outliers.
Before and after the runs no other active test workers were observed, and the
cgroup throttled-period and throttled-time counters did not increase; no
per-sample process monitor was used, so brief contention cannot be ruled out.

The exact ordered samples, CPU counters, binary/source hashes and workload
hashes are in [`validation.json`](measurements/2026-10-26-scalar/validation.json)
and [`index.json`](measurements/2026-10-26-scalar/index.json). The respective
Goose binary SHA-256 values were:

- A: `93b4bc9ff0b7c9aaf0c1b3cc40637707bac8517b1bd96db9f41226596930da94`.
- B: `3393bfbd8f5dfbd7e7a660e6d7247f22c7aece22e24d22f4337dabea433a709d`.
- C: `980d5559bce54a5e190d700bfe3a30aa8112eacd93fd36fed41f1876d7de82a9`.

The deterministic [`source-c.tar.gz`](measurements/2026-10-26-scalar/source-c.tar.gz)
contains the 34 project source/build files imported by C, with individual
hashes in [`source-c-pins.json`](measurements/2026-10-26-scalar/source-c-pins.json).
Its SHA-256 is `8ef80940a49d93538dc442eb42722d3660b8c63eff2f0f5cab2c00af483d7dd9`.
The archived source contains no toolchain or executable. To reconstruct the
three candidates, extract that archive to three separate scratch directories;
replace `k1/module_frontend.goose` in A and B with
[`control-unindexed-module.goose.txt`](measurements/2026-10-26-scalar/control-unindexed-module.goose.txt),
and replace `k1/main.goose` in A with
[`control-four-validation-main.goose.txt`](measurements/2026-10-26-scalar/control-four-validation-main.goose.txt).
Build each with the pinned Goose compiler and its own `GOOSE_HOME`, then run
`python3 k1/bench_module.py A_BINARY B_BINARY OUTPUT.json` and repeat for B/C.
Exact executable hashes may vary with the compiler toolchain and build paths.

A separate scalar identity witness compared the legacy release export with the
experimental K1 thin worker. It used 2,000 input-value checks, eight warmup
batches and 31 alternating pairs of two million JavaScript-to-Wasm calls.
The legacy and K1 bodies have the identical Wasm instruction bytes described
above. Median observed times were 10.91 and 10.99 ns per call respectively;
the median paired K1/legacy ratio was 1.001, with p10–p90 0.969–1.061.
The JavaScript loop, input generation, call boundary and JIT are included,
so this is a narrow witness rather than a reliable statement about generated
kernel throughput. The samples do not establish that either compiler is faster.

Ordered samples and runtime metadata are in
[`identity-runtime.json`](measurements/2026-10-26-scalar/identity-runtime.json),
with cgroup snapshots in
[`identity-cpu-before.txt`](measurements/2026-10-26-scalar/identity-cpu-before.txt)
and [`identity-cpu-after.txt`](measurements/2026-10-26-scalar/identity-cpu-after.txt).
The exact tiny test binaries are
[`legacy-id.wasm`](measurements/2026-10-26-scalar/legacy-id.wasm) and
[`k1-thin-id.wasm`](measurements/2026-10-26-scalar/k1-thin-id.wasm); their
SHA-256 values are recorded in the JSON. Re-run the witness with
`node k1/bench_scalar_runtime.mjs LEGACY.wasm K1.wasm OUTPUT.json`. These
binaries are test fixtures, not a K1 host interface or a release artifact.
