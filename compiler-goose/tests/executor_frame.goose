import bootstrap_globals;
import driver.cli;
import driver.cli_workers;
import driver.project_executor;
import driver.compile_workspace;
import std;
import reuse.frontend_binding_relocation;
fn bindingMap()->blot_reuse_frontend_binding_relocation::Map {
 let bindings=blot_reuse_frontend_binding_relocation::words(2,17);let nominals=blot_reuse_frontend_binding_relocation::words(2,23);let constructors=blot_reuse_frontend_binding_relocation::words(2,31);let contracts=blot_reuse_frontend_binding_relocation::words(2,41);let implementations=blot_reuse_frontend_binding_relocation::words(2,47);
 let qualifications=blot_reuse_frontend_binding_relocation::owned_qualifications.alloc_slice(1);qualifications[0]=blot_reuse_frontend_binding_relocation::Qualification{blot_parse_ast::Span{1,2},blot_parse_ast::Span{3,4}};
 return blot_reuse_frontend_binding_relocation::canonicalOwned(blot_reuse_frontend_binding_relocation::Map{bindings,nominals,constructors,contracts,implementations,qualifications});
}
fn mapPublication() {
 var result,error=blot_reuse_project_check::initResult();assert(error==blot_error::Error.none);assert(result.allocateReuse(1)==blot_error::Error.none);
 let mapping=bindingMap();result.binding_maps[0]=blot_support::Option<blot_reuse_frontend_binding_relocation::Map>{true,blot_reuse_frontend_binding_relocation::canonicalOwned(mapping)};
 var frame,error=blot_compile_workspace::create(blot_native::fresh_owner_id());assert(error==blot_error::Error.none);assert(frame.release()==blot_error::Error.none);
 let observed=result.binding_maps[0];assert(observed.present && observed.value.binding(1).value==17);assert(observed.value.nominals[1]==23 && observed.value.constructors[1]==31 && observed.value.contracts[1]==41 && observed.value.implementations[1]==47);assert(observed.value.qualification(blot_parse_ast::Span{1,2})==blot_parse_ast::Span{3,4});
 result.deinit();
}
fn main() {
 mapPublication();
 var worker=blot_project_executor::init();let source=blot_reuse_project::Project{};
 var engine,error=blot_reuse_project_check::initEngine(source,blot_check_check::PrivateExecution{},blot_reuse_project_check::Editor.none,false);assert(error==blot_error::Error.none);
 let order:u32[0]=default<u32[0]>();let jobs=blot_reuse_project_check::project_jobs.alloc_slice(1);jobs[0]=blot_reuse_project_check::ParallelJob{};
 let rejected,error=worker.runProjectChecks(engine,order[..],1,jobs);assert(error==blot_error::Error.invalid_request);
 let counts,error=worker.runProjectChecks(engine,order[..],1,jobs[..0]);assert(error==blot_error::Error.none);engine.deinit();worker.deinit();
 for &job in jobs {job.deinit();}blot_reuse_project_check::project_jobs.free_slice(jobs);
 var frame,error=blot_compile_workspace::create(blot_native::fresh_owner_id());assert(error==blot_error::Error.none);assert(frame.release()==blot_error::Error.none);
 print("executor Frame ownership passed: invalid-size rejection, valid empty batch and pooled-slot cleanup");
}
