import Base
import ./model.bend as M
import ./closures.bend as F
import ./monomorph.bend as Mono
import ./index.bend as Index

# A known function may consume several arguments before doing any work: its
# leading bodies are literal lambdas. Fully supplied calls can bind those
# arguments directly instead of constructing and immediately calling closures.
# Definitions with work between stages and genuine partial applications retain
# their ordinary evaluation path.
type Definition is Data:
  Definition{key: String, parameters: List<&2, String>, body: M.Expr}

type Application is Data:
  Application{head: M.Expr, arguments: List<&2, M.Expr>}

type Candidate is Data:
  Candidate{definition: Definition, arguments: List<&2, M.Expr>}

type Edited is Data:
  Edited{expressions: List<&2, M.Expr>, budget: Nat, serial: Nat}

type Work is Data:
  Expression{expression: M.Expr}
  Expressions{expressions: List<&2, M.Expr>, reversed: List<&2, M.Expr>}
  Attempt{original: M.Expr, candidate: Maybe<&2, Candidate>}
  Expand{original: M.Expr, candidate: Candidate, cost: Nat, allowed: Bool}

def empty() -> Map<&2, Maybe<&2, Definition>>:
  Map.new(&2, Maybe<&2, Definition>)

def definition(fuel: Nat, key: String, expression: M.Expr, reversed: List<&2, String>) -> Maybe<&2, Definition>:
  match fuel expression:
    case 0n _:
      None{}
    case 1n+rest M.SourceExpr{offset, annotation, body}:
      definition(rest, key, body, reversed)
    case 1n+rest M.LambdaExpr{identity, parameter, p, r, body}:
      definition(rest, key, body, parameter <> reversed)
    case _ body:
      Some{Definition{key, List.reverse(&2, String, reversed), body}}

def definitions(functions: List<&2, M.CheckedFunction>, indexed: Map<&2, Maybe<&2, Definition>>) -> Map<&2, Maybe<&2, Definition>>:
  match functions:
    case Nil{}:
      indexed
    case M.CheckedFunction{M.Function{+name, exported, parameter, p, r, body}, signature, effects} <> tail:
      definitions(tail, Map.set(&2, Maybe<&2, Definition>, indexed, name, definition(256n, "fn:" ++ name, body, [parameter])))

def application(fuel: Nat, expression: M.Expr, arguments: List<&2, M.Expr>) -> Application:
  match fuel expression:
    case 1n+rest M.SourceExpr{offset, annotation, body}:
      application(rest, body, arguments)
    case 1n+rest M.InstantiationExpr{site, value}:
      application(rest, value, arguments)
    case 1n+rest M.ApplyExpr{callee, argument}:
      application(rest, callee, argument <> arguments)
    case 1n+rest M.CallExpr{name, argument}:
      Application{M.FunctionExpr{name}, argument <> arguments}
    case _ head:
      Application{head, arguments}

def resolved(head: M.Expr, known: Map<&2, Maybe<&2, Definition>>) -> Maybe<&2, Definition>:
  match head:
    case M.FunctionExpr{name}:
      Index.get(Maybe<&2, Definition>, known, name, None{})
    case M.LambdaExpr{+identity, parameter, p, r, body}:
      definition(256n, "lambda:" ++ Nat.show(identity), body, [parameter])
    case _:
      None{}

def arity_match(found: Maybe<&2, Definition>, +arguments: List<&2, M.Expr>) -> Maybe<&2, Candidate>:
  match found:
    case None{}:
      None{}
    case Some{Definition{key, +parameters, body}}:
      +count = List.length(&2, String, parameters)
      Bool.pick(Maybe<&2, Candidate>, Bool.and(Nat.is_ge(count, 2n), Nat.is_eq(count, List.length(&2, M.Expr, arguments))), Some{Candidate{Definition{key, parameters, body}, arguments}}, None{})

