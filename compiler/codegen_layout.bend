import Base
import ./model.bend as M
import ./codegen_ir.bend as I
import ./index.bend as Index

# Representation evidence derived only from a normalized instruction job.
# Never use erased annotations, constant contents or another entry's body:
# these are intentionally absent from the instruction-cache key.
type Shape is Data:
  Unknown{}
  Scalar{}
  ScalarArray{}
  Product{fields: List<&2, Shape>}

def empty() -> Map<&2, Shape>:
  Map.new(&2, Shape)

def find(locals: Map<&2, Shape>, name: String) -> Shape:
  Index.get(Shape, locals, name, Unknown{})

def bind(locals: Map<&2, Shape>, name: String, shape: Shape) -> Map<&2, Shape>:
  Map.set(&2, Shape, locals, name, shape)

def scalar(shape: Shape) -> Bool:
  match shape:
    case Scalar{}:
      True{}
    case _:
      False{}

def all_scalar(fields: List<&2, Shape>) -> Bool:
  match fields:
    case Nil{}:
      True{}
    case Scalar{} <> tail:
      all_scalar(tail)
    case _:
      False{}

def array_shape(scalars: Bool) -> Shape:
  Bool.pick(Shape, scalars, ScalarArray{}, Unknown{})

def field(fields: List<&2, Shape>, index: Nat) -> Shape:
  match fields index:
    case head <> tail 0n:
      head
    case head <> tail 1n+rest:
      field(tail, rest)
    case Nil{} _:
      Unknown{}

def project(shape: Shape, index: Nat) -> Shape:
  match shape:
    case Product{fields}:
      field(fields, index)
    case _:
      Unknown{}

def element(shape: Shape) -> Shape:
  match shape:
    case ScalarArray{}:
      Scalar{}
    case _:
      Unknown{}

def prepend(head: Shape, tail: Shape) -> Shape:
  match tail:
    case Product{fields}:
      Product{head <> fields}
    case _:
      Unknown{}

def scalar_fields(shape: Shape) -> Bool:
  match shape:
    case Product{fields}:
      all_scalar(fields)
    case _:
      False{}

# A join can only lose information; one known branch cannot establish the
# representation of another unknown branch. Different arities stay unknown.
def meet(fuel: Nat, left: Shape, right: Shape) -> Shape:
  match fuel left right:
    case 0n _ _:
      Unknown{}
    case 1n+rest Scalar{} Scalar{}:
      Scalar{}
    case 1n+rest ScalarArray{} ScalarArray{}:
      ScalarArray{}
    case 1n+rest Product{Nil{}} Product{Nil{}}:
      Product{Nil{}}
    case 1n+ +rest Product{a <> left} Product{b <> right}:
      prepend(meet(rest, a, b), meet(rest, Product{left}, Product{right}))
    case _ _ _:
      Unknown{}

type PatternWork is Data:
  Pattern{pattern: M.Pattern, shape: Shape}
  Fields{patterns: List<&2, M.Pattern>, shape: Shape, index: Nat}
  Rows{patterns: List<&2, M.Pattern>, shapes: List<&2, Shape>}

# Every binding shadows, even without evidence. Constructor payloads remain
# unknown. Exhausting the analysis budget clears facts rather than risking a
# stale outer binding. It does not reject the program or affect emitted scopes.
def pattern_work(fuel: Nat, work: PatternWork, locals: Map<&2, Shape>) -> Map<&2, Shape>:
  match fuel work:
    case 0n _:
      empty()
    case 1n+rest Pattern{M.BindingPattern{name}, shape}:
      bind(locals, name, shape)
    case 1n+rest Pattern{M.ProductPattern{fields}, shape}:
      pattern_work(rest, Fields{fields, shape, 0n}, locals)
    case 1n+rest Pattern{M.ConstructorPattern{constructor, Some{payload}}, shape}:
      pattern_work(rest, Pattern{payload, Unknown{}}, locals)
    case 1n+rest Pattern{pat, shape}:
      locals
    case 1n+rest Fields{Nil{}, shape, index}:
      locals
    case 1n+ +rest Fields{head <> tail, +shape, +index}:
      pattern_work(rest, Fields{tail, shape, 1n+index}, pattern_work(rest, Pattern{head, project(shape, index)}, locals))
    case 1n+rest Rows{Nil{}, shapes}:
      locals
    case 1n+ +rest Rows{head <> tail, value <> following}:
      pattern_work(rest, Rows{tail, following}, pattern_work(rest, Pattern{head, value}, locals))
    case 1n+ +rest Rows{head <> tail, Nil{}}:
      pattern_work(rest, Rows{tail, Nil{}}, pattern_work(rest, Pattern{head, Unknown{}}, locals))

