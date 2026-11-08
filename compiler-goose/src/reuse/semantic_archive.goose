// Source-free previous semantic owner; current Gate/Importer re-admit receipts.
namespace blot_reuse_semantic_archive;
import dictionary;
import check.core;
import check.types;
import check.frozen_core_validation;
import check.staging_snapshot;
import eval.core_eval;
import eval.eval_values;
import eval.type_evidence;
import eval.implementation_evidence;
import eval.selected_implementation_admission;
import eval.selected_query;
import eval.pool_leases;
import reuse.code_artifacts;
import reuse.artifact_capture;
import reuse.specialization_receipt;
import reuse.portable_query;
import reuse.dependency_format;
import reuse.source_overlays;
import backend.runtime_identity;
import support.error;
import support.option;
import support.pooled_buffer;
import support.pooled_map;
type Error=blot_error::Error;
type Digest=blot_reuse_dependency_format::Digest;
type Core=blot_check_core::Module;
type Capture=blot_reuse_artifact_capture::Capture;
struct Unit {unit:u32,canonical_path:const u8[:],stamp:Digest,certificates:const u32[:],core:Core}
struct RecordKey {input:u32,expected:u32,options:blot_eval_core_eval::Options,depth:i64}
struct Dependencies {values_before:i64,children_before:i64,values_added:i64,children_added:i64,collected:i64,source_scopes:i64,solver_nodes:i64,sources:const blot_check_core::BindingRef[:],scalar_reads:const blot_reuse_specialization_receipt::ScalarRead[:],call_reads:const blot_reuse_specialization_receipt::CallRead[:],call_publications:const blot_reuse_specialization_receipt::CallRead[:],views:const blot_reuse_specialization_receipt::ViewEffect[:],plain_facts:const blot_reuse_specialization_receipt::PlainFact[:]}
struct RecordResult {selected:u32}
struct Record {key:RecordKey,dependencies:Dependencies,result:RecordResult}
struct Section {header:blot_reuse_portable_query::Header,records:const Record[:]}
let claim=blot_reuse_portable_query::Claim.selected_complete_proof;
fn admitted(self_:Section)->bool {return self_.header==blot_reuse_portable_query::header(claim);}
struct Snapshot {identity:blot_reuse_code_artifacts::IdentityMetadata,units:const Unit[:],evaluator:blot_eval_core_eval::Snapshot,slots:const blot_reuse_code_artifacts::Slot[:],field_locations:const blot_reuse_code_artifacts::FieldLocation[:],queries:Section}
let limits=blot_reuse_dependency_format::Limits{elements:67108864};
fn wireKey(compiler:Digest)->blot_reuse_dependency_format::Key {return blot_reuse_dependency_format::Key{compiler,blot_reuse_dependency_format::digest("blot-semantic-archive-v3:selected-implementations"),[0;32],[0;32]};}
fn encode(compiler:Digest,source:const Capture&)->blot_support::Option<u8[:]>,Error {return encodeWithDigests(compiler,source,blot_support::none<const Digest[:]>(),null);}
fn encodeWithDigests(compiler:Digest,source:const Capture&,digests:blot_support::Option<const Digest[:]>,over_limit:bool?=null)->blot_support::Option<u8[:]>,Error {
 if !source.metadata.pools.present {return blot_support::none<u8[:]>(),blot_error::Error.none;}let pools=source.metadata.pools.value;if digests.present && digests.value.len!=pools.modules.len {return blot_support::none<u8[:]>(),blot_error::Error.invalid_artifact;}if !pools.identity.present || !pools.project_identity || pools.modules.len==0 {return blot_support::none<u8[:]>(),blot_error::Error.none;}
 var complete=false;for query in source.metadata.specialization_queries.records {if !query.dependencies.member.present && blot_eval_selected_query::complete(blot_eval_selected_query::Adapter{},query) {complete=true;break;}}if !complete {return blot_support::none<u8[:]>(),blot_error::Error.none;}
 var units:Unit[>..]=[];
 // Certificate words occupy separate stable runs while unit descriptors grow.
 var words:const u32[:][>..]=[];
 for pin,index in pools.modules {let nodes=pin.module.types.nodes;var saved:const u32[:]=default<const u32[:]>();for node in nodes {if node.closed_height!=0 || node.closed_generation!=0 {let owned=certificate_pool.alloc_slice(nodes.len);for node,ordinal in nodes {owned[ordinal]=(node.closed_height as u32)|((node.closed_generation as u32)<<8);}saved=owned;words.push(saved);break;}}var stamp=pin.stamp;if digests.present {stamp=blot_support::some(digests.value[index]);}else if !stamp.present {stamp=blot_support::some(blot_reuse_code_artifacts::stamp(pin.module));}units.push(Unit{pin.unit,pin.canonical_path,stamp.value,saved,pin.module});}
 var records:Record[>..]=[];for query in source.metadata.specialization_queries.records {let proof=query.dependencies;if proof.member.present || !blot_eval_selected_query::complete(blot_eval_selected_query::Adapter{},query) {continue;}records.push(Record{RecordKey{proof.input,proof.expected,proof.options,proof.depth},Dependencies{proof.values_before,proof.children_before,proof.values_added,proof.children_added,proof.collected,proof.source_scopes,proof.solver_nodes,proof.sources,proof.scalar_reads,proof.call_reads,proof.call_publications,proof.views,proof.plain_facts},RecordResult{proof.selected}});}
 let snapshot=Snapshot{pools.identity.value,units[..],pools.evaluator,pools.slots,pools.field_locations,Section{blot_reuse_portable_query::header(claim),records[..]}};
 let staged=blot_check_staging_snapshot::validate(snapshot.evaluator,units[..]);if staged==blot_error::Error.out_of_memory {let __cleanup_result_1_0: blot_support::Option<u8[:]> = blot_support::none<u8[:]>(); let __cleanup_result_1_1: Error = staged; {for word in words {if word.len!=0 {certificate_pool.free_slice(word);}}} {} return __cleanup_result_1_0, __cleanup_result_1_1;}if staged!=blot_error::Error.none {let __cleanup_result_2_0: blot_support::Option<u8[:]> = blot_support::none<u8[:]>(); let __cleanup_result_2_1: Error = blot_error::Error.none; {for word in words {if word.len!=0 {certificate_pool.free_slice(word);}}} {} return __cleanup_result_2_0, __cleanup_result_2_1;}
 let bytes,error=blot_reuse_dependency_format::encodeWithLimits(wireKey(compiler),snapshot,limits);if error==blot_error::Error.artifact_limit {if over_limit {over_limit=true;}let __cleanup_result_3_0: blot_support::Option<u8[:]> = blot_support::none<u8[:]>(); let __cleanup_result_3_1: Error = blot_error::Error.none; {for word in words {if word.len!=0 {certificate_pool.free_slice(word);}}} {} return __cleanup_result_3_0, __cleanup_result_3_1;}if error!=blot_error::Error.none {let __cleanup_result_4_0: blot_support::Option<u8[:]> = blot_support::none<u8[:]>(); let __cleanup_result_4_1: Error = error; {for word in words {if word.len!=0 {certificate_pool.free_slice(word);}}} {} return __cleanup_result_4_0, __cleanup_result_4_1;}let __cleanup_result_5_0: blot_support::Option<u8[:]> = blot_support::some(bytes); let __cleanup_result_5_1: Error = blot_error::Error.none; {for word in words {if word.len!=0 {certificate_pool.free_slice(word);}}} {} return __cleanup_result_5_0, __cleanup_result_5_1;
 {for word in words {if word.len!=0 {certificate_pool.free_slice(word);}}} {} }