def candidate(chain: Application, known: Map<&2, Maybe<&2, Definition>>) -> Maybe<&2, Candidate>:
  Application{head, arguments} = chain
  arity_match(resolved(head, known), arguments)

# Count executable body nodes, ignoring source annotations and nested lambda
# bodies (which have their own jobs). Keep loops in their original instruction
# jobs: compaction is context-sensitive, and ownership scans rely on the
# original loop bindings remaining distinct. A body over 96 nodes keeps its call.
def body_cost(fuel: Nat, pending: List<&2, M.Expr>, count: Nat) -> Nat:
  match fuel pending:
    case _ Nil{}:
      count
    case 0n _:
      97n
    case 1n+rest M.SourceExpr{offset, annotation, body} <> tail:
      body_cost(rest, body <> tail, count)
    case 1n+rest M.ForeverExpr{state, initial, body} <> tail:
      97n
    case 1n+rest M.ForExpr{index, start, end, state, initial, body} <> tail:
      97n
    case 1n+rest M.LambdaExpr{identity, parameter, p, r, body} <> tail:
      body_cost(rest, tail, 1n+count)
    case 1n+rest head <> tail:
      body_cost(rest, List.append(&2, M.Expr, F.children(head), tail), 1n+count)

def eligible(item: Candidate, +cost: Nat, budget: Nat, active: Set()) -> Bool:
  Candidate{Definition{key, parameters, body}, arguments} = item
  Bool.and(Nat.is_le(cost, 96n), Bool.and(Nat.is_le(cost, budget), Bool.not(Maybe.is_some(&2, Unit, Index.find(Unit, active, key)))))

def candidate_cost(item: Candidate) -> Nat:
  Candidate{Definition{key, parameters, body}, arguments} = item
  # Each parameter adds an argument Let, a parameter Let, and a Local read.
  Nat.add(body_cost(256n, [body], 0n), Nat.mul(3n, List.length(&2, String, parameters)))

def expressions(edited: Edited) -> List<&2, M.Expr>:
  Edited{values, budget, serial} = edited
  values

def remaining(edited: Edited) -> Nat:
  Edited{values, budget, serial} = edited
  budget

def next_serial(edited: Edited) -> Nat:
  Edited{values, budget, serial} = edited
  serial

def one(values: List<&2, M.Expr>) -> Result<&2, &2, M.Diagnostic, M.Expr>:
  match values:
    case value <> Nil{}:
      Done{value}
    case _:
      Fail{M.Diagnostic{"internal_error", "saturated call", "saturation traversal lost an expression child"}}

def temporary(serial: Nat, index: Nat) -> String:
  "$codegen.saturated[" ++ Nat.show(serial) ++ "].arg[" ++ Nat.show(index) ++ "]"

def bind_parameters(parameters: List<&2, String>, +serial: Nat, +index: Nat, body: M.Expr) -> M.Expr:
  match parameters:
    case Nil{}:
      body
    case parameter <> tail:
      M.LetExpr{parameter, M.LocalExpr{temporary(serial, index)}, bind_parameters(tail, serial, 1n+index, body)}

def bind_arguments(arguments: List<&2, M.Expr>, +serial: Nat, +index: Nat, body: M.Expr) -> M.Expr:
  match arguments:
    case Nil{}:
      body
    case argument <> tail:
      M.LetExpr{temporary(serial, index), argument, bind_arguments(tail, serial, 1n+index, body)}

# A statically known unary application already has a direct ABI entry. This
# also handles the first stage of partial applications without allocating a
# closure for the function itself; the returned closure is still preserved.
def direct_head(fuel: Nat, head: M.Expr, argument: M.Expr) -> M.Expr:
  match fuel head:
    case 1n+rest M.SourceExpr{offset, annotation, body}:
      direct_head(rest, body, argument)
    case _ M.FunctionExpr{name}:
      M.CallExpr{name, argument}
    case _ value:
      M.ApplyExpr{value, argument}

