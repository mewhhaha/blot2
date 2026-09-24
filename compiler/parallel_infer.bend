import Base
import ./model.bend as M
import ./infer.bend as I
import ./types.bend as T
import ./globals.bend as G
import ./dependency.bend as D
import ./inference_batch.bend as Batch
import ./nat_index.bend as NatIndex
import ./global_bindings.bend as Bindings

# These tasks are speculative. A failed guard replays the entire run through
# Globals in declaration order, including the first diagnostic.
type Job is Data:
  Job{declaration: G.Declaration, reads: List<&2, Nat>, first: Nat, limit: Nat}

type Classified is Data:
  Eligible{declaration: G.Declaration}
  Ineligible{declaration: G.Declaration}

type Run is Data:
  Run{declarations: List<&2, G.Declaration>, remaining: List<&2, Classified>}

type Context is Data:
  Context{environment: G.Environment, operations: List<&2, M.Operation>, types: List<&2, M.DataType>, functions: List<&2, String>, catalog: Maybe<&2, Map<&2, List<&2, Bindings.Entry>>>}

type Outcome is Data:
  Outcome{job: Job, result: Result<&2, &2, M.Diagnostic, G.Environment>}

def declaration_body(declaration: G.Declaration) -> M.Expr:
  match declaration:
    case G.FunctionDeclaration{M.Function{name, exported, parameter, p, r, body}}:
      body
    case G.ConstantDeclaration{M.Constant{name, exported, annotation, value}}:
      value

def any_pending(references: List<&2, String>, +pending: Set()) -> Bool:
  match references:
    case Nil{}:
      False{}
    case name <> tail:
      Bool.or(D.member(pending, name), any_pending(tail, pending))

def overlap(left: List<&2, Nat>, +right: List<&2, Nat>) -> Bool:
  match left:
    case Nil{}:
      False{}
    case head <> tail:
      Bool.or(T.contains(right, head), overlap(tail, right))

def quantified_unbound(variables: List<&2, Nat>, +substitutions: T.Substitutions) -> Bool:
  match variables:
    case Nil{}: True{}
    case +head <> tail:
      +type_bound = Maybe.is_some(&2, T.Version<M.Ty>, T.value_version(substitutions, head, 0n))
      +row_bound = Maybe.is_some(&2, T.Version<M.EffectRow>, T.row_version(substitutions, head, 0n))
      Bool.and(Bool.not(Bool.or(type_bound, row_bound)), quantified_unbound(tail, substitutions))

def binding_free(bindings: List<&2, I.Binding>, +substitutions: T.Substitutions) -> Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
  match bindings:
    case Nil{}:
      Done{Nil{}}
    case I.Binding{name, +ty, +variables} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
        checked : Unit <- Bool.pick(Result<&2, &2, M.Diagnostic, Unit>, quantified_unbound(variables, substitutions), Done{Unit{}}, Fail{M.Diagnostic{"internal_error", name, "bound imported quantifier"}})
        raw : List<&2, Nat> <- T.free(ty)
        resolved : M.Ty <- T.resolve(substitutions, ty)
        refined : List<&2, Nat> <- T.free(resolved)
        rest : List<&2, Nat> <- binding_free(tail, substitutions)
        return T.union(T.union(T.difference(raw, variables), T.difference(refined, variables)), rest)

def substitution_free(one: T.Substitution) -> Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
  match one:
    case T.Substitution{+variable, replacement}:
      T.free(replacement)
    case T.RowSubstitution{+variable, replacement}:
      Done{T.row_free(replacement)}

def adjacency(history: List<&2, T.Substitution>, +graph: NatIndex.Index<List<&2, Nat>>) -> Result<&2, &2, M.Diagnostic, NatIndex.Index<List<&2, Nat>>>:
  match history:
    case Nil{}:
      Done{graph}
    case head <> tail:
      match head:
        case T.Substitution{+variable, replacement}:
          do Result<&2, &2, M.Diagnostic, NatIndex.Index<List<&2, Nat>>>:
            added : List<&2, Nat> <- T.free(replacement)
            adjacency(tail, NatIndex.set(List<&2, Nat>, graph, variable, T.union(added, NatIndex.get(List<&2, Nat>, graph, variable, Nil{}))))
        case T.RowSubstitution{+variable, replacement}:
          adjacency(tail, NatIndex.set(List<&2, Nat>, graph, variable, T.union(T.row_free(replacement), NatIndex.get(List<&2, Nat>, graph, variable, Nil{}))))

type ClosureStep is Data:
  ClosureStep{queue: List<&2, Nat>, seen: List<&2, Nat>}

