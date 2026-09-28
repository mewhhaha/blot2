# Layout propagation

This extends the pointer-free array optimization from `f46baf4`. The earlier
runtime measurements remain historical results for their recorded revisions.

## Representation evidence

`codegen_layout.bend` records unknown words, scalars, pointers to scalar arrays,
and pointers to products with per-field evidence. These are representation
facts, not a second type checker. A scalar-array pointer is never a scalar word.

The emitter carries this evidence through lexical bindings, product fields,
pattern bindings, array reads and branches that agree on representation. Fresh
products containing only scalar words now receive the same pointer-free header
bit as scalar arrays. This includes record payload products; constructor
wrappers still contain a pointer and remain traced.

Only normalized instruction-job contents contribute facts. Erased annotations,
other function bodies, constant contents and global metadata do not influence
emission, so existing exact instruction-cache keys remain sufficient. Function
parameters, captures, unknown calls and constructor-pattern payloads stay
unknown. Loop indices are scalar; loop-carried state is not inferred from its
initial value. Unknown shadowing bindings remove outer facts.

Blocks stay unknown because nonlocal returns may bypass their last expression.
Branch joins only retain agreed facts. Structural recursion has a depth budget
of 32; exhaustion loses evidence instead of rejecting a valid program. Exhausted
pattern traversal clears facts rather than retaining stale outer bindings. This
is a bounded conservative analysis, not a complete type/layout proof.

The runtime header size, ABI, allocation cadence and immutable-update ownership
rules are unchanged. No generated Bend C or JavaScript is patched.

## Tests and measurement

`codegen_layout.test.ts` exercises evidence propagation, joins, shadowing,
nonlocal control flow and budget exhaustion. `layout_propagation.test.ts` checks
actual allocation flags in compiler-generated Wasm, not only return values. Its
native and JavaScript cases cover pointer-looking integers, scalar record
payloads, reference-containing tuples and 10,000-iteration captured-closure and
nested-array loops. Existing relocation and incremental cache tests remain in
the native regression gate.

```sh
# Build both checkouts with the same Bend release and matching loader.
python3 scripts/build_runtime_reference.py
deno task generate:parser

# In the new checkout; baseline is the previous PR head f46baf4, not main.
deno run --allow-read --allow-write=build compiler/layout_bench.ts /path/to/before
```

The layout workflow independently builds both revisions and records exact source
identities. Eight runtime cases use eleven alternating samples, at least 200 ms
and 32 warmup calls per implementation, and identical batch lengths. Every
measured result is checked outside the timer. Memory high-water marks and Wasm
sizes are retained. Two separate full-source-compilation cases report the cost
of doing the analysis, rather than conflating runtime gains with compiler speed.

Retained-buffer cases deliberately isolate repeated conservative scanning and
can produce large ratios. They are not application-wide speedup claims. Unknown
parameter and allocation-free controls are reported alongside optimized cases.
Timing ratios are diagnostic and do not decide whether CI passes.
