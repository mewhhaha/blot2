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
import ./check_chain_plan.bend as Chains
import ./check_regions.bend as Regions
import ./inference_batch.bend as B
import ./native_plan.bend as Plan
import ./dependency.bend as D
import ./monomorph.bend as Mono
import ./dispatch_resolution.bend as Resolution
import ./effect_families.bend as Families
import ./check.bend as Check
import ./source_modules.bend as Modules
import ./catalog_versions.bend as CV
import ./entry_points.bend as Entries

type Mode is Data:
  AnalyzeMode{}
  CompileMode{}

type Cached<-V: Data> is Data:
  Cached{keys: List<&2, List<&2, U32>>, value: V}

type Lowered is Data:
  Lowered{node: C.Cst, fuel: Nat, fragment: M.Module, scanned: Plan.Scanned, nominals: Maybe<&2, Cached<Plan.Nominals>>}

type Declaration is Data:
  Retained{identity: Nat}
  Replaced{node: C.Cst}

type InferencePlan is Data:
  IndependentPlan{count: Nat, scheduled: List<&2, Scheduler.Scheduled>}
  RegionPlan{prefix: List<&2, Chains.Chain>, regions: List<&2, Regions.Region>}

type State is Data:
  State{
    prelude: L.Prelude,
    scope_key: Maybe<&2, List<&2, U32>>,
    declarations: Map<&2, Lowered>,
    planning: Maybe<&2, Cached<InferencePlan>>,
    groups: Map<&2, Cached<G.CheckedGroup>>,
    constants: Map<&2, Cached<Const.Constants>>,
    entries: Map<&2, Cached<W.EntryCode>>,
    specialization: Maybe<&2, Mono.Cache>,
    catalog_version: Maybe<&2, CV.Revision>
  }

type Output is Data:
  Analyzed{analysis: Main.Analysis}
  Compiled{artifact: Main.PlannedArtifact}

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
    return State{prepared, None{}, Map.new(&2, Lowered), None{}, Map.new(&2, Cached<G.CheckedGroup>), Map.new(&2, Cached<Const.Constants>), Map.new(&2, Cached<W.EntryCode>), None{}, None{}}

type Lowering is Data:
  Lowering{values: List<&2, Lowered>, scans: List<&2, Plan.Scanned>, counts: Counts}

def lowered_fragment(lowered: Lowered) -> M.Module:
  Lowered{node, fuel, fragment, scanned, nominals} = lowered
  fragment

def lowered_scan(lowered: Lowered) -> Plan.Scanned:
  Lowered{node, fuel, fragment, scanned, nominals} = lowered
  scanned

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
    case Some{Lowered{+prior, +budget, fragment, scanned, nominals}}:
      cached_if(Lowered, Bool.and(source_equal(retained, prior, node), Nat.is_le(budget, fuel)), Lowered{prior, budget, fragment, scanned, nominals})

type LoweringSelection is Data:
  LoweringHit{lowered: Lowered}
  LoweringMiss{}

type LoweringPlan is Data:
  LoweringPlan{selections: List<&2, LoweringSelection>, missing: List<&2, C.Cst>}

def select_lowering(found: Maybe<&2, Lowered>, node: C.Cst, plan: LoweringPlan) -> LoweringPlan:
  match found plan:
    case Some{value} LoweringPlan{selections, missing}:
      LoweringPlan{LoweringHit{value} <> selections, missing}
    case None{} LoweringPlan{selections, missing}:
      LoweringPlan{LoweringMiss{} <> selections, node <> missing}

def plan_lowering(nodes: List<&2, C.Cst>, +fuel: Nat, +previous: Map<&2, Lowered>, +retained: Set(), plan: LoweringPlan) -> LoweringPlan:
  match nodes:
    case Nil{}:
      LoweringPlan{selections, missing} = plan
      LoweringPlan{List.reverse(&2, LoweringSelection, selections), List.reverse(&2, C.Cst, missing)}
    case +node <> tail:
      +owner = Nat.show(C.offset_of(node))
      found = lower_hit(Index.find(Lowered, previous, owner), node, fuel, retained_declaration(Index.find(Unit, retained, owner)))
      plan_lowering(tail, fuel, previous, retained, select_lowering(found, node, plan))

def lower_missing_leaf(nodes: List<&2, C.Cst>, +scope: L.Context, +fuel: Nat, reversed: List<&2, Lowered>) -> Result<&2, &2, M.Diagnostic, List<&2, Lowered>>:
  match nodes:
    case Nil{}:
      Done{List.reverse(&2, Lowered, reversed)}
    case +node <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, Lowered>>:
        +fragment : M.Module <- L.lower_source_declaration(node, scope, fuel)
        lower_missing_leaf(tail, scope, fuel, Lowered{node, fuel, fragment, Plan.scan(fragment), None{}} <> reversed)

# Sessions select the first failing source declaration, unlike clean lowering's
# tail-first traversal. Parallel completion order must not select the error.
def merge_lowered(left: Result<&2, &2, M.Diagnostic, List<&2, Lowered>>, right: Result<&2, &2, M.Diagnostic, List<&2, Lowered>>) -> Result<&2, &2, M.Diagnostic, List<&2, Lowered>>:
  do Result<&2, &2, M.Diagnostic, List<&2, Lowered>>:
    a : List<&2, Lowered> <- left
    b : List<&2, Lowered> <- right
    return List.reverse.go(&2, Lowered, List.reverse(&2, Lowered, a), b)

def lower_missing_batch(batch: L.DeclarationBatch, +scope: L.Context, +fuel: Nat) -> Result<&2, &2, M.Diagnostic, List<&2, Lowered>>:
  match batch:
    case L.DeclarationLeaf{nodes}:
      lower_missing_leaf(nodes, scope, fuel, Nil{})
    case L.DeclarationFork{L.DeclarationFork{L.DeclarationFork{a, b}, L.DeclarationFork{c, d}}, L.DeclarationFork{L.DeclarationFork{e, f}, L.DeclarationFork{g, h}}}:
      ra rb rc rd re rf rg rh = lower_missing_batch(a, scope, fuel) lower_missing_batch(b, scope, fuel) lower_missing_batch(c, scope, fuel) lower_missing_batch(d, scope, fuel) lower_missing_batch(e, scope, fuel) lower_missing_batch(f, scope, fuel) lower_missing_batch(g, scope, fuel) lower_missing_batch(h, scope, fuel)
      merge_lowered(merge_lowered(merge_lowered(ra, rb), merge_lowered(rc, rd)), merge_lowered(merge_lowered(re, rf), merge_lowered(rg, rh)))
    case L.DeclarationFork{L.DeclarationFork{a, b}, L.DeclarationFork{c, d}}:
      ra rb rc rd = lower_missing_batch(a, scope, fuel) lower_missing_batch(b, scope, fuel) lower_missing_batch(c, scope, fuel) lower_missing_batch(d, scope, fuel)
      merge_lowered(merge_lowered(ra, rb), merge_lowered(rc, rd))
    case L.DeclarationFork{left, right}:
      a b = lower_missing_batch(left, scope, fuel) lower_missing_batch(right, scope, fuel)
      merge_lowered(a, b)

def publish_lowered(selections: List<&2, LoweringSelection>, missing: List<&2, Lowered>, reversed: List<&2, Lowered>, scans: List<&2, Plan.Scanned>, counts: Counts) -> Result<&2, &2, M.Diagnostic, Lowering>:
  match selections missing:
    case Nil{} Nil{}:
      Done{Lowering{List.reverse(&2, Lowered, reversed), List.reverse(&2, Plan.Scanned, scans), counts}}
    case LoweringHit{+lowered} <> tail _:
      publish_lowered(tail, missing, lowered <> reversed, lowered_scan(lowered) <> scans, count(counts, True{}))
    case LoweringMiss{} <> tail +lowered <> rest:
      publish_lowered(tail, rest, lowered <> reversed, lowered_scan(lowered) <> scans, count(counts, False{}))
    case _ _:
      Fail{M.Diagnostic{"internal_error", "native_session", "lowering batch returned a different declaration count"}}

def lower_plan(plan: LoweringPlan, scope: L.Context, fuel: Nat) -> Result<&2, &2, M.Diagnostic, Lowering>:
  LoweringPlan{selections, +missing} = plan
  +missing_count = List.length(&2, C.Cst, missing)
  do Result<&2, &2, M.Diagnostic, Lowering>:
    lowered : List<&2, Lowered> <- lower_missing_batch(L.declaration_batches(48n, missing, missing_count, Nat.is_le(missing_count, 4n)), scope, fuel)
    publish_lowered(selections, lowered, Nil{}, Nil{}, Counts{0n, 0n})

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

type NominalContext is Data:
  NominalContext{key: List<&2, U32>, constructors: Map<&2, M.TypeId>}

