(* Native semantic port of compiler/parallel_infer.bend.

   Source SHA-256: 3d7a7e0f1bc0d0b0b8354566bc976b469b55158cef5f5bce8699fcbf054785c9

   Ownership/type arguments are erased; value types are checked by OCaml.

   No Bend interpreter or generated C/JavaScript is linked. *)

open Base

module M = Ox_model

module I = Ox_infer

module T = Ox_types

module G = Ox_globals

module D = Ox_dependency

module Batch = Ox_inference_batch

module NatIndex = Ox_nat_index

module Bindings = Ox_global_bindings

module C = Ox_constraints

module Uses = Ox_use_plans

type t_Job =
  | Job of G.t_Declaration * (int) list * int * int
and t_Classified =
  | Eligible of G.t_Declaration
  | Ineligible of G.t_Declaration
and t_Run =
  | Run of (G.t_Declaration) list * (t_Classified) list
and t_Context =
  | Context of G.t_Environment * (M.t_Operation) list * (M.t_DataType) list * (Base.text) list * (((Bindings.t_Entry) list) Base.map) option
and t_Outcome =
  | Outcome of t_Job * (M.t_Diagnostic, G.t_Environment) Base.result_
and t_ClosureStep =
  | ClosureStep of (int) list * (int) list
and t_MergeWork =
  | MergeVisit of ((M.t_Ty) T.t_Version) list * ((M.t_EffectRow) T.t_Version) list * (int) list
  | MergeChoose of (M.t_Ty) T.t_Version * ((M.t_Ty) T.t_Version) list * (M.t_EffectRow) T.t_Version * ((M.t_EffectRow) T.t_Version) list * (int) list * bool
and t_ConflictWork =
  | Gather of (t_Outcome) list * (int) list * (int) list
  | Check of (t_Outcome) list * (int) list * T.t_Substitutions * int * (int) list * (int) list * bool
and t_Work =
  | Evaluate of (t_Classified) list * G.t_Environment
  | Execute of t_Run * G.t_Environment

let s_0 = Base.text_of_utf8 "internal_error"

let s_1 = Base.text_of_utf8 "bound imported quantifier"

let s_2 = Base.text_of_utf8 "parallel"

let s_3 = Base.text_of_utf8 "indexed version merge limit"

let s_4 = Base.text_of_utf8 "read closure limit"

let s_5 = Base.text_of_utf8 "inference traversal limit"

