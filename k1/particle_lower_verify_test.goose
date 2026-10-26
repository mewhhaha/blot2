import particle_source_core;
import particle_lower_core;
import particle_lower_parse;
import particle_lower_verify;
fn source()->u8[] {return "pub let project: forall [r: Region, s: Region, n: Nat, c: Nat, d: Domain] => Fn[static, Many, (View[r,{x:F32,y:F32,vx:F32,vy:F32},n,d], F32, Builder[s,{x:F32,y:F32},0,c,Append]), exists [e: Domain] => View[s,{x:F32,y:F32},n,e]] ! {read r, write s} requires [Le(n,c)] resources {depth: 2, frame: 256} = fn (source,dt,initial) => do:\n  let built = for i in 0..n carry (b = initial)\n    invariant [Eq(Init(b),i)] do:\n      next (builder.append(b, {x: source[i].x + source[i].vx * dt, y: source[i].y + source[i].vy * dt}))\n  return builder.freeze(built)\n";}
fn clone(c:particle_lower_core::Core&)->particle_lower_core::Core {return particle_lower_core::Core {source:copy(c.source),context:c.context,sites:c.sites,proofs:c.proofs,nodes:copy(c.nodes),x_root:c.x_root,y_root:c.y_root};}
fn replace(s:u8[:],a:u8[:],b:u8[:])->u8[] {var out:u8[>..]=[];var i:i64=0;var found=false;while i<s.len {if !found && a.len<=s.len-i && s[i..i+a.len]==a {out.append(b);i+=a.len;found=true;}else {out.push(s[i]);i+=1;}}assert(found);return out;}
fn main() {
    let ctx=particle_source_core::Context {owner:1,input:2,input_version:3,input_region:4,input_domain:5,length:6,dt:7,dt_version:8,builder:9,builder_version:10,output_region:11,capacity:12,index:13,next_builder:14,next_version:15,result:16,result_version:17,result_domain:18};
    let text=source();var core,status=particle_lower_parse::parse(text,ctx);assert(status==0 && particle_lower_verify::verify(core,text,ctx));
    let original="source[i].x + source[i].vx * dt";
    for expr in ["source[i].x", "dt", "(source[i].x + source[i].vx) * dt", "source[i].x * source[i].vx + dt * source[i].y", "source[i].x + (source[i].vx + dt) * source[i].vy", "source[i].x * dt * dt + source[i].vx"] {
        let changed=replace(text,original,expr);var p,e=particle_lower_parse::parse(changed,ctx);assert(e==0 && particle_lower_verify::verify(p,changed,ctx));
    }
    for i in core.nodes.len {for field in 12 {
        var p=clone(core);
        if field==0 {p.nodes[i].kind+=1;}else if field==1 {p.nodes[i].start+=1;}else if field==2 {p.nodes[i].end+=1;}
        else if field==3 {p.nodes[i].field_start+=1;}else if field==4 {p.nodes[i].field_end+=1;}else if field==5 {p.nodes[i].field+=1;}
        else if field==6 {p.nodes[i].left+=1;}else if field==7 {p.nodes[i].right+=1;}else if field==8 {p.nodes[i].symbol+=1;}
        else if field==9 {p.nodes[i].version+=1;}else if field==10 {p.nodes[i].index+=1;}else {p.nodes[i].proof+=1;}
        assert(!particle_lower_verify::verify(p,text,ctx));
    }}
    for i in core.nodes.len {var p=clone(core);p.nodes[i].domain+=1;assert(!particle_lower_verify::verify(p,text,ctx));}
    for i in 6 {for field in 9 {var p=clone(core);
        if field==0 {p.proofs[i].rule+=1;}else if field==1 {p.proofs[i].owner+=1;}else if field==2 {p.proofs[i].left+=1;}
        else if field==3 {p.proofs[i].right+=1;}else if field==4 {p.proofs[i].version+=1;}else if field==5 {p.proofs[i].dep1+=1;}
        else if field==6 {p.proofs[i].dep2+=1;}else if field==7 {p.proofs[i].dep3+=1;}else {p.proofs[i].site+=1;}
        assert(!particle_lower_verify::verify(p,text,ctx));
    }}
    var bad_x=clone(core);bad_x.x_root=bad_x.y_root;assert(!particle_lower_verify::verify(bad_x,text,ctx));
    var bad_y=clone(core);bad_y.y_root-=1;assert(!particle_lower_verify::verify(bad_y,text,ctx));
    var bad_site=clone(core);bad_site.sites.append_site.start+=1;assert(!particle_lower_verify::verify(bad_site,text,ctx));
    var other=ctx;other.dt_version+=1;assert(!particle_lower_verify::verify(core,text,other));
    let forged=replace(text,"source[i].vx","source[i].vy");assert(!particle_lower_verify::verify(core,forged,ctx));
    for invalid in ["source[j].x", "source[i].q", "dt + 1", "source[i].x +", "(source[i].x", "source[i].x * * dt"] {
        let changed=replace(text,original,invalid);let p,e=particle_lower_parse::parse(changed,ctx);assert(e!=0 && !particle_lower_verify::verify(p,changed,ctx));
    }
    print("independent particle source, precedence, node and evidence checks passed");
}
