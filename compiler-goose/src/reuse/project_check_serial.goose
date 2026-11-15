// The serial executor of project checks, for callers without workers. The
// project check asks an executor for workers only when the project requests
// more than one, and every caller in this port requests one.
namespace blot_reuse_project_check;
import .project_check;
struct SerialChecks {requested:u8=1}
fn runProjectChecks(self_:SerialChecks&,parent:Engine&,order:const u32[:],width:i64,jobs:ParallelJob[:])->blot_work_counters::Frontend,Error {return blot_work_counters::Frontend{..},blot_error::Error.invalid_request;}
fn cancelProjectChecks(self_:SerialChecks&) {}
fn checkProjectSerial(source:Project)->CheckedProject,Error {var executor=SerialChecks{..};return checkProject(executor,source);}
fn checkProjectForEditorSerial(source:Project,query:EditorQuery)->CheckedProject,Error {var executor=SerialChecks{..};return checkProjectForEditor(executor,source,query);}
fn checkProjectToFirstDiagnosticSerial(source:Project)->CheckedProject,Error {var executor=SerialChecks{..};return checkProjectToFirstDiagnostic(executor,source);}
