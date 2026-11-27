namespace squid_backend_collection_ops;
import support.option;
import support.error;
import support.structural;

enum Op { length, get, set, fill, generate, append, prepend, identity, concat, slice, simd_load, simd_store, flatten, simd_load_u8x16, simd_store_u8x16, simd_load_f64x2, simd_store_f64x2 }
let operations = [Op.length, Op.get, Op.set, Op.fill, Op.generate, Op.append, Op.prepend, Op.identity, Op.concat, Op.slice, Op.simd_load, Op.simd_store, Op.flatten, Op.simd_load_u8x16, Op.simd_store_u8x16, Op.simd_load_f64x2, Op.simd_store_f64x2];
let names = ["length", "get", "set", "fill", "generate", "append", "prepend", "identity", "concat", "slice", "simd_load", "simd_store", "flatten", "simd_load_u8x16", "simd_store_u8x16", "simd_load_f64x2", "simd_store_f64x2"];
struct Primitive { op: Op = Op.length, arity: u8 = 0 }
fn opCode(op: Op) -> u32 { for value, index in operations { if value == op { return index as u32; } } abort("invalid collection operation"); }
fn opFromCode(code: u32) -> Op, squid_error::Error {
    if code >= operations.len { return Op.length, squid_error::Error.invalid_operation; }
    return operations[code], squid_error::Error.none;
}
fn arity(op: Op) -> u8 {
    if op == Op.length || op == Op.identity || op == Op.flatten { return 1; }
    if op == Op.set || op == Op.slice || op == Op.simd_store || op == Op.simd_store_u8x16 || op == Op.simd_store_f64x2 { return 3; }
    return 2;
}
fn equal(left: const u8[:], right: const u8[:]) -> bool {
    if left.len != right.len { return false; } for byte, index in left { if byte != right[index] { return false; } } return true;
}
fn startsWith(value: const u8[:], prefix: const u8[:]) -> bool { value.len >= prefix.len && equal(value[..prefix.len], prefix) }
fn primitive(op: Op) -> squid_support::Option<Primitive> { squid_support::some(Primitive { op: op, arity: arity(op), ..}) }
fn lookup(name: const u8[:]) -> squid_support::Option<Primitive> {
    if equal(name, "@simd.load") { return primitive(Op.simd_load); }
    if equal(name, "@simd.store") { return primitive(Op.simd_store); }
    if equal(name, "@simd.load_u8x16") { return primitive(Op.simd_load_u8x16); }
    if equal(name, "@simd.store_u8x16") { return primitive(Op.simd_store_u8x16); }
    if equal(name, "@simd.load_f64x2") { return primitive(Op.simd_load_f64x2); }
    if equal(name, "@simd.store_f64x2") { return primitive(Op.simd_store_f64x2); }
    if !startsWith(name, "@array.") { return squid_support::none<Primitive>(); }
    let member = name[7..];
    for op in [Op.length, Op.get, Op.set, Op.fill, Op.generate, Op.append, Op.prepend, Op.identity, Op.concat, Op.slice, Op.flatten] {
        if !equal(member, names[opCode(op)]) { continue; }
        return primitive(op);
    }
    return squid_support::none<Primitive>();
}

fn squid_backend_collection_ops::squidStructuralHash<S>(value:squid_backend_collection_ops::Op,sink:S&) {squid_structural::hash(sink,squid_backend_collection_ops::opCode(value));}

fn squid_structural::equal(left:squid_backend_collection_ops::Op,right:squid_backend_collection_ops::Op)->bool {return left==right;}
