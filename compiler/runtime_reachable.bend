import Base
import ./model.bend as M
import ./const_eval.bend as C
import ./closures.bend as F
import ./codegen_ir.bend as I
import ./index.bend as Index
import ./runtime_initialization.bend as Init

type Catalog is Data:
  Catalog{functions: Map<&2, Maybe<&2, M.CheckedFunction>>, constants: Map<&2, Maybe<&2, C.Value>>, initializers: Map<&2, Init.Initializer>}

type State is Data:
  State{visited: Map<&2, Bool>, lambda_ids: Map<&2, Bool>, lambdas: List<&2, F.Lambda>, constructors: Set(), operations: Set()}

type Work is Data:
  FunctionWork{name: String}
  ConstantWork{name: String}
  ExpressionWork{expression: M.Expr}
  ExpressionsWork{expressions: List<&2, M.Expr>}
  PatternWork{patterns: List<&2, M.Pattern>}
  PatternArms{arms: List<&2, M.MatchArm<M.Expr>>}
  ValueWork{value: C.Value}
  ValuesWork{values: List<&2, C.Value>}

type Step is Data:
  Step{pending: List<&2, Work>, state: State}

type Runtime is Data:
  Runtime{checked: M.CheckedModule, constants: List<&2, C.Binding<C.Value>>, lambdas: List<&2, F.Lambda>, constructors: Set(), operations: Set()}

def function_index(functions: List<&2, M.CheckedFunction>, indexed: Map<&2, Maybe<&2, M.CheckedFunction>>) -> Map<&2, Maybe<&2, M.CheckedFunction>>:
  match functions:
    case Nil{}:
      indexed
    case M.CheckedFunction{M.Function{+name, exported, parameter, parameter_type, result_type, body}, signature, effects} <> tail:
      function_index(tail, Index.set(Maybe<&2, M.CheckedFunction>, indexed, name, Some{M.CheckedFunction{M.Function{name, exported, parameter, parameter_type, result_type, body}, signature, effects}}))

def constant_index(constants: List<&2, C.Binding<C.Value>>, indexed: Map<&2, Maybe<&2, C.Value>>) -> Map<&2, Maybe<&2, C.Value>>:
  match constants:
    case Nil{}:
      indexed
    case C.Binding{name, value} <> tail:
      constant_index(tail, Index.set(Maybe<&2, C.Value>, indexed, name, Some{value}))

def seen(state: State, name: String) -> Bool:
  State{visited, lambda_ids, lambdas, constructors, operations} = state
  Index.get(Bool, visited, name, False{})

def mark(state: State, name: String) -> State:
  State{visited, lambda_ids, lambdas, constructors, operations} = state
  State{Index.set(Bool, visited, name, True{}), lambda_ids, lambdas, constructors, operations}

def lambda_seen(state: State, identity: Nat) -> Bool:
  State{visited, lambda_ids, lambdas, constructors, operations} = state
  Index.get(Bool, lambda_ids, Nat.show(identity), False{})

def add_lambda(state: State, lambda: F.Lambda) -> State:
  State{visited, lambda_ids, lambdas, constructors, operations} = state
  F.Lambda{+identity, parameter, body, captures} = lambda
  State{visited, Index.set(Bool, lambda_ids, Nat.show(identity), True{}), F.Lambda{identity, parameter, body, captures} <> lambdas, constructors, operations}

def use_constructor(state: State, name: String) -> State:
  State{visited, lambda_ids, lambdas, constructors, operations} = state
  State{visited, lambda_ids, lambdas, Set.add(constructors, name), operations}

def use_operation(state: State, identity: M.TypeId) -> State:
  State{visited, lambda_ids, lambdas, constructors, operations} = state
  State{visited, lambda_ids, lambdas, constructors, Set.add(operations, I.operation_key(identity))}

def function_value(catalog: Catalog, name: String) -> Maybe<&2, M.CheckedFunction>:
  Catalog{functions, constants, initializers} = catalog
  Index.get(Maybe<&2, M.CheckedFunction>, functions, name, None{})

def constant_value(catalog: Catalog, name: String) -> Maybe<&2, C.Value>:
  Catalog{functions, constants, initializers} = catalog
  Index.get(Maybe<&2, C.Value>, constants, name, None{})

