import Base
import ./model.bend as M
import ./constraints.bend as C
import ./types.bend as T
import ./effect_rows.bend as Rows
import ./state_specialize.bend as State
import ./core_compare.bend as Compare

# A closed synthetic State.run body may expose a rank-one result type and a
# residual effect row. This module certifies that particular selected evidence;
# it does not change substitutions or decide which owner generalized the IDs.

def free_within(found: Result<&2, &2, M.Diagnostic, List<&2, Nat>>, bound: List<&2, Nat>) -> Bool:
  match found:
    case Done{free}:
      List.is_empty(&2, Nat, T.difference(free, bound))
    case Fail{diagnostic}:
      False{}

def admissible_tail(tail: M.RowTail, bound: List<&2, Nat>) -> Bool:
  match tail:
    case M.ClosedRow{}:
      True{}
    case M.RowVariable{index}:
      T.contains(bound, index)
    case _:
      False{}

# T.free intentionally counts only flexible variables. For a universal
# certificate, a source name or rigid parameter inside T must not escape just
# because it is absent from that free-variable list.
def admissible_result_type(+fuel: Nat, pending: List<&2, M.Ty>, +bound: List<&2, Nat>) -> Bool:
  match fuel pending:
    case 0n _:
      False{}
    case 1n+rest Nil{}:
      True{}
    case 1n+rest M.VariableTy{index} <> tail:
      Bool.and(T.contains(bound, index), admissible_result_type(rest, tail, bound))
    case 1n+rest M.ParameterTy{index} <> tail:
      False{}
    case 1n+rest M.FreeTy{scope, name} <> tail:
      False{}
    case 1n+rest M.FunctionTy{parameter, result, effects} <> tail:
      Bool.and(admissible_tail(Rows.row_tail(effects), bound), admissible_result_type(rest, parameter <> result <> tail, bound))
    case 1n+rest M.ProviderTy{identity, effects} <> tail:
      Bool.and(admissible_tail(Rows.row_tail(effects), bound), admissible_result_type(rest, tail, bound))
    case 1n+rest M.StateProviderTy{read, write, state} <> tail:
      admissible_result_type(rest, state <> tail, bound)
    case 1n+rest M.AppliedTy{identity, arguments} <> tail:
      admissible_result_type(rest, List.append(&2, M.Ty, arguments, tail), bound)
    case 1n+rest M.ProductTy{elements} <> tail:
      admissible_result_type(rest, List.append(&2, M.Ty, elements, tail), bound)
    case 1n+rest M.ArrayTy{element} <> tail:
      admissible_result_type(rest, element <> tail, bound)
    case 1n+rest M.UnitTy{} <> tail:
      admissible_result_type(rest, tail, bound)
    case 1n+rest M.U32Ty{} <> tail:
      admissible_result_type(rest, tail, bound)
    case 1n+rest M.BoolTy{} <> tail:
      admissible_result_type(rest, tail, bound)
    case 1n+rest M.NeverTy{} <> tail:
      admissible_result_type(rest, tail, bound)
    case 1n+rest M.F32Ty{} <> tail:
      admissible_result_type(rest, tail, bound)
    case 1n+rest M.EffectDescriptorTy{} <> tail:
      admissible_result_type(rest, tail, bound)
    case 1n+rest M.EffectSetTy{} <> tail:
      admissible_result_type(rest, tail, bound)
    case 1n+rest head <> tail:
      False{}

def same_ty(left: M.Ty, right: M.Ty) -> Bool:
  Compare.compare(65536n, [Compare.TyPair{left, right}], True{})

def same_tail(left: M.RowTail, right: M.RowTail) -> Bool:
  Compare.compare(65536n, [Compare.RowTailPair{left, right}], True{})

def same_row(left: M.EffectRow, right: M.EffectRow) -> Bool:
  Compare.compare(65536n, [Compare.EffectRowPair{Rows.canonical(left), Rows.canonical(right)}], True{})

# Constraint resolution can reorder the invocation and callback rows separately
# from the selected signature. Compare both complete multisets without changing
# callback parameter/result types, row tails, or duplicate labels.
def same_predicate(left: M.Predicate, right: M.Predicate) -> Bool:
  match left right:
    case M.AssociatedPredicate{am, at, al, M.FunctionTy{ap, ar, ac}, av, ae} M.AssociatedPredicate{bm, bt, bl, M.FunctionTy{bp, br, bc}, bv, be}:
      Compare.compare(65536n, [Compare.PredicatePair{M.AssociatedPredicate{am, at, al, M.FunctionTy{ap, ar, Rows.canonical(ac)}, av, Rows.canonical(ae)}, M.AssociatedPredicate{bm, bt, bl, M.FunctionTy{bp, br, Rows.canonical(bc)}, bv, Rows.canonical(be)}}], True{})
    case _ _:
      False{}

def same_operation(left: M.Operation, right: M.Operation) -> Bool:
  Compare.compare(65536n, [Compare.OperationPair{left, right}], True{})

