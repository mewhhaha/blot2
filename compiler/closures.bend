import Base
import ./model.bend as M

type Lambda is Data:
  Lambda{identity: Nat, parameter: String, body: M.Expr, captures: List<&2, String>}

type FreeWork is Data:
  ExpressionWork{expression: M.Expr, bound: List<&2, String>}
  ExpressionsWork{expressions: List<&2, M.Expr>, bound: List<&2, String>}
  ArmsWork{arms: List<&2, M.MatchArm<M.Expr>>, bound: List<&2, String>}

def contains(names: List<&2, String>, +name: String) -> Bool:
  match names:
    case Nil{}:
      False{}
    case head <> tail:
      Bool.or(M.name_equal(head, name), contains(tail, name))

def union(left: List<&2, String>, +right: List<&2, String>) -> List<&2, String>:
  match left:
    case Nil{}:
      right
    case +head <> tail:
      +rest = union(tail, right)
      Bool.pick(List<&2, String>, contains(rest, head), rest, head <> rest)

def pattern_names(pattern: M.Pattern) -> List<&2, String>:
  match pattern:
    case M.BindingPattern{name}:
      [name]
    case M.ConstructorPattern{constructor, Some{payload}}:
      pattern_names(payload)
    case _:
      Nil{}

def arm_expressions(arms: List<&2, M.MatchArm<M.Expr>>) -> List<&2, M.Expr>:
  match arms:
    case Nil{}:
      Nil{}
    case M.MatchArm{pattern, body} <> tail:
      body <> arm_expressions(tail)

def children(expression: M.Expr) -> List<&2, M.Expr>:
  match expression:
    case M.ConstructExpr{constructor, Some{payload}}:
      [payload]
    case M.LambdaExpr{identity, parameter, parameter_type, result_type, body}:
      [body]
    case M.ApplyExpr{callee, argument}:
      [callee, argument]
    case M.CallExpr{callee, argument}:
      [argument]
    case M.ScalarExpr{operator, left, right}:
      [left, right]
    case M.LetExpr{name, value, body}:
      [value, body]
    case M.UseExpr{name, value, body}:
      [value, body]
    case M.IfExpr{condition, consequent, alternative}:
      [condition, consequent, alternative]
    case M.SequenceExpr{first, next}:
      [first, next]
    case M.MatchExpr{value, arms}:
      value <> arm_expressions(arms)
    case M.GuardExpr{pattern, value, alternative, body}:
      [value, alternative, body]
    case M.BlockExpr{label, body}:
      [body]
    case M.ReturnExpr{label, value}:
      [value]
    case M.SourceExpr{offset, annotation, value}:
      [value]
    case M.WriteExpr{value}:
      [value]
    case M.InsertExpr{value}:
      [value]
    case _:
      Nil{}

