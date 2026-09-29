import Base
import ./model.bend as M
import ./types.bend as T
import ./index.bend as Index
import ./type_data.bend as D
import ./effect_rows.bend as R
import ./dependency.bend as Graph
import ./state_specialize.bend as TypedState
import ./constraints.bend as C

type Binding is Data:
  Binding{name: String, inferred_type: M.Ty, variables: List<&2, Nat>, predicates: List<&2, M.Predicate>}

type Label is Data:
  Label{identity: Nat, result: M.Ty}

type Context is Data:
  Context{globals: List<&2, Binding>, locals: List<&2, Binding>, labels: List<&2, Label>, data_types: List<&2, M.DataType>, operations: List<&2, M.Operation>, subject: String, function_names: List<&2, String>, ambient: M.EffectRow}

type Reflection is Data:
  Reflection{callee: String, subject: String, instantiated_type: M.Ty, predicates: List<&2, M.Predicate>}

# LetGeneralized records the variables a local let generalized (or whose rows
# its scheme closed) that a deferred associated requirement of its value
# mentions. Selecting that requirement before specialization must not bind
# them: the let's scheme, and so every use of the let, would change. Each
# variable appears both as a parameter type and as a row tail (one index space,
# one kind per index), so every renaming and resolution of types and rows
# carries it along.
type Coverage is Data:
  DemandCall{site: Nat}
  OperationNeed{identity: Nat, template: M.TypeId, arguments: List<&2, M.Ty>, function_type: M.Ty, subject: String}
  AssociatedNeed{identity: Nat, dispatch: M.Dispatch, member: String, templates: List<&2, M.TypeId>, left: M.Ty, right: M.Ty, result: M.Ty, invocation: Maybe<&2, M.EffectRow>, ambient: M.EffectRow, subject: String}
  ValuePatternType{inferred_type: M.Ty, subject: String}
  Coverage{inferred_types: List<&2, M.Ty>, patterns: List<&2, List<&2, M.Pattern>>, subject: String}
  LetGeneralized{witness: M.Ty}
  QualifiedNeed{site: Nat, predicate: M.Predicate, subject: String}
  # Retain the annotation's first-pass variables for SCC peer closure checks.
  QualifiedBoundary{offset: Nat, declared: List<&2, M.Predicate>, subject: String}

type Inference is Data:
  Inference{inferred_type: M.Ty, coverage: List<&2, Coverage>, exits: List<&2, Nat>, reflections: List<&2, Reflection>, predicates: List<&2, M.Predicate>, uses: List<&2, C.UsePlan>}

type State is Data:
  State{substitutions: T.Substitutions, next: Nat, annotations: Map<&2, M.Ty>}

type Typing is Data:
  Typing{inference: Inference, state: State}

type Definition is Data:
  Definition{name: String, inference: Inference}

type SchemeInstance is Data:
  SchemeInstance{inferred_type: M.Ty, predicates: List<&2, M.Predicate>, next: Nat}

type PatternTyping is Data:
  PatternTyping{bindings: List<&2, Binding>, state: State, constraints: List<&2, Coverage>}

def inferred_type(inference: Inference) -> M.Ty:
  Inference{ty, coverage, exits, reflections, predicates, uses} = inference
  ty

def inference_coverage(inference: Inference) -> List<&2, Coverage>:
  Inference{ty, coverage, exits, reflections, predicates, uses} = inference
  coverage

def inference_predicates(inference: Inference) -> List<&2, M.Predicate>:
  Inference{ty, coverage, exits, reflections, predicates, uses} = inference
  predicates

def inference_uses(inference: Inference) -> List<&2, C.UsePlan>:
  Inference{ty, coverage, exits, reflections, predicates, uses} = inference
  uses

def with_predicate(inference: Inference, predicate: M.Predicate) -> Inference:
  Inference{ty, coverage, exits, reflections, predicates, uses} = inference
  Inference{ty, coverage, exits, reflections, predicate <> predicates, uses}

def with_use(inference: Inference, site: Nat, subject: String) -> Inference:
  Inference{+ty, coverage, exits, reflections, +predicates, +uses} = inference
  Inference{ty, coverage, exits, reflections, predicates, C.UsePlan{site, subject, ty, C.unplanned(uses, predicates)} <> uses}

def without_residual(inference: Inference) -> Inference:
  Inference{ty, coverage, exits, reflections, predicates, uses} = inference
  Inference{ty, coverage, exits, reflections, Nil{}, uses}

def plan_needs_reversed(predicates: List<&2, M.Predicate>, +site: Nat, +subject: String, reversed: List<&2, Coverage>) -> List<&2, Coverage>:
  match predicates:
    case Nil{}:
      reversed
    case head <> tail:
      plan_needs_reversed(tail, site, subject, QualifiedNeed{site, head, subject} <> reversed)

def plan_needs(plan: C.UsePlan) -> List<&2, Coverage>:
  C.UsePlan{site, subject, ty, predicates} = plan
  List.reverse(&2, Coverage, plan_needs_reversed(predicates, site, subject, Nil{}))

def execution_needs_reversed(uses: List<&2, C.UsePlan>, reversed: List<&2, Coverage>) -> List<&2, Coverage>:
  match uses:
    case Nil{}:
      List.reverse(&2, Coverage, reversed)
    case C.UsePlan{site, subject, ty, predicates} <> tail:
      execution_needs_reversed(tail, plan_needs_reversed(predicates, site, subject, reversed))

def execution_needs(uses: List<&2, C.UsePlan>) -> List<&2, Coverage>:
  execution_needs_reversed(uses, Nil{})

def inference_of(typing: Typing) -> Inference:
  Typing{inference, state} = typing
  inference

def state_of(typing: Typing) -> State:
  Typing{inference, state} = typing
  state

def type_of(typing: Typing) -> M.Ty:
  inferred_type(inference_of(typing))

def next_of(state: State) -> Nat:
  State{substitutions, next, annotations} = state
  next

def substitutions_of(state: State) -> T.Substitutions:
  State{substitutions, next, annotations} = state
  substitutions

def with_next(state: State, next: Nat) -> State:
  State{substitutions, previous, annotations} = state
  State{substitutions, next, annotations}

def pure(ty: M.Ty) -> Inference:
  Inference{ty, Nil{}, Nil{}, Nil{}, Nil{}, Nil{}}

# Qualified predicate lists can exceed the host stack during source checking.
# Copy only the left spine, retaining all occurrences and their original order.
def append_predicates(left: List<&2, M.Predicate>, right: List<&2, M.Predicate>) -> List<&2, M.Predicate>:
  List.reverse.go(&2, M.Predicate, List.reverse(&2, M.Predicate, left), right)

def join(left: Inference, right: Inference, ty: M.Ty) -> Inference:
  Inference{lt, lc, lx, lr, lp, lu} = left
  Inference{rt, rc, rx, rr, rp, ru} = right
  Inference{ty, List.append(&2, Coverage, lc, rc), T.union(lx, rx), List.append(&2, Reflection, lr, rr), append_predicates(lp, rp), List.append(&2, C.UsePlan, lu, ru)}

def reachable_exits(ty: M.Ty, left: List<&2, Nat>, right: List<&2, Nat>) -> List<&2, Nat>:
  match ty:
    case M.NeverTy{}:
      left
    case _:
      T.union(left, right)

def sequence(left: Inference, right: Inference, ty: M.Ty) -> Inference:
  Inference{lt, lc, lx, lr, lp, lu} = left
  Inference{rt, rc, rx, rr, rp, ru} = right
  Inference{ty, List.append(&2, Coverage, lc, rc), reachable_exits(lt, lx, rx), List.append(&2, Reflection, lr, rr), append_predicates(lp, rp), List.append(&2, C.UsePlan, lu, ru)}

def lambda_value(inference: Inference, parameter: M.Ty, result: M.Ty, effects: M.EffectRow) -> Inference:
  Inference{ty, coverage, exits, reflections, predicates, uses} = inference
  Inference{M.FunctionTy{parameter, result, effects}, coverage, Nil{}, reflections, predicates, uses}

def add_coverage(inference: Inference, types: List<&2, M.Ty>, patterns: List<&2, List<&2, M.Pattern>>, subject: String) -> Inference:
  Inference{result, coverage, exits, reflections, predicates, uses} = inference
  Inference{result, Coverage{types, patterns, subject} <> coverage, exits, reflections, predicates, uses}

def block_result(caught: Bool, body: M.Ty, result: M.Ty) -> M.Ty:
  match caught:
    case True{}:
      result
    case False{}:
      body

def block_value(inference: Inference, +label: Nat, result: M.Ty) -> Inference:
  Inference{ty, coverage, +exits, reflections, predicates, uses} = inference
  Inference{block_result(T.contains(exits, label), ty, result), coverage, T.difference(exits, [label]), reflections, predicates, uses}

def return_value(inference: Inference, label: Nat) -> Inference:
  Inference{ty, coverage, exits, reflections, predicates, uses} = inference
  Inference{M.NeverTy{}, coverage, reachable_exits(ty, exits, [label]), reflections, predicates, uses}

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

def solved_state(solution: T.Solution, annotations: Map<&2, M.Ty>) -> State:
  T.Solution{substitutions, next} = solution
  State{substitutions, next, annotations}

def unify(left: M.Ty, right: M.Ty, state: State, subject: String) -> Result<&2, &2, M.Diagnostic, State>:
  State{substitutions, next, annotations} = state
  do Result<&2, &2, M.Diagnostic, State>:
    solved : T.Solution <- T.unify_at(left, right, substitutions, next, subject)
    return solved_state(solved, annotations)

def unify_rows(left: M.EffectRow, right: M.EffectRow, state: State, subject: String) -> Result<&2, &2, M.Diagnostic, State>:
  State{substitutions, next, annotations} = state
  do Result<&2, &2, M.Diagnostic, State>:
    solved : T.Solution <- T.unify_rows_at(left, right, substitutions, next, subject)
    return solved_state(solved, annotations)

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
  Context{globals, Binding{name, ty, Nil{}, Nil{}} <> locals, Nil{}, types, operations, subject, functions, ambient}

