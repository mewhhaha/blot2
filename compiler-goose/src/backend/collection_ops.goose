namespace blot_backend_collection_ops;
import support.option;
import support.error;
import support.structural;

enum Op { length, get, set, fill, generate, append, prepend, identity, convert, cursor, cursor_has, cursor_value, cursor_advance, concat, slice, simd_load, simd_store, flatten }
let operations = [Op.length, Op.get, Op.set, Op.fill, Op.generate, Op.append, Op.prepend, Op.identity, Op.convert, Op.cursor, Op.cursor_has, Op.cursor_value, Op.cursor_advance, Op.concat, Op.slice, Op.simd_load, Op.simd_store, Op.flatten];
let names = ["length", "get", "set", "fill", "generate", "append", "prepend", "identity", "convert", "cursor", "cursor_has", "cursor_value", "cursor_advance", "concat", "slice", "simd_load", "simd_store", "flatten"];
struct Primitive { op: Op = Op.length, arity: u8 = 0, is_list: bool = false }
fn opCode(op: Op) -> u32 { for value, index in operations { if value == op { return index as u32; } } abort("invalid collection operation"); }
fn opFromCode(code: u32) -> Op, blot_error::Error {
    if code >= operations.len { return Op.length, blot_error::Error.invalid_operation; }
    return operations[code], blot_error::Error.none;
}
fn arity(op: Op) -> u8 {
    if op == Op.length || op == Op.identity || op == Op.convert || op == Op.cursor || op == Op.cursor_has || op == Op.cursor_value || op == Op.cursor_advance || op == Op.flatten { return 1; }
    if op == Op.set || op == Op.slice || op == Op.simd_store { return 3; }
    return 2;
}
fn equal(left: const u8[:], right: const u8[:]) -> bool {
    if left.len != right.len { return false; } for byte, index in left { if byte != right[index] { return false; } } return true;
}
fn startsWith(value: const u8[:], prefix: const u8[:]) -> bool { value.len >= prefix.len && equal(value[..prefix.len], prefix) }
fn primitive(op: Op, is_list: bool) -> blot_support::Option<Primitive> { blot_support::some(Primitive { op: op, arity: arity(op), is_list: is_list , ..}) }
fn lookup(name: const u8[:]) -> blot_support::Option<Primitive> {
    if equal(name, "@cursor.has") { return primitive(Op.cursor_has, false); }
    if equal(name, "@cursor.value") { return primitive(Op.cursor_value, false); }
    if equal(name, "@cursor.advance") { return primitive(Op.cursor_advance, false); }
    if equal(name, "@simd.load") { return primitive(Op.simd_load, false); }
    if equal(name, "@simd.store") { return primitive(Op.simd_store, false); }
    let is_list = startsWith(name, "@list.");
    if !is_list && !startsWith(name, "@array.") { return blot_support::none<Primitive>(); }
    var start = 7; if is_list { start = 6; }
    let member = name[start..];
    if (is_list && equal(member, "from_array")) || (!is_list && equal(member, "from_list")) { return primitive(Op.convert, is_list); }
    for op in [Op.length, Op.get, Op.set, Op.fill, Op.generate, Op.append, Op.prepend, Op.identity, Op.cursor, Op.concat, Op.slice, Op.flatten] {
        if !equal(member, names[opCode(op)]) { continue; }
        if is_list && (op == Op.get || op == Op.set || op == Op.flatten) { return blot_support::none<Primitive>(); }
        return primitive(op, is_list);
    }
    return blot_support::none<Primitive>();
}

fn blot_structural::hash<S>(sink:S&,value:blot_backend_collection_ops::Op) {blot_structural::hash(sink,blot_backend_collection_ops::opCode(value));}
