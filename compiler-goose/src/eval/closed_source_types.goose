namespace blot_eval_closed_source_types;
import dictionary;
import support.pooled_map;
import check.core;
import check.types;
import check.effects;
import support.error;
import support.native;
struct FactMap { count: i64=0,slots: dictionary_slot<u64,bool>[:]=[] }
reusable[] var pool_FactMap: dictionary_slot<u64,bool>[>..]=[];
fn get(self: const FactMap&,key: u64) -> bool? { let view=blot_support_pooled_map::Map<u64,bool> {count:self.count,slots:self.slots}; return blot_support_pooled_map::get(view,key); }
fn contains(self: const FactMap&,key: u64) -> bool { return self.get(key)!=null; }
fn insert(self: FactMap&,key: u64,value: bool) { var view=blot_support_pooled_map::Map<u64,bool> {count:self.count,slots:self.slots}; blot_support_pooled_map::insert(view,key,value,pool_FactMap); self.count=view.count; self.slots=view.slots; }
fn clear(self: FactMap&) { for &slot in self.slots { slot.tag=0; } self.count=0; }
fn release(self: FactMap&) { if self.slots.len!=0 { pool_FactMap.free_slice(self.slots); } self.slots=[]; self.count=0; }
fn restore(self: FactMap&,slots: const dictionary_slot<u64,bool>[:],count: i64) { release(self); self.count=count; if slots.len!=0 { self.slots=pool_FactMap.alloc_slice(slots.len); for slot,index in slots { self.slots[index]=slot; } } }
struct FactsState { answers: FactMap=FactMap {},owner_id: u64=0,lease_generation: u64=0,live: bool=false }
reusable var Facts_states: FactsState[>..]=[];
var inactive_Facts: FactsState=FactsState {};
var next_Facts_generation: u64=1;
struct Facts { answers: FactMap&=inactive_Facts.answers,owner_id: u64&=inactive_Facts.owner_id,lease: u32=0,lease_generation: u64=0 }
fn initFactsPooled() -> Facts,blot_error::Error { if next_Facts_generation==0xffffffffffffffff||Facts_states.len>=0xffffffff { return Facts {},blot_error::Error.out_of_memory; } let generation=next_Facts_generation; next_Facts_generation++; let index=Facts_states.alloc_index(FactsState {lease_generation:generation,live:true,owner_id:blot_native::fresh_owner_id()}); let state: FactsState&=Facts_states[index]; return Facts {answers:state.answers,owner_id:state.owner_id,lease:(index+1) as u32,lease_generation:generation},blot_error::Error.none; }
fn deinit(self: Facts&) { if self.lease==0 { return; } let index=self.lease-1; assert(index<Facts_states.len&&Facts_states[index].live&&Facts_states[index].lease_generation==self.lease_generation); release(self.answers); Facts_states[index].live=false; Facts_states.free(index); self=Facts {}; }

