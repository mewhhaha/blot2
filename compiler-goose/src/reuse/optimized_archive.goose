// Portable optimizer candidates require exact current machine correspondence.
namespace blot_reuse_optimized_archive;
import backend.runtime_ir;
import backend.optimized_bodies;
import backend.wasm_lifetimes;
import backend.wasm;
import backend.provider_modes;
import backend.runtime_body_relocation;
import runtime.region_runtime;
import reuse.executable_query;
import reuse.portable_query;
import reuse.dependency_format;
import reuse.source_overlays;
import compilation_tier;
import support.error;
import support.option;
import support.structural;
type Error=blot_error::Error;
type Digest=blot_reuse_dependency_format::Digest;
type ValueType=blot_backend_runtime_ir::ValueType;
type Body=blot_backend_runtime_ir::DetachedBody;
type Parameter=blot_backend_wasm_lifetimes::Parameter;
type Capture=blot_backend_optimized_bodies::Capture;
type Tier=blot_compilation_tier::Tier;
struct Function {parameters:const ValueType[:],result:ValueType,result_role:blot_backend_runtime_ir::Role=blot_backend_runtime_ir::ROLE_unknown,entry:bool=false,provider_parameter:u16=blot_backend_runtime_ir::unknown_provider,callable_layout:u32=0,parameter_roles:u64,annotations:u32,signature:u32,body:Body}
struct Entry {source:Function,parameters:const Parameter[:],invalidates:bool,owned_result_bytes:blot_support::Option<u32>,output:blot_support::Option<Body>,output_ready:bool}
struct Key {tier:Tier}
struct Dependencies {callees:const u32[:],parameters:const Parameter[:],invalidates:bool,owned_result_bytes:blot_support::Option<u32>}
struct Result {function:u32}
struct Record {key:Key,dependencies:Dependencies,result:Result}
struct Section {header:blot_reuse_portable_query::Header,records:const Record[:]}
let claim=blot_reuse_portable_query::Claim.optimizer_output;
fn admitted(self_:Section)->bool {return self_.header==blot_reuse_portable_query::header(claim);}
struct Snapshot {tier:Tier,roots:bool=false,needs_roots:bool=false,root_slots:u32=0,arena:blot_support::Option<blot_backend_wasm::Arena>,regions:blot_support::Option<blot_runtime_region_runtime::Prepared> =blot_support::none<blot_runtime_region_runtime::Prepared>(),entries:const Entry[:],signatures:const blot_backend_optimized_bodies::Signature[:],imports:const blot_backend_optimized_bodies::Import[:],globals:const blot_backend_wasm::Global[:],providers:const blot_backend_provider_modes::Mode[:]=default<const blot_backend_provider_modes::Mode[:]>(),sealed:bool,queries:Section}
fn wireKey(compiler:Digest)->blot_reuse_dependency_format::Key {return blot_reuse_dependency_format::Key{compiler,blot_reuse_dependency_format::digest("blot-optimizer-capture-v42:profile-identity+inline-contexts+borrowed-variant-payloads+collector-contract+profile-categories+tagged-numeric-rows+flatten+diagnostic-source-origins+owned-region-preparation-context+physical-tracing-absent+checked-logical-callable-endpoints+checked-provider-modes+checked-provider-parameters+selected-implementations+associated-types+checked-call-results+root-frame-demand+compact-roots+row-fusion+forwarded-roots+paired-state+numeric-scopes+row-products+conditional-roots+private-local-storage+immutable-acyclic-layouts+direct-callable-environments+scalar-journals+owned-field-locals+small-producer-groups+qualified-journal-fallback+private-cursors+private-table-projections+private-cursor-word-positions+snapshot-leaf-directory+eager-tuple-reductions+symbolic-empty-constructor-fields+activation-owned-field-roots+checked-nonempty-loads+private-absent-fields+journal-only-carriers+immortal-reference-facts+prefix-owned-fields+progress-sized-replacement+per-loop-journal-cost+bounded-private-scalar-consumers+bounded-invalidation-worklist+structured-control-reachability+completed-empty-producer-loops+checked-scalar-self-identities+checked-field-update-layouts+checked-scalar-stores+wide-counted-shapes+deferred-partial-tracing+checked-list-literal-publication+prepared-machine-sharing+proved-list-runtime-access+checked-production-emission+resolved-collection-iteration+exact-empty-cursor"),[0;32],[0;32]};}
fn encode(compiler:Digest,capture:const Capture&)->u8[:],Error {
 var entries:Entry[>..<];for entry in capture.entries.items {let source=entry.source;entries.push(Entry{Function{parameters:source.parameters,result:source.result,result_role:source.result_role,entry:source.entry,provider_parameter:source.provider_parameter,callable_layout:source.callable_layout,parameter_roles:source.parameter_roles,annotations:source.annotations,signature:source.signature,body:Body{source.locals,source.instructions}},entry.parameters,entry.invalidates,entry.owned_result_bytes,entry.output,entry.output_ready});}
 let sealed=capture.queries_complete;var records:Record[>..<];if sealed {for record in capture.queries.records {records.push(Record{Key{record.key.tier},Dependencies{record.dependencies.callees,record.dependencies.parameters,record.dependencies.invalidates,record.dependencies.owned_result_bytes},Result{record.value.function}});}}
 let snapshot=Snapshot{tier:capture.tier,roots:capture.roots,needs_roots:capture.needs_roots,root_slots:capture.root_slots,arena:capture.arena,regions:capture.regions,entries:entries[..],signatures:capture.signatures.items,imports:capture.imports.items,globals:capture.globals.items,providers:capture.providers.items,sealed:sealed,queries:Section{blot_reuse_portable_query::header(claim),records[..]}};return blot_reuse_dependency_format::encode(wireKey(compiler),snapshot);
}
fn decode(compiler:Digest,bytes:const u8[:])->Capture,Error {
 let decoded,error=blot_reuse_dependency_format::decode<Snapshot>(bytes,wireKey(compiler));if error!=blot_error::Error.none {return Capture{},error;}var owner=decoded;let error=validate(owner.value);if error!=blot_error::Error.none {let __cleanup_result_1_0: Capture = Capture{}; let __cleanup_result_1_1: Error = error; {owner.deinit();} return __cleanup_result_1_0, __cleanup_result_1_1;}
 let opened,error=blot_backend_optimized_bodies::initPooled();if error!=blot_error::Error.none {let __cleanup_result_2_0: Capture = Capture{}; let __cleanup_result_2_1: Error = error; {owner.deinit();} return __cleanup_result_2_0, __cleanup_result_2_1;}var result=opened;var published=false;
 let snapshot=owner.value;result.tier=snapshot.tier;result.roots=snapshot.roots;result.needs_roots=snapshot.needs_roots;result.root_slots=snapshot.root_slots;result.arena=snapshot.arena;let error=result.captureRegions(snapshot.regions);if error!=blot_error::Error.none {let __cleanup_result_3_0: Capture = Capture{}; let __cleanup_result_3_1: Error = error; {if !published {result.deinit();}} {owner.deinit();} return __cleanup_result_3_0, __cleanup_result_3_1;}
 let error=result.entries.ensure(snapshot.entries.len);if error!=blot_error::Error.none {let __cleanup_result_4_0: Capture = Capture{}; let __cleanup_result_4_1: Error = error; {if !published {result.deinit();}} {owner.deinit();} return __cleanup_result_4_0, __cleanup_result_4_1;}
 for entry in snapshot.entries {
  // cloneFunction reads these borrowed views and creates its own detached runs.
  let source=blot_backend_runtime_ir::DetachedFunction{parameters:owner.owner.mutable(entry.source.parameters),result:entry.source.result,result_role:entry.source.result_role,entry:entry.source.entry,provider_parameter:entry.source.provider_parameter as u8,callable_layout:entry.source.callable_layout,parameter_roles:entry.source.parameter_roles,annotations:entry.source.annotations,signature:entry.source.signature,locals:owner.owner.mutable(entry.source.body.locals),instructions:owner.owner.mutable(entry.source.body.instructions)};
  let cloned,error=blot_backend_runtime_ir::cloneFunction(source);if error!=blot_error::Error.none {let __cleanup_result_5_0: Capture = Capture{}; let __cleanup_result_5_1: Error = error; {if !published {result.deinit();}} {owner.deinit();} return __cleanup_result_5_0, __cleanup_result_5_1;}var own_source=cloned;var output=blot_support::none<Body>();
  if entry.output.present {let copied,error=blot_backend_runtime_ir::cloneBody(entry.output.value);if error!=blot_error::Error.none {own_source.deinit();let __cleanup_result_6_0: Capture = Capture{}; let __cleanup_result_6_1: Error = error; {if !published {result.deinit();}} {owner.deinit();} return __cleanup_result_6_0, __cleanup_result_6_1;}output=blot_support::some(copied);}
  let own_parameters=blot_backend_optimized_bodies::copyParameters(entry.parameters);let error=result.entries.push(blot_backend_optimized_bodies::Entry{source:own_source,parameters:own_parameters,invalidates:entry.invalidates,owned_result_bytes:entry.owned_result_bytes,output:output,output_ready:entry.output_ready});if error!=blot_error::Error.none {var rejected=blot_backend_optimized_bodies::Entry{source:own_source,parameters:own_parameters,output:output};rejected.deinit();let __cleanup_result_7_0: Capture = Capture{}; let __cleanup_result_7_1: Error = error; {if !published {result.deinit();}} {owner.deinit();} return __cleanup_result_7_0, __cleanup_result_7_1;}
 }
 for signature in snapshot.signatures {let parameters=blot_backend_optimized_bodies::copyTypes(signature.parameters);let error=result.signatures.push(blot_backend_optimized_bodies::Signature{parameters,signature.result});if error!=blot_error::Error.none {blot_backend_optimized_bodies::freeTypes(parameters);let __cleanup_result_8_0: Capture = Capture{}; let __cleanup_result_8_1: Error = error; {if !published {result.deinit();}} {owner.deinit();} return __cleanup_result_8_0, __cleanup_result_8_1;}}
 for item in snapshot.imports {let module=blot_backend_optimized_bodies::copyBytes(item.module);let name=blot_backend_optimized_bodies::copyBytes(item.name);let error=result.imports.push(blot_backend_optimized_bodies::Import{module,name,item.signature});if error!=blot_error::Error.none {blot_backend_optimized_bodies::freeBytes(module);blot_backend_optimized_bodies::freeBytes(name);let __cleanup_result_9_0: Capture = Capture{}; let __cleanup_result_9_1: Error = error; {if !published {result.deinit();}} {owner.deinit();} return __cleanup_result_9_0, __cleanup_result_9_1;}}
 let error=result.providers.append(snapshot.providers);if error!=blot_error::Error.none {let __cleanup_result_10_0: Capture = Capture{}; let __cleanup_result_10_1: Error = error; {if !published {result.deinit();}} {owner.deinit();} return __cleanup_result_10_0, __cleanup_result_10_1;}let error=result.globals.append(snapshot.globals);if error!=blot_error::Error.none {let __cleanup_result_11_0: Capture = Capture{}; let __cleanup_result_11_1: Error = error; {if !published {result.deinit();}} {owner.deinit();} return __cleanup_result_11_0, __cleanup_result_11_1;}if snapshot.sealed {let error=seal(result,snapshot.queries.records);if error!=blot_error::Error.none {let __cleanup_result_12_0: Capture = Capture{}; let __cleanup_result_12_1: Error = error; {if !published {result.deinit();}} {owner.deinit();} return __cleanup_result_12_0, __cleanup_result_12_1;}}published=true;let __cleanup_result_13_0: Capture = result; let __cleanup_result_13_1: Error = blot_error::Error.none; {if !published {result.deinit();}} {owner.deinit();} return __cleanup_result_13_0, __cleanup_result_13_1;
 {if !published {result.deinit();}} {owner.deinit();} }
