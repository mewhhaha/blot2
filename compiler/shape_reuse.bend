import Base
import ./model.bend as M
import ./groups.bend as G
import ./check_scheduler.bend as Scheduler
import ./native_cache_keys.bend as K
import ./catalog_versions.bend as CV

# The initial shape check has already run coverage and reflection validation.
# A final group can reuse that result only when its entire module and imported
# typed interfaces have the same exact keys.
type Seed is Data:
  Seed{owner: String, keys: List<&2, List<&2, U32>>, checked: G.CheckedGroup}

def owner(members: List<&2, String>) -> Result<&2, &2, M.Diagnostic, String>:
  match members:
    case head <> tail:
      Done{head}
    case Nil{}:
      Fail{M.Diagnostic{"internal_error", "shape_reuse", "inference planner returned an empty group"}}

def group_interfaces(group: G.CheckedGroup) -> List<&2, G.Interface>:
  G.CheckedGroup{checked, interfaces} = group
  interfaces

def checked_subset(subset: M.Module, +functions: Map<&2, M.CheckedFunction>, +constants: Map<&2, M.CheckedConstant>) -> Result<&2, &2, M.Diagnostic, G.CheckedGroup>:
  M.Module{cs, fs, types, operations} = subset
  do Result<&2, &2, M.Diagnostic, G.CheckedGroup>:
    checked_functions : List<&2, M.CheckedFunction> <- Scheduler.ordered_functions(fs, functions)
    checked_constants : List<&2, M.CheckedConstant> <- Scheduler.ordered_constants(cs, constants)
    G.checked_group(M.CheckedModule{checked_constants, checked_functions, types, operations})

def seed_jobs(jobs: List<&2, G.Job>, +catalog: Scheduler.Catalog, +revision: CV.Revision, +functions: Map<&2, M.CheckedFunction>, +constants: Map<&2, M.CheckedConstant>, +interfaces: Map<&2, G.Interface>, reversed: List<&2, Seed>) -> Result<&2, &2, M.Diagnostic, List<&2, Seed>>:
  match jobs:
    case Nil{}:
      Done{List.reverse(&2, Seed, reversed)}
    case +job <> tail:
      G.Job{+members, +dependencies, types} = job
      +subset = Scheduler.group_module(catalog, job)
      do Result<&2, &2, M.Diagnostic, List<&2, Seed>>:
        +name : String <- owner(List.sort(~String, ~String.is_le, members))
        imported : List<&2, G.Interface> <- Scheduler.dependency_interfaces(dependencies, interfaces)
        base : List<&2, U32> <- CV.group_key(subset, revision)
        deps : List<&2, U32> <- K.interfaces(imported)
        +checked : G.CheckedGroup <- checked_subset(subset, functions, constants)
        seed_jobs(tail, catalog, revision, functions, constants, Scheduler.publish_interfaces(group_interfaces(checked), interfaces), Seed{name, [base, deps], checked} <> reversed)

def seed(+original: M.Module, checked: M.CheckedModule, revision: CV.Revision) -> Result<&2, &2, M.Diagnostic, List<&2, Seed>>:
  M.CheckedModule{constants, functions, types, operations} = checked
  +fn_index = Scheduler.publish_functions(functions, Map.new(&2, M.CheckedFunction))
  +constant_index = Scheduler.publish_constants(constants, Map.new(&2, M.CheckedConstant))
  do Result<&2, &2, M.Diagnostic, List<&2, Seed>>:
    jobs : List<&2, G.Job> <- G.plan(original)
    seed_jobs(jobs, Scheduler.catalog(original), revision, fn_index, constant_index, Map.new(&2, G.Interface), Nil{})
