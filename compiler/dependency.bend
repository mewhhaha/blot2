import Base
import ./model.bend as M
import ./index.bend as Index

type Node is Data:
  Node{name: String, references: List<&2, String>, lambdas: List<&2, Nat>}

type Work is Data:
  Expression{value: M.Expr}
  Arms{values: List<&2, M.MatchArm<M.Expr>>}

type References is Data:
  References{names: List<&2, String>, lambdas: List<&2, Nat>}

def names_of(refs: References) -> List<&2, String>:
  References{names, lambdas} = refs
  names

def lambdas_of(refs: References) -> List<&2, Nat>:
  References{names, lambdas} = refs
  lambdas

def combine(a: References, b: References) -> References:
  References{an, al} = a
  References{bn, bl} = b
  References{List.append(&2, String, an, bn), List.append(&2, Nat, al, bl)}

def payload_expression(payload: Maybe<&2, M.Expr>) -> M.Expr:
  match payload:
    case None{}:
      M.UnitExpr{}
    case Some{value}:
      value

def references(+fuel: Nat, work: Work) -> Result<&2, &2, M.Diagnostic, References>:
  match fuel work:
    case 0n _:
      Fail{M.Diagnostic{"expression_complexity", "inference", "expression nesting exceeds compiler traversal limit"}}
    case 1n+rest Expression{M.ConstantExpr{name}}:
      Done{References{[name], Nil{}}}
    case 1n+rest Expression{M.FunctionExpr{name}}:
      Done{References{[name], Nil{}}}
    case 1n+rest Expression{M.CallExpr{callee, argument}}:
      do Result<&2, &2, M.Diagnostic, References>:
        refs : References <- references(rest, Expression{argument})
        return combine(References{[callee], Nil{}}, refs)
    case 1n+rest Expression{M.LambdaExpr{identity, parameter, p, r, body}}:
      do Result<&2, &2, M.Diagnostic, References>:
        refs : References <- references(rest, Expression{body})
        return combine(References{Nil{}, [identity]}, refs)
    case 1n+rest Expression{M.ApplyExpr{callee, argument}}:
      do Result<&2, &2, M.Diagnostic, References>:
        a : References <- references(rest, Expression{callee})
        b : References <- references(rest, Expression{argument})
        return combine(a, b)
    case 1n+rest Expression{M.ScalarExpr{operator, left, right}}:
      do Result<&2, &2, M.Diagnostic, References>:
        a : References <- references(rest, Expression{left})
        b : References <- references(rest, Expression{right})
        return combine(a, b)
    case 1n+rest Expression{M.LetExpr{name, value, body}}:
      do Result<&2, &2, M.Diagnostic, References>:
        a : References <- references(rest, Expression{value})
        b : References <- references(rest, Expression{body})
        return combine(a, b)
    case 1n+rest Expression{M.UseExpr{name, value, body}}:
      do Result<&2, &2, M.Diagnostic, References>:
        a : References <- references(rest, Expression{value})
        b : References <- references(rest, Expression{body})
        return combine(a, b)
    case 1n+rest Expression{M.IfExpr{condition, consequent, alternative}}:
      do Result<&2, &2, M.Diagnostic, References>:
        a : References <- references(rest, Expression{condition})
        b : References <- references(rest, Expression{consequent})
        c : References <- references(rest, Expression{alternative})
        return combine(a, combine(b, c))
    case 1n+rest Expression{M.SequenceExpr{first, next}}:
      do Result<&2, &2, M.Diagnostic, References>:
        a : References <- references(rest, Expression{first})
        b : References <- references(rest, Expression{next})
        return combine(a, b)
    case 1n+rest Expression{M.MatchExpr{value, arms}}:
      do Result<&2, &2, M.Diagnostic, References>:
        a : References <- references(rest, Expression{value})
        b : References <- references(rest, Arms{arms})
        return combine(a, b)
    case 1n+rest Expression{M.GuardExpr{pattern, value, alternative, body}}:
      do Result<&2, &2, M.Diagnostic, References>:
        a : References <- references(rest, Expression{value})
        b : References <- references(rest, Expression{alternative})
        c : References <- references(rest, Expression{body})
        return combine(a, combine(b, c))
    case 1n+rest Expression{M.ConstructExpr{constructor, payload}}:
      references(rest, Expression{payload_expression(payload)})
    case 1n+rest Expression{M.BlockExpr{label, body}}:
      references(rest, Expression{body})
    case 1n+rest Expression{M.ReturnExpr{label, value}}:
      references(rest, Expression{value})
    case 1n+rest Expression{M.SourceExpr{offset, annotation, value}}:
      references(rest, Expression{value})
    case 1n+rest Expression{M.WriteExpr{value}}:
      references(rest, Expression{value})
    case 1n+rest Expression{M.InsertExpr{value}}:
      references(rest, Expression{value})
    case 1n+rest Expression{other}:
      Done{References{Nil{}, Nil{}}}
    case 1n+rest Arms{Nil{}}:
      Done{References{Nil{}, Nil{}}}
    case 1n+rest Arms{M.MatchArm{pattern, body} <> tail}:
      do Result<&2, &2, M.Diagnostic, References>:
        a : References <- references(rest, Expression{body})
        b : References <- references(rest, Arms{tail})
        return combine(a, b)

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

