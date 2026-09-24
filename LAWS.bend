import Base
import ./compiler/schema_stage.bend as Schema
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
import ./compiler/native_output.bend as NativeOutput
import ./compiler/native_cache_keys.bend as NativeKeys
import ./compiler/type_data.bend as TypeData
import ./compiler/patterns.bend as Patterns
import ./compiler/closures.bend as Closures
import ./compiler/check_scheduler.bend as Scheduler
import ./compiler/check_chain_plan.bend as Chains
import ./compiler/check_regions.bend as Regions
import ./compiler/groups.bend as Groups
import ./compiler/cst.bend as Cst
import ./compiler/native_session.bend as Session
import ./compiler/native_plan.bend as NativePlan
import ./compiler/dependency.bend as Dependency
import ./compiler/runtime_reachable.bend as Reachable
import ./compiler/source_modules.bend as SourceModules
import ./compiler/monomorph.bend as Mono
import ./compiler/infer.bend as Infer
import ./compiler/array_reuse.bend as Reuse
import ./compiler/public_exports.bend as Public
import ./compiler/core_compare.bend as CoreCompare
import ./compiler/checked_core.bend as CheckedCore
import ./compiler/nat_index.bend as NatIndex
import ./compiler/frontier_alpha_compare.bend as FrontierAlpha
import ./compiler/global_bindings.bend as GlobalBindings
import ./compiler/globals.bend as Globals
import ./compiler/state_specialize.bend as StateSpecialize
import ./compiler/parallel_infer.bend as ParallelInfer
import ./compiler/staging_scheme.bend as StagingScheme

# An exported function-valued constant is called through its stored value.
# Selecting exports after inference must never duplicate its initializer.
law checked_public_wrapper_calls_stored_constant:
  for +name: String
  for +input: M.Ty
  for +output: M.Ty
  for variables: List<&2, Nat>
  for row: M.EffectRow
  {Public.unchecked_functions([Public.checked_wrapper(name, input, output, variables, row)]) == [M.Function{"$public:" ++ name, True{}, "$argument", Some{input}, Some{output}, M.ApplyExpr{M.ConstantExpr{name}, M.LocalExpr{"$argument"}}}] : List<&2, M.Function>}

# Membership stops after a hit. The remaining scan is a thunk so an eager
# backend does not evaluate a recursive Boolean argument before selecting it.
law dependency_membership_hit_finishes:
  for remaining: Unit -> Bool
  {Dependency.contains_step(True{}, remaining) == True{} : Bool}

# Once a specialization lookup finds its first binding, later bindings cannot
# change the result, including a duplicate of the same name.
law mono_rename_keeps_first_found:
  for tail: List<&2, Mono.Rename>
  for wanted: String
  for specialized: String
  {Mono.renamed_work(tail, wanted, Some{specialized}) == Some{specialized} : Maybe<&2, String>}

law mono_function_keeps_first_found:
  for tail: List<&2, M.Function>
  for wanted: String
  for function: M.Function
  {Mono.lookup_work(tail, wanted, Some{function}) == Done{function} : Result<&2, &2, M.Diagnostic, M.Function>}

law mono_constant_keeps_first_found:
  for tail: List<&2, M.Constant>
  for wanted: String
  for constant: M.Constant
  {Mono.lookup_constant_work(tail, wanted, Some{constant}) == Some{constant} : Maybe<&2, M.Constant>}

law mono_local_template_keeps_first_found:
  for tail: List<&2, Mono.LocalTemplate>
  for wanted: String
  for value: M.Expr
  {Mono.local_template_work(tail, wanted, Some{value}) == Some{value} : Maybe<&2, M.Expr>}

law mono_effect_family_keeps_first_found:
  for tail: List<&2, M.Operation>
  for wanted: M.TypeId
  for declaration: M.Operation
  {Mono.family_declaration_work(tail, wanted, Some{declaration}) == Done{declaration} : Result<&2, &2, M.Diagnostic, M.Operation>}

# Parallel compilation keeps source-order diagnostics and a sequential leaf
# below the scheduling grain. Neither rule depends on worker completion order.
law cached_scan_preserves_first_failure:
  for +error: M.Diagnostic
  for following: Result<&2, &2, M.Diagnostic, List<&2, Dependency.Node>>
  {NativePlan.append_nodes(Fail{error}, following) == Fail{error} : Result<&2, &2, M.Diagnostic, List<&2, Dependency.Node>>}

