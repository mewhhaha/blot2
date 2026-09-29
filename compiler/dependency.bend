import Base
import ./model.bend as M
import ./index.bend as Index
import ./nat_index.bend as NatIndex

type Node is Data:
  Node{name: String, references: List<&2, String>, lambdas: List<&2, Nat>}

type Work is Data:
  Expression{value: M.Expr}
  Arms{values: List<&2, M.MatchArm<M.Expr>>}
  Expressions{values: List<&2, M.Expr>}
  Patterns{values: List<&2, M.Pattern>}

type References is Data:
  References{names: List<&2, String>, lambdas: List<&2, Nat>}

def names_of(refs: References) -> List<&2, String>:
  References{names, lambdas} = refs
  names

def lambdas_of(refs: References) -> List<&2, Nat>:
  References{names, lambdas} = refs
  lambdas

def reference_name(name: String, reversed: References) -> References:
  References{names, lambdas} = reversed
  References{name <> names, lambdas}

def reference_lambda(identity: Nat, reversed: References) -> References:
  References{names, lambdas} = reversed
  References{names, identity <> lambdas}

def reference_order(reversed: References) -> References:
  References{names, lambdas} = reversed
  References{List.reverse(&2, String, names), List.reverse(&2, Nat, lambdas)}

def payload_expression(payload: Maybe<&2, M.Expr>) -> M.Expr:
  match payload:
    case None{}:
      M.UnitExpr{}
    case Some{value}:
      value

type PendingReference is Data:
  PendingReference{depth: Nat, work: Work}

type ReferenceStep is Data:
  ReferenceStep{pending: List<&2, PendingReference>, reversed: References}