def select_nominals(found: Maybe<&2, Plan.Nominals>, fragment: M.Module, constructors: Map<&2, M.TypeId>) -> Plan.Nominals:
  match found:
    case Some{scanned}:
      scanned
    case None{}:
      Plan.nominal_scan(fragment, constructors)

def refresh_nominals(lowered: Lowered, context: NominalContext) -> Lowered:
  Lowered{node, fuel, +fragment, scanned, nominals} = lowered
  NominalContext{+key, constructors} = context
  found = select_nominals(cached(Plan.Nominals, nominals, [key]), fragment, constructors)
  Lowered{node, fuel, fragment, scanned, Some{Cached{[key], found}}}

def sum_costs(costs: List<&2, Nat>, total: Nat) -> Nat:
  match costs:
    case Nil{}:
      total
    case head <> tail:
      sum_costs(tail, Nat.add(total, head))

def nominal_cost(found: Maybe<&2, Plan.Nominals>, scanned: Plan.Scanned) -> Nat:
  match found:
    case Some{value}:
      1n
    case None{}:
      Plan.Scanned{functions, constants, costs} = scanned
      sum_costs(Map.values(&2, Nat, costs), 16n)

def nominal_tasks(values: List<&2, Lowered>, +key: List<&2, U32>) -> List<&2, B.Weighted<Lowered>>:
  match values:
    case Nil{}:
      Nil{}
    case +value <> tail:
      Lowered{node, fuel, fragment, scanned, +nominals} = value
      cost = nominal_cost(cached(Plan.Nominals, nominals, [key]), scanned)
      B.Weighted{value, cost} <> nominal_tasks(tail, key)

type NominalRevision is Data:
  NominalRevision{declarations: Map<&2, Lowered>, usages: Plan.Nominals}

def merge_nominal_revision(found: Plan.Nominals, rest: NominalRevision) -> NominalRevision:
  NominalRevision{declarations, usages} = rest
  NominalRevision{declarations, Plan.merge_nominals(found, usages)}

def publish_nominals(values: List<&2, Lowered>, next: Map<&2, Lowered>) -> Result<&2, &2, M.Diagnostic, NominalRevision>:
  match values:
    case Nil{}:
      Done{NominalRevision{next, Plan.Nominals{Done{Nil{}}, Done{Nil{}}}}}
    case Lowered{node, fuel, fragment, scanned, None{}} <> tail:
      Fail{M.Diagnostic{"internal_error", "native_session", "nominal scan was not prepared"}}
    case Lowered{+node, fuel, fragment, scanned, Some{Cached{keys, +found}}} <> tail:
      value = {Lowered{node, fuel, fragment, scanned, Some{Cached{keys, found}}} : Lowered}
      do Result<&2, &2, M.Diagnostic, NominalRevision>:
        rest : NominalRevision <- publish_nominals(tail, Index.set(Lowered, next, Nat.show(C.offset_of(node)), value))
        return merge_nominal_revision(found, rest)

def nominal_declarations(revision: NominalRevision) -> Map<&2, Lowered>:
  NominalRevision{declarations, usages} = revision
  declarations

def nominal_usages(revision: NominalRevision, prelude: Plan.Nominals) -> Result<&2, &2, M.Diagnostic, List<&2, G.DeclarationUsage>>:
  NominalRevision{declarations, usages} = revision
  Plan.nominal_usages(Plan.merge_nominals(prelude, usages))

# Small summaries cost less to rescan than to retain, key, and publish.
# Use cached lowering estimates, never another body traversal or workload name.
def cache_nominal_scans(scans: List<&2, Plan.Scanned>, work: Nat, +count: Nat) -> Bool:
  match scans:
    case Nil{}:
      Bool.and(Nat.is_gt(count, 0n), Nat.is_ge(work, Nat.mul(count, 256n)))
    case Plan.Scanned{functions, constants, costs} <> tail:
      cache_nominal_scans(tail, sum_costs(Map.values(&2, Nat, costs), work), 1n+count)

def index_lowered(values: List<&2, Lowered>, next: Map<&2, Lowered>) -> Map<&2, Lowered>:
  match values:
    case Nil{}:
      next
    case Lowered{+node, fuel, fragment, scanned, nominals} <> tail:
      index_lowered(tail, Index.set(Lowered, next, Nat.show(C.offset_of(node)), Lowered{node, fuel, fragment, scanned, None{}}))

type PreparedPlanning is Data:
  PreparedPlanning{declarations: Map<&2, Lowered>, plan: G.Planning}

def planning_declarations(prepared: PreparedPlanning) -> Map<&2, Lowered>:
  PreparedPlanning{declarations, plan} = prepared
  declarations

def planning_value(prepared: PreparedPlanning) -> G.Planning:
  PreparedPlanning{declarations, plan} = prepared
  plan

def module_types(module: M.Module) -> List<&2, M.DataType>:
  M.Module{constants, functions, types, operations} = module
  types

def prepare_planning(+module: M.Module, prelude: M.Module, +values: List<&2, Lowered>, graph: List<&2, D.Node>, retain: Bool) -> Result<&2, &2, M.Diagnostic, PreparedPlanning>:
  match retain:
    case False{}:
      do Result<&2, &2, M.Diagnostic, PreparedPlanning>:
        plan : G.Planning <- G.prepare_plan_graph(module, Done{graph})
        return PreparedPlanning{index_lowered(values, Map.new(&2, Lowered)), plan}
    case True{}:
      +types = module_types(module)
      +constructors = G.constructor_index(types, Map.new(&2, M.TypeId))
      do Result<&2, &2, M.Diagnostic, PreparedPlanning>:
        +key : List<&2, U32> <- K.encode([K.DataTypes{types}])
        +nominals : NominalRevision <- publish_nominals(B.execute(~Lowered, ~NominalContext, ~Lowered, ~refresh_nominals, B.plan(Lowered, nominal_tasks(values, key), 512n), NominalContext{key, constructors}), Map.new(&2, Lowered))
        plan : G.Planning <- G.prepare_plan_usages(module, Done{graph}, nominal_usages(nominals, Plan.nominal_scan(prelude, constructors)))
        return PreparedPlanning{nominal_declarations(nominals), plan}

def inference_plan(+jobs: List<&2, G.Job>, dependent: Bool) -> Result<&2, &2, M.Diagnostic, InferencePlan>:
  match dependent:
    case False{}:
      do Result<&2, &2, M.Diagnostic, InferencePlan>:
        scheduled : List<&2, Scheduler.Scheduled> <- Scheduler.schedule(jobs)
        return IndependentPlan{List.length(&2, G.Job, jobs), scheduled}
    case True{}:
      do Result<&2, &2, M.Diagnostic, InferencePlan>:
        chains : List<&2, Chains.Chain> <- Chains.plan(jobs)
        +rooted : Regions.RootedPlan <- Regions.rooted_plan(chains)
        return RegionPlan{Regions.prefix(rooted), Regions.branches(rooted)}

# The existing planning key covers declaration order, edges and nominal type
# dependencies. Body-only edits can reuse the schedule as well as its SCCs.
def select_plan(found: Maybe<&2, InferencePlan>, plan: G.Planning) -> Result<&2, &2, M.Diagnostic, InferencePlan>:
  match found:
    case Some{scheduled}:
      Done{scheduled}
    case None{}:
      do Result<&2, &2, M.Diagnostic, InferencePlan>:
        +jobs : List<&2, G.Job> <- G.finish_plan(plan)
        inference_plan(jobs, Scheduler.has_dependencies(jobs))

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

# Each group contains only the exact body and short nominal-version tokens.
# The revision catalog was compared once before checking any cached group.
type CheckCatalog is Data:
  CheckCatalog{catalog: Scheduler.Catalog, revision: CV.Revision}

def check_catalog(value: CheckCatalog) -> Scheduler.Catalog:
  CheckCatalog{catalog, revision} = value
  catalog

def check_revision(value: CheckCatalog) -> CV.Revision:
  CheckCatalog{catalog, revision} = value
  revision

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
      publish_closure(tail, closure, Index.set(Set(), known, name, closure))

def group_owner(members: List<&2, String>) -> Result<&2, &2, M.Diagnostic, String>:
  match members:
    case head <> tail:
      Done{head}
    case Nil{}:
      Fail{M.Diagnostic{"internal_error", "native_session", "incremental planner returned an empty declaration group"}}

def checked_group_checked(group: G.CheckedGroup) -> M.CheckedModule:
  G.CheckedGroup{checked, interfaces, uses} = group
  checked

def checked_group_interfaces(group: G.CheckedGroup) -> List<&2, G.Interface>:
  G.CheckedGroup{checked, interfaces, uses} = group
  interfaces