reusable[] var certificate_pool:u32[>..]=[];
fn require(value:bool)->Error {if !value {return blot_error::Error.invalid_artifact;}return blot_error::Error.none;}
fn validSpan(length:i64,start:i64,count:i64)->bool {return start<=length && count<=length-start;}
fn validBinding(units:const Unit[:],target:blot_check_core::BindingRef)->bool {return target.unit!=0 && target.unit<=units.len && target.binding!=0 && target.binding<units[target.unit-1].core.bindings.len;}
fn restoreCertificates<O>(owner:O&,unit:Unit&)->Error {if unit.certificates.len==0 {return blot_error::Error.none;}if unit.certificates.len!=unit.core.types.nodes.len {return blot_error::Error.invalid_artifact;}let nodes=owner.mutable(unit.core.types.nodes);for word,index in unit.certificates {if word>>24!=0 {return blot_error::Error.invalid_artifact;}nodes[index].closed_height=word as! u8;nodes[index].closed_generation=(word>>8) as! u16;}return blot_error::Error.none;}
fn validate(snapshot:const Snapshot&)->Error {
 let section=snapshot.queries;if section.header.version!=blot_reuse_portable_query::version {return blot_error::Error.unsupported_version;}if !section.admitted() {return blot_error::Error.schema_mismatch;}let units=snapshot.units;let names=snapshot.identity.view();
 if units.len==0 || units.len>=0xffffffff || names.owners.len!=units.len || names.symbols.len==0 || names.symbols.len>0xffffffff {return blot_error::Error.invalid_artifact;}for id in 1..names.symbols.len {if !names.symbol(id as u32).present {return blot_error::Error.invalid_artifact;}}
 var paths:dictionary<const u8[:],bool> =dictionary<const u8[:],bool>{};var views:blot_check_frozen_core_validation::ModuleRef[>..]=[];var bindings:i64=0;
 for &unit,index in units {let id=(index+1) as u32;if unit.unit!=id || unit.core.unit!=id {return blot_error::Error.invalid_artifact;}let path=names.owner(id);if !path.present || path.value.len==0 || path.value!=unit.canonical_path || !blot_reuse_source_overlays::utf8_valid(path.value) {return blot_error::Error.invalid_artifact;}for byte in path.value {if byte==0 {return blot_error::Error.invalid_artifact;}}if paths.contains(path.value) {return blot_error::Error.invalid_artifact;}paths.insert(path.value,true);views.push(blot_check_frozen_core_validation::ModuleRef{unit.core});if unit.core.bindings.len>0x7fffffffffffffff-bindings {return blot_error::Error.invalid_artifact;}bindings+=unit.core.bindings.len;}
 for unit in units {let error=blot_check_frozen_core_validation::validate(unit.core,blot_check_frozen_core_validation::Context{units:views[..],symbol_count:blot_support::some(names.symbols.len),..});if error==blot_error::Error.out_of_memory {return error;}if error!=blot_error::Error.none {return blot_error::Error.invalid_artifact;}}
 let error=validEvaluator(snapshot.evaluator,units.len);if error!=blot_error::Error.none {return error;}let error=blot_check_staging_snapshot::validate(snapshot.evaluator,units);if error!=blot_error::Error.none {return error;}
 if snapshot.evaluator.implementation_proofs.proofs.len!=0 {var modules:Core[>..<]=[];for unit in units {modules.push(unit.core);}var remaining:i64=1000000;let error=blot_eval_selected_implementation_admission::snapshot(modules[..],snapshot.evaluator.evidence.view(),snapshot.evaluator.implementation_proofs.view(),remaining);if error!=blot_error::Error.none {return error;}}
 if snapshot.slots.len!=bindings {return blot_error::Error.invalid_artifact;}for slot in snapshot.slots {if slot.value>=snapshot.evaluator.values.len {return blot_error::Error.invalid_artifact;}}
 for field in snapshot.field_locations {let unit=field.family>>32;if (unit!=0xffffffff && (unit==0 || unit>units.len)) || field.name>=names.symbols.len {return blot_error::Error.invalid_artifact;}}
 for record in section.records {let error=validRecord(record,snapshot);if error!=blot_error::Error.none {return error;}}return blot_error::Error.none;
}
fn validEvaluator(snapshot:const blot_eval_core_eval::Snapshot&,units:i64)->Error {
 let values=snapshot.values.len;let nodes=snapshot.evidence.nodes.len;if !blot_reuse_portable_query::validEvidence(snapshot.evidence.view()) || values==0 || snapshot.value_evidence.len!=values || snapshot.value_records.len!=values {return blot_error::Error.invalid_artifact;}
 for value in snapshot.values {if !validSpan(snapshot.children.len,value.start,value.len) || (value.kind==blot_eval_eval_values::ValueKind.closure && value.bits>=snapshot.closures.len) {return blot_error::Error.invalid_artifact;}}
 for child in snapshot.children {if child>=values {return blot_error::Error.invalid_artifact;}}for closure in snapshot.closures {if closure.unit>units || !validSpan(snapshot.type_mappings.len,closure.mappings.start,closure.mappings.len) || !validSpan(snapshot.row_mappings.len,closure.row_mappings.start,closure.row_mappings.len) {return blot_error::Error.invalid_artifact;}}
 for id in snapshot.value_evidence {if id>=nodes || (id!=0 && !blot_reuse_portable_query::closedEvidence(snapshot.evidence.view(),id)) {return blot_error::Error.invalid_artifact;}}
 for mapping in snapshot.type_mappings {if mapping.evidence>=nodes || !blot_reuse_portable_query::closedEvidence(snapshot.evidence.view(),mapping.evidence) {return blot_error::Error.invalid_artifact;}}for mapping in snapshot.row_mappings {if mapping.evidence>=snapshot.evidence.effects.rows.len {return blot_error::Error.invalid_artifact;}}
 for record in snapshot.value_records {if record>=snapshot.record_layouts.len {return blot_error::Error.invalid_artifact;}}for layout in snapshot.record_layouts {if !validSpan(snapshot.field_names.len,layout.start,layout.len) {return blot_error::Error.invalid_artifact;}}
 let proofs=snapshot.implementation_proofs;for root in proofs.arguments {if root==0 || root>=nodes {return blot_error::Error.invalid_artifact;}}for member in proofs.members {if member.root==0 || member.root>=nodes || member.target.unit>units {return blot_error::Error.invalid_artifact;}}
 for proof,ordinal in proofs.proofs {if proof.context==0 || proof.context>units || proof.implementation.unit>units || proof.contract.unit>units || !validSpan(proofs.arguments.len,proof.arguments.start,proof.arguments.len) || !validSpan(proofs.members.len,proof.members.start,proof.members.len) || !validSpan(proofs.edges.len,proof.prerequisites.start,proof.prerequisites.len) {return blot_error::Error.invalid_artifact;}for child in proofs.edges[proof.prerequisites.start..proof.prerequisites.start+proof.prerequisites.len] {if child>=ordinal {return blot_error::Error.invalid_artifact;}}for root in proof.predicate.operands {if root>=nodes {return blot_error::Error.invalid_artifact;}}if proof.predicate.target.unit>units {return blot_error::Error.invalid_artifact;}}
 return blot_error::Error.none;
}
fn validRecord(record:Record,snapshot:const Snapshot&)->Error {
 let evaluator=snapshot.evaluator;let values=evaluator.values.len;let nodes=evaluator.evidence.nodes.len;let key=record.key;let proof=record.dependencies;
 if key.input==0 || key.input>=values || evaluator.values[key.input].kind!=blot_eval_eval_values::ValueKind.closure || record.result.selected>=values || key.expected==0 || key.expected>=nodes || evaluator.evidence.nodes[key.expected].tag!=blot_eval_type_evidence::Tag.function || !blot_reuse_portable_query::closedEvidence(evaluator.evidence.view(),key.expected) {return blot_error::Error.invalid_artifact;}
 if proof.values_before>values || proof.values_added>values-proof.values_before || proof.children_before>evaluator.children.len || proof.children_added>evaluator.children.len-proof.children_before {return blot_error::Error.invalid_artifact;}
 for source in proof.sources {if !validBinding(snapshot.units,source) {return blot_error::Error.invalid_artifact;}}for read in proof.scalar_reads {if !validBinding(snapshot.units,read.target) || read.evidence>=nodes {return blot_error::Error.invalid_artifact;}}
 for calls in [proof.call_reads,proof.call_publications] {for call in calls {if !validBinding(snapshot.units,blot_check_core::BindingRef{call.unit,call.binding}) || call.evidence>=nodes {return blot_error::Error.invalid_artifact;}}}
 for view in proof.views {if view.value>=values || view.selected>=values || view.evidence>=nodes {return blot_error::Error.invalid_artifact;}}return blot_error::Error.none;
}
// The static factory owns canonical Context/Recorder/query tables. Its token is
// interpreted only by that concrete factory, never as a foreign pointer.
enum Archive<C> {inactive,live{units:const Unit[:],capture:Capture?,factory:C,token:u64,owner:blot_reuse_dependency_format::Owner}}
fn capture<C>(self_:Archive<C>)->Capture& {match self_ {inactive=>{abort("inactive semantic archive");},live payload=>{let capture .= payload.capture;assert(capture!=null);return capture;}}}
fn deinit<C>(self_:Archive<C>&) {match self_ {inactive=>{},live &payload=>{payload.factory.destroyArchiveCapture(payload.token);payload.owner.deinit();}}self_=Archive<C>.inactive {};}
fn decode<C>(factory:C&,compiler:Digest,bytes:const u8[:])->Archive<C>,Error {
 let decoded,error=blot_reuse_dependency_format::decodeWithLimits<Snapshot>(bytes,wireKey(compiler),limits);if error!=blot_error::Error.none {return Archive<C>.inactive {},error;}var snapshot=decoded;var moved=false;
 let units=snapshot.owner.mutable(snapshot.value.units);for &unit in units {let error=restoreCertificates(snapshot.owner,unit);if error!=blot_error::Error.none {let __cleanup_result_6_0: Archive<C> = Archive<C>.inactive {}; let __cleanup_result_6_1: Error = error; {if !moved {snapshot.deinit();}} return __cleanup_result_6_0, __cleanup_result_6_1;}}
 let error=validate(snapshot.value);if error!=blot_error::Error.none {let __cleanup_result_7_0: Archive<C> = Archive<C>.inactive {}; let __cleanup_result_7_1: Error = error; {if !moved {snapshot.deinit();}} return __cleanup_result_7_0, __cleanup_result_7_1;}let result,error=adopt(factory,snapshot);if error!=blot_error::Error.none {let __cleanup_result_8_0: Archive<C> = Archive<C>.inactive {}; let __cleanup_result_8_1: Error = error; {if !moved {snapshot.deinit();}} return __cleanup_result_8_0, __cleanup_result_8_1;}moved=true;let __cleanup_result_9_0: Archive<C> = result; let __cleanup_result_9_1: Error = blot_error::Error.none; {if !moved {snapshot.deinit();}} return __cleanup_result_9_0, __cleanup_result_9_1;
 {if !moved {snapshot.deinit();}} }