# Each queued branch carries its original structural depth budget. Siblings
# do not consume one another's fuel, even though the traversal is now flat.
def reference_step(+fuel: Nat, work: Work, pending: List<&2, PendingReference>, reversed: References) -> Result<&2, &2, M.Diagnostic, ReferenceStep>:
  match fuel work:
    case 0n _:
      Fail{M.Diagnostic{"expression_complexity", "inference", "expression nesting exceeds compiler traversal limit"}}
    case 1n+rest Expression{M.ConstantExpr{name}}:
      Done{ReferenceStep{pending, reference_name(name, reversed)}}
    case 1n+rest Expression{M.FunctionExpr{name}}:
      Done{ReferenceStep{pending, reference_name(name, reversed)}}
    case 1n+rest Expression{M.FunctionEffectsExpr{callee}}:
      Done{ReferenceStep{pending, reference_name(callee, reversed)}}
    case 1n+rest Expression{M.CallExpr{callee, argument}}:
      Done{ReferenceStep{PendingReference{rest, Expression{argument}} <> pending, reference_name(callee, reversed)}}
    case 1n+rest Expression{M.LambdaExpr{identity, parameter, p, r, body}}:
      Done{ReferenceStep{PendingReference{rest, Expression{body}} <> pending, reference_lambda(identity, reversed)}}
    case 1n+rest Expression{M.ApplyExpr{callee, argument}}:
      Done{ReferenceStep{PendingReference{rest, Expression{callee}} <> PendingReference{rest, Expression{argument}} <> pending, reversed}}
    case 1n+rest Expression{M.TagExpr{offset, callee, argument}}:
      Done{ReferenceStep{PendingReference{rest, Expression{callee}} <> PendingReference{rest, Expression{argument}} <> pending, reversed}}
    case 1n+rest Expression{M.AssociatedExpr{identity, dispatch, member, templates, left, right}}:
      Done{ReferenceStep{PendingReference{rest, Expression{left}} <> PendingReference{rest, Expression{right}} <> pending, reversed}}
    case 1n+rest Expression{M.ScalarExpr{operator, left, right}}:
      Done{ReferenceStep{PendingReference{rest, Expression{left}} <> PendingReference{rest, Expression{right}} <> pending, reversed}}
    case 1n+rest Expression{M.UnaryExpr{operator, value}}:
      Done{ReferenceStep{PendingReference{rest, Expression{value}} <> pending, reversed}}
    case 1n+rest Expression{M.LetExpr{name, value, body}}:
      Done{ReferenceStep{PendingReference{rest, Expression{value}} <> PendingReference{rest, Expression{body}} <> pending, reversed}}
    case 1n+rest Expression{M.UseExpr{name, value, body}}:
      Done{ReferenceStep{PendingReference{rest, Expression{value}} <> PendingReference{rest, Expression{body}} <> pending, reversed}}
    case 1n+rest Expression{M.IfExpr{condition, consequent, alternative}}:
      Done{ReferenceStep{PendingReference{rest, Expression{condition}} <> PendingReference{rest, Expression{consequent}} <> PendingReference{rest, Expression{alternative}} <> pending, reversed}}
    case 1n+rest Expression{M.SequenceExpr{first, next}}:
      Done{ReferenceStep{PendingReference{rest, Expression{first}} <> PendingReference{rest, Expression{next}} <> pending, reversed}}
    case 1n+rest Expression{M.MatchExpr{values, arms}}:
      Done{ReferenceStep{PendingReference{rest, Expressions{values}} <> PendingReference{rest, Arms{arms}} <> pending, reversed}}
    case 1n+rest Expression{M.GuardExpr{pattern, value, alternative, body}}:
      Done{ReferenceStep{PendingReference{rest, Patterns{[pattern]}} <> PendingReference{rest, Expression{value}} <> PendingReference{rest, Expression{alternative}} <> PendingReference{rest, Expression{body}} <> pending, reversed}}
    case 1n+rest Expression{M.ConstructExpr{constructor, payload}}:
      Done{ReferenceStep{PendingReference{rest, Expression{payload_expression(payload)}} <> pending, reversed}}
    case 1n+rest Expression{M.ProductExpr{elements}}:
      Done{ReferenceStep{PendingReference{rest, Expressions{elements}} <> pending, reversed}}
    case 1n+rest Expression{M.ProjectExpr{value, index}}:
      Done{ReferenceStep{PendingReference{rest, Expression{value}} <> pending, reversed}}
    case 1n+rest Expression{M.ArrayExpr{elements}}:
      Done{ReferenceStep{PendingReference{rest, Expressions{elements}} <> pending, reversed}}
    case 1n+rest Expression{M.ForExpr{index, start, end, state, initial, body}}:
      Done{ReferenceStep{PendingReference{rest, Expressions{[start, end, initial, body]}} <> pending, reversed}}
    case 1n+rest Expression{M.ForeverExpr{state, initial, body}}:
      Done{ReferenceStep{PendingReference{rest, Expressions{[initial, body]}} <> pending, reversed}}
    case 1n+rest Expression{M.ArrayGenerateExpr{count, generator}}:
      Done{ReferenceStep{PendingReference{rest, Expressions{[count, generator]}} <> pending, reversed}}
    case 1n+rest Expression{M.ArrayFillExpr{count, value}}:
      Done{ReferenceStep{PendingReference{rest, Expressions{[count, value]}} <> pending, reversed}}
    case 1n+rest Expression{M.ArrayGetExpr{array, index}}:
      Done{ReferenceStep{PendingReference{rest, Expressions{[array, index]}} <> pending, reversed}}
    case 1n+rest Expression{M.ArraySetExpr{array, index, value}}:
      Done{ReferenceStep{PendingReference{rest, Expressions{[array, index, value]}} <> pending, reversed}}
    case 1n+rest Expression{M.ArrayLengthExpr{array}}:
      Done{ReferenceStep{PendingReference{rest, Expression{array}} <> pending, reversed}}
    case 1n+rest Expression{M.BlockExpr{label, body}}:
      Done{ReferenceStep{PendingReference{rest, Expression{body}} <> pending, reversed}}
    case 1n+rest Expression{M.ReturnExpr{label, value}}:
      Done{ReferenceStep{PendingReference{rest, Expression{value}} <> pending, reversed}}
    case 1n+rest Expression{M.RuntimeInitExpr{value}}:
      Done{ReferenceStep{PendingReference{rest, Expression{value}} <> pending, reversed}}
    case 1n+rest Expression{M.SourceExpr{offset, annotation, value}}:
      Done{ReferenceStep{PendingReference{rest, Expression{value}} <> pending, reversed}}
    case 1n+rest Expression{M.QualifiedExpr{offset, annotation, predicates, value}}:
      Done{ReferenceStep{PendingReference{rest, Expression{value}} <> pending, reversed}}
    case 1n+rest Expression{M.MemoExpr{value}}:
      Done{ReferenceStep{PendingReference{rest, Expression{value}} <> pending, reversed}}
    case 1n+rest Expression{M.ForceExpr{value}}:
      Done{ReferenceStep{PendingReference{rest, Expression{value}} <> pending, reversed}}
    case 1n+rest Expression{M.InstantiationExpr{site, value}}:
      Done{ReferenceStep{PendingReference{rest, Expression{value}} <> pending, reversed}}
    case 1n+rest Expression{M.StateProviderExpr{read, write, initial}}:
      Done{ReferenceStep{PendingReference{rest, Expression{initial}} <> pending, reversed}}
    case 1n+rest Expression{M.ProviderExpr{identity, implementation}}:
      Done{ReferenceStep{PendingReference{rest, Expression{implementation}} <> pending, reversed}}
    case 1n+rest Expression{M.HandleExpr{provider, body}}:
      Done{ReferenceStep{PendingReference{rest, Expression{provider}} <> PendingReference{rest, Expression{body}} <> pending, reversed}}
    case 1n+rest Expression{M.EffectHasExpr{set, operation}}:
      Done{ReferenceStep{PendingReference{rest, Expression{set}} <> PendingReference{rest, Expression{operation}} <> pending, reversed}}
    case 1n+rest Expression{M.EffectCountExpr{set}}:
      Done{ReferenceStep{PendingReference{rest, Expression{set}} <> pending, reversed}}
    case 1n+rest Expression{M.EffectSameExpr{left, right}}:
      Done{ReferenceStep{PendingReference{rest, Expression{left}} <> PendingReference{rest, Expression{right}} <> pending, reversed}}
    case 1n+rest Expression{M.UnitExpr{}}:
      Done{ReferenceStep{pending, reversed}}
    case 1n+rest Expression{M.U32Expr{value}}:
      Done{ReferenceStep{pending, reversed}}
    case 1n+rest Expression{M.F32Expr{value}}:
      Done{ReferenceStep{pending, reversed}}
    case 1n+rest Expression{M.BoolExpr{value}}:
      Done{ReferenceStep{pending, reversed}}
    case 1n+rest Expression{M.LocalExpr{name}}:
      Done{ReferenceStep{pending, reversed}}
    case 1n+rest Expression{M.ConstructorRefExpr{name}}:
      Done{ReferenceStep{pending, reversed}}
    case 1n+rest Expression{M.GenericOperationExpr{identity, template, arguments}}:
      Done{ReferenceStep{pending, reversed}}
    case 1n+rest Expression{M.OperationExpr{identity}}:
      Done{ReferenceStep{pending, reversed}}
    case 1n+rest Expression{M.SpecializeOperationExpr{template, arguments, body}}:
      Done{ReferenceStep{PendingReference{rest, Expression{body}} <> pending, reversed}}
    case 1n+rest Expression{M.OperationDescriptorExpr{identity}}:
      Done{ReferenceStep{pending, reversed}}
    case 1n+rest Expression{M.PanicExpr{message}}:
      Done{ReferenceStep{pending, reversed}}
    case 1n+rest Arms{Nil{}}:
      Done{ReferenceStep{pending, reversed}}
    case 1n+rest Arms{M.MatchArm{patterns, body} <> tail}:
      Done{ReferenceStep{PendingReference{rest, Patterns{patterns}} <> PendingReference{rest, Expression{body}} <> PendingReference{rest, Arms{tail}} <> pending, reversed}}
    case 1n+rest Patterns{Nil{}}:
      Done{ReferenceStep{pending, reversed}}
    case 1n+rest Patterns{M.ValuePattern{reference} <> tail}:
      Done{ReferenceStep{PendingReference{rest, Expression{M.reference_expr(reference)}} <> PendingReference{rest, Patterns{tail}} <> pending, reversed}}
    case 1n+rest Patterns{M.ConstructorPattern{name, Some{payload}} <> tail}:
      Done{ReferenceStep{PendingReference{rest, Patterns{payload <> tail}} <> pending, reversed}}
    case 1n+rest Patterns{M.ProductPattern{elements} <> tail}:
      Done{ReferenceStep{PendingReference{rest, Patterns{elements}} <> PendingReference{rest, Patterns{tail}} <> pending, reversed}}
    case 1n+rest Patterns{pattern <> tail}:
      Done{ReferenceStep{PendingReference{rest, Patterns{tail}} <> pending, reversed}}
    case 1n+rest Expressions{Nil{}}:
      Done{ReferenceStep{pending, reversed}}
    case 1n+rest Expressions{head <> tail}:
      Done{ReferenceStep{PendingReference{rest, Expression{head}} <> PendingReference{rest, Expressions{tail}} <> pending, reversed}}

