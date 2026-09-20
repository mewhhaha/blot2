import Base
import ./model.bend as M

type Binding<-V: Data> is Data:
  Binding{name: String, value: V}

type Value is Data:
  UnitValue{}
  U32Value{value: U32}
  BoolValue{value: Bool}
  FunctionValue{name: String}
  ConstructorFunctionValue{constructor: String}
  DataValue{constructor: String, payload: Maybe<&2, Value>}
  ClosureValue{identity: Nat, parameter: String, body: M.Expr, environment: List<&2, Binding<Value>>}
  ReturnValue{label: Nat, value: Value}

type Evaluation is Data:
  Evaluation{value: Value, remaining: Nat}

type Context is Data:
  Context{constants: List<&2, M.Constant>, functions: List<&2, M.Function>, locals: List<&2, Binding<Value>>, data_types: List<&2, M.DataType>}

type Constants is Data:
  Constants{bindings: List<&2, Binding<Value>>, remaining: Nat}

type ScopedExpr is Data:
  ScopedExpr{expression: M.Expr, context: Context}

type Application is Data:
  BodyApplication{scope: ScopedExpr}
  ValueApplication{value: Value}

def lookup_local(locals: List<&2, Binding<Value>>, +name: String) -> Result<&2, &2, M.Diagnostic, Value>:
  match locals:
    case Nil{}:
      Fail{M.Diagnostic{"internal_error", name, "const evaluator lost a checked local"}}
    case Binding{found, value} <> tail:
      Bool.pick(Result<&2, &2, M.Diagnostic, Value>, M.name_equal(found, name), Done{value}, lookup_local(tail, name))

def lookup_constant(constants: List<&2, M.Constant>, +name: String) -> Result<&2, &2, M.Diagnostic, M.Expr>:
  match constants:
    case Nil{}:
      Fail{M.Diagnostic{"internal_error", name, "const evaluator lost a checked constant"}}
    case M.Constant{found, exported, annotation, value} <> tail:
      Bool.pick(Result<&2, &2, M.Diagnostic, M.Expr>, M.name_equal(found, name), Done{value}, lookup_constant(tail, name))

def lookup_function(functions: List<&2, M.Function>, +name: String) -> Result<&2, &2, M.Diagnostic, M.Function>:
  match functions:
    case Nil{}:
      Fail{M.Diagnostic{"internal_error", name, "const evaluator lost a checked function"}}
    case M.Function{+found, +exported, +parameter, +parameter_type, +result_type, +body} <> tail:
      Bool.pick(Result<&2, &2, M.Diagnostic, M.Function>, M.name_equal(found, name), Done{M.Function{found, exported, parameter, parameter_type, result_type, body}}, lookup_function(tail, name))

def eval_value(evaluation: Evaluation) -> Value:
  Evaluation{value, remaining} = evaluation
  value

def eval_remaining(evaluation: Evaluation) -> Nat:
  Evaluation{value, remaining} = evaluation
  remaining

def context_locals(context: Context) -> List<&2, Binding<Value>>:
  Context{constants, functions, locals, data_types} = context
  locals

def context_constants(context: Context) -> List<&2, M.Constant>:
  Context{constants, functions, locals, data_types} = context
  constants

def context_functions(context: Context) -> List<&2, M.Function>:
  Context{constants, functions, locals, data_types} = context
  functions

def context_data_types(context: Context) -> List<&2, M.DataType>:
  Context{constants, functions, locals, data_types} = context
  data_types

def without_locals(context: Context) -> Context:
  Context{constants, functions, locals, data_types} = context
  Context{constants, functions, Nil{}, data_types}

def with_locals(context: Context, locals: List<&2, Binding<Value>>) -> Context:
  Context{constants, functions, previous, data_types} = context
  Context{constants, functions, locals, data_types}

def with_local(context: Context, name: String, value: Value) -> Context:
  Context{constants, functions, locals, data_types} = context
  Context{constants, functions, Binding{name, value} <> locals, data_types}

def with_bindings(context: Context, bindings: List<&2, Binding<Value>>) -> Context:
  Context{constants, functions, locals, data_types} = context
  Context{constants, functions, List.append(&2, Binding<Value>, bindings, locals), data_types}

def function_body(function: M.Function) -> M.Expr:
  M.Function{name, exported, parameter, param_ty, result_ty, body} = function
  body

def function_context(function: M.Function, argument: Value, context: Context) -> Context:
  M.Function{name, exported, parameter, param_ty, result_ty, body} = function
  with_local(without_locals(context), parameter, argument)

def scalar_value(operator: M.ScalarOp, left: U32, right: U32) -> Value:
  match operator:
    case M.Add{}:
      U32Value{U32.add(left, right)}
    case M.Subtract{}:
      U32Value{U32.sub(left, right)}
    case M.Multiply{}:
      U32Value{U32.mul(left, right)}
    case M.Equal{}:
      BoolValue{U32.is_eq(left, right)}
    case M.LessThan{}:
      BoolValue{U32.is_lt(left, right)}

