import Base
import ./compiler/model.bend as M
import ./compiler/effects.bend as Effects
import ./compiler/const_eval.bend as Const
import ./compiler/check.bend as Check
import ./compiler/lower.bend as Lower
import ./compiler/types.bend as Substitutions
import ./compiler/wasm.bend as Wasm
import ./compiler/codegen_ir.bend as Codegen
import ./compiler/index.bend as Index
import ./compiler/native_request.bend as NativeRequest
import ./compiler/native_io.bend as NativeIO
import ./compiler/native_response.bend as NativeResponse
import ./compiler/native_cache_keys.bend as NativeKeys
import ./compiler/type_data.bend as TypeData
import ./compiler/patterns.bend as Patterns
import ./compiler/closures.bend as Closures
import ./compiler/check_scheduler.bend as Scheduler
import ./compiler/cst.bend as Cst
import ./compiler/native_session.bend as Session
import ./compiler/dependency.bend as Dependency
import ./compiler/runtime_reachable.bend as Reachable

# Parallel compilation keeps source-order diagnostics and a sequential leaf
# below the scheduling grain. Neither rule depends on worker completion order.
law lowering_join_preserves_tail_error:
  for earlier: Result<&2, &2, M.Diagnostic, M.Module>
  for +error: M.Diagnostic
  {Lower.merge_declarations(earlier, Fail{error}) == Fail{error} : Result<&2, &2, M.Diagnostic, M.Module>}

law lowering_small_batches_are_sequential:
  for +nodes: List<&2, Cst.Cst>
  for count: Nat
  {Lower.declaration_batches(48n, nodes, count, True{}) == Lower.DeclarationLeaf{nodes} : Lower.DeclarationBatch}

law lowering_cost_stops_at_its_bound:
  for nodes: List<&2, Cst.Cst>
  for +cost: Nat
  {Lower.declaration_cost(0n, nodes, cost) == cost : Nat}

law lowering_heavy_first_declaration_never_makes_an_empty_half:
  for +node: Cst.Cst
  {Lower.declaration_boundary([Lower.WeightedDeclaration{node, 100n}, Lower.WeightedDeclaration{node, 1n}, Lower.WeightedDeclaration{node, 1n}, Lower.WeightedDeclaration{node, 1n}, Lower.WeightedDeclaration{node, 1n}], 52n, 0n, 0n, False{}) == 1n : Nat}

law session_lowering_join_preserves_first_error:
  for +error: M.Diagnostic
  for later: Result<&2, &2, M.Diagnostic, List<&2, Session.Lowered>>
  {Session.merge_lowered(Fail{error}, later) == Fail{error} : Result<&2, &2, M.Diagnostic, List<&2, Session.Lowered>>}

law native_empty_string_preserves_cursor:
  for words: Array<U32>
  for +offset: Nat
  for +remaining: Nat
  {NativeRequest.scan_string(0n, NativeRequest.Cursor{words, offset, remaining, [SNil{} : String*1n], 0}, SNil{}, True{}) == NativeRequest.CompleteString{SNil{}, NativeRequest.Cursor{words, offset, remaining, [SNil{} : String*1n], 0}} : NativeRequest.ScannedString}

law native_zero_nat_consumes_exactly_two_words:
  {NativeRequest.natural(NativeRequest.Cursor{[0 : U32*2n], 0n, 2n, [SNil{} : String*1n], 0}, "fuel") == Done{NativeRequest.Parsed{0n, NativeRequest.Cursor{[0 : U32*2n], 2n, 0n, [SNil{} : String*1n], 0}}} : Result<&2, &1, NativeRequest.ScanFailure, NativeRequest.Parsed<Nat>>}

law native_string_rejects_surrogate_at_its_offset:
  {NativeRequest.scan_string(1n, NativeRequest.Cursor{[55296 : U32*8n], 7n, 1n, [SNil{} : String*1n], 0}, SNil{}, True{}) == NativeRequest.InvalidCharacter{7n} : NativeRequest.ScannedString}

law native_exhausted_buffer_never_wraps:
  for words: Array<U32>
  for offset: Nat
  {Result.is_done(&2, &1, NativeRequest.ScanFailure, NativeRequest.Parsed<U32>, NativeRequest.word(NativeRequest.Cursor{words, offset, 0n, [SNil{} : String*1n], 0}, "word")) == False{} : Bool}