def references_walk(fuel: Nat, step: Result<&2, &2, M.Diagnostic, ReferenceStep>) -> Result<&2, &2, M.Diagnostic, References>:
  match fuel step:
    case _ Fail{error}:
      Fail{error}
    case _ Done{ReferenceStep{Nil{}, reversed}}:
      Done{reversed}
    case 0n _:
      Fail{M.Diagnostic{"expression_complexity", "inference", "expression traversal exceeds compiler work limit"}}
    case 1n+rest Done{ReferenceStep{PendingReference{depth, work} <> tail, reversed}}:
      references_walk(rest, reference_step(depth, work, tail, reversed))

def references_go(fuel: Nat, work: Work, reversed: References) -> Result<&2, &2, M.Diagnostic, References>:
  references_walk(M.max_nat(), Done{ReferenceStep{[PendingReference{fuel, work}], reversed}})

def references(fuel: Nat, work: Work) -> Result<&2, &2, M.Diagnostic, References>:
  do Result<&2, &2, M.Diagnostic, References>:
    reversed : References <- references_go(fuel, work, References{Nil{}, Nil{}})
    return reference_order(reversed)

def function_nodes(functions: List<&2, M.Function>) -> Result<&2, &2, M.Diagnostic, List<&2, Node>>:
  match functions:
    case Nil{}:
      Done{Nil{}}
    case M.Function{name, exported, parameter, p, r, body} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, Node>>:
        +refs : References <- references(Nat.mul(256n, 256n), Expression{body})
        rest : List<&2, Node> <- function_nodes(tail)
        return Node{name, names_of(refs), lambdas_of(refs)} <> rest

