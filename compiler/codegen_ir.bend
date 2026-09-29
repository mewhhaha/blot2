import Base
import ./model.bend as M
import ./closures.bend as F
import ./wasm_catalog.bend as E
import ./index.bend as Index
import ./codegen_saturation.bend as Saturation

type Metadata is Data:
  Metadata{lambdas: Map<&2, Maybe<&2, F.Lambda>>, constructors: Map<&2, Maybe<&2, E.ConstructorSlot>>, safe_loops: Set(), functions: Map<&2, Maybe<&2, Saturation.Definition>>}

def lambda_index_go(lambdas: List<&2, F.Lambda>, indexed: Map<&2, Maybe<&2, F.Lambda>>) -> Map<&2, Maybe<&2, F.Lambda>>:
  match lambdas:
    case Nil{}:
      indexed
    case F.Lambda{+identity, parameter, body, captures} <> tail:
      lambda_index_go(tail, Index.set(Maybe<&2, F.Lambda>, indexed, Nat.show(identity), Some{F.Lambda{identity, parameter, body, captures}}))

def metadata(lambdas: List<&2, F.Lambda>, constructors: Map<&2, Maybe<&2, E.ConstructorSlot>>) -> Metadata:
  Metadata{lambda_index_go(List.reverse(&2, F.Lambda, lambdas), Map.new(&2, Maybe<&2, F.Lambda>)), constructors, Set.new(), Saturation.empty()}

def metadata_lambdas(projection: Metadata) -> Map<&2, Maybe<&2, F.Lambda>>:
  Metadata{lambdas, constructors, safe_loops, functions} = projection
  lambdas

def metadata_constructors(projection: Metadata) -> Map<&2, Maybe<&2, E.ConstructorSlot>>:
  Metadata{lambdas, constructors, safe_loops, functions} = projection
  constructors

def with_safe_loops(projection: Metadata, entries: Set()) -> Metadata:
  Metadata{lambdas, constructors, previous, functions} = projection
  Metadata{lambdas, constructors, entries, functions}

def with_functions(projection: Metadata, checked: List<&2, M.CheckedFunction>) -> Metadata:
  Metadata{lambdas, constructors, safe_loops, previous} = projection
  Metadata{lambdas, constructors, safe_loops, Saturation.definitions(checked, Saturation.empty())}

def metadata_functions(projection: Metadata) -> Map<&2, Maybe<&2, Saturation.Definition>>:
  Metadata{lambdas, constructors, safe_loops, functions} = projection
  functions

def safe_loop_entry(projection: Metadata, key: String) -> Bool:
  Metadata{lambdas, constructors, safe_loops, functions} = projection
  Maybe.is_some(&2, Unit, Index.find(Unit, safe_loops, key))

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
  StateProviderExpr{read: M.TypeId, write: M.TypeId, initial: Expr}
  HandleExpr{provider: Expr, body: Expr}
  InvokeOperationExpr{identity: M.TypeId, argument: Expr}
  PanicExpr{message: String}
  ProductExpr{elements: List<&2, Expr>}
  ProjectExpr{value: Expr, index: Nat}
  ArrayExpr{elements: List<&2, Expr>}
  ForExpr{index: String, start: Expr, end: Expr, state: String, initial: Expr, body: Expr}
  ForeverExpr{state: String, initial: Expr, body: Expr, compact: Bool}
  ArrayGenerateExpr{count: Expr, generator: Expr}
  ArrayFillExpr{count: Expr, value: Expr}
  ArrayGetExpr{array: Expr, index: Expr}
  ArraySetExpr{array: Expr, index: Expr, value: Expr}
  ArrayReuseExpr{array: Expr, index: Expr, value: Expr}
  ArrayLengthExpr{array: Expr}
  MemoExpr{computation: Expr}
  ForceExpr{value: Expr}

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
    case M.MemoExpr{computation} value <> Nil{}:
      Done{MemoExpr{value}}
    case M.ForceExpr{original} value <> Nil{}:
      Done{ForceExpr{value}}
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
    case M.StateProviderExpr{read, write, initial} value <> Nil{}:
      Done{StateProviderExpr{read, write, value}}
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
    case M.ForExpr{index, start, end, state, initial, body} a <> b <> c <> d <> Nil{}:
      Done{ForExpr{index, a, b, state, c, d}}
    case M.ForeverExpr{state, initial, body} a <> b <> Nil{}:
      Done{ForeverExpr{state, a, b, False{}}}
    case M.ArrayGenerateExpr{count, generator} c <> v <> Nil{}:
      Done{ArrayGenerateExpr{c, v}}
    case M.ArrayFillExpr{count, value} c <> v <> Nil{}:
      Done{ArrayFillExpr{c, v}}
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

# Explicit checked array annotations provide the carry representation without
# leaking source annotations into codegen cache keys. Other loop state shapes
# keep the ordinary allocator behavior.
def flat_annotation(fuel: Nat, expression: M.Expr) -> Bool:
  match fuel expression:
    case 0n _:
      False{}
    case 1n+rest M.SourceExpr{offset, Some{M.ArrayTy{M.F32Ty{}}}, value}:
      True{}
    case 1n+rest M.SourceExpr{offset, Some{M.ArrayTy{M.U32Ty{}}}, value}:
      True{}
    case 1n+rest M.SourceExpr{offset, annotation, value}:
      flat_annotation(rest, value)
    case 1n+rest M.QualifiedExpr{offset, annotation, predicates, value}:
      flat_annotation(rest, value)
    case 1n+rest M.InstantiationExpr{site, value}:
      flat_annotation(rest, value)
    case _ _:
      False{}

