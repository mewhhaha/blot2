// Owner traversal keeps branch selection, queue order, dedup and exact node budget.
import bootstrap_globals;
import driver.cli;
import driver.cli_workers;
import std;
import backend.layout;
import support.error;
struct Probe {calls:u32=0}
fn pushNode(store:blot_backend_layout::Store&,tag:blot_backend_layout::Tag,a:u32=0,b:u32=0,c:u32=0)->u32 {let id=store.nodes.len as u32;store.nodes.push(blot_backend_layout::Node{tag,a,b,c});store.next.push(0);return id;}
fn expected(store:const blot_backend_layout::Store&,root:u32,owners:bool,error:blot_error::Error=blot_error::Error.none) {let actual,failure=store.hasOwners(root);assert(actual==owners && failure==error);}
fn probe(context:Probe&,store:blot_backend_layout::Store&)->blot_error::Error {
 expected(store,blot_backend_layout::word,false);
 let owner=pushNode(store,blot_backend_layout::Tag.owning,blot_backend_layout::word);expected(store,owner,true);
 for tag in [blot_backend_layout::Tag.array,blot_backend_layout::Tag.list,blot_backend_layout::Tag.cursor,blot_backend_layout::Tag.resolver,blot_backend_layout::Tag.provider,blot_backend_layout::Tag.scoped,blot_backend_layout::Tag.universal,blot_backend_layout::Tag.existential] {let wrapped=pushNode(store,tag,owner);expected(store,wrapped,true);let plain=pushNode(store,tag,blot_backend_layout::word);expected(store,plain,false);}
 let function=pushNode(store,blot_backend_layout::Tag.function,blot_backend_layout::word,owner);expected(store,function,true);
 let provider=pushNode(store,blot_backend_layout::Tag.state_provider,blot_backend_layout::word,blot_backend_layout::word,owner);expected(store,provider,true);
 let start=store.extra.len as u32;store.extra.append([blot_backend_layout::word,owner]);let product=pushNode(store,blot_backend_layout::Tag.product,start,2);expected(store,product,true);
 let nominal_start=store.extra.len as u32;store.extra.append([2 as u32,blot_backend_layout::word,owner]);let nominal=pushNode(store,blot_backend_layout::Tag.nominal,7,17,nominal_start);expected(store,nominal,true);
 let names_only=store.extra.len as u32;store.extra.append([0xffffffff as u32,blot_backend_layout::word,owner,blot_backend_layout::word]);let record=pushNode(store,blot_backend_layout::Tag.record,names_only,2);expected(store,record,false);
 let owning_field=store.extra.len as u32;store.extra.append([0xffffffff as u32,owner]);let record_owner=pushNode(store,blot_backend_layout::Tag.record,owning_field,1);expected(store,record_owner,true);
 let cycle=store.nodes.len as u32;let cycle_id=pushNode(store,blot_backend_layout::Tag.array,cycle);assert(cycle_id==cycle);let shared=store.extra.len as u32;store.extra.append([cycle,cycle]);let shared_root=pushNode(store,blot_backend_layout::Tag.product,shared,2);expected(store,shared_root,false);
 expected(store,store.nodes.len as u32,false,blot_error::Error.layout_limit);
 // Exactly4096 distinct nodes pass. One extra predecessor exhausts the same queue.
 let chain=store.nodes.len as u32;for index in 0..4095 {let id=pushNode(store,blot_backend_layout::Tag.array,chain+index as u32+1);assert(id==chain+index);}
 let tail=pushNode(store,blot_backend_layout::Tag.unsigned32);expected(store,chain,false);
 let over=pushNode(store,blot_backend_layout::Tag.array,chain);expected(store,over,false,blot_error::Error.layout_limit);
 store.nodes[tail]=blot_backend_layout::Node{tag:blot_backend_layout::Tag.owning,a:blot_backend_layout::word,..};expected(store,chain,true);expected(store,over,false,blot_error::Error.layout_limit);
 // Enqueue all children before visiting any: an early owning child cannot bypass overflow.
 let wide_start=store.extra.len as u32;store.extra.push(owner);for index in 0..4095 {store.extra.push(chain+index as u32);}let wide=pushNode(store,blot_backend_layout::Tag.product,wide_start,4096);expected(store,wide,false,blot_error::Error.layout_limit);
 context.calls++;return blot_error::Error.none;
}
fn main(){var context=Probe{};assert(blot_backend_layout::withStore(context,probe)==blot_error::Error.none && context.calls==1);print("layout owner traversal passed: branches, record names, cycles, shared nodes and exact4096 queue limit");}