def constant_nodes(constants: List<&2, M.Constant>) -> Result<&2, &2, M.Diagnostic, List<&2, Node>>:
  match constants:
    case Nil{}:
      Done{Nil{}}
    case M.Constant{name, exported, annotation, value} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, Node>>:
        +refs : References <- references(Nat.mul(256n, 256n), Expression{value})
        rest : List<&2, Node> <- constant_nodes(tail)
        return Node{name, names_of(refs), lambdas_of(refs)} <> rest

def contains_step(equal: Bool, remaining: Unit -> Bool) -> Bool:
  match equal:
    case True{}:
      True{}
    case False{}:
      remaining(Unit{})

def contains_work(names: List<&2, String>, +name: String, found: Bool) -> Bool:
  match names found:
    case _ True{}:
      True{}
    case Nil{} False{}:
      False{}
    case head <> tail False{}:
      contains_work(tail, name, M.name_equal(head, name))

def contains(names: List<&2, String>, name: String) -> Bool:
  contains_work(names, name, False{})

# Keep the decision outside Bool.pick: its result arguments are evaluated
# eagerly, including the otherwise-unused scan after the first matching node.
def lookup_work(nodes: List<&2, Node>, +name: String, matched: Bool, found: List<&2, String>) -> List<&2, String>:
  match nodes matched:
    case _ True{}:
      found
    case Nil{} False{}:
      Nil{}
    case Node{candidate, refs, lambdas} <> tail False{}:
      lookup_work(tail, name, M.name_equal(candidate, name), refs)

