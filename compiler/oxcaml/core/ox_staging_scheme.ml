(* Native semantic port of compiler/staging_scheme.bend.

   Source SHA-256: b537b0b3478969f68e0882825a6ec67917e15ff327e950323644d30d0183b0a2

   Ownership/type arguments are erased; value types are checked by OCaml.

   No Bend interpreter or generated C/JavaScript is linked. *)

open Base

module M = Ox_model

module I = Ox_infer

module G = Ox_globals

module T = Ox_types

module R = Ox_staging_residual

module F = Ox_closures

module NatIndex = Ox_nat_index

module Compare = Ox_core_compare

module C = Ox_constraints

type t_Scheme =
  | Scheme of M.t_Function * I.t_Inference * (int) list * int * (M.t_DataType) list
and t_LocalSite =
  | LocalSite of int * Base.text
and t_CloneName =
  | CloneName of int * Base.text
and t_Placeholder =
  | Placeholder of int * int * int * M.t_Ty
and t_Candidate =
  | Candidate of t_Scheme * t_CloneName

let s_0 = Base.text_of_utf8 "@type.same"

let s_1 = Base.text_of_utf8 "$prelude.Type.eq"

let s_2 = Base.text_of_utf8 "offset:"

let s_3 = Base.text_of_utf8 "$mono["

