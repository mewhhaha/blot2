import Base
import ./model.bend as M
import ./closures.bend as F

type Binding<-V: Data> is Data:
  Binding{name: String, value: V}

type Provider<-V: Data> is Data:
  Provider{identity: M.TypeId, implementation: V}

type Value is Data:
  UnitValue{}
  U32Value{value: U32}
  BoolValue{value: Bool}
  FunctionValue{name: String}
  ConstructorFunctionValue{constructor: String}
  DataValue{constructor: String, payload: Maybe<&2, Value>}
  ClosureValue{identity: Nat, parameter: String, body: M.Expr, environment: List<&2, Binding<Value>>}
  ReturnValue{label: Nat, value: Value}
  F32Value{value: F32}
  OperationValue{identity: M.TypeId}
  ProviderValue{identity: M.TypeId, implementation: Value}
  StateProviderValue{read: M.TypeId, write: M.TypeId, initial: Value}
  StateReadValue{slot: Nat}
  StateWriteValue{slot: Nat}
  EffectDescriptorValue{identity: M.TypeId}
  EffectSetValue{operations: List<&2, M.TypeId>}
  MatchValuesValue{values: List<&2, Value>}
  PatternBindingsValue{bindings: Maybe<&2, List<&2, Binding<Value>>>}
  ProductValue{elements: List<&2, Value>}
  ArrayValue{elements: List<&2, Value>}

type StateCell is Data:
  StateCell{slot: Nat, value: Value}

type Budget is Data:
  Budget{remaining: Nat, cells: List<&2, StateCell>}

type Evaluation is Data:
  Evaluation{value: Value, remaining: Budget}

type Context is Data:
  Context{constants: List<&2, M.Constant>, functions: List<&2, M.Function>, locals: List<&2, Binding<Value>>, data_types: List<&2, M.DataType>, providers: List<&2, Provider<Value>>, checked_functions: List<&2, M.CheckedFunction>}

type Constants is Data:
  Constants{bindings: List<&2, Binding<Value>>, remaining: Nat}

type ScopedExpr is Data:
  ScopedExpr{expression: M.Expr, context: Context}

type Application is Data:
  BodyApplication{scope: ScopedExpr}
  ValueApplication{value: Value}
  OperationApplication{identity: M.TypeId, argument: Value}
  StateReadApplication{slot: Nat}
  StateWriteApplication{slot: Nat, value: Value}

type PatternWork is Data:
  PatternValue{pattern: M.Pattern, value: Value}
  ProductPatterns{patterns: List<&2, M.Pattern>, values: List<&2, Value>}
  ConstructorPayload{same: Bool, pattern: M.Pattern, value: Value}

type PatternProgress is Data:
  PatternPending{work: List<&2, PatternWork>, reversed: List<&2, Binding<Value>>}
  PatternRejected{}

type EvaluationWork is Data:
  HandleValue{provider: Value, body: M.Expr}
  Expression{expression: M.Expr}
  ForBounds{index: String, start: Value, end: Value, state: String, initial: Value, body: M.Expr}
  ForIterations{index: String, current: U32, state: String, value: Value, body: M.Expr}
  ForeverIterations{state: String, value: Value, body: M.Expr}
  GenerateElements{generator: Value, index: U32, reversed: List<&2, Value>}
  CollectValues{}
  MatchArms{arms: List<&2, M.MatchArm<M.Expr>>, values: List<&2, Value>}
  MatchSelected{bindings: Value, body: M.Expr, arms: List<&2, M.MatchArm<M.Expr>>, values: List<&2, Value>}
  MatchPatterns{fuel: Nat, progress: Result<&2, &2, M.Diagnostic, PatternProgress>}

def lookup_local_work(locals: List<&2, Binding<Value>>, +name: String, found: Maybe<&2, Value>) -> Result<&2, &2, M.Diagnostic, Value>:
  match locals found:
    case _ Some{value}:
      Done{value}
    case Nil{} None{}:
      Fail{M.Diagnostic{"internal_error", name, "const evaluator lost a checked local"}}
    case Binding{declared, value} <> tail None{}:
      lookup_local_work(tail, name, Bool.pick(Maybe<&2, Value>, M.name_equal(declared, name), Some{value}, None{}))

def lookup_local(locals: List<&2, Binding<Value>>, name: String) -> Result<&2, &2, M.Diagnostic, Value>:
  lookup_local_work(locals, name, None{})

# Const values cross the compiler transport too; retaining unused lexical values
# can duplicate entire prior builder closures exponentially during serialization.
def capture_environment(names: List<&2, String>, +locals: List<&2, Binding<Value>>) -> Result<&2, &2, M.Diagnostic, List<&2, Binding<Value>>>:
  match names:
    case Nil{}:
      Done{Nil{}}
    case +name <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, Binding<Value>>>:
        value : Value <- lookup_local(locals, name)
        captured : List<&2, Binding<Value>> <- capture_environment(tail, locals)
        return Binding{name, value} <> captured

def lookup_constant_work(constants: List<&2, M.Constant>, +name: String, found: Maybe<&2, M.Expr>) -> Result<&2, &2, M.Diagnostic, M.Expr>:
  match constants found:
    case _ Some{value}:
      Done{value}
    case Nil{} None{}:
      Fail{M.Diagnostic{"internal_error", name, "const evaluator lost a checked constant"}}
    case M.Constant{declared, exported, annotation, value} <> tail None{}:
      lookup_constant_work(tail, name, Bool.pick(Maybe<&2, M.Expr>, M.name_equal(declared, name), Some{value}, None{}))

def lookup_constant(constants: List<&2, M.Constant>, name: String) -> Result<&2, &2, M.Diagnostic, M.Expr>:
  lookup_constant_work(constants, name, None{})

def lookup_function_work(functions: List<&2, M.Function>, +name: String, found: Maybe<&2, M.Function>) -> Result<&2, &2, M.Diagnostic, M.Function>:
  match functions found:
    case _ Some{value}:
      Done{value}
    case Nil{} None{}:
      Fail{M.Diagnostic{"internal_error", name, "const evaluator lost a checked function"}}
    case M.Function{+declared, exported, parameter, parameter_type, result_type, body} <> tail None{}:
      lookup_function_work(tail, name, Bool.pick(Maybe<&2, M.Function>, M.name_equal(declared, name), Some{M.Function{declared, exported, parameter, parameter_type, result_type, body}}, None{}))

def lookup_function(functions: List<&2, M.Function>, name: String) -> Result<&2, &2, M.Diagnostic, M.Function>:
  lookup_function_work(functions, name, None{})

def eval_value(evaluation: Evaluation) -> Value:
  Evaluation{value, remaining} = evaluation
  value

def eval_remaining(evaluation: Evaluation) -> Nat:
  Evaluation{value, Budget{remaining, cells}} = evaluation
  remaining

def spend_budget(budget: Budget) -> Budget:
  Budget{remaining, cells} = budget
  Budget{Nat.sub(remaining, 1n), cells}

def eval_budget(evaluation: Evaluation) -> Budget:
  Evaluation{value, budget} = evaluation
  budget

def context_locals(context: Context) -> List<&2, Binding<Value>>:
  Context{constants, functions, locals, data_types, providers, checked_functions} = context
  locals

def context_constants(context: Context) -> List<&2, M.Constant>:
  Context{constants, functions, locals, data_types, providers, checked_functions} = context
  constants

def context_functions(context: Context) -> List<&2, M.Function>:
  Context{constants, functions, locals, data_types, providers, checked_functions} = context
  functions

def context_data_types(context: Context) -> List<&2, M.DataType>:
  Context{constants, functions, locals, data_types, providers, checked_functions} = context
  data_types

def context_providers(context: Context) -> List<&2, Provider<Value>>:
  Context{constants, functions, locals, data_types, providers, checked_functions} = context
  providers

def context_checked_functions(context: Context) -> List<&2, M.CheckedFunction>:
  Context{constants, functions, locals, data_types, providers, checked_functions} = context
  checked_functions

def without_locals(context: Context) -> Context:
  Context{constants, functions, locals, data_types, providers, checked_functions} = context
  Context{constants, functions, Nil{}, data_types, providers, checked_functions}

def with_locals(context: Context, locals: List<&2, Binding<Value>>) -> Context:
  Context{constants, functions, previous, data_types, providers, checked_functions} = context
  Context{constants, functions, locals, data_types, providers, checked_functions}

def with_local(context: Context, name: String, value: Value) -> Context:
  Context{constants, functions, locals, data_types, providers, checked_functions} = context
  Context{constants, functions, Binding{name, value} <> locals, data_types, providers, checked_functions}

