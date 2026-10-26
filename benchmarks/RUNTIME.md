# Bounded runtime follow-up

This pass follows draft [PR #43](https://github.com/mewhhaha/blot2/pull/43).
It implements two reviewed lowering changes and stops after one fixed measurement
pass. Both changes are retained; no further optimization candidates were tried.

## Implementation and qualification

Frame planning now uses the same register-transfer predicate as edge emission.
Edges that already move scalar/flat values through Wasm registers reserve no
physical phi scratch. Nonflat edges retain the complete parallel-copy fallback;
owned sealing retains its separate scratch. Source admission, public preflight
and conservative resource bounds remain unchanged.

Known four-byte payload copies use an integer load followed by an integer store.
Dictionary-sized copies evaluate their byte count once and select that word path
for four bytes, otherwise retaining bulk copy, including zero bytes. Known other
fixed sizes keep their existing bulk path. This avoids dynamic bulk-copy overhead
for scalar values in shared generic bodies. Load-before-store preserves overlaps
and exact F32 bits. Argument/result slots remain distinct, with one generic body
and the existing ABI. Telemetry still counts every logical copy once.

Three Sol agents reviewed the candidates and the concrete implementation.
The full Linux release gate passed **116 native entries, 92 Deno integration
tests, editor scopes and 29 formatter round trips**. New laws cover register-only
loops/joins, simultaneous mixed/F32 swaps, nonflat fallback, conservative frame
rejection, exact copy telemetry, 0–256-byte copies, unaligned overlaps, raw NaN and
signed-zero bits, and bounds failures without partial writes.

Final compiler: `94b3d24012f8868a8eb7e8e6351edcfea9529c3d7de36845d10b0b2e47f032bd`.
Input manifest: `27e9627f595ffe94ff0a2955c600ef977cd1262638152326700716c8fb85d67e`.
[The immutable evidence package](results/runtime/manifest.json) binds all
197 qualified inputs, full gate evidence, baseline sources and 228 measurement
records. The baseline is commit `900ede209ca16b9728347fbcea58d44228a3b16f`, compiler
`ca49141eea94f5f3e1cb3d87930bb41b5409e5dedc777b991c6ed6b2eebcf527`.

## Measurements

Five counterbalanced before/after pairs use `--opt=off` on both qualified release
compilers. Each Wasm artifact runs in a fresh Deno process, so previous samples
cannot retain JS inline caches or Wasm code in that process. Instantiation,
20,000 warmup calls and reference checks are outside the timed 20,000 calls.
Inputs cycle through seven deterministic seeds; exact integer/F32 reference models
and timed checksums guard every result. The JS/Wasm boundary remains included.
Default V8 and `--no-liftoff` optimizing-only results are reported separately.

A recurrence call performs 1,024 wrapping-integer steps; an affine call performs
128 separately rounded F32 steps. Generic variants pass values through the same
shared identity body on each iteration. The eight-byte pair exercises the bulk
fallback. These are loop kernels, not a migrated application. CPU placement,
frequency, load and filesystem cache remain uncontrolled on the shared workstation.
All samples and ranges are retained. The harness smoke check was functional only.

Default-engine medians, microseconds per complete kernel call:

| Kernel | Previous µs | New µs | Paired new/previous | Paired range |
| --- | ---: | ---: | ---: | ---: |
| Integer recurrence | 1.051 | 1.041 | 0.999 | 0.973–1.045 |
| F32 affine loop | 0.149 | 0.144 | 0.965 | 0.795–1.003 |
| Generic integer recurrence | 5.795 | 1.267 | 0.220 | 0.209–0.226 |
| Generic F32 affine loop | 0.789 | 0.650 | 0.813 | 0.669–0.933 |
| Generic 8-byte pair | 6.958 | 6.872 | 0.983 | 0.966–1.007 |

The generic integer kernel takes about **78% less time** (paired speedup 4.5×).
The generic F32 kernel takes about **19% less time**. Ordinary kernels and the
aggregate fallback do not establish a material change.

Optimizing-only engine control, microseconds per complete kernel call:

| Kernel | Previous µs | New µs | Paired new/previous | Paired range |
| --- | ---: | ---: | ---: | ---: |
| Integer recurrence | 1.031 | 1.091 | 1.023 | 0.971–1.062 |
| F32 affine loop | 0.144 | 0.144 | 1.001 | 0.980–1.166 |
| Generic integer recurrence | 6.108 | 1.213 | 0.206 | 0.194–0.229 |
| Generic F32 affine loop | 0.742 | 0.647 | 0.847 | 0.706–0.901 |
| Generic 8-byte pair | 7.012 | 6.960 | 1.004 | 0.972–1.016 |

The same directional improvement survives this control: about **79% less time**
for the generic integer kernel (4.9× paired speedup), and **15% less** for generic
F32. It is not a reason to substitute optimizing-only numbers for default-engine
performance. This is a combined comparison, not independent ablations of the two
changes; the removed bulk transfer is the direct mechanism for the scalar-generic
improvement.

## Physical evidence and compile controls

The plain affine body drops from 138 to 93 Wasm bytes and from eight physical
frame bytes to zero, while its conservative body frame bound stays eight bytes.
The integer recurrence's physical frame falls from 20 to eight bytes. The generic
integer/F32/pair caller frames fall from 28/16/36 to 16/8/24 bytes; their certified
body bounds remain 1,052/1,040/1,060 bytes. Public preflight still checks the original
source contract. These are frame reductions, not claimed whole-process RSS savings.

The single shared generic identity body grows from 17 to 50 bytes for the guarded
word path. No additional source body or specialized ABI is emitted. Exact binary
hashes, source-function frames, local groups and body sizes are archived in
`build/runtime-pass-attribution/kernel-layouts.json` inside the evidence package.

Nine synthetic compile controls at scale 128 (chain 127) have paired whole-process
time ratios of 0.959–1.023. They do not establish a material compile-time change.
CPU/RSS and phase records are retained. Their short runtime loops are correctness
checks only; runtime conclusions above use the isolated kernel harness.

No new legacy comparison, gdev migration, retained-edit measurement or compiler
rebuild-time claim is made in this pass. Inlining policy and its previous unresolved
runtime results remain separate. The bounded pass is complete; further work should
start from a new workload/profile question rather than continuing to tune these
five kernels.
