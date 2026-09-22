import Base
import ./model.bend as M

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
  EffectDescriptorValue{identity: M.TypeId}
  EffectSetValue{operations: List<&2, M.TypeId>}
  MatchValuesValue{values: List<&2, Value>}
  ProductValue{elements: List<&2, Value>}
  ArrayValue{elements: List<&2, Value>}

type Evaluation is Data:
  Evaluation{value: Value, remaining: Nat}

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

type EvaluationWork is Data:
  Expression{expression: M.Expr}
  CollectValues{}

type PatternWork is Data:
  PatternValue{pattern: M.Pattern, value: Value}
  ProductPatterns{patterns: List<&2, M.Pattern>, values: List<&2, Value>}
  ConstructorPayload{same: Bool, pattern: M.Pattern, value: Value}

type PatternProgress is Data:
  PatternPending{work: List<&2, PatternWork>, reversed: List<&2, Binding<Value>>}
  PatternRejected{}

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
  Evaluation{value, remaining} = evaluation
  remaining

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

def function_context(function: M.Function, argument: Value, context: Context) -> Context:
  M.Function{name, exported, parameter, param_ty, result_ty, body} = function
  with_local(without_locals(context), parameter, argument)

def scalar(operator: M.ScalarOp, left: Value, right: Value, remaining: Nat) -> Result<&2, &2, M.Diagnostic, Evaluation>:
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

def unary(operator: M.UnaryOp, value: Value, remaining: Nat) -> Result<&2, &2, M.Diagnostic, Evaluation>:
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
    case M.Constructor{+found, +payload} <> tail:
      Bool.pick(Maybe<&2, M.Constructor>, M.name_equal(found, name), Some{M.Constructor{found, payload}}, constructor_in(tail, name))

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
    case Some{M.Constructor{found, None{}}}:
      Done{DataValue{found, None{}}}
    case Some{M.Constructor{found, Some{payload}}}:
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

def effect_has(set: Value, operation: Value, remaining: Nat) -> Result<&2, &2, M.Diagnostic, Evaluation>:
  match set operation:
    case EffectSetValue{operations} EffectDescriptorValue{identity}:
      Done{Evaluation{BoolValue{operation_contains(operations, identity)}, remaining}}
    case _ _:
      Fail{M.Diagnostic{"internal_error", "const", "checked effect membership received values of the wrong type"}}

def effect_count(set: Value, remaining: Nat) -> Result<&2, &2, M.Diagnostic, Evaluation>:
  match set:
    case EffectSetValue{operations}:
      Done{Evaluation{U32Value{U32.from_nat(List.length(&2, M.TypeId, operations))}, remaining}}
    case _:
      Fail{M.Diagnostic{"internal_error", "const", "checked effect count received a non-set value"}}

def effect_same(left: Value, right: Value, remaining: Nat) -> Result<&2, &2, M.Diagnostic, Evaluation>:
  match left right:
    case EffectDescriptorValue{a} EffectDescriptorValue{b}:
      Done{Evaluation{BoolValue{M.type_id_equal(a, b)}, remaining}}
    case _ _:
      Fail{M.Diagnostic{"internal_error", "const", "checked effect equality received non-descriptor values"}}

# Continuations are affine Bend functions, not Blot closures. They keep block
# exits explicit without duplicating expression continuations or charging fuel
# for evaluator bookkeeping.
def continue_value(evaluation: Evaluation, continuation: Value -> Nat -> Result<&2, &2, M.Diagnostic, Evaluation>) -> Result<&2, &2, M.Diagnostic, Evaluation>:
  match evaluation:
    case Evaluation{ReturnValue{label, value}, remaining}:
      Done{Evaluation{ReturnValue{label, value}, remaining}}
    case Evaluation{value, remaining}:
      continuation(value, remaining)

def complete_application(application: Application, remaining: Nat, continuation: M.Expr -> Context -> Nat -> Result<&2, &2, M.Diagnostic, Evaluation>) -> Result<&2, &2, M.Diagnostic, Evaluation>:
  match application:
    case ValueApplication{value}:
      Done{Evaluation{value, remaining}}
    case BodyApplication{ScopedExpr{expression, context}}:
      continuation(expression, context, remaining)
    case OperationApplication{identity, argument}:
      Fail{M.Diagnostic{"internal_error", M.type_id_show(identity), "const evaluator failed to resolve an operation application"}}