fn adopt<C>(factory:C&,snapshot:blot_reuse_dependency_format::Owned<Snapshot>&)->Archive<C>,Error {
 let capture,token,error=factory.createArchiveCapture();if error!=blot_error::Error.none {return Archive<C>.inactive {},error;}assert(capture!=null);var published=false;
 var pools=default<blot_reuse_code_artifacts::Pools>();var copying=blot_reuse_code_artifacts::CaptureState{shared:blot_eval_pool_leases::Builder{}};var pools_moved=false;
 pools.project_identity=true;let names=snapshot.value.identity;pools.identity=blot_support::some(blot_reuse_code_artifacts::IdentityMetadata{copying.capture_identity_bytes(names.bytes,[]),copying.capture_identity_symbols(names.symbols,[]),copying.capture_identity_owners(names.owners,[])});
 let pins=blot_reuse_code_artifacts::allocateOwned_pins(snapshot.value.units.len);pools.modules=pins;var offsets:i64[>..<]=[];var next:i64=0;
 for &unit,index in snapshot.value.units {pins[index]=blot_reuse_code_artifacts::init(unit.unit,unit.core,blot_reuse_code_artifacts::copyOwned(unit.canonical_path));pins[index].stamp=blot_support::some(unit.stamp);offsets.push(next);next+=unit.core.bindings.len;}
 pools.binding_offsets=copying.capture_binding_offsets(offsets[..],[]);pools.slots=copying.capture_slots(snapshot.value.slots,[]);pools.field_locations=copying.capture_field_locations(snapshot.value.field_locations,[]);pools.field_locations_stamp=blot_reuse_code_artifacts::stamp(snapshot.value.field_locations);
 let source=snapshot.value.evaluator;pools.evaluator.owner_id=source.owner_id;pools.evaluator.evidence.owner_id=source.evidence.owner_id;pools.evaluator.evidence.effects.owner_id=source.evidence.effects.owner_id;pools.evaluator.implementation_proofs.owner_id=source.implementation_proofs.owner_id;
 pools.evaluator.code_origins=copying.capture_code_origins(source.code_origins,[]);
 pools.evaluator.values=copying.capture_values(source.values,[]);
 pools.evaluator.children=copying.capture_children(source.children,[]);
 pools.evaluator.closures=copying.capture_closures(source.closures,[]);
 pools.evaluator.value_evidence=copying.capture_value_evidence(source.value_evidence,[]);
 pools.evaluator.type_mappings=copying.capture_type_mappings(source.type_mappings,[]);
 pools.evaluator.row_mappings=copying.capture_row_mappings(source.row_mappings,[]);
 pools.evaluator.value_records=copying.capture_value_records(source.value_records,[]);
 pools.evaluator.record_layouts=copying.capture_record_layouts(source.record_layouts,[]);
 pools.evaluator.field_names=copying.capture_field_names(source.field_names,[]);
 pools.evaluator.evidence.nodes=copying.capture_evidence_nodes(source.evidence.nodes,[]);
 pools.evaluator.evidence.extra=copying.capture_evidence_extra(source.evidence.extra,[]);
 pools.evaluator.evidence.quantifier_goals=copying.capture_evidence_quantifier_goals(source.evidence.quantifier_goals,[]);
 pools.evaluator.evidence.quantifier_obligations=copying.capture_evidence_quantifier_obligations(source.evidence.quantifier_obligations,[]);
 pools.evaluator.evidence.effects.operations=copying.capture_evidence_operations(source.evidence.effects.operations,[]);
 pools.evaluator.evidence.effects.arguments=copying.capture_evidence_arguments(source.evidence.effects.arguments,[]);
 pools.evaluator.evidence.effects.rows=copying.capture_evidence_rows(source.evidence.effects.rows,[]);
 pools.evaluator.evidence.effects.labels=copying.capture_evidence_labels(source.evidence.effects.labels,[]);
 pools.evaluator.implementation_proofs.proofs=copying.capture_implementation_proofs(source.implementation_proofs.proofs,[]);
 pools.evaluator.implementation_proofs.arguments=copying.capture_implementation_arguments(source.implementation_proofs.arguments,[]);
 pools.evaluator.implementation_proofs.members=copying.capture_implementation_members(source.implementation_proofs.members,[]);
 pools.evaluator.implementation_proofs.edges=copying.capture_implementation_edges(source.implementation_proofs.edges,[]);
 if copying.failure!=blot_error::Error.none {let __cleanup_result_10_0: Archive<C> = Archive<C>.inactive {}; let __cleanup_result_10_1: Error = copying.failure; {if !pools_moved {pools.leases=copying.shared.leases;pools.deinit();}} {if !published {factory.destroyArchiveCapture(token);}} return __cleanup_result_10_0, __cleanup_result_10_1;}
 // All immutable pools are complete before any selected record is published.
 for record in snapshot.value.queries.records {
  let proof=record.dependencies;let owned=blot_reuse_specialization_receipt::Record{member:blot_support::none<blot_reuse_specialization_receipt::Member>(),input:record.key.input,expected:record.key.expected,selected:record.result.selected,options:record.key.options,depth:record.key.depth,values_before:proof.values_before,children_before:proof.children_before,values_added:proof.values_added,children_added:proof.children_added,steps:0,collected:proof.collected,source_scopes:proof.source_scopes,solver_nodes:proof.solver_nodes,complete:true,sources:blot_reuse_specialization_receipt::copyOwned(proof.sources),scalar_reads:blot_reuse_specialization_receipt::copyOwned(proof.scalar_reads),call_reads:blot_reuse_specialization_receipt::copyOwned(proof.call_reads),call_publications:blot_reuse_specialization_receipt::copyOwned(proof.call_publications),views:blot_reuse_specialization_receipt::copyOwned(proof.views),plain_facts:blot_reuse_specialization_receipt::copyOwned(proof.plain_facts)};
  let closure=snapshot.value.evaluator.closures[snapshot.value.evaluator.values[owned.input].bits];let position,remembered,error=blot_eval_selected_query::remember(capture.metadata.specialization_queries,closure,owned);if error!=blot_error::Error.none {let __cleanup_result_11_0: Archive<C> = Archive<C>.inactive {}; let __cleanup_result_11_1: Error = error; {if !pools_moved {pools.leases=copying.shared.leases;pools.deinit();}} {if !published {factory.destroyArchiveCapture(token);}} return __cleanup_result_11_0, __cleanup_result_11_1;}
 }
 pools.leases=copying.shared.leases;capture.metadata.pools=blot_support::some(pools);pools_moved=true;let result=Archive<C>.live{snapshot.value.units,capture,factory,token,snapshot.owner};snapshot.owner=blot_reuse_dependency_format::Owner{};published=true;let __cleanup_result_12_0: Archive<C> = result; let __cleanup_result_12_1: Error = blot_error::Error.none; {if !pools_moved {pools.leases=copying.shared.leases;pools.deinit();}} {if !published {factory.destroyArchiveCapture(token);}} return __cleanup_result_12_0, __cleanup_result_12_1;
 {if !pools_moved {pools.leases=copying.shared.leases;pools.deinit();}} {if !published {factory.destroyArchiveCapture(token);}} }
fn emptyEvaluator()->blot_eval_core_eval::Snapshot {return default<blot_eval_core_eval::Snapshot>();}