def visit_function(visited: Bool, found: Maybe<&2, M.CheckedFunction>, name: String, state: State) -> Result<&2, &2, M.Diagnostic, Step>:
  match visited found:
    case True{} _:
      Done{Step{Nil{}, state}}
    case False{} None{}:
      Fail{M.Diagnostic{"internal_error", name, "runtime reachability lost a checked function"}}
    case False{} Some{M.CheckedFunction{M.Function{found_name, exported, parameter, parameter_type, result_type, body}, signature, effects}}:
      Done{Step{[ExpressionWork{body}], mark(state, "fn:" ++ name)}}

def visit_constant(visited: Bool, found: Maybe<&2, C.Value>, initializer: Maybe<&2, Init.Initializer>, name: String, state: State) -> Result<&2, &2, M.Diagnostic, Step>:
  match visited found initializer:
    case True{} _ _:
      Done{Step{Nil{}, state}}
    case False{} Some{value} _:
      Done{Step{[ValueWork{value}], mark(state, "const:" ++ name)}}
    case False{} None{} Some{Init.Initializer{declared, value}}:
      Done{Step{[ExpressionWork{value}], mark(state, "const:" ++ name)}}
    case False{} None{} None{}:
      Fail{M.Diagnostic{"internal_error", name, "runtime reachability lost a checked value"}}

def initializer_value(catalog: Catalog, name: String) -> Maybe<&2, Init.Initializer>:
  Catalog{functions, constants, initializers} = catalog
  Index.find(Init.Initializer, initializers, name)

def captured_values(names: List<&2, String>, +environment: List<&2, C.Binding<C.Value>>) -> Result<&2, &2, M.Diagnostic, List<&2, C.Value>>:
  match names:
    case Nil{}:
      Done{Nil{}}
    case head <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, C.Value>>:
        first : C.Value <- C.lookup_local(environment, head)
        remaining : List<&2, C.Value> <- captured_values(tail, environment)
        return first <> remaining

def closure_captures(environment: Maybe<&2, List<&2, C.Binding<C.Value>>>, captures: List<&2, String>) -> Result<&2, &2, M.Diagnostic, List<&2, C.Value>>:
  match environment:
    case None{}:
      Done{Nil{}}
    case Some{bindings}:
      captured_values(captures, bindings)

def visit_lambda(visited: Bool, identity: Nat, +parameter: String, +body: M.Expr, environment: Maybe<&2, List<&2, C.Binding<C.Value>>>, state: State) -> Result<&2, &2, M.Diagnostic, Step>:
  match visited:
    case True{}:
      # The body is shared, but two values may close over different live functions.
      do Result<&2, &2, M.Diagnostic, Step>:
        captures : List<&2, String> <- F.free(U32.to_nat(4096), F.ExpressionWork{body, [parameter]})
        values : List<&2, C.Value> <- closure_captures(environment, captures)
        return Step{[ValuesWork{values}], state}
    case False{}:
      do Result<&2, &2, M.Diagnostic, Step>:
        +captures : List<&2, String> <- F.free(U32.to_nat(4096), F.ExpressionWork{body, [parameter]})
        values : List<&2, C.Value> <- closure_captures(environment, captures)
        return Step{[ExpressionWork{body}, ValuesWork{values}], add_lambda(state, F.Lambda{identity, parameter, body, captures})}

def expanded_step(result: Result<&2, &2, M.Diagnostic, Step>, pending: List<&2, Work>) -> Result<&2, &2, M.Diagnostic, Step>:
  match result:
    case Fail{error}:
      Fail{error}
    case Done{Step{next, state}}:
      Done{Step{List.append(&2, Work, next, pending), state}}

