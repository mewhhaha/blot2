# Private syntax and completion experiment

This isolated function-body experiment is not connected to the driver, and it
is not K1 source admission, typed Core, executable lowering, or full completion.
It recognizes `do:` suites of `return expression`, value-block `break expression`,
and nested `if expression:` with optional `else:`. Expressions cover valid identifiers, U32 decimal literals,
Boolean literals, Unit, tuples, grouping, calls with zero or multiple syntactic
arguments, and `&&`/`||` at their specified
precedence and left associativity. A call is syntactic only; neither its callee nor
any name is resolved. Nested value `do:` blocks have explicit lexical break targets;
returns target the enclosing function in this function-body-only context. Other
expressions, declarations, loops, other transfers, and top-level declarations are
not implemented. A value `do` nested inside delimiters is not supported because the
current shared lexer suppresses structural indentation inside delimiters. No
emitted executable uses this tree.

`flow_parse` produces an owned source snapshot and postfix node array with
one-based child IDs. Spans are half-open. `flow_verify` independently recognizes
the complete owned source using the shared lexer and checks every postorder tag,
span and child against the proposed tree, including the root and absence of extra
nodes. Neither this check nor structural completion resolves names, checks types,
effects, ownership, proofs, resources, or operation semantics. Calls are
opaque and may not be treated as effect-free, terminating, or correctly typed.
Call syntax supplies a single value: `()` supplies Unit, `(x)` supplies `x`,
and `(x,y,...)` supplies a tuple. Tuple elements are stored in source order in
a left-associated pair tree; the tree does not itself execute those elements.
Trailing commas are not supported by this prototype.

`flow_completion` first invokes the independent recognizer and then computes a
syntactic fallthrough/unreachable summary. It recognizes only direct Bool
literals (and transparent grouping) for reachability; it does not use optional
constant folding or facts. Other conditions are unknown. A return terminates its
path, and sequential code after an unconditional transfer is reported as
unreachable. This prototype conservatively reports such code inside even a
literal-pruned branch. It also rejects a value block with a reachable normal
path that neither breaks nor returns; return paths inside a value block exit the
enclosing function. Missing-break findings are propagated only through reachable
literal branches and possible short-circuit operands. The recognizer still checks
syntax and lexical targets in pruned branches, and the prototype still reports
code after unconditional transfer in them. It does not check name, type or effect
validity in any branch. A block consumes only its own lexical breaks, identified by
the one-based source byte offset of its `do` token. The recognizer recomputes each
target from the source nesting and rejects forged links. This is not full
normative K1 completion.
The prototype's 2,048-node and 64-parser-frame caps are local engineering limits,
not the K1 semantic budget or a claim about valid K1 source. All operations are
unmetered and cannot produce a shared work receipt or a trusted artifact.
