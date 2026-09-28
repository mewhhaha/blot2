import Base
import ./compiler/schema_stage.bend as Schema
import ./compiler/model.bend as M
import ./compiler/constraints.bend as Constraints
import ./compiler/effects.bend as Effects
import ./compiler/const_eval.bend as Const
import ./compiler/check.bend as Check
import ./compiler/lower.bend as Lower
import ./compiler/types.bend as Substitutions
import ./compiler/wasm.bend as Wasm
import ./compiler/codegen_ir.bend as Codegen
import ./compiler/codegen_saturation.bend as Saturation
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
import ./compiler/resolving_core.bend as ResolvingCore
import ./compiler/nat_index.bend as NatIndex
import ./compiler/frontier_alpha_compare.bend as FrontierAlpha
import ./compiler/global_bindings.bend as GlobalBindings
import ./compiler/globals.bend as Globals
import ./compiler/state_specialize.bend as StateSpecialize
import ./compiler/parallel_infer.bend as ParallelInfer
import ./compiler/staging_scheme.bend as StagingScheme
import ./compiler/main.bend as Main
import ./compiler/dispatch_resolution.bend as Resolution
import ./compiler/entry_points.bend as Entries
import ./compiler/loop_memory.bend as LoopMemory
import ./compiler/raw_core_qualification.bend as RawQualification
import ./compiler/effect_rows.bend as Rows

# Raw core has no evidence selector, so a nonempty qualification cannot be
# erased by constant evaluation. Empty metadata remains transparent.
law raw_core_rejects_nonempty_qualification:
  for offset: Nat
  {RawQualification.check(M.Module{[M.Constant{"answer", False{}, None{}, M.QualifiedExpr{offset, M.U32Ty{}, [M.TypeRepPredicate{M.U32Ty{}}], M.U32Expr{42}}}], Nil{}, Nil{}, Nil{}}) == Fail{M.Diagnostic{"unspecialized_qualified", "offset:" ++ Nat.show(offset), "raw core with a nonempty where clause requires evidence elaboration through the source compiler"}} : Result<&2, &2, M.Diagnostic, Unit>}

law raw_core_accepts_empty_qualification:
  for value: U32
  {RawQualification.check(M.Module{[M.Constant{"answer", False{}, None{}, M.QualifiedExpr{0n, M.U32Ty{}, Nil{}, M.U32Expr{value}}}], Nil{}, Nil{}, Nil{}}) == Done{Unit{}} : Result<&2, &2, M.Diagnostic, Unit>}

# A declaration tag records the exact source origin and both dependencies.
law declaration_tag_preserves_origin_and_operands:
  for offset: Nat
  for function: M.Expr
  for value: M.Expr
  {Lower.tag_application(offset, function, value) == M.TagExpr{offset, function, value} : M.Expr}

law declaration_tag_reachability_includes_both_operands:
  for offset: Nat
  for function: M.Expr
  for value: M.Expr
  {Closures.children(M.TagExpr{offset, function, value}) == [function, value] : List<&2, M.Expr>}

law empty_declaration_tags_preserve_initializer:
  for value: M.Expr
  for fuel: Nat
  for scope: Lower.Context
  {Lower.apply_tags(Nil{}, value, fuel, scope) == Done{value} : Result<&2, &2, M.Diagnostic, M.Expr>}

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

# A singleton remains one SCC even with self or unresolved outgoing edges.
# The general DFS still spends one fuel step per pending event.
law empty_dependency_graph_has_no_components:
  {Dependency.components(Nil{}) == Done{Nil{}} : Result<&2, &2, M.Diagnostic, List<&2, List<&2, String>>>}

law singleton_dependency_graph_is_one_component:
  for +name: String
  for references: List<&2, String>
  for lambdas: List<&2, Nat>
  {Dependency.components([Dependency.Node{name, references, lambdas}]) == Done{[name <> Nil{}]} : Result<&2, &2, M.Diagnostic, List<&2, List<&2, String>>>}

law seen_dependency_enter_does_not_expand_neighbors:
  for name: String
  for edges: Map<&2, List<&2, String>>
  for +pending: List<&2, Dependency.Visit>
  {Dependency.visit_events_edges(False{}, name, edges, pending) == pending : List<&2, Dependency.Visit>}

law seen_dependency_reach_does_not_expand_neighbors:
  for edges: Map<&2, List<&2, String>>
  for name: String
  for +pending: List<&2, String>
  {Dependency.next_work_edges(False{}, edges, name, pending) == pending : List<&2, String>}

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
  {List.take(&2, U32, NativeResponse.finish(Fail{M.Diagnostic{"native_protocol", "native_response", "response exceeds 16M words"}}), 3n) == [1112297300, 13, 0] : List<&2, U32>}

# A Wasm-only (Emit) request runs the same compile pipeline and session caches
# as Compile, so its Wasm is identical; only the reply drops the analysis.
law native_emit_compiles_like_compile:
  {NativeRequest.mode(NativeRequest.EmitWasm{}) == NativeRequest.mode(NativeRequest.Compile{}) : Session.Mode}

law native_emit_replies_wasm_only:
  {NativeRequest.contents(NativeRequest.EmitWasm{}) == NativeOutput.WasmOnly{} : NativeOutput.Contents}

