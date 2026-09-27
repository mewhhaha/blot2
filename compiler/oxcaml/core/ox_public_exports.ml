(* Native semantic port of compiler/public_exports.bend.

   Source SHA-256: 31e714805f0d88fc38b97287e325a772712ffca5f39b8b3665817ea6c74422b7

   Ownership/type arguments are erased; value types are checked by OCaml.

   No Bend interpreter or generated C/JavaScript is linked. *)

open Base

module M = Ox_model

module I = Ox_infer

module Index = Ox_index

module Rows = Ox_effect_rows

type t_Selection =
  | Candidates
  | Resolved
and t_ConstantSelection =
  | ConstantSelection of (M.t_Constant) list * (M.t_Function) list
and t_CheckedConstantSelection =
  | CheckedConstantSelection of (M.t_CheckedConstant) list * (M.t_CheckedFunction) list

let s_0 = Base.text_of_utf8 "$public:"

let s_1 = Base.text_of_utf8 "internal_error"

let s_2 = Base.text_of_utf8 "missing inferred type while selecting public entry points"

let s_3 = Base.text_of_utf8 "$argument"

let s_4 = Base.text_of_utf8 "missing inferred binding for public callable value"

let rec (* public_exports.bend:14 *)
f_export_name : Base.text -> Base.text =
fun v_name ->
(Base.bool_pick ((Base.string_starts_with (v_name) (s_0))) ((Base.string_drop (v_name) (8))) (v_name))
and (* public_exports.bend:17 *)
f_scalar : M.t_Ty -> bool =
fun v_ty ->
(match v_ty with
| M.UnitTy ->
true
| M.U32Ty ->
true
| M.F32Ty ->
true
| M.BoolTy ->
true
| _ ->
false)
and (* public_exports.bend:30 *)
f_value : M.t_Ty -> bool =
fun v_ty ->
(match v_ty with
| (M.ArrayTy (M.U32Ty)) ->
true
| (M.ArrayTy (M.F32Ty)) ->
true
| v_other ->
(f_scalar (v_other)))
and (* public_exports.bend:39 *)
f_callback_row : M.t_EffectRow -> bool =
fun v_row ->
(match v_row with
| (M.EffectRow ((v_identity :: []), M.ClosedRow)) ->
(M.f_is_foreign (v_identity))
| _ ->
false)
and (* public_exports.bend:48 *)
f_result : M.t_Ty -> t_Selection -> bool =
fun v_ty v_selection ->
(match (v_ty, v_selection) with
| ((M.VariableTy (v_index)), Candidates) ->
true
| ((M.ParameterTy (v_index)), Candidates) ->
true
| ((M.ArrayTy ((M.VariableTy (v_index)))), Candidates) ->
true
| ((M.ArrayTy ((M.ParameterTy (v_index)))), Candidates) ->
true
| (v_other, _) ->
(f_value (v_other)))
and (* public_exports.bend:61 *)
f_parameter : M.t_Ty -> t_Selection -> bool =
fun v_ty v_selection ->
(match (v_ty, v_selection) with
| ((M.FunctionTy (v_input, v_output, v_row)), Resolved) ->
(Base.bool_and ((f_callback_row (v_row))) ((Base.bool_and ((f_value (v_input))) ((f_value (v_output))))))
| ((M.FunctionTy (v_input, v_output, v_row)), Candidates) ->
(Base.bool_and ((f_result (v_input) (Candidates))) ((f_result (v_output) (Candidates))))
| (v_other, v_mode) ->
(f_result (v_other) (v_mode)))
and (* public_exports.bend:70 *)
f_foreign_operations : (M.t_TypeId) list -> bool =
fun v_operations ->
(match v_operations with
| [] ->
true
| (v_head :: v_tail) ->
(Base.bool_and ((M.f_is_foreign (v_head))) ((f_foreign_operations (v_tail)))))
and (* public_exports.bend:77 *)
f_effects : M.t_Ty -> M.t_EffectRow -> t_Selection -> bool =
fun v_input v_row v_selection ->
(match (v_input, v_row, v_selection) with
| (_, _, Candidates) ->
true
| (_, (M.EffectRow ([], M.ClosedRow)), Resolved) ->
true
| ((M.FunctionTy (v_parameter, v_result, v_callback_effects)), (M.EffectRow (v_operations, M.ClosedRow)), Resolved) ->
(f_foreign_operations (v_operations))
| (_, _, _) ->
false)
and (* public_exports.bend:88 *)
f_callable : M.t_Ty -> t_Selection -> bool =
fun v_ty v_selection ->
(match v_ty with
| (M.FunctionTy (v_input, v_output, v_row)) ->
(Base.bool_and ((f_parameter (v_input) (v_selection))) ((Base.bool_and ((f_result (v_output) (v_selection))) ((f_effects (v_input) (v_row) (v_selection))))))
| _ ->
false)
and (* public_exports.bend:95 *)
f_binding_index : (I.t_Binding) list -> (I.t_Binding) Base.map -> (I.t_Binding) Base.map =
fun v_bindings v_index ->
(match v_bindings with
| [] ->
v_index
| ((I.Binding (v_name, v_ty, v_variables, v_predicates)) :: v_tail) ->
(f_binding_index (v_tail) ((Base.map_set (v_index) (v_name) ((I.Binding (v_name, v_ty, v_variables, v_predicates)))))))
and (* public_exports.bend:102 *)
f_inferred : (I.t_Binding) option -> Base.text -> (M.t_Diagnostic, M.t_Ty) Base.result_ =
fun v_found v_name ->
(match v_found with
| (Some ((I.Binding (v_name, v_ty, v_variables, v_predicates)))) ->
(Done (v_ty))
| None ->
(Fail ((M.Diagnostic (s_1, v_name, s_2)))))
and (* public_exports.bend:111 *)
f_preliminary_function_export : M.t_Ty -> t_Selection -> bool =
fun v_ty v_selection ->
(match v_selection with
| Candidates ->
(f_callable (v_ty) (Candidates))
| Resolved ->
true)
and (* public_exports.bend:118 *)
f_functions : (M.t_Function) list -> (I.t_Binding) Base.map -> t_Selection -> (M.t_Diagnostic, (M.t_Function) list) Base.result_ =
fun v_pending v_types v_selection ->
(match v_pending with
| [] ->
(Done ([]))
| ((M.Function (v_name, true, v_argument, v_input, v_output, v_body)) :: v_tail) ->
(match (f_inferred ((Index.f_find (v_types) (v_name))) (v_name)) with
| Fail __error -> Fail __error
| Done v_ty ->
(match (f_functions (v_tail) (v_types) (v_selection)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done (((M.Function (v_name, (f_preliminary_function_export (v_ty) (v_selection)), v_argument, v_input, v_output, v_body)) :: v_rest)))))
| (v_head :: v_tail) ->
(match (f_functions (v_tail) (v_types) (v_selection)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done ((v_head :: v_rest)))))
and (* public_exports.bend:132 *)
f_constant_type : M.t_Ty -> t_Selection -> bool =
fun v_ty v_selection ->
(match (v_ty, v_selection) with
| ((M.VariableTy (v_index)), Candidates) ->
true
| ((M.ParameterTy (v_index)), Candidates) ->
true
| ((M.FunctionTy (v_input, v_output, v_effects)), Candidates) ->
(f_callable ((M.FunctionTy (v_input, v_output, v_effects))) (Candidates))
| (v_other, _) ->
(f_scalar (v_other)))
and (* public_exports.bend:145 *)
f_select_constant : M.t_Ty -> t_Selection -> M.t_Constant -> t_ConstantSelection -> t_ConstantSelection =
fun v_ty v_selection v_constant v_rest ->
(match (v_ty, v_selection) with
| ((M.FunctionTy (v_input, v_output, v_effects)), Resolved) ->
(let (M.Constant (v_name, v_exported, v_annotation, v_expression)) = v_constant in
(let (ConstantSelection (v_constants, v_wrappers)) = v_rest in
(let v_supported = (f_callable ((M.FunctionTy (v_input, v_output, v_effects))) (Resolved)) in
(let v_wrapper = (M.Function ((Base.string_append s_0 v_name), true, s_3, (Some (v_input)), (Some (v_output)), (M.ApplyExpr ((M.ConstantExpr (v_name)), (M.LocalExpr (s_3)))))) in
(ConstantSelection (((M.Constant (v_name, false, v_annotation, v_expression)) :: v_constants), (Base.bool_pick (v_supported) ((v_wrapper :: v_wrappers)) (v_wrappers))))))))
| (v_other, v_mode) ->
(let (M.Constant (v_name, v_exported, v_annotation, v_expression)) = v_constant in
(let (ConstantSelection (v_constants, v_wrappers)) = v_rest in
(ConstantSelection (((M.Constant (v_name, (f_constant_type (v_other) (v_mode)), v_annotation, v_expression)) :: v_constants), v_wrappers)))))
and (* public_exports.bend:158 *)
f_prepend_constant : M.t_Constant -> t_ConstantSelection -> t_ConstantSelection =
fun v_constant v_rest ->
(let (ConstantSelection (v_constants, v_wrappers)) = v_rest in
(ConstantSelection ((v_constant :: v_constants), v_wrappers)))
and (* public_exports.bend:162 *)
f_constants : (M.t_Constant) list -> (I.t_Binding) Base.map -> t_Selection -> (M.t_Diagnostic, t_ConstantSelection) Base.result_ =
fun v_pending v_types v_selection ->
(match v_pending with
| [] ->
(Done ((ConstantSelection ([], []))))
| ((M.Constant (v_name, true, v_annotation, v_expression)) :: v_tail) ->
(match (f_inferred ((Index.f_find (v_types) (v_name))) (v_name)) with
| Fail __error -> Fail __error
| Done v_ty ->
(match (f_constants (v_tail) (v_types) (v_selection)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done ((f_select_constant (v_ty) (v_selection) ((M.Constant (v_name, true, v_annotation, v_expression))) (v_rest))))))
| (v_head :: v_tail) ->
(match (f_constants (v_tail) (v_types) (v_selection)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done ((f_prepend_constant (v_head) (v_rest))))))
and (* public_exports.bend:176 *)
f_selected_module : t_ConstantSelection -> (M.t_Function) list -> (M.t_DataType) list -> (M.t_Operation) list -> M.t_Module =
fun v_constants v_functions v_types v_operations ->
(let (ConstantSelection (v_values, v_wrappers)) = v_constants in
(M.Module (v_values, (Base.list_append (v_functions) (v_wrappers)), v_types, v_operations)))
and (* public_exports.bend:180 *)
f_wrapper_names : (M.t_Function) list -> (Base.text) list =
fun v_functions ->
(match v_functions with
| [] ->
[]
| ((M.Function (v_name, v_exported, v_parameter, v_input, v_output, v_body)) :: v_tail) ->
(let v_rest = (f_wrapper_names (v_tail)) in
(Base.bool_pick ((Base.string_starts_with (v_name) (s_0))) ((v_name :: v_rest)) (v_rest))))
and (* public_exports.bend:188 *)
f_wrapper_binding : (I.t_Binding) option -> (I.t_Binding) option -> Base.text -> (M.t_Diagnostic, (I.t_Binding) list) Base.result_ =
fun v_existing v_original v_name ->
(match (v_existing, v_original) with
| ((Some (v_binding)), _) ->
(Done ([]))
| (None, (Some ((I.Binding (v_source, v_ty, v_variables, v_predicates))))) ->
(Done ([(I.Binding (v_name, v_ty, v_variables, v_predicates))]))
| (None, None) ->
(Fail ((M.Diagnostic (s_1, v_name, s_4)))))
and (* public_exports.bend:197 *)
f_wrapper_bindings : (Base.text) list -> (I.t_Binding) Base.map -> (I.t_Binding) list -> (M.t_Diagnostic, (I.t_Binding) list) Base.result_ =
fun v_names v_index v_bindings ->
(match v_names with
| [] ->
(Done (v_bindings))
| (v_name :: v_tail) ->
(match (f_wrapper_binding ((Index.f_find (v_index) (v_name))) ((Index.f_find (v_index) ((f_export_name (v_name))))) (v_name)) with
| Fail __error -> Fail __error
| Done v_alias ->
(match (f_wrapper_bindings (v_tail) (v_index) (v_bindings)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done ((Base.list_append (v_alias) (v_rest)))))))
and (* public_exports.bend:207 *)
f_add_wrapper_bindings : (Base.text) list -> (I.t_Binding) list -> (M.t_Diagnostic, (I.t_Binding) list) Base.result_ =
fun v_names v_bindings ->
(match v_names with
| [] ->
(Done (v_bindings))
| (v_head :: v_tail) ->
(f_wrapper_bindings ((v_head :: v_tail)) ((f_binding_index (v_bindings) (MTip))) (v_bindings)))
and (* public_exports.bend:214 *)
f_generated_bindings : M.t_Module -> (I.t_Binding) list -> (M.t_Diagnostic, (I.t_Binding) list) Base.result_ =
fun v_module v_bindings ->
(let (M.Module (v_constants, v_functions, v_types, v_operations)) = v_module in
(f_add_wrapper_bindings ((f_wrapper_names (v_functions))) (v_bindings)))
and (* public_exports.bend:218 *)
f_select : M.t_Module -> (I.t_Binding) list -> t_Selection -> (M.t_Diagnostic, M.t_Module) Base.result_ =
fun v_module v_bindings v_selection ->
(let (M.Module (v_cs, v_fs, v_types, v_operations)) = v_module in
(let v_inferred = (f_binding_index (v_bindings) (MTip)) in
(match (f_functions (v_fs) (v_inferred) (v_selection)) with
| Fail __error -> Fail __error
| Done v_selected_functions ->
(match (f_constants (v_cs) (v_inferred) (v_selection)) with
| Fail __error -> Fail __error
| Done v_selected_constants ->
(Done ((f_selected_module (v_selected_constants) (v_selected_functions) (v_types) (v_operations))))))))
and (* public_exports.bend:232 *)
f_checked_wrapper : Base.text -> M.t_Ty -> M.t_Ty -> (int) list -> M.t_EffectRow -> M.t_CheckedFunction =
fun v_name v_input v_output v_variables v_row ->
(let v_exported = (Base.string_append s_0 v_name) in
(let v_function = (M.Function (v_exported, true, s_3, (Some (v_input)), (Some (v_output)), (M.ApplyExpr ((M.ConstantExpr (v_name)), (M.LocalExpr (s_3)))))) in
(M.CheckedFunction (v_function, (M.Signature (v_exported, v_input, v_output, v_variables, v_row)), (Rows.f_metadata ((Rows.f_operation_set (v_row))))))))
and (* public_exports.bend:237 *)
f_checked_functions : (M.t_CheckedFunction) list -> (M.t_CheckedFunction) list =
fun v_functions ->
(match v_functions with
| [] ->
[]
| ((M.CheckedFunction ((M.Function (v_name, true, v_argument, v_input, v_output, v_body)), (M.Signature (v_declared, v_p, v_r, v_variables, v_row)), v_effects)) :: v_tail) ->
((M.CheckedFunction ((M.Function (v_name, (f_callable ((M.FunctionTy (v_p, v_r, v_row))) (Resolved)), v_argument, v_input, v_output, v_body)), (M.Signature (v_declared, v_p, v_r, v_variables, v_row)), v_effects)) :: (f_checked_functions (v_tail)))
| (v_head :: v_tail) ->
(v_head :: (f_checked_functions (v_tail))))
and (* public_exports.bend:246 *)
f_prepend_checked_constant : M.t_CheckedConstant -> t_CheckedConstantSelection -> t_CheckedConstantSelection =
fun v_constant v_rest ->
(let (CheckedConstantSelection (v_constants, v_wrappers)) = v_rest in
(CheckedConstantSelection ((v_constant :: v_constants), v_wrappers)))
and (* public_exports.bend:250 *)
f_select_checked_constant : M.t_Ty -> Base.text -> (M.t_Ty) option -> M.t_Expr -> (int) list -> t_CheckedConstantSelection -> t_CheckedConstantSelection =
fun v_ty v_name v_annotation v_expression v_variables v_rest ->
(match v_ty with
| (M.FunctionTy (v_input, v_output, v_row)) ->
(let (CheckedConstantSelection (v_constants, v_wrappers)) = v_rest in
(let v_supported = (f_callable ((M.FunctionTy (v_input, v_output, v_row))) (Resolved)) in
(let v_wrapper = (f_checked_wrapper (v_name) (v_input) (v_output) (v_variables) (v_row)) in
(CheckedConstantSelection (((M.CheckedConstant ((M.Constant (v_name, false, v_annotation, v_expression)), (M.FunctionTy (v_input, v_output, v_row)), v_variables)) :: v_constants), (Base.bool_pick (v_supported) ((v_wrapper :: v_wrappers)) (v_wrappers)))))))
| v_other ->
(f_prepend_checked_constant ((M.CheckedConstant ((M.Constant (v_name, (f_constant_type (v_other) (Resolved)), v_annotation, v_expression)), v_other, v_variables))) (v_rest)))
and (* public_exports.bend:260 *)
f_checked_constants : (M.t_CheckedConstant) list -> t_CheckedConstantSelection =
fun v_constants ->
(match v_constants with
| [] ->
(CheckedConstantSelection ([], []))
| ((M.CheckedConstant ((M.Constant (v_name, true, v_annotation, v_expression)), v_ty, v_variables)) :: v_tail) ->
(f_select_checked_constant (v_ty) (v_name) (v_annotation) (v_expression) (v_variables) ((f_checked_constants (v_tail))))
| (v_head :: v_tail) ->
(f_prepend_checked_constant (v_head) ((f_checked_constants (v_tail)))))
and (* public_exports.bend:269 *)
f_selected_checked_module : t_CheckedConstantSelection -> (M.t_CheckedFunction) list -> (M.t_DataType) list -> (M.t_Operation) list -> M.t_CheckedModule =
fun v_constants v_functions v_types v_operations ->
(let (CheckedConstantSelection (v_values, v_wrappers)) = v_constants in
(M.CheckedModule (v_values, (Base.list_append (v_functions) (v_wrappers)), v_types, v_operations)))
and (* public_exports.bend:273 *)
f_select_checked : M.t_CheckedModule -> M.t_CheckedModule =
fun v_module ->
(let (M.CheckedModule (v_constants, v_functions, v_types, v_operations)) = v_module in
(f_selected_checked_module ((f_checked_constants (v_constants))) ((f_checked_functions (v_functions))) (v_types) (v_operations)))
and (* public_exports.bend:277 *)
f_unchecked_functions : (M.t_CheckedFunction) list -> (M.t_Function) list =
fun v_functions ->
(match v_functions with
| [] ->
[]
| ((M.CheckedFunction (v_function, v_signature, v_effects)) :: v_tail) ->
(v_function :: (f_unchecked_functions (v_tail))))
and (* public_exports.bend:284 *)
f_unchecked_constants : (M.t_CheckedConstant) list -> (M.t_Constant) list =
fun v_constants ->
(match v_constants with
| [] ->
[]
| ((M.CheckedConstant (v_constant, v_ty, v_variables)) :: v_tail) ->
(v_constant :: (f_unchecked_constants (v_tail))))
and (* public_exports.bend:291 *)
f_unchecked_module : M.t_CheckedModule -> M.t_Module =
fun v_module ->
(let (M.CheckedModule (v_constants, v_functions, v_types, v_operations)) = v_module in
(M.Module ((f_unchecked_constants (v_constants)), (f_unchecked_functions (v_functions)), v_types, v_operations)))
