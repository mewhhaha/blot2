// A speculative field miss never creates or replaces a user diagnostic.
import bootstrap_globals;
import driver.cli;
import driver.cli_workers;
import std;
import eval.core_eval;
import eval.eval_values;
import check.types;
import reuse.dependency_payload;
import reuse.dependency_owned_headers;
import support.native;
import support.error;
fn inspect(session:blot_eval_core_eval::Session&) {
 let first,error=session.storage.scalar(blot_eval_core_eval::Value{blot_backend_runtime_ir::SC_u32,17});assert(error==blot_error::Error.none);let second,error=session.storage.scalar(blot_eval_core_eval::Value{blot_backend_runtime_ir::SC_u32,29});assert(error==blot_error::Error.none);
 let record,error=session.storage.aggregate(blot_eval_eval_values::ValueKind.record,0,0,[first,second]);assert(error==blot_error::Error.none);let shape=session.storage.saveRecordShape([11 as u32,17 as u32]);session.storage.value_records.items[record]=shape;
 let found,reason=session.probeGenericField(0,17,record);assert(!reason.present && found.container==record && found.field==1 && !found.wrapped && !session.diagnostic.present);
 let missing,reason=session.probeGenericField(0,23,record);assert(reason.present && reason.value==blot_check_diagnostic_code::Code.unsupported && !session.diagnostic.present);
 let unsupported,reason=session.probeGenericField(0,11,first);assert(reason.present && reason.value==blot_check_diagnostic_code::Code.unsupported && !session.diagnostic.present);
 let family=(1 as u64)<<32|9;let wrapped,error=session.storage.aggregate(blot_eval_eval_values::ValueKind.nominal,family,3,[record]);assert(error==blot_error::Error.none);session.field_locations.insert(blot_eval_core_eval::FieldKey{family,3,17},blot_eval_core_eval::FieldLocation{1,2});
 let nominal,reason=session.probeGenericField(0,17,wrapped);assert(!reason.present && nominal.container==record && nominal.field==1 && nominal.wrapped);
 let hidden_family=(2 as u64)<<32|(blot_check_types::opaque_name_bit|9) as u64;let hidden,error=session.storage.aggregate(blot_eval_eval_values::ValueKind.nominal,hidden_family,0,[record]);assert(error==blot_error::Error.none);
 let hidden_field,reason=session.probeGenericField(0,17,hidden);assert(reason.present && reason.value==blot_check_diagnostic_code::Code.missing_field && !session.diagnostic.present);
 let prior=blot_support::Option<blot_eval_core_eval::Diagnostic>{true,blot_eval_core_eval::Diagnostic{unit:1,span:blot_check_core::Span{7,19},code:blot_check_diagnostic_code::Code.const_panic,..}};assert(blot_eval_core_eval::restoreDiagnostic(session,prior,"preserved detail")==blot_error::Error.none);let message_length=session.owned_diagnostic_message.len;
 let miss,reason=session.probeGenericField(0,23,record);assert(reason.present && session.diagnostic.value.code==blot_check_diagnostic_code::Code.const_panic && session.diagnostic.value.detail=="preserved detail" && session.owned_diagnostic_message.len==message_length);
 let actual,error=session.genericField(0,1,17,record);assert(error==blot_error::Error.none && actual.field==1 && session.diagnostic.value.detail=="preserved detail");let miss,error=session.genericField(0,1,23,record);assert(error==blot_error::Error.declined && session.diagnostic.value.code==blot_check_diagnostic_code::Code.const_panic && session.diagnostic.value.detail=="preserved detail");
 session.discardDiagnostic();let miss,error=session.genericField(0,1,23,record);assert(error==blot_error::Error.declined && session.diagnostic.value.code==blot_check_diagnostic_code::Code.unsupported && session.diagnostic.value.span==blot_check_core::Span{7,19});
 session.discardDiagnostic();let miss,error=session.genericField(0,1,17,hidden);assert(error==blot_error::Error.declined && session.diagnostic.value.code==blot_check_diagnostic_code::Code.missing_field);session.discardDiagnostic();
}
fn main() {
 var pin,error=blot_reuse_dependency_payload::init();assert(error==blot_error::Error.none);var types,error=blot_check_types::init();assert(error==blot_error::Error.none);let type_nodes,error=pin.copy(types.nodes.items);assert(error==blot_error::Error.none);let type_extra,error=pin.copy(types.extra.items);assert(error==blot_error::Error.none);let effect_rows,error=pin.copy(types.effects.rows.items);assert(error==blot_error::Error.none);let effect_labels,error=pin.copy(types.effects.labels.items);assert(error==blot_error::Error.none);let operations,error=pin.copy(types.operations.items);assert(error==blot_error::Error.none);types.deinit();
 let nodes,error=pin.copy([blot_check_core::Node{tag:blot_check_core::Tag.invalid,..},blot_check_core::Node{tag:blot_check_core::Tag.constant,ty:blot_check_types::u32_type,a:17,..}]);assert(error==blot_error::Error.none);let spans,error=pin.copy([blot_check_core::Span{..},blot_check_core::Span{7,19}]);assert(error==blot_error::Error.none);
 let units,error=blot_reuse_dependency_payload::alloc<blot_check_core::Module>(pin,1);assert(error==blot_error::Error.none);units[0]=blot_reuse_dependency_owned_headers::canonical(pin,blot_check_core::Module{unit:1,types:blot_check_core::Types{nodes:type_nodes,extra:type_extra,effects:blot_check_core::EffectRows{rows:effect_rows,labels:effect_labels,..},operations:operations,..},nodes:nodes,spans:spans,..});
 let session,error=blot_eval_core_eval::initOwnedSession(pin.mutable(units),blot_native::fresh_owner_id());assert(error==blot_error::Error.none && session);inspect(session);blot_eval_core_eval::deinitOwnedSession(session);pin.deinit();print("generic field probe passed: records, nominal wrapping, exact reasons and preserved prior diagnostic");
}
