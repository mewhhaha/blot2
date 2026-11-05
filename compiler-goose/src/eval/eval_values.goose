// Immutable values and parallel metadata. This owner publishes no judgments.
namespace blot_eval_eval_values;
import std;
import dictionary;
import support.pooled_buffer;
import support.pooled_map;
import check.core;
import check.types;
import check.staging_origins;
import backend.scalar_ops;
import backend.runtime_ir;
import .type_evidence;
import .implementation_evidence;
import .eval_collection_growth;
import support.error;
import support.native;
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
fn hash(self: RecordNames,key: blot_check_core::List) -> u64 { return namesHash(self.words[key.start..key.start+key.len]); }
fn eql(self: RecordNames,a: blot_check_core::List,b: blot_check_core::List) -> bool { return self.words[a.start..a.start+a.len]==self.words[b.start..b.start+b.len]; }
fn namesHash(names: const u32[:]) -> u64 { var hash: u64=0; for name in names { hash=::hash_combine(hash,::hash(name)); } return hash; }
struct ValuesBuffer { storage: ValueInfo[:]=[],items: ValueInfo[:]=[],len: i64=0,failure: Error=Error.none }
reusable[] var pool_ValuesBuffer: ValueInfo[>..]=[];
fn ensure(self: ValuesBuffer&,minimum: i64) -> Error { if self.failure!=Error.none { return self.failure; } let error=blot_support_pooled_buffer::ensure(self,minimum,pool_ValuesBuffer); if error!=Error.none { self.failure=error; } return error; }
fn push(self: ValuesBuffer&,value: ValueInfo) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::push(self,value,pool_ValuesBuffer); self.len=self.items.len; }
fn append(self: ValuesBuffer&,values: const ValueInfo[:]) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::append(self,values,pool_ValuesBuffer); self.len=self.items.len; }
fn resize(self: ValuesBuffer&,length: i64) { blot_support_pooled_buffer::resize(self,length); self.len=length; }
fn resize(self: ValuesBuffer&,length: i64,value: ValueInfo) { if length<=self.len { resize(self,length); return; } let error=ensure(self,length); if error!=Error.none { return; } for index in self.len..length { self.storage[index]=value; } self.items=self.storage[..length]; self.len=length; }
fn clear(self: ValuesBuffer&) { blot_support_pooled_buffer::clear(self); self.len=0; self.failure=Error.none; }
fn deinit(self: ValuesBuffer&) { blot_support_pooled_buffer::deinit(self,pool_ValuesBuffer); self.len=0; self.failure=Error.none; }
struct ClosuresBuffer { storage: ClosureValue[:]=[],items: ClosureValue[:]=[],len: i64=0,failure: Error=Error.none }
reusable[] var pool_ClosuresBuffer: ClosureValue[>..]=[];
fn ensure(self: ClosuresBuffer&,minimum: i64) -> Error { if self.failure!=Error.none { return self.failure; } let error=blot_support_pooled_buffer::ensure(self,minimum,pool_ClosuresBuffer); if error!=Error.none { self.failure=error; } return error; }
fn push(self: ClosuresBuffer&,value: ClosureValue) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::push(self,value,pool_ClosuresBuffer); self.len=self.items.len; }
fn append(self: ClosuresBuffer&,values: const ClosureValue[:]) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::append(self,values,pool_ClosuresBuffer); self.len=self.items.len; }
fn resize(self: ClosuresBuffer&,length: i64) { blot_support_pooled_buffer::resize(self,length); self.len=length; }
fn resize(self: ClosuresBuffer&,length: i64,value: ClosureValue) { if length<=self.len { resize(self,length); return; } let error=ensure(self,length); if error!=Error.none { return; } for index in self.len..length { self.storage[index]=value; } self.items=self.storage[..length]; self.len=length; }
fn clear(self: ClosuresBuffer&) { blot_support_pooled_buffer::clear(self); self.len=0; self.failure=Error.none; }
fn deinit(self: ClosuresBuffer&) { blot_support_pooled_buffer::deinit(self,pool_ClosuresBuffer); self.len=0; self.failure=Error.none; }
struct CodeOriginsBuffer { storage: blot_check_staging_origins::Record[:]=[],items: blot_check_staging_origins::Record[:]=[],len: i64=0,failure: Error=Error.none }
reusable[] var pool_CodeOriginsBuffer: blot_check_staging_origins::Record[>..]=[];
fn ensure(self: CodeOriginsBuffer&,minimum: i64) -> Error { if self.failure!=Error.none { return self.failure; } let error=blot_support_pooled_buffer::ensure(self,minimum,pool_CodeOriginsBuffer); if error!=Error.none { self.failure=error; } return error; }
fn push(self: CodeOriginsBuffer&,value: blot_check_staging_origins::Record) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::push(self,value,pool_CodeOriginsBuffer); self.len=self.items.len; }
fn append(self: CodeOriginsBuffer&,values: const blot_check_staging_origins::Record[:]) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::append(self,values,pool_CodeOriginsBuffer); self.len=self.items.len; }
fn resize(self: CodeOriginsBuffer&,length: i64) { blot_support_pooled_buffer::resize(self,length); self.len=length; }
fn resize(self: CodeOriginsBuffer&,length: i64,value: blot_check_staging_origins::Record) { if length<=self.len { resize(self,length); return; } let error=ensure(self,length); if error!=Error.none { return; } for index in self.len..length { self.storage[index]=value; } self.items=self.storage[..length]; self.len=length; }
fn clear(self: CodeOriginsBuffer&) { blot_support_pooled_buffer::clear(self); self.len=0; self.failure=Error.none; }
fn deinit(self: CodeOriginsBuffer&) { blot_support_pooled_buffer::deinit(self,pool_CodeOriginsBuffer); self.len=0; self.failure=Error.none; }
struct Words { storage: u32[:]=[],items: u32[:]=[],len: i64=0,failure: Error=Error.none }
reusable[] var pool_Words: u32[>..]=[];
fn ensure(self: Words&,minimum: i64) -> Error { if self.failure!=Error.none { return self.failure; } let error=blot_support_pooled_buffer::ensure(self,minimum,pool_Words); if error!=Error.none { self.failure=error; } return error; }
fn push(self: Words&,value: u32) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::push(self,value,pool_Words); self.len=self.items.len; }
fn append(self: Words&,values: const u32[:]) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::append(self,values,pool_Words); self.len=self.items.len; }
fn resize(self: Words&,length: i64) { blot_support_pooled_buffer::resize(self,length); self.len=length; }
fn resize(self: Words&,length: i64,value: u32) { if length<=self.len { resize(self,length); return; } let error=ensure(self,length); if error!=Error.none { return; } for index in self.len..length { self.storage[index]=value; } self.items=self.storage[..length]; self.len=length; }
fn clear(self: Words&) { blot_support_pooled_buffer::clear(self); self.len=0; self.failure=Error.none; }
fn deinit(self: Words&) { blot_support_pooled_buffer::deinit(self,pool_Words); self.len=0; self.failure=Error.none; }
struct TypeMappingsBuffer { storage: blot_eval_type_evidence::Mapping[:]=[],items: blot_eval_type_evidence::Mapping[:]=[],len: i64=0,failure: Error=Error.none }
reusable[] var pool_TypeMappingsBuffer: blot_eval_type_evidence::Mapping[>..]=[];
fn ensure(self: TypeMappingsBuffer&,minimum: i64) -> Error { if self.failure!=Error.none { return self.failure; } let error=blot_support_pooled_buffer::ensure(self,minimum,pool_TypeMappingsBuffer); if error!=Error.none { self.failure=error; } return error; }
fn push(self: TypeMappingsBuffer&,value: blot_eval_type_evidence::Mapping) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::push(self,value,pool_TypeMappingsBuffer); self.len=self.items.len; }
fn append(self: TypeMappingsBuffer&,values: const blot_eval_type_evidence::Mapping[:]) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::append(self,values,pool_TypeMappingsBuffer); self.len=self.items.len; }
fn resize(self: TypeMappingsBuffer&,length: i64) { blot_support_pooled_buffer::resize(self,length); self.len=length; }
fn resize(self: TypeMappingsBuffer&,length: i64,value: blot_eval_type_evidence::Mapping) { if length<=self.len { resize(self,length); return; } let error=ensure(self,length); if error!=Error.none { return; } for index in self.len..length { self.storage[index]=value; } self.items=self.storage[..length]; self.len=length; }
fn clear(self: TypeMappingsBuffer&) { blot_support_pooled_buffer::clear(self); self.len=0; self.failure=Error.none; }
fn deinit(self: TypeMappingsBuffer&) { blot_support_pooled_buffer::deinit(self,pool_TypeMappingsBuffer); self.len=0; self.failure=Error.none; }
struct RowMappingsBuffer { storage: blot_eval_type_evidence::RowMapping[:]=[],items: blot_eval_type_evidence::RowMapping[:]=[],len: i64=0,failure: Error=Error.none }
reusable[] var pool_RowMappingsBuffer: blot_eval_type_evidence::RowMapping[>..]=[];
fn ensure(self: RowMappingsBuffer&,minimum: i64) -> Error { if self.failure!=Error.none { return self.failure; } let error=blot_support_pooled_buffer::ensure(self,minimum,pool_RowMappingsBuffer); if error!=Error.none { self.failure=error; } return error; }
fn push(self: RowMappingsBuffer&,value: blot_eval_type_evidence::RowMapping) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::push(self,value,pool_RowMappingsBuffer); self.len=self.items.len; }
fn append(self: RowMappingsBuffer&,values: const blot_eval_type_evidence::RowMapping[:]) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::append(self,values,pool_RowMappingsBuffer); self.len=self.items.len; }
fn resize(self: RowMappingsBuffer&,length: i64) { blot_support_pooled_buffer::resize(self,length); self.len=length; }
fn resize(self: RowMappingsBuffer&,length: i64,value: blot_eval_type_evidence::RowMapping) { if length<=self.len { resize(self,length); return; } let error=ensure(self,length); if error!=Error.none { return; } for index in self.len..length { self.storage[index]=value; } self.items=self.storage[..length]; self.len=length; }
fn clear(self: RowMappingsBuffer&) { blot_support_pooled_buffer::clear(self); self.len=0; self.failure=Error.none; }
fn deinit(self: RowMappingsBuffer&) { blot_support_pooled_buffer::deinit(self,pool_RowMappingsBuffer); self.len=0; self.failure=Error.none; }
struct RecordLayoutsBuffer { storage: blot_check_core::List[:]=[],items: blot_check_core::List[:]=[],len: i64=0,failure: Error=Error.none }
reusable[] var pool_RecordLayoutsBuffer: blot_check_core::List[>..]=[];
fn ensure(self: RecordLayoutsBuffer&,minimum: i64) -> Error { if self.failure!=Error.none { return self.failure; } let error=blot_support_pooled_buffer::ensure(self,minimum,pool_RecordLayoutsBuffer); if error!=Error.none { self.failure=error; } return error; }
fn push(self: RecordLayoutsBuffer&,value: blot_check_core::List) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::push(self,value,pool_RecordLayoutsBuffer); self.len=self.items.len; }
fn append(self: RecordLayoutsBuffer&,values: const blot_check_core::List[:]) { if self.failure!=Error.none { return; } self.failure=blot_support_pooled_buffer::append(self,values,pool_RecordLayoutsBuffer); self.len=self.items.len; }
fn resize(self: RecordLayoutsBuffer&,length: i64) { blot_support_pooled_buffer::resize(self,length); self.len=length; }
fn resize(self: RecordLayoutsBuffer&,length: i64,value: blot_check_core::List) { if length<=self.len { resize(self,length); return; } let error=ensure(self,length); if error!=Error.none { return; } for index in self.len..length { self.storage[index]=value; } self.items=self.storage[..length]; self.len=length; }
fn clear(self: RecordLayoutsBuffer&) { blot_support_pooled_buffer::clear(self); self.len=0; self.failure=Error.none; }
fn deinit(self: RecordLayoutsBuffer&) { blot_support_pooled_buffer::deinit(self,pool_RecordLayoutsBuffer); self.len=0; self.failure=Error.none; }
struct TypedViewsMap { count: i64=0,slots: dictionary_slot<ViewKey,ValueId>[:]=[] }
reusable[] var pool_TypedViewsMap: dictionary_slot<ViewKey,ValueId>[>..]=[];
fn get(self: const TypedViewsMap&,key: ViewKey) -> ValueId? { let view=blot_support_pooled_map::Map<ViewKey,ValueId> {count:self.count,slots:self.slots}; return blot_support_pooled_map::get(view,key); }
fn contains(self: const TypedViewsMap&,key: ViewKey) -> bool { return self.get(key)!=null; }
fn insert(self: TypedViewsMap&,key: ViewKey,value: ValueId) { var view=blot_support_pooled_map::Map<ViewKey,ValueId> {count:self.count,slots:self.slots}; blot_support_pooled_map::insert(view,key,value,pool_TypedViewsMap); self.count=view.count; self.slots=view.slots; }
fn clear(self: TypedViewsMap&) { for &slot in self.slots { slot.tag=0; } self.count=0; }
fn release(self: TypedViewsMap&) { if self.slots.len!=0 { pool_TypedViewsMap.free_slice(self.slots); } self.slots=[]; self.count=0; }
fn restore(self: TypedViewsMap&,slots: const dictionary_slot<ViewKey,ValueId>[:],count: i64) { release(self); self.count=count; if slots.len!=0 { self.slots=pool_TypedViewsMap.alloc_slice(slots.len); for slot,index in slots { self.slots[index]=slot; } } }
struct RecordTypesMap { count: i64=0,slots: dictionary_slot<RecordKey,u32>[:]=[] }
reusable[] var pool_RecordTypesMap: dictionary_slot<RecordKey,u32>[>..]=[];
fn get(self: const RecordTypesMap&,key: RecordKey) -> u32? { let view=blot_support_pooled_map::Map<RecordKey,u32> {count:self.count,slots:self.slots}; return blot_support_pooled_map::get(view,key); }
fn contains(self: const RecordTypesMap&,key: RecordKey) -> bool { return self.get(key)!=null; }
fn insert(self: RecordTypesMap&,key: RecordKey,value: u32) { var view=blot_support_pooled_map::Map<RecordKey,u32> {count:self.count,slots:self.slots}; blot_support_pooled_map::insert(view,key,value,pool_RecordTypesMap); self.count=view.count; self.slots=view.slots; }
fn clear(self: RecordTypesMap&) { for &slot in self.slots { slot.tag=0; } self.count=0; }
fn release(self: RecordTypesMap&) { if self.slots.len!=0 { pool_RecordTypesMap.free_slice(self.slots); } self.slots=[]; self.count=0; }
fn restore(self: RecordTypesMap&,slots: const dictionary_slot<RecordKey,u32>[:],count: i64) { release(self); self.count=count; if slots.len!=0 { self.slots=pool_RecordTypesMap.alloc_slice(slots.len); for slot,index in slots { self.slots[index]=slot; } } }
struct RecordShapesMap { count: i64=0,slots: dictionary_slot<u64,u32>[:]=[] }
reusable[] var pool_RecordShapesMap: dictionary_slot<u64,u32>[>..]=[];
fn get(self: const RecordShapesMap&,key: u64) -> u32? { let view=blot_support_pooled_map::Map<u64,u32> {count:self.count,slots:self.slots}; return blot_support_pooled_map::get(view,key); }
fn contains(self: const RecordShapesMap&,key: u64) -> bool { return self.get(key)!=null; }
fn insert(self: RecordShapesMap&,key: u64,value: u32) { var view=blot_support_pooled_map::Map<u64,u32> {count:self.count,slots:self.slots}; blot_support_pooled_map::insert(view,key,value,pool_RecordShapesMap); self.count=view.count; self.slots=view.slots; }
fn clear(self: RecordShapesMap&) { for &slot in self.slots { slot.tag=0; } self.count=0; }
fn release(self: RecordShapesMap&) { if self.slots.len!=0 { pool_RecordShapesMap.free_slice(self.slots); } self.slots=[]; self.count=0; }
fn restore(self: RecordShapesMap&,slots: const dictionary_slot<u64,u32>[:],count: i64) { release(self); self.count=count; if slots.len!=0 { self.slots=pool_RecordShapesMap.alloc_slice(slots.len); for slot,index in slots { self.slots[index]=slot; } } }
struct State { owner_id: u64=0,generation: u64=0,live: bool=false,evidence: blot_eval_type_evidence::Store=blot_eval_type_evidence::Store {},collection_buffers: blot_eval_eval_collection_growth::Store=blot_eval_eval_collection_growth::Store {},values: ValuesBuffer=ValuesBuffer {},children: Words=Words {},closures: ClosuresBuffer=ClosuresBuffer {},code_origins: CodeOriginsBuffer=CodeOriginsBuffer {},value_evidence: Words=Words {},type_mappings: TypeMappingsBuffer=TypeMappingsBuffer {},row_mappings: RowMappingsBuffer=RowMappingsBuffer {},value_records: Words=Words {},record_layouts: RecordLayoutsBuffer=RecordLayoutsBuffer {},field_names: Words=Words {},record_shape_next: Words=Words {},typed_views: TypedViewsMap=TypedViewsMap {},specialized_closures: TypedViewsMap=TypedViewsMap {},record_types: RecordTypesMap=RecordTypesMap {},record_shapes: RecordShapesMap=RecordShapesMap {} }
reusable var states: State[>..]=[];
var inactive: State=State {};
var next_generation: u64=1;
struct Store { owner_id: u64&=inactive.owner_id,evidence: blot_eval_type_evidence::Store&=inactive.evidence,collection_buffers: blot_eval_eval_collection_growth::Store&=inactive.collection_buffers,values: ValuesBuffer&=inactive.values,children: Words&=inactive.children,closures: ClosuresBuffer&=inactive.closures,code_origins: CodeOriginsBuffer&=inactive.code_origins,value_evidence: Words&=inactive.value_evidence,type_mappings: TypeMappingsBuffer&=inactive.type_mappings,row_mappings: RowMappingsBuffer&=inactive.row_mappings,value_records: Words&=inactive.value_records,record_layouts: RecordLayoutsBuffer&=inactive.record_layouts,field_names: Words&=inactive.field_names,record_shape_next: Words&=inactive.record_shape_next,typed_views: TypedViewsMap&=inactive.typed_views,specialized_closures: TypedViewsMap&=inactive.specialized_closures,record_types: RecordTypesMap&=inactive.record_types,record_shapes: RecordShapesMap&=inactive.record_shapes,lease: u32=0,generation: u64=0,handle_index: i64=-1 }
reusable var handles: Store[>..]=[];
fn initPooled() -> Store,Error { if next_generation==0xffffffffffffffff||states.len>=0xffffffff { return Store {},Error.out_of_memory; } let semantic,semantic_error=blot_eval_type_evidence::init(); if semantic_error!=Error.none { return Store {},semantic_error; } var evidence=semantic; let growth,growth_error=blot_eval_eval_collection_growth::initPooled(); if growth_error!=Error.none { evidence.deinit(); return Store {},growth_error; } let generation=next_generation; next_generation++; let index=states.alloc_index(State {owner_id:blot_native::fresh_owner_id(),generation:generation,live:true,evidence:evidence,collection_buffers:growth}); let state: State&=states[index]; var self=Store {owner_id:state.owner_id,evidence:state.evidence,collection_buffers:state.collection_buffers,values:state.values,children:state.children,closures:state.closures,code_origins:state.code_origins,value_evidence:state.value_evidence,type_mappings:state.type_mappings,row_mappings:state.row_mappings,value_records:state.value_records,record_layouts:state.record_layouts,field_names:state.field_names,record_shape_next:state.record_shape_next,typed_views:state.typed_views,specialized_closures:state.specialized_closures,record_types:state.record_types,record_shapes:state.record_shapes,lease:(index+1) as u32,generation:generation}; seedEmpty(self); return self,Error.none; }
fn initPooledRef() -> Store?,Error { let value,error=initPooled(); if error!=Error.none { return null,error; } let index=handles.alloc_index(value); handles[index].handle_index=index; return handles[index],Error.none; }
fn seedEmpty(self: Store) { self.values.push(ValueInfo {}); self.value_evidence.push(1); self.value_records.push(0); self.record_layouts.push(blot_check_core::List {}); self.record_shape_next.push(0); }
fn valid(self: Store) -> bool { return self.lease!=0&&self.lease-1<states.len&&states[self.lease-1].live&&states[self.lease-1].generation==self.generation; }
fn scalar(self: Store,value: Value) -> ValueId,Error {
 let id=self.values.len as ValueId; self.values.push(ValueInfo {scalar:value.scalar,bits:value.bits}); var evidence: u32=0;
 if value.scalar==blot_backend_runtime_ir::SC_unit { evidence=1; } else if value.scalar==blot_backend_runtime_ir::SC_bool { evidence=2; } else if value.scalar==blot_backend_runtime_ir::SC_u32 { evidence=3; } else if value.scalar==blot_backend_runtime_ir::SC_f32 { evidence=4; }
 self.value_evidence.push(evidence); self.value_records.push(0); return id,Error.none;
}
fn aggregate(self: Store,kind: ValueKind,nominal: u64,tag: u32,children: const ValueId[:]) -> ValueId,Error {
 var stable: ValueId[>..]=[]; stable.append(children); let id=self.values.len as ValueId; let start=self.children.len as u32; self.children.append(stable); self.values.push(ValueInfo {nominal:nominal,start:start,len:stable.len as u32,bits:tag,kind:kind}); self.value_evidence.push(0); self.value_records.push(0); return id,Error.none;
}
fn view(self: const Store&,proofs: blot_eval_implementation_evidence::View) -> View { return View {self.owner_id,self.code_origins.items,self.values.items,self.children.items,self.closures.items,self.value_evidence.items,self.type_mappings.items,self.row_mappings.items,self.evidence.view(),self.value_records.items,self.record_layouts.items,self.field_names.items,proofs}; }
fn view(self: const Snapshot&) -> View { return View {self.owner_id,self.code_origins,self.values,self.children,self.closures,self.value_evidence,self.type_mappings,self.row_mappings,self.evidence.view(),self.value_records,self.record_layouts,self.field_names,self.implementation_proofs.view()}; }
fn findRecordShape(self: const Store&,names: const u32[:]) -> u32,bool {
 let bucket=self.record_shapes.get(namesHash(names)); var candidate: u32=0; if bucket { candidate=bucket; }
 while candidate!=0 { let span=self.record_layouts.items[candidate]; if self.field_names.items[span.start..span.start+span.len]==names { return candidate,true; } candidate=self.record_shape_next.items[candidate]; } return 0,false;
}
fn saveRecordShape(self: Store,names: const u32[:]) -> u32 {
 let existing,found=findRecordShape(self,names); if found { return existing; } var stable: u32[>..]=[]; stable.append(names); let hash=namesHash(stable); var previous: u32=0; let bucket=self.record_shapes.get(hash); if bucket { previous=bucket; }
 let id=self.record_layouts.len as u32; self.record_layouts.push(blot_check_core::List {self.field_names.len as u32,stable.len as u32}); self.field_names.append(stable); self.record_shape_next.push(previous); self.record_shapes.insert(hash,id); return id;
}
struct SnapshotTables { code_origins: blot_check_staging_origins::Record[>..]&,values: ValueInfo[>..]&,children: ValueId[>..]&,closures: ClosureValue[>..]&,value_evidence: u32[>..]&,type_mappings: blot_eval_type_evidence::Mapping[>..]&,row_mappings: blot_eval_type_evidence::RowMapping[>..]&,value_records: u32[>..]&,record_layouts: blot_check_core::List[>..]&,field_names: u32[>..]&,evidence: blot_eval_type_evidence::SnapshotTables,implementation_proofs: blot_eval_implementation_evidence::SnapshotTables }
fn copySnapshot(self: const Store&,proofs: const blot_eval_implementation_evidence::Store&,target: SnapshotTables) -> Snapshot,Error {
 let co=target.code_origins.len; let va=target.values.len; let ch=target.children.len; let cl=target.closures.len; let ve=target.value_evidence.len; let tm=target.type_mappings.len; let rm=target.row_mappings.len; let vr=target.value_records.len; let rl=target.record_layouts.len; let fnames=target.field_names.len;
 target.code_origins.append(self.code_origins.items); target.values.append(self.values.items); target.children.append(self.children.items); target.closures.append(self.closures.items); target.value_evidence.append(self.value_evidence.items); target.type_mappings.append(self.type_mappings.items); target.row_mappings.append(self.row_mappings.items); target.value_records.append(self.value_records.items); target.record_layouts.append(self.record_layouts.items); target.field_names.append(self.field_names.items);
 let selected,e=proofs.copyOwned(target.implementation_proofs); if e!=Error.none { return default<Snapshot>(),e; } let evidence,error=self.evidence.copyOwned(target.evidence); if error!=Error.none { return default<Snapshot>(),error; }
 return Snapshot {code_origins:target.code_origins[co..],values:target.values[va..],children:target.children[ch..],closures:target.closures[cl..],value_evidence:target.value_evidence[ve..],type_mappings:target.type_mappings[tm..],row_mappings:target.row_mappings[rm..],evidence:evidence,value_records:target.value_records[vr..],record_layouts:target.record_layouts[rl..],field_names:target.field_names[fnames..],implementation_proofs:selected},Error.none;
}

