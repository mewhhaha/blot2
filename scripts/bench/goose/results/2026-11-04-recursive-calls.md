# Direct recursive calls — 2026-11-04

The unchanged Goose merge-sort and quicksort ports now compile and execute.
Closed named functions may recurse directly over U32 bounds and existing fixed
Array U32 owners, returning Unit. Recursive bodies and reached helpers cannot
allocate, resize, freeze, transfer owners, access globals, suspend, call
indirectly or form mutual cycles. Broader recursion remains separate.

The [evidence](2026-11-04-recursive-calls.json) pins sources,
compiler/toolchain, work, samples, Wasm, memory and incomplete qualification.
Release compiler SHA256:
`f90931ef17ec2b143f880db68253d54392ec4f19a44e9eb58ff09b587d6d967b`. The frozen
baseline is `2de96d223cced8d71bbf4a5ebf2d875ed92a2445a7ef7abb556c8ec7e81c8d19`.
ABI 8, session protocol 2, saved schema 26 and sibling source/assets are
unchanged.

## Recursive boundary

A complete direct header precedes body construction. Semantic owner aliases
remain in its identity; physical aliases, runtime bounds and local IDs do not.
Recursive headers never narrow parameters or use addressed/packed transport.
Only the matching private self edge may use the provisional header; failed
construction rolls back dependent executable plans and committed counters.

Finite invariant plain-owner access stays separate from ordered access events.
Existing accessed rows must be initialized or vacuously empty. Reads reach
surrounding loop checks; possible writes reject frozen owners and invalidate
literals without proving initialization or nonempty storage, including through
ordinary wrappers. Recursive components require no guest scratch.

The outliner now proves strongly connected components disjoint from each live
bank group. Ordinary recursion below a banked caller is allowed. Cycles
containing a bank member and reachable unknown indirect dispatch still reject
publication. Astra reviewed the design and two implementation passes.

## Checked benchmark pairs

Five fresh uncached builds include startup. Both official input sizes, 100,000
and 400,000, pass independent checksum and observable revision checks. Five
warmed bounded pairs retain production problem sizes with reduced iteration
counts. Sorts use four measured iterations after one kernel warmup; these are
not official production scores. Both execute in Node 24.22.1 / V8
13.6.233.17-node.58.

| Sort  | Cold Blot / Goose (ms) | Wasm Blot / Goose (B) | Bounded Blot / Goose (ms) | Paired ratio |
| ----- | ---------------------: | --------------------: | ------------------------: | -----------: |
| Merge |          51.00 / 78.53 |         6,741 / 5,453 |           407.20 / 162.07 |        2.54x |
| Quick |          52.74 / 80.72 |         6,244 / 4,566 |           175.30 / 116.05 |        1.51x |

Each binary has one recursive function with two self-call sites, verified in the
actual Wasm. Merge retains ten i32 inputs; quicksort retains six. Including the
storage/runtime functions, their modules contain 34/32 functions. Separate
compiler profiles take 8.75/8.15ms internally, with checking 5.20/4.95ms and
backend 0.99/0.89ms. These diagnostic clocks differ from uncached process wall.

All seven adapted pairs now pass: six original-numeric workloads and the
explicit Mandelbrot F32 control. The five preceding numeric binaries remain
byte-identical; no runtime improvement is claimed for them. Current bounded gaps
remain 8.10x CRC32, 6.95x custom hash, 2.93x Sieve and 1.88x F32 Mandelbrot;
Fannkuch is near parity. Byte buffers use U32 in Blot and U8 in Goose. Original
F64 and the other 43 catalog tasks remain outside paired coverage. README charts
include all seven pairs; no unsupported sort cells remain.

## Gdev control

Three fresh uncached pairs, seeded side order and no deliberate concurrent
measurement work, retain identical source and toolchain.

| Metric                    |     Before |      After |
| ------------------------- | ---------: | ---------: |
| Compile median            |     5.615s |     5.732s |
| Median absolute deviation |     0.090s |     0.016s |
| Main bytes                | 10,253,029 | 10,253,029 |
| Main functions            |      9,440 |      9,440 |

The median rises **2.1%**, with paired differences +117/-21/+234ms. Keep this
small regression visible; this feature is no Main compile-speed win. Main's
SHA256 remains
`148bf08353aa302e2462e15488728a18a036fa71dfc7d7aedd192a235ee05833`.
Sub-five-second, subsecond and 1–2MB targets remain unmet.

One separate same-artifact profile records backend 4.769s, checking 0.513s,
lowering 0.131s and validation 0.108s. Backend requests 5.30GB cumulatively;
peak process RSS is 1,102,832KiB. Requested bytes are not peak memory, and
overlapping timing families do not add. Main's recursive discovery examines
4,029 source bodies / 169,617 nodes but admits no recursive component. Discovery
counters are inclusive of nested planned calls, not unique-node cardinalities.

A fresh real NVIDIA frame passes the original memory budgets. Its inspected PNG
and guest trace match the baseline exactly; see
[frame evidence](../../../../tasks/storage-handoff-evidence/2026-11-04-recursive-calls-frame.json).
Broader gameplay/software-adapter coverage remains pending. Gdev is `38af070`,
Ink `ccaf08f`, Pen `d159492`; their source/assets remain unchanged.

## Qualification

- All 2,983 native laws compile without LLVM; 419 affected laws pass sampled
  faults. Seven new laws pass full-fault mode, including three exhaustive
  sweeps.
- The development family passes 252 native laws and 242 guest tests in 53.1s,
  with formatting, types and zero Zig lint findings. Native development rebuilds
  take about 7s for the compiler / 16s for the complete inventory. LLVM was used
  only for the final measurement candidate.
- All 24 recursive guests pass both codegen tiers, including depth512, both
  branches, owner aliases, unused inputs, repeated exports, trap recovery,
  negative admission/retry and a forced outline-bank caller.
- Affected release guests pass 324/326. The summary-job ECS export and optimized
  iter.take(0) allocation failures both reproduce on the frozen compiler.
- The full gate passes smoke/harness and 200 native laws, then stops at 133.4s
  on a source-input primitive-arity diagnostic mismatch: expected `call_arity`,
  found `module_loader_required`. The frozen source snapshot reproduces it
  exactly; all 294 frontend files are identical. It has zero leaks/logged
  errors.

**Full compiler qualification remains pending.** This checkpoint implements the
[first recursive slice](../../../../tasks/RECURSIVE_CALLS.md), not the entire
owned-storage rewrite. Main's next separate hill remains structured-control copy
coalescing; sort support does not establish its latency or size targets.