law native_empty_dictionary_rejects_zero_id:
  {Result.is_done(&2, &1, NativeRequest.ScanFailure, NativeRequest.Parsed<String>, NativeRequest.string_reference(NativeRequest.Cursor{[0 : U32*1n], 0n, 1n, [SNil{} : String*1n], 0}, "ID")) == False{} : Bool}

law dependency_siblings_keep_their_depth_budget:
  {Dependency.references(2n, Dependency.Expression{M.ApplyExpr{M.FunctionExpr{"left"}, M.ConstantExpr{"right"}}}) == Done{Dependency.References{["left", "right"], Nil{}}} : Result<&2, &2, M.Diagnostic, Dependency.References>}

law reachability_counts_the_empty_children_step:
  for catalog: Reachable.Catalog
  for state: Reachable.State
  {Result.is_done(&2, &2, M.Diagnostic, Reachable.State, Reachable.walk(1n, [Reachable.ExpressionWork{M.UnitExpr{}}], catalog, state)) == False{} : Bool}

law reachability_leaf_spends_two_steps:
  for catalog: Reachable.Catalog
  for +state: Reachable.State
  {Reachable.walk(2n, [Reachable.ExpressionWork{M.UnitExpr{}}], catalog, state) == Done{state} : Result<&2, &2, M.Diagnostic, Reachable.State>}

law codegen_join_preserves_first_error:
  for +error: M.Diagnostic
  for later: Result<&2, &2, M.Diagnostic, List<&2, Wasm.EntryCode>>
  {Wasm.merge_entries(Fail{error}, later) == Fail{error} : Result<&2, &2, M.Diagnostic, List<&2, Wasm.EntryCode>>}

law preparation_join_preserves_first_error:
  for +error: M.Diagnostic
  for later: Result<&2, &2, M.Diagnostic, List<&2, Wasm.CodegenJob>>
  {Wasm.merge_prepared(Fail{error}, later) == Fail{error} : Result<&2, &2, M.Diagnostic, List<&2, Wasm.CodegenJob>>}

law codegen_small_batches_are_sequential:
  for +entries: List<&2, Wasm.WeightedEntry<Wasm.CodegenJob>>
  for weight: Nat
  for grain: Nat
  {Wasm.partition_entries(Wasm.CodegenJob, False{}, Wasm.EntryWorkload{entries, weight}, grain) == Wasm.EntryLeaf{entries} : Wasm.EntryPartition<Wasm.CodegenJob>}

law inference_empty_schedule_has_no_work:
  {Scheduler.schedule(Nil{}) == Done{Nil{}} : Result<&2, &2, M.Diagnostic, List<&2, Scheduler.Scheduled>>}

law inference_keeps_the_earlier_failure:
  for +first: M.Diagnostic
  for later: M.Diagnostic
  {Scheduler.first_failure(Some{Scheduler.Failure{0n, first}}, Scheduler.Failure{1n, later}) == Some{Scheduler.Failure{0n, first}} : Maybe<&2, Scheduler.Failure>}

law inference_without_failure_keeps_pending_work:
  for position: Nat
  {Scheduler.precedes_failure(position, None{}) == True{} : Bool}

# Foreign records a call through supplied authority; it is not a declaration or
# an operation a source provider can manufacture or discharge.
law foreign_is_a_valid_effect_label:
  {TypeData.valid_effect_label(Nil{}, M.foreign_identity()) == Done{Unit{}} : Result<&2, &2, M.Diagnostic, Unit>}

law foreign_cannot_be_declared:
  {Result.is_done(&2, &2, M.Diagnostic, Unit, TypeData.valid_operation_identity(M.foreign_identity())) == False{} : Bool}

law foreign_cannot_be_supplied_as_an_operation:
  {Result.is_done(&2, &2, M.Diagnostic, M.Operation, TypeData.require_operation(Some{M.Operation{M.foreign_identity(), M.U32Ty{}, M.U32Ty{}}}, M.foreign_identity())) == False{} : Bool}

law foreign_is_not_a_same_named_source_effect:
  {M.is_foreign(M.TypeId{"source", "Foreign"}) == False{} : Bool}

