import Base
import ./model.bend as M
import ./codegen_ir.bend as I
import ./index.bend as Index

# Reuse is local to an instruction job. Parameters, captured values, projections,
# constants, and unknown calls never confer ownership of an array allocation.
def arm_bodies(arms: List<&2, M.MatchArm<I.Expr>>) -> List<&2, I.Expr>:
  match arms:
    case Nil{}:
      Nil{}
    case M.MatchArm{patterns, body} <> tail:
      body <> arm_bodies(tail)

def children(expression: I.Expr) -> List<&2, I.Expr>:
  match expression:
    case I.ConstructExpr{constructor, Some{payload}}:
      [payload]
    case I.ApplyExpr{callee, argument}:
      [callee, argument]
    case I.CallExpr{key, argument}:
      [argument]
    case I.ScalarExpr{operator, left, right}:
      [left, right]
    case I.LetExpr{name, value, body}:
      [value, body]
    case I.IfExpr{condition, consequent, alternative}:
      [condition, consequent, alternative]
    case I.SequenceExpr{first, next}:
      [first, next]
    case I.GuardExpr{pattern, value, alternative, body}:
      [value, alternative, body]
    case I.BlockExpr{label, body}:
      [body]
    case I.ReturnExpr{label, value}:
      [value]
    case I.UnaryExpr{operator, value}:
      [value]
    case I.ProviderExpr{identity, implementation}:
      [implementation]
    case I.StateProviderExpr{read, write, initial}:
      [initial]
    case I.HandleExpr{provider, body}:
      [provider, body]
    case I.InvokeOperationExpr{identity, argument}:
      [argument]
    case I.ProjectExpr{value, index}:
      [value]
    case I.ForExpr{index, start, end, state, initial, body}:
      [start, end, initial, body]
    case I.ArrayGenerateExpr{count, generator}:
      [count, generator]
    case I.ArrayFillExpr{count, value}:
      [count, value]
    case I.ArrayGetExpr{array, index}:
      [array, index]
    case I.ArraySetExpr{array, index, value}:
      [array, index, value]
    case I.ArrayReuseExpr{array, index, value}:
      [array, index, value]
    case I.ArrayLengthExpr{array}:
      [array]
    case I.MatchExpr{values, arms}:
      List.append(&2, I.Expr, values, arm_bodies(arms))
    case I.ArrayExpr{elements}:
      elements
    case I.ProductExpr{elements}:
      elements
    case _:
      Nil{}

def invalid() -> M.Diagnostic:
  M.Diagnostic{"internal_error", "array ownership", "ownership traversal lost an expression child"}

def one(expressions: List<&2, I.Expr>) -> Result<&2, &2, M.Diagnostic, I.Expr>:
  match expressions:
    case expression <> Nil{}:
      Done{expression}
    case _:
      Fail{invalid()}

def rebuild_arms(arms: List<&2, M.MatchArm<I.Expr>>, bodies: List<&2, I.Expr>) -> Result<&2, &2, M.Diagnostic, List<&2, M.MatchArm<I.Expr>>>:
  match arms bodies:
    case Nil{} Nil{}:
      Done{Nil{}}
    case M.MatchArm{patterns, body} <> tail first <> rest:
      do Result<&2, &2, M.Diagnostic, List<&2, M.MatchArm<I.Expr>>>:
        next : List<&2, M.MatchArm<I.Expr>> <- rebuild_arms(tail, rest)
        return M.MatchArm{patterns, first} <> next
    case _ _:
      Fail{invalid()}