# encode_artifact and session replies take their fields from artifact_fields.
law native_wasm_only_reply_omits_analysis:
  for analysis: Main.Analysis
  {NativeOutput.artifact_fields(NativeOutput.WasmOnly{}, analysis) == [NativeResponse.Word{5}] : List<&2, NativeResponse.Work>}

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
  for signature: M.Ty
  {Mono.selected_call(Some{Mono.FunctionChoice{name, signature}}, member, left, right) == Done{M.UseExpr{"$associated.left", left, M.UseExpr{"$associated.right", right, M.ApplyExpr{M.ApplyExpr{M.FunctionExpr{name}, M.LocalExpr{"$associated.left"}}, M.LocalExpr{"$associated.right"}}}}} : Result<&2, &2, M.Diagnostic, M.Expr>}

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
  {Scheduler.check_task_planned(Scheduler.EvidenceTask{position, module, imports, cost}, Unit{}) == Scheduler.EvidenceOutcome{position, module, imports, Groups.check_group_resolving_planned(module, imports)} : Scheduler.Outcome}

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
  {Infer.instance(Nil{}, ty, next) == Done{Infer.SchemeInstance{ty, Nil{}, next}} : Result<&2, &2, M.Diagnostic, Infer.SchemeInstance>}

# A successful group check is reused as a whole dependency component. Dropping
# declarations cannot turn a larger certificate into a proof for a smaller one.
law retained_group_cannot_discard_all_functions:
  for function: M.Function
  for rest: List<&2, M.Function>
  {CheckedCore.same_declarations(M.Module{Nil{}, function <> rest, Nil{}, Nil{}}, M.Module{Nil{}, Nil{}, Nil{}, Nil{}}) == False{} : Bool}

# A duplicate catalog identity resolves to the earliest declaration. This also
# applies when an abstract operation precedes a concrete operation of the same
# identity: only required abstract operations are skipped during validation.
law certificate_type_index_keeps_first_identity:
  {Index.find(M.DataType, CheckedCore.first_type_index([M.DataType{M.TypeId{"catalog", "Item"}, 0n, Nil{}}, M.DataType{M.TypeId{"catalog", "Item"}, 1n, Nil{}}], Map.new(&2, M.DataType)), Groups.type_key(M.TypeId{"catalog", "Item"})) == Some{M.DataType{M.TypeId{"catalog", "Item"}, 0n, Nil{}}} : Maybe<&2, M.DataType>}

law certificate_operation_index_keeps_first_identity:
  {Index.find(M.Operation, CheckedCore.first_operation_index([M.OperationTemplate{M.TypeId{"catalog", "Read"}, 1n, M.UnitTy{}, M.U32Ty{}}, M.Operation{M.TypeId{"catalog", "Read"}, M.UnitTy{}, M.U32Ty{}}], Map.new(&2, M.Operation)), Groups.type_key(M.TypeId{"catalog", "Read"})) == Some{M.OperationTemplate{M.TypeId{"catalog", "Read"}, 1n, M.UnitTy{}, M.U32Ty{}}} : Maybe<&2, M.Operation>}

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

law empty_pending_change_has_no_requirements:
  for change: Mono.ChoiceChange
  {Mono.remaining_after_change(Nil{}, change) == Nil{} : List<&2, Infer.Coverage>}

law different_qualified_site_stays_pending:
  for predicate: M.Predicate
  for selected: M.Predicate
  {Mono.qualified_pending_after_change(False{}, predicate, selected) == True{} : Bool}

law unknown_choice_change_uses_full_refresh:
  for +selected: Mono.Specialization
  for +cache: Mono.PendingCache
  {Mono.refresh_after_change(selected, cache, Mono.UnknownChoiceChange{}) == Mono.refresh_pending(selected, cache) : Mono.PendingCache}

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

law dependency_lookup_stops_after_match:
  for rest: List<&2, Dependency.Node>
  for name: String
  for +found: List<&2, String>
  {Dependency.lookup_work(rest, name, True{}, found) == found : List<&2, String>}

law definition_predicates_stop_after_match:
  for rest: List<&2, Infer.Definition>
  for name: String
  for +found: List<&2, M.Predicate>
  {Globals.definition_predicates_work(rest, name, True{}, found) == found : List<&2, M.Predicate>}

law empty_operation_merge_preserves_catalog:
  for +operations: List<&2, M.Operation>
  {StateSpecialize.merge(Nil{}, operations) == operations : List<&2, M.Operation>}

law zero_distance_index_advance_preserves_suffix:
  for +suffix: String
  {Index.advance_suffix(0n, suffix) == suffix : String}

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

law sorted_nominal_merge_keeps_common_without_new_types:
  for +common: List<&2, M.TypeId>
  {Groups.merge_required(common, Nil{}) == common : List<&2, M.TypeId>}

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

# Concrete dispatch resolution. A requirement is closed only when no caller can
# instantiate its types differently: inference, generalized and row variables
# all keep a site deferred.
law dispatch_inference_variable_is_open:
  for fuel: Nat
  for index: Nat
  for tail: List<&2, M.Ty>
  {Groups.closed_types(1n+fuel, M.VariableTy{index} <> tail) == False{} : Bool}

law dispatch_generalized_variable_is_open:
  for fuel: Nat
  for index: Nat
  for tail: List<&2, M.Ty>
  {Groups.closed_types(1n+fuel, M.ParameterTy{index} <> tail) == False{} : Bool}

law dispatch_open_effect_row_is_open:
  for fuel: Nat
  for parameter: M.Ty
  for result: M.Ty
  for operations: List<&2, M.TypeId>
  for index: Nat
  for tail: List<&2, M.Ty>
  {Groups.closed_types(1n+fuel, M.FunctionTy{parameter, result, M.EffectRow{operations, M.RowVariable{index}}} <> tail) == False{} : Bool}