def in_block(context: Context, label: Nat, ty: M.Ty) -> Context:
  Context{globals, locals, labels, types, operations, subject, functions, ambient} = context
  Context{globals, locals, Label{label, ty} <> labels, types, operations, subject, functions, ambient}

def lookup_binding_work(bindings: List<&2, Binding>, +name: String, found: Maybe<&2, Binding>) -> Maybe<&2, Binding>:
  match bindings found:
    case _ Some{binding}:
      Some{binding}
    case Nil{} None{}:
      None{}
    case Binding{+declared, ty, variables, predicates} <> tail None{}:
      lookup_binding_work(tail, name, Bool.pick(Maybe<&2, Binding>, M.name_equal(declared, name), Some{Binding{declared, ty, variables, predicates}}, None{}))

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

def instance_sequential(variables: List<&2, Nat>, ty: M.Ty, predicates: List<&2, M.Predicate>, +next: Nat) -> Result<&2, &2, M.Diagnostic, SchemeInstance>:
  match variables:
    case Nil{}:
      Done{SchemeInstance{ty, predicates, next}}
    case +head <> tail:
      do Result<&2, &2, M.Diagnostic, SchemeInstance>:
        replaced : M.Ty <- T.replace(ty, head, M.VariableTy{next})
        needs : List<&2, M.Predicate> <- C.replace_variable(predicates, head, next)
        instance_sequential(tail, replaced, needs, 1n+next)

def instance_mapped(renaming: T.Renaming, binders: List<&2, Nat>, ty: M.Ty, predicates: List<&2, M.Predicate>, next: Nat) -> Result<&2, &2, M.Diagnostic, SchemeInstance>:
  match renaming:
    case T.Renaming{+mapping, fresh_next, True{}}:
      do Result<&2, &2, M.Diagnostic, SchemeInstance>:
        renamed : M.Ty <- T.rename_type(ty, mapping)
        needs : List<&2, M.Predicate> <- C.rename_list(mapping, predicates)
        return SchemeInstance{renamed, needs, fresh_next}
    case T.Renaming{mapping, fresh_next, False{}}:
      instance_sequential(binders, ty, predicates, next)

def instance_qualified(variables: List<&2, Nat>, ty: M.Ty, predicates: List<&2, M.Predicate>, +next: Nat) -> Result<&2, &2, M.Diagnostic, SchemeInstance>:
  match variables:
    case Nil{}:
      Done{SchemeInstance{ty, predicates, next}}
    case +head <> Nil{}:
      do Result<&2, &2, M.Diagnostic, SchemeInstance>:
        renamed : M.Ty <- T.replace(ty, head, M.VariableTy{next})
        needs : List<&2, M.Predicate> <- C.replace_variable(predicates, head, next)
        return SchemeInstance{renamed, needs, 1n+next}
    case +head <> +tail:
      +binders : List<&2, Nat> = head <> tail
      instance_mapped(T.renaming(binders, next), binders, ty, predicates, next)

def instance(variables: List<&2, Nat>, ty: M.Ty, next: Nat) -> Result<&2, &2, M.Diagnostic, SchemeInstance>:
  instance_qualified(variables, ty, Nil{}, next)

def instance_typing(value: SchemeInstance, substitutions: T.Substitutions, annotations: Map<&2, M.Ty>) -> Result<&2, &2, M.Diagnostic, Typing>:
  SchemeInstance{ty, predicates, next} = value
  do Result<&2, &2, M.Diagnostic, Typing>:
    +opened : T.Opened <- T.open_covariant(ty, next)
    return Typing{Inference{T.opened_type(opened), Nil{}, Nil{}, Nil{}, predicates, Nil{}}, State{substitutions, T.opened_next(opened), annotations}}

# A selected implementation is checked in the ambient row using its opened
# type, while evidence records the same instantiation before covariance opens
# the implementation's own latent rows.
type SelectedInstantiation is Data:
  SelectedInstantiation{typing: Typing, exact: M.Ty}

def selected_typing(value: SelectedInstantiation) -> Typing:
  SelectedInstantiation{typing, exact} = value
  typing

def selected_exact(value: SelectedInstantiation) -> M.Ty:
  SelectedInstantiation{typing, exact} = value
  exact

def selected_instance(value: SchemeInstance, substitutions: T.Substitutions, annotations: Map<&2, M.Ty>) -> Result<&2, &2, M.Diagnostic, SelectedInstantiation>:
  SchemeInstance{+inferred_type, needs, fresh_next} = value
  do Result<&2, &2, M.Diagnostic, SelectedInstantiation>:
    +opened : T.Opened <- T.open_covariant(inferred_type, fresh_next)
    return SelectedInstantiation{Typing{Inference{T.opened_type(opened), Nil{}, Nil{}, Nil{}, needs, Nil{}}, State{substitutions, T.opened_next(opened), annotations}}, inferred_type}

def instantiate_binding_selected(found: Maybe<&2, Binding>, state: State, name: String, subject: String) -> Result<&2, &2, M.Diagnostic, SelectedInstantiation>:
  match found:
    case None{}:
      Fail{M.Diagnostic{"unknown_name", subject, "unknown value " ++ name}}
    case Some{Binding{binding_name, ty, variables, predicates}}:
      State{+substitutions, next, annotations} = state
      do Result<&2, &2, M.Diagnostic, SelectedInstantiation>:
        resolved : M.Ty <- T.resolve(substitutions, ty)
        needs : List<&2, M.Predicate> <- C.resolve_list(substitutions, predicates)
        instantiated : SchemeInstance <- instance_qualified(variables, resolved, needs, next)
        selected_instance(instantiated, substitutions, annotations)

def instantiate_binding(found: Maybe<&2, Binding>, state: State, name: String, subject: String) -> Result<&2, &2, M.Diagnostic, Typing>:
  match found:
    case None{}:
      Fail{M.Diagnostic{"unknown_name", subject, "unknown value " ++ name}}
    case Some{Binding{binding_name, ty, variables, predicates}}:
      State{+substitutions, next, annotations} = state
      do Result<&2, &2, M.Diagnostic, Typing>:
        resolved : M.Ty <- T.resolve(substitutions, ty)
        needs : List<&2, M.Predicate> <- C.resolve_list(substitutions, predicates)
        instantiated : SchemeInstance <- instance_qualified(variables, resolved, needs, next)
        instance_typing(instantiated, substitutions, annotations)

def associated_witness_shape(witness: M.Ty, result: M.Ty, state: State, subject: String) -> Result<&2, &2, M.Diagnostic, State>:
  match witness:
    case M.VariableTy{index}:
      Done{state}
    case M.ParameterTy{index}:
      Done{state}
    case other:
      unify(result, other, state, subject)

# Deferred state calls still have known value relationships before their
# concrete operation identities are selected. Preserve these for callers.
def associated_shape(same: Bool, request: Maybe<&2, TypedState.Request>, +left: M.Ty, +right: M.Ty, +result: M.Ty, +state: State, +subject: String) -> Result<&2, &2, M.Diagnostic, State>:
  match same request:
    case _ Some{TypedState.Write{}}:
      unify(result, M.UnitTy{}, state, subject)
    case True{} _:
      unify(result, M.BoolTy{}, state, subject)
    case _ Some{TypedState.Run{}}:
      +body_result = {M.VariableTy{next_of(state)} : M.Ty}
      +body_row = R.variable_row(1n+next_of(state))
      do Result<&2, &2, M.Diagnostic, State>:
        callback : State <- unify(right, M.FunctionTy{M.UnitTy{}, body_result, body_row}, with_next(state, 2n+next_of(state)), subject)
        unify(result, M.ProductTy{[left, body_result]}, callback, subject)
    case _ Some{TypedState.Reader{}}:
      +implementation = {M.VariableTy{next_of(state)} : M.Ty}
      +body_row = R.variable_row(1n+next_of(state))
      unify(right, M.ProductTy{[implementation, M.FunctionTy{M.UnitTy{}, result, body_row}]}, with_next(state, 2n+next_of(state)), subject)
    case _ Some{TypedState.Writer{}}:
      +implementation = {M.VariableTy{next_of(state)} : M.Ty}
      +body_row = R.variable_row(1n+next_of(state))
      unify(right, M.ProductTy{[implementation, M.FunctionTy{M.UnitTy{}, result, body_row}]}, with_next(state, 2n+next_of(state)), subject)
    case _ Some{TypedState.Read{}}:
      do Result<&2, &2, M.Diagnostic, State>:
        witnessed : M.Ty <- T.resolve(substitutions_of(state), left)
        associated_witness_shape(TypedState.witness(65536n, witnessed), result, state, subject)
    case _ _:
      Done{state}

def result_shape(result_dispatch: Bool, +right: M.Ty, +result: M.Ty, state: State, subject: String) -> Result<&2, &2, M.Diagnostic, State>:
  match result_dispatch:
    case True{}:
      unify(right, M.FunctionTy{M.UnitTy{}, result, M.EffectRow{Nil{}, M.ClosedRow{}}}, state, subject)
    case False{}:
      Done{state}

def binding_free(bindings: List<&2, Binding>, +substitutions: T.Substitutions) -> Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
  match bindings:
    case Nil{}:
      Done{Nil{}}
    case Binding{name, ty, variables, predicates} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
        resolved : M.Ty <- T.resolve(substitutions, ty)
        free : List<&2, Nat> <- T.free(resolved)
        resolved_predicates : List<&2, M.Predicate> <- C.resolve_list(substitutions, predicates)
        predicate_free : List<&2, Nat> <- C.free_list(resolved_predicates)
        rest : List<&2, Nat> <- binding_free(tail, substitutions)
        return T.union(T.difference(T.union(free, predicate_free), variables), rest)

def label_bindings(labels: List<&2, Label>) -> List<&2, Binding>:
  match labels:
    case Nil{}:
      Nil{}
    case Label{identity, result} <> tail:
      Binding{"", result, Nil{}, Nil{}} <> label_bindings(tail)

def environment_bindings(context: Context) -> List<&2, Binding>:
  Context{globals, locals, labels, types, operations, subject, functions, ambient} = context
  List.append(&2, Binding, globals, List.append(&2, Binding, locals, label_bindings(labels)))

