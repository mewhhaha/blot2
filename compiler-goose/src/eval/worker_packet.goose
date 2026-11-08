// Concrete copied-worker wire helpers. No reference or semantic lease crosses queues.
namespace blot_eval_worker_packet;
import reuse.principal_interface;

import backend.runtime_identity;
import check.check_packet_owner;
import check.core;
import check.effect_evidence;
import check.frozen_core_scopes;
import eval.core_eval;
import eval.implementation_evidence;
import eval.instance_arguments;
import eval.type_evidence;
import reuse.code_artifacts;
import reuse.dependency_certificate;
import reuse.independent_worker;
import support.bytes;
import support.core_packet;
import support.error;
import support.evidence_packet;
import support.native;
import support.option;

import dictionary;
import .eval_values;
import check.frozen_core_validation;
import reuse.independent_call_proof;
type Error=blot_error::Error;
let limit: i64=67108864;
let elements: i64=4194304;
struct Writer { data: u8[>..]&,failure: Error=blot_error::Error.none }
struct Reader { data: const u8[:],at: i64=0,failure: Error=blot_error::Error.none,total: i64=0 }
fn reserve(w: Writer&,count: i64) -> bool { if w.failure!=blot_error::Error.none { return false; } if count<0||w.data.len>limit||count>limit-w.data.len { w.failure=blot_error::Error.artifact_limit; return false; } return true; }
fn put(w: Writer&,value: u8) { if reserve(w,1) { w.data.push(value); } }
fn put(w: Writer&,value: bool) { var byte: u8=0; if value { byte=1; } put(w,byte); }
fn put(w: Writer&,value: u32) { if reserve(w,4) { for shift in 0..4 { w.data.push((value>>((shift*8) as u32)) as! u8); } } }
fn put(w: Writer&,value: u64) { if reserve(w,8) { for shift in 0..8 { w.data.push((value>>((shift*8) as u32)) as! u8); } } }
fn put(w: Writer&,value: i64) { put(w,value as! u64); }
fn put<T>(w: Writer&,value: blot_support::Option<T>) { put(w,value.present); if value.present { put(w,value.value); } }
fn putRecord<T>(w: Writer&,value: T) { const for <N,A> in fields<T> { put(w,value.A); } }
fn available(r: Reader&,count: i64) -> bool { if r.failure!=blot_error::Error.none { return false; } if count<0||r.at<0||r.at>r.data.len||count>r.data.len-r.at { r.failure=blot_error::Error.invalid_artifact; return false; } return true; }
fn get(r: Reader&,out: u8&) { if !available(r,1) { return; } out=r.data[r.at]; r.at++; }
fn get(r: Reader&,out: bool&) { var byte: u8=0; get(r,byte); if byte>1 { r.failure=blot_error::Error.invalid_artifact; return; } out=byte==1; }
fn get(r: Reader&,out: u32&) { if !available(r,4) { return; } out=blot_bytes::get_u32(r.data,r.at); r.at+=4; }
fn get(r: Reader&,out: u64&) { if !available(r,8) { return; } out=blot_bytes::get_u64(r.data,r.at); r.at+=8; }
fn get(r: Reader&,out: i64&) { var bits: u64=0; get(r,bits); out=bits as! i64; }
fn get<T>(r: Reader&,out: blot_support::Option<T>&) { get(r,out.present); if out.present { get(r,out.value); } }
fn getRecord<T>(r: Reader&,out: T&) { const for <N,A> in fields<T> { get(r,out.A); } }
fn count(w: Writer&,length: i64) { if length<0||length>elements { w.failure=blot_error::Error.artifact_limit; return; } put(w,length as u32); }
fn count(r: Reader&,width: i64) -> i64 { var value: u32=0; get(r,value); if r.failure!=blot_error::Error.none { return 0; } let length=value as i64; if length>elements||r.total>elements-length||width<=0||length>(r.data.len-r.at)/width { r.failure=blot_error::Error.artifact_limit; return 0; } r.total+=length; return length; }
fn blob(w: Writer&,bytes: const u8[:]) { if !reserve(w,8+bytes.len) { return; } put(w,bytes.len as u64); w.data.append(bytes); }
fn blob(r: Reader&) -> const u8[:] { var length: u64=0; get(r,length); if r.failure!=blot_error::Error.none { return default<const u8[:]>(); } if length>limit as u64||!available(r,length as i64) { r.failure=blot_error::Error.artifact_limit; return default<const u8[:]>(); } let start=r.at; r.at+=length as i64; return r.data[start..r.at]; }
struct Catalog { owners: blot_core_packet::Owned[:]=default<blot_core_packet::Owned[:]>(),modules: blot_check_core::Module[:]=default<blot_check_core::Module[:]>(),refs: blot_check_frozen_core_validation::ModuleRef[:]=default<blot_check_frozen_core_validation::ModuleRef[:]>() }
reusable[] var core_owners: blot_core_packet::Owned[>..]=[];
reusable[] var core_modules: blot_check_core::Module[>..]=[];
reusable[] var core_refs: blot_check_frozen_core_validation::ModuleRef[>..]=[];
fn deinit(catalog: Catalog&) { for &owner in catalog.owners { if owner.lease!=0 { owner.deinit(); } } core_owners.free_slice(catalog.owners); core_refs.free_slice(catalog.refs); core_modules.free_slice(catalog.modules); catalog=Catalog {}; }
fn writeCatalog(w: Writer&,modules: const blot_check_core::Module[:]) { count(w,modules.len); for module in modules { var packet: u8[>..<]=[]; let error=blot_core_packet::encode(module,packet); if error!=blot_error::Error.none { w.failure=error; return; } blob(w,packet); if w.failure!=blot_error::Error.none { return; } } }
fn readCatalog(r: Reader&) -> Catalog { let length=count(r,8); if r.failure!=blot_error::Error.none { return Catalog {}; } var catalog=Catalog {owners:core_owners.alloc_slice(length),modules:core_modules.alloc_slice(length),refs:core_refs.alloc_slice(length)}; for &owner in catalog.owners { owner=default<blot_core_packet::Owned>(); } for index in 0..length { let packet=blob(r); if r.failure!=blot_error::Error.none { deinit(catalog); return Catalog {}; } let owner,error=blot_core_packet::decode(packet); if error!=blot_error::Error.none { r.failure=error; deinit(catalog); return Catalog {}; } catalog.owners[index]=owner; catalog.modules[index]=owner.module; } for &module,index in catalog.modules { catalog.refs[index]=blot_check_frozen_core_validation::ModuleRef {value:module}; } return catalog; }
fn validate(catalog: const Catalog&,symbols: blot_support::Option<i64>) -> Error { var spawn=false; for module in catalog.modules { spawn=spawn||blot_check_frozen_core_validation::moduleHasSpawnContracts(module); } let context=blot_check_frozen_core_validation::Context {units:catalog.refs,symbol_count:symbols,source_length:blot_support::none<u32>(),forbidden_owner:blot_support::none<u32>()}; let batch=blot_check_frozen_core_validation::Batch {context,spawn}; var remaining: i64=0x7fffffffffffffff; for module in catalog.modules { let error=batch.validateWithBudget(module,blot_support::none<u32>(),remaining); if error!=blot_error::Error.none { return error; } } return blot_error::Error.none; }
struct Identity { bytes: u8[:]=default<u8[:]>(),symbols: blot_backend_runtime_identity::Name[:]=default<blot_backend_runtime_identity::Name[:]>(),owners: blot_backend_runtime_identity::Name[:]=default<blot_backend_runtime_identity::Name[:]>() }
reusable[] var identity_bytes: u8[>..]=[];
reusable[] var identity_names: blot_backend_runtime_identity::Name[>..]=[];
fn view(identity: const Identity&) -> blot_backend_runtime_identity::View { return blot_backend_runtime_identity::View {identity.bytes,identity.symbols,identity.owners}; }
fn metadata(identity: const Identity&) -> blot_reuse_code_artifacts::IdentityMetadata { return blot_reuse_code_artifacts::IdentityMetadata {identity.bytes,identity.symbols,identity.owners}; }
fn deinit(identity: Identity&) { identity_bytes.free_slice(identity.bytes); identity_names.free_slice(identity.symbols); identity_names.free_slice(identity.owners); identity=Identity {}; }
fn writeIdentity(w: Writer&,identity: blot_backend_runtime_identity::View) { blob(w,identity.bytes); count(w,identity.symbols.len); for name in identity.symbols { put(w,name); } count(w,identity.owners.len); for owner in identity.owners { put(w,owner); } }
fn readIdentity(r: Reader&) -> Identity { var identity=Identity {}; let bytes=blob(r); if r.failure!=blot_error::Error.none { return identity; } identity.bytes=identity_bytes.alloc_slice(bytes.len); for byte,index in bytes { identity.bytes[index]=byte; } let symbol_count=count(r,8); if r.failure!=blot_error::Error.none { deinit(identity); return Identity {}; } identity.symbols=identity_names.alloc_slice(symbol_count); for &name in identity.symbols { get(r,name); if name.start>identity.bytes.len||name.len>identity.bytes.len-name.start { r.failure=blot_error::Error.invalid_identity; } } let owner_count=count(r,8); if r.failure!=blot_error::Error.none { deinit(identity); return Identity {}; } identity.owners=identity_names.alloc_slice(owner_count); for &name in identity.owners { get(r,name); if name.start>identity.bytes.len||name.len>identity.bytes.len-name.start { r.failure=blot_error::Error.invalid_identity; } } if r.failure!=blot_error::Error.none { deinit(identity); return Identity {}; } return identity; }
fn writeEvidence(w: Writer&,view: blot_eval_type_evidence::View) { var bytes: u8[>..<]=[]; let error=blot_evidence_packet::encode(view,bytes); if error!=blot_error::Error.none { w.failure=error; return; } blob(w,bytes); }
fn readEvidence(r: Reader&) -> blot_evidence_packet::OwnedSnapshot { let bytes=blob(r); if r.failure!=blot_error::Error.none { return blot_evidence_packet::OwnedSnapshot {snapshot:blot_evidence_packet::emptySnapshot()}; } let snapshot,error=blot_evidence_packet::decode(bytes); if error!=blot_error::Error.none { r.failure=error; } return snapshot; }
struct ScalarSeed { target: blot_check_core::BindingRef,value: blot_eval_core_eval::Value }
reusable[] var scalar_seeds: ScalarSeed[>..]=[];
fn writeSeeds(w: Writer&,session: const blot_eval_core_eval::Session&) { var length=0; for module,owner in session.units { let start=session.binding_offsets[owner]; for slot,index in session.slots[start..start+module.bindings.len] { if slot.state!=blot_eval_core_eval::State.complete||module.bindings[index].kind!=blot_reuse_principal_interface::Kind.global { continue; } let body=module.body(index as u32); if body==null||body.runtime { continue; } let scalar=session.valueScalar(slot.value); if !scalar.present { continue; } let evidence=session.valueEvidence(slot.value); if (scalar.value.scalar==0&&evidence==1)||(scalar.value.scalar==2&&evidence==2)||(scalar.value.scalar==1&&evidence==3)||(scalar.value.scalar==3&&evidence==4) { length++; } } } count(w,length); for module,owner in session.units { let start=session.binding_offsets[owner]; for slot,index in session.slots[start..start+module.bindings.len] { if slot.state!=blot_eval_core_eval::State.complete||module.bindings[index].kind!=blot_reuse_principal_interface::Kind.global { continue; } let body=module.body(index as u32); if body==null||body.runtime { continue; } let scalar=session.valueScalar(slot.value); if !scalar.present { continue; } let evidence=session.valueEvidence(slot.value); if (scalar.value.scalar==0&&evidence==1)||(scalar.value.scalar==2&&evidence==2)||(scalar.value.scalar==1&&evidence==3)||(scalar.value.scalar==3&&evidence==4) { put(w,ScalarSeed {blot_check_core::BindingRef {session.unitId(owner),index as u32},scalar.value}); } } } }
fn readSeeds(r: Reader&) -> ScalarSeed[:] { let length=count(r,13); if r.failure!=blot_error::Error.none { return default<ScalarSeed[:]>(); } let seeds=scalar_seeds.alloc_slice(length); for &seed in seeds { get(r,seed); } return seeds; }
fn seed(session: blot_eval_core_eval::Session&,seeds: const ScalarSeed[:]) -> Error { for seed in seeds { let owner=session.unitIndex(seed.target.unit); if !owner.present||seed.target.binding==0||seed.target.binding>=session.units[owner.value].bindings.len { return blot_error::Error.invalid_artifact; } let module=session.units[owner.value]; let body=module.body(seed.target.binding); if body==null||body.runtime||module.bindings[seed.target.binding].kind!=blot_reuse_principal_interface::Kind.global||seed.value.scalar>3 { return blot_error::Error.invalid_artifact; } let value,error=session.makeScalar(owner.value,body.root,seed.value); if error!=blot_error::Error.none { return error; } session.slots[session.binding_offsets[owner.value]+seed.target.binding]=blot_eval_core_eval::Slot {state:blot_eval_core_eval::State.complete,value:value}; } return blot_error::Error.none; }
import check.check;
import .semantic_parallel;
fn put(w: Writer&,values: i64[15]) { for value in values { put(w,value); } }
fn get(r: Reader&,values: i64[15]&) { for &value in values { get(r,value); } }
fn writeCatalog(w: Writer&,modules: const blot_reuse_code_artifacts::ModulePin[:]) { count(w,modules.len); for pin in modules { var packet: u8[>..<]=[]; let error=blot_core_packet::encode(pin.module,packet); if error!=blot_error::Error.none { w.failure=error; return; } blob(w,packet); if w.failure!=blot_error::Error.none { return; } } }
reusable[] var pins: blot_reuse_code_artifacts::ModulePin[>..]=[];
fn pin(catalog: const Catalog&,identity: const Identity&) -> blot_reuse_code_artifacts::ModulePin[:],Error { let result=pins.alloc_slice(catalog.modules.len); for &module,index in catalog.modules { let path=view(identity).owner((index+1) as u32); if !path.present { pins.free_slice(result); return default<blot_reuse_code_artifacts::ModulePin[:]>(),blot_error::Error.invalid_identity; } result[index]=blot_reuse_code_artifacts::validated((index+1) as u32,module,path.value); } return result,blot_error::Error.none; }
fn writeRecord(w: Writer&,record: blot_reuse_independent_call_proof::Record) { put(w,record.target); put(w,record.evidence); put(w,record.options); put(w,record.depth); count(w,record.sources.len); for source in record.sources { put(w,source); } count(w,record.scalar_reads.len); for scalar in record.scalar_reads { put(w,scalar); } }
fn readRecord(r: Reader&) -> blot_reuse_independent_call_proof::Record { var result=default<blot_reuse_independent_call_proof::Record>(); get(r,result.target); get(r,result.evidence); get(r,result.options); get(r,result.depth); let source_count=count(r,8); if r.failure!=blot_error::Error.none { return result; } var sources: blot_check_core::BindingRef[>..<]=[]; for index in 0..source_count { var source=blot_check_core::BindingRef {0,0}; get(r,source); sources.push(source); } let scalar_count=count(r,13); if r.failure!=blot_error::Error.none { return result; } var scalars: blot_reuse_independent_call_proof::ScalarInput[>..<]=[]; for index in 0..scalar_count { var input=default<blot_reuse_independent_call_proof::ScalarInput>(); get(r,input); if input.evidence>4 { r.failure=blot_error::Error.invalid_artifact; } if input.value.present&&input.value.value.scalar>3 { r.failure=blot_error::Error.invalid_artifact; } scalars.push(input); } if r.failure!=blot_error::Error.none { return result; } result.sources=blot_reuse_independent_call_proof::copySources(sources); result.scalar_reads=blot_reuse_independent_call_proof::copyScalars(scalars); return result; }
reusable[] var proof_records: blot_reuse_independent_call_proof::Record[>..]=[];
fn writeRecords(w: Writer&,records: const blot_reuse_independent_call_proof::Record[:]) { count(w,records.len); for record in records { writeRecord(w,record); } }
fn readRecords(r: Reader&) -> blot_reuse_independent_call_proof::Record[:] { let length=count(r,16); if r.failure!=blot_error::Error.none { return default<blot_reuse_independent_call_proof::Record[:]>(); } let records=proof_records.alloc_slice(length); for &record in records { record=default<blot_reuse_independent_call_proof::Record>(); } for &record in records { record=readRecord(r); if r.failure!=blot_error::Error.none { releaseRecords(records); return default<blot_reuse_independent_call_proof::Record[:]>(); } } return records; }
fn releaseRecords(records: blot_reuse_independent_call_proof::Record[:]) { for &record in records { record.deinit(); } proof_records.free_slice(records); }
fn semanticPools(identity: const Identity&,module_pins: const blot_reuse_code_artifacts::ModulePin[:],evidence: const blot_evidence_packet::OwnedSnapshot&) -> blot_reuse_code_artifacts::Pools { let empty_effects=blot_check_effect_evidence::Snapshot {owner_id:0,..}; let evaluator=blot_eval_core_eval::Snapshot {owner_id:blot_native::fresh_owner_id(),evidence:evidence.snapshot,implementation_proofs:blot_eval_implementation_evidence::Snapshot {},..}; return blot_reuse_code_artifacts::Pools {project_identity:true,identity:blot_support::some(metadata(identity)),modules:module_pins,dependency_certificate:blot_support::none<blot_reuse_dependency_certificate::Certificate>(),layouts:blot_reuse_code_artifacts::Layouts {effects:empty_effects,..},evaluator:evaluator,rows:blot_reuse_code_artifacts::Substitutions {},templates:blot_reuse_code_artifacts::Substitutions {},static_values:blot_reuse_code_artifacts::Substitutions {},instance_arguments:blot_eval_instance_arguments::Owned {},bridge:blot_support::none<blot_reuse_code_artifacts::Bridge>(),field_locations_stamp:[0;32],operations_finalized:false,evaluator_steps:0,evaluator_demanded:0,evaluator_traced_bodies:0,evaluator_traced_nodes:0,..}; }

fn get(r:Reader&,out:blot_backend_runtime_identity::Name&) {getRecord(r,out);}
fn put(w:Writer&,value:blot_backend_runtime_identity::Name) {putRecord(w,value);}

fn get(r:Reader&,out:ScalarSeed&) {getRecord(r,out);}
fn put(w:Writer&,value:ScalarSeed) {putRecord(w,value);}

fn get(r:Reader&,out:blot_check_core::BindingRef&) {getRecord(r,out);}
fn put(w:Writer&,value:blot_check_core::BindingRef) {putRecord(w,value);}

fn get(r:Reader&,out:blot_eval_core_eval::Value&) {getRecord(r,out);}
fn put(w:Writer&,value:blot_eval_core_eval::Value) {putRecord(w,value);}

fn get(r:Reader&,out:blot_eval_core_eval::Options&) {getRecord(r,out);}
fn put(w:Writer&,value:blot_eval_core_eval::Options) {putRecord(w,value);}

fn get(r:Reader&,out:blot_reuse_independent_call_proof::ScalarInput&) {getRecord(r,out);}
fn put(w:Writer&,value:blot_reuse_independent_call_proof::ScalarInput) {putRecord(w,value);}