law blocked_single_group_preserves_progress:
  for scheduled: Scheduler.Scheduled
  for known: Session.CheckCatalog
  for previous: Map<&2, Session.Cached<Groups.CheckedGroup>>
  for +progress: Session.GroupProgress
  {Session.check_single_group(scheduled, known, previous, progress, False{}) == progress : Session.GroupProgress}

law cached_group_cost_skips_body_traversal:
  for +cost: Nat
  for known: Scheduler.Catalog
  for job: Groups.Job
  {Scheduler.group_cost_found(Some{cost}, known, job) == cost : Nat}

law small_frontier_skips_pipeline_cost_traversal:
  for ready: List<&2, Scheduler.Scheduled>
  for known: Session.CheckCatalog
  {Session.staged_frontier(ready, known, True{}) == True{} : Bool}

law inference_union_same_root_preserves_forest:
  for left: String
  for left_rank: Nat
  for right: String
  for right_rank: Nat
  for +forest: Map<&2, Regions.Link>
  for order: Cmp
  {Regions.join_roots(left, left_rank, right, right_rank, forest, True{}, order) == forest : Map<&2, Regions.Link>}

law session_key_failure_preserves_earlier_misses:
  for jobs: List<&2, Session.KeyedEntry>
  for previous: Map<&2, Session.Cached<Wasm.EntryCode>>
  for +selections: List<&2, Session.EntrySelection>
  for +missing: List<&2, Wasm.CodegenJob>
  for +error: M.Diagnostic
  {Session.plan_entries(jobs, previous, Session.EntryPlan{selections, missing, Some{error}}) == Session.EntryPlan{List.reverse(&2, Session.EntrySelection, selections), List.reverse(&2, Wasm.CodegenJob, missing), Some{error}} : Session.EntryPlan}

law pipelined_codegen_keeps_first_failure:
  for +error: M.Diagnostic
  for tail: List<&2, Result<&2, &2, M.Diagnostic, Session.PreparedEntry>>
  for next: Map<&2, Session.Cached<Wasm.EntryCode>>
  for reversed: List<&2, Wasm.EntryCode>
  for counts: Session.Counts
  {Session.publish_compiled_entries(Fail{error} <> tail, next, reversed, counts) == Fail{error} : Result<&2, &2, M.Diagnostic, Session.CompiledEntries>}

law completed_dependency_does_not_join_pending_regions:
  for owner: Nat
  for fuel: Nat
  for head: String
  for name: String
  for +forest: Map<&2, Regions.Link>
  {Regions.link_dependency(None{}, Some{owner}, fuel, head, name, forest) == Done{forest} : Result<&2, &2, M.Diagnostic, Map<&2, Regions.Link>>}

law session_small_frontier_skips_cost_traversal:
  for job: Groups.Job
  for known: Session.CheckCatalog
  {Session.group_preparation_cost(job, known, True{}) == 0n : Nat}

law inference_single_frontier_keeps_its_parallel_batch:
  for +chains: List<&2, Chains.Chain>
  for ready: List<&2, Chains.Chain>
  {Regions.plan_frontier(chains, Chains.Frontier{ready, Nil{}}) == Done{[Regions.Region{chains}]} : Result<&2, &2, M.Diagnostic, List<&2, Regions.Region>>}

law inference_single_root_needs_no_partition:
  for +chains: List<&2, Chains.Chain>
  for root: Chains.Chain
  for pending: List<&2, Chains.Chain>
  {Regions.plan_frontier(chains, Chains.Frontier{[root], pending}) == Done{[Regions.Region{chains}]} : Result<&2, &2, M.Diagnostic, List<&2, Regions.Region>>}

law lowering_join_preserves_tail_error:
  for earlier: Result<&2, &2, M.Diagnostic, M.Module>
  for +error: M.Diagnostic
  {Lower.merge_declarations(earlier, Fail{error}) == Fail{error} : Result<&2, &2, M.Diagnostic, M.Module>}

law lowering_small_batches_are_sequential:
  for +nodes: List<&2, Cst.Cst>
  for count: Nat
  {Lower.declaration_batches(48n, nodes, count, True{}) == Lower.DeclarationLeaf{nodes} : Lower.DeclarationBatch}

