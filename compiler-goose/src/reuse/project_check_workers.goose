// A ready batch shares one immutable input image. Each fork owns its checker
// pools and checks a group of modules. The parent works on one group directly
// and consumes the other groups' replies after joining them.
namespace blot_reuse_project_check;
import .project_check;
import support.project_packet;
import support.native;
import phase_profile;
struct Workers {requested:u8=1}
let job_signature:u32=0x424a4f42;
// How a job ended, as the copy reports it.
let job_accepted:u32=0;
let job_out_of_memory:u32=1;
let job_failed:u32=2;
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
fn checkTimedJob(parent:Engine&,unit:u32,job:ParallelJob&) {
    job.deinit();
    let wall=blot_native::clock_ns();
    let cpu=blot_native::thread_cpu_ns();
    let error=executeProjectJob(parent,unit,job);
    let stopped=blot_native::clock_ns();
    let cpu_stopped=blot_native::thread_cpu_ns();
    if error!=blot_error::Error.none {job.failure=error;}
    if stopped>=wall {job.work.parallel_worker_us=(stopped-wall)/1000;}
    if cpu_stopped>=cpu && blot_native::thread_cpu_available() {
        job.work.parallel_worker_cpu_us=(cpu_stopped-cpu)/1000;
        job.work.parallel_worker_cpu_samples=1;
    }
}

fn answerBatch(parent:Engine&,order:const u32[:],groups:const u8[:],group:u8,reply:u64) {
    blot_phase_profile::installTrace(null);
    var job=ParallelJob{..};
    var output:u8[>..<]=[];
    for unit,index in order {
        if groups[index]!=group {continue;}
        output.clear();
        checkTimedJob(parent,unit,job);
        if encodeJob(unit,job,output)!=blot_error::Error.none || output.len==0 {
            blot_native::job_exit(1);
        }
        if !blot_native::check_reply_append(reply,output[0],output.len as u64) {
            blot_native::job_exit(1);
        }
    }
    blot_native::job_exit(0);
}

fn collectBatch(reply:u64,order:const u32[:],groups:const u8[:],group:u8,jobs:ParallelJob[:])->i64 {
    var packet:u8[>..]=[];
    var offset:u64=0;
    for unit,index in order {
        if groups[index]!=group {continue;}
        let size=blot_native::check_reply_size(reply,offset);
        if size<=0 {return -1;}
        packet.resize(size,0);
        let next=blot_native::check_reply_copy(reply,offset,packet[0],size as u64);
        if next<0 {return -1;}
        offset=next as u64;
        let job:ParallelJob& =jobs[unit-1];
        job.deinit();
        let error=decodeJob(unit,packet[..],job);
        if error!=blot_error::Error.none {
            job.deinit();
            job.failure=error;
        }
    }
    if blot_native::check_reply_size(reply,offset)!=0 {return -1;}
    return offset as i64;
}

fn checkBatchLocally(parent:Engine&,order:const u32[:],groups:const u8[:],group:u8,jobs:ParallelJob[:]) {
    for unit,index in order {
        if groups[index]==group {checkTimedJob(parent,unit,jobs[unit-1]);}
    }
}

fn runProjectChecks(self_:Workers&,parent:Engine&,order:const u32[:],width:i64,jobs:ParallelJob[:])->blot_work_counters::Frontend,Error {
    var totals=blot_work_counters::Frontend{..};
    if width<1 || width>16 || jobs.len!=parent.source.units.len {return totals,blot_error::Error.invalid_request;}
    let started=blot_native::clock_ns();
    // The caller orders larger syntax trees first. Balance their estimated
    // work across groups and give the first group to the parent.
    var groups:u8[>..<]=[];
    var seen:bool[>..<]=[];
    seen.resize(jobs.len,false);
    var load:i64[16]=[0;16];
    for unit,position in order {
        if unit==0 || unit>jobs.len {return totals,blot_error::Error.invalid_request;}
        if seen[unit-1] {return totals,blot_error::Error.invalid_request;}
        seen[unit-1]=true;
        var group:i64=0;
        for index in 1..width {if load[index]<load[group] {group=index;}}
        let count=parent.source.unit(unit).tree.nodes.len;
        load[group]+=min(0x7fffffffffffffff-load[group],count);
        groups.push(group as u8);
    }
    var pids:i64[16]=[0;16];
    var replies:u64[16]=[0;16];
    for group in 1..width {
        let reply=blot_native::check_reply_open();
        if reply==0 {continue;}
        let pid=blot_native::fork_process();
        if pid==0 {answerBatch(parent,order,groups[..],group as u8,reply);}
        if pid<0 {blot_native::check_reply_close(reply);continue;}
        pids[group]=pid;
        replies[group]=reply;
        totals.parallel_worker_processes++;
    }
    checkBatchLocally(parent,order,groups[..],0,jobs);
    for group in 1..width {
        var received:i64=-1;
        if pids[group]>0 {
            if blot_native::wait_success(pids[group] as u32) {
                received=collectBatch(replies[group],order,groups[..],group as u8,jobs);
            }
            blot_native::check_reply_close(replies[group]);
        }
        if received<0 {
            checkBatchLocally(parent,order,groups[..],group as u8,jobs);
        }else {
            totals.parallel_worker_reply_bytes+=received as u64;
        }
    }
    let ended=blot_native::clock_ns();
    if ended>=started {totals.parallel_batch_us=(ended-started)/1000;}
    totals.parallel_worker_slots=width as u64;
    totals.parallel_worker_jobs=order.len as u64;
    return totals,blot_error::Error.none;
}
// All child processes have ended by the time runProjectChecks returns.
fn cancelProjectChecks(self_:Workers&) {}
fn checkProjectWithWorkers(source:Project)->CheckedProject,Error {var executor=Workers{..};return checkProject(executor,source);}
fn checkProjectForEditorWithWorkers(source:Project,query:EditorQuery)->CheckedProject,Error {var executor=Workers{..};return checkProjectForEditor(executor,source,query);}
fn checkProjectToFirstDiagnosticWithWorkers(source:Project)->CheckedProject,Error {var executor=Workers{..};return checkProjectToFirstDiagnostic(executor,source);}
