# Private I08 branch-aware source ownership experiment

This experiment independently replays the fixed I08 source/header, bounded
type shapes, numerical read obligations, and explicit completion. It checks a
single source-owned Builder carry initialized from the exact formal builder,
with loop `0..n` and invariant `Eq(Init(b),i)`. Each reachable loop-body path
must consume that carry exactly once through `next(builder.append(b,row))`.
An unknown branch requires both arms to satisfy the same rule; a branch may
also transfer in one arm and fall through to a later transfer. Rows may use
only bounded F32 expressions over `dt` and exact `source[i]` fields.

The checker rejects every in-loop `stop` and function `return`, including in
literal-pruned branches. The carry's initialized length is `i`, while the
function result requires `n`; the current type-shape checker does not prove
the dependent equality needed to accept such exits. It also rejects unsupported
condition/effect expressions, builder aliases and multiple carries. Branches
are source-validated and type-checked even when literal-pruned.

The plan enumerates reachable transfer/append/row source node IDs. The separate
consumer replays source and reconstructs per-path completion, builder use and
edge ordering; a missing, reordered or forged edge rejects. IDs are local to
this immutable source snapshot, not fresh runtime generations or capabilities.
No live View loan, initialized memory, exclusive builder, intrinsic transition,
per-iteration SSA versions, general loop invariant, complete type/effect/affine
system, C09 receipt, generated branch worker or public ABI is established. This
is a non-admitting source experiment, not an executable compiler path.
