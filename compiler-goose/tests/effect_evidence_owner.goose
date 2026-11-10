// Move existing evidence allocations; source retirement must not invalidate them.
import bootstrap_globals;
import driver.cli;
import driver.cli_workers;
import std;
import check.effect_evidence;
import eval.type_evidence;
import eval.purity_type_key;
import driver.compile_workspace;
fn evidenceBucketGrowth() {
 var source,error=blot_eval_type_evidence::init();assert(error==blot_error::Error.none);
 let first,error=source.intern(blot_eval_type_evidence::Tag.array,3,0,[]);assert(error==blot_error::Error.none);
 var current=first;
 for index in 0..64 {let next,error=source.intern(blot_eval_type_evidence::Tag.array,current,0,[]);assert(error==blot_error::Error.none);current=next;}
 assert(source.buckets.reserve(512)==blot_error::Error.none);
 let capacity=source.buckets.slots.len;let count=source.buckets.count;let nodes=source.nodes.len;
 assert(source.buckets.reserve(1)==blot_error::Error.none && source.buckets.slots.len==capacity);
 var frame,error=blot_compile_workspace::create(blot_native::fresh_owner_id());assert(error==blot_error::Error.none && frame.release()==blot_error::Error.none);
 let repeated,error=source.intern(blot_eval_type_evidence::Tag.array,3,0,[]);assert(error==blot_error::Error.none && repeated==first);
 assert(source.buckets.count==count && source.nodes.len==nodes && source.node(current).tag==blot_eval_type_evidence::Tag.array);
 source.deinit();
}
fn main() {evidenceBucketGrowth();purityKeys();
 var source,error=blot_check_effect_evidence::init();assert(error==blot_error::Error.none);
 var destination,error=blot_check_effect_evidence::init();assert(error==blot_error::Error.none);
 let label,error=source.internOperation(blot_check_types::NominalIdentity{7,9},[11 as u32,13 as u32]);assert(error==blot_error::Error.none);
 let row,error=source.internRow([label]);assert(error==blot_error::Error.none && row!=0);
 let identity=source.owner_id;assert(blot_check_effect_evidence::prepareCommit(source,destination)==blot_error::Error.none);
 blot_check_effect_evidence::commit(source,destination);assert(destination.owner_id==identity);source.deinit();
 var frame,error=blot_compile_workspace::create(blot_native::fresh_owner_id());assert(error==blot_error::Error.none && frame.valid());assert(frame.release()==blot_error::Error.none);
 assert(destination.view().operation(label).identity==blot_check_types::NominalIdentity{7,9});assert(destination.view().operationArguments(label)==[11 as u32,13 as u32]);assert(destination.view().rowLabels(row)==[label]);
 let again,error=destination.internOperation(blot_check_types::NominalIdentity{7,9},[11 as u32,13 as u32]);assert(error==blot_error::Error.none && again==label);
 let same,error=destination.internRow([label]);assert(error==blot_error::Error.none && same==row);destination.deinit();
}

struct PurityNames {module:const u8[:],declaration:const u8[:],second_module:const u8[:],second_declaration:const u8[:]}
fn origin(self_:PurityNames&,identity:blot_check_types::NominalIdentity,kind:blot_eval_purity_type_key::Kind)->blot_eval_purity_type_key::Identity,blot_error::Error {
 if identity.decl==10 {return blot_eval_purity_type_key::Identity{blot_check_check::canonicalDiagnosticText(self_.second_module),blot_check_check::canonicalDiagnosticText(self_.second_declaration)},blot_error::Error.none;}
 return blot_eval_purity_type_key::Identity{blot_check_check::canonicalDiagnosticText(self_.module),blot_check_check::canonicalDiagnosticText(self_.declaration)},blot_error::Error.none;
}
fn arguments(self_:PurityNames&,identity:blot_check_types::NominalIdentity,kind:blot_eval_purity_type_key::Kind,actual:const u32[:])->const u32[:],blot_error::Error {return actual,blot_error::Error.none;}
fn purityKeys() {
 var types,error=blot_check_types::init();assert(error==blot_error::Error.none);
 var names=PurityNames{blot_check_check::ownDiagnosticText("z"),blot_check_check::ownDiagnosticText("perform"),blot_check_check::ownDiagnosticText("aa"),blot_check_check::ownDiagnosticText("b")};
 var context,error=blot_eval_purity_type_key::initContext(types,names);assert(error==blot_error::Error.none);
 let label,error=types.internOperation(blot_check_types::NominalIdentity{7,9},default<const u32[:]>());assert(error==blot_error::Error.none);
 let second,error=types.internOperation(blot_check_types::NominalIdentity{7,10},default<const u32[:]>());assert(error==blot_error::Error.none);
 let row,error=types.effects.row([label,blot_check_types::foreign_operation,second],blot_check_effects::Tail.closed);assert(error==blot_error::Error.none);
 let key,error=context.rowKey(row,65536);assert(error==blot_error::Error.none);
 assert(key=="7:2:aa1:b25:13:blot:compiler7:Foreign12:1:z7:perform");
 let repeated,error=context.rowKey(row,65536);assert(error==blot_error::Error.none&&key==repeated);
 context.deinit();blot_check_check::freeDiagnosticText(names.module);blot_check_check::freeDiagnosticText(names.declaration);blot_check_check::freeDiagnosticText(names.second_module);blot_check_check::freeDiagnosticText(names.second_declaration);types.deinit();
 var frame,error=blot_compile_workspace::create(blot_native::fresh_owner_id());assert(error==blot_error::Error.none);assert(frame.release()==blot_error::Error.none);
 assert(key==repeated&&key.len>0);blot_eval_purity_type_key::release(repeated);blot_eval_purity_type_key::release(key);
 print("purity identity local publication passed");
}
