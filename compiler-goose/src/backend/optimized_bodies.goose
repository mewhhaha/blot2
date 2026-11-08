// Immutable detached optimizer inputs/results and exact bounded correspondence.
namespace blot_backend_optimized_bodies;
import dictionary;
import backend.runtime_ir;
import backend.wasm;
import backend.wasm_lifetimes;
import backend.provider_modes;
import backend.runtime_body_relocation;
import backend.runtime_function_key;
import reuse.executable_query;
import reuse.semantic_query_table;
import runtime.region_runtime;
import runtime.cohort_runtime;
import compilation_tier;
import support.error;
import support.option;
import support.native;
import support.structural;
import support.pooled_buffer;
import support.wyhash;
type Error=blot_error::Error;
type ValueType=blot_backend_runtime_ir::ValueType;
type Instruction=blot_backend_runtime_ir::Instruction;
type SourceFunction=blot_backend_runtime_ir::DetachedFunction;
type Body=blot_backend_runtime_ir::DetachedBody;
type Parameter=blot_backend_wasm_lifetimes::Parameter;
type Tier=blot_compilation_tier::Tier;
type Walk=blot_backend_runtime_body_relocation::Walk;
type ReferenceKind=blot_backend_runtime_body_relocation::Kind;
struct WorkerTiming {cpu_us:blot_support::Option<u64> =blot_support::none<u64>(),jobs:i64=0,instructions:i64=0,started_us:u64=0,finished_us:u64=0}
struct Stats {tier:Tier=blot_compilation_tier::Tier.optimized,functions:i64=0,optimized:i64=0,reused:i64=0,shared:i64=0,workers:i64=1,parallel_jobs:i64=0,rc_reused:i64=0,rc_checked:i64=0,encoded_reused:i64=0,encoded_reused_bytes:i64=0,retained_bytes:i64=0,role_conflicts:i64=0,match_candidates:i64=0,match_work:i64=0,match_budget_exhausted:i64=0,query_records:i64=0,query_complete:bool=false,query_saturated:i64=0,query_capacity_bytes:i64=0,worker_timings:blot_support::Option<WorkerTiming[16]> =blot_support::none<WorkerTiming[16]>()}
struct EncodedRange {start:i64=0,len:i64=0}
struct Entry {source:SourceFunction=default<SourceFunction>(),parameters:Parameter[:] = default<Parameter[:]>(),invalidates:bool=false,owned_result_bytes:blot_support::Option<u32> =blot_support::none<u32>(),output:blot_support::Option<Body> =blot_support::none<Body>(),output_ready:bool=false,rc_unproven:blot_support::Option<bool> =blot_support::none<bool>(),encoded:EncodedRange=EncodedRange{}}
struct Encoding {functions:i64,unique:i64,imports:u32,globals:i64,signatures:i64,root_mode:u32,rc_admitted:bool,wide:bool,retire:blot_support::Option<u32>,collector_free:bool=false,profile_base:u32=0,profile_rows:i64=0}
struct Import {module:const u8[:] = default<const u8[:]>(),name:const u8[:] = default<const u8[:]>(),signature:u32=0}
struct Signature {parameters:const ValueType[:] = default<const ValueType[:]>(),result:ValueType=blot_backend_runtime_ir::VT_none}
reusable[] var owned_parameters:Parameter[>..]=[];
reusable[] var owned_types:ValueType[>..]=[];
reusable[] var owned_bytes:u8[>..]=[];
reusable[] var owned_words:u32[>..]=[];
reusable[] var region_members:blot_runtime_region_runtime::Member[>..]=[];
reusable[] var region_scopes:blot_runtime_region_runtime::Scope[>..]=[];
fn copyParameters(source:const Parameter[:])->Parameter[:] {let result=owned_parameters.alloc_slice(source.len);for item,index in source {result[index]=item;}return result;}
fn copyTypes(source:const ValueType[:])->const ValueType[:] {let result=owned_types.alloc_slice(source.len);for item,index in source {result[index]=item;}return result;}
fn copyBytes(source:const u8[:])->const u8[:] {let result=owned_bytes.alloc_slice(source.len);for item,index in source {result[index]=item;}return result;}
fn freeBytes(source:const u8[:]) {if source.len!=0 {owned_bytes.free_slice(source);}}
fn freeTypes(source:const ValueType[:]) {if source.len!=0 {owned_types.free_slice(source);}}
fn deinit(self_:Entry&) {self_.source.deinit();if self_.parameters.len!=0 {owned_parameters.free_slice(self_.parameters);}if self_.output.present {self_.output.value.deinit();}self_=Entry{};}
fn deinit(self_:Import&) {freeBytes(self_.module);freeBytes(self_.name);self_=Import{};}
struct Entries {storage:Entry[:] = default<Entry[:]>(),items:Entry[:] = default<Entry[:]>(),len:i64=0,failure:Error=blot_error::Error.none}
reusable[] var entries_pool:Entry[>..]=[];
fn ensure(self_:Entries&,minimum:i64)->Error {if self_.failure!=blot_error::Error.none {return self_.failure;}let error=blot_support_pooled_buffer::ensure(self_,minimum,entries_pool);if error!=blot_error::Error.none {self_.failure=error;}return error;}
fn push(self_:Entries&,value:Entry)->Error {if self_.failure!=blot_error::Error.none {return self_.failure;}let error=blot_support_pooled_buffer::push(self_,value,entries_pool);self_.len=self_.items.len;self_.failure=error;return error;}
fn append(self_:Entries&,values:const Entry[:])->Error {if self_.failure!=blot_error::Error.none {return self_.failure;}let error=blot_support_pooled_buffer::append(self_,values,entries_pool);self_.len=self_.items.len;self_.failure=error;return error;}
fn clear(self_:Entries&) {blot_support_pooled_buffer::clear(self_);self_.len=0;self_.failure=blot_error::Error.none;}
fn deinit(self_:Entries&) {blot_support_pooled_buffer::deinit(self_,entries_pool);self_.len=0;self_.failure=blot_error::Error.none;}
struct Signatures {storage:Signature[:] = default<Signature[:]>(),items:Signature[:] = default<Signature[:]>(),len:i64=0,failure:Error=blot_error::Error.none}
reusable[] var signatures_pool:Signature[>..]=[];
fn ensure(self_:Signatures&,minimum:i64)->Error {if self_.failure!=blot_error::Error.none {return self_.failure;}let error=blot_support_pooled_buffer::ensure(self_,minimum,signatures_pool);if error!=blot_error::Error.none {self_.failure=error;}return error;}
fn push(self_:Signatures&,value:Signature)->Error {if self_.failure!=blot_error::Error.none {return self_.failure;}let error=blot_support_pooled_buffer::push(self_,value,signatures_pool);self_.len=self_.items.len;self_.failure=error;return error;}
fn append(self_:Signatures&,values:const Signature[:])->Error {if self_.failure!=blot_error::Error.none {return self_.failure;}let error=blot_support_pooled_buffer::append(self_,values,signatures_pool);self_.len=self_.items.len;self_.failure=error;return error;}
fn clear(self_:Signatures&) {blot_support_pooled_buffer::clear(self_);self_.len=0;self_.failure=blot_error::Error.none;}
fn deinit(self_:Signatures&) {blot_support_pooled_buffer::deinit(self_,signatures_pool);self_.len=0;self_.failure=blot_error::Error.none;}
struct Imports {storage:Import[:] = default<Import[:]>(),items:Import[:] = default<Import[:]>(),len:i64=0,failure:Error=blot_error::Error.none}
reusable[] var imports_pool:Import[>..]=[];
fn ensure(self_:Imports&,minimum:i64)->Error {if self_.failure!=blot_error::Error.none {return self_.failure;}let error=blot_support_pooled_buffer::ensure(self_,minimum,imports_pool);if error!=blot_error::Error.none {self_.failure=error;}return error;}
fn push(self_:Imports&,value:Import)->Error {if self_.failure!=blot_error::Error.none {return self_.failure;}let error=blot_support_pooled_buffer::push(self_,value,imports_pool);self_.len=self_.items.len;self_.failure=error;return error;}
fn append(self_:Imports&,values:const Import[:])->Error {if self_.failure!=blot_error::Error.none {return self_.failure;}let error=blot_support_pooled_buffer::append(self_,values,imports_pool);self_.len=self_.items.len;self_.failure=error;return error;}
fn clear(self_:Imports&) {blot_support_pooled_buffer::clear(self_);self_.len=0;self_.failure=blot_error::Error.none;}
fn deinit(self_:Imports&) {blot_support_pooled_buffer::deinit(self_,imports_pool);self_.len=0;self_.failure=blot_error::Error.none;}
struct Globals {storage:blot_backend_wasm::Global[:] = default<blot_backend_wasm::Global[:]>(),items:blot_backend_wasm::Global[:] = default<blot_backend_wasm::Global[:]>(),len:i64=0,failure:Error=blot_error::Error.none}
reusable[] var globals_pool:blot_backend_wasm::Global[>..]=[];
fn ensure(self_:Globals&,minimum:i64)->Error {if self_.failure!=blot_error::Error.none {return self_.failure;}let error=blot_support_pooled_buffer::ensure(self_,minimum,globals_pool);if error!=blot_error::Error.none {self_.failure=error;}return error;}
fn push(self_:Globals&,value:blot_backend_wasm::Global)->Error {if self_.failure!=blot_error::Error.none {return self_.failure;}let error=blot_support_pooled_buffer::push(self_,value,globals_pool);self_.len=self_.items.len;self_.failure=error;return error;}
fn append(self_:Globals&,values:const blot_backend_wasm::Global[:])->Error {if self_.failure!=blot_error::Error.none {return self_.failure;}let error=blot_support_pooled_buffer::append(self_,values,globals_pool);self_.len=self_.items.len;self_.failure=error;return error;}
fn clear(self_:Globals&) {blot_support_pooled_buffer::clear(self_);self_.len=0;self_.failure=blot_error::Error.none;}
fn deinit(self_:Globals&) {blot_support_pooled_buffer::deinit(self_,globals_pool);self_.len=0;self_.failure=blot_error::Error.none;}
struct Providers {storage:blot_backend_provider_modes::Mode[:] = default<blot_backend_provider_modes::Mode[:]>(),items:blot_backend_provider_modes::Mode[:] = default<blot_backend_provider_modes::Mode[:]>(),len:i64=0,failure:Error=blot_error::Error.none}
reusable[] var providers_pool:blot_backend_provider_modes::Mode[>..]=[];
fn ensure(self_:Providers&,minimum:i64)->Error {if self_.failure!=blot_error::Error.none {return self_.failure;}let error=blot_support_pooled_buffer::ensure(self_,minimum,providers_pool);if error!=blot_error::Error.none {self_.failure=error;}return error;}
fn push(self_:Providers&,value:blot_backend_provider_modes::Mode)->Error {if self_.failure!=blot_error::Error.none {return self_.failure;}let error=blot_support_pooled_buffer::push(self_,value,providers_pool);self_.len=self_.items.len;self_.failure=error;return error;}
fn append(self_:Providers&,values:const blot_backend_provider_modes::Mode[:])->Error {if self_.failure!=blot_error::Error.none {return self_.failure;}let error=blot_support_pooled_buffer::append(self_,values,providers_pool);self_.len=self_.items.len;self_.failure=error;return error;}
fn clear(self_:Providers&) {blot_support_pooled_buffer::clear(self_);self_.len=0;self_.failure=blot_error::Error.none;}
fn deinit(self_:Providers&) {blot_support_pooled_buffer::deinit(self_,providers_pool);self_.len=0;self_.failure=blot_error::Error.none;}
struct Encoded {storage:u8[:] = default<u8[:]>(),items:u8[:] = default<u8[:]>(),len:i64=0,failure:Error=blot_error::Error.none}
reusable[] var encoded_pool:u8[>..]=[];
fn ensure(self_:Encoded&,minimum:i64)->Error {if self_.failure!=blot_error::Error.none {return self_.failure;}let error=blot_support_pooled_buffer::ensure(self_,minimum,encoded_pool);if error!=blot_error::Error.none {self_.failure=error;}return error;}
fn push(self_:Encoded&,value:u8)->Error {if self_.failure!=blot_error::Error.none {return self_.failure;}let error=blot_support_pooled_buffer::push(self_,value,encoded_pool);self_.len=self_.items.len;self_.failure=error;return error;}
fn append(self_:Encoded&,values:const u8[:])->Error {if self_.failure!=blot_error::Error.none {return self_.failure;}let error=blot_support_pooled_buffer::append(self_,values,encoded_pool);self_.len=self_.items.len;self_.failure=error;return error;}
fn clear(self_:Encoded&) {blot_support_pooled_buffer::clear(self_);self_.len=0;self_.failure=blot_error::Error.none;}
fn deinit(self_:Encoded&) {blot_support_pooled_buffer::deinit(self_,encoded_pool);self_.len=0;self_.failure=blot_error::Error.none;}
struct State {live:bool=false,generation:u64=0,roots:bool=false,needs_roots:bool=false,root_slots:u32=0,tier:Tier=blot_compilation_tier::Tier.optimized,entries:Entries=Entries{},signatures:Signatures=Signatures{},imports:Imports=Imports{},globals:Globals=Globals{},arena:blot_support::Option<blot_backend_wasm::Arena> =blot_support::none<blot_backend_wasm::Arena>(),cohorts:blot_support::Option<blot_runtime_cohort_runtime::Runtime> =blot_support::none<blot_runtime_cohort_runtime::Runtime>(),fixture_helpers:blot_support::Option<u32[3]> =blot_support::none<u32[3]>(),regions:blot_support::Option<blot_runtime_region_runtime::Prepared> =blot_support::none<blot_runtime_region_runtime::Prepared>(),providers:Providers=Providers{},queries:blot_reuse_executable_query::OptimizerTable=blot_reuse_executable_query::OptimizerTable{adapter:blot_reuse_executable_query::OptimizerAdapter{},limits:blot_reuse_semantic_query_table::Limits{records:16384,retained_capacity:8388608}},queries_complete:bool=false,encoding:blot_support::Option<Encoding> =blot_support::none<Encoding>(),encoding_indexes:const u32[:] = default<const u32[:]>(),encoded:Encoded=Encoded{}}
var inactive:State=State{};
reusable var states:State[>..]=[];
struct Capture {slot:u32=0,generation:u64=0,canonical:u32=0,
roots:(bool)& =inactive.roots,
needs_roots:(bool)& =inactive.needs_roots,
root_slots:(u32)& =inactive.root_slots,
tier:(Tier)& =inactive.tier,
entries:(Entries)& =inactive.entries,
signatures:(Signatures)& =inactive.signatures,
imports:(Imports)& =inactive.imports,
globals:(Globals)& =inactive.globals,
arena:(blot_support::Option<blot_backend_wasm::Arena>)& =inactive.arena,
cohorts:(blot_support::Option<blot_runtime_cohort_runtime::Runtime>)& =inactive.cohorts,
fixture_helpers:(blot_support::Option<u32[3]>)& =inactive.fixture_helpers,
regions:(blot_support::Option<blot_runtime_region_runtime::Prepared>)& =inactive.regions,
providers:(Providers)& =inactive.providers,
queries:(blot_reuse_executable_query::OptimizerTable)& =inactive.queries,
queries_complete:(bool)& =inactive.queries_complete,
encoding:(blot_support::Option<Encoding>)& =inactive.encoding,
encoding_indexes:(const u32[:])& =inactive.encoding_indexes,
encoded:(Encoded)& =inactive.encoded,
}
reusable var canonical_captures:Capture[>..]=[];
fn valid(self_:const Capture&)->bool {return self_.slot!=0 && self_.slot-1<states.len && states[self_.slot-1].live && states[self_.slot-1].generation==self_.generation;}
fn initPooled()->Capture,Error {if states.len>=0xffffffff {return Capture{},blot_error::Error.out_of_memory;}let generation=blot_native::fresh_owner_id();let at=states.alloc_index(State{live:true,generation:generation});let state:State& =states[at];state.queries=blot_reuse_executable_query::initOptimizer(blot_reuse_semantic_query_table::Limits{records:16384,retained_capacity:8388608});return Capture{slot:(at+1) as u32,generation:generation,roots:state.roots,needs_roots:state.needs_roots,root_slots:state.root_slots,tier:state.tier,entries:state.entries,signatures:state.signatures,imports:state.imports,globals:state.globals,arena:state.arena,cohorts:state.cohorts,fixture_helpers:state.fixture_helpers,regions:state.regions,providers:state.providers,queries:state.queries,queries_complete:state.queries_complete,encoding:state.encoding,encoding_indexes:state.encoding_indexes,encoded:state.encoded},blot_error::Error.none;}
fn init()->Capture,Error {return initPooled();}
fn initPooledRef()->Capture?,Error {let value,error=initPooled();if error!=blot_error::Error.none {return null,error;}let at=canonical_captures.alloc_index(value);canonical_captures[at].canonical=(at+1) as u32;return canonical_captures[at],blot_error::Error.none;}
fn freeRegions(value:blot_runtime_region_runtime::Prepared) {if value.plan.members.len!=0 {region_members.free_slice(value.plan.members);}if value.scopes.len!=0 {region_scopes.free_slice(value.scopes);}}
fn clearOwned(self_:Capture&) {
 if self_.regions.present {freeRegions(self_.regions.value);}self_.regions=blot_support::none<blot_runtime_region_runtime::Prepared>();self_.queries.deinit();if self_.encoding_indexes.len!=0 {owned_words.free_slice(self_.encoding_indexes);}self_.encoding_indexes=default<const u32[:]>();self_.encoded.deinit();for &entry in self_.entries.items {entry.deinit();}self_.entries.deinit();for signature in self_.signatures.items {freeTypes(signature.parameters);}self_.signatures.deinit();for &item in self_.imports.items {item.deinit();}self_.imports.deinit();self_.globals.deinit();self_.providers.deinit();
}
fn deinit(self_:Capture&) {if self_.slot==0 {return;}assert(self_.valid());let at=self_.slot-1;let canonical=self_.canonical;self_.clearOwned();states[at]=State{};states.free(at);self_=Capture{};if canonical!=0 {canonical_captures[canonical-1]=Capture{};canonical_captures.free(canonical-1);}}
fn reset(self_:Capture&)->Error {assert(self_.valid());self_.clearOwned();let generation=self_.generation;let state:State& =states[self_.slot-1];state=State{live:true,generation:generation};state.queries=blot_reuse_executable_query::initOptimizer(blot_reuse_semantic_query_table::Limits{records:16384,retained_capacity:8388608});return blot_error::Error.none;}
fn captureRegions(self_:Capture&,regions:blot_support::Option<blot_runtime_region_runtime::Prepared>)->Error {assert(self_.valid() && !self_.regions.present);if !regions.present {return blot_error::Error.none;}var context=regions.value;let members=region_members.alloc_slice(context.plan.members.len);for member,index in context.plan.members {members[index]=member;}let scopes=region_scopes.alloc_slice(context.scopes.len);for scope,index in context.scopes {scopes[index]=scope;}context.plan.members=members;context.scopes=scopes;self_.regions=blot_support::some(context);return blot_error::Error.none;}
fn recordInputs(self_:Capture&,module:const blot_backend_wasm::Module&,summaries:const blot_backend_wasm_lifetimes::Summaries&)->Error {
 assert(self_.entries.len==0 && self_.signatures.len==0);self_.arena=module.arena;self_.cohorts=module.cohorts;self_.fixture_helpers=module.fixture_helpers;let error=self_.captureRegions(module.regions);if error!=blot_error::Error.none {return error;}
 let error=self_.entries.ensure(module.functions.len);if error!=blot_error::Error.none {return error;}
 for function,index in module.functions {let summary=summaries.functions[index];let cloned,error=blot_backend_runtime_ir::cloneFunction(function,blot_backend_wasm::parameters(module,function),blot_backend_wasm::locals(module,function),blot_backend_wasm::instructions(module,function));if error!=blot_error::Error.none {return error;}var source=cloned;let parameters=copyParameters(summary.parameters);let error=self_.entries.push(Entry{source:source,parameters:parameters,invalidates:summary.invalidates,owned_result_bytes:summary.owned_result_bytes});if error!=blot_error::Error.none {source.deinit();if parameters.len!=0 {owned_parameters.free_slice(parameters);}return error;}}
 let error=self_.signatures.ensure(module.signatures.len);if error!=blot_error::Error.none {return error;}for signature in module.signatures {let parameters=copyTypes(module.types[signature.parameters.start..signature.parameters.start+signature.parameters.len]);let error=self_.signatures.push(Signature{parameters,signature.result});if error!=blot_error::Error.none {freeTypes(parameters);return error;}}
 let error=self_.imports.ensure(module.imports.len);if error!=blot_error::Error.none {return error;}for item in module.imports {let namespace_=copyBytes(blot_backend_wasm::name(module,item.module));let name=copyBytes(blot_backend_wasm::name(module,item.name));let error=self_.imports.push(Import{namespace_,name,item.signature});if error!=blot_error::Error.none {freeBytes(namespace_);freeBytes(name);return error;}}
 return self_.globals.append(module.globals[..]);
}
fn recordOutput(self_:Capture&,id:i64,body_result:blot_support::Option<Body>)->Error {assert(!self_.entries.items[id].output.present);if body_result.present {let body,error=blot_backend_runtime_ir::cloneBody(body_result.value);if error!=blot_error::Error.none {return error;}self_.entries.items[id].output=blot_support::some(body);}self_.entries.items[id].output_ready=true;return blot_error::Error.none;}
fn recordEncoding(self_:Capture&,context:Encoding,indexes:const u32[:])->Error {let owned=owned_words.alloc_slice(indexes.len);for index,at in indexes {owned[at]=index;}if self_.encoding_indexes.len!=0 {owned_words.free_slice(self_.encoding_indexes);}self_.encoding_indexes=owned;self_.encoding=blot_support::some(context);return blot_error::Error.none;}
fn recordEncoded(self_:Capture&,id:i64,bytes:const u8[:])->Error {let limit:i64=8388608;if bytes.len>limit-self_.encoded.len {return blot_error::Error.none;}let start=self_.encoded.len;let error=self_.encoded.append(bytes);if error!=blot_error::Error.none {return error;}self_.entries.items[id].encoded=EncodedRange{start,bytes.len};return blot_error::Error.none;}
fn output(self_:const Capture&,id:i64)->blot_support::Option<Body> {return self_.entries.items[id].output;}
fn queryAt(self_:const Capture&,id:i64)->const blot_reuse_executable_query::OptimizerRecord? {if !self_.queries_complete || self_.queries.limits.lookup_work==0 {return null;}var first:i64=0;var end=self_.queries.records.len;while first<end {let middle=first+(end-first)/2;let record .= self_.queries.records[middle];if record.value.function<id {first=middle+1;}else if record.value.function>id {end=middle;}else {return record;}}return null;}
fn sealQueries(self_:Capture&)->Error {
 assert(self_.queries.records.len==0 && !self_.queries_complete);
 for entry,id in self_.entries.items {if !entry.output_ready {continue;}var call_count:i64=0;for inst in entry.source.instructions {if inst.op==blot_backend_runtime_ir::OP_call || inst.table_reference {call_count++;}}let bytes=blot_reuse_executable_query::dependencyBytes<u32,Parameter>(call_count,entry.parameters.len);if !bytes.present || !self_.queries.canAdmit(bytes.value) {self_.queries.saturate();return blot_error::Error.none;}
  var builder=self_.queries.begin(blot_reuse_executable_query::OptimizerKey{local_fingerprint:blot_backend_runtime_body_relocation::hash(entry.source),tier:self_.tier});let callees=owned_words.alloc_slice(call_count);var cursor:i64=0;for inst in entry.source.instructions {if inst.op==blot_backend_runtime_ir::OP_call || inst.table_reference {callees[cursor]=inst.operand;cursor++;}}
  let owned=blot_reuse_executable_query::copyCallees(callees);if callees.len!=0 {owned_words.free_slice(callees);}builder.read(blot_reuse_executable_query::OptimizerDependencies{callees:owned,parameters:blot_reuse_executable_query::copyParameters(entry.parameters),invalidates:entry.invalidates,owned_result_bytes:entry.owned_result_bytes,context_complete:true});builder.stage(blot_reuse_executable_query::OptimizerResult{id as u32,true});var candidate=builder.complete();assert(candidate.present);let prepared,error=self_.queries.prepare(candidate.value);if error!=blot_error::Error.none {let __cleanup_result_1_0: Error = error; {candidate.value.abort();} {builder.abort();} return __cleanup_result_1_0;}if !prepared.present {let __cleanup_result_2_0: Error = blot_error::Error.none; {candidate.value.abort();} {builder.abort();} return __cleanup_result_2_0;}let handle=self_.queries.publish(prepared.value,candidate.value);
  {candidate.value.abort();} {builder.abort();} }self_.queries_complete=true;return blot_error::Error.none;
}
fn bytes(self_:const Capture&)->i64 {var count=self_.entries.len*146+self_.signatures.len*17+self_.imports.len*36+self_.globals.len*6+self_.providers.len*7;for entry in self_.entries.items {count+=entry.source.parameters.len+entry.source.locals.len+entry.source.instructions.len*11+entry.parameters.len*5;if entry.output.present {count+=entry.output.value.locals.len+entry.output.value.instructions.len*11;}}for signature in self_.signatures.items {count+=signature.parameters.len;}for item in self_.imports.items {count+=item.module.len+item.name.len;}if self_.regions.present {count+=self_.regions.value.plan.members.len*8+self_.regions.value.scopes.len*8;}return count+self_.queries.owned_bytes+self_.queries.capacity_bytes+self_.encoding_indexes.len*4+self_.encoded.storage.len;}
fn blot_backend_runtime_body_relocation::hash(function:blot_backend_runtime_ir::DetachedFunction)->u64 {
 var bytes:u8[>..]=[];blot_backend_runtime_function_key::appendWord(bytes,function.parameters.len as u64,8);bytes.append(function.parameters);bytes.push(function.result);bytes.push(function.result_role);var entry:u8=0;if function.entry {entry=1;}bytes.push(entry);blot_backend_runtime_function_key::appendWord(bytes,function.parameter_roles,8);bytes.push(function.provider_parameter);blot_backend_runtime_function_key::appendWord(bytes,function.callable_layout,4);blot_backend_runtime_function_key::appendWord(bytes,function.locals.len as u64,8);bytes.append(function.locals);
 for inst in function.instructions {bytes.push(inst.op);var flag:u8=0;if inst.table_reference {flag=1;}bytes.push(flag);bytes.push(inst.table_kind);if !blot_backend_runtime_body_relocation::reference(inst) {blot_backend_runtime_function_key::appendWord(bytes,inst.operand,4);}}return blot_support_wyhash::hash(0,bytes[..]);
}
fn blot_backend_runtime_body_relocation::equalLocal(before:blot_backend_runtime_ir::DetachedFunction,after:blot_backend_runtime_ir::DetachedFunction)->bool {
 if before.result_role!=after.result_role || before.entry!=after.entry || before.parameter_roles!=after.parameter_roles || before.provider_parameter!=after.provider_parameter || before.callable_layout!=after.callable_layout || before.result!=after.result || before.parameters!=after.parameters || before.locals!=after.locals || before.instructions.len!=after.instructions.len {return false;}
 for left,index in before.instructions {let right=after.instructions[index];if left.op!=right.op || left.table_reference!=right.table_reference || left.table_kind!=right.table_kind || (!blot_backend_runtime_body_relocation::reference(left) && left.operand!=right.operand) {return false;}}return true;
}
fn regionsEqual(before:blot_support::Option<blot_runtime_region_runtime::Prepared>,after:blot_support::Option<blot_runtime_region_runtime::Prepared>)->bool {
 if before.present!=after.present {return false;}if !before.present {return true;}let left=before.value;let right=after.value;if left.runtime!=right.runtime || left.plan.frame_bytes!=right.plan.frame_bytes || left.plan.bytes!=right.plan.bytes || left.plan.mask!=right.plan.mask || left.plan.members.len!=right.plan.members.len || left.scopes.len!=right.scopes.len {return false;}for member,index in left.plan.members {if member!=right.plan.members[index] {return false;}}for scope,index in left.scopes {if scope!=right.scopes[index] {return false;}}return true;
}
reusable[] var match_flags:bool[>..]=[];
reusable[] var match_bodies:blot_support::Option<Body>[>..]=[];
reusable[] var match_ids:blot_support::Option<i64>[>..]=[];
struct Matcher {old:Capture=Capture{},current:Capture=Capture{},same:bool[:] = default<bool[:]>(),arena_same:bool=false,relocated:blot_support::Option<Body>[:] = default<blot_support::Option<Body>[:]>(),prior_ids:blot_support::Option<i64>[:] = default<blot_support::Option<i64>[:]>(),candidates:i64=0,work:i64=0,budget_exhausted:i64=0}
fn resourceDrain(capture:const Capture&)->bool {for item in capture.imports.items {if item.module!="blot:resource/2" || item.name!="drain" {continue;}let signature=capture.signatures.items[item.signature];if signature.parameters.len==0 && signature.result==blot_backend_runtime_ir::VT_none {return true;}}return false;}
fn samePosition(before:SourceFunction,after:SourceFunction)->bool {if !blot_backend_runtime_body_relocation::equalLocal(before,after) {return false;}for left,index in before.instructions {if left.operand!=after.instructions[index].operand {return false;}}return true;}
fn init(old:const Capture&,current:const Capture&)->Matcher,Error {
 assert(old.valid() && current.valid());var providers_same=old.providers.len==current.providers.len;if providers_same {for left,index in old.providers.items {if left!=current.providers.items[index] {providers_same=false;break;}}}
 let arena_same=regionsEqual(old.regions,current.regions) && resourceDrain(old)==resourceDrain(current) && providers_same && old.tier==current.tier && old.roots==current.roots && old.needs_roots==current.needs_roots && old.root_slots==current.root_slots && old.arena.present==current.arena.present;
 let same=match_flags.alloc_slice(current.entries.len);for entry,id in current.entries.items {same[id]=arena_same && old.queries_complete && old.queries.limits.lookup_work!=0 && id<old.entries.len && samePosition(old.entries.items[id].source,entry.source);}
 let relocated=match_bodies.alloc_slice(current.entries.len);for &body in relocated {body=blot_support::none<Body>();}let prior_ids=match_ids.alloc_slice(current.entries.len);for &id in prior_ids {id=blot_support::none<i64>();}
 var self_=Matcher{old:old,current:current,same:same,arena_same:arena_same,relocated:relocated,prior_ids:prior_ids};if self_.arena_same {let error=self_.findRelocations();if error!=blot_error::Error.none {self_.deinit();return Matcher{},error;}}return self_,blot_error::Error.none;
}
fn deinit(self_:Matcher&) {for &body in self_.relocated {if body.present {body.value.deinit();}}if self_.relocated.len!=0 {match_bodies.free_slice(self_.relocated);}if self_.prior_ids.len!=0 {match_ids.free_slice(self_.prior_ids);}if self_.same.len!=0 {match_flags.free_slice(self_.same);}self_=Matcher{};}
fn signatureSame(self_:const Matcher&,before:u32,after:u32)->bool {if before>=self_.old.signatures.len || after>=self_.current.signatures.len {return false;}let left=self_.old.signatures.items[before];let right=self_.current.signatures.items[after];return left.result==right.result && left.parameters==right.parameters;}
fn summarySame(self_:const Matcher&,before:blot_reuse_executable_query::OptimizerDependencies,after:Entry)->bool {if before.invalidates!=after.invalidates || !blot_support::equal(before.owned_result_bytes,after.owned_result_bytes) || before.parameters.len!=after.parameters.len {return false;}for left,index in before.parameters {if left!=after.parameters[index] {return false;}}return true;}
fn importSame(self_:const Matcher&,before:u32,after:u32)->bool {if before>=self_.old.imports.len || after>=self_.current.imports.len {return false;}let left=self_.old.imports.items[before];let right=self_.current.imports.items[after];return left.module==right.module && left.name==right.name && self_.signatureSame(left.signature,right.signature);}
fn globalSame(self_:const Matcher&,before:u32,after:u32)->bool {return before<self_.old.globals.len && after<self_.current.globals.len && self_.old.globals.items[before]==self_.current.globals.items[after];}
fn matchesPosition(self_:const Matcher&,walk:Walk&,id:i64)->bool {
 if !self_.arena_same || !blot_structural::equal(self_.old.arena,self_.current.arena) || !self_.same[id] || self_.old.entries.items[id].source.parameter_roles!=self_.current.entries.items[id].source.parameter_roles || !self_.old.entries.items[id].output_ready {return false;}
 let record .= self_.old.queryAt(id);if !record || record.key.tier!=self_.current.tier || !self_.summarySame(record.dependencies,self_.current.entries.items[id]) {return false;}
 let selected=self_.old.output(id);if selected.present {let body=selected.value;if !walk.spend(body.instructions.len) {return false;}for inst in body.instructions {let kind=blot_backend_runtime_body_relocation::referenceKind(inst);if !kind.present {continue;}match kind.value {function=>{if inst.operand>=self_.same.len || !self_.same[inst.operand] {return false;}},import_=>{if !self_.importSame(inst.operand,inst.operand) {return false;}},signature=>{if !self_.signatureSame(inst.operand,inst.operand) {return false;}},global=>{if !self_.globalSame(inst.operand,inst.operand) {return false;}},}}}return true;
}
fn matches(self_:const Matcher&,id:i64)->bool {return self_.prior_ids[id].present;}
fn output(self_:const Matcher&,id:i64)->blot_support::Option<Body> {if self_.relocated[id].present {return self_.relocated[id];}assert(self_.prior_ids[id].present);return self_.old.output(self_.prior_ids[id].value);}
fn rcUnproven(self_:const Matcher&,id:i64)->blot_support::Option<bool> {if !self_.prior_ids[id].present {return blot_support::none<bool>();}if !blot_structural::equal(self_.old.arena,self_.current.arena) || !blot_structural::equal(self_.old.cohorts,self_.current.cohorts) || !blot_structural::equal(self_.old.fixture_helpers,self_.current.fixture_helpers) {return blot_support::none<bool>();}return self_.old.entries.items[self_.prior_ids[id].value].rc_unproven;}
fn encodingSame(self_:const Matcher&,context:Encoding,indexes:const u32[:])->bool {if !self_.old.encoding.present || !blot_structural::equal(self_.old.encoding.value,context) || !blot_structural::equal(self_.old.arena,self_.current.arena) || self_.old.encoding_indexes!=indexes || self_.old.globals.len!=self_.current.globals.len {return false;}for left,index in self_.old.globals.items {if left!=self_.current.globals.items[index] {return false;}}return true;}
fn encodedBody(self_:const Matcher&,id:i64)->blot_support::Option<const u8[:]> {if !self_.prior_ids[id].present || self_.prior_ids[id].value!=id || !self_.same[id] || self_.relocated[id].present {return blot_support::none<const u8[:]>();}let span=self_.old.entries.items[id].encoded;if span.len==0 {return blot_support::none<const u8[:]>();}return blot_support::some(self_.old.encoded.items[span.start..span.start+span.len]);}
fn arenaRole(arena:blot_support::Option<blot_backend_wasm::Arena>,id:u32,functions:bool)->blot_support::Option<i64> {
 if !arena.present {return blot_support::none<i64>();}
 if functions {for field,index in blot_backend_wasm::arena_function_fields {const for <N,A> in fields<blot_backend_wasm::Arena> {if N==field && arena.value.A==id {return blot_support::some(index);}}}}
 else {for field,index in blot_backend_wasm::arena_global_fields {const for <N,A> in fields<blot_backend_wasm::Arena> {if N==field && arena.value.A==id {return blot_support::some(index);}}}}
 return blot_support::none<i64>();
}
fn referenceSame(self_:const Matcher&,walk:Walk&,kind:ReferenceKind,before:u32,after:u32)->bool {
 match kind {
  function=>{if !blot_support::equal(arenaRole(self_.old.arena,before,true),arenaRole(self_.current.arena,after,true)) {return false;}},
  import_=>{if !self_.importSame(before,after) || !walk.add(blot_backend_runtime_body_relocation::Kind.signature,self_.old.imports.items[before].signature,self_.current.imports.items[after].signature) {return false;}},
  signature=>{if !self_.signatureSame(before,after) {return false;}},
  global=>{if !self_.globalSame(before,after) || !blot_support::equal(arenaRole(self_.old.arena,before,false),arenaRole(self_.current.arena,after,false)) {return false;}},
 }return walk.add(kind,before,after);
}
fn drainGraph(self_:const Matcher&,walk:Walk&)->bool {
 while walk.pending.len!=0 {let pair=walk.pending.pop();if pair.before>=self_.old.entries.len || pair.after>=self_.current.entries.len {return false;}let left=self_.old.entries.items[pair.before];let right=self_.current.entries.items[pair.after];if !self_.referenceSame(walk,blot_backend_runtime_body_relocation::Kind.signature,left.source.signature,right.source.signature) {return false;}
  if !walk.spend(left.source.instructions.len+left.source.parameters.len+left.source.locals.len) || !blot_backend_runtime_body_relocation::equalLocal(left.source,right.source) || left.invalidates!=right.invalidates || !blot_support::equal(left.owned_result_bytes,right.owned_result_bytes) || left.parameters.len!=right.parameters.len {return false;}for parameter,index in left.parameters {if parameter!=right.parameters[index] {return false;}}
  for instruction,index in left.source.instructions {let kind=blot_backend_runtime_body_relocation::referenceKind(instruction);if kind.present && !self_.referenceSame(walk,kind.value,instruction.operand,right.source.instructions[index].operand) {return false;}}
 }return true;
}
fn graphSame(self_:const Matcher&,walk:Walk&,before:i64,after:i64)->bool {walk.clear();if !self_.referenceSame(walk,blot_backend_runtime_body_relocation::Kind.function,before as u32,after as u32) {return false;}return self_.drainGraph(walk);}
fn outputReferences(self_:const Matcher&,walk:Walk&,body:Body)->bool {
 for inst in body.instructions {let kind=blot_backend_runtime_body_relocation::referenceKind(inst);if !kind.present {continue;}if !walk.spend(1) {return false;}if walk.get(kind.value,inst.operand).present {continue;}if kind.value!=blot_backend_runtime_body_relocation::Kind.function || !self_.old.arena.present || !self_.current.arena.present {return false;}var found=false;
  const for <N,A> in fields<blot_backend_wasm::Arena> {var selected=false;for name in blot_backend_wasm::arena_function_fields {if N==name {selected=true;}}if selected && self_.old.arena.value.A==inst.operand {if !self_.referenceSame(walk,blot_backend_runtime_body_relocation::Kind.function,inst.operand,self_.current.arena.value.A) {return false;}found=true;}}
  if !found {return false;}
 }return self_.drainGraph(walk);
}
struct ReverseEdge {caller:u32,next:u32}
fn preparePositions(self_:Matcher&,walk:Walk&)->Error {
 if !blot_structural::equal(self_.old.arena,self_.current.arena) || !walk.spend(self_.same.len) {for &same in self_.same {same=false;}return blot_error::Error.none;}
 for entry,id in self_.current.entries.items {
  if !self_.same[id] {continue;}let before=self_.old.entries.items[id];if !walk.spend(entry.source.instructions.len+before.parameters.len) {for &same in self_.same {same=false;}return blot_error::Error.none;}
  if before.invalidates!=entry.invalidates || !blot_support::equal(before.owned_result_bytes,entry.owned_result_bytes) || before.parameters.len!=entry.parameters.len {self_.same[id]=false;continue;}
  for left,index in before.parameters {if left!=entry.parameters[index] {self_.same[id]=false;}}
  for inst in entry.source.instructions {if inst.op==blot_backend_runtime_ir::OP_call_import {if !self_.importSame(inst.operand,inst.operand) {self_.same[id]=false;}}else if inst.op==blot_backend_runtime_ir::OP_call_indirect {if !self_.signatureSame(inst.operand,inst.operand) {self_.same[id]=false;}}else if inst.op==blot_backend_runtime_ir::OP_global_get || inst.op==blot_backend_runtime_ir::OP_global_set {if !self_.globalSame(inst.operand,inst.operand) {self_.same[id]=false;}}}
 }
 var changed=false;for same in self_.same {if !same {changed=true;break;}}if !changed {return blot_error::Error.none;}
 let absent:u32=0xffffffff;let heads=owned_words.alloc_slice(self_.same.len);for &head in heads {head=absent;}var edges:ReverseEdge[>..<]=[];var pending:u32[>..<]=[];
 for entry,id in self_.current.entries.items {if !self_.same[id] {continue;}for inst in entry.source.instructions {if inst.op!=blot_backend_runtime_ir::OP_call && !inst.table_reference {continue;}if !walk.spend(1) {for &same in self_.same {same=false;}let __cleanup_result_3_0: Error = blot_error::Error.none; {if heads.len!=0 {owned_words.free_slice(heads);}} return __cleanup_result_3_0;}if inst.operand>=self_.same.len {self_.same[id]=false;break;}let next=edges.len as u32;edges.push(ReverseEdge{id as u32,heads[inst.operand]});heads[inst.operand]=next;}}
 for same,id in self_.same {if !same {pending.push(id as u32);}}
 while pending.len!=0 {let callee=pending.pop();var edge=heads[callee];while edge!=absent {if !walk.spend(1) {for &same in self_.same {same=false;}let __cleanup_result_4_0: Error = blot_error::Error.none; {if heads.len!=0 {owned_words.free_slice(heads);}} return __cleanup_result_4_0;}let item=edges[edge];if self_.same[item.caller] {self_.same[item.caller]=false;pending.push(item.caller);}edge=item.next;}}let __cleanup_result_5_0: Error = blot_error::Error.none; {if heads.len!=0 {owned_words.free_slice(heads);}} return __cleanup_result_5_0;
 {if heads.len!=0 {owned_words.free_slice(heads);}} }
