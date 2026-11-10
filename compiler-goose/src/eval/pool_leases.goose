// Typed reusable runs retain only the blocks named by live artifact owners.
namespace blot_eval_pool_leases;
import backend.layout;
import backend.provider_chain;
import backend.runtime_identity;
import check.core;
import check.effect_evidence;
import check.staging_origins;
import eval.eval_values;
import eval.implementation_evidence;
import eval.type_evidence;
import reuse.code_artifacts;
import support.error;
import support.option;
import support.structural_adapters;

import support.structural;
type Error=blot_error::Error;
enum Field { identity_bytes,identity_symbols,identity_owners,layout_nodes,layout_extra,layout_universal_dictionaries,layout_operations,layout_arguments,layout_rows,layout_labels,values,children,closures,value_evidence,type_mappings,row_mappings,evidence_nodes,evidence_extra,evidence_quantifier_goals,evidence_quantifier_obligations,evidence_operations,evidence_arguments,evidence_rows,evidence_labels,value_records,record_layouts,field_names,implementation_proofs,implementation_arguments,implementation_members,implementation_edges,captures,field_locations,functions,serialized,runtime_globals,runtime_order,binding_offsets,node_offsets,slots,visited_nodes,provider_frames,provider_cells,request_cells,request_handlers,break_values,operation_relocations,code_origins }
fn fieldCode(field: Field) -> u32 { match field { identity_bytes=>0,identity_symbols=>1,identity_owners=>2,layout_nodes=>3,layout_extra=>4,layout_universal_dictionaries=>5,layout_operations=>6,layout_arguments=>7,layout_rows=>8,layout_labels=>9,values=>10,children=>11,closures=>12,value_evidence=>13,type_mappings=>14,row_mappings=>15,evidence_nodes=>16,evidence_extra=>17,evidence_quantifier_goals=>18,evidence_quantifier_obligations=>19,evidence_operations=>20,evidence_arguments=>21,evidence_rows=>22,evidence_labels=>23,value_records=>24,record_layouts=>25,field_names=>26,implementation_proofs=>27,implementation_arguments=>28,implementation_members=>29,implementation_edges=>30,captures=>31,field_locations=>32,functions=>33,serialized=>34,runtime_globals=>35,runtime_order=>36,binding_offsets=>37,node_offsets=>38,slots=>39,visited_nodes=>40,provider_frames=>41,provider_cells=>42,request_cells=>43,request_handlers=>44,break_values=>45,operation_relocations=>46,code_origins=>47 } }
let field_count: i64=48;
struct LeaseRef { index: u32=0,generation: u64=0 }
struct LeaseMeta { references: u64=0,field: Field=Field.identity_bytes,start: i64=0,len: i64=0,generation: u64=0,live: bool=false }
struct Leases { values: LeaseRef[48]=[LeaseRef {};48] }
struct Stats { shared_fields: i64=0,shared_bytes: i64=0,copied_fields: i64=0,copied_bytes: i64=0 }
struct Builder { previous: const Leases?=null,leases: Leases=Leases {},stats: Stats=Stats {} }
reusable var lease_meta: LeaseMeta[>..]=[];
var next_generation: u64=1;
fn valid(ref: LeaseRef) -> bool { return ref.index!=0&&ref.index<=lease_meta.len&&lease_meta[ref.index-1].live&&lease_meta[ref.index-1].generation==ref.generation; }
fn get(leases: const Leases&,field: Field) -> LeaseRef { return leases.values[fieldCode(field)]; }
fn set(leases: Leases&,field: Field,ref: LeaseRef) { leases.values[fieldCode(field)]=ref; }
fn retain(ref: LeaseRef) -> Error { if !valid(ref) { return blot_error::Error.invalid_artifact; } if lease_meta[ref.index-1].references==0xffffffffffffffff { return blot_error::Error.artifact_limit; } lease_meta[ref.index-1].references++; return blot_error::Error.none; }
fn create(field: Field,start: i64,len: i64) -> LeaseRef,Error {
 if next_generation==0xffffffffffffffff { return LeaseRef {},blot_error::Error.artifact_limit; }
 let generation=next_generation; next_generation++; let index=lease_meta.alloc_index(LeaseMeta {1,field,start,len,generation,true}); return LeaseRef {(index+1) as u32,generation},blot_error::Error.none;
}
reusable[] var pool_identity_bytes: u8[>..]=[];
reusable[] var pool_identity_symbols: blot_backend_runtime_identity::Name[>..]=[];
reusable[] var pool_identity_owners: blot_backend_runtime_identity::Name[>..]=[];
reusable[] var pool_layout_nodes: blot_backend_layout::Node[>..]=[];
reusable[] var pool_layout_extra: u32[>..]=[];
reusable[] var pool_layout_universal_dictionaries: blot_backend_layout::UniversalDictionaries[>..]=[];
reusable[] var pool_layout_operations: blot_check_effect_evidence::Operation[>..]=[];
reusable[] var pool_layout_arguments: u32[>..]=[];
reusable[] var pool_layout_rows: blot_check_effect_evidence::Row[>..]=[];
reusable[] var pool_layout_labels: u32[>..]=[];
reusable[] var pool_values: blot_eval_eval_values::ValueInfo[>..]=[];
reusable[] var pool_children: u32[>..]=[];
reusable[] var pool_closures: blot_eval_eval_values::ClosureValue[>..]=[];
reusable[] var pool_value_evidence: u32[>..]=[];
reusable[] var pool_type_mappings: blot_eval_type_evidence::Mapping[>..]=[];
reusable[] var pool_row_mappings: blot_eval_type_evidence::RowMapping[>..]=[];
reusable[] var pool_evidence_nodes: blot_eval_type_evidence::Node[>..]=[];
reusable[] var pool_evidence_extra: u32[>..]=[];
reusable[] var pool_evidence_quantifier_goals: blot_eval_type_evidence::QuantifierGoals[>..]=[];
reusable[] var pool_evidence_quantifier_obligations: blot_eval_type_evidence::Goal[>..]=[];
reusable[] var pool_evidence_operations: blot_check_effect_evidence::Operation[>..]=[];
reusable[] var pool_evidence_arguments: u32[>..]=[];
reusable[] var pool_evidence_rows: blot_check_effect_evidence::Row[>..]=[];
reusable[] var pool_evidence_labels: u32[>..]=[];
reusable[] var pool_value_records: u32[>..]=[];
reusable[] var pool_record_layouts: blot_check_core::List[>..]=[];
reusable[] var pool_field_names: u32[>..]=[];
reusable[] var pool_implementation_proofs: blot_eval_implementation_evidence::Proof[>..]=[];
reusable[] var pool_implementation_arguments: u32[>..]=[];
reusable[] var pool_implementation_members: blot_eval_implementation_evidence::Member[>..]=[];
reusable[] var pool_implementation_edges: u32[>..]=[];
reusable[] var pool_captures: blot_reuse_code_artifacts::CapturedTemplate[>..]=[];
reusable[] var pool_field_locations: blot_reuse_code_artifacts::FieldLocation[>..]=[];
reusable[] var pool_functions: blot_reuse_code_artifacts::Function[>..]=[];
reusable[] var pool_serialized: blot_reuse_code_artifacts::Serialized[>..]=[];
reusable[] var pool_runtime_globals: blot_reuse_code_artifacts::RuntimeGlobal[>..]=[];
reusable[] var pool_runtime_order: u32[>..]=[];
reusable[] var pool_binding_offsets: i64[>..]=[];
reusable[] var pool_node_offsets: i64[>..]=[];
reusable[] var pool_slots: blot_reuse_code_artifacts::Slot[>..]=[];
reusable[] var pool_visited_nodes: bool[>..]=[];
reusable[] var pool_provider_frames: blot_backend_provider_chain::Frame[>..]=[];
reusable[] var pool_provider_cells: blot_backend_provider_chain::Cell[>..]=[];
reusable[] var pool_request_cells: blot_reuse_code_artifacts::RequestCell[>..]=[];
reusable[] var pool_request_handlers: blot_reuse_code_artifacts::RequestHandler[>..]=[];
reusable[] var pool_break_values: u32[>..]=[];
reusable[] var pool_operation_relocations: blot_reuse_code_artifacts::OperationRelocation[>..]=[];
reusable[] var pool_code_origins: blot_check_staging_origins::Record[>..]=[];
fn release(ref: LeaseRef) -> Error {
 if !valid(ref) { return blot_error::Error.invalid_artifact; } let index=ref.index-1;
 if lease_meta[index].references==0 { return blot_error::Error.invalid_artifact; }
 lease_meta[index].references--; if lease_meta[index].references!=0 { return blot_error::Error.none; }
 let meta=lease_meta[index];
 match meta.field {
  identity_bytes=>{ pool_identity_bytes.free_slice(pool_identity_bytes[meta.start..meta.start+meta.len]); },
  identity_symbols=>{ pool_identity_symbols.free_slice(pool_identity_symbols[meta.start..meta.start+meta.len]); },
  identity_owners=>{ pool_identity_owners.free_slice(pool_identity_owners[meta.start..meta.start+meta.len]); },
  layout_nodes=>{ pool_layout_nodes.free_slice(pool_layout_nodes[meta.start..meta.start+meta.len]); },
  layout_extra=>{ pool_layout_extra.free_slice(pool_layout_extra[meta.start..meta.start+meta.len]); },
  layout_universal_dictionaries=>{ pool_layout_universal_dictionaries.free_slice(pool_layout_universal_dictionaries[meta.start..meta.start+meta.len]); },
  layout_operations=>{ pool_layout_operations.free_slice(pool_layout_operations[meta.start..meta.start+meta.len]); },
  layout_arguments=>{ pool_layout_arguments.free_slice(pool_layout_arguments[meta.start..meta.start+meta.len]); },
  layout_rows=>{ pool_layout_rows.free_slice(pool_layout_rows[meta.start..meta.start+meta.len]); },
  layout_labels=>{ pool_layout_labels.free_slice(pool_layout_labels[meta.start..meta.start+meta.len]); },
  values=>{ pool_values.free_slice(pool_values[meta.start..meta.start+meta.len]); },
  children=>{ pool_children.free_slice(pool_children[meta.start..meta.start+meta.len]); },
  closures=>{ pool_closures.free_slice(pool_closures[meta.start..meta.start+meta.len]); },
  value_evidence=>{ pool_value_evidence.free_slice(pool_value_evidence[meta.start..meta.start+meta.len]); },
  type_mappings=>{ pool_type_mappings.free_slice(pool_type_mappings[meta.start..meta.start+meta.len]); },
  row_mappings=>{ pool_row_mappings.free_slice(pool_row_mappings[meta.start..meta.start+meta.len]); },
  evidence_nodes=>{ pool_evidence_nodes.free_slice(pool_evidence_nodes[meta.start..meta.start+meta.len]); },
  evidence_extra=>{ pool_evidence_extra.free_slice(pool_evidence_extra[meta.start..meta.start+meta.len]); },
  evidence_quantifier_goals=>{ pool_evidence_quantifier_goals.free_slice(pool_evidence_quantifier_goals[meta.start..meta.start+meta.len]); },
  evidence_quantifier_obligations=>{ pool_evidence_quantifier_obligations.free_slice(pool_evidence_quantifier_obligations[meta.start..meta.start+meta.len]); },
  evidence_operations=>{ pool_evidence_operations.free_slice(pool_evidence_operations[meta.start..meta.start+meta.len]); },
  evidence_arguments=>{ pool_evidence_arguments.free_slice(pool_evidence_arguments[meta.start..meta.start+meta.len]); },
  evidence_rows=>{ pool_evidence_rows.free_slice(pool_evidence_rows[meta.start..meta.start+meta.len]); },
  evidence_labels=>{ pool_evidence_labels.free_slice(pool_evidence_labels[meta.start..meta.start+meta.len]); },
  value_records=>{ pool_value_records.free_slice(pool_value_records[meta.start..meta.start+meta.len]); },
  record_layouts=>{ pool_record_layouts.free_slice(pool_record_layouts[meta.start..meta.start+meta.len]); },
  field_names=>{ pool_field_names.free_slice(pool_field_names[meta.start..meta.start+meta.len]); },
  implementation_proofs=>{ pool_implementation_proofs.free_slice(pool_implementation_proofs[meta.start..meta.start+meta.len]); },
  implementation_arguments=>{ pool_implementation_arguments.free_slice(pool_implementation_arguments[meta.start..meta.start+meta.len]); },
  implementation_members=>{ pool_implementation_members.free_slice(pool_implementation_members[meta.start..meta.start+meta.len]); },
  implementation_edges=>{ pool_implementation_edges.free_slice(pool_implementation_edges[meta.start..meta.start+meta.len]); },
  captures=>{ pool_captures.free_slice(pool_captures[meta.start..meta.start+meta.len]); },
  field_locations=>{ pool_field_locations.free_slice(pool_field_locations[meta.start..meta.start+meta.len]); },
  functions=>{ pool_functions.free_slice(pool_functions[meta.start..meta.start+meta.len]); },
  serialized=>{ pool_serialized.free_slice(pool_serialized[meta.start..meta.start+meta.len]); },
  runtime_globals=>{ pool_runtime_globals.free_slice(pool_runtime_globals[meta.start..meta.start+meta.len]); },
  runtime_order=>{ pool_runtime_order.free_slice(pool_runtime_order[meta.start..meta.start+meta.len]); },
  binding_offsets=>{ pool_binding_offsets.free_slice(pool_binding_offsets[meta.start..meta.start+meta.len]); },
  node_offsets=>{ pool_node_offsets.free_slice(pool_node_offsets[meta.start..meta.start+meta.len]); },
  slots=>{ pool_slots.free_slice(pool_slots[meta.start..meta.start+meta.len]); },
  visited_nodes=>{ pool_visited_nodes.free_slice(pool_visited_nodes[meta.start..meta.start+meta.len]); },
  provider_frames=>{ pool_provider_frames.free_slice(pool_provider_frames[meta.start..meta.start+meta.len]); },
  provider_cells=>{ pool_provider_cells.free_slice(pool_provider_cells[meta.start..meta.start+meta.len]); },
  request_cells=>{ pool_request_cells.free_slice(pool_request_cells[meta.start..meta.start+meta.len]); },
  request_handlers=>{ pool_request_handlers.free_slice(pool_request_handlers[meta.start..meta.start+meta.len]); },
  break_values=>{ pool_break_values.free_slice(pool_break_values[meta.start..meta.start+meta.len]); },
  operation_relocations=>{ pool_operation_relocations.free_slice(pool_operation_relocations[meta.start..meta.start+meta.len]); },
  code_origins=>{ pool_code_origins.free_slice(pool_code_origins[meta.start..meta.start+meta.len]); },
 }
 lease_meta[index].live=false; lease_meta.free(index); return blot_error::Error.none;
}
fn abort(self_: Builder&) -> Error {
 var failure=blot_error::Error.none;
 for i in 0..field_count { let ref=self_.leases.values[i]; if ref.index!=0 { let error=release(ref); if failure==blot_error::Error.none { failure=error; } self_.leases.values[i]=LeaseRef {}; } }
 return failure;
}

fn alloc_identity_bytes(self_: Builder&,len: i64) -> u8[:],Error {
 if self_.leases.values[0].index!=0||len<0 { return default<u8[:]>(),blot_error::Error.invalid_artifact; }
 if len==0 { return default<u8[:]>(),blot_error::Error.none; }
 if next_generation==0xffffffffffffffff { return default<u8[:]>(),blot_error::Error.artifact_limit; }
 let items=pool_identity_bytes.alloc_slice(len); let first: const u8& =items[0]; let start=pool_identity_bytes.index_of(first);
 let ref,error=create(Field.identity_bytes,start,len); if error!=blot_error::Error.none { pool_identity_bytes.free_slice(items); return default<u8[:]>(),error; }
 self_.leases.values[0]=ref; self_.stats.copied_fields++; self_.stats.copied_bytes+=bytes_of(items).len; return items,blot_error::Error.none;
}
fn shareable_identity_bytes(self_: const Builder&,old: const u8[:]) -> bool {
 if old.len==0 {return false;}let previous .=self_.previous;if !previous {return false;}
 let ref=previous.values[0]; if !valid(ref) { return false; } let meta=lease_meta[ref.index-1];
 if meta.field!=Field.identity_bytes||meta.len!=old.len { return false; }
 let a: const u8& =old[0]; let b: const u8& =pool_identity_bytes[meta.start]; return a .== b;
}
fn retained_identity_bytes(self_: Builder&,old: const u8[:]) -> const u8[:],Error {
 let previous .=self_.previous;if !previous {return default<const u8[:]>(),blot_error::Error.invalid_artifact;}let ref=previous.values[0]; let error=retain(ref); if error!=blot_error::Error.none { return default<const u8[:]>(),error; }
 let meta=lease_meta[ref.index-1];
 assert(meta.field==Field.identity_bytes && meta.len==old.len && meta.len>0 && meta.start>=0 && meta.start<=pool_identity_bytes.len && meta.len<=pool_identity_bytes.len-meta.start);
 let items=pool_identity_bytes[meta.start..meta.start+meta.len];assert(blot_support::same_slice_identity(items,old));
 self_.leases.values[0]=ref; self_.stats.shared_fields++; self_.stats.shared_bytes+=bytes_of(old).len; return items,blot_error::Error.none;
}
fn dupe_identity_bytes(self_: Builder&,source: const u8[:],previous: const u8[:]) -> const u8[:],Error {
 if shareable_identity_bytes(self_,previous)&&blot_structural::equal(source,previous) { return retained_identity_bytes(self_,previous); }
 let items,error=alloc_identity_bytes(self_,source.len); if error!=blot_error::Error.none { return default<const u8[:]>(),error; } for value,index in source { items[index]=value; } return items,blot_error::Error.none;
}
fn converted_identity_bytes<C,F>(self_: Builder&,len: i64,context: C&,previous: const u8[:]) -> const u8[:],Error {
 if shareable_identity_bytes(self_,previous)&&previous.len==len {
  var same=true; for item,index in previous { if !blot_structural::equal(item,F(context,index)) { same=false; break; } } if same { return retained_identity_bytes(self_,previous); }
 }
 let items,error=alloc_identity_bytes(self_,len); if error!=blot_error::Error.none { return default<const u8[:]>(),error; } for index in 0..len { items[index]=F(context,index); } return items,blot_error::Error.none;
}
fn free_identity_bytes(leases: const Leases&,items: const u8[:]) -> Error {
 let ref=leases.values[0]; if ref.index!=0 { return release(ref); }
 if items.len!=0 {pool_identity_bytes.free_slice(items);} return blot_error::Error.none;
}

fn alloc_identity_symbols(self_: Builder&,len: i64) -> blot_backend_runtime_identity::Name[:],Error {
 if self_.leases.values[1].index!=0||len<0 { return default<blot_backend_runtime_identity::Name[:]>(),blot_error::Error.invalid_artifact; }
 if len==0 { return default<blot_backend_runtime_identity::Name[:]>(),blot_error::Error.none; }
 if next_generation==0xffffffffffffffff { return default<blot_backend_runtime_identity::Name[:]>(),blot_error::Error.artifact_limit; }
 let items=pool_identity_symbols.alloc_slice(len); let first: const blot_backend_runtime_identity::Name& =items[0]; let start=pool_identity_symbols.index_of(first);
 let ref,error=create(Field.identity_symbols,start,len); if error!=blot_error::Error.none { pool_identity_symbols.free_slice(items); return default<blot_backend_runtime_identity::Name[:]>(),error; }
 self_.leases.values[1]=ref; self_.stats.copied_fields++; self_.stats.copied_bytes+=bytes_of(items).len; return items,blot_error::Error.none;
}
fn shareable_identity_symbols(self_: const Builder&,old: const blot_backend_runtime_identity::Name[:]) -> bool {
 if old.len==0 {return false;}let previous .=self_.previous;if !previous {return false;}
 let ref=previous.values[1]; if !valid(ref) { return false; } let meta=lease_meta[ref.index-1];
 if meta.field!=Field.identity_symbols||meta.len!=old.len { return false; }
 let a: const blot_backend_runtime_identity::Name& =old[0]; let b: const blot_backend_runtime_identity::Name& =pool_identity_symbols[meta.start]; return a .== b;
}
fn retained_identity_symbols(self_: Builder&,old: const blot_backend_runtime_identity::Name[:]) -> const blot_backend_runtime_identity::Name[:],Error {
 let previous .=self_.previous;if !previous {return default<const blot_backend_runtime_identity::Name[:]>(),blot_error::Error.invalid_artifact;}let ref=previous.values[1]; let error=retain(ref); if error!=blot_error::Error.none { return default<const blot_backend_runtime_identity::Name[:]>(),error; }
 let meta=lease_meta[ref.index-1];
 assert(meta.field==Field.identity_symbols && meta.len==old.len && meta.len>0 && meta.start>=0 && meta.start<=pool_identity_symbols.len && meta.len<=pool_identity_symbols.len-meta.start);
 let items=pool_identity_symbols[meta.start..meta.start+meta.len];assert(blot_support::same_slice_identity(items,old));
 self_.leases.values[1]=ref; self_.stats.shared_fields++; self_.stats.shared_bytes+=bytes_of(old).len; return items,blot_error::Error.none;
}
fn dupe_identity_symbols(self_: Builder&,source: const blot_backend_runtime_identity::Name[:],previous: const blot_backend_runtime_identity::Name[:]) -> const blot_backend_runtime_identity::Name[:],Error {
 if shareable_identity_symbols(self_,previous)&&blot_structural::equal(source,previous) { return retained_identity_symbols(self_,previous); }
 let items,error=alloc_identity_symbols(self_,source.len); if error!=blot_error::Error.none { return default<const blot_backend_runtime_identity::Name[:]>(),error; } for value,index in source { items[index]=value; } return items,blot_error::Error.none;
}
fn converted_identity_symbols<C,F>(self_: Builder&,len: i64,context: C&,previous: const blot_backend_runtime_identity::Name[:]) -> const blot_backend_runtime_identity::Name[:],Error {
 if shareable_identity_symbols(self_,previous)&&previous.len==len {
  var same=true; for item,index in previous { if !blot_structural::equal(item,F(context,index)) { same=false; break; } } if same { return retained_identity_symbols(self_,previous); }
 }
 let items,error=alloc_identity_symbols(self_,len); if error!=blot_error::Error.none { return default<const blot_backend_runtime_identity::Name[:]>(),error; } for index in 0..len { items[index]=F(context,index); } return items,blot_error::Error.none;
}
fn free_identity_symbols(leases: const Leases&,items: const blot_backend_runtime_identity::Name[:]) -> Error {
 let ref=leases.values[1]; if ref.index!=0 { return release(ref); }
 if items.len!=0 {pool_identity_symbols.free_slice(items);} return blot_error::Error.none;
}

fn alloc_identity_owners(self_: Builder&,len: i64) -> blot_backend_runtime_identity::Name[:],Error {
 if self_.leases.values[2].index!=0||len<0 { return default<blot_backend_runtime_identity::Name[:]>(),blot_error::Error.invalid_artifact; }
 if len==0 { return default<blot_backend_runtime_identity::Name[:]>(),blot_error::Error.none; }
 if next_generation==0xffffffffffffffff { return default<blot_backend_runtime_identity::Name[:]>(),blot_error::Error.artifact_limit; }
 let items=pool_identity_owners.alloc_slice(len); let first: const blot_backend_runtime_identity::Name& =items[0]; let start=pool_identity_owners.index_of(first);
 let ref,error=create(Field.identity_owners,start,len); if error!=blot_error::Error.none { pool_identity_owners.free_slice(items); return default<blot_backend_runtime_identity::Name[:]>(),error; }
 self_.leases.values[2]=ref; self_.stats.copied_fields++; self_.stats.copied_bytes+=bytes_of(items).len; return items,blot_error::Error.none;
}
fn shareable_identity_owners(self_: const Builder&,old: const blot_backend_runtime_identity::Name[:]) -> bool {
 if old.len==0 {return false;}let previous .=self_.previous;if !previous {return false;}
 let ref=previous.values[2]; if !valid(ref) { return false; } let meta=lease_meta[ref.index-1];
 if meta.field!=Field.identity_owners||meta.len!=old.len { return false; }
 let a: const blot_backend_runtime_identity::Name& =old[0]; let b: const blot_backend_runtime_identity::Name& =pool_identity_owners[meta.start]; return a .== b;
}
fn retained_identity_owners(self_: Builder&,old: const blot_backend_runtime_identity::Name[:]) -> const blot_backend_runtime_identity::Name[:],Error {
 let previous .=self_.previous;if !previous {return default<const blot_backend_runtime_identity::Name[:]>(),blot_error::Error.invalid_artifact;}let ref=previous.values[2]; let error=retain(ref); if error!=blot_error::Error.none { return default<const blot_backend_runtime_identity::Name[:]>(),error; }
 let meta=lease_meta[ref.index-1];
 assert(meta.field==Field.identity_owners && meta.len==old.len && meta.len>0 && meta.start>=0 && meta.start<=pool_identity_owners.len && meta.len<=pool_identity_owners.len-meta.start);
 let items=pool_identity_owners[meta.start..meta.start+meta.len];assert(blot_support::same_slice_identity(items,old));
 self_.leases.values[2]=ref; self_.stats.shared_fields++; self_.stats.shared_bytes+=bytes_of(old).len; return items,blot_error::Error.none;
}
fn dupe_identity_owners(self_: Builder&,source: const blot_backend_runtime_identity::Name[:],previous: const blot_backend_runtime_identity::Name[:]) -> const blot_backend_runtime_identity::Name[:],Error {
 if shareable_identity_owners(self_,previous)&&blot_structural::equal(source,previous) { return retained_identity_owners(self_,previous); }
 let items,error=alloc_identity_owners(self_,source.len); if error!=blot_error::Error.none { return default<const blot_backend_runtime_identity::Name[:]>(),error; } for value,index in source { items[index]=value; } return items,blot_error::Error.none;
}
fn converted_identity_owners<C,F>(self_: Builder&,len: i64,context: C&,previous: const blot_backend_runtime_identity::Name[:]) -> const blot_backend_runtime_identity::Name[:],Error {
 if shareable_identity_owners(self_,previous)&&previous.len==len {
  var same=true; for item,index in previous { if !blot_structural::equal(item,F(context,index)) { same=false; break; } } if same { return retained_identity_owners(self_,previous); }
 }
 let items,error=alloc_identity_owners(self_,len); if error!=blot_error::Error.none { return default<const blot_backend_runtime_identity::Name[:]>(),error; } for index in 0..len { items[index]=F(context,index); } return items,blot_error::Error.none;
}
fn free_identity_owners(leases: const Leases&,items: const blot_backend_runtime_identity::Name[:]) -> Error {
 let ref=leases.values[2]; if ref.index!=0 { return release(ref); }
 if items.len!=0 {pool_identity_owners.free_slice(items);} return blot_error::Error.none;
}

