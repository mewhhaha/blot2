import std;
import os;
import closure_core;
import closure_parse;
import closure_validate;
import closure_resources;
import closure_wasm;
import closure_wasm_validate;
fn main() {
    let source = "let apply: (U32, U32) -> U32 = fn (capture, arg) => do:\n  let f = fn x => return x & capture\n  return f(arg)\n";
    var core, status = closure_parse::parse(source);
    assert(status == 0 && closure_validate::verify(source,core));
    assert(core.env_size == 4 && core.caller_frame == 4 && core.caller_depth == 2);
    let bytes = closure_wasm::emit(source,core);
    assert(bytes.len == 106 && closure_wasm_validate::verify(source,core,bytes));
    assert(write_file("closure_fixture.wasm",bytes));
    let alternate = "let other: (U32,U32)->U32 = fn (bias,input) => do:\n  let inner = fn value => return value & bias\n  return inner(input)";
    var other, alternate_status = closure_parse::parse(alternate);
    assert(alternate_status == 0 && closure_validate::verify(alternate,other));
    assert(closure_wasm::emit(alternate,other) == bytes);
    for i in bytes.len {
        var altered: u8[>..] = []; altered.append(bytes); altered[i] ^= 1;
        assert(!closure_wasm_validate::verify(source,core,altered));
        assert(!closure_wasm_validate::verify(source,core,bytes[..i]));
    }
    var extra: u8[>..] = []; extra.append(bytes); extra.push(0);
    assert(!closure_wasm_validate::verify(source,core,extra));
    assert(!closure_validate::verify(alternate,core));
    assert(closure_wasm::emit(alternate,core).len == 0);
    for i in 14 {
        var bad = copy(core);
        if i == 0 { bad.schema = 0; } else if i == 1 { bad.capture_kind = 2; }
        else if i == 2 { bad.capture_version = 2; } else if i == 3 { bad.argument_version = 3; }
        else if i == 4 { bad.inner_version = 4; } else if i == 5 { bad.mode = 2; }
        else if i == 6 { bad.placement = 2; } else if i == 7 { bad.escaping = 1; }
        else if i == 8 { bad.env_size = 3; } else if i == 9 { bad.env_align = 8; }
        else if i == 10 { bad.env_offset = 1; } else if i == 11 { bad.code_slot = 1; }
        else if i == 12 { bad.caller_frame = 3; } else { bad.worker_depth = 2; }
        assert(!closure_validate::verify(source,bad) && closure_wasm::emit(source,bad).len == 0);
    }
    for i in 9 {
        var bad = copy(core);
        if i == 0 { bad.function.start = -1; } else if i == 1 { bad.capture.end = 9223372036854775807; }
        else if i == 2 { bad.argument.start += 1; } else if i == 3 { bad.binding.end += 1; }
        else if i == 4 { bad.parameter.start = 0; } else if i == 5 { bad.inner_use.start += 1; }
        else if i == 6 { bad.capture_use.end -= 1; } else if i == 7 { bad.binding_use.start = -1; }
        else { bad.argument_use.end = 0; }
        assert(!closure_validate::verify(source,bad) && closure_wasm::emit(source,bad).len == 0);
    }
    for bad in ["let apply: (U32,U32)->U32 = fn (c,a) => do:\n  let f = fn x => return x & a\n  return f(a)",
                "let apply: (U32,U32)->U32 = fn (c,c) => do:\n  let f = fn x => return x & c\n  return f(c)",
                "let apply: (U32,U32)->U32 = fn (c,a) => do:\n  let f = fn x => return x & c\n  return f(c)",
                "let apply: (U32,U32)->U32 = fn (c,a) => do:\n  let f = fn x => return x + c\n  return f(a)"] {
        var rejected, st = closure_parse::parse(bad); assert(st != 0 && !closure_validate::verify(bad,rejected));
    }
    let good = [closure_resources::Fn { depth: 1 }, closure_resources::Fn { own: 4, frame: 4, depth: 2, callee: 1, indirect: true }];
    assert(closure_resources::validate(good) == 0);
    let depth = [good[0], closure_resources::Fn { own: 4, frame: 4, depth: 1, callee: 1, indirect: true }];
    assert(closure_resources::validate(depth) == 3);
    let frame = [good[0], closure_resources::Fn { own: 4, frame: 3, depth: 2, callee: 1, indirect: true }];
    assert(closure_resources::validate(frame) == 3);
    let overflow = [closure_resources::Fn { frame: 4294967295, depth: 1 }, closure_resources::Fn { own: 1, frame: 4294967295, depth: 2, callee: 1 }];
    assert(closure_resources::validate(overflow) == 3);
    let named_cycle = [closure_resources::Fn { depth: 1, callee: 2 }, closure_resources::Fn { depth: 1, callee: 1 }];
    assert(closure_resources::validate(named_cycle) == 2);
    let callback_cycle = [closure_resources::Fn { depth: 1, callee: 2 }, closure_resources::Fn { depth: 1, callee: 1, indirect: true }];
    assert(closure_resources::validate(callback_cycle) == 3);
    let indirect_predecessor = [closure_resources::Fn { depth: 1, callee: 2, indirect: true }, closure_resources::Fn { depth: 1, callee: 2 }];
    assert(closure_resources::validate(indirect_predecessor) == 2);
    assert(closure_resources::widens(1,4,2,4) && !closure_resources::widens(2,4,1,4));
    assert(!closure_resources::widens(1,4,1,3) && !closure_resources::widens(1,4,129,4));
    print("private source-bound checked closure and resources passed");
}
