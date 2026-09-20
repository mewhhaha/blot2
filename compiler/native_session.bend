import Base
import ./model.bend as M
import ./main.bend as Main
import ./cst.bend as C
import ./lower.bend as L
import ./groups.bend as G
import ./const_eval.bend as Const
import ./wasm.bend as W
import ./native_cache_keys.bend as K
import ./native_response.bend as R
import ./index.bend as Index
import ./check_scheduler.bend as Scheduler

type Mode is Data:
  AnalyzeMode{}
  CompileMode{}

type Cached<-V: Data> is Data:
  Cached{keys: List<&2, List<&2, U32>>, value: V}

type Lowered is Data:
  Lowered{node: C.Cst, fuel: Nat, fragment: M.Module}

type Declaration is Data:
  Retained{identity: Nat}
  Replaced{node: C.Cst}

type State is Data:
  State{
    prelude: L.Prelude,
    scope_key: Maybe<&2, List<&2, U32>>,
    declarations: Map<&2, Lowered>,
    planning: Maybe<&2, Cached<List<&2, G.Job>>>,
    groups: Map<&2, Cached<G.CheckedGroup>>,
    constants: Map<&2, Cached<Const.Constants>>,
    entries: Map<&2, Cached<W.EntryCode>>
  }

type Output is Data:
  Analyzed{analysis: Main.Analysis}
  Compiled{artifact: Main.Artifact}

type Stats is Data:
  Stats{
    declarations_lowered: Nat,
    declarations_reused: Nat,
    groups_checked: Nat,
    groups_reused: Nat,
    constants_evaluated: Nat,
    constants_reused: Nat,
    entries_compiled: Nat,
    entries_reused: Nat
  }

# A failed transition has no candidate State: publishing is success-only.
type Completion is Data:
  Completion{state: State, output: Output, stats: Stats}

type Counts is Data:
  Counts{fresh: Nat, reused: Nat}

type Selected<-V: Data> is Data:
  Selected{value: V, reused: Bool}

def selected_value(-V: Data, chosen: Selected<V>) -> V:
  Selected{value, reused} = chosen
  value

def selected_reused(-V: Data, chosen: Selected<V>) -> Bool:
  Selected{value, reused} = chosen
  reused

def count(counts: Counts, reused: Bool) -> Counts:
  match counts reused:
    case Counts{fresh, old} True{}:
      Counts{fresh, 1n+old}
    case Counts{fresh, old} False{}:
      Counts{1n+fresh, old}

def key_parts_same(left: List<&2, List<&2, U32>>, right: List<&2, List<&2, U32>>, same: Bool) -> Bool:
  match left right same:
    case _ _ False{}:
      False{}
    case Nil{} Nil{} True{}:
      True{}
    case a <> xs b <> ys True{}:
      key_parts_same(xs, ys, K.same(a, b))
    case _ _ _:
      False{}

def cached_if(-V: Data, same: Bool, value: V) -> Maybe<&2, V>:
  match same:
    case True{}:
      Some{value}
    case False{}:
      None{}

def cached(-V: Data, previous: Maybe<&2, Cached<V>>, keys: List<&2, List<&2, U32>>) -> Maybe<&2, V>:
  match previous:
    case None{}:
      None{}
    case Some{Cached{prior, value}}:
      cached_if(V, key_parts_same(prior, keys, True{}), value)

def required(-V: Data, found: Maybe<&2, V>, name: String) -> Result<&2, &2, M.Diagnostic, V>:
  match found:
    case Some{value}:
      Done{value}
    case None{}:
      Fail{M.Diagnostic{"internal_error", name, "incremental plan omitted a required checked dependency"}}

def open(prelude: C.Cst, fuel: Nat) -> Result<&2, &2, M.Diagnostic, State>:
  do Result<&2, &2, M.Diagnostic, State>:
    prepared : L.Prelude <- L.prepare_prelude(prelude, fuel)
    return State{prepared, None{}, Map.new(&2, Lowered), None{}, Map.new(&2, Cached<G.CheckedGroup>), Map.new(&2, Cached<Const.Constants>), Map.new(&2, Cached<W.EntryCode>)}

type Lowering is Data:
  Lowering{fragments: List<&2, M.Module>, declarations: Map<&2, Lowered>, counts: Counts}

def lowered_fragment(lowered: Lowered) -> M.Module:
  Lowered{node, fuel, fragment} = lowered
  fragment

def source_equal(retained: Bool, previous: C.Cst, node: C.Cst) -> Bool:
  match retained:
    case True{}:
      True{}
    case False{}:
      K.same_cst(previous, node)

def retained_declaration(found: Maybe<&2, Unit>) -> Bool:
  match found:
    case Some{value}:
      True{}
    case None{}:
      False{}

