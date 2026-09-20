import Base
import ./model.bend as M
import ./types.bend as T
import ./type_data.bend as D
import ./effect_rows.bend as R
import ./dependency.bend as Graph

type Binding is Data:
  Binding{name: String, inferred_type: M.Ty, variables: List<&2, Nat>}

type Label is Data:
  Label{identity: Nat, result: M.Ty}

type Context is Data:
  Context{globals: List<&2, Binding>, locals: List<&2, Binding>, labels: List<&2, Label>, data_types: List<&2, M.DataType>, operations: List<&2, M.Operation>, subject: String, function_names: List<&2, String>, ambient: M.EffectRow}

type Reflection is Data:
  Reflection{callee: String, subject: String}

type Coverage is Data:
  Coverage{inferred_types: List<&2, M.Ty>, patterns: List<&2, List<&2, M.Pattern>>, subject: String}

type Inference is Data:
  Inference{inferred_type: M.Ty, coverage: List<&2, Coverage>, exits: List<&2, Nat>, reflections: List<&2, Reflection>}

type State is Data:
  State{substitutions: List<&2, T.Substitution>, next: Nat}

type Typing is Data:
  Typing{inference: Inference, state: State}

type Definition is Data:
  Definition{name: String, inference: Inference}

type SchemeInstance is Data:
  SchemeInstance{inferred_type: M.Ty, next: Nat}

type PatternTyping is Data:
  PatternTyping{bindings: List<&2, Binding>, state: State}

def inferred_type(inference: Inference) -> M.Ty:
  Inference{ty, coverage, exits, reflections} = inference
  ty

def inference_of(typing: Typing) -> Inference:
  Typing{inference, state} = typing
  inference

def state_of(typing: Typing) -> State:
  Typing{inference, state} = typing
  state

def type_of(typing: Typing) -> M.Ty:
  inferred_type(inference_of(typing))

def next_of(state: State) -> Nat:
  State{substitutions, next} = state
  next

def substitutions_of(state: State) -> List<&2, T.Substitution>:
  State{substitutions, next} = state
  substitutions

def with_next(state: State, next: Nat) -> State:
  State{substitutions, previous} = state
  State{substitutions, next}

def pure(ty: M.Ty) -> Inference:
  Inference{ty, Nil{}, Nil{}, Nil{}}

def join(left: Inference, right: Inference, ty: M.Ty) -> Inference:
  Inference{lt, lc, lx, lr} = left
  Inference{rt, rc, rx, rr} = right
  Inference{ty, List.append(&2, Coverage, lc, rc), T.union(lx, rx), List.append(&2, Reflection, lr, rr)}

def reachable_exits(ty: M.Ty, left: List<&2, Nat>, right: List<&2, Nat>) -> List<&2, Nat>:
  match ty:
    case M.NeverTy{}:
      left
    case _:
      T.union(left, right)

def sequence(left: Inference, right: Inference, ty: M.Ty) -> Inference:
  Inference{lt, lc, lx, lr} = left
  Inference{rt, rc, rx, rr} = right
  Inference{ty, List.append(&2, Coverage, lc, rc), reachable_exits(lt, lx, rx), List.append(&2, Reflection, lr, rr)}

def lambda_value(inference: Inference, parameter: M.Ty, result: M.Ty, effects: M.EffectRow) -> Inference:
  Inference{ty, coverage, exits, reflections} = inference
  Inference{M.FunctionTy{parameter, result, effects}, coverage, Nil{}, reflections}

def add_coverage(inference: Inference, types: List<&2, M.Ty>, patterns: List<&2, List<&2, M.Pattern>>, subject: String) -> Inference:
  Inference{result, coverage, exits, reflections} = inference
  Inference{result, Coverage{types, patterns, subject} <> coverage, exits, reflections}

def block_result(caught: Bool, body: M.Ty, result: M.Ty) -> M.Ty:
  match caught:
    case True{}:
      result
    case False{}:
      body

def block_value(inference: Inference, +label: Nat, result: M.Ty) -> Inference:
  Inference{ty, coverage, +exits, reflections} = inference
  Inference{block_result(T.contains(exits, label), ty, result), coverage, T.difference(exits, [label]), reflections}

def return_value(inference: Inference, label: Nat) -> Inference:
  Inference{ty, coverage, exits, reflections} = inference
  Inference{M.NeverTy{}, coverage, reachable_exits(ty, exits, [label]), reflections}

def flow(first: M.Ty, next: M.Ty) -> M.Ty:
  match first:
    case M.NeverTy{}:
      M.NeverTy{}
    case _:
      next

def branch_type(left: M.Ty, right: M.Ty) -> M.Ty:
  match left:
    case M.NeverTy{}:
      right
    case other:
      other

def solved_state(solution: T.Solution) -> State:
  T.Solution{substitutions, next} = solution
  State{substitutions, next}

def unify(left: M.Ty, right: M.Ty, state: State, subject: String) -> Result<&2, &2, M.Diagnostic, State>:
  State{substitutions, next} = state
  do Result<&2, &2, M.Diagnostic, State>:
    solved : T.Solution <- T.unify_at(left, right, substitutions, next, subject)
    return solved_state(solved)

def unify_rows(left: M.EffectRow, right: M.EffectRow, state: State, subject: String) -> Result<&2, &2, M.Diagnostic, State>:
  State{substitutions, next} = state
  do Result<&2, &2, M.Diagnostic, State>:
    solved : T.Solution <- T.unify_rows_at(left, right, substitutions, next, subject)
    return solved_state(solved)

def context_subject(context: Context) -> String:
  Context{globals, locals, labels, types, operations, subject, functions, ambient} = context
  subject

def context_types(context: Context) -> List<&2, M.DataType>:
  Context{globals, locals, labels, types, operations, subject, functions, ambient} = context
  types

def context_operations(context: Context) -> List<&2, M.Operation>:
  Context{globals, locals, labels, types, operations, subject, functions, ambient} = context
  operations