fn findRelocations(self_:Matcher&)->Error {
 if !self_.old.queries_complete || self_.old.queries.limits.lookup_work==0 {return blot_error::Error.none;}
 var targets:dictionary<blot_backend_runtime_body_relocation::Key,u32> =dictionary<blot_backend_runtime_body_relocation::Key,u32>{};var reverse:dictionary<blot_backend_runtime_body_relocation::Key,u32> =dictionary<blot_backend_runtime_body_relocation::Key,u32>{};var pending:blot_backend_runtime_body_relocation::Pair[>..<]=[];var walk=Walk{targets:targets,reverse:reverse,pending:pending};let budget=walk.remaining;
 var position_targets:dictionary<blot_backend_runtime_body_relocation::Key,u32> =dictionary<blot_backend_runtime_body_relocation::Key,u32>{};var position_reverse:dictionary<blot_backend_runtime_body_relocation::Key,u32> =dictionary<blot_backend_runtime_body_relocation::Key,u32>{};var position_pending:blot_backend_runtime_body_relocation::Pair[>..<]=[];var positions=Walk{targets:position_targets,reverse:position_reverse,pending:position_pending,remaining:0x7fffffffffffffff};

 let error=self_.preparePositions(positions);if error!=blot_error::Error.none {let __cleanup_result_6_0: Error = error; {let relocation_work=budget-walk.remaining;let position_work=0x7fffffffffffffff-positions.remaining;if position_work>0x7fffffffffffffff-relocation_work {self_.work=0x7fffffffffffffff;}else {self_.work=relocation_work+position_work;}self_.budget_exhausted=0;if walk.remaining==0 {self_.budget_exhausted=1;}} return __cleanup_result_6_0;}var missing=false;
 for &prior,id in self_.prior_ids {self_.candidates++;if self_.matchesPosition(positions,id) {prior=blot_support::some(id);}else {missing=true;}}
 if !missing {let __cleanup_result_7_0: Error = blot_error::Error.none; {let relocation_work=budget-walk.remaining;let position_work=0x7fffffffffffffff-positions.remaining;if position_work>0x7fffffffffffffff-relocation_work {self_.work=0x7fffffffffffffff;}else {self_.work=relocation_work+position_work;}self_.budget_exhausted=0;if walk.remaining==0 {self_.budget_exhausted=1;}} return __cleanup_result_7_0;}
 for entry,id in self_.current.entries.items {
  if self_.prior_ids[id].present {continue;}if walk.remaining==0 {let __cleanup_result_8_0: Error = blot_error::Error.none; {let relocation_work=budget-walk.remaining;let position_work=0x7fffffffffffffff-positions.remaining;if position_work>0x7fffffffffffffff-relocation_work {self_.work=0x7fffffffffffffff;}else {self_.work=relocation_work+position_work;}self_.budget_exhausted=0;if walk.remaining==0 {self_.budget_exhausted=1;}} return __cleanup_result_8_0;}
  var candidates=self_.old.queries.candidates(blot_backend_runtime_body_relocation::hash(entry.source),blot_reuse_semantic_query_table::Order.newest_first);candidates.remaining=min(candidates.remaining,64);
  loop {let position=candidates.next();if !position.present {break;}if walk.remaining==0 {let __cleanup_result_9_0: Error = blot_error::Error.none; {let relocation_work=budget-walk.remaining;let position_work=0x7fffffffffffffff-positions.remaining;if position_work>0x7fffffffffffffff-relocation_work {self_.work=0x7fffffffffffffff;}else {self_.work=relocation_work+position_work;}self_.budget_exhausted=0;if walk.remaining==0 {self_.budget_exhausted=1;}} return __cleanup_result_9_0;}self_.candidates++;let record=self_.old.queries.records[position.value];if record.key.tier!=self_.current.tier || !self_.summarySame(record.dependencies,entry) {continue;}let before=record.value.function;if !self_.graphSame(walk,before,id) {continue;}
   let selected=self_.old.output(before);if selected.present {let body=selected.value;let copied,error=blot_backend_runtime_ir::cloneBody(body);if error!=blot_error::Error.none {let __cleanup_result_10_0: Error = error; {let relocation_work=budget-walk.remaining;let position_work=0x7fffffffffffffff-positions.remaining;if position_work>0x7fffffffffffffff-relocation_work {self_.work=0x7fffffffffffffff;}else {self_.work=relocation_work+position_work;}self_.budget_exhausted=0;if walk.remaining==0 {self_.budget_exhausted=1;}} return __cleanup_result_10_0;}var relocated=copied;var owns=true;if !self_.outputReferences(walk,body) {{if owns {relocated.deinit();}} continue;}for &inst in relocated.instructions {let kind=blot_backend_runtime_body_relocation::referenceKind(inst);if kind.present {let actual=walk.get(kind.value,inst.operand);assert(actual.present);inst.operand=actual.value;}}self_.relocated[id]=blot_support::some(relocated);owns=false; {if owns {relocated.deinit();}} }
   self_.prior_ids[id]=blot_support::some(before as i64);break;
  }
 }let __cleanup_result_12_0: Error = blot_error::Error.none; {let relocation_work=budget-walk.remaining;let position_work=0x7fffffffffffffff-positions.remaining;if position_work>0x7fffffffffffffff-relocation_work {self_.work=0x7fffffffffffffff;}else {self_.work=relocation_work+position_work;}self_.budget_exhausted=0;if walk.remaining==0 {self_.budget_exhausted=1;}} return __cleanup_result_12_0;
 {let relocation_work=budget-walk.remaining;let position_work=0x7fffffffffffffff-positions.remaining;if position_work>0x7fffffffffffffff-relocation_work {self_.work=0x7fffffffffffffff;}else {self_.work=relocation_work+position_work;}self_.budget_exhausted=0;if walk.remaining==0 {self_.budget_exhausted=1;}} }
fn cloneBody(source:Body)->Body,Error {return blot_backend_runtime_ir::cloneBody(source);}
fn cloneFunction(source:SourceFunction)->SourceFunction,Error {return blot_backend_runtime_ir::cloneFunction(source);}

// Caller-owned canonical headers may be reused across compiler attempts. The
// header itself outlives every borrowed run and is not a reusable pool lease.
fn initInto(self_:Capture&)->Error {
 if self_.valid() {return self_.reset();}
 let value,error=initPooled();if error!=blot_error::Error.none {return error;}self_=value;return blot_error::Error.none;
}
