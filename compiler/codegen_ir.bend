import Base
import ./model.bend as M
import ./closures.bend as F
import ./wasm_catalog.bend as E
import ./index.bend as Index

type Metadata is Data:
  Metadata{lambdas: Map<&2, Maybe<&2, F.Lambda>>, constructors: Map<&2, Maybe<&2, E.ConstructorSlot>>}

def lambda_index_go(lambdas: List<&2, F.Lambda>, indexed: Map<&2, Maybe<&2, F.Lambda>>) -> Map<&2, Maybe<&2, F.Lambda>>:
  match lambdas:
    case Nil{}:
      indexed
    case F.Lambda{+identity, parameter, body, captures} <> tail:
      lambda_index_go(tail, Map.set(&2, Maybe<&2, F.Lambda>, indexed, Nat.show(identity), Some{F.Lambda{identity, parameter, body, captures}}))

def metadata(lambdas: List<&2, F.Lambda>, constructors: Map<&2, Maybe<&2, E.ConstructorSlot>>) -> Metadata:
  Metadata{lambda_index_go(List.reverse(&2, F.Lambda, lambdas), Map.new(&2, Maybe<&2, F.Lambda>)), constructors}

def metadata_lambdas(projection: Metadata) -> Map<&2, Maybe<&2, F.Lambda>>:
  Metadata{lambdas, constructors} = projection
  lambdas

def metadata_constructors(projection: Metadata) -> Map<&2, Maybe<&2, E.ConstructorSlot>>:
  Metadata{lambdas, constructors} = projection
  constructors

def lambda_get(indexed: Map<&2, Maybe<&2, F.Lambda>>, identity: Nat) -> Maybe<&2, F.Lambda>:
  Index.get(Maybe<&2, F.Lambda>, indexed, Nat.show(identity), None{})

# This is the cache boundary: annotations, source locations, linked indices,
# constant values, and nested lambda bodies cannot enter an instruction job.
type Expr is Data:
  UnitExpr{}
  U32Expr{value: U32}
  BoolExpr{value: Bool}
  LocalExpr{name: String}
  ConstantExpr{name: String}
  ClosureExpr{key: String, captures: List<&2, String>}
  ConstructExpr{constructor: String, payload: Maybe<&2, Expr>}
  ApplyExpr{callee: Expr, argument: Expr}
  CallExpr{key: String, argument: Expr}
  ScalarExpr{operator: M.ScalarOp, left: Expr, right: Expr}
  LetExpr{name: String, value: Expr, body: Expr}
  IfExpr{condition: Expr, consequent: Expr, alternative: Expr}
  SequenceExpr{first: Expr, next: Expr}
  MatchExpr{values: List<&2, Expr>, arms: List<&2, M.MatchArm<Expr>>}
  GuardExpr{pattern: M.Pattern, value: Expr, alternative: Expr, body: Expr}
  BlockExpr{label: Nat, body: Expr}
  ReturnExpr{label: Nat, value: Expr}
  F32Expr{value: F32}
  UnaryExpr{operator: M.UnaryOp, value: Expr}
  ProviderExpr{identity: M.TypeId, implementation: Expr}
  HandleExpr{provider: Expr, body: Expr}
  InvokeOperationExpr{identity: M.TypeId, argument: Expr}
  PanicExpr{message: String}
  ProductExpr{elements: List<&2, Expr>}
  ProjectExpr{value: Expr, index: Nat}
  ArrayExpr{elements: List<&2, Expr>}
  ArrayGetExpr{array: Expr, index: Expr}
  ArraySetExpr{array: Expr, index: Expr, value: Expr}
  ArrayLengthExpr{array: Expr}

type Work is Data:
  ExpressionWork{expression: M.Expr}
  ExpressionsWork{expressions: List<&2, M.Expr>, reversed: List<&2, Expr>}

def invalid() -> M.Diagnostic:
  M.Diagnostic{"internal_error", "codegen", "runtime projection lost a checked expression child"}

def operation_key(identity: M.TypeId) -> String:
  M.TypeId{+module_name, declaration} = identity
  "operation:" ++ Nat.show(String.length(module_name)) ++ ":" ++ module_name ++ declaration

def const_only() -> M.Diagnostic:
  M.Diagnostic{"backend_const_only", "effect reflection", "effect descriptors and reflection are only available during constant evaluation"}

