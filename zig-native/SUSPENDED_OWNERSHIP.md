# Suspended ownership

Task 033 extends [counted roots](PERSISTENT_ROOTS.md) to generated host
callbacks and request execution. The nonmoving tracer still reclaims unreachable
cycles; trial deletion and tracing removal remain tasks 034 and 035.

## Admission and owners

Only exact generated `blot:host/1` imports are admitted: canonical callback
name, externref argument, checked numeric/Array argument and checked result
signature. Unknown imports retain whole-module tracing fallback. Externrefs
belong to a separate host table; they are never guest heap edges.

The invocation journal remains live while JSPI suspends. Guest Array arguments
are borrowed until the host copies them; a numeric Array reply is freshly
allocated in that same invocation before resumption. Request cells own checked
exit/state fields, decisions own checked reply/state fields, and result pairs
own checked final-state/result fields. Replacements retain before dropping old
edges. The dispatcher reads the immutable cell layout to select the checked
state role when constructing a result pair.

Runtime helpers cannot cancel requests. Removing cancellation guards after those
helpers preserves allocation provenance and avoids repeated checks. Source
calls, indirect calls and host imports still check cancellation.

## Failure, cancellation and teardown

A force registers its active demand before publishing `evaluating`. Its journal
record owns a dynamic demand; static demand addresses need no counted heap edge.
Failed invocation cleanup changes any remaining evaluating demands to terminal
before releasing frames. A ready memo remains ready and strong.

Request return/break cancellation resets the interrupted demand to pending; it
can retry. A host rejection or Wasm trap terminalizes the interrupted force.
These are separate transitions. JSPI offers no Promise abort operation: while
settlement is pending, the guest rejects reentry and disposal and keeps all
owners until success or rejection settles.

Invocation leave clears the externref table on success and failure, including
traps that skip the callback wrapper's normal epilogue. Teardown releases module
roots and clears host references, then resets the retained tracer to reclaim
unreachable cycles. Raw ABI callers must invoke the matching leave hook after a
trap or rejected Promise and discard the instance after teardown.

## Revoked capabilities and strong memos

A ready memo can own a host closure beyond the invocation that supplied it.
Clearing table slot zero and reusing it would silently bind that old closure to
a later host callback. The closure instead carries its own descriptor identity
as a borrowed token plus its table handle. The host stub checks that identity
against the active descriptor before reading the table handle.

A live cached descriptor cannot be reallocated at the same address. A later
invocation therefore rejects the revoked closure instead of invoking its new
callback. The memo stays ready and retains its original closure; no cache is
weakened and no generation counter can wrap. The descriptor grows from 8 to 12
bytes, still in the same 48-byte allocator class with the 32-byte header.

Trace: first invocation supplies A, forces the memo and calls A(41) to
obtain 42. Leave revokes A. A second invocation supplies B; the ready memo still
contains A, so its identity check traps and B has no event. Failed leave clears
B's table slot and invocation owners. An unrelated pure entry still executes;
teardown finally releases the strong memo.

## Focused evidence

Native laws cover immutable Core and exact fresh/retained/checkpoint/full-replay
Wasm, allocation failures and rejected import namespace/name/signatures.
Executed laws assert mode 2 admission, owners while JSPI is pending, Array
packet copies, settlement/rejection cleanup, request snapshots, terminal failed
forces, retryable cancellation, revoked memo capabilities and repeated
invocation retirement. The fallback, source-limit and existing demand laws
remain mandatory.

## Isolated release costs

The incoming code tree is `6064c8e2d114bfb39ab3c78d5c0b295f51f1be15`. Its
qualified Fast executable SHA-256 is
`b802365944a69db01df83442db960a8fd7b717828f7cbb1ac5aba2b661d80d17`. The final
suspension candidate is
`148ff0f95e4a8ce07a87988a96e2d1f37bbafbc32dee59578229597c6ec2305a`, with
compiler-input identity
`983af2f5263eb3fa3cc8e2047eed8623323f0d869fddf5da6e9fc3bb290f0d4b`. The initial
candidate `63dd5af5b6b467399213bcd8db4f3e646ee50456123adbaa43bce5889fd66db4` and
its measurements remain separate historical evidence.

