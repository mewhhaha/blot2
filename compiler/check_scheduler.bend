import Base
import ./model.bend as M
import ./groups.bend as G
import ./index.bend as Index
import ./inference_batch.bend as B
import ./check_chain_plan.bend as Chains
import ./check_regions.bend as Regions

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
    costs: Map<&2, Nat>
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
  Catalog{index_functions(functions, 0n, Map.new(&2, Positioned<M.Function>)), index_constants(constants, 0n, Map.new(&2, Positioned<M.Constant>)), index_types(types, 0n, Map.new(&2, Positioned<M.DataType>)), operations, costs}

def catalog(module: M.Module) -> Catalog:
  catalog_costs(module, Map.new(&2, Nat))

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
  Catalog{functions, constants, types, operations, costs} = known
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

type Outcome is Data:
  Outcome{position: Nat, checked: Result<&2, &2, M.Diagnostic, G.CheckedGroup>}

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
  Task{position, module, dependencies, cost} = task
  Outcome{position, G.check_group(module, dependencies)}

def check_task_planned(task: Task, context: Unit) -> Outcome:
  Task{position, module, dependencies, cost} = task
  Outcome{position, G.check_group_planned(module, dependencies)}

def weighted_tasks(tasks: List<&2, Task>) -> List<&2, B.Weighted<Task>>:
  match tasks:
    case Nil{}:
      Nil{}
    case Task{position, module, dependencies, +cost} <> tail:
      B.Weighted{Task{position, module, dependencies, cost}, cost} <> weighted_tasks(tail)

def task_batch(tasks: List<&2, Task>, grain: Nat) -> B.Batch<Task>:
  B.plan(Task, weighted_tasks(tasks), grain)

def check_batch_with_grain(tasks: List<&2, Task>, grain: Nat) -> List<&2, Outcome>:
  B.execute(~Task, ~Unit, ~Outcome, ~check_task, task_batch(tasks, grain), Unit{})

def check_batch(tasks: List<&2, Task>) -> List<&2, Outcome>:
  check_batch_with_grain(tasks, inference_grain())

# The parent planner has already validated the complete module and graph.
def check_batch_planned(tasks: List<&2, Task>) -> List<&2, Outcome>:
  B.execute(~Task, ~Unit, ~Outcome, ~check_task_planned, task_batch(tasks, inference_grain()), Unit{})

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
  Catalog{functions, constants, types, operations, costs} = known
  G.Job{members, dependencies, required_types} = job
  group_cost_found(cached_cost(members, costs, 64n), known, job)

type Completed is Data:
  Completed{
    interfaces: Map<&2, G.Interface>,
    functions: Map<&2, M.CheckedFunction>,
    constants: Map<&2, M.CheckedConstant>,
    published: List<&2, G.Interface>,
    failure: Maybe<&2, Failure>
  }

def publish_outcomes(outcomes: List<&2, Outcome>, completed: Completed) -> Completed:
  match outcomes:
    case Nil{}:
      completed
    case Outcome{position, Fail{diagnostic}} <> tail:
      Completed{interfaces, functions, constants, published, failure} = completed
      publish_outcomes(tail, Completed{interfaces, functions, constants, published, first_failure(failure, Failure{position, diagnostic})})
    case Outcome{position, Done{G.CheckedGroup{M.CheckedModule{cs, fs, types, operations}, +exported}}} <> tail:
      Completed{interfaces, functions, constants, published, failure} = completed
      publish_outcomes(tail, Completed{publish_interfaces(exported, interfaces), publish_functions(fs, functions), publish_constants(cs, constants), List.reverse.go(&2, G.Interface, exported, published), failure})

type Preparation is Data:
  Preparation{tasks: List<&2, Task>, failures: List<&2, Outcome>}

def prepare_result(position: Nat, result: Result<&2, &2, M.Diagnostic, Task>, preparation: Preparation) -> Preparation:
  match result preparation:
    case Done{task} Preparation{tasks, failures}:
      Preparation{task <> tasks, failures}
    case Fail{diagnostic} Preparation{tasks, failures}:
      Preparation{tasks, Outcome{position, Fail{diagnostic}} <> failures}