def one(expressions: List<&2, Expr>) -> Result<&2, &2, M.Diagnostic, Expr>:
  match expressions:
    case expression <> Nil{}:
      Done{expression}
    case _:
      Fail{invalid()}

def closure_reference(found: Maybe<&2, F.Lambda>, wanted: Nat) -> Result<&2, &2, M.Diagnostic, Expr>:
  match found:
    case None{}:
      Fail{M.Diagnostic{"internal_error", Nat.show(wanted), "runtime projection lost a checked lambda"}}
    case Some{F.Lambda{identity, parameter, body, captures}}:
      Done{ClosureExpr{"lambda:" ++ Nat.show(wanted), captures}}

def constructor_reference(found: Maybe<&2, E.ConstructorSlot>, wanted: String) -> Result<&2, &2, M.Diagnostic, Expr>:
  match found:
    case None{}:
      Fail{M.Diagnostic{"internal_error", wanted, "runtime projection lost a checked constructor"}}
    case Some{E.ConstructorSlot{name, tag, False{}}}:
      Done{ConstructExpr{wanted, None{}}}
    case Some{E.ConstructorSlot{name, tag, True{}}}:
      Done{ClosureExpr{"constructor:" ++ wanted, Nil{}}}

def rebuild_arms(arms: List<&2, M.MatchArm<M.Expr>>, bodies: List<&2, Expr>) -> Result<&2, &2, M.Diagnostic, List<&2, M.MatchArm<Expr>>>:
  match arms bodies:
    case Nil{} Nil{}:
      Done{Nil{}}
    case M.MatchArm{patterns, body} <> tail head <> rest:
      do Result<&2, &2, M.Diagnostic, List<&2, M.MatchArm<Expr>>>:
        remaining : List<&2, M.MatchArm<Expr>> <- rebuild_arms(tail, rest)
        return M.MatchArm{patterns, head} <> remaining
    case _ _:
      Fail{invalid()}

def rebuild(original: M.Expr, children: List<&2, Expr>) -> Result<&2, &2, M.Diagnostic, Expr>:
  match original children:
    case M.UnitExpr{} Nil{}:
      Done{UnitExpr{}}
    case M.U32Expr{value} Nil{}:
      Done{U32Expr{value}}
    case M.F32Expr{value} Nil{}:
      Done{F32Expr{value}}
    case M.BoolExpr{value} Nil{}:
      Done{BoolExpr{value}}
    case M.LocalExpr{name} Nil{}:
      Done{LocalExpr{name}}
    case M.ConstantExpr{name} Nil{}:
      Done{ConstantExpr{name}}
    case M.FunctionExpr{name} Nil{}:
      Done{ClosureExpr{"fn:" ++ name, Nil{}}}
    case M.OperationExpr{identity} Nil{}:
      Done{ClosureExpr{operation_key(identity), Nil{}}}
    case M.ProviderExpr{identity, implementation} value <> Nil{}:
      Done{ProviderExpr{identity, value}}
    case M.HandleExpr{provider, body} p <> b <> Nil{}:
      Done{HandleExpr{p, b}}
    case M.PanicExpr{message} Nil{}:
      Done{PanicExpr{message}}
    case M.ProductExpr{elements} children:
      Done{ProductExpr{children}}
    case M.ProjectExpr{value, index} child <> Nil{}:
      Done{ProjectExpr{child, index}}
    case M.ArrayExpr{elements} children:
      Done{ArrayExpr{children}}
    case M.ArrayGetExpr{array, index} a <> i <> Nil{}:
      Done{ArrayGetExpr{a, i}}
    case M.ArraySetExpr{array, index, value} a <> i <> v <> Nil{}:
      Done{ArraySetExpr{a, i, v}}
    case M.ArrayLengthExpr{array} child <> Nil{}:
      Done{ArrayLengthExpr{child}}
    case M.OperationDescriptorExpr{identity} _:
      Fail{const_only()}
    case M.FunctionEffectsExpr{callee} _:
      Fail{const_only()}
    case M.EffectHasExpr{set, operation} _:
      Fail{const_only()}
    case M.EffectCountExpr{set} _:
      Fail{const_only()}
    case M.EffectSameExpr{left, right} _:
      Fail{const_only()}
    case M.ConstructExpr{constructor, None{}} Nil{}:
      Done{ConstructExpr{constructor, None{}}}
    case M.ConstructExpr{constructor, Some{payload}} child <> Nil{}:
      Done{ConstructExpr{constructor, Some{child}}}
    case M.ApplyExpr{callee, argument} function <> value <> Nil{}:
      Done{ApplyExpr{function, value}}
    case M.CallExpr{callee, argument} value <> Nil{}:
      Done{CallExpr{"fn:" ++ callee, value}}
    case M.ScalarExpr{operator, left, right} a <> b <> Nil{}:
      Done{ScalarExpr{operator, a, b}}
    case M.UnaryExpr{operator, value} child <> Nil{}:
      Done{UnaryExpr{operator, child}}
    case M.LetExpr{name, value, body} v <> b <> Nil{}:
      Done{LetExpr{name, v, b}}
    case M.UseExpr{name, value, body} v <> b <> Nil{}:
      Done{LetExpr{name, v, b}}
    case M.IfExpr{condition, consequent, alternative} c <> y <> n <> Nil{}:
      Done{IfExpr{c, y, n}}
    case M.SequenceExpr{first, next} a <> b <> Nil{}:
      Done{SequenceExpr{a, b}}
    case M.MatchExpr{values, arms} +children:
      +count = List.length(&2, M.Expr, values)
      do Result<&2, &2, M.Diagnostic, Expr>:
        branches : List<&2, M.MatchArm<Expr>> <- rebuild_arms(arms, List.drop(&2, Expr, children, count))
        return MatchExpr{List.take(&2, Expr, children, count), branches}
    case M.GuardExpr{pattern, value, alternative, body} v <> a <> b <> Nil{}:
      Done{GuardExpr{pattern, v, a, b}}
    case M.BlockExpr{label, body} b <> Nil{}:
      Done{BlockExpr{label, b}}
    case M.ReturnExpr{label, value} v <> Nil{}:
      Done{ReturnExpr{label, v}}
    case _ _:
      Fail{invalid()}

