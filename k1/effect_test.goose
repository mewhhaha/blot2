import effect_core;
import effect_build;
import effect_verify;
import module_frontend;
import std;

fn bounds_for(source: u8[:]) -> effect_core::Bound[>..] {
    var m, status = module_frontend::parse(source);
    assert(status == 0);
    var result: effect_core::Bound[>..] = [];
    for d in m.declarations {
        result.push(effect_core::Bound { name_start: d.name_start, name_end: d.name_end, depth: d.depth });
    }
    return result;
}
fn chain(count: i64) -> u8[>..] {
    var result: u8[>..] = [];
    for i in count {
        if i + 1 == count { format(result, "let f", i, ": U32 -> U32 = fn x => return x\n"); }
        else { format(result, "let f", i, ": U32 -> U32 = fn x => return f", i + 1, "(x)\n"); }
    }
    return result;
}
fn main() {
    let source = "let a: U32 -> U32 = fn x => return b(x)\nlet b: U32 -> U32 = fn x => return c(x)\nlet c: U32 -> U32 = fn x => return x & 3\n";
    var bounds = bounds_for(source);
    bounds[0].effects = 7; bounds[1].effects = 3; bounds[2].effects = 1;
    bounds[0].frame = 4294967295; bounds[1].frame = 17; bounds[2].frame = 16;
    var summary, ok = effect_build::build(source, bounds);
    assert(ok && effect_verify::verify(source, bounds, summary));
    assert(summary.entries[0].actual_depth == 3 && summary.entries[1].actual_depth == 2 && summary.entries[2].actual_depth == 1);
    assert(summary.entries[0].callee == 1 && summary.entries[1].callee == 2 && summary.entries[2].callee == -1);
    summary.entries[0].callee = 2; assert(!effect_verify::verify(source, bounds, summary)); summary.entries[0].callee = 1;
    summary.entries[0].callee = 999; assert(!effect_verify::verify(source, bounds, summary)); summary.entries[0].callee = 1;
    summary.entries[0].actual_depth = 2; assert(!effect_verify::verify(source, bounds, summary)); summary.entries[0].actual_depth = 3;
    summary.entries[0].actual_frame = 1; assert(!effect_verify::verify(source, bounds, summary)); summary.entries[0].actual_frame = 0;
    summary.entries[0].actual_effects = 1; assert(!effect_verify::verify(source, bounds, summary)); summary.entries[0].actual_effects = 0;
    summary.entries[0].bound.frame = 0; assert(!effect_verify::verify(source, bounds, summary)); summary.entries[0].bound.frame = 4294967295;
    summary.entries[0].bound.effects = 0; assert(!effect_verify::verify(source, bounds, summary)); summary.entries[0].bound.effects = 7;
    summary.entries[0].bound.depth = 1; assert(!effect_verify::verify(source, bounds, summary)); summary.entries[0].bound.depth = 3;
    summary.entries[0].bound.name_start = -1; assert(!effect_verify::verify(source, bounds, summary)); summary.entries[0].bound.name_start = bounds[0].name_start;
    summary.entries[0].bound.name_end += 1; assert(!effect_verify::verify(source, bounds, summary)); summary.entries[0].bound.name_end = bounds[0].name_end;
    summary.entries[2].callee = 0; assert(!effect_verify::verify(source, bounds, summary)); summary.entries[2].callee = -1;
    summary.source[0] = 'X'; assert(!effect_verify::verify(source, bounds, summary)); summary.source[0] = 'l';
    assert(!effect_verify::verify("let replacement: U32 -> U32 = fn x => return x", bounds, summary));
    assert(effect_verify::verify(source, bounds, summary));
    bounds[0].effects = 2;
    let _, bad_effect = effect_build::build(source, bounds); assert(!bad_effect && !effect_verify::verify(source, bounds, summary));
    bounds[0].effects = 8;
    let _, unknown_effect = effect_build::build(source, bounds); assert(!unknown_effect);
    bounds[0].effects = 7; bounds[0].depth = 2;
    let _, depth = effect_build::build(source, bounds); assert(!depth);
    bounds[0].depth = 3; bounds[1].depth = 3;
    let _, advertised_depth = effect_build::build(source, bounds); assert(!advertised_depth);
    bounds[1].depth = 2; bounds[0].frame = 16;
    let _, advertised_frame = effect_build::build(source, bounds); assert(!advertised_frame);
    bounds[0].frame = 4294967296;
    let _, huge_frame = effect_build::build(source, bounds); assert(!huge_frame);
    bounds[0].frame = 4294967295; bounds[0].name_start = -1;
    let _, wrong_name = effect_build::build(source, bounds); assert(!wrong_name);
    var single: effect_core::Bound[>..] = [effect_core::Bound { name_start: 4, name_end: 5, depth: 1 }];
    let _, hidden = effect_build::build("let f: U32 -> U32 = fn x => return f(f(x))", single); assert(!hidden);
    let _, cycle_ok = effect_build::build("let f: U32 -> U32 = fn x => return f(x)", single); assert(!cycle_ok);
    let _, import_call = effect_build::build("let f: U32 -> U32 = fn x => return host(x)", single); assert(!import_call);
    let _, unsupported_effect = effect_build::build("let f: U32 -> U32 = fn x => do:\n  reserve x\n  return x\n", single); assert(!unsupported_effect);
    let max_source = chain(128);
    let max_bounds = bounds_for(max_source);
    var max_summary, max_ok = effect_build::build(max_source, max_bounds);
    assert(max_ok && effect_verify::verify(max_source, max_bounds, max_summary));
    let too_deep = chain(129);
    let _, too_deep_ok = effect_build::build(too_deep, max_bounds); assert(!too_deep_ok);
    print("effect summary tests passed\n");
}