law inference_chain_never_contracts_a_join:
  for position: Nat
  for consumers: Map<&2, Chains.Consumer>
  {Chains.continuation(Chains.SeveralParents{}, position, consumers) == None{} : Maybe<&2, Nat>}

law inference_chain_never_contracts_a_fanout:
  for position: Nat
  {Chains.sole_consumer(Some{Chains.Several{}}, position) == False{} : Bool}

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
  {List.take(&2, U32, NativeResponse.finish(Fail{M.Diagnostic{"native_protocol", "native_response", "response exceeds 16M words"}}), 3n) == [1112297300, 11, 0] : List<&2, U32>}

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

law runtime_initializers_preserve_const_budget:
  for expression: M.Expr
  for +steps: Nat
  for context: Const.Context
  {Const.evaluate_constants([M.CheckedConstant{M.Constant{"runtime", False{}, None{}, M.RuntimeInitExpr{expression}}, M.U32Ty{}, Nil{}}], steps, context) == Done{Const.Constants{Nil{}, steps}} : Result<&2, &2, M.Diagnostic, Const.Constants>}

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
  {Const.evaluate(4n, 4n, M.BlockExpr{0n, M.SequenceExpr{M.ReturnExpr{0n, M.U32Expr{value}}, next}}, context) == Done{Const.Evaluation{Const.U32Value{value}, Const.Budget{0n, Nil{}}}} : Result<&2, &2, M.Diagnostic, Const.Evaluation>}

# Matching evaluates each column only if preceding columns complete normally.
law match_return_skips_remaining_scrutinees:
  for value: U32
  for next: M.Expr
  for context: Const.Context
  {Const.evaluate(4n, 4n, M.BlockExpr{0n, M.MatchExpr{[M.ReturnExpr{0n, M.U32Expr{value}}, next], Nil{}}}, context) == Done{Const.Evaluation{Const.U32Value{value}, Const.Budget{0n, Nil{}}}} : Result<&2, &2, M.Diagnostic, Const.Evaluation>}

law product_projection_selects_first:
  for first: Const.Value
  for second: Const.Value
  for steps: Const.Budget
  {Const.project(Const.ProductValue{[first, second]}, 0n, steps) == Done{Const.Evaluation{first, steps}} : Result<&2, &2, M.Diagnostic, Const.Evaluation>}

law product_projection_selects_second:
  for first: Const.Value
  for second: Const.Value
  for steps: Const.Budget
  {Const.project(Const.ProductValue{[first, second]}, 1n, steps) == Done{Const.Evaluation{second, steps}} : Result<&2, &2, M.Diagnostic, Const.Evaluation>}

law product_projection_rejects_length_index:
  for elements: List<&2, Const.Value>
  for steps: Const.Budget
  {Result.is_done(&2, &2, M.Diagnostic, Const.Evaluation, Const.project(Const.ProductValue{elements}, List.length(&2, Const.Value, elements), steps)) == False{} : Bool}

law product_retains_mixed_fields:
  for number: U32
  for flag: Bool
  for context: Const.Context
  {Const.evaluate(3n, 3n, M.ProductExpr{[M.U32Expr{number}, M.BoolExpr{flag}]}, context) == Done{Const.Evaluation{Const.ProductValue{[Const.U32Value{number}, Const.BoolValue{flag}]}, Const.Budget{0n, Nil{}}}} : Result<&2, &2, M.Diagnostic, Const.Evaluation>}

law product_return_skips_remaining_elements:
  for value: U32
  for next: M.Expr
  for context: Const.Context
  {Const.evaluate(4n, 4n, M.BlockExpr{0n, M.ProductExpr{[M.ReturnExpr{0n, M.U32Expr{value}}, next]}}, context) == Done{Const.Evaluation{Const.U32Value{value}, Const.Budget{0n, Nil{}}}} : Result<&2, &2, M.Diagnostic, Const.Evaluation>}

law empty_array_length_is_zero:
  for steps: Const.Budget
  {Const.array_length(Const.ArrayValue{Nil{}}, steps) == Done{Const.Evaluation{Const.U32Value{0}, steps}} : Result<&2, &2, M.Diagnostic, Const.Evaluation>}