fn valueKindCode(value: ValueKind) -> u8 { match value { scalar=>0,product=>1,record=>2,nominal=>3,array=>4,list=>5,closure=>6,type_constructor=>7,resolver=>8,provider=>9,state_provider=>10,effect_set=>11,effect_descriptor=>12,computation=>13,request_decision=>14,cursor=>15,proof=>16,package=>17,code=>18,descriptor=>19,staged_value=>20,capability=>21 } }

fn closureOriginCode(value: ClosureOrigin) -> u8 { match value { named=>0,anonymous=>1,constructor=>2,primitive=>3,operation=>4 } }
fn deinit(self: Store&) { if self.lease==0 { return; } assert(valid(self)); self.values.deinit(); self.children.deinit(); self.closures.deinit(); self.code_origins.deinit(); self.value_evidence.deinit(); self.type_mappings.deinit(); self.row_mappings.deinit(); self.value_records.deinit(); self.record_layouts.deinit(); self.field_names.deinit(); self.record_shape_next.deinit(); release(self.typed_views); release(self.specialized_closures); release(self.record_types); release(self.record_shapes); self.evidence.deinit(); self.collection_buffers.deinit(); let at=self.lease-1; states[at].live=false; states.free(at); let handle=self.handle_index; self=Store {}; if handle>=0 { handles.free(handle); } }
fn reset(self: Store) -> Error { assert(valid(self)); self.values.clear(); self.children.clear(); self.closures.clear(); self.code_origins.clear(); self.value_evidence.clear(); self.type_mappings.clear(); self.row_mappings.clear(); self.value_records.clear(); self.record_layouts.clear(); self.field_names.clear(); self.record_shape_next.clear(); self.typed_views.clear(); self.specialized_closures.clear(); self.record_types.clear(); self.record_shapes.clear(); self.evidence.deinit(); self.collection_buffers.buffers.clear(); self.collection_buffers.owner_id=blot_native::fresh_owner_id(); self.collection_buffers.mutation_serial=0; let semantic,error=blot_eval_type_evidence::init(); if error!=Error.none { return error; } self.evidence=semantic; self.owner_id=blot_native::fresh_owner_id(); seedEmpty(self); return Error.none; }