# Type identity requests keep their own compile-time specialization.
law dispatch_type_identity_is_not_plain:
  {Resolution.plain_member("@type.same") == False{} : Bool}

# Receiver selection waits until the receiver's nominal head is known; a
# requirement that cannot be selected leaves the group solver untouched.
law dispatch_unknown_receiver_waits:
  for index: Nat
  {Resolution.receiver_known(M.VariableTy{index}) == False{} : Bool}

law dispatch_dropped_requirement_changes_nothing:
  for need: Groups.Resolution
  for +solving: Resolution.Solving
  {Resolution.settle(Resolution.Dropped{}, need, solving) == solving : Resolution.Solving}

# A site without a unique planned choice stays deferred, so specialization
# still owns its diagnostics (ambiguity, missing members, clashes).
law dispatch_unplanned_site_stays_deferred:
  for identity: Nat
  for dispatch: M.Dispatch
  for member: String
  for templates: List<&2, M.TypeId>
  for left: M.Expr
  for right: M.Expr
  {Resolution.resolved_call(None{}, identity, dispatch, member, templates, left, right) == Done{M.AssociatedExpr{identity, dispatch, member, templates, left, right}} : Result<&2, &2, M.Diagnostic, M.Expr>}

law dispatch_conflicting_requirements_rewrite_neither:
  for choice: Mono.Choice
  {Resolution.choice_entry(True{}, choice) == None{} : Maybe<&2, Mono.Choice>}

# A resolved binary site is exactly specialization's call: both operands are
# evaluated once, left to right, before the selected implementation is applied.
law dispatch_binary_site_calls_selected_implementation:
  for identity: Nat
  for member: String
  for templates: List<&2, M.TypeId>
  for left: M.Expr
  for right: M.Expr
  for name: String
  for signature: M.Ty
  {Resolution.resolved_call(Some{Some{Mono.FunctionChoice{name, signature}}}, identity, M.BinaryDispatch{}, member, templates, left, right) == Done{M.UseExpr{"$associated.left", left, M.UseExpr{"$associated.right", right, M.ApplyExpr{M.ApplyExpr{M.FunctionExpr{name}, M.LocalExpr{"$associated.left"}}, M.LocalExpr{"$associated.right"}}}}} : Result<&2, &2, M.Diagnostic, M.Expr>}

law dispatch_receiver_site_applies_selected_member:
  for identity: Nat
  for member: String
  for templates: List<&2, M.TypeId>
  for receiver: M.Expr
  for unit: M.Expr
  for name: String
  for signature: M.Ty
  {Resolution.resolved_call(Some{Some{Mono.ReceiverChoice{name, signature}}}, identity, M.MemberDispatch{}, member, templates, receiver, unit) == Done{M.ApplyExpr{M.FunctionExpr{name}, receiver}} : Result<&2, &2, M.Diagnostic, M.Expr>}

# The resolved call contains no deferred dispatch, so its declaration is no
# longer a template seed.
law dispatch_resolved_site_is_not_a_seed:
  for left: String
  for right: String
  for name: String
  {Mono.has_deferred(16n, [M.UseExpr{"$associated.left", M.LocalExpr{left}, M.UseExpr{"$associated.right", M.LocalExpr{right}, M.ApplyExpr{M.ApplyExpr{M.FunctionExpr{name}, M.LocalExpr{"$associated.left"}}, M.LocalExpr{"$associated.right"}}}}]) == False{} : Bool}

# One accessor per (receiver nominal type, field): the name depends on nothing
# else, so every site and every specialization unit shares it.
law dispatch_field_accessor_is_shared:
  for +owner: String
  for +member: String
  {Mono.accessor_name(owner, member, M.MemberDispatch{}) == "$member[" ++ owner ++ "]." ++ member : String}

law dispatch_field_update_accessor_is_shared:
  for +owner: String
  for +member: String
  {Mono.accessor_name(owner, member, M.FieldUpdateDispatch{}) == "$member.set[" ++ owner ++ "]." ++ member : String}

law dispatch_duplicate_accessor_keeps_first:
  for function: M.Function
  for +reversed: List<&2, M.Function>
  {Mono.kept_accessor(True{}, function, reversed) == reversed : List<&2, M.Function>}

# A failed rewritten round carries first-pass evidence to the original-source
# fallback. It never exposes the rewritten diagnostic.
law dispatch_failed_round_abandons_resolution:
  for fuel: Nat
  for module: M.Module
  for diagnostic: M.Diagnostic
  for next: Nat
  for proofs: Maybe<&2, List<&2, Schema.Evidence>>
  for cache: Map<&2, Resolution.Accessor>
  for budget: Nat
  for entry: String
  for +source: List<&2, CheckedCore.Certificate>
  for +partial: List<&2, CheckedCore.Certificate>
  for inferred: Nat
  for retained: Nat
  {Resolution.rounds(1n+fuel, Resolution.CheckedRound{module, Scheduler.FailedInitial{diagnostic, partial, inferred, retained}, next, proofs, cache, budget, source}, entry) == Resolution.Fallback{List.append(&2, CheckedCore.Certificate, source, partial)} : Resolution.Resolved}