fn alloc_layout_nodes(self_: Builder&,len: i64) -> blot_backend_layout::Node[:],Error {
 if self_.leases.values[3].index!=0||len<0 { return default<blot_backend_layout::Node[:]>(),blot_error::Error.invalid_artifact; }
 if len==0 { return default<blot_backend_layout::Node[:]>(),blot_error::Error.none; }
 if next_generation==0xffffffffffffffff { return default<blot_backend_layout::Node[:]>(),blot_error::Error.artifact_limit; }
 let items=pool_layout_nodes.alloc_slice(len); let first: const blot_backend_layout::Node& =items[0]; let start=pool_layout_nodes.index_of(first);
 let ref,error=create(Field.layout_nodes,start,len); if error!=blot_error::Error.none { pool_layout_nodes.free_slice(items); return default<blot_backend_layout::Node[:]>(),error; }
 self_.leases.values[3]=ref; self_.stats.copied_fields++; self_.stats.copied_bytes+=bytes_of(items).len; return items,blot_error::Error.none;
}
fn shareable_layout_nodes(self_: const Builder&,old: const blot_backend_layout::Node[:]) -> bool {
 if old.len==0 {return false;}let previous .=self_.previous;if !previous {return false;}
 let ref=previous.values[3]; if !valid(ref) { return false; } let meta=lease_meta[ref.index-1];
 if meta.field!=Field.layout_nodes||meta.len!=old.len { return false; }
 let a: const blot_backend_layout::Node& =old[0]; let b: const blot_backend_layout::Node& =pool_layout_nodes[meta.start]; return a .== b;
}
fn retained_layout_nodes(self_: Builder&,old: const blot_backend_layout::Node[:]) -> const blot_backend_layout::Node[:],Error {
 let previous .=self_.previous;if !previous {return default<const blot_backend_layout::Node[:]>(),blot_error::Error.invalid_artifact;}let ref=previous.values[3]; let error=retain(ref); if error!=blot_error::Error.none { return default<const blot_backend_layout::Node[:]>(),error; }
 let meta=lease_meta[ref.index-1];
 assert(meta.field==Field.layout_nodes && meta.len==old.len && meta.len>0 && meta.start>=0 && meta.start<=pool_layout_nodes.len && meta.len<=pool_layout_nodes.len-meta.start);
 let items=pool_layout_nodes[meta.start..meta.start+meta.len];assert(blot_support::same_slice_identity(items,old));
 self_.leases.values[3]=ref; self_.stats.shared_fields++; self_.stats.shared_bytes+=bytes_of(old).len; return items,blot_error::Error.none;
}
fn dupe_layout_nodes(self_: Builder&,source: const blot_backend_layout::Node[:],previous: const blot_backend_layout::Node[:]) -> const blot_backend_layout::Node[:],Error {
 if shareable_layout_nodes(self_,previous)&&blot_structural::equal(source,previous) { return retained_layout_nodes(self_,previous); }
 let items,error=alloc_layout_nodes(self_,source.len); if error!=blot_error::Error.none { return default<const blot_backend_layout::Node[:]>(),error; } for value,index in source { items[index]=value; } return items,blot_error::Error.none;
}
fn converted_layout_nodes<C,F>(self_: Builder&,len: i64,context: C&,previous: const blot_backend_layout::Node[:]) -> const blot_backend_layout::Node[:],Error {
 if shareable_layout_nodes(self_,previous)&&previous.len==len {
  var same=true; for item,index in previous { if !blot_structural::equal(item,F(context,index)) { same=false; break; } } if same { return retained_layout_nodes(self_,previous); }
 }
 let items,error=alloc_layout_nodes(self_,len); if error!=blot_error::Error.none { return default<const blot_backend_layout::Node[:]>(),error; } for index in 0..len { items[index]=F(context,index); } return items,blot_error::Error.none;
}
fn free_layout_nodes(leases: const Leases&,items: const blot_backend_layout::Node[:]) -> Error {
 let ref=leases.values[3]; if ref.index!=0 { return release(ref); }
 if items.len!=0 {pool_layout_nodes.free_slice(items);} return blot_error::Error.none;
}

fn alloc_layout_extra(self_: Builder&,len: i64) -> u32[:],Error {
 if self_.leases.values[4].index!=0||len<0 { return default<u32[:]>(),blot_error::Error.invalid_artifact; }
 if len==0 { return default<u32[:]>(),blot_error::Error.none; }
 if next_generation==0xffffffffffffffff { return default<u32[:]>(),blot_error::Error.artifact_limit; }
 let items=pool_layout_extra.alloc_slice(len); let first: const u32& =items[0]; let start=pool_layout_extra.index_of(first);
 let ref,error=create(Field.layout_extra,start,len); if error!=blot_error::Error.none { pool_layout_extra.free_slice(items); return default<u32[:]>(),error; }
 self_.leases.values[4]=ref; self_.stats.copied_fields++; self_.stats.copied_bytes+=bytes_of(items).len; return items,blot_error::Error.none;
}
fn shareable_layout_extra(self_: const Builder&,old: const u32[:]) -> bool {
 if old.len==0 {return false;}let previous .=self_.previous;if !previous {return false;}
 let ref=previous.values[4]; if !valid(ref) { return false; } let meta=lease_meta[ref.index-1];
 if meta.field!=Field.layout_extra||meta.len!=old.len { return false; }
 let a: const u32& =old[0]; let b: const u32& =pool_layout_extra[meta.start]; return a .== b;
}
fn retained_layout_extra(self_: Builder&,old: const u32[:]) -> const u32[:],Error {
 let previous .=self_.previous;if !previous {return default<const u32[:]>(),blot_error::Error.invalid_artifact;}let ref=previous.values[4]; let error=retain(ref); if error!=blot_error::Error.none { return default<const u32[:]>(),error; }
 let meta=lease_meta[ref.index-1];
 assert(meta.field==Field.layout_extra && meta.len==old.len && meta.len>0 && meta.start>=0 && meta.start<=pool_layout_extra.len && meta.len<=pool_layout_extra.len-meta.start);
 let items=pool_layout_extra[meta.start..meta.start+meta.len];assert(blot_support::same_slice_identity(items,old));
 self_.leases.values[4]=ref; self_.stats.shared_fields++; self_.stats.shared_bytes+=bytes_of(old).len; return items,blot_error::Error.none;
}
fn dupe_layout_extra(self_: Builder&,source: const u32[:],previous: const u32[:]) -> const u32[:],Error {
 if shareable_layout_extra(self_,previous)&&blot_structural::equal(source,previous) { return retained_layout_extra(self_,previous); }
 let items,error=alloc_layout_extra(self_,source.len); if error!=blot_error::Error.none { return default<const u32[:]>(),error; } for value,index in source { items[index]=value; } return items,blot_error::Error.none;
}
fn converted_layout_extra<C,F>(self_: Builder&,len: i64,context: C&,previous: const u32[:]) -> const u32[:],Error {
 if shareable_layout_extra(self_,previous)&&previous.len==len {
  var same=true; for item,index in previous { if !blot_structural::equal(item,F(context,index)) { same=false; break; } } if same { return retained_layout_extra(self_,previous); }
 }
 let items,error=alloc_layout_extra(self_,len); if error!=blot_error::Error.none { return default<const u32[:]>(),error; } for index in 0..len { items[index]=F(context,index); } return items,blot_error::Error.none;
}
fn free_layout_extra(leases: const Leases&,items: const u32[:]) -> Error {
 let ref=leases.values[4]; if ref.index!=0 { return release(ref); }
 if items.len!=0 {pool_layout_extra.free_slice(items);} return blot_error::Error.none;
}

fn alloc_layout_universal_dictionaries(self_: Builder&,len: i64) -> blot_backend_layout::UniversalDictionaries[:],Error {
 if self_.leases.values[5].index!=0||len<0 { return default<blot_backend_layout::UniversalDictionaries[:]>(),blot_error::Error.invalid_artifact; }
 if len==0 { return default<blot_backend_layout::UniversalDictionaries[:]>(),blot_error::Error.none; }
 if next_generation==0xffffffffffffffff { return default<blot_backend_layout::UniversalDictionaries[:]>(),blot_error::Error.artifact_limit; }
 let items=pool_layout_universal_dictionaries.alloc_slice(len); let first: const blot_backend_layout::UniversalDictionaries& =items[0]; let start=pool_layout_universal_dictionaries.index_of(first);
 let ref,error=create(Field.layout_universal_dictionaries,start,len); if error!=blot_error::Error.none { pool_layout_universal_dictionaries.free_slice(items); return default<blot_backend_layout::UniversalDictionaries[:]>(),error; }
 self_.leases.values[5]=ref; self_.stats.copied_fields++; self_.stats.copied_bytes+=bytes_of(items).len; return items,blot_error::Error.none;
}
fn shareable_layout_universal_dictionaries(self_: const Builder&,old: const blot_backend_layout::UniversalDictionaries[:]) -> bool {
 if old.len==0 {return false;}let previous .=self_.previous;if !previous {return false;}
 let ref=previous.values[5]; if !valid(ref) { return false; } let meta=lease_meta[ref.index-1];
 if meta.field!=Field.layout_universal_dictionaries||meta.len!=old.len { return false; }
 let a: const blot_backend_layout::UniversalDictionaries& =old[0]; let b: const blot_backend_layout::UniversalDictionaries& =pool_layout_universal_dictionaries[meta.start]; return a .== b;
}
fn retained_layout_universal_dictionaries(self_: Builder&,old: const blot_backend_layout::UniversalDictionaries[:]) -> const blot_backend_layout::UniversalDictionaries[:],Error {
 let previous .=self_.previous;if !previous {return default<const blot_backend_layout::UniversalDictionaries[:]>(),blot_error::Error.invalid_artifact;}let ref=previous.values[5]; let error=retain(ref); if error!=blot_error::Error.none { return default<const blot_backend_layout::UniversalDictionaries[:]>(),error; }
 let meta=lease_meta[ref.index-1];
 assert(meta.field==Field.layout_universal_dictionaries && meta.len==old.len && meta.len>0 && meta.start>=0 && meta.start<=pool_layout_universal_dictionaries.len && meta.len<=pool_layout_universal_dictionaries.len-meta.start);
 let items=pool_layout_universal_dictionaries[meta.start..meta.start+meta.len];assert(blot_support::same_slice_identity(items,old));
 self_.leases.values[5]=ref; self_.stats.shared_fields++; self_.stats.shared_bytes+=bytes_of(old).len; return items,blot_error::Error.none;
}
fn dupe_layout_universal_dictionaries(self_: Builder&,source: const blot_backend_layout::UniversalDictionaries[:],previous: const blot_backend_layout::UniversalDictionaries[:]) -> const blot_backend_layout::UniversalDictionaries[:],Error {
 if shareable_layout_universal_dictionaries(self_,previous)&&blot_structural::equal(source,previous) { return retained_layout_universal_dictionaries(self_,previous); }
 let items,error=alloc_layout_universal_dictionaries(self_,source.len); if error!=blot_error::Error.none { return default<const blot_backend_layout::UniversalDictionaries[:]>(),error; } for value,index in source { items[index]=value; } return items,blot_error::Error.none;
}
fn converted_layout_universal_dictionaries<C,F>(self_: Builder&,len: i64,context: C&,previous: const blot_backend_layout::UniversalDictionaries[:]) -> const blot_backend_layout::UniversalDictionaries[:],Error {
 if shareable_layout_universal_dictionaries(self_,previous)&&previous.len==len {
  var same=true; for item,index in previous { if !blot_structural::equal(item,F(context,index)) { same=false; break; } } if same { return retained_layout_universal_dictionaries(self_,previous); }
 }
 let items,error=alloc_layout_universal_dictionaries(self_,len); if error!=blot_error::Error.none { return default<const blot_backend_layout::UniversalDictionaries[:]>(),error; } for index in 0..len { items[index]=F(context,index); } return items,blot_error::Error.none;
}
fn free_layout_universal_dictionaries(leases: const Leases&,items: const blot_backend_layout::UniversalDictionaries[:]) -> Error {
 let ref=leases.values[5]; if ref.index!=0 { return release(ref); }
 if items.len!=0 {pool_layout_universal_dictionaries.free_slice(items);} return blot_error::Error.none;
}

fn alloc_layout_operations(self_: Builder&,len: i64) -> blot_check_effect_evidence::Operation[:],Error {
 if self_.leases.values[6].index!=0||len<0 { return default<blot_check_effect_evidence::Operation[:]>(),blot_error::Error.invalid_artifact; }
 if len==0 { return default<blot_check_effect_evidence::Operation[:]>(),blot_error::Error.none; }
 if next_generation==0xffffffffffffffff { return default<blot_check_effect_evidence::Operation[:]>(),blot_error::Error.artifact_limit; }
 let items=pool_layout_operations.alloc_slice(len); let first: const blot_check_effect_evidence::Operation& =items[0]; let start=pool_layout_operations.index_of(first);
 let ref,error=create(Field.layout_operations,start,len); if error!=blot_error::Error.none { pool_layout_operations.free_slice(items); return default<blot_check_effect_evidence::Operation[:]>(),error; }
 self_.leases.values[6]=ref; self_.stats.copied_fields++; self_.stats.copied_bytes+=bytes_of(items).len; return items,blot_error::Error.none;
}
fn shareable_layout_operations(self_: const Builder&,old: const blot_check_effect_evidence::Operation[:]) -> bool {
 if old.len==0 {return false;}let previous .=self_.previous;if !previous {return false;}
 let ref=previous.values[6]; if !valid(ref) { return false; } let meta=lease_meta[ref.index-1];
 if meta.field!=Field.layout_operations||meta.len!=old.len { return false; }
 let a: const blot_check_effect_evidence::Operation& =old[0]; let b: const blot_check_effect_evidence::Operation& =pool_layout_operations[meta.start]; return a .== b;
}
fn retained_layout_operations(self_: Builder&,old: const blot_check_effect_evidence::Operation[:]) -> const blot_check_effect_evidence::Operation[:],Error {
 let previous .=self_.previous;if !previous {return default<const blot_check_effect_evidence::Operation[:]>(),blot_error::Error.invalid_artifact;}let ref=previous.values[6]; let error=retain(ref); if error!=blot_error::Error.none { return default<const blot_check_effect_evidence::Operation[:]>(),error; }
 let meta=lease_meta[ref.index-1];
 assert(meta.field==Field.layout_operations && meta.len==old.len && meta.len>0 && meta.start>=0 && meta.start<=pool_layout_operations.len && meta.len<=pool_layout_operations.len-meta.start);
 let items=pool_layout_operations[meta.start..meta.start+meta.len];assert(blot_support::same_slice_identity(items,old));
 self_.leases.values[6]=ref; self_.stats.shared_fields++; self_.stats.shared_bytes+=bytes_of(old).len; return items,blot_error::Error.none;
}
fn dupe_layout_operations(self_: Builder&,source: const blot_check_effect_evidence::Operation[:],previous: const blot_check_effect_evidence::Operation[:]) -> const blot_check_effect_evidence::Operation[:],Error {
 if shareable_layout_operations(self_,previous)&&blot_structural::equal(source,previous) { return retained_layout_operations(self_,previous); }
 let items,error=alloc_layout_operations(self_,source.len); if error!=blot_error::Error.none { return default<const blot_check_effect_evidence::Operation[:]>(),error; } for value,index in source { items[index]=value; } return items,blot_error::Error.none;
}
fn converted_layout_operations<C,F>(self_: Builder&,len: i64,context: C&,previous: const blot_check_effect_evidence::Operation[:]) -> const blot_check_effect_evidence::Operation[:],Error {
 if shareable_layout_operations(self_,previous)&&previous.len==len {
  var same=true; for item,index in previous { if !blot_structural::equal(item,F(context,index)) { same=false; break; } } if same { return retained_layout_operations(self_,previous); }
 }
 let items,error=alloc_layout_operations(self_,len); if error!=blot_error::Error.none { return default<const blot_check_effect_evidence::Operation[:]>(),error; } for index in 0..len { items[index]=F(context,index); } return items,blot_error::Error.none;
}
fn free_layout_operations(leases: const Leases&,items: const blot_check_effect_evidence::Operation[:]) -> Error {
 let ref=leases.values[6]; if ref.index!=0 { return release(ref); }
 if items.len!=0 {pool_layout_operations.free_slice(items);} return blot_error::Error.none;
}

fn alloc_layout_arguments(self_: Builder&,len: i64) -> u32[:],Error {
 if self_.leases.values[7].index!=0||len<0 { return default<u32[:]>(),blot_error::Error.invalid_artifact; }
 if len==0 { return default<u32[:]>(),blot_error::Error.none; }
 if next_generation==0xffffffffffffffff { return default<u32[:]>(),blot_error::Error.artifact_limit; }
 let items=pool_layout_arguments.alloc_slice(len); let first: const u32& =items[0]; let start=pool_layout_arguments.index_of(first);
 let ref,error=create(Field.layout_arguments,start,len); if error!=blot_error::Error.none { pool_layout_arguments.free_slice(items); return default<u32[:]>(),error; }
 self_.leases.values[7]=ref; self_.stats.copied_fields++; self_.stats.copied_bytes+=bytes_of(items).len; return items,blot_error::Error.none;
}
fn shareable_layout_arguments(self_: const Builder&,old: const u32[:]) -> bool {
 if old.len==0 {return false;}let previous .=self_.previous;if !previous {return false;}
 let ref=previous.values[7]; if !valid(ref) { return false; } let meta=lease_meta[ref.index-1];
 if meta.field!=Field.layout_arguments||meta.len!=old.len { return false; }
 let a: const u32& =old[0]; let b: const u32& =pool_layout_arguments[meta.start]; return a .== b;
}
fn retained_layout_arguments(self_: Builder&,old: const u32[:]) -> const u32[:],Error {
 let previous .=self_.previous;if !previous {return default<const u32[:]>(),blot_error::Error.invalid_artifact;}let ref=previous.values[7]; let error=retain(ref); if error!=blot_error::Error.none { return default<const u32[:]>(),error; }
 let meta=lease_meta[ref.index-1];
 assert(meta.field==Field.layout_arguments && meta.len==old.len && meta.len>0 && meta.start>=0 && meta.start<=pool_layout_arguments.len && meta.len<=pool_layout_arguments.len-meta.start);
 let items=pool_layout_arguments[meta.start..meta.start+meta.len];assert(blot_support::same_slice_identity(items,old));
 self_.leases.values[7]=ref; self_.stats.shared_fields++; self_.stats.shared_bytes+=bytes_of(old).len; return items,blot_error::Error.none;
}
fn dupe_layout_arguments(self_: Builder&,source: const u32[:],previous: const u32[:]) -> const u32[:],Error {
 if shareable_layout_arguments(self_,previous)&&blot_structural::equal(source,previous) { return retained_layout_arguments(self_,previous); }
 let items,error=alloc_layout_arguments(self_,source.len); if error!=blot_error::Error.none { return default<const u32[:]>(),error; } for value,index in source { items[index]=value; } return items,blot_error::Error.none;
}
fn converted_layout_arguments<C,F>(self_: Builder&,len: i64,context: C&,previous: const u32[:]) -> const u32[:],Error {
 if shareable_layout_arguments(self_,previous)&&previous.len==len {
  var same=true; for item,index in previous { if !blot_structural::equal(item,F(context,index)) { same=false; break; } } if same { return retained_layout_arguments(self_,previous); }
 }
 let items,error=alloc_layout_arguments(self_,len); if error!=blot_error::Error.none { return default<const u32[:]>(),error; } for index in 0..len { items[index]=F(context,index); } return items,blot_error::Error.none;
}
fn free_layout_arguments(leases: const Leases&,items: const u32[:]) -> Error {
 let ref=leases.values[7]; if ref.index!=0 { return release(ref); }
 if items.len!=0 {pool_layout_arguments.free_slice(items);} return blot_error::Error.none;
}

fn alloc_layout_rows(self_: Builder&,len: i64) -> blot_check_effect_evidence::Row[:],Error {
 if self_.leases.values[8].index!=0||len<0 { return default<blot_check_effect_evidence::Row[:]>(),blot_error::Error.invalid_artifact; }
 if len==0 { return default<blot_check_effect_evidence::Row[:]>(),blot_error::Error.none; }
 if next_generation==0xffffffffffffffff { return default<blot_check_effect_evidence::Row[:]>(),blot_error::Error.artifact_limit; }
 let items=pool_layout_rows.alloc_slice(len); let first: const blot_check_effect_evidence::Row& =items[0]; let start=pool_layout_rows.index_of(first);
 let ref,error=create(Field.layout_rows,start,len); if error!=blot_error::Error.none { pool_layout_rows.free_slice(items); return default<blot_check_effect_evidence::Row[:]>(),error; }
 self_.leases.values[8]=ref; self_.stats.copied_fields++; self_.stats.copied_bytes+=bytes_of(items).len; return items,blot_error::Error.none;
}
fn shareable_layout_rows(self_: const Builder&,old: const blot_check_effect_evidence::Row[:]) -> bool {
 if old.len==0 {return false;}let previous .=self_.previous;if !previous {return false;}
 let ref=previous.values[8]; if !valid(ref) { return false; } let meta=lease_meta[ref.index-1];
 if meta.field!=Field.layout_rows||meta.len!=old.len { return false; }
 let a: const blot_check_effect_evidence::Row& =old[0]; let b: const blot_check_effect_evidence::Row& =pool_layout_rows[meta.start]; return a .== b;
}
fn retained_layout_rows(self_: Builder&,old: const blot_check_effect_evidence::Row[:]) -> const blot_check_effect_evidence::Row[:],Error {
 let previous .=self_.previous;if !previous {return default<const blot_check_effect_evidence::Row[:]>(),blot_error::Error.invalid_artifact;}let ref=previous.values[8]; let error=retain(ref); if error!=blot_error::Error.none { return default<const blot_check_effect_evidence::Row[:]>(),error; }
 let meta=lease_meta[ref.index-1];
 assert(meta.field==Field.layout_rows && meta.len==old.len && meta.len>0 && meta.start>=0 && meta.start<=pool_layout_rows.len && meta.len<=pool_layout_rows.len-meta.start);
 let items=pool_layout_rows[meta.start..meta.start+meta.len];assert(blot_support::same_slice_identity(items,old));
 self_.leases.values[8]=ref; self_.stats.shared_fields++; self_.stats.shared_bytes+=bytes_of(old).len; return items,blot_error::Error.none;
}
fn dupe_layout_rows(self_: Builder&,source: const blot_check_effect_evidence::Row[:],previous: const blot_check_effect_evidence::Row[:]) -> const blot_check_effect_evidence::Row[:],Error {
 if shareable_layout_rows(self_,previous)&&blot_structural::equal(source,previous) { return retained_layout_rows(self_,previous); }
 let items,error=alloc_layout_rows(self_,source.len); if error!=blot_error::Error.none { return default<const blot_check_effect_evidence::Row[:]>(),error; } for value,index in source { items[index]=value; } return items,blot_error::Error.none;
}
fn converted_layout_rows<C,F>(self_: Builder&,len: i64,context: C&,previous: const blot_check_effect_evidence::Row[:]) -> const blot_check_effect_evidence::Row[:],Error {
 if shareable_layout_rows(self_,previous)&&previous.len==len {
  var same=true; for item,index in previous { if !blot_structural::equal(item,F(context,index)) { same=false; break; } } if same { return retained_layout_rows(self_,previous); }
 }
 let items,error=alloc_layout_rows(self_,len); if error!=blot_error::Error.none { return default<const blot_check_effect_evidence::Row[:]>(),error; } for index in 0..len { items[index]=F(context,index); } return items,blot_error::Error.none;
}
fn free_layout_rows(leases: const Leases&,items: const blot_check_effect_evidence::Row[:]) -> Error {
 let ref=leases.values[8]; if ref.index!=0 { return release(ref); }
 if items.len!=0 {pool_layout_rows.free_slice(items);} return blot_error::Error.none;
}

