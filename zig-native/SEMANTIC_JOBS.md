# Private semantic jobs

Task 012 is under qualification. The serial default remains unchanged.
Performance qualification and any default policy decision belong to task 013.

## Scheduling and identity

`CallSummaries` dispatches at least two ready components. Every member must be
queued or waiting without a live region, and known outgoing dependencies must
already be complete or declined. A recursive component is one job. Components
with distinct closed keys for the same active source owner remain on the serial
path, preserving the existing monomorphic recursion rule. Independent closed
instances can run as separate jobs.

The job borrows immutable Core modules and a const parent Session until join.
Each worker owns a private Session, solver arenas, scratch, evidence importer
maps and diagnostic buffers. It receives the exact Options key, closed input and
expected type/effect evidence, copied primitive scalar inputs and the requested
lexical capture records. It receives no incoming caller proof, plain-data cache,
live solver variable, provider pointer or value handle. No evaluation is
admitted: the worker must leave steps and its seeded value/child lengths
unchanged.

Captured closure records copy source identity, type/row mappings, capture
interfaces, alias ordinals and immutable origin words. Type/effect IDs are
explicitly remapped. Origin words contain parent evidence/value ordinals; they
never index the private Session's capture cache. Requested records have local
ordinals with an explicit map back to the parent. A newly discovered private
lexical key without such an origin map declines the package and stays serial.

An internal work quota partitions the parent's remaining summary transition
budget without changing canonical Options. The quota spans all private
inquiries; it cannot reset when a worker opens another region. Summary
transitions and counters from returned completed/declined results are attributed
to the parent; work abandoned by a throwing allocation failure has no returned
counters. Result publication requires a successful budget charge.

## Joining and publication

The generic batch owns one outcome per input slot. Atomic dispatch assigns each
job once; mutable solver state is never shared. A short locked allocator adapter
protects backing allocation operations. Returned buffers carry no pointer to
that stack adapter. Each worker arena resets between jobs, retaining at most 512
KiB. All tasks join before source, allocator or result teardown.

Cancellation stops subsequent dispatch and joins running jobs. A running solver
finishes within its configured bounds; cancellation is polled between jobs, not
inside every constraint. Per-slot allocation failure and semantic decline do not
erase other completed outcomes. Thread admission failure runs remaining jobs on
the available workers and coordinator.

Each successful component returns an owned evidence snapshot, exact keys,
completed roots and source dependency reads. It includes every completed private
summary, including recursive members and transitive completed dependencies;
provisional and declined judgments never cross owners. Untracked or nested reads
decline the package. If a dependency touches a currently active coordinator
source, the package returns to serial inference so the existing SCC restart can
discover the edge.

The coordinator processes components in deterministic source order. It clones
the destination evidence owner, remaps every type, effect label and row into
that private staged Store, validates original keys/states and conflicting
completed results, and reserves all key/job capacity. Only then does it swap the
evidence owner and publish the complete package without allocation. Import
failure cannot publish half an SCC. On allocation failure, completed independent
judgments survive while pending indices, active state and regions are abandoned.

Independent closed-call certificate batches use the same joined owner.
Successful certificates transfer to a bounded current-query cache before any
fallible consumer cloning. A later sibling or executable-query failure cannot
erase them. They remain private judgments: executable admission and artifact
persistence retain their own checks. Cache lookup rechecks exact current input
evidence, Options, depth, source validity and primitive scalar observations.

The existing artifact adapter assumes positional source unit IDs. It now
declines non-positional current or retained modules before indexing them.
General serial Session inference continues to resolve explicit source
identities. Supporting general source relocation in that adapter remains a
separate migration.

## Public opt-in

Native `build`, `build-project` and `serve-project` accept
`--semantic-workers 1..16`. The direct native project client accepts
`semanticWorkers: 1..16`, validated before process creation. Explicit one-worker
mode uses the same private component path as multiple workers; omission uses the
existing serial path. The framed protocol and checkpoint format do not change.

