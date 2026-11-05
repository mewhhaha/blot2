namespace blot_eval_implementation_patterns;
import check.effects;
import check.types;
import reuse.principal_interface;
import support.error;

import dictionary;
type Store=blot_check_types::Store;
type Declaration=blot_reuse_principal_interface::Implementation;
type Error=blot_error::Error;
struct Instance { variables: const u32[:],rows: const u32[:],head: blot_check_types::List }
struct Work { id: u32,row: bool=false,depth: i64=0 }
fn chargeGraph(store: Store&,root: u32) -> Error {
 var pending: Work[>..<]=[Work {id:root}]; var seen: dictionary<u64,bool>;
 while pending.len!=0 {
  let work=pending[pending.len-1]; pending.resize(pending.len-1); let e=store.chargeProjection(); if e!=blot_error::Error.none { return e; } if work.depth>=256 { return blot_error::Error.type_limit; }
  var key=work.id as u64; if work.row { key|=0x100000000; } if seen.contains(key) { continue; } seen.insert(key,true);
  if work.row { for label in store.rowLabels(work.id) { let err=store.chargeProjection(); if err!=blot_error::Error.none { return err; } for argument in store.operationArguments(label) { pending.push(Work {id:argument,depth:work.depth+1}); } } continue; }
  let value=store.node(store.head(work.id,0)); let tag=value.tag;
  if tag==blot_check_types::Tag.function||tag==blot_check_types::Tag.provider { pending.push(Work {value.c,true,work.depth+1}); }
  if tag==blot_check_types::Tag.function { pending.push(Work {id:value.a,depth:work.depth+1}); pending.push(Work {id:value.b,depth:work.depth+1}); }
  else if tag==blot_check_types::Tag.array||tag==blot_check_types::Tag.list||tag==blot_check_types::Tag.cursor||tag==blot_check_types::Tag.resolver||tag==blot_check_types::Tag.provider { pending.push(Work {id:value.a,depth:work.depth+1}); }
  else if tag==blot_check_types::Tag.state_provider { let children: u32[3]=[value.a,value.b,value.c]; for child in children { pending.push(Work {id:child,depth:work.depth+1}); } }
  else if tag==blot_check_types::Tag.product { for child in store.list(blot_check_types::List {value.a,value.b}) { pending.push(Work {id:child,depth:work.depth+1}); } }
  else if tag==blot_check_types::Tag.record { for index in 0..value.b { pending.push(Work {id:store.recordField(value,index).ty,depth:work.depth+1}); } }
  else if tag==blot_check_types::Tag.nominal||tag==blot_check_types::Tag.projection { for child in store.nominalArguments(value) { pending.push(Work {id:child,depth:work.depth+1}); } }
 }
 return blot_error::Error.none;
}
fn typeBinders(store: Store&,declaration: Declaration) -> u32[>..],Error { var result: u32[>..]=[]; for value in store.list(declaration.variables) { result.push(store.head(value,0)); } return result,blot_error::Error.none; }
fn rowBinders(store: Store&,declaration: Declaration) -> u32[>..],Error {
 var result: u32[>..]=[]; let count=declaration.row_variables.len;
 for ordinal in 0..count { let resolved,e=store.resolveEffects(store.list(declaration.row_parameters)[ordinal],0); if e!=blot_error::Error.none { return [],e; } let row=store.row(resolved); match row.tail { variable v=>{ result.push(v.value); },_=>{ return [],blot_error::Error.type_mismatch; }, } } return result,blot_error::Error.none;
}
fn instantiate(store: Store&,declaration: Declaration,variables: u32[>..<]&,rows: u32[>..<]&) -> Instance,Error {
 let err=store.chargeProjection(); if err!=blot_error::Error.none { return default<Instance>(),err; }
 let old,e=typeBinders(store,declaration); if e!=blot_error::Error.none { return default<Instance>(),e; }
 let variable_start=variables.len; for i in 0..old.len { let id,error=store.fresh(); if error!=blot_error::Error.none { return default<Instance>(),error; } variables.push(id); }
 let old_rows,error=rowBinders(store,declaration); if error!=blot_error::Error.none { return default<Instance>(),error; }
 let row_start=rows.len; for i in 0..old_rows.len { let id,failure=store.freshEffects(); if failure!=blot_error::Error.none { return default<Instance>(),failure; } rows.push(id); }
 var before: u32[>..]=[]; before.append(store.list(declaration.head)); var head: u32[>..]=[];
 for root in before { let failure=chargeGraph(store,root); if failure!=blot_error::Error.none { return default<Instance>(),failure; } let resolved,e1=store.resolve(root,0); if e1!=blot_error::Error.none { return default<Instance>(),e1; } let substituted,e2=store.substituteWithRows(resolved,old,variables[variable_start..],old_rows,rows[row_start..]); if e2!=blot_error::Error.none { return default<Instance>(),e2; } head.push(substituted); }
 let list,e3=store.saveList(head); if e3!=blot_error::Error.none { return default<Instance>(),e3; } return Instance {variables[variable_start..],rows[row_start..],list},blot_error::Error.none;
}
fn matches(store: Store&,declaration: Declaration,actual: const u32[:]) -> bool,Error {
 if actual.len!=declaration.head.len { return false,blot_error::Error.none; } let point=store.mark();
 var roots: u32[>..]=[]; roots.append(actual); var variables: u32[>..<]=[]; var rows: u32[>..<]=[]; let instance,e=instantiate(store,declaration,variables,rows); if e!=blot_error::Error.none { let __cleanup_result_117_0: bool = false; let __cleanup_result_117_1: Error = e; { store.rollback(point); } return __cleanup_result_117_0, __cleanup_result_117_1; }
 for root,index in roots { let err=store.chargeProjection(); if err!=blot_error::Error.none { let __cleanup_result_118_0: bool = false; let __cleanup_result_118_1: Error = err; { store.rollback(point); } return __cleanup_result_118_0, __cleanup_result_118_1; } let error=store.unifyPattern(store.list(instance.head)[index],root); if error==blot_error::Error.out_of_memory||error==blot_error::Error.type_limit { let __cleanup_result_119_0: bool = false; let __cleanup_result_119_1: Error = error; { store.rollback(point); } return __cleanup_result_119_0, __cleanup_result_119_1; } if error!=blot_error::Error.none { let __cleanup_result_120_0: bool = false; let __cleanup_result_120_1: Error = blot_error::Error.none; { store.rollback(point); } return __cleanup_result_120_0, __cleanup_result_120_1; } } let __cleanup_result_121_0: bool = true; let __cleanup_result_121_1: Error = blot_error::Error.none; { store.rollback(point); } return __cleanup_result_121_0, __cleanup_result_121_1;
 { store.rollback(point); } }
