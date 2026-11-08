// Real copied check/lower processes. The coordinator alone publishes replies;
// private workers rebuild every source, producer, cache and solver owner.
namespace blot_project_executor;
import dictionary;
import support.project_packet;
import support.process_pool;
import support.error;
import support.option;
import support.native;
import support.core_packet;
import support.pooled_map;
import check.check;
import check.core;
import check.core_builder;
import check.frozen_core_validation;
import reuse.project;
import reuse.project_check;
import reuse.dependency_payload;
import reuse.dependency_interface_validation;
import reuse.body_check_cache;
import reuse.hole_diagnostics;
import reuse.dispatch_explanation;
import parse.ast;
import parse.symbols;
import work_counters;
import phase_profile;
type Error=blot_error::Error;
type Writer=blot_project_packet::Writer;
type Reader=blot_project_packet::Reader;
type PacketOwner=blot_project_packet::Owner;
type Project=blot_reuse_project::Project;
type Engine=blot_reuse_project_check::Engine;
type Job=blot_reuse_project_check::ParallelJob;
type Checked=blot_check_check::Checked;
type Core=blot_check_core::Module;
type OwnedCore=blot_reuse_dependency_payload::Owned<Core>;
let version:u32=1;
struct Executor {slot:u32=0,generation:u64=0}
struct LowerSlot {requested:bool=false,taken:bool=false,packet:u8[:]=default<u8[:]>(),output:OwnedCore=default<OwnedCore>(),failure:Error=blot_error::Error.none}
struct LowerState {live:bool=false,generation:u64=0,executed:bool=false,slots:LowerSlot[:]=default<LowerSlot[:]>()}
reusable var lower_states:LowerState[>..]=[];
reusable[] var lower_slots:LowerSlot[>..]=[];
reusable[] var packets:u8[>..]=[];
reusable[] var process_requests:blot_process_pool::Request[>..]=[];
fn init()->Executor {return Executor{..};}
fn valid(self_:Executor)->bool {return self_.slot!=0&&self_.slot-1<lower_states.len&&lower_states[self_.slot-1].live&&lower_states[self_.slot-1].generation==self_.generation;}
fn ownedPacket(bytes:const u8[:])->u8[:] {let result=packets.alloc_slice(bytes.len);for byte,index in bytes {result[index]=byte;}return result;}
fn releasePacket(bytes:u8[:]) {if bytes.len!=0 {packets.free_slice(bytes);}}
fn begin(self_:Executor&,length:i64)->Error {
 if self_.slot!=0||length<0||length>blot_project_packet::element_limit {return blot_error::Error.invalid_request;}if lower_states.len>=0xffffffff {return blot_error::Error.out_of_memory;}
 let slots=lower_slots.alloc_slice(length);for &slot in slots {slot=LowerSlot{..};}let generation=blot_native::fresh_owner_id();let at=lower_states.alloc_index(LowerState{live:true,generation:generation,slots:slots,..});self_=Executor{(at+1) as u32,generation};return blot_error::Error.none;
}
fn prepare(self_:Executor&,index:i64,tree:const blot_parse_ast::Tree&,names:const blot_parse_symbols::Pool&,checked:const Checked&,origins:blot_check_check::ModuleOrigins)->Error {
 if !self_.valid() {return blot_error::Error.invalid_request;}let state:LowerState& =lower_states[self_.slot-1];if state.executed||index<0||index>=state.slots.len||state.slots[index].requested {return blot_error::Error.invalid_request;}if origins.failure!=blot_error::Error.none {return origins.failure;}
 var output:u8[>..<]=[];var writer=Writer{output};blot_project_packet::put(writer,0x504c5751 as u32);blot_project_packet::put(writer,version);blot_project_packet::put(writer,blot_phase_profile::captureWorker());blot_project_packet::put(writer,index);blot_project_packet::put(writer,tree);blot_project_packet::put(writer,names);blot_project_packet::put(writer,checked);blot_project_packet::put(writer,origins);if writer.failure!=blot_error::Error.none {return writer.failure;}
 state.slots[index].packet=ownedPacket(output);state.slots[index].requested=true;return blot_error::Error.none;
}
fn execute(self_:Executor&,order:const u32[:],width:i64)->Error {
 if !self_.valid()||width<1||width>16 {return blot_error::Error.invalid_request;}let state:LowerState& =lower_states[self_.slot-1];if state.executed {return blot_error::Error.invalid_request;}
 let requests=process_requests.alloc_slice(order.len);for &request in requests {request=blot_process_pool::Request{bytes:[]};}
 for index,position in order {if index>=state.slots.len||!state.slots[index].requested {process_requests.free_slice(requests);return blot_error::Error.invalid_request;}for previous in order[..position] {if previous==index {process_requests.free_slice(requests);return blot_error::Error.invalid_request;}}requests[position]=blot_process_pool::Request{state.slots[index].packet};}
 state.executed=true;var replies,error=blot_process_pool::run(blot_process_pool::Kind.lower,requests,width as u8);process_requests.free_slice(requests);if error!=blot_error::Error.none {replies.deinit();return error;}if replies.items.len!=order.len {replies.deinit();return blot_error::Error.invalid_artifact;}
 var failure=blot_error::Error.none;for reply,position in replies.items {let slot:LowerSlot& =state.slots[order[position]];if reply.failure!=blot_error::Error.none {slot.failure=reply.failure;continue;}let decoded,error=decodeLowerReply(reply.bytes,order[position] as i64);if error!=blot_error::Error.none {slot.failure=error;if failure==blot_error::Error.none {failure=error;}}else {slot.output=decoded;}}
 replies.deinit();return failure;
}
fn take(self_:Executor&,index:i64)->OwnedCore,Error {if !self_.valid() {return default<OwnedCore>(),blot_error::Error.invalid_artifact;}let state:LowerState& =lower_states[self_.slot-1];if !state.executed||index<0||index>=state.slots.len||!state.slots[index].requested||state.slots[index].taken {return default<OwnedCore>(),blot_error::Error.invalid_artifact;}let slot:LowerSlot& =state.slots[index];slot.taken=true;let value=slot.output;slot.output=default<OwnedCore>();return value,slot.failure;}
fn discard(self_:Executor&,index:i64) {assert(self_.valid());let state:LowerState& =lower_states[self_.slot-1];assert(index>=0&&index<state.slots.len);let slot:LowerSlot& =state.slots[index];if !slot.taken {slot.output.deinit();slot.taken=true;}}
fn cancelAndJoin(self_:Executor&) {blot_process_pool::shutdown();}
fn deinit(self_:Executor&) {if self_.slot==0 {return;}assert(self_.valid());let at=self_.slot-1;let state:LowerState& =lower_states[at];for &slot in state.slots {if !slot.taken {slot.output.deinit();}releasePacket(slot.packet);slot=LowerSlot{..};}if state.slots.len!=0 {lower_slots.free_slice(state.slots);}state=LowerState{..};lower_states.free(at);self_=Executor{..};}
fn cancelProjectChecks(self_:Executor&) {blot_process_pool::shutdown();}