# A failed key encoding must never become a successful, colliding cache key.
law native_key_requires_traversal_fuel:
  {Result.is_done(&2, &2, M.Diagnostic, List<&2, U32>, NativeKeys.encode_limited(0n, [NativeKeys.Field{NativeResponse.Word{1}}], 1n)) == False{} : Bool}

law native_key_requires_output_room:
  {Result.is_done(&2, &2, M.Diagnostic, List<&2, U32>, NativeKeys.encode_limited(2n, [NativeKeys.Field{NativeResponse.Word{1}}], 0n)) == False{} : Bool}

def encoded_keys_differ(left: Result<&2, &2, M.Diagnostic, List<&2, U32>>, right: Result<&2, &2, M.Diagnostic, List<&2, U32>>) -> Bool:
  match left right:
    case Done{a} Done{b}:
      Bool.not(NativeKeys.same(a, b))
    case _ _:
      False{}

def native_keys_differ(left: NativeKeys.Work, right: NativeKeys.Work) -> Bool:
  encoded_keys_differ(NativeKeys.encode_limited(128n, [left], 256n), NativeKeys.encode_limited(128n, [right], 256n))

def operation_global_key(kind: Lower.GlobalKind) -> NativeKeys.Work:
  NativeKeys.Globals{[Lower.Global{"Reader.ask", "same", kind}]}

def matching_key(values: List<&2, Codegen.Expr>, patterns: List<&2, M.Pattern>) -> NativeKeys.Work:
  NativeKeys.Runtime{Codegen.MatchExpr{values, [M.MatchArm{patterns, Codegen.UnitExpr{}}]}}

law native_runtime_keys_preserve_nominal_identity:
  {Bool.and(
    native_keys_differ(NativeKeys.Runtime{Codegen.ProviderExpr{M.TypeId{"a::b", "c"}, Codegen.UnitExpr{}}}, NativeKeys.Runtime{Codegen.ProviderExpr{M.TypeId{"a", "b::c"}, Codegen.UnitExpr{}}}),
    native_keys_differ(NativeKeys.Runtime{Codegen.InvokeOperationExpr{M.TypeId{"𐐀", "é"}, Codegen.UnitExpr{}}}, NativeKeys.Runtime{Codegen.InvokeOperationExpr{M.TypeId{"𐐀", "é"}, Codegen.UnitExpr{}}})) == True{} : Bool}

law native_runtime_keys_preserve_operation_forms:
  {Bool.and(
    native_keys_differ(NativeKeys.Runtime{Codegen.ProviderExpr{M.TypeId{"m", "ask"}, Codegen.UnitExpr{}}}, NativeKeys.Runtime{Codegen.InvokeOperationExpr{M.TypeId{"m", "ask"}, Codegen.UnitExpr{}}}),
    native_keys_differ(NativeKeys.Runtime{Codegen.HandleExpr{Codegen.UnitExpr{}, Codegen.U32Expr{1}}}, NativeKeys.Runtime{Codegen.HandleExpr{Codegen.U32Expr{1}, Codegen.UnitExpr{}}})) == True{} : Bool}

law native_operation_globals_preserve_kind_and_identity:
  {Bool.and(
    native_keys_differ(operation_global_key(Lower.OperationName{M.TypeId{"a::b", "c"}}), operation_global_key(Lower.OperationName{M.TypeId{"a", "b::c"}})),
    Bool.and(native_keys_differ(operation_global_key(Lower.OperationName{M.TypeId{"a::b", "c"}}), operation_global_key(Lower.FunctionName{})), native_keys_differ(operation_global_key(Lower.OperationName{M.TypeId{"a::b", "c"}}), operation_global_key(Lower.ConstantName{})))) == True{} : Bool}