fn alloc_layout_labels(self_: Builder&,len: i64) -> u32[:],Error {
 if self_.leases.values[9].index!=0||len<0 { return default<u32[:]>(),blot_error::Error.invalid_artifact; }
 if len==0 { return default<u32[:]>(),blot_error::Error.none; }
 if next_generation==0xffffffffffffffff { return default<u32[:]>(),blot_error::Error.artifact_limit; }
 let items=pool_layout_labels.alloc_slice(len); let first: const u32& =items[0]; let start=pool_layout_labels.index_of(first);
 let ref,error=create(Field.layout_labels,start,len); if error!=blot_error::Error.none { pool_layout_labels.free_slice(items); return default<u32[:]>(),error; }
 self_.leases.values[9]=ref; self_.stats.copied_fields++; self_.stats.copied_bytes+=bytes_of(items).len; return items,blot_error::Error.none;
}
fn shareable_layout_labels(self_: const Builder&,old: const u32[:]) -> bool {
 if old.len==0 {return false;}let previous .=self_.previous;if !previous {return false;}
 let ref=previous.values[9]; if !valid(ref) { return false; } let meta=lease_meta[ref.index-1];
 if meta.field!=Field.layout_labels||meta.len!=old.len { return false; }
 let a: const u32& =old[0]; let b: const u32& =pool_layout_labels[meta.start]; return a .== b;
}
fn retained_layout_labels(self_: Builder&,old: const u32[:]) -> const u32[:],Error {
 let previous .=self_.previous;if !previous {return default<const u32[:]>(),blot_error::Error.invalid_artifact;}let ref=previous.values[9]; let error=retain(ref); if error!=blot_error::Error.none { return default<const u32[:]>(),error; }
 let meta=lease_meta[ref.index-1];
 assert(meta.field==Field.layout_labels && meta.len==old.len && meta.len>0 && meta.start>=0 && meta.start<=pool_layout_labels.len && meta.len<=pool_layout_labels.len-meta.start);
 let items=pool_layout_labels[meta.start..meta.start+meta.len];assert(blot_support::same_slice_identity(items,old));
 self_.leases.values[9]=ref; self_.stats.shared_fields++; self_.stats.shared_bytes+=bytes_of(old).len; return items,blot_error::Error.none;
}
fn dupe_layout_labels(self_: Builder&,source: const u32[:],previous: const u32[:]) -> const u32[:],Error {
 if shareable_layout_labels(self_,previous)&&blot_structural::equal(source,previous) { return retained_layout_labels(self_,previous); }
 let items,error=alloc_layout_labels(self_,source.len); if error!=blot_error::Error.none { return default<const u32[:]>(),error; } for value,index in source { items[index]=value; } return items,blot_error::Error.none;
}
fn converted_layout_labels<C,F>(self_: Builder&,len: i64,context: C&,previous: const u32[:]) -> const u32[:],Error {
 if shareable_layout_labels(self_,previous)&&previous.len==len {
  var same=true; for item,index in previous { if !blot_structural::equal(item,F(context,index)) { same=false; break; } } if same { return retained_layout_labels(self_,previous); }
 }
 let items,error=alloc_layout_labels(self_,len); if error!=blot_error::Error.none { return default<const u32[:]>(),error; } for index in 0..len { items[index]=F(context,index); } return items,blot_error::Error.none;
}
fn free_layout_labels(leases: const Leases&,items: const u32[:]) -> Error {
 let ref=leases.values[9]; if ref.index!=0 { return release(ref); }
 if items.len!=0 {pool_layout_labels.free_slice(items);} return blot_error::Error.none;
}

fn alloc_values(self_: Builder&,len: i64) -> blot_eval_eval_values::ValueInfo[:],Error {
 if self_.leases.values[10].index!=0||len<0 { return default<blot_eval_eval_values::ValueInfo[:]>(),blot_error::Error.invalid_artifact; }
 if len==0 { return default<blot_eval_eval_values::ValueInfo[:]>(),blot_error::Error.none; }
 if next_generation==0xffffffffffffffff { return default<blot_eval_eval_values::ValueInfo[:]>(),blot_error::Error.artifact_limit; }
 let items=pool_values.alloc_slice(len); let first: const blot_eval_eval_values::ValueInfo& =items[0]; let start=pool_values.index_of(first);
 let ref,error=create(Field.values,start,len); if error!=blot_error::Error.none { pool_values.free_slice(items); return default<blot_eval_eval_values::ValueInfo[:]>(),error; }
 self_.leases.values[10]=ref; self_.stats.copied_fields++; self_.stats.copied_bytes+=bytes_of(items).len; return items,blot_error::Error.none;
}
fn shareable_values(self_: const Builder&,old: const blot_eval_eval_values::ValueInfo[:]) -> bool {
 if old.len==0 {return false;}let previous .=self_.previous;if !previous {return false;}
 let ref=previous.values[10]; if !valid(ref) { return false; } let meta=lease_meta[ref.index-1];
 if meta.field!=Field.values||meta.len!=old.len { return false; }
 let a: const blot_eval_eval_values::ValueInfo& =old[0]; let b: const blot_eval_eval_values::ValueInfo& =pool_values[meta.start]; return a .== b;
}
fn retained_values(self_: Builder&,old: const blot_eval_eval_values::ValueInfo[:]) -> const blot_eval_eval_values::ValueInfo[:],Error {
 let previous .=self_.previous;if !previous {return default<const blot_eval_eval_values::ValueInfo[:]>(),blot_error::Error.invalid_artifact;}let ref=previous.values[10]; let error=retain(ref); if error!=blot_error::Error.none { return default<const blot_eval_eval_values::ValueInfo[:]>(),error; }
 let meta=lease_meta[ref.index-1];
 assert(meta.field==Field.values && meta.len==old.len && meta.len>0 && meta.start>=0 && meta.start<=pool_values.len && meta.len<=pool_values.len-meta.start);
 let items=pool_values[meta.start..meta.start+meta.len];assert(blot_support::same_slice_identity(items,old));
 self_.leases.values[10]=ref; self_.stats.shared_fields++; self_.stats.shared_bytes+=bytes_of(old).len; return items,blot_error::Error.none;
}
fn dupe_values(self_: Builder&,source: const blot_eval_eval_values::ValueInfo[:],previous: const blot_eval_eval_values::ValueInfo[:]) -> const blot_eval_eval_values::ValueInfo[:],Error {
 if shareable_values(self_,previous)&&blot_structural::equal(source,previous) { return retained_values(self_,previous); }
 let items,error=alloc_values(self_,source.len); if error!=blot_error::Error.none { return default<const blot_eval_eval_values::ValueInfo[:]>(),error; } for value,index in source { items[index]=value; } return items,blot_error::Error.none;
}
fn converted_values<C,F>(self_: Builder&,len: i64,context: C&,previous: const blot_eval_eval_values::ValueInfo[:]) -> const blot_eval_eval_values::ValueInfo[:],Error {
 if shareable_values(self_,previous)&&previous.len==len {
  var same=true; for item,index in previous { if !blot_structural::equal(item,F(context,index)) { same=false; break; } } if same { return retained_values(self_,previous); }
 }
 let items,error=alloc_values(self_,len); if error!=blot_error::Error.none { return default<const blot_eval_eval_values::ValueInfo[:]>(),error; } for index in 0..len { items[index]=F(context,index); } return items,blot_error::Error.none;
}
fn free_values(leases: const Leases&,items: const blot_eval_eval_values::ValueInfo[:]) -> Error {
 let ref=leases.values[10]; if ref.index!=0 { return release(ref); }
 if items.len!=0 {pool_values.free_slice(items);} return blot_error::Error.none;
}

fn alloc_children(self_: Builder&,len: i64) -> u32[:],Error {
 if self_.leases.values[11].index!=0||len<0 { return default<u32[:]>(),blot_error::Error.invalid_artifact; }
 if len==0 { return default<u32[:]>(),blot_error::Error.none; }
 if next_generation==0xffffffffffffffff { return default<u32[:]>(),blot_error::Error.artifact_limit; }
 let items=pool_children.alloc_slice(len); let first: const u32& =items[0]; let start=pool_children.index_of(first);
 let ref,error=create(Field.children,start,len); if error!=blot_error::Error.none { pool_children.free_slice(items); return default<u32[:]>(),error; }
 self_.leases.values[11]=ref; self_.stats.copied_fields++; self_.stats.copied_bytes+=bytes_of(items).len; return items,blot_error::Error.none;
}
fn shareable_children(self_: const Builder&,old: const u32[:]) -> bool {
 if old.len==0 {return false;}let previous .=self_.previous;if !previous {return false;}
 let ref=previous.values[11]; if !valid(ref) { return false; } let meta=lease_meta[ref.index-1];
 if meta.field!=Field.children||meta.len!=old.len { return false; }
 let a: const u32& =old[0]; let b: const u32& =pool_children[meta.start]; return a .== b;
}
fn retained_children(self_: Builder&,old: const u32[:]) -> const u32[:],Error {
 let previous .=self_.previous;if !previous {return default<const u32[:]>(),blot_error::Error.invalid_artifact;}let ref=previous.values[11]; let error=retain(ref); if error!=blot_error::Error.none { return default<const u32[:]>(),error; }
 let meta=lease_meta[ref.index-1];
 assert(meta.field==Field.children && meta.len==old.len && meta.len>0 && meta.start>=0 && meta.start<=pool_children.len && meta.len<=pool_children.len-meta.start);
 let items=pool_children[meta.start..meta.start+meta.len];assert(blot_support::same_slice_identity(items,old));
 self_.leases.values[11]=ref; self_.stats.shared_fields++; self_.stats.shared_bytes+=bytes_of(old).len; return items,blot_error::Error.none;
}
fn dupe_children(self_: Builder&,source: const u32[:],previous: const u32[:]) -> const u32[:],Error {
 if shareable_children(self_,previous)&&blot_structural::equal(source,previous) { return retained_children(self_,previous); }
 let items,error=alloc_children(self_,source.len); if error!=blot_error::Error.none { return default<const u32[:]>(),error; } for value,index in source { items[index]=value; } return items,blot_error::Error.none;
}
fn converted_children<C,F>(self_: Builder&,len: i64,context: C&,previous: const u32[:]) -> const u32[:],Error {
 if shareable_children(self_,previous)&&previous.len==len {
  var same=true; for item,index in previous { if !blot_structural::equal(item,F(context,index)) { same=false; break; } } if same { return retained_children(self_,previous); }
 }
 let items,error=alloc_children(self_,len); if error!=blot_error::Error.none { return default<const u32[:]>(),error; } for index in 0..len { items[index]=F(context,index); } return items,blot_error::Error.none;
}
fn free_children(leases: const Leases&,items: const u32[:]) -> Error {
 let ref=leases.values[11]; if ref.index!=0 { return release(ref); }
 if items.len!=0 {pool_children.free_slice(items);} return blot_error::Error.none;
}

fn alloc_closures(self_: Builder&,len: i64) -> blot_eval_eval_values::ClosureValue[:],Error {
 if self_.leases.values[12].index!=0||len<0 { return default<blot_eval_eval_values::ClosureValue[:]>(),blot_error::Error.invalid_artifact; }
 if len==0 { return default<blot_eval_eval_values::ClosureValue[:]>(),blot_error::Error.none; }
 if next_generation==0xffffffffffffffff { return default<blot_eval_eval_values::ClosureValue[:]>(),blot_error::Error.artifact_limit; }
 let items=pool_closures.alloc_slice(len); let first: const blot_eval_eval_values::ClosureValue& =items[0]; let start=pool_closures.index_of(first);
 let ref,error=create(Field.closures,start,len); if error!=blot_error::Error.none { pool_closures.free_slice(items); return default<blot_eval_eval_values::ClosureValue[:]>(),error; }
 self_.leases.values[12]=ref; self_.stats.copied_fields++; self_.stats.copied_bytes+=bytes_of(items).len; return items,blot_error::Error.none;
}
fn shareable_closures(self_: const Builder&,old: const blot_eval_eval_values::ClosureValue[:]) -> bool {
 if old.len==0 {return false;}let previous .=self_.previous;if !previous {return false;}
 let ref=previous.values[12]; if !valid(ref) { return false; } let meta=lease_meta[ref.index-1];
 if meta.field!=Field.closures||meta.len!=old.len { return false; }
 let a: const blot_eval_eval_values::ClosureValue& =old[0]; let b: const blot_eval_eval_values::ClosureValue& =pool_closures[meta.start]; return a .== b;
}
fn retained_closures(self_: Builder&,old: const blot_eval_eval_values::ClosureValue[:]) -> const blot_eval_eval_values::ClosureValue[:],Error {
 let previous .=self_.previous;if !previous {return default<const blot_eval_eval_values::ClosureValue[:]>(),blot_error::Error.invalid_artifact;}let ref=previous.values[12]; let error=retain(ref); if error!=blot_error::Error.none { return default<const blot_eval_eval_values::ClosureValue[:]>(),error; }
 let meta=lease_meta[ref.index-1];
 assert(meta.field==Field.closures && meta.len==old.len && meta.len>0 && meta.start>=0 && meta.start<=pool_closures.len && meta.len<=pool_closures.len-meta.start);
 let items=pool_closures[meta.start..meta.start+meta.len];assert(blot_support::same_slice_identity(items,old));
 self_.leases.values[12]=ref; self_.stats.shared_fields++; self_.stats.shared_bytes+=bytes_of(old).len; return items,blot_error::Error.none;
}
fn dupe_closures(self_: Builder&,source: const blot_eval_eval_values::ClosureValue[:],previous: const blot_eval_eval_values::ClosureValue[:]) -> const blot_eval_eval_values::ClosureValue[:],Error {
 if shareable_closures(self_,previous)&&blot_structural::equal(source,previous) { return retained_closures(self_,previous); }
 let items,error=alloc_closures(self_,source.len); if error!=blot_error::Error.none { return default<const blot_eval_eval_values::ClosureValue[:]>(),error; } for value,index in source { items[index]=value; } return items,blot_error::Error.none;
}
fn converted_closures<C,F>(self_: Builder&,len: i64,context: C&,previous: const blot_eval_eval_values::ClosureValue[:]) -> const blot_eval_eval_values::ClosureValue[:],Error {
 if shareable_closures(self_,previous)&&previous.len==len {
  var same=true; for item,index in previous { if !blot_structural::equal(item,F(context,index)) { same=false; break; } } if same { return retained_closures(self_,previous); }
 }
 let items,error=alloc_closures(self_,len); if error!=blot_error::Error.none { return default<const blot_eval_eval_values::ClosureValue[:]>(),error; } for index in 0..len { items[index]=F(context,index); } return items,blot_error::Error.none;
}
fn free_closures(leases: const Leases&,items: const blot_eval_eval_values::ClosureValue[:]) -> Error {
 let ref=leases.values[12]; if ref.index!=0 { return release(ref); }
 if items.len!=0 {pool_closures.free_slice(items);} return blot_error::Error.none;
}

fn alloc_value_evidence(self_: Builder&,len: i64) -> u32[:],Error {
 if self_.leases.values[13].index!=0||len<0 { return default<u32[:]>(),blot_error::Error.invalid_artifact; }
 if len==0 { return default<u32[:]>(),blot_error::Error.none; }
 if next_generation==0xffffffffffffffff { return default<u32[:]>(),blot_error::Error.artifact_limit; }
 let items=pool_value_evidence.alloc_slice(len); let first: const u32& =items[0]; let start=pool_value_evidence.index_of(first);
 let ref,error=create(Field.value_evidence,start,len); if error!=blot_error::Error.none { pool_value_evidence.free_slice(items); return default<u32[:]>(),error; }
 self_.leases.values[13]=ref; self_.stats.copied_fields++; self_.stats.copied_bytes+=bytes_of(items).len; return items,blot_error::Error.none;
}
fn shareable_value_evidence(self_: const Builder&,old: const u32[:]) -> bool {
 if old.len==0 {return false;}let previous .=self_.previous;if !previous {return false;}
 let ref=previous.values[13]; if !valid(ref) { return false; } let meta=lease_meta[ref.index-1];
 if meta.field!=Field.value_evidence||meta.len!=old.len { return false; }
 let a: const u32& =old[0]; let b: const u32& =pool_value_evidence[meta.start]; return a .== b;
}
fn retained_value_evidence(self_: Builder&,old: const u32[:]) -> const u32[:],Error {
 let previous .=self_.previous;if !previous {return default<const u32[:]>(),blot_error::Error.invalid_artifact;}let ref=previous.values[13]; let error=retain(ref); if error!=blot_error::Error.none { return default<const u32[:]>(),error; }
 let meta=lease_meta[ref.index-1];
 assert(meta.field==Field.value_evidence && meta.len==old.len && meta.len>0 && meta.start>=0 && meta.start<=pool_value_evidence.len && meta.len<=pool_value_evidence.len-meta.start);
 let items=pool_value_evidence[meta.start..meta.start+meta.len];assert(blot_support::same_slice_identity(items,old));
 self_.leases.values[13]=ref; self_.stats.shared_fields++; self_.stats.shared_bytes+=bytes_of(old).len; return items,blot_error::Error.none;
}
fn dupe_value_evidence(self_: Builder&,source: const u32[:],previous: const u32[:]) -> const u32[:],Error {
 if shareable_value_evidence(self_,previous)&&blot_structural::equal(source,previous) { return retained_value_evidence(self_,previous); }
 let items,error=alloc_value_evidence(self_,source.len); if error!=blot_error::Error.none { return default<const u32[:]>(),error; } for value,index in source { items[index]=value; } return items,blot_error::Error.none;
}
fn converted_value_evidence<C,F>(self_: Builder&,len: i64,context: C&,previous: const u32[:]) -> const u32[:],Error {
 if shareable_value_evidence(self_,previous)&&previous.len==len {
  var same=true; for item,index in previous { if !blot_structural::equal(item,F(context,index)) { same=false; break; } } if same { return retained_value_evidence(self_,previous); }
 }
 let items,error=alloc_value_evidence(self_,len); if error!=blot_error::Error.none { return default<const u32[:]>(),error; } for index in 0..len { items[index]=F(context,index); } return items,blot_error::Error.none;
}
fn free_value_evidence(leases: const Leases&,items: const u32[:]) -> Error {
 let ref=leases.values[13]; if ref.index!=0 { return release(ref); }
 if items.len!=0 {pool_value_evidence.free_slice(items);} return blot_error::Error.none;
}

fn alloc_type_mappings(self_: Builder&,len: i64) -> blot_eval_type_evidence::Mapping[:],Error {
 if self_.leases.values[14].index!=0||len<0 { return default<blot_eval_type_evidence::Mapping[:]>(),blot_error::Error.invalid_artifact; }
 if len==0 { return default<blot_eval_type_evidence::Mapping[:]>(),blot_error::Error.none; }
 if next_generation==0xffffffffffffffff { return default<blot_eval_type_evidence::Mapping[:]>(),blot_error::Error.artifact_limit; }
 let items=pool_type_mappings.alloc_slice(len); let first: const blot_eval_type_evidence::Mapping& =items[0]; let start=pool_type_mappings.index_of(first);
 let ref,error=create(Field.type_mappings,start,len); if error!=blot_error::Error.none { pool_type_mappings.free_slice(items); return default<blot_eval_type_evidence::Mapping[:]>(),error; }
 self_.leases.values[14]=ref; self_.stats.copied_fields++; self_.stats.copied_bytes+=bytes_of(items).len; return items,blot_error::Error.none;
}
fn shareable_type_mappings(self_: const Builder&,old: const blot_eval_type_evidence::Mapping[:]) -> bool {
 if old.len==0 {return false;}let previous .=self_.previous;if !previous {return false;}
 let ref=previous.values[14]; if !valid(ref) { return false; } let meta=lease_meta[ref.index-1];
 if meta.field!=Field.type_mappings||meta.len!=old.len { return false; }
 let a: const blot_eval_type_evidence::Mapping& =old[0]; let b: const blot_eval_type_evidence::Mapping& =pool_type_mappings[meta.start]; return a .== b;
}
fn retained_type_mappings(self_: Builder&,old: const blot_eval_type_evidence::Mapping[:]) -> const blot_eval_type_evidence::Mapping[:],Error {
 let previous .=self_.previous;if !previous {return default<const blot_eval_type_evidence::Mapping[:]>(),blot_error::Error.invalid_artifact;}let ref=previous.values[14]; let error=retain(ref); if error!=blot_error::Error.none { return default<const blot_eval_type_evidence::Mapping[:]>(),error; }
 let meta=lease_meta[ref.index-1];
 assert(meta.field==Field.type_mappings && meta.len==old.len && meta.len>0 && meta.start>=0 && meta.start<=pool_type_mappings.len && meta.len<=pool_type_mappings.len-meta.start);
 let items=pool_type_mappings[meta.start..meta.start+meta.len];assert(blot_support::same_slice_identity(items,old));
 self_.leases.values[14]=ref; self_.stats.shared_fields++; self_.stats.shared_bytes+=bytes_of(old).len; return items,blot_error::Error.none;
}
fn dupe_type_mappings(self_: Builder&,source: const blot_eval_type_evidence::Mapping[:],previous: const blot_eval_type_evidence::Mapping[:]) -> const blot_eval_type_evidence::Mapping[:],Error {
 if shareable_type_mappings(self_,previous)&&blot_structural::equal(source,previous) { return retained_type_mappings(self_,previous); }
 let items,error=alloc_type_mappings(self_,source.len); if error!=blot_error::Error.none { return default<const blot_eval_type_evidence::Mapping[:]>(),error; } for value,index in source { items[index]=value; } return items,blot_error::Error.none;
}
fn converted_type_mappings<C,F>(self_: Builder&,len: i64,context: C&,previous: const blot_eval_type_evidence::Mapping[:]) -> const blot_eval_type_evidence::Mapping[:],Error {
 if shareable_type_mappings(self_,previous)&&previous.len==len {
  var same=true; for item,index in previous { if !blot_structural::equal(item,F(context,index)) { same=false; break; } } if same { return retained_type_mappings(self_,previous); }
 }
 let items,error=alloc_type_mappings(self_,len); if error!=blot_error::Error.none { return default<const blot_eval_type_evidence::Mapping[:]>(),error; } for index in 0..len { items[index]=F(context,index); } return items,blot_error::Error.none;
}
fn free_type_mappings(leases: const Leases&,items: const blot_eval_type_evidence::Mapping[:]) -> Error {
 let ref=leases.values[14]; if ref.index!=0 { return release(ref); }
 if items.len!=0 {pool_type_mappings.free_slice(items);} return blot_error::Error.none;
}

fn alloc_row_mappings(self_: Builder&,len: i64) -> blot_eval_type_evidence::RowMapping[:],Error {
 if self_.leases.values[15].index!=0||len<0 { return default<blot_eval_type_evidence::RowMapping[:]>(),blot_error::Error.invalid_artifact; }
 if len==0 { return default<blot_eval_type_evidence::RowMapping[:]>(),blot_error::Error.none; }
 if next_generation==0xffffffffffffffff { return default<blot_eval_type_evidence::RowMapping[:]>(),blot_error::Error.artifact_limit; }
 let items=pool_row_mappings.alloc_slice(len); let first: const blot_eval_type_evidence::RowMapping& =items[0]; let start=pool_row_mappings.index_of(first);
 let ref,error=create(Field.row_mappings,start,len); if error!=blot_error::Error.none { pool_row_mappings.free_slice(items); return default<blot_eval_type_evidence::RowMapping[:]>(),error; }
 self_.leases.values[15]=ref; self_.stats.copied_fields++; self_.stats.copied_bytes+=bytes_of(items).len; return items,blot_error::Error.none;
}
fn shareable_row_mappings(self_: const Builder&,old: const blot_eval_type_evidence::RowMapping[:]) -> bool {
 if old.len==0 {return false;}let previous .=self_.previous;if !previous {return false;}
 let ref=previous.values[15]; if !valid(ref) { return false; } let meta=lease_meta[ref.index-1];
 if meta.field!=Field.row_mappings||meta.len!=old.len { return false; }
 let a: const blot_eval_type_evidence::RowMapping& =old[0]; let b: const blot_eval_type_evidence::RowMapping& =pool_row_mappings[meta.start]; return a .== b;
}
fn retained_row_mappings(self_: Builder&,old: const blot_eval_type_evidence::RowMapping[:]) -> const blot_eval_type_evidence::RowMapping[:],Error {
 let previous .=self_.previous;if !previous {return default<const blot_eval_type_evidence::RowMapping[:]>(),blot_error::Error.invalid_artifact;}let ref=previous.values[15]; let error=retain(ref); if error!=blot_error::Error.none { return default<const blot_eval_type_evidence::RowMapping[:]>(),error; }
 let meta=lease_meta[ref.index-1];
 assert(meta.field==Field.row_mappings && meta.len==old.len && meta.len>0 && meta.start>=0 && meta.start<=pool_row_mappings.len && meta.len<=pool_row_mappings.len-meta.start);
 let items=pool_row_mappings[meta.start..meta.start+meta.len];assert(blot_support::same_slice_identity(items,old));
 self_.leases.values[15]=ref; self_.stats.shared_fields++; self_.stats.shared_bytes+=bytes_of(old).len; return items,blot_error::Error.none;
}
fn dupe_row_mappings(self_: Builder&,source: const blot_eval_type_evidence::RowMapping[:],previous: const blot_eval_type_evidence::RowMapping[:]) -> const blot_eval_type_evidence::RowMapping[:],Error {
 if shareable_row_mappings(self_,previous)&&blot_structural::equal(source,previous) { return retained_row_mappings(self_,previous); }
 let items,error=alloc_row_mappings(self_,source.len); if error!=blot_error::Error.none { return default<const blot_eval_type_evidence::RowMapping[:]>(),error; } for value,index in source { items[index]=value; } return items,blot_error::Error.none;
}
fn converted_row_mappings<C,F>(self_: Builder&,len: i64,context: C&,previous: const blot_eval_type_evidence::RowMapping[:]) -> const blot_eval_type_evidence::RowMapping[:],Error {
 if shareable_row_mappings(self_,previous)&&previous.len==len {
  var same=true; for item,index in previous { if !blot_structural::equal(item,F(context,index)) { same=false; break; } } if same { return retained_row_mappings(self_,previous); }
 }
 let items,error=alloc_row_mappings(self_,len); if error!=blot_error::Error.none { return default<const blot_eval_type_evidence::RowMapping[:]>(),error; } for index in 0..len { items[index]=F(context,index); } return items,blot_error::Error.none;
}
fn free_row_mappings(leases: const Leases&,items: const blot_eval_type_evidence::RowMapping[:]) -> Error {
 let ref=leases.values[15]; if ref.index!=0 { return release(ref); }
 if items.len!=0 {pool_row_mappings.free_slice(items);} return blot_error::Error.none;
}

