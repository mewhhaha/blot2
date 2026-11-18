// Public constructors publish only complete ownership.
namespace blot_reuse_project_check;
import .project_check;
fn checkProject<E>(executor:E&,source:Project)->CheckedProject,Error {return checkProjectWithPrivateExecution(executor,source,blot_check_check::PrivateExecution{..});}
// PRIVATE execution-only project proof. Public callers remain default off;
// the loader, semantic options and artifact identities receive no new flags.
fn checkProjectWithPrivateExecution<E>(executor:E&,source:Project,execution:blot_check_check::PrivateExecution)->CheckedProject,Error {return checkProjectMode(executor,source,execution,Editor.none,false,default<ModuleDebit[:]>());}
// One request-local checker graph, with a shared work budget across modules.
fn checkProjectForEditor<E>(executor:E&,source:Project,query:EditorQuery)->CheckedProject,Error {return checkProjectMode(executor,source,blot_check_check::PrivateExecution{..},Editor.query{query},false,default<ModuleDebit[:]>());}
// checkProject for callers that publish only the first diagnostic. Checking
// stops after the first module that reports one, so `diagnostics` is a
// non-empty prefix of the complete check's list exactly when that list is
// non-empty, and later modules stay unchecked.
fn checkProjectToFirstDiagnostic<E>(executor:E&,source:Project)->CheckedProject,Error {return checkProjectMode(executor,source,blot_check_check::PrivateExecution{..},Editor.none,true,default<ModuleDebit[:]>());}
fn checkProjectToFirstDiagnosticTracked(source:Project,debits:ModuleDebit[:])->CheckedProject,Error {
 assert(source.checking.workers<=1 && debits.len==source.units.len);
 var executor=Workers{..};
 return checkProjectMode(executor,source,blot_check_check::PrivateExecution{..},Editor.none,true,debits);
}
fn finishProject(engine:Engine&)->CheckedProject {engine.result.diagnostics=copyDiagnostics(engine.diagnostics);engine.diagnostics.items=engine.diagnostics.storage[..0];let result=canonicalOwnedResult(engine.result);engine.result=CheckedProject{..};return result;}
fn checkProjectMode<E>(executor:E&,source:Project,execution:blot_check_check::PrivateExecution,editor:Editor,first_diagnostic:bool,debits:ModuleDebit[:])->CheckedProject,Error {
 let timing=blot_phase_profile::enter(blot_phase_profile::Phase.check);var engine,error=initEngine(source,execution,editor);if error!=blot_error::Error.none {timing.exit();return CheckedProject{..},error;}
 let error=checkProjectInto(engine,executor,first_diagnostic,debits);if error!=blot_error::Error.none {engine.deinit();timing.exit();return CheckedProject{..},error;}let result=finishProject(engine);engine.deinit();timing.exit();return result,blot_error::Error.none;
}
fn checkProjectInto<E>(self_:Engine&,executor:E&,first_diagnostic:bool,debits:ModuleDebit[:])->Error {
 let source=self_.source;if source.diagnostics.len!=0 {return self_.appendSourceDiagnostics();}
 { let propagated_error = self_.result.allocateModules(source.units.len); if propagated_error != blot_error::Error.none { return propagated_error; } }self_.source_validation=source.input_mode==blot_reuse_project::InputMode.source && blot_check_check::sourceImportDiagnostic(source.unit(source.entry).tree).present;
 for unit in source.units.items {if blot_check_check::hasNumericFailure(unit.tree) {self_.source_validation=true;break;}}
 if self_.source_validation {self_.source_modules=source_module_runs.alloc_slice(source.units.len);for &value in self_.source_modules {value=blot_support::none<SourceModule>();}}
 { let propagated_error = self_.initCompiledCatalogs(); if propagated_error != blot_error::Error.none { return propagated_error; } }
 let parallel,error=self_.checkParallel(executor);{ let propagated_error = error; if propagated_error != blot_error::Error.none { return propagated_error; } }
 // Diagnostics are appended in dependency order and never reordered, so the
 // first is final once it exists. Source validation still collects every
 // module's numeric diagnostics.
 if !parallel {return checkSerial(self_,first_diagnostic,debits);}
 return blot_error::Error.none;
}
fn checkSerial(self_:Engine&,first_diagnostic:bool,debits:ModuleDebit[:])->Error {
 for unit in self_.source.order.items {
  let resolution=self_.resolution_remaining;
  let associated=self_.associated_remaining;
  let continued,error=self_.checkOrdered(unit);
  if error!=blot_error::Error.none {return error;}
  if !continued {break;}
  if debits.len!=0 {debits[unit-1]=ModuleDebit{resolution-self_.resolution_remaining,associated-self_.associated_remaining,self_.source.symbols.entries.len};}
  if first_diagnostic && !self_.source_validation && self_.diagnostics.items.len!=0 {break;}
 }
 return blot_error::Error.none;
}