def rebuild(original: I.Expr, children: List<&2, I.Expr>) -> Result<&2, &2, M.Diagnostic, I.Expr>:
  match original children:
    case I.ConstructExpr{constructor, Some{payload}} payload_new <> Nil{}:
      Done{I.ConstructExpr{constructor, Some{payload_new}}}
    case I.ApplyExpr{callee, argument} callee_new <> argument_new <> Nil{}:
      Done{I.ApplyExpr{callee_new, argument_new}}
    case I.CallExpr{key, argument} argument_new <> Nil{}:
      Done{I.CallExpr{key, argument_new}}
    case I.ScalarExpr{operator, left, right} left_new <> right_new <> Nil{}:
      Done{I.ScalarExpr{operator, left_new, right_new}}
    case I.LetExpr{name, value, body} value_new <> body_new <> Nil{}:
      Done{I.LetExpr{name, value_new, body_new}}
    case I.IfExpr{condition, consequent, alternative} condition_new <> consequent_new <> alternative_new <> Nil{}:
      Done{I.IfExpr{condition_new, consequent_new, alternative_new}}
    case I.SequenceExpr{first, next} first_new <> next_new <> Nil{}:
      Done{I.SequenceExpr{first_new, next_new}}
    case I.GuardExpr{pattern, value, alternative, body} value_new <> alternative_new <> body_new <> Nil{}:
      Done{I.GuardExpr{pattern, value_new, alternative_new, body_new}}
    case I.BlockExpr{label, body} body_new <> Nil{}:
      Done{I.BlockExpr{label, body_new}}
    case I.ReturnExpr{label, value} value_new <> Nil{}:
      Done{I.ReturnExpr{label, value_new}}
    case I.UnaryExpr{operator, value} value_new <> Nil{}:
      Done{I.UnaryExpr{operator, value_new}}
    case I.ProviderExpr{identity, implementation} implementation_new <> Nil{}:
      Done{I.ProviderExpr{identity, implementation_new}}
    case I.StateProviderExpr{read, write, initial} initial_new <> Nil{}:
      Done{I.StateProviderExpr{read, write, initial_new}}
    case I.HandleExpr{provider, body} provider_new <> body_new <> Nil{}:
      Done{I.HandleExpr{provider_new, body_new}}
    case I.InvokeOperationExpr{identity, argument} argument_new <> Nil{}:
      Done{I.InvokeOperationExpr{identity, argument_new}}
    case I.ProjectExpr{value, index} value_new <> Nil{}:
      Done{I.ProjectExpr{value_new, index}}
    case I.ForExpr{index, start, end, state, initial, body} start_new <> end_new <> initial_new <> body_new <> Nil{}:
      Done{I.ForExpr{index, start_new, end_new, state, initial_new, body_new}}
    case I.ArrayGenerateExpr{count, generator} count_new <> generator_new <> Nil{}:
      Done{I.ArrayGenerateExpr{count_new, generator_new}}
    case I.ArrayFillExpr{count, value} count_new <> value_new <> Nil{}:
      Done{I.ArrayFillExpr{count_new, value_new}}
    case I.ArrayGetExpr{array, index} array_new <> index_new <> Nil{}:
      Done{I.ArrayGetExpr{array_new, index_new}}
    case I.ArraySetExpr{array, index, value} array_new <> index_new <> value_new <> Nil{}:
      Done{I.ArraySetExpr{array_new, index_new, value_new}}
    case I.ArrayReuseExpr{array, index, value} array_new <> index_new <> value_new <> Nil{}:
      Done{I.ArrayReuseExpr{array_new, index_new, value_new}}
    case I.ArrayLengthExpr{array} array_new <> Nil{}:
      Done{I.ArrayLengthExpr{array_new}}
    case I.MatchExpr{values, arms} +children:
      +count = List.length(&2, I.Expr, values)
      do Result<&2, &2, M.Diagnostic, I.Expr>:
        branches : List<&2, M.MatchArm<I.Expr>> <- rebuild_arms(arms, List.drop(&2, I.Expr, children, count))
        return I.MatchExpr{List.take(&2, I.Expr, children, count), branches}
    case I.ArrayExpr{old} elements:
      Done{I.ArrayExpr{elements}}
    case I.ProductExpr{old} elements:
      Done{I.ProductExpr{elements}}
    case original Nil{}:
      Done{original}
    case _ _:
      Fail{invalid()}

type Usage is Data:
  Usage{escapes: Nat, last: Nat}

def reference_count(usage: Usage, name: String, borrowed: Bool, position: Nat, usages: Map<&2, Usage>) -> Map<&2, Usage>:
  Usage{escapes, last} = usage
  Map.set(&2, Usage, usages, name, Usage{Nat.add(escapes, Bool.pick(Nat, borrowed, 0n, 1n)), position})

def reference(+name: String, borrowed: Bool, position: Nat, +usages: Map<&2, Usage>) -> Map<&2, Usage>:
  reference_count(Index.get(Usage, usages, name, Usage{0n, 0n}), name, borrowed, position, usages)

