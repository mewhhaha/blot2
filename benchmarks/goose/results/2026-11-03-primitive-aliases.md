# Scalar primitive aliases — 2026-11-03

Thirty terminal U32/F32 prelude wrappers are now direct primitive aliases, such
as `const F32.mul = @f32.mul`. Scalar primitives use ordinary function typing,
partial application and callbacks; literal-sensitive storage/SIMD operations
retain their exact-call rules. The owned backend keeps named functions, closures
and primitives distinct while sharing their callable type/identity contracts.
Generic associated dispatch and nominal operators remain.

Scalar Wasm lowering now uses the same opcode/result contract as constant
evaluation. Optional exact-bit folding preserves wrapping, masked shifts,
saturation and signed zero, and declines arithmetic NaN payload choices.
Ordinary compile-time evaluation still accepts NaNs. Computed constants never
acquire source-literal authority. Concrete primitive callables retain no
unrelated type environment; partial scalar captures snapshot their current
value.

[Raw pinned evidence](2026-11-03-primitive-aliases.json) contains
source/compiler hashes, commands, samples, checksums, failures and
qualification. The final LLVM compiler is
`88709e2adf6f29ff41a2eaf475851964c05f7d48854dc6f3c78031c87d14daa4`; the
preceding compiler is
`89cd47f3b9a3d4bbfa37857edb6b974d0e8bbf11432c3a4531f44d3b51c96bcb`.

## Paired Blot runtime

Five fresh-process pairs rerun preserved before and final after artifacts, with
seeded side order, identical bounded parameters, internal warmup and checked
checksums. These are V8 shared-host observations, not official LangArena scores.

| Kernel         | Before median (ms) | After median (ms) |
| -------------- | -----------------: | ----------------: |
| Fannkuch       |              14.00 |             13.96 |
| CRC32          |             109.33 |            112.09 |
| Custom hash    |              99.01 |             98.87 |
| Sieve          |              60.95 |             61.02 |
| Mandelbrot F32 |              96.04 |             73.18 |

Mandelbrot uses **23.8% less kernel time**, with a median paired speedup of
1.318x. CRC32 is 2.5% slower by ratio of medians; the other three are
effectively flat. Mandelbrot reports no new scoped constant folds: removing
forwarding boundaries changes generated calls and V8 optimization, but these
measurements do not isolate its engine decisions. The earlier source-only
constant control is retained in [the survey](2026-11-03-expanded.md).

The separate five-pair Goose comparison now shows Blot/Goose ratios of 8.29x
CRC32, 6.98x custom hash, 3.07x Sieve, 1.86x Mandelbrot F32 and 0.97x Fannkuch.
Both recursive Blot sorts still fail explicitly and receive no timing. Original
F64 remains unsupported; only the explicit F32 Mandelbrot control is compared.
Blot byte buffers remain U32 versus Goose U8. The README charts use this final
compiler; coverage remains five matched pairs out of seven adapted cases.

## Gdev and size

Three fresh uncached pairs include session startup, use the corresponding
prelude for each compiler and verify the old Main artifact is unchanged.

| Metric                         |     Before |      After |
| ------------------------------ | ---------: | ---------: |
| Main compile median            |     5.860s |     5.814s |
| Main Wasm bytes                | 12,476,667 | 12,490,827 |
| Wasm functions                 |      8,041 |      8,267 |
| Declared locals                |    413,352 |    414,062 |
| Local/global instruction bytes |  8,254,281 |  8,257,498 |
| Completed-plan rollbacks       |      2,009 |      2,009 |
| Discarded expressions          |    181,762 |    184,212 |

Compile time is effectively flat; Wasm grows 14,160B (0.11%). Main performs
3,426 scoped exact constant folds, but this does not move the large transport
and expansion bottleneck. Five-second, subsecond and 1–2MB targets remain unmet.
The noLLVM debug integration probe stopped at its 30-second cap and is excluded
from release comparisons; it was not repeated.

World/editor and hand checks return identical results synchronously and
asynchronously. Their Wasm sizes fall 488,909 → 488,432B and 198,167 → 197,860B.
Seven renderer scenarios produce identical lane streams. The final Main passes
the headless NVIDIA frame checks; its inspected PNG and guest trace are
byte-identical to the preceding checkpoint. See
[frame evidence](../../evidence/integration/2026-11-03-primitive-aliases-frame.json).
Broader gameplay and software-adapter coverage remain pending.

## Qualification and next hill

All 2,945 native laws compile with Zig 0.17 and noLLVM. The affected 214-law /
196-guest development family passes in 52.42s; the same 196 guests pass with the
final LLVM compiler. Nine focused native laws pass full-fault mode, including an
exhaustive partial-capture allocation sweep. Coverage includes eager sync and
async callbacks, same-helper partial captures of 2 and 9, scalar-reference
mutation, callable identities, conversions, traps, NaNs, signed zero, nominal
operators and receiver-bound aliases. Zig lint is clean; Astra's final review
found no remaining blocker. Full compiler qualification remains pending; its
bounded gate passes 49 smoke and 57 harness checks, then stops at its 180s
budget during exhaustive native execution: 110 completed laws, 83 full sweeps,
zero failures/leaks/logged errors. This is incomplete, not a pass. Exact gate
phases and completed native records are retained in the JSON.

Next address the unchanged **2,009 completed-plan rollbacks**, especially fresh
fixed-array results: reusable calls need an explicit owner-transfer contract
instead of expanding their bodies into callers. Do not widen the 512-word ABI
selector; it already admits buffered calls. CRC32's conditional shift/XOR
recurrence remains the largest measured kernel gap. Numeric wrappers were a
useful simplification, but they are not Main's dominant size problem.