type MergeWork is Data:
  MergeVisit{values: List<&2, T.Version<M.Ty>>, rows: List<&2, T.Version<M.EffectRow>>, collected: List<&2, Nat>}
  MergeChoose{type_head: T.Version<M.Ty>, type_tail: List<&2, T.Version<M.Ty>>, row_head: T.Version<M.EffectRow>, row_tail: List<&2, T.Version<M.EffectRow>>, collected: List<&2, Nat>, type_first: Bool}

def merge_loop(fuel: Nat, work: MergeWork) -> Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
  match fuel work:
    case _ MergeVisit{Nil{}, Nil{}, collected}:
      Done{collected}
    case 0n _:
      Fail{M.Diagnostic{"internal_error", "parallel", "indexed version merge limit"}}
    case 1n+rest MergeVisit{T.Version{position, replacement} <> tail, Nil{}, collected}:
      do Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
        added : List<&2, Nat> <- T.free(replacement)
        merge_loop(rest, MergeVisit{tail, Nil{}, T.union(added, collected)})
    case 1n+rest MergeVisit{Nil{}, T.Version{position, replacement} <> tail, collected}:
      merge_loop(rest, MergeVisit{Nil{}, tail, T.union(T.row_free(replacement), collected)})
    case 1n+rest MergeVisit{T.Version{+type_position, type_replacement} <> type_tail, T.Version{+row_position, row_replacement} <> row_tail, collected}:
      merge_loop(rest, MergeChoose{T.Version{type_position, type_replacement}, type_tail, T.Version{row_position, row_replacement}, row_tail, collected, Nat.is_ge(type_position, row_position)})
    case 1n+rest MergeChoose{T.Version{position, replacement}, type_tail, row_head, row_tail, collected, True{}}:
      do Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
        added : List<&2, Nat> <- T.free(replacement)
        merge_loop(rest, MergeVisit{type_tail, row_head <> row_tail, T.union(added, collected)})
    case 1n+rest MergeChoose{type_head, type_tail, T.Version{position, replacement}, row_tail, collected, False{}}:
      merge_loop(rest, MergeVisit{type_head <> type_tail, row_tail, T.union(T.row_free(replacement), collected)})

def merge_versions(+values: List<&2, T.Version<M.Ty>>, +rows: List<&2, T.Version<M.EffectRow>>, collected: List<&2, Nat>) -> Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
  merge_loop(1n+Nat.mul(2n, Nat.add(List.length(&2, T.Version<M.Ty>, values), List.length(&2, T.Version<M.EffectRow>, rows))), MergeVisit{values, rows, collected})

def indexed_neighbors(substitutions: T.Substitutions, +variable: Nat) -> Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
  T.Substitutions{history, values, rows, count} = substitutions
  merge_versions(NatIndex.get(List<&2, T.Version<M.Ty>>, values, variable, Nil{}), NatIndex.get(List<&2, T.Version<M.EffectRow>>, rows, variable, Nil{}), Nil{})

def closure_next(visited: Bool, +head: Nat, tail: List<&2, Nat>, +seen: List<&2, Nat>, substitutions: T.Substitutions) -> Result<&2, &2, M.Diagnostic, ClosureStep>:
  match visited:
    case True{}: Done{ClosureStep{tail, seen}}
    case False{}:
      do Result<&2, &2, M.Diagnostic, ClosureStep>:
        neighbors : List<&2, Nat> <- indexed_neighbors(substitutions, head)
        return ClosureStep{List.append(&2, Nat, tail, T.difference(neighbors, head <> seen)), head <> seen}

def read_closure(fuel: Nat, work: ClosureStep, +substitutions: T.Substitutions) -> Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
  match fuel work:
    case _ ClosureStep{Nil{}, seen}: Done{seen}
    case 0n _:
      Fail{M.Diagnostic{"internal_error", "parallel", "read closure limit"}}
    case 1n+rest ClosureStep{+head <> tail, +seen}:
      do Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
        next : ClosureStep <- closure_next(T.contains(seen, head), head, tail, seen, substitutions)
        read_closure(rest, next, substitutions)

def classified(+declaration: G.Declaration, pending: Set(), found: Result<&2, &2, M.Diagnostic, D.References>) -> Classified:
  match found:
    case Fail{error}: Ineligible{declaration}
    case Done{references}:
      Bool.pick(Classified, any_pending(D.names_of(references), pending), Ineligible{declaration}, Eligible{declaration})

def classify(declarations: List<&2, G.Declaration>, +pending: Set()) -> List<&2, Classified>:
  match declarations:
    case Nil{}: Nil{}
    case +head <> tail:
      classified(head, pending, D.references(Nat.mul(256n, 256n), D.Expression{declaration_body(head)})) <> classify(tail, pending)

