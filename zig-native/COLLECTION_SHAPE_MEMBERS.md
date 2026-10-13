# Collection length without element inference

The captured project repeatedly asks for the length of arrays containing open
element types and captured functions. Ordinary member specialization
reconstructs those element interfaces even though the checked length body only
observes the container. On one retained edit this contributes 170,960 inference
scopes and 135,269 lexical interface projections.

`Session.shapeOnlyArrayMember` admits an exact checked Core body: a pure,
unconstrained `Array a -> U32` or `List a -> U32` function whose sole operation
is the intrinsic length of its sole parameter. The public and body parameter
variables can be alpha-renamed. The proof checks their respective owners rather
than comparing unrelated type IDs. Concrete element annotations, requirements,
rows, changed bodies, captures and partial applications use ordinary inference.
Admission is independent of the member's spelling.

The method is still prepared through the ordinary named-value path, retaining
its dependency reads. Its original body executes with the original receiver,
providers and source fuel. No type authority is inferred for an element or
captured function, and no constant/member receipt rejection is relaxed. Explicit
nondefault evaluation quotas retain the ordinary path.

## Isolated release measurement, 13 October 2026

Control source is `38e822ded9d65625d4b3cf53ae352f0a8bade570`, with LLVM/Fast
binary SHA-256
`bbf4fb62168a056aa3b55b439c2a509cd0781e2d691f000a809e09ec1bcbd9a3`. The isolated
candidate binary is
`87d19548756acde922233415c2c81c0367dfc4a1c081d23e898bccdcca91cf29`, built with
Zig 0.17.0. Its patch SHA-256 is
`e957a67b8f124fc1cea5ab85fb76849ef4a6cee566b5115faafbadeb26e455b2`.

Seven alternating pairs on CPU 6 use the current frozen gdev snapshot, changing
`floor_half_extent` from 60 to 61 and reverting it. Each revision agrees with
its fresh oracle and the control in Wasm bytes and source fuel (70,330 steps).

| Phase  | Control CPU ms | Candidate CPU ms | Median paired ratio |   Ratio range |
| ------ | -------------: | ---------------: | ------------------: | ------------: |
| Fresh  |       2199.380 |         1919.886 |              0.8739 | 0.8590–0.8758 |
| Edit   |       1232.855 |          961.714 |              0.7793 | 0.7592–0.7832 |
| Revert |       1132.835 |          860.799 |              0.7593 | 0.7527–0.7612 |

Each revision eliminates 220 inference regions. Retained edit scopes fall from
188,816 to 17,856; lexical interface projections fall from 135,269 to zero.
Requested solver allocation falls from 166,861,564 to 82,129,536 bytes and
scratch allocation from 182,393,392 to 41,564,360 bytes. Their peak live
requested memory stays unchanged. Constant receipt activity stays zero on this
capture.

Thirteen public examples, seven alternating pairs each, preserve exact Wasm,
diagnostics, source fuel, requested allocation and peak live memory. CPU ratios
range from 0.9882 to 1.0112. These results qualify this particular consumer
path; they do not meet the remaining total-edit target in task 093.

## Correctness and evidence

Native laws compare Array and List results and source fuel with ordinary
specialization, sweep every allocation failure, and reject changed bodies,
concrete arguments, effects, incompatible expected results and custom quotas.
Both codegen tiers execute retained/fresh method edits, sibling edits, rejected
edits and recovery over open empty elements and capturing callbacks. The focused
development guest batch passes ten laws; 374 analyzer files have zero findings.
The combined source still requires the parent-owned full compiler gate.

Immutable binaries, source patch, pins, all 42 captured samples, public samples
and logs are in `build/bench/continuation-20261013/shape-members-release/`.
Earlier Safe/noLLVM screens are retained separately. The first screen admitted
nothing because its alpha-renamed parameter guard was too strict; its timings
are not evidence for this implementation.

The combined `ae001bb` checkpoint passes the complete native/guest/OOM gate and
release comparisons. See [merged qualification](CONTINUATION_QUALIFICATION.md)
for exact pins, the repaired revert regression and final measurements. Later
prototypes remain separate.
