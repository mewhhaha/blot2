import Base
import ./model.bend as M
import ./constraints.bend as C
import ./core_compare.bend as Compare
import ./state_specialize.bend as State
import ./staging_scheme.bend as Staging
import ./types.bend as T

# A certificate for the generated clone of std/prelude Type.eq. The caller
# supplies the @type.same choice from the exact AssociatedExpr site returned
# by clone_site. No search by a generated function-name prefix is sufficient.
# The returned signature changes only the two invocation rows. In particular
# callable rows inside either Type argument remain byte-for-byte unchanged.

type Located is Data:
  Missing{}
  One{function: M.Function}
  Duplicate{}

def locate_work(functions: List<&2, M.Function>, +wanted: String, found: Located) -> Located:
  match functions found:
    case Nil{} result:
      result
    case M.Function{+name, exported, parameter, p, r, body} <> tail Missing{}:
      locate_work(tail, wanted, Bool.pick(Located, M.name_equal(name, wanted), One{M.Function{name, exported, parameter, p, r, body}}, Missing{}))
    case M.Function{+name, exported, parameter, p, r, body} <> tail One{previous}:
      locate_work(tail, wanted, Bool.pick(Located, M.name_equal(name, wanted), Duplicate{}, One{previous}))
    case head <> tail Duplicate{}:
      locate_work(tail, wanted, Duplicate{})

def located(found: Located) -> Maybe<&2, M.Function>:
  match found:
    case One{function}:
      Some{function}
    case _:
      None{}

def locate(functions: List<&2, M.Function>, name: String) -> Maybe<&2, M.Function>:
  located(locate_work(functions, name, Missing{}))

def local_name(value: M.Expr) -> Maybe<&2, String>:
  match value:
    case M.SourceExpr{offset, None{}, M.InstantiationExpr{site, M.LocalExpr{name}}}:
      Some{name}
    case _:
      None{}

def local_is_found(found: Maybe<&2, String>, +wanted: String) -> Bool:
  match found:
    case Some{name}:
      M.name_equal(name, wanted)
    case None{}:
      False{}

def local_is(value: M.Expr, wanted: String) -> Bool:
  local_is_found(local_name(value), wanted)

def arm_site(arm: M.MatchArm<M.Expr>) -> Maybe<&2, Nat>:
  match arm:
    case M.MatchArm{[M.ConstructorPattern{first, Some{M.BindingPattern{+a}}}, M.ConstructorPattern{second, Some{M.BindingPattern{+b}}}], M.SourceExpr{offset, None{}, M.AssociatedExpr{site, M.BinaryDispatch{}, member, Nil{}, l, r}}}:
      Bool.pick(Maybe<&2, Nat>, Bool.and(M.name_equal(first, "$prelude.Type"), Bool.and(M.name_equal(second, "$prelude.Type"), Bool.and(M.name_equal(member, "@type.same"), Bool.and(Bool.not(M.name_equal(a, b)), Bool.and(local_is(l, a), local_is(r, b)))))), Some{site}, None{})
    case _:
      None{}

def match_if(valid: Bool, arm: M.MatchArm<M.Expr>) -> Maybe<&2, Nat>:
  match valid:
    case True{}:
      arm_site(arm)
    case False{}:
      None{}

def match_locals(a: Maybe<&2, String>, b: Maybe<&2, String>, arm: M.MatchArm<M.Expr>, +left: String, +right: String) -> Maybe<&2, Nat>:
  match a b:
    case Some{found_left} Some{found_right}:
      match_if(Bool.and(M.name_equal(found_left, left), Bool.and(M.name_equal(found_right, right), Bool.not(M.name_equal(left, right)))), arm)
    case _ _:
      None{}

def match_site(value: M.Expr, left: String, right: String) -> Maybe<&2, Nat>:
  match value:
    case M.SourceExpr{offset, None{}, M.MatchExpr{[a, b], [arm]}}:
      match_locals(local_name(a), local_name(b), arm, left, right)
    case _:
      None{}

def source_clone_parsed(parsed: Maybe<&2, Staging.CloneName>) -> Bool:
  match parsed:
    case Some{Staging.CloneName{counter, source}}:
      M.name_equal(source, "$prelude.Type.eq")
    case _:
      False{}

def source_clone(name: String) -> Bool:
  source_clone_parsed(Staging.clone_name(name))

