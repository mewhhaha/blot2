# Forwarded collection edit qualification

Issue #17 exposed a size-dependent cost cliff in an otherwise ordinary array
update loop. A direct `array.replace` reused the loop's exclusive array, but a
source wrapper `fn index value values => array.replace index value values`
copied the entire array on every edit. The forwarding proof now admits one
source wrapper that passes every parameter exactly once to an edit primitive,
including a plain alias or parameter reordering. The compiler evaluates actual
arguments in their original order. An observed old array version still forces
copying, and wrappers with extra work or unresolved higher-order calls keep
the conservative path.

The executed-Wasm matrix compares direct, aliased, direct-wrapper, reordered-
wrapper and retained-snapshot forms at 32, 128 and 512 elements in both
codegen tiers. It checks results, rounded allocator traffic, retains and
releases. It also edits the wrapper in a retained compiler session and reverts
it, checking the changed result and byte-identical restored Wasm. At 512
elements, direct and forwarding forms use 409,600 rounded allocator bytes per
100 calls in either tier; the retained-snapshot form uses 210,124,800. These
are recycled allocator traffic, not live memory or an exact copy count.

The focused native collection laws passed 32/32, Zig lint had zero findings,
and the full compiler gate passed 2,505 native laws with full allocation-
failure sweeps and 1,623 guest tests.

The before/after benchmark uses LLVM release compilers built from baseline
`fabbc19` and this change. Reproduce it with
`deno run --allow-read --allow-write --allow-run scripts/bench_collection_wrapper.ts BASELINE CANDIDATE OUTPUT_DIRECTORY`.
It uses the same 512-element wrapped update in both compilers, nine alternating
fresh compiler-process pairs and 31 alternating runtime pairs of 200 guest
calls after warmup. The SHA-256 hashes pin baseline compiler
`5793a89967f1922c72ef39592014677cf4ab278b8146058076f0b42259e27673`,
candidate compiler `1f79d8fbc72caa1fd93b617d5fa9cdce35ca679a95de2841346fea99bafd6baf`,
source `4948dcc3547af4e88d58eb2d56ce88bef9e18ca2b305511d7eb3650b5c6873f9`,
prelude `a7abdffba8c3189b0e2c3df85294daef96616d0e45e27d054214b1c32c90f584`,
and `std/array` `1a11c8ef63fc18fec2515889efc8fdf0fa3030db59e061b43f38c8f0ea506be1`.
Baseline/candidate Wasm hashes are
`553ba4dac610ff195b47dd3cf2f13d4dd7c8878be523575cb1663d2955598e87`
and `b863f67d838ffbedbd7a7efede8407d29c92e009d970c2888e54d9b60b5581ab`.

| Metric (median) | Baseline | Candidate |
| --- | ---: | ---: |
| Guest-call wall time per 200 calls | 3.893 ms | 0.072 ms |
| Paired candidate/baseline runtime ratio | — | 0.0186 |
| Compiler-reported build time | 6.010 ms | 5.991 ms |
| Generated Wasm bytes | 5,773 | 5,664 |
| Compiler allocation requests | 15,390 | 15,358 |
| Guest rounded allocation bytes per 100 calls | 210,124,800 | 409,600 |

The runtime ratio describes this update-heavy fixture, including guest-call
overhead; it does not establish a general application speedup. The short
compiler builds do not establish a compile-time speedup. Issue #17 remains open
for source cost remarks, generic and nominal records, and other conservative
forms.
