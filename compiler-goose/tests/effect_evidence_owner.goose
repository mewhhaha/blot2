// Move existing evidence allocations; source retirement must not invalidate them.
import bootstrap_globals;
import driver.cli;
import driver.cli_workers;
import std;
import check.effect_evidence;
import driver.compile_workspace;
fn main() {
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