fn seal(capture:Capture&,records:const Record[:])->Error {
 for record in records {var builder=capture.queries.begin(blot_reuse_executable_query::OptimizerKey{local_fingerprint:blot_backend_runtime_body_relocation::hash(capture.entries.items[record.result.function].source),tier:record.key.tier});builder.read(blot_reuse_executable_query::OptimizerDependencies{callees:blot_reuse_executable_query::copyCallees(record.dependencies.callees),parameters:blot_reuse_executable_query::copyParameters(record.dependencies.parameters),invalidates:record.dependencies.invalidates,owned_result_bytes:record.dependencies.owned_result_bytes,context_complete:true});builder.stage(blot_reuse_executable_query::OptimizerResult{record.result.function,true});var candidate=builder.complete();if !candidate.present {let __cleanup_result_14_0: Error = blot_error::Error.none; {builder.abort();} return __cleanup_result_14_0;}let prepared,error=capture.queries.prepare(candidate.value);if error!=blot_error::Error.none {let __cleanup_result_15_0: Error = error; {candidate.value.abort();} {builder.abort();} return __cleanup_result_15_0;}if !prepared.present {let __cleanup_result_16_0: Error = blot_error::Error.none; {candidate.value.abort();} {builder.abort();} return __cleanup_result_16_0;}let handle=capture.queries.publish(prepared.value,candidate.value); {candidate.value.abort();} {builder.abort();} }capture.queries_complete=true;return blot_error::Error.none;
}
fn validTypes(values:const ValueType[:])->bool {for value in values {if value==blot_backend_runtime_ir::VT_none {return false;}}return true;}
fn validate(snapshot:const Snapshot&)->Error {
 let section=snapshot.queries;if section.header.version!=blot_reuse_portable_query::version {return blot_error::Error.unsupported_version;}if !section.admitted() {return blot_error::Error.schema_mismatch;}var frames:bool[>..<];let resources=Resources{snapshot.entries.len,snapshot.imports.len,snapshot.signatures.len,snapshot.globals.len,frames};
 if snapshot.providers.len>4096 {return blot_error::Error.invalid_artifact;}for mode,index in snapshot.providers {if mode.operation==0 || (index!=0 && snapshot.providers[index-1].operation>=mode.operation) {return blot_error::Error.invalid_artifact;}if mode.access!=blot_backend_provider_modes::Access.unsupported && ((mode.role!=blot_backend_runtime_ir::ROLE_scalar && mode.role!=blot_backend_runtime_ir::ROLE_reference) || (mode.machine!=blot_backend_runtime_ir::VT_i32 && mode.machine!=blot_backend_runtime_ir::VT_f32) || (mode.role==blot_backend_runtime_ir::ROLE_reference && mode.machine!=blot_backend_runtime_ir::VT_i32)) {return blot_error::Error.invalid_artifact;}}
 for signature in snapshot.signatures {if !validTypes(signature.parameters) {return blot_error::Error.invalid_artifact;}}
 for item in snapshot.imports {if item.signature>=snapshot.signatures.len || !blot_reuse_source_overlays::utf8_valid(item.module) || !blot_reuse_source_overlays::utf8_valid(item.name) {return blot_error::Error.invalid_artifact;}}
 if snapshot.arena.present {const for <N,A> in fields<blot_backend_wasm::Arena> {for field in blot_backend_wasm::arena_function_fields {if N==field && snapshot.arena.value.A>=resources.functions {return blot_error::Error.invalid_artifact;}}for field in blot_backend_wasm::arena_global_fields {if N==field && snapshot.arena.value.A>=resources.globals {return blot_error::Error.invalid_artifact;}}}}
 if snapshot.roots && (!snapshot.arena.present || snapshot.root_slots<snapshot.globals.len || snapshot.root_slots>0x3fffffff) {return blot_error::Error.invalid_artifact;}if !snapshot.roots && (snapshot.needs_roots || snapshot.root_slots!=0) {return blot_error::Error.invalid_artifact;}
 for entry in snapshot.entries {
  if entry.source.signature>=snapshot.signatures.len || entry.parameters.len!=entry.source.parameters.len || (!entry.output_ready && entry.output.present) || (entry.source.result_role==blot_backend_runtime_ir::ROLE_reference && entry.source.result!=blot_backend_runtime_ir::VT_i32) || entry.source.callable_layout>=1<<26 {return blot_error::Error.invalid_artifact;}
  let provider=entry.source.provider_parameter;if provider!=blot_backend_runtime_ir::unknown_provider && provider!=blot_backend_runtime_ir::no_provider && (provider>=entry.source.parameters.len || entry.source.parameters[provider]!=blot_backend_runtime_ir::VT_i32 || provider>=32 || ((entry.source.parameter_roles>>((provider*2) as u32))&3)!=blot_backend_runtime_ir::ROLE_reference) {return blot_error::Error.invalid_artifact;}
  let signature=snapshot.signatures[entry.source.signature];if signature.result!=entry.source.result || signature.parameters!=entry.source.parameters || !validTypes(entry.source.parameters) || !validTypes(entry.source.body.locals) {return blot_error::Error.invalid_artifact;}
  var annotations:i64=0;for inst in entry.source.body.instructions {if inst.op==blot_backend_runtime_ir::OP_ownership {annotations++;}}if annotations!=entry.source.annotations || !resources.body(entry.source.parameters.len,entry.source.body) {return blot_error::Error.invalid_artifact;}if entry.output.present {if !validTypes(entry.output.value.locals) || !resources.body(entry.source.parameters.len,entry.output.value) {return blot_error::Error.invalid_artifact;}}
 }
 let error=validateRegions(snapshot);if error!=blot_error::Error.none {return error;}if !snapshot.sealed {if section.records.len!=0 {return blot_error::Error.invalid_artifact;}return blot_error::Error.none;}
 var next:i64=0;for entry,id in snapshot.entries {if !entry.output_ready {continue;}if next==section.records.len || !recordMatches(section.records[next],snapshot,id) {return blot_error::Error.invalid_artifact;}next++;}if next!=section.records.len {return blot_error::Error.invalid_artifact;}return blot_error::Error.none;
}
fn recordMatches(record:Record,snapshot:const Snapshot&,id:i64)->bool {
 let entry=snapshot.entries[id];if record.result.function!=id || record.key.tier!=snapshot.tier {return false;}let observed=record.dependencies;if observed.invalidates!=entry.invalidates || !blot_support::equal(observed.owned_result_bytes,entry.owned_result_bytes) || observed.parameters.len!=entry.parameters.len {return false;}for left,index in observed.parameters {if left!=entry.parameters[index] {return false;}}var cursor:i64=0;for inst in entry.source.body.instructions {if inst.op==blot_backend_runtime_ir::OP_call || inst.table_reference {if cursor==observed.callees.len || observed.callees[cursor]!=inst.operand {return false;}cursor++;}}return cursor==observed.callees.len;
}
struct Resources {functions:i64,imports:i64,signatures:i64,globals:i64,frames:bool[>..<]&}
fn body(self_:Resources,parameters:i64,value:Body)->bool {
 var locals:i64=0x7fffffffffffffff;if value.locals.len<=0x7fffffffffffffff-parameters {locals=parameters+value.locals.len;}let frames .= self_.frames;frames.clear();
 for inst,at in value.instructions {
  if inst.op==blot_backend_runtime_ir::OP_ownership {let annotation=blot_backend_runtime_ir::ownership(inst.operand);if annotation.kind==blot_backend_runtime_ir::OWN_call_result {if annotation.chunk!=0 || annotation.roles>blot_backend_runtime_ir::ROLE_value || at+1>=value.instructions.len || value.instructions[at+1].op!=blot_backend_runtime_ir::OP_call_indirect {return false;}}}
  if (!inst.table_reference && inst.table_kind!=blot_backend_runtime_ir::TABLE_unknown) || (inst.table_reference && (inst.op!=blot_backend_runtime_ir::OP_i32_const || inst.operand>=self_.functions)) {return false;}
  if inst.op==blot_backend_runtime_ir::OP_block || inst.op==blot_backend_runtime_ir::OP_loop || inst.op==blot_backend_runtime_ir::OP_if_ {let value=inst.operand;if value!=0 && value!=blot_backend_runtime_ir::VT_i32 && value!=blot_backend_runtime_ir::VT_f32 && value!=blot_backend_runtime_ir::VT_v128 && value!=blot_backend_runtime_ir::VT_externref && value!=blot_backend_runtime_ir::VT_none {return false;}frames.push(inst.op==blot_backend_runtime_ir::OP_if_);}
  else if inst.op==blot_backend_runtime_ir::OP_else_ {if frames.len==0 {return false;}let allowed=frames[frames.len-1];frames[frames.len-1]=false;if !allowed {return false;}}
  else if inst.op==blot_backend_runtime_ir::OP_end {if frames.len==0 {return false;}frames.pop();}
  else if inst.op==blot_backend_runtime_ir::OP_br || inst.op==blot_backend_runtime_ir::OP_br_if {if inst.operand>frames.len {return false;}}
  else if inst.op==blot_backend_runtime_ir::OP_call {if inst.operand>=self_.functions {return false;}}
  else if inst.op==blot_backend_runtime_ir::OP_call_import {if inst.operand>=self_.imports {return false;}}
  else if inst.op==blot_backend_runtime_ir::OP_call_indirect {if inst.operand>=self_.signatures {return false;}}
  else if inst.op==blot_backend_runtime_ir::OP_global_get || inst.op==blot_backend_runtime_ir::OP_global_set {if inst.operand>=self_.globals {return false;}}
  else if inst.op==blot_backend_runtime_ir::OP_local_get || inst.op==blot_backend_runtime_ir::OP_local_set || inst.op==blot_backend_runtime_ir::OP_local_tee {if inst.operand>=locals {return false;}}
  else if inst.op==blot_backend_runtime_ir::OP_i32x4_replace_lane || inst.op==blot_backend_runtime_ir::OP_i32x4_extract_lane || inst.op==blot_backend_runtime_ir::OP_f32x4_extract_lane || inst.op==blot_backend_runtime_ir::OP_f32x4_replace_lane {if inst.operand>=4 {return false;}}
  else if inst.op==blot_backend_runtime_ir::OP_i8x16_shuffle {if inst.operand>=1<<12 {return false;}}
 }return frames.len==0;
}
fn validateRegions(snapshot:const Snapshot&)->Error {
 if !snapshot.regions.present {return blot_error::Error.none;}let regions=snapshot.regions.value;if !snapshot.roots || !snapshot.needs_roots || !snapshot.arena.present || regions.scopes.len>snapshot.entries.len || !regions.plan.valid() {return blot_error::Error.invalid_artifact;}
 var types:blot_backend_runtime_ir::ValueType[>..<];
 var instructions:blot_backend_runtime_ir::Instruction[>..<];
 var names:u8[>..<];
 var functions:blot_backend_runtime_ir::Function[>..<];
 var signatures:blot_backend_runtime_ir::Signature[>..<];
 var imports:blot_backend_wasm::Import[>..<];
 var globals:blot_backend_wasm::Global[>..<];
 var exports:blot_backend_wasm::Export[>..<];
 var data:u8[>..<];
 var static_fields:u32[>..<];
 var table_functions:u32[>..<];
 var table_origins:blot_backend_wasm::TableOrigin[>..<];
 var semantic_sites:blot_backend_wasm::SemanticSite[>..<];
 var module=blot_backend_wasm::init(types,instructions,names,functions,signatures,imports,globals,exports,data,static_fields,table_functions,table_origins,semantic_sites);
 for entry in snapshot.entries {if entry.source.provider_parameter>255 {return blot_error::Error.invalid_artifact;}let start=types.len as u32;types.append(entry.source.parameters);let function=blot_backend_runtime_ir::Function{parameters:blot_backend_runtime_ir::Range{start,entry.source.parameters.len as u32},result:entry.source.result,result_role:entry.source.result_role,entry:entry.source.entry,parameter_roles:entry.source.parameter_roles,provider_parameter:entry.source.provider_parameter as u8,signature:entry.source.signature,..};if !blot_backend_runtime_ir::validProviderParameter(module,function) {return blot_error::Error.invalid_artifact;}functions.push(function);}
 if !regions.valid(module) {return blot_error::Error.invalid_artifact;}return blot_error::Error.none;
}