// Execution policy contains no observer/function identity in admitted parallel
// batches. Every actual scalar setting is still copied into the private job.
fn putExecution(writer:Writer&,execution:blot_check_check::PrivateExecution)->Error {if execution.stats!=null||execution.observe!=null {return blot_error::Error.invalid_request;}blot_project_packet::put(writer,execution.parallel_min_nodes);blot_project_packet::put(writer,execution.scheme_dependency_reuse);blot_project_packet::put(writer,execution.indexed_scheme_membership);blot_project_packet::put(writer,execution.closed_array_locals);blot_project_packet::put(writer,execution.eager_scheme_summaries);blot_project_packet::put(writer,execution.imported_summary_reuse);blot_project_packet::put(writer,execution.alias_globals);blot_project_packet::put(writer,execution.schedule_globals);return writer.failure;}
fn getExecution(reader:Reader&)->blot_check_check::PrivateExecution {var execution=blot_check_check::PrivateExecution{..};blot_project_packet::get(reader,execution.parallel_min_nodes);blot_project_packet::get(reader,execution.scheme_dependency_reuse);blot_project_packet::get(reader,execution.indexed_scheme_membership);blot_project_packet::get(reader,execution.closed_array_locals);blot_project_packet::get(reader,execution.eager_scheme_summaries);blot_project_packet::get(reader,execution.imported_summary_reuse);blot_project_packet::get(reader,execution.alias_globals);blot_project_packet::get(reader,execution.schedule_globals);return execution;}
fn putProject(writer:Writer&,source:const Project&) {
 blot_project_packet::put(writer,source.input_mode);blot_project_packet::put(writer,source.symbols);blot_project_packet::put(writer,source.entry);blot_project_packet::put(writer,source.prelude_unit);blot_project_packet::put(writer,source.source_bytes);blot_project_packet::put(writer,source.lowering);blot_project_packet::put(writer,source.checking);
 blot_project_packet::count(writer,source.units.len);for unit in source.units.items {blot_project_packet::put(writer,unit.filename);blot_project_packet::put(writer,unit.source);blot_project_packet::put(writer,unit.tree);blot_project_packet::put(writer,unit.imports);blot_project_packet::put(writer,unit.implicit_prelude);}
 blot_project_packet::put(writer,source.order.items);blot_project_packet::put(writer,source.imports.items);blot_project_packet::put(writer,source.diagnostics.items);blot_project_packet::put(writer,source.compiled_modules);blot_project_packet::put(writer,source.compiled_reuse);
}
fn getProject(reader:Reader&,source:Project&)->Error {
 let project,error=blot_reuse_project::init();if error!=blot_error::Error.none {return error;}source=project;source.symbols.deinit();blot_project_packet::get(reader,source.input_mode);blot_project_packet::get(reader,source.symbols);blot_project_packet::get(reader,source.entry);blot_project_packet::get(reader,source.prelude_unit);blot_project_packet::get(reader,source.source_bytes);blot_project_packet::get(reader,source.lowering);blot_project_packet::get(reader,source.checking);let length=blot_project_packet::count(reader);
 for index in length {var filename:u32=0;var bytes:u8[:]=default<u8[:]>();var tree=blot_parse_ast::Tree{..};var imports=blot_reuse_project::Range{..};var prelude=false;blot_project_packet::get(reader,filename);blot_project_packet::get(reader,bytes);blot_project_packet::get(reader,tree);blot_project_packet::get(reader,imports);blot_project_packet::get(reader,prelude);if reader.failure!=blot_error::Error.none {tree.deinit();return reader.failure;}if filename>source.symbols.entries.len {tree.deinit();return blot_error::Error.invalid_artifact;}let copied=blot_reuse_project::copySource(bytes);source.units.push(blot_reuse_project::Unit{filename,copied,tree,imports,prelude});if source.units.failure!=blot_error::Error.none {var unit=blot_reuse_project::Unit{filename,copied,tree,imports,prelude};unit.deinit();return source.units.failure;}}
 var order:u32[:]=default<u32[:]>();var imports:blot_reuse_project::Import[:]=default<blot_reuse_project::Import[:]>();var diagnostics:blot_reuse_project::Diagnostic[:]=default<blot_reuse_project::Diagnostic[:]>();blot_project_packet::get(reader,order);blot_project_packet::get(reader,imports);blot_project_packet::get(reader,diagnostics);blot_project_packet::get(reader,source.compiled_modules);blot_project_packet::get(reader,source.compiled_reuse);if reader.failure!=blot_error::Error.none {return reader.failure;}
 source.order.append(order);source.imports.append(imports);for diagnostic in diagnostics {var value=diagnostic;value.lexical_details=blot_reuse_project::copyLexical(diagnostic.lexical_details);source.diagnostics.push(value);if source.diagnostics.failure!=blot_error::Error.none {blot_reuse_project::releaseLexical(value.lexical_details);return source.diagnostics.failure;}}
 if source.order.failure!=blot_error::Error.none {return source.order.failure;}if source.imports.failure!=blot_error::Error.none {return source.imports.failure;}if source.entry==0||source.entry>source.units.len||source.prelude_unit>source.units.len||source.source_bytes<0||source.compiled_modules.len>source.units.len {return blot_error::Error.invalid_artifact;}if source.compiled_reuse.len!=0&&source.compiled_reuse.len!=source.compiled_modules.len {return blot_error::Error.invalid_artifact;}
 for unit in source.order.items {if unit==0||unit>source.units.len {return blot_error::Error.invalid_artifact;}}for unit in source.units.items {if unit.imports.start>source.imports.len||unit.imports.len>source.imports.len-unit.imports.start {return blot_error::Error.invalid_artifact;}}for imported in source.imports.items {if imported.target==0||imported.target>source.units.len {return blot_error::Error.invalid_artifact;}}
 return validateCompiled(source);
}
fn validateCompiled(source:const Project&)->Error {
 var refs:blot_check_frozen_core_validation::ModuleRef[>..]=[];for &module in source.compiled_modules {refs.push(blot_check_frozen_core_validation::ModuleRef{module.core});}
 let context=blot_check_frozen_core_validation::Context{units:refs[..],symbol_count:blot_support::some(source.symbols.entries.len+1),source_length:blot_support::none<u32>(),forbidden_owner:blot_support::none<u32>()};var spawn=false;for module in source.compiled_modules {spawn=spawn||blot_check_frozen_core_validation::moduleHasSpawnContracts(module.core);}let batch=blot_check_frozen_core_validation::Batch{context,spawn};var remaining:i64=0x7fffffffffffffff;
 for module in source.compiled_modules {let error=batch.validateWithBudget(module.core,blot_support::none<u32>(),remaining);if error!=blot_error::Error.none {return error;}let error=blot_reuse_dependency_interface_validation::validate(module.interface,source.symbols.entries.len+1,source.units.len);if error!=blot_error::Error.none {return error;}let error=blot_reuse_dependency_interface_validation::validateGraph(module.interface);if error!=blot_error::Error.none {return error;}}return blot_error::Error.none;
}
fn putModule(writer:Writer&,module:blot_reuse_project_check::Module) {blot_project_packet::put(writer,module.checked);blot_project_packet::put(writer,module.exports);blot_project_packet::put(writer,module.valid);}
fn getModule(reader:Reader&)->blot_reuse_project_check::Module,Error {var checked=default<Checked>();var exports:blot_reuse_project_check::Export[:]=default<blot_reuse_project_check::Export[:]>();var valid=false;blot_project_packet::get(reader,checked);blot_project_packet::get(reader,exports);blot_project_packet::get(reader,valid);if reader.failure!=blot_error::Error.none {checked.deinit();return default<blot_reuse_project_check::Module>(),reader.failure;}return blot_reuse_project_check::Module{checked,blot_reuse_project_check::copyOwned(exports),valid},blot_error::Error.none;}
struct CheckRequest {owner:PacketOwner=PacketOwner{..},source:Project=Project{..},engine:Engine?=null,offers:blot_reuse_body_check_cache::Cache[:]=default<blot_reuse_body_check_cache::Cache[:]>()}
fn deinit(self_:CheckRequest&) {if self_.engine {let engine .= self_.engine;assert(engine);engine.deinit();self_.engine .= null;}for &cache in self_.offers {cache.deinit();}self_.source.symbols.read_only=false;self_.source.deinit();self_.owner.deinit();self_=CheckRequest{..};}
fn putEngine(writer:Writer&,parent:const Engine&)->Error {
 if parent.source_validation||parent.source_modules.len!=0 {return blot_error::Error.invalid_request;}match parent.editor {none=>{},_=>{return blot_error::Error.invalid_request;},}
 putProject(writer,parent.source);let error=putExecution(writer,parent.execution);if error!=blot_error::Error.none {return error;}blot_project_packet::put(writer,parent.retain_bodies);blot_project_packet::put(writer,parent.prepare_names);blot_project_packet::put(writer,parent.resolution_remaining);blot_project_packet::put(writer,parent.associated_remaining);
 blot_project_packet::count(writer,parent.result.modules.len);for item in parent.result.modules {blot_project_packet::put(writer,item.present);if item.present {putModule(writer,item.value);}}
 blot_project_packet::count(writer,parent.result.body_caches.len);for cache in parent.result.body_caches {blot_project_packet::put(writer,cache);}blot_project_packet::put(writer,parent.result.body_elaborations);blot_project_packet::put(writer,parent.result.imported_schemes);blot_project_packet::put(writer,parent.result.normalization);
 // Current Project symbol IDs retain filename identity across the copied symbol table.
 // Empty offers retain ambiguity; cache ownership is reconstructed in the child.
 blot_project_packet::count(writer,parent.previous_bodies.count);for slot in parent.previous_bodies.slots {if slot.tag==0 {continue;}blot_project_packet::put(writer,slot.key);let cache .= parent.offeredBody(slot.key);blot_project_packet::put(writer,cache!=null);if cache {let value:const blot_reuse_body_check_cache::Cache& =cache;blot_project_packet::put(writer,value);}}
 return writer.failure;
}
fn getEngine(reader:Reader&,context:CheckRequest)->CheckRequest,Error {
 let error=getProject(reader,context.source);if error!=blot_error::Error.none {return context,error;}let execution=getExecution(reader);var retain=false;var prepare=false;var resolution:i64=0;var associated:i64=0;blot_project_packet::get(reader,retain);blot_project_packet::get(reader,prepare);blot_project_packet::get(reader,resolution);blot_project_packet::get(reader,associated);if reader.failure!=blot_error::Error.none {return context,reader.failure;}if resolution<0||associated<0 {return context,blot_error::Error.invalid_artifact;}
 let engine,error=blot_reuse_project_check::initEngine(context.source,execution,blot_reuse_project_check::Editor.none,retain);if error!=blot_error::Error.none {return context,error;}assert(engine);context.engine .= engine;engine.prepare_names=prepare;engine.resolution_remaining=resolution;engine.associated_remaining=associated;let module_count=blot_project_packet::count(reader);if module_count!=context.source.units.len {return context,blot_error::Error.invalid_artifact;}let allocated=engine.result.allocateModules(module_count,retain);if allocated!=blot_error::Error.none {return context,allocated;}
 for index in module_count {var present=false;blot_project_packet::get(reader,present);if reader.failure!=blot_error::Error.none {return context,reader.failure;}if present {let module,error=getModule(reader);if error!=blot_error::Error.none {return context,error;}engine.result.modules[index]=blot_support::some(module);}}
 let caches=blot_project_packet::count(reader);if caches!=engine.result.body_caches.len {return context,blot_error::Error.invalid_artifact;}for index in caches {blot_project_packet::get(reader,engine.result.body_caches[index]);if reader.failure!=blot_error::Error.none {return context,reader.failure;}}
 blot_project_packet::get(reader,engine.result.body_elaborations);blot_project_packet::get(reader,engine.result.imported_schemes);blot_project_packet::get(reader,engine.result.normalization);let count=blot_project_packet::count(reader);let offers,error=blot_project_packet::allocate(reader.owner,count,default<blot_reuse_body_check_cache::Cache>());if error!=blot_error::Error.none {return context,error;}context.offers=offers;
 for index in count {var filename:u32=0;var present=false;blot_project_packet::get(reader,filename);blot_project_packet::get(reader,present);if reader.failure!=blot_error::Error.none {return context,reader.failure;}if filename==0||filename>context.source.symbols.entries.len {return context,blot_error::Error.invalid_artifact;}var offer=blot_reuse_project_check::BodyOffer{..};if present {blot_project_packet::get(reader,context.offers[index]);if reader.failure!=blot_error::Error.none {return context,reader.failure;}let cache=context.offers[index];offer=blot_reuse_project_check::BodyOffer{cache.lease,cache.generation};}blot_support_pooled_map::insert(engine.previous_bodies,filename,offer,blot_reuse_project_check::offer_slots);}
 if reader.failure!=blot_error::Error.none {return context,reader.failure;}return context,engine.initCompiledCatalogs();
}

