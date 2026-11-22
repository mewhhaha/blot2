namespace blot_backend_collection_ops;
import support.option;
import support.error;
import support.structural;

enum Op { length, get, set, fill, generate, append, prepend, identity, concat, slice, simd_load, simd_store, flatten }
let operations = [Op.length, Op.get, Op.set, Op.fill, Op.generate, Op.append, Op.prepend, Op.identity, Op.concat, Op.slice, Op.simd_load, Op.simd_store, Op.flatten];
let names = ["length", "get", "set", "fill", "generate", "append", "prepend", "identity", "concat", "slice", "simd_load", "simd_store", "flatten"];
struct Primitive { op: Op = Op.length, arity: u8 = 0 }
fn opCode(op: Op) -> u32 { for value, index in operations { if value == op { return index as u32; } } abort("invalid collection operation"); }
fn opFromCode(code: u32) -> Op, blot_error::Error {
    if code >= operations.len { return Op.length, blot_error::Error.invalid_operation; }
    return operations[code], blot_error::Error.none;
}
fn arity(op: Op) -> u8 {
    if op == Op.length || op == Op.identity || op == Op.flatten { return 1; }
    if op == Op.set || op == Op.slice || op == Op.simd_store { return 3; }
    return 2;
}
fn equal(left: const u8[:], right: const u8[:]) -> bool {
    if left.len != right.len { return false; } for byte, index in left { if byte != right[index] { return false; } } return true;
}
fn startsWith(value: const u8[:], prefix: const u8[:]) -> bool { value.len >= prefix.len && equal(value[..prefix.len], prefix) }
fn primitive(op: Op) -> blot_support::Option<Primitive> { blot_support::some(Primitive { op: op, arity: arity(op), ..}) }
fn lookup(name: const u8[:]) -> blot_support::Option<Primitive> {
    if equal(name, "@simd.load") { return primitive(Op.simd_load); }
    if equal(name, "@simd.store") { return primitive(Op.simd_store); }
    if !startsWith(name, "@array.") { return blot_support::none<Primitive>(); }
    let member = name[7..];
    for op in [Op.length, Op.get, Op.set, Op.fill, Op.generate, Op.append, Op.prepend, Op.identity, Op.concat, Op.slice, Op.flatten] {
        if !equal(member, names[opCode(op)]) { continue; }
        return primitive(op);
    }
    return blot_support::none<Primitive>();
}

fn blot_backend_collection_ops::blotStructuralHash<S>(value:blot_backend_collection_ops::Op,sink:S&) {blot_structural::hash(sink,blot_backend_collection_ops::opCode(value));}

fn blot_structural::equal(left:blot_backend_collection_ops::Op,right:blot_backend_collection_ops::Op)->bool {return left==right;}
