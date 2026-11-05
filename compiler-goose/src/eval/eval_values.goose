// Immutable values and parallel metadata. This owner publishes no judgments.
namespace blot_eval_eval_values;
import std;
import dictionary;
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
struct Store {
 owner_id: u64=blot_native::fresh_owner_id(),values: ValueInfo[>..<]&,children: ValueId[>..<]&,collection_buffers: blot_eval_eval_collection_growth::Store&,closures: ClosureValue[>..<]&,code_origins: blot_check_staging_origins::Record[>..<]&,value_evidence: u32[>..<]&,type_mappings: blot_eval_type_evidence::Mapping[>..<]&,row_mappings: blot_eval_type_evidence::RowMapping[>..<]&,evidence: blot_eval_type_evidence::Store&,typed_views: dictionary<ViewKey,ValueId>&,specialized_closures: dictionary<ViewKey,ValueId>&,value_records: u32[>..<]&,record_layouts: blot_check_core::List[>..<]&,field_names: u32[>..<]&,record_types: dictionary<RecordKey,u32>&,record_shapes: dictionary<u64,u32>&,record_shape_next: u32[>..<]&
}
struct Tables {
 values: ValueInfo[>..<]&,children: ValueId[>..<]&,closures: ClosureValue[>..<]&,code_origins: blot_check_staging_origins::Record[>..<]&,value_evidence: u32[>..<]&,type_mappings: blot_eval_type_evidence::Mapping[>..<]&,row_mappings: blot_eval_type_evidence::RowMapping[>..<]&,typed_views: dictionary<ViewKey,ValueId>&,specialized_closures: dictionary<ViewKey,ValueId>&,value_records: u32[>..<]&,record_layouts: blot_check_core::List[>..<]&,field_names: u32[>..<]&,record_types: dictionary<RecordKey,u32>&,record_shapes: dictionary<u64,u32>&,record_shape_next: u32[>..<]&
}
fn init(t: Tables,evidence: blot_eval_type_evidence::Store&,buffers: blot_eval_eval_collection_growth::Store&) -> Store {
 t.values.push(ValueInfo {}); t.value_evidence.push(1); t.value_records.push(0); t.record_layouts.push(blot_check_core::List {}); t.record_shape_next.push(0);
 return Store {values:t.values,children:t.children,collection_buffers:buffers,closures:t.closures,code_origins:t.code_origins,value_evidence:t.value_evidence,type_mappings:t.type_mappings,row_mappings:t.row_mappings,evidence:evidence,typed_views:t.typed_views,specialized_closures:t.specialized_closures,value_records:t.value_records,record_layouts:t.record_layouts,field_names:t.field_names,record_types:t.record_types,record_shapes:t.record_shapes,record_shape_next:t.record_shape_next};
}
fn scalar(self: Store&,value: Value) -> ValueId,Error {
 let id=self.values.len as ValueId; self.values.push(ValueInfo {scalar:value.scalar,bits:value.bits}); var evidence: u32=0;
 if value.scalar==blot_backend_runtime_ir::SC_unit { evidence=1; } else if value.scalar==blot_backend_runtime_ir::SC_bool { evidence=2; } else if value.scalar==blot_backend_runtime_ir::SC_u32 { evidence=3; } else if value.scalar==blot_backend_runtime_ir::SC_f32 { evidence=4; }
 self.value_evidence.push(evidence); self.value_records.push(0); return id,Error.none;
}
fn aggregate(self: Store&,kind: ValueKind,nominal: u64,tag: u32,children: const ValueId[:]) -> ValueId,Error {
 var stable: ValueId[>..]=[]; stable.append(children); let id=self.values.len as ValueId; let start=self.children.len as u32; self.children.append(stable); self.values.push(ValueInfo {nominal:nominal,start:start,len:stable.len as u32,bits:tag,kind:kind}); self.value_evidence.push(0); self.value_records.push(0); return id,Error.none;
}
fn view(self: const Store&,proofs: blot_eval_implementation_evidence::View) -> View { return View {self.owner_id,self.code_origins,self.values,self.children,self.closures,self.value_evidence,self.type_mappings,self.row_mappings,self.evidence.view(),self.value_records,self.record_layouts,self.field_names,proofs}; }
fn view(self: const Snapshot&) -> View { return View {self.owner_id,self.code_origins,self.values,self.children,self.closures,self.value_evidence,self.type_mappings,self.row_mappings,self.evidence.view(),self.value_records,self.record_layouts,self.field_names,self.implementation_proofs.view()}; }
fn findRecordShape(self: const Store&,names: const u32[:]) -> u32,bool {
 let bucket=self.record_shapes.get(namesHash(names)); var candidate: u32=0; if bucket { candidate=bucket; }
 while candidate!=0 { let span=self.record_layouts[candidate]; if self.field_names[span.start..span.start+span.len]==names { return candidate,true; } candidate=self.record_shape_next[candidate]; } return 0,false;
}
fn saveRecordShape(self: Store&,names: const u32[:]) -> u32 {
 let existing,found=findRecordShape(self,names); if found { return existing; } var stable: u32[>..]=[]; stable.append(names); let hash=namesHash(stable); var previous: u32=0; let bucket=self.record_shapes.get(hash); if bucket { previous=bucket; }
 let id=self.record_layouts.len as u32; self.record_layouts.push(blot_check_core::List {self.field_names.len as u32,stable.len as u32}); self.field_names.append(stable); self.record_shape_next.push(previous); self.record_shapes.insert(hash,id); return id;
}
struct SnapshotTables { code_origins: blot_check_staging_origins::Record[>..]&,values: ValueInfo[>..]&,children: ValueId[>..]&,closures: ClosureValue[>..]&,value_evidence: u32[>..]&,type_mappings: blot_eval_type_evidence::Mapping[>..]&,row_mappings: blot_eval_type_evidence::RowMapping[>..]&,value_records: u32[>..]&,record_layouts: blot_check_core::List[>..]&,field_names: u32[>..]&,evidence: blot_eval_type_evidence::SnapshotTables,implementation_proofs: blot_eval_implementation_evidence::SnapshotTables }
fn copySnapshot(self: const Store&,proofs: const blot_eval_implementation_evidence::Store&,target: SnapshotTables) -> Snapshot,Error {
 let co=target.code_origins.len; let va=target.values.len; let ch=target.children.len; let cl=target.closures.len; let ve=target.value_evidence.len; let tm=target.type_mappings.len; let rm=target.row_mappings.len; let vr=target.value_records.len; let rl=target.record_layouts.len; let fnames=target.field_names.len;
 target.code_origins.append(self.code_origins); target.values.append(self.values); target.children.append(self.children); target.closures.append(self.closures); target.value_evidence.append(self.value_evidence); target.type_mappings.append(self.type_mappings); target.row_mappings.append(self.row_mappings); target.value_records.append(self.value_records); target.record_layouts.append(self.record_layouts); target.field_names.append(self.field_names);
 let selected,e=proofs.copyOwned(target.implementation_proofs); if e!=Error.none { return default<Snapshot>(),e; } let evidence,error=self.evidence.copyOwned(target.evidence); if error!=Error.none { return default<Snapshot>(),error; }
 return Snapshot {code_origins:target.code_origins[co..],values:target.values[va..],children:target.children[ch..],closures:target.closures[cl..],value_evidence:target.value_evidence[ve..],type_mappings:target.type_mappings[tm..],row_mappings:target.row_mappings[rm..],evidence:evidence,value_records:target.value_records[vr..],record_layouts:target.record_layouts[rl..],field_names:target.field_names[fnames..],implementation_proofs:selected},Error.none;
}