law dispatch_unchanged_round_keeps_its_check:
  for fuel: Nat
  for +initial: Scheduler.Initial
  for +module: M.Module
  for certificates: List<&2, CheckedCore.Certificate>
  for next: Nat
  for cache: Map<&2, Resolution.Accessor>
  for stable: Bool
  for proofs: List<&2, Schema.Evidence>
  for budget: Nat
  for entry: String
  for source: List<&2, CheckedCore.Certificate>
  {Resolution.rounds(1n+fuel, Resolution.RewrittenRound{initial, Resolution.Rewrite{module, certificates, next, cache, False{}, stable}, proofs, budget, source}, entry) == Resolution.Resolved{module, initial, source} : Resolution.Resolved}

# A rewrite that leaves every interface unchanged is not checked again.
law dispatch_stable_rewrite_skips_verification:
  for fuel: Nat
  for initial: Scheduler.Initial
  for module: M.Module
  for +certificates: List<&2, CheckedCore.Certificate>
  for next: Nat
  for cache: Map<&2, Resolution.Accessor>
  for proofs: List<&2, Schema.Evidence>
  for budget: Nat
  for entry: String
  for source: List<&2, CheckedCore.Certificate>
  {Resolution.rounds(1n+fuel, Resolution.RewrittenRound{initial, Resolution.Rewrite{module, certificates, next, cache, True{}, True{}}, proofs, budget, source}, entry) == Resolution.Resolved{module, Resolution.extended_initial(initial, certificates), source} : Resolution.Resolved}

law dispatch_group_without_resolutions_is_stable:
  for state: Infer.State
  for waiting: List<&2, Groups.Resolution>
  for progress: Bool
  for members: List<&2, Infer.Binding>
  for generalized: List<&2, Nat>
  for next: Nat
  {Resolution.solved_group(Resolution.Solving{state, Nil{}, waiting, progress}, members, generalized, next) == Resolution.Solved{Nil{}, True{}} : Resolution.Solved}

# A local let's scheme is invisible in every interface. A round whose solver
# binds a variable some let generalized, or binds a group variable to a type
# that mentions one, changes that let at its uses, so it is checked again
# (and abandoned if the check fails) however unchanged its interfaces are.
law dispatch_changed_local_scheme_is_checked_again:
  for unchanged: Bool
  {Resolution.stable_group(False{}, False{}, unchanged) == False{} : Bool}

law dispatch_let_generalized_binding_changes_its_scheme:
  for group: Bool
  for replacement: Bool
  {Resolution.binding_untouched(True{}, group, replacement) == False{} : Bool}

law dispatch_group_variable_must_not_name_let_generalized:
  for replacement: Bool
  {Resolution.binding_untouched(False{}, True{}, replacement) == replacement : Bool}

# A fresh variable of a selected implementation's instance may name a
# let-generalized variable: the rewritten direct call instantiates the same way.
law dispatch_fresh_instance_may_name_let_generalized:
  for replacement: Bool
  {Resolution.binding_untouched(False{}, False{}, replacement) == True{} : Bool}

law dispatch_group_without_let_generalization_keeps_schemes:
  for substitutions: Substitutions.Substitutions
  for next: Nat
  {Resolution.schemes_untouched(substitutions, Nil{}, next) == True{} : Bool}

law dispatch_unchanged_schemes_defer_to_interfaces:
  for unchanged: Bool
  {Resolution.stable_group(False{}, True{}, unchanged) == unchanged : Bool}

# Let-generalization evidence only informs resolution: pattern checking and
# specialization's requirements ignore it, and a let that generalizes nothing
# records none.
law let_generalization_evidence_is_not_a_pattern_constraint:
  for witness: M.Ty
  for +tail: List<&2, Infer.Coverage>
  for +substitutions: Substitutions.Substitutions
  for +types: List<&2, M.DataType>
  {Patterns.check(Infer.LetGeneralized{witness} <> tail, substitutions, types) == Patterns.check(tail, substitutions, types) : Result<&2, &2, M.Diagnostic, Unit>}

law let_generalization_evidence_is_not_a_requirement:
  for witness: M.Ty
  for +tail: List<&2, Infer.Coverage>
  {Mono.requirements(Infer.LetGeneralized{witness} <> tail) == Mono.requirements(tail) : List<&2, Infer.Coverage>}

law let_without_generalization_records_no_evidence:
  for coverage: List<&2, Infer.Coverage>
  for substitutions: Substitutions.Substitutions
  {Infer.let_generalized(Nil{}, coverage, substitutions) == Done{Nil{}} : Result<&2, &2, M.Diagnostic, List<&2, Infer.Coverage>>}

law dispatch_unresolved_module_specializes_original:
  for +module: M.Module
  for +entry: String
  for +family_templates: List<&2, M.Operation>
  {Resolution.prepare_deferred_resolved(Resolution.NoResolution{}, module, entry, family_templates) == Mono.prepare_deferred_core(module, entry, family_templates) : Result<&2, &2, M.Diagnostic, CheckedCore.Prepared>}

# Resolution rounds retain unchanged groups and certify them again, so the last
# round's certificates cover every group of the module it returns.
law evidence_check_certifies_retained_groups:
  for +position: Nat
  for +subset: M.Module
  for +imports: List<&2, Groups.Interface>
  for +checked: Groups.CheckedGroup
  {Scheduler.selected_task(Some{checked}, True{}, position, subset, imports) == Scheduler.RetainedEvidenceTask{position, subset, imports, checked, Nil{}} : Scheduler.Task}

