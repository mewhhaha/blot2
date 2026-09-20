import Base
import ./compiler/model.bend as M
import ./compiler/effects.bend as Effects
import ./compiler/const_eval.bend as Const
import ./compiler/schedule.bend as Schedule
import ./compiler/check.bend as Check
import ./compiler/lower.bend as Lower
import ./compiler/type_data.bend as Types
import ./compiler/types.bend as Substitutions
import ./compiler/wasm.bend as Wasm
import ./compiler/codegen_ir.bend as Codegen
import ./compiler/index.bend as Index
import ./compiler/native_request.bend as NativeRequest

# The native boundary must not interpret incomplete or extended payloads.
law native_empty_request_fails:
  {Result.is_done(&2, &2, M.Diagnostic, NativeRequest.Request, NativeRequest.decode(Nil{})) == False{} : Bool}

law native_trailing_words_fail:
  for word: U32
  for tail: List<&2, U32>
  for offset: Nat
  {Result.is_done(&2, &2, M.Diagnostic, Unit, NativeRequest.end(NativeRequest.Cursor{word <> tail, offset})) == False{} : Bool}

# Metadata reads never invent entries in an empty index.
law empty_index_is_absent:
  for -V: Data
  for name: String
  {Index.find(V, MTip{}, name) == None{} : Maybe<&2, V>}

law empty_index_uses_fallback:
  for -V: Data
  for name: String
  for +fallback: V
  {Index.get(V, MTip{}, name, fallback) == fallback : V}

# Inserting storage must never filter out the entities that need inserting.
law insert_has_no_presence_requirement:
  for storage: M.Storage
  {Effects.requires_entity(M.Insert{}, storage) == False{} : Bool}

# Resources belong to the world, not to each matched entity.
law resource_has_no_presence_requirement:
  for access: M.Access
  {Effects.requires_entity(access, M.Resource{}) == False{} : Bool}

law component_reads_require_presence:
  {Effects.requires_entity(M.Read{}, M.Component{}) == True{} : Bool}

law component_writes_require_presence:
  {Effects.requires_entity(M.Write{}, M.Component{}) == True{} : Bool}

law reads_do_not_write:
  {Effects.is_write(M.Read{}) == False{} : Bool}

law insertion_is_a_write:
  {Effects.is_write(M.Insert{}) == True{} : Bool}

law pure_system_registers_nothing:
  {Effects.registrations(Nil{}) == Nil{} : List<&2, M.Descriptor>}

law insertion_registers_storage:
  for identity: M.TypeId
  for storage: M.Storage
  {Effects.registrations([M.Effect{M.Insert{}, M.Descriptor{identity, storage}}]) == [M.Descriptor{identity, storage}] : List<&2, M.Descriptor>}

law reads_never_conflict:
  for left: M.Descriptor
  for right: M.Descriptor
  {Effects.conflicts(M.Effect{M.Read{}, left}, M.Effect{M.Read{}, right}) == False{} : Bool}

law zero_const_budget_fails:
  for expression: M.Expr
  for context: Const.Context
  {Result.is_done(&2, &2, M.Diagnostic, Const.Evaluation, Const.evaluate(0n, 0n, expression, context)) == False{} : Bool}

law const_reads_are_rejected:
  for identity: M.TypeId
  for remaining: Nat
  for context: Const.Context
  {Result.is_done(&2, &2, M.Diagnostic, Const.Evaluation, Const.evaluate(1n, 1n+remaining, M.ReadExpr{identity}, context)) == False{} : Bool}

law insertion_changes_structure:
  {Schedule.structural(M.Insert{}) == True{} : Bool}

law reads_preserve_structure:
  {Schedule.structural(M.Read{}) == False{} : Bool}

law writes_preserve_structure:
  {Schedule.structural(M.Write{}) == False{} : Bool}

law empty_schedule_has_no_batches:
  {Schedule.batches(Nil{}) == Nil{} : List<&2, List<&2, String>>}

law let_accepts_a_pure_rhs:
  for subject: String
  {Result.is_done(&2, &2, M.Diagnostic, Unit, Check.require_let_pure(Nil{}, subject)) == True{} : Bool}

law let_rejects_any_runtime_effect:
  for effect: M.Effect
  for rest: List<&2, M.Effect>
  for subject: String
  {Result.is_done(&2, &2, M.Diagnostic, Unit, Check.require_let_pure(effect <> rest, subject)) == False{} : Bool}

law discard_preserves_source_scope:
  for context: Lower.Context
  for internal_name: String
  {Lower.bind(context, Lower.Local{"_", internal_name}) == context : Lower.Context}

# Explicit block exits do not evaluate (or charge) an unreachable continuation.
law block_return_skips_the_tail:
  for value: U32
  for next: M.Expr
  for context: Const.Context
  {Const.evaluate(4n, 4n, M.BlockExpr{0n, M.SequenceExpr{M.ReturnExpr{0n, M.U32Expr{value}}, next}}, context) == Done{Const.Evaluation{Const.U32Value{value}, 0n}} : Result<&2, &2, M.Diagnostic, Const.Evaluation>}

# Storage reads and source constructors must inhabit the same declared type.
law declared_storage_retains_data_type:
  for +identity: M.TypeId
  for constructors: List<&2, M.Constructor>
  {Types.storage_type(Some{M.DataType{identity, 0n, constructors}}, identity) == Done{M.AppliedTy{identity, Nil{}}} : Result<&2, &2, M.Diagnostic, M.Ty>}

law empty_substitutions_preserve_type:
  for +ty: M.Ty
  for fuel: Nat
  {Substitutions.resolve_work(Nil{}, fuel, Substitutions.OneType{ty}) == Done{[ty]} : Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>}

# A sequential substitution does not apply itself inside the inserted type.
law final_substitution_does_not_rewrite_its_replacement:
  for +replacement: M.Ty
  for fuel: Nat
  {Substitutions.resolve_work([Substitutions.Substitution{0n, replacement}], 1n+fuel, Substitutions.OneType{M.VariableTy{0n}}) == Done{[replacement]} : Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>}

law substitutions_preserve_u32:
  for substitutions: List<&2, Substitutions.Substitution>
  for fuel: Nat
  {Substitutions.resolve_work(substitutions, 1n+fuel, Substitutions.OneType{M.U32Ty{}}) == Done{[M.U32Ty{}]} : Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>}

# Cached code refers to constants symbolically, never to their current values.
law constant_code_is_relocatable:
  for +key: String
  for parameter: String
  for +name: String
  for captures: List<&2, String>
  {Wasm.compile_entry(Wasm.CodegenJob{key, parameter, Codegen.ConstantExpr{name}, captures}) == Done{Wasm.EntryCode{key, Wasm.Code{[Wasm.ConstantReference{name}], 0n}}} : Result<&2, &2, M.Diagnostic, Wasm.EntryCode>}
