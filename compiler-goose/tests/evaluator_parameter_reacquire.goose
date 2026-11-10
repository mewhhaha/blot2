// Real two-parameter invocation and curried application preserve metadata/order/restoration.
import bootstrap_globals;
import driver.cli;
import driver.cli_workers;
import std;
import eval.core_eval;
import check.types;
import check.core;
import reuse.dependency_payload;
import reuse.dependency_owned_headers;
import support.native;
import support.error;
fn result(session:blot_eval_core_eval::Session&,flow:blot_eval_core_eval::Flow) {
 assert(blot_eval_core_eval::isValue(flow));let value=blot_eval_core_eval::flowValue(flow);let fields=session.valueChildren(value);assert(fields.len==2);
 assert(session.valueScalar(fields[0]).value.bits==17 && session.valueScalar(fields[1]).value.bits==29);
}
fn invoke(session:blot_eval_core_eval::Session&) {
 let first,error=session.makeScalar(0,3,blot_eval_core_eval::Value{blot_backend_runtime_ir::SC_u32,17});assert(error==blot_error::Error.none);
 let second,error=session.makeScalar(0,3,blot_eval_core_eval::Value{blot_backend_runtime_ir::SC_u32,29});assert(error==blot_error::Error.none);
 let origin=session.specialization_origin;let generator_origin=session.generator_origin;let depth=session.call_depth;
 let direct,error=session.invokeNamedWithSeeds(blot_eval_core_eval::Target{0,1},[first,second],0,3,0,0,default<const blot_eval_type_evidence::Mapping[:]>(),default<const blot_eval_type_evidence::RowMapping[:]>());assert(error==blot_error::Error.none);result(session,direct);
 assert(session.call_depth==depth && session.specialization_origin==origin && session.generator_origin==generator_origin);
 let wrapped,error=session.invokeNamed(blot_eval_core_eval::Target{0,1},[first,second],0,3,0,0);assert(error==blot_error::Error.none);result(session,wrapped);
 let closure,error=session.constant(blot_eval_core_eval::Target{0,1});assert(error==blot_error::Error.none);
 let partial,error=session.applyValue(0,3,closure,first,0);assert(error==blot_error::Error.none && blot_eval_core_eval::isValue(partial));
 let completed,error=session.applyValue(0,3,blot_eval_core_eval::flowValue(partial),second,0);assert(error==blot_error::Error.none);result(session,completed);
 let wrong,error=session.makeScalar(0,3,blot_eval_core_eval::Value{blot_backend_runtime_ir::SC_bool,1});assert(error==blot_error::Error.none);
 let rejected,error=session.invokeNamedWithSeeds(blot_eval_core_eval::Target{0,1},[first,wrong],0,3,0,0,default<const blot_eval_type_evidence::Mapping[:]>(),default<const blot_eval_type_evidence::RowMapping[:]>());assert(error!=blot_error::Error.none && session.diagnostic.present);
 assert(session.call_depth==depth && session.specialization_origin==origin && session.generator_origin==generator_origin);session.discardDiagnostic();
 let again,error=session.invokeNamedWithSeeds(blot_eval_core_eval::Target{0,1},[first,second],0,3,0,0,default<const blot_eval_type_evidence::Mapping[:]>(),default<const blot_eval_type_evidence::RowMapping[:]>());assert(error==blot_error::Error.none);result(session,again);
}
fn main() {
 var pin,error=blot_reuse_dependency_payload::init();assert(error==blot_error::Error.none);var types,error=blot_check_types::init();assert(error==blot_error::Error.none);
 let pair,error=types.product([blot_check_types::u32_type,blot_check_types::u32_type]);assert(error==blot_error::Error.none);let suffix,error=types.function(blot_check_types::u32_type,pair);assert(error==blot_error::Error.none);let arrow,error=types.function(blot_check_types::u32_type,suffix);assert(error==blot_error::Error.none);
 let type_nodes,error=pin.copy(types.nodes.items);assert(error==blot_error::Error.none);let type_extra,error=pin.copy(types.extra.items);assert(error==blot_error::Error.none);let effect_rows,error=pin.copy(types.effects.rows.items);assert(error==blot_error::Error.none);let effect_labels,error=pin.copy(types.effects.labels.items);assert(error==blot_error::Error.none);let operations,error=pin.copy(types.operations.items);assert(error==blot_error::Error.none);types.deinit();
 let nodes,error=pin.copy([blot_check_core::Node{tag:blot_check_core::Tag.invalid,..},blot_check_core::Node{tag:blot_check_core::Tag.reference,ty:blot_check_types::u32_type,a:0,..},blot_check_core::Node{tag:blot_check_core::Tag.reference,ty:blot_check_types::u32_type,a:1,..},blot_check_core::Node{tag:blot_check_core::Tag.product,ty:pair,a:0,b:2,..}]);assert(error==blot_error::Error.none);
 let spans,error=pin.copy([blot_check_core::Span{..};4]);assert(error==blot_error::Error.none);let extra,error=pin.copy([1 as u32,2 as u32]);assert(error==blot_error::Error.none);
 let bindings,error=blot_reuse_dependency_payload::alloc<blot_check_core::Binding>(pin,4);assert(error==blot_error::Error.none);for &binding in bindings {binding=default<blot_check_core::Binding>();}bindings[1].kind=blot_reuse_principal_interface::Kind.global;bindings[1].ty=arrow;bindings[1].scheme=blot_check_types::Scheme{root:arrow,..};bindings[1].body_id=1;bindings[2].kind=blot_reuse_principal_interface::Kind.parameter;bindings[2].ty=blot_check_types::u32_type;bindings[3].kind=blot_reuse_principal_interface::Kind.parameter;bindings[3].ty=blot_check_types::u32_type;
 let bodies,error=pin.copy([blot_check_core::Body{..},blot_check_core::Body{binding:1,root:3,parameters:blot_check_core::List{0,2,..},scheme:blot_check_types::Scheme{root:arrow,..},is_function:true,..}]);assert(error==blot_error::Error.none);
 let parameters,error=pin.copy([blot_check_core::Parameter{binding:2,ty:blot_check_types::u32_type,..},blot_check_core::Parameter{binding:3,ty:blot_check_types::u32_type,..}]);assert(error==blot_error::Error.none);let references,error=pin.copy([blot_check_core::BindingRef{0,2},blot_check_core::BindingRef{0,3}]);assert(error==blot_error::Error.none);
 let units,error=blot_reuse_dependency_payload::alloc<blot_check_core::Module>(pin,1);assert(error==blot_error::Error.none);units[0]=blot_reuse_dependency_owned_headers::canonical(pin,blot_check_core::Module{unit:1,types:blot_check_core::Types{nodes:type_nodes,extra:type_extra,effects:blot_check_core::EffectRows{rows:effect_rows,labels:effect_labels,..},operations:operations,..},nodes:nodes,spans:spans,extra:extra,bindings:bindings,bodies:bodies,parameters:parameters,references:references,..});
 let session,error=blot_eval_core_eval::initOwnedSession(pin.mutable(units),blot_native::fresh_owner_id());assert(error==blot_error::Error.none && session);invoke(session);blot_eval_core_eval::deinitOwnedSession(session);pin.deinit();print("evaluator parameter metadata passed: two arguments, curried apply, order and error/origin restoration");
}