def publish_group(state: CheckedGroups, owner: String, members: List<&2, String>, closure: Set(), base_key: List<&2, U32>, keys: List<&2, List<&2, U32>>, +selected: Selected<G.CheckedGroup>) -> CheckedGroups:
  CheckedGroups{groups, interfaces, functions, constants, closures, base_keys, counts} = state
  +value = selected_value(G.CheckedGroup, selected)
  +checked = checked_group_checked(value)
  +name = owner
  CheckedGroups{Index.set(Cached<G.CheckedGroup>, groups, name, Cached{keys, value}), Scheduler.publish_interfaces(checked_group_interfaces(value), interfaces), Scheduler.publish_functions(Main.checked_functions(checked), functions), Scheduler.publish_constants(Main.checked_constants(checked), constants), publish_closure(members, closure, closures), Index.set(List<&2, U32>, base_keys, name, base_key), count(counts, selected_reused(G.CheckedGroup, selected))}

type GroupSelection is Data:
  GroupHit{checked: G.CheckedGroup}
  GroupMiss{task: Scheduler.Task}
  GroupChecked{checked: G.CheckedGroup}

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

# A retained independent checking result is considered only after the finalized
# incremental cache misses. Its exact body, dependencies and catalog must match.
def select_retained_group(found: Maybe<&2, G.CheckedGroup>, known: CheckCatalog, job: G.Job, +subset: M.Module, +imports: List<&2, G.Interface>, position: Nat, cost: Nat) -> GroupSelection:
  match found:
    case Some{value}:
      GroupHit{value}
    case None{}:
      select_group(Scheduler.retained_group(check_catalog(known), job, subset, imports), position, subset, imports, cost)

def prepare_group(+position: Nat, +job: G.Job, +known: CheckCatalog, previous: Map<&2, Cached<G.CheckedGroup>>, state: CheckedGroups) -> Result<&2, &2, M.Diagnostic, PreparedGroup>:
  G.Job{+members, +dependencies, types} = job
  CheckedGroups{groups, interfaces, functions, constants, closures, base_keys, counts} = state
  do Result<&2, &2, M.Diagnostic, PreparedGroup>:
    +owner : String <- group_owner(List.sort(~String, ~String.is_le, members))
    +subset : M.Module = Scheduler.group_module(check_catalog(known), G.Job{members, dependencies, types})
    +base_key : List<&2, U32> <- CV.group_key(subset, check_revision(known))
    +imports : List<&2, G.Interface> <- Scheduler.dependency_interfaces(dependencies, interfaces)
    imported_key : List<&2, U32> <- K.interfaces(imports)
    +keys : List<&2, List<&2, U32>> = [base_key, imported_key]
    selection : GroupSelection = select_retained_group(cached(G.CheckedGroup, Index.find(Cached<G.CheckedGroup>, previous, owner), keys), known, job, subset, imports, position, List.length(&2, U32, base_key))
    closure : Set() <- dependency_closure(dependencies, closures, Set.add(Set.new(), owner))
    return PreparedGroup{position, owner, members, closure, base_key, keys, selection}

type GroupPreparationContext is Data:
  GroupPreparationContext{known: CheckCatalog, previous: Map<&2, Cached<G.CheckedGroup>>, state: CheckedGroups}

def prepare_group_task(scheduled: Scheduler.Scheduled, context: GroupPreparationContext) -> GroupPreparation:
  Scheduler.Scheduled{+position, level, job} = scheduled
  GroupPreparationContext{known, previous, state} = context
  GroupPreparation{position, prepare_group(position, job, known, previous, state)}

def group_preparation_cost(job: G.Job, known: CheckCatalog, small: Bool) -> Nat:
  match small:
    case True{}:
      0n
    case False{}:
      Scheduler.group_cost(check_catalog(known), job)

def group_preparation_tasks(ready: List<&2, Scheduler.Scheduled>, +known: CheckCatalog, +failure: Maybe<&2, Scheduler.Failure>, +small: Bool, reversed: List<&2, B.Weighted<Scheduler.Scheduled>>, allowed: Bool) -> List<&2, B.Weighted<Scheduler.Scheduled>>:
  match ready allowed:
    case Nil{} _:
      List.reverse(&2, B.Weighted<Scheduler.Scheduled>, reversed)
    case _ False{}:
      List.reverse(&2, B.Weighted<Scheduler.Scheduled>, reversed)
    case Scheduler.Scheduled{position, level, +job} <> +tail True{}:
      cost = group_preparation_cost(job, known, small)
      group_preparation_tasks(tail, known, failure, small, B.Weighted{Scheduler.Scheduled{position, level, job}, cost} <> reversed, Scheduler.next_allowed(tail, failure))

# Key construction reads one immutable frontier snapshot. Results retain source
# order; no candidate cache state is published by a worker. Small frontiers need
# no cost traversal or extra forks inside an already-parallel dependency region.
def prepare_groups(+ready: List<&2, Scheduler.Scheduled>, +known: CheckCatalog, previous: Map<&2, Cached<G.CheckedGroup>>, state: CheckedGroups, +failure: Maybe<&2, Scheduler.Failure>) -> List<&2, GroupPreparation>:
  tasks = group_preparation_tasks(ready, known, failure, Nat.is_le(List.length(&2, Scheduler.Scheduled, ready), 4n), Nil{}, Scheduler.next_allowed(ready, failure))
  B.execute(~Scheduler.Scheduled, ~GroupPreparationContext, ~GroupPreparation, ~prepare_group_task, B.plan(Scheduler.Scheduled, tasks, 2048n), GroupPreparationContext{known, previous, state})

def complete_preparation(prepared: Result<&2, &2, M.Diagnostic, PreparedGroup>) -> Result<&2, &2, M.Diagnostic, PreparedGroup>:
  match prepared:
    case Done{PreparedGroup{position, owner, members, closure, base_key, keys, GroupMiss{Scheduler.Task{index, module, dependencies, cost}}}}:
      do Result<&2, &2, M.Diagnostic, PreparedGroup>:
        checked : G.CheckedGroup <- G.check_group_planned(module, dependencies)
        return PreparedGroup{position, owner, members, closure, base_key, keys, GroupChecked{checked}}
    case other:
      other

def check_group_task(scheduled: Scheduler.Scheduled, context: GroupPreparationContext) -> GroupPreparation:
  Scheduler.Scheduled{+position, level, job} = scheduled
  GroupPreparationContext{known, previous, state} = context
  GroupPreparation{position, complete_preparation(prepare_group(position, job, known, previous, state))}

# Warm frontiers usually check few misses, so amortize their key work with a
# coarser grain. Cache presence affects scheduling only, never hit validation.
def group_pipeline_grain(previous: Map<&2, Cached<G.CheckedGroup>>) -> Nat:
  match previous:
    case MTip{}:
      Scheduler.inference_grain()
    case _:
      2048n

# Each leaf can begin inference before another leaf finishes its cache keys.
# Workers still read a single immutable frontier; publication remains ordered.
def check_groups(+ready: List<&2, Scheduler.Scheduled>, +known: CheckCatalog, +previous: Map<&2, Cached<G.CheckedGroup>>, state: CheckedGroups, +failure: Maybe<&2, Scheduler.Failure>) -> List<&2, GroupPreparation>:
  tasks = group_preparation_tasks(ready, known, failure, False{}, Nil{}, Scheduler.next_allowed(ready, failure))
  B.execute(~Scheduler.Scheduled, ~GroupPreparationContext, ~GroupPreparation, ~check_group_task, B.plan(Scheduler.Scheduled, tasks, group_pipeline_grain(previous)), GroupPreparationContext{known, previous, state})

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
  match outcome:
    case Scheduler.Outcome{position, checked}:
      Bool.pick(Result<&2, &2, M.Diagnostic, G.CheckedGroup>, Nat.is_eq(position, expected), checked, Fail{M.Diagnostic{"internal_error", "native_session", "inference batch changed declaration group order"}})
    case Scheduler.EvidenceOutcome{position, module, imports, checked}:
      Bool.pick(Result<&2, &2, M.Diagnostic, G.CheckedGroup>, Nat.is_eq(position, expected), Scheduler.resolving_checked(checked), Fail{M.Diagnostic{"internal_error", "native_session", "inference batch changed declaration group order"}})

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
    case GroupPreparation{position, Done{PreparedGroup{index, owner, members, closure, base_key, keys, GroupChecked{checked}}}} <> tail remaining:
      publish_prepared(tail, remaining, group_success(progress, owner, members, closure, base_key, keys, Selected{checked, False{}}))
    case GroupPreparation{position, Done{PreparedGroup{index, owner, members, closure, base_key, keys, GroupMiss{task}}}} <> tail Nil{}:
      group_failure(progress, position, M.Diagnostic{"internal_error", "native_session", "inference batch omitted a declaration group"})
    case GroupPreparation{+position, Done{PreparedGroup{index, owner, members, closure, base_key, keys, GroupMiss{task}}}} <> tail outcome <> remaining:
      publish_prepared(tail, remaining, publish_group_result(checked_outcome(outcome, position), progress, position, owner, members, closure, base_key, keys))

