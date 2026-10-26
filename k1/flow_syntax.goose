// Source-owned syntax only. No semantic admission, name binding, type/effect
// checking, work receipt, or executable lowering is established here.
namespace flow_syntax;

// One-based child IDs; children precede their parent. Tags: name 1, decimal 2,
// Bool false/true 3/4, group 5, call 6, &&/|| 7/8, return 9, if 10,
// sequence 11. A sequence is binary and has at least one statement. Call has
// a callee and one argument expression; () and tuple calls are not yet parsed.
struct Node { tag: i64 = 0, start: i64 = 0, end: i64 = 0, a: i64 = 0, b: i64 = 0, c: i64 = 0 }
struct Tree { source: u8[] = [], nodes: Node[] = [], root: i64 = 0 }
