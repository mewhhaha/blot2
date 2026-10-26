import frontend;
import validate;

fn invalid_comment(bytes: u8[:]) -> bool {
    var source: u8[>..] = [];
    source.append("// ");
    source.append(bytes);
    source.append("\nlet f: U32 -> U32 = fn x => return x\n");
    let result = frontend::parse_scalar(source[..]);
    return result.status == 1 && result.start == 3 && result.end == 4;
}

// These are executable admission laws for the deliberately small scalar slice.
// Later K1 grammar must not turn an unimplemented construct into an admitted
// program without checking its semantics.
fn main() {
    // Restricted typed binary subset: single operation, U32 operands.
    let and_source = "let f: U32 -> U32 = fn x => return x & 4294967295";
    let bitand = frontend::parse_scalar(and_source);
    assert(bitand.status == 0 && bitand.result_type == 1 && bitand.binary_op == 1);
    assert(bitand.kind == 0 && bitand.right_kind == 1 && bitand.right_literal == 4294967295);
    assert(and_source[bitand.parameter_start..bitand.parameter_end] == "x");
    assert(and_source[bitand.start..bitand.end] == "x");
    assert(and_source[bitand.operator_start..bitand.operator_end] == "&");
    assert(and_source[bitand.right_start..bitand.right_end] == "4294967295");
    let cmp_source = "let f: U32 -> Bool = fn x => return 0 < x";
    let cmp = frontend::parse_scalar(cmp_source);
    assert(cmp.status == 0 && cmp.result_type == 2 && cmp.binary_op == 2);
    assert(cmp.kind == 1 && cmp.literal == 0 && cmp.right_kind == 0);
    assert(cmp_source[cmp.operator_start..cmp.operator_end] == "<");
    assert(frontend::parse_scalar("let f: U32 -> Bool = fn x => return x < 1").status == 0);
    assert(frontend::parse_scalar("let f: U32 -> U32 = fn x => return x < 1").status == 7);
    assert(frontend::parse_scalar("let f: U32 -> Bool = fn x => return x & 1").status == 7);
    assert(frontend::parse_scalar("let f: U32 -> Bool = fn x => return x").status == 7);
    assert(frontend::parse_scalar("let f: U32 -> U32 = fn x => return x & y").status == 3);
    assert(frontend::parse_scalar("let f: U32 -> U32 = fn x => return x & 4294967296").status == 1);
    assert(frontend::parse_scalar("let f: U32 -> U32 = fn x => return x & 1 & 1").status == 2);
    assert(frontend::parse_scalar("let f: U32 -> Bool = fn x => return x < 1 < 2").status == 2);
    assert(frontend::parse_scalar("let f: U32 -> U32 = fn x => return x && x").status == 2);
    assert(frontend::parse_scalar("let f: U32 -> Bool = fn x => return x <= 1").status == 2);
    assert(frontend::parse_scalar("let f: U32 -> U32 = fn x => return x << 1").status == 2);
    // SYN-A01: explicit short, body-block and value-block exits agree.
    let body_block_source = "let f: U32 -> U32 = fn x => do:\n  return x\n";
    let body_block = frontend::parse_scalar(body_block_source);
    assert(body_block.status == 0 && body_block.kind == 0);
    assert(validate::scalar(body_block_source, body_block.start, body_block.end, body_block.name_start, body_block.name_end, body_block.kind, body_block.literal, "k1", "K1-SEM-POLICY-1", "K1-OPT-POLICY-1", "K1-WASM32-ABI1") == 0);
    let value_block_source = "let f: U32 -> U32 = fn x => return do:\n  break x\n";
    let value_block = frontend::parse_scalar(value_block_source);
    assert(value_block.status == 0 && value_block.kind == 0);
    assert(validate::scalar(value_block_source, value_block.start, value_block.end, value_block.name_start, value_block.name_end, value_block.kind, value_block.literal, "k1", "K1-SEM-POLICY-1", "K1-OPT-POLICY-1", "K1-WASM32-ABI1") == 0);
    let nested_source = "let f: U32 -> U32 = fn x => do:\n  return do:\n    break 42\n";
    let nested = frontend::parse_scalar(nested_source);
    assert(nested.status == 0 && nested.kind == 1 && nested.literal == 42);
    assert(validate::scalar(nested_source, nested.start, nested.end, nested.name_start, nested.name_end, nested.kind, nested.literal, "k1", "K1-SEM-POLICY-1", "K1-OPT-POLICY-1", "K1-WASM32-ABI1") == 0);
    let inner_return_source = "let f: U32 -> U32 = fn x => return do:\n  return x\n";
    let inner_return = frontend::parse_scalar(inner_return_source);
    assert(inner_return.status == 0 && inner_return.kind == 0);
    assert(validate::scalar(inner_return_source, inner_return.start, inner_return.end, inner_return.name_start, inner_return.name_end, inner_return.kind, inner_return.literal, "k1", "K1-SEM-POLICY-1", "K1-OPT-POLICY-1", "K1-WASM32-ABI1") == 0);
    assert(frontend::parse_scalar("let f: U32 -> U32 = fn x => do:\n  x\n").status == 4);
    assert(frontend::parse_scalar("let f: U32 -> U32 = fn x => do:\n  break x\n").status == 6);
    assert(frontend::parse_scalar("let f: U32 -> U32 = fn x => break x").status == 6);
    assert(frontend::parse_scalar("let f: U32 -> U32 = fn x => return continue").status == 6);
    assert(frontend::parse_scalar("let f: U32 -> U32 = fn x => return do:\n  continue\n").status == 6);
    assert(frontend::parse_scalar("let f: U32 -> U32 = fn x => do:\n return x\n").status == 1);
    assert(frontend::parse_scalar("let f: U32 -> U32 = fn x => do:\n    return x\n").status == 1);
    assert(frontend::parse_scalar("let f: U32 -> U32 = fn x => return do:\n  x\n").status == 4);
    assert(frontend::parse_scalar("let f: U32 -> U32 = fn x => return do:\n  break y\n").status == 3);
    assert(frontend::parse_scalar("let f: U32 -> U32 = fn x => do: return x").status == 1);
    assert(frontend::parse_scalar("let f: U32 -> U32 = fn x => do:\n  return x\n  return x\n").status != 0);
    let identity = frontend::parse_scalar("let identity: U32 -> U32 = fn x => return x\n");
    assert(identity.status == 0 && identity.kind == 0);
    assert(identity.name_start == 4 && identity.name_end == 12);
    let maximum = frontend::parse_scalar("// heading\nlet value: U32 -> U32 = fn x => return 4294967295 // comment\n");
    assert(maximum.status == 0 && maximum.kind == 1 && maximum.literal == 4294967295);
    let zero = frontend::parse_scalar("let f: U32 -> U32 = fn x => return 0");
    assert(zero.status == 0 && zero.kind == 1 && zero.literal == 0);
    let overflow = frontend::parse_scalar("let f: U32 -> U32 = fn x => return 4294967296");
    assert(overflow.status == 1);
    let huge_number = frontend::parse_scalar("let f: U32 -> U32 = fn x => return 99999999999999999999999999999999");
    assert(huge_number.status == 1);
    let unbound = frontend::parse_scalar("let f: U32 -> U32 = fn x => return y");
    assert(unbound.status == 3);
    let missing = frontend::parse_scalar("let f: U32 -> U32 = fn x => x");
    assert(missing.status == 4);
    let truncated = frontend::parse_scalar("let f: U32 -> U32 = fn x => return");
    assert(truncated.status == 1);
    let arithmetic = frontend::parse_scalar("let f: U32 -> U32 = fn x => return x + 1");
    assert(arithmetic.status == 2);
    let second = frontend::parse_scalar("let f: U32 -> U32 = fn x => return x\nlet g: U32 -> U32 = fn x => return x");
    assert(second.status == 2);
    let reserved = frontend::parse_scalar("let U32: U32 -> U32 = fn x => return x");
    assert(reserved.status == 1);
    let indent = frontend::parse_scalar(" let f: U32 -> U32 = fn x => return x");
    assert(indent.status == 1);
    let invalid_byte = frontend::parse_scalar("let f: U32 -> U32 = fn x => return \t");
    assert(invalid_byte.status == 1);
    let bare_cr = frontend::parse_scalar("let\r f: U32 -> U32 = fn x => return x");
    assert(bare_cr.status == 1);
    let crlf = frontend::parse_scalar("// comment\r\nlet f: U32 -> U32 = fn x => return x\r\n");
    assert(crlf.status == 0);
    let utf8 = frontend::parse_scalar("// café 漢字 🌍\nlet f: U32 -> U32 = fn x => return x\n");
    assert(utf8.status == 0);
    assert(invalid_comment([128]));              // lone continuation
    assert(invalid_comment([192, 128]));         // overlong U+0000
    assert(invalid_comment([224, 128, 128]));    // overlong three-byte form
    assert(invalid_comment([237, 160, 128]));    // UTF-16 surrogate
    assert(invalid_comment([240, 128, 128, 128])); // overlong four-byte form
    assert(invalid_comment([244, 144, 128, 128])); // above U+10FFFF
    assert(invalid_comment([245, 128, 128, 128])); // invalid lead
    assert(invalid_comment([226, 40, 161]));     // invalid continuation
    assert(invalid_comment([226]));              // newline cannot complete a sequence
    let truncated_utf8: u8[] = ['/', '/', ' ', 226];
    let bad_end = frontend::parse_scalar(truncated_utf8[..]);
    assert(bad_end.status == 1 && bad_end.start == 3 && bad_end.end == 4);
    var boundary: u8[>..] = [];
    for i in 16777216 { boundary.push('x'); }
    assert(frontend::parse_scalar(boundary[..]).status == 2);
    boundary.push(255); // The size limit is checked before UTF-8 validation.
    assert(frontend::parse_scalar(boundary[..]).status == 5);
    print("frontend laws passed");
}
