import Base
import ./model.bend as M
import ./groups.bend as G
import ./index.bend as Index
import ./inference_batch.bend as B
import ./check_chain_plan.bend as Chains
import ./check_regions.bend as Regions
import ./checked_core.bend as Core
import ./resolving_core.bend as ResolvingCore
import ./frontier_alpha_compare.bend as AlphaCompare
import ./nat_index.bend as NatIndex

def required(-V: Data, found: Maybe<&2, V>, name: String) -> Result<&2, &2, M.Diagnostic, V>:
  match found:
    case Some{value}:
      Done{value}
    case None{}:
      Fail{M.Diagnostic{"internal_error", name, "incremental plan omitted a required checked dependency"}}

type Positioned<-V: Data> is Data:
  Positioned{position: Nat, value: V}

type Catalog is Data:
  Catalog{
    functions: Map<&2, Positioned<M.Function>>,
    constants: Map<&2, Positioned<M.Constant>>,
    types: Map<&2, Positioned<M.DataType>>,
    operations: List<&2, M.Operation>,
    costs: Map<&2, Nat>,
    core: Map<&2, List<&2, Core.Certificate>>,
    evidence: Bool,
    resolving: Map<&2, List<&2, ResolvingCore.Witness>>
  }

def index_functions(values: List<&2, M.Function>, +position: Nat, found: Map<&2, Positioned<M.Function>>) -> Map<&2, Positioned<M.Function>>:
  match values:
    case Nil{}:
      found
    case M.Function{+name, exported, parameter, p, r, body} <> tail:
      index_functions(tail, 1n+position, Map.set(&2, Positioned<M.Function>, found, name, Positioned{position, M.Function{name, exported, parameter, p, r, body}}))

def index_constants(values: List<&2, M.Constant>, +position: Nat, found: Map<&2, Positioned<M.Constant>>) -> Map<&2, Positioned<M.Constant>>:
  match values:
    case Nil{}:
      found
    case M.Constant{+name, exported, annotation, value} <> tail:
      index_constants(tail, 1n+position, Map.set(&2, Positioned<M.Constant>, found, name, Positioned{position, M.Constant{name, exported, annotation, value}}))

def index_types(values: List<&2, M.DataType>, +position: Nat, found: Map<&2, Positioned<M.DataType>>) -> Map<&2, Positioned<M.DataType>>:
  match values:
    case Nil{}:
      found
    case M.DataType{+identity, parameters, constructors} <> tail:
      index_types(tail, 1n+position, Map.set(&2, Positioned<M.DataType>, found, G.type_key(identity), Positioned{position, M.DataType{identity, parameters, constructors}}))

def catalog_costs(module: M.Module, costs: Map<&2, Nat>) -> Catalog:
  M.Module{constants, functions, types, operations} = module
  Catalog{index_functions(functions, 0n, Map.new(&2, Positioned<M.Function>)), index_constants(constants, 0n, Map.new(&2, Positioned<M.Constant>)), index_types(types, 0n, Map.new(&2, Positioned<M.DataType>)), operations, costs, Map.new(&2, List<&2, Core.Certificate>), False{}, Map.new(&2, List<&2, ResolvingCore.Witness>)}

def catalog(module: M.Module) -> Catalog:
  catalog_costs(module, Map.new(&2, Nat))

def with_core(known: Catalog, module: M.Module, certificates: List<&2, Core.Certificate>) -> Catalog:
  Catalog{functions, constants, types, operations, costs, core, evidence, resolving} = known
  Catalog{functions, constants, types, operations, costs, Core.index_for(module, certificates), evidence, resolving}

def with_evidence(known: Catalog) -> Catalog:
  Catalog{functions, constants, types, operations, costs, core, evidence, resolving} = known
  Catalog{functions, constants, types, operations, costs, core, True{}, resolving}

def with_resolving(known: Catalog, witnesses: Map<&2, List<&2, ResolvingCore.Witness>>) -> Catalog:
  Catalog{functions, constants, types, operations, costs, core, evidence, resolving} = known
  Catalog{functions, constants, types, operations, costs, core, evidence, witnesses}

def retained_resolving(known: Catalog, job: G.Job, subset: M.Module, imports: List<&2, G.Interface>) -> Maybe<&2, G.Resolving>:
  Catalog{functions, constants, types, operations, costs, core, evidence, resolving} = known
  ResolvingCore.lookup(resolving, job, subset, imports)

def collecting(known: Catalog) -> Bool:
  Catalog{functions, constants, types, operations, costs, core, evidence, resolving} = known
  evidence

def core_index(known: Catalog) -> Map<&2, List<&2, Core.Certificate>>:
  Catalog{functions, constants, types, operations, costs, core, evidence, resolving} = known
  core

def retained_group(known: Catalog, job: G.Job, subset: M.Module, imports: List<&2, G.Interface>) -> Maybe<&2, G.CheckedGroup>:
  Core.lookup(core_index(known), job, subset, imports)

def selected_position(-V: Data, found: Maybe<&2, Positioned<V>>, rest: List<&2, Positioned<V>>) -> List<&2, Positioned<V>>:
  match found:
    case None{}:
      rest
    case Some{value}:
      value <> rest

def select_positions(-V: Data, names: List<&2, String>, +indexed: Map<&2, Positioned<V>>) -> List<&2, Positioned<V>>:
  match names:
    case Nil{}:
      Nil{}
    case head <> tail:
      selected_position(V, Index.find(Positioned<V>, indexed, head), select_positions(V, tail, indexed))

def position_le(-V: Data, left: Positioned<V>, right: Positioned<V>) -> Bool:
  Positioned{a, av} = left
  Positioned{b, bv} = right
  Nat.is_le(a, b)

def positioned_values(-V: Data, values: List<&2, Positioned<V>>) -> List<&2, V>:
  match values:
    case Nil{}:
      Nil{}
    case Positioned{position, value} <> tail:
      value <> positioned_values(V, tail)

def function_position_le(left: Positioned<M.Function>, right: Positioned<M.Function>) -> Bool:
  position_le(M.Function, left, right)

def constant_position_le(left: Positioned<M.Constant>, right: Positioned<M.Constant>) -> Bool:
  position_le(M.Constant, left, right)

def type_position_le(left: Positioned<M.DataType>, right: Positioned<M.DataType>) -> Bool:
  position_le(M.DataType, left, right)

def group_module(known: Catalog, job: G.Job) -> M.Module:
  Catalog{functions, constants, types, operations, costs, core, evidence, resolving} = known
  G.Job{+members, dependencies, required_types} = job
  +nominals = G.type_keys(required_types)
  cs = positioned_values(M.Constant, List.sort(~Positioned<M.Constant>, ~constant_position_le, select_positions(M.Constant, members, constants)))
  fs = positioned_values(M.Function, List.sort(~Positioned<M.Function>, ~function_position_le, select_positions(M.Function, members, functions)))
  ts = positioned_values(M.DataType, List.sort(~Positioned<M.DataType>, ~type_position_le, select_positions(M.DataType, nominals, types)))
  M.Module{cs, fs, ts, operations}

def dependency_interfaces(names: List<&2, String>, +known: Map<&2, G.Interface>) -> Result<&2, &2, M.Diagnostic, List<&2, G.Interface>>:
  match names:
    case Nil{}:
      Done{Nil{}}
    case +name <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, G.Interface>>:
        value : G.Interface <- required(G.Interface, Index.find(G.Interface, known, name), name)
        rest : List<&2, G.Interface> <- dependency_interfaces(tail, known)
        return value <> rest

def publish_interfaces(values: List<&2, G.Interface>, known: Map<&2, G.Interface>) -> Map<&2, G.Interface>:
  match values:
    case Nil{}:
      known
    case G.Interface{+name, kind, template, parameters, effects} <> tail:
      publish_interfaces(tail, Map.set(&2, G.Interface, known, name, G.Interface{name, kind, template, parameters, effects}))

def publish_functions(values: List<&2, M.CheckedFunction>, known: Map<&2, M.CheckedFunction>) -> Map<&2, M.CheckedFunction>:
  match values:
    case Nil{}:
      known
    case M.CheckedFunction{M.Function{+name, exported, parameter, p, r, body}, signature, effects} <> tail:
      publish_functions(tail, Map.set(&2, M.CheckedFunction, known, name, M.CheckedFunction{M.Function{name, exported, parameter, p, r, body}, signature, effects}))