def lookup(nodes: List<&2, Node>, name: String) -> List<&2, String>:
  lookup_work(nodes, name, False{}, Nil{})

def edge_count(nodes: List<&2, Node>) -> Nat:
  match nodes:
    case Nil{}:
      0n
    case Node{name, refs, lambdas} <> tail:
      Nat.add(List.length(&2, String, refs), edge_count(tail))

def next_work(visited: Bool, dependencies: List<&2, String>, pending: List<&2, String>) -> List<&2, String>:
  match visited:
    case True{}:
      pending
    case False{}:
      List.append(&2, String, dependencies, pending)

def node_names(nodes: List<&2, Node>) -> List<&2, String>:
  match nodes:
    case Nil{}:
      Nil{}
    case Node{name, refs, lambdas} <> tail:
      name <> node_names(tail)

def adjacency(nodes: List<&2, Node>, edges: Map<&2, List<&2, String>>) -> Map<&2, List<&2, String>>:
  match nodes:
    case Nil{}:
      edges
    case Node{name, refs, lambdas} <> tail:
      adjacency(tail, Index.set(List<&2, String>, edges, name, refs))

def neighbors(edges: Map<&2, List<&2, String>>, name: String) -> List<&2, String>:
  Index.get(List<&2, String>, edges, name, Nil{})

def transpose_edges(refs: List<&2, String>, +name: String, +edges: Map<&2, List<&2, String>>) -> Map<&2, List<&2, String>>:
  match refs:
    case Nil{}:
      edges
    case +head <> tail:
      transpose_edges(tail, name, Index.set(List<&2, String>, edges, head, name <> neighbors(edges, head)))

def transpose(nodes: List<&2, Node>, edges: Map<&2, List<&2, String>>) -> Map<&2, List<&2, String>>:
  match nodes:
    case Nil{}:
      edges
    case Node{name, refs, lambdas} <> tail:
      transpose(tail, transpose_edges(refs, name, edges))

def member(names: Set(), name: String) -> Bool:
  Maybe.is_some(&2, Unit, Index.find(Unit, names, name))

def mark(fresh: Bool, seen: Set(), name: String) -> Set():
  match fresh:
    case False{}:
      seen
    case True{}:
      Set.add(seen, name)

type Visit is Data:
  Enter{name: String}
  Leave{name: String}

def enter_events(names: List<&2, String>, tail: List<&2, Visit>) -> List<&2, Visit>:
  match names:
    case Nil{}:
      tail
    case head <> rest:
      Enter{head} <> enter_events(rest, tail)

def visit_events(fresh: Bool, name: String, refs: List<&2, String>, tail: List<&2, Visit>) -> List<&2, Visit>:
  match fresh:
    case False{}:
      tail
    case True{}:
      enter_events(refs, Leave{name} <> tail)

# A previously visited name needs neither another known-set lookup nor an
# adjacency lookup. The event list and fuel spent on each event stay unchanged.
def unseen_known(already_seen: Bool, known: Set(), name: String) -> Bool:
  match already_seen:
    case True{}:
      False{}
    case False{}:
      member(known, name)

def fresh_name(+name: String, +known: Set(), seen: Set()) -> Bool:
  unseen_known(member(seen, name), known, name)

def visit_events_edges(fresh: Bool, +name: String, edges: Map<&2, List<&2, String>>, tail: List<&2, Visit>) -> List<&2, Visit>:
  match fresh:
    case False{}:
      tail
    case True{}:
      enter_events(neighbors(edges, name), Leave{name} <> tail)