def complete_scope(scope: ScopedExpr, remaining: Nat, continuation: M.Expr -> Context -> Nat -> Result<&2, &2, M.Diagnostic, Evaluation>) -> Result<&2, &2, M.Diagnostic, Evaluation>:
  ScopedExpr{expression, context} = scope
  continuation(expression, context, remaining)

def merge_pattern_bindings(first: Maybe<&2, List<&2, Binding<Value>>>, rest: Maybe<&2, List<&2, Binding<Value>>>) -> Maybe<&2, List<&2, Binding<Value>>>:
  match first rest:
    case Some{left} Some{right}:
      Some{List.append(&2, Binding<Value>, left, right)}
    case _ _:
      None{}

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

def choose_match(bindings: Maybe<&2, List<&2, Binding<Value>>>, body: M.Expr, context: Context, fallback: Unit -> Result<&2, &2, M.Diagnostic, ScopedExpr>) -> Result<&2, &2, M.Diagnostic, ScopedExpr>:
  match bindings:
    case Some{locals}:
      Done{ScopedExpr{body, with_bindings(context, locals)}}
    case None{}:
      fallback(Unit{})

def match_patterns(patterns: List<&2, M.Pattern>, values: List<&2, Value>) -> Result<&2, &2, M.Diagnostic, Maybe<&2, List<&2, Binding<Value>>>>:
  match patterns values:
    case Nil{} Nil{}:
      Done{Some{Nil{}}}
    case pattern <> rest value <> tail:
      do Result<&2, &2, M.Diagnostic, Maybe<&2, List<&2, Binding<Value>>>>:
        first : Maybe<&2, List<&2, Binding<Value>>> <- match_pattern(pattern, value)
        matched : Maybe<&2, List<&2, Binding<Value>>> <- match_patterns(rest, tail)
        return merge_pattern_bindings(first, matched)
    case _ _:
      Fail{M.Diagnostic{"internal_error", "const", "checked match arm has the wrong number of patterns"}}

def matching_arm(arms: List<&2, M.MatchArm<M.Expr>>, +values: List<&2, Value>, +context: Context) -> Result<&2, &2, M.Diagnostic, ScopedExpr>:
  match arms:
    case Nil{}:
      Fail{M.Diagnostic{"internal_error", "const", "checked match has no matching arm"}}
    case M.MatchArm{patterns, body} <> tail:
      do Result<&2, &2, M.Diagnostic, ScopedExpr>:
        bindings : Maybe<&2, List<&2, Binding<Value>>> <- match_patterns(patterns, values)
        choose_match(bindings, body, context, ignored => matching_arm(tail, values, context))

def matching_values(arms: List<&2, M.MatchArm<M.Expr>>, collected: Value, context: Context) -> Result<&2, &2, M.Diagnostic, ScopedExpr>:
  match collected:
    case MatchValuesValue{values}:
      matching_arm(arms, values, context)
    case _:
      Fail{M.Diagnostic{"internal_error", "const", "const evaluator lost collected match values"}}

def prepend_collected_value(value: Value, collected: Value, remaining: Nat) -> Result<&2, &2, M.Diagnostic, Evaluation>:
  match collected:
    case MatchValuesValue{values}:
      Done{Evaluation{MatchValuesValue{value <> values}, remaining}}
    case _:
      Fail{M.Diagnostic{"internal_error", "const", "const evaluator lost an expression collection tail"}}

def product_value(collected: Value, remaining: Nat) -> Result<&2, &2, M.Diagnostic, Evaluation>:
  match collected:
    case MatchValuesValue{elements}:
      Done{Evaluation{ProductValue{elements}, remaining}}
    case _:
      Fail{M.Diagnostic{"internal_error", "const", "const evaluator lost collected product elements"}}

def project_elements(elements: List<&2, Value>, index: Nat, remaining: Nat) -> Result<&2, &2, M.Diagnostic, Evaluation>:
  match elements index:
    case Nil{} _:
      Fail{M.Diagnostic{"product_index", "const", "product projection index is outside the element range"}}
    case head <> tail 0n:
      Done{Evaluation{head, remaining}}
    case head <> tail 1n+rest:
      project_elements(tail, rest, remaining)

def project(value: Value, index: Nat, remaining: Nat) -> Result<&2, &2, M.Diagnostic, Evaluation>:
  match value:
    case ProductValue{elements}:
      project_elements(elements, index, remaining)
    case _:
      Fail{M.Diagnostic{"type_mismatch", "const", "product projection requires a product value"}}