def lower_hit(found: Maybe<&2, Lowered>, node: C.Cst, fuel: Nat, retained: Bool) -> Maybe<&2, Lowered>:
  match found:
    case None{}:
      None{}
    case Some{Lowered{+prior, +budget, fragment}}:
      cached_if(Lowered, Bool.and(source_equal(retained, prior, node), Nat.is_le(budget, fuel)), Lowered{prior, budget, fragment})

def lower_select(found: Maybe<&2, Lowered>, +node: C.Cst, scope: L.Context, +fuel: Nat) -> Result<&2, &2, M.Diagnostic, Selected<Lowered>>:
  match found:
    case Some{value}:
      Done{Selected{value, True{}}}
    case None{}:
      do Result<&2, &2, M.Diagnostic, Selected<Lowered>>:
        fragment : M.Module <- L.lower_source_declaration(node, scope, fuel)
        return Selected{Lowered{node, fuel, fragment}, False{}}

def lower_declarations(nodes: List<&2, C.Cst>, +scope: L.Context, +fuel: Nat, +previous: Map<&2, Lowered>, next: Map<&2, Lowered>, reversed: List<&2, M.Module>, counts: Counts, +retained: Set()) -> Result<&2, &2, M.Diagnostic, Lowering>:
  match nodes:
    case Nil{}:
      Done{Lowering{List.reverse(&2, M.Module, reversed), next, counts}}
    case +node <> tail:
      +owner = Nat.show(C.offset_of(node))
      do Result<&2, &2, M.Diagnostic, Lowering>:
        +chosen : Selected<Lowered> <- lower_select(lower_hit(Index.find(Lowered, previous, owner), node, fuel, retained_declaration(Index.find(Unit, retained, owner))), node, scope, fuel)
        +lowered : Lowered = selected_value(Lowered, chosen)
        lower_declarations(tail, scope, fuel, previous, Map.set(&2, Lowered, next, owner, lowered), lowered_fragment(lowered) <> reversed, count(counts, selected_reused(Lowered, chosen)), retained)

def reusable_scope(previous: Maybe<&2, List<&2, U32>>, key: List<&2, U32>, declarations: Map<&2, Lowered>) -> Map<&2, Lowered>:
  match previous:
    case None{}:
      Map.new(&2, Lowered)
    case Some{prior}:
      Bool.pick(Map<&2, Lowered>, K.same(prior, key), declarations, Map.new(&2, Lowered))

def combine_fragments(fragments: List<&2, M.Module>) -> M.Module:
  match fragments:
    case Nil{}:
      M.Module{Nil{}, Nil{}, Nil{}, Nil{}}
    case head <> tail:
      L.combine_modules(head, combine_fragments(tail))

def select_plan(found: Maybe<&2, List<&2, G.Job>>, plan: G.Planning) -> Result<&2, &2, M.Diagnostic, List<&2, G.Job>>:
  match found:
    case Some{jobs}:
      Done{jobs}
    case None{}:
      G.finish_plan(plan)

type CheckedGroups is Data:
  CheckedGroups{
    groups: Map<&2, Cached<G.CheckedGroup>>,
    interfaces: Map<&2, G.Interface>,
    functions: Map<&2, M.CheckedFunction>,
    constants: Map<&2, M.CheckedConstant>,
    closures: Map<&2, Set()>,
    base_keys: Map<&2, List<&2, U32>>,
    counts: Counts
  }

def empty_checked() -> CheckedGroups:
  CheckedGroups{Map.new(&2, Cached<G.CheckedGroup>), Map.new(&2, G.Interface), Map.new(&2, M.CheckedFunction), Map.new(&2, M.CheckedConstant), Map.new(&2, Set()), Map.new(&2, List<&2, U32>), Counts{0n, 0n}}

def dependency_closure(names: List<&2, String>, +known: Map<&2, Set()>, found: Set()) -> Result<&2, &2, M.Diagnostic, Set()>:
  match names:
    case Nil{}:
      Done{found}
    case +name <> tail:
      do Result<&2, &2, M.Diagnostic, Set()>:
        inherited : Set() <- required(Set(), Index.find(Set(), known, name), name)
        dependency_closure(tail, known, Map.union(&2, Unit, found, inherited))

def publish_closure(names: List<&2, String>, +closure: Set(), known: Map<&2, Set()>) -> Map<&2, Set()>:
  match names:
    case Nil{}:
      known
    case name <> tail:
      publish_closure(tail, closure, Map.set(&2, Set(), known, name, closure))

def group_owner(members: List<&2, String>) -> Result<&2, &2, M.Diagnostic, String>:
  match members:
    case head <> tail:
      Done{head}
    case Nil{}:
      Fail{M.Diagnostic{"internal_error", "native_session", "incremental planner returned an empty declaration group"}}

def checked_group_checked(group: G.CheckedGroup) -> M.CheckedModule:
  G.CheckedGroup{checked, interfaces} = group
  checked

def checked_group_interfaces(group: G.CheckedGroup) -> List<&2, G.Interface>:
  G.CheckedGroup{checked, interfaces} = group
  interfaces

