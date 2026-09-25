import Base

type TypeId is Data:
  TypeId{module_name: String, declaration: String}

type RowTail is Data:
  ClosedRow{}
  RowVariable{index: Nat}
  RowParameter{index: Nat}

# Scoped rows preserve duplicate labels during inference; reflection exposes sets.
type EffectRow is Data:
  EffectRow{operations: List<&2, TypeId>, tail: RowTail}

type Ty is Data:
  UnitTy{}
  U32Ty{}
  BoolTy{}
  AppliedTy{identity: TypeId, arguments: List<&2, Ty>}
  FunctionTy{parameter: Ty, result: Ty, effects: EffectRow}
  ParameterTy{index: Nat}
  VariableTy{index: Nat}
  NeverTy{}
  F32Ty{}
  ProviderTy{identity: TypeId, effects: EffectRow}
  StateProviderTy{read: TypeId, write: TypeId, state: Ty}
  EffectDescriptorTy{}
  EffectSetTy{}
  ProductTy{elements: List<&2, Ty>}
  ArrayTy{element: Ty}
  FreeTy{scope: String, name: String}

type Operation is Data:
  Operation{identity: TypeId, parameter: Ty, result: Ty}
  OperationTemplate{identity: TypeId, parameters: Nat, parameter: Ty, result: Ty}
  OperationInstance{template: TypeId, arguments: List<&2, Ty>}

type Constructor is Data:
  Constructor{name: String, payload: Maybe<&2, Ty>, fields: List<&2, String>}

type DataType is Data:
  DataType{identity: TypeId, parameters: Nat, constructors: List<&2, Constructor>}

type ValueReference is Data:
  LocalReference{name: String}
  ConstantReference{name: String}

type Pattern is Data:
  WildcardPattern{}
  BindingPattern{name: String}
  UnitPattern{}
  U32Pattern{value: U32}
  BoolPattern{value: Bool}
  ValuePattern{reference: ValueReference}
  ConstructorPattern{constructor: String, payload: Maybe<&2, Pattern>}
  ProductPattern{elements: List<&2, Pattern>}

type MatchArm<-E: Data> is Data:
  MatchArm{patterns: List<&2, Pattern>, body: E}

type ScalarOp is Data:
  Add{}
  Subtract{}
  Multiply{}
  Equal{}
  LessThan{}
  F32Add{}
  F32Subtract{}
  F32Multiply{}
  F32Divide{}
  F32Equal{}
  F32NotEqual{}
  F32LessThan{}
  F32LessEqual{}
  F32GreaterThan{}
  F32GreaterEqual{}

type UnaryOp is Data:
  F32Negate{}
  F32Absolute{}
  F32SquareRoot{}
  F32Floor{}
  F32Ceiling{}
  F32Truncate{}
  U32ToF32{}
  F32ToU32{}

type Dispatch is Data:
  BinaryDispatch{}
  MemberDispatch{}
  FieldUpdateDispatch{}

# This is resolved core, not a second spelling of the surface grammar.
type Expr is Data:
  UnitExpr{}
  U32Expr{value: U32}
  BoolExpr{value: Bool}
  LocalExpr{name: String}
  ConstantExpr{name: String}
  FunctionExpr{name: String}
  ConstructorRefExpr{constructor: String}
  ConstructExpr{constructor: String, payload: Maybe<&2, Expr>}
  LambdaExpr{identity: Nat, parameter: String, parameter_type: Maybe<&2, Ty>, result_type: Maybe<&2, Ty>, body: Expr}
  ApplyExpr{callee: Expr, argument: Expr}
  CallExpr{callee: String, argument: Expr}
  ScalarExpr{operator: ScalarOp, left: Expr, right: Expr}
  LetExpr{name: String, value: Expr, body: Expr}
  UseExpr{name: String, value: Expr, body: Expr}
  IfExpr{condition: Expr, consequent: Expr, alternative: Expr}
  SequenceExpr{first: Expr, next: Expr}
  MatchExpr{values: List<&2, Expr>, arms: List<&2, MatchArm<Expr>>}
  GuardExpr{pattern: Pattern, value: Expr, alternative: Expr, body: Expr}
  BlockExpr{label: Nat, body: Expr}
  ReturnExpr{label: Nat, value: Expr}
  SourceExpr{offset: Nat, annotation: Maybe<&2, Ty>, value: Expr}
  RuntimeInitExpr{value: Expr}
  F32Expr{value: F32}
  UnaryExpr{operator: UnaryOp, value: Expr}
  OperationExpr{identity: TypeId}
  SpecializeOperationExpr{template: TypeId, arguments: List<&2, Ty>, body: Expr}
  ProviderExpr{identity: TypeId, implementation: Expr}
  StateProviderExpr{read: TypeId, write: TypeId, initial: Expr}
  HandleExpr{provider: Expr, body: Expr}
  OperationDescriptorExpr{identity: TypeId}
  FunctionEffectsExpr{callee: String}
  EffectHasExpr{set: Expr, operation: Expr}
  EffectCountExpr{set: Expr}
  EffectSameExpr{left: Expr, right: Expr}
  PanicExpr{message: String}
  ProductExpr{elements: List<&2, Expr>}
  ProjectExpr{value: Expr, index: Nat}
  ArrayExpr{elements: List<&2, Expr>}
  ForExpr{index: String, start: Expr, end: Expr, state: String, initial: Expr, body: Expr}
  ForeverExpr{state: String, initial: Expr, body: Expr}
  ArrayGenerateExpr{count: Expr, generator: Expr}
  ArrayFillExpr{count: Expr, value: Expr}
  ArrayGetExpr{array: Expr, index: Expr}
  ArraySetExpr{array: Expr, index: Expr, value: Expr}
  ArrayLengthExpr{array: Expr}
  AssociatedExpr{identity: Nat, dispatch: Dispatch, member: String, templates: List<&2, TypeId>, left: Expr, right: Expr}
  GenericOperationExpr{identity: Nat, template: TypeId, arguments: List<&2, Ty>}

