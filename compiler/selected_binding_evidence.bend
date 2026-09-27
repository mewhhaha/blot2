import Base
import ./model.bend as M
import ./infer.bend as I
import ./types.bend as T
import ./constraints.bend as C
import ./core_compare.bend as Compare

# A selected callable may retain flexible rows in an argument or witness
# supplied by its owner. This proof checks that its exact signature is an
# instance of one current, generalized, predicate-free source binding. It is
# isolated from the caller's substitutions and does not finalize an invocation.

def admissible_row(row: M.EffectRow) -> Bool:
  match row:
    case M.EffectRow{operations, M.ClosedRow{}}: True{}
    case M.EffectRow{operations, M.RowVariable{index}}: True{}
    case _: False{}

def admissible_types(+fuel: Nat, pending: List<&2, M.Ty>) -> Bool:
  match fuel pending:
    case _ Nil{}: True{}
    case 0n _: False{}
    case 1n+rest M.UnitTy{} <> tail: admissible_types(rest, tail)
    case 1n+rest M.U32Ty{} <> tail: admissible_types(rest, tail)
    case 1n+rest M.F32Ty{} <> tail: admissible_types(rest, tail)
    case 1n+rest M.BoolTy{} <> tail: admissible_types(rest, tail)
    case 1n+rest M.EffectDescriptorTy{} <> tail: admissible_types(rest, tail)
    case 1n+rest M.EffectSetTy{} <> tail: admissible_types(rest, tail)
    case 1n+rest M.VariableTy{index} <> tail: admissible_types(rest, tail)
    case 1n+rest M.FunctionTy{parameter, result, effects} <> tail:
      Bool.and(admissible_row(effects), admissible_types(rest, parameter <> result <> tail))
    case 1n+rest M.ProviderTy{identity, effects} <> tail:
      Bool.and(admissible_row(effects), admissible_types(rest, tail))
    case 1n+rest M.StateProviderTy{read, write, state} <> tail:
      admissible_types(rest, state <> tail)
    case 1n+rest M.AppliedTy{identity, arguments} <> tail:
      admissible_types(rest, List.append(&2, M.Ty, arguments, tail))
    case 1n+rest M.ProductTy{elements} <> tail:
      admissible_types(rest, List.append(&2, M.Ty, elements, tail))
    case 1n+rest M.ArrayTy{element} <> tail:
      admissible_types(rest, element <> tail)
    # Never is a wildcard in unification. Source names and rigid parameters
    # are not inferred scheme variables. Do not certify any of these shapes.
    case _ _: False{}

def unique_variables(values: List<&2, Nat>) -> Bool:
  match values:
    case Nil{}: True{}
    case head <> +tail:
      Bool.and(Bool.not(T.contains(tail, head)), unique_variables(tail))

def subset(values: List<&2, Nat>, +allowed: List<&2, Nat>) -> Bool:
  match values:
    case Nil{}: True{}
    case head <> tail:
      Bool.and(T.contains(allowed, head), subset(tail, allowed))

def resolved_same(found: Result<&2, &2, M.Diagnostic, M.Ty>, selected: M.Ty) -> Bool:
  match found:
    case Done{resolved}: Compare.same_ty(resolved, selected)
    case Fail{diagnostic}: False{}

def unified(found: Result<&2, &2, M.Diagnostic, T.Substitutions>, +selected: M.Ty) -> Bool:
  match found:
    case Done{substitutions}:
      resolved_same(T.resolve(substitutions, selected), selected)
    case Fail{diagnostic}: False{}

def renamed(found: Result<&2, &2, M.Diagnostic, M.Ty>, +selected: M.Ty) -> Bool:
  match found:
    case Done{fresh}:
      unified(T.unify(fresh, selected, T.empty(), "selected source binding"), selected)
    case Fail{diagnostic}: False{}

def freshened(renaming: T.Renaming, source: M.Ty, selected: M.Ty) -> Bool:
  match renaming:
    case T.Renaming{mapping, next, True{}}:
      renamed(T.rename_type(source, mapping), selected)
    case _:
      False{}

def admissible_instance(ready: Bool, source: M.Ty, selected: M.Ty, quantified: List<&2, Nat>, source_free: List<&2, Nat>, selected_free: List<&2, Nat>) -> Bool:
  match ready:
    case True{}:
      freshened(T.renaming(quantified, T.above(T.union(source_free, selected_free), 0n)), source, selected)
    case False{}: False{}

def checked_free(source_result: Result<&2, &2, M.Diagnostic, List<&2, Nat>>, selected_result: Result<&2, &2, M.Diagnostic, List<&2, Nat>>, +source: M.Ty, +selected: M.Ty, +quantified: List<&2, Nat>, owner_bound: List<&2, Nat>) -> Bool:
  match source_result selected_result:
    case Done{+source_free} Done{+selected_free}:
      admissible_instance(Bool.and(unique_variables(quantified), Bool.and(subset(source_free, quantified), Bool.and(subset(selected_free, owner_bound), Bool.and(admissible_types(65536n, [source]), admissible_types(65536n, [selected]))))), source, selected, quantified, source_free, selected_free)
    case _ _: False{}

def checked_binding(binding: I.Binding, +selected: M.Ty, owner_bound: List<&2, Nat>) -> Bool:
  I.Binding{name, +source, quantified, predicates} = binding
  match predicates:
    case Nil{}:
      checked_free(T.free(source), T.free(selected), source, selected, quantified, owner_bound)
    case _: False{}

def certify_same(same: Bool, binding: I.Binding, selected: M.Ty, owner_bound: List<&2, Nat>) -> Bool:
  match same:
    case True{}: checked_binding(binding, selected, owner_bound)
    case False{}: False{}

# Caller must supply the exact current uniquely named binding, already
# resolved under the same current substitutions as the selected evidence.
# It must still validate the exact chosen site and qualified invocation.
def certify(+binding: I.Binding, evidence: C.Evidence, owner_bound: List<&2, Nat>) -> Bool:
  match binding evidence:
    case I.Binding{+source_name, ty, variables, predicates} C.SelectedFunction{selected_name, selected}:
      certify_same(M.name_equal(source_name, selected_name), I.Binding{source_name, ty, variables, predicates}, selected, owner_bound)
    case _ _: False{}

type Lookup is Data:
  Missing{}
  Unique{binding: I.Binding}
  Duplicate{}

def seen(same: Bool, binding: I.Binding, found: Lookup) -> Lookup:
  match same found:
    case True{} Missing{}: Unique{binding}
    case True{} _: Duplicate{}
    case False{} prior: prior

def unique_binding(bindings: List<&2, I.Binding>, +name: String, found: Lookup) -> Lookup:
  match bindings:
    case Nil{}: found
    case +binding <> tail:
      I.Binding{+current, ty, variables, predicates} = binding
      unique_binding(tail, name, seen(M.name_equal(current, name), binding, found))

def certify_found(found: Lookup, evidence: C.Evidence, owner_bound: List<&2, Nat>) -> Bool:
  match found:
    case Unique{binding}: certify(binding, evidence, owner_bound)
    case _: False{}

# This wrapper is useful at boundaries where no caller has already proved
# that the selected name has exactly one current generalized binding.
def certify_named(name: String, evidence: C.Evidence, owner_bound: List<&2, Nat>, current: List<&2, I.Binding>) -> Bool:
  certify_found(unique_binding(current, name, Missing{}), evidence, owner_bound)