def publish_constants(values: List<&2, M.CheckedConstant>, known: Map<&2, M.CheckedConstant>) -> Map<&2, M.CheckedConstant>:
  match values:
    case Nil{}:
      known
    case M.CheckedConstant{M.Constant{+name, exported, annotation, value}, ty, variables} <> tail:
      publish_constants(tail, Map.set(&2, M.CheckedConstant, known, name, M.CheckedConstant{M.Constant{name, exported, annotation, value}, ty, variables}))

def ordered_functions(values: List<&2, M.Function>, +known: Map<&2, M.CheckedFunction>) -> Result<&2, &2, M.Diagnostic, List<&2, M.CheckedFunction>>:
  match values:
    case Nil{}:
      Done{Nil{}}
    case M.Function{+name, exported, parameter, p, r, body} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, M.CheckedFunction>>:
        value : M.CheckedFunction <- required(M.CheckedFunction, Index.find(M.CheckedFunction, known, name), name)
        rest : List<&2, M.CheckedFunction> <- ordered_functions(tail, known)
        return value <> rest

def ordered_constants(values: List<&2, M.Constant>, +known: Map<&2, M.CheckedConstant>) -> Result<&2, &2, M.Diagnostic, List<&2, M.CheckedConstant>>:
  match values:
    case Nil{}:
      Done{Nil{}}
    case M.Constant{+name, exported, annotation, expression} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, M.CheckedConstant>>:
        value : M.CheckedConstant <- required(M.CheckedConstant, Index.find(M.CheckedConstant, known, name), name)
        rest : List<&2, M.CheckedConstant> <- ordered_constants(tail, known)
        return value <> rest

type Scheduled is Data:
  Scheduled{position: Nat, level: Nat, job: G.Job}

type Task is Data:
  Task{position: Nat, module: M.Module, dependencies: List<&2, G.Interface>, cost: Nat}
  EvidenceTask{position: Nat, module: M.Module, dependencies: List<&2, G.Interface>, cost: Nat}
  RetainedTask{position: Nat, checked: G.CheckedGroup}
  RetainedEvidenceTask{position: Nat, module: M.Module, dependencies: List<&2, G.Interface>, checked: G.CheckedGroup, needs: List<&2, G.GroupNeeds>}

type Outcome is Data:
  Outcome{position: Nat, checked: Result<&2, &2, M.Diagnostic, G.CheckedGroup>}
  EvidenceOutcome{position: Nat, module: M.Module, imports: List<&2, G.Interface>, checked: Result<&2, &2, M.Diagnostic, G.Resolving>}

type Failure is Data:
  Failure{position: Nat, diagnostic: M.Diagnostic}

def dependency_level(found: Maybe<&2, Nat>, name: String) -> Result<&2, &2, M.Diagnostic, Nat>:
  match found:
    case Some{level}:
      Done{1n+level}
    case None{}:
      Fail{M.Diagnostic{"internal_error", name, "incremental plan omitted a required checked dependency"}}

def highest_level(names: List<&2, String>, +levels: Map<&2, Nat>, maximum: Nat) -> Result<&2, &2, M.Diagnostic, Nat>:
  match names:
    case Nil{}:
      Done{maximum}
    case +name <> tail:
      do Result<&2, &2, M.Diagnostic, Nat>:
        level : Nat <- dependency_level(Index.find(Nat, levels, name), name)
        highest_level(tail, levels, Nat.max(maximum, level))

def publish_level(names: List<&2, String>, +level: Nat, levels: Map<&2, Nat>) -> Map<&2, Nat>:
  match names:
    case Nil{}:
      levels
    case name <> tail:
      publish_level(tail, level, Map.set(&2, Nat, levels, name, level))

def scheduled_le(left: Scheduled, right: Scheduled) -> Bool:
  Scheduled{a, +x, first} = left
  Scheduled{b, +y, second} = right
  Bool.or(Nat.is_lt(x, y), Bool.and(Nat.is_eq(x, y), Nat.is_le(a, b)))

def schedule_work(jobs: List<&2, G.Job>, +position: Nat, +levels: Map<&2, Nat>, reversed: List<&2, Scheduled>) -> Result<&2, &2, M.Diagnostic, List<&2, Scheduled>>:
  match jobs:
    case Nil{}:
      Done{List.sort(~Scheduled, ~scheduled_le, List.reverse(&2, Scheduled, reversed))}
    case +job <> tail:
      G.Job{+members, dependencies, types} = job
      do Result<&2, &2, M.Diagnostic, List<&2, Scheduled>>:
        +level : Nat <- highest_level(dependencies, levels, 0n)
        schedule_work(tail, 1n+position, publish_level(members, level, levels), Scheduled{position, level, job} <> reversed)

# SCCs arrive dependency-first. Leveling that order visits every edge once;
# repeatedly scanning pending groups would make a dependency chain quadratic.
def schedule(jobs: List<&2, G.Job>) -> Result<&2, &2, M.Diagnostic, List<&2, Scheduled>>:
  schedule_work(jobs, 0n, Map.new(&2, Nat), Nil{})

def precedes_failure(position: Nat, failure: Maybe<&2, Failure>) -> Bool:
  match failure:
    case None{}:
      True{}
    case Some{Failure{limit, diagnostic}}:
      Nat.is_lt(position, limit)

def first_failure(+previous: Maybe<&2, Failure>, +candidate: Failure) -> Maybe<&2, Failure>:
  Failure{position, diagnostic} = candidate
  Bool.pick(Maybe<&2, Failure>, precedes_failure(position, previous), Some{candidate}, previous)

# Session costs reuse serialized module word counts; fresh checks estimate that
# scale from expressions. Small leaves stay sequential; an SCC is never split.
def inference_grain() -> Nat:
  128n

def check_task(task: Task, context: Unit) -> Outcome:
  match task:
    case Task{position, module, dependencies, cost}:
      Outcome{position, G.check_group(module, dependencies)}
    case EvidenceTask{position, +module, +dependencies, cost}:
      EvidenceOutcome{position, module, dependencies, G.check_group_resolving(module, dependencies)}
    case RetainedTask{position, checked}:
      Outcome{position, Done{checked}}
    case RetainedEvidenceTask{position, module, dependencies, checked, needs}:
      EvidenceOutcome{position, module, dependencies, Done{G.Resolving{checked, needs}}}

def check_task_planned(task: Task, context: Unit) -> Outcome:
  match task:
    case Task{position, module, dependencies, cost}:
      Outcome{position, G.check_group_planned(module, dependencies)}
    case EvidenceTask{position, +module, +dependencies, cost}:
      EvidenceOutcome{position, module, dependencies, G.check_group_resolving_planned(module, dependencies)}
    case RetainedTask{position, checked}:
      Outcome{position, Done{checked}}
    case RetainedEvidenceTask{position, module, dependencies, checked, needs}:
      EvidenceOutcome{position, module, dependencies, Done{G.Resolving{checked, needs}}}

def weighted_tasks(tasks: List<&2, Task>) -> List<&2, B.Weighted<Task>>:
  match tasks:
    case Nil{}:
      Nil{}
    case Task{position, module, dependencies, +cost} <> tail:
      B.Weighted{Task{position, module, dependencies, cost}, cost} <> weighted_tasks(tail)
    case EvidenceTask{position, module, dependencies, +cost} <> tail:
      B.Weighted{EvidenceTask{position, module, dependencies, cost}, cost} <> weighted_tasks(tail)
    case RetainedTask{position, checked} <> tail:
      B.Weighted{RetainedTask{position, checked}, 0n} <> weighted_tasks(tail)
    case RetainedEvidenceTask{position, module, dependencies, checked, needs} <> tail:
      B.Weighted{RetainedEvidenceTask{position, module, dependencies, checked, needs}, 0n} <> weighted_tasks(tail)

def task_batch(tasks: List<&2, Task>, grain: Nat) -> B.Batch<Task>:
  B.plan(Task, weighted_tasks(tasks), grain)

def check_batch_with_grain(tasks: List<&2, Task>, grain: Nat) -> List<&2, Outcome>:
  B.execute(~Task, ~Unit, ~Outcome, ~check_task, task_batch(tasks, grain), Unit{})

def check_batch(tasks: List<&2, Task>) -> List<&2, Outcome>:
  check_batch_with_grain(tasks, inference_grain())

