// Independent tests for the typed scalar Wasm encoder. No source authority is
// conveyed by these manually constructed transient Core values.
import os;
import std;
import scalar_core;
import scalar_plan;
import wasm;

fn require(ok: bool, message: u8[:]) {
    if !ok { abort(str("typed scalar wasm test: ", message)); }
}
fn build_fixture(result_type: i64, op: i64, left_kind: i64, left_literal: u32,
                 right_kind: i64, right_literal: u32) -> scalar_core::ScalarCore {
    var c = scalar_core::build(result_type, op, left_kind, left_literal, right_kind, right_literal);
    c.name_start = 1; c.name_end = 2;
    c.parameter_start = 3; c.parameter_end = 4;
    c.left_start = 5; c.left_end = 6;
    if op != 0 { c.operator_start = 7; c.operator_end = 8; c.right_start = 9; c.right_end = 10; }
    return c;
}
fn emit(name: u8[:], c: scalar_core::ScalarCore) -> u8[] {
    return wasm::emit_scalar_v2(name, scalar_plan::make(c));
}
fn main() {
    let numbers: i64[5] = [0, 1, 2147483647, 2147483648, 4294967295];
    for number, i in numbers {
        let n = number as u32;
        for op in 1..3 {
            let result_type = if op == 1 { 1 } else { 2 };
            let a = build_fixture(result_type, op, 0, 0, 1, n);
            let b = build_fixture(result_type, op, 1, n, 0, 0);
            let c = build_fixture(result_type, op, 1, n, 1, 1);
            require(write_file(str("v2_right_", op, "_", i, ".wasm"), emit("f", a)), "right");
            require(write_file(str("v2_left_", op, "_", i, ".wasm"), emit("f", b)), "left");
            require(write_file(str("v2_pair_", op, "_", i, ".wasm"), emit("f", c)), "pair");
        }
    }
    let unary = build_fixture(1, 0, 0, 0, 0, 0);
    require(emit("f", unary).len > 0, "unary");
    require(emit("return", unary).len == 0, "reserved name");
    var c = build_fixture(1, 1, 1, 7, 1, 7);
    require(emit("f", c).len > 0, "valid");
    c.values[3].right_id = 1;
    require(emit("f", c).len == 0, "reused literal record");
    c = build_fixture(1, 1, 1, 7, 0, 0);
    c.values[2].left_id = 2;
    require(emit("f", c).len == 0, "forward reference");
    c = build_fixture(1, 1, 0, 0, 1, 7);
    c.values[1].type_id = 2;
    require(emit("f", c).len == 0, "bad operand type");
    c = build_fixture(2, 2, 0, 0, 1, 7);
    c.values[2].type_id = 1;
    require(emit("f", c).len == 0, "bad result type");
    c = build_fixture(1, 0, 0, 0, 0, 0);
    c.values[3].literal = 1;
    require(emit("f", c).len == 0, "nonzero unused field");
    c = build_fixture(1, 1, 0, 0, 1, 7);
    c.values[2].op_id = 9;
    require(emit("f", c).len == 0, "unknown op");
    c = build_fixture(1, 1, 0, 0, 1, 7);
    c.terminator = 0;
    require(emit("f", c).len == 0, "missing terminator");
    c = build_fixture(1, 1, 0, 0, 1, 7);
    var plan = scalar_plan::make(c);
    plan.opcode = 0x49;
    require(wasm::emit_scalar_v2("f", plan).len == 0, "forged plan opcode");
    plan = scalar_plan::make(c);
    plan.memory_maximum_pages = 276;
    require(wasm::emit_scalar_v2("f", plan).len == 0, "forged memory plan");
}