def scalar(operator: M.ScalarOp, left: Value, right: Value, remaining: Nat) -> Result<&2, &2, M.Diagnostic, Evaluation>:
  match left right:
    case U32Value{a} U32Value{b}:
      Done{Evaluation{scalar_value(operator, a, b), remaining}}
    case _ _:
      Fail{M.Diagnostic{"internal_error", "const", "checked scalar operation received a non-U32 value"}}

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
    case _:
      Fail{M.Diagnostic{"internal_error", "const", "checked application received a non-function value"}}

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

def complete_scope(scope: ScopedExpr, remaining: Nat, continuation: M.Expr -> Context -> Nat -> Result<&2, &2, M.Diagnostic, Evaluation>) -> Result<&2, &2, M.Diagnostic, Evaluation>:
  ScopedExpr{expression, context} = scope
  continuation(expression, context, remaining)

def match_pattern(pattern: M.Pattern, value: Value) -> Maybe<&2, List<&2, Binding<Value>>>:
  match pattern value:
    case M.WildcardPattern{} _:
      Some{Nil{}}
    case M.BindingPattern{name} value:
      Some{[Binding{name, value}]}
    case M.UnitPattern{} UnitValue{}:
      Some{Nil{}}
    case M.U32Pattern{expected} U32Value{actual}:
      Bool.pick(Maybe<&2, List<&2, Binding<Value>>>, U32.is_eq(expected, actual), Some{Nil{}}, None{})
    case M.BoolPattern{expected} BoolValue{actual}:
      Bool.pick(Maybe<&2, List<&2, Binding<Value>>>, Bool.not(Bool.xor(expected, actual)), Some{Nil{}}, None{})
    case M.ConstructorPattern{constructor, None{}} DataValue{found, None{}}:
      Bool.pick(Maybe<&2, List<&2, Binding<Value>>>, M.name_equal(constructor, found), Some{Nil{}}, None{})
    case M.ConstructorPattern{constructor, Some{nested}} DataValue{found, Some{payload}}:
      Bool.pick(Maybe<&2, List<&2, Binding<Value>>>, M.name_equal(constructor, found), match_pattern(nested, payload), None{})
    case _ _:
      None{}

def choose_match(bindings: Maybe<&2, List<&2, Binding<Value>>>, body: M.Expr, context: Context, fallback: Unit -> Result<&2, &2, M.Diagnostic, ScopedExpr>) -> Result<&2, &2, M.Diagnostic, ScopedExpr>:
  match bindings:
    case Some{locals}:
      Done{ScopedExpr{body, with_bindings(context, locals)}}
    case None{}:
      fallback(Unit{})

def matching_arm(arms: List<&2, M.MatchArm<M.Expr>>, +value: Value, +context: Context) -> Result<&2, &2, M.Diagnostic, ScopedExpr>:
  match arms:
    case Nil{}:
      Fail{M.Diagnostic{"internal_error", "const", "checked match has no matching arm"}}
    case M.MatchArm{pattern, body} <> tail:
      choose_match(match_pattern(pattern, value), body, context, ignored => matching_arm(tail, value, context))

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
    case Evaluation{value, remaining}:
      Done{Evaluation{value, remaining}}