# A frontier has one immutable operation catalog. A successful independent
# singleton check can certify another clone only when its complete input is
# equal up to the uniform shift used for lambda and return-label identities.
# The candidate stores source origin, full function, exact imported interfaces
# and nominal declarations. Operations are shared by the publish_preparation
# caller; the generic mixed-catalog batch entry below never coalesces.
type FrontierCandidate is Data:
  FrontierCandidate{position: Nat, origin: String, function: M.Function, types: List<&2, M.DataType>, imports: List<&2, G.Interface>}

def clone_origin(name: String) -> String:
  match name:
    case SCon{Chr{93}, SCon{Chr{46}, tail}}:
      tail
    case SCon{character, tail}:
      clone_origin(tail)
    case SNil{}:
      SNil{}

def candidate_parts(position: Nat, constants: List<&2, M.Constant>, functions: List<&2, M.Function>, types: List<&2, M.DataType>, imports: List<&2, G.Interface>) -> Maybe<&2, FrontierCandidate>:
  match constants functions:
    case Nil{} M.Function{+name, exported, parameter, p, r, body} <> Nil{}:
      Bool.pick(Maybe<&2, FrontierCandidate>, String.starts_with(name, "$mono["), Some{FrontierCandidate{position, clone_origin(name), M.Function{"$self", exported, parameter, p, r, body}, types, imports}}, None{})
    case _ _:
      None{}

def task_candidate(task: Task) -> Maybe<&2, FrontierCandidate>:
  match task:
    case Task{position, M.Module{constants, functions, types, operations}, imports, cost}:
      candidate_parts(position, constants, functions, types, imports)
    case EvidenceTask{position, M.Module{constants, functions, types, operations}, imports, cost}:
      candidate_parts(position, constants, functions, types, imports)
    case RetainedTask{position, checked}:
      None{}
    case RetainedEvidenceTask{position, module, imports, checked, needs}:
      None{}

def same_candidate(left: FrontierCandidate, right: FrontierCandidate) -> Bool:
  FrontierCandidate{left_position, left_origin, left_function, left_types, left_imports} = left
  FrontierCandidate{right_position, right_origin, right_function, right_types, right_imports} = right
  Bool.and(M.name_equal(left_origin, right_origin), Bool.and(Core.same_imports(left_imports, right_imports), AlphaCompare.same_alpha_module(M.Module{Nil{}, [left_function], left_types, Nil{}}, M.Module{Nil{}, [right_function], right_types, Nil{}})))

def candidate_position(candidate: FrontierCandidate) -> Nat:
  FrontierCandidate{position, origin, function, types, imports} = candidate
  position

