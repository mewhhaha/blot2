// Real preparation success/error paths over a pinned nonempty typed Core catalog.
import bootstrap_globals;
import driver.cli;
import driver.cli_workers;
import std;
import backend.backend_emission;
import backend.substitution_buffers;
import backend.resolved_body;
import driver.compile_workspace;
import reuse.dependency_payload;
import reuse.dependency_owned_headers;
import check.types;
import check.typed_staging;
import check.core;
import runtime.runtime_cleanup;
import support.native;
import support.error;
type Maps=blot_backend_substitution_buffers::Mappings;
type Rows=blot_backend_substitution_buffers::Rows;
fn prepare(frame:blot_compile_workspace::Frame,units:const blot_check_core::Module[:],pin:blot_reuse_dependency_payload::Owner) {
 let workspace .=frame.borrow();assert(workspace);let owners=[pin];
 assert(blot_backend_core_backend::pinWorkspaceInputs(workspace,units,pin,owners[..],default<const blot_reuse_dependency_payload::Owner[:]>())==blot_error::Error.none);
 assert(blot_backend_core_backend::resetGenerator(workspace,null)==blot_error::Error.none);
 let generator .=workspace.generator;
 let function,error=generator.module.addFunction(default<const blot_backend_runtime_ir::ValueType[:]>(),blot_backend_runtime_ir::VT_none);assert(error==blot_error::Error.none);
 var maps=Maps{};var rows=Rows{};
 assert(maps.push(blot_backend_layout::Mapping{variable:blot_check_types::u32_type,layout:blot_backend_layout::word,instance:blot_check_types::NominalIdentity{unit:0,decl:1}})==blot_error::Error.none);
 assert(rows.push(blot_backend_layout::RowMapping{variable:1,row:blot_backend_layout::unknown_row})==blot_error::Error.none);
 let cleanups,error=blot_runtime_runtime_cleanup::initPooled();assert(error==blot_error::Error.none);
 var parent=blot_backend_backend_emission::Owner{frame:frame,unit_id:1,function_id:function,mapping_read:blot_backend_backend_emission::bufferMappings(maps),row_read:blot_backend_backend_emission::bufferRows(rows),cleanups:cleanups,..};
 let parent_map=parent.mapping_read;let parent_row=parent.row_read;let parent_mark=parent.cleanups.mark();let previous_stage=generator.evaluator.inference_stage;
 let body,error=blot_backend_backend_emission::prepareMapped(parent,1,0,false,parent.mappings(),parent.row_mappings(),blot_support::none<blot_backend_backend_emission::InstanceRead>());
 assert(error==blot_error::Error.none && body!=0 && generator.evaluator.inference_stage==previous_stage && parent.cleanups.mark()==parent_mark);
 assert(parent.mapping_read==parent_map && parent.row_read==parent_row && parent.mappings()[0].layout==blot_backend_layout::word);
 let child_cleanups,error=blot_runtime_runtime_cleanup::initPooled(parent.cleanups);assert(error==blot_error::Error.none);
 var child=blot_backend_backend_emission::Owner{preparation_depth:1,frame:frame,unit_id:1,function_id:function,mapping_read:blot_backend_backend_emission::bodyMappings(body),row_read:blot_backend_backend_emission::bodyRows(body),cleanups:child_cleanups,..};
 let child_map=child.mapping_read;let child_row=child.row_read;let child_mark=child.cleanups.mark();let before=blot_backend_resolved_body::headers.len;
 let outer_stage=generator.evaluator.enterInferenceStage(blot_work_counters::InferenceStage.specialization);
 let rejected,error=blot_backend_backend_emission::prepareMapped(child,2,0,false,child.mappings(),child.row_mappings(),blot_support::none<blot_backend_backend_emission::InstanceRead>());
 assert(error!=blot_error::Error.none && rejected==0 && generator.diagnostic.present && generator.diagnostic.value.code==blot_check_diagnostic_code::Code.stage_unavailable);
 assert(generator.evaluator.inference_stage==blot_work_counters::InferenceStage.specialization && child.cleanups.mark()==child_mark && parent.cleanups.mark()==parent_mark);
 assert(child.mapping_read==child_map && child.row_read==child_row && child.mappings()[0].variable==blot_check_types::u32_type && child.row_mappings()[0].row==blot_backend_layout::unknown_row);
 assert(blot_backend_resolved_body::headers.len==before+1 && !blot_backend_resolved_body::headers[before].active && blot_backend_resolved_body::headers[body-1].active);
 outer_stage.deinit();assert(generator.evaluator.inference_stage==previous_stage);child.deinit();parent.deinit();
 blot_backend_resolved_body::release(body);assert(!child_map.valid() && !child_row.valid());maps.deinit();rows.deinit();
}
fn main() {
 var pin,error=blot_reuse_dependency_payload::init();assert(error==blot_error::Error.none);
 var types,error=blot_check_types::init();assert(error==blot_error::Error.none);
 let code_type,error=blot_check_typed_staging::code(types,blot_check_types::u32_type,0);assert(error==blot_error::Error.none);
 let type_nodes,error=pin.copy(types.nodes.items);assert(error==blot_error::Error.none);let type_extra,error=pin.copy(types.extra.items);assert(error==blot_error::Error.none);
 let effect_rows,error=pin.copy(types.effects.rows.items);assert(error==blot_error::Error.none);let effect_labels,error=pin.copy(types.effects.labels.items);assert(error==blot_error::Error.none);let operations,error=pin.copy(types.operations.items);assert(error==blot_error::Error.none);types.deinit();
 let nodes,error=pin.copy([blot_check_core::Node{tag:blot_check_core::Tag.invalid,..},blot_check_core::Node{tag:blot_check_core::Tag.constant,ty:blot_check_types::u32_type,a:7,..},blot_check_core::Node{tag:blot_check_core::Tag.staging,ty:code_type,a:1,c:0,..}]);assert(error==blot_error::Error.none);
 let spans,error=pin.copy([blot_check_core::Span{..};3]);assert(error==blot_error::Error.none);
 let units,error=blot_reuse_dependency_payload::alloc<blot_check_core::Module>(pin,1);assert(error==blot_error::Error.none);
 units[0]=blot_reuse_dependency_owned_headers::canonical(pin,blot_check_core::Module{unit:1,types:blot_check_core::Types{nodes:type_nodes,extra:type_extra,effects:blot_check_core::EffectRows{rows:effect_rows,labels:effect_labels,..},operations:operations,..},nodes:nodes,spans:spans,..});
 var frame,error=blot_compile_workspace::create(blot_native::fresh_owner_id());assert(error==blot_error::Error.none);prepare(frame,units,pin);assert(frame.release()==blot_error::Error.none);pin.deinit();
 print("emission preparation passed: real pinned Core, nested owners, nonempty selections and error/stage/cleanup restoration");
}