def context_row(context: Context) -> M.EffectRow:
  Context{globals, locals, labels, types, operations, subject, functions, ambient} = context
  ambient

def with_row(context: Context, ambient: M.EffectRow) -> Context:
  Context{globals, locals, labels, types, operations, subject, functions, previous} = context
  Context{globals, locals, labels, types, operations, subject, functions, ambient}

def at_subject(context: Context, subject: String) -> Context:
  Context{globals, locals, labels, types, operations, previous, functions, ambient} = context
  Context{globals, locals, labels, types, operations, subject, functions, ambient}

def extend(context: Context, bindings: List<&2, Binding>) -> Context:
  Context{globals, locals, labels, types, operations, subject, functions, ambient} = context
  Context{globals, List.append(&2, Binding, bindings, locals), labels, types, operations, subject, functions, ambient}

def in_lambda(context: Context, name: String, ty: M.Ty, ambient: M.EffectRow) -> Context:
  Context{globals, locals, labels, types, operations, subject, functions, previous} = context
  Context{globals, Binding{name, ty, Nil{}} <> locals, Nil{}, types, operations, subject, functions, ambient}

def in_block(context: Context, label: Nat, ty: M.Ty) -> Context:
  Context{globals, locals, labels, types, operations, subject, functions, ambient} = context
  Context{globals, locals, Label{label, ty} <> labels, types, operations, subject, functions, ambient}

def lookup_binding_work(bindings: List<&2, Binding>, +name: String, found: Maybe<&2, Binding>) -> Maybe<&2, Binding>:
  match bindings found:
    case _ Some{binding}:
      Some{binding}
    case Nil{} None{}:
      None{}
    case Binding{+declared, ty, variables} <> tail None{}:
      lookup_binding_work(tail, name, Bool.pick(Maybe<&2, Binding>, M.name_equal(declared, name), Some{Binding{declared, ty, variables}}, None{}))

def lookup_binding(bindings: List<&2, Binding>, name: String) -> Maybe<&2, Binding>:
  lookup_binding_work(bindings, name, None{})

def lookup_global(context: Context, name: String) -> Maybe<&2, Binding>:
  Context{globals, locals, labels, types, operations, subject, functions, ambient} = context
  lookup_binding(globals, name)

def lookup_local(context: Context, name: String) -> Maybe<&2, Binding>:
  Context{globals, locals, labels, types, operations, subject, functions, ambient} = context
  lookup_binding(locals, name)

def valid_global_kind(context: Context, +name: String, function: Bool) -> Result<&2, &2, M.Diagnostic, Unit>:
  Context{globals, locals, labels, types, operations, subject, functions, ambient} = context
  +found = Graph.contains(functions, name)
  +expected = function
  +code = Bool.pick(String, expected, "unknown_function", "unknown_name")
  Bool.pick(Result<&2, &2, M.Diagnostic, Unit>, Bool.not(Bool.xor(found, expected)), Done{Unit{}}, Fail{M.Diagnostic{code, subject, "resolved reference has the wrong definition kind: " ++ name}})

def lookup_label(labels: List<&2, Label>, +identity: Nat, +subject: String) -> Result<&2, &2, M.Diagnostic, M.Ty>:
  match labels:
    case Nil{}:
      Fail{M.Diagnostic{"invalid_return", subject, "return target is not an enclosing do block"}}
    case Label{found, ty} <> tail:
      Bool.pick(Result<&2, &2, M.Diagnostic, M.Ty>, Nat.is_eq(found, identity), Done{ty}, lookup_label(tail, identity, subject))

def return_type(context: Context, identity: Nat) -> Result<&2, &2, M.Diagnostic, M.Ty>:
  Context{globals, locals, labels, types, operations, subject, functions, ambient} = context
  lookup_label(labels, identity, subject)

def instance(variables: List<&2, Nat>, ty: M.Ty, +next: Nat) -> Result<&2, &2, M.Diagnostic, SchemeInstance>:
  match variables:
    case Nil{}:
      Done{SchemeInstance{ty, next}}
    case head <> tail:
      do Result<&2, &2, M.Diagnostic, SchemeInstance>:
        replaced : M.Ty <- T.replace(ty, head, M.VariableTy{next})
        instance(tail, replaced, 1n+next)

def instance_typing(value: SchemeInstance, substitutions: List<&2, T.Substitution>) -> Result<&2, &2, M.Diagnostic, Typing>:
  SchemeInstance{ty, next} = value
  do Result<&2, &2, M.Diagnostic, Typing>:
    +opened : T.Opened <- T.open_covariant(ty, next)
    return Typing{pure(T.opened_type(opened)), State{substitutions, T.opened_next(opened)}}

def instantiate_binding(found: Maybe<&2, Binding>, state: State, name: String, subject: String) -> Result<&2, &2, M.Diagnostic, Typing>:
  match found:
    case None{}:
      Fail{M.Diagnostic{"unknown_name", subject, "unknown value " ++ name}}
    case Some{Binding{binding_name, ty, variables}}:
      State{+substitutions, next} = state
      do Result<&2, &2, M.Diagnostic, Typing>:
        resolved : M.Ty <- T.resolve(substitutions, ty)
        instantiated : SchemeInstance <- instance(variables, resolved, next)
        instance_typing(instantiated, substitutions)

def binding_free(bindings: List<&2, Binding>, +substitutions: List<&2, T.Substitution>) -> Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
  match bindings:
    case Nil{}:
      Done{Nil{}}
    case Binding{name, ty, variables} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
        resolved : M.Ty <- T.resolve(substitutions, ty)
        free : List<&2, Nat> <- T.free(resolved)
        rest : List<&2, Nat> <- binding_free(tail, substitutions)
        return T.union(T.difference(free, variables), rest)

def label_bindings(labels: List<&2, Label>) -> List<&2, Binding>:
  match labels:
    case Nil{}:
      Nil{}
    case Label{identity, result} <> tail:
      Binding{"", result, Nil{}} <> label_bindings(tail)