def publish_group(state: CheckedGroups, owner: String, members: List<&2, String>, closure: Set(), base_key: List<&2, U32>, keys: List<&2, List<&2, U32>>, +selected: Selected<G.CheckedGroup>) -> CheckedGroups:
  CheckedGroups{groups, interfaces, functions, constants, closures, base_keys, counts} = state
  +value = selected_value(G.CheckedGroup, selected)
  +checked = checked_group_checked(value)
  +name = owner
  CheckedGroups{Map.set(&2, Cached<G.CheckedGroup>, groups, name, Cached{keys, value}), Scheduler.publish_interfaces(checked_group_interfaces(value), interfaces), Scheduler.publish_functions(Main.checked_functions(checked), functions), Scheduler.publish_constants(Main.checked_constants(checked), constants), publish_closure(members, closure, closures), Map.set(&2, List<&2, U32>, base_keys, name, base_key), count(counts, selected_reused(G.CheckedGroup, selected))}

type GroupSelection is Data:
  GroupHit{checked: G.CheckedGroup}
  GroupMiss{task: Scheduler.Task}

type PreparedGroup is Data:
  PreparedGroup{
    position: Nat,
    owner: String,
    members: List<&2, String>,
    closure: Set(),
    base_key: List<&2, U32>,
    keys: List<&2, List<&2, U32>>,
    selection: GroupSelection
  }

type GroupPreparation is Data:
  GroupPreparation{position: Nat, result: Result<&2, &2, M.Diagnostic, PreparedGroup>}

type GroupProgress is Data:
  GroupProgress{checked: CheckedGroups, failure: Maybe<&2, Scheduler.Failure>}

def select_group(found: Maybe<&2, G.CheckedGroup>, position: Nat, module: M.Module, dependencies: List<&2, G.Interface>, cost: Nat) -> GroupSelection:
  match found:
    case Some{value}:
      GroupHit{value}
    case None{}:
      GroupMiss{Scheduler.Task{position, module, dependencies, cost}}

def prepare_group(+position: Nat, job: G.Job, known: Scheduler.Catalog, previous: Map<&2, Cached<G.CheckedGroup>>, state: CheckedGroups) -> Result<&2, &2, M.Diagnostic, PreparedGroup>:
  G.Job{+members, +dependencies, types} = job
  CheckedGroups{groups, interfaces, functions, constants, closures, base_keys, counts} = state
  do Result<&2, &2, M.Diagnostic, PreparedGroup>:
    +owner : String <- group_owner(List.sort(~String, ~String.is_le, members))
    +subset : M.Module = Scheduler.group_module(known, G.Job{members, dependencies, types})
    +base_key : List<&2, U32> <- K.module(subset)
    +imports : List<&2, G.Interface> <- Scheduler.dependency_interfaces(dependencies, interfaces)
    imported_key : List<&2, U32> <- K.interfaces(imports)
    +keys : List<&2, List<&2, U32>> = [base_key, imported_key]
    selection : GroupSelection = select_group(cached(G.CheckedGroup, Index.find(Cached<G.CheckedGroup>, previous, owner), keys), position, subset, imports, List.length(&2, U32, base_key))
    closure : Set() <- dependency_closure(dependencies, closures, Set.add(Set.new(), owner))
    return PreparedGroup{position, owner, members, closure, base_key, keys, selection}

def prepare_groups(ready: List<&2, Scheduler.Scheduled>, +known: Scheduler.Catalog, +previous: Map<&2, Cached<G.CheckedGroup>>, +state: CheckedGroups, +failure: Maybe<&2, Scheduler.Failure>, reversed: List<&2, GroupPreparation>, allowed: Bool) -> List<&2, GroupPreparation>:
  match ready allowed:
    case Nil{} _:
      List.reverse(&2, GroupPreparation, reversed)
    case _ False{}:
      List.reverse(&2, GroupPreparation, reversed)
    case Scheduler.Scheduled{+position, level, job} <> +tail True{}:
      prepared = prepare_group(position, job, known, previous, state)
      prepare_groups(tail, known, previous, state, failure, GroupPreparation{position, prepared} <> reversed, Scheduler.next_allowed(tail, failure))

def group_tasks(prepared: List<&2, GroupPreparation>, reversed: List<&2, Scheduler.Task>) -> List<&2, Scheduler.Task>:
  match prepared:
    case Nil{}:
      List.reverse(&2, Scheduler.Task, reversed)
    case GroupPreparation{position, Done{PreparedGroup{index, owner, members, closure, base_key, keys, GroupMiss{task}}}} <> tail:
      group_tasks(tail, task <> reversed)
    case head <> tail:
      group_tasks(tail, reversed)

def group_failure(progress: GroupProgress, position: Nat, diagnostic: M.Diagnostic) -> GroupProgress:
  GroupProgress{checked, failure} = progress
  GroupProgress{checked, Scheduler.first_failure(failure, Scheduler.Failure{position, diagnostic})}

