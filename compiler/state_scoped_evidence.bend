import Base
import ./model.bend as M
import ./constraints.bend as C
import ./types.bend as T
import ./state_specialize.bend as State
import ./state_run_evidence.bend as RunEvidence
import ./core_compare.bend as Compare
import ./effect_rows.bend as Rows

# A generated reader/writer handles exactly one concrete operation. Its
# implementation uses the residual invocation row E, while its action uses
# that one operation plus E, including every repeated label. The generated
# outer arrow is pure. Only owner-quantified flexible variables may remain.
type Source is Data:
  BuiltinReader{}
  BuiltinWriter{}
  FamilyReader{template: M.TypeId}
  FamilyWriter{template: M.TypeId}

def operation_match(same: Bool, found: Bool, actual: M.Operation, expected: M.Operation) -> Bool:
  match same found:
    case False{} _:
      True{}
    case True{} False{}:
      RunEvidence.same_operation(actual, expected)
    case True{} True{}:
      False{}

def exact_operation(operations: List<&2, M.Operation>, +wanted: M.TypeId, +expected: M.Operation, +found: Bool) -> Bool:
  match operations:
    case Nil{}:
      found
    case M.Operation{+identity, parameter, result} <> tail:
      +same = M.type_id_equal(identity, wanted)
      +valid = operation_match(same, found, M.Operation{identity, parameter, result}, expected)
      Bool.and(valid, exact_operation(tail, wanted, expected, Bool.or(found, same)))
    case M.OperationTemplate{identity, parameters, parameter, result} <> tail:
      Bool.and(Bool.not(M.type_id_equal(identity, wanted)), exact_operation(tail, wanted, expected, found))
    case M.OperationInstance{template, arguments} <> tail:
      Bool.and(Bool.not(M.type_id_equal(template, wanted)), exact_operation(tail, wanted, expected, found))

def template_match(same: Bool, found: Bool, actual: M.Operation, expected: M.Operation) -> Bool:
  match same found:
    case False{} _:
      True{}
    case True{} False{}:
      RunEvidence.same_operation(actual, expected)
    case True{} True{}:
      False{}

def exact_template(operations: List<&2, M.Operation>, +wanted: M.TypeId, +expected: M.Operation, +found: Bool) -> Bool:
  match operations:
    case Nil{}:
      found
    case M.OperationTemplate{+identity, parameters, parameter, result} <> tail:
      +same = M.type_id_equal(identity, wanted)
      +valid = template_match(same, found, M.OperationTemplate{identity, parameters, parameter, result}, expected)
      Bool.and(valid, exact_template(tail, wanted, expected, Bool.or(found, same)))
    case M.Operation{identity, parameter, result} <> tail:
      Bool.and(Bool.not(M.type_id_equal(identity, wanted)), exact_template(tail, wanted, expected, found))
    case M.OperationInstance{template, arguments} <> tail:
      Bool.and(Bool.not(M.type_id_equal(template, wanted)), exact_template(tail, wanted, expected, found))

def function_name(function: M.Function) -> String:
  M.Function{name, exported, parameter, p, r, body} = function
  name

def exact_body(function: M.Function, request: State.Request, +read: M.TypeId, +write: M.TypeId, +name: String) -> Bool:
  match function:
    case M.Function{found, exported, parameter, p, r, M.LambdaExpr{+identity, inner_parameter, ip, ir, body}}:
      Compare.compare(65536n, [Compare.FunctionPair{M.Function{found, exported, parameter, p, r, M.LambdaExpr{identity, inner_parameter, ip, ir, body}}, State.function_for(request, read, write, name, identity)}], True{})
    case _:
      False{}

def named_match(same: Bool, found: Bool, function: M.Function, request: State.Request, read: M.TypeId, write: M.TypeId, name: String) -> Bool:
  match same found:
    case False{} _:
      True{}
    case True{} False{}:
      exact_body(function, request, read, write, name)
    case True{} True{}:
      False{}

