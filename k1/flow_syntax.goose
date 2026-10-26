// Source-owned syntax only. No semantic admission, name binding, type/effect
// checking, work receipt, or executable lowering is established here.
namespace flow_syntax;

// One-based child IDs; children precede their parent. Tags: name 1, decimal 2,
// Bool false/true 3/4, group 5, call 6, &&/|| 7/8, return 9, if 10,
// sequence 11, Unit 12, tuple-item pair 13, tuple 14, value do 15, and
// break-value 16. A break's b field is its target's do-byte offset plus one.
// A sequence and a
// tuple-item pair are binary. A tuple has at least two items. A call has a
// callee and a single argument value: Unit for (), its item for (x), and a
// tuple for (x,y,...). The pair tree preserves left-to-right item order.
struct Node { tag: i64 = 0, start: i64 = 0, end: i64 = 0, a: i64 = 0, b: i64 = 0, c: i64 = 0 }
struct Tree { source: u8[] = [], nodes: Node[] = [], root: i64 = 0 }