def flat_carry(fuel: Nat, expression: M.Expr, +arrays: Set()) -> Bool:
  match fuel expression:
    case 0n _:
      False{}
    case 1n+rest M.LocalExpr{name}:
      Maybe.is_some(&2, Unit, Index.find(Unit, arrays, name))
    case 1n+rest M.SourceExpr{offset, annotation, value}:
      flat_carry(rest, value, arrays)
    case 1n+rest M.QualifiedExpr{offset, annotation, predicates, value}:
      flat_carry(rest, value, arrays)
    case 1n+rest M.InstantiationExpr{site, value}:
      flat_carry(rest, value, arrays)
    case _ _:
      False{}

def provider_free(expression: M.Expr) -> Bool:
  match expression:
    case M.HandleExpr{provider, body}:
      False{}
    case _:
      True{}

def lower(+fuel: Nat, work: Work, +projection: Metadata, +arrays: Set(), +isolated: Bool) -> Result<&2, &2, M.Diagnostic, List<&2, Expr>>:
  match fuel work:
    case 0n _:
      Fail{M.Diagnostic{"backend_limit", "codegen", "runtime projection exceeded its structural depth limit"}}
    case 1n+rest ExpressionWork{M.RuntimeInitExpr{value}}:
      lower(rest, ExpressionWork{value}, projection, arrays, isolated)
    case 1n+rest ExpressionWork{M.SourceExpr{offset, annotation, value}}:
      lower(rest, ExpressionWork{value}, projection, arrays, isolated)
    case 1n+rest ExpressionWork{M.QualifiedExpr{offset, annotation, predicates, value}}:
      lower(rest, ExpressionWork{value}, projection, arrays, isolated)
    case 1n+rest ExpressionWork{M.InstantiationExpr{site, value}}:
      lower(rest, ExpressionWork{value}, projection, arrays, isolated)
    case 1n+rest ExpressionWork{M.TagExpr{offset, callee, argument}}:
      lower(rest, ExpressionWork{M.ApplyExpr{callee, argument}}, projection, arrays, isolated)
    case 1n+rest ExpressionWork{M.LambdaExpr{+identity, parameter, parameter_type, result_type, body}}:
      do Result<&2, &2, M.Diagnostic, List<&2, Expr>>:
        reference : Expr <- closure_reference(lambda_get(metadata_lambdas(projection), identity), identity)
        return [reference]
    case 1n+rest ExpressionWork{M.ConstructorRefExpr{+constructor}}:
      do Result<&2, &2, M.Diagnostic, List<&2, Expr>>:
        reference : Expr <- constructor_reference(E.constructor_get(metadata_constructors(projection), constructor), constructor)
        return [reference]
    case 1n+rest ExpressionWork{M.LetExpr{+name, +value, body}}:
      +nested = Bool.pick(Set(), flat_annotation(16384n, value), Set.add(arrays, name), arrays)
      do Result<&2, &2, M.Diagnostic, List<&2, Expr>>:
        values : List<&2, Expr> <- lower(rest, ExpressionWork{value}, projection, arrays, isolated)
        v : Expr <- one(values)
        bodies : List<&2, Expr> <- lower(rest, ExpressionWork{body}, projection, nested, isolated)
        b : Expr <- one(bodies)
        return [LetExpr{name, v, b}]
    case 1n+rest ExpressionWork{M.ForeverExpr{state, +initial, body}}:
      +compact = isolated
      do Result<&2, &2, M.Diagnostic, List<&2, Expr>>:
        values : List<&2, Expr> <- lower(rest, ExpressionWork{initial}, projection, arrays, isolated)
        v : Expr <- one(values)
        bodies : List<&2, Expr> <- lower(rest, ExpressionWork{body}, projection, arrays, isolated)
        b : Expr <- one(bodies)
        return [ForeverExpr{state, v, b, compact}]
    case 1n+rest ExpressionWork{+expression}:
      # State providers can retain iteration allocations independently of carry.
      +safe = Bool.and(isolated, provider_free(expression))
      do Result<&2, &2, M.Diagnostic, List<&2, Expr>>:
        children : List<&2, Expr> <- lower(rest, ExpressionsWork{F.children(expression), Nil{}}, projection, arrays, safe)
        prepared : Expr <- rebuild(expression, children)
        return [prepared]
    case 1n+rest ExpressionsWork{Nil{}, reversed}:
      Done{List.reverse(&2, Expr, reversed)}
    case 1n+rest ExpressionsWork{head <> tail, reversed}:
      do Result<&2, &2, M.Diagnostic, List<&2, Expr>>:
        first : List<&2, Expr> <- lower(rest, ExpressionWork{head}, projection, arrays, isolated)
        prepared : Expr <- one(first)
        lower(rest, ExpressionsWork{tail, prepared <> reversed}, projection, arrays, isolated)

def prepare_scoped(expression: M.Expr, +projection: Metadata, isolated: Bool) -> Result<&2, &2, M.Diagnostic, Expr>:
  do Result<&2, &2, M.Diagnostic, Expr>:
    expanded : M.Expr <- Saturation.prepare(expression, metadata_functions(projection))
    result : List<&2, Expr> <- lower(U32.to_nat(16384), ExpressionWork{expanded}, projection, Set.new(), isolated)
    one(result)

def prepare(expression: M.Expr, projection: Metadata) -> Result<&2, &2, M.Diagnostic, Expr>:
  prepare_scoped(expression, projection, False{})