fn alloc_evidence_nodes(self_: Builder&,len: i64) -> blot_eval_type_evidence::Node[:],Error {
 if self_.leases.values[16].index!=0||len<0 { return default<blot_eval_type_evidence::Node[:]>(),blot_error::Error.invalid_artifact; }
 if len==0 { return default<blot_eval_type_evidence::Node[:]>(),blot_error::Error.none; }
 if next_generation==0xffffffffffffffff { return default<blot_eval_type_evidence::Node[:]>(),blot_error::Error.artifact_limit; }
 let items=pool_evidence_nodes.alloc_slice(len); let first: const blot_eval_type_evidence::Node& =items[0]; let start=pool_evidence_nodes.index_of(first);
 let ref,error=create(Field.evidence_nodes,start,len); if error!=blot_error::Error.none { pool_evidence_nodes.free_slice(items); return default<blot_eval_type_evidence::Node[:]>(),error; }
 self_.leases.values[16]=ref; self_.stats.copied_fields++; self_.stats.copied_bytes+=bytes_of(items).len; return items,blot_error::Error.none;
}
fn shareable_evidence_nodes(self_: const Builder&,old: const blot_eval_type_evidence::Node[:]) -> bool {
 if old.len==0 {return false;}let previous .=self_.previous;if !previous {return false;}
 let ref=previous.values[16]; if !valid(ref) { return false; } let meta=lease_meta[ref.index-1];
 if meta.field!=Field.evidence_nodes||meta.len!=old.len { return false; }
 let a: const blot_eval_type_evidence::Node& =old[0]; let b: const blot_eval_type_evidence::Node& =pool_evidence_nodes[meta.start]; return a .== b;
}
fn retained_evidence_nodes(self_: Builder&,old: const blot_eval_type_evidence::Node[:]) -> const blot_eval_type_evidence::Node[:],Error {
 let previous .=self_.previous;if !previous {return default<const blot_eval_type_evidence::Node[:]>(),blot_error::Error.invalid_artifact;}let ref=previous.values[16]; let error=retain(ref); if error!=blot_error::Error.none { return default<const blot_eval_type_evidence::Node[:]>(),error; }
 let meta=lease_meta[ref.index-1];
 assert(meta.field==Field.evidence_nodes && meta.len==old.len && meta.len>0 && meta.start>=0 && meta.start<=pool_evidence_nodes.len && meta.len<=pool_evidence_nodes.len-meta.start);
 let items=pool_evidence_nodes[meta.start..meta.start+meta.len];assert(blot_support::same_slice_identity(items,old));
 self_.leases.values[16]=ref; self_.stats.shared_fields++; self_.stats.shared_bytes+=bytes_of(old).len; return items,blot_error::Error.none;
}
fn dupe_evidence_nodes(self_: Builder&,source: const blot_eval_type_evidence::Node[:],previous: const blot_eval_type_evidence::Node[:]) -> const blot_eval_type_evidence::Node[:],Error {
 if shareable_evidence_nodes(self_,previous)&&blot_structural::equal(source,previous) { return retained_evidence_nodes(self_,previous); }
 let items,error=alloc_evidence_nodes(self_,source.len); if error!=blot_error::Error.none { return default<const blot_eval_type_evidence::Node[:]>(),error; } for value,index in source { items[index]=value; } return items,blot_error::Error.none;
}
fn converted_evidence_nodes<C,F>(self_: Builder&,len: i64,context: C&,previous: const blot_eval_type_evidence::Node[:]) -> const blot_eval_type_evidence::Node[:],Error {
 if shareable_evidence_nodes(self_,previous)&&previous.len==len {
  var same=true; for item,index in previous { if !blot_structural::equal(item,F(context,index)) { same=false; break; } } if same { return retained_evidence_nodes(self_,previous); }
 }
 let items,error=alloc_evidence_nodes(self_,len); if error!=blot_error::Error.none { return default<const blot_eval_type_evidence::Node[:]>(),error; } for index in 0..len { items[index]=F(context,index); } return items,blot_error::Error.none;
}
fn free_evidence_nodes(leases: const Leases&,items: const blot_eval_type_evidence::Node[:]) -> Error {
 let ref=leases.values[16]; if ref.index!=0 { return release(ref); }
 if items.len!=0 {pool_evidence_nodes.free_slice(items);} return blot_error::Error.none;
}

fn alloc_evidence_extra(self_: Builder&,len: i64) -> u32[:],Error {
 if self_.leases.values[17].index!=0||len<0 { return default<u32[:]>(),blot_error::Error.invalid_artifact; }
 if len==0 { return default<u32[:]>(),blot_error::Error.none; }
 if next_generation==0xffffffffffffffff { return default<u32[:]>(),blot_error::Error.artifact_limit; }
 let items=pool_evidence_extra.alloc_slice(len); let first: const u32& =items[0]; let start=pool_evidence_extra.index_of(first);
 let ref,error=create(Field.evidence_extra,start,len); if error!=blot_error::Error.none { pool_evidence_extra.free_slice(items); return default<u32[:]>(),error; }
 self_.leases.values[17]=ref; self_.stats.copied_fields++; self_.stats.copied_bytes+=bytes_of(items).len; return items,blot_error::Error.none;
}
fn shareable_evidence_extra(self_: const Builder&,old: const u32[:]) -> bool {
 if old.len==0 {return false;}let previous .=self_.previous;if !previous {return false;}
 let ref=previous.values[17]; if !valid(ref) { return false; } let meta=lease_meta[ref.index-1];
 if meta.field!=Field.evidence_extra||meta.len!=old.len { return false; }
 let a: const u32& =old[0]; let b: const u32& =pool_evidence_extra[meta.start]; return a .== b;
}
fn retained_evidence_extra(self_: Builder&,old: const u32[:]) -> const u32[:],Error {
 let previous .=self_.previous;if !previous {return default<const u32[:]>(),blot_error::Error.invalid_artifact;}let ref=previous.values[17]; let error=retain(ref); if error!=blot_error::Error.none { return default<const u32[:]>(),error; }
 let meta=lease_meta[ref.index-1];
 assert(meta.field==Field.evidence_extra && meta.len==old.len && meta.len>0 && meta.start>=0 && meta.start<=pool_evidence_extra.len && meta.len<=pool_evidence_extra.len-meta.start);
 let items=pool_evidence_extra[meta.start..meta.start+meta.len];assert(blot_support::same_slice_identity(items,old));
 self_.leases.values[17]=ref; self_.stats.shared_fields++; self_.stats.shared_bytes+=bytes_of(old).len; return items,blot_error::Error.none;
}
fn dupe_evidence_extra(self_: Builder&,source: const u32[:],previous: const u32[:]) -> const u32[:],Error {
 if shareable_evidence_extra(self_,previous)&&blot_structural::equal(source,previous) { return retained_evidence_extra(self_,previous); }
 let items,error=alloc_evidence_extra(self_,source.len); if error!=blot_error::Error.none { return default<const u32[:]>(),error; } for value,index in source { items[index]=value; } return items,blot_error::Error.none;
}
fn converted_evidence_extra<C,F>(self_: Builder&,len: i64,context: C&,previous: const u32[:]) -> const u32[:],Error {
 if shareable_evidence_extra(self_,previous)&&previous.len==len {
  var same=true; for item,index in previous { if !blot_structural::equal(item,F(context,index)) { same=false; break; } } if same { return retained_evidence_extra(self_,previous); }
 }
 let items,error=alloc_evidence_extra(self_,len); if error!=blot_error::Error.none { return default<const u32[:]>(),error; } for index in 0..len { items[index]=F(context,index); } return items,blot_error::Error.none;
}
fn free_evidence_extra(leases: const Leases&,items: const u32[:]) -> Error {
 let ref=leases.values[17]; if ref.index!=0 { return release(ref); }
 if items.len!=0 {pool_evidence_extra.free_slice(items);} return blot_error::Error.none;
}

fn alloc_evidence_quantifier_goals(self_: Builder&,len: i64) -> blot_eval_type_evidence::QuantifierGoals[:],Error {
 if self_.leases.values[18].index!=0||len<0 { return default<blot_eval_type_evidence::QuantifierGoals[:]>(),blot_error::Error.invalid_artifact; }
 if len==0 { return default<blot_eval_type_evidence::QuantifierGoals[:]>(),blot_error::Error.none; }
 if next_generation==0xffffffffffffffff { return default<blot_eval_type_evidence::QuantifierGoals[:]>(),blot_error::Error.artifact_limit; }
 let items=pool_evidence_quantifier_goals.alloc_slice(len); let first: const blot_eval_type_evidence::QuantifierGoals& =items[0]; let start=pool_evidence_quantifier_goals.index_of(first);
 let ref,error=create(Field.evidence_quantifier_goals,start,len); if error!=blot_error::Error.none { pool_evidence_quantifier_goals.free_slice(items); return default<blot_eval_type_evidence::QuantifierGoals[:]>(),error; }
 self_.leases.values[18]=ref; self_.stats.copied_fields++; self_.stats.copied_bytes+=bytes_of(items).len; return items,blot_error::Error.none;
}
fn shareable_evidence_quantifier_goals(self_: const Builder&,old: const blot_eval_type_evidence::QuantifierGoals[:]) -> bool {
 if old.len==0 {return false;}let previous .=self_.previous;if !previous {return false;}
 let ref=previous.values[18]; if !valid(ref) { return false; } let meta=lease_meta[ref.index-1];
 if meta.field!=Field.evidence_quantifier_goals||meta.len!=old.len { return false; }
 let a: const blot_eval_type_evidence::QuantifierGoals& =old[0]; let b: const blot_eval_type_evidence::QuantifierGoals& =pool_evidence_quantifier_goals[meta.start]; return a .== b;
}
fn retained_evidence_quantifier_goals(self_: Builder&,old: const blot_eval_type_evidence::QuantifierGoals[:]) -> const blot_eval_type_evidence::QuantifierGoals[:],Error {
 let previous .=self_.previous;if !previous {return default<const blot_eval_type_evidence::QuantifierGoals[:]>(),blot_error::Error.invalid_artifact;}let ref=previous.values[18]; let error=retain(ref); if error!=blot_error::Error.none { return default<const blot_eval_type_evidence::QuantifierGoals[:]>(),error; }
 let meta=lease_meta[ref.index-1];
 assert(meta.field==Field.evidence_quantifier_goals && meta.len==old.len && meta.len>0 && meta.start>=0 && meta.start<=pool_evidence_quantifier_goals.len && meta.len<=pool_evidence_quantifier_goals.len-meta.start);
 let items=pool_evidence_quantifier_goals[meta.start..meta.start+meta.len];assert(blot_support::same_slice_identity(items,old));
 self_.leases.values[18]=ref; self_.stats.shared_fields++; self_.stats.shared_bytes+=bytes_of(old).len; return items,blot_error::Error.none;
}
fn dupe_evidence_quantifier_goals(self_: Builder&,source: const blot_eval_type_evidence::QuantifierGoals[:],previous: const blot_eval_type_evidence::QuantifierGoals[:]) -> const blot_eval_type_evidence::QuantifierGoals[:],Error {
 if shareable_evidence_quantifier_goals(self_,previous)&&blot_structural::equal(source,previous) { return retained_evidence_quantifier_goals(self_,previous); }
 let items,error=alloc_evidence_quantifier_goals(self_,source.len); if error!=blot_error::Error.none { return default<const blot_eval_type_evidence::QuantifierGoals[:]>(),error; } for value,index in source { items[index]=value; } return items,blot_error::Error.none;
}
fn converted_evidence_quantifier_goals<C,F>(self_: Builder&,len: i64,context: C&,previous: const blot_eval_type_evidence::QuantifierGoals[:]) -> const blot_eval_type_evidence::QuantifierGoals[:],Error {
 if shareable_evidence_quantifier_goals(self_,previous)&&previous.len==len {
  var same=true; for item,index in previous { if !blot_structural::equal(item,F(context,index)) { same=false; break; } } if same { return retained_evidence_quantifier_goals(self_,previous); }
 }
 let items,error=alloc_evidence_quantifier_goals(self_,len); if error!=blot_error::Error.none { return default<const blot_eval_type_evidence::QuantifierGoals[:]>(),error; } for index in 0..len { items[index]=F(context,index); } return items,blot_error::Error.none;
}
fn free_evidence_quantifier_goals(leases: const Leases&,items: const blot_eval_type_evidence::QuantifierGoals[:]) -> Error {
 let ref=leases.values[18]; if ref.index!=0 { return release(ref); }
 if items.len!=0 {pool_evidence_quantifier_goals.free_slice(items);} return blot_error::Error.none;
}

fn alloc_evidence_quantifier_obligations(self_: Builder&,len: i64) -> blot_eval_type_evidence::Goal[:],Error {
 if self_.leases.values[19].index!=0||len<0 { return default<blot_eval_type_evidence::Goal[:]>(),blot_error::Error.invalid_artifact; }
 if len==0 { return default<blot_eval_type_evidence::Goal[:]>(),blot_error::Error.none; }
 if next_generation==0xffffffffffffffff { return default<blot_eval_type_evidence::Goal[:]>(),blot_error::Error.artifact_limit; }
 let items=pool_evidence_quantifier_obligations.alloc_slice(len); let first: const blot_eval_type_evidence::Goal& =items[0]; let start=pool_evidence_quantifier_obligations.index_of(first);
 let ref,error=create(Field.evidence_quantifier_obligations,start,len); if error!=blot_error::Error.none { pool_evidence_quantifier_obligations.free_slice(items); return default<blot_eval_type_evidence::Goal[:]>(),error; }
 self_.leases.values[19]=ref; self_.stats.copied_fields++; self_.stats.copied_bytes+=bytes_of(items).len; return items,blot_error::Error.none;
}
fn shareable_evidence_quantifier_obligations(self_: const Builder&,old: const blot_eval_type_evidence::Goal[:]) -> bool {
 if old.len==0 {return false;}let previous .=self_.previous;if !previous {return false;}
 let ref=previous.values[19]; if !valid(ref) { return false; } let meta=lease_meta[ref.index-1];
 if meta.field!=Field.evidence_quantifier_obligations||meta.len!=old.len { return false; }
 let a: const blot_eval_type_evidence::Goal& =old[0]; let b: const blot_eval_type_evidence::Goal& =pool_evidence_quantifier_obligations[meta.start]; return a .== b;
}
fn retained_evidence_quantifier_obligations(self_: Builder&,old: const blot_eval_type_evidence::Goal[:]) -> const blot_eval_type_evidence::Goal[:],Error {
 let previous .=self_.previous;if !previous {return default<const blot_eval_type_evidence::Goal[:]>(),blot_error::Error.invalid_artifact;}let ref=previous.values[19]; let error=retain(ref); if error!=blot_error::Error.none { return default<const blot_eval_type_evidence::Goal[:]>(),error; }
 let meta=lease_meta[ref.index-1];
 assert(meta.field==Field.evidence_quantifier_obligations && meta.len==old.len && meta.len>0 && meta.start>=0 && meta.start<=pool_evidence_quantifier_obligations.len && meta.len<=pool_evidence_quantifier_obligations.len-meta.start);
 let items=pool_evidence_quantifier_obligations[meta.start..meta.start+meta.len];assert(blot_support::same_slice_identity(items,old));
 self_.leases.values[19]=ref; self_.stats.shared_fields++; self_.stats.shared_bytes+=bytes_of(old).len; return items,blot_error::Error.none;
}
fn dupe_evidence_quantifier_obligations(self_: Builder&,source: const blot_eval_type_evidence::Goal[:],previous: const blot_eval_type_evidence::Goal[:]) -> const blot_eval_type_evidence::Goal[:],Error {
 if shareable_evidence_quantifier_obligations(self_,previous)&&blot_structural::equal(source,previous) { return retained_evidence_quantifier_obligations(self_,previous); }
 let items,error=alloc_evidence_quantifier_obligations(self_,source.len); if error!=blot_error::Error.none { return default<const blot_eval_type_evidence::Goal[:]>(),error; } for value,index in source { items[index]=value; } return items,blot_error::Error.none;
}
fn converted_evidence_quantifier_obligations<C,F>(self_: Builder&,len: i64,context: C&,previous: const blot_eval_type_evidence::Goal[:]) -> const blot_eval_type_evidence::Goal[:],Error {
 if shareable_evidence_quantifier_obligations(self_,previous)&&previous.len==len {
  var same=true; for item,index in previous { if !blot_structural::equal(item,F(context,index)) { same=false; break; } } if same { return retained_evidence_quantifier_obligations(self_,previous); }
 }
 let items,error=alloc_evidence_quantifier_obligations(self_,len); if error!=blot_error::Error.none { return default<const blot_eval_type_evidence::Goal[:]>(),error; } for index in 0..len { items[index]=F(context,index); } return items,blot_error::Error.none;
}
fn free_evidence_quantifier_obligations(leases: const Leases&,items: const blot_eval_type_evidence::Goal[:]) -> Error {
 let ref=leases.values[19]; if ref.index!=0 { return release(ref); }
 if items.len!=0 {pool_evidence_quantifier_obligations.free_slice(items);} return blot_error::Error.none;
}

fn alloc_evidence_operations(self_: Builder&,len: i64) -> blot_check_effect_evidence::Operation[:],Error {
 if self_.leases.values[20].index!=0||len<0 { return default<blot_check_effect_evidence::Operation[:]>(),blot_error::Error.invalid_artifact; }
 if len==0 { return default<blot_check_effect_evidence::Operation[:]>(),blot_error::Error.none; }
 if next_generation==0xffffffffffffffff { return default<blot_check_effect_evidence::Operation[:]>(),blot_error::Error.artifact_limit; }
 let items=pool_evidence_operations.alloc_slice(len); let first: const blot_check_effect_evidence::Operation& =items[0]; let start=pool_evidence_operations.index_of(first);
 let ref,error=create(Field.evidence_operations,start,len); if error!=blot_error::Error.none { pool_evidence_operations.free_slice(items); return default<blot_check_effect_evidence::Operation[:]>(),error; }
 self_.leases.values[20]=ref; self_.stats.copied_fields++; self_.stats.copied_bytes+=bytes_of(items).len; return items,blot_error::Error.none;
}
fn shareable_evidence_operations(self_: const Builder&,old: const blot_check_effect_evidence::Operation[:]) -> bool {
 if old.len==0 {return false;}let previous .=self_.previous;if !previous {return false;}
 let ref=previous.values[20]; if !valid(ref) { return false; } let meta=lease_meta[ref.index-1];
 if meta.field!=Field.evidence_operations||meta.len!=old.len { return false; }
 let a: const blot_check_effect_evidence::Operation& =old[0]; let b: const blot_check_effect_evidence::Operation& =pool_evidence_operations[meta.start]; return a .== b;
}
fn retained_evidence_operations(self_: Builder&,old: const blot_check_effect_evidence::Operation[:]) -> const blot_check_effect_evidence::Operation[:],Error {
 let previous .=self_.previous;if !previous {return default<const blot_check_effect_evidence::Operation[:]>(),blot_error::Error.invalid_artifact;}let ref=previous.values[20]; let error=retain(ref); if error!=blot_error::Error.none { return default<const blot_check_effect_evidence::Operation[:]>(),error; }
 let meta=lease_meta[ref.index-1];
 assert(meta.field==Field.evidence_operations && meta.len==old.len && meta.len>0 && meta.start>=0 && meta.start<=pool_evidence_operations.len && meta.len<=pool_evidence_operations.len-meta.start);
 let items=pool_evidence_operations[meta.start..meta.start+meta.len];assert(blot_support::same_slice_identity(items,old));
 self_.leases.values[20]=ref; self_.stats.shared_fields++; self_.stats.shared_bytes+=bytes_of(old).len; return items,blot_error::Error.none;
}
fn dupe_evidence_operations(self_: Builder&,source: const blot_check_effect_evidence::Operation[:],previous: const blot_check_effect_evidence::Operation[:]) -> const blot_check_effect_evidence::Operation[:],Error {
 if shareable_evidence_operations(self_,previous)&&blot_structural::equal(source,previous) { return retained_evidence_operations(self_,previous); }
 let items,error=alloc_evidence_operations(self_,source.len); if error!=blot_error::Error.none { return default<const blot_check_effect_evidence::Operation[:]>(),error; } for value,index in source { items[index]=value; } return items,blot_error::Error.none;
}
fn converted_evidence_operations<C,F>(self_: Builder&,len: i64,context: C&,previous: const blot_check_effect_evidence::Operation[:]) -> const blot_check_effect_evidence::Operation[:],Error {
 if shareable_evidence_operations(self_,previous)&&previous.len==len {
  var same=true; for item,index in previous { if !blot_structural::equal(item,F(context,index)) { same=false; break; } } if same { return retained_evidence_operations(self_,previous); }
 }
 let items,error=alloc_evidence_operations(self_,len); if error!=blot_error::Error.none { return default<const blot_check_effect_evidence::Operation[:]>(),error; } for index in 0..len { items[index]=F(context,index); } return items,blot_error::Error.none;
}
fn free_evidence_operations(leases: const Leases&,items: const blot_check_effect_evidence::Operation[:]) -> Error {
 let ref=leases.values[20]; if ref.index!=0 { return release(ref); }
 if items.len!=0 {pool_evidence_operations.free_slice(items);} return blot_error::Error.none;
}

fn alloc_evidence_arguments(self_: Builder&,len: i64) -> u32[:],Error {
 if self_.leases.values[21].index!=0||len<0 { return default<u32[:]>(),blot_error::Error.invalid_artifact; }
 if len==0 { return default<u32[:]>(),blot_error::Error.none; }
 if next_generation==0xffffffffffffffff { return default<u32[:]>(),blot_error::Error.artifact_limit; }
 let items=pool_evidence_arguments.alloc_slice(len); let first: const u32& =items[0]; let start=pool_evidence_arguments.index_of(first);
 let ref,error=create(Field.evidence_arguments,start,len); if error!=blot_error::Error.none { pool_evidence_arguments.free_slice(items); return default<u32[:]>(),error; }
 self_.leases.values[21]=ref; self_.stats.copied_fields++; self_.stats.copied_bytes+=bytes_of(items).len; return items,blot_error::Error.none;
}
fn shareable_evidence_arguments(self_: const Builder&,old: const u32[:]) -> bool {
 if old.len==0 {return false;}let previous .=self_.previous;if !previous {return false;}
 let ref=previous.values[21]; if !valid(ref) { return false; } let meta=lease_meta[ref.index-1];
 if meta.field!=Field.evidence_arguments||meta.len!=old.len { return false; }
 let a: const u32& =old[0]; let b: const u32& =pool_evidence_arguments[meta.start]; return a .== b;
}
fn retained_evidence_arguments(self_: Builder&,old: const u32[:]) -> const u32[:],Error {
 let previous .=self_.previous;if !previous {return default<const u32[:]>(),blot_error::Error.invalid_artifact;}let ref=previous.values[21]; let error=retain(ref); if error!=blot_error::Error.none { return default<const u32[:]>(),error; }
 let meta=lease_meta[ref.index-1];
 assert(meta.field==Field.evidence_arguments && meta.len==old.len && meta.len>0 && meta.start>=0 && meta.start<=pool_evidence_arguments.len && meta.len<=pool_evidence_arguments.len-meta.start);
 let items=pool_evidence_arguments[meta.start..meta.start+meta.len];assert(blot_support::same_slice_identity(items,old));
 self_.leases.values[21]=ref; self_.stats.shared_fields++; self_.stats.shared_bytes+=bytes_of(old).len; return items,blot_error::Error.none;
}
fn dupe_evidence_arguments(self_: Builder&,source: const u32[:],previous: const u32[:]) -> const u32[:],Error {
 if shareable_evidence_arguments(self_,previous)&&blot_structural::equal(source,previous) { return retained_evidence_arguments(self_,previous); }
 let items,error=alloc_evidence_arguments(self_,source.len); if error!=blot_error::Error.none { return default<const u32[:]>(),error; } for value,index in source { items[index]=value; } return items,blot_error::Error.none;
}
fn converted_evidence_arguments<C,F>(self_: Builder&,len: i64,context: C&,previous: const u32[:]) -> const u32[:],Error {
 if shareable_evidence_arguments(self_,previous)&&previous.len==len {
  var same=true; for item,index in previous { if !blot_structural::equal(item,F(context,index)) { same=false; break; } } if same { return retained_evidence_arguments(self_,previous); }
 }
 let items,error=alloc_evidence_arguments(self_,len); if error!=blot_error::Error.none { return default<const u32[:]>(),error; } for index in 0..len { items[index]=F(context,index); } return items,blot_error::Error.none;
}
fn free_evidence_arguments(leases: const Leases&,items: const u32[:]) -> Error {
 let ref=leases.values[21]; if ref.index!=0 { return release(ref); }
 if items.len!=0 {pool_evidence_arguments.free_slice(items);} return blot_error::Error.none;
}