def pattern(fuel: Nat, pat: M.Pattern, shape: Shape, locals: Map<&2, Shape>) -> Map<&2, Shape>:
  pattern_work(fuel, Pattern{pat, shape}, locals)

def patterns(fuel: Nat, pats: List<&2, M.Pattern>, shapes: List<&2, Shape>, locals: Map<&2, Shape>) -> Map<&2, Shape>:
  pattern_work(fuel, Rows{pats, shapes}, locals)

type Work is Data:
  Expression{expression: I.Expr}
  Expressions{expressions: List<&2, I.Expr>}

# Blocks and loops remain unknown: their value can arrive through a nonlocal
# return or a loop-carried value, not just their final expression. Budgets bound
# the extra analysis work; exhaustion always loses facts, never compilation.
def infer(fuel: Nat, work: Work, +locals: Map<&2, Shape>) -> Shape:
  match fuel work:
    case 0n _:
      Unknown{}
    case 1n+rest Expression{I.UnitExpr{}}:
      Scalar{}
    case 1n+rest Expression{I.U32Expr{value}}:
      Scalar{}
    case 1n+rest Expression{I.F32Expr{value}}:
      Scalar{}
    case 1n+rest Expression{I.BoolExpr{value}}:
      Scalar{}
    case 1n+rest Expression{I.ScalarExpr{operator, left, right}}:
      Scalar{}
    case 1n+rest Expression{I.UnaryExpr{operator, value}}:
      Scalar{}
    case 1n+rest Expression{I.ArrayLengthExpr{array}}:
      Scalar{}
    case 1n+rest Expression{I.LocalExpr{name}}:
      find(locals, name)
    case 1n+rest Expression{I.ProductExpr{fields}}:
      infer(rest, Expressions{fields}, locals)
    case 1n+rest Expression{I.ProjectExpr{value, index}}:
      project(infer(rest, Expression{value}, locals), index)
    case 1n+rest Expression{I.ArrayExpr{fields}}:
      array_shape(scalar_fields(infer(rest, Expressions{fields}, locals)))
    case 1n+rest Expression{I.ArrayFillExpr{count, value}}:
      array_shape(scalar(infer(rest, Expression{value}, locals)))
    case 1n+rest Expression{I.ArrayGetExpr{array, index}}:
      element(infer(rest, Expression{array}, locals))
    case 1n+ +rest Expression{I.ArraySetExpr{array, index, value}}:
      meet(rest, infer(rest, Expression{array}, locals), array_shape(scalar(infer(rest, Expression{value}, locals))))
    case 1n+ +rest Expression{I.ArrayReuseExpr{array, index, value}}:
      meet(rest, infer(rest, Expression{array}, locals), array_shape(scalar(infer(rest, Expression{value}, locals))))
    case 1n+ +rest Expression{I.LetExpr{name, value, body}}:
      infer(rest, Expression{body}, bind(locals, name, infer(rest, Expression{value}, locals)))
    case 1n+ +rest Expression{I.IfExpr{condition, consequent, alternative}}:
      meet(rest, infer(rest, Expression{consequent}, locals), infer(rest, Expression{alternative}, locals))
    case 1n+rest Expression{I.SequenceExpr{first, next}}:
      infer(rest, Expression{next}, locals)
    case 1n+ +rest Expression{I.GuardExpr{pat, value, alternative, body}}:
      meet(rest, infer(rest, Expression{alternative}, locals), infer(rest, Expression{body}, pattern(rest, pat, infer(rest, Expression{value}, locals), locals)))
    case 1n+rest Expression{expr}:
      Unknown{}
    case 1n+rest Expressions{Nil{}}:
      Product{Nil{}}
    case 1n+ +rest Expressions{head <> tail}:
      prepend(infer(rest, Expression{head}, locals), infer(rest, Expressions{tail}, locals))

def expression(fuel: Nat, expr: I.Expr, locals: Map<&2, Shape>) -> Shape:
  infer(fuel, Expression{expr}, locals)

def shapes(shape: Shape) -> List<&2, Shape>:
  match shape:
    case Product{fields}:
      fields
    case _:
      Nil{}

def expressions(fuel: Nat, values: List<&2, I.Expr>, locals: Map<&2, Shape>) -> List<&2, Shape>:
  shapes(infer(fuel, Expressions{values}, locals))
