// Immutable values and parallel metadata. This owner publishes no judgments.
namespace blot_eval_eval_values;
import backend.runtime_ir;
import backend.scalar_ops;
import check.core;
import check.staging_origins;
import eval.eval_collection_growth;
import eval.implementation_evidence;
import eval.type_evidence;
import support.error;
import support.native;
import support.pooled_buffer;
import support.pooled_map;

import std;
import dictionary;
import check.types;
type Value=blot_backend_scalar_ops::Value;
type ValueId=u32;
type Error=blot_error::Error;
enum ValueKind { scalar,product,record,nominal,array,list,closure,type_constructor,resolver,provider,state_provider,effect_set,effect_descriptor,computation,request_decision,cursor,proof,package,code,descriptor,staged_value,capability }
enum ClosureOrigin { named,anonymous,constructor,primitive,operation }
struct ClosureValue { staged: ValueId=0,unit: u32,identity: u32,applied: u32=0,origin: ClosureOrigin,mappings: blot_check_core::List=blot_check_core::List {},row_mappings: blot_check_core::List=blot_check_core::List {},ty: u32=0 }
struct ValueInfo { nominal: u64=0,start: u32=0,len: u32=0,bits: u32=0,kind: ValueKind=ValueKind.scalar,scalar: blot_backend_runtime_ir::Scalar=blot_backend_runtime_ir::SC_unit }
struct View {
 owner_id: u64=0,code_origins: const blot_check_staging_origins::Record[:],values: const ValueInfo[:],children: const ValueId[:],closures: const ClosureValue[:],value_evidence: const u32[:],type_mappings: const blot_eval_type_evidence::Mapping[:],row_mappings: const blot_eval_type_evidence::RowMapping[:],evidence: blot_eval_type_evidence::View,value_records: const u32[:],record_layouts: const blot_check_core::List[:],field_names: const u32[:],implementation_proofs: blot_eval_implementation_evidence::View
}
struct Snapshot {
 owner_id: u64=blot_native::fresh_owner_id(),code_origins: const blot_check_staging_origins::Record[:],values: const ValueInfo[:],children: const ValueId[:],closures: const ClosureValue[:],value_evidence: const u32[:],type_mappings: const blot_eval_type_evidence::Mapping[:],row_mappings: const blot_eval_type_evidence::RowMapping[:],evidence: blot_eval_type_evidence::Snapshot,value_records: const u32[:],record_layouts: const blot_check_core::List[:],field_names: const u32[:],implementation_proofs: blot_eval_implementation_evidence::Snapshot
}
struct ViewKey { value: ValueId,evidence: u32,entry_interface: bool=false }
fn hash(key: ViewKey) -> u64 { var h=::hash_combine(::hash(key.value),::hash(key.evidence)); if key.entry_interface { h=::hash_combine(h,1); } return h; }
struct RecordKey { unit: i64,ty: u32 }
fn hash(key: RecordKey) -> u64 { return ::hash_combine(::hash(key.unit),::hash(key.ty)); }
struct RecordNames { words: const u32[:] }
fn hash(self_: RecordNames,key: blot_check_core::List) -> u64 { return namesHash(self_.words[key.start..key.start+key.len]); }
fn eql(self_: RecordNames,a: blot_check_core::List,b: blot_check_core::List) -> bool { return self_.words[a.start..a.start+a.len]==self_.words[b.start..b.start+b.len]; }
fn namesHash(names: const u32[:]) -> u64 { var hash: u64=0; for name in names { hash=::hash_combine(hash,::hash(name)); } return hash; }
struct ValuesBuffer { storage: ValueInfo[:]=default<ValueInfo[:]>(),items: ValueInfo[:]=default<ValueInfo[:]>(),len: i64=0,failure: Error=blot_error::Error.none }
reusable[] var pool_ValuesBuffer: ValueInfo[>..]=[];
fn ensure(self_: ValuesBuffer&,minimum: i64) -> Error { if self_.failure!=blot_error::Error.none { return self_.failure; } let error=blot_support_pooled_buffer::ensure(self_,minimum,pool_ValuesBuffer); if error!=blot_error::Error.none { self_.failure=error; } return error; }
fn push(self_: ValuesBuffer&,value: ValueInfo) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::push(self_,value,pool_ValuesBuffer); self_.len=self_.items.len; }
fn append(self_: ValuesBuffer&,values: const ValueInfo[:]) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::append(self_,values,pool_ValuesBuffer); self_.len=self_.items.len; }
fn resize(self_: ValuesBuffer&,length: i64) { blot_support_pooled_buffer::resize(self_,length); self_.len=length; }
fn resize(self_: ValuesBuffer&,length: i64,value: ValueInfo) { if length<=self_.len { resize(self_,length); return; } let error=ensure(self_,length); if error!=blot_error::Error.none { return; } for index in self_.len..length { self_.storage[index]=value; } self_.items=self_.storage[..length]; self_.len=length; }
fn clear(self_: ValuesBuffer&) { blot_support_pooled_buffer::clear(self_); self_.len=0; self_.failure=blot_error::Error.none; }
fn deinit(self_: ValuesBuffer&) { blot_support_pooled_buffer::deinit(self_,pool_ValuesBuffer); self_.len=0; self_.failure=blot_error::Error.none; }
struct ClosuresBuffer { storage: ClosureValue[:]=default<ClosureValue[:]>(),items: ClosureValue[:]=default<ClosureValue[:]>(),len: i64=0,failure: Error=blot_error::Error.none }
reusable[] var pool_ClosuresBuffer: ClosureValue[>..]=[];
fn ensure(self_: ClosuresBuffer&,minimum: i64) -> Error { if self_.failure!=blot_error::Error.none { return self_.failure; } let error=blot_support_pooled_buffer::ensure(self_,minimum,pool_ClosuresBuffer); if error!=blot_error::Error.none { self_.failure=error; } return error; }
fn push(self_: ClosuresBuffer&,value: ClosureValue) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::push(self_,value,pool_ClosuresBuffer); self_.len=self_.items.len; }
fn append(self_: ClosuresBuffer&,values: const ClosureValue[:]) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::append(self_,values,pool_ClosuresBuffer); self_.len=self_.items.len; }
fn resize(self_: ClosuresBuffer&,length: i64) { blot_support_pooled_buffer::resize(self_,length); self_.len=length; }
fn resize(self_: ClosuresBuffer&,length: i64,value: ClosureValue) { if length<=self_.len { resize(self_,length); return; } let error=ensure(self_,length); if error!=blot_error::Error.none { return; } for index in self_.len..length { self_.storage[index]=value; } self_.items=self_.storage[..length]; self_.len=length; }
fn clear(self_: ClosuresBuffer&) { blot_support_pooled_buffer::clear(self_); self_.len=0; self_.failure=blot_error::Error.none; }
fn deinit(self_: ClosuresBuffer&) { blot_support_pooled_buffer::deinit(self_,pool_ClosuresBuffer); self_.len=0; self_.failure=blot_error::Error.none; }
struct CodeOriginsBuffer { storage: blot_check_staging_origins::Record[:]=default<blot_check_staging_origins::Record[:]>(),items: blot_check_staging_origins::Record[:]=default<blot_check_staging_origins::Record[:]>(),len: i64=0,failure: Error=blot_error::Error.none }
reusable[] var pool_CodeOriginsBuffer: blot_check_staging_origins::Record[>..]=[];
fn ensure(self_: CodeOriginsBuffer&,minimum: i64) -> Error { if self_.failure!=blot_error::Error.none { return self_.failure; } let error=blot_support_pooled_buffer::ensure(self_,minimum,pool_CodeOriginsBuffer); if error!=blot_error::Error.none { self_.failure=error; } return error; }
fn push(self_: CodeOriginsBuffer&,value: blot_check_staging_origins::Record) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::push(self_,value,pool_CodeOriginsBuffer); self_.len=self_.items.len; }
fn append(self_: CodeOriginsBuffer&,values: const blot_check_staging_origins::Record[:]) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::append(self_,values,pool_CodeOriginsBuffer); self_.len=self_.items.len; }
fn resize(self_: CodeOriginsBuffer&,length: i64) { blot_support_pooled_buffer::resize(self_,length); self_.len=length; }
fn resize(self_: CodeOriginsBuffer&,length: i64,value: blot_check_staging_origins::Record) { if length<=self_.len { resize(self_,length); return; } let error=ensure(self_,length); if error!=blot_error::Error.none { return; } for index in self_.len..length { self_.storage[index]=value; } self_.items=self_.storage[..length]; self_.len=length; }
fn clear(self_: CodeOriginsBuffer&) { blot_support_pooled_buffer::clear(self_); self_.len=0; self_.failure=blot_error::Error.none; }
fn deinit(self_: CodeOriginsBuffer&) { blot_support_pooled_buffer::deinit(self_,pool_CodeOriginsBuffer); self_.len=0; self_.failure=blot_error::Error.none; }
struct Words { storage: u32[:]=default<u32[:]>(),items: u32[:]=default<u32[:]>(),len: i64=0,failure: Error=blot_error::Error.none }
reusable[] var pool_Words: u32[>..]=[];
fn ensure(self_: Words&,minimum: i64) -> Error { if self_.failure!=blot_error::Error.none { return self_.failure; } let error=blot_support_pooled_buffer::ensure(self_,minimum,pool_Words); if error!=blot_error::Error.none { self_.failure=error; } return error; }
fn push(self_: Words&,value: u32) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::push(self_,value,pool_Words); self_.len=self_.items.len; }
fn append(self_: Words&,values: const u32[:]) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::append(self_,values,pool_Words); self_.len=self_.items.len; }
fn resize(self_: Words&,length: i64) { blot_support_pooled_buffer::resize(self_,length); self_.len=length; }
fn resize(self_: Words&,length: i64,value: u32) { if length<=self_.len { resize(self_,length); return; } let error=ensure(self_,length); if error!=blot_error::Error.none { return; } for index in self_.len..length { self_.storage[index]=value; } self_.items=self_.storage[..length]; self_.len=length; }
fn clear(self_: Words&) { blot_support_pooled_buffer::clear(self_); self_.len=0; self_.failure=blot_error::Error.none; }
fn deinit(self_: Words&) { blot_support_pooled_buffer::deinit(self_,pool_Words); self_.len=0; self_.failure=blot_error::Error.none; }
struct TypeMappingsBuffer { storage: blot_eval_type_evidence::Mapping[:]=default<blot_eval_type_evidence::Mapping[:]>(),items: blot_eval_type_evidence::Mapping[:]=default<blot_eval_type_evidence::Mapping[:]>(),len: i64=0,failure: Error=blot_error::Error.none }
reusable[] var pool_TypeMappingsBuffer: blot_eval_type_evidence::Mapping[>..]=[];
fn ensure(self_: TypeMappingsBuffer&,minimum: i64) -> Error { if self_.failure!=blot_error::Error.none { return self_.failure; } let error=blot_support_pooled_buffer::ensure(self_,minimum,pool_TypeMappingsBuffer); if error!=blot_error::Error.none { self_.failure=error; } return error; }
fn push(self_: TypeMappingsBuffer&,value: blot_eval_type_evidence::Mapping) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::push(self_,value,pool_TypeMappingsBuffer); self_.len=self_.items.len; }
fn append(self_: TypeMappingsBuffer&,values: const blot_eval_type_evidence::Mapping[:]) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::append(self_,values,pool_TypeMappingsBuffer); self_.len=self_.items.len; }
fn resize(self_: TypeMappingsBuffer&,length: i64) { blot_support_pooled_buffer::resize(self_,length); self_.len=length; }
fn resize(self_: TypeMappingsBuffer&,length: i64,value: blot_eval_type_evidence::Mapping) { if length<=self_.len { resize(self_,length); return; } let error=ensure(self_,length); if error!=blot_error::Error.none { return; } for index in self_.len..length { self_.storage[index]=value; } self_.items=self_.storage[..length]; self_.len=length; }
fn clear(self_: TypeMappingsBuffer&) { blot_support_pooled_buffer::clear(self_); self_.len=0; self_.failure=blot_error::Error.none; }
fn deinit(self_: TypeMappingsBuffer&) { blot_support_pooled_buffer::deinit(self_,pool_TypeMappingsBuffer); self_.len=0; self_.failure=blot_error::Error.none; }
struct RowMappingsBuffer { storage: blot_eval_type_evidence::RowMapping[:]=default<blot_eval_type_evidence::RowMapping[:]>(),items: blot_eval_type_evidence::RowMapping[:]=default<blot_eval_type_evidence::RowMapping[:]>(),len: i64=0,failure: Error=blot_error::Error.none }
reusable[] var pool_RowMappingsBuffer: blot_eval_type_evidence::RowMapping[>..]=[];
fn ensure(self_: RowMappingsBuffer&,minimum: i64) -> Error { if self_.failure!=blot_error::Error.none { return self_.failure; } let error=blot_support_pooled_buffer::ensure(self_,minimum,pool_RowMappingsBuffer); if error!=blot_error::Error.none { self_.failure=error; } return error; }
fn push(self_: RowMappingsBuffer&,value: blot_eval_type_evidence::RowMapping) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::push(self_,value,pool_RowMappingsBuffer); self_.len=self_.items.len; }
fn append(self_: RowMappingsBuffer&,values: const blot_eval_type_evidence::RowMapping[:]) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::append(self_,values,pool_RowMappingsBuffer); self_.len=self_.items.len; }
fn resize(self_: RowMappingsBuffer&,length: i64) { blot_support_pooled_buffer::resize(self_,length); self_.len=length; }
fn resize(self_: RowMappingsBuffer&,length: i64,value: blot_eval_type_evidence::RowMapping) { if length<=self_.len { resize(self_,length); return; } let error=ensure(self_,length); if error!=blot_error::Error.none { return; } for index in self_.len..length { self_.storage[index]=value; } self_.items=self_.storage[..length]; self_.len=length; }
fn clear(self_: RowMappingsBuffer&) { blot_support_pooled_buffer::clear(self_); self_.len=0; self_.failure=blot_error::Error.none; }
fn deinit(self_: RowMappingsBuffer&) { blot_support_pooled_buffer::deinit(self_,pool_RowMappingsBuffer); self_.len=0; self_.failure=blot_error::Error.none; }
struct RecordLayoutsBuffer { storage: blot_check_core::List[:]=default<blot_check_core::List[:]>(),items: blot_check_core::List[:]=default<blot_check_core::List[:]>(),len: i64=0,failure: Error=blot_error::Error.none }
reusable[] var pool_RecordLayoutsBuffer: blot_check_core::List[>..]=[];
fn ensure(self_: RecordLayoutsBuffer&,minimum: i64) -> Error { if self_.failure!=blot_error::Error.none { return self_.failure; } let error=blot_support_pooled_buffer::ensure(self_,minimum,pool_RecordLayoutsBuffer); if error!=blot_error::Error.none { self_.failure=error; } return error; }
fn push(self_: RecordLayoutsBuffer&,value: blot_check_core::List) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::push(self_,value,pool_RecordLayoutsBuffer); self_.len=self_.items.len; }
fn append(self_: RecordLayoutsBuffer&,values: const blot_check_core::List[:]) { if self_.failure!=blot_error::Error.none { return; } self_.failure=blot_support_pooled_buffer::append(self_,values,pool_RecordLayoutsBuffer); self_.len=self_.items.len; }
fn resize(self_: RecordLayoutsBuffer&,length: i64) { blot_support_pooled_buffer::resize(self_,length); self_.len=length; }
fn resize(self_: RecordLayoutsBuffer&,length: i64,value: blot_check_core::List) { if length<=self_.len { resize(self_,length); return; } let error=ensure(self_,length); if error!=blot_error::Error.none { return; } for index in self_.len..length { self_.storage[index]=value; } self_.items=self_.storage[..length]; self_.len=length; }
fn clear(self_: RecordLayoutsBuffer&) { blot_support_pooled_buffer::clear(self_); self_.len=0; self_.failure=blot_error::Error.none; }
fn deinit(self_: RecordLayoutsBuffer&) { blot_support_pooled_buffer::deinit(self_,pool_RecordLayoutsBuffer); self_.len=0; self_.failure=blot_error::Error.none; }
struct TypedViewsMap { count: i64=0,slots: dictionary_slot<ViewKey,ValueId>[:]=default<dictionary_slot<ViewKey,ValueId>[:]>() }
reusable[] var pool_TypedViewsMap: dictionary_slot<ViewKey,ValueId>[>..]=[];
fn get(self_: const TypedViewsMap&,key: ViewKey) -> ValueId? { let view=blot_support_pooled_map::Map<ViewKey,ValueId> {count:self_.count,slots:self_.slots}; return blot_support_pooled_map::get(view,key); }
fn contains(self_: const TypedViewsMap&,key: ViewKey) -> bool { return self_.get(key)!=null; }
fn insert(self_: TypedViewsMap&,key: ViewKey,value: ValueId) { var view=blot_support_pooled_map::Map<ViewKey,ValueId> {count:self_.count,slots:self_.slots}; blot_support_pooled_map::insert(view,key,value,pool_TypedViewsMap); self_.count=view.count; self_.slots=view.slots; }
fn clear(self_: TypedViewsMap&) { for &slot in self_.slots { slot.tag=0; } self_.count=0; }
fn release(self_: TypedViewsMap&) { if self_.slots.len!=0 { pool_TypedViewsMap.free_slice(self_.slots); } self_.slots=default<dictionary_slot<ViewKey,ValueId>[:]>(); self_.count=0; }
fn restore(self_: TypedViewsMap&,slots: const dictionary_slot<ViewKey,ValueId>[:],count: i64) { release(self_); self_.count=count; if slots.len!=0 { self_.slots=pool_TypedViewsMap.alloc_slice(slots.len); for slot,index in slots { self_.slots[index]=slot; } } }
struct RecordTypesMap { count: i64=0,slots: dictionary_slot<RecordKey,u32>[:]=default<dictionary_slot<RecordKey,u32>[:]>() }
reusable[] var pool_RecordTypesMap: dictionary_slot<RecordKey,u32>[>..]=[];
fn get(self_: const RecordTypesMap&,key: RecordKey) -> u32? { let view=blot_support_pooled_map::Map<RecordKey,u32> {count:self_.count,slots:self_.slots}; return blot_support_pooled_map::get(view,key); }
fn contains(self_: const RecordTypesMap&,key: RecordKey) -> bool { return self_.get(key)!=null; }
fn insert(self_: RecordTypesMap&,key: RecordKey,value: u32) { var view=blot_support_pooled_map::Map<RecordKey,u32> {count:self_.count,slots:self_.slots}; blot_support_pooled_map::insert(view,key,value,pool_RecordTypesMap); self_.count=view.count; self_.slots=view.slots; }
fn clear(self_: RecordTypesMap&) { for &slot in self_.slots { slot.tag=0; } self_.count=0; }
fn release(self_: RecordTypesMap&) { if self_.slots.len!=0 { pool_RecordTypesMap.free_slice(self_.slots); } self_.slots=default<dictionary_slot<RecordKey,u32>[:]>(); self_.count=0; }
fn restore(self_: RecordTypesMap&,slots: const dictionary_slot<RecordKey,u32>[:],count: i64) { release(self_); self_.count=count; if slots.len!=0 { self_.slots=pool_RecordTypesMap.alloc_slice(slots.len); for slot,index in slots { self_.slots[index]=slot; } } }
struct RecordShapesMap { count: i64=0,slots: dictionary_slot<u64,u32>[:]=default<dictionary_slot<u64,u32>[:]>() }
reusable[] var pool_RecordShapesMap: dictionary_slot<u64,u32>[>..]=[];
fn get(self_: const RecordShapesMap&,key: u64) -> u32? { let view=blot_support_pooled_map::Map<u64,u32> {count:self_.count,slots:self_.slots}; return blot_support_pooled_map::get(view,key); }
fn contains(self_: const RecordShapesMap&,key: u64) -> bool { return self_.get(key)!=null; }
fn insert(self_: RecordShapesMap&,key: u64,value: u32) { var view=blot_support_pooled_map::Map<u64,u32> {count:self_.count,slots:self_.slots}; blot_support_pooled_map::insert(view,key,value,pool_RecordShapesMap); self_.count=view.count; self_.slots=view.slots; }
fn clear(self_: RecordShapesMap&) { for &slot in self_.slots { slot.tag=0; } self_.count=0; }
fn release(self_: RecordShapesMap&) { if self_.slots.len!=0 { pool_RecordShapesMap.free_slice(self_.slots); } self_.slots=default<dictionary_slot<u64,u32>[:]>(); self_.count=0; }
fn restore(self_: RecordShapesMap&,slots: const dictionary_slot<u64,u32>[:],count: i64) { release(self_); self_.count=count; if slots.len!=0 { self_.slots=pool_RecordShapesMap.alloc_slice(slots.len); for slot,index in slots { self_.slots[index]=slot; } } }
struct State { owner_id: u64=0,generation: u64=0,live: bool=false,evidence: blot_eval_type_evidence::Store=blot_eval_type_evidence::Store {},collection_buffers: blot_eval_eval_collection_growth::Store=blot_eval_eval_collection_growth::Store {},values: ValuesBuffer=ValuesBuffer {},children: Words=Words {},closures: ClosuresBuffer=ClosuresBuffer {},code_origins: CodeOriginsBuffer=CodeOriginsBuffer {},value_evidence: Words=Words {},type_mappings: TypeMappingsBuffer=TypeMappingsBuffer {},row_mappings: RowMappingsBuffer=RowMappingsBuffer {},value_records: Words=Words {},record_layouts: RecordLayoutsBuffer=RecordLayoutsBuffer {},field_names: Words=Words {},record_shape_next: Words=Words {},typed_views: TypedViewsMap=TypedViewsMap {},specialized_closures: TypedViewsMap=TypedViewsMap {},record_types: RecordTypesMap=RecordTypesMap {},record_shapes: RecordShapesMap=RecordShapesMap {} }
reusable var states: State[>..]=[];
var inactive: State=State {};
var next_generation: u64=1;
struct Store { owner_id: u64& =inactive.owner_id,evidence: blot_eval_type_evidence::Store& =inactive.evidence,collection_buffers: blot_eval_eval_collection_growth::Store& =inactive.collection_buffers,values: ValuesBuffer& =inactive.values,children: Words& =inactive.children,closures: ClosuresBuffer& =inactive.closures,code_origins: CodeOriginsBuffer& =inactive.code_origins,value_evidence: Words& =inactive.value_evidence,type_mappings: TypeMappingsBuffer& =inactive.type_mappings,row_mappings: RowMappingsBuffer& =inactive.row_mappings,value_records: Words& =inactive.value_records,record_layouts: RecordLayoutsBuffer& =inactive.record_layouts,field_names: Words& =inactive.field_names,record_shape_next: Words& =inactive.record_shape_next,typed_views: TypedViewsMap& =inactive.typed_views,specialized_closures: TypedViewsMap& =inactive.specialized_closures,record_types: RecordTypesMap& =inactive.record_types,record_shapes: RecordShapesMap& =inactive.record_shapes,lease: u32=0,generation: u64=0,handle_index: i64=-1 }
reusable var handles: Store[>..]=[];
fn initPooled() -> Store,Error { if next_generation==0xffffffffffffffff||states.len>=0xffffffff { return Store {},blot_error::Error.out_of_memory; } let semantic,semantic_error=blot_eval_type_evidence::init(); if semantic_error!=blot_error::Error.none { return Store {},semantic_error; } var evidence=semantic; let growth,growth_error=blot_eval_eval_collection_growth::initPooled(); if growth_error!=blot_error::Error.none { evidence.deinit(); return Store {},growth_error; } let generation=next_generation; next_generation++; let index=states.alloc_index(State {owner_id:blot_native::fresh_owner_id(),generation:generation,live:true,evidence:evidence,collection_buffers:growth}); let state: State& =states[index]; var self_=Store {owner_id:state.owner_id,evidence:state.evidence,collection_buffers:state.collection_buffers,values:state.values,children:state.children,closures:state.closures,code_origins:state.code_origins,value_evidence:state.value_evidence,type_mappings:state.type_mappings,row_mappings:state.row_mappings,value_records:state.value_records,record_layouts:state.record_layouts,field_names:state.field_names,record_shape_next:state.record_shape_next,typed_views:state.typed_views,specialized_closures:state.specialized_closures,record_types:state.record_types,record_shapes:state.record_shapes,lease:(index+1) as u32,generation:generation}; seedEmpty(self_); return self_,blot_error::Error.none; }
fn initPooledRef() -> Store?,Error { let value,error=initPooled(); if error!=blot_error::Error.none { return null,error; } let index=handles.alloc_index(value); handles[index].handle_index=index; return handles[index],blot_error::Error.none; }
fn seedEmpty(self_: Store) { self_.values.push(ValueInfo {}); self_.value_evidence.push(1); self_.value_records.push(0); self_.record_layouts.push(blot_check_core::List {}); self_.record_shape_next.push(0); }
fn valid(self_: Store) -> bool { return self_.lease!=0&&self_.lease-1<states.len&&states[self_.lease-1].live&&states[self_.lease-1].generation==self_.generation; }
fn scalar(self_: Store,value: Value) -> ValueId,Error {
 let id=self_.values.len as ValueId; self_.values.push(ValueInfo { bits:value.bits, scalar:value.scalar }); var evidence: u32=0;
 if value.scalar==blot_backend_runtime_ir::SC_unit { evidence=1; } else if value.scalar==blot_backend_runtime_ir::SC_bool { evidence=2; } else if value.scalar==blot_backend_runtime_ir::SC_u32 { evidence=3; } else if value.scalar==blot_backend_runtime_ir::SC_f32 { evidence=4; }
 self_.value_evidence.push(evidence); self_.value_records.push(0); return id,blot_error::Error.none;
}
fn aggregate(self_: Store,kind: ValueKind,nominal: u64,tag: u32,children: const ValueId[:]) -> ValueId,Error {
 var stable: ValueId[>..]=[]; stable.append(children); let id=self_.values.len as ValueId; let start=self_.children.len as u32; self_.children.append(stable); self_.values.push(ValueInfo {nominal:nominal,start:start,len:stable.len as u32,bits:tag,kind:kind}); self_.value_evidence.push(0); self_.value_records.push(0); return id,blot_error::Error.none;
}
fn view(self_: const Store&,proofs: blot_eval_implementation_evidence::View) -> View { return View {self_.owner_id,self_.code_origins.items,self_.values.items,self_.children.items,self_.closures.items,self_.value_evidence.items,self_.type_mappings.items,self_.row_mappings.items,self_.evidence.view(),self_.value_records.items,self_.record_layouts.items,self_.field_names.items,proofs}; }
fn view(self_: const Snapshot&) -> View { return View {self_.owner_id,self_.code_origins,self_.values,self_.children,self_.closures,self_.value_evidence,self_.type_mappings,self_.row_mappings,self_.evidence.view(),self_.value_records,self_.record_layouts,self_.field_names,self_.implementation_proofs.view()}; }
fn findRecordShape(self_: const Store&,names: const u32[:]) -> u32,bool {
 let bucket=self_.record_shapes.get(namesHash(names)); var candidate: u32=0; if bucket { candidate=bucket; }
 while candidate!=0 { let span=self_.record_layouts.items[candidate]; if self_.field_names.items[span.start..span.start+span.len]==names { return candidate,true; } candidate=self_.record_shape_next.items[candidate]; } return 0,false;
}
fn saveRecordShape(self_: Store,names: const u32[:]) -> u32 {
 let existing,found=findRecordShape(self_,names); if found { return existing; } var stable: u32[>..]=[]; stable.append(names); let hash=namesHash(stable); var previous: u32=0; let bucket=self_.record_shapes.get(hash); if bucket { previous=bucket; }
 let id=self_.record_layouts.len as u32; self_.record_layouts.push(blot_check_core::List {self_.field_names.len as u32,stable.len as u32}); self_.field_names.append(stable); self_.record_shape_next.push(previous); self_.record_shapes.insert(hash,id); return id;
}
struct SnapshotTables { code_origins: blot_check_staging_origins::Record[>..]&,values: ValueInfo[>..]&,children: ValueId[>..]&,closures: ClosureValue[>..]&,value_evidence: u32[>..]&,type_mappings: blot_eval_type_evidence::Mapping[>..]&,row_mappings: blot_eval_type_evidence::RowMapping[>..]&,value_records: u32[>..]&,record_layouts: blot_check_core::List[>..]&,field_names: u32[>..]&,evidence: blot_eval_type_evidence::SnapshotTables,implementation_proofs: blot_eval_implementation_evidence::SnapshotTables }
fn copySnapshot(self_: const Store&,proofs: const blot_eval_implementation_evidence::Store&,target: SnapshotTables) -> Snapshot,Error {
 let co=target.code_origins.len; let va=target.values.len; let ch=target.children.len; let cl=target.closures.len; let ve=target.value_evidence.len; let tm=target.type_mappings.len; let rm=target.row_mappings.len; let vr=target.value_records.len; let rl=target.record_layouts.len; let fnames=target.field_names.len;
 target.code_origins.append(self_.code_origins.items); target.values.append(self_.values.items); target.children.append(self_.children.items); target.closures.append(self_.closures.items); target.value_evidence.append(self_.value_evidence.items); target.type_mappings.append(self_.type_mappings.items); target.row_mappings.append(self_.row_mappings.items); target.value_records.append(self_.value_records.items); target.record_layouts.append(self_.record_layouts.items); target.field_names.append(self_.field_names.items);
 let selected,e=proofs.copyOwned(target.implementation_proofs); if e!=blot_error::Error.none { return default<Snapshot>(),e; } let evidence,error=self_.evidence.copyOwned(target.evidence); if error!=blot_error::Error.none { return default<Snapshot>(),error; }
 return Snapshot {code_origins:target.code_origins[co..],values:target.values[va..],children:target.children[ch..],closures:target.closures[cl..],value_evidence:target.value_evidence[ve..],type_mappings:target.type_mappings[tm..],row_mappings:target.row_mappings[rm..],evidence:evidence,value_records:target.value_records[vr..],record_layouts:target.record_layouts[rl..],field_names:target.field_names[fnames..],implementation_proofs:selected},blot_error::Error.none;
}

