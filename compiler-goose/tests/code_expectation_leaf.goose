// Fixed-tag binder synthesis shares the canonical validation/intern leaf.
import bootstrap_globals;
import driver.cli;
import driver.cli_workers;
import std;
import support.u64_id_map;
import reuse.code_expectation;
import support.error;
fn main() {
 var nodes=blot_reuse_code_expectation::Nodes{};var extra=blot_reuse_code_expectation::Ids{};var next=blot_reuse_code_expectation::Ids{};var buckets=blot_support_u64_id_map::Buckets{};
 var store,error=blot_reuse_code_expectation::init(nodes,extra,next,buckets);assert(error==blot_error::Error.none && nodes.len==6);
 let quantified,error=store.intern(blot_eval_type_evidence::Tag.forall,3,2,[]);assert(error==blot_error::Error.none && quantified==8 && nodes.len==9);
 assert(store.view().children(quantified)==[6 as u32,7 as u32]);
 let first=store.view().node(6);let second=store.view().node(7);assert(first.tag==blot_eval_type_evidence::Tag.bound && first.a==0 && second.tag==blot_eval_type_evidence::Tag.bound && second.a==1);
 let explicit_,error=store.intern(blot_eval_type_evidence::Tag.forall,3,2,[6 as u32,7 as u32]);assert(error==blot_error::Error.none && explicit_==8 && nodes.len==9);
 let existential,error=store.intern(blot_eval_type_evidence::Tag.existential,3,2,[]);assert(error==blot_error::Error.none && existential==9 && nodes.len==10);
 let repeated,error=store.intern(blot_eval_type_evidence::Tag.existential,3,2,[6 as u32,7 as u32]);assert(error==blot_error::Error.none && repeated==9 && nodes.len==10);
 for count in [0 as u32,129 as u32] {let rejected,error=store.intern(blot_eval_type_evidence::Tag.forall,3,count,[]);assert(error==blot_error::Error.type_mismatch && nodes.len==10);}
 let rejected,error=store.intern(blot_eval_type_evidence::Tag.forall,3,2,[7 as u32,6 as u32]);assert(error==blot_error::Error.type_mismatch && nodes.len==10);
 let rejected,error=store.internBound(128,0,0);assert(error==blot_error::Error.type_mismatch && nodes.len==10);
 let rejected,error=store.internBound(0,3,0);assert(error==blot_error::Error.type_mismatch && nodes.len==10);
 let rejected,error=store.internBound(0,0,128);assert(error==blot_error::Error.type_mismatch && nodes.len==10);
 let boundary,error=store.internBound(127,2,127);assert(error==blot_error::Error.none && boundary==10);
 let sorted,error=store.internBound(0,1,0);assert(error==blot_error::Error.none && sorted==11);
 let rejected,error=store.intern(blot_eval_type_evidence::Tag.existential,3,1,[sorted]);assert(error==blot_error::Error.type_mismatch && nodes.len==12);
 // Invalid body still synthesizes missing default binders before canonical rejection.
 let rejected,error=store.intern(blot_eval_type_evidence::Tag.forall,0,3,[]);assert(error==blot_error::Error.type_mismatch && nodes.len==13 && store.view().node(12).a==2);
 let capacity=buckets.slots.len;
 for _ in 0..3 {let previous=store.owner_id;assert(store.reset()==blot_error::Error.none && store.owner_id!=previous && nodes.len==6 && extra.len==0 && next.len==6 && buckets.count==0 && buckets.slots.len==capacity);let fresh,error=store.intern(blot_eval_type_evidence::Tag.forall,3,1,[]);assert(error==blot_error::Error.none && fresh==7 && store.view().children(fresh)==[6 as u32]);}
 store.deinit();assert(nodes.len==0 && extra.len==0 && next.len==0 && buckets.count==0 && buckets.slots.len==capacity);
 buckets.deinit();assert(buckets.slots.len==0);nodes.deinit();extra.deinit();next.deinit();
 print("code expectation leaf passed: exact IDs, binder synthesis, explicit dedup, guards and owner reset");
}