def finish_order(fuel: Nat, pending: List<&2, Visit>, +edges: Map<&2, List<&2, String>>, +known: Set(), +seen: Set(), order: List<&2, String>) -> Result<&2, &2, M.Diagnostic, List<&2, String>>:
  match fuel pending:
    case _ Nil{}:
      Done{order}
    case 0n _:
      Fail{M.Diagnostic{"internal_error", "inference", "dependency DFS exceeded its node/edge bound"}}
    case 1n+rest Enter{+name} <> tail:
      +fresh = fresh_name(name, known, seen)
      finish_order(rest, visit_events_edges(fresh, name, edges, tail), edges, known, mark(fresh, seen, name), order)
    case 1n+rest Leave{name} <> tail:
      finish_order(rest, tail, edges, known, seen, name <> order)

type Reachability is Data:
  Reachability{seen: Set(), members: List<&2, String>}

def reached_seen(result: Reachability) -> Set():
  Reachability{seen, members} = result
  seen

def reached_members(result: Reachability) -> List<&2, String>:
  Reachability{seen, members} = result
  members

def next_work_edges(fresh: Bool, edges: Map<&2, List<&2, String>>, name: String, pending: List<&2, String>) -> List<&2, String>:
  match fresh:
    case False{}:
      pending
    case True{}:
      List.append(&2, String, neighbors(edges, name), pending)

def reachable(fuel: Nat, pending: List<&2, String>, +edges: Map<&2, List<&2, String>>, +known: Set(), +seen: Set(), +members: List<&2, String>) -> Result<&2, &2, M.Diagnostic, Reachability>:
  match fuel pending:
    case _ Nil{}:
      Done{Reachability{seen, members}}
    case 0n _:
      Fail{M.Diagnostic{"internal_error", "inference", "dependency component exceeded its node/edge bound"}}
    case 1n+rest +head <> tail:
      +fresh = fresh_name(head, known, seen)
      reachable(rest, next_work_edges(fresh, edges, head, tail), edges, known, mark(fresh, seen, head), Bool.pick(List<&2, String>, fresh, head <> members, members))

def prepend_component(members: List<&2, String>, rest: List<&2, List<&2, String>>) -> List<&2, List<&2, String>>:
  match members:
    case Nil{}:
      rest
    case head <> tail:
      (head <> tail) <> rest

def collect_components(order: List<&2, String>, +edges: Map<&2, List<&2, String>>, +known: Set(), seen: Set(), +fuel: Nat) -> Result<&2, &2, M.Diagnostic, List<&2, List<&2, String>>>:
  match order:
    case Nil{}:
      Done{Nil{}}
    case head <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, List<&2, String>>>:
        +reached : Reachability <- reachable(fuel, [head], edges, known, seen, Nil{})
        rest : List<&2, List<&2, String>> <- collect_components(tail, edges, known, reached_seen(reached), fuel)
        return prepend_component(reached_members(reached), rest)

# Resolve declaration names once. Both Kosaraju passes then use compact
# numeric identities, preserving input, edge and SCC member order. Unknown
# references remain inference's responsibility; dropping their DFS events
# cannot move a known declaration or exhaust the original node/edge bound.
type CompactCatalog is Data:
  CompactCatalog{ids: Map<&2, Nat>, names: NatIndex.Index<String>}

def compact_catalog(nodes: List<&2, Node>, +next: Nat, known: CompactCatalog) -> CompactCatalog:
  match nodes:
    case Nil{}:
      known
    case Node{+name, references, lambdas} <> tail:
      CompactCatalog{ids, names} = known
      compact_catalog(tail, 1n+next, CompactCatalog{Index.set(Nat, ids, name, next), NatIndex.set(String, names, next, name)})

def compact_numbered_reference(found: Maybe<&2, Nat>, rest: List<&2, Nat>) -> List<&2, Nat>:
  match found:
    case None{}: rest
    case Some{identity}: identity <> rest