fn alloc_evidence_rows(self_: Builder&,len: i64) -> blot_check_effect_evidence::Row[:],Error {
 if self_.leases.values[22].index!=0||len<0 { return default<blot_check_effect_evidence::Row[:]>(),blot_error::Error.invalid_artifact; }
 if len==0 { return default<blot_check_effect_evidence::Row[:]>(),blot_error::Error.none; }
 if next_generation==0xffffffffffffffff { return default<blot_check_effect_evidence::Row[:]>(),blot_error::Error.artifact_limit; }
 let items=pool_evidence_rows.alloc_slice(len); let first: const blot_check_effect_evidence::Row& =items[0]; let start=pool_evidence_rows.index_of(first);
 let ref,error=create(Field.evidence_rows,start,len); if error!=blot_error::Error.none { pool_evidence_rows.free_slice(items); return default<blot_check_effect_evidence::Row[:]>(),error; }
 self_.leases.values[22]=ref; self_.stats.copied_fields++; self_.stats.copied_bytes+=bytes_of(items).len; return items,blot_error::Error.none;
}
fn shareable_evidence_rows(self_: const Builder&,old: const blot_check_effect_evidence::Row[:]) -> bool {
 if old.len==0 {return false;}let previous .=self_.previous;if !previous {return false;}
 let ref=previous.values[22]; if !valid(ref) { return false; } let meta=lease_meta[ref.index-1];
 if meta.field!=Field.evidence_rows||meta.len!=old.len { return false; }
 let a: const blot_check_effect_evidence::Row& =old[0]; let b: const blot_check_effect_evidence::Row& =pool_evidence_rows[meta.start]; return a .== b;
}
fn retained_evidence_rows(self_: Builder&,old: const blot_check_effect_evidence::Row[:]) -> const blot_check_effect_evidence::Row[:],Error {
 let previous .=self_.previous;if !previous {return default<const blot_check_effect_evidence::Row[:]>(),blot_error::Error.invalid_artifact;}let ref=previous.values[22]; let error=retain(ref); if error!=blot_error::Error.none { return default<const blot_check_effect_evidence::Row[:]>(),error; }
 let meta=lease_meta[ref.index-1];
 assert(meta.field==Field.evidence_rows && meta.len==old.len && meta.len>0 && meta.start>=0 && meta.start<=pool_evidence_rows.len && meta.len<=pool_evidence_rows.len-meta.start);
 let items=pool_evidence_rows[meta.start..meta.start+meta.len];assert(blot_support::same_slice_identity(items,old));
 self_.leases.values[22]=ref; self_.stats.shared_fields++; self_.stats.shared_bytes+=bytes_of(old).len; return items,blot_error::Error.none;
}
fn dupe_evidence_rows(self_: Builder&,source: const blot_check_effect_evidence::Row[:],previous: const blot_check_effect_evidence::Row[:]) -> const blot_check_effect_evidence::Row[:],Error {
 if shareable_evidence_rows(self_,previous)&&blot_structural::equal(source,previous) { return retained_evidence_rows(self_,previous); }
 let items,error=alloc_evidence_rows(self_,source.len); if error!=blot_error::Error.none { return default<const blot_check_effect_evidence::Row[:]>(),error; } for value,index in source { items[index]=value; } return items,blot_error::Error.none;
}
fn converted_evidence_rows<C,F>(self_: Builder&,len: i64,context: C&,previous: const blot_check_effect_evidence::Row[:]) -> const blot_check_effect_evidence::Row[:],Error {
 if shareable_evidence_rows(self_,previous)&&previous.len==len {
  var same=true; for item,index in previous { if !blot_structural::equal(item,F(context,index)) { same=false; break; } } if same { return retained_evidence_rows(self_,previous); }
 }
 let items,error=alloc_evidence_rows(self_,len); if error!=blot_error::Error.none { return default<const blot_check_effect_evidence::Row[:]>(),error; } for index in 0..len { items[index]=F(context,index); } return items,blot_error::Error.none;
}
fn free_evidence_rows(leases: const Leases&,items: const blot_check_effect_evidence::Row[:]) -> Error {
 let ref=leases.values[22]; if ref.index!=0 { return release(ref); }
 if items.len!=0 {pool_evidence_rows.free_slice(items);} return blot_error::Error.none;
}

fn alloc_evidence_labels(self_: Builder&,len: i64) -> u32[:],Error {
 if self_.leases.values[23].index!=0||len<0 { return default<u32[:]>(),blot_error::Error.invalid_artifact; }
 if len==0 { return default<u32[:]>(),blot_error::Error.none; }
 if next_generation==0xffffffffffffffff { return default<u32[:]>(),blot_error::Error.artifact_limit; }
 let items=pool_evidence_labels.alloc_slice(len); let first: const u32& =items[0]; let start=pool_evidence_labels.index_of(first);
 let ref,error=create(Field.evidence_labels,start,len); if error!=blot_error::Error.none { pool_evidence_labels.free_slice(items); return default<u32[:]>(),error; }
 self_.leases.values[23]=ref; self_.stats.copied_fields++; self_.stats.copied_bytes+=bytes_of(items).len; return items,blot_error::Error.none;
}
fn shareable_evidence_labels(self_: const Builder&,old: const u32[:]) -> bool {
 if old.len==0 {return false;}let previous .=self_.previous;if !previous {return false;}
 let ref=previous.values[23]; if !valid(ref) { return false; } let meta=lease_meta[ref.index-1];
 if meta.field!=Field.evidence_labels||meta.len!=old.len { return false; }
 let a: const u32& =old[0]; let b: const u32& =pool_evidence_labels[meta.start]; return a .== b;
}
fn retained_evidence_labels(self_: Builder&,old: const u32[:]) -> const u32[:],Error {
 let previous .=self_.previous;if !previous {return default<const u32[:]>(),blot_error::Error.invalid_artifact;}let ref=previous.values[23]; let error=retain(ref); if error!=blot_error::Error.none { return default<const u32[:]>(),error; }
 let meta=lease_meta[ref.index-1];
 assert(meta.field==Field.evidence_labels && meta.len==old.len && meta.len>0 && meta.start>=0 && meta.start<=pool_evidence_labels.len && meta.len<=pool_evidence_labels.len-meta.start);
 let items=pool_evidence_labels[meta.start..meta.start+meta.len];assert(blot_support::same_slice_identity(items,old));
 self_.leases.values[23]=ref; self_.stats.shared_fields++; self_.stats.shared_bytes+=bytes_of(old).len; return items,blot_error::Error.none;
}
fn dupe_evidence_labels(self_: Builder&,source: const u32[:],previous: const u32[:]) -> const u32[:],Error {
 if shareable_evidence_labels(self_,previous)&&blot_structural::equal(source,previous) { return retained_evidence_labels(self_,previous); }
 let items,error=alloc_evidence_labels(self_,source.len); if error!=blot_error::Error.none { return default<const u32[:]>(),error; } for value,index in source { items[index]=value; } return items,blot_error::Error.none;
}
fn converted_evidence_labels<C,F>(self_: Builder&,len: i64,context: C&,previous: const u32[:]) -> const u32[:],Error {
 if shareable_evidence_labels(self_,previous)&&previous.len==len {
  var same=true; for item,index in previous { if !blot_structural::equal(item,F(context,index)) { same=false; break; } } if same { return retained_evidence_labels(self_,previous); }
 }
 let items,error=alloc_evidence_labels(self_,len); if error!=blot_error::Error.none { return default<const u32[:]>(),error; } for index in 0..len { items[index]=F(context,index); } return items,blot_error::Error.none;
}
fn free_evidence_labels(leases: const Leases&,items: const u32[:]) -> Error {
 let ref=leases.values[23]; if ref.index!=0 { return release(ref); }
 if items.len!=0 {pool_evidence_labels.free_slice(items);} return blot_error::Error.none;
}

fn alloc_value_records(self_: Builder&,len: i64) -> u32[:],Error {
 if self_.leases.values[24].index!=0||len<0 { return default<u32[:]>(),blot_error::Error.invalid_artifact; }
 if len==0 { return default<u32[:]>(),blot_error::Error.none; }
 if next_generation==0xffffffffffffffff { return default<u32[:]>(),blot_error::Error.artifact_limit; }
 let items=pool_value_records.alloc_slice(len); let first: const u32& =items[0]; let start=pool_value_records.index_of(first);
 let ref,error=create(Field.value_records,start,len); if error!=blot_error::Error.none { pool_value_records.free_slice(items); return default<u32[:]>(),error; }
 self_.leases.values[24]=ref; self_.stats.copied_fields++; self_.stats.copied_bytes+=bytes_of(items).len; return items,blot_error::Error.none;
}
fn shareable_value_records(self_: const Builder&,old: const u32[:]) -> bool {
 if old.len==0 {return false;}let previous .=self_.previous;if !previous {return false;}
 let ref=previous.values[24]; if !valid(ref) { return false; } let meta=lease_meta[ref.index-1];
 if meta.field!=Field.value_records||meta.len!=old.len { return false; }
 let a: const u32& =old[0]; let b: const u32& =pool_value_records[meta.start]; return a .== b;
}
fn retained_value_records(self_: Builder&,old: const u32[:]) -> const u32[:],Error {
 let previous .=self_.previous;if !previous {return default<const u32[:]>(),blot_error::Error.invalid_artifact;}let ref=previous.values[24]; let error=retain(ref); if error!=blot_error::Error.none { return default<const u32[:]>(),error; }
 let meta=lease_meta[ref.index-1];
 assert(meta.field==Field.value_records && meta.len==old.len && meta.len>0 && meta.start>=0 && meta.start<=pool_value_records.len && meta.len<=pool_value_records.len-meta.start);
 let items=pool_value_records[meta.start..meta.start+meta.len];assert(blot_support::same_slice_identity(items,old));
 self_.leases.values[24]=ref; self_.stats.shared_fields++; self_.stats.shared_bytes+=bytes_of(old).len; return items,blot_error::Error.none;
}
fn dupe_value_records(self_: Builder&,source: const u32[:],previous: const u32[:]) -> const u32[:],Error {
 if shareable_value_records(self_,previous)&&blot_structural::equal(source,previous) { return retained_value_records(self_,previous); }
 let items,error=alloc_value_records(self_,source.len); if error!=blot_error::Error.none { return default<const u32[:]>(),error; } for value,index in source { items[index]=value; } return items,blot_error::Error.none;
}
fn converted_value_records<C,F>(self_: Builder&,len: i64,context: C&,previous: const u32[:]) -> const u32[:],Error {
 if shareable_value_records(self_,previous)&&previous.len==len {
  var same=true; for item,index in previous { if !blot_structural::equal(item,F(context,index)) { same=false; break; } } if same { return retained_value_records(self_,previous); }
 }
 let items,error=alloc_value_records(self_,len); if error!=blot_error::Error.none { return default<const u32[:]>(),error; } for index in 0..len { items[index]=F(context,index); } return items,blot_error::Error.none;
}
fn free_value_records(leases: const Leases&,items: const u32[:]) -> Error {
 let ref=leases.values[24]; if ref.index!=0 { return release(ref); }
 if items.len!=0 {pool_value_records.free_slice(items);} return blot_error::Error.none;
}

fn alloc_record_layouts(self_: Builder&,len: i64) -> blot_check_core::List[:],Error {
 if self_.leases.values[25].index!=0||len<0 { return default<blot_check_core::List[:]>(),blot_error::Error.invalid_artifact; }
 if len==0 { return default<blot_check_core::List[:]>(),blot_error::Error.none; }
 if next_generation==0xffffffffffffffff { return default<blot_check_core::List[:]>(),blot_error::Error.artifact_limit; }
 let items=pool_record_layouts.alloc_slice(len); let first: const blot_check_core::List& =items[0]; let start=pool_record_layouts.index_of(first);
 let ref,error=create(Field.record_layouts,start,len); if error!=blot_error::Error.none { pool_record_layouts.free_slice(items); return default<blot_check_core::List[:]>(),error; }
 self_.leases.values[25]=ref; self_.stats.copied_fields++; self_.stats.copied_bytes+=bytes_of(items).len; return items,blot_error::Error.none;
}
fn shareable_record_layouts(self_: const Builder&,old: const blot_check_core::List[:]) -> bool {
 if old.len==0 {return false;}let previous .=self_.previous;if !previous {return false;}
 let ref=previous.values[25]; if !valid(ref) { return false; } let meta=lease_meta[ref.index-1];
 if meta.field!=Field.record_layouts||meta.len!=old.len { return false; }
 let a: const blot_check_core::List& =old[0]; let b: const blot_check_core::List& =pool_record_layouts[meta.start]; return a .== b;
}
fn retained_record_layouts(self_: Builder&,old: const blot_check_core::List[:]) -> const blot_check_core::List[:],Error {
 let previous .=self_.previous;if !previous {return default<const blot_check_core::List[:]>(),blot_error::Error.invalid_artifact;}let ref=previous.values[25]; let error=retain(ref); if error!=blot_error::Error.none { return default<const blot_check_core::List[:]>(),error; }
 let meta=lease_meta[ref.index-1];
 assert(meta.field==Field.record_layouts && meta.len==old.len && meta.len>0 && meta.start>=0 && meta.start<=pool_record_layouts.len && meta.len<=pool_record_layouts.len-meta.start);
 let items=pool_record_layouts[meta.start..meta.start+meta.len];assert(blot_support::same_slice_identity(items,old));
 self_.leases.values[25]=ref; self_.stats.shared_fields++; self_.stats.shared_bytes+=bytes_of(old).len; return items,blot_error::Error.none;
}
fn dupe_record_layouts(self_: Builder&,source: const blot_check_core::List[:],previous: const blot_check_core::List[:]) -> const blot_check_core::List[:],Error {
 if shareable_record_layouts(self_,previous)&&blot_structural::equal(source,previous) { return retained_record_layouts(self_,previous); }
 let items,error=alloc_record_layouts(self_,source.len); if error!=blot_error::Error.none { return default<const blot_check_core::List[:]>(),error; } for value,index in source { items[index]=value; } return items,blot_error::Error.none;
}
fn converted_record_layouts<C,F>(self_: Builder&,len: i64,context: C&,previous: const blot_check_core::List[:]) -> const blot_check_core::List[:],Error {
 if shareable_record_layouts(self_,previous)&&previous.len==len {
  var same=true; for item,index in previous { if !blot_structural::equal(item,F(context,index)) { same=false; break; } } if same { return retained_record_layouts(self_,previous); }
 }
 let items,error=alloc_record_layouts(self_,len); if error!=blot_error::Error.none { return default<const blot_check_core::List[:]>(),error; } for index in 0..len { items[index]=F(context,index); } return items,blot_error::Error.none;
}
fn free_record_layouts(leases: const Leases&,items: const blot_check_core::List[:]) -> Error {
 let ref=leases.values[25]; if ref.index!=0 { return release(ref); }
 if items.len!=0 {pool_record_layouts.free_slice(items);} return blot_error::Error.none;
}

fn alloc_field_names(self_: Builder&,len: i64) -> u32[:],Error {
 if self_.leases.values[26].index!=0||len<0 { return default<u32[:]>(),blot_error::Error.invalid_artifact; }
 if len==0 { return default<u32[:]>(),blot_error::Error.none; }
 if next_generation==0xffffffffffffffff { return default<u32[:]>(),blot_error::Error.artifact_limit; }
 let items=pool_field_names.alloc_slice(len); let first: const u32& =items[0]; let start=pool_field_names.index_of(first);
 let ref,error=create(Field.field_names,start,len); if error!=blot_error::Error.none { pool_field_names.free_slice(items); return default<u32[:]>(),error; }
 self_.leases.values[26]=ref; self_.stats.copied_fields++; self_.stats.copied_bytes+=bytes_of(items).len; return items,blot_error::Error.none;
}
fn shareable_field_names(self_: const Builder&,old: const u32[:]) -> bool {
 if old.len==0 {return false;}let previous .=self_.previous;if !previous {return false;}
 let ref=previous.values[26]; if !valid(ref) { return false; } let meta=lease_meta[ref.index-1];
 if meta.field!=Field.field_names||meta.len!=old.len { return false; }
 let a: const u32& =old[0]; let b: const u32& =pool_field_names[meta.start]; return a .== b;
}
fn retained_field_names(self_: Builder&,old: const u32[:]) -> const u32[:],Error {
 let previous .=self_.previous;if !previous {return default<const u32[:]>(),blot_error::Error.invalid_artifact;}let ref=previous.values[26]; let error=retain(ref); if error!=blot_error::Error.none { return default<const u32[:]>(),error; }
 let meta=lease_meta[ref.index-1];
 assert(meta.field==Field.field_names && meta.len==old.len && meta.len>0 && meta.start>=0 && meta.start<=pool_field_names.len && meta.len<=pool_field_names.len-meta.start);
 let items=pool_field_names[meta.start..meta.start+meta.len];assert(blot_support::same_slice_identity(items,old));
 self_.leases.values[26]=ref; self_.stats.shared_fields++; self_.stats.shared_bytes+=bytes_of(old).len; return items,blot_error::Error.none;
}
fn dupe_field_names(self_: Builder&,source: const u32[:],previous: const u32[:]) -> const u32[:],Error {
 if shareable_field_names(self_,previous)&&blot_structural::equal(source,previous) { return retained_field_names(self_,previous); }
 let items,error=alloc_field_names(self_,source.len); if error!=blot_error::Error.none { return default<const u32[:]>(),error; } for value,index in source { items[index]=value; } return items,blot_error::Error.none;
}
fn converted_field_names<C,F>(self_: Builder&,len: i64,context: C&,previous: const u32[:]) -> const u32[:],Error {
 if shareable_field_names(self_,previous)&&previous.len==len {
  var same=true; for item,index in previous { if !blot_structural::equal(item,F(context,index)) { same=false; break; } } if same { return retained_field_names(self_,previous); }
 }
 let items,error=alloc_field_names(self_,len); if error!=blot_error::Error.none { return default<const u32[:]>(),error; } for index in 0..len { items[index]=F(context,index); } return items,blot_error::Error.none;
}
fn free_field_names(leases: const Leases&,items: const u32[:]) -> Error {
 let ref=leases.values[26]; if ref.index!=0 { return release(ref); }
 if items.len!=0 {pool_field_names.free_slice(items);} return blot_error::Error.none;
}

fn alloc_implementation_proofs(self_: Builder&,len: i64) -> blot_eval_implementation_evidence::Proof[:],Error {
 if self_.leases.values[27].index!=0||len<0 { return default<blot_eval_implementation_evidence::Proof[:]>(),blot_error::Error.invalid_artifact; }
 if len==0 { return default<blot_eval_implementation_evidence::Proof[:]>(),blot_error::Error.none; }
 if next_generation==0xffffffffffffffff { return default<blot_eval_implementation_evidence::Proof[:]>(),blot_error::Error.artifact_limit; }
 let items=pool_implementation_proofs.alloc_slice(len); let first: const blot_eval_implementation_evidence::Proof& =items[0]; let start=pool_implementation_proofs.index_of(first);
 let ref,error=create(Field.implementation_proofs,start,len); if error!=blot_error::Error.none { pool_implementation_proofs.free_slice(items); return default<blot_eval_implementation_evidence::Proof[:]>(),error; }
 self_.leases.values[27]=ref; self_.stats.copied_fields++; self_.stats.copied_bytes+=bytes_of(items).len; return items,blot_error::Error.none;
}
fn shareable_implementation_proofs(self_: const Builder&,old: const blot_eval_implementation_evidence::Proof[:]) -> bool {
 if old.len==0 {return false;}let previous .=self_.previous;if !previous {return false;}
 let ref=previous.values[27]; if !valid(ref) { return false; } let meta=lease_meta[ref.index-1];
 if meta.field!=Field.implementation_proofs||meta.len!=old.len { return false; }
 let a: const blot_eval_implementation_evidence::Proof& =old[0]; let b: const blot_eval_implementation_evidence::Proof& =pool_implementation_proofs[meta.start]; return a .== b;
}
fn retained_implementation_proofs(self_: Builder&,old: const blot_eval_implementation_evidence::Proof[:]) -> const blot_eval_implementation_evidence::Proof[:],Error {
 let previous .=self_.previous;if !previous {return default<const blot_eval_implementation_evidence::Proof[:]>(),blot_error::Error.invalid_artifact;}let ref=previous.values[27]; let error=retain(ref); if error!=blot_error::Error.none { return default<const blot_eval_implementation_evidence::Proof[:]>(),error; }
 let meta=lease_meta[ref.index-1];
 assert(meta.field==Field.implementation_proofs && meta.len==old.len && meta.len>0 && meta.start>=0 && meta.start<=pool_implementation_proofs.len && meta.len<=pool_implementation_proofs.len-meta.start);
 let items=pool_implementation_proofs[meta.start..meta.start+meta.len];assert(blot_support::same_slice_identity(items,old));
 self_.leases.values[27]=ref; self_.stats.shared_fields++; self_.stats.shared_bytes+=bytes_of(old).len; return items,blot_error::Error.none;
}
fn dupe_implementation_proofs(self_: Builder&,source: const blot_eval_implementation_evidence::Proof[:],previous: const blot_eval_implementation_evidence::Proof[:]) -> const blot_eval_implementation_evidence::Proof[:],Error {
 if shareable_implementation_proofs(self_,previous)&&blot_structural::equal(source,previous) { return retained_implementation_proofs(self_,previous); }
 let items,error=alloc_implementation_proofs(self_,source.len); if error!=blot_error::Error.none { return default<const blot_eval_implementation_evidence::Proof[:]>(),error; } for value,index in source { items[index]=value; } return items,blot_error::Error.none;
}
fn converted_implementation_proofs<C,F>(self_: Builder&,len: i64,context: C&,previous: const blot_eval_implementation_evidence::Proof[:]) -> const blot_eval_implementation_evidence::Proof[:],Error {
 if shareable_implementation_proofs(self_,previous)&&previous.len==len {
  var same=true; for item,index in previous { if !blot_structural::equal(item,F(context,index)) { same=false; break; } } if same { return retained_implementation_proofs(self_,previous); }
 }
 let items,error=alloc_implementation_proofs(self_,len); if error!=blot_error::Error.none { return default<const blot_eval_implementation_evidence::Proof[:]>(),error; } for index in 0..len { items[index]=F(context,index); } return items,blot_error::Error.none;
}
fn free_implementation_proofs(leases: const Leases&,items: const blot_eval_implementation_evidence::Proof[:]) -> Error {
 let ref=leases.values[27]; if ref.index!=0 { return release(ref); }
 if items.len!=0 {pool_implementation_proofs.free_slice(items);} return blot_error::Error.none;
}

fn alloc_implementation_arguments(self_: Builder&,len: i64) -> u32[:],Error {
 if self_.leases.values[28].index!=0||len<0 { return default<u32[:]>(),blot_error::Error.invalid_artifact; }
 if len==0 { return default<u32[:]>(),blot_error::Error.none; }
 if next_generation==0xffffffffffffffff { return default<u32[:]>(),blot_error::Error.artifact_limit; }
 let items=pool_implementation_arguments.alloc_slice(len); let first: const u32& =items[0]; let start=pool_implementation_arguments.index_of(first);
 let ref,error=create(Field.implementation_arguments,start,len); if error!=blot_error::Error.none { pool_implementation_arguments.free_slice(items); return default<u32[:]>(),error; }
 self_.leases.values[28]=ref; self_.stats.copied_fields++; self_.stats.copied_bytes+=bytes_of(items).len; return items,blot_error::Error.none;
}
fn shareable_implementation_arguments(self_: const Builder&,old: const u32[:]) -> bool {
 if old.len==0 {return false;}let previous .=self_.previous;if !previous {return false;}
 let ref=previous.values[28]; if !valid(ref) { return false; } let meta=lease_meta[ref.index-1];
 if meta.field!=Field.implementation_arguments||meta.len!=old.len { return false; }
 let a: const u32& =old[0]; let b: const u32& =pool_implementation_arguments[meta.start]; return a .== b;
}
fn retained_implementation_arguments(self_: Builder&,old: const u32[:]) -> const u32[:],Error {
 let previous .=self_.previous;if !previous {return default<const u32[:]>(),blot_error::Error.invalid_artifact;}let ref=previous.values[28]; let error=retain(ref); if error!=blot_error::Error.none { return default<const u32[:]>(),error; }
 let meta=lease_meta[ref.index-1];
 assert(meta.field==Field.implementation_arguments && meta.len==old.len && meta.len>0 && meta.start>=0 && meta.start<=pool_implementation_arguments.len && meta.len<=pool_implementation_arguments.len-meta.start);
 let items=pool_implementation_arguments[meta.start..meta.start+meta.len];assert(blot_support::same_slice_identity(items,old));
 self_.leases.values[28]=ref; self_.stats.shared_fields++; self_.stats.shared_bytes+=bytes_of(old).len; return items,blot_error::Error.none;
}
fn dupe_implementation_arguments(self_: Builder&,source: const u32[:],previous: const u32[:]) -> const u32[:],Error {
 if shareable_implementation_arguments(self_,previous)&&blot_structural::equal(source,previous) { return retained_implementation_arguments(self_,previous); }
 let items,error=alloc_implementation_arguments(self_,source.len); if error!=blot_error::Error.none { return default<const u32[:]>(),error; } for value,index in source { items[index]=value; } return items,blot_error::Error.none;
}
fn converted_implementation_arguments<C,F>(self_: Builder&,len: i64,context: C&,previous: const u32[:]) -> const u32[:],Error {
 if shareable_implementation_arguments(self_,previous)&&previous.len==len {
  var same=true; for item,index in previous { if !blot_structural::equal(item,F(context,index)) { same=false; break; } } if same { return retained_implementation_arguments(self_,previous); }
 }
 let items,error=alloc_implementation_arguments(self_,len); if error!=blot_error::Error.none { return default<const u32[:]>(),error; } for index in 0..len { items[index]=F(context,index); } return items,blot_error::Error.none;
}
fn free_implementation_arguments(leases: const Leases&,items: const u32[:]) -> Error {
 let ref=leases.values[28]; if ref.index!=0 { return release(ref); }
 if items.len!=0 {pool_implementation_arguments.free_slice(items);} return blot_error::Error.none;
}

