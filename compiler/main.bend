import Base
import ./model.bend as M
import ./check.bend as Check
import ./check_scheduler.bend as CheckScheduler
import ./const_eval.bend as Const
import ./wasm.bend as Wasm
import ./source_modules.bend as SourceModules
import ./groups.bend as Groups
import ./cst.bend as Cst

type Analysis is Data:
  Analysis{checked: M.CheckedModule, constants: List<&2, Const.Binding<Const.Value>>, remaining_steps: Nat}

type Artifact is Data:
  Artifact{analysis: Analysis, bytes: List<&2, U32>}

def checked_functions(checked: M.CheckedModule) -> List<&2, M.CheckedFunction>:
  M.CheckedModule{constants, functions, data_types, operations} = checked
  functions

def checked_constants(checked: M.CheckedModule) -> List<&2, M.CheckedConstant>:
  M.CheckedModule{constants, functions, data_types, operations} = checked
  constants

def const_context(module: M.Module, checked: M.CheckedModule) -> Const.Context:
  M.Module{constants, functions, data_types, operations} = module
  Const.Context{constants, functions, Nil{}, data_types, Nil{}, checked_functions(checked)}

def finish_analysis(checked: M.CheckedModule, constants: Const.Constants) -> Analysis:
  Const.Constants{bindings, remaining} = constants
  Analysis{checked, bindings, remaining}

def analyze(+module: M.Module, steps: Nat) -> Result<&2, &2, M.Diagnostic, Analysis>:
  do Result<&2, &2, M.Diagnostic, Analysis>:
    +checked : M.CheckedModule <- CheckScheduler.check_module(module)
    constants : Const.Constants <- Const.evaluate_constants(checked_constants(checked), steps, const_context(module, checked))
    return finish_analysis(checked, constants)

def analysis_checked(analysis: Analysis) -> M.CheckedModule:
  Analysis{checked, constants, remaining_steps} = analysis
  checked

def analysis_constants(analysis: Analysis) -> List<&2, Const.Binding<Const.Value>>:
  Analysis{checked, constants, remaining_steps} = analysis
  constants

def compile(module: M.Module, steps: Nat) -> Result<&2, &2, M.Diagnostic, Artifact>:
  do Result<&2, &2, M.Diagnostic, Artifact>:
    +analysis : Analysis <- analyze(module, steps)
    bytes : List<&2, U32> <- Wasm.emit(analysis_checked(analysis), analysis_constants(analysis))
    return Artifact{analysis, bytes}

# Keep intermediate compiler terms inside Bend; the host only receives results.
def analyze_source(+root: Cst.Cst, prelude: Cst.Cst, fuel: Nat, steps: Nat) -> Result<&2, &2, M.Diagnostic, Analysis>:
  do Result<&2, &2, M.Diagnostic, Analysis>:
    module : M.Module <- SourceModules.source_module(M.name_equal(Cst.kind_of(root), "source_project"), root, prelude, fuel)
    analyze(module, steps)

def compile_source(+root: Cst.Cst, prelude: Cst.Cst, fuel: Nat, steps: Nat) -> Result<&2, &2, M.Diagnostic, Artifact>:
  do Result<&2, &2, M.Diagnostic, Artifact>:
    module : M.Module <- SourceModules.source_module(M.name_equal(Cst.kind_of(root), "source_project"), root, prelude, fuel)
    compile(module, steps)
