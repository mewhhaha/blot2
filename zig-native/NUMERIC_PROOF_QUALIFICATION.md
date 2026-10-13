# Numeric proof prototype

Task 070 is in progress. The isolated source in
`/var/tmp/blot2-erased-proofs-070` grants no runtime witness authority and is
not part of the qualified main compiler. [The design](ERASED_PROOFS.md) remains
the acceptance contract.

Frozen tree `698cfe4ac3535f20118fdb942f1d8e4181bb869a`, base tree
`d55ab1cd300936b92ec48fc607b7e74e234f0d9e`, patch SHA-256
`41db5de726d60c51c05763e2aa0c63a4b1da95b6208f055fa2a18363f9243439`. Patch, file
hashes and pins are under ignored
`build/bench/continuation-20261013/proof-consistency-foundation/`. The older
`proof-foundation/` checkpoint remains preserved separately.

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

Zig 0.17.0 focused checks pass 26 native laws, including complete allocation
failure sweeps. Full native syntax passes 41 laws. Frontend syntax/format/parser
checks pass 23 tests; ordinary execution controls use the qualified compiler.
Tree-sitter 0.27.1 passes seven corpus cases, sixteen highlight fixtures and
four example parses. Analyzer reports zero findings across 377 files. Logs are
`proof-consistency-final-{native,syntax,analyzer}.log`,
`proof-frontend-full.log` and `proof-editor.log` under the same evidence root.

Remaining work includes binding-owned complete contracts, distinct proof-kind
checking, constructor guards and trap ordering, exact call substitution,
compiled introduction/dominance/consumer authority, storage/escape rejection,
runtime erasure, diagnostics and the full source/compiled acceptance matrix.
Ordinary datatype unification must remain separate from value identity. No full
compiler gate, release qualification or task completion is claimed for this
prototype. Task 071 remains dependent on 070.