def check_single_group(scheduled: Scheduler.Scheduled, known: CheckCatalog, previous: Map<&2, Cached<G.CheckedGroup>>, +progress: GroupProgress, allowed: Bool) -> GroupProgress:
  match progress allowed:
    case prior False{}:
      prior
    case GroupProgress{+state, failure} True{}:
      publish_prepared([check_group_task(scheduled, GroupPreparationContext{known, previous, state})], Nil{}, GroupProgress{state, failure})

def check_frontier_sized(ready: List<&2, Scheduler.Scheduled>, known: CheckCatalog, previous: Map<&2, Cached<G.CheckedGroup>>, +progress: GroupProgress, small: Bool) -> GroupProgress:
  match progress small:
    case GroupProgress{+state, +failure} True{}:
      +prepared = prepare_groups(ready, known, previous, state, failure)
      publish_prepared(prepared, Scheduler.check_batch_planned(group_tasks(prepared, Nil{})), GroupProgress{state, failure})
    case GroupProgress{+state, +failure} False{}:
      publish_prepared(check_groups(ready, known, previous, state, failure), Nil{}, GroupProgress{state, failure})

def frontier_cost(ready: List<&2, Scheduler.Scheduled>, +known: CheckCatalog, cost: Nat) -> Nat:
  match ready:
    case Nil{}:
      cost
    case Scheduler.Scheduled{position, level, job} <> tail:
      frontier_cost(tail, known, Nat.add(cost, Scheduler.group_cost(check_catalog(known), job)))

# Tiny jobs benefit from collecting misses into their own balanced batch.
# Fuse stages only when the average job amortizes the worker-local checking path.
def staged_frontier(+ready: List<&2, Scheduler.Scheduled>, known: CheckCatalog, small: Bool) -> Bool:
  match small:
    case True{}:
      True{}
    case False{}:
      Nat.is_lt(frontier_cost(ready, known, 0n), Nat.mul(List.length(&2, Scheduler.Scheduled, ready), 256n))

def check_frontier(ready: List<&2, Scheduler.Scheduled>, +known: CheckCatalog, previous: Map<&2, Cached<G.CheckedGroup>>, +progress: GroupProgress) -> GroupProgress:
  match ready:
    case Nil{}:
      progress
    case Scheduler.Scheduled{+position, level, job} <> Nil{}:
      GroupProgress{state, failure} = progress
      check_single_group(Scheduler.Scheduled{position, level, job}, known, previous, progress, Scheduler.precedes_failure(position, failure))
    case +remaining:
      check_frontier_sized(remaining, known, previous, progress, staged_frontier(remaining, known, Nat.is_le(List.length(&2, Scheduler.Scheduled, remaining), 4n)))

def finish_groups(progress: GroupProgress) -> Result<&2, &2, M.Diagnostic, CheckedGroups>:
  match progress:
    case GroupProgress{checked, None{}}:
      Done{checked}
    case GroupProgress{checked, Some{Scheduler.Failure{position, diagnostic}}}:
      Fail{diagnostic}

# Only closed interfaces from completed frontiers enter the next one. A failed
# later ready job cannot hide an earlier job waiting on an earlier frontier.
def check_frontiers(fuel: Nat, frontier: Scheduler.Frontier, +known: CheckCatalog, +previous: Map<&2, Cached<G.CheckedGroup>>, progress: GroupProgress) -> Result<&2, &2, M.Diagnostic, CheckedGroups>:
  match fuel frontier:
    case _ Scheduler.Frontier{Nil{}, Nil{}}:
      finish_groups(progress)
    case 0n _:
      Fail{M.Diagnostic{"internal_error", "native_session", "dependency frontier count exceeds its declaration group count"}}
    case 1n+rest Scheduler.Frontier{ready, pending}:
      check_frontiers(rest, Scheduler.next_frontier(pending), known, previous, check_frontier(ready, known, previous, progress))

def chain_allowed(jobs: List<&2, Chains.Job>, progress: GroupProgress) -> Bool:
  match jobs:
    case Nil{}:
      False{}
    case Chains.Job{position, job} <> tail:
      GroupProgress{state, failure} = progress
      Scheduler.precedes_failure(position, failure)

def check_chain(jobs: List<&2, Chains.Job>, +known: CheckCatalog, +previous: Map<&2, Cached<G.CheckedGroup>>, progress: GroupProgress, allowed: Bool) -> GroupProgress:
  match jobs allowed:
    case Nil{} _:
      progress
    case _ False{}:
      progress
    case Chains.Job{position, job} <> +tail True{}:
      +next = check_frontier([Scheduler.Scheduled{position, 0n, job}], known, previous, progress)
      check_chain(tail, known, previous, next, chain_allowed(tail, next))

type ChainContext is Data:
  ChainContext{
    known: CheckCatalog,
    previous: Map<&2, Cached<G.CheckedGroup>>,
    interfaces: Map<&2, G.Interface>,
    closures: Map<&2, Set()>,
    failure: Maybe<&2, Scheduler.Failure>
  }

def run_chain(chain: Chains.Chain, context: ChainContext) -> GroupProgress:
  Chains.Chain{position, level, +jobs} = chain
  ChainContext{known, previous, interfaces, closures, failure} = context
  # Only dependency lookups inherit state; each lane owns its cache delta and
  # counters. No candidate cache is published until the whole request succeeds.
  local = {CheckedGroups{Map.new(&2, Cached<G.CheckedGroup>), interfaces, Map.new(&2, M.CheckedFunction), Map.new(&2, M.CheckedConstant), closures, Map.new(&2, List<&2, U32>), Counts{0n, 0n}} : CheckedGroups}
  +initial = {GroupProgress{local, failure} : GroupProgress}
  check_chain(jobs, known, previous, initial, chain_allowed(jobs, initial))

def merge_progress(chains: List<&2, GroupProgress>, progress: GroupProgress) -> GroupProgress:
  match chains:
    case Nil{}:
      progress
    case GroupProgress{CheckedGroups{cg, ci, cf, cc, cl, ck, Counts{fresh, reused}}, failure} <> tail:
      GroupProgress{CheckedGroups{groups, interfaces, functions, constants, closures, base_keys, Counts{prior_fresh, prior_reused}}, prior_failure} = progress
      combined = {CheckedGroups{Map.union(&2, Cached<G.CheckedGroup>, groups, cg), Map.union(&2, G.Interface, interfaces, ci), Map.union(&2, M.CheckedFunction, functions, cf), Map.union(&2, M.CheckedConstant, constants, cc), Map.union(&2, Set(), closures, cl), Map.union(&2, List<&2, U32>, base_keys, ck), Counts{Nat.add(prior_fresh, fresh), Nat.add(prior_reused, reused)}} : CheckedGroups}
      merge_progress(tail, GroupProgress{combined, Scheduler.merge_failure(prior_failure, failure)})

def check_parallel_chains(ready: List<&2, Chains.Chain>, +known: CheckCatalog, previous: Map<&2, Cached<G.CheckedGroup>>, +progress: GroupProgress) -> GroupProgress:
  GroupProgress{CheckedGroups{groups, interfaces, functions, constants, closures, base_keys, counts}, failure} = progress
  outcomes = B.execute(~Chains.Chain, ~ChainContext, ~GroupProgress, ~run_chain, Scheduler.chain_batch(ready, check_catalog(known)), ChainContext{known, previous, interfaces, closures, failure})
  merge_progress(outcomes, progress)

def check_chain_frontier_planned(ready: List<&2, Chains.Chain>, known: CheckCatalog, previous: Map<&2, Cached<G.CheckedGroup>>, +progress: GroupProgress, singletons: Maybe<&2, List<&2, Scheduler.Scheduled>>) -> GroupProgress:
  match ready singletons:
    case Chains.Chain{position, level, +jobs} <> Nil{} _:
      check_chain(jobs, known, previous, progress, chain_allowed(jobs, progress))
    case _ Some{scheduled}:
      check_frontier(scheduled, known, previous, progress)
    case _ None{}:
      check_parallel_chains(ready, known, previous, progress)

def check_chain_frontier(+ready: List<&2, Chains.Chain>, known: CheckCatalog, previous: Map<&2, Cached<G.CheckedGroup>>, progress: GroupProgress) -> GroupProgress:
  check_chain_frontier_planned(ready, known, previous, progress, Scheduler.singleton_jobs(ready))

