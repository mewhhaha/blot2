import Base
import ./model.bend as M
import ./groups.bend as G
import ./check_scheduler.bend as Scheduler
import ./native_cache_keys.bend as K
import ./catalog_versions.bend as CV
import ./checked_core.bend as Core

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
  G.CheckedGroup{checked, interfaces, uses} = group
  interfaces

def checked_subset(found: Maybe<&2, G.CheckedGroup>) -> Result<&2, &2, M.Diagnostic, G.CheckedGroup>:
  match found:
    case Some{checked}:
      Done{checked}
    case None{}:
      Fail{M.Diagnostic{"internal_error", "shape_reuse", "initial check omitted an exact group certificate"}}

def seed_jobs(jobs: List<&2, G.Job>, +catalog: Scheduler.Catalog, +revision: CV.Revision, +certificates: Map<&2, List<&2, Core.Certificate>>, +interfaces: Map<&2, G.Interface>, reversed: List<&2, Seed>) -> Result<&2, &2, M.Diagnostic, List<&2, Seed>>:
  match jobs:
    case Nil{}:
      Done{List.reverse(&2, Seed, reversed)}
    case +job <> tail:
      G.Job{+members, +dependencies, types} = job
      +subset = Scheduler.group_module(catalog, job)
      do Result<&2, &2, M.Diagnostic, List<&2, Seed>>:
        +name : String <- owner(List.sort(~String, ~String.is_le, members))
        +imported : List<&2, G.Interface> <- Scheduler.dependency_interfaces(dependencies, interfaces)
        base : List<&2, U32> <- CV.group_key(subset, revision)
        deps : List<&2, U32> <- K.interfaces(imported)
        +checked : G.CheckedGroup <- checked_subset(Core.lookup(certificates, job, subset, imported))
        seed_jobs(tail, catalog, revision, certificates, Scheduler.publish_interfaces(group_interfaces(checked), interfaces), Seed{name, [base, deps], checked} <> reversed)

def seed(+original: M.Module, initial: Scheduler.Initial, revision: CV.Revision) -> Result<&2, &2, M.Diagnostic, List<&2, Seed>>:
  # Bare checked signatures omit qualified interfaces and occurrence plans.
  # Reuse the complete source certificate instead of reconstructing a group.
  certificates = Core.index_for(original, Scheduler.initial_certificates(initial))
  do Result<&2, &2, M.Diagnostic, List<&2, Seed>>:
    jobs : List<&2, G.Job> <- G.plan(original)
    seed_jobs(jobs, Scheduler.catalog(original), revision, certificates, Map.new(&2, G.Interface), Nil{})