type Function is Data:
  Function{
    name: String,
    exported: Bool,
    parameter: String,
    parameter_type: Maybe<&2, Ty>,
    result_type: Maybe<&2, Ty>,
    body: Expr
  }

type Constant is Data:
  Constant{name: String, exported: Bool, annotation: Maybe<&2, Ty>, value: Expr}

type Module is Data:
  Module{
    constants: List<&2, Constant>,
    functions: List<&2, Function>,
    data_types: List<&2, DataType>,
    operations: List<&2, Operation>
  }

def module_operations(module: Module) -> List<&2, Operation>:
  Module{constants, functions, data_types, operations} = module
  operations

type Diagnostic is Data:
  Diagnostic{code: String, subject: String, message: String}

type Effect is Data:
  OperationEffect{identity: TypeId}

type Signature is Data:
  Signature{name: String, parameter: Ty, result: Ty, variables: List<&2, Nat>, effects: EffectRow}

type CheckedFunction is Data:
  CheckedFunction{function: Function, signature: Signature, effects: List<&2, Effect>}

type CheckedConstant is Data:
  CheckedConstant{constant: Constant, inferred_type: Ty, variables: List<&2, Nat>}

type CheckedModule is Data:
  CheckedModule{
    constants: List<&2, CheckedConstant>,
    functions: List<&2, CheckedFunction>,
    data_types: List<&2, DataType>,
    operations: List<&2, Operation>
  }

def empty_row() -> EffectRow:
  EffectRow{Nil{}, ClosedRow{}}

# Bend 2.0.5's String.eq reconstructs both compared inputs.
# Compiler names only need the Boolean result; consume their common prefix.
def name_equal_tail(left: String, right: String, same: Bool) -> Bool:
  match left right same:
    case _ _ False{}:
      False{}
    case SNil{} SNil{} True{}:
      True{}
    case SCon{a, left_tail} SCon{b, right_tail} True{}:
      name_equal_tail(left_tail, right_tail, Char.is_eq(a, b))
    case _ _ True{}:
      False{}

def name_equal(left: String, right: String) -> Bool:
  name_equal_tail(left, right, True{})

def type_id_equal(a: TypeId, b: TypeId) -> Bool:
  TypeId{am, an} = a
  TypeId{bm, bn} = b
  Bool.and(name_equal(am, bm), name_equal(an, bn))

def foreign_identity() -> TypeId:
  TypeId{"blot:compiler", "Foreign"}

def is_foreign(identity: TypeId) -> Bool:
  type_id_equal(identity, foreign_identity())

def foreign_row() -> EffectRow:
  EffectRow{[foreign_identity()], ClosedRow{}}

def type_id_show(identity: TypeId) -> String:
  TypeId{module_name, declaration} = identity
  module_name ++ "::" ++ declaration

type TypeDisplay is Data:
  DisplayType{value: Ty}
  DisplayArguments{values: List<&2, Ty>}
  DisplayElements{values: List<&2, Ty>}

def row_tail_show(tail: RowTail) -> String:
  match tail:
    case ClosedRow{}:
      ""
    case RowVariable{index}:
      "| ?e" ++ Nat.show(index)
    case RowParameter{index}:
      "| 'e" ++ Nat.show(index)

