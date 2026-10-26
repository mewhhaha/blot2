# Private syntax and completion experiment

This isolated function-body experiment is not connected to the driver, and it
is not K1 source admission, typed Core, executable lowering, or full completion.
It recognizes only `do:` suites of `return expression` and nested `if expression:`
with optional `else:`. Expressions cover valid identifiers, U32 decimal literals,
Boolean literals, grouping, one-expression calls, and `&&`/`||` at their specified
precedence and left associativity. A call is syntactic only; neither its callee nor
any name is resolved. Unit, tuple and multi-argument calls, all other expressions,
declarations, value blocks, other transfers, and top-level declarations are not
implemented. Only `return` is represented, targeted implicitly at the enclosing
function by this function-body-only context. No emitted executable uses this tree.

`flow_parse` produces an owned source snapshot and postfix node array with
one-based child IDs. Spans are half-open. `flow_verify` independently recognizes
the complete owned source using the shared lexer and checks every postorder tag,
span and child against the proposed tree, including the root and absence of extra
nodes. Neither this check nor structural completion resolves names, checks types,
effects, ownership, proofs, resources, or operation semantics. Calls are
opaque and may not be treated as effect-free, terminating, or correctly typed.

`flow_completion` first invokes the independent recognizer and then computes a
syntactic fallthrough/unreachable summary. It recognizes only direct Bool
literals (and transparent grouping) for reachability; it does not use optional
constant folding or facts. Other conditions are unknown. A return terminates its
path, and sequential code after an unconditional transfer is reported as
unreachable. This prototype conservatively reports such code inside even a
literal-pruned branch. Thus its output is not full normative K1 completion.
The prototype's 2,048-node and 64-parser-frame caps are local engineering limits,
not the K1 semantic budget or a claim about valid K1 source. All operations are
unmetered and cannot produce a shared work receipt or a trusted artifact.
