// Optional observation records actual borrowed reads without changing ownership decisions.
import bootstrap_globals;
import driver.cli;
import driver.cli_workers;
import std;
import backend.owned_arrays;
import support.error;
fn main() {
 var nodes:blot_check_core::Node[6]=default<blot_check_core::Node[6]>();
 nodes[1]=blot_check_core::Node{tag:blot_check_core::Tag.reference,ty:3,a:0,..};nodes[2]=blot_check_core::Node{tag:blot_check_core::Tag.array_op,ty:3,a:0,b:1,c:0,..};nodes[3]=blot_check_core::Node{tag:blot_check_core::Tag.closure,a:0,..};nodes[4]=blot_check_core::Node{tag:blot_check_core::Tag.constant,ty:3,..};nodes[5]=blot_check_core::Node{tag:blot_check_core::Tag.array_op,a:2,b:2,c:4,..};
 var extra:u32[4]=[1 as u32,1 as u32,4 as u32,3 as u32];var references:blot_check_core::BindingRef[1]=[blot_check_core::BindingRef{0,1,..}];
 var closures:blot_check_core::ClosureInfo[1]=[blot_check_core::ClosureInfo{body:2,parameter:default<blot_check_core::Parameter>(),captures:blot_check_core::List{1,1,..},..}];
 var modules:blot_check_core::Module[1]=[blot_check_core::Module{unit:1,nodes:nodes[..],extra:extra[..],references:references[..],closures:closures[..],..}];
 var borrows=blot_backend_owned_arrays::Borrows{units:modules[..],..};
 var absent=blot_backend_owned_arrays::Walk{unit:1,binding:1,depth:0,..};absent.see(42);assert(absent.seen==null && absent.visit(borrows,5) && !absent.parts);
 var seen:u32[>..<]=[];var present=blot_backend_owned_arrays::Walk{unit:1,binding:1,depth:0,seen:seen,..};
 present.see(11);present.see(11);present.see(0);assert(seen.len==3 && seen[0]==11 && seen[1]==11 && seen[2]==0);
 assert(present.captures(borrows,3) && !present.visit(borrows,3) && seen.len==3);
 assert(present.visit(borrows,5) && !present.parts && seen.len==4 && seen[3]==1);
 assert(present.visit(borrows,5) && !present.parts && seen.len==5 && seen[4]==1);
 var reads:u32[6]=default<u32[6]>();let captured=borrows.captured(1,3,1,19,reads[..]);assert(captured.present && captured.value==blot_backend_owned_arrays::Use.scalars && reads[1]==19);
 let observed .=present.seen;assert(observed && observed .==seen);
 borrows.deinit();print("owned array seen passed: absent/present, duplicate order and captured borrowed read");
}