def annotation_bindings(types: List<&2, M.Ty>) -> List<&2, Binding>:
  match types:
    case Nil{}:
      Nil{}
    case ty <> rest:
      Binding{"", ty, Nil{}, Nil{}} <> annotation_bindings(rest)

def annotation_types(state: State) -> List<&2, M.Ty>:
  State{substitutions, next, annotations} = state
  Map.values(&2, M.Ty, annotations)

def clear_annotations(state: State) -> State:
  State{substitutions, next, annotations} = state
  State{substitutions, next, MTip{}}

# A local RHS annotation's source names belong to that binding. Preserve
# solved links and fresh indices, while retaining only annotations that were
# already fixed in the enclosing inference scope.
def restore_annotations(state: State, prior: State) -> State:
  State{substitutions, next, current} = state
  State{old_substitutions, old_next, annotations} = prior
  State{substitutions, next, annotations}

# Only source lets with their own annotation scope may discard RHS annotation
# names. Synthetic lets for assignment, if-let, and loops use the enclosing
# scope, so their new annotation names must survive into the following body.
def local_annotation_state(value: M.Expr, state: State, prior: State) -> State:
  match value:
    case M.SourceExpr{offset, Some{annotation}, body}:
      restore_annotations(state, prior)
    case M.SourceExpr{offset, None{}, M.QualifiedExpr{qualified_offset, annotation, predicates, body}}:
      restore_annotations(state, prior)
    case other:
      state

# A scheme and every variable its generalization quantified, including the
# row variables the scheme closed.
type Generalization is Data:
  Generalization{binding: Binding, variables: List<&2, Nat>}

def generalization_binding(generalized: Generalization) -> Binding:
  Generalization{binding, variables} = generalized
  binding

def generalization_variables(generalized: Generalization) -> List<&2, Nat>:
  Generalization{binding, variables} = generalized
  variables

# If the solved type and every residual predicate are closed, no variable can
# be generalized. Computing free variables of the whole environment in this
# case used to revisit every earlier let binding for no change in the result.
# The open case still excludes globals, locals, labels, annotations, ambient
# rows and blocked predicate variables before applying the covariance rules.
def generalization_candidates(candidates: List<&2, Nat>, +resolved: M.Ty, +needs: List<&2, M.Predicate>, +predicate_free: List<&2, Nat>, +context: Context, +state: State, name: String, blocked: List<&2, Nat>) -> Result<&2, &2, M.Diagnostic, Generalization>:
  match candidates:
    case Nil{}:
      Done{Generalization{Binding{name, resolved, Nil{}, needs}, Nil{}}}
    case head <> tail:
      do Result<&2, &2, M.Diagnostic, Generalization>:
        excluded : List<&2, Nat> <- binding_free(List.append(&2, Binding, environment_bindings(context), annotation_bindings(annotation_types(state))), substitutions_of(state))
        +variables : List<&2, Nat> = T.difference(head <> tail, T.union(blocked, T.union(excluded, T.row_free(T.resolve_row(substitutions_of(state), context_row(context))))))
        +closed : M.Ty <- T.close_covariant(resolved, variables, predicate_free)
        remaining : List<&2, Nat> <- T.free(closed)
        return Generalization{Binding{name, closed, T.difference(variables, T.difference(variables, T.union(remaining, predicate_free))), needs}, variables}

def generalization_qualified_excluding(ty: M.Ty, predicates: List<&2, M.Predicate>, context: Context, +state: State, name: String, blocked: List<&2, Nat>) -> Result<&2, &2, M.Diagnostic, Generalization>:
  do Result<&2, &2, M.Diagnostic, Generalization>:
    +resolved : M.Ty <- T.resolve(substitutions_of(state), ty)
    resolved_needs : List<&2, M.Predicate> <- C.resolve_list(substitutions_of(state), predicates)
    +needs : List<&2, M.Predicate> = C.canonical_predicates(resolved_needs, Nil{})
    type_free : List<&2, Nat> <- T.free(resolved)
    +predicate_free : List<&2, Nat> <- C.free_list(needs)
    generalization_candidates(T.union(type_free, predicate_free), resolved, needs, predicate_free, context, state, name, blocked)

# Retained slow oracle for differential tests of the closed-type fast path.
def generalization_qualified_excluding_reference(ty: M.Ty, predicates: List<&2, M.Predicate>, +context: Context, +state: State, name: String, +blocked: List<&2, Nat>) -> Result<&2, &2, M.Diagnostic, Generalization>:
  do Result<&2, &2, M.Diagnostic, Generalization>:
    +resolved : M.Ty <- T.resolve(substitutions_of(state), ty)
    resolved_needs : List<&2, M.Predicate> <- C.resolve_list(substitutions_of(state), predicates)
    +needs : List<&2, M.Predicate> = C.canonical_predicates(resolved_needs, Nil{})
    type_free : List<&2, Nat> <- T.free(resolved)
    +predicate_free : List<&2, Nat> <- C.free_list(needs)
    excluded : List<&2, Nat> <- binding_free(List.append(&2, Binding, environment_bindings(context), annotation_bindings(annotation_types(state))), substitutions_of(state))
    +variables : List<&2, Nat> = T.difference(T.union(type_free, predicate_free), T.union(blocked, T.union(excluded, T.row_free(T.resolve_row(substitutions_of(state), context_row(context))))))
    +closed : M.Ty <- T.close_covariant(resolved, variables, predicate_free)
    remaining : List<&2, Nat> <- T.free(closed)
    return Generalization{Binding{name, closed, T.difference(variables, T.difference(variables, T.union(remaining, predicate_free))), needs}, variables}

def generalization_qualified(ty: M.Ty, predicates: List<&2, M.Predicate>, context: Context, state: State, name: String) -> Result<&2, &2, M.Diagnostic, Generalization>:
  generalization_qualified_excluding(ty, predicates, context, state, name, Nil{})

def generalization(ty: M.Ty, context: Context, state: State, name: String) -> Result<&2, &2, M.Diagnostic, Generalization>:
  generalization_qualified(ty, Nil{}, context, state, name)

def generalize(ty: M.Ty, +context: Context, +state: State, name: String) -> Result<&2, &2, M.Diagnostic, Binding>:
  do Result<&2, &2, M.Diagnostic, Binding>:
    generalized : Generalization <- generalization(ty, context, state, name)
    return generalization_binding(generalized)

def generalize_qualified(ty: M.Ty, predicates: List<&2, M.Predicate>, context: Context, state: State, name: String) -> Result<&2, &2, M.Diagnostic, Binding>:
  do Result<&2, &2, M.Diagnostic, Binding>:
    generalized : Generalization <- generalization_qualified(ty, predicates, context, state, name)
    return generalization_binding(generalized)

# The variables the deferred associated requirements of `coverage` mention,
# under the current substitution.
def invocation_free(invocation: Maybe<&2, M.EffectRow>, +substitutions: T.Substitutions) -> List<&2, Nat>:
  match invocation:
    case None{}:
      Nil{}
    case Some{row}:
      T.row_free(T.resolve_row(substitutions, row))

def need_invocation(invocation: Maybe<&2, M.EffectRow>, ambient: M.EffectRow) -> M.EffectRow:
  match invocation:
    case Some{row}:
      row
    case None{}:
      ambient

def associated_free(coverage: List<&2, Coverage>, +substitutions: T.Substitutions) -> Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
  match coverage:
    case Nil{}:
      Done{Nil{}}
    case AssociatedNeed{identity, dispatch, member, templates, left, right, result, invocation, ambient, subject} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
        resolved : List<&2, M.Ty> <- T.resolve_work(substitutions, U32.to_nat(65536), T.ManyTypes{[left, right, result]})
        free : List<&2, Nat> <- T.free(M.ProductTy{resolved})
        rest : List<&2, Nat> <- associated_free(tail, substitutions)
        return T.union(invocation_free(invocation, substitutions), T.union(T.row_free(T.resolve_row(substitutions, ambient)), T.union(free, rest)))
    case head <> tail:
      associated_free(tail, substitutions)

def generalized_witness(variables: List<&2, Nat>) -> List<&2, M.Ty>:
  match variables:
    case Nil{}:
      Nil{}
    case +variable <> tail:
      M.FunctionTy{M.VariableTy{variable}, M.UnitTy{}, R.variable_row(variable)} <> generalized_witness(tail)

def generalized_evidence(variables: List<&2, Nat>) -> List<&2, Coverage>:
  match variables:
    case Nil{}:
      Nil{}
    case head <> tail:
      [LetGeneralized{M.ProductTy{generalized_witness(head <> tail)}}]

def mentioned_generalized(+variables: List<&2, Nat>, mentioned: Result<&2, &2, M.Diagnostic, List<&2, Nat>>) -> Result<&2, &2, M.Diagnostic, List<&2, Coverage>>:
  do Result<&2, &2, M.Diagnostic, List<&2, Coverage>>:
    free : List<&2, Nat> <- mentioned
    return generalized_evidence(T.difference(variables, T.difference(variables, free)))

# Evidence for the variables a let generalized that its value's deferred
# associated requirements mention; a let that generalizes nothing records none.
def let_generalized(variables: List<&2, Nat>, coverage: List<&2, Coverage>, substitutions: T.Substitutions) -> Result<&2, &2, M.Diagnostic, List<&2, Coverage>>:
  match variables:
    case Nil{}:
      Done{Nil{}}
    case head <> tail:
      mentioned_generalized(head <> tail, associated_free(coverage, substitutions))

def annotation_variable(found: Maybe<&2, M.Ty>, key: String, state: State) -> Typing:
  match found:
    case Some{ty}:
      Typing{pure(ty), state}
    case None{}:
      State{substitutions, +next, annotations} = state
      Typing{pure(M.VariableTy{next}), State{substitutions, 1n+next, Index.set(M.Ty, annotations, key, M.VariableTy{next})}}

