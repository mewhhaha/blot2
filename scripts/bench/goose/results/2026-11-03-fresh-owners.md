# Fresh fixed-owner call results — 2026-11-03

Reusable calls can now return fresh fixed arrays, including aliases and borrowed
siblings in records. Previously the compiler emitted these helpers, rejected
their new owner IDs, discarded the IR and expanded the body into callers.

Result contracts extend the input-owner roles with compact fresh roles. Each
fresh owner needs a live, nonpersistent, nondedicated fixed-region allocation,
plain inline elements and an unconditional singleton array descriptor outside
variant payloads. The caller imports real returned descriptors at its current
scope depth. Input access events remain input-only. Conditional/mixed origins,
resizable results and borrowed escapes retain fallback or rejection. ABI 8 and
session protocol 2 remain unchanged.

Packets close after result import; enclosing scope rewind preserves live result
extents. Packet owner slots are released immediately, but their bytes can remain
below returned allocations until lexical cleanup. This is a capacity tradeoff,
not a new region or runtime allocator. Direct/buffered calls, scratch holes,
reordered owners, aliases, borrowed views and nested forwarding have dedicated
laws. The 1 KiB cleanup fixture survives 4,096 iterations,
continue/break/return, a bounds trap and a subsequent successful invocation.

[Machine-readable evidence](2026-11-03-fresh-owners.json) pins compiler/source
hashes, commands, samples, counters, failures and qualification. Final compiler:
`1ccf0e50b158971a3fa3d7943be3f6393db4212e61714cfc7ca0835c8b57068a`. Before
compiler: `88709e2adf6f29ff41a2eaf475851964c05f7d48854dc6f3c78031c87d14daa4`.
Gdev, Ink and Pen sources/assets remain unchanged.

## Main: paired fresh builds

Three uncached pairs use randomized side order, identical inputs and startup
policy. This shared-host round's baseline is 6.85s; the earlier 5.81s snapshot
is a different round and is not the before value for this change.

| Metric                                 |     Before |      After |
| -------------------------------------- | ---------: | ---------: |
| Compile median, including session open |     6.848s |     6.526s |
| Main Wasm bytes                        | 12,490,827 | 12,113,691 |
| Emitted expressions                    |    998,564 |    853,678 |
| Completed-plan rollbacks               |      2,009 |      1,464 |
| Discarded expressions                  |    184,212 |    108,775 |
| Declared locals                        |    414,062 |    399,240 |
| Wasm functions                         |      8,267 |      8,627 |
| Local/global instruction bytes         |  8,257,498 |  8,017,336 |

Main is **377,136B smaller (3.0%)**. The observed paired median is **4.7%
faster**, with per-pair reductions of 347, 326 and 138ms. Five-second, subsecond
and 1–2MB targets remain unmet. Discarded expression work falls 41%; more
reusable functions do not imply more total code.

The final compilation publishes 405 owner-transfer definitions and imports 3,297
result-owner roles at emitted call sites. These are compiler work counts, not
runtime allocation counts. The remaining 1,464 rollbacks include 230
fresh/unknown-owner summary declines; the other causes are not classified here.
Do not assume all previous rollbacks were fresh arrays.

A separate profile emits the exact same Main artifact. Its exclusive backend
phase is **5.440s**, checking **0.565s**, lowering **0.139s** and validation
**0.121s**. Backend allocation requests total 5.00GB cumulatively; this is not
peak memory. Whole-process peak RSS is about 1.17GiB. The backend remains the
main latency target.

## Runtime controls and integration

All five numeric Blot kernel artifacts are byte-identical to the preceding
checkpoint. Five fresh-process before/after pairs remain checksummed controls;
their timing fluctuations are not new code-generation gains. The README charts
rerun the same seven adapted Goose cases with the final compiler: five matched
pairs and two explicitly unsupported recursive Blot sorts. Original F64
Mandelbrot remains unsupported; the F32 control is labeled. Byte buffers retain
the U32/U8 representation difference.

World/editor and hand return identical sync/async results. Their Wasm sizes are
488,432 → 479,110B and 197,860 → 198,598B respectively. Seven renderer lane
streams match; its small control grows 91,228 → 92,016B. These small regressions
remain visible. Final Main passes the original 2 MiB temporary / 256 KiB
persistent / 4096-owner frame configuration. Its inspected NVIDIA PNG and guest
trace are byte-identical to the baseline; see
[frame evidence](../../../../tasks/storage-handoff-evidence/2026-11-03-fresh-owners-frame.json).
Broader gameplay and software-adapter coverage remain pending.

## Correctness and qualification

Broader checks also exposed a preexisting primitive-alias bug: selected
compile-time operators required a syntactic function with an exact parameter
count. Alias bodies have zero syntactic parameters. Nonexact calls now use the
existing typed callable/application path; exact named calls keep their seeded
fast path. Staged conversions/operators, division traps, allocation faults and
separate effect providers are covered. Missing-provider constants still fail
purity checking. Two stale reader/inline counter assertions were corrected only
after frozen-baseline and current controls produced identical values/counters.

All **2,954 native laws compile** with Zig 0.17/noLLVM. The two affected
families execute **390 unique native laws** successfully. Ten focused laws pass
full fault mode, including three exhaustive allocation sweeps. The initial
ownership development family passes 219 native laws and 198 guests in 58.52s.
The final LLVM guest union executes 282 tests: **280 pass**, with two failures
reproduced on the frozen baseline: the ECS summary-job fixture is unsupported,
and the legacy optimized `iter.take(0)` fixture still allocates. Neither is a
pass.

The full gate passes 49 smoke and 57 harness checks, then stops at its 180s
budget: 102 completed native laws, 76 full sweeps, zero failures/leaks/logged
errors. **Full qualification remains incomplete.** Zig lint is clean.
Development compiler builds remain 5–6s; complete native compilation is 10–11s.
The fast noLLVM whole-game probe stopped at 30s. Two final LLVM builds were
needed because the wider checks found the earlier constexpr bug; both take about
five minutes. Only the final compiler's timings are reported above.

## Next experiment

Measure physical duplication in wide callback environments. Gdev's
`world_storage.with_owners` creates four callbacks capturing the same wide base.
The semantic owner graph deduplicates owners, while physical call words still
flatten records and captures. First test a separate descriptor-donor table for
unconditional singleton array inputs, then let existing demand passes omit
repeated word groups. Mixed-root descriptors and inactive variant payloads are
unsafe donors; the existing root-assignment table cannot be reused for this.
Keep index/length snapshots, effects, owner identities and logical packet
bounds.

Use width-32/128 bundles, one/four captures, one/eight calls and mixed-root /
inactive-variant controls before another game build. Immutable addressed
aggregate environments are the larger follow-up if descriptor sharing is
insufficient. The remaining local/global bytes are not all removable copies;
reaching 1–2MB also requires sharing surrounding operations and control flow.