fn valueKindCode(value: ValueKind) -> u8 { match value { scalar=>0,product=>1,record=>2,nominal=>3,array=>4,list=>5,closure=>6,type_constructor=>7,resolver=>8,provider=>9,state_provider=>10,effect_set=>11,effect_descriptor=>12,computation=>13,request_decision=>14,cursor=>15,proof=>16,package=>17,code=>18,descriptor=>19,staged_value=>20,capability=>21 } }

fn closureOriginCode(value: ClosureOrigin) -> u8 { match value { named=>0,anonymous=>1,constructor=>2,primitive=>3,operation=>4 } }
fn deinit(self: Store&) { self.values.clear(); self.children.clear(); self.collection_buffers.buffers.clear(); self.closures.clear(); self.code_origins.clear(); self.value_evidence.clear(); self.type_mappings.clear(); self.row_mappings.clear(); self.evidence.deinit(); self.typed_views.clear(); self.specialized_closures.clear(); self.value_records.clear(); self.record_layouts.clear(); self.field_names.clear(); self.record_types.clear(); self.record_shapes.clear(); self.record_shape_next.clear(); self.owner_id=0; }
fn reset(self: Store&) -> Error { deinit(self); let semantic,error=blot_eval_type_evidence::init(); if error!=Error.none { return error; } self.evidence=semantic; self.collection_buffers.owner_id=blot_native::fresh_owner_id(); self.collection_buffers.mutation_serial=0; self.owner_id=blot_native::fresh_owner_id(); self.values.push(ValueInfo {}); self.value_evidence.push(1); self.value_records.push(0); self.record_layouts.push(blot_check_core::List {}); self.record_shape_next.push(0); return Error.none; }