def annotation_instance(parameters: List<&2, M.Ty>, ty: M.Ty, +state: State) -> Result<&2, &2, M.Diagnostic, Typing>:
  match parameters:
    case Nil{}:
      Done{Typing{pure(ty), state}}
    case M.FreeTy{+scope, +name} <> rest:
      State{substitutions, next, annotations} = state
      +key = Nat.show(String.length(scope)) ++ ":" ++ scope ++ name
      +variable = {annotation_variable(Index.find(M.Ty, annotations, key), key, state) : Typing}
      do Result<&2, &2, M.Diagnostic, Typing>:
        types : List<&2, M.Ty> <- T.rewrite(65536n, T.OneType{ty}, T.ReplaceFree{scope, name, type_of(variable)})
        replaced : M.Ty <- T.first_type(types)
        annotation_instance(rest, replaced, state_of(variable))

    case other <> rest:
      Fail{M.Diagnostic{"internal_error", "annotation", "free annotation name traversal returned a concrete type"}}

type QualifiedAnnotation is Data:
  QualifiedAnnotation{ty: M.Ty, predicates: List<&2, M.Predicate>, state: State}

def qualified_type(value: QualifiedAnnotation) -> M.Ty:
  QualifiedAnnotation{ty, predicates, state} = value
  ty

def qualified_predicates(value: QualifiedAnnotation) -> List<&2, M.Predicate>:
  QualifiedAnnotation{ty, predicates, state} = value
  predicates

def qualified_state(value: QualifiedAnnotation) -> State:
  QualifiedAnnotation{ty, predicates, state} = value
  state

def qualified_inference(value: Inference, offset: Nat, declared_type: M.Ty, +declared: List<&2, M.Predicate>, subject: String) -> Inference:
  Inference{ty, coverage, exits, reflections, inferred, uses} = value
  Inference{declared_type, List.append(&2, Coverage, coverage, [QualifiedBoundary{offset, declared, subject}]), exits, reflections, C.canonical_predicates(declared, Nil{}), uses}

def source_variable_index(ty: M.Ty) -> Result<&2, &2, M.Diagnostic, Nat>:
  match ty:
    case M.VariableTy{index}:
      Done{index}
    case _:
      Fail{M.Diagnostic{"internal_error", "annotation", "source annotation name did not resolve to a variable"}}

def qualified_annotation_instance(parameters: List<&2, M.Ty>, ty: M.Ty, predicates: List<&2, M.Predicate>, +state: State) -> Result<&2, &2, M.Diagnostic, QualifiedAnnotation>:
  match parameters:
    case Nil{}:
      Done{QualifiedAnnotation{ty, predicates, state}}
    case M.FreeTy{+scope, +name} <> rest:
      State{substitutions, next, annotations} = state
      +key = Nat.show(String.length(scope)) ++ ":" ++ scope ++ name
      +variable = {annotation_variable(Index.find(M.Ty, annotations, key), key, state) : Typing}
      do Result<&2, &2, M.Diagnostic, QualifiedAnnotation>:
        types : List<&2, M.Ty> <- T.rewrite(65536n, T.OneType{ty}, T.ReplaceFree{scope, name, type_of(variable)})
        changed : M.Ty <- T.first_type(types)
        index : Nat <- source_variable_index(type_of(variable))
        needs : List<&2, M.Predicate> <- C.replace_source(predicates, scope, name, index)
        qualified_annotation_instance(rest, changed, needs, state_of(variable))
    case other <> rest:
      Fail{M.Diagnostic{"internal_error", "annotation", "free qualified name traversal returned a concrete type"}}

def validate_qualified_predicates(predicates: List<&2, M.Predicate>, +context: Context) -> Result<&2, &2, M.Diagnostic, Unit>:
  match predicates:
    case Nil{}:
      Done{Unit{}}
    case head <> tail:
      do Result<&2, &2, M.Diagnostic, Unit>:
        valid : Unit <- D.annotation(Some{C.shape_type(head)}, context_operations(context), context_types(context), context_subject(context))
        validate_qualified_predicates(tail, context)

def qualified_annotation(+annotation: M.Ty, +predicates: List<&2, M.Predicate>, state: State, +context: Context) -> Result<&2, &2, M.Diagnostic, QualifiedAnnotation>:
  do Result<&2, &2, M.Diagnostic, QualifiedAnnotation>:
    valid : Unit <- D.annotation(Some{annotation}, context_operations(context), context_types(context), context_subject(context))
    valid_needs : Unit <- validate_qualified_predicates(predicates, context)
    types : List<&2, M.Ty> <- T.annotation_names(65536n, T.OneType{annotation})
    names : List<&2, M.Ty> <- C.annotation_names(predicates)
    qualified_annotation_instance(List.append(&2, M.Ty, types, names), annotation, predicates, state)

def annotation(annotation: Maybe<&2, M.Ty>, ty: M.Ty, state: State, context: Context) -> Result<&2, &2, M.Diagnostic, State>:
  match annotation:
    case None{}:
      Done{state}
    case Some{+expected}:
      Context{globals, locals, labels, types, operations, +subject, functions, ambient} = context
      do Result<&2, &2, M.Diagnostic, State>:
        valid : Unit <- D.annotation(Some{expected}, operations, types, subject)
        parameters : List<&2, M.Ty> <- T.annotation_names(65536n, T.OneType{expected})
        +instantiated : Typing <- annotation_instance(parameters, expected, state)
        unify(type_of(instantiated), ty, state_of(instantiated), subject)

def operation_template(operations: List<&2, M.Operation>, +wanted: M.TypeId) -> Result<&2, &2, M.Diagnostic, M.Operation>:
  match operations:
    case Nil{}:
      Fail{M.Diagnostic{"unknown_effect", M.type_id_show(wanted), "no declaration defines this generic effect operation"}}
    case M.OperationTemplate{+identity, parameters, parameter, result} <> tail:
      Bool.pick(Result<&2, &2, M.Diagnostic, M.Operation>, M.type_id_equal(identity, wanted), Done{M.OperationTemplate{identity, parameters, parameter, result}}, operation_template(tail, wanted))
    case head <> tail:
      operation_template(tail, wanted)

def fresh_operation_arguments(count: Nat, +next: Nat) -> List<&2, M.Ty>:
  match count:
    case 0n:
      Nil{}
    case 1n+rest:
      M.VariableTy{next} <> fresh_operation_arguments(rest, 1n+next)

type OperationArguments is Data:
  OperationArguments{types: List<&2, M.Ty>, state: State}

def instantiate_operation_arguments(arguments: List<&2, M.Ty>, state: State, +context: Context, reversed: List<&2, M.Ty>) -> Result<&2, &2, M.Diagnostic, OperationArguments>:
  match arguments:
    case Nil{}:
      Done{OperationArguments{List.reverse(&2, M.Ty, reversed), state}}
    case +argument <> tail:
      do Result<&2, &2, M.Diagnostic, OperationArguments>:
        valid : Unit <- D.annotation(Some{argument}, context_operations(context), context_types(context), context_subject(context))
        parameters : List<&2, M.Ty> <- T.annotation_names(65536n, T.OneType{argument})
        +instantiated : Typing <- annotation_instance(parameters, argument, state)
        instantiate_operation_arguments(tail, state_of(instantiated), context, type_of(instantiated) <> reversed)

def operation_arguments(arguments: List<&2, M.Ty>, +count: Nat, +state: State, context: Context) -> Result<&2, &2, M.Diagnostic, OperationArguments>:
  match arguments:
    case Nil{}:
      +start = next_of(state)
      Done{OperationArguments{fresh_operation_arguments(count, start), with_next(state, Nat.add(start, count))}}
    case arguments:
      instantiate_operation_arguments(arguments, state, context, Nil{})

def generic_operation_signature(identity: Nat, +template: M.TypeId, parameter: M.Ty, result: M.Ty, arguments: OperationArguments, context: Context) -> Result<&2, &2, M.Diagnostic, Typing>:
  OperationArguments{+types, +state} = arguments
  do Result<&2, &2, M.Diagnostic, Typing>:
    p : M.Ty <- T.parameters(types, 0n, parameter)
    r : M.Ty <- T.parameters(types, 0n, result)
    +signature : M.Ty = M.FunctionTy{p, r, R.variable_row(next_of(state))}
    return Typing{Inference{signature, [OperationNeed{identity, template, types, signature, context_subject(context)}], Nil{}, Nil{}, [M.OperationPredicate{template, types, signature}], Nil{}}, with_next(state, 1n+next_of(state))}

def associated_predicate(dispatch: M.Dispatch, member: String, templates: List<&2, M.TypeId>, left: M.Ty, right: M.Ty, result: M.Ty, ambient: M.EffectRow) -> M.Predicate:
  match dispatch:
    case M.BinaryDispatch{}:
      M.AssociatedPredicate{member, templates, left, right, result, ambient}
    case M.MemberDispatch{}:
      M.ReceiverPredicate{member, templates, left, right, result, ambient}
    case M.FieldUpdateDispatch{}:
      M.UpdatePredicate{member, left, right, result, ambient}

def generic_operation(identity: Nat, +template: M.TypeId, declared: M.Operation, arguments: List<&2, M.Ty>, state: State, +context: Context) -> Result<&2, &2, M.Diagnostic, Typing>:
  match declared:
    case M.OperationTemplate{declared_identity, parameters, parameter, result}:
      do Result<&2, &2, M.Diagnostic, Typing>:
        instantiated : OperationArguments <- operation_arguments(arguments, parameters, state, context)
        generic_operation_signature(identity, template, parameter, result, instantiated, context)
    case _:
      Fail{M.Diagnostic{"internal_error", M.type_id_show(template), "generic operation requires a template declaration"}}

def predicate_arity(valid: Bool, subject: String) -> Result<&2, &2, M.Diagnostic, Unit>:
  Bool.pick(Result<&2, &2, M.Diagnostic, Unit>, valid, Done{Unit{}}, Fail{M.Diagnostic{"effect_arity", subject, "generic operation predicate has the wrong type argument count"}})