def group_success(progress: GroupProgress, owner: String, members: List<&2, String>, closure: Set(), base_key: List<&2, U32>, keys: List<&2, List<&2, U32>>, selected: Selected<G.CheckedGroup>) -> GroupProgress:
  GroupProgress{checked, failure} = progress
  GroupProgress{publish_group(checked, owner, members, closure, base_key, keys, selected), failure}

def publish_group_result(result: Result<&2, &2, M.Diagnostic, G.CheckedGroup>, progress: GroupProgress, position: Nat, owner: String, members: List<&2, String>, closure: Set(), base_key: List<&2, U32>, keys: List<&2, List<&2, U32>>) -> GroupProgress:
  match result:
    case Fail{diagnostic}:
      group_failure(progress, position, diagnostic)
    case Done{checked}:
      group_success(progress, owner, members, closure, base_key, keys, Selected{checked, False{}})

def checked_outcome(outcome: Scheduler.Outcome, expected: Nat) -> Result<&2, &2, M.Diagnostic, G.CheckedGroup>:
  Scheduler.Outcome{position, checked} = outcome
  Bool.pick(Result<&2, &2, M.Diagnostic, G.CheckedGroup>, Nat.is_eq(position, expected), checked, Fail{M.Diagnostic{"internal_error", "native_session", "inference batch changed declaration group order"}})

def publish_prepared(prepared: List<&2, GroupPreparation>, outcomes: List<&2, Scheduler.Outcome>, progress: GroupProgress) -> GroupProgress:
  match prepared outcomes:
    case Nil{} Nil{}:
      progress
    case Nil{} _:
      group_failure(progress, 0n, M.Diagnostic{"internal_error", "native_session", "inference batch returned an unexpected declaration group"})
    case GroupPreparation{position, Fail{diagnostic}} <> tail remaining:
      publish_prepared(tail, remaining, group_failure(progress, position, diagnostic))
    case GroupPreparation{position, Done{PreparedGroup{index, owner, members, closure, base_key, keys, GroupHit{checked}}}} <> tail remaining:
      publish_prepared(tail, remaining, group_success(progress, owner, members, closure, base_key, keys, Selected{checked, True{}}))
    case GroupPreparation{position, Done{PreparedGroup{index, owner, members, closure, base_key, keys, GroupMiss{task}}}} <> tail Nil{}:
      group_failure(progress, position, M.Diagnostic{"internal_error", "native_session", "inference batch omitted a declaration group"})
    case GroupPreparation{+position, Done{PreparedGroup{index, owner, members, closure, base_key, keys, GroupMiss{task}}}} <> tail outcome <> remaining:
      publish_prepared(tail, remaining, publish_group_result(checked_outcome(outcome, position), progress, position, owner, members, closure, base_key, keys))

def check_frontier(+ready: List<&2, Scheduler.Scheduled>, known: Scheduler.Catalog, previous: Map<&2, Cached<G.CheckedGroup>>, +progress: GroupProgress) -> GroupProgress:
  GroupProgress{state, +failure} = progress
  +prepared = prepare_groups(ready, known, previous, state, failure, Nil{}, Scheduler.next_allowed(ready, failure))
  publish_prepared(prepared, Scheduler.check_batch(group_tasks(prepared, Nil{})), progress)

def finish_groups(progress: GroupProgress) -> Result<&2, &2, M.Diagnostic, CheckedGroups>:
  match progress:
    case GroupProgress{checked, None{}}:
      Done{checked}
    case GroupProgress{checked, Some{Scheduler.Failure{position, diagnostic}}}:
      Fail{diagnostic}

# Only closed interfaces from completed frontiers enter the next one. A failed
# later ready job cannot hide an earlier job waiting on an earlier frontier.
def check_frontiers(fuel: Nat, frontier: Scheduler.Frontier, +known: Scheduler.Catalog, +previous: Map<&2, Cached<G.CheckedGroup>>, progress: GroupProgress) -> Result<&2, &2, M.Diagnostic, CheckedGroups>:
  match fuel frontier:
    case _ Scheduler.Frontier{Nil{}, Nil{}}:
      finish_groups(progress)
    case 0n _:
      Fail{M.Diagnostic{"internal_error", "native_session", "dependency frontier count exceeds its declaration group count"}}
    case 1n+rest Scheduler.Frontier{ready, pending}:
      check_frontiers(rest, Scheduler.next_frontier(pending), known, previous, check_frontier(ready, known, previous, progress))

def check_jobs(+jobs: List<&2, G.Job>, known: Scheduler.Catalog, previous: Map<&2, Cached<G.CheckedGroup>>, state: CheckedGroups) -> Result<&2, &2, M.Diagnostic, CheckedGroups>:
  do Result<&2, &2, M.Diagnostic, CheckedGroups>:
    scheduled : List<&2, Scheduler.Scheduled> <- Scheduler.schedule(jobs)
    check_frontiers(List.length(&2, G.Job, jobs), Scheduler.next_frontier(scheduled), known, previous, GroupProgress{state, None{}})

