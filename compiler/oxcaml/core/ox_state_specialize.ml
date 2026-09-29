(* Native semantic port of compiler/state_specialize.bend.

   Source SHA-256: df9ab25d9faef5acae4306e8788bb466dfc0cf9b22df44df4e507a2e0577c3b0

   Ownership/type arguments are erased; value types are checked by OCaml.

   No Bend interpreter or generated C/JavaScript is linked. *)

open Base

module M = Ox_model

module E = Ox_effects

type t_Request =
  | Read
  | Write
  | Run
  | Reader
  | Writer
and t_KeyWork =
  | TypeKey of M.t_Ty
  | TypesKey of (M.t_Ty) list

let s_0 = Base.text_of_utf8 "@state.get"

let s_1 = Base.text_of_utf8 "@state.set"

let s_2 = Base.text_of_utf8 "@state.run"

let s_3 = Base.text_of_utf8 "@effect.run"

let s_4 = Base.text_of_utf8 "@state.reader"

let s_5 = Base.text_of_utf8 "@effect.reader"

let s_6 = Base.text_of_utf8 "@state.writer"

let s_7 = Base.text_of_utf8 "@effect.writer"

let s_8 = Base.text_of_utf8 ":"

let s_9 = Base.text_of_utf8 ""

let s_10 = Base.text_of_utf8 "ambiguous_state"

let s_11 = Base.text_of_utf8 "state"

let s_12 = Base.text_of_utf8 "state identity requires closed effect rows"

let s_13 = Base.text_of_utf8 "specialization_limit"

let s_14 = Base.text_of_utf8 "state type exceeds its structural limit"

let s_15 = Base.text_of_utf8 "u"

let s_16 = Base.text_of_utf8 "i"

let s_17 = Base.text_of_utf8 "f"

let s_18 = Base.text_of_utf8 "b"

let s_19 = Base.text_of_utf8 "n"

let s_20 = Base.text_of_utf8 "a"

let s_21 = Base.text_of_utf8 "p"

let s_22 = Base.text_of_utf8 "c"

let s_23 = Base.text_of_utf8 "state requires a concrete runtime value type"

let s_24 = Base.text_of_utf8 "blot:state"

let s_25 = Base.text_of_utf8 "read:"

let s_26 = Base.text_of_utf8 "write:"

let s_27 = Base.text_of_utf8 "$state.left"

let s_28 = Base.text_of_utf8 "$state.right"

let s_29 = Base.text_of_utf8 "$state.implementation"

let s_30 = Base.text_of_utf8 "$state.action"

