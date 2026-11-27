namespace squid_backend_simd_intrinsics;
import std;
import check.core;
import support.option;

enum Lane { unsigned, floating }
enum Shape { unary, convert, binary, compare, shift, reduce, select, madd, shuffle, swizzle, broadcast, splat_u8, splat_u32, bitmask }
struct Intrinsic { op: squid_check_core::Op, arity: u8 = 0, floating: bool = false, wide: bool = false, shape: Shape = Shape.unary }
struct Entry { name: const u8[:], op: squid_check_core::Op, shape: Shape }
fn lane(value: Intrinsic) -> Lane { if value.floating { return Lane.floating; } return Lane.unsigned; }
fn resultLane(value: Intrinsic) -> Lane {
    if value.shape == Shape.convert { if value.floating { return Lane.unsigned; } return Lane.floating; }
    if value.shape == Shape.compare { return Lane.unsigned; }
    return lane(value);
}
let shared = [
    Entry { "add", squid_check_core::Op.add, Shape.binary , ..},
    Entry { "sub", squid_check_core::Op.sub, Shape.binary , ..},
    Entry { "mul", squid_check_core::Op.mul, Shape.binary , ..},
    Entry { "min", squid_check_core::Op.min, Shape.binary , ..},
    Entry { "max", squid_check_core::Op.max, Shape.binary , ..},
    Entry { "eq", squid_check_core::Op.equal, Shape.compare , ..},
    Entry { "ne", squid_check_core::Op.not_equal, Shape.compare , ..},
    Entry { "lt", squid_check_core::Op.less, Shape.compare , ..},
    Entry { "le", squid_check_core::Op.less_equal, Shape.compare , ..},
    Entry { "gt", squid_check_core::Op.greater, Shape.compare , ..},
    Entry { "ge", squid_check_core::Op.greater_equal, Shape.compare , ..},
    Entry { "select", squid_check_core::Op.select, Shape.select , ..},
    Entry { "shuffle", squid_check_core::Op.shuffle, Shape.shuffle , ..},
    Entry { "swizzle", squid_check_core::Op.swizzle, Shape.swizzle , ..},
    Entry { "broadcast", squid_check_core::Op.broadcast, Shape.broadcast , ..},
];
let floating_only = [
    Entry { "div", squid_check_core::Op.div, Shape.binary , ..},
    Entry { "abs", squid_check_core::Op.abs, Shape.unary , ..},
    Entry { "neg", squid_check_core::Op.neg, Shape.unary , ..},
    Entry { "ceil", squid_check_core::Op.ceil, Shape.unary , ..},
    Entry { "floor", squid_check_core::Op.floor, Shape.unary , ..},
    Entry { "trunc", squid_check_core::Op.trunc, Shape.unary , ..},
    Entry { "sqrt", squid_check_core::Op.sqrt, Shape.unary , ..},
    Entry { "to_u32", squid_check_core::Op.convert_f32_u32, Shape.convert , ..},
    Entry { "bits", squid_check_core::Op.bits, Shape.convert , ..},
    Entry { "relaxed_madd", squid_check_core::Op.relaxed_madd, Shape.madd , ..},
    Entry { "relaxed_nmadd", squid_check_core::Op.relaxed_nmadd, Shape.madd , ..},
    Entry { "to_u32_signed", squid_check_core::Op.convert_f32_i32, Shape.convert , ..},
];
let integer_only = [
    Entry { "bit_and", squid_check_core::Op.bit_and, Shape.binary , ..},
    Entry { "bit_or", squid_check_core::Op.bit_or, Shape.binary , ..},
    Entry { "bit_xor", squid_check_core::Op.bit_xor, Shape.binary , ..},
    Entry { "andnot", squid_check_core::Op.bit_andnot, Shape.binary , ..},
    Entry { "not", squid_check_core::Op.bit_not, Shape.unary , ..},
    Entry { "to_f32", squid_check_core::Op.convert_u32_f32, Shape.convert , ..},
    Entry { "from_bits", squid_check_core::Op.from_bits, Shape.convert , ..},
    Entry { "shl", squid_check_core::Op.shift_left, Shape.shift , ..},
    Entry { "shr", squid_check_core::Op.shift_right, Shape.shift , ..},
    Entry { "sar", squid_check_core::Op.shift_right_signed, Shape.shift , ..},
    Entry { "any_true", squid_check_core::Op.any_true, Shape.reduce , ..},
    Entry { "all_true", squid_check_core::Op.all_true, Shape.reduce , ..},
    Entry { "to_f32_signed", squid_check_core::Op.convert_i32_f32, Shape.convert , ..},
];
let f64x2_ops = [
    Entry { "add", squid_check_core::Op.add, Shape.binary , ..},
    Entry { "sub", squid_check_core::Op.sub, Shape.binary , ..},
    Entry { "mul", squid_check_core::Op.mul, Shape.binary , ..},
    Entry { "div", squid_check_core::Op.div, Shape.binary , ..},
    Entry { "min", squid_check_core::Op.min, Shape.binary , ..},
    Entry { "max", squid_check_core::Op.max, Shape.binary , ..},
    Entry { "abs", squid_check_core::Op.abs, Shape.unary , ..},
    Entry { "neg", squid_check_core::Op.neg, Shape.unary , ..},
    Entry { "ceil", squid_check_core::Op.ceil, Shape.unary , ..},
    Entry { "floor", squid_check_core::Op.floor, Shape.unary , ..},
    Entry { "trunc", squid_check_core::Op.trunc, Shape.unary , ..},
    Entry { "sqrt", squid_check_core::Op.sqrt, Shape.unary , ..},
    Entry { "eq", squid_check_core::Op.equal, Shape.compare , ..},
    Entry { "ne", squid_check_core::Op.not_equal, Shape.compare , ..},
    Entry { "lt", squid_check_core::Op.less, Shape.compare , ..},
    Entry { "le", squid_check_core::Op.less_equal, Shape.compare , ..},
    Entry { "gt", squid_check_core::Op.greater, Shape.compare , ..},
    Entry { "ge", squid_check_core::Op.greater_equal, Shape.compare , ..},
    Entry { "select", squid_check_core::Op.select, Shape.select , ..},
    Entry { "bits", squid_check_core::Op.bits, Shape.convert , ..},
    Entry { "relaxed_madd", squid_check_core::Op.relaxed_madd, Shape.madd , ..},
    Entry { "relaxed_nmadd", squid_check_core::Op.relaxed_nmadd, Shape.madd , ..},
];
let u64x2_ops = [
    Entry { "bit_and", squid_check_core::Op.bit_and, Shape.binary , ..},
    Entry { "bit_or", squid_check_core::Op.bit_or, Shape.binary , ..},
    Entry { "bit_xor", squid_check_core::Op.bit_xor, Shape.binary , ..},
    Entry { "andnot", squid_check_core::Op.bit_andnot, Shape.binary , ..},
    Entry { "not", squid_check_core::Op.bit_not, Shape.unary , ..},
    Entry { "select", squid_check_core::Op.select, Shape.select , ..},
    Entry { "any_true", squid_check_core::Op.any_true, Shape.reduce , ..},
    Entry { "all_true", squid_check_core::Op.all_true, Shape.reduce , ..},
    Entry { "from_bits", squid_check_core::Op.from_bits, Shape.convert , ..},
];
let u8x16_ops = [
    Entry { "splat", squid_check_core::Op.i8x16_splat, Shape.splat_u8 , ..},
    Entry { "add", squid_check_core::Op.i8x16_add, Shape.binary , ..},
    Entry { "sub", squid_check_core::Op.i8x16_sub, Shape.binary , ..},
    Entry { "min", squid_check_core::Op.i8x16_min_u, Shape.binary , ..},
    Entry { "max", squid_check_core::Op.i8x16_max_u, Shape.binary , ..},
    Entry { "eq", squid_check_core::Op.i8x16_eq, Shape.binary , ..},
    Entry { "avgr", squid_check_core::Op.i8x16_avgr_u, Shape.binary , ..},
    Entry { "bitmask", squid_check_core::Op.i8x16_bitmask, Shape.bitmask , ..},
    Entry { "narrow", squid_check_core::Op.i8x16_narrow_u, Shape.binary , ..},
];
let i16x8_ops = [
    Entry { "splat", squid_check_core::Op.i16x8_splat, Shape.splat_u32 , ..},
    Entry { "extend_low_u", squid_check_core::Op.i16x8_extend_low_u, Shape.unary , ..},
    Entry { "extend_high_u", squid_check_core::Op.i16x8_extend_high_u, Shape.unary , ..},
    Entry { "add", squid_check_core::Op.i16x8_add, Shape.binary , ..},
    Entry { "sub", squid_check_core::Op.i16x8_sub, Shape.binary , ..},
    Entry { "mul", squid_check_core::Op.i16x8_mul, Shape.binary , ..},
    Entry { "shl", squid_check_core::Op.i16x8_shl, Shape.shift , ..},
    Entry { "shr_u", squid_check_core::Op.i16x8_shr_u, Shape.shift , ..},
    Entry { "shr_s", squid_check_core::Op.i16x8_shr_s, Shape.shift , ..},
    Entry { "min", squid_check_core::Op.i16x8_min_u, Shape.binary , ..},
    Entry { "max", squid_check_core::Op.i16x8_max_u, Shape.binary , ..},
];
fn arity(shape: Shape) -> u8 {
    if shape == Shape.unary || shape == Shape.convert || shape == Shape.reduce || shape == Shape.splat_u8 || shape == Shape.splat_u32 || shape == Shape.bitmask { return 1; }
    return 2;
}
fn equalBytes(left: const u8[:], right: const u8[:]) -> bool {
    if left.len != right.len { return false; } for byte, index in left { if byte != right[index] { return false; } } return true;
}
fn startsWith(value: const u8[:], prefix: const u8[:]) -> bool {
    if value.len < prefix.len { return false; } return equalBytes(value[..prefix.len], prefix);
}
fn lookup(name: const u8[:]) -> squid_support::Option<Intrinsic> {
    if startsWith(name, "@simd.f64x2.") {
        let member = name[12..];
        for entry in f64x2_ops { if equalBytes(member, entry.name) { return squid_support::some(Intrinsic { op: entry.op, arity: arity(entry.shape), floating: true, wide: true, shape: entry.shape , ..}); } }
        return squid_support::none<Intrinsic>();
    }
    if startsWith(name, "@simd.u64x2.") {
        let member = name[12..];
        for entry in u64x2_ops { if equalBytes(member, entry.name) { return squid_support::some(Intrinsic { op: entry.op, arity: arity(entry.shape), floating: false, wide: true, shape: entry.shape , ..}); } }
        return squid_support::none<Intrinsic>();
    }
    if startsWith(name, "@simd.u8x16.") {
        let member = name[12..];
        for entry in u8x16_ops { if equalBytes(member, entry.name) { return squid_support::some(Intrinsic { op: entry.op, arity: arity(entry.shape), floating: false, wide: true, shape: entry.shape , ..}); } }
        return squid_support::none<Intrinsic>();
    }
    if startsWith(name, "@simd.i16x8.") {
        let member = name[12..];
        for entry in i16x8_ops { if equalBytes(member, entry.name) { return squid_support::some(Intrinsic { op: entry.op, arity: arity(entry.shape), floating: false, wide: true, shape: entry.shape , ..}); } }
        return squid_support::none<Intrinsic>();
    }
    let floating = startsWith(name, "@simd.f32x4.");
    if !floating && !startsWith(name, "@simd.u32x4.") { return squid_support::none<Intrinsic>(); }
    let member = name[12..];
    for entry in shared { if equalBytes(member, entry.name) { return squid_support::some(Intrinsic { op: entry.op, arity: arity(entry.shape), floating: floating, wide: false, shape: entry.shape , ..}); } }
    if floating {
        for entry in floating_only { if equalBytes(member, entry.name) { return squid_support::some(Intrinsic { op: entry.op, arity: arity(entry.shape), floating: floating, wide: false, shape: entry.shape , ..}); } }
    } else {
        for entry in integer_only { if equalBytes(member, entry.name) { return squid_support::some(Intrinsic { op: entry.op, arity: arity(entry.shape), floating: floating, wide: false, shape: entry.shape , ..}); } }
    }
    return squid_support::none<Intrinsic>();
}
fn operation(op: squid_check_core::Op, lane: Lane) -> squid_support::Option<Intrinsic> {
    let floating = lane == Lane.floating;
    for entry in shared { if entry.op == op { return squid_support::some(Intrinsic { op: op, arity: arity(entry.shape), floating: floating, shape: entry.shape , ..}); } }
    if floating {
        for entry in floating_only { if entry.op == op { return squid_support::some(Intrinsic { op: op, arity: arity(entry.shape), floating: floating, shape: entry.shape , ..}); } }
    } else {
        for entry in integer_only { if entry.op == op { return squid_support::some(Intrinsic { op: op, arity: arity(entry.shape), floating: floating, shape: entry.shape , ..}); } }
    }
    return squid_support::none<Intrinsic>();
}
fn vectorOnly(op: squid_check_core::Op) -> bool {
    return op == squid_check_core::Op.shift_right_signed || op == squid_check_core::Op.min || op == squid_check_core::Op.max ||
        op == squid_check_core::Op.bit_not || op == squid_check_core::Op.bit_andnot || op == squid_check_core::Op.any_true || op == squid_check_core::Op.all_true ||
        op == squid_check_core::Op.select || op == squid_check_core::Op.shuffle || op == squid_check_core::Op.swizzle || op == squid_check_core::Op.broadcast ||
        op == squid_check_core::Op.bits || op == squid_check_core::Op.from_bits || op == squid_check_core::Op.relaxed_madd || op == squid_check_core::Op.relaxed_nmadd ||
        op == squid_check_core::Op.convert_i32_f32 || op == squid_check_core::Op.convert_f32_i32;
}
fn pairs(op: squid_check_core::Op) -> bool { op == squid_check_core::Op.select || op == squid_check_core::Op.relaxed_madd || op == squid_check_core::Op.relaxed_nmadd || op == squid_check_core::Op.shuffle }
fn literalLanes(op: squid_check_core::Op) -> bool { op == squid_check_core::Op.shuffle || op == squid_check_core::Op.swizzle || op == squid_check_core::Op.broadcast }
fn laneLimit(op: squid_check_core::Op) -> u32 { if op == squid_check_core::Op.shuffle { return 8; } return 4; }