law array_read_selects_first:
  for first: Const.Value
  for tail: List<&2, Const.Value>
  for steps: Const.Budget
  {Const.array_get(Const.ArrayValue{first <> tail}, Const.U32Value{0}, steps) == Done{Const.Evaluation{first, steps}} : Result<&2, &2, M.Diagnostic, Const.Evaluation>}

law array_read_rejects_length_index:
  for elements: List<&2, Const.Value>
  for steps: Const.Budget
  {Result.is_done(&2, &2, M.Diagnostic, Const.Evaluation, Const.array_get_elements(elements, List.length(&2, Const.Value, elements), steps)) == False{} : Bool}

law array_set_preserves_other_elements:
  for first: Const.Value
  for second: Const.Value
  for replacement: Const.Value
  {Const.array_set(Const.ArrayValue{[first, second]}, Const.U32Value{0}, replacement, Const.Budget{2n, Nil{}}) == Done{Const.Evaluation{Const.ArrayValue{[replacement, second]}, Const.Budget{0n, Nil{}}}} : Result<&2, &2, M.Diagnostic, Const.Evaluation>}

law array_copy_requires_per_element_budget:
  for first: Const.Value
  for second: Const.Value
  for replacement: Const.Value
  {Result.is_done(&2, &2, M.Diagnostic, Const.Evaluation, Const.array_set(Const.ArrayValue{[first, second]}, Const.U32Value{0}, replacement, Const.Budget{1n, Nil{}})) == False{} : Bool}

law array_return_skips_remaining_elements:
  for value: U32
  for next: M.Expr
  for context: Const.Context
  {Const.evaluate(4n, 4n, M.BlockExpr{0n, M.ArrayExpr{[M.ReturnExpr{0n, M.U32Expr{value}}, next]}}, context) == Done{Const.Evaluation{Const.U32Value{value}, Const.Budget{0n, Nil{}}}} : Result<&2, &2, M.Diagnostic, Const.Evaluation>}

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
  {Substitutions.resolve_work(Substitutions.empty(), fuel, Substitutions.OneType{ty}) == Done{[ty]} : Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>}

# A sequential substitution does not apply itself inside the inserted type.
law final_substitution_does_not_rewrite_its_replacement:
  for +replacement: M.Ty
  for fuel: Nat
  {Substitutions.resolve_work(Substitutions.from_list([Substitutions.Substitution{0n, replacement}]), 1n+fuel, Substitutions.OneType{M.VariableTy{0n}}) == Done{[replacement]} : Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>}

law substitutions_preserve_u32:
  for substitutions: Substitutions.Substitutions
  for fuel: Nat
  {Substitutions.resolve_work(substitutions, 1n+fuel, Substitutions.OneType{M.U32Ty{}}) == Done{[M.U32Ty{}]} : Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>}

# The explicit continuation machine has a finite step budget. Crossing it
# restarts the unchanged resolver with the original history, fuel, and work.
law flat_resolver_step_exhaustion_restarts_reference:
  for substitutions: Substitutions.Substitutions
  for fuel: Nat
  for work: Substitutions.TypeWork
  {Substitutions.flat_result(None{}, substitutions, fuel, work) == Substitutions.resolve_work_reference(substitutions, fuel, work) : Result<&2, &2, M.Diagnostic, List<&2, M.Ty>>}

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

law parallel_linking_keeps_first_failure:
  for +error: M.Diagnostic
  for following: List<&2, Result<&2, &2, M.Diagnostic, Wasm.BytePlan>>
  {Wasm.collect_bodies(Fail{error} <> following) == Fail{error} : Result<&2, &2, M.Diagnostic, List<&2, Wasm.BytePlan>>}

law nominal_summaries_keep_function_failure_first:
  for +error: M.Diagnostic
  for constants: Result<&2, &2, M.Diagnostic, List<&2, Groups.DeclarationUsage>>
  {NativePlan.nominal_usages(NativePlan.Nominals{Fail{error}, constants}) == Fail{error} : Result<&2, &2, M.Diagnostic, List<&2, Groups.DeclarationUsage>>}

law packed_output_keeps_first_failure:
  for +error: M.Diagnostic
  for following: Result<&2, &2, M.Diagnostic, NativeOutput.Packed>
  {NativeOutput.merge(Fail{error}, following) == Fail{error} : Result<&2, &2, M.Diagnostic, NativeOutput.Packed>}

