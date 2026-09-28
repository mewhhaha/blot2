(* Native semantic port of compiler/native_session.bend.

   Source SHA-256: 41000979b851136da8760dd0ea739c02a280bd9ee4f56f387b67268b133224dd

   Ownership/type arguments are erased; value types are checked by OCaml.

   No Bend interpreter or generated C/JavaScript is linked. *)

open Base

module M = Ox_model

module Main = Ox_main

module C = Ox_cst

module L = Ox_lower

module G = Ox_groups

module Const = Ox_const_eval

module W = Ox_wasm

module K = Ox_native_cache_keys

module R = Ox_native_response

module Index = Ox_index

module Scheduler = Ox_check_scheduler

module Chains = Ox_check_chain_plan

module Regions = Ox_check_regions

module B = Ox_inference_batch

module Plan = Ox_native_plan

module D = Ox_dependency

module Mono = Ox_monomorph

module Resolution = Ox_dispatch_resolution

module Families = Ox_effect_families

module Check = Ox_check

module Modules = Ox_source_modules

module CV = Ox_catalog_versions

module Entries = Ox_entry_points

type t_Mode =
  | AnalyzeMode
  | CompileMode
and 'v t_Cached =
  | Cached of ((Base.word32) list) list * 'v
and t_Lowered =
  | Lowered of C.t_Cst * int * M.t_Module * Plan.t_Scanned * ((Plan.t_Nominals) t_Cached) option
and t_Declaration =
  | Retained of int
  | Replaced of C.t_Cst
and t_InferencePlan =
  | IndependentPlan of int * (Scheduler.t_Scheduled) list
  | RegionPlan of (Chains.t_Chain) list * (Regions.t_Region) list
and t_State =
  | State of L.t_Prelude * ((Base.word32) list) option * (t_Lowered) Base.map * ((t_InferencePlan) t_Cached) option * ((G.t_CheckedGroup) t_Cached) Base.map * ((Const.t_Constants) t_Cached) Base.map * ((W.t_EntryCode) t_Cached) Base.map * (Mono.t_Cache) option * (CV.t_Revision) option
and t_Output =
  | Analyzed of Main.t_Analysis
  | Compiled of Main.t_PlannedArtifact
and t_Stats =
  | Stats of int * int * int * int * int * int * int * int
and t_Completion =
  | Completion of t_State * t_Output * t_Stats
and t_Counts =
  | Counts of int * int
and 'v t_Selected =
  | Selected of 'v * bool
and t_Lowering =
  | Lowering of (t_Lowered) list * (Plan.t_Scanned) list * t_Counts
and t_LoweringSelection =
  | LoweringHit of t_Lowered
  | LoweringMiss
and t_LoweringPlan =
  | LoweringPlan of (t_LoweringSelection) list * (C.t_Cst) list
and t_NominalContext =
  | NominalContext of (Base.word32) list * (M.t_TypeId) Base.map
and t_NominalRevision =
  | NominalRevision of (t_Lowered) Base.map * Plan.t_Nominals
and t_PreparedPlanning =
  | PreparedPlanning of (t_Lowered) Base.map * G.t_Planning
and t_CheckedGroups =
  | CheckedGroups of ((G.t_CheckedGroup) t_Cached) Base.map * (G.t_Interface) Base.map * (M.t_CheckedFunction) Base.map * (M.t_CheckedConstant) Base.map * (Base.set) Base.map * ((Base.word32) list) Base.map * t_Counts
and t_CheckCatalog =
  | CheckCatalog of Scheduler.t_Catalog * CV.t_Revision
and t_GroupSelection =
  | GroupHit of G.t_CheckedGroup
  | GroupMiss of Scheduler.t_Task
  | GroupChecked of G.t_CheckedGroup
and t_PreparedGroup =
  | PreparedGroup of int * Base.text * (Base.text) list * Base.set * (Base.word32) list * ((Base.word32) list) list * t_GroupSelection
and t_GroupPreparation =
  | GroupPreparation of int * (M.t_Diagnostic, t_PreparedGroup) Base.result_
and t_GroupProgress =
  | GroupProgress of t_CheckedGroups * (Scheduler.t_Failure) option
and t_GroupPreparationContext =
  | GroupPreparationContext of t_CheckCatalog * ((G.t_CheckedGroup) t_Cached) Base.map * t_CheckedGroups
and t_ChainContext =
  | ChainContext of t_CheckCatalog * ((G.t_CheckedGroup) t_Cached) Base.map * (G.t_Interface) Base.map * (Base.set) Base.map * (Scheduler.t_Failure) option
and t_Evaluated =
  | Evaluated of ((Const.t_Constants) t_Cached) Base.map * Const.t_Constants * t_Counts
and t_CompiledEntries =
  | CompiledEntries of ((W.t_EntryCode) t_Cached) Base.map * (W.t_EntryCode) list * t_Counts
and t_EntrySelection =
  | ReusedEntry of Base.text * (Base.word32) list * W.t_EntryCode
  | FreshEntry of Base.text * (Base.word32) list
and t_EntryPlan =
  | EntryPlan of (t_EntrySelection) list * (W.t_CodegenJob) list * (M.t_Diagnostic) option
and t_KeyedEntry =
  | KeyedEntry of W.t_CodegenJob * (M.t_Diagnostic, (Base.word32) list) Base.result_
and t_PreparedEntry =
  | PreparedEntry of Base.text * (Base.word32) list * (W.t_EntryCode) t_Selected
and t_ResolvedDeclarations =
  | ResolvedDeclarations of (C.t_Cst) list * Base.set
and t_ProjectContext =
  | ProjectContext of (t_Lowered) Base.map * int
and t_ProjectLowering =
  | ProjectLowering of t_Lowering * M.t_Module

let s_0 = Base.text_of_utf8 "internal_error"

let s_1 = Base.text_of_utf8 "incremental plan omitted a required checked dependency"

let s_2 = Base.text_of_utf8 "native_session"

let s_3 = Base.text_of_utf8 "lowering batch returned a different declaration count"

let s_4 = Base.text_of_utf8 "nominal scan was not prepared"

let s_5 = Base.text_of_utf8 "incremental planner returned an empty declaration group"

let s_6 = Base.text_of_utf8 "inference batch changed declaration group order"

let s_7 = Base.text_of_utf8 "inference batch returned an unexpected declaration group"

let s_8 = Base.text_of_utf8 "inference batch omitted a declaration group"

let s_9 = Base.text_of_utf8 "dependency frontier count exceeds its declaration group count"

let s_10 = Base.text_of_utf8 "dependency chain frontiers exceed their declaration group count"

let s_11 = Base.text_of_utf8 "codegen"

let s_12 = Base.text_of_utf8 "incremental codegen results do not match the miss plan"

let s_13 = Base.text_of_utf8 "offset:"

let s_14 = Base.text_of_utf8 "declaration identities must be unique within a revision"

let s_15 = Base.text_of_utf8 "main"

let s_16 = Base.text_of_utf8 "retained declaration is absent from the last successful revision"

let s_17 = Base.text_of_utf8 "replacement must have the declarations field"

let s_18 = Base.text_of_utf8 "declarations"

let s_19 = Base.text_of_utf8 "module"

let s_20 = Base.text_of_utf8 ""

let s_21 = Base.text_of_utf8 "retained declaration marker is malformed"

let s_22 = Base.text_of_utf8 "retained_declaration"

let s_23 = Base.text_of_utf8 "body"

let s_24 = Base.text_of_utf8 "attributes"

let s_25 = Base.text_of_utf8 "value"

let s_26 = Base.text_of_utf8 "modules"

let s_27 = Base.text_of_utf8 "source_project"

