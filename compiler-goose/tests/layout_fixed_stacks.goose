// Existing quantifier limits use fixed scratch and unwind counts on every exit.
import bootstrap_globals;
import driver.cli;
import driver.cli_workers;
import std;
import backend.layout;
import check.types;
import check.core;
import support.error;
type Error=blot_error::Error;
struct Probe {calls:u32=0}
fn empty(store:const blot_backend_layout::Store&) {assert(store.type_owner_count==0 && store.solver_owner_count==0 && store.solver_binder_count==0);}
fn probe(context:Probe&,store:blot_backend_layout::Store&)->Error {
 empty(store);var source,error=blot_check_types::init();assert(error==blot_error::Error.none);
 var binders:u32[128]=default<u32[128]>();
 for index in 0..128 {let binder,error=source.boundType(index as u32,0);assert(error==blot_error::Error.none);binders[index]=binder;}
 var wide=binders[127];var narrow=binders[0];
 for _ in 0..128 {let next,error=source.quantified(blot_check_types::Tag.forall,wide,binders[..]);assert(error==blot_error::Error.none);wide=next;let next,error=source.quantified(blot_check_types::Tag.forall,narrow,binders[..1]);assert(error==blot_error::Error.none);narrow=next;}
 let wide_over,error=source.quantified(blot_check_types::Tag.forall,wide,binders[..]);assert(error==blot_error::Error.none);
 let narrow_over,error=source.quantified(blot_check_types::Tag.forall,narrow,binders[..1]);assert(error==blot_error::Error.none);
 let bad_inner,error=source.quantified(blot_check_types::Tag.forall,0,binders[..1]);assert(error==blot_error::Error.none);
 let bad_outer,error=source.quantified(blot_check_types::Tag.forall,bad_inner,binders[..1]);assert(error==blot_error::Error.none);
 let wide_result,error=store.fromSolver(source,wide);assert(error==blot_error::Error.none && store.node(wide_result).tag==blot_backend_layout::Tag.universal);empty(store);
 var wide_leaf=wide_result;for _ in 0..128 {wide_leaf=store.node(wide_leaf).a;}let opened=store.node(wide_leaf);assert(opened.tag==blot_backend_layout::Tag.opened && opened.a==127 && opened.b==0);
 assert(store.solver_owners[127].start==16256 && store.solver_owners[127].len==128 && store.solver_binders[16383]==binders[127]);
 let rejected,error=store.fromSolver(source,wide_over);assert(error==blot_error::Error.layout_limit);empty(store);
 let rejected,error=store.fromSolver(source,bad_outer);assert(error==blot_error::Error.unresolved_type);empty(store);
 let repeated,error=store.fromSolver(source,wide);assert(error==blot_error::Error.none && repeated==wide_result);empty(store);
 var module=default<blot_check_core::Module>();module.types=blot_check_core::Types {nodes:source.nodes.items,extra:source.extra.items,..};
 let result,error=store.fromType(module,narrow,[]);assert(error==blot_error::Error.none && store.node(result).tag==blot_backend_layout::Tag.universal);empty(store);
 assert(store.type_owners[127]!=0);var narrow_leaf=result;for _ in 0..128 {narrow_leaf=store.node(narrow_leaf).a;}let opened=store.node(narrow_leaf);assert(opened.tag==blot_backend_layout::Tag.opened && opened.a==0 && opened.b==0);
 let rejected,error=store.fromType(module,narrow_over,[]);assert(error==blot_error::Error.layout_limit);empty(store);
 let rejected,error=store.fromType(module,bad_outer,[]);assert(error==blot_error::Error.unresolved_type);empty(store);
 let repeated,error=store.fromType(module,narrow,[]);assert(error==blot_error::Error.none && repeated==result);empty(store);
 source.deinit();context.calls++;return blot_error::Error.none;
}
fn main(){var context=Probe{};assert(blot_backend_layout::withStore(context,probe)==blot_error::Error.none && context.calls==1);print("layout fixed stacks passed: 128 owners, 16384 binders, overflow rejection and nested count unwind");}