Zig 0.17.0 Fast / LLVM builds used CPUs 0–5. Paired measurements used CPU 6;
load, source/harness hashes and every raw round are retained. Compiler medians
use 20 rounds after two discarded rounds; `nativeWorkSteps` match in every pair.
Runtime probes warm each function with 10,000 calls, alternate order for 25
rounds and discard the first five. Times are process CPU milliseconds. Scalar
batches have 10,000 calls; Array and request batches have 2,000. JSPI callbacks
settle through a Promise microtask. These are focused workloads, not a general
performance claim.

| Workload       | Incoming tracing | Candidate | Change |
| -------------- | ---------------: | --------: | -----: |
| Fresh compiler |            6.160 |     6.182 |  +0.4% |
| Retained edit  |            2.448 |     2.502 |  +2.2% |
| Scalar sync    |            2.927 |     5.544 | +89.4% |
| Array sync     |            4.156 |     5.284 | +27.1% |
| Request sync   |            6.480 |     9.322 | +43.9% |
| Scalar JSPI    |           19.724 |    23.929 | +21.3% |
| Array JSPI     |            7.906 |     9.067 | +14.7% |
| Request JSPI   |            9.808 |    12.846 | +31.0% |

The initial frame-per-stub candidate had material callback costs. The exact
scalar-stub proof removes 26 Wasm bytes. A direct initial/final paired probe
measures scalar sync CPU −5.0% and scalar JSPI −2.2%; Array/request controls
stay within about 1%. The remaining cost is material: synchronous scalar
overhead is about 262 ns per invocation. Counted boundary work and actual
destruction replace deferred tracing. This does not satisfy the later 035 final
CPU gate.

The source probe changes from ownership manifest `[1, 0, 2]` to `[2, 2, 0]`.
Wasm grows from 6642 to 7359 bytes, including the counted helpers and exact host
identity checks. Both routes plateau at 128 KiB after warm-up and 2048
additional raw invocations, with the same plateau across measured guest batches.
The candidate restores roots, leases and host references after every invocation.
Scalar callbacks retire one object per call, Arrays four and requests twelve;
requests perform fifteen retains and twenty-seven releases. The tracing baseline
defers retirement and reports zero RC operations. The header, 244-word leaf
geometry and host descriptor's 64-byte class remain unchanged.

Reproduction files are outside source control in
`build/bench/suspended/{compiler-cost,runtime-cost,runtime-subtraction,memory-cost,summary}.json`
and `measure_{compiler.py,runtime.ts,subtraction.ts,memory.ts}`. Historical
`*-initial.json` and the initial executable are preserved. Focused final checks
pass native fresh/retained/checkpoint/replay and OOM laws, 62 request/suspension
laws, 18 host client laws, the live force-record fixture law and zero analyzer
findings across 340 Zig files. Newly admitted host client laws explicitly
require ABI 3 and mode 2; ABI 2 compatibility laws remain.

## Integrated qualification

Task 033 is complete at local implementation `f184dde`. The joint
[qualification record](MODULE_ABSTRACTION_QUALIFICATION.md#integrated-qualification--12-october-2026)
pins the actual integrated source/binary, all 1,400 native and 871 guest/client
laws, eight unchanged allocation budgets, zero analyzer findings across 343
files, and paired public/synthetic costs. Suspended owners, exceptional cleanup,
revoked capabilities and retryable cancellation are qualified with task 032's
roots and tasks 052/038's representation and callback changes.

The focused host-call overhead above remains material. Tasks 034/035 still own
complete cycle reclamation, tracing removal and the final CPU/memory gate.