def with_bindings(context: Context, bindings: List<&2, Binding<Value>>) -> Context:
  Context{constants, functions, locals, data_types, providers, checked_functions} = context
  Context{constants, functions, List.append(&2, Binding<Value>, bindings, locals), data_types, providers, checked_functions}

def with_providers(context: Context, providers: List<&2, Provider<Value>>) -> Context:
  Context{constants, functions, locals, data_types, previous, checked_functions} = context
  Context{constants, functions, locals, data_types, providers, checked_functions}

def with_provider(value: Value, context: Context) -> Result<&2, &2, M.Diagnostic, Context>:
  match value:
    case ProviderValue{identity, implementation}:
      Context{constants, functions, locals, data_types, providers, checked_functions} = context
      Done{Context{constants, functions, locals, data_types, Provider{identity, implementation} <> providers, checked_functions}}
    case _:
      Fail{M.Diagnostic{"internal_error", "const", "checked handler received a non-provider value"}}

def function_body(function: M.Function) -> M.Expr:
  M.Function{name, exported, parameter, param_ty, result_ty, body} = function
  body

def function_value_allowed(body: M.Expr, name: String, remaining: Budget) -> Result<&2, &2, M.Diagnostic, Evaluation>:
  match body:
    case M.RuntimeInitExpr{value}:
      Fail{M.Diagnostic{"const_runtime_dependency", name, "a const initializer cannot read a top-level let function"}}
    case _:
      Done{Evaluation{FunctionValue{name}, remaining}}

def function_context(function: M.Function, argument: Value, context: Context) -> Context:
  M.Function{name, exported, parameter, param_ty, result_ty, body} = function
  with_local(without_locals(context), parameter, argument)

def scalar(operator: M.ScalarOp, left: Value, right: Value, remaining: Budget) -> Result<&2, &2, M.Diagnostic, Evaluation>:
  match operator left right:
    case M.Add{} U32Value{a} U32Value{b}:
      Done{Evaluation{U32Value{U32.add(a, b)}, remaining}}
    case M.Subtract{} U32Value{a} U32Value{b}:
      Done{Evaluation{U32Value{U32.sub(a, b)}, remaining}}
    case M.Multiply{} U32Value{a} U32Value{b}:
      Done{Evaluation{U32Value{U32.mul(a, b)}, remaining}}
    case M.Equal{} U32Value{a} U32Value{b}:
      Done{Evaluation{BoolValue{U32.is_eq(a, b)}, remaining}}
    case M.LessThan{} U32Value{a} U32Value{b}:
      Done{Evaluation{BoolValue{U32.is_lt(a, b)}, remaining}}
    case M.F32Add{} F32Value{a} F32Value{b}:
      Done{Evaluation{F32Value{F32.add(a, b)}, remaining}}
    case M.F32Subtract{} F32Value{a} F32Value{b}:
      Done{Evaluation{F32Value{F32.sub(a, b)}, remaining}}
    case M.F32Multiply{} F32Value{a} F32Value{b}:
      Done{Evaluation{F32Value{F32.mul(a, b)}, remaining}}
    case M.F32Divide{} F32Value{a} F32Value{b}:
      Done{Evaluation{F32Value{F32.div(a, b)}, remaining}}
    case M.F32Equal{} F32Value{a} F32Value{b}:
      Done{Evaluation{BoolValue{F32.is_eq(a, b)}, remaining}}
    case M.F32NotEqual{} F32Value{a} F32Value{b}:
      Done{Evaluation{BoolValue{F32.is_ne(a, b)}, remaining}}
    case M.F32LessThan{} F32Value{a} F32Value{b}:
      Done{Evaluation{BoolValue{F32.is_lt(a, b)}, remaining}}
    case M.F32LessEqual{} F32Value{a} F32Value{b}:
      Done{Evaluation{BoolValue{F32.is_le(a, b)}, remaining}}
    case M.F32GreaterThan{} F32Value{a} F32Value{b}:
      Done{Evaluation{BoolValue{F32.is_gt(a, b)}, remaining}}
    case M.F32GreaterEqual{} F32Value{a} F32Value{b}:
      Done{Evaluation{BoolValue{F32.is_ge(a, b)}, remaining}}
    case _ _ _:
      Fail{M.Diagnostic{"internal_error", "const", "checked scalar operation received values of the wrong type"}}

# Match Wasm i32.trunc_sat_f32_u: negative values and NaN become zero;
# overflow and positive infinity saturate at U32.max.
def f32_to_u32_saturating(+value: F32) -> U32:
  Bool.pick(U32, F32.is_ge(value, 4294967296.0), 4294967295, F32.to_u32(value))

def unary(operator: M.UnaryOp, value: Value, remaining: Budget) -> Result<&2, &2, M.Diagnostic, Evaluation>:
  match operator value:
    case M.F32Negate{} F32Value{number}:
      Done{Evaluation{F32Value{F32.neg(number)}, remaining}}
    case M.F32Absolute{} F32Value{number}:
      Done{Evaluation{F32Value{F32.abs(number)}, remaining}}
    case M.F32SquareRoot{} F32Value{number}:
      Done{Evaluation{F32Value{F32.sqrt(number)}, remaining}}
    case M.F32Floor{} F32Value{number}:
      Done{Evaluation{F32Value{F32.floor(number)}, remaining}}
    case M.F32Ceiling{} F32Value{number}:
      Done{Evaluation{F32Value{F32.ceil(number)}, remaining}}
    case M.F32Truncate{} F32Value{number}:
      Done{Evaluation{F32Value{F32.trunc(number)}, remaining}}
    case M.U32ToF32{} U32Value{number}:
      Done{Evaluation{F32Value{U32.to_f32(number)}, remaining}}
    case M.F32ToU32{} F32Value{number}:
      Done{Evaluation{U32Value{f32_to_u32_saturating(number)}, remaining}}
    case _ _:
      Fail{M.Diagnostic{"internal_error", "const", "checked unary operation received a value of the wrong type"}}

def branch(condition: Value, consequent: M.Expr, alternative: M.Expr) -> Result<&2, &2, M.Diagnostic, M.Expr>:
  match condition:
    case BoolValue{test}:
      Done{Bool.pick(M.Expr, test, consequent, alternative)}
    case _:
      Fail{M.Diagnostic{"internal_error", "const", "checked condition received a non-Bool value"}}

def constructor_in(constructors: List<&2, M.Constructor>, +name: String) -> Maybe<&2, M.Constructor>:
  match constructors:
    case Nil{}:
      None{}
    case M.Constructor{+found, +payload, +fields} <> tail:
      Bool.pick(Maybe<&2, M.Constructor>, M.name_equal(found, name), Some{M.Constructor{found, payload, fields}}, constructor_in(tail, name))

def lookup_constructor(data_types: List<&2, M.DataType>, +name: String) -> Maybe<&2, M.Constructor>:
  match data_types:
    case Nil{}:
      None{}
    case M.DataType{identity, parameters, constructors} <> tail:
      Maybe.or(&2, M.Constructor, constructor_in(constructors, name), lookup_constructor(tail, name))

def constructor_value(constructor: Maybe<&2, M.Constructor>, name: String) -> Result<&2, &2, M.Diagnostic, Value>:
  match constructor:
    case None{}:
      Fail{M.Diagnostic{"internal_error", name, "const evaluator lost a checked constructor"}}
    case Some{M.Constructor{found, None{}, fields}}:
      Done{DataValue{found, None{}}}
    case Some{M.Constructor{found, Some{payload}, fields}}:
      Done{ConstructorFunctionValue{found}}

def application(callee: Value, argument: Value, +context: Context) -> Result<&2, &2, M.Diagnostic, Application>:
  match callee:
    case FunctionValue{name}:
      do Result<&2, &2, M.Diagnostic, Application>:
        +function : M.Function <- lookup_function(context_functions(context), name)
        return BodyApplication{ScopedExpr{function_body(function), function_context(function, argument, context)}}
    case ClosureValue{identity, parameter, body, environment}:
      Done{BodyApplication{ScopedExpr{body, with_local(with_locals(context, environment), parameter, argument)}}}
    case ConstructorFunctionValue{constructor}:
      Done{ValueApplication{DataValue{constructor, Some{argument}}}}
    case OperationValue{identity}:
      Done{OperationApplication{identity, argument}}
    case StateReadValue{slot}:
      Done{StateReadApplication{slot}}
    case StateWriteValue{slot}:
      Done{StateWriteApplication{slot, argument}}
    case _:
      Fail{M.Diagnostic{"internal_error", "const", "checked application received a non-function value"}}