def check_chain_frontiers(fuel: Nat, frontier: Chains.Frontier, +known: CheckCatalog, +previous: Map<&2, Cached<G.CheckedGroup>>, progress: GroupProgress) -> Result<&2, &2, M.Diagnostic, GroupProgress>:
  match fuel frontier:
    case _ Chains.Frontier{Nil{}, Nil{}}:
      Done{progress}
    case 0n _:
      Fail{M.Diagnostic{"internal_error", "native_session", "dependency chain frontiers exceed their declaration group count"}}
    case 1n+rest Chains.Frontier{ready, pending}:
      check_chain_frontiers(rest, Chains.next_frontier(pending), known, previous, check_chain_frontier(ready, known, previous, progress))

def run_region(region: Regions.Region, context: ChainContext) -> Result<&2, &2, M.Diagnostic, GroupProgress>:
  Regions.Region{+chains} = region
  ChainContext{known, previous, interfaces, closures, failure} = context
  local = {CheckedGroups{Map.new(&2, Cached<G.CheckedGroup>), interfaces, Map.new(&2, M.CheckedFunction), Map.new(&2, M.CheckedConstant), closures, Map.new(&2, List<&2, U32>), Counts{0n, 0n}} : CheckedGroups}
  check_chain_frontiers(List.length(&2, Chains.Chain, chains), Chains.next_frontier(chains), known, previous, GroupProgress{local, failure})

def merge_regions(outcomes: List<&2, Result<&2, &2, M.Diagnostic, GroupProgress>>, progress: GroupProgress) -> Result<&2, &2, M.Diagnostic, GroupProgress>:
  match outcomes:
    case Nil{}:
      Done{progress}
    case Fail{diagnostic} <> tail:
      Fail{diagnostic}
    case Done{region} <> tail:
      merge_regions(tail, merge_progress([region], progress))

def check_regions(regions: List<&2, Regions.Region>, +known: CheckCatalog, previous: Map<&2, Cached<G.CheckedGroup>>, +progress: GroupProgress) -> Result<&2, &2, M.Diagnostic, GroupProgress>:
  match regions:
    case Regions.Region{+chains} <> Nil{}:
      check_chain_frontiers(List.length(&2, Chains.Chain, chains), Chains.next_frontier(chains), known, previous, progress)
    case _:
      GroupProgress{CheckedGroups{groups, interfaces, functions, constants, closures, base_keys, counts}, failure} = progress
      outcomes = B.execute(~Regions.Region, ~ChainContext, ~Result<&2, &2, M.Diagnostic, GroupProgress>, ~run_region, Scheduler.region_batch(regions, check_catalog(known)), ChainContext{known, previous, interfaces, closures, failure})
      merge_regions(outcomes, progress)

def check_plan(plan: InferencePlan, +known: CheckCatalog, +previous: Map<&2, Cached<G.CheckedGroup>>, state: CheckedGroups) -> Result<&2, &2, M.Diagnostic, CheckedGroups>:
  match plan:
    case IndependentPlan{group_count, scheduled}:
      check_frontiers(group_count, Scheduler.next_frontier(scheduled), known, previous, GroupProgress{state, None{}})
    case RegionPlan{prefix, regions}:
      do Result<&2, &2, M.Diagnostic, CheckedGroups>:
        initial : GroupProgress = check_chain_frontier(prefix, known, previous, GroupProgress{state, None{}})
        progress : GroupProgress <- check_regions(regions, known, previous, initial)
        finish_groups(progress)

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
        evaluate_constants(tail, constant_remaining(value), context, closures, base_keys, previous, Index.set(Cached<Const.Constants>, next, name, Cached{keys, value}), List.append(&2, Const.Binding<Const.Value>, List.reverse(&2, Const.Binding<Const.Value>, constant_bindings(value)), reversed), count(counts, selected_reused(Const.Constants, chosen)))

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

type KeyedEntry is Data:
  KeyedEntry{job: W.CodegenJob, encoded: Result<&2, &2, M.Diagnostic, List<&2, U32>>}

def entry_key_task(job: W.CodegenJob, context: Unit) -> KeyedEntry:
  +entry = job
  KeyedEntry{entry, K.entry(entry)}

def entry_key_tasks(jobs: List<&2, W.CodegenJob>, reversed: List<&2, B.Weighted<W.CodegenJob>>) -> List<&2, B.Weighted<W.CodegenJob>>:
  match jobs:
    case Nil{}:
      List.reverse(&2, B.Weighted<W.CodegenJob>, reversed)
    case +job <> tail:
      entry_key_tasks(tail, B.Weighted{job, W.codegen_weight(job)} <> reversed)

def keyed_entries(jobs: List<&2, W.CodegenJob>) -> List<&2, KeyedEntry>:
  B.execute(~W.CodegenJob, ~Unit, ~KeyedEntry, ~entry_key_task, B.plan(W.CodegenJob, entry_key_tasks(jobs, Nil{}), 512n), Unit{})

def plan_entries(jobs: List<&2, KeyedEntry>, +previous: Map<&2, Cached<W.EntryCode>>, plan: EntryPlan) -> EntryPlan:
  match jobs plan:
    case Nil{} EntryPlan{selections, missing, failure}:
      EntryPlan{List.reverse(&2, EntrySelection, selections), List.reverse(&2, W.CodegenJob, missing), failure}
    case _ EntryPlan{selections, missing, Some{error}}:
      EntryPlan{List.reverse(&2, EntrySelection, selections), List.reverse(&2, W.CodegenJob, missing), Some{error}}
    case KeyedEntry{job, encoded} <> tail EntryPlan{selections, missing, None{}}:
      plan_entries(tail, previous, plan_entry_key(encoded, job, previous, EntryPlan{selections, missing, None{}}))

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
      publish_entries(tail, compiled, failure, Index.set(Cached<W.EntryCode>, next, name, Cached{[key], value}), value <> reversed, count(counts, True{}))
    case FreshEntry{+name, key} <> tail W.EntryCode{+found, code} <> rest:
      do Result<&2, &2, M.Diagnostic, CompiledEntries>:
        valid : Unit <- W.matching_entry(M.name_equal(name, found), name)
        +value : W.EntryCode = W.EntryCode{found, code}
        publish_entries(tail, rest, failure, Index.set(Cached<W.EntryCode>, next, name, Cached{[key], value}), value <> reversed, count(counts, False{}))
    case _ _:
      Fail{M.Diagnostic{"internal_error", "codegen", "incremental codegen results do not match the miss plan"}}

# Key errors remain behind all earlier misses, preserving the old serial
# diagnostic order. Cache hits never enter the compiler's parallel work tree.
def compile_entry_plan(plan: EntryPlan, next: Map<&2, Cached<W.EntryCode>>, reversed: List<&2, W.EntryCode>, counts: Counts) -> Result<&2, &2, M.Diagnostic, CompiledEntries>:
  EntryPlan{selections, missing, failure} = plan
  do Result<&2, &2, M.Diagnostic, CompiledEntries>:
    compiled : List<&2, W.EntryCode> <- W.compile_entries(missing)
    publish_entries(selections, compiled, failure, next, reversed, counts)

type PreparedEntry is Data:
  PreparedEntry{name: String, key: List<&2, U32>, selected: Selected<W.EntryCode>}

def select_compiled_entry(found: Maybe<&2, W.EntryCode>, job: W.CodegenJob) -> Result<&2, &2, M.Diagnostic, Selected<W.EntryCode>>:
  match found:
    case Some{value}:
      Done{Selected{value, True{}}}
    case None{}:
      do Result<&2, &2, M.Diagnostic, Selected<W.EntryCode>>:
        value : W.EntryCode <- W.compile_entry(job)
        return Selected{value, False{}}

def compile_keyed_entry(entry: KeyedEntry, previous: Map<&2, Cached<W.EntryCode>>) -> Result<&2, &2, M.Diagnostic, PreparedEntry>:
  KeyedEntry{+job, encoded} = entry
  W.CodegenJob{+name, parameter, body, captures} = job
  do Result<&2, &2, M.Diagnostic, PreparedEntry>:
    +key : List<&2, U32> <- encoded
    selected : Selected<W.EntryCode> <- select_compiled_entry(cached(W.EntryCode, Index.find(Cached<W.EntryCode>, previous, name), [key]), job)
    return PreparedEntry{name, key, selected}

def compile_entry_task(job: W.CodegenJob, previous: Map<&2, Cached<W.EntryCode>>) -> Result<&2, &2, M.Diagnostic, PreparedEntry>:
  +entry = job
  compile_keyed_entry(KeyedEntry{entry, K.entry(entry)}, previous)

