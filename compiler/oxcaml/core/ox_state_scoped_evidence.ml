(* Native semantic port of compiler/state_scoped_evidence.bend.

   Source SHA-256: e44094a08c45fe34225f95e9042a1a204c54c26b96d6c8cb1ef1b66a9f162018

   Ownership/type arguments are erased; value types are checked by OCaml.

   No Bend interpreter or generated C/JavaScript is linked. *)

open Base

module M = Ox_model

module C = Ox_constraints

module T = Ox_types

module State = Ox_state_specialize

module RunEvidence = Ox_state_run_evidence

module Compare = Ox_core_compare

module Rows = Ox_effect_rows

type t_Source =
  | BuiltinReader
  | BuiltinWriter
  | FamilyReader of M.t_TypeId
  | FamilyWriter of M.t_TypeId

let s_0 = Base.text_of_utf8 "@state.reader"

let s_1 = Base.text_of_utf8 "@state.writer"

let s_2 = Base.text_of_utf8 "@effect.reader"

let s_3 = Base.text_of_utf8 "@effect.writer"

let rec (* state_scoped_evidence.bend:20 *)
f_operation_match : bool -> bool -> M.t_Operation -> M.t_Operation -> bool =
fun v_same v_found v_actual v_expected ->
(match (v_same, v_found) with
| (false, _) ->
true
| (true, false) ->
(RunEvidence.f_same_operation (v_actual) (v_expected))
| (true, true) ->
false)
and (* state_scoped_evidence.bend:29 *)
f_exact_operation : (M.t_Operation) list -> M.t_TypeId -> M.t_Operation -> bool -> bool =
fun v_operations v_wanted v_expected v_found ->
(match v_operations with
| [] ->
v_found
| ((M.Operation (v_identity, v_parameter, v_result)) :: v_tail) ->
(let v_same = (M.f_type_id_equal (v_identity) (v_wanted)) in
(let v_valid = (f_operation_match (v_same) (v_found) ((M.Operation (v_identity, v_parameter, v_result))) (v_expected)) in
(Base.bool_and (v_valid) ((f_exact_operation (v_tail) (v_wanted) (v_expected) ((Base.bool_or (v_found) (v_same))))))))
| ((M.OperationTemplate (v_identity, v_parameters, v_parameter, v_result)) :: v_tail) ->
(Base.bool_and ((Base.bool_not ((M.f_type_id_equal (v_identity) (v_wanted))))) ((f_exact_operation (v_tail) (v_wanted) (v_expected) (v_found))))
| ((M.OperationInstance (v_template, v_arguments)) :: v_tail) ->
(Base.bool_and ((Base.bool_not ((M.f_type_id_equal (v_template) (v_wanted))))) ((f_exact_operation (v_tail) (v_wanted) (v_expected) (v_found)))))
and (* state_scoped_evidence.bend:42 *)
f_template_match : bool -> bool -> M.t_Operation -> M.t_Operation -> bool =
fun v_same v_found v_actual v_expected ->
(match (v_same, v_found) with
| (false, _) ->
true
| (true, false) ->
(RunEvidence.f_same_operation (v_actual) (v_expected))
| (true, true) ->
false)
and (* state_scoped_evidence.bend:51 *)
f_exact_template : (M.t_Operation) list -> M.t_TypeId -> M.t_Operation -> bool -> bool =
fun v_operations v_wanted v_expected v_found ->
(match v_operations with
| [] ->
v_found
| ((M.OperationTemplate (v_identity, v_parameters, v_parameter, v_result)) :: v_tail) ->
(let v_same = (M.f_type_id_equal (v_identity) (v_wanted)) in
(let v_valid = (f_template_match (v_same) (v_found) ((M.OperationTemplate (v_identity, v_parameters, v_parameter, v_result))) (v_expected)) in
(Base.bool_and (v_valid) ((f_exact_template (v_tail) (v_wanted) (v_expected) ((Base.bool_or (v_found) (v_same))))))))
| ((M.Operation (v_identity, v_parameter, v_result)) :: v_tail) ->
(Base.bool_and ((Base.bool_not ((M.f_type_id_equal (v_identity) (v_wanted))))) ((f_exact_template (v_tail) (v_wanted) (v_expected) (v_found))))
| ((M.OperationInstance (v_template, v_arguments)) :: v_tail) ->
(Base.bool_and ((Base.bool_not ((M.f_type_id_equal (v_template) (v_wanted))))) ((f_exact_template (v_tail) (v_wanted) (v_expected) (v_found)))))
and (* state_scoped_evidence.bend:64 *)
f_function_name : M.t_Function -> Base.text =
fun v_function ->
(let (M.Function (v_name, v_exported, v_parameter, v_p, v_r, v_body)) = v_function in
v_name)
and (* state_scoped_evidence.bend:68 *)
f_exact_body : M.t_Function -> State.t_Request -> M.t_TypeId -> M.t_TypeId -> Base.text -> bool =
fun v_function v_request v_read v_write v_name ->
(match v_function with
| (M.Function (v_found, v_exported, v_parameter, v_p, v_r, (M.LambdaExpr (v_identity, v_inner_parameter, v_ip, v_ir, v_body)))) ->
(Compare.f_compare (65536) ([(Compare.FunctionPair ((M.Function (v_found, v_exported, v_parameter, v_p, v_r, (M.LambdaExpr (v_identity, v_inner_parameter, v_ip, v_ir, v_body)))), (State.f_function_for (v_request) (v_read) (v_write) (v_name) (v_identity))))]) (true))
| _ ->
false)
and (* state_scoped_evidence.bend:75 *)
f_named_match : bool -> bool -> M.t_Function -> State.t_Request -> M.t_TypeId -> M.t_TypeId -> Base.text -> bool =
fun v_same v_found v_function v_request v_read v_write v_name ->
(match (v_same, v_found) with
| (false, _) ->
true
| (true, false) ->
(f_exact_body (v_function) (v_request) (v_read) (v_write) (v_name))
| (true, true) ->
false)
and (* state_scoped_evidence.bend:84 *)
f_exact_named : (M.t_Function) list -> Base.text -> State.t_Request -> M.t_TypeId -> M.t_TypeId -> bool -> bool =
fun v_functions v_name v_request v_read v_write v_found ->
(match v_functions with
| [] ->
v_found
| (v_head :: v_tail) ->
(let v_same = (M.f_name_equal ((f_function_name (v_head))) (v_name)) in
(let v_valid = (f_named_match (v_same) (v_found) (v_head) (v_request) (v_read) (v_write) (v_name)) in
(Base.bool_and (v_valid) ((f_exact_named (v_tail) (v_name) (v_request) (v_read) (v_write) ((Base.bool_or (v_found) (v_same)))))))))
and (* state_scoped_evidence.bend:93 *)
f_source_key : t_Source -> M.t_Ty -> (M.t_Diagnostic, Base.text) Base.result_ =
fun v_source v_state ->
(match v_source with
| BuiltinReader ->
(State.f_type_key (65536) ((State.TypeKey (v_state))))
| BuiltinWriter ->
(State.f_type_key (65536) ((State.TypeKey (v_state))))
| (FamilyReader (v_template)) ->
(State.f_type_key (65536) ((State.TypesKey ([v_state]))))
| (FamilyWriter (v_template)) ->
(State.f_type_key (65536) ((State.TypesKey ([v_state])))))
and (* state_scoped_evidence.bend:104 *)
f_builtin_catalog : (M.t_Operation) list -> M.t_TypeId -> M.t_TypeId -> M.t_Ty -> bool =
fun v_operations v_read v_write v_state ->
(Base.bool_and ((Base.bool_not ((M.f_type_id_equal (v_read) (v_write))))) ((Base.bool_and ((f_exact_operation (v_operations) (v_read) ((M.Operation (v_read, M.UnitTy, v_state))) (false))) ((f_exact_operation (v_operations) (v_write) ((M.Operation (v_write, v_state, M.UnitTy))) (false))))))
and (* state_scoped_evidence.bend:107 *)
f_family_reader_catalog : (M.t_Operation) list -> M.t_TypeId -> M.t_TypeId -> M.t_Ty -> bool =
fun v_operations v_template v_read v_state ->
(Base.bool_and ((f_exact_template (v_operations) (v_template) ((M.OperationTemplate (v_template, 1, M.UnitTy, (M.ParameterTy (0))))) (false))) ((f_exact_operation (v_operations) (v_read) ((M.Operation (v_read, M.UnitTy, v_state))) (false))))
and (* state_scoped_evidence.bend:110 *)
f_family_writer_catalog : (M.t_Operation) list -> M.t_TypeId -> M.t_TypeId -> M.t_Ty -> bool =
fun v_operations v_template v_write v_state ->
(Base.bool_and ((f_exact_template (v_operations) (v_template) ((M.OperationTemplate (v_template, 1, (M.ParameterTy (0)), M.UnitTy))) (false))) ((f_exact_operation (v_operations) (v_write) ((M.Operation (v_write, v_state, M.UnitTy))) (false))))
and (* state_scoped_evidence.bend:113 *)
f_body_if_catalog : bool -> (M.t_Function) list -> Base.text -> State.t_Request -> M.t_TypeId -> M.t_TypeId -> bool =
fun v_valid v_functions v_name v_request v_read v_write ->
(match v_valid with
| false ->
false
| true ->
(f_exact_named (v_functions) (v_name) (v_request) (v_read) (v_write) (false)))
and (* state_scoped_evidence.bend:120 *)
f_source_catalog_body : t_Source -> Base.text -> M.t_Ty -> M.t_TypeId -> Base.text -> M.t_Module -> bool =
fun v_source v_key v_state v_operation v_name v_module ->
(match (v_source, v_module) with
| (BuiltinReader, (M.Module (v_constants, v_functions, v_types, v_operations))) ->
(let v_read = (State.f_read_identity (v_key)) in
(let v_write = (State.f_write_identity (v_key)) in
(f_body_if_catalog ((f_builtin_catalog (v_operations) (v_read) (v_write) (v_state))) (v_functions) (v_name) (State.Reader) (v_read) (v_write))))
| (BuiltinWriter, (M.Module (v_constants, v_functions, v_types, v_operations))) ->
(let v_read = (State.f_read_identity (v_key)) in
(let v_write = (State.f_write_identity (v_key)) in
(f_body_if_catalog ((f_builtin_catalog (v_operations) (v_read) (v_write) (v_state))) (v_functions) (v_name) (State.Writer) (v_read) (v_write))))
| ((FamilyReader (v_template)), (M.Module (v_constants, v_functions, v_types, v_operations))) ->
(f_body_if_catalog ((f_family_reader_catalog (v_operations) (v_template) (v_operation) (v_state))) (v_functions) (v_name) (State.Reader) (v_operation) (v_operation))
| ((FamilyWriter (v_template)), (M.Module (v_constants, v_functions, v_types, v_operations))) ->
(f_body_if_catalog ((f_family_writer_catalog (v_operations) (v_template) (v_operation) (v_state))) (v_functions) (v_name) (State.Writer) (v_operation) (v_operation)))
and (* state_scoped_evidence.bend:135 *)
f_implementation_shape : t_Source -> M.t_Ty -> M.t_Ty -> M.t_EffectRow -> bool =
fun v_source v_implementation v_state v_invocation ->
(match (v_source, v_implementation) with
| (BuiltinReader, (M.FunctionTy (v_parameter, v_result, v_effects))) ->
(Base.bool_and ((RunEvidence.f_same_ty (v_parameter) (M.UnitTy))) ((Base.bool_and ((RunEvidence.f_same_ty (v_result) (v_state))) ((RunEvidence.f_same_row (v_effects) (v_invocation))))))
| ((FamilyReader (v_template)), (M.FunctionTy (v_parameter, v_result, v_effects))) ->
(Base.bool_and ((RunEvidence.f_same_ty (v_parameter) (M.UnitTy))) ((Base.bool_and ((RunEvidence.f_same_ty (v_result) (v_state))) ((RunEvidence.f_same_row (v_effects) (v_invocation))))))
| (BuiltinWriter, (M.FunctionTy (v_parameter, v_result, v_effects))) ->
(Base.bool_and ((RunEvidence.f_same_ty (v_parameter) (v_state))) ((Base.bool_and ((RunEvidence.f_same_ty (v_result) (M.UnitTy))) ((RunEvidence.f_same_row (v_effects) (v_invocation))))))
| ((FamilyWriter (v_template)), (M.FunctionTy (v_parameter, v_result, v_effects))) ->
(Base.bool_and ((RunEvidence.f_same_ty (v_parameter) (v_state))) ((Base.bool_and ((RunEvidence.f_same_ty (v_result) (M.UnitTy))) ((RunEvidence.f_same_row (v_effects) (v_invocation))))))
| (_, _) ->
false)
and (* state_scoped_evidence.bend:148 *)
f_source_member : t_Source -> Base.text =
fun v_source ->
(match v_source with
| BuiltinReader ->
s_0
| BuiltinWriter ->
s_1
| (FamilyReader (v_template)) ->
s_2
| (FamilyWriter (v_template)) ->
s_3)
and (* state_scoped_evidence.bend:159 *)
f_source_templates : t_Source -> (M.t_TypeId) list =
fun v_source ->
(match v_source with
| BuiltinReader ->
[]
| BuiltinWriter ->
[]
| (FamilyReader (v_template)) ->
[v_template]
| (FamilyWriter (v_template)) ->
[v_template])
and (* state_scoped_evidence.bend:170 *)
f_source_checked : bool -> t_Source -> Base.text -> M.t_Ty -> M.t_TypeId -> Base.text -> M.t_Module -> bool =
fun v_eligible v_source v_key v_state v_operation v_name v_module ->
(match v_eligible with
| false ->
false
| true ->
(f_source_catalog_body (v_source) (v_key) (v_state) (v_operation) (v_name) (v_module)))
and (* state_scoped_evidence.bend:179 *)
f_same_callback : M.t_Ty -> M.t_Ty -> bool =
fun v_left v_right ->
(match (v_left, v_right) with
| ((M.FunctionTy (v_ap, v_ar, v_ae)), (M.FunctionTy (v_bp, v_br, v_be))) ->
(Base.bool_and ((RunEvidence.f_same_ty (v_ap) (v_bp))) ((Base.bool_and ((RunEvidence.f_same_ty (v_ar) (v_br))) ((RunEvidence.f_same_row (v_ae) (v_be))))))
| (_, _) ->
false)
and (* state_scoped_evidence.bend:186 *)
f_same_scoped_predicate : M.t_Predicate -> M.t_Predicate -> bool =
fun v_left v_right ->
(match (v_left, v_right) with
| ((M.AssociatedPredicate (v_am, v_at, v_al, (M.ProductTy ((v_ai :: (v_aa :: [])))), v_av, v_ae)), (M.AssociatedPredicate (v_bm, v_bt, v_bl, (M.ProductTy ((v_bi :: (v_ba :: [])))), v_bv, v_be))) ->
(Base.bool_and ((Compare.f_compare (65536) ([(Compare.PredicatePair ((M.AssociatedPredicate (v_am, v_at, v_al, M.UnitTy, v_av, (Rows.f_canonical (v_ae)))), (M.AssociatedPredicate (v_bm, v_bt, v_bl, M.UnitTy, v_bv, (Rows.f_canonical (v_be))))))]) (true))) ((Base.bool_and ((f_same_callback (v_ai) (v_bi))) ((f_same_callback (v_aa) (v_ba))))))
| (_, _) ->
false)
and (* state_scoped_evidence.bend:196 *)
f_source_certificate : t_Source -> M.t_Predicate -> Base.text -> Base.text -> M.t_Ty -> M.t_Ty -> M.t_Ty -> M.t_Ty -> M.t_Ty -> (M.t_TypeId) list -> M.t_RowTail -> (M.t_TypeId) list -> M.t_RowTail -> (int) list -> M.t_TypeId -> M.t_Module -> bool =
fun v_source v_predicate v_name v_key v_witness v_state v_implementation v_action v_result v_action_labels v_action_tail v_invocation_labels v_invocation_tail v_bound v_operation v_module ->
(let v_invocation = (M.EffectRow (v_invocation_labels, v_invocation_tail)) in
(let v_expected = (M.AssociatedPredicate ((f_source_member (v_source)), (f_source_templates (v_source)), v_witness, (M.ProductTy ([v_implementation; v_action])), v_result, v_invocation)) in
(let v_callback = (M.EffectRow (v_action_labels, v_action_tail)) in
(let v_expected_callback = (M.EffectRow ((v_operation :: v_invocation_labels), v_invocation_tail)) in
(let v_valid = (Base.bool_and ((Base.bool_and ((RunEvidence.f_admissible_tail (v_invocation_tail) (v_bound))) ((RunEvidence.f_admissible_result_type (65536) ([v_result]) (v_bound))))) ((Base.bool_and ((Base.bool_and ((f_implementation_shape (v_source) (v_implementation) (v_state) (v_invocation))) ((RunEvidence.f_same_row (v_callback) (v_expected_callback))))) ((f_same_scoped_predicate (v_predicate) (v_expected)))))) in
(f_source_checked (v_valid) (v_source) (v_key) (v_state) (v_operation) (v_name) (v_module)))))))
and (* state_scoped_evidence.bend:210 *)
f_key_certificate : (M.t_Diagnostic, Base.text) Base.result_ -> t_Source -> M.t_Predicate -> Base.text -> M.t_Ty -> M.t_Ty -> M.t_Ty -> M.t_Ty -> M.t_Ty -> (M.t_TypeId) list -> M.t_RowTail -> (M.t_TypeId) list -> M.t_RowTail -> (int) list -> M.t_Module -> bool =
fun v_found v_source v_predicate v_name v_witness v_state v_implementation v_action v_result v_action_labels v_action_tail v_invocation_labels v_invocation_tail v_bound v_module ->
(match (v_found, v_source) with
| ((Fail (v_diagnostic)), _) ->
false
| ((Done (v_key)), BuiltinReader) ->
(f_source_certificate (BuiltinReader) (v_predicate) (v_name) (v_key) (v_witness) (v_state) (v_implementation) (v_action) (v_result) (v_action_labels) (v_action_tail) (v_invocation_labels) (v_invocation_tail) (v_bound) ((State.f_read_identity (v_key))) (v_module))
| ((Done (v_key)), BuiltinWriter) ->
(f_source_certificate (BuiltinWriter) (v_predicate) (v_name) (v_key) (v_witness) (v_state) (v_implementation) (v_action) (v_result) (v_action_labels) (v_action_tail) (v_invocation_labels) (v_invocation_tail) (v_bound) ((State.f_write_identity (v_key))) (v_module))
| ((Done (v_key)), (FamilyReader (v_template))) ->
(f_source_certificate ((FamilyReader (v_template))) (v_predicate) (v_name) (v_key) (v_witness) (v_state) (v_implementation) (v_action) (v_result) (v_action_labels) (v_action_tail) (v_invocation_labels) (v_invocation_tail) (v_bound) ((RunEvidence.f_family_identity (v_template) (v_key))) (v_module))
| ((Done (v_key)), (FamilyWriter (v_template))) ->
(f_source_certificate ((FamilyWriter (v_template))) (v_predicate) (v_name) (v_key) (v_witness) (v_state) (v_implementation) (v_action) (v_result) (v_action_labels) (v_action_tail) (v_invocation_labels) (v_invocation_tail) (v_bound) ((RunEvidence.f_family_identity (v_template) (v_key))) (v_module)))
and (* state_scoped_evidence.bend:223 *)
f_signature_shape : M.t_Ty -> M.t_Predicate -> Base.text -> t_Source -> (int) list -> M.t_Module -> bool -> bool =
fun v_signature v_predicate v_name v_source v_bound v_module v_free_ok ->
(match v_signature with
| (M.FunctionTy (v_witness, (M.FunctionTy ((M.ProductTy ((v_implementation :: ((M.FunctionTy (M.UnitTy, v_result, (M.EffectRow (v_action_labels, v_action_tail)))) :: [])))), v_returned, (M.EffectRow (v_invocation_labels, v_invocation_tail)))), (M.EffectRow ([], M.ClosedRow)))) ->
(let v_state = (State.f_witness (65536) (v_witness)) in
(Base.bool_and (v_free_ok) ((Base.bool_and ((RunEvidence.f_admissible_result_type (65536) ([v_witness]) (v_bound))) ((Base.bool_and ((RunEvidence.f_same_ty (v_result) (v_returned))) ((f_key_certificate ((f_source_key (v_source) (v_state))) (v_source) (v_predicate) (v_name) (v_witness) (v_state) (v_implementation) ((M.FunctionTy (M.UnitTy, v_result, (M.EffectRow (v_action_labels, v_action_tail))))) (v_result) (v_action_labels) (v_action_tail) (v_invocation_labels) (v_invocation_tail) (v_bound) (v_module)))))))))
| _ ->
false)
and (* state_scoped_evidence.bend:231 *)
f_signature_certificate : M.t_Ty -> M.t_Predicate -> Base.text -> t_Source -> (int) list -> M.t_Module -> bool =
fun v_signature v_predicate v_name v_source v_bound v_module ->
(f_signature_shape (v_signature) (v_predicate) (v_name) (v_source) (v_bound) (v_module) ((RunEvidence.f_free_within ((T.f_free (v_signature))) (v_bound))))
and (* state_scoped_evidence.bend:234 *)
f_selected_member : bool -> M.t_Predicate -> C.t_Evidence -> t_Source -> (int) list -> M.t_Module -> bool =
fun v_valid v_predicate v_evidence v_source v_bound v_module ->
(match (v_valid, v_evidence) with
| (true, (C.SelectedFunction (v_name, v_signature))) ->
(f_signature_certificate (v_signature) (v_predicate) (v_name) (v_source) (v_bound) (v_module))
| (_, _) ->
false)
and (* state_scoped_evidence.bend:243 *)
f_certify_scoped : M.t_Predicate -> C.t_Evidence -> (int) list -> M.t_Module -> bool =
fun v_predicate v_evidence v_bound v_module ->
(match v_predicate with
| (M.AssociatedPredicate (v_member, [], v_left, v_right, v_result, v_invocation)) ->
(Base.bool_or ((f_selected_member ((M.f_name_equal (v_member) (s_0))) (v_predicate) (v_evidence) (BuiltinReader) (v_bound) (v_module))) ((f_selected_member ((M.f_name_equal (v_member) (s_1))) (v_predicate) (v_evidence) (BuiltinWriter) (v_bound) (v_module))))
| (M.AssociatedPredicate (v_member, (v_template :: []), v_left, v_right, v_result, v_invocation)) ->
(Base.bool_or ((f_selected_member ((M.f_name_equal (v_member) (s_2))) (v_predicate) (v_evidence) ((FamilyReader (v_template))) (v_bound) (v_module))) ((f_selected_member ((M.f_name_equal (v_member) (s_3))) (v_predicate) (v_evidence) ((FamilyWriter (v_template))) (v_bound) (v_module))))
| _ ->
false)