law parallel_modules_keep_first_failure:
  for +error: M.Diagnostic
  for following: List<&2, Result<&2, &2, M.Diagnostic, M.Module>>
  for previous: M.Module
  {SourceModules.collect_modules(Fail{error} <> following, previous) == Fail{error} : Result<&2, &2, M.Diagnostic, M.Module>}

# A resolved lexical binding must not scan the remaining scope. This also keeps
# host stack usage independent of the number of unrelated bindings.
law wasm_local_lookup_hit_finishes:
  for locals: List<&2, Wasm.Local>
  for name: String
  for +location: Wasm.Location
  {Wasm.lookup_local_work(locals, name, Some{location}) == Done{location} : Result<&2, &2, M.Diagnostic, Wasm.Location>}

law const_local_lookup_hit_finishes:
  for locals: List<&2, Const.Binding<Const.Value>>
  for name: String
  for +value: Const.Value
  {Const.lookup_local_work(locals, name, Some{value}) == Done{value} : Result<&2, &2, M.Diagnostic, Const.Value>}

law const_declaration_lookup_hit_finishes:
  for constants: List<&2, M.Constant>
  for name: String
  for +value: M.Expr
  {Const.lookup_constant_work(constants, name, Some{value}) == Done{value} : Result<&2, &2, M.Diagnostic, M.Expr>}

law const_function_lookup_hit_finishes:
  for functions: List<&2, M.Function>
  for name: String
  for +value: M.Function
  {Const.lookup_function_work(functions, name, Some{value}) == Done{value} : Result<&2, &2, M.Diagnostic, M.Function>}

# A pin reads the surrounding scope and contributes no new pattern bindings.
law value_pattern_preserves_local_reference:
  for +name: String
  for node: Cst.Cst
  {Lower.value_pattern(M.LocalExpr{name}, node) == Done{Lower.PatternResult{M.ValuePattern{M.LocalReference{name}}, Nil{}}} : Result<&2, &2, M.Diagnostic, Lower.PatternResult>}

# Runtime references cannot establish exhaustive coverage of a finite type.
law value_pattern_is_refutable:
  for head: Patterns.Head
  for reference: M.ValueReference
  for tail: List<&2, M.Pattern>
  {Patterns.select_head(head, M.ValuePattern{reference}, tail) == None{} : Maybe<&2, List<&2, M.Pattern>>}

# Filling zero slots preserves the step budget and never creates an element.
law empty_array_fill_preserves_budget:
  for value: Const.Value
  for +steps: Const.Budget
  {Const.array_fill_elements(0n, value, Nil{}, steps) == Done{Const.Evaluation{Const.ArrayValue{Nil{}}, steps}} : Result<&2, &2, M.Diagnostic, Const.Evaluation>}

law array_fill_rejects_oversized_count:
  for count: U32
  for value: Const.Value
  for steps: Const.Budget
  {Const.array_fill_checked(False{}, count, value, steps) == Fail{M.Diagnostic{"backend_limit", "array", "array length exceeds the 16 MiB bootstrap arena"}} : Result<&2, &2, M.Diagnostic, Const.Evaluation>}

# A zero-length generation never invokes the callback or spends its budget.
law empty_array_generation_skips_callback:
  for +steps: Const.Budget
  for generator: Const.Value
  for context: Const.Context
  {Const.evaluate_work(1n, 0n, Nil{}, steps, Const.GenerateElements{generator, 0, Nil{}}, context) == Done{Const.Evaluation{Const.ArrayValue{Nil{}}, steps}} : Result<&2, &2, M.Diagnostic, Const.Evaluation>}

# Associated dispatch preserves left precedence and operand order at compile time.
law associated_left_precedence:
  for left: Infer.Typing
  for right: Result<&2, &2, M.Diagnostic, Infer.Typing>
  for +name: String
  for other: Maybe<&2, String>
  for subject: String
  for description: String
  {Mono.chosen(Done{left}, Some{name}, right, other, subject, description) == Done{name} : Result<&2, &2, M.Diagnostic, String>}

