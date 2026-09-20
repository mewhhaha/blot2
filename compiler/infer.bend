import Base
import ./model.bend as M
import ./types.bend as T
import ./type_data.bend as D
import ./dependency.bend as Graph

type Binding is Data:
  Binding{name: String, inferred_type: M.Ty, variables: List<&2, Nat>}

type Label is Data:
  Label{identity: Nat, result: M.Ty}

type Context is Data:
  Context{globals: List<&2, Binding>, locals: List<&2, Binding>, labels: List<&2, Label>, descriptors: List<&2, M.Descriptor>, data_types: List<&2, M.DataType>, subject: String, function_names: List<&2, String>}

type Requirement is Data:
  AccessRequirement{access: M.Access, target: M.Ty}
  CallRequirement{callee: String}
  ConstantRequirement{name: String}

type PurityConstraint is Data:
  PurityConstraint{subject: String, requirements: List<&2, Requirement>}
  FunctionPurityConstraint{subject: String, requirements: List<&2, Requirement>}

type Coverage is Data:
  Coverage{inferred_type: M.Ty, patterns: List<&2, M.Pattern>, subject: String}

type Inference is Data:
  Inference{inferred_type: M.Ty, requirements: List<&2, Requirement>, purity: List<&2, PurityConstraint>, coverage: List<&2, Coverage>, exits: List<&2, Nat>}

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
  Inference{ty, requirements, purity, coverage, exits} = inference
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
  Inference{ty, Nil{}, Nil{}, Nil{}, Nil{}}

def join(left: Inference, right: Inference, ty: M.Ty) -> Inference:
  Inference{lt, lr, lp, lc, lx} = left
  Inference{rt, rr, rp, rc, rx} = right
  Inference{ty, List.append(&2, Requirement, lr, rr), List.append(&2, PurityConstraint, lp, rp), List.append(&2, Coverage, lc, rc), T.union(lx, rx)}

def reachable_exits(ty: M.Ty, left: List<&2, Nat>, right: List<&2, Nat>) -> List<&2, Nat>:
  match ty:
    case M.NeverTy{}:
      left
    case _:
      T.union(left, right)

def sequence(left: Inference, right: Inference, ty: M.Ty) -> Inference:
  Inference{lt, lr, lp, lc, lx} = left
  Inference{rt, rr, rp, rc, rx} = right
  Inference{ty, List.append(&2, Requirement, lr, rr), List.append(&2, PurityConstraint, lp, rp), List.append(&2, Coverage, lc, rc), reachable_exits(lt, lx, rx)}

def add_requirement(inference: Inference, requirement: Requirement) -> Inference:
  Inference{ty, requirements, purity, coverage, exits} = inference
  Inference{ty, requirement <> requirements, purity, coverage, exits}

def pure_rhs(inference: Inference, subject: String) -> Inference:
  Inference{ty, +requirements, purity, coverage, exits} = inference
  Inference{ty, requirements, PurityConstraint{subject, requirements} <> purity, coverage, exits}

def lambda_value(inference: Inference, parameter: M.Ty, result: M.Ty, subject: String) -> Inference:
  Inference{ty, requirements, purity, coverage, exits} = inference
  Inference{M.FunctionTy{parameter, result}, Nil{}, FunctionPurityConstraint{subject, requirements} <> purity, coverage, Nil{}}

def add_coverage(inference: Inference, ty: M.Ty, patterns: List<&2, M.Pattern>, subject: String) -> Inference:
  Inference{result, requirements, purity, coverage, exits} = inference
  Inference{result, requirements, purity, Coverage{ty, patterns, subject} <> coverage, exits}

def block_result(caught: Bool, body: M.Ty, result: M.Ty) -> M.Ty:
  match caught:
    case True{}:
      result
    case False{}:
      body

def block_value(inference: Inference, +label: Nat, result: M.Ty) -> Inference:
  Inference{ty, requirements, purity, coverage, +exits} = inference
  Inference{block_result(T.contains(exits, label), ty, result), requirements, purity, coverage, T.difference(exits, [label])}

def return_value(inference: Inference, label: Nat) -> Inference:
  Inference{ty, requirements, purity, coverage, exits} = inference
  Inference{M.NeverTy{}, requirements, purity, coverage, reachable_exits(ty, exits, [label])}

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

def unify(left: M.Ty, right: M.Ty, state: State, subject: String) -> Result<&2, &2, M.Diagnostic, State>:
  State{substitutions, next} = state
  do Result<&2, &2, M.Diagnostic, State>:
    solved : List<&2, T.Substitution> <- T.unify(left, right, substitutions, subject)
    return State{solved, next}

