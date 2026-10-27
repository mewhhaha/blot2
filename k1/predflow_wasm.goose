// Private whole-source U32/Bool lowering; the caller retains immutable source
// and an independent recognizer rechecks it before any bytes are returned.
namespace predflow_wasm;
import unified_core;
import predflow_check;
import predflow_target;
import wasm;
struct Action { kind:i64=0, value:i64=0 }
fn visit(a:Action[>..]&,x:i64) {a.push(Action {kind:1,value:x});}
fn byte(a:Action[>..]&,x:i64) {a.push(Action {kind:2,value:x});}
fn local(a:Action[>..]&,x:i64) {a.push(Action {kind:3,value:x});}
fn lower(expected:u8[:],p:unified_core::Program&,probe_node:i64) -> u8[] {
    if !predflow_check::verify(expected,p) {return [];}
    if probe_node!=0 {var found=false;for n in p.nodes {if (n.tag==12 || n.tag==13) && n.b==probe_node {found=true;}}if !found {return [];}}
    var out:u8[>..]=[];
    if p.bindings.len==0 {out.push(0);}else {out.push(1);wasm::unsigned_leb(out,p.bindings.len);out.push(0x7f);}
    var actions:Action[>..]=[];visit(actions,p.root);var steps:i64=0;
    while actions.len>0 {
        steps+=1;if steps>32768 || out.len>65536 {return [];}
        let a=actions[actions.len-1];actions.pop();
        if a.kind==2 {out.push(a.value as u8);continue;}
        if a.kind==3 {wasm::unsigned_leb(out,a.value);continue;}
        if a.kind!=1 || a.value<1 || a.value>p.nodes.len {return [];}
        if a.value==probe_node {out.push(0x00);continue;}
        let n=p.nodes[a.value-1];
        if n.tag==1 {out.push(0x20);wasm::unsigned_leb(out,n.a+1);}
        else if n.tag==2 {out.push(0x41);wasm::signed_i32_leb(out,n.literal);}
        else if n.tag==3 || n.tag==4 || n.tag==5 || n.tag==6 || n.tag==7 || n.tag==9 || n.tag==18 {
            let op=if n.tag==3 || n.tag==4 {0x6a} else if n.tag==5 {0x6b} else if n.tag==6 {0x6c} else if n.tag==7 {0x71} else if n.tag==9 {0x49} else {0x4d};
            byte(actions,op);visit(actions,n.b);visit(actions,n.a);
        } else if n.tag==8 {visit(actions,n.a);}
        else if n.tag==10 || n.tag==11 {out.push(0x41);out.push(if n.tag==10 {1} else {0});}
        else if n.tag==12 || n.tag==13 {
            byte(actions,0x0b);
            if n.tag==12 {byte(actions,0);byte(actions,0x41);} else {visit(actions,n.b);}
            byte(actions,0x05);
            if n.tag==12 {visit(actions,n.b);} else {byte(actions,1);byte(actions,0x41);}
            byte(actions,0x7f);byte(actions,0x04);visit(actions,n.a);
        } else if n.tag==14 {local(actions,n.b+1);byte(actions,0x21);visit(actions,n.a);}
        else if n.tag==15 {byte(actions,0x0f);visit(actions,n.a);}
        else if n.tag==16 {
            byte(actions,0x0b);if n.c!=0 {visit(actions,n.c);byte(actions,0x05);}
            visit(actions,n.b);byte(actions,0x40);byte(actions,0x04);visit(actions,n.a);
        } else if n.tag==17 {visit(actions,n.b);visit(actions,n.a);}
        else {return [];}
    }
    // A separately established explicit return, not this unreachable opcode,
    // establishes source completion. The opcode provides Wasm polymorphism.
    out.push(0x00);out.push(0x0b);
    return wasm::emit_body(expected[p.name_start..p.name_end],out);
}
fn emit(expected:u8[:],p:unified_core::Program&) -> u8[] {let bytes=lower(expected,p,0);if bytes.len==0 || !predflow_target::verify(expected,p,bytes) {return [];}return bytes;}
fn probe(expected:u8[:],p:unified_core::Program&,node:i64) -> u8[] {if node<=0 {return [];}return lower(expected,p,node);}
