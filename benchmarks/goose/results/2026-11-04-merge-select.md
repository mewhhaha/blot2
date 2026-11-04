# Checked merge selection — 2026-11-04

Unchanged merge sort improves **230.88 → 157.72ms**, a **1.466x median paired
speedup** across five fresh release pairs. These clocks cover four measured
400,000-element sorts, including their original copy/clear work, after one
kernel warmup. The fresh Goose gap narrows from **1.97x to 1.36x**.

[Machine-readable evidence](2026-11-04-merge-select.json) preserves compiler,
source, Wasm, host and workload identities, all samples, diagnostic controls and
qualification limits. The source algorithm and benchmark port are unchanged.
Final release compiler SHA256:
`105f0e18734b8eeb7fa53801087f069a8d4591d325f26eea6c4f0416538cecbf`.

## Why the gap existed

Both ports use recursive top-down merge sort and four-byte elements. Goose's
compiler already recognizes the merge loop: it validates complete ranges, loads
the two candidate values once, selects the result and advances cursors without a
data-dependent branch. Blot emitted a branch, selected-source reload, unused old
destination load and larger branch/carry transport, alongside per-access bounds
and per-call owner validation.

A diagnostic V8 profile places 1,558 of 2,064 guest-module leaf samples in
merge, 265 in owner validation, 100 in recursion and 74 in checked addressing.
This includes preparation and warmup; it is not exclusive kernel attribution or
a hardware branch-counter measurement. Source-only caching and arithmetic
masking showed no material gain and were not adopted.

## What changed

A bounded source proof admits the exact two-cursor U32 loop shape. It checks two
ordered exits, indexed source/store correspondence, distinct cursor/output
carries, invariant limits and every SSA branch/backedge identity. Extra
statements, effects, self-dependent stores and changed increments decline. After
ordinary semantic, ownership, read and escape checking, the completed loop
suffix uses two loads, `i32_select`, one store and Boolean cursor increments.

Lazy owner validation, every bounds check, source-source-destination access
order and store-before-increments remain. Both sources reload each iteration,
including aliased input/output. Ties and U32 wrapping remain exact. Same-width
stores preserve traps previously observable at the discarded destination load.
Capacity reservation precedes replacement, and span/snapshot receipts reset. See
[the contract](../../../docs/compiler/CONTRACT.md).

This measured rewrite combines selection, fewer loads and smaller transport;
individual microarchitectural costs were not isolated. It matches a general loop
shape and adds no source API.

| Measurement                      |            Before |             After |
| -------------------------------- | ----------------: | ----------------: |
| Same-engine merge region         |          230.88ms |          157.72ms |
| Wasm                             |            6,991B |            6,810B |
| Fresh Blot / Goose merge region  | 231.94 / 116.48ms | 156.39 / 114.95ms |
| Median paired Blot / Goose ratio |             1.97x |             1.36x |

The native development compiler pilot was screened first; final release Wasm is
byte-identical to it. Headline numbers use fresh release pairs. All official
small and bounded checksums and observable revision checks pass. These remain
bounded repetition profiles, not official full-production scores.

Six other benchmark Wasms are byte-identical across the frozen preceding and
final releases, and match the preceding array-loop survey. The README runtime
chart refreshes merge only; their exact-artifact timing observations are
retained. Its cold-compilation chart remains the preceding full survey. The
fresh five-build merge measurements are available in the JSON evidence, with no
controlled compiler-latency speedup claim.

## Main and qualification

Main is byte-identical at **10,049,963B** and admits zero merge rewrites. Three
fresh uncached pairs measure **5.271 → 5.279s**, with paired changes **-8 / -73
/ +19ms**: no material compilation gain. Original ABI 8, session 2, schema 26
and memory/owner budgets remain. A fresh inspected NVIDIA frame matches the
preceding PNG/trace; broader gameplay and software-adapter checks remain
pending.

All **2,953 native laws compile without LLVM**. The merge development family
passes **8 native / 28 guests in 9.36s**; the four new native laws also pass
full fault mode, including the detached emitter's allocation sweep. All **28
affected release guests** pass, covering aliases, ties, skipped reads,
source/destination trap prefixes, wrapping cursors, recursion and bulk-loop
behavior. The packaged and standalone public API passes four laws. Types,
changed-file formatting and Zig lint pass.

The full gate passes smoke, harness, runtime fixtures and native compilation,
then its native runner exits 130 after **83 passes / 50 full allocation
sweeps**. No failing law was emitted. It stopped before the 180s cap, and the
cancellation cause is not established. **Full qualification remains pending.**
Raw shard output and phase reports are preserved; this incomplete gate is not a
pass.

A filesystem metadata stall inflated one development build to about two minutes
while using about 20 CPU seconds. Pruning 4.01GiB of older disposable compiler
cache objects relieved pressure. Zig retained stale generated-options manifests;
invalidating only empty-input manifests regenerated those files normally.
Source, installed binaries and evidence were preserved. The subsequent
development cycle took 9.36s. One final LLVM release took about five minutes; no
further production source changes followed it.

The remaining merge hill is complete-range bounds reuse and cheaper recursive
owner descriptors. Goose already has the range proof; its exclusive contribution
has not been isolated here. Main's representation/output problem and packed List
integration remain separate unfinished work.