def environment_bindings(context: Context) -> List<&2, Binding>:
  Context{globals, locals, labels, types, operations, subject, functions, ambient} = context
  List.append(&2, Binding, globals, List.append(&2, Binding, locals, label_bindings(labels)))

def generalize(ty: M.Ty, +context: Context, +state: State, name: String) -> Result<&2, &2, M.Diagnostic, Binding>:
  do Result<&2, &2, M.Diagnostic, Binding>:
    +resolved : M.Ty <- T.resolve(substitutions_of(state), ty)
    free : List<&2, Nat> <- T.free(resolved)
    excluded : List<&2, Nat> <- binding_free(environment_bindings(context), substitutions_of(state))
    +variables : List<&2, Nat> = T.difference(free, T.union(excluded, T.row_free(T.resolve_row(substitutions_of(state), context_row(context)))))
    +closed : M.Ty <- T.close_generalized(resolved, variables)
    remaining : List<&2, Nat> <- T.free(closed)
    return Binding{name, closed, T.difference(variables, T.difference(variables, remaining))}

def annotation(annotation: Maybe<&2, M.Ty>, ty: M.Ty, state: State, context: Context) -> Result<&2, &2, M.Diagnostic, State>:
  match annotation:
    case None{}:
      Done{state}
    case Some{+expected}:
      Context{globals, locals, labels, types, operations, +subject, functions, ambient} = context
      do Result<&2, &2, M.Diagnostic, State>:
        valid : Unit <- D.annotation(Some{expected}, operations, types, subject)
        unify(expected, ty, state, subject)

def constructor_instance(name: String, +context: Context, +state: State) -> Result<&2, &2, M.Diagnostic, D.ConstructorType>:
  +constructor_name = name
  D.instantiate(D.constructor(context_types(context), constructor_name), constructor_name, next_of(state), context_subject(context))

def constructor_type(value: D.ConstructorType) -> M.Ty:
  match value:
    case D.ConstructorType{result, None{}, next}:
      result
    case D.ConstructorType{result, Some{payload}, next}:
      M.FunctionTy{payload, result, R.variable_row(next)}

def constructor_result(value: D.ConstructorType) -> M.Ty:
  D.ConstructorType{result, payload, next} = value
  result

def constructor_payload(value: D.ConstructorType) -> Maybe<&2, M.Ty>:
  D.ConstructorType{result, payload, next} = value
  payload

def constructor_state(value: D.ConstructorType, state: State) -> State:
  D.ConstructorType{result, payload, next} = value
  with_next(state, 1n+next)

def payload_type(payload: Maybe<&2, M.Ty>, subject: String) -> Result<&2, &2, M.Diagnostic, M.Ty>:
  match payload:
    case None{}:
      Fail{M.Diagnostic{"constructor_arity", subject, "nullary constructor does not accept a payload"}}
    case Some{ty}:
      Done{ty}

def no_payload(payload: Maybe<&2, M.Ty>, subject: String) -> Result<&2, &2, M.Diagnostic, Unit>:
  match payload:
    case None{}:
      Done{Unit{}}
    case Some{ty}:
      Fail{M.Diagnostic{"constructor_arity", subject, "constructor requires a payload"}}

def pattern_state(typing: PatternTyping) -> State:
  PatternTyping{bindings, state} = typing
  state

def pattern_bindings(typing: PatternTyping) -> List<&2, Binding>:
  PatternTyping{bindings, state} = typing
  bindings

def require_new_binding(found: Maybe<&2, Binding>, subject: String, name: String) -> Result<&2, &2, M.Diagnostic, Unit>:
  match found:
    case None{}:
      Done{Unit{}}
    case Some{binding}:
      Fail{M.Diagnostic{"duplicate_pattern_binding", subject, "pattern row binds " ++ name ++ " more than once"}}

type PatternWork is Data:
  PatternValue{pattern: M.Pattern, expected: M.Ty}
  PatternFields{patterns: List<&2, M.Pattern>, expected: List<&2, M.Ty>}

def infer_pattern_work(fuel: Nat, pending: List<&2, PatternWork>, +context: Context, +state: State, +bindings: List<&2, Binding>) -> Result<&2, &2, M.Diagnostic, PatternTyping>:
  match fuel pending:
    case _ Nil{}:
      Done{PatternTyping{bindings, state}}
    case 0n _:
      Fail{M.Diagnostic{"pattern_complexity", context_subject(context), "pattern typing exceeds compiler traversal limit"}}
    case 1n+rest PatternValue{M.WildcardPattern{}, expected} <> tail:
      infer_pattern_work(rest, tail, context, state, bindings)
    case 1n+rest PatternValue{M.BindingPattern{+name}, expected} <> tail:
      do Result<&2, &2, M.Diagnostic, PatternTyping>:
        fresh : Unit <- require_new_binding(lookup_binding(bindings, name), context_subject(context), name)
        infer_pattern_work(rest, tail, context, state, Binding{name, expected, Nil{}} <> bindings)
    case 1n+rest PatternValue{M.UnitPattern{}, expected} <> tail:
      do Result<&2, &2, M.Diagnostic, PatternTyping>:
        next : State <- unify(expected, M.UnitTy{}, state, context_subject(context))
        infer_pattern_work(rest, tail, context, next, bindings)
    case 1n+rest PatternValue{M.U32Pattern{value}, expected} <> tail:
      do Result<&2, &2, M.Diagnostic, PatternTyping>:
        next : State <- unify(expected, M.U32Ty{}, state, context_subject(context))
        infer_pattern_work(rest, tail, context, next, bindings)
    case 1n+rest PatternValue{M.BoolPattern{value}, expected} <> tail:
      do Result<&2, &2, M.Diagnostic, PatternTyping>:
        next : State <- unify(expected, M.BoolTy{}, state, context_subject(context))
        infer_pattern_work(rest, tail, context, next, bindings)
    case 1n+rest PatternValue{M.ConstructorPattern{name, None{}}, expected} <> tail:
      do Result<&2, &2, M.Diagnostic, PatternTyping>:
        +ctor : D.ConstructorType <- constructor_instance(name, context, state)
        arity : Unit <- no_payload(constructor_payload(ctor), context_subject(context))
        next : State <- unify(expected, constructor_result(ctor), constructor_state(ctor, state), context_subject(context))
        infer_pattern_work(rest, tail, context, next, bindings)
    case 1n+rest PatternValue{M.ConstructorPattern{name, Some{payload}}, expected} <> tail:
      do Result<&2, &2, M.Diagnostic, PatternTyping>:
        +ctor : D.ConstructorType <- constructor_instance(name, context, state)
        ty : M.Ty <- payload_type(constructor_payload(ctor), context_subject(context))
        next : State <- unify(expected, constructor_result(ctor), constructor_state(ctor, state), context_subject(context))
        infer_pattern_work(rest, PatternValue{payload, ty} <> tail, context, next, bindings)
    case 1n+rest PatternValue{M.ProductPattern{+elements}, expected} <> tail:
      +count = List.length(&2, M.Pattern, elements)
      +fields = D.fresh_arguments(count, next_of(state))
      do Result<&2, &2, M.Diagnostic, PatternTyping>:
        arity : Unit <- D.require_product_arity(count, context_subject(context))
        next : State <- unify(expected, M.ProductTy{fields}, with_next(state, Nat.add(next_of(state), count)), context_subject(context))
        infer_pattern_work(rest, PatternFields{elements, fields} <> tail, context, next, bindings)
    case 1n+rest PatternFields{Nil{}, Nil{}} <> tail:
      infer_pattern_work(rest, tail, context, state, bindings)
    case 1n+rest PatternFields{pattern <> following, ty <> remaining} <> tail:
      infer_pattern_work(rest, PatternValue{pattern, ty} <> PatternFields{following, remaining} <> tail, context, state, bindings)
    case 1n+rest PatternFields{patterns, expected} <> tail:
      Fail{M.Diagnostic{"internal_error", context_subject(context), "product pattern fields lost their inferred types"}}