def canonical_if(source: Bool, body: M.Expr, left: String, right: String) -> Maybe<&2, Nat>:
  match source:
    case True{}:
      match_site(body, left, right)
    case False{}:
      None{}

def canonical_site(function: M.Function) -> Maybe<&2, Nat>:
  match function:
    case M.Function{name, False{}, left, None{}, None{}, M.SourceExpr{offset, None{}, M.LambdaExpr{identity, right, None{}, None{}, body}}}:
      canonical_if(source_clone(name), body, left, right)
    case _:
      None{}

def clone_site_found(found: Maybe<&2, M.Function>) -> Maybe<&2, Nat>:
  match found:
    case Some{function}:
      canonical_site(function)
    case None{}:
      None{}

def clone_site(evidence: C.Evidence, module: M.Module) -> Maybe<&2, Nat>:
  match evidence module:
    case C.SelectedFunction{name, signature} M.Module{constants, functions, types, operations}:
      clone_site_found(locate(functions, name))
    case _ _:
      None{}

def type_argument(ty: M.Ty) -> Maybe<&2, M.Ty>:
  match ty:
    case M.AppliedTy{identity, [argument]}:
      Bool.pick(Maybe<&2, M.Ty>, M.type_id_equal(identity, M.TypeId{"std/prelude", "Type"}), Some{argument}, None{})
    case _:
      None{}

type TypeCatalog is Data:
  TypeAbsent{}
  TypeUnique{valid: Bool}
  TypeDuplicate{}

def exact_type_record(identity: M.TypeId, parameters: Nat, sole: Bool, payload: Maybe<&2, M.Ty>, fields: List<&2, String>) -> Bool:
  match payload fields:
    case Some{M.ParameterTy{0n}} Nil{}:
      Bool.and(sole, Bool.and(M.type_id_equal(identity, M.TypeId{"std/prelude", "Type"}), Nat.is_eq(parameters, 1n)))
    case _ _:
      False{}

def catalog_record(named: Bool, valid: Bool, current: TypeCatalog) -> TypeCatalog:
  match named current:
    case False{} previous:
      previous
    case True{} TypeAbsent{}:
      TypeUnique{valid}
    case True{} _:
      TypeDuplicate{}

def catalog_constructors(constructors: List<&2, M.Constructor>, +identity: M.TypeId, +parameters: Nat, +sole: Bool, current: TypeCatalog) -> TypeCatalog:
  match constructors:
    case Nil{}:
      current
    case M.Constructor{name, payload, fields} <> tail:
      catalog_constructors(tail, identity, parameters, sole, catalog_record(M.name_equal(name, "$prelude.Type"), exact_type_record(identity, parameters, sole, payload, fields), current))

def catalog_types(types: List<&2, M.DataType>, current: TypeCatalog) -> TypeCatalog:
  match types:
    case Nil{}:
      current
    case M.DataType{identity, parameters, +constructors} <> tail:
      catalog_types(tail, catalog_constructors(constructors, identity, parameters, Nat.is_eq(List.length(&2, M.Constructor, constructors), 1n), current))

def type_owner_count(types: List<&2, M.DataType>) -> Nat:
  match types:
    case Nil{}:
      0n
    case M.DataType{identity, parameters, constructors} <> tail:
      Nat.add(Bool.pick(Nat, M.type_id_equal(identity, M.TypeId{"std/prelude", "Type"}), 1n, 0n), type_owner_count(tail))

def exact_type_catalog(found: TypeCatalog) -> Bool:
  match found:
    case TypeUnique{True{}}:
      True{}
    case _:
      False{}

def exact_type_constructor(+types: List<&2, M.DataType>) -> Bool:
  Bool.and(Nat.is_eq(type_owner_count(types), 1n), exact_type_catalog(catalog_types(types, TypeAbsent{})))

def key_equal_results(a_key: Result<&2, &2, M.Diagnostic, String>, b_key: Result<&2, &2, M.Diagnostic, String>) -> Maybe<&2, Bool>:
  match a_key b_key:
    case Done{a} Done{b}:
      Some{M.name_equal(a, b)}
    case _ _:
      None{}

def key_equal(left: M.Ty, right: M.Ty) -> Maybe<&2, Bool>:
  key_equal_results(State.type_key(65536n, State.TypeKey{State.witness(65536n, left)}), State.type_key(65536n, State.TypeKey{State.witness(65536n, right)}))

