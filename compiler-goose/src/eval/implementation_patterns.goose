namespace blot_eval_implementation_patterns;
import dictionary;
import check.types;
import check.effects;
import reuse.principal_interface;
import support.error;
type Store=blot_check_types::Store;
type Declaration=blot_reuse_principal_interface::Implementation;
type Error=blot_error::Error;
struct Instance { variables: const u32[:],rows: const u32[:],head: blot_check_types::List }
struct Work { id: u32,row: bool=false,depth: i64=0 }
fn chargeGraph(store: Store&,root: u32) -> Error {
 var pending: Work[>..<]=[Work {id:root}]; var seen: dictionary<u64,bool>;
 while pending.len!=0 {
  let work=pending[pending.len-1]; pending.resize(pending.len-1); let e=store.chargeProjection(); if e!=Error.none { return e; } if work.depth>=256 { return Error.type_limit; }
  var key=work.id as u64; if work.row { key|=0x100000000; } if seen.contains(key) { continue; } seen.insert(key,true);
  if work.row { for label in store.rowLabels(work.id) { let err=store.chargeProjection(); if err!=Error.none { return err; } for argument in store.operationArguments(label) { pending.push(Work {id:argument,depth:work.depth+1}); } } continue; }
  let value=store.node(store.head(work.id,0)); let tag=value.tag;
  if tag==blot_check_types::Tag.function||tag==blot_check_types::Tag.provider { pending.push(Work {value.c,true,work.depth+1}); }
  if tag==blot_check_types::Tag.function { pending.push(Work {id:value.a,depth:work.depth+1}); pending.push(Work {id:value.b,depth:work.depth+1}); }
  else if tag==blot_check_types::Tag.array||tag==blot_check_types::Tag.list||tag==blot_check_types::Tag.cursor||tag==blot_check_types::Tag.resolver||tag==blot_check_types::Tag.provider { pending.push(Work {id:value.a,depth:work.depth+1}); }
  else if tag==blot_check_types::Tag.state_provider { let children: u32[3]=[value.a,value.b,value.c]; for child in children { pending.push(Work {id:child,depth:work.depth+1}); } }
  else if tag==blot_check_types::Tag.product { for child in store.list(blot_check_types::List {value.a,value.b}) { pending.push(Work {id:child,depth:work.depth+1}); } }
  else if tag==blot_check_types::Tag.record { for index in 0..value.b { pending.push(Work {id:store.recordField(value,index).ty,depth:work.depth+1}); } }
  else if tag==blot_check_types::Tag.nominal||tag==blot_check_types::Tag.projection { for child in store.nominalArguments(value) { pending.push(Work {id:child,depth:work.depth+1}); } }
 }
 return Error.none;
}
fn typeBinders(store: Store&,declaration: Declaration) -> u32[>..],Error { var result: u32[>..]=[]; for value in store.list(declaration.variables) { result.push(store.head(value,0)); } return result,Error.none; }
fn rowBinders(store: Store&,declaration: Declaration) -> u32[>..],Error {
 var result: u32[>..]=[]; let count=declaration.row_variables.len;
 for ordinal in 0..count { let resolved,e=store.resolveEffects(store.list(declaration.row_parameters)[ordinal],0); if e!=Error.none { return [],e; } let row=store.row(resolved); match row.tail { variable v=>{ result.push(v.value); },_=>{ return [],Error.type_mismatch; }, } } return result,Error.none;
}
fn instantiate(store: Store&,declaration: Declaration,variables: u32[>..<]&,rows: u32[>..<]&) -> Instance,Error {
 let err=store.chargeProjection(); if err!=Error.none { return default<Instance>(),err; }
 let old,e=typeBinders(store,declaration); if e!=Error.none { return default<Instance>(),e; }
 let variable_start=variables.len; for i in 0..old.len { let id,error=store.fresh(); if error!=Error.none { return default<Instance>(),error; } variables.push(id); }
 let old_rows,error=rowBinders(store,declaration); if error!=Error.none { return default<Instance>(),error; }
 let row_start=rows.len; for i in 0..old_rows.len { let id,failure=store.freshEffects(); if failure!=Error.none { return default<Instance>(),failure; } rows.push(id); }
 var before: u32[>..]=[]; before.append(store.list(declaration.head)); var head: u32[>..]=[];
 for root in before { let failure=chargeGraph(store,root); if failure!=Error.none { return default<Instance>(),failure; } let resolved,e1=store.resolve(root,0); if e1!=Error.none { return default<Instance>(),e1; } let substituted,e2=store.substituteWithRows(resolved,old,variables[variable_start..],old_rows,rows[row_start..]); if e2!=Error.none { return default<Instance>(),e2; } head.push(substituted); }
 let list,e3=store.saveList(head); if e3!=Error.none { return default<Instance>(),e3; } return Instance {variables[variable_start..],rows[row_start..],list},Error.none;
}
fn matches(store: Store&,declaration: Declaration,actual: const u32[:]) -> bool,Error {
 if actual.len!=declaration.head.len { return false,Error.none; } let point=store.mark(); defer { store.rollback(point); }
 var roots: u32[>..]=[]; roots.append(actual); var variables: u32[>..<]=[]; var rows: u32[>..<]=[]; let instance,e=instantiate(store,declaration,variables,rows); if e!=Error.none { return false,e; }
 for root,index in roots { let err=store.chargeProjection(); if err!=Error.none { return false,err; } let error=store.unifyPattern(store.list(instance.head)[index],root); if error==Error.out_of_memory||error==Error.type_limit { return false,error; } if error!=Error.none { return false,Error.none; } } return true,Error.none;
}
fn matchesRigid(store: Store&,declaration: Declaration,actual: const u32[:]) -> bool,Error {
 if actual.len!=declaration.head.len { return false,Error.none; } let point=store.mark(); defer { store.rollback(point); }
 var roots: u32[>..]=[]; roots.append(actual); let product,e=store.product(roots); if e!=Error.none { return false,e; } let pack,error=store.resolve(product,0); if error!=Error.none { return false,error; }
 let rigid,e1=store.freeVariables(pack); if e1!=Error.none { return false,e1; } let rigid_rows,e2=store.freeRowVariables(pack); if e2!=Error.none { return false,e2; }
 var variables: u32[>..<]=[]; var rows: u32[>..<]=[]; let instance,e3=instantiate(store,declaration,variables,rows); if e3!=Error.none { return false,e3; }
 for root,index in roots { let err=store.unifyPattern(store.list(instance.head)[index],root); if err==Error.out_of_memory||err==Error.type_limit { return false,err; } if err!=Error.none { return false,Error.none; } }
 for variable in rigid { if store.head(variable,0)!=variable { return false,Error.none; } }
 for variable in rigid_rows { let row_id,err=store.effects.row([],blot_check_effects::Tail.variable {value:variable}); if err!=Error.none { return false,blot_check_types::effectError(err); } let resolved,er=store.resolveEffects(row_id,0); if er!=Error.none { return false,er; } let row=store.row(resolved); if row.labels.len!=0 { return false,Error.none; } match row.tail { variable v=>{ if v.value!=variable { return false,Error.none; } },_=>{ return false,Error.none; }, } }
 return true,Error.none;
}
fn overlap(store: Store&,a: Declaration,b: Declaration) -> bool,Error {
 let err=store.chargeProjection(); if err!=Error.none { return false,err; } if a.contract!=b.contract||a.head.len!=b.head.len { return false,Error.none; }
 let point=store.mark(); defer { store.rollback(point); } var av: u32[>..<]=[]; var ar: u32[>..<]=[]; var bv: u32[>..<]=[]; var br: u32[>..<]=[];
 let left,e=instantiate(store,a,av,ar); if e!=Error.none { return false,e; } let right,error=instantiate(store,b,bv,br); if error!=Error.none { return false,error; }
 for index in 0..left.head.len { let charge=store.chargeProjection(); if charge!=Error.none { return false,charge; } let failure=store.unifyPattern(store.list(left.head)[index],store.list(right.head)[index]); if failure==Error.out_of_memory||failure==Error.type_limit { return false,failure; } if failure!=Error.none { return false,Error.none; } } return true,Error.none;
}
