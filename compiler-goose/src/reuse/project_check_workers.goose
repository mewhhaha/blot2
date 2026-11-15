// The executor of project checks. A project that asks for more than one
// checker has its ready modules checked in forked copies of this process.
// A copy holds the whole compiler state as it stood at the fork, so only its
// answer crosses a pipe: the checked module, or word that the module has to
// be checked here instead. A module with a diagnostic is always checked here,
// so diagnostics never depend on the number of checkers.
namespace blot_reuse_project_check;
import .project_check;
import support.project_packet;
import support.native;
import support.io;
import phase_profile;
struct Workers {requested:u8=1}
let job_signature:u32=0x424a4f42;
// How a job ended, as the copy reports it.
let job_accepted:u32=0;
let job_out_of_memory:u32=1;
let job_failed:u32=2;
struct RunningJob {unit:u32,pid:i64,descriptor:i32}
fn putModule(writer:blot_project_packet::Writer&,module:Module) {blot_project_packet::put(writer,module.checked);blot_project_packet::put(writer,module.exports);blot_project_packet::put(writer,module.valid);}
fn getModule(reader:blot_project_packet::Reader&)->Module,Error {
 var checked=default<Checked>();var exports:Export[:]=default<Export[:]>();var valid=false;blot_project_packet::get(reader,checked);blot_project_packet::get(reader,exports);blot_project_packet::get(reader,valid);
 if reader.failure!=blot_error::Error.none {checked.deinit();return default<Module>(),reader.failure;}return canonicalModule(Module{checked,copyOwned(exports),valid}),blot_error::Error.none;
}
fn encodeJob(unit:u32,job:const ParallelJob&,output:u8[>..<]&)->Error {
 var writer=blot_project_packet::Writer{output};blot_project_packet::put(writer,job_signature);blot_project_packet::put(writer,unit);blot_project_packet::put(writer,job.work);
 var outcome=job_accepted;if job.failure==blot_error::Error.out_of_memory {outcome=job_out_of_memory;}else if job.failure!=blot_error::Error.none {outcome=job_failed;}blot_project_packet::put(writer,outcome);
 blot_project_packet::put(writer,job.missing_name);blot_project_packet::put(writer,job.resolution_used);blot_project_packet::put(writer,job.associated_used);
 // A module with diagnostics is not sent: this process checks it again.
 let published=outcome==job_accepted && job.module.present && job.diagnostics.len==0;blot_project_packet::put(writer,published);if published {putModule(writer,job.module.value);}return writer.failure;
}
fn decodeJob(unit:u32,bytes:const u8[:],job:ParallelJob&)->Error {
 var owner,error=blot_project_packet::initOwner();if error!=blot_error::Error.none {return error;}var reader=blot_project_packet::Reader{bytes,owner};
 var signature:u32=0;var actual:u32=0;var outcome:u32=0;blot_project_packet::get(reader,signature);blot_project_packet::get(reader,actual);if reader.failure!=blot_error::Error.none || signature!=job_signature || actual!=unit {owner.deinit();return blot_error::Error.invalid_artifact;}
 blot_project_packet::get(reader,job.work);blot_project_packet::get(reader,outcome);blot_project_packet::get(reader,job.missing_name);blot_project_packet::get(reader,job.resolution_used);blot_project_packet::get(reader,job.associated_used);
 var published=false;blot_project_packet::get(reader,published);if reader.failure!=blot_error::Error.none || outcome>job_failed || job.resolution_used<0 || job.associated_used<0 {owner.deinit();return blot_error::Error.invalid_artifact;}
 if outcome==job_out_of_memory {job.failure=blot_error::Error.out_of_memory;}else if outcome==job_failed {job.failure=blot_error::Error.invalid_artifact;}
 if published {let module,error=getModule(reader);if error!=blot_error::Error.none {owner.deinit();return error;}job.module=blot_support::Option<Module>{true,module};}
 if reader.failure!=blot_error::Error.none || reader.at!=reader.bytes.len {job.deinit();owner.deinit();return blot_error::Error.invalid_artifact;}owner.deinit();return blot_error::Error.none;
}
// Runs in the copy: check, answer and end. The copy releases nothing; its
// memory goes with its process.
fn answerJob(parent:Engine&,unit:u32,descriptor:i32) {
 blot_phase_profile::installTrace(null);var job=ParallelJob{..};let wall=blot_native::clock_ns();let cpu=blot_native::thread_cpu_ns();let error=executeProjectJob(parent,unit,job);let stopped=blot_native::clock_ns();let cpu_stopped=blot_native::thread_cpu_ns();
 if stopped>=wall {job.work.parallel_worker_us=blot_work_counters::saturating_add(job.work.parallel_worker_us,(stopped-wall)/1000);}
 if cpu_stopped>=cpu && blot_native::thread_cpu_available() {job.work.parallel_worker_cpu_us=blot_work_counters::saturating_add(job.work.parallel_worker_cpu_us,(cpu_stopped-cpu)/1000);job.work.parallel_worker_cpu_samples++;}
 var status:i32=1;var output:u8[>..<]=[];if error==blot_error::Error.none {if encodeJob(unit,job,output)==blot_error::Error.none {if blot_io::write_all(blot_io::Writer{descriptor},output[..])==blot_error::Error.none {status=0;}}}
 blot_native::job_exit(status);
}
// Reads a copy's whole answer and waits for the copy to end.
fn collectJob(running:RunningJob,job:ParallelJob&) {
 var bytes:u8[>..]=[];var chunk:u8[65536];var failed=false;
 loop {let count=blot_native::read(running.descriptor,chunk[0],65536);if count<0 {failed=true;break;}if count==0 {break;}bytes.append(chunk[..count]);}
 blot_native::close(running.descriptor);let succeeded=blot_native::wait_success(running.pid as u32);job.deinit();
 if failed || !succeeded {job.failure=blot_error::Error.invalid_artifact;return;}let error=decodeJob(running.unit,bytes[..],job);if error!=blot_error::Error.none {job.deinit();job.failure=error;}
}
// At most `width` copies run at a time. A job that cannot run or answer is
// marked failed, and the caller checks its module here.
fn runProjectChecks(self_:Workers&,parent:Engine&,order:const u32[:],width:i64,jobs:ParallelJob[:])->blot_work_counters::Frontend,Error {
 var totals=blot_work_counters::Frontend{..};if width<1 || width>16 || jobs.len!=parent.source.units.len {return totals,blot_error::Error.invalid_request;}
 for unit,position in order {if unit==0 || unit>jobs.len {return totals,blot_error::Error.invalid_request;}for previous in order[..position] {if previous==unit {return totals,blot_error::Error.invalid_request;}}}
 let started=blot_native::clock_ns();var running:RunningJob[>..]=[];var next:i64=0;var oldest:i64=0;
 while next<order.len || oldest<running.len {
  while next<order.len && running.len-oldest<width {
   let unit=order[next];next++;var descriptor:i32=-1;let pid=blot_native::job_fork(descriptor);
   if pid<0 {jobs[unit-1].deinit();jobs[unit-1].failure=blot_error::Error.io;continue;}
   if pid==0 {answerJob(parent,unit,descriptor);}
   running.push(RunningJob{unit,pid,descriptor});
  }
  if oldest<running.len {let job=running[oldest];oldest++;collectJob(job,jobs[job.unit-1]);}
 }
 let ended=blot_native::clock_ns();if ended>=started {totals.parallel_batch_us=(ended-started)/1000;}totals.parallel_worker_slots=width as u64;totals.parallel_worker_jobs=order.len as u64;return totals,blot_error::Error.none;
}
// Every copy has ended by the time runProjectChecks returns.
fn cancelProjectChecks(self_:Workers&) {}
fn checkProjectWithWorkers(source:Project)->CheckedProject,Error {var executor=Workers{..};return checkProject(executor,source);}
fn checkProjectForEditorWithWorkers(source:Project,query:EditorQuery)->CheckedProject,Error {var executor=Workers{..};return checkProjectForEditor(executor,source,query);}
fn checkProjectToFirstDiagnosticWithWorkers(source:Project)->CheckedProject,Error {var executor=Workers{..};return checkProjectToFirstDiagnostic(executor,source);}