def publish_compiled_entries(entries: List<&2, Result<&2, &2, M.Diagnostic, PreparedEntry>>, next: Map<&2, Cached<W.EntryCode>>, reversed: List<&2, W.EntryCode>, counts: Counts) -> Result<&2, &2, M.Diagnostic, CompiledEntries>:
  match entries:
    case Nil{}:
      finish_entries(None{}, next, reversed, counts)
    case Fail{error} <> tail:
      Fail{error}
    case Done{PreparedEntry{+name, key, Selected{+value, reused}}} <> tail:
      W.EntryCode{found, code} = value
      do Result<&2, &2, M.Diagnostic, CompiledEntries>:
        valid : Unit <- W.matching_entry(M.name_equal(name, found), name)
        publish_compiled_entries(tail, Index.set(Cached<W.EntryCode>, next, name, Cached{[key], value}), value <> reversed, count(counts, reused))

# Keying and cache-miss compilation share a worker. Ordered publication keeps
# an earlier compilation error ahead of a later key error, despite speculation.
def compile_weighted_entries(tasks: List<&2, B.Weighted<W.CodegenJob>>, previous: Map<&2, Cached<W.EntryCode>>, next: Map<&2, Cached<W.EntryCode>>, reversed: List<&2, W.EntryCode>, counts: Counts, staged: Bool) -> Result<&2, &2, M.Diagnostic, CompiledEntries>:
  match staged:
    case True{}:
      keyed = B.execute(~W.CodegenJob, ~Unit, ~KeyedEntry, ~entry_key_task, B.plan(W.CodegenJob, tasks, 512n), Unit{})
      compile_entry_plan(plan_entries(keyed, previous, EntryPlan{Nil{}, Nil{}, None{}}), next, reversed, counts)
    case False{}:
      compiled = B.execute(~W.CodegenJob, ~Map<&2, Cached<W.EntryCode>>, ~Result<&2, &2, M.Diagnostic, PreparedEntry>, ~compile_entry_task, B.plan(W.CodegenJob, tasks, 512n), previous)
      publish_compiled_entries(compiled, next, reversed, counts)

def compile_jobs(jobs: List<&2, W.CodegenJob>, previous: Map<&2, Cached<W.EntryCode>>, next: Map<&2, Cached<W.EntryCode>>, reversed: List<&2, W.EntryCode>, counts: Counts) -> Result<&2, &2, M.Diagnostic, CompiledEntries>:
  +tasks = entry_key_tasks(jobs, Nil{})
  staged = Nat.is_lt(B.total_cost(W.CodegenJob, tasks, 0n), Nat.mul(List.length(&2, B.Weighted<W.CodegenJob>, tasks), 256n))
  compile_weighted_entries(tasks, previous, next, reversed, counts, staged)

def stats(declarations: Counts, groups: Counts, constants: Counts, entries: Counts) -> Stats:
  Counts{dl, dr} = declarations
  Counts{gc, gr} = groups
  Counts{ce, cr} = constants
  Counts{ec, er} = entries
  Stats{dl, dr, gc, gr, ce, cr, ec, er}

def finish_compiled(state: State, analysis: Main.Analysis, +prepared: W.Prepared, compiled: CompiledEntries, declarations: Counts, groups: Counts, constants: Counts) -> Result<&2, &2, M.Diagnostic, Completion>:
  State{prelude, scope_key, lowered, planning, checked, evaluated, previous, specialization, catalog_version} = state
  CompiledEntries{entries, values, entry_counts} = compiled
  do Result<&2, &2, M.Diagnostic, Completion>:
    bytes : W.BytePlan <- W.link_plan(prepared, values)
    return Completion{State{prelude, scope_key, lowered, planning, checked, evaluated, entries, specialization, catalog_version}, Compiled{Main.PlannedArtifact{analysis, bytes}}, stats(declarations, groups, constants, entry_counts)}

def state_entries(state: State) -> Map<&2, Cached<W.EntryCode>>:
  State{prelude, scope_key, lowered, planning, checked, evaluated, entries, specialization, catalog_version} = state
  entries

def finish(mode: Mode, +state: State, +analysis: Main.Analysis, declarations: Counts, groups: Counts, constants: Counts) -> Result<&2, &2, M.Diagnostic, Completion>:
  match mode:
    case AnalyzeMode{}:
      Done{Completion{state, Analyzed{analysis}, stats(declarations, groups, constants, Counts{0n, 0n})}}
    case CompileMode{}:
      do Result<&2, &2, M.Diagnostic, Completion>:
        exports : Unit <- Entries.require_exports(Main.analysis_checked(analysis))
        +prepared : W.Prepared <- W.prepare(Main.analysis_checked(analysis), Main.analysis_constants(analysis))
        compiled : CompiledEntries <- compile_jobs(W.prepared_jobs(prepared), state_entries(state), Map.new(&2, Cached<W.EntryCode>), Nil{}, Counts{0n, 0n})
        finish_compiled(state, analysis, prepared, compiled, declarations, groups, constants)

def update_evaluated(state: State, mode: Mode, checked: M.CheckedModule, evaluated: Evaluated, declaration_counts: Counts, group_counts: Counts) -> Result<&2, &2, M.Diagnostic, Completion>:
  State{prelude, scope_key, declarations, planning, groups, previous_constants, entries, specialization, catalog_version} = state
  Evaluated{constants, Const.Constants{bindings, remaining}, constant_counts} = evaluated
  next = {State{prelude, scope_key, declarations, planning, groups, constants, entries, specialization, catalog_version} : State}
  finish(mode, next, Main.Analysis{checked, bindings, remaining}, declaration_counts, group_counts, constant_counts)

def evaluate_demand_graph(+constants: List<&2, M.CheckedConstant>, steps: Nat, context: Const.Context) -> Result<&2, &2, M.Diagnostic, Evaluated>:
  +count = List.length(&2, M.CheckedConstant, constants)
  do Result<&2, &2, M.Diagnostic, Evaluated>:
    values : Const.Constants <- Const.evaluate_constants_selected(True{}, constants, steps, context)
    return Evaluated{Map.new(&2, Cached<Const.Constants>), values, Counts{count, 0n}}

def evaluate_checked_constants(demands: Bool, constants: List<&2, M.CheckedConstant>, steps: Nat, context: Const.Context, closures: Map<&2, Set()>, base_keys: Map<&2, List<&2, U32>>, previous: Map<&2, Cached<Const.Constants>>) -> Result<&2, &2, M.Diagnostic, Evaluated>:
  match demands:
    case True{}:
      evaluate_demand_graph(constants, steps, context)
    case False{}:
      evaluate_constants(constants, steps, context, closures, base_keys, previous, Map.new(&2, Cached<Const.Constants>), Nil{}, Counts{0n, 0n})

def update_checked(state: State, mode: Mode, +module: M.Module, +completed: CheckedGroups, declaration_counts: Counts, +steps: Nat, hosts: List<&2, Entries.Entry>) -> Result<&2, &2, M.Diagnostic, Completion>:
  State{prelude, scope_key, declarations, planning, previous_groups, previous_constants, entries, specialization, catalog_version} = state
  CheckedGroups{groups, interfaces, functions, constants, closures, base_keys, group_counts} = completed
  do Result<&2, &2, M.Diagnostic, Completion>:
    +checked : M.CheckedModule <- assemble(module, completed)
    valid : Unit <- Entries.verify(hosts, checked)
    +context : Const.Context = Main.const_context(module, checked)
    evaluated : Evaluated <- evaluate_checked_constants(Const.has_demands(context), Main.checked_constants(checked), steps, context, closures, base_keys, previous_constants)
    update_evaluated(State{prelude, scope_key, declarations, planning, groups, Map.new(&2, Cached<Const.Constants>), entries, specialization, catalog_version}, mode, checked, evaluated, declaration_counts, group_counts)

def lowered_fragments(values: List<&2, Lowered>) -> List<&2, M.Module>:
  match values:
    case Nil{}:
      Nil{}
    case head <> tail:
      lowered_fragment(head) <> lowered_fragments(tail)

def specialization_graph(specialized: Bool, module: M.Module, scans: List<&2, Plan.Scanned>) -> Result<&2, &2, M.Diagnostic, List<&2, D.Node>>:
  match specialized:
    case True{}:
      Check.module_graph(module)
    case False{}:
      Plan.graph(module, scans)

def function_count(module: M.Module) -> Nat:
  M.Module{constants, functions, types, operations} = module
  List.length(&2, M.Function, functions)

def constant_count(module: M.Module) -> Nat:
  M.Module{constants, functions, types, operations} = module
  List.length(&2, M.Constant, constants)

# Specialization or dead-code elimination changed the declarations, so the
# lowered scans no longer describe the module.
def reshaped(specialized: Bool, +raw_module: M.Module, +module: M.Module) -> Bool:
  Bool.or(specialized, Bool.or(Bool.not(Nat.is_eq(function_count(raw_module), function_count(module))), Bool.not(Nat.is_eq(constant_count(raw_module), constant_count(module)))))