def provider_application(matches: Bool, identity: M.TypeId, implementation: Value, argument: Value, context: Context) -> Result<&2, &2, M.Diagnostic, Application>:
  match matches:
    case True{}:
      application(implementation, argument, context)
    case False{}:
      Done{OperationApplication{identity, argument}}

# A handler executes outside its own installation, including intervening inner
# handlers. Operation-valued implementations can forward along the same finite
# stack without manufacturing evaluator expressions or capturing dynamic scope.
def resolve_application(providers: List<&2, Provider<Value>>, call: Application, +context: Context) -> Result<&2, &2, M.Diagnostic, Application>:
  match providers call:
    case _ BodyApplication{scope}:
      Done{BodyApplication{scope}}
    case _ ValueApplication{value}:
      Done{ValueApplication{value}}
    case _ StateReadApplication{slot}:
      Done{StateReadApplication{slot}}
    case _ StateWriteApplication{slot, value}:
      Done{StateWriteApplication{slot, value}}
    case Nil{} OperationApplication{identity, argument}:
      Fail{M.Diagnostic{"const_effect", M.type_id_show(identity), "compile-time operation has no enclosing provider"}}
    case Provider{found, implementation} <> +tail OperationApplication{+identity, argument}:
      +scope = with_providers(context, tail)
      do Result<&2, &2, M.Diagnostic, Application>:
        next : Application <- provider_application(M.type_id_equal(found, identity), identity, implementation, argument, scope)
        resolve_application(tail, next, scope)

def operation_contains(operations: List<&2, M.TypeId>, +identity: M.TypeId) -> Bool:
  match operations:
    case Nil{}:
      False{}
    case found <> tail:
      Bool.or(M.type_id_equal(found, identity), operation_contains(tail, identity))

def unique_operations(operations: List<&2, M.TypeId>, +reversed: List<&2, M.TypeId>) -> List<&2, M.TypeId>:
  match operations:
    case Nil{}:
      List.reverse(&2, M.TypeId, reversed)
    case +identity <> tail:
      unique_operations(tail, Bool.pick(List<&2, M.TypeId>, operation_contains(reversed, identity), reversed, identity <> reversed))

def describe_row(row: M.EffectRow, name: String) -> Result<&2, &2, M.Diagnostic, Value>:
  match row:
    case M.EffectRow{operations, M.ClosedRow{}}:
      Done{EffectSetValue{unique_operations(operations, Nil{})}}
    case _:
      Fail{M.Diagnostic{"open_effect_row", name, "effect descriptors require a closed function effect row"}}

def describe_function(found: Bool, signature: M.Signature, name: String, fallback: Unit -> Result<&2, &2, M.Diagnostic, Value>) -> Result<&2, &2, M.Diagnostic, Value>:
  match found:
    case False{}:
      fallback(Unit{})
    case True{}:
      M.Signature{function_name, parameter, result, variables, row} = signature
      describe_row(row, name)

def function_effects(functions: List<&2, M.CheckedFunction>, +name: String) -> Result<&2, &2, M.Diagnostic, Value>:
  match functions:
    case Nil{}:
      Fail{M.Diagnostic{"internal_error", name, "const evaluator lost checked function effect metadata"}}
    case M.CheckedFunction{M.Function{found, exported, parameter, parameter_type, result_type, body}, signature, effects} <> tail:
      describe_function(M.name_equal(found, name), signature, name, ignored => function_effects(tail, name))

def effect_has(set: Value, operation: Value, remaining: Budget) -> Result<&2, &2, M.Diagnostic, Evaluation>:
  match set operation:
    case EffectSetValue{operations} EffectDescriptorValue{identity}:
      Done{Evaluation{BoolValue{operation_contains(operations, identity)}, remaining}}
    case _ _:
      Fail{M.Diagnostic{"internal_error", "const", "checked effect membership received values of the wrong type"}}

def effect_count(set: Value, remaining: Budget) -> Result<&2, &2, M.Diagnostic, Evaluation>:
  match set:
    case EffectSetValue{operations}:
      Done{Evaluation{U32Value{U32.from_nat(List.length(&2, M.TypeId, operations))}, remaining}}
    case _:
      Fail{M.Diagnostic{"internal_error", "const", "checked effect count received a non-set value"}}

def effect_same(left: Value, right: Value, remaining: Budget) -> Result<&2, &2, M.Diagnostic, Evaluation>:
  match left right:
    case EffectDescriptorValue{a} EffectDescriptorValue{b}:
      Done{Evaluation{BoolValue{M.type_id_equal(a, b)}, remaining}}
    case _ _:
      Fail{M.Diagnostic{"internal_error", "const", "checked effect equality received non-descriptor values"}}

# Continuations are affine Bend functions, not Blot closures. They keep block
# exits explicit without duplicating expression continuations or charging fuel
# for evaluator bookkeeping.
def continue_value(evaluation: Evaluation, continuation: Value -> Budget -> Result<&2, &2, M.Diagnostic, Evaluation>) -> Result<&2, &2, M.Diagnostic, Evaluation>:
  match evaluation:
    case Evaluation{ReturnValue{label, value}, remaining}:
      Done{Evaluation{ReturnValue{label, value}, remaining}}
    case Evaluation{value, remaining}:
      continuation(value, remaining)

def state_cell(cells: List<&2, StateCell>, +wanted: Nat) -> Result<&2, &2, M.Diagnostic, Value>:
  match cells:
    case Nil{}:
      Fail{M.Diagnostic{"internal_error", "state", "state operation escaped its resolver scope"}}
    case StateCell{+slot, value} <> tail:
      Bool.pick(Result<&2, &2, M.Diagnostic, Value>, Nat.is_eq(slot, wanted), Done{value}, state_cell(tail, wanted))

def replace_state(cells: List<&2, StateCell>, +wanted: Nat, +replacement: Value) -> Result<&2, &2, M.Diagnostic, List<&2, StateCell>>:
  match cells:
    case Nil{}:
      Fail{M.Diagnostic{"internal_error", "state", "state operation escaped its resolver scope"}}
    case StateCell{+slot, value} <> +tail:
      Bool.pick(Result<&2, &2, M.Diagnostic, List<&2, StateCell>>, Nat.is_eq(slot, wanted), Done{StateCell{slot, replacement} <> tail},
        do Result<&2, &2, M.Diagnostic, List<&2, StateCell>>:
          next : List<&2, StateCell> <- replace_state(tail, wanted, replacement)
          return StateCell{slot, value} <> next)

def read_state(slot: Nat, +budget: Budget) -> Result<&2, &2, M.Diagnostic, Evaluation>:
  Budget{remaining, cells} = budget
  do Result<&2, &2, M.Diagnostic, Evaluation>:
    value : Value <- state_cell(cells, slot)
    return Evaluation{value, budget}

def write_state(slot: Nat, value: Value, budget: Budget) -> Result<&2, &2, M.Diagnostic, Evaluation>:
  Budget{remaining, cells} = budget
  do Result<&2, &2, M.Diagnostic, Evaluation>:
    next : List<&2, StateCell> <- replace_state(cells, slot, value)
    return Evaluation{UnitValue{}, Budget{remaining, next}}

def state_scope(read: M.TypeId, write: M.TypeId, +slot: Nat, context: Context) -> Context:
  Context{constants, functions, locals, data_types, providers, checked_functions} = context
  Context{constants, functions, locals, data_types, Provider{read, StateReadValue{slot}} <> Provider{write, StateWriteValue{slot}} <> providers, checked_functions}

def state_result(state: Value, result: Value) -> Value:
  match result:
    case ReturnValue{label, value}:
      ReturnValue{label, value}
    case value:
      ProductValue{[state, value]}

def finish_state_scope(evaluation: Evaluation, +wanted: Nat) -> Result<&2, &2, M.Diagnostic, Evaluation>:
  match evaluation:
    case Evaluation{result, Budget{remaining, StateCell{+slot, state} <> cells}}:
      Bool.pick(Result<&2, &2, M.Diagnostic, Evaluation>, Nat.is_eq(slot, wanted), Done{Evaluation{state_result(state, result), Budget{remaining, cells}}}, Fail{M.Diagnostic{"internal_error", "state", "resolver scopes completed out of order"}})
    case _:
      Fail{M.Diagnostic{"internal_error", "state", "resolver lost its state before completion"}}