fn matchesRigid(store: Store&,declaration: Declaration,actual: const u32[:]) -> bool,Error {
 if actual.len!=declaration.head.len { return false,blot_error::Error.none; } let point=store.mark();
 var roots: u32[>..]=[]; roots.append(actual); let product,e=store.product(roots); if e!=blot_error::Error.none { let __cleanup_result_122_0: bool = false; let __cleanup_result_122_1: Error = e; { store.rollback(point); } return __cleanup_result_122_0, __cleanup_result_122_1; } let pack,error=store.resolve(product,0); if error!=blot_error::Error.none { let __cleanup_result_123_0: bool = false; let __cleanup_result_123_1: Error = error; { store.rollback(point); } return __cleanup_result_123_0, __cleanup_result_123_1; }
 let rigid,e1=store.freeVariables(pack); if e1!=blot_error::Error.none { let __cleanup_result_124_0: bool = false; let __cleanup_result_124_1: Error = e1; { store.rollback(point); } return __cleanup_result_124_0, __cleanup_result_124_1; } let rigid_rows,e2=store.freeRowVariables(pack); if e2!=blot_error::Error.none { let __cleanup_result_125_0: bool = false; let __cleanup_result_125_1: Error = e2; { store.rollback(point); } return __cleanup_result_125_0, __cleanup_result_125_1; }
 var variables: u32[>..<]=[]; var rows: u32[>..<]=[]; let instance,e3=instantiate(store,declaration,variables,rows); if e3!=blot_error::Error.none { let __cleanup_result_126_0: bool = false; let __cleanup_result_126_1: Error = e3; { store.rollback(point); } return __cleanup_result_126_0, __cleanup_result_126_1; }
 for root,index in roots { let err=store.unifyPattern(store.list(instance.head)[index],root); if err==blot_error::Error.out_of_memory||err==blot_error::Error.type_limit { let __cleanup_result_127_0: bool = false; let __cleanup_result_127_1: Error = err; { store.rollback(point); } return __cleanup_result_127_0, __cleanup_result_127_1; } if err!=blot_error::Error.none { let __cleanup_result_128_0: bool = false; let __cleanup_result_128_1: Error = blot_error::Error.none; { store.rollback(point); } return __cleanup_result_128_0, __cleanup_result_128_1; } }
 for variable in rigid { if store.head(variable,0)!=variable { let __cleanup_result_129_0: bool = false; let __cleanup_result_129_1: Error = blot_error::Error.none; { store.rollback(point); } return __cleanup_result_129_0, __cleanup_result_129_1; } }
 for variable in rigid_rows { let row_id,err=store.effects.row([],blot_check_effects::Tail.variable {value:variable}); if err!=blot_error::Error.none { let __cleanup_result_130_0: bool = false; let __cleanup_result_130_1: Error = blot_check_types::effectError(err); { store.rollback(point); } return __cleanup_result_130_0, __cleanup_result_130_1; } let resolved,er=store.resolveEffects(row_id,0); if er!=blot_error::Error.none { let __cleanup_result_131_0: bool = false; let __cleanup_result_131_1: Error = er; { store.rollback(point); } return __cleanup_result_131_0, __cleanup_result_131_1; } let row=store.row(resolved); if row.labels.len!=0 { let __cleanup_result_132_0: bool = false; let __cleanup_result_132_1: Error = blot_error::Error.none; { store.rollback(point); } return __cleanup_result_132_0, __cleanup_result_132_1; } match row.tail { variable v=>{ if v.value!=variable { let __cleanup_result_133_0: bool = false; let __cleanup_result_133_1: Error = blot_error::Error.none; { store.rollback(point); } return __cleanup_result_133_0, __cleanup_result_133_1; } },_=>{ let __cleanup_result_134_0: bool = false; let __cleanup_result_134_1: Error = blot_error::Error.none; { store.rollback(point); } return __cleanup_result_134_0, __cleanup_result_134_1; }, } }
 let __cleanup_result_135_0: bool = true; let __cleanup_result_135_1: Error = blot_error::Error.none; { store.rollback(point); } return __cleanup_result_135_0, __cleanup_result_135_1;
 { store.rollback(point); } }