def constrain_declared_operation(declared: M.Operation, +arguments: List<&2, M.Ty>, function_type: M.Ty, +state: State, +context: Context) -> Result<&2, &2, M.Diagnostic, State>:
  match declared:
    case M.OperationTemplate{identity, parameters, parameter, result}:
      do Result<&2, &2, M.Diagnostic, State>:
        arity : Unit <- predicate_arity(Nat.is_eq(parameters, List.length(&2, M.Ty, arguments)), context_subject(context))
        p : M.Ty <- T.parameters(arguments, 0n, parameter)
        r : M.Ty <- T.parameters(arguments, 0n, result)
        unify(function_type, M.FunctionTy{p, r, R.variable_row(next_of(state))}, with_next(state, 1n+next_of(state)), context_subject(context))
    case _:
      Fail{M.Diagnostic{"internal_error", context_subject(context), "operation predicate expected a generic template"}}

def constrain_predicate(predicate: M.Predicate, +state: State, +context: Context) -> Result<&2, &2, M.Diagnostic, State>:
  match predicate:
    case M.OperationPredicate{template, arguments, function_type}:
      do Result<&2, &2, M.Diagnostic, State>:
        declared : M.Operation <- operation_template(context_operations(context), template)
        constrain_declared_operation(declared, arguments, function_type, state, context)
    case other:
      Done{state}

def constrain_predicates(predicates: List<&2, M.Predicate>, state: State, +context: Context) -> Result<&2, &2, M.Diagnostic, State>:
  match predicates:
    case Nil{}:
      Done{state}
    case head <> tail:
      do Result<&2, &2, M.Diagnostic, State>:
        next : State <- constrain_predicate(head, state, context)
        constrain_predicates(tail, next, context)

def unify_entail_shapes(shapes: C.EntailShapes, state: State, subject: String) -> Result<&2, &2, M.Diagnostic, State>:
  C.EntailShapes{left, right} = shapes
  unify(left, right, state, subject)

def candidate_attempt(compatible: Bool, wanted: M.Predicate, candidate: M.Predicate, state: State, subject: String) -> Result<&2, &2, M.Diagnostic, State>:
  match compatible:
    case False{}:
      Fail{M.Diagnostic{"different_predicate", subject, "predicate member or kind differs"}}
    case True{}:
      unify_entail_shapes(C.entail_shapes(wanted, candidate), state, subject)

def entail_work(declared: List<&2, M.Predicate>, attempt: Result<&2, &2, M.Diagnostic, State>, +wanted: M.Predicate, +state: State, +subject: String) -> Result<&2, &2, M.Diagnostic, State>:
  match declared attempt:
    case _ Done{next}:
      Done{next}
    case Nil{} Fail{diagnostic}:
      Fail{M.Diagnostic{"missing_predicate", subject, "inferred requirement is absent from the explicit where clause"}}
    case +candidate <> tail Fail{diagnostic}:
      entail_work(tail, candidate_attempt(C.same_head(wanted, candidate), wanted, candidate, state, subject), wanted, state, subject)

def entail_one(wanted: M.Predicate, declared: List<&2, M.Predicate>, state: State, +subject: String) -> Result<&2, &2, M.Diagnostic, State>:
  entail_work(declared, Fail{M.Diagnostic{"missing_predicate", subject, "explicit where clause has no matching requirement"}}, wanted, state, subject)

def entailment_value_free(predicate: M.Predicate, checked: List<&2, Nat>) -> Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
  match predicate:
    case M.AssociatedPredicate{member, templates, left, right, result, invocation}:
      T.free(M.ProductTy{[left, right, result]})
    case M.ReceiverPredicate{member, templates, receiver, argument, result, invocation}:
      T.free(M.ProductTy{[receiver, argument, result]})
    case M.UpdatePredicate{member, receiver, assigned, result, invocation}:
      T.free(M.ProductTy{[receiver, assigned, result]})
    case other:
      Done{checked}

def entailment_free(+predicate: M.Predicate) -> Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
  do Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
    checked : List<&2, Nat> <- C.free(predicate)
    entailment_value_free(predicate, checked)

def require_open_entailment(closed: Bool, required: M.Predicate, declared: List<&2, M.Predicate>, state: State, subject: String) -> Result<&2, &2, M.Diagnostic, State>:
  match closed:
    case True{}:
      Done{state}
    case False{}:
      entail_one(required, declared, state, subject)

def coverage_subject(+required: M.Predicate, coverage: List<&2, Coverage>, +fallback: String) -> String:
  match coverage:
    case Nil{}:
      fallback
    case AssociatedNeed{identity, dispatch, member, templates, left, right, result, invocation, ambient, subject} <> tail:
      Bool.pick(String, C.same_head(required, associated_predicate(dispatch, member, templates, left, right, result, need_invocation(invocation, ambient))), subject, coverage_subject(required, tail, fallback))
    case OperationNeed{identity, template, arguments, function_type, subject} <> tail:
      Bool.pick(String, C.same_head(required, M.OperationPredicate{template, arguments, function_type}), subject, coverage_subject(required, tail, fallback))
    case head <> tail:
      coverage_subject(required, tail, fallback)

def use_subject(+required: M.Predicate, plans: List<&2, C.UsePlan>, +fallback: String) -> String:
  match plans:
    case Nil{}:
      fallback
    case C.UsePlan{site, subject, ty, predicates} <> tail:
      Bool.pick(String, C.contains_head(predicates, required), subject, use_subject(required, tail, fallback))

def entail_all(inferred: List<&2, M.Predicate>, +coverage: List<&2, Coverage>, +uses: List<&2, C.UsePlan>, +declared: List<&2, M.Predicate>, +state: State, +subject: String) -> Result<&2, &2, M.Diagnostic, State>:
  match inferred:
    case Nil{}:
      Done{state}
    case head <> tail:
      do Result<&2, &2, M.Diagnostic, State>:
        +resolved : M.Predicate <- C.resolve(substitutions_of(state), head)
        free : List<&2, Nat> <- entailment_free(resolved)
        +origin : String = coverage_subject(resolved, coverage, use_subject(resolved, uses, subject))
        next : State <- require_open_entailment(List.is_empty(&2, Nat, free), resolved, declared, state, origin)
        entail_all(tail, coverage, uses, declared, next, subject)

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
  PatternTyping{bindings, state, constraints} = typing
  state

def pattern_bindings(typing: PatternTyping) -> List<&2, Binding>:
  PatternTyping{bindings, state, constraints} = typing
  bindings

def pattern_constraints(typing: PatternTyping) -> List<&2, Coverage>:
  PatternTyping{bindings, state, constraints} = typing
  constraints

def with_pattern_constraints(inference: Inference, constraints: List<&2, Coverage>) -> Inference:
  Inference{ty, coverage, exits, reflections, predicates, uses} = inference
  Inference{ty, List.append(&2, Coverage, constraints, coverage), exits, reflections, predicates, uses}

def require_new_binding(found: Maybe<&2, Binding>, subject: String, name: String) -> Result<&2, &2, M.Diagnostic, Unit>:
  match found:
    case None{}:
      Done{Unit{}}
    case Some{binding}:
      Fail{M.Diagnostic{"duplicate_pattern_binding", subject, "pattern row binds " ++ name ++ " more than once"}}

type PatternWork is Data:
  PatternValue{pattern: M.Pattern, expected: M.Ty}
  PatternFields{patterns: List<&2, M.Pattern>, expected: List<&2, M.Ty>}

def pattern_requirements_closed(predicates: List<&2, M.Predicate>, +state: State, +subject: String) -> Result<&2, &2, M.Diagnostic, Unit>:
  match predicates:
    case Nil{}:
      Done{Unit{}}
    case head <> tail:
      do Result<&2, &2, M.Diagnostic, Unit>:
        resolved : M.Predicate <- C.resolve(substitutions_of(state), head)
        free : List<&2, Nat> <- C.free(resolved)
        closed : Unit <- Bool.pick(Result<&2, &2, M.Diagnostic, Unit>, List.is_empty(&2, Nat, free), Done{Unit{}}, Fail{M.Diagnostic{"qualified_pattern", subject, "an open qualified value cannot be used as a pattern until its evidence is selected"}})
        pattern_requirements_closed(tail, state, subject)

def pattern_reference_ready_for(predicates: List<&2, M.Predicate>, +value: Typing, subject: String) -> Result<&2, &2, M.Diagnostic, Typing>:
  do Result<&2, &2, M.Diagnostic, Typing>:
    ready : Unit <- pattern_requirements_closed(predicates, state_of(value), subject)
    return value

def pattern_reference_ready(+value: Typing, subject: String) -> Result<&2, &2, M.Diagnostic, Typing>:
  pattern_reference_ready_for(inference_predicates(inference_of(value)), value, subject)

def value_reference_type(reference: M.ValueReference, +context: Context, state: State) -> Result<&2, &2, M.Diagnostic, Typing>:
  match reference:
    case M.LocalReference{+name}:
      do Result<&2, &2, M.Diagnostic, Typing>:
        value : Typing <- instantiate_binding(lookup_local(context, name), state, name, context_subject(context))
        pattern_reference_ready(value, context_subject(context))
    case M.ConstantReference{+name}:
      do Result<&2, &2, M.Diagnostic, Typing>:
        valid : Unit <- valid_global_kind(context, name, False{})
        value : Typing <- instantiate_binding(lookup_global(context, name), state, name, context_subject(context))
        pattern_reference_ready(value, context_subject(context))