# Exactly one declaration for each synthetic identity, with the parameter and
# result types constructed by State.operations for this concrete state type.
def exact_operation(operations: List<&2, M.Operation>, +wanted: M.TypeId, +expected: M.Operation, +found: Bool) -> Bool:
  match operations:
    case Nil{}:
      found
    case M.Operation{+identity, parameter, result} <> tail:
      +same = M.type_id_equal(identity, wanted)
      +valid = Bool.or(Bool.not(same), Bool.and(Bool.not(found), same_operation(M.Operation{identity, parameter, result}, expected)))
      Bool.and(valid, exact_operation(tail, wanted, expected, Bool.or(found, same)))
    case M.OperationTemplate{identity, parameters, parameter, result} <> tail:
      Bool.and(Bool.not(M.type_id_equal(identity, wanted)), exact_operation(tail, wanted, expected, found))
    case M.OperationInstance{template, arguments} <> tail:
      Bool.and(Bool.not(M.type_id_equal(template, wanted)), exact_operation(tail, wanted, expected, found))
    case head <> tail:
      exact_operation(tail, wanted, expected, found)

def exact_catalog(expected: List<&2, M.Operation>, +operations: List<&2, M.Operation>) -> Bool:
  match expected:
    case M.Operation{+read, read_parameter, read_result} <> M.Operation{+write, write_parameter, write_result} <> Nil{}:
      Bool.and(exact_operation(operations, read, M.Operation{read, read_parameter, read_result}, False{}), exact_operation(operations, write, M.Operation{write, write_parameter, write_result}, False{}))
    case _:
      False{}

# A family operation must have one declaration of the exact rank-one shape.
# A concrete declaration or instance with the template's own identity is a
# collision, not another proof of the declared family.
def exact_template(operations: List<&2, M.Operation>, +wanted: M.TypeId, +expected: M.Operation, +found: Bool) -> Bool:
  match operations:
    case Nil{}:
      found
    case M.OperationTemplate{+identity, parameters, parameter, result} <> tail:
      +same = M.type_id_equal(identity, wanted)
      +valid = Bool.or(Bool.not(same), Bool.and(Bool.not(found), same_operation(M.OperationTemplate{identity, parameters, parameter, result}, expected)))
      Bool.and(valid, exact_template(tail, wanted, expected, Bool.or(found, same)))
    case M.Operation{identity, parameter, result} <> tail:
      Bool.and(Bool.not(M.type_id_equal(identity, wanted)), exact_template(tail, wanted, expected, found))
    case M.OperationInstance{template, arguments} <> tail:
      Bool.and(Bool.not(M.type_id_equal(template, wanted)), exact_template(tail, wanted, expected, found))

def family_identity(template: M.TypeId, key: String) -> M.TypeId:
  M.TypeId{module_name, declaration} = template
  M.TypeId{module_name, declaration ++ "<" ++ key ++ ">"}

def family_catalog(+operations: List<&2, M.Operation>, +read_template: M.TypeId, +write_template: M.TypeId, +read: M.TypeId, +write: M.TypeId, +state: M.Ty) -> Bool:
  Bool.and(
    Bool.not(M.type_id_equal(read_template, write_template)),
    Bool.and(
      exact_template(operations, read_template, M.OperationTemplate{read_template, 1n, M.UnitTy{}, M.ParameterTy{0n}}, False{}),
      Bool.and(
        exact_template(operations, write_template, M.OperationTemplate{write_template, 1n, M.ParameterTy{0n}, M.UnitTy{}}, False{}),
        exact_catalog([M.Operation{read, M.UnitTy{}, state}, M.Operation{write, state, M.UnitTy{}}], operations)
      )
    )
  )

def function_name(function: M.Function) -> String:
  M.Function{name, exported, parameter, p, r, body} = function
  name

def exact_run_body(function: M.Function, +name: String, +read: M.TypeId, +write: M.TypeId) -> Bool:
  match function:
    case M.Function{found, exported, parameter, p, r, M.LambdaExpr{+identity, inner_parameter, ip, ir, body}}:
      Compare.compare(65536n, [Compare.FunctionPair{M.Function{found, exported, parameter, p, r, M.LambdaExpr{identity, inner_parameter, ip, ir, body}}, State.function_for(State.Run{}, read, write, name, identity)}], True{})
    case _:
      False{}

# A name match is necessary but never sufficient: the full generated function
# must equal the canonical State.function_for(Run) body, and duplicates fail.
def exact_named_run(functions: List<&2, M.Function>, +name: String, +read: M.TypeId, +write: M.TypeId, +found: Bool) -> Bool:
  match functions:
    case Nil{}:
      found
    case +head <> tail:
      +same = M.name_equal(function_name(head), name)
      +valid = Bool.or(Bool.not(same), Bool.and(Bool.not(found), exact_run_body(head, name, read, write)))
      Bool.and(valid, exact_named_run(tail, name, read, write, Bool.or(found, same)))

type RunSource is Data:
  Builtin{}
  Family{read: M.TypeId, write: M.TypeId}