law associated_call_preserves_operands:
  for +name: String
  for member: String
  for +left: M.Expr
  for +right: M.Expr
  {Mono.selected_call(Some{Mono.FunctionChoice{name}}, member, left, right) == Done{M.UseExpr{"$associated.left", left, M.UseExpr{"$associated.right", right, M.ApplyExpr{M.ApplyExpr{M.FunctionExpr{name}, M.LocalExpr{"$associated.left"}}, M.LocalExpr{"$associated.right"}}}}} : Result<&2, &2, M.Diagnostic, M.Expr>}

law rebinding_self_uses_previous_local:
  for +core: String
  for +context: Lower.Context
  for node: Cst.Cst
  {Lower.rebinding_scope(Some{core}, context, node) == Done{Lower.bind(context, Lower.Local{"self", core})} : Result<&2, &2, M.Diagnostic, Lower.Context>}

# State cells are scoped; finishing a resolver exposes a successor without mutating its input.
law state_scope_returns_successor:
  for current: Const.Value
  for result: U32
  for steps: Nat
  for outer: List<&2, Const.StateCell>
  {Const.finish_state_scope(Const.Evaluation{Const.U32Value{result}, Const.Budget{steps, Const.StateCell{0n, current} <> outer}}, 0n) == Done{Const.Evaluation{Const.ProductValue{[current, Const.U32Value{result}]}, Const.Budget{steps, outer}}} : Result<&2, &2, M.Diagnostic, Const.Evaluation>}

law state_scope_preserves_nonlocal_return:
  for current: Const.Value
  for result: Const.Value
  for label: Nat
  for steps: Nat
  for outer: List<&2, Const.StateCell>
  {Const.finish_state_scope(Const.Evaluation{Const.ReturnValue{label, result}, Const.Budget{steps, Const.StateCell{0n, current} <> outer}}, 0n) == Done{Const.Evaluation{Const.ReturnValue{label, result}, Const.Budget{steps, outer}}} : Result<&2, &2, M.Diagnostic, Const.Evaluation>}

# Multiple escaping references require a copy, even after the last read.
law shared_array_is_not_consumed:
  for last: Nat
  for end: Nat
  {Reuse.consumed(Reuse.Usage{2n, last}, end) == False{} : Bool}

law unknown_array_storage_is_not_owned:
  for name: String
  for usages: Map<&2, Reuse.Usage>
  for end: Nat
  {Reuse.transferable(name, Map.new(&2, Bool), usages, end) == False{} : Bool}

law array_reuse_preserves_operand_order:
  for +array: Codegen.Expr
  for +index: Codegen.Expr
  for +value: Codegen.Expr
  {Reuse.children(Codegen.ArrayReuseExpr{array, index, value}) == [array, index, value] : List<&2, Codegen.Expr>}

# A failed or exhausted structural comparison never certifies a body.
law retained_core_comparison_stops_on_mismatch:
  for fuel: Nat
  for pending: List<&2, CoreCompare.Work>
  {CoreCompare.compare(fuel, pending, False{}) == False{} : Bool}

law retained_core_comparison_exhaustion_is_a_miss:
  for head: CoreCompare.Work
  for tail: List<&2, CoreCompare.Work>
  {CoreCompare.compare(0n, head <> tail, True{}) == False{} : Bool}

law retained_group_skips_reinference:
  for +position: Nat
  for +checked: Groups.CheckedGroup
  {Scheduler.check_task_planned(Scheduler.RetainedTask{position, checked}, Unit{}) == Scheduler.Outcome{position, Done{checked}} : Scheduler.Outcome}

law ordinary_catalog_does_not_collect_certificates:
  for module: M.Module
  {Scheduler.collecting(Scheduler.catalog(module)) == False{} : Bool}

law evidenced_group_keeps_exact_source_and_imports:
  for +position: Nat
  for +module: M.Module
  for +imports: List<&2, Groups.Interface>
  for cost: Nat
  {Scheduler.check_task_planned(Scheduler.EvidenceTask{position, module, imports, cost}, Unit{}) == Scheduler.EvidenceOutcome{position, module, imports, Groups.check_group_planned(module, imports)} : Scheduler.Outcome}

# Alpha-renaming changes the shared value/row variable domain, while ordered
# operation identities (including duplicates) remain part of the checked type.
law residual_renaming_preserves_operation_labels:
  for +operations: List<&2, M.TypeId>
  for tail: M.RowTail
  for mapping: NatIndex.Index<Nat>
  {Substitutions.rename_row(M.EffectRow{operations, tail}, mapping) == M.EffectRow{operations, Substitutions.rename_tail(tail, mapping)} : M.EffectRow}

