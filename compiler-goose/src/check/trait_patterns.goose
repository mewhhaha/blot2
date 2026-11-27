namespace squid_check_trait_patterns;
import check.effects;
import check.types;
import reuse.principal_interface;
import support.error;

import dictionary;
type Store=squid_check_types::Store;
type Declaration=squid_reuse_principal_interface::Implementation;
type Error=squid_error::Error;
struct Instance { head: squid_check_types::List }
struct Work { id: u32,row: bool=false,depth: i64=0 }
fn chargeGraph(store: Store&,root: u32) -> Error {
 var pending: Work[>..<]=[Work {id:root}]; var seen: dictionary<u64,bool> = dictionary<u64,bool>{};
 while pending.len!=0 {
  let work=pending[pending.len-1]; pending.resize(pending.len-1); let e=store.chargeProjection(); if e!=squid_error::Error.none { return e; } if work.depth>=256 { return squid_error::Error.type_limit; }
  var key=work.id as u64; if work.row { key|=0x100000000; } if seen.contains(key) { continue; } seen.insert(key,true);
  if work.row { for label in store.rowLabels(work.id) { let err=store.chargeProjection(); if err!=squid_error::Error.none { return err; } for argument in store.operationArguments(label) { pending.push(Work {id:argument,depth:work.depth+1}); } } continue; }
  let value=store.node(store.head(work.id,0)); let tag=value.tag;
  if tag==squid_check_types::Tag.function||tag==squid_check_types::Tag.provider { pending.push(Work {value.c,true,work.depth+1}); }
  if tag==squid_check_types::Tag.function { pending.push(Work {id:value.a,depth:work.depth+1}); pending.push(Work {id:value.b,depth:work.depth+1}); }
  else if tag==squid_check_types::Tag.array||tag==squid_check_types::Tag.provider { pending.push(Work {id:value.a,depth:work.depth+1}); }
  else if tag==squid_check_types::Tag.state_provider { let children: u32[3]=[value.a,value.b,value.c]; for child in children { pending.push(Work {id:child,depth:work.depth+1}); } }
  else if tag==squid_check_types::Tag.product { for child in store.list(squid_check_types::List {value.a,value.b}) { pending.push(Work {id:child,depth:work.depth+1}); } }
  else if tag==squid_check_types::Tag.record { for index in 0..value.b { pending.push(Work {id:store.recordField(value,index).ty,depth:work.depth+1}); } }
  else if tag==squid_check_types::Tag.nominal||tag==squid_check_types::Tag.projection { for child in store.nominalArguments(value) { pending.push(Work {id:child,depth:work.depth+1}); } }
 }
 return squid_error::Error.none;
}
fn typeBinders(store: Store&,declaration: Declaration) -> u32[>..],Error { var result: u32[>..]=[]; for value in store.list(declaration.variables) { result.push(store.head(value,0)); } return result,squid_error::Error.none; }
fn instantiate(store: Store&,declaration: Declaration,variables: u32[>..<]&) -> Instance,Error {
 let err=store.chargeProjection(); if err!=squid_error::Error.none { return default<Instance>(),err; }
 let old,e=typeBinders(store,declaration); if e!=squid_error::Error.none { return default<Instance>(),e; }
 let variable_start=variables.len; for i in 0..old.len { let id,error=store.fresh(); if error!=squid_error::Error.none { return default<Instance>(),error; } variables.push(id); }
 var before: u32[>..]=[]; before.append(store.list(declaration.head)); var head: u32[>..]=[];
 for root in before { let failure=chargeGraph(store,root); if failure!=squid_error::Error.none { return default<Instance>(),failure; } let resolved,e1=store.resolve(root,0); if e1!=squid_error::Error.none { return default<Instance>(),e1; } let substituted,e2=store.substituteWithRows(resolved,old,variables[variable_start..],[],[]); if e2!=squid_error::Error.none { return default<Instance>(),e2; } head.push(substituted); }
 let list,e3=store.saveList(head); if e3!=squid_error::Error.none { return default<Instance>(),e3; } return Instance {list},squid_error::Error.none;
}
fn matches(store: Store&,declaration: Declaration,actual: const u32[:]) -> bool,Error {
 if actual.len!=declaration.head.len { return false,squid_error::Error.none; } let point=store.mark();
 var roots: u32[>..]=[]; roots.append(actual); var variables: u32[>..<]=[]; let instance,e=instantiate(store,declaration,variables); if e!=squid_error::Error.none { store.rollback(point); return false, e; }
 for root,index in roots { let err=store.chargeProjection(); if err!=squid_error::Error.none { store.rollback(point); return false, err; } let error=store.unifyPattern(store.list(instance.head)[index],root); if error==squid_error::Error.out_of_memory||error==squid_error::Error.type_limit { store.rollback(point); return false, error; } if error!=squid_error::Error.none { store.rollback(point); return false, squid_error::Error.none; } } store.rollback(point); return true, squid_error::Error.none;
}
fn matchesRigid(store: Store&,declaration: Declaration,actual: const u32[:]) -> bool,Error {
 if actual.len!=declaration.head.len { return false,squid_error::Error.none; } let point=store.mark();
 var roots: u32[>..]=[]; roots.append(actual); let product,e=store.product(roots); if e!=squid_error::Error.none { store.rollback(point); return false, e; } let pack,error=store.resolve(product,0); if error!=squid_error::Error.none { store.rollback(point); return false, error; }
 let rigid,e1=store.freeVariables(pack); if e1!=squid_error::Error.none { store.rollback(point); return false, e1; }
 var variables: u32[>..<]=[]; let instance,e3=instantiate(store,declaration,variables); if e3!=squid_error::Error.none { store.rollback(point); return false, e3; }
 for root,index in roots { let err=store.unifyPattern(store.list(instance.head)[index],root); if err==squid_error::Error.out_of_memory||err==squid_error::Error.type_limit { store.rollback(point); return false, err; } if err!=squid_error::Error.none { store.rollback(point); return false, squid_error::Error.none; } }
 for variable in rigid { if store.head(variable,0)!=variable { store.rollback(point); return false, squid_error::Error.none; } }
 store.rollback(point); return true, squid_error::Error.none;
}
fn overlap(store: Store&,a: Declaration,b: Declaration) -> bool,Error {
 let err=store.chargeProjection(); if err!=squid_error::Error.none { return false,err; } if a.contract!=b.contract||a.head.len!=b.head.len { return false,squid_error::Error.none; }
 let point=store.mark(); var av: u32[>..<]=[]; var bv: u32[>..<]=[];
 let left,e=instantiate(store,a,av); if e!=squid_error::Error.none { store.rollback(point); return false, e; } let right,error=instantiate(store,b,bv); if error!=squid_error::Error.none { store.rollback(point); return false, error; }
 for index in 0..left.head.len { let charge=store.chargeProjection(); if charge!=squid_error::Error.none { store.rollback(point); return false, charge; } let failure=store.unifyPattern(store.list(left.head)[index],store.list(right.head)[index]); if failure==squid_error::Error.out_of_memory||failure==squid_error::Error.type_limit { store.rollback(point); return false, failure; } if failure!=squid_error::Error.none { store.rollback(point); return false, squid_error::Error.none; } } store.rollback(point); return true, squid_error::Error.none;
}
reusable[] var instance_words: u32[>..]=[];
fn instantiateInto(store: Store&,declaration: Declaration,variables: u32[:]) -> Instance,Error {
 if variables.len!=declaration.variables.len { return default<Instance>(),squid_error::Error.type_mismatch; }
 let charged=store.chargeProjection(); if charged!=squid_error::Error.none { return default<Instance>(),charged; }
 let old=instance_words.alloc_slice(variables.len); let before=instance_words.alloc_slice(declaration.head.len); let head=instance_words.alloc_slice(declaration.head.len);
 let result,error=instantiateRuns(store,declaration,variables,old,before,head);
 instance_words.free_slice(head); instance_words.free_slice(before); instance_words.free_slice(old); return result,error;
}
fn instantiateRuns(store: Store&,declaration: Declaration,variables: u32[:],old: u32[:],before: u32[:],head: u32[:]) -> Instance,Error {
 for value,index in store.list(declaration.variables) { old[index]=store.head(value,0); }
 for &variable in variables { let fresh,error=store.fresh(); if error!=squid_error::Error.none { return default<Instance>(),error; } variable=fresh; }
 for root,index in store.list(declaration.head) { before[index]=root; }
 for root,index in before { let charged=chargeGraph(store,root); if charged!=squid_error::Error.none { return default<Instance>(),charged; } let resolved,error=store.resolve(root,0); if error!=squid_error::Error.none { return default<Instance>(),error; } let substituted,failure=store.substituteWithRows(resolved,old,variables,[],[]); if failure!=squid_error::Error.none { return default<Instance>(),failure; } head[index]=substituted; }
 let list,error=store.saveList(head); if error!=squid_error::Error.none { return default<Instance>(),error; } return Instance {list},squid_error::Error.none;
}