def contains(names: List<&2, String>, +name: String) -> Bool:
  match names:
    case Nil{}:
      False{}
    case head <> tail:
      Bool.or(M.name_equal(head, name), contains(tail, name))

def lookup(nodes: List<&2, Node>, +name: String) -> List<&2, String>:
  match nodes:
    case Nil{}:
      Nil{}
    case Node{found, +refs, lambdas} <> tail:
      Bool.pick(List<&2, String>, M.name_equal(found, name), refs, lookup(tail, name))

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
      adjacency(tail, Map.set(&2, List<&2, String>, edges, name, refs))

def neighbors(edges: Map<&2, List<&2, String>>, name: String) -> List<&2, String>:
  Index.get(List<&2, String>, edges, name, Nil{})

def transpose_edges(refs: List<&2, String>, +name: String, +edges: Map<&2, List<&2, String>>) -> Map<&2, List<&2, String>>:
  match refs:
    case Nil{}:
      edges
    case +head <> tail:
      transpose_edges(tail, name, Map.set(&2, List<&2, String>, edges, head, name <> neighbors(edges, head)))

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

def finish_order(fuel: Nat, pending: List<&2, Visit>, +edges: Map<&2, List<&2, String>>, +known: Set(), +seen: Set(), order: List<&2, String>) -> Result<&2, &2, M.Diagnostic, List<&2, String>>:
  match fuel pending:
    case _ Nil{}:
      Done{order}
    case 0n _:
      Fail{M.Diagnostic{"internal_error", "inference", "dependency DFS exceeded its node/edge bound"}}
    case 1n+rest Enter{+name} <> tail:
      +fresh = Bool.and(member(known, name), Bool.not(member(seen, name)))
      finish_order(rest, visit_events(fresh, name, neighbors(edges, name), tail), edges, known, mark(fresh, seen, name), order)
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

def reachable(fuel: Nat, pending: List<&2, String>, +edges: Map<&2, List<&2, String>>, +known: Set(), +seen: Set(), +members: List<&2, String>) -> Result<&2, &2, M.Diagnostic, Reachability>:
  match fuel pending:
    case _ Nil{}:
      Done{Reachability{seen, members}}
    case 0n _:
      Fail{M.Diagnostic{"internal_error", "inference", "dependency component exceeded its node/edge bound"}}
    case 1n+rest +head <> tail:
      +fresh = Bool.and(member(known, head), Bool.not(member(seen, head)))
      reachable(rest, next_work(Bool.not(fresh), neighbors(edges, head), tail), edges, known, mark(fresh, seen, head), Bool.pick(List<&2, String>, fresh, head <> members, members))

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

# Kosaraju runs once per module. Visiting the transpose first orders the
# resulting original-graph components dependency-first, ready for HM schemes.
# Unknown references are ignored by graph traversal, then diagnosed by inference.
def components(+nodes: List<&2, Node>) -> Result<&2, &2, M.Diagnostic, List<&2, List<&2, String>>>:
  +names = node_names(nodes)
  +known = Set.from_list(names)
  +fuel = {1n+Nat.add(Nat.mul(2n, List.length(&2, String, names)), edge_count(nodes)) : Nat}
  do Result<&2, &2, M.Diagnostic, List<&2, List<&2, String>>>:
    order : List<&2, String> <- finish_order(fuel, enter_events(names, Nil{}), transpose(nodes, Map.new(&2, List<&2, String>)), known, Set.new(), Nil{})
    collect_components(order, adjacency(nodes, Map.new(&2, List<&2, String>)), known, Set.new(), fuel)