law native_matching_keys_preserve_columns:
  {Bool.and(
    native_keys_differ(matching_key([Codegen.UnitExpr{}, Codegen.U32Expr{1}], [M.BindingPattern{"value"}, M.WildcardPattern{}]), matching_key([Codegen.U32Expr{1}, Codegen.UnitExpr{}], [M.BindingPattern{"value"}, M.WildcardPattern{}])),
    Bool.and(native_keys_differ(matching_key([Codegen.UnitExpr{}, Codegen.U32Expr{1}], [M.BindingPattern{"value"}, M.WildcardPattern{}]), matching_key([Codegen.UnitExpr{}, Codegen.U32Expr{1}], [M.WildcardPattern{}, M.BindingPattern{"value"}])), native_keys_differ(matching_key([Codegen.UnitExpr{}, Codegen.U32Expr{1}], [M.BindingPattern{"value"}, M.WildcardPattern{}]), matching_key([Codegen.UnitExpr{}], [M.BindingPattern{"value"}, M.WildcardPattern{}])))) == True{} : Bool}

law native_runtime_key_zero_fuel_reports_complexity:
  {NativeKeys.encode_limited(0n, [NativeKeys.Runtime{Codegen.ProviderExpr{M.TypeId{"m", "ask"}, Codegen.UnitExpr{}}}], 256n) == Fail{M.Diagnostic{"cache_key_complexity", "native_session", "cache key traversal exceeded its bound"}} : Result<&2, &2, M.Diagnostic, List<&2, U32>>}

law native_runtime_key_zero_room_fails:
  {Result.is_done(&2, &2, M.Diagnostic, List<&2, U32>, NativeKeys.encode_limited(128n, [NativeKeys.Runtime{Codegen.ProviderExpr{M.TypeId{"m", "ask"}, Codegen.UnitExpr{}}}], 0n)) == False{} : Bool}

law f32_arithmetic_has_f32_result:
  {M.scalar_result(M.F32Add{}) == M.F32Ty{} : M.Ty}

law f32_comparison_has_bool_result:
  {M.scalar_result(M.F32LessThan{}) == M.BoolTy{} : M.Ty}

law f32_to_u32_saturates_overflow:
  for +value: F32
  for overflow: {F32.is_ge(value, 4294967296.0) == True{} : Bool}
  {Const.f32_to_u32_saturating(value) == 4294967295 : U32}

# The native boundary must not interpret incomplete or extended payloads.
law native_empty_request_fails:
  {Result.is_done(&2, &2, M.Diagnostic, NativeRequest.Request, NativeRequest.decode(NativeIO.Frame{[0 : U32*1n], 0})) == False{} : Bool}

law native_trailing_words_fail:
  for words: Array<U32>
  for remaining: Nat
  for offset: Nat
  {Result.is_done(&2, &1, NativeRequest.ScanFailure, Unit, NativeRequest.end(NativeRequest.Cursor{words, offset, 1n+remaining, [SNil{} : String*1n], 0})) == False{} : Bool}

law native_response_failure_keeps_protocol_version:
  {List.take(&2, U32, NativeResponse.finish(Fail{M.Diagnostic{"native_protocol", "native_response", "response exceeds 16M words"}}), 3n) == [1112297300, 7, 0] : List<&2, U32>}

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

law pure_effect_metadata_is_empty:
  {Effects.canonical(Nil{}) == Nil{} : List<&2, M.Effect>}

law zero_const_budget_fails:
  for expression: M.Expr
  for context: Const.Context
  {Result.is_done(&2, &2, M.Diagnostic, Const.Evaluation, Const.evaluate(0n, 0n, expression, context)) == False{} : Bool}

law unhandled_const_operations_fail:
  for identity: M.TypeId
  for argument: Const.Value
  for context: Const.Context
  {Result.is_done(&2, &2, M.Diagnostic, Const.Application, Const.resolve_application(Nil{}, Const.OperationApplication{identity, argument}, context)) == False{} : Bool}

# Binding a closure's lexical values does not replace the caller's providers.
law closure_bindings_preserve_invocation_providers:
  for +context: Const.Context
  for environment: List<&2, Const.Binding<Const.Value>>
  {Const.context_providers(Const.with_locals(context, environment)) == Const.context_providers(context) : List<&2, Const.Provider<Const.Value>>}

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

# Matching evaluates each column only if preceding columns complete normally.
law match_return_skips_remaining_scrutinees:
  for value: U32
  for next: M.Expr
  for context: Const.Context
  {Const.evaluate(4n, 4n, M.BlockExpr{0n, M.MatchExpr{[M.ReturnExpr{0n, M.U32Expr{value}}, next], Nil{}}}, context) == Done{Const.Evaluation{Const.U32Value{value}, 0n}} : Result<&2, &2, M.Diagnostic, Const.Evaluation>}