def context_subject(context: Context) -> String:
  Context{globals, locals, labels, descriptors, types, subject, functions} = context
  subject

def context_types(context: Context) -> List<&2, M.DataType>:
  Context{globals, locals, labels, descriptors, types, subject, functions} = context
  types

def at_subject(context: Context, subject: String) -> Context:
  Context{globals, locals, labels, descriptors, types, previous, functions} = context
  Context{globals, locals, labels, descriptors, types, subject, functions}

def extend(context: Context, bindings: List<&2, Binding>) -> Context:
  Context{globals, locals, labels, descriptors, types, subject, functions} = context
  Context{globals, List.append(&2, Binding, bindings, locals), labels, descriptors, types, subject, functions}

def in_lambda(context: Context, name: String, ty: M.Ty) -> Context:
  Context{globals, locals, labels, descriptors, types, subject, functions} = context
  Context{globals, Binding{name, ty, Nil{}} <> locals, Nil{}, descriptors, types, subject, functions}

def in_block(context: Context, label: Nat, ty: M.Ty) -> Context:
  Context{globals, locals, labels, descriptors, types, subject, functions} = context
  Context{globals, locals, Label{label, ty} <> labels, descriptors, types, subject, functions}

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
  Context{globals, locals, labels, descriptors, types, subject, functions} = context
  lookup_binding(globals, name)

def lookup_local(context: Context, name: String) -> Maybe<&2, Binding>:
  Context{globals, locals, labels, descriptors, types, subject, functions} = context
  lookup_binding(locals, name)

def valid_global_kind(context: Context, +name: String, function: Bool) -> Result<&2, &2, M.Diagnostic, Unit>:
  Context{globals, locals, labels, descriptors, types, subject, functions} = context
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
  Context{globals, locals, labels, descriptors, types, subject, functions} = context
  lookup_label(labels, identity, subject)

def instance(variables: List<&2, Nat>, ty: M.Ty, +next: Nat) -> Result<&2, &2, M.Diagnostic, SchemeInstance>:
  match variables:
    case Nil{}:
      Done{SchemeInstance{ty, next}}
    case head <> tail:
      do Result<&2, &2, M.Diagnostic, SchemeInstance>:
        replaced : M.Ty <- T.replace(ty, head, M.VariableTy{next})
        instance(tail, replaced, 1n+next)

def instance_typing(value: SchemeInstance, substitutions: List<&2, T.Substitution>) -> Typing:
  SchemeInstance{ty, next} = value
  Typing{pure(ty), State{substitutions, next}}

def instantiate_binding(found: Maybe<&2, Binding>, state: State, name: String, subject: String) -> Result<&2, &2, M.Diagnostic, Typing>:
  match found:
    case None{}:
      Fail{M.Diagnostic{"unknown_name", subject, "unknown value " ++ name}}
    case Some{Binding{binding_name, ty, variables}}:
      State{+substitutions, next} = state
      do Result<&2, &2, M.Diagnostic, Typing>:
        resolved : M.Ty <- T.resolve(substitutions, ty)
        instantiated : SchemeInstance <- instance(variables, resolved, next)
        return instance_typing(instantiated, substitutions)

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
  Context{globals, locals, labels, descriptors, types, subject, functions} = context
  List.append(&2, Binding, globals, List.append(&2, Binding, locals, label_bindings(labels)))

def generalize_variables(variables: List<&2, Nat>, ty: M.Ty, context: Context, state: State, name: String) -> Result<&2, &2, M.Diagnostic, Binding>:
  match variables:
    case Nil{}:
      Done{Binding{name, ty, Nil{}}}
    case head <> tail:
      do Result<&2, &2, M.Diagnostic, Binding>:
        excluded : List<&2, Nat> <- binding_free(environment_bindings(context), substitutions_of(state))
        return Binding{name, ty, T.difference(head <> tail, excluded)}

def generalize(ty: M.Ty, context: Context, +state: State, name: String) -> Result<&2, &2, M.Diagnostic, Binding>:
  do Result<&2, &2, M.Diagnostic, Binding>:
    +resolved : M.Ty <- T.resolve(substitutions_of(state), ty)
    variables : List<&2, Nat> <- T.free(resolved)
    generalize_variables(variables, resolved, context, state, name)

