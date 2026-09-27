(* Native semantic port of compiler/selected_binding_evidence.bend.

   Source SHA-256: cc262dc64e419654fbc274513eb22c488b9dd2448a203ae86142b828e6a1f793

   Ownership/type arguments are erased; value types are checked by OCaml.

   No Bend interpreter or generated C/JavaScript is linked. *)

open Base

module M = Ox_model

module I = Ox_infer

module T = Ox_types

module C = Ox_constraints

module Compare = Ox_core_compare

type t_Lookup =
  | Missing
  | Unique of I.t_Binding
  | Duplicate

let s_0 = Base.text_of_utf8 "selected source binding"

let rec (* selected_binding_evidence.bend:13 *)
f_admissible_row : M.t_EffectRow -> bool =
fun v_row ->
(match v_row with
| (M.EffectRow (v_operations, M.ClosedRow)) ->
true
| (M.EffectRow (v_operations, (M.RowVariable (v_index)))) ->
true
| _ ->
false)
and (* selected_binding_evidence.bend:19 *)
f_admissible_types : int -> (M.t_Ty) list -> bool =
fun v_fuel v_pending ->
(match (v_fuel, v_pending) with
| (_, []) ->
true
| (0, _) ->
false
| (__nat_1, (M.UnitTy :: v_tail)) when __nat_1 >= 1 ->
(let v_rest = (__nat_1 - 1) in
(f_admissible_types (v_rest) (v_tail)))
| (__nat_2, (M.U32Ty :: v_tail)) when __nat_2 >= 1 ->
(let v_rest = (__nat_2 - 1) in
(f_admissible_types (v_rest) (v_tail)))
| (__nat_3, (M.F32Ty :: v_tail)) when __nat_3 >= 1 ->
(let v_rest = (__nat_3 - 1) in
(f_admissible_types (v_rest) (v_tail)))
| (__nat_4, (M.BoolTy :: v_tail)) when __nat_4 >= 1 ->
(let v_rest = (__nat_4 - 1) in
(f_admissible_types (v_rest) (v_tail)))
| (__nat_5, (M.EffectDescriptorTy :: v_tail)) when __nat_5 >= 1 ->
(let v_rest = (__nat_5 - 1) in
(f_admissible_types (v_rest) (v_tail)))
| (__nat_6, (M.EffectSetTy :: v_tail)) when __nat_6 >= 1 ->
(let v_rest = (__nat_6 - 1) in
(f_admissible_types (v_rest) (v_tail)))
| (__nat_7, ((M.VariableTy (v_index)) :: v_tail)) when __nat_7 >= 1 ->
(let v_rest = (__nat_7 - 1) in
(f_admissible_types (v_rest) (v_tail)))
| (__nat_8, ((M.FunctionTy (v_parameter, v_result, v_effects)) :: v_tail)) when __nat_8 >= 1 ->
(let v_rest = (__nat_8 - 1) in
(Base.bool_and ((f_admissible_row (v_effects))) ((f_admissible_types (v_rest) ((v_parameter :: (v_result :: v_tail)))))))
| (__nat_9, ((M.ProviderTy (v_identity, v_effects)) :: v_tail)) when __nat_9 >= 1 ->
(let v_rest = (__nat_9 - 1) in
(Base.bool_and ((f_admissible_row (v_effects))) ((f_admissible_types (v_rest) (v_tail)))))
| (__nat_10, ((M.StateProviderTy (v_read, v_write, v_state)) :: v_tail)) when __nat_10 >= 1 ->
(let v_rest = (__nat_10 - 1) in
(f_admissible_types (v_rest) ((v_state :: v_tail))))
| (__nat_11, ((M.AppliedTy (v_identity, v_arguments)) :: v_tail)) when __nat_11 >= 1 ->
(let v_rest = (__nat_11 - 1) in
(f_admissible_types (v_rest) ((Base.list_append (v_arguments) (v_tail)))))
| (__nat_12, ((M.ProductTy (v_elements)) :: v_tail)) when __nat_12 >= 1 ->
(let v_rest = (__nat_12 - 1) in
(f_admissible_types (v_rest) ((Base.list_append (v_elements) (v_tail)))))
| (__nat_13, ((M.ArrayTy (v_element)) :: v_tail)) when __nat_13 >= 1 ->
(let v_rest = (__nat_13 - 1) in
(f_admissible_types (v_rest) ((v_element :: v_tail))))
| (_, _) ->
false)
and (* selected_binding_evidence.bend:46 *)
f_unique_variables : (int) list -> bool =
fun v_values ->
(match v_values with
| [] ->
true
| (v_head :: v_tail) ->
(Base.bool_and ((Base.bool_not ((T.f_contains (v_tail) (v_head))))) ((f_unique_variables (v_tail)))))
and (* selected_binding_evidence.bend:52 *)
f_subset : (int) list -> (int) list -> bool =
fun v_values v_allowed ->
(match v_values with
| [] ->
true
| (v_head :: v_tail) ->
(Base.bool_and ((T.f_contains (v_allowed) (v_head))) ((f_subset (v_tail) (v_allowed)))))
and (* selected_binding_evidence.bend:58 *)
f_resolved_same : (M.t_Diagnostic, M.t_Ty) Base.result_ -> M.t_Ty -> bool =
fun v_found v_selected ->
(match v_found with
| (Done (v_resolved)) ->
(Compare.f_same_ty (v_resolved) (v_selected))
| (Fail (v_diagnostic)) ->
false)
and (* selected_binding_evidence.bend:63 *)
f_unified : (M.t_Diagnostic, T.t_Substitutions) Base.result_ -> M.t_Ty -> bool =
fun v_found v_selected ->
(match v_found with
| (Done (v_substitutions)) ->
(f_resolved_same ((T.f_resolve (v_substitutions) (v_selected))) (v_selected))
| (Fail (v_diagnostic)) ->
false)
and (* selected_binding_evidence.bend:69 *)
f_renamed : (M.t_Diagnostic, M.t_Ty) Base.result_ -> M.t_Ty -> bool =
fun v_found v_selected ->
(match v_found with
| (Done (v_fresh)) ->
(f_unified ((T.f_unify (v_fresh) (v_selected) ((T.f_empty ())) (s_0))) (v_selected))
| (Fail (v_diagnostic)) ->
false)
and (* selected_binding_evidence.bend:75 *)
f_freshened : T.t_Renaming -> M.t_Ty -> M.t_Ty -> bool =
fun v_renaming v_source v_selected ->
(match v_renaming with
| (T.Renaming (v_mapping, v_next, true)) ->
(f_renamed ((T.f_rename_type (v_source) (v_mapping))) (v_selected))
| _ ->
false)
and (* selected_binding_evidence.bend:82 *)
f_admissible_instance : bool -> M.t_Ty -> M.t_Ty -> (int) list -> (int) list -> (int) list -> bool =
fun v_ready v_source v_selected v_quantified v_source_free v_selected_free ->
(match v_ready with
| true ->
(f_freshened ((T.f_renaming (v_quantified) ((T.f_above ((T.f_union (v_source_free) (v_selected_free))) (0))))) (v_source) (v_selected))
| false ->
false)
and (* selected_binding_evidence.bend:88 *)
f_checked_free : (M.t_Diagnostic, (int) list) Base.result_ -> (M.t_Diagnostic, (int) list) Base.result_ -> M.t_Ty -> M.t_Ty -> (int) list -> (int) list -> bool =
fun v_source_result v_selected_result v_source v_selected v_quantified v_owner_bound ->
(match (v_source_result, v_selected_result) with
| ((Done (v_source_free)), (Done (v_selected_free))) ->
(f_admissible_instance ((Base.bool_and ((f_unique_variables (v_quantified))) ((Base.bool_and ((f_subset (v_source_free) (v_quantified))) ((Base.bool_and ((f_subset (v_selected_free) (v_owner_bound))) ((Base.bool_and ((f_admissible_types (65536) ([v_source]))) ((f_admissible_types (65536) ([v_selected]))))))))))) (v_source) (v_selected) (v_quantified) (v_source_free) (v_selected_free))
| (_, _) ->
false)
and (* selected_binding_evidence.bend:94 *)
f_checked_binding : I.t_Binding -> M.t_Ty -> (int) list -> bool =
fun v_binding v_selected v_owner_bound ->
(let (I.Binding (v_name, v_source, v_quantified, v_predicates)) = v_binding in
(match v_predicates with
| [] ->
(f_checked_free ((T.f_free (v_source))) ((T.f_free (v_selected))) (v_source) (v_selected) (v_quantified) (v_owner_bound))
| _ ->
false))
and (* selected_binding_evidence.bend:101 *)
f_certify_same : bool -> I.t_Binding -> M.t_Ty -> (int) list -> bool =
fun v_same v_binding v_selected v_owner_bound ->
(match v_same with
| true ->
(f_checked_binding (v_binding) (v_selected) (v_owner_bound))
| false ->
false)
and (* selected_binding_evidence.bend:109 *)
f_certify : I.t_Binding -> C.t_Evidence -> (int) list -> bool =
fun v_binding v_evidence v_owner_bound ->
(match (v_binding, v_evidence) with
| ((I.Binding (v_source_name, v_ty, v_variables, v_predicates)), (C.SelectedFunction (v_selected_name, v_selected))) ->
(f_certify_same ((M.f_name_equal (v_source_name) (v_selected_name))) ((I.Binding (v_source_name, v_ty, v_variables, v_predicates))) (v_selected) (v_owner_bound))
| (_, _) ->
false)
and (* selected_binding_evidence.bend:120 *)
f_seen : bool -> I.t_Binding -> t_Lookup -> t_Lookup =
fun v_same v_binding v_found ->
(match (v_same, v_found) with
| (true, Missing) ->
(Unique (v_binding))
| (true, _) ->
Duplicate
| (false, v_prior) ->
v_prior)
and (* selected_binding_evidence.bend:126 *)
f_unique_binding : (I.t_Binding) list -> Base.text -> t_Lookup -> t_Lookup =
fun v_bindings v_name v_found ->
(match v_bindings with
| [] ->
v_found
| (v_binding :: v_tail) ->
(let (I.Binding (v_current, v_ty, v_variables, v_predicates)) = v_binding in
(f_unique_binding (v_tail) (v_name) ((f_seen ((M.f_name_equal (v_current) (v_name))) (v_binding) (v_found))))))
and (* selected_binding_evidence.bend:133 *)
f_certify_found : t_Lookup -> C.t_Evidence -> (int) list -> bool =
fun v_found v_evidence v_owner_bound ->
(match v_found with
| (Unique (v_binding)) ->
(f_certify (v_binding) (v_evidence) (v_owner_bound))
| _ ->
false)
and (* selected_binding_evidence.bend:140 *)
f_certify_named : Base.text -> C.t_Evidence -> (int) list -> (I.t_Binding) list -> bool =
fun v_name v_evidence v_owner_bound v_current ->
(f_certify_found ((f_unique_binding (v_current) (v_name) (Missing))) (v_evidence) (v_owner_bound))
