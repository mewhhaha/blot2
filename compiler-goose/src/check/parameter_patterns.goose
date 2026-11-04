// Source argument patterns retain their syntactic kind after AST release.
namespace blot_check_parameter_patterns;
import support.structural;
import std;
import support.error;
type Id = u32;
type List = blot_check_types::List;
enum Kind { binding, tuple, array, record }
struct Node { kind: Kind, a: u32, b: u32 = 0 }
struct Field { name: u32, pattern: Id }
struct Store { nodes: Node[>..<]&, extra: u32[>..<]& }
fn init(nodes: Node[>..<]&, extra: u32[>..<]&) -> Store { return Store { nodes, extra }; }
fn deinit(self: Store&) { self.nodes.clear(); self.extra.clear(); }
fn node(self: const Store&, id: Id) -> Node { return self.nodes[id]; }
fn list(self: const Store&, span: List) -> const Id[:] { return self.extra[span.start..span.start + span.len]; }
fn saveList(self: Store&, values: const Id[:]) -> List, blot_error::Error {
    if values.len > 0xffffffff - self.extra.len { return List {}, blot_error::Error.type_limit; }
    let start = self.extra.len as u32;
    self.extra.append(values);
    return List { start, values.len as u32 }, blot_error::Error.none;
}
fn add(self: Store&, value: Node) -> Id, blot_error::Error {
    if self.nodes.len == 0xffffffff { return 0, blot_error::Error.type_limit; }
    let id = self.nodes.len as u32;
    self.nodes.push(value);
    return id, blot_error::Error.none;
}
fn sequence(self: Store&, kind: Kind, children: const Id[:]) -> Id, blot_error::Error {
    assert(kind == Kind.tuple || kind == Kind.array);
    let span, error = saveList(self, children);
    if error != blot_error::Error.none { return 0, error; }
    return add(self, Node { kind, span.start, span.len });
}
fn record(self: Store&, fields: const Field[:]) -> Id, blot_error::Error {
    if fields.len > (0xffffffff - self.extra.len) / 2 { return 0, blot_error::Error.type_limit; }
    let start = self.extra.len as u32;
    for item in fields { self.extra.push(item.name); self.extra.push(item.pattern); }
    return add(self, Node { Kind.record, start, fields.len as u32 });
}
fn field(self: const Store&, value: Node, index: i64) -> Field {
    assert(value.kind == Kind.record && index < value.b);
    return Field { self.extra[value.a + index * 2], self.extra[value.a + index * 2 + 1] };
}

fn kindCode(value: Kind) -> u32 {
    match value {
        binding => { return 0; },
        tuple => { return 1; },
        array => { return 2; },
        record => { return 3; },
    }
}
fn kindFromCode(code: u32) -> Kind, blot_error::Error {
    match code {
        0 => { return Kind.binding, blot_error::Error.none; },
        1 => { return Kind.tuple, blot_error::Error.none; },
        2 => { return Kind.array, blot_error::Error.none; },
        3 => { return Kind.record, blot_error::Error.none; },
        _ => { return Kind.binding, blot_error::Error.invalid_artifact; },
    }
}

fn blot_structural::equal(left: blot_check_parameter_patterns::Kind, right: blot_check_parameter_patterns::Kind) -> bool { return left == right; }
fn blot_structural::hash<S>(sink: S&, value: blot_check_parameter_patterns::Kind) { blot_structural::hash(sink, blot_check_parameter_patterns::kindCode(value) as! u8); }