def groups_if_same_catalog(same: Bool, previous: Map<&2, Cached<G.CheckedGroup>>) -> Map<&2, Cached<G.CheckedGroup>>:
  match same:
    case True{}:
      previous
    case False{}:
      Map.new(&2, Cached<G.CheckedGroup>)

def constants_if_same_catalog(same: Bool, previous: Map<&2, Cached<Const.Constants>>) -> Map<&2, Cached<Const.Constants>>:
  match same:
    case True{}:
      previous
    case False{}:
      Map.new(&2, Cached<Const.Constants>)

def update_lowered_module(state: State, mode: Mode, entry: String, +prelude_module: M.Module, +raw_module: M.Module, scope_words: List<&2, U32>, lowered: Lowering, steps: Nat) -> Result<&2, &2, M.Diagnostic, Completion>:
  State{+prelude, scope_key, declarations, planning, +previous_groups, constants, entries, specialization, catalog_version} = state
  Lowering{+values, +scans, declaration_counts} = lowered
  +specialized = Bool.or(Mono.required(raw_module), Families.required(raw_module))
  do Result<&2, &2, M.Diagnostic, Completion>:
    +family_module : M.Module <- Families.prepare(raw_module)
    +specialization_result : Mono.Prepared <- Resolution.prepare_cached_evidenced(~K.module, family_module, entry, M.module_operations(raw_module), specialization)
    +module : M.Module = Mono.prepared_module(specialization_result)
    +expanded : Bool = reshaped(specialized, raw_module, module)
    graph : List<&2, D.Node> <- specialization_graph(expanded, module, Plan.scan(prelude_module) <> scans)
    +prepared : PreparedPlanning <- prepare_planning(module, prelude_module, values, graph, Bool.and(Bool.not(expanded), cache_nominal_scans(scans, 0n, 0n)))
    +plan : G.Planning = planning_value(prepared)
    +plan_key : List<&2, U32> <- K.planning(plan)
    +scheduled : InferencePlan <- select_plan(cached(InferencePlan, planning, [plan_key]), plan)
    +catalog : CV.Prepared <- CV.prepare(module_types(module), M.module_operations(module), catalog_version)
    +revision : CV.Revision = CV.prepared_revision(catalog)
    +same_catalog : Bool = CV.prepared_same_operations(catalog)
    +previous_valid : Map<&2, Cached<G.CheckedGroup>> = groups_if_same_catalog(same_catalog, previous_groups)
    completed : CheckedGroups <- check_plan(scheduled, CheckCatalog{Scheduler.with_core(Scheduler.catalog_costs(module, Plan.collect_costs(scans, Map.new(&2, Nat))), module, Mono.prepared_certificates(specialization_result)), revision}, previous_valid, empty_checked())
    update_checked(State{prelude, Some{scope_words}, planning_declarations(prepared), Some{Cached{[plan_key], scheduled}}, Map.new(&2, Cached<G.CheckedGroup>), constants_if_same_catalog(same_catalog, constants), entries, Some{Mono.prepared_cache(specialization_result)}, Some{revision}}, mode, module, completed, declaration_counts, steps, Entries.entries(raw_module))

def update_lowered(state: State, mode: Mode, entry: String, +prelude_module: M.Module, scope_words: List<&2, U32>, lowered: Lowering, steps: Nat) -> Result<&2, &2, M.Diagnostic, Completion>:
  Lowering{+values, scans, counts} = lowered
  +raw_module = combine_fragments(prelude_module <> lowered_fragments(values))
  update_lowered_module(state, mode, entry, prelude_module, raw_module, scope_words, Lowering{values, scans, counts}, steps)

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

def update_source(+state: State, mode: Mode, source: L.SourcePlan, +fuel: Nat, steps: Nat, retained: Set()) -> Result<&2, &2, M.Diagnostic, Completion>:
  State{prelude, scope_key, declarations, planning, groups, constants, entries, specialization, catalog_version} = state
  L.SourcePlan{prelude_module, +scope, +nodes} = source
  do Result<&2, &2, M.Diagnostic, Completion>:
    unique : Unit <- unique_declaration_ids(nodes, Set.new())
    +scope_words : List<&2, U32> <- K.scope(scope)
    lowered : Lowering <- lower_plan(plan_lowering(nodes, fuel, reusable_scope(scope_key, scope_words, declarations), retained, LoweringPlan{Nil{}, Nil{}}), scope, fuel)
    update_lowered(state, mode, "main", prelude_module, scope_words, lowered, steps)

def update_single(+state: State, mode: Mode, root: C.Cst, fuel: Nat, steps: Nat) -> Result<&2, &2, M.Diagnostic, Completion>:
  State{prelude, scope_key, declarations, planning, groups, constants, entries, specialization, catalog_version} = state
  do Result<&2, &2, M.Diagnostic, Completion>:
    source : L.SourcePlan <- L.prepare_source(root, prelude)
    update_source(state, mode, source, fuel, steps, Set.new())

type ResolvedDeclarations is Data:
  ResolvedDeclarations{nodes: List<&2, C.Cst>, retained: Set()}

def require_retained(found: Maybe<&2, Lowered>, identity: Nat) -> Result<&2, &2, M.Diagnostic, C.Cst>:
  match found:
    case Some{Lowered{node, fuel, fragment, scanned, nominals}}:
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
  State{prelude, scope_key, declarations, planning, groups, constants, entries, specialization, catalog_version} = state
  ResolvedDeclarations{nodes, retained} = resolved
  do Result<&2, &2, M.Diagnostic, Completion>:
    source : L.SourcePlan <- L.prepare_source(C.Cst{"module", "", "", 0n, nodes}, prelude)
    update_source(state, mode, source, fuel, steps, retained)

# References name only declarations held by the last successful State. The
# complete reconstructed source still passes scope, graph, type/effect, budget,
# and backend checks; a patch is transport compression, not semantic authority.
def update_patch(+state: State, mode: Mode, declarations: List<&2, Declaration>, fuel: Nat, steps: Nat) -> Result<&2, &2, M.Diagnostic, Completion>:
  State{prelude, scope_key, previous, planning, groups, constants, entries, specialization, catalog_version} = state
  do Result<&2, &2, M.Diagnostic, Completion>:
    resolved : ResolvedDeclarations <- resolve_declarations(declarations, previous, Nil{}, Set.new())
    update_resolved(state, mode, resolved, fuel, steps)

# Project patches retain declaration trees only from the acknowledged revision.
# Import headers always travel with the request and rebuild their name scopes.
def project_marker_valid(node: C.Cst) -> Bool:
  C.Cst{kind, field, text, offset, children} = node
  Bool.and(M.name_equal(field, "declarations"), Bool.and(M.name_equal(text, ""), Bool.not(C.present(children))))

def project_retained(valid: Bool, node: C.Cst, previous: Map<&2, Lowered>) -> Result<&2, &2, M.Diagnostic, C.Cst>:
  match valid:
    case False{}:
      Fail{C.diagnostic(node, "native_session", "retained declaration marker is malformed")}
    case True{}:
      +identity = C.offset_of(node)
      require_retained(Index.find(Lowered, previous, Nat.show(identity)), identity)

def project_node(retained: Bool, +node: C.Cst, previous: Map<&2, Lowered>) -> Result<&2, &2, M.Diagnostic, C.Cst>:
  match retained:
    case False{}:
      Done{node}
    case True{}:
      project_retained(project_marker_valid(node), node, previous)

def project_children(nodes: List<&2, C.Cst>, +previous: Map<&2, Lowered>) -> Result<&2, &2, M.Diagnostic, List<&2, C.Cst>>:
  match nodes:
    case Nil{}:
      Done{Nil{}}
    case +head <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, C.Cst>>:
        first : C.Cst <- project_node(M.name_equal(C.kind_of(head), "retained_declaration"), head, previous)
        rest : List<&2, C.Cst> <- project_children(tail, previous)
        return first <> rest

def project_body(body: C.Cst, previous: Map<&2, Lowered>) -> Result<&2, &2, M.Diagnostic, C.Cst>:
  C.Cst{kind, field, text, offset, declarations} = body
  do Result<&2, &2, M.Diagnostic, C.Cst>:
    resolved : List<&2, C.Cst> <- project_children(declarations, previous)
    return C.Cst{kind, field, text, offset, resolved}

def project_modules(nodes: List<&2, C.Cst>, +previous: Map<&2, Lowered>) -> Result<&2, &2, M.Diagnostic, List<&2, C.Cst>>:
  match nodes:
    case Nil{}:
      Done{Nil{}}
    case C.Cst{kind, field, text, offset, children} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, C.Cst>>:
        body : C.Cst <- C.one(C.fields(children, "body"))
        resolved : C.Cst <- project_body(body, previous)
        rest : List<&2, C.Cst> <- project_modules(tail, previous)
        return C.Cst{kind, field, text, offset, [resolved]} <> rest