def prepare_task(position: Nat, +job: G.Job, known: Catalog, interfaces: Map<&2, G.Interface>) -> Result<&2, &2, M.Diagnostic, Task>:
  G.Job{members, dependencies, types} = job
  +subset = group_module(known, job)
  do Result<&2, &2, M.Diagnostic, Task>:
    imports : List<&2, G.Interface> <- dependency_interfaces(dependencies, interfaces)
    return Task{position, subset, imports, module_cost(subset)}

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

def outcome_le(left: Outcome, right: Outcome) -> Bool:
  Outcome{a, x} = left
  Outcome{b, y} = right
  Nat.is_le(a, b)

def assembled(module: M.Module, completed: Completed) -> Result<&2, &2, M.Diagnostic, M.CheckedModule>:
  M.Module{constants, functions, types, operations} = module
  Completed{interfaces, checked_functions, checked_constants, published, failure} = completed
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
  outcomes = check_batch_planned(List.reverse(&2, Task, tasks))
  ordered = List.sort(~Outcome, ~outcome_le, List.reverse.go(&2, Outcome, failures, outcomes))
  publish_outcomes(ordered, completed)

def check_frontier(+ready: List<&2, Scheduled>, known: Catalog, +completed: Completed) -> Completed:
  Completed{interfaces, functions, constants, published, +failure} = completed
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
      Completed{interfaces, functions, constants, published, failure} = completed
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
  +initial = {Completed{interfaces, Map.new(&2, M.CheckedFunction), Map.new(&2, M.CheckedConstant), Nil{}, failure} : Completed}
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
    case Completed{ci, cf, cc, +published, failure} <> tail:
      Completed{interfaces, functions, constants, prior_published, previous} = completed
      merge_completed(tail, Completed{publish_interfaces(published, interfaces), Map.union(&2, M.CheckedFunction, functions, cf), Map.union(&2, M.CheckedConstant, constants, cc), List.reverse.go(&2, G.Interface, published, prior_published), merge_failure(previous, failure)})

def check_parallel_chains(ready: List<&2, Chains.Chain>, +known: Catalog, +completed: Completed) -> Completed:
  Completed{interfaces, functions, constants, published, failure} = completed
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
  initial = {Completed{interfaces, Map.new(&2, M.CheckedFunction), Map.new(&2, M.CheckedConstant), Nil{}, failure} : Completed}
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
      Completed{interfaces, functions, constants, published, failure} = completed
      outcomes = B.execute(~Regions.Region, ~ChainContext, ~Result<&2, &2, M.Diagnostic, Completed>, ~run_region, region_batch(regions, known), ChainContext{known, interfaces, failure})
      merge_regions(outcomes, completed)

def check_jobs(+jobs: List<&2, G.Job>, +known: Catalog, completed: Completed, dependent: Bool) -> Result<&2, &2, M.Diagnostic, Completed>:
  match dependent:
    case False{}:
      do Result<&2, &2, M.Diagnostic, Completed>:
        scheduled : List<&2, Scheduled> <- schedule(jobs)
        check_frontiers(List.length(&2, G.Job, jobs), next_frontier(scheduled), known, completed)
    case True{}:
      do Result<&2, &2, M.Diagnostic, Completed>:
        chains : List<&2, Chains.Chain> <- Chains.plan(jobs)
        +rooted : Regions.RootedPlan <- Regions.rooted_plan(chains)
        check_regions(Regions.branches(rooted), known, check_chain_frontier(Regions.prefix(rooted), known, completed))

def check_module(+module: M.Module) -> Result<&2, &2, M.Diagnostic, M.CheckedModule>:
  do Result<&2, &2, M.Diagnostic, M.CheckedModule>:
    +jobs : List<&2, G.Job> <- G.plan(module)
    completed : Completed <- check_jobs(jobs, catalog(module), Completed{Map.new(&2, G.Interface), Map.new(&2, M.CheckedFunction), Map.new(&2, M.CheckedConstant), Nil{}, None{}}, has_dependencies(jobs))
    assembled(module, completed)
