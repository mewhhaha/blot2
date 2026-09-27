(* Native semantic port of compiler/state_run_evidence.bend.

   Source SHA-256: 3d01388a03b84216a2e88094072f6c1440b718568d50b486784b3ca12daaefb2

   Ownership/type arguments are erased; value types are checked by OCaml.

   No Bend interpreter or generated C/JavaScript is linked. *)

open Base

module M = Ox_model

module C = Ox_constraints

module T = Ox_types

module Rows = Ox_effect_rows

module State = Ox_state_specialize

module Compare = Ox_core_compare

type t_RunSource =
  | Builtin
  | Family of M.t_TypeId * M.t_TypeId

let s_0 = Base.text_of_utf8 "<"

let s_1 = Base.text_of_utf8 ">"

let s_2 = Base.text_of_utf8 "@state.run"

let s_3 = Base.text_of_utf8 "@effect.run"

let rec (* state_run_evidence.bend:13 *)
f_free_within : (M.t_Diagnostic, (int) list) Base.result_ -> (int) list -> bool =
fun v_found v_bound ->
(match v_found with
| (Done (v_free)) ->
(Base.list_is_empty ((T.f_difference (v_free) (v_bound))))
| (Fail (v_diagnostic)) ->
false)
and (* state_run_evidence.bend:20 *)
f_admissible_tail : M.t_RowTail -> (int) list -> bool =
fun v_tail v_bound ->
(match v_tail with
| M.ClosedRow ->
true
| (M.RowVariable (v_index)) ->
(T.f_contains (v_bound) (v_index))
| _ ->
false)
and (* state_run_evidence.bend:32 *)
f_admissible_result_type : int -> (M.t_Ty) list -> (int) list -> bool =
fun v_fuel v_pending v_bound ->
(match (v_fuel, v_pending) with
| (0, _) ->
false
| (__nat_1, []) when __nat_1 >= 1 ->
(let v_rest = (__nat_1 - 1) in
true)
| (__nat_2, ((M.VariableTy (v_index)) :: v_tail)) when __nat_2 >= 1 ->
(let v_rest = (__nat_2 - 1) in
(Base.bool_and ((T.f_contains (v_bound) (v_index))) ((f_admissible_result_type (v_rest) (v_tail) (v_bound)))))
| (__nat_3, ((M.ParameterTy (v_index)) :: v_tail)) when __nat_3 >= 1 ->
(let v_rest = (__nat_3 - 1) in
false)
| (__nat_4, ((M.FreeTy (v_scope, v_name)) :: v_tail)) when __nat_4 >= 1 ->
(let v_rest = (__nat_4 - 1) in
false)
| (__nat_5, ((M.FunctionTy (v_parameter, v_result, v_effects)) :: v_tail)) when __nat_5 >= 1 ->
(let v_rest = (__nat_5 - 1) in
(Base.bool_and ((f_admissible_tail ((Rows.f_row_tail (v_effects))) (v_bound))) ((f_admissible_result_type (v_rest) ((v_parameter :: (v_result :: v_tail))) (v_bound)))))
| (__nat_6, ((M.ProviderTy (v_identity, v_effects)) :: v_tail)) when __nat_6 >= 1 ->
(let v_rest = (__nat_6 - 1) in
(Base.bool_and ((f_admissible_tail ((Rows.f_row_tail (v_effects))) (v_bound))) ((f_admissible_result_type (v_rest) (v_tail) (v_bound)))))
| (__nat_7, ((M.StateProviderTy (v_read, v_write, v_state)) :: v_tail)) when __nat_7 >= 1 ->
(let v_rest = (__nat_7 - 1) in
(f_admissible_result_type (v_rest) ((v_state :: v_tail)) (v_bound)))
| (__nat_8, ((M.AppliedTy (v_identity, v_arguments)) :: v_tail)) when __nat_8 >= 1 ->
(let v_rest = (__nat_8 - 1) in
(f_admissible_result_type (v_rest) ((Base.list_append (v_arguments) (v_tail))) (v_bound)))
| (__nat_9, ((M.ProductTy (v_elements)) :: v_tail)) when __nat_9 >= 1 ->
(let v_rest = (__nat_9 - 1) in
(f_admissible_result_type (v_rest) ((Base.list_append (v_elements) (v_tail))) (v_bound)))
| (__nat_10, ((M.ArrayTy (v_element)) :: v_tail)) when __nat_10 >= 1 ->
(let v_rest = (__nat_10 - 1) in
(f_admissible_result_type (v_rest) ((v_element :: v_tail)) (v_bound)))
| (__nat_11, (M.UnitTy :: v_tail)) when __nat_11 >= 1 ->
(let v_rest = (__nat_11 - 1) in
(f_admissible_result_type (v_rest) (v_tail) (v_bound)))
| (__nat_12, (M.U32Ty :: v_tail)) when __nat_12 >= 1 ->
(let v_rest = (__nat_12 - 1) in
(f_admissible_result_type (v_rest) (v_tail) (v_bound)))
| (__nat_13, (M.BoolTy :: v_tail)) when __nat_13 >= 1 ->
(let v_rest = (__nat_13 - 1) in
(f_admissible_result_type (v_rest) (v_tail) (v_bound)))
| (__nat_14, (M.NeverTy :: v_tail)) when __nat_14 >= 1 ->
(let v_rest = (__nat_14 - 1) in
(f_admissible_result_type (v_rest) (v_tail) (v_bound)))
| (__nat_15, (M.F32Ty :: v_tail)) when __nat_15 >= 1 ->
(let v_rest = (__nat_15 - 1) in
(f_admissible_result_type (v_rest) (v_tail) (v_bound)))
| (__nat_16, (M.EffectDescriptorTy :: v_tail)) when __nat_16 >= 1 ->
(let v_rest = (__nat_16 - 1) in
(f_admissible_result_type (v_rest) (v_tail) (v_bound)))
| (__nat_17, (M.EffectSetTy :: v_tail)) when __nat_17 >= 1 ->
(let v_rest = (__nat_17 - 1) in
(f_admissible_result_type (v_rest) (v_tail) (v_bound)))
| (__nat_18, (v_head :: v_tail)) when __nat_18 >= 1 ->
(let v_rest = (__nat_18 - 1) in
false))
and (* state_run_evidence.bend:73 *)
f_same_ty : M.t_Ty -> M.t_Ty -> bool =
fun v_left v_right ->
(Compare.f_compare (65536) ([(Compare.TyPair (v_left, v_right))]) (true))
and (* state_run_evidence.bend:76 *)
f_same_tail : M.t_RowTail -> M.t_RowTail -> bool =
fun v_left v_right ->
(Compare.f_compare (65536) ([(Compare.RowTailPair (v_left, v_right))]) (true))
and (* state_run_evidence.bend:79 *)
f_same_row : M.t_EffectRow -> M.t_EffectRow -> bool =
fun v_left v_right ->
(Compare.f_compare (65536) ([(Compare.EffectRowPair ((Rows.f_canonical (v_left)), (Rows.f_canonical (v_right))))]) (true))
and (* state_run_evidence.bend:85 *)
f_same_predicate : M.t_Predicate -> M.t_Predicate -> bool =
fun v_left v_right ->
(match (v_left, v_right) with
| ((M.AssociatedPredicate (v_am, v_at, v_al, (M.FunctionTy (v_ap, v_ar, v_ac)), v_av, v_ae)), (M.AssociatedPredicate (v_bm, v_bt, v_bl, (M.FunctionTy (v_bp, v_br, v_bc)), v_bv, v_be))) ->
(Compare.f_compare (65536) ([(Compare.PredicatePair ((M.AssociatedPredicate (v_am, v_at, v_al, (M.FunctionTy (v_ap, v_ar, (Rows.f_canonical (v_ac)))), v_av, (Rows.f_canonical (v_ae)))), (M.AssociatedPredicate (v_bm, v_bt, v_bl, (M.FunctionTy (v_bp, v_br, (Rows.f_canonical (v_bc)))), v_bv, (Rows.f_canonical (v_be))))))]) (true))
| (_, _) ->
false)
and (* state_run_evidence.bend:92 *)
f_same_operation : M.t_Operation -> M.t_Operation -> bool =
fun v_left v_right ->
(Compare.f_compare (65536) ([(Compare.OperationPair (v_left, v_right))]) (true))
and (* state_run_evidence.bend:97 *)
f_exact_operation : (M.t_Operation) list -> M.t_TypeId -> M.t_Operation -> bool -> bool =
fun v_operations v_wanted v_expected v_found ->
(match v_operations with
| [] ->
v_found
| ((M.Operation (v_identity, v_parameter, v_result)) :: v_tail) ->
(let v_same = (M.f_type_id_equal (v_identity) (v_wanted)) in
(let v_valid = (Base.bool_or ((Base.bool_not (v_same))) ((Base.bool_and ((Base.bool_not (v_found))) ((f_same_operation ((M.Operation (v_identity, v_parameter, v_result))) (v_expected)))))) in
(Base.bool_and (v_valid) ((f_exact_operation (v_tail) (v_wanted) (v_expected) ((Base.bool_or (v_found) (v_same))))))))
| ((M.OperationTemplate (v_identity, v_parameters, v_parameter, v_result)) :: v_tail) ->
(Base.bool_and ((Base.bool_not ((M.f_type_id_equal (v_identity) (v_wanted))))) ((f_exact_operation (v_tail) (v_wanted) (v_expected) (v_found))))
| ((M.OperationInstance (v_template, v_arguments)) :: v_tail) ->
(Base.bool_and ((Base.bool_not ((M.f_type_id_equal (v_template) (v_wanted))))) ((f_exact_operation (v_tail) (v_wanted) (v_expected) (v_found))))
| (v_head :: v_tail) ->
(f_exact_operation (v_tail) (v_wanted) (v_expected) (v_found)))
and (* state_run_evidence.bend:112 *)
f_exact_catalog : (M.t_Operation) list -> (M.t_Operation) list -> bool =
fun v_expected v_operations ->
(match v_expected with
| ((M.Operation (v_read, v_read_parameter, v_read_result)) :: ((M.Operation (v_write, v_write_parameter, v_write_result)) :: [])) ->
(Base.bool_and ((f_exact_operation (v_operations) (v_read) ((M.Operation (v_read, v_read_parameter, v_read_result))) (false))) ((f_exact_operation (v_operations) (v_write) ((M.Operation (v_write, v_write_parameter, v_write_result))) (false))))
| _ ->
false)
and (* state_run_evidence.bend:122 *)
f_exact_template : (M.t_Operation) list -> M.t_TypeId -> M.t_Operation -> bool -> bool =
fun v_operations v_wanted v_expected v_found ->
(match v_operations with
| [] ->
v_found
| ((M.OperationTemplate (v_identity, v_parameters, v_parameter, v_result)) :: v_tail) ->
(let v_same = (M.f_type_id_equal (v_identity) (v_wanted)) in
(let v_valid = (Base.bool_or ((Base.bool_not (v_same))) ((Base.bool_and ((Base.bool_not (v_found))) ((f_same_operation ((M.OperationTemplate (v_identity, v_parameters, v_parameter, v_result))) (v_expected)))))) in
(Base.bool_and (v_valid) ((f_exact_template (v_tail) (v_wanted) (v_expected) ((Base.bool_or (v_found) (v_same))))))))
| ((M.Operation (v_identity, v_parameter, v_result)) :: v_tail) ->
(Base.bool_and ((Base.bool_not ((M.f_type_id_equal (v_identity) (v_wanted))))) ((f_exact_template (v_tail) (v_wanted) (v_expected) (v_found))))
| ((M.OperationInstance (v_template, v_arguments)) :: v_tail) ->
(Base.bool_and ((Base.bool_not ((M.f_type_id_equal (v_template) (v_wanted))))) ((f_exact_template (v_tail) (v_wanted) (v_expected) (v_found)))))
and (* state_run_evidence.bend:135 *)
f_family_identity : M.t_TypeId -> Base.text -> M.t_TypeId =
fun v_template v_key ->
(let (M.TypeId (v_module_name, v_declaration)) = v_template in
(M.TypeId (v_module_name, (Base.string_append v_declaration (Base.string_append s_0 (Base.string_append v_key s_1))))))
and (* state_run_evidence.bend:139 *)
f_family_catalog : (M.t_Operation) list -> M.t_TypeId -> M.t_TypeId -> M.t_TypeId -> M.t_TypeId -> M.t_Ty -> bool =
fun v_operations v_read_template v_write_template v_read v_write v_state ->
(Base.bool_and ((Base.bool_not ((M.f_type_id_equal (v_read_template) (v_write_template))))) ((Base.bool_and ((f_exact_template (v_operations) (v_read_template) ((M.OperationTemplate (v_read_template, 1, M.UnitTy, (M.ParameterTy (0))))) (false))) ((Base.bool_and ((f_exact_template (v_operations) (v_write_template) ((M.OperationTemplate (v_write_template, 1, (M.ParameterTy (0)), M.UnitTy))) (false))) ((f_exact_catalog ([(M.Operation (v_read, M.UnitTy, v_state)); (M.Operation (v_write, v_state, M.UnitTy))]) (v_operations))))))))
and (* state_run_evidence.bend:151 *)
f_function_name : M.t_Function -> Base.text =
fun v_function ->
(let (M.Function (v_name, v_exported, v_parameter, v_p, v_r, v_body)) = v_function in
v_name)
and (* state_run_evidence.bend:155 *)
f_exact_run_body : M.t_Function -> Base.text -> M.t_TypeId -> M.t_TypeId -> bool =
fun v_function v_name v_read v_write ->
(match v_function with
| (M.Function (v_found, v_exported, v_parameter, v_p, v_r, (M.LambdaExpr (v_identity, v_inner_parameter, v_ip, v_ir, v_body)))) ->
(Compare.f_compare (65536) ([(Compare.FunctionPair ((M.Function (v_found, v_exported, v_parameter, v_p, v_r, (M.LambdaExpr (v_identity, v_inner_parameter, v_ip, v_ir, v_body)))), (State.f_function_for (State.Run) (v_read) (v_write) (v_name) (v_identity))))]) (true))
| _ ->
false)
and (* state_run_evidence.bend:164 *)
f_exact_named_run : (M.t_Function) list -> Base.text -> M.t_TypeId -> M.t_TypeId -> bool -> bool =
fun v_functions v_name v_read v_write v_found ->
(match v_functions with
| [] ->
v_found
| (v_head :: v_tail) ->
(let v_same = (M.f_name_equal ((f_function_name (v_head))) (v_name)) in
(let v_valid = (Base.bool_or ((Base.bool_not (v_same))) ((Base.bool_and ((Base.bool_not (v_found))) ((f_exact_run_body (v_head) (v_name) (v_read) (v_write)))))) in
(Base.bool_and (v_valid) ((f_exact_named_run (v_tail) (v_name) (v_read) (v_write) ((Base.bool_or (v_found) (v_same)))))))))
and (* state_run_evidence.bend:177 *)
f_source_certificate : Base.text -> M.t_Predicate -> Base.text -> (M.t_TypeId) list -> M.t_Ty -> M.t_Ty -> M.t_Ty -> M.t_Ty -> (M.t_TypeId) list -> M.t_RowTail -> (M.t_TypeId) list -> M.t_RowTail -> (int) list -> M.t_TypeId -> M.t_TypeId -> bool -> (M.t_Function) list -> bool =
fun v_name v_predicate v_member v_templates v_state v_value v_returned_state v_returned_value v_labels v_callback_tail v_invocation_labels v_invocation_tail v_bound v_read v_write v_catalog_ok v_functions ->
(let v_callback = (M.FunctionTy (M.UnitTy, v_value, (M.EffectRow (v_labels, v_callback_tail)))) in
(let v_result = (M.ProductTy ([v_state; v_value])) in
(let v_invocation = (M.EffectRow (v_invocation_labels, v_invocation_tail)) in
(let v_expected = (M.AssociatedPredicate (v_member, v_templates, v_state, v_callback, v_result, v_invocation)) in
(Base.bool_and ((Base.bool_and ((f_same_ty (v_state) (v_returned_state))) ((f_same_ty (v_value) (v_returned_value))))) ((Base.bool_and ((Base.bool_and ((Base.bool_and ((f_admissible_tail (v_callback_tail) (v_bound))) ((f_admissible_result_type (65536) ([v_value]) (v_bound))))) ((f_same_tail (v_callback_tail) (v_invocation_tail))))) ((Base.bool_and ((Base.bool_and ((f_same_row ((M.EffectRow (v_labels, M.ClosedRow))) ((M.EffectRow ((Base.list_append ([v_read; v_write]) (v_invocation_labels)), M.ClosedRow))))) ((f_same_predicate (v_predicate) (v_expected))))) ((Base.bool_and (v_catalog_ok) ((f_exact_named_run (v_functions) (v_name) (v_read) (v_write) (false))))))))))))))
and (* state_run_evidence.bend:193 *)
f_key_certificate : (M.t_Diagnostic, Base.text) Base.result_ -> t_RunSource -> Base.text -> M.t_Predicate -> M.t_Ty -> M.t_Ty -> M.t_Ty -> M.t_Ty -> (M.t_TypeId) list -> M.t_RowTail -> (M.t_TypeId) list -> M.t_RowTail -> (int) list -> M.t_Module -> bool =
fun v_key_result v_source v_name v_predicate v_state v_value v_returned_state v_returned_value v_labels v_callback_tail v_invocation_labels v_invocation_tail v_bound v_module ->
(match (v_key_result, v_source) with
| ((Fail (v_diagnostic)), _) ->
false
| ((Done (v_key)), Builtin) ->
(let (M.Module (v_constants, v_functions, v_types, v_operations)) = v_module in
(let v_read = (State.f_read_identity (v_key)) in
(let v_write = (State.f_write_identity (v_key)) in
(f_source_certificate (v_name) (v_predicate) (s_2) ([]) (v_state) (v_value) (v_returned_state) (v_returned_value) (v_labels) (v_callback_tail) (v_invocation_labels) (v_invocation_tail) (v_bound) (v_read) (v_write) ((f_exact_catalog ((State.f_operations (v_key) (v_state) ([]))) (v_operations))) (v_functions)))))
| ((Done (v_key)), (Family (v_read_template, v_write_template))) ->
(let (M.Module (v_constants, v_functions, v_types, v_operations)) = v_module in
(let v_read = (f_family_identity (v_read_template) (v_key)) in
(let v_write = (f_family_identity (v_write_template) (v_key)) in
(f_source_certificate (v_name) (v_predicate) (s_3) ([v_read_template; v_write_template]) (v_state) (v_value) (v_returned_state) (v_returned_value) (v_labels) (v_callback_tail) (v_invocation_labels) (v_invocation_tail) (v_bound) (v_read) (v_write) ((f_family_catalog (v_operations) (v_read_template) (v_write_template) (v_read) (v_write) (v_state))) (v_functions))))))
and (* state_run_evidence.bend:208 *)
f_source_key : t_RunSource -> M.t_Ty -> (M.t_Diagnostic, Base.text) Base.result_ =
fun v_source v_state ->
(match v_source with
| Builtin ->
(State.f_type_key (65536) ((State.TypeKey (v_state))))
| (Family (v_read, v_write)) ->
(State.f_type_key (65536) ((State.TypesKey ([v_state])))))
and (* state_run_evidence.bend:215 *)
f_signature_shape : M.t_Ty -> M.t_Predicate -> Base.text -> t_RunSource -> (int) list -> M.t_Module -> bool -> bool =
fun v_signature v_predicate v_name v_source v_bound v_module v_free_ok ->
(match v_signature with
| (M.FunctionTy (v_state, (M.FunctionTy ((M.FunctionTy (M.UnitTy, v_value, (M.EffectRow (v_labels, v_callback_tail)))), (M.ProductTy ((v_returned_state :: (v_returned_value :: [])))), (M.EffectRow (v_invocation_labels, v_invocation_tail)))), (M.EffectRow ([], M.ClosedRow)))) ->
(Base.bool_and (v_free_ok) ((f_key_certificate ((f_source_key (v_source) (v_state))) (v_source) (v_name) (v_predicate) (v_state) (v_value) (v_returned_state) (v_returned_value) (v_labels) (v_callback_tail) (v_invocation_labels) (v_invocation_tail) (v_bound) (v_module))))
| _ ->
false)
and (* state_run_evidence.bend:222 *)
f_signature_certificate : M.t_Ty -> M.t_Predicate -> Base.text -> t_RunSource -> (int) list -> M.t_Module -> bool =
fun v_signature v_predicate v_name v_source v_bound v_module ->
(f_signature_shape (v_signature) (v_predicate) (v_name) (v_source) (v_bound) (v_module) ((f_free_within ((T.f_free (v_signature))) (v_bound))))
and (* state_run_evidence.bend:228 *)
f_certify_run : M.t_Predicate -> C.t_Evidence -> (int) list -> M.t_Module -> bool =
fun v_predicate v_evidence v_bound v_module ->
(match (v_predicate, v_evidence) with
| ((M.AssociatedPredicate (v_member, [], v_left, v_right, v_result, v_invocation)), (C.SelectedFunction (v_name, v_signature))) ->
(Base.bool_and ((M.f_name_equal (v_member) (s_2))) ((f_signature_certificate (v_signature) (v_predicate) (v_name) (Builtin) (v_bound) (v_module))))
| ((M.AssociatedPredicate (v_member, (v_read :: (v_write :: [])), v_left, v_right, v_result, v_invocation)), (C.SelectedFunction (v_name, v_signature))) ->
(Base.bool_and ((M.f_name_equal (v_member) (s_3))) ((f_signature_certificate (v_signature) (v_predicate) (v_name) ((Family (v_read, v_write))) (v_bound) (v_module))))
| (_, _) ->
false)
