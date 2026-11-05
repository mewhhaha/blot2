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
struct WorkerTiming {cpu_us:blot_support::Option<u64>=blot_support::none<u64>(),jobs:i64=0,instructions:i64=0,started_us:u64=0,finished_us:u64=0}
struct Stats {tier:Tier=Tier.optimized,functions:i64=0,optimized:i64=0,reused:i64=0,shared:i64=0,workers:i64=1,parallel_jobs:i64=0,rc_reused:i64=0,rc_checked:i64=0,encoded_reused:i64=0,encoded_reused_bytes:i64=0,retained_bytes:i64=0,role_conflicts:i64=0,match_candidates:i64=0,match_work:i64=0,match_budget_exhausted:i64=0,query_records:i64=0,query_complete:bool=false,query_saturated:i64=0,query_capacity_bytes:i64=0,worker_timings:blot_support::Option<WorkerTiming[16]>=blot_support::none<WorkerTiming[16]>()}
struct EncodedRange {start:i64=0,len:i64=0}
struct Entry {source:SourceFunction=default<SourceFunction>(),parameters:Parameter[:]=[],invalidates:bool=false,owned_result_bytes:blot_support::Option<u32>=blot_support::none<u32>(),output:blot_support::Option<Body>=blot_support::none<Body>(),output_ready:bool=false,rc_unproven:blot_support::Option<bool>=blot_support::none<bool>(),encoded:EncodedRange=EncodedRange{}}
struct Encoding {functions:i64,unique:i64,imports:u32,globals:i64,signatures:i64,root_mode:u32,rc_admitted:bool,wide:bool,retire:blot_support::Option<u32>,collector_free:bool=false,profile_base:u32=0,profile_rows:i64=0}
struct Import {module:const u8[:]=[],name:const u8[:]=[],signature:u32=0}
struct Signature {parameters:const ValueType[:]=[],result:ValueType=blot_backend_runtime_ir::VT_none}
reusable[] var owned_parameters:Parameter[>..]=[];
reusable[] var owned_types:ValueType[>..]=[];
reusable[] var owned_bytes:u8[>..]=[];
reusable[] var owned_words:u32[>..]=[];
reusable[] var region_members:blot_runtime_region_runtime::Member[>..]=[];
reusable[] var region_scopes:blot_runtime_region_runtime::Scope[>..]=[];
fn copyParameters(source:const Parameter[:])->Parameter[:] {let result=owned_parameters.alloc_slice(source.len);for item,index in source {result[index]=item;}return result;}
fn copyTypes(source:const ValueType[:])->const ValueType[:] {let result=owned_types.alloc_slice(source.len);for item,index in source {result[index]=item;}return result;}
fn copyBytes(source:const u8[:])->const u8[:] {let result=owned_bytes.alloc_slice(source.len);for item,index in source {result[index]=item;}return result;}
fn freeBytes(source:const u8[:]) {if source.len!=0 {let first:const u8&=source[0];let at=owned_bytes.index_of(first);owned_bytes.free_slice(owned_bytes[at..at+source.len]);}}
fn freeTypes(source:const ValueType[:]) {if source.len!=0 {let first:const ValueType&=source[0];let at=owned_types.index_of(first);owned_types.free_slice(owned_types[at..at+source.len]);}}
fn deinit(self:Entry&) {self.source.deinit();if self.parameters.len!=0 {owned_parameters.free_slice(self.parameters);}if self.output.present {self.output.value.deinit();}self=Entry{};}
fn deinit(self:Import&) {freeBytes(self.module);freeBytes(self.name);self=Import{};}
struct Entries {storage:Entry[:]=[],items:Entry[:]=[],len:i64=0,failure:Error=Error.none}
reusable[] var entries_pool:Entry[>..]=[];
fn ensure(self:Entries&,minimum:i64)->Error {if self.failure!=Error.none {return self.failure;}let error=blot_support_pooled_buffer::ensure(self,minimum,entries_pool);if error!=Error.none {self.failure=error;}return error;}
fn push(self:Entries&,value:Entry)->Error {if self.failure!=Error.none {return self.failure;}let error=blot_support_pooled_buffer::push(self,value,entries_pool);self.len=self.items.len;self.failure=error;return error;}
fn append(self:Entries&,values:const Entry[:])->Error {if self.failure!=Error.none {return self.failure;}let error=blot_support_pooled_buffer::append(self,values,entries_pool);self.len=self.items.len;self.failure=error;return error;}
fn clear(self:Entries&) {blot_support_pooled_buffer::clear(self);self.len=0;self.failure=Error.none;}
fn deinit(self:Entries&) {blot_support_pooled_buffer::deinit(self,entries_pool);self.len=0;self.failure=Error.none;}
struct Signatures {storage:Signature[:]=[],items:Signature[:]=[],len:i64=0,failure:Error=Error.none}
reusable[] var signatures_pool:Signature[>..]=[];
fn ensure(self:Signatures&,minimum:i64)->Error {if self.failure!=Error.none {return self.failure;}let error=blot_support_pooled_buffer::ensure(self,minimum,signatures_pool);if error!=Error.none {self.failure=error;}return error;}
fn push(self:Signatures&,value:Signature)->Error {if self.failure!=Error.none {return self.failure;}let error=blot_support_pooled_buffer::push(self,value,signatures_pool);self.len=self.items.len;self.failure=error;return error;}
fn append(self:Signatures&,values:const Signature[:])->Error {if self.failure!=Error.none {return self.failure;}let error=blot_support_pooled_buffer::append(self,values,signatures_pool);self.len=self.items.len;self.failure=error;return error;}
fn clear(self:Signatures&) {blot_support_pooled_buffer::clear(self);self.len=0;self.failure=Error.none;}
fn deinit(self:Signatures&) {blot_support_pooled_buffer::deinit(self,signatures_pool);self.len=0;self.failure=Error.none;}
struct Imports {storage:Import[:]=[],items:Import[:]=[],len:i64=0,failure:Error=Error.none}
reusable[] var imports_pool:Import[>..]=[];
fn ensure(self:Imports&,minimum:i64)->Error {if self.failure!=Error.none {return self.failure;}let error=blot_support_pooled_buffer::ensure(self,minimum,imports_pool);if error!=Error.none {self.failure=error;}return error;}
fn push(self:Imports&,value:Import)->Error {if self.failure!=Error.none {return self.failure;}let error=blot_support_pooled_buffer::push(self,value,imports_pool);self.len=self.items.len;self.failure=error;return error;}
fn append(self:Imports&,values:const Import[:])->Error {if self.failure!=Error.none {return self.failure;}let error=blot_support_pooled_buffer::append(self,values,imports_pool);self.len=self.items.len;self.failure=error;return error;}
fn clear(self:Imports&) {blot_support_pooled_buffer::clear(self);self.len=0;self.failure=Error.none;}
fn deinit(self:Imports&) {blot_support_pooled_buffer::deinit(self,imports_pool);self.len=0;self.failure=Error.none;}
struct Globals {storage:blot_backend_wasm::Global[:]=[],items:blot_backend_wasm::Global[:]=[],len:i64=0,failure:Error=Error.none}
reusable[] var globals_pool:blot_backend_wasm::Global[>..]=[];
fn ensure(self:Globals&,minimum:i64)->Error {if self.failure!=Error.none {return self.failure;}let error=blot_support_pooled_buffer::ensure(self,minimum,globals_pool);if error!=Error.none {self.failure=error;}return error;}
fn push(self:Globals&,value:blot_backend_wasm::Global)->Error {if self.failure!=Error.none {return self.failure;}let error=blot_support_pooled_buffer::push(self,value,globals_pool);self.len=self.items.len;self.failure=error;return error;}
fn append(self:Globals&,values:const blot_backend_wasm::Global[:])->Error {if self.failure!=Error.none {return self.failure;}let error=blot_support_pooled_buffer::append(self,values,globals_pool);self.len=self.items.len;self.failure=error;return error;}
fn clear(self:Globals&) {blot_support_pooled_buffer::clear(self);self.len=0;self.failure=Error.none;}
fn deinit(self:Globals&) {blot_support_pooled_buffer::deinit(self,globals_pool);self.len=0;self.failure=Error.none;}
struct Providers {storage:blot_backend_provider_modes::Mode[:]=[],items:blot_backend_provider_modes::Mode[:]=[],len:i64=0,failure:Error=Error.none}
reusable[] var providers_pool:blot_backend_provider_modes::Mode[>..]=[];
fn ensure(self:Providers&,minimum:i64)->Error {if self.failure!=Error.none {return self.failure;}let error=blot_support_pooled_buffer::ensure(self,minimum,providers_pool);if error!=Error.none {self.failure=error;}return error;}
fn push(self:Providers&,value:blot_backend_provider_modes::Mode)->Error {if self.failure!=Error.none {return self.failure;}let error=blot_support_pooled_buffer::push(self,value,providers_pool);self.len=self.items.len;self.failure=error;return error;}
fn append(self:Providers&,values:const blot_backend_provider_modes::Mode[:])->Error {if self.failure!=Error.none {return self.failure;}let error=blot_support_pooled_buffer::append(self,values,providers_pool);self.len=self.items.len;self.failure=error;return error;}
fn clear(self:Providers&) {blot_support_pooled_buffer::clear(self);self.len=0;self.failure=Error.none;}
fn deinit(self:Providers&) {blot_support_pooled_buffer::deinit(self,providers_pool);self.len=0;self.failure=Error.none;}
struct Encoded {storage:u8[:]=[],items:u8[:]=[],len:i64=0,failure:Error=Error.none}
reusable[] var encoded_pool:u8[>..]=[];
fn ensure(self:Encoded&,minimum:i64)->Error {if self.failure!=Error.none {return self.failure;}let error=blot_support_pooled_buffer::ensure(self,minimum,encoded_pool);if error!=Error.none {self.failure=error;}return error;}
fn push(self:Encoded&,value:u8)->Error {if self.failure!=Error.none {return self.failure;}let error=blot_support_pooled_buffer::push(self,value,encoded_pool);self.len=self.items.len;self.failure=error;return error;}
fn append(self:Encoded&,values:const u8[:])->Error {if self.failure!=Error.none {return self.failure;}let error=blot_support_pooled_buffer::append(self,values,encoded_pool);self.len=self.items.len;self.failure=error;return error;}
fn clear(self:Encoded&) {blot_support_pooled_buffer::clear(self);self.len=0;self.failure=Error.none;}
fn deinit(self:Encoded&) {blot_support_pooled_buffer::deinit(self,encoded_pool);self.len=0;self.failure=Error.none;}
struct State {live:bool=false,generation:u64=0,roots:bool=false,needs_roots:bool=false,root_slots:u32=0,tier:Tier=Tier.optimized,entries:Entries=Entries{},signatures:Signatures=Signatures{},imports:Imports=Imports{},globals:Globals=Globals{},arena:blot_support::Option<blot_backend_wasm::Arena>=blot_support::none<blot_backend_wasm::Arena>(),cohorts:blot_support::Option<blot_runtime_cohort_runtime::Runtime>=blot_support::none<blot_runtime_cohort_runtime::Runtime>(),fixture_helpers:blot_support::Option<u32[3]>=blot_support::none<u32[3]>(),regions:blot_support::Option<blot_runtime_region_runtime::Prepared>=blot_support::none<blot_runtime_region_runtime::Prepared>(),providers:Providers=Providers{},queries:blot_reuse_executable_query::OptimizerTable=blot_reuse_executable_query::OptimizerTable{adapter:blot_reuse_executable_query::OptimizerAdapter{},limits:blot_reuse_semantic_query_table::Limits{records:16384,retained_capacity:8388608}},queries_complete:bool=false,encoding:blot_support::Option<Encoding>=blot_support::none<Encoding>(),encoding_indexes:const u32[:]=[],encoded:Encoded=Encoded{}}
var inactive:State=State{};
reusable var states:State[>..]=[];
struct Capture {slot:u32=0,generation:u64=0,canonical:u32=0,
roots:(bool)&=inactive.roots,
needs_roots:(bool)&=inactive.needs_roots,
root_slots:(u32)&=inactive.root_slots,
tier:(Tier)&=inactive.tier,
entries:(Entries)&=inactive.entries,
signatures:(Signatures)&=inactive.signatures,
imports:(Imports)&=inactive.imports,
globals:(Globals)&=inactive.globals,
arena:(blot_support::Option<blot_backend_wasm::Arena>)&=inactive.arena,
cohorts:(blot_support::Option<blot_runtime_cohort_runtime::Runtime>)&=inactive.cohorts,
fixture_helpers:(blot_support::Option<u32[3]>)&=inactive.fixture_helpers,
regions:(blot_support::Option<blot_runtime_region_runtime::Prepared>)&=inactive.regions,
providers:(Providers)&=inactive.providers,
queries:(blot_reuse_executable_query::OptimizerTable)&=inactive.queries,
queries_complete:(bool)&=inactive.queries_complete,
encoding:(blot_support::Option<Encoding>)&=inactive.encoding,
encoding_indexes:(const u32[:])&=inactive.encoding_indexes,
encoded:(Encoded)&=inactive.encoded,
}
reusable var canonical_captures:Capture[>..]=[];
fn valid(self:const Capture&)->bool {return self.slot!=0 && self.slot-1<states.len && states[self.slot-1].live && states[self.slot-1].generation==self.generation;}
fn initPooled()->Capture,Error {if states.len>=0xffffffff {return Capture{},Error.out_of_memory;}let generation=blot_native::fresh_owner_id();let at=states.alloc_index(State{live:true,generation:generation});let state:State&=states[at];return Capture{slot:(at+1) as u32,generation:generation,roots:state.roots,needs_roots:state.needs_roots,root_slots:state.root_slots,tier:state.tier,entries:state.entries,signatures:state.signatures,imports:state.imports,globals:state.globals,arena:state.arena,cohorts:state.cohorts,fixture_helpers:state.fixture_helpers,regions:state.regions,providers:state.providers,queries:state.queries,queries_complete:state.queries_complete,encoding:state.encoding,encoding_indexes:state.encoding_indexes,encoded:state.encoded},Error.none;}
fn init()->Capture,Error {return initPooled();}
fn initPooledRef()->Capture?,Error {let value,error=initPooled();if error!=Error.none {return null,error;}let at=canonical_captures.alloc_index(value);canonical_captures[at].canonical=(at+1) as u32;return canonical_captures[at],Error.none;}
fn freeRegions(value:blot_runtime_region_runtime::Prepared) {if value.plan.members.len!=0 {let first:const blot_runtime_region_runtime::Member&=value.plan.members[0];let at=region_members.index_of(first);region_members.free_slice(region_members[at..at+value.plan.members.len]);}if value.scopes.len!=0 {let first:const blot_runtime_region_runtime::Scope&=value.scopes[0];let at=region_scopes.index_of(first);region_scopes.free_slice(region_scopes[at..at+value.scopes.len]);}}
fn clearOwned(self:Capture&) {
 if self.regions.present {freeRegions(self.regions.value);}self.regions=blot_support::none<blot_runtime_region_runtime::Prepared>();self.queries.deinit();if self.encoding_indexes.len!=0 {let first:const u32&=self.encoding_indexes[0];let at=owned_words.index_of(first);owned_words.free_slice(owned_words[at..at+self.encoding_indexes.len]);}self.encoding_indexes=[];self.encoded.deinit();for &entry in self.entries.items {entry.deinit();}self.entries.deinit();for signature in self.signatures.items {freeTypes(signature.parameters);}self.signatures.deinit();for &item in self.imports.items {item.deinit();}self.imports.deinit();self.globals.deinit();self.providers.deinit();
}
fn deinit(self:Capture&) {if self.slot==0 {return;}assert(self.valid());let at=self.slot-1;let canonical=self.canonical;self.clearOwned();states[at]=State{};states.free(at);self=Capture{};if canonical!=0 {canonical_captures[canonical-1]=Capture{};canonical_captures.free(canonical-1);}}
fn reset(self:Capture&)->Error {assert(self.valid());self.clearOwned();let generation=self.generation;let state:State&=states[self.slot-1];state=State{live:true,generation:generation};return Error.none;}
fn captureRegions(self:Capture&,regions:blot_support::Option<blot_runtime_region_runtime::Prepared>)->Error {assert(self.valid() && !self.regions.present);if !regions.present {return Error.none;}var context=regions.value;let members=region_members.alloc_slice(context.plan.members.len);for member,index in context.plan.members {members[index]=member;}let scopes=region_scopes.alloc_slice(context.scopes.len);for scope,index in context.scopes {scopes[index]=scope;}context.plan.members=members;context.scopes=scopes;self.regions=blot_support::some(context);return Error.none;}
fn recordInputs(self:Capture&,module:const blot_backend_wasm::Module&,summaries:const blot_backend_wasm_lifetimes::Summaries&)->Error {
 assert(self.entries.len==0 && self.signatures.len==0);self.arena=module.arena;self.cohorts=module.cohorts;self.fixture_helpers=module.fixture_helpers;let error=self.captureRegions(module.regions);if error!=Error.none {return error;}
 let error=self.entries.ensure(module.functions.len);if error!=Error.none {return error;}
 for function,index in module.functions {let summary=summaries.functions[index];let cloned,error=blot_backend_runtime_ir::cloneFunction(function,blot_backend_wasm::parameters(module,function),blot_backend_wasm::locals(module,function),blot_backend_wasm::instructions(module,function));if error!=Error.none {return error;}var source=cloned;let parameters=copyParameters(summary.parameters);let error=self.entries.push(Entry{source:source,parameters:parameters,invalidates:summary.invalidates,owned_result_bytes:summary.owned_result_bytes});if error!=Error.none {source.deinit();if parameters.len!=0 {owned_parameters.free_slice(parameters);}return error;}}
 let error=self.signatures.ensure(module.signatures.len);if error!=Error.none {return error;}for signature in module.signatures {let parameters=copyTypes(module.types[signature.parameters.start..signature.parameters.start+signature.parameters.len]);let error=self.signatures.push(Signature{parameters,signature.result});if error!=Error.none {freeTypes(parameters);return error;}}
 let error=self.imports.ensure(module.imports.len);if error!=Error.none {return error;}for item in module.imports {let namespace=copyBytes(item.module);let name=copyBytes(item.name);let error=self.imports.push(Import{namespace,name,item.signature});if error!=Error.none {freeBytes(namespace);freeBytes(name);return error;}}
 return self.globals.append(module.globals[:]);
}
fn recordOutput(self:Capture&,id:i64,body_result:blot_support::Option<Body>)->Error {assert(!self.entries.items[id].output.present);if body_result.present {let body,error=blot_backend_runtime_ir::cloneBody(body_result.value);if error!=Error.none {return error;}self.entries.items[id].output=blot_support::some(body);}self.entries.items[id].output_ready=true;return Error.none;}
fn recordEncoding(self:Capture&,context:Encoding,indexes:const u32[:])->Error {let owned=owned_words.alloc_slice(indexes.len);for index,at in indexes {owned[at]=index;}if self.encoding_indexes.len!=0 {let first:const u32&=self.encoding_indexes[0];let at=owned_words.index_of(first);owned_words.free_slice(owned_words[at..at+self.encoding_indexes.len]);}self.encoding_indexes=owned;self.encoding=blot_support::some(context);return Error.none;}
fn recordEncoded(self:Capture&,id:i64,bytes:const u8[:])->Error {let limit:i64=8388608;if bytes.len>limit-self.encoded.len {return Error.none;}let start=self.encoded.len;let error=self.encoded.append(bytes);if error!=Error.none {return error;}self.entries.items[id].encoded=EncodedRange{start,bytes.len};return Error.none;}
fn output(self:const Capture&,id:i64)->blot_support::Option<Body> {return self.entries.items[id].output;}
fn queryAt(self:const Capture&,id:i64)->const blot_reuse_executable_query::OptimizerRecord? {if !self.queries_complete || self.queries.limits.lookup_work==0 {return null;}var first:i64=0;var end=self.queries.records.len;while first<end {let middle=first+(end-first)/2;let record .= self.queries.records[middle];if record.value.function<id {first=middle+1;}else if record.value.function>id {end=middle;}else {return record;}}return null;}
fn sealQueries(self:Capture&)->Error {
 assert(self.queries.records.len==0 && !self.queries_complete);
 for entry,id in self.entries.items {if !entry.output_ready {continue;}var call_count:i64=0;for inst in entry.source.instructions {if inst.op==blot_backend_runtime_ir::OP_call || inst.table_reference {call_count++;}}let bytes=blot_reuse_executable_query::dependencyBytes<u32,Parameter>(call_count,entry.parameters.len);if !bytes.present || !self.queries.canAdmit(bytes.value) {self.queries.saturate();return Error.none;}
  var builder=self.queries.begin(blot_reuse_executable_query::OptimizerKey{local_fingerprint:blot_backend_runtime_body_relocation::hash(entry.source),tier:self.tier});defer {builder.abort();}let callees=owned_words.alloc_slice(call_count);var cursor:i64=0;for inst in entry.source.instructions {if inst.op==blot_backend_runtime_ir::OP_call || inst.table_reference {callees[cursor]=inst.operand;cursor++;}}
  let owned=blot_reuse_executable_query::copyCallees(callees);if callees.len!=0 {owned_words.free_slice(callees);}builder.read(blot_reuse_executable_query::OptimizerDependencies{callees:owned,parameters:blot_reuse_executable_query::copyParameters(entry.parameters),invalidates:entry.invalidates,owned_result_bytes:entry.owned_result_bytes,context_complete:true});builder.stage(blot_reuse_executable_query::OptimizerResult{id as u32,true});var candidate=builder.complete();assert(candidate.present);defer {candidate.value.abort();}let prepared,error=self.queries.prepare(candidate.value);if error!=Error.none {return error;}if !prepared.present {return Error.none;}let handle=self.queries.publish(prepared.value,candidate.value);
 }self.queries_complete=true;return Error.none;
}
fn bytes(self:const Capture&)->i64 {var count=self.entries.len*146+self.signatures.len*17+self.imports.len*36+self.globals.len*6+self.providers.len*7;for entry in self.entries.items {count+=entry.source.parameters.len+entry.source.locals.len+entry.source.instructions.len*7+entry.parameters.len*5;if entry.output.present {count+=entry.output.value.locals.len+entry.output.value.instructions.len*7;}}for signature in self.signatures.items {count+=signature.parameters.len;}for item in self.imports.items {count+=item.module.len+item.name.len;}if self.regions.present {count+=self.regions.value.plan.members.len*12+self.regions.value.scopes.len*12;}return count+self.queries.owned_bytes+self.queries.capacity_bytes+self.encoding_indexes.len*4+self.encoded.storage.len;}