def assemble(module: M.Module, completed: CheckedGroups) -> Result<&2, &2, M.Diagnostic, M.CheckedModule>:
  M.Module{constants, functions, types, operations} = module
  CheckedGroups{groups, interfaces, checked_functions, checked_constants, closures, base_keys, counts} = completed
  do Result<&2, &2, M.Diagnostic, M.CheckedModule>:
    fs : List<&2, M.CheckedFunction> <- Scheduler.ordered_functions(functions, checked_functions)
    cs : List<&2, M.CheckedConstant> <- Scheduler.ordered_constants(constants, checked_constants)
    return M.CheckedModule{cs, fs, types, operations}

type Evaluated is Data:
  Evaluated{constants: Map<&2, Cached<Const.Constants>>, values: Const.Constants, counts: Counts}

def constant_bindings(value: Const.Constants) -> List<&2, Const.Binding<Const.Value>>:
  Const.Constants{bindings, remaining} = value
  bindings

def constant_remaining(value: Const.Constants) -> Nat:
  Const.Constants{bindings, remaining} = value
  remaining

def body_keys(owners: List<&2, String>, +known: Map<&2, List<&2, U32>>) -> Result<&2, &2, M.Diagnostic, List<&2, List<&2, U32>>>:
  match owners:
    case Nil{}:
      Done{Nil{}}
    case +name <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, List<&2, U32>>>:
        key : List<&2, U32> <- required(List<&2, U32>, Index.find(List<&2, U32>, known, name), name)
        rest : List<&2, List<&2, U32>> <- body_keys(tail, known)
        return key <> rest

def select_constant(found: Maybe<&2, Const.Constants>, constant: M.CheckedConstant, steps: Nat, context: Const.Context) -> Result<&2, &2, M.Diagnostic, Selected<Const.Constants>>:
  match found:
    case Some{value}:
      Done{Selected{value, True{}}}
    case None{}:
      do Result<&2, &2, M.Diagnostic, Selected<Const.Constants>>:
        value : Const.Constants <- Const.evaluate_constants([constant], steps, context)
        return Selected{value, False{}}

def evaluate_constants(constants: List<&2, M.CheckedConstant>, +steps: Nat, +context: Const.Context, +closures: Map<&2, Set()>, +base_keys: Map<&2, List<&2, U32>>, +previous: Map<&2, Cached<Const.Constants>>, next: Map<&2, Cached<Const.Constants>>, reversed: List<&2, Const.Binding<Const.Value>>, counts: Counts) -> Result<&2, &2, M.Diagnostic, Evaluated>:
  match constants:
    case Nil{}:
      Done{Evaluated{next, Const.Constants{List.reverse(&2, Const.Binding<Const.Value>, reversed), steps}, counts}}
    case M.CheckedConstant{M.Constant{+name, exported, annotation, expression}, ty, variables} <> tail:
      do Result<&2, &2, M.Diagnostic, Evaluated>:
        closure : Set() <- required(Set(), Index.find(Set(), closures, name), name)
        dependencies : List<&2, List<&2, U32>> <- body_keys(Set.to_list(closure), base_keys)
        budget : List<&2, U32> <- K.encode([K.Field{R.Natural{steps}}])
        +keys : List<&2, List<&2, U32>> = budget <> dependencies
        +chosen : Selected<Const.Constants> <- select_constant(cached(Const.Constants, Index.find(Cached<Const.Constants>, previous, name), keys), M.CheckedConstant{M.Constant{name, exported, annotation, expression}, ty, variables}, steps, context)
        +value : Const.Constants = selected_value(Const.Constants, chosen)
        evaluate_constants(tail, constant_remaining(value), context, closures, base_keys, previous, Map.set(&2, Cached<Const.Constants>, next, name, Cached{keys, value}), List.append(&2, Const.Binding<Const.Value>, List.reverse(&2, Const.Binding<Const.Value>, constant_bindings(value)), reversed), count(counts, selected_reused(Const.Constants, chosen)))

type CompiledEntries is Data:
  CompiledEntries{entries: Map<&2, Cached<W.EntryCode>>, values: List<&2, W.EntryCode>, counts: Counts}

type EntrySelection is Data:
  ReusedEntry{name: String, key: List<&2, U32>, value: W.EntryCode}
  FreshEntry{name: String, key: List<&2, U32>}

type EntryPlan is Data:
  EntryPlan{selections: List<&2, EntrySelection>, missing: List<&2, W.CodegenJob>, failure: Maybe<&2, M.Diagnostic>}