def exact_named(functions: List<&2, M.Function>, +name: String, +request: State.Request, +read: M.TypeId, +write: M.TypeId, +found: Bool) -> Bool:
  match functions:
    case Nil{}:
      found
    case +head <> tail:
      +same = M.name_equal(function_name(head), name)
      +valid = named_match(same, found, head, request, read, write, name)
      Bool.and(valid, exact_named(tail, name, request, read, write, Bool.or(found, same)))

def source_key(source: Source, state: M.Ty) -> Result<&2, &2, M.Diagnostic, String>:
  match source:
    case BuiltinReader{}:
      State.type_key(65536n, State.TypeKey{state})
    case BuiltinWriter{}:
      State.type_key(65536n, State.TypeKey{state})
    case FamilyReader{template}:
      State.type_key(65536n, State.TypesKey{[state]})
    case FamilyWriter{template}:
      State.type_key(65536n, State.TypesKey{[state]})

def builtin_catalog(+operations: List<&2, M.Operation>, +read: M.TypeId, +write: M.TypeId, +state: M.Ty) -> Bool:
  Bool.and(Bool.not(M.type_id_equal(read, write)), Bool.and(exact_operation(operations, read, M.Operation{read, M.UnitTy{}, state}, False{}), exact_operation(operations, write, M.Operation{write, state, M.UnitTy{}}, False{})))

def family_reader_catalog(+operations: List<&2, M.Operation>, +template: M.TypeId, +read: M.TypeId, +state: M.Ty) -> Bool:
  Bool.and(exact_template(operations, template, M.OperationTemplate{template, 1n, M.UnitTy{}, M.ParameterTy{0n}}, False{}), exact_operation(operations, read, M.Operation{read, M.UnitTy{}, state}, False{}))

def family_writer_catalog(+operations: List<&2, M.Operation>, +template: M.TypeId, +write: M.TypeId, +state: M.Ty) -> Bool:
  Bool.and(exact_template(operations, template, M.OperationTemplate{template, 1n, M.ParameterTy{0n}, M.UnitTy{}}, False{}), exact_operation(operations, write, M.Operation{write, state, M.UnitTy{}}, False{}))

def body_if_catalog(valid: Bool, functions: List<&2, M.Function>, name: String, request: State.Request, read: M.TypeId, write: M.TypeId) -> Bool:
  match valid:
    case False{}:
      False{}
    case True{}:
      exact_named(functions, name, request, read, write, False{})

def source_catalog_body(source: Source, +key: String, +state: M.Ty, +operation: M.TypeId, +name: String, module: M.Module) -> Bool:
  match source module:
    case BuiltinReader{} M.Module{constants, functions, types, operations}:
      +read = State.read_identity(key)
      +write = State.write_identity(key)
      body_if_catalog(builtin_catalog(operations, read, write, state), functions, name, State.Reader{}, read, write)
    case BuiltinWriter{} M.Module{constants, functions, types, operations}:
      +read = State.read_identity(key)
      +write = State.write_identity(key)
      body_if_catalog(builtin_catalog(operations, read, write, state), functions, name, State.Writer{}, read, write)
    case FamilyReader{template} M.Module{constants, functions, types, operations}:
      body_if_catalog(family_reader_catalog(operations, template, operation, state), functions, name, State.Reader{}, operation, operation)
    case FamilyWriter{template} M.Module{constants, functions, types, operations}:
      body_if_catalog(family_writer_catalog(operations, template, operation, state), functions, name, State.Writer{}, operation, operation)

def implementation_shape(source: Source, implementation: M.Ty, state: M.Ty, invocation: M.EffectRow) -> Bool:
  match source implementation:
    case BuiltinReader{} M.FunctionTy{parameter, result, effects}:
      Bool.and(RunEvidence.same_ty(parameter, M.UnitTy{}), Bool.and(RunEvidence.same_ty(result, state), RunEvidence.same_row(effects, invocation)))
    case FamilyReader{template} M.FunctionTy{parameter, result, effects}:
      Bool.and(RunEvidence.same_ty(parameter, M.UnitTy{}), Bool.and(RunEvidence.same_ty(result, state), RunEvidence.same_row(effects, invocation)))
    case BuiltinWriter{} M.FunctionTy{parameter, result, effects}:
      Bool.and(RunEvidence.same_ty(parameter, state), Bool.and(RunEvidence.same_ty(result, M.UnitTy{}), RunEvidence.same_row(effects, invocation)))
    case FamilyWriter{template} M.FunctionTy{parameter, result, effects}:
      Bool.and(RunEvidence.same_ty(parameter, state), Bool.and(RunEvidence.same_ty(result, M.UnitTy{}), RunEvidence.same_row(effects, invocation)))
    case _ _:
      False{}

