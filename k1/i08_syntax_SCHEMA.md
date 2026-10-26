# Scratch I08 common source arena

This is a private experiment, not source admission, an executable compiler,
K1 type/effect/ownership checking, a loan authority, proof certificate, C09
receipt, ABI or performance qualification.

`i08_header_parse::parse(source)` recognizes the exact canonical particle
signature and derives the `r,s,n,c,d` Region/Nat/Domain tokens from the
original immutable full-source bytes. `i08_parse::parse_from` then assigns these
source-bound names and body formals to the same binding table as the loop
index, carry and local result. The postorder node arena includes View index,
field/length, F32 operators and records, builder calls, loop syntax and
invariant syntax. `i08_header_verify::verify(tree,source)` independently
re-lexes the full signature and reconstructs binding/scope, syntax and targets.
The raw resume helpers only fence malformed lexer state; they are not source
or capability authority. The standalone suffix entry cannot resolve header
binders.

`i08_typed_shape::verify` is a bounded structural type pass after full source
replay. It rejects unsupported kinds and obvious F32/U32, View, record and
builder mismatches; it is not a general type checker, completion checker,
effect or ownership validator. `i08_bound_shape::verify` additionally checks
only a formal raw-index fact: each `source[i]` lies in the lexical body of
its exact `for i in 0..n`, where source and n are the exact typed formal View
and Nat binding from the fixed signature. A literal index or `0..c` rejects.
No immutable loan, initialized input storage, versioned builder carry,
resource policy, arithmetic facts, invariant preservation, result domain,
execution or host memory authority is inferred. These obligations must be
established independently before any read/append/freeze is admitted or code
is emitted. In particular, type-shape success alone does not establish bounds.

The diagnostic statuses and fixed source-size, syntax, and proof-search bounds
are private experimental limits. The source-bound full-header entry is the only
entry that authenticates header provenance; raw resume helpers are checked
for malformed lexer state but remain internal and unauthenticated. Numeric
index obligations cannot by themselves authorize a memory read.