def compact_numbered_references(names: List<&2, String>, +ids: Map<&2, Nat>) -> List<&2, Nat>:
  match names:
    case Nil{}: Nil{}
    case name <> tail:
      compact_numbered_reference(Index.find(Nat, ids, name), compact_numbered_references(tail, ids))

def compact_reverse_edges(references: List<&2, Nat>, +identity: Nat, +reversed: NatIndex.Index<List<&2, Nat>>) -> NatIndex.Index<List<&2, Nat>>:
  match references:
    case Nil{}: reversed
    case +head <> tail:
      compact_reverse_edges(tail, identity, NatIndex.set(List<&2, Nat>, reversed, head, identity <> NatIndex.get(List<&2, Nat>, reversed, head, Nil{})))

type CompactGraph is Data:
  CompactGraph{order: List<&2, Nat>, forward: NatIndex.Index<List<&2, Nat>>, reverse: NatIndex.Index<List<&2, Nat>>, fuel: Nat}

def compact_graph(nodes: List<&2, Node>, +ids: Map<&2, Nat>, forward: NatIndex.Index<List<&2, Nat>>, reverse: NatIndex.Index<List<&2, Nat>>, fuel: Nat, order: List<&2, Nat>) -> CompactGraph:
  match nodes:
    case Nil{}:
      CompactGraph{List.reverse(&2, Nat, order), forward, reverse, fuel}
    case Node{name, +references, lambdas} <> tail:
      +identity = Index.get(Nat, ids, name, 0n)
      +targets = compact_numbered_references(references, ids)
      compact_graph(tail, ids, NatIndex.set(List<&2, Nat>, forward, identity, targets), compact_reverse_edges(targets, identity, reverse), Nat.add(2n+fuel, List.length(&2, String, references)), identity <> order)

type CompactVisit is Data:
  CompactEnter{identity: Nat}
  CompactLeave{identity: Nat}

def compact_enter(names: List<&2, Nat>, pending: List<&2, CompactVisit>) -> List<&2, CompactVisit>:
  match names:
    case Nil{}: pending
    case head <> tail: CompactEnter{head} <> compact_enter(tail, pending)

def compact_fresh(seen: NatIndex.Index<Unit>, identity: Nat) -> Bool:
  Bool.not(Maybe.is_some(&2, Unit, NatIndex.find(Unit, seen, identity)))

def compact_mark(fresh: Bool, seen: NatIndex.Index<Unit>, identity: Nat) -> NatIndex.Index<Unit>:
  match fresh:
    case False{}: seen
    case True{}: NatIndex.set(Unit, seen, identity, Unit{})

def compact_events(fresh: Bool, +identity: Nat, edges: NatIndex.Index<List<&2, Nat>>, tail: List<&2, CompactVisit>) -> List<&2, CompactVisit>:
  match fresh:
    case False{}: tail
    case True{}: compact_enter(NatIndex.get(List<&2, Nat>, edges, identity, Nil{}), CompactLeave{identity} <> tail)

def compact_finish(fuel: Nat, pending: List<&2, CompactVisit>, +edges: NatIndex.Index<List<&2, Nat>>, +seen: NatIndex.Index<Unit>, order: List<&2, Nat>) -> Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
  match fuel pending:
    case _ Nil{}: Done{order}
    case 0n _:
      Fail{M.Diagnostic{"internal_error", "inference", "dependency DFS exceeded its node/edge bound"}}
    case 1n+rest CompactEnter{+identity} <> tail:
      +unseen = compact_fresh(seen, identity)
      compact_finish(rest, compact_events(unseen, identity, edges, tail), edges, compact_mark(unseen, seen, identity), order)
    case 1n+rest CompactLeave{identity} <> tail:
      compact_finish(rest, tail, edges, seen, identity <> order)

type CompactReachability is Data:
  CompactReachability{seen: NatIndex.Index<Unit>, members: List<&2, Nat>}

def compact_reached_seen(found: CompactReachability) -> NatIndex.Index<Unit>:
  CompactReachability{seen, members} = found
  seen

