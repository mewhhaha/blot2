import os;
import loop_core;
import loop_parse;
import loop_validate;
import loop_wasm;
fn source() -> u8[] {
    return "pub let copy_into: forall [r: Region, s: Region, n: Nat, c: Nat, d: Domain] => Fn[static, Many, (View[r,U32,n,d], Builder[s,U32,0,c,Append]), Builder[s,U32,n,c,Append]] ! {read r, write s} requires [Le(n,c)] resources {depth: 1, frame: 256} = fn (source,initial) => do:\n  let built = for i in 0..n carry (b = initial)\n    invariant [Eq(Init(b),i)] do:\n      next (builder.append(b, source[i]))\n  return built\n";
}
fn replace(original: u8[:], before: u8[:], after: u8[:]) -> u8[] {
    var result: u8[>..] = []; var pos: i64 = 0; var found = false;
    while pos < original.len {
        if !found && before.len <= original.len-pos && original[pos..pos+before.len] == before {
            result.append(after); pos += before.len; found = true;
        } else { result.push(original[pos]); pos += 1; }
    }
    assert(found); return result;
}
fn copy_core(c: loop_core::Core&) -> loop_core::Core {
    return loop_core::Core { source: copy(c.source), context: c.context, sites: c.sites, evidence: c.evidence, ops: c.ops };
}
fn reject_change(core: loop_core::Core&, text: u8[:], ctx: loop_core::Context, data: u32[:], before: u8[:], after: u8[:]) {
    let changed = replace(text,before,after);
    var bad, error = loop_parse::parse(changed,ctx); assert(error != 0 && !loop_validate::verify(bad,changed,ctx));
    assert(!loop_validate::verify(core,changed,ctx) && loop_wasm::emit(core,changed,ctx,data).len == 0);
}
fn main() {
    let ctx = loop_core::Context { owner: 1,input: 2,input_version: 3,input_region: 4,input_domain: 5,length: 6,builder: 7,
        builder_version: 8,output_region: 9,capacity: 10,index: 11,next_builder: 12,next_version: 14,result: 13,result_version: 15 };
    let text = source(); var core,status = loop_parse::parse(text,ctx);
    assert(status == 0 && loop_validate::verify(core,text,ctx));
    assert(core.evidence[3].dep1 == 1 && core.evidence[3].dep2 == 2 && core.evidence[3].dep3 == 3);
    assert(core.evidence[4].left == ctx.next_builder && core.evidence[4].version == ctx.next_version &&
        core.evidence[5].left == ctx.result && core.evidence[5].version == ctx.result_version &&
        core.ops[0].proof1 == 3 && core.ops[1].proof1 == 4 && core.ops[1].output_version == ctx.next_version &&
        core.ops[2].version == ctx.next_version && core.ops[2].output_version == ctx.builder_version && core.ops[3].output_version == ctx.result_version);
    let data: u32[4] = [42,0xffffffff,0,123456789];
    let bytes = loop_wasm::emit(core,text,ctx,data); assert(bytes.len > 0 && write_file("loop-fixture.wasm",bytes));
    let empty: u32[0] = []; let zero = loop_wasm::emit(core,text,ctx,empty); assert(zero.len > 0 && write_file("loop-empty.wasm",zero));
    var max: u32[128] = [0;128]; for i in 128 { max[i] = (i as u32*65537)^0xa5a5a5a5; }
    let maximum = loop_wasm::emit(core,text,ctx,max); assert(maximum.len > 0 && write_file("loop-max.wasm",maximum));
    assert(write_file("loop-fault-0.wasm",loop_wasm::emit_test(core,text,ctx,data,0)));
    assert(write_file("loop-fault-1.wasm",loop_wasm::emit_test(core,text,ctx,data,1)));
    assert(write_file("loop-fault-2.wasm",loop_wasm::emit_test(core,text,ctx,data,2)));
    assert(write_file("loop-fault-3.wasm",loop_wasm::emit_test(core,text,ctx,data,3)));
    assert(write_file("loop-fault-4.wasm",loop_wasm::emit_test(core,text,ctx,data,4)));
    assert(write_file("loop-mid-0.wasm",loop_wasm::emit_test(core,text,ctx,data,129)));
    assert(write_file("loop-mid-1.wasm",loop_wasm::emit_test(core,text,ctx,data,130)));
    assert(write_file("loop-mid-2.wasm",loop_wasm::emit_test(core,text,ctx,data,131)));
    assert(write_file("loop-mid-3.wasm",loop_wasm::emit_test(core,text,ctx,data,132)));
    let without_final_newline = text[0..text.len-1]; var p2,s2 = loop_parse::parse(without_final_newline,ctx);
    assert(s2 == 0 && loop_validate::verify(p2,without_final_newline,ctx));
    reject_change(core,text,ctx,data,"Le(n,c)","Lt(n,c)"); reject_change(core,text,ctx,data,"Le(n,c)","Le(c,n)");
    reject_change(core,text,ctx,data,"Init(b),i","Init(b),n"); reject_change(core,text,ctx,data,"source[i]","source[i+1]");
    reject_change(core,text,ctx,data,"source[i]","source[n]"); reject_change(core,text,ctx,data,"builder.append","builder.set");
    reject_change(core,text,ctx,data,"next (","stop ("); reject_change(core,text,ctx,data,"for i in 0..n","for i in 1..n");
    reject_change(core,text,ctx,data,"for i in 0..n","for i in 0..c");
    reject_change(core,text,ctx,data,"Builder[s,U32,0,c,Append]","Builder[s,U32,1,c,Append]");
    reject_change(core,text,ctx,data,"read r, write s","write r, write s"); reject_change(core,text,ctx,data,"frame: 256","frame: 1");
    reject_change(core,text,ctx,data,"return built","return initial");
    // Independently forged proof rule, owner, operands, versions, dependencies,
    // and source site cannot pass validation or reach code emission.
    for i in 6 { for field in 9 {
        var bad = copy_core(core);
        if field == 0 { bad.evidence[i].rule += 1; }
        else if field == 1 { bad.evidence[i].owner += 1; }
        else if field == 2 { bad.evidence[i].left += 1; }
        else if field == 3 { bad.evidence[i].right += 1; }
        else if field == 4 { bad.evidence[i].version += 1; }
        else if field == 5 { bad.evidence[i].dep1 += 1; }
        else if field == 6 { bad.evidence[i].dep2 += 1; }
        else if field == 7 { bad.evidence[i].dep3 += 1; }
        else { bad.evidence[i].site += 1; }
        assert(!loop_validate::verify(bad,text,ctx) && loop_wasm::emit(bad,text,ctx,data).len == 0);
    } }
    for i in 4 { for field in 11 {
        var bad = copy_core(core);
        if field == 0 { bad.ops[i].kind += 1; }
        else if field == 1 { bad.ops[i].owner += 1; }
        else if field == 2 { bad.ops[i].input += 1; }
        else if field == 3 { bad.ops[i].version += 1; }
        else if field == 4 { bad.ops[i].output += 1; }
        else if field == 5 { bad.ops[i].output_version += 1; }
        else if field == 6 { bad.ops[i].index += 1; }
        else if field == 7 { bad.ops[i].domain += 1; }
        else if field == 8 { bad.ops[i].proof1 += 1; }
        else if field == 9 { bad.ops[i].proof2 += 1; }
        else { bad.ops[i].site += 1; }
        assert(!loop_validate::verify(bad,text,ctx) && loop_wasm::emit(bad,text,ctx,data).len == 0);
    } }
    var alternate = ctx; alternate.input_version += 1; assert(!loop_validate::verify(core,text,alternate));
    alternate = ctx; alternate.builder_version += 1; assert(!loop_validate::verify(core,text,alternate));
    alternate = ctx; alternate.next_version += 1; assert(!loop_validate::verify(core,text,alternate));
    alternate = ctx; alternate.result_version += 1; assert(!loop_validate::verify(core,text,alternate));
    alternate = ctx; alternate.input_domain += 1; assert(!loop_validate::verify(core,text,alternate));
    alternate = ctx; alternate.output_region = ctx.input_region; let _, wrong_regions = loop_parse::parse(text,alternate); assert(wrong_regions != 0);
    var mutable: u8[>..] = []; mutable.append(text); var own, own_status = loop_parse::parse(mutable,ctx); assert(own_status == 0);
    mutable[0] = '?'; assert(loop_validate::verify(own,text,ctx));
    for i in text.len { var bad = copy_core(core); bad.source[i] = '?'; assert(!loop_validate::verify(bad,text,ctx)); }
    var large: u32[129] = [0;129]; assert(loop_wasm::emit(core,text,ctx,large).len == 0);
    assert(loop_wasm::emit_test(core,text,ctx,data,257).len == 0);
    print("private source-bound U32 carry loop Core passed");
}