# Keep ordinary expression/value traversal in the tail loop. Only catalog and
# closure expansion take the fallible slow path; every Work still spends one
# unit of the original traversal allowance.
def walk_steps(fuel: Nat, step: Result<&2, &2, M.Diagnostic, Step>, +catalog: Catalog) -> Result<&2, &2, M.Diagnostic, State>:
  match fuel step:
    case _ Fail{error}:
      Fail{error}
    case _ Done{Step{Nil{}, state}}:
      Done{state}
    case 0n _:
      Fail{M.Diagnostic{"backend_limit", "reachability", "runtime reachability exceeded its traversal limit"}}
    case 1n+rest Done{Step{FunctionWork{+name} <> pending, +state}}:
      walk_steps(rest, expanded_step(visit_function(seen(state, "fn:" ++ name), function_value(catalog, name), name, state), pending), catalog)
    case 1n+rest Done{Step{ConstantWork{+name} <> pending, +state}}:
      walk_steps(rest, expanded_step(visit_constant(seen(state, "const:" ++ name), constant_value(catalog, name), initializer_value(catalog, name), name, state), pending), catalog)
    case 1n+rest Done{Step{ExpressionWork{M.FunctionExpr{name}} <> pending, state}}:
      walk_steps(rest, Done{Step{FunctionWork{name} <> pending, state}}, catalog)
    case 1n+rest Done{Step{ExpressionWork{M.CallExpr{callee, argument}} <> pending, state}}:
      walk_steps(rest, Done{Step{FunctionWork{callee} <> ExpressionWork{argument} <> pending, state}}, catalog)
    case 1n+rest Done{Step{ExpressionWork{M.ConstantExpr{name}} <> pending, state}}:
      walk_steps(rest, Done{Step{ConstantWork{name} <> pending, state}}, catalog)
    case 1n+rest Done{Step{ExpressionWork{M.ConstructorRefExpr{name}} <> pending, state}}:
      walk_steps(rest, Done{Step{pending, use_constructor(state, name)}}, catalog)
    case 1n+rest Done{Step{ExpressionWork{M.OperationExpr{identity}} <> pending, state}}:
      walk_steps(rest, Done{Step{pending, use_operation(state, identity)}}, catalog)
    case 1n+rest Done{Step{ExpressionWork{M.ProviderExpr{identity, implementation}} <> pending, state}}:
      walk_steps(rest, Done{Step{ExpressionWork{implementation} <> pending, use_operation(state, identity)}}, catalog)
    case 1n+rest Done{Step{ExpressionWork{M.StateProviderExpr{read, write, initial}} <> pending, state}}:
      walk_steps(rest, Done{Step{ExpressionWork{initial} <> pending, use_operation(use_operation(state, read), write)}}, catalog)
    case 1n+rest Done{Step{ExpressionWork{M.LambdaExpr{+identity, parameter, parameter_type, result_type, body}} <> pending, +state}}:
      walk_steps(rest, expanded_step(visit_lambda(lambda_seen(state, identity), identity, parameter, body, None{}, state), pending), catalog)
    case 1n+rest Done{Step{ExpressionWork{M.OperationDescriptorExpr{identity}} <> pending, state}}:
      Fail{I.const_only()}
    case 1n+rest Done{Step{ExpressionWork{M.FunctionEffectsExpr{callee}} <> pending, state}}:
      Fail{I.const_only()}
    case 1n+rest Done{Step{ExpressionWork{M.EffectHasExpr{set, operation}} <> pending, state}}:
      Fail{I.const_only()}
    case 1n+rest Done{Step{ExpressionWork{M.EffectCountExpr{set}} <> pending, state}}:
      Fail{I.const_only()}
    case 1n+rest Done{Step{ExpressionWork{M.EffectSameExpr{left, right}} <> pending, state}}:
      Fail{I.const_only()}
    case 1n+rest Done{Step{ExpressionWork{M.MatchExpr{values, +arms}} <> pending, state}}:
      walk_steps(rest, Done{Step{PatternArms{arms} <> ExpressionsWork{F.children(M.MatchExpr{values, arms})} <> pending, state}}, catalog)
    case 1n+rest Done{Step{ExpressionWork{M.GuardExpr{+pattern, value, alternative, body}} <> pending, state}}:
      walk_steps(rest, Done{Step{PatternWork{[pattern]} <> ExpressionsWork{[value, alternative, body]} <> pending, state}}, catalog)
    case 1n+rest Done{Step{PatternArms{Nil{}} <> pending, state}}:
      walk_steps(rest, Done{Step{pending, state}}, catalog)
    case 1n+rest Done{Step{PatternArms{M.MatchArm{patterns, body} <> tail} <> pending, state}}:
      walk_steps(rest, Done{Step{PatternWork{patterns} <> PatternArms{tail} <> pending, state}}, catalog)
    case 1n+rest Done{Step{PatternWork{Nil{}} <> pending, state}}:
      walk_steps(rest, Done{Step{pending, state}}, catalog)
    case 1n+rest Done{Step{PatternWork{M.ValuePattern{reference} <> tail} <> pending, state}}:
      walk_steps(rest, Done{Step{ExpressionWork{M.reference_expr(reference)} <> PatternWork{tail} <> pending, state}}, catalog)
    case 1n+rest Done{Step{PatternWork{M.ConstructorPattern{name, Some{payload}} <> tail} <> pending, state}}:
      walk_steps(rest, Done{Step{PatternWork{payload <> tail} <> pending, state}}, catalog)
    case 1n+rest Done{Step{PatternWork{M.ProductPattern{elements} <> tail} <> pending, state}}:
      walk_steps(rest, Done{Step{PatternWork{elements} <> PatternWork{tail} <> pending, state}}, catalog)
    case 1n+rest Done{Step{PatternWork{pattern <> tail} <> pending, state}}:
      walk_steps(rest, Done{Step{PatternWork{tail} <> pending, state}}, catalog)
    case 1n+rest Done{Step{ExpressionWork{expression} <> pending, state}}:
      walk_steps(rest, Done{Step{ExpressionsWork{F.children(expression)} <> pending, state}}, catalog)
    case 1n+rest Done{Step{ExpressionsWork{Nil{}} <> pending, state}}:
      walk_steps(rest, Done{Step{pending, state}}, catalog)
    case 1n+rest Done{Step{ExpressionsWork{head <> tail} <> pending, state}}:
      walk_steps(rest, Done{Step{ExpressionWork{head} <> ExpressionsWork{tail} <> pending, state}}, catalog)
    case 1n+rest Done{Step{ValueWork{C.FunctionValue{name}} <> pending, state}}:
      walk_steps(rest, Done{Step{FunctionWork{name} <> pending, state}}, catalog)
    case 1n+rest Done{Step{ValueWork{C.ConstructorFunctionValue{name}} <> pending, state}}:
      walk_steps(rest, Done{Step{pending, use_constructor(state, name)}}, catalog)
    case 1n+rest Done{Step{ValueWork{C.OperationValue{identity}} <> pending, state}}:
      walk_steps(rest, Done{Step{pending, use_operation(state, identity)}}, catalog)
    case 1n+rest Done{Step{ValueWork{C.ClosureValue{+identity, parameter, body, environment}} <> pending, +state}}:
      walk_steps(rest, expanded_step(visit_lambda(lambda_seen(state, identity), identity, parameter, body, Some{environment}, state), pending), catalog)
    case 1n+rest Done{Step{ValueWork{C.DataValue{constructor, Some{payload}}} <> pending, state}}:
      walk_steps(rest, Done{Step{ValueWork{payload} <> pending, state}}, catalog)
    case 1n+rest Done{Step{ValueWork{C.ProductValue{elements}} <> pending, state}}:
      walk_steps(rest, Done{Step{ValuesWork{elements} <> pending, state}}, catalog)
    case 1n+rest Done{Step{ValueWork{C.ArrayValue{elements}} <> pending, state}}:
      walk_steps(rest, Done{Step{ValuesWork{elements} <> pending, state}}, catalog)
    case 1n+rest Done{Step{ValueWork{C.MemoValue{slot, computed, value}} <> pending, state}}:
      walk_steps(rest, Done{Step{ValueWork{value} <> pending, state}}, catalog)
    case 1n+rest Done{Step{ValueWork{C.DemandValue{slot, computation}} <> pending, state}}:
      Fail{M.Diagnostic{"internal_error", "demand", "an unsnapshotted memo escaped constant evaluation"}}
    case 1n+rest Done{Step{ValueWork{C.StateProviderValue{read, write, initial}} <> pending, state}}:
      walk_steps(rest, Done{Step{ValueWork{initial} <> pending, use_operation(use_operation(state, read), write)}}, catalog)
    case 1n+rest Done{Step{ValueWork{C.ProviderValue{identity, implementation}} <> pending, state}}:
      walk_steps(rest, Done{Step{ValueWork{implementation} <> pending, use_operation(state, identity)}}, catalog)
    case 1n+rest Done{Step{ValueWork{C.EffectDescriptorValue{identity}} <> pending, state}}:
      Fail{I.const_only()}
    case 1n+rest Done{Step{ValueWork{C.EffectSetValue{operations}} <> pending, state}}:
      Fail{I.const_only()}
    case 1n+rest Done{Step{ValueWork{C.ReturnValue{label, value}} <> pending, state}}:
      Fail{M.Diagnostic{"internal_error", "constant", "runtime reachability received an unhandled return"}}
    case 1n+rest Done{Step{ValueWork{C.PatternBindingsValue{bindings}} <> pending, state}}:
      Fail{M.Diagnostic{"internal_error", "constant", "runtime reachability received internal pattern bindings"}}
    case 1n+rest Done{Step{ValueWork{C.MatchValuesValue{values}} <> pending, state}}:
      Fail{M.Diagnostic{"internal_error", "constant", "runtime reachability received a match scrutinee collection"}}
    case 1n+rest Done{Step{ValueWork{value} <> pending, state}}:
      walk_steps(rest, Done{Step{pending, state}}, catalog)
    case 1n+rest Done{Step{ValuesWork{Nil{}} <> pending, state}}:
      walk_steps(rest, Done{Step{pending, state}}, catalog)
    case 1n+rest Done{Step{ValuesWork{head <> tail} <> pending, state}}:
      walk_steps(rest, Done{Step{ValueWork{head} <> ValuesWork{tail} <> pending, state}}, catalog)