fn encodeCheck(parent:const Engine&,unit:u32)->u8[:],Error {
 if unit==0||unit>parent.source.units.len {return default<u8[:]>(),blot_error::Error.invalid_request;}var output:u8[>..<]=[];var writer=Writer{output};blot_project_packet::put(writer,0x50435751 as u32);blot_project_packet::put(writer,version);blot_project_packet::put(writer,blot_phase_profile::captureWorker());blot_project_packet::put(writer,unit);let error=putEngine(writer,parent);if error!=blot_error::Error.none {return default<u8[:]>(),error;}return ownedPacket(output),blot_error::Error.none;
}
fn runProjectChecks(self_:Executor&,parent:Engine&,order:const u32[:],width:i64,jobs:Job[:])->blot_work_counters::Frontend,Error {
 var totals=blot_work_counters::Frontend{..};if width<1||width>16||jobs.len!=parent.source.units.len {return totals,blot_error::Error.invalid_request;}let started=blot_native::clock_ns();let requests=process_requests.alloc_slice(order.len);for &request in requests {request=blot_process_pool::Request{bytes:[]};}
 var made:i64=0;for unit,position in order {if unit==0||unit>jobs.len {releaseCheckRequests(requests,made);return totals,blot_error::Error.invalid_request;}for previous in order[..position] {if previous==unit {releaseCheckRequests(requests,made);return totals,blot_error::Error.invalid_request;}}let packet,error=encodeCheck(parent,unit);if error!=blot_error::Error.none {releaseCheckRequests(requests,made);return totals,error;}requests[position]=blot_process_pool::Request{packet};made++;}
 let prepared=blot_native::clock_ns();if prepared>=started {totals.parallel_capacity_us=(prepared-started)/1000;}var replies,error=blot_process_pool::run(blot_process_pool::Kind.check,requests,width as u8);releaseCheckRequests(requests,made);if error!=blot_error::Error.none {replies.deinit();return totals,error;}if replies.items.len!=order.len {replies.deinit();return totals,blot_error::Error.invalid_artifact;}
 var failure=blot_error::Error.none;for reply,position in replies.items {let unit=order[position];let job:Job& =jobs[unit-1];job.deinit();if reply.failure!=blot_error::Error.none {job.failure=reply.failure;continue;}let error=decodeCheckReply(parent,unit,reply.bytes,job);if error!=blot_error::Error.none {job.deinit();job.failure=error;if failure==blot_error::Error.none {failure=error;}}}
 replies.deinit();let ended=blot_native::clock_ns();if ended>=prepared {totals.parallel_batch_us=(ended-prepared)/1000;}totals.parallel_worker_slots=width as u64;totals.parallel_worker_jobs=order.len as u64;return totals,failure;
}
fn releaseCheckRequests(requests:blot_process_pool::Request[:],made:i64) {for request in requests[..made] {if request.bytes.len!=0 {packets.free_slice(request.bytes);}}process_requests.free_slice(requests);}
fn cloneDiagnostic(parent:const Engine&,source:blot_reuse_project_check::Diagnostic)->blot_reuse_project_check::Diagnostic,Error {
 var value=source;value.detail=blot_support::none<const u8[:]>();value.purity=blot_support::none<blot_check_check::PurityWitness>();value.hole=blot_support::none<blot_reuse_hole_diagnostics::Snapshot>();value.explanation=blot_support::none<blot_reuse_dispatch_explanation::Explanation>();
 if source.source.present {var found=false;let old=source.source.value;for original in parent.source.diagnostics.items {if old.unit!=original.unit||old.span!=original.span||old.code!=original.code||old.target!=original.target {continue;}if old.lexical_details!=original.lexical_details {continue;}value.source=blot_support::some(original);found=true;break;}if !found {return default<blot_reuse_project_check::Diagnostic>(),blot_error::Error.invalid_artifact;}}
 if source.detail.present {value.detail=blot_support::some<const u8[:]>(blot_reuse_project_check::copyOwned(source.detail.value));}if source.purity.present {var witness=source.purity.value;if witness.operation_name.present {witness.operation_name=blot_support::some<const u8[:]>(blot_reuse_project_check::copyOwned(witness.operation_name.value));}value.purity=blot_support::some(witness);}
 if source.hole.present {let hole,error=source.hole.value.clone();if error!=blot_error::Error.none {value.deinit();return default<blot_reuse_project_check::Diagnostic>(),error;}value.hole=blot_support::some(hole);}if source.explanation.present {let explanation,error=source.explanation.value.clone();if error!=blot_error::Error.none {value.deinit();return default<blot_reuse_project_check::Diagnostic>(),error;}value.explanation=blot_support::some(explanation);}return value,blot_error::Error.none;
}
fn decodeCheckReply(parent:const Engine&,unit:u32,bytes:const u8[:],job:Job&)->Error {
 var owner,error=blot_project_packet::initOwner();if error!=blot_error::Error.none {return error;}var reader=Reader{bytes,owner};var signature:u32=0;var schema:u32=0;var actual:u32=0;var telemetry=blot_phase_profile::WorkerSnapshot{..};blot_project_packet::get(reader,signature);blot_project_packet::get(reader,schema);blot_project_packet::get(reader,actual);blot_project_packet::get(reader,telemetry);if reader.failure!=blot_error::Error.none||signature!=0x50435752||schema!=version||actual!=unit {owner.deinit();return blot_error::Error.invalid_artifact;}
 blot_project_packet::get(reader,job.work);blot_project_packet::get(reader,job.failure);blot_project_packet::get(reader,job.missing_name);blot_project_packet::get(reader,job.resolution_used);blot_project_packet::get(reader,job.associated_used);var diagnostics:blot_reuse_project_check::Diagnostic[:]=default<blot_reuse_project_check::Diagnostic[:]>();blot_project_packet::get(reader,diagnostics);if reader.failure!=blot_error::Error.none {owner.deinit();return reader.failure;}
 job.diagnostics=blot_reuse_project_check::owned_Diagnostic.alloc_slice(diagnostics.len);for &diagnostic in job.diagnostics {diagnostic=default<blot_reuse_project_check::Diagnostic>();}for diagnostic,index in diagnostics {let copied,error=cloneDiagnostic(parent,diagnostic);if error!=blot_error::Error.none {job.deinit();owner.deinit();return error;}job.diagnostics[index]=copied;}
 var present=false;blot_project_packet::get(reader,present);if present&&reader.failure==blot_error::Error.none {let module,error=getModule(reader);if error!=blot_error::Error.none {job.deinit();owner.deinit();return error;}job.module=blot_support::some(module);}blot_project_packet::get(reader,job.cache);
 if reader.failure!=blot_error::Error.none||reader.at!=reader.bytes.len||job.resolution_used<0||job.associated_used<0 {var failure=reader.failure;if failure==blot_error::Error.none {failure=blot_error::Error.invalid_artifact;}job.deinit();owner.deinit();return failure;}owner.deinit();blot_phase_profile::mergeWorker(telemetry);return blot_error::Error.none;
}
fn writeJob(writer:Writer&,unit:u32,job:const Job&,telemetry:blot_phase_profile::WorkerSnapshot) {
 blot_project_packet::put(writer,0x50435752 as u32);blot_project_packet::put(writer,version);blot_project_packet::put(writer,unit);blot_project_packet::put(writer,telemetry);blot_project_packet::put(writer,job.work);blot_project_packet::put(writer,job.failure);blot_project_packet::put(writer,job.missing_name);blot_project_packet::put(writer,job.resolution_used);blot_project_packet::put(writer,job.associated_used);blot_project_packet::put(writer,job.diagnostics);blot_project_packet::put(writer,job.module.present);if job.module.present {putModule(writer,job.module.value);}blot_project_packet::put(writer,job.cache);
}
// Called only by Kind.check in the process dispatcher. No parent Engine,
// Project reference, callback or cache handle is accepted as wire authority.
fn executeCheckPacket(bytes:const u8[:],output:u8[>..<]&)->Error {
 var owner,error=blot_project_packet::initOwner();if error!=blot_error::Error.none {return error;}var context=CheckRequest{owner:owner,..};var reader=Reader{bytes,owner};var signature:u32=0;var schema:u32=0;var unit:u32=0;var telemetry=blot_phase_profile::WorkerContext{..};blot_project_packet::get(reader,signature);blot_project_packet::get(reader,schema);blot_project_packet::get(reader,telemetry);blot_project_packet::get(reader,unit);if reader.failure!=blot_error::Error.none||signature!=0x50435751||schema!=version {context.deinit();return blot_error::Error.invalid_artifact;}
 context,error=getEngine(reader,context);if error!=blot_error::Error.none||reader.at!=reader.bytes.len||unit==0||unit>context.source.units.len {var failure=error;if failure==blot_error::Error.none {failure=blot_error::Error.invalid_artifact;}context.deinit();return failure;}assert(context.engine);var installation=blot_phase_profile::beginWorker(telemetry);var job=Job{..};let wall=blot_native::clock_ns();let cpu=blot_native::thread_cpu_ns();let error=blot_reuse_project_check::executeProjectJob(context.engine,unit,job);let stopped=blot_native::clock_ns();let cpu_stopped=blot_native::thread_cpu_ns();if stopped>=wall {job.work.parallel_worker_us=blot_work_counters::saturating_add(job.work.parallel_worker_us,(stopped-wall)/1000);}if cpu_stopped>=cpu&&blot_native::thread_cpu_available() {job.work.parallel_worker_cpu_us=blot_work_counters::saturating_add(job.work.parallel_worker_cpu_us,(cpu_stopped-cpu)/1000);job.work.parallel_worker_cpu_samples++;}
 let snapshot=installation.finish();if error!=blot_error::Error.none {job.deinit();context.deinit();return error;}var writer=Writer{output};writeJob(writer,unit,job,snapshot);job.deinit();context.deinit();return writer.failure;
}

