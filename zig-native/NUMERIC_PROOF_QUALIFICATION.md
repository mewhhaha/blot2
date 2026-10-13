# Numeric proof prototype

Task 070 is in progress. The isolated source in
`/var/tmp/blot2-erased-proofs-070` grants no runtime witness authority and is
not part of the qualified main compiler. [The design](ERASED_PROOFS.md) remains
the acceptance contract.

Frozen tree `40af0cf79b7c59c1128283b14b342b78929c9236`, base tree
`d55ab1cd300936b92ec48fc607b7e74e234f0d9e`, patch SHA-256
`25d154417cb7e71fb9acbc8fc27e3d34503b016326f873e80c6bcdac469c610a`. Patch, file
hashes and pins are under ignored
`build/bench/continuation-20261013/proof-kind-foundation/`. Earlier syntax,
consistency and positional-header checkpoints remain preserved separately.

The native and Baba parsers accept six intrinsic proof annotations with bounded
operands. Formatter and tree-sitter highlighting preserve them. Exact typed
value terms have explicit formal/capture/version substitution and transactional
owned imports. Importing 256 propositions from a shared 2,049-term graph costs
2,817 charged visits. Public contract validation checks scope, kind, complete
result recipes and consistency without granting witness authority.

Iterative strongly connected components replace transitive edge expansion for
unsigned order consistency. A strict edge within one component establishes a
contradiction; a non-strict cycle alone does not. Small random graphs agree with
an independent dense closure oracle, including disconnected graphs. The maximum
256-requirement chain now validates with 259 terms, 773 edges and 4,902 charged
visits; the old implementation exhausted its 65,536-visit budget at 32
requirements. Requested memory at 256 requirements falls 74,548→53,332 bytes,
allocations 19→14, and peak requested storage 51,316→44,620 bytes, with zero
live bytes at teardown. These are deterministic analysis/memory measurements,
not compiler CPU timings; exact measured module hashes and logs are in
`proof-consistency/`.

Owned headers now map actual curried argument positions to dense numeric or
collection formals and proof requirements. Resolved kinds, rather than source
type names, determine operand validity. Aliases, shadowing, missing/forward
binders and wrong collection-length intrinsics have explicit laws. Lazy
complement edges preserve equality substitution in AddFits; eighty unsigned
boundary cases agree with direct U32 mathematics.

The separate erased-proof kind cannot instantiate ordinary data variables,
associated equations, operation type arguments or stored payloads. The source
checker owns public contracts and diagnoses invalid operands, scope errors and
contradictions. Explicit unused proof parameters check. A marker alone cannot
authorize proof calls or results; those paths, runtime layout and compiled
admission remain conservative until exact body evidence is connected. Ordinary
annotations allocate no proof tables, and there is no Unit representation
bridge.

Zig 0.17.0 focused checks pass 35 native tests, including complete allocation
failure sweeps. The full native syntax suite and all eight unchanged compilation
budgets pass through the development harness, which rebuilds the compiler and
runs transport smoke tests. Analyzer reports zero findings across 379 files.
Logs: `proof-kind-checker-{native,controls,analyzer}.log`. Earlier frontend
syntax/format/parser checks pass 23 tests; tree-sitter 0.27.1 passes seven
corpus cases, sixteen highlight fixtures and four example parses. That unchanged
frontend evidence remains `proof-frontend-full.log` and `proof-editor.log`.

Remaining work includes checked constructor guards and trap ordering, exact
body/call evidence, public proof result admission, compiled introduction and
consumer authority, closure escape rejection, runtime erasure, complete
diagnostics and the full source/compiled acceptance matrix. No full compiler
gate, release qualification or task completion is claimed for this prototype.
Task 071 remains dependent on 070.
