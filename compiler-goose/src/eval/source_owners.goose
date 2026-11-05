namespace blot_eval_source_owners;
import reuse.principal_interface;

import check.check_packet_owner;
import check.core;
import eval.body_recipe;
import support.error;
import support.native;
import support.pooled_map;

import dictionary;
import check.check;
type Error=blot_error::Error;
let ambiguous: u32=0xffffffff;
struct Index { nodes: const u32[:]=default<const u32[:]>(),bindings: const u32[:]=default<const u32[:]>(),complete: bool=false }
fn record(slots: u32[:],id: u32,owner: u32) { if id==0||id>=slots.len { return; } if slots[id]==0 { slots[id]=owner; } else if slots[id]!=owner { slots[id]=ambiguous; } }
fn result(self_: Index,slots: const u32[:],id: u32) -> u32,bool { if !self_.complete||id==0||id>=slots.len||slots[id]==0||slots[id]==ambiguous { return 0,false; } return slots[id],true; }
reusable[] var owner_words:u32[>..]=[];
fn deinit(self_:Index&) {release(self_.nodes);release(self_.bindings);self_=Index {};}
fn release(values:const u32[:]) {if values.len==0 {return;}let first:const u32& =values[0];let at=owner_words.index_of(first);assert(at>=0);owner_words.free_slice(owner_words[at..at+values.len]);}
fn retain(nodes:const u32[:],bindings:const u32[:],complete:bool)->Index {let ns=owner_words.alloc_slice(nodes.len);let bs=owner_words.alloc_slice(bindings.len);for value,index in nodes {ns[index]=value;}for value,index in bindings {bs[index]=value;}return Index {ns,bs,complete};}
fn build(module: const blot_check_core::Module&,limit: i64) -> Index,Error {
 if module.nodes.len>limit||module.bindings.len>limit { return Index {},blot_error::Error.none; }
 var nodes: u32[>..<]=[]; nodes.resize(module.nodes.len,0); var bindings: u32[>..<]=[]; bindings.resize(module.bindings.len,0); var seen: u32[>..<]=[]; seen.resize(module.nodes.len,0);
 var items: u32[>..<]=[]; var work=blot_eval_body_recipe::Pending {items,limit}; var remaining=limit;
 for body in module.bodies {
  if body.binding==0||body.binding>=module.bindings.len||module.bindings[body.binding].kind!=blot_reuse_principal_interface::Kind.global { continue; }
  if items.len==limit { return retain(nodes,bindings,false),blot_error::Error.none; } items.push(body.root); record(bindings,body.binding,body.binding);
  for parameter in module.bodyParameters(body) { record(bindings,parameter.binding,body.binding); }
  loop {
   let id,present=work.pop(); if !present { break; } if id==0 { continue; }
   if id>=module.nodes.len||remaining==0 { return retain(nodes,bindings,false),blot_error::Error.none; } if seen[id]==body.binding { continue; }
   seen[id]=body.binding; remaining--; record(nodes,id,body.binding); let n=module.node(id);
   if n.tag==blot_check_core::Tag.closure { let closure=module.closure(id); record(bindings,closure.parameter.binding,body.binding); let e=work.append(closure.body); if e==blot_error::Error.plan_limit { return retain(nodes,bindings,false),blot_error::Error.none; } if e!=blot_error::Error.none { return Index {},e; } }
   if n.tag==blot_check_core::Tag.bind { record(bindings,n.a,body.binding); }
   let e=blot_eval_body_recipe::appendChildren(work,module,id,false); if e==blot_error::Error.plan_limit { return retain(nodes,bindings,false),blot_error::Error.none; } if e!=blot_error::Error.none { return Index {},e; }
  }
 }
 for binding,id in module.bindings { if binding.kind!=blot_reuse_principal_interface::Kind.local||binding.initializer==0||binding.initializer>=nodes.len { continue; } let owner=nodes[binding.initializer]; if owner!=0 { record(bindings,id as u32,owner); } }
 return retain(nodes,bindings,true),blot_error::Error.none;
}
type UnitMap=blot_support_pooled_map::Map<i64,Index>;
reusable[] var unit_slots:dictionary_slot<i64,Index>[>..]=[];
fn get(self_:const UnitMap&,key:i64)->Index? {return blot_support_pooled_map::get(self_,key);}
fn insert(self_:UnitMap&,key:i64,value:Index) {blot_support_pooled_map::insert(self_,key,value,unit_slots);}
fn clear(self_:UnitMap&) {for &slot in self_.slots {if slot.tag!=0 {slot.val.deinit();}}blot_support_pooled_map::clear(self_);}
fn release(self_:UnitMap&) {self_.clear();blot_support_pooled_map::deinit(self_,unit_slots);}
struct CacheState {live:bool=false,generation:u64=0,units:UnitMap=UnitMap {},owner_id:u64=0}
var inactive:CacheState=CacheState {};
struct Cache {lease:u32=0,generation:u64=0,units:UnitMap& =inactive.units, owner_id:(u64)& =inactive.owner_id}
struct CacheSlot {state:CacheState=CacheState {},handle:Cache=Cache {}}
reusable var cache_slots:CacheSlot[>..]=[];
fn valid(self_:const Cache&)->bool {return self_.lease!=0&&self_.lease-1<cache_slots.len&&cache_slots[self_.lease-1].state.live&&cache_slots[self_.lease-1].state.generation==self_.generation;}
fn initPooled()->Cache,Error {
 if cache_slots.len>=0xffffffff {return Cache {},blot_error::Error.out_of_memory;}
 let generation=blot_native::fresh_owner_id();let at=cache_slots.alloc_index(CacheSlot {state:CacheState {live:true,generation:generation,owner_id:blot_native::fresh_owner_id()}});let slot:CacheSlot& =cache_slots[at];
 slot.handle=Cache {lease:(at+1) as u32,generation:generation,units:slot.state.units, owner_id:slot.state.owner_id};return copy(slot.handle),blot_error::Error.none;
}
fn init()->Cache,Error {return initPooled();}
fn initPooledRef()->Cache?,Error {let cache,error=initPooled();if error!=blot_error::Error.none {return null,error;}return cache_slots[cache.lease-1].handle,blot_error::Error.none;}
fn deinit(self_:Cache&) {if self_.lease==0 {return;}assert(valid(self_));self_.units.release();let at=self_.lease-1;cache_slots[at].state.live=false;self_=Cache {};cache_slots.free(at);}
fn index(self_: Cache&,units: const blot_check_core::Module[:],owner: i64,limit: i64) -> Index,bool,Error {
 assert(valid(self_)); if owner<0||owner>=units.len { return Index {},false,blot_error::Error.none; } let known=self_.units.get(owner); if known { return known,true,blot_error::Error.none; }
 let created,e=build(units[owner],limit); if e!=blot_error::Error.none { return Index {},false,e; } self_.units.insert(owner,created); return created,true,blot_error::Error.none;
}
fn binding(self_: Cache&,units: const blot_check_core::Module[:],owner: i64,id: u32,limit: i64) -> u32,bool,Error { let view,present,error=index(self_,units,owner,limit); if error!=blot_error::Error.none||!present { return 0,false,error; } let value,found=result(view,view.bindings,id); return value,found,blot_error::Error.none; }
fn node(self_: Cache&,units: const blot_check_core::Module[:],owner: i64,id: u32,limit: i64) -> u32,bool,Error { let view,present,error=index(self_,units,owner,limit); if error!=blot_error::Error.none||!present { return 0,false,error; } let value,found=result(view,view.nodes,id); return value,found,blot_error::Error.none; }

fn reset(self_:Cache&) {assert(valid(self_));self_.units.clear();self_.owner_id=blot_native::fresh_owner_id();}