def find_candidate(prior: List<&2, FrontierCandidate>, +current: FrontierCandidate, found: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match prior found:
    case _ Some{position}:
      Some{position}
    case Nil{} None{}:
      None{}
    case +earlier <> tail None{}:
      find_candidate(tail, current, Bool.pick(Maybe<&2, Nat>, same_candidate(earlier, current), Some{candidate_position(earlier)}, None{}))

type BatchState is Data:
  BatchState{known: Map<&2, List<&2, FrontierCandidate>>, originals: List<&2, Task>, representatives: List<&2, Task>, followers: NatIndex.Index<Nat>}

type PlannedBatch is Data:
  PlannedBatch{originals: List<&2, Task>, representatives: List<&2, Task>, followers: NatIndex.Index<Nat>}

def plan_found(found: Maybe<&2, Nat>, prior: List<&2, FrontierCandidate>, candidate: FrontierCandidate, +task: Task, state: BatchState) -> BatchState:
  match found:
    case None{}:
      FrontierCandidate{position, +origin, function, types, imports} = candidate
      BatchState{known, originals, representatives, followers} = state
      BatchState{Map.set(&2, List<&2, FrontierCandidate>, known, origin, FrontierCandidate{position, origin, function, types, imports} <> prior), task <> originals, task <> representatives, followers}
    case Some{representative}:
      BatchState{known, originals, representatives, followers} = state
      BatchState{known, task <> originals, representatives, NatIndex.set(Nat, followers, candidate_position(candidate), representative)}

def plan_prior(prior: Maybe<&2, List<&2, FrontierCandidate>>, +candidate: FrontierCandidate, task: Task, state: BatchState) -> BatchState:
  match prior:
    case None{}:
      plan_found(None{}, Nil{}, candidate, task, state)
    case Some{+previous}:
      plan_found(find_candidate(previous, candidate, None{}), previous, candidate, task, state)

def plan_candidate(candidate: Maybe<&2, FrontierCandidate>, +task: Task, state: BatchState) -> BatchState:
  match candidate:
    case None{}:
      BatchState{known, originals, representatives, followers} = state
      BatchState{known, task <> originals, task <> representatives, followers}
    case Some{value}:
      FrontierCandidate{position, +origin, function, types, imports} = value
      BatchState{+known, originals, representatives, followers} = state
      plan_prior(Index.find(List<&2, FrontierCandidate>, known, origin), FrontierCandidate{position, origin, function, types, imports}, task, BatchState{known, originals, representatives, followers})

def finish_plan(state: BatchState) -> PlannedBatch:
  BatchState{known, originals, representatives, followers} = state
  PlannedBatch{List.reverse(&2, Task, originals), List.reverse(&2, Task, representatives), followers}

def plan_batch(remaining: List<&2, Task>, state: BatchState) -> PlannedBatch:
  match remaining:
    case Nil{}:
      finish_plan(state)
    case +task <> tail:
      plan_batch(tail, plan_candidate(task_candidate(task), task, state))

def batch_outcome_position(outcome: Outcome) -> Nat:
  match outcome:
    case Outcome{position, checked}:
      position
    case EvidenceOutcome{position, module, imports, checked}:
      position

def index_outcomes(outcomes: List<&2, Outcome>, known: NatIndex.Index<Outcome>) -> NatIndex.Index<Outcome>:
  match outcomes:
    case Nil{}:
      known
    case +outcome <> tail:
      index_outcomes(tail, NatIndex.set(Outcome, known, batch_outcome_position(outcome), outcome))

def resolving_checked(result: Result<&2, &2, M.Diagnostic, G.Resolving>) -> Result<&2, &2, M.Diagnostic, G.CheckedGroup>:
  match result:
    case Fail{diagnostic}:
      Fail{diagnostic}
    case Done{resolved}:
      Done{G.resolving_group(resolved)}

def outcome_checked(outcome: Outcome) -> Result<&2, &2, M.Diagnostic, G.CheckedGroup>:
  match outcome:
    case Outcome{position, checked}:
      checked
    case EvidenceOutcome{position, module, imports, checked}:
      resolving_checked(checked)

def replay_parts(old_constants: List<&2, M.CheckedConstant>, old_functions: List<&2, M.CheckedFunction>, old_interfaces: List<&2, G.Interface>, constants: List<&2, M.Constant>, functions: List<&2, M.Function>, types: List<&2, M.DataType>, operations: List<&2, M.Operation>) -> Maybe<&2, G.CheckedGroup>:
  match old_constants old_functions old_interfaces constants functions:
    case Nil{} M.CheckedFunction{old_function, M.Signature{old_name, parameter, result, variables, row}, effects} <> Nil{} G.Interface{interface_name, G.FunctionInterface{}, template, parameters, interface_effects} <> Nil{} Nil{} M.Function{+current_name, exported, argument, p, r, body} <> Nil{}:
      Bool.pick(Maybe<&2, G.CheckedGroup>, M.name_equal(old_name, interface_name), Some{G.CheckedGroup{M.CheckedModule{Nil{}, [M.CheckedFunction{M.Function{current_name, exported, argument, p, r, body}, M.Signature{current_name, parameter, result, variables, row}, effects}], types, operations}, [G.Interface{current_name, G.FunctionInterface{}, template, parameters, interface_effects}]}}, None{})
    case _ _ _ _ _:
      None{}

def replay_for_task(prior: G.CheckedGroup, task: Task) -> Maybe<&2, G.CheckedGroup>:
  G.CheckedGroup{M.CheckedModule{old_constants, old_functions, old_types, old_operations}, old_interfaces} = prior
  match task:
    case Task{position, M.Module{constants, functions, types, operations}, imports, cost}:
      replay_parts(old_constants, old_functions, old_interfaces, constants, functions, types, operations)
    case EvidenceTask{position, M.Module{constants, functions, types, operations}, imports, cost}:
      replay_parts(old_constants, old_functions, old_interfaces, constants, functions, types, operations)
    case RetainedTask{position, checked}:
      None{}
    case RetainedEvidenceTask{position, module, imports, checked, needs}:
      None{}

def replay_outcome(task: Task, checked: G.CheckedGroup) -> Outcome:
  match task:
    case Task{position, module, imports, cost}:
      Outcome{position, Done{checked}}
    case EvidenceTask{position, module, imports, cost}:
      EvidenceOutcome{position, module, imports, Done{G.Resolving{checked, Nil{}}}}
    case RetainedTask{position, prior}:
      Outcome{position, Done{prior}}
    case RetainedEvidenceTask{position, module, imports, prior, needs}:
      EvidenceOutcome{position, module, imports, Done{G.Resolving{prior, needs}}}

def replay_found(replayed: Maybe<&2, G.CheckedGroup>, task: Task) -> Outcome:
  match replayed:
    case None{}:
      check_task_planned(task, Unit{})
    case Some{checked}:
      replay_outcome(task, checked)

def representative_found(result: Result<&2, &2, M.Diagnostic, G.CheckedGroup>, +task: Task) -> Outcome:
  match result:
    case Fail{diagnostic}:
      check_task_planned(task, Unit{})
    case Done{checked}:
      replay_found(replay_for_task(checked, task), task)

def follower_found(prior: Maybe<&2, Outcome>, task: Task) -> Outcome:
  match prior:
    case None{}:
      check_task_planned(task, Unit{})
    case Some{outcome}:
      representative_found(outcome_checked(outcome), task)

def task_position(task: Task) -> Nat:
  match task:
    case Task{position, module, imports, cost}:
      position
    case EvidenceTask{position, module, imports, cost}:
      position
    case RetainedTask{position, checked}:
      position
    case RetainedEvidenceTask{position, module, imports, checked, needs}:
      position

def original_found(prior: Maybe<&2, Outcome>, task: Task) -> Outcome:
  match prior:
    case None{}:
      check_task_planned(task, Unit{})
    case Some{outcome}:
      outcome

def restore_found(representative: Maybe<&2, Nat>, +task: Task, outcomes: NatIndex.Index<Outcome>) -> Outcome:
  match representative:
    case None{}:
      original_found(NatIndex.find(Outcome, outcomes, task_position(task)), task)
    case Some{position}:
      follower_found(NatIndex.find(Outcome, outcomes, position), task)

def restore_batch(tasks: List<&2, Task>, +representatives: NatIndex.Index<Outcome>, +followers: NatIndex.Index<Nat>, reversed: List<&2, Outcome>) -> List<&2, Outcome>:
  match tasks:
    case Nil{}:
      List.reverse(&2, Outcome, reversed)
    case +task <> tail:
      restore_batch(tail, representatives, followers, restore_found(NatIndex.find(Nat, followers, task_position(task)), task, representatives) <> reversed)

def execute_planned_batch(plan: PlannedBatch) -> List<&2, Outcome>:
  PlannedBatch{originals, representatives, followers} = plan
  checked = B.execute(~Task, ~Unit, ~Outcome, ~check_task_planned, task_batch(representatives, inference_grain()), Unit{})
  restore_batch(originals, index_outcomes(checked, NatIndex.new(Outcome)), followers, Nil{})

# The parent planner has already validated the complete module and graph.
# Generic callers may mix operation catalogs, so this entry keeps every task.
def check_batch_planned(tasks: List<&2, Task>) -> List<&2, Outcome>:
  B.execute(~Task, ~Unit, ~Outcome, ~check_task_planned, task_batch(tasks, inference_grain()), Unit{})

# publish_preparation creates every task from one Catalog and one dependency
# frontier. Its operation catalog is therefore identical for all candidates.
def check_batch_same_catalog(tasks: List<&2, Task>) -> List<&2, Outcome>:
  execute_planned_batch(plan_batch(tasks, BatchState{Map.new(&2, List<&2, FrontierCandidate>), Nil{}, Nil{}, NatIndex.new(Nat)}))

type Frontier is Data:
  Frontier{ready: List<&2, Scheduled>, pending: List<&2, Scheduled>}

def same_level(scheduled: List<&2, Scheduled>, level: Nat) -> Bool:
  match scheduled:
    case Nil{}:
      False{}
    case Scheduled{position, next, job} <> tail:
      Nat.is_eq(level, next)

def take_frontier(scheduled: List<&2, Scheduled>, +level: Nat, reversed: List<&2, Scheduled>, same: Bool) -> Frontier:
  match scheduled same:
    case remaining False{}:
      Frontier{List.reverse(&2, Scheduled, reversed), remaining}
    case Nil{} True{}:
      Frontier{List.reverse(&2, Scheduled, reversed), Nil{}}
    case head <> +tail True{}:
      take_frontier(tail, level, head <> reversed, same_level(tail, level))

type CostWork is Data:
  ExpressionCost{value: M.Expr}
  ExpressionsCost{values: List<&2, M.Expr>}
  ArmsCost{values: List<&2, M.MatchArm<M.Expr>>}
  PatternsCost{values: List<&2, M.Pattern>}
  PatternCost{value: M.Pattern}

# This estimate cannot reject a program or change inference fuel. It saturates
# once a single job is already large; only batching needs the approximate size.
def expression_cost(fuel: Nat, pending: List<&2, CostWork>, total: Nat) -> Nat:
  match fuel pending:
    case _ Nil{}:
      total
    case 0n _:
      total
    case 1n+rest ExpressionsCost{Nil{}} <> tail:
      expression_cost(rest, tail, total)
    case 1n+rest ExpressionsCost{head <> remaining} <> tail:
      expression_cost(rest, ExpressionCost{head} <> ExpressionsCost{remaining} <> tail, total)
    case 1n+rest ArmsCost{Nil{}} <> tail:
      expression_cost(rest, tail, total)
    case 1n+rest ArmsCost{M.MatchArm{patterns, body} <> remaining} <> tail:
      expression_cost(rest, PatternsCost{patterns} <> ExpressionCost{body} <> ArmsCost{remaining} <> tail, total)
    case 1n+rest PatternsCost{Nil{}} <> tail:
      expression_cost(rest, tail, total)
    case 1n+rest PatternsCost{head <> remaining} <> tail:
      expression_cost(rest, PatternCost{head} <> PatternsCost{remaining} <> tail, total)
    case 1n+rest PatternCost{M.ProductPattern{elements}} <> tail:
      expression_cost(rest, PatternsCost{elements} <> tail, Nat.add(total, 8n))
    case 1n+rest PatternCost{M.ConstructorPattern{name, Some{payload}}} <> tail:
      expression_cost(rest, PatternCost{payload} <> tail, Nat.add(total, 8n))
    case 1n+rest PatternCost{other} <> tail:
      expression_cost(rest, tail, Nat.add(total, 8n))
    case 1n+rest ExpressionCost{M.ConstructExpr{name, Some{payload}}} <> tail:
      expression_cost(rest, ExpressionCost{payload} <> tail, Nat.add(total, 8n))
    case 1n+rest ExpressionCost{M.LambdaExpr{identity, parameter, p, r, body}} <> tail:
      expression_cost(rest, ExpressionCost{body} <> tail, Nat.add(total, 16n))
    case 1n+rest ExpressionCost{M.ApplyExpr{callee, argument}} <> tail:
      expression_cost(rest, ExpressionCost{callee} <> ExpressionCost{argument} <> tail, Nat.add(total, 16n))
    case 1n+rest ExpressionCost{M.CallExpr{callee, argument}} <> tail:
      expression_cost(rest, ExpressionCost{argument} <> tail, Nat.add(total, 16n))
    case 1n+rest ExpressionCost{M.ScalarExpr{operator, left, right}} <> tail:
      expression_cost(rest, ExpressionCost{left} <> ExpressionCost{right} <> tail, Nat.add(total, 8n))
    case 1n+rest ExpressionCost{M.LetExpr{name, value, body}} <> tail:
      expression_cost(rest, ExpressionCost{value} <> ExpressionCost{body} <> tail, Nat.add(total, 16n))
    case 1n+rest ExpressionCost{M.UseExpr{name, value, body}} <> tail:
      expression_cost(rest, ExpressionCost{value} <> ExpressionCost{body} <> tail, Nat.add(total, 16n))
    case 1n+rest ExpressionCost{M.IfExpr{condition, consequent, alternative}} <> tail:
      expression_cost(rest, ExpressionCost{condition} <> ExpressionCost{consequent} <> ExpressionCost{alternative} <> tail, Nat.add(total, 8n))
    case 1n+rest ExpressionCost{M.SequenceExpr{first, next}} <> tail:
      expression_cost(rest, ExpressionCost{first} <> ExpressionCost{next} <> tail, Nat.add(total, 8n))
    case 1n+rest ExpressionCost{M.MatchExpr{values, arms}} <> tail:
      expression_cost(rest, ExpressionsCost{values} <> ArmsCost{arms} <> tail, Nat.add(total, 16n))
    case 1n+rest ExpressionCost{M.GuardExpr{pattern, value, alternative, body}} <> tail:
      expression_cost(rest, PatternCost{pattern} <> ExpressionCost{value} <> ExpressionCost{alternative} <> ExpressionCost{body} <> tail, Nat.add(total, 16n))
    case 1n+rest ExpressionCost{M.BlockExpr{label, body}} <> tail:
      expression_cost(rest, ExpressionCost{body} <> tail, Nat.add(total, 8n))
    case 1n+rest ExpressionCost{M.ReturnExpr{label, value}} <> tail:
      expression_cost(rest, ExpressionCost{value} <> tail, Nat.add(total, 8n))
    case 1n+rest ExpressionCost{M.RuntimeInitExpr{value}} <> tail:
      expression_cost(rest, ExpressionCost{value} <> tail, Nat.add(total, 8n))
    case 1n+rest ExpressionCost{M.SourceExpr{offset, annotation, value}} <> tail:
      expression_cost(rest, ExpressionCost{value} <> tail, Nat.add(total, 8n))
    case 1n+rest ExpressionCost{M.TagExpr{offset, callee, argument}} <> tail:
      expression_cost(rest, ExpressionCost{callee} <> ExpressionCost{argument} <> tail, Nat.add(total, 16n))
    case 1n+rest ExpressionCost{M.UnaryExpr{operator, value}} <> tail:
      expression_cost(rest, ExpressionCost{value} <> tail, Nat.add(total, 8n))
    case 1n+rest ExpressionCost{M.StateProviderExpr{read, write, initial}} <> tail:
      expression_cost(rest, ExpressionCost{initial} <> tail, Nat.add(total, 16n))
    case 1n+rest ExpressionCost{M.ProviderExpr{identity, implementation}} <> tail:
      expression_cost(rest, ExpressionCost{implementation} <> tail, Nat.add(total, 16n))
    case 1n+rest ExpressionCost{M.HandleExpr{provider, body}} <> tail:
      expression_cost(rest, ExpressionCost{provider} <> ExpressionCost{body} <> tail, Nat.add(total, 16n))
    case 1n+rest ExpressionCost{M.EffectHasExpr{set, operation}} <> tail:
      expression_cost(rest, ExpressionCost{set} <> ExpressionCost{operation} <> tail, Nat.add(total, 8n))
    case 1n+rest ExpressionCost{M.EffectCountExpr{set}} <> tail:
      expression_cost(rest, ExpressionCost{set} <> tail, Nat.add(total, 8n))
    case 1n+rest ExpressionCost{M.EffectSameExpr{left, right}} <> tail:
      expression_cost(rest, ExpressionCost{left} <> ExpressionCost{right} <> tail, Nat.add(total, 8n))
    case 1n+rest ExpressionCost{M.ProductExpr{elements}} <> tail:
      expression_cost(rest, ExpressionsCost{elements} <> tail, Nat.add(total, 8n))
    case 1n+rest ExpressionCost{M.ProjectExpr{value, index}} <> tail:
      expression_cost(rest, ExpressionCost{value} <> tail, Nat.add(total, 8n))
    case 1n+rest ExpressionCost{M.ArrayExpr{elements}} <> tail:
      expression_cost(rest, ExpressionsCost{elements} <> tail, Nat.add(total, 8n))
    case 1n+rest ExpressionCost{M.ForExpr{index, start, end, state, initial, body}} <> tail:
      expression_cost(rest, ExpressionsCost{[start, end, initial, body]} <> tail, Nat.add(total, 8n))
    case 1n+rest ExpressionCost{M.ForeverExpr{state, initial, body}} <> tail:
      expression_cost(rest, ExpressionsCost{[initial, body]} <> tail, Nat.add(total, 8n))
    case 1n+rest ExpressionCost{M.ArrayGenerateExpr{count, generator}} <> tail:
      expression_cost(rest, ExpressionCost{count} <> ExpressionCost{generator} <> tail, Nat.add(total, 8n))
    case 1n+rest ExpressionCost{M.ArrayFillExpr{count, value}} <> tail:
      expression_cost(rest, ExpressionCost{count} <> ExpressionCost{value} <> tail, Nat.add(total, 8n))
    case 1n+rest ExpressionCost{M.ArrayGetExpr{array, index}} <> tail:
      expression_cost(rest, ExpressionCost{array} <> ExpressionCost{index} <> tail, Nat.add(total, 8n))
    case 1n+rest ExpressionCost{M.ArraySetExpr{array, index, value}} <> tail:
      expression_cost(rest, ExpressionCost{array} <> ExpressionCost{index} <> ExpressionCost{value} <> tail, Nat.add(total, 8n))
    case 1n+rest ExpressionCost{M.ArrayLengthExpr{array}} <> tail:
      expression_cost(rest, ExpressionCost{array} <> tail, Nat.add(total, 8n))
    case 1n+rest ExpressionCost{other} <> tail:
      expression_cost(rest, tail, Nat.add(total, 8n))

def function_work(functions: List<&2, M.Function>, work: List<&2, CostWork>) -> List<&2, CostWork>:
  match functions:
    case Nil{}:
      work
    case M.Function{name, exported, parameter, p, r, body} <> tail:
      function_work(tail, ExpressionCost{body} <> work)

def constant_work(constants: List<&2, M.Constant>, work: List<&2, CostWork>) -> List<&2, CostWork>:
  match constants:
    case Nil{}:
      work
    case M.Constant{name, exported, annotation, value} <> tail:
      constant_work(tail, ExpressionCost{value} <> work)

def module_cost(module: M.Module) -> Nat:
  M.Module{constants, functions, types, operations} = module
  expression_cost(65536n, function_work(functions, constant_work(constants, Nil{})), 64n)

def cached_cost(names: List<&2, String>, +costs: Map<&2, Nat>, total: Nat) -> Maybe<&2, Nat>:
  match names:
    case Nil{}:
      Some{total}
    case name <> tail:
      do Maybe<&2, Nat>:
        cost : Nat <- Index.find(Nat, costs, name)
        cached_cost(tail, costs, Nat.add(total, Nat.sub(cost, 64n)))

def group_cost_found(found: Maybe<&2, Nat>, known: Catalog, job: G.Job) -> Nat:
  match found:
    case Some{cost}:
      cost
    case None{}:
      module_cost(group_module(known, job))

# Cost is scheduling metadata, not a validation budget. Per-declaration
# saturation may overestimate a large SCC; that SCC still remains indivisible.
def group_cost(+known: Catalog, +job: G.Job) -> Nat:
  Catalog{functions, constants, types, operations, costs, core, evidence, resolving} = known
  G.Job{members, dependencies, required_types} = job
  group_cost_found(cached_cost(members, costs, 64n), known, job)

type Completed is Data:
  Completed{
    interfaces: Map<&2, G.Interface>,
    functions: Map<&2, M.CheckedFunction>,
    constants: Map<&2, M.CheckedConstant>,
    published: List<&2, G.Interface>,
    failure: Maybe<&2, Failure>,
    certificates: List<&2, Core.Certificate>,
    needs: List<&2, G.GroupNeeds>
  }

def empty_completed() -> Completed:
  Completed{Map.new(&2, G.Interface), Map.new(&2, M.CheckedFunction), Map.new(&2, M.CheckedConstant), Nil{}, None{}, Nil{}, Nil{}}

def publish_checked(checked: G.CheckedGroup, completed: Completed) -> Completed:
  G.CheckedGroup{M.CheckedModule{cs, fs, types, operations}, +exported} = checked
  Completed{interfaces, functions, constants, published, failure, certificates, needs} = completed
  Completed{publish_interfaces(exported, interfaces), publish_functions(fs, functions), publish_constants(cs, constants), List.reverse.go(&2, G.Interface, exported, published), failure, certificates, needs}

def publish_failure(position: Nat, diagnostic: M.Diagnostic, completed: Completed) -> Completed:
  Completed{interfaces, functions, constants, published, failure, certificates, needs} = completed
  Completed{interfaces, functions, constants, published, first_failure(failure, Failure{position, diagnostic}), certificates, needs}

def publish_certificate(module: M.Module, checked: G.CheckedGroup, imports: List<&2, G.Interface>, completed: Completed) -> Completed:
  Completed{interfaces, functions, constants, published, failure, certificates, needs} = completed
  Completed{interfaces, functions, constants, published, failure, Core.Certificate{module, checked, imports} <> certificates, needs}

def publish_needs(resolved: List<&2, G.GroupNeeds>, completed: Completed) -> Completed:
  Completed{interfaces, functions, constants, published, failure, certificates, needs} = completed
  Completed{interfaces, functions, constants, published, failure, certificates, List.reverse.go(&2, G.GroupNeeds, resolved, needs)}

def publish_resolving(module: M.Module, resolved: G.Resolving, imports: List<&2, G.Interface>, completed: Completed) -> Completed:
  G.Resolving{+checked, needs} = resolved
  publish_needs(needs, publish_certificate(module, checked, imports, publish_checked(checked, completed)))

def publish_outcomes(outcomes: List<&2, Outcome>, completed: Completed) -> Completed:
  match outcomes:
    case Nil{}:
      completed
    case Outcome{position, Fail{diagnostic}} <> tail:
      publish_outcomes(tail, publish_failure(position, diagnostic, completed))
    case Outcome{position, Done{checked}} <> tail:
      publish_outcomes(tail, publish_checked(checked, completed))
    case EvidenceOutcome{position, module, imports, Fail{diagnostic}} <> tail:
      publish_outcomes(tail, publish_failure(position, diagnostic, completed))
    case EvidenceOutcome{position, module, imports, Done{resolved}} <> tail:
      publish_outcomes(tail, publish_resolving(module, resolved, imports, completed))

type Preparation is Data:
  Preparation{tasks: List<&2, Task>, failures: List<&2, Outcome>}

def prepare_result(position: Nat, result: Result<&2, &2, M.Diagnostic, Task>, preparation: Preparation) -> Preparation:
  match result preparation:
    case Done{task} Preparation{tasks, failures}:
      Preparation{task <> tasks, failures}
    case Fail{diagnostic} Preparation{tasks, failures}:
      Preparation{tasks, Outcome{position, Fail{diagnostic}} <> failures}

# Evidence checks certify every group, including groups that still contain
# deferred dispatch: a later resolution round retains unchanged ones. Callers
# that hand certificates to a final check keep only Core.source_ready groups.
def selected_task(found: Maybe<&2, G.CheckedGroup>, evidence: Bool, position: Nat, +subset: M.Module, imports: List<&2, G.Interface>) -> Task:
  match found evidence:
    case Some{checked} True{}:
      RetainedEvidenceTask{position, subset, imports, checked, Nil{}}
    case Some{checked} False{}:
      RetainedTask{position, checked}
    case None{} True{}:
      EvidenceTask{position, subset, imports, module_cost(subset)}
    case None{} False{}:
      Task{position, subset, imports, module_cost(subset)}

def resolving_task(found: Maybe<&2, G.Resolving>, +known: Catalog, +job: G.Job, position: Nat, +subset: M.Module, +imports: List<&2, G.Interface>) -> Task:
  match found:
    case Some{G.Resolving{checked, needs}}:
      RetainedEvidenceTask{position, subset, imports, checked, needs}
    case None{}:
      selected_task(retained_group(known, job, subset, imports), collecting(known), position, subset, imports)

def prepare_task(position: Nat, +job: G.Job, +known: Catalog, interfaces: Map<&2, G.Interface>) -> Result<&2, &2, M.Diagnostic, Task>:
  G.Job{members, dependencies, types} = job
  +subset = group_module(known, job)
  do Result<&2, &2, M.Diagnostic, Task>:
    +imports : List<&2, G.Interface> <- dependency_interfaces(dependencies, interfaces)
    return resolving_task(retained_resolving(known, job, subset, imports), known, job, position, subset, imports)

def next_allowed(ready: List<&2, Scheduled>, failure: Maybe<&2, Failure>) -> Bool:
  match ready:
    case Nil{}:
      False{}
    case Scheduled{position, level, job} <> tail:
      precedes_failure(position, failure)

def prepare_tasks(ready: List<&2, Scheduled>, +known: Catalog, +interfaces: Map<&2, G.Interface>, +failure: Maybe<&2, Failure>, preparation: Preparation, allowed: Bool) -> Preparation:
  match ready allowed:
    case Nil{} _:
      preparation
    case _ False{}:
      preparation
    case Scheduled{+position, level, job} <> +tail True{}:
      prepare_tasks(tail, known, interfaces, failure, prepare_result(position, prepare_task(position, job, known, interfaces), preparation), next_allowed(tail, failure))

def outcome_position(outcome: Outcome) -> Nat:
  match outcome:
    case Outcome{position, checked}:
      position
    case EvidenceOutcome{position, module, imports, checked}:
      position

def outcome_le(left: Outcome, right: Outcome) -> Bool:
  Nat.is_le(outcome_position(left), outcome_position(right))

def assembled(module: M.Module, completed: Completed) -> Result<&2, &2, M.Diagnostic, M.CheckedModule>:
  M.Module{constants, functions, types, operations} = module
  Completed{interfaces, checked_functions, checked_constants, published, failure, certificates, needs} = completed
  match failure:
    case Some{Failure{position, diagnostic}}:
      Fail{diagnostic}
    case None{}:
      do Result<&2, &2, M.Diagnostic, M.CheckedModule>:
        fs : List<&2, M.CheckedFunction> <- ordered_functions(functions, checked_functions)
        cs : List<&2, M.CheckedConstant> <- ordered_constants(constants, checked_constants)
        return M.CheckedModule{cs, fs, types, operations}

def next_frontier(scheduled: List<&2, Scheduled>) -> Frontier:
  match scheduled:
    case Nil{}:
      Frontier{Nil{}, Nil{}}
    case Scheduled{position, +level, job} <> tail:
      take_frontier(Scheduled{position, level, job} <> tail, level, Nil{}, True{})

def publish_preparation(preparation: Preparation, completed: Completed) -> Completed:
  Preparation{tasks, failures} = preparation
  outcomes = check_batch_same_catalog(List.reverse(&2, Task, tasks))
  ordered = List.sort(~Outcome, ~outcome_le, List.reverse.go(&2, Outcome, failures, outcomes))
  publish_outcomes(ordered, completed)

def check_frontier(+ready: List<&2, Scheduled>, known: Catalog, +completed: Completed) -> Completed:
  Completed{interfaces, functions, constants, published, +failure, certificates, needs} = completed
  publish_preparation(prepare_tasks(ready, known, interfaces, failure, Preparation{Nil{}, Nil{}}, next_allowed(ready, failure)), completed)

def check_frontiers(fuel: Nat, frontier: Frontier, +known: Catalog, completed: Completed) -> Result<&2, &2, M.Diagnostic, Completed>:
  match fuel frontier:
    case _ Frontier{Nil{}, Nil{}}:
      Done{completed}
    case 0n _:
      Fail{M.Diagnostic{"internal_error", "check_scheduler", "dependency frontier count exceeds its declaration group count"}}
    case 1n+rest Frontier{ready, pending}:
      check_frontiers(rest, next_frontier(pending), known, check_frontier(ready, known, completed))

def chain_cost(jobs: List<&2, Chains.Job>, +known: Catalog, cost: Nat) -> Nat:
  match jobs:
    case Nil{}:
      cost
    case Chains.Job{position, job} <> tail:
      chain_cost(tail, known, Nat.add(cost, group_cost(known, job)))

def weighted_chains(chains: List<&2, Chains.Chain>, +known: Catalog) -> List<&2, B.Weighted<Chains.Chain>>:
  match chains:
    case Nil{}:
      Nil{}
    case +chain <> tail:
      Chains.Chain{position, level, jobs} = chain
      B.Weighted{chain, chain_cost(jobs, known, 0n)} <> weighted_chains(tail, known)

def chain_batch(chains: List<&2, Chains.Chain>, known: Catalog) -> B.Batch<Chains.Chain>:
  B.plan(Chains.Chain, weighted_chains(chains, known), inference_grain())

def chain_allowed(jobs: List<&2, Chains.Job>, completed: Completed) -> Bool:
  match jobs:
    case Nil{}:
      False{}
    case Chains.Job{position, job} <> tail:
      Completed{interfaces, functions, constants, published, failure, certificates, needs} = completed
      precedes_failure(position, failure)

def check_chain(jobs: List<&2, Chains.Job>, +known: Catalog, completed: Completed, allowed: Bool) -> Completed:
  match jobs allowed:
    case Nil{} _:
      completed
    case _ False{}:
      completed
    case Chains.Job{position, job} <> +tail True{}:
      +next = check_frontier([Scheduled{position, 0n, job}], known, completed)
      check_chain(tail, known, next, chain_allowed(tail, next))

type ChainContext is Data:
  ChainContext{known: Catalog, interfaces: Map<&2, G.Interface>, failure: Maybe<&2, Failure>}

def run_chain(chain: Chains.Chain, context: ChainContext) -> Completed:
  Chains.Chain{position, level, +jobs} = chain
  ChainContext{known, interfaces, failure} = context
  +initial = {Completed{interfaces, Map.new(&2, M.CheckedFunction), Map.new(&2, M.CheckedConstant), Nil{}, failure, Nil{}, Nil{}} : Completed}
  check_chain(jobs, known, initial, chain_allowed(jobs, initial))

def merge_failure(previous: Maybe<&2, Failure>, candidate: Maybe<&2, Failure>) -> Maybe<&2, Failure>:
  match candidate:
    case None{}:
      previous
    case Some{failure}:
      first_failure(previous, failure)

# Branches inherit interfaces for lookup, but publish only their own results.
# Merging inherited environments repeats the shared prefix for every branch.
def merge_completed(chains: List<&2, Completed>, completed: Completed) -> Completed:
  match chains:
    case Nil{}:
      completed
    case Completed{ci, cf, cc, +published, failure, certificates, needs} <> tail:
      Completed{interfaces, functions, constants, prior_published, previous, prior_certificates, prior_needs} = completed
      merge_completed(tail, Completed{publish_interfaces(published, interfaces), Map.union(&2, M.CheckedFunction, functions, cf), Map.union(&2, M.CheckedConstant, constants, cc), List.reverse.go(&2, G.Interface, published, prior_published), merge_failure(previous, failure), List.reverse.go(&2, Core.Certificate, certificates, prior_certificates), List.reverse.go(&2, G.GroupNeeds, needs, prior_needs)})

def check_parallel_chains(ready: List<&2, Chains.Chain>, +known: Catalog, +completed: Completed) -> Completed:
  Completed{interfaces, functions, constants, published, failure, certificates, needs} = completed
  outcomes = B.execute(~Chains.Chain, ~ChainContext, ~Completed, ~run_chain, chain_batch(ready, known), ChainContext{known, interfaces, failure})
  merge_completed(outcomes, completed)

def singleton_jobs(chains: List<&2, Chains.Chain>) -> Maybe<&2, List<&2, Scheduled>>:
  match chains:
    case Nil{}:
      Some{Nil{}}
    case Chains.Chain{head, level, Chains.Job{position, job} <> Nil{}} <> tail:
      do Maybe<&2, List<&2, Scheduled>>:
        rest : List<&2, Scheduled> <- singleton_jobs(tail)
        return Scheduled{position, level, job} <> rest
    case _:
      None{}

def check_chain_frontier_planned(ready: List<&2, Chains.Chain>, known: Catalog, +completed: Completed, singletons: Maybe<&2, List<&2, Scheduled>>) -> Completed:
  match ready singletons:
    case Chains.Chain{position, level, +jobs} <> Nil{} _:
      check_chain(jobs, known, completed, chain_allowed(jobs, completed))
    case _ Some{scheduled}:
      check_frontier(scheduled, known, completed)
    case _ None{}:
      check_parallel_chains(ready, known, completed)

def check_chain_frontier(+ready: List<&2, Chains.Chain>, known: Catalog, completed: Completed) -> Completed:
  check_chain_frontier_planned(ready, known, completed, singleton_jobs(ready))

def check_chain_frontiers(fuel: Nat, frontier: Chains.Frontier, +known: Catalog, completed: Completed) -> Result<&2, &2, M.Diagnostic, Completed>:
  match fuel frontier:
    case _ Chains.Frontier{Nil{}, Nil{}}:
      Done{completed}
    case 0n _:
      Fail{M.Diagnostic{"internal_error", "check_scheduler", "dependency chain frontiers exceed their declaration group count"}}
    case 1n+rest Chains.Frontier{ready, pending}:
      check_chain_frontiers(rest, Chains.next_frontier(pending), known, check_chain_frontier(ready, known, completed))

def has_dependencies(jobs: List<&2, G.Job>) -> Bool:
  match jobs:
    case Nil{}:
      False{}
    case G.Job{members, Nil{}, types} <> tail:
      has_dependencies(tail)
    case head <> tail:
      True{}

def mono_singletons(jobs: List<&2, G.Job>, +count: Nat) -> Nat:
  match jobs:
    case Nil{}:
      count
    case G.Job{members, dependencies, types} <> tail:
      match members:
        case name <> Nil{}:
          mono_singletons(tail, Bool.pick(Nat, String.starts_with(name, "$mono["), 1n+count, count))
        case _:
          mono_singletons(tail, count)

def weighted_regions(regions: List<&2, Regions.Region>, +known: Catalog) -> List<&2, B.Weighted<Regions.Region>>:
  match regions:
    case Nil{}:
      Nil{}
    case +region <> tail:
      Regions.Region{chains} = region
      cost = B.total_cost(Chains.Chain, weighted_chains(chains, known), 0n)
      B.Weighted{region, cost} <> weighted_regions(tail, known)

def region_batch(regions: List<&2, Regions.Region>, known: Catalog) -> B.Batch<Regions.Region>:
  B.plan(Regions.Region, weighted_regions(regions, known), inference_grain())

def run_region(region: Regions.Region, context: ChainContext) -> Result<&2, &2, M.Diagnostic, Completed>:
  Regions.Region{+chains} = region
  ChainContext{known, interfaces, failure} = context
  initial = {Completed{interfaces, Map.new(&2, M.CheckedFunction), Map.new(&2, M.CheckedConstant), Nil{}, failure, Nil{}, Nil{}} : Completed}
  check_chain_frontiers(List.length(&2, Chains.Chain, chains), Chains.next_frontier(chains), known, initial)

def merge_regions(outcomes: List<&2, Result<&2, &2, M.Diagnostic, Completed>>, completed: Completed) -> Result<&2, &2, M.Diagnostic, Completed>:
  match outcomes:
    case Nil{}:
      Done{completed}
    case Fail{diagnostic} <> tail:
      Fail{diagnostic}
    case Done{region} <> tail:
      merge_regions(tail, merge_completed([region], completed))

def check_regions(regions: List<&2, Regions.Region>, +known: Catalog, +completed: Completed) -> Result<&2, &2, M.Diagnostic, Completed>:
  match regions:
    case Regions.Region{+chains} <> Nil{}:
      check_chain_frontiers(List.length(&2, Chains.Chain, chains), Chains.next_frontier(chains), known, completed)
    case _:
      Completed{interfaces, functions, constants, published, failure, certificates, needs} = completed
      outcomes = B.execute(~Regions.Region, ~ChainContext, ~Result<&2, &2, M.Diagnostic, Completed>, ~run_region, region_batch(regions, known), ChainContext{known, interfaces, failure})
      merge_regions(outcomes, completed)

def check_dependent_jobs(flat: Bool, +jobs: List<&2, G.Job>, +known: Catalog, completed: Completed) -> Result<&2, &2, M.Diagnostic, Completed>:
  match flat:
    case True{}:
      do Result<&2, &2, M.Diagnostic, Completed>:
        scheduled : List<&2, Scheduled> <- schedule(jobs)
        check_frontiers(List.length(&2, G.Job, jobs), next_frontier(scheduled), known, completed)
    case False{}:
      do Result<&2, &2, M.Diagnostic, Completed>:
        chains : List<&2, Chains.Chain> <- Chains.plan(jobs)
        +rooted : Regions.RootedPlan <- Regions.rooted_plan(chains)
        check_regions(Regions.branches(rooted), known, check_chain_frontier(Regions.prefix(rooted), known, completed))

def check_jobs(+jobs: List<&2, G.Job>, +known: Catalog, completed: Completed, dependent: Bool) -> Result<&2, &2, M.Diagnostic, Completed>:
  match dependent:
    case False{}:
      do Result<&2, &2, M.Diagnostic, Completed>:
        scheduled : List<&2, Scheduled> <- schedule(jobs)
        check_frontiers(List.length(&2, G.Job, jobs), next_frontier(scheduled), known, completed)
    case True{}:
      # The chain route separates most generated singleton siblings. At eight
      # or more such jobs, dependency-level frontiers expose complete groups
      # for one independent check per exact clone class.
      check_dependent_jobs(Nat.is_le(8n, mono_singletons(jobs, 0n)), jobs, known, completed)

def check_module_core(+module: M.Module, certificates: List<&2, Core.Certificate>) -> Result<&2, &2, M.Diagnostic, M.CheckedModule>:
  do Result<&2, &2, M.Diagnostic, M.CheckedModule>:
    +jobs : List<&2, G.Job> <- G.plan(module)
    completed : Completed <- check_jobs(jobs, with_core(catalog(module), module, certificates), empty_completed(), has_dependencies(jobs))
    assembled(module, completed)

# `certificates` covers every current group; `needs` lists the closed dispatch
# requirements inferred or atomically retained with their checked group.
type Initial is Data:
  Initial{checked: M.CheckedModule, certificates: List<&2, Core.Certificate>, needs: List<&2, G.GroupNeeds>}

# A failed source check still certifies every complete SCC that succeeded.
# These certificates are exact-source evidence; the caller may use them while
# checking the original module without adopting a rewritten round's error.
type InitialAttempt is Data:
  CheckedInitial{initial: Initial, inferred: Nat, retained: Nat}
  FailedInitial{diagnostic: M.Diagnostic, certificates: List<&2, Core.Certificate>, inferred: Nat, retained: Nat}

def initial_checked(initial: Initial) -> M.CheckedModule:
  Initial{checked, certificates, needs} = initial
  checked

def initial_certificates(initial: Initial) -> List<&2, Core.Certificate>:
  Initial{checked, certificates, needs} = initial
  certificates

def retained_members(members: List<&2, String>, module: M.Module, imports: List<&2, G.Interface>, available: Map<&2, List<&2, Core.Certificate>>) -> Bool:
  match members:
    case Nil{}:
      False{}
    case name <> tail:
      Maybe.is_some(&2, G.CheckedGroup, Core.available_candidates(Index.find(List<&2, Core.Certificate>, available, name), module, imports))

def retained_certificate(certificate: Core.Certificate, available: Map<&2, List<&2, Core.Certificate>>) -> Bool:
  Core.Certificate{+module, checked, imports} = certificate
  retained_members(Core.names(module), module, imports, available)

def retained_count(certificates: List<&2, Core.Certificate>, +available: Map<&2, List<&2, Core.Certificate>>, count: Nat) -> Nat:
  match certificates:
    case Nil{}:
      count
    case +certificate <> tail:
      retained_count(tail, available, Nat.add(count, Bool.pick(Nat, retained_certificate(certificate, available), 1n, 0n)))

type AuditCounts is Data:
  AuditCounts{inferred: Nat, retained: Nat}

def audit_counts(audit: Bool, module: M.Module, +issued: List<&2, Core.Certificate>, supplied: List<&2, Core.Certificate>) -> AuditCounts:
  match audit:
    case False{}:
      AuditCounts{0n, 0n}
    case True{}:
      +retained = retained_count(issued, Core.index_for(module, supplied), 0n)
      AuditCounts{Nat.sub(List.length(&2, Core.Certificate, issued), retained), retained}

def assembled_attempt(result: Result<&2, &2, M.Diagnostic, M.CheckedModule>, issued: List<&2, Core.Certificate>, needs: List<&2, G.GroupNeeds>, counts: AuditCounts) -> InitialAttempt:
  match result counts:
    case Done{checked} AuditCounts{inferred, retained}:
      CheckedInitial{Initial{checked, issued, List.reverse(&2, G.GroupNeeds, needs)}, inferred, retained}
    case Fail{diagnostic} AuditCounts{inferred, retained}:
      FailedInitial{diagnostic, issued, inferred, retained}

def initial_attempt(+module: M.Module, +completed: Completed, supplied: List<&2, Core.Certificate>, audit: Bool) -> InitialAttempt:
  Completed{interfaces, functions, constants, published, failure, certificates, needs} = completed
  +issued = List.reverse(&2, Core.Certificate, certificates)
  assembled_attempt(assembled(module, completed), issued, needs, audit_counts(audit, module, issued, supplied))

def failed_attempt(diagnostic: M.Diagnostic) -> InitialAttempt:
  FailedInitial{diagnostic, Nil{}, 0n, 0n}

def checked_attempt(result: Result<&2, &2, M.Diagnostic, Completed>, module: M.Module, certificates: List<&2, Core.Certificate>, audit: Bool) -> InitialAttempt:
  match result:
    case Fail{diagnostic}:
      failed_attempt(diagnostic)
    case Done{completed}:
      initial_attempt(module, completed, certificates, audit)

def planned_attempt(result: Result<&2, &2, M.Diagnostic, List<&2, G.Job>>, +module: M.Module, +certificates: List<&2, Core.Certificate>, audit: Bool) -> InitialAttempt:
  match result:
    case Fail{diagnostic}:
      failed_attempt(diagnostic)
    case Done{+jobs}:
      checked_attempt(check_jobs(jobs, with_evidence(with_core(catalog(module), module, certificates)), empty_completed(), has_dependencies(jobs)), module, certificates, audit)

def planned_reusing(result: Result<&2, &2, M.Diagnostic, List<&2, G.Job>>, +module: M.Module, +certificates: List<&2, Core.Certificate>, witnesses: Map<&2, List<&2, ResolvingCore.Witness>>) -> InitialAttempt:
  match result:
    case Fail{diagnostic}:
      failed_attempt(diagnostic)
    case Done{+jobs}:
      known = with_resolving(with_evidence(with_core(catalog(module), module, certificates)), witnesses)
      checked_attempt(check_jobs(jobs, known, empty_completed(), has_dependencies(jobs)), module, certificates, False{})

# Reuse only evidence paired inside the same successful source check. A bare
# deferred certificate still cannot provide the group's unresolved requirements.
# Generated/source-ready certificates retain their ordinary final-check lane.
def check_module_resolving_reusing(+module: M.Module, certificates: List<&2, Core.Certificate>, previous: Initial) -> InitialAttempt:
  Initial{checked, prior_certificates, needs} = previous
  witnesses = ResolvingCore.index(prior_certificates, needs, Map.new(&2, List<&2, ResolvingCore.Witness>))
  planned_reusing(G.plan(module), module, Core.ready_certificates(certificates), witnesses)

def check_module_resolving_attempt(+module: M.Module, certificates: List<&2, Core.Certificate>) -> InitialAttempt:
  planned_attempt(G.plan(module), module, certificates, False{})

# A pure probe for regression tests. Production checks skip the second lookup
# needed to count actual retained groups; their result fields stay zero.
def check_module_resolving_probe(+module: M.Module, certificates: List<&2, Core.Certificate>) -> InitialAttempt:
  planned_attempt(G.plan(module), module, certificates, True{})

def attempt_result(attempt: InitialAttempt) -> Result<&2, &2, M.Diagnostic, Initial>:
  match attempt:
    case CheckedInitial{initial, inferred, retained}:
      Done{initial}
    case FailedInitial{diagnostic, certificates, inferred, retained}:
      Fail{diagnostic}

# Source shape passes ask for principal, exact-SCC evidence. A group whose
# declarations and imported interfaces match one of `certificates` is retained
# (and certified again) instead of being inferred.
def check_module_resolving(+module: M.Module, certificates: List<&2, Core.Certificate>) -> Result<&2, &2, M.Diagnostic, Initial>:
  attempt_result(check_module_resolving_attempt(module, certificates))

def check_module_evidenced(module: M.Module) -> Result<&2, &2, M.Diagnostic, Initial>:
  check_module_resolving(module, Nil{})

# Direct IR checking and warm shape passes use the ordinary checker.
def check_module(module: M.Module) -> Result<&2, &2, M.Diagnostic, M.CheckedModule>:
  check_module_core(module, Nil{})