def array_value(collected: Value, remaining: Nat) -> Result<&2, &2, M.Diagnostic, Evaluation>:
  match collected:
    case MatchValuesValue{elements}:
      Done{Evaluation{ArrayValue{elements}, remaining}}
    case _:
      Fail{M.Diagnostic{"internal_error", "const", "const evaluator lost collected array elements"}}

def array_bounds() -> M.Diagnostic:
  M.Diagnostic{"array_bounds", "const", "array index is outside the element range"}

def array_get_elements(elements: List<&2, Value>, index: Nat, remaining: Nat) -> Result<&2, &2, M.Diagnostic, Evaluation>:
  match elements index:
    case Nil{} _:
      Fail{array_bounds()}
    case head <> tail 0n:
      Done{Evaluation{head, remaining}}
    case head <> tail 1n+rest:
      array_get_elements(tail, rest, remaining)

def array_get(array: Value, index: Value, remaining: Nat) -> Result<&2, &2, M.Diagnostic, Evaluation>:
  match array index:
    case ArrayValue{elements} U32Value{offset}:
      array_get_elements(elements, U32.to_nat(offset), remaining)
    case _ _:
      Fail{M.Diagnostic{"type_mismatch", "const", "array indexing requires an array and a U32 index"}}

# Copying an immutable array is work even when its elements came from a local.
# Charge the whole copy before publishing its successor; old values stay intact.
def array_copy(elements: List<&2, Value>, +index: Nat, +replacement: Value, +offset: Nat, reversed: List<&2, Value>, steps: Nat) -> Result<&2, &2, M.Diagnostic, Evaluation>:
  match elements steps:
    case Nil{} _:
      Done{Evaluation{ArrayValue{List.reverse(&2, Value, reversed)}, steps}}
    case head <> tail 0n:
      Fail{M.Diagnostic{"const_budget", "const", "compile-time evaluation exhausted its step budget while copying an array"}}
    case head <> tail 1n+remaining:
      array_copy(tail, index, replacement, 1n+offset, Bool.pick(Value, Nat.is_eq(index, offset), replacement, head) <> reversed, remaining)

def array_set_checked(valid: Bool, elements: List<&2, Value>, index: Nat, replacement: Value, steps: Nat) -> Result<&2, &2, M.Diagnostic, Evaluation>:
  match valid:
    case False{}:
      Fail{array_bounds()}
    case True{}:
      array_copy(elements, index, replacement, 0n, Nil{}, steps)

def array_set(array: Value, index: Value, replacement: Value, remaining: Nat) -> Result<&2, &2, M.Diagnostic, Evaluation>:
  match array index:
    case ArrayValue{+elements} U32Value{offset}:
      +index = U32.to_nat(offset)
      array_set_checked(Nat.is_lt(index, List.length(&2, Value, elements)), elements, index, replacement, remaining)
    case _ _:
      Fail{M.Diagnostic{"type_mismatch", "const", "array update requires an array and a U32 index"}}

def array_length_checked(valid: Bool, count: Nat, remaining: Nat) -> Result<&2, &2, M.Diagnostic, Evaluation>:
  match valid:
    case False{}:
      Fail{M.Diagnostic{"array_size", "const", "array length exceeds the U32 index range"}}
    case True{}:
      Done{Evaluation{U32Value{U32.from_nat(count)}, remaining}}

def array_length(array: Value, remaining: Nat) -> Result<&2, &2, M.Diagnostic, Evaluation>:
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
    case Evaluation{MatchValuesValue{values}, remaining}:
      Fail{M.Diagnostic{"internal_error", "const", "internal match values escaped their evaluator scope"}}
    case Evaluation{value, remaining}:
      Done{Evaluation{value, remaining}}