law parameter_mapping_keeps_first_binder:
  for previous: Nat
  for head: Nat
  for index: Nat
  for +mapping: NatIndex.Index<Nat>
  {Substitutions.parameter_mapping_next(Some{previous}, head, index, mapping) == mapping : NatIndex.Index<Nat>}

law empty_generic_scheme_needs_no_traversal:
  for +ty: M.Ty
  for +next: Nat
  {Infer.instance(Nil{}, ty, next) == Done{Infer.SchemeInstance{ty, next}} : Result<&2, &2, M.Diagnostic, Infer.SchemeInstance>}

# A successful group check is reused as a whole dependency component. Dropping
# declarations cannot turn a larger certificate into a proof for a smaller one.
law retained_group_cannot_discard_all_functions:
  for function: M.Function
  for rest: List<&2, M.Function>
  {CheckedCore.same_declarations(M.Module{Nil{}, function <> rest, Nil{}, Nil{}}, M.Module{Nil{}, Nil{}, Nil{}, Nil{}}) == False{} : Bool}

# Frontier reuse fails closed and never reinterprets an already retained group.
law frontier_comparison_stops_on_mismatch:
  for fuel: Nat
  for pending: List<&2, FrontierAlpha.Work>
  for delta: Maybe<&2, FrontierAlpha.Offset>
  {FrontierAlpha.compare_work(fuel, False{}, pending, delta) == False{} : Bool}

law frontier_comparison_exhaustion_is_a_miss:
  for head: FrontierAlpha.Work
  for tail: List<&2, FrontierAlpha.Work>
  for delta: Maybe<&2, FrontierAlpha.Offset>
  {FrontierAlpha.compare_work(0n, True{}, head <> tail, delta) == False{} : Bool}

law frontier_failure_checks_the_current_task:
  for diagnostic: M.Diagnostic
  for +task: Scheduler.Task
  {Scheduler.representative_found(Fail{diagnostic}, task) == Scheduler.check_task_planned(task, Unit{}) : Scheduler.Outcome}

law frontier_reuse_excludes_retained_tasks:
  for position: Nat
  for checked: Groups.CheckedGroup
  {Scheduler.task_candidate(Scheduler.RetainedTask{position, checked}) == None{} : Maybe<&2, Scheduler.FrontierCandidate>}

# Pending caches retain raw requirements in order; current substitutions still
# determine their readiness. An invalid prefix count uses the complete scan.
law pending_cache_preserves_requirements:
  for count: Nat
  for +needs: List<&2, Infer.Coverage>
  {Mono.cached_needs(Mono.PendingCache{count, needs}) == needs : List<&2, Infer.Coverage>}

law empty_coverage_preserves_pending_tail:
  for choices: Map<&2, Mono.Choice>
  for +rest: List<&2, Infer.Coverage>
  {Mono.unresolved_coverage_with_tail(Nil{}, choices, rest) == rest : List<&2, Infer.Coverage>}

law empty_fresh_prefix_preserves_pending_tail:
  for definitions: List<&2, Infer.Definition>
  for choices: Map<&2, Mono.Choice>
  for +rest: List<&2, Infer.Coverage>
  {Mono.fresh_unresolved(Mono.FreshWork{0n, definitions}, choices, rest) == Some{rest} : Maybe<&2, List<&2, Infer.Coverage>>}

law invalid_pending_prefix_uses_full_scan:
  for +selected: Mono.Specialization
  for +count: Nat
  for prior_count: Nat
  for definitions: List<&2, Infer.Definition>
  for prior_needs: List<&2, Infer.Coverage>
  for choices: Map<&2, Mono.Choice>
  {Mono.refresh_with_count(False{}, selected, count, prior_count, definitions, prior_needs, choices) == Mono.PendingCache{count, Mono.specialization_pending(selected)} : Mono.PendingCache}

# Repeated references must not duplicate the binding environment. A name index
# preserves source positions and every binding with that name, including shadows.
law global_binding_repeat_reference_keeps_selection:
  for name: String
  for index: Map<&2, List<&2, GlobalBindings.Entry>>
  for +selection: GlobalBindings.Selection
  {GlobalBindings.select_name(True{}, name, index, selection) == selection : GlobalBindings.Selection}

