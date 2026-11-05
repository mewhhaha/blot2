// Resolved per-function emission borrows one attempt and immutable evidence.
namespace blot_backend_backend_emission;
import dictionary;
import check.core;
import check.types;
import check.task_core;
import check.usage_check;
import check.dictionary_owner;
import .core_backend;
import .wasm;
import .runtime_ir;
import .scalar_ops;
import .simd_intrinsics;
import .simd_call;
import .layout;
import .provider_chain;
import .resolved_call;
import .resolved_body;
import .resolved_flow;
import .packed_layout;
import .numeric_rows;
import .list_traversal;
import .function_facts;
import .exact_builder;
import .ragged_builder;
import .runtime_operations;
import .linear_cursor;
import .source_origins;
import .unit_index;
import .bottom_result;
import .safe_local_sinking;
import .private_cursor;
import .dictionary_layout;
import .collection_edit_call;
import .collection_iteration;
import .inline_body;
import .known_call;
import .opaque_storage;
import .startup_emission_facts;
import reuse.refinement_receipt;
import check.numeric_proof_core;
import check.typed_staging;
import check.staging_origins;
import check.record_order;
import check.diagnostic_code;
import check.primitive_operator;
import check.cleanup_contracts;
import check.task_regions;
import check.task_types;
import work_counters;
import eval.core_eval;
import eval.closed_local_value;
import eval.type_evidence;
import reuse.substitution_keys;
import reuse.row_projection_uses;
import reuse.artifact_emitter;
import reuse.code_artifacts;
import runtime.runtime_cleanup;
import runtime.request_runtime;
import runtime.runtime_layout;
import runtime.shared_rc;
import runtime.list_runtime;
import support.error;
import support.option;
import support.pooled_map;
import support.pooled_buffer;
import .substitution_buffers;
type Error = blot_error::Error;
type Key = blot_reuse_code_artifacts::Key;
type Mapping = blot_backend_layout::Mapping;
type RowMapping = blot_backend_layout::RowMapping;
type MappingBuffer = blot_backend_substitution_buffers::Mappings;
type RowBuffer = blot_backend_substitution_buffers::Rows;
let max_parameters: i64 = 16;
let max_local_instances: i64 = 4;
struct CarrierKey { from: u32,to: u32 }
struct Template { scalar_environment: bool = false,callable_instances: u32 = 0,staged: u32 = 0,unit: u32 = 0,node: u32,environment: blot_support::Option<u32>,captures: u32 = 0,templates: u32 = 0,computation: bool = false,evidence: u32 = 0,rows: u32 = 0 }
struct ReturnTarget { node: u32,label: u32,cleanup: blot_runtime_runtime_cleanup::Mark,template_result: bool = false }
struct CarryRoot { iteration: u32,outgoing: u32,slot: u32 }
struct ContinueTarget { plan: blot_backend_resolved_flow::Loop,metadata: blot_check_core::LoopInfo,input: LoopInput,outer_cleanup: blot_runtime_runtime_cleanup::Mark,inner_cleanup: blot_runtime_runtime_cleanup::Mark,row_label: u32,head_label: u32 }
struct LoopTarget { node: u32,label: u32,cleanup: blot_runtime_runtime_cleanup::Mark,roots: const CarryRoot[:] = [],backedge: blot_support::Option<ContinueTarget> }
struct RaggedCount { plan: blot_backend_ragged_builder::Plan,count: u32,eligible: u32,budget: u32,limit: u32,exit: u32,cleanup: blot_runtime_runtime_cleanup::Mark }
enum ResolverPlan { monad,forward,run { value: blot_backend_resolved_call::Arrow },call { value: blot_backend_resolved_call::Applied } }
enum DispatchPlan { scalar { value: blot_backend_runtime_ir::Op },simd { input: u32,result: u32 },selected { key: Key,call: blot_backend_resolved_call::Applied } }
struct TemplatePreparation { metadata: Template,capture_types: u32[:],capture_roles: blot_backend_runtime_ir::Role[:],static_key: blot_support::Option<blot_reuse_code_artifacts::ClosureKey> }
struct FieldPlan { index: u32,projection: blot_check_core::Projection,variants: blot_check_core::ProjectionVariant[:],slots: u32[:] }
enum ProjectionPlan { field { value: FieldPlan },member { direct: Key,wrapper: blot_reuse_code_artifacts::CallableKey },empty_cursor { value: u32 } }
enum FactoryCallee { named { key: Key },closure { key: blot_reuse_code_artifacts::ClosureKey } }
struct FactoryPlan { callee: FactoryCallee,admitted: bool[16] = [false;16],result: Template }
struct DictionaryMemberPlan { offset: i64,signature: u32 }
struct SourceCall { key: Key,arguments: u32[16],count: i64 }
struct EvaluatedNamed { key: Key,arguments: u32[16],count: i64,captured: u32[16],capture_count: i64 }
struct NamedPlan { call: blot_backend_resolved_call::Named,spawn: blot_support::Option<blot_check_task_core::SpawnApplication>,evaluated: blot_support::Option<EvaluatedNamed>,dictionary_owner: blot_support::Option<blot_check_dictionary_owner::Owner>,dictionary_member: blot_support::Option<DictionaryMemberPlan>,factory: blot_support::Option<FactoryPlan> }
struct StaticClosurePlan { header: blot_eval_core_eval::ClosureValue,ty: u32,captured: u32[:],mappings: Mapping[:],rows: RowMapping[:] }
struct ApplyPlan { spawn: blot_support::Option<blot_check_task_core::SpawnApplication>,factory: blot_support::Option<FactoryPlan>,evaluated: blot_support::Option<EvaluatedNamed>,static_closure: blot_support::Option<StaticClosurePlan>,partial: blot_support::Option<SourceCall>,known: blot_support::Option<SourceCall>,arrow: blot_support::Option<blot_backend_resolved_call::Arrow>,universal: blot_support::Option<u32>,quantifier: u32 = 0,never: bool = false }
struct ProviderPlan { ty: blot_backend_layout::Node,read: u32,write: blot_support::Option<u32> }
struct StagingPlan { value: u32,body: blot_support::Option<u32> }
struct LocalInstance { layout: u32,body: u32 }
struct StaticBinding { binding: u32,value: u32 }
enum Plan {
    staging { value: StagingPlan },static_binding { value: u32 },instances { value: LocalInstance[:] },operation { ty: u32,label: u32 },provider { value: ProviderPlan },projection { value: blot_support::Option<ProjectionPlan> },update_locations { value: FieldPlan[:] },pattern { value: blot_support::Option<StaticBinding[:]> },template { value: TemplatePreparation },reference { value: blot_support::Option<blot_check_core::BindingRef> },named { value: NamedPlan },application { value: ApplyPlan },
    resource_scope { acquire: u32,release: u32,callback: u32 },usage_borrow { value: u32 },usage_read { value: u32 },usage_share { value: u32 },resolver { value: ResolverPlan },dispatch { value: DispatchPlan },comparison { value: bool },constructor_subject { value: u32 },result_member { value: blot_reuse_code_artifacts::CallableKey },join { value: blot_backend_resolved_flow::Join },match_ { value: blot_backend_resolved_flow::Match },loop_ { value: blot_backend_resolved_flow::Loop },exit { value: blot_backend_resolved_flow::SymbolicExit },request { value: blot_backend_resolved_flow::RequestLoop },collection_step { pattern: u32,receiver: u32,key: Key },collection_pattern,private_cursor { input: u32,linear: blot_support::Option<blot_backend_linear_cursor::Plan> },private_row { value: u32 },private_pattern { value: u32 },
}
struct InstanceReads { nodes: u32[32],len: i64 = 0 }
struct FactRange { start: i64 = 0,len: i64 = 0 }
struct InstanceDecision { statement: u32,count: i64 = 0,layouts: u32[4],facts: FactRange[4] = [FactRange {};4],rows: FactRange[4] = [FactRange {};4],reads: InstanceReads }
struct InstanceDecisions { decisions: DecisionBuffer,facts: MappingBuffer,rows: RowBuffer }
fn deinit(decisions: InstanceDecisions&) { decisions.decisions.deinit(); decisions.facts.deinit(); decisions.rows.deinit(); }
fn find(decisions: const InstanceDecisions&,statement: u32) -> const InstanceDecision&? { for decision in decisions.decisions.items { if decision.statement == statement { return decision; } } return null; }
fn factsAt(decisions: const InstanceDecisions&,decision: const InstanceDecision&,index: i64) -> const Mapping[:] { let range = decision.facts[index]; return decisions.facts.items[range.start..range.start + range.len]; }
fn rowsAt(decisions: const InstanceDecisions&,decision: const InstanceDecision&,index: i64) -> const RowMapping[:] { let range = decision.rows[index]; return decisions.rows.items[range.start..range.start + range.len]; }
fn reader(decisions: const InstanceDecisions&,node: u32) -> const InstanceDecision&? { for decision in decisions.decisions.items { for read in decision.reads.nodes[..decision.reads.len] { if read == node { return decision; } } } return null; }
struct InstanceLocals { count: i64 = 0,layouts: u32[4],locals: u32[4] }
struct RowView { binding: u32,row: u32,address: u32,limit_address: u32 }
struct ListDirectory { storage: u32,array: u32,offset: u32 }
struct CursorDirectory { directory: ListDirectory,span: u32[3] }
struct LayoutEntry { ty: u32 = 0,value: u32 = 0 }
enum SmallKind { collection,cursor }
struct SmallCollection { values: u32[blot_backend_function_facts::small_limit],len: i64 = 0,machine: blot_backend_runtime_ir::ValueType = blot_backend_runtime_ir::VT_i32,kind: SmallKind = SmallKind.collection }
struct PlannedReturn { node: u32,template_result: bool }
struct SmallResult { root: u32 = 0,slot: u32 = 0 }
struct SmallOutput { live: bool = false,value: SmallCollection }
var small_outputs: SmallOutput[>..] = [];
var free_small_outputs: u32[>..<] = [];
fn allocateSmallOutput(value: SmallCollection) -> u32,Error { var id: u32 = 0; if free_small_outputs.len != 0 { id = free_small_outputs[free_small_outputs.len - 1]; free_small_outputs.resize(free_small_outputs.len - 1); } else { if small_outputs.len >= 4294967295 { return 0,Error.module_too_large; } small_outputs.push(SmallOutput {}); id = small_outputs.len as u32; } small_outputs[id - 1] = SmallOutput { true,value }; return id,Error.none; }
fn releaseSmallOutput(id: u32) { assert(id != 0 && id <= small_outputs.len && small_outputs[id - 1].live); small_outputs[id - 1].live = false; free_small_outputs.push(id); }
struct ExactBuild { plan: blot_backend_exact_builder::Plan,storage: u32,index: u32,row_words: u32 }
struct SemanticContext { mappings: u32,rows: u32 }
struct LoopInput { counter: u32,end: u32,array_local: u32,list_span: blot_support::Option<u32[3]>,small: blot_support::Option<SmallCollection>,borrowed_view: blot_support::Option<RowView>,row_view: blot_support::Option<RowView>,array_view: blot_support::Option<RowView>,list_directory: blot_support::Option<ListDirectory> }
struct WordBuffer { storage: u32[:] = [],items: u32[:] = [] }
reusable[] var buffer_WordBuffer: u32[>..] = [];
fn push(buffer: WordBuffer&,value: u32) -> Error { return blot_support_pooled_buffer::push(buffer,value,buffer_WordBuffer); }
fn append(buffer: WordBuffer&,values: const u32[:]) -> Error { return blot_support_pooled_buffer::append(buffer,values,buffer_WordBuffer); }
fn clear(buffer: WordBuffer&) { blot_support_pooled_buffer::clear(buffer); }
fn resize(buffer: WordBuffer&,length: i64) { blot_support_pooled_buffer::resize(buffer,length); }
fn deinit(buffer: WordBuffer&) { blot_support_pooled_buffer::deinit(buffer,buffer_WordBuffer); }
struct DecisionBuffer { storage: InstanceDecision[:] = [],items: InstanceDecision[:] = [] }
reusable[] var buffer_DecisionBuffer: InstanceDecision[>..] = [];
fn push(buffer: DecisionBuffer&,value: InstanceDecision) -> Error { return blot_support_pooled_buffer::push(buffer,value,buffer_DecisionBuffer); }
fn append(buffer: DecisionBuffer&,values: const InstanceDecision[:]) -> Error { return blot_support_pooled_buffer::append(buffer,values,buffer_DecisionBuffer); }
fn clear(buffer: DecisionBuffer&) { blot_support_pooled_buffer::clear(buffer); }
fn resize(buffer: DecisionBuffer&,length: i64) { blot_support_pooled_buffer::resize(buffer,length); }
fn deinit(buffer: DecisionBuffer&) { blot_support_pooled_buffer::deinit(buffer,buffer_DecisionBuffer); }
struct PlannedReturnBuffer { storage: PlannedReturn[:] = [],items: PlannedReturn[:] = [] }
reusable[] var buffer_PlannedReturnBuffer: PlannedReturn[>..] = [];
fn push(buffer: PlannedReturnBuffer&,value: PlannedReturn) -> Error { return blot_support_pooled_buffer::push(buffer,value,buffer_PlannedReturnBuffer); }
fn append(buffer: PlannedReturnBuffer&,values: const PlannedReturn[:]) -> Error { return blot_support_pooled_buffer::append(buffer,values,buffer_PlannedReturnBuffer); }
fn clear(buffer: PlannedReturnBuffer&) { blot_support_pooled_buffer::clear(buffer); }
fn resize(buffer: PlannedReturnBuffer&,length: i64) { blot_support_pooled_buffer::resize(buffer,length); }
fn deinit(buffer: PlannedReturnBuffer&) { blot_support_pooled_buffer::deinit(buffer,buffer_PlannedReturnBuffer); }
struct RowViewBuffer { storage: RowView[:] = [],items: RowView[:] = [] }
reusable[] var buffer_RowViewBuffer: RowView[>..] = [];
fn push(buffer: RowViewBuffer&,value: RowView) -> Error { return blot_support_pooled_buffer::push(buffer,value,buffer_RowViewBuffer); }
fn append(buffer: RowViewBuffer&,values: const RowView[:]) -> Error { return blot_support_pooled_buffer::append(buffer,values,buffer_RowViewBuffer); }
fn clear(buffer: RowViewBuffer&) { blot_support_pooled_buffer::clear(buffer); }
fn resize(buffer: RowViewBuffer&,length: i64) { blot_support_pooled_buffer::resize(buffer,length); }
fn deinit(buffer: RowViewBuffer&) { blot_support_pooled_buffer::deinit(buffer,buffer_RowViewBuffer); }
struct ReturnTargetBuffer { storage: ReturnTarget[:] = [],items: ReturnTarget[:] = [] }
reusable[] var buffer_ReturnTargetBuffer: ReturnTarget[>..] = [];
fn push(buffer: ReturnTargetBuffer&,value: ReturnTarget) -> Error { return blot_support_pooled_buffer::push(buffer,value,buffer_ReturnTargetBuffer); }
fn append(buffer: ReturnTargetBuffer&,values: const ReturnTarget[:]) -> Error { return blot_support_pooled_buffer::append(buffer,values,buffer_ReturnTargetBuffer); }
fn clear(buffer: ReturnTargetBuffer&) { blot_support_pooled_buffer::clear(buffer); }
fn resize(buffer: ReturnTargetBuffer&,length: i64) { blot_support_pooled_buffer::resize(buffer,length); }
fn deinit(buffer: ReturnTargetBuffer&) { blot_support_pooled_buffer::deinit(buffer,buffer_ReturnTargetBuffer); }
struct LoopTargetBuffer { storage: LoopTarget[:] = [],items: LoopTarget[:] = [] }
reusable[] var buffer_LoopTargetBuffer: LoopTarget[>..] = [];
fn push(buffer: LoopTargetBuffer&,value: LoopTarget) -> Error { return blot_support_pooled_buffer::push(buffer,value,buffer_LoopTargetBuffer); }
fn append(buffer: LoopTargetBuffer&,values: const LoopTarget[:]) -> Error { return blot_support_pooled_buffer::append(buffer,values,buffer_LoopTargetBuffer); }
fn clear(buffer: LoopTargetBuffer&) { blot_support_pooled_buffer::clear(buffer); }
fn resize(buffer: LoopTargetBuffer&,length: i64) { blot_support_pooled_buffer::resize(buffer,length); }
fn deinit(buffer: LoopTargetBuffer&) { blot_support_pooled_buffer::deinit(buffer,buffer_LoopTargetBuffer); }
struct RoleBuffer { storage: blot_backend_runtime_ir::Role[:] = [],items: blot_backend_runtime_ir::Role[:] = [] }
reusable[] var buffer_RoleBuffer: blot_backend_runtime_ir::Role[>..] = [];
fn push(buffer: RoleBuffer&,value: blot_backend_runtime_ir::Role) -> Error { return blot_support_pooled_buffer::push(buffer,value,buffer_RoleBuffer); }
fn append(buffer: RoleBuffer&,values: const blot_backend_runtime_ir::Role[:]) -> Error { return blot_support_pooled_buffer::append(buffer,values,buffer_RoleBuffer); }
fn clear(buffer: RoleBuffer&) { blot_support_pooled_buffer::clear(buffer); }
fn resize(buffer: RoleBuffer&,length: i64) { blot_support_pooled_buffer::resize(buffer,length); }
fn deinit(buffer: RoleBuffer&) { blot_support_pooled_buffer::deinit(buffer,buffer_RoleBuffer); }
struct InstructionBuffer { storage: blot_backend_runtime_ir::Instruction[:] = [],items: blot_backend_runtime_ir::Instruction[:] = [] }
reusable[] var buffer_InstructionBuffer: blot_backend_runtime_ir::Instruction[>..] = [];
fn push(buffer: InstructionBuffer&,value: blot_backend_runtime_ir::Instruction) -> Error { return blot_support_pooled_buffer::push(buffer,value,buffer_InstructionBuffer); }
fn append(buffer: InstructionBuffer&,values: const blot_backend_runtime_ir::Instruction[:]) -> Error { return blot_support_pooled_buffer::append(buffer,values,buffer_InstructionBuffer); }
fn clear(buffer: InstructionBuffer&) { blot_support_pooled_buffer::clear(buffer); }
fn resize(buffer: InstructionBuffer&,length: i64) { blot_support_pooled_buffer::resize(buffer,length); }
fn deinit(buffer: InstructionBuffer&) { blot_support_pooled_buffer::deinit(buffer,buffer_InstructionBuffer); }
struct LayoutNodeBuffer { storage: blot_backend_layout::Node[:] = [],items: blot_backend_layout::Node[:] = [] }
reusable[] var buffer_LayoutNodeBuffer: blot_backend_layout::Node[>..] = [];
fn push(buffer: LayoutNodeBuffer&,value: blot_backend_layout::Node) -> Error { return blot_support_pooled_buffer::push(buffer,value,buffer_LayoutNodeBuffer); }
fn append(buffer: LayoutNodeBuffer&,values: const blot_backend_layout::Node[:]) -> Error { return blot_support_pooled_buffer::append(buffer,values,buffer_LayoutNodeBuffer); }
fn clear(buffer: LayoutNodeBuffer&) { blot_support_pooled_buffer::clear(buffer); }
fn resize(buffer: LayoutNodeBuffer&,length: i64) { blot_support_pooled_buffer::resize(buffer,length); }
fn deinit(buffer: LayoutNodeBuffer&) { blot_support_pooled_buffer::deinit(buffer,buffer_LayoutNodeBuffer); }
struct FieldBuffer { storage: FieldPlan[:] = [],items: FieldPlan[:] = [] }
reusable[] var buffer_FieldBuffer: FieldPlan[>..] = [];
fn push(buffer: FieldBuffer&,value: FieldPlan) -> Error { return blot_support_pooled_buffer::push(buffer,value,buffer_FieldBuffer); }
fn append(buffer: FieldBuffer&,values: const FieldPlan[:]) -> Error { return blot_support_pooled_buffer::append(buffer,values,buffer_FieldBuffer); }
fn clear(buffer: FieldBuffer&) { blot_support_pooled_buffer::clear(buffer); }
fn resize(buffer: FieldBuffer&,length: i64) { blot_support_pooled_buffer::resize(buffer,length); }
fn deinit(buffer: FieldBuffer&) { blot_support_pooled_buffer::deinit(buffer,buffer_FieldBuffer); }
struct VariantBuffer { storage: blot_check_core::ProjectionVariant[:] = [],items: blot_check_core::ProjectionVariant[:] = [] }
reusable[] var buffer_VariantBuffer: blot_check_core::ProjectionVariant[>..] = [];
fn push(buffer: VariantBuffer&,value: blot_check_core::ProjectionVariant) -> Error { return blot_support_pooled_buffer::push(buffer,value,buffer_VariantBuffer); }
fn append(buffer: VariantBuffer&,values: const blot_check_core::ProjectionVariant[:]) -> Error { return blot_support_pooled_buffer::append(buffer,values,buffer_VariantBuffer); }
fn clear(buffer: VariantBuffer&) { blot_support_pooled_buffer::clear(buffer); }
fn resize(buffer: VariantBuffer&,length: i64) { blot_support_pooled_buffer::resize(buffer,length); }
fn deinit(buffer: VariantBuffer&) { blot_support_pooled_buffer::deinit(buffer,buffer_VariantBuffer); }
struct BindingBuffer { storage: StaticBinding[:] = [],items: StaticBinding[:] = [] }
reusable[] var buffer_BindingBuffer: StaticBinding[>..] = [];
fn push(buffer: BindingBuffer&,value: StaticBinding) -> Error { return blot_support_pooled_buffer::push(buffer,value,buffer_BindingBuffer); }
fn append(buffer: BindingBuffer&,values: const StaticBinding[:]) -> Error { return blot_support_pooled_buffer::append(buffer,values,buffer_BindingBuffer); }
fn clear(buffer: BindingBuffer&) { blot_support_pooled_buffer::clear(buffer); }
fn resize(buffer: BindingBuffer&,length: i64) { blot_support_pooled_buffer::resize(buffer,length); }
fn deinit(buffer: BindingBuffer&) { blot_support_pooled_buffer::deinit(buffer,buffer_BindingBuffer); }
struct CarryRootBuffer { storage: CarryRoot[:] = [],items: CarryRoot[:] = [] }
reusable[] var buffer_CarryRootBuffer: CarryRoot[>..] = [];
fn push(buffer: CarryRootBuffer&,value: CarryRoot) -> Error { return blot_support_pooled_buffer::push(buffer,value,buffer_CarryRootBuffer); }
fn append(buffer: CarryRootBuffer&,values: const CarryRoot[:]) -> Error { return blot_support_pooled_buffer::append(buffer,values,buffer_CarryRootBuffer); }
fn clear(buffer: CarryRootBuffer&) { blot_support_pooled_buffer::clear(buffer); }
fn resize(buffer: CarryRootBuffer&,length: i64) { blot_support_pooled_buffer::resize(buffer,length); }
fn deinit(buffer: CarryRootBuffer&) { blot_support_pooled_buffer::deinit(buffer,buffer_CarryRootBuffer); }
struct LocalMap { table: blot_support_pooled_map::Map<u32,u32> }
reusable[] var slots_LocalMap: dictionary_slot<u32,u32>[>..] = [];
fn get(map: const LocalMap&,key: u32) -> u32? { return blot_support_pooled_map::get(map.table,key); }
fn contains(map: const LocalMap&,key: u32) -> bool { return blot_support_pooled_map::contains(map.table,key); }
fn insert(map: LocalMap&,key: u32,value: u32) -> bool { return blot_support_pooled_map::insert(map.table,key,value,slots_LocalMap); }
fn remove(map: LocalMap&,key: u32) -> bool { return blot_support_pooled_map::remove(map.table,key); }
fn clear(map: LocalMap&) { blot_support_pooled_map::clear(map.table); }
fn clone(map: const LocalMap&) -> LocalMap { return LocalMap { blot_support_pooled_map::clone(map.table,slots_LocalMap) }; }
fn deinit(map: LocalMap&) { blot_support_pooled_map::deinit(map.table,slots_LocalMap); }
fn each<F>(map: LocalMap&) { blot_support_pooled_map::each(map.table,F); }
struct TemplateMap { table: blot_support_pooled_map::Map<u32,Template> }
reusable[] var slots_TemplateMap: dictionary_slot<u32,Template>[>..] = [];
fn get(map: const TemplateMap&,key: u32) -> Template? { return blot_support_pooled_map::get(map.table,key); }
fn contains(map: const TemplateMap&,key: u32) -> bool { return blot_support_pooled_map::contains(map.table,key); }
fn insert(map: TemplateMap&,key: u32,value: Template) -> bool { return blot_support_pooled_map::insert(map.table,key,value,slots_TemplateMap); }
fn remove(map: TemplateMap&,key: u32) -> bool { return blot_support_pooled_map::remove(map.table,key); }
fn clear(map: TemplateMap&) { blot_support_pooled_map::clear(map.table); }
fn clone(map: const TemplateMap&) -> TemplateMap { return TemplateMap { blot_support_pooled_map::clone(map.table,slots_TemplateMap) }; }
fn deinit(map: TemplateMap&) { blot_support_pooled_map::deinit(map.table,slots_TemplateMap); }
fn each<F>(map: TemplateMap&) { blot_support_pooled_map::each(map.table,F); }
struct SmallMap { table: blot_support_pooled_map::Map<u32,SmallCollection> }
reusable[] var slots_SmallMap: dictionary_slot<u32,SmallCollection>[>..] = [];
fn get(map: const SmallMap&,key: u32) -> SmallCollection? { return blot_support_pooled_map::get(map.table,key); }
fn contains(map: const SmallMap&,key: u32) -> bool { return blot_support_pooled_map::contains(map.table,key); }
fn insert(map: SmallMap&,key: u32,value: SmallCollection) -> bool { return blot_support_pooled_map::insert(map.table,key,value,slots_SmallMap); }
fn remove(map: SmallMap&,key: u32) -> bool { return blot_support_pooled_map::remove(map.table,key); }
fn clear(map: SmallMap&) { blot_support_pooled_map::clear(map.table); }
fn clone(map: const SmallMap&) -> SmallMap { return SmallMap { blot_support_pooled_map::clone(map.table,slots_SmallMap) }; }
fn deinit(map: SmallMap&) { blot_support_pooled_map::deinit(map.table,slots_SmallMap); }
fn each<F>(map: SmallMap&) { blot_support_pooled_map::each(map.table,F); }
struct CursorMap { table: blot_support_pooled_map::Map<u32,CursorDirectory> }
reusable[] var slots_CursorMap: dictionary_slot<u32,CursorDirectory>[>..] = [];
fn get(map: const CursorMap&,key: u32) -> CursorDirectory? { return blot_support_pooled_map::get(map.table,key); }
fn contains(map: const CursorMap&,key: u32) -> bool { return blot_support_pooled_map::contains(map.table,key); }
fn insert(map: CursorMap&,key: u32,value: CursorDirectory) -> bool { return blot_support_pooled_map::insert(map.table,key,value,slots_CursorMap); }
fn remove(map: CursorMap&,key: u32) -> bool { return blot_support_pooled_map::remove(map.table,key); }
fn clear(map: CursorMap&) { blot_support_pooled_map::clear(map.table); }
fn clone(map: const CursorMap&) -> CursorMap { return CursorMap { blot_support_pooled_map::clone(map.table,slots_CursorMap) }; }
fn deinit(map: CursorMap&) { blot_support_pooled_map::deinit(map.table,slots_CursorMap); }
fn each<F>(map: CursorMap&) { blot_support_pooled_map::each(map.table,F); }
struct InstanceMap { table: blot_support_pooled_map::Map<u32,InstanceLocals> }
reusable[] var slots_InstanceMap: dictionary_slot<u32,InstanceLocals>[>..] = [];
fn get(map: const InstanceMap&,key: u32) -> InstanceLocals? { return blot_support_pooled_map::get(map.table,key); }
fn contains(map: const InstanceMap&,key: u32) -> bool { return blot_support_pooled_map::contains(map.table,key); }
fn insert(map: InstanceMap&,key: u32,value: InstanceLocals) -> bool { return blot_support_pooled_map::insert(map.table,key,value,slots_InstanceMap); }
fn remove(map: InstanceMap&,key: u32) -> bool { return blot_support_pooled_map::remove(map.table,key); }
fn clear(map: InstanceMap&) { blot_support_pooled_map::clear(map.table); }
fn clone(map: const InstanceMap&) -> InstanceMap { return InstanceMap { blot_support_pooled_map::clone(map.table,slots_InstanceMap) }; }
fn deinit(map: InstanceMap&) { blot_support_pooled_map::deinit(map.table,slots_InstanceMap); }
fn each<F>(map: InstanceMap&) { blot_support_pooled_map::each(map.table,F); }
struct Owner {
    body: blot_support::Option<u32>,staged: blot_support::Option<u32>,preparation_depth: u16 = 0,preparing: bool = false,has_collection_steps: bool = false,
    planned_returns: PlannedReturnBuffer,planned_loops: WordBuffer,small_values: SmallMap,row_views: RowViewBuffer,diagnostic_context: u32 = 0,cursor_directories: CursorMap,small_result: SmallResult = SmallResult {},
    analysis_root: u32 = 0,exact_probe: bool = false,exact_build: blot_support::Option<ExactBuild>,ragged_fill: bool = false,ragged_count: blot_support::Option<RaggedCount>,
    generator: blot_backend_core_backend::Generator&,unit_id: u32,function_id: u32,semantic_node: u32 = 0,semantic_context: blot_support::Option<SemanticContext>,provider_local: blot_support::Option<u32>,dictionary_local: blot_support::Option<u32>,dictionary_owner: blot_support::Option<blot_check_dictionary_owner::Owner>,
    mappings: const Mapping[:],row_mappings: const RowMapping[:] = [],locals: LocalMap,cleanups: blot_runtime_runtime_cleanup::Stack,return_targets: ReturnTargetBuffer,loop_targets: LoopTargetBuffer,labels: u32 = 0,
    templates: TemplateMap,static_values: LocalMap,computation_values: LocalMap,result_template: blot_support::Option<u32>,factory_template: bool = false,owned_edit: blot_support::Option<u32>,inline_depth: u8 = 0,inline_loop: bool = false,
    local_instances: blot_support::Option<InstanceDecisions>,instance_locals: InstanceMap,layout_cache: LayoutEntry[32] = [LayoutEntry {};32],
}
struct Config { staged: blot_support::Option<u32>,generator: blot_backend_core_backend::Generator&,unit_id: u32,function_id: u32,provider_local: blot_support::Option<u32>,mappings: const Mapping[:],row_mappings: const RowMapping[:] = [],factory_template: bool = false }
fn withOwner<C,F>(config: Config,context: C&) -> Error {
    let cleanups,error = blot_runtime_runtime_cleanup::initPooled(); if error != Error.none { return error; }
    var owner = Owner { staged: config.staged,generator: config.generator,unit_id: config.unit_id,function_id: config.function_id,provider_local: config.provider_local,mappings: config.mappings,row_mappings: config.row_mappings,cleanups: cleanups,factory_template: config.factory_template };
    
    recursive fn cleanup_continuation_82() -> Error {
 return F(context,owner);

    }
    let cleanup_result_82_0 = cleanup_continuation_82();
     owner.deinit(); 
    return cleanup_result_82_0;
}
reusable[] var owned_words: u32[>..] = [];
reusable[] var owned_roles: blot_backend_runtime_ir::Role[>..] = [];
reusable[] var owned_variants: blot_check_core::ProjectionVariant[>..] = [];
reusable[] var owned_fields: FieldPlan[>..] = [];
reusable[] var owned_bindings: StaticBinding[>..] = [];
reusable[] var owned_instances: LocalInstance[>..] = [];
reusable[] var owned_mappings: Mapping[>..] = [];
reusable[] var owned_rows: RowMapping[>..] = [];
fn freeWords(values: const u32[:]) { if values.len != 0 { let first: const u32& = values[0]; let at = owned_words.index_of(first); owned_words.free_slice(owned_words[at..at + values.len]); } }
fn freeRoles(values: const blot_backend_runtime_ir::Role[:]) { if values.len != 0 { let first: const blot_backend_runtime_ir::Role& = values[0]; let at = owned_roles.index_of(first); owned_roles.free_slice(owned_roles[at..at + values.len]); } }
fn freeMappings(values: const Mapping[:]) { if values.len != 0 { let first: const Mapping& = values[0]; let at = owned_mappings.index_of(first); owned_mappings.free_slice(owned_mappings[at..at + values.len]); } }
fn freeRows(values: const RowMapping[:]) { if values.len != 0 { let first: const RowMapping& = values[0]; let at = owned_rows.index_of(first); owned_rows.free_slice(owned_rows[at..at + values.len]); } }
fn deinit(field: FieldPlan&) { if field.variants.len != 0 { let first: const blot_check_core::ProjectionVariant& = field.variants[0]; let at = owned_variants.index_of(first); owned_variants.free_slice(owned_variants[at..at + field.variants.len]); } freeWords(field.slots); field.variants = []; field.slots = []; }
fn deinit(projection: ProjectionPlan&) { match projection { field p=>{ var field = p.value; field.deinit(); },_=>{}, } }
fn deinit(preparation: TemplatePreparation&) { freeWords(preparation.capture_types); freeRoles(preparation.capture_roles); preparation.capture_types = []; preparation.capture_roles = []; }
fn deinit(plan: StaticClosurePlan&) { freeWords(plan.captured); freeMappings(plan.mappings); freeRows(plan.rows); plan.captured = []; plan.mappings = []; plan.rows = []; }
fn deinit(plan: NamedPlan&) { plan.call.deinit(); }
fn deinit(plan: ApplyPlan&) { if plan.static_closure.present { plan.static_closure.value.deinit(); } }
recursive fn deinit(plan: Plan&,bodies: blot_backend_resolved_body::Store<Plan>&) {
    match plan {
        staging p=>{ if p.value.body.present { bodies.release(p.value.body.value); } },
        instances p=>{ for instance in p.value { bodies.release(instance.body); } if p.value.len != 0 { let first: const LocalInstance& = p.value[0]; let at = owned_instances.index_of(first); owned_instances.free_slice(owned_instances[at..at + p.value.len]); } },
        request p=>{ var request = p.value; request.deinit(); },
        pattern p=>{ if p.value.present && p.value.value.len != 0 { let first: const StaticBinding& = p.value.value[0]; let at = owned_bindings.index_of(first); owned_bindings.free_slice(owned_bindings[at..at + p.value.value.len]); } },
        template p=>{ var preparation = p.value; preparation.deinit(); },projection p=>{ if p.value.present { var projection = p.value.value; projection.deinit(); } },
        update_locations p=>{ for field in p.value { field.deinit(); } if p.value.len != 0 { let first: const FieldPlan& = p.value[0]; let at = owned_fields.index_of(first); owned_fields.free_slice(owned_fields[at..at + p.value.len]); } },
        named p=>{ var named = p.value; named.deinit(); },application p=>{ var application = p.value; application.deinit(); },
        resolver p=>{ match p.value { call c=>{ var call = c.value; call.deinit(); },_=>{}, } },
        dispatch p=>{ match p.value { selected s=>{ var call = s.call; call.deinit(); },_=>{}, } },_=>{},
    }
}
fn deinit(owner: Owner&) {
    owner.planned_returns.deinit(); owner.planned_loops.deinit(); owner.row_views.deinit(); owner.cursor_directories.deinit(); owner.small_values.deinit(); owner.locals.deinit(); owner.cleanups.deinit(); owner.return_targets.deinit(); owner.loop_targets.deinit(); owner.templates.deinit(); owner.static_values.deinit(); owner.computation_values.deinit(); owner.instance_locals.deinit();
}
fn operationConstant(owner: Owner&,operation: u32) -> Error { let error = owner.generator.planning.runtime_operations.emit(owner.generator.module,owner.function_id,operation); if error == Error.invalid_operation { return Error.invalid_function_reference; } return error; }
fn resolvedPlan(owner: Owner&,id: u32) -> Plan {
    owner.generator.evaluator.counters.resolved_plan_reads++; assert(owner.body.present); let prepared = owner.generator.planning.bodies.get(owner.body.value,id);
    match prepared {
        join p=>{ owner.generator.evaluator.counters.prepared_joins++; },
        match_ p=>{ owner.generator.evaluator.counters.prepared_joins++; owner.generator.evaluator.counters.prepared_matches++; },
        loop_ p=>{ owner.generator.evaluator.counters.prepared_loops++; },exit p=>{ owner.generator.evaluator.counters.prepared_exits++; },
        request p=>{ owner.generator.evaluator.counters.prepared_exits += 2; owner.generator.evaluator.counters.prepared_request_loops++; },_=>{},
    } return prepared;
}
fn inlineContext(owner: Owner&) -> u32,Error {
    let generator .= owner.generator; if !generator.memory_profile || owner.semantic_node == 0 { return owner.diagnostic_context,Error.none; }
    let context,error = generator.diagnostic_contexts.intern(blot_backend_source_origins::Context { unit: owner.unit_id,node: owner.semantic_node,parent: owner.diagnostic_context }); if error != Error.none { if error == Error.out_of_memory { return 0,error; } return 0,generator.fail(owner.unit_id,owner.semantic_node,blot_backend_core_backend::Code.complexity); } return context,Error.none;
}
fn recordSemantic(owner: Owner&,op: blot_backend_runtime_ir::Op,operand: u32) -> Error {
    if owner.semantic_node == 0 { return Error.none; } let generator .= owner.generator; let call = op == blot_backend_runtime_ir::OP_call || op == blot_backend_runtime_ir::OP_call_indirect || op == blot_backend_runtime_ir::OP_call_import;
    let memory = generator.memory_profile && (blot_backend_runtime_ir::fixed(op).bytes != 0 || op == blot_backend_runtime_ir::OP_memory_copy || op == blot_backend_runtime_ir::OP_memory_fill); if !call && !memory { return Error.none; }
    var kind = blot_backend_wasm::SemanticKind.call;
    if memory { kind = blot_backend_wasm::SemanticKind.diagnostic_memory; }
    else if op == blot_backend_runtime_ir::OP_call && generator.module.arena.present && generator.module.arena.value.isAllocation(operand) { kind = blot_backend_wasm::SemanticKind.allocation; }
    else if op == blot_backend_runtime_ir::OP_call && generator.module.runtimeHelper(operand) { if !generator.memory_profile { return Error.none; } kind = blot_backend_wasm::SemanticKind.diagnostic_call; }
    if !owner.semantic_context.present {
        let mappings,error = generator.mappingEvidence(owner.mappings); if error != Error.none { return error; } let rows,row_error = generator.rowMappingEvidence(owner.row_mappings); if row_error != Error.none { return row_error; } owner.semantic_context = blot_support::some(SemanticContext { mappings,rows });
    }
    var root = owner.analysis_root; if owner.body.present { root = generator.planning.bodies.header(owner.body.value).root; }
    return generator.module.recordSemanticSite(blot_backend_wasm::SemanticSite { diagnostic_context: owner.diagnostic_context,function: owner.function_id,place: generator.module.functions[owner.function_id].instructions.len as u32,unit: owner.unit_id,node: owner.semantic_node,root: root,mappings: owner.semantic_context.value.mappings,rows: owner.semantic_context.value.rows,kind: kind });
}
fn emit(owner: Owner&,op: blot_backend_runtime_ir::Op,operand: u32 = 0) -> Error {
    assert(!owner.preparing); let semantic = recordSemantic(owner,op,operand); if semantic != Error.none { return semantic; }
    let emitted = owner.generator.module.emit(owner.function_id,blot_backend_runtime_ir::instruction(op,operand)); if emitted != Error.none { return emitted; }
    if op == blot_backend_runtime_ir::OP_call && owner.generator.module.runtimeHelper(operand) { return Error.none; }
    if op == blot_backend_runtime_ir::OP_call || op == blot_backend_runtime_ir::OP_call_indirect || op == blot_backend_runtime_ir::OP_call_import { if owner.generator.request_owner.present { return blot_runtime_request_runtime::guard(owner.generator.module,owner.function_id,owner.generator.request_owner.value,owner.cleanups); } } return Error.none;
}
fn referenceConstant(owner: Owner&,value: u32,role: blot_reuse_artifact_emitter::Role) -> Error {
    if role == blot_reuse_artifact_emitter::Role.static_address { let marker = owner.generator.module.emit(owner.function_id,blot_backend_runtime_ir::immortalReference()); if marker != Error.none { return marker; } } return owner.generator.module.emitReference(owner.function_id,blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,value),role);
}
fn emitUnguarded(owner: Owner&,op: blot_backend_runtime_ir::Op,operand: u32) -> Error { let semantic = recordSemantic(owner,op,operand); if semantic != Error.none { return semantic; } return owner.generator.module.emit(owner.function_id,blot_backend_runtime_ir::instruction(op,operand)); }
fn providerHead(owner: Owner&) -> Error { if owner.provider_local.present { return emit(owner,blot_backend_runtime_ir::OP_local_get,owner.provider_local.value); } return emit(owner,blot_backend_runtime_ir::OP_i32_const,0); }
fn temporary(owner: Owner&,machine: blot_backend_runtime_ir::ValueType) -> u32,Error { assert(!owner.preparing); return owner.generator.module.addLocal(owner.function_id,machine); }
struct AllocationRoles { words: const blot_backend_runtime_ir::Role[:] = [],rest: blot_backend_runtime_ir::Role = blot_backend_runtime_ir::ROLE_unknown }
fn layoutRoles(owner: Owner&,layouts: const u32[:],roles: blot_backend_runtime_ir::Role[>..<]&) -> Error { for layout in layouts { roles.push(owner.generator.layoutRole(layout)); } return Error.none; }
fn markAcyclic(owner: Owner&,value: u32,ty: u32) -> Error {
    let acyclic,error = owner.generator.acyclicLayout(ty); if error != Error.none { return error; } if !acyclic { return Error.none; } assert(owner.generator.module.arena.present);
    let get = emit(owner,blot_backend_runtime_ir::OP_local_get,value); if get != Error.none { return get; } return emit(owner,blot_backend_runtime_ir::OP_call,owner.generator.module.arena.value.mark_acyclic);
}
fn cleanupTo(owner: Owner&,checkpoint: blot_runtime_runtime_cleanup::Mark) -> Error { owner.cleanups.emitTo(owner.generator.module,owner.function_id,checkpoint) }
fn allocate(owner: Owner&,bytes: u32,roles: AllocationRoles) -> u32,Error { allocateStorage(owner,bytes,false,roles) }
fn allocatePrivate(owner: Owner&,bytes: u32,roles: AllocationRoles) -> u32,Error {
    let local,error = allocate(owner,bytes,roles); if error != Error.none { return 0,error; } let registered = owner.cleanups.append(blot_runtime_runtime_cleanup::Action.release { local }); if registered != Error.none { return 0,registered; } return local,Error.none;
}
fn annotateAllocation(owner: Owner&,roles: AllocationRoles) -> Error {
    var buffer: blot_backend_runtime_ir::Instruction[blot_backend_runtime_ir::max_annotations]; let run = blot_backend_runtime_ir::annotations(roles.words,roles.rest,buffer);
    for annotation in run { let emitted = emit(owner,annotation.op,annotation.operand); if emitted != Error.none { return emitted; } } owner.generator.evaluator.counters.allocation_role_runs++; return Error.none;
}
fn wideShape(owner: Owner&,bytes: u32,roles: AllocationRoles,force: bool) -> blot_support::Option<u32>,Error {
    if bytes == 0 || bytes % 4 != 0 { return blot_support::none<u32>(),Error.none; } if !force && bytes <= 128 { return blot_support::none<u32>(),Error.none; }
    let count = bytes / 4; var tail = blot_backend_runtime_ir::ROLE_unknown; var wide = false;
    for word in 0..count {
        var role = roles.rest; if word < roles.words.len { role = roles.words[word]; } if role != blot_backend_runtime_ir::ROLE_scalar && role != blot_backend_runtime_ir::ROLE_reference { return blot_support::none<u32>(),Error.none; }
        if word == 31 { tail = role; } if word > 31 && role != tail { wide = true; }
    }
    if !wide && !force && count <= 16 * blot_backend_runtime_ir::words_per_chunk { return blot_support::none<u32>(),Error.none; }
    var bitmap: u32[>..<] = []; for index in 0..1 + (count + 31) / 32 { bitmap.push(0); } bitmap[0] = count;
    for word in 0..count { var role = roles.rest; if word < roles.words.len { role = roles.words[word]; } if role == blot_backend_runtime_ir::ROLE_reference { bitmap[1 + word / 32] |= (1 as u32) << (word % 32) as u32; } }
    let address,error = owner.generator.module.dataWords(bitmap); if error != Error.none { return blot_support::none<u32>(),error; } assert(owner.generator.module.arena.present); let arena = owner.generator.module.arena.value;
    let flags = owner.generator.module.globals[arena.rc_enabled].bits | blot_runtime_shared_rc::shaped_mode; let configured = owner.generator.module.setGlobalBits(arena.rc_enabled,flags); if configured != Error.none { return blot_support::none<u32>(),configured; } return blot_support::some(address),Error.none;
}
fn allocateStorage(owner: Owner&,bytes: u32,scalar_payload: bool,roles: AllocationRoles) -> u32,Error {
    let arena,error = owner.generator.module.ensureArena(); if error != Error.none { return 0,error; } let local,local_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if local_error != Error.none { return 0,local_error; }
    var shape = blot_support::none<u32>(); if !scalar_payload { let selected,shape_error = wideShape(owner,bytes,roles,false); if shape_error != Error.none { return 0,shape_error; } shape = selected; }
    if shape.present {
        let size = emit(owner,blot_backend_runtime_ir::OP_i32_const,bytes); if size != Error.none { return 0,size; }
        let address = referenceConstant(owner,shape.value,blot_reuse_artifact_emitter::Role.static_address); if address != Error.none { return 0,address; }
        let allocated = emit(owner,blot_backend_runtime_ir::OP_call,arena.allocate_shaped); if allocated != Error.none { return 0,allocated; }
    } else {
        var allocation_roles = roles; if scalar_payload { allocation_roles = AllocationRoles { rest: blot_backend_runtime_ir::ROLE_scalar }; } let annotated = annotateAllocation(owner,allocation_roles); if annotated != Error.none { return 0,annotated; }
        let size = emit(owner,blot_backend_runtime_ir::OP_i32_const,bytes); if size != Error.none { return 0,size; } var function = arena.allocate; if scalar_payload { function = arena.allocate_scalar; }
        let allocated = emit(owner,blot_backend_runtime_ir::OP_call,function); if allocated != Error.none { return 0,allocated; }
    }
    let stored = emit(owner,blot_backend_runtime_ir::OP_local_set,local); if stored != Error.none { return 0,stored; } return local,Error.none;
}
fn scalar(owner: Owner&,id: u32) -> blot_backend_runtime_ir::Scalar,Error {
    let source .= owner.generator.unit(owner.unit_id); var shape: u32; var error: Error;
    if source.node(id).tag == blot_check_core::Tag.reference { shape,error = referenceLayout(owner,id); } else { shape,error = codeLayout(owner,source.typeOf(id),source.span(id)); }
    if error != Error.none { return blot_backend_runtime_ir::SC_unit,error; } let selected = owner.generator.representations.store.scalar(shape); if selected.present { return selected.value,Error.none; } return blot_backend_runtime_ir::SC_pointer,Error.none;
}
fn capture(owner: Owner&,id: u32,depth: i64) -> u32,Error {
    let source .= owner.generator.unit(owner.unit_id);
    if source.types.node(source.typeOf(id)).tag == blot_check_types::Tag.erased_proof { let emitted = expression(owner,id,depth + 1); if emitted != Error.none { return 0,emitted; } return 4294967295,Error.none; }
    let value_type,type_error = scalar(owner,id); if type_error != Error.none { return 0,type_error; }
    let local,error = temporary(owner,blot_backend_runtime_ir::machine(value_type)); if error != Error.none { return 0,error; } let emitted = expression(owner,id,depth + 1); if emitted != Error.none { return 0,emitted; }
    let stored = emit(owner,blot_backend_runtime_ir::OP_local_set,local); if stored != Error.none { return 0,stored; } return local,Error.none;
}
fn containsValue<T>(values: const T[:],value: T) -> bool { for candidate in values { if candidate == value { return true; } } return false; }
fn withFacts<T,B>(base: const T[:],facts: const T[:],out: B&) -> Error {
    let appended = out.append(base); if appended != Error.none { return appended; }
    for fact in facts { var replaced = false; for &mapping in out.items { if mapping.variable == fact.variable { mapping = fact; replaced = true; break; } } if !replaced { let error = out.push(fact); if error != Error.none { return error; } } } return Error.none;
}
struct Ambiguous { types: MappingBuffer,rows: RowBuffer }
fn deinit(ambiguous: Ambiguous&) { ambiguous.types.deinit(); ambiguous.rows.deinit(); }
struct TypeVariables { source: const blot_check_core::Module&,types: u32[32],type_count: i64 = 0,rows: u32[16],row_count: i64 = 0,remaining: i64 = 1024 }
recursive fn visit(variables: TypeVariables&,ty: u32,depth: i64) -> bool {
    if depth >= 64 || variables.remaining == 0 { return false; } variables.remaining--; let source .= variables.source; let n = source.types.node(ty);
    match n.tag {
        unit,boolean,unsigned32,floating32,never,erased_proof,type_constructor,bound=>{ return true; },
        variable=>{ if containsValue(variables.types[..variables.type_count],ty) { return true; } if variables.type_count == 32 { return false; } variables.types[variables.type_count] = ty; variables.type_count++; return true; },
        function,provider=>{ if n.tag == blot_check_types::Tag.function && !visit(variables,n.b,depth + 1) { return false; } return row(variables,n.c,depth + 1) && visit(variables,n.a,depth + 1); },
        array,list,cursor,resolver,usage,scoped,forall,existential=>{ return visit(variables,n.a,depth + 1); },state_provider=>{ return visit(variables,n.a,depth + 1) && visit(variables,n.b,depth + 1) && visit(variables,n.c,depth + 1); },
        product,nominal=>{ var children: const u32[:] = []; if n.tag == blot_check_types::Tag.nominal { children = source.types.nominalArguments(n); } else { children = source.types.list(blot_check_types::List { n.a,n.b }); } for child in children { if !visit(variables,child,depth + 1) { return false; } } return true; },
        record=>{ for index in 0..n.b { if !visit(variables,source.types.recordField(n,index).ty,depth + 1) { return false; } } return true; },_=>{ return false; },
    }
}
fn row(variables: TypeVariables&,id: u32,depth: i64) -> bool {
    let source .= variables.source; for label in source.types.rowLabels(id) { for argument in source.types.operationArguments(label) { if !visit(variables,argument,depth + 1) { return false; } } }
    match source.types.row(id).tail {
        variable value=>{ if containsValue(variables.rows[..variables.row_count],value.value) { return true; } if variables.row_count == 16 { return false; } variables.rows[variables.row_count] = value.value; variables.row_count++; return true; },_=>{ return true; },
    }
}
recursive fn hasErasedType(owner: const Owner&,ty: u32,depth: i64) -> bool {
    if depth >= 128 { return true; } let layouts .= owner.generator.representations.store; let node = layouts.node(ty);
    match node.tag {
        erased,invalid=>{ return true; },function=>{ return hasErasedType(owner,node.a,depth + 1) || hasErasedType(owner,node.b,depth + 1); },array,list,cursor,provider,resolver=>{ return hasErasedType(owner,node.a,depth + 1); },state_provider=>{ return hasErasedType(owner,node.a,depth + 1) || hasErasedType(owner,node.b,depth + 1) || hasErasedType(owner,node.c,depth + 1); },
        product,nominal=>{ for child in layouts.children(ty) { if hasErasedType(owner,child,depth + 1) { return true; } } return false; },record=>{ let fields = layouts.children(ty); var index: i64 = 1; while index < fields.len { if hasErasedType(owner,fields[index],depth + 1) { return true; } index += 2; } return false; },_=>{ return false; },
    }
}
fn closeAmbiguousUse(owner: Owner&,ty: u32,mappings: const Mapping[:],rows: const RowMapping[:],span: blot_check_core::Span,ambiguous: Ambiguous&) -> bool,Error {
    let generator .= owner.generator; let source .= generator.unit(owner.unit_id); var variables = TypeVariables { source: source }; if !visit(variables,ty,0) { return false,Error.none; }
    let known_types = ambiguous.types.items.len; let known_rows = ambiguous.rows.items.len; var closed = false; 
    recursive fn cleanup_continuation_81() -> bool,Error {

    for variable in variables.types[..variables.type_count] {
        var present = false; for mapping in mappings { if mapping.variable == variable { present = true; break; } } if present { continue; }
        let quantified,error = generator.quantifiedVariable(owner.unit_id,variable,false); if error != Error.none { return false,error; } if quantified { return false,Error.none; } let appended = ambiguous.types.push(Mapping { variable: variable,layout: blot_backend_layout::word }); if appended != Error.none { return false,appended; }
    }
    if ambiguous.types.items.len == known_types { return false,Error.none; }
    for variable in variables.rows[..variables.row_count] {
        var present = false; for mapping in rows { if mapping.variable == variable { present = true; break; } } if present { continue; }
        let quantified,error = generator.quantifiedVariable(owner.unit_id,variable,true); if error != Error.none { return false,error; } if quantified { continue; } let appended = ambiguous.rows.push(RowMapping { variable,0 }); if appended != Error.none { return false,appended; }
    }
    var closed_types = MappingBuffer {}; 
    recursive fn cleanup_continuation_80() -> bool,Error {
 var closed_rows = RowBuffer {}; 
    recursive fn cleanup_continuation_79() -> bool,Error {
 let types = withFacts(mappings,ambiguous.types.items[known_types..],closed_types); if types != Error.none { return false,types; } let row_mappings = withFacts(rows,ambiguous.rows.items[known_rows..],closed_rows); if row_mappings != Error.none { return false,row_mappings; }
    let layout,error = generator.codeLayoutWithRows(owner.unit_id,ty,closed_types.items,closed_rows.items,span); if error != Error.none { return false,error; } closed = !hasErasedType(owner,layout,0); return closed,Error.none;

    }
    let cleanup_result_79_0,cleanup_result_79_1 = cleanup_continuation_79();
     closed_rows.deinit(); 
    return cleanup_result_79_0,cleanup_result_79_1;

    }
    let cleanup_result_80_0,cleanup_result_80_1 = cleanup_continuation_80();
     closed_types.deinit(); 
    return cleanup_result_80_0,cleanup_result_80_1;

    }
    let cleanup_result_81_0,cleanup_result_81_1 = cleanup_continuation_81();
     if !closed { ambiguous.types.resize(known_types); ambiguous.rows.resize(known_rows); } 
    return cleanup_result_81_0,cleanup_result_81_1;
}
struct ProducerScan { source: const blot_check_core::Module&,reads: InstanceReads&,edits: u32[32],edit_count: i64 = 0,remaining: i64 = 256 }
fn usageNominal(source: const blot_check_core::Module&,ty: u32) -> bool { let contains,error = blot_check_usage_check::containsNominal(source.types,source.nominals,ty); return error != Error.none || contains; }
recursive fn visit(scan: ProducerScan&,id: u32,depth: i64) -> bool {
    if id == 0 || depth >= 64 || scan.remaining == 0 { return false; } scan.remaining--; let source .= scan.source; let n = source.node(id);
    if source.has_usage_contracts {
        if usageNominal(source,n.ty) { return false; } if n.tag == blot_check_core::Tag.closure { let closure = source.closure(id); for held in source.extra[closure.captures.start..closure.captures.start + closure.captures.len] { if usageNominal(source,source.binding(held).ty) { return false; } } }
    }
    if n.tag == blot_check_core::Tag.call || n.tag == blot_check_core::Tag.apply || n.tag == blot_check_core::Tag.array_op { if scan.edit_count == 32 { return false; } scan.edits[scan.edit_count] = id; scan.edit_count++; }
    match n.tag {
        constant,constructor_function,primitive_function,closure=>{ return true; },reference=>{ if scan.reads.len == 32 { return false; } scan.reads.nodes[scan.reads.len] = id; scan.reads.len++; return true; },
        scalar=>{ return visit(scan,n.a,depth + 1) && (n.b == 0 || visit(scan,n.b,depth + 1)); },logical,associated,apply,record_merge=>{ return visit(scan,n.a,depth + 1) && visit(scan,n.b,depth + 1); },if_value=>{ return visit(scan,n.a,depth + 1) && visit(scan,n.b,depth + 1) && visit(scan,n.c,depth + 1); },project=>{ return visit(scan,n.a,depth + 1); },construct=>{ return n.b == 0 || visit(scan,n.b,depth + 1); },
        call,product,record,array,array_op=>{ for child in source.children(id) { if !visit(scan,child,depth + 1) { return false; } } return true; },_=>{ return false; },
    }
}
fn mappingAt(mappings: const Mapping[:],variable: u32) -> u32 { for mapping in mappings { if mapping.variable == variable { return mapping.layout; } } return blot_backend_layout::erased; }
fn rowAt(rows: const RowMapping[:],variable: u32) -> u32 { for mapping in rows { if mapping.variable == variable { return mapping.row; } } return blot_backend_layout::unknown_row; }
fn decideInstances(owner: Owner&,statement: u32,previous: const Mapping[:],previous_rows: const RowMapping[:],uses: const u32[:],decisions: InstanceDecisions&) -> Error {
    let generator .= owner.generator; let source .= generator.unit(owner.unit_id); let n = source.node(statement); let binding = source.binding(n.a); let span = source.span(statement);
    if binding.scheme.obligations.len != 0 || binding.scheme.generative.len != 0 { return Error.none; }
    if !blot_eval_closed_local_value::dataShape(generator.units,owner.unit_id,binding.ty) { return Error.none; }
    if source.has_usage_contracts && usageNominal(source,binding.ty) { return Error.none; }
    assert(uses.len <= max_local_instances); var decision = InstanceDecision { statement,count: uses.len }; var scan = ProducerScan { source,reads: decision.reads }; if !scan.visit(n.b,0) { return Error.none; }
    for edit in scan.edits[..scan.edit_count] { let owns,error = generator.ownsArrayUpdate(owner.unit_id,edit); if error != Error.none { return error; } if owns { return Error.none; } }
    let fact_start = decisions.facts.items.len; let row_start = decisions.rows.items.len; var admitted = false;
    
    recursive fn cleanup_continuation_78() -> Error {

    var next = MappingBuffer {}; 
    recursive fn cleanup_continuation_77() -> Error {
 var next_rows = RowBuffer {}; 
    recursive fn cleanup_continuation_76() -> Error {

    var closed = MappingBuffer {}; 
    recursive fn cleanup_continuation_75() -> Error {
 var closed_rows = RowBuffer {}; 
    recursive fn cleanup_continuation_74() -> Error {

    let variables = source.types.list(binding.scheme.variables); let row_variables = source.types.list(binding.scheme.row_variables);
    for selected,index in uses {
        next.clear(); next_rows.clear(); let a = next.append(previous); if a != Error.none { return a; } let b = next_rows.append(previous_rows); if b != Error.none { return b; }
        let mapped = generator.mapTypeDepth(owner.unit_id,next,next_rows,binding.ty,selected,span,0); if mapped != Error.none { return mapped; }
        let producer = generator.mapTypeDepth(owner.unit_id,next,next_rows,source.typeOf(n.b),selected,span,0); if producer != Error.none { return producer; }
        let first_fact = decisions.facts.items.len;
        for mapping in next.items { if mapping.layout == mappingAt(previous,mapping.variable) { continue; } if !containsValue(variables,mapping.variable) { return Error.none; } let appended = decisions.facts.push(mapping); if appended != Error.none { return appended; } }
        let first_row = decisions.rows.items.len;
        for mapping in next_rows.items { let old = rowAt(previous_rows,mapping.variable); if mapping.row == old { continue; } if old != blot_backend_layout::unknown_row && !containsValue(row_variables,mapping.variable) { return Error.none; } let appended = decisions.rows.push(mapping); if appended != Error.none { return appended; } }
        decision.facts[index] = FactRange { first_fact,decisions.facts.items.len - first_fact }; decision.rows[index] = FactRange { first_row,decisions.rows.items.len - first_row }; decision.layouts[index] = selected;
        closed.clear(); closed_rows.clear(); let facts = withFacts(previous,decisions.factsAt(decision,index),closed); if facts != Error.none { return facts; } let rows = withFacts(previous_rows,decisions.rowsAt(decision,index),closed_rows); if rows != Error.none { return rows; }
        let representation,error = generator.codeLayoutWithRows(owner.unit_id,binding.ty,closed.items,closed_rows.items,span); if error != Error.none { return error; } if representation != selected { return Error.none; }
    }
    let appended = decisions.decisions.push(decision); if appended != Error.none { return appended; } admitted = true; return Error.none;

    }
    let cleanup_result_74_0 = cleanup_continuation_74();
     closed_rows.deinit(); 
    return cleanup_result_74_0;

    }
    let cleanup_result_75_0 = cleanup_continuation_75();
     closed.deinit(); 
    return cleanup_result_75_0;

    }
    let cleanup_result_76_0 = cleanup_continuation_76();
     next_rows.deinit(); 
    return cleanup_result_76_0;

    }
    let cleanup_result_77_0 = cleanup_continuation_77();
     next.deinit(); 
    return cleanup_result_77_0;

    }
    let cleanup_result_78_0 = cleanup_continuation_78();
     if !admitted { decisions.facts.resize(fact_start); decisions.rows.resize(row_start); } 
    return cleanup_result_78_0;
}
fn localStorageMappings(owner: Owner&,root: u32,mappings: MappingBuffer&,rows: RowBuffer&,instances: InstanceDecisions&) -> Error {
    let generator .= owner.generator; let source .= generator.unit(owner.unit_id); var unit_uses: const blot_backend_unit_index::Uses? = null; let statements = source.children(root);
    var dead_aliases: u32[16]; var dead_count: i64 = 0; var scratch = MappingBuffer {}; 
    recursive fn cleanup_continuation_73() -> Error {
 var scratch_rows = RowBuffer {}; 
    recursive fn cleanup_continuation_72() -> Error {

    var ambiguous = Ambiguous {}; 
    recursive fn cleanup_continuation_71() -> Error {
 var with_ambiguous = MappingBuffer {}; 
    recursive fn cleanup_continuation_70() -> Error {
 var with_ambiguous_rows = RowBuffer {}; 
    recursive fn cleanup_continuation_69() -> Error {
 var scratch_plain = MappingBuffer {}; 
    recursive fn cleanup_continuation_68() -> Error {

    var position = statements.len;
    while position > 0 {
        position--; let statement = statements[position]; let n = source.node(statement); if n.tag != blot_check_core::Tag.bind || n.a == 0 { continue; } let producer = source.node(n.b);
        let built = producer.tag == blot_check_core::Tag.construct || producer.tag == blot_check_core::Tag.product || producer.tag == blot_check_core::Tag.record || producer.tag == blot_check_core::Tag.array;
        if !built && producer.tag != blot_check_core::Tag.call && producer.tag != blot_check_core::Tag.apply && producer.tag != blot_check_core::Tag.project && producer.tag != blot_check_core::Tag.reference { continue; }
        let binding = source.binding(n.a); if binding.kind != blot_check_core::BindingKind.local || binding.scheme.variables.len == 0 { continue; }
        let produced,produced_error = codeLayout(owner,binding.ty,source.span(statement)); if produced_error != Error.none { return produced_error; } if !hasErasedType(owner,produced,0) { continue; }
        if producer.tag == blot_check_core::Tag.project {
            if source.projectionVariants(producer.b).len != 0 { continue; } let projection = source.projection(producer.b); let receiver,error = codeLayout(owner,projection.source_type,source.span(n.b)); if error != Error.none { return error; }
            let target,target_error = memberTarget(owner,n.b,projection.field,receiver); if target_error != Error.none { return target_error; } if !target.present { continue; }
        }
        if producer.tag == blot_check_core::Tag.reference { let aliased = source.reference(n.b); if aliased.unit != 0 && aliased.unit != owner.unit_id { continue; } if source.binding(aliased.binding).kind != blot_check_core::BindingKind.local { continue; } }
        var plain = owner.mappings; if mappings.items.len != 0 { plain = mappings.items; }
        with_ambiguous.clear(); let merged = withFacts(plain,ambiguous.types.items,with_ambiguous); if merged != Error.none { return merged; } let previous = with_ambiguous.items;
        with_ambiguous_rows.clear(); let merged_rows = withFacts(owner.row_mappings,ambiguous.rows.items,with_ambiguous_rows); if merged_rows != Error.none { return merged_rows; } let previous_rows = with_ambiguous_rows.items;
        var uses: u32[4]; var use_count: i64 = 0; var open = false; var widened = false; var restart = false;
        if unit_uses == null { let index,error = generator.unitUses(owner.unit_id,blot_backend_unit_index::Need {}); if error != Error.none { return error; } unit_uses .= index; } assert(unit_uses != null); let index .= unit_uses;
        for use in index.references.get(n.a) {
            let reference = source.reference(use); if reference.unit != 0 && reference.unit != owner.unit_id { continue; } if containsValue(dead_aliases[..dead_count],use) { continue; }
            let reader .= instances.reader(use); var contexts: i64 = 1; if reader != null { contexts = reader.count; }
            for context in 0..contexts {
                var context_mappings: const Mapping[:] = previous; var context_rows: const RowMapping[:] = previous_rows;
                if reader != null { scratch.clear(); let facts = withFacts(previous,instances.factsAt(reader,context),scratch); if facts != Error.none { return facts; } context_mappings = scratch.items; scratch_rows.clear(); let row_facts = withFacts(previous_rows,instances.rowsAt(reader,context),scratch_rows); if row_facts != Error.none { return row_facts; } context_rows = scratch_rows.items; }
                let use_type = source.typeOf(use); let span = source.span(use); let instance,error = generator.codeLayoutWithRows(owner.unit_id,use_type,context_mappings,context_rows,span); if error != Error.none { return error; }
                if hasErasedType(owner,instance,0) { let closed,closed_error = closeAmbiguousUse(owner,use_type,context_mappings,context_rows,span,ambiguous); if closed_error != Error.none { return closed_error; } if closed { restart = true; } else { open = true; } break; }
                if ambiguous.types.items.len != 0 && !widened { scratch_plain.clear(); var facts: const Mapping[:] = []; if reader != null { facts = instances.factsAt(reader,context); } let merged_plain = withFacts(plain,facts,scratch_plain); if merged_plain != Error.none { return merged_plain; } let plain_layout,plain_error = generator.codeLayoutWithRows(owner.unit_id,use_type,scratch_plain.items,context_rows,span); if plain_error != Error.none { return plain_error; } widened = hasErasedType(owner,plain_layout,0); }
                if containsValue(uses[..use_count],instance) { continue; } if use_count == 4 { open = true; break; } uses[use_count] = instance; use_count++;
            }
            if restart || open { break; }
        }
        if restart { position++; continue; } if open { continue; }
        if use_count == 0 && producer.tag == blot_check_core::Tag.reference { if dead_count < 16 { dead_aliases[dead_count] = n.b; dead_count++; } continue; }
        let flags = index.flagsOf(n.a); if flags.captured || flags.merge_branch || flags.carried { continue; }
        let promotable = producer.tag == blot_check_core::Tag.call || producer.tag == blot_check_core::Tag.apply || producer.tag == blot_check_core::Tag.project || producer.tag == blot_check_core::Tag.construct || producer.tag == blot_check_core::Tag.product || producer.tag == blot_check_core::Tag.record;
        if widened && generator.speculative_locals && promotable { generator.speculated = true; continue; }
        if use_count > 1 || (built && use_count == 1) { let decided = decideInstances(owner,statement,previous,previous_rows,uses[..use_count],instances); if decided != Error.none { return decided; } continue; } if built { continue; }
        var next = MappingBuffer {}; defer { next.deinit(); } let copied = next.append(previous); if copied != Error.none { return copied; }
        if use_count == 1 { let a = generator.mapTypeDepth(owner.unit_id,next,null,binding.ty,uses[0],source.span(statement),0); if a != Error.none { return a; } let b = generator.mapTypeDepth(owner.unit_id,next,null,source.typeOf(n.b),uses[0],source.span(statement),0); if b != Error.none { return b; } }
        else {
            for variable in source.types.list(binding.scheme.variables) { var found = false; for mapping in next.items { if mapping.variable == variable { found = true; break; } } if !found { let added = next.push(Mapping { variable,layout: blot_backend_layout::word }); if added != Error.none { return added; } } }
            let closed,error = generator.codeLayoutWithRows(owner.unit_id,binding.ty,next.items,previous_rows,source.span(statement)); if error != Error.none { return error; } if hasErasedType(owner,closed,0) { continue; } let mapped = generator.mapTypeDepth(owner.unit_id,next,null,source.typeOf(n.b),closed,source.span(statement),0); if mapped != Error.none { return mapped; }
        }
        var private = true; for mapping in next.items { if mapping.layout != mappingAt(previous,mapping.variable) && !containsValue(source.types.list(binding.scheme.variables),mapping.variable) { private = false; } } if !private { continue; }
        mappings.deinit(); mappings = next; next = MappingBuffer {};
    }
    if ambiguous.types.items.len == 0 { return Error.none; } var merged = MappingBuffer {}; var transferred = false; 
    recursive fn cleanup_continuation_67() -> Error {
 var base = owner.mappings; if mappings.items.len != 0 { base = mappings.items; }
    let facts = withFacts(base,ambiguous.types.items,merged); if facts != Error.none { return facts; } mappings.deinit(); mappings = merged; transferred = true;
    if ambiguous.rows.items.len == 0 { return Error.none; } rows.clear(); return withFacts(owner.row_mappings,ambiguous.rows.items,rows);

    }
    let cleanup_result_67_0 = cleanup_continuation_67();
     if !transferred { merged.deinit(); } 
    return cleanup_result_67_0;

    }
    let cleanup_result_68_0 = cleanup_continuation_68();
     scratch_plain.deinit(); 
    return cleanup_result_68_0;

    }
    let cleanup_result_69_0 = cleanup_continuation_69();
     with_ambiguous_rows.deinit(); 
    return cleanup_result_69_0;

    }
    let cleanup_result_70_0 = cleanup_continuation_70();
     with_ambiguous.deinit(); 
    return cleanup_result_70_0;

    }
    let cleanup_result_71_0 = cleanup_continuation_71();
     ambiguous.deinit(); 
    return cleanup_result_71_0;

    }
    let cleanup_result_72_0 = cleanup_continuation_72();
     scratch_rows.deinit(); 
    return cleanup_result_72_0;

    }
    let cleanup_result_73_0 = cleanup_continuation_73();
     scratch.deinit(); 
    return cleanup_result_73_0;
}
recursive fn prepareBody(owner: Owner&,root: u32,depth: i64,template: bool) -> u32,Error {
    let generator .= owner.generator; let stage = generator.evaluator.enterInferenceStage(blot_work_counters::InferenceStage.preparation); 
    recursive fn cleanup_continuation_66() -> u32,Error {

    if owner.preparation_depth >= 256 { return 0,generator.fail(owner.unit_id,root,blot_backend_core_backend::Code.complexity); }
    var storage = MappingBuffer {}; 
    recursive fn cleanup_continuation_65() -> u32,Error {
 var storage_rows = RowBuffer {}; 
    recursive fn cleanup_continuation_64() -> u32,Error {
 var instances = InstanceDecisions {}; 
    recursive fn cleanup_continuation_63() -> u32,Error {

    let selected = localStorageMappings(owner,root,storage,storage_rows,instances); if selected != Error.none { return 0,selected; }
    let source .= generator.unit(owner.unit_id);
    if blot_backend_bottom_result::proves(generator.units,owner.unit_id,root) {
        let result,result_error = codeLayout(owner,source.typeOf(root),source.span(root)); if result_error != Error.none { return 0,result_error; }
        if result == blot_backend_layout::erased { if storage.items.len == 0 { let copied = storage.append(owner.mappings); if copied != Error.none { return 0,copied; } } var rows = RowBuffer {}; defer { rows.deinit(); } let mapped = generator.mapTypeDepth(owner.unit_id,storage,rows,source.typeOf(root),5,source.span(root),0); if mapped != Error.none { return 0,mapped; } }
    }
    var mappings = owner.mappings; if storage.items.len != 0 { mappings = storage.items; } var rows = owner.row_mappings; if storage_rows.items.len != 0 { rows = storage_rows.items; }
    var selected_instances: const InstanceDecisions? = null; if instances.decisions.items.len != 0 { selected_instances .= instances; }
    return prepareMapped(owner,root,depth,template,mappings,rows,selected_instances);

    }
    let cleanup_result_63_0,cleanup_result_63_1 = cleanup_continuation_63();
     instances.deinit(); 
    return cleanup_result_63_0,cleanup_result_63_1;

    }
    let cleanup_result_64_0,cleanup_result_64_1 = cleanup_continuation_64();
     storage_rows.deinit(); 
    return cleanup_result_64_0,cleanup_result_64_1;

    }
    let cleanup_result_65_0,cleanup_result_65_1 = cleanup_continuation_65();
     storage.deinit(); 
    return cleanup_result_65_0,cleanup_result_65_1;

    }
    let cleanup_result_66_0,cleanup_result_66_1 = cleanup_continuation_66();
     stage.deinit(); 
    return cleanup_result_66_0,cleanup_result_66_1;
}
recursive fn prepareMapped(owner: Owner&,root: u32,depth: i64,template: bool,mappings: const Mapping[:],rows: const RowMapping[:],instances: const InstanceDecisions?) -> u32,Error {
    let generator .= owner.generator; let stage = generator.evaluator.enterInferenceStage(blot_work_counters::InferenceStage.preparation); 
    recursive fn cleanup_continuation_62() -> u32,Error {

    if owner.preparation_depth >= 256 { return 0,generator.fail(owner.unit_id,root,blot_backend_core_backend::Code.complexity); }
    let bodies .= generator.planning.bodies; let body,error = bodies.create(owner.unit_id,root,mappings,rows); if error != Error.none { return 0,error; } var published = false; 
    recursive fn cleanup_continuation_61() -> u32,Error {

    let evidence,evidence_error = generator.rowMappingEvidence(rows); if evidence_error != Error.none { return 0,evidence_error; } bodies.headers[body - 1].rows_evidence = evidence;
    for mapping in bodies.header(body).mappings { let owns,owns_error = generator.representations.store.hasOwners(mapping.layout); if owns_error != Error.none { return 0,generator.fail(owner.unit_id,root,blot_backend_core_backend::Code.complexity); } if owns { bodies.headers[body - 1].has_owners = true; break; } }
    let cleanups,cleanup_error = blot_runtime_runtime_cleanup::initPooled(); if cleanup_error != Error.none { return 0,cleanup_error; }
    let header = bodies.header(body); var preparer = Owner { generator,unit_id: owner.unit_id,function_id: owner.function_id,mappings: header.mappings,row_mappings: header.rows,factory_template: owner.factory_template,preparation_depth: owner.preparation_depth + 1,preparing: true,staged: owner.staged,cleanups };
    
    recursive fn cleanup_continuation_60() -> u32,Error {
 preparer.dictionary_local = owner.dictionary_local; preparer.dictionary_owner = owner.dictionary_owner; preparer.locals = owner.locals.clone(); preparer.templates = owner.templates.clone(); preparer.static_values = owner.static_values.clone(); if instances != null { preparer.local_instances = blot_support::some(instances); }
    let prepared = prepareNode(preparer,body,root,depth,template); if prepared != Error.none { return 0,prepared; }
    if preparer.has_collection_steps { let cursors = prepareCursorFamilies(preparer,body); if cursors != Error.none { return 0,cursors; } }
    let linear = prepareLinearCursors(preparer,body); if linear != Error.none { return 0,linear; } let numeric = prepareNumeric(preparer,body); if numeric != Error.none { return 0,numeric; }
    let uses,uses_error = generator.unitUses(owner.unit_id,blot_backend_unit_index::Need {}); if uses_error != Error.none { return 0,uses_error; }
    let sinks = blot_backend_safe_local_sinking::plan(generator.unit(owner.unit_id),uses,root,bodies,body); if sinks != Error.none { return 0,sinks; }
    generator.evaluator.counters.safe_local_sinks += bodies.sinkCount(body); generator.evaluator.counters.resolved_bodies++; generator.evaluator.counters.resolved_plan_entries += bodies.entryCount(body); published = true; return body,Error.none;

    }
    let cleanup_result_60_0,cleanup_result_60_1 = cleanup_continuation_60();
     preparer.deinit(); 
    return cleanup_result_60_0,cleanup_result_60_1;

    }
    let cleanup_result_61_0,cleanup_result_61_1 = cleanup_continuation_61();
     if !published { bodies.release(body); } 
    return cleanup_result_61_0,cleanup_result_61_1;

    }
    let cleanup_result_62_0,cleanup_result_62_1 = cleanup_continuation_62();
     stage.deinit(); 
    return cleanup_result_62_0,cleanup_result_62_1;
}
fn prepareCursorFamilies(owner: Owner&,body: u32) -> Error {
    let generator .= owner.generator; let source .= generator.unit(owner.unit_id); let bodies .= generator.planning.bodies; let uses,error = generator.unitUses(owner.unit_id,blot_backend_unit_index::Need { flow: true }); if error != Error.none { return error; }
    var steps: blot_backend_private_cursor::Step[64]; var count: i64 = 0; var cursor = bodies.header(body).first;
    while cursor != 0 {
        let slot = bodies.slots[cursor - 1]; let id = slot.node; cursor = slot.next; let selected = bodies.get(body,id);
        match selected { collection_step step=>{
            if source.node(step.receiver).tag != blot_check_core::Tag.reference { continue; } let receiver = source.reference(step.receiver); if receiver.unit != 0 && receiver.unit != owner.unit_id { continue; } if count == 64 { return Error.none; }
            let pattern = source.node(step.pattern); let fields = source.patternChildren(source.pattern(pattern.a).b); let rest = source.pattern(fields[1]); var tail: u32 = 0; if rest.tag == blot_check_core::PatternTag.bind { tail = rest.a; }
            steps[count] = blot_backend_private_cursor::Step { node: source.node(id).b,pattern: step.pattern,input: receiver.binding,rest: tail }; count++;
        },_=>{}, }
    }
    var handled: bool[64] = [false;64];
    for step,index in steps[..count] {
        if handled[index] { continue; } let family = blot_backend_private_cursor::checkSteps(source,uses,bodies.header(body).root,step.input,steps[..count]); if !family.present { continue; } var admissible = true;
        cursor = bodies.header(body).first;
        while cursor != 0 { let slot = bodies.slots[cursor - 1]; cursor = slot.next; if source.node(slot.node).tag != blot_check_core::Tag.loop_ { continue; } let planned = bodies.get(body,slot.node); match planned { loop_ loop=>{ if loop.value.collection.present { for carry in source.loopCarries(slot.node) { if containsValue(family.value.bindings[..family.value.len],carry.iteration) { admissible = false; break; } } } },_=>{}, } if !admissible { break; } }
        if !admissible { continue; }
        for binding in family.value.bindings[..family.value.len] {
            let concrete,concrete_error = codeLayout(owner,source.binding(binding).ty,source.span(bodies.header(body).root)); if concrete_error != Error.none { return concrete_error; } let node = generator.representations.store.node(concrete);
            if node.tag != blot_backend_layout::Tag.cursor { admissible = false; break; } let words,word_error = generator.collectionRowWords(node.a); if word_error != Error.none { return word_error; } let input = generator.representations.store.node(node.a);
            if words != 0 || (input.tag != blot_backend_layout::Tag.array && input.tag != blot_backend_layout::Tag.list) { admissible = false; break; }
            let evidence,evidence_error = generator.representations.toEvidence(generator.evaluator.evidenceStore(),concrete); if evidence_error != Error.none { if evidence_error == Error.out_of_memory { return evidence_error; } admissible = false; break; }
            if source.binding(binding).kind != blot_check_core::BindingKind.local { admissible = false; break; }
        }
        if !admissible { continue; } for other,other_index in steps[..count] { if containsValue(family.value.bindings[..family.value.len],other.input) { handled[other_index] = true; } }
        var definitions = WordBuffer {}; defer { definitions.deinit(); } for binding in family.value.bindings[..family.value.len] { let appended = definitions.append(uses.definitions.get(binding)); if appended != Error.none { return appended; } }
        sortWords(definitions.items);
        for id,position in definitions.items { if position != 0 && definitions.items[position - 1] == id { continue; } if bodies.contains(body,id) { continue; } let input,input_error = privateCursorConstructor(owner,body,source.node(id).b); if input_error != Error.none { return input_error; } var selected: u32 = 0; if input.present { selected = input.value; } let added = bodies.put(body,id,Plan.private_cursor { selected,blot_support::none<blot_backend_linear_cursor::Plan>() }); if added != Error.none { return added; } }
    } return Error.none;
}
fn sortWords(values: u32[:]) { var width: i64 = 1; while width < values.len { var start: i64 = 0; while start < values.len { let middle = min(start + width,values.len); let end = min(middle + width,values.len); var left = start; var right = middle; while left < right && right < end { if values[left] <= values[right] { left++; } else { let selected = values[right]; var index = right; while index > left { values[index] = values[index - 1]; index--; } values[left] = selected; left++; right++; } } start = end; } if width > values.len / 2 { break; } width *= 2; } }
fn prepareLinearCursors(owner: Owner&,body: u32) -> Error {
    let generator .= owner.generator; let source .= generator.unit(owner.unit_id); let bodies .= generator.planning.bodies; var cursor = bodies.header(body).first;
    while cursor != 0 { let slot = bodies.slots[cursor - 1]; cursor = slot.next; let selected = bodies.get(body,slot.node);
        match selected { private_cursor private=>{
            if private.input == 0 { continue; } let concrete,error = codeLayout(owner,source.binding(source.node(slot.node).a).ty,source.span(slot.node)); if error != Error.none { return error; } let node = generator.representations.store.node(concrete);
            if node.tag != blot_backend_layout::Tag.cursor || generator.representations.store.node(node.a).tag != blot_backend_layout::Tag.list { continue; } let words,word_error = generator.collectionRowWords(node.a); if word_error != Error.none { return word_error; } if words == 0 { continue; }
            let uses,uses_error = generator.unitUses(owner.unit_id,blot_backend_unit_index::Need { parents: true,flow: true }); if uses_error != Error.none { return uses_error; } let linear = blot_backend_linear_cursor::check(source,uses,bodies.header(body).root,slot.node); if !linear.present { continue; }
            if !bodies.contains(body,linear.value.advance) || !bodies.contains(body,linear.value.loop) { continue; } var advance_ok = false; match bodies.get(body,linear.value.advance) { private_cursor p=>{ advance_ok = true; },_=>{}, } if !advance_ok { continue; }
            var loop_ok = false; match bodies.get(body,linear.value.loop) { loop_ p=>{ loop_ok = !p.value.collection.present; },_=>{}, } if !loop_ok { continue; }
            let payload .= bodies.getRef(body,slot.node); match payload { private_cursor &p=>{ p.linear = linear; },_=>{ assert(false); }, }
        },_=>{}, }
    } return Error.none;
}
fn prepareNumeric(owner: Owner&,body: u32) -> Error {
    let generator .= owner.generator; let bodies .= generator.planning.bodies; let header = bodies.header(body); if !header.has_associated || !header.has_numeric_checks { return Error.none; }
    let source .= generator.unit(owner.unit_id); var selected: blot_check_numeric_proof_core::Selected[256]; var count: i64 = 0; var cursor = header.first;
    while cursor != 0 { let slot = bodies.slots[cursor - 1]; cursor = slot.next; if source.node(slot.node).tag != blot_check_core::Tag.associated { continue; } match bodies.get(body,slot.node) { dispatch d=>{ match d.value { selected invocation=>{ let call = invocation.call; if call.consumed == 0 || call.consumed > 2 || call.extra.len != 2 - call.consumed { continue; } if count == 256 { return Error.none; } selected[count] = blot_check_numeric_proof_core::Selected { slot.node,invocation.key.target }; count++; },_=>{}, } },_=>{}, } }
    if count == 0 { return Error.none; } var original: const blot_check_core::Body? = null; for &candidate in source.bodies[1..] { if candidate.root == header.root && candidate.is_function { original .= candidate; break; } } if original == null { return Error.none; }
    let plan,error = blot_check_numeric_proof_core::analyzePrepared(source,generator.units,original,selected[..count],blot_check_numeric_proof_core::Options {}); if error != Error.none { return error; } var retained = false; 
    recursive fn cleanup_continuation_59() -> Error {

    var improves = false; for check,id in plan.checks { if check.seen && check.admitted { let known,known_error = generator.numericCheck(owner.unit_id,id as u32); if known_error != Error.none { return known_error; } if !known { improves = true; break; } } }
    if !improves { return Error.none; } bodies.headers[body - 1].numeric = blot_support::some(plan); retained = true; if generator.artifacts != null { generator.artifacts.requireFreshCode(); } return Error.none;

    }
    let cleanup_result_59_0 = cleanup_continuation_59();
     if !retained { plan.deinit(); } 
    return cleanup_result_59_0;
}
fn numericCheck(owner: Owner&,id: u32) -> bool,Error { if owner.body.present { let header = owner.generator.planning.bodies.header(owner.body.value); if header.numeric.present && header.numeric.value.admits(id) { return true,Error.none; } } return owner.generator.numericCheck(owner.unit_id,id); }
recursive fn bodyExpression(owner: Owner&,root: u32,depth: i64,template: bool) -> Error { let body,error = prepareBody(owner,root,depth,template); if error != Error.none { return error; } 
    recursive fn cleanup_continuation_58() -> Error {
 return preparedExpression(owner,body,root,depth,template); 
    }
    let cleanup_result_58_0 = cleanup_continuation_58();
     owner.generator.planning.bodies.release(body); 
    return cleanup_result_58_0;
}
recursive fn preparedExpression(owner: Owner&,body: u32,root: u32,depth: i64,template: bool) -> Error {
    let stage = owner.generator.evaluator.enterInferenceStage(blot_work_counters::InferenceStage.lowering); 
    recursive fn cleanup_continuation_57() -> Error {
 let old_context = owner.semantic_context; owner.semantic_context = blot_support::none<SemanticContext>(); 
    recursive fn cleanup_continuation_56() -> Error {

    let previous = owner.body; owner.body = blot_support::some(body); 
    recursive fn cleanup_continuation_55() -> Error {
 let header = owner.generator.planning.bodies.header(body); let old_mappings = owner.mappings; let old_rows = owner.row_mappings;
    var changed = old_mappings.len != header.mappings.len; if !changed { for old,index in old_mappings { let current = header.mappings[index]; if old.variable != current.variable || old.layout != current.layout { changed = true; break; } } }
    var rows_changed = old_rows.len != header.rows.len; if !rows_changed { for old,index in old_rows { let current = header.rows[index]; if old.variable != current.variable || old.row != current.row { rows_changed = true; break; } } }
    if rows_changed { owner.row_mappings = header.rows; } changed = changed || rows_changed; owner.mappings = header.mappings; if changed { owner.layout_cache = [LayoutEntry {};32]; }
    
    recursive fn cleanup_continuation_54() -> Error {

    if template { return templateExpression(owner,root,depth); } return expression(owner,root,depth);

    }
    let cleanup_result_54_0 = cleanup_continuation_54();
     owner.mappings = old_mappings; owner.row_mappings = old_rows; if changed { owner.layout_cache = [LayoutEntry {};32]; } 
    return cleanup_result_54_0;

    }
    let cleanup_result_55_0 = cleanup_continuation_55();
     owner.body = previous; 
    return cleanup_result_55_0;

    }
    let cleanup_result_56_0 = cleanup_continuation_56();
     owner.semantic_context = old_context; 
    return cleanup_result_56_0;

    }
    let cleanup_result_57_0 = cleanup_continuation_57();
     stage.deinit(); 
    return cleanup_result_57_0;
}
fn stagingConstant(owner: Owner&,id: u32) -> u32,Error {
    let generator .= owner.generator; var mappings = blot_backend_substitution_buffers::EvidenceMappings {}; 
    recursive fn cleanup_continuation_53() -> u32,Error {
 var rows = blot_backend_substitution_buffers::EvidenceRows {}; 
    recursive fn cleanup_continuation_52() -> u32,Error {

    for mapping in owner.mappings { if mapping.instance.decl != 0 { continue; } let actual,error = generator.representations.toEvidence(generator.evaluator.evidenceStore(),mapping.layout); if error != Error.none { if error == Error.out_of_memory { return 0,error; } continue; } let appended = mappings.push(blot_eval_type_evidence::Mapping { mapping.variable,actual }); if appended != Error.none { return 0,appended; } }
    for mapping in owner.row_mappings { if mapping.row == blot_backend_layout::unknown_row { continue; } let actual,error = generator.representations.rowToEvidence(generator.evaluator.evidenceStore(),mapping.row); if error != Error.none { if error == Error.out_of_memory { return 0,error; } return 0,generator.fail(owner.unit_id,id,blot_backend_core_backend::Code.stage_unavailable); } let appended = rows.push(blot_eval_type_evidence::RowMapping { mapping.variable,actual }); if appended != Error.none { return 0,appended; } }
    let value,error = generator.evaluator.closedNodeSlots(owner.unit_id,id,owner.static_values.table.slots,mappings.items,rows.items); if error == Error.none { return value,error; } if error == Error.out_of_memory { return 0,error; }
    if generator.evaluator.diagnostic.present { let code = generator.evaluator.diagnostic.value.code; if code == blot_check_diagnostic_code::Code.unsupported || code == blot_check_diagnostic_code::Code.const_runtime_dependency { generator.evaluator.diagnostic.value.code = blot_check_diagnostic_code::Code.stage_unavailable; } } return 0,generator.evaluationFailure();

    }
    let cleanup_result_52_0,cleanup_result_52_1 = cleanup_continuation_52();
     rows.deinit(); 
    return cleanup_result_52_0,cleanup_result_52_1;

    }
    let cleanup_result_53_0,cleanup_result_53_1 = cleanup_continuation_53();
     mappings.deinit(); 
    return cleanup_result_53_0,cleanup_result_53_1;
}
fn stagingOp(code: u32) -> blot_check_typed_staging::Op { match code { 0=>{ return blot_check_typed_staging::Op.quote; },1=>{ return blot_check_typed_staging::Op.splice; },2=>{ return blot_check_typed_staging::Op.lift; },3=>{ return blot_check_typed_staging::Op.emit; },4=>{ return blot_check_typed_staging::Op.run; },5=>{ return blot_check_typed_staging::Op.describe; },6=>{ return blot_check_typed_staging::Op.same; },7=>{ return blot_check_typed_staging::Op.fields; },8=>{ return blot_check_typed_staging::Op.evaluate; },_=>{ assert(false); return blot_check_typed_staging::Op.quote; }, } }
recursive fn prepareStaging(owner: Owner&,id: u32,depth: i64) -> StagingPlan,Error {
    let generator .= owner.generator; let source .= generator.unit(owner.unit_id); let node = source.node(id); let op = stagingOp(node.c); var value: u32 = 0;
    if op == blot_check_typed_staging::Op.lift || op == blot_check_typed_staging::Op.splice { if !owner.staged.present { return StagingPlan { 0 },generator.fail(owner.unit_id,id,blot_backend_core_backend::Code.stage_unavailable); } let replacement = generator.evaluator.stagedReplacement(owner.staged.value,id); if !replacement.present { return StagingPlan { 0 },generator.fail(owner.unit_id,id,blot_backend_core_backend::Code.stage_unavailable); } value = replacement.value; }
    else { if op == blot_check_typed_staging::Op.quote { return StagingPlan { 0 },generator.fail(owner.unit_id,id,blot_backend_core_backend::Code.stage_unavailable); } var target = id; if op == blot_check_typed_staging::Op.emit { target = node.a; } let evaluated,error = stagingConstant(owner,target); if error != Error.none { return StagingPlan { 0 },error; } value = evaluated; }
    if op != blot_check_typed_staging::Op.emit && op != blot_check_typed_staging::Op.splice { return StagingPlan { value },Error.none; } let staged = generator.evaluator.stagedInfo(value); if !staged.present { return StagingPlan { 0 },generator.fail(owner.unit_id,id,blot_backend_core_backend::Code.code_shape_mismatch); } let metadata = staged.value;
    let previous_trace = generator.staging_trace; 
    recursive fn cleanup_continuation_51() -> StagingPlan,Error {

    let traced = blot_check_staging_origins::code(generator.staging_trace,generator.evaluator.units,metadata,blot_check_staging_origins::Source { owner.unit_id,id },blot_check_staging_origins::generator(generator.evaluator.storage.code_origins,value),op == blot_check_typed_staging::Op.splice);
    if traced != Error.none { var issue = blot_backend_core_backend::Code.staging_budget; if traced == Error.invalid_origin { issue = blot_backend_core_backend::Code.code_shape_mismatch; } return StagingPlan { 0 },generator.fail(owner.unit_id,id,issue); }
    var mappings = MappingBuffer {}; 
    recursive fn cleanup_continuation_50() -> StagingPlan,Error {
 var rows = RowBuffer {}; 
    recursive fn cleanup_continuation_49() -> StagingPlan,Error {

    for mapping in generator.evaluator.storage.type_mappings[metadata.mappings.start..metadata.mappings.start + metadata.mappings.len] { let actual,error = generator.representations.fromEvidence(generator.evaluator.evidenceStore(),mapping.evidence); if error != Error.none { if error == Error.out_of_memory { return StagingPlan { 0 },error; } return StagingPlan { 0 },generator.fail(owner.unit_id,id,blot_backend_core_backend::Code.stage_unavailable); } let appended = mappings.push(Mapping { mapping.variable,actual }); if appended != Error.none { return StagingPlan { 0 },appended; } }
    for mapping in generator.evaluator.storage.row_mappings[metadata.row_mappings.start..metadata.row_mappings.start + metadata.row_mappings.len] { let actual,error = generator.representations.rowFromEvidence(generator.evaluator.evidenceStore(),mapping.evidence); if error != Error.none { if error == Error.out_of_memory { return StagingPlan { 0 },error; } return StagingPlan { 0 },generator.fail(owner.unit_id,id,blot_backend_core_backend::Code.stage_unavailable); } let appended = rows.push(RowMapping { mapping.variable,actual }); if appended != Error.none { return StagingPlan { 0 },appended; } }
    let cleanups,error = blot_runtime_runtime_cleanup::initPooled(); if error != Error.none { return StagingPlan { 0 },error; } var future = Owner { generator,unit_id: metadata.unit,function_id: owner.function_id,mappings: mappings.items,row_mappings: rows.items,staged: blot_support::some(value),provider_local: owner.provider_local,labels: owner.labels,preparation_depth: owner.preparation_depth + 1,preparing: true,cleanups }; 
    recursive fn cleanup_continuation_48() -> StagingPlan,Error {

    let body,body_error = prepareBody(future,metadata.identity,depth + 1,false); if body_error != Error.none { return StagingPlan { 0 },body_error; } return StagingPlan { value,blot_support::some(body) },Error.none;

    }
    let cleanup_result_48_0,cleanup_result_48_1 = cleanup_continuation_48();
     future.deinit(); 
    return cleanup_result_48_0,cleanup_result_48_1;

    }
    let cleanup_result_49_0,cleanup_result_49_1 = cleanup_continuation_49();
     rows.deinit(); 
    return cleanup_result_49_0,cleanup_result_49_1;

    }
    let cleanup_result_50_0,cleanup_result_50_1 = cleanup_continuation_50();
     mappings.deinit(); 
    return cleanup_result_50_0,cleanup_result_50_1;

    }
    let cleanup_result_51_0,cleanup_result_51_1 = cleanup_continuation_51();
     generator.staging_trace = previous_trace; 
    return cleanup_result_51_0,cleanup_result_51_1;
}
recursive fn emitStaging(owner: Owner&,id: u32,depth: i64) -> Error {
    let generator .= owner.generator; var plan = StagingPlan { 0 }; match resolvedPlan(owner,id) { staging staged=>{ plan = staged.value; },_=>{ assert(false); }, }
    if plan.body.present {
        let staged = generator.evaluator.stagedInfo(plan.value); if !staged.present { return generator.fail(owner.unit_id,id,blot_backend_core_backend::Code.code_shape_mismatch); } let header = generator.planning.bodies.header(plan.body.value);
        let cleanups,error = blot_runtime_runtime_cleanup::initPooled(); if error != Error.none { return error; } var future = Owner { generator,unit_id: staged.value.unit,function_id: owner.function_id,mappings: header.mappings,row_mappings: header.rows,staged: blot_support::some(plan.value),provider_local: owner.provider_local,labels: owner.labels,body: plan.body,cleanups }; defer { future.deinit(); } return expression(future,staged.value.identity,depth + 1);
    }
    let scalar = generator.evaluator.valueScalar(plan.value); if scalar.present { return generator.emitValue(owner.function_id,scalar.value); } let ty,error = codeLayout(owner,generator.unit(owner.unit_id).typeOf(id),generator.unit(owner.unit_id).span(id)); if error != Error.none { return error; }
    let address,address_error = generator.static_data.serialize(generator,plan.value,ty,0); if address_error != Error.none { return address_error; } return generator.emitValue(owner.function_id,blot_backend_scalar_ops::Value { blot_backend_runtime_ir::SC_pointer,address });
}
recursive fn prepareInstances(owner: Owner&,decisions: const InstanceDecisions&,decision: const InstanceDecision&,depth: i64) -> LocalInstance[:],Error {
    let generator .= owner.generator; let producer = generator.unit(owner.unit_id).node(decision.statement).b; let instances = owned_instances.alloc_slice(decision.count); var prepared: i64 = 0; var published = false; 
    recursive fn cleanup_continuation_47() -> LocalInstance[:],Error {

    var mappings = MappingBuffer {}; 
    recursive fn cleanup_continuation_46() -> LocalInstance[:],Error {
 var rows = RowBuffer {}; 
    recursive fn cleanup_continuation_45() -> LocalInstance[:],Error {

    for index in 0..decision.count { mappings.clear(); rows.clear(); let facts = withFacts(owner.mappings,decisions.factsAt(decision,index),mappings); if facts != Error.none { return [],facts; } let row_facts = withFacts(owner.row_mappings,decisions.rowsAt(decision,index),rows); if row_facts != Error.none { return [],row_facts; }
        let body,error = prepareMapped(owner,producer,depth + 1,false,mappings.items,rows.items,null); if error != Error.none { return [],error; } instances[index] = LocalInstance { decision.layouts[index],body }; prepared++;
    } published = true; return instances,Error.none;

    }
    let cleanup_result_45_0,cleanup_result_45_1 = cleanup_continuation_45();
     rows.deinit(); 
    return cleanup_result_45_0,cleanup_result_45_1;

    }
    let cleanup_result_46_0,cleanup_result_46_1 = cleanup_continuation_46();
     mappings.deinit(); 
    return cleanup_result_46_0,cleanup_result_46_1;

    }
    let cleanup_result_47_0,cleanup_result_47_1 = cleanup_continuation_47();
     if !published { for instance in instances[..prepared] { generator.planning.bodies.release(instance.body); } owned_instances.free_slice(instances); } 
    return cleanup_result_47_0,cleanup_result_47_1;
}
recursive fn bindInstances(owner: Owner&,statement: u32,instances: const LocalInstance[:],depth: i64) -> Error {
    let generator .= owner.generator; let n = generator.unit(owner.unit_id).node(statement); var held = InstanceLocals {};
    for instance in instances { let prepared = preparedExpression(owner,instance.body,n.b,depth + 1,false); if prepared != Error.none { return prepared; } let local,error = temporary(owner,generator.representations.store.machine(instance.layout)); if error != Error.none { return error; } let stored = emit(owner,blot_backend_runtime_ir::OP_local_set,local); if stored != Error.none { return stored; } held.layouts[held.count] = instance.layout; held.locals[held.count] = local; held.count++; }
    owner.instance_locals.insert(n.a,held); return Error.none;
}
fn useCount(owner: Owner&,binding: u32) -> i64,Error { let source .= owner.generator.unit(owner.unit_id); let uses,error = owner.generator.unitUses(owner.unit_id,blot_backend_unit_index::Need {}); if error != Error.none { return 0,error; } var count: i64 = 0; for index in uses.references.get(binding) { let reference = source.reference(index); if reference.unit == 0 || reference.unit == owner.unit_id { count++; } } return count,Error.none; }
fn hasMutableUse(owner: Owner&,binding: u32) -> bool,Error { let uses,error = owner.generator.unitUses(owner.unit_id,blot_backend_unit_index::Need {}); if error != Error.none { return false,error; } let flags = uses.flagsOf(binding); return flags.carried || flags.merge_branch || flags.merge_result,Error.none; }
recursive fn preparePattern(owner: Owner&,body: u32,id: u32,depth: i64) -> Error {
    if id == 0 { return Error.none; } let generator .= owner.generator; let source .= generator.unit(owner.unit_id); if depth >= 1024 { return generator.fail(owner.unit_id,generator.planning.bodies.header(body).root,blot_backend_core_backend::Code.complexity); } let pattern = source.pattern(id);
    match pattern.tag { value=>{ return prepareNode(owner,body,pattern.a,depth + 1,false); },bind=>{ if pattern.a != 0 { owner.locals.insert(pattern.a,0); } },product=>{ for child in source.patternChildren(id) { let error = preparePattern(owner,body,child,depth + 1); if error != Error.none { return error; } } },constructor,record_payload=>{ return preparePattern(owner,body,pattern.b,depth + 1); },_=>{}, } return Error.none;
}
fn prepareConstructorSubject(owner: Owner&,body: u32,match_id: u32,arm: blot_check_core::MatchArm) -> Error {
    let source .= owner.generator.unit(owner.unit_id); let inputs = source.matchInputs(match_id); if inputs.len != 1 || source.node(inputs[0]).tag != blot_check_core::Tag.reference { return Error.none; } let subject = source.reference(inputs[0]); if subject.unit != 0 && subject.unit != owner.unit_id { return Error.none; } if !owner.locals.contains(subject.binding) { return Error.none; }
    let rows = source.armRows(arm); if rows.len != 1 { return Error.none; } let patterns = source.rowPatterns(rows[0]); if patterns.len != 1 { return Error.none; } let pattern = source.pattern(patterns[0]); if pattern.tag != blot_check_core::PatternTag.constructor || pattern.b == 0 { return Error.none; } let payload = source.pattern(pattern.b); if payload.tag != blot_check_core::PatternTag.bind || payload.a == 0 { return Error.none; }
    var constructed_id = arm.body; for index in 0..32 { let node = source.node(constructed_id); if node.tag == blot_check_core::Tag.return_ { if node.a == 0 { return Error.none; } constructed_id = node.a; } else if node.tag == blot_check_core::Tag.block_ || node.tag == blot_check_core::Tag.suite { let children = source.children(constructed_id); if children.len != 1 { return Error.none; } constructed_id = children[0]; } else { break; } }
    let constructed = source.node(constructed_id); if constructed.tag != blot_check_core::Tag.construct || constructed.a != pattern.a || constructed.c != 0 || constructed.b == 0 || source.node(constructed.b).tag != blot_check_core::Tag.reference { return Error.none; }
    let reference = source.reference(constructed.b); if (reference.unit != 0 && reference.unit != owner.unit_id) || reference.binding != payload.a { return Error.none; } return owner.generator.planning.bodies.put(body,constructed_id,Plan.constructor_subject { inputs[0] });
}
recursive fn staticCallableValue(owner: Owner&,id: u32,remaining: i64&,depth: i64) -> blot_support::Option<u32>,Error {
    if remaining == 0 || depth >= 64 { return blot_support::none<u32>(),Error.none; } remaining--; let generator .= owner.generator; let source .= generator.unit(owner.unit_id); let node = source.node(id);
    if node.tag == blot_check_core::Tag.reference { let reference = source.reference(id); if reference.unit == 0 || reference.unit == owner.unit_id { let value .= owner.static_values.get(reference.binding); if value != null { return blot_support::some(value),Error.none; } } return blot_support::none<u32>(),Error.none; }
    if node.tag != blot_check_core::Tag.project { return blot_support::none<u32>(),Error.none; } let container,error = staticCallableValue(owner,node.a,remaining,depth + 1); if error != Error.none || !container.present { return blot_support::none<u32>(),error; }
    let projection = source.projection(node.b); if projection.nominal.unit != 0 || projection.nominal.decl != 0 { return blot_support::none<u32>(),Error.none; } let info = generator.evaluator.valueInfo(container.value);
    if projection.field != 0 { if info.kind != blot_eval_core_eval::ValueKind.record { return blot_support::none<u32>(),Error.none; } for name,index in generator.evaluator.recordFieldNames(container.value) { if remaining == 0 { return blot_support::none<u32>(),Error.none; } remaining--; if name == projection.field { return blot_support::some(generator.evaluator.valueChildren(container.value)[index]),Error.none; } } return blot_support::none<u32>(),Error.none; }
    if info.kind != blot_eval_core_eval::ValueKind.product || projection.variants.len != 1 { return blot_support::none<u32>(),Error.none; } let variant = source.projectionVariants(node.b)[0]; if variant.tag != 0 || variant.field >= info.len { return blot_support::none<u32>(),Error.none; } return blot_support::some(generator.evaluator.valueChildren(container.value)[variant.field]),Error.none;
}
fn staticCallableTemplate(owner: Owner&,id: u32) -> blot_support::Option<Template>,Error {
    if owner.static_values.table.count == 0 { return blot_support::none<Template>(),Error.none; } let generator .= owner.generator; var remaining: i64 = 65536; let value,error = staticCallableValue(owner,id,remaining,0); if error != Error.none || !value.present { return blot_support::none<Template>(),error; }
    if generator.evaluator.valueInfo(value.value).kind != blot_eval_core_eval::ValueKind.closure { return blot_support::none<Template>(),Error.none; } let metadata = generator.evaluator.closureInfo(value.value);
    if metadata.origin != blot_eval_core_eval::ClosureOrigin.named || metadata.applied != 0 || metadata.mappings.len != 0 || metadata.row_mappings.len != 0 { return blot_support::none<Template>(),Error.none; } let target = blot_check_core::BindingRef { metadata.unit,metadata.identity };
    for &source,ordinal in generator.units { var unit = source.unit; if unit == 0 { unit = (ordinal + 1) as u32; } for node,index in source.nodes { if remaining == 0 { return blot_support::none<Template>(),Error.none; } remaining--; if node.tag != blot_check_core::Tag.reference { continue; } let normalized,normalized_error = generator.normalize(unit,source.reference(index as u32)); if normalized_error != Error.none { return blot_support::none<Template>(),normalized_error; } if normalized != target { continue; } let instances,instance_error = scopedCallableTargetInstances(owner,id,target); if instance_error != Error.none { return blot_support::none<Template>(),instance_error; } return blot_support::some(Template { unit,node: index as u32,callable_instances: instances }),Error.none; } }
    return blot_support::none<Template>(),Error.none;
}
fn describeCallable(owner: Owner&,body: u32,id: u32) -> blot_support::Option<Template>,Error {
    let evaluated,error = staticCallableTemplate(owner,id); if error != Error.none || evaluated.present { return evaluated,error; } let source .= owner.generator.unit(owner.unit_id); let node = source.node(id);
    if node.tag == blot_check_core::Tag.closure { match owner.generator.planning.bodies.get(body,id) { template value=>{ return blot_support::some(value.value.metadata),Error.none; },_=>{ assert(false); }, } }
    if node.tag == blot_check_core::Tag.primitive_function || node.tag == blot_check_core::Tag.constructor_function { let instances,instances_error = scopedCallableInstances(owner,id); if instances_error != Error.none { return blot_support::none<Template>(),instances_error; } return blot_support::some(Template { unit: owner.unit_id,node: id,callable_instances: instances }),Error.none; }
    if node.tag != blot_check_core::Tag.reference { return blot_support::none<Template>(),Error.none; } let reference = source.reference(id);
    if reference.unit == 0 || reference.unit == owner.unit_id { let metadata .= owner.templates.get(reference.binding); if metadata != null { let selected,error = templateAt(owner,metadata,id); if error != Error.none { return blot_support::none<Template>(),error; } return blot_support::some(selected),Error.none; } let kind = source.binding(reference.binding).kind; if kind != blot_check_core::BindingKind.global && kind != blot_check_core::BindingKind.external { return blot_support::none<Template>(),Error.none; } }
    let instances,instances_error = scopedCallableInstances(owner,id); if instances_error != Error.none { return blot_support::none<Template>(),instances_error; } return blot_support::some(Template { unit: owner.unit_id,node: id,callable_instances: instances }),Error.none;
}
recursive fn prepareFactory(owner: Owner&,body: u32,id: u32) -> blot_support::Option<FactoryPlan>,Error {
    assert(owner.preparing); let generator .= owner.generator; let source .= generator.unit(owner.unit_id); let node = source.node(id); let result_type = source.types.node(node.ty);
    if result_type.tag != blot_check_types::Tag.nominal || result_type.a != 4294967295 || result_type.b != 5 { return blot_support::none<FactoryPlan>(),Error.none; } if owner.preparation_depth >= 256 { return blot_support::none<FactoryPlan>(),generator.fail(owner.unit_id,id,blot_backend_core_backend::Code.complexity); }
    var admitted: bool[16] = [false;16]; var callee = FactoryCallee.named { Key {} }; var unit: u32 = 0; var root: u32 = 0; var mappings = MappingBuffer {}; 
    recursive fn cleanup_continuation_44() -> blot_support::Option<FactoryPlan>,Error {
 var rows = RowBuffer {}; 
    recursive fn cleanup_continuation_43() -> blot_support::Option<FactoryPlan>,Error {

    let cleanups,cleanup_error = blot_runtime_runtime_cleanup::initPooled(); if cleanup_error != Error.none { return blot_support::none<FactoryPlan>(),cleanup_error; } var preparer = Owner { generator,unit_id: 0,function_id: owner.function_id,mappings: [],factory_template: true,preparation_depth: owner.preparation_depth + 1,preparing: true,cleanups }; 
    recursive fn cleanup_continuation_42() -> blot_support::Option<FactoryPlan>,Error {

    if node.tag == blot_check_core::Tag.call {
        let call = source.call(id); var key = Key {}; match generator.planning.bodies.get(body,id) { named plan=>{ key = plan.value.call.key; },_=>{ assert(false); }, }
        if key.count != call.arguments.len || !computationAction(owner,key.result).present { return blot_support::none<FactoryPlan>(),Error.none; } let producer .= generator.unit(key.target.unit); let definition .= producer.body(key.target.binding); if definition == null || !definition.is_function || definition.parameters.len != key.count { return blot_support::none<FactoryPlan>(),Error.none; }
        for argument,index in call.arguments { admitted[index] = isCallableTemplate(owner,argument); } if !factoryTemplateResult(owner,key.target.unit,definition.root,producer.bodyParameters(definition),admitted[..key.count],0) { return blot_support::none<FactoryPlan>(),Error.none; }
        var entries = blot_backend_substitution_buffers::Entries {}; defer { entries.deinit(); }
        for argument,index in call.arguments { let parameter = producer.bodyParameters(definition)[index]; if admitted[index] {
            let actual,error = codeLayout(owner,source.typeOf(argument),source.span(argument)); if error != Error.none { return blot_support::none<FactoryPlan>(),error; } let selected,selected_error = sourceArgumentLayout(owner,key.parameters[index],actual,0); if selected_error != Error.none { return blot_support::none<FactoryPlan>(),selected_error; } key.parameters[index] = selected;
            let metadata,metadata_error = describeCallable(owner,body,argument); if metadata_error != Error.none { return blot_support::none<FactoryPlan>(),metadata_error; } if !metadata.present { return blot_support::none<FactoryPlan>(),generator.fail(owner.unit_id,argument,blot_backend_core_backend::Code.unresolved_type); }
            let template,template_error = generator.captureTemplate(metadata.value); if template_error != Error.none { return blot_support::none<FactoryPlan>(),template_error; } let appended = entries.push(blot_reuse_substitution_keys::Entry { parameter.binding,template }); if appended != Error.none { return blot_support::none<FactoryPlan>(),appended; } preparer.templates.insert(parameter.binding,metadata.value);
        } else if parameter.binding != 0 { preparer.locals.insert(parameter.binding,0); } }
        let templates,template_error = generator.representations.template_keys.intern(entries.items); if template_error != Error.none { if template_error == Error.out_of_memory { return blot_support::none<FactoryPlan>(),template_error; } return blot_support::none<FactoryPlan>(),generator.fail(owner.unit_id,id,blot_backend_core_backend::Code.complexity); } key.templates = templates; key.template_result = true;
        let service,service_error = generator.specializer(); if service_error != Error.none { return blot_support::none<FactoryPlan>(),service_error; } let resolved,resolved_error = service.named(key,generator.representations.instance_arguments.get(key.instance_arguments),mappings,rows); if resolved_error != Error.none { return blot_support::none<FactoryPlan>(),generator.specializationFailure(service,resolved_error); }
        callee = FactoryCallee.named { key }; unit = key.target.unit; root = definition.root;
    } else {
        if !isCallableTemplate(owner,node.a) { return blot_support::none<FactoryPlan>(),Error.none; } let callable,error = describeCallable(owner,body,node.a); if error != Error.none || !callable.present { return blot_support::none<FactoryPlan>(),error; } let factory = callable.value; unit = factory.unit; if unit == 0 { unit = owner.unit_id; }
        let producer .= generator.unit(unit); let factory_node = producer.node(factory.node); if factory_node.tag != blot_check_core::Tag.closure { return blot_support::none<FactoryPlan>(),Error.none; } let metadata = producer.closures[factory_node.a]; admitted[0] = isCallableTemplate(owner,node.b);
        if !factoryTemplateResult(owner,unit,metadata.body,[metadata.parameter],admitted[..1],0) { return blot_support::none<FactoryPlan>(),Error.none; } let original,original_error = codeLayout(owner,source.typeOf(node.a),source.span(id)); if original_error != Error.none { return blot_support::none<FactoryPlan>(),original_error; } var ty = original;
        if admitted[0] { let arrow = generator.representations.store.node(ty); let actual,actual_error = codeLayout(owner,source.typeOf(node.b),source.span(node.b)); if actual_error != Error.none { return blot_support::none<FactoryPlan>(),actual_error; } let argument,argument_error = sourceArgumentLayout(owner,arrow.a,actual,0); if argument_error != Error.none { return blot_support::none<FactoryPlan>(),argument_error; } let selected,selected_error = generator.internLayoutWithEffects(blot_backend_layout::Tag.function,argument,arrow.b,arrow.c,[]); if selected_error != Error.none { return blot_support::none<FactoryPlan>(),selected_error; } ty = selected; }
        var key = blot_reuse_code_artifacts::ClosureKey { unit,catalog: factory_node.a,ty,scalar_environment: factory.scalar_environment,captures: factory.captures,templates: factory.templates,evidence: factory.evidence,rows: factory.rows,template_result: true };
        if admitted[0] { let argument,argument_error = describeCallable(owner,body,node.b); if argument_error != Error.none { return blot_support::none<FactoryPlan>(),argument_error; } if !argument.present { return blot_support::none<FactoryPlan>(),generator.fail(owner.unit_id,node.b,blot_backend_core_backend::Code.unresolved_type); } let template,template_error = generator.captureTemplate(argument.value); if template_error != Error.none { return blot_support::none<FactoryPlan>(),template_error; } key.parameter_template = template; preparer.templates.insert(metadata.parameter.binding,argument.value); }
        else if metadata.parameter.binding != 0 { preparer.locals.insert(metadata.parameter.binding,0); }
        let resolved = generator.resolveClosureMappings(key,mappings,rows); if resolved != Error.none { return blot_support::none<FactoryPlan>(),resolved; }
        for binding in producer.extra[metadata.captures.start..metadata.captures.start + metadata.captures.len] { let captured = generator.capturedTemplate(key.templates,binding); if captured.present { preparer.templates.insert(binding,blot_backend_core_backend::templateMetadata(captured.value,0)); } else { preparer.locals.insert(binding,0); } }
        callee = FactoryCallee.closure { key }; root = metadata.body;
    }
    preparer.unit_id = unit; preparer.mappings = mappings.items; preparer.row_mappings = rows.items; let prepared,error = generator.planning.bodies.create(unit,root,mappings.items,rows.items); if error != Error.none { return blot_support::none<FactoryPlan>(),error; } 
    recursive fn cleanup_continuation_41() -> blot_support::Option<FactoryPlan>,Error {

    let generated = prepareNode(preparer,prepared,root,0,true); if generated != Error.none { return blot_support::none<FactoryPlan>(),generated; } let described,described_error = describeComputation(preparer,prepared,root,0); if described_error != Error.none { return blot_support::none<FactoryPlan>(),described_error; } if !described.present { return blot_support::none<FactoryPlan>(),generator.fail(unit,root,blot_backend_core_backend::Code.unresolved_type); }
    var result = described.value; result.scalar_environment = false; return blot_support::some(FactoryPlan { callee,admitted,result }),Error.none;

    }
    let cleanup_result_41_0,cleanup_result_41_1 = cleanup_continuation_41();
     generator.planning.bodies.release(prepared); 
    return cleanup_result_41_0,cleanup_result_41_1;

    }
    let cleanup_result_42_0,cleanup_result_42_1 = cleanup_continuation_42();
     preparer.deinit(); 
    return cleanup_result_42_0,cleanup_result_42_1;

    }
    let cleanup_result_43_0,cleanup_result_43_1 = cleanup_continuation_43();
     rows.deinit(); 
    return cleanup_result_43_0,cleanup_result_43_1;

    }
    let cleanup_result_44_0,cleanup_result_44_1 = cleanup_continuation_44();
     mappings.deinit(); 
    return cleanup_result_44_0,cleanup_result_44_1;
}
recursive fn describeComputation(owner: Owner&,body: u32,id: u32,depth: i64) -> blot_support::Option<Template>,Error {
    if id == 0 { return blot_support::none<Template>(),Error.none; } let generator .= owner.generator; let source .= generator.unit(owner.unit_id); if depth >= 1024 { return blot_support::none<Template>(),generator.fail(owner.unit_id,id,blot_backend_core_backend::Code.complexity); } let node = source.node(id);
    match node.tag {
        computation,effect_scope=>{ let callable,error = describeCallable(owner,body,node.a); if error != Error.none || !callable.present { return callable,error; } var metadata = callable.value; metadata.computation = true; return blot_support::some(metadata),Error.none; },
        reference=>{ let reference = source.reference(id); if reference.unit == 0 || reference.unit == owner.unit_id { let metadata .= owner.templates.get(reference.binding); if metadata != null && metadata.computation { return blot_support::some(metadata),Error.none; } } },
        call=>{ match generator.planning.bodies.get(body,id) { named plan=>{ if plan.value.factory.present { return blot_support::some(plan.value.factory.value.result),Error.none; } },_=>{ assert(false); }, } },
        apply=>{ match generator.planning.bodies.get(body,id) { application plan=>{ if plan.value.factory.present { return blot_support::some(plan.value.factory.value.result),Error.none; } },_=>{ assert(false); }, } },
        block_=>{ for statement in source.children(id) { let value = source.node(statement); if value.tag == blot_check_core::Tag.return_ && value.b == id { return describeComputation(owner,body,value.a,depth + 1); } } },
        if_value=>{ let left,left_error = describeComputation(owner,body,node.b,depth + 1); if left_error != Error.none || !left.present { return blot_support::none<Template>(),left_error; } let right,right_error = describeComputation(owner,body,node.c,depth + 1); if right_error != Error.none || !right.present { return blot_support::none<Template>(),right_error; } let left_key,key_error = generator.captureTemplate(left.value); if key_error != Error.none { return blot_support::none<Template>(),key_error; } let right_key,right_key_error = generator.captureTemplate(right.value); if right_key_error != Error.none { return blot_support::none<Template>(),right_key_error; } if left_key != right_key { return blot_support::none<Template>(),generator.fail(owner.unit_id,id,blot_backend_core_backend::Code.unresolved_type); } return left,Error.none; },_=>{},
    } return blot_support::none<Template>(),Error.none;
}
fn codeLayout(owner: Owner&,ty: u32,span: blot_check_core::Span) -> u32,Error {
    let generator .= owner.generator; generator.planning.facts.stats.layout_requests++; let slot .= owner.layout_cache[ty % 32]; if slot.ty == ty && slot.value != 0 { generator.planning.facts.stats.layout_reused++; return slot.value,Error.none; }
    let result,error = generator.codeLayoutWithRows(owner.unit_id,ty,owner.mappings,owner.row_mappings,span); if error != Error.none { return 0,error; } slot = LayoutEntry { ty,result }; return result,Error.none;
}
recursive fn preparePrivateBinding(owner: Owner&,body: u32,id: u32,depth: i64) -> blot_support::Option<Plan>,Error {
    let generator .= owner.generator; let source .= generator.unit(owner.unit_id); let n = source.node(id); let collection,error = prepareCollectionStep(owner,body,id,depth); if error != Error.none || collection.present { return collection,error; } let value = source.node(n.b);
    if value.tag == blot_check_core::Tag.array_op && source.arrayOperation(n.b) == blot_backend_collection_ops::Op.cursor_value {
        let operand = source.children(n.b)[0]; if source.node(operand).tag == blot_check_core::Tag.reference {
            let reference = source.reference(operand); let concrete,concrete_error = codeLayout(owner,source.typeOf(operand),source.span(id)); if concrete_error != Error.none { return blot_support::none<Plan>(),concrete_error; } let cursor = generator.representations.store.node(concrete);
            if (reference.unit == 0 || reference.unit == owner.unit_id) && cursor.tag == blot_backend_layout::Tag.cursor {
                let words,word_error = generator.collectionRowWords(cursor.a); if word_error != Error.none { return blot_support::none<Plan>(),word_error; } if words != 0 { let uses,uses_error = generator.unitUses(owner.unit_id,blot_backend_unit_index::Need { flow: true }); if uses_error != Error.none { return blot_support::none<Plan>(),uses_error; }
                    if blot_backend_private_cursor::check(source,uses,generator.planning.bodies.header(body).root,reference.binding) { let row = generator.representations.store.node(cursor.a).a; if blot_backend_packed_layout::rowWords(generator.representations.store,row) != 0 && blot_reuse_row_projection_uses::checkBinding(source,generator.planning.bodies.header(body).root,id,n.a,generator.representations.store,row) { return blot_support::some(Plan.private_row { row }),Error.none; } }
                }
            }
        }
    }
    if source.types.node(source.binding(n.a).ty).tag != blot_check_types::Tag.cursor { return blot_support::none<Plan>(),Error.none; }
    let concrete,concrete_error = codeLayout(owner,source.binding(n.a).ty,source.span(id)); if concrete_error != Error.none { return blot_support::none<Plan>(),concrete_error; } let cursor = generator.representations.store.node(concrete);
    if cursor.tag != blot_backend_layout::Tag.cursor || generator.representations.store.node(cursor.a).tag != blot_backend_layout::Tag.list { return blot_support::none<Plan>(),Error.none; } let words,word_error = generator.collectionRowWords(cursor.a); if word_error != Error.none { return blot_support::none<Plan>(),word_error; } if words == 0 { return blot_support::none<Plan>(),Error.none; }
    let uses,uses_error = generator.unitUses(owner.unit_id,blot_backend_unit_index::Need { flow: true }); if uses_error != Error.none { return blot_support::none<Plan>(),uses_error; } if !blot_backend_private_cursor::check(source,uses,generator.planning.bodies.header(body).root,n.a) { return blot_support::none<Plan>(),Error.none; }
    let prepared = prepareNode(owner,body,n.b,depth + 1,false); if prepared != Error.none { return blot_support::none<Plan>(),prepared; } let input,input_error = privateCursorConstructor(owner,body,n.b); if input_error != Error.none { return blot_support::none<Plan>(),input_error; }
    if !input.present && source.node(n.b).tag != blot_check_core::Tag.reference && !(source.node(n.b).tag == blot_check_core::Tag.array_op && source.arrayOperation(n.b) == blot_backend_collection_ops::Op.cursor_advance) { return blot_support::none<Plan>(),Error.none; }
    var selected: u32 = 0; if input.present { selected = input.value; } return blot_support::some(Plan.private_cursor { selected,blot_support::none<blot_backend_linear_cursor::Plan>() }),Error.none;
}
recursive fn prepareNode(owner: Owner&,body: u32,id: u32,depth: i64,template: bool) -> Error {
    assert(owner.preparing); let generator .= owner.generator; let bodies .= generator.planning.bodies; if id == 0 || bodies.contains(body,id) { return Error.none; } let source .= generator.unit(owner.unit_id); if depth >= 1024 { return generator.fail(owner.unit_id,id,blot_backend_core_backend::Code.complexity); } let n = source.node(id);
    if source.has_usage_contracts && !bodies.headers[body - 1].has_owners { let owns,error = blot_check_usage_check::containsNominal(source.types,source.nominals,n.ty); if error != Error.none { return generator.fail(owner.unit_id,id,blot_backend_core_backend::Code.complexity); } bodies.headers[body - 1].has_owners = owns; }
    if n.tag == blot_check_core::Tag.staging { let staged,error = prepareStaging(owner,id,depth); if error != Error.none { return error; } var plan = Plan.staging { staged }; let stored = bodies.put(body,id,plan); if stored != Error.none { plan.deinit(bodies); } return stored; }
    if n.tag == blot_check_core::Tag.proof_guard || (n.tag == blot_check_core::Tag.array_op && (source.arrayOperation(id) == blot_backend_collection_ops::Op.get || source.arrayOperation(id) == blot_backend_collection_ops::Op.set)) { bodies.headers[body - 1].has_numeric_checks = true; }
    if n.tag == blot_check_core::Tag.bind {
        let compile_only,error = blot_check_typed_staging::compileOnly(source.types,source.binding(n.a).ty); if error != Error.none { if error == Error.out_of_memory { return error; } return generator.fail(owner.unit_id,id,blot_backend_core_backend::Code.staging_budget); }
        if compile_only { let value,value_error = stagingConstant(owner,n.b); if value_error != Error.none { return value_error; } owner.static_values.insert(n.a,value); return bodies.put(body,id,Plan.static_binding { value }); }
        let binding = source.binding(n.a); let shape = source.types.node(binding.ty); var mutable = true; if binding.kind == blot_check_core::BindingKind.local && binding.scheme.variables.len != 0 { let value,error = hasMutableUse(owner,n.a); if error != Error.none { return error; } mutable = value; }
        if binding.kind == blot_check_core::BindingKind.local && binding.scheme.variables.len != 0 && !mutable {
            let data = shape.tag == blot_check_types::Tag.nominal || shape.tag == blot_check_types::Tag.product || shape.tag == blot_check_types::Tag.record;
            if data { let proof = blot_eval_closed_local_value::analyze(generator.units,owner.unit_id,n.b); if proof.present {
                if generator.artifacts != null { for target in proof.value.dependencies[..proof.value.len] { let read = generator.artifacts.readInlineBody(target); if read != Error.none { return read; } } generator.artifacts.requireFreshCode(); }
                let value,error = generator.evaluator.closedConstructorNode(owner.unit_id,n.b); if error != Error.none { if error == Error.out_of_memory { return error; } return generator.evaluationFailure(); } owner.static_values.insert(n.a,value); return bodies.put(body,id,Plan.static_binding { value });
            } }
            let producer = source.node(n.b).tag; let built = producer == blot_check_core::Tag.call || producer == blot_check_core::Tag.apply || producer == blot_check_core::Tag.project || producer == blot_check_core::Tag.construct || producer == blot_check_core::Tag.product || producer == blot_check_core::Tag.record;
            if generator.speculative_locals && built {
                let count,count_error = useCount(owner,n.a); if count_error != Error.none { return count_error; }
                if count != 0 { let concrete,error = codeLayout(owner,binding.ty,source.span(id)); if error != Error.none { return error; } if hasErasedType(owner,concrete,0) && blot_eval_closed_local_value::dataShape(generator.units,owner.unit_id,binding.ty) {
                    let value,found,value_error = generator.evaluator.attemptClosedNodeSlots(owner.unit_id,n.b,owner.static_values.table.slots); if value_error != Error.none { return value_error; } if found { if generator.artifacts != null { generator.artifacts.requireFreshCode(); } generator.speculated = true; owner.static_values.insert(n.a,value); return bodies.put(body,id,Plan.static_binding { value }); }
                } }
            }
        }
        if owner.local_instances.present { let decision .= owner.local_instances.value.find(id); if decision != null { let instances,error = prepareInstances(owner,owner.local_instances.value,decision,depth); if error != Error.none { return error; } var plan = Plan.instances { instances }; let stored = bodies.put(body,id,plan); if stored != Error.none { plan.deinit(bodies); } return stored; } }
    }
    var entry = blot_support::none<Plan>();
    match n.tag {
        resource_acquire,resource_scope=>{ let plan,error = prepareResourceScope(owner,id); if error != Error.none { return error; } entry = blot_support::some(Plan.resource_scope { plan.acquire,plan.release,plan.callback }); },resource_release=>{},
        usage_borrow=>{ let plan,error = prepareUsageBorrow(owner,id); if error != Error.none { return error; } entry = blot_support::some(Plan.usage_borrow { plan }); },
        usage_share=>{ let plan,error = prepareUsageShare(owner,id); if error != Error.none { return error; } entry = blot_support::some(Plan.usage_share { plan }); },
        usage_read=>{ let plan,error = prepareUsageRead(owner,id); if error != Error.none { return error; } entry = blot_support::some(Plan.usage_read { plan }); },
        bind=>{ let plan,error = preparePrivateBinding(owner,body,id,depth); if error != Error.none { return error; } entry = plan; },
        operation_value=>{ let ty,error = codeLayout(owner,n.ty,source.span(id)); if error != Error.none { return error; } let label,label_error = generator.operationLabel(owner.unit_id,n.a,owner.mappings,owner.row_mappings,source.span(id)); if label_error != Error.none { return label_error; } entry = blot_support::some(Plan.operation { ty,label }); },
        effect_provider,state_provider=>{ let plan,error = prepareProvider(owner,id); if error != Error.none { return error; } entry = blot_support::some(Plan.provider { plan }); },
        effect_reflection=>{ return generator.fail(owner.unit_id,id,blot_backend_core_backend::Code.backend_const_only); },
        pattern_bind=>{ let plan,error = prepareCollectionStep(owner,body,id,depth); if error != Error.none { return error; } entry = plan; if !entry.present { let private,error = preparePrivateCursorPattern(owner,body,id); if error != Error.none { return error; } entry = private; } },
        closure=>{ let plan,error = prepareTemplate(owner,id); if error != Error.none { return error; } entry = blot_support::some(Plan.template { plan }); },
        reference=>{ let plan,error = prepareReference(owner,id); if error != Error.none { return error; } entry = blot_support::some(Plan.reference { plan }); },
        project=>{ let plan,error = prepareProjection(owner,body,id,depth); if error != Error.none { return error; } entry = blot_support::some(Plan.projection { plan }); },
        update=>{ let plan,error = prepareUpdateLocations(owner,id); if error != Error.none { return error; } entry = blot_support::some(Plan.update_locations { plan }); },
        call=>{ let plan,error = prepareNamedCall(owner,id); if error != Error.none { return error; } entry = blot_support::some(Plan.named { plan }); },
        apply=>{ let plan,error = prepareApplication(owner,id); if error != Error.none { return error; } entry = blot_support::some(Plan.application { plan }); },
        scalar,associated=>{ let plan,error = resolveDispatch(owner,id); if error != Error.none { return error; } entry = blot_support::some(Plan.dispatch { plan }); },
        type_same=>{ let plan,error = prepareTypeComparison(owner,id); if error != Error.none { return error; } entry = blot_support::some(Plan.comparison { plan }); },
        result_associated=>{ let plan,error = prepareResultAssociated(owner,id); if error != Error.none { return error; } entry = blot_support::some(Plan.result_member { plan }); },
        resolver_op=>{ let plan,error = prepareResolver(owner,id); if error != Error.none { return error; } entry = blot_support::some(Plan.resolver { plan }); },
        block_,if_value=>{ var kind = JoinKind.value; if template { kind = JoinKind.template; } let plan,error = prepareJoin(owner,id,kind); if error != Error.none { return error; } entry = blot_support::some(Plan.join { plan }); },
        if_stmt=>{ let plan,error = prepareJoin(owner,id,JoinKind.statement); if error != Error.none { return error; } entry = blot_support::some(Plan.join { plan }); },
        match_=>{ let plan,error = prepareMatch(owner,id); if error != Error.none { return error; } entry = blot_support::some(Plan.match_ { plan }); },
        loop_=>{ let plan,error = prepareLoop(owner,body,id,depth); if error != Error.none { return error; } entry = blot_support::some(Plan.loop_ { plan }); },
        request_loop=>{ let plan,error = prepareRequestLoop(owner,id); if error != Error.none { return error; } entry = blot_support::some(Plan.request { plan }); },
        return_=>{ let plan,error = prepareReturn(owner,id,blot_backend_resolved_flow::ExitKind.return_,n.b); if error != Error.none { return error; } entry = blot_support::some(Plan.exit { plan }); },
        break_=>{ let plan,error = prepareBreak(owner,id); if error != Error.none { return error; } entry = blot_support::some(Plan.exit { plan }); },_=>{},
    }
    if entry.present { let stored = bodies.put(body,id,entry.value); if stored != Error.none { entry.value.deinit(bodies); return stored; } } if n.tag == blot_check_core::Tag.associated { bodies.headers[body - 1].has_associated = true; }
    let children = prepareChildren(owner,body,id,depth,template); if children != Error.none { return children; }
    if n.tag == blot_check_core::Tag.call || n.tag == blot_check_core::Tag.apply { let factory,error = prepareFactory(owner,body,id); if error != Error.none { return error; } let payload .= bodies.getRef(body,id); match payload { named &call=>{ call.value.factory = factory; },application &application=>{ application.value.factory = factory; },_=>{ assert(false); }, } } return Error.none;
}
recursive fn prepareChildren(owner: Owner&,body: u32,id: u32,depth: i64,template: bool) -> Error {
    let source .= owner.generator.unit(owner.unit_id); let n = source.node(id); let bodies .= owner.generator.planning.bodies;
    match n.tag {
        package_pack=>{ for child in source.children(id) { let error = prepareNode(owner,body,child,depth + 1,false); if error != Error.none { return error; } } },
        package_unpack=>{ return preparePackageBody(owner,body,id,depth); },
        block_=>{ let length = owner.planned_returns.items.len; let pushed = owner.planned_returns.push(PlannedReturn { id,template }); if pushed != Error.none { return pushed; } defer { owner.planned_returns.resize(length); } for child in source.children(id) { let error = prepareNode(owner,body,child,depth + 1,false); if error != Error.none { return error; } let tag = source.node(child).tag; if tag == blot_check_core::Tag.return_ || tag == blot_check_core::Tag.break_ || source.types.node(source.typeOf(child)).tag == blot_check_types::Tag.never { break; } } },
        task,suite,product,record,array,array_op,call=>{ for child in source.children(id) { let error = prepareNode(owner,body,child,depth + 1,false); if error != Error.none { return error; } if n.tag == blot_check_core::Tag.suite && (source.node(child).tag == blot_check_core::Tag.return_ || source.node(child).tag == blot_check_core::Tag.break_ || source.types.node(source.typeOf(child)).tag == blot_check_types::Tag.never) { break; } } },
        bind=>{ return prepareBindingBody(owner,body,id,depth); },
        pattern_bind=>{ match bodies.get(body,id) { pattern selected=>{ if selected.value.present { for binding in selected.value.value { owner.static_values.insert(binding.binding,binding.value); } return Error.none; } },_=>{}, } let pattern = preparePattern(owner,body,n.a,depth + 1); if pattern != Error.none { return pattern; } let left = prepareNode(owner,body,n.b,depth + 1,false); if left != Error.none { return left; } return prepareNode(owner,body,n.c,depth + 1,false); },
        return_=>{ match bodies.get(body,id) { exit selected=>{ return prepareNode(owner,body,n.a,depth + 1,selected.value.template_result); },_=>{ assert(false); }, } },
        break_=>{ for child in source.breakValues(id) { let error = prepareNode(owner,body,child,depth + 1,false); if error != Error.none { return error; } } },
        loop_=>{ let loop = source.loopInfo(id); let first = prepareNode(owner,body,loop.first,depth + 1,false); if first != Error.none { return first; } let end = prepareNode(owner,body,loop.end,depth + 1,false); if end != Error.none { return end; } let length = owner.planned_loops.items.len; let pushed = owner.planned_loops.push(id); if pushed != Error.none { return pushed; } defer { owner.planned_loops.resize(length); } let pattern = preparePattern(owner,body,loop.pattern,depth + 1); if pattern != Error.none { return pattern; } return prepareNode(owner,body,loop.body,depth + 1,false); },
        request_loop=>{ let request = source.requestLoopInfo(id); let computation = prepareNode(owner,body,request.computation,depth + 1,false); if computation != Error.none { return computation; } for arm in source.requestArms(id) { let callback = prepareNode(owner,body,arm.callback,depth + 1,false); if callback != Error.none { return callback; } if arm.selector != 0 { let selector = prepareNode(owner,body,arm.selector,depth + 1,false); if selector != Error.none { return selector; } } } let length = owner.planned_loops.items.len; let pushed = owner.planned_loops.push(id); if pushed != Error.none { return pushed; } defer { owner.planned_loops.resize(length); } let pattern = preparePattern(owner,body,request.completion_pattern,depth + 1); if pattern != Error.none { return pattern; } return prepareNode(owner,body,request.completion_body,depth + 1,false); },
        match_=>{ for child in source.matchInputs(id) { let error = prepareNode(owner,body,child,depth + 1,false); if error != Error.none { return error; } } for arm in source.matchArms(id) { for row in source.armRows(arm) { for pattern in source.rowPatterns(row) { let error = preparePattern(owner,body,pattern,depth + 1); if error != Error.none { return error; } } } let guard = prepareNode(owner,body,arm.guard,depth + 1,false); if guard != Error.none { return guard; } let value = prepareNode(owner,body,arm.body,depth + 1,false); if value != Error.none { return value; } let shared = prepareConstructorSubject(owner,body,id,arm); if shared != Error.none { return shared; } } },
        update=>{ let metadata = source.updateInfo(id); let root = prepareNode(owner,body,metadata.root,depth + 1,false); if root != Error.none { return root; } for selector in source.updateSelectors(id) { if selector.kind == blot_check_core::UpdateKind.index { let error = prepareNode(owner,body,selector.index,depth + 1,false); if error != Error.none { return error; } } } return prepareNode(owner,body,metadata.value,depth + 1,false); },
        resolver_op=>{ let resolver = prepareNode(owner,body,source.resolverInfo(id).resolver,depth + 1,false); if resolver != Error.none { return resolver; } for child in source.resolverArguments(id) { let error = prepareNode(owner,body,child,depth + 1,false); if error != Error.none { return error; } } },
        if_value,if_stmt=>{ let condition = prepareNode(owner,body,n.a,depth + 1,false); if condition != Error.none { return condition; } let left = prepareNode(owner,body,n.b,depth + 1,template); if left != Error.none { return left; } return prepareNode(owner,body,n.c,depth + 1,template); },
        resource_acquire,scalar,associated,logical,type_same,apply,record_merge,handle,usage_borrow,proof_guard=>{ let first = prepareNode(owner,body,n.a,depth + 1,false); if first != Error.none { return first; } return prepareNode(owner,body,n.b,depth + 1,false); },
        resource_release,usage_share,project,result_associated,computation,effect_scope,usage_read=>{ return prepareNode(owner,body,n.a,depth + 1,false); },
        construct=>{ return prepareNode(owner,body,n.b,depth + 1,false); },
        effect_provider,state_provider=>{ if scopedProvider(owner,n.ty) { let capability = prepareNode(owner,body,n.a,depth + 1,false); if capability != Error.none { return capability; } } let handler = prepareNode(owner,body,n.b,depth + 1,false); if handler != Error.none { return handler; } if n.tag == blot_check_core::Tag.state_provider { return prepareNode(owner,body,n.c,depth + 1,false); } },
        resource_scope=>{ let a = prepareNode(owner,body,n.a,depth + 1,false); if a != Error.none { return a; } let b = prepareNode(owner,body,n.b,depth + 1,false); if b != Error.none { return b; } return prepareNode(owner,body,n.c,depth + 1,false); },
        operation_value=>{ let operation = source.operationValue(id); if operation.capability != 0 { return prepareNode(owner,body,operation.capability,depth + 1,false); } },
        request_decision=>{ let b = prepareNode(owner,body,n.b,depth + 1,false); if b != Error.none { return b; } return prepareNode(owner,body,n.c,depth + 1,false); },_=>{},
    } return Error.none;
}
recursive fn preparePackageBody(owner: Owner&,body: u32,id: u32,depth: i64) -> Error {
    let generator .= owner.generator; let source .= generator.unit(owner.unit_id); let n = source.node(id); let package = prepareNode(owner,body,n.a,depth + 1,false); if package != Error.none { return package; } let opening = source.packageOpening(id); var mappings = MappingBuffer {}; 
    recursive fn cleanup_continuation_40() -> Error {
 let copied = mappings.append(owner.mappings); if copied != Error.none { return copied; }
    for binder,ordinal in source.types.list(opening.binders) { let opened,error = generator.internLayout(blot_backend_layout::Tag.opened,ordinal as u32,0,[]); if error != Error.none { return error; } let appended = mappings.push(Mapping { binder,opened }); if appended != Error.none { return appended; } }
    let bound = blot_backend_dictionary_layout::bind(source,generator.representations.store,mappings,source.typeOf(n.a),n.b,opening.binders,false); if bound != Error.none { if bound == Error.out_of_memory { return bound; } return generator.fail(owner.unit_id,id,blot_backend_core_backend::Code.unresolved_type); }
    let previous = owner.mappings; owner.mappings = mappings.items; 
    recursive fn cleanup_continuation_39() -> Error {
 return prepareNode(owner,body,opening.body,depth + 1,false);

    }
    let cleanup_result_39_0 = cleanup_continuation_39();
     owner.mappings = previous; 
    return cleanup_result_39_0;

    }
    let cleanup_result_40_0 = cleanup_continuation_40();
     mappings.deinit(); 
    return cleanup_result_40_0;
}
recursive fn prepareBindingBody(owner: Owner&,body: u32,id: u32,depth: i64) -> Error {
    let source .= owner.generator.unit(owner.unit_id); let n = source.node(id); let prepared = prepareNode(owner,body,n.b,depth + 1,false); if prepared != Error.none { return prepared; } let computation,error = describeComputation(owner,body,n.b,depth + 1); if error != Error.none { return error; } if computation.present { owner.templates.insert(n.a,computation.value); return Error.none; }
    let value = source.node(n.b); let bodies .= owner.generator.planning.bodies;
    if value.tag == blot_check_core::Tag.closure { match bodies.get(body,n.b) { template plan=>{ if plan.value.static_key.present { owner.locals.insert(n.a,0); return Error.none; } },_=>{ assert(false); }, } }
    if value.tag == blot_check_core::Tag.closure || value.tag == blot_check_core::Tag.primitive_function || value.tag == blot_check_core::Tag.constructor_function {
        var metadata = Template { unit: owner.unit_id,node: n.b }; if value.tag == blot_check_core::Tag.closure { match bodies.get(body,n.b) { template plan=>{ metadata = plan.value.metadata; },_=>{ assert(false); }, } } owner.templates.insert(n.a,metadata);
    } else if value.tag == blot_check_core::Tag.computation && source.node(value.a).tag == blot_check_core::Tag.closure { match bodies.get(body,value.a) { template plan=>{ var metadata = plan.value.metadata; metadata.computation = true; owner.templates.insert(n.a,metadata); },_=>{ assert(false); }, } }
    else if value.tag == blot_check_core::Tag.reference { let metadata .= owner.templates.get(source.reference(n.b).binding); if metadata != null { owner.templates.insert(n.a,metadata); } else { owner.locals.insert(n.a,0); } }
    else { owner.locals.insert(n.a,0); } return Error.none;
}
recursive fn inlineCollectionEdit(owner: Owner&,id: u32,key: Key,depth: i64) -> bool,Error {
    let generator .= owner.generator; let analyzed = blot_backend_collection_edit_call::analyze(generator.units,owner.unit_id,id); if !analyzed.present { return false,Error.none; } let plan = analyzed.value; if key.count != plan.count || plan.target != key.target { return false,Error.none; }
    for ty in key.parameters[..key.count] { if hasErasedType(owner,ty,0) { return false,Error.none; } } if generator.artifacts != null { let read = generator.artifacts.readInlineBody(plan.target); if read != Error.none { return false,read; } if plan.forwarded_target.present { let forwarded = generator.artifacts.readInlineBody(plan.forwarded_target.value); if forwarded != Error.none { return false,forwarded; } } }
    let source .= generator.unit(owner.unit_id); var values: u32[3]; for argument,index in plan.arguments[..plan.count] { let value,error = capture(owner,argument,depth); if error != Error.none { return false,error; } values[index] = value; }
    if plan.success.present {
        let producer .= generator.unit(plan.target.unit); let body .= producer.body(plan.target.binding); assert(body != null); var mappings = MappingBuffer {}; defer { mappings.deinit(); } var rows = RowBuffer {}; defer { rows.deinit(); }
        for parameter,index in producer.bodyParameters(body) { let mapped = generator.mapTypeDepth(plan.target.unit,mappings,rows,parameter.ty,key.parameters[index],body.span,0); if mapped != Error.none { return false,mapped; } }
        let mapped = generator.mapTypeDepth(plan.target.unit,mappings,rows,producer.typeOf(body.root),key.result,body.span,0); if mapped != Error.none { return false,mapped; }
        let context,context_error = inlineContext(owner); if context_error != Error.none { return false,context_error; } let cleanups,cleanup_error = blot_runtime_runtime_cleanup::initPooled(owner.cleanups); if cleanup_error != Error.none { return false,cleanup_error; }
        let owns,owns_error = generator.ownsArrayUpdate(owner.unit_id,id); if owns_error != Error.none { cleanups.deinit(); return false,owns_error; } var owned_edit = blot_support::none<u32>(); if owns { owned_edit = blot_support::some(plan.edit); }
        var emitter = Owner { generator,unit_id: plan.target.unit,function_id: owner.function_id,provider_local: owner.provider_local,mappings: mappings.items,row_mappings: rows.items,cleanups,diagnostic_context: context,labels: owner.labels,owned_edit }; defer { emitter.deinit(); }
        for parameter,index in producer.bodyParameters(body) { if parameter.binding != 0 { emitter.locals.insert(parameter.binding,values[index]); } } let emitted = bodyExpression(emitter,body.root,depth + 1,false); return emitted == Error.none,emitted;
    }
    let result,error = codeLayout(owner,source.typeOf(id),source.span(id)); if error != Error.none { return false,error; } var operands: u32[3]; var machines: blot_backend_runtime_ir::ValueType[3]; for position,index in plan.positions[..plan.count] { operands[index] = values[position]; machines[index] = generator.representations.store.machine(key.parameters[position]); }
    let emitted = arrayLocals(owner,id,plan.op,operands[..plan.count],machines[..plan.count],result,key.parameters[plan.positions[0]]); return emitted == Error.none,emitted;
}
recursive fn inlineSimdCall(owner: Owner&,id: u32,key: Key,depth: i64) -> bool,Error {
    let generator .= owner.generator; let analyzed = blot_backend_simd_call::analyze(generator.units,owner.unit_id,id); if !analyzed.present { return false,Error.none; } let plan = analyzed.value; if key.count != plan.count || plan.target != key.target { return false,Error.none; }
    if generator.artifacts != null { let read = generator.artifacts.readInlineBody(plan.target); if read != Error.none { return false,read; } } var lanes = blot_support::none<u8[4]>();
    if plan.lanes.present { lanes = simdLaneLiterals(owner,plan.arguments[plan.lanes.value],plan.op); if !lanes.present { return false,generator.fail(owner.unit_id,plan.arguments[plan.lanes.value],blot_backend_core_backend::Code.simd_lane_literal); } }
    var values: u32[3]; for argument,index in plan.arguments[..plan.count] { if !plan.lanes.present || plan.lanes.value != index { let local,error = capture(owner,argument,depth); if error != Error.none { return false,error; } values[index] = local; } }
    var operands: u32[3]; var count: i64 = 0; for position,index in plan.vectors[..plan.vector_count] { if plan.pair_parameter && index + 1 == plan.vector_count { var pair: u32[2]; let error = simdPairLocals(owner,values[position],pair); if error != Error.none { return false,error; } operands[count] = pair[0]; operands[count + 1] = pair[1]; count += 2; } else { operands[count] = values[position]; count++; } }
    let source .= generator.unit(owner.unit_id); let result,error = codeLayout(owner,source.typeOf(id),source.span(id)); if error != Error.none { return false,error; } let emitted = simdLocals(owner,plan.op,operands[..count],lanes,result,result); return emitted == Error.none,emitted;
}
recursive fn inlineNamedCall(owner: Owner&,key: Key,arguments: const u32[:],depth: i64) -> bool,Error { if !owner.generator.inline_named { return false,Error.none; } return inlineNamedValues(owner,key,arguments,blot_support::none<const u32[:]>(),depth); }
recursive fn inlineNamedValues(owner: Owner&,key: Key,arguments: const u32[:],captured: blot_support::Option<const u32[:]>,depth: i64) -> bool,Error { return inlineNamedValuesMode(owner,key,arguments,captured,depth,blot_support::none<u32>()); }
fn borrowedRowArgument(owner: const Owner&,id: u32) -> blot_support::Option<RowView> { let source .= owner.generator.unit(owner.unit_id); if source.node(id).tag != blot_check_core::Tag.reference { return blot_support::none<RowView>(); } let reference = source.reference(id); if reference.unit != 0 && reference.unit != owner.unit_id { return blot_support::none<RowView>(); } var index = owner.row_views.items.len; while index != 0 { index--; let view = owner.row_views.items[index]; if view.binding == reference.binding { return blot_support::some(view); } } return blot_support::none<RowView>(); }
fn readsRow(owner: Owner&,source: const blot_check_core::Module&,root: u32,binding: u32,row: u32) -> bool,Error { let nested,error = owner.generator.nestedRow(row); if error != Error.none { return false,error; } if nested.present { return blot_reuse_row_projection_uses::checkNumeric(source,root,binding,owner.generator.representations.store,nested.value),Error.none; } return blot_reuse_row_projection_uses::check(source,root,binding,owner.generator.representations.store,row),Error.none; }
enum InlinePreparation { declined,admitted { emitter: Owner,borrowed_collections: u16 } }
fn prepareNamedInline(owner: Owner&,key: Key,arguments: const u32[:],captured: blot_support::Option<const u32[:]>,small_result: blot_support::Option<u32>,mappings: MappingBuffer&,rows: RowBuffer&) -> InlinePreparation,Error {
    let generator .= owner.generator; if owner.dictionary_owner.present { return InlinePreparation.declined,Error.none; }
    if owner.inline_depth >= 6 || generator.module.functions[owner.function_id].instructions.len > 4096 || key.templates != 0 || key.template_result { return InlinePreparation.declined,Error.none; }
    if captured.present { if captured.value.len != key.count { return InlinePreparation.declined,Error.none; } } else if arguments.len < key.count { return InlinePreparation.declined,Error.none; }
    let source .= generator.unit(key.target.unit); let body .= source.body(key.target.binding); if body == null || !body.is_function || body.parameters.len != key.count { return InlinePreparation.declined,Error.none; }
    let facts,error = generator.planning.facts.get(generator.units,key.target); if error != Error.none { return InlinePreparation.declined,error; } let in_loop = owner.inline_loop || owner.loop_targets.items.len != 0;
    var expose_data = small_result.present || (in_loop && inlineDataType(owner,key.result)) || inlineOpaqueType(owner,key.result); for ty in key.parameters[..key.count] { expose_data = expose_data || inlineOpaqueType(owner,ty); }
    if !captured.present { for ty,index in key.parameters[..key.count] { let argument = arguments[index]; expose_data = expose_data || (generator.representations.store.node(ty).tag == blot_backend_layout::Tag.function && isCallableTemplate(owner,argument)); if index < 16 && (facts.borrowed_collections & ((1 as u16) << index as u32)) != 0 && smallCollectionCandidate(owner,argument) { expose_data = true; } if in_loop { let words,word_error = generator.rowWords(ty); if word_error != Error.none { return InlinePreparation.declined,word_error; } if words != 0 { expose_data = true; } } } }
    var ordinary_limit: u16 = 4; if expose_data { ordinary_limit = 64; } var numeric_limit: u16 = 0;
    if !facts.inline_cost.present || facts.inline_cost.value > ordinary_limit { let budget,budget_error = numericInlineBudget(owner,key.result); if budget_error != Error.none { return InlinePreparation.declined,budget_error; } numeric_limit = budget; for ty in key.parameters[..key.count] { let candidate,candidate_error = numericInlineBudget(owner,ty); if candidate_error != Error.none { return InlinePreparation.declined,candidate_error; } numeric_limit = max(numeric_limit,candidate); } }
    var size = facts.inline_cost; if !size.present && numeric_limit != 0 { size = blot_backend_inline_body::numericCost(source,body.root); } if !size.present || size.value > max(ordinary_limit,numeric_limit) || hasErasedType(owner,key.result,0) { return InlinePreparation.declined,Error.none; } for ty in key.parameters[..key.count] { if hasErasedType(owner,ty,0) { return InlinePreparation.declined,Error.none; } }
    let seeded = generator.seedNamedInstance(key,mappings); if seeded != Error.none { return InlinePreparation.declined,seeded; } let initial,initial_error = generator.functionRoot(key.target.unit,source.binding(key.target.binding).ty,body.span); if initial_error != Error.none { return InlinePreparation.declined,initial_error; } var source_type = initial;
    for ty,index in key.parameters[..key.count] { let arrow = source.types.node(source_type); let mapped = generator.mapTypeDepth(key.target.unit,mappings,rows,arrow.a,ty,body.span,0); if mapped != Error.none { return InlinePreparation.declined,mapped; } let row = generator.mapRow(key.target.unit,mappings,rows,arrow.c,key.effects[index],body.span,true); if row != Error.none { return InlinePreparation.declined,row; } source_type = arrow.b; }
    let mapped = generator.mapTypeDepth(key.target.unit,mappings,rows,source_type,key.result,body.span,0); if mapped != Error.none { return InlinePreparation.declined,mapped; } var full = key.result; var reverse = key.count as i64;
    while reverse != 0 { reverse--; let arrow,arrow_error = generator.internLayoutWithEffects(blot_backend_layout::Tag.function,key.parameters[reverse],full,key.effects[reverse],[]); if arrow_error != Error.none { return InlinePreparation.declined,arrow_error; } full = arrow; }
    let refined = generator.refineMappings(key.target.unit,blot_reuse_refinement_receipt::Root.body { key.target },full,mappings,rows,body.span); if refined != Error.none { return InlinePreparation.declined,refined; } if generator.artifacts != null { let read = generator.artifacts.readInlineBody(key.target); if read != Error.none { return InlinePreparation.declined,read; } }
    let context,context_error = inlineContext(owner); if context_error != Error.none { return InlinePreparation.declined,context_error; } let cleanups,cleanup_error = blot_runtime_runtime_cleanup::initPooled(owner.cleanups); if cleanup_error != Error.none { return InlinePreparation.declined,cleanup_error; }
    var emitter = Owner { generator,unit_id: key.target.unit,function_id: owner.function_id,provider_local: owner.provider_local,mappings: mappings.items,row_mappings: rows.items,cleanups,diagnostic_context: context,labels: owner.labels,inline_depth: owner.inline_depth + 1,inline_loop: in_loop }; if small_result.present { emitter.small_result = SmallResult { body.root,small_result.value }; }
    return InlinePreparation.admitted { emitter,facts.borrowed_collections },Error.none;
}
recursive fn inlineNamedValuesMode(owner: Owner&,key: Key,arguments: const u32[:],captured: blot_support::Option<const u32[:]>,depth: i64,small_result: blot_support::Option<u32>) -> bool,Error {
    let generator .= owner.generator; var mappings = MappingBuffer {}; 
    recursive fn cleanup_continuation_38() -> bool,Error {
 var rows = RowBuffer {}; 
    recursive fn cleanup_continuation_37() -> bool,Error {
 let preparation,error = prepareNamedInline(owner,key,arguments,captured,small_result,mappings,rows); if error != Error.none { return false,error; }
    match preparation { declined=>{ return false,Error.none; },admitted prepared=>{
        var emitter = prepared.emitter; defer { emitter.deinit(); } let source .= generator.unit(key.target.unit); let body .= source.body(key.target.binding); assert(body != null);
        for parameter,index in source.bodyParameters(body) {
            if captured.present { if parameter.binding != 0 { emitter.locals.insert(parameter.binding,captured.value[index]); } continue; } let argument = arguments[index]; let borrowed = borrowedRowArgument(owner,argument);
            if borrowed.present && parameter.binding != 0 && key.parameters[index] == borrowed.value.row { let reads,read_error = readsRow(owner,source,body.root,parameter.binding,borrowed.value.row); if read_error != Error.none { return false,read_error; } if reads { var view = borrowed.value; view.binding = parameter.binding; let appended = emitter.row_views.push(view); if appended != Error.none { return false,appended; } continue; } }
            if index < 16 && (prepared.borrowed_collections & ((1 as u16) << index as u32)) != 0 { let values,value_error = captureSmallCollection(owner,argument,depth); if value_error != Error.none { return false,value_error; } if values.present { if parameter.binding != 0 { emitter.small_values.insert(parameter.binding,values.value); } continue; } }
            if generator.representations.store.node(key.parameters[index]).tag == blot_backend_layout::Tag.function && owner.static_values.table.count == 0 && isCallableTemplate(owner,argument) { let callable,callable_error = callableTemplate(owner,argument); if callable_error != Error.none { return false,callable_error; } assert(callable.present); if parameter.binding != 0 { emitter.templates.insert(parameter.binding,callable.value); } }
            else { let value,value_error = capture(owner,argument,depth); if value_error != Error.none { return false,value_error; } if parameter.binding != 0 { emitter.locals.insert(parameter.binding,value); } }
        }
        var remaining: const u32[:] = []; if !captured.present { remaining = arguments[key.count..]; } let prepared_body,body_error = prepareBody(emitter,body.root,depth + 1,false); if body_error != Error.none { return false,body_error; } defer { generator.planning.bodies.release(prepared_body); }
        emitter.body = blot_support::some(prepared_body); let header = generator.planning.bodies.header(prepared_body); emitter.mappings = header.mappings; emitter.row_mappings = header.rows; emitter.layout_cache = [LayoutEntry {};32];
        if remaining.len != 0 { let saturated,saturated_error = saturatedAssociated(emitter,body.root,owner,remaining,depth); if saturated_error != Error.none || saturated { return saturated,saturated_error; } }
        if remaining.len == 0 && !small_result.present { let opaque,opaque_error = emitOpaqueAdapterBody(emitter,body.root,depth + 1); if opaque_error != Error.none || opaque { return opaque,opaque_error; } }
        let emitted = expression(emitter,body.root,depth + 1); if emitted != Error.none { return false,emitted; } var ty = key.result;
        for argument in remaining {
            let arrow = generator.representations.store.node(ty); let callee,callee_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if callee_error != Error.none { return false,callee_error; } let saved = emit(owner,blot_backend_runtime_ir::OP_local_set,callee); if saved != Error.none { return false,saved; } let value,value_error = capture(owner,argument,depth); if value_error != Error.none { return false,value_error; }
            let a = emit(owner,blot_backend_runtime_ir::OP_local_get,callee); if a != Error.none { return false,a; } let b = emit(owner,blot_backend_runtime_ir::OP_i32_load,blot_runtime_runtime_layout::Closure_environment); if b != Error.none { return false,b; } let c = emit(owner,blot_backend_runtime_ir::OP_local_get,value); if c != Error.none { return false,c; } let d = providerHead(owner); if d != Error.none { return false,d; }
            let e = emit(owner,blot_backend_runtime_ir::OP_local_get,callee); if e != Error.none { return false,e; } let f = emit(owner,blot_backend_runtime_ir::OP_i32_load,blot_runtime_runtime_layout::Closure_function); if f != Error.none { return false,f; } let annotated = generator.module.emit(owner.function_id,blot_backend_runtime_ir::callResult(generator.layoutRole(arrow.b))); if annotated != Error.none { return false,annotated; }
            let signature,signature_error = generator.module.internType([blot_backend_runtime_ir::VT_i32,generator.representations.store.machine(arrow.a),blot_backend_runtime_ir::VT_i32],generator.representations.store.machine(arrow.b)); if signature_error != Error.none { return false,signature_error; } let called = emit(owner,blot_backend_runtime_ir::OP_call_indirect,signature); if called != Error.none { return false,called; } ty = arrow.b;
        } return true,Error.none;
    }, }

    }
    let cleanup_result_37_0,cleanup_result_37_1 = cleanup_continuation_37();
     rows.deinit(); 
    return cleanup_result_37_0,cleanup_result_37_1;

    }
    let cleanup_result_38_0,cleanup_result_38_1 = cleanup_continuation_38();
     mappings.deinit(); 
    return cleanup_result_38_0,cleanup_result_38_1;
}
struct Alias { binding: u32,local: u32 }
recursive fn emitOpaqueAdapterBody(owner: Owner&,root: u32,depth: i64) -> bool,Error {
    if owner.small_result.slot != 0 { return false,Error.none; } let source .= owner.generator.unit(owner.unit_id); if source.node(root).tag != blot_check_core::Tag.block_ { return false,Error.none; } let statements = source.children(root); if statements.len < 2 || statements.len > 9 { return false,Error.none; } let result = source.node(statements[statements.len - 1]); if result.tag != blot_check_core::Tag.return_ || result.b != root { return false,Error.none; }
    var aliases: Alias[8]; var count: i64 = 0;
    for statement in statements[..statements.len - 1] {
        let node = source.node(statement); if node.tag != blot_check_core::Tag.pattern_bind || node.c != 0 || source.node(node.b).tag != blot_check_core::Tag.reference { return false,Error.none; } let reference = source.reference(node.b); if reference.unit != 0 && reference.unit != owner.unit_id { return false,Error.none; }
        let mutable,mutable_error = hasMutableUse(owner,reference.binding); if mutable_error != Error.none { return false,mutable_error; } if mutable { return false,Error.none; }
        var local = blot_support::none<u32>(); { let found .= owner.locals.get(reference.binding); if found != null { local = blot_support::some(found); } } if !local.present { for alias in aliases[..count] { if alias.binding == reference.binding { local = blot_support::some(alias.local); break; } } } if !local.present { return false,Error.none; }
        var pattern_id = node.a; var found_opaque = false; var binding = blot_support::none<u32>();
        for index in 0..32 { let pattern = source.pattern(pattern_id); match pattern.tag {
            constructor=>{ let nominal = source.nominal(source.constructor(pattern.a).nominal); if !nominal.is_opaque || nominal.storage.kind == blot_backend_opaque_storage::Kind.unknown || nominal.affine || nominal.has_usage || pattern.b == 0 { return false,Error.none; } found_opaque = true; pattern_id = pattern.b; },
            bind=>{ binding = blot_support::some(pattern.a); },wildcard=>{ binding = blot_support::some(0 as u32); },_=>{ return false,Error.none; },
        } if binding.present { break; } }
        if !binding.present || !found_opaque { return false,Error.none; } if binding.value == 0 { continue; }
        if binding.value >= source.bindings.len || source.types.node(source.binding(binding.value).ty).tag == blot_check_types::Tag.erased_proof || owner.locals.contains(binding.value) { return false,Error.none; } let mutable_binding,binding_error = hasMutableUse(owner,binding.value); if binding_error != Error.none { return false,binding_error; } if mutable_binding { return false,Error.none; }
        for alias in aliases[..count] { if alias.binding == binding.value { return false,Error.none; } } aliases[count] = Alias { binding.value,local.value }; count++;
    }
    var leaf = result.a; var complete = false;
    for index in 0..32 { let node = source.node(leaf);
        if node.tag == blot_check_core::Tag.project {
            let concrete,error = codeLayout(owner,source.typeOf(node.a),source.span(leaf)); if error != Error.none { return false,error; } let input = owner.generator.representations.store.node(concrete); var projection = blot_support::none<ProjectionPlan>(); match resolvedPlan(owner,leaf) { projection p=>{ projection = p.value; },_=>{ assert(false); }, }
            if input.tag != blot_backend_layout::Tag.record || !projection.present { return false,Error.none; } match projection.value { field p=>{ if p.value.projection.nominal.decl != 0 || p.value.variants.len != 1 { return false,Error.none; } },_=>{ return false,Error.none; }, } leaf = node.a;
        } else if node.tag == blot_check_core::Tag.reference {
            let reference = source.reference(leaf); if reference.unit != 0 && reference.unit != owner.unit_id { return false,Error.none; } var known = owner.locals.contains(reference.binding); for alias in aliases[..count] { known = known || alias.binding == reference.binding; } let mutable,error = hasMutableUse(owner,reference.binding); if error != Error.none { return false,error; } if !known || mutable { return false,Error.none; } complete = true; break;
        } else { return false,Error.none; }
    }
    if !complete { return false,Error.none; } for alias in aliases[..count] { owner.locals.insert(alias.binding,alias.local); } let emitted = expression(owner,result.a,depth + 1); return emitted == Error.none,emitted;
}
fn inlineOpaqueType(owner: const Owner&,ty: u32) -> bool { let generator .= owner.generator; let selected = generator.representations.store.node(ty); if selected.tag != blot_backend_layout::Tag.nominal || selected.a == 0 || selected.a > generator.units.len { return false; } for nominal in generator.unit(selected.a).nominals { if nominal.identity.unit == selected.a && nominal.identity.decl == selected.b { return nominal.is_opaque && nominal.storage.kind != blot_backend_opaque_storage::Kind.unknown; } } return false; }
fn inlineDataType(owner: const Owner&,ty: u32) -> bool { match owner.generator.representations.store.node(ty).tag { record,product,nominal,cursor=>{ return true; },_=>{ return false; }, } }
fn numericInlineBudget(owner: Owner&,ty: u32) -> u16,Error { let tag = owner.generator.representations.store.node(ty).tag; if tag != blot_backend_layout::Tag.record && tag != blot_backend_layout::Tag.product && tag != blot_backend_layout::Tag.nominal { return 0,Error.none; } var remaining: i64 = 128; var words: i64 = 0; let leaves,error = numericLeaves(owner,ty,remaining,words,0); if error != Error.none { return 0,error; } if !leaves || words < 4 { return 0,Error.none; } return min(128,words * 8) as u16,Error.none; }
recursive fn numericLeaves(owner: Owner&,ty: u32,remaining: i64&,words: i64&,depth: i64) -> bool,Error {
    if remaining == 0 || depth >= 16 { return false,Error.none; } remaining--; let generator .= owner.generator; let node = generator.representations.store.node(ty);
    match node.tag {
        unit,boolean,unsigned32,floating32=>{ words++; return words <= 16,Error.none; },
        record,product=>{ var step: i64 = 1; if node.tag == blot_backend_layout::Tag.record { step = 2; } let count = generator.representations.store.children(ty).len / step; for index in 0..count { let child = generator.representations.store.children(ty)[index * step + step - 1]; let admitted,error = numericLeaves(owner,child,remaining,words,depth + 1); if error != Error.none || !admitted { return admitted,error; } } return true,Error.none; },
        nominal=>{ if node.a == 0 || node.a > generator.units.len { return false,Error.none; } let source .= generator.unit(node.a); var tag = blot_support::none<u32>(); for constructor in source.constructors { if remaining == 0 { return false,Error.none; } remaining--; let identity = source.nominal(constructor.nominal).identity; if identity.unit != node.a || identity.decl != node.b { continue; } if tag.present { return false,Error.none; } tag = blot_support::some(constructor.tag); } if !tag.present { return false,Error.none; }
            let payload,error = generator.nominalPayload(((node.a as u64) << 32) | node.b,tag.value,ty); if error != Error.none { if error == Error.out_of_memory { return false,error; } return false,Error.none; } return numericLeaves(owner,payload,remaining,words,depth + 1);
        },_=>{ return false,Error.none; },
    }
}
recursive fn saturatedAssociated(owner: Owner&,id: u32,caller: Owner&,extra: const u32[:],depth: i64) -> bool,Error {
    let generator .= owner.generator; let source .= generator.unit(owner.unit_id); let node = source.node(id); if node.tag != blot_check_core::Tag.associated || node.op != blot_check_core::Op.none || extra.len + 2 > max_parameters { return false,Error.none; }
    var selected = blot_support::none<Key>(); match resolvedPlan(owner,id) { dispatch dispatch=>{ match dispatch.value { selected plan=>{ selected = blot_support::some(plan.key); },_=>{}, } },_=>{ assert(false); }, } if !selected.present { return false,Error.none; } var key = selected.value; var result_type = key.result;
    let body .= generator.unit(key.target.unit).body(key.target.binding); if body == null || !body.is_function || body.parameters.len != extra.len + 2 { return false,Error.none; }
    for argument,index in extra { let arrow = generator.representations.store.node(result_type); if arrow.tag != blot_backend_layout::Tag.function { return false,Error.none; } key.parameters[index + 2] = arrow.a; key.effects[index + 2] = arrow.c; result_type = arrow.b; } key.count = (extra.len + 2) as u8; key.result = result_type;
    var values: u32[16]; let first,first_error = capture(owner,node.a,depth); if first_error != Error.none { return false,first_error; } values[0] = first; let second,second_error = capture(owner,node.b,depth); if second_error != Error.none { return false,second_error; } values[1] = second; for argument,index in extra { let value,error = capture(caller,argument,depth); if error != Error.none { return false,error; } values[index + 2] = value; }
    let inlined,error = inlineNamedValues(owner,key,[],blot_support::some<const u32[:]>(values[..key.count]),depth); if error != Error.none { return false,error; }
    if !inlined { let function,function_error = generator.function(key); if function_error != Error.none { return false,function_error; } for value in values[..key.count] { let loaded = emit(owner,blot_backend_runtime_ir::OP_local_get,value); if loaded != Error.none { return false,loaded; } } let provider = providerHead(owner); if provider != Error.none { return false,provider; } let called = emit(owner,blot_backend_runtime_ir::OP_call,function); if called != Error.none { return false,called; } } return true,Error.none;
}
recursive fn evaluatedCaptureSupported(owner: const Owner&,value: u32,remaining: i64&,depth: i64) -> bool { if remaining == 0 || depth >= 128 { return false; } remaining--; let evaluator .= owner.generator.evaluator; if evaluator.valueInfo(value).kind == blot_eval_core_eval::ValueKind.closure && evaluator.closureInfo(value).origin == blot_eval_core_eval::ClosureOrigin.constructor { return false; } for child in evaluator.valueChildren(value) { if !evaluatedCaptureSupported(owner,child,remaining,depth + 1) { return false; } } return true; }
fn prepareEvaluatedNamed(owner: Owner&,id: u32) -> blot_support::Option<EvaluatedNamed>,Error { let previous = owner.generator.diagnostic; let plan,error = prepareEvaluatedNamedInner(owner,id); if error == Error.declined { owner.generator.diagnostic = previous; return blot_support::none<EvaluatedNamed>(),Error.none; } return plan,error; }
fn prepareEvaluatedNamedInner(owner: Owner&,id: u32) -> blot_support::Option<EvaluatedNamed>,Error {
    let generator .= owner.generator; if !generator.inline_named || owner.dictionary_owner.present || owner.factory_template { return blot_support::none<EvaluatedNamed>(),Error.none; } let source .= generator.unit(owner.unit_id); var arguments: u32[16]; var count: i64 = 0; var selected: u32 = 0; var value: u32 = 0;
    if source.node(id).tag == blot_check_core::Tag.call {
        let call = source.call(id); if call.arguments.len == 0 || call.arguments.len > max_parameters { return blot_support::none<EvaluatedNamed>(),Error.none; } let target,error = generator.normalize(owner.unit_id,call.target); if error != Error.none { return blot_support::none<EvaluatedNamed>(),error; } let definition .= generator.unit(target.unit).body(target.binding); if definition == null || definition.runtime || definition.is_function { return blot_support::none<EvaluatedNamed>(),Error.none; }
        let evaluated,evaluation_error = generator.evaluator.richValue(target); if evaluation_error != Error.none { if evaluation_error == Error.out_of_memory { return blot_support::none<EvaluatedNamed>(),evaluation_error; } return blot_support::none<EvaluatedNamed>(),generator.evaluationFailure(); } value = evaluated;
        if generator.artifacts != null { let read = generator.artifacts.readStaticValue(target,value); if read != Error.none { return blot_support::none<EvaluatedNamed>(),read; } } count = call.arguments.len; for argument,index in call.arguments { arguments[index] = argument; }
        let concrete,concrete_error = codeLayout(owner,call.callee_type,source.span(id)); if concrete_error != Error.none { return blot_support::none<EvaluatedNamed>(),concrete_error; } selected = concrete;
    } else {
        var root = id; while source.node(root).tag == blot_check_core::Tag.apply { if count == 16 { return blot_support::none<EvaluatedNamed>(),Error.none; } arguments[count] = source.node(root).b; count++; root = source.node(root).a; } if count == 0 { return blot_support::none<EvaluatedNamed>(),Error.none; } reverse(arguments[..count]);
        let reference,error = staticReference(owner,root); if error != Error.none || !reference.present { return blot_support::none<EvaluatedNamed>(),error; } value = reference.value; let concrete,concrete_error = codeLayout(owner,source.typeOf(root),source.span(id)); if concrete_error != Error.none { return blot_support::none<EvaluatedNamed>(),concrete_error; } selected = concrete;
    }
    if generator.evaluator.valueInfo(value).kind != blot_eval_core_eval::ValueKind.closure { return blot_support::none<EvaluatedNamed>(),Error.none; } let header = generator.evaluator.closureInfo(value); if header.origin != blot_eval_core_eval::ClosureOrigin.named || header.staged != 0 { return blot_support::none<EvaluatedNamed>(),Error.none; }
    let producer .= generator.unit(header.unit); let definition .= producer.body(header.identity); if definition == null || !definition.is_function || definition.parameters.len > 16 || header.applied + count != definition.parameters.len || !blot_backend_inline_body::cost(producer,definition.root).present { return blot_support::none<EvaluatedNamed>(),Error.none; }
    let capture_count = header.applied as i64; if generator.evaluator.valueInfo(value).len != capture_count { return blot_support::none<EvaluatedNamed>(),Error.none; } var captured: u32[16]; for actual,index in generator.evaluator.valueChildren(value) { captured[index] = actual; } var capture_budget: i64 = 65536; for actual in captured[..capture_count] { if !evaluatedCaptureSupported(owner,actual,capture_budget,0) { return blot_support::none<EvaluatedNamed>(),Error.none; } }
    var mappings = MappingBuffer {}; 
    recursive fn cleanup_continuation_36() -> blot_support::Option<EvaluatedNamed>,Error {
 var rows = RowBuffer {}; 
    recursive fn cleanup_continuation_35() -> blot_support::Option<EvaluatedNamed>,Error {

    for mapping in generator.evaluator.storage.type_mappings[header.mappings.start..header.mappings.start + header.mappings.len] { let concrete,error = generator.representations.fromEvidence(generator.evaluator.evidenceStore(),mapping.evidence); if error != Error.none { if error == Error.out_of_memory { return blot_support::none<EvaluatedNamed>(),error; } return blot_support::none<EvaluatedNamed>(),generator.fail(owner.unit_id,id,blot_backend_core_backend::Code.unresolved_type); } let mapped = generator.mapType(header.unit,mappings,mapping.variable,concrete,definition.span); if mapped != Error.none { return blot_support::none<EvaluatedNamed>(),mapped; } }
    let loaded = generator.loadSemanticRows(generator.evaluator.storage.row_mappings[header.row_mappings.start..header.row_mappings.start + header.row_mappings.len],rows); if loaded != Error.none { return blot_support::none<EvaluatedNamed>(),loaded; } let initial,initial_error = generator.functionRoot(header.unit,producer.binding(header.identity).ty,definition.span); if initial_error != Error.none { return blot_support::none<EvaluatedNamed>(),initial_error; } var source_type = initial;
    for parameter,index in producer.bodyParameters(definition)[..capture_count] { let concrete,error = generator.captureTypeLayout(header.unit,parameter.ty,parameter.span,captured[index],mappings,rows); if error != Error.none { return blot_support::none<EvaluatedNamed>(),error; } let arrow = producer.types.node(source_type); if arrow.tag != blot_check_types::Tag.function { return blot_support::none<EvaluatedNamed>(),generator.fail(owner.unit_id,id,blot_backend_core_backend::Code.unresolved_type); } let mapped = generator.mapType(header.unit,mappings,arrow.a,concrete,definition.span); if mapped != Error.none { return blot_support::none<EvaluatedNamed>(),mapped; } source_type = arrow.b; }
    let mapped = generator.mapTypeDepth(header.unit,mappings,rows,source_type,selected,definition.span,0); if mapped != Error.none { return blot_support::none<EvaluatedNamed>(),mapped; } let expected,expected_error = generator.codeLayoutWithRows(header.unit,producer.binding(header.identity).ty,mappings.items,rows.items,definition.span); if expected_error != Error.none { return blot_support::none<EvaluatedNamed>(),expected_error; }
    let refined = generator.refineMappings(header.unit,blot_reuse_refinement_receipt::Root.body { blot_check_core::BindingRef { header.unit,header.identity } },expected,mappings,rows,definition.span); if refined != Error.none { return blot_support::none<EvaluatedNamed>(),refined; } let refined_type,refined_error = generator.codeLayoutWithRows(header.unit,producer.binding(header.identity).ty,mappings.items,rows.items,definition.span); if refined_error != Error.none { return blot_support::none<EvaluatedNamed>(),refined_error; } var full = refined_type;
    var key = Key { target: blot_check_core::BindingRef { header.unit,header.identity },count: definition.parameters.len as u8,result: 0 };
    for index in 0..key.count { let arrow = generator.representations.store.node(full); if arrow.tag != blot_backend_layout::Tag.function || hasErasedType(owner,arrow.a,0) || generator.representations.store.node(arrow.a).tag == blot_backend_layout::Tag.universal { return blot_support::none<EvaluatedNamed>(),Error.none; } key.parameters[index] = arrow.a; key.effects[index] = arrow.c;
        if index >= capture_count { let actual,error = codeLayout(owner,source.typeOf(arguments[index - capture_count]),source.span(id)); if error != Error.none { return blot_support::none<EvaluatedNamed>(),error; } if actual != arrow.a { return blot_support::none<EvaluatedNamed>(),Error.none; } } full = arrow.b;
    }
    if hasErasedType(owner,full,0) { return blot_support::none<EvaluatedNamed>(),Error.none; } key.result = full; return blot_support::some(EvaluatedNamed { key,arguments,count,captured,capture_count }),Error.none;

    }
    let cleanup_result_35_0,cleanup_result_35_1 = cleanup_continuation_35();
     rows.deinit(); 
    return cleanup_result_35_0,cleanup_result_35_1;

    }
    let cleanup_result_36_0,cleanup_result_36_1 = cleanup_continuation_36();
     mappings.deinit(); 
    return cleanup_result_36_0,cleanup_result_36_1;
}
fn reverse(values: u32[:]) { var first: i64 = 0; var last = values.len; while first < last { last--; if first >= last { break; } let previous = values[first]; values[first] = values[last]; values[last] = previous; first++; } }
recursive fn emitEvaluatedNamed(owner: Owner&,plan: const EvaluatedNamed&,depth: i64) -> bool,Error {
    let generator .= owner.generator; if owner.inline_depth >= 6 || generator.instance_depth >= 256 || generator.module.functions[owner.function_id].instructions.len > 4096 { return false,Error.none; } let source .= generator.unit(plan.key.target.unit); let definition .= source.body(plan.key.target.binding); assert(definition != null);
    var mappings = MappingBuffer {}; 
    recursive fn cleanup_continuation_34() -> bool,Error {
 var rows = RowBuffer {}; 
    recursive fn cleanup_continuation_33() -> bool,Error {
 let service,service_error = generator.specializer(); if service_error != Error.none { return false,service_error; } let resolved,error = service.named(plan.key,[],mappings,rows); if error != Error.none { return false,generator.specializationFailure(service,error); }
    if generator.artifacts != null { if !generator.artifacts.hasStaticValues() { generator.artifacts.requireFreshCode(); } let read = generator.artifacts.readInlineBody(plan.key.target); if read != Error.none { return false,read; } }
    generator.instance_depth++; 
    recursive fn cleanup_continuation_32() -> bool,Error {
 let context,context_error = inlineContext(owner); if context_error != Error.none { return false,context_error; } let cleanups,cleanup_error = blot_runtime_runtime_cleanup::initPooled(owner.cleanups); if cleanup_error != Error.none { return false,cleanup_error; }
    var emitter = Owner { generator,unit_id: plan.key.target.unit,function_id: owner.function_id,provider_local: owner.provider_local,mappings: mappings.items,row_mappings: rows.items,cleanups,diagnostic_context: context,labels: owner.labels,inline_depth: owner.inline_depth + 1,inline_loop: owner.inline_loop || owner.loop_targets.items.len != 0 }; 
    recursive fn cleanup_continuation_31() -> bool,Error {

    let parameters = source.bodyParameters(definition); for parameter,index in parameters[..plan.capture_count] { if parameter.binding != 0 { emitter.static_values.insert(parameter.binding,plan.captured[index]); } } for parameter,index in parameters[plan.capture_count..] { let local,local_error = capture(owner,plan.arguments[index],depth); if local_error != Error.none { return false,local_error; } if parameter.binding != 0 { emitter.locals.insert(parameter.binding,local); } }
    let emitted = bodyExpression(emitter,resolved.root,depth + 1,false); return emitted == Error.none,emitted;

    }
    let cleanup_result_31_0,cleanup_result_31_1 = cleanup_continuation_31();
     emitter.deinit(); 
    return cleanup_result_31_0,cleanup_result_31_1;

    }
    let cleanup_result_32_0,cleanup_result_32_1 = cleanup_continuation_32();
     generator.instance_depth--; 
    return cleanup_result_32_0,cleanup_result_32_1;

    }
    let cleanup_result_33_0,cleanup_result_33_1 = cleanup_continuation_33();
     rows.deinit(); 
    return cleanup_result_33_0,cleanup_result_33_1;

    }
    let cleanup_result_34_0,cleanup_result_34_1 = cleanup_continuation_34();
     mappings.deinit(); 
    return cleanup_result_34_0,cleanup_result_34_1;
}
fn staticReference(owner: Owner&,id: u32) -> blot_support::Option<u32>,Error {
    let generator .= owner.generator; let source .= generator.unit(owner.unit_id); if source.node(id).tag != blot_check_core::Tag.reference { return blot_support::none<u32>(),Error.none; } let reference = source.reference(id);
    if reference.unit == 0 || reference.unit == owner.unit_id { let known .= owner.static_values.get(reference.binding); if known != null { return blot_support::some(known),Error.none; } if owner.locals.contains(reference.binding) || owner.templates.contains(reference.binding) { return blot_support::none<u32>(),Error.none; } let kind = source.binding(reference.binding).kind; if kind != blot_check_core::BindingKind.global && kind != blot_check_core::BindingKind.external { return blot_support::none<u32>(),Error.none; } }
    let target,error = generator.normalize(owner.unit_id,reference); if error != Error.none { return blot_support::none<u32>(),error; } let body .= generator.unit(target.unit).body(target.binding); if body == null || body.runtime || body.is_function { return blot_support::none<u32>(),Error.none; } let value,value_error = generator.evaluator.richValue(target); if value_error != Error.none { if value_error == Error.out_of_memory { return blot_support::none<u32>(),value_error; } return blot_support::none<u32>(),generator.evaluationFailure(); } if generator.artifacts != null { let read = generator.artifacts.readStaticValue(target,value); if read != Error.none { return blot_support::none<u32>(),read; } } return blot_support::some(value),Error.none;
}
recursive fn inlineStaticCall(owner: Owner&,key: Key,arguments: const u32[:],depth: i64) -> bool,Error {
    let generator .= owner.generator; if arguments.len > key.count { return false,Error.none; } let source .= generator.unit(key.target.unit); let body .= source.body(key.target.binding); if body == null || !body.is_function || body.parameters.len != key.count { return false,Error.none; }
    var values: blot_support::Option<u32>[16] = [blot_support::none<u32>();16]; var retained = false; for argument,index in arguments { if !hasErasedType(owner,key.parameters[index],0) { continue; } let value,error = staticReference(owner,argument); if error != Error.none { return false,error; } values[index] = value; retained = retained || value.present; } if !retained { return false,Error.none; }
    if generator.artifacts != null { let read = generator.artifacts.readInlineBody(key.target); if read != Error.none { return false,read; } if !generator.artifacts.hasStaticValues() { generator.artifacts.requireFreshCode(); } }
    if generator.instance_depth >= 256 { return false,generator.decline(key.target.unit,body.span,blot_backend_core_backend::Code.complexity); } generator.instance_depth++; 
    recursive fn cleanup_continuation_30() -> bool,Error {

    var mappings = MappingBuffer {}; 
    recursive fn cleanup_continuation_29() -> bool,Error {
 var rows = RowBuffer {}; 
    recursive fn cleanup_continuation_28() -> bool,Error {
 var full = key.result; var index = key.count as i64;
    while index != 0 { index--; let arrow,error = generator.internLayoutWithEffects(blot_backend_layout::Tag.function,key.parameters[index],full,key.effects[index],[]); if error != Error.none { return false,error; } full = arrow; }
    let seeded = generator.seedNamedInstance(key,mappings); if seeded != Error.none { return false,seeded; } let initial,initial_error = generator.functionRoot(key.target.unit,source.binding(key.target.binding).ty,body.span); if initial_error != Error.none { return false,initial_error; } var source_type = initial;
    for parameter,index in key.parameters[..key.count] { let arrow = source.types.node(source_type); if arrow.tag != blot_check_types::Tag.function { return false,generator.decline(key.target.unit,body.span,blot_backend_core_backend::Code.unresolved_type); } let mapped = generator.mapTypeDepth(key.target.unit,mappings,rows,arrow.a,parameter,body.span,0); if mapped != Error.none { return false,mapped; } let row = generator.mapRow(key.target.unit,mappings,rows,arrow.c,key.effects[index],body.span,true); if row != Error.none { return false,row; } source_type = arrow.b; }
    let mapped = generator.mapTypeDepth(key.target.unit,mappings,rows,source_type,key.result,body.span,0); if mapped != Error.none { return false,mapped; } let refined = generator.refineMappings(key.target.unit,blot_reuse_refinement_receipt::Root.body { key.target },full,mappings,rows,body.span); if refined != Error.none { return false,refined; }
    let context,context_error = inlineContext(owner); if context_error != Error.none { return false,context_error; } let cleanups,cleanup_error = blot_runtime_runtime_cleanup::initPooled(owner.cleanups); if cleanup_error != Error.none { return false,cleanup_error; } var emitter = Owner { generator,unit_id: key.target.unit,function_id: owner.function_id,provider_local: owner.provider_local,mappings: mappings.items,row_mappings: rows.items,cleanups,diagnostic_context: context,labels: owner.labels }; 
    recursive fn cleanup_continuation_27() -> bool,Error {

    for argument,index in arguments { let parameter = source.bodyParameters(body)[index]; if values[index].present { if parameter.binding != 0 { emitter.static_values.insert(parameter.binding,values[index].value); } } else { let local,error = capture(owner,argument,depth); if error != Error.none { return false,error; } if parameter.binding != 0 { emitter.locals.insert(parameter.binding,local); } } }
    let emitted = finishStaticCall(emitter,key,arguments.len,depth); return emitted == Error.none,emitted;

    }
    let cleanup_result_27_0,cleanup_result_27_1 = cleanup_continuation_27();
     emitter.deinit(); 
    return cleanup_result_27_0,cleanup_result_27_1;

    }
    let cleanup_result_28_0,cleanup_result_28_1 = cleanup_continuation_28();
     rows.deinit(); 
    return cleanup_result_28_0,cleanup_result_28_1;

    }
    let cleanup_result_29_0,cleanup_result_29_1 = cleanup_continuation_29();
     mappings.deinit(); 
    return cleanup_result_29_0,cleanup_result_29_1;

    }
    let cleanup_result_30_0,cleanup_result_30_1 = cleanup_continuation_30();
     generator.instance_depth--; 
    return cleanup_result_30_0,cleanup_result_30_1;
}
recursive fn finishStaticCall(owner: Owner&,key: Key,supplied: i64,depth: i64) -> Error {
    let generator .= owner.generator; let source .= generator.unit(key.target.unit); let body .= source.body(key.target.binding); assert(body != null);
    if supplied == key.count { let emitted = bodyExpression(owner,body.root,depth + 1,false); if emitted != Error.none { return emitted; } if source.types.node(source.typeOf(body.root)).tag == blot_check_types::Tag.never { return emit(owner,blot_backend_runtime_ir::OP_unreachable_,0); } return Error.none; }
    var machine = blot_backend_runtime_ir::VT_i32; var role = blot_backend_runtime_ir::ROLE_reference; if supplied + 1 == key.count { machine = generator.representations.store.machine(key.result); role = generator.layoutRole(key.result); }
    let function,error = generator.module.addTypedFunction([blot_backend_runtime_ir::VT_i32,generator.representations.store.machine(key.parameters[supplied]),blot_backend_runtime_ir::VT_i32],machine,role); if error != Error.none { return error; } let described = generator.setParameterRoles(function,generator.closureRoles(key.parameters[supplied]),blot_support::some(2 as u16)); if described != Error.none { return described; }
    generator.static_data.closures.push(function); generator.work.fresh_closures++; let requested = generator.planning.startup_facts.request(function,blot_backend_startup_emission_facts::Kind.named,key.target.unit,key.target.binding,false); if requested != Error.none { return requested; }
    let cleanups,cleanup_error = blot_runtime_runtime_cleanup::initPooled(); if cleanup_error != Error.none { return cleanup_error; } var emitter = Owner { generator,unit_id: key.target.unit,function_id: function,provider_local: blot_support::some(2 as u32),mappings: owner.mappings,row_mappings: owner.row_mappings,cleanups }; 
    recursive fn cleanup_continuation_26() -> Error {

    var roles: blot_backend_runtime_ir::Role[16]; for ty,index in key.parameters[..supplied] { roles[index] = generator.layoutRole(ty); } let environment,environment_error = allocate(owner,(supplied * 4) as u32,AllocationRoles { words: roles[..supplied] }); if environment_error != Error.none { return environment_error; } let parameters = source.bodyParameters(body);
    for parameter,index in parameters[..supplied] {
        let value .= owner.static_values.get(parameter.binding); let target = emit(owner,blot_backend_runtime_ir::OP_local_get,environment); if target != Error.none { return target; }
        if value != null || parameter.binding == 0 { let zero = emit(owner,blot_backend_runtime_ir::OP_i32_const,0); if zero != Error.none { return zero; } let stored = emit(owner,blot_backend_runtime_ir::OP_i32_store,(index * 4) as u32); if stored != Error.none { return stored; } if value != null { emitter.static_values.insert(parameter.binding,value); } }
        else {
            let local .= owner.locals.get(parameter.binding); assert(local != null); let loaded = emit(owner,blot_backend_runtime_ir::OP_local_get,local); if loaded != Error.none { return loaded; } let machine = generator.representations.store.machine(key.parameters[index]); var store = blot_backend_runtime_ir::OP_i32_store; var load = blot_backend_runtime_ir::OP_i32_load; if machine == blot_backend_runtime_ir::VT_f32 { store = blot_backend_runtime_ir::OP_f32_store; load = blot_backend_runtime_ir::OP_f32_load; }
            let stored = emit(owner,store,(index * 4) as u32); if stored != Error.none { return stored; } let captured,captured_error = temporary(emitter,machine); if captured_error != Error.none { return captured_error; }
            let base = emit(emitter,blot_backend_runtime_ir::OP_local_get,0); if base != Error.none { return base; } let restored = emit(emitter,load,(index * 4) as u32); if restored != Error.none { return restored; } let saved = emit(emitter,blot_backend_runtime_ir::OP_local_set,captured); if saved != Error.none { return saved; } emitter.locals.insert(parameter.binding,captured);
        }
    }
    if parameters[supplied].binding != 0 { emitter.locals.insert(parameters[supplied].binding,1); } let caller = generator.planning.startup_facts.active; generator.planning.startup_facts.active = function; 
    recursive fn cleanup_continuation_25() -> Error {

    let remaining = finishStaticCall(emitter,key,supplied + 1,depth); if remaining != Error.none { return remaining; } generator.planning.startup_facts.complete(function); generator.planning.startup_facts.active = caller; return descriptor(owner,function,environment);

    }
    let cleanup_result_25_0 = cleanup_continuation_25();
     generator.planning.startup_facts.active = caller; 
    return cleanup_result_25_0;

    }
    let cleanup_result_26_0 = cleanup_continuation_26();
     emitter.deinit(); 
    return cleanup_result_26_0;
}
fn preparePartialStaticCall(owner: Owner&,id: u32) -> blot_support::Option<SourceCall>,Error {
    assert(owner.preparing); let generator .= owner.generator; let source .= generator.unit(owner.unit_id); var arguments: u32[16]; var count: i64 = 0; var root = id;
    while source.node(root).tag == blot_check_core::Tag.apply { if count == 16 { return blot_support::none<SourceCall>(),Error.none; } let node = source.node(root); arguments[count] = node.b; count++; root = node.a; } if source.node(root).tag != blot_check_core::Tag.reference { return blot_support::none<SourceCall>(),Error.none; } let reference = source.reference(root);
    if reference.unit == 0 || reference.unit == owner.unit_id { if owner.locals.contains(reference.binding) || owner.templates.contains(reference.binding) || owner.static_values.contains(reference.binding) { return blot_support::none<SourceCall>(),Error.none; } let kind = source.binding(reference.binding).kind; if kind != blot_check_core::BindingKind.global && kind != blot_check_core::BindingKind.external { return blot_support::none<SourceCall>(),Error.none; } }
    let target,error = generator.normalize(owner.unit_id,reference); if error != Error.none { return blot_support::none<SourceCall>(),error; } let body .= generator.unit(target.unit).body(target.binding); if body == null || !body.is_function || count >= body.parameters.len { return blot_support::none<SourceCall>(),Error.none; }
    let key,key_error = generator.signature(target,source.typeOf(root),owner.unit_id,owner.mappings,owner.row_mappings,source.span(id),false); if key_error != Error.none { return blot_support::none<SourceCall>(),key_error; } reverse(arguments[..count]); return blot_support::some(SourceCall { key,arguments,count }),Error.none;
}
recursive fn discardAggregateValue(owner: Owner&,id: u32,depth: i64) -> Error {
    if id == 0 { return Error.none; } let generator .= owner.generator; let source .= generator.unit(owner.unit_id); if depth >= 1024 { return generator.fail(owner.unit_id,id,blot_backend_core_backend::Code.complexity); } let node = source.node(id);
    match node.tag {
        product,record,array=>{ for child in source.children(id) { let error = discardAggregateValue(owner,child,depth + 1); if error != Error.none { return error; } } },construct=>{ return discardAggregateValue(owner,node.b,depth + 1); },constant,constructor_function,primitive_function=>{},
        closure=>{ if !generator.discardableClosure(owner.unit_id,node.a) { let emitted = expression(owner,id,depth + 1); if emitted != Error.none { return emitted; } return emit(owner,blot_backend_runtime_ir::OP_drop,0); } },
        reference=>{ let reference = source.reference(id); if (reference.unit == 0 || reference.unit == owner.unit_id) && source.binding(reference.binding).kind != blot_check_core::BindingKind.global && source.binding(reference.binding).kind != blot_check_core::BindingKind.external { if source.binding(reference.binding).scheme.obligations.len != 0 { let emitted = expression(owner,id,depth + 1); if emitted != Error.none { return emitted; } return emit(owner,blot_backend_runtime_ir::OP_drop,0); } return Error.none; }
            var target = blot_check_core::BindingRef {}; match resolvedPlan(owner,id) { reference plan=>{ assert(plan.value.present); target = plan.value.value; },_=>{ assert(false); }, } let body .= generator.unit(target.unit).body(target.binding); if body == null { return generator.fail(owner.unit_id,id,blot_backend_core_backend::Code.unsupported); }
            if body.runtime && !body.is_function { let global,error = generator.planning.runtimeGlobal(generator,target); return error; }
            var emit_value = false; if !body.is_function { let value,error = generator.evaluator.richValue(target); if error != Error.none { if error == Error.out_of_memory { return error; } return generator.evaluationFailure(); } emit_value = !generator.discardableValue(value,0); } else { emit_value = body.scheme.obligations.len != 0; }
            if emit_value { let emitted = expression(owner,id,depth + 1); if emitted != Error.none { return emitted; } return emit(owner,blot_backend_runtime_ir::OP_drop,0); }
        },_=>{ let emitted = expression(owner,id,depth + 1); if emitted != Error.none { return emitted; } return emit(owner,blot_backend_runtime_ir::OP_drop,0); },
    } return Error.none;
}
recursive fn recordMerge(owner: Owner&,id: u32,depth: i64) -> Error {
    let generator .= owner.generator; let source .= generator.unit(owner.unit_id); let node = source.node(id); let left_type,left_error = codeLayout(owner,source.typeOf(node.a),source.span(id)); if left_error != Error.none { return left_error; } let right_type,right_error = codeLayout(owner,source.typeOf(node.b),source.span(id)); if right_error != Error.none { return right_error; } let result_type,result_error = codeLayout(owner,node.ty,source.span(id)); if result_error != Error.none { return result_error; }
    if generator.representations.store.node(left_type).tag != blot_backend_layout::Tag.record || generator.representations.store.node(right_type).tag != blot_backend_layout::Tag.record || generator.representations.store.node(result_type).tag != blot_backend_layout::Tag.record { return generator.fail(owner.unit_id,id,blot_backend_core_backend::Code.unresolved_type); }
    let left,capture_error = capture(owner,node.a,depth); if capture_error != Error.none { return capture_error; } let right,right_capture_error = capture(owner,node.b,depth); if right_capture_error != Error.none { return right_capture_error; }
    let left_fields = generator.representations.store.children(left_type); let right_fields = generator.representations.store.children(right_type); let fields = generator.representations.store.children(result_type);
    if left_fields.len == 0 || right_fields.len == 0 { var selected = left; if left_fields.len == 0 { selected = right; } return emit(owner,blot_backend_runtime_ir::OP_local_get,selected); } if fields.len / 2 > 4294967295 / 4 { return generator.fail(owner.unit_id,id,blot_backend_core_backend::Code.complexity); }
    var roles = RoleBuffer {}; 
    recursive fn cleanup_continuation_24() -> Error {
 for index in 0..fields.len / 2 { let appended = roles.push(generator.layoutRole(fields[index * 2 + 1])); if appended != Error.none { return appended; } } let result,error = allocate(owner,(fields.len * 2) as u32,AllocationRoles { words: roles.items }); if error != Error.none { return error; }
    var a: i64 = 0; var b: i64 = 0; var out: i64 = 0;
    while out < fields.len { let from_left = a < left_fields.len && left_fields[a] == fields[out]; let from_right = b < right_fields.len && right_fields[b] == fields[out]; if !from_left && !from_right { return generator.fail(owner.unit_id,id,blot_backend_core_backend::Code.unresolved_type); } var selected = left; var offset = a; if from_right { selected = right; offset = b; }
        let target = emit(owner,blot_backend_runtime_ir::OP_local_get,result); if target != Error.none { return target; } let input = emit(owner,blot_backend_runtime_ir::OP_local_get,selected); if input != Error.none { return input; } let loaded = emit(owner,blot_backend_runtime_ir::OP_i32_load,(offset * 2) as u32); if loaded != Error.none { return loaded; } let stored = emit(owner,blot_backend_runtime_ir::OP_i32_store,(out * 2) as u32); if stored != Error.none { return stored; }
        if from_left { a += 2; } if from_right { b += 2; } out += 2;
    } return emit(owner,blot_backend_runtime_ir::OP_local_get,result);

    }
    let cleanup_result_24_0 = cleanup_continuation_24();
     roles.deinit(); 
    return cleanup_result_24_0;
}
fn physicalOrder(owner: Owner&,record: blot_check_types::Node,out: WordBuffer&) -> Error {
    let generator .= owner.generator; let source .= generator.unit(owner.unit_id); assert(record.tag == blot_check_types::Tag.record); if record.b < 2 { return Error.none; } var ordered = true;
    for index in 1..record.b { if !blot_check_record_order::less(generator.representations.store.record_names,source.types.recordField(record,index - 1).name,source.types.recordField(record,index).name) { ordered = false; break; } } if ordered { return Error.none; }
    var sorted = WordBuffer {}; 
    recursive fn cleanup_continuation_23() -> Error {
 for index in 0..record.b { let appended = sorted.push(index as u32); if appended != Error.none { return appended; } }
    for index in 1..sorted.items.len { let original = sorted.items[index]; var position = index; while position > 0 && blot_check_record_order::less(generator.representations.store.record_names,source.types.recordField(record,original).name,source.types.recordField(record,sorted.items[position - 1]).name) { sorted.items[position] = sorted.items[position - 1]; position--; } sorted.items[position] = original; }
    for index in 0..record.b { let appended = out.push(0); if appended != Error.none { return appended; } } for original,index in sorted.items { out.items[original] = index as u32; } return Error.none;

    }
    let cleanup_result_23_0 = cleanup_continuation_23();
     sorted.deinit(); 
    return cleanup_result_23_0;
}
recursive fn aggregate(owner: Owner&,id: u32,depth: i64) -> Error {
    let generator .= owner.generator; let source .= generator.unit(owner.unit_id); let children = source.children(id); if children.len == 0 { return emit(owner,blot_backend_runtime_ir::OP_i32_const,0); } if children.len > 4294967295 / 4 { return generator.fail(owner.unit_id,id,blot_backend_core_backend::Code.complexity); }
    var locals = WordBuffer {}; 
    recursive fn cleanup_continuation_22() -> Error {
 for child in children { let local,error = capture(owner,child,depth); if error != Error.none { return error; } let appended = locals.push(local); if appended != Error.none { return appended; } if source.types.node(source.typeOf(child)).tag == blot_check_types::Tag.never { return Error.none; } }
    let record = source.node(id).tag == blot_check_core::Tag.record; var destinations: const u32[:] = []; if record { destinations = source.recordDestinations(id); } var aggregate_type = source.typeOf(id); if source.types.node(aggregate_type).tag == blot_check_types::Tag.usage { aggregate_type = source.types.node(aggregate_type).a; }
    var physical = WordBuffer {}; 
    recursive fn cleanup_continuation_21() -> Error {
 if record { let order = physicalOrder(owner,source.types.node(aggregate_type),physical); if order != Error.none { return order; } } var roles = RoleBuffer {}; 
    recursive fn cleanup_continuation_20() -> Error {
 for child in children { let appended = roles.push(blot_backend_runtime_ir::ROLE_unknown); if appended != Error.none { return appended; } }
    for child,index in children { var declared = index as u32; if record { declared = destinations[index]; } var slot = declared; if physical.items.len != 0 { slot = physical.items[declared]; } let concrete,error = codeLayout(owner,source.typeOf(child),source.span(child)); if error != Error.none { return error; } roles.items[slot] = generator.layoutRole(concrete); }
    let address,error = allocate(owner,(children.len * 4) as u32,AllocationRoles { words: roles.items }); if error != Error.none { return error; } if containsValue(roles.items,blot_backend_runtime_ir::ROLE_reference) { let concrete,concrete_error = codeLayout(owner,source.typeOf(id),source.span(id)); if concrete_error != Error.none { return concrete_error; } let acyclic = markAcyclic(owner,address,concrete); if acyclic != Error.none { return acyclic; } }
    for child,index in children { var declared = index as u32; if record { declared = destinations[index]; } var slot = declared; if physical.items.len != 0 { slot = physical.items[declared]; } let a = emit(owner,blot_backend_runtime_ir::OP_local_get,address); if a != Error.none { return a; } let b = emit(owner,blot_backend_runtime_ir::OP_local_get,locals.items[index]); if b != Error.none { return b; } let scalar_type,scalar_error = scalar(owner,child); if scalar_error != Error.none { return scalar_error; } var store = blot_backend_runtime_ir::OP_i32_store; if scalar_type == blot_backend_runtime_ir::SC_f32 { store = blot_backend_runtime_ir::OP_f32_store; } let stored = emit(owner,store,slot * 4); if stored != Error.none { return stored; } }
    return emit(owner,blot_backend_runtime_ir::OP_local_get,address);

    }
    let cleanup_result_20_0 = cleanup_continuation_20();
     roles.deinit(); 
    return cleanup_result_20_0;

    }
    let cleanup_result_21_0 = cleanup_continuation_21();
     physical.deinit(); 
    return cleanup_result_21_0;

    }
    let cleanup_result_22_0 = cleanup_continuation_22();
     locals.deinit(); 
    return cleanup_result_22_0;
}
fn recordRepresentation(owner: Owner&,record: blot_check_types::Node,value: u32,into_record: bool) -> u32,Error {
    let generator .= owner.generator; var order = WordBuffer {}; 
    recursive fn cleanup_continuation_19() -> u32,Error {
 let selected = physicalOrder(owner,record,order); if selected != Error.none { return 0,selected; } if order.items.len == 0 { return value,Error.none; } if record.b > 4294967295 / 4 { return 0,generator.decline(owner.unit_id,blot_check_core::Span { 0,0 },blot_backend_core_backend::Code.complexity); }
    var roles = RoleBuffer {}; 
    recursive fn cleanup_continuation_18() -> u32,Error {
 for index in 0..record.b { let appended = roles.push(blot_backend_runtime_ir::ROLE_unknown); if appended != Error.none { return 0,appended; } }
    for physical,declared in order.items { let field = generator.unit(owner.unit_id).types.recordField(record,declared as u32); var target = declared as u32; if into_record { target = physical; } let concrete,error = codeLayout(owner,field.ty,blot_check_core::Span { 0,0 }); if error != Error.none { return 0,error; } roles.items[target] = generator.layoutRole(concrete); }
    let address,error = allocate(owner,record.b * 4,AllocationRoles { words: roles.items }); if error != Error.none { return 0,error; }
    for physical,declared in order.items { var source = physical; var target = declared as u32; if into_record { source = declared as u32; target = physical; } let a = emit(owner,blot_backend_runtime_ir::OP_local_get,address); if a != Error.none { return 0,a; } let b = emit(owner,blot_backend_runtime_ir::OP_local_get,value); if b != Error.none { return 0,b; } let loaded = emit(owner,blot_backend_runtime_ir::OP_i32_load,source * 4); if loaded != Error.none { return 0,loaded; } let stored = emit(owner,blot_backend_runtime_ir::OP_i32_store,target * 4); if stored != Error.none { return 0,stored; } } return address,Error.none;

    }
    let cleanup_result_18_0,cleanup_result_18_1 = cleanup_continuation_18();
     roles.deinit(); 
    return cleanup_result_18_0,cleanup_result_18_1;

    }
    let cleanup_result_19_0,cleanup_result_19_1 = cleanup_continuation_19();
     order.deinit(); 
    return cleanup_result_19_0,cleanup_result_19_1;
}
fn nullaryConstructor(owner: Owner&,tag: u32) -> Error {
    let address,error = owner.generator.module.dataWords([tag,0]); if error != Error.none { return error; } let low = emit(owner,blot_backend_runtime_ir::OP_ownership,blot_backend_runtime_ir::pack(blot_backend_runtime_ir::Ownership { blot_backend_runtime_ir::OWN_words,14,tag & 67108863 })); if low != Error.none { return low; }
    let high = emit(owner,blot_backend_runtime_ir::OP_ownership,blot_backend_runtime_ir::pack(blot_backend_runtime_ir::Ownership { blot_backend_runtime_ir::OWN_words,15,tag >> 26 })); if high != Error.none { return high; }
    var facts: blot_backend_runtime_ir::Instruction[blot_backend_runtime_ir::max_annotations]; let run = blot_backend_runtime_ir::annotations([blot_backend_runtime_ir::ROLE_scalar,blot_backend_runtime_ir::ROLE_reference],blot_backend_runtime_ir::ROLE_unknown,facts);
    for original,index in run { var fact = original; if index + 1 == run.len { var terminator = blot_backend_runtime_ir::ownership(fact.operand); terminator.chunk = 15; fact.operand = blot_backend_runtime_ir::pack(terminator); } let added = owner.generator.module.emit(owner.function_id,fact); if added != Error.none { return added; } }
    return owner.generator.module.emitReference(owner.function_id,blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,address),blot_reuse_artifact_emitter::Role.static_address);
}
recursive fn construct(owner: Owner&,id: u32,depth: i64) -> Error {
    let generator .= owner.generator; assert(owner.body.present); if generator.planning.bodies.contains(owner.body.value,id) { match resolvedPlan(owner,id) { constructor_subject plan=>{ return expression(owner,plan.value,depth + 1); },_=>{ assert(false); }, } }
    let source .= generator.unit(owner.unit_id); let node = source.node(id); let constructor = source.constructor(node.a); if source.nominal(constructor.nominal).is_opaque { if node.b == 0 { return emit(owner,blot_backend_runtime_ir::OP_i32_const,0); } return expression(owner,node.b,depth + 1); } if node.b == 0 && node.c == 0 { return nullaryConstructor(owner,constructor.tag); }
    var payload = blot_support::none<u32>(); if node.b != 0 { let value,error = capture(owner,node.b,depth); if error != Error.none { return error; } payload = blot_support::some(value); } if node.b != 0 && source.types.node(source.typeOf(node.b)).tag == blot_check_types::Tag.never { return Error.none; } var floating = false; if node.b != 0 { let value,error = scalar(owner,node.b); if error != Error.none { return error; } floating = value == blot_backend_runtime_ir::SC_f32; }
    if node.c != 0 {
        let record = source.types.node(source.constructor(node.a).payload); if record.tag != blot_check_types::Tag.record || record.b == 0 || !payload.present { return generator.fail(owner.unit_id,id,blot_backend_core_backend::Code.unsupported); }
        if record.b == 1 { let concrete,error = codeLayout(owner,source.typeOf(node.b),source.span(node.b)); if error != Error.none { return error; } let address,address_error = allocate(owner,4,AllocationRoles { words: [generator.layoutRole(concrete)] }); if address_error != Error.none { return address_error; } let a = emit(owner,blot_backend_runtime_ir::OP_local_get,address); if a != Error.none { return a; } let b = emit(owner,blot_backend_runtime_ir::OP_local_get,payload.value); if b != Error.none { return b; } var store = blot_backend_runtime_ir::OP_i32_store; if floating { store = blot_backend_runtime_ir::OP_f32_store; } let stored = emit(owner,store,0); if stored != Error.none { return stored; } payload = blot_support::some(address); }
        else { let original = payload.value; let converted,error = recordRepresentation(owner,record,original,true); if error != Error.none { return error; } payload = blot_support::some(converted); if converted != original { let concrete,concrete_error = codeLayout(owner,source.typeOf(node.b),source.span(node.b)); if concrete_error != Error.none { return concrete_error; } let acyclic = markAcyclic(owner,converted,concrete); if acyclic != Error.none { return acyclic; } } } floating = false;
    }
    var payload_role = blot_backend_runtime_ir::ROLE_scalar; if node.c != 0 { payload_role = blot_backend_runtime_ir::ROLE_reference; } else if node.b != 0 { let concrete,error = codeLayout(owner,source.typeOf(node.b),source.span(node.b)); if error != Error.none { return error; } payload_role = generator.layoutRole(concrete); }
    let address,error = allocate(owner,8,AllocationRoles { words: [blot_backend_runtime_ir::ROLE_scalar,payload_role] }); if error != Error.none { return error; } if payload_role == blot_backend_runtime_ir::ROLE_reference { let concrete,concrete_error = codeLayout(owner,node.ty,source.span(id)); if concrete_error != Error.none { return concrete_error; } let acyclic = markAcyclic(owner,address,concrete); if acyclic != Error.none { return acyclic; } }
    let a = emit(owner,blot_backend_runtime_ir::OP_local_get,address); if a != Error.none { return a; } let b = emit(owner,blot_backend_runtime_ir::OP_i32_const,constructor.tag); if b != Error.none { return b; } let c = emit(owner,blot_backend_runtime_ir::OP_i32_store,0); if c != Error.none { return c; } let d = emit(owner,blot_backend_runtime_ir::OP_local_get,address); if d != Error.none { return d; }
    var selected: Error; if payload.present { selected = emit(owner,blot_backend_runtime_ir::OP_local_get,payload.value); } else { selected = emit(owner,blot_backend_runtime_ir::OP_i32_const,0); } if selected != Error.none { return selected; } var store = blot_backend_runtime_ir::OP_i32_store; if floating { store = blot_backend_runtime_ir::OP_f32_store; } let stored = emit(owner,store,4); if stored != Error.none { return stored; } return emit(owner,blot_backend_runtime_ir::OP_local_get,address);
}
struct Location { owner: u32,container: u32,offset: u32,size: blot_support::Option<u32>,wrapped: bool,list_index: blot_support::Option<u32>,row_words: u32 = 0,row_layout: u32 = 0,array_scalar: blot_support::Option<bool>,mask: blot_support::Option<u32>,scalar_storage: bool = false,shape: blot_support::Option<u32>,acyclic: bool = false }
struct LocationBuffer { storage: Location[:] = [],items: Location[:] = [] }
reusable[] var location_runs: Location[>..] = [];
fn push(buffer: LocationBuffer&,value: Location) -> Error { return blot_support_pooled_buffer::push(buffer,value,location_runs); }
fn deinit(buffer: LocationBuffer&) { blot_support_pooled_buffer::deinit(buffer,location_runs); }
fn payloadLayout(owner: Owner&,projection: blot_check_core::Projection,tag: u32,id: u32) -> u32,Error {
    let generator .= owner.generator; let source .= generator.unit(owner.unit_id); for constructor in source.constructors { let nominal = source.nominal(constructor.nominal); if nominal.identity != projection.nominal || constructor.tag != tag { continue; } let concrete,error = codeLayout(owner,projection.source_type,source.span(id)); if error != Error.none { return 0,error; } let arguments = generator.representations.store.children(concrete); let parameters = source.types.list(nominal.parameters); if arguments.len != parameters.len { return 0,generator.fail(owner.unit_id,id,blot_backend_core_backend::Code.unresolved_type); }
        var mappings = MappingBuffer {}; defer { mappings.deinit(); } let copied = mappings.append(owner.mappings); if copied != Error.none { return 0,copied; } for parameter,index in parameters { let mapped = generator.mapType(owner.unit_id,mappings,parameter,arguments[index],source.span(id)); if mapped != Error.none { return 0,mapped; } } return generator.codeLayoutWithRows(owner.unit_id,constructor.payload,mappings.items,owner.row_mappings,source.span(id));
    } return 0,generator.fail(owner.unit_id,id,blot_backend_core_backend::Code.unsupported);
}
fn payloadSlots(owner: Owner&,projection: blot_check_core::Projection,tag: u32,id: u32) -> u32,Error { let concrete,error = payloadLayout(owner,projection,tag,id); if error != Error.none { return 0,error; } let node = owner.generator.representations.store.node(concrete); if node.tag == blot_backend_layout::Tag.product || node.tag == blot_backend_layout::Tag.record { return node.b,Error.none; } return 0,owner.generator.fail(owner.unit_id,id,blot_backend_core_backend::Code.unsupported); }
fn resolveProjection(owner: Owner&,original: blot_check_core::Projection,variants: VariantBuffer&,id: u32) -> blot_check_core::Projection,Error {
    let generator .= owner.generator; let source .= generator.unit(owner.unit_id); var projection = original; let concrete,error = codeLayout(owner,projection.source_type,source.span(id)); if error != Error.none { return projection,error; } let node = generator.representations.store.node(concrete);
    if node.tag == blot_backend_layout::Tag.record { let fields = generator.representations.store.children(concrete); var index: i64 = 0; while index < fields.len { if fields[index] == projection.field { let appended = variants.push(blot_check_core::ProjectionVariant { 0,(index / 2) as u32 }); return projection,appended; } index += 2; } }
    else if node.tag == blot_backend_layout::Tag.nominal { projection.nominal = blot_check_types::NominalIdentity { node.a,node.b }; for constructor in source.constructors { if source.nominal(constructor.nominal).identity != projection.nominal { continue; } let payload,payload_error = payloadLayout(owner,projection,constructor.tag,id); if payload_error != Error.none { return projection,payload_error; } if generator.representations.store.node(payload).tag != blot_backend_layout::Tag.record { return projection,generator.fail(owner.unit_id,id,blot_backend_core_backend::Code.unresolved_type); } let fields = generator.representations.store.children(payload); var index: i64 = 0; var found = false;
            while index < fields.len { if fields[index] == projection.field { let appended = variants.push(blot_check_core::ProjectionVariant { constructor.tag,(index / 2) as u32 }); if appended != Error.none { return projection,appended; } found = true; break; } index += 2; } if !found { return projection,generator.fail(owner.unit_id,id,blot_backend_core_backend::Code.unresolved_type); }
        } if variants.items.len != 0 { return projection,Error.none; }
    } return projection,generator.fail(owner.unit_id,id,blot_backend_core_backend::Code.unresolved_type);
}
fn copyWords(values: const u32[:]) -> u32[:] { if values.len == 0 { return []; } let copy = owned_words.alloc_slice(values.len); for value,index in values { copy[index] = value; } return copy; }
fn copyMappings(values: const Mapping[:]) -> Mapping[:] { if values.len == 0 { return []; } let copy = owned_mappings.alloc_slice(values.len); for value,index in values { copy[index] = value; } return copy; }
fn copyRows(values: const RowMapping[:]) -> RowMapping[:] { if values.len == 0 { return []; } let copy = owned_rows.alloc_slice(values.len); for value,index in values { copy[index] = value; } return copy; }
fn copyVariants(values: const blot_check_core::ProjectionVariant[:]) -> blot_check_core::ProjectionVariant[:] { if values.len == 0 { return []; } let copy = owned_variants.alloc_slice(values.len); for value,index in values { copy[index] = value; } return copy; }
fn prepareField(owner: Owner&,id: u32,index: u32,sizes: bool) -> FieldPlan,Error {
    let generator .= owner.generator; let source .= generator.unit(owner.unit_id); var projection = source.projection(index); var variants = VariantBuffer {}; 
    recursive fn cleanup_continuation_17() -> FieldPlan,Error {
 var slots = WordBuffer {}; 
    recursive fn cleanup_continuation_16() -> FieldPlan,Error {
 let original = source.projectionVariants(index);
    if projection.field != 0 || original.len == 0 { let resolved,error = resolveProjection(owner,projection,variants,id); if error != Error.none { return FieldPlan { index,projection,[],[] },error; } projection = resolved; }
    else { let appended = variants.append(original); if appended != Error.none { return FieldPlan { index,projection,[],[] },appended; } }
    if sizes { for variant in variants.items {
        var count: u32 = 0; if projection.nominal.decl != 0 { let words,error = payloadSlots(owner,projection,variant.tag,id); if error != Error.none { return FieldPlan { index,projection,[],[] },error; } count = words; }
        else { let concrete,error = codeLayout(owner,projection.source_type,source.span(id)); if error != Error.none { return FieldPlan { index,projection,[],[] },error; } count = generator.representations.store.node(concrete).b; }
        if count > 4294967295 / 4 { return FieldPlan { index,projection,[],[] },generator.fail(owner.unit_id,id,blot_backend_core_backend::Code.complexity); } let appended = slots.push(count); if appended != Error.none { return FieldPlan { index,projection,[],[] },appended; }
    } }
    return FieldPlan { index,projection,copyVariants(variants.items),copyWords(slots.items) },Error.none;

    }
    let cleanup_result_16_0,cleanup_result_16_1 = cleanup_continuation_16();
     slots.deinit(); 
    return cleanup_result_16_0,cleanup_result_16_1;

    }
    let cleanup_result_17_0,cleanup_result_17_1 = cleanup_continuation_17();
     variants.deinit(); 
    return cleanup_result_17_0,cleanup_result_17_1;
}
fn prepareUpdateLocations(owner: Owner&,id: u32) -> FieldPlan[:],Error {
    assert(owner.preparing); let source .= owner.generator.unit(owner.unit_id); var fields = FieldBuffer {}; var published = false; 
    recursive fn cleanup_continuation_15() -> FieldPlan[:],Error {
 let selectors = source.updateSelectors(id);
    if selectors.len == 0 { for index in source.updatePath(id) { let field,error = prepareField(owner,id,index,true); if error != Error.none { return [],error; } let appended = fields.push(field); if appended != Error.none { field.deinit(); return [],appended; } } }
    else { for selector in selectors { if selector.kind == blot_check_core::UpdateKind.field { let field,error = prepareField(owner,id,selector.projection,true); if error != Error.none { return [],error; } let appended = fields.push(field); if appended != Error.none { field.deinit(); return [],appended; } } } }
    var output: FieldPlan[:] = []; if fields.items.len != 0 { let owned = owned_fields.alloc_slice(fields.items.len); for field,index in fields.items { owned[index] = field; } output = owned; } published = true; return output,Error.none;

    }
    let cleanup_result_15_0,cleanup_result_15_1 = cleanup_continuation_15();
     if !published { for &field in fields.items { field.deinit(); } } fields.deinit(); 
    return cleanup_result_15_0,cleanup_result_15_1;
}
fn fieldPlan(owner: Owner&,id: u32,index: u32) -> FieldPlan {
    match resolvedPlan(owner,id) { projection selected=>{ assert(selected.value.present); match selected.value.value { field value=>{ return value.value; },_=>{ assert(false); }, } },update_locations selected=>{ for place in selected.value { if place.index == index { return place; } } },_=>{ assert(false); }, }
    abort("checked field plan missing");
}
recursive fn prepareProjection(owner: Owner&,body: u32,id: u32,depth: i64) -> blot_support::Option<ProjectionPlan>,Error {
    assert(owner.preparing); let generator .= owner.generator; let source .= generator.unit(owner.unit_id); let node = source.node(id); if source.types.node(source.typeOf(node.a)).tag == blot_check_types::Tag.never { return blot_support::none<ProjectionPlan>(),Error.none; } let metadata = source.projection(node.b);
    if source.projectionVariants(node.b).len != 0 { let field,error = prepareField(owner,id,node.b,false); if error != Error.none { return blot_support::none<ProjectionPlan>(),error; } return blot_support::some(ProjectionPlan.field { field }),Error.none; }
    let previous = generator.diagnostic; var field = blot_support::none<FieldPlan>(); let prepared,prepared_error = prepareField(owner,id,node.b,false); if prepared_error == Error.declined { generator.diagnostic = previous; } else if prepared_error != Error.none { return blot_support::none<ProjectionPlan>(),prepared_error; } else { field = blot_support::some(prepared); }
    var transferred = false; 
    recursive fn cleanup_continuation_14() -> blot_support::Option<ProjectionPlan>,Error {
 let concrete,error = codeLayout(owner,metadata.source_type,source.span(id)); if error != Error.none { return blot_support::none<ProjectionPlan>(),error; } let method,method_error = memberTarget(owner,id,metadata.field,concrete); if method_error != Error.none { return blot_support::none<ProjectionPlan>(),method_error; }
    if field.present && method.present { return blot_support::none<ProjectionPlan>(),generator.fail(owner.unit_id,id,blot_backend_core_backend::Code.ambiguous_member); } if field.present { transferred = true; return blot_support::some(ProjectionPlan.field { field.value }),Error.none; } if !method.present { return blot_support::none<ProjectionPlan>(),generator.fail(owner.unit_id,id,blot_backend_core_backend::Code.missing_member); } let target = method.value;
    let result,result_error = codeLayout(owner,node.ty,source.span(id)); if result_error != Error.none { return blot_support::none<ProjectionPlan>(),result_error; } let full,full_error = generator.internLayout(blot_backend_layout::Tag.function,concrete,result,[]); if full_error != Error.none { return blot_support::none<ProjectionPlan>(),full_error; } let signature,signature_error = dispatchCallableLayout(owner,id,full); if signature_error != Error.none { return blot_support::none<ProjectionPlan>(),signature_error; }
    var direct = Key { target,count: 1,result }; direct.parameters[0] = concrete; direct.effects[0] = generator.representations.store.node(signature).c;
    let producer .= generator.unit(target.unit); let method_body .= producer.body(target.binding); if method_body != null {
        let root = producer.node(method_body.root); if root.tag == blot_check_core::Tag.if_value && producer.node(root.b).tag == blot_check_core::Tag.construct && blot_backend_collection_iteration::cursorNext(producer,target.binding,producer,producer.node(root.b).a) && !producer.nominal(producer.constructor(producer.node(root.b).a).nominal).is_opaque {
            let prepared = prepareNode(owner,body,node.a,depth + 1,false); if prepared != Error.none { return blot_support::none<ProjectionPlan>(),prepared; } let input,input_error = privateCursorConstructor(owner,body,node.a); if input_error != Error.none { return blot_support::none<ProjectionPlan>(),input_error; } if input.present && source.node(input.value).tag == blot_check_core::Tag.array && source.children(input.value).len == 0 { if generator.artifacts != null { generator.artifacts.requireFreshCode(); } return blot_support::some(ProjectionPlan.empty_cursor { producer.constructor(producer.node(root.c).a).tag }),Error.none; }
        }
    }
    return blot_support::some(ProjectionPlan.member { direct,blot_reuse_code_artifacts::CallableKey { target,ty: signature } }),Error.none;

    }
    let cleanup_result_14_0,cleanup_result_14_1 = cleanup_continuation_14();
     if !transferred && field.present { field.value.deinit(); } 
    return cleanup_result_14_0,cleanup_result_14_1;
}
fn fieldType(owner: Owner&,projection: blot_check_core::Projection,tag: u32,id: u32) -> u32,Error { if projection.nominal.decl != 0 { return payloadLayout(owner,projection,tag,id); } return codeLayout(owner,projection.source_type,owner.generator.unit(owner.unit_id).span(id)); }
fn fieldMask(owner: Owner&,projection: blot_check_core::Projection,tag: u32,id: u32) -> blot_support::Option<u32>,Error {
    let generator .= owner.generator; let ty,error = fieldType(owner,projection,tag,id); if error != Error.none { return blot_support::none<u32>(),error; } let node = generator.representations.store.node(ty); if node.tag != blot_backend_layout::Tag.product && node.tag != blot_backend_layout::Tag.record { return blot_support::none<u32>(),Error.none; }
    let fields = generator.representations.store.children(ty); var mask: u32 = 0; var tail = blot_backend_runtime_ir::ROLE_scalar;
    for word in 0..node.b { var index = word; if node.tag == blot_backend_layout::Tag.record { index = word * 2 + 1; } let role = generator.layoutRole(fields[index]); if role != blot_backend_runtime_ir::ROLE_scalar && role != blot_backend_runtime_ir::ROLE_reference { return blot_support::none<u32>(),Error.none; }
        if word < 31 { if role == blot_backend_runtime_ir::ROLE_reference { mask |= (1 as u32) << word as u32; } } else if word == 31 { tail = role; if role == blot_backend_runtime_ir::ROLE_reference { mask |= 2147483648; } } else if role != tail { return blot_support::none<u32>(),Error.none; }
    } return blot_support::some(mask),Error.none;
}
fn fieldShape(owner: Owner&,projection: blot_check_core::Projection,tag: u32,id: u32) -> blot_support::Option<u32>,Error {
    let generator .= owner.generator; let ty,error = fieldType(owner,projection,tag,id); if error != Error.none { return blot_support::none<u32>(),error; } let node = generator.representations.store.node(ty); if node.tag != blot_backend_layout::Tag.product && node.tag != blot_backend_layout::Tag.record { return blot_support::none<u32>(),Error.none; }
    let fields = generator.representations.store.children(ty); var roles = RoleBuffer {}; 
    recursive fn cleanup_continuation_13() -> blot_support::Option<u32>,Error {
 for word in 0..node.b { var index = word; if node.tag == blot_backend_layout::Tag.record { index = word * 2 + 1; } let appended = roles.push(generator.layoutRole(fields[index])); if appended != Error.none { return blot_support::none<u32>(),appended; } } return wideShape(owner,node.b * 4,AllocationRoles { words: roles.items },true);

    }
    let cleanup_result_13_0,cleanup_result_13_1 = cleanup_continuation_13();
     roles.deinit(); 
    return cleanup_result_13_0,cleanup_result_13_1;
}
fn emitInstructions(owner: Owner&,instructions: const blot_backend_runtime_ir::Instruction[:]) -> Error { for instruction in instructions { let error = emit(owner,instruction.op,instruction.operand); if error != Error.none { return error; } } return Error.none; }
fn emitConstantLocal(owner: Owner&,value: u32,local: u32) -> Error { let constant = emit(owner,blot_backend_runtime_ir::OP_i32_const,value); if constant != Error.none { return constant; } return emit(owner,blot_backend_runtime_ir::OP_local_set,local); }
fn setLocationVariant(owner: Owner&,prepared: FieldPlan,index: i64,id: u32,offset: u32,size: blot_support::Option<u32>,mask: blot_support::Option<u32>,shape: blot_support::Option<u32>,shapes: const u32[:]) -> Error {
    let variant = prepared.variants[index]; let field = emitConstantLocal(owner,variant.field * 4,offset); if field != Error.none { return field; }
    if size.present { let slots = prepared.slots[index]; if slots > 4294967295 / 4 { return owner.generator.fail(owner.unit_id,id,blot_backend_core_backend::Code.complexity); } let assigned = emitConstantLocal(owner,slots * 4,size.value); if assigned != Error.none { return assigned; } }
    if mask.present { let bits,error = fieldMask(owner,prepared.projection,variant.tag,id); if error != Error.none { return error; } assert(bits.present); let assigned = emitConstantLocal(owner,bits.value,mask.value); if assigned != Error.none { return assigned; } }
    if shape.present { let reference = referenceConstant(owner,shapes[index],blot_reuse_artifact_emitter::Role.static_address); if reference != Error.none { return reference; } return emit(owner,blot_backend_runtime_ir::OP_local_set,shape.value); } return Error.none;
}
fn location(owner: Owner&,value_owner: u32,projection_index: u32,id: u32,need_size: bool) -> Location,Error {
    let generator .= owner.generator; let prepared = fieldPlan(owner,id,projection_index); let projection = prepared.projection; let variants = prepared.variants; var result = Location { owner: value_owner,container: value_owner,offset: 0,size: blot_support::none<u32>(),wrapped: projection.nominal.decl != 0 };
    if need_size { let concrete,error = codeLayout(owner,projection.source_type,generator.unit(owner.unit_id).span(id)); if error != Error.none { return result,error; } let acyclic,acyclic_error = generator.acyclicLayout(concrete); if acyclic_error != Error.none { return result,acyclic_error; } result.acyclic = acyclic; }
    if result.wrapped { for nominal in generator.unit(projection.nominal.unit).nominals { if nominal.identity == projection.nominal && nominal.is_opaque { result.wrapped = false; break; } } }
    if result.wrapped { let local,error = temporary(owner,blot_backend_runtime_ir::VT_i32); if error != Error.none { return result,error; } result.container = local; } let offset,offset_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if offset_error != Error.none { return result,offset_error; } result.offset = offset;
    if need_size { let size,error = temporary(owner,blot_backend_runtime_ir::VT_i32); if error != Error.none { return result,error; } result.size = blot_support::some(size); } result.scalar_storage = need_size;
    if need_size { for variant in variants { let bits,error = fieldMask(owner,projection,variant.tag,id); if error != Error.none { return result,error; } if !bits.present || bits.value != 0 { result.scalar_storage = false; } } }
    if need_size && !result.scalar_storage { var known = true; for variant in variants { let bits,error = fieldMask(owner,projection,variant.tag,id); if error != Error.none { return result,error; } if !bits.present { known = false; break; } } if known { let mask,error = temporary(owner,blot_backend_runtime_ir::VT_i32); if error != Error.none { return result,error; } result.mask = blot_support::some(mask); } }
    var shapes = WordBuffer {}; 
    recursive fn cleanup_continuation_12() -> Location,Error {

    if need_size && !result.scalar_storage && !result.mask.present { var known = true; for variant in variants { let address,error = fieldShape(owner,projection,variant.tag,id); if error != Error.none { return result,error; } if !address.present { known = false; break; } let appended = shapes.push(address.value); if appended != Error.none { return result,appended; } } if known { let shape,error = temporary(owner,blot_backend_runtime_ir::VT_i32); if error != Error.none { return result,error; } result.shape = blot_support::some(shape); } }
    if result.wrapped { let loaded = emit(owner,blot_backend_runtime_ir::OP_local_get,value_owner); if loaded != Error.none { return result,loaded; } let payload = nonzeroLoad(owner,blot_backend_runtime_ir::OP_i32_load,4); if payload != Error.none { return result,payload; } let stored = emit(owner,blot_backend_runtime_ir::OP_local_set,result.container); if stored != Error.none { return result,stored; } }
    if variants.len == 1 {
        if result.wrapped { let loaded = emit(owner,blot_backend_runtime_ir::OP_local_get,value_owner); if loaded != Error.none { return result,loaded; } let tag = nonzeroLoad(owner,blot_backend_runtime_ir::OP_i32_load,0); if tag != Error.none { return result,tag; } let checked = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,variants[0].tag),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_ne),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_if_),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_unreachable_),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_end)]); if checked != Error.none { return result,checked; } }
        let assigned = setLocationVariant(owner,prepared,0,id,result.offset,result.size,result.mask,result.shape,shapes.items); return result,assigned;
    }
    let sentinel = emitConstantLocal(owner,4294967295,result.offset); if sentinel != Error.none { return result,sentinel; }
    for variant,index in variants {
        if result.wrapped { let loaded = emit(owner,blot_backend_runtime_ir::OP_local_get,value_owner); if loaded != Error.none { return result,loaded; } let tag = nonzeroLoad(owner,blot_backend_runtime_ir::OP_i32_load,0); if tag != Error.none { return result,tag; } let checked = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,variant.tag),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_eq),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_if_)]); if checked != Error.none { return result,checked; } owner.labels++; }
        let assigned = setLocationVariant(owner,prepared,index,id,result.offset,result.size,result.mask,result.shape,shapes.items); if assigned != Error.none { return result,assigned; } if result.wrapped { owner.labels--; let end = emit(owner,blot_backend_runtime_ir::OP_end); if end != Error.none { return result,end; } }
    }
    let checked = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,result.offset),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,4294967295),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_eq),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_if_),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_unreachable_),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_end)]); return result,checked;

    }
    let cleanup_result_12_0,cleanup_result_12_1 = cleanup_continuation_12();
     shapes.deinit(); 
    return cleanup_result_12_0,cleanup_result_12_1;
}
fn nonzeroLoad(owner: Owner&,op: blot_backend_runtime_ir::Op,offset: u32) -> Error { let marker = owner.generator.module.emit(owner.function_id,blot_backend_runtime_ir::nonzeroRead()); if marker != Error.none { return marker; } return emit(owner,op,offset); }
fn loadLocation(owner: Owner&,place: Location,scalar: blot_backend_runtime_ir::Scalar) -> Error { if place.list_index.present && place.row_words != 0 { return readListRow(owner,place.owner,place.list_index.value,place.row_words,blot_support::none<u32[2]>(),blot_support::none<u32>(),place.row_layout); } let address = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,place.container),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,place.offset),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_add)]); if address != Error.none { return address; } return readElement(owner,blot_backend_runtime_ir::machine(scalar),0,place.row_words,place.row_layout); }
fn dispatchCallableLayout(owner: Owner&,id: u32,fallback: u32) -> u32,Error { let source .= owner.generator.unit(owner.unit_id); let signature = source.dispatchSignature(id); if signature == 0 { return fallback,Error.none; } return codeLayout(owner,signature,source.span(id)); }
recursive fn project(owner: Owner&,id: u32,depth: i64) -> Error {
    let generator .= owner.generator; let callable,callable_error = staticCallableTemplate(owner,id); if callable_error != Error.none { return callable_error; } let source .= generator.unit(owner.unit_id);
    if callable.present { let concrete,error = codeLayout(owner,source.typeOf(id),source.span(id)); if error != Error.none { return error; } return templateValue(owner,callable.value,concrete); } let node = source.node(id); if source.types.node(source.typeOf(node.a)).tag == blot_check_types::Tag.never { return expression(owner,node.a,depth + 1); }
    var prepared = blot_support::none<ProjectionPlan>(); match resolvedPlan(owner,id) { projection plan=>{ prepared = plan.value; },_=>{ assert(false); }, } assert(prepared.present);
    match prepared.value {
        empty_cursor plan=>{ let evaluated = expression(owner,node.a,depth + 1); if evaluated != Error.none { return evaluated; } let dropped = emit(owner,blot_backend_runtime_ir::OP_drop); if dropped != Error.none { return dropped; } return nullaryConstructor(owner,plan.value); },
        member plan=>{ let inlined,error = inlineNamedCall(owner,plan.direct,[node.a],depth); if error != Error.none || inlined { return error; } let wrapper,wrapper_error = generator.callable(plan.wrapper); if wrapper_error != Error.none { return wrapper_error; } let receiver,receiver_error = capture(owner,node.a,depth); if receiver_error != Error.none { return receiver_error; } let loaded = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,0),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,receiver)]); if loaded != Error.none { return loaded; } let provider = providerHead(owner); if provider != Error.none { return provider; } return emit(owner,blot_backend_runtime_ir::OP_call,wrapper); },_=>{},
    }
    let packed,packed_error = packedProjection(owner,id,depth); if packed_error != Error.none || packed { return packed_error; }
    for view in owner.row_views.items { let nested,error = generator.nestedRow(view.row); if error != Error.none { return error; } if nested.present { let offset = blot_reuse_row_projection_uses::numericOffset(source,id,view.binding,generator.representations.store,nested.value); if offset.present { let scalar_type,scalar_error = scalar(owner,id); if scalar_error != Error.none { return scalar_error; } return loadRowView(owner,view,offset.value,blot_backend_runtime_ir::machine(scalar_type)); } } }
    if source.node(node.a).tag == blot_check_core::Tag.reference { let reference = source.reference(node.a); if reference.unit == 0 || reference.unit == owner.unit_id { var index = owner.row_views.items.len; while index != 0 { index--; let view = owner.row_views.items[index]; if view.binding != reference.binding { continue; } let offset = blot_reuse_row_projection_uses::fieldOffset(source,node.b,generator.representations.store,view.row); if !offset.present { return generator.fail(owner.unit_id,id,blot_backend_core_backend::Code.unresolved_type); } let scalar_type,scalar_error = scalar(owner,id); if scalar_error != Error.none { return scalar_error; } return loadRowView(owner,view,offset.value,blot_backend_runtime_ir::machine(scalar_type)); } } }
    let container,container_error = capture(owner,node.a,depth); if container_error != Error.none { return container_error; } let place,place_error = location(owner,container,node.b,id,false); if place_error != Error.none { return place_error; }
    let address = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,place.container),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,place.offset),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_add)]); if address != Error.none { return address; } let scalar_type,scalar_error = scalar(owner,id); if scalar_error != Error.none { return scalar_error; } var load = blot_backend_runtime_ir::OP_i32_load; if blot_backend_runtime_ir::machine(scalar_type) == blot_backend_runtime_ir::VT_f32 { load = blot_backend_runtime_ir::OP_f32_load; } return nonzeroLoad(owner,load,0);
}
recursive fn packedProjection(owner: Owner&,id: u32,depth: i64) -> bool,Error {
    let generator .= owner.generator; let source .= generator.unit(owner.unit_id); var origin = source.node(id).a; var remaining: i64 = 16; while source.node(origin).tag == blot_check_core::Tag.project && remaining != 0 { origin = source.node(origin).a; remaining--; } let value = source.node(origin); if value.tag != blot_check_core::Tag.array_op { return false,Error.none; } let op = source.arrayOperation(origin); if op != blot_backend_collection_ops::Op.get && op != blot_backend_collection_ops::Op.cursor_value { return false,Error.none; }
    let operands = source.children(origin); let input,error = codeLayout(owner,source.typeOf(operands[0]),source.span(id)); if error != Error.none { return false,error; } var collection = input; if op == blot_backend_collection_ops::Op.cursor_value { collection = generator.representations.store.node(input).a; } let words,word_error = generator.collectionRowWords(collection); if word_error != Error.none { return false,word_error; } if words == 0 { return false,Error.none; } let row = generator.representations.store.node(collection).a;
    let nested,nested_error = generator.nestedRow(row); if nested_error != Error.none { return false,nested_error; } var field: u32 = 0;
    if nested.present { let offset = blot_reuse_row_projection_uses::numericExpressionOffset(source,id,origin,generator.representations.store,nested.value); if !offset.present { return false,Error.none; } field = offset.value / 4; }
    else { let projected = source.node(id); if origin != projected.a { return false,Error.none; } let offset = blot_reuse_row_projection_uses::fieldOffset(source,projected.b,generator.representations.store,row); if !offset.present { return false,Error.none; } field = offset.value / 4; }
    let held,held_error = capture(owner,operands[0],depth); if held_error != Error.none { return false,held_error; } var container = held; var cursor = blot_support::none<u32>(); if op == blot_backend_collection_ops::Op.cursor_value { cursor = blot_support::some(container); } var cache = blot_support::none<u32[2]>(); var index: u32 = 0;
    if op == blot_backend_collection_ops::Op.get { let selected,selected_error = capture(owner,operands[1],depth); if selected_error != Error.none { return false,selected_error; } index = selected; }
    else { let private = privateCursorReference(owner,operands[0]); if private.present { container = private.value.values[0]; cache = blot_support::some([private.value.values[2],private.value.values[3]]); index = private.value.values[1]; }
        else { let position,position_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if position_error != Error.none { return false,position_error; } let loaded = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,container),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,blot_runtime_runtime_layout::Cursor_index),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,position),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,container),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,blot_runtime_runtime_layout::Cursor_collection)]); if loaded != Error.none { return false,loaded; } let collection,collection_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if collection_error != Error.none { return false,collection_error; } container = collection; let stored = emit(owner,blot_backend_runtime_ir::OP_local_set,container); if stored != Error.none { return false,stored; } index = position; }
    }
    let is_list = generator.representations.store.node(collection).tag == blot_backend_layout::Tag.list;
    if is_list { if cache.present { let bounds = privateCursorBounds(owner,container,index,words); if bounds != Error.none { return false,bounds; } let address = cachedListWordAddress(owner,container,index,field,cache.value); if address != Error.none { return false,address; } }
        else { let bounds = listRowBounds(owner,container,index,words); if bounds != Error.none { return false,bounds; } let base,base_error = multiplyLocal(owner,index,words); if base_error != Error.none { return false,base_error; } if cursor.present { let cached,cached_error = cursorCache(owner,cursor.value); if cached_error != Error.none { return false,cached_error; } let address = cachedListWordAddress(owner,container,base,field,cached); if address != Error.none { return false,address; } } else { let address = listWordAddress(owner,container,base,field,false); if address != Error.none { return false,address; } } }
    } else { let bounds = arrayBounds(owner,container,index); if bounds != Error.none { return false,bounds; } let address = arrayAddress(owner,container,index,words * 4); if address != Error.none { return false,address; } }
    let scalar_type,scalar_error = scalar(owner,id); if scalar_error != Error.none { return false,scalar_error; } var load = blot_backend_runtime_ir::OP_i32_load; if scalar_type == blot_backend_runtime_ir::SC_f32 { load = blot_backend_runtime_ir::OP_f32_load; } var offset: u32 = 0; if !is_list { offset = 4 + field * 4; } let loaded = emit(owner,load,offset); return loaded == Error.none,loaded;
}
fn memberTarget(owner: Owner&,id: u32,member: u32,receiver: u32) -> blot_support::Option<blot_check_core::BindingRef>,Error { let identity = dispatchIdentity(owner,receiver); if !identity.present { return blot_support::none<blot_check_core::BindingRef>(),Error.none; } return owner.generator.associatedTarget(owner.unit_id,identity.value,member,blot_check_core::Op.none); }
fn indexLocation(owner: Owner&,array: u32,index: u32,collection: u32) -> Location,Error {
    let generator .= owner.generator; let is_list = generator.representations.store.node(collection).tag == blot_backend_layout::Tag.list; let words,error = generator.collectionRowWords(collection); var result = Location { owner: array,container: array,offset: index,size: blot_support::none<u32>(),wrapped: false }; if error != Error.none { return result,error; }
    if is_list && words != 0 { let bounds = listRowBounds(owner,array,index,words); if bounds != Error.none { return result,bounds; } result.list_index = blot_support::some(index); result.row_words = words; result.row_layout = generator.representations.store.node(collection).a; return result,Error.none; }
    let bounds = arrayBounds(owner,array,index); if bounds != Error.none { return result,bounds; }
    if is_list { let runtime,runtime_error = generator.module.ensureLists(); if runtime_error != Error.none { return result,runtime_error; } let address,address_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if address_error != Error.none { return result,address_error; } let zero,zero_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if zero_error != Error.none { return result,zero_error; }
        let located = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,array),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,index),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_call,runtime.address),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,address),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,0),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,zero)]); if located != Error.none { return result,located; } result.container = address; result.offset = zero; result.list_index = blot_support::some(index); return result,Error.none;
    }
    let count,count_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if count_error != Error.none { return result,count_error; } let counted = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,array),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,0),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,count)]); if counted != Error.none { return result,counted; }
    let row_words,row_error = generator.collectionRowWords(collection); if row_error != Error.none { return result,row_error; } let size,size_error = arraySize(owner,count,blot_backend_packed_layout::stride(row_words)); if size_error != Error.none { return result,size_error; } let offset,offset_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if offset_error != Error.none { return result,offset_error; }
    let located = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,index),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,blot_backend_packed_layout::stride(row_words)),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_mul),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,4),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_add),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,offset)]); if located != Error.none { return result,located; }
    result.offset = offset; result.size = blot_support::some(size); result.row_words = row_words; result.row_layout = generator.representations.store.node(collection).a; result.array_scalar = blot_support::some(row_words != 0 || generator.representations.store.scalar(result.row_layout).present); return result,Error.none;
}
recursive fn update(owner: Owner&,id: u32,depth: i64) -> Error {
    let generator .= owner.generator; let source .= generator.unit(owner.unit_id); let metadata = source.updateInfo(id); let path = source.updatePath(id); let selectors = source.updateSelectors(id); var places = LocationBuffer {}; 
    recursive fn cleanup_continuation_11() -> Error {

    let initial,initial_error = capture(owner,metadata.root,depth); if initial_error != Error.none { return initial_error; } var current = initial;
    if selectors.len != 0 { for selector in selectors {
        var place = Location { owner: current,container: current,offset: 0,size: blot_support::none<u32>(),wrapped: false };
        if selector.kind == blot_check_core::UpdateKind.field { let selected,error = location(owner,current,selector.projection,id,true); if error != Error.none { return error; } place = selected; }
        else { let index,error = capture(owner,selector.index,depth); if error != Error.none { return error; } let collection,collection_error = codeLayout(owner,selector.source_type,source.span(id)); if collection_error != Error.none { return collection_error; } let selected,selected_error = indexLocation(owner,current,index,collection); if selected_error != Error.none { return selected_error; } place = selected; }
        let appended = places.push(place); if appended != Error.none { return appended; } let scalar_type,error = generator.scalarWithRows(owner.unit_id,selector.result_type,owner.mappings,owner.row_mappings,source.span(id)); if error != Error.none { return error; }
        let local,local_error = temporary(owner,blot_backend_runtime_ir::machine(scalar_type)); if local_error != Error.none { return local_error; } current = local; let loaded = loadLocation(owner,place,scalar_type); if loaded != Error.none { return loaded; } let stored = emit(owner,blot_backend_runtime_ir::OP_local_set,current); if stored != Error.none { return stored; }
    } } else { for projection in path {
        let place,error = location(owner,current,projection,id,true); if error != Error.none { return error; } let appended = places.push(place); if appended != Error.none { return appended; } let scalar_type,scalar_error = generator.scalarWithRows(owner.unit_id,source.projection(projection).result_type,owner.mappings,owner.row_mappings,source.span(id)); if scalar_error != Error.none { return scalar_error; }
        let local,local_error = temporary(owner,blot_backend_runtime_ir::machine(scalar_type)); if local_error != Error.none { return local_error; } current = local; let loaded = loadLocation(owner,place,scalar_type); if loaded != Error.none { return loaded; } let stored = emit(owner,blot_backend_runtime_ir::OP_local_set,current); if stored != Error.none { return stored; }
    } }
    if metadata.self_binding != 0 { let loaded = emit(owner,blot_backend_runtime_ir::OP_local_get,current); if loaded != Error.none { return loaded; } let saved = save(owner,metadata.self_binding,id); if saved != Error.none { return saved; } }
    let result,result_error = capture(owner,metadata.value,depth); if result_error != Error.none { return result_error; } var changed = result; let result_scalar,scalar_error = scalar(owner,metadata.value); if scalar_error != Error.none { return scalar_error; } var changed_scalar = result_scalar; var index = places.items.len;
    while index != 0 {
        index--; let place = places.items[index]; let reuse,reuse_error = generator.ownsArrayUpdate(owner.unit_id,id); if reuse_error != Error.none { return reuse_error; }
        if place.list_index.present {
            let runtime,runtime_error = generator.module.ensureLists(); if runtime_error != Error.none { return runtime_error; } let container,container_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if container_error != Error.none { return container_error; }
            if place.row_words != 0 { let edited = editListRow(owner,place.owner,place.list_index.value,changed,place.row_words,blot_support::none<bool>(),reuse,place.row_layout); if edited != Error.none { return edited; } let stored = emit(owner,blot_backend_runtime_ir::OP_local_set,container); if stored != Error.none { return stored; } changed = container; changed_scalar = blot_backend_runtime_ir::SC_pointer; continue; }
            let loaded = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,place.owner),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,place.list_index.value),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,changed)]); if loaded != Error.none { return loaded; }
            if changed_scalar == blot_backend_runtime_ir::SC_f32 { let reinterpreted = emit(owner,blot_backend_runtime_ir::OP_i32_reinterpret_f32); if reinterpreted != Error.none { return reinterpreted; } } var consuming: u32 = 0; if reuse { consuming = 1; }
            let edited = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,consuming),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_call,runtime.set),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,container)]); if edited != Error.none { return edited; } changed = container; changed_scalar = blot_backend_runtime_ir::SC_pointer; continue;
        }
        var container = place.container; if !reuse {
            let copied,copy_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if copy_error != Error.none { return copy_error; } container = copied; let arena,arena_error = generator.module.ensureArena(); if arena_error != Error.none { return arena_error; } assert(place.size.present);
            let size = emit(owner,blot_backend_runtime_ir::OP_local_get,place.size.value); if size != Error.none { return size; }
            if place.array_scalar.present { let allocated = allocateArray(owner,place.array_scalar.value,place.row_layout); if allocated != Error.none { return allocated; } }
            else if place.scalar_storage { let allocated = emit(owner,blot_backend_runtime_ir::OP_call,arena.allocate_scalar); if allocated != Error.none { return allocated; } }
            else if place.mask.present { let allocated = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,place.mask.value),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_call,arena.allocate_typed)]); if allocated != Error.none { return allocated; } }
            else if place.shape.present { let allocated = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,place.shape.value),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_call,arena.allocate_shaped)]); if allocated != Error.none { return allocated; } }
            else { var allocator = arena.allocate; if place.row_words != 0 { allocator = arena.allocate_scalar; } let allocated = emit(owner,blot_backend_runtime_ir::OP_call,allocator); if allocated != Error.none { return allocated; } }
            let stored = emit(owner,blot_backend_runtime_ir::OP_local_set,container); if stored != Error.none { return stored; }
            if place.acyclic && !place.scalar_storage { let marked = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,container),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_call,arena.mark_acyclic)]); if marked != Error.none { return marked; } }
            let counted = place.array_scalar.present || place.mask.present || place.shape.present; if counted { let destination = emit(owner,blot_backend_runtime_ir::OP_local_get,container); if destination != Error.none { return destination; } }
            let inputs = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,container),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,place.container),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,place.size.value)]); if inputs != Error.none { return inputs; } var copied_error: Error; if counted { copied_error = emit(owner,blot_backend_runtime_ir::OP_call,arena.copy_words); } else { copied_error = emit(owner,blot_backend_runtime_ir::OP_memory_copy); } if copied_error != Error.none { return copied_error; }
        }
        let destination = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,container),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,place.offset),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_add),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,changed)]); if destination != Error.none { return destination; }
        let numeric_word = place.array_scalar.present && place.array_scalar.value && !place.mask.present && !place.shape.present && place.row_words == 0;
        var written: Error; if numeric_word { written = storeElement(owner,blot_backend_runtime_ir::machine(changed_scalar),0,0,true,0); }
        else if (place.array_scalar.present || place.mask.present || place.shape.present) && place.row_words == 0 { written = storeCollectionWord(owner,container,false,blot_backend_runtime_ir::machine(changed_scalar),0); }
        else { written = storeElement(owner,blot_backend_runtime_ir::machine(changed_scalar),0,place.row_words,changed_scalar != blot_backend_runtime_ir::SC_pointer,place.row_layout); } if written != Error.none { return written; }
        if place.wrapped {
            var wrapper = place.owner; if !reuse { let allocated,allocation_error = allocate(owner,8,AllocationRoles { words: [blot_backend_runtime_ir::ROLE_scalar,blot_backend_runtime_ir::ROLE_reference] }); if allocation_error != Error.none { return allocation_error; } wrapper = allocated;
                if place.acyclic { assert(generator.module.arena.present); let marked = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,wrapper),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_call,generator.module.arena.value.mark_acyclic)]); if marked != Error.none { return marked; } }
                let copied = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,wrapper),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,place.owner),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,8),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_memory_copy)]); if copied != Error.none { return copied; }
            }
            let replaced = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,wrapper),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,container)]); if replaced != Error.none { return replaced; } let stored = storeCollectionWord(owner,wrapper,false,blot_backend_runtime_ir::VT_i32,4); if stored != Error.none { return stored; } changed = wrapper;
        } else { changed = container; } changed_scalar = blot_backend_runtime_ir::SC_pointer;
    }
    return emit(owner,blot_backend_runtime_ir::OP_local_get,changed);

    }
    let cleanup_result_11_0 = cleanup_continuation_11();
     places.deinit(); 
    return cleanup_result_11_0;
}
recursive fn prepareCollectionStep(owner: Owner&,body: u32,id: u32,depth: i64) -> blot_support::Option<Plan>,Error {
    if owner.dictionary_owner.present { return blot_support::none<Plan>(),Error.none; } let generator .= owner.generator; let source .= generator.unit(owner.unit_id); let initializer = source.node(id).b; let tag = source.node(initializer).tag; if tag != blot_check_core::Tag.project && tag != blot_check_core::Tag.call { return blot_support::none<Plan>(),Error.none; }
    let uses,uses_error = generator.unitUses(owner.unit_id,blot_backend_unit_index::Need { parents: true }); if uses_error != Error.none { return blot_support::none<Plan>(),uses_error; } let selected = blot_backend_collection_iteration::stepSink(source,uses,id); if !selected.present { return blot_support::none<Plan>(),Error.none; } let sink = selected.value;
    let prepared = prepareNode(owner,body,initializer,depth + 1,false); if prepared != Error.none { return blot_support::none<Plan>(),prepared; } if !generator.planning.bodies.contains(body,initializer) { return blot_support::none<Plan>(),Error.none; } var key = blot_support::none<Key>(); var receiver: u32 = 0;
    match generator.planning.bodies.get(body,initializer) {
        projection projection=>{ if projection.value.present { match projection.value.value { member member=>{ key = blot_support::some(member.direct); receiver = source.node(initializer).a; },_=>{}, } } },
        named named=>{ if tag == blot_check_core::Tag.call && source.call(initializer).arguments.len == 1 { key = blot_support::some(named.value.call.key); receiver = source.call(initializer).arguments[0]; } },_=>{},
    }
    if !key.present || key.value.count != 1 || key.value.effects[0] != 0 || key.value.dictionaries || key.value.templates != 0 || key.value.template_result { return blot_support::none<Plan>(),Error.none; } let producer .= generator.unit(key.value.target.unit); if !blot_backend_collection_iteration::cursorNext(producer,key.value.target.binding,source,sink.constructor) || source.nominal(source.constructor(sink.constructor).nominal).is_opaque { return blot_support::none<Plan>(),Error.none; }
    let cursor = generator.representations.store.node(key.value.parameters[0]); if cursor.tag != blot_backend_layout::Tag.cursor { return blot_support::none<Plan>(),Error.none; } let collection = generator.representations.store.node(cursor.a); if collection.tag != blot_backend_layout::Tag.array && collection.tag != blot_backend_layout::Tag.list { return blot_support::none<Plan>(),Error.none; } let words,word_error = generator.collectionRowWords(cursor.a); if word_error != Error.none { return blot_support::none<Plan>(),word_error; } if words != 0 { return blot_support::none<Plan>(),Error.none; }
    let evidence,evidence_error = generator.representations.toEvidence(generator.evaluator.evidenceStore(),key.value.parameters[0]); if evidence_error != Error.none { if evidence_error == Error.out_of_memory { return blot_support::none<Plan>(),evidence_error; } return blot_support::none<Plan>(),Error.none; }
    let pattern = source.node(sink.pattern); let fields = source.patternChildren(source.pattern(pattern.a).b); let expected = [collection.a,key.value.parameters[0]]; for field,index in fields { let item = source.pattern(field); if item.tag == blot_check_core::PatternTag.bind { let concrete,error = codeLayout(owner,item.ty,source.span(id)); if error != Error.none { return blot_support::none<Plan>(),error; } if concrete != expected[index] { return blot_support::none<Plan>(),Error.none; } } }
    if generator.artifacts != null { let read = generator.artifacts.readInlineBody(key.value.target); if read != Error.none { return blot_support::none<Plan>(),read; } } let matched = preparePattern(owner,body,pattern.a,depth + 1); if matched != Error.none { return blot_support::none<Plan>(),matched; }
    let value = prepareNode(owner,body,pattern.b,depth + 1,false); if value != Error.none { return blot_support::none<Plan>(),value; } let fallback = prepareNode(owner,body,pattern.c,depth + 1,false); if fallback != Error.none { return blot_support::none<Plan>(),fallback; }
    if sink.pattern != id { let saved = generator.planning.bodies.put(body,sink.pattern,Plan.collection_pattern); if saved != Error.none { return blot_support::none<Plan>(),saved; } } owner.has_collection_steps = true; return blot_support::some(Plan.collection_step { sink.pattern,receiver,key.value }),Error.none;
}
recursive fn emitCollectionStep(owner: Owner&,id: u32,depth: i64) -> bool,Error {
    assert(owner.body.present); let generator .= owner.generator; if !generator.planning.bodies.contains(owner.body.value,id) { return false,Error.none; }
    match resolvedPlan(owner,id) { collection_step plan=>{
        let producer .= generator.unit(plan.key.target.unit); let producer_body .= producer.body(plan.key.target.binding); assert(producer_body != null); var mappings = MappingBuffer {}; defer { mappings.deinit(); } var rows = RowBuffer {}; defer { rows.deinit(); }
        let service,service_error = generator.specializer(); if service_error != Error.none { return false,service_error; } let resolved,resolved_error = service.named(plan.key,generator.representations.instance_arguments.get(plan.key.instance_arguments),mappings,rows); if resolved_error != Error.none { return false,generator.specializationFailure(service,resolved_error); }
        let private = privateCursorReference(owner,plan.receiver); var receiver: u32 = 0; if private.present { receiver = private.value.values[0]; } else { let value,error = capture(owner,plan.receiver,depth + 1); if error != Error.none { return false,error; } receiver = value; }
        let context,context_error = inlineContext(owner); if context_error != Error.none { return false,context_error; } let cleanups,cleanup_error = blot_runtime_runtime_cleanup::initPooled(owner.cleanups); if cleanup_error != Error.none { return false,cleanup_error; } var emitter = Owner { generator,unit_id: plan.key.target.unit,function_id: owner.function_id,provider_local: owner.provider_local,mappings: mappings.items,row_mappings: rows.items,cleanups,diagnostic_context: context,labels: owner.labels }; defer { emitter.deinit(); }
        let parameter = producer.bodyParameters(producer_body)[0].binding; emitter.locals.insert(parameter,receiver); if private.present { emitter.small_values.insert(parameter,private.value); } let prepared,prepared_error = prepareBody(emitter,producer_body.root,depth + 1,false); if prepared_error != Error.none { return false,prepared_error; } defer { generator.planning.bodies.release(prepared); } emitter.body = blot_support::some(prepared); emitter.analysis_root = producer_body.root;
        let root = producer.node(producer_body.root); let predicate = expression(emitter,root.a,depth + 1); if predicate != Error.none { return false,predicate; } let branch = emit(owner,blot_backend_runtime_ir::OP_if_); if branch != Error.none { return false,branch; } owner.labels++; emitter.labels = owner.labels;
        let source .= generator.unit(owner.unit_id); let pattern = source.node(plan.pattern); let fields = source.patternChildren(source.pattern(pattern.a).b); let values = producer.children(producer.node(root.b).b);
        for field,index in fields { let bound = source.pattern(field); if index == 1 && private.present { let next,error = advancePrivateCursor(emitter,private.value,generator.representations.store.listInput(plan.key.parameters[0])); if error != Error.none { return false,error; } if bound.tag == blot_check_core::PatternTag.bind { let saved = savePrivateCursor(owner,bound.a,next); if saved != Error.none { return false,saved; } } }
            else { let evaluated = expression(emitter,values[index],depth + 1); if evaluated != Error.none { return false,evaluated; } var saved: Error; if bound.tag == blot_check_core::PatternTag.bind { saved = save(owner,bound.a,plan.pattern); } else { saved = emit(owner,blot_backend_runtime_ir::OP_drop); } if saved != Error.none { return false,saved; } }
        }
        let alternate = emit(owner,blot_backend_runtime_ir::OP_else_); if alternate != Error.none { return false,alternate; } if pattern.c == 0 { let trap = emit(owner,blot_backend_runtime_ir::OP_unreachable_); if trap != Error.none { return false,trap; } } else { let exits,error = suite(owner,pattern.c,depth + 1); if error != Error.none { return false,error; } if !exits { return false,generator.fail(owner.unit_id,plan.pattern,blot_backend_core_backend::Code.unsupported); } }
        owner.labels--; let ended = emit(owner,blot_backend_runtime_ir::OP_end); return ended == Error.none,ended;
    },_=>{ return false,Error.none; }, }
}
fn preparePrivateCursorPattern(owner: Owner&,body: u32,id: u32) -> blot_support::Option<Plan>,Error {
    let bindings,bindings_error = prepareStaticPattern(owner,id); if bindings_error != Error.none { return blot_support::none<Plan>(),bindings_error; } if bindings.present { return blot_support::some(Plan.pattern { bindings }),Error.none; } let fallback = blot_support::some(Plan.pattern { blot_support::none<StaticBinding[:]> () });
    let generator .= owner.generator; let source .= generator.unit(owner.unit_id); let node = source.node(id); if source.pattern(node.a).tag != blot_check_core::PatternTag.product || source.node(node.b).tag != blot_check_core::Tag.array_op || source.arrayOperation(node.b) != blot_backend_collection_ops::Op.cursor_value { return fallback,Error.none; } let operand = source.children(node.b)[0]; if source.node(operand).tag != blot_check_core::Tag.reference { return fallback,Error.none; }
    let reference = source.reference(operand); let concrete,error = codeLayout(owner,source.typeOf(operand),source.span(id)); if error != Error.none { return blot_support::none<Plan>(),error; } let cursor = generator.representations.store.node(concrete); if (reference.unit != 0 && reference.unit != owner.unit_id) || cursor.tag != blot_backend_layout::Tag.cursor || generator.representations.store.node(cursor.a).tag != blot_backend_layout::Tag.list { return fallback,Error.none; }
    let words,word_error = generator.collectionRowWords(cursor.a); if word_error != Error.none { return blot_support::none<Plan>(),word_error; } let row = generator.representations.store.node(cursor.a).a; if words == 0 || generator.representations.store.node(row).tag != blot_backend_layout::Tag.product || source.patternChildren(node.a).len != words { return fallback,Error.none; }
    let uses,uses_error = generator.unitUses(owner.unit_id,blot_backend_unit_index::Need { flow: true }); if uses_error != Error.none { return blot_support::none<Plan>(),uses_error; } if !blot_backend_private_cursor::check(source,uses,generator.planning.bodies.header(body).root,reference.binding) { return fallback,Error.none; } let fields = generator.representations.store.children(row);
    for child,index in source.patternChildren(node.a) { let pattern = source.pattern(child); if pattern.tag == blot_check_core::PatternTag.wildcard { continue; } if pattern.tag != blot_check_core::PatternTag.bind { return fallback,Error.none; } let actual,error = codeLayout(owner,pattern.ty,source.span(id)); if error != Error.none { return blot_support::none<Plan>(),error; } if !generator.representations.store.scalar(actual).present || generator.representations.store.machine(actual) != generator.representations.store.machine(fields[index]) { return fallback,Error.none; } }
    return blot_support::some(Plan.private_pattern { row }),Error.none;
}
fn privateCursorConstructor(owner: Owner&,body: u32,id: u32) -> blot_support::Option<u32>,Error {
    let generator .= owner.generator; let source .= generator.unit(owner.unit_id); let node = source.node(id); if node.tag == blot_check_core::Tag.array_op { if source.arrayOperation(id) == blot_backend_collection_ops::Op.cursor { return blot_support::some(source.children(id)[0]),Error.none; } return blot_support::none<u32>(),Error.none; }
    if !generator.planning.bodies.contains(body,id) { return blot_support::none<u32>(),Error.none; } var target = blot_support::none<blot_check_core::BindingRef>(); var input: u32 = 0;
    match generator.planning.bodies.get(body,id) { named plan=>{ if plan.value.call.key.count != 1 || source.children(id).len != 1 { return blot_support::none<u32>(),Error.none; } target = blot_support::some(plan.value.call.key.target); input = source.children(id)[0]; },projection plan=>{ if plan.value.present { match plan.value.value { member member=>{ if member.direct.count != 1 { return blot_support::none<u32>(),Error.none; } target = blot_support::some(member.direct.target); input = node.a; },_=>{}, } } },_=>{}, }
    if !target.present { return blot_support::none<u32>(),Error.none; } let producer .= generator.unit(target.value.unit); let wrapper .= producer.body(target.value.binding); if wrapper == null || wrapper.parameters.len != 1 || producer.node(wrapper.root).tag != blot_check_core::Tag.array_op || producer.arrayOperation(wrapper.root) != blot_backend_collection_ops::Op.cursor { return blot_support::none<u32>(),Error.none; } let operand = producer.children(wrapper.root)[0]; if producer.node(operand).tag != blot_check_core::Tag.reference { return blot_support::none<u32>(),Error.none; } let reference = producer.reference(operand); if (reference.unit != 0 && reference.unit != target.value.unit) || reference.binding != producer.bodyParameters(wrapper)[0].binding { return blot_support::none<u32>(),Error.none; }
    if generator.artifacts != null { let read = generator.artifacts.readInlineBody(target.value); if read != Error.none { return blot_support::none<u32>(),read; } } return blot_support::some(input),Error.none;
}
fn privateCursor(owner: const Owner&,binding: u32) -> blot_support::Option<SmallCollection> { let value .= owner.small_values.get(binding); if value == null || value.kind != SmallKind.cursor { return blot_support::none<SmallCollection>(); } return blot_support::some(value); }
fn privateCursorReference(owner: const Owner&,id: u32) -> blot_support::Option<SmallCollection> { let source .= owner.generator.unit(owner.unit_id); if source.node(id).tag != blot_check_core::Tag.reference { return blot_support::none<SmallCollection>(); } let reference = source.reference(id); if reference.unit != 0 && reference.unit != owner.unit_id { return blot_support::none<SmallCollection>(); } return privateCursor(owner,reference.binding); }
fn savePrivateCursor(owner: Owner&,binding: u32,value: SmallCollection) -> Error {
    var snapshot = SmallCollection { kind: SmallKind.cursor,len: 4 }; for from,index in value.values[..4] { let local,error = temporary(owner,blot_backend_runtime_ir::VT_i32); if error != Error.none { return error; } snapshot.values[index] = local; let copied = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,from),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,local)]); if copied != Error.none { return copied; } } owner.small_values.insert(binding,snapshot); let loaded = emit(owner,blot_backend_runtime_ir::OP_local_get,snapshot.values[0]); if loaded != Error.none { return loaded; } return save(owner,binding,0);
}
enum CursorPrevious { boxed { value: u32 },fields { value: u32[2] } }
fn privateCursorRow(owner: Owner&,statement: u32,row: u32) -> blot_support::Option<RowView>,Error {
    let generator .= owner.generator; let source .= generator.unit(owner.unit_id); let binding = source.node(statement); let operand = source.children(binding.b)[0]; let selected = privateCursorReference(owner,operand); if !selected.present { return blot_support::none<RowView>(),Error.none; } let cursor = selected.value;
    let concrete,error = codeLayout(owner,source.typeOf(operand),source.span(statement)); if error != Error.none { return blot_support::none<RowView>(),error; } let input = generator.representations.store.node(concrete); let words = blot_backend_packed_layout::rowWords(generator.representations.store,row); let address,address_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if address_error != Error.none { return blot_support::none<RowView>(),address_error; } assert(generator.representations.store.node(input.a).tag == blot_backend_layout::Tag.list);
    let bounds = privateCursorBounds(owner,cursor.values[0],cursor.values[1],words); if bounds != Error.none { return blot_support::none<RowView>(),bounds; }
    let located = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,cursor.values[2]),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,cursor.values[1]),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,cursor.values[3]),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_sub),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,4),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_mul),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_add),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,blot_runtime_list_runtime::header),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_add),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,address)]); if located != Error.none { return blot_support::none<RowView>(),located; } return blot_support::some(RowView { 0,row,address,address }),Error.none;
}
fn bindPrivateRow(owner: Owner&,statement: u32) -> bool,Error {
    if !owner.body.present || !owner.generator.planning.bodies.contains(owner.body.value,statement) { return false,Error.none; }
    match owner.generator.planning.bodies.get(owner.body.value,statement) { private_row plan=>{ let selected,error = privateCursorRow(owner,statement,plan.value); if error != Error.none || !selected.present { return false,error; } var view = selected.value; view.binding = owner.generator.unit(owner.unit_id).node(statement).a; let appended = owner.row_views.push(view); return appended == Error.none,appended; },_=>{ return false,Error.none; }, }
}
recursive fn bindPrivateCursor(owner: Owner&,statement: u32,depth: i64) -> bool,Error {
    let generator .= owner.generator; let source .= generator.unit(owner.unit_id); let node = source.node(statement); if !owner.body.present || !generator.planning.bodies.contains(owner.body.value,statement) { return false,Error.none; }
    match generator.planning.bodies.get(owner.body.value,statement) { private_cursor plan=>{
        let previous_cursor = privateCursorReference(owner,node.b); if previous_cursor.present { let saved = savePrivateCursor(owner,node.a,previous_cursor.value); return saved == Error.none,saved; }
        let value_node = source.node(node.b); let concrete,error = codeLayout(owner,source.binding(node.a).ty,source.span(statement)); if error != Error.none { return false,error; } let cursor = generator.representations.store.node(concrete); let is_list = generator.representations.store.node(cursor.a).tag == blot_backend_layout::Tag.list; let row_words,row_error = generator.collectionRowWords(cursor.a); if row_error != Error.none { return false,row_error; } let words = max(1,row_words);
        var collection: u32 = 0; let index,index_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if index_error != Error.none { return false,index_error; } var previous = blot_support::none<CursorPrevious>();
        if plan.input != 0 {
            let held,held_error = capture(owner,plan.input,depth); if held_error != Error.none { return false,held_error; } collection = held;
            if is_list { let loaded = emit(owner,blot_backend_runtime_ir::OP_local_get,collection); if loaded != Error.none { return false,loaded; } let snapshot,snapshot_error = generator.module.ensureListSnapshot(); if snapshot_error != Error.none { return false,snapshot_error; } let copied = emit(owner,blot_backend_runtime_ir::OP_call,snapshot); if copied != Error.none { return false,copied; } let local,local_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if local_error != Error.none { return false,local_error; } collection = local; let stored = emit(owner,blot_backend_runtime_ir::OP_local_set,collection); if stored != Error.none { return false,stored; } }
            let zero = emit(owner,blot_backend_runtime_ir::OP_i32_const,0); if zero != Error.none { return false,zero; }
        } else if value_node.tag == blot_check_core::Tag.array_op && source.arrayOperation(node.b) == blot_backend_collection_ops::Op.cursor_advance {
            let value = privateCursorReference(owner,source.children(node.b)[0]); if !value.present { return false,Error.none; } collection = value.value.values[0]; let bounds = privateCursorBounds(owner,collection,value.value.values[1],words); if bounds != Error.none { return false,bounds; }
            let advanced = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,value.value.values[1]),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,words),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_add)]); if advanced != Error.none { return false,advanced; } previous = blot_support::some(CursorPrevious.fields { [value.value.values[2],value.value.values[3]] });
        } else {
            let boxed,boxed_error = capture(owner,node.b,depth); if boxed_error != Error.none { return false,boxed_error; } var fields = SmallCollection { kind: SmallKind.cursor,len: 4 }; let offsets = [blot_runtime_runtime_layout::Cursor_collection,blot_runtime_runtime_layout::Cursor_index,blot_runtime_runtime_layout::Cursor_leaf,blot_runtime_runtime_layout::Cursor_base];
            for offset,field in offsets { let local,local_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if local_error != Error.none { return false,local_error; } fields.values[field] = local; let loaded = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,boxed),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,offset),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,local)]); if loaded != Error.none { return false,loaded; } }
            let rooted = rootDirective(owner,5,fields.values[0]); if rooted != Error.none { return false,rooted; } let saved = savePrivateCursor(owner,node.a,fields); return saved == Error.none,saved;
        }
        let stored = emit(owner,blot_backend_runtime_ir::OP_local_set,index); if stored != Error.none { return false,stored; }
        if plan.linear.present { let directory,directory_error = startCursorDirectory(owner,collection); if directory_error != Error.none { return false,directory_error; } owner.cursor_directories.insert(plan.linear.value.advance,directory); let fields,field_error = cursorDirectoryFields(owner,collection,index,directory); if field_error != Error.none { return false,field_error; } let saved = savePrivateCursor(owner,node.a,fields); return saved == Error.none,saved; }
        { let directory .= owner.cursor_directories.get(statement); if directory != null { let fields,field_error = cursorDirectoryFields(owner,collection,index,directory); if field_error != Error.none { return false,field_error; } let saved = savePrivateCursor(owner,node.a,fields); return saved == Error.none,saved; } }
        let fields,field_error = cursorFields(owner,collection,index,is_list,previous,1); if field_error != Error.none { return false,field_error; } let saved = savePrivateCursor(owner,node.a,fields); return saved == Error.none,saved;
    },_=>{ return false,Error.none; }, }
}
fn startCursorDirectory(owner: Owner&,collection: u32) -> CursorDirectory,Error {
    var span: u32[3]; for &field in span { let local,error = temporary(owner,blot_backend_runtime_ir::VT_i32); if error != Error.none { return CursorDirectory { ListDirectory { 0,0,0 },span },error; } field = local; let initialized = emitConstantLocal(owner,0,field); if initialized != Error.none { return CursorDirectory { ListDirectory { 0,0,0 },span },initialized; } }
    let length,length_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if length_error != Error.none { return CursorDirectory { ListDirectory { 0,0,0 },span },length_error; } let loaded = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,collection),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,blot_runtime_runtime_layout::ListDescriptor_length),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,length)]); if loaded != Error.none { return CursorDirectory { ListDirectory { 0,0,0 },span },loaded; }
    let directory,error = loopListDirectory(owner,collection,length); if error != Error.none { return CursorDirectory { directory,span },error; } let rooted = openRootScope(owner); if rooted != Error.none { return CursorDirectory { directory,span },rooted; } return CursorDirectory { directory,span },Error.none;
}
fn cursorDirectoryFields(owner: Owner&,collection: u32,index: u32,cursor: CursorDirectory) -> SmallCollection,Error {
    var fields = SmallCollection { kind: SmallKind.cursor,len: 4 }; let error = emitInstructions(owner,[
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,index),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,collection),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,blot_runtime_runtime_layout::ListDescriptor_length),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_lt_u),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_if_),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,index),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,cursor.span[2]),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_ge_u),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_if_),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,cursor.directory.array),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,cursor.directory.offset),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_add),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,blot_runtime_runtime_layout::Array_bytes),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,cursor.span[0]),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,cursor.directory.offset),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,4),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_add),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,cursor.directory.offset),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,cursor.span[2]),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_tee,cursor.span[1]),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,cursor.span[0]),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,blot_runtime_runtime_layout::ListNode_length),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_add),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,cursor.span[2]),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_end),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_end)]);
    if error != Error.none { return fields,error; } fields.values[0] = collection; fields.values[1] = index; fields.values[2] = cursor.span[0]; fields.values[3] = cursor.span[1]; return fields,Error.none;
}
fn smallCollectionCandidate(owner: const Owner&,id: u32) -> bool {
    let source .= owner.generator.unit(owner.unit_id); let node = source.node(id); if node.tag == blot_check_core::Tag.reference { if source.types.node(node.ty).tag == blot_check_types::Tag.cursor { return false; } let reference = source.reference(id); if reference.unit != 0 && reference.unit != owner.unit_id { return false; } let value .= owner.small_values.get(reference.binding); return value != null && value.kind == SmallKind.collection; }
    let ty = source.types.node(node.ty).tag; if ty != blot_check_types::Tag.array && ty != blot_check_types::Tag.list { return false; } match source.types.node(source.types.node(node.ty).a).tag { unit,boolean,unsigned32,floating32,variable=>{},_=>{ return false; }, }
    if node.tag == blot_check_core::Tag.array { return source.children(id).len <= blot_backend_function_facts::small_limit; } if node.tag != blot_check_core::Tag.call { return false; } let call = source.call(id); var target = call.target; if target.unit == 0 { target.unit = owner.unit_id; }
    for iteration in 0..16 { if target.unit == 0 || target.unit > owner.generator.units.len { return false; } let producer .= owner.generator.unit(target.unit); if target.binding == 0 || target.binding >= producer.bindings.len { return false; } let binding = producer.binding(target.binding); if binding.kind == blot_check_core::BindingKind.external { let unit = target.unit; target = binding.target; if target.unit == 0 { target.unit = unit; } continue; } let body .= producer.body(target.binding); if body == null { return false; } return body.is_function && body.parameters.len == call.arguments.len && producer.node(body.root).tag == blot_check_core::Tag.array && producer.children(body.root).len <= blot_backend_function_facts::small_limit; } return false;
}
recursive fn captureSmallCollection(owner: Owner&,id: u32,depth: i64) -> blot_support::Option<SmallCollection>,Error {
    if !smallCollectionCandidate(owner,id) { return blot_support::none<SmallCollection>(),Error.none; } let generator .= owner.generator; let source .= generator.unit(owner.unit_id); let node = source.node(id); if node.tag == blot_check_core::Tag.reference { let value .= owner.small_values.get(source.reference(id).binding); assert(value != null); return blot_support::some(value),Error.none; }
    let concrete,error = codeLayout(owner,node.ty,source.span(id)); if error != Error.none { return blot_support::none<SmallCollection>(),error; } let ty = generator.representations.store.node(concrete); if (ty.tag != blot_backend_layout::Tag.array && ty.tag != blot_backend_layout::Tag.list) || !generator.representations.store.scalar(ty.a).present { return blot_support::none<SmallCollection>(),Error.none; } var result = SmallCollection { machine: generator.representations.store.machine(ty.a) };
    if node.tag == blot_check_core::Tag.array { let children = source.children(id); result.len = children.len; for child,index in children { let value,value_error = capture(owner,child,depth); if value_error != Error.none { return blot_support::none<SmallCollection>(),value_error; } result.values[index] = value; } generator.planning.facts.stats.small_collections++; return blot_support::some(result),Error.none; }
    let call = source.call(id); var key = Key {}; match resolvedPlan(owner,id) { named plan=>{ key = plan.value.call.key; },_=>{ assert(false); }, } let producer .= generator.unit(key.target.unit); let body .= producer.body(key.target.binding); if body == null || producer.node(body.root).tag != blot_check_core::Tag.array || producer.children(body.root).len > blot_backend_function_facts::small_limit || call.arguments.len != key.count { return blot_support::none<SmallCollection>(),Error.none; }
    let slot,slot_error = allocateSmallOutput(result); if slot_error != Error.none { return blot_support::none<SmallCollection>(),slot_error; } let inlined,inline_error = inlineNamedValuesMode(owner,key,call.arguments,blot_support::none<const u32[:]>(),depth,blot_support::some(slot)); result = small_outputs[slot - 1].value; releaseSmallOutput(slot); if inline_error != Error.none || !inlined { return blot_support::none<SmallCollection>(),inline_error; } let dropped = emit(owner,blot_backend_runtime_ir::OP_drop); if dropped != Error.none { return blot_support::none<SmallCollection>(),dropped; } return blot_support::some(result),Error.none;
}
recursive fn smallCollectionElement(owner: Owner&,values: SmallCollection,index: u32,start: i64,end: i64) -> Error { if start == end { return emit(owner,blot_backend_runtime_ir::OP_unreachable_); } if end - start == 1 { return emit(owner,blot_backend_runtime_ir::OP_local_get,values.values[start]); } let middle = start + (end - start) / 2;
    let condition = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,index),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,middle as u32),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_lt_u),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_if_,values.machine as u32)]); if condition != Error.none { return condition; } let left = smallCollectionElement(owner,values,index,start,middle); if left != Error.none { return left; } let alternate = emit(owner,blot_backend_runtime_ir::OP_else_); if alternate != Error.none { return alternate; } let right = smallCollectionElement(owner,values,index,middle,end); if right != Error.none { return right; } return emit(owner,blot_backend_runtime_ir::OP_end);
}
fn listKind(owner: Owner&,scalar_words: u32,element: u32) -> u32,Error { if scalar_words != 0 { return scalar_words,Error.none; } let acyclic,error = owner.generator.acyclicLayout(element); if error != Error.none { return 0,error; } if !acyclic { return scalar_words,Error.none; } return blot_runtime_list_runtime::acyclic_kind,Error.none; }
recursive fn array(owner: Owner&,id: u32,depth: i64) -> Error {
    let generator .= owner.generator; let source .= generator.unit(owner.unit_id); if owner.exact_build.present && owner.exact_build.value.plan.initial == id { return emit(owner,blot_backend_runtime_ir::OP_local_get,owner.exact_build.value.storage); }
    if owner.small_result.slot != 0 && owner.small_result.root == id { let result,error = captureSmallCollection(owner,id,depth); if error != Error.none { return error; } assert(result.present); assert(small_outputs[owner.small_result.slot - 1].live); small_outputs[owner.small_result.slot - 1].value = result.value; return emit(owner,blot_backend_runtime_ir::OP_i32_const,0); }
    let children = source.children(id); if children.len > 1073741822 { return generator.fail(owner.unit_id,id,blot_backend_core_backend::Code.complexity); } var locals = WordBuffer {}; 
    recursive fn cleanup_continuation_10() -> Error {

    for child in children { let local,error = capture(owner,child,depth); if error != Error.none { return error; } let appended = locals.push(local); if appended != Error.none { return appended; } if source.types.node(source.typeOf(child)).tag == blot_check_types::Tag.never { return Error.none; } }
    let concrete,error = codeLayout(owner,source.typeOf(id),source.span(id)); if error != Error.none { return error; } var collection = generator.representations.store.node(concrete); if collection.tag == blot_backend_layout::Tag.owning { collection = generator.representations.store.node(collection.a); } let row_words,row_error = generator.rowWords(collection.a); if row_error != Error.none { return row_error; } let scalar_elements = row_words != 0 || generator.representations.store.scalar(collection.a).present;
    if collection.tag == blot_backend_layout::Tag.list {
        let runtime,runtime_error = generator.module.ensureLists(); if runtime_error != Error.none { return runtime_error; } let address,address_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if address_error != Error.none { return address_error; } if children.len > 268435456 / max(1,row_words) { return generator.fail(owner.unit_id,id,blot_backend_core_backend::Code.complexity); }
        let length = emit(owner,blot_backend_runtime_ir::OP_i32_const,(children.len * max(1,row_words)) as u32); if length != Error.none { return length; } var scalar_words: u32 = 0; if scalar_elements { scalar_words = max(1,row_words); } let kind,kind_error = listKind(owner,scalar_words,collection.a); if kind_error != Error.none { return kind_error; }
        let allocated = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,kind),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,blot_runtime_list_runtime::leafLimit(max(1,row_words))),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_call,runtime.new),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,address)]); if allocated != Error.none { return allocated; }
        for child,index in children { let value = locals.items[index]; if row_words != 0 { let position,position_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if position_error != Error.none { return position_error; } let initialized = emitConstantLocal(owner,index as u32,position); if initialized != Error.none { return initialized; } let stored = storeListRow(owner,address,position,value,row_words,collection.a); if stored != Error.none { return stored; } continue; }
            let located = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,address),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,index as u32),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_call,runtime.address),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,value)]); if located != Error.none { return located; } let scalar_type,scalar_error = scalar(owner,child); if scalar_error != Error.none { return scalar_error; } let machine = blot_backend_runtime_ir::machine(scalar_type); var store = blot_backend_runtime_ir::OP_i32_store; if machine == blot_backend_runtime_ir::VT_f32 { store = blot_backend_runtime_ir::OP_f32_store; } var stored: Error;
            if scalar_elements { stored = storeScalar(owner,store,0); } else if generator.layoutRole(collection.a) == blot_backend_runtime_ir::ROLE_reference { stored = storeCollectionWord(owner,address,true,machine,0); } else { stored = emit(owner,store,0); } if stored != Error.none { return stored; }
        } return emit(owner,blot_backend_runtime_ir::OP_local_get,address);
    }
    let stride = blot_backend_packed_layout::stride(row_words); if children.len > (4294967295 - 4) / stride { return generator.fail(owner.unit_id,id,blot_backend_core_backend::Code.complexity); } let address,address_error = allocateStorage(owner,(children.len * stride + 4) as u32,scalar_elements || row_words != 0,AllocationRoles { words: [blot_backend_runtime_ir::ROLE_scalar],rest: generator.layoutRole(collection.a) }); if address_error != Error.none { return address_error; }
    if !scalar_elements && row_words == 0 && generator.layoutRole(collection.a) == blot_backend_runtime_ir::ROLE_reference { let acyclic = markAcyclic(owner,address,collection.a); if acyclic != Error.none { return acyclic; } } let length = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,address),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,children.len as u32),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_store,0)]); if length != Error.none { return length; }
    for child,index in children { let loaded = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,address),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,locals.items[index])]); if loaded != Error.none { return loaded; } let scalar_type,scalar_error = scalar(owner,child); if scalar_error != Error.none { return scalar_error; } let stored = storeElement(owner,blot_backend_runtime_ir::machine(scalar_type),(index * stride + 4) as u32,row_words,scalar_elements,collection.a); if stored != Error.none { return stored; } } return emit(owner,blot_backend_runtime_ir::OP_local_get,address);

    }
    let cleanup_result_10_0 = cleanup_continuation_10();
     locals.deinit(); 
    return cleanup_result_10_0;
}
fn arrayAddress(owner: Owner&,array: u32,index: u32,stride: u32) -> Error { return emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,array),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,index),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,stride),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_mul),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_add)]); }
type NumericPlan = blot_backend_numeric_rows::Plan;
recursive fn rowGuard(owner: Owner&,plan: const NumericPlan&,guard: blot_support::Option<u8>,objects: blot_support::Option<const u32[:]>,fields: const u32[:]) -> i64,Error {
    if !guard.present { return 0,Error.none; } let condition = plan.guards[guard.value]; let depth,error = rowGuard(owner,plan,condition.parent,objects,fields); if error != Error.none { return 0,error; }
    if objects.present { let loaded = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,objects.value[condition.owner]),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,0)]); if loaded != Error.none { return 0,loaded; } }
    else { let loaded = emit(owner,blot_backend_runtime_ir::OP_local_get,fields[condition.word]); if loaded != Error.none { return 0,loaded; } }
    let entered = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,condition.tag),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_eq),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_if_)]); if entered != Error.none { return 0,entered; } return depth + 1,Error.none;
}
fn rowGuardEnd(owner: Owner&,count: i64) -> Error { for index in 0..count { let ended = emit(owner,blot_backend_runtime_ir::OP_end); if ended != Error.none { return ended; } } return Error.none; }
fn validateRowTags(owner: Owner&,plan: const NumericPlan&,fields: const u32[:]) -> Error {
    for leaf in plan.leaves[..plan.leaf_count] { if !leaf.discriminant { continue; } let blocks,error = rowGuard(owner,plan,leaf.guard,blot_support::none<const u32[:]>(),fields); if error != Error.none { return error; } var first = true;
        for guard in plan.guards[..plan.guard_count] { if guard.owner != leaf.owner || guard.word != leaf.word { continue; } let compared = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,fields[leaf.word]),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,guard.tag),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_eq)]); if compared != Error.none { return compared; } if !first { let joined = emit(owner,blot_backend_runtime_ir::OP_i32_or); if joined != Error.none { return joined; } } first = false; }
        assert(!first); let checked = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_eqz),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_if_),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_unreachable_),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_end)]); if checked != Error.none { return checked; } let ended = rowGuardEnd(owner,blocks); if ended != Error.none { return ended; }
    } return Error.none;
}
fn unpackRow(owner: Owner&,fields: const u32[:],element: u32) -> Error {
    let selected,error = owner.generator.nestedRow(element); if error != Error.none { return error; }
    if !selected.present { let row,row_error = allocateStorage(owner,(fields.len * 4) as u32,true,AllocationRoles { rest: blot_backend_runtime_ir::ROLE_scalar }); if row_error != Error.none { return row_error; } for field,index in fields { let stored = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,row),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,field),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_store,(index * 4) as u32)]); if stored != Error.none { return stored; } } return emit(owner,blot_backend_runtime_ir::OP_local_get,row); }
    let plan = selected.value; assert(fields.len == plan.word_count); let valid = validateRowTags(owner,plan,fields); if valid != Error.none { return valid; } var objects: u32[32];
    for storage,index in plan.storage[..plan.storage_count] { if storage.guard.present || storage.unit_payload { let local,local_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if local_error != Error.none { return local_error; } objects[index] = local; } }
    var result = blot_support::none<u32>(); if plan.storage[0].guard.present { let local,local_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if local_error != Error.none { return local_error; } result = blot_support::some(local); } var next = plan.storage_count as i64;
    while next > 0 {
        next--; let storage = plan.storage[next]; let blocks,guard_error = rowGuard(owner,plan,storage.guard,blot_support::none<const u32[:]>(),fields); if guard_error != Error.none { return guard_error; }
        if storage.unit_payload {
            assert(storage.tag.present); let constant = nullaryConstructor(owner,storage.tag.value); if constant != Error.none { return constant; } let stored = emit(owner,blot_backend_runtime_ir::OP_local_set,objects[next]); if stored != Error.none { return stored; }
            if !storage.parent.present && result.present { let published = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,objects[next]),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,result.value)]); if published != Error.none { return published; } }
            let ended = rowGuardEnd(owner,blocks); if ended != Error.none { return ended; } continue;
        }
        var roles: blot_backend_runtime_ir::Role[16]; for index in 0..storage.bytes / 4 { roles[index] = blot_backend_runtime_ir::ROLE_scalar; if (storage.references & ((1 as u16) << index as u32)) != 0 { roles[index] = blot_backend_runtime_ir::ROLE_reference; } }
        let object,allocation_error = allocateStorage(owner,storage.bytes,storage.references == 0,AllocationRoles { words: roles[..storage.bytes / 4],rest: blot_backend_runtime_ir::ROLE_scalar }); if allocation_error != Error.none { return allocation_error; }
        if storage.tag.present { let tagged = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,object),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,storage.tag.value),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_store,0)]); if tagged != Error.none { return tagged; } }
        for leaf in plan.leaves[..plan.leaf_count] { if leaf.owner != next || leaf.discriminant { continue; } let stored = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,object),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,fields[leaf.word]),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_store,leaf.offset)]); if stored != Error.none { return stored; } }
        for child,index in plan.storage[..plan.storage_count] { if !child.parent.present || child.parent.value != next { continue; } let active,active_error = rowGuard(owner,plan,child.guard,blot_support::none<const u32[:]>(),fields); if active_error != Error.none { return active_error; } let stored = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,object),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,objects[index]),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_store,child.offset)]); if stored != Error.none { return stored; } let ended = rowGuardEnd(owner,active); if ended != Error.none { return ended; } }
        if storage.references != 0 { let marked = markAcyclic(owner,object,storage.layout); if marked != Error.none { return marked; } }
        if storage.guard.present { let published = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,object),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,objects[next])]); if published != Error.none { return published; } } else { objects[next] = object; }
        if !storage.parent.present && result.present { let published = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,object),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,result.value)]); if published != Error.none { return published; } }
        let ended = rowGuardEnd(owner,blocks); if ended != Error.none { return ended; }
    }
    var output = objects[0]; if result.present { output = result.value; } return emit(owner,blot_backend_runtime_ir::OP_local_get,output);
}
fn packRow(owner: Owner&,row: u32,words: u32,element: u32) -> u32[16],Error {
    var fields: u32[16]; for &field in fields[..words] { let local,error = temporary(owner,blot_backend_runtime_ir::VT_i32); if error != Error.none { return fields,error; } field = local; }
    let selected,error = owner.generator.nestedRow(element); if error != Error.none { return fields,error; }
    if selected.present {
        let plan = selected.value; assert(words == plan.word_count); if plan.guard_count != 0 { for field in fields[..words] { let cleared = emitConstantLocal(owner,0,field); if cleared != Error.none { return fields,cleared; } } }
        var objects: u32[32];
        for storage,index in plan.storage[..plan.storage_count] {
            let local,local_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if local_error != Error.none { return fields,local_error; } objects[index] = local; var blocks: i64 = 0;
            if storage.parent.present { let parent = storage.parent.value; let entered,entered_error = rowGuard(owner,plan,plan.storage[parent].guard,blot_support::some<const u32[:]>(objects),[]); if entered_error != Error.none { return fields,entered_error; } blocks = entered; let loaded = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,objects[parent]),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,storage.offset)]); if loaded != Error.none { return fields,loaded; } }
            else { let loaded = emit(owner,blot_backend_runtime_ir::OP_local_get,row); if loaded != Error.none { return fields,loaded; } } let stored = emit(owner,blot_backend_runtime_ir::OP_local_set,objects[index]); if stored != Error.none { return fields,stored; } let ended = rowGuardEnd(owner,blocks); if ended != Error.none { return fields,ended; }
        }
        for leaf in plan.leaves[..plan.leaf_count] { let blocks,guard_error = rowGuard(owner,plan,leaf.guard,blot_support::some<const u32[:]>(objects),[]); if guard_error != Error.none { return fields,guard_error; } let loaded = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,objects[leaf.owner]),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,leaf.offset),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,fields[leaf.word])]); if loaded != Error.none { return fields,loaded; } let ended = rowGuardEnd(owner,blocks); if ended != Error.none { return fields,ended; } }
        let valid = validateRowTags(owner,plan,fields[..words]); if valid != Error.none { return fields,valid; }
    } else { for field,index in fields[..words] { let loaded = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,row),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,(index * 4) as u32),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,field)]); if loaded != Error.none { return fields,loaded; } } }
    return fields,Error.none;
}
fn readElement(owner: Owner&,machine: blot_backend_runtime_ir::ValueType,offset: u32,row_words: u32,element: u32) -> Error {
    if row_words == 0 { var load = blot_backend_runtime_ir::OP_i32_load; if machine == blot_backend_runtime_ir::VT_f32 { load = blot_backend_runtime_ir::OP_f32_load; } return emit(owner,load,offset); }
    let source,source_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if source_error != Error.none { return source_error; } let saved = emit(owner,blot_backend_runtime_ir::OP_local_set,source); if saved != Error.none { return saved; } let nested,nested_error = owner.generator.nestedRow(element); if nested_error != Error.none { return nested_error; }
    if !nested.present { let row,error = allocateStorage(owner,row_words * 4,true,AllocationRoles { rest: blot_backend_runtime_ir::ROLE_scalar }); if error != Error.none { return error; } for index in 0..row_words { let field = index as u32 * 4; let loaded = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,row),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,source),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,offset + field),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_store,field)]); if loaded != Error.none { return loaded; } } return emit(owner,blot_backend_runtime_ir::OP_local_get,row); }
    var fields: u32[16]; for index in 0..row_words { let local,error = temporary(owner,blot_backend_runtime_ir::VT_i32); if error != Error.none { return error; } fields[index] = local; let loaded = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,source),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,offset + index as u32 * 4),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,local)]); if loaded != Error.none { return loaded; } } return unpackRow(owner,fields[..row_words],element);
}
fn storeScalar(owner: Owner&,op: blot_backend_runtime_ir::Op,offset: u32) -> Error { let marker = owner.generator.module.emit(owner.function_id,blot_backend_runtime_ir::scalarStore(blot_backend_runtime_ir::fixed(op).bytes)); if marker != Error.none { return marker; } return emit(owner,op,offset); }
fn storeElement(owner: Owner&,machine: blot_backend_runtime_ir::ValueType,offset: u32,row_words: u32,scalar_element: bool,element: u32) -> Error {
    if row_words == 0 { var op = blot_backend_runtime_ir::OP_i32_store; if machine == blot_backend_runtime_ir::VT_f32 { op = blot_backend_runtime_ir::OP_f32_store; } if scalar_element { return storeScalar(owner,op,offset); } return emit(owner,op,offset); }
    let row,error = temporary(owner,blot_backend_runtime_ir::VT_i32); if error != Error.none { return error; } let destination,destination_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if destination_error != Error.none { return destination_error; }
    let saved = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,row),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,destination)]); if saved != Error.none { return saved; } let nested,nested_error = owner.generator.nestedRow(element); if nested_error != Error.none { return nested_error; } var fields = blot_support::none<u32[16]>();
    if nested.present { let packed,packed_error = packRow(owner,row,row_words,element); if packed_error != Error.none { return packed_error; } fields = blot_support::some(packed); }
    for index in 0..row_words { let field = index as u32 * 4; let target = emit(owner,blot_backend_runtime_ir::OP_local_get,destination); if target != Error.none { return target; } if fields.present { let loaded = emit(owner,blot_backend_runtime_ir::OP_local_get,fields.value[index]); if loaded != Error.none { return loaded; } }
        else { let loaded = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,row),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,field)]); if loaded != Error.none { return loaded; } } let stored = storeScalar(owner,blot_backend_runtime_ir::OP_i32_store,offset + field); if stored != Error.none { return stored; }
    } return Error.none;
}
fn arrayBounds(owner: Owner&,array: u32,index: u32) -> Error { return emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,index),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,array),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,0),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_ge_u),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_if_),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_unreachable_),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_end)]); }
fn simdArrayBounds(owner: Owner&,array: u32,index: u32) -> Error { let length,error = temporary(owner,blot_backend_runtime_ir::VT_i32); if error != Error.none { return error; } return emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,array),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,0),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_tee,length),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,4),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_lt_u),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,index),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,length),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,4),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_sub),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_gt_u),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_or),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_if_),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_unreachable_),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_end)]); }
fn copyScalarArray(owner: Owner&,source: u32) -> u32,Error {
    let changed,error = temporary(owner,blot_backend_runtime_ir::VT_i32); if error != Error.none { return 0,error; } let count,count_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if count_error != Error.none { return 0,count_error; } let counted = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,source),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,0),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,count)]); if counted != Error.none { return 0,counted; }
    let size,size_error = arraySize(owner,count,4); if size_error != Error.none { return 0,size_error; } let length = emit(owner,blot_backend_runtime_ir::OP_local_get,size); if length != Error.none { return 0,length; } let allocated = allocateArray(owner,true,blot_support::none<u32>()); if allocated != Error.none { return 0,allocated; }
    let prepared = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,changed),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,changed),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,changed),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,source),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,size)]); if prepared != Error.none { return 0,prepared; } let arena,arena_error = owner.generator.module.ensureArena(); if arena_error != Error.none { return 0,arena_error; } let copied = emit(owner,blot_backend_runtime_ir::OP_call,arena.copy_words); return changed,copied;
}
fn arraySize(owner: Owner&,count: u32,stride: u32) -> u32,Error {
    let checked = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,count),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,(4294967295 - 4) / stride),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_gt_u),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_if_),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_unreachable_),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_end)]); if checked != Error.none { return 0,checked; }
    let size,error = temporary(owner,blot_backend_runtime_ir::VT_i32); if error != Error.none { return 0,error; } let count_loaded = emit(owner,blot_backend_runtime_ir::OP_local_get,count); if count_loaded != Error.none { return 0,count_loaded; }
    var computed: Error; if stride == 4 { computed = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,1),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_add),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,4),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_mul)]); }
    else { computed = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,stride),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_mul),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,4),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_add)]); } if computed != Error.none { return 0,computed; } let stored = emit(owner,blot_backend_runtime_ir::OP_local_set,size); return size,stored;
}
fn allocateArray(owner: Owner&,scalar_elements: bool,element: u32) -> Error { return allocateArray(owner,scalar_elements,blot_support::some(element)); }
fn allocateArray(owner: Owner&,scalar_elements: bool,element: blot_support::Option<u32>) -> Error {
    let arena,error = owner.generator.module.ensureArena(); if error != Error.none { return error; } if scalar_elements { return emit(owner,blot_backend_runtime_ir::OP_call,arena.allocate_scalar); } let allocated = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,4294967294),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_call,arena.allocate_typed)]); if allocated != Error.none { return allocated; } if !element.present { return Error.none; }
    let acyclic,acyclic_error = owner.generator.acyclicLayout(element.value); if acyclic_error != Error.none { return acyclic_error; } if !acyclic { return Error.none; } let array,array_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if array_error != Error.none { return array_error; } return emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_tee,array),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_call,arena.mark_acyclic),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,array)]);
}
fn storeCollectionWord(owner: Owner&,collection: u32,is_list: bool,machine: blot_backend_runtime_ir::ValueType,offset: u32) -> Error {
    let value,error = temporary(owner,blot_backend_runtime_ir::VT_i32); if error != Error.none { return error; } let address,address_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if address_error != Error.none { return address_error; }
    if machine == blot_backend_runtime_ir::VT_f32 { let bits = emit(owner,blot_backend_runtime_ir::OP_i32_reinterpret_f32); if bits != Error.none { return bits; } } let saved = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,value),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,address),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,collection)]); if saved != Error.none { return saved; }
    if is_list { let leaf = emit(owner,blot_backend_runtime_ir::OP_i32_load,blot_runtime_runtime_layout::ListDescriptor_cached_leaf); if leaf != Error.none { return leaf; } } let loaded = emit(owner,blot_backend_runtime_ir::OP_local_get,address); if loaded != Error.none { return loaded; }
    if offset != 0 { let adjusted = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,offset),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_add)]); if adjusted != Error.none { return adjusted; } } let bits = emit(owner,blot_backend_runtime_ir::OP_local_get,value); if bits != Error.none { return bits; } let arena,arena_error = owner.generator.module.ensureArena(); if arena_error != Error.none { return arena_error; } return emit(owner,blot_backend_runtime_ir::OP_call,arena.store_word);
}
struct PackedProducer { template: Template,ty: u32 }
fn sameOptional<T>(left: blot_support::Option<T>,right: blot_support::Option<T>) -> bool { if left.present != right.present { return false; } return !left.present || left.value == right.value; }
recursive fn packedValue(owner: Owner&,encoding: bool,id: u32,plan: const NumericPlan&,parent: blot_support::Option<u8>,offset: u32,fields: const u32[:],depth: i64) -> bool,Error {
    if depth >= 64 { return false,Error.none; } let generator .= owner.generator; let source .= generator.unit(owner.unit_id);
    for leaf in plan.leaves[..plan.leaf_count] { if leaf.discriminant || !parent.present || parent.value != leaf.owner || offset != leaf.offset { continue; }
        if encoding { if id == 0 { let zero = emit(owner,blot_backend_runtime_ir::OP_i32_const,0); if zero != Error.none { return false,zero; } } else { let value = expression(owner,id,depth + 1); if value != Error.none { return false,value; } if leaf.floating { let bits = emit(owner,blot_backend_runtime_ir::OP_i32_reinterpret_f32); if bits != Error.none { return false,bits; } } } let saved = emit(owner,blot_backend_runtime_ir::OP_local_set,fields[leaf.word]); if saved != Error.none { return false,saved; } } return true,Error.none;
    }
    if id == 0 { return false,Error.none; } let node = source.node(id);
    if node.tag == blot_check_core::Tag.if_value {
        if encoding { let condition = expression(owner,node.a,depth + 1); if condition != Error.none { return false,condition; } let branch = emit(owner,blot_backend_runtime_ir::OP_if_); if branch != Error.none { return false,branch; } owner.labels++; }
        let left,left_error = packedValue(owner,encoding,node.b,plan,parent,offset,fields,depth + 1); if left_error != Error.none || !left { return false,left_error; } if encoding { let alternate = emit(owner,blot_backend_runtime_ir::OP_else_); if alternate != Error.none { return false,alternate; } }
        let right,right_error = packedValue(owner,encoding,node.c,plan,parent,offset,fields,depth + 1); if right_error != Error.none || !right { return false,right_error; } if encoding { owner.labels--; let ended = emit(owner,blot_backend_runtime_ir::OP_end); if ended != Error.none { return false,ended; } } return true,Error.none;
    }
    if node.tag != blot_check_core::Tag.construct && node.tag != blot_check_core::Tag.record && node.tag != blot_check_core::Tag.product { return false,Error.none; } var tag = blot_support::none<u32>(); if node.tag == blot_check_core::Tag.construct { tag = blot_support::some(source.constructor(node.a).tag); }
    var selected = blot_support::none<u8>(); for storage,index in plan.storage[..plan.storage_count] { if sameOptional(storage.parent,parent) && storage.offset == offset && sameOptional(storage.tag,tag) { selected = blot_support::some(index as u8); break; } } if !selected.present { return false,Error.none; }
    if node.tag == blot_check_core::Tag.construct {
        if encoding && plan.storage[selected.value].guard.present { let active = plan.storage[selected.value].guard.value; let guard = plan.guards[active]; if guard.owner == selected.value || (sameOptional(plan.storage[guard.owner].parent,parent) && plan.storage[guard.owner].offset == offset) { assert(tag.present); let written = emitConstantLocal(owner,tag.value,fields[guard.word]); if written != Error.none { return false,written; } } }
        return packedValue(owner,encoding,node.b,plan,selected,4,fields,depth + 1);
    }
    let children = source.children(id); let record = node.tag == blot_check_core::Tag.record; var destinations: const u32[:] = []; if record { destinations = source.recordDestinations(id); } var physical = WordBuffer {}; 
    recursive fn cleanup_continuation_9() -> bool,Error {
 if record { let ordered = physicalOrder(owner,source.types.node(source.typeOf(id)),physical); if ordered != Error.none { return false,ordered; } }
    for child,index in children { var declared = index as u32; if record { declared = destinations[index]; } var slot = declared; if physical.items.len != 0 { slot = physical.items[declared]; } let admitted,error = packedValue(owner,encoding,child,plan,selected,slot * 4,fields,depth + 1); if error != Error.none || !admitted { return false,error; } } return true,Error.none;

    }
    let cleanup_result_9_0,cleanup_result_9_1 = cleanup_continuation_9();
     physical.deinit(); 
    return cleanup_result_9_0,cleanup_result_9_1;
}
recursive fn generatedPackedRow(owner: Owner&,producer: PackedProducer,index: u32,destination: u32,is_list: bool,plan: const NumericPlan&) -> bool,Error {
    let generator .= owner.generator; if owner.inline_depth >= 6 || producer.template.templates != 0 || producer.template.staged != 0 || producer.template.callable_instances != 0 || owner.dictionary_owner.present { return false,Error.none; } var unit = producer.template.unit; if unit == 0 { unit = owner.unit_id; } let source .= generator.unit(unit); let node = source.node(producer.template.node); let arrow = generator.representations.store.node(producer.ty);
    var mappings = MappingBuffer {}; 
    recursive fn cleanup_continuation_8() -> bool,Error {
 var rows = RowBuffer {}; 
    recursive fn cleanup_continuation_7() -> bool,Error {
 let context,context_error = inlineContext(owner); if context_error != Error.none { return false,context_error; } let cleanups,cleanup_error = blot_runtime_runtime_cleanup::initPooled(owner.cleanups); if cleanup_error != Error.none { return false,cleanup_error; }
    var emitter = Owner { generator,unit_id: unit,function_id: owner.function_id,provider_local: owner.provider_local,mappings: [],cleanups,diagnostic_context: context,labels: owner.labels,inline_depth: owner.inline_depth + 1,inline_loop: true }; 
    recursive fn cleanup_continuation_6() -> bool,Error {
 var root: u32 = 0;
    if node.tag == blot_check_core::Tag.reference {
        let target,error = generator.normalize(unit,source.reference(producer.template.node)); if error != Error.none { return false,error; } let target_source .= generator.unit(target.unit); let body .= target_source.body(target.binding); if body == null || body.parameters.len != 1 || !body.is_function { return false,Error.none; } let cost = blot_backend_inline_body::cost(target_source,body.root); if !cost.present || cost.value > 64 { return false,Error.none; }
        var key = Key { target,count: 1,result: arrow.b }; key.parameters[0] = arrow.a; key.effects[0] = arrow.c; let service,service_error = generator.specializer(); if service_error != Error.none { return false,service_error; } let resolved,resolved_error = service.named(key,[],mappings,rows); if resolved_error != Error.none { return false,generator.specializationFailure(service,resolved_error); }
        emitter.unit_id = target.unit; root = body.root; emitter.locals.insert(target_source.bodyParameters(body)[0].binding,index); if generator.artifacts != null { let read = generator.artifacts.readInlineBody(target); if read != Error.none { return false,read; } }
    } else if node.tag == blot_check_core::Tag.closure {
        let closure = source.closures[node.a]; let cost = blot_backend_inline_body::cost(source,closure.body); if !cost.present || cost.value > 64 { return false,Error.none; } let key = blot_reuse_code_artifacts::ClosureKey { unit,catalog: node.a,ty: producer.ty,captures: producer.template.captures,scalar_environment: producer.template.scalar_environment,evidence: producer.template.evidence,rows: producer.template.rows }; let resolved = generator.resolveClosureMappings(key,mappings,rows); if resolved != Error.none { return false,resolved; } root = closure.body; emitter.locals.insert(closure.parameter.binding,index);
    } else { return false,Error.none; }
    emitter.mappings = mappings.items; emitter.row_mappings = rows.items; let supported,supported_error = packedValue(emitter,false,root,plan,blot_support::none<u8>(),0,[],0); if supported_error != Error.none || !supported { return false,supported_error; }
    if node.tag == blot_check_core::Tag.closure { let closure = source.closures[node.a]; for binding,position in source.extra[closure.captures.start..closure.captures.start + closure.captures.len] { let concrete = generator.representations.store.children(producer.template.captures)[position]; let machine = generator.representations.store.machine(concrete); let local,error = temporary(owner,machine); if error != Error.none { return false,error; } assert(producer.template.environment.present); let environment = emit(owner,blot_backend_runtime_ir::OP_local_get,producer.template.environment.value); if environment != Error.none { return false,environment; }
        if !producer.template.scalar_environment { var load = blot_backend_runtime_ir::OP_i32_load; if machine == blot_backend_runtime_ir::VT_f32 { load = blot_backend_runtime_ir::OP_f32_load; } let loaded = emit(owner,load,(position * 4) as u32); if loaded != Error.none { return false,loaded; } } let stored = emit(owner,blot_backend_runtime_ir::OP_local_set,local); if stored != Error.none { return false,stored; } emitter.locals.insert(binding,local);
    } }
    let body,body_error = prepareBody(emitter,root,0,false); if body_error != Error.none { return false,body_error; } 
    recursive fn cleanup_continuation_5() -> bool,Error {
 emitter.body = blot_support::some(body); emitter.analysis_root = root; let header = generator.planning.bodies.header(body); emitter.mappings = header.mappings; emitter.row_mappings = header.rows;
    var fields: u32[16]; for &field in fields[..plan.word_count] { let local,error = temporary(owner,blot_backend_runtime_ir::VT_i32); if error != Error.none { return false,error; } field = local; let initialized = emitConstantLocal(owner,0,field); if initialized != Error.none { return false,initialized; } }
    let packed,packed_error = packedValue(emitter,true,root,plan,blot_support::none<u8>(),0,fields[..plan.word_count],0); if packed_error != Error.none { return false,packed_error; } assert(packed); var base: u32 = 0; if is_list { let selected,selected_error = multiplyLocal(owner,index,plan.word_count); if selected_error != Error.none { return false,selected_error; } base = selected; }
    for field,position in fields[..plan.word_count] { var address: Error; if is_list { address = listWordAddress(owner,destination,base,position as u32,false); } else { address = arrayAddress(owner,destination,index,plan.word_count as u32 * 4); } if address != Error.none { return false,address; } let loaded = emit(owner,blot_backend_runtime_ir::OP_local_get,field); if loaded != Error.none { return false,loaded; } var offset: u32 = 0; if !is_list { offset = 4 + position as u32 * 4; } let stored = storeScalar(owner,blot_backend_runtime_ir::OP_i32_store,offset); if stored != Error.none { return false,stored; } } return true,Error.none;

    }
    let cleanup_result_5_0,cleanup_result_5_1 = cleanup_continuation_5();
     generator.planning.bodies.release(body); 
    return cleanup_result_5_0,cleanup_result_5_1;

    }
    let cleanup_result_6_0,cleanup_result_6_1 = cleanup_continuation_6();
     emitter.deinit(); 
    return cleanup_result_6_0,cleanup_result_6_1;

    }
    let cleanup_result_7_0,cleanup_result_7_1 = cleanup_continuation_7();
     rows.deinit(); 
    return cleanup_result_7_0,cleanup_result_7_1;

    }
    let cleanup_result_8_0,cleanup_result_8_1 = cleanup_continuation_8();
     mappings.deinit(); 
    return cleanup_result_8_0,cleanup_result_8_1;
}
recursive fn arrayFill(owner: Owner&,count: u32,value: u32,machine: blot_backend_runtime_ir::ValueType,is_generated: bool,is_list: bool,known: blot_support::Option<u32>,element: u32,producer: blot_support::Option<PackedProducer>) -> Error {
    let generator .= owner.generator; let row_words,row_error = generator.rowWords(element); if row_error != Error.none { return row_error; } var copied_row_scope = false; if is_generated { let nested,error = generator.nestedRow(element); if error != Error.none { return error; } copied_row_scope = nested.present; }
    let iteration_cleanup = owner.cleanups.mark(); 
    recursive fn cleanup_continuation_4() -> Error {
 let stride = blot_backend_packed_layout::stride(row_words); let scalar_elements = row_words != 0 || generator.representations.store.scalar(element).present;
    let size,size_error = arraySize(owner,count,stride); if size_error != Error.none { return size_error; } let array,array_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if array_error != Error.none { return array_error; } let index,index_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if index_error != Error.none { return index_error; } var physical = count;
    if is_list && row_words > 1 { let words,error = listWordCount(owner,count,row_words); if error != Error.none { return error; } physical = words; } var length = size; if is_list { length = physical; } let loaded = emit(owner,blot_backend_runtime_ir::OP_local_get,length); if loaded != Error.none { return loaded; }
    if is_list { var scalar_words: u32 = 0; if scalar_elements { scalar_words = max(1,row_words); } let kind,error = listKind(owner,scalar_words,element); if error != Error.none { return error; } let prepared = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,kind),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,blot_runtime_list_runtime::leafLimit(max(1,row_words)))]); if prepared != Error.none { return prepared; } }
    var allocated: Error; if is_list { let runtime,error = generator.module.ensureLists(); if error != Error.none { return error; } allocated = emit(owner,blot_backend_runtime_ir::OP_call,runtime.new); } else { allocated = allocateArray(owner,scalar_elements,element); } if allocated != Error.none { return allocated; }
    let saved = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,array),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,array)]); if saved != Error.none { return saved; } var logical_length = count; if is_list { logical_length = physical; } let counted = emit(owner,blot_backend_runtime_ir::OP_local_get,logical_length); if counted != Error.none { return counted; }
    var stored: Error; if is_list { stored = storeCollectionWord(owner,array,false,blot_backend_runtime_ir::VT_i32,0); } else { stored = emit(owner,blot_backend_runtime_ir::OP_i32_store,0); } if stored != Error.none { return stored; }
    let initialized = emitConstantLocal(owner,0,index); if initialized != Error.none { return initialized; } let entered = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_block),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_loop)]); if entered != Error.none { return entered; } owner.labels += 2;
    let bounded = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,index),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,count),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_ge_u),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_br_if,1)]); if bounded != Error.none { return bounded; }
    var chunk_end = blot_support::none<u32>();
    if copied_row_scope {
        let rooted = openRootScope(owner); if rooted != Error.none { return rooted; } let local,error = temporary(owner,blot_backend_runtime_ir::VT_i32); if error != Error.none { return error; } chunk_end = blot_support::some(local);
        let chunked = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,index),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,32),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_add),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_tee,local),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,count),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_gt_u),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_if_),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,count),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,local),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_end),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_loop)]); if chunked != Error.none { return chunked; } owner.labels++;
    }
    var direct = false; if producer.present { let nested,error = generator.nestedRow(element); if error != Error.none { return error; } if nested.present && nested.value.guard_count != 0 { let generated,generated_error = generatedPackedRow(owner,producer.value,index,array,is_list,nested.value); if generated_error != Error.none { return generated_error; } direct = generated; } }
    if !direct {
        if is_list && row_words == 0 { let loaded = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,array),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,index)]); if loaded != Error.none { return loaded; } let runtime,error = generator.module.ensureLists(); if error != Error.none { return error; } let address = emit(owner,blot_backend_runtime_ir::OP_call,runtime.address); if address != Error.none { return address; } }
        else if !is_list { let address = arrayAddress(owner,array,index,stride); if address != Error.none { return address; } }
        if known.present { let loaded = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,value),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,index)]); if loaded != Error.none { return loaded; } let provider = providerHead(owner); if provider != Error.none { return provider; } let called = emit(owner,blot_backend_runtime_ir::OP_call,known.value); if called != Error.none { return called; } }
        else if is_generated { let signature,error = generator.module.internType([blot_backend_runtime_ir::VT_i32,blot_backend_runtime_ir::VT_i32,blot_backend_runtime_ir::VT_i32],machine); if error != Error.none { return error; } let environment = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,value),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,4),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,index)]); if environment != Error.none { return environment; } let provider = providerHead(owner); if provider != Error.none { return provider; } let called = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,value),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,0),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_call_indirect,signature)]); if called != Error.none { return called; } }
        else { let loaded = emit(owner,blot_backend_runtime_ir::OP_local_get,value); if loaded != Error.none { return loaded; } }
        var stored: Error; if is_list && row_words != 0 { let row,error = temporary(owner,blot_backend_runtime_ir::VT_i32); if error != Error.none { return error; } let saved = emit(owner,blot_backend_runtime_ir::OP_local_set,row); if saved != Error.none { return saved; } stored = storeListRow(owner,array,index,row,row_words,element); }
        else if is_list { stored = storeCollectionWord(owner,array,true,machine,0); } else if !scalar_elements { stored = storeCollectionWord(owner,array,false,machine,4); } else { stored = storeElement(owner,machine,4,row_words,scalar_elements,element); } if stored != Error.none { return stored; }
    }
    let advanced = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,index),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,1),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_add),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,index)]); if advanced != Error.none { return advanced; }
    if copied_row_scope { assert(chunk_end.present); let repeated = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,index),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,chunk_end.value),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_lt_u),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_br_if,0)]); if repeated != Error.none { return repeated; } owner.labels--; let ended = emit(owner,blot_backend_runtime_ir::OP_end); if ended != Error.none { return ended; } let cleaned = cleanupTo(owner,iteration_cleanup); if cleaned != Error.none { return cleaned; } owner.cleanups.restore(iteration_cleanup); }
    let repeated = emit(owner,blot_backend_runtime_ir::OP_br,0); if repeated != Error.none { return repeated; } owner.labels -= 2; return emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_end),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_end),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,array)]);

    }
    let cleanup_result_4_0 = cleanup_continuation_4();
     if copied_row_scope { owner.cleanups.restore(iteration_cleanup); } 
    return cleanup_result_4_0;
}
fn advancePrivateCursor(owner: Owner&,fields: SmallCollection,is_list: bool) -> SmallCollection,Error {
    let bounds = privateCursorBounds(owner,fields.values[0],fields.values[1],1); if bounds != Error.none { return SmallCollection {},bounds; } let index,error = temporary(owner,blot_backend_runtime_ir::VT_i32); if error != Error.none { return SmallCollection {},error; } let advanced = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,fields.values[1]),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,1),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_add),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,index)]); if advanced != Error.none { return SmallCollection {},advanced; } return cursorFields(owner,fields.values[0],index,is_list,blot_support::some(CursorPrevious.fields { [fields.values[2],fields.values[3]] }),1);
}
fn privateCursorOperation(owner: Owner&,id: u32) -> bool,Error {
    let generator .= owner.generator; let source .= generator.unit(owner.unit_id); let op = source.arrayOperation(id); if op != blot_backend_collection_ops::Op.cursor_has && op != blot_backend_collection_ops::Op.cursor_value { return false,Error.none; } let operand = source.children(id)[0]; let selected = privateCursorReference(owner,operand); if !selected.present { return false,Error.none; } let cursor = selected.value;
    let concrete,error = codeLayout(owner,source.typeOf(operand),source.span(id)); if error != Error.none { return false,error; } let input = generator.representations.store.node(concrete); let collection = generator.representations.store.node(input.a); let words,word_error = generator.collectionRowWords(input.a); if word_error != Error.none { return false,word_error; }
    if words == 0 {
        if op == blot_backend_collection_ops::Op.cursor_has { let remaining = privateCursorRemaining(owner,cursor.values[0],cursor.values[1]); if remaining != Error.none { return false,remaining; } let checked = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,1),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_ge_u)]); if checked != Error.none { return false,checked; } }
        else { let bounds = privateCursorBounds(owner,cursor.values[0],cursor.values[1],1); if bounds != Error.none { return false,bounds; } var address: Error; var offset: u32 = 4; if collection.tag == blot_backend_layout::Tag.list { address = cachedListWordAddress(owner,cursor.values[0],cursor.values[1],0,[cursor.values[2],cursor.values[3]]); offset = 0; } else { address = arrayAddress(owner,cursor.values[0],cursor.values[1],4); } if address != Error.none { return false,address; } let loaded = readElement(owner,generator.representations.store.machine(collection.a),offset,0,collection.a); if loaded != Error.none { return false,loaded; } }
        return true,Error.none;
    }
    assert(collection.tag == blot_backend_layout::Tag.list); if op == blot_backend_collection_ops::Op.cursor_has { let remaining = privateCursorRemaining(owner,cursor.values[0],cursor.values[1]); if remaining != Error.none { return false,remaining; } let checked = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,words),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_ge_u)]); if checked != Error.none { return false,checked; } }
    else { let bounds = privateCursorBounds(owner,cursor.values[0],cursor.values[1],words); if bounds != Error.none { return false,bounds; } let index,index_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if index_error != Error.none { return false,index_error; }
        let logical = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,cursor.values[1]),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,words),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_div_u),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,index)]); if logical != Error.none { return false,logical; } let loaded = readListRow(owner,cursor.values[0],index,words,blot_support::some([cursor.values[2],cursor.values[3]]),blot_support::none<u32>(),collection.a); if loaded != Error.none { return false,loaded; }
    } return true,Error.none;
}
recursive fn arrayOperation(owner: Owner&,id: u32,depth: i64) -> Error {
    let generator .= owner.generator; let source .= generator.unit(owner.unit_id); let operands = source.children(id); let private,error = privateCursorOperation(owner,id); if error != Error.none || private { return error; } if operands.len > 3 { return generator.fail(owner.unit_id,id,blot_backend_core_backend::Code.unsupported); }
    if owner.ragged_count.present { let probe = owner.ragged_count.value; if probe.plan.storage.conversion == id { return expression(owner,operands[0],depth + 1); } if probe.plan.storage.append == id { let checked = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,probe.count),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,probe.limit),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_ge_u)]); if checked != Error.none { return checked; } let declined = declineRaggedCount(owner); if declined != Error.none { return declined; }
        return emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,probe.count),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,1),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_add),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,probe.count),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,0)]);
    } }
    if owner.exact_build.present { let builder = owner.exact_build.value; if builder.plan.conversion == id { return expression(owner,operands[0],depth + 1); } if builder.plan.append == id {
        let value,value_error = capture(owner,operands[1],depth); if value_error != Error.none { return value_error; } let element,element_error = codeLayout(owner,source.typeOf(operands[1]),source.span(operands[1])); if element_error != Error.none { return element_error; } let role = generator.layoutRole(element); let machine = generator.representations.store.machine(element); let is_list = builder.plan.conversion == 0;
        if is_list && builder.row_words != 0 { let stored = storeListRow(owner,builder.storage,builder.index,value,builder.row_words,element); if stored != Error.none { return stored; } }
        else { if is_list { let loaded = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,builder.storage),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,builder.index)]); if loaded != Error.none { return loaded; } let runtime,runtime_error = generator.module.ensureLists(); if runtime_error != Error.none { return runtime_error; } let address = emit(owner,blot_backend_runtime_ir::OP_call,runtime.address); if address != Error.none { return address; } }
            else { let address = arrayAddress(owner,builder.storage,builder.index,blot_backend_packed_layout::stride(builder.row_words)); if address != Error.none { return address; } } let loaded = emit(owner,blot_backend_runtime_ir::OP_local_get,value); if loaded != Error.none { return loaded; } var offset: u32 = 4; if is_list { offset = 0; } var stored: Error;
            if builder.row_words == 0 && role == blot_backend_runtime_ir::ROLE_reference { stored = storeCollectionWord(owner,builder.storage,is_list,machine,offset); } else { stored = storeElement(owner,machine,offset,builder.row_words,role == blot_backend_runtime_ir::ROLE_scalar,element); } if stored != Error.none { return stored; }
        }
        return emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,builder.index),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,1),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_add),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,builder.index),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,builder.storage)]);
    } }
    if source.arrayOperation(id) == blot_backend_collection_ops::Op.length { let values,value_error = captureSmallCollection(owner,operands[0],depth); if value_error != Error.none { return value_error; } if values.present { return emit(owner,blot_backend_runtime_ir::OP_i32_const,values.value.len as u32); } }
    if source.arrayOperation(id) == blot_backend_collection_ops::Op.generate && owner.static_values.table.count == 0 && isCallableTemplate(owner,operands[1]) {
        let count,count_error = capture(owner,operands[0],depth); if count_error != Error.none { return count_error; } let callable,callable_error = callableTemplate(owner,operands[1]); if callable_error != Error.none { return callable_error; } assert(callable.present); let template,template_error = boxTemplate(owner,callable.value); if template_error != Error.none { return template_error; }
        let callback,callback_error = codeLayout(owner,source.typeOf(operands[1]),source.span(id)); if callback_error != Error.none { return callback_error; } let result,result_error = codeLayout(owner,source.typeOf(id),source.span(id)); if result_error != Error.none { return result_error; } var environment: u32 = 0;
        if template.environment.present { environment = template.environment.value; } else { let local,local_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if local_error != Error.none { return local_error; } let initialized = emitConstantLocal(owner,0,local); if initialized != Error.none { return initialized; } environment = local; }
        let function,function_error = templateFunction(owner,template,callback,false); if function_error != Error.none { return function_error; } let collection = generator.representations.store.node(result); return arrayFill(owner,count,environment,generator.representations.store.machine(collection.a),true,collection.tag == blot_backend_layout::Tag.list,blot_support::some(function),collection.a,blot_support::some(PackedProducer { template,callback }));
    }
    var locals: u32[3]; var machines: blot_backend_runtime_ir::ValueType[3]; for operand,index in operands { let local,local_error = capture(owner,operand,depth); if local_error != Error.none { return local_error; } locals[index] = local; let scalar_type,scalar_error = scalar(owner,operand); if scalar_error != Error.none { return scalar_error; } machines[index] = blot_backend_runtime_ir::machine(scalar_type); }
    let result,result_error = codeLayout(owner,source.typeOf(id),source.span(id)); if result_error != Error.none { return result_error; } let source_layout,source_error = codeLayout(owner,source.typeOf(operands[0]),source.span(id)); if source_error != Error.none { return source_error; } return arrayLocals(owner,id,source.arrayOperation(id),locals[..operands.len],machines[..operands.len],result,source_layout);
}
recursive fn exactBuilder(owner: Owner&,id: u32,plan: blot_backend_exact_builder::Plan,depth: i64) -> Error {
    let generator .= owner.generator; let source .= generator.unit(owner.unit_id); let concrete,error = codeLayout(owner,source.typeOf(plan.initial),source.span(id)); if error != Error.none { return error; } let collection = generator.representations.store.node(concrete); let is_list = plan.conversion == 0; let row_words,row_error = generator.rowWords(collection.a); if row_error != Error.none { return row_error; } let stride = blot_backend_packed_layout::stride(row_words); var limit: u32 = min(268435456,(4294967295 - 4) / stride); if is_list { limit = 268435456 / max(1,row_words); }
    let count,count_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if count_error != Error.none { return count_error; } let eligible,eligible_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if eligible_error != Error.none { return eligible_error; } let counted = emitConstantLocal(owner,1,count); if counted != Error.none { return counted; } let admitted = emitConstantLocal(owner,1,eligible); if admitted != Error.none { return admitted; }
    for loop_id in plan.loops[..plan.loop_count] {
        let loop = source.loopInfo(loop_id); let length,length_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if length_error != Error.none { return length_error; }
        if loop.kind == blot_check_core::LoopKind.range { let first,first_error = capture(owner,loop.first,depth); if first_error != Error.none { return first_error; } let end,end_error = capture(owner,loop.end,depth); if end_error != Error.none { return end_error; }
            let measured = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,end),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,first),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_gt_u),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_if_,blot_backend_runtime_ir::VT_i32 as u32),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,end),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,first),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_sub),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_else_),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,0),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_end)]); if measured != Error.none { return measured; }
        } else { let small,small_error = captureSmallCollection(owner,loop.first,depth); if small_error != Error.none { return small_error; } if small.present { let measured = emit(owner,blot_backend_runtime_ir::OP_i32_const,small.value.len as u32); if measured != Error.none { return measured; } }
            else { let evaluated = expression(owner,loop.first,depth + 1); if evaluated != Error.none { return evaluated; } let loaded = emit(owner,blot_backend_runtime_ir::OP_i32_load,0); if loaded != Error.none { return loaded; } let input,input_error = codeLayout(owner,source.typeOf(loop.first),source.span(loop.first)); if input_error != Error.none { return input_error; } let logical = logicalListLength(owner,input); if logical != Error.none { return logical; } }
        }
        let multiplied = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,length),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,count),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_if_),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,length),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,limit),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,count),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_div_u),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_gt_u),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_if_),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,0),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,eligible),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_end),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_end),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,count),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,length),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_mul),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,count)]); if multiplied != Error.none { return multiplied; }
    }
    let filled = fillExactBuilder(owner,id,plan,count,eligible,depth); if filled != Error.none { return filled; } generator.planning.facts.stats.exact_builders++; return Error.none;
}
recursive fn fillExactBuilder(owner: Owner&,id: u32,plan: blot_backend_exact_builder::Plan,count: u32,eligible: u32,depth: i64) -> Error {
    let generator .= owner.generator; let source .= generator.unit(owner.unit_id); let concrete,error = codeLayout(owner,source.typeOf(plan.initial),source.span(id)); if error != Error.none { return error; } let collection = generator.representations.store.node(concrete); let is_list = plan.conversion == 0; let row_words,row_error = generator.rowWords(collection.a); if row_error != Error.none { return row_error; } let stride = blot_backend_packed_layout::stride(row_words);
    let previous_probe = owner.exact_probe; let previous_build = owner.exact_build; owner.exact_probe = true; 
    recursive fn cleanup_continuation_3() -> Error {

    let selected = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,eligible),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_if_,blot_backend_runtime_ir::VT_i32 as u32)]); if selected != Error.none { return selected; } owner.labels++; let scalar_elements = row_words != 0 || generator.representations.store.scalar(collection.a).present; var size = count;
    if is_list { if row_words > 1 { let words,word_error = listWordCount(owner,count,row_words); if word_error != Error.none { return word_error; } size = words; } } else { let bytes,byte_error = arraySize(owner,count,stride); if byte_error != Error.none { return byte_error; } size = bytes; }
    let storage,storage_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if storage_error != Error.none { return storage_error; } let loaded = emit(owner,blot_backend_runtime_ir::OP_local_get,size); if loaded != Error.none { return loaded; }
    if is_list { var scalar_words: u32 = 0; if scalar_elements { scalar_words = max(1,row_words); } let kind,kind_error = listKind(owner,scalar_words,collection.a); if kind_error != Error.none { return kind_error; } let prepared = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,kind),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,blot_runtime_list_runtime::leafLimit(max(1,row_words)))]); if prepared != Error.none { return prepared; } }
    var allocated: Error; if is_list { let runtime,runtime_error = generator.module.ensureLists(); if runtime_error != Error.none { return runtime_error; } allocated = emit(owner,blot_backend_runtime_ir::OP_call,runtime.new); } else { allocated = allocateArray(owner,scalar_elements,collection.a); } if allocated != Error.none { return allocated; } let saved = emit(owner,blot_backend_runtime_ir::OP_local_set,storage); if saved != Error.none { return saved; }
    if !is_list { let counted = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,storage),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,count),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_store,0)]); if counted != Error.none { return counted; } }
    let index,index_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if index_error != Error.none { return index_error; } let initialized = emitConstantLocal(owner,0,index); if initialized != Error.none { return initialized; } owner.exact_build = blot_support::some(ExactBuild { plan,storage,index,row_words });
    let fast = expression(owner,id,depth + 1); if fast != Error.none { return fast; } let alternate = emit(owner,blot_backend_runtime_ir::OP_else_); if alternate != Error.none { return alternate; } owner.exact_build = previous_build; let ordinary = expression(owner,id,depth + 1); if ordinary != Error.none { return ordinary; } owner.labels--; return emit(owner,blot_backend_runtime_ir::OP_end);

    }
    let cleanup_result_3_0 = cleanup_continuation_3();
     owner.exact_probe = previous_probe; owner.exact_build = previous_build; 
    return cleanup_result_3_0;
}
struct RaggedFacts { generator: blot_backend_core_backend::Generator&,unit: u32,body: u32,templates: TemplateMap }
fn raggedFacts(owner: const Owner&) -> RaggedFacts { assert(owner.body.present); return RaggedFacts { owner.generator,owner.unit_id,owner.body.value,owner.templates }; }
fn primitive(facts: RaggedFacts,id: u32) -> bool {
    let bodies .= facts.generator.planning.bodies; if !bodies.contains(facts.body,id) { return false; }
    match bodies.get(facts.body,id) {
        named plan=>{ let key = plan.value.call.key; if key.count != 2 || key.parameters[0] != key.parameters[1] { return false; } let machine = facts.generator.representations.store.scalar(key.parameters[0]); if !machine.present { return false; } let operation = blot_check_primitive_operator::analyzeTyped(facts.generator.units,key.target,machine.value); return operation.present && blot_check_primitive_operator::total(operation.value); },
        dispatch plan=>{ match plan.value { scalar operation=>{ return true; },selected selected=>{ let operation = blot_check_primitive_operator::analyze(facts.generator.units,selected.key.target); return operation.present && blot_check_primitive_operator::total(operation.value); },_=>{ return false; }, } },_=>{ return false; },
    }
}
fn reference(facts: RaggedFacts,id: u32) -> bool {
    let source .= facts.generator.unit(facts.unit); let reference = source.reference(id); if reference.unit == 0 || reference.unit == source.unit { let binding = source.binding(reference.binding); if binding.kind == blot_check_core::BindingKind.local || binding.kind == blot_check_core::BindingKind.parameter { return !facts.templates.contains(reference.binding); } }
     match facts.generator.planning.bodies.get(facts.body,id) { reference plan=>{ if !plan.value.present { return false; } let declaration .= facts.generator.unit(plan.value.value.unit).body(plan.value.value.binding); return declaration != null && !declaration.is_function; },_=>{ assert(false); return false; }, }
}
fn field(facts: RaggedFacts,id: u32) -> bool { let bodies .= facts.generator.planning.bodies; if !bodies.contains(facts.body,id) { return false; } match bodies.get(facts.body,id) { projection plan=>{ if !plan.value.present { return false; } match plan.value.value { field value=>{ return true; },_=>{ return false; }, } },_=>{ return false; }, } }
fn pattern(facts: RaggedFacts,id: u32) -> bool { let bodies .= facts.generator.planning.bodies; if !bodies.contains(facts.body,id) { return false; } match bodies.get(facts.body,id) { loop_ plan=>{ return !plan.value.refutable; },_=>{ return false; }, } }
fn declineRaggedCount(owner: Owner&) -> Error { assert(owner.ragged_count.present); let probe = owner.ragged_count.value; let branch = emit(owner,blot_backend_runtime_ir::OP_if_); if branch != Error.none { return branch; } owner.labels++; let declined = emitConstantLocal(owner,0,probe.eligible); if declined != Error.none { return declined; } let cleaned = cleanupTo(owner,probe.cleanup); if cleaned != Error.none { return cleaned; } let exited = emit(owner,blot_backend_runtime_ir::OP_br,owner.labels - 1 - probe.exit); if exited != Error.none { return exited; } owner.labels--; return emit(owner,blot_backend_runtime_ir::OP_end); }
recursive fn raggedBuilder(owner: Owner&,id: u32,plan: blot_backend_ragged_builder::Plan,depth: i64) -> Error {
    let generator .= owner.generator; let source .= generator.unit(owner.unit_id); for expression in plan.expressions[..plan.expression_count] { let read = raggedDependencies(owner,expression); if read != Error.none { return read; } } let payload = raggedDependencies(owner,plan.storage.value); if payload != Error.none { return payload; }
    let concrete,error = codeLayout(owner,source.typeOf(plan.storage.initial),source.span(id)); if error != Error.none { return error; } let collection = generator.representations.store.node(concrete); let words,word_error = generator.rowWords(collection.a); if word_error != Error.none { return word_error; } let maximum = blot_backend_ragged_builder::maximumCount(words,plan.storage.conversion == 0); assert(maximum.present);
    let count,count_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if count_error != Error.none { return count_error; } let eligible,eligible_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if eligible_error != Error.none { return eligible_error; } let budget,budget_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if budget_error != Error.none { return budget_error; }
    let zero = emitConstantLocal(owner,0,count); if zero != Error.none { return zero; } let admitted = emitConstantLocal(owner,1,eligible); if admitted != Error.none { return admitted; } let bounded = emitConstantLocal(owner,generator.ragged_probe_limit,budget); if bounded != Error.none { return bounded; }
    let previous_probe = owner.exact_probe; let previous_count = owner.ragged_count; owner.exact_probe = true; 
    recursive fn cleanup_continuation_2() -> Error {

    let entered = emit(owner,blot_backend_runtime_ir::OP_block); if entered != Error.none { return entered; } owner.ragged_count = blot_support::some(RaggedCount { plan,count,eligible,budget,limit: maximum.value,exit: owner.labels,cleanup: owner.cleanups.mark() }); owner.labels++;
    let probed = expression(owner,id,depth + 1); if probed != Error.none { return probed; } let dropped = emit(owner,blot_backend_runtime_ir::OP_drop); if dropped != Error.none { return dropped; } owner.labels--; let ended = emit(owner,blot_backend_runtime_ir::OP_end); if ended != Error.none { return ended; } owner.ragged_count = previous_count;
    let previous_fill = owner.ragged_fill; owner.ragged_fill = true; 
    recursive fn cleanup_continuation_1() -> Error {
 let filled = fillExactBuilder(owner,id,plan.storage,count,eligible,depth); if filled != Error.none { return filled; } generator.evaluator.counters.ragged_runtime_regions++; return Error.none;

    }
    let cleanup_result_1_0 = cleanup_continuation_1();
     owner.ragged_fill = previous_fill; 
    return cleanup_result_1_0;

    }
    let cleanup_result_2_0 = cleanup_continuation_2();
     owner.exact_probe = previous_probe; owner.ragged_count = previous_count; 
    return cleanup_result_2_0;
}
recursive fn raggedDependencies(owner: Owner&,id: u32) -> Error {
    let generator .= owner.generator; if id == 0 || generator.artifacts == null { return Error.none; } let source .= generator.unit(owner.unit_id); let node = source.node(id); assert(owner.body.present); let bodies .= generator.planning.bodies;
    match node.tag {
        scalar,associated=>{ match bodies.get(owner.body.value,id) { dispatch plan=>{ match plan.value { selected selected=>{ let operation = blot_check_primitive_operator::analyze(generator.units,selected.key.target); assert(operation.present); for target in operation.value.dependencies[..operation.value.dependency_count] { let read = generator.artifacts.readInlineBody(target); if read != Error.none { return read; } } },_=>{}, } },_=>{ assert(false); }, } let left = raggedDependencies(owner,node.a); if left != Error.none { return left; } return raggedDependencies(owner,node.b); },
        call=>{ var key = Key {}; match bodies.get(owner.body.value,id) { named plan=>{ key = plan.value.call.key; },_=>{ assert(false); }, } let machine = generator.representations.store.scalar(key.parameters[0]); assert(machine.present); let operation = blot_check_primitive_operator::analyzeTyped(generator.units,key.target,machine.value); assert(operation.present); for target in operation.value.dependencies[..operation.value.dependency_count] { let read = generator.artifacts.readInlineBody(target); if read != Error.none { return read; } } for child in source.children(id) { let read = raggedDependencies(owner,child); if read != Error.none { return read; } } },
        logical=>{ let left = raggedDependencies(owner,node.a); if left != Error.none { return left; } return raggedDependencies(owner,node.b); },if_value=>{ let condition = raggedDependencies(owner,node.a); if condition != Error.none { return condition; } let left = raggedDependencies(owner,node.b); if left != Error.none { return left; } return raggedDependencies(owner,node.c); },project=>{ return raggedDependencies(owner,node.a); },array_op=>{ return raggedDependencies(owner,source.children(id)[0]); },_=>{},
    } return Error.none;
}
fn ownsEdit(owner: Owner&,id: u32) -> bool,Error { if id == 0 { return false,Error.none; } if owner.owned_edit.present && owner.owned_edit.value == id { return true,Error.none; } return owner.generator.ownsArrayUpdate(owner.unit_id,id); }
fn emitLocals(owner: Owner&,locals: const u32[:]) -> Error { for local in locals { let error = emit(owner,blot_backend_runtime_ir::OP_local_get,local); if error != Error.none { return error; } } return Error.none; }
recursive fn arrayLocals(owner: Owner&,id: u32,op: blot_backend_collection_ops::Op,locals: const u32[:],machines: const blot_backend_runtime_ir::ValueType[:],result_layout: u32,input_layout: u32) -> Error {
    let generator .= owner.generator; let result = generator.representations.store.machine(result_layout); let input_list = generator.representations.store.listInput(input_layout); let input_node = generator.representations.store.node(input_layout); var input_collection = input_layout; if input_node.tag == blot_backend_layout::Tag.cursor { input_collection = input_node.a; }
    let row_words,row_error = generator.collectionRowWords(input_collection); if row_error != Error.none { return row_error; } let stride = blot_backend_packed_layout::stride(row_words); let expected = blot_backend_collection_ops::arity(op); if locals.len == 0 || locals.len != expected || machines.len != expected { return generator.fail(owner.unit_id,id,blot_backend_core_backend::Code.unsupported); }
    match op {
        flatten=>{ return arrayFlatten(owner,locals[0],generator.representations.store.node(result_layout).a); },
        simd_load,simd_store=>{ let element = generator.representations.store.scalar(input_node.a); if !element.present || input_list || row_words != 0 || (element.value != blot_backend_runtime_ir::SC_u32 && element.value != blot_backend_runtime_ir::SC_f32 && element.value != blot_backend_runtime_ir::SC_bool) { return generator.fail(owner.unit_id,id,blot_backend_core_backend::Code.unsupported); }
            let bounds = simdArrayBounds(owner,locals[0],locals[1]); if bounds != Error.none { return bounds; }
            if op == blot_backend_collection_ops::Op.simd_load { let address,error = allocateStorage(owner,16,true,AllocationRoles { rest: blot_backend_runtime_ir::ROLE_scalar }); if error != Error.none { return error; } let target = emit(owner,blot_backend_runtime_ir::OP_local_get,address); if target != Error.none { return target; } let source = arrayAddress(owner,locals[0],locals[1],4); if source != Error.none { return source; } return emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_v128_load,4),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_v128_store,0),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,address)]); }
            let reuse,reuse_error = ownsEdit(owner,id); if reuse_error != Error.none { return reuse_error; } var changed = locals[0]; if !reuse { let copied,error = copyScalarArray(owner,locals[0]); if error != Error.none { return error; } changed = copied; } let address = arrayAddress(owner,changed,locals[1],4); if address != Error.none { return address; } let loaded = simdLoad(owner,locals[2]); if loaded != Error.none { return loaded; } let stored = storeScalar(owner,blot_backend_runtime_ir::OP_v128_store,4); if stored != Error.none { return stored; } return emit(owner,blot_backend_runtime_ir::OP_local_get,changed);
        },
        cursor=>{ return createCollectionCursor(owner,locals[0],input_list,row_words); },cursor_has,cursor_value,cursor_advance=>{ return readCollectionCursor(owner,locals[0],op,input_list,input_collection,row_words,stride,result); },
        concat,slice=>{ if input_list { if op == blot_backend_collection_ops::Op.slice && row_words != 0 { return sliceListRows(owner,locals,row_words); } let loaded = emitLocals(owner,locals); if loaded != Error.none { return loaded; } let runtime,error = generator.module.ensureLists(); if error != Error.none { return error; } var function = runtime.slice; if op == blot_backend_collection_ops::Op.concat { function = runtime.concat; } return emit(owner,blot_backend_runtime_ir::OP_call,function); }
            let element = generator.representations.store.node(result_layout).a; return arrayStructural(owner,op,locals,row_words != 0 || generator.representations.store.scalar(element).present,stride,element);
        },
        length=>{ let loaded = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,locals[0]),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,0)]); if loaded != Error.none { return loaded; } return logicalListLength(owner,input_collection); },
        get=>{ let proven,error = numericCheck(owner,id); if error != Error.none { return error; } if input_list && row_words != 0 { if !proven { let checked = listRowBounds(owner,locals[0],locals[1],row_words); if checked != Error.none { return checked; } } return readListRow(owner,locals[0],locals[1],row_words,blot_support::none<u32[2]>(),blot_support::none<u32>(),generator.representations.store.node(input_collection).a); }
            if !proven { let checked = arrayBounds(owner,locals[0],locals[1]); if checked != Error.none { return checked; } }
            if input_list { let runtime,runtime_error = generator.module.ensureLists(); if runtime_error != Error.none { return runtime_error; } var address = runtime.address; if proven { let unchecked,error = generator.module.ensureUncheckedListAddress(); if error != Error.none { return error; } address = unchecked; } let loaded = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,locals[0]),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,locals[1]),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_call,address)]); if loaded != Error.none { return loaded; } }
            else { let address = arrayAddress(owner,locals[0],locals[1],stride); if address != Error.none { return address; } } var offset: u32 = 4; if input_list { offset = 0; } return readElement(owner,result,offset,row_words,generator.representations.store.node(input_collection).a);
        },
        set=>{ let reuse,reuse_error = ownsEdit(owner,id); if reuse_error != Error.none { return reuse_error; }
            if input_list { if row_words != 0 { return editListRow(owner,locals[0],blot_support::some(locals[1]),locals[2],row_words,blot_support::none<bool>(),reuse,generator.representations.store.node(input_collection).a); } let loaded = emitLocals(owner,locals); if loaded != Error.none { return loaded; } if machines[2] == blot_backend_runtime_ir::VT_f32 { let bits = emit(owner,blot_backend_runtime_ir::OP_i32_reinterpret_f32); if bits != Error.none { return bits; } } var consuming: u32 = 0; if reuse { consuming = 1; } let flag = emit(owner,blot_backend_runtime_ir::OP_i32_const,consuming); if flag != Error.none { return flag; }
                let runtime,runtime_error = generator.module.ensureLists(); if runtime_error != Error.none { return runtime_error; } var function = runtime.set; let proven,proof_error = numericCheck(owner,id); if proof_error != Error.none { return proof_error; } if proven { let unchecked,error = generator.module.ensureUncheckedListSet(); if error != Error.none { return error; } function = unchecked; } return emit(owner,blot_backend_runtime_ir::OP_call,function);
            }
            let proven,proof_error = numericCheck(owner,id); if proof_error != Error.none { return proof_error; } if !proven { let checked = arrayBounds(owner,locals[0],locals[1]); if checked != Error.none { return checked; } } var changed = locals[0];
            if !reuse { let local,local_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if local_error != Error.none { return local_error; } changed = local; let count,count_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if count_error != Error.none { return count_error; } let counted = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,locals[0]),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,0),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,count)]); if counted != Error.none { return counted; }
                let size,size_error = arraySize(owner,count,stride); if size_error != Error.none { return size_error; } let loaded = emit(owner,blot_backend_runtime_ir::OP_local_get,size); if loaded != Error.none { return loaded; } let element = generator.representations.store.node(result_layout).a; let allocated = allocateArray(owner,row_words != 0 || generator.representations.store.scalar(element).present,element); if allocated != Error.none { return allocated; }
                let copied = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,changed),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,changed),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,changed),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,locals[0]),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,size)]); if copied != Error.none { return copied; } let arena,arena_error = generator.module.ensureArena(); if arena_error != Error.none { return arena_error; } let stored = emit(owner,blot_backend_runtime_ir::OP_call,arena.copy_words); if stored != Error.none { return stored; }
            }
            let address = arrayAddress(owner,changed,locals[1],stride); if address != Error.none { return address; } let loaded = emit(owner,blot_backend_runtime_ir::OP_local_get,locals[2]); if loaded != Error.none { return loaded; } let numeric = generator.representations.store.scalar(generator.representations.store.node(result_layout).a).present; var stored: Error;
            if row_words == 0 && !numeric { stored = storeCollectionWord(owner,changed,false,machines[2],4); } else { stored = storeElement(owner,machines[2],4,row_words,true,generator.representations.store.node(input_collection).a); } if stored != Error.none { return stored; } return emit(owner,blot_backend_runtime_ir::OP_local_get,changed);
        },
        fill=>{ let collection = generator.representations.store.node(result_layout); return arrayFill(owner,locals[0],locals[1],machines[1],false,collection.tag == blot_backend_layout::Tag.list,blot_support::none<u32>(),collection.a,blot_support::none<PackedProducer>()); },
        generate=>{ let collection = generator.representations.store.node(result_layout); return arrayFill(owner,locals[0],locals[1],generator.representations.store.machine(collection.a),true,collection.tag == blot_backend_layout::Tag.list,blot_support::none<u32>(),collection.a,blot_support::none<PackedProducer>()); },identity=>{ return emit(owner,blot_backend_runtime_ir::OP_local_get,locals[0]); },
        convert=>{ let element = generator.representations.store.node(result_layout).a; let words,error = generator.rowWords(element); if error != Error.none { return error; } if words != 0 { return convertRows(owner,locals[0],input_list,words); } let loaded = emit(owner,blot_backend_runtime_ir::OP_local_get,locals[0]); if loaded != Error.none { return loaded; } let runtime,runtime_error = generator.module.ensureLists(); if runtime_error != Error.none { return runtime_error; }
            if !input_list { var scalar_words: u32 = 0; if generator.representations.store.scalar(element).present { scalar_words = 1; } let kind,kind_error = listKind(owner,scalar_words,element); if kind_error != Error.none { return kind_error; } let described = emit(owner,blot_backend_runtime_ir::OP_i32_const,kind); if described != Error.none { return described; } } var function = runtime.from_array; if input_list { function = runtime.to_array; } return emit(owner,blot_backend_runtime_ir::OP_call,function);
        },
        append,prepend=>{ if input_list { var reuse = false; if id != 0 { let owned,error = generator.ownsArrayUpdate(owner.unit_id,id); if error != Error.none { return error; } reuse = owned; } if row_words != 0 { return editListRow(owner,locals[0],blot_support::none<u32>(),locals[1],row_words,blot_support::some(op == blot_backend_collection_ops::Op.prepend),reuse,generator.representations.store.node(input_collection).a); }
                let loaded = emitLocals(owner,locals); if loaded != Error.none { return loaded; } if machines[1] == blot_backend_runtime_ir::VT_f32 { let bits = emit(owner,blot_backend_runtime_ir::OP_i32_reinterpret_f32); if bits != Error.none { return bits; } } var front: u32 = 0; if op == blot_backend_collection_ops::Op.prepend { front = 1; } var consuming: u32 = 0; if reuse { consuming = 1; } let flags = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,front),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,consuming)]); if flags != Error.none { return flags; } let runtime,runtime_error = generator.module.ensureLists(); if runtime_error != Error.none { return runtime_error; } return emit(owner,blot_backend_runtime_ir::OP_call,runtime.push);
            }
            let element = generator.representations.store.node(result_layout).a; return arrayPush(owner,locals[0],locals[1],machines[1],op == blot_backend_collection_ops::Op.prepend,row_words != 0 || generator.representations.store.scalar(element).present,row_words,element);
        },
    }
}
fn arrayFlatten(owner: Owner&,chunks: u32,element: u32) -> Error {
    let generator .= owner.generator; let words,error = generator.rowWords(element); if error != Error.none { return error; } let stride = blot_backend_packed_layout::stride(words);
    let count,count_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if count_error != Error.none { return count_error; } let total,total_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if total_error != Error.none { return total_error; } let index,index_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if index_error != Error.none { return index_error; } let chunk,chunk_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if chunk_error != Error.none { return chunk_error; } let length,length_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if length_error != Error.none { return length_error; } let offset,offset_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if offset_error != Error.none { return offset_error; } let destination,destination_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if destination_error != Error.none { return destination_error; }
    let counted = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,chunks),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,0),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,count)]); if counted != Error.none { return counted; } let initialized = emitConstantLocal(owner,0,total); if initialized != Error.none { return initialized; }
    for copying in [false,true] {
        if copying { let bytes,byte_error = arraySize(owner,total,stride); if byte_error != Error.none { return byte_error; } let size = emit(owner,blot_backend_runtime_ir::OP_local_get,bytes); if size != Error.none { return size; } let allocated = allocateArray(owner,words != 0 || generator.representations.store.scalar(element).present,element); if allocated != Error.none { return allocated; }
            let published = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,destination),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,destination),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,total),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_store,0)]); if published != Error.none { return published; } let cleared = emitConstantLocal(owner,0,offset); if cleared != Error.none { return cleared; }
        }
        let start = emitConstantLocal(owner,0,index); if start != Error.none { return start; } let entered = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_block),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_loop)]); if entered != Error.none { return entered; } owner.labels += 2;
        let bounded = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,index),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,count),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_ge_u),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_br_if,1)]); if bounded != Error.none { return bounded; } let address = arrayAddress(owner,chunks,index,4); if address != Error.none { return address; }
        let selected = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,4),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_tee,chunk),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,0),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,length)]); if selected != Error.none { return selected; }
        if copying { let target = emit(owner,blot_backend_runtime_ir::OP_local_get,destination); if target != Error.none { return target; } let address = arrayAddress(owner,destination,offset,stride); if address != Error.none { return address; } assert(generator.module.arena.present);
            let copied = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,4),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_add),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,chunk),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,4),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_add),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,length),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,stride),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_mul),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_call,generator.module.arena.value.copy_words),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,offset),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,length),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_add),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,offset)]); if copied != Error.none { return copied; }
        } else {
            let summed = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,total),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,length),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_add),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_tee,offset),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,total),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_lt_u),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_if_),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_unreachable_),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_end),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,offset),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,total)]); if summed != Error.none { return summed; }
        }
        let advanced = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,index),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,1),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_add),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,index),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_br,0)]); if advanced != Error.none { return advanced; } owner.labels -= 2; let ended = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_end),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_end)]); if ended != Error.none { return ended; }
    }
    return emit(owner,blot_backend_runtime_ir::OP_local_get,destination);
}
fn createCollectionCursor(owner: Owner&,first: u32,input_list: bool,row_words: u32) -> Error {
    let generator .= owner.generator; var snapshot = first; if input_list { let local,error = temporary(owner,blot_backend_runtime_ir::VT_i32); if error != Error.none { return error; } snapshot = local; let loaded = emit(owner,blot_backend_runtime_ir::OP_local_get,first); if loaded != Error.none { return loaded; } let copy,copy_error = generator.module.ensureListSnapshot(); if copy_error != Error.none { return copy_error; } let copied = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_call,copy),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,snapshot)]); if copied != Error.none { return copied; } }
    let index,error = temporary(owner,blot_backend_runtime_ir::VT_i32); if error != Error.none { return error; } let initialized = emitConstantLocal(owner,0,index); if initialized != Error.none { return initialized; } return cursorPosition(owner,snapshot,index,input_list,blot_support::none<u32>(),row_words);
}
fn readCollectionCursor(owner: Owner&,first: u32,op: blot_backend_collection_ops::Op,input_list: bool,input_collection: u32,row_words: u32,stride: u32,result: blot_backend_runtime_ir::ValueType) -> Error {
    let generator .= owner.generator; let source,source_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if source_error != Error.none { return source_error; } let index,index_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if index_error != Error.none { return index_error; }
    let loaded = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,first),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,blot_runtime_runtime_layout::Cursor_collection),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,source),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,first),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,blot_runtime_runtime_layout::Cursor_index),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,index)]); if loaded != Error.none { return loaded; }
    if op == blot_backend_collection_ops::Op.cursor_has { let length = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,index),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,source),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,0)]); if length != Error.none { return length; } let logical = logicalListLength(owner,input_collection); if logical != Error.none { return logical; } return emit(owner,blot_backend_runtime_ir::OP_i32_lt_u); }
    if input_list && row_words != 0 {
        let bounds = listRowBounds(owner,source,index,row_words); if bounds != Error.none { return bounds; }
        if op == blot_backend_collection_ops::Op.cursor_value { let cache,error = cursorCache(owner,first); if error != Error.none { return error; } return readListRow(owner,source,index,row_words,blot_support::some(cache),blot_support::none<u32>(),generator.representations.store.node(input_collection).a); }
        let next,error = temporary(owner,blot_backend_runtime_ir::VT_i32); if error != Error.none { return error; } let advanced = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,index),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,1),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_add),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,next)]); if advanced != Error.none { return advanced; } return cursorPosition(owner,source,next,true,blot_support::some(first),row_words);
    }
    let bounds = arrayBounds(owner,source,index); if bounds != Error.none { return bounds; }
    if op == blot_backend_collection_ops::Op.cursor_value {
        if input_list { let leaf,leaf_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if leaf_error != Error.none { return leaf_error; }
            let cached = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,first),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,blot_runtime_runtime_layout::Cursor_leaf),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_tee,leaf),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_if_,blot_backend_runtime_ir::VT_i32 as u32),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,leaf),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,index),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,first),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,blot_runtime_runtime_layout::Cursor_base),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_sub),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,4),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_mul),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_add),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,blot_runtime_runtime_layout::ListNode_bytes),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_add),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_else_),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,source),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,index)]); if cached != Error.none { return cached; }
            let address,address_error = generator.module.ensureUncheckedListAddress(); if address_error != Error.none { return address_error; } let resolved = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_call,address),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_end)]); if resolved != Error.none { return resolved; }
        } else { let address = arrayAddress(owner,source,index,stride); if address != Error.none { return address; } }
        var offset: u32 = 4; if input_list { offset = 0; } return readElement(owner,result,offset,row_words,generator.representations.store.node(input_collection).a);
    }
    let next,error = temporary(owner,blot_backend_runtime_ir::VT_i32); if error != Error.none { return error; } let advanced = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,index),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,1),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_add),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,next)]); if advanced != Error.none { return advanced; } return cursorPosition(owner,source,next,input_list,blot_support::some(first),row_words);
}
fn logicalListLength(owner: Owner&,collection: u32) -> Error { if owner.generator.representations.store.node(collection).tag != blot_backend_layout::Tag.list { return Error.none; } let words,error = owner.generator.collectionRowWords(collection); if error != Error.none { return error; } if words <= 1 { return Error.none; } return emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,words),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_div_u)]); }
fn listWordCount(owner: Owner&,count: u32,words: u32) -> u32,Error { let checked = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,count),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,268435456 / words),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_gt_u),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_if_),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_unreachable_),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_end)]); if checked != Error.none { return 0,checked; } return multiplyLocal(owner,count,words); }
fn multiplyLocal(owner: Owner&,value: u32,factor: u32) -> u32,Error { let result,error = temporary(owner,blot_backend_runtime_ir::VT_i32); if error != Error.none { return 0,error; } let multiplied = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,value),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,factor),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_mul),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,result)]); return result,multiplied; }
fn listRowBounds(owner: Owner&,source: u32,index: u32,words: u32) -> Error { return emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,index),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,source),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,0),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,words),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_div_u),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_ge_u),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_if_),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_unreachable_),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_end)]); }
fn privateCursorRemaining(owner: Owner&,source: u32,position: u32) -> Error { return emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,source),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,0),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,position),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_sub)]); }
fn privateCursorBounds(owner: Owner&,source: u32,position: u32,words: u32) -> Error { let remaining = privateCursorRemaining(owner,source,position); if remaining != Error.none { return remaining; } return emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,words),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_lt_u),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_if_),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_unreachable_),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_end)]); }
fn listWordAddress(owner: Owner&,source: u32,base: u32,field: u32,proven: bool) -> Error {
    let runtime,error = owner.generator.module.ensureLists(); if error != Error.none { return error; } var address = runtime.address; if proven { let unchecked,unchecked_error = owner.generator.module.ensureUncheckedListAddress(); if unchecked_error != Error.none { return unchecked_error; } address = unchecked; }
    let loaded = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,source),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,base)]); if loaded != Error.none { return loaded; } if field != 0 { let offset = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,field),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_add)]); if offset != Error.none { return offset; } } return emit(owner,blot_backend_runtime_ir::OP_call,address);
}
fn resolveListSpan(owner: Owner&,source: u32,position: u32,span: u32[3],walk: blot_support::Option<blot_backend_list_traversal::Walk>) -> Error {
    if walk.present { return blot_backend_list_traversal::next(owner.generator.module,owner.function_id,span,walk.value); } let loaded = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,source),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,position)]); if loaded != Error.none { return loaded; } let runtime,error = owner.generator.module.ensureLists(); if error != Error.none { return error; }
    return emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_call,runtime.address),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_drop),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,source),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,8),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,span[0]),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,source),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,12),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_tee,span[1]),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,span[0]),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,8),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_add),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,span[2])]);
}
fn listSpanAddress(owner: Owner&,position: u32,span: u32[3]) -> Error { return emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,span[0]),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,position),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,span[1]),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_sub),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,4),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_mul),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_add),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,blot_runtime_list_runtime::header),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_add)]); }
fn readListSpanRow(owner: Owner&,source: u32,base: u32,words: u32,span: u32[3],walk: blot_support::Option<blot_backend_list_traversal::Walk>,element: u32) -> Error {
    let condition = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,base),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,span[2]),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_ge_u),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_if_)]); if condition != Error.none { return condition; } let resolved = resolveListSpan(owner,source,base,span,walk); if resolved != Error.none { return resolved; } let ended = emit(owner,blot_backend_runtime_ir::OP_end); if ended != Error.none { return ended; }
    let address,error = temporary(owner,blot_backend_runtime_ir::VT_i32); if error != Error.none { return error; } let located = listSpanAddress(owner,base,span); if located != Error.none { return located; } let saved = emit(owner,blot_backend_runtime_ir::OP_local_set,address); if saved != Error.none { return saved; } var fields: u32[16];
    for &field,index in fields[..words] { let local,local_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if local_error != Error.none { return local_error; } field = local; let loaded = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,address),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,(index * 4) as u32),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,local)]); if loaded != Error.none { return loaded; } } return unpackRow(owner,fields[..words],element);
}
fn readListRowView(owner: Owner&,words: u32,span: u32[3],view: RowView,directory: ListDirectory) -> Error {
    let resolved = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,directory.array),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,directory.offset),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_add),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,blot_runtime_runtime_layout::Array_bytes),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,span[0]),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,directory.offset),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,4),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_add),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,directory.offset),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,span[0]),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,blot_runtime_list_runtime::header),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_add),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,view.address),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,span[0]),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,blot_runtime_runtime_layout::ListNode_length)]); if resolved != Error.none { return resolved; }
    let length,error = temporary(owner,blot_backend_runtime_ir::VT_i32); if error != Error.none { return error; } return emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,length),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,span[2]),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,length),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_add),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,span[2]),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,view.address),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,length),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,words),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_sub),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,4),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_mul),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_add),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,view.limit_address)]);
}
fn readListRow(owner: Owner&,source: u32,index: u32,words: u32,cache: blot_support::Option<u32[2]>,span_end: blot_support::Option<u32>,element: u32) -> Error {
    let base,error = multiplyLocal(owner,index,words); if error != Error.none { return error; } var fields: u32[16]; for &field in fields[..words] { let local,local_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if local_error != Error.none { return local_error; } field = local; }
    if cache.present {
        let cached = cache.value; let relative,relative_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if relative_error != Error.none { return relative_error; } let located = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,base),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,cached[1]),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_sub),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,relative)]); if located != Error.none { return located; }
        if span_end.present { let complete = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,base),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,words),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_add),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,span_end.value),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_le_u)]); if complete != Error.none { return complete; } }
        else { let complete = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,cached[0]),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_if_,blot_backend_runtime_ir::VT_i32 as u32),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,relative),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,cached[0]),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,blot_runtime_runtime_layout::ListNode_length),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_le_u),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,cached[0]),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,blot_runtime_runtime_layout::ListNode_length),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,relative),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_sub),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,words),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_ge_u),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_and),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_else_),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,0),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_end)]); if complete != Error.none { return complete; } }
        let entered = emit(owner,blot_backend_runtime_ir::OP_if_); if entered != Error.none { return entered; } let address,address_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if address_error != Error.none { return address_error; } let offset = arrayAddress(owner,cached[0],relative,4); if offset != Error.none { return offset; } let saved = emit(owner,blot_backend_runtime_ir::OP_local_set,address); if saved != Error.none { return saved; }
        for field,position in fields[..words] { let loaded = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,address),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,blot_runtime_runtime_layout::ListNode_bytes + position as u32 * 4),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,field)]); if loaded != Error.none { return loaded; } } let alternate = emit(owner,blot_backend_runtime_ir::OP_else_); if alternate != Error.none { return alternate; }
    }
    for field,position in fields[..words] { let address = listWordAddress(owner,source,base,position as u32,true); if address != Error.none { return address; } let loaded = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,0),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,field)]); if loaded != Error.none { return loaded; } }
    if cache.present { let ended = emit(owner,blot_backend_runtime_ir::OP_end); if ended != Error.none { return ended; } } return unpackRow(owner,fields[..words],element);
}
fn cursorCache(owner: Owner&,cursor: u32) -> u32[2],Error {
    var values: u32[2]; let offsets = [blot_runtime_runtime_layout::Cursor_leaf,blot_runtime_runtime_layout::Cursor_base]; for offset,index in offsets { let local,error = temporary(owner,blot_backend_runtime_ir::VT_i32); if error != Error.none { return values,error; } values[index] = local; let loaded = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,cursor),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,offset),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,local)]); if loaded != Error.none { return values,loaded; } } return values,Error.none;
}
fn cachedListWordAddress(owner: Owner&,source: u32,base: u32,field: u32,cache: u32[2]) -> Error {
    let leaf = cache[0]; let relative,error = temporary(owner,blot_backend_runtime_ir::VT_i32); if error != Error.none { return error; }
    let cached = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,base),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,field),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_add),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,cache[1]),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_sub),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,relative),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,leaf),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_if_,blot_backend_runtime_ir::VT_i32 as u32),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,relative),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,leaf),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,blot_runtime_runtime_layout::ListNode_length),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_lt_u),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_else_),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,0),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_end),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_if_,blot_backend_runtime_ir::VT_i32 as u32),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,leaf),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,relative),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,4),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_mul),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_add),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,blot_runtime_runtime_layout::ListNode_bytes),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_add),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_else_)]); if cached != Error.none { return cached; } let ordinary = listWordAddress(owner,source,base,field,false); if ordinary != Error.none { return ordinary; } return emit(owner,blot_backend_runtime_ir::OP_end);
}
fn storeListRow(owner: Owner&,source: u32,index: u32,row: u32,words: u32,element: u32) -> Error {
    let base,error = multiplyLocal(owner,index,words); if error != Error.none { return error; } let nested,nested_error = owner.generator.nestedRow(element); if nested_error != Error.none { return nested_error; } var fields = blot_support::none<u32[16]>(); if nested.present { let values,value_error = packRow(owner,row,words,element); if value_error != Error.none { return value_error; } fields = blot_support::some(values); }
    for index in 0..words { let address = listWordAddress(owner,source,base,index as u32,false); if address != Error.none { return address; } if fields.present { let loaded = emit(owner,blot_backend_runtime_ir::OP_local_get,fields.value[index]); if loaded != Error.none { return loaded; } }
        else { let loaded = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,row),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,index as u32 * 4)]); if loaded != Error.none { return loaded; } } let stored = storeScalar(owner,blot_backend_runtime_ir::OP_i32_store,0); if stored != Error.none { return stored; }
    } return Error.none;
}
fn editListRow(owner: Owner&,source: u32,index: u32,row: u32,words: u32,front: blot_support::Option<bool>,reuse: bool,element: u32) -> Error { return editListRow(owner,source,blot_support::some(index),row,words,front,reuse,element); }
fn editListRow(owner: Owner&,source: u32,index: blot_support::Option<u32>,row: u32,words: u32,front: blot_support::Option<bool>,reuse: bool,element: u32) -> Error {
    let runtime,error = owner.generator.module.ensureLists(); if error != Error.none { return error; } let result,result_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if result_error != Error.none { return result_error; } var base = blot_support::none<u32>();
    if index.present { let bounds = listRowBounds(owner,source,index.value,words); if bounds != Error.none { return bounds; } let position,position_error = multiplyLocal(owner,index.value,words); if position_error != Error.none { return position_error; } base = blot_support::some(position); }
    let nested,nested_error = owner.generator.nestedRow(element); if nested_error != Error.none { return nested_error; } var fields = blot_support::none<u32[16]>(); if nested.present { let values,value_error = packRow(owner,row,words,element); if value_error != Error.none { return value_error; } fields = blot_support::some(values); }
    for step in 0..words { var position = step; if front.present && front.value { position = words - 1 - step; } var current = source; if step != 0 { current = result; } let loaded = emit(owner,blot_backend_runtime_ir::OP_local_get,current); if loaded != Error.none { return loaded; }
        if base.present { let selected = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,base.value),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,position as u32),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_add)]); if selected != Error.none { return selected; } }
        if fields.present { let loaded = emit(owner,blot_backend_runtime_ir::OP_local_get,fields.value[position]); if loaded != Error.none { return loaded; } } else { let loaded = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,row),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,position as u32 * 4)]); if loaded != Error.none { return loaded; } }
        if front.present { var prepend: u32 = 0; if front.value { prepend = 1; } let selected = emit(owner,blot_backend_runtime_ir::OP_i32_const,prepend); if selected != Error.none { return selected; } } var consuming: u32 = 0; if step != 0 || reuse { consuming = 1; } var function = runtime.push; if base.present { function = runtime.set; }
        let edited = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,consuming),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_call,function),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,result)]); if edited != Error.none { return edited; }
    } return emit(owner,blot_backend_runtime_ir::OP_local_get,result);
}
fn sliceListRows(owner: Owner&,locals: const u32[:],words: u32) -> Error {
    let count,error = temporary(owner,blot_backend_runtime_ir::VT_i32); if error != Error.none { return error; } let checked = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,locals[0]),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,0),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,words),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_div_u),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,count),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,locals[1]),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,count),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_gt_u),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_if_),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_unreachable_),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_end),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,locals[2]),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,count),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,locals[1]),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_sub),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_gt_u),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_if_),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_unreachable_),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_end)]); if checked != Error.none { return checked; }
    let start,start_error = multiplyLocal(owner,locals[1],words); if start_error != Error.none { return start_error; } let length,length_error = multiplyLocal(owner,locals[2],words); if length_error != Error.none { return length_error; } let loaded = emitLocals(owner,[locals[0],start,length]); if loaded != Error.none { return loaded; } let runtime,runtime_error = owner.generator.module.ensureLists(); if runtime_error != Error.none { return runtime_error; } return emit(owner,blot_backend_runtime_ir::OP_call,runtime.slice);
}
fn convertRows(owner: Owner&,source: u32,input_list: bool,row_words: u32) -> Error {
    let runtime,error = owner.generator.module.ensureLists(); if error != Error.none { return error; } let loaded = emit(owner,blot_backend_runtime_ir::OP_local_get,source); if loaded != Error.none { return loaded; } if !input_list { let described = emit(owner,blot_backend_runtime_ir::OP_i32_const,row_words); if described != Error.none { return described; } } var function = runtime.from_array; if input_list { function = runtime.to_array; } let converted = emit(owner,blot_backend_runtime_ir::OP_call,function); if converted != Error.none { return converted; }
    if input_list && row_words > 1 { let result,result_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if result_error != Error.none { return result_error; } let length = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,result),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,result),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,result),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,0),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,row_words),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_div_u)]); if length != Error.none { return length; } let stored = storeScalar(owner,blot_backend_runtime_ir::OP_i32_store,0); if stored != Error.none { return stored; } return emit(owner,blot_backend_runtime_ir::OP_local_get,result); } return Error.none;
}
fn cursorFields(owner: Owner&,source: u32,index: u32,is_list: bool,previous: blot_support::Option<CursorPrevious>,row_words: u32) -> SmallCollection,Error {
    var fields = SmallCollection { kind: SmallKind.cursor,len: 4 }; var position = index; if is_list && row_words > 1 { let physical,error = multiplyLocal(owner,index,row_words); if error != Error.none { return fields,error; } position = physical; }
    let leaf,leaf_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if leaf_error != Error.none { return fields,leaf_error; } let base,base_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if base_error != Error.none { return fields,base_error; } let leaf_zero = emitConstantLocal(owner,0,leaf); if leaf_zero != Error.none { return fields,leaf_zero; } let base_zero = emitConstantLocal(owner,0,base); if base_zero != Error.none { return fields,base_zero; }
    if is_list {
        let available = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,position),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,source),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,blot_runtime_runtime_layout::ListDescriptor_length),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_lt_u),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_if_)]); if available != Error.none { return fields,available; }
        if previous.present {
            var loaded: Error; match previous.value { boxed value=>{ loaded = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,value.value),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,blot_runtime_runtime_layout::Cursor_base),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,base),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,value.value),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,blot_runtime_runtime_layout::Cursor_leaf)]); },fields value=>{ loaded = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,value.value[1]),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,base),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,value.value[0])]); }, } if loaded != Error.none { return fields,loaded; }
            let checked = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_tee,leaf),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_if_),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,position),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,base),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_sub),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,leaf),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,blot_runtime_runtime_layout::ListNode_length),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_ge_u),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_if_),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,0),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,leaf),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_end),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_end)]); if checked != Error.none { return fields,checked; }
        }
        let missing = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,leaf),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_eqz),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_if_),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,source),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,position)]); if missing != Error.none { return fields,missing; } let runtime,error = owner.generator.module.ensureLists(); if error != Error.none { return fields,error; }
        let resolved = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_call,runtime.address),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_drop),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,source),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,blot_runtime_runtime_layout::ListDescriptor_cached_leaf),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,leaf),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,source),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,blot_runtime_runtime_layout::ListDescriptor_cached_base),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,base),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_end),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_end)]); if resolved != Error.none { return fields,resolved; }
    }
    fields.values[0] = source; fields.values[1] = index; fields.values[2] = leaf; fields.values[3] = base; return fields,Error.none;
}
fn cursorPosition(owner: Owner&,source: u32,index: u32,is_list: bool,previous: blot_support::Option<u32>,row_words: u32) -> Error {
    var old = blot_support::none<CursorPrevious>(); if previous.present { old = blot_support::some(CursorPrevious.boxed { previous.value }); } let fields,error = cursorFields(owner,source,index,is_list,old,row_words); if error != Error.none { return error; }
    let address,address_error = allocate(owner,blot_runtime_runtime_layout::Cursor_bytes,AllocationRoles { words: [blot_backend_runtime_ir::ROLE_reference,blot_backend_runtime_ir::ROLE_scalar,blot_backend_runtime_ir::ROLE_reference,blot_backend_runtime_ir::ROLE_scalar] }); if address_error != Error.none { return address_error; }
    let offsets = [blot_runtime_runtime_layout::Cursor_collection,blot_runtime_runtime_layout::Cursor_index,blot_runtime_runtime_layout::Cursor_leaf,blot_runtime_runtime_layout::Cursor_base]; for offset,field in offsets { let stored = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,address),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,fields.values[field]),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_store,offset)]); if stored != Error.none { return stored; } } return emit(owner,blot_backend_runtime_ir::OP_local_get,address);
}
fn arrayPush(owner: Owner&,source: u32,value: u32,machine: blot_backend_runtime_ir::ValueType,front: bool,scalar_elements: bool,row_words: u32,element: u32) -> Error {
    let count,error = temporary(owner,blot_backend_runtime_ir::VT_i32); if error != Error.none { return error; } let result,result_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if result_error != Error.none { return result_error; }
    let counted = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,source),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,0),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,1),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_add),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,count)]); if counted != Error.none { return counted; } let stride = blot_backend_packed_layout::stride(row_words); let size,size_error = arraySize(owner,count,stride); if size_error != Error.none { return size_error; } let length = emit(owner,blot_backend_runtime_ir::OP_local_get,size); if length != Error.none { return length; } let allocated = allocateArray(owner,scalar_elements,element); if allocated != Error.none { return allocated; }
    var prefix: u32 = 4; if front { prefix = 4 + stride; }
    let copied = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,result),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,result),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,count),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_store,0),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,result),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,prefix),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_add),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,source),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,4),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_add),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,size),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,4 + stride),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_sub),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_memory_copy)]); if copied != Error.none { return copied; }
    if front { let target = emit(owner,blot_backend_runtime_ir::OP_local_get,result); if target != Error.none { return target; } }
    else { let target = arrayAddress(owner,result,count,stride); if target != Error.none { return target; } if stride != 4 { let adjusted = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,stride - 4),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_sub)]); if adjusted != Error.none { return adjusted; } } }
    let loaded = emit(owner,blot_backend_runtime_ir::OP_local_get,value); if loaded != Error.none { return loaded; } var offset: u32 = 0; if front { offset = 4; } let stored = storeElement(owner,machine,offset,row_words,scalar_elements,element); if stored != Error.none { return stored; } return emit(owner,blot_backend_runtime_ir::OP_local_get,result);
}
fn simdCompare(op: blot_check_core::Op,floating: bool) -> blot_backend_runtime_ir::Op {
    match op { equal=>{ if floating { return blot_backend_runtime_ir::OP_f32x4_eq; } return blot_backend_runtime_ir::OP_i32x4_eq; },not_equal=>{ if floating { return blot_backend_runtime_ir::OP_f32x4_ne; } return blot_backend_runtime_ir::OP_i32x4_ne; },less=>{ if floating { return blot_backend_runtime_ir::OP_f32x4_lt; } return blot_backend_runtime_ir::OP_i32x4_lt_u; },less_equal=>{ if floating { return blot_backend_runtime_ir::OP_f32x4_le; } return blot_backend_runtime_ir::OP_i32x4_le_u; },greater=>{ if floating { return blot_backend_runtime_ir::OP_f32x4_gt; } return blot_backend_runtime_ir::OP_i32x4_gt_u; },greater_equal=>{ if floating { return blot_backend_runtime_ir::OP_f32x4_ge; } return blot_backend_runtime_ir::OP_i32x4_ge_u; },_=>{ abort("non-comparison SIMD operation"); }, }
}
fn simdLocals(owner: Owner&,op: blot_check_core::Op,operands: const u32[:],lanes: blot_support::Option<u8[4]>,input: u32,result: u32) -> Error {
    let generator .= owner.generator; var vector_layout = input; if blot_backend_simd_intrinsics::pairs(op) || op == blot_check_core::Op.swizzle { vector_layout = result; } let fields = generator.representations.store.children(vector_layout); if fields.len != 4 { return generator.fail(owner.unit_id,0,blot_backend_core_backend::Code.unsupported); } let scalar_type = generator.representations.store.scalar(fields[0]); if !scalar_type.present { return generator.fail(owner.unit_id,0,blot_backend_core_backend::Code.unsupported); } for field in fields { if field != fields[0] { return generator.fail(owner.unit_id,0,blot_backend_core_backend::Code.unsupported); } } let floating = scalar_type.value == blot_backend_runtime_ir::SC_f32;
    var expected = operands.len; match op { select,relaxed_madd,relaxed_nmadd=>{ expected = 3; },shuffle,shift_left,shift_right,shift_right_signed,min,max,bit_andnot=>{ expected = 2; },swizzle,broadcast,bits,from_bits,bit_not,any_true,all_true=>{ expected = 1; },_=>{}, }
    if operands.len != expected || operands.len == 0 { return generator.fail(owner.unit_id,0,blot_backend_core_backend::Code.unsupported); } if blot_backend_simd_intrinsics::literalLanes(op) && !lanes.present { return generator.fail(owner.unit_id,0,blot_backend_core_backend::Code.simd_lane_literal); }
    if op == blot_check_core::Op.any_true || op == blot_check_core::Op.all_true { let loaded = simdLoad(owner,operands[0]); if loaded != Error.none { return loaded; } var reduction = blot_backend_runtime_ir::OP_i32x4_all_true; if op == blot_check_core::Op.any_true { reduction = blot_backend_runtime_ir::OP_v128_any_true; } return emit(owner,reduction); }
    let address,error = allocateStorage(owner,16,true,AllocationRoles { rest: blot_backend_runtime_ir::ROLE_scalar }); if error != Error.none { return error; } let target = emit(owner,blot_backend_runtime_ir::OP_local_get,address); if target != Error.none { return target; }
    match op {
        shift_left,shift_right,shift_right_signed=>{ if floating { return generator.fail(owner.unit_id,0,blot_backend_core_backend::Code.unsupported); } let loaded = simdLoad(owner,operands[0]); if loaded != Error.none { return loaded; } let count = emit(owner,blot_backend_runtime_ir::OP_local_get,operands[1]); if count != Error.none { return count; } var shift = blot_backend_runtime_ir::OP_i32x4_shr_s; if op == blot_check_core::Op.shift_left { shift = blot_backend_runtime_ir::OP_i32x4_shl; } else if op == blot_check_core::Op.shift_right { shift = blot_backend_runtime_ir::OP_i32x4_shr_u; } let emitted = emit(owner,shift); if emitted != Error.none { return emitted; } },
        shuffle,swizzle,broadcast=>{ let first = simdLoad(owner,operands[0]); if first != Error.none { return first; } let last = simdLoad(owner,operands[operands.len - 1]); if last != Error.none { return last; } assert(lanes.present); var packed: u32 = 0; for lane,index in lanes.value { packed |= (lane as u32) << (index * 3) as u32; } let shuffled = emit(owner,blot_backend_runtime_ir::OP_i8x16_shuffle,packed); if shuffled != Error.none { return shuffled; } },
        select=>{ for index in [1,2,0] { let loaded = simdLoad(owner,operands[index]); if loaded != Error.none { return loaded; } } let selected = emit(owner,blot_backend_runtime_ir::OP_v128_bitselect); if selected != Error.none { return selected; } },
        relaxed_madd,relaxed_nmadd=>{ if !floating { return generator.fail(owner.unit_id,0,blot_backend_core_backend::Code.unsupported); } for operand in operands { let loaded = simdLoad(owner,operand); if loaded != Error.none { return loaded; } } var operation = blot_backend_runtime_ir::OP_f32x4_relaxed_nmadd; if op == blot_check_core::Op.relaxed_madd { operation = blot_backend_runtime_ir::OP_f32x4_relaxed_madd; } let emitted = emit(owner,operation); if emitted != Error.none { return emitted; } },
        convert_i32_f32,convert_f32_i32=>{ if floating != (op == blot_check_core::Op.convert_f32_i32) { return generator.fail(owner.unit_id,0,blot_backend_core_backend::Code.unsupported); } let loaded = simdLoad(owner,operands[0]); if loaded != Error.none { return loaded; } var operation = blot_backend_runtime_ir::OP_i32x4_trunc_sat_f32x4_s; if op == blot_check_core::Op.convert_i32_f32 { operation = blot_backend_runtime_ir::OP_f32x4_convert_i32x4_s; } let converted = emit(owner,operation); if converted != Error.none { return converted; } },
        min,max=>{ if floating { let right = simdLoad(owner,operands[1]); if right != Error.none { return right; } let left = simdLoad(owner,operands[0]); if left != Error.none { return left; } var operation = blot_backend_runtime_ir::OP_f32x4_pmax; if op == blot_check_core::Op.min { operation = blot_backend_runtime_ir::OP_f32x4_pmin; } let emitted = emit(owner,operation); if emitted != Error.none { return emitted; } }
            else { let left = simdLoad(owner,operands[0]); if left != Error.none { return left; } let right = simdLoad(owner,operands[1]); if right != Error.none { return right; } var operation = blot_backend_runtime_ir::OP_i32x4_max_u; if op == blot_check_core::Op.min { operation = blot_backend_runtime_ir::OP_i32x4_min_u; } let emitted = emit(owner,operation); if emitted != Error.none { return emitted; } }
        },bits,from_bits=>{ let loaded = simdLoad(owner,operands[0]); if loaded != Error.none { return loaded; } },bit_not=>{ let loaded = simdLoad(owner,operands[0]); if loaded != Error.none { return loaded; } let inverted = emit(owner,blot_backend_runtime_ir::OP_v128_not); if inverted != Error.none { return inverted; } },
        bit_andnot=>{ let left = simdLoad(owner,operands[0]); if left != Error.none { return left; } let right = simdLoad(owner,operands[1]); if right != Error.none { return right; } let masked = emit(owner,blot_backend_runtime_ir::OP_v128_andnot); if masked != Error.none { return masked; } },
        equal,not_equal,less,less_equal,greater,greater_equal=>{ let left = simdLoad(owner,operands[0]); if left != Error.none { return left; } let right = simdLoad(owner,operands[1]); if right != Error.none { return right; } let compared = emit(owner,simdCompare(op,floating)); if compared != Error.none { return compared; } },
        _=>{ let scalar_op = blot_backend_scalar_ops::opcode(op,scalar_type.value); if !scalar_op.present { return generator.fail(owner.unit_id,0,blot_backend_core_backend::Code.unsupported); } let vector_op,has_vector = blot_backend_runtime_ir::lift(scalar_op.value); if !has_vector { return generator.fail(owner.unit_id,0,blot_backend_core_backend::Code.unsupported); } for operand in operands { let loaded = simdLoad(owner,operand); if loaded != Error.none { return loaded; } } let emitted = emit(owner,vector_op); if emitted != Error.none { return emitted; } },
    }
    return emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_v128_store,0),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,address)]);
}
fn simdLoad(owner: Owner&,operand: u32) -> Error { return emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,operand),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_v128_load,0)]); }
fn simdPairLocals(owner: Owner&,pair: u32,into: u32[2]&) -> Error { for &local,index in into { let temporary_local,error = temporary(owner,blot_backend_runtime_ir::VT_i32); if error != Error.none { return error; } local = temporary_local; let loaded = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,pair),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,(index * 4) as u32),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,local)]); if loaded != Error.none { return loaded; } } return Error.none; }
fn laneLiteral(source: const blot_check_core::Module&,id: u32,limit: u32) -> blot_support::Option<u8> { let node = source.node(id); if node.tag != blot_check_core::Tag.constant || source.types.node(source.typeOf(id)).tag != blot_check_types::Tag.unsigned32 || node.a >= limit { return blot_support::none<u8>(); } return blot_support::some(node.a as u8); }
fn simdLaneLiterals(owner: Owner&,id: u32,op: blot_check_core::Op) -> blot_support::Option<u8[4]> {
    let source .= owner.generator.unit(owner.unit_id); let limit = blot_backend_simd_intrinsics::laneLimit(op); if op == blot_check_core::Op.broadcast { let lane = laneLiteral(source,id,limit); if !lane.present { return blot_support::none<u8[4]>(); } return blot_support::some([lane.value;4]); } if source.node(id).tag != blot_check_core::Tag.product { return blot_support::none<u8[4]>(); } let children = source.children(id); if children.len != 4 { return blot_support::none<u8[4]>(); }
    var lanes: u8[4]; for child,index in children { let lane = laneLiteral(source,child,limit); if !lane.present { return blot_support::none<u8[4]>(); } lanes[index] = lane.value; } return blot_support::some(lanes);
}
recursive fn simdExpression(owner: Owner&,id: u32,input: u32,result: u32,depth: i64) -> Error {
    let generator .= owner.generator; let value = generator.unit(owner.unit_id).node(id); var lanes = blot_support::none<u8[4]>(); var operands: u32[3]; var count: i64 = 0;
    if value.op == blot_check_core::Op.shuffle || value.op == blot_check_core::Op.swizzle { lanes = simdLaneLiterals(owner,value.a,value.op); if !lanes.present { return generator.fail(owner.unit_id,value.a,blot_backend_core_backend::Code.simd_lane_literal); } }
    else { let operand,error = capture(owner,value.a,depth); if error != Error.none { return error; } operands[0] = operand; count = 1; }
    if value.op == blot_check_core::Op.broadcast { lanes = simdLaneLiterals(owner,value.b,value.op); if !lanes.present { return generator.fail(owner.unit_id,value.b,blot_backend_core_backend::Code.simd_lane_literal); } }
    else if value.b != 0 { var next: u32[2]; let supplied,error = simdOperand(owner,value.op,value.b,next,depth); if error != Error.none { return error; } for index in 0..supplied { operands[count + index] = next[index]; } count += supplied; } return simdLocals(owner,value.op,operands[..count],lanes,input,result);
}
recursive fn simdOperand(owner: Owner&,op: blot_check_core::Op,id: u32,into: u32[2]&,depth: i64) -> i64,Error {
    let source .= owner.generator.unit(owner.unit_id); if !blot_backend_simd_intrinsics::pairs(op) { let operand,error = capture(owner,id,depth); if error != Error.none { return 0,error; } into[0] = operand; return 1,Error.none; }
    if source.node(id).tag == blot_check_core::Tag.product && source.children(id).len == 2 { for child,index in source.children(id) { let operand,error = capture(owner,child,depth); if error != Error.none { return 0,error; } into[index] = operand; } }
    else { let pair,error = capture(owner,id,depth); if error != Error.none { return 0,error; } let unpacked = simdPairLocals(owner,pair,into); if unpacked != Error.none { return 0,unpacked; } } return 2,Error.none;
}
fn arrayStructural(owner: Owner&,op: blot_backend_collection_ops::Op,locals: const u32[:],scalar_elements: bool,stride: u32,element: u32) -> Error {
    let count,error = temporary(owner,blot_backend_runtime_ir::VT_i32); if error != Error.none { return error; } let left_count,left_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if left_error != Error.none { return left_error; } let loaded = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,locals[0]),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,0),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,left_count)]); if loaded != Error.none { return loaded; }
    if op == blot_backend_collection_ops::Op.concat { let checked = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,left_count),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,locals[1]),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,0),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_add),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_tee,count),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,left_count),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_lt_u),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_if_),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_unreachable_),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_end)]); if checked != Error.none { return checked; } }
    else { let checked = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,locals[1]),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,left_count),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_gt_u),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_if_),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_unreachable_),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_end),
        blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,locals[2]),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_tee,count),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,left_count),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,locals[1]),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_sub),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_gt_u),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_if_),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_unreachable_),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_end)]); if checked != Error.none { return checked; } }
    let bytes,byte_error = arraySize(owner,count,stride); if byte_error != Error.none { return byte_error; } let address,address_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if address_error != Error.none { return address_error; } let length = emit(owner,blot_backend_runtime_ir::OP_local_get,bytes); if length != Error.none { return length; } let allocated = allocateArray(owner,scalar_elements,element); if allocated != Error.none { return allocated; }
    let prepared = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,address),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,address),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,count),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_store,0),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,address),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,address),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,4),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_add)]); if prepared != Error.none { return prepared; }
    if op == blot_backend_collection_ops::Op.slice { let source = arrayAddress(owner,locals[0],locals[1],stride); if source != Error.none { return source; } } else { let source = emit(owner,blot_backend_runtime_ir::OP_local_get,locals[0]); if source != Error.none { return source; } }
    let source = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,4),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_add)]); if source != Error.none { return source; } var copied_count = left_count; if op == blot_backend_collection_ops::Op.slice { copied_count = count; } assert(owner.generator.module.arena.present);
    let copied = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,copied_count),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,stride),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_mul),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_call,owner.generator.module.arena.value.copy_words)]); if copied != Error.none { return copied; }
    if op == blot_backend_collection_ops::Op.concat { let target = emit(owner,blot_backend_runtime_ir::OP_local_get,address); if target != Error.none { return target; } let destination = arrayAddress(owner,address,left_count,stride); if destination != Error.none { return destination; }
        let copied = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,4),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_add),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,locals[1]),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,4),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_add),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,count),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,left_count),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_sub),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,stride),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_mul),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_call,owner.generator.module.arena.value.copy_words)]); if copied != Error.none { return copied; }
    } return emit(owner,blot_backend_runtime_ir::OP_local_get,address);
}
fn descriptor(owner: Owner&,function: u32,environment: u32) -> Error { return descriptor(owner,function,blot_support::some(environment)); }
fn descriptor(owner: Owner&,function: u32,environment: blot_support::Option<u32>) -> Error {
    let generator .= owner.generator; if !environment.present { let address,error = generator.static_data.closureData(generator,function,0); if error != Error.none { return error; } return referenceConstant(owner,address,blot_reuse_artifact_emitter::Role.static_address); }
    let role = generator.module.functions[function].parameterRole(0); let address,error = allocate(owner,blot_runtime_runtime_layout::Closure_bytes,AllocationRoles { words: [blot_backend_runtime_ir::ROLE_scalar,role] }); if error != Error.none { return error; } let target = emit(owner,blot_backend_runtime_ir::OP_local_get,address); if target != Error.none { return target; } let reference = referenceConstant(owner,function,blot_reuse_artifact_emitter::Role.callable_function); if reference != Error.none { return reference; }
    let stored = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_store,blot_runtime_runtime_layout::Closure_function),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,address),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,environment.value),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_store,blot_runtime_runtime_layout::Closure_environment),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,address)]); return stored;
}
fn callableImplementationLayout(owner: Owner&,id: u32) -> u32,Error { let source .= owner.generator.unit(owner.unit_id); let value,error = codeLayout(owner,source.typeOf(id),source.span(id)); if error != Error.none { return 0,error; } let node = owner.generator.representations.store.node(value); if node.tag == blot_backend_layout::Tag.universal { return node.a,Error.none; } return value,Error.none; }
fn copyRoles(values: const blot_backend_runtime_ir::Role[:]) -> blot_backend_runtime_ir::Role[:] { if values.len == 0 { return []; } let copy = owned_roles.alloc_slice(values.len); for value,index in values { copy[index] = value; } return copy; }
fn prepareTemplate(owner: Owner&,id: u32) -> TemplatePreparation,Error {
    assert(owner.preparing); var capture_types = WordBuffer {}; var capture_roles = RoleBuffer {}; var templates = blot_backend_substitution_buffers::Entries {}; var values = blot_backend_substitution_buffers::Entries {}; var static_types = WordBuffer {};
    recursive fn prepare() -> TemplatePreparation,Error {
        let generator .= owner.generator; let source .= generator.unit(owner.unit_id); let node = source.node(id); let captures = source.closureCaptures(id); let empty = TemplatePreparation { Template { node: id },[],[],blot_support::none<blot_reuse_code_artifacts::ClosureKey>() };
        for binding in captures {
            let template .= owner.templates.get(binding); if template != null { let appended = capture_types.push(1); if appended != Error.none { return empty,appended; } let key,key_error = generator.captureTemplate(template); if key_error != Error.none { return empty,key_error; } let captured = templates.push(blot_reuse_substitution_keys::Entry { binding,key }); if captured != Error.none { return empty,captured; } }
            else { let concrete,error = codeLayout(owner,source.binding(binding).ty,source.span(id)); if error != Error.none { return empty,error; } let checked = checkComputationABI(owner,binding,concrete,id); if checked != Error.none { return empty,checked; } let appended = capture_types.push(concrete); if appended != Error.none { return empty,appended; } }
        }
        let capture_layout,layout_error = generator.internLayout(blot_backend_layout::Tag.product,0,0,capture_types.items); if layout_error != Error.none { return empty,layout_error; }
        for ty in capture_types.items { let appended = capture_roles.push(generator.layoutRole(ty)); if appended != Error.none { return empty,appended; } }
        for binding,index in captures { let template .= owner.templates.get(binding); if template != null { capture_roles.items[index] = blot_backend_runtime_ir::ROLE_reference; if template.scalar_environment { capture_roles.items[index] = blot_backend_runtime_ir::ROLE_scalar; } } }
        let template_key,key_error = generator.representations.template_keys.intern(templates.items); if key_error != Error.none { if key_error == Error.out_of_memory { return empty,key_error; } return empty,generator.fail(owner.unit_id,id,blot_backend_core_backend::Code.complexity); }
        var evidence: u32 = 0; var rows: u32 = 0; if owner.factory_template { let mapped,mapped_error = generator.mappingEvidence(owner.mappings); if mapped_error != Error.none { return empty,mapped_error; } evidence = mapped; let row_mappings,row_error = generator.rowMappingEvidence(owner.row_mappings); if row_error != Error.none { return empty,row_error; } rows = row_mappings; }
        var staged: u32 = 0; if owner.staged.present { staged = owner.staged.value; } var environment = blot_support::none<u32>(); if captures.len != 0 { environment = blot_support::some(0 as u32); }
        var metadata = Template { unit: owner.unit_id,node: id,staged,environment,captures: capture_layout,templates: template_key,evidence,rows }; var static_key = blot_support::none<blot_reuse_code_artifacts::ClosureKey>();
        if node.tag == blot_check_core::Tag.closure && owner.static_values.table.count != 0 {
            for binding in captures { let value .= owner.static_values.get(binding); if value != null { let appended = values.push(blot_reuse_substitution_keys::Entry { binding,value }); if appended != Error.none { return empty,appended; } } let concrete,error = codeLayout(owner,source.binding(binding).ty,source.span(id)); if error != Error.none { return empty,error; } let appended = static_types.push(concrete); if appended != Error.none { return empty,appended; } }
            if values.items.len != 0 { let ty,type_error = callableImplementationLayout(owner,id); if type_error != Error.none { return empty,type_error; } let captures,capture_error = generator.internLayout(blot_backend_layout::Tag.product,0,0,static_types.items); if capture_error != Error.none { return empty,capture_error; } let static_values,static_error = generator.representations.static_keys.intern(values.items); if static_error != Error.none { if static_error == Error.out_of_memory { return empty,static_error; } return empty,generator.fail(owner.unit_id,id,blot_backend_core_backend::Code.complexity); }
                static_key = blot_support::some(blot_reuse_code_artifacts::ClosureKey { unit: owner.unit_id,catalog: node.a,ty,captures,templates: metadata.templates,staged: metadata.staged,static_values });
            }
        }
        if node.tag == blot_check_core::Tag.closure && !owner.factory_template && !static_key.present && templates.items.len == 0 && generator.representations.store.scalarEnvironment(capture_layout) { metadata.scalar_environment = true; }
        return TemplatePreparation { metadata,copyWords(capture_types.items),copyRoles(capture_roles.items),static_key },Error.none;
    }
    let result,error = prepare(); static_types.deinit(); values.deinit(); templates.deinit(); capture_roles.deinit(); capture_types.deinit(); return result,error;
}
fn scopedCallableInstances(owner: Owner&,id: u32) -> u32,Error { return scopedCallableTargetInstances(owner,id,blot_support::none<blot_check_core::BindingRef>()); }
fn scopedCallableTargetInstances(owner: Owner&,id: u32,supplied: blot_check_core::BindingRef) -> u32,Error { return scopedCallableTargetInstances(owner,id,blot_support::some(supplied)); }
fn scopedCallableTargetInstances(owner: Owner&,id: u32,supplied: blot_support::Option<blot_check_core::BindingRef>) -> u32,Error {
    let generator .= owner.generator; let source .= generator.unit(owner.unit_id); let node = source.node(id); if node.tag != blot_check_core::Tag.reference && !supplied.present { return 0,Error.none; } var ty = node.ty; var scoped = false;
    for index in 0..max_parameters { let arrow = source.types.node(ty); if arrow.tag != blot_check_types::Tag.function { break; } if source.types.node(arrow.a).tag == blot_check_types::Tag.scoped { scoped = true; } ty = arrow.b; } if !scoped { return 0,Error.none; }
    var target = supplied; if !target.present { let normalized,error = generator.normalize(owner.unit_id,source.reference(id)); if error != Error.none { return 0,error; } target = blot_support::some(normalized); }
    let selected,error = generator.signature(target.value,node.ty,owner.unit_id,owner.mappings,owner.row_mappings,source.span(id),false); if error != Error.none { return 0,error; } return selected.instance_arguments,Error.none;
}
fn templateAt(owner: Owner&,template: Template,id: u32) -> Template,Error {
    let generator .= owner.generator; var unit = template.unit; if unit == 0 { unit = owner.unit_id; } let source .= generator.unit(unit); if source.node(template.node).tag != blot_check_core::Tag.reference { return template,Error.none; } let target,error = generator.normalize(unit,source.reference(template.node)); if error != Error.none { return template,error; } let instances,instance_error = scopedCallableTargetInstances(owner,id,target); if instance_error != Error.none { return template,instance_error; } if instances == 0 { return template,Error.none; } var selected = template; selected.callable_instances = instances; return selected,Error.none;
}
fn newTemplate(owner: Owner&,id: u32) -> Template,Error {
    let generator .= owner.generator; let source .= generator.unit(owner.unit_id); let node = source.node(id);
    if node.tag == blot_check_core::Tag.reference { let reference = source.reference(id); if reference.unit == 0 || reference.unit == owner.unit_id { let template .= owner.templates.get(reference.binding); if template != null { return templateAt(owner,template,id); } } let instances,error = scopedCallableInstances(owner,id); return Template { unit: owner.unit_id,node: id,callable_instances: instances },error; }
    if node.tag == blot_check_core::Tag.constructor_function || node.tag == blot_check_core::Tag.primitive_function { let instances,error = scopedCallableInstances(owner,id); return Template { unit: owner.unit_id,node: id,callable_instances: instances },error; }
    let captures = source.closureCaptures(id); var selected = TemplatePreparation { Template { node: id },[],[],blot_support::none<blot_reuse_code_artifacts::ClosureKey>() }; match resolvedPlan(owner,id) { template plan=>{ selected = plan.value; },_=>{ assert(false); }, }
    if selected.metadata.scalar_environment { let environment,error = temporary(owner,blot_backend_runtime_ir::VT_i32); if error != Error.none { return Template { node: id },error; } let local .= owner.locals.get(captures[0]); if local == null { return Template { node: id },generator.fail(owner.unit_id,id,blot_backend_core_backend::Code.unsupported); } let copied = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,local),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,environment)]); if copied != Error.none { return Template { node: id },copied; } var metadata = selected.metadata; metadata.environment = blot_support::some(environment); return metadata,Error.none; }
    var environment = blot_support::none<u32>(); if captures.len != 0 { let address,error = allocate(owner,(captures.len * 4) as u32,AllocationRoles { words: selected.capture_roles }); if error != Error.none { return Template { node: id },error; } environment = blot_support::some(address); }
    for binding,index in captures {
        assert(environment.present); let address = emit(owner,blot_backend_runtime_ir::OP_local_get,environment.value); if address != Error.none { return Template { node: id },address; } var found = false;
        { let local .= owner.locals.get(binding); if local != null { let loaded = emit(owner,blot_backend_runtime_ir::OP_local_get,local); if loaded != Error.none { return Template { node: id },loaded; } found = true; } }
        if !found { let template .= owner.templates.get(binding); if template == null { return Template { node: id },generator.fail(owner.unit_id,id,blot_backend_core_backend::Code.unsupported); } var loaded: Error; if template.environment.present { loaded = emit(owner,blot_backend_runtime_ir::OP_local_get,template.environment.value); } else { loaded = emit(owner,blot_backend_runtime_ir::OP_i32_const,0); } if loaded != Error.none { return Template { node: id },loaded; } }
        var store = blot_backend_runtime_ir::OP_i32_store; if generator.representations.store.machine(selected.capture_types[index]) == blot_backend_runtime_ir::VT_f32 { store = blot_backend_runtime_ir::OP_f32_store; } let stored = emit(owner,store,(index * 4) as u32); if stored != Error.none { return Template { node: id },stored; }
    }
    var metadata = selected.metadata; metadata.environment = environment; return metadata,Error.none;
}
fn computationAction(owner: Owner&,ty: u32) -> blot_support::Option<u32> { let layouts .= owner.generator.representations.store; let node = layouts.node(ty); if node.tag != blot_backend_layout::Tag.nominal || node.a != 4294967295 || node.b != 5 || layouts.children(ty).len != 1 { return blot_support::none<u32>(); } let action = layouts.children(ty)[0]; if layouts.node(action).tag != blot_backend_layout::Tag.function { return blot_support::none<u32>(); } return blot_support::some(action); }
fn checkComputationABI(owner: Owner&,binding: u32,expected: u32,source: u32) -> Error {
    let actual .= owner.computation_values.get(binding); if actual == null { return Error.none; } let given = computationAction(owner,actual); if !given.present { return Error.none; } let required = computationAction(owner,expected); if !required.present { return Error.none; } let layouts .= owner.generator.representations.store; if layouts.machine(layouts.node(given.value).b) != layouts.machine(layouts.node(required.value).b) { return owner.generator.fail(owner.unit_id,source,blot_backend_core_backend::Code.unresolved_type); } return Error.none;
}
recursive fn sourceTemplate(owner: Owner&,unit: u32,id: u32,parameters: const blot_check_core::Parameter[:],arguments: const bool[:],depth: i64) -> bool {
    if depth >= 1024 { return false; } let source .= owner.generator.unit(unit); let node = source.node(id); if node.tag == blot_check_core::Tag.closure || node.tag == blot_check_core::Tag.primitive_function || node.tag == blot_check_core::Tag.constructor_function { return true; } if node.tag != blot_check_core::Tag.reference { return false; } let reference = source.reference(id); if reference.unit != 0 && reference.unit != unit { return true; }
    for parameter,index in parameters { if parameter.binding == reference.binding { return arguments[index]; } } if source.types.node(node.ty).tag != blot_check_types::Tag.function { return false; } let binding = source.binding(reference.binding); if binding.kind == blot_check_core::BindingKind.global || binding.kind == blot_check_core::BindingKind.external { return true; } return binding.initializer != 0 && sourceTemplate(owner,unit,binding.initializer,parameters,arguments,depth + 1);
}
recursive fn factoryTemplateResult(owner: Owner&,unit: u32,id: u32,parameters: const blot_check_core::Parameter[:],arguments: const bool[:],depth: i64) -> bool {
    if depth >= 1024 { return false; } let source .= owner.generator.unit(unit); let node = source.node(id);
    match node.tag {
        computation,effect_scope=>{ return sourceTemplate(owner,unit,node.a,parameters,arguments,depth + 1); },reference=>{ let reference = source.reference(id); if reference.unit != 0 && reference.unit != unit { return false; } for parameter,index in parameters { if parameter.binding == reference.binding { return arguments[index]; } } let binding = source.binding(reference.binding); return binding.initializer != 0 && factoryTemplateResult(owner,unit,binding.initializer,parameters,arguments,depth + 1); },
        call=>{ let call = source.call(id); let target,error = owner.generator.normalize(unit,call.target); if error != Error.none { return false; } let producer .= owner.generator.unit(target.unit); let body .= producer.body(target.binding); if body == null || !body.is_function || body.parameters.len != call.arguments.len || call.arguments.len > 16 { return false; } var admitted: bool[16] = [false;16]; for argument,index in call.arguments { admitted[index] = sourceTemplate(owner,unit,argument,parameters,arguments,depth + 1); } return factoryTemplateResult(owner,target.unit,body.root,producer.bodyParameters(body),admitted[..call.arguments.len],depth + 1); },
        block_=>{ for statement in source.children(id) { let value = source.node(statement); if value.tag == blot_check_core::Tag.return_ && value.b == id { return factoryTemplateResult(owner,unit,value.a,parameters,arguments,depth + 1); } } return false; },
        if_value=>{ return factoryTemplateResult(owner,unit,node.b,parameters,arguments,depth + 1) && factoryTemplateResult(owner,unit,node.c,parameters,arguments,depth + 1); },_=>{ return false; },
    }
}
fn isCallableTemplate(owner: Owner&,id: u32) -> bool {
    let source .= owner.generator.unit(owner.unit_id); let node = source.node(id);
    if owner.dictionary_owner.present && node.tag == blot_check_core::Tag.reference { let reference = source.reference(id); var unit = reference.unit; if unit == 0 { unit = owner.unit_id; } let kind = owner.generator.unit(unit).binding(reference.binding).kind; if kind == blot_check_core::BindingKind.global || kind == blot_check_core::BindingKind.external { let target,error = owner.generator.normalize(owner.unit_id,reference); if error != Error.none { return false; } if blot_check_dictionary_owner::forBinding(owner.generator.unit(target.unit),target.binding).present { return false; } } }
    if node.tag == blot_check_core::Tag.closure || node.tag == blot_check_core::Tag.primitive_function || node.tag == blot_check_core::Tag.constructor_function { return true; } if node.tag != blot_check_core::Tag.reference { return false; } let reference = source.reference(id);
    if reference.unit == 0 || reference.unit == owner.unit_id { if owner.templates.contains(reference.binding) { return true; } if source.types.node(node.ty).tag != blot_check_types::Tag.function { return false; } let kind = source.binding(reference.binding).kind; return kind == blot_check_core::BindingKind.global || kind == blot_check_core::BindingKind.external; } return source.types.node(node.ty).tag == blot_check_types::Tag.function;
}
recursive fn sourceArgumentLayout(owner: Owner&,selected: u32,actual: u32,depth: i64) -> u32,Error {
    let generator .= owner.generator; if depth >= 1024 { return 0,generator.decline(owner.unit_id,blot_check_core::Span { 0,0 },blot_backend_core_backend::Code.complexity); } if selected == blot_backend_layout::erased { return actual,Error.none; } let wanted = generator.representations.store.node(selected); let given = generator.representations.store.node(actual); if wanted.tag != given.tag { return selected,Error.none; }
    if wanted.tag == blot_backend_layout::Tag.function { let parameter,error = sourceArgumentLayout(owner,wanted.a,given.a,depth + 1); if error != Error.none { return 0,error; } let result,result_error = sourceArgumentLayout(owner,wanted.b,given.b,depth + 1); if result_error != Error.none { return 0,result_error; } return generator.internLayoutWithEffects(blot_backend_layout::Tag.function,parameter,result,wanted.c,[]); }
    if wanted.tag == blot_backend_layout::Tag.array || wanted.tag == blot_backend_layout::Tag.list { let parameter,error = sourceArgumentLayout(owner,wanted.a,given.a,depth + 1); if error != Error.none { return 0,error; } return generator.internLayoutWithEffects(wanted.tag,parameter,wanted.b,wanted.c,[]); }
    if wanted.tag != blot_backend_layout::Tag.product && wanted.tag != blot_backend_layout::Tag.nominal && wanted.tag != blot_backend_layout::Tag.record { return selected,Error.none; }
    if wanted.tag == blot_backend_layout::Tag.nominal && (wanted.a != given.a || wanted.b != given.b) { return selected,Error.none; } let count = generator.representations.store.children(selected).len; if count != generator.representations.store.children(actual).len { return selected,Error.none; } var children = WordBuffer {};
    recursive fn collect() -> u32,Error {
        if wanted.tag == blot_backend_layout::Tag.record {
            var index: i64 = 0; while index < count { let name = generator.representations.store.children(selected)[index]; let left = generator.representations.store.children(selected)[index + 1]; var right = blot_support::none<u32>(); var position: i64 = 0;
                while position < count { if generator.representations.store.children(actual)[position] == name { right = blot_support::some(generator.representations.store.children(actual)[position + 1]); break; } position += 2; } if !right.present { return selected,Error.none; } let named = children.push(name); if named != Error.none { return 0,named; } let child,error = sourceArgumentLayout(owner,left,right.value,depth + 1); if error != Error.none { return 0,error; } let appended = children.push(child); if appended != Error.none { return 0,appended; } index += 2;
            } return generator.internLayout(blot_backend_layout::Tag.record,0,0,children.items);
        }
        for index in 0..count { let left = generator.representations.store.children(selected)[index]; let right = generator.representations.store.children(actual)[index]; let child,error = sourceArgumentLayout(owner,left,right,depth + 1); if error != Error.none { return 0,error; } let appended = children.push(child); if appended != Error.none { return 0,appended; } }
        var unit: u32 = 0; var declaration: u32 = 0; if wanted.tag == blot_backend_layout::Tag.nominal { unit = wanted.a; declaration = wanted.b; } return generator.internLayout(wanted.tag,unit,declaration,children.items);
    }
    let result,error = collect(); children.deinit(); return result,error;
}
fn callableTemplate(owner: Owner&,id: u32) -> blot_support::Option<Template>,Error {
    let evaluated,evaluated_error = staticCallableTemplate(owner,id); if evaluated_error != Error.none || evaluated.present { return evaluated,evaluated_error; } let source .= owner.generator.unit(owner.unit_id); let node = source.node(id);
    if node.tag == blot_check_core::Tag.closure || node.tag == blot_check_core::Tag.primitive_function || node.tag == blot_check_core::Tag.constructor_function { let template,error = newTemplate(owner,id); if error != Error.none { return blot_support::none<Template>(),error; } return blot_support::some(template),Error.none; }
    if node.tag != blot_check_core::Tag.reference { return blot_support::none<Template>(),Error.none; } let reference = source.reference(id); if reference.unit == 0 || reference.unit == owner.unit_id { let template .= owner.templates.get(reference.binding); if template != null { if template.computation { return blot_support::none<Template>(),Error.none; } let selected,error = templateAt(owner,template,id); if error != Error.none { return blot_support::none<Template>(),error; } return blot_support::some(selected),Error.none; } let kind = source.binding(reference.binding).kind; if kind != blot_check_core::BindingKind.global && kind != blot_check_core::BindingKind.external { return blot_support::none<Template>(),Error.none; } }
    let template,error = newTemplate(owner,id); if error != Error.none { return blot_support::none<Template>(),error; } return blot_support::some(template),Error.none;
}
recursive fn computationTemplate(owner: Owner&,id: u32) -> blot_support::Option<Template>,Error {
    let generator .= owner.generator; let source .= generator.unit(owner.unit_id); let node = source.node(id);
    if node.tag == blot_check_core::Tag.reference { let reference = source.reference(id); if reference.unit == 0 || reference.unit == owner.unit_id { let template .= owner.templates.get(reference.binding); if template != null && template.computation { return blot_support::some(template),Error.none; } } return blot_support::none<Template>(),Error.none; }
    if node.tag == blot_check_core::Tag.computation { let callable,error = callableTemplate(owner,node.a); if error != Error.none || !callable.present { return blot_support::none<Template>(),error; } var template = callable.value; template.computation = true; return blot_support::some(template),Error.none; }
    var selected = blot_support::none<FactoryPlan>(); match node.tag { apply=>{ match resolvedPlan(owner,id) { application plan=>{ selected = plan.value.factory; },_=>{ assert(false); }, } },call=>{ match resolvedPlan(owner,id) { named plan=>{ selected = plan.value.factory; },_=>{ assert(false); }, } },_=>{ return blot_support::none<Template>(),Error.none; }, } if !selected.present { return blot_support::none<Template>(),Error.none; } let plan = selected.value;
    var arguments: u32[16]; var environment = blot_support::none<u32>();
    recursive fn invoke(operands: const u32[:]) -> blot_support::Option<Template>,Error {
        for argument,index in operands {
            if node.tag == blot_check_core::Tag.apply { let scalar_type,scalar_error = scalar(owner,argument); if scalar_error != Error.none { return blot_support::none<Template>(),scalar_error; } let local,error = temporary(owner,blot_backend_runtime_ir::machine(scalar_type)); if error != Error.none { return blot_support::none<Template>(),error; } arguments[index] = local; }
            if plan.admitted[index] {
                let argument_node = source.node(argument); var retained = blot_support::none<Template>(); if argument_node.tag == blot_check_core::Tag.reference { let reference = source.reference(argument); if reference.unit == 0 || reference.unit == owner.unit_id { let known .= owner.templates.get(reference.binding); if known != null { retained = blot_support::some(known); } } }
                if !retained.present { let callable,error = callableTemplate(owner,argument); if error != Error.none { return blot_support::none<Template>(),error; } retained = callable; } if !retained.present { return blot_support::none<Template>(),generator.fail(owner.unit_id,argument,blot_backend_core_backend::Code.unresolved_type); } let metadata = retained.value;
                if node.tag != blot_check_core::Tag.apply { let local,error = temporary(owner,blot_backend_runtime_ir::VT_i32); if error != Error.none { return blot_support::none<Template>(),error; } arguments[index] = local; } var loaded: Error; if metadata.environment.present { loaded = emit(owner,blot_backend_runtime_ir::OP_local_get,metadata.environment.value); } else { loaded = emit(owner,blot_backend_runtime_ir::OP_i32_const,0); } if loaded != Error.none { return blot_support::none<Template>(),loaded; } let saved = emit(owner,blot_backend_runtime_ir::OP_local_set,arguments[index]); if saved != Error.none { return blot_support::none<Template>(),saved; }
            } else if node.tag == blot_check_core::Tag.apply { let evaluated = expression(owner,argument,0); if evaluated != Error.none { return blot_support::none<Template>(),evaluated; } let saved = emit(owner,blot_backend_runtime_ir::OP_local_set,arguments[index]); if saved != Error.none { return blot_support::none<Template>(),saved; } }
            else { let value,error = capture(owner,argument,0); if error != Error.none { return blot_support::none<Template>(),error; } arguments[index] = value; }
        }
        var function: u32 = 0; match plan.callee { named named=>{ let selected,error = generator.function(named.key); if error != Error.none { return blot_support::none<Template>(),error; } function = selected; },closure closure=>{ let selected,error = generator.closureFunction(closure.key); if error != Error.none { return blot_support::none<Template>(),error; } function = selected; }, }
        if node.tag == blot_check_core::Tag.apply { var loaded: Error; if environment.present { loaded = emit(owner,blot_backend_runtime_ir::OP_local_get,environment.value); } else { loaded = emit(owner,blot_backend_runtime_ir::OP_i32_const,0); } if loaded != Error.none { return blot_support::none<Template>(),loaded; } } let loaded = emitLocals(owner,arguments[..operands.len]); if loaded != Error.none { return blot_support::none<Template>(),loaded; } let provider = providerHead(owner); if provider != Error.none { return blot_support::none<Template>(),provider; } let called = emit(owner,blot_backend_runtime_ir::OP_call,function); if called != Error.none { return blot_support::none<Template>(),called; }
        let result_environment,error = temporary(owner,blot_backend_runtime_ir::VT_i32); if error != Error.none { return blot_support::none<Template>(),error; } let saved = emit(owner,blot_backend_runtime_ir::OP_local_set,result_environment); if saved != Error.none { return blot_support::none<Template>(),saved; } var result = plan.result; if result.environment.present { result.environment = blot_support::some(result_environment); } return blot_support::some(result),Error.none;
    }
    if node.tag == blot_check_core::Tag.apply { let factory,error = callableTemplate(owner,node.a); if error != Error.none { return blot_support::none<Template>(),error; } if !factory.present { return blot_support::none<Template>(),generator.fail(owner.unit_id,node.a,blot_backend_core_backend::Code.unresolved_type); } environment = factory.value.environment; return invoke([node.b]); } return invoke(source.call(id).arguments);
}
fn boxTemplate(owner: Owner&,template: Template) -> Template,Error {
    if !template.scalar_environment { return template,Error.none; } let environment,error = allocate(owner,4,AllocationRoles { words: [blot_backend_runtime_ir::ROLE_scalar] }); if error != Error.none { return template,error; } assert(template.environment.present); let stored = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,environment),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,template.environment.value),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_store,0)]); if stored != Error.none { return template,stored; } var boxed = template; boxed.environment = blot_support::some(environment); boxed.scalar_environment = false; return boxed,Error.none;
}
fn publishTemplate(owner: Owner&,supplied: Template,source: u32) -> Error {
    let template,error = boxTemplate(owner,supplied); if error != Error.none { return error; } let retained,retained_error = owner.generator.captureTemplate(template); if retained_error != Error.none { return retained_error; } if owner.result_template.present { if owner.result_template.value != retained { return owner.generator.fail(owner.unit_id,source,blot_backend_core_backend::Code.unresolved_type); } } else { owner.result_template = blot_support::some(retained); }
    if template.environment.present { return emit(owner,blot_backend_runtime_ir::OP_local_get,template.environment.value); } return emit(owner,blot_backend_runtime_ir::OP_i32_const,0);
}
recursive fn templateExpression(owner: Owner&,id: u32,depth: i64) -> Error {
    let previous_semantic = owner.semantic_node; owner.semantic_node = id;
    recursive fn lower() -> Error {
        let generator .= owner.generator; if depth >= 1024 { return generator.fail(owner.unit_id,id,blot_backend_core_backend::Code.complexity); } let source .= generator.unit(owner.unit_id); let node = source.node(id);
        match node.tag {
            computation,reference,call,apply=>{ let template,error = computationTemplate(owner,id); if error != Error.none { return error; } if !template.present { return generator.fail(owner.unit_id,id,blot_backend_core_backend::Code.unresolved_type); } return publishTemplate(owner,template.value,id); },
            block_=>{ var join = blot_backend_resolved_flow::Join { node: id,result: blot_support::none<blot_backend_runtime_ir::ValueType>(),merges: [] }; match resolvedPlan(owner,id) { join plan=>{ join = plan.value; },_=>{ assert(false); }, } assert(join.result.present); let entered = emit(owner,blot_backend_runtime_ir::OP_block,join.result.value as u32); if entered != Error.none { return entered; }
                let pushed = owner.return_targets.push(ReturnTarget { node: id,label: owner.labels,cleanup: owner.cleanups.mark(),template_result: true }); if pushed != Error.none { return pushed; } owner.labels++; let terminated,error = suite(owner,id,depth + 1); if error != Error.none { return error; } if terminated { let unreachable = emit(owner,blot_backend_runtime_ir::OP_unreachable_); if unreachable != Error.none { return unreachable; } } else { return generator.fail(owner.unit_id,id,blot_backend_core_backend::Code.unresolved_type); }
                owner.labels--; owner.return_targets.resize(owner.return_targets.items.len - 1); return emit(owner,blot_backend_runtime_ir::OP_end);
            },
            if_value=>{ var join = blot_backend_resolved_flow::Join { node: id,result: blot_support::none<blot_backend_runtime_ir::ValueType>(),merges: [] }; match resolvedPlan(owner,id) { join plan=>{ join = plan.value; },_=>{ assert(false); }, } assert(join.result.present); let condition = expression(owner,node.a,depth + 1); if condition != Error.none { return condition; } let entered = emit(owner,blot_backend_runtime_ir::OP_if_,join.result.value as u32); if entered != Error.none { return entered; } owner.labels++;
                let left = templateExpression(owner,node.b,depth + 1); if left != Error.none { return left; } let alternate = emit(owner,blot_backend_runtime_ir::OP_else_); if alternate != Error.none { return alternate; } let right = templateExpression(owner,node.c,depth + 1); if right != Error.none { return right; } owner.labels--; return emit(owner,blot_backend_runtime_ir::OP_end);
            },panic=>{ return emit(owner,blot_backend_runtime_ir::OP_unreachable_); },_=>{ return generator.fail(owner.unit_id,id,blot_backend_core_backend::Code.unresolved_type); },
        }
    }
    let error = lower(); owner.semantic_node = previous_semantic; return error;
}
recursive fn templateValue(owner: Owner&,template: Template,requested: u32) -> Error {
    let generator .= owner.generator; var ty = requested; var dictionaries = false;
    if template.computation { let value = generator.representations.store.node(requested); if value.tag != blot_backend_layout::Tag.nominal || value.a != 4294967295 || value.b != 5 || generator.representations.store.children(requested).len != 1 { return generator.fail(owner.unit_id,template.node,blot_backend_core_backend::Code.unresolved_type); } ty = generator.representations.store.children(requested)[0]; }
    if generator.representations.store.node(ty).tag == blot_backend_layout::Tag.universal { var unit = template.unit; if unit == 0 { unit = owner.unit_id; } let producer .= generator.unit(unit); let principal = producer.typeOf(template.node); dictionaries = producer.types.node(principal).tag == blot_check_types::Tag.forall && producer.types.quantifierGoals(principal).len != 0; ty = generator.representations.store.node(ty).a; }
    let function,error = templateFunction(owner,template,ty,dictionaries); if error != Error.none { return error; } return descriptor(owner,function,template.environment);
}
recursive fn templateFunction(owner: Owner&,template: Template,ty: u32,dictionaries: bool) -> u32,Error {
    let generator .= owner.generator; var unit = template.unit; if unit == 0 { unit = owner.unit_id; } let source .= generator.unit(unit); let node = source.node(template.node);
    match node.tag {
        closure=>{ return generator.closureFunction(blot_reuse_code_artifacts::ClosureKey { unit,catalog: node.a,ty,scalar_environment: template.scalar_environment,captures: template.captures,templates: template.templates,staged: template.staged,evidence: template.evidence,rows: template.rows,dictionaries }); },
        constructor_function=>{ return generator.constructorFunction(blot_reuse_code_artifacts::ConstructorKey { unit,catalog: node.a,ty }); },primitive_function=>{ return generator.primitiveFunction(blot_reuse_code_artifacts::PrimitiveKey { unit,catalog: node.a,ty }); },
        reference=>{ let target,error = generator.normalize(unit,source.reference(template.node)); if error != Error.none { return 0,error; } return generator.callable(blot_reuse_code_artifacts::CallableKey { target,ty,dictionaries,instance_arguments: template.callable_instances }); },_=>{ return 0,generator.fail(owner.unit_id,template.node,blot_backend_core_backend::Code.unsupported); },
    }
}
recursive fn closure(owner: Owner&,id: u32) -> Error { let source .= owner.generator.unit(owner.unit_id); let static_captures,error = closureWithStaticCaptures(owner,id); if error != Error.none || static_captures { return error; } let template,template_error = newTemplate(owner,id); if template_error != Error.none { return template_error; } let ty,type_error = codeLayout(owner,source.typeOf(id),source.span(id)); if type_error != Error.none { return type_error; } return templateValue(owner,template,ty); }
recursive fn closureWithStaticCaptures(owner: Owner&,id: u32) -> bool,Error {
    let generator .= owner.generator; let source .= generator.unit(owner.unit_id); var key = blot_support::none<blot_reuse_code_artifacts::ClosureKey>(); match resolvedPlan(owner,id) { template plan=>{ key = plan.value.static_key; },_=>{ assert(false); }, } if !key.present { return false,Error.none; } let captures = source.closureCaptures(id); var capture_types = WordBuffer {}; var capture_roles = RoleBuffer {};
    recursive fn lower() -> bool,Error {
        let copied = capture_types.append(generator.representations.store.children(key.value.captures)); if copied != Error.none { return false,copied; } let function,error = generator.closureFunction(key.value); if error != Error.none { return false,error; }
        for ty in capture_types.items { let appended = capture_roles.push(generator.layoutRole(ty)); if appended != Error.none { return false,appended; } } for binding,index in captures { if owner.static_values.contains(binding) { capture_roles.items[index] = blot_backend_runtime_ir::ROLE_scalar; } }
        let environment,environment_error = allocate(owner,(captures.len * 4) as u32,AllocationRoles { words: capture_roles.items }); if environment_error != Error.none { return false,environment_error; }
        for binding,index in captures {
            let target = emit(owner,blot_backend_runtime_ir::OP_local_get,environment); if target != Error.none { return false,target; } if owner.static_values.contains(binding) { let cleared = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,0),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_store,(index * 4) as u32)]); if cleared != Error.none { return false,cleared; } continue; }
            var found = false; { let local .= owner.locals.get(binding); if local != null { let loaded = emit(owner,blot_backend_runtime_ir::OP_local_get,local); if loaded != Error.none { return false,loaded; } found = true; } }
            if !found { let template .= owner.templates.get(binding); if template == null { return false,generator.fail(owner.unit_id,id,blot_backend_core_backend::Code.unsupported); } var loaded: Error; if template.environment.present { loaded = emit(owner,blot_backend_runtime_ir::OP_local_get,template.environment.value); } else { loaded = emit(owner,blot_backend_runtime_ir::OP_i32_const,0); } if loaded != Error.none { return false,loaded; } }
            var store = blot_backend_runtime_ir::OP_i32_store; if generator.representations.store.machine(capture_types.items[index]) == blot_backend_runtime_ir::VT_f32 { store = blot_backend_runtime_ir::OP_f32_store; } let stored = emit(owner,store,(index * 4) as u32); if stored != Error.none { return false,stored; }
        }
        let described = descriptor(owner,function,environment); return described == Error.none,described;
    }
    let result,error = lower(); capture_roles.deinit(); capture_types.deinit(); return result,error;
}
fn invokeRequest(owner: Owner&,frame: u32,argument: u32,argument_machine: blot_backend_runtime_ir::ValueType,result_machine: blot_backend_runtime_ir::ValueType,argument_role: blot_backend_runtime_ir::Role) -> Error {
    let generator .= owner.generator; let cell,cell_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if cell_error != Error.none { return cell_error; } let callback,callback_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if callback_error != Error.none { return callback_error; }
    let selected = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,frame),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,blot_runtime_runtime_layout::RequestFrame_cell),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,cell),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,frame),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,blot_runtime_runtime_layout::RequestFrame_target),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,callback)]); if selected != Error.none { return selected; }
    let arena,arena_error = generator.module.ensureArena(); if arena_error != Error.none { return arena_error; } let pair,pair_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if pair_error != Error.none { return pair_error; }
    let classified = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_global_get,arena.rc_enabled),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_eqz),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,cell),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,blot_runtime_runtime_layout::ArenaHeader_bytes),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_sub),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,blot_runtime_runtime_layout::ArenaHeader_layout),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,4),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_and),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_or),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_if_)]); if classified != Error.none { return classified; } owner.labels++;
    let references,reference_error = allocate(owner,blot_runtime_runtime_layout::Pair_bytes,AllocationRoles { words: [argument_role,blot_backend_runtime_ir::ROLE_reference] }); if reference_error != Error.none { return reference_error; } let reference_pair = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,references),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,pair),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_else_)]); if reference_pair != Error.none { return reference_pair; }
    let scalars,scalar_error = allocate(owner,blot_runtime_runtime_layout::Pair_bytes,AllocationRoles { words: [argument_role,blot_backend_runtime_ir::ROLE_scalar] }); if scalar_error != Error.none { return scalar_error; } let scalar_pair = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,scalars),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,pair)]); if scalar_pair != Error.none { return scalar_pair; } owner.labels--; let joined = emit(owner,blot_backend_runtime_ir::OP_end); if joined != Error.none { return joined; }
    var argument_scalar = blot_backend_runtime_ir::SC_u32; if argument_machine == blot_backend_runtime_ir::VT_f32 { argument_scalar = blot_backend_runtime_ir::SC_f32; } let stored = storeTypedWord(owner,pair,blot_runtime_runtime_layout::Pair_first,argument,argument_scalar,0); if stored != Error.none { return stored; }
    let state,state_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if state_error != Error.none { return state_error; } let initial = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,cell),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,blot_runtime_runtime_layout::RequestCell_state),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,state)]); if initial != Error.none { return initial; } let state_pair = storeTypedWord(owner,pair,blot_runtime_runtime_layout::Pair_second,state,blot_backend_runtime_ir::SC_u32,0); if state_pair != Error.none { return state_pair; }
    let arguments = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,callback),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,blot_runtime_runtime_layout::Closure_environment),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,pair),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,frame),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,blot_runtime_runtime_layout::RequestFrame_runner_outer),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,callback),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,blot_runtime_runtime_layout::Closure_function)]); if arguments != Error.none { return arguments; }
    let annotated = generator.module.emit(owner.function_id,blot_backend_runtime_ir::callResult(blot_backend_runtime_ir::ROLE_reference)); if annotated != Error.none { return annotated; } let signature,signature_error = generator.module.internType([blot_backend_runtime_ir::VT_i32,blot_backend_runtime_ir::VT_i32,blot_backend_runtime_ir::VT_i32],blot_backend_runtime_ir::VT_i32); if signature_error != Error.none { return signature_error; } let called = emit(owner,blot_backend_runtime_ir::OP_call_indirect,signature); if called != Error.none { return called; }
    let decision,decision_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if decision_error != Error.none { return decision_error; } let returned = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,decision),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,decision),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,blot_runtime_runtime_layout::Decision_state),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,state)]); if returned != Error.none { return returned; } let updated = storeTypedWord(owner,cell,blot_runtime_runtime_layout::RequestCell_state,state,blot_backend_runtime_ir::SC_u32,0); if updated != Error.none { return updated; }
    let branch = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,decision),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,blot_runtime_runtime_layout::Decision_kind),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_eqz),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_if_,result_machine as u32),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,decision)]); if branch != Error.none { return branch; } var load = blot_backend_runtime_ir::OP_i32_load; if result_machine == blot_backend_runtime_ir::VT_f32 { load = blot_backend_runtime_ir::OP_f32_load; } let reply = emit(owner,load,blot_runtime_runtime_layout::Decision_payload); if reply != Error.none { return reply; }
    let checked = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_else_),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,decision),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,blot_runtime_runtime_layout::Decision_kind),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,blot_check_core::requestDecisionKindCode(blot_check_core::RequestDecisionKind.break_)),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_gt_u),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_if_),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_unreachable_),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_end),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,decision),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,blot_runtime_runtime_layout::Decision_kind),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,state)]); if checked != Error.none { return checked; }
    let status = storeTypedWord(owner,cell,blot_runtime_runtime_layout::RequestCell_status,state,blot_backend_runtime_ir::SC_u32,0); if status != Error.none { return status; } let payload = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,decision),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,blot_runtime_runtime_layout::Decision_payload),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,state)]); if payload != Error.none { return payload; } let exited = storeTypedWord(owner,cell,blot_runtime_runtime_layout::RequestCell_exit,state,blot_backend_runtime_ir::SC_u32,0); if exited != Error.none { return exited; }
    assert(generator.request_owner.present); let published = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,cell),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_global_set,generator.request_owner.value)]); if published != Error.none { return published; } let dummy = blot_runtime_request_runtime::dummy(generator.module,owner.function_id,owner.cleanups); if dummy != Error.none { return dummy; } return emit(owner,blot_backend_runtime_ir::OP_end);
}
recursive fn requestDecision(owner: Owner&,id: u32,depth: i64) -> Error {
    let generator .= owner.generator; let source .= generator.unit(owner.unit_id); let node = source.node(id); var payload = blot_support::none<u32>(); var state = blot_support::none<u32>();
    if node.b != 0 { let value,error = capture(owner,node.b,depth); if error != Error.none { return error; } payload = blot_support::some(value); } if node.c != 0 { let value,error = capture(owner,node.c,depth); if error != Error.none { return error; } state = blot_support::some(value); }
    var payload_role = blot_backend_runtime_ir::ROLE_scalar; var state_role = blot_backend_runtime_ir::ROLE_scalar; if node.b != 0 { let concrete,error = codeLayout(owner,source.typeOf(node.b),source.span(id)); if error != Error.none { return error; } payload_role = generator.layoutRole(concrete); } if node.c != 0 { let concrete,error = codeLayout(owner,source.typeOf(node.c),source.span(id)); if error != Error.none { return error; } state_role = generator.layoutRole(concrete); }
    let decision,error = allocate(owner,blot_runtime_runtime_layout::Decision_bytes,AllocationRoles { words: [blot_backend_runtime_ir::ROLE_scalar,payload_role,state_role] }); if error != Error.none { return error; } let kind = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,decision),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,node.a),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_store,blot_runtime_runtime_layout::Decision_kind),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,decision)]); if kind != Error.none { return kind; }
    var loaded: Error; if payload.present { loaded = emit(owner,blot_backend_runtime_ir::OP_local_get,payload.value); } else { loaded = emit(owner,blot_backend_runtime_ir::OP_i32_const,0); } if loaded != Error.none { return loaded; } var payload_store = blot_backend_runtime_ir::OP_i32_store; if node.b != 0 { let scalar_type,scalar_error = scalar(owner,node.b); if scalar_error != Error.none { return scalar_error; } if scalar_type == blot_backend_runtime_ir::SC_f32 { payload_store = blot_backend_runtime_ir::OP_f32_store; } } let payload_stored = emit(owner,payload_store,blot_runtime_runtime_layout::Decision_payload); if payload_stored != Error.none { return payload_stored; }
    let target = emit(owner,blot_backend_runtime_ir::OP_local_get,decision); if target != Error.none { return target; } if state.present { loaded = emit(owner,blot_backend_runtime_ir::OP_local_get,state.value); } else { loaded = emit(owner,blot_backend_runtime_ir::OP_i32_const,0); } if loaded != Error.none { return loaded; } var state_store = blot_backend_runtime_ir::OP_i32_store; if node.c != 0 { let scalar_type,scalar_error = scalar(owner,node.c); if scalar_error != Error.none { return scalar_error; } if scalar_type == blot_backend_runtime_ir::SC_f32 { state_store = blot_backend_runtime_ir::OP_f32_store; } } let state_stored = emit(owner,state_store,blot_runtime_runtime_layout::Decision_state); if state_stored != Error.none { return state_stored; } return emit(owner,blot_backend_runtime_ir::OP_local_get,decision);
}
recursive fn requestStateValue(owner: Owner&,id: u32,binding: u32,ty: u32) -> Error {
    { let template .= owner.templates.get(binding); if template != null { return templateValue(owner,template,ty); } } { let local .= owner.locals.get(binding); if local != null { return emit(owner,blot_backend_runtime_ir::OP_local_get,local); } }
    { let value .= owner.static_values.get(binding); if value != null { let scalar = owner.generator.evaluator.valueScalar(value); if scalar.present { var op = blot_backend_runtime_ir::OP_i32_const; if scalar.value.scalar == blot_backend_runtime_ir::SC_f32 { op = blot_backend_runtime_ir::OP_f32_const; } return emit(owner,op,scalar.value.bits); }
        let bits,error = owner.generator.static_data.serialize(owner.generator,value,ty,0); if error != Error.none { return error; } let selected = owner.generator.representations.store.scalar(ty); var scalar_type = blot_backend_runtime_ir::SC_pointer; if selected.present { scalar_type = selected.value; } return owner.generator.emitValue(owner.function_id,blot_backend_scalar_ops::Value { scalar_type,bits });
    } } return owner.generator.fail(owner.unit_id,id,blot_backend_core_backend::Code.unsupported);
}
recursive fn requestState(owner: Owner&,id: u32,carries: const blot_check_core::LoopCarry[:],ty: u32) -> u32,Error {
    let generator .= owner.generator; if carries.len == 1 { let state,error = temporary(owner,generator.representations.store.machine(ty)); if error != Error.none { return 0,error; } let value = requestStateValue(owner,id,carries[0].incoming,ty); if value != Error.none { return 0,value; } let saved = emit(owner,blot_backend_runtime_ir::OP_local_set,state); return state,saved; }
    if carries.len == 0 { let value,error = temporary(owner,blot_backend_runtime_ir::VT_i32); if error != Error.none { return 0,error; } let initialized = emitConstantLocal(owner,0,value); return value,initialized; } if carries.len > 4294967295 / 4 { return 0,generator.fail(owner.unit_id,id,blot_backend_core_backend::Code.complexity); } var child_types = WordBuffer {}; var roles = RoleBuffer {};
    recursive fn lower() -> u32,Error {
        let copied = child_types.append(generator.representations.store.children(ty)); if copied != Error.none { return 0,copied; } if child_types.items.len != carries.len { return 0,generator.fail(owner.unit_id,id,blot_backend_core_backend::Code.unresolved_type); } for child in child_types.items { let appended = roles.push(generator.layoutRole(child)); if appended != Error.none { return 0,appended; } }
        let state,error = allocate(owner,(carries.len * 4) as u32,AllocationRoles { words: roles.items }); if error != Error.none { return 0,error; } for carry,index in carries { let target = emit(owner,blot_backend_runtime_ir::OP_local_get,state); if target != Error.none { return 0,target; } let value = requestStateValue(owner,id,carry.incoming,child_types.items[index]); if value != Error.none { return 0,value; } var store = blot_backend_runtime_ir::OP_i32_store; if generator.representations.store.machine(child_types.items[index]) == blot_backend_runtime_ir::VT_f32 { store = blot_backend_runtime_ir::OP_f32_store; } let stored = emit(owner,store,(index * 4) as u32); if stored != Error.none { return 0,stored; } } return state,Error.none;
    }
    let state,error = lower(); roles.deinit(); child_types.deinit(); return state,error;
}
fn requestBindState(owner: Owner&,id: u32,state: u32,bindings: const u32[:]) -> Error {
    let generator .= owner.generator; for binding,index in bindings { let ty,error = generator.scalarWithRows(owner.unit_id,generator.unit(owner.unit_id).binding(binding).ty,owner.mappings,owner.row_mappings,generator.unit(owner.unit_id).span(id)); if error != Error.none { return error; } let loaded = emit(owner,blot_backend_runtime_ir::OP_local_get,state); if loaded != Error.none { return loaded; }
        if bindings.len > 1 { var load = blot_backend_runtime_ir::OP_i32_load; if ty == blot_backend_runtime_ir::SC_f32 { load = blot_backend_runtime_ir::OP_f32_load; } let field = emit(owner,load,(index * 4) as u32); if field != Error.none { return field; } } let saved = save(owner,binding,id); if saved != Error.none { return saved; }
    } return Error.none;
}
recursive fn requestLoop(owner: Owner&,id: u32,depth: i64) -> Error {
    let checkpoint = owner.cleanups.mark();
    recursive fn lower(plan: blot_backend_resolved_flow::RequestLoop) -> Error {
        let generator .= owner.generator; let source .= generator.unit(owner.unit_id); let exited,exit_error = bindExit(owner,plan.exited); if exit_error != Error.none { return exit_error; } let exit_label = owner.labels; let metadata = source.requestLoopInfo(id); let carries = plan.broken.carries;
        let computation,computation_error = capture(owner,metadata.computation,depth); if computation_error != Error.none { return computation_error; } let state_layout,layout_error = codeLayout(owner,metadata.state_type,source.span(id)); if layout_error != Error.none { return layout_error; } let initial,initial_error = requestState(owner,id,carries,state_layout); if initial_error != Error.none { return initial_error; }
        let state_machine = generator.representations.store.machine(state_layout); let value_scalar,value_error = generator.scalarWithRows(owner.unit_id,metadata.value_type,owner.mappings,owner.row_mappings,source.span(id)); if value_error != Error.none { return value_error; } let result_scalar,result_error = generator.scalarWithRows(owner.unit_id,metadata.result_type,owner.mappings,owner.row_mappings,source.span(id)); if result_error != Error.none { return result_error; }
        let value_machine = blot_backend_runtime_ir::machine(value_scalar); let result_machine = blot_backend_runtime_ir::machine(result_scalar); let result_layout,result_layout_error = codeLayout(owner,metadata.result_type,source.span(id)); if result_layout_error != Error.none { return result_layout_error; }
        let cell,cell_error = allocatePrivate(owner,blot_runtime_runtime_layout::RequestCell_bytes,AllocationRoles { words: [blot_backend_runtime_ir::ROLE_scalar,generator.layoutRole(result_layout),generator.layoutRole(state_layout)] }); if cell_error != Error.none { return cell_error; }
        let initialized = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,cell),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,0),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_store,blot_runtime_runtime_layout::RequestCell_status),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,cell),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,0),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_store,blot_runtime_runtime_layout::RequestCell_exit),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,cell),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,initial)]); if initialized != Error.none { return initialized; }
        var state_store = blot_backend_runtime_ir::OP_i32_store; if state_machine == blot_backend_runtime_ir::VT_f32 { state_store = blot_backend_runtime_ir::OP_f32_store; } let initial_stored = emit(owner,state_store,blot_runtime_runtime_layout::RequestCell_state); if initial_stored != Error.none { return initial_stored; }
        let outer,outer_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if outer_error != Error.none { return outer_error; } let head = providerHead(owner); if head != Error.none { return head; } let outer_saved = emit(owner,blot_backend_runtime_ir::OP_local_set,outer); if outer_saved != Error.none { return outer_saved; } let provider,provider_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if provider_error != Error.none { return provider_error; } let provider_saved = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,outer),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,provider)]); if provider_saved != Error.none { return provider_saved; }
        for arm,index in plan.arms {
            let operation = plan.operations[index]; let callback,callback_error = capture(owner,arm.callback,depth); if callback_error != Error.none { return callback_error; } let scoped = arm.selector != 0; var authority = blot_support::none<u32>(); if scoped { let value,error = operationOwner(owner,arm.selector,depth); if error != Error.none { return error; } authority = blot_support::some(value); }
            var frame: u32; if scoped { let value,error = allocatePrivate(owner,blot_runtime_runtime_layout::ScopedRequestFrame_bytes,AllocationRoles { words: blot_runtime_runtime_layout::layout_roles(default<blot_runtime_runtime_layout::ScopedRequestFrame>()) }); if error != Error.none { return error; } frame = value; } else { let value,error = allocatePrivate(owner,blot_runtime_runtime_layout::RequestFrame_bytes,AllocationRoles { words: blot_runtime_runtime_layout::layout_roles(default<blot_runtime_runtime_layout::RequestFrame>()) }); if error != Error.none { return error; } frame = value; }
            if authority.present { let stored = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,frame),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,authority.value),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_store,blot_runtime_runtime_layout::ScopedRequestFrame_owner)]); if stored != Error.none { return stored; } }
            let operation_target = emit(owner,blot_backend_runtime_ir::OP_local_get,frame); if operation_target != Error.none { return operation_target; } let runtime_operation,runtime_error = generator.runtimeOperation(operation,owner.unit_id,source.span(id)); if runtime_error != Error.none { return runtime_error; } let operation_value = operationConstant(owner,runtime_operation); if operation_value != Error.none { return operation_value; } let operation_stored = emit(owner,blot_backend_runtime_ir::OP_i32_store,blot_runtime_runtime_layout::RequestFrame_operation); if operation_stored != Error.none { return operation_stored; }
            var kind = blot_runtime_request_runtime::request_kind; if scoped { kind = blot_runtime_runtime_layout::ScopedRequestFrame_tag; }
            let fields = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,frame),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,callback),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_store,blot_runtime_runtime_layout::RequestFrame_target),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,frame),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,provider),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_store,blot_runtime_runtime_layout::RequestFrame_outer),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,frame),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,kind),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_store,blot_runtime_runtime_layout::RequestFrame_kind),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,frame),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,cell),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_store,blot_runtime_runtime_layout::RequestFrame_cell),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,frame),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,outer),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_store,blot_runtime_runtime_layout::RequestFrame_runner_outer)]); if fields != Error.none { return fields; }
            let origin_operation,origin_error = generator.runtimeOperation(operation,owner.unit_id,source.span(id)); if origin_error != Error.none { return origin_error; } let origin = providerOrigin(owner,frame,kind,blot_backend_runtime_ir::ROLE_reference,origin_operation,blot_support::none<u32>()); if origin != Error.none { return origin; } let selected = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,frame),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,provider)]); if selected != Error.none { return selected; }
        }
        let value,value_local_error = temporary(owner,value_machine); if value_local_error != Error.none { return value_local_error; } let arguments = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,computation),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,blot_runtime_runtime_layout::Closure_environment),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,0),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,provider),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,computation),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,blot_runtime_runtime_layout::Closure_function)]); if arguments != Error.none { return arguments; }
        let value_layout,value_layout_error = codeLayout(owner,metadata.value_type,source.span(id)); if value_layout_error != Error.none { return value_layout_error; } let annotated = generator.module.emit(owner.function_id,blot_backend_runtime_ir::callResult(generator.layoutRole(value_layout))); if annotated != Error.none { return annotated; } let signature,signature_error = generator.module.internType([blot_backend_runtime_ir::VT_i32,blot_backend_runtime_ir::VT_i32,blot_backend_runtime_ir::VT_i32],value_machine); if signature_error != Error.none { return signature_error; } let called = emitUnguarded(owner,blot_backend_runtime_ir::OP_call_indirect,signature); if called != Error.none { return called; } let saved = emit(owner,blot_backend_runtime_ir::OP_local_set,value); if saved != Error.none { return saved; }
        assert(generator.request_owner.present); let run = blot_runtime_request_runtime::runner(generator.module,owner.function_id,generator.request_owner.value,cell,owner.cleanups); if run != Error.none { return run; } let state,state_error = temporary(owner,state_machine); if state_error != Error.none { return state_error; } let cell_loaded = emit(owner,blot_backend_runtime_ir::OP_local_get,cell); if cell_loaded != Error.none { return cell_loaded; } var state_load = blot_backend_runtime_ir::OP_i32_load; if state_machine == blot_backend_runtime_ir::VT_f32 { state_load = blot_backend_runtime_ir::OP_f32_load; } let state_value = emitInstructions(owner,[blot_backend_runtime_ir::instruction(state_load,blot_runtime_runtime_layout::RequestCell_state),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,state)]); if state_value != Error.none { return state_value; }
        assert(owner.labels == exit_label); let broken = plan.broken.bind(exit_label,owner.cleanups.mark()); let entered = emit(owner,blot_backend_runtime_ir::OP_block); if entered != Error.none { return entered; } owner.labels++; let target = owner.loop_targets.push(LoopTarget { node: id,label: broken.label,cleanup: broken.cleanup,backedge: blot_support::none<ContinueTarget>() }); if target != Error.none { return target; }
        let exit_test = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,cell),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,blot_runtime_runtime_layout::RequestCell_status),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,blot_runtime_runtime_layout::RequestStatus_exited),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_eq),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_if_)]); if exit_test != Error.none { return exit_test; } owner.labels++;
        let result_target = emit(owner,blot_backend_runtime_ir::OP_local_get,cell); if result_target != Error.none { return result_target; } var result_load = blot_backend_runtime_ir::OP_i32_load; if result_machine == blot_backend_runtime_ir::VT_f32 { result_load = blot_backend_runtime_ir::OP_f32_load; } let result_value = emit(owner,result_load,blot_runtime_runtime_layout::RequestCell_exit); if result_value != Error.none { return result_value; } let taken = takeExit(owner,exited); if taken != Error.none { return taken; } owner.labels--; let exited_end = emit(owner,blot_backend_runtime_ir::OP_end); if exited_end != Error.none { return exited_end; }
        let break_test = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,cell),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,blot_runtime_runtime_layout::RequestCell_status),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,blot_runtime_runtime_layout::RequestStatus_broken),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_eq),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_if_)]); if break_test != Error.none { return break_test; } owner.labels++;
        for carry,index in carries { let ty,error = generator.scalarWithRows(owner.unit_id,source.binding(carry.outgoing).ty,owner.mappings,owner.row_mappings,source.span(id)); if error != Error.none { return error; } let loaded = emit(owner,blot_backend_runtime_ir::OP_local_get,state); if loaded != Error.none { return loaded; } if carries.len > 1 { var load = blot_backend_runtime_ir::OP_i32_load; if ty == blot_backend_runtime_ir::SC_f32 { load = blot_backend_runtime_ir::OP_f32_load; } let field = emit(owner,load,(index * 4) as u32); if field != Error.none { return field; } } let bound = save(owner,carry.outgoing,id); if bound != Error.none { return bound; } }
        assert(owner.cleanups.since(broken.cleanup).len == 0); let broken_exit = takeExit(owner,broken); if broken_exit != Error.none { return broken_exit; } owner.labels--; let broken_end = emit(owner,blot_backend_runtime_ir::OP_end); if broken_end != Error.none { return broken_end; } let bound = requestBindState(owner,id,state,source.requestCompletionBindings(id)); if bound != Error.none { return bound; }
        let pattern_block = emit(owner,blot_backend_runtime_ir::OP_block); if pattern_block != Error.none { return pattern_block; } let pattern_failure = owner.labels; owner.labels++; let matched = matchPattern(owner,id,plan.completion_pattern,value,pattern_failure,depth + 1); if matched != Error.none { return matched; } let terminated,suite_error = suite(owner,plan.completion_body,depth + 1); if suite_error != Error.none { return suite_error; } let unreachable = emit(owner,blot_backend_runtime_ir::OP_unreachable_); if unreachable != Error.none { return unreachable; } owner.labels--; let pattern_end = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_end),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_unreachable_)]); if pattern_end != Error.none { return pattern_end; } owner.labels--; owner.loop_targets.resize(owner.loop_targets.items.len - 1); let ended = emit(owner,blot_backend_runtime_ir::OP_end); if ended != Error.none { return ended; } return cleanupTo(owner,checkpoint);
    }
    var error: Error; match resolvedPlan(owner,id) { request plan=>{ error = lower(plan.value); },_=>{ abort("expected prepared request loop"); }, } owner.cleanups.restore(checkpoint); return error;
}
fn storeTypedWord(owner: Owner&,allocation: u32,offset: u32,local: blot_support::Option<u32>,scalar_type: blot_backend_runtime_ir::Scalar,literal: u32) -> Error {
    let arena,error = owner.generator.module.ensureArena(); if error != Error.none { return error; } let address = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,allocation),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,allocation),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,offset),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_add)]); if address != Error.none { return address; }
    if local.present { let value = emit(owner,blot_backend_runtime_ir::OP_local_get,local.value); if value != Error.none { return value; } if scalar_type == blot_backend_runtime_ir::SC_f32 { let bits = emit(owner,blot_backend_runtime_ir::OP_i32_reinterpret_f32); if bits != Error.none { return bits; } } } else { let value = emit(owner,blot_backend_runtime_ir::OP_i32_const,literal); if value != Error.none { return value; } } return emit(owner,blot_backend_runtime_ir::OP_call,arena.store_word);
}
fn storeTypedWord(owner: Owner&,allocation: u32,offset: u32,local: u32,scalar_type: blot_backend_runtime_ir::Scalar,literal: u32) -> Error { storeTypedWord(owner,allocation,offset,blot_support::some(local),scalar_type,literal) }
recursive fn prepareStaticClosure(owner: Owner&,id: u32) -> blot_support::Option<StaticClosurePlan>,Error {
    assert(owner.preparing); let generator .= owner.generator; let source .= generator.unit(owner.unit_id); let node = source.node(id); if owner.static_values.table.count == 0 { return blot_support::none<StaticClosurePlan>(),Error.none; }
    let value,value_error = staticReference(owner,node.a); if value_error != Error.none || !value.present { return blot_support::none<StaticClosurePlan>(),value_error; } if generator.evaluator.valueInfo(value.value).kind != blot_eval_core_eval::ValueKind.closure { return blot_support::none<StaticClosurePlan>(),Error.none; }
    let header = generator.evaluator.closureInfo(value.value); if header.origin != blot_eval_core_eval::ClosureOrigin.anonymous { return blot_support::none<StaticClosurePlan>(),Error.none; } let ty,type_error = codeLayout(owner,source.typeOf(node.a),source.span(id)); if type_error != Error.none { return blot_support::none<StaticClosurePlan>(),type_error; } let arrow = generator.representations.store.node(ty);
    if arrow.tag != blot_backend_layout::Tag.function || arrow.c == blot_backend_layout::unknown_row { return blot_support::none<StaticClosurePlan>(),Error.none; } let evidence,evidence_error = generator.representations.toEvidence(generator.evaluator.evidenceStore(),ty); if evidence_error == Error.none { return blot_support::none<StaticClosurePlan>(),Error.none; } if evidence_error == Error.out_of_memory { return blot_support::none<StaticClosurePlan>(),evidence_error; } if evidence_error != Error.unresolved_type || hasErasedType(owner,ty,0) { return blot_support::none<StaticClosurePlan>(),Error.none; }
    let producer .= generator.unit(header.unit); let metadata = producer.closures[header.identity]; let bindings = producer.extra[metadata.captures.start..metadata.captures.start + metadata.captures.len]; let captured = copyWords(generator.evaluator.valueChildren(value.value)); var mappings = MappingBuffer {}; var rows = RowBuffer {}; var hints = blot_backend_substitution_buffers::Hints {}; var argument_rows = blot_backend_substitution_buffers::EvidenceRows {};
    recursive fn lower() -> blot_support::Option<StaticClosurePlan>,Error {
        if bindings.len != captured.len { return blot_support::none<StaticClosurePlan>(),generator.fail(header.unit,metadata.body,blot_backend_core_backend::Code.unsupported); } if generator.artifacts != null { generator.artifacts.requireFreshCode(); }
        for mapping in generator.evaluator.storage.type_mappings.items[header.mappings.start..header.mappings.start + header.mappings.len] { let concrete,error = generator.representations.fromEvidence(generator.evaluator.evidenceStore(),mapping.evidence); if error != Error.none { if error == Error.out_of_memory { return blot_support::none<StaticClosurePlan>(),error; } return blot_support::none<StaticClosurePlan>(),generator.fail(header.unit,metadata.body,blot_backend_core_backend::Code.unresolved_type); } let mapped = generator.mapType(header.unit,mappings,mapping.variable,concrete,producer.span(metadata.body)); if mapped != Error.none { return blot_support::none<StaticClosurePlan>(),mapped; } }
        let loaded = generator.loadSemanticRows(generator.evaluator.storage.row_mappings.items[header.row_mappings.start..header.row_mappings.start + header.row_mappings.len],rows); if loaded != Error.none { return blot_support::none<StaticClosurePlan>(),loaded; }
        if metadata.function_type != 0 { let mapped = generator.mapCapturedFunction(header.unit,metadata.function_type,ty,mappings,rows,producer.span(metadata.body)); if mapped != Error.none { return blot_support::none<StaticClosurePlan>(),mapped; } } else { let input = generator.mapType(header.unit,mappings,metadata.parameter.ty,arrow.a,metadata.parameter.span); if input != Error.none { return blot_support::none<StaticClosurePlan>(),input; } let output = generator.mapType(header.unit,mappings,producer.typeOf(metadata.body),arrow.b,producer.span(metadata.body)); if output != Error.none { return blot_support::none<StaticClosurePlan>(),output; } }
        if captured.len == 9223372036854775807 && metadata.parameter.binding != 0 { return blot_support::none<StaticClosurePlan>(),generator.fail(header.unit,metadata.body,blot_backend_core_backend::Code.complexity); }
        for binding,index in bindings { let appended = hints.push(blot_eval_core_eval::RetainedCapture { binding,unit: header.unit,node: 0,value: captured[index] }); if appended != Error.none { return blot_support::none<StaticClosurePlan>(),appended; } }
        for mapping in owner.row_mappings { if mapping.row == blot_backend_layout::unknown_row { continue; } let actual,error = generator.representations.rowToEvidence(generator.evaluator.evidenceStore(),mapping.row); if error != Error.none { if error == Error.out_of_memory { return blot_support::none<StaticClosurePlan>(),error; } return blot_support::none<StaticClosurePlan>(),generator.fail(owner.unit_id,id,blot_backend_core_backend::Code.unresolved_type); } let appended = argument_rows.push(blot_eval_type_evidence::RowMapping { variable: mapping.variable,evidence: actual }); if appended != Error.none { return blot_support::none<StaticClosurePlan>(),appended; } }
        if metadata.parameter.binding != 0 { let evidence,error = generator.mappingEvidence(owner.mappings); if error != Error.none { return blot_support::none<StaticClosurePlan>(),error; } let appended = hints.push(blot_eval_core_eval::RetainedCapture { binding: metadata.parameter.binding,unit: owner.unit_id,node: node.b,mappings: evidence,rows: argument_rows.items,signature_only: true }); if appended != Error.none { return blot_support::none<StaticClosurePlan>(),appended; } }
        let refined = generator.refineAccessorMappings(header.unit,header.identity,ty,mappings,rows,producer.span(metadata.body),hints.items); if refined != Error.none { return blot_support::none<StaticClosurePlan>(),refined; } return blot_support::some(StaticClosurePlan { header,ty,captured,mappings: copyMappings(mappings.items),rows: copyRows(rows.items) }),Error.none;
    }
    let result,error = lower(); argument_rows.deinit(); hints.deinit(); rows.deinit(); mappings.deinit(); if error != Error.none || !result.present { freeWords(captured); } return result,error;
}
recursive fn staticApply(owner: Owner&,id: u32,depth: i64) -> bool,Error {
    let generator .= owner.generator; let node = generator.unit(owner.unit_id).node(id); var prepared = blot_support::none<StaticClosurePlan>(); match resolvedPlan(owner,id) { application plan=>{ prepared = plan.value.static_closure; },_=>{ abort("expected prepared application"); }, } if !prepared.present { return false,Error.none; } let plan = prepared.value; generator.evaluator.counters.prepared_static_closures++; let header = plan.header; let producer .= generator.unit(header.unit); let metadata = producer.closures[header.identity]; let bindings = producer.extra[metadata.captures.start..metadata.captures.start + metadata.captures.len]; let argument,argument_error = capture(owner,node.b,depth); if argument_error != Error.none { return false,argument_error; }
    let inline_body = owner.inline_depth < 6 && generator.module.functions[owner.function_id].codeLength() <= 4096 && blot_backend_inline_body::cost(producer,metadata.body).present;
    if !inline_body { let function,error = generator.capturedClosureFunction(header,plan.ty,plan.captured,plan.mappings,plan.rows); if error != Error.none { return false,error; } let arguments = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,0),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,argument)]); if arguments != Error.none { return false,arguments; } let head = providerHead(owner); if head != Error.none { return false,head; } let called = emit(owner,blot_backend_runtime_ir::OP_call,function); return called == Error.none,called; }
    let cleanups,cleanup_error = blot_runtime_runtime_cleanup::initPooled(owner.cleanups); if cleanup_error != Error.none { return false,cleanup_error; } let context,context_error = inlineContext(owner); if context_error != Error.none { var unused = cleanups; unused.deinit(); return false,context_error; }
    var emitter = Owner { generator,unit_id: header.unit,function_id: owner.function_id,provider_local: owner.provider_local,mappings: plan.mappings,row_mappings: plan.rows,cleanups,diagnostic_context: context,labels: owner.labels,inline_depth: owner.inline_depth + 1 };
    if metadata.parameter.binding != 0 { emitter.locals.insert(metadata.parameter.binding,argument); } for binding,index in bindings { emitter.static_values.insert(binding,plan.captured[index]); } let error = bodyExpression(emitter,metadata.body,depth + 1,false); emitter.deinit(); return error == Error.none,error;
}
struct UniversalCallee { layout: u32,quantifier: u32 }
recursive fn universalCallee(owner: Owner&,callee: u32,use: u32) -> blot_support::Option<UniversalCallee>,Error {
    let generator .= owner.generator; let source .= generator.unit(owner.unit_id); let node = source.node(callee); var ty: u32 = 0;
    match node.tag {
        reference=>{ let reference = source.reference(callee); if reference.unit != 0 && reference.unit != owner.unit_id { return blot_support::none<UniversalCallee>(),Error.none; } let declaration = source.binding(reference.binding); if declaration.kind != blot_check_core::BindingKind.parameter && declaration.kind != blot_check_core::BindingKind.local { return blot_support::none<UniversalCallee>(),Error.none; } ty = declaration.ty; },
        project=>{ ty = source.projection(node.b).result_type; },call=>{ let call = source.call(callee); let value,error = source.types.withoutForall(call.callee_type); if error != Error.none { return blot_support::none<UniversalCallee>(),generator.fail(owner.unit_id,use,blot_backend_core_backend::Code.complexity); } ty = value; for argument in call.arguments { let arrow = source.types.node(ty); if arrow.tag != blot_check_types::Tag.function { return blot_support::none<UniversalCallee>(),Error.none; } ty = arrow.b; } },_=>{ return blot_support::none<UniversalCallee>(),Error.none; },
    }
    if source.types.node(ty).tag != blot_check_types::Tag.forall { return blot_support::none<UniversalCallee>(),Error.none; } let representation,error = codeLayout(owner,ty,source.span(use)); if error != Error.none { return blot_support::none<UniversalCallee>(),error; } if generator.representations.store.node(representation).tag != blot_backend_layout::Tag.universal { return blot_support::none<UniversalCallee>(),Error.none; } return blot_support::some(UniversalCallee { layout: representation,quantifier: ty }),Error.none;
}
recursive fn prepareApplication(owner: Owner&,id: u32) -> ApplyPlan,Error {
    assert(owner.preparing); let generator .= owner.generator; let source .= generator.unit(owner.unit_id); let node = source.node(id); let spawn,spawn_error = prepareSpawnApplication(owner,id); if spawn_error != Error.none { return ApplyPlan {},spawn_error; } if spawn.present { return ApplyPlan { spawn },Error.none; } if source.types.node(source.typeOf(node.a)).tag == blot_check_types::Tag.never { return ApplyPlan { never: true },Error.none; } var result = ApplyPlan {};
    recursive fn lower() -> Error {
        let stored,stored_error = universalCallee(owner,node.a,id); if stored_error != Error.none { return stored_error; } if stored.present { let arrow,error = prepareIndirect(owner,node.a,id); if error != Error.none { return error; } result.arrow = blot_support::some(arrow); result.universal = blot_support::some(generator.representations.store.node(stored.value.layout).a); result.quantifier = stored.value.quantifier; return Error.none; }
        let evaluated,evaluated_error = prepareEvaluatedNamed(owner,id); if evaluated_error != Error.none { return evaluated_error; } result.evaluated = evaluated; if result.evaluated.present { let arrow,error = prepareIndirect(owner,node.a,id); if error != Error.none { return error; } result.arrow = blot_support::some(arrow); return Error.none; }
        let closure,closure_error = prepareStaticClosure(owner,id); if closure_error != Error.none { return closure_error; } result.static_closure = closure; if closure.present { return Error.none; } let partial,partial_error = preparePartialStaticCall(owner,id); if partial_error != Error.none { return partial_error; } result.partial = partial;
        let known = blot_backend_known_call::resolve(generator.units,owner.unit_id,id); if known.present && known.value.signature != 0 { let key,error = generator.signature(known.value.target,known.value.signature,owner.unit_id,owner.mappings,owner.row_mappings,source.span(id),false); if error != Error.none { return error; } if key.count == known.value.count { result.known = blot_support::some(SourceCall { key,arguments: known.value.arguments,count: known.value.count }); } }
        let arrow,error = prepareIndirect(owner,node.a,id); if error != Error.none { return error; } result.arrow = blot_support::some(arrow); return Error.none;
    }
    let error = lower(); if error != Error.none { result.deinit(); } return result,error;
}
recursive fn apply(owner: Owner&,id: u32,depth: i64) -> Error {
    let generator .= owner.generator; let source .= generator.unit(owner.unit_id); let node = source.node(id); var prepared = ApplyPlan {}; match resolvedPlan(owner,id) { application plan=>{ prepared = plan.value; },_=>{ abort("expected prepared application"); }, }
    if prepared.spawn.present { return emitSpawnApplication(owner,prepared.spawn.value,depth); }
    if prepared.universal.present {
        assert(prepared.arrow.present); let concrete = prepared.arrow.value; let abstract = generator.representations.store.node(prepared.universal.value); if abstract.tag != blot_backend_layout::Tag.function { return generator.fail(owner.unit_id,id,blot_backend_core_backend::Code.unresolved_type); } let rows = carrierRows(owner,abstract.c,concrete.row,id); if rows != Error.none { return rows; }
        let callee,callee_error = capture(owner,node.a,depth); if callee_error != Error.none { return callee_error; } let input,input_error = capture(owner,node.b,depth); if input_error != Error.none { return input_error; } let argument,argument_error = carrierValue(owner,input,concrete.parameter,abstract.a,0); if argument_error != Error.none { return argument_error; } let qualified = source.types.quantifierGoals(prepared.quantifier).len != 0; var dictionary: u32 = 0; if qualified { let selected,error = universalDictionary(owner,id,prepared.quantifier,node.a); if error != Error.none { return error; } dictionary = selected; }
        let arguments = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,callee),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,blot_runtime_runtime_layout::Closure_environment),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,argument)]); if arguments != Error.none { return arguments; } let head = providerHead(owner); if head != Error.none { return head; } if qualified { let loaded = emit(owner,blot_backend_runtime_ir::OP_local_get,dictionary); if loaded != Error.none { return loaded; } }
        let selector = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,callee),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,blot_runtime_runtime_layout::Closure_function)]); if selector != Error.none { return selector; } let annotated = generator.module.emit(owner.function_id,blot_backend_runtime_ir::callResult(generator.layoutRole(abstract.b))); if annotated != Error.none { return annotated; } let ordinary,ordinary_error = generator.closureSignature(abstract.a,abstract.b); if ordinary_error != Error.none { return ordinary_error; } var signature = ordinary; if qualified { let selected,error = generator.dictionaryClosureSignature(abstract.a,abstract.b); if error != Error.none { return error; } signature = selected; }
        let called = emit(owner,blot_backend_runtime_ir::OP_call_indirect,signature); if called != Error.none { return called; } let output,output_error = temporary(owner,generator.representations.store.machine(abstract.b)); if output_error != Error.none { return output_error; } let saved = emit(owner,blot_backend_runtime_ir::OP_local_set,output); if saved != Error.none { return saved; } let result,result_error = carrierValue(owner,output,abstract.b,concrete.result,0); if result_error != Error.none { return result_error; } return emit(owner,blot_backend_runtime_ir::OP_local_get,result);
    }
    if prepared.never { let callee = expression(owner,node.a,depth + 1); if callee != Error.none { return callee; } return emit(owner,blot_backend_runtime_ir::OP_unreachable_); }
    if prepared.evaluated.present { let inlined,error = emitEvaluatedNamed(owner,prepared.evaluated.value,depth); if error != Error.none || inlined { return error; } } let static_applied,static_error = staticApply(owner,id,depth); if static_error != Error.none || static_applied { return static_error; }
    if prepared.partial.present { let partial = prepared.partial.value; let inlined,error = inlineStaticCall(owner,partial.key,partial.arguments[..partial.count],depth); if error != Error.none || inlined { return error; } }
    if prepared.known.present { let known = prepared.known.value; let edited,edit_error = inlineCollectionEdit(owner,id,known.key,depth); if edit_error != Error.none || edited { return edit_error; } let simd,simd_error = inlineSimdCall(owner,id,known.key,depth); if simd_error != Error.none || simd { return simd_error; } let inlined,inline_error = inlineNamedCall(owner,known.key,known.arguments[..known.count],depth); if inline_error != Error.none || inlined { return inline_error; } }
    if owner.static_values.table.count == 0 && isCallableTemplate(owner,node.a) { let selected,error = callableTemplate(owner,node.a); if error != Error.none { return error; } assert(selected.present); let template = selected.value; let ty,type_error = codeLayout(owner,source.typeOf(node.a),source.span(id)); if type_error != Error.none { return type_error; } let function,function_error = templateFunction(owner,template,ty,false); if function_error != Error.none { return function_error; } let argument,argument_error = capture(owner,node.b,depth); if argument_error != Error.none { return argument_error; }
        var environment: Error; if template.environment.present { environment = emit(owner,blot_backend_runtime_ir::OP_local_get,template.environment.value); } else { environment = emit(owner,blot_backend_runtime_ir::OP_i32_const,0); } if environment != Error.none { return environment; } let loaded = emit(owner,blot_backend_runtime_ir::OP_local_get,argument); if loaded != Error.none { return loaded; } let head = providerHead(owner); if head != Error.none { return head; } return emit(owner,blot_backend_runtime_ir::OP_call,function);
    }
    if source.node(node.a).tag == blot_check_core::Tag.operation_value {
        var operation_type: u32 = 0; var label: u32 = 0; match resolvedPlan(owner,node.a) { operation selected=>{ operation_type = selected.ty; label = selected.label; },_=>{ abort("expected prepared operation value"); }, } let operation = source.operationValue(node.a); let token,token_error = generator.runtimeOperation(label,owner.unit_id,source.span(node.a)); if token_error != Error.none { return token_error; } let function,function_error = generator.operationFunction(blot_reuse_code_artifacts::OperationKey { operation: token,ty: operation_type,scoped: operation.capability != 0 }); if function_error != Error.none { return function_error; }
        assert(prepared.arrow.present); let arrow = prepared.arrow.value; let expected,expected_error = generator.closureSignature(arrow.parameter,arrow.result); if expected_error != Error.none { return expected_error; } let callee = generator.module.functions[function];
        if callee.signature == expected && callee.result_role == generator.layoutRole(arrow.result) && callee.parameter_roles == generator.closureRoles(arrow.parameter) {
            var environment = blot_support::none<u32>(); if operation.capability != 0 { let captured,error = capture(owner,operation.capability,depth); if error != Error.none { return error; } environment = blot_support::some(captured); } let argument,argument_error = capture(owner,node.b,depth); if argument_error != Error.none { return argument_error; } var loaded: Error; if environment.present { loaded = emit(owner,blot_backend_runtime_ir::OP_local_get,environment.value); } else { loaded = emit(owner,blot_backend_runtime_ir::OP_i32_const,0); } if loaded != Error.none { return loaded; }
            if generator.representations.store.node(arrow.parameter).tag != blot_backend_layout::Tag.erased_proof { let input = emit(owner,blot_backend_runtime_ir::OP_local_get,argument); if input != Error.none { return input; } } let head = providerHead(owner); if head != Error.none { return head; } return emit(owner,blot_backend_runtime_ir::OP_call,function);
        }
    }
    assert(prepared.arrow.present); let arrow = prepared.arrow.value; let numeric,numeric_error = selectedNumericCall(owner,id,arrow,depth); if numeric_error != Error.none || numeric { return numeric_error; } generator.evaluator.counters.prepared_indirect_calls++;
    let callee,callee_error = capture(owner,node.a,depth); if callee_error != Error.none { return callee_error; } let argument,argument_error = capture(owner,node.b,depth); if argument_error != Error.none { return argument_error; } let signature,signature_error = generator.closureSignature(arrow.parameter,arrow.result); if signature_error != Error.none { return signature_error; }
    let environment = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,callee),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,blot_runtime_runtime_layout::Closure_environment)]); if environment != Error.none { return environment; } if generator.representations.store.node(arrow.parameter).tag != blot_backend_layout::Tag.erased_proof { let input = emit(owner,blot_backend_runtime_ir::OP_local_get,argument); if input != Error.none { return input; } } let head = providerHead(owner); if head != Error.none { return head; } let target = emit(owner,blot_backend_runtime_ir::OP_local_get,callee); if target != Error.none { return target; }
    let logical,logical_error = generator.internLayoutWithEffects(blot_backend_layout::Tag.function,arrow.parameter,arrow.result,arrow.row,[]); if logical_error != Error.none { return logical_error; } if logical < 67108864 { let recorded = generator.module.emitReference(owner.function_id,blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_ownership,logical),blot_reuse_artifact_emitter::Role.callable_layout); if recorded != Error.none { return recorded; } }
    let selected = emit(owner,blot_backend_runtime_ir::OP_i32_load,blot_runtime_runtime_layout::Closure_function); if selected != Error.none { return selected; } let annotated = generator.module.emit(owner.function_id,blot_backend_runtime_ir::callResult(generator.layoutRole(arrow.result))); if annotated != Error.none { return annotated; } return emit(owner,blot_backend_runtime_ir::OP_call_indirect,signature);
}
recursive fn numericCallTargets(owner: Owner&,id: u32,targets: u32[4]&,count: i64&,budget: i64&) -> Error {
    if id == 0 || budget == 0 || count == 4 || !owner.body.present { return Error.none; } budget--; let generator .= owner.generator; let source .= generator.unit(owner.unit_id); let node = source.node(id);
    if node.tag == blot_check_core::Tag.if_value { let left = numericCallTargets(owner,node.b,targets,count,budget); if left != Error.none { return left; } return numericCallTargets(owner,node.c,targets,count,budget); } var template = blot_support::none<Template>();
    if node.tag == blot_check_core::Tag.closure {
        if !generator.planning.bodies.contains(owner.body.value,id) { return Error.none; } match generator.planning.bodies.get(owner.body.value,id) { template prepared=>{ if prepared.value.static_key.present { return Error.none; } template = blot_support::some(prepared.value.metadata); },_=>{ return Error.none; }, }
    } else if node.tag == blot_check_core::Tag.reference {
        let reference = source.reference(id); if reference.unit == 0 || reference.unit == owner.unit_id { let binding = source.binding(reference.binding); if binding.kind != blot_check_core::BindingKind.global && binding.kind != blot_check_core::BindingKind.external { return numericCallTargets(owner,binding.initializer,targets,count,budget); } } if !isCallableTemplate(owner,id) { return Error.none; } var unit = reference.unit; if unit == 0 { unit = owner.unit_id; } let body .= generator.unit(unit).body(reference.binding); if body == null || !body.is_function { return Error.none; } let prepared,error = newTemplate(owner,id); if error != Error.none { return error; } template = blot_support::some(prepared);
    } else { return Error.none; }
    let ty,type_error = codeLayout(owner,source.typeOf(id),source.span(id)); if type_error != Error.none { return type_error; } if generator.representations.store.node(ty).tag != blot_backend_layout::Tag.function { return Error.none; } assert(template.present); let target,error = templateFunction(owner,template.value,ty,false); if error != Error.none { return error; } for existing in targets[..count] { if existing == target { return Error.none; } } targets[count] = target; count++; return Error.none;
}
recursive fn selectedNumericCall(owner: Owner&,id: u32,arrow: blot_backend_resolved_call::Arrow,depth: i64) -> bool,Error {
    let generator .= owner.generator; if !generator.inline_named || owner.static_values.table.count != 0 || generator.layoutRole(arrow.result) != blot_backend_runtime_ir::ROLE_scalar { return false,Error.none; } let node = generator.unit(owner.unit_id).node(id); let view = borrowedRowArgument(owner,node.b); if !view.present || view.value.row != arrow.parameter { return false,Error.none; } var targets: u32[4] = [0;4]; var count: i64 = 0; var budget: i64 = 32;
    let collected = numericCallTargets(owner,node.a,targets,count,budget); if collected != Error.none { return false,collected; } if count == 0 { return false,Error.none; } let signature,signature_error = generator.closureSignature(arrow.parameter,arrow.result); if signature_error != Error.none { return false,signature_error; } for target in targets[..count] { if generator.module.functions[target].signature != signature { return false,Error.none; } }
    let callee,callee_error = capture(owner,node.a,depth); if callee_error != Error.none { return false,callee_error; } let selector,selector_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if selector_error != Error.none { return false,selector_error; } let selected = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,callee),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,blot_runtime_runtime_layout::Closure_function),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,selector)]); if selected != Error.none { return false,selected; }
    for target in targets[..count] {
        let loaded = emit(owner,blot_backend_runtime_ir::OP_local_get,selector); if loaded != Error.none { return false,loaded; } let constant = referenceConstant(owner,target,blot_reuse_artifact_emitter::Role.callable_function); if constant != Error.none { return false,constant; } let branch = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_eq),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_if_,generator.representations.store.machine(arrow.result) as u32)]); if branch != Error.none { return false,branch; } owner.labels++;
        let argument,error = capture(owner,node.b,depth); if error != Error.none { return false,error; } let arguments = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,callee),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,blot_runtime_runtime_layout::Closure_environment),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,argument)]); if arguments != Error.none { return false,arguments; } let head = providerHead(owner); if head != Error.none { return false,head; } let called = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_call,target),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_else_)]); if called != Error.none { return false,called; }
    }
    let argument,argument_error = capture(owner,node.b,depth); if argument_error != Error.none { return false,argument_error; } let arguments = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,callee),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,blot_runtime_runtime_layout::Closure_environment),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,argument)]); if arguments != Error.none { return false,arguments; } let head = providerHead(owner); if head != Error.none { return false,head; } let selector_loaded = emit(owner,blot_backend_runtime_ir::OP_local_get,selector); if selector_loaded != Error.none { return false,selector_loaded; } let annotated = generator.module.emit(owner.function_id,blot_backend_runtime_ir::callResult(generator.layoutRole(arrow.result))); if annotated != Error.none { return false,annotated; } let called = emit(owner,blot_backend_runtime_ir::OP_call_indirect,signature); if called != Error.none { return false,called; }
    for index in 0..count { owner.labels--; let ended = emit(owner,blot_backend_runtime_ir::OP_end); if ended != Error.none { return false,ended; } } return true,Error.none;
}
struct ResourceScopePlan { acquire: u32 = 0,release: u32 = 0,callback: u32 = 0 }
fn resourceScopePlan(owner: Owner&,id: u32) -> ResourceScopePlan { match resolvedPlan(owner,id) { resource_scope plan=>{ return ResourceScopePlan { plan.acquire,plan.release,plan.callback }; },_=>{ abort("expected prepared resource scope"); }, } }
recursive fn prepareResourceScope(owner: Owner&,id: u32) -> ResourceScopePlan,Error {
    let generator .= owner.generator; let source .= generator.unit(owner.unit_id); let node = source.node(id); let transferred = node.tag == blot_check_core::Tag.resource_acquire; var count: i64 = 3; if transferred { count = 2; } let callables: u32[3] = [node.a,node.b,node.c]; let kinds: u32[3] = [4,6,4];
    if !source.has_usage_contracts || (transferred && node.c != 0) { return ResourceScopePlan {},generator.fail(owner.unit_id,id,blot_backend_core_backend::Code.unsupported); }
    for callable,index in callables[..count] { let kind = kinds[index]; if source.node(callable).tag != blot_check_core::Tag.closure && !(kind == 6 && blot_check_cleanup_contracts::immutableHost(source,callable)) { return ResourceScopePlan {},generator.fail(owner.unit_id,id,blot_backend_core_backend::Code.unsupported); } let wrapper = source.types.node(source.typeOf(callable)); if wrapper.tag != blot_check_types::Tag.usage || wrapper.b != kind || wrapper.c != 0 { return ResourceScopePlan {},generator.fail(owner.unit_id,id,blot_backend_core_backend::Code.unsupported); } }
    var safe: Error; if transferred { safe = blot_check_cleanup_contracts::immutableTransferred(source,node.b); } else { safe = blot_check_cleanup_contracts::immutable(source,node.b); } if safe != Error.none { return ResourceScopePlan {},generator.fail(owner.unit_id,id,blot_backend_core_backend::Code.unsupported); }
    let acquire,acquire_error = codeLayout(owner,source.typeOf(node.a),source.span(id)); if acquire_error != Error.none { return ResourceScopePlan {},acquire_error; } let release,release_error = codeLayout(owner,source.typeOf(node.b),source.span(id)); if release_error != Error.none { return ResourceScopePlan {},release_error; } let acquired = generator.representations.store.node(acquire); let released = generator.representations.store.node(release);
    if acquired.tag != blot_backend_layout::Tag.function || released.tag != blot_backend_layout::Tag.function { return ResourceScopePlan {},generator.fail(owner.unit_id,id,blot_backend_core_backend::Code.unresolved_type); } let acquire_wrapper = source.types.node(source.typeOf(node.a)); let acquired_owner = source.types.node(source.types.node(acquire_wrapper.a).b);
    if acquired_owner.tag != blot_check_types::Tag.usage || acquired_owner.b != 0 || acquired_owner.c != 0 || !blot_check_cleanup_contracts::payloadNominal(source.types,source.nominals,acquired_owner.a) { return ResourceScopePlan {},generator.fail(owner.unit_id,id,blot_backend_core_backend::Code.unsupported); }
    if generator.representations.store.node(acquired.a).tag != blot_backend_layout::Tag.unit || generator.representations.store.node(released.b).tag != blot_backend_layout::Tag.unit || acquired.b != released.a || generator.representations.store.node(acquired.b).tag != blot_backend_layout::Tag.owning { return ResourceScopePlan {},generator.fail(owner.unit_id,id,blot_backend_core_backend::Code.unresolved_type); }
    var callback: u32 = 0; if transferred { let imports,error = generator.module.resourceTransferImports(); if error != Error.none { return ResourceScopePlan {},error; } let expected,type_error = codeLayout(owner,node.ty,source.span(id)); if type_error != Error.none { return ResourceScopePlan {},type_error; } if acquired.b != expected { return ResourceScopePlan {},generator.fail(owner.unit_id,id,blot_backend_core_backend::Code.unresolved_type); } }
    else { let selected,error = codeLayout(owner,source.typeOf(node.c),source.span(id)); if error != Error.none { return ResourceScopePlan {},error; } callback = selected; let called = generator.representations.store.node(callback); let expected,type_error = codeLayout(owner,node.ty,source.span(id)); if type_error != Error.none { return ResourceScopePlan {},type_error; } if called.tag != blot_backend_layout::Tag.function || generator.representations.store.node(acquired.b).a != called.a || called.b != expected { return ResourceScopePlan {},generator.fail(owner.unit_id,id,blot_backend_core_backend::Code.unresolved_type); } }
    return ResourceScopePlan { acquire,release,callback },Error.none;
}
fn invokeUsageClosure(owner: Owner&,callable: u32,argument: blot_support::Option<u32>,arrow: blot_backend_layout::Node) -> Error {
    let generator .= owner.generator; let environment = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,callable),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,blot_runtime_runtime_layout::Closure_environment)]); if environment != Error.none { return environment; } var input: Error; if argument.present { input = emit(owner,blot_backend_runtime_ir::OP_local_get,argument.value); } else { input = emit(owner,blot_backend_runtime_ir::OP_i32_const,0); } if input != Error.none { return input; } let head = providerHead(owner); if head != Error.none { return head; }
    let selector = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,callable),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,blot_runtime_runtime_layout::Closure_function)]); if selector != Error.none { return selector; } let annotated = generator.module.emit(owner.function_id,blot_backend_runtime_ir::callResult(generator.layoutRole(arrow.b))); if annotated != Error.none { return annotated; } let signature,error = generator.closureSignature(arrow.a,arrow.b); if error != Error.none { return error; } return emit(owner,blot_backend_runtime_ir::OP_call_indirect,signature);
}
fn invokeUsageClosure(owner: Owner&,callable: u32,argument: u32,arrow: blot_backend_layout::Node) -> Error { invokeUsageClosure(owner,callable,blot_support::some(argument),arrow) }
recursive fn resourceAcquire(owner: Owner&,id: u32,depth: i64) -> Error {
    let generator .= owner.generator; let node = generator.unit(owner.unit_id).node(id); let plan = resourceScopePlan(owner,id); let acquire_arrow = generator.representations.store.node(plan.acquire); let payload = generator.representations.store.node(acquire_arrow.b).a; let imports,imports_error = generator.module.resourceTransferImports(); if imports_error != Error.none { return imports_error; } let adapter,adapter_error = generator.resourceAdapter(payload); if adapter_error != Error.none { return adapter_error; }
    let acquire,acquire_error = capture(owner,node.a,depth); if acquire_error != Error.none { return acquire_error; } let cleanup,cleanup_error = capture(owner,node.b,depth); if cleanup_error != Error.none { return cleanup_error; } let token,token_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if token_error != Error.none { return token_error; } let reserved = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_call_import,imports.reserve),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,token)]); if reserved != Error.none { return reserved; }
    var zero = blot_backend_runtime_ir::OP_i32_const; if generator.representations.store.machine(payload) == blot_backend_runtime_ir::VT_f32 { zero = blot_backend_runtime_ir::OP_f32_const; } let initialized = emit(owner,zero); if initialized != Error.none { return initialized; } let boxed = boxOwner(owner,payload); if boxed != Error.none { return boxed; } let allocation,allocation_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if allocation_error != Error.none { return allocation_error; } let saved = emit(owner,blot_backend_runtime_ir::OP_local_set,allocation); if saved != Error.none { return saved; }
    let acquired,acquired_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if acquired_error != Error.none { return acquired_error; } let invoked = invokeUsageClosure(owner,acquire,blot_support::none<u32>(),acquire_arrow); if invoked != Error.none { return invoked; } let checked = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,acquired),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,acquired),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,blot_runtime_runtime_layout::Owning_token),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_if_),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_unreachable_),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_end)]); if checked != Error.none { return checked; }
    let raw,raw_error = temporary(owner,generator.representations.store.machine(payload)); if raw_error != Error.none { return raw_error; } var load = blot_backend_runtime_ir::OP_i32_load; if generator.representations.store.machine(payload) == blot_backend_runtime_ir::VT_f32 { load = blot_backend_runtime_ir::OP_f32_load; } let loaded = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,acquired),blot_backend_runtime_ir::instruction(load,blot_runtime_runtime_layout::Owning_payload),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,raw)]); if loaded != Error.none { return loaded; }
    let selected = generator.representations.store.scalar(payload); var scalar_type = blot_backend_runtime_ir::SC_pointer; if selected.present { scalar_type = selected.value; } let stored = storeTypedWord(owner,allocation,blot_runtime_runtime_layout::Owning_payload,raw,scalar_type,0); if stored != Error.none { return stored; } assert(generator.module.arena.present); let arena = generator.module.arena.value; if generator.layoutRole(payload) == blot_backend_runtime_ir::ROLE_reference { let retained = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,raw),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_call,arena.retain)]); if retained != Error.none { return retained; } }
    let arguments = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,cleanup),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_call,arena.retain),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,token),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,adapter),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,raw)]); if arguments != Error.none { return arguments; } if generator.representations.store.machine(payload) == blot_backend_runtime_ir::VT_f32 { let bits = emit(owner,blot_backend_runtime_ir::OP_i32_reinterpret_f32); if bits != Error.none { return bits; } }
    return emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,cleanup),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,0),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,allocation),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_call_import,imports.register),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,allocation)]);
}
recursive fn resourceRelease(owner: Owner&,id: u32,depth: i64) -> Error {
    let generator .= owner.generator; let source .= generator.unit(owner.unit_id); let node = source.node(id); let wrapper = source.types.node(source.typeOf(node.a)); if node.b != 0 || node.c != 0 || node.ty != blot_check_types::unit || wrapper.tag != blot_check_types::Tag.usage || wrapper.b != 0 || wrapper.c != 0 || !blot_check_cleanup_contracts::payloadNominal(source.types,source.nominals,wrapper.a) { return generator.fail(owner.unit_id,id,blot_backend_core_backend::Code.unsupported); }
    let imports,imports_error = generator.module.resourceTransferImports(); if imports_error != Error.none { return imports_error; } let ty,type_error = codeLayout(owner,source.typeOf(node.a),source.span(id)); if type_error != Error.none { return type_error; } let adapter,adapter_error = generator.resourceAdapter(generator.representations.store.node(ty).a); if adapter_error != Error.none { return adapter_error; } let captured,capture_error = capture(owner,node.a,depth); if capture_error != Error.none { return capture_error; } let allocation,allocation_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if allocation_error != Error.none { return allocation_error; }
    let initialized = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,captured),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,allocation),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_block),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_loop)]); if initialized != Error.none { return initialized; } owner.labels += 2;
    let unwrapped = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,allocation),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,blot_runtime_runtime_layout::ArenaHeader_bytes),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_sub),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,blot_runtime_runtime_layout::ArenaHeader_requested),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,blot_runtime_runtime_layout::OwningView_bytes),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_ne),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_br_if,1),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,allocation),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,blot_runtime_runtime_layout::OwningView_owner),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,allocation),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_br),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_end),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_end)]); if unwrapped != Error.none { return unwrapped; } owner.labels -= 2;
    let token,token_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if token_error != Error.none { return token_error; } return emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,allocation),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,blot_runtime_runtime_layout::Owning_token),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_tee,token),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_if_),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,token),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_call_import,imports.release),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_end),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,0)]);
}
recursive fn taskMove(owner: Owner&,ty: u32,value: u32,depth: i64) -> Error { if depth >= 128 { return Error.declined; } if owner.generator.layoutRole(ty) != blot_backend_runtime_ir::ROLE_reference { return Error.none; } let function,error = owner.generator.taskMover(ty); if error != Error.none { return error; } return emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,value),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_call,function)]); }
recursive fn taskMoveBody(owner: Owner&,ty: u32,value: u32,depth: i64) -> Error {
    let generator .= owner.generator; if depth >= 128 { return Error.declined; } let node = generator.representations.store.node(ty); if generator.layoutRole(ty) != blot_backend_runtime_ir::ROLE_reference { return Error.none; }
    match node.tag {
        owning=>{ if node.b != 0 { return Error.none; } let payload = generator.representations.store.node(node.a); if payload.tag == blot_backend_layout::Tag.nominal && payload.a == 4294967295 && payload.b == blot_backend_layout::capability_layout_decl { return Error.none; } let token,error = temporary(owner,blot_backend_runtime_ir::VT_i32); if error != Error.none { return error; } let transfer,present = generator.module.taskImportNamed("transfer"); assert(present);
            let moved = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,value),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,blot_runtime_runtime_layout::Owning_token),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_tee,token),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_if_),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,token),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_call_import,transfer),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_end)]); if moved != Error.none { return moved; } if generator.layoutRole(node.a) == blot_backend_runtime_ir::ROLE_reference { let child,child_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if child_error != Error.none { return child_error; } let loaded = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,value),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,blot_runtime_runtime_layout::Owning_payload),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,child)]); if loaded != Error.none { return loaded; } return taskMove(owner,node.a,child,depth + 1); }
        },product,record=>{ let children = generator.representations.store.children(ty); var count = children.len; if node.tag == blot_backend_layout::Tag.record { count /= 2; } for index in 0..count { var child_type = children[index]; if node.tag == blot_backend_layout::Tag.record { child_type = children[index * 2 + 1]; } if generator.layoutRole(child_type) != blot_backend_runtime_ir::ROLE_reference { continue; } let child,error = temporary(owner,blot_backend_runtime_ir::VT_i32); if error != Error.none { return error; } let loaded = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,value),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,(index * 4) as u32),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,child)]); if loaded != Error.none { return loaded; } let moved = taskMove(owner,child_type,child,depth + 1); if moved != Error.none { return moved; } } },
        array,list=>{ let words,words_error = generator.rowWords(node.a); if words_error != Error.none { return words_error; } if generator.layoutRole(node.a) != blot_backend_runtime_ir::ROLE_reference || words != 0 { return Error.none; } let index,index_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if index_error != Error.none { return index_error; } let child,child_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if child_error != Error.none { return child_error; }
            let entered = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,0),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,index),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_block),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_loop),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,index),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,value),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_ge_u),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_br_if,1)]); if entered != Error.none { return entered; }
            if node.tag == blot_backend_layout::Tag.list { let lists,error = generator.module.ensureLists(); if error != Error.none { return error; } let loaded = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,value),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,index),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_call,lists.address),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load)]); if loaded != Error.none { return loaded; } } else { let address = arrayAddress(owner,value,index,4); if address != Error.none { return address; } let loaded = emit(owner,blot_backend_runtime_ir::OP_i32_load,4); if loaded != Error.none { return loaded; } }
            let saved = emit(owner,blot_backend_runtime_ir::OP_local_set,child); if saved != Error.none { return saved; } let moved = taskMove(owner,node.a,child,depth + 1); if moved != Error.none { return moved; } return emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,index),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,1),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_add),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,index),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_br),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_end),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_end)]);
        },function=>{ return Error.declined; },nominal=>{
            if node.a == 4294967295 && node.b == blot_backend_layout::capability_layout_decl { return Error.none; } if generator.representations.store.scalar(ty).present { return Error.none; } if node.a == 0 || node.a > generator.units.len { return Error.declined; } let source .= generator.unit(node.a); var found = false;
            for constructor in source.constructors { let nominal = source.nominal(constructor.nominal); if nominal.identity.unit != node.a || nominal.identity.decl != node.b { continue; } found = true; if constructor.payload == 0 { continue; } let payload,error = generator.nominalPayload((node.a as u64 << 32) | node.b as u64,constructor.tag,ty); if error != Error.none { return error; } if generator.layoutRole(payload) != blot_backend_runtime_ir::ROLE_reference { continue; } if nominal.is_opaque { let moved = taskMove(owner,payload,value,depth + 1); if moved != Error.none { return moved; } } else {
                    let entered = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,value),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,constructor.tag),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_eq),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_if_)]); if entered != Error.none { return entered; } let child,child_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if child_error != Error.none { return child_error; } let loaded = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,value),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,4),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,child)]); if loaded != Error.none { return loaded; } let moved = taskMove(owner,payload,child,depth + 1); if moved != Error.none { return moved; } let ended = emit(owner,blot_backend_runtime_ir::OP_end); if ended != Error.none { return ended; }
                } } if !found { return Error.declined; }
        },_=>{},
    } return Error.none;
}
recursive fn taskMoveTemplate<M>(owner: Owner&,metadata: M,environment: u32,depth: i64) -> Error {
    let generator .= owner.generator; if depth >= 128 { return Error.declined; } let source .= generator.unit(metadata.unit); if source.node(metadata.node).tag != blot_check_core::Tag.closure || metadata.scalar_environment { return Error.none; } let captures = source.closureCaptures(metadata.node); let types = generator.representations.store.children(metadata.captures);
    for binding,index in captures { let ty = types[index]; let child,error = temporary(owner,blot_backend_runtime_ir::VT_i32); if error != Error.none { return error; } let nested = generator.capturedTemplate(metadata.templates,binding);
        if nested.present { let loaded = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,environment),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,(index * 4) as u32),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,child)]); if loaded != Error.none { return loaded; } let moved = taskMoveTemplate(owner,nested.value,child,depth + 1); if moved != Error.none { return moved; } }
        else if generator.layoutRole(ty) == blot_backend_runtime_ir::ROLE_reference { let semantic = source.types.node(source.binding(binding).ty); if semantic.tag == blot_check_types::Tag.usage && (semantic.b == 7 || semantic.b == 2) { continue; } let loaded = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,environment),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,(index * 4) as u32),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,child)]); if loaded != Error.none { return loaded; } let moved = taskMove(owner,ty,child,depth + 1); if moved != Error.none { return moved; } }
    } return Error.none;
}
struct TaskExportName { bytes: u8[64] = [0;64],len: i64 = 0 }
fn taskExportName(prefix: const u8[:],id: u32) -> TaskExportName {
    var result = TaskExportName {}; assert(prefix.len <= 54); for byte in prefix { result.bytes[result.len] = byte; result.len++; } var digits: u8[10] = [0;10]; var count: i64 = 0; var value = id; loop { digits[count] = ('0' as u32 + value % 10) as u8; count++; value /= 10; if value == 0 { break; } } while count != 0 { count--; result.bytes[result.len] = digits[count]; result.len++; } return result;
}
recursive fn taskDescriptor(owner: Owner&,thunk: u32) -> u32,Error {
    let generator .= owner.generator; let source .= generator.unit(owner.unit_id); var selected = blot_support::none<Template>(); if source.node(thunk).tag == blot_check_core::Tag.reference { let metadata .= owner.templates.get(source.reference(thunk).binding); if metadata != null { selected = blot_support::some(metadata); } }
    if !selected.present { let actual,error = blot_check_task_core::callable(source,thunk); if error != Error.none { return 0,Error.declined; } match resolvedPlan(owner,actual) { template prepared=>{ var metadata = prepared.value.metadata; if prepared.value.static_key.present { metadata.captures = prepared.value.static_key.value.captures; } selected = blot_support::some(metadata); },_=>{ abort("expected prepared task closure"); }, } }
    let metadata = selected.value; var unit = metadata.unit; if unit == 0 { unit = owner.unit_id; } let producer .= generator.unit(unit); if producer.node(metadata.node).tag != blot_check_core::Tag.closure { return 0,Error.declined; } let ty,type_error = codeLayout(owner,source.typeOf(thunk),source.span(thunk)); if type_error != Error.none { return 0,type_error; } let arrow = generator.representations.store.node(ty); let descriptor = generator.module.taskCount(); let run,run_error = generator.module.addTypedFunction([blot_backend_runtime_ir::VT_i32],blot_backend_runtime_ir::VT_i32,blot_backend_runtime_ir::ROLE_reference); if run_error != Error.none { return 0,run_error; }
    let described = generator.setParameterRoles(run,blot_backend_runtime_ir::packParameterRoles([blot_backend_runtime_ir::ROLE_reference]),blot_support::none<u16>()); if described != Error.none { return 0,described; } let cleanup,cleanup_error = blot_runtime_runtime_cleanup::initPooled(); if cleanup_error != Error.none { return 0,cleanup_error; } var adapter = Owner { generator,unit_id: owner.unit_id,function_id: run,mappings: owner.mappings,row_mappings: owner.row_mappings,cleanups: cleanup };
    recursive fn emitAdapter() -> blot_backend_runtime_ir::Role,Error {
        let callable,callable_error = temporary(adapter,blot_backend_runtime_ir::VT_i32); if callable_error != Error.none { return blot_backend_runtime_ir::ROLE_unknown,callable_error; } let provider,provider_error = temporary(adapter,blot_backend_runtime_ir::VT_i32); if provider_error != Error.none { return blot_backend_runtime_ir::ROLE_unknown,provider_error; }
        let loaded = emitInstructions(adapter,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,0),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,0),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,callable),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,0),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,4),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,provider)]); if loaded != Error.none { return blot_backend_runtime_ir::ROLE_unknown,loaded; } adapter.provider_local = blot_support::some(provider); let invoked = invokeUsageClosure(adapter,callable,blot_support::none<u32>(),arrow); if invoked != Error.none { return blot_backend_runtime_ir::ROLE_unknown,invoked; }
        let role = generator.bodyResultRole(arrow.b,unit,producer.closure(metadata.node).body); let boxed = boxOwnerStorage(adapter,generator.representations.store.machine(arrow.b),role); if boxed != Error.none { return blot_backend_runtime_ir::ROLE_unknown,boxed; } let result,result_error = temporary(adapter,blot_backend_runtime_ir::VT_i32); if result_error != Error.none { return blot_backend_runtime_ir::ROLE_unknown,result_error; } assert(generator.module.arena.present); let retained = emitInstructions(adapter,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_tee,result),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_call,generator.module.arena.value.retain),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,result)]); if retained != Error.none { return blot_backend_runtime_ir::ROLE_unknown,retained; }
        let name = taskExportName("blot:task_start/",descriptor); let exported = generator.module.exportTaskAdapter(run,name.bytes[..name.len],false); return role,exported;
    }
    let result_role,adapter_error = emitAdapter(); adapter.deinit(); if adapter_error != Error.none { return 0,adapter_error; }
    recursive fn emitMover(result_move: bool) -> Error {
        let function,error = generator.module.addTypedFunction([blot_backend_runtime_ir::VT_i32],blot_backend_runtime_ir::VT_none,blot_backend_runtime_ir::ROLE_scalar); if error != Error.none { return error; } let described = generator.setParameterRoles(function,blot_backend_runtime_ir::packParameterRoles([blot_backend_runtime_ir::ROLE_reference]),blot_support::none<u16>()); if described != Error.none { return described; } let cleanup,cleanup_error = blot_runtime_runtime_cleanup::initPooled(); if cleanup_error != Error.none { return cleanup_error; } var mover = Owner { generator,unit_id: owner.unit_id,function_id: function,mappings: owner.mappings,row_mappings: owner.row_mappings,cleanups: cleanup };
        recursive fn lower() -> Error {
            let value,value_error = temporary(mover,blot_backend_runtime_ir::VT_i32); if value_error != Error.none { return value_error; } let loaded = emitInstructions(mover,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,0),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,value)]); if loaded != Error.none { return loaded; }
            if result_move { if result_role == blot_backend_runtime_ir::ROLE_reference { let moved = taskMove(mover,arrow.b,value,0); if moved != Error.none { return moved; } } } else { let environment,environment_error = temporary(mover,blot_backend_runtime_ir::VT_i32); if environment_error != Error.none { return environment_error; } let loaded = emitInstructions(mover,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,value),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,blot_runtime_runtime_layout::Closure_environment),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,environment)]); if loaded != Error.none { return loaded; } let moved = taskMoveTemplate(mover,metadata,environment,0); if moved != Error.none { return moved; } }
            var prefix: const u8[:] = "blot:task_move_captures/"; if result_move { prefix = "blot:task_move_result/"; } let name = taskExportName(prefix,descriptor); return generator.module.exportTaskAdapter(function,name.bytes[..name.len],false);
        }
        let emitted = lower(); mover.deinit(); return emitted;
    }
    let captures_moved = emitMover(false); if captures_moved != Error.none { return 0,captures_moved; } let result_moved = emitMover(true); if result_moved != Error.none { return 0,result_moved; } return descriptor,Error.none;
}
recursive fn taskSplit(owner: Owner&,id: u32,depth: i64) -> Error {
    let generator .= owner.generator; let source .= generator.unit(owner.unit_id); let args = source.children(id); let plan,plan_error = blot_check_task_regions::partition(source,id); if plan_error != Error.none { return generator.fail(owner.unit_id,id,blot_backend_core_backend::Code.unsupported); } let allocation,allocation_error = capture(owner,args[0],depth); if allocation_error != Error.none { return allocation_error; } let partition = expression(owner,args[1],depth + 1); if partition != Error.none { return partition; } let dropped = emit(owner,blot_backend_runtime_ir::OP_drop); if dropped != Error.none { return dropped; } let callback,callback_error = capture(owner,args[2],depth); if callback_error != Error.none { return callback_error; }
    let array,array_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if array_error != Error.none { return array_error; } let checked = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,allocation),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,blot_runtime_runtime_layout::Owning_payload),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,array),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,array),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,plan.limit),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_lt_u),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_if_),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_unreachable_),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_end)]); if checked != Error.none { return checked; } let checkpoint = owner.cleanups.mark();
    recursive fn lower() -> Error {
        var views: u32[16] = [0;16]; for range,index in plan.ranges[..plan.len] {
            let view,error = allocate(owner,16,AllocationRoles { words: [blot_backend_runtime_ir::ROLE_scalar,blot_backend_runtime_ir::ROLE_reference,blot_backend_runtime_ir::ROLE_scalar,blot_backend_runtime_ir::ROLE_scalar] }); if error != Error.none { return error; } let offsets: u32[3] = [0,8,12]; let literals: u32[3] = [1,range.first,range.end]; for offset,field in offsets { let stored = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,view),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,literals[field]),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_store,offset)]); if stored != Error.none { return stored; } }
            let stored = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,view),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,allocation),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_store,4)]); if stored != Error.none { return stored; } let appended = owner.cleanups.append(blot_runtime_runtime_cleanup::Action.revoke_effect { local: view }); if appended != Error.none { return appended; } assert(generator.module.arena.present); let rooted = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,view),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_call,generator.module.arena.value.root_authority),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,view)]); if rooted != Error.none { return rooted; } let boxed = boxOwnerStorage(owner,blot_backend_runtime_ir::VT_i32,blot_backend_runtime_ir::ROLE_reference); if boxed != Error.none { return boxed; } let local,local_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if local_error != Error.none { return local_error; } views[index] = local; let saved = emit(owner,blot_backend_runtime_ir::OP_local_set,local); if saved != Error.none { return saved; }
        }
        let roles: blot_backend_runtime_ir::Role[16] = [blot_backend_runtime_ir::ROLE_reference;16]; let product,error = allocate(owner,(plan.len * 4) as u32,AllocationRoles { words: roles[..plan.len] }); if error != Error.none { return error; } for view,index in views[..plan.len] { let stored = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,product),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,view),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_store,(index * 4) as u32)]); if stored != Error.none { return stored; } }
        let callback_type,type_error = codeLayout(owner,source.typeOf(args[2]),source.span(id)); if type_error != Error.none { return type_error; } let arrow = generator.representations.store.node(callback_type); let invoked = invokeUsageClosure(owner,callback,product,arrow); if invoked != Error.none { return invoked; } let result,result_error = temporary(owner,generator.representations.store.machine(arrow.b)); if result_error != Error.none { return result_error; } let drain,present = generator.module.taskImportNamed("drain"); assert(present); let drained = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,result),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_call_import,drain)]); if drained != Error.none { return drained; } let cleaned = cleanupTo(owner,checkpoint); if cleaned != Error.none { return cleaned; }
        let pair,pair_error = allocate(owner,8,AllocationRoles { words: [blot_backend_runtime_ir::ROLE_reference,generator.layoutRole(arrow.b)] }); if pair_error != Error.none { return pair_error; } let first = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,pair),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,allocation),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_store),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,pair),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,result)]); if first != Error.none { return first; } var store = blot_backend_runtime_ir::OP_i32_store; if generator.representations.store.machine(arrow.b) == blot_backend_runtime_ir::VT_f32 { store = blot_backend_runtime_ir::OP_f32_store; } return emitInstructions(owner,[blot_backend_runtime_ir::instruction(store,4),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,pair)]);
    }
    let error = lower(); owner.cleanups.restore(checkpoint); return error;
}
recursive fn taskView(owner: Owner&,id: u32,depth: i64,write: bool) -> Error {
    let generator .= owner.generator; let source .= generator.unit(owner.unit_id); let args = source.children(id); let boxed,boxed_error = capture(owner,args[0],depth); if boxed_error != Error.none { return boxed_error; } let index,index_error = capture(owner,args[1],depth); if index_error != Error.none { return index_error; } var value: u32 = 0; if write { let captured,error = capture(owner,args[2],depth); if error != Error.none { return error; } value = captured; }
    let view,view_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if view_error != Error.none { return view_error; } let array,array_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if array_error != Error.none { return array_error; } let absolute,absolute_error = temporary(owner,blot_backend_runtime_ir::VT_i32); if absolute_error != Error.none { return absolute_error; }
    let checked = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,boxed),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,view),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,view),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_eqz),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_if_),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_unreachable_),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_end),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,index),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,view),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,12),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,view),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,8),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_sub),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_ge_u),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_if_),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_unreachable_),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_end),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,index),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,view),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,8),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_add),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,absolute),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,view),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load,4),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_load),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_set,array)]); if checked != Error.none { return checked; }
    let info = blot_check_task_types::viewInfo(source.types,source.typeOf(args[0])); assert(info.present); let element,element_error = codeLayout(owner,source.types.node(info.value.payload).a,source.span(id)); if element_error != Error.none { return element_error; } let machine = generator.representations.store.machine(element); let row_words,words_error = generator.rowWords(element); if words_error != Error.none { return words_error; } let stride = blot_backend_packed_layout::stride(row_words);
    if row_words != 0 { let address = arrayAddress(owner,array,absolute,stride); if address != Error.none { return address; } if write { let loaded = emit(owner,blot_backend_runtime_ir::OP_local_get,value); if loaded != Error.none { return loaded; } let stored = storeElement(owner,machine,4,row_words,true,element); if stored != Error.none { return stored; } return emit(owner,blot_backend_runtime_ir::OP_i32_const,0); } return readElement(owner,machine,4,row_words,element); }
    if write && generator.layoutRole(element) == blot_backend_runtime_ir::ROLE_reference { let allocation = emit(owner,blot_backend_runtime_ir::OP_local_get,array); if allocation != Error.none { return allocation; } let address = arrayAddress(owner,array,absolute,stride); if address != Error.none { return address; } assert(generator.module.arena.present); let stored = emitInstructions(owner,[blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const,4),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_add),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_local_get,value),blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_call,generator.module.arena.value.store_word)]); if stored != Error.none { return stored; } }
    else { let address = arrayAddress(owner,array,absolute,stride); if address != Error.none { return address; } if write { let loaded = emit(owner,blot_backend_runtime_ir::OP_local_get,value); if loaded != Error.none { return loaded; } var store = blot_backend_runtime_ir::OP_i32_store; if machine == blot_backend_runtime_ir::VT_f32 { store = blot_backend_runtime_ir::OP_f32_store; } let stored = storeScalar(owner,store,4); if stored != Error.none { return stored; } } else { var load = blot_backend_runtime_ir::OP_i32_load; if machine == blot_backend_runtime_ir::VT_f32 { load = blot_backend_runtime_ir::OP_f32_load; } let loaded = emit(owner,load,4); if loaded != Error.none { return loaded; } } }
    if write { return emit(owner,blot_backend_runtime_ir::OP_i32_const,0); } return Error.none;
}
