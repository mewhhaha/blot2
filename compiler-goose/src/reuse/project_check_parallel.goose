// Ready batches cross a copied executor boundary; publication remains ordered.
namespace blot_reuse_project_check;
import .project_check;
import check.source_sort;
struct ParallelJob {
 work:blot_work_counters::Frontend=blot_work_counters::Frontend{..},diagnostics:Diagnostic[:]=default<Diagnostic[:]>(),failure:Error=blot_error::Error.none,missing_name:bool=false,resolution_used:i64=0,associated_used:i64=0,
 module:blot_support::Option<Module> =blot_support::none<Module>(),cache:blot_reuse_body_check_cache::Cache=blot_reuse_body_check_cache::Cache{..},
}
reusable[] var project_jobs:ParallelJob[>..]=[];
fn deinit(self_:ParallelJob&) {for &diagnostic in self_.diagnostics {diagnostic.deinit();}releaseOwned(self_.diagnostics);if self_.module.present {self_.module.value.deinit();}self_.cache.deinit();self_=ParallelJob{..};}
fn parallelReady(source:Project,unit:u32,done:const bool[:])->bool {for imported in source.unitImports(unit) {if !done[imported.target-1] && source.compiledModule(imported.target)==null {return false;}}if source.unit(unit).implicit_prelude && source.prelude_unit!=0 && source.prelude_unit!=unit {let prelude=source.prelude_unit;if !done[prelude-1] && source.compiledModule(prelude)==null {return false;}}return true;}
struct WorkOrder {source:Project,units:u32[:]}
fn lessThan(self_:WorkOrder,left:i64,right:i64)->bool {let l=self_.units[left];let r=self_.units[right];let a=self_.source.unit(l).tree.nodes.len;let b=self_.source.unit(r).tree.nodes.len;if a!=b {return a>b;}return l<r;}
fn swap(self_:WorkOrder,left:i64,right:i64) {let value=self_.units[left];self_.units[left]=self_.units[right];self_.units[right]=value;}
type ParallelUnits=blot_support_pooled_buffer::Buffer<u32>;
reusable[] var parallel_unit_runs:u32[>..]=[];
fn prepareReadyUnits(source:Project,done:const bool[:],deferrable:bool,ready:ParallelUnits&)->Error {
 blot_support_pooled_buffer::clear(ready);for unit in source.order.items {if done[unit-1] || (deferrable && unit==source.entry) {continue;}if parallelReady(source,unit,done) {let error=blot_support_pooled_buffer::push(ready,unit,parallel_unit_runs);if error!=blot_error::Error.none {return error;}}}return blot_error::Error.none;
}
fn prepareWorkOrder(source:Project,ready:const u32[:],work:ParallelUnits&)->Error {
 blot_support_pooled_buffer::clear(work);let error=blot_support_pooled_buffer::append(work,ready,parallel_unit_runs);if error!=blot_error::Error.none {return error;}
 let canonical=parallel_unit_runs.realloc_slice(work.storage,work.storage.len);assert(blot_support::same_slice_identity(canonical,work.storage));blot_check_source_sort::pdqContext(0,work.items.len,WorkOrder{source,canonical[..work.items.len], ..});return blot_error::Error.none;
}
fn discardParallel(self_:Engine&,resolution:i64,associated:i64) {
 for &slot in self_.result.modules {if slot.present {slot.value.deinit();slot=blot_support::none<Module>();}}
 for &cache in self_.result.body_caches {cache.deinit();cache=blot_reuse_body_check_cache::Cache{..};}
 self_.result.body_elaborations=0;self_.result.imported_schemes=0;self_.result.normalization=blot_work_counters::Normalization{..};self_.resolution_remaining=resolution;self_.associated_remaining=associated;blot_phase_profile::recordChecking(blot_work_counters::Frontend{parallel_retries:1, ..});
}
// The worker borrows producer/result headers for the joined invocation.
fn borrowWorker(parent:const Engine&)->Engine {
 var worker=copy(parent);worker.diagnostics=DiagnosticBuffer{..};worker.result.body_elaborations=0;worker.result.imported_schemes=0;worker.result.normalization=blot_work_counters::Normalization{..};return worker;
}
// Only worker diagnostics are owned here; result/catalog/editor views stay borrowed.
fn discardWorker(worker:Engine&) {worker.deinitDiagnostics();worker=Engine{..};}
fn prepareParallelNames(parent:Engine&,units:const u32[:])->bool,Error {
 let started=blot_native::clock_ns();let trace=blot_phase_profile::currentTrace()!=null;var accepted=true;var failure=blot_error::Error.none;
 for unit in units {var worker=borrowWorker(parent);worker.prepare_names=true;let error=worker.checkModule(unit);let rejected=worker.diagnostics.items.len!=0;discardWorker(worker);if error!=blot_error::Error.none {failure=error;break;}if rejected {accepted=false;break;}}
 if trace {let ended=blot_native::clock_ns();var elapsed:u64=0;if ended>=started {elapsed=(ended-started)/1000;}blot_phase_profile::recordChecking(blot_work_counters::Frontend{parallel_prepare_us:elapsed, ..});}return accepted,failure;
}
// The copied-worker executor invokes this exact program in its private context;
// its reply owns all new tables and carries no borrowed Engine or producer ref.
fn executeProjectJob(parent:Engine&,unit:u32,job:ParallelJob&)->Error {
 var worker=borrowWorker(parent);worker.source.symbols.read_only=true;worker.source.symbols.missing_name=false;let capture=blot_phase_profile::captureChecking(job.work);job.failure=worker.checkModule(unit);capture.restore(job.work);
 job.missing_name=worker.source.symbols.missing_name;job.resolution_used=parent.resolution_remaining-worker.resolution_remaining;job.associated_used=parent.associated_remaining-worker.associated_remaining;job.work.parallel_jobs+=1;
 job.module=worker.result.modules[unit-1];worker.result.modules[unit-1]=blot_support::none<Module>();if worker.result.body_caches.len!=0 {job.cache=worker.result.body_caches[unit-1];worker.result.body_caches[unit-1]=blot_reuse_body_check_cache::Cache{..};}
 job.diagnostics=copyDiagnostics(worker.diagnostics);worker.diagnostics.items=worker.diagnostics.storage[..0];discardWorker(worker);return blot_error::Error.none;
}
fn checkParallel<E>(self_:Engine&,executor:E&,deferrable:bool)->bool,Error {
 let requested=self_.source.checking.workers;var editor=false;match self_.editor {query=>{editor=true;},_=>{}}
 if requested<=1 || !self_.source.checking.io || self_.source_validation || editor || self_.execution.observe!=null || self_.execution.stats!=null || self_.source.input_mode!=blot_reuse_project::InputMode.project {return false,blot_error::Error.none;}
 var nodes:i64=0;var remaining:i64=0;for unit in self_.source.order.items {if deferrable && unit==self_.source.entry {continue;}let count=self_.source.unit(unit).tree.nodes.len;nodes+=min(0x7fffffffffffffff-nodes,count);remaining+=1;}if remaining<2 || nodes<self_.execution.parallel_min_nodes {return false,blot_error::Error.none;}
 let resolution=self_.resolution_remaining;let associated=self_.associated_remaining;let done=owned_bool.alloc_slice(self_.source.units.len);for &value in done {value=false;}let jobs=project_jobs.alloc_slice(done.len);for &job in jobs {job=ParallelJob{..};}
 let accepted,error=parallelBatches(self_,executor,deferrable,remaining,resolution,associated,done,jobs);for &job in jobs {job.deinit();}project_jobs.free_slice(jobs);owned_bool.free_slice(done);return accepted,error;
}
fn parallelBatches<E>(self_:Engine&,executor:E&,deferrable:bool,remaining:i64,resolution:i64,associated:i64,done:bool[:],jobs:ParallelJob[:])->bool,Error {
 var ready=ParallelUnits{};var work_order=ParallelUnits{};
 fn run()->bool,Error {
 var left=remaining;
 while left!=0 {let error=prepareReadyUnits(self_.source,done,deferrable,ready);if error!=blot_error::Error.none {return false,error;}
 if ready.items.len==0 {self_.discardParallel(resolution,associated);return false,blot_error::Error.none;}let prepared,error=prepareParallelNames(self_,ready.items);if error!=blot_error::Error.none {return false,error;}if !prepared {self_.discardParallel(resolution,associated);return false,blot_error::Error.none;}
 let error=prepareWorkOrder(self_.source,ready.items,work_order);if error!=blot_error::Error.none {return false,error;}
 // This static executor copies the full immutable input image, joins every
 // process/worker before returning, and imports owned replies into jobs[unit-1].
 // Preparation, charging and publication below keep dependency traversal order.
 let width=min(self_.source.checking.workers as i64,min(ready.items.len,16));let counts,error=executor.runProjectChecks(self_,work_order.items,width,jobs);if error!=blot_error::Error.none {executor.cancelProjectChecks();self_.discardParallel(resolution,associated);return false,error;}
 blot_phase_profile::recordChecking(counts);blot_phase_profile::recordChecking(blot_work_counters::Frontend{parallel_batches:1, ..});var retry=false;var out_of_memory=false;
 for unit in ready.items {let job:ParallelJob& =jobs[unit-1];blot_phase_profile::recordChecking(job.work);if job.failure!=blot_error::Error.none {out_of_memory=out_of_memory || job.failure==blot_error::Error.out_of_memory;retry=true;}
 retry=retry || job.missing_name || job.diagnostics.len!=0 || !job.module.present;if job.resolution_used>self_.resolution_remaining || job.associated_used>self_.associated_remaining {retry=true;}else {self_.resolution_remaining-=job.resolution_used;self_.associated_remaining-=job.associated_used;}
 if job.module.present {self_.result.modules[unit-1]=job.module;job.module=blot_support::none<Module>();}if self_.result.body_caches.len!=0 {self_.result.body_caches[unit-1]=job.cache;job.cache=blot_reuse_body_check_cache::Cache{..};}
 }
 if retry {self_.discardParallel(resolution,associated);if out_of_memory {return false,blot_error::Error.out_of_memory;}return false,blot_error::Error.none;}
 for unit in ready.items {let checked:const Checked& =self_.result.modules[unit-1].value.checked;self_.result.body_elaborations+=checked.body_elaborations;self_.result.imported_schemes+=checked.imported_schemes;self_.result.normalization.merge(checked.types.normalization);done[unit-1]=true;left-=1;}
 }
 if deferrable {self_.result.deferred_entry=blot_support::some(Deferred{self_.resolution_remaining,self_.associated_remaining, ..});}return true,blot_error::Error.none;

 }
 let accepted,error=run();blot_support_pooled_buffer::deinit(work_order,parallel_unit_runs);blot_support_pooled_buffer::deinit(ready,parallel_unit_runs);return accepted,error;
}