def infer_pattern_work(fuel: Nat, pending: List<&2, PatternWork>, +context: Context, +state: State, +bindings: List<&2, Binding>, +constraints: List<&2, Coverage>) -> Result<&2, &2, M.Diagnostic, PatternTyping>:
  match fuel pending:
    case _ Nil{}:
      Done{PatternTyping{bindings, state, constraints}}
    case 0n _:
      Fail{M.Diagnostic{"pattern_complexity", context_subject(context), "pattern typing exceeds compiler traversal limit"}}
    case 1n+rest PatternValue{M.WildcardPattern{}, expected} <> tail:
      infer_pattern_work(rest, tail, context, state, bindings, constraints)
    case 1n+rest PatternValue{M.BindingPattern{+name}, expected} <> tail:
      do Result<&2, &2, M.Diagnostic, PatternTyping>:
        fresh : Unit <- require_new_binding(lookup_binding(bindings, name), context_subject(context), name)
        infer_pattern_work(rest, tail, context, state, Binding{name, expected, Nil{}, Nil{}} <> bindings, constraints)
    case 1n+rest PatternValue{M.ValuePattern{+reference}, +expected} <> tail:
      do Result<&2, &2, M.Diagnostic, PatternTyping>:
        +value : Typing <- value_reference_type(reference, context, state)
        next : State <- unify(expected, type_of(value), state_of(value), context_subject(context))
        infer_pattern_work(rest, tail, context, next, bindings, ValuePatternType{expected, context_subject(context)} <> constraints)
    case 1n+rest PatternValue{M.UnitPattern{}, expected} <> tail:
      do Result<&2, &2, M.Diagnostic, PatternTyping>:
        next : State <- unify(expected, M.UnitTy{}, state, context_subject(context))
        infer_pattern_work(rest, tail, context, next, bindings, constraints)
    case 1n+rest PatternValue{M.U32Pattern{value}, expected} <> tail:
      do Result<&2, &2, M.Diagnostic, PatternTyping>:
        next : State <- unify(expected, M.U32Ty{}, state, context_subject(context))
        infer_pattern_work(rest, tail, context, next, bindings, constraints)
    case 1n+rest PatternValue{M.BoolPattern{value}, expected} <> tail:
      do Result<&2, &2, M.Diagnostic, PatternTyping>:
        next : State <- unify(expected, M.BoolTy{}, state, context_subject(context))
        infer_pattern_work(rest, tail, context, next, bindings, constraints)
    case 1n+rest PatternValue{M.ConstructorPattern{name, None{}}, expected} <> tail:
      do Result<&2, &2, M.Diagnostic, PatternTyping>:
        +ctor : D.ConstructorType <- constructor_instance(name, context, state)
        arity : Unit <- no_payload(constructor_payload(ctor), context_subject(context))
        next : State <- unify(expected, constructor_result(ctor), constructor_state(ctor, state), context_subject(context))
        infer_pattern_work(rest, tail, context, next, bindings, constraints)
    case 1n+rest PatternValue{M.ConstructorPattern{name, Some{payload}}, expected} <> tail:
      do Result<&2, &2, M.Diagnostic, PatternTyping>:
        +ctor : D.ConstructorType <- constructor_instance(name, context, state)
        ty : M.Ty <- payload_type(constructor_payload(ctor), context_subject(context))
        next : State <- unify(expected, constructor_result(ctor), constructor_state(ctor, state), context_subject(context))
        infer_pattern_work(rest, PatternValue{payload, ty} <> tail, context, next, bindings, constraints)
    case 1n+rest PatternValue{M.ProductPattern{+elements}, expected} <> tail:
      +count = List.length(&2, M.Pattern, elements)
      +fields = D.fresh_arguments(count, next_of(state))
      do Result<&2, &2, M.Diagnostic, PatternTyping>:
        arity : Unit <- D.require_product_arity(count, context_subject(context))
        next : State <- unify(expected, M.ProductTy{fields}, with_next(state, Nat.add(next_of(state), count)), context_subject(context))
        infer_pattern_work(rest, PatternFields{elements, fields} <> tail, context, next, bindings, constraints)
    case 1n+rest PatternFields{Nil{}, Nil{}} <> tail:
      infer_pattern_work(rest, tail, context, state, bindings, constraints)
    case 1n+rest PatternFields{pattern <> following, ty <> remaining} <> tail:
      infer_pattern_work(rest, PatternValue{pattern, ty} <> PatternFields{following, remaining} <> tail, context, state, bindings, constraints)
    case 1n+rest PatternFields{patterns, expected} <> tail:
      Fail{M.Diagnostic{"internal_error", context_subject(context), "product pattern fields lost their inferred types"}}

def infer_pattern(value: M.Pattern, expected: M.Ty, context: Context, state: State) -> Result<&2, &2, M.Diagnostic, PatternTyping>:
  infer_pattern_work(U32.to_nat(65536), [PatternValue{value, expected}], context, state, Nil{}, Nil{})

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
    case Binding{+name, ty, variables, predicates} <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, Binding>>:
        fresh : Unit <- require_new_binding(lookup_binding(bindings, name), subject, name)
        merge_pattern_bindings(tail, Binding{name, ty, variables, predicates} <> bindings, subject)

def infer_patterns(patterns: List<&2, M.Pattern>, expected: List<&2, M.Ty>, +context: Context, state: State, bindings: List<&2, Binding>, constraints: List<&2, Coverage>) -> Result<&2, &2, M.Diagnostic, PatternTyping>:
  match patterns expected:
    case Nil{} Nil{}:
      Done{PatternTyping{bindings, state, constraints}}
    case pattern <> tail ty <> remaining:
      do Result<&2, &2, M.Diagnostic, PatternTyping>:
        +first : PatternTyping <- infer_pattern(pattern, ty, context, state)
        merged : List<&2, Binding> <- merge_pattern_bindings(pattern_bindings(first), bindings, context_subject(context))
        infer_patterns(tail, remaining, context, pattern_state(first), merged, List.append(&2, Coverage, pattern_constraints(first), constraints))
    case _ _:
      Fail{M.Diagnostic{"match_arity", context_subject(context), "every pattern row must match the scrutinee count"}}

def operation_type(declaration: M.Operation, next: Nat) -> M.Ty:
  match declaration:
    case M.Operation{identity, parameter, result}:
      M.FunctionTy{parameter, result, R.singleton(identity, M.RowVariable{next})}
    case _:
      M.NeverTy{}

def operation_parameter(declaration: M.Operation) -> M.Ty:
  match declaration:
    case M.Operation{identity, parameter, result}:
      parameter
    case _:
      M.NeverTy{}

def operation_result(declaration: M.Operation) -> M.Ty:
  match declaration:
    case M.Operation{identity, parameter, result}:
      result
    case _:
      M.NeverTy{}

type Provider is Data:
  Provider{identities: List<&2, M.TypeId>, effects: M.EffectRow, state: Maybe<&2, M.Ty>}

def require_provider(ty: M.Ty, subject: String) -> Result<&2, &2, M.Diagnostic, Provider>:
  match ty:
    case M.ProviderTy{identity, effects}:
      Done{Provider{[identity], effects, None{}}}
    case M.StateProviderTy{read, write, state}:
      Done{Provider{[read, write], M.empty_row(), Some{state}}}
    case other:
      Fail{M.Diagnostic{"invalid_provider", subject, "do requires a provider with a known nominal operation, got " ++ M.type_show(other)}}

def prepare_provider(provider: Provider, +context: Context, state: State) -> Result<&2, &2, M.Diagnostic, State>:
  match provider:
    case Provider{identities, effects, None{}}:
      unify_rows(effects, context_row(context), state, context_subject(context))
    case Provider{identities, effects, Some{ty}}:
      Done{state}

def handled_context(+context: Context, provider: Provider) -> Context:
  Provider{identities, effects, state} = provider
  with_row(context, R.prepend(identities, context_row(context)))

def handled_result(provider: Provider, result: M.Ty) -> M.Ty:
  match provider:
    case Provider{identities, effects, None{}}:
      result
    case Provider{identities, effects, Some{state}}:
      M.ProductTy{[state, result]}

def state_operations_distinct(read: M.TypeId, write: M.TypeId, subject: String) -> Result<&2, &2, M.Diagnostic, Unit>:
  Bool.pick(Result<&2, &2, M.Diagnostic, Unit>, M.type_id_equal(read, write), Fail{M.Diagnostic{"invalid_state_provider", subject, "state read and write must be distinct operations"}}, Done{Unit{}})

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

# Deferred results retain their relationships to operation and operand types.
# Generalizing a temporary result would sever those relationships before selection.
def deferred_bindings(constraints: List<&2, Coverage>) -> List<&2, Binding>:
  match constraints:
    case Nil{}:
      Nil{}
    case OperationNeed{identity, template, arguments, function_type, subject} <> tail:
      Binding{"$operation", M.ProductTy{function_type <> arguments}, Nil{}, Nil{}} <> deferred_bindings(tail)
    case AssociatedNeed{identity, dispatch, member, templates, left, right, result, invocation, ambient, subject} <> tail:
      Binding{"$associated", M.ProductTy{[left, right, result]}, Nil{}, Nil{}} <> deferred_bindings(tail)
    case head <> tail:
      deferred_bindings(tail)

def let_context(inference: Inference, context: Context) -> Context:
  match inference:
    case Inference{M.FunctionTy{parameter, result, row}, coverage, exits, reflections, predicates, uses}:
      context
    case Inference{ty, coverage, exits, reflections, predicates, uses}:
      extend(context, deferred_bindings(coverage))

# These are the values Mono can clone per concrete use without evaluating a
# computed RHS again. Keep this list aligned with Mono.template_value.
def template_value(fuel: Nat, expression: M.Expr) -> Bool:
  match fuel expression:
    case 0n _:
      False{}
    case 1n+rest M.SourceExpr{offset, annotation, value}:
      template_value(rest, value)
    case 1n+rest M.QualifiedExpr{offset, annotation, predicates, value}:
      template_value(rest, value)
    case 1n+rest M.InstantiationExpr{site, value}:
      template_value(rest, value)
    case _ M.FunctionExpr{name}:
      True{}
    case _ M.ConstantExpr{name}:
      True{}
    case _ M.ConstructorRefExpr{constructor}:
      True{}
    case _ M.GenericOperationExpr{identity, template, arguments}:
      True{}
    case _ M.LambdaExpr{identity, parameter, p, r, body}:
      True{}
    case _ _:
      False{}

def computed_predicate_variables(template: Bool, predicates: List<&2, M.Predicate>, state: State) -> Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
  match template:
    case True{}:
      Done{Nil{}}
    case False{}:
      do Result<&2, &2, M.Diagnostic, List<&2, Nat>>:
        resolved : List<&2, M.Predicate> <- C.resolve_list(substitutions_of(state), predicates)
        C.free_list(resolved)