fn alloc_implementation_members(self_: Builder&,len: i64) -> blot_eval_implementation_evidence::Member[:],Error {
 if self_.leases.values[29].index!=0||len<0 { return default<blot_eval_implementation_evidence::Member[:]>(),blot_error::Error.invalid_artifact; }
 if len==0 { return default<blot_eval_implementation_evidence::Member[:]>(),blot_error::Error.none; }
 if next_generation==0xffffffffffffffff { return default<blot_eval_implementation_evidence::Member[:]>(),blot_error::Error.artifact_limit; }
 let items=pool_implementation_members.alloc_slice(len); let first: const blot_eval_implementation_evidence::Member& =items[0]; let start=pool_implementation_members.index_of(first);
 let ref,error=create(Field.implementation_members,start,len); if error!=blot_error::Error.none { pool_implementation_members.free_slice(items); return default<blot_eval_implementation_evidence::Member[:]>(),error; }
 self_.leases.values[29]=ref; self_.stats.copied_fields++; self_.stats.copied_bytes+=bytes_of(items).len; return items,blot_error::Error.none;
}
fn shareable_implementation_members(self_: const Builder&,old: const blot_eval_implementation_evidence::Member[:]) -> bool {
 if old.len==0 {return false;}let previous .=self_.previous;if !previous {return false;}
 let ref=previous.values[29]; if !valid(ref) { return false; } let meta=lease_meta[ref.index-1];
 if meta.field!=Field.implementation_members||meta.len!=old.len { return false; }
 let a: const blot_eval_implementation_evidence::Member& =old[0]; let b: const blot_eval_implementation_evidence::Member& =pool_implementation_members[meta.start]; return a .== b;
}
fn retained_implementation_members(self_: Builder&,old: const blot_eval_implementation_evidence::Member[:]) -> const blot_eval_implementation_evidence::Member[:],Error {
 let previous .=self_.previous;if !previous {return default<const blot_eval_implementation_evidence::Member[:]>(),blot_error::Error.invalid_artifact;}let ref=previous.values[29]; let error=retain(ref); if error!=blot_error::Error.none { return default<const blot_eval_implementation_evidence::Member[:]>(),error; }
 let meta=lease_meta[ref.index-1];
 assert(meta.field==Field.implementation_members && meta.len==old.len && meta.len>0 && meta.start>=0 && meta.start<=pool_implementation_members.len && meta.len<=pool_implementation_members.len-meta.start);
 let items=pool_implementation_members[meta.start..meta.start+meta.len];assert(blot_support::same_slice_identity(items,old));
 self_.leases.values[29]=ref; self_.stats.shared_fields++; self_.stats.shared_bytes+=bytes_of(old).len; return items,blot_error::Error.none;
}
fn dupe_implementation_members(self_: Builder&,source: const blot_eval_implementation_evidence::Member[:],previous: const blot_eval_implementation_evidence::Member[:]) -> const blot_eval_implementation_evidence::Member[:],Error {
 if shareable_implementation_members(self_,previous)&&blot_structural::equal(source,previous) { return retained_implementation_members(self_,previous); }
 let items,error=alloc_implementation_members(self_,source.len); if error!=blot_error::Error.none { return default<const blot_eval_implementation_evidence::Member[:]>(),error; } for value,index in source { items[index]=value; } return items,blot_error::Error.none;
}
fn converted_implementation_members<C,F>(self_: Builder&,len: i64,context: C&,previous: const blot_eval_implementation_evidence::Member[:]) -> const blot_eval_implementation_evidence::Member[:],Error {
 if shareable_implementation_members(self_,previous)&&previous.len==len {
  var same=true; for item,index in previous { if !blot_structural::equal(item,F(context,index)) { same=false; break; } } if same { return retained_implementation_members(self_,previous); }
 }
 let items,error=alloc_implementation_members(self_,len); if error!=blot_error::Error.none { return default<const blot_eval_implementation_evidence::Member[:]>(),error; } for index in 0..len { items[index]=F(context,index); } return items,blot_error::Error.none;
}
fn free_implementation_members(leases: const Leases&,items: const blot_eval_implementation_evidence::Member[:]) -> Error {
 let ref=leases.values[29]; if ref.index!=0 { return release(ref); }
 if items.len!=0 {pool_implementation_members.free_slice(items);} return blot_error::Error.none;
}

fn alloc_implementation_edges(self_: Builder&,len: i64) -> u32[:],Error {
 if self_.leases.values[30].index!=0||len<0 { return default<u32[:]>(),blot_error::Error.invalid_artifact; }
 if len==0 { return default<u32[:]>(),blot_error::Error.none; }
 if next_generation==0xffffffffffffffff { return default<u32[:]>(),blot_error::Error.artifact_limit; }
 let items=pool_implementation_edges.alloc_slice(len); let first: const u32& =items[0]; let start=pool_implementation_edges.index_of(first);
 let ref,error=create(Field.implementation_edges,start,len); if error!=blot_error::Error.none { pool_implementation_edges.free_slice(items); return default<u32[:]>(),error; }
 self_.leases.values[30]=ref; self_.stats.copied_fields++; self_.stats.copied_bytes+=bytes_of(items).len; return items,blot_error::Error.none;
}
fn shareable_implementation_edges(self_: const Builder&,old: const u32[:]) -> bool {
 if old.len==0 {return false;}let previous .=self_.previous;if !previous {return false;}
 let ref=previous.values[30]; if !valid(ref) { return false; } let meta=lease_meta[ref.index-1];
 if meta.field!=Field.implementation_edges||meta.len!=old.len { return false; }
 let a: const u32& =old[0]; let b: const u32& =pool_implementation_edges[meta.start]; return a .== b;
}
fn retained_implementation_edges(self_: Builder&,old: const u32[:]) -> const u32[:],Error {
 let previous .=self_.previous;if !previous {return default<const u32[:]>(),blot_error::Error.invalid_artifact;}let ref=previous.values[30]; let error=retain(ref); if error!=blot_error::Error.none { return default<const u32[:]>(),error; }
 let meta=lease_meta[ref.index-1];
 assert(meta.field==Field.implementation_edges && meta.len==old.len && meta.len>0 && meta.start>=0 && meta.start<=pool_implementation_edges.len && meta.len<=pool_implementation_edges.len-meta.start);
 let items=pool_implementation_edges[meta.start..meta.start+meta.len];assert(blot_support::same_slice_identity(items,old));
 self_.leases.values[30]=ref; self_.stats.shared_fields++; self_.stats.shared_bytes+=bytes_of(old).len; return items,blot_error::Error.none;
}
fn dupe_implementation_edges(self_: Builder&,source: const u32[:],previous: const u32[:]) -> const u32[:],Error {
 if shareable_implementation_edges(self_,previous)&&blot_structural::equal(source,previous) { return retained_implementation_edges(self_,previous); }
 let items,error=alloc_implementation_edges(self_,source.len); if error!=blot_error::Error.none { return default<const u32[:]>(),error; } for value,index in source { items[index]=value; } return items,blot_error::Error.none;
}
fn converted_implementation_edges<C,F>(self_: Builder&,len: i64,context: C&,previous: const u32[:]) -> const u32[:],Error {
 if shareable_implementation_edges(self_,previous)&&previous.len==len {
  var same=true; for item,index in previous { if !blot_structural::equal(item,F(context,index)) { same=false; break; } } if same { return retained_implementation_edges(self_,previous); }
 }
 let items,error=alloc_implementation_edges(self_,len); if error!=blot_error::Error.none { return default<const u32[:]>(),error; } for index in 0..len { items[index]=F(context,index); } return items,blot_error::Error.none;
}
fn free_implementation_edges(leases: const Leases&,items: const u32[:]) -> Error {
 let ref=leases.values[30]; if ref.index!=0 { return release(ref); }
 if items.len!=0 {pool_implementation_edges.free_slice(items);} return blot_error::Error.none;
}

fn alloc_captures(self_: Builder&,len: i64) -> blot_reuse_code_artifacts::CapturedTemplate[:],Error {
 if self_.leases.values[31].index!=0||len<0 { return default<blot_reuse_code_artifacts::CapturedTemplate[:]>(),blot_error::Error.invalid_artifact; }
 if len==0 { return default<blot_reuse_code_artifacts::CapturedTemplate[:]>(),blot_error::Error.none; }
 if next_generation==0xffffffffffffffff { return default<blot_reuse_code_artifacts::CapturedTemplate[:]>(),blot_error::Error.artifact_limit; }
 let items=pool_captures.alloc_slice(len); let first: const blot_reuse_code_artifacts::CapturedTemplate& =items[0]; let start=pool_captures.index_of(first);
 let ref,error=create(Field.captures,start,len); if error!=blot_error::Error.none { pool_captures.free_slice(items); return default<blot_reuse_code_artifacts::CapturedTemplate[:]>(),error; }
 self_.leases.values[31]=ref; self_.stats.copied_fields++; self_.stats.copied_bytes+=bytes_of(items).len; return items,blot_error::Error.none;
}
fn shareable_captures(self_: const Builder&,old: const blot_reuse_code_artifacts::CapturedTemplate[:]) -> bool {
 if old.len==0 {return false;}let previous .=self_.previous;if !previous {return false;}
 let ref=previous.values[31]; if !valid(ref) { return false; } let meta=lease_meta[ref.index-1];
 if meta.field!=Field.captures||meta.len!=old.len { return false; }
 let a: const blot_reuse_code_artifacts::CapturedTemplate& =old[0]; let b: const blot_reuse_code_artifacts::CapturedTemplate& =pool_captures[meta.start]; return a .== b;
}
fn retained_captures(self_: Builder&,old: const blot_reuse_code_artifacts::CapturedTemplate[:]) -> const blot_reuse_code_artifacts::CapturedTemplate[:],Error {
 let previous .=self_.previous;if !previous {return default<const blot_reuse_code_artifacts::CapturedTemplate[:]>(),blot_error::Error.invalid_artifact;}let ref=previous.values[31]; let error=retain(ref); if error!=blot_error::Error.none { return default<const blot_reuse_code_artifacts::CapturedTemplate[:]>(),error; }
 let meta=lease_meta[ref.index-1];
 assert(meta.field==Field.captures && meta.len==old.len && meta.len>0 && meta.start>=0 && meta.start<=pool_captures.len && meta.len<=pool_captures.len-meta.start);
 let items=pool_captures[meta.start..meta.start+meta.len];assert(blot_support::same_slice_identity(items,old));
 self_.leases.values[31]=ref; self_.stats.shared_fields++; self_.stats.shared_bytes+=bytes_of(old).len; return items,blot_error::Error.none;
}
fn dupe_captures(self_: Builder&,source: const blot_reuse_code_artifacts::CapturedTemplate[:],previous: const blot_reuse_code_artifacts::CapturedTemplate[:]) -> const blot_reuse_code_artifacts::CapturedTemplate[:],Error {
 if shareable_captures(self_,previous)&&blot_structural::equal(source,previous) { return retained_captures(self_,previous); }
 let items,error=alloc_captures(self_,source.len); if error!=blot_error::Error.none { return default<const blot_reuse_code_artifacts::CapturedTemplate[:]>(),error; } for value,index in source { items[index]=value; } return items,blot_error::Error.none;
}
fn converted_captures<C,F>(self_: Builder&,len: i64,context: C&,previous: const blot_reuse_code_artifacts::CapturedTemplate[:]) -> const blot_reuse_code_artifacts::CapturedTemplate[:],Error {
 if shareable_captures(self_,previous)&&previous.len==len {
  var same=true; for item,index in previous { if !blot_structural::equal(item,F(context,index)) { same=false; break; } } if same { return retained_captures(self_,previous); }
 }
 let items,error=alloc_captures(self_,len); if error!=blot_error::Error.none { return default<const blot_reuse_code_artifacts::CapturedTemplate[:]>(),error; } for index in 0..len { items[index]=F(context,index); } return items,blot_error::Error.none;
}
fn free_captures(leases: const Leases&,items: const blot_reuse_code_artifacts::CapturedTemplate[:]) -> Error {
 let ref=leases.values[31]; if ref.index!=0 { return release(ref); }
 if items.len!=0 {pool_captures.free_slice(items);} return blot_error::Error.none;
}

fn alloc_field_locations(self_: Builder&,len: i64) -> blot_reuse_code_artifacts::FieldLocation[:],Error {
 if self_.leases.values[32].index!=0||len<0 { return default<blot_reuse_code_artifacts::FieldLocation[:]>(),blot_error::Error.invalid_artifact; }
 if len==0 { return default<blot_reuse_code_artifacts::FieldLocation[:]>(),blot_error::Error.none; }
 if next_generation==0xffffffffffffffff { return default<blot_reuse_code_artifacts::FieldLocation[:]>(),blot_error::Error.artifact_limit; }
 let items=pool_field_locations.alloc_slice(len); let first: const blot_reuse_code_artifacts::FieldLocation& =items[0]; let start=pool_field_locations.index_of(first);
 let ref,error=create(Field.field_locations,start,len); if error!=blot_error::Error.none { pool_field_locations.free_slice(items); return default<blot_reuse_code_artifacts::FieldLocation[:]>(),error; }
 self_.leases.values[32]=ref; self_.stats.copied_fields++; self_.stats.copied_bytes+=bytes_of(items).len; return items,blot_error::Error.none;
}
fn shareable_field_locations(self_: const Builder&,old: const blot_reuse_code_artifacts::FieldLocation[:]) -> bool {
 if old.len==0 {return false;}let previous .=self_.previous;if !previous {return false;}
 let ref=previous.values[32]; if !valid(ref) { return false; } let meta=lease_meta[ref.index-1];
 if meta.field!=Field.field_locations||meta.len!=old.len { return false; }
 let a: const blot_reuse_code_artifacts::FieldLocation& =old[0]; let b: const blot_reuse_code_artifacts::FieldLocation& =pool_field_locations[meta.start]; return a .== b;
}
fn retained_field_locations(self_: Builder&,old: const blot_reuse_code_artifacts::FieldLocation[:]) -> const blot_reuse_code_artifacts::FieldLocation[:],Error {
 let previous .=self_.previous;if !previous {return default<const blot_reuse_code_artifacts::FieldLocation[:]>(),blot_error::Error.invalid_artifact;}let ref=previous.values[32]; let error=retain(ref); if error!=blot_error::Error.none { return default<const blot_reuse_code_artifacts::FieldLocation[:]>(),error; }
 let meta=lease_meta[ref.index-1];
 assert(meta.field==Field.field_locations && meta.len==old.len && meta.len>0 && meta.start>=0 && meta.start<=pool_field_locations.len && meta.len<=pool_field_locations.len-meta.start);
 let items=pool_field_locations[meta.start..meta.start+meta.len];assert(blot_support::same_slice_identity(items,old));
 self_.leases.values[32]=ref; self_.stats.shared_fields++; self_.stats.shared_bytes+=bytes_of(old).len; return items,blot_error::Error.none;
}
fn dupe_field_locations(self_: Builder&,source: const blot_reuse_code_artifacts::FieldLocation[:],previous: const blot_reuse_code_artifacts::FieldLocation[:]) -> const blot_reuse_code_artifacts::FieldLocation[:],Error {
 if shareable_field_locations(self_,previous)&&blot_structural::equal(source,previous) { return retained_field_locations(self_,previous); }
 let items,error=alloc_field_locations(self_,source.len); if error!=blot_error::Error.none { return default<const blot_reuse_code_artifacts::FieldLocation[:]>(),error; } for value,index in source { items[index]=value; } return items,blot_error::Error.none;
}
fn converted_field_locations<C,F>(self_: Builder&,len: i64,context: C&,previous: const blot_reuse_code_artifacts::FieldLocation[:]) -> const blot_reuse_code_artifacts::FieldLocation[:],Error {
 if shareable_field_locations(self_,previous)&&previous.len==len {
  var same=true; for item,index in previous { if !blot_structural::equal(item,F(context,index)) { same=false; break; } } if same { return retained_field_locations(self_,previous); }
 }
 let items,error=alloc_field_locations(self_,len); if error!=blot_error::Error.none { return default<const blot_reuse_code_artifacts::FieldLocation[:]>(),error; } for index in 0..len { items[index]=F(context,index); } return items,blot_error::Error.none;
}
fn free_field_locations(leases: const Leases&,items: const blot_reuse_code_artifacts::FieldLocation[:]) -> Error {
 let ref=leases.values[32]; if ref.index!=0 { return release(ref); }
 if items.len!=0 {pool_field_locations.free_slice(items);} return blot_error::Error.none;
}

fn alloc_functions(self_: Builder&,len: i64) -> blot_reuse_code_artifacts::Function[:],Error {
 if self_.leases.values[33].index!=0||len<0 { return default<blot_reuse_code_artifacts::Function[:]>(),blot_error::Error.invalid_artifact; }
 if len==0 { return default<blot_reuse_code_artifacts::Function[:]>(),blot_error::Error.none; }
 if next_generation==0xffffffffffffffff { return default<blot_reuse_code_artifacts::Function[:]>(),blot_error::Error.artifact_limit; }
 let items=pool_functions.alloc_slice(len); let first: const blot_reuse_code_artifacts::Function& =items[0]; let start=pool_functions.index_of(first);
 let ref,error=create(Field.functions,start,len); if error!=blot_error::Error.none { pool_functions.free_slice(items); return default<blot_reuse_code_artifacts::Function[:]>(),error; }
 self_.leases.values[33]=ref; self_.stats.copied_fields++; self_.stats.copied_bytes+=bytes_of(items).len; return items,blot_error::Error.none;
}
fn shareable_functions(self_: const Builder&,old: const blot_reuse_code_artifacts::Function[:]) -> bool {
 if old.len==0 {return false;}let previous .=self_.previous;if !previous {return false;}
 let ref=previous.values[33]; if !valid(ref) { return false; } let meta=lease_meta[ref.index-1];
 if meta.field!=Field.functions||meta.len!=old.len { return false; }
 let a: const blot_reuse_code_artifacts::Function& =old[0]; let b: const blot_reuse_code_artifacts::Function& =pool_functions[meta.start]; return a .== b;
}
fn retained_functions(self_: Builder&,old: const blot_reuse_code_artifacts::Function[:]) -> const blot_reuse_code_artifacts::Function[:],Error {
 let previous .=self_.previous;if !previous {return default<const blot_reuse_code_artifacts::Function[:]>(),blot_error::Error.invalid_artifact;}let ref=previous.values[33]; let error=retain(ref); if error!=blot_error::Error.none { return default<const blot_reuse_code_artifacts::Function[:]>(),error; }
 let meta=lease_meta[ref.index-1];
 assert(meta.field==Field.functions && meta.len==old.len && meta.len>0 && meta.start>=0 && meta.start<=pool_functions.len && meta.len<=pool_functions.len-meta.start);
 let items=pool_functions[meta.start..meta.start+meta.len];assert(blot_support::same_slice_identity(items,old));
 self_.leases.values[33]=ref; self_.stats.shared_fields++; self_.stats.shared_bytes+=bytes_of(old).len; return items,blot_error::Error.none;
}
fn dupe_functions(self_: Builder&,source: const blot_reuse_code_artifacts::Function[:],previous: const blot_reuse_code_artifacts::Function[:]) -> const blot_reuse_code_artifacts::Function[:],Error {
 if shareable_functions(self_,previous)&&blot_structural::equal(source,previous) { return retained_functions(self_,previous); }
 let items,error=alloc_functions(self_,source.len); if error!=blot_error::Error.none { return default<const blot_reuse_code_artifacts::Function[:]>(),error; } for value,index in source { items[index]=value; } return items,blot_error::Error.none;
}
fn converted_functions<C,F>(self_: Builder&,len: i64,context: C&,previous: const blot_reuse_code_artifacts::Function[:]) -> const blot_reuse_code_artifacts::Function[:],Error {
 if shareable_functions(self_,previous)&&previous.len==len {
  var same=true; for item,index in previous { if !blot_structural::equal(item,F(context,index)) { same=false; break; } } if same { return retained_functions(self_,previous); }
 }
 let items,error=alloc_functions(self_,len); if error!=blot_error::Error.none { return default<const blot_reuse_code_artifacts::Function[:]>(),error; } for index in 0..len { items[index]=F(context,index); } return items,blot_error::Error.none;
}
fn free_functions(leases: const Leases&,items: const blot_reuse_code_artifacts::Function[:]) -> Error {
 let ref=leases.values[33]; if ref.index!=0 { return release(ref); }
 if items.len!=0 {pool_functions.free_slice(items);} return blot_error::Error.none;
}

fn alloc_serialized(self_: Builder&,len: i64) -> blot_reuse_code_artifacts::Serialized[:],Error {
 if self_.leases.values[34].index!=0||len<0 { return default<blot_reuse_code_artifacts::Serialized[:]>(),blot_error::Error.invalid_artifact; }
 if len==0 { return default<blot_reuse_code_artifacts::Serialized[:]>(),blot_error::Error.none; }
 if next_generation==0xffffffffffffffff { return default<blot_reuse_code_artifacts::Serialized[:]>(),blot_error::Error.artifact_limit; }
 let items=pool_serialized.alloc_slice(len); let first: const blot_reuse_code_artifacts::Serialized& =items[0]; let start=pool_serialized.index_of(first);
 let ref,error=create(Field.serialized,start,len); if error!=blot_error::Error.none { pool_serialized.free_slice(items); return default<blot_reuse_code_artifacts::Serialized[:]>(),error; }
 self_.leases.values[34]=ref; self_.stats.copied_fields++; self_.stats.copied_bytes+=bytes_of(items).len; return items,blot_error::Error.none;
}
fn shareable_serialized(self_: const Builder&,old: const blot_reuse_code_artifacts::Serialized[:]) -> bool {
 if old.len==0 {return false;}let previous .=self_.previous;if !previous {return false;}
 let ref=previous.values[34]; if !valid(ref) { return false; } let meta=lease_meta[ref.index-1];
 if meta.field!=Field.serialized||meta.len!=old.len { return false; }
 let a: const blot_reuse_code_artifacts::Serialized& =old[0]; let b: const blot_reuse_code_artifacts::Serialized& =pool_serialized[meta.start]; return a .== b;
}
fn retained_serialized(self_: Builder&,old: const blot_reuse_code_artifacts::Serialized[:]) -> const blot_reuse_code_artifacts::Serialized[:],Error {
 let previous .=self_.previous;if !previous {return default<const blot_reuse_code_artifacts::Serialized[:]>(),blot_error::Error.invalid_artifact;}let ref=previous.values[34]; let error=retain(ref); if error!=blot_error::Error.none { return default<const blot_reuse_code_artifacts::Serialized[:]>(),error; }
 let meta=lease_meta[ref.index-1];
 assert(meta.field==Field.serialized && meta.len==old.len && meta.len>0 && meta.start>=0 && meta.start<=pool_serialized.len && meta.len<=pool_serialized.len-meta.start);
 let items=pool_serialized[meta.start..meta.start+meta.len];assert(blot_support::same_slice_identity(items,old));
 self_.leases.values[34]=ref; self_.stats.shared_fields++; self_.stats.shared_bytes+=bytes_of(old).len; return items,blot_error::Error.none;
}
fn dupe_serialized(self_: Builder&,source: const blot_reuse_code_artifacts::Serialized[:],previous: const blot_reuse_code_artifacts::Serialized[:]) -> const blot_reuse_code_artifacts::Serialized[:],Error {
 if shareable_serialized(self_,previous)&&blot_structural::equal(source,previous) { return retained_serialized(self_,previous); }
 let items,error=alloc_serialized(self_,source.len); if error!=blot_error::Error.none { return default<const blot_reuse_code_artifacts::Serialized[:]>(),error; } for value,index in source { items[index]=value; } return items,blot_error::Error.none;
}
fn converted_serialized<C,F>(self_: Builder&,len: i64,context: C&,previous: const blot_reuse_code_artifacts::Serialized[:]) -> const blot_reuse_code_artifacts::Serialized[:],Error {
 if shareable_serialized(self_,previous)&&previous.len==len {
  var same=true; for item,index in previous { if !blot_structural::equal(item,F(context,index)) { same=false; break; } } if same { return retained_serialized(self_,previous); }
 }
 let items,error=alloc_serialized(self_,len); if error!=blot_error::Error.none { return default<const blot_reuse_code_artifacts::Serialized[:]>(),error; } for index in 0..len { items[index]=F(context,index); } return items,blot_error::Error.none;
}
fn free_serialized(leases: const Leases&,items: const blot_reuse_code_artifacts::Serialized[:]) -> Error {
 let ref=leases.values[34]; if ref.index!=0 { return release(ref); }
 if items.len!=0 {pool_serialized.free_slice(items);} return blot_error::Error.none;
}