def select_entry(found: Maybe<&2, W.EntryCode>, job: W.CodegenJob, key: List<&2, U32>, plan: EntryPlan) -> EntryPlan:
  match found:
    case Some{value}:
      W.CodegenJob{name, parameter, body, captures} = job
      EntryPlan{selections, missing, failure} = plan
      EntryPlan{ReusedEntry{name, key, value} <> selections, missing, failure}
    case None{}:
      W.CodegenJob{+name, parameter, body, captures} = job
      EntryPlan{selections, missing, failure} = plan
      EntryPlan{FreshEntry{name, key} <> selections, W.CodegenJob{name, parameter, body, captures} <> missing, failure}

def plan_entry_key(encoded: Result<&2, &2, M.Diagnostic, List<&2, U32>>, +job: W.CodegenJob, previous: Map<&2, Cached<W.EntryCode>>, plan: EntryPlan) -> EntryPlan:
  match encoded:
    case Fail{error}:
      EntryPlan{selections, missing, failure} = plan
      EntryPlan{selections, missing, Some{error}}
    case Done{+key}:
      W.CodegenJob{name, parameter, body, captures} = job
      select_entry(cached(W.EntryCode, Index.find(Cached<W.EntryCode>, previous, name), [key]), job, key, plan)

def plan_entries(jobs: List<&2, W.CodegenJob>, +previous: Map<&2, Cached<W.EntryCode>>, plan: EntryPlan) -> EntryPlan:
  match jobs plan:
    case Nil{} EntryPlan{selections, missing, failure}:
      EntryPlan{List.reverse(&2, EntrySelection, selections), List.reverse(&2, W.CodegenJob, missing), failure}
    case _ EntryPlan{selections, missing, Some{error}}:
      EntryPlan{List.reverse(&2, EntrySelection, selections), List.reverse(&2, W.CodegenJob, missing), Some{error}}
    case +job <> tail EntryPlan{selections, missing, None{}}:
      plan_entries(tail, previous, plan_entry_key(K.entry(job), job, previous, EntryPlan{selections, missing, None{}}))

def finish_entries(failure: Maybe<&2, M.Diagnostic>, next: Map<&2, Cached<W.EntryCode>>, reversed: List<&2, W.EntryCode>, counts: Counts) -> Result<&2, &2, M.Diagnostic, CompiledEntries>:
  match failure:
    case Some{error}:
      Fail{error}
    case None{}:
      Done{CompiledEntries{next, List.reverse(&2, W.EntryCode, reversed), counts}}

def publish_entries(selections: List<&2, EntrySelection>, compiled: List<&2, W.EntryCode>, failure: Maybe<&2, M.Diagnostic>, next: Map<&2, Cached<W.EntryCode>>, reversed: List<&2, W.EntryCode>, counts: Counts) -> Result<&2, &2, M.Diagnostic, CompiledEntries>:
  match selections compiled:
    case Nil{} Nil{}:
      finish_entries(failure, next, reversed, counts)
    case ReusedEntry{+name, key, +value} <> tail _:
      publish_entries(tail, compiled, failure, Map.set(&2, Cached<W.EntryCode>, next, name, Cached{[key], value}), value <> reversed, count(counts, True{}))
    case FreshEntry{+name, key} <> tail W.EntryCode{+found, code} <> rest:
      do Result<&2, &2, M.Diagnostic, CompiledEntries>:
        valid : Unit <- W.matching_entry(M.name_equal(name, found), name)
        +value : W.EntryCode = W.EntryCode{found, code}
        publish_entries(tail, rest, failure, Map.set(&2, Cached<W.EntryCode>, next, name, Cached{[key], value}), value <> reversed, count(counts, False{}))
    case _ _:
      Fail{M.Diagnostic{"internal_error", "codegen", "incremental codegen results do not match the miss plan"}}

# Key errors remain behind all earlier misses, preserving the old serial
# diagnostic order. Cache hits never enter the compiler's parallel work tree.
def compile_entry_plan(plan: EntryPlan, next: Map<&2, Cached<W.EntryCode>>, reversed: List<&2, W.EntryCode>, counts: Counts) -> Result<&2, &2, M.Diagnostic, CompiledEntries>:
  EntryPlan{selections, missing, failure} = plan
  do Result<&2, &2, M.Diagnostic, CompiledEntries>:
    compiled : List<&2, W.EntryCode> <- W.compile_entries(missing)
    publish_entries(selections, compiled, failure, next, reversed, counts)

def compile_jobs(jobs: List<&2, W.CodegenJob>, previous: Map<&2, Cached<W.EntryCode>>, next: Map<&2, Cached<W.EntryCode>>, reversed: List<&2, W.EntryCode>, counts: Counts) -> Result<&2, &2, M.Diagnostic, CompiledEntries>:
  compile_entry_plan(plan_entries(jobs, previous, EntryPlan{Nil{}, Nil{}, None{}}), next, reversed, counts)

def stats(declarations: Counts, groups: Counts, constants: Counts, entries: Counts) -> Stats:
  Counts{dl, dr} = declarations
  Counts{gc, gr} = groups
  Counts{ce, cr} = constants
  Counts{ec, er} = entries
  Stats{dl, dr, gc, gr, ce, cr, ec, er}