def complete_application(application: Application, remaining: Budget, continuation: M.Expr -> Context -> Budget -> Result<&2, &2, M.Diagnostic, Evaluation>) -> Result<&2, &2, M.Diagnostic, Evaluation>:
  match application:
    case ValueApplication{value}:
      Done{Evaluation{value, remaining}}
    case BodyApplication{ScopedExpr{expression, context}}:
      continuation(expression, context, remaining)
    case OperationApplication{identity, argument}:
      Fail{M.Diagnostic{"internal_error", M.type_id_show(identity), "const evaluator failed to resolve an operation application"}}
    case StateReadApplication{slot}:
      read_state(slot, remaining)
    case StateWriteApplication{slot, value}:
      write_state(slot, value, remaining)

def complete_scope(scope: ScopedExpr, remaining: Budget, continuation: M.Expr -> Context -> Budget -> Result<&2, &2, M.Diagnostic, Evaluation>) -> Result<&2, &2, M.Diagnostic, Evaluation>:
  ScopedExpr{expression, context} = scope
  continuation(expression, context, remaining)

def pattern_step(work: PatternWork, +pending: List<&2, PatternWork>, +reversed: List<&2, Binding<Value>>) -> Result<&2, &2, M.Diagnostic, PatternProgress>:
  match work:
    case PatternValue{M.WildcardPattern{}, value}:
      Done{PatternPending{pending, reversed}}
    case PatternValue{M.BindingPattern{name}, value}:
      Done{PatternPending{pending, Binding{name, value} <> reversed}}
    case PatternValue{M.UnitPattern{}, UnitValue{}}:
      Done{PatternPending{pending, reversed}}
    case PatternValue{M.U32Pattern{expected}, U32Value{actual}}:
      Done{Bool.pick(PatternProgress, U32.is_eq(expected, actual), PatternPending{pending, reversed}, PatternRejected{})}
    case PatternValue{M.BoolPattern{expected}, BoolValue{actual}}:
      Done{Bool.pick(PatternProgress, Bool.not(Bool.xor(expected, actual)), PatternPending{pending, reversed}, PatternRejected{})}
    case PatternValue{M.ConstructorPattern{constructor, None{}}, DataValue{found, None{}}}:
      Done{Bool.pick(PatternProgress, M.name_equal(constructor, found), PatternPending{pending, reversed}, PatternRejected{})}
    case PatternValue{M.ConstructorPattern{constructor, Some{nested}}, DataValue{found, Some{payload}}}:
      Done{PatternPending{ConstructorPayload{M.name_equal(constructor, found), nested, payload} <> pending, reversed}}
    case PatternValue{M.ProductPattern{first <> second <> tail}, ProductValue{elements}}:
      Done{PatternPending{ProductPatterns{first <> second <> tail, elements} <> pending, reversed}}
    case PatternValue{M.ProductPattern{Nil{}}, value}:
      Fail{M.Diagnostic{"product_arity", "const", "a product pattern requires at least two elements"}}
    case PatternValue{M.ProductPattern{head <> Nil{}}, value}:
      Fail{M.Diagnostic{"product_arity", "const", "a product pattern requires at least two elements"}}
    case PatternValue{pattern, value}:
      Done{PatternRejected{}}
    case ConstructorPayload{False{}, pattern, value}:
      Done{PatternRejected{}}
    case ConstructorPayload{True{}, pattern, value}:
      Done{PatternPending{PatternValue{pattern, value} <> pending, reversed}}
    case ProductPatterns{Nil{}, Nil{}}:
      Done{PatternPending{pending, reversed}}
    case ProductPatterns{head <> tail, value <> rest}:
      Done{PatternPending{PatternValue{head, value} <> ProductPatterns{tail, rest} <> pending, reversed}}
    case ProductPatterns{patterns, values}:
      Done{PatternRejected{}}

# The queue bounds total pattern work without using the host stack per field.
# A mismatch discards both partial bindings and every pending sibling at once.
def match_pattern_queue(fuel: Nat, progress: Result<&2, &2, M.Diagnostic, PatternProgress>) -> Result<&2, &2, M.Diagnostic, Maybe<&2, List<&2, Binding<Value>>>>:
  match fuel progress:
    case _ Fail{error}:
      Fail{error}
    case _ Done{PatternRejected{}}:
      Done{None{}}
    case _ Done{PatternPending{Nil{}, reversed}}:
      Done{Some{List.reverse(&2, Binding<Value>, reversed)}}
    case 0n Done{PatternPending{pending, reversed}}:
      Fail{M.Diagnostic{"pattern_complexity", "const", "constant pattern matching exceeds compiler traversal limit"}}
    case 1n+remaining Done{PatternPending{work <> pending, reversed}}:
      match_pattern_queue(remaining, pattern_step(work, pending, reversed))

def match_pattern_work(fuel: Nat, work: PatternWork) -> Result<&2, &2, M.Diagnostic, Maybe<&2, List<&2, Binding<Value>>>>:
  match_pattern_queue(fuel, Done{PatternPending{[work], Nil{}}})

def match_pattern(pattern: M.Pattern, value: Value) -> Result<&2, &2, M.Diagnostic, Maybe<&2, List<&2, Binding<Value>>>>:
  match_pattern_work(U32.to_nat(65536), PatternValue{pattern, value})

def prepend_collected_value(value: Value, collected: Value, remaining: Budget) -> Result<&2, &2, M.Diagnostic, Evaluation>:
  match collected:
    case MatchValuesValue{values}:
      Done{Evaluation{MatchValuesValue{value <> values}, remaining}}
    case _:
      Fail{M.Diagnostic{"internal_error", "const", "const evaluator lost an expression collection tail"}}

def product_value(collected: Value, remaining: Budget) -> Result<&2, &2, M.Diagnostic, Evaluation>:
  match collected:
    case MatchValuesValue{elements}:
      Done{Evaluation{ProductValue{elements}, remaining}}
    case _:
      Fail{M.Diagnostic{"internal_error", "const", "const evaluator lost collected product elements"}}

def project_elements(elements: List<&2, Value>, index: Nat, remaining: Budget) -> Result<&2, &2, M.Diagnostic, Evaluation>:
  match elements index:
    case Nil{} _:
      Fail{M.Diagnostic{"product_index", "const", "product projection index is outside the element range"}}
    case head <> tail 0n:
      Done{Evaluation{head, remaining}}
    case head <> tail 1n+rest:
      project_elements(tail, rest, remaining)

def project(value: Value, index: Nat, remaining: Budget) -> Result<&2, &2, M.Diagnostic, Evaluation>:
  match value:
    case ProductValue{elements}:
      project_elements(elements, index, remaining)
    case _:
      Fail{M.Diagnostic{"type_mismatch", "const", "product projection requires a product value"}}

def array_value(collected: Value, remaining: Budget) -> Result<&2, &2, M.Diagnostic, Evaluation>:
  match collected:
    case MatchValuesValue{elements}:
      Done{Evaluation{ArrayValue{elements}, remaining}}
    case _:
      Fail{M.Diagnostic{"internal_error", "const", "const evaluator lost collected array elements"}}

# Each filled element consumes one evaluation step; check the arena limit before
# converting a potentially huge U32 count to a structural natural.
def array_fill_elements(count: Nat, +value: Value, elements: List<&2, Value>, steps: Budget) -> Result<&2, &2, M.Diagnostic, Evaluation>:
  match count steps:
    case 0n _:
      Done{Evaluation{ArrayValue{elements}, steps}}
    case 1n+rest Budget{0n, cells}:
      Fail{M.Diagnostic{"const_budget", "const", "compile-time evaluation exhausted its step budget while filling an array"}}
    case 1n+rest Budget{1n+remaining, cells}:
      remaining = {Budget{remaining, cells} : Budget}
      array_fill_elements(rest, value, value <> elements, remaining)

def array_fill_checked(allowed: Bool, count: U32, value: Value, remaining: Budget) -> Result<&2, &2, M.Diagnostic, Evaluation>:
  match allowed:
    case False{}:
      Fail{M.Diagnostic{"backend_limit", "array", "array length exceeds the 16 MiB bootstrap arena"}}
    case True{}:
      array_fill_elements(U32.to_nat(count), value, Nil{}, remaining)

def array_fill(count: Value, value: Value, remaining: Budget) -> Result<&2, &2, M.Diagnostic, Evaluation>:
  match count:
    case U32Value{+length}:
      array_fill_checked(U32.is_lt(length, 4194304), length, value, remaining)
    case _:
      Fail{M.Diagnostic{"type_mismatch", "const", "array fill requires a U32 count"}}