fn valueKindCode(value: ValueKind) -> u8 { match value { scalar=>0,product=>1,record=>2,nominal=>3,array=>4,list=>5,closure=>6,type_constructor=>7,resolver=>8,provider=>9,state_provider=>10,effect_set=>11,effect_descriptor=>12,computation=>13,request_decision=>14,cursor=>15,proof=>16,package=>17,code=>18,descriptor=>19,staged_value=>20,capability=>21 } }

fn closureOriginCode(value: ClosureOrigin) -> u8 { match value { named=>0,anonymous=>1,constructor=>2,primitive=>3,operation=>4 } }
fn deinit(self_: Store&) { if self_.lease==0 { return; } assert(valid(self_)); self_.values.deinit(); self_.children.deinit(); self_.closures.deinit(); self_.code_origins.deinit(); self_.value_evidence.deinit(); self_.type_mappings.deinit(); self_.row_mappings.deinit(); self_.value_records.deinit(); self_.record_layouts.deinit(); self_.field_names.deinit(); self_.record_shape_next.deinit(); release(self_.typed_views); release(self_.specialized_closures); release(self_.record_types); release(self_.record_shapes); self_.evidence.deinit(); self_.collection_buffers.deinit(); let at=self_.lease-1; states[at].live=false; states.free(at); let handle=self_.handle_index; self_=Store {}; if handle>=0 { handles.free(handle); } }
fn reset(self_: Store) -> Error { assert(valid(self_)); self_.values.clear(); self_.children.clear(); self_.closures.clear(); self_.code_origins.clear(); self_.value_evidence.clear(); self_.type_mappings.clear(); self_.row_mappings.clear(); self_.value_records.clear(); self_.record_layouts.clear(); self_.field_names.clear(); self_.record_shape_next.clear(); self_.typed_views.clear(); self_.specialized_closures.clear(); self_.record_types.clear(); self_.record_shapes.clear(); self_.evidence.deinit(); self_.collection_buffers.buffers.clear(); self_.collection_buffers.owner_id=blot_native::fresh_owner_id(); self_.collection_buffers.mutation_serial=0; let semantic,error=blot_eval_type_evidence::init(); if error!=blot_error::Error.none { return error; } self_.evidence=semantic; self_.owner_id=blot_native::fresh_owner_id(); seedEmpty(self_); return blot_error::Error.none; }

