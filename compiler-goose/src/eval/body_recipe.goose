// Immutable source visit orders. Every replay performs current region actions.
namespace blot_eval_body_recipe;
import std;
import dictionary;
import check.core;
import check.check;
import support.error;
import support.native;
type Module=blot_check_core::Module;
type Error=blot_error::Error;
struct Key { owner: i64,body: u32,callables: bool }
fn hash(key: Key) -> u64 { return ::hash_combine(::hash_combine(::hash(key.owner),::hash(key.body)),::hash(key.callables)); }
struct Recipe { visits: const u32[:],has_lexical_captures: bool=false }
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
struct Cache { owner_id: u64=blot_native::fresh_owner_id(),recipes: Recipe[>..]&,words: u32[>..]&,keys: dictionary<Key,u32>&,declined_limits: dictionary<Key,i64>&,requests: i64=0,builds: i64=0,planned_visits: i64=0,replayed_visits: i64=0,declined_walks: i64=0,reused_declines: i64=0 }
fn build(visits: u32[>..<]&,module: const Module&,key: Key,limit: i64) -> bool,Error {
 var items: u32[>..<]=[]; var work=Pending {items,limit}; var seen: dictionary<u32,bool>; let error=append(work,key.body); if error!=Error.none { return false,error; } var captures=false;
 loop { let id,present=pop(work); if !present { break; } if id==0||seen.contains(id) { continue; } if visits.len==limit { return false,Error.plan_limit; } seen.insert(id,true); visits.push(id); let tag=module.node(id).tag;
  if tag==blot_check_core::Tag.closure&&module.closures[module.node(id).a].captures.len!=0 { captures=true; } if tag==blot_check_core::Tag.invalid { break; }
  let err=appendChildren(work,module,id,key.callables); if err!=Error.none { return false,err; }
 } return captures,Error.none;
}
fn get(self: Cache&,units: const Module[:],key: Key,max_values: i64) -> const Recipe?,Error {
 self.requests++; let known=self.keys.get(key); if known { let recipe=self.recipes[known]; if recipe.visits.len<=max_values { return self.recipes[known],Error.none; } self.declined_walks++; return null,Error.none; }
 var limit=max_values; if limit>4096 { limit=4096; } if limit==0 { self.declined_walks++; return null,Error.none; }
 let decline=self.declined_limits.get(key); if decline&&limit<=decline { self.declined_walks++; self.reused_declines++; return null,Error.none; }
 var visits: u32[>..<]=[]; let captures,error=build(visits,units[key.owner],key,limit);
 if error==Error.plan_limit { self.declined_limits.insert(key,limit); self.declined_walks++; return null,Error.none; } if error!=Error.none { return null,error; }
 let start=self.words.len; self.words.append(visits); let index=self.recipes.len as u32; self.recipes.push(Recipe {self.words[start..],captures}); self.keys.insert(key,index); self.builds++; self.planned_visits+=visits.len; return self.recipes[index],Error.none;
}
struct Walk { recipe: const Recipe?=null,index: i64=0,count: i64=0,work: u32[>..<]&,seen: dictionary<u32,bool>& }
fn append(self: Walk&,id: u32) -> Error { if self.recipe==null { self.work.push(id); } return Error.none; }
fn appendSlice(self: Walk&,ids: const u32[:]) -> Error { if self.recipe==null { self.work.append(ids); } return Error.none; }
fn next(self: Walk&) -> u32,bool,Error {
 if self.recipe { if self.index==self.recipe.visits.len { return 0,false,Error.none; } let id=self.recipe.visits[self.index]; self.index++; self.count++; return id,true,Error.none; }
 while self.work.len!=0 { let id=self.work[self.work.len-1]; self.work.resize(self.work.len-1); if id==0||self.seen.contains(id) { continue; } self.seen.insert(id,true); self.count++; return id,true,Error.none; } return 0,false,Error.none;
}