let rec (* state_specialize.bend:12 *)
f_request : Base.text -> (t_Request) option =
fun v_member ->
(Base.bool_pick ((M.f_name_equal (v_member) (s_0))) ((Some (Read))) ((Base.bool_pick ((M.f_name_equal (v_member) (s_1))) ((Some (Write))) ((Base.bool_pick ((Base.bool_or ((M.f_name_equal (v_member) (s_2))) ((M.f_name_equal (v_member) (s_3))))) ((Some (Run))) ((Base.bool_pick ((Base.bool_or ((M.f_name_equal (v_member) (s_4))) ((M.f_name_equal (v_member) (s_5))))) ((Some (Reader))) ((Base.bool_pick ((Base.bool_or ((M.f_name_equal (v_member) (s_6))) ((M.f_name_equal (v_member) (s_7))))) ((Some (Writer))) (None))))))))))
and (* state_specialize.bend:19 *)
f_witness : int -> M.t_Ty -> M.t_Ty =
fun v_fuel v_ty ->
(match (v_fuel, v_ty) with
| (__nat_1, (M.FunctionTy (v_parameter, v_result, v_effects))) when __nat_1 >= 1 ->
(let v_rest = (__nat_1 - 1) in
(f_witness (v_rest) (v_result)))
| (_, v_other) ->
v_other)
and (* state_specialize.bend:26 *)
f_state_type : t_Request -> M.t_Ty -> M.t_Ty =
fun v_request v_left ->
(match v_request with
| Write ->
v_left
| Run ->
v_left
| _ ->
(f_witness (65536) (v_left)))
and (* state_specialize.bend:39 *)
f_packed : Base.text -> Base.text =
fun v_value ->
(Base.string_append (Base.nat_show ((Base.string_length (v_value)))) (Base.string_append s_8 v_value))
and (* state_specialize.bend:42 *)
f_nominal : M.t_TypeId -> Base.text =
fun v_identity ->
(let (M.TypeId (v_module_name, v_declaration)) = v_identity in
(Base.string_append (f_packed (v_module_name)) (f_packed (v_declaration))))
and (* state_specialize.bend:46 *)
f_operation_keys : (M.t_TypeId) list -> Base.text =
fun v_operations ->
(match v_operations with
| [] ->
s_9
| (v_head :: v_tail) ->
(Base.string_append (f_packed ((f_nominal (v_head)))) (f_operation_keys (v_tail))))
and (* state_specialize.bend:53 *)
f_operation_less : M.t_TypeId -> M.t_TypeId -> bool =
fun v_left v_right ->
(E.f_effect_le ((M.OperationEffect (v_left))) ((M.OperationEffect (v_right))))
and (* state_specialize.bend:56 *)
f_row_key : M.t_EffectRow -> (M.t_Diagnostic, Base.text) Base.result_ =
fun v_row ->
(match v_row with
| (M.EffectRow (v_operations, M.ClosedRow)) ->
(Done ((f_operation_keys ((Base.list_sort (f_operation_less) (v_operations))))))
| _ ->
(Fail ((M.Diagnostic (s_10, s_11, s_12)))))
and (* state_specialize.bend:65 *)
f_type_key : int -> t_KeyWork -> (M.t_Diagnostic, Base.text) Base.result_ =
fun v_fuel v_work ->
(match (v_fuel, v_work) with
| (0, _) ->
(Fail ((M.Diagnostic (s_13, s_11, s_14))))
| (__nat_2, (TypeKey (M.UnitTy))) when __nat_2 >= 1 ->
(let v_rest = (__nat_2 - 1) in
(Done (s_15)))
| (__nat_3, (TypeKey (M.U32Ty))) when __nat_3 >= 1 ->
(let v_rest = (__nat_3 - 1) in
(Done (s_16)))
| (__nat_4, (TypeKey (M.F32Ty))) when __nat_4 >= 1 ->
(let v_rest = (__nat_4 - 1) in
(Done (s_17)))
| (__nat_5, (TypeKey (M.BoolTy))) when __nat_5 >= 1 ->
(let v_rest = (__nat_5 - 1) in
(Done (s_18)))
| (__nat_6, (TypeKey ((M.AppliedTy (v_identity, v_arguments))))) when __nat_6 >= 1 ->
(let v_rest = (__nat_6 - 1) in
(match (f_type_key (v_rest) ((TypesKey (v_arguments)))) with
| Fail __error -> Fail __error
| Done v_args ->
(Done ((Base.string_append s_19 (Base.string_append (f_nominal (v_identity)) (f_packed (v_args))))))))
| (__nat_7, (TypeKey ((M.ArrayTy (v_element))))) when __nat_7 >= 1 ->
(let v_rest = (__nat_7 - 1) in
(match (f_type_key (v_rest) ((TypeKey (v_element)))) with
| Fail __error -> Fail __error
| Done v_value ->
(Done ((Base.string_append s_20 (f_packed (v_value)))))))
| (__nat_8, (TypeKey ((M.ProductTy (v_elements))))) when __nat_8 >= 1 ->
(let v_rest = (__nat_8 - 1) in
(match (f_type_key (v_rest) ((TypesKey (v_elements)))) with
| Fail __error -> Fail __error
| Done v_values ->
(Done ((Base.string_append s_21 (f_packed (v_values)))))))
| (__nat_9, (TypeKey ((M.FunctionTy (v_parameter, v_result, v_effects))))) when __nat_9 >= 1 ->
(let v_rest = (__nat_9 - 1) in
(match (f_type_key (v_rest) ((TypeKey (v_parameter)))) with
| Fail __error -> Fail __error
| Done v_p ->
(match (f_type_key (v_rest) ((TypeKey (v_result)))) with
| Fail __error -> Fail __error
| Done v_r ->
(match (f_row_key (v_effects)) with
| Fail __error -> Fail __error
| Done v_e ->
(Done ((Base.string_append s_22 (Base.string_append (f_packed (v_p)) (Base.string_append (f_packed (v_r)) (f_packed (v_e)))))))))))
| (__nat_10, (TypesKey ([]))) when __nat_10 >= 1 ->
(let v_rest = (__nat_10 - 1) in
(Done (s_9)))
| (__nat_11, (TypesKey ((v_head :: v_tail)))) when __nat_11 >= 1 ->
(let v_rest = (__nat_11 - 1) in
(match (f_type_key (v_rest) ((TypeKey (v_head)))) with
| Fail __error -> Fail __error
| Done v_value ->
(match (f_type_key (v_rest) ((TypesKey (v_tail)))) with
| Fail __error -> Fail __error
| Done v_remaining ->
(Done ((Base.string_append (f_packed (v_value)) v_remaining))))))
| (_, _) ->
(Fail ((M.Diagnostic (s_10, s_11, s_23)))))
and (* state_specialize.bend:105 *)
f_read_identity : Base.text -> M.t_TypeId =
fun v_key ->
(M.TypeId (s_24, (Base.string_append s_25 v_key)))
and (* state_specialize.bend:108 *)
f_write_identity : Base.text -> M.t_TypeId =
fun v_key ->
(M.TypeId (s_24, (Base.string_append s_26 v_key)))
and (* state_specialize.bend:111 *)
f_contains_step : bool -> (unit -> bool) -> bool =
fun v_equal v_remaining ->
(match v_equal with
| true ->
true
| false ->
(v_remaining (())))
and (* state_specialize.bend:118 *)
f_contains_work : (M.t_Operation) list -> M.t_TypeId -> bool -> bool =
fun v_operations v_identity v_found ->
(match (v_operations, v_found) with
| (_, true) ->
true
| ([], false) ->
false
| (((M.Operation (v_known, v_parameter, v_result)) :: v_tail), false) ->
(f_contains_work (v_tail) (v_identity) ((M.f_type_id_equal (v_known) (v_identity))))
| ((v_head :: v_tail), false) ->
(f_contains_work (v_tail) (v_identity) (false)))
and (* state_specialize.bend:129 *)
f_contains : (M.t_Operation) list -> M.t_TypeId -> bool =
fun v_operations v_identity ->
(f_contains_work (v_operations) (v_identity) (false))
and (* state_specialize.bend:132 *)
f_concrete : (M.t_Operation) list -> (M.t_Operation) list =
fun v_operations ->
(match v_operations with
| [] ->
[]
| ((M.Operation (v_identity, v_parameter, v_result)) :: v_tail) ->
((M.Operation (v_identity, v_parameter, v_result)) :: (f_concrete (v_tail)))
| (v_head :: v_tail) ->
(f_concrete (v_tail)))
and (* state_specialize.bend:141 *)
f_merge_operation : bool -> (M.t_Operation) list -> M.t_Operation -> (M.t_Operation) list =
fun v_present v_operations v_operation ->
(match v_present with
| true ->
v_operations
| false ->
(Base.list_append (v_operations) ([v_operation])))
and (* state_specialize.bend:148 *)
f_merge : (M.t_Operation) list -> (M.t_Operation) list -> (M.t_Operation) list =
fun v_incoming v_operations ->
(match v_incoming with
| [] ->
v_operations
| ((M.Operation (v_identity, v_parameter, v_result)) :: v_tail) ->
(let v_operation = (M.Operation (v_identity, v_parameter, v_result)) in
(f_merge (v_tail) ((f_merge_operation ((f_contains (v_operations) (v_identity))) (v_operations) (v_operation)))))
| (v_head :: v_tail) ->
(f_merge (v_tail) (v_operations)))
and (* state_specialize.bend:158 *)
f_operations : Base.text -> M.t_Ty -> (M.t_Operation) list -> (M.t_Operation) list =
fun v_key v_ty v_existing ->
(f_merge ([(M.Operation ((f_read_identity (v_key)), M.UnitTy, v_ty)); (M.Operation ((f_write_identity (v_key)), v_ty, M.UnitTy))]) (v_existing))
and (* state_specialize.bend:161 *)
f_body : t_Request -> M.t_TypeId -> M.t_TypeId -> M.t_Expr =
fun v_request v_read v_write ->
(match v_request with
| Read ->
(M.ApplyExpr ((M.OperationExpr (v_read)), M.UnitExpr))
| Write ->
(M.ApplyExpr ((M.OperationExpr (v_write)), (M.LocalExpr (s_27))))
| Run ->
(M.HandleExpr ((M.StateProviderExpr (v_read, v_write, (M.LocalExpr (s_27)))), (M.ApplyExpr ((M.LocalExpr (s_28)), M.UnitExpr))))
| Reader ->
(M.MatchExpr ([(M.LocalExpr (s_28))], [(M.MatchArm ([(M.ProductPattern ([(M.BindingPattern (s_29)); (M.BindingPattern (s_30))]))], (M.HandleExpr ((M.ProviderExpr (v_read, (M.LocalExpr (s_29)))), (M.ApplyExpr ((M.LocalExpr (s_30)), M.UnitExpr))))))]))
| Writer ->
(M.MatchExpr ([(M.LocalExpr (s_28))], [(M.MatchArm ([(M.ProductPattern ([(M.BindingPattern (s_29)); (M.BindingPattern (s_30))]))], (M.HandleExpr ((M.ProviderExpr (v_write, (M.LocalExpr (s_29)))), (M.ApplyExpr ((M.LocalExpr (s_30)), M.UnitExpr))))))])))
and (* state_specialize.bend:174 *)
f_function_for : t_Request -> M.t_TypeId -> M.t_TypeId -> Base.text -> int -> M.t_Function =
fun v_request v_read v_write v_name v_identity ->
(M.Function (v_name, false, s_27, None, None, (M.LambdaExpr (v_identity, s_28, None, None, (f_body (v_request) (v_read) (v_write))))))
and (* state_specialize.bend:177 *)
f_function : t_Request -> Base.text -> Base.text -> int -> M.t_Function =
fun v_request v_key v_name v_identity ->
(f_function_for (v_request) ((f_read_identity (v_key))) ((f_write_identity (v_key))) (v_name) (v_identity))
