# Private I08 builder-use and completion experiment

This source-bound experiment recognizes the single canonical I08 declaration
and loop using the independently replayed `i08_*` source arena. The producer
constructs a plan of exact source-local node and binding identities; the
separate consumer replays the original source, type shapes, formal index
bounds, the plan and the use structure. Neither the plan IDs nor lexical byte
spans are runtime handles, fresh SSA versions, loan authority or capabilities.

The accepted shape binds one initial `Builder[...,0,c,Append]` to a single
loop carry, with `for i in 0..n`, `Eq(Init(b),i)` and one body statement
`next(builder.append(b, row))`. The row contains only bounded F32 operations
on `dt`, literals and fields of the same source View read at the loop index.
After the loop, the exact result is consumed by `builder.freeze` in the sole
return. The check rejects stop, fallthrough, multiple append operations,
reusing the original builder, freezing the wrong binding, other invariants,
wrong index and other source shapes. It is conservative and does not implement
general branch joins, earlier returns, multi-carry loops or an affine language.

The fixed header states `Le(n,c)` and a zero initialized length; the accepted
source names an invariant and one syntactic append/next transition. This pass
checks their identities and structure, not a general invariant proof engine or
runtime builder implementation. A later checker must prove the trusted append
transition, simultaneous carry substitution, exact capacity/length arithmetic,
loop exit and any mutable state versions. It must independently establish a
live input View loan, initialized input storage, exclusive output capability,
relevant disjointness and generative result Domain before admitting any read,
append, freeze or executable code. No C09 work accounting, host ABI, artifact
or performance qualification is supplied here.