def annotation(annotation: Maybe<&2, M.Ty>, ty: M.Ty, state: State, context: Context) -> Result<&2, &2, M.Diagnostic, State>:
  match annotation:
    case None{}:
      Done{state}
    case Some{+expected}:
      Context{globals, locals, labels, descriptors, types, +subject, functions} = context
      do Result<&2, &2, M.Diagnostic, State>:
        valid : Unit <- D.annotation(Some{expected}, descriptors, types, subject)
        unify(expected, ty, state, subject)

def constructor_instance(name: String, +context: Context, +state: State) -> Result<&2, &2, M.Diagnostic, D.ConstructorType>:
  +constructor_name = name
  D.instantiate(D.constructor(context_types(context), constructor_name), constructor_name, next_of(state), context_subject(context))

def constructor_type(value: D.ConstructorType) -> M.Ty:
  match value:
    case D.ConstructorType{result, None{}, next}:
      result
    case D.ConstructorType{result, Some{payload}, next}:
      M.FunctionTy{payload, result}

def constructor_result(value: D.ConstructorType) -> M.Ty:
  D.ConstructorType{result, payload, next} = value
  result

def constructor_payload(value: D.ConstructorType) -> Maybe<&2, M.Ty>:
  D.ConstructorType{result, payload, next} = value
  payload

def constructor_state(value: D.ConstructorType, state: State) -> State:
  D.ConstructorType{result, payload, next} = value
  with_next(state, next)

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

def infer_pattern(value: M.Pattern, +expected: M.Ty, +context: Context, +state: State) -> Result<&2, &2, M.Diagnostic, PatternTyping>:
  match value:
    case M.WildcardPattern{}:
      Done{PatternTyping{Nil{}, state}}
    case M.BindingPattern{name}:
      Done{PatternTyping{[Binding{name, expected, Nil{}}], state}}
    case M.UnitPattern{}:
      do Result<&2, &2, M.Diagnostic, PatternTyping>:
        next : State <- unify(expected, M.UnitTy{}, state, context_subject(context))
        return PatternTyping{Nil{}, next}
    case M.U32Pattern{value}:
      do Result<&2, &2, M.Diagnostic, PatternTyping>:
        next : State <- unify(expected, M.U32Ty{}, state, context_subject(context))
        return PatternTyping{Nil{}, next}
    case M.BoolPattern{value}:
      do Result<&2, &2, M.Diagnostic, PatternTyping>:
        next : State <- unify(expected, M.BoolTy{}, state, context_subject(context))
        return PatternTyping{Nil{}, next}
    case M.ConstructorPattern{name, None{}}:
      do Result<&2, &2, M.Diagnostic, PatternTyping>:
        +ctor : D.ConstructorType <- constructor_instance(name, context, state)
        arity : Unit <- no_payload(constructor_payload(ctor), context_subject(context))
        next : State <- unify(expected, constructor_result(ctor), constructor_state(ctor, state), context_subject(context))
        return PatternTyping{Nil{}, next}
    case M.ConstructorPattern{name, Some{payload}}:
      do Result<&2, &2, M.Diagnostic, PatternTyping>:
        +ctor : D.ConstructorType <- constructor_instance(name, context, state)
        ty : M.Ty <- payload_type(constructor_payload(ctor), context_subject(context))
        next : State <- unify(expected, constructor_result(ctor), constructor_state(ctor, state), context_subject(context))
        infer_pattern(payload, ty, context, next)

type Work is Data:
  Expression{value: M.Expr}
  MatchArms{values: List<&2, M.MatchArm<M.Expr>>, scrutinee: M.Ty}

def arm_patterns(arms: List<&2, M.MatchArm<M.Expr>>) -> List<&2, M.Pattern>:
  match arms:
    case Nil{}:
      Nil{}
    case M.MatchArm{pattern, body} <> tail:
      pattern <> arm_patterns(tail)

def guard_exits(ty: M.Ty, subject: String) -> Result<&2, &2, M.Diagnostic, Unit>:
  match ty:
    case M.NeverTy{}:
      Done{Unit{}}
    case other:
      Fail{M.Diagnostic{"guard_fallthrough", subject, "let-else fallback must exit its enclosing do block"}}

def requirements_of(inference: Inference) -> List<&2, Requirement>:
  Inference{ty, requirements, purity, coverage, exits} = inference
  requirements

def function_reference(typing: Typing, name: String, subject: String) -> Typing:
  Typing{Inference{ty, requirements, purity, coverage, exits}, state} = typing
  Typing{Inference{ty, requirements, FunctionPurityConstraint{subject, [CallRequirement{name}]} <> purity, coverage, exits}, state}