let rec (* staging_scheme.bend:23 *)
f_safe_work : int -> (M.t_Expr) list -> bool =
fun v_fuel v_pending ->
(match (v_fuel, v_pending) with
| (_, []) ->
true
| (0, _) ->
false
| (__nat_1, ((M.SourceExpr (v_offset, None, (M.InstantiationExpr (v_site, (M.LocalExpr (v_name)))))) :: v_tail)) when __nat_1 >= 1 ->
(let v_rest = (__nat_1 - 1) in
(Base.bool_and ((Base.nat_is_eq (v_site) ((Base.nat_mul (v_offset) (16))))) ((f_safe_work (v_rest) (v_tail)))))
| (__nat_2, ((M.SourceExpr (v_offset, None, v_value)) :: v_tail)) when __nat_2 >= 1 ->
(let v_rest = (__nat_2 - 1) in
(f_safe_work (v_rest) ((v_value :: v_tail))))
| (__nat_3, ((M.LambdaExpr (v_identity, v_parameter, None, None, v_body)) :: v_tail)) when __nat_3 >= 1 ->
(let v_rest = (__nat_3 - 1) in
(f_safe_work (v_rest) ((v_body :: v_tail))))
| (__nat_4, ((M.MatchExpr (v_values, v_arms)) :: v_tail)) when __nat_4 >= 1 ->
(let v_rest = (__nat_4 - 1) in
(f_safe_work (v_rest) ((Base.list_append ((F.f_children ((M.MatchExpr (v_values, v_arms))))) (v_tail)))))
| (__nat_5, ((M.AssociatedExpr (v_identity, M.BinaryDispatch, v_member, [], v_left, v_right)) :: v_tail)) when __nat_5 >= 1 ->
(let v_rest = (__nat_5 - 1) in
(Base.bool_and ((M.f_name_equal (v_member) (s_0))) ((f_safe_work (v_rest) ((v_left :: (v_right :: v_tail)))))))
| (_, _) ->
false)
and (* staging_scheme.bend:42 *)
f_eligible : M.t_Function -> bool =
fun v_function ->
(match v_function with
| (M.Function (v_name, v_exported, v_parameter, None, None, v_body)) ->
(Base.bool_and ((M.f_name_equal (v_name) (s_1))) ((f_safe_work (65536) ([v_body]))))
| _ ->
false)
and (* staging_scheme.bend:53 *)
f_local_sites_work : int -> (M.t_Expr) list -> (t_LocalSite) list -> ((t_LocalSite) list) option =
fun v_fuel v_pending v_reversed ->
(match (v_fuel, v_pending) with
| (0, _) ->
None
| (__nat_6, []) when __nat_6 >= 1 ->
(let v_rest = (__nat_6 - 1) in
(Some ((Base.list_reverse (v_reversed)))))
| (__nat_7, ((M.SourceExpr (v_offset, None, (M.InstantiationExpr (v_site, (M.LocalExpr (v_name)))))) :: v_tail)) when __nat_7 >= 1 ->
(let v_rest = (__nat_7 - 1) in
(f_local_sites_work (v_rest) (v_tail) (((LocalSite (v_site, (Base.string_append s_2 (Base.nat_show (v_offset))))) :: v_reversed))))
| (__nat_8, (v_head :: v_tail)) when __nat_8 >= 1 ->
(let v_rest = (__nat_8 - 1) in
(f_local_sites_work (v_rest) ((Base.list_append ((F.f_children (v_head))) (v_tail))) (v_reversed))))
and (* staging_scheme.bend:64 *)
f_local_sites : M.t_Function -> ((t_LocalSite) list) option =
fun v_source ->
(let (M.Function (v_name, v_exported, v_parameter, v_p, v_r, v_body)) = v_source in
(f_local_sites_work (65536) ([v_body]) ([])))
and (* staging_scheme.bend:68 *)
f_use_count : (C.t_UsePlan) list -> int -> Base.text -> int =
fun v_uses v_site v_subject ->
(match v_uses with
| [] ->
0
| ((C.UsePlan (v_actual, v_found, v_ty, v_predicates)) :: v_tail) ->
(Base.nat_add ((Base.bool_pick ((Base.bool_and ((Base.nat_is_eq (v_site) (v_actual))) ((M.f_name_equal (v_subject) (v_found))))) (1) (0))) ((f_use_count (v_tail) (v_site) (v_subject)))))
and (* staging_scheme.bend:75 *)
f_each_site : (t_LocalSite) list -> (C.t_UsePlan) list -> bool =
fun v_sites v_uses ->
(match v_sites with
| [] ->
true
| ((LocalSite (v_site, v_subject)) :: v_tail) ->
(Base.bool_and ((Base.nat_is_eq ((f_use_count (v_uses) (v_site) (v_subject))) (1))) ((f_each_site (v_tail) (v_uses)))))
and (* staging_scheme.bend:82 *)
f_site_count : (t_LocalSite) list -> int -> Base.text -> int =
fun v_sites v_wanted v_subject ->
(match v_sites with
| [] ->
0
| ((LocalSite (v_site, v_found)) :: v_tail) ->
(Base.nat_add ((Base.bool_pick ((Base.bool_and ((Base.nat_is_eq (v_site) (v_wanted))) ((M.f_name_equal (v_subject) (v_found))))) (1) (0))) ((f_site_count (v_tail) (v_wanted) (v_subject)))))
and (* staging_scheme.bend:89 *)
f_each_use : (C.t_UsePlan) list -> (t_LocalSite) list -> bool =
fun v_uses v_sites ->
(match v_uses with
| [] ->
true
| ((C.UsePlan (v_site, v_subject, v_ty, [])) :: v_tail) ->
(Base.bool_and ((Base.nat_is_eq ((f_site_count (v_sites) (v_site) (v_subject))) (1))) ((f_each_use (v_tail) (v_sites))))
| _ ->
false)
and (* staging_scheme.bend:98 *)
f_matched_uses : ((t_LocalSite) list) option -> (C.t_UsePlan) list -> bool =
fun v_found v_uses ->
(match v_found with
| None ->
false
| (Some (v_sites)) ->
(Base.bool_and ((Base.nat_is_gt ((Base.list_length (v_sites))) (0))) ((Base.bool_and ((Base.nat_is_eq ((Base.list_length (v_sites))) ((Base.list_length (v_uses))))) ((Base.bool_and ((f_each_site (v_sites) (v_uses))) ((f_each_use (v_uses) (v_sites)))))))))
and (* staging_scheme.bend:105 *)
f_type_equality_inference : M.t_Function -> I.t_Inference -> bool =
fun v_source v_value ->
(match v_value with
| (I.Inference ((M.FunctionTy (v_parameter, v_result, v_effects)), ((I.Coverage (v_inferred, v_patterns, v_coverage_subject)) :: ((I.AssociatedNeed (v_identity, M.BinaryDispatch, v_member, [], v_left, v_right, v_selected, (Some (v_invocation)), v_ambient, v_subject)) :: [])), [], [], (v_predicate :: []), v_uses)) ->
(Base.bool_and ((f_eligible (v_source))) ((Base.bool_and ((M.f_name_equal (v_member) (s_0))) ((Base.bool_and ((M.f_name_equal (v_subject) ((Base.string_append s_2 (Base.nat_show (v_identity)))))) ((Base.bool_and ((Compare.f_same_predicate (v_predicate) ((M.AssociatedPredicate (v_member, [], v_left, v_right, v_selected, v_invocation))))) ((f_matched_uses ((f_local_sites (v_source))) (v_uses))))))))))
| _ ->
false)
and (* staging_scheme.bend:114 *)
f_captured_free : (M.t_Diagnostic, (int) list) Base.result_ -> M.t_Function -> I.t_Inference -> int -> (M.t_DataType) list -> (t_Scheme) option =
fun v_free v_source v_inference v_allocated v_types ->
(match v_free with
| (Fail (v_diagnostic)) ->
None
| (Done (v_variables)) ->
(Base.bool_pick ((Base.bool_and ((Base.nat_is_ge (v_allocated) (3))) ((Base.bool_and ((Base.nat_is_le ((T.f_above (v_variables) (0))) (v_allocated))) ((f_type_equality_inference (v_source) (v_inference))))))) ((Some ((Scheme (v_source, v_inference, v_variables, v_allocated, v_types))))) (None)))
and (* staging_scheme.bend:121 *)
f_captured_resolved : (M.t_Diagnostic, I.t_Inference) Base.result_ -> M.t_Function -> int -> (M.t_DataType) list -> (t_Scheme) option =
fun v_resolved v_source v_allocated v_types ->
(match v_resolved with
| (Fail (v_diagnostic)) ->
None
| (Done (v_inference)) ->
(f_captured_free ((R.f_free (v_inference))) (v_source) (v_inference) (v_allocated) (v_types)))
and (* staging_scheme.bend:128 *)
f_captured : (M.t_Diagnostic, G.t_Environment) Base.result_ -> M.t_Function -> (M.t_DataType) list -> (t_Scheme) option =
fun v_result v_source v_types ->
(match v_result with
| (Fail (v_diagnostic)) ->
None
| (Done ((G.Environment (v_bindings, v_definitions, v_state)))) ->
(match v_definitions with
| ((I.Definition (v_name, v_inference)) :: []) ->
(f_captured_resolved ((R.f_resolve (v_inference) ((I.f_substitutions_of (v_state))))) (v_source) ((I.f_next_of (v_state))) (v_types))
| _ ->
None))
and (* staging_scheme.bend:139 *)
f_capture_one : M.t_Function -> (M.t_Operation) list -> (M.t_DataType) list -> (t_Scheme) option =
fun v_function v_operations v_types ->
(match v_function with
| v_source ->
(let (M.Function (v_name, v_exported, v_parameter, v_annotation, v_result, v_body)) = v_source in
(let v_declarations = (G.f_function_declarations ([v_source])) in
(let v_initial = (G.f_initial_bindings (v_declarations) (0)) in
(f_captured ((G.f_infer_component ([v_name]) (v_declarations) ((G.Environment (v_initial, [], (I.State ((T.f_empty ()), (G.f_initial_next (v_declarations) (0)), MTip))))) (v_operations) (v_types) ([v_name]))) (v_source) (v_types))))))
and (* staging_scheme.bend:147 *)
f_capture_if : bool -> M.t_Function -> (M.t_Operation) list -> (M.t_DataType) list -> (t_Scheme) option =
fun v_allowed v_function v_operations v_types ->
(match v_allowed with
| false ->
None
| true ->
(f_capture_one (v_function) (v_operations) (v_types)))
and (* staging_scheme.bend:154 *)
f_append : (t_Scheme) option -> (t_Scheme) list -> (t_Scheme) list =
fun v_found v_rest ->
(match v_found with
| None ->
v_rest
| (Some (v_value)) ->
(v_value :: v_rest))
and (* staging_scheme.bend:161 *)
f_capture : (M.t_Function) list -> (M.t_Operation) list -> (M.t_DataType) list -> (t_Scheme) list =
fun v_functions v_operations v_types ->
(match v_functions with
| [] ->
[]
| (v_head :: v_tail) ->
(f_append ((f_capture_if ((f_eligible (v_head))) (v_head) (v_operations) (v_types))) ((f_capture (v_tail) (v_operations) (v_types)))))
and (* staging_scheme.bend:168 *)
f_capture_closed : bool -> (M.t_Function) list -> (M.t_Operation) list -> (M.t_DataType) list -> (t_Scheme) list =
fun v_closed v_functions v_operations v_types ->
(match v_closed with
| false ->
[]
| true ->
(f_capture (v_functions) (v_operations) (v_types)))
and (* staging_scheme.bend:178 *)
f_parsed_number : (int) option -> Base.text -> (t_CloneName) option =
fun v_value v_source ->
(match v_value with
| None ->
None
| (Some (v_counter)) ->
(Some ((CloneName (v_counter, v_source)))))
and (* staging_scheme.bend:185 *)
f_parse_digits : Base.text -> Base.text -> (t_CloneName) option =
fun v_value v_reversed ->
(match v_value with
| (SCon ((Chr ((Base.W32 0x5d))), (SCon ((Chr ((Base.W32 0x2e))), v_source)))) ->
(f_parsed_number ((Base.nat_read ((Base.string_reverse (v_reversed))))) (v_source))
| (SCon (v_character, v_tail)) ->
(f_parse_digits (v_tail) ((SCon (v_character, v_reversed))))
| SNil ->
None)
and (* staging_scheme.bend:194 *)
f_parse_prefix : bool -> Base.text -> (t_CloneName) option =
fun v_found v_name ->
(match v_found with
| false ->
None
| true ->
(f_parse_digits ((Base.string_drop (v_name) (6))) (SNil)))
and (* staging_scheme.bend:201 *)
f_clone_name : Base.text -> (t_CloneName) option =
fun v_name ->
(f_parse_prefix ((Base.string_starts_with (v_name) (s_3))) (v_name))
and (* staging_scheme.bend:204 *)
f_source_name : M.t_Function -> Base.text =
fun v_source ->
(let (M.Function (v_name, v_exported, v_parameter, v_annotation, v_result, v_body)) = v_source in
v_name)
and (* staging_scheme.bend:208 *)
f_scheme_source : t_Scheme -> M.t_Function =
fun v_scheme ->
(let (Scheme (v_source, v_inference, v_variables, v_allocated, v_types)) = v_scheme in
v_source)
and (* staging_scheme.bend:212 *)
f_matches_source : t_Scheme -> t_CloneName -> bool =
fun v_scheme v_parsed ->
(let (Scheme (v_source, v_inference, v_variables, v_allocated, v_types)) = v_scheme in
(let (CloneName (v_counter, v_original)) = v_parsed in
(M.f_name_equal ((f_source_name (v_source))) (v_original))))
and (* staging_scheme.bend:220 *)
f_placeholder : (I.t_Binding) option -> Base.text -> (t_Placeholder) option =
fun v_found v_wanted ->
(match v_found with
| (Some ((I.Binding (v_name, (M.FunctionTy ((M.VariableTy (v_p)), (M.VariableTy (v_r)), (M.EffectRow ([], (M.RowVariable (v_e)))))), [], [])))) ->
(Base.bool_pick ((M.f_name_equal (v_name) (v_wanted))) ((Some ((Placeholder (v_p, v_r, v_e, (M.FunctionTy ((M.VariableTy (v_p)), (M.VariableTy (v_r)), (M.EffectRow ([], (M.RowVariable (v_e))))))))))) (None))
| _ ->
None)
and (* staging_scheme.bend:227 *)
f_map_body : int -> int -> int -> (int) NatIndex.t_Index -> (int) NatIndex.t_Index =
fun v_remaining v_old v_fresh v_mapping ->
(match v_remaining with
| 0 ->
v_mapping
| __nat_9 when __nat_9 >= 1 ->
(let v_rest = (__nat_9 - 1) in
(f_map_body (v_rest) ((Base.nat_add 1 v_old)) ((Base.nat_add 1 v_fresh)) ((NatIndex.f_set (v_mapping) (v_old) (v_fresh))))))
and (* staging_scheme.bend:234 *)
f_mapping : t_Placeholder -> int -> int -> (int) NatIndex.t_Index =
fun v_placeholder v_allocated v_next ->
(let (Placeholder (v_p, v_r, v_e, v_ty)) = v_placeholder in
(let v_head = (NatIndex.f_set ((NatIndex.f_set ((NatIndex.f_set ((NatIndex.f_new ())) (0) (v_p))) (1) (v_r))) (2) (v_e)) in
(f_map_body ((Base.nat_sub (v_allocated) (3))) (3) (v_next) (v_head))))
and (* staging_scheme.bend:239 *)
f_replay_unified : (M.t_Diagnostic, I.t_State) Base.result_ -> Base.text -> I.t_Inference -> (I.t_Binding) list -> (I.t_Definition) list -> (G.t_Environment) option =
fun v_result v_name v_inference v_bindings v_definitions ->
(match v_result with
| (Fail (v_diagnostic)) ->
None
| (Done (v_state)) ->
(Some ((G.Environment (v_bindings, ((I.Definition (v_name, v_inference)) :: v_definitions), (I.f_clear_annotations (v_state)))))))
and (* staging_scheme.bend:246 *)
f_replay_offset : (M.t_Diagnostic, I.t_Inference) Base.result_ -> Base.text -> t_Placeholder -> I.t_State -> (I.t_Binding) list -> (I.t_Definition) list -> int -> (G.t_Environment) option =
fun v_result v_name v_placeholder v_state v_bindings v_definitions v_next ->
(match v_result with
| (Fail (v_diagnostic)) ->
None
| (Done (v_inference)) ->
(let (Placeholder (v_p, v_r, v_e, v_expected)) = v_placeholder in
(f_replay_unified ((I.f_unify ((I.f_inferred_type (v_inference))) (v_expected) ((I.f_with_next (v_state) (v_next))) (v_name))) (v_name) (v_inference) (v_bindings) (v_definitions))))
and (* staging_scheme.bend:254 *)
f_replay_renamed : (M.t_Diagnostic, I.t_Inference) Base.result_ -> Base.text -> int -> t_Placeholder -> I.t_State -> (I.t_Binding) list -> (I.t_Definition) list -> int -> (G.t_Environment) option =
fun v_result v_name v_base v_placeholder v_state v_bindings v_definitions v_next ->
(match v_result with
| (Fail (v_diagnostic)) ->
None
| (Done (v_inference)) ->
(f_replay_offset ((R.f_offset_identities (v_inference) (v_base))) (v_name) (v_placeholder) (v_state) (v_bindings) (v_definitions) (v_next)))
and (* staging_scheme.bend:261 *)
f_scheme_inference : t_Scheme -> I.t_Inference =
fun v_scheme ->
(let (Scheme (v_source, v_inference, v_variables, v_allocated, v_types)) = v_scheme in
v_inference)
and (* staging_scheme.bend:265 *)
f_scheme_allocated : t_Scheme -> int =
fun v_scheme ->
(let (Scheme (v_source, v_inference, v_variables, v_allocated, v_types)) = v_scheme in
v_allocated)
and (* staging_scheme.bend:269 *)
f_clone_counter : t_CloneName -> int =
fun v_parsed ->
(let (CloneName (v_counter, v_source)) = v_parsed in
v_counter)
and (* staging_scheme.bend:273 *)
f_replay_with_space : bool -> t_Placeholder -> t_Scheme -> M.t_Function -> t_CloneName -> int -> G.t_Environment -> (G.t_Environment) option =
fun v_fits v_placeholder v_scheme v_clone v_parsed v_stride v_environment ->
(match v_fits with
| false ->
None
| true ->
(let v_name = (f_source_name (v_clone)) in
(let v_allocated = (f_scheme_allocated (v_scheme)) in
(let v_next = (I.f_next_of ((G.f_env_state (v_environment)))) in
(let v_advanced = (Base.nat_add (v_next) ((Base.nat_sub (v_allocated) (3)))) in
(f_replay_renamed ((R.f_rewrite_inference ((f_scheme_inference (v_scheme))) ((R.Alpha ((f_mapping (v_placeholder) (v_allocated) (v_next)), (NatIndex.f_new ())))))) (v_name) ((Base.nat_mul ((f_clone_counter (v_parsed))) (v_stride))) (v_placeholder) ((G.f_env_state (v_environment))) ((G.f_env_bindings (v_environment))) ((G.f_env_definitions (v_environment))) (v_advanced)))))))
and (* staging_scheme.bend:284 *)
f_max_nat48 : unit -> int =
fun () ->
(Base.nat_add ((Base.nat_mul ((Base.u32_to_nat ((Base.W32 0xffffffff)))) (65536))) (65535))
and (* staging_scheme.bend:287 *)
f_replay_placeholder : (t_Placeholder) option -> t_Scheme -> M.t_Function -> t_CloneName -> int -> G.t_Environment -> (G.t_Environment) option =
fun v_found v_scheme v_clone v_parsed v_stride v_environment ->
(match v_found with
| None ->
None
| (Some (v_placeholder)) ->
(let v_allocated = (f_scheme_allocated (v_scheme)) in
(let v_next = (I.f_next_of ((G.f_env_state (v_environment)))) in
(f_replay_with_space ((Base.nat_is_le ((Base.nat_sub (v_allocated) (3))) ((Base.nat_sub ((f_max_nat48 ())) (v_next))))) (v_placeholder) (v_scheme) (v_clone) (v_parsed) (v_stride) (v_environment)))))
and (* staging_scheme.bend:296 *)
f_clean_state : I.t_State -> bool =
fun v_state ->
(match v_state with
| (I.State (v_substitutions, v_next, MTip)) ->
true
| _ ->
false)
and (* staging_scheme.bend:303 *)
f_replay_if_clean : bool -> (t_Placeholder) option -> t_Scheme -> M.t_Function -> t_CloneName -> int -> G.t_Environment -> (G.t_Environment) option =
fun v_clean v_found v_scheme v_clone v_parsed v_stride v_environment ->
(match v_clean with
| false ->
None
| true ->
(f_replay_placeholder (v_found) (v_scheme) (v_clone) (v_parsed) (v_stride) (v_environment)))
and (* staging_scheme.bend:310 *)
f_replay_scheme : bool -> t_Scheme -> M.t_Function -> t_CloneName -> int -> G.t_Environment -> (G.t_Environment) option =
fun v_allowed v_scheme v_clone v_parsed v_stride v_environment ->
(match v_allowed with
| false ->
None
| true ->
(let v_name = (f_source_name (v_clone)) in
(f_replay_if_clean ((f_clean_state ((G.f_env_state (v_environment))))) ((f_placeholder ((I.f_lookup_binding ((G.f_env_bindings (v_environment))) (v_name))) (v_name))) (v_scheme) (v_clone) (v_parsed) (v_stride) (v_environment))))
and (* staging_scheme.bend:318 *)
f_lookup : (t_Scheme) list -> Base.text -> (t_Scheme) option =
fun v_schemes v_wanted ->
(match v_schemes with
| [] ->
None
| (v_head :: v_tail) ->
(let (Scheme (v_source, v_inference, v_variables, v_allocated, v_types)) = v_head in
(Base.bool_pick ((M.f_name_equal ((f_source_name (v_source))) (v_wanted))) ((Some (v_head))) ((f_lookup (v_tail) (v_wanted))))))
and (* staging_scheme.bend:329 *)
f_candidate_found : (t_Scheme) option -> t_CloneName -> (t_Candidate) option =
fun v_found v_parsed ->
(match v_found with
| None ->
None
| (Some (v_scheme)) ->
(Base.bool_pick ((f_matches_source (v_scheme) (v_parsed))) ((Some ((Candidate (v_scheme, v_parsed))))) (None)))
and (* staging_scheme.bend:336 *)
f_candidate_parsed : (t_CloneName) option -> (t_Scheme) list -> (t_Candidate) option =
fun v_found v_schemes ->
(match v_found with
| None ->
None
| (Some (v_parsed)) ->
(let (CloneName (v_counter, v_original)) = v_parsed in
(f_candidate_found ((f_lookup (v_schemes) (v_original))) (v_parsed))))
and (* staging_scheme.bend:344 *)
f_candidate : M.t_Function -> (t_Scheme) list -> (t_Candidate) option =
fun v_clone v_schemes ->
(f_candidate_parsed ((f_clone_name ((f_source_name (v_clone))))) (v_schemes))
and (* staging_scheme.bend:347 *)
f_candidate_source : t_Candidate -> M.t_Function =
fun v_value ->
(let (Candidate (v_scheme, v_parsed)) = v_value in
(f_scheme_source (v_scheme)))
and (* staging_scheme.bend:351 *)
f_candidate_counter : t_Candidate -> int =
fun v_value ->
(let (Candidate (v_scheme, v_parsed)) = v_value in
(f_clone_counter (v_parsed)))
and (* staging_scheme.bend:355 *)
f_replay : t_Candidate -> M.t_Function -> int -> G.t_Environment -> (M.t_DataType) list -> bool -> (G.t_Environment) option =
fun v_value v_clone v_stride v_environment v_current_types v_exact ->
(let (Candidate (v_scheme, v_parsed)) = v_value in
(let (Scheme (v_source, v_inference, v_variables, v_allocated, v_types)) = v_scheme in
(f_replay_scheme ((Base.bool_and (v_exact) ((Compare.f_compare (1048576) ([(Compare.DataTypeListPair (v_types, v_current_types))]) (true))))) (v_scheme) (v_clone) (v_parsed) (v_stride) (v_environment))))