def generated_bool(function: M.Function, expected: Bool) -> Bool:
  match function:
    case M.Function{name, False{}, first, None{}, None{}, M.LambdaExpr{identity, second, None{}, None{}, M.BoolExpr{actual}}}:
      Bool.and(M.name_equal(first, "$type.left"), Bool.and(M.name_equal(second, "$type.right"), Bool.not(Bool.xor(expected, actual))))
    case _:
      False{}

def same_selected_found(found: Maybe<&2, M.Function>, a: M.Ty, b: M.Ty, +left: M.Ty, +right: M.Ty, expected: Bool) -> Bool:
  match found:
    case Some{function}:
      Bool.and(Compare.same_ty(a, left), Bool.and(Compare.same_ty(b, right), generated_bool(function, expected)))
    case None{}:
      False{}

def same_selected(same: C.Evidence, functions: List<&2, M.Function>, left: M.Ty, right: M.Ty, expected: Bool) -> Bool:
  match same:
    case C.SelectedFunction{name, M.FunctionTy{a, M.FunctionTy{b, M.BoolTy{}, inner}, outer}}:
      same_selected_found(locate(functions, name), a, b, left, right, expected)
    case _:
      False{}

def certify_payloads_found(expected: Maybe<&2, Bool>, left: M.Ty, right: M.Ty, same: C.Evidence, functions: List<&2, M.Function>) -> Bool:
  match expected:
    case Some{answer}:
      same_selected(same, functions, left, right, answer)
    case None{}:
      False{}

def certify_payloads(+left: M.Ty, +right: M.Ty, same: C.Evidence, functions: List<&2, M.Function>) -> Bool:
  certify_payloads_found(key_equal(left, right), left, right, same, functions)

def disjoint_claim(left: Result<&2, &2, M.Diagnostic, List<&2, Nat>>, right: Result<&2, &2, M.Diagnostic, List<&2, Nat>>, +index: Nat) -> Bool:
  match left right:
    case Done{a} Done{b}:
      Bool.and(Bool.not(T.contains(a, index)), Bool.not(T.contains(b, index)))
    case _ _:
      False{}

def pure_claim(row: M.EffectRow, left: M.Ty, right: M.Ty) -> Bool:
  match row:
    case M.EffectRow{Nil{}, M.ClosedRow{}}:
      True{}
    case M.EffectRow{Nil{}, M.RowVariable{index}}:
      disjoint_claim(T.free(left), T.free(right), index)
    case _:
      False{}

def certified_found(a: Maybe<&2, M.Ty>, b: Maybe<&2, M.Ty>, site: Maybe<&2, Nat>, +member: String, +wanted: Nat, invocation: M.EffectRow, types: List<&2, M.DataType>, functions: List<&2, M.Function>, +left: M.Ty, +right: M.Ty, selected_left: M.Ty, selected_right: M.Ty, same: C.Evidence) -> Maybe<&2, M.Ty>:
  match a b site:
    case Some{payload_left} Some{payload_right} Some{found}:
      valid = Bool.and(pure_claim(invocation, left, right), Bool.and(M.name_equal(member, "eq"), Bool.and(Nat.is_eq(found, wanted), Bool.and(exact_type_constructor(types), Bool.and(Compare.same_ty(left, selected_left), Bool.and(Compare.same_ty(right, selected_right), certify_payloads(payload_left, payload_right, same, functions)))))))
      Bool.pick(Maybe<&2, M.Ty>, valid, Some{M.FunctionTy{left, M.FunctionTy{right, M.BoolTy{}, M.empty_row()}, M.empty_row()}}, None{})
    case _ _ _:
      None{}

def certified_signature(predicate: M.Predicate, outer: C.Evidence, same_site: Nat, same: C.Evidence, module: M.Module) -> Maybe<&2, M.Ty>:
  match predicate outer module:
    case M.AssociatedPredicate{member, Nil{}, +left, +right, M.BoolTy{}, invocation} C.SelectedFunction{name, M.FunctionTy{+selected_left, M.FunctionTy{+selected_right, M.BoolTy{}, inner}, outer_row}} M.Module{constants, +functions, +types, operations}:
      certified_found(type_argument(left), type_argument(right), clone_site(C.SelectedFunction{name, M.FunctionTy{selected_left, M.FunctionTy{selected_right, M.BoolTy{}, inner}, outer_row}}, M.Module{constants, functions, types, operations}), member, same_site, invocation, types, functions, left, right, selected_left, selected_right, same)
    case _ _ _:
      None{}