def captures(names: List<&2, String>, +position: Nat, usages: Map<&2, Usage>) -> Map<&2, Usage>:
  match names:
    case Nil{}:
      usages
    case name <> tail:
      captures(tail, position, reference(name, False{}, position, usages))

type Scan is Data:
  Scan{expression: I.Expr, borrowed: Bool}
  ScanExpressions{expressions: List<&2, I.Expr>}

def scan(fuel: Nat, pending: List<&2, Scan>, usages: Map<&2, Usage>, +position: Nat) -> Result<&2, &2, M.Diagnostic, Map<&2, Usage>>:
  match fuel pending:
    case _ Nil{}:
      Done{usages}
    case 0n _:
      Fail{M.Diagnostic{"backend_limit", "array ownership", "ownership scan exceeded its structural limit"}}
    case 1n+rest Scan{I.LocalExpr{name}, borrowed} <> tail:
      scan(rest, tail, reference(name, borrowed, position, usages), 1n+position)
    case 1n+rest Scan{I.ClosureExpr{key, names}, borrowed} <> tail:
      scan(rest, tail, captures(names, position, usages), 1n+position)
    case 1n+rest Scan{I.ArrayGetExpr{array, index}, borrowed} <> tail:
      scan(rest, Scan{array, True{}} <> Scan{index, False{}} <> tail, usages, 1n+position)
    case 1n+rest Scan{I.ArrayLengthExpr{array}, borrowed} <> tail:
      scan(rest, Scan{array, True{}} <> tail, usages, 1n+position)
    case 1n+rest Scan{expression, borrowed} <> tail:
      scan(rest, ScanExpressions{children(expression)} <> tail, usages, 1n+position)
    case 1n+rest ScanExpressions{Nil{}} <> tail:
      scan(rest, tail, usages, position)
    case 1n+rest ScanExpressions{head <> following} <> tail:
      scan(rest, Scan{head, False{}} <> ScanExpressions{following} <> tail, usages, position)

def consumed(usage: Usage, end: Nat) -> Bool:
  Usage{escapes, last} = usage
  Bool.and(Nat.is_eq(escapes, 1n), Nat.is_lt(last, end))

def transferable(+name: String, owned: Map<&2, Bool>, usages: Map<&2, Usage>, end: Nat) -> Bool:
  Bool.and(Index.get(Bool, owned, name, False{}), consumed(Index.get(Usage, usages, name, Usage{0n, 0n}), end))

type Edited is Data:
  Edited{expressions: List<&2, I.Expr>, owned: Bool, next: Nat}

def expressions(result: Edited) -> List<&2, I.Expr>:
  Edited{expressions, owned, next} = result
  expressions

def owned(result: Edited) -> Bool:
  Edited{expressions, owned, next} = result
  owned

def next(result: Edited) -> Nat:
  Edited{expressions, owned, next} = result
  next

def reusable(original: I.Expr, inferred: Bool, ownership: Map<&2, Bool>, usages: Map<&2, Usage>, end: Nat) -> Bool:
  match original:
    case I.LocalExpr{name}:
      transferable(name, ownership, usages, end)
    case _:
      inferred

def update(reuse: Bool, array: I.Expr, index: I.Expr, value: I.Expr) -> I.Expr:
  match reuse:
    case True{}:
      I.ArrayReuseExpr{array, index, value}
    case False{}:
      I.ArraySetExpr{array, index, value}

def fresh(expression: I.Expr, ownership: Map<&2, Bool>, usages: Map<&2, Usage>, end: Nat) -> Bool:
  match expression:
    case I.ArrayExpr{elements}:
      True{}
    case I.ArrayFillExpr{count, value}:
      True{}
    case I.ArrayGenerateExpr{count, generator}:
      True{}
    case I.LocalExpr{name}:
      transferable(name, ownership, usages, end)
    case _:
      False{}

def branch_scope(expression: I.Expr, ownership: Map<&2, Bool>) -> Map<&2, Bool>:
  match expression:
    case I.MatchExpr{values, arms}:
      Map.new(&2, Bool)
    case I.GuardExpr{pattern, value, alternative, body}:
      Map.new(&2, Bool)
    case _:
      ownership

type Work is Data:
  Expression{expression: I.Expr}
  Expressions{expressions: List<&2, I.Expr>, reversed: List<&2, I.Expr>}