def row_operations_show(operations: List<&2, TypeId>) -> String:
  match operations:
    case Nil{}:
      ""
    case head <> Nil{}:
      type_id_show(head)
    case head <> next <> tail:
      type_id_show(head) ++ ", " ++ row_operations_show(next <> tail)

def row_show(row: EffectRow) -> String:
  match row:
    case EffectRow{Nil{}, ClosedRow{}}:
      ""
    case EffectRow{operations, tail}:
      " ! {" ++ row_operations_show(operations) ++ row_tail_show(tail) ++ "}"

def type_display(+depth: Nat, display: TypeDisplay) -> String:
  match depth display:
    case 0n _:
      "..."
    case 1n+rest DisplayType{UnitTy{}}:
      "Unit"
    case 1n+rest DisplayType{U32Ty{}}:
      "U32"
    case 1n+rest DisplayType{F32Ty{}}:
      "F32"
    case 1n+rest DisplayType{BoolTy{}}:
      "Bool"
    case 1n+rest DisplayType{AppliedTy{identity, arguments}}:
      type_id_show(identity) ++ type_display(rest, DisplayArguments{arguments})
    case 1n+rest DisplayType{FunctionTy{parameter, result, effects}}:
      "(" ++ type_display(rest, DisplayType{parameter}) ++ " -> " ++ type_display(rest, DisplayType{result}) ++ row_show(effects) ++ ")"
    case 1n+rest DisplayType{StateProviderTy{read, write, state}}:
      "StateProvider " ++ type_id_show(read) ++ " " ++ type_id_show(write) ++ " (" ++ type_display(rest, DisplayType{state}) ++ ")"
    case 1n+rest DisplayType{ProviderTy{identity, effects}}:
      "Provider " ++ type_id_show(identity) ++ row_show(effects)
    case 1n+rest DisplayType{EffectDescriptorTy{}}:
      "EffectDescriptor"
    case 1n+rest DisplayType{EffectSetTy{}}:
      "EffectSet"
    case 1n+rest DisplayType{ProductTy{elements}}:
      "(" ++ type_display(rest, DisplayElements{elements}) ++ ")"
    case 1n+rest DisplayType{ArrayTy{element}}:
      "Array (" ++ type_display(rest, DisplayType{element}) ++ ")"
    case 1n+rest DisplayType{FreeTy{scope, name}}:
      name
    case 1n+rest DisplayType{ParameterTy{index}}:
      "'" ++ Nat.show(index)
    case 1n+rest DisplayType{VariableTy{index}}:
      "?" ++ Nat.show(index)
    case 1n+rest DisplayType{NeverTy{}}:
      "Never"
    case 1n+rest DisplayArguments{Nil{}}:
      ""
    case 1n+rest DisplayArguments{head <> tail}:
      " (" ++ type_display(rest, DisplayType{head}) ++ ")" ++ type_display(rest, DisplayArguments{tail})
    case 1n+rest DisplayElements{Nil{}}:
      ""
    case 1n+rest DisplayElements{head <> Nil{}}:
      type_display(rest, DisplayType{head})
    case 1n+rest DisplayElements{head <> next <> tail}:
      type_display(rest, DisplayType{head}) ++ ", " ++ type_display(rest, DisplayElements{next <> tail})

def type_show(ty: Ty) -> String:
  type_display(64n, DisplayType{ty})

def scalar_result(operator: ScalarOp) -> Ty:
  match operator:
    case Add{}:
      U32Ty{}
    case Subtract{}:
      U32Ty{}
    case Multiply{}:
      U32Ty{}
    case Equal{}:
      BoolTy{}
    case LessThan{}:
      BoolTy{}
    case F32Add{}:
      F32Ty{}
    case F32Subtract{}:
      F32Ty{}
    case F32Multiply{}:
      F32Ty{}
    case F32Divide{}:
      F32Ty{}
    case _:
      BoolTy{}

def scalar_parameter(operator: ScalarOp) -> Ty:
  match operator:
    case Add{}:
      U32Ty{}
    case Subtract{}:
      U32Ty{}
    case Multiply{}:
      U32Ty{}
    case Equal{}:
      U32Ty{}
    case LessThan{}:
      U32Ty{}
    case _:
      F32Ty{}

def unary_parameter(operator: UnaryOp) -> Ty:
  match operator:
    case U32ToF32{}:
      U32Ty{}
    case _:
      F32Ty{}

def unary_result(operator: UnaryOp) -> Ty:
  match operator:
    case F32ToU32{}:
      U32Ty{}
    case _:
      F32Ty{}

def reference_expr(reference: ValueReference) -> Expr:
  match reference:
    case LocalReference{name}:
      LocalExpr{name}
    case ConstantReference{name}:
      ConstantExpr{name}
