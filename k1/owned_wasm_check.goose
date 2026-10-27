// Independent structured decoder for one closed private Wasm state machine.
// Source extraction is independently replayed by owned_chain and source-owned
// checkers; this is not a portable certificate or general K1 target validator.
namespace owned_wasm_check;
import owned_wasm_plan;
import owned_chain;
import ownership_syntax;
import owned_scalar_source;
import wasm_scalar_validation;
import i08_same_target;
fn byte(b:u8[:],r:wasm_scalar_validation::Reader&,x:i64)->bool {return wasm_scalar_validation::byte(b,r)==x;}
fn imm(b:u8[:],r:wasm_scalar_validation::Reader&,op:i64,x:i64)->bool {return byte(b,r,op) && wasm_scalar_validation::u32_leb(b,r)==x;}
fn constant(b:u8[:],r:wasm_scalar_validation::Reader&,x:u32)->bool {return byte(b,r,0x41) && wasm_scalar_validation::i32_leb_bits(b,r)==(x as i64);}
fn load(b:u8[:],r:wasm_scalar_validation::Reader&,at:u32)->bool {return constant(b,r,at) && byte(b,r,0x28) && byte(b,r,2) && byte(b,r,0);}
fn store(b:u8[:],r:wasm_scalar_validation::Reader&,at:u32,value:u32)->bool {return constant(b,r,at) && constant(b,r,value) && byte(b,r,0x36) && byte(b,r,2) && byte(b,r,0);}
fn check(b:u8[:],r:wasm_scalar_validation::Reader&,at:u32,want:u32)->bool {return load(b,r,at) && constant(b,r,want) && byte(b,r,0x47) && byte(b,r,4) && byte(b,r,0x40) && byte(b,r,0) && byte(b,r,11);}
fn bump(b:u8[:],r:wasm_scalar_validation::Reader&,at:u32,op:i64)->bool {return constant(b,r,at) && load(b,r,at) && constant(b,r,1) && byte(b,r,op) && byte(b,r,0x36) && byte(b,r,2) && byte(b,r,0);}
recursive fn node(b:u8[:],r:wasm_scalar_validation::Reader&,t:ownership_syntax::Tree&,id:i64,depth:i64,branch:i64)->bool {
 if depth>256 || id<1 || id>t.nodes.len || branch>64{return false;}let n=t.nodes[id-1];
 if n.tag==8 {return node(b,r,t,n.a,depth+1,branch) && node(b,r,t,n.b,depth+1,branch);}
 if n.tag==1 {return check(b,r,0,1) && check(b,r,4,0) && bump(b,r,8,0x6a);}
 if n.tag==2 {return check(b,r,0,1) && check(b,r,4,0) && store(b,r,0,0);}
 if n.tag==3 {return check(b,r,0,1) && bump(b,r,4,0x6a) && load(b,r,256) && imm(b,r,0x21,1) && byte(b,r,2) && byte(b,r,0x40) && node(b,r,t,n.a,depth+1,0) && byte(b,r,11) && bump(b,r,4,0x6b);}
 if n.tag==4 {if !imm(b,r,0x20,0) || !byte(b,r,4) || !byte(b,r,0x40) || !node(b,r,t,n.a,depth+1,branch+1) {return false;}if n.b!=0 && (!byte(b,r,5) || !node(b,r,t,n.b,depth+1,branch+1)) {return false;}return byte(b,r,11);}
 if n.tag==6 {return imm(b,r,0x20,1) && byte(b,r,0x0f);}
 if n.tag==7 {return imm(b,r,0x0c,branch);}
 return false;
}
fn raw(b:u8[:],r:wasm_scalar_validation::Reader&,items:const u8[:])->bool {for x in items {if !byte(b,r,x) {return false;}}return true;}
fn entry(b:u8[:],r:wasm_scalar_validation::Reader&,core:owned_scalar_source::Core,flag:bool)->bool {
 if !raw(b,r,[1,1,0x7f]) || !check(b,r,0,0) || !check(b,r,4,0) {return false;}
 if core.work_bytes>3840 {return raw(b,r,[0x42,0x80,0x80,0x80,0x80,0x30,0x42]) && byte(b,r,if core.work_bytes>4294962944 {1} else {3}) && raw(b,r,[0x84,0x0f,0x0b]);}
 if !store(b,r,0,4) || !store(b,r,8,1) {return false;}
 if core.terminal==2 {return store(b,r,0,0) && raw(b,r,[0x42,0x80,0x80,0x80,0x80,0x20,0x0f,0x0b]);}
 return store(b,r,256,core.value) && store(b,r,0,1) && constant(b,r,if flag {1} else {0}) && imm(b,r,0x10,0) && imm(b,r,0x21,0) && check(b,r,0,0) && check(b,r,4,0) && imm(b,r,0x20,0) && raw(b,r,[0xad,0x0b]);
}
fn verify(s:u8[:],b:u8[:])->bool {
 var p=owned_wasm_plan::plan(s);let native=owned_chain::run(s);if p.status!=0 || native.status==1 || b.len<8 || b.len>65536 || b[..8]!=[0 as u8,97,115,109,1,0,0,0] {return false;}
 let expected_status=if p.core.work_bytes>3840 {3} else if p.core.terminal==2 {2} else {0};if native.status!=expected_status || (native.status==0 && native.value!=p.core.value) || (native.status==3 && native.reserve_error!=(if p.core.work_bytes>4294962944 {1} else {3})) {return false;}
 var pos:i64=8;let types=i08_same_target::section(b,pos,1);if !types.ok || b[types.payload..types.end]!=[2 as u8,0x60,1,0x7f,1,0x7f,0x60,0,1,0x7e] {return false;}pos=types.end;
 let fun=i08_same_target::section(b,pos,3);if !fun.ok || b[fun.payload..fun.end]!=[2 as u8,0,1] {return false;}pos=fun.end;
 let mem=i08_same_target::section(b,pos,5);if !mem.ok || b[mem.payload..mem.end]!=[1 as u8,1,1,1] {return false;}pos=mem.end;
 let exp=i08_same_target::section(b,pos,7);if !exp.ok || b[exp.payload..exp.end]!=[1 as u8,6,'i','n','v','o','k','e',0,1] {return false;}pos=exp.end;
 let code=i08_same_target::section(b,pos,10);if !code.ok || code.end!=b.len {return false;}var outer=wasm_scalar_validation::Reader {at:code.payload,end:code.end};
 if wasm_scalar_validation::u32_leb(b,outer)!=2{return false;}let size=wasm_scalar_validation::u32_leb(b,outer);if size<0 || size>outer.end-outer.at{return false;}
 var worker=wasm_scalar_validation::Reader {at:outer.at,end:outer.at+size};outer.at+=size;
 if !raw(b,worker,[1,1,0x7f]) || !node(b,worker,p.consumer.tree,p.consumer.tree.root,0,0) || !raw(b,worker,[0,0x0b]) || !wasm_scalar_validation::done(worker) {return false;}
 let size2=wasm_scalar_validation::u32_leb(b,outer);if size2<0 || size2>outer.end-outer.at {return false;}var main=wasm_scalar_validation::Reader {at:outer.at,end:outer.at+size2};outer.at+=size2;
 return entry(b,main,p.core,p.flag) && wasm_scalar_validation::done(main) && wasm_scalar_validation::done(outer);
}