def with_type(typing: Typing, ty: M.Ty) -> Typing:
  Typing{Inference{old, requirements, purity, coverage, exits}, state} = typing
  Typing{Inference{ty, requirements, purity, coverage, exits}, state}

def add_global_requirement(typing: Typing, name: String) -> Typing:
  Typing{inference, state} = typing
  Typing{add_requirement(inference, ConstantRequirement{name}), state}

def access(typing: Typing, access: M.Access) -> Typing:
  Typing{Inference{+ty, requirements, purity, coverage, exits}, state} = typing
  Typing{Inference{flow(ty, M.UnitTy{}), AccessRequirement{access, ty} <> requirements, purity, coverage, exits}, state}

def infer_read(+identity: M.TypeId, context: Context, state: State) -> Result<&2, &2, M.Diagnostic, Typing>:
  Context{globals, locals, labels, descriptors, types, subject, functions} = context
  do Result<&2, &2, M.Diagnostic, Typing>:
    registered : Unit <- D.require_storage(D.known_storage(descriptors, identity), identity)
    +ty : M.Ty <- D.storage_type(D.lookup(types, identity), identity)
    return Typing{Inference{ty, [AccessRequirement{M.Read{}, ty}], Nil{}, Nil{}, Nil{}}, state}

def expr_work(+fuel: Nat, work: Work, +context: Context, +state: State) -> Result<&2, &2, M.Diagnostic, Typing>:
  match fuel work:
    case 0n _:
      Fail{M.Diagnostic{"expression_complexity", context_subject(context), "expression nesting exceeds compiler traversal limit"}}
    case 1n+rest Expression{M.UnitExpr{}}:
      Done{Typing{pure(M.UnitTy{}), state}}
    case 1n+rest Expression{M.U32Expr{value}}:
      Done{Typing{pure(M.U32Ty{}), state}}
    case 1n+rest Expression{M.BoolExpr{value}}:
      Done{Typing{pure(M.BoolTy{}), state}}
    case 1n+rest Expression{M.LocalExpr{+name}}:
      instantiate_binding(lookup_local(context, name), state, name, context_subject(context))
    case 1n+rest Expression{M.ConstantExpr{+name}}:
      do Result<&2, &2, M.Diagnostic, Typing>:
        valid : Unit <- valid_global_kind(context, name, False{})
        found : Typing <- instantiate_binding(lookup_global(context, name), state, name, context_subject(context))
        return add_global_requirement(found, name)
    case 1n+rest Expression{M.FunctionExpr{+name}}:
      do Result<&2, &2, M.Diagnostic, Typing>:
        valid : Unit <- valid_global_kind(context, name, True{})
        found : Typing <- instantiate_binding(lookup_global(context, name), state, name, context_subject(context))
        return function_reference(found, name, context_subject(context))
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
      do Result<&2, &2, M.Diagnostic, Typing>:
        s1 : State <- annotation(p, parameter_ty, with_next(state, 2n+next_of(state)), context)
        s2 : State <- annotation(r, result_ty, s1, context)
        +value : Typing <- expr_work(rest, Expression{body}, in_lambda(context, parameter, parameter_ty), s2)
        next : State <- unify(type_of(value), result_ty, state_of(value), context_subject(context))
        return Typing{lambda_value(inference_of(value), parameter_ty, result_ty, context_subject(context)), next}
    case 1n+rest Expression{M.ApplyExpr{callee, argument}}:
      do Result<&2, &2, M.Diagnostic, Typing>:
        +fn : Typing <- expr_work(rest, Expression{callee}, context, state)
        +arg : Typing <- expr_work(rest, Expression{argument}, context, state_of(fn))
        +result : M.Ty = M.VariableTy{next_of(state_of(arg))}
        next : State <- unify(type_of(fn), M.FunctionTy{type_of(arg), result}, with_next(state_of(arg), 1n+next_of(state_of(arg))), context_subject(context))
        return Typing{sequence(inference_of(fn), inference_of(arg), flow(type_of(fn), flow(type_of(arg), result))), next}
    case 1n+rest Expression{M.CallExpr{+callee, argument}}:
      do Result<&2, &2, M.Diagnostic, Typing>:
        valid : Unit <- valid_global_kind(context, callee, True{})
        +fn : Typing <- instantiate_binding(lookup_global(context, callee), state, callee, context_subject(context))
        +arg : Typing <- expr_work(rest, Expression{argument}, context, state_of(fn))
        +result : M.Ty = M.VariableTy{next_of(state_of(arg))}
        next : State <- unify(type_of(fn), M.FunctionTy{type_of(arg), result}, with_next(state_of(arg), 1n+next_of(state_of(arg))), context_subject(context))
        return Typing{add_requirement(join(inference_of(fn), inference_of(arg), flow(type_of(arg), result)), CallRequirement{callee}), next}
    case 1n+rest Expression{M.ScalarExpr{operator, left, right}}:
      do Result<&2, &2, M.Diagnostic, Typing>:
        +l : Typing <- expr_work(rest, Expression{left}, context, state)
        +r : Typing <- expr_work(rest, Expression{right}, context, state_of(l))
        s1 : State <- unify(type_of(l), M.U32Ty{}, state_of(r), context_subject(context))
        s2 : State <- unify(type_of(r), M.U32Ty{}, s1, context_subject(context))
        return Typing{sequence(inference_of(l), inference_of(r), flow(type_of(l), flow(type_of(r), M.scalar_result(operator)))), s2}
    case 1n+rest Expression{M.LetExpr{+name, value, body}}:
      do Result<&2, &2, M.Diagnostic, Typing>:
        +v : Typing <- expr_work(rest, Expression{value}, context, state)
        binding : Binding <- generalize(type_of(v), context, state_of(v), name)
        +b : Typing <- expr_work(rest, Expression{body}, extend(context, [binding]), state_of(v))
        return Typing{sequence(pure_rhs(inference_of(v), context_subject(context)), inference_of(b), flow(type_of(v), type_of(b))), state_of(b)}
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
    case 1n+rest Expression{M.MatchExpr{value, +arms}}:
      do Result<&2, &2, M.Diagnostic, Typing>:
        +v : Typing <- expr_work(rest, Expression{value}, context, state)
        +a : Typing <- expr_work(rest, MatchArms{arms, type_of(v)}, context, state_of(v))
        return Typing{add_coverage(sequence(inference_of(v), inference_of(a), flow(type_of(v), type_of(a))), type_of(v), arm_patterns(arms), context_subject(context)), state_of(a)}
    case 1n+rest Expression{M.GuardExpr{pat, value, alternative, body}}:
      do Result<&2, &2, M.Diagnostic, Typing>:
        +v : Typing <- expr_work(rest, Expression{value}, context, state)
        +bindings : PatternTyping <- infer_pattern(pat, type_of(v), context, state_of(v))
        +a : Typing <- expr_work(rest, Expression{alternative}, context, pattern_state(bindings))
        exit : Unit <- guard_exits(type_of(a), context_subject(context))
        +b : Typing <- expr_work(rest, Expression{body}, extend(context, pattern_bindings(bindings)), state_of(a))
        +result : M.Ty = flow(type_of(v), type_of(b))
        return Typing{sequence(pure_rhs(inference_of(v), context_subject(context)), join(inference_of(a), inference_of(b), result), result), state_of(b)}
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
    case 1n+rest Expression{M.ReadExpr{+identity}}:
      infer_read(identity, context, state)
    case 1n+rest Expression{M.WriteExpr{value}}:
      do Result<&2, &2, M.Diagnostic, Typing>:
        v : Typing <- expr_work(rest, Expression{value}, context, state)
        return access(v, M.Write{})
    case 1n+rest Expression{M.InsertExpr{value}}:
      do Result<&2, &2, M.Diagnostic, Typing>:
        v : Typing <- expr_work(rest, Expression{value}, context, state)
        return access(v, M.Insert{})
    case 1n+rest MatchArms{Nil{}, scrutinee}:
      Done{Typing{pure(M.NeverTy{}), state}}
    case 1n+rest MatchArms{M.MatchArm{pat, body} <> tail, +scrutinee}:
      do Result<&2, &2, M.Diagnostic, Typing>:
        +bindings : PatternTyping <- infer_pattern(pat, scrutinee, context, state)
        +b : Typing <- expr_work(rest, Expression{body}, extend(context, pattern_bindings(bindings)), pattern_state(bindings))
        +t : Typing <- expr_work(rest, MatchArms{tail, scrutinee}, context, state_of(b))
        next : State <- unify(type_of(b), type_of(t), state_of(t), context_subject(context))
        return Typing{join(inference_of(b), inference_of(t), branch_type(type_of(b), type_of(t))), next}

def expr(expression: M.Expr, context: Context, state: State) -> Result<&2, &2, M.Diagnostic, Typing>:
  expr_work(Nat.mul(256n, 256n), Expression{expression}, context, state)