def array_generate_count_checked(allowed: Bool, count: U32) -> Result<&2, &2, M.Diagnostic, Nat>:
  match allowed:
    case False{}:
      Fail{M.Diagnostic{"backend_limit", "array", "array length exceeds the 16 MiB bootstrap arena"}}
    case True{}:
      Done{U32.to_nat(count)}

def array_generate_count(count: Value) -> Result<&2, &2, M.Diagnostic, Nat>:
  match count:
    case U32Value{+length}:
      array_generate_count_checked(U32.is_lt(length, 4194304), length)
    case _:
      Fail{M.Diagnostic{"type_mismatch", "const", "array generation requires a U32 count"}}

def array_bounds() -> M.Diagnostic:
  M.Diagnostic{"array_bounds", "const", "array index is outside the element range"}

def array_get_elements(elements: List<&2, Value>, index: Nat, remaining: Budget) -> Result<&2, &2, M.Diagnostic, Evaluation>:
  match elements index:
    case Nil{} _:
      Fail{array_bounds()}
    case head <> tail 0n:
      Done{Evaluation{head, remaining}}
    case head <> tail 1n+rest:
      array_get_elements(tail, rest, remaining)

def array_get(array: Value, index: Value, remaining: Budget) -> Result<&2, &2, M.Diagnostic, Evaluation>:
  match array index:
    case ArrayValue{elements} U32Value{offset}:
      array_get_elements(elements, U32.to_nat(offset), remaining)
    case _ _:
      Fail{M.Diagnostic{"type_mismatch", "const", "array indexing requires an array and a U32 index"}}

# Copying an immutable array is work even when its elements came from a local.
# Charge the whole copy before publishing its successor; old values stay intact.
def array_copy(elements: List<&2, Value>, +index: Nat, +replacement: Value, +offset: Nat, reversed: List<&2, Value>, steps: Budget) -> Result<&2, &2, M.Diagnostic, Evaluation>:
  match elements steps:
    case Nil{} _:
      Done{Evaluation{ArrayValue{List.reverse(&2, Value, reversed)}, steps}}
    case head <> tail Budget{0n, cells}:
      Fail{M.Diagnostic{"const_budget", "const", "compile-time evaluation exhausted its step budget while copying an array"}}
    case head <> tail Budget{1n+remaining, cells}:
      remaining = {Budget{remaining, cells} : Budget}
      array_copy(tail, index, replacement, 1n+offset, Bool.pick(Value, Nat.is_eq(index, offset), replacement, head) <> reversed, remaining)

def array_set_checked(valid: Bool, elements: List<&2, Value>, index: Nat, replacement: Value, steps: Budget) -> Result<&2, &2, M.Diagnostic, Evaluation>:
  match valid:
    case False{}:
      Fail{array_bounds()}
    case True{}:
      array_copy(elements, index, replacement, 0n, Nil{}, steps)

def array_set(array: Value, index: Value, replacement: Value, remaining: Budget) -> Result<&2, &2, M.Diagnostic, Evaluation>:
  match array index:
    case ArrayValue{+elements} U32Value{offset}:
      +index = U32.to_nat(offset)
      array_set_checked(Nat.is_lt(index, List.length(&2, Value, elements)), elements, index, replacement, remaining)
    case _ _:
      Fail{M.Diagnostic{"type_mismatch", "const", "array update requires an array and a U32 index"}}

def array_length_checked(valid: Bool, count: Nat, remaining: Budget) -> Result<&2, &2, M.Diagnostic, Evaluation>:
  match valid:
    case False{}:
      Fail{M.Diagnostic{"array_size", "const", "array length exceeds the U32 index range"}}
    case True{}:
      Done{Evaluation{U32Value{U32.from_nat(count)}, remaining}}

def array_length(array: Value, remaining: Budget) -> Result<&2, &2, M.Diagnostic, Evaluation>:
  match array:
    case ArrayValue{elements}:
      +count = List.length(&2, Value, elements)
      array_length_checked(Nat.is_le(count, U32.to_nat(4294967295)), count, remaining)
    case _:
      Fail{M.Diagnostic{"type_mismatch", "const", "array length requires an array value"}}

def guard_scope(bindings: Maybe<&2, List<&2, Binding<Value>>>, body: M.Expr, alternative: M.Expr, context: Context) -> ScopedExpr:
  match bindings:
    case Some{locals}:
      ScopedExpr{body, with_bindings(context, locals)}
    case None{}:
      ScopedExpr{alternative, context}

def complete_block(evaluation: Evaluation, +label: Nat) -> Evaluation:
  match evaluation:
    case Evaluation{ReturnValue{+target, +value}, +remaining}:
      Bool.pick(Evaluation, Nat.is_eq(target, label), Evaluation{value, remaining}, Evaluation{ReturnValue{target, value}, remaining})
    case Evaluation{value, remaining}:
      Evaluation{value, remaining}

def complete_definition(evaluation: Evaluation) -> Result<&2, &2, M.Diagnostic, Evaluation>:
  match evaluation:
    case Evaluation{ReturnValue{label, value}, remaining}:
      Fail{M.Diagnostic{"internal_error", "const", "a checked return escaped its function or constant"}}
    case Evaluation{PatternBindingsValue{bindings}, remaining}:
      Fail{M.Diagnostic{"internal_error", "const", "internal pattern bindings escaped their evaluator scope"}}
    case Evaluation{MatchValuesValue{values}, remaining}:
      Fail{M.Diagnostic{"internal_error", "const", "internal match values escaped their evaluator scope"}}
    case Evaluation{value, remaining}:
      Done{Evaluation{value, remaining}}

def collected_match_values(collected: Value) -> Result<&2, &2, M.Diagnostic, List<&2, Value>>:
  match collected:
    case MatchValuesValue{values}:
      Done{values}
    case _:
      Fail{M.Diagnostic{"internal_error", "const", "const evaluator lost collected match values"}}

def collected_pattern_bindings(collected: Value) -> Result<&2, &2, M.Diagnostic, Maybe<&2, List<&2, Binding<Value>>>>:
  match collected:
    case PatternBindingsValue{bindings}:
      Done{bindings}
    case _:
      Fail{M.Diagnostic{"internal_error", "const", "const evaluator lost pattern bindings"}}

def value_pattern(value: Value) -> Result<&2, &2, M.Diagnostic, M.Pattern>:
  match value:
    case U32Value{number}:
      Done{M.U32Pattern{number}}
    case BoolValue{boolean}:
      Done{M.BoolPattern{boolean}}
    case _:
      Fail{M.Diagnostic{"value_pattern_type", "const", "value patterns require U32 or Bool"}}