def project_task_key(prepared: Result<&2, &2, M.Diagnostic, Modules.ModuleTask>) -> Result<&2, &2, M.Diagnostic, List<&2, U32>>:
  match prepared:
    case Fail{error}:
      # A later scope error cannot mask an earlier module's body error.
      Done{[0]}
    case Done{Modules.ModuleTask{declarations, prefix, name, entry, scope}}:
      do Result<&2, &2, M.Diagnostic, List<&2, U32>>:
        header : List<&2, U32> <- K.encode([K.Field{R.Text{prefix}}, K.Field{R.Text{name}}, K.flag(entry)])
        +words : List<&2, U32> <- K.scope(scope)
        return List.append(&2, U32, header, U32.from_nat(List.length(&2, U32, words)) <> words)

def project_scope_key(tasks: List<&2, B.Weighted<Result<&2, &2, M.Diagnostic, Modules.ModuleTask>>>) -> Result<&2, &2, M.Diagnostic, List<&2, U32>>:
  match tasks:
    case Nil{}:
      Done{Nil{}}
    case B.Weighted{task, cost} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, U32>>:
        +first : List<&2, U32> <- project_task_key(task)
        rest : List<&2, U32> <- project_scope_key(tail)
        return U32.from_nat(List.length(&2, U32, first)) <> List.append(&2, U32, first, rest)

type ProjectContext is Data:
  ProjectContext{previous: Map<&2, Lowered>, fuel: Nat}

def lower_project_node(found: Maybe<&2, Lowered>, +node: C.Cst, task: Modules.ModuleTask, +fuel: Nat) -> Result<&2, &2, M.Diagnostic, Lowered>:
  match found:
    case Some{value}:
      Done{value}
    case None{}:
      Modules.ModuleTask{declarations, prefix, name, entry, scope} = task
      do Result<&2, &2, M.Diagnostic, Lowered>:
        +value : C.Cst <- C.one(C.field_values(node, "value"))
        +fragment : M.Module <- L.declaration(L.classify(C.kind_of(value)), value, C.field_values(node, "attributes"), prefix, name, entry, M.Module{Nil{}, Nil{}, Nil{}, Nil{}}, fuel, scope)
        return Lowered{node, fuel, fragment, Plan.scan(fragment), None{}}

def lower_project_nodes(nodes: List<&2, C.Cst>, +task: Modules.ModuleTask, +context: ProjectContext, lowered: Lowering) -> Result<&2, &2, M.Diagnostic, Lowering>:
  match nodes:
    case Nil{}:
      Done{lowered}
    case +node <> tail:
      ProjectContext{previous, +fuel} = context
      Lowering{values, scans, counts} = lowered
      +found = lower_hit(Index.find(Lowered, previous, Nat.show(C.offset_of(node))), node, fuel, False{})
      do Result<&2, &2, M.Diagnostic, Lowering>:
        +value : Lowered <- lower_project_node(found, node, task, fuel)
        lower_project_nodes(tail, task, context, Lowering{value <> values, lowered_scan(value) <> scans, count(counts, Maybe.is_some(&2, Lowered, found))})

type ProjectLowering is Data:
  ProjectLowering{lowered: Lowering, module: M.Module}

def project_module(lowered: Lowering, requests: List<&2, M.Operation>) -> M.Module:
  Lowering{values, scans, counts} = lowered
  L.add_operations(combine_fragments(lowered_fragments(values)), requests)

def lower_project_ready(+task: Modules.ModuleTask, +context: ProjectContext) -> Result<&2, &2, M.Diagnostic, ProjectLowering>:
  Modules.ModuleTask{+declarations, prefix, name, entry, scope} = task
  ProjectContext{previous, fuel} = context
  do Result<&2, &2, M.Diagnostic, ProjectLowering>:
    valid : Unit <- L.validate_declaration_nodes(declarations)
    +lowered : Lowering <- lower_project_nodes(List.reverse(&2, C.Cst, declarations), task, context, Lowering{Nil{}, Nil{}, Counts{0n, 0n}})
    requests : List<&2, M.Operation> <- L.declarations_row_requests(declarations, fuel, scope, Nil{})
    return ProjectLowering{lowered, project_module(lowered, requests)}

def lower_project_task(prepared: Result<&2, &2, M.Diagnostic, Modules.ModuleTask>, context: ProjectContext) -> Result<&2, &2, M.Diagnostic, ProjectLowering>:
  do Result<&2, &2, M.Diagnostic, ProjectLowering>:
    task : Modules.ModuleTask <- prepared
    lower_project_ready(task, context)

def combine_project_lowering(first: Lowering, rest: Lowering) -> Lowering:
  Lowering{a, sa, Counts{fa, ra}} = first
  Lowering{b, sb, Counts{fb, rb}} = rest
  Lowering{List.append(&2, Lowered, a, b), List.append(&2, Plan.Scanned, sa, sb), Counts{Nat.add(fa, fb), Nat.add(ra, rb)}}

def combine_project_modules(first: ProjectLowering, rest: ProjectLowering) -> ProjectLowering:
  ProjectLowering{a, ma} = first
  ProjectLowering{b, mb} = rest
  ProjectLowering{combine_project_lowering(a, b), L.combine_modules(ma, mb)}

def collect_project_lowering(outcomes: List<&2, Result<&2, &2, M.Diagnostic, ProjectLowering>>) -> Result<&2, &2, M.Diagnostic, ProjectLowering>:
  match outcomes:
    case Nil{}:
      Done{ProjectLowering{Lowering{Nil{}, Nil{}, Counts{0n, 0n}}, M.Module{Nil{}, Nil{}, Nil{}, Nil{}}}}
    case head <> tail:
      do Result<&2, &2, M.Diagnostic, ProjectLowering>:
        first : ProjectLowering <- head
        rest : ProjectLowering <- collect_project_lowering(tail)
        return combine_project_modules(first, rest)

def project_nodes(values: List<&2, Lowered>) -> List<&2, C.Cst>:
  match values:
    case Nil{}:
      Nil{}
    case Lowered{node, fuel, fragment, scanned, nominals} <> tail:
      node <> project_nodes(tail)

def update_project_lowered(state: State, mode: Mode, entry: String, +prelude_module: M.Module, key: List<&2, U32>, project: ProjectLowering, steps: Nat) -> Result<&2, &2, M.Diagnostic, Completion>:
  ProjectLowering{Lowering{+values, scans, counts}, module} = project
  do Result<&2, &2, M.Diagnostic, Completion>:
    unique : Unit <- unique_declaration_ids(project_nodes(values), Set.new())
    update_lowered_module(state, mode, entry, prelude_module, L.combine_modules(prelude_module, module), key, Lowering{values, scans, counts}, steps)

def update_project(+state: State, mode: Mode, +root: C.Cst, +fuel: Nat, steps: Nat) -> Result<&2, &2, M.Diagnostic, Completion>:
  State{L.Prelude{prelude_module, +scope}, scope_key, +declarations, planning, groups, constants, entries, specialization, catalog_version} = state
  do Result<&2, &2, M.Diagnostic, Completion>:
    modules : List<&2, C.Cst> <- project_modules(C.field_values(root, "modules"), declarations)
    +tasks : List<&2, B.Weighted<Result<&2, &2, M.Diagnostic, Modules.ModuleTask>>> = Modules.prepare_modules(modules, C.text_of(root), scope, MTip{})
    +key : List<&2, U32> <- project_scope_key(tasks)
    outcomes : List<&2, Result<&2, &2, M.Diagnostic, ProjectLowering>> = B.execute(~Result<&2, &2, M.Diagnostic, Modules.ModuleTask>, ~ProjectContext, ~Result<&2, &2, M.Diagnostic, ProjectLowering>, ~lower_project_task, B.plan(Result<&2, &2, M.Diagnostic, Modules.ModuleTask>, tasks, 512n), ProjectContext{reusable_scope(scope_key, key, declarations), fuel})
    lowered : ProjectLowering <- collect_project_lowering(outcomes)
    update_project_lowered(state, mode, C.text_of(root), prelude_module, key, lowered, steps)

def update_kind(project: Bool, state: State, mode: Mode, root: C.Cst, fuel: Nat, steps: Nat) -> Result<&2, &2, M.Diagnostic, Completion>:
  match project:
    case False{}:
      update_single(state, mode, root, fuel, steps)
    case True{}:
      update_project(state, mode, root, fuel, steps)

def update(state: State, mode: Mode, +root: C.Cst, fuel: Nat, steps: Nat) -> Result<&2, &2, M.Diagnostic, Completion>:
  update_kind(M.name_equal(C.kind_of(root), "source_project"), state, mode, root, fuel, steps)