# Entry declarations. `entry` is a contextual declaration modifier: any other
# identifier before `const`/`let` is rejected, `entry` outside the entry module
# is rejected, and only `entry` in the entry module sets the export flag.
law entry_modifier_rejects_other_identifiers:
  for entry_module: Bool
  for node: Cst.Cst
  {Result.is_done(&2, &2, M.Diagnostic, Bool, Lower.entry_modifier(False{}, entry_module, node)) == False{} : Bool}

law entry_outside_entry_module_is_rejected:
  for node: Cst.Cst
  {Result.is_done(&2, &2, M.Diagnostic, Bool, Lower.entry_modifier(True{}, False{}, node)) == False{} : Bool}

law entry_in_entry_module_is_exported:
  for node: Cst.Cst
  {Lower.entry_modifier(True{}, True{}, node) == Done{True{}} : Result<&2, &2, M.Diagnostic, Bool>}

law declaration_without_modifier_is_not_exported:
  for entry_module: Bool
  {Lower.declaration_modifier(Nil{}, entry_module) == Done{False{}} : Result<&2, &2, M.Diagnostic, Bool>}

# The export flag of a lowered declaration is its entry declaration.
law exported_function_is_an_entry:
  for name: String
  for parameter: String
  for p: Maybe<&2, M.Ty>
  for r: Maybe<&2, M.Ty>
  for +body: M.Expr
  {Entries.function_entries([M.Function{name, True{}, parameter, p, r, body}]) == [Entries.Entry{name, Entries.runtime_value(body)}] : List<&2, Entries.Entry>}

law runtime_constant_is_an_entry_let:
  for name: String
  for annotation: Maybe<&2, M.Ty>
  for value: M.Expr
  {Entries.constant_entries([M.Constant{name, True{}, annotation, M.RuntimeInitExpr{value}}]) == [Entries.Entry{name, True{}}] : List<&2, Entries.Entry>}

law non_entry_constant_is_not_an_entry:
  for name: String
  for annotation: Maybe<&2, M.Ty>
  for value: M.Expr
  {Entries.constant_entries([M.Constant{name, False{}, annotation, value}]) == Nil{} : List<&2, Entries.Entry>}

# Dead-code elimination drops what the entries do not reach, keeps nominal
# types and operations, and associated implementations are owned exactly as
# specialization owns them.
law unreached_function_is_pruned:
  for name: String
  for exported: Bool
  for parameter: String
  for p: Maybe<&2, M.Ty>
  for r: Maybe<&2, M.Ty>
  for body: M.Expr
  {Entries.keep_functions([M.Function{name, exported, parameter, p, r, body}], Set.new()) == Nil{} : List<&2, M.Function>}

law unreached_constant_is_pruned:
  for name: String
  for exported: Bool
  for annotation: Maybe<&2, M.Ty>
  for value: M.Expr
  {Entries.keep_constants([M.Constant{name, exported, annotation, value}], Set.new()) == Nil{} : List<&2, M.Constant>}

law pruning_keeps_operations:
  for constants: List<&2, M.Constant>
  for functions: List<&2, M.Function>
  for types: List<&2, M.DataType>
  for operations: List<&2, M.Operation>
  for +seen: Set()
  {M.module_operations(Entries.keep_module(M.Module{constants, functions, types, operations}, seen)) == operations : List<&2, M.Operation>}

law entry_owner_prefix_matches_specialization:
  for identity: M.TypeId
  for +entry: String
  {Entries.owner_prefix(identity, entry) == Mono.nominal_prefix(identity, entry) : String}

# Transformed reachability failure returns a fallback marker; the source-first
# wrapper reuses the already checked original module and its Initial.
law dispatch_failed_pruning_abandons_resolution:
  for diagnostic: M.Diagnostic
  for next: Nat
  for +entry: String
  for source: List<&2, CheckedCore.Certificate>
  {Resolution.pruned_round(Fail{diagnostic}, next, entry, source) == Resolution.Fallback{source} : Resolution.Resolved}

# Builds need an entry; a module without exports fails with no_entry.
law build_without_entries_fails:
  for types: List<&2, M.DataType>
  for operations: List<&2, M.Operation>
  {Result.is_done(&2, &2, M.Diagnostic, Unit, Entries.require_exports(M.CheckedModule{Nil{}, Nil{}, types, operations})) == False{} : Bool}

law no_entries_verify:
  for checked: M.CheckedModule
  {Entries.verify(Nil{}, checked) == Done{Unit{}} : Result<&2, &2, M.Diagnostic, Unit>}

# Catalog declarations remain available for checking and layout, but an
# unused concrete effect operation has no runtime wrapper job.
law unused_operation_has_no_wasm_job:
  for identity: M.TypeId
  for parameter: M.Ty
  for result: M.Ty
  {Wasm.used_operations([M.Operation{identity, parameter, result}], Set.new()) == Nil{} : List<&2, M.Operation>}

# The full source is checked before inlining and pruning, so its first error is
# authoritative even when a later transformation could have changed the body.
law dispatch_original_failure_is_authoritative:
  for diagnostic: M.Diagnostic
  for certificates: List<&2, CheckedCore.Certificate>
  for inferred: Nat
  for retained: Nat
  for module: M.Module
  for entry: String
  {Resolution.source_checked(Scheduler.FailedInitial{diagnostic, certificates, inferred, retained}, module, entry) == Resolution.OriginalFailure{diagnostic} : Resolution.Resolved}