# Pattern references share the expression evaluator and its step budget.
# Pattern bookkeeping has separate fuel so it does not consume expression depth.
# A mismatch discards partial bindings before evaluating any later reference.
def evaluate_work(+depth: Nat, +matching_fuel: Nat, pending: List<&2, M.Expr>, +steps: Budget, work: EvaluationWork, +context: Context) -> Result<&2, &2, M.Diagnostic, Evaluation>:
  match depth matching_fuel pending steps work:
    case _ 1n+scope_rest _ Budget{remaining, +cells} HandleValue{StateProviderValue{read, write, initial}, body}:
      +slot = List.length(&2, StateCell, cells)
      do Result<&2, &2, M.Diagnostic, Evaluation>:
        result : Evaluation <- evaluate_work(depth, scope_rest, Nil{}, Budget{remaining, StateCell{slot, initial} <> cells}, Expression{body}, state_scope(read, write, slot, context))
        finish_state_scope(result, slot)
    case _ 1n+scope_rest _ _ HandleValue{provider, body}:
      do Result<&2, &2, M.Diagnostic, Evaluation>:
        scope : Context <- with_provider(provider, context)
        evaluate_work(depth, scope_rest, Nil{}, steps, Expression{body}, scope)
    case _ 0n _ _ HandleValue{provider, body}:
      Fail{M.Diagnostic{"const_budget", "state", "compile-time evaluation exhausted its scope depth"}}
    case 1n+limit _ _ _ ForBounds{index, U32Value{+start}, U32Value{+end}, state, initial, body}:
      evaluate_work(limit, Bool.pick(Nat, U32.is_lt(start, end), Nat.sub(U32.to_nat(end), U32.to_nat(start)), 0n), Nil{}, steps, ForIterations{index, start, state, initial, body}, context)
    case _ _ _ _ ForBounds{index, start, end, state, initial, body}:
      Fail{M.Diagnostic{"internal_error", "for", "checked loop lost its U32 bounds"}}
    case _ 0n _ _ ForIterations{index, current, state, value, body}:
      Done{Evaluation{value, steps}}
    case _ 1n+rest _ Budget{0n, cells} ForIterations{index, current, state, value, body}:
      Fail{M.Diagnostic{"const_budget", "for", "compile-time evaluation exhausted its step budget in a loop"}}
    case _ 1n+rest _ Budget{1n+remaining, cells} ForIterations{+index, +current, +state, value, +body}:
      remaining = {Budget{remaining, cells} : Budget}
      do Result<&2, &2, M.Diagnostic, Evaluation>:
        checked : Evaluation <- evaluate_work(depth, rest, Nil{}, remaining, Expression{body}, with_local(with_local(context, index, U32Value{current}), state, value))
        continue_value(checked, successor => next_steps =>
          evaluate_work(depth, rest, Nil{}, next_steps, ForIterations{index, (current + 1 : U32), state, successor, body}, context))
    case _ _ _ Budget{0n, cells} ForeverIterations{state, value, body}:
      Fail{M.Diagnostic{"const_budget", "for ever", "compile-time evaluation exhausted its step budget in an unbounded loop"}}
    case 1n+limit _ _ Budget{1n+remaining, cells} ForeverIterations{+state, value, +body}:
      remaining = {Budget{remaining, cells} : Budget}
      do Result<&2, &2, M.Diagnostic, Evaluation>:
        checked : Evaluation <- evaluate_work(limit, matching_fuel, Nil{}, remaining, Expression{body}, with_local(context, state, value))
        continue_value(checked, successor => next_steps =>
          evaluate_work(limit, matching_fuel, Nil{}, next_steps, ForeverIterations{state, successor, body}, context))
    case 0n _ _ _ ForeverIterations{state, value, body}:
      Fail{M.Diagnostic{"const_budget", "for ever", "compile-time evaluation exhausted its structural depth in an unbounded loop"}}
    case _ 0n _ _ GenerateElements{generator, index, reversed}:
      Done{Evaluation{ArrayValue{List.reverse(&2, Value, reversed)}, steps}}
    case _ 1n+rest _ Budget{0n, cells} GenerateElements{generator, index, reversed}:
      Fail{M.Diagnostic{"const_budget", "const", "compile-time evaluation exhausted its step budget while generating an array"}}
    case _ 1n+rest _ Budget{1n+remaining, cells} GenerateElements{+generator, +index, +reversed}:
      remaining = {Budget{remaining, cells} : Budget}
      do Result<&2, &2, M.Diagnostic, Evaluation>:
        call : Application <- application(generator, U32Value{index}, context)
        resolved : Application <- resolve_application(context_providers(context), call, context)
        generated : Evaluation <- complete_application(resolved, remaining, body => scope => body_steps =>
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            result : Evaluation <- evaluate_work(depth, rest, Nil{}, body_steps, Expression{body}, scope)
            complete_definition(result))
        continue_value(generated, element => next_steps =>
          evaluate_work(depth, rest, Nil{}, next_steps, GenerateElements{generator, (index + 1 : U32), element <> reversed}, context))
    case _ _ _ _ MatchPatterns{fuel, Fail{error}}:
      Fail{error}
    case _ _ _ _ MatchPatterns{fuel, Done{PatternRejected{}}}:
      Done{Evaluation{PatternBindingsValue{None{}}, steps}}
    case _ _ _ _ MatchPatterns{fuel, Done{PatternPending{Nil{}, reversed}}}:
      Done{Evaluation{PatternBindingsValue{Some{List.reverse(&2, Binding<Value>, reversed)}}, steps}}
    case _ _ _ _ MatchPatterns{0n, Done{PatternPending{pending_patterns, reversed}}}:
      Fail{M.Diagnostic{"pattern_complexity", "const", "constant pattern matching exceeds compiler traversal limit"}}
    case _ 1n+matching_rest _ _ MatchPatterns{1n+fuel, Done{PatternPending{PatternValue{M.ValuePattern{reference}, actual} <> remaining_patterns, reversed}}}:
      do Result<&2, &2, M.Diagnostic, Evaluation>:
        +expected : Evaluation <- evaluate_work(depth, matching_rest, Nil{}, steps, Expression{M.reference_expr(reference)}, context)
        literal : M.Pattern <- value_pattern(eval_value(expected))
        evaluate_work(depth, matching_rest, Nil{}, eval_budget(expected), MatchPatterns{fuel, pattern_step(PatternValue{literal, actual}, remaining_patterns, reversed)}, context)
    case _ 1n+matching_rest _ _ MatchPatterns{1n+fuel, Done{PatternPending{head <> remaining_patterns, reversed}}}:
      evaluate_work(depth, matching_rest, Nil{}, steps, MatchPatterns{fuel, pattern_step(head, remaining_patterns, reversed)}, context)
    case _ _ _ _ MatchArms{Nil{}, values}:
      Fail{M.Diagnostic{"internal_error", "const", "checked match has no matching arm"}}
    case _ 1n+matching_rest _ _ MatchArms{M.MatchArm{patterns, body} <> tail, +values}:
      do Result<&2, &2, M.Diagnostic, Evaluation>:
        +matched : Evaluation <- evaluate_work(depth, matching_rest, Nil{}, steps, MatchPatterns{U32.to_nat(65536), Done{PatternPending{[ProductPatterns{patterns, values}], Nil{}}}}, context)
        evaluate_work(depth, matching_rest, Nil{}, eval_budget(matched), MatchSelected{eval_value(matched), body, tail, values}, context)
    case _ 1n+matching_rest _ _ MatchSelected{PatternBindingsValue{Some{locals}}, body, arms, values}:
      evaluate_work(depth, matching_rest, Nil{}, steps, Expression{body}, with_bindings(context, locals))
    case _ 1n+matching_rest _ _ MatchSelected{PatternBindingsValue{None{}}, body, arms, values}:
      evaluate_work(depth, matching_rest, Nil{}, steps, MatchArms{arms, values}, context)
    case _ 0n _ _ MatchPatterns{fuel, progress}:
      Fail{M.Diagnostic{"pattern_complexity", "const", "constant pattern matching exceeds compiler traversal limit"}}
    case _ 0n _ _ MatchArms{arms, values}:
      Fail{M.Diagnostic{"pattern_complexity", "const", "constant pattern matching exceeds compiler traversal limit"}}
    case _ 0n _ _ MatchSelected{bindings, body, arms, values}:
      Fail{M.Diagnostic{"pattern_complexity", "const", "constant pattern matching exceeds compiler traversal limit"}}
    case _ _ _ _ MatchSelected{other, body, arms, values}:
      Fail{M.Diagnostic{"internal_error", "const", "const evaluator lost pattern bindings"}}
    case _ _ Nil{} _ CollectValues{}:
      Done{Evaluation{MatchValuesValue{Nil{}}, steps}}
    case _ _ head <> +tail _ CollectValues{}:
      do Result<&2, &2, M.Diagnostic, Evaluation>:
        checked : Evaluation <- evaluate_work(depth, matching_fuel, tail, steps, Expression{head}, context)
        continue_value(checked, value => next_steps =>
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            collected : Evaluation <- evaluate_work(depth, matching_fuel, tail, next_steps, CollectValues{}, context)
            continue_value(collected, values => remaining => prepend_collected_value(value, values, remaining)))
    case 0n _ _ _ Expression{expression}:
      Fail{M.Diagnostic{"const_budget", "const", "compile-time evaluation exhausted its step budget"}}
    case _ _ _ Budget{0n, cells} Expression{expression}:
      Fail{M.Diagnostic{"const_budget", "const", "compile-time evaluation exhausted its step budget"}}
    case 1n+limit _ _ Budget{1n+remaining, cells} Expression{expression}:
      match expression:
        # Budget guards must reduce without inspecting symbolic expressions in proofs.
        case M.RuntimeInitExpr{value}:
          Fail{M.Diagnostic{"const_runtime_dependency", "let", "a const initializer cannot read a top-level let value initialized at module startup"}}
        case M.UnitExpr{}:
          Done{Evaluation{UnitValue{}, spend_budget(steps)}}
        case M.U32Expr{value}:
          Done{Evaluation{U32Value{value}, spend_budget(steps)}}
        case M.F32Expr{value}:
          Done{Evaluation{F32Value{value}, spend_budget(steps)}}
        case M.BoolExpr{value}:
          Done{Evaluation{BoolValue{value}, spend_budget(steps)}}
        case M.PanicExpr{message}:
          Fail{M.Diagnostic{"const_panic", "const", message}}
        case M.LocalExpr{name}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            value : Value <- lookup_local(context_locals(context), name)
            return Evaluation{value, spend_budget(steps)}
        case M.ConstantExpr{name}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            value : M.Expr <- lookup_constant(context_constants(context), name)
            evaluate_work(limit, U32.to_nat(65536), Nil{}, spend_budget(steps), Expression{value}, without_locals(context))
        case M.FunctionExpr{+name}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            function : M.Function <- lookup_function(context_functions(context), name)
            function_value_allowed(function_body(function), name, spend_budget(steps))
        case M.OperationExpr{identity}:
          Done{Evaluation{OperationValue{identity}, spend_budget(steps)}}
        case M.SpecializeOperationExpr{template, arguments, body}:
          Fail{M.Diagnostic{"unspecialized_effect", "const", "effect instance reached evaluation before specialization"}}
        case M.OperationDescriptorExpr{identity}:
          Done{Evaluation{EffectDescriptorValue{identity}, spend_budget(steps)}}
        case M.FunctionEffectsExpr{callee}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            value : Value <- function_effects(context_checked_functions(context), callee)
            return Evaluation{value, spend_budget(steps)}
        case M.ConstructorRefExpr{+constructor}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            value : Value <- constructor_value(lookup_constructor(context_data_types(context), constructor), constructor)
            return Evaluation{value, spend_budget(steps)}
        case M.ConstructExpr{constructor, None{}}:
          Done{Evaluation{DataValue{constructor, None{}}, spend_budget(steps)}}
        case M.ConstructExpr{constructor, Some{payload}}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            checked : Evaluation <- evaluate_work(limit, U32.to_nat(65536), Nil{}, spend_budget(steps), Expression{payload}, context)
            continue_value(checked, value => next_steps => Done{Evaluation{DataValue{constructor, Some{value}}, next_steps}})
        case M.ProductExpr{first <> second <> tail}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            checked : Evaluation <- evaluate_work(limit, U32.to_nat(65536), first <> second <> tail, spend_budget(steps), CollectValues{}, context)
            continue_value(checked, collected => next_steps => product_value(collected, next_steps))
        case M.ProductExpr{elements}:
          Fail{M.Diagnostic{"product_arity", "const", "products require at least two elements; Unit is a distinct value"}}
        case M.ProjectExpr{value, index}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            checked : Evaluation <- evaluate_work(limit, U32.to_nat(65536), Nil{}, spend_budget(steps), Expression{value}, context)
            continue_value(checked, product => next_steps => project(product, index, next_steps))
        case M.ArrayExpr{elements}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            checked : Evaluation <- evaluate_work(limit, U32.to_nat(65536), elements, spend_budget(steps), CollectValues{}, context)
            continue_value(checked, collected => next_steps => array_value(collected, next_steps))
        case M.ForExpr{index, start, end, state, initial, body}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            checked : Evaluation <- evaluate_work(limit, U32.to_nat(65536), Nil{}, spend_budget(steps), Expression{start}, context)
            continue_value(checked, first => end_steps =>
              do Result<&2, &2, M.Diagnostic, Evaluation>:
                bounded : Evaluation <- evaluate_work(limit, U32.to_nat(65536), Nil{}, end_steps, Expression{end}, context)
                continue_value(bounded, last => initial_steps =>
                  do Result<&2, &2, M.Diagnostic, Evaluation>:
                    prepared : Evaluation <- evaluate_work(limit, U32.to_nat(65536), Nil{}, initial_steps, Expression{initial}, context)
                    continue_value(prepared, value => next_steps =>
                      evaluate_work(limit, U32.to_nat(65536), Nil{}, next_steps, ForBounds{index, first, last, state, value, body}, context))))
        case M.ForeverExpr{state, initial, body}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            prepared : Evaluation <- evaluate_work(limit, U32.to_nat(65536), Nil{}, spend_budget(steps), Expression{initial}, context)
            continue_value(prepared, value => next_steps =>
              evaluate_work(limit, U32.to_nat(65536), Nil{}, next_steps, ForeverIterations{state, value, body}, context))
        case M.ArrayGenerateExpr{count, generator}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            checked : Evaluation <- evaluate_work(limit, U32.to_nat(65536), Nil{}, spend_budget(steps), Expression{count}, context)
            continue_value(checked, length => generator_steps =>
              do Result<&2, &2, M.Diagnostic, Evaluation>:
                prepared : Evaluation <- evaluate_work(limit, U32.to_nat(65536), Nil{}, generator_steps, Expression{generator}, context)
                continue_value(prepared, function => next_steps =>
                  do Result<&2, &2, M.Diagnostic, Evaluation>:
                    count : Nat <- array_generate_count(length)
                    evaluate_work(limit, count, Nil{}, next_steps, GenerateElements{function, 0, Nil{}}, context)))
        case M.ArrayFillExpr{count, value}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            checked : Evaluation <- evaluate_work(limit, U32.to_nat(65536), Nil{}, spend_budget(steps), Expression{count}, context)
            continue_value(checked, length => value_steps =>
              do Result<&2, &2, M.Diagnostic, Evaluation>:
                filled : Evaluation <- evaluate_work(limit, U32.to_nat(65536), Nil{}, value_steps, Expression{value}, context)
                continue_value(filled, element => next_steps => array_fill(length, element, next_steps)))
        case M.ArrayGetExpr{array, index}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            checked : Evaluation <- evaluate_work(limit, U32.to_nat(65536), Nil{}, spend_budget(steps), Expression{array}, context)
            continue_value(checked, value => index_steps =>
              do Result<&2, &2, M.Diagnostic, Evaluation>:
                indexed : Evaluation <- evaluate_work(limit, U32.to_nat(65536), Nil{}, index_steps, Expression{index}, context)
                continue_value(indexed, offset => next_steps => array_get(value, offset, next_steps)))
        case M.ArraySetExpr{array, index, value}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            checked : Evaluation <- evaluate_work(limit, U32.to_nat(65536), Nil{}, spend_budget(steps), Expression{array}, context)
            continue_value(checked, original => index_steps =>
              do Result<&2, &2, M.Diagnostic, Evaluation>:
                indexed : Evaluation <- evaluate_work(limit, U32.to_nat(65536), Nil{}, index_steps, Expression{index}, context)
                continue_value(indexed, offset => value_steps =>
                  do Result<&2, &2, M.Diagnostic, Evaluation>:
                    changed : Evaluation <- evaluate_work(limit, U32.to_nat(65536), Nil{}, value_steps, Expression{value}, context)
                    continue_value(changed, replacement => next_steps => array_set(original, offset, replacement, next_steps))))
        case M.AssociatedExpr{identity, dispatch, member, templates, left, right}:
          Fail{M.Diagnostic{"unresolved_associated", "const", "associated call reached evaluation before specialization"}}
        case M.GenericOperationExpr{identity, template, arguments}:
          Fail{M.Diagnostic{"unspecialized_effect", M.type_id_show(template), "generic effect operation reached evaluation before specialization"}}
        case M.ArrayLengthExpr{array}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            checked : Evaluation <- evaluate_work(limit, U32.to_nat(65536), Nil{}, spend_budget(steps), Expression{array}, context)
            continue_value(checked, value => next_steps => array_length(value, next_steps))
        case M.LambdaExpr{identity, +parameter, parameter_type, result_type, +body}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            names : List<&2, String> <- F.free(4096n, F.ExpressionWork{body, [parameter]})
            environment : List<&2, Binding<Value>> <- capture_environment(names, context_locals(context))
            return Evaluation{ClosureValue{identity, parameter, body, environment}, spend_budget(steps)}
        case M.StateProviderExpr{read, write, initial}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            checked : Evaluation <- evaluate_work(limit, U32.to_nat(65536), Nil{}, spend_budget(steps), Expression{initial}, context)
            continue_value(checked, value => next_steps => Done{Evaluation{StateProviderValue{read, write, value}, next_steps}})
        case M.ProviderExpr{identity, implementation}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            checked : Evaluation <- evaluate_work(limit, U32.to_nat(65536), Nil{}, spend_budget(steps), Expression{implementation}, context)
            continue_value(checked, value => next_steps => Done{Evaluation{ProviderValue{identity, value}, next_steps}})
        case M.HandleExpr{provider, body}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            checked : Evaluation <- evaluate_work(limit, U32.to_nat(65536), Nil{}, spend_budget(steps), Expression{provider}, context)
            continue_value(checked, value => next_steps =>
              evaluate_work(limit, U32.to_nat(65536), Nil{}, next_steps, HandleValue{value, body}, context))
        case M.ApplyExpr{callee, argument}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            checked : Evaluation <- evaluate_work(limit, U32.to_nat(65536), Nil{}, spend_budget(steps), Expression{callee}, context)
            continue_value(checked, function => argument_steps =>
              do Result<&2, &2, M.Diagnostic, Evaluation>:
                applied : Evaluation <- evaluate_work(limit, U32.to_nat(65536), Nil{}, argument_steps, Expression{argument}, context)
                continue_value(applied, value => call_steps =>
                  do Result<&2, &2, M.Diagnostic, Evaluation>:
                    call : Application <- application(function, value, context)
                    resolved : Application <- resolve_application(context_providers(context), call, context)
                    complete_application(resolved, call_steps, body => scope => body_steps =>
                      do Result<&2, &2, M.Diagnostic, Evaluation>:
                        result : Evaluation <- evaluate_work(limit, U32.to_nat(65536), Nil{}, body_steps, Expression{body}, scope)
                        complete_definition(result))))
        case M.CallExpr{callee, argument}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            checked : Evaluation <- evaluate_work(limit, U32.to_nat(65536), Nil{}, spend_budget(steps), Expression{argument}, context)
            continue_value(checked, value => next_steps =>
              do Result<&2, &2, M.Diagnostic, Evaluation>:
                +function : M.Function <- lookup_function(context_functions(context), callee)
                result : Evaluation <- evaluate_work(limit, U32.to_nat(65536), Nil{}, next_steps, Expression{function_body(function)}, function_context(function, value, context))
                complete_definition(result))
        case M.ScalarExpr{operator, left, right}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            checked : Evaluation <- evaluate_work(limit, U32.to_nat(65536), Nil{}, spend_budget(steps), Expression{left}, context)
            continue_value(checked, left_value => right_steps =>
              do Result<&2, &2, M.Diagnostic, Evaluation>:
                right_result : Evaluation <- evaluate_work(limit, U32.to_nat(65536), Nil{}, right_steps, Expression{right}, context)
                continue_value(right_result, right_value => next_steps => scalar(operator, left_value, right_value, next_steps)))
        case M.UnaryExpr{operator, value}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            checked : Evaluation <- evaluate_work(limit, U32.to_nat(65536), Nil{}, spend_budget(steps), Expression{value}, context)
            continue_value(checked, result => next_steps => unary(operator, result, next_steps))
        case M.EffectHasExpr{set, operation}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            checked : Evaluation <- evaluate_work(limit, U32.to_nat(65536), Nil{}, spend_budget(steps), Expression{set}, context)
            continue_value(checked, selected => operation_steps =>
              do Result<&2, &2, M.Diagnostic, Evaluation>:
                inspected : Evaluation <- evaluate_work(limit, U32.to_nat(65536), Nil{}, operation_steps, Expression{operation}, context)
                continue_value(inspected, descriptor => next_steps => effect_has(selected, descriptor, next_steps)))
        case M.EffectCountExpr{set}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            checked : Evaluation <- evaluate_work(limit, U32.to_nat(65536), Nil{}, spend_budget(steps), Expression{set}, context)
            continue_value(checked, selected => next_steps => effect_count(selected, next_steps))
        case M.EffectSameExpr{left, right}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            checked : Evaluation <- evaluate_work(limit, U32.to_nat(65536), Nil{}, spend_budget(steps), Expression{left}, context)
            continue_value(checked, a => right_steps =>
              do Result<&2, &2, M.Diagnostic, Evaluation>:
                inspected : Evaluation <- evaluate_work(limit, U32.to_nat(65536), Nil{}, right_steps, Expression{right}, context)
                continue_value(inspected, b => next_steps => effect_same(a, b, next_steps)))
        case M.LetExpr{name, value, body}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            bound : Evaluation <- evaluate_work(limit, U32.to_nat(65536), Nil{}, spend_budget(steps), Expression{value}, context)
            continue_value(bound, value => next_steps => evaluate_work(limit, U32.to_nat(65536), Nil{}, next_steps, Expression{body}, with_local(context, name, value)))
        case M.UseExpr{name, value, body}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            bound : Evaluation <- evaluate_work(limit, U32.to_nat(65536), Nil{}, spend_budget(steps), Expression{value}, context)
            continue_value(bound, value => next_steps => evaluate_work(limit, U32.to_nat(65536), Nil{}, next_steps, Expression{body}, with_local(context, name, value)))
        case M.IfExpr{condition, consequent, alternative}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            test : Evaluation <- evaluate_work(limit, U32.to_nat(65536), Nil{}, spend_budget(steps), Expression{condition}, context)
            continue_value(test, value => next_steps =>
              do Result<&2, &2, M.Diagnostic, Evaluation>:
                chosen : M.Expr <- branch(value, consequent, alternative)
                evaluate_work(limit, U32.to_nat(65536), Nil{}, next_steps, Expression{chosen}, context))
        case M.SequenceExpr{first, next}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            checked : Evaluation <- evaluate_work(limit, U32.to_nat(65536), Nil{}, spend_budget(steps), Expression{first}, context)
            continue_value(checked, ignored => next_steps => evaluate_work(limit, U32.to_nat(65536), Nil{}, next_steps, Expression{next}, context))
        case M.MatchExpr{values, arms}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            checked : Evaluation <- evaluate_work(limit, U32.to_nat(65536), values, spend_budget(steps), CollectValues{}, context)
            continue_value(checked, collected => next_steps =>
              do Result<&2, &2, M.Diagnostic, Evaluation>:
                scrutinees : List<&2, Value> <- collected_match_values(collected)
                evaluate_work(limit, U32.to_nat(65536), Nil{}, next_steps, MatchArms{arms, scrutinees}, context))
        case M.GuardExpr{pattern, value, alternative, body}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            checked : Evaluation <- evaluate_work(limit, U32.to_nat(65536), Nil{}, spend_budget(steps), Expression{value}, context)
            continue_value(checked, value => next_steps =>
              do Result<&2, &2, M.Diagnostic, Evaluation>:
                +matched : Evaluation <- evaluate_work(limit, U32.to_nat(65536), Nil{}, next_steps, MatchPatterns{U32.to_nat(65536), Done{PatternPending{[PatternValue{pattern, value}], Nil{}}}}, context)
                bindings : Maybe<&2, List<&2, Binding<Value>>> <- collected_pattern_bindings(eval_value(matched))
                complete_scope(guard_scope(bindings, body, alternative, context), eval_budget(matched),
                  selected_body => scope_context => body_steps => evaluate_work(limit, U32.to_nat(65536), Nil{}, body_steps, Expression{selected_body}, scope_context)))
        case M.BlockExpr{label, body}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            checked : Evaluation <- evaluate_work(limit, U32.to_nat(65536), Nil{}, spend_budget(steps), Expression{body}, context)
            return complete_block(checked, label)
        case M.ReturnExpr{label, value}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            checked : Evaluation <- evaluate_work(limit, U32.to_nat(65536), Nil{}, spend_budget(steps), Expression{value}, context)
            continue_value(checked, value => next_steps => Done{Evaluation{ReturnValue{label, value}, next_steps}})
        case M.SourceExpr{offset, annotation, value}:
          evaluate_work(limit, U32.to_nat(65536), Nil{}, spend_budget(steps), Expression{value}, context)