def reads_from_references(references: D.References, name: String, +environment: G.Environment, catalog: Maybe<&2, Map<&2, List<&2, Bindings.Entry>>>) -> Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
  +substitutions = I.substitutions_of(G.env_state(environment))
  do Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
    free : List<&2, Nat> <- binding_free(G.reference_bindings_prepared(catalog, G.env_bindings(environment), name <> D.names_of(references)), substitutions)
    read_closure(1048576n, ClosureStep{free, Nil{}}, substitutions)

def reads_result(+declaration: G.Declaration, environment: G.Environment, catalog: Maybe<&2, Map<&2, List<&2, Bindings.Entry>>>) -> Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
  +name = G.declaration_name(declaration)
  +body = declaration_body(declaration)
  do Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
    references : D.References <- D.references(Nat.mul(256n, 256n), D.Expression{body})
    reads_from_references(references, name, environment, catalog)

def collect(declarations: List<&2, Classified>, reversed: List<&2, G.Declaration>) -> Run:
  match declarations:
    case Nil{}:
      Run{List.reverse(&2, G.Declaration, reversed), Nil{}}
    case Eligible{head} <> tail:
      collect(tail, head <> reversed)
    case Ineligible{head} <> tail:
      Run{List.reverse(&2, G.Declaration, reversed), declarations}

def prepare_jobs(declarations: List<&2, G.Declaration>, +environment: G.Environment, +catalog: Maybe<&2, Map<&2, List<&2, Bindings.Entry>>>, +ordinal: Nat) -> Result<&2, &2, M.Diagnostic, List<&2, Job>>:
  match declarations:
    case Nil{}: Done{Nil{}}
    case +head <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, Job>>:
        +reads : List<&2, Nat> <- reads_result(head, environment, catalog)
        rest : List<&2, Job> <- prepare_jobs(tail, environment, catalog, 1n+ordinal)
        return Job{head, reads, Nat.add(I.next_of(G.env_state(environment)), Nat.mul(ordinal, 65536n)), Nat.add(I.next_of(G.env_state(environment)), Nat.mul(1n+ordinal, 65536n))} <> rest

def type_closed_result(found: Result<&2, &2, M.Diagnostic, List<&2, Nat>>) -> Bool:
  match found:
    case Done{free}: Nat.is_eq(List.length(&2, Nat, free), 0n)
    case Fail{error}: False{}

def types_closed(types: List<&2, M.Ty>) -> Bool:
  match types:
    case Nil{}: True{}
    case head <> tail:
      Bool.and(type_closed_result(T.free(head)), types_closed(tail))

def operation_closed(operation: M.Operation) -> Bool:
  match operation:
    case M.Operation{identity, parameter, result}:
      types_closed([parameter, result])
    case M.OperationTemplate{identity, parameters, parameter, result}:
      types_closed([parameter, result])
    case M.OperationInstance{template, arguments}:
      types_closed(arguments)

def operations_closed(operations: List<&2, M.Operation>) -> Bool:
  match operations:
    case Nil{}: True{}
    case head <> tail: Bool.and(operation_closed(head), operations_closed(tail))

def constructors_closed(constructors: List<&2, M.Constructor>) -> Bool:
  match constructors:
    case Nil{}: True{}
    case M.Constructor{name, None{}, fields} <> tail: constructors_closed(tail)
    case M.Constructor{name, Some{payload}, fields} <> tail:
      Bool.and(type_closed_result(T.free(payload)), constructors_closed(tail))

def data_types_closed(types: List<&2, M.DataType>) -> Bool:
  match types:
    case Nil{}: True{}
    case M.DataType{identity, parameters, constructors} <> tail:
      Bool.and(constructors_closed(constructors), data_types_closed(tail))

def run_job(job: Job, context: Context) -> Outcome:
  Job{+declaration, reads, +first, limit} = job
  Context{environment, operations, types, functions, catalog} = context
  G.Environment{bindings, definitions, state} = environment
  +separate = {G.Environment{bindings, definitions, I.with_next(state, first)} : G.Environment}
  Outcome{Job{declaration, reads, first, limit}, G.infer_declaration_prepared(declaration, separate, operations, types, functions, catalog)}

def weighted(jobs: List<&2, Job>) -> List<&2, Batch.Weighted<Job>>:
  match jobs:
    case Nil{}: Nil{}
    case head <> tail: Batch.Weighted{head, 1n} <> weighted(tail)

def serial(declarations: List<&2, G.Declaration>, environment: G.Environment, +operations: List<&2, M.Operation>, +types: List<&2, M.DataType>, +functions: List<&2, String>, +catalog: Maybe<&2, Map<&2, List<&2, Bindings.Entry>>>) -> Result<&2, &2, M.Diagnostic, G.Environment>:
  match declarations:
    case Nil{}: Done{environment}
    case declaration <> tail:
      do Result<&2, &2, M.Diagnostic, G.Environment>:
        next : G.Environment <- G.infer_declaration_prepared(declaration, environment, operations, types, functions, catalog)
        serial(tail, next, operations, types, functions, catalog)