def lower(+fuel: Nat, work: Work, +projection: Metadata) -> Result<&2, &2, M.Diagnostic, List<&2, Expr>>:
  match fuel work:
    case 0n _:
      Fail{M.Diagnostic{"backend_limit", "codegen", "runtime projection exceeded its structural depth limit"}}
    case 1n+rest ExpressionWork{M.SourceExpr{offset, annotation, value}}:
      lower(rest, ExpressionWork{value}, projection)
    case 1n+rest ExpressionWork{M.LambdaExpr{+identity, parameter, parameter_type, result_type, body}}:
      do Result<&2, &2, M.Diagnostic, List<&2, Expr>>:
        reference : Expr <- closure_reference(lambda_get(metadata_lambdas(projection), identity), identity)
        return [reference]
    case 1n+rest ExpressionWork{M.ConstructorRefExpr{+constructor}}:
      do Result<&2, &2, M.Diagnostic, List<&2, Expr>>:
        reference : Expr <- constructor_reference(E.constructor_get(metadata_constructors(projection), constructor), constructor)
        return [reference]
    case 1n+rest ExpressionWork{+expression}:
      do Result<&2, &2, M.Diagnostic, List<&2, Expr>>:
        children : List<&2, Expr> <- lower(rest, ExpressionsWork{F.children(expression), Nil{}}, projection)
        prepared : Expr <- rebuild(expression, children)
        return [prepared]
    case 1n+rest ExpressionsWork{Nil{}, reversed}:
      Done{List.reverse(&2, Expr, reversed)}
    case 1n+rest ExpressionsWork{head <> tail, reversed}:
      do Result<&2, &2, M.Diagnostic, List<&2, Expr>>:
        first : List<&2, Expr> <- lower(rest, ExpressionWork{head}, projection)
        prepared : Expr <- one(first)
        lower(rest, ExpressionsWork{tail, prepared <> reversed}, projection)

def prepare(expression: M.Expr, projection: Metadata) -> Result<&2, &2, M.Diagnostic, Expr>:
  do Result<&2, &2, M.Diagnostic, Expr>:
    result : List<&2, Expr> <- lower(U32.to_nat(16384), ExpressionWork{expression}, projection)
    one(result)