def walk(fuel: Nat, pending: List<&2, Work>, catalog: Catalog, state: State) -> Result<&2, &2, M.Diagnostic, State>:
  walk_steps(fuel, Done{Step{pending, state}}, catalog)

def function_roots(functions: List<&2, M.CheckedFunction>) -> List<&2, Work>:
  match functions:
    case Nil{}:
      Nil{}
    case M.CheckedFunction{M.Function{name, True{}, parameter, parameter_type, result_type, body}, signature, effects} <> tail:
      FunctionWork{name} <> function_roots(tail)
    case head <> tail:
      function_roots(tail)

def constant_roots(constants: List<&2, M.CheckedConstant>) -> List<&2, Work>:
  match constants:
    case Nil{}:
      Nil{}
    case M.CheckedConstant{M.Constant{name, exported, annotation, M.RuntimeInitExpr{value}}, ty, variables} <> tail:
      ConstantWork{name} <> constant_roots(tail)
    case M.CheckedConstant{M.Constant{name, True{}, annotation, value}, ty, variables} <> tail:
      ConstantWork{name} <> constant_roots(tail)
    case head <> tail:
      constant_roots(tail)

def keep_functions(functions: List<&2, M.CheckedFunction>, +state: State) -> List<&2, M.CheckedFunction>:
  match functions:
    case Nil{}:
      Nil{}
    case M.CheckedFunction{M.Function{+name, exported, parameter, parameter_type, result_type, body}, signature, effects} <> tail:
      +remaining = keep_functions(tail, state)
      Bool.pick(List<&2, M.CheckedFunction>, seen(state, "fn:" ++ name), M.CheckedFunction{M.Function{name, exported, parameter, parameter_type, result_type, body}, signature, effects} <> remaining, remaining)

