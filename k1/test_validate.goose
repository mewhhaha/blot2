import validate;
import frontend;
import scalar_core;
fn build_v2(source: u8[:]) -> scalar_core::ScalarCore {
    let parsed = frontend::parse_scalar(source);
    assert(parsed.status == 0);
    var core = scalar_core::build(parsed.result_type, parsed.binary_op, parsed.kind,
        parsed.literal, parsed.right_kind, parsed.right_literal);
    core.name_start = parsed.name_start; core.name_end = parsed.name_end;
    core.parameter_start = parsed.parameter_start; core.parameter_end = parsed.parameter_end;
    core.left_start = parsed.start; core.left_end = parsed.end;
    core.operator_start = parsed.operator_start; core.operator_end = parsed.operator_end;
    core.right_start = parsed.right_start; core.right_end = parsed.right_end;
    return core;
}
fn check_v2(source: u8[:], core: scalar_core::ScalarCore) -> i64 {
    return validate::scalar_v2(source, core, "k1", "K1-SEM-POLICY-1",
        "K1-OPT-POLICY-1", "K1-WASM32-ABI1");
}
fn main() {
    let and_source = "let f: U32 -> U32 = fn x => return x & 4294967295";
    let and_core = build_v2(and_source);
    assert(check_v2(and_source, and_core) == 0);
    let cmp_source = "let f: U32 -> Bool = fn x => return 4294967295 < x";
    let cmp_core = build_v2(cmp_source);
    assert(check_v2(cmp_source, cmp_core) == 0);
    let block_source = "let f: U32 -> Bool = fn x => do:\n  return do:\n    break x < 2\n";
    let block_core = build_v2(block_source);
    assert(check_v2(block_source, block_core) == 0);
    let constants_source = "let f: U32 -> Bool = fn x => return 1 < 1";
    let constants = build_v2(constants_source);
    assert(constants.value_count == 4 && check_v2(constants_source, constants) == 0);
    var bad_constants = constants;
    bad_constants.values[3].right_id = 1; // identical constants still have distinct IDs
    assert(check_v2(constants_source, bad_constants) == 1);
    let scalar_source = "let f: U32 -> U32 = fn x => return x";
    let scalar = build_v2(scalar_source);
    assert(check_v2(scalar_source, scalar) == 0);
    var forged = and_core;
    forged.values[2].op_id = 2;
    assert(check_v2(and_source, forged) == 1);
    forged = and_core;
    forged.values[2].left_id = 2; // forward/self reference
    assert(check_v2(and_source, forged) == 1);
    forged = and_core;
    forged.values[2].right_id = -1;
    assert(check_v2(and_source, forged) == 1);
    forged = and_core;
    forged.values[1].literal = 0;
    assert(check_v2(and_source, forged) == 1);
    forged = and_core;
    forged.values[1].type_id = 2;
    assert(check_v2(and_source, forged) == 1);
    forged = and_core;
    forged.values[3].producer = 1; // inactive records must be zero
    assert(check_v2(and_source, forged) == 1);
    forged = and_core;
    forged.result_type = 2;
    assert(check_v2(and_source, forged) == 1);
    forged = and_core;
    forged.operator_start = 0;
    assert(check_v2(and_source, forged) == 1);
    forged = and_core;
    forged.parameter_start = 0;
    assert(check_v2(and_source, forged) == 1);
    forged = and_core;
    forged.value_count = 5;
    assert(check_v2(and_source, forged) == 1);
    assert(validate::scalar_v2(and_source, and_core, "legacy", "K1-SEM-POLICY-1", "K1-OPT-POLICY-1", "K1-WASM32-ABI1") == 2);
    let source = "let id: U32 -> U32 = fn x => return x";
    assert(validate::scalar(source, 36, 37, 4, 6, 0, 0, "k1", "K1-SEM-POLICY-1", "K1-OPT-POLICY-1", "K1-WASM32-ABI1") == 0);
    assert(validate::scalar(source, 24, 25, 4, 6, 0, 0, "k1", "K1-SEM-POLICY-1", "K1-OPT-POLICY-1", "K1-WASM32-ABI1") == 1);
    let forged = "let id: U32 -> U32 = fn y => return x";
    assert(validate::scalar(forged, 36, 37, 4, 6, 0, 0, "k1", "K1-SEM-POLICY-1", "K1-OPT-POLICY-1", "K1-WASM32-ABI1") == 1);
    let constant = "let id: U32 -> U32 = fn x => return 4294967295";
    assert(validate::scalar(constant, 36, 46, 4, 6, 1, 4294967295, "k1", "K1-SEM-POLICY-1", "K1-OPT-POLICY-1", "K1-WASM32-ABI1") == 0);
    assert(validate::scalar(constant, 36, 46, 4, 6, 1, 0, "k1", "K1-SEM-POLICY-1", "K1-OPT-POLICY-1", "K1-WASM32-ABI1") == 1);
    assert(validate::scalar(source, 36, 37, 4, 6, 2, 0, "k1", "K1-SEM-POLICY-1", "K1-OPT-POLICY-1", "K1-WASM32-ABI1") == 1);
    assert(validate::scalar(source, -1, 37, 4, 6, 0, 0, "k1", "K1-SEM-POLICY-1", "K1-OPT-POLICY-1", "K1-WASM32-ABI1") == 1);
    assert(validate::scalar(source, 36, 38, 4, 6, 0, 0, "k1", "K1-SEM-POLICY-1", "K1-OPT-POLICY-1", "K1-WASM32-ABI1") == 1);
    assert(validate::scalar(source, 36, 37, 4, 6, 0, 0, "k1", "bad", "K1-OPT-POLICY-1", "K1-WASM32-ABI1") == 2);
    assert(validate::scalar(source, 36, 37, 4, 6, 0, 0, "k1", "K1-SEM-POLICY-1", "bad", "K1-WASM32-ABI1") == 2);
    assert(validate::scalar(source, 36, 37, 4, 6, 0, 0, "k1", "K1-SEM-POLICY-1", "K1-OPT-POLICY-1", "bad") == 2);
    assert(validate::scalar(source, 36, 37, 4, 6, 0, 0, "legacy", "K1-SEM-POLICY-1", "K1-OPT-POLICY-1", "K1-WASM32-ABI1") == 2);
    assert(validate::scalar("let Type: U32 -> U32 = fn x => return x", 38, 39, 4, 8, 0, 0, "k1", "K1-SEM-POLICY-1", "K1-OPT-POLICY-1", "K1-WASM32-ABI1") == 1);
    assert(validate::scalar("let id: U32 -> U32 = fn Type => return Type", 39, 43, 4, 6, 0, 0, "k1", "K1-SEM-POLICY-1", "K1-OPT-POLICY-1", "K1-WASM32-ABI1") == 1);
    assert(validate::scalar("let Region: U32 -> U32 = fn x => return x", 40, 41, 4, 10, 0, 0, "k1", "K1-SEM-POLICY-1", "K1-OPT-POLICY-1", "K1-WASM32-ABI1") == 1);
    assert(validate::scalar("let id: U32 -> U32 = fn Region => return Region", 41, 47, 4, 6, 0, 0, "k1", "K1-SEM-POLICY-1", "K1-OPT-POLICY-1", "K1-WASM32-ABI1") == 1);
    assert(validate::scalar("let Nat: U32 -> U32 = fn x => return x", 37, 38, 4, 7, 0, 0, "k1", "K1-SEM-POLICY-1", "K1-OPT-POLICY-1", "K1-WASM32-ABI1") == 1);
    assert(validate::scalar("let id: U32 -> U32 = fn Nat => return Nat", 38, 41, 4, 6, 0, 0, "k1", "K1-SEM-POLICY-1", "K1-OPT-POLICY-1", "K1-WASM32-ABI1") == 1);
    assert(validate::scalar("let Domain: U32 -> U32 = fn x => return x", 40, 41, 4, 10, 0, 0, "k1", "K1-SEM-POLICY-1", "K1-OPT-POLICY-1", "K1-WASM32-ABI1") == 1);
    assert(validate::scalar("let id: U32 -> U32 = fn Domain => return Domain", 41, 47, 4, 6, 0, 0, "k1", "K1-SEM-POLICY-1", "K1-OPT-POLICY-1", "K1-WASM32-ABI1") == 1);
    assert(validate::scalar("let Plain: U32 -> U32 = fn x => return x", 39, 40, 4, 9, 0, 0, "k1", "K1-SEM-POLICY-1", "K1-OPT-POLICY-1", "K1-WASM32-ABI1") == 1);
    assert(validate::scalar("let id: U32 -> U32 = fn Plain => return Plain", 40, 45, 4, 6, 0, 0, "k1", "K1-SEM-POLICY-1", "K1-OPT-POLICY-1", "K1-WASM32-ABI1") == 1);
    assert(validate::scalar("let Share: U32 -> U32 = fn x => return x", 39, 40, 4, 9, 0, 0, "k1", "K1-SEM-POLICY-1", "K1-OPT-POLICY-1", "K1-WASM32-ABI1") == 1);
    assert(validate::scalar("let id: U32 -> U32 = fn Share => return Share", 40, 45, 4, 6, 0, 0, "k1", "K1-SEM-POLICY-1", "K1-OPT-POLICY-1", "K1-WASM32-ABI1") == 1);
    assert(validate::scalar("let\r id: U32 -> U32 = fn x => return x", 37, 38, 5, 7, 0, 0, "k1", "K1-SEM-POLICY-1", "K1-OPT-POLICY-1", "K1-WASM32-ABI1") == 1);
    let bad_utf_0: u8[] = [108, 101, 116, 32, 105, 100, 58, 32, 85, 51, 50, 32, 45, 62, 32, 85, 51, 50, 32, 61, 32, 102, 110, 32, 120, 32, 61, 62, 32, 114, 101, 116, 117, 114, 110, 32, 120, 32, 47, 47, 32, 255];
    assert(validate::scalar(bad_utf_0, 36, 37, 4, 6, 0, 0, "k1", "K1-SEM-POLICY-1", "K1-OPT-POLICY-1", "K1-WASM32-ABI1") == 1);
    let bad_utf_1: u8[] = [108, 101, 116, 32, 105, 100, 58, 32, 85, 51, 50, 32, 45, 62, 32, 85, 51, 50, 32, 61, 32, 102, 110, 32, 120, 32, 61, 62, 32, 114, 101, 116, 117, 114, 110, 32, 120, 32, 47, 47, 32, 192, 175];
    assert(validate::scalar(bad_utf_1, 36, 37, 4, 6, 0, 0, "k1", "K1-SEM-POLICY-1", "K1-OPT-POLICY-1", "K1-WASM32-ABI1") == 1);
    let bad_utf_2: u8[] = [108, 101, 116, 32, 105, 100, 58, 32, 85, 51, 50, 32, 45, 62, 32, 85, 51, 50, 32, 61, 32, 102, 110, 32, 120, 32, 61, 62, 32, 114, 101, 116, 117, 114, 110, 32, 120, 32, 47, 47, 32, 237, 160, 128];
    assert(validate::scalar(bad_utf_2, 36, 37, 4, 6, 0, 0, "k1", "K1-SEM-POLICY-1", "K1-OPT-POLICY-1", "K1-WASM32-ABI1") == 1);
    let bad_utf_3: u8[] = [108, 101, 116, 32, 105, 100, 58, 32, 85, 51, 50, 32, 45, 62, 32, 85, 51, 50, 32, 61, 32, 102, 110, 32, 120, 32, 61, 62, 32, 114, 101, 116, 117, 114, 110, 32, 120, 32, 47, 47, 32, 244, 144, 128, 128];
    assert(validate::scalar(bad_utf_3, 36, 37, 4, 6, 0, 0, "k1", "K1-SEM-POLICY-1", "K1-OPT-POLICY-1", "K1-WASM32-ABI1") == 1);
    let bad_utf_4: u8[] = [108, 101, 116, 32, 105, 100, 58, 32, 85, 51, 50, 32, 45, 62, 32, 85, 51, 50, 32, 61, 32, 102, 110, 32, 120, 32, 61, 62, 32, 114, 101, 116, 117, 114, 110, 32, 120, 32, 47, 47, 32, 226, 130];
    assert(validate::scalar(bad_utf_4, 36, 37, 4, 6, 0, 0, "k1", "K1-SEM-POLICY-1", "K1-OPT-POLICY-1", "K1-WASM32-ABI1") == 1);
    let good_utf: u8[] = [108, 101, 116, 32, 105, 100, 58, 32, 85, 51, 50, 32, 45, 62, 32, 85, 51, 50, 32, 61, 32, 102, 110, 32, 120, 32, 61, 62, 32, 114, 101, 116, 117, 114, 110, 32, 120, 32, 47, 47, 32, 195, 169, 13, 10];
    assert(validate::scalar(good_utf, 36, 37, 4, 6, 0, 0, "k1", "K1-SEM-POLICY-1", "K1-OPT-POLICY-1", "K1-WASM32-ABI1") == 0);
    assert(validate::scalar("let f: U32 -> U32 = fn x => do:\n  return x\n", 41, 42, 4, 5, 0, 0, "k1", "K1-SEM-POLICY-1", "K1-OPT-POLICY-1", "K1-WASM32-ABI1") == 0);
    assert(validate::scalar("let f: U32 -> U32 = fn x => return do:\n  break x\n", 47, 48, 4, 5, 0, 0, "k1", "K1-SEM-POLICY-1", "K1-OPT-POLICY-1", "K1-WASM32-ABI1") == 0);
    assert(validate::scalar("let f: U32 -> U32 = fn y => return do:\n  break x\n", 47, 48, 4, 5, 0, 0, "k1", "K1-SEM-POLICY-1", "K1-OPT-POLICY-1", "K1-WASM32-ABI1") == 1);
    assert(validate::scalar("let f: U32 -> U32 = fn x => do:\n  break x\n", 40, 41, 4, 5, 0, 0, "k1", "K1-SEM-POLICY-1", "K1-OPT-POLICY-1", "K1-WASM32-ABI1") == 1);
    assert(validate::scalar("let f: U32 -> U32 = fn x => do:\n   return x\n", 42, 43, 4, 5, 0, 0, "k1", "K1-SEM-POLICY-1", "K1-OPT-POLICY-1", "K1-WASM32-ABI1") == 1);
}