law product_projection_selects_first:
  for first: Const.Value
  for second: Const.Value
  for steps: Nat
  {Const.project(Const.ProductValue{[first, second]}, 0n, steps) == Done{Const.Evaluation{first, steps}} : Result<&2, &2, M.Diagnostic, Const.Evaluation>}

law product_projection_selects_second:
  for first: Const.Value
  for second: Const.Value
  for steps: Nat
  {Const.project(Const.ProductValue{[first, second]}, 1n, steps) == Done{Const.Evaluation{second, steps}} : Result<&2, &2, M.Diagnostic, Const.Evaluation>}

law product_projection_rejects_length_index:
  for elements: List<&2, Const.Value>
  for steps: Nat
  {Result.is_done(&2, &2, M.Diagnostic, Const.Evaluation, Const.project(Const.ProductValue{elements}, List.length(&2, Const.Value, elements), steps)) == False{} : Bool}

law product_retains_mixed_fields:
  for number: U32
  for flag: Bool
  for context: Const.Context
  {Const.evaluate(3n, 3n, M.ProductExpr{[M.U32Expr{number}, M.BoolExpr{flag}]}, context) == Done{Const.Evaluation{Const.ProductValue{[Const.U32Value{number}, Const.BoolValue{flag}]}, 0n}} : Result<&2, &2, M.Diagnostic, Const.Evaluation>}

law product_return_skips_remaining_elements:
  for value: U32
  for next: M.Expr
  for context: Const.Context
  {Const.evaluate(4n, 4n, M.BlockExpr{0n, M.ProductExpr{[M.ReturnExpr{0n, M.U32Expr{value}}, next]}}, context) == Done{Const.Evaluation{Const.U32Value{value}, 0n}} : Result<&2, &2, M.Diagnostic, Const.Evaluation>}

law empty_array_length_is_zero:
  for steps: Nat
  {Const.array_length(Const.ArrayValue{Nil{}}, steps) == Done{Const.Evaluation{Const.U32Value{0}, steps}} : Result<&2, &2, M.Diagnostic, Const.Evaluation>}

law array_read_selects_first:
  for first: Const.Value
  for tail: List<&2, Const.Value>
  for steps: Nat
  {Const.array_get(Const.ArrayValue{first <> tail}, Const.U32Value{0}, steps) == Done{Const.Evaluation{first, steps}} : Result<&2, &2, M.Diagnostic, Const.Evaluation>}

law array_read_rejects_length_index:
  for elements: List<&2, Const.Value>
  for steps: Nat
  {Result.is_done(&2, &2, M.Diagnostic, Const.Evaluation, Const.array_get_elements(elements, List.length(&2, Const.Value, elements), steps)) == False{} : Bool}

law array_set_preserves_other_elements:
  for first: Const.Value
  for second: Const.Value
  for replacement: Const.Value
  {Const.array_set(Const.ArrayValue{[first, second]}, Const.U32Value{0}, replacement, 2n) == Done{Const.Evaluation{Const.ArrayValue{[replacement, second]}, 0n}} : Result<&2, &2, M.Diagnostic, Const.Evaluation>}

law array_copy_requires_per_element_budget:
  for first: Const.Value
  for second: Const.Value
  for replacement: Const.Value
  {Result.is_done(&2, &2, M.Diagnostic, Const.Evaluation, Const.array_set(Const.ArrayValue{[first, second]}, Const.U32Value{0}, replacement, 1n)) == False{} : Bool}

law array_return_skips_remaining_elements:
  for value: U32
  for next: M.Expr
  for context: Const.Context
  {Const.evaluate(4n, 4n, M.BlockExpr{0n, M.ArrayExpr{[M.ReturnExpr{0n, M.U32Expr{value}}, next]}}, context) == Done{Const.Evaluation{Const.U32Value{value}, 0n}} : Result<&2, &2, M.Diagnostic, Const.Evaluation>}