struct LowerRequest {owner:PacketOwner=PacketOwner{..},tree:blot_parse_ast::Tree=blot_parse_ast::Tree{..},names:blot_parse_symbols::Pool=blot_parse_symbols::Pool{..},checked:Checked=default<Checked>(),origins:blot_check_check::ModuleOrigins=blot_check_check::ModuleOrigins{..},index:i64=0}
fn deinit(self_:LowerRequest&) {self_.checked.deinit();self_.tree.deinit();self_.names.read_only=false;self_.names.deinit();self_.owner.deinit();self_=LowerRequest{..};}
// Called only by Kind.lower. The result is a real owned Core module produced by
// CoreBuilder, serialized before any private checker/tree owners are released.
fn executeLowerPacket(bytes:const u8[:],output:u8[>..<]&)->Error {
 var owner,error=blot_project_packet::initOwner();if error!=blot_error::Error.none {return error;}var context=LowerRequest{owner:owner,..};var reader=Reader{bytes,owner};var signature:u32=0;var schema:u32=0;var telemetry=blot_phase_profile::WorkerContext{..};blot_project_packet::get(reader,signature);blot_project_packet::get(reader,schema);blot_project_packet::get(reader,telemetry);blot_project_packet::get(reader,context.index);blot_project_packet::get(reader,context.tree);blot_project_packet::get(reader,context.names);blot_project_packet::get(reader,context.checked);blot_project_packet::get(reader,context.origins);
 if reader.failure!=blot_error::Error.none||reader.at!=reader.bytes.len||signature!=0x504c5751||schema!=version||context.index<0 {var failure=reader.failure;if failure==blot_error::Error.none {failure=blot_error::Error.invalid_artifact;}context.deinit();return failure;}if context.origins.failure!=blot_error::Error.none {let failure=context.origins.failure;context.deinit();return failure;}
 var installation=blot_phase_profile::beginWorker(telemetry);var lowered,error=blot_check_core_builder::lowerWithOrigins(context.tree,context.names,context.checked,context.origins);let snapshot=installation.finish();if error!=blot_error::Error.none {context.deinit();return error;}
 var writer=Writer{output};blot_project_packet::put(writer,0x504c5752 as u32);blot_project_packet::put(writer,version);blot_project_packet::put(writer,context.index);blot_project_packet::put(writer,snapshot);var encoded:u8[>..<]=[];let encoded_error=blot_core_packet::encode(lowered.value,encoded);if encoded_error==blot_error::Error.none {blot_project_packet::put(writer,encoded[..]);}lowered.deinit();context.deinit();if encoded_error!=blot_error::Error.none {return encoded_error;}return writer.failure;
}
fn decodeLowerReply(bytes:const u8[:],index:i64)->OwnedCore,Error {
 var owner,error=blot_project_packet::initOwner();if error!=blot_error::Error.none {return default<OwnedCore>(),error;}var reader=Reader{bytes,owner};var signature:u32=0;var schema:u32=0;var actual:i64=0;var telemetry=blot_phase_profile::WorkerSnapshot{..};var encoded:u8[:]=default<u8[:]>();blot_project_packet::get(reader,signature);blot_project_packet::get(reader,schema);blot_project_packet::get(reader,actual);blot_project_packet::get(reader,telemetry);blot_project_packet::get(reader,encoded);if reader.failure!=blot_error::Error.none||reader.at!=reader.bytes.len||signature!=0x504c5752||schema!=version||index!=actual {owner.deinit();return default<OwnedCore>(),blot_error::Error.invalid_artifact;}
 var packet,error=blot_core_packet::decode(encoded);if error!=blot_error::Error.none {owner.deinit();return default<OwnedCore>(),error;}let core,error=blot_reuse_dependency_payload::clone(packet.module);packet.deinit();owner.deinit();if error!=blot_error::Error.none {return default<OwnedCore>(),error;}blot_phase_profile::mergeWorker(telemetry);return core,blot_error::Error.none;
}