def evaluate(depth: Nat, steps: Nat, expression: M.Expr, context: Context) -> Result<&2, &2, M.Diagnostic, Evaluation>:
  evaluate_work(depth, U32.to_nat(65536), Nil{}, Budget{steps, Nil{}}, Expression{expression}, context)

def prepend_constant(name: String, value: Value, constants: Constants) -> Constants:
  Constants{bindings, remaining} = constants
  Constants{Binding{name, value} <> bindings, remaining}

def evaluate_constants(constants: List<&2, M.CheckedConstant>, steps: Nat, +context: Context) -> Result<&2, &2, M.Diagnostic, Constants>:
  match constants:
    case Nil{}:
      Done{Constants{Nil{}, steps}}
    case M.CheckedConstant{M.Constant{name, exported, annotation, M.RuntimeInitExpr{value}}, ty, variables} <> tail:
      evaluate_constants(tail, steps, context)
    case M.CheckedConstant{M.Constant{name, exported, annotation, value}, ty, variables} <> tail:
      +budget = steps
      do Result<&2, &2, M.Diagnostic, Constants>:
        checked : Evaluation <- evaluate(budget, budget, value, context)
        +head : Evaluation <- complete_definition(checked)
        rest : Constants <- evaluate_constants(tail, eval_remaining(head), context)
        return prepend_constant(name, eval_value(head), rest)