# The decreasing depth proves termination to Bend. The separate remaining
# counter charges every evaluated node, including siblings and function calls.
def evaluate(+depth: Nat, +steps: Nat, expression: M.Expr, +context: Context) -> Result<&2, &2, M.Diagnostic, Evaluation>:
  match depth steps:
    case 0n _:
      Fail{M.Diagnostic{"const_budget", "const", "compile-time evaluation exhausted its step budget"}}
    case _ 0n:
      Fail{M.Diagnostic{"const_budget", "const", "compile-time evaluation exhausted its step budget"}}
    case 1n+limit 1n+remaining:
      match expression:
        case M.UnitExpr{}:
          Done{Evaluation{UnitValue{}, remaining}}
        case M.U32Expr{value}:
          Done{Evaluation{U32Value{value}, remaining}}
        case M.BoolExpr{value}:
          Done{Evaluation{BoolValue{value}, remaining}}
        case M.LocalExpr{name}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            value : Value <- lookup_local(context_locals(context), name)
            return Evaluation{value, remaining}
        case M.ConstantExpr{name}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            value : M.Expr <- lookup_constant(context_constants(context), name)
            evaluate(limit, remaining, value, without_locals(context))
        case M.FunctionExpr{name}:
          Done{Evaluation{FunctionValue{name}, remaining}}
        case M.ConstructorRefExpr{+constructor}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            value : Value <- constructor_value(lookup_constructor(context_data_types(context), constructor), constructor)
            return Evaluation{value, remaining}
        case M.ConstructExpr{constructor, None{}}:
          Done{Evaluation{DataValue{constructor, None{}}, remaining}}
        case M.ConstructExpr{constructor, Some{payload}}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            checked : Evaluation <- evaluate(limit, remaining, payload, context)
            continue_value(checked, value => next_steps => Done{Evaluation{DataValue{constructor, Some{value}}, next_steps}})
        case M.LambdaExpr{identity, parameter, parameter_type, result_type, body}:
          Done{Evaluation{ClosureValue{identity, parameter, body, context_locals(context)}, remaining}}
        case M.ApplyExpr{callee, argument}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            checked : Evaluation <- evaluate(limit, remaining, callee, context)
            continue_value(checked, function => argument_steps =>
              do Result<&2, &2, M.Diagnostic, Evaluation>:
                applied : Evaluation <- evaluate(limit, argument_steps, argument, context)
                continue_value(applied, value => call_steps =>
                  do Result<&2, &2, M.Diagnostic, Evaluation>:
                    call : Application <- application(function, value, context)
                    complete_application(call, call_steps, body => scope => body_steps =>
                      do Result<&2, &2, M.Diagnostic, Evaluation>:
                        result : Evaluation <- evaluate(limit, body_steps, body, scope)
                        complete_definition(result))))
        case M.CallExpr{callee, argument}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            checked : Evaluation <- evaluate(limit, remaining, argument, context)
            continue_value(checked, value => next_steps =>
              do Result<&2, &2, M.Diagnostic, Evaluation>:
                +function : M.Function <- lookup_function(context_functions(context), callee)
                result : Evaluation <- evaluate(limit, next_steps, function_body(function), function_context(function, value, context))
                complete_definition(result))
        case M.ScalarExpr{operator, left, right}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            checked : Evaluation <- evaluate(limit, remaining, left, context)
            continue_value(checked, left_value => right_steps =>
              do Result<&2, &2, M.Diagnostic, Evaluation>:
                right_result : Evaluation <- evaluate(limit, right_steps, right, context)
                continue_value(right_result, right_value => next_steps => scalar(operator, left_value, right_value, next_steps)))
        case M.LetExpr{name, value, body}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            bound : Evaluation <- evaluate(limit, remaining, value, context)
            continue_value(bound, value => next_steps => evaluate(limit, next_steps, body, with_local(context, name, value)))
        case M.UseExpr{name, value, body}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            bound : Evaluation <- evaluate(limit, remaining, value, context)
            continue_value(bound, value => next_steps => evaluate(limit, next_steps, body, with_local(context, name, value)))
        case M.IfExpr{condition, consequent, alternative}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            test : Evaluation <- evaluate(limit, remaining, condition, context)
            continue_value(test, value => next_steps =>
              do Result<&2, &2, M.Diagnostic, Evaluation>:
                chosen : M.Expr <- branch(value, consequent, alternative)
                evaluate(limit, next_steps, chosen, context))
        case M.SequenceExpr{first, next}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            checked : Evaluation <- evaluate(limit, remaining, first, context)
            continue_value(checked, ignored => next_steps => evaluate(limit, next_steps, next, context))
        case M.MatchExpr{value, arms}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            checked : Evaluation <- evaluate(limit, remaining, value, context)
            continue_value(checked, value => next_steps =>
              do Result<&2, &2, M.Diagnostic, Evaluation>:
                scope : ScopedExpr <- matching_arm(arms, value, context)
                complete_scope(scope, next_steps, body => scope_context => body_steps => evaluate(limit, body_steps, body, scope_context)))
        case M.GuardExpr{pattern, value, alternative, body}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            checked : Evaluation <- evaluate(limit, remaining, value, context)
            continue_value(checked, value => next_steps =>
              complete_scope(guard_scope(match_pattern(pattern, value), body, alternative, context), next_steps,
                selected_body => scope_context => body_steps => evaluate(limit, body_steps, selected_body, scope_context)))
        case M.BlockExpr{label, body}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            checked : Evaluation <- evaluate(limit, remaining, body, context)
            return complete_block(checked, label)
        case M.ReturnExpr{label, value}:
          do Result<&2, &2, M.Diagnostic, Evaluation>:
            checked : Evaluation <- evaluate(limit, remaining, value, context)
            continue_value(checked, value => next_steps => Done{Evaluation{ReturnValue{label, value}, next_steps}})
        case M.SourceExpr{offset, annotation, value}:
          evaluate(limit, remaining, value, context)
        case M.ReadExpr{identity}:
          Fail{M.Diagnostic{"const_effect", M.type_id_show(identity), "cannot read runtime ECS storage during const evaluation"}}
        case M.WriteExpr{value}:
          Fail{M.Diagnostic{"const_effect", "const", "cannot write runtime ECS storage during const evaluation"}}
        case M.InsertExpr{value}:
          Fail{M.Diagnostic{"const_effect", "const", "cannot insert runtime ECS storage during const evaluation"}}

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
