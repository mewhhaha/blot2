// Owned, source-bound syntax for a deliberately bounded finite-loop subset.
// IDs refer only to records in this one source snapshot; they are not type,
// region, ownership, effect, proof, artifact or runtime authority. Identifier
// types and the truth of invariants are intentionally NOT inferred here.
namespace i08_core;
// Binding kinds: 1 function parameter, 2 loop index, 3 carry, 4 let-result.
// `scope` is the one-based byte offset of the lexical owner (function, branch
// or loop), not a globally authenticated identity. Each binding is unique.
struct Binding { start: i64 = 0, end: i64 = 0, kind: i64 = 0, scope: i64 = 0 }
// Postorder nodes; children use one-based IDs, zero means absent.
// 1 name (a = binding ID), 2 U32 literal, 3 #True, 4 #False,
// 5 list-pair (a previous item/list, b final item),
// 6 carry (a initial value, b binding ID),
// 7 observation Init/Len/Cap (a name, b selector 1/2/3),
// 8 fact (a left, b right, c Eq/Lt/Le/AddFits/SubFits/MulFits = 1..6;
//         c=7 for Index with d as third child),
// 9 next, 10 stop (a arguments or 0, b arity, target = innermost loop),
// 11 continue, 12 bare break (target = innermost no-carry loop),
// 13 return (a expression, target = owning function),
// 14 if (a condition, b then suite, c else suite or 0),
// 15 for (a lo, b hi, c carries, d invariant facts, e body,
//         f index binding, g carry arity, target = for byte offset + 1),
// 16 let (a for initializer, b newly introduced binding),
// 17 sequence (a previous, b next), 18 function (a body, b parameter count,
//         target = fn byte offset + 1).
// 19 U32.wrapping_add, 20 group, 21 addition, 22 less-than;
// 23 field (a receiver, b selector 1=x, 2=y, 3=vx, 4=vy, 5=length),
// 24 index (a receiver, b index), 25 multiplication, 26 {x:a,y:b},
// 27 builder.append(a,b), 28 builder.freeze(a), 29 F32 decimal literal.
// Syntax alone does not establish operand types, numeric fit, declared
// builtins, View identity, loans, bounds, resource effects or authority.
struct Node { tag: i64 = 0, start: i64 = 0, end: i64 = 0,
    a: i64 = 0, b: i64 = 0, c: i64 = 0, d: i64 = 0, e: i64 = 0, f: i64 = 0, g: i64 = 0, target: i64 = 0 }
struct Tree { source: u8[] = [], bindings: Binding[] = [], nodes: Node[] = [], root: i64 = 0 }
fn same_node(a: Node, b: Node) -> bool {
    return a.tag == b.tag && a.start == b.start && a.end == b.end && a.a == b.a && a.b == b.b && a.c == b.c &&
        a.d == b.d && a.e == b.e && a.f == b.f && a.g == b.g && a.target == b.target;
}
fn same_binding(a: Binding, b: Binding) -> bool { return a.start == b.start && a.end == b.end && a.kind == b.kind && a.scope == b.scope; }