let rec (* parallel_infer.bend:31 *)
f_declaration_body : G.t_Declaration -> M.t_Expr =
fun v_declaration ->
(match v_declaration with
| (G.FunctionDeclaration ((M.Function (v_name, v_exported, v_parameter, v_p, v_r, v_body)))) ->
v_body
| (G.ConstantDeclaration ((M.Constant (v_name, v_exported, v_annotation, v_value)))) ->
v_value)
and (* parallel_infer.bend:38 *)
f_any_pending : (Base.text) list -> Base.set -> bool =
fun v_references v_pending ->
(match v_references with
| [] ->
false
| (v_name :: v_tail) ->
(Base.bool_or ((D.f_member (v_pending) (v_name))) ((f_any_pending (v_tail) (v_pending)))))
and (* parallel_infer.bend:45 *)
f_overlap : (int) list -> (int) list -> bool =
fun v_left v_right ->
(match v_left with
| [] ->
false
| (v_head :: v_tail) ->
(Base.bool_or ((T.f_contains (v_right) (v_head))) ((f_overlap (v_tail) (v_right)))))
and (* parallel_infer.bend:52 *)
f_quantified_unbound : (int) list -> T.t_Substitutions -> bool =
fun v_variables v_substitutions ->
(match v_variables with
| [] ->
true
| (v_head :: v_tail) ->
(let v_type_bound = (Base.maybe_is_some ((T.f_value_version (v_substitutions) (v_head) (0)))) in
(let v_row_bound = (Base.maybe_is_some ((T.f_row_version (v_substitutions) (v_head) (0)))) in
(Base.bool_and ((Base.bool_not ((Base.bool_or (v_type_bound) (v_row_bound))))) ((f_quantified_unbound (v_tail) (v_substitutions)))))))
and (* parallel_infer.bend:60 *)
f_binding_free : (I.t_Binding) list -> T.t_Substitutions -> (M.t_Diagnostic, (int) list) Base.result_ =
fun v_bindings v_substitutions ->
(match v_bindings with
| [] ->
(Done ([]))
| ((I.Binding (v_name, v_ty, v_variables, v_predicates)) :: v_tail) ->
(match (Base.bool_pick ((f_quantified_unbound (v_variables) (v_substitutions))) ((Done (()))) ((Fail ((M.Diagnostic (s_0, v_name, s_1)))))) with
| Fail __error -> Fail __error
| Done v_checked ->
(match (T.f_free (v_ty)) with
| Fail __error -> Fail __error
| Done v_raw_type ->
(match (C.f_free_list (v_predicates)) with
| Fail __error -> Fail __error
| Done v_raw_predicates ->
(match (T.f_resolve (v_substitutions) (v_ty)) with
| Fail __error -> Fail __error
| Done v_resolved ->
(match (T.f_free (v_resolved)) with
| Fail __error -> Fail __error
| Done v_refined_type ->
(match (C.f_resolve_list (v_substitutions) (v_predicates)) with
| Fail __error -> Fail __error
| Done v_resolved_predicates ->
(match (C.f_free_list (v_resolved_predicates)) with
| Fail __error -> Fail __error
| Done v_refined_predicates ->
(match (f_binding_free (v_tail) (v_substitutions)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done ((T.f_union ((T.f_union ((T.f_difference ((T.f_union (v_raw_type) (v_raw_predicates))) (v_variables))) ((T.f_difference ((T.f_union (v_refined_type) (v_refined_predicates))) (v_variables))))) (v_rest)))))))))))))
and (* parallel_infer.bend:76 *)
f_substitution_free : T.t_Substitution -> (M.t_Diagnostic, (int) list) Base.result_ =
fun v_one ->
(match v_one with
| (T.Substitution (v_variable, v_replacement)) ->
(T.f_free (v_replacement))
| (T.RowSubstitution (v_variable, v_replacement)) ->
(Done ((T.f_row_free (v_replacement)))))
and (* parallel_infer.bend:83 *)
f_adjacency : (T.t_Substitution) list -> ((int) list) NatIndex.t_Index -> (M.t_Diagnostic, ((int) list) NatIndex.t_Index) Base.result_ =
fun v_history v_graph ->
(match v_history with
| [] ->
(Done (v_graph))
| (v_head :: v_tail) ->
(match v_head with
| (T.Substitution (v_variable, v_replacement)) ->
(match (T.f_free (v_replacement)) with
| Fail __error -> Fail __error
| Done v_added ->
(f_adjacency (v_tail) ((NatIndex.f_set (v_graph) (v_variable) ((T.f_union (v_added) ((NatIndex.f_get (v_graph) (v_variable) ([])))))))))
| (T.RowSubstitution (v_variable, v_replacement)) ->
(f_adjacency (v_tail) ((NatIndex.f_set (v_graph) (v_variable) ((T.f_union ((T.f_row_free (v_replacement))) ((NatIndex.f_get (v_graph) (v_variable) ([]))))))))))
and (* parallel_infer.bend:103 *)
f_merge_loop : int -> t_MergeWork -> (M.t_Diagnostic, (int) list) Base.result_ =
fun v_fuel v_work ->
(match (v_fuel, v_work) with
| (_, (MergeVisit ([], [], v_collected))) ->
(Done (v_collected))
| (0, _) ->
(Fail ((M.Diagnostic (s_0, s_2, s_3))))
| (__nat_1, (MergeVisit (((T.Version (v_position, v_replacement)) :: v_tail), [], v_collected))) when __nat_1 >= 1 ->
(let v_rest = (__nat_1 - 1) in
(match (T.f_free (v_replacement)) with
| Fail __error -> Fail __error
| Done v_added ->
(f_merge_loop (v_rest) ((MergeVisit (v_tail, [], (T.f_union (v_added) (v_collected))))))))
| (__nat_2, (MergeVisit ([], ((T.Version (v_position, v_replacement)) :: v_tail), v_collected))) when __nat_2 >= 1 ->
(let v_rest = (__nat_2 - 1) in
(f_merge_loop (v_rest) ((MergeVisit ([], v_tail, (T.f_union ((T.f_row_free (v_replacement))) (v_collected)))))))
| (__nat_3, (MergeVisit (((T.Version (v_type_position, v_type_replacement)) :: v_type_tail), ((T.Version (v_row_position, v_row_replacement)) :: v_row_tail), v_collected))) when __nat_3 >= 1 ->
(let v_rest = (__nat_3 - 1) in
(f_merge_loop (v_rest) ((MergeChoose ((T.Version (v_type_position, v_type_replacement)), v_type_tail, (T.Version (v_row_position, v_row_replacement)), v_row_tail, v_collected, (Base.nat_is_ge (v_type_position) (v_row_position)))))))
| (__nat_4, (MergeChoose ((T.Version (v_position, v_replacement)), v_type_tail, v_row_head, v_row_tail, v_collected, true))) when __nat_4 >= 1 ->
(let v_rest = (__nat_4 - 1) in
(match (T.f_free (v_replacement)) with
| Fail __error -> Fail __error
| Done v_added ->
(f_merge_loop (v_rest) ((MergeVisit (v_type_tail, (v_row_head :: v_row_tail), (T.f_union (v_added) (v_collected))))))))
| (__nat_5, (MergeChoose (v_type_head, v_type_tail, (T.Version (v_position, v_replacement)), v_row_tail, v_collected, false))) when __nat_5 >= 1 ->
(let v_rest = (__nat_5 - 1) in
(f_merge_loop (v_rest) ((MergeVisit ((v_type_head :: v_type_tail), v_row_tail, (T.f_union ((T.f_row_free (v_replacement))) (v_collected))))))))
and (* parallel_infer.bend:124 *)
f_merge_versions : ((M.t_Ty) T.t_Version) list -> ((M.t_EffectRow) T.t_Version) list -> (int) list -> (M.t_Diagnostic, (int) list) Base.result_ =
fun v_values v_rows v_collected ->
(f_merge_loop ((Base.nat_add 1 (Base.nat_mul (2) ((Base.nat_add ((Base.list_length (v_values))) ((Base.list_length (v_rows)))))))) ((MergeVisit (v_values, v_rows, v_collected))))
and (* parallel_infer.bend:127 *)
f_indexed_neighbors : T.t_Substitutions -> int -> (M.t_Diagnostic, (int) list) Base.result_ =
fun v_substitutions v_variable ->
(let (T.Substitutions (v_history, v_values, v_rows, v_count)) = v_substitutions in
(f_merge_versions ((NatIndex.f_get (v_values) (v_variable) ([]))) ((NatIndex.f_get (v_rows) (v_variable) ([]))) ([])))
and (* parallel_infer.bend:131 *)
f_closure_next : bool -> int -> (int) list -> (int) list -> T.t_Substitutions -> (M.t_Diagnostic, t_ClosureStep) Base.result_ =
fun v_visited v_head v_tail v_seen v_substitutions ->
(match v_visited with
| true ->
(Done ((ClosureStep (v_tail, v_seen))))
| false ->
(match (f_indexed_neighbors (v_substitutions) (v_head)) with
| Fail __error -> Fail __error
| Done v_neighbors ->
(Done ((ClosureStep ((Base.list_append (v_tail) ((T.f_difference (v_neighbors) ((v_head :: v_seen))))), (v_head :: v_seen)))))))
and (* parallel_infer.bend:139 *)
f_read_closure : int -> t_ClosureStep -> T.t_Substitutions -> (M.t_Diagnostic, (int) list) Base.result_ =
fun v_fuel v_work v_substitutions ->
(match (v_fuel, v_work) with
| (_, (ClosureStep ([], v_seen))) ->
(Done (v_seen))
| (0, _) ->
(Fail ((M.Diagnostic (s_0, s_2, s_4))))
| (__nat_6, (ClosureStep ((v_head :: v_tail), v_seen))) when __nat_6 >= 1 ->
(let v_rest = (__nat_6 - 1) in
(match (f_closure_next ((T.f_contains (v_seen) (v_head))) (v_head) (v_tail) (v_seen) (v_substitutions)) with
| Fail __error -> Fail __error
| Done v_next ->
(f_read_closure (v_rest) (v_next) (v_substitutions)))))
and (* parallel_infer.bend:149 *)
f_classified : G.t_Declaration -> Base.set -> (M.t_Diagnostic, D.t_References) Base.result_ -> t_Classified =
fun v_declaration v_pending v_found ->
(match v_found with
| (Fail (v_error)) ->
(Ineligible (v_declaration))
| (Done (v_references)) ->
(Base.bool_pick ((f_any_pending ((D.f_names_of (v_references))) (v_pending))) ((Ineligible (v_declaration))) ((Eligible (v_declaration)))))
and (* parallel_infer.bend:155 *)
f_classify : (G.t_Declaration) list -> Base.set -> (t_Classified) list =
fun v_declarations v_pending ->
(match v_declarations with
| [] ->
[]
| (v_head :: v_tail) ->
((f_classified (v_head) (v_pending) ((D.f_references ((Base.nat_mul (256) (256))) ((D.Expression ((f_declaration_body (v_head)))))))) :: (f_classify (v_tail) (v_pending))))
and (* parallel_infer.bend:161 *)
f_reads_from_references : D.t_References -> Base.text -> G.t_Environment -> (((Bindings.t_Entry) list) Base.map) option -> (M.t_Diagnostic, (int) list) Base.result_ =
fun v_references v_name v_environment v_catalog ->
(let v_substitutions = (I.f_substitutions_of ((G.f_env_state (v_environment)))) in
(match (f_binding_free ((G.f_reference_bindings_prepared (v_catalog) ((G.f_env_bindings (v_environment))) ((v_name :: (D.f_names_of (v_references)))))) (v_substitutions)) with
| Fail __error -> Fail __error
| Done v_free ->
(f_read_closure (1048576) ((ClosureStep (v_free, []))) (v_substitutions))))
and (* parallel_infer.bend:167 *)
f_reads_result : G.t_Declaration -> G.t_Environment -> (((Bindings.t_Entry) list) Base.map) option -> (M.t_Diagnostic, (int) list) Base.result_ =
fun v_declaration v_environment v_catalog ->
(let v_name = (G.f_declaration_name (v_declaration)) in
(let v_body = (f_declaration_body (v_declaration)) in
(match (D.f_references ((Base.nat_mul (256) (256))) ((D.Expression (v_body)))) with
| Fail __error -> Fail __error
| Done v_references ->
(f_reads_from_references (v_references) (v_name) (v_environment) (v_catalog)))))
and (* parallel_infer.bend:174 *)
f_collect : (t_Classified) list -> (G.t_Declaration) list -> t_Run =
fun v_declarations v_reversed ->
(match v_declarations with
| [] ->
(Run ((Base.list_reverse (v_reversed)), []))
| ((Eligible (v_head)) :: v_tail) ->
(f_collect (v_tail) ((v_head :: v_reversed)))
| ((Ineligible (v_head)) :: v_tail) ->
(Run ((Base.list_reverse (v_reversed)), v_declarations)))
and (* parallel_infer.bend:183 *)
f_prepare_jobs : (G.t_Declaration) list -> G.t_Environment -> (((Bindings.t_Entry) list) Base.map) option -> int -> (M.t_Diagnostic, (t_Job) list) Base.result_ =
fun v_declarations v_environment v_catalog v_ordinal ->
(match v_declarations with
| [] ->
(Done ([]))
| (v_head :: v_tail) ->
(match (f_reads_result (v_head) (v_environment) (v_catalog)) with
| Fail __error -> Fail __error
| Done v_reads ->
(match (f_prepare_jobs (v_tail) (v_environment) (v_catalog) ((Base.nat_add 1 v_ordinal))) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done (((Job (v_head, v_reads, (Base.nat_add ((I.f_next_of ((G.f_env_state (v_environment))))) ((Base.nat_mul (v_ordinal) (65536)))), (Base.nat_add ((I.f_next_of ((G.f_env_state (v_environment))))) ((Base.nat_mul ((Base.nat_add 1 v_ordinal)) (65536)))))) :: v_rest))))))
and (* parallel_infer.bend:192 *)
f_type_closed_result : (M.t_Diagnostic, (int) list) Base.result_ -> bool =
fun v_found ->
(match v_found with
| (Done (v_free)) ->
(Base.nat_is_eq ((Base.list_length (v_free))) (0))
| (Fail (v_error)) ->
false)
and (* parallel_infer.bend:197 *)
f_types_closed : (M.t_Ty) list -> bool =
fun v_types ->
(match v_types with
| [] ->
true
| (v_head :: v_tail) ->
(Base.bool_and ((f_type_closed_result ((T.f_free (v_head))))) ((f_types_closed (v_tail)))))
and (* parallel_infer.bend:203 *)
f_operation_closed : M.t_Operation -> bool =
fun v_operation ->
(match v_operation with
| (M.Operation (v_identity, v_parameter, v_result)) ->
(f_types_closed ([v_parameter; v_result]))
| (M.OperationTemplate (v_identity, v_parameters, v_parameter, v_result)) ->
(f_types_closed ([v_parameter; v_result]))
| (M.OperationInstance (v_template, v_arguments)) ->
(f_types_closed (v_arguments)))
and (* parallel_infer.bend:212 *)
f_operations_closed : (M.t_Operation) list -> bool =
fun v_operations ->
(match v_operations with
| [] ->
true
| (v_head :: v_tail) ->
(Base.bool_and ((f_operation_closed (v_head))) ((f_operations_closed (v_tail)))))
and (* parallel_infer.bend:217 *)
f_constructors_closed : (M.t_Constructor) list -> bool =
fun v_constructors ->
(match v_constructors with
| [] ->
true
| ((M.Constructor (v_name, None, v_fields)) :: v_tail) ->
(f_constructors_closed (v_tail))
| ((M.Constructor (v_name, (Some (v_payload)), v_fields)) :: v_tail) ->
(Base.bool_and ((f_type_closed_result ((T.f_free (v_payload))))) ((f_constructors_closed (v_tail)))))
and (* parallel_infer.bend:224 *)
f_data_types_closed : (M.t_DataType) list -> bool =
fun v_types ->
(match v_types with
| [] ->
true
| ((M.DataType (v_identity, v_parameters, v_constructors)) :: v_tail) ->
(Base.bool_and ((f_constructors_closed (v_constructors))) ((f_data_types_closed (v_tail)))))
and (* parallel_infer.bend:230 *)
f_run_job : t_Job -> t_Context -> t_Outcome =
fun v_job v_context ->
(let (Job (v_declaration, v_reads, v_first, v_limit)) = v_job in
(let (Context (v_environment, v_operations, v_types, v_functions, v_catalog)) = v_context in
(let (G.Environment (v_bindings, v_definitions, v_state)) = v_environment in
(let v_separate = (G.Environment (v_bindings, v_definitions, (I.f_with_next (v_state) (v_first)))) in
(Outcome ((Job (v_declaration, v_reads, v_first, v_limit)), (G.f_infer_declaration_prepared (v_declaration) (v_separate) (v_operations) (v_types) (v_functions) (v_catalog))))))))
and (* parallel_infer.bend:237 *)
f_weighted : (t_Job) list -> ((t_Job) Batch.t_Weighted) list =
fun v_jobs ->
(match v_jobs with
| [] ->
[]
| (v_head :: v_tail) ->
((Batch.Weighted (v_head, 1)) :: (f_weighted (v_tail))))
and (* parallel_infer.bend:242 *)
f_serial : (G.t_Declaration) list -> G.t_Environment -> (M.t_Operation) list -> (M.t_DataType) list -> (Base.text) list -> (((Bindings.t_Entry) list) Base.map) option -> (M.t_Diagnostic, G.t_Environment) Base.result_ =
fun v_declarations v_environment v_operations v_types v_functions v_catalog ->
(match v_declarations with
| [] ->
(Done (v_environment))
| (v_declaration :: v_tail) ->
(match (G.f_infer_declaration_prepared (v_declaration) (v_environment) (v_operations) (v_types) (v_functions) (v_catalog)) with
| Fail __error -> Fail __error
| Done v_next ->
(f_serial (v_tail) (v_next) (v_operations) (v_types) (v_functions) (v_catalog))))
and (* parallel_infer.bend:250 *)
f_delta : (T.t_Substitution) list -> int -> (T.t_Substitution) list =
fun v_history v_count ->
(match (v_history, v_count) with
| (_, 0) ->
[]
| ((v_head :: v_tail), __nat_7) when __nat_7 >= 1 ->
(let v_rest = (__nat_7 - 1) in
(v_head :: (f_delta (v_tail) (v_rest))))
| (_, _) ->
[])
and (* parallel_infer.bend:256 *)
f_written_ids : (T.t_Substitution) list -> (int) list =
fun v_changes ->
(match v_changes with
| [] ->
[]
| ((T.Substitution (v_variable, v_replacement)) :: v_tail) ->
(v_variable :: (f_written_ids (v_tail)))
| ((T.RowSubstitution (v_variable, v_replacement)) :: v_tail) ->
(v_variable :: (f_written_ids (v_tail))))
and (* parallel_infer.bend:264 *)
f_compatible : (int) list -> (int) list -> (int) list -> (int) list -> bool =
fun v_reads v_writes v_seen_reads v_seen_writes ->
(Base.bool_not ((Base.bool_or ((f_overlap (v_writes) (v_seen_reads))) ((Base.bool_or ((f_overlap (v_reads) (v_seen_writes))) ((f_overlap (v_writes) (v_seen_writes))))))))
and (* parallel_infer.bend:271 *)
f_conflict_loop : int -> t_ConflictWork -> int -> bool =
fun v_fuel v_work v_base_count ->
(match (v_fuel, v_work) with
| (_, (Gather ([], v_seen_reads, v_seen_writes))) ->
true
| (0, _) ->
false
| (__nat_8, (Gather (((Outcome (v_job, (Fail (v_error)))) :: v_tail), v_seen_reads, v_seen_writes))) when __nat_8 >= 1 ->
(let v_rest = (__nat_8 - 1) in
false)
| (__nat_9, (Gather (((Outcome ((Job (v_declaration, v_reads, v_first, v_limit)), (Done ((G.Environment (v_bindings, v_definitions, v_state)))))) :: v_tail), v_seen_reads, v_seen_writes))) when __nat_9 >= 1 ->
(let v_rest = (__nat_9 - 1) in
(let v_subs = (I.f_substitutions_of (v_state)) in
(let v_count = (T.f_substitution_count (v_subs)) in
(f_conflict_loop (v_rest) ((Check (v_tail, v_reads, v_subs, v_count, v_seen_reads, v_seen_writes, (Base.nat_is_ge (v_count) (v_base_count))))) (v_base_count)))))
| (__nat_10, (Check (v_outcomes, v_reads, v_substitutions, v_count, v_seen_reads, v_seen_writes, false))) when __nat_10 >= 1 ->
(let v_rest = (__nat_10 - 1) in
false)
| (__nat_11, (Check (v_outcomes, v_reads, v_substitutions, v_count, v_seen_reads, v_seen_writes, true))) when __nat_11 >= 1 ->
(let v_rest = (__nat_11 - 1) in
(let v_writes = (f_written_ids ((f_delta ((T.f_substitution_history (v_substitutions))) ((Base.nat_sub (v_count) (v_base_count)))))) in
(Base.bool_and ((f_compatible (v_reads) (v_writes) (v_seen_reads) (v_seen_writes))) ((f_conflict_loop (v_rest) ((Gather (v_outcomes, (T.f_union (v_reads) (v_seen_reads)), (T.f_union (v_writes) (v_seen_writes))))) (v_base_count)))))))
and (* parallel_infer.bend:285 *)
f_conflicts_absent : (t_Outcome) list -> int -> bool =
fun v_outcomes v_base_count ->
(f_conflict_loop ((Base.nat_add 1 (Base.nat_mul (2) ((Base.list_length (v_outcomes)))))) ((Gather (v_outcomes, [], []))) (v_base_count))
and (* parallel_infer.bend:288 *)
f_ids_safe : (int) list -> (int) list -> int -> int -> int -> bool =
fun v_ids v_reads v_snapshot v_first v_next ->
(match v_ids with
| [] ->
true
| (v_id :: v_tail) ->
(let v_allowed = (Base.bool_pick ((Base.nat_is_lt (v_id) (v_snapshot))) ((T.f_contains (v_reads) (v_id))) ((Base.bool_and ((Base.nat_is_ge (v_id) (v_first))) ((Base.nat_is_lt (v_id) (v_next)))))) in
(Base.bool_and (v_allowed) ((f_ids_safe (v_tail) (v_reads) (v_snapshot) (v_first) (v_next))))))
and (* parallel_infer.bend:295 *)
f_types_free : (M.t_Ty) list -> (M.t_Diagnostic, (int) list) Base.result_ =
fun v_types ->
(match v_types with
| [] ->
(Done ([]))
| (v_head :: v_tail) ->
(match (T.f_free (v_head)) with
| Fail __error -> Fail __error
| Done v_a ->
(match (f_types_free (v_tail)) with
| Fail __error -> Fail __error
| Done v_b ->
(Done ((T.f_union (v_a) (v_b)))))))
and (* parallel_infer.bend:304 *)
f_invocation_free : (M.t_EffectRow) option -> (int) list =
fun v_invocation ->
(match v_invocation with
| None ->
[]
| (Some (v_row)) ->
(T.f_row_free (v_row)))
and (* parallel_infer.bend:311 *)
f_rename_invocation : (M.t_EffectRow) option -> (int) NatIndex.t_Index -> (M.t_EffectRow) option =
fun v_invocation v_mapping ->
(match v_invocation with
| None ->
None
| (Some (v_row)) ->
(Some ((T.f_rename_row (v_row) (v_mapping)))))
and (* parallel_infer.bend:318 *)
f_coverage_free : I.t_Coverage -> (M.t_Diagnostic, (int) list) Base.result_ =
fun v_coverage ->
(match v_coverage with
| (I.QualifiedBoundary (v_offset, v_declared, v_subject)) ->
(C.f_free_list (v_declared))
| (I.QualifiedNeed (v_site, v_predicate, v_subject)) ->
(C.f_free (v_predicate))
| (I.OperationNeed (v_identity, v_template, v_arguments, v_function_type, v_subject)) ->
(match (f_types_free (v_arguments)) with
| Fail __error -> Fail __error
| Done v_a ->
(match (T.f_free (v_function_type)) with
| Fail __error -> Fail __error
| Done v_b ->
(Done ((T.f_union (v_a) (v_b))))))
| (I.AssociatedNeed (v_identity, v_dispatch, v_member, v_templates, v_left, v_right, v_result, v_invocation, v_ambient, v_subject)) ->
(match (f_types_free ([v_left; v_right; v_result])) with
| Fail __error -> Fail __error
| Done v_free ->
(Done ((T.f_union (v_free) ((T.f_union ((f_invocation_free (v_invocation))) ((T.f_row_free (v_ambient)))))))))
| (I.ValuePatternType (v_inferred_type, v_subject)) ->
(T.f_free (v_inferred_type))
| (I.Coverage (v_inferred_types, v_patterns, v_subject)) ->
(f_types_free (v_inferred_types))
| (I.LetGeneralized (v_witness)) ->
(T.f_free (v_witness)))
and (* parallel_infer.bend:340 *)
f_coverages_free : (I.t_Coverage) list -> (M.t_Diagnostic, (int) list) Base.result_ =
fun v_coverages ->
(match v_coverages with
| [] ->
(Done ([]))
| (v_head :: v_tail) ->
(match (f_coverage_free (v_head)) with
| Fail __error -> Fail __error
| Done v_a ->
(match (f_coverages_free (v_tail)) with
| Fail __error -> Fail __error
| Done v_b ->
(Done ((T.f_union (v_a) (v_b)))))))
and (* parallel_infer.bend:349 *)
f_reflections_free : (I.t_Reflection) list -> (M.t_Diagnostic, (int) list) Base.result_ =
fun v_reflections ->
(match v_reflections with
| [] ->
(Done ([]))
| ((I.Reflection (v_callee, v_subject, v_ty, v_predicates)) :: v_tail) ->
(match (T.f_free (v_ty)) with
| Fail __error -> Fail __error
| Done v_own_type ->
(match (C.f_free_list (v_predicates)) with
| Fail __error -> Fail __error
| Done v_own_predicates ->
(match (f_reflections_free (v_tail)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done ((T.f_union (v_own_type) ((T.f_union (v_own_predicates) (v_rest))))))))))
and (* parallel_infer.bend:360 *)
f_definition_free : I.t_Definition -> (M.t_Diagnostic, (int) list) Base.result_ =
fun v_definition ->
(let (I.Definition (v_name, (I.Inference (v_ty, v_coverage, v_exits, v_reflections, v_predicates, v_uses)))) = v_definition in
(match (T.f_free (v_ty)) with
| Fail __error -> Fail __error
| Done v_a ->
(match (f_coverages_free (v_coverage)) with
| Fail __error -> Fail __error
| Done v_b ->
(match (C.f_free_list (v_predicates)) with
| Fail __error -> Fail __error
| Done v_c ->
(match (Uses.f_free (v_uses)) with
| Fail __error -> Fail __error
| Done v_d ->
(match (f_reflections_free (v_reflections)) with
| Fail __error -> Fail __error
| Done v_e ->
(Done ((T.f_union (v_a) ((T.f_union (v_b) ((T.f_union (v_c) ((T.f_union (v_d) (v_e))))))))))))))))
and (* parallel_infer.bend:370 *)
f_mapping : int -> int -> int -> (int) NatIndex.t_Index -> (int) NatIndex.t_Index =
fun v_count v_first v_target v_result ->
(match v_count with
| 0 ->
v_result
| __nat_12 when __nat_12 >= 1 ->
(let v_rest = (__nat_12 - 1) in
(f_mapping (v_rest) ((Base.nat_add 1 v_first)) ((Base.nat_add 1 v_target)) ((NatIndex.f_set (v_result) (v_first) (v_target))))))
and (* parallel_infer.bend:375 *)
f_rename_types : (M.t_Ty) list -> (int) NatIndex.t_Index -> (M.t_Diagnostic, (M.t_Ty) list) Base.result_ =
fun v_types v_mapping ->
(match v_types with
| [] ->
(Done ([]))
| (v_head :: v_tail) ->
(match (T.f_rename_type (v_head) (v_mapping)) with
| Fail __error -> Fail __error
| Done v_a ->
(match (f_rename_types (v_tail) (v_mapping)) with
| Fail __error -> Fail __error
| Done v_b ->
(Done ((v_a :: v_b))))))
and (* parallel_infer.bend:384 *)
f_rename_coverage : I.t_Coverage -> (int) NatIndex.t_Index -> (M.t_Diagnostic, I.t_Coverage) Base.result_ =
fun v_coverage v_mapping ->
(match v_coverage with
| (I.QualifiedBoundary (v_offset, v_declared, v_subject)) ->
(match (C.f_rename_list (v_mapping) (v_declared)) with
| Fail __error -> Fail __error
| Done v_needs ->
(Done ((I.QualifiedBoundary (v_offset, v_needs, v_subject)))))
| (I.QualifiedNeed (v_site, v_predicate, v_subject)) ->
(match (C.f_rename (v_mapping) (v_predicate)) with
| Fail __error -> Fail __error
| Done v_next ->
(Done ((I.QualifiedNeed (v_site, v_next, v_subject)))))
| (I.OperationNeed (v_identity, v_template, v_arguments, v_function_type, v_subject)) ->
(match (f_rename_types (v_arguments) (v_mapping)) with
| Fail __error -> Fail __error
| Done v_args ->
(match (T.f_rename_type (v_function_type) (v_mapping)) with
| Fail __error -> Fail __error
| Done v_fn ->
(Done ((I.OperationNeed (v_identity, v_template, v_args, v_fn, v_subject))))))
| (I.AssociatedNeed (v_identity, v_dispatch, v_member, v_templates, v_left, v_right, v_result, v_invocation, v_ambient, v_subject)) ->
(match (T.f_rename_type (v_left) (v_mapping)) with
| Fail __error -> Fail __error
| Done v_a ->
(match (T.f_rename_type (v_right) (v_mapping)) with
| Fail __error -> Fail __error
| Done v_b ->
(match (T.f_rename_type (v_result) (v_mapping)) with
| Fail __error -> Fail __error
| Done v_c ->
(Done ((I.AssociatedNeed (v_identity, v_dispatch, v_member, v_templates, v_a, v_b, v_c, (f_rename_invocation (v_invocation) (v_mapping)), (T.f_rename_row (v_ambient) (v_mapping)), v_subject)))))))
| (I.ValuePatternType (v_inferred_type, v_subject)) ->
(match (T.f_rename_type (v_inferred_type) (v_mapping)) with
| Fail __error -> Fail __error
| Done v_ty ->
(Done ((I.ValuePatternType (v_ty, v_subject)))))
| (I.Coverage (v_inferred_types, v_patterns, v_subject)) ->
(match (f_rename_types (v_inferred_types) (v_mapping)) with
| Fail __error -> Fail __error
| Done v_tys ->
(Done ((I.Coverage (v_tys, v_patterns, v_subject)))))
| (I.LetGeneralized (v_witness)) ->
(match (T.f_rename_type (v_witness) (v_mapping)) with
| Fail __error -> Fail __error
| Done v_ty ->
(Done ((I.LetGeneralized (v_ty))))))
and (* parallel_infer.bend:418 *)
f_rename_coverages : (I.t_Coverage) list -> (int) NatIndex.t_Index -> (M.t_Diagnostic, (I.t_Coverage) list) Base.result_ =
fun v_coverages v_mapping ->
(match v_coverages with
| [] ->
(Done ([]))
| (v_head :: v_tail) ->
(match (f_rename_coverage (v_head) (v_mapping)) with
| Fail __error -> Fail __error
| Done v_a ->
(match (f_rename_coverages (v_tail) (v_mapping)) with
| Fail __error -> Fail __error
| Done v_b ->
(Done ((v_a :: v_b))))))
and (* parallel_infer.bend:427 *)
f_rename_reflections : (I.t_Reflection) list -> (int) NatIndex.t_Index -> (M.t_Diagnostic, (I.t_Reflection) list) Base.result_ =
fun v_reflections v_mapping ->
(match v_reflections with
| [] ->
(Done ([]))
| ((I.Reflection (v_callee, v_subject, v_ty, v_predicates)) :: v_tail) ->
(match (T.f_rename_type (v_ty) (v_mapping)) with
| Fail __error -> Fail __error
| Done v_next_type ->
(match (C.f_rename_list (v_mapping) (v_predicates)) with
| Fail __error -> Fail __error
| Done v_next_predicates ->
(match (f_rename_reflections (v_tail) (v_mapping)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done (((I.Reflection (v_callee, v_subject, v_next_type, v_next_predicates)) :: v_rest)))))))
and (* parallel_infer.bend:438 *)
f_rename_definition : I.t_Definition -> (int) NatIndex.t_Index -> (M.t_Diagnostic, I.t_Definition) Base.result_ =
fun v_definition v_mapping ->
(let (I.Definition (v_name, (I.Inference (v_ty, v_coverage, v_exits, v_reflections, v_predicates, v_uses)))) = v_definition in
(match (T.f_rename_type (v_ty) (v_mapping)) with
| Fail __error -> Fail __error
| Done v_next_ty ->
(match (f_rename_coverages (v_coverage) (v_mapping)) with
| Fail __error -> Fail __error
| Done v_next_coverage ->
(match (C.f_rename_list (v_mapping) (v_predicates)) with
| Fail __error -> Fail __error
| Done v_next_predicates ->
(match (Uses.f_transform_types (v_uses) ((C.Rename (v_mapping, T.FreshVariables)))) with
| Fail __error -> Fail __error
| Done v_next_uses ->
(match (f_rename_reflections (v_reflections) (v_mapping)) with
| Fail __error -> Fail __error
| Done v_next_reflections ->
(Done ((I.Definition (v_name, (I.Inference (v_next_ty, v_next_coverage, v_exits, v_next_reflections, v_next_predicates, v_next_uses))))))))))))
and (* parallel_infer.bend:448 *)
f_rename_substitution : T.t_Substitution -> (int) NatIndex.t_Index -> (M.t_Diagnostic, T.t_Substitution) Base.result_ =
fun v_substitution v_mapping ->
(match v_substitution with
| (T.Substitution (v_variable, v_replacement)) ->
(match (T.f_rename_type (v_replacement) (v_mapping)) with
| Fail __error -> Fail __error
| Done v_ty ->
(Done ((T.Substitution ((NatIndex.f_get (v_mapping) (v_variable) (v_variable)), v_ty)))))
| (T.RowSubstitution (v_variable, v_replacement)) ->
(Done ((T.RowSubstitution ((NatIndex.f_get (v_mapping) (v_variable) (v_variable)), (T.f_rename_row (v_replacement) (v_mapping)))))))
and (* parallel_infer.bend:457 *)
f_replay_delta : (T.t_Substitution) list -> (int) NatIndex.t_Index -> T.t_Substitutions -> (M.t_Diagnostic, T.t_Substitutions) Base.result_ =
fun v_delta v_mapping v_substitutions ->
(match v_delta with
| [] ->
(Done (v_substitutions))
| (v_head :: v_tail) ->
(match (f_rename_substitution (v_head) (v_mapping)) with
| Fail __error -> Fail __error
| Done v_value ->
(f_replay_delta (v_tail) (v_mapping) ((T.f_append_substitution (v_substitutions) (v_value))))))
and (* parallel_infer.bend:465 *)
f_result_option : 'v. (M.t_Diagnostic, 'v) Base.result_ -> ('v) option =
fun v_found ->
(match v_found with
| (Fail (v_error)) ->
None
| (Done (v_value)) ->
(Some (v_value)))
and (* parallel_infer.bend:470 *)
f_valid_unit : bool -> (unit) option =
fun v_valid ->
(match v_valid with
| false ->
None
| true ->
(Some (())))
and (* parallel_infer.bend:475 *)
f_commit_safe : I.t_Definition -> (T.t_Substitution) list -> int -> int -> G.t_Environment -> (G.t_Environment) option =
fun v_definition v_changes v_first v_fresh v_environment ->
(let v_serial_next = (I.f_next_of ((G.f_env_state (v_environment)))) in
(let v_rename = (f_mapping (v_fresh) (v_first) (v_serial_next) ((NatIndex.f_new ()))) in
(match (f_result_option ((f_rename_definition (v_definition) (v_rename)))) with
| None -> None
| Some v_renamed ->
(match (f_result_option ((f_replay_delta ((Base.list_reverse (v_changes))) (v_rename) ((I.f_substitutions_of ((G.f_env_state (v_environment)))))))) with
| None -> None
| Some v_replayed ->
(Some ((G.Environment ((G.f_env_bindings (v_environment)), (v_renamed :: (G.f_env_definitions (v_environment))), (I.State (v_replayed, (Base.nat_add (v_serial_next) (v_fresh)), MTip))))))))))
and (* parallel_infer.bend:483 *)
f_commit_valid : I.t_Definition -> (int) list -> int -> int -> T.t_Substitutions -> int -> int -> int -> G.t_Environment -> bool -> (G.t_Environment) option =
fun v_definition v_reads v_first v_next v_subs v_count v_snapshot v_base_count v_environment v_valid ->
(match v_valid with
| false ->
None
| true ->
(let v_changes = (f_delta ((T.f_substitution_history (v_subs))) ((Base.nat_sub (v_count) (v_base_count)))) in
(let v_fresh = (Base.nat_sub (v_next) (v_first)) in
(match (f_result_option ((T.f_substitutions_free (v_changes)))) with
| None -> None
| Some v_ids ->
(match (f_result_option ((f_definition_free (v_definition)))) with
| None -> None
| Some v_defs ->
(match (f_valid_unit ((Base.bool_and ((f_ids_safe (v_ids) (v_reads) (v_snapshot) (v_first) (v_next))) ((f_ids_safe (v_defs) (v_reads) (v_snapshot) (v_first) (v_next)))))) with
| None -> None
| Some v_checked ->
(f_commit_safe (v_definition) (v_changes) (v_first) (v_fresh) (v_environment))))))))
and (* parallel_infer.bend:495 *)
f_commit_one : t_Outcome -> G.t_Environment -> int -> int -> (G.t_Environment) option =
fun v_outcome v_environment v_snapshot v_base_count ->
(match v_outcome with
| (Outcome (v_job, (Fail (v_error)))) ->
None
| (Outcome (v_job, (Done ((G.Environment (v_bindings, [], v_state)))))) ->
None
| (Outcome ((Job (v_declaration, v_reads, v_first, v_limit)), (Done ((G.Environment (v_bindings, (v_definition :: v_rest), v_state)))))) ->
(let v_next = (I.f_next_of (v_state)) in
(let v_subs = (I.f_substitutions_of (v_state)) in
(let v_count = (T.f_substitution_count (v_subs)) in
(f_commit_valid (v_definition) (v_reads) (v_first) (v_next) (v_subs) (v_count) (v_snapshot) (v_base_count) (v_environment) ((Base.bool_and ((Base.nat_is_ge (v_next) (v_first))) ((Base.bool_and ((Base.nat_is_lt (v_next) (v_limit))) ((Base.nat_is_ge (v_count) (v_base_count))))))))))))
and (* parallel_infer.bend:505 *)
f_commit : (t_Outcome) list -> (G.t_Environment) option -> int -> int -> (G.t_Environment) option =
fun v_outcomes v_pending v_snapshot v_base_count ->
(match (v_outcomes, v_pending) with
| ([], v_result) ->
v_result
| ((v_head :: v_tail), None) ->
None
| ((v_head :: v_tail), (Some (v_environment))) ->
(f_commit (v_tail) ((f_commit_one (v_head) (v_environment) (v_snapshot) (v_base_count))) (v_snapshot) (v_base_count)))
and (* parallel_infer.bend:512 *)
f_windows_fit_length : int -> int -> bool -> bool =
fun v_next v_length v_short ->
(match v_short with
| false ->
false
| true ->
(Base.nat_is_le ((Base.nat_add 1 v_length)) ((Base.nat_div ((Base.nat_sub ((Base.u32_to_nat ((Base.W32 0xffffffff)))) (v_next))) (65536)))))
and (* parallel_infer.bend:517 *)
f_windows_fit : int -> int -> bool -> bool =
fun v_next v_length v_under_limit ->
(match v_under_limit with
| false ->
false
| true ->
(f_windows_fit_length (v_next) (v_length) ((Base.nat_is_le (v_length) (65535)))))
and (* parallel_infer.bend:523 *)
f_serial_or_committed : (G.t_Environment) option -> (G.t_Declaration) list -> G.t_Environment -> (M.t_Operation) list -> (M.t_DataType) list -> (Base.text) list -> (((Bindings.t_Entry) list) Base.map) option -> (M.t_Diagnostic, G.t_Environment) Base.result_ =
fun v_committed v_declarations v_environment v_operations v_types v_functions v_catalog ->
(match v_committed with
| (Some (v_result)) ->
(Done (v_result))
| None ->
(f_serial (v_declarations) (v_environment) (v_operations) (v_types) (v_functions) (v_catalog)))
and (* parallel_infer.bend:528 *)
f_commit_if_compatible_checked : (t_Outcome) list -> G.t_Environment -> int -> int -> bool -> (G.t_Environment) option =
fun v_outcomes v_environment v_snapshot v_base_count v_compatible ->
(match v_compatible with
| false ->
None
| true ->
(f_commit (v_outcomes) ((Some (v_environment))) (v_snapshot) (v_base_count)))
and (* parallel_infer.bend:533 *)
f_commit_if_compatible : (t_Outcome) list -> G.t_Environment -> int -> int -> (G.t_Environment) option =
fun v_outcomes v_environment v_snapshot v_base_count ->
(f_commit_if_compatible_checked (v_outcomes) (v_environment) (v_snapshot) (v_base_count) ((f_conflicts_absent (v_outcomes) (v_base_count))))
and (* parallel_infer.bend:536 *)
f_execute_jobs : (t_Job) list -> (G.t_Declaration) list -> G.t_Environment -> (M.t_Operation) list -> (M.t_DataType) list -> (Base.text) list -> (((Bindings.t_Entry) list) Base.map) option -> (M.t_Diagnostic, G.t_Environment) Base.result_ =
fun v_jobs v_declarations v_environment v_operations v_types v_functions v_catalog ->
(let v_context = (Context (v_environment, v_operations, v_types, v_functions, v_catalog)) in
(let v_outcomes = (Batch.f_execute (f_run_job) ((Batch.f_plan ((f_weighted (v_jobs))) (1))) (v_context)) in
(let v_base_count = (T.f_substitution_count ((I.f_substitutions_of ((G.f_env_state (v_environment)))))) in
(f_serial_or_committed ((f_commit_if_compatible (v_outcomes) (v_environment) ((I.f_next_of ((G.f_env_state (v_environment))))) (v_base_count))) (v_declarations) (v_environment) (v_operations) (v_types) (v_functions) (v_catalog)))))
and (* parallel_infer.bend:542 *)
f_checked_jobs : (M.t_Diagnostic, (t_Job) list) Base.result_ -> (G.t_Declaration) list -> G.t_Environment -> (M.t_Operation) list -> (M.t_DataType) list -> (Base.text) list -> (((Bindings.t_Entry) list) Base.map) option -> (M.t_Diagnostic, G.t_Environment) Base.result_ =
fun v_found v_declarations v_environment v_operations v_types v_functions v_catalog ->
(match v_found with
| (Fail (v_error)) ->
(f_serial (v_declarations) (v_environment) (v_operations) (v_types) (v_functions) (v_catalog))
| (Done (v_jobs)) ->
(f_execute_jobs (v_jobs) (v_declarations) (v_environment) (v_operations) (v_types) (v_functions) (v_catalog)))
and (* parallel_infer.bend:547 *)
f_run_parallel_if : (G.t_Declaration) list -> G.t_Environment -> (M.t_Operation) list -> (M.t_DataType) list -> (Base.text) list -> (((Bindings.t_Entry) list) Base.map) option -> bool -> (M.t_Diagnostic, G.t_Environment) Base.result_ =
fun v_declarations v_environment v_operations v_types v_functions v_catalog v_enabled ->
(match v_enabled with
| false ->
(f_serial (v_declarations) (v_environment) (v_operations) (v_types) (v_functions) (v_catalog))
| true ->
(f_checked_jobs ((f_prepare_jobs (v_declarations) (v_environment) (v_catalog) (0))) (v_declarations) (v_environment) (v_operations) (v_types) (v_functions) (v_catalog)))
and (* parallel_infer.bend:553 *)
f_run_parallel : (G.t_Declaration) list -> G.t_Environment -> (M.t_Operation) list -> (M.t_DataType) list -> (Base.text) list -> (((Bindings.t_Entry) list) Base.map) option -> (M.t_Diagnostic, G.t_Environment) Base.result_ =
fun v_declarations v_environment v_operations v_types v_functions v_catalog ->
(let v_next = (I.f_next_of ((G.f_env_state (v_environment)))) in
(f_run_parallel_if (v_declarations) (v_environment) (v_operations) (v_types) (v_functions) (v_catalog) ((f_windows_fit (v_next) ((Base.list_length (v_declarations))) ((Base.nat_is_lt (v_next) ((Base.u32_to_nat ((Base.W32 0xffffffff))))))))))
and (* parallel_infer.bend:561 *)
f_infer_work : int -> t_Work -> (M.t_Operation) list -> (M.t_DataType) list -> (Base.text) list -> (((Bindings.t_Entry) list) Base.map) option -> (M.t_Diagnostic, G.t_Environment) Base.result_ =
fun v_fuel v_work v_operations v_types v_functions v_catalog ->
(match (v_fuel, v_work) with
| (_, (Evaluate ([], v_environment))) ->
(Done (v_environment))
| (0, _) ->
(Fail ((M.Diagnostic (s_0, s_2, s_5))))
| (__nat_13, (Evaluate (((Ineligible (v_declaration)) :: v_tail), v_environment))) when __nat_13 >= 1 ->
(let v_rest = (__nat_13 - 1) in
(match (G.f_infer_declaration_prepared (v_declaration) (v_environment) (v_operations) (v_types) (v_functions) (v_catalog)) with
| Fail __error -> Fail __error
| Done v_next ->
(f_infer_work (v_rest) ((Evaluate (v_tail, v_next))) (v_operations) (v_types) (v_functions) (v_catalog))))
| (__nat_14, (Evaluate (((Eligible (v_declaration)) :: v_tail), v_environment))) when __nat_14 >= 1 ->
(let v_rest = (__nat_14 - 1) in
(f_infer_work (v_rest) ((Execute ((f_collect (((Eligible (v_declaration)) :: v_tail)) ([])), v_environment))) (v_operations) (v_types) (v_functions) (v_catalog)))
| (__nat_15, (Execute ((Run ([], v_remaining)), v_environment))) when __nat_15 >= 1 ->
(let v_rest = (__nat_15 - 1) in
(f_infer_work (v_rest) ((Evaluate (v_remaining, v_environment))) (v_operations) (v_types) (v_functions) (v_catalog)))
| (__nat_16, (Execute ((Run ([v_declaration], v_remaining)), v_environment))) when __nat_16 >= 1 ->
(let v_rest = (__nat_16 - 1) in
(match (G.f_infer_declaration_prepared (v_declaration) (v_environment) (v_operations) (v_types) (v_functions) (v_catalog)) with
| Fail __error -> Fail __error
| Done v_next ->
(f_infer_work (v_rest) ((Evaluate (v_remaining, v_next))) (v_operations) (v_types) (v_functions) (v_catalog))))
| (__nat_17, (Execute ((Run (v_declarations, v_remaining)), v_environment))) when __nat_17 >= 1 ->
(let v_rest = (__nat_17 - 1) in
(match (f_run_parallel (v_declarations) (v_environment) (v_operations) (v_types) (v_functions) (v_catalog)) with
| Fail __error -> Fail __error
| Done v_next ->
(f_infer_work (v_rest) ((Evaluate (v_remaining, v_next))) (v_operations) (v_types) (v_functions) (v_catalog)))))
and (* parallel_infer.bend:583 *)
f_unique_names : (Base.text) list -> Base.set -> bool =
fun v_names v_seen ->
(match v_names with
| [] ->
true
| (v_name :: v_tail) ->
(Base.bool_and ((Base.bool_not ((D.f_member (v_seen) (v_name))))) ((f_unique_names (v_tail) ((Base.set_add (v_seen) (v_name)))))))
and (* parallel_infer.bend:589 *)
f_ineligible_all : (G.t_Declaration) list -> (t_Classified) list =
fun v_declarations ->
(match v_declarations with
| [] ->
[]
| (v_head :: v_tail) ->
((Ineligible (v_head)) :: (f_ineligible_all (v_tail))))
and (* parallel_infer.bend:594 *)
f_classify_all : (G.t_Declaration) list -> Base.set -> bool -> (t_Classified) list =
fun v_declarations v_pending v_enabled ->
(match v_enabled with
| false ->
(f_ineligible_all (v_declarations))
| true ->
(f_classify (v_declarations) (v_pending)))
and (* parallel_infer.bend:599 *)
f_catalog_closed : (M.t_Operation) list -> (M.t_DataType) list -> bool =
fun v_operations v_types ->
(Base.bool_and ((f_operations_closed (v_operations))) ((f_data_types_closed (v_types))))
and (* parallel_infer.bend:602 *)
f_infer_with_state : I.t_State -> (G.t_Declaration) list -> (Base.text) list -> G.t_Environment -> (M.t_Operation) list -> (M.t_DataType) list -> (Base.text) list -> (((Bindings.t_Entry) list) Base.map) option -> bool -> (M.t_Diagnostic, G.t_Environment) Base.result_ =
fun v_state v_declarations v_all_pending_names v_environment v_operations v_types v_functions v_catalog v_enabled ->
(match v_state with
| (I.State (v_substitutions, v_next, MTip)) ->
(f_infer_work ((Base.nat_add 1 (Base.nat_mul (2) ((Base.list_length (v_declarations)))))) ((Evaluate ((f_classify_all (v_declarations) ((G.f_reference_set (v_all_pending_names) ((Base.set_new ())))) (v_enabled)), v_environment))) (v_operations) (v_types) (v_functions) (v_catalog))
| _ ->
(f_infer_work ((Base.nat_add 1 (Base.nat_mul (2) ((Base.list_length (v_declarations)))))) ((Evaluate ((f_ineligible_all (v_declarations)), v_environment))) (v_operations) (v_types) (v_functions) (v_catalog)))
and (* parallel_infer.bend:611 *)
f_infer_segment_prechecked : (G.t_Declaration) list -> (Base.text) list -> G.t_Environment -> (M.t_Operation) list -> (M.t_DataType) list -> (Base.text) list -> (((Bindings.t_Entry) list) Base.map) option -> bool -> (M.t_Diagnostic, G.t_Environment) Base.result_ =
fun v_declarations v_all_pending_names v_environment v_operations v_types v_functions v_catalog v_catalog_is_closed ->
(match v_declarations with
| [] ->
(Done (v_environment))
| [v_declaration] ->
(G.f_infer_declaration_prepared (v_declaration) (v_environment) (v_operations) (v_types) (v_functions) (v_catalog))
| (v_a :: (v_b :: v_rest)) ->
(f_infer_with_state ((G.f_env_state (v_environment))) ((v_a :: (v_b :: v_rest))) (v_all_pending_names) (v_environment) (v_operations) (v_types) (v_functions) (v_catalog) (v_catalog_is_closed)))
and (* parallel_infer.bend:618 *)
f_infer_segment : (G.t_Declaration) list -> (Base.text) list -> G.t_Environment -> (M.t_Operation) list -> (M.t_DataType) list -> (Base.text) list -> (((Bindings.t_Entry) list) Base.map) option -> (M.t_Diagnostic, G.t_Environment) Base.result_ =
fun v_declarations v_all_pending_names v_environment v_operations v_types v_functions v_catalog ->
(match v_declarations with
| [] ->
(Done (v_environment))
| [v_declaration] ->
(G.f_infer_declaration_prepared (v_declaration) (v_environment) (v_operations) (v_types) (v_functions) (v_catalog))
| (v_a :: (v_b :: v_rest)) ->
(f_infer_with_state ((G.f_env_state (v_environment))) ((v_a :: (v_b :: v_rest))) (v_all_pending_names) (v_environment) (v_operations) (v_types) (v_functions) (v_catalog) ((Base.bool_and ((f_unique_names (v_all_pending_names) ((Base.set_new ())))) ((f_catalog_closed (v_operations) (v_types)))))))
and (* parallel_infer.bend:625 *)
f_infer_component_unique : (G.t_Declaration) list -> (Base.text) list -> G.t_Environment -> (M.t_Operation) list -> (M.t_DataType) list -> (Base.text) list -> bool -> (M.t_Diagnostic, G.t_Environment) Base.result_ =
fun v_declarations v_names v_environment v_operations v_types v_functions v_unique ->
(match v_unique with
| false ->
(G.f_infer_component (v_names) (v_declarations) (v_environment) (v_operations) (v_types) (v_functions))
| true ->
(f_infer_segment (v_declarations) (v_names) (v_environment) (v_operations) (v_types) (v_functions) ((G.f_component_bindings (v_names) ((G.f_env_bindings (v_environment)))))))
and (* parallel_infer.bend:630 *)
f_infer_component : (G.t_Declaration) list -> G.t_Environment -> (M.t_Operation) list -> (M.t_DataType) list -> (Base.text) list -> (M.t_Diagnostic, G.t_Environment) Base.result_ =
fun v_declarations v_environment v_operations v_types v_functions ->
(match v_declarations with
| [] ->
(Done (v_environment))
| [v_declaration] ->
(G.f_infer_declaration_prepared (v_declaration) (v_environment) (v_operations) (v_types) (v_functions) (None))
| (v_a :: (v_b :: v_rest)) ->
(let v_all = (v_a :: (v_b :: v_rest)) in
(let v_names = (G.f_names (v_all)) in
(f_infer_component_unique (v_all) (v_names) (v_environment) (v_operations) (v_types) (v_functions) ((f_unique_names (v_names) ((Base.set_new ()))))))))