def delta(history: List<&2, T.Substitution>, count: Nat) -> List<&2, T.Substitution>:
  match history count:
    case _ 0n: Nil{}
    case head <> tail 1n+rest: head <> delta(tail, rest)
    case _ _: Nil{}

def written_ids(changes: List<&2, T.Substitution>) -> List<&2, Nat>:
  match changes:
    case Nil{}: Nil{}
    case T.Substitution{+variable, replacement} <> tail:
      variable <> written_ids(tail)
    case T.RowSubstitution{+variable, replacement} <> tail:
      variable <> written_ids(tail)

def compatible(reads: List<&2, Nat>, +writes: List<&2, Nat>, seen_reads: List<&2, Nat>, +seen_writes: List<&2, Nat>) -> Bool:
  Bool.not(Bool.or(overlap(writes, seen_reads), Bool.or(overlap(reads, seen_writes), overlap(writes, seen_writes))))

type ConflictWork is Data:
  Gather{outcomes: List<&2, Outcome>, seen_reads: List<&2, Nat>, seen_writes: List<&2, Nat>}
  Check{outcomes: List<&2, Outcome>, reads: List<&2, Nat>, substitutions: T.Substitutions, count: Nat, seen_reads: List<&2, Nat>, seen_writes: List<&2, Nat>, count_valid: Bool}

def conflict_loop(fuel: Nat, work: ConflictWork, +base_count: Nat) -> Bool:
  match fuel work:
    case _ Gather{Nil{}, seen_reads, seen_writes}: True{}
    case 0n _: False{}
    case 1n+rest Gather{Outcome{job, Fail{error}} <> tail, seen_reads, seen_writes}: False{}
    case 1n+rest Gather{Outcome{Job{declaration, reads, first, limit}, Done{G.Environment{bindings, definitions, state}}} <> tail, seen_reads, seen_writes}:
      +subs = I.substitutions_of(state)
      +count = T.substitution_count(subs)
      conflict_loop(rest, Check{tail, reads, subs, count, seen_reads, seen_writes, Nat.is_ge(count, base_count)}, base_count)
    case 1n+rest Check{outcomes, reads, substitutions, count, seen_reads, seen_writes, False{}}: False{}
    case 1n+rest Check{outcomes, +reads, substitutions, count, +seen_reads, +seen_writes, True{}}:
      +writes = written_ids(delta(T.substitution_history(substitutions), Nat.sub(count, base_count)))
      Bool.and(compatible(reads, writes, seen_reads, seen_writes), conflict_loop(rest, Gather{outcomes, T.union(reads, seen_reads), T.union(writes, seen_writes)}, base_count))

def conflicts_absent(+outcomes: List<&2, Outcome>, base_count: Nat) -> Bool:
  conflict_loop(1n+Nat.mul(2n, List.length(&2, Outcome, outcomes)), Gather{outcomes, Nil{}, Nil{}}, base_count)

def ids_safe(ids: List<&2, Nat>, +reads: List<&2, Nat>, +snapshot: Nat, +first: Nat, +next: Nat) -> Bool:
  match ids:
    case Nil{}: True{}
    case +id <> tail:
      +allowed = Bool.pick(Bool, Nat.is_lt(id, snapshot), T.contains(reads, id), Bool.and(Nat.is_ge(id, first), Nat.is_lt(id, next)))
      Bool.and(allowed, ids_safe(tail, reads, snapshot, first, next))

def types_free(types: List<&2, M.Ty>) -> Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
  match types:
    case Nil{}: Done{Nil{}}
    case head <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
        a : List<&2, Nat> <- T.free(head)
        b : List<&2, Nat> <- types_free(tail)
        return T.union(a, b)

def coverage_free(coverage: I.Coverage) -> Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
  match coverage:
    case I.OperationNeed{identity, template, arguments, function_type, subject}:
      do Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
        a : List<&2, Nat> <- types_free(arguments)
        b : List<&2, Nat> <- T.free(function_type)
        return T.union(a, b)
    case I.AssociatedNeed{identity, dispatch, member, templates, left, right, result, ambient, subject}:
      do Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
        free : List<&2, Nat> <- types_free([left, right, result])
        return T.union(free, T.row_free(ambient))
    case I.ValuePatternType{inferred_type, subject}:
      T.free(inferred_type)
    case I.Coverage{inferred_types, patterns, subject}:
      types_free(inferred_types)

def coverages_free(coverages: List<&2, I.Coverage>) -> Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
  match coverages:
    case Nil{}: Done{Nil{}}
    case head <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
        a : List<&2, Nat> <- coverage_free(head)
        b : List<&2, Nat> <- coverages_free(tail)
        return T.union(a, b)