def source_member(source: Source) -> String:
  match source:
    case BuiltinReader{}:
      "@state.reader"
    case BuiltinWriter{}:
      "@state.writer"
    case FamilyReader{template}:
      "@effect.reader"
    case FamilyWriter{template}:
      "@effect.writer"

def source_templates(source: Source) -> List<&2, M.TypeId>:
  match source:
    case BuiltinReader{}:
      Nil{}
    case BuiltinWriter{}:
      Nil{}
    case FamilyReader{template}:
      [template]
    case FamilyWriter{template}:
      [template]

def source_checked(eligible: Bool, source: Source, key: String, state: M.Ty, operation: M.TypeId, name: String, module: M.Module) -> Bool:
  match eligible:
    case False{}:
      False{}
    case True{}:
      source_catalog_body(source, key, state, operation, name, module)

# Resolution may sort a callback's row independently of the selected signature.
# Compare its complete multiset and tail, retaining exact parameter/result types.
def same_callback(left: M.Ty, right: M.Ty) -> Bool:
  match left right:
    case M.FunctionTy{ap, ar, ae} M.FunctionTy{bp, br, be}:
      Bool.and(RunEvidence.same_ty(ap, bp), Bool.and(RunEvidence.same_ty(ar, br), RunEvidence.same_row(ae, be)))
    case _ _:
      False{}

def same_scoped_predicate(left: M.Predicate, right: M.Predicate) -> Bool:
  match left right:
    case M.AssociatedPredicate{am, at, al, M.ProductTy{ai <> aa <> Nil{}}, av, ae} M.AssociatedPredicate{bm, bt, bl, M.ProductTy{bi <> ba <> Nil{}}, bv, be}:
      Bool.and(
        Compare.compare(65536n, [Compare.PredicatePair{M.AssociatedPredicate{am, at, al, M.UnitTy{}, av, Rows.canonical(ae)}, M.AssociatedPredicate{bm, bt, bl, M.UnitTy{}, bv, Rows.canonical(be)}}], True{}),
        Bool.and(same_callback(ai, bi), same_callback(aa, ba))
      )
    case _ _:
      False{}

def source_certificate(+source: Source, +predicate: M.Predicate, +name: String, +key: String, +witness: M.Ty, +state: M.Ty, +implementation: M.Ty, +action: M.Ty, +result: M.Ty, +action_labels: List<&2, M.TypeId>, +action_tail: M.RowTail, +invocation_labels: List<&2, M.TypeId>, +invocation_tail: M.RowTail, +bound: List<&2, Nat>, +operation: M.TypeId, module: M.Module) -> Bool:
  +invocation : M.EffectRow = M.EffectRow{invocation_labels, invocation_tail}
  +expected : M.Predicate = M.AssociatedPredicate{source_member(source), source_templates(source), witness, M.ProductTy{[implementation, action]}, result, invocation}
  +callback : M.EffectRow = M.EffectRow{action_labels, action_tail}
  +expected_callback : M.EffectRow = M.EffectRow{operation <> invocation_labels, invocation_tail}
  +valid = Bool.and(
    Bool.and(RunEvidence.admissible_tail(invocation_tail, bound), RunEvidence.admissible_result_type(65536n, [result], bound)),
    Bool.and(
      Bool.and(implementation_shape(source, implementation, state, invocation), RunEvidence.same_row(callback, expected_callback)),
      same_scoped_predicate(predicate, expected)
    )
  )
  source_checked(valid, source, key, state, operation, name, module)

