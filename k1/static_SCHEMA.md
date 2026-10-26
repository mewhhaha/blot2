# Private static scalar evaluation fixture

This experiment evaluates one source-bound `static let` declaration of U32 or
F32. It independently re-recognizes its restricted source and operation tree;
then it evaluates checked/wrapping U32 arithmetic and individual F32 operations,
with positive canonical arithmetic NaNs. Its limited F32 literal grammar admits
only exact nonnegative `N.0` or `N.5` forms within its documented bounds.
General decimal conversion, declaration dependencies, calls, arrays, static
storage publication, effects, and source-level admission are unsupported.

Its 100,000 primitive-step ceiling uses the K1 numeric limit but is only this
fixture's partial accounting, not the complete required-static policy. The
128-node expression-tree depth is a **private conservative engineering cap**;
it is distinct from and does not implement K1's static call-depth limit of
128. The parser also has its own parenthesis/nesting cap. The 4 MiB output
budget helper is exercised at its boundary, but the executable source subset
only produces one four-byte scalar and cannot reach that bound. None of these
checks replaces the shared 1,048,576 semantic-visit ceiling or an authenticated
compiler-wide receipt. Failure returns no value and never requests runtime
fallback; private statuses are not qualified K1 diagnostics.

F32 evaluation assumes IEEE binary32 round-to-nearest and Goose's documented
little-endian serialization support. Operations materialize each intermediate
at binary32 width; the fixture does not enable reassociation or fused multiply
add. The random F32 differential is bounded test evidence, not a proof for
every host or a complete K1 numeric implementation.