def tag_coverage(needs: List<&2, Coverage>, +subject: String) -> List<&2, Coverage>:
  match needs:
    case Nil{}:
      Nil{}
    case OperationNeed{identity, template, arguments, function_type, old_subject} <> tail:
      OperationNeed{identity, template, arguments, function_type, subject} <> tag_coverage(tail, subject)
    case AssociatedNeed{identity, dispatch, member, templates, left, right, result, invocation, ambient, old_subject} <> tail:
      AssociatedNeed{identity, dispatch, member, templates, left, right, result, invocation, ambient, subject} <> tag_coverage(tail, subject)
    case QualifiedNeed{site, predicate, old_subject} <> tail:
      QualifiedNeed{site, predicate, subject} <> tag_coverage(tail, subject)
    case QualifiedBoundary{offset, declared, old_subject} <> tail:
      QualifiedBoundary{offset, declared, subject} <> tag_coverage(tail, subject)
    case ValuePatternType{inferred_type, old_subject} <> tail:
      ValuePatternType{inferred_type, subject} <> tag_coverage(tail, subject)
    case Coverage{inferred_types, patterns, old_subject} <> tail:
      Coverage{inferred_types, patterns, subject} <> tag_coverage(tail, subject)
    case head <> tail:
      head <> tag_coverage(tail, subject)

def tag_uses(plans: List<&2, C.UsePlan>, +subject: String) -> List<&2, C.UsePlan>:
  match plans:
    case Nil{}:
      Nil{}
    case C.UsePlan{site, old_subject, ty, predicates} <> tail:
      C.UsePlan{site, subject, ty, predicates} <> tag_uses(tail, subject)

def tag_reflections(reflections: List<&2, Reflection>, +subject: String) -> List<&2, Reflection>:
  match reflections:
    case Nil{}:
      Nil{}
    case Reflection{callee, old_subject, ty, predicates} <> tail:
      Reflection{callee, subject, ty, predicates} <> tag_reflections(tail, subject)