law inlined_operator_retains_source_and_creation_site:
  for offset: Nat
  for site: Nat
  for value: M.Expr
  {Resolution.inline_location(offset, Some{site}, value) == M.SourceExpr{offset, None{}, M.InstantiationExpr{site, value}} : M.Expr}

law dispatch_transformed_failure_preserves_certificates:
  for diagnostic: M.Diagnostic
  for +certificates: List<&2, CheckedCore.Certificate>
  for inferred: Nat
  for retained: Nat
  for module: M.Module
  for next: Nat
  for entry: String
  for +source: List<&2, CheckedCore.Certificate>
  {Resolution.transformed_round(Scheduler.FailedInitial{diagnostic, certificates, inferred, retained}, module, next, entry, source) == Resolution.Fallback{List.append(&2, CheckedCore.Certificate, source, certificates)} : Resolution.Resolved}

law dispatch_fallback_reuses_checked_source:
  for transformed: List<&2, CheckedCore.Certificate>
  for module: M.Module
  for initial: Scheduler.Initial
  for source: List<&2, CheckedCore.Certificate>
  {Resolution.source_fallback(Resolution.Fallback{transformed}, module, initial, source) == Resolution.Resolved{module, initial, source} : Resolution.Resolved}

law dispatch_without_sites_reuses_checked_source:
  for seen: Set()
  for unique: Bool
  for module: M.Module
  for inlined: M.Module
  for initial: Scheduler.Initial
  for original: M.Module
  for entry: String
  for source: List<&2, CheckedCore.Certificate>
  {Resolution.resolve_scanned(Resolution.DispatchScan{0n, seen, unique}, module, inlined, initial, original, entry, source) == Resolution.Resolved{module, initial, source} : Resolution.Resolved}

law failed_initial_assembly_preserves_completed_groups:
  for diagnostic: M.Diagnostic
  for certificates: List<&2, CheckedCore.Certificate>
  for needs: List<&2, Groups.GroupNeeds>
  for inferred: Nat
  for retained: Nat
  {Scheduler.assembled_attempt(Fail{diagnostic}, certificates, needs, Scheduler.AuditCounts{inferred, retained}) == Scheduler.FailedInitial{diagnostic, certificates, inferred, retained} : Scheduler.InitialAttempt}

# Qualified schemes share all semantic mappings with their occurrence plans.
law qualified_rename_shares_type_and_row_mapping:
  for +mapping: NatIndex.Index<Nat>
  for +type_index: Nat
  for +row_index: Nat
  for +labels: List<&2, M.TypeId>
  {Constraints.rename(mapping, M.AssociatedPredicate{"combine", Nil{}, M.VariableTy{type_index}, M.VariableTy{type_index}, M.VariableTy{type_index}, M.EffectRow{labels, M.RowVariable{row_index}}}) == Done{M.AssociatedPredicate{"combine", Nil{}, Substitutions.renamed_type(type_index, mapping, Substitutions.FreshVariables{}), Substitutions.renamed_type(type_index, mapping, Substitutions.FreshVariables{}), Substitutions.renamed_type(type_index, mapping, Substitutions.FreshVariables{}), M.EffectRow{labels, Substitutions.rename_tail(M.RowVariable{row_index}, mapping)}}} : Result<&2, &2, M.Diagnostic, M.Predicate>}

law qualified_parameterize_preserves_row_multiplicity:
  for +mapping: NatIndex.Index<Nat>
  for +index: Nat
  for +labels: List<&2, M.TypeId>
  {Constraints.parameterize(mapping, M.EffectRepPredicate{M.EffectRow{labels, M.RowVariable{index}}}) == Done{M.EffectRepPredicate{M.EffectRow{labels, Substitutions.rename_tail_kind(M.RowVariable{index}, mapping, Substitutions.SchemeParameters{})}}} : Result<&2, &2, M.Diagnostic, M.Predicate>}

law qualified_relocate_free_row_scope_only:
  for +scope: String
  for +name: String
  for +suffix: String
  for +labels: List<&2, M.TypeId>
  {Constraints.relocate_free([M.EffectRepPredicate{M.EffectRow{labels, M.FreeRow{scope, name}}}], suffix) == Done{[M.EffectRepPredicate{M.EffectRow{labels, M.FreeRow{scope ++ suffix, name}}}]} : Result<&2, &2, M.Diagnostic, List<&2, M.Predicate>>}

law qualified_occurrence_site_is_not_a_predicate:
  for +site: Nat
  for +subject: String
  for ty: M.Ty
  for +predicate: M.Predicate
  {Infer.execution_needs([Constraints.UsePlan{site, subject, ty, [predicate]}]) == [Infer.QualifiedNeed{site, predicate, subject}] : List<&2, Infer.Coverage>}

law qualified_root_uses_reserved_creation_lane:
  for +offset: Nat
  for value: M.Expr
  {Lower.qualified_root(True{}, True{}, offset, value) == M.InstantiationExpr{Nat.add(Nat.mul(offset, 16n), 3n), value} : M.Expr}

law unexported_qualified_declaration_has_no_root_demand:
  for offset: Nat
  for value: M.Expr
  {Lower.qualified_root(False{}, True{}, offset, value) == value : M.Expr}

# A recursive peer can acquire requirements after the caller was first
# inferred. Its original, even empty, creation-site plan is filled in place.
law scc_creation_site_keeps_peer_obligation:
  for +site: Nat
  for +subject: String
  for ty: M.Ty
  for +predicate: M.Predicate
  {Globals.scc_plan_for(Some{"peer"}, Constraints.UsePlan{site, subject, ty, Nil{}}, [Globals.SccClosure{"peer", [predicate]}]) == Constraints.UsePlan{site, subject, ty, [predicate]} : Constraints.UsePlan}