def free(+fuel: Nat, work: FreeWork) -> Result<&2, &2, M.Diagnostic, List<&2, String>>:
  match fuel:
    case 0n:
      Fail{M.Diagnostic{"backend_limit", "closure", "closure analysis exceeded its structural depth limit"}}
    case 1n+rest:
      match work:
        case ExpressionWork{M.LocalExpr{+name}, bound}:
          Done{Bool.pick(List<&2, String>, contains(bound, name), Nil{}, [name])}
        case ExpressionWork{M.LambdaExpr{identity, parameter, parameter_type, result_type, body}, bound}:
          free(rest, ExpressionWork{body, parameter <> bound})
        case ExpressionWork{M.LetExpr{name, value, body}, +bound}:
          do Result<&2, &2, M.Diagnostic, List<&2, String>>:
            a : List<&2, String> <- free(rest, ExpressionWork{value, bound})
            b : List<&2, String> <- free(rest, ExpressionWork{body, name <> bound})
            return union(a, b)
        case ExpressionWork{M.UseExpr{name, value, body}, +bound}:
          do Result<&2, &2, M.Diagnostic, List<&2, String>>:
            a : List<&2, String> <- free(rest, ExpressionWork{value, bound})
            b : List<&2, String> <- free(rest, ExpressionWork{body, name <> bound})
            return union(a, b)
        case ExpressionWork{M.MatchExpr{value, arms}, +bound}:
          do Result<&2, &2, M.Diagnostic, List<&2, String>>:
            a : List<&2, String> <- free(rest, ExpressionWork{value, bound})
            b : List<&2, String> <- free(rest, ArmsWork{arms, bound})
            return union(a, b)
        case ExpressionWork{M.GuardExpr{pattern, value, alternative, body}, +bound}:
          do Result<&2, &2, M.Diagnostic, List<&2, String>>:
            a : List<&2, String> <- free(rest, ExpressionsWork{[value, alternative], bound})
            b : List<&2, String> <- free(rest, ExpressionWork{body, List.append(&2, String, pattern_names(pattern), bound)})
            return union(a, b)
        case ExpressionWork{expression, bound}:
          free(rest, ExpressionsWork{children(expression), bound})
        case ExpressionsWork{Nil{}, bound}:
          Done{Nil{}}
        case ExpressionsWork{head <> tail, +bound}:
          do Result<&2, &2, M.Diagnostic, List<&2, String>>:
            a : List<&2, String> <- free(rest, ExpressionWork{head, bound})
            b : List<&2, String> <- free(rest, ExpressionsWork{tail, bound})
            return union(a, b)
        case ArmsWork{Nil{}, bound}:
          Done{Nil{}}
        case ArmsWork{M.MatchArm{pattern, body} <> tail, +bound}:
          do Result<&2, &2, M.Diagnostic, List<&2, String>>:
            a : List<&2, String> <- free(rest, ExpressionWork{body, List.append(&2, String, pattern_names(pattern), bound)})
            b : List<&2, String> <- free(rest, ArmsWork{tail, bound})
            return union(a, b)

def lambda(expression: M.Expr) -> Result<&2, &2, M.Diagnostic, List<&2, Lambda>>:
  match expression:
    case M.LambdaExpr{identity, +parameter, parameter_type, result_type, +body}:
      do Result<&2, &2, M.Diagnostic, List<&2, Lambda>>:
        captures : List<&2, String> <- free(U32.to_nat(4096), ExpressionWork{body, [parameter]})
        return [Lambda{identity, parameter, body, captures}]
    case _:
      Done{Nil{}}

def collect(+fuel: Nat, expressions: List<&2, M.Expr>) -> Result<&2, &2, M.Diagnostic, List<&2, Lambda>>:
  match fuel:
    case 0n:
      Fail{M.Diagnostic{"backend_limit", "closure", "lambda collection exceeded its structural depth limit"}}
    case 1n+rest:
      match expressions:
        case Nil{}:
          Done{Nil{}}
        case +head <> tail:
          do Result<&2, &2, M.Diagnostic, List<&2, Lambda>>:
            own : List<&2, Lambda> <- lambda(head)
            nested : List<&2, Lambda> <- collect(rest, children(head))
            siblings : List<&2, Lambda> <- collect(rest, tail)
            return List.append(&2, Lambda, own, List.append(&2, Lambda, nested, siblings))

def function_expressions(functions: List<&2, M.CheckedFunction>) -> List<&2, M.Expr>:
  match functions:
    case Nil{}:
      Nil{}
    case M.CheckedFunction{M.Function{name, exported, parameter, parameter_type, result_type, body}, signature, effects} <> tail:
      body <> function_expressions(tail)

def constant_expressions(constants: List<&2, M.CheckedConstant>) -> List<&2, M.Expr>:
  match constants:
    case Nil{}:
      Nil{}
    case M.CheckedConstant{M.Constant{name, exported, annotation, value}, inferred_type, variables} <> tail:
      value <> constant_expressions(tail)
