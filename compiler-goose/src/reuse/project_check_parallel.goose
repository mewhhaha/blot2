// Ready batches cross a copied executor boundary; publication remains ordered.
namespace blot_reuse_project_check;
import .project_check;
import check.source_sort;
struct ParallelJob {
 work:blot_work_counters::Frontend=blot_work_counters::Frontend{..},diagnostics:Diagnostic[:]=[],failure:Error=Error.none,missing_name:bool=false,resolution_used:i64=0,associated_used:i64=0,
 module:blot_support::Option<Module>=blot_support::none<Module>(),cache:blot_reuse_body_check_cache::Cache=blot_reuse_body_check_cache::Cache{..},
}
reusable[] var project_jobs:ParallelJob[>..]=[];
fn deinit(self:ParallelJob&) {for &diagnostic in self.diagnostics {diagnostic.deinit();}releaseOwned(self.diagnostics);if self.module.present {self.module.value.deinit();}self.cache.deinit();self=ParallelJob{..};}
fn parallelReady(self:const Engine&,unit:u32,done:const bool[:])->bool {for imported in self.source.unitImports(unit) {if !done[imported.target-1] && self.source.compiledModule(imported.target)==null {return false;}}if self.source.unit(unit).implicit_prelude && self.source.prelude_unit!=0 && self.source.prelude_unit!=unit {let prelude=self.source.prelude_unit;if !done[prelude-1] && self.source.compiledModule(prelude)==null {return false;}}return true;}
struct WorkOrder {source:Project,units:u32[:]}
fn lessThan(self:WorkOrder,left:i64,right:i64)->bool {let l=self.units[left];let r=self.units[right];let a=self.source.unit(l).tree.nodes.len;let b=self.source.unit(r).tree.nodes.len;if a!=b {return a>b;}return l<r;}
fn swap(self:WorkOrder,left:i64,right:i64) {let value=self.units[left];self.units[left]=self.units[right];self.units[right]=value;}
fn discardParallel(self:Engine&,resolution:i64,associated:i64) {
 for &slot in self.result.modules {if slot.present {slot.value.deinit();slot=blot_support::none<Module>();}}
 for &cache in self.result.body_caches {cache.deinit();cache=blot_reuse_body_check_cache::Cache{..};}
 self.result.body_elaborations=0;self.result.imported_schemes=0;self.result.normalization=blot_work_counters::Normalization{..};self.resolution_remaining=resolution;self.associated_remaining=associated;blot_phase_profile::recordChecking(blot_work_counters::Frontend{parallel_retries:1, ..});
}
// A borrowed engine header gets its own canonical callback identity. Producer
// tables stay borrowed; only this job's new module/cache/diagnostics transfer.
fn borrowWorker(parent:const Engine&)->Engine?,Error {
 if engines.len>=0xffffffff {return null,Error.out_of_memory;}let generation=blot_native::fresh_owner_id();let at=engines.alloc_index(copy(parent));let worker:Engine&=engines[at];worker.slot=(at+1) as u32;worker.generation=generation;worker.live=true;worker.diagnostics=DiagnosticBuffer{..};worker.result.body_elaborations=0;worker.result.imported_schemes=0;worker.result.normalization=blot_work_counters::Normalization{..};return worker,Error.none;
}
fn discardWorker(worker:Engine&) {worker.deinitDiagnostics();let at=worker.slot-1;worker=Engine{..};engines.free(at);}
fn prepareParallelNames(parent:Engine&,units:const u32[:])->bool,Error {
 let started=blot_native::clock_ns();let trace=blot_phase_profile::currentTrace()!=null;var accepted=true;var failure=Error.none;
 for unit in units {let worker,error=borrowWorker(parent);if error!=Error.none {failure=error;break;}assert(worker);worker.prepare_names=true;let error=worker.checkModule(unit);let rejected=worker.diagnostics.items.len!=0;discardWorker(worker);if error!=Error.none {failure=error;break;}if rejected {accepted=false;break;}}
 if trace {let ended=blot_native::clock_ns();var elapsed:u64=0;if ended>=started {elapsed=(ended-started)/1000;}blot_phase_profile::recordChecking(blot_work_counters::Frontend{parallel_prepare_us:elapsed, ..});}return accepted,failure;
}
// The copied-worker executor invokes this exact program in its private context;
// its reply owns all new tables and carries no borrowed Engine or producer ref.
fn executeProjectJob(parent:Engine&,unit:u32,job:ParallelJob&)->Error {
 let worker,error=borrowWorker(parent);if error!=Error.none {job.failure=error;return Error.none;}assert(worker);worker.source.symbols.read_only=true;worker.source.symbols.missing_name=false;let capture=blot_phase_profile::captureChecking(job.work);job.failure=worker.checkModule(unit);capture.restore(job.work);
 job.missing_name=worker.source.symbols.missing_name;job.resolution_used=parent.resolution_remaining-worker.resolution_remaining;job.associated_used=parent.associated_remaining-worker.associated_remaining;job.work.parallel_jobs+=1;
 job.module=worker.result.modules[unit-1];worker.result.modules[unit-1]=blot_support::none<Module>();if worker.result.body_caches.len!=0 {job.cache=worker.result.body_caches[unit-1];worker.result.body_caches[unit-1]=blot_reuse_body_check_cache::Cache{..};}
 job.diagnostics=copyOwned(worker.diagnostics.items);worker.diagnostics.items=worker.diagnostics.storage[..0];discardWorker(worker);return Error.none;
}
fn checkParallel<E>(self:Engine&,executor:E&,deferrable:bool)->bool,Error {
 let requested=self.source.checking.workers;var editor=false;match self.editor {Editor.query=>{editor=true;},_=>{}}
 if requested<=1 || !self.source.checking.io || self.source_validation || editor || self.execution.observe!=null || self.execution.stats!=null || self.source.input_mode!=blot_reuse_project::InputMode.project {return false,Error.none;}
 var nodes:i64=0;var remaining:i64=0;for unit in self.source.order.items {if deferrable && unit==self.source.entry {continue;}let count=self.source.unit(unit).tree.nodes.len;nodes+=min(0x7fffffffffffffff-nodes,count);remaining+=1;}if remaining<2 || nodes<self.execution.parallel_min_nodes {return false,Error.none;}
 let resolution=self.resolution_remaining;let associated=self.associated_remaining;let done=owned_bool.alloc_slice(self.source.units.len);for &value in done {value=false;}let jobs=project_jobs.alloc_slice(done.len);for &job in jobs {job=ParallelJob{..};}
 let accepted,error=parallelBatches(self,executor,deferrable,remaining,resolution,associated,done,jobs);for &job in jobs {job.deinit();}project_jobs.free_slice(jobs);owned_bool.free_slice(done);return accepted,error;
}
fn parallelBatches<E>(self:Engine&,executor:E&,deferrable:bool,remaining:i64,resolution:i64,associated:i64,done:bool[:],jobs:ParallelJob[:])->bool,Error {
 var left=remaining;var ready:u32[>..<]=[];var work_order:u32[>..<]=[];
 while left!=0 {ready.clear();for unit in self.source.order.items {if done[unit-1] || (deferrable && unit==self.source.entry) {continue;}if self.parallelReady(unit,done) {ready.push(unit);}}
 if ready.len==0 {self.discardParallel(resolution,associated);return false,Error.none;}let prepared,error=prepareParallelNames(self,ready[:]);if error!=Error.none {return false,error;}if !prepared {self.discardParallel(resolution,associated);return false,Error.none;}
 work_order.clear();work_order.append(ready[:]);blot_check_source_sort::pdqContext(0,work_order.len,WorkOrder{self.source,work_order[:], ..});
 // This static executor copies the full immutable input image, joins every
 // process/worker before returning, and imports owned replies into jobs[unit-1].
 // Preparation, charging and publication below keep dependency traversal order.
 let width=min(self.source.checking.workers as i64,min(ready.len,16));let counts,error=executor.runProjectChecks(self,work_order[:],width,jobs);if error!=Error.none {executor.cancelProjectChecks();self.discardParallel(resolution,associated);return false,error;}
 blot_phase_profile::recordChecking(counts);blot_phase_profile::recordChecking(blot_work_counters::Frontend{parallel_batches:1, ..});var retry=false;var out_of_memory=false;
 for unit in ready {let job:ParallelJob&=jobs[unit-1];blot_phase_profile::recordChecking(job.work);if job.failure!=Error.none {out_of_memory=out_of_memory || job.failure==Error.out_of_memory;retry=true;}
 retry=retry || job.missing_name || job.diagnostics.len!=0 || !job.module.present;if job.resolution_used>self.resolution_remaining || job.associated_used>self.associated_remaining {retry=true;}else {self.resolution_remaining-=job.resolution_used;self.associated_remaining-=job.associated_used;}
 if job.module.present {self.result.modules[unit-1]=job.module;job.module=blot_support::none<Module>();}if self.result.body_caches.len!=0 {self.result.body_caches[unit-1]=job.cache;job.cache=blot_reuse_body_check_cache::Cache{..};}
 }
 if retry {self.discardParallel(resolution,associated);if out_of_memory {return false,Error.out_of_memory;}return false,Error.none;}
 for unit in ready {let checked:const Checked&=self.result.modules[unit-1].value.checked;self.result.body_elaborations+=checked.body_elaborations;self.result.imported_schemes+=checked.imported_schemes;self.result.normalization.merge(checked.types.normalization);done[unit-1]=true;left-=1;}
 }
 if deferrable {self.result.deferred_entry=blot_support::some(Deferred{self.resolution_remaining,self.associated_remaining, ..});}return true,Error.none;
}