def definition_free(definition: I.Definition) -> Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
  I.Definition{name, I.Inference{ty, coverage, exits, reflections}} = definition
  do Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
    a : List<&2, Nat> <- T.free(ty)
    b : List<&2, Nat> <- coverages_free(coverage)
    return T.union(a, b)

def mapping(count: Nat, +first: Nat, +target: Nat, +result: NatIndex.Index<Nat>) -> NatIndex.Index<Nat>:
  match count:
    case 0n: result
    case 1n+rest: mapping(rest, 1n+first, 1n+target, NatIndex.set(Nat, result, first, target))

def rename_types(types: List<&2, M.Ty>, +mapping: NatIndex.Index<Nat>) -> Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>:
  match types:
    case Nil{}: Done{Nil{}}
    case head <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>:
        a : M.Ty <- T.rename_type(head, mapping)
        b : List<&2, M.Ty> <- rename_types(tail, mapping)
        return a <> b

def rename_coverage(coverage: I.Coverage, +mapping: NatIndex.Index<Nat>) -> Result<&2, &2, M.Diagnostic, I.Coverage>:
  match coverage:
    case I.OperationNeed{identity, template, arguments, function_type, subject}:
      do Result<&2, &2, M.Diagnostic, I.Coverage>:
        args : List<&2, M.Ty> <- rename_types(arguments, mapping)
        fn : M.Ty <- T.rename_type(function_type, mapping)
        return I.OperationNeed{identity, template, args, fn, subject}
    case I.AssociatedNeed{identity, dispatch, member, templates, left, right, result, ambient, subject}:
      do Result<&2, &2, M.Diagnostic, I.Coverage>:
        a : M.Ty <- T.rename_type(left, mapping)
        b : M.Ty <- T.rename_type(right, mapping)
        c : M.Ty <- T.rename_type(result, mapping)
        return I.AssociatedNeed{identity, dispatch, member, templates, a, b, c, T.rename_row(ambient, mapping), subject}
    case I.ValuePatternType{inferred_type, subject}:
      do Result<&2, &2, M.Diagnostic, I.Coverage>:
        ty : M.Ty <- T.rename_type(inferred_type, mapping)
        return I.ValuePatternType{ty, subject}
    case I.Coverage{inferred_types, patterns, subject}:
      do Result<&2, &2, M.Diagnostic, I.Coverage>:
        tys : List<&2, M.Ty> <- rename_types(inferred_types, mapping)
        return I.Coverage{tys, patterns, subject}

def rename_coverages(coverages: List<&2, I.Coverage>, +mapping: NatIndex.Index<Nat>) -> Result<&2, &2, M.Diagnostic, List<&2, I.Coverage>>:
  match coverages:
    case Nil{}: Done{Nil{}}
    case head <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, I.Coverage>>:
        a : I.Coverage <- rename_coverage(head, mapping)
        b : List<&2, I.Coverage> <- rename_coverages(tail, mapping)
        return a <> b

def rename_definition(definition: I.Definition, +mapping: NatIndex.Index<Nat>) -> Result<&2, &2, M.Diagnostic, I.Definition>:
  I.Definition{name, I.Inference{ty, coverage, exits, reflections}} = definition
  do Result<&2, &2, M.Diagnostic, I.Definition>:
    next_ty : M.Ty <- T.rename_type(ty, mapping)
    next_coverage : List<&2, I.Coverage> <- rename_coverages(coverage, mapping)
    return I.Definition{name, I.Inference{next_ty, next_coverage, exits, reflections}}

def rename_substitution(substitution: T.Substitution, +mapping: NatIndex.Index<Nat>) -> Result<&2, &2, M.Diagnostic, T.Substitution>:
  match substitution:
    case T.Substitution{+variable, replacement}:
      do Result<&2, &2, M.Diagnostic, T.Substitution>:
        ty : M.Ty <- T.rename_type(replacement, mapping)
        return T.Substitution{NatIndex.get(Nat, mapping, variable, variable), ty}
    case T.RowSubstitution{+variable, replacement}:
      Done{T.RowSubstitution{NatIndex.get(Nat, mapping, variable, variable), T.rename_row(replacement, mapping)}}

def replay_delta(delta: List<&2, T.Substitution>, +mapping: NatIndex.Index<Nat>, substitutions: T.Substitutions) -> Result<&2, &2, M.Diagnostic, T.Substitutions>:
  match delta:
    case Nil{}: Done{substitutions}
    case head <> tail:
      do Result<&2, &2, M.Diagnostic, T.Substitutions>:
        value : T.Substitution <- rename_substitution(head, mapping)
        replay_delta(tail, mapping, T.append_substitution(substitutions, value))