def compact_reached_members(found: CompactReachability) -> List<&2, Nat>:
  CompactReachability{seen, members} = found
  members

def compact_pending(fresh: Bool, edges: NatIndex.Index<List<&2, Nat>>, identity: Nat, tail: List<&2, Nat>) -> List<&2, Nat>:
  match fresh:
    case False{}: tail
    case True{}: List.append(&2, Nat, NatIndex.get(List<&2, Nat>, edges, identity, Nil{}), tail)

def compact_reach(fuel: Nat, work: List<&2, Nat>, +edges: NatIndex.Index<List<&2, Nat>>, +seen: NatIndex.Index<Unit>, +members: List<&2, Nat>) -> Result<&2, &2, M.Diagnostic, CompactReachability>:
  match fuel work:
    case _ Nil{}: Done{CompactReachability{seen, members}}
    case 0n _:
      Fail{M.Diagnostic{"internal_error", "inference", "dependency component exceeded its node/edge bound"}}
    case 1n+rest +identity <> tail:
      +unseen = compact_fresh(seen, identity)
      compact_reach(rest, compact_pending(unseen, edges, identity, tail), edges, compact_mark(unseen, seen, identity), Bool.pick(List<&2, Nat>, unseen, identity <> members, members))

def compact_names(members: List<&2, Nat>, +catalog: NatIndex.Index<String>) -> List<&2, String>:
  match members:
    case Nil{}: Nil{}
    case identity <> tail:
      NatIndex.get(String, catalog, identity, "") <> compact_names(tail, catalog)

def compact_prepend(members: List<&2, Nat>, rest: List<&2, List<&2, String>>, catalog: NatIndex.Index<String>) -> List<&2, List<&2, String>>:
  match members:
    case Nil{}: rest
    case head <> tail: compact_names(head <> tail, catalog) <> rest

def compact_collect(order: List<&2, Nat>, +edges: NatIndex.Index<List<&2, Nat>>, seen: NatIndex.Index<Unit>, +fuel: Nat, +catalog: NatIndex.Index<String>) -> Result<&2, &2, M.Diagnostic, List<&2, List<&2, String>>>:
  match order:
    case Nil{}: Done{Nil{}}
    case head <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, List<&2, String>>>:
        +reached : CompactReachability <- compact_reach(fuel, [head], edges, seen, Nil{})
        rest : List<&2, List<&2, String>> <- compact_collect(tail, edges, compact_reached_seen(reached), fuel, catalog)
        return compact_prepend(compact_reached_members(reached), rest, catalog)

def compact_components_graph(graph: CompactGraph, catalog: NatIndex.Index<String>) -> Result<&2, &2, M.Diagnostic, List<&2, List<&2, String>>>:
  CompactGraph{order, forward, reverse, +fuel} = graph
  do Result<&2, &2, M.Diagnostic, List<&2, List<&2, String>>>:
    finished : List<&2, Nat> <- compact_finish(fuel, compact_enter(order, Nil{}), reverse, NatIndex.Empty{}, Nil{})
    compact_collect(finished, forward, NatIndex.Empty{}, fuel, catalog)

def compact_components_catalog(nodes: List<&2, Node>, known: CompactCatalog) -> Result<&2, &2, M.Diagnostic, List<&2, List<&2, String>>>:
  CompactCatalog{ids, names} = known
  compact_components_graph(compact_graph(nodes, ids, NatIndex.Empty{}, NatIndex.Empty{}, 1n, Nil{}), names)

def components(+nodes: List<&2, Node>) -> Result<&2, &2, M.Diagnostic, List<&2, List<&2, String>>>:
  match nodes:
    case Nil{}: Done{Nil{}}
    case Node{name, references, lambdas} <> Nil{}: Done{[name <> Nil{}]}
    case head <> tail:
      compact_components_catalog(nodes, compact_catalog(head <> tail, 0n, CompactCatalog{MTip{}, NatIndex.Empty{}}))
