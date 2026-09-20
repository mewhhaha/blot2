import Base

type TypeId is Data:
  TypeId{module_name: String, declaration: String}

type Storage is Data:
  Component{}
  Resource{}

type Access is Data:
  Read{}
  Write{}
  Insert{}

type Descriptor is Data:
  Descriptor{identity: TypeId, storage: Storage}

type Ty is Data:
  UnitTy{}
  U32Ty{}
  BoolTy{}
  NominalTy{identity: TypeId}
  AppliedTy{identity: TypeId, arguments: List<&2, Ty>}
  FunctionTy{parameter: Ty, result: Ty}
  ParameterTy{index: Nat}
  VariableTy{index: Nat}
  NeverTy{}

type Constructor is Data:
  Constructor{name: String, payload: Maybe<&2, Ty>}

type DataType is Data:
  DataType{identity: TypeId, parameters: Nat, constructors: List<&2, Constructor>}

type Pattern is Data:
  WildcardPattern{}
  BindingPattern{name: String}
  UnitPattern{}
  U32Pattern{value: U32}
  BoolPattern{value: Bool}
  ConstructorPattern{constructor: String, payload: Maybe<&2, Pattern>}

type MatchArm<-E: Data> is Data:
  MatchArm{pattern: Pattern, body: E}

type ScalarOp is Data:
  Add{}
  Subtract{}
  Multiply{}
  Equal{}
  LessThan{}

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
  MatchExpr{value: Expr, arms: List<&2, MatchArm<Expr>>}
  GuardExpr{pattern: Pattern, value: Expr, alternative: Expr, body: Expr}
  BlockExpr{label: Nat, body: Expr}
  ReturnExpr{label: Nat, value: Expr}
  SourceExpr{offset: Nat, annotation: Maybe<&2, Ty>, value: Expr}
  ReadExpr{identity: TypeId}
  WriteExpr{value: Expr}
  InsertExpr{value: Expr}

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
    descriptors: List<&2, Descriptor>,
    constants: List<&2, Constant>,
    functions: List<&2, Function>,
    data_types: List<&2, DataType>
  }

type Diagnostic is Data:
  Diagnostic{code: String, subject: String, message: String}

type Effect is Data:
  Effect{access: Access, descriptor: Descriptor}

type Signature is Data:
  Signature{name: String, parameter: Ty, result: Ty, variables: List<&2, Nat>}

type CheckedFunction is Data:
  CheckedFunction{function: Function, signature: Signature, effects: List<&2, Effect>}

type CheckedConstant is Data:
  CheckedConstant{constant: Constant, inferred_type: Ty, variables: List<&2, Nat>}

type CheckedModule is Data:
  CheckedModule{
    constants: List<&2, CheckedConstant>,
    functions: List<&2, CheckedFunction>,
    data_types: List<&2, DataType>
  }

type SystemPlan is Data:
  SystemPlan{name: String, effects: List<&2, Effect>, query: List<&2, Descriptor>}

type WorldPlan is Data:
  WorldPlan{registrations: List<&2, Descriptor>, systems: List<&2, SystemPlan>, batches: List<&2, List<&2, String>>}

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
  same_module same_name = name_equal(am, bm) name_equal(an, bn)
  Bool.and(same_module, same_name)

def type_id_show(identity: TypeId) -> String:
  TypeId{module_name, declaration} = identity
  module_name ++ "::" ++ declaration

type TypeDisplay is Data:
  DisplayType{value: Ty}
  DisplayArguments{values: List<&2, Ty>}

def type_display(+depth: Nat, display: TypeDisplay) -> String:
  match depth display:
    case 0n _:
      "..."
    case 1n+rest DisplayType{UnitTy{}}:
      "Unit"
    case 1n+rest DisplayType{U32Ty{}}:
      "U32"
    case 1n+rest DisplayType{BoolTy{}}:
      "Bool"
    case 1n+rest DisplayType{NominalTy{identity}}:
      type_id_show(identity)
    case 1n+rest DisplayType{AppliedTy{identity, arguments}}:
      type_id_show(identity) ++ type_display(rest, DisplayArguments{arguments})
    case 1n+rest DisplayType{FunctionTy{parameter, result}}:
      "(" ++ type_display(rest, DisplayType{parameter}) ++ " -> " ++ type_display(rest, DisplayType{result}) ++ ")"
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