def result_option(-V: Data, found: Result<&2, &2, M.Diagnostic, V>) -> Maybe<&2, V>:
  match found:
    case Fail{error}: None{}
    case Done{value}: Some{value}

def valid_unit(valid: Bool) -> Maybe<&2, Unit>:
  match valid:
    case False{}: None{}
    case True{}: Some{Unit{}}

def commit_safe(definition: I.Definition, changes: List<&2, T.Substitution>, first: Nat, +fresh: Nat, +environment: G.Environment) -> Maybe<&2, G.Environment>:
  +serial_next = I.next_of(G.env_state(environment))
  +rename = mapping(fresh, first, serial_next, NatIndex.new(Nat))
  do Maybe<&2, G.Environment>:
    renamed : I.Definition <- result_option(I.Definition, rename_definition(definition, rename))
    replayed : T.Substitutions <- result_option(T.Substitutions, replay_delta(List.reverse(&2, T.Substitution, changes), rename, I.substitutions_of(G.env_state(environment))))
    return G.Environment{G.env_bindings(environment), renamed <> G.env_definitions(environment), I.State{replayed, Nat.add(serial_next, fresh), MTip{}}}

def commit_valid(+definition: I.Definition, +reads: List<&2, Nat>, +first: Nat, +next: Nat, +subs: T.Substitutions, +count: Nat, +snapshot: Nat, +base_count: Nat, +environment: G.Environment, valid: Bool) -> Maybe<&2, G.Environment>:
  match valid:
    case False{}: None{}
    case True{}:
      +changes = delta(T.substitution_history(subs), Nat.sub(count, base_count))
      +fresh = Nat.sub(next, first)
      do Maybe<&2, G.Environment>:
        ids : List<&2, Nat> <- result_option(List<&2, Nat>, T.substitutions_free(changes))
        defs : List<&2, Nat> <- result_option(List<&2, Nat>, definition_free(definition))
        checked : Unit <- valid_unit(Bool.and(ids_safe(ids, reads, snapshot, first, next), ids_safe(defs, reads, snapshot, first, next)))
        commit_safe(definition, changes, first, fresh, environment)

def commit_one(outcome: Outcome, environment: G.Environment, snapshot: Nat, +base_count: Nat) -> Maybe<&2, G.Environment>:
  match outcome:
    case Outcome{job, Fail{error}}: None{}
    case Outcome{job, Done{G.Environment{bindings, Nil{}, state}}}: None{}
    case Outcome{Job{declaration, reads, +first, limit}, Done{G.Environment{bindings, definition <> rest, +state}}}:
      +next = I.next_of(state)
      +subs = I.substitutions_of(state)
      +count = T.substitution_count(subs)
      commit_valid(definition, reads, first, next, subs, count, snapshot, base_count, environment, Bool.and(Nat.is_ge(next, first), Bool.and(Nat.is_lt(next, limit), Nat.is_ge(count, base_count))))

def commit(outcomes: List<&2, Outcome>, pending: Maybe<&2, G.Environment>, +snapshot: Nat, +base_count: Nat) -> Maybe<&2, G.Environment>:
  match outcomes pending:
    case Nil{} result: result
    case head <> tail None{}: None{}
    case head <> tail Some{environment}:
      commit(tail, commit_one(head, environment, snapshot, base_count), snapshot, base_count)

def windows_fit_length(next: Nat, length: Nat, short: Bool) -> Bool:
  match short:
    case False{}: False{}
    case True{}: Nat.is_le(1n+length, Nat.div(Nat.sub(U32.to_nat(4294967295), next), 65536n))

def windows_fit(next: Nat, +length: Nat, under_limit: Bool) -> Bool:
  match under_limit:
    case False{}: False{}
    case True{}:
      windows_fit_length(next, length, Nat.is_le(length, 65535n))

def serial_or_committed(committed: Maybe<&2, G.Environment>, declarations: List<&2, G.Declaration>, environment: G.Environment, operations: List<&2, M.Operation>, types: List<&2, M.DataType>, functions: List<&2, String>, catalog: Maybe<&2, Map<&2, List<&2, Bindings.Entry>>>) -> Result<&2, &2, M.Diagnostic, G.Environment>:
  match committed:
    case Some{result}: Done{result}
    case None{}: serial(declarations, environment, operations, types, functions, catalog)

def commit_if_compatible_checked(outcomes: List<&2, Outcome>, environment: G.Environment, snapshot: Nat, base_count: Nat, compatible: Bool) -> Maybe<&2, G.Environment>:
  match compatible:
    case False{}: None{}
    case True{}: commit(outcomes, Some{environment}, snapshot, base_count)

def commit_if_compatible(+outcomes: List<&2, Outcome>, environment: G.Environment, snapshot: Nat, +base_count: Nat) -> Maybe<&2, G.Environment>:
  commit_if_compatible_checked(outcomes, environment, snapshot, base_count, conflicts_absent(outcomes, base_count))

