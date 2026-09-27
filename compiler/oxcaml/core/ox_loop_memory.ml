(* Native semantic port of compiler/loop_memory.bend.

   Source SHA-256: 3cedffdccb14d6f6de5785c9a9e4e08020121917ec2c720775a257f5742d94cd

   Ownership/type arguments are erased; value types are checked by OCaml.

   No Bend interpreter or generated C/JavaScript is linked. *)

open Base

module M = Ox_model

let s_0 = Base.text_of_utf8 "lambda:"

let s_1 = Base.text_of_utf8 "fn:"

let rec (* loop_memory.bend:7 *)
f_foreign_only : (M.t_TypeId) list -> bool =
fun v_operations ->
(match v_operations with
| [] ->
true
| (v_head :: v_tail) ->
(Base.bool_and ((M.f_is_foreign (v_head))) ((f_foreign_only (v_tail)))))
and (* loop_memory.bend:14 *)
f_isolated : M.t_EffectRow -> bool =
fun v_effects ->
(match v_effects with
| (M.EffectRow (v_operations, M.ClosedRow)) ->
(f_foreign_only (v_operations))
| _ ->
false)
and (* loop_memory.bend:21 *)
f_add_if : bool -> Base.text -> Base.set -> Base.set =
fun v_safe v_key v_entries ->
(Base.bool_pick (v_safe) ((Base.set_add (v_entries) (v_key))) (v_entries))
and (* loop_memory.bend:26 *)
f_lambda_entries : int -> M.t_Expr -> M.t_Ty -> Base.set -> Base.set =
fun v_fuel v_expression v_ty v_entries ->
(match (v_fuel, v_expression, v_ty) with
| (0, _, _) ->
v_entries
| (__nat_1, (M.SourceExpr (v_offset, v_annotation, v_value)), v_ty) when __nat_1 >= 1 ->
(let v_rest = (__nat_1 - 1) in
(f_lambda_entries (v_rest) (v_value) (v_ty) (v_entries)))
| (__nat_2, (M.QualifiedExpr (v_offset, v_annotation, v_predicates, v_value)), v_ty) when __nat_2 >= 1 ->
(let v_rest = (__nat_2 - 1) in
(f_lambda_entries (v_rest) (v_value) (v_ty) (v_entries)))
| (__nat_3, (M.InstantiationExpr (v_site, v_value)), v_ty) when __nat_3 >= 1 ->
(let v_rest = (__nat_3 - 1) in
(f_lambda_entries (v_rest) (v_value) (v_ty) (v_entries)))
| (__nat_4, (M.RuntimeInitExpr (v_value)), v_ty) when __nat_4 >= 1 ->
(let v_rest = (__nat_4 - 1) in
(f_lambda_entries (v_rest) (v_value) (v_ty) (v_entries)))
| (__nat_5, (M.LetExpr (v_name, v_value, v_body)), v_ty) when __nat_5 >= 1 ->
(let v_rest = (__nat_5 - 1) in
(f_lambda_entries (v_rest) (v_body) (v_ty) (v_entries)))
| (__nat_6, (M.UseExpr (v_name, v_value, v_body)), v_ty) when __nat_6 >= 1 ->
(let v_rest = (__nat_6 - 1) in
(f_lambda_entries (v_rest) (v_body) (v_ty) (v_entries)))
| (__nat_7, (M.LambdaExpr (v_identity, v_parameter, v_p, v_r, v_body)), (M.FunctionTy (v_input, v_result, v_effects))) when __nat_7 >= 1 ->
(let v_rest = (__nat_7 - 1) in
(f_lambda_entries (v_rest) (v_body) (v_result) ((f_add_if ((f_isolated (v_effects))) ((Base.string_append s_0 (Base.nat_show (v_identity)))) (v_entries)))))
| (_, _, _) ->
v_entries)
and (* loop_memory.bend:47 *)
f_constants : (M.t_CheckedConstant) list -> Base.set -> Base.set =
fun v_values v_entries ->
(match v_values with
| [] ->
v_entries
| ((M.CheckedConstant ((M.Constant (v_name, v_exported, v_annotation, v_value)), v_ty, v_variables)) :: v_tail) ->
(f_constants (v_tail) ((f_lambda_entries (16384) (v_value) (v_ty) (v_entries)))))
and (* loop_memory.bend:54 *)
f_functions : (M.t_CheckedFunction) list -> Base.set -> Base.set =
fun v_values v_entries ->
(match v_values with
| [] ->
v_entries
| ((M.CheckedFunction ((M.Function (v_name, v_exported, v_parameter, v_p, v_r, v_body)), (M.Signature (v_declared, v_input, v_result, v_variables, v_effects)), v_used)) :: v_tail) ->
(f_functions (v_tail) ((f_lambda_entries (16384) (v_body) (v_result) ((f_add_if ((f_isolated (v_effects))) ((Base.string_append s_1 v_name)) (v_entries)))))))
and (* loop_memory.bend:61 *)
f_eligible : (M.t_CheckedConstant) list -> (M.t_CheckedFunction) list -> Base.set =
fun v_constants_checked v_functions_checked ->
(f_functions (v_functions_checked) ((f_constants (v_constants_checked) ((Base.set_new ())))))