def infer_pattern(value: M.Pattern, expected: M.Ty, context: Context, state: State) -> Result<&2, &2, M.Diagnostic, PatternTyping>:
  infer_pattern_work(U32.to_nat(65536), [PatternValue{value, expected}], context, state, Nil{})

type Work is Data:
  Expression{value: M.Expr}
  MatchArms{values: List<&2, M.MatchArm<M.Expr>>, scrutinees: List<&2, M.Ty>}
  MatchValues{values: List<&2, M.Expr>, types: List<&2, M.Ty>, arms: List<&2, M.MatchArm<M.Expr>>, accumulated: Inference}
  ProductValues{values: List<&2, M.Expr>, types: List<&2, M.Ty>, accumulated: Inference}
  ArrayValues{values: List<&2, M.Expr>, element: M.Ty, accumulated: Inference}

def arm_patterns(arms: List<&2, M.MatchArm<M.Expr>>) -> List<&2, List<&2, M.Pattern>>:
  match arms:
    case Nil{}:
      Nil{}
    case M.MatchArm{patterns, body} <> tail:
      patterns <> arm_patterns(tail)

def guard_exits(ty: M.Ty, subject: String) -> Result<&2, &2, M.Diagnostic, Unit>:
  match ty:
    case M.NeverTy{}:
      Done{Unit{}}
    case other:
      Fail{M.Diagnostic{"guard_fallthrough", subject, "let-else fallback must exit its enclosing do block"}}

def pure_row(row: M.EffectRow, state: State, subject: String, code: String) -> Result<&2, &2, M.Diagnostic, State>:
  match row:
    case M.EffectRow{Nil{}, tail}:
      unify_rows(M.EffectRow{Nil{}, tail}, M.empty_row(), state, subject)
    case M.EffectRow{head <> tail, rest}:
      Fail{M.Diagnostic{code, subject, "pure evaluation cannot perform " ++ M.type_id_show(head) ++ "; sequence an operation with use inside a provider scope"}}

def require_pure(row: M.EffectRow, +state: State, subject: String, code: String) -> Result<&2, &2, M.Diagnostic, State>:
  pure_row(T.resolve_row(substitutions_of(state), row), state, subject, code)

def merge_pattern_bindings(pending: List<&2, Binding>, +bindings: List<&2, Binding>, +subject: String) -> Result<&2, &2, M.Diagnostic, List<&2, Binding>>:
  match pending:
    case Nil{}:
      Done{bindings}
    case Binding{+name, ty, variables} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, Binding>>:
        fresh : Unit <- require_new_binding(lookup_binding(bindings, name), subject, name)
        merge_pattern_bindings(tail, Binding{name, ty, variables} <> bindings, subject)

def infer_patterns(patterns: List<&2, M.Pattern>, expected: List<&2, M.Ty>, +context: Context, state: State, bindings: List<&2, Binding>) -> Result<&2, &2, M.Diagnostic, PatternTyping>:
  match patterns expected:
    case Nil{} Nil{}:
      Done{PatternTyping{bindings, state}}
    case pattern <> tail ty <> remaining:
      do Result<&2, &2, M.Diagnostic, PatternTyping>:
        +first : PatternTyping <- infer_pattern(pattern, ty, context, state)
        merged : List<&2, Binding> <- merge_pattern_bindings(pattern_bindings(first), bindings, context_subject(context))
        infer_patterns(tail, remaining, context, pattern_state(first), merged)
    case _ _:
      Fail{M.Diagnostic{"match_arity", context_subject(context), "every pattern row must match the scrutinee count"}}

def operation_type(declaration: M.Operation, next: Nat) -> M.Ty:
  M.Operation{identity, parameter, result} = declaration
  M.FunctionTy{parameter, result, R.singleton(identity, M.RowVariable{next})}

def operation_parameter(declaration: M.Operation) -> M.Ty:
  M.Operation{identity, parameter, result} = declaration
  parameter

def operation_result(declaration: M.Operation) -> M.Ty:
  M.Operation{identity, parameter, result} = declaration
  result

type Provider is Data:
  Provider{identity: M.TypeId, effects: M.EffectRow}

