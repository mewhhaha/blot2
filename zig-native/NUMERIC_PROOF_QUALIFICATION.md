# Numeric proof prototype

Task 070 is in progress. The isolated source in
`/var/tmp/blot2-erased-proofs-070` grants no runtime witness authority and is
not part of the qualified main compiler. [The design](ERASED_PROOFS.md) remains
the acceptance contract.

Frozen tree `7cfa6e5d212c040b1853e7dca117ab5c01a6746f`, base tree
`d55ab1cd300936b92ec48fc607b7e74e234f0d9e`, patch SHA-256
`9448b407d7c4158ecd636804f113678b49cb7ff8ac973f5c8c6b44b2f6fabde8`. Patch, file
hashes and pins are under ignored
`build/bench/continuation-20261013/proof-call-foundation/`. Earlier syntax,
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
associated equations, operation type arguments or stored payloads. Checked
constructors now own exact operands, lexical owners and ordered argument nodes.
Exact aliases preserve values; rebindings create new versions, and collection
lengths retain their exact collection. A known-false constructor remains
recorded for its required runtime trap. Source metadata survives
AST/checker-owner teardown and grants no executable authority by itself.

Complete explicit local headers now substitute prior ordinary arguments into
proof requirements. Direct local calls accept exact witness aliases and
forwarded proof parameters; other collections, rebound indexes, wrong relations,
Unit and captured witnesses reject. A function type cannot authorize another
contract through an unchecked callable alias. Proof results and imported
contracts remain conservative. Every metadata table and repeated consistency
check consumes bounded shared work; two large requirement instantiations exhaust
the same 10,000-visit budget. Ordinary annotations allocate no proof tables, and
there is no Unit representation bridge.

Zig 0.17.0 focused checks pass 41 numeric-proof native tests, including complete
allocation failure sweeps, plus the separate complete syntax suite's 41 tests.
All eight unchanged compilation budgets pass through the dev build/transport
smoke harness. Analyzer reports zero findings across 380 files. Logs:
`proof-calls-{all-native,full-syntax,controls,analyzer}.log`. A command
combining the syntax suite and name filter covered only six tests; the complete
focused commands were subsequently run separately and both logs are preserved.
Earlier frontend syntax/format/parser checks pass 23 tests; tree-sitter 0.27.1
passes seven corpus cases, sixteen highlight fixtures and four example parses.
That unchanged frontend evidence remains `proof-frontend-full.log` and
`proof-editor.log`.

Remaining work includes executable constructor guards and trap ordering, exact
Core body/call admission, public proof results, compiled introduction and
consumer authority, complete closure escape handling, runtime erasure, complete
diagnostics and the full source/compiled acceptance matrix. No full compiler
gate, release qualification or task completion is claimed for this prototype.
Task 071 remains dependent on 070.