def tag_typing(result: Result<&2, &2, M.Diagnostic, Typing>, offset: Nat) -> Result<&2, &2, M.Diagnostic, Typing>:
  match result:
    case Done{Typing{Inference{ty, coverage, exits, reflections, predicates, uses}, state}}:
      +subject = "offset:" ++ Nat.show(offset)
      Done{Typing{Inference{ty, tag_coverage(coverage, subject), exits, tag_reflections(reflections, subject), predicates, tag_uses(uses, subject)}, state}}
    case Fail{M.Diagnostic{code, subject, message}}:
      Fail{M.Diagnostic{code, "offset:" ++ Nat.show(offset), message}}

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
    case 1n+rest Expression{M.ForExpr{index, start, end, carried, initial, body}}:
      do Result<&2, &2, M.Diagnostic, Typing>:
        +a : Typing <- expr_work(rest, Expression{start}, context, state)
        s1 : State <- unify(type_of(a), M.U32Ty{}, state_of(a), context_subject(context))
        +b : Typing <- expr_work(rest, Expression{end}, context, s1)
        s2 : State <- unify(type_of(b), M.U32Ty{}, state_of(b), context_subject(context))
        +v : Typing <- expr_work(rest, Expression{initial}, context, s2)
        +loop : Typing <- expr_work(rest, Expression{body}, extend(context, [Binding{index, M.U32Ty{}, Nil{}, Nil{}}, Binding{carried, type_of(v), Nil{}, Nil{}}]), state_of(v))
        next : State <- unify(type_of(loop), type_of(v), state_of(loop), context_subject(context))
        +result : M.Ty = flow(type_of(a), flow(type_of(b), type_of(v)))
        return Typing{sequence(inference_of(a), sequence(inference_of(b), sequence(inference_of(v), inference_of(loop), result), result), result), next}
    case 1n+rest Expression{M.ForeverExpr{carried, initial, body}}:
      do Result<&2, &2, M.Diagnostic, Typing>:
        +v : Typing <- expr_work(rest, Expression{initial}, context, state)
        +loop : Typing <- expr_work(rest, Expression{body}, extend(context, [Binding{carried, type_of(v), Nil{}, Nil{}}]), state_of(v))
        next : State <- unify(type_of(loop), type_of(v), state_of(loop), context_subject(context))
        +result : M.Ty = M.NeverTy{}
        return Typing{sequence(inference_of(v), inference_of(loop), result), next}
    case 1n+rest Expression{M.ArrayGenerateExpr{count, generator}}:
      do Result<&2, &2, M.Diagnostic, Typing>:
        +c : Typing <- expr_work(rest, Expression{count}, context, state)
        +g : Typing <- expr_work(rest, Expression{generator}, context, state_of(c))
        +element : M.Ty = M.VariableTy{next_of(state_of(g))}
        s1 : State <- unify(type_of(c), M.U32Ty{}, with_next(state_of(g), 1n+next_of(state_of(g))), context_subject(context))
        next : State <- unify(type_of(g), M.FunctionTy{M.U32Ty{}, element, M.EffectRow{Nil{}, M.ClosedRow{}}}, s1, context_subject(context))
        +result : M.Ty = flow(type_of(c), flow(type_of(g), M.ArrayTy{element}))
        return Typing{sequence(inference_of(c), inference_of(g), result), next}
    case 1n+rest Expression{M.ArrayFillExpr{count, value}}:
      do Result<&2, &2, M.Diagnostic, Typing>:
        +c : Typing <- expr_work(rest, Expression{count}, context, state)
        +v : Typing <- expr_work(rest, Expression{value}, context, state_of(c))
        next : State <- unify(type_of(c), M.U32Ty{}, state_of(v), context_subject(context))
        +result : M.Ty = flow(type_of(c), flow(type_of(v), M.ArrayTy{type_of(v)}))
        return Typing{sequence(inference_of(c), inference_of(v), result), next}
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
    case 1n+rest Expression{M.MemoExpr{computation}}:
      do Result<&2, &2, M.Diagnostic, Typing>:
        +value : Typing <- expr_work(rest, Expression{computation}, context, state)
        +result : M.Ty = M.VariableTy{next_of(state_of(value))}
        +latent : M.EffectRow = R.variable_row(1n+next_of(state_of(value)))
        next : State <- unify(type_of(value), M.FunctionTy{M.UnitTy{}, result, latent}, with_next(state_of(value), 2n+next_of(state_of(value))), context_subject(context))
        return Typing{join(inference_of(value), pure(M.UnitTy{}), M.demand_type(M.FunctionTy{M.UnitTy{}, result, latent})), next}
    case 1n+rest Expression{M.ForceExpr{value}}:
      do Result<&2, &2, M.Diagnostic, Typing>:
        +suspended : Typing <- expr_work(rest, Expression{value}, context, state)
        +result : M.Ty = M.VariableTy{next_of(state_of(suspended))}
        next : State <- unify(type_of(suspended), M.demand_type(M.FunctionTy{M.UnitTy{}, result, context_row(context)}), with_next(state_of(suspended), 1n+next_of(state_of(suspended))), context_subject(context))
        return Typing{join(inference_of(suspended), pure(M.UnitTy{}), flow(type_of(suspended), result)), next}
    case 1n+rest Expression{M.InstantiationExpr{+site, M.ApplyExpr{callee, +argument}}}:
      do Result<&2, &2, M.Diagnostic, Typing>:
        +fn : Typing <- expr_work(rest, Expression{callee}, context, state)
        resolved : M.Ty <- T.resolve(substitutions_of(state_of(fn)), type_of(fn))
        +lazy : Bool = M.demand_callee(resolved)
        +arg : Typing <- expr_work(rest, Expression{Bool.pick(M.Expr, lazy, M.suspend_argument(site, argument), argument)}, context, state_of(fn))
        +result : M.Ty = M.VariableTy{next_of(state_of(arg))}
        next : State <- unify(type_of(fn), M.FunctionTy{type_of(arg), result, context_row(context)}, with_next(state_of(arg), 1n+next_of(state_of(arg))), context_subject(context))
        joined : Inference = sequence(inference_of(fn), inference_of(arg), flow(type_of(fn), flow(type_of(arg), result)))
        return Typing{with_use(with_pattern_constraints(joined, Bool.pick(List<&2, Coverage>, lazy, [DemandCall{site}], Nil{})), site, context_subject(context)), next}
    case 1n+rest Expression{M.InstantiationExpr{+site, M.CallExpr{callee, argument}}}:
      expr_work(rest, Expression{M.InstantiationExpr{site, M.ApplyExpr{M.FunctionExpr{callee}, argument}}}, context, state)
    case 1n+rest Expression{M.ApplyExpr{callee, argument}}:
      do Result<&2, &2, M.Diagnostic, Typing>:
        +fn : Typing <- expr_work(rest, Expression{callee}, context, state)
        +arg : Typing <- expr_work(rest, Expression{argument}, context, state_of(fn))
        +result : M.Ty = M.VariableTy{next_of(state_of(arg))}
        next : State <- unify(type_of(fn), M.FunctionTy{type_of(arg), result, context_row(context)}, with_next(state_of(arg), 1n+next_of(state_of(arg))), context_subject(context))
        return Typing{sequence(inference_of(fn), inference_of(arg), flow(type_of(fn), flow(type_of(arg), result))), next}
    case 1n+rest Expression{M.TagExpr{+offset, callee, argument}}:
      +at = at_subject(context, "offset:" ++ Nat.show(offset))
      do Result<&2, &2, M.Diagnostic, Typing>:
        +fn : Typing <- tag_typing(expr_work(rest, Expression{callee}, at, state), offset)
        +arg : Typing <- expr_work(rest, Expression{argument}, context, state_of(fn))
        +result : M.Ty = M.VariableTy{next_of(state_of(arg))}
        next : State <- unify(type_of(fn), M.FunctionTy{type_of(arg), result, context_row(context)}, with_next(state_of(arg), 1n+next_of(state_of(arg))), context_subject(at))
        return Typing{sequence(inference_of(fn), inference_of(arg), flow(type_of(fn), flow(type_of(arg), result))), next}
    case 1n+rest Expression{M.CallExpr{+callee, argument}}:
      do Result<&2, &2, M.Diagnostic, Typing>:
        valid : Unit <- valid_global_kind(context, callee, True{})
        +fn : Typing <- instantiate_binding(lookup_global(context, callee), state, callee, context_subject(context))
        +arg : Typing <- expr_work(rest, Expression{argument}, context, state_of(fn))
        +result : M.Ty = M.VariableTy{next_of(state_of(arg))}
        next : State <- unify(type_of(fn), M.FunctionTy{type_of(arg), result, context_row(context)}, with_next(state_of(arg), 1n+next_of(state_of(arg))), context_subject(context))
        return Typing{join(inference_of(fn), inference_of(arg), flow(type_of(arg), result)), next}
    case 1n+rest Expression{M.AssociatedExpr{identity, +dispatch, +member, +templates, left, right}}:
      do Result<&2, &2, M.Diagnostic, Typing>:
        +l : Typing <- expr_work(rest, Expression{left}, context, state)
        +r : Typing <- expr_work(rest, Expression{right}, context, state_of(l))
        +result : M.Ty = M.VariableTy{next_of(state_of(r))}
        +joined : Inference = sequence(inference_of(l), inference_of(r), flow(type_of(l), flow(type_of(r), result)))
        ordinary : State <- associated_shape(M.name_equal(member, "@type.same"), TypedState.request(member), type_of(l), type_of(r), result, with_next(state_of(r), 1n+next_of(state_of(r))), context_subject(context))
        +shaped : State <- result_shape(String.starts_with(member, "@result."), type_of(r), result, ordinary, context_subject(context))
        +invocation : M.EffectRow = R.variable_row(next_of(shaped))
        +need : M.Predicate = associated_predicate(dispatch, member, templates, type_of(l), type_of(r), result, invocation)
        return Typing{with_predicate(with_pattern_constraints(joined, [AssociatedNeed{identity, dispatch, member, templates, type_of(l), type_of(r), result, Some{invocation}, context_row(context), context_subject(context)}]), need), with_next(shaped, 1n+next_of(shaped))}
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
    case 1n+rest Expression{M.LetExpr{+name, +value, body}}:
      +row = R.variable_row(next_of(state))
      do Result<&2, &2, M.Diagnostic, Typing>:
        +v : Typing <- expr_work(rest, Expression{value}, with_row(context, row), with_next(state, 1n+next_of(state)))
        pure_state : State <- require_pure(row, state_of(v), context_subject(context), "let_effect")
        +local_state : State = local_annotation_state(value, pure_state, state)
        blocked : List<&2, Nat> <- computed_predicate_variables(template_value(65536n, value), inference_predicates(inference_of(v)), local_state)
        +generalized : Generalization <- generalization_qualified_excluding(type_of(v), inference_predicates(inference_of(v)), let_context(inference_of(v), context), local_state, name, blocked)
        evidence : List<&2, Coverage> <- let_generalized(generalization_variables(generalized), inference_coverage(inference_of(v)), substitutions_of(local_state))
        +b : Typing <- expr_work(rest, Expression{body}, extend(context, [generalization_binding(generalized)]), local_state)
        return Typing{with_pattern_constraints(sequence(without_residual(inference_of(v)), inference_of(b), flow(type_of(v), type_of(b))), evidence), state_of(b)}
    case 1n+rest Expression{M.UseExpr{name, value, body}}:
      do Result<&2, &2, M.Diagnostic, Typing>:
        +v : Typing <- expr_work(rest, Expression{value}, context, state)
        +b : Typing <- expr_work(rest, Expression{body}, extend(context, [Binding{name, type_of(v), Nil{}, Nil{}}]), state_of(v))
        return Typing{sequence(inference_of(v), inference_of(b), flow(type_of(v), type_of(b))), state_of(b)}
    case 1n+rest Expression{M.InstantiationExpr{site, value}}:
      do Result<&2, &2, M.Diagnostic, Typing>:
        +v : Typing <- expr_work(rest, Expression{value}, context, state)
        return Typing{with_use(inference_of(v), site, context_subject(context)), state_of(v)}
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
        +bindings : PatternTyping <- infer_pattern(pat, type_of(v), context, restore_annotations(pure_state, state))
        +a : Typing <- expr_work(rest, Expression{alternative}, context, pattern_state(bindings))
        exit : Unit <- guard_exits(type_of(a), context_subject(context))
        +b : Typing <- expr_work(rest, Expression{body}, extend(context, pattern_bindings(bindings)), state_of(a))
        +result : M.Ty = flow(type_of(v), type_of(b))
        return Typing{with_pattern_constraints(sequence(inference_of(v), join(inference_of(a), inference_of(b), result), result), pattern_constraints(bindings)), state_of(b)}
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
    case 1n+rest Expression{M.RuntimeInitExpr{value}}:
      expr_work(rest, Expression{value}, context, state)
    case 1n+rest Expression{M.SourceExpr{+offset, ann, value}}:
      +at = at_subject(context, "offset:" ++ Nat.show(offset))
      do Result<&2, &2, M.Diagnostic, Typing>:
        +v : Typing <- expr_work(rest, Expression{value}, at, state)
        next : State <- annotation(ann, type_of(v), state_of(v), at)
        return Typing{inference_of(v), next}
    case 1n+rest Expression{M.QualifiedExpr{+offset, annotation_type, predicates, value}}:
      +at = at_subject(context, "offset:" ++ Nat.show(offset))
      do Result<&2, &2, M.Diagnostic, Typing>:
        +prepared : QualifiedAnnotation <- qualified_annotation(annotation_type, predicates, state, at)
        +declared_type : M.Ty = qualified_type(prepared)
        +declared : List<&2, M.Predicate> = qualified_predicates(prepared)
        annotated_state : State = qualified_state(prepared)
        shaped : State <- constrain_predicates(declared, annotated_state, at)
        +v : Typing <- expr_work(rest, Expression{value}, at, shaped)
        unified : State <- unify(type_of(v), declared_type, state_of(v), context_subject(at))
        +entailed : State <- entail_all(inference_predicates(inference_of(v)), inference_coverage(inference_of(v)), inference_uses(inference_of(v)), declared, unified, context_subject(at))
        # The declaration is checked against its closed row above. Each use
        # may then call that pure value within its own ambient effect row.
        +opened : T.Opened <- T.open_covariant(declared_type, next_of(entailed))
        return Typing{qualified_inference(inference_of(v), offset, T.opened_type(opened), declared, context_subject(at)), with_next(entailed, T.opened_next(opened))}
    case 1n+rest Expression{M.GenericOperationExpr{identity, +template, arguments}}:
      do Result<&2, &2, M.Diagnostic, Typing>:
        declared : M.Operation <- operation_template(context_operations(context), template)
        generic_operation(identity, template, declared, arguments, state, context)
    case 1n+rest Expression{M.OperationExpr{+identity}}:
      do Result<&2, &2, M.Diagnostic, Typing>:
        declared : M.Operation <- D.require_operation(D.operation(context_operations(context), identity), identity)
        return Typing{pure(operation_type(declared, next_of(state))), with_next(state, 1n+next_of(state))}
    case 1n+rest Expression{M.SpecializeOperationExpr{template, arguments, body}}:
      Fail{M.Diagnostic{"unspecialized_effect", "effect", "effect instance reached inference before specialization"}}
    case 1n+rest Expression{M.StateProviderExpr{+read, +write, initial}}:
      do Result<&2, &2, M.Diagnostic, Typing>:
        distinct : Unit <- state_operations_distinct(read, write, context_subject(context))
        +reader : M.Operation <- D.require_operation(D.operation(context_operations(context), read), read)
        +writer : M.Operation <- D.require_operation(D.operation(context_operations(context), write), write)
        +value : Typing <- expr_work(rest, Expression{initial}, context, state)
        s1 : State <- unify(operation_parameter(reader), M.UnitTy{}, state_of(value), context_subject(context))
        s2 : State <- unify(operation_result(writer), M.UnitTy{}, s1, context_subject(context))
        s3 : State <- unify(operation_result(reader), operation_parameter(writer), s2, context_subject(context))
        s4 : State <- unify(type_of(value), operation_result(reader), s3, context_subject(context))
        return Typing{join(inference_of(value), pure(M.UnitTy{}), flow(type_of(value), M.StateProviderTy{read, write, operation_result(reader)})), s4}
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
        prepared : State <- prepare_provider(supplied, context, state_of(p))
        +b : Typing <- expr_work(rest, Expression{body}, handled_context(context, supplied), prepared)
        return Typing{sequence(inference_of(p), inference_of(b), flow(type_of(p), handled_result(supplied, type_of(b)))), state_of(b)}
    case 1n+rest Expression{M.OperationDescriptorExpr{+identity}}:
      do Result<&2, &2, M.Diagnostic, Typing>:
        known : Unit <- D.valid_effect_label(context_operations(context), identity)
        return Typing{pure(M.EffectDescriptorTy{}), state}
    case 1n+rest Expression{M.FunctionEffectsExpr{+callee}}:
      do Result<&2, &2, M.Diagnostic, Typing>:
        known : Unit <- valid_global_kind(context, callee, True{})
        +selected : SelectedInstantiation <- instantiate_binding_selected(lookup_global(context, callee), state, callee, context_subject(context))
        +scheme : Typing = selected_typing(selected)
        # Reflection reads the checked signature row; it does not create or
        # invoke the qualified callable. Check rejects an open reflected row.
        return Typing{Inference{M.EffectSetTy{}, Nil{}, Nil{}, [Reflection{callee, context_subject(context), selected_exact(selected), inference_predicates(inference_of(scheme))}], Nil{}, Nil{}}, state_of(scheme)}
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
        +bindings : PatternTyping <- infer_patterns(patterns, scrutinees, context, state, Nil{}, Nil{})
        +b : Typing <- expr_work(rest, Expression{body}, extend(context, pattern_bindings(bindings)), pattern_state(bindings))
        +t : Typing <- expr_work(rest, MatchArms{tail, scrutinees}, context, state_of(b))
        next : State <- unify(type_of(b), type_of(t), state_of(t), context_subject(context))
        return Typing{with_pattern_constraints(join(inference_of(b), inference_of(t), branch_type(type_of(b), type_of(t))), pattern_constraints(bindings)), next}


def expr(expression: M.Expr, context: Context, state: State) -> Result<&2, &2, M.Diagnostic, Typing>:
  expr_work(Nat.mul(256n, 256n), Expression{expression}, context, state)