fn reserve(self_: TypedViewsMap&,count: i64) -> Error { if count<0||count>0x1555555555555555 { return blot_error::Error.out_of_memory; } var capacity=max(8,self_.slots.len); while count*3>capacity*2 { capacity*=2; } if capacity>self_.slots.len { var view=blot_support_pooled_map::Map<ViewKey,ValueId> {count:self_.count,slots:self_.slots}; blot_support_pooled_map::grow(view,capacity,pool_TypedViewsMap); self_.count=view.count; self_.slots=view.slots; } return blot_error::Error.none; }

fn reserve(self_: RecordTypesMap&,count: i64) -> Error { if count<0||count>0x1555555555555555 { return blot_error::Error.out_of_memory; } var capacity=max(8,self_.slots.len); while count*3>capacity*2 { capacity*=2; } if capacity>self_.slots.len { var view=blot_support_pooled_map::Map<RecordKey,u32> {count:self_.count,slots:self_.slots}; blot_support_pooled_map::grow(view,capacity,pool_RecordTypesMap); self_.count=view.count; self_.slots=view.slots; } return blot_error::Error.none; }

fn reserve(self_: RecordShapesMap&,count: i64) -> Error { if count<0||count>0x1555555555555555 { return blot_error::Error.out_of_memory; } var capacity=max(8,self_.slots.len); while count*3>capacity*2 { capacity*=2; } if capacity>self_.slots.len { var view=blot_support_pooled_map::Map<u64,u32> {count:self_.count,slots:self_.slots}; blot_support_pooled_map::grow(view,capacity,pool_RecordShapesMap); self_.count=view.count; self_.slots=view.slots; } return blot_error::Error.none; }