def rewrite(fuel: Nat, work: Work, +ownership: Map<&2, Bool>, +usages: Map<&2, Usage>, position: Nat) -> Result<&2, &2, M.Diagnostic, Edited>:
  match fuel work:
    case 0n _:
      Fail{M.Diagnostic{"backend_limit", "array ownership", "ownership rewrite exceeded its structural limit"}}
    case 1n+ +rest Expression{I.LetExpr{+name, value, body}}:
      do Result<&2, &2, M.Diagnostic, Edited>:
        +v : Edited <- rewrite(rest, Expression{value}, ownership, usages, 1n+position)
        value : I.Expr <- one(expressions(v))
        +b : Edited <- rewrite(rest, Expression{body}, Map.set(&2, Bool, ownership, name, owned(v)), usages, next(v))
        body : I.Expr <- one(expressions(b))
        return Edited{[I.LetExpr{name, value, body}], owned(b), next(b)}
    case 1n+ +rest Expression{I.ForExpr{index, start, end, +state, initial, body}}:
      do Result<&2, &2, M.Diagnostic, Edited>:
        +s : Edited <- rewrite(rest, Expression{start}, ownership, usages, 1n+position)
        start : I.Expr <- one(expressions(s))
        +e : Edited <- rewrite(rest, Expression{end}, ownership, usages, next(s))
        end : I.Expr <- one(expressions(e))
        +i : Edited <- rewrite(rest, Expression{initial}, ownership, usages, next(e))
        initial : I.Expr <- one(expressions(i))
        +b : Edited <- rewrite(rest, Expression{body}, Map.set(&2, Bool, Map.new(&2, Bool), state, owned(i)), usages, next(i))
        body : I.Expr <- one(expressions(b))
        return Edited{[I.ForExpr{index, start, end, state, initial, body}], Bool.and(owned(i), owned(b)), next(b)}
    case 1n+ +rest Expression{I.ArraySetExpr{+array, index, value}}:
      do Result<&2, &2, M.Diagnostic, Edited>:
        +a : Edited <- rewrite(rest, Expression{array}, ownership, usages, 1n+position)
        prepared_array : I.Expr <- one(expressions(a))
        +i : Edited <- rewrite(rest, Expression{index}, ownership, usages, next(a))
        index : I.Expr <- one(expressions(i))
        +v : Edited <- rewrite(rest, Expression{value}, ownership, usages, next(i))
        value : I.Expr <- one(expressions(v))
        return Edited{[update(reusable(array, owned(a), ownership, usages, next(v)), prepared_array, index, value)], True{}, next(v)}
    case 1n+ +rest Expression{I.SequenceExpr{first, following}}:
      do Result<&2, &2, M.Diagnostic, Edited>:
        +a : Edited <- rewrite(rest, Expression{first}, ownership, usages, 1n+position)
        first : I.Expr <- one(expressions(a))
        +b : Edited <- rewrite(rest, Expression{following}, ownership, usages, next(a))
        following : I.Expr <- one(expressions(b))
        return Edited{[I.SequenceExpr{first, following}], owned(b), next(b)}
    case 1n+ +rest Expression{+expression}:
      do Result<&2, &2, M.Diagnostic, Edited>:
        +c : Edited <- rewrite(rest, Expressions{children(expression), Nil{}}, branch_scope(expression, ownership), usages, 1n+position)
        +prepared : I.Expr <- rebuild(expression, expressions(c))
        return Edited{[prepared], fresh(prepared, ownership, usages, next(c)), next(c)}
    case 1n+ +rest Expressions{Nil{}, reversed}:
      Done{Edited{List.reverse(&2, I.Expr, reversed), False{}, position}}
    case 1n+ +rest Expressions{head <> tail, reversed}:
      do Result<&2, &2, M.Diagnostic, Edited>:
        +first : Edited <- rewrite(rest, Expression{head}, ownership, usages, position)
        value : I.Expr <- one(expressions(first))
        rewrite(rest, Expressions{tail, value <> reversed}, ownership, usages, next(first))

def prepare(+expression: I.Expr) -> Result<&2, &2, M.Diagnostic, I.Expr>:
  do Result<&2, &2, M.Diagnostic, I.Expr>:
    usages : Map<&2, Usage> <- scan(65536n, [Scan{expression, False{}}], Map.new(&2, Usage), 0n)
    result : Edited <- rewrite(65536n, Expression{expression}, Map.new(&2, Bool), usages, 0n)
    one(expressions(result))