def direct(expression: M.Expr) -> M.Expr:
  match expression:
    case M.ApplyExpr{head, argument}:
      direct_head(256n, head, argument)
    case other:
      other

def rewrite(+fuel: Nat, work: Work, +known: Map<&2, Maybe<&2, Definition>>, +active: Set(), +budget: Nat, +serial: Nat) -> Result<&2, &2, M.Diagnostic, Edited>:
  match fuel work:
    case 0n _:
      Fail{M.Diagnostic{"backend_limit", "saturated call", "saturation traversal exceeded its structural limit"}}
    case 1n+rest Expression{M.SourceExpr{offset, annotation, value}}:
      # Projection still needs explicit flat-array annotations for loop carry
      # safety. Keep wrappers until that analysis consumes them.
      do Result<&2, &2, M.Diagnostic, Edited>:
        +child : Edited <- rewrite(rest, Expression{value}, known, active, budget, serial)
        prepared : M.Expr <- one(expressions(child))
        return Edited{[M.SourceExpr{offset, annotation, prepared}], remaining(child), next_serial(child)}
    case 1n+rest Expression{M.LambdaExpr{identity, parameter, p, r, body}}:
      Done{Edited{[M.LambdaExpr{identity, parameter, p, r, body}], budget, serial}}
    case 1n+rest Expression{+expression}:
      rewrite(rest, Attempt{expression, candidate(application(256n, expression, Nil{}), known)}, known, active, budget, serial)
    case 1n+rest Attempt{original, Some{+item}}:
      +cost = candidate_cost(item)
      rewrite(rest, Expand{original, item, cost, eligible(item, cost, budget, active)}, known, active, budget, serial)
    case 1n+rest Expand{original, Candidate{Definition{+key, parameters, body}, arguments}, +cost, True{}}:
      do Result<&2, &2, M.Diagnostic, Edited>:
        +values : Edited <- rewrite(rest, Expressions{arguments, Nil{}}, known, active, Nat.sub(budget, cost), serial)
        +call_serial : Nat = next_serial(values)
        +expanded : Edited <- rewrite(rest, Expression{body}, known, Set.add(active, key), remaining(values), 1n+call_serial)
        final : M.Expr <- one(expressions(expanded))
        return Edited{[bind_arguments(expressions(values), call_serial, 0n, bind_parameters(parameters, call_serial, 0n, final))], remaining(expanded), next_serial(expanded)}
    case 1n+rest Expand{original, candidate, cost, False{}}:
      rewrite(rest, Attempt{original, None{}}, known, active, budget, serial)
    case 1n+rest Attempt{+original, None{}}:
      do Result<&2, &2, M.Diagnostic, Edited>:
        +children : Edited <- rewrite(rest, Expressions{F.children(original), Nil{}}, known, active, budget, serial)
        rebuilt : M.Expr <- Mono.rebuild(original, expressions(children), 0n)
        return Edited{[direct(rebuilt)], remaining(children), next_serial(children)}
    case 1n+rest Expressions{Nil{}, reversed}:
      Done{Edited{List.reverse(&2, M.Expr, reversed), budget, serial}}
    case 1n+rest Expressions{head <> tail, reversed}:
      do Result<&2, &2, M.Diagnostic, Edited>:
        +first : Edited <- rewrite(rest, Expression{head}, known, active, budget, serial)
        prepared : M.Expr <- one(expressions(first))
        rewrite(rest, Expressions{tail, prepared <> reversed}, known, active, remaining(first), next_serial(first))

def prepare(expression: M.Expr, known: Map<&2, Maybe<&2, Definition>>) -> Result<&2, &2, M.Diagnostic, M.Expr>:
  do Result<&2, &2, M.Diagnostic, M.Expr>:
    result : Edited <- rewrite(65536n, Expression{expression}, known, Set.new(), 2048n, 0n)
    one(expressions(result))
