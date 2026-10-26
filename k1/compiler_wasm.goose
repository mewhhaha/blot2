// Scratch tagged compiler: delegates unified scalar lowering, and lowers a
// source-verified finite U32 loop subset. Not a public ABI or K1 certificate.
namespace compiler_wasm;
import compiler_core;
import compiler_validate;
import unified_wasm;
import mixed_wasm;
import iteration_core;
import wasm;
struct Action {kind:i64=0,node:i64=0}
struct Loop {target:i64=0,index:i64=0,carry:i64=0,loop_depth:i64=0,exit_depth:i64=0}
fn node(stack:Action[>..]&,id:i64) {stack.push(Action {kind:1,node:id});}
fn value(p:compiler_core::Program&,id:i64,out:u8[>..]&) -> bool {
    if id<1 || id>p.body.nodes.len {return false;}let n=p.body.nodes[id-1];
    if n.tag==1 {if n.a<1 || n.a>p.body.bindings.len {return false;}out.push(0x20);wasm::unsigned_leb(out,n.a);return true;}
    if n.tag==2 {
        if n.start<0 || n.end<=n.start || n.end>p.body.source.len {return false;}
        var v:u64=0;for c in p.body.source[n.start..n.end] {if c<'0' || c>'9' {return false;}let d=(c-'0') as u64;if v>(4294967295-d)/10 {return false;}v=v*10+d;}
        out.push(0x41);wasm::signed_i32_leb(out,v as u32);return true;
    }
    if n.tag==3 || n.tag==4 {out.push(0x41);out.push(if n.tag==3 {1} else {0});return true;}
    return false;
}
fn set(out:u8[>..]&,slot:i64) {out.push(0x21);wasm::unsigned_leb(out,slot);}
fn get(out:u8[>..]&,slot:i64) {out.push(0x20);wasm::unsigned_leb(out,slot);}
fn inc(out:u8[>..]&,slot:i64) {get(out,slot);out.push(0x41);out.push(1);out.push(0x6a);set(out,slot);}
fn emit(expected:u8[:],p:compiler_core::Program&) -> u8[] {
    if !compiler_validate::verify(expected,p) {return [];}
    if p.variant==1 {return unified_wasm::emit(expected,p.scalar);}
    if p.variant==3 {return mixed_wasm::emit(expected,p.mixed);}
    var limit:i64[2048]=[0;2048];var count:i64=0;
    for n,i in p.body.nodes {if n.tag==15 {count+=1;if count>128 {return [];}limit[i]=p.body.bindings.len+count;}}
    let locals=p.body.bindings.len-1+count;if locals<0 || locals>255 {return [];}
    var out:u8[>..]=[];if locals==0 {out.push(0);}else {out.push(1);wasm::unsigned_leb(out,locals);out.push(0x7f);}
    var actions:Action[>..]=[];var loops:Loop[>..]=[];var depth:i64=0;var steps:i64=0;node(actions,p.body.nodes[p.body.root-1].a);
    while actions.len>0 {
        steps+=1;if steps>32768 || out.len>65536 {return [];}
        let a=actions[actions.len-1];actions.pop();
        if a.kind==2 {out.push(0x05);continue;} // else
        if a.kind==3 {out.push(0x0b);depth-=1;continue;} // end if
        if a.kind==4 {out.push(0x00);out.push(0x0b);out.push(0x0b);depth-=2;loops.pop();continue;} // finish loop
        if a.kind==5 {
            let let_node=p.body.nodes[a.node-1];let loop_node=p.body.nodes[let_node.a-1];let carry=p.body.nodes[loop_node.c-1];
            get(out,carry.b);set(out,let_node.b);continue;
        }
        if a.kind!=1 || a.node<1 || a.node>p.body.nodes.len {return [];}
        let n=p.body.nodes[a.node-1];
        if n.tag==17 {node(actions,n.b);node(actions,n.a);}
        else if n.tag==16 {actions.push(Action {kind:5,node:a.node});node(actions,n.a);}
        else if n.tag==15 {
            if !value(p,n.a,out) {return [];}set(out,n.f);
            if !value(p,n.b,out) {return [];}set(out,limit[a.node-1]);
            var carry:i64=0;
            if n.g==1 {let c=p.body.nodes[n.c-1];carry=c.b;if !value(p,c.a,out) {return [];}set(out,carry);}
            out.push(0x02);out.push(0x40);out.push(0x03);out.push(0x40);depth+=2;
            loops.push(Loop {target:n.target,index:n.f,carry:carry,loop_depth:depth,exit_depth:depth-1});
            get(out,n.f);get(out,limit[a.node-1]);out.push(0x4f);out.push(0x0d);wasm::unsigned_leb(out,1);
            actions.push(Action {kind:4});node(actions,n.e);
        } else if n.tag==14 {
            if !value(p,n.a,out) {return [];}out.push(0x04);out.push(0x40);depth+=1;
            actions.push(Action {kind:3});if n.c!=0 {node(actions,n.c);actions.push(Action {kind:2});}node(actions,n.b);
        } else if n.tag==13 {if !value(p,n.a,out) {return [];}out.push(0x0f);}
        else if n.tag>=9 && n.tag<=12 {
            if loops.len==0 {return [];}let l=loops[loops.len-1];if n.target!=l.target {return [];}
            if n.tag==9 || n.tag==10 {if l.carry==0 || n.b!=1 || !value(p,n.a,out) {return [];}set(out,l.carry);}
            if n.tag==9 || n.tag==11 {inc(out,l.index);out.push(0x0c);wasm::unsigned_leb(out,depth-l.loop_depth);}
            else {out.push(0x0c);wasm::unsigned_leb(out,depth-l.exit_depth);}
        } else {return [];}
    }
    if loops.len!=0 || depth!=0 {return [];}
    out.push(0x00);out.push(0x0b);
    return wasm::emit_body(expected[p.name_start..p.name_end],out);
}
