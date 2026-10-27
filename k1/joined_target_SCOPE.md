# Private independent joined target checker

This bounded checker revalidates a joined source/Core candidate against the
caller-retained original bytes, then independently decodes the fixed private
Wasm module and matches its type, function, memory, export, code, and custom
metadata sections. It checks canonical bounded LEBs, locals, constants,
operations, branches, returns, nested loop labels, transfers, and all section
and body boundaries against the checked scalar, finite-loop or mixed source
tree. It does not invoke the Wasm emitter. Unknown opcodes, extra sections,
noncanonical encodings, altered source or Core, and unsupported variants fail
closed. A valid-Wasm change from addition to subtraction is rejected.

The test interface retains the existing fixture's noncapturing two-i32 call
convention and fixed memory geometry. Decoder control recursion is limited to
128; source expression and sequence spines use explicit bounded stacks so long
left-associated inputs do not consume that recursion budget. The mixed value
limit matches its existing parser/checker bound. Immutable expected source is
retained independently by the compiler caller.

This is a private, source-bound subset validator, not a general Wasm verifier,
M13 proof, public ABI or full C09 receipt. It does not independently prove the
source frontend's typing/arithmetic/ownership semantics, authenticate external
origin, or authorize a public host export. The underlying source verifier and
proof consumers remain required, and full language/resource/ABI work is absent.