def require_provider(ty: M.Ty, subject: String) -> Result<&2, &2, M.Diagnostic, Provider>:
  match ty:
    case M.ProviderTy{identity, effects}:
      Done{Provider{identity, effects}}
    case other:
      Fail{M.Diagnostic{"invalid_provider", subject, "do requires a provider with a known nominal operation, got " ++ M.type_show(other)}}

def provider_row(provider: Provider) -> M.EffectRow:
  Provider{identity, effects} = provider
  effects

def handled_context(+context: Context, provider: Provider) -> Context:
  Provider{identity, effects} = provider
  with_row(context, R.prepend([identity], context_row(context)))

def product_element(elements: List<&2, M.Ty>, index: Nat, subject: String) -> Result<&2, &2, M.Diagnostic, M.Ty>:
  match elements index:
    case head <> tail 0n:
      Done{head}
    case head <> tail 1n+rest:
      product_element(tail, rest, subject)
    case Nil{} _:
      Fail{M.Diagnostic{"product_index", subject, "product projection index is outside its fixed arity"}}

def project_type(ty: M.Ty, index: Nat, subject: String) -> Result<&2, &2, M.Diagnostic, M.Ty>:
  match ty:
    case M.ProductTy{elements}:
      product_element(elements, index, subject)
    case M.NeverTy{}:
      Done{M.NeverTy{}}
    case M.VariableTy{variable}:
      Fail{M.Diagnostic{"unknown_product_shape", subject, "projection requires a known product arity; annotate the parameter with a product type"}}
    case other:
      Fail{M.Diagnostic{"type_mismatch", subject, "projection requires a product, got " ++ M.type_show(other)}}