law empty_global_references_select_no_bindings:
  for index: Map<&2, List<&2, GlobalBindings.Entry>>
  {GlobalBindings.referenced(index, Nil{}) == Nil{} : List<&2, Infer.Binding>}

law global_declaration_lookup_keeps_first_match:
  for rest: List<&2, Globals.Declaration>
  for name: String
  for +declaration: Globals.Declaration
  {Globals.lookup_work(rest, name, Some{declaration}) == Done{declaration} : Result<&2, &2, M.Diagnostic, Globals.Declaration>}

law dependency_membership_work_stops_after_hit:
  for rest: List<&2, String>
  for name: String
  {Dependency.contains_work(rest, name, True{}) == True{} : Bool}

law state_membership_work_stops_after_hit:
  for rest: List<&2, M.Operation>
  for identity: M.TypeId
  {StateSpecialize.contains_work(rest, identity, True{}) == True{} : Bool}

law variable_membership_work_stops_after_hit:
  for rest: List<&2, Nat>
  for variable: Nat
  {Substitutions.variable_contains_work(rest, variable, True{}) == True{} : Bool}

# Failed speculation must use the original environment and declaration order.
law failed_parallel_commit_replays_serial_inference:
  for +declarations: List<&2, Globals.Declaration>
  for +environment: Globals.Environment
  for +operations: List<&2, M.Operation>
  for +types: List<&2, M.DataType>
  for +functions: List<&2, String>
  for +catalog: Maybe<&2, Map<&2, List<&2, GlobalBindings.Entry>>>
  {ParallelInfer.serial_or_committed(None{}, declarations, environment, operations, types, functions, catalog) == ParallelInfer.serial(declarations, environment, operations, types, functions, catalog) : Result<&2, &2, M.Diagnostic, Globals.Environment>}

# Typed source evidence cannot be used after any eligibility guard fails.
law rejected_staging_scheme_does_not_replay:
  for scheme: StagingScheme.Scheme
  for clone: M.Function
  for parsed: StagingScheme.CloneName
  for stride: Nat
  for environment: Globals.Environment
  {StagingScheme.replay_scheme(False{}, scheme, clone, parsed, stride, environment) == None{} : Maybe<&2, Globals.Environment>}

# Operation signatures contribute a transitive nominal catalog shared by every
# checking job. Jobs without additional requirements reuse its sorted list.
law shared_nominal_catalog_reuses_sorted_list:
  for shared: Groups.TypeSet()
  for +common: List<&2, M.TypeId>
  {Groups.required_for_summary(MTip{}, shared, common) == common : List<&2, M.TypeId>}

# Optional schema reduction must fall back when evidence or bounded work fails.
law exhausted_schema_reduction_is_a_miss:
  for work: Schema.ChainWork
  {Schema.decide_chain(0n, work) == None{} : Maybe<&2, Bool>}

law rejected_schema_source_is_a_miss:
  for left: M.Ty
  for witness: M.Ty
  for proof: Schema.Evidence
  {Schema.decide_checked(False{}, left, witness, proof) == None{} : Maybe<&2, Bool>}

# A true membership result cannot hide a malformed later head or tail.
law schema_hit_still_validates_tail:
  for +fuel: Nat
  for +tail: M.Ty
  for +wanted: String
  for +proof: Schema.Evidence
  for answer: Bool
  {Schema.decide_chain(1n+fuel, Schema.Choose{True{}, tail, wanted, proof, answer}) == Schema.decide_chain(fuel, Schema.Walk{tail, wanted, proof, True{}}) : Maybe<&2, Bool>}

law missing_schema_choice_uses_ordinary_selection:
  for +need: Infer.Coverage
  for +left: M.Ty
  for +right: M.Ty
  for +specialization: Mono.Specialization
  for +configuration: Mono.Configuration
  for +shapes: List<&2, Infer.Binding>
  for +schemes: List<&2, StagingScheme.Scheme>
  {Mono.select_method_staged(None{}, need, left, right, specialization, configuration, shapes, schemes) == Mono.select_method_original(need, left, right, specialization, configuration, shapes, schemes) : Result<&2, &2, M.Diagnostic, Mono.Specialization>}