def source_certificate(+name: String, +predicate: M.Predicate, +member: String, +templates: List<&2, M.TypeId>, +state: M.Ty, +value: M.Ty, +returned_state: M.Ty, +returned_value: M.Ty, +labels: List<&2, M.TypeId>, +callback_tail: M.RowTail, +invocation_labels: List<&2, M.TypeId>, +invocation_tail: M.RowTail, +bound: List<&2, Nat>, +read: M.TypeId, +write: M.TypeId, catalog_ok: Bool, functions: List<&2, M.Function>) -> Bool:
  +callback : M.Ty = M.FunctionTy{M.UnitTy{}, value, M.EffectRow{labels, callback_tail}}
  +result : M.Ty = M.ProductTy{[state, value]}
  +invocation : M.EffectRow = M.EffectRow{invocation_labels, invocation_tail}
  +expected : M.Predicate = M.AssociatedPredicate{member, templates, state, callback, result, invocation}
  Bool.and(
    Bool.and(same_ty(state, returned_state), same_ty(value, returned_value)),
    Bool.and(
      Bool.and(Bool.and(admissible_tail(callback_tail, bound), admissible_result_type(65536n, [value], bound)), same_tail(callback_tail, invocation_tail)),
      Bool.and(
        Bool.and(same_row(M.EffectRow{labels, M.ClosedRow{}}, M.EffectRow{List.append(&2, M.TypeId, [read, write], invocation_labels), M.ClosedRow{}}), same_predicate(predicate, expected)),
        Bool.and(catalog_ok, exact_named_run(functions, name, read, write, False{}))
      )
    )
  )

def key_certificate(key_result: Result<&2, &2, M.Diagnostic, String>, source: RunSource, +name: String, +predicate: M.Predicate, +state: M.Ty, +value: M.Ty, +returned_state: M.Ty, +returned_value: M.Ty, +labels: List<&2, M.TypeId>, +callback_tail: M.RowTail, +invocation_labels: List<&2, M.TypeId>, +invocation_tail: M.RowTail, +bound: List<&2, Nat>, module: M.Module) -> Bool:
  match key_result source:
    case Fail{diagnostic} _:
      False{}
    case Done{+key} Builtin{}:
      M.Module{constants, functions, types, operations} = module
      +read = State.read_identity(key)
      +write = State.write_identity(key)
      source_certificate(name, predicate, "@state.run", Nil{}, state, value, returned_state, returned_value, labels, callback_tail, invocation_labels, invocation_tail, bound, read, write, exact_catalog(State.operations(key, state, Nil{}), operations), functions)
    case Done{+key} Family{+read_template, +write_template}:
      M.Module{constants, functions, types, operations} = module
      +read = family_identity(read_template, key)
      +write = family_identity(write_template, key)
      source_certificate(name, predicate, "@effect.run", [read_template, write_template], state, value, returned_state, returned_value, labels, callback_tail, invocation_labels, invocation_tail, bound, read, write, family_catalog(operations, read_template, write_template, read, write, state), functions)

def source_key(source: RunSource, state: M.Ty) -> Result<&2, &2, M.Diagnostic, String>:
  match source:
    case Builtin{}:
      State.type_key(65536n, State.TypeKey{state})
    case Family{read, write}:
      State.type_key(65536n, State.TypesKey{[state]})

def signature_shape(signature: M.Ty, predicate: M.Predicate, name: String, +source: RunSource, +bound: List<&2, Nat>, module: M.Module, free_ok: Bool) -> Bool:
  match signature:
    case M.FunctionTy{+state, M.FunctionTy{M.FunctionTy{M.UnitTy{}, value, M.EffectRow{labels, callback_tail}}, M.ProductTy{returned_state <> returned_value <> Nil{}}, M.EffectRow{invocation_labels, invocation_tail}}, M.EffectRow{Nil{}, M.ClosedRow{}}}:
      Bool.and(free_ok, key_certificate(source_key(source, state), source, name, predicate, state, value, returned_state, returned_value, labels, callback_tail, invocation_labels, invocation_tail, bound, module))
    case _:
      False{}

def signature_certificate(+signature: M.Ty, predicate: M.Predicate, name: String, source: RunSource, +bound: List<&2, Nat>, module: M.Module) -> Bool:
  signature_shape(signature, predicate, name, source, bound, module, free_within(T.free(signature), bound))

# The caller supplies variables generalized by this evidence's owning binding,
# not a union of every scheme in the module. No open source row or noncanonical
# operation/body can pass this certificate.
def certify_run(+predicate: M.Predicate, evidence: C.Evidence, bound: List<&2, Nat>, module: M.Module) -> Bool:
  match predicate evidence:
    case M.AssociatedPredicate{member, Nil{}, left, right, result, invocation} C.SelectedFunction{name, signature}:
      Bool.and(M.name_equal(member, "@state.run"), signature_certificate(signature, predicate, name, Builtin{}, bound, module))
    case M.AssociatedPredicate{member, read <> write <> Nil{}, left, right, result, invocation} C.SelectedFunction{name, signature}:
      Bool.and(M.name_equal(member, "@effect.run"), signature_certificate(signature, predicate, name, Family{read, write}, bound, module))
    case _ _:
      False{}
