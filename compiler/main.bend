import Base
import ./model.bend as M
import ./check.bend as Check
import ./check_scheduler.bend as CheckScheduler
import ./const_eval.bend as Const
import ./wasm.bend as Wasm
import ./source_modules.bend as SourceModules
import ./groups.bend as Groups
import ./cst.bend as Cst
import ./public_exports.bend as Public
import ./checked_core.bend as Core
import ./entry_points.bend as Entries
import ./raw_core_qualification.bend as RawQualification

type Analysis is Data:
  Analysis{checked: M.CheckedModule, constants: List<&2, Const.Binding<Const.Value>>, remaining_steps: Nat}

type Artifact is Data:
  Artifact{analysis: Analysis, bytes: List<&2, U32>}

type PlannedArtifact is Data:
  PlannedArtifact{analysis: Analysis, bytes: Wasm.BytePlan}

def checked_functions(checked: M.CheckedModule) -> List<&2, M.CheckedFunction>:
  M.CheckedModule{constants, functions, data_types, operations} = checked
  functions

def checked_constants(checked: M.CheckedModule) -> List<&2, M.CheckedConstant>:
  M.CheckedModule{constants, functions, data_types, operations} = checked
  constants

def const_context_prepared(module: M.Module, checked: M.CheckedModule) -> Const.Context:
  M.Module{constants, functions, data_types, operations} = module
  Const.Context{constants, functions, Nil{}, data_types, Nil{}, checked_functions(checked)}

def const_context(module: M.Module, +checked: M.CheckedModule) -> Const.Context:
  const_context_prepared(Public.unchecked_module(checked), checked)

def finish_analysis(checked: M.CheckedModule, constants: Const.Constants) -> Analysis:
  Const.Constants{bindings, remaining} = constants
  Analysis{checked, bindings, remaining}

def analyze(+module: M.Module, steps: Nat) -> Result<&2, &2, M.Diagnostic, Analysis>:
  do Result<&2, &2, M.Diagnostic, Analysis>:
    +checked : M.CheckedModule <- CheckScheduler.check_module(module)
    qualified : Unit <- RawQualification.check(module)
    constants : Const.Constants <- Const.evaluate_constants(checked_constants(checked), steps, const_context(Public.unchecked_module(checked), checked))
    return finish_analysis(checked, constants)

def analysis_checked(analysis: Analysis) -> M.CheckedModule:
  Analysis{checked, constants, remaining_steps} = analysis
  checked

def analysis_constants(analysis: Analysis) -> List<&2, Const.Binding<Const.Value>>:
  Analysis{checked, constants, remaining_steps} = analysis
  constants

def compile_plan(module: M.Module, steps: Nat) -> Result<&2, &2, M.Diagnostic, PlannedArtifact>:
  do Result<&2, &2, M.Diagnostic, PlannedArtifact>:
    +analysis : Analysis <- analyze(module, steps)
    bytes : Wasm.BytePlan <- Wasm.emit_plan(analysis_checked(analysis), analysis_constants(analysis))
    return PlannedArtifact{analysis, bytes}

def flatten_artifact(artifact: PlannedArtifact) -> Artifact:
  PlannedArtifact{analysis, bytes} = artifact
  Artifact{analysis, Wasm.plan_finish(bytes)}

def compile(module: M.Module, steps: Nat) -> Result<&2, &2, M.Diagnostic, Artifact>:
  do Result<&2, &2, M.Diagnostic, Artifact>:
    artifact : PlannedArtifact <- compile_plan(module, steps)
    return flatten_artifact(artifact)

# Keep intermediate compiler terms inside Bend; the host only receives results.
# Only declarations the entries reach are finally checked, const-evaluated and
# emitted; every declaration still passed the initial check. An analysis
# without entry declarations therefore reports nothing but succeeds when the
# program checks.
def analyze_source(+root: Cst.Cst, prelude: Cst.Cst, fuel: Nat, steps: Nat) -> Result<&2, &2, M.Diagnostic, Analysis>:
  do Result<&2, &2, M.Diagnostic, Analysis>:
    +sourced : SourceModules.Sourced <- SourceModules.source_module_core(M.name_equal(Cst.kind_of(root), "source_project"), root, prelude, fuel)
    +prepared : Core.Prepared = SourceModules.sourced_prepared(sourced)
    inferred : M.CheckedModule <- CheckScheduler.check_prepared(prepared)
    +checked : M.CheckedModule = Public.select_checked(inferred)
    valid : Unit <- Entries.verify(SourceModules.sourced_entries(sourced), checked)
    raw : M.Module = Public.unchecked_module(checked)
    constants : Const.Constants <- Const.evaluate_constants(checked_constants(checked), steps, const_context(raw, checked))
    return finish_analysis(checked, constants)

def compile_source(+root: Cst.Cst, prelude: Cst.Cst, fuel: Nat, steps: Nat) -> Result<&2, &2, M.Diagnostic, Artifact>:
  do Result<&2, &2, M.Diagnostic, Artifact>:
    +analysis : Analysis <- analyze_source(root, prelude, fuel, steps)
    exports : Unit <- Entries.require_exports(analysis_checked(analysis))
    bytes : Wasm.BytePlan <- Wasm.emit_plan(analysis_checked(analysis), analysis_constants(analysis))
    return flatten_artifact(PlannedArtifact{analysis, bytes})

def compile_source_plan(+root: Cst.Cst, prelude: Cst.Cst, fuel: Nat, steps: Nat) -> Result<&2, &2, M.Diagnostic, PlannedArtifact>:
  do Result<&2, &2, M.Diagnostic, PlannedArtifact>:
    +analysis : Analysis <- analyze_source(root, prelude, fuel, steps)
    exports : Unit <- Entries.require_exports(analysis_checked(analysis))
    bytes : Wasm.BytePlan <- Wasm.emit_plan(analysis_checked(analysis), analysis_constants(analysis))
    return PlannedArtifact{analysis, bytes}
