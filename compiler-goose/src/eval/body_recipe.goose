// Immutable source visit orders. Every replay performs current region actions.
namespace blot_eval_body_recipe;
import check.check_packet_owner;
import check.core;
import support.error;
import support.native;
import support.pooled_buffer;
import support.pooled_map;

import std;
import dictionary;
import check.check;
type Module=blot_check_core::Module;
type Error=blot_error::Error;
struct Key { owner: i64,body: u32,callables: bool }
fn hash(key: Key) -> u64 { return ::hash_combine(::hash_combine(::hash(key.owner),::hash(key.body)),::hash(key.callables)); }
struct Recipe { visits: const u32[:]=default<const u32[:]>(),has_lexical_captures: bool=false }
struct Pending { items: u32[>..<]&,limit: i64 }
fn append(self_: Pending&,id: u32) -> Error { if self_.items.len==self_.limit { return blot_error::Error.plan_limit; } self_.items.push(id); return blot_error::Error.none; }
fn appendSlice(self_: Pending&,ids: const u32[:]) -> Error { if ids.len>self_.limit-self_.items.len { return blot_error::Error.plan_limit; } self_.items.append(ids); return blot_error::Error.none; }
fn pop(self_: Pending&) -> u32,bool { if self_.items.len==0 { return 0,false; } let id=self_.items[self_.items.len-1]; self_.items.resize(self_.items.len-1); return id,true; }
fn appendChild<W,A,B>(work:W&,first:A&,second:B&,id:u32)->Error {return work.append(id);}
fn appendChildSlice<W,A,B>(work:W&,first:A&,second:B&,ids:const u32[:])->Error {return work.appendSlice(ids);}
recursive fn appendChildren<W>(work:W&,module:const Module&,id:u32,callables:bool)->Error {var first:u8=0;var second:u8=0;return visitChildren<W,u8,u8>(work,first,second,module,id,callables,appendChild,appendChildSlice);}
recursive fn visitChildren<W,A,B,F,G>(work: W&,first:A&,second:B&,module: const Module&,id: u32,callables: bool) -> Error {
 let n=module.node(id); let tag=n.tag;
 if callables&&tag==blot_check_core::Tag.apply&&module.node(n.a).tag==blot_check_core::Tag.closure { let err=F(work,first,second,module.closure(n.a).body); if err!=blot_error::Error.none { return err; } }
 if tag==blot_check_core::Tag.resource_release||tag==blot_check_core::Tag.usage_share||tag==blot_check_core::Tag.usage_read||tag==blot_check_core::Tag.package_pack { return F(work,first,second,n.a); }
 if tag==blot_check_core::Tag.package_unpack { return G(work,first,second,[n.a,module.packageOpening(id).body]); }
 if tag==blot_check_core::Tag.staging||tag==blot_check_core::Tag.scalar||tag==blot_check_core::Tag.associated||tag==blot_check_core::Tag.logical||tag==blot_check_core::Tag.record_merge||tag==blot_check_core::Tag.type_same||tag==blot_check_core::Tag.apply||tag==blot_check_core::Tag.effect_provider||tag==blot_check_core::Tag.handle||tag==blot_check_core::Tag.proof_guard||tag==blot_check_core::Tag.resource_acquire||tag==blot_check_core::Tag.usage_borrow { return G(work,first,second,[n.a,n.b]); }
 if tag==blot_check_core::Tag.resource_scope||tag==blot_check_core::Tag.if_value||tag==blot_check_core::Tag.if_stmt||tag==blot_check_core::Tag.state_provider { return G(work,first,second,[n.a,n.b,n.c]); }
 if tag==blot_check_core::Tag.task||tag==blot_check_core::Tag.block_||tag==blot_check_core::Tag.suite||tag==blot_check_core::Tag.product||tag==blot_check_core::Tag.record||tag==blot_check_core::Tag.array||tag==blot_check_core::Tag.array_op||tag==blot_check_core::Tag.storage||tag==blot_check_core::Tag.call||tag==blot_check_core::Tag.contract_method { return G(work,first,second,module.children(id)); }
 if tag==blot_check_core::Tag.bind { return F(work,first,second,n.b); }
 if tag==blot_check_core::Tag.return_||tag==blot_check_core::Tag.project||tag==blot_check_core::Tag.result_associated { return F(work,first,second,n.a); }
 if tag==blot_check_core::Tag.construct { return F(work,first,second,n.b); }
 if tag==blot_check_core::Tag.pattern_bind { return G(work,first,second,[n.b,n.c]); }
 if tag==blot_check_core::Tag.match_ { let err=G(work,first,second,module.matchInputs(id)); if err!=blot_error::Error.none { return err; } for arm in module.matchArms(id) { let error=G(work,first,second,[arm.guard_,arm.body]); if error!=blot_error::Error.none { return error; } } return blot_error::Error.none; }
 if tag==blot_check_core::Tag.loop_ { let iteration=module.loopInfo(id); return G(work,first,second,[iteration.first,iteration.end,iteration.body]); }
 if tag==blot_check_core::Tag.break_ { return G(work,first,second,module.breakValues(id)); }
 if tag==blot_check_core::Tag.resolver_op {
  let metadata=module.resolverInfo(id); let e=F(work,first,second,metadata.resolver); if e!=blot_error::Error.none { return e; } let error=G(work,first,second,module.resolverArguments(id)); if error!=blot_error::Error.none { return error; }
  if callables&&(metadata.operation==blot_check_core::ResolverOperation.run||metadata.operation==blot_check_core::ResolverOperation.bind||metadata.operation==blot_check_core::ResolverOperation.iterate) { for argument in module.resolverArguments(id) { if module.node(argument).tag==blot_check_core::Tag.closure { let err=F(work,first,second,module.closure(argument).body); if err!=blot_error::Error.none { return err; } } } } return blot_error::Error.none;
 }
 if tag==blot_check_core::Tag.update { let update=module.updateInfo(id); let e=G(work,first,second,[update.root,update.value]); if e!=blot_error::Error.none { return e; } for selector in module.updateSelectors(id) { if selector.kind==blot_check_core::UpdateKind.index { let err=F(work,first,second,selector.index); if err!=blot_error::Error.none { return err; } } } return blot_error::Error.none; }
 if tag==blot_check_core::Tag.effect_reflection {
  let kind,known=blot_check_check::reflectionKindFromCode(n.a); if known&&(kind==blot_check_check::ReflectionKind.count||kind==blot_check_check::ReflectionKind.has||kind==blot_check_check::ReflectionKind.same) { let e=F(work,first,second,n.b); if e!=blot_error::Error.none { return e; } } if n.c!=0 { return F(work,first,second,n.c); } return blot_error::Error.none;
 }
 if tag==blot_check_core::Tag.computation||tag==blot_check_core::Tag.effect_scope { return F(work,first,second,n.a); }
 if tag==blot_check_core::Tag.request_decision { return G(work,first,second,[n.b,n.c]); }
 if tag==blot_check_core::Tag.request_loop { let metadata=module.requestLoopInfo(id); let e=G(work,first,second,[metadata.computation,metadata.completion_body]); if e!=blot_error::Error.none { return e; } for arm in module.requestArms(id) { let err=F(work,first,second,arm.callback); if err!=blot_error::Error.none { return err; } if arm.selector!=0 { let error=F(work,first,second,arm.selector); if error!=blot_error::Error.none { return error; } } } }
 return blot_error::Error.none;
}
// Every published recipe and its visit run has a stable owner until reset.
struct RecipeRecord {value:Recipe=Recipe {}}
reusable var recipe_records:RecipeRecord[>..]=[];
reusable[] var recipe_visits:u32[>..]=[];
struct RecipeTable {storage:u32[:]=default<u32[:]>(),items:u32[:]=default<u32[:]>(),len:i64=0}
reusable[] var recipe_indexes:u32[>..]=[];
fn at(self_:const RecipeTable&,index:i64)->const Recipe& {assert(index>=0&&index<self_.len);return recipe_records[self_.items[index]].value;}
fn publish(self_:RecipeTable&,visits:const u32[:],captures:bool)->u32,Error {
 if self_.len>=0xffffffff||recipe_records.len>=0xffffffff {return 0,blot_error::Error.out_of_memory;}
 let reserved=blot_support_pooled_buffer::ensure(self_,self_.len+1,recipe_indexes);if reserved!=blot_error::Error.none {return 0,reserved;}
 let owned=recipe_visits.alloc_slice(visits.len);for value,index in visits {owned[index]=value;}
 let record=recipe_records.alloc_index(RecipeRecord {value:Recipe {owned,captures}});let index=self_.len as u32;
 self_.storage[self_.len]=record as u32;self_.len++;self_.items=self_.storage[..self_.len];return index,blot_error::Error.none;
}
fn clear(self_:RecipeTable&) {for id in self_.items {let words=recipe_records[id].value.visits;if words.len!=0 {recipe_visits.free_slice(words);}recipe_records.free(id);}self_.items=self_.storage[..0];self_.len=0;}
fn release(self_:RecipeTable&) {self_.clear();blot_support_pooled_buffer::deinit(self_,recipe_indexes);}
type Keys=blot_support_pooled_map::Map<Key,u32>;
type Declines=blot_support_pooled_map::Map<Key,i64>;
reusable[] var key_slots:dictionary_slot<Key,u32>[>..]=[];
reusable[] var decline_slots:dictionary_slot<Key,i64>[>..]=[];
fn get(self_:const Keys&,key:Key)->u32? {return blot_support_pooled_map::get(self_,key);}
fn get(self_:const Declines&,key:Key)->i64? {return blot_support_pooled_map::get(self_,key);}
fn insert(self_:Keys&,key:Key,value:u32) {blot_support_pooled_map::insert(self_,key,value,key_slots);}
fn insert(self_:Declines&,key:Key,value:i64) {blot_support_pooled_map::insert(self_,key,value,decline_slots);}
fn clear(self_:Keys&) {blot_support_pooled_map::clear(self_);}
fn clear(self_:Declines&) {blot_support_pooled_map::clear(self_);}
fn release(self_:Keys&) {blot_support_pooled_map::deinit(self_,key_slots);}
fn release(self_:Declines&) {blot_support_pooled_map::deinit(self_,decline_slots);}
struct CacheState {live:bool=false,generation:u64=0,recipes:RecipeTable=RecipeTable {}, keys:Keys=Keys {}, declined_limits:Declines=Declines {},owner_id:u64=0, requests:i64=0, builds:i64=0, planned_visits:i64=0, replayed_visits:i64=0, declined_walks:i64=0, reused_declines:i64=0}
var inactive:CacheState=CacheState {};
struct Cache {lease:u32=0,generation:u64=0,recipes:RecipeTable& =inactive.recipes, keys:Keys& =inactive.keys, declined_limits:Declines& =inactive.declined_limits, owner_id:(u64)& =inactive.owner_id, requests:(i64)& =inactive.requests, builds:(i64)& =inactive.builds, planned_visits:(i64)& =inactive.planned_visits, replayed_visits:(i64)& =inactive.replayed_visits, declined_walks:(i64)& =inactive.declined_walks, reused_declines:(i64)& =inactive.reused_declines}
struct CacheSlot {state:CacheState=CacheState {},handle:Cache=Cache {}}
reusable var cache_slots:CacheSlot[>..]=[];
fn valid(self_:const Cache&)->bool {return self_.lease!=0&&self_.lease-1<cache_slots.len&&cache_slots[self_.lease-1].state.live&&cache_slots[self_.lease-1].state.generation==self_.generation;}
fn initPooled()->Cache,Error {
 if cache_slots.len>=0xffffffff {return Cache {},blot_error::Error.out_of_memory;}
 let generation=blot_native::fresh_owner_id();let at=cache_slots.alloc_index(CacheSlot {state:CacheState {live:true,generation:generation,owner_id:blot_native::fresh_owner_id()}});let slot:CacheSlot& =cache_slots[at];
 let result=Cache {lease:(at+1) as u32,generation:generation,recipes:cache_slots[at].state.recipes, keys:cache_slots[at].state.keys, declined_limits:cache_slots[at].state.declined_limits, owner_id:cache_slots[at].state.owner_id, requests:cache_slots[at].state.requests, builds:cache_slots[at].state.builds, planned_visits:cache_slots[at].state.planned_visits, replayed_visits:cache_slots[at].state.replayed_visits, declined_walks:cache_slots[at].state.declined_walks, reused_declines:cache_slots[at].state.reused_declines};slot.handle=result;return result,blot_error::Error.none;
}
fn init()->Cache,Error {return initPooled();}
fn initPooledRef()->Cache?,Error {let cache,error=initPooled();if error!=blot_error::Error.none {return null,error;}return cache_slots[cache.lease-1].handle,blot_error::Error.none;}
fn deinit(self_:Cache&) {if self_.lease==0 {return;}assert(valid(self_));self_.recipes.release();release(self_.keys);release(self_.declined_limits);let at=self_.lease-1;cache_slots[at].state.live=false;self_=Cache {};cache_slots.free(at);}
fn build(visits: u32[>..<]&,module: const Module&,key: Key,limit: i64) -> bool,Error {
 var items: u32[>..<]=[]; var work=Pending {items,limit}; var seen: dictionary<u32,bool> =dictionary<u32,bool> {}; let error=append(work,key.body); if error!=blot_error::Error.none { return false,error; } var captures=false;
 loop { let id,present=pop(work); if !present { break; } if id==0||::contains(seen,id) { continue; } if visits.len==limit { return false,blot_error::Error.plan_limit; } ::insert(seen,id,true); visits.push(id); let tag=module.node(id).tag;
  if tag==blot_check_core::Tag.closure&&module.closures[module.node(id).a].captures.len!=0 { captures=true; } if tag==blot_check_core::Tag.invalid { break; }
  let err=appendChildren(work,module,id,key.callables); if err!=blot_error::Error.none { return false,err; }
 } return captures,blot_error::Error.none;
}
fn get(self_: Cache&,units: const Module[:],key: Key,max_values: i64) -> const Recipe?,Error {
 assert(valid(self_));self_.requests++; let known=get(self_.keys,key); if known { let recipe=self_.recipes.at(known); if recipe.visits.len<=max_values { return self_.recipes.at(known),blot_error::Error.none; } self_.declined_walks++; return null,blot_error::Error.none; }
 var limit=max_values; if limit>4096 { limit=4096; } if limit==0 { self_.declined_walks++; return null,blot_error::Error.none; }
 let decline=get(self_.declined_limits,key); if decline&&limit<=decline { self_.declined_walks++; self_.reused_declines++; return null,blot_error::Error.none; }
 var visits: u32[>..<]=[]; let captures,error=build(visits,units[key.owner],key,limit);
 if error==blot_error::Error.plan_limit { insert(self_.declined_limits,key,limit); self_.declined_walks++; return null,blot_error::Error.none; } if error!=blot_error::Error.none { return null,error; }
 let index,published=self_.recipes.publish(visits,captures);if published!=blot_error::Error.none {return null,published;}insert(self_.keys,key,index);self_.builds++;self_.planned_visits+=visits.len;return self_.recipes.at(index),blot_error::Error.none;
}
type Work=blot_support_pooled_buffer::Buffer<u32>;
type Seen=blot_support_pooled_map::Map<u32,bool>;
reusable[] var walk_words:u32[>..]=[];
reusable[] var walk_slots:dictionary_slot<u32,bool>[>..]=[];
struct Walk {recipe:const Recipe?=null,index:i64=0,count:i64=0,work:Work=Work {},seen:Seen=Seen {}}
fn deinit(self_:Walk&) {blot_support_pooled_buffer::deinit(self_.work,walk_words);blot_support_pooled_map::deinit(self_.seen,walk_slots);self_=Walk {};}
fn append(self_:Walk&,id:u32)->Error {if self_.recipe!=null {return blot_error::Error.none;}return blot_support_pooled_buffer::push(self_.work,id,walk_words);}
fn appendSlice(self_:Walk&,ids:const u32[:])->Error {if self_.recipe!=null {return blot_error::Error.none;}return blot_support_pooled_buffer::append(self_.work,ids,walk_words);}
fn next(self_:Walk&)->u32,bool,Error {
 let recipe=self_.recipe;if recipe {if self_.index==recipe.visits.len {return 0,false,blot_error::Error.none;}let id=recipe.visits[self_.index];self_.index++;self_.count++;return id,true,blot_error::Error.none;}
 while self_.work.items.len!=0 {let length=self_.work.items.len-1;let id=self_.work.items[length];blot_support_pooled_buffer::resize(self_.work,length);if id==0||blot_support_pooled_map::contains(self_.seen,id) {continue;}blot_support_pooled_map::insert(self_.seen,id,true,walk_slots);self_.count++;return id,true,blot_error::Error.none;}return 0,false,blot_error::Error.none;
}
fn reset(self_:Cache&) {assert(valid(self_));self_.recipes.clear();clear(self_.keys);clear(self_.declined_limits);self_.owner_id=blot_native::fresh_owner_id();self_.requests=0;self_.builds=0;self_.planned_visits=0;self_.replayed_visits=0;self_.declined_walks=0;self_.reused_declines=0;}
