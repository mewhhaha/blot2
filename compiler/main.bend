import Base
import ./model.bend as M
import ./check.bend as Check
import ./const_eval.bend as Const
import ./effects.bend as Effects
import ./wasm.bend as Wasm
import ./lower.bend as Lower
import ./schedule.bend as Schedule
import ./ecs_abi.bend as Ecs
import ./groups.bend as Groups
import ./cst.bend as Cst

type Analysis is Data:
  Analysis{checked: M.CheckedModule, constants: List<&2, Const.Binding<Const.Value>>, world: M.WorldPlan, remaining_steps: Nat}

type Artifact is Data:
  Artifact{analysis: Analysis, bytes: List<&2, U32>}

type EcsArtifact is Data:
  EcsArtifact{analysis: Analysis, storage: List<&2, Ecs.StorageBinding>, bytes: List<&2, U32>}

def plan_if(exported: Bool, name: String, +effects: List<&2, M.Effect>, rest: List<&2, M.SystemPlan>) -> List<&2, M.SystemPlan>:
  match exported:
    case False{}:
      rest
    case True{}:
      M.SystemPlan{name, effects, Effects.canonical(Effects.query(effects))} <> rest

def system_plans(functions: List<&2, M.CheckedFunction>) -> List<&2, M.SystemPlan>:
  match functions:
    case Nil{}:
      Nil{}
    case M.CheckedFunction{M.Function{name, exported, parameter, param_ty, result_ty, body}, signature, effects} <> tail:
      plan_if(exported, name, effects, system_plans(tail))

def world_plan(+systems: List<&2, M.SystemPlan>) -> M.WorldPlan:
  M.WorldPlan{Effects.canonical(Effects.system_registrations(systems)), systems, Schedule.batches(systems)}

def checked_functions(checked: M.CheckedModule) -> List<&2, M.CheckedFunction>:
  M.CheckedModule{constants, functions, data_types} = checked
  functions

def checked_constants(checked: M.CheckedModule) -> List<&2, M.CheckedConstant>:
  M.CheckedModule{constants, functions, data_types} = checked
  constants

def const_context(module: M.Module) -> Const.Context:
  M.Module{descriptors, constants, functions, data_types} = module
  Const.Context{constants, functions, Nil{}, data_types}

def finish_analysis(+checked: M.CheckedModule, constants: Const.Constants) -> Analysis:
  Const.Constants{bindings, remaining} = constants
  Analysis{checked, bindings, world_plan(system_plans(checked_functions(checked))), remaining}

def analyze(+module: M.Module, steps: Nat) -> Result<&2, &2, M.Diagnostic, Analysis>:
  do Result<&2, &2, M.Diagnostic, Analysis>:
    +checked : M.CheckedModule <- Check.check_module(module)
    constants : Const.Constants <- Const.evaluate_constants(checked_constants(checked), steps, const_context(module))
    return finish_analysis(checked, constants)

def analysis_checked(analysis: Analysis) -> M.CheckedModule:
  Analysis{checked, constants, world, remaining_steps} = analysis
  checked

def analysis_constants(analysis: Analysis) -> List<&2, Const.Binding<Const.Value>>:
  Analysis{checked, constants, world, remaining_steps} = analysis
  constants

def compile(module: M.Module, steps: Nat) -> Result<&2, &2, M.Diagnostic, Artifact>:
  do Result<&2, &2, M.Diagnostic, Artifact>:
    +analysis : Analysis <- analyze(module, steps)
    bytes : List<&2, U32> <- Wasm.emit(analysis_checked(analysis), analysis_constants(analysis))
    return Artifact{analysis, bytes}

def compile_ecs(module: M.Module, steps: Nat) -> Result<&2, &2, M.Diagnostic, EcsArtifact>:
  do Result<&2, &2, M.Diagnostic, EcsArtifact>:
    +analysis : Analysis <- analyze(module, steps)
    +prepared : Wasm.Prepared <- Wasm.prepare_ecs(analysis_checked(analysis), analysis_constants(analysis))
    entries : List<&2, Wasm.EntryCode> <- Wasm.compile_entries(Wasm.prepared_jobs(prepared))
    bytes : List<&2, U32> <- Wasm.link(prepared, entries)
    return EcsArtifact{analysis, Wasm.prepared_storage(prepared), bytes}

# Source compilation keeps its intermediate module inside Bend. Only the final
# analysis/artifact crosses the public host boundary.
def analyze_source(root: Cst.Cst, prelude: Cst.Cst, fuel: Nat, steps: Nat) -> Result<&2, &2, M.Diagnostic, Analysis>:
  do Result<&2, &2, M.Diagnostic, Analysis>:
    module : M.Module <- Lower.source_module(root, prelude, fuel)
    analyze(module, steps)

def compile_source(root: Cst.Cst, prelude: Cst.Cst, fuel: Nat, steps: Nat) -> Result<&2, &2, M.Diagnostic, Artifact>:
  do Result<&2, &2, M.Diagnostic, Artifact>:
    module : M.Module <- Lower.source_module(root, prelude, fuel)
    compile(module, steps)

def compile_ecs_source(root: Cst.Cst, prelude: Cst.Cst, fuel: Nat, steps: Nat) -> Result<&2, &2, M.Diagnostic, EcsArtifact>:
  do Result<&2, &2, M.Diagnostic, EcsArtifact>:
    module : M.Module <- Lower.source_module(root, prelude, fuel)
    compile_ecs(module, steps)