fn reserve(self: TypedViewsMap&,count: i64) -> Error { if count<0||count>0x1555555555555555 { return Error.out_of_memory; } var capacity=max(8,self.slots.len); while count*3>capacity*2 { capacity*=2; } if capacity>self.slots.len { var view=blot_support_pooled_map::Map<ViewKey,ValueId> {count:self.count,slots:self.slots}; blot_support_pooled_map::grow(view,capacity,pool_TypedViewsMap); self.count=view.count; self.slots=view.slots; } return Error.none; }

fn reserve(self: RecordTypesMap&,count: i64) -> Error { if count<0||count>0x1555555555555555 { return Error.out_of_memory; } var capacity=max(8,self.slots.len); while count*3>capacity*2 { capacity*=2; } if capacity>self.slots.len { var view=blot_support_pooled_map::Map<RecordKey,u32> {count:self.count,slots:self.slots}; blot_support_pooled_map::grow(view,capacity,pool_RecordTypesMap); self.count=view.count; self.slots=view.slots; } return Error.none; }

fn reserve(self: RecordShapesMap&,count: i64) -> Error { if count<0||count>0x1555555555555555 { return Error.out_of_memory; } var capacity=max(8,self.slots.len); while count*3>capacity*2 { capacity*=2; } if capacity>self.slots.len { var view=blot_support_pooled_map::Map<u64,u32> {count:self.count,slots:self.slots}; blot_support_pooled_map::grow(view,capacity,pool_RecordShapesMap); self.count=view.count; self.slots=view.slots; } return Error.none; }
