// Five independent pooled bridge memos retain capacity while snapshots own values.
import bootstrap_globals;
import driver.cli;
import driver.cli_workers;
import std;
import dictionary;
import backend.layout_bridge;
import backend.optimizer_buffers;
import reuse.code_artifacts;
import reuse.code_expectation;
import support.error;
import support.option;
type Words=blot_backend_optimizer_buffers::Words;
fn seed(table:Words&,id:u32,value:u32) {
 assert(blot_backend_layout_bridge::publish(table,id,value)==blot_error::Error.none);
 assert(table.len==id+1 && table.items.len==table.len);
 for index in id {assert(table.items[index]==blot_backend_layout_bridge::missing);}
 assert(!blot_backend_layout_bridge::lookup(table.items,id+1).present);
 assert(blot_backend_layout_bridge::lookup(table.items,id).value==value);
 assert(blot_backend_layout_bridge::publish(table,id,value+1)==blot_error::Error.none && table.items[id]==value+1);
}
fn main() {
 var nodes=blot_reuse_code_expectation::Nodes {..};var extra=blot_reuse_code_expectation::Ids {..};var next=blot_reuse_code_expectation::Ids {..};var buckets:dictionary<u64,u32> =dictionary<u64,u32>{};
 var partial,error=blot_reuse_code_expectation::init(nodes,extra,next,buckets);assert(error==blot_error::Error.none);
 var to=Words {..};var from=Words {..};var row_to=Words {..};var row_from=Words {..};var shapes=Words {..};
 let original_owner=partial.owner_id;assert(partial.reset()==blot_error::Error.none && partial.owner_id!=original_owner && partial.nodes.len==6 && partial.next.len==6 && partial.extra.len==0);
 var store=blot_backend_layout_bridge::init(blot_backend_layout_bridge::Tables {partial:partial,to:to,from:from,row_to:row_to,row_from:row_from,shapes:shapes,..});
 seed(to,9,100);seed(from,17,200);seed(row_to,25,300);seed(row_from,33,400);seed(shapes,41,500);
 assert(to.items[9]==101 && from.items[9]==blot_backend_layout_bridge::missing && row_to.items[17]==blot_backend_layout_bridge::missing);
 var snapshot=blot_reuse_code_artifacts::captureBridge(store);
 assert(snapshot.nodes.len==6 && snapshot.extra.len==0);
 assert(snapshot.to.len==10 && snapshot.from.len==18 && snapshot.row_to.len==26 && snapshot.row_from.len==34 && snapshot.shapes.len==42);
 assert(snapshot.to[9]==101 && snapshot.from[17]==201 && snapshot.row_to[25]==301 && snapshot.row_from[33]==401 && snapshot.shapes[41]==501);
 let to_capacity=to.storage.len;let from_capacity=from.storage.len;let row_to_capacity=row_to.storage.len;let row_from_capacity=row_from.storage.len;let shapes_capacity=shapes.storage.len;
 // The existing pooled capacity guard rejects impossible growth before allocation or publication.
 assert(to.ensure(0x5555555555555541)==blot_error::Error.out_of_memory && to.len==10 && to.items[9]==101);
 store.deinit();assert(to.len==0 && from.len==0 && row_to.len==0 && row_from.len==0 && shapes.len==0);
 assert(to.storage.len==to_capacity && from.storage.len==from_capacity && row_to.storage.len==row_to_capacity && row_from.storage.len==row_from_capacity && shapes.storage.len==shapes_capacity);
 seed(to,9,600);seed(from,17,700);seed(row_to,25,800);seed(row_from,33,900);seed(shapes,41,1000);
 assert(to.storage.len==to_capacity && from.storage.len==from_capacity && row_to.storage.len==row_to_capacity && row_from.storage.len==row_from_capacity && shapes.storage.len==shapes_capacity);
 assert(snapshot.nodes.len==6 && snapshot.to[9]==101 && snapshot.from[17]==201 && snapshot.row_to[25]==301 && snapshot.row_from[33]==401 && snapshot.shapes[41]==501);
 assert(snapshot.to[0]==blot_backend_layout_bridge::missing && snapshot.shapes[40]==blot_backend_layout_bridge::missing);
 snapshot.deinit();store.deinit();to.deinit();from.deinit();row_to.deinit();row_from.deinit();shapes.deinit();nodes.deinit();extra.deinit();next.deinit();
 print("layout bridge words passed: independent sparse memos, overwrite, failure guard, clear/reuse and owned snapshots");
}