def finish_compiled(state: State, analysis: Main.Analysis, +prepared: W.Prepared, compiled: CompiledEntries, declarations: Counts, groups: Counts, constants: Counts) -> Result<&2, &2, M.Diagnostic, Completion>:
  State{prelude, scope_key, lowered, planning, checked, evaluated, previous} = state
  CompiledEntries{entries, values, entry_counts} = compiled
  do Result<&2, &2, M.Diagnostic, Completion>:
    bytes : List<&2, U32> <- W.link(prepared, values)
    return Completion{State{prelude, scope_key, lowered, planning, checked, evaluated, entries}, Compiled{Main.Artifact{analysis, bytes}}, stats(declarations, groups, constants, entry_counts)}

def state_entries(state: State) -> Map<&2, Cached<W.EntryCode>>:
  State{prelude, scope_key, lowered, planning, checked, evaluated, entries} = state
  entries

def finish(mode: Mode, +state: State, +analysis: Main.Analysis, declarations: Counts, groups: Counts, constants: Counts) -> Result<&2, &2, M.Diagnostic, Completion>:
  match mode:
    case AnalyzeMode{}:
      Done{Completion{state, Analyzed{analysis}, stats(declarations, groups, constants, Counts{0n, 0n})}}
    case CompileMode{}:
      do Result<&2, &2, M.Diagnostic, Completion>:
        +prepared : W.Prepared <- W.prepare(Main.analysis_checked(analysis), Main.analysis_constants(analysis))
        compiled : CompiledEntries <- compile_jobs(W.prepared_jobs(prepared), state_entries(state), Map.new(&2, Cached<W.EntryCode>), Nil{}, Counts{0n, 0n})
        finish_compiled(state, analysis, prepared, compiled, declarations, groups, constants)

def update_evaluated(state: State, mode: Mode, checked: M.CheckedModule, evaluated: Evaluated, declaration_counts: Counts, group_counts: Counts) -> Result<&2, &2, M.Diagnostic, Completion>:
  State{prelude, scope_key, declarations, planning, groups, previous_constants, entries} = state
  Evaluated{constants, Const.Constants{bindings, remaining}, constant_counts} = evaluated
  next = {State{prelude, scope_key, declarations, planning, groups, constants, entries} : State}
  finish(mode, next, Main.Analysis{checked, bindings, remaining}, declaration_counts, group_counts, constant_counts)

def update_checked(state: State, mode: Mode, +module: M.Module, +completed: CheckedGroups, declaration_counts: Counts, steps: Nat) -> Result<&2, &2, M.Diagnostic, Completion>:
  State{prelude, scope_key, declarations, planning, previous_groups, previous_constants, entries} = state
  CheckedGroups{groups, interfaces, functions, constants, closures, base_keys, group_counts} = completed
  do Result<&2, &2, M.Diagnostic, Completion>:
    +checked : M.CheckedModule <- assemble(module, completed)
    evaluated : Evaluated <- evaluate_constants(Main.checked_constants(checked), steps, Main.const_context(module, checked), closures, base_keys, previous_constants, Map.new(&2, Cached<Const.Constants>), Nil{}, Counts{0n, 0n})
    update_evaluated(State{prelude, scope_key, declarations, planning, groups, Map.new(&2, Cached<Const.Constants>), entries}, mode, checked, evaluated, declaration_counts, group_counts)

def update_lowered(state: State, mode: Mode, prelude_module: M.Module, scope_words: List<&2, U32>, lowered: Lowering, steps: Nat) -> Result<&2, &2, M.Diagnostic, Completion>:
  State{prelude, scope_key, declarations, planning, previous_groups, constants, entries} = state
  Lowering{fragments, next_declarations, declaration_counts} = lowered
  +module = combine_fragments(prelude_module <> fragments)
  do Result<&2, &2, M.Diagnostic, Completion>:
    +plan : G.Planning <- G.prepare_plan(module)
    +plan_key : List<&2, U32> <- K.planning(plan)
    +jobs : List<&2, G.Job> <- select_plan(cached(List<&2, G.Job>, planning, [plan_key]), plan)
    completed : CheckedGroups <- check_jobs(jobs, Scheduler.catalog(module), previous_groups, empty_checked())
    update_checked(State{prelude, Some{scope_words}, next_declarations, Some{Cached{[plan_key], jobs}}, Map.new(&2, Cached<G.CheckedGroup>), constants, entries}, mode, module, completed, declaration_counts, steps)

def unique_identity(found: Maybe<&2, Unit>, identity: Nat) -> Result<&2, &2, M.Diagnostic, Unit>:
  match found:
    case None{}:
      Done{Unit{}}
    case Some{value}:
      Fail{M.Diagnostic{"native_session", "offset:" ++ Nat.show(identity), "declaration identities must be unique within a revision"}}