law scc_effect_reflection_creates_no_callable_site:
  for +name: String
  {Globals.scc_sites(M.FunctionEffectsExpr{name}) == Done{Nil{}} : Result<&2, &2, M.Diagnostic, List<&2, Globals.SccSite>>}

law scc_raw_core_reference_keeps_dependency_without_inventing_site:
  for +name: String
  {Globals.scc_sites(M.FunctionExpr{name}) == Done{[Globals.SccSite{None{}, name, None{}}]} : Result<&2, &2, M.Diagnostic, List<&2, Globals.SccSite>>}

# A local where clause owns only the peer references inside its own boundary.
# Its initially empty requirement list must still be checked after SCC closure.
law scc_qualified_reference_keeps_nearest_boundary:
  for +offset: Nat
  for +site: Nat
  for +name: String
  {Globals.scc_sites(M.QualifiedExpr{offset, M.UnitTy{}, Nil{}, M.InstantiationExpr{site, M.FunctionExpr{name}}}) == Done{[Globals.SccSite{Some{site}, name, Some{offset}}]} : Result<&2, &2, M.Diagnostic, List<&2, Globals.SccSite>>}

law scc_other_boundary_cannot_satisfy_local_clause:
  for +site: Nat
  for +name: String
  for +predicate: M.Predicate
  {Globals.scc_boundary_predicates([Globals.SccSite{Some{site}, name, Some{1n}}], 0n, Globals.reference_set([name], Set.new()), [Globals.SccClosure{name, [predicate]}]) == Nil{} : List<&2, M.Predicate>}

# Imported templates and their requirements quantify one shared index space.
law imported_scheme_rejects_mixed_parameter_kinds:
  for +subject: String
  {Groups.validate_scheme_kinds(M.ParameterTy{0n}, [M.EffectRepPredicate{M.EffectRow{Nil{}, M.RowParameter{0n}}}], subject) == Fail{M.Diagnostic{"kind_mismatch", subject, "a quantified index is used as both a value type and an effect row"}} : Result<&2, &2, M.Diagnostic, Unit>}

# Evidence metadata cannot consume the program's constant-evaluation budget.
law const_instantiation_metadata_is_free:
  for site: Nat
  for +value: U32
  for +depth: Nat
  for +steps: Nat
  for +context: Const.Context
  {Const.evaluate(1n+depth, 1n+steps, M.InstantiationExpr{site, M.U32Expr{value}}, context) == Const.evaluate(1n+depth, 1n+steps, M.U32Expr{value}, context) : Result<&2, &2, M.Diagnostic, Const.Evaluation>}

law const_qualified_metadata_is_free:
  for offset: Nat
  for annotation: M.Ty
  for predicates: List<&2, M.Predicate>
  for +value: U32
  for +depth: Nat
  for +steps: Nat
  for +context: Const.Context
  {Const.evaluate(1n+depth, 1n+steps, M.QualifiedExpr{offset, annotation, predicates, M.U32Expr{value}}, context) == Const.evaluate(1n+depth, 1n+steps, M.U32Expr{value}, context) : Result<&2, &2, M.Diagnostic, Const.Evaluation>}

# Recycling a loop arena requires a closed effect boundary: source state
# operations could otherwise retain pointers not represented by the carry.
law loop_memory_pure_closed_row_is_isolated:
  {LoopMemory.isolated(M.EffectRow{Nil{}, M.ClosedRow{}}) == True{} : Bool}

law loop_memory_foreign_closed_row_is_isolated:
  {LoopMemory.isolated(M.EffectRow{[M.foreign_identity()], M.ClosedRow{}}) == True{} : Bool}

law loop_memory_open_row_is_not_isolated:
  for operations: List<&2, M.TypeId>
  for index: Nat
  {LoopMemory.isolated(M.EffectRow{operations, M.RowVariable{index}}) == False{} : Bool}

law loop_memory_source_state_is_not_isolated:
  {LoopMemory.isolated(M.EffectRow{[M.TypeId{"game", "State.write"}], M.ClosedRow{}}) == False{} : Bool}

law retained_resolving_task_keeps_requirements:
  for position: Nat
  for module: M.Module
  for imports: List<&2, Groups.Interface>
  for checked: Groups.CheckedGroup
  for needs: List<&2, Groups.GroupNeeds>
  {Scheduler.check_task(Scheduler.RetainedEvidenceTask{position, module, imports, checked, needs}, Unit{}) == Scheduler.EvidenceOutcome{position, module, imports, Done{Groups.Resolving{checked, needs}}} : Scheduler.Outcome}

law conflicting_resolving_association_cannot_certify:
  for certificate: CheckedCore.Certificate
  {ResolvingCore.paired(ResolvingCore.Invalid{}, certificate) == None{} : Maybe<&2, ResolvingCore.Witness>}

# A cached shape-bound failure belongs only to tasks that require inference.

law seen_compact_dependency_enter_does_not_expand_neighbors:
  for identity: Nat
  for edges: NatIndex.Index<List<&2, Nat>>
  for +pending: List<&2, Dependency.CompactVisit>
  {Dependency.compact_events(False{}, identity, edges, pending) == pending : List<&2, Dependency.CompactVisit>}