def execute_jobs(jobs: List<&2, Job>, declarations: List<&2, G.Declaration>, +environment: G.Environment, +operations: List<&2, M.Operation>, +types: List<&2, M.DataType>, +functions: List<&2, String>, +catalog: Maybe<&2, Map<&2, List<&2, Bindings.Entry>>>) -> Result<&2, &2, M.Diagnostic, G.Environment>:
  +context = {Context{environment, operations, types, functions, catalog} : Context}
  +outcomes = Batch.execute(~Job, ~Context, ~Outcome, ~run_job, Batch.plan(Job, weighted(jobs), 1n), context)
  +base_count = T.substitution_count(I.substitutions_of(G.env_state(environment)))
  serial_or_committed(commit_if_compatible(outcomes, environment, I.next_of(G.env_state(environment)), base_count), declarations, environment, operations, types, functions, catalog)

def checked_jobs(found: Result<&2, &2, M.Diagnostic, List<&2, Job>>, declarations: List<&2, G.Declaration>, environment: G.Environment, operations: List<&2, M.Operation>, types: List<&2, M.DataType>, functions: List<&2, String>, catalog: Maybe<&2, Map<&2, List<&2, Bindings.Entry>>>) -> Result<&2, &2, M.Diagnostic, G.Environment>:
  match found:
    case Fail{error}: serial(declarations, environment, operations, types, functions, catalog)
    case Done{jobs}: execute_jobs(jobs, declarations, environment, operations, types, functions, catalog)

def run_parallel_if(+declarations: List<&2, G.Declaration>, +environment: G.Environment, operations: List<&2, M.Operation>, types: List<&2, M.DataType>, functions: List<&2, String>, +catalog: Maybe<&2, Map<&2, List<&2, Bindings.Entry>>>, enabled: Bool) -> Result<&2, &2, M.Diagnostic, G.Environment>:
  match enabled:
    case False{}: serial(declarations, environment, operations, types, functions, catalog)
    case True{}:
      checked_jobs(prepare_jobs(declarations, environment, catalog, 0n), declarations, environment, operations, types, functions, catalog)

def run_parallel(+declarations: List<&2, G.Declaration>, +environment: G.Environment, operations: List<&2, M.Operation>, types: List<&2, M.DataType>, functions: List<&2, String>, catalog: Maybe<&2, Map<&2, List<&2, Bindings.Entry>>>) -> Result<&2, &2, M.Diagnostic, G.Environment>:
  +next = I.next_of(G.env_state(environment))
  run_parallel_if(declarations, environment, operations, types, functions, catalog, windows_fit(next, List.length(&2, G.Declaration, declarations), Nat.is_lt(next, U32.to_nat(4294967295))))

type Work is Data:
  Evaluate{remaining: List<&2, Classified>, environment: G.Environment}
  Execute{run: Run, environment: G.Environment}

def infer_work(fuel: Nat, work: Work, +operations: List<&2, M.Operation>, +types: List<&2, M.DataType>, +functions: List<&2, String>, +catalog: Maybe<&2, Map<&2, List<&2, Bindings.Entry>>>) -> Result<&2, &2, M.Diagnostic, G.Environment>:
  match fuel work:
    case _ Evaluate{Nil{}, environment}: Done{environment}
    case 0n _:
      Fail{M.Diagnostic{"internal_error", "parallel", "inference traversal limit"}}
    case 1n+rest Evaluate{Ineligible{declaration} <> tail, environment}:
      do Result<&2, &2, M.Diagnostic, G.Environment>:
        next : G.Environment <- G.infer_declaration_prepared(declaration, environment, operations, types, functions, catalog)
        infer_work(rest, Evaluate{tail, next}, operations, types, functions, catalog)
    case 1n+rest Evaluate{Eligible{declaration} <> tail, environment}:
      infer_work(rest, Execute{collect(Eligible{declaration} <> tail, Nil{}), environment}, operations, types, functions, catalog)
    case 1n+rest Execute{Run{Nil{}, remaining}, environment}:
      infer_work(rest, Evaluate{remaining, environment}, operations, types, functions, catalog)
    case 1n+rest Execute{Run{[declaration], remaining}, environment}:
      do Result<&2, &2, M.Diagnostic, G.Environment>:
        next : G.Environment <- G.infer_declaration_prepared(declaration, environment, operations, types, functions, catalog)
        infer_work(rest, Evaluate{remaining, next}, operations, types, functions, catalog)
    case 1n+rest Execute{Run{declarations, remaining}, environment}:
      do Result<&2, &2, M.Diagnostic, G.Environment>:
        next : G.Environment <- run_parallel(declarations, environment, operations, types, functions, catalog)
        infer_work(rest, Evaluate{remaining, next}, operations, types, functions, catalog)

