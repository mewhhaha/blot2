# Private static aggregates with pure scalar calls

This bounded source experiment accepts a module in the existing checked pure
U32 scalar-function subset followed by a required-static tuple or homogeneous
array of tuples. A tuple component may be an existing U32/F32 scalar
expression or one direct U32 function call taking a U32 literal. A direct call
must occupy the entire component. Calls within arithmetic, F32 calls, captures,
foreign effects, arbitrary expressions, records and variants are unsupported.

The producer uses a length-preserving projection of each supported call to
recognize the aggregate shape. The verifier independently re-lexes the exact
original source, reconstructs that projection and every call record, resolves
callee names against the independently checked module and source Core, and
requires every projected call to match one complete component. No projection,
caller-selected number or forged call record is authority by itself. Duplicate
top-level names, cycles, undeclared calls and unsupported bodies reject.

The private evaluator executes fields left to right. One budget is shared by
scalar operations, every executed call and aggregate construction, and the
active call stack is bounded at 128. The fixture charges one literal-argument
step, one call and one result-expression step per function, literal operand
steps, existing scalar Core node steps, each completed tuple, and array
construction. It counts final output bytes once. These fixture costs are not a
complete K1 semantic or C09 cost schedule. The 4 MiB helper is enforced, but
this bounded input cannot produce 4 MiB before its other limits. The 128-node
scalar-expression cap is separate from active call depth. No shared 1,048,576
semantic-visit receipt is implemented.

Required-static F32 arithmetic uses the existing scalar fixture's binary32
operations and positive canonical arithmetic NaN; non-arithmetic copies and
negation retain their existing bit semantics. Returned bytes are only private
fixture values: this does not publish a static global, authenticate a
module-instance Domain, complete declaration dependencies, or constitute a
public static evaluator or K1 admission. Failure returns no bytes and does not
fall back to runtime execution.
