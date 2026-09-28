(* Native semantic port of compiler/check_scheduler.bend.

   Source SHA-256: e62e46475ab823fed2a0527e3dc7df07e718a6a6c492f3ae0fb803438a6ab09a

   Ownership/type arguments are erased; value types are checked by OCaml.

   No Bend interpreter or generated C/JavaScript is linked. *)

open Base

module M = Ox_model

module G = Ox_groups

module Index = Ox_index

module B = Ox_inference_batch

module Chains = Ox_check_chain_plan

module Regions = Ox_check_regions

module Core = Ox_checked_core

module ResolvingCore = Ox_resolving_core

module AlphaCompare = Ox_frontier_alpha_compare

module NatIndex = Ox_nat_index

type 'v t_Positioned =
  | Positioned of int * 'v
and t_Catalog =
  | Catalog of ((M.t_Function) t_Positioned) Base.map * ((M.t_Constant) t_Positioned) Base.map * ((M.t_DataType) t_Positioned) Base.map * (M.t_Operation) list * (int) Base.map * ((Core.t_Certificate) list) Base.map * bool * ((ResolvingCore.t_Witness) list) Base.map
and t_Scheduled =
  | Scheduled of int * int * G.t_Job
and t_Task =
  | Task of int * M.t_Module * (G.t_Interface) list * int
  | EvidenceTask of int * M.t_Module * (G.t_Interface) list * int
  | RetainedTask of int * G.t_CheckedGroup
  | RetainedEvidenceTask of int * M.t_Module * (G.t_Interface) list * G.t_CheckedGroup * (G.t_GroupNeeds) list
and t_Outcome =
  | Outcome of int * (M.t_Diagnostic, G.t_CheckedGroup) Base.result_
  | EvidenceOutcome of int * M.t_Module * (G.t_Interface) list * (M.t_Diagnostic, G.t_Resolving) Base.result_
and t_Failure =
  | Failure of int * M.t_Diagnostic
and t_FrontierCandidate =
  | FrontierCandidate of int * Base.text * M.t_Function * (M.t_DataType) list * (G.t_Interface) list
and t_BatchState =
  | BatchState of ((t_FrontierCandidate) list) Base.map * (t_Task) list * (t_Task) list * (int) NatIndex.t_Index
and t_PlannedBatch =
  | PlannedBatch of (t_Task) list * (t_Task) list * (int) NatIndex.t_Index
and t_Frontier =
  | Frontier of (t_Scheduled) list * (t_Scheduled) list
and t_CostWork =
  | ExpressionCost of M.t_Expr
  | ExpressionsCost of (M.t_Expr) list
  | ArmsCost of ((M.t_Expr) M.t_MatchArm) list
  | PatternsCost of (M.t_Pattern) list
  | PatternCost of M.t_Pattern
and t_Completed =
  | Completed of (G.t_Interface) Base.map * (M.t_CheckedFunction) Base.map * (M.t_CheckedConstant) Base.map * (G.t_Interface) list * (t_Failure) option * (Core.t_Certificate) list * (G.t_GroupNeeds) list
and t_Preparation =
  | Preparation of (t_Task) list * (t_Outcome) list
and t_ChainContext =
  | ChainContext of t_Catalog * (G.t_Interface) Base.map * (t_Failure) option
and t_Initial =
  | Initial of M.t_CheckedModule * (Core.t_Certificate) list * (G.t_GroupNeeds) list
and t_InitialAttempt =
  | CheckedInitial of t_Initial * int * int
  | FailedInitial of M.t_Diagnostic * (Core.t_Certificate) list * int * int
and t_AuditCounts =
  | AuditCounts of int * int

let s_0 = Base.text_of_utf8 "internal_error"

let s_1 = Base.text_of_utf8 "incremental plan omitted a required checked dependency"

let s_2 = Base.text_of_utf8 "$mono["

let s_3 = Base.text_of_utf8 "$self"

let s_4 = Base.text_of_utf8 "check_scheduler"

let s_5 = Base.text_of_utf8 "dependency frontier count exceeds its declaration group count"

let s_6 = Base.text_of_utf8 "dependency chain frontiers exceed their declaration group count"