fn alloc_runtime_globals(self_: Builder&,len: i64) -> blot_reuse_code_artifacts::RuntimeGlobal[:],Error {
 if self_.leases.values[35].index!=0||len<0 { return default<blot_reuse_code_artifacts::RuntimeGlobal[:]>(),blot_error::Error.invalid_artifact; }
 if len==0 { return default<blot_reuse_code_artifacts::RuntimeGlobal[:]>(),blot_error::Error.none; }
 if next_generation==0xffffffffffffffff { return default<blot_reuse_code_artifacts::RuntimeGlobal[:]>(),blot_error::Error.artifact_limit; }
 let items=pool_runtime_globals.alloc_slice(len); let first: const blot_reuse_code_artifacts::RuntimeGlobal& =items[0]; let start=pool_runtime_globals.index_of(first);
 let ref,error=create(Field.runtime_globals,start,len); if error!=blot_error::Error.none { pool_runtime_globals.free_slice(items); return default<blot_reuse_code_artifacts::RuntimeGlobal[:]>(),error; }
 self_.leases.values[35]=ref; self_.stats.copied_fields++; self_.stats.copied_bytes+=bytes_of(items).len; return items,blot_error::Error.none;
}
fn shareable_runtime_globals(self_: const Builder&,old: const blot_reuse_code_artifacts::RuntimeGlobal[:]) -> bool {
 if old.len==0 {return false;}let previous .=self_.previous;if !previous {return false;}
 let ref=previous.values[35]; if !valid(ref) { return false; } let meta=lease_meta[ref.index-1];
 if meta.field!=Field.runtime_globals||meta.len!=old.len { return false; }
 let a: const blot_reuse_code_artifacts::RuntimeGlobal& =old[0]; let b: const blot_reuse_code_artifacts::RuntimeGlobal& =pool_runtime_globals[meta.start]; return a .== b;
}
fn retained_runtime_globals(self_: Builder&,old: const blot_reuse_code_artifacts::RuntimeGlobal[:]) -> const blot_reuse_code_artifacts::RuntimeGlobal[:],Error {
 let previous .=self_.previous;if !previous {return default<const blot_reuse_code_artifacts::RuntimeGlobal[:]>(),blot_error::Error.invalid_artifact;}let ref=previous.values[35]; let error=retain(ref); if error!=blot_error::Error.none { return default<const blot_reuse_code_artifacts::RuntimeGlobal[:]>(),error; }
 let meta=lease_meta[ref.index-1];
 assert(meta.field==Field.runtime_globals && meta.len==old.len && meta.len>0 && meta.start>=0 && meta.start<=pool_runtime_globals.len && meta.len<=pool_runtime_globals.len-meta.start);
 let items=pool_runtime_globals[meta.start..meta.start+meta.len];assert(blot_support::same_slice_identity(items,old));
 self_.leases.values[35]=ref; self_.stats.shared_fields++; self_.stats.shared_bytes+=bytes_of(old).len; return items,blot_error::Error.none;
}
fn dupe_runtime_globals(self_: Builder&,source: const blot_reuse_code_artifacts::RuntimeGlobal[:],previous: const blot_reuse_code_artifacts::RuntimeGlobal[:]) -> const blot_reuse_code_artifacts::RuntimeGlobal[:],Error {
 if shareable_runtime_globals(self_,previous)&&blot_structural::equal(source,previous) { return retained_runtime_globals(self_,previous); }
 let items,error=alloc_runtime_globals(self_,source.len); if error!=blot_error::Error.none { return default<const blot_reuse_code_artifacts::RuntimeGlobal[:]>(),error; } for value,index in source { items[index]=value; } return items,blot_error::Error.none;
}
fn converted_runtime_globals<C,F>(self_: Builder&,len: i64,context: C&,previous: const blot_reuse_code_artifacts::RuntimeGlobal[:]) -> const blot_reuse_code_artifacts::RuntimeGlobal[:],Error {
 if shareable_runtime_globals(self_,previous)&&previous.len==len {
  var same=true; for item,index in previous { if !blot_structural::equal(item,F(context,index)) { same=false; break; } } if same { return retained_runtime_globals(self_,previous); }
 }
 let items,error=alloc_runtime_globals(self_,len); if error!=blot_error::Error.none { return default<const blot_reuse_code_artifacts::RuntimeGlobal[:]>(),error; } for index in 0..len { items[index]=F(context,index); } return items,blot_error::Error.none;
}
fn free_runtime_globals(leases: const Leases&,items: const blot_reuse_code_artifacts::RuntimeGlobal[:]) -> Error {
 let ref=leases.values[35]; if ref.index!=0 { return release(ref); }
 if items.len!=0 {pool_runtime_globals.free_slice(items);} return blot_error::Error.none;
}

fn alloc_runtime_order(self_: Builder&,len: i64) -> u32[:],Error {
 if self_.leases.values[36].index!=0||len<0 { return default<u32[:]>(),blot_error::Error.invalid_artifact; }
 if len==0 { return default<u32[:]>(),blot_error::Error.none; }
 if next_generation==0xffffffffffffffff { return default<u32[:]>(),blot_error::Error.artifact_limit; }
 let items=pool_runtime_order.alloc_slice(len); let first: const u32& =items[0]; let start=pool_runtime_order.index_of(first);
 let ref,error=create(Field.runtime_order,start,len); if error!=blot_error::Error.none { pool_runtime_order.free_slice(items); return default<u32[:]>(),error; }
 self_.leases.values[36]=ref; self_.stats.copied_fields++; self_.stats.copied_bytes+=bytes_of(items).len; return items,blot_error::Error.none;
}
fn shareable_runtime_order(self_: const Builder&,old: const u32[:]) -> bool {
 if old.len==0 {return false;}let previous .=self_.previous;if !previous {return false;}
 let ref=previous.values[36]; if !valid(ref) { return false; } let meta=lease_meta[ref.index-1];
 if meta.field!=Field.runtime_order||meta.len!=old.len { return false; }
 let a: const u32& =old[0]; let b: const u32& =pool_runtime_order[meta.start]; return a .== b;
}
fn retained_runtime_order(self_: Builder&,old: const u32[:]) -> const u32[:],Error {
 let previous .=self_.previous;if !previous {return default<const u32[:]>(),blot_error::Error.invalid_artifact;}let ref=previous.values[36]; let error=retain(ref); if error!=blot_error::Error.none { return default<const u32[:]>(),error; }
 let meta=lease_meta[ref.index-1];
 assert(meta.field==Field.runtime_order && meta.len==old.len && meta.len>0 && meta.start>=0 && meta.start<=pool_runtime_order.len && meta.len<=pool_runtime_order.len-meta.start);
 let items=pool_runtime_order[meta.start..meta.start+meta.len];assert(blot_support::same_slice_identity(items,old));
 self_.leases.values[36]=ref; self_.stats.shared_fields++; self_.stats.shared_bytes+=bytes_of(old).len; return items,blot_error::Error.none;
}
fn dupe_runtime_order(self_: Builder&,source: const u32[:],previous: const u32[:]) -> const u32[:],Error {
 if shareable_runtime_order(self_,previous)&&blot_structural::equal(source,previous) { return retained_runtime_order(self_,previous); }
 let items,error=alloc_runtime_order(self_,source.len); if error!=blot_error::Error.none { return default<const u32[:]>(),error; } for value,index in source { items[index]=value; } return items,blot_error::Error.none;
}
fn converted_runtime_order<C,F>(self_: Builder&,len: i64,context: C&,previous: const u32[:]) -> const u32[:],Error {
 if shareable_runtime_order(self_,previous)&&previous.len==len {
  var same=true; for item,index in previous { if !blot_structural::equal(item,F(context,index)) { same=false; break; } } if same { return retained_runtime_order(self_,previous); }
 }
 let items,error=alloc_runtime_order(self_,len); if error!=blot_error::Error.none { return default<const u32[:]>(),error; } for index in 0..len { items[index]=F(context,index); } return items,blot_error::Error.none;
}
fn free_runtime_order(leases: const Leases&,items: const u32[:]) -> Error {
 let ref=leases.values[36]; if ref.index!=0 { return release(ref); }
 if items.len!=0 {pool_runtime_order.free_slice(items);} return blot_error::Error.none;
}

fn alloc_binding_offsets(self_: Builder&,len: i64) -> i64[:],Error {
 if self_.leases.values[37].index!=0||len<0 { return default<i64[:]>(),blot_error::Error.invalid_artifact; }
 if len==0 { return default<i64[:]>(),blot_error::Error.none; }
 if next_generation==0xffffffffffffffff { return default<i64[:]>(),blot_error::Error.artifact_limit; }
 let items=pool_binding_offsets.alloc_slice(len); let first: const i64& =items[0]; let start=pool_binding_offsets.index_of(first);
 let ref,error=create(Field.binding_offsets,start,len); if error!=blot_error::Error.none { pool_binding_offsets.free_slice(items); return default<i64[:]>(),error; }
 self_.leases.values[37]=ref; self_.stats.copied_fields++; self_.stats.copied_bytes+=bytes_of(items).len; return items,blot_error::Error.none;
}
fn shareable_binding_offsets(self_: const Builder&,old: const i64[:]) -> bool {
 if old.len==0 {return false;}let previous .=self_.previous;if !previous {return false;}
 let ref=previous.values[37]; if !valid(ref) { return false; } let meta=lease_meta[ref.index-1];
 if meta.field!=Field.binding_offsets||meta.len!=old.len { return false; }
 let a: const i64& =old[0]; let b: const i64& =pool_binding_offsets[meta.start]; return a .== b;
}
fn retained_binding_offsets(self_: Builder&,old: const i64[:]) -> const i64[:],Error {
 let previous .=self_.previous;if !previous {return default<const i64[:]>(),blot_error::Error.invalid_artifact;}let ref=previous.values[37]; let error=retain(ref); if error!=blot_error::Error.none { return default<const i64[:]>(),error; }
 let meta=lease_meta[ref.index-1];
 assert(meta.field==Field.binding_offsets && meta.len==old.len && meta.len>0 && meta.start>=0 && meta.start<=pool_binding_offsets.len && meta.len<=pool_binding_offsets.len-meta.start);
 let items=pool_binding_offsets[meta.start..meta.start+meta.len];assert(blot_support::same_slice_identity(items,old));
 self_.leases.values[37]=ref; self_.stats.shared_fields++; self_.stats.shared_bytes+=bytes_of(old).len; return items,blot_error::Error.none;
}
fn dupe_binding_offsets(self_: Builder&,source: const i64[:],previous: const i64[:]) -> const i64[:],Error {
 if shareable_binding_offsets(self_,previous)&&blot_structural::equal(source,previous) { return retained_binding_offsets(self_,previous); }
 let items,error=alloc_binding_offsets(self_,source.len); if error!=blot_error::Error.none { return default<const i64[:]>(),error; } for value,index in source { items[index]=value; } return items,blot_error::Error.none;
}
fn converted_binding_offsets<C,F>(self_: Builder&,len: i64,context: C&,previous: const i64[:]) -> const i64[:],Error {
 if shareable_binding_offsets(self_,previous)&&previous.len==len {
  var same=true; for item,index in previous { if !blot_structural::equal(item,F(context,index)) { same=false; break; } } if same { return retained_binding_offsets(self_,previous); }
 }
 let items,error=alloc_binding_offsets(self_,len); if error!=blot_error::Error.none { return default<const i64[:]>(),error; } for index in 0..len { items[index]=F(context,index); } return items,blot_error::Error.none;
}
fn free_binding_offsets(leases: const Leases&,items: const i64[:]) -> Error {
 let ref=leases.values[37]; if ref.index!=0 { return release(ref); }
 if items.len!=0 {pool_binding_offsets.free_slice(items);} return blot_error::Error.none;
}

fn alloc_node_offsets(self_: Builder&,len: i64) -> i64[:],Error {
 if self_.leases.values[38].index!=0||len<0 { return default<i64[:]>(),blot_error::Error.invalid_artifact; }
 if len==0 { return default<i64[:]>(),blot_error::Error.none; }
 if next_generation==0xffffffffffffffff { return default<i64[:]>(),blot_error::Error.artifact_limit; }
 let items=pool_node_offsets.alloc_slice(len); let first: const i64& =items[0]; let start=pool_node_offsets.index_of(first);
 let ref,error=create(Field.node_offsets,start,len); if error!=blot_error::Error.none { pool_node_offsets.free_slice(items); return default<i64[:]>(),error; }
 self_.leases.values[38]=ref; self_.stats.copied_fields++; self_.stats.copied_bytes+=bytes_of(items).len; return items,blot_error::Error.none;
}
fn shareable_node_offsets(self_: const Builder&,old: const i64[:]) -> bool {
 if old.len==0 {return false;}let previous .=self_.previous;if !previous {return false;}
 let ref=previous.values[38]; if !valid(ref) { return false; } let meta=lease_meta[ref.index-1];
 if meta.field!=Field.node_offsets||meta.len!=old.len { return false; }
 let a: const i64& =old[0]; let b: const i64& =pool_node_offsets[meta.start]; return a .== b;
}
fn retained_node_offsets(self_: Builder&,old: const i64[:]) -> const i64[:],Error {
 let previous .=self_.previous;if !previous {return default<const i64[:]>(),blot_error::Error.invalid_artifact;}let ref=previous.values[38]; let error=retain(ref); if error!=blot_error::Error.none { return default<const i64[:]>(),error; }
 let meta=lease_meta[ref.index-1];
 assert(meta.field==Field.node_offsets && meta.len==old.len && meta.len>0 && meta.start>=0 && meta.start<=pool_node_offsets.len && meta.len<=pool_node_offsets.len-meta.start);
 let items=pool_node_offsets[meta.start..meta.start+meta.len];assert(blot_support::same_slice_identity(items,old));
 self_.leases.values[38]=ref; self_.stats.shared_fields++; self_.stats.shared_bytes+=bytes_of(old).len; return items,blot_error::Error.none;
}
fn dupe_node_offsets(self_: Builder&,source: const i64[:],previous: const i64[:]) -> const i64[:],Error {
 if shareable_node_offsets(self_,previous)&&blot_structural::equal(source,previous) { return retained_node_offsets(self_,previous); }
 let items,error=alloc_node_offsets(self_,source.len); if error!=blot_error::Error.none { return default<const i64[:]>(),error; } for value,index in source { items[index]=value; } return items,blot_error::Error.none;
}
fn converted_node_offsets<C,F>(self_: Builder&,len: i64,context: C&,previous: const i64[:]) -> const i64[:],Error {
 if shareable_node_offsets(self_,previous)&&previous.len==len {
  var same=true; for item,index in previous { if !blot_structural::equal(item,F(context,index)) { same=false; break; } } if same { return retained_node_offsets(self_,previous); }
 }
 let items,error=alloc_node_offsets(self_,len); if error!=blot_error::Error.none { return default<const i64[:]>(),error; } for index in 0..len { items[index]=F(context,index); } return items,blot_error::Error.none;
}
fn free_node_offsets(leases: const Leases&,items: const i64[:]) -> Error {
 let ref=leases.values[38]; if ref.index!=0 { return release(ref); }
 if items.len!=0 {pool_node_offsets.free_slice(items);} return blot_error::Error.none;
}

fn alloc_slots(self_: Builder&,len: i64) -> blot_reuse_code_artifacts::Slot[:],Error {
 if self_.leases.values[39].index!=0||len<0 { return default<blot_reuse_code_artifacts::Slot[:]>(),blot_error::Error.invalid_artifact; }
 if len==0 { return default<blot_reuse_code_artifacts::Slot[:]>(),blot_error::Error.none; }
 if next_generation==0xffffffffffffffff { return default<blot_reuse_code_artifacts::Slot[:]>(),blot_error::Error.artifact_limit; }
 let items=pool_slots.alloc_slice(len); let first: const blot_reuse_code_artifacts::Slot& =items[0]; let start=pool_slots.index_of(first);
 let ref,error=create(Field.slots,start,len); if error!=blot_error::Error.none { pool_slots.free_slice(items); return default<blot_reuse_code_artifacts::Slot[:]>(),error; }
 self_.leases.values[39]=ref; self_.stats.copied_fields++; self_.stats.copied_bytes+=bytes_of(items).len; return items,blot_error::Error.none;
}
fn shareable_slots(self_: const Builder&,old: const blot_reuse_code_artifacts::Slot[:]) -> bool {
 if old.len==0 {return false;}let previous .=self_.previous;if !previous {return false;}
 let ref=previous.values[39]; if !valid(ref) { return false; } let meta=lease_meta[ref.index-1];
 if meta.field!=Field.slots||meta.len!=old.len { return false; }
 let a: const blot_reuse_code_artifacts::Slot& =old[0]; let b: const blot_reuse_code_artifacts::Slot& =pool_slots[meta.start]; return a .== b;
}
fn retained_slots(self_: Builder&,old: const blot_reuse_code_artifacts::Slot[:]) -> const blot_reuse_code_artifacts::Slot[:],Error {
 let previous .=self_.previous;if !previous {return default<const blot_reuse_code_artifacts::Slot[:]>(),blot_error::Error.invalid_artifact;}let ref=previous.values[39]; let error=retain(ref); if error!=blot_error::Error.none { return default<const blot_reuse_code_artifacts::Slot[:]>(),error; }
 let meta=lease_meta[ref.index-1];
 assert(meta.field==Field.slots && meta.len==old.len && meta.len>0 && meta.start>=0 && meta.start<=pool_slots.len && meta.len<=pool_slots.len-meta.start);
 let items=pool_slots[meta.start..meta.start+meta.len];assert(blot_support::same_slice_identity(items,old));
 self_.leases.values[39]=ref; self_.stats.shared_fields++; self_.stats.shared_bytes+=bytes_of(old).len; return items,blot_error::Error.none;
}
fn dupe_slots(self_: Builder&,source: const blot_reuse_code_artifacts::Slot[:],previous: const blot_reuse_code_artifacts::Slot[:]) -> const blot_reuse_code_artifacts::Slot[:],Error {
 if shareable_slots(self_,previous)&&blot_structural::equal(source,previous) { return retained_slots(self_,previous); }
 let items,error=alloc_slots(self_,source.len); if error!=blot_error::Error.none { return default<const blot_reuse_code_artifacts::Slot[:]>(),error; } for value,index in source { items[index]=value; } return items,blot_error::Error.none;
}
fn converted_slots<C,F>(self_: Builder&,len: i64,context: C&,previous: const blot_reuse_code_artifacts::Slot[:]) -> const blot_reuse_code_artifacts::Slot[:],Error {
 if shareable_slots(self_,previous)&&previous.len==len {
  var same=true; for item,index in previous { if !blot_structural::equal(item,F(context,index)) { same=false; break; } } if same { return retained_slots(self_,previous); }
 }
 let items,error=alloc_slots(self_,len); if error!=blot_error::Error.none { return default<const blot_reuse_code_artifacts::Slot[:]>(),error; } for index in 0..len { items[index]=F(context,index); } return items,blot_error::Error.none;
}
fn free_slots(leases: const Leases&,items: const blot_reuse_code_artifacts::Slot[:]) -> Error {
 let ref=leases.values[39]; if ref.index!=0 { return release(ref); }
 if items.len!=0 {pool_slots.free_slice(items);} return blot_error::Error.none;
}

fn alloc_visited_nodes(self_: Builder&,len: i64) -> bool[:],Error {
 if self_.leases.values[40].index!=0||len<0 { return default<bool[:]>(),blot_error::Error.invalid_artifact; }
 if len==0 { return default<bool[:]>(),blot_error::Error.none; }
 if next_generation==0xffffffffffffffff { return default<bool[:]>(),blot_error::Error.artifact_limit; }
 let items=pool_visited_nodes.alloc_slice(len); let first: const bool& =items[0]; let start=pool_visited_nodes.index_of(first);
 let ref,error=create(Field.visited_nodes,start,len); if error!=blot_error::Error.none { pool_visited_nodes.free_slice(items); return default<bool[:]>(),error; }
 self_.leases.values[40]=ref; self_.stats.copied_fields++; self_.stats.copied_bytes+=bytes_of(items).len; return items,blot_error::Error.none;
}
fn shareable_visited_nodes(self_: const Builder&,old: const bool[:]) -> bool {
 if old.len==0 {return false;}let previous .=self_.previous;if !previous {return false;}
 let ref=previous.values[40]; if !valid(ref) { return false; } let meta=lease_meta[ref.index-1];
 if meta.field!=Field.visited_nodes||meta.len!=old.len { return false; }
 let a: const bool& =old[0]; let b: const bool& =pool_visited_nodes[meta.start]; return a .== b;
}
fn retained_visited_nodes(self_: Builder&,old: const bool[:]) -> const bool[:],Error {
 let previous .=self_.previous;if !previous {return default<const bool[:]>(),blot_error::Error.invalid_artifact;}let ref=previous.values[40]; let error=retain(ref); if error!=blot_error::Error.none { return default<const bool[:]>(),error; }
 let meta=lease_meta[ref.index-1];
 assert(meta.field==Field.visited_nodes && meta.len==old.len && meta.len>0 && meta.start>=0 && meta.start<=pool_visited_nodes.len && meta.len<=pool_visited_nodes.len-meta.start);
 let items=pool_visited_nodes[meta.start..meta.start+meta.len];assert(blot_support::same_slice_identity(items,old));
 self_.leases.values[40]=ref; self_.stats.shared_fields++; self_.stats.shared_bytes+=bytes_of(old).len; return items,blot_error::Error.none;
}
fn dupe_visited_nodes(self_: Builder&,source: const bool[:],previous: const bool[:]) -> const bool[:],Error {
 if shareable_visited_nodes(self_,previous)&&blot_structural::equal(source,previous) { return retained_visited_nodes(self_,previous); }
 let items,error=alloc_visited_nodes(self_,source.len); if error!=blot_error::Error.none { return default<const bool[:]>(),error; } for value,index in source { items[index]=value; } return items,blot_error::Error.none;
}
fn converted_visited_nodes<C,F>(self_: Builder&,len: i64,context: C&,previous: const bool[:]) -> const bool[:],Error {
 if shareable_visited_nodes(self_,previous)&&previous.len==len {
  var same=true; for item,index in previous { if !blot_structural::equal(item,F(context,index)) { same=false; break; } } if same { return retained_visited_nodes(self_,previous); }
 }
 let items,error=alloc_visited_nodes(self_,len); if error!=blot_error::Error.none { return default<const bool[:]>(),error; } for index in 0..len { items[index]=F(context,index); } return items,blot_error::Error.none;
}
fn free_visited_nodes(leases: const Leases&,items: const bool[:]) -> Error {
 let ref=leases.values[40]; if ref.index!=0 { return release(ref); }
 if items.len!=0 {pool_visited_nodes.free_slice(items);} return blot_error::Error.none;
}

fn alloc_provider_frames(self_: Builder&,len: i64) -> blot_backend_provider_chain::Frame[:],Error {
 if self_.leases.values[41].index!=0||len<0 { return default<blot_backend_provider_chain::Frame[:]>(),blot_error::Error.invalid_artifact; }
 if len==0 { return default<blot_backend_provider_chain::Frame[:]>(),blot_error::Error.none; }
 if next_generation==0xffffffffffffffff { return default<blot_backend_provider_chain::Frame[:]>(),blot_error::Error.artifact_limit; }
 let items=pool_provider_frames.alloc_slice(len); let first: const blot_backend_provider_chain::Frame& =items[0]; let start=pool_provider_frames.index_of(first);
 let ref,error=create(Field.provider_frames,start,len); if error!=blot_error::Error.none { pool_provider_frames.free_slice(items); return default<blot_backend_provider_chain::Frame[:]>(),error; }
 self_.leases.values[41]=ref; self_.stats.copied_fields++; self_.stats.copied_bytes+=bytes_of(items).len; return items,blot_error::Error.none;
}
fn shareable_provider_frames(self_: const Builder&,old: const blot_backend_provider_chain::Frame[:]) -> bool {
 if old.len==0 {return false;}let previous .=self_.previous;if !previous {return false;}
 let ref=previous.values[41]; if !valid(ref) { return false; } let meta=lease_meta[ref.index-1];
 if meta.field!=Field.provider_frames||meta.len!=old.len { return false; }
 let a: const blot_backend_provider_chain::Frame& =old[0]; let b: const blot_backend_provider_chain::Frame& =pool_provider_frames[meta.start]; return a .== b;
}
fn retained_provider_frames(self_: Builder&,old: const blot_backend_provider_chain::Frame[:]) -> const blot_backend_provider_chain::Frame[:],Error {
 let previous .=self_.previous;if !previous {return default<const blot_backend_provider_chain::Frame[:]>(),blot_error::Error.invalid_artifact;}let ref=previous.values[41]; let error=retain(ref); if error!=blot_error::Error.none { return default<const blot_backend_provider_chain::Frame[:]>(),error; }
 let meta=lease_meta[ref.index-1];
 assert(meta.field==Field.provider_frames && meta.len==old.len && meta.len>0 && meta.start>=0 && meta.start<=pool_provider_frames.len && meta.len<=pool_provider_frames.len-meta.start);
 let items=pool_provider_frames[meta.start..meta.start+meta.len];assert(blot_support::same_slice_identity(items,old));
 self_.leases.values[41]=ref; self_.stats.shared_fields++; self_.stats.shared_bytes+=bytes_of(old).len; return items,blot_error::Error.none;
}
fn dupe_provider_frames(self_: Builder&,source: const blot_backend_provider_chain::Frame[:],previous: const blot_backend_provider_chain::Frame[:]) -> const blot_backend_provider_chain::Frame[:],Error {
 if shareable_provider_frames(self_,previous)&&blot_structural::equal(source,previous) { return retained_provider_frames(self_,previous); }
 let items,error=alloc_provider_frames(self_,source.len); if error!=blot_error::Error.none { return default<const blot_backend_provider_chain::Frame[:]>(),error; } for value,index in source { items[index]=value; } return items,blot_error::Error.none;
}
fn converted_provider_frames<C,F>(self_: Builder&,len: i64,context: C&,previous: const blot_backend_provider_chain::Frame[:]) -> const blot_backend_provider_chain::Frame[:],Error {
 if shareable_provider_frames(self_,previous)&&previous.len==len {
  var same=true; for item,index in previous { if !blot_structural::equal(item,F(context,index)) { same=false; break; } } if same { return retained_provider_frames(self_,previous); }
 }
 let items,error=alloc_provider_frames(self_,len); if error!=blot_error::Error.none { return default<const blot_backend_provider_chain::Frame[:]>(),error; } for index in 0..len { items[index]=F(context,index); } return items,blot_error::Error.none;
}
fn free_provider_frames(leases: const Leases&,items: const blot_backend_provider_chain::Frame[:]) -> Error {
 let ref=leases.values[41]; if ref.index!=0 { return release(ref); }
 if items.len!=0 {pool_provider_frames.free_slice(items);} return blot_error::Error.none;
}

