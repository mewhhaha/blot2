import os;
import particle_source_backend;
import particle_source_core;
import particle_source_parse;
import particle_source_validate;
import particle_source_target;
import particle_source_wasm;
fn source()->u8[] {
    return "pub let project: forall [r: Region, s: Region, n: Nat, c: Nat, d: Domain] => Fn[static, Many, (View[r,{x:F32,y:F32,vx:F32,vy:F32},n,d], F32, Builder[s,{x:F32,y:F32},0,c,Append]), exists [e: Domain] => View[s,{x:F32,y:F32},n,e]] ! {read r, write s} requires [Le(n,c)] resources {depth: 2, frame: 256} = fn (source,dt,initial) => do:\n  let built = for i in 0..n carry (b = initial)\n    invariant [Eq(Init(b),i)] do:\n      next (builder.append(b, {x: source[i].x + source[i].vx * dt, y: source[i].y + source[i].vy * dt}))\n  return builder.freeze(built)\n";
}
fn cloned(p:particle_source_core::Core&)->particle_source_core::Core {
    return particle_source_core::Core {source:copy(p.source),context:p.context,sites:p.sites,evidence:p.evidence,ops:p.ops};
}
fn replace(original:u8[:], before:u8[:], after:u8[:])->u8[] {
    var out:u8[>..]=[]; var i:i64=0; var found=false;
    while i<original.len {
        if !found && before.len<=original.len-i && original[i..i+before.len]==before {out.append(after); i+=before.len; found=true;}
        else {out.push(original[i]); i+=1;}
    }
    assert(found); return out;
}
fn reject(core:particle_source_core::Core&, text:u8[:], ctx:particle_source_core::Context, before:u8[:], after:u8[:]) {
    let altered=replace(text,before,after); var candidate,status=particle_source_parse::parse(altered,ctx);
    assert(status!=0 && !particle_source_validate::verify(candidate,altered,ctx));
    assert(!particle_source_validate::verify(core,altered,ctx) && particle_source_wasm::emit(core,altered,ctx).len==0);
}
fn main() {
    let ctx=particle_source_core::Context {owner:1,input:2,input_version:3,input_region:4,input_domain:5,length:6,
        dt:7,dt_version:8,builder:9,builder_version:10,output_region:11,capacity:12,index:13,next_builder:14,next_version:15,
        result:16,result_version:17,result_domain:18};
    let text=source(); var core,status=particle_source_parse::parse(text,ctx);
    assert(status==0 && particle_source_validate::verify(core,text,ctx));
    assert(core.ops[0].field==0 && core.ops[1].field==2 && core.ops[4].field==1 && core.ops[5].field==3);
    assert(core.ops[2].kind==2 && core.ops[3].kind==3 && core.ops[9].proof==4 && core.ops[10].proof==5 && core.ops[11].proof==6);
    let module=particle_source_wasm::emit(core,text,ctx);
    assert(module.len>0 && particle_source_target::verify(core,text,ctx,module));
    assert(write_file("particle-source.wasm",module));
    // Existing independently executed fixture checks these separately emitted
    // trap controls. They are test-only engine traps, not source error paths.
    assert(write_file("particle-source-fault-0.wasm",particle_source_backend::emit_test(0)));
    assert(write_file("particle-source-fault-1.wasm",particle_source_backend::emit_test(1)));
    assert(write_file("particle-source-fault-2.wasm",particle_source_backend::emit_test(2)));
    assert(write_file("particle-source-fault-3.wasm",particle_source_backend::emit_test(3)));
    assert(write_file("particle-source-fault-4.wasm",particle_source_backend::emit_test(4)));
    let no_final_newline=text[0..text.len-1]; var exact,complete=particle_source_parse::parse(no_final_newline,ctx);
    assert(complete==0 && particle_source_validate::verify(exact,no_final_newline,ctx));
    reject(core,text,ctx,"Le(n,c)","Lt(n,c)"); reject(core,text,ctx,"Le(n,c)","Le(c,n)");
    reject(core,text,ctx,"Init(b),i","Init(b),n"); reject(core,text,ctx,"source[i].x","source[i].y");
    reject(core,text,ctx,"source[i].vx","source[i].vy"); reject(core,text,ctx,"source[i].vy","source[i+1].vy");
    reject(core,text,ctx,".vx * dt",".vx + dt"); reject(core,text,ctx,".x + source",".x * source");
    reject(core,text,ctx,"for i in 0..n","for i in 0..c"); reject(core,text,ctx,"next (","stop (");
    reject(core,text,ctx,"builder.freeze(built)","builder.freeze(initial)");
    reject(core,text,ctx,"read r, write s","write r, write s"); reject(core,text,ctx,"depth: 2","depth: 1");
    reject(core,text,ctx,"frame: 256","frame: 1"); reject(core,text,ctx,"0,c,Append","1,c,Append");
    // Every proof field and operation field must agree with independently
    // reconstructed source, operand/version IDs and dependency records.
    for i in 6 {for f in 9 {
        var forged=cloned(core);
        if f==0 {forged.evidence[i].rule+=1;} else if f==1 {forged.evidence[i].owner+=1;}
        else if f==2 {forged.evidence[i].left+=1;} else if f==3 {forged.evidence[i].right+=1;}
        else if f==4 {forged.evidence[i].version+=1;} else if f==5 {forged.evidence[i].dep1+=1;}
        else if f==6 {forged.evidence[i].dep2+=1;} else if f==7 {forged.evidence[i].dep3+=1;} else {forged.evidence[i].site+=1;}
        assert(!particle_source_validate::verify(forged,text,ctx) && particle_source_wasm::emit(forged,text,ctx).len==0);
    }}
    for i in 13 {for f in 14 {
        var forged=cloned(core);
        if f==0 {forged.ops[i].kind+=1;} else if f==1 {forged.ops[i].owner+=1;}
        else if f==2 {forged.ops[i].a+=1;} else if f==3 {forged.ops[i].b+=1;}
        else if f==4 {forged.ops[i].symbol+=1;} else if f==5 {forged.ops[i].version+=1;}
        else if f==6 {forged.ops[i].output+=1;} else if f==7 {forged.ops[i].output_version+=1;}
        else if f==8 {forged.ops[i].index+=1;} else if f==9 {forged.ops[i].domain+=1;}
        else if f==10 {forged.ops[i].field+=1;} else if f==11 {forged.ops[i].proof+=1;}
        else if f==12 {forged.ops[i].site+=1;} else {forged.ops[i].field_site+=1;}
        assert(!particle_source_validate::verify(forged,text,ctx) && particle_source_wasm::emit(forged,text,ctx).len==0);
    }}
    for i in 4 {
        var a=cloned(core); a.sites.read[i].start+=1; assert(!particle_source_validate::verify(a,text,ctx));
        var b=cloned(core); b.sites.field[i].end+=1; assert(!particle_source_validate::verify(b,text,ctx));
    }
    for i in 2 {
        var a=cloned(core); a.sites.add[i].start+=1; assert(!particle_source_validate::verify(a,text,ctx));
        var b=cloned(core); b.sites.mul[i].end+=1; assert(!particle_source_validate::verify(b,text,ctx));
    }
    var wrong=ctx; wrong.input_version+=1; assert(!particle_source_validate::verify(core,text,wrong));
    wrong=ctx; wrong.builder_version+=1; assert(!particle_source_validate::verify(core,text,wrong));
    wrong=ctx; wrong.next_version+=1; assert(!particle_source_validate::verify(core,text,wrong));
    wrong=ctx; wrong.input_domain+=1; assert(!particle_source_validate::verify(core,text,wrong));
    wrong=ctx; wrong.result_domain+=1; assert(!particle_source_validate::verify(core,text,wrong));
    wrong=ctx; wrong.output_region=ctx.input_region; let _,bad_context=particle_source_parse::parse(text,wrong); assert(bad_context==1);
    for i in text.len {var forged=cloned(core); forged.source[i]='?'; assert(!particle_source_validate::verify(forged,text,ctx));}
    // Exact byte identity rejects mutation of any target byte, including
    // preflight helper and export sections, even if it remains valid Wasm.
    for i in module.len {var changed=copy(module); changed[i]^=1; assert(!particle_source_target::verify(core,text,ctx,changed));}
    var caller:u8[>..]=[]; caller.append(text); var owned,owned_status=particle_source_parse::parse(caller,ctx);
    assert(owned_status==0); caller[0]='?'; assert(particle_source_validate::verify(owned,text,ctx));
    var oversized:u8[>..]=[32;65537]; let _,limit=particle_source_parse::parse(oversized,ctx); assert(limit==2);
    print("private source-linked particle Core and target passed");
}
