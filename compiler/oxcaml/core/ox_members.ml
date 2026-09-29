(* Native semantic port of compiler/members.bend.

   Source SHA-256: e668a7146fba1457212a1458c251325a8812fddc951339feda10d6e9a4fdd155

   Ownership/type arguments are erased; value types are checked by OCaml.

   No Bend interpreter or generated C/JavaScript is linked. *)

open Base

module M = Ox_model

module Types = Ox_type_data

let s_0 = Base.text_of_utf8 "$field.payload"

let s_1 = Base.text_of_utf8 "$field.replacement"

let s_2 = Base.text_of_utf8 "internal_error"

let s_3 = Base.text_of_utf8 "record field disappeared during member selection"

let s_4 = Base.text_of_utf8 "$field.receiver"

let rec (* members.bend:5 *)
f_position_work : (Base.text) list -> Base.text -> int -> (int) option -> (int) option =
fun v_fields v_member v_index v_found ->
(match (v_fields, v_found) with
| (_, (Some (v_index))) ->
(Some (v_index))
| ([], None) ->
None
| ((v_field :: v_tail), None) ->
(f_position_work (v_tail) (v_member) ((Base.nat_add 1 v_index)) ((Base.bool_pick ((M.f_name_equal (v_field) (v_member))) ((Some (v_index))) (None)))))
and (* members.bend:14 *)
f_position : (Base.text) list -> Base.text -> int -> (int) option =
fun v_fields v_member v_index ->
(f_position_work (v_fields) (v_member) (v_index) (None))
and (* members.bend:17 *)
f_shared : (M.t_Constructor) list -> Base.text -> bool =
fun v_constructors v_member ->
(match v_constructors with
| [] ->
true
| ((M.Constructor (v_name, v_payload, v_fields)) :: v_tail) ->
(Base.bool_and ((Base.maybe_is_some ((f_position (v_fields) (v_member) (0))))) ((f_shared (v_tail) (v_member)))))
and (* members.bend:24 *)
f_projection : bool -> int -> M.t_Expr =
fun v_single v_index ->
(match v_single with
| true ->
(M.LocalExpr (s_0))
| false ->
(M.ProjectExpr ((M.LocalExpr (s_0)), v_index)))
and (* members.bend:31 *)
f_replacements : (Base.text) list -> Base.text -> bool -> int -> (M.t_Expr) list =
fun v_fields v_member v_single v_index ->
(match v_fields with
| [] ->
[]
| (v_field :: v_tail) ->
((Base.bool_pick ((M.f_name_equal (v_field) (v_member))) ((M.LocalExpr (s_1))) ((f_projection (v_single) (v_index)))) :: (f_replacements (v_tail) (v_member) (v_single) ((Base.nat_add 1 v_index)))))
and (* members.bend:38 *)
f_payload : (M.t_Expr) list -> M.t_Expr =
fun v_elements ->
(match v_elements with
| (v_value :: []) ->
v_value
| v_elements ->
(M.ProductExpr (v_elements)))
and (* members.bend:45 *)
f_access_at : (int) option -> M.t_Dispatch -> Base.text -> (Base.text) list -> Base.text -> (M.t_Diagnostic, M.t_Expr) Base.result_ =
fun v_found v_dispatch v_constructor v_fields v_member ->
(match (v_found, v_dispatch) with
| (None, _) ->
(Fail ((M.Diagnostic (s_2, v_member, s_3))))
| ((Some (v_index)), M.FieldUpdateDispatch) ->
(Done ((M.ConstructExpr (v_constructor, (Some ((f_payload ((f_replacements (v_fields) (v_member) ((Base.nat_is_eq ((Base.list_length (v_fields))) (1))) (0))))))))))
| ((Some (v_index)), _) ->
(Done ((f_projection ((Base.nat_is_eq ((Base.list_length (v_fields))) (1))) (v_index)))))
and (* members.bend:54 *)
f_arms : (M.t_Constructor) list -> M.t_Dispatch -> Base.text -> (M.t_Diagnostic, ((M.t_Expr) M.t_MatchArm) list) Base.result_ =
fun v_constructors v_dispatch v_member ->
(match v_constructors with
| [] ->
(Done ([]))
| ((M.Constructor (v_constructor, v_ty, v_fields)) :: v_tail) ->
(match (f_access_at ((f_position (v_fields) (v_member) (0))) (v_dispatch) (v_constructor) (v_fields) (v_member)) with
| Fail __error -> Fail __error
| Done v_body ->
(match (f_arms (v_tail) (v_dispatch) (v_member)) with
| Fail __error -> Fail __error
| Done v_following ->
(Done (((M.MatchArm ([(M.ConstructorPattern (v_constructor, (Some ((M.BindingPattern (s_0))))))], v_body)) :: v_following))))))
and (* members.bend:64 *)
f_body : M.t_Dispatch -> ((M.t_Expr) M.t_MatchArm) list -> int -> M.t_Expr =
fun v_dispatch v_branches v_identity ->
(match v_dispatch with
| M.FieldUpdateDispatch ->
(M.LambdaExpr (v_identity, s_1, None, None, (M.MatchExpr ([(M.LocalExpr (s_4))], v_branches))))
| _ ->
(M.MatchExpr ([(M.LocalExpr (s_4))], v_branches)))
and (* members.bend:71 *)
f_function : (M.t_Constructor) list -> M.t_Dispatch -> Base.text -> Base.text -> int -> (M.t_Diagnostic, M.t_Function) Base.result_ =
fun v_constructors v_dispatch v_member v_name v_identity ->
(match (f_arms (v_constructors) (v_dispatch) (v_member)) with
| Fail __error -> Fail __error
| Done v_branches ->
(Done ((M.Function (v_name, false, s_4, None, None, (f_body (v_dispatch) (v_branches) (v_identity)))))))
and (* members.bend:76 *)
f_declared_constructors : (M.t_DataType) option -> (M.t_Constructor) list =
fun v_found ->
(match v_found with
| (Some ((M.DataType (v_identity, v_parameters, v_constructors)))) ->
v_constructors
| None ->
[])
and (* members.bend:83 *)
f_constructors : M.t_Ty -> (M.t_DataType) list -> (M.t_Constructor) list =
fun v_ty v_types ->
(match v_ty with
| (M.AppliedTy (v_identity, v_arguments)) ->
(f_declared_constructors ((Types.f_lookup (v_types) (v_identity))))
| _ ->
[])
and (* members.bend:90 *)
f_has_field : (M.t_Constructor) list -> Base.text -> bool =
fun v_constructors v_member ->
(match v_constructors with
| [] ->
false
| v_constructors ->
(f_shared (v_constructors) (v_member)))