fn key(owner: i64,ty: u32) -> u64 { return (owner as u64)<<32|ty; }
fn closed(self: Facts&,units: const blot_check_core::Module[:],owner: i64,ty: u32,depth: i64) -> bool,blot_error::Error {
 if ty<=5 { return ty!=0,blot_error::Error.none; } if depth>=256 { return false,blot_error::Error.none; }
 let id=key(owner,ty); let known=self.answers.get(id); if known { return known,blot_error::Error.none; }
 let source=units[owner].types; let n=source.node(ty); let tag=n.tag; var result=false;
 if tag==blot_check_types::Tag.unit||tag==blot_check_types::Tag.boolean||tag==blot_check_types::Tag.unsigned32||tag==blot_check_types::Tag.floating32||tag==blot_check_types::Tag.never||tag==blot_check_types::Tag.type_constructor { result=true; }
 else if tag==blot_check_types::Tag.array||tag==blot_check_types::Tag.list||tag==blot_check_types::Tag.cursor||tag==blot_check_types::Tag.resolver { let value,err=closed(self,units,owner,n.a,depth+1); if err!=blot_error::Error.none { return false,err; } result=value; }
 else if tag==blot_check_types::Tag.function||tag==blot_check_types::Tag.provider {
  let a,e=closed(self,units,owner,n.a,depth+1); if e!=blot_error::Error.none { return false,e; } result=a;
  if result&&tag==blot_check_types::Tag.function { let b,error=closed(self,units,owner,n.b,depth+1); if error!=blot_error::Error.none { return false,error; } result=b; }
  if result { let row,err=closedRow(self,units,owner,n.c,depth+1); if err!=blot_error::Error.none { return false,err; } result=row; }
 } else if tag==blot_check_types::Tag.state_provider {
  result=true; let children: u32[3]=[n.a,n.b,n.c]; for child in children { let value,err=closed(self,units,owner,child,depth+1); if err!=blot_error::Error.none { return false,err; } if !value { result=false; break; } }
 } else if tag==blot_check_types::Tag.product||tag==blot_check_types::Tag.nominal {
  var children=source.list(blot_check_types::List {n.a,n.b}); if tag==blot_check_types::Tag.nominal { children=source.nominalArguments(n); } result=true;
  for child in children { let value,err=closed(self,units,owner,child,depth+1); if err!=blot_error::Error.none { return false,err; } if !value { result=false; break; } }
 } else if tag==blot_check_types::Tag.record { result=true; for index in 0..n.b { let value,err=closed(self,units,owner,source.recordField(n,index).ty,depth+1); if err!=blot_error::Error.none { return false,err; } if !value { result=false; break; } } }
 self.answers.insert(id,result); return result,blot_error::Error.none;
}
fn closedRow(self: Facts&,units: const blot_check_core::Module[:],owner: i64,row: u32,depth: i64) -> bool,blot_error::Error {
 if depth>=256 { return false,blot_error::Error.none; } let source=units[owner].types; if source.row(row).tail!=blot_check_effects::Tail.closed { return false,blot_error::Error.none; }
 for label in source.rowLabels(row) { for arg in source.operationArguments(label) { let value,err=closed(self,units,owner,arg,depth+1); if err!=blot_error::Error.none||!value { return value,err; } } } return true,blot_error::Error.none;
}
struct CacheKey { source: u64,depth: i64 }
fn hash(key: CacheKey) -> u64 { return ::hash_combine(::hash(key.source),::hash(key.depth)); }
struct AnswerMap { count: i64=0,slots: dictionary_slot<CacheKey,u32>[:]=[] }
reusable[] var pool_AnswerMap: dictionary_slot<CacheKey,u32>[>..]=[];
fn get(self: const AnswerMap&,key: CacheKey) -> u32? { let view=blot_support_pooled_map::Map<CacheKey,u32> {count:self.count,slots:self.slots}; return blot_support_pooled_map::get(view,key); }
fn contains(self: const AnswerMap&,key: CacheKey) -> bool { return self.get(key)!=null; }
fn insert(self: AnswerMap&,key: CacheKey,value: u32) { var view=blot_support_pooled_map::Map<CacheKey,u32> {count:self.count,slots:self.slots}; blot_support_pooled_map::insert(view,key,value,pool_AnswerMap); self.count=view.count; self.slots=view.slots; }
fn clear(self: AnswerMap&) { for &slot in self.slots { slot.tag=0; } self.count=0; }
fn release(self: AnswerMap&) { if self.slots.len!=0 { pool_AnswerMap.free_slice(self.slots); } self.slots=[]; self.count=0; }
fn restore(self: AnswerMap&,slots: const dictionary_slot<CacheKey,u32>[:],count: i64) { release(self); self.count=count; if slots.len!=0 { self.slots=pool_AnswerMap.alloc_slice(slots.len); for slot,index in slots { self.slots[index]=slot; } } }
struct CacheState { answers: AnswerMap=AnswerMap {},owner_id: u64=0,generation: u16=0,physical: u64=0,max_depth: i64=0,lease_generation: u64=0,live: bool=false }
reusable var Cache_states: CacheState[>..]=[];
var inactive_Cache: CacheState=CacheState {};
var next_Cache_generation: u64=1;
struct Cache { answers: AnswerMap&=inactive_Cache.answers,owner_id: u64&=inactive_Cache.owner_id,generation: u16&=inactive_Cache.generation,physical: u64&=inactive_Cache.physical,max_depth: i64&=inactive_Cache.max_depth,lease: u32=0,lease_generation: u64=0 }
fn initPooled() -> Cache,blot_error::Error { if next_Cache_generation==0xffffffffffffffff||Cache_states.len>=0xffffffff { return Cache {},blot_error::Error.out_of_memory; } let generation=next_Cache_generation; next_Cache_generation++; let index=Cache_states.alloc_index(CacheState {lease_generation:generation,live:true,owner_id:blot_native::fresh_owner_id()}); let state: CacheState&=Cache_states[index]; return Cache {answers:state.answers,owner_id:state.owner_id,generation:state.generation,physical:state.physical,max_depth:state.max_depth,lease:(index+1) as u32,lease_generation:generation},blot_error::Error.none; }
fn deinit(self: Cache&) { if self.lease==0 { return; } let index=self.lease-1; assert(index<Cache_states.len&&Cache_states[index].live&&Cache_states[index].lease_generation==self.lease_generation); release(self.answers); Cache_states[index].live=false; Cache_states.free(index); self=Cache {}; }

fn clearRetainingCapacity(self: Cache&) { self.answers.clear(); self.generation=0; self.physical=0; self.max_depth=0; }
fn activate(self: Cache&,solver: const blot_check_types::Store&,max_depth: i64) -> bool {
 if self.generation!=solver.closed_generation||self.physical!=solver.effects.physical_epoch||self.max_depth!=max_depth { self.answers.clear(); self.generation=solver.closed_generation; self.physical=solver.effects.physical_epoch; self.max_depth=max_depth; }
 return self.generation!=0xffff&&self.physical!=0xffffffffffffffff;
}
fn cacheKey(owner: i64,ty: u32,depth: i64) -> CacheKey { return CacheKey {key(owner,ty),depth}; }