law unknown_compact_dependency_reference_is_omitted:
  for +tail: List<&2, Nat>
  {Dependency.compact_numbered_reference(None{}, tail) == tail : List<&2, Nat>}

law specialization_without_inference_ignores_shape_failure:
  for expanded: Mono.ExpandedModule
  for configuration: Mono.Configuration
  for shapes: List<&2, Infer.Binding>
  for isolated: Bool
  for schemes: List<&2, StagingScheme.Scheme>
  for diagnostic: M.Diagnostic
  {Mono.infer_present_at(False{}, expanded, configuration, shapes, isolated, schemes, Fail{diagnostic}) == Done{expanded} : Result<&2, &2, M.Diagnostic, Mono.ExpandedModule>}

# Canonical reader/writer evidence may retain owner-quantified rows only after
# verifying its exact generated body and operation catalog. The handler uses
# residual row E; the action uses one handled operation plus E, retaining all
# duplicate labels. The concrete operation key comes from State.witness while
# the predicate keeps the original witness. This proof does not change the
# owning substitution or close its protected rows.
# Final row closure can touch only a selected flexible tail. A protected row
# must preserve the entire inference state, including its other substitutions.
law protected_selected_row_preserves_state:
  for index: Nat
  for +state: Infer.State
  {Mono.close_selected_one(True{}, index, state) == Done{state} : Result<&2, &2, M.Diagnostic, Infer.State>}

# Value variables and rigid or source-named effect tails are not closure
# candidates, even when they share a signature with a flexible effect tail.
law selected_signature_collects_only_flexible_effect_tail:
  for value: Nat
  for +row: Nat
  for parameter: Nat
  for +labels: List<&2, M.TypeId>
  for scope: String
  for name: String
  {Mono.signature_rows(M.ProductTy{[
    M.FunctionTy{M.VariableTy{value}, M.UnitTy{}, M.EffectRow{labels, M.RowVariable{row}}},
    M.FunctionTy{M.UnitTy{}, M.UnitTy{}, M.EffectRow{labels, M.RowParameter{parameter}}},
    M.FunctionTy{M.UnitTy{}, M.UnitTy{}, M.EffectRow{labels, M.FreeRow{scope, name}}}
  ]}) == Done{[row]} : Result<&2, &2, M.Diagnostic, List<&2, Nat>>}

# Replacing a selected tail with the empty row leaves every concrete label in
# place, including repeated occurrences of the same operation.
law closing_selected_tail_preserves_duplicate_operations:
  for +operation: M.TypeId
  {Rows.resolve([Rows.Binding{0n, M.empty_row()}], M.EffectRow{[operation, operation], M.RowVariable{0n}}) == M.EffectRow{[operation, operation], M.ClosedRow{}} : M.EffectRow}


# Dynamic arrays check multiplication before allocating into Wasm32 memory.
# Header plus the largest accepted payload stays below unsigned wraparound.
law runtime_array_byte_count_does_not_wrap:
  {U32.mul(U32.add(Wasm.runtime_array_max_count(), 1), 4) == 4294967292 : U32}

law runtime_memory_uses_wasm32_page_range:
  {Wasm.runtime_memory_max_pages() == 65536n : Nat}

# Saturation applies only after every parameter in a literal lambda chain is
# supplied. Partial applications preserve their closure-producing behavior.
law saturated_partial_application_is_not_expanded:
  for key: String
  for left: String
  for right: String
  for body: M.Expr
  for argument: M.Expr
  {Saturation.arity_match(Some{Saturation.Definition{key, [left, right], body}}, [argument]) == None{} : Maybe<&2, Saturation.Candidate>}

# Statically named functions can use the existing direct unary entry without
# changing the calling convention for escaping function values.
law saturated_known_head_uses_direct_call:
  for name: String
  for argument: M.Expr
  {Saturation.direct_head(256n, M.FunctionExpr{name}, argument) == M.CallExpr{name, argument} : M.Expr}

# Moving a compaction loop into another function can change arena ownership.
law saturated_compaction_loop_is_not_inlineable:
  for state: String
  for initial: M.Expr
  for body: M.Expr
  {Saturation.body_cost(256n, [M.ForeverExpr{state, initial, body}], 0n) == 97n : Nat}

# Ownership analysis is scoped to instruction jobs; duplicated counted loops
# must not merge their binder usage counts and lose in-place array updates.
law saturated_counted_loop_is_not_inlineable:
  for index: String
  for start: M.Expr
  for end: M.Expr
  for state: String
  for initial: M.Expr
  for body: M.Expr
  {Saturation.body_cost(256n, [M.ForExpr{index, start, end, state, initial, body}], 0n) == 97n : Nat}

# Collector layout hints are justified by expression constructors, never by
# pointer-looking bits or the names of erased local bindings.
law scalar_u32_result_is_pointer_free:
  for value: U32
  {Wasm.scalar_word(Codegen.U32Expr{value}) == True{} : Bool}

law unknown_local_result_keeps_conservative_tracing:
  for name: String
  {Wasm.scalar_word(Codegen.LocalExpr{name}) == False{} : Bool}

law closure_result_keeps_conservative_tracing:
  for key: String
  for captures: List<&2, String>
  {Wasm.scalar_word(Codegen.ClosureExpr{key, captures}) == False{} : Bool}

law projected_array_element_keeps_conservative_tracing:
  for array: Codegen.Expr
  for index: Codegen.Expr
  {Wasm.scalar_word(Codegen.ArrayGetExpr{array, index}) == False{} : Bool}
