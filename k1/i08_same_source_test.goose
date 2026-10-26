import os;
import particle_source_core;
import i08_same_golden;
import particle_lower_core;
import particle_lower_parse;
import particle_lower_verify;
import i08_same_target;
import i08_same_wasm;
fn source(x:u8[:],y:u8[:])->u8[] {
    var out:u8[>..]=[];
    out.append("pub let project: forall [r: Region, s: Region, n: Nat, c: Nat, d: Domain] => Fn[static, Many, (View[r,{x:F32,y:F32,vx:F32,vy:F32},n,d], F32, Builder[s,{x:F32,y:F32},0,c,Append]), exists [e: Domain] => View[s,{x:F32,y:F32},n,e]] ! {read r, write s} requires [Le(n,c)] resources {depth: 2, frame: 256} = fn (source,dt,initial) => do:\n  let built = for i in 0..n carry (b = initial)\n    invariant [Eq(Init(b),i)] do:\n      next (builder.append(b, {x: ");
    out.append(x);out.append(", y: ");out.append(y);out.append("}))\n  return builder.freeze(built)\n");return out;
}
fn cloned(p:particle_lower_core::Core&)->particle_lower_core::Core {
    return particle_lower_core::Core {source:copy(p.source),context:p.context,sites:p.sites,proofs:p.proofs,nodes:copy(p.nodes),x_root:p.x_root,y_root:p.y_root};
}
fn compile(x:u8[:],y:u8[:],path:u8[:],ctx:particle_source_core::Context)->u8[] {
    let text=source(x,y);var core,status=particle_lower_parse::parse(text,ctx);
    assert(status==0 && particle_lower_verify::verify(core,text,ctx));
    let bytes=i08_same_wasm::emit(core,text,ctx);assert(bytes.len>0 && i08_same_target::verify(core,text,ctx,bytes));
    assert(write_file(path,bytes));return bytes;
}
fn main() {
    let ctx=particle_source_core::Context {owner:1,input:2,input_version:3,input_region:4,input_domain:5,length:6,dt:7,dt_version:8,
        builder:9,builder_version:10,output_region:11,capacity:12,index:13,next_builder:14,next_version:15,result:16,result_version:17,result_domain:18};
    let ax="source[i].x + source[i].vx * dt";let ay="source[i].y + source[i].vy * dt";
    let text=source(ax,ay);var p,status=particle_lower_parse::parse(text,ctx);assert(status==0 && particle_lower_verify::verify(p,text,ctx));
    let a=compile(ax,ay,"particle-lower-a.wasm",ctx);let pinned=i08_same_golden::bytes();assert(a[..]==pinned[..]);
    let b=compile("(source[i].vx + source[i].x) * dt","source[i].y * dt + source[i].vy","particle-lower-b.wasm",ctx);
    let c=compile("source[i].vx","source[i].x","particle-lower-c.wasm",ctx);
    let d=compile("dt + source[i].x * source[i].vy","(source[i].vx + source[i].y) * (source[i].vy + dt)","particle-lower-d.wasm",ctx);
    assert(b[..]!=a[..] && c[..]!=a[..] && d[..]!=a[..]);
    assert(!i08_same_target::verify(p,text,ctx,b) && !i08_same_target::verify(p,text,ctx,c) && !i08_same_target::verify(p,text,ctx,d));
    // Preserve lexical order, index identity and supported F32 operators.
    for bad in ["source[j].x","source[i+1].x","source[i].z","source[i].x / dt","source[i].x - dt","-dt","unknown","source[i]","(dt + )"] {
        let altered=source(bad,ay);var invalid,error=particle_lower_parse::parse(altered,ctx);assert(error!=0);
        assert(!particle_lower_verify::verify(invalid,altered,ctx));
    }
    for i in p.nodes.len {for field in 13 {
        var bad=cloned(p);
        if field==0 {bad.nodes[i].kind+=1;} else if field==1 {bad.nodes[i].start+=1;} else if field==2 {bad.nodes[i].end+=1;}
        else if field==3 {bad.nodes[i].field_start+=1;} else if field==4 {bad.nodes[i].field_end+=1;} else if field==5 {bad.nodes[i].field+=1;}
        else if field==6 {bad.nodes[i].left+=1;} else if field==7 {bad.nodes[i].right+=1;} else if field==8 {bad.nodes[i].symbol+=1;}
        else if field==9 {bad.nodes[i].version+=1;} else if field==10 {bad.nodes[i].index+=1;} else if field==11 {bad.nodes[i].domain+=1;}
        else {bad.nodes[i].proof+=1;}
        assert(!particle_lower_verify::verify(bad,text,ctx) && i08_same_wasm::emit(bad,text,ctx).len==0);
    }}
    for i in 6 {for f in 9 {
        var bad=cloned(p);
        if f==0 {bad.proofs[i].rule+=1;} else if f==1 {bad.proofs[i].owner+=1;} else if f==2 {bad.proofs[i].left+=1;}
        else if f==3 {bad.proofs[i].right+=1;} else if f==4 {bad.proofs[i].version+=1;} else if f==5 {bad.proofs[i].dep1+=1;}
        else if f==6 {bad.proofs[i].dep2+=1;} else if f==7 {bad.proofs[i].dep3+=1;} else {bad.proofs[i].site+=1;}
        assert(!particle_lower_verify::verify(bad,text,ctx) && i08_same_wasm::emit(bad,text,ctx).len==0);
    }}
    var wrong=cloned(p);wrong.x_root+=1;assert(!particle_lower_verify::verify(wrong,text,ctx));
    var wrong2=cloned(p);wrong2.y_root-=1;assert(!particle_lower_verify::verify(wrong2,text,ctx));
    var other=ctx;other.dt_version+=1;assert(!particle_lower_verify::verify(p,text,other));
    other=ctx;other.input_version+=1;assert(!particle_lower_verify::verify(p,text,other));
    other=ctx;other.input_domain+=1;assert(!particle_lower_verify::verify(p,text,other));
    other=ctx;other.output_region=ctx.input_region;let _,badctx=particle_lower_parse::parse(text,other);assert(badctx==1);
    for i in text.len {var bad=cloned(p);bad.source[i]='?';assert(!particle_lower_verify::verify(bad,text,ctx));}
    // Every single byte in a final module, including helper code and dynamic
    // worker operands, is bound by the independent final-byte checker.
    for i in a.len {var changed=copy(a);changed[i]^=1;assert(!i08_same_target::verify(p,text,ctx,changed));}
    var owned:u8[>..]=[];owned.append(text);var copy,copy_status=particle_lower_parse::parse(owned,ctx);
    assert(copy_status==0);owned[0]='?';assert(particle_lower_verify::verify(copy,text,ctx));
    var too_long:u8[>..]=[32;65537];let _,limit=particle_lower_parse::parse(too_long,ctx);assert(limit==2);
    print("private generalized particle expression/Core/target passed");
}
