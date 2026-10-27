// Private closed single-capsule Wasm state machine, no general K1 ABI.
namespace owned_wasm_emit;
import pool_guest;
import owned_wasm_plan;
import ownership_syntax;
fn const32(o:u8[>..]&,v:u32) {pool_guest::constant(o,v);}
fn ld(o:u8[>..]&,at:u32) {const32(o,at);pool_guest::load(o,0);}
fn st(o:u8[>..]&,at:u32,v:u32) {const32(o,at);const32(o,v);pool_guest::store(o,0);}
fn check_one(o:u8[>..]&,at:u32,want:u32) {ld(o,at);const32(o,want);o.push(0x47);o.append([0x04,0x40,0,0x0b]);}
fn bump(o:u8[>..]&,at:u32,op:u8) {const32(o,at);ld(o,at);const32(o,1);o.push(op);pool_guest::store(o,0);}
recursive fn node(o:u8[>..]&,t:ownership_syntax::Tree&,id:i64,depth:i64,branch:i64)->bool {
 if depth>256 || id<1 || id>t.nodes.len || branch>64 {return false;}let n=t.nodes[id-1];
 if n.tag==8 {return node(o,t,n.a,depth+1,branch) && node(o,t,n.b,depth+1,branch);}
 if n.tag==1 {check_one(o,0,1);check_one(o,4,0);bump(o,8,0x6a);return true;}
 if n.tag==2 {check_one(o,0,1);check_one(o,4,0);st(o,0,0);return true;}
 if n.tag==3 {check_one(o,0,1);bump(o,4,0x6a);ld(o,256);pool_guest::set(o,1);o.append([0x02,0x40]);if !node(o,t,n.a,depth+1,0){return false;}o.push(0x0b);bump(o,4,0x6b);return true;}
 if n.tag==4 {pool_guest::get(o,0);o.append([0x04,0x40]);if !node(o,t,n.a,depth+1,branch+1){return false;}if n.b!=0 {o.push(0x05);if !node(o,t,n.b,depth+1,branch+1){return false;}}o.push(0x0b);return true;}
 if n.tag==6 {pool_guest::get(o,1);o.push(0x0f);return true;}
 if n.tag==7 {o.push(0x0c);pool_guest::uleb(o,branch);return true;}
 return false;
}
fn worker(t:ownership_syntax::Tree&)->u8[] {var b:u8[>..]=[1,1,0x7f];if !node(b,t,t.root,0,0){return [];}b.append([0,0x0b]);return copy(b);}
fn entry(core:owned_scalar_source::Core,flag:bool)->u8[] {
 var b:u8[>..]=[1,1,0x7f];check_one(b,0,0);check_one(b,4,0);
 if core.work_bytes>3840 {b.append([0x42,0x80,0x80,0x80,0x80,0x30,0x42]);b.push(if core.work_bytes>4294962944 {1} else {3});b.append([0x84,0x0f,0x0b]);return copy(b);}
 st(b,0,4);st(b,8,1);
 if core.terminal==2 {st(b,0,0);b.append([0x42,0x80,0x80,0x80,0x80,0x20,0x0f,0x0b]);return copy(b);}
 st(b,256,core.value);st(b,0,1);
 const32(b,if flag {1} else {0});pool_guest::call(b,0);pool_guest::set(b,0);check_one(b,0,0);check_one(b,4,0);pool_guest::get(b,0);b.append([0xad,0x0b]);return copy(b);
}
import owned_scalar_source;
fn emit(s:u8[:])->u8[] {
 var p=owned_wasm_plan::plan(s);if p.status!=0 {return [];}
 let w=worker(p.consumer.tree);if w.len==0 {return [];}let e=entry(p.core,p.flag);
 var out:u8[>..]=[0,97,115,109,1,0,0,0];
 pool_guest::section(out,1,[2,0x60,1,0x7f,1,0x7f,0x60,0,1,0x7e]);pool_guest::section(out,3,[2,0,1]);pool_guest::section(out,5,[1,1,1,1]);
 pool_guest::section(out,7,[1,6,'i','n','v','o','k','e',0,1]);var code:u8[>..]=[2];pool_guest::add_body(code,w);pool_guest::add_body(code,e);pool_guest::section(out,10,code);return copy(out);
}