def expr_work(+fuel: Nat, work: Work, +context: Context, +state: State) -> Result<&2, &2, M.Diagnostic, Typing>:
  match fuel work:
    case 0n _:
      Fail{M.Diagnostic{"expression_complexity", context_subject(context), "expression nesting exceeds compiler traversal limit"}}
    case 1n+rest Expression{M.UnitExpr{}}:
      Done{Typing{pure(M.UnitTy{}), state}}
    case 1n+rest Expression{M.U32Expr{value}}:
      Done{Typing{pure(M.U32Ty{}), state}}
    case 1n+rest Expression{M.F32Expr{value}}:
      Done{Typing{pure(M.F32Ty{}), state}}
    case 1n+rest Expression{M.BoolExpr{value}}:
      Done{Typing{pure(M.BoolTy{}), state}}
    case 1n+rest Expression{M.PanicExpr{message}}:
      Done{Typing{pure(M.NeverTy{}), state}}
    case 1n+rest Expression{M.ProductExpr{+elements}}:
      do Result<&2, &2, M.Diagnostic, Typing>:
        arity : Unit <- D.require_product_arity(List.length(&2, M.Expr, elements), context_subject(context))
        expr_work(rest, ProductValues{elements, Nil{}, pure(M.UnitTy{})}, context, state)
    case 1n+rest Expression{M.ProjectExpr{value, index}}:
      do Result<&2, &2, M.Diagnostic, Typing>:
        +v : Typing <- expr_work(rest, Expression{value}, context, state)
        resolved : M.Ty <- T.resolve(substitutions_of(state_of(v)), type_of(v))
        result : M.Ty <- project_type(resolved, index, context_subject(context))
        return Typing{join(inference_of(v), pure(M.UnitTy{}), result), state_of(v)}
    case 1n+rest Expression{M.ArrayExpr{elements}}:
      expr_work(rest, ArrayValues{elements, M.VariableTy{next_of(state)}, pure(M.UnitTy{})}, context, with_next(state, 1n+next_of(state)))
    case 1n+rest Expression{M.ArrayGetExpr{array, index}}:
      do Result<&2, &2, M.Diagnostic, Typing>:
        +a : Typing <- expr_work(rest, Expression{array}, context, state)
        +i : Typing <- expr_work(rest, Expression{index}, context, state_of(a))
        +element : M.Ty = M.VariableTy{next_of(state_of(i))}
        s1 : State <- unify(type_of(a), M.ArrayTy{element}, with_next(state_of(i), 1n+next_of(state_of(i))), context_subject(context))
        s2 : State <- unify(type_of(i), M.U32Ty{}, s1, context_subject(context))
        return Typing{sequence(inference_of(a), inference_of(i), flow(type_of(a), flow(type_of(i), element))), s2}
    case 1n+rest Expression{M.ArraySetExpr{array, index, value}}:
      do Result<&2, &2, M.Diagnostic, Typing>:
        +a : Typing <- expr_work(rest, Expression{array}, context, state)
        +i : Typing <- expr_work(rest, Expression{index}, context, state_of(a))
        +v : Typing <- expr_work(rest, Expression{value}, context, state_of(i))
        +element : M.Ty = M.VariableTy{next_of(state_of(v))}
        s1 : State <- unify(type_of(a), M.ArrayTy{element}, with_next(state_of(v), 1n+next_of(state_of(v))), context_subject(context))
        s2 : State <- unify(type_of(i), M.U32Ty{}, s1, context_subject(context))
        s3 : State <- unify(type_of(v), element, s2, context_subject(context))
        +result : M.Ty = flow(type_of(a), flow(type_of(i), flow(type_of(v), M.ArrayTy{element})))
        return Typing{sequence(inference_of(a), sequence(inference_of(i), inference_of(v), result), result), s3}
    case 1n+rest Expression{M.ArrayLengthExpr{array}}:
      do Result<&2, &2, M.Diagnostic, Typing>:
        +a : Typing <- expr_work(rest, Expression{array}, context, state)
        element : M.Ty = M.VariableTy{next_of(state_of(a))}
        next : State <- unify(type_of(a), M.ArrayTy{element}, with_next(state_of(a), 1n+next_of(state_of(a))), context_subject(context))
        return Typing{join(inference_of(a), pure(M.UnitTy{}), flow(type_of(a), M.U32Ty{})), next}
    case 1n+rest Expression{M.LocalExpr{+name}}:
      do Result<&2, &2, M.Diagnostic, Typing>:
        +found : Typing <- instantiate_binding(lookup_local(context, name), state, name, context_subject(context))
        return found
    case 1n+rest Expression{M.ConstantExpr{+name}}:
      do Result<&2, &2, M.Diagnostic, Typing>:
        valid : Unit <- valid_global_kind(context, name, False{})
        +found : Typing <- instantiate_binding(lookup_global(context, name), state, name, context_subject(context))
        return found
    case 1n+rest Expression{M.FunctionExpr{+name}}:
      do Result<&2, &2, M.Diagnostic, Typing>:
        valid : Unit <- valid_global_kind(context, name, True{})
        instantiate_binding(lookup_global(context, name), state, name, context_subject(context))
    case 1n+rest Expression{M.ConstructorRefExpr{name}}:
      do Result<&2, &2, M.Diagnostic, Typing>:
        +ctor : D.ConstructorType <- constructor_instance(name, context, state)
        return Typing{pure(constructor_type(ctor)), constructor_state(ctor, state)}
    case 1n+rest Expression{M.ConstructExpr{name, None{}}}:
      do Result<&2, &2, M.Diagnostic, Typing>:
        +ctor : D.ConstructorType <- constructor_instance(name, context, state)
        arity : Unit <- no_payload(constructor_payload(ctor), context_subject(context))
        return Typing{pure(constructor_result(ctor)), constructor_state(ctor, state)}
    case 1n+rest Expression{M.ConstructExpr{name, Some{payload}}}:
      do Result<&2, &2, M.Diagnostic, Typing>:
        +ctor : D.ConstructorType <- constructor_instance(name, context, state)
        expected : M.Ty <- payload_type(constructor_payload(ctor), context_subject(context))
        +value : Typing <- expr_work(rest, Expression{payload}, context, constructor_state(ctor, state))
        next : State <- unify(type_of(value), expected, state_of(value), context_subject(context))
        return Typing{join(inference_of(value), pure(M.UnitTy{}), flow(type_of(value), constructor_result(ctor))), next}
    case 1n+rest Expression{M.LambdaExpr{identity, parameter, p, r, body}}:
      +parameter_ty = {M.VariableTy{next_of(state)} : M.Ty}
      +result_ty = {M.VariableTy{1n+next_of(state)} : M.Ty}
      +row = R.variable_row(2n+next_of(state))
      do Result<&2, &2, M.Diagnostic, Typing>:
        s1 : State <- annotation(p, parameter_ty, with_next(state, 3n+next_of(state)), context)
        s2 : State <- annotation(r, result_ty, s1, context)
        +value : Typing <- expr_work(rest, Expression{body}, in_lambda(context, parameter, parameter_ty, row), s2)
        next : State <- unify(type_of(value), result_ty, state_of(value), context_subject(context))
        return Typing{lambda_value(inference_of(value), parameter_ty, result_ty, row), next}
    case 1n+rest Expression{M.ApplyExpr{callee, argument}}:
      do Result<&2, &2, M.Diagnostic, Typing>:
        +fn : Typing <- expr_work(rest, Expression{callee}, context, state)
        +arg : Typing <- expr_work(rest, Expression{argument}, context, state_of(fn))
        +result : M.Ty = M.VariableTy{next_of(state_of(arg))}
        next : State <- unify(type_of(fn), M.FunctionTy{type_of(arg), result, context_row(context)}, with_next(state_of(arg), 1n+next_of(state_of(arg))), context_subject(context))
        return Typing{sequence(inference_of(fn), inference_of(arg), flow(type_of(fn), flow(type_of(arg), result))), next}
    case 1n+rest Expression{M.CallExpr{+callee, argument}}:
      do Result<&2, &2, M.Diagnostic, Typing>:
        valid : Unit <- valid_global_kind(context, callee, True{})
        +fn : Typing <- instantiate_binding(lookup_global(context, callee), state, callee, context_subject(context))
        +arg : Typing <- expr_work(rest, Expression{argument}, context, state_of(fn))
        +result : M.Ty = M.VariableTy{next_of(state_of(arg))}
        next : State <- unify(type_of(fn), M.FunctionTy{type_of(arg), result, context_row(context)}, with_next(state_of(arg), 1n+next_of(state_of(arg))), context_subject(context))
        return Typing{join(inference_of(fn), inference_of(arg), flow(type_of(arg), result)), next}
    case 1n+rest Expression{M.ScalarExpr{+operator, left, right}}:
      do Result<&2, &2, M.Diagnostic, Typing>:
        +l : Typing <- expr_work(rest, Expression{left}, context, state)
        +r : Typing <- expr_work(rest, Expression{right}, context, state_of(l))
        s1 : State <- unify(type_of(l), M.scalar_parameter(operator), state_of(r), context_subject(context))
        s2 : State <- unify(type_of(r), M.scalar_parameter(operator), s1, context_subject(context))
        return Typing{sequence(inference_of(l), inference_of(r), flow(type_of(l), flow(type_of(r), M.scalar_result(operator)))), s2}
    case 1n+rest Expression{M.UnaryExpr{+operator, value}}:
      do Result<&2, &2, M.Diagnostic, Typing>:
        +v : Typing <- expr_work(rest, Expression{value}, context, state)
        next : State <- unify(type_of(v), M.unary_parameter(operator), state_of(v), context_subject(context))
        return Typing{join(inference_of(v), pure(M.UnitTy{}), flow(type_of(v), M.unary_result(operator))), next}
    case 1n+rest Expression{M.LetExpr{+name, value, body}}:
      +row = R.variable_row(next_of(state))
      do Result<&2, &2, M.Diagnostic, Typing>:
        +v : Typing <- expr_work(rest, Expression{value}, with_row(context, row), with_next(state, 1n+next_of(state)))
        +pure_state : State <- require_pure(row, state_of(v), context_subject(context), "let_effect")
        binding : Binding <- generalize(type_of(v), context, pure_state, name)
        +b : Typing <- expr_work(rest, Expression{body}, extend(context, [binding]), pure_state)
        return Typing{sequence(inference_of(v), inference_of(b), flow(type_of(v), type_of(b))), state_of(b)}
    case 1n+rest Expression{M.UseExpr{name, value, body}}:
      do Result<&2, &2, M.Diagnostic, Typing>:
        +v : Typing <- expr_work(rest, Expression{value}, context, state)
        +b : Typing <- expr_work(rest, Expression{body}, extend(context, [Binding{name, type_of(v), Nil{}}]), state_of(v))
        return Typing{sequence(inference_of(v), inference_of(b), flow(type_of(v), type_of(b))), state_of(b)}
    case 1n+rest Expression{M.IfExpr{condition, consequent, alternative}}:
      do Result<&2, &2, M.Diagnostic, Typing>:
        +c : Typing <- expr_work(rest, Expression{condition}, context, state)
        s1 : State <- unify(type_of(c), M.BoolTy{}, state_of(c), context_subject(context))
        +y : Typing <- expr_work(rest, Expression{consequent}, context, s1)
        +n : Typing <- expr_work(rest, Expression{alternative}, context, state_of(y))
        s2 : State <- unify(type_of(y), type_of(n), state_of(n), context_subject(context))
        +result : M.Ty = flow(type_of(c), branch_type(type_of(y), type_of(n)))
        return Typing{sequence(inference_of(c), join(inference_of(y), inference_of(n), result), result), s2}
    case 1n+rest Expression{M.SequenceExpr{first, next}}:
      do Result<&2, &2, M.Diagnostic, Typing>:
        +a : Typing <- expr_work(rest, Expression{first}, context, state)
        +b : Typing <- expr_work(rest, Expression{next}, context, state_of(a))
        return Typing{sequence(inference_of(a), inference_of(b), flow(type_of(a), type_of(b))), state_of(b)}
    case 1n+rest Expression{M.MatchExpr{Nil{}, arms}}:
      Fail{M.Diagnostic{"match_arity", context_subject(context), "case requires at least one scrutinee"}}
    case 1n+rest Expression{M.MatchExpr{values, arms}}:
      expr_work(rest, MatchValues{values, Nil{}, arms, pure(M.UnitTy{})}, context, state)
    case 1n+rest Expression{M.GuardExpr{pat, value, alternative, body}}:
      +row = R.variable_row(next_of(state))
      do Result<&2, &2, M.Diagnostic, Typing>:
        +v : Typing <- expr_work(rest, Expression{value}, with_row(context, row), with_next(state, 1n+next_of(state)))
        pure_state : State <- require_pure(row, state_of(v), context_subject(context), "let_effect")
        +bindings : PatternTyping <- infer_pattern(pat, type_of(v), context, pure_state)
        +a : Typing <- expr_work(rest, Expression{alternative}, context, pattern_state(bindings))
        exit : Unit <- guard_exits(type_of(a), context_subject(context))
        +b : Typing <- expr_work(rest, Expression{body}, extend(context, pattern_bindings(bindings)), state_of(a))
        +result : M.Ty = flow(type_of(v), type_of(b))
        return Typing{sequence(inference_of(v), join(inference_of(a), inference_of(b), result), result), state_of(b)}
    case 1n+rest Expression{M.BlockExpr{+label, body}}:
      +result = {M.VariableTy{next_of(state)} : M.Ty}
      do Result<&2, &2, M.Diagnostic, Typing>:
        +b : Typing <- expr_work(rest, Expression{body}, in_block(context, label, result), with_next(state, 1n+next_of(state)))
        next : State <- unify(type_of(b), result, state_of(b), context_subject(context))
        return Typing{block_value(inference_of(b), label, result), next}
    case 1n+rest Expression{M.ReturnExpr{+label, value}}:
      do Result<&2, &2, M.Diagnostic, Typing>:
        target : M.Ty <- return_type(context, label)
        +v : Typing <- expr_work(rest, Expression{value}, context, state)
        next : State <- unify(type_of(v), target, state_of(v), context_subject(context))
        return Typing{return_value(inference_of(v), label), next}
    case 1n+rest Expression{M.SourceExpr{+offset, ann, value}}:
      +at = at_subject(context, "offset:" ++ Nat.show(offset))
      do Result<&2, &2, M.Diagnostic, Typing>:
        +v : Typing <- expr_work(rest, Expression{value}, at, state)
        next : State <- annotation(ann, type_of(v), state_of(v), at)
        return Typing{inference_of(v), next}
    case 1n+rest Expression{M.OperationExpr{+identity}}:
      do Result<&2, &2, M.Diagnostic, Typing>:
        declared : M.Operation <- D.require_operation(D.operation(context_operations(context), identity), identity)
        return Typing{pure(operation_type(declared, next_of(state))), with_next(state, 1n+next_of(state))}
    case 1n+rest Expression{M.ProviderExpr{+identity, implementation}}:
      do Result<&2, &2, M.Diagnostic, Typing>:
        +declared : M.Operation <- D.require_operation(D.operation(context_operations(context), identity), identity)
        +handler : Typing <- expr_work(rest, Expression{implementation}, context, state)
        +row : M.EffectRow = R.variable_row(next_of(state_of(handler)))
        next : State <- unify(type_of(handler), M.FunctionTy{operation_parameter(declared), operation_result(declared), row}, with_next(state_of(handler), 1n+next_of(state_of(handler))), context_subject(context))
        return Typing{join(inference_of(handler), pure(M.UnitTy{}), flow(type_of(handler), M.ProviderTy{identity, row})), next}
    case 1n+rest Expression{M.HandleExpr{provider, body}}:
      do Result<&2, &2, M.Diagnostic, Typing>:
        +p : Typing <- expr_work(rest, Expression{provider}, context, state)
        resolved : M.Ty <- T.resolve(substitutions_of(state_of(p)), type_of(p))
        +supplied : Provider <- require_provider(resolved, context_subject(context))
        prepared : State <- unify_rows(provider_row(supplied), context_row(context), state_of(p), context_subject(context))
        +b : Typing <- expr_work(rest, Expression{body}, handled_context(context, supplied), prepared)
        return Typing{sequence(inference_of(p), inference_of(b), flow(type_of(p), type_of(b))), state_of(b)}
    case 1n+rest Expression{M.OperationDescriptorExpr{+identity}}:
      do Result<&2, &2, M.Diagnostic, Typing>:
        known : Unit <- D.valid_effect_label(context_operations(context), identity)
        return Typing{pure(M.EffectDescriptorTy{}), state}
    case 1n+rest Expression{M.FunctionEffectsExpr{+callee}}:
      do Result<&2, &2, M.Diagnostic, Typing>:
        known : Unit <- valid_global_kind(context, callee, True{})
        return Typing{Inference{M.EffectSetTy{}, Nil{}, Nil{}, [Reflection{callee, context_subject(context)}]}, state}
    case 1n+rest Expression{M.EffectHasExpr{set, operation}}:
      do Result<&2, &2, M.Diagnostic, Typing>:
        +a : Typing <- expr_work(rest, Expression{set}, context, state)
        +b : Typing <- expr_work(rest, Expression{operation}, context, state_of(a))
        s1 : State <- unify(type_of(a), M.EffectSetTy{}, state_of(b), context_subject(context))
        s2 : State <- unify(type_of(b), M.EffectDescriptorTy{}, s1, context_subject(context))
        return Typing{sequence(inference_of(a), inference_of(b), flow(type_of(a), flow(type_of(b), M.BoolTy{}))), s2}
    case 1n+rest Expression{M.EffectCountExpr{set}}:
      do Result<&2, &2, M.Diagnostic, Typing>:
        +a : Typing <- expr_work(rest, Expression{set}, context, state)
        next : State <- unify(type_of(a), M.EffectSetTy{}, state_of(a), context_subject(context))
        return Typing{join(inference_of(a), pure(M.UnitTy{}), flow(type_of(a), M.U32Ty{})), next}
    case 1n+rest Expression{M.EffectSameExpr{left, right}}:
      do Result<&2, &2, M.Diagnostic, Typing>:
        +a : Typing <- expr_work(rest, Expression{left}, context, state)
        +b : Typing <- expr_work(rest, Expression{right}, context, state_of(a))
        s1 : State <- unify(type_of(a), M.EffectDescriptorTy{}, state_of(b), context_subject(context))
        s2 : State <- unify(type_of(b), M.EffectDescriptorTy{}, s1, context_subject(context))
        return Typing{sequence(inference_of(a), inference_of(b), flow(type_of(a), flow(type_of(b), M.BoolTy{}))), s2}
    case 1n+rest MatchValues{head <> tail, types, arms, +accumulated}:
      do Result<&2, &2, M.Diagnostic, Typing>:
        +value : Typing <- expr_work(rest, Expression{head}, context, state)
        expr_work(rest, MatchValues{tail, type_of(value) <> types, arms, sequence(accumulated, inference_of(value), flow(inferred_type(accumulated), type_of(value)))}, context, state_of(value))
    case 1n+rest ProductValues{head <> tail, types, +accumulated}:
      do Result<&2, &2, M.Diagnostic, Typing>:
        +value : Typing <- expr_work(rest, Expression{head}, context, state)
        expr_work(rest, ProductValues{tail, type_of(value) <> types, sequence(accumulated, inference_of(value), flow(inferred_type(accumulated), type_of(value)))}, context, state_of(value))
    case 1n+rest ProductValues{Nil{}, types, +accumulated}:
      Done{Typing{join(accumulated, pure(M.UnitTy{}), flow(inferred_type(accumulated), M.ProductTy{List.reverse(&2, M.Ty, types)})), state}}
    case 1n+rest ArrayValues{head <> tail, +element, +accumulated}:
      do Result<&2, &2, M.Diagnostic, Typing>:
        +value : Typing <- expr_work(rest, Expression{head}, context, state)
        next : State <- unify(type_of(value), element, state_of(value), context_subject(context))
        expr_work(rest, ArrayValues{tail, element, sequence(accumulated, inference_of(value), flow(inferred_type(accumulated), type_of(value)))}, context, next)
    case 1n+rest ArrayValues{Nil{}, element, +accumulated}:
      Done{Typing{join(accumulated, pure(M.UnitTy{}), flow(inferred_type(accumulated), M.ArrayTy{element})), state}}
    case 1n+rest MatchValues{Nil{}, types, +arms, +accumulated}:
      +scrutinees = List.reverse(&2, M.Ty, types)
      do Result<&2, &2, M.Diagnostic, Typing>:
        +a : Typing <- expr_work(rest, MatchArms{arms, scrutinees}, context, state)
        return Typing{add_coverage(sequence(accumulated, inference_of(a), flow(inferred_type(accumulated), type_of(a))), scrutinees, arm_patterns(arms), context_subject(context)), state_of(a)}
    case 1n+rest MatchArms{Nil{}, scrutinees}:
      Done{Typing{pure(M.NeverTy{}), state}}
    case 1n+rest MatchArms{M.MatchArm{patterns, body} <> tail, +scrutinees}:
      do Result<&2, &2, M.Diagnostic, Typing>:
        +bindings : PatternTyping <- infer_patterns(patterns, scrutinees, context, state, Nil{})
        +b : Typing <- expr_work(rest, Expression{body}, extend(context, pattern_bindings(bindings)), pattern_state(bindings))
        +t : Typing <- expr_work(rest, MatchArms{tail, scrutinees}, context, state_of(b))
        next : State <- unify(type_of(b), type_of(t), state_of(t), context_subject(context))
        return Typing{join(inference_of(b), inference_of(t), branch_type(type_of(b), type_of(t))), next}


def expr(expression: M.Expr, context: Context, state: State) -> Result<&2, &2, M.Diagnostic, Typing>:
  expr_work(Nat.mul(256n, 256n), Expression{expression}, context, state)
