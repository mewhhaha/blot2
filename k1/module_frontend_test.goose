import module_frontend;
import std;
import module_core;
import lexer;

fn rejected(source: u8[:], expected: i64) {
    let module, status = module_frontend::parse(source);
    assert(status == expected && module.source.len == 0 && module.declarations.len == 0);
}
fn valid(source: u8[:], n: i64) {
    var module, status = module_frontend::parse(source);
    assert(status == 0 && module.declarations.len == n);
    assert(module_frontend::verify(module) == 0);
}
fn chain(count: i64) -> u8[>..] {
    var out: u8[>..] = [];
    for i in count {
        if i + 1 == count { format(out, "let f", i, ": U32 -> U32 = fn x => return x\n"); }
        else { format(out, "let f", i, ": U32 -> U32 = fn x => return f", i + 1, "(x)\n"); }
    }
    return out;
}
fn long_cycle(count: i64) -> u8[>..] {
    var out: u8[>..] = [];
    for i in count {
        let next = if i + 1 == count { 0 } else { i + 1 };
        format(out, "let f", i, ": U32 -> U32 = fn x => return f", next, "(x)\n");
    }
    return out;
}
fn independent(count: i64) -> u8[>..] {
    var out: u8[>..] = [];
    for i in count { format(out, "let f", i, ": U32 -> U32 = fn x => return x\n"); }
    return out;
}
fn main() {
    let src = "let caller: U32 -> U32 = fn x => return callee(x)\nlet callee: U32 -> U32 = fn x => return x & 3\n";
    var module, status = module_frontend::parse(src);
    assert(status == 0 && module.declarations.len == 2 && module_frontend::verify(module) == 0);
    assert(module.declarations[0].form == 3 && module.declarations[0].callee_id == 1 && module.declarations[0].depth == 2);
    assert(module.declarations[1].form == 2 && module.declarations[1].depth == 1);
    // Construction is not authority: a forged input may produce a candidate,
    // but source/Core verification must reject it before emission.
    module.declarations[0].callee_id = 999;
    var forged = module_frontend::build_unvalidated_core(module);
    assert(module_frontend::verify_core(module, forged) != 0);
    assert(module_frontend::to_core(module).functions.len == 0);
    module.declarations[0].callee_id = 1;
    var candidate = module_frontend::build_unvalidated_core(module);
    assert(module_frontend::verify_core(module, candidate) == 0);
    module.declarations[0].form = 99;
    var forged_form = module_frontend::build_unvalidated_core(module);
    assert(module_frontend::verify_core(module, forged_form) != 0);
    module.declarations[0].form = 3;
    module.declarations[0].name_start = -1;
    var forged_span = module_frontend::build_unvalidated_core(module);
    assert(module_frontend::verify_core(module, forged_span) != 0);
    module.declarations[0].name_start = 4;
    var malformed_call = module.declarations[0];
    malformed_call.expression_end = src.len + 1;
    assert(!module_frontend::call_syntax(src, malformed_call));
    malformed_call = module.declarations[0]; malformed_call.expression_start = -1;
    assert(!module_frontend::call_syntax(src, malformed_call));
    malformed_call = module.declarations[0]; malformed_call.left_end = src.len + 1;
    assert(!module_frontend::call_syntax(src, malformed_call));
    assert(!module_frontend::word(src, lexer::Token { kind: 1, start: -1, end: 2 }, "x"));
    assert(!module_frontend::symbol(src, lexer::Token { kind: 5, start: 0, end: src.len + 1 }, "("));
    assert(!module_frontend::same_name(src, -1, 1, 0, 1));

    var core = module_frontend::to_core(module);
    assert(module_frontend::verify_core(module, core) == 0);
    // A different constant can be structurally valid but disagrees with source.
    core.functions[1].values[1].literal = 2;
    assert(module_core::validate(core) == 0 && module_frontend::verify_core(module, core) == 1);
    core.functions[1].values[1].literal = 3;
    assert(module_frontend::verify_core(module, core) == 0);
    core.functions[0].return_start += 1;
    assert(module_core::validate(core) == 0 && module_frontend::verify_core(module, core) == 1);
    core.functions[0].return_start -= 1;
    module.source[0] = 'X';
    assert(core.source[0] == 'l' && module_frontend::verify_core(module, core) == 1);
    module.source[0] = 'l';
    assert(module_frontend::verify_core(module, core) == 0);
    valid("let leaf: U32 -> U32 = fn x => return x\nlet b: U32 -> U32 = fn x => return leaf(0)\nlet a: U32 -> U32 = fn x => return b(x)\n", 3);
    valid("let a: U32 -> U32 = fn x => return f(x)\nlet b: U32 -> U32 = fn x => return f(4294967295)\nlet f: U32 -> U32 = fn x => return 1\n", 3);
    valid("let a: U32 -> U32 = fn x => do:\n  return do:\n    break b(x)\nlet b: U32 -> U32 = fn x => return x\n", 2);
    valid("let a: U32 -> U32 = fn x => return b(\n  x\n)\nlet b: U32 -> U32 = fn x => return x\n", 2);
    rejected("let a: U32 -> U32 = fn x => return missing(x)", 3);
    rejected("let a: U32 -> U32 = fn a => return a(0)", 7);
    rejected("let a: U32 -> U32 = fn x => return x\nlet a: U32 -> U32 = fn y => return y", 1);
    rejected("let a: U32 -> U32 = fn x => return a(x)", 8);
    rejected("let a: U32 -> U32 = fn x => return b(x)\nlet b: U32 -> U32 = fn x => return a(x)", 8);
    rejected("let a: U32 -> U32 = fn x => return x\nlet b: U32 -> U32 = fn x => return b(x)", 8);
    rejected("let f: U32 -> U32 = fn x => return f(f(x))", 2);
    rejected("let f: U32 -> U32 = fn x => return f()", 2);
    rejected("let U32: U32 -> U32 = fn x => return x", 1);
    rejected("let f: U32 -> U32 = fn x => return 4294967296", 1);
    rejected("let f: U32 -> Bool = fn x => return x < 1", 2);
    rejected("let f: U32 -> U32 = fn x => return x + 1", 2);
    rejected("let f: U32 -> U32 = fn x => return x let g: U32 -> U32 = fn y => return y", 2);
    rejected("let f: U32 -> U32 = fn x => do:\n  break x", 6);
    rejected("  let f: U32 -> U32 = fn x => return x", 1);
    let c128 = chain(128);
    var m128, s128 = module_frontend::parse(c128);
    assert(s128 == 0 && m128.declarations[0].depth == 128 && module_frontend::verify(m128) == 0);
    let c129 = chain(129);
    rejected(c129, 9);
    let cycle129 = long_cycle(129);
    rejected(cycle129, 8);
    let n256 = independent(256);
    var m256, s256 = module_frontend::parse(n256);
    assert(s256 == 0 && m256.declarations.len == 256 && module_frontend::verify(m256) == 0);
    let n257 = independent(257);
    rejected(n257, 2);

    // Source, names, call graph and resource receipts are rechecked, not trusted.
    module.declarations[0].callee_id = 0; assert(module_frontend::verify(module) == 1); module.declarations[0].callee_id = 1;
    module.declarations[0].depth = 1; assert(module_frontend::verify(module) == 1); module.declarations[0].depth = 2;
    module.declarations[0].left_kind = 1; assert(module_frontend::verify(module) == 1); module.declarations[0].left_kind = 0;
    module.declarations[0].callee_start = 0; assert(module_frontend::verify(module) == 1); module.declarations[0].callee_start = 40;
    assert(module_frontend::verify(module) == 0);
    module.source[0] = 'X'; assert(module_frontend::verify(module) == 1);
    print("module frontend laws passed");
}