let rec (* check_scheduler.bend:13 *)
f_required : 'v. ('v) option -> Base.text -> (M.t_Diagnostic, 'v) Base.result_ =
fun v_found v_name ->
(match v_found with
| (Some (v_value)) ->
(Done (v_value))
| None ->
(Fail ((M.Diagnostic (s_0, v_name, s_1)))))
and (* check_scheduler.bend:35 *)
f_index_functions : (M.t_Function) list -> int -> ((M.t_Function) t_Positioned) Base.map -> ((M.t_Function) t_Positioned) Base.map =
fun v_values v_position v_found ->
(match v_values with
| [] ->
v_found
| ((M.Function (v_name, v_exported, v_parameter, v_p, v_r, v_body)) :: v_tail) ->
(f_index_functions (v_tail) ((Base.nat_add 1 v_position)) ((Base.map_set (v_found) (v_name) ((Positioned (v_position, (M.Function (v_name, v_exported, v_parameter, v_p, v_r, v_body)))))))))
and (* check_scheduler.bend:42 *)
f_index_constants : (M.t_Constant) list -> int -> ((M.t_Constant) t_Positioned) Base.map -> ((M.t_Constant) t_Positioned) Base.map =
fun v_values v_position v_found ->
(match v_values with
| [] ->
v_found
| ((M.Constant (v_name, v_exported, v_annotation, v_value)) :: v_tail) ->
(f_index_constants (v_tail) ((Base.nat_add 1 v_position)) ((Base.map_set (v_found) (v_name) ((Positioned (v_position, (M.Constant (v_name, v_exported, v_annotation, v_value)))))))))
and (* check_scheduler.bend:49 *)
f_index_types : (M.t_DataType) list -> int -> ((M.t_DataType) t_Positioned) Base.map -> ((M.t_DataType) t_Positioned) Base.map =
fun v_values v_position v_found ->
(match v_values with
| [] ->
v_found
| ((M.DataType (v_identity, v_parameters, v_constructors)) :: v_tail) ->
(f_index_types (v_tail) ((Base.nat_add 1 v_position)) ((Base.map_set (v_found) ((G.f_type_key (v_identity))) ((Positioned (v_position, (M.DataType (v_identity, v_parameters, v_constructors)))))))))
and (* check_scheduler.bend:56 *)
f_catalog_costs : M.t_Module -> (int) Base.map -> t_Catalog =
fun v_module v_costs ->
(let (M.Module (v_constants, v_functions, v_types, v_operations)) = v_module in
(Catalog ((f_index_functions (v_functions) (0) ((Base.map_new ()))), (f_index_constants (v_constants) (0) ((Base.map_new ()))), (f_index_types (v_types) (0) ((Base.map_new ()))), v_operations, v_costs, (Base.map_new ()), false, (Base.map_new ()))))
and (* check_scheduler.bend:60 *)
f_catalog : M.t_Module -> t_Catalog =
fun v_module ->
(f_catalog_costs (v_module) ((Base.map_new ())))
and (* check_scheduler.bend:63 *)
f_with_core : t_Catalog -> M.t_Module -> (Core.t_Certificate) list -> t_Catalog =
fun v_known v_module v_certificates ->
(let (Catalog (v_functions, v_constants, v_types, v_operations, v_costs, v_core, v_evidence, v_resolving)) = v_known in
(Catalog (v_functions, v_constants, v_types, v_operations, v_costs, (Core.f_index_for (v_module) (v_certificates)), v_evidence, v_resolving)))
and (* check_scheduler.bend:67 *)
f_with_evidence : t_Catalog -> t_Catalog =
fun v_known ->
(let (Catalog (v_functions, v_constants, v_types, v_operations, v_costs, v_core, v_evidence, v_resolving)) = v_known in
(Catalog (v_functions, v_constants, v_types, v_operations, v_costs, v_core, true, v_resolving)))
and (* check_scheduler.bend:71 *)
f_with_resolving : t_Catalog -> ((ResolvingCore.t_Witness) list) Base.map -> t_Catalog =
fun v_known v_witnesses ->
(let (Catalog (v_functions, v_constants, v_types, v_operations, v_costs, v_core, v_evidence, v_resolving)) = v_known in
(Catalog (v_functions, v_constants, v_types, v_operations, v_costs, v_core, v_evidence, v_witnesses)))
and (* check_scheduler.bend:75 *)
f_retained_resolving : t_Catalog -> G.t_Job -> M.t_Module -> (G.t_Interface) list -> (G.t_Resolving) option =
fun v_known v_job v_subset v_imports ->
(let (Catalog (v_functions, v_constants, v_types, v_operations, v_costs, v_core, v_evidence, v_resolving)) = v_known in
(ResolvingCore.f_lookup (v_resolving) (v_job) (v_subset) (v_imports)))
and (* check_scheduler.bend:79 *)
f_collecting : t_Catalog -> bool =
fun v_known ->
(let (Catalog (v_functions, v_constants, v_types, v_operations, v_costs, v_core, v_evidence, v_resolving)) = v_known in
v_evidence)
and (* check_scheduler.bend:83 *)
f_core_index : t_Catalog -> ((Core.t_Certificate) list) Base.map =
fun v_known ->
(let (Catalog (v_functions, v_constants, v_types, v_operations, v_costs, v_core, v_evidence, v_resolving)) = v_known in
v_core)
and (* check_scheduler.bend:87 *)
f_retained_group : t_Catalog -> G.t_Job -> M.t_Module -> (G.t_Interface) list -> (G.t_CheckedGroup) option =
fun v_known v_job v_subset v_imports ->
(Core.f_lookup ((f_core_index (v_known))) (v_job) (v_subset) (v_imports))
and (* check_scheduler.bend:90 *)
f_selected_position : 'v. (('v) t_Positioned) option -> (('v) t_Positioned) list -> (('v) t_Positioned) list =
fun v_found v_rest ->
(match v_found with
| None ->
v_rest
| (Some (v_value)) ->
(v_value :: v_rest))
and (* check_scheduler.bend:97 *)
f_select_positions : 'v. (Base.text) list -> (('v) t_Positioned) Base.map -> (('v) t_Positioned) list =
fun v_names v_indexed ->
(match v_names with
| [] ->
[]
| (v_head :: v_tail) ->
(f_selected_position ((Index.f_find (v_indexed) (v_head))) ((f_select_positions (v_tail) (v_indexed)))))
and (* check_scheduler.bend:104 *)
f_position_le : 'v. ('v) t_Positioned -> ('v) t_Positioned -> bool =
fun v_left v_right ->
(let (Positioned (v_a, v_av)) = v_left in
(let (Positioned (v_b, v_bv)) = v_right in
(Base.nat_is_le (v_a) (v_b))))
and (* check_scheduler.bend:109 *)
f_positioned_values : 'v. (('v) t_Positioned) list -> ('v) list =
fun v_values ->
(match v_values with
| [] ->
[]
| ((Positioned (v_position, v_value)) :: v_tail) ->
(v_value :: (f_positioned_values (v_tail))))
and (* check_scheduler.bend:116 *)
f_function_position_le : (M.t_Function) t_Positioned -> (M.t_Function) t_Positioned -> bool =
fun v_left v_right ->
(f_position_le (v_left) (v_right))
and (* check_scheduler.bend:119 *)
f_constant_position_le : (M.t_Constant) t_Positioned -> (M.t_Constant) t_Positioned -> bool =
fun v_left v_right ->
(f_position_le (v_left) (v_right))
and (* check_scheduler.bend:122 *)
f_type_position_le : (M.t_DataType) t_Positioned -> (M.t_DataType) t_Positioned -> bool =
fun v_left v_right ->
(f_position_le (v_left) (v_right))
and (* check_scheduler.bend:125 *)
f_group_module : t_Catalog -> G.t_Job -> M.t_Module =
fun v_known v_job ->
(let (Catalog (v_functions, v_constants, v_types, v_operations, v_costs, v_core, v_evidence, v_resolving)) = v_known in
(let (G.Job (v_members, v_dependencies, v_required_types)) = v_job in
(let v_nominals = (G.f_type_keys (v_required_types)) in
(let v_cs = (f_positioned_values ((Base.list_sort (f_constant_position_le) ((f_select_positions (v_members) (v_constants)))))) in
(let v_fs = (f_positioned_values ((Base.list_sort (f_function_position_le) ((f_select_positions (v_members) (v_functions)))))) in
(let v_ts = (f_positioned_values ((Base.list_sort (f_type_position_le) ((f_select_positions (v_nominals) (v_types)))))) in
(M.Module (v_cs, v_fs, v_ts, v_operations))))))))
and (* check_scheduler.bend:134 *)
f_dependency_interfaces : (Base.text) list -> (G.t_Interface) Base.map -> (M.t_Diagnostic, (G.t_Interface) list) Base.result_ =
fun v_names v_known ->
(match v_names with
| [] ->
(Done ([]))
| (v_name :: v_tail) ->
(match (f_required ((Index.f_find (v_known) (v_name))) (v_name)) with
| Fail __error -> Fail __error
| Done v_value ->
(match (f_dependency_interfaces (v_tail) (v_known)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done ((v_value :: v_rest))))))
and (* check_scheduler.bend:144 *)
f_publish_interfaces : (G.t_Interface) list -> (G.t_Interface) Base.map -> (G.t_Interface) Base.map =
fun v_values v_known ->
(match v_values with
| [] ->
v_known
| ((G.Interface (v_name, v_kind, v_template, v_parameters, v_effects, v_predicates)) :: v_tail) ->
(f_publish_interfaces (v_tail) ((Base.map_set (v_known) (v_name) ((G.Interface (v_name, v_kind, v_template, v_parameters, v_effects, v_predicates)))))))
and (* check_scheduler.bend:151 *)
f_publish_functions : (M.t_CheckedFunction) list -> (M.t_CheckedFunction) Base.map -> (M.t_CheckedFunction) Base.map =
fun v_values v_known ->
(match v_values with
| [] ->
v_known
| ((M.CheckedFunction ((M.Function (v_name, v_exported, v_parameter, v_p, v_r, v_body)), v_signature, v_effects)) :: v_tail) ->
(f_publish_functions (v_tail) ((Base.map_set (v_known) (v_name) ((M.CheckedFunction ((M.Function (v_name, v_exported, v_parameter, v_p, v_r, v_body)), v_signature, v_effects)))))))
and (* check_scheduler.bend:158 *)
f_publish_constants : (M.t_CheckedConstant) list -> (M.t_CheckedConstant) Base.map -> (M.t_CheckedConstant) Base.map =
fun v_values v_known ->
(match v_values with
| [] ->
v_known
| ((M.CheckedConstant ((M.Constant (v_name, v_exported, v_annotation, v_value)), v_ty, v_variables)) :: v_tail) ->
(f_publish_constants (v_tail) ((Base.map_set (v_known) (v_name) ((M.CheckedConstant ((M.Constant (v_name, v_exported, v_annotation, v_value)), v_ty, v_variables)))))))
and (* check_scheduler.bend:165 *)
f_ordered_functions : (M.t_Function) list -> (M.t_CheckedFunction) Base.map -> (M.t_Diagnostic, (M.t_CheckedFunction) list) Base.result_ =
fun v_values v_known ->
(match v_values with
| [] ->
(Done ([]))
| ((M.Function (v_name, v_exported, v_parameter, v_p, v_r, v_body)) :: v_tail) ->
(match (f_required ((Index.f_find (v_known) (v_name))) (v_name)) with
| Fail __error -> Fail __error
| Done v_value ->
(match (f_ordered_functions (v_tail) (v_known)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done ((v_value :: v_rest))))))
and (* check_scheduler.bend:175 *)
f_ordered_constants : (M.t_Constant) list -> (M.t_CheckedConstant) Base.map -> (M.t_Diagnostic, (M.t_CheckedConstant) list) Base.result_ =
fun v_values v_known ->
(match v_values with
| [] ->
(Done ([]))
| ((M.Constant (v_name, v_exported, v_annotation, v_expression)) :: v_tail) ->
(match (f_required ((Index.f_find (v_known) (v_name))) (v_name)) with
| Fail __error -> Fail __error
| Done v_value ->
(match (f_ordered_constants (v_tail) (v_known)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done ((v_value :: v_rest))))))
and (* check_scheduler.bend:201 *)
f_dependency_level : (int) option -> Base.text -> (M.t_Diagnostic, int) Base.result_ =
fun v_found v_name ->
(match v_found with
| (Some (v_level)) ->
(Done ((Base.nat_add 1 v_level)))
| None ->
(Fail ((M.Diagnostic (s_0, v_name, s_1)))))
and (* check_scheduler.bend:208 *)
f_highest_level : (Base.text) list -> (int) Base.map -> int -> (M.t_Diagnostic, int) Base.result_ =
fun v_names v_levels v_maximum ->
(match v_names with
| [] ->
(Done (v_maximum))
| (v_name :: v_tail) ->
(match (f_dependency_level ((Index.f_find (v_levels) (v_name))) (v_name)) with
| Fail __error -> Fail __error
| Done v_level ->
(f_highest_level (v_tail) (v_levels) ((Base.nat_max (v_maximum) (v_level))))))
and (* check_scheduler.bend:217 *)
f_publish_level : (Base.text) list -> int -> (int) Base.map -> (int) Base.map =
fun v_names v_level v_levels ->
(match v_names with
| [] ->
v_levels
| (v_name :: v_tail) ->
(f_publish_level (v_tail) (v_level) ((Base.map_set (v_levels) (v_name) (v_level)))))
and (* check_scheduler.bend:224 *)
f_scheduled_le : t_Scheduled -> t_Scheduled -> bool =
fun v_left v_right ->
(let (Scheduled (v_a, v_x, v_first)) = v_left in
(let (Scheduled (v_b, v_y, v_second)) = v_right in
(Base.bool_or ((Base.nat_is_lt (v_x) (v_y))) ((Base.bool_and ((Base.nat_is_eq (v_x) (v_y))) ((Base.nat_is_le (v_a) (v_b))))))))
and (* check_scheduler.bend:229 *)
f_schedule_work : (G.t_Job) list -> int -> (int) Base.map -> (t_Scheduled) list -> (M.t_Diagnostic, (t_Scheduled) list) Base.result_ =
fun v_jobs v_position v_levels v_reversed ->
(match v_jobs with
| [] ->
(Done ((Base.list_sort (f_scheduled_le) ((Base.list_reverse (v_reversed))))))
| (v_job :: v_tail) ->
(let (G.Job (v_members, v_dependencies, v_types)) = v_job in
(match (f_highest_level (v_dependencies) (v_levels) (0)) with
| Fail __error -> Fail __error
| Done v_level ->
(f_schedule_work (v_tail) ((Base.nat_add 1 v_position)) ((f_publish_level (v_members) (v_level) (v_levels))) (((Scheduled (v_position, v_level, v_job)) :: v_reversed))))))
and (* check_scheduler.bend:241 *)
f_schedule : (G.t_Job) list -> (M.t_Diagnostic, (t_Scheduled) list) Base.result_ =
fun v_jobs ->
(f_schedule_work (v_jobs) (0) ((Base.map_new ())) ([]))
and (* check_scheduler.bend:244 *)
f_precedes_failure : int -> (t_Failure) option -> bool =
fun v_position v_failure ->
(match v_failure with
| None ->
true
| (Some ((Failure (v_limit, v_diagnostic)))) ->
(Base.nat_is_lt (v_position) (v_limit)))
and (* check_scheduler.bend:251 *)
f_first_failure : (t_Failure) option -> t_Failure -> (t_Failure) option =
fun v_previous v_candidate ->
(let (Failure (v_position, v_diagnostic)) = v_candidate in
(Base.bool_pick ((f_precedes_failure (v_position) (v_previous))) ((Some (v_candidate))) (v_previous)))
and (* check_scheduler.bend:257 *)
f_inference_grain : unit -> int =
fun () ->
128
and (* check_scheduler.bend:260 *)
f_check_task : t_Task -> unit -> t_Outcome =
fun v_task v_context ->
(match v_task with
| (Task (v_position, v_module, v_dependencies, v_cost)) ->
(Outcome (v_position, (G.f_check_group (v_module) (v_dependencies))))
| (EvidenceTask (v_position, v_module, v_dependencies, v_cost)) ->
(EvidenceOutcome (v_position, v_module, v_dependencies, (G.f_check_group_resolving (v_module) (v_dependencies))))
| (RetainedTask (v_position, v_checked)) ->
(Outcome (v_position, (Done (v_checked))))
| (RetainedEvidenceTask (v_position, v_module, v_dependencies, v_checked, v_needs)) ->
(EvidenceOutcome (v_position, v_module, v_dependencies, (Done ((G.Resolving (v_checked, v_needs)))))))
and (* check_scheduler.bend:271 *)
f_check_task_planned : t_Task -> unit -> t_Outcome =
fun v_task v_context ->
(match v_task with
| (Task (v_position, v_module, v_dependencies, v_cost)) ->
(Outcome (v_position, (G.f_check_group_planned (v_module) (v_dependencies))))
| (EvidenceTask (v_position, v_module, v_dependencies, v_cost)) ->
(EvidenceOutcome (v_position, v_module, v_dependencies, (G.f_check_group_resolving_planned (v_module) (v_dependencies))))
| (RetainedTask (v_position, v_checked)) ->
(Outcome (v_position, (Done (v_checked))))
| (RetainedEvidenceTask (v_position, v_module, v_dependencies, v_checked, v_needs)) ->
(EvidenceOutcome (v_position, v_module, v_dependencies, (Done ((G.Resolving (v_checked, v_needs)))))))
and (* check_scheduler.bend:282 *)
f_weighted_tasks : (t_Task) list -> ((t_Task) B.t_Weighted) list =
fun v_tasks ->
(match v_tasks with
| [] ->
[]
| ((Task (v_position, v_module, v_dependencies, v_cost)) :: v_tail) ->
((B.Weighted ((Task (v_position, v_module, v_dependencies, v_cost)), v_cost)) :: (f_weighted_tasks (v_tail)))
| ((EvidenceTask (v_position, v_module, v_dependencies, v_cost)) :: v_tail) ->
((B.Weighted ((EvidenceTask (v_position, v_module, v_dependencies, v_cost)), v_cost)) :: (f_weighted_tasks (v_tail)))
| ((RetainedTask (v_position, v_checked)) :: v_tail) ->
((B.Weighted ((RetainedTask (v_position, v_checked)), 0)) :: (f_weighted_tasks (v_tail)))
| ((RetainedEvidenceTask (v_position, v_module, v_dependencies, v_checked, v_needs)) :: v_tail) ->
((B.Weighted ((RetainedEvidenceTask (v_position, v_module, v_dependencies, v_checked, v_needs)), 0)) :: (f_weighted_tasks (v_tail))))
and (* check_scheduler.bend:295 *)
f_task_batch : (t_Task) list -> int -> (t_Task) B.t_Batch =
fun v_tasks v_grain ->
(B.f_plan ((f_weighted_tasks (v_tasks))) (v_grain))
and (* check_scheduler.bend:298 *)
f_check_batch_with_grain : (t_Task) list -> int -> (t_Outcome) list =
fun v_tasks v_grain ->
(B.f_execute (f_check_task) ((f_task_batch (v_tasks) (v_grain))) (()))
and (* check_scheduler.bend:301 *)
f_check_batch : (t_Task) list -> (t_Outcome) list =
fun v_tasks ->
(f_check_batch_with_grain (v_tasks) ((f_inference_grain ())))
and (* check_scheduler.bend:313 *)
f_clone_origin : Base.text -> Base.text =
fun v_name ->
(match v_name with
| (SCon ((Chr ((Base.W32 0x5d))), (SCon ((Chr ((Base.W32 0x2e))), v_tail)))) ->
v_tail
| (SCon (v_character, v_tail)) ->
(f_clone_origin (v_tail))
| SNil ->
SNil)
and (* check_scheduler.bend:322 *)
f_candidate_parts : int -> (M.t_Constant) list -> (M.t_Function) list -> (M.t_DataType) list -> (G.t_Interface) list -> (t_FrontierCandidate) option =
fun v_position v_constants v_functions v_types v_imports ->
(match (v_constants, v_functions) with
| ([], ((M.Function (v_name, v_exported, v_parameter, v_p, v_r, v_body)) :: [])) ->
(Base.bool_pick ((Base.string_starts_with (v_name) (s_2))) ((Some ((FrontierCandidate (v_position, (f_clone_origin (v_name)), (M.Function (s_3, v_exported, v_parameter, v_p, v_r, v_body)), v_types, v_imports))))) (None))
| (_, _) ->
None)
and (* check_scheduler.bend:329 *)
f_task_candidate : t_Task -> (t_FrontierCandidate) option =
fun v_task ->
(match v_task with
| (Task (v_position, (M.Module (v_constants, v_functions, v_types, v_operations)), v_imports, v_cost)) ->
(f_candidate_parts (v_position) (v_constants) (v_functions) (v_types) (v_imports))
| (EvidenceTask (v_position, (M.Module (v_constants, v_functions, v_types, v_operations)), v_imports, v_cost)) ->
(f_candidate_parts (v_position) (v_constants) (v_functions) (v_types) (v_imports))
| (RetainedTask (v_position, v_checked)) ->
None
| (RetainedEvidenceTask (v_position, v_module, v_imports, v_checked, v_needs)) ->
None)
and (* check_scheduler.bend:340 *)
f_same_candidate : t_FrontierCandidate -> t_FrontierCandidate -> bool =
fun v_left v_right ->
(let (FrontierCandidate (v_left_position, v_left_origin, v_left_function, v_left_types, v_left_imports)) = v_left in
(let (FrontierCandidate (v_right_position, v_right_origin, v_right_function, v_right_types, v_right_imports)) = v_right in
(Base.bool_and ((M.f_name_equal (v_left_origin) (v_right_origin))) ((Base.bool_and ((Core.f_same_imports (v_left_imports) (v_right_imports))) ((AlphaCompare.f_same_alpha_module ((M.Module ([], [v_left_function], v_left_types, []))) ((M.Module ([], [v_right_function], v_right_types, []))))))))))
and (* check_scheduler.bend:345 *)
f_candidate_position : t_FrontierCandidate -> int =
fun v_candidate ->
(let (FrontierCandidate (v_position, v_origin, v_function, v_types, v_imports)) = v_candidate in
v_position)
and (* check_scheduler.bend:349 *)
f_find_candidate : (t_FrontierCandidate) list -> t_FrontierCandidate -> (int) option -> (int) option =
fun v_prior v_current v_found ->
(match (v_prior, v_found) with
| (_, (Some (v_position))) ->
(Some (v_position))
| ([], None) ->
None
| ((v_earlier :: v_tail), None) ->
(f_find_candidate (v_tail) (v_current) ((Base.bool_pick ((f_same_candidate (v_earlier) (v_current))) ((Some ((f_candidate_position (v_earlier))))) (None)))))
and (* check_scheduler.bend:364 *)
f_plan_found : (int) option -> (t_FrontierCandidate) list -> t_FrontierCandidate -> t_Task -> t_BatchState -> t_BatchState =
fun v_found v_prior v_candidate v_task v_state ->
(match v_found with
| None ->
(let (FrontierCandidate (v_position, v_origin, v_function, v_types, v_imports)) = v_candidate in
(let (BatchState (v_known, v_originals, v_representatives, v_followers)) = v_state in
(BatchState ((Base.map_set (v_known) (v_origin) (((FrontierCandidate (v_position, v_origin, v_function, v_types, v_imports)) :: v_prior))), (v_task :: v_originals), (v_task :: v_representatives), v_followers))))
| (Some (v_representative)) ->
(let (BatchState (v_known, v_originals, v_representatives, v_followers)) = v_state in
(BatchState (v_known, (v_task :: v_originals), v_representatives, (NatIndex.f_set (v_followers) ((f_candidate_position (v_candidate))) (v_representative))))))
and (* check_scheduler.bend:374 *)
f_plan_prior : ((t_FrontierCandidate) list) option -> t_FrontierCandidate -> t_Task -> t_BatchState -> t_BatchState =
fun v_prior v_candidate v_task v_state ->
(match v_prior with
| None ->
(f_plan_found (None) ([]) (v_candidate) (v_task) (v_state))
| (Some (v_previous)) ->
(f_plan_found ((f_find_candidate (v_previous) (v_candidate) (None))) (v_previous) (v_candidate) (v_task) (v_state)))
and (* check_scheduler.bend:381 *)
f_plan_candidate : (t_FrontierCandidate) option -> t_Task -> t_BatchState -> t_BatchState =
fun v_candidate v_task v_state ->
(match v_candidate with
| None ->
(let (BatchState (v_known, v_originals, v_representatives, v_followers)) = v_state in
(BatchState (v_known, (v_task :: v_originals), (v_task :: v_representatives), v_followers)))
| (Some (v_value)) ->
(let (FrontierCandidate (v_position, v_origin, v_function, v_types, v_imports)) = v_value in
(let (BatchState (v_known, v_originals, v_representatives, v_followers)) = v_state in
(f_plan_prior ((Index.f_find (v_known) (v_origin))) ((FrontierCandidate (v_position, v_origin, v_function, v_types, v_imports))) (v_task) ((BatchState (v_known, v_originals, v_representatives, v_followers)))))))
and (* check_scheduler.bend:391 *)
f_finish_plan : t_BatchState -> t_PlannedBatch =
fun v_state ->
(let (BatchState (v_known, v_originals, v_representatives, v_followers)) = v_state in
(PlannedBatch ((Base.list_reverse (v_originals)), (Base.list_reverse (v_representatives)), v_followers)))
and (* check_scheduler.bend:395 *)
f_plan_batch : (t_Task) list -> t_BatchState -> t_PlannedBatch =
fun v_remaining v_state ->
(match v_remaining with
| [] ->
(f_finish_plan (v_state))
| (v_task :: v_tail) ->
(f_plan_batch (v_tail) ((f_plan_candidate ((f_task_candidate (v_task))) (v_task) (v_state)))))
and (* check_scheduler.bend:402 *)
f_batch_outcome_position : t_Outcome -> int =
fun v_outcome ->
(match v_outcome with
| (Outcome (v_position, v_checked)) ->
v_position
| (EvidenceOutcome (v_position, v_module, v_imports, v_checked)) ->
v_position)
and (* check_scheduler.bend:409 *)
f_index_outcomes : (t_Outcome) list -> (t_Outcome) NatIndex.t_Index -> (t_Outcome) NatIndex.t_Index =
fun v_outcomes v_known ->
(match v_outcomes with
| [] ->
v_known
| (v_outcome :: v_tail) ->
(f_index_outcomes (v_tail) ((NatIndex.f_set (v_known) ((f_batch_outcome_position (v_outcome))) (v_outcome)))))
and (* check_scheduler.bend:416 *)
f_resolving_checked : (M.t_Diagnostic, G.t_Resolving) Base.result_ -> (M.t_Diagnostic, G.t_CheckedGroup) Base.result_ =
fun v_result ->
(match v_result with
| (Fail (v_diagnostic)) ->
(Fail (v_diagnostic))
| (Done (v_resolved)) ->
(Done ((G.f_resolving_group (v_resolved)))))
and (* check_scheduler.bend:423 *)
f_outcome_checked : t_Outcome -> (M.t_Diagnostic, G.t_CheckedGroup) Base.result_ =
fun v_outcome ->
(match v_outcome with
| (Outcome (v_position, v_checked)) ->
v_checked
| (EvidenceOutcome (v_position, v_module, v_imports, v_checked)) ->
(f_resolving_checked (v_checked)))
and (* check_scheduler.bend:430 *)
f_replay_parts : (M.t_CheckedConstant) list -> (M.t_CheckedFunction) list -> (G.t_Interface) list -> (M.t_Constant) list -> (M.t_Function) list -> (M.t_DataType) list -> (M.t_Operation) list -> (G.t_CheckedGroup) option =
fun v_old_constants v_old_functions v_old_interfaces v_constants v_functions v_types v_operations ->
(match (v_old_constants, v_old_functions, v_old_interfaces, v_constants, v_functions) with
| ([], ((M.CheckedFunction (v_old_function, (M.Signature (v_old_name, v_parameter, v_result, v_variables, v_row)), v_effects)) :: []), ((G.Interface (v_interface_name, G.FunctionInterface, v_template, v_parameters, v_interface_effects, [])) :: []), [], ((M.Function (v_current_name, v_exported, v_argument, v_p, v_r, v_body)) :: [])) ->
(Base.bool_pick ((M.f_name_equal (v_old_name) (v_interface_name))) ((Some ((G.CheckedGroup ((M.CheckedModule ([], [(M.CheckedFunction ((M.Function (v_current_name, v_exported, v_argument, v_p, v_r, v_body)), (M.Signature (v_current_name, v_parameter, v_result, v_variables, v_row)), v_effects))], v_types, v_operations)), [(G.Interface (v_current_name, G.FunctionInterface, v_template, v_parameters, v_interface_effects, []))], []))))) (None))
| (_, _, _, _, _) ->
None)
and (* check_scheduler.bend:440 *)
f_replay_for_task : G.t_CheckedGroup -> t_Task -> (G.t_CheckedGroup) option =
fun v_prior v_task ->
(match (v_prior, v_task) with
| ((G.CheckedGroup ((M.CheckedModule (v_old_constants, v_old_functions, v_old_types, v_old_operations)), v_old_interfaces, [])), (Task (v_position, (M.Module (v_constants, v_functions, v_types, v_operations)), v_imports, v_cost))) ->
(f_replay_parts (v_old_constants) (v_old_functions) (v_old_interfaces) (v_constants) (v_functions) (v_types) (v_operations))
| ((G.CheckedGroup ((M.CheckedModule (v_old_constants, v_old_functions, v_old_types, v_old_operations)), v_old_interfaces, [])), (EvidenceTask (v_position, (M.Module (v_constants, v_functions, v_types, v_operations)), v_imports, v_cost))) ->
(f_replay_parts (v_old_constants) (v_old_functions) (v_old_interfaces) (v_constants) (v_functions) (v_types) (v_operations))
| (_, _) ->
None)
and (* check_scheduler.bend:449 *)
f_replay_outcome : t_Task -> G.t_CheckedGroup -> t_Outcome =
fun v_task v_checked ->
(match v_task with
| (Task (v_position, v_module, v_imports, v_cost)) ->
(Outcome (v_position, (Done (v_checked))))
| (EvidenceTask (v_position, v_module, v_imports, v_cost)) ->
(EvidenceOutcome (v_position, v_module, v_imports, (Done ((G.Resolving (v_checked, []))))))
| (RetainedTask (v_position, v_prior)) ->
(Outcome (v_position, (Done (v_prior))))
| (RetainedEvidenceTask (v_position, v_module, v_imports, v_prior, v_needs)) ->
(EvidenceOutcome (v_position, v_module, v_imports, (Done ((G.Resolving (v_prior, v_needs)))))))
and (* check_scheduler.bend:460 *)
f_replay_found : (G.t_CheckedGroup) option -> t_Task -> t_Outcome =
fun v_replayed v_task ->
(match v_replayed with
| None ->
(f_check_task_planned (v_task) (()))
| (Some (v_checked)) ->
(f_replay_outcome (v_task) (v_checked)))
and (* check_scheduler.bend:467 *)
f_representative_found : (M.t_Diagnostic, G.t_CheckedGroup) Base.result_ -> t_Task -> t_Outcome =
fun v_result v_task ->
(match v_result with
| (Fail (v_diagnostic)) ->
(f_check_task_planned (v_task) (()))
| (Done (v_checked)) ->
(f_replay_found ((f_replay_for_task (v_checked) (v_task))) (v_task)))
and (* check_scheduler.bend:474 *)
f_follower_found : (t_Outcome) option -> t_Task -> t_Outcome =
fun v_prior v_task ->
(match v_prior with
| None ->
(f_check_task_planned (v_task) (()))
| (Some (v_outcome)) ->
(f_representative_found ((f_outcome_checked (v_outcome))) (v_task)))
and (* check_scheduler.bend:481 *)
f_task_position : t_Task -> int =
fun v_task ->
(match v_task with
| (Task (v_position, v_module, v_imports, v_cost)) ->
v_position
| (EvidenceTask (v_position, v_module, v_imports, v_cost)) ->
v_position
| (RetainedTask (v_position, v_checked)) ->
v_position
| (RetainedEvidenceTask (v_position, v_module, v_imports, v_checked, v_needs)) ->
v_position)
and (* check_scheduler.bend:492 *)
f_original_found : (t_Outcome) option -> t_Task -> t_Outcome =
fun v_prior v_task ->
(match v_prior with
| None ->
(f_check_task_planned (v_task) (()))
| (Some (v_outcome)) ->
v_outcome)
and (* check_scheduler.bend:499 *)
f_restore_found : (int) option -> t_Task -> (t_Outcome) NatIndex.t_Index -> t_Outcome =
fun v_representative v_task v_outcomes ->
(match v_representative with
| None ->
(f_original_found ((NatIndex.f_find (v_outcomes) ((f_task_position (v_task))))) (v_task))
| (Some (v_position)) ->
(f_follower_found ((NatIndex.f_find (v_outcomes) (v_position))) (v_task)))
and (* check_scheduler.bend:506 *)
f_restore_batch : (t_Task) list -> (t_Outcome) NatIndex.t_Index -> (int) NatIndex.t_Index -> (t_Outcome) list -> (t_Outcome) list =
fun v_tasks v_representatives v_followers v_reversed ->
(match v_tasks with
| [] ->
(Base.list_reverse (v_reversed))
| (v_task :: v_tail) ->
(f_restore_batch (v_tail) (v_representatives) (v_followers) (((f_restore_found ((NatIndex.f_find (v_followers) ((f_task_position (v_task))))) (v_task) (v_representatives)) :: v_reversed))))
and (* check_scheduler.bend:513 *)
f_execute_planned_batch : t_PlannedBatch -> (t_Outcome) list =
fun v_plan ->
(let (PlannedBatch (v_originals, v_representatives, v_followers)) = v_plan in
(let v_checked = (B.f_execute (f_check_task_planned) ((f_task_batch (v_representatives) ((f_inference_grain ())))) (())) in
(f_restore_batch (v_originals) ((f_index_outcomes (v_checked) ((NatIndex.f_new ())))) (v_followers) ([]))))
and (* check_scheduler.bend:520 *)
f_check_batch_planned : (t_Task) list -> (t_Outcome) list =
fun v_tasks ->
(B.f_execute (f_check_task_planned) ((f_task_batch (v_tasks) ((f_inference_grain ())))) (()))
and (* check_scheduler.bend:525 *)
f_check_batch_same_catalog : (t_Task) list -> (t_Outcome) list =
fun v_tasks ->
(f_execute_planned_batch ((f_plan_batch (v_tasks) ((BatchState ((Base.map_new ()), [], [], (NatIndex.f_new ())))))))
and (* check_scheduler.bend:531 *)
f_same_level : (t_Scheduled) list -> int -> bool =
fun v_scheduled v_level ->
(match v_scheduled with
| [] ->
false
| ((Scheduled (v_position, v_next, v_job)) :: v_tail) ->
(Base.nat_is_eq (v_level) (v_next)))
and (* check_scheduler.bend:538 *)
f_take_frontier : (t_Scheduled) list -> int -> (t_Scheduled) list -> bool -> t_Frontier =
fun v_scheduled v_level v_reversed v_same ->
(match (v_scheduled, v_same) with
| (v_remaining, false) ->
(Frontier ((Base.list_reverse (v_reversed)), v_remaining))
| ([], true) ->
(Frontier ((Base.list_reverse (v_reversed)), []))
| ((v_head :: v_tail), true) ->
(f_take_frontier (v_tail) (v_level) ((v_head :: v_reversed)) ((f_same_level (v_tail) (v_level)))))
and (* check_scheduler.bend:556 *)
f_expression_cost : int -> (t_CostWork) list -> int -> int =
fun v_fuel v_pending v_total ->
(match (v_fuel, v_pending) with
| (_, []) ->
v_total
| (0, _) ->
v_total
| (__nat_1, ((ExpressionsCost ([])) :: v_tail)) when __nat_1 >= 1 ->
(let v_rest = (__nat_1 - 1) in
(f_expression_cost (v_rest) (v_tail) (v_total)))
| (__nat_2, ((ExpressionsCost ((v_head :: v_remaining))) :: v_tail)) when __nat_2 >= 1 ->
(let v_rest = (__nat_2 - 1) in
(f_expression_cost (v_rest) (((ExpressionCost (v_head)) :: ((ExpressionsCost (v_remaining)) :: v_tail))) (v_total)))
| (__nat_3, ((ArmsCost ([])) :: v_tail)) when __nat_3 >= 1 ->
(let v_rest = (__nat_3 - 1) in
(f_expression_cost (v_rest) (v_tail) (v_total)))
| (__nat_4, ((ArmsCost (((M.MatchArm (v_patterns, v_body)) :: v_remaining))) :: v_tail)) when __nat_4 >= 1 ->
(let v_rest = (__nat_4 - 1) in
(f_expression_cost (v_rest) (((PatternsCost (v_patterns)) :: ((ExpressionCost (v_body)) :: ((ArmsCost (v_remaining)) :: v_tail)))) (v_total)))
| (__nat_5, ((PatternsCost ([])) :: v_tail)) when __nat_5 >= 1 ->
(let v_rest = (__nat_5 - 1) in
(f_expression_cost (v_rest) (v_tail) (v_total)))
| (__nat_6, ((PatternsCost ((v_head :: v_remaining))) :: v_tail)) when __nat_6 >= 1 ->
(let v_rest = (__nat_6 - 1) in
(f_expression_cost (v_rest) (((PatternCost (v_head)) :: ((PatternsCost (v_remaining)) :: v_tail))) (v_total)))
| (__nat_7, ((PatternCost ((M.ProductPattern (v_elements)))) :: v_tail)) when __nat_7 >= 1 ->
(let v_rest = (__nat_7 - 1) in
(f_expression_cost (v_rest) (((PatternsCost (v_elements)) :: v_tail)) ((Base.nat_add (v_total) (8)))))
| (__nat_8, ((PatternCost ((M.ConstructorPattern (v_name, (Some (v_payload)))))) :: v_tail)) when __nat_8 >= 1 ->
(let v_rest = (__nat_8 - 1) in
(f_expression_cost (v_rest) (((PatternCost (v_payload)) :: v_tail)) ((Base.nat_add (v_total) (8)))))
| (__nat_9, ((PatternCost (v_other)) :: v_tail)) when __nat_9 >= 1 ->
(let v_rest = (__nat_9 - 1) in
(f_expression_cost (v_rest) (v_tail) ((Base.nat_add (v_total) (8)))))
| (__nat_10, ((ExpressionCost ((M.ConstructExpr (v_name, (Some (v_payload)))))) :: v_tail)) when __nat_10 >= 1 ->
(let v_rest = (__nat_10 - 1) in
(f_expression_cost (v_rest) (((ExpressionCost (v_payload)) :: v_tail)) ((Base.nat_add (v_total) (8)))))
| (__nat_11, ((ExpressionCost ((M.LambdaExpr (v_identity, v_parameter, v_p, v_r, v_body)))) :: v_tail)) when __nat_11 >= 1 ->
(let v_rest = (__nat_11 - 1) in
(f_expression_cost (v_rest) (((ExpressionCost (v_body)) :: v_tail)) ((Base.nat_add (v_total) (16)))))
| (__nat_12, ((ExpressionCost ((M.ApplyExpr (v_callee, v_argument)))) :: v_tail)) when __nat_12 >= 1 ->
(let v_rest = (__nat_12 - 1) in
(f_expression_cost (v_rest) (((ExpressionCost (v_callee)) :: ((ExpressionCost (v_argument)) :: v_tail))) ((Base.nat_add (v_total) (16)))))
| (__nat_13, ((ExpressionCost ((M.CallExpr (v_callee, v_argument)))) :: v_tail)) when __nat_13 >= 1 ->
(let v_rest = (__nat_13 - 1) in
(f_expression_cost (v_rest) (((ExpressionCost (v_argument)) :: v_tail)) ((Base.nat_add (v_total) (16)))))
| (__nat_14, ((ExpressionCost ((M.ScalarExpr (v_operator, v_left, v_right)))) :: v_tail)) when __nat_14 >= 1 ->
(let v_rest = (__nat_14 - 1) in
(f_expression_cost (v_rest) (((ExpressionCost (v_left)) :: ((ExpressionCost (v_right)) :: v_tail))) ((Base.nat_add (v_total) (8)))))
| (__nat_15, ((ExpressionCost ((M.LetExpr (v_name, v_value, v_body)))) :: v_tail)) when __nat_15 >= 1 ->
(let v_rest = (__nat_15 - 1) in
(f_expression_cost (v_rest) (((ExpressionCost (v_value)) :: ((ExpressionCost (v_body)) :: v_tail))) ((Base.nat_add (v_total) (16)))))
| (__nat_16, ((ExpressionCost ((M.UseExpr (v_name, v_value, v_body)))) :: v_tail)) when __nat_16 >= 1 ->
(let v_rest = (__nat_16 - 1) in
(f_expression_cost (v_rest) (((ExpressionCost (v_value)) :: ((ExpressionCost (v_body)) :: v_tail))) ((Base.nat_add (v_total) (16)))))
| (__nat_17, ((ExpressionCost ((M.IfExpr (v_condition, v_consequent, v_alternative)))) :: v_tail)) when __nat_17 >= 1 ->
(let v_rest = (__nat_17 - 1) in
(f_expression_cost (v_rest) (((ExpressionCost (v_condition)) :: ((ExpressionCost (v_consequent)) :: ((ExpressionCost (v_alternative)) :: v_tail)))) ((Base.nat_add (v_total) (8)))))
| (__nat_18, ((ExpressionCost ((M.SequenceExpr (v_first, v_next)))) :: v_tail)) when __nat_18 >= 1 ->
(let v_rest = (__nat_18 - 1) in
(f_expression_cost (v_rest) (((ExpressionCost (v_first)) :: ((ExpressionCost (v_next)) :: v_tail))) ((Base.nat_add (v_total) (8)))))
| (__nat_19, ((ExpressionCost ((M.MatchExpr (v_values, v_arms)))) :: v_tail)) when __nat_19 >= 1 ->
(let v_rest = (__nat_19 - 1) in
(f_expression_cost (v_rest) (((ExpressionsCost (v_values)) :: ((ArmsCost (v_arms)) :: v_tail))) ((Base.nat_add (v_total) (16)))))
| (__nat_20, ((ExpressionCost ((M.GuardExpr (v_pattern, v_value, v_alternative, v_body)))) :: v_tail)) when __nat_20 >= 1 ->
(let v_rest = (__nat_20 - 1) in
(f_expression_cost (v_rest) (((PatternCost (v_pattern)) :: ((ExpressionCost (v_value)) :: ((ExpressionCost (v_alternative)) :: ((ExpressionCost (v_body)) :: v_tail))))) ((Base.nat_add (v_total) (16)))))
| (__nat_21, ((ExpressionCost ((M.BlockExpr (v_label, v_body)))) :: v_tail)) when __nat_21 >= 1 ->
(let v_rest = (__nat_21 - 1) in
(f_expression_cost (v_rest) (((ExpressionCost (v_body)) :: v_tail)) ((Base.nat_add (v_total) (8)))))
| (__nat_22, ((ExpressionCost ((M.ReturnExpr (v_label, v_value)))) :: v_tail)) when __nat_22 >= 1 ->
(let v_rest = (__nat_22 - 1) in
(f_expression_cost (v_rest) (((ExpressionCost (v_value)) :: v_tail)) ((Base.nat_add (v_total) (8)))))
| (__nat_23, ((ExpressionCost ((M.RuntimeInitExpr (v_value)))) :: v_tail)) when __nat_23 >= 1 ->
(let v_rest = (__nat_23 - 1) in
(f_expression_cost (v_rest) (((ExpressionCost (v_value)) :: v_tail)) ((Base.nat_add (v_total) (8)))))
| (__nat_24, ((ExpressionCost ((M.SourceExpr (v_offset, v_annotation, v_value)))) :: v_tail)) when __nat_24 >= 1 ->
(let v_rest = (__nat_24 - 1) in
(f_expression_cost (v_rest) (((ExpressionCost (v_value)) :: v_tail)) ((Base.nat_add (v_total) (8)))))
| (__nat_25, ((ExpressionCost ((M.QualifiedExpr (v_offset, v_annotation, v_predicates, v_value)))) :: v_tail)) when __nat_25 >= 1 ->
(let v_rest = (__nat_25 - 1) in
(f_expression_cost (v_rest) (((ExpressionCost (v_value)) :: v_tail)) ((Base.nat_add (v_total) (8)))))
| (__nat_26, ((ExpressionCost ((M.InstantiationExpr (v_site, v_value)))) :: v_tail)) when __nat_26 >= 1 ->
(let v_rest = (__nat_26 - 1) in
(f_expression_cost (v_rest) (((ExpressionCost (v_value)) :: v_tail)) ((Base.nat_add (v_total) (8)))))
| (__nat_27, ((ExpressionCost ((M.TagExpr (v_offset, v_callee, v_argument)))) :: v_tail)) when __nat_27 >= 1 ->
(let v_rest = (__nat_27 - 1) in
(f_expression_cost (v_rest) (((ExpressionCost (v_callee)) :: ((ExpressionCost (v_argument)) :: v_tail))) ((Base.nat_add (v_total) (16)))))
| (__nat_28, ((ExpressionCost ((M.UnaryExpr (v_operator, v_value)))) :: v_tail)) when __nat_28 >= 1 ->
(let v_rest = (__nat_28 - 1) in
(f_expression_cost (v_rest) (((ExpressionCost (v_value)) :: v_tail)) ((Base.nat_add (v_total) (8)))))
| (__nat_29, ((ExpressionCost ((M.StateProviderExpr (v_read, v_write, v_initial)))) :: v_tail)) when __nat_29 >= 1 ->
(let v_rest = (__nat_29 - 1) in
(f_expression_cost (v_rest) (((ExpressionCost (v_initial)) :: v_tail)) ((Base.nat_add (v_total) (16)))))
| (__nat_30, ((ExpressionCost ((M.ProviderExpr (v_identity, v_implementation)))) :: v_tail)) when __nat_30 >= 1 ->
(let v_rest = (__nat_30 - 1) in
(f_expression_cost (v_rest) (((ExpressionCost (v_implementation)) :: v_tail)) ((Base.nat_add (v_total) (16)))))
| (__nat_31, ((ExpressionCost ((M.HandleExpr (v_provider, v_body)))) :: v_tail)) when __nat_31 >= 1 ->
(let v_rest = (__nat_31 - 1) in
(f_expression_cost (v_rest) (((ExpressionCost (v_provider)) :: ((ExpressionCost (v_body)) :: v_tail))) ((Base.nat_add (v_total) (16)))))
| (__nat_32, ((ExpressionCost ((M.EffectHasExpr (v_set, v_operation)))) :: v_tail)) when __nat_32 >= 1 ->
(let v_rest = (__nat_32 - 1) in
(f_expression_cost (v_rest) (((ExpressionCost (v_set)) :: ((ExpressionCost (v_operation)) :: v_tail))) ((Base.nat_add (v_total) (8)))))
| (__nat_33, ((ExpressionCost ((M.EffectCountExpr (v_set)))) :: v_tail)) when __nat_33 >= 1 ->
(let v_rest = (__nat_33 - 1) in
(f_expression_cost (v_rest) (((ExpressionCost (v_set)) :: v_tail)) ((Base.nat_add (v_total) (8)))))
| (__nat_34, ((ExpressionCost ((M.EffectSameExpr (v_left, v_right)))) :: v_tail)) when __nat_34 >= 1 ->
(let v_rest = (__nat_34 - 1) in
(f_expression_cost (v_rest) (((ExpressionCost (v_left)) :: ((ExpressionCost (v_right)) :: v_tail))) ((Base.nat_add (v_total) (8)))))
| (__nat_35, ((ExpressionCost ((M.ProductExpr (v_elements)))) :: v_tail)) when __nat_35 >= 1 ->
(let v_rest = (__nat_35 - 1) in
(f_expression_cost (v_rest) (((ExpressionsCost (v_elements)) :: v_tail)) ((Base.nat_add (v_total) (8)))))
| (__nat_36, ((ExpressionCost ((M.ProjectExpr (v_value, v_index)))) :: v_tail)) when __nat_36 >= 1 ->
(let v_rest = (__nat_36 - 1) in
(f_expression_cost (v_rest) (((ExpressionCost (v_value)) :: v_tail)) ((Base.nat_add (v_total) (8)))))
| (__nat_37, ((ExpressionCost ((M.ArrayExpr (v_elements)))) :: v_tail)) when __nat_37 >= 1 ->
(let v_rest = (__nat_37 - 1) in
(f_expression_cost (v_rest) (((ExpressionsCost (v_elements)) :: v_tail)) ((Base.nat_add (v_total) (8)))))
| (__nat_38, ((ExpressionCost ((M.ForExpr (v_index, v_start, v_end, v_state, v_initial, v_body)))) :: v_tail)) when __nat_38 >= 1 ->
(let v_rest = (__nat_38 - 1) in
(f_expression_cost (v_rest) (((ExpressionsCost ([v_start; v_end; v_initial; v_body])) :: v_tail)) ((Base.nat_add (v_total) (8)))))
| (__nat_39, ((ExpressionCost ((M.ForeverExpr (v_state, v_initial, v_body)))) :: v_tail)) when __nat_39 >= 1 ->
(let v_rest = (__nat_39 - 1) in
(f_expression_cost (v_rest) (((ExpressionsCost ([v_initial; v_body])) :: v_tail)) ((Base.nat_add (v_total) (8)))))
| (__nat_40, ((ExpressionCost ((M.ArrayGenerateExpr (v_count, v_generator)))) :: v_tail)) when __nat_40 >= 1 ->
(let v_rest = (__nat_40 - 1) in
(f_expression_cost (v_rest) (((ExpressionCost (v_count)) :: ((ExpressionCost (v_generator)) :: v_tail))) ((Base.nat_add (v_total) (8)))))
| (__nat_41, ((ExpressionCost ((M.ArrayFillExpr (v_count, v_value)))) :: v_tail)) when __nat_41 >= 1 ->
(let v_rest = (__nat_41 - 1) in
(f_expression_cost (v_rest) (((ExpressionCost (v_count)) :: ((ExpressionCost (v_value)) :: v_tail))) ((Base.nat_add (v_total) (8)))))
| (__nat_42, ((ExpressionCost ((M.ArrayGetExpr (v_array, v_index)))) :: v_tail)) when __nat_42 >= 1 ->
(let v_rest = (__nat_42 - 1) in
(f_expression_cost (v_rest) (((ExpressionCost (v_array)) :: ((ExpressionCost (v_index)) :: v_tail))) ((Base.nat_add (v_total) (8)))))
| (__nat_43, ((ExpressionCost ((M.ArraySetExpr (v_array, v_index, v_value)))) :: v_tail)) when __nat_43 >= 1 ->
(let v_rest = (__nat_43 - 1) in
(f_expression_cost (v_rest) (((ExpressionCost (v_array)) :: ((ExpressionCost (v_index)) :: ((ExpressionCost (v_value)) :: v_tail)))) ((Base.nat_add (v_total) (8)))))
| (__nat_44, ((ExpressionCost ((M.ArrayLengthExpr (v_array)))) :: v_tail)) when __nat_44 >= 1 ->
(let v_rest = (__nat_44 - 1) in
(f_expression_cost (v_rest) (((ExpressionCost (v_array)) :: v_tail)) ((Base.nat_add (v_total) (8)))))
| (__nat_45, ((ExpressionCost (v_other)) :: v_tail)) when __nat_45 >= 1 ->
(let v_rest = (__nat_45 - 1) in
(f_expression_cost (v_rest) (v_tail) ((Base.nat_add (v_total) (8))))))
and (* check_scheduler.bend:653 *)
f_function_work : (M.t_Function) list -> (t_CostWork) list -> (t_CostWork) list =
fun v_functions v_work ->
(match v_functions with
| [] ->
v_work
| ((M.Function (v_name, v_exported, v_parameter, v_p, v_r, v_body)) :: v_tail) ->
(f_function_work (v_tail) (((ExpressionCost (v_body)) :: v_work))))
and (* check_scheduler.bend:660 *)
f_constant_work : (M.t_Constant) list -> (t_CostWork) list -> (t_CostWork) list =
fun v_constants v_work ->
(match v_constants with
| [] ->
v_work
| ((M.Constant (v_name, v_exported, v_annotation, v_value)) :: v_tail) ->
(f_constant_work (v_tail) (((ExpressionCost (v_value)) :: v_work))))
and (* check_scheduler.bend:667 *)
f_module_cost : M.t_Module -> int =
fun v_module ->
(let (M.Module (v_constants, v_functions, v_types, v_operations)) = v_module in
(f_expression_cost (65536) ((f_function_work (v_functions) ((f_constant_work (v_constants) ([]))))) (64)))
and (* check_scheduler.bend:671 *)
f_cached_cost : (Base.text) list -> (int) Base.map -> int -> (int) option =
fun v_names v_costs v_total ->
(match v_names with
| [] ->
(Some (v_total))
| (v_name :: v_tail) ->
(match (Index.f_find (v_costs) (v_name)) with
| None -> None
| Some v_cost ->
(f_cached_cost (v_tail) (v_costs) ((Base.nat_add (v_total) ((Base.nat_sub (v_cost) (64))))))))
and (* check_scheduler.bend:680 *)
f_group_cost_found : (int) option -> t_Catalog -> G.t_Job -> int =
fun v_found v_known v_job ->
(match v_found with
| (Some (v_cost)) ->
v_cost
| None ->
(f_module_cost ((f_group_module (v_known) (v_job)))))
and (* check_scheduler.bend:689 *)
f_group_cost : t_Catalog -> G.t_Job -> int =
fun v_known v_job ->
(let (Catalog (v_functions, v_constants, v_types, v_operations, v_costs, v_core, v_evidence, v_resolving)) = v_known in
(let (G.Job (v_members, v_dependencies, v_required_types)) = v_job in
(f_group_cost_found ((f_cached_cost (v_members) (v_costs) (64))) (v_known) (v_job))))
and (* check_scheduler.bend:705 *)
f_empty_completed : unit -> t_Completed =
fun () ->
(Completed ((Base.map_new ()), (Base.map_new ()), (Base.map_new ()), [], None, [], []))
and (* check_scheduler.bend:708 *)
f_publish_checked : G.t_CheckedGroup -> t_Completed -> t_Completed =
fun v_checked v_completed ->
(let (G.CheckedGroup ((M.CheckedModule (v_cs, v_fs, v_types, v_operations)), v_exported, v_uses)) = v_checked in
(let (Completed (v_interfaces, v_functions, v_constants, v_published, v_failure, v_certificates, v_needs)) = v_completed in
(Completed ((f_publish_interfaces (v_exported) (v_interfaces)), (f_publish_functions (v_fs) (v_functions)), (f_publish_constants (v_cs) (v_constants)), (Base.list_reverse_go (v_exported) (v_published)), v_failure, v_certificates, v_needs))))
and (* check_scheduler.bend:713 *)
f_publish_failure : int -> M.t_Diagnostic -> t_Completed -> t_Completed =
fun v_position v_diagnostic v_completed ->
(let (Completed (v_interfaces, v_functions, v_constants, v_published, v_failure, v_certificates, v_needs)) = v_completed in
(Completed (v_interfaces, v_functions, v_constants, v_published, (f_first_failure (v_failure) ((Failure (v_position, v_diagnostic)))), v_certificates, v_needs)))
and (* check_scheduler.bend:717 *)
f_publish_certificate : M.t_Module -> G.t_CheckedGroup -> (G.t_Interface) list -> t_Completed -> t_Completed =
fun v_module v_checked v_imports v_completed ->
(let (Completed (v_interfaces, v_functions, v_constants, v_published, v_failure, v_certificates, v_needs)) = v_completed in
(Completed (v_interfaces, v_functions, v_constants, v_published, v_failure, ((Core.Certificate (v_module, v_checked, v_imports)) :: v_certificates), v_needs)))
and (* check_scheduler.bend:721 *)
f_publish_needs : (G.t_GroupNeeds) list -> t_Completed -> t_Completed =
fun v_resolved v_completed ->
(let (Completed (v_interfaces, v_functions, v_constants, v_published, v_failure, v_certificates, v_needs)) = v_completed in
(Completed (v_interfaces, v_functions, v_constants, v_published, v_failure, v_certificates, (Base.list_reverse_go (v_resolved) (v_needs)))))
and (* check_scheduler.bend:725 *)
f_publish_resolving : M.t_Module -> G.t_Resolving -> (G.t_Interface) list -> t_Completed -> t_Completed =
fun v_module v_resolved v_imports v_completed ->
(let (G.Resolving (v_checked, v_needs)) = v_resolved in
(f_publish_needs (v_needs) ((f_publish_certificate (v_module) (v_checked) (v_imports) ((f_publish_checked (v_checked) (v_completed)))))))
and (* check_scheduler.bend:729 *)
f_publish_outcomes : (t_Outcome) list -> t_Completed -> t_Completed =
fun v_outcomes v_completed ->
(match v_outcomes with
| [] ->
v_completed
| ((Outcome (v_position, (Fail (v_diagnostic)))) :: v_tail) ->
(f_publish_outcomes (v_tail) ((f_publish_failure (v_position) (v_diagnostic) (v_completed))))
| ((Outcome (v_position, (Done (v_checked)))) :: v_tail) ->
(f_publish_outcomes (v_tail) ((f_publish_checked (v_checked) (v_completed))))
| ((EvidenceOutcome (v_position, v_module, v_imports, (Fail (v_diagnostic)))) :: v_tail) ->
(f_publish_outcomes (v_tail) ((f_publish_failure (v_position) (v_diagnostic) (v_completed))))
| ((EvidenceOutcome (v_position, v_module, v_imports, (Done (v_resolved)))) :: v_tail) ->
(f_publish_outcomes (v_tail) ((f_publish_resolving (v_module) (v_resolved) (v_imports) (v_completed)))))
and (* check_scheduler.bend:745 *)
f_prepare_result : int -> (M.t_Diagnostic, t_Task) Base.result_ -> t_Preparation -> t_Preparation =
fun v_position v_result v_preparation ->
(match (v_result, v_preparation) with
| ((Done (v_task)), (Preparation (v_tasks, v_failures))) ->
(Preparation ((v_task :: v_tasks), v_failures))
| ((Fail (v_diagnostic)), (Preparation (v_tasks, v_failures))) ->
(Preparation (v_tasks, ((Outcome (v_position, (Fail (v_diagnostic)))) :: v_failures))))
and (* check_scheduler.bend:755 *)
f_selected_task : (G.t_CheckedGroup) option -> bool -> int -> M.t_Module -> (G.t_Interface) list -> t_Task =
fun v_found v_evidence v_position v_subset v_imports ->
(match (v_found, v_evidence) with
| ((Some (v_checked)), true) ->
(RetainedEvidenceTask (v_position, v_subset, v_imports, v_checked, []))
| ((Some (v_checked)), false) ->
(RetainedTask (v_position, v_checked))
| (None, true) ->
(EvidenceTask (v_position, v_subset, v_imports, (f_module_cost (v_subset))))
| (None, false) ->
(Task (v_position, v_subset, v_imports, (f_module_cost (v_subset)))))
and (* check_scheduler.bend:766 *)
f_resolving_task : (G.t_Resolving) option -> t_Catalog -> G.t_Job -> int -> M.t_Module -> (G.t_Interface) list -> t_Task =
fun v_found v_known v_job v_position v_subset v_imports ->
(match v_found with
| (Some ((G.Resolving (v_checked, v_needs)))) ->
(RetainedEvidenceTask (v_position, v_subset, v_imports, v_checked, v_needs))
| None ->
(f_selected_task ((f_retained_group (v_known) (v_job) (v_subset) (v_imports))) ((f_collecting (v_known))) (v_position) (v_subset) (v_imports)))
and (* check_scheduler.bend:773 *)
f_prepare_task : int -> G.t_Job -> t_Catalog -> (G.t_Interface) Base.map -> (M.t_Diagnostic, t_Task) Base.result_ =
fun v_position v_job v_known v_interfaces ->
(let (G.Job (v_members, v_dependencies, v_types)) = v_job in
(let v_subset = (f_group_module (v_known) (v_job)) in
(match (f_dependency_interfaces (v_dependencies) (v_interfaces)) with
| Fail __error -> Fail __error
| Done v_imports ->
(Done ((f_resolving_task ((f_retained_resolving (v_known) (v_job) (v_subset) (v_imports))) (v_known) (v_job) (v_position) (v_subset) (v_imports)))))))
and (* check_scheduler.bend:780 *)
f_next_allowed : (t_Scheduled) list -> (t_Failure) option -> bool =
fun v_ready v_failure ->
(match v_ready with
| [] ->
false
| ((Scheduled (v_position, v_level, v_job)) :: v_tail) ->
(f_precedes_failure (v_position) (v_failure)))
and (* check_scheduler.bend:787 *)
f_prepare_tasks : (t_Scheduled) list -> t_Catalog -> (G.t_Interface) Base.map -> (t_Failure) option -> t_Preparation -> bool -> t_Preparation =
fun v_ready v_known v_interfaces v_failure v_preparation v_allowed ->
(match (v_ready, v_allowed) with
| ([], _) ->
v_preparation
| (_, false) ->
v_preparation
| (((Scheduled (v_position, v_level, v_job)) :: v_tail), true) ->
(f_prepare_tasks (v_tail) (v_known) (v_interfaces) (v_failure) ((f_prepare_result (v_position) ((f_prepare_task (v_position) (v_job) (v_known) (v_interfaces))) (v_preparation))) ((f_next_allowed (v_tail) (v_failure)))))
and (* check_scheduler.bend:796 *)
f_outcome_position : t_Outcome -> int =
fun v_outcome ->
(match v_outcome with
| (Outcome (v_position, v_checked)) ->
v_position
| (EvidenceOutcome (v_position, v_module, v_imports, v_checked)) ->
v_position)
and (* check_scheduler.bend:803 *)
f_outcome_le : t_Outcome -> t_Outcome -> bool =
fun v_left v_right ->
(Base.nat_is_le ((f_outcome_position (v_left))) ((f_outcome_position (v_right))))
and (* check_scheduler.bend:806 *)
f_assembled : M.t_Module -> t_Completed -> (M.t_Diagnostic, M.t_CheckedModule) Base.result_ =
fun v_module v_completed ->
(let (M.Module (v_constants, v_functions, v_types, v_operations)) = v_module in
(let (Completed (v_interfaces, v_checked_functions, v_checked_constants, v_published, v_failure, v_certificates, v_needs)) = v_completed in
(match v_failure with
| (Some ((Failure (v_position, v_diagnostic)))) ->
(Fail (v_diagnostic))
| None ->
(match (f_ordered_functions (v_functions) (v_checked_functions)) with
| Fail __error -> Fail __error
| Done v_fs ->
(match (f_ordered_constants (v_constants) (v_checked_constants)) with
| Fail __error -> Fail __error
| Done v_cs ->
(Done ((M.CheckedModule (v_cs, v_fs, v_types, v_operations)))))))))
and (* check_scheduler.bend:818 *)
f_next_frontier : (t_Scheduled) list -> t_Frontier =
fun v_scheduled ->
(match v_scheduled with
| [] ->
(Frontier ([], []))
| ((Scheduled (v_position, v_level, v_job)) :: v_tail) ->
(f_take_frontier (((Scheduled (v_position, v_level, v_job)) :: v_tail)) (v_level) ([]) (true)))
and (* check_scheduler.bend:825 *)
f_publish_preparation : t_Preparation -> t_Completed -> t_Completed =
fun v_preparation v_completed ->
(let (Preparation (v_tasks, v_failures)) = v_preparation in
(let v_outcomes = (f_check_batch_same_catalog ((Base.list_reverse (v_tasks)))) in
(let v_ordered = (Base.list_sort (f_outcome_le) ((Base.list_reverse_go (v_failures) (v_outcomes)))) in
(f_publish_outcomes (v_ordered) (v_completed)))))
and (* check_scheduler.bend:831 *)
f_check_frontier : (t_Scheduled) list -> t_Catalog -> t_Completed -> t_Completed =
fun v_ready v_known v_completed ->
(let (Completed (v_interfaces, v_functions, v_constants, v_published, v_failure, v_certificates, v_needs)) = v_completed in
(f_publish_preparation ((f_prepare_tasks (v_ready) (v_known) (v_interfaces) (v_failure) ((Preparation ([], []))) ((f_next_allowed (v_ready) (v_failure))))) (v_completed)))
and (* check_scheduler.bend:835 *)
f_check_frontiers : int -> t_Frontier -> t_Catalog -> t_Completed -> (M.t_Diagnostic, t_Completed) Base.result_ =
fun v_fuel v_frontier v_known v_completed ->
(match (v_fuel, v_frontier) with
| (_, (Frontier ([], []))) ->
(Done (v_completed))
| (0, _) ->
(Fail ((M.Diagnostic (s_0, s_4, s_5))))
| (__nat_46, (Frontier (v_ready, v_pending))) when __nat_46 >= 1 ->
(let v_rest = (__nat_46 - 1) in
(f_check_frontiers (v_rest) ((f_next_frontier (v_pending))) (v_known) ((f_check_frontier (v_ready) (v_known) (v_completed))))))
and (* check_scheduler.bend:844 *)
f_chain_cost : (Chains.t_Job) list -> t_Catalog -> int -> int =
fun v_jobs v_known v_cost ->
(match v_jobs with
| [] ->
v_cost
| ((Chains.Job (v_position, v_job)) :: v_tail) ->
(f_chain_cost (v_tail) (v_known) ((Base.nat_add (v_cost) ((f_group_cost (v_known) (v_job)))))))
and (* check_scheduler.bend:851 *)
f_weighted_chains : (Chains.t_Chain) list -> t_Catalog -> ((Chains.t_Chain) B.t_Weighted) list =
fun v_chains v_known ->
(match v_chains with
| [] ->
[]
| (v_chain :: v_tail) ->
(let (Chains.Chain (v_position, v_level, v_jobs)) = v_chain in
((B.Weighted (v_chain, (f_chain_cost (v_jobs) (v_known) (0)))) :: (f_weighted_chains (v_tail) (v_known)))))
and (* check_scheduler.bend:859 *)
f_chain_batch : (Chains.t_Chain) list -> t_Catalog -> (Chains.t_Chain) B.t_Batch =
fun v_chains v_known ->
(B.f_plan ((f_weighted_chains (v_chains) (v_known))) ((f_inference_grain ())))
and (* check_scheduler.bend:862 *)
f_chain_allowed : (Chains.t_Job) list -> t_Completed -> bool =
fun v_jobs v_completed ->
(match v_jobs with
| [] ->
false
| ((Chains.Job (v_position, v_job)) :: v_tail) ->
(let (Completed (v_interfaces, v_functions, v_constants, v_published, v_failure, v_certificates, v_needs)) = v_completed in
(f_precedes_failure (v_position) (v_failure))))
and (* check_scheduler.bend:870 *)
f_check_chain : (Chains.t_Job) list -> t_Catalog -> t_Completed -> bool -> t_Completed =
fun v_jobs v_known v_completed v_allowed ->
(match (v_jobs, v_allowed) with
| ([], _) ->
v_completed
| (_, false) ->
v_completed
| (((Chains.Job (v_position, v_job)) :: v_tail), true) ->
(let v_next = (f_check_frontier ([(Scheduled (v_position, 0, v_job))]) (v_known) (v_completed)) in
(f_check_chain (v_tail) (v_known) (v_next) ((f_chain_allowed (v_tail) (v_next))))))
and (* check_scheduler.bend:883 *)
f_run_chain : Chains.t_Chain -> t_ChainContext -> t_Completed =
fun v_chain v_context ->
(let (Chains.Chain (v_position, v_level, v_jobs)) = v_chain in
(let (ChainContext (v_known, v_interfaces, v_failure)) = v_context in
(let v_initial = (Completed (v_interfaces, (Base.map_new ()), (Base.map_new ()), [], v_failure, [], [])) in
(f_check_chain (v_jobs) (v_known) (v_initial) ((f_chain_allowed (v_jobs) (v_initial)))))))
and (* check_scheduler.bend:889 *)
f_merge_failure : (t_Failure) option -> (t_Failure) option -> (t_Failure) option =
fun v_previous v_candidate ->
(match v_candidate with
| None ->
v_previous
| (Some (v_failure)) ->
(f_first_failure (v_previous) (v_failure)))
and (* check_scheduler.bend:898 *)
f_merge_completed : (t_Completed) list -> t_Completed -> t_Completed =
fun v_chains v_completed ->
(match v_chains with
| [] ->
v_completed
| ((Completed (v_ci, v_cf, v_cc, v_published, v_failure, v_certificates, v_needs)) :: v_tail) ->
(let (Completed (v_interfaces, v_functions, v_constants, v_prior_published, v_previous, v_prior_certificates, v_prior_needs)) = v_completed in
(f_merge_completed (v_tail) ((Completed ((f_publish_interfaces (v_published) (v_interfaces)), (Base.map_union (v_functions) (v_cf)), (Base.map_union (v_constants) (v_cc)), (Base.list_reverse_go (v_published) (v_prior_published)), (f_merge_failure (v_previous) (v_failure)), (Base.list_reverse_go (v_certificates) (v_prior_certificates)), (Base.list_reverse_go (v_needs) (v_prior_needs))))))))
and (* check_scheduler.bend:906 *)
f_check_parallel_chains : (Chains.t_Chain) list -> t_Catalog -> t_Completed -> t_Completed =
fun v_ready v_known v_completed ->
(let (Completed (v_interfaces, v_functions, v_constants, v_published, v_failure, v_certificates, v_needs)) = v_completed in
(let v_outcomes = (B.f_execute (f_run_chain) ((f_chain_batch (v_ready) (v_known))) ((ChainContext (v_known, v_interfaces, v_failure)))) in
(f_merge_completed (v_outcomes) (v_completed))))
and (* check_scheduler.bend:911 *)
f_singleton_jobs : (Chains.t_Chain) list -> ((t_Scheduled) list) option =
fun v_chains ->
(match v_chains with
| [] ->
(Some ([]))
| ((Chains.Chain (v_head, v_level, ((Chains.Job (v_position, v_job)) :: []))) :: v_tail) ->
(match (f_singleton_jobs (v_tail)) with
| None -> None
| Some v_rest ->
(Some (((Scheduled (v_position, v_level, v_job)) :: v_rest))))
| _ ->
None)
and (* check_scheduler.bend:922 *)
f_check_chain_frontier_planned : (Chains.t_Chain) list -> t_Catalog -> t_Completed -> ((t_Scheduled) list) option -> t_Completed =
fun v_ready v_known v_completed v_singletons ->
(match (v_ready, v_singletons) with
| (((Chains.Chain (v_position, v_level, v_jobs)) :: []), _) ->
(f_check_chain (v_jobs) (v_known) (v_completed) ((f_chain_allowed (v_jobs) (v_completed))))
| (_, (Some (v_scheduled))) ->
(f_check_frontier (v_scheduled) (v_known) (v_completed))
| (_, None) ->
(f_check_parallel_chains (v_ready) (v_known) (v_completed)))
and (* check_scheduler.bend:931 *)
f_check_chain_frontier : (Chains.t_Chain) list -> t_Catalog -> t_Completed -> t_Completed =
fun v_ready v_known v_completed ->
(f_check_chain_frontier_planned (v_ready) (v_known) (v_completed) ((f_singleton_jobs (v_ready))))
and (* check_scheduler.bend:934 *)
f_check_chain_frontiers : int -> Chains.t_Frontier -> t_Catalog -> t_Completed -> (M.t_Diagnostic, t_Completed) Base.result_ =
fun v_fuel v_frontier v_known v_completed ->
(match (v_fuel, v_frontier) with
| (_, (Chains.Frontier ([], []))) ->
(Done (v_completed))
| (0, _) ->
(Fail ((M.Diagnostic (s_0, s_4, s_6))))
| (__nat_47, (Chains.Frontier (v_ready, v_pending))) when __nat_47 >= 1 ->
(let v_rest = (__nat_47 - 1) in
(f_check_chain_frontiers (v_rest) ((Chains.f_next_frontier (v_pending))) (v_known) ((f_check_chain_frontier (v_ready) (v_known) (v_completed))))))
and (* check_scheduler.bend:943 *)
f_has_dependencies : (G.t_Job) list -> bool =
fun v_jobs ->
(match v_jobs with
| [] ->
false
| ((G.Job (v_members, [], v_types)) :: v_tail) ->
(f_has_dependencies (v_tail))
| (v_head :: v_tail) ->
true)
and (* check_scheduler.bend:952 *)
f_mono_singletons : (G.t_Job) list -> int -> int =
fun v_jobs v_count ->
(match v_jobs with
| [] ->
v_count
| ((G.Job (v_members, v_dependencies, v_types)) :: v_tail) ->
(match v_members with
| (v_name :: []) ->
(f_mono_singletons (v_tail) ((Base.bool_pick ((Base.string_starts_with (v_name) (s_2))) ((Base.nat_add 1 v_count)) (v_count))))
| _ ->
(f_mono_singletons (v_tail) (v_count))))
and (* check_scheduler.bend:963 *)
f_weighted_regions : (Regions.t_Region) list -> t_Catalog -> ((Regions.t_Region) B.t_Weighted) list =
fun v_regions v_known ->
(match v_regions with
| [] ->
[]
| (v_region :: v_tail) ->
(let (Regions.Region (v_chains)) = v_region in
(let v_cost = (B.f_total_cost ((f_weighted_chains (v_chains) (v_known))) (0)) in
((B.Weighted (v_region, v_cost)) :: (f_weighted_regions (v_tail) (v_known))))))
and (* check_scheduler.bend:972 *)
f_region_batch : (Regions.t_Region) list -> t_Catalog -> (Regions.t_Region) B.t_Batch =
fun v_regions v_known ->
(B.f_plan ((f_weighted_regions (v_regions) (v_known))) ((f_inference_grain ())))
and (* check_scheduler.bend:975 *)
f_run_region : Regions.t_Region -> t_ChainContext -> (M.t_Diagnostic, t_Completed) Base.result_ =
fun v_region v_context ->
(let (Regions.Region (v_chains)) = v_region in
(let (ChainContext (v_known, v_interfaces, v_failure)) = v_context in
(let v_initial = (Completed (v_interfaces, (Base.map_new ()), (Base.map_new ()), [], v_failure, [], [])) in
(f_check_chain_frontiers ((Base.list_length (v_chains))) ((Chains.f_next_frontier (v_chains))) (v_known) (v_initial)))))
and (* check_scheduler.bend:981 *)
f_merge_regions : ((M.t_Diagnostic, t_Completed) Base.result_) list -> t_Completed -> (M.t_Diagnostic, t_Completed) Base.result_ =
fun v_outcomes v_completed ->
(match v_outcomes with
| [] ->
(Done (v_completed))
| ((Fail (v_diagnostic)) :: v_tail) ->
(Fail (v_diagnostic))
| ((Done (v_region)) :: v_tail) ->
(f_merge_regions (v_tail) ((f_merge_completed ([v_region]) (v_completed)))))
and (* check_scheduler.bend:990 *)
f_check_regions : (Regions.t_Region) list -> t_Catalog -> t_Completed -> (M.t_Diagnostic, t_Completed) Base.result_ =
fun v_regions v_known v_completed ->
(match v_regions with
| ((Regions.Region (v_chains)) :: []) ->
(f_check_chain_frontiers ((Base.list_length (v_chains))) ((Chains.f_next_frontier (v_chains))) (v_known) (v_completed))
| _ ->
(let (Completed (v_interfaces, v_functions, v_constants, v_published, v_failure, v_certificates, v_needs)) = v_completed in
(let v_outcomes = (B.f_execute (f_run_region) ((f_region_batch (v_regions) (v_known))) ((ChainContext (v_known, v_interfaces, v_failure)))) in
(f_merge_regions (v_outcomes) (v_completed)))))
and (* check_scheduler.bend:999 *)
f_check_dependent_jobs : bool -> (G.t_Job) list -> t_Catalog -> t_Completed -> (M.t_Diagnostic, t_Completed) Base.result_ =
fun v_flat v_jobs v_known v_completed ->
(match v_flat with
| true ->
(match (f_schedule (v_jobs)) with
| Fail __error -> Fail __error
| Done v_scheduled ->
(f_check_frontiers ((Base.list_length (v_jobs))) ((f_next_frontier (v_scheduled))) (v_known) (v_completed)))
| false ->
(match (Chains.f_plan (v_jobs)) with
| Fail __error -> Fail __error
| Done v_chains ->
(match (Regions.f_rooted_plan (v_chains)) with
| Fail __error -> Fail __error
| Done v_rooted ->
(f_check_regions ((Regions.f_branches (v_rooted))) (v_known) ((f_check_chain_frontier ((Regions.f_prefix (v_rooted))) (v_known) (v_completed)))))))
and (* check_scheduler.bend:1011 *)
f_check_jobs : (G.t_Job) list -> t_Catalog -> t_Completed -> bool -> (M.t_Diagnostic, t_Completed) Base.result_ =
fun v_jobs v_known v_completed v_dependent ->
(match v_dependent with
| false ->
(match (f_schedule (v_jobs)) with
| Fail __error -> Fail __error
| Done v_scheduled ->
(f_check_frontiers ((Base.list_length (v_jobs))) ((f_next_frontier (v_scheduled))) (v_known) (v_completed)))
| true ->
(f_check_dependent_jobs ((Base.nat_is_le (8) ((f_mono_singletons (v_jobs) (0))))) (v_jobs) (v_known) (v_completed)))
and (* check_scheduler.bend:1023 *)
f_check_module_core : M.t_Module -> (Core.t_Certificate) list -> (M.t_Diagnostic, M.t_CheckedModule) Base.result_ =
fun v_module v_certificates ->
(match (G.f_plan (v_module)) with
| Fail __error -> Fail __error
| Done v_jobs ->
(match (f_check_jobs (v_jobs) ((f_with_core ((f_catalog (v_module))) (v_module) (v_certificates))) ((f_empty_completed ())) ((f_has_dependencies (v_jobs)))) with
| Fail __error -> Fail __error
| Done v_completed ->
(f_assembled (v_module) (v_completed))))
and (* check_scheduler.bend:1041 *)
f_initial_checked : t_Initial -> M.t_CheckedModule =
fun v_initial ->
(let (Initial (v_checked, v_certificates, v_needs)) = v_initial in
v_checked)
and (* check_scheduler.bend:1045 *)
f_initial_certificates : t_Initial -> (Core.t_Certificate) list =
fun v_initial ->
(let (Initial (v_checked, v_certificates, v_needs)) = v_initial in
v_certificates)
and (* check_scheduler.bend:1049 *)
f_retained_members : (Base.text) list -> M.t_Module -> (G.t_Interface) list -> ((Core.t_Certificate) list) Base.map -> bool =
fun v_members v_module v_imports v_available ->
(match v_members with
| [] ->
false
| (v_name :: v_tail) ->
(Base.maybe_is_some ((Core.f_available_candidates ((Index.f_find (v_available) (v_name))) (v_module) (v_imports)))))
and (* check_scheduler.bend:1056 *)
f_retained_certificate : Core.t_Certificate -> ((Core.t_Certificate) list) Base.map -> bool =
fun v_certificate v_available ->
(let (Core.Certificate (v_module, v_checked, v_imports)) = v_certificate in
(f_retained_members ((Core.f_names (v_module))) (v_module) (v_imports) (v_available)))
and (* check_scheduler.bend:1060 *)
f_retained_count : (Core.t_Certificate) list -> ((Core.t_Certificate) list) Base.map -> int -> int =
fun v_certificates v_available v_count ->
(match v_certificates with
| [] ->
v_count
| (v_certificate :: v_tail) ->
(f_retained_count (v_tail) (v_available) ((Base.nat_add (v_count) ((Base.bool_pick ((f_retained_certificate (v_certificate) (v_available))) (1) (0)))))))
and (* check_scheduler.bend:1070 *)
f_audit_counts : bool -> M.t_Module -> (Core.t_Certificate) list -> (Core.t_Certificate) list -> t_AuditCounts =
fun v_audit v_module v_issued v_supplied ->
(match v_audit with
| false ->
(AuditCounts (0, 0))
| true ->
(let v_retained = (f_retained_count (v_issued) ((Core.f_index_for (v_module) (v_supplied))) (0)) in
(AuditCounts ((Base.nat_sub ((Base.list_length (v_issued))) (v_retained)), v_retained))))
and (* check_scheduler.bend:1078 *)
f_assembled_attempt : (M.t_Diagnostic, M.t_CheckedModule) Base.result_ -> (Core.t_Certificate) list -> (G.t_GroupNeeds) list -> t_AuditCounts -> t_InitialAttempt =
fun v_result v_issued v_needs v_counts ->
(match (v_result, v_counts) with
| ((Done (v_checked)), (AuditCounts (v_inferred, v_retained))) ->
(CheckedInitial ((Initial (v_checked, v_issued, (Base.list_reverse (v_needs)))), v_inferred, v_retained))
| ((Fail (v_diagnostic)), (AuditCounts (v_inferred, v_retained))) ->
(FailedInitial (v_diagnostic, v_issued, v_inferred, v_retained)))
and (* check_scheduler.bend:1085 *)
f_initial_attempt : M.t_Module -> t_Completed -> (Core.t_Certificate) list -> bool -> t_InitialAttempt =
fun v_module v_completed v_supplied v_audit ->
(let (Completed (v_interfaces, v_functions, v_constants, v_published, v_failure, v_certificates, v_needs)) = v_completed in
(let v_issued = (Base.list_reverse (v_certificates)) in
(f_assembled_attempt ((f_assembled (v_module) (v_completed))) (v_issued) (v_needs) ((f_audit_counts (v_audit) (v_module) (v_issued) (v_supplied))))))
and (* check_scheduler.bend:1090 *)
f_failed_attempt : M.t_Diagnostic -> t_InitialAttempt =
fun v_diagnostic ->
(FailedInitial (v_diagnostic, [], 0, 0))
and (* check_scheduler.bend:1093 *)
f_checked_attempt : (M.t_Diagnostic, t_Completed) Base.result_ -> M.t_Module -> (Core.t_Certificate) list -> bool -> t_InitialAttempt =
fun v_result v_module v_certificates v_audit ->
(match v_result with
| (Fail (v_diagnostic)) ->
(f_failed_attempt (v_diagnostic))
| (Done (v_completed)) ->
(f_initial_attempt (v_module) (v_completed) (v_certificates) (v_audit)))
and (* check_scheduler.bend:1100 *)
f_planned_attempt : (M.t_Diagnostic, (G.t_Job) list) Base.result_ -> M.t_Module -> (Core.t_Certificate) list -> bool -> t_InitialAttempt =
fun v_result v_module v_certificates v_audit ->
(match v_result with
| (Fail (v_diagnostic)) ->
(f_failed_attempt (v_diagnostic))
| (Done (v_jobs)) ->
(f_checked_attempt ((f_check_jobs (v_jobs) ((f_with_evidence ((f_with_core ((f_catalog (v_module))) (v_module) (v_certificates))))) ((f_empty_completed ())) ((f_has_dependencies (v_jobs))))) (v_module) (v_certificates) (v_audit)))
and (* check_scheduler.bend:1107 *)
f_planned_reusing : (M.t_Diagnostic, (G.t_Job) list) Base.result_ -> M.t_Module -> (Core.t_Certificate) list -> ((ResolvingCore.t_Witness) list) Base.map -> t_InitialAttempt =
fun v_result v_module v_certificates v_witnesses ->
(match v_result with
| (Fail (v_diagnostic)) ->
(f_failed_attempt (v_diagnostic))
| (Done (v_jobs)) ->
(let v_known = (f_with_resolving ((f_with_evidence ((f_with_core ((f_catalog (v_module))) (v_module) (v_certificates))))) (v_witnesses)) in
(f_checked_attempt ((f_check_jobs (v_jobs) (v_known) ((f_empty_completed ())) ((f_has_dependencies (v_jobs))))) (v_module) (v_certificates) (false))))
and (* check_scheduler.bend:1118 *)
f_check_module_resolving_reusing : M.t_Module -> (Core.t_Certificate) list -> t_Initial -> t_InitialAttempt =
fun v_module v_certificates v_previous ->
(let (Initial (v_checked, v_prior_certificates, v_needs)) = v_previous in
(let v_witnesses = (ResolvingCore.f_index (v_prior_certificates) (v_needs) ((Base.map_new ()))) in
(f_planned_reusing ((G.f_plan (v_module))) (v_module) ((Core.f_ready_certificates (v_certificates))) (v_witnesses))))
and (* check_scheduler.bend:1123 *)
f_check_module_resolving_attempt : M.t_Module -> (Core.t_Certificate) list -> t_InitialAttempt =
fun v_module v_certificates ->
(f_planned_attempt ((G.f_plan (v_module))) (v_module) (v_certificates) (false))
and (* check_scheduler.bend:1128 *)
f_check_module_resolving_probe : M.t_Module -> (Core.t_Certificate) list -> t_InitialAttempt =
fun v_module v_certificates ->
(f_planned_attempt ((G.f_plan (v_module))) (v_module) (v_certificates) (true))
and (* check_scheduler.bend:1131 *)
f_attempt_result : t_InitialAttempt -> (M.t_Diagnostic, t_Initial) Base.result_ =
fun v_attempt ->
(match v_attempt with
| (CheckedInitial (v_initial, v_inferred, v_retained)) ->
(Done (v_initial))
| (FailedInitial (v_diagnostic, v_certificates, v_inferred, v_retained)) ->
(Fail (v_diagnostic)))
and (* check_scheduler.bend:1141 *)
f_check_module_resolving : M.t_Module -> (Core.t_Certificate) list -> (M.t_Diagnostic, t_Initial) Base.result_ =
fun v_module v_certificates ->
(f_attempt_result ((f_check_module_resolving_attempt (v_module) (v_certificates))))
and (* check_scheduler.bend:1144 *)
f_check_module_evidenced : M.t_Module -> (M.t_Diagnostic, t_Initial) Base.result_ =
fun v_module ->
(f_check_module_resolving (v_module) ([]))
and (* check_scheduler.bend:1148 *)
f_check_module : M.t_Module -> (M.t_Diagnostic, M.t_CheckedModule) Base.result_ =
fun v_module ->
(f_check_module_core (v_module) ([]))