fn alloc_provider_cells(self_: Builder&,len: i64) -> blot_backend_provider_chain::Cell[:],Error {
 if self_.leases.values[42].index!=0||len<0 { return default<blot_backend_provider_chain::Cell[:]>(),blot_error::Error.invalid_artifact; }
 if len==0 { return default<blot_backend_provider_chain::Cell[:]>(),blot_error::Error.none; }
 if next_generation==0xffffffffffffffff { return default<blot_backend_provider_chain::Cell[:]>(),blot_error::Error.artifact_limit; }
 let items=pool_provider_cells.alloc_slice(len); let first: const blot_backend_provider_chain::Cell& =items[0]; let start=pool_provider_cells.index_of(first);
 let ref,error=create(Field.provider_cells,start,len); if error!=blot_error::Error.none { pool_provider_cells.free_slice(items); return default<blot_backend_provider_chain::Cell[:]>(),error; }
 self_.leases.values[42]=ref; self_.stats.copied_fields++; self_.stats.copied_bytes+=bytes_of(items).len; return items,blot_error::Error.none;
}
fn shareable_provider_cells(self_: const Builder&,old: const blot_backend_provider_chain::Cell[:]) -> bool {
 if old.len==0 {return false;}let previous .=self_.previous;if !previous {return false;}
 let ref=previous.values[42]; if !valid(ref) { return false; } let meta=lease_meta[ref.index-1];
 if meta.field!=Field.provider_cells||meta.len!=old.len { return false; }
 let a: const blot_backend_provider_chain::Cell& =old[0]; let b: const blot_backend_provider_chain::Cell& =pool_provider_cells[meta.start]; return a .== b;
}
fn retained_provider_cells(self_: Builder&,old: const blot_backend_provider_chain::Cell[:]) -> const blot_backend_provider_chain::Cell[:],Error {
 let previous .=self_.previous;if !previous {return default<const blot_backend_provider_chain::Cell[:]>(),blot_error::Error.invalid_artifact;}let ref=previous.values[42]; let error=retain(ref); if error!=blot_error::Error.none { return default<const blot_backend_provider_chain::Cell[:]>(),error; }
 let meta=lease_meta[ref.index-1];
 assert(meta.field==Field.provider_cells && meta.len==old.len && meta.len>0 && meta.start>=0 && meta.start<=pool_provider_cells.len && meta.len<=pool_provider_cells.len-meta.start);
 let items=pool_provider_cells[meta.start..meta.start+meta.len];assert(blot_support::same_slice_identity(items,old));
 self_.leases.values[42]=ref; self_.stats.shared_fields++; self_.stats.shared_bytes+=bytes_of(old).len; return items,blot_error::Error.none;
}
fn dupe_provider_cells(self_: Builder&,source: const blot_backend_provider_chain::Cell[:],previous: const blot_backend_provider_chain::Cell[:]) -> const blot_backend_provider_chain::Cell[:],Error {
 if shareable_provider_cells(self_,previous)&&blot_structural::equal(source,previous) { return retained_provider_cells(self_,previous); }
 let items,error=alloc_provider_cells(self_,source.len); if error!=blot_error::Error.none { return default<const blot_backend_provider_chain::Cell[:]>(),error; } for value,index in source { items[index]=value; } return items,blot_error::Error.none;
}
fn converted_provider_cells<C,F>(self_: Builder&,len: i64,context: C&,previous: const blot_backend_provider_chain::Cell[:]) -> const blot_backend_provider_chain::Cell[:],Error {
 if shareable_provider_cells(self_,previous)&&previous.len==len {
  var same=true; for item,index in previous { if !blot_structural::equal(item,F(context,index)) { same=false; break; } } if same { return retained_provider_cells(self_,previous); }
 }
 let items,error=alloc_provider_cells(self_,len); if error!=blot_error::Error.none { return default<const blot_backend_provider_chain::Cell[:]>(),error; } for index in 0..len { items[index]=F(context,index); } return items,blot_error::Error.none;
}
fn free_provider_cells(leases: const Leases&,items: const blot_backend_provider_chain::Cell[:]) -> Error {
 let ref=leases.values[42]; if ref.index!=0 { return release(ref); }
 if items.len!=0 {pool_provider_cells.free_slice(items);} return blot_error::Error.none;
}

fn alloc_request_cells(self_: Builder&,len: i64) -> blot_reuse_code_artifacts::RequestCell[:],Error {
 if self_.leases.values[43].index!=0||len<0 { return default<blot_reuse_code_artifacts::RequestCell[:]>(),blot_error::Error.invalid_artifact; }
 if len==0 { return default<blot_reuse_code_artifacts::RequestCell[:]>(),blot_error::Error.none; }
 if next_generation==0xffffffffffffffff { return default<blot_reuse_code_artifacts::RequestCell[:]>(),blot_error::Error.artifact_limit; }
 let items=pool_request_cells.alloc_slice(len); let first: const blot_reuse_code_artifacts::RequestCell& =items[0]; let start=pool_request_cells.index_of(first);
 let ref,error=create(Field.request_cells,start,len); if error!=blot_error::Error.none { pool_request_cells.free_slice(items); return default<blot_reuse_code_artifacts::RequestCell[:]>(),error; }
 self_.leases.values[43]=ref; self_.stats.copied_fields++; self_.stats.copied_bytes+=bytes_of(items).len; return items,blot_error::Error.none;
}
fn shareable_request_cells(self_: const Builder&,old: const blot_reuse_code_artifacts::RequestCell[:]) -> bool {
 if old.len==0 {return false;}let previous .=self_.previous;if !previous {return false;}
 let ref=previous.values[43]; if !valid(ref) { return false; } let meta=lease_meta[ref.index-1];
 if meta.field!=Field.request_cells||meta.len!=old.len { return false; }
 let a: const blot_reuse_code_artifacts::RequestCell& =old[0]; let b: const blot_reuse_code_artifacts::RequestCell& =pool_request_cells[meta.start]; return a .== b;
}
fn retained_request_cells(self_: Builder&,old: const blot_reuse_code_artifacts::RequestCell[:]) -> const blot_reuse_code_artifacts::RequestCell[:],Error {
 let previous .=self_.previous;if !previous {return default<const blot_reuse_code_artifacts::RequestCell[:]>(),blot_error::Error.invalid_artifact;}let ref=previous.values[43]; let error=retain(ref); if error!=blot_error::Error.none { return default<const blot_reuse_code_artifacts::RequestCell[:]>(),error; }
 let meta=lease_meta[ref.index-1];
 assert(meta.field==Field.request_cells && meta.len==old.len && meta.len>0 && meta.start>=0 && meta.start<=pool_request_cells.len && meta.len<=pool_request_cells.len-meta.start);
 let items=pool_request_cells[meta.start..meta.start+meta.len];assert(blot_support::same_slice_identity(items,old));
 self_.leases.values[43]=ref; self_.stats.shared_fields++; self_.stats.shared_bytes+=bytes_of(old).len; return items,blot_error::Error.none;
}
fn dupe_request_cells(self_: Builder&,source: const blot_reuse_code_artifacts::RequestCell[:],previous: const blot_reuse_code_artifacts::RequestCell[:]) -> const blot_reuse_code_artifacts::RequestCell[:],Error {
 if shareable_request_cells(self_,previous)&&blot_structural::equal(source,previous) { return retained_request_cells(self_,previous); }
 let items,error=alloc_request_cells(self_,source.len); if error!=blot_error::Error.none { return default<const blot_reuse_code_artifacts::RequestCell[:]>(),error; } for value,index in source { items[index]=value; } return items,blot_error::Error.none;
}
fn converted_request_cells<C,F>(self_: Builder&,len: i64,context: C&,previous: const blot_reuse_code_artifacts::RequestCell[:]) -> const blot_reuse_code_artifacts::RequestCell[:],Error {
 if shareable_request_cells(self_,previous)&&previous.len==len {
  var same=true; for item,index in previous { if !blot_structural::equal(item,F(context,index)) { same=false; break; } } if same { return retained_request_cells(self_,previous); }
 }
 let items,error=alloc_request_cells(self_,len); if error!=blot_error::Error.none { return default<const blot_reuse_code_artifacts::RequestCell[:]>(),error; } for index in 0..len { items[index]=F(context,index); } return items,blot_error::Error.none;
}
fn free_request_cells(leases: const Leases&,items: const blot_reuse_code_artifacts::RequestCell[:]) -> Error {
 let ref=leases.values[43]; if ref.index!=0 { return release(ref); }
 if items.len!=0 {pool_request_cells.free_slice(items);} return blot_error::Error.none;
}

fn alloc_request_handlers(self_: Builder&,len: i64) -> blot_reuse_code_artifacts::RequestHandler[:],Error {
 if self_.leases.values[44].index!=0||len<0 { return default<blot_reuse_code_artifacts::RequestHandler[:]>(),blot_error::Error.invalid_artifact; }
 if len==0 { return default<blot_reuse_code_artifacts::RequestHandler[:]>(),blot_error::Error.none; }
 if next_generation==0xffffffffffffffff { return default<blot_reuse_code_artifacts::RequestHandler[:]>(),blot_error::Error.artifact_limit; }
 let items=pool_request_handlers.alloc_slice(len); let first: const blot_reuse_code_artifacts::RequestHandler& =items[0]; let start=pool_request_handlers.index_of(first);
 let ref,error=create(Field.request_handlers,start,len); if error!=blot_error::Error.none { pool_request_handlers.free_slice(items); return default<blot_reuse_code_artifacts::RequestHandler[:]>(),error; }
 self_.leases.values[44]=ref; self_.stats.copied_fields++; self_.stats.copied_bytes+=bytes_of(items).len; return items,blot_error::Error.none;
}
fn shareable_request_handlers(self_: const Builder&,old: const blot_reuse_code_artifacts::RequestHandler[:]) -> bool {
 if old.len==0 {return false;}let previous .=self_.previous;if !previous {return false;}
 let ref=previous.values[44]; if !valid(ref) { return false; } let meta=lease_meta[ref.index-1];
 if meta.field!=Field.request_handlers||meta.len!=old.len { return false; }
 let a: const blot_reuse_code_artifacts::RequestHandler& =old[0]; let b: const blot_reuse_code_artifacts::RequestHandler& =pool_request_handlers[meta.start]; return a .== b;
}
fn retained_request_handlers(self_: Builder&,old: const blot_reuse_code_artifacts::RequestHandler[:]) -> const blot_reuse_code_artifacts::RequestHandler[:],Error {
 let previous .=self_.previous;if !previous {return default<const blot_reuse_code_artifacts::RequestHandler[:]>(),blot_error::Error.invalid_artifact;}let ref=previous.values[44]; let error=retain(ref); if error!=blot_error::Error.none { return default<const blot_reuse_code_artifacts::RequestHandler[:]>(),error; }
 let meta=lease_meta[ref.index-1];
 assert(meta.field==Field.request_handlers && meta.len==old.len && meta.len>0 && meta.start>=0 && meta.start<=pool_request_handlers.len && meta.len<=pool_request_handlers.len-meta.start);
 let items=pool_request_handlers[meta.start..meta.start+meta.len];assert(blot_support::same_slice_identity(items,old));
 self_.leases.values[44]=ref; self_.stats.shared_fields++; self_.stats.shared_bytes+=bytes_of(old).len; return items,blot_error::Error.none;
}
fn dupe_request_handlers(self_: Builder&,source: const blot_reuse_code_artifacts::RequestHandler[:],previous: const blot_reuse_code_artifacts::RequestHandler[:]) -> const blot_reuse_code_artifacts::RequestHandler[:],Error {
 if shareable_request_handlers(self_,previous)&&blot_structural::equal(source,previous) { return retained_request_handlers(self_,previous); }
 let items,error=alloc_request_handlers(self_,source.len); if error!=blot_error::Error.none { return default<const blot_reuse_code_artifacts::RequestHandler[:]>(),error; } for value,index in source { items[index]=value; } return items,blot_error::Error.none;
}
fn converted_request_handlers<C,F>(self_: Builder&,len: i64,context: C&,previous: const blot_reuse_code_artifacts::RequestHandler[:]) -> const blot_reuse_code_artifacts::RequestHandler[:],Error {
 if shareable_request_handlers(self_,previous)&&previous.len==len {
  var same=true; for item,index in previous { if !blot_structural::equal(item,F(context,index)) { same=false; break; } } if same { return retained_request_handlers(self_,previous); }
 }
 let items,error=alloc_request_handlers(self_,len); if error!=blot_error::Error.none { return default<const blot_reuse_code_artifacts::RequestHandler[:]>(),error; } for index in 0..len { items[index]=F(context,index); } return items,blot_error::Error.none;
}
fn free_request_handlers(leases: const Leases&,items: const blot_reuse_code_artifacts::RequestHandler[:]) -> Error {
 let ref=leases.values[44]; if ref.index!=0 { return release(ref); }
 if items.len!=0 {pool_request_handlers.free_slice(items);} return blot_error::Error.none;
}

fn alloc_break_values(self_: Builder&,len: i64) -> u32[:],Error {
 if self_.leases.values[45].index!=0||len<0 { return default<u32[:]>(),blot_error::Error.invalid_artifact; }
 if len==0 { return default<u32[:]>(),blot_error::Error.none; }
 if next_generation==0xffffffffffffffff { return default<u32[:]>(),blot_error::Error.artifact_limit; }
 let items=pool_break_values.alloc_slice(len); let first: const u32& =items[0]; let start=pool_break_values.index_of(first);
 let ref,error=create(Field.break_values,start,len); if error!=blot_error::Error.none { pool_break_values.free_slice(items); return default<u32[:]>(),error; }
 self_.leases.values[45]=ref; self_.stats.copied_fields++; self_.stats.copied_bytes+=bytes_of(items).len; return items,blot_error::Error.none;
}
fn shareable_break_values(self_: const Builder&,old: const u32[:]) -> bool {
 if old.len==0 {return false;}let previous .=self_.previous;if !previous {return false;}
 let ref=previous.values[45]; if !valid(ref) { return false; } let meta=lease_meta[ref.index-1];
 if meta.field!=Field.break_values||meta.len!=old.len { return false; }
 let a: const u32& =old[0]; let b: const u32& =pool_break_values[meta.start]; return a .== b;
}
fn retained_break_values(self_: Builder&,old: const u32[:]) -> const u32[:],Error {
 let previous .=self_.previous;if !previous {return default<const u32[:]>(),blot_error::Error.invalid_artifact;}let ref=previous.values[45]; let error=retain(ref); if error!=blot_error::Error.none { return default<const u32[:]>(),error; }
 let meta=lease_meta[ref.index-1];
 assert(meta.field==Field.break_values && meta.len==old.len && meta.len>0 && meta.start>=0 && meta.start<=pool_break_values.len && meta.len<=pool_break_values.len-meta.start);
 let items=pool_break_values[meta.start..meta.start+meta.len];assert(blot_support::same_slice_identity(items,old));
 self_.leases.values[45]=ref; self_.stats.shared_fields++; self_.stats.shared_bytes+=bytes_of(old).len; return items,blot_error::Error.none;
}
fn dupe_break_values(self_: Builder&,source: const u32[:],previous: const u32[:]) -> const u32[:],Error {
 if shareable_break_values(self_,previous)&&blot_structural::equal(source,previous) { return retained_break_values(self_,previous); }
 let items,error=alloc_break_values(self_,source.len); if error!=blot_error::Error.none { return default<const u32[:]>(),error; } for value,index in source { items[index]=value; } return items,blot_error::Error.none;
}
fn converted_break_values<C,F>(self_: Builder&,len: i64,context: C&,previous: const u32[:]) -> const u32[:],Error {
 if shareable_break_values(self_,previous)&&previous.len==len {
  var same=true; for item,index in previous { if !blot_structural::equal(item,F(context,index)) { same=false; break; } } if same { return retained_break_values(self_,previous); }
 }
 let items,error=alloc_break_values(self_,len); if error!=blot_error::Error.none { return default<const u32[:]>(),error; } for index in 0..len { items[index]=F(context,index); } return items,blot_error::Error.none;
}
fn free_break_values(leases: const Leases&,items: const u32[:]) -> Error {
 let ref=leases.values[45]; if ref.index!=0 { return release(ref); }
 if items.len!=0 {pool_break_values.free_slice(items);} return blot_error::Error.none;
}

fn alloc_operation_relocations(self_: Builder&,len: i64) -> blot_reuse_code_artifacts::OperationRelocation[:],Error {
 if self_.leases.values[46].index!=0||len<0 { return default<blot_reuse_code_artifacts::OperationRelocation[:]>(),blot_error::Error.invalid_artifact; }
 if len==0 { return default<blot_reuse_code_artifacts::OperationRelocation[:]>(),blot_error::Error.none; }
 if next_generation==0xffffffffffffffff { return default<blot_reuse_code_artifacts::OperationRelocation[:]>(),blot_error::Error.artifact_limit; }
 let items=pool_operation_relocations.alloc_slice(len); let first: const blot_reuse_code_artifacts::OperationRelocation& =items[0]; let start=pool_operation_relocations.index_of(first);
 let ref,error=create(Field.operation_relocations,start,len); if error!=blot_error::Error.none { pool_operation_relocations.free_slice(items); return default<blot_reuse_code_artifacts::OperationRelocation[:]>(),error; }
 self_.leases.values[46]=ref; self_.stats.copied_fields++; self_.stats.copied_bytes+=bytes_of(items).len; return items,blot_error::Error.none;
}
fn shareable_operation_relocations(self_: const Builder&,old: const blot_reuse_code_artifacts::OperationRelocation[:]) -> bool {
 if old.len==0 {return false;}let previous .=self_.previous;if !previous {return false;}
 let ref=previous.values[46]; if !valid(ref) { return false; } let meta=lease_meta[ref.index-1];
 if meta.field!=Field.operation_relocations||meta.len!=old.len { return false; }
 let a: const blot_reuse_code_artifacts::OperationRelocation& =old[0]; let b: const blot_reuse_code_artifacts::OperationRelocation& =pool_operation_relocations[meta.start]; return a .== b;
}
fn retained_operation_relocations(self_: Builder&,old: const blot_reuse_code_artifacts::OperationRelocation[:]) -> const blot_reuse_code_artifacts::OperationRelocation[:],Error {
 let previous .=self_.previous;if !previous {return default<const blot_reuse_code_artifacts::OperationRelocation[:]>(),blot_error::Error.invalid_artifact;}let ref=previous.values[46]; let error=retain(ref); if error!=blot_error::Error.none { return default<const blot_reuse_code_artifacts::OperationRelocation[:]>(),error; }
 let meta=lease_meta[ref.index-1];
 assert(meta.field==Field.operation_relocations && meta.len==old.len && meta.len>0 && meta.start>=0 && meta.start<=pool_operation_relocations.len && meta.len<=pool_operation_relocations.len-meta.start);
 let items=pool_operation_relocations[meta.start..meta.start+meta.len];assert(blot_support::same_slice_identity(items,old));
 self_.leases.values[46]=ref; self_.stats.shared_fields++; self_.stats.shared_bytes+=bytes_of(old).len; return items,blot_error::Error.none;
}
fn dupe_operation_relocations(self_: Builder&,source: const blot_reuse_code_artifacts::OperationRelocation[:],previous: const blot_reuse_code_artifacts::OperationRelocation[:]) -> const blot_reuse_code_artifacts::OperationRelocation[:],Error {
 if shareable_operation_relocations(self_,previous)&&blot_structural::equal(source,previous) { return retained_operation_relocations(self_,previous); }
 let items,error=alloc_operation_relocations(self_,source.len); if error!=blot_error::Error.none { return default<const blot_reuse_code_artifacts::OperationRelocation[:]>(),error; } for value,index in source { items[index]=value; } return items,blot_error::Error.none;
}
fn converted_operation_relocations<C,F>(self_: Builder&,len: i64,context: C&,previous: const blot_reuse_code_artifacts::OperationRelocation[:]) -> const blot_reuse_code_artifacts::OperationRelocation[:],Error {
 if shareable_operation_relocations(self_,previous)&&previous.len==len {
  var same=true; for item,index in previous { if !blot_structural::equal(item,F(context,index)) { same=false; break; } } if same { return retained_operation_relocations(self_,previous); }
 }
 let items,error=alloc_operation_relocations(self_,len); if error!=blot_error::Error.none { return default<const blot_reuse_code_artifacts::OperationRelocation[:]>(),error; } for index in 0..len { items[index]=F(context,index); } return items,blot_error::Error.none;
}
fn free_operation_relocations(leases: const Leases&,items: const blot_reuse_code_artifacts::OperationRelocation[:]) -> Error {
 let ref=leases.values[46]; if ref.index!=0 { return release(ref); }
 if items.len!=0 {pool_operation_relocations.free_slice(items);} return blot_error::Error.none;
}

fn alloc_code_origins(self_: Builder&,len: i64) -> blot_check_staging_origins::Record[:],Error {
 if self_.leases.values[47].index!=0||len<0 { return default<blot_check_staging_origins::Record[:]>(),blot_error::Error.invalid_artifact; }
 if len==0 { return default<blot_check_staging_origins::Record[:]>(),blot_error::Error.none; }
 if next_generation==0xffffffffffffffff { return default<blot_check_staging_origins::Record[:]>(),blot_error::Error.artifact_limit; }
 let items=pool_code_origins.alloc_slice(len); let first: const blot_check_staging_origins::Record& =items[0]; let start=pool_code_origins.index_of(first);
 let ref,error=create(Field.code_origins,start,len); if error!=blot_error::Error.none { pool_code_origins.free_slice(items); return default<blot_check_staging_origins::Record[:]>(),error; }
 self_.leases.values[47]=ref; self_.stats.copied_fields++; self_.stats.copied_bytes+=bytes_of(items).len; return items,blot_error::Error.none;
}
fn shareable_code_origins(self_: const Builder&,old: const blot_check_staging_origins::Record[:]) -> bool {
 if old.len==0 {return false;}let previous .=self_.previous;if !previous {return false;}
 let ref=previous.values[47]; if !valid(ref) { return false; } let meta=lease_meta[ref.index-1];
 if meta.field!=Field.code_origins||meta.len!=old.len { return false; }
 let a: const blot_check_staging_origins::Record& =old[0]; let b: const blot_check_staging_origins::Record& =pool_code_origins[meta.start]; return a .== b;
}
fn retained_code_origins(self_: Builder&,old: const blot_check_staging_origins::Record[:]) -> const blot_check_staging_origins::Record[:],Error {
 let previous .=self_.previous;if !previous {return default<const blot_check_staging_origins::Record[:]>(),blot_error::Error.invalid_artifact;}let ref=previous.values[47]; let error=retain(ref); if error!=blot_error::Error.none { return default<const blot_check_staging_origins::Record[:]>(),error; }
 let meta=lease_meta[ref.index-1];
 assert(meta.field==Field.code_origins && meta.len==old.len && meta.len>0 && meta.start>=0 && meta.start<=pool_code_origins.len && meta.len<=pool_code_origins.len-meta.start);
 let items=pool_code_origins[meta.start..meta.start+meta.len];assert(blot_support::same_slice_identity(items,old));
 self_.leases.values[47]=ref; self_.stats.shared_fields++; self_.stats.shared_bytes+=bytes_of(old).len; return items,blot_error::Error.none;
}
fn dupe_code_origins(self_: Builder&,source: const blot_check_staging_origins::Record[:],previous: const blot_check_staging_origins::Record[:]) -> const blot_check_staging_origins::Record[:],Error {
 if shareable_code_origins(self_,previous)&&blot_structural::equal(source,previous) { return retained_code_origins(self_,previous); }
 let items,error=alloc_code_origins(self_,source.len); if error!=blot_error::Error.none { return default<const blot_check_staging_origins::Record[:]>(),error; } for value,index in source { items[index]=value; } return items,blot_error::Error.none;
}
fn converted_code_origins<C,F>(self_: Builder&,len: i64,context: C&,previous: const blot_check_staging_origins::Record[:]) -> const blot_check_staging_origins::Record[:],Error {
 if shareable_code_origins(self_,previous)&&previous.len==len {
  var same=true; for item,index in previous { if !blot_structural::equal(item,F(context,index)) { same=false; break; } } if same { return retained_code_origins(self_,previous); }
 }
 let items,error=alloc_code_origins(self_,len); if error!=blot_error::Error.none { return default<const blot_check_staging_origins::Record[:]>(),error; } for index in 0..len { items[index]=F(context,index); } return items,blot_error::Error.none;
}
fn free_code_origins(leases: const Leases&,items: const blot_check_staging_origins::Record[:]) -> Error {
 let ref=leases.values[47]; if ref.index!=0 { return release(ref); }
 if items.len!=0 {pool_code_origins.free_slice(items);} return blot_error::Error.none;
}