law tuple_pattern_binds_fields_in_order:
  for first: Const.Value
  for second: Const.Value
  {Const.match_pattern_work(16n, Const.PatternValue{M.ProductPattern{[M.BindingPattern{"first"}, M.BindingPattern{"second"}]}, Const.ProductValue{[first, second]}}) == Done{Some{[Const.Binding{"first", first}, Const.Binding{"second", second}]}} : Result<&2, &2, M.Diagnostic, Maybe<&2, List<&2, Const.Binding<Const.Value>>>>}

law tuple_pattern_failure_discards_all_bindings:
  for first: Const.Value
  {Const.match_pattern_work(16n, Const.PatternValue{M.ProductPattern{[M.BindingPattern{"first"}, M.BoolPattern{True{}}]}, Const.ProductValue{[first, Const.BoolValue{False{}}]}}) == Done{None{}} : Result<&2, &2, M.Diagnostic, Maybe<&2, List<&2, Const.Binding<Const.Value>>>>}

law tuple_pattern_mismatch_skips_pending_fields:
  for next: M.Pattern
  for value: Const.Value
  {Const.match_pattern_work(3n, Const.PatternValue{M.ProductPattern{[M.U32Pattern{1}, next]}, Const.ProductValue{[Const.U32Value{0}, value]}}) == Done{None{}} : Result<&2, &2, M.Diagnostic, Maybe<&2, List<&2, Const.Binding<Const.Value>>>>}

law tuple_pattern_budget_bounds_total_work:
  {Const.match_pattern_work(5n, Const.PatternValue{M.ProductPattern{[M.WildcardPattern{}, M.WildcardPattern{}]}, Const.ProductValue{[Const.UnitValue{}, Const.UnitValue{}]}}) == Fail{M.Diagnostic{"pattern_complexity", "const", "constant pattern matching exceeds compiler traversal limit"}} : Result<&2, &2, M.Diagnostic, Maybe<&2, List<&2, Const.Binding<Const.Value>>>>}

law tuple_pattern_requires_exact_arity:
  for first: Const.Value
  for second: Const.Value
  for third: Const.Value
  {Const.match_pattern_work(16n, Const.PatternValue{M.ProductPattern{[M.WildcardPattern{}, M.WildcardPattern{}]}, Const.ProductValue{[first, second, third]}}) == Done{None{}} : Result<&2, &2, M.Diagnostic, Maybe<&2, List<&2, Const.Binding<Const.Value>>>>}

law pattern_traversal_exhaustion_is_not_a_failed_match:
  for work: Const.PatternWork
  {Const.match_pattern_work(0n, work) == Fail{M.Diagnostic{"pattern_complexity", "const", "constant pattern matching exceeds compiler traversal limit"}} : Result<&2, &2, M.Diagnostic, Maybe<&2, List<&2, Const.Binding<Const.Value>>>>}

law tuple_coverage_preserves_correlations:
  {Patterns.coverage(32n, Patterns.Cover{[M.ProductTy{[M.BoolTy{}, M.BoolTy{}]}], [[M.ProductPattern{[M.BoolPattern{True{}}, M.BoolPattern{True{}}]}], [M.ProductPattern{[M.BoolPattern{False{}}, M.BoolPattern{False{}}]}]]}, Nil{}) == Done{False{}} : Result<&2, &2, M.Diagnostic, Bool>}

law tuple_capture_names_follow_nested_field_order:
  for first: String
  for second: String
  {Closures.pattern_names(M.ProductPattern{[M.BindingPattern{first}, M.ConstructorPattern{"Some", Some{M.ProductPattern{[M.BindingPattern{second}, M.WildcardPattern{}]}}}]}) == Done{[first, second]} : Result<&2, &2, M.Diagnostic, List<&2, String>>}

law record_fields_keep_written_evaluation_order:
  for first: M.Expr
  for second: M.Expr
  for body: M.Expr
  {Lower.record_bindings([Lower.RecordElement{"y", "second", second}, Lower.RecordElement{"x", "first", first}], body) == M.UseExpr{"first", first, M.UseExpr{"second", second, body}} : M.Expr}

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

# The linker must not confuse distinct nominal operations at module separators.
law operation_keys_preserve_nominal_boundaries:
  {M.name_equal(Codegen.operation_key(M.TypeId{"a::b", "c"}), Codegen.operation_key(M.TypeId{"a", "b::c"})) == False{} : Bool}
