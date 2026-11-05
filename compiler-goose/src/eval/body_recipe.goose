// Immutable source visit orders. Every replay performs current region actions.
namespace blot_eval_body_recipe;
import std;
import dictionary;
import check.core;
import check.check;
import support.error;
import support.native;
import support.pooled_map;
import support.pooled_buffer;
type Module=blot_check_core::Module;
type Error=blot_error::Error;
struct Key { owner: i64,body: u32,callables: bool }
fn hash(key: Key) -> u64 { return ::hash_combine(::hash_combine(::hash(key.owner),::hash(key.body)),::hash(key.callables)); }
struct Recipe { visits: const u32[:]=[],has_lexical_captures: bool=false }
struct Pending { items: u32[>..<]&,limit: i64 }
fn append(self: Pending&,id: u32) -> Error { if self.items.len==self.limit { return Error.plan_limit; } self.items.push(id); return Error.none; }
fn appendSlice(self: Pending&,ids: const u32[:]) -> Error { if ids.len>self.limit-self.items.len { return Error.plan_limit; } self.items.append(ids); return Error.none; }
fn pop(self: Pending&) -> u32,bool { if self.items.len==0 { return 0,false; } let id=self.items[self.items.len-1]; self.items.resize(self.items.len-1); return id,true; }
fn appendChildren<W>(work: W&,module: const Module&,id: u32,callables: bool) -> Error {
 let n=module.node(id); let tag=n.tag;
 if callables&&tag==blot_check_core::Tag.apply&&module.node(n.a).tag==blot_check_core::Tag.closure { let err=work.append(module.closure(n.a).body); if err!=Error.none { return err; } }
 if tag==blot_check_core::Tag.resource_release||tag==blot_check_core::Tag.usage_share||tag==blot_check_core::Tag.usage_read||tag==blot_check_core::Tag.package_pack { return work.append(n.a); }
 if tag==blot_check_core::Tag.package_unpack { return work.appendSlice([n.a,module.packageOpening(id).body]); }
 if tag==blot_check_core::Tag.staging||tag==blot_check_core::Tag.scalar||tag==blot_check_core::Tag.associated||tag==blot_check_core::Tag.logical||tag==blot_check_core::Tag.record_merge||tag==blot_check_core::Tag.type_same||tag==blot_check_core::Tag.apply||tag==blot_check_core::Tag.effect_provider||tag==blot_check_core::Tag.handle||tag==blot_check_core::Tag.proof_guard||tag==blot_check_core::Tag.resource_acquire||tag==blot_check_core::Tag.usage_borrow { return work.appendSlice([n.a,n.b]); }
 if tag==blot_check_core::Tag.resource_scope||tag==blot_check_core::Tag.if_value||tag==blot_check_core::Tag.if_stmt||tag==blot_check_core::Tag.state_provider { return work.appendSlice([n.a,n.b,n.c]); }
 if tag==blot_check_core::Tag.task||tag==blot_check_core::Tag.block_||tag==blot_check_core::Tag.suite||tag==blot_check_core::Tag.product||tag==blot_check_core::Tag.record||tag==blot_check_core::Tag.array||tag==blot_check_core::Tag.array_op||tag==blot_check_core::Tag.storage||tag==blot_check_core::Tag.call||tag==blot_check_core::Tag.contract_method { return work.appendSlice(module.children(id)); }
 if tag==blot_check_core::Tag.bind { return work.append(n.b); }
 if tag==blot_check_core::Tag.return_||tag==blot_check_core::Tag.project||tag==blot_check_core::Tag.result_associated { return work.append(n.a); }
 if tag==blot_check_core::Tag.construct { return work.append(n.b); }
 if tag==blot_check_core::Tag.pattern_bind { return work.appendSlice([n.b,n.c]); }
 if tag==blot_check_core::Tag.match_ { let err=work.appendSlice(module.matchInputs(id)); if err!=Error.none { return err; } for arm in module.matchArms(id) { let error=work.appendSlice([arm.guard,arm.body]); if error!=Error.none { return error; } } return Error.none; }
 if tag==blot_check_core::Tag.loop_ { let iteration=module.loopInfo(id); return work.appendSlice([iteration.first,iteration.end,iteration.body]); }
 if tag==blot_check_core::Tag.break_ { return work.appendSlice(module.breakValues(id)); }
 if tag==blot_check_core::Tag.resolver_op {
  let metadata=module.resolverInfo(id); let e=work.append(metadata.resolver); if e!=Error.none { return e; } let error=work.appendSlice(module.resolverArguments(id)); if error!=Error.none { return error; }
  if callables&&(metadata.operation==blot_check_core::ResolverOperation.run||metadata.operation==blot_check_core::ResolverOperation.bind||metadata.operation==blot_check_core::ResolverOperation.iterate) { for argument in module.resolverArguments(id) { if module.node(argument).tag==blot_check_core::Tag.closure { let err=work.append(module.closure(argument).body); if err!=Error.none { return err; } } } } return Error.none;
 }
 if tag==blot_check_core::Tag.update { let update=module.updateInfo(id); let e=work.appendSlice([update.root,update.value]); if e!=Error.none { return e; } for selector in module.updateSelectors(id) { if selector.kind==blot_check_core::UpdateKind.index { let err=work.append(selector.index); if err!=Error.none { return err; } } } return Error.none; }
 if tag==blot_check_core::Tag.effect_reflection {
  let kind,known=blot_check_check::reflectionKindFromCode(n.a); if known&&(kind==blot_check_check::ReflectionKind.count||kind==blot_check_check::ReflectionKind.has||kind==blot_check_check::ReflectionKind.same) { let e=work.append(n.b); if e!=Error.none { return e; } } if n.c!=0 { return work.append(n.c); } return Error.none;
 }
 if tag==blot_check_core::Tag.computation||tag==blot_check_core::Tag.effect_scope { return work.append(n.a); }
 if tag==blot_check_core::Tag.request_decision { return work.appendSlice([n.b,n.c]); }
 if tag==blot_check_core::Tag.request_loop { let metadata=module.requestLoopInfo(id); let e=work.appendSlice([metadata.computation,metadata.completion_body]); if e!=Error.none { return e; } for arm in module.requestArms(id) { let err=work.append(arm.callback); if err!=Error.none { return err; } if arm.selector!=0 { let error=work.append(arm.selector); if error!=Error.none { return error; } } } }
 return Error.none;
}
// Every published recipe and its visit run has a stable owner until reset.
struct RecipeRecord {value:Recipe=Recipe {}}
reusable var recipe_records:RecipeRecord[>..]=[];
reusable[] var recipe_visits:u32[>..]=[];
struct RecipeTable {storage:u32[:]=[],items:u32[:]=[],len:i64=0}
reusable[] var recipe_indexes:u32[>..]=[];
fn at(self:const RecipeTable&,index:i64)->const Recipe& {assert(index>=0&&index<self.len);return recipe_records[self.items[index]].value;}
fn publish(self:RecipeTable&,visits:const u32[:],captures:bool)->u32,Error {
 if self.len>=0xffffffff||recipe_records.len>=0xffffffff {return 0,Error.out_of_memory;}
 let reserved=blot_support_pooled_buffer::ensure(self,self.len+1,recipe_indexes);if reserved!=Error.none {return 0,reserved;}
 let owned=recipe_visits.alloc_slice(visits.len);for value,index in visits {owned[index]=value;}
 let record=recipe_records.alloc_index(RecipeRecord {value:Recipe {owned,captures}});let index=self.len as u32;
 self.storage[self.len]=record as u32;self.len++;self.items=self.storage[..self.len];return index,Error.none;
}
fn clear(self:RecipeTable&) {for id in self.items {let words=recipe_records[id].value.visits;if words.len!=0 {let first:const u32&=words[0];let at=recipe_visits.index_of(first);assert(at>=0);recipe_visits.free_slice(recipe_visits[at..at+words.len]);}recipe_records.free(id);}self.items=self.storage[..0];self.len=0;}
fn release(self:RecipeTable&) {self.clear();blot_support_pooled_buffer::deinit(self,recipe_indexes);}
type Keys=blot_support_pooled_map::Map<Key,u32>;
type Declines=blot_support_pooled_map::Map<Key,i64>;
reusable[] var key_slots:dictionary_slot<Key,u32>[>..]=[];
reusable[] var decline_slots:dictionary_slot<Key,i64>[>..]=[];
fn get(self:const Keys&,key:Key)->u32? {return blot_support_pooled_map::get(self,key);}
fn get(self:const Declines&,key:Key)->i64? {return blot_support_pooled_map::get(self,key);}
fn insert(self:Keys&,key:Key,value:u32) {blot_support_pooled_map::insert(self,key,value,key_slots);}
fn insert(self:Declines&,key:Key,value:i64) {blot_support_pooled_map::insert(self,key,value,decline_slots);}
fn clear(self:Keys&) {blot_support_pooled_map::clear(self);}
fn clear(self:Declines&) {blot_support_pooled_map::clear(self);}
fn release(self:Keys&) {blot_support_pooled_map::deinit(self,key_slots);}
fn release(self:Declines&) {blot_support_pooled_map::deinit(self,decline_slots);}
struct CacheState {live:bool=false,generation:u64=0,recipes:RecipeTable=RecipeTable {}, keys:Keys=Keys {}, declined_limits:Declines=Declines {},owner_id:u64=0, requests:i64=0, builds:i64=0, planned_visits:i64=0, replayed_visits:i64=0, declined_walks:i64=0, reused_declines:i64=0}
var inactive:CacheState=CacheState {};
struct Cache {lease:u32=0,generation:u64=0,recipes:RecipeTable&=inactive.recipes, keys:Keys&=inactive.keys, declined_limits:Declines&=inactive.declined_limits, owner_id:(u64)&=inactive.owner_id, requests:(i64)&=inactive.requests, builds:(i64)&=inactive.builds, planned_visits:(i64)&=inactive.planned_visits, replayed_visits:(i64)&=inactive.replayed_visits, declined_walks:(i64)&=inactive.declined_walks, reused_declines:(i64)&=inactive.reused_declines}
struct CacheSlot {state:CacheState=CacheState {},handle:Cache=Cache {}}
reusable var cache_slots:CacheSlot[>..]=[];
fn valid(self:const Cache&)->bool {return self.lease!=0&&self.lease-1<cache_slots.len&&cache_slots[self.lease-1].state.live&&cache_slots[self.lease-1].state.generation==self.generation;}
fn initPooled()->Cache,Error {
 if cache_slots.len>=0xffffffff {return Cache {},Error.out_of_memory;}
 let generation=blot_native::fresh_owner_id();let at=cache_slots.alloc_index(CacheSlot {state:CacheState {live:true,generation:generation,owner_id:blot_native::fresh_owner_id()}});let slot:CacheSlot&=cache_slots[at];
 slot.handle=Cache {lease:(at+1) as u32,generation:generation,recipes:slot.state.recipes, keys:slot.state.keys, declined_limits:slot.state.declined_limits, owner_id:slot.state.owner_id, requests:slot.state.requests, builds:slot.state.builds, planned_visits:slot.state.planned_visits, replayed_visits:slot.state.replayed_visits, declined_walks:slot.state.declined_walks, reused_declines:slot.state.reused_declines};return copy(slot.handle),Error.none;
}
fn init()->Cache,Error {return initPooled();}
fn initPooledRef()->Cache?,Error {let cache,error=initPooled();if error!=Error.none {return null,error;}return cache_slots[cache.lease-1].handle,Error.none;}
fn deinit(self:Cache&) {if self.lease==0 {return;}assert(valid(self));self.recipes.release();self.keys.release();self.declined_limits.release();let at=self.lease-1;cache_slots[at].state.live=false;self=Cache {};cache_slots.free(at);}
fn build(visits: u32[>..<]&,module: const Module&,key: Key,limit: i64) -> bool,Error {
 var items: u32[>..<]=[]; var work=Pending {items,limit}; var seen: dictionary<u32,bool>=dictionary<u32,bool> {}; let error=append(work,key.body); if error!=Error.none { return false,error; } var captures=false;
 loop { let id,present=pop(work); if !present { break; } if id==0||seen.contains(id) { continue; } if visits.len==limit { return false,Error.plan_limit; } seen.insert(id,true); visits.push(id); let tag=module.node(id).tag;
  if tag==blot_check_core::Tag.closure&&module.closures[module.node(id).a].captures.len!=0 { captures=true; } if tag==blot_check_core::Tag.invalid { break; }
  let err=appendChildren(work,module,id,key.callables); if err!=Error.none { return false,err; }
 } return captures,Error.none;
}
fn get(self: Cache&,units: const Module[:],key: Key,max_values: i64) -> const Recipe?,Error {
 assert(valid(self));self.requests++; let known=self.keys.get(key); if known { let recipe=self.recipes.at(known); if recipe.visits.len<=max_values { return self.recipes.at(known),Error.none; } self.declined_walks++; return null,Error.none; }
 var limit=max_values; if limit>4096 { limit=4096; } if limit==0 { self.declined_walks++; return null,Error.none; }
 let decline=self.declined_limits.get(key); if decline&&limit<=decline { self.declined_walks++; self.reused_declines++; return null,Error.none; }
 var visits: u32[>..<]=[]; let captures,error=build(visits,units[key.owner],key,limit);
 if error==Error.plan_limit { self.declined_limits.insert(key,limit); self.declined_walks++; return null,Error.none; } if error!=Error.none { return null,error; }
 let index,published=self.recipes.publish(visits,captures);if published!=Error.none {return null,published;}self.keys.insert(key,index);self.builds++;self.planned_visits+=visits.len;return self.recipes.at(index),Error.none;
}
type Work=blot_support_pooled_buffer::Buffer<u32>;
type Seen=blot_support_pooled_map::Map<u32,bool>;
reusable[] var walk_words:u32[>..]=[];
reusable[] var walk_slots:dictionary_slot<u32,bool>[>..]=[];
struct Walk {recipe:const Recipe?=null,index:i64=0,count:i64=0,work:Work=Work {},seen:Seen=Seen {}}
fn deinit(self:Walk&) {blot_support_pooled_buffer::deinit(self.work,walk_words);blot_support_pooled_map::deinit(self.seen,walk_slots);self=Walk {};}
fn append(self:Walk&,id:u32)->Error {if self.recipe!=null {return Error.none;}return blot_support_pooled_buffer::push(self.work,id,walk_words);}
fn appendSlice(self:Walk&,ids:const u32[:])->Error {if self.recipe!=null {return Error.none;}return blot_support_pooled_buffer::append(self.work,ids,walk_words);}
fn next(self:Walk&)->u32,bool,Error {
 let recipe=self.recipe;if recipe {if self.index==recipe.visits.len {return 0,false,Error.none;}let id=recipe.visits[self.index];self.index++;self.count++;return id,true,Error.none;}
 while self.work.items.len!=0 {let length=self.work.items.len-1;let id=self.work.items[length];blot_support_pooled_buffer::resize(self.work,length);if id==0||blot_support_pooled_map::contains(self.seen,id) {continue;}blot_support_pooled_map::insert(self.seen,id,true,walk_slots);self.count++;return id,true,Error.none;}return 0,false,Error.none;
}
fn reset(self:Cache&) {assert(valid(self));self.recipes.clear();self.keys.clear();self.declined_limits.clear();self.owner_id=blot_native::fresh_owner_id();self.requests=0;self.builds=0;self.planned_visits=0;self.replayed_visits=0;self.declined_walks=0;self.reused_declines=0;}
