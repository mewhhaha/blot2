import bootstrap_globals;
import driver.cli;
import driver.cli_workers;
import driver.project_executor;
import driver.compile_workspace;
import std;
fn main() {
 var worker=blot_project_executor::init();let source=blot_reuse_project::Project{};
 var engine,error=blot_reuse_project_check::initEngine(source,blot_check_check::PrivateExecution{},blot_reuse_project_check::Editor.none,false);assert(error==blot_error::Error.none);
 let order:u32[0]=default<u32[0]>();let jobs=blot_reuse_project_check::project_jobs.alloc_slice(1);jobs[0]=blot_reuse_project_check::ParallelJob{};
 let rejected,error=worker.runProjectChecks(engine,order[..],1,jobs);assert(error==blot_error::Error.invalid_request);
 let counts,error=worker.runProjectChecks(engine,order[..],1,jobs[..0]);assert(error==blot_error::Error.none);engine.deinit();worker.deinit();
 for &job in jobs {job.deinit();}blot_reuse_project_check::project_jobs.free_slice(jobs);
 var frame,error=blot_compile_workspace::create(blot_native::fresh_owner_id());assert(error==blot_error::Error.none);assert(frame.release()==blot_error::Error.none);
 print("executor Frame ownership passed: invalid-size rejection, valid empty batch and pooled-slot cleanup");
}
