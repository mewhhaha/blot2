// Scalar effect owner keys reject dead and reused pooled leases.
import bootstrap_globals;
import driver.cli;
import driver.cli_workers;
import std;
import check.effect_evidence;
import support.error;
type Handle=blot_check_effect_evidence::Handle;
fn rows(key:Handle,decl:u32) {
 var store=blot_check_effect_evidence::fromHandle(key);
 let op,error=store.internOperation(blot_check_types::NominalIdentity {7,decl},[11 as u32,13 as u32]);assert(error==blot_error::Error.none && op==1);
 let same,error=store.internOperation(blot_check_types::NominalIdentity {7,decl},[11 as u32,13 as u32]);assert(error==blot_error::Error.none && same==op);
 let row,error=store.internRowWithFormal([op],5);assert(error==blot_error::Error.none && row==1);
 let again,error=store.internRowWithFormal([op],5);assert(error==blot_error::Error.none && again==row);
 let observed=blot_check_effect_evidence::fromHandle(key);let view=observed.view();
 assert(view.owner_id==key.owner_id && view.operation(op).identity.decl==decl && view.operationArguments(op)==[11 as u32,13 as u32]);
 assert(view.rows[row].formal==5 && view.rowLabels(row)==[op]);
 let checked=blot_check_effect_evidence::handle(observed);assert(checked.owner_id==key.owner_id && checked.lease==key.lease && checked.generation==key.generation);
}
fn main() {
 var zero=Handle{};assert(!blot_check_effect_evidence::valid(zero));zero.deinit();zero.deinit();
 var source,error=blot_check_effect_evidence::init();assert(error==blot_error::Error.none);
 var key=blot_check_effect_evidence::handle(source);let stale=key;
 assert(blot_check_effect_evidence::valid(key));rows(key,17);
 key.deinit();assert(key.owner_id==0 && key.lease==0 && key.generation==0 && !blot_check_effect_evidence::valid(stale));key.deinit();
 var replacement,error=blot_check_effect_evidence::init();assert(error==blot_error::Error.none);
 var fresh=blot_check_effect_evidence::handle(replacement);
 assert(fresh.lease==stale.lease && fresh.generation!=stale.generation && fresh.owner_id!=stale.owner_id);
 assert(!blot_check_effect_evidence::valid(stale) && blot_check_effect_evidence::valid(fresh));
 let wrong_generation=Handle{fresh.owner_id,fresh.lease,stale.generation};let wrong_owner=Handle{stale.owner_id,fresh.lease,fresh.generation};
 assert(!blot_check_effect_evidence::valid(wrong_generation) && !blot_check_effect_evidence::valid(wrong_owner));
 let empty=blot_check_effect_evidence::fromHandle(fresh);assert(empty.operations.len==1 && empty.rows.len==1 && empty.arguments.len==0 && empty.labels.len==0);
 rows(fresh,23);fresh.deinit();assert(!blot_check_effect_evidence::valid(fresh) && !blot_check_effect_evidence::valid(stale));
 print("effect evidence handles passed: zero, live rows/operations, release, reused slot and stale key isolation");
}