# Depth decreases for expression recursion; pending decreases while collecting
# expression values. Bookkeeping needs no extra step charge or depth budget.
def evaluate_work(+depth: Nat, pending: List<&2, M.Expr>, +steps: Nat, work: EvaluationWork, +context: Context) -> Result<&2, &2, M.Diagnostic, Evaluation>:
  match depth pending steps work:
    case _ Nil{} _ CollectValues{}:
      Done{Evaluation{MatchValuesValue{Nil{}}, steps}}
    case _ head <> +tail _ CollectValues{}:
      do Result<&2, &2, M.Diagnostic, Evaluation>:
        checked : Evaluation <- evaluate_work(depth, tail, steps, Expression{head}, context)
        continue_value(checked, value => next_steps =>
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            collected : Evaluation <- evaluate_work(depth, tail, next_steps, CollectValues{}, context)
            continue_value(collected, values => remaining => prepend_collected_value(value, values, remaining)))
    case 0n _ _ Expression{expression}:
      Fail{M.Diagnostic{"const_budget", "const", "compile-time evaluation exhausted its step budget"}}
    case _ _ 0n Expression{expression}:
      Fail{M.Diagnostic{"const_budget", "const", "compile-time evaluation exhausted its step budget"}}
    case 1n+limit _ 1n+remaining Expression{expression}:
      match expression:
        case M.UnitExpr{}:
          Done{Evaluation{UnitValue{}, remaining}}
        case M.U32Expr{value}:
          Done{Evaluation{U32Value{value}, remaining}}
        case M.F32Expr{value}:
          Done{Evaluation{F32Value{value}, remaining}}
        case M.BoolExpr{value}:
          Done{Evaluation{BoolValue{value}, remaining}}
        case M.PanicExpr{message}:
          Fail{M.Diagnostic{"const_panic", "const", message}}
        case M.LocalExpr{name}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            value : Value <- lookup_local(context_locals(context), name)
            return Evaluation{value, remaining}
        case M.ConstantExpr{name}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            value : M.Expr <- lookup_constant(context_constants(context), name)
            evaluate_work(limit, Nil{}, remaining, Expression{value}, without_locals(context))
        case M.FunctionExpr{name}:
          Done{Evaluation{FunctionValue{name}, remaining}}
        case M.OperationExpr{identity}:
          Done{Evaluation{OperationValue{identity}, remaining}}
        case M.OperationDescriptorExpr{identity}:
          Done{Evaluation{EffectDescriptorValue{identity}, remaining}}
        case M.FunctionEffectsExpr{callee}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            value : Value <- function_effects(context_checked_functions(context), callee)
            return Evaluation{value, remaining}
        case M.ConstructorRefExpr{+constructor}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            value : Value <- constructor_value(lookup_constructor(context_data_types(context), constructor), constructor)
            return Evaluation{value, remaining}
        case M.ConstructExpr{constructor, None{}}:
          Done{Evaluation{DataValue{constructor, None{}}, remaining}}
        case M.ConstructExpr{constructor, Some{payload}}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            checked : Evaluation <- evaluate_work(limit, Nil{}, remaining, Expression{payload}, context)
            continue_value(checked, value => next_steps => Done{Evaluation{DataValue{constructor, Some{value}}, next_steps}})
        case M.ProductExpr{first <> second <> tail}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            checked : Evaluation <- evaluate_work(limit, first <> second <> tail, remaining, CollectValues{}, context)
            continue_value(checked, collected => next_steps => product_value(collected, next_steps))
        case M.ProductExpr{elements}:
          Fail{M.Diagnostic{"product_arity", "const", "products require at least two elements; Unit is a distinct value"}}
        case M.ProjectExpr{value, index}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            checked : Evaluation <- evaluate_work(limit, Nil{}, remaining, Expression{value}, context)
            continue_value(checked, product => next_steps => project(product, index, next_steps))
        case M.ArrayExpr{elements}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            checked : Evaluation <- evaluate_work(limit, elements, remaining, CollectValues{}, context)
            continue_value(checked, collected => next_steps => array_value(collected, next_steps))
        case M.ArrayGetExpr{array, index}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            checked : Evaluation <- evaluate_work(limit, Nil{}, remaining, Expression{array}, context)
            continue_value(checked, value => index_steps =>
              do Result<&2, &2, M.Diagnostic, Evaluation>:
                indexed : Evaluation <- evaluate_work(limit, Nil{}, index_steps, Expression{index}, context)
                continue_value(indexed, offset => next_steps => array_get(value, offset, next_steps)))
        case M.ArraySetExpr{array, index, value}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            checked : Evaluation <- evaluate_work(limit, Nil{}, remaining, Expression{array}, context)
            continue_value(checked, original => index_steps =>
              do Result<&2, &2, M.Diagnostic, Evaluation>:
                indexed : Evaluation <- evaluate_work(limit, Nil{}, index_steps, Expression{index}, context)
                continue_value(indexed, offset => value_steps =>
                  do Result<&2, &2, M.Diagnostic, Evaluation>:
                    changed : Evaluation <- evaluate_work(limit, Nil{}, value_steps, Expression{value}, context)
                    continue_value(changed, replacement => next_steps => array_set(original, offset, replacement, next_steps))))
        case M.ArrayLengthExpr{array}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            checked : Evaluation <- evaluate_work(limit, Nil{}, remaining, Expression{array}, context)
            continue_value(checked, value => next_steps => array_length(value, next_steps))
        case M.LambdaExpr{identity, parameter, parameter_type, result_type, body}:
          Done{Evaluation{ClosureValue{identity, parameter, body, context_locals(context)}, remaining}}
        case M.ProviderExpr{identity, implementation}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            checked : Evaluation <- evaluate_work(limit, Nil{}, remaining, Expression{implementation}, context)
            continue_value(checked, value => next_steps => Done{Evaluation{ProviderValue{identity, value}, next_steps}})
        case M.HandleExpr{provider, body}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            checked : Evaluation <- evaluate_work(limit, Nil{}, remaining, Expression{provider}, context)
            continue_value(checked, value => next_steps =>
              do Result<&2, &2, M.Diagnostic, Evaluation>:
                scope : Context <- with_provider(value, context)
                evaluate_work(limit, Nil{}, next_steps, Expression{body}, scope))
        case M.ApplyExpr{callee, argument}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            checked : Evaluation <- evaluate_work(limit, Nil{}, remaining, Expression{callee}, context)
            continue_value(checked, function => argument_steps =>
              do Result<&2, &2, M.Diagnostic, Evaluation>:
                applied : Evaluation <- evaluate_work(limit, Nil{}, argument_steps, Expression{argument}, context)
                continue_value(applied, value => call_steps =>
                  do Result<&2, &2, M.Diagnostic, Evaluation>:
                    call : Application <- application(function, value, context)
                    resolved : Application <- resolve_application(context_providers(context), call, context)
                    complete_application(resolved, call_steps, body => scope => body_steps =>
                      do Result<&2, &2, M.Diagnostic, Evaluation>:
                        result : Evaluation <- evaluate_work(limit, Nil{}, body_steps, Expression{body}, scope)
                        complete_definition(result))))
        case M.CallExpr{callee, argument}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            checked : Evaluation <- evaluate_work(limit, Nil{}, remaining, Expression{argument}, context)
            continue_value(checked, value => next_steps =>
              do Result<&2, &2, M.Diagnostic, Evaluation>:
                +function : M.Function <- lookup_function(context_functions(context), callee)
                result : Evaluation <- evaluate_work(limit, Nil{}, next_steps, Expression{function_body(function)}, function_context(function, value, context))
                complete_definition(result))
        case M.ScalarExpr{operator, left, right}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            checked : Evaluation <- evaluate_work(limit, Nil{}, remaining, Expression{left}, context)
            continue_value(checked, left_value => right_steps =>
              do Result<&2, &2, M.Diagnostic, Evaluation>:
                right_result : Evaluation <- evaluate_work(limit, Nil{}, right_steps, Expression{right}, context)
                continue_value(right_result, right_value => next_steps => scalar(operator, left_value, right_value, next_steps)))
        case M.UnaryExpr{operator, value}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            checked : Evaluation <- evaluate_work(limit, Nil{}, remaining, Expression{value}, context)
            continue_value(checked, result => next_steps => unary(operator, result, next_steps))
        case M.EffectHasExpr{set, operation}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            checked : Evaluation <- evaluate_work(limit, Nil{}, remaining, Expression{set}, context)
            continue_value(checked, selected => operation_steps =>
              do Result<&2, &2, M.Diagnostic, Evaluation>:
                inspected : Evaluation <- evaluate_work(limit, Nil{}, operation_steps, Expression{operation}, context)
                continue_value(inspected, descriptor => next_steps => effect_has(selected, descriptor, next_steps)))
        case M.EffectCountExpr{set}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            checked : Evaluation <- evaluate_work(limit, Nil{}, remaining, Expression{set}, context)
            continue_value(checked, selected => next_steps => effect_count(selected, next_steps))
        case M.EffectSameExpr{left, right}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            checked : Evaluation <- evaluate_work(limit, Nil{}, remaining, Expression{left}, context)
            continue_value(checked, a => right_steps =>
              do Result<&2, &2, M.Diagnostic, Evaluation>:
                inspected : Evaluation <- evaluate_work(limit, Nil{}, right_steps, Expression{right}, context)
                continue_value(inspected, b => next_steps => effect_same(a, b, next_steps)))
        case M.LetExpr{name, value, body}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            bound : Evaluation <- evaluate_work(limit, Nil{}, remaining, Expression{value}, context)
            continue_value(bound, value => next_steps => evaluate_work(limit, Nil{}, next_steps, Expression{body}, with_local(context, name, value)))
        case M.UseExpr{name, value, body}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            bound : Evaluation <- evaluate_work(limit, Nil{}, remaining, Expression{value}, context)
            continue_value(bound, value => next_steps => evaluate_work(limit, Nil{}, next_steps, Expression{body}, with_local(context, name, value)))
        case M.IfExpr{condition, consequent, alternative}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            test : Evaluation <- evaluate_work(limit, Nil{}, remaining, Expression{condition}, context)
            continue_value(test, value => next_steps =>
              do Result<&2, &2, M.Diagnostic, Evaluation>:
                chosen : M.Expr <- branch(value, consequent, alternative)
                evaluate_work(limit, Nil{}, next_steps, Expression{chosen}, context))
        case M.SequenceExpr{first, next}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            checked : Evaluation <- evaluate_work(limit, Nil{}, remaining, Expression{first}, context)
            continue_value(checked, ignored => next_steps => evaluate_work(limit, Nil{}, next_steps, Expression{next}, context))
        case M.MatchExpr{values, arms}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            checked : Evaluation <- evaluate_work(limit, values, remaining, CollectValues{}, context)
            continue_value(checked, collected => next_steps =>
              do Result<&2, &2, M.Diagnostic, Evaluation>:
                scope : ScopedExpr <- matching_values(arms, collected, context)
                complete_scope(scope, next_steps, body => scope_context => body_steps => evaluate_work(limit, Nil{}, body_steps, Expression{body}, scope_context)))
        case M.GuardExpr{pattern, value, alternative, body}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            checked : Evaluation <- evaluate_work(limit, Nil{}, remaining, Expression{value}, context)
            continue_value(checked, value => next_steps =>
              do Result<&2, &2, M.Diagnostic, Evaluation>:
                bindings : Maybe<&2, List<&2, Binding<Value>>> <- match_pattern(pattern, value)
                complete_scope(guard_scope(bindings, body, alternative, context), next_steps,
                  selected_body => scope_context => body_steps => evaluate_work(limit, Nil{}, body_steps, Expression{selected_body}, scope_context)))
        case M.BlockExpr{label, body}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            checked : Evaluation <- evaluate_work(limit, Nil{}, remaining, Expression{body}, context)
            return complete_block(checked, label)
        case M.ReturnExpr{label, value}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            checked : Evaluation <- evaluate_work(limit, Nil{}, remaining, Expression{value}, context)
            continue_value(checked, value => next_steps => Done{Evaluation{ReturnValue{label, value}, next_steps}})
        case M.SourceExpr{offset, annotation, value}:
          evaluate_work(limit, Nil{}, remaining, Expression{value}, context)

def evaluate(depth: Nat, steps: Nat, expression: M.Expr, context: Context) -> Result<&2, &2, M.Diagnostic, Evaluation>:
  evaluate_work(depth, Nil{}, steps, Expression{expression}, context)

def prepend_constant(name: String, value: Value, constants: Constants) -> Constants:
  Constants{bindings, remaining} = constants
  Constants{Binding{name, value} <> bindings, remaining}

def evaluate_constants(constants: List<&2, M.CheckedConstant>, steps: Nat, +context: Context) -> Result<&2, &2, M.Diagnostic, Constants>:
  match constants:
    case Nil{}:
      Done{Constants{Nil{}, steps}}
    case M.CheckedConstant{M.Constant{name, exported, annotation, value}, ty, variables} <> tail:
      +budget = steps
      do Result<&2, &2, M.Diagnostic, Constants>:
        checked : Evaluation <- evaluate(budget, budget, value, context)
        +head : Evaluation <- complete_definition(checked)
        rest : Constants <- evaluate_constants(tail, eval_remaining(head), context)
        return prepend_constant(name, eval_value(head), rest)