fn overlap(store: Store&,a: Declaration,b: Declaration) -> bool,Error {
 let err=store.chargeProjection(); if err!=blot_error::Error.none { return false,err; } if a.contract!=b.contract||a.head.len!=b.head.len { return false,blot_error::Error.none; }
 let point=store.mark();  var av: u32[>..<]=[]; var ar: u32[>..<]=[]; var bv: u32[>..<]=[]; var br: u32[>..<]=[];
 let left,e=instantiate(store,a,av,ar); if e!=blot_error::Error.none { let __cleanup_result_136_0: bool = false; let __cleanup_result_136_1: Error = e; { store.rollback(point); } return __cleanup_result_136_0, __cleanup_result_136_1; } let right,error=instantiate(store,b,bv,br); if error!=blot_error::Error.none { let __cleanup_result_137_0: bool = false; let __cleanup_result_137_1: Error = error; { store.rollback(point); } return __cleanup_result_137_0, __cleanup_result_137_1; }
 for index in 0..left.head.len { let charge=store.chargeProjection(); if charge!=blot_error::Error.none { let __cleanup_result_138_0: bool = false; let __cleanup_result_138_1: Error = charge; { store.rollback(point); } return __cleanup_result_138_0, __cleanup_result_138_1; } let failure=store.unifyPattern(store.list(left.head)[index],store.list(right.head)[index]); if failure==blot_error::Error.out_of_memory||failure==blot_error::Error.type_limit { let __cleanup_result_139_0: bool = false; let __cleanup_result_139_1: Error = failure; { store.rollback(point); } return __cleanup_result_139_0, __cleanup_result_139_1; } if failure!=blot_error::Error.none { let __cleanup_result_140_0: bool = false; let __cleanup_result_140_1: Error = blot_error::Error.none; { store.rollback(point); } return __cleanup_result_140_0, __cleanup_result_140_1; } } let __cleanup_result_141_0: bool = true; let __cleanup_result_141_1: Error = blot_error::Error.none; { store.rollback(point); } return __cleanup_result_141_0, __cleanup_result_141_1;
 { store.rollback(point); } }