`semantic_component_batches` and `semantic_component_jobs` report submitted
component batches and jobs, including slots cancelled before execution. Counts
describe components, not exported functions or a promised thread count. Returned
private work counters merge after join; maximum counters retain their maximum
semantics. This path deliberately pays for private Sessions, snapshots and
destination staging. A speedup is not assumed.

## Qualification

Focused native laws cover capture-interface remapping without live handles,
atomic known recursive groups at every allocation failure, distinct U32/F32
closed recursive instances, late active dependencies, declined siblings,
independent certificate retention, dispatch/result allocation failure and joined
cancellation with one and multiple workers. The executed-Wasm law compares fresh
and retained population/edit/revert/no-op, failed source recovery and checkpoint
restart across worker counts.

The candidate is pinned under
`build/bench/cloud-principal-graphs/candidate-semantic-jobs/` against task 011's
immutable `candidate-allocation/` compiler. Candidate compiler SHA-256 is
`c96e7679ac6173b9d3b9bb3a76d78c1904f4be6735f9419406b2390d93554466`;
identity-file SHA-256 is
`c5880517a6eed3c8c2aea91c1a781fe2579944f9d5ca302d0b622e0deb7dfe76`. The sorted
19-file source hash-map SHA-256 is
`b62e0c396ad50979030456be53fc2257909ab8189e237a8e458e5d2ad7336ddd`. The baseline
compiler SHA-256 is
`571c1ccab004a8659553a20b10d5eb2e4b1ad9e680999a59156bc7b66af92c36`. Source
revision will be recorded after the local implementation milestone.

`jobs-comparisons/report.json` compares the baseline, candidate default, and
explicit workers **1, 2, 4 and 8** on **626** source/prelude cases. All
**3,756** invocations match ordered diagnostics and Wasm; **433** cases succeed
in every policy. All invocations report zero live backing bytes and disabled
restart caching. Each opt-in worker policy submits 490 components across this
corpus; both serial defaults submit zero. `jobs-comparisons/execution.json`
executes **192 guests / 10,362 calls** against original fixture expectations.

`jobs-retained/report.json` covers **27** wide capture, canonical capture,
recursive, forward-chain and independent-call workloads across those six
policies. Three population/edit/revert/no-op rounds per retained owner plus
checkpoint restart produce **2,106** successful revision samples. Four fresh
cross-checks per workload/policy add 648 builds; failed-source diagnostics and
corrected-source bytes also match for every owner. **648 guests / 41,208 calls**
check original and edited outputs, including captured scalar/nominal values and
different closed recursive instances. The harness source and workload hashes
remain with these ignored qualification artifacts.

One observed fresh independent-call graph with 128 leaves reports the following
backing allocation totals. This is an ownership/overhead observation, not a
timing distribution or performance qualification:

| Policy                       | Requested bytes | Allocations | Peak live bytes | Submitted components |
| ---------------------------- | --------------: | ----------: | --------------: | -------------------: |
| Task 011 / candidate default |       3,168,641 |       5,941 |         866,693 |                    0 |
| One worker                   |       3,260,073 |       7,870 |         866,693 |                  128 |
| Two workers                  |       3,311,401 |       7,875 |         866,693 |                  128 |
| Four workers                 |       3,414,057 |       7,885 |         866,693 |                  128 |
| Eight workers                |       3,516,713 |       7,895 |         866,693 |                  128 |

`jobs-analyzer-v2.log` checks **297 Zig files with zero findings**.
`jobs-full-gate-v1.log` passes the full LLVM native suite and **620 guest/client
tests** with Zig **0.17.0**. `jobs-package-v1.log` passes the package build,
public API type checks and publish dry run; `jobs-format-v1.log` passes
formatting. Task 013 will record alternating CPU/wall and retained allocation
distributions before deciding any default policy; task 012 makes no timing
claim.

The historical boxed compiler and private gdev snapshot remain unavailable.
Public qualification cannot close that external application gate. Running-job
cancellation latency is bounded by the current solver job, and lexical inputs
discovered without a parent origin still use serial inference.
