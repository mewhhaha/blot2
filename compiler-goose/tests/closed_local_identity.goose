// Closed-local scans return original module headers and preserve fallback lookup.
import bootstrap_globals;
import driver.cli;
import driver.cli_workers;
import std;
import eval.closed_local_value;
import support.error;
fn main() {
 var types:blot_check_types::Node[8]=default<blot_check_types::Node[8]>();types[0].tag=blot_check_types::Tag.absent;types[1].tag=blot_check_types::Tag.unit;types[2].tag=blot_check_types::Tag.boolean;types[3].tag=blot_check_types::Tag.unsigned32;types[4].tag=blot_check_types::Tag.floating32;types[5].tag=blot_check_types::Tag.never;types[6]=blot_check_types::Node{tag:blot_check_types::Tag.array,a:3,..};types[7]=blot_check_types::Node{tag:blot_check_types::Tag.function,a:3,b:3,c:0,..};
 var rows:blot_check_effects::Row[1]=default<blot_check_effects::Row[1]>();
 var nodes:blot_check_core::Node[3]=default<blot_check_core::Node[3]>();nodes[1]=blot_check_core::Node{tag:blot_check_core::Tag.constant,ty:3,..};nodes[2]=blot_check_core::Node{tag:blot_check_core::Tag.call,ty:3,a:0,b:0,c:1,..};
 var extra:u32[1]=[1 as u32];var bindings:blot_check_core::Binding[3]=default<blot_check_core::Binding[3]>();bindings[1].kind=blot_reuse_principal_interface::Kind.global;bindings[1].ty=7;bindings[1].body_id=1;bindings[2].kind=blot_reuse_principal_interface::Kind.parameter;bindings[2].ty=3;
 var bodies:blot_check_core::Body[2]=default<blot_check_core::Body[2]>();bodies[1]=blot_check_core::Body{binding:1,root:1,parameters:blot_check_core::List{0,1,..},is_function:true,..};
 var parameters:blot_check_core::Parameter[1]=[blot_check_core::Parameter{binding:2,ty:3,..}];var calls:blot_check_core::CallInfo[1]=[blot_check_core::CallInfo{target:blot_check_core::BindingRef{7,1,..},callee_type:7,..}];
 var modules:blot_check_core::Module[3]=default<blot_check_core::Module[3]>();
 modules[0]=blot_check_core::Module{unit:7,types:blot_check_core::Types{nodes:types[..],extra:default<const u32[:]>(),effects:blot_check_core::EffectRows{rows:rows[..],..},..},nodes:nodes[..],extra:extra[..],bindings:bindings[..],bodies:bodies[..],parameters:parameters[..],calls:calls[..],..};modules[1]=modules[0];modules[1].unit=0;modules[2]=modules[0];
 var scan=blot_eval_closed_local_value::Scan{units:modules[..],..};
 var retained:const blot_check_core::Module? =null;
 {let found .=scan.unit(7);assert(found .==modules[0]);retained .=found;}
 assert(retained .==modules[0]);let fallback .=scan.unit(2);assert(fallback!=null);assert(fallback .==modules[1] && fallback.unit==0);
 assert(scan.unit(0)==null && scan.unit(1)==null && scan.unit(99)==null);
 assert(blot_eval_closed_local_value::dataShape(modules[..],7,3) && blot_eval_closed_local_value::dataShape(modules[..],2,6) && blot_eval_closed_local_value::dataShape(modules[..],7,7));
 assert(!blot_eval_closed_local_value::dataShape(modules[..],99,3) && !blot_eval_closed_local_value::dataShape(modules[..],7,0));
 let proof,proven=blot_eval_closed_local_value::analyze(modules[..],7,1);assert(proven && proof.len==0);
 let proof,proven=blot_eval_closed_local_value::analyze(modules[..],2,1);assert(proven && proof.len==0);
 let proof,proven=blot_eval_closed_local_value::analyze(modules[..],7,2);assert(proven && proof.len==1 && proof.dependencies[0].unit==7 && proof.dependencies[0].binding==1);
 let proof,proven=blot_eval_closed_local_value::analyze(modules[..],99,1);assert(!proven && proof.len==0);
 print("closed local module identity passed: original/fallback/missing/first match, shape and call dependencies");
}