def unique_names(names: List<&2, String>, +seen: Set()) -> Bool:
  match names:
    case Nil{}: True{}
    case +name <> tail:
      Bool.and(Bool.not(D.member(seen, name)), unique_names(tail, Set.add(seen, name)))

def ineligible_all(declarations: List<&2, G.Declaration>) -> List<&2, Classified>:
  match declarations:
    case Nil{}: Nil{}
    case head <> tail: Ineligible{head} <> ineligible_all(tail)

def classify_all(declarations: List<&2, G.Declaration>, pending: Set(), enabled: Bool) -> List<&2, Classified>:
  match enabled:
    case False{}: ineligible_all(declarations)
    case True{}: classify(declarations, pending)

def catalog_closed(operations: List<&2, M.Operation>, types: List<&2, M.DataType>) -> Bool:
  Bool.and(operations_closed(operations), data_types_closed(types))

def infer_with_state(state: I.State, +declarations: List<&2, G.Declaration>, +all_pending_names: List<&2, String>, environment: G.Environment, operations: List<&2, M.Operation>, types: List<&2, M.DataType>, functions: List<&2, String>, catalog: Maybe<&2, Map<&2, List<&2, Bindings.Entry>>>, enabled: Bool) -> Result<&2, &2, M.Diagnostic, G.Environment>:
  match state:
    case I.State{substitutions, next, MTip{}}:
      infer_work(1n+Nat.mul(2n, List.length(&2, G.Declaration, declarations)), Evaluate{classify_all(declarations, G.reference_set(all_pending_names, Set.new()), enabled), environment}, operations, types, functions, catalog)
    case _:
      infer_work(1n+Nat.mul(2n, List.length(&2, G.Declaration, declarations)), Evaluate{ineligible_all(declarations), environment}, operations, types, functions, catalog)

# Caller has already checked full-bundle name uniqueness. The catalog remains
# immutable across staged barriers, so its closedness can be reused per segment.
def infer_segment_prechecked(declarations: List<&2, G.Declaration>, all_pending_names: List<&2, String>, +environment: G.Environment, operations: List<&2, M.Operation>, types: List<&2, M.DataType>, functions: List<&2, String>, catalog: Maybe<&2, Map<&2, List<&2, Bindings.Entry>>>, catalog_is_closed: Bool) -> Result<&2, &2, M.Diagnostic, G.Environment>:
  match declarations:
    case Nil{}: Done{environment}
    case [declaration]: G.infer_declaration_prepared(declaration, environment, operations, types, functions, catalog)
    case a <> b <> rest:
      infer_with_state(G.env_state(environment), a <> b <> rest, all_pending_names, environment, operations, types, functions, catalog, catalog_is_closed)

def infer_segment(declarations: List<&2, G.Declaration>, +all_pending_names: List<&2, String>, +environment: G.Environment, +operations: List<&2, M.Operation>, +types: List<&2, M.DataType>, functions: List<&2, String>, catalog: Maybe<&2, Map<&2, List<&2, Bindings.Entry>>>) -> Result<&2, &2, M.Diagnostic, G.Environment>:
  match declarations:
    case Nil{}: Done{environment}
    case [declaration]: G.infer_declaration_prepared(declaration, environment, operations, types, functions, catalog)
    case a <> b <> rest:
      infer_with_state(G.env_state(environment), a <> b <> rest, all_pending_names, environment, operations, types, functions, catalog, Bool.and(unique_names(all_pending_names, Set.new()), catalog_closed(operations, types)))

def infer_component_unique(declarations: List<&2, G.Declaration>, +names: List<&2, String>, +environment: G.Environment, operations: List<&2, M.Operation>, types: List<&2, M.DataType>, functions: List<&2, String>, unique: Bool) -> Result<&2, &2, M.Diagnostic, G.Environment>:
  match unique:
    case False{}: G.infer_component(names, declarations, environment, operations, types, functions)
    case True{}: infer_segment(declarations, names, environment, operations, types, functions, G.component_bindings(names, G.env_bindings(environment)))

def infer_component(declarations: List<&2, G.Declaration>, environment: G.Environment, operations: List<&2, M.Operation>, types: List<&2, M.DataType>, functions: List<&2, String>) -> Result<&2, &2, M.Diagnostic, G.Environment>:
  match declarations:
    case Nil{}: Done{environment}
    case [declaration]: G.infer_declaration_prepared(declaration, environment, operations, types, functions, None{})
    case a <> b <> rest:
      +all = {a <> b <> rest : List<&2, G.Declaration>}
      +names = G.names(all)
      infer_component_unique(all, names, environment, operations, types, functions, unique_names(names, Set.new()))