// These temporary runs remain fixed descriptors while substitution re-enters
// prerequisite resolution. The output runs belong to the caller.
reusable[] var instance_words: u32[>..]=[];
fn instantiateInto(store: Store&,declaration: Declaration,variables: u32[:],rows: u32[:]) -> Instance,Error {
 if variables.len!=declaration.variables.len||rows.len!=declaration.row_variables.len { return default<Instance>(),blot_error::Error.type_mismatch; }
 let charged=store.chargeProjection(); if charged!=blot_error::Error.none { return default<Instance>(),charged; }
 let old=instance_words.alloc_slice(variables.len); let old_rows=instance_words.alloc_slice(rows.len); let before=instance_words.alloc_slice(declaration.head.len); let head=instance_words.alloc_slice(declaration.head.len);
 let result,error=instantiateRuns(store,declaration,variables,rows,old,old_rows,before,head);
 instance_words.free_slice(head); instance_words.free_slice(before); instance_words.free_slice(old_rows); instance_words.free_slice(old); return result,error;
}
fn instantiateRuns(store: Store&,declaration: Declaration,variables: u32[:],rows: u32[:],old: u32[:],old_rows: u32[:],before: u32[:],head: u32[:]) -> Instance,Error {
 for value,index in store.list(declaration.variables) { old[index]=store.head(value,0); }
 for &variable in variables { let fresh,error=store.fresh(); if error!=blot_error::Error.none { return default<Instance>(),error; } variable=fresh; }
 for ordinal in 0..rows.len { let resolved,error=store.resolveEffects(store.list(declaration.row_parameters)[ordinal],0); if error!=blot_error::Error.none { return default<Instance>(),error; } let row=store.row(resolved); match row.tail { variable value=>{ old_rows[ordinal]=value.value; },_=>{ return default<Instance>(),blot_error::Error.type_mismatch; }, } }
 for &row in rows { let fresh,error=store.freshEffects(); if error!=blot_error::Error.none { return default<Instance>(),error; } row=fresh; }
 for root,index in store.list(declaration.head) { before[index]=root; }
 for root,index in before { let charged=chargeGraph(store,root); if charged!=blot_error::Error.none { return default<Instance>(),charged; } let resolved,error=store.resolve(root,0); if error!=blot_error::Error.none { return default<Instance>(),error; } let substituted,failure=store.substituteWithRows(resolved,old,variables,old_rows,rows); if failure!=blot_error::Error.none { return default<Instance>(),failure; } head[index]=substituted; }
 let list,error=store.saveList(head); if error!=blot_error::Error.none { return default<Instance>(),error; } return Instance {variables,rows,list},blot_error::Error.none;
}