let rec (* native_session.bend:83 *)
f_selected_value : 'v. ('v) t_Selected -> 'v =
fun v_chosen ->
(let (Selected (v_value, v_reused)) = v_chosen in
v_value)
and (* native_session.bend:87 *)
f_selected_reused : 'v. ('v) t_Selected -> bool =
fun v_chosen ->
(let (Selected (v_value, v_reused)) = v_chosen in
v_reused)
and (* native_session.bend:91 *)
f_count : t_Counts -> bool -> t_Counts =
fun v_counts v_reused ->
(match (v_counts, v_reused) with
| ((Counts (v_fresh, v_old)), true) ->
(Counts (v_fresh, (Base.nat_add 1 v_old)))
| ((Counts (v_fresh, v_old)), false) ->
(Counts ((Base.nat_add 1 v_fresh), v_old)))
and (* native_session.bend:98 *)
f_key_parts_same : ((Base.word32) list) list -> ((Base.word32) list) list -> bool -> bool =
fun v_left v_right v_same ->
(match (v_left, v_right, v_same) with
| (_, _, false) ->
false
| ([], [], true) ->
true
| ((v_a :: v_xs), (v_b :: v_ys), true) ->
(f_key_parts_same (v_xs) (v_ys) ((K.f_same (v_a) (v_b))))
| (_, _, _) ->
false)
and (* native_session.bend:109 *)
f_cached_if : 'v. bool -> 'v -> ('v) option =
fun v_same v_value ->
(match v_same with
| true ->
(Some (v_value))
| false ->
None)
and (* native_session.bend:116 *)
f_cached : 'v. (('v) t_Cached) option -> ((Base.word32) list) list -> ('v) option =
fun v_previous v_keys ->
(match v_previous with
| None ->
None
| (Some ((Cached (v_prior, v_value)))) ->
(f_cached_if ((f_key_parts_same (v_prior) (v_keys) (true))) (v_value)))
and (* native_session.bend:123 *)
f_required : 'v. ('v) option -> Base.text -> (M.t_Diagnostic, 'v) Base.result_ =
fun v_found v_name ->
(match v_found with
| (Some (v_value)) ->
(Done (v_value))
| None ->
(Fail ((M.Diagnostic (s_0, v_name, s_1)))))
and (* native_session.bend:130 *)
f_open : C.t_Cst -> int -> (M.t_Diagnostic, t_State) Base.result_ =
fun v_prelude v_fuel ->
(match (L.f_prepare_prelude (v_prelude) (v_fuel)) with
| Fail __error -> Fail __error
| Done v_prepared ->
(Done ((State (v_prepared, None, (Base.map_new ()), None, (Base.map_new ()), (Base.map_new ()), (Base.map_new ()), None, None)))))
and (* native_session.bend:138 *)
f_lowered_fragment : t_Lowered -> M.t_Module =
fun v_lowered ->
(let (Lowered (v_node, v_fuel, v_fragment, v_scanned, v_nominals)) = v_lowered in
v_fragment)
and (* native_session.bend:142 *)
f_lowered_scan : t_Lowered -> Plan.t_Scanned =
fun v_lowered ->
(let (Lowered (v_node, v_fuel, v_fragment, v_scanned, v_nominals)) = v_lowered in
v_scanned)
and (* native_session.bend:146 *)
f_source_equal : bool -> C.t_Cst -> C.t_Cst -> bool =
fun v_retained v_previous v_node ->
(match v_retained with
| true ->
true
| false ->
(K.f_same_cst (v_previous) (v_node)))
and (* native_session.bend:153 *)
f_retained_declaration : (unit) option -> bool =
fun v_found ->
(match v_found with
| (Some (v_value)) ->
true
| None ->
false)
and (* native_session.bend:160 *)
f_lower_hit : (t_Lowered) option -> C.t_Cst -> int -> bool -> (t_Lowered) option =
fun v_found v_node v_fuel v_retained ->
(match v_found with
| None ->
None
| (Some ((Lowered (v_prior, v_budget, v_fragment, v_scanned, v_nominals)))) ->
(f_cached_if ((Base.bool_and ((f_source_equal (v_retained) (v_prior) (v_node))) ((Base.nat_is_le (v_budget) (v_fuel))))) ((Lowered (v_prior, v_budget, v_fragment, v_scanned, v_nominals)))))
and (* native_session.bend:174 *)
f_select_lowering : (t_Lowered) option -> C.t_Cst -> t_LoweringPlan -> t_LoweringPlan =
fun v_found v_node v_plan ->
(match (v_found, v_plan) with
| ((Some (v_value)), (LoweringPlan (v_selections, v_missing))) ->
(LoweringPlan (((LoweringHit (v_value)) :: v_selections), v_missing))
| (None, (LoweringPlan (v_selections, v_missing))) ->
(LoweringPlan ((LoweringMiss :: v_selections), (v_node :: v_missing))))
and (* native_session.bend:181 *)
f_plan_lowering : (C.t_Cst) list -> int -> (t_Lowered) Base.map -> Base.set -> t_LoweringPlan -> t_LoweringPlan =
fun v_nodes v_fuel v_previous v_retained v_plan ->
(match v_nodes with
| [] ->
(let (LoweringPlan (v_selections, v_missing)) = v_plan in
(LoweringPlan ((Base.list_reverse (v_selections)), (Base.list_reverse (v_missing)))))
| (v_node :: v_tail) ->
(let v_owner = (Base.nat_show ((C.f_offset_of (v_node)))) in
(let v_found = (f_lower_hit ((Index.f_find (v_previous) (v_owner))) (v_node) (v_fuel) ((f_retained_declaration ((Index.f_find (v_retained) (v_owner)))))) in
(f_plan_lowering (v_tail) (v_fuel) (v_previous) (v_retained) ((f_select_lowering (v_found) (v_node) (v_plan)))))))
and (* native_session.bend:191 *)
f_lower_missing_leaf : (C.t_Cst) list -> L.t_Context -> int -> (t_Lowered) list -> (M.t_Diagnostic, (t_Lowered) list) Base.result_ =
fun v_nodes v_scope v_fuel v_reversed ->
(match v_nodes with
| [] ->
(Done ((Base.list_reverse (v_reversed))))
| (v_node :: v_tail) ->
(match (L.f_lower_source_declaration (v_node) (v_scope) (v_fuel)) with
| Fail __error -> Fail __error
| Done v_fragment ->
(f_lower_missing_leaf (v_tail) (v_scope) (v_fuel) (((Lowered (v_node, v_fuel, v_fragment, (Plan.f_scan (v_fragment)), None)) :: v_reversed)))))
and (* native_session.bend:202 *)
f_merge_lowered : (M.t_Diagnostic, (t_Lowered) list) Base.result_ -> (M.t_Diagnostic, (t_Lowered) list) Base.result_ -> (M.t_Diagnostic, (t_Lowered) list) Base.result_ =
fun v_left v_right ->
(match v_left with
| Fail __error -> Fail __error
| Done v_a ->
(match v_right with
| Fail __error -> Fail __error
| Done v_b ->
(Done ((Base.list_reverse_go ((Base.list_reverse (v_a))) (v_b))))))
and (* native_session.bend:208 *)
f_lower_missing_batch : L.t_DeclarationBatch -> L.t_Context -> int -> (M.t_Diagnostic, (t_Lowered) list) Base.result_ =
fun v_batch v_scope v_fuel ->
(match v_batch with
| (L.DeclarationLeaf (v_nodes)) ->
(f_lower_missing_leaf (v_nodes) (v_scope) (v_fuel) ([]))
| (L.DeclarationFork ((L.DeclarationFork ((L.DeclarationFork (v_a, v_b)), (L.DeclarationFork (v_c, v_d)))), (L.DeclarationFork ((L.DeclarationFork (v_e, v_f)), (L.DeclarationFork (v_g, v_h)))))) ->
(let (v_ra, v_rb, v_rc, v_rd, v_re, v_rf, v_rg, v_rh) = Native_parallel.eight (fun () -> (f_lower_missing_batch (v_a) (v_scope) (v_fuel))) (fun () -> (f_lower_missing_batch (v_b) (v_scope) (v_fuel))) (fun () -> (f_lower_missing_batch (v_c) (v_scope) (v_fuel))) (fun () -> (f_lower_missing_batch (v_d) (v_scope) (v_fuel))) (fun () -> (f_lower_missing_batch (v_e) (v_scope) (v_fuel))) (fun () -> (f_lower_missing_batch (v_f) (v_scope) (v_fuel))) (fun () -> (f_lower_missing_batch (v_g) (v_scope) (v_fuel))) (fun () -> (f_lower_missing_batch (v_h) (v_scope) (v_fuel))) in
(f_merge_lowered ((f_merge_lowered ((f_merge_lowered (v_ra) (v_rb))) ((f_merge_lowered (v_rc) (v_rd))))) ((f_merge_lowered ((f_merge_lowered (v_re) (v_rf))) ((f_merge_lowered (v_rg) (v_rh)))))))
| (L.DeclarationFork ((L.DeclarationFork (v_a, v_b)), (L.DeclarationFork (v_c, v_d)))) ->
(let (v_ra, v_rb, v_rc, v_rd) = Native_parallel.four (fun () -> (f_lower_missing_batch (v_a) (v_scope) (v_fuel))) (fun () -> (f_lower_missing_batch (v_b) (v_scope) (v_fuel))) (fun () -> (f_lower_missing_batch (v_c) (v_scope) (v_fuel))) (fun () -> (f_lower_missing_batch (v_d) (v_scope) (v_fuel))) in
(f_merge_lowered ((f_merge_lowered (v_ra) (v_rb))) ((f_merge_lowered (v_rc) (v_rd)))))
| (L.DeclarationFork (v_left, v_right)) ->
(let (v_a, v_b) = Native_parallel.two (fun () -> (f_lower_missing_batch (v_left) (v_scope) (v_fuel))) (fun () -> (f_lower_missing_batch (v_right) (v_scope) (v_fuel))) in
(f_merge_lowered (v_a) (v_b))))
and (* native_session.bend:222 *)
f_publish_lowered : (t_LoweringSelection) list -> (t_Lowered) list -> (t_Lowered) list -> (Plan.t_Scanned) list -> t_Counts -> (M.t_Diagnostic, t_Lowering) Base.result_ =
fun v_selections v_missing v_reversed v_scans v_counts ->
(match (v_selections, v_missing) with
| ([], []) ->
(Done ((Lowering ((Base.list_reverse (v_reversed)), (Base.list_reverse (v_scans)), v_counts))))
| (((LoweringHit (v_lowered)) :: v_tail), _) ->
(f_publish_lowered (v_tail) (v_missing) ((v_lowered :: v_reversed)) (((f_lowered_scan (v_lowered)) :: v_scans)) ((f_count (v_counts) (true))))
| ((LoweringMiss :: v_tail), (v_lowered :: v_rest)) ->
(f_publish_lowered (v_tail) (v_rest) ((v_lowered :: v_reversed)) (((f_lowered_scan (v_lowered)) :: v_scans)) ((f_count (v_counts) (false))))
| (_, _) ->
(Fail ((M.Diagnostic (s_0, s_2, s_3)))))
and (* native_session.bend:233 *)
f_lower_plan : t_LoweringPlan -> L.t_Context -> int -> (M.t_Diagnostic, t_Lowering) Base.result_ =
fun v_plan v_scope v_fuel ->
(let (LoweringPlan (v_selections, v_missing)) = v_plan in
(let v_missing_count = (Base.list_length (v_missing)) in
(match (f_lower_missing_batch ((L.f_declaration_batches (48) (v_missing) (v_missing_count) ((Base.nat_is_le (v_missing_count) (4))))) (v_scope) (v_fuel)) with
| Fail __error -> Fail __error
| Done v_lowered ->
(f_publish_lowered (v_selections) (v_lowered) ([]) ([]) ((Counts (0, 0)))))))
and (* native_session.bend:240 *)
f_reusable_scope : ((Base.word32) list) option -> (Base.word32) list -> (t_Lowered) Base.map -> (t_Lowered) Base.map =
fun v_previous v_key v_declarations ->
(match v_previous with
| None ->
(Base.map_new ())
| (Some (v_prior)) ->
(Base.bool_pick ((K.f_same (v_prior) (v_key))) (v_declarations) ((Base.map_new ()))))
and (* native_session.bend:247 *)
f_combine_fragments : (M.t_Module) list -> M.t_Module =
fun v_fragments ->
(match v_fragments with
| [] ->
(M.Module ([], [], [], []))
| (v_head :: v_tail) ->
(L.f_combine_modules (v_head) ((f_combine_fragments (v_tail)))))
and (* native_session.bend:257 *)
f_select_nominals : (Plan.t_Nominals) option -> M.t_Module -> (M.t_TypeId) Base.map -> Plan.t_Nominals =
fun v_found v_fragment v_constructors ->
(match v_found with
| (Some (v_scanned)) ->
v_scanned
| None ->
(Plan.f_nominal_scan (v_fragment) (v_constructors)))
and (* native_session.bend:264 *)
f_refresh_nominals : t_Lowered -> t_NominalContext -> t_Lowered =
fun v_lowered v_context ->
(let (Lowered (v_node, v_fuel, v_fragment, v_scanned, v_nominals)) = v_lowered in
(let (NominalContext (v_key, v_constructors)) = v_context in
(let v_found = (f_select_nominals ((f_cached (v_nominals) ([v_key]))) (v_fragment) (v_constructors)) in
(Lowered (v_node, v_fuel, v_fragment, v_scanned, (Some ((Cached ([v_key], v_found)))))))))
and (* native_session.bend:270 *)
f_sum_costs : (int) list -> int -> int =
fun v_costs v_total ->
(match v_costs with
| [] ->
v_total
| (v_head :: v_tail) ->
(f_sum_costs (v_tail) ((Base.nat_add (v_total) (v_head)))))
and (* native_session.bend:277 *)
f_nominal_cost : (Plan.t_Nominals) option -> Plan.t_Scanned -> int =
fun v_found v_scanned ->
(match v_found with
| (Some (v_value)) ->
1
| None ->
(let (Plan.Scanned (v_functions, v_constants, v_costs)) = v_scanned in
(f_sum_costs ((Base.map_values (v_costs))) (16))))
and (* native_session.bend:285 *)
f_nominal_tasks : (t_Lowered) list -> (Base.word32) list -> ((t_Lowered) B.t_Weighted) list =
fun v_values v_key ->
(match v_values with
| [] ->
[]
| (v_value :: v_tail) ->
(let (Lowered (v_node, v_fuel, v_fragment, v_scanned, v_nominals)) = v_value in
(let v_cost = (f_nominal_cost ((f_cached (v_nominals) ([v_key]))) (v_scanned)) in
((B.Weighted (v_value, v_cost)) :: (f_nominal_tasks (v_tail) (v_key))))))
and (* native_session.bend:297 *)
f_merge_nominal_revision : Plan.t_Nominals -> t_NominalRevision -> t_NominalRevision =
fun v_found v_rest ->
(let (NominalRevision (v_declarations, v_usages)) = v_rest in
(NominalRevision (v_declarations, (Plan.f_merge_nominals (v_found) (v_usages)))))
and (* native_session.bend:301 *)
f_publish_nominals : (t_Lowered) list -> (t_Lowered) Base.map -> (M.t_Diagnostic, t_NominalRevision) Base.result_ =
fun v_values v_next ->
(match v_values with
| [] ->
(Done ((NominalRevision (v_next, (Plan.Nominals ((Done ([])), (Done ([]))))))))
| ((Lowered (v_node, v_fuel, v_fragment, v_scanned, None)) :: v_tail) ->
(Fail ((M.Diagnostic (s_0, s_2, s_4))))
| ((Lowered (v_node, v_fuel, v_fragment, v_scanned, (Some ((Cached (v_keys, v_found)))))) :: v_tail) ->
(let v_value = (Lowered (v_node, v_fuel, v_fragment, v_scanned, (Some ((Cached (v_keys, v_found)))))) in
(match (f_publish_nominals (v_tail) ((Base.map_set (v_next) ((Base.nat_show ((C.f_offset_of (v_node))))) (v_value)))) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done ((f_merge_nominal_revision (v_found) (v_rest)))))))
and (* native_session.bend:313 *)
f_nominal_declarations : t_NominalRevision -> (t_Lowered) Base.map =
fun v_revision ->
(let (NominalRevision (v_declarations, v_usages)) = v_revision in
v_declarations)
and (* native_session.bend:317 *)
f_nominal_usages : t_NominalRevision -> Plan.t_Nominals -> (M.t_Diagnostic, (G.t_DeclarationUsage) list) Base.result_ =
fun v_revision v_prelude ->
(let (NominalRevision (v_declarations, v_usages)) = v_revision in
(Plan.f_nominal_usages ((Plan.f_merge_nominals (v_prelude) (v_usages)))))
and (* native_session.bend:323 *)
f_cache_nominal_scans : (Plan.t_Scanned) list -> int -> int -> bool =
fun v_scans v_work v_count ->
(match v_scans with
| [] ->
(Base.bool_and ((Base.nat_is_gt (v_count) (0))) ((Base.nat_is_ge (v_work) ((Base.nat_mul (v_count) (256))))))
| ((Plan.Scanned (v_functions, v_constants, v_costs)) :: v_tail) ->
(f_cache_nominal_scans (v_tail) ((f_sum_costs ((Base.map_values (v_costs))) (v_work))) ((Base.nat_add 1 v_count))))
and (* native_session.bend:330 *)
f_index_lowered : (t_Lowered) list -> (t_Lowered) Base.map -> (t_Lowered) Base.map =
fun v_values v_next ->
(match v_values with
| [] ->
v_next
| ((Lowered (v_node, v_fuel, v_fragment, v_scanned, v_nominals)) :: v_tail) ->
(f_index_lowered (v_tail) ((Base.map_set (v_next) ((Base.nat_show ((C.f_offset_of (v_node))))) ((Lowered (v_node, v_fuel, v_fragment, v_scanned, None)))))))
and (* native_session.bend:340 *)
f_planning_declarations : t_PreparedPlanning -> (t_Lowered) Base.map =
fun v_prepared ->
(let (PreparedPlanning (v_declarations, v_plan)) = v_prepared in
v_declarations)
and (* native_session.bend:344 *)
f_planning_value : t_PreparedPlanning -> G.t_Planning =
fun v_prepared ->
(let (PreparedPlanning (v_declarations, v_plan)) = v_prepared in
v_plan)
and (* native_session.bend:348 *)
f_module_types : M.t_Module -> (M.t_DataType) list =
fun v_module ->
(let (M.Module (v_constants, v_functions, v_types, v_operations)) = v_module in
v_types)
and (* native_session.bend:352 *)
f_prepare_planning : M.t_Module -> M.t_Module -> (t_Lowered) list -> (D.t_Node) list -> bool -> (M.t_Diagnostic, t_PreparedPlanning) Base.result_ =
fun v_module v_prelude v_values v_graph v_retain ->
(match v_retain with
| false ->
(match (G.f_prepare_plan_graph (v_module) ((Done (v_graph)))) with
| Fail __error -> Fail __error
| Done v_plan ->
(Done ((PreparedPlanning ((f_index_lowered (v_values) ((Base.map_new ()))), v_plan)))))
| true ->
(let v_types = (f_module_types (v_module)) in
(let v_constructors = (G.f_constructor_index (v_types) ((Base.map_new ()))) in
(match (K.f_encode ([(K.DataTypes (v_types))])) with
| Fail __error -> Fail __error
| Done v_key ->
(match (f_publish_nominals ((B.f_execute (f_refresh_nominals) ((B.f_plan ((f_nominal_tasks (v_values) (v_key))) (512))) ((NominalContext (v_key, v_constructors))))) ((Base.map_new ()))) with
| Fail __error -> Fail __error
| Done v_nominals ->
(match (G.f_prepare_plan_usages (v_module) ((Done (v_graph))) ((f_nominal_usages (v_nominals) ((Plan.f_nominal_scan (v_prelude) (v_constructors)))))) with
| Fail __error -> Fail __error
| Done v_plan ->
(Done ((PreparedPlanning ((f_nominal_declarations (v_nominals)), v_plan))))))))))
and (* native_session.bend:367 *)
f_inference_plan : (G.t_Job) list -> bool -> (M.t_Diagnostic, t_InferencePlan) Base.result_ =
fun v_jobs v_dependent ->
(match v_dependent with
| false ->
(match (Scheduler.f_schedule (v_jobs)) with
| Fail __error -> Fail __error
| Done v_scheduled ->
(Done ((IndependentPlan ((Base.list_length (v_jobs)), v_scheduled)))))
| true ->
(match (Chains.f_plan (v_jobs)) with
| Fail __error -> Fail __error
| Done v_chains ->
(match (Regions.f_rooted_plan (v_chains)) with
| Fail __error -> Fail __error
| Done v_rooted ->
(Done ((RegionPlan ((Regions.f_prefix (v_rooted)), (Regions.f_branches (v_rooted)))))))))
and (* native_session.bend:381 *)
f_select_plan : (t_InferencePlan) option -> G.t_Planning -> (M.t_Diagnostic, t_InferencePlan) Base.result_ =
fun v_found v_plan ->
(match v_found with
| (Some (v_scheduled)) ->
(Done (v_scheduled))
| None ->
(match (G.f_finish_plan (v_plan)) with
| Fail __error -> Fail __error
| Done v_jobs ->
(f_inference_plan (v_jobs) ((Scheduler.f_has_dependencies (v_jobs))))))
and (* native_session.bend:406 *)
f_check_catalog : t_CheckCatalog -> Scheduler.t_Catalog =
fun v_value ->
(let (CheckCatalog (v_catalog, v_revision)) = v_value in
v_catalog)
and (* native_session.bend:410 *)
f_check_revision : t_CheckCatalog -> CV.t_Revision =
fun v_value ->
(let (CheckCatalog (v_catalog, v_revision)) = v_value in
v_revision)
and (* native_session.bend:414 *)
f_empty_checked : unit -> t_CheckedGroups =
fun () ->
(CheckedGroups ((Base.map_new ()), (Base.map_new ()), (Base.map_new ()), (Base.map_new ()), (Base.map_new ()), (Base.map_new ()), (Counts (0, 0))))
and (* native_session.bend:417 *)
f_dependency_closure : (Base.text) list -> (Base.set) Base.map -> Base.set -> (M.t_Diagnostic, Base.set) Base.result_ =
fun v_names v_known v_found ->
(match v_names with
| [] ->
(Done (v_found))
| (v_name :: v_tail) ->
(match (f_required ((Index.f_find (v_known) (v_name))) (v_name)) with
| Fail __error -> Fail __error
| Done v_inherited ->
(f_dependency_closure (v_tail) (v_known) ((Base.map_union (v_found) (v_inherited))))))
and (* native_session.bend:426 *)
f_publish_closure : (Base.text) list -> Base.set -> (Base.set) Base.map -> (Base.set) Base.map =
fun v_names v_closure v_known ->
(match v_names with
| [] ->
v_known
| (v_name :: v_tail) ->
(f_publish_closure (v_tail) (v_closure) ((Base.map_set (v_known) (v_name) (v_closure)))))
and (* native_session.bend:433 *)
f_group_owner : (Base.text) list -> (M.t_Diagnostic, Base.text) Base.result_ =
fun v_members ->
(match v_members with
| (v_head :: v_tail) ->
(Done (v_head))
| [] ->
(Fail ((M.Diagnostic (s_0, s_2, s_5)))))
and (* native_session.bend:440 *)
f_checked_group_checked : G.t_CheckedGroup -> M.t_CheckedModule =
fun v_group ->
(let (G.CheckedGroup (v_checked, v_interfaces, v_uses)) = v_group in
v_checked)
and (* native_session.bend:444 *)
f_checked_group_interfaces : G.t_CheckedGroup -> (G.t_Interface) list =
fun v_group ->
(let (G.CheckedGroup (v_checked, v_interfaces, v_uses)) = v_group in
v_interfaces)
and (* native_session.bend:448 *)
f_publish_group : t_CheckedGroups -> Base.text -> (Base.text) list -> Base.set -> (Base.word32) list -> ((Base.word32) list) list -> (G.t_CheckedGroup) t_Selected -> t_CheckedGroups =
fun v_state v_owner v_members v_closure v_base_key v_keys v_selected ->
(let (CheckedGroups (v_groups, v_interfaces, v_functions, v_constants, v_closures, v_base_keys, v_counts)) = v_state in
(let v_value = (f_selected_value (v_selected)) in
(let v_checked = (f_checked_group_checked (v_value)) in
(let v_name = v_owner in
(CheckedGroups ((Base.map_set (v_groups) (v_name) ((Cached (v_keys, v_value)))), (Scheduler.f_publish_interfaces ((f_checked_group_interfaces (v_value))) (v_interfaces)), (Scheduler.f_publish_functions ((Main.f_checked_functions (v_checked))) (v_functions)), (Scheduler.f_publish_constants ((Main.f_checked_constants (v_checked))) (v_constants)), (f_publish_closure (v_members) (v_closure) (v_closures)), (Base.map_set (v_base_keys) (v_name) (v_base_key)), (f_count (v_counts) ((f_selected_reused (v_selected))))))))))
and (* native_session.bend:477 *)
f_select_group : (G.t_CheckedGroup) option -> int -> M.t_Module -> (G.t_Interface) list -> int -> t_GroupSelection =
fun v_found v_position v_module v_dependencies v_cost ->
(match v_found with
| (Some (v_value)) ->
(GroupHit (v_value))
| None ->
(GroupMiss ((Scheduler.Task (v_position, v_module, v_dependencies, v_cost)))))
and (* native_session.bend:486 *)
f_select_retained_group : (G.t_CheckedGroup) option -> t_CheckCatalog -> G.t_Job -> M.t_Module -> (G.t_Interface) list -> int -> int -> t_GroupSelection =
fun v_found v_known v_job v_subset v_imports v_position v_cost ->
(match v_found with
| (Some (v_value)) ->
(GroupHit (v_value))
| None ->
(f_select_group ((Scheduler.f_retained_group ((f_check_catalog (v_known))) (v_job) (v_subset) (v_imports))) (v_position) (v_subset) (v_imports) (v_cost)))
and (* native_session.bend:493 *)
f_prepare_group : int -> G.t_Job -> t_CheckCatalog -> ((G.t_CheckedGroup) t_Cached) Base.map -> t_CheckedGroups -> (M.t_Diagnostic, t_PreparedGroup) Base.result_ =
fun v_position v_job v_known v_previous v_state ->
(let (G.Job (v_members, v_dependencies, v_types)) = v_job in
(let (CheckedGroups (v_groups, v_interfaces, v_functions, v_constants, v_closures, v_base_keys, v_counts)) = v_state in
(match (f_group_owner ((Base.list_sort (Base.string_is_le) (v_members)))) with
| Fail __error -> Fail __error
| Done v_owner ->
(let v_subset = (Scheduler.f_group_module ((f_check_catalog (v_known))) ((G.Job (v_members, v_dependencies, v_types)))) in
(match (CV.f_group_key (v_subset) ((f_check_revision (v_known)))) with
| Fail __error -> Fail __error
| Done v_base_key ->
(match (Scheduler.f_dependency_interfaces (v_dependencies) (v_interfaces)) with
| Fail __error -> Fail __error
| Done v_imports ->
(match (K.f_interfaces (v_imports)) with
| Fail __error -> Fail __error
| Done v_imported_key ->
(let v_keys = [v_base_key; v_imported_key] in
(let v_selection = (f_select_retained_group ((f_cached ((Index.f_find (v_previous) (v_owner))) (v_keys))) (v_known) (v_job) (v_subset) (v_imports) (v_position) ((Base.list_length (v_base_key)))) in
(match (f_dependency_closure (v_dependencies) (v_closures) ((Base.set_add ((Base.set_new ())) (v_owner)))) with
| Fail __error -> Fail __error
| Done v_closure ->
(Done ((PreparedGroup (v_position, v_owner, v_members, v_closure, v_base_key, v_keys, v_selection))))))))))))))
and (* native_session.bend:510 *)
f_prepare_group_task : Scheduler.t_Scheduled -> t_GroupPreparationContext -> t_GroupPreparation =
fun v_scheduled v_context ->
(let (Scheduler.Scheduled (v_position, v_level, v_job)) = v_scheduled in
(let (GroupPreparationContext (v_known, v_previous, v_state)) = v_context in
(GroupPreparation (v_position, (f_prepare_group (v_position) (v_job) (v_known) (v_previous) (v_state))))))
and (* native_session.bend:515 *)
f_group_preparation_cost : G.t_Job -> t_CheckCatalog -> bool -> int =
fun v_job v_known v_small ->
(match v_small with
| true ->
0
| false ->
(Scheduler.f_group_cost ((f_check_catalog (v_known))) (v_job)))
and (* native_session.bend:522 *)
f_group_preparation_tasks : (Scheduler.t_Scheduled) list -> t_CheckCatalog -> (Scheduler.t_Failure) option -> bool -> ((Scheduler.t_Scheduled) B.t_Weighted) list -> bool -> ((Scheduler.t_Scheduled) B.t_Weighted) list =
fun v_ready v_known v_failure v_small v_reversed v_allowed ->
(match (v_ready, v_allowed) with
| ([], _) ->
(Base.list_reverse (v_reversed))
| (_, false) ->
(Base.list_reverse (v_reversed))
| (((Scheduler.Scheduled (v_position, v_level, v_job)) :: v_tail), true) ->
(let v_cost = (f_group_preparation_cost (v_job) (v_known) (v_small)) in
(f_group_preparation_tasks (v_tail) (v_known) (v_failure) (v_small) (((B.Weighted ((Scheduler.Scheduled (v_position, v_level, v_job)), v_cost)) :: v_reversed)) ((Scheduler.f_next_allowed (v_tail) (v_failure))))))
and (* native_session.bend:535 *)
f_prepare_groups : (Scheduler.t_Scheduled) list -> t_CheckCatalog -> ((G.t_CheckedGroup) t_Cached) Base.map -> t_CheckedGroups -> (Scheduler.t_Failure) option -> (t_GroupPreparation) list =
fun v_ready v_known v_previous v_state v_failure ->
(let v_tasks = (f_group_preparation_tasks (v_ready) (v_known) (v_failure) ((Base.nat_is_le ((Base.list_length (v_ready))) (4))) ([]) ((Scheduler.f_next_allowed (v_ready) (v_failure)))) in
(B.f_execute (f_prepare_group_task) ((B.f_plan (v_tasks) (2048))) ((GroupPreparationContext (v_known, v_previous, v_state)))))
and (* native_session.bend:539 *)
f_complete_preparation : (M.t_Diagnostic, t_PreparedGroup) Base.result_ -> (M.t_Diagnostic, t_PreparedGroup) Base.result_ =
fun v_prepared ->
(match v_prepared with
| (Done ((PreparedGroup (v_position, v_owner, v_members, v_closure, v_base_key, v_keys, (GroupMiss ((Scheduler.Task (v_index, v_module, v_dependencies, v_cost)))))))) ->
(match (G.f_check_group_planned (v_module) (v_dependencies)) with
| Fail __error -> Fail __error
| Done v_checked ->
(Done ((PreparedGroup (v_position, v_owner, v_members, v_closure, v_base_key, v_keys, (GroupChecked (v_checked)))))))
| v_other ->
v_other)
and (* native_session.bend:548 *)
f_check_group_task : Scheduler.t_Scheduled -> t_GroupPreparationContext -> t_GroupPreparation =
fun v_scheduled v_context ->
(let (Scheduler.Scheduled (v_position, v_level, v_job)) = v_scheduled in
(let (GroupPreparationContext (v_known, v_previous, v_state)) = v_context in
(GroupPreparation (v_position, (f_complete_preparation ((f_prepare_group (v_position) (v_job) (v_known) (v_previous) (v_state))))))))
and (* native_session.bend:555 *)
f_group_pipeline_grain : ((G.t_CheckedGroup) t_Cached) Base.map -> int =
fun v_previous ->
(match v_previous with
| MTip ->
(Scheduler.f_inference_grain ())
| _ ->
2048)
and (* native_session.bend:564 *)
f_check_groups : (Scheduler.t_Scheduled) list -> t_CheckCatalog -> ((G.t_CheckedGroup) t_Cached) Base.map -> t_CheckedGroups -> (Scheduler.t_Failure) option -> (t_GroupPreparation) list =
fun v_ready v_known v_previous v_state v_failure ->
(let v_tasks = (f_group_preparation_tasks (v_ready) (v_known) (v_failure) (false) ([]) ((Scheduler.f_next_allowed (v_ready) (v_failure)))) in
(B.f_execute (f_check_group_task) ((B.f_plan (v_tasks) ((f_group_pipeline_grain (v_previous))))) ((GroupPreparationContext (v_known, v_previous, v_state)))))
and (* native_session.bend:568 *)
f_group_tasks : (t_GroupPreparation) list -> (Scheduler.t_Task) list -> (Scheduler.t_Task) list =
fun v_prepared v_reversed ->
(match v_prepared with
| [] ->
(Base.list_reverse (v_reversed))
| ((GroupPreparation (v_position, (Done ((PreparedGroup (v_index, v_owner, v_members, v_closure, v_base_key, v_keys, (GroupMiss (v_task)))))))) :: v_tail) ->
(f_group_tasks (v_tail) ((v_task :: v_reversed)))
| (v_head :: v_tail) ->
(f_group_tasks (v_tail) (v_reversed)))
and (* native_session.bend:577 *)
f_group_failure : t_GroupProgress -> int -> M.t_Diagnostic -> t_GroupProgress =
fun v_progress v_position v_diagnostic ->
(let (GroupProgress (v_checked, v_failure)) = v_progress in
(GroupProgress (v_checked, (Scheduler.f_first_failure (v_failure) ((Scheduler.Failure (v_position, v_diagnostic)))))))
and (* native_session.bend:581 *)
f_group_success : t_GroupProgress -> Base.text -> (Base.text) list -> Base.set -> (Base.word32) list -> ((Base.word32) list) list -> (G.t_CheckedGroup) t_Selected -> t_GroupProgress =
fun v_progress v_owner v_members v_closure v_base_key v_keys v_selected ->
(let (GroupProgress (v_checked, v_failure)) = v_progress in
(GroupProgress ((f_publish_group (v_checked) (v_owner) (v_members) (v_closure) (v_base_key) (v_keys) (v_selected)), v_failure)))
and (* native_session.bend:585 *)
f_publish_group_result : (M.t_Diagnostic, G.t_CheckedGroup) Base.result_ -> t_GroupProgress -> int -> Base.text -> (Base.text) list -> Base.set -> (Base.word32) list -> ((Base.word32) list) list -> t_GroupProgress =
fun v_result v_progress v_position v_owner v_members v_closure v_base_key v_keys ->
(match v_result with
| (Fail (v_diagnostic)) ->
(f_group_failure (v_progress) (v_position) (v_diagnostic))
| (Done (v_checked)) ->
(f_group_success (v_progress) (v_owner) (v_members) (v_closure) (v_base_key) (v_keys) ((Selected (v_checked, false)))))
and (* native_session.bend:592 *)
f_checked_outcome : Scheduler.t_Outcome -> int -> (M.t_Diagnostic, G.t_CheckedGroup) Base.result_ =
fun v_outcome v_expected ->
(match v_outcome with
| (Scheduler.Outcome (v_position, v_checked)) ->
(Base.bool_pick ((Base.nat_is_eq (v_position) (v_expected))) (v_checked) ((Fail ((M.Diagnostic (s_0, s_2, s_6))))))
| (Scheduler.EvidenceOutcome (v_position, v_module, v_imports, v_checked)) ->
(Base.bool_pick ((Base.nat_is_eq (v_position) (v_expected))) ((Scheduler.f_resolving_checked (v_checked))) ((Fail ((M.Diagnostic (s_0, s_2, s_6)))))))
and (* native_session.bend:599 *)
f_publish_prepared : (t_GroupPreparation) list -> (Scheduler.t_Outcome) list -> t_GroupProgress -> t_GroupProgress =
fun v_prepared v_outcomes v_progress ->
(match (v_prepared, v_outcomes) with
| ([], []) ->
v_progress
| ([], _) ->
(f_group_failure (v_progress) (0) ((M.Diagnostic (s_0, s_2, s_7))))
| (((GroupPreparation (v_position, (Fail (v_diagnostic)))) :: v_tail), v_remaining) ->
(f_publish_prepared (v_tail) (v_remaining) ((f_group_failure (v_progress) (v_position) (v_diagnostic))))
| (((GroupPreparation (v_position, (Done ((PreparedGroup (v_index, v_owner, v_members, v_closure, v_base_key, v_keys, (GroupHit (v_checked)))))))) :: v_tail), v_remaining) ->
(f_publish_prepared (v_tail) (v_remaining) ((f_group_success (v_progress) (v_owner) (v_members) (v_closure) (v_base_key) (v_keys) ((Selected (v_checked, true))))))
| (((GroupPreparation (v_position, (Done ((PreparedGroup (v_index, v_owner, v_members, v_closure, v_base_key, v_keys, (GroupChecked (v_checked)))))))) :: v_tail), v_remaining) ->
(f_publish_prepared (v_tail) (v_remaining) ((f_group_success (v_progress) (v_owner) (v_members) (v_closure) (v_base_key) (v_keys) ((Selected (v_checked, false))))))
| (((GroupPreparation (v_position, (Done ((PreparedGroup (v_index, v_owner, v_members, v_closure, v_base_key, v_keys, (GroupMiss (v_task)))))))) :: v_tail), []) ->
(f_group_failure (v_progress) (v_position) ((M.Diagnostic (s_0, s_2, s_8))))
| (((GroupPreparation (v_position, (Done ((PreparedGroup (v_index, v_owner, v_members, v_closure, v_base_key, v_keys, (GroupMiss (v_task)))))))) :: v_tail), (v_outcome :: v_remaining)) ->
(f_publish_prepared (v_tail) (v_remaining) ((f_publish_group_result ((f_checked_outcome (v_outcome) (v_position))) (v_progress) (v_position) (v_owner) (v_members) (v_closure) (v_base_key) (v_keys)))))
and (* native_session.bend:616 *)
f_check_single_group : Scheduler.t_Scheduled -> t_CheckCatalog -> ((G.t_CheckedGroup) t_Cached) Base.map -> t_GroupProgress -> bool -> t_GroupProgress =
fun v_scheduled v_known v_previous v_progress v_allowed ->
(match (v_progress, v_allowed) with
| (v_prior, false) ->
v_prior
| ((GroupProgress (v_state, v_failure)), true) ->
(f_publish_prepared ([(f_check_group_task (v_scheduled) ((GroupPreparationContext (v_known, v_previous, v_state))))]) ([]) ((GroupProgress (v_state, v_failure)))))
and (* native_session.bend:623 *)
f_check_frontier_sized : (Scheduler.t_Scheduled) list -> t_CheckCatalog -> ((G.t_CheckedGroup) t_Cached) Base.map -> t_GroupProgress -> bool -> t_GroupProgress =
fun v_ready v_known v_previous v_progress v_small ->
(match (v_progress, v_small) with
| ((GroupProgress (v_state, v_failure)), true) ->
(let v_prepared = (f_prepare_groups (v_ready) (v_known) (v_previous) (v_state) (v_failure)) in
(f_publish_prepared (v_prepared) ((Scheduler.f_check_batch_planned ((f_group_tasks (v_prepared) ([]))))) ((GroupProgress (v_state, v_failure)))))
| ((GroupProgress (v_state, v_failure)), false) ->
(f_publish_prepared ((f_check_groups (v_ready) (v_known) (v_previous) (v_state) (v_failure))) ([]) ((GroupProgress (v_state, v_failure)))))
and (* native_session.bend:631 *)
f_frontier_cost : (Scheduler.t_Scheduled) list -> t_CheckCatalog -> int -> int =
fun v_ready v_known v_cost ->
(match v_ready with
| [] ->
v_cost
| ((Scheduler.Scheduled (v_position, v_level, v_job)) :: v_tail) ->
(f_frontier_cost (v_tail) (v_known) ((Base.nat_add (v_cost) ((Scheduler.f_group_cost ((f_check_catalog (v_known))) (v_job)))))))
and (* native_session.bend:640 *)
f_staged_frontier : (Scheduler.t_Scheduled) list -> t_CheckCatalog -> bool -> bool =
fun v_ready v_known v_small ->
(match v_small with
| true ->
true
| false ->
(Base.nat_is_lt ((f_frontier_cost (v_ready) (v_known) (0))) ((Base.nat_mul ((Base.list_length (v_ready))) (256)))))
and (* native_session.bend:647 *)
f_check_frontier : (Scheduler.t_Scheduled) list -> t_CheckCatalog -> ((G.t_CheckedGroup) t_Cached) Base.map -> t_GroupProgress -> t_GroupProgress =
fun v_ready v_known v_previous v_progress ->
(match v_ready with
| [] ->
v_progress
| ((Scheduler.Scheduled (v_position, v_level, v_job)) :: []) ->
(let (GroupProgress (v_state, v_failure)) = v_progress in
(f_check_single_group ((Scheduler.Scheduled (v_position, v_level, v_job))) (v_known) (v_previous) (v_progress) ((Scheduler.f_precedes_failure (v_position) (v_failure)))))
| v_remaining ->
(f_check_frontier_sized (v_remaining) (v_known) (v_previous) (v_progress) ((f_staged_frontier (v_remaining) (v_known) ((Base.nat_is_le ((Base.list_length (v_remaining))) (4)))))))
and (* native_session.bend:657 *)
f_finish_groups : t_GroupProgress -> (M.t_Diagnostic, t_CheckedGroups) Base.result_ =
fun v_progress ->
(match v_progress with
| (GroupProgress (v_checked, None)) ->
(Done (v_checked))
| (GroupProgress (v_checked, (Some ((Scheduler.Failure (v_position, v_diagnostic)))))) ->
(Fail (v_diagnostic)))
and (* native_session.bend:666 *)
f_check_frontiers : int -> Scheduler.t_Frontier -> t_CheckCatalog -> ((G.t_CheckedGroup) t_Cached) Base.map -> t_GroupProgress -> (M.t_Diagnostic, t_CheckedGroups) Base.result_ =
fun v_fuel v_frontier v_known v_previous v_progress ->
(match (v_fuel, v_frontier) with
| (_, (Scheduler.Frontier ([], []))) ->
(f_finish_groups (v_progress))
| (0, _) ->
(Fail ((M.Diagnostic (s_0, s_2, s_9))))
| (__nat_1, (Scheduler.Frontier (v_ready, v_pending))) when __nat_1 >= 1 ->
(let v_rest = (__nat_1 - 1) in
(f_check_frontiers (v_rest) ((Scheduler.f_next_frontier (v_pending))) (v_known) (v_previous) ((f_check_frontier (v_ready) (v_known) (v_previous) (v_progress))))))
and (* native_session.bend:675 *)
f_chain_allowed : (Chains.t_Job) list -> t_GroupProgress -> bool =
fun v_jobs v_progress ->
(match v_jobs with
| [] ->
false
| ((Chains.Job (v_position, v_job)) :: v_tail) ->
(let (GroupProgress (v_state, v_failure)) = v_progress in
(Scheduler.f_precedes_failure (v_position) (v_failure))))
and (* native_session.bend:683 *)
f_check_chain : (Chains.t_Job) list -> t_CheckCatalog -> ((G.t_CheckedGroup) t_Cached) Base.map -> t_GroupProgress -> bool -> t_GroupProgress =
fun v_jobs v_known v_previous v_progress v_allowed ->
(match (v_jobs, v_allowed) with
| ([], _) ->
v_progress
| (_, false) ->
v_progress
| (((Chains.Job (v_position, v_job)) :: v_tail), true) ->
(let v_next = (f_check_frontier ([(Scheduler.Scheduled (v_position, 0, v_job))]) (v_known) (v_previous) (v_progress)) in
(f_check_chain (v_tail) (v_known) (v_previous) (v_next) ((f_chain_allowed (v_tail) (v_next))))))
and (* native_session.bend:702 *)
f_run_chain : Chains.t_Chain -> t_ChainContext -> t_GroupProgress =
fun v_chain v_context ->
(let (Chains.Chain (v_position, v_level, v_jobs)) = v_chain in
(let (ChainContext (v_known, v_previous, v_interfaces, v_closures, v_failure)) = v_context in
(let v_local = (CheckedGroups ((Base.map_new ()), v_interfaces, (Base.map_new ()), (Base.map_new ()), v_closures, (Base.map_new ()), (Counts (0, 0)))) in
(let v_initial = (GroupProgress (v_local, v_failure)) in
(f_check_chain (v_jobs) (v_known) (v_previous) (v_initial) ((f_chain_allowed (v_jobs) (v_initial))))))))
and (* native_session.bend:711 *)
f_merge_progress : (t_GroupProgress) list -> t_GroupProgress -> t_GroupProgress =
fun v_chains v_progress ->
(match v_chains with
| [] ->
v_progress
| ((GroupProgress ((CheckedGroups (v_cg, v_ci, v_cf, v_cc, v_cl, v_ck, (Counts (v_fresh, v_reused)))), v_failure)) :: v_tail) ->
(let (GroupProgress ((CheckedGroups (v_groups, v_interfaces, v_functions, v_constants, v_closures, v_base_keys, (Counts (v_prior_fresh, v_prior_reused)))), v_prior_failure)) = v_progress in
(let v_combined = (CheckedGroups ((Base.map_union (v_groups) (v_cg)), (Base.map_union (v_interfaces) (v_ci)), (Base.map_union (v_functions) (v_cf)), (Base.map_union (v_constants) (v_cc)), (Base.map_union (v_closures) (v_cl)), (Base.map_union (v_base_keys) (v_ck)), (Counts ((Base.nat_add (v_prior_fresh) (v_fresh)), (Base.nat_add (v_prior_reused) (v_reused)))))) in
(f_merge_progress (v_tail) ((GroupProgress (v_combined, (Scheduler.f_merge_failure (v_prior_failure) (v_failure)))))))))
and (* native_session.bend:720 *)
f_check_parallel_chains : (Chains.t_Chain) list -> t_CheckCatalog -> ((G.t_CheckedGroup) t_Cached) Base.map -> t_GroupProgress -> t_GroupProgress =
fun v_ready v_known v_previous v_progress ->
(let (GroupProgress ((CheckedGroups (v_groups, v_interfaces, v_functions, v_constants, v_closures, v_base_keys, v_counts)), v_failure)) = v_progress in
(let v_outcomes = (B.f_execute (f_run_chain) ((Scheduler.f_chain_batch (v_ready) ((f_check_catalog (v_known))))) ((ChainContext (v_known, v_previous, v_interfaces, v_closures, v_failure)))) in
(f_merge_progress (v_outcomes) (v_progress))))
and (* native_session.bend:725 *)
f_check_chain_frontier_planned : (Chains.t_Chain) list -> t_CheckCatalog -> ((G.t_CheckedGroup) t_Cached) Base.map -> t_GroupProgress -> ((Scheduler.t_Scheduled) list) option -> t_GroupProgress =
fun v_ready v_known v_previous v_progress v_singletons ->
(match (v_ready, v_singletons) with
| (((Chains.Chain (v_position, v_level, v_jobs)) :: []), _) ->
(f_check_chain (v_jobs) (v_known) (v_previous) (v_progress) ((f_chain_allowed (v_jobs) (v_progress))))
| (_, (Some (v_scheduled))) ->
(f_check_frontier (v_scheduled) (v_known) (v_previous) (v_progress))
| (_, None) ->
(f_check_parallel_chains (v_ready) (v_known) (v_previous) (v_progress)))
and (* native_session.bend:734 *)
f_check_chain_frontier : (Chains.t_Chain) list -> t_CheckCatalog -> ((G.t_CheckedGroup) t_Cached) Base.map -> t_GroupProgress -> t_GroupProgress =
fun v_ready v_known v_previous v_progress ->
(f_check_chain_frontier_planned (v_ready) (v_known) (v_previous) (v_progress) ((Scheduler.f_singleton_jobs (v_ready))))
and (* native_session.bend:737 *)
f_check_chain_frontiers : int -> Chains.t_Frontier -> t_CheckCatalog -> ((G.t_CheckedGroup) t_Cached) Base.map -> t_GroupProgress -> (M.t_Diagnostic, t_GroupProgress) Base.result_ =
fun v_fuel v_frontier v_known v_previous v_progress ->
(match (v_fuel, v_frontier) with
| (_, (Chains.Frontier ([], []))) ->
(Done (v_progress))
| (0, _) ->
(Fail ((M.Diagnostic (s_0, s_2, s_10))))
| (__nat_2, (Chains.Frontier (v_ready, v_pending))) when __nat_2 >= 1 ->
(let v_rest = (__nat_2 - 1) in
(f_check_chain_frontiers (v_rest) ((Chains.f_next_frontier (v_pending))) (v_known) (v_previous) ((f_check_chain_frontier (v_ready) (v_known) (v_previous) (v_progress))))))
and (* native_session.bend:746 *)
f_run_region : Regions.t_Region -> t_ChainContext -> (M.t_Diagnostic, t_GroupProgress) Base.result_ =
fun v_region v_context ->
(let (Regions.Region (v_chains)) = v_region in
(let (ChainContext (v_known, v_previous, v_interfaces, v_closures, v_failure)) = v_context in
(let v_local = (CheckedGroups ((Base.map_new ()), v_interfaces, (Base.map_new ()), (Base.map_new ()), v_closures, (Base.map_new ()), (Counts (0, 0)))) in
(f_check_chain_frontiers ((Base.list_length (v_chains))) ((Chains.f_next_frontier (v_chains))) (v_known) (v_previous) ((GroupProgress (v_local, v_failure)))))))
and (* native_session.bend:752 *)
f_merge_regions : ((M.t_Diagnostic, t_GroupProgress) Base.result_) list -> t_GroupProgress -> (M.t_Diagnostic, t_GroupProgress) Base.result_ =
fun v_outcomes v_progress ->
(match v_outcomes with
| [] ->
(Done (v_progress))
| ((Fail (v_diagnostic)) :: v_tail) ->
(Fail (v_diagnostic))
| ((Done (v_region)) :: v_tail) ->
(f_merge_regions (v_tail) ((f_merge_progress ([v_region]) (v_progress)))))
and (* native_session.bend:761 *)
f_check_regions : (Regions.t_Region) list -> t_CheckCatalog -> ((G.t_CheckedGroup) t_Cached) Base.map -> t_GroupProgress -> (M.t_Diagnostic, t_GroupProgress) Base.result_ =
fun v_regions v_known v_previous v_progress ->
(match v_regions with
| ((Regions.Region (v_chains)) :: []) ->
(f_check_chain_frontiers ((Base.list_length (v_chains))) ((Chains.f_next_frontier (v_chains))) (v_known) (v_previous) (v_progress))
| _ ->
(let (GroupProgress ((CheckedGroups (v_groups, v_interfaces, v_functions, v_constants, v_closures, v_base_keys, v_counts)), v_failure)) = v_progress in
(let v_outcomes = (B.f_execute (f_run_region) ((Scheduler.f_region_batch (v_regions) ((f_check_catalog (v_known))))) ((ChainContext (v_known, v_previous, v_interfaces, v_closures, v_failure)))) in
(f_merge_regions (v_outcomes) (v_progress)))))
and (* native_session.bend:770 *)
f_check_plan : t_InferencePlan -> t_CheckCatalog -> ((G.t_CheckedGroup) t_Cached) Base.map -> t_CheckedGroups -> (M.t_Diagnostic, t_CheckedGroups) Base.result_ =
fun v_plan v_known v_previous v_state ->
(match v_plan with
| (IndependentPlan (v_group_count, v_scheduled)) ->
(f_check_frontiers (v_group_count) ((Scheduler.f_next_frontier (v_scheduled))) (v_known) (v_previous) ((GroupProgress (v_state, None))))
| (RegionPlan (v_prefix, v_regions)) ->
(let v_initial = (f_check_chain_frontier (v_prefix) (v_known) (v_previous) ((GroupProgress (v_state, None)))) in
(match (f_check_regions (v_regions) (v_known) (v_previous) (v_initial)) with
| Fail __error -> Fail __error
| Done v_progress ->
(f_finish_groups (v_progress)))))
and (* native_session.bend:780 *)
f_assemble : M.t_Module -> t_CheckedGroups -> (M.t_Diagnostic, M.t_CheckedModule) Base.result_ =
fun v_module v_completed ->
(let (M.Module (v_constants, v_functions, v_types, v_operations)) = v_module in
(let (CheckedGroups (v_groups, v_interfaces, v_checked_functions, v_checked_constants, v_closures, v_base_keys, v_counts)) = v_completed in
(match (Scheduler.f_ordered_functions (v_functions) (v_checked_functions)) with
| Fail __error -> Fail __error
| Done v_fs ->
(match (Scheduler.f_ordered_constants (v_constants) (v_checked_constants)) with
| Fail __error -> Fail __error
| Done v_cs ->
(Done ((M.CheckedModule (v_cs, v_fs, v_types, v_operations))))))))
and (* native_session.bend:791 *)
f_constant_bindings : Const.t_Constants -> ((Const.t_Value) Const.t_Binding) list =
fun v_value ->
(let (Const.Constants (v_bindings, v_remaining)) = v_value in
v_bindings)
and (* native_session.bend:795 *)
f_constant_remaining : Const.t_Constants -> int =
fun v_value ->
(let (Const.Constants (v_bindings, v_remaining)) = v_value in
v_remaining)
and (* native_session.bend:799 *)
f_body_keys : (Base.text) list -> ((Base.word32) list) Base.map -> (M.t_Diagnostic, ((Base.word32) list) list) Base.result_ =
fun v_owners v_known ->
(match v_owners with
| [] ->
(Done ([]))
| (v_name :: v_tail) ->
(match (f_required ((Index.f_find (v_known) (v_name))) (v_name)) with
| Fail __error -> Fail __error
| Done v_key ->
(match (f_body_keys (v_tail) (v_known)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done ((v_key :: v_rest))))))
and (* native_session.bend:809 *)
f_select_constant : (Const.t_Constants) option -> M.t_CheckedConstant -> int -> Const.t_Context -> (M.t_Diagnostic, (Const.t_Constants) t_Selected) Base.result_ =
fun v_found v_constant v_steps v_context ->
(match v_found with
| (Some (v_value)) ->
(Done ((Selected (v_value, true))))
| None ->
(match (Const.f_evaluate_constants ([v_constant]) (v_steps) (v_context)) with
| Fail __error -> Fail __error
| Done v_value ->
(Done ((Selected (v_value, false))))))
and (* native_session.bend:818 *)
f_evaluate_constants : (M.t_CheckedConstant) list -> int -> Const.t_Context -> (Base.set) Base.map -> ((Base.word32) list) Base.map -> ((Const.t_Constants) t_Cached) Base.map -> ((Const.t_Constants) t_Cached) Base.map -> ((Const.t_Value) Const.t_Binding) list -> t_Counts -> (M.t_Diagnostic, t_Evaluated) Base.result_ =
fun v_constants v_steps v_context v_closures v_base_keys v_previous v_next v_reversed v_counts ->
(match v_constants with
| [] ->
(Done ((Evaluated (v_next, (Const.Constants ((Base.list_reverse (v_reversed)), v_steps)), v_counts))))
| ((M.CheckedConstant ((M.Constant (v_name, v_exported, v_annotation, v_expression)), v_ty, v_variables)) :: v_tail) ->
(match (f_required ((Index.f_find (v_closures) (v_name))) (v_name)) with
| Fail __error -> Fail __error
| Done v_closure ->
(match (f_body_keys ((Base.set_to_list (v_closure))) (v_base_keys)) with
| Fail __error -> Fail __error
| Done v_dependencies ->
(match (K.f_encode ([(K.Field ((R.Natural (v_steps))))])) with
| Fail __error -> Fail __error
| Done v_budget ->
(let v_keys = (v_budget :: v_dependencies) in
(match (f_select_constant ((f_cached ((Index.f_find (v_previous) (v_name))) (v_keys))) ((M.CheckedConstant ((M.Constant (v_name, v_exported, v_annotation, v_expression)), v_ty, v_variables))) (v_steps) (v_context)) with
| Fail __error -> Fail __error
| Done v_chosen ->
(let v_value = (f_selected_value (v_chosen)) in
(f_evaluate_constants (v_tail) ((f_constant_remaining (v_value))) (v_context) (v_closures) (v_base_keys) (v_previous) ((Base.map_set (v_next) (v_name) ((Cached (v_keys, v_value))))) ((Base.list_append ((Base.list_reverse ((f_constant_bindings (v_value))))) (v_reversed))) ((f_count (v_counts) ((f_selected_reused (v_chosen)))))))))))))
and (* native_session.bend:842 *)
f_select_entry : (W.t_EntryCode) option -> W.t_CodegenJob -> (Base.word32) list -> t_EntryPlan -> t_EntryPlan =
fun v_found v_job v_key v_plan ->
(match v_found with
| (Some (v_value)) ->
(let (W.CodegenJob (v_name, v_parameter, v_body, v_captures)) = v_job in
(let (EntryPlan (v_selections, v_missing, v_failure)) = v_plan in
(EntryPlan (((ReusedEntry (v_name, v_key, v_value)) :: v_selections), v_missing, v_failure))))
| None ->
(let (W.CodegenJob (v_name, v_parameter, v_body, v_captures)) = v_job in
(let (EntryPlan (v_selections, v_missing, v_failure)) = v_plan in
(EntryPlan (((FreshEntry (v_name, v_key)) :: v_selections), ((W.CodegenJob (v_name, v_parameter, v_body, v_captures)) :: v_missing), v_failure)))))
and (* native_session.bend:853 *)
f_plan_entry_key : (M.t_Diagnostic, (Base.word32) list) Base.result_ -> W.t_CodegenJob -> ((W.t_EntryCode) t_Cached) Base.map -> t_EntryPlan -> t_EntryPlan =
fun v_encoded v_job v_previous v_plan ->
(match v_encoded with
| (Fail (v_error)) ->
(let (EntryPlan (v_selections, v_missing, v_failure)) = v_plan in
(EntryPlan (v_selections, v_missing, (Some (v_error)))))
| (Done (v_key)) ->
(let (W.CodegenJob (v_name, v_parameter, v_body, v_captures)) = v_job in
(f_select_entry ((f_cached ((Index.f_find (v_previous) (v_name))) ([v_key]))) (v_job) (v_key) (v_plan))))
and (* native_session.bend:865 *)
f_entry_key_task : W.t_CodegenJob -> unit -> t_KeyedEntry =
fun v_job v_context ->
(let v_entry = v_job in
(KeyedEntry (v_entry, (K.f_entry (v_entry)))))
and (* native_session.bend:869 *)
f_entry_key_tasks : (W.t_CodegenJob) list -> ((W.t_CodegenJob) B.t_Weighted) list -> ((W.t_CodegenJob) B.t_Weighted) list =
fun v_jobs v_reversed ->
(match v_jobs with
| [] ->
(Base.list_reverse (v_reversed))
| (v_job :: v_tail) ->
(f_entry_key_tasks (v_tail) (((B.Weighted (v_job, (W.f_codegen_weight (v_job)))) :: v_reversed))))
and (* native_session.bend:876 *)
f_keyed_entries : (W.t_CodegenJob) list -> (t_KeyedEntry) list =
fun v_jobs ->
(B.f_execute (f_entry_key_task) ((B.f_plan ((f_entry_key_tasks (v_jobs) ([]))) (512))) (()))
and (* native_session.bend:879 *)
f_plan_entries : (t_KeyedEntry) list -> ((W.t_EntryCode) t_Cached) Base.map -> t_EntryPlan -> t_EntryPlan =
fun v_jobs v_previous v_plan ->
(match (v_jobs, v_plan) with
| ([], (EntryPlan (v_selections, v_missing, v_failure))) ->
(EntryPlan ((Base.list_reverse (v_selections)), (Base.list_reverse (v_missing)), v_failure))
| (_, (EntryPlan (v_selections, v_missing, (Some (v_error))))) ->
(EntryPlan ((Base.list_reverse (v_selections)), (Base.list_reverse (v_missing)), (Some (v_error))))
| (((KeyedEntry (v_job, v_encoded)) :: v_tail), (EntryPlan (v_selections, v_missing, None))) ->
(f_plan_entries (v_tail) (v_previous) ((f_plan_entry_key (v_encoded) (v_job) (v_previous) ((EntryPlan (v_selections, v_missing, None)))))))
and (* native_session.bend:888 *)
f_finish_entries : (M.t_Diagnostic) option -> ((W.t_EntryCode) t_Cached) Base.map -> (W.t_EntryCode) list -> t_Counts -> (M.t_Diagnostic, t_CompiledEntries) Base.result_ =
fun v_failure v_next v_reversed v_counts ->
(match v_failure with
| (Some (v_error)) ->
(Fail (v_error))
| None ->
(Done ((CompiledEntries (v_next, (Base.list_reverse (v_reversed)), v_counts)))))
and (* native_session.bend:895 *)
f_publish_entries : (t_EntrySelection) list -> (W.t_EntryCode) list -> (M.t_Diagnostic) option -> ((W.t_EntryCode) t_Cached) Base.map -> (W.t_EntryCode) list -> t_Counts -> (M.t_Diagnostic, t_CompiledEntries) Base.result_ =
fun v_selections v_compiled v_failure v_next v_reversed v_counts ->
(match (v_selections, v_compiled) with
| ([], []) ->
(f_finish_entries (v_failure) (v_next) (v_reversed) (v_counts))
| (((ReusedEntry (v_name, v_key, v_value)) :: v_tail), _) ->
(f_publish_entries (v_tail) (v_compiled) (v_failure) ((Base.map_set (v_next) (v_name) ((Cached ([v_key], v_value))))) ((v_value :: v_reversed)) ((f_count (v_counts) (true))))
| (((FreshEntry (v_name, v_key)) :: v_tail), ((W.EntryCode (v_found, v_code)) :: v_rest)) ->
(match (W.f_matching_entry ((M.f_name_equal (v_name) (v_found))) (v_name)) with
| Fail __error -> Fail __error
| Done v_valid ->
(let v_value = (W.EntryCode (v_found, v_code)) in
(f_publish_entries (v_tail) (v_rest) (v_failure) ((Base.map_set (v_next) (v_name) ((Cached ([v_key], v_value))))) ((v_value :: v_reversed)) ((f_count (v_counts) (false))))))
| (_, _) ->
(Fail ((M.Diagnostic (s_0, s_11, s_12)))))
and (* native_session.bend:911 *)
f_compile_entry_plan : t_EntryPlan -> ((W.t_EntryCode) t_Cached) Base.map -> (W.t_EntryCode) list -> t_Counts -> (M.t_Diagnostic, t_CompiledEntries) Base.result_ =
fun v_plan v_next v_reversed v_counts ->
(let (EntryPlan (v_selections, v_missing, v_failure)) = v_plan in
(match (W.f_compile_entries (v_missing)) with
| Fail __error -> Fail __error
| Done v_compiled ->
(f_publish_entries (v_selections) (v_compiled) (v_failure) (v_next) (v_reversed) (v_counts))))
and (* native_session.bend:920 *)
f_select_compiled_entry : (W.t_EntryCode) option -> W.t_CodegenJob -> (M.t_Diagnostic, (W.t_EntryCode) t_Selected) Base.result_ =
fun v_found v_job ->
(match v_found with
| (Some (v_value)) ->
(Done ((Selected (v_value, true))))
| None ->
(match (W.f_compile_entry (v_job)) with
| Fail __error -> Fail __error
| Done v_value ->
(Done ((Selected (v_value, false))))))
and (* native_session.bend:929 *)
f_compile_keyed_entry : t_KeyedEntry -> ((W.t_EntryCode) t_Cached) Base.map -> (M.t_Diagnostic, t_PreparedEntry) Base.result_ =
fun v_entry v_previous ->
(let (KeyedEntry (v_job, v_encoded)) = v_entry in
(let (W.CodegenJob (v_name, v_parameter, v_body, v_captures)) = v_job in
(match v_encoded with
| Fail __error -> Fail __error
| Done v_key ->
(match (f_select_compiled_entry ((f_cached ((Index.f_find (v_previous) (v_name))) ([v_key]))) (v_job)) with
| Fail __error -> Fail __error
| Done v_selected ->
(Done ((PreparedEntry (v_name, v_key, v_selected))))))))
and (* native_session.bend:937 *)
f_compile_entry_task : W.t_CodegenJob -> ((W.t_EntryCode) t_Cached) Base.map -> (M.t_Diagnostic, t_PreparedEntry) Base.result_ =
fun v_job v_previous ->
(let v_entry = v_job in
(f_compile_keyed_entry ((KeyedEntry (v_entry, (K.f_entry (v_entry))))) (v_previous)))
and (* native_session.bend:941 *)
f_publish_compiled_entries : ((M.t_Diagnostic, t_PreparedEntry) Base.result_) list -> ((W.t_EntryCode) t_Cached) Base.map -> (W.t_EntryCode) list -> t_Counts -> (M.t_Diagnostic, t_CompiledEntries) Base.result_ =
fun v_entries v_next v_reversed v_counts ->
(match v_entries with
| [] ->
(f_finish_entries (None) (v_next) (v_reversed) (v_counts))
| ((Fail (v_error)) :: v_tail) ->
(Fail (v_error))
| ((Done ((PreparedEntry (v_name, v_key, (Selected (v_value, v_reused)))))) :: v_tail) ->
(let (W.EntryCode (v_found, v_code)) = v_value in
(match (W.f_matching_entry ((M.f_name_equal (v_name) (v_found))) (v_name)) with
| Fail __error -> Fail __error
| Done v_valid ->
(f_publish_compiled_entries (v_tail) ((Base.map_set (v_next) (v_name) ((Cached ([v_key], v_value))))) ((v_value :: v_reversed)) ((f_count (v_counts) (v_reused)))))))
and (* native_session.bend:955 *)
f_compile_weighted_entries : ((W.t_CodegenJob) B.t_Weighted) list -> ((W.t_EntryCode) t_Cached) Base.map -> ((W.t_EntryCode) t_Cached) Base.map -> (W.t_EntryCode) list -> t_Counts -> bool -> (M.t_Diagnostic, t_CompiledEntries) Base.result_ =
fun v_tasks v_previous v_next v_reversed v_counts v_staged ->
(match v_staged with
| true ->
(let v_keyed = (B.f_execute (f_entry_key_task) ((B.f_plan (v_tasks) (512))) (())) in
(f_compile_entry_plan ((f_plan_entries (v_keyed) (v_previous) ((EntryPlan ([], [], None))))) (v_next) (v_reversed) (v_counts)))
| false ->
(let v_compiled = (B.f_execute (f_compile_entry_task) ((B.f_plan (v_tasks) (512))) (v_previous)) in
(f_publish_compiled_entries (v_compiled) (v_next) (v_reversed) (v_counts))))
and (* native_session.bend:964 *)
f_compile_jobs : (W.t_CodegenJob) list -> ((W.t_EntryCode) t_Cached) Base.map -> ((W.t_EntryCode) t_Cached) Base.map -> (W.t_EntryCode) list -> t_Counts -> (M.t_Diagnostic, t_CompiledEntries) Base.result_ =
fun v_jobs v_previous v_next v_reversed v_counts ->
(let v_tasks = (f_entry_key_tasks (v_jobs) ([])) in
(let v_staged = (Base.nat_is_lt ((B.f_total_cost (v_tasks) (0))) ((Base.nat_mul ((Base.list_length (v_tasks))) (256)))) in
(f_compile_weighted_entries (v_tasks) (v_previous) (v_next) (v_reversed) (v_counts) (v_staged))))
and (* native_session.bend:969 *)
f_stats : t_Counts -> t_Counts -> t_Counts -> t_Counts -> t_Stats =
fun v_declarations v_groups v_constants v_entries ->
(let (Counts (v_dl, v_dr)) = v_declarations in
(let (Counts (v_gc, v_gr)) = v_groups in
(let (Counts (v_ce, v_cr)) = v_constants in
(let (Counts (v_ec, v_er)) = v_entries in
(Stats (v_dl, v_dr, v_gc, v_gr, v_ce, v_cr, v_ec, v_er))))))
and (* native_session.bend:976 *)
f_finish_compiled : t_State -> Main.t_Analysis -> W.t_Prepared -> t_CompiledEntries -> t_Counts -> t_Counts -> t_Counts -> (M.t_Diagnostic, t_Completion) Base.result_ =
fun v_state v_analysis v_prepared v_compiled v_declarations v_groups v_constants ->
(let (State (v_prelude, v_scope_key, v_lowered, v_planning, v_checked, v_evaluated, v_previous, v_specialization, v_catalog_version)) = v_state in
(let (CompiledEntries (v_entries, v_values, v_entry_counts)) = v_compiled in
(match (W.f_link_plan (v_prepared) (v_values)) with
| Fail __error -> Fail __error
| Done v_bytes ->
(Done ((Completion ((State (v_prelude, v_scope_key, v_lowered, v_planning, v_checked, v_evaluated, v_entries, v_specialization, v_catalog_version)), (Compiled ((Main.PlannedArtifact (v_analysis, v_bytes)))), (f_stats (v_declarations) (v_groups) (v_constants) (v_entry_counts)))))))))
and (* native_session.bend:983 *)
f_state_entries : t_State -> ((W.t_EntryCode) t_Cached) Base.map =
fun v_state ->
(let (State (v_prelude, v_scope_key, v_lowered, v_planning, v_checked, v_evaluated, v_entries, v_specialization, v_catalog_version)) = v_state in
v_entries)
and (* native_session.bend:987 *)
f_finish : t_Mode -> t_State -> Main.t_Analysis -> t_Counts -> t_Counts -> t_Counts -> (M.t_Diagnostic, t_Completion) Base.result_ =
fun v_mode v_state v_analysis v_declarations v_groups v_constants ->
(match v_mode with
| AnalyzeMode ->
(Done ((Completion (v_state, (Analyzed (v_analysis)), (f_stats (v_declarations) (v_groups) (v_constants) ((Counts (0, 0))))))))
| CompileMode ->
(match (Entries.f_require_exports ((Main.f_analysis_checked (v_analysis)))) with
| Fail __error -> Fail __error
| Done v_exports ->
(match (W.f_prepare ((Main.f_analysis_checked (v_analysis))) ((Main.f_analysis_constants (v_analysis)))) with
| Fail __error -> Fail __error
| Done v_prepared ->
(match (f_compile_jobs ((W.f_prepared_jobs (v_prepared))) ((f_state_entries (v_state))) ((Base.map_new ())) ([]) ((Counts (0, 0)))) with
| Fail __error -> Fail __error
| Done v_compiled ->
(f_finish_compiled (v_state) (v_analysis) (v_prepared) (v_compiled) (v_declarations) (v_groups) (v_constants))))))
and (* native_session.bend:998 *)
f_update_evaluated : t_State -> t_Mode -> M.t_CheckedModule -> t_Evaluated -> t_Counts -> t_Counts -> (M.t_Diagnostic, t_Completion) Base.result_ =
fun v_state v_mode v_checked v_evaluated v_declaration_counts v_group_counts ->
(let (State (v_prelude, v_scope_key, v_declarations, v_planning, v_groups, v_previous_constants, v_entries, v_specialization, v_catalog_version)) = v_state in
(let (Evaluated (v_constants, (Const.Constants (v_bindings, v_remaining)), v_constant_counts)) = v_evaluated in
(let v_next = (State (v_prelude, v_scope_key, v_declarations, v_planning, v_groups, v_constants, v_entries, v_specialization, v_catalog_version)) in
(f_finish (v_mode) (v_next) ((Main.Analysis (v_checked, v_bindings, v_remaining))) (v_declaration_counts) (v_group_counts) (v_constant_counts)))))
and (* native_session.bend:1004 *)
f_update_checked : t_State -> t_Mode -> M.t_Module -> t_CheckedGroups -> t_Counts -> int -> (Entries.t_Entry) list -> (M.t_Diagnostic, t_Completion) Base.result_ =
fun v_state v_mode v_module v_completed v_declaration_counts v_steps v_hosts ->
(let (State (v_prelude, v_scope_key, v_declarations, v_planning, v_previous_groups, v_previous_constants, v_entries, v_specialization, v_catalog_version)) = v_state in
(let (CheckedGroups (v_groups, v_interfaces, v_functions, v_constants, v_closures, v_base_keys, v_group_counts)) = v_completed in
(match (f_assemble (v_module) (v_completed)) with
| Fail __error -> Fail __error
| Done v_checked ->
(match (Entries.f_verify (v_hosts) (v_checked)) with
| Fail __error -> Fail __error
| Done v_valid ->
(match (f_evaluate_constants ((Main.f_checked_constants (v_checked))) (v_steps) ((Main.f_const_context (v_module) (v_checked))) (v_closures) (v_base_keys) (v_previous_constants) ((Base.map_new ())) ([]) ((Counts (0, 0)))) with
| Fail __error -> Fail __error
| Done v_evaluated ->
(f_update_evaluated ((State (v_prelude, v_scope_key, v_declarations, v_planning, v_groups, (Base.map_new ()), v_entries, v_specialization, v_catalog_version))) (v_mode) (v_checked) (v_evaluated) (v_declaration_counts) (v_group_counts)))))))
and (* native_session.bend:1013 *)
f_lowered_fragments : (t_Lowered) list -> (M.t_Module) list =
fun v_values ->
(match v_values with
| [] ->
[]
| (v_head :: v_tail) ->
((f_lowered_fragment (v_head)) :: (f_lowered_fragments (v_tail))))
and (* native_session.bend:1020 *)
f_specialization_graph : bool -> M.t_Module -> (Plan.t_Scanned) list -> (M.t_Diagnostic, (D.t_Node) list) Base.result_ =
fun v_specialized v_module v_scans ->
(match v_specialized with
| true ->
(Check.f_module_graph (v_module))
| false ->
(Plan.f_graph (v_module) (v_scans)))
and (* native_session.bend:1027 *)
f_function_count : M.t_Module -> int =
fun v_module ->
(let (M.Module (v_constants, v_functions, v_types, v_operations)) = v_module in
(Base.list_length (v_functions)))
and (* native_session.bend:1031 *)
f_constant_count : M.t_Module -> int =
fun v_module ->
(let (M.Module (v_constants, v_functions, v_types, v_operations)) = v_module in
(Base.list_length (v_constants)))
and (* native_session.bend:1037 *)
f_reshaped : bool -> M.t_Module -> M.t_Module -> bool =
fun v_specialized v_raw_module v_module ->
(Base.bool_or (v_specialized) ((Base.bool_or ((Base.bool_not ((Base.nat_is_eq ((f_function_count (v_raw_module))) ((f_function_count (v_module))))))) ((Base.bool_not ((Base.nat_is_eq ((f_constant_count (v_raw_module))) ((f_constant_count (v_module))))))))))
and (* native_session.bend:1040 *)
f_groups_if_same_catalog : bool -> ((G.t_CheckedGroup) t_Cached) Base.map -> ((G.t_CheckedGroup) t_Cached) Base.map =
fun v_same v_previous ->
(match v_same with
| true ->
v_previous
| false ->
(Base.map_new ()))
and (* native_session.bend:1047 *)
f_constants_if_same_catalog : bool -> ((Const.t_Constants) t_Cached) Base.map -> ((Const.t_Constants) t_Cached) Base.map =
fun v_same v_previous ->
(match v_same with
| true ->
v_previous
| false ->
(Base.map_new ()))
and (* native_session.bend:1054 *)
f_update_lowered_module : t_State -> t_Mode -> Base.text -> M.t_Module -> M.t_Module -> (Base.word32) list -> t_Lowering -> int -> (M.t_Diagnostic, t_Completion) Base.result_ =
fun v_state v_mode v_entry v_prelude_module v_raw_module v_scope_words v_lowered v_steps ->
(let (State (v_prelude, v_scope_key, v_declarations, v_planning, v_previous_groups, v_constants, v_entries, v_specialization, v_catalog_version)) = v_state in
(let (Lowering (v_values, v_scans, v_declaration_counts)) = v_lowered in
(let v_specialized = (Base.bool_or ((Mono.f_required (v_raw_module))) ((Families.f_required (v_raw_module)))) in
(match (Families.f_prepare (v_raw_module)) with
| Fail __error -> Fail __error
| Done v_family_module ->
(match (Resolution.f_prepare_cached_evidenced (K.f_module) (v_family_module) (v_entry) ((M.f_module_operations (v_raw_module))) (v_specialization)) with
| Fail __error -> Fail __error
| Done v_specialization_result ->
(let v_module = (Mono.f_prepared_module (v_specialization_result)) in
(let v_expanded = (f_reshaped (v_specialized) (v_raw_module) (v_module)) in
(match (f_specialization_graph (v_expanded) (v_module) (((Plan.f_scan (v_prelude_module)) :: v_scans))) with
| Fail __error -> Fail __error
| Done v_graph ->
(match (f_prepare_planning (v_module) (v_prelude_module) (v_values) (v_graph) ((Base.bool_and ((Base.bool_not (v_expanded))) ((f_cache_nominal_scans (v_scans) (0) (0)))))) with
| Fail __error -> Fail __error
| Done v_prepared ->
(let v_plan = (f_planning_value (v_prepared)) in
(match (K.f_planning (v_plan)) with
| Fail __error -> Fail __error
| Done v_plan_key ->
(match (f_select_plan ((f_cached (v_planning) ([v_plan_key]))) (v_plan)) with
| Fail __error -> Fail __error
| Done v_scheduled ->
(match (CV.f_prepare ((f_module_types (v_module))) ((M.f_module_operations (v_module))) (v_catalog_version)) with
| Fail __error -> Fail __error
| Done v_catalog ->
(let v_revision = (CV.f_prepared_revision (v_catalog)) in
(let v_same_catalog = (CV.f_prepared_same_operations (v_catalog)) in
(let v_previous_valid = (f_groups_if_same_catalog (v_same_catalog) (v_previous_groups)) in
(match (f_check_plan (v_scheduled) ((CheckCatalog ((Scheduler.f_with_core ((Scheduler.f_catalog_costs (v_module) ((Plan.f_collect_costs (v_scans) ((Base.map_new ())))))) (v_module) ((Mono.f_prepared_certificates (v_specialization_result)))), v_revision))) (v_previous_valid) ((f_empty_checked ()))) with
| Fail __error -> Fail __error
| Done v_completed ->
(f_update_checked ((State (v_prelude, (Some (v_scope_words)), (f_planning_declarations (v_prepared)), (Some ((Cached ([v_plan_key], v_scheduled)))), (Base.map_new ()), (f_constants_if_same_catalog (v_same_catalog) (v_constants)), v_entries, (Some ((Mono.f_prepared_cache (v_specialization_result)))), (Some (v_revision))))) (v_mode) (v_module) (v_completed) (v_declaration_counts) (v_steps) ((Entries.f_entries (v_raw_module)))))))))))))))))))))
and (* native_session.bend:1075 *)
f_update_lowered : t_State -> t_Mode -> Base.text -> M.t_Module -> (Base.word32) list -> t_Lowering -> int -> (M.t_Diagnostic, t_Completion) Base.result_ =
fun v_state v_mode v_entry v_prelude_module v_scope_words v_lowered v_steps ->
(let (Lowering (v_values, v_scans, v_counts)) = v_lowered in
(let v_raw_module = (f_combine_fragments ((v_prelude_module :: (f_lowered_fragments (v_values))))) in
(f_update_lowered_module (v_state) (v_mode) (v_entry) (v_prelude_module) (v_raw_module) (v_scope_words) ((Lowering (v_values, v_scans, v_counts))) (v_steps))))
and (* native_session.bend:1080 *)
f_unique_identity : (unit) option -> int -> (M.t_Diagnostic, unit) Base.result_ =
fun v_found v_identity ->
(match v_found with
| None ->
(Done (()))
| (Some (v_value)) ->
(Fail ((M.Diagnostic (s_2, (Base.string_append s_13 (Base.nat_show (v_identity))), s_14)))))
and (* native_session.bend:1087 *)
f_unique_declaration_ids : (C.t_Cst) list -> Base.set -> (M.t_Diagnostic, unit) Base.result_ =
fun v_nodes v_seen ->
(match v_nodes with
| [] ->
(Done (()))
| (v_node :: v_tail) ->
(let v_identity = (C.f_offset_of (v_node)) in
(let v_key = (Base.nat_show (v_identity)) in
(match (f_unique_identity ((Index.f_find (v_seen) (v_key))) (v_identity)) with
| Fail __error -> Fail __error
| Done v_unique ->
(f_unique_declaration_ids (v_tail) ((Base.set_add (v_seen) (v_key))))))))
and (* native_session.bend:1098 *)
f_update_source : t_State -> t_Mode -> L.t_SourcePlan -> int -> int -> Base.set -> (M.t_Diagnostic, t_Completion) Base.result_ =
fun v_state v_mode v_source v_fuel v_steps v_retained ->
(let (State (v_prelude, v_scope_key, v_declarations, v_planning, v_groups, v_constants, v_entries, v_specialization, v_catalog_version)) = v_state in
(let (L.SourcePlan (v_prelude_module, v_scope, v_nodes)) = v_source in
(match (f_unique_declaration_ids (v_nodes) ((Base.set_new ()))) with
| Fail __error -> Fail __error
| Done v_unique ->
(match (K.f_scope (v_scope)) with
| Fail __error -> Fail __error
| Done v_scope_words ->
(match (f_lower_plan ((f_plan_lowering (v_nodes) (v_fuel) ((f_reusable_scope (v_scope_key) (v_scope_words) (v_declarations))) (v_retained) ((LoweringPlan ([], []))))) (v_scope) (v_fuel)) with
| Fail __error -> Fail __error
| Done v_lowered ->
(f_update_lowered (v_state) (v_mode) (s_15) (v_prelude_module) (v_scope_words) (v_lowered) (v_steps)))))))
and (* native_session.bend:1107 *)
f_update_single : t_State -> t_Mode -> C.t_Cst -> int -> int -> (M.t_Diagnostic, t_Completion) Base.result_ =
fun v_state v_mode v_root v_fuel v_steps ->
(let (State (v_prelude, v_scope_key, v_declarations, v_planning, v_groups, v_constants, v_entries, v_specialization, v_catalog_version)) = v_state in
(match (L.f_prepare_source (v_root) (v_prelude)) with
| Fail __error -> Fail __error
| Done v_source ->
(f_update_source (v_state) (v_mode) (v_source) (v_fuel) (v_steps) ((Base.set_new ())))))
and (* native_session.bend:1116 *)
f_require_retained : (t_Lowered) option -> int -> (M.t_Diagnostic, C.t_Cst) Base.result_ =
fun v_found v_identity ->
(match v_found with
| (Some ((Lowered (v_node, v_fuel, v_fragment, v_scanned, v_nominals)))) ->
(Done (v_node))
| None ->
(Fail ((M.Diagnostic (s_2, (Base.string_append s_13 (Base.nat_show (v_identity))), s_16)))))
and (* native_session.bend:1123 *)
f_require_declaration : bool -> C.t_Cst -> (M.t_Diagnostic, C.t_Cst) Base.result_ =
fun v_valid v_node ->
(match v_valid with
| true ->
(Done (v_node))
| false ->
(Fail ((C.f_diagnostic (v_node) (s_2) (s_17)))))
and (* native_session.bend:1130 *)
f_resolve_declarations : (t_Declaration) list -> (t_Lowered) Base.map -> (C.t_Cst) list -> Base.set -> (M.t_Diagnostic, t_ResolvedDeclarations) Base.result_ =
fun v_pending v_previous v_reversed v_retained ->
(match v_pending with
| [] ->
(Done ((ResolvedDeclarations ((Base.list_reverse (v_reversed)), v_retained))))
| ((Retained (v_identity)) :: v_tail) ->
(let v_key = (Base.nat_show (v_identity)) in
(match (f_require_retained ((Index.f_find (v_previous) (v_key))) (v_identity)) with
| Fail __error -> Fail __error
| Done v_node ->
(f_resolve_declarations (v_tail) (v_previous) ((v_node :: v_reversed)) ((Base.set_add (v_retained) (v_key))))))
| ((Replaced ((C.Cst (v_kind, v_field, v_text, v_offset, v_children)))) :: v_tail) ->
(match (f_require_declaration ((M.f_name_equal (v_field) (s_18))) ((C.Cst (v_kind, v_field, v_text, v_offset, v_children)))) with
| Fail __error -> Fail __error
| Done v_node ->
(f_resolve_declarations (v_tail) (v_previous) ((v_node :: v_reversed)) (v_retained))))
and (* native_session.bend:1144 *)
f_update_resolved : t_State -> t_Mode -> t_ResolvedDeclarations -> int -> int -> (M.t_Diagnostic, t_Completion) Base.result_ =
fun v_state v_mode v_resolved v_fuel v_steps ->
(let (State (v_prelude, v_scope_key, v_declarations, v_planning, v_groups, v_constants, v_entries, v_specialization, v_catalog_version)) = v_state in
(let (ResolvedDeclarations (v_nodes, v_retained)) = v_resolved in
(match (L.f_prepare_source ((C.Cst (s_19, s_20, s_20, 0, v_nodes))) (v_prelude)) with
| Fail __error -> Fail __error
| Done v_source ->
(f_update_source (v_state) (v_mode) (v_source) (v_fuel) (v_steps) (v_retained)))))
and (* native_session.bend:1154 *)
f_update_patch : t_State -> t_Mode -> (t_Declaration) list -> int -> int -> (M.t_Diagnostic, t_Completion) Base.result_ =
fun v_state v_mode v_declarations v_fuel v_steps ->
(let (State (v_prelude, v_scope_key, v_previous, v_planning, v_groups, v_constants, v_entries, v_specialization, v_catalog_version)) = v_state in
(match (f_resolve_declarations (v_declarations) (v_previous) ([]) ((Base.set_new ()))) with
| Fail __error -> Fail __error
| Done v_resolved ->
(f_update_resolved (v_state) (v_mode) (v_resolved) (v_fuel) (v_steps))))
and (* native_session.bend:1162 *)
f_project_marker_valid : C.t_Cst -> bool =
fun v_node ->
(let (C.Cst (v_kind, v_field, v_text, v_offset, v_children)) = v_node in
(Base.bool_and ((M.f_name_equal (v_field) (s_18))) ((Base.bool_and ((M.f_name_equal (v_text) (s_20))) ((Base.bool_not ((C.f_present (v_children)))))))))
and (* native_session.bend:1166 *)
f_project_retained : bool -> C.t_Cst -> (t_Lowered) Base.map -> (M.t_Diagnostic, C.t_Cst) Base.result_ =
fun v_valid v_node v_previous ->
(match v_valid with
| false ->
(Fail ((C.f_diagnostic (v_node) (s_2) (s_21))))
| true ->
(let v_identity = (C.f_offset_of (v_node)) in
(f_require_retained ((Index.f_find (v_previous) ((Base.nat_show (v_identity))))) (v_identity))))
and (* native_session.bend:1174 *)
f_project_node : bool -> C.t_Cst -> (t_Lowered) Base.map -> (M.t_Diagnostic, C.t_Cst) Base.result_ =
fun v_retained v_node v_previous ->
(match v_retained with
| false ->
(Done (v_node))
| true ->
(f_project_retained ((f_project_marker_valid (v_node))) (v_node) (v_previous)))
and (* native_session.bend:1181 *)
f_project_children : (C.t_Cst) list -> (t_Lowered) Base.map -> (M.t_Diagnostic, (C.t_Cst) list) Base.result_ =
fun v_nodes v_previous ->
(match v_nodes with
| [] ->
(Done ([]))
| (v_head :: v_tail) ->
(match (f_project_node ((M.f_name_equal ((C.f_kind_of (v_head))) (s_22))) (v_head) (v_previous)) with
| Fail __error -> Fail __error
| Done v_first ->
(match (f_project_children (v_tail) (v_previous)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done ((v_first :: v_rest))))))
and (* native_session.bend:1191 *)
f_project_body : C.t_Cst -> (t_Lowered) Base.map -> (M.t_Diagnostic, C.t_Cst) Base.result_ =
fun v_body v_previous ->
(let (C.Cst (v_kind, v_field, v_text, v_offset, v_declarations)) = v_body in
(match (f_project_children (v_declarations) (v_previous)) with
| Fail __error -> Fail __error
| Done v_resolved ->
(Done ((C.Cst (v_kind, v_field, v_text, v_offset, v_resolved))))))
and (* native_session.bend:1197 *)
f_project_modules : (C.t_Cst) list -> (t_Lowered) Base.map -> (M.t_Diagnostic, (C.t_Cst) list) Base.result_ =
fun v_nodes v_previous ->
(match v_nodes with
| [] ->
(Done ([]))
| ((C.Cst (v_kind, v_field, v_text, v_offset, v_children)) :: v_tail) ->
(match (C.f_one ((C.f_fields (v_children) (s_23)))) with
| Fail __error -> Fail __error
| Done v_body ->
(match (f_project_body (v_body) (v_previous)) with
| Fail __error -> Fail __error
| Done v_resolved ->
(match (f_project_modules (v_tail) (v_previous)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done (((C.Cst (v_kind, v_field, v_text, v_offset, [v_resolved])) :: v_rest)))))))
and (* native_session.bend:1208 *)
f_project_task_key : (M.t_Diagnostic, Modules.t_ModuleTask) Base.result_ -> (M.t_Diagnostic, (Base.word32) list) Base.result_ =
fun v_prepared ->
(match v_prepared with
| (Fail (v_error)) ->
(Done ([(Base.W32 0x0)]))
| (Done ((Modules.ModuleTask (v_declarations, v_prefix, v_name, v_entry, v_scope)))) ->
(match (K.f_encode ([(K.Field ((R.Text (v_prefix)))); (K.Field ((R.Text (v_name)))); (K.f_flag (v_entry))])) with
| Fail __error -> Fail __error
| Done v_header ->
(match (K.f_scope (v_scope)) with
| Fail __error -> Fail __error
| Done v_words ->
(Done ((Base.list_append (v_header) (((Base.u32_from_nat ((Base.list_length (v_words)))) :: v_words))))))))
and (* native_session.bend:1219 *)
f_project_scope_key : (((M.t_Diagnostic, Modules.t_ModuleTask) Base.result_) B.t_Weighted) list -> (M.t_Diagnostic, (Base.word32) list) Base.result_ =
fun v_tasks ->
(match v_tasks with
| [] ->
(Done ([]))
| ((B.Weighted (v_task, v_cost)) :: v_tail) ->
(match (f_project_task_key (v_task)) with
| Fail __error -> Fail __error
| Done v_first ->
(match (f_project_scope_key (v_tail)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done (((Base.u32_from_nat ((Base.list_length (v_first)))) :: (Base.list_append (v_first) (v_rest))))))))
and (* native_session.bend:1232 *)
f_lower_project_node : (t_Lowered) option -> C.t_Cst -> Modules.t_ModuleTask -> int -> (M.t_Diagnostic, t_Lowered) Base.result_ =
fun v_found v_node v_task v_fuel ->
(match v_found with
| (Some (v_value)) ->
(Done (v_value))
| None ->
(let (Modules.ModuleTask (v_declarations, v_prefix, v_name, v_entry, v_scope)) = v_task in
(match (C.f_one ((C.f_field_values (v_node) (s_25)))) with
| Fail __error -> Fail __error
| Done v_value ->
(match (L.f_declaration ((L.f_classify ((C.f_kind_of (v_value))))) (v_value) ((C.f_field_values (v_node) (s_24))) (v_prefix) (v_name) (v_entry) ((M.Module ([], [], [], []))) (v_fuel) (v_scope)) with
| Fail __error -> Fail __error
| Done v_fragment ->
(Done ((Lowered (v_node, v_fuel, v_fragment, (Plan.f_scan (v_fragment)), None))))))))
and (* native_session.bend:1243 *)
f_lower_project_nodes : (C.t_Cst) list -> Modules.t_ModuleTask -> t_ProjectContext -> t_Lowering -> (M.t_Diagnostic, t_Lowering) Base.result_ =
fun v_nodes v_task v_context v_lowered ->
(match v_nodes with
| [] ->
(Done (v_lowered))
| (v_node :: v_tail) ->
(let (ProjectContext (v_previous, v_fuel)) = v_context in
(let (Lowering (v_values, v_scans, v_counts)) = v_lowered in
(let v_found = (f_lower_hit ((Index.f_find (v_previous) ((Base.nat_show ((C.f_offset_of (v_node))))))) (v_node) (v_fuel) (false)) in
(match (f_lower_project_node (v_found) (v_node) (v_task) (v_fuel)) with
| Fail __error -> Fail __error
| Done v_value ->
(f_lower_project_nodes (v_tail) (v_task) (v_context) ((Lowering ((v_value :: v_values), ((f_lowered_scan (v_value)) :: v_scans), (f_count (v_counts) ((Base.maybe_is_some (v_found)))))))))))))
and (* native_session.bend:1258 *)
f_project_module : t_Lowering -> (M.t_Operation) list -> M.t_Module =
fun v_lowered v_requests ->
(let (Lowering (v_values, v_scans, v_counts)) = v_lowered in
(L.f_add_operations ((f_combine_fragments ((f_lowered_fragments (v_values))))) (v_requests)))
and (* native_session.bend:1262 *)
f_lower_project_ready : Modules.t_ModuleTask -> t_ProjectContext -> (M.t_Diagnostic, t_ProjectLowering) Base.result_ =
fun v_task v_context ->
(let (Modules.ModuleTask (v_declarations, v_prefix, v_name, v_entry, v_scope)) = v_task in
(let (ProjectContext (v_previous, v_fuel)) = v_context in
(match (L.f_validate_declaration_nodes (v_declarations)) with
| Fail __error -> Fail __error
| Done v_valid ->
(match (f_lower_project_nodes ((Base.list_reverse (v_declarations))) (v_task) (v_context) ((Lowering ([], [], (Counts (0, 0)))))) with
| Fail __error -> Fail __error
| Done v_lowered ->
(match (L.f_declarations_row_requests (v_declarations) (v_fuel) (v_scope) ([])) with
| Fail __error -> Fail __error
| Done v_requests ->
(Done ((ProjectLowering (v_lowered, (f_project_module (v_lowered) (v_requests)))))))))))
and (* native_session.bend:1271 *)
f_lower_project_task : (M.t_Diagnostic, Modules.t_ModuleTask) Base.result_ -> t_ProjectContext -> (M.t_Diagnostic, t_ProjectLowering) Base.result_ =
fun v_prepared v_context ->
(match v_prepared with
| Fail __error -> Fail __error
| Done v_task ->
(f_lower_project_ready (v_task) (v_context)))
and (* native_session.bend:1276 *)
f_combine_project_lowering : t_Lowering -> t_Lowering -> t_Lowering =
fun v_first v_rest ->
(let (Lowering (v_a, v_sa, (Counts (v_fa, v_ra)))) = v_first in
(let (Lowering (v_b, v_sb, (Counts (v_fb, v_rb)))) = v_rest in
(Lowering ((Base.list_append (v_a) (v_b)), (Base.list_append (v_sa) (v_sb)), (Counts ((Base.nat_add (v_fa) (v_fb)), (Base.nat_add (v_ra) (v_rb))))))))
and (* native_session.bend:1281 *)
f_combine_project_modules : t_ProjectLowering -> t_ProjectLowering -> t_ProjectLowering =
fun v_first v_rest ->
(let (ProjectLowering (v_a, v_ma)) = v_first in
(let (ProjectLowering (v_b, v_mb)) = v_rest in
(ProjectLowering ((f_combine_project_lowering (v_a) (v_b)), (L.f_combine_modules (v_ma) (v_mb))))))
and (* native_session.bend:1286 *)
f_collect_project_lowering : ((M.t_Diagnostic, t_ProjectLowering) Base.result_) list -> (M.t_Diagnostic, t_ProjectLowering) Base.result_ =
fun v_outcomes ->
(match v_outcomes with
| [] ->
(Done ((ProjectLowering ((Lowering ([], [], (Counts (0, 0)))), (M.Module ([], [], [], []))))))
| (v_head :: v_tail) ->
(match v_head with
| Fail __error -> Fail __error
| Done v_first ->
(match (f_collect_project_lowering (v_tail)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done ((f_combine_project_modules (v_first) (v_rest)))))))
and (* native_session.bend:1296 *)
f_project_nodes : (t_Lowered) list -> (C.t_Cst) list =
fun v_values ->
(match v_values with
| [] ->
[]
| ((Lowered (v_node, v_fuel, v_fragment, v_scanned, v_nominals)) :: v_tail) ->
(v_node :: (f_project_nodes (v_tail))))
and (* native_session.bend:1303 *)
f_update_project_lowered : t_State -> t_Mode -> Base.text -> M.t_Module -> (Base.word32) list -> t_ProjectLowering -> int -> (M.t_Diagnostic, t_Completion) Base.result_ =
fun v_state v_mode v_entry v_prelude_module v_key v_project v_steps ->
(let (ProjectLowering ((Lowering (v_values, v_scans, v_counts)), v_module)) = v_project in
(match (f_unique_declaration_ids ((f_project_nodes (v_values))) ((Base.set_new ()))) with
| Fail __error -> Fail __error
| Done v_unique ->
(f_update_lowered_module (v_state) (v_mode) (v_entry) (v_prelude_module) ((L.f_combine_modules (v_prelude_module) (v_module))) (v_key) ((Lowering (v_values, v_scans, v_counts))) (v_steps))))
and (* native_session.bend:1309 *)
f_update_project : t_State -> t_Mode -> C.t_Cst -> int -> int -> (M.t_Diagnostic, t_Completion) Base.result_ =
fun v_state v_mode v_root v_fuel v_steps ->
(let (State ((L.Prelude (v_prelude_module, v_scope)), v_scope_key, v_declarations, v_planning, v_groups, v_constants, v_entries, v_specialization, v_catalog_version)) = v_state in
(match (f_project_modules ((C.f_field_values (v_root) (s_26))) (v_declarations)) with
| Fail __error -> Fail __error
| Done v_modules ->
(let v_tasks = (Modules.f_prepare_modules (v_modules) ((C.f_text_of (v_root))) (v_scope) (MTip)) in
(match (f_project_scope_key (v_tasks)) with
| Fail __error -> Fail __error
| Done v_key ->
(let v_outcomes = (B.f_execute (f_lower_project_task) ((B.f_plan (v_tasks) (512))) ((ProjectContext ((f_reusable_scope (v_scope_key) (v_key) (v_declarations)), v_fuel)))) in
(match (f_collect_project_lowering (v_outcomes)) with
| Fail __error -> Fail __error
| Done v_lowered ->
(f_update_project_lowered (v_state) (v_mode) ((C.f_text_of (v_root))) (v_prelude_module) (v_key) (v_lowered) (v_steps))))))))
and (* native_session.bend:1319 *)
f_update_kind : bool -> t_State -> t_Mode -> C.t_Cst -> int -> int -> (M.t_Diagnostic, t_Completion) Base.result_ =
fun v_project v_state v_mode v_root v_fuel v_steps ->
(match v_project with
| false ->
(f_update_single (v_state) (v_mode) (v_root) (v_fuel) (v_steps))
| true ->
(f_update_project (v_state) (v_mode) (v_root) (v_fuel) (v_steps)))
and (* native_session.bend:1326 *)
f_update : t_State -> t_Mode -> C.t_Cst -> int -> int -> (M.t_Diagnostic, t_Completion) Base.result_ =
fun v_state v_mode v_root v_fuel v_steps ->
(f_update_kind ((M.f_name_equal ((C.f_kind_of (v_root))) (s_27))) (v_state) (v_mode) (v_root) (v_fuel) (v_steps))
