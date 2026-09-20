import Base
import ./LAWS.bend as Laws
import ./compiler/model.bend as M
import ./compiler/lower.bend as Lower
import ./compiler/types.bend as Substitutions

def Laws.native_empty_request_fails():
  {==}

def Laws.native_trailing_words_fail(word, tail, offset):
  {==}

def Laws.empty_index_is_absent(V, name):
  {==}

def Laws.empty_index_uses_fallback(V, name, fallback):
  {==}

def Laws.constant_code_is_relocatable(key, parameter, name, captures):
  {==}

def Laws.insert_has_no_presence_requirement(storage):
  match storage:
    case M.Component{}:
      {==}
    case M.Resource{}:
      {==}

def Laws.resource_has_no_presence_requirement(access):
  match access:
    case M.Read{}:
      {==}
    case M.Write{}:
      {==}
    case M.Insert{}:
      {==}

def Laws.component_reads_require_presence():
  {==}

def Laws.component_writes_require_presence():
  {==}

def Laws.reads_do_not_write():
  {==}

def Laws.insertion_is_a_write():
  {==}

def Laws.pure_system_registers_nothing():
  {==}

def Laws.insertion_registers_storage(identity, storage):
  match identity:
    case M.TypeId{module_name, declaration}:
      {==}

def and_false(value: Bool) -> {Bool.and(value, False{}) == False{} : Bool}:
  match value:
    case False{}:
      {==}
    case True{}:
      {==}

def Laws.reads_never_conflict(left, right):
  M.Descriptor{left_id, left_storage} = left
  M.Descriptor{right_id, right_storage} = right
  and_false(M.type_id_equal(left_id, right_id))

def Laws.zero_const_budget_fails(expression, context):
  {==}

def Laws.const_reads_are_rejected(identity, remaining, context):
  {==}

def Laws.insertion_changes_structure():
  {==}

def Laws.reads_preserve_structure():
  {==}

def Laws.writes_preserve_structure():
  {==}

def Laws.empty_schedule_has_no_batches():
  {==}

def Laws.let_accepts_a_pure_rhs(subject):
  {==}

def Laws.let_rejects_any_runtime_effect(effect, rest, subject):
  {==}

def Laws.discard_preserves_source_scope(context, internal_name):
  match context:
    case Lower.Context{globals, headers, fixities, locals, return_label}:
      {==}

def Laws.block_return_skips_the_tail(value, next, context):
  {==}

def Laws.declared_storage_retains_data_type(identity, constructors):
  {==}

def Laws.empty_substitutions_preserve_type(ty, fuel):
  match ty fuel:
    case _ 0n:
      {==}
    case M.UnitTy{} 1n+rest:
      {==}
    case M.U32Ty{} 1n+rest:
      {==}
    case M.BoolTy{} 1n+rest:
      {==}
    case M.NeverTy{} 1n+rest:
      {==}
    case M.NominalTy{identity} 1n+rest:
      {==}
    case M.AppliedTy{identity, arguments} 1n+rest:
      {==}
    case M.FunctionTy{parameter, result} 1n+rest:
      {==}
    case M.ParameterTy{index} 1n+rest:
      {==}
    case M.VariableTy{index} 1n+rest:
      {==}

def Laws.final_substitution_does_not_rewrite_its_replacement(replacement, fuel):
  Laws.empty_substitutions_preserve_type(replacement, 1n+fuel)

def Laws.substitutions_preserve_u32(substitutions, fuel):
  match substitutions:
    case Nil{}:
      {==}
    case Substitutions.Substitution{variable, replacement} <> tail:
      {==}