def unique_declaration_ids(nodes: List<&2, C.Cst>, +seen: Set()) -> Result<&2, &2, M.Diagnostic, Unit>:
  match nodes:
    case Nil{}:
      Done{Unit{}}
    case node <> tail:
      +identity = C.offset_of(node)
      +key = Nat.show(identity)
      do Result<&2, &2, M.Diagnostic, Unit>:
        unique : Unit <- unique_identity(Index.find(Unit, seen, key), identity)
        unique_declaration_ids(tail, Set.add(seen, key))

def update_source(+state: State, mode: Mode, source: L.SourcePlan, fuel: Nat, steps: Nat, retained: Set()) -> Result<&2, &2, M.Diagnostic, Completion>:
  State{prelude, scope_key, declarations, planning, groups, constants, entries} = state
  L.SourcePlan{prelude_module, +scope, +nodes} = source
  do Result<&2, &2, M.Diagnostic, Completion>:
    unique : Unit <- unique_declaration_ids(nodes, Set.new())
    +scope_words : List<&2, U32> <- K.scope(scope)
    lowered : Lowering <- lower_declarations(nodes, scope, fuel, reusable_scope(scope_key, scope_words, declarations), Map.new(&2, Lowered), Nil{}, Counts{0n, 0n}, retained)
    update_lowered(state, mode, prelude_module, scope_words, lowered, steps)

def update(+state: State, mode: Mode, root: C.Cst, fuel: Nat, steps: Nat) -> Result<&2, &2, M.Diagnostic, Completion>:
  State{prelude, scope_key, declarations, planning, groups, constants, entries} = state
  do Result<&2, &2, M.Diagnostic, Completion>:
    source : L.SourcePlan <- L.prepare_source(root, prelude)
    update_source(state, mode, source, fuel, steps, Set.new())

type ResolvedDeclarations is Data:
  ResolvedDeclarations{nodes: List<&2, C.Cst>, retained: Set()}

def require_retained(found: Maybe<&2, Lowered>, identity: Nat) -> Result<&2, &2, M.Diagnostic, C.Cst>:
  match found:
    case Some{Lowered{node, fuel, fragment}}:
      Done{node}
    case None{}:
      Fail{M.Diagnostic{"native_session", "offset:" ++ Nat.show(identity), "retained declaration is absent from the last successful revision"}}

def require_declaration(valid: Bool, node: C.Cst) -> Result<&2, &2, M.Diagnostic, C.Cst>:
  match valid:
    case True{}:
      Done{node}
    case False{}:
      Fail{C.diagnostic(node, "native_session", "replacement must have the declarations field")}

def resolve_declarations(pending: List<&2, Declaration>, +previous: Map<&2, Lowered>, reversed: List<&2, C.Cst>, retained: Set()) -> Result<&2, &2, M.Diagnostic, ResolvedDeclarations>:
  match pending:
    case Nil{}:
      Done{ResolvedDeclarations{List.reverse(&2, C.Cst, reversed), retained}}
    case Retained{+identity} <> tail:
      +key = Nat.show(identity)
      do Result<&2, &2, M.Diagnostic, ResolvedDeclarations>:
        node : C.Cst <- require_retained(Index.find(Lowered, previous, key), identity)
        resolve_declarations(tail, previous, node <> reversed, Set.add(retained, key))
    case Replaced{C.Cst{kind, +field, text, offset, children}} <> tail:
      do Result<&2, &2, M.Diagnostic, ResolvedDeclarations>:
        node : C.Cst <- require_declaration(M.name_equal(field, "declarations"), C.Cst{kind, field, text, offset, children})
        resolve_declarations(tail, previous, node <> reversed, retained)

def update_resolved(+state: State, mode: Mode, resolved: ResolvedDeclarations, fuel: Nat, steps: Nat) -> Result<&2, &2, M.Diagnostic, Completion>:
  State{prelude, scope_key, declarations, planning, groups, constants, entries} = state
  ResolvedDeclarations{nodes, retained} = resolved
  do Result<&2, &2, M.Diagnostic, Completion>:
    source : L.SourcePlan <- L.prepare_source(C.Cst{"module", "", "", 0n, nodes}, prelude)
    update_source(state, mode, source, fuel, steps, retained)

# References name only declarations held by the last successful State. The
# complete reconstructed source still passes scope, graph, type/effect, budget,
# and backend checks; a patch is transport compression, not semantic authority.
def update_patch(+state: State, mode: Mode, declarations: List<&2, Declaration>, fuel: Nat, steps: Nat) -> Result<&2, &2, M.Diagnostic, Completion>:
  State{prelude, scope_key, previous, planning, groups, constants, entries} = state
  do Result<&2, &2, M.Diagnostic, Completion>:
    resolved : ResolvedDeclarations <- resolve_declarations(declarations, previous, Nil{}, Set.new())
    update_resolved(state, mode, resolved, fuel, steps)
