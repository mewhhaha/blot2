# Private static products, arrays and scalar calls

The product experiment accepts a required `static let` whose initializer is a
tuple of 2–16 U32 or F32 scalar expressions, or a nonempty `#[...]` array of
homogeneous tuples of that shape. It lexically replays the retained source and
independently rechecks each component's scalar Core before evaluation. Fields
are evaluated in source order and returned as little-endian immutable bytes;
arithmetic NaNs use positive canonical `0x7fc00000`. This reuses the existing
scalar fixture's limited float literals, host binary32 assumptions, expression
depth cap and semantics. It cannot publish a static global or create a real
module-instance Domain, and supports neither standalone scalar arrays, empty
arrays, records, variants, arbitrary declarations nor nested aggregate values.

The local meter charges each evaluated scalar Core node, each finished tuple,
and each array construction. It charges final bytes once, not intermediate
scalar temporary bytes; this explicit fixture schedule is not a complete K1
primitive cost model. One shared counter is checked before each primitive;
failures produce no returned data. Output is capped at 4 MiB by the shared
helper, but that boundary cannot be reached within this syntax and 100,000-step
limit. The existing 128 expression-tree cap is not K1's call-depth limit.
There is no shared 1,048,576 semantic-visit receipt.

The separate scalar-call experiment accepts a finite module of the already
checked noncapturing `U32 -> U32` identity, bit-and, or direct-tail-call source
forms followed by a single required-static U32 literal call. Source and Core
are rechecked by the existing module recognizer and independent graph verifier;
unknown targets, cycles, unsupported effects and declarations reject. Its
call depth measures active source calls, including the first, and is capped at
128. The local meter charges the initializer literal, each call and result
expression, and literal operands. It is not a general K1 cost schedule. Calls
are not yet supported inside product or array elements; no declaration
completion, arbitrary closure or runtime/foreign effect is implied. Both
experiments return failure rather than runtime fallback and remain private
fixtures, not general static evaluator or K1 admission.