def keep_constants(constants: List<&2, M.CheckedConstant>, +state: State) -> List<&2, M.CheckedConstant>:
  match constants:
    case Nil{}:
      Nil{}
    case M.CheckedConstant{M.Constant{+name, exported, annotation, value}, ty, variables} <> tail:
      +remaining = keep_constants(tail, state)
      Bool.pick(List<&2, M.CheckedConstant>, seen(state, "const:" ++ name), M.CheckedConstant{M.Constant{name, exported, annotation, value}, ty, variables} <> remaining, remaining)

def keep_bindings(constants: List<&2, C.Binding<C.Value>>, +state: State) -> List<&2, C.Binding<C.Value>>:
  match constants:
    case Nil{}:
      Nil{}
    case C.Binding{+name, value} <> tail:
      +remaining = keep_bindings(tail, state)
      Bool.pick(List<&2, C.Binding<C.Value>>, seen(state, "const:" ++ name), C.Binding{name, value} <> remaining, remaining)

def reached_lambdas(state: State) -> List<&2, F.Lambda>:
  State{visited, lambda_ids, lambdas, constructors, operations} = state
  List.reverse(&2, F.Lambda, lambdas)

def used_constructors(state: State) -> Set():
  State{visited, lambda_ids, lambdas, constructors, operations} = state
  constructors

def used_operations(state: State) -> Set():
  State{visited, lambda_ids, lambdas, constructors, operations} = state
  operations

def prepare(checked: M.CheckedModule, +bindings: List<&2, C.Binding<C.Value>>) -> Result<&2, &2, M.Diagnostic, Runtime>:
  M.CheckedModule{+constants, +functions, types, operations} = checked
  +catalog = {Catalog{function_index(functions, Map.new(&2, Maybe<&2, M.CheckedFunction>)), constant_index(bindings, Map.new(&2, Maybe<&2, C.Value>)), Init.index(Init.bindings(constants), MTip{})} : Catalog}
  do Result<&2, &2, M.Diagnostic, Runtime>:
    +state : State <- walk(U32.to_nat(1048576), List.append(&2, Work, function_roots(functions), constant_roots(constants)), catalog, State{Map.new(&2, Bool), Map.new(&2, Bool), Nil{}, Set.new(), Set.new()})
    return Runtime{M.CheckedModule{keep_constants(constants, state), keep_functions(functions, state), types, operations}, keep_bindings(bindings, state), reached_lambdas(state), used_constructors(state), used_operations(state)}