def key_certificate(found: Result<&2, &2, M.Diagnostic, String>, source: Source, predicate: M.Predicate, name: String, witness: M.Ty, state: M.Ty, implementation: M.Ty, action: M.Ty, result: M.Ty, action_labels: List<&2, M.TypeId>, action_tail: M.RowTail, invocation_labels: List<&2, M.TypeId>, invocation_tail: M.RowTail, bound: List<&2, Nat>, module: M.Module) -> Bool:
  match found source:
    case Fail{diagnostic} _:
      False{}
    case Done{+key} BuiltinReader{}:
      source_certificate(BuiltinReader{}, predicate, name, key, witness, state, implementation, action, result, action_labels, action_tail, invocation_labels, invocation_tail, bound, State.read_identity(key), module)
    case Done{+key} BuiltinWriter{}:
      source_certificate(BuiltinWriter{}, predicate, name, key, witness, state, implementation, action, result, action_labels, action_tail, invocation_labels, invocation_tail, bound, State.write_identity(key), module)
    case Done{+key} FamilyReader{+template}:
      source_certificate(FamilyReader{template}, predicate, name, key, witness, state, implementation, action, result, action_labels, action_tail, invocation_labels, invocation_tail, bound, RunEvidence.family_identity(template, key), module)
    case Done{+key} FamilyWriter{+template}:
      source_certificate(FamilyWriter{template}, predicate, name, key, witness, state, implementation, action, result, action_labels, action_tail, invocation_labels, invocation_tail, bound, RunEvidence.family_identity(template, key), module)

def signature_shape(signature: M.Ty, predicate: M.Predicate, name: String, +source: Source, +bound: List<&2, Nat>, module: M.Module, free_ok: Bool) -> Bool:
  match signature:
    case M.FunctionTy{+witness, M.FunctionTy{M.ProductTy{+implementation <> M.FunctionTy{M.UnitTy{}, +result, M.EffectRow{+action_labels, +action_tail}} <> Nil{}}, returned, M.EffectRow{+invocation_labels, +invocation_tail}}, M.EffectRow{Nil{}, M.ClosedRow{}}}:
      +state : M.Ty = State.witness(65536n, witness)
      Bool.and(free_ok, Bool.and(RunEvidence.admissible_result_type(65536n, [witness], bound), Bool.and(RunEvidence.same_ty(result, returned), key_certificate(source_key(source, state), source, predicate, name, witness, state, implementation, M.FunctionTy{M.UnitTy{}, result, M.EffectRow{action_labels, action_tail}}, result, action_labels, action_tail, invocation_labels, invocation_tail, bound, module))))
    case _:
      False{}

def signature_certificate(+signature: M.Ty, predicate: M.Predicate, name: String, source: Source, +bound: List<&2, Nat>, module: M.Module) -> Bool:
  signature_shape(signature, predicate, name, source, bound, module, RunEvidence.free_within(T.free(signature), bound))

def selected_member(valid: Bool, predicate: M.Predicate, evidence: C.Evidence, source: Source, bound: List<&2, Nat>, module: M.Module) -> Bool:
  match valid evidence:
    case True{} C.SelectedFunction{name, signature}:
      signature_certificate(signature, predicate, name, source, bound, module)
    case _ _:
      False{}

# The caller supplies variables generalized by this answer's owning binding.
# Ordinary evidence still follows the strict closed-signature path.
def certify_scoped(+predicate: M.Predicate, +evidence: C.Evidence, +bound: List<&2, Nat>, +module: M.Module) -> Bool:
  match predicate:
    case M.AssociatedPredicate{+member, Nil{}, left, right, result, invocation}:
      Bool.or(
        selected_member(M.name_equal(member, "@state.reader"), predicate, evidence, BuiltinReader{}, bound, module),
        selected_member(M.name_equal(member, "@state.writer"), predicate, evidence, BuiltinWriter{}, bound, module)
      )
    case M.AssociatedPredicate{+member, +template <> Nil{}, left, right, result, invocation}:
      Bool.or(
        selected_member(M.name_equal(member, "@effect.reader"), predicate, evidence, FamilyReader{template}, bound, module),
        selected_member(M.name_equal(member, "@effect.writer"), predicate, evidence, FamilyWriter{template}, bound, module)
      )
    case _:
      False{}
