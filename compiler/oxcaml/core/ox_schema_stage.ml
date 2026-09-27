(* Native semantic port of compiler/schema_stage.bend.

   Source SHA-256: a29ddc9f36e45423b21c21443eaaed199d68dc80c58d58413edd89dd7a32d0ac

   Ownership/type arguments are erased; value types are checked by OCaml.

   No Bend interpreter or generated C/JavaScript is linked. *)

open Base

module M = Ox_model

module Compare = Ox_core_compare

module TD = Ox_type_data

module State = Ox_state_specialize

module Groups = Ox_groups

module Members = Ox_members

type t_Evidence =
  | Evidence of M.t_Function * M.t_Function * M.t_Function * M.t_Function * M.t_DataType * M.t_DataType * M.t_DataType * Base.text * M.t_TypeId * M.t_TypeId * Base.text
and t_NodeShape =
  | NodeShape of Base.text * Base.text * Base.text * Base.text
and t_EqualCall =
  | EqualCall of Base.text * Base.text
and t_Terminal =
  | Terminal of M.t_Function * M.t_DataType
and t_ChainWork =
  | Walk of M.t_Ty * Base.text * t_Evidence * bool
  | OnNode of M.t_Ty * M.t_Ty * Base.text * t_Evidence * bool * bool
  | ComparedHead of (Base.text) option * Base.text * M.t_Ty * t_Evidence * bool
  | Choose of bool * M.t_Ty * Base.text * t_Evidence * bool
and t_Search =
  | Scan of (t_Evidence) list * Base.text * Base.text * M.t_Ty * M.t_Ty * (M.t_Function) list * (M.t_DataType) list
  | Chosen of (bool) option * (t_Evidence) list * Base.text * Base.text * M.t_Ty * M.t_Ty * (M.t_Function) list * (M.t_DataType) list

let s_0 = Base.text_of_utf8 "eq"

let s_1 = Base.text_of_utf8 "@type.same"

let s_2 = Base.text_of_utf8 "std/prelude"

let s_3 = Base.text_of_utf8 "$prelude."

let s_4 = Base.text_of_utf8 ""

let s_5 = Base.text_of_utf8 "$module["

let s_6 = Base.text_of_utf8 "]."

let s_7 = Base.text_of_utf8 "."

let rec (* schema_stage.bend:24 *)
f_node_constructor : t_NodeShape -> Base.text =
fun v_shape ->
(let (NodeShape (v_constructor, v_member, v_equality, v_witness_constructor)) = v_shape in
v_constructor)
and (* schema_stage.bend:28 *)
f_node_member : t_NodeShape -> Base.text =
fun v_shape ->
(let (NodeShape (v_constructor, v_member, v_equality, v_witness_constructor)) = v_shape in
v_member)
and (* schema_stage.bend:32 *)
f_node_equality : t_NodeShape -> Base.text =
fun v_shape ->
(let (NodeShape (v_constructor, v_member, v_equality, v_witness_constructor)) = v_shape in
v_equality)
and (* schema_stage.bend:36 *)
f_witness_constructor : t_NodeShape -> Base.text =
fun v_shape ->
(let (NodeShape (v_constructor, v_member, v_equality, v_witness_constructor)) = v_shape in
v_witness_constructor)
and (* schema_stage.bend:40 *)
f_distinct2 : Base.text -> Base.text -> bool =
fun v_a v_b ->
(Base.bool_not ((M.f_name_equal (v_a) (v_b))))
and (* schema_stage.bend:43 *)
f_distinct4 : Base.text -> Base.text -> Base.text -> Base.text -> bool =
fun v_a v_b v_c v_d ->
(Base.bool_and ((f_distinct2 (v_a) (v_b))) ((Base.bool_and ((f_distinct2 (v_a) (v_c))) ((Base.bool_and ((f_distinct2 (v_a) (v_d))) ((Base.bool_and ((f_distinct2 (v_b) (v_c))) ((Base.bool_and ((f_distinct2 (v_b) (v_d))) ((f_distinct2 (v_c) (v_d))))))))))))
and (* schema_stage.bend:46 *)
f_distinct5 : Base.text -> Base.text -> Base.text -> Base.text -> Base.text -> bool =
fun v_a v_b v_c v_d v_e ->
(Base.bool_and ((f_distinct4 (v_a) (v_b) (v_c) (v_d))) ((Base.bool_and ((f_distinct2 (v_a) (v_e))) ((Base.bool_and ((f_distinct2 (v_b) (v_e))) ((Base.bool_and ((f_distinct2 (v_c) (v_e))) ((f_distinct2 (v_d) (v_e))))))))))
and (* schema_stage.bend:49 *)
f_bare : M.t_Expr -> (M.t_Expr) option =
fun v_value ->
(match v_value with
| (M.SourceExpr (v_offset, None, v_inner)) ->
(f_bare (v_inner))
| (M.SourceExpr (v_offset, (Some (v_annotation)), v_inner)) ->
None
| (M.InstantiationExpr (v_site, v_inner)) ->
(f_bare (v_inner))
| v_other ->
(Some (v_other)))
and (* schema_stage.bend:61 *)
f_local_bare : (M.t_Expr) option -> Base.text -> bool =
fun v_value v_wanted ->
(match v_value with
| (Some ((M.LocalExpr (v_name)))) ->
(M.f_name_equal (v_name) (v_wanted))
| _ ->
false)
and (* schema_stage.bend:68 *)
f_local : M.t_Expr -> Base.text -> bool =
fun v_value v_wanted ->
(f_local_bare ((f_bare (v_value))) (v_wanted))
and (* schema_stage.bend:71 *)
f_unit_bare : (M.t_Expr) option -> bool =
fun v_value ->
(match v_value with
| (Some (M.UnitExpr)) ->
true
| _ ->
false)
and (* schema_stage.bend:78 *)
f_unit : M.t_Expr -> bool =
fun v_value ->
(f_unit_bare ((f_bare (v_value))))
and (* schema_stage.bend:81 *)
f_boolean_bare : (M.t_Expr) option -> bool -> bool =
fun v_value v_wanted ->
(match (v_value, v_wanted) with
| ((Some ((M.BoolExpr (true)))), true) ->
true
| ((Some ((M.BoolExpr (false)))), false) ->
true
| (_, _) ->
false)
and (* schema_stage.bend:90 *)
f_boolean : M.t_Expr -> bool -> bool =
fun v_value v_wanted ->
(f_boolean_bare ((f_bare (v_value))) (v_wanted))
and (* schema_stage.bend:93 *)
f_type_argument_callee : (M.t_Expr) option -> M.t_Expr -> Base.text -> (Base.text) option =
fun v_value v_argument v_variable ->
(match v_value with
| (Some ((M.ConstructorRefExpr (v_constructor)))) ->
(Base.bool_pick ((f_local (v_argument) (v_variable))) ((Some (v_constructor))) (None))
| _ ->
None)
and (* schema_stage.bend:100 *)
f_type_argument_bare : (M.t_Expr) option -> Base.text -> (Base.text) option =
fun v_value v_variable ->
(match v_value with
| (Some ((M.ApplyExpr (v_callee, v_argument)))) ->
(f_type_argument_callee ((f_bare (v_callee))) (v_argument) (v_variable))
| _ ->
None)
and (* schema_stage.bend:107 *)
f_type_argument : M.t_Expr -> Base.text -> (Base.text) option =
fun v_value v_variable ->
(f_type_argument_bare ((f_bare (v_value))) (v_variable))
and (* schema_stage.bend:110 *)
f_equal_arguments : (Base.text) option -> (Base.text) option -> Base.text -> (t_EqualCall) option =
fun v_left v_right v_function ->
(match (v_left, v_right) with
| ((Some (v_a)), (Some (v_b))) ->
(Base.bool_pick ((M.f_name_equal (v_a) (v_b))) ((Some ((EqualCall (v_function, v_a))))) (None))
| (_, _) ->
None)
and (* schema_stage.bend:117 *)
f_equality_callee : (M.t_Expr) option -> M.t_Expr -> Base.text -> Base.text -> (t_EqualCall) option =
fun v_value v_argument v_witness v_head ->
(match v_value with
| (Some ((M.CallExpr (v_function, v_left)))) ->
(f_equal_arguments ((f_type_argument (v_left) (v_head))) ((f_type_argument (v_argument) (v_witness))) (v_function))
| _ ->
None)
and (* schema_stage.bend:124 *)
f_equality_bare : (M.t_Expr) option -> Base.text -> Base.text -> (t_EqualCall) option =
fun v_value v_witness v_head ->
(match v_value with
| (Some ((M.ApplyExpr (v_callee, v_argument)))) ->
(f_equality_callee ((f_bare (v_callee))) (v_argument) (v_witness) (v_head))
| _ ->
None)
and (* schema_stage.bend:131 *)
f_equality : M.t_Expr -> Base.text -> Base.text -> (t_EqualCall) option =
fun v_value v_witness v_head ->
(f_equality_bare ((f_bare (v_value))) (v_witness) (v_head))
and (* schema_stage.bend:134 *)
f_returned_bool_bare : (M.t_Expr) option -> int -> bool -> bool =
fun v_value v_label v_wanted ->
(match v_value with
| (Some ((M.ReturnExpr (v_found, v_body)))) ->
(Base.bool_and ((Base.nat_is_eq (v_found) (v_label))) ((f_boolean (v_body) (v_wanted))))
| _ ->
false)
and (* schema_stage.bend:141 *)
f_returned_bool : M.t_Expr -> int -> bool -> bool =
fun v_value v_label v_wanted ->
(f_returned_bool_bare ((f_bare (v_value))) (v_label) (v_wanted))
and (* schema_stage.bend:144 *)
f_tail_member_bare : (M.t_Expr) option -> Base.text -> (Base.text) option =
fun v_value v_tail ->
(match v_value with
| (Some ((M.AssociatedExpr (v_identity, M.MemberDispatch, v_member, [], v_receiver, v_right)))) ->
(Base.bool_pick ((Base.bool_and ((f_local (v_receiver) (v_tail))) ((f_unit (v_right))))) ((Some (v_member))) (None))
| _ ->
None)
and (* schema_stage.bend:151 *)
f_tail_call_callee : (M.t_Expr) option -> M.t_Expr -> Base.text -> Base.text -> (Base.text) option =
fun v_value v_argument v_witness v_tail ->
(match v_value with
| (Some ((M.AssociatedExpr (v_identity, M.MemberDispatch, v_member, [], v_receiver, v_right)))) ->
(Base.bool_pick ((Base.bool_and ((f_local (v_receiver) (v_tail))) ((Base.bool_and ((f_unit (v_right))) ((f_local (v_argument) (v_witness))))))) ((Some (v_member))) (None))
| _ ->
None)
and (* schema_stage.bend:158 *)
f_tail_call_bare : (M.t_Expr) option -> Base.text -> Base.text -> (Base.text) option =
fun v_value v_witness v_tail ->
(match v_value with
| (Some ((M.ApplyExpr (v_callee, v_argument)))) ->
(f_tail_call_callee ((f_bare (v_callee))) (v_argument) (v_witness) (v_tail))
| _ ->
None)
and (* schema_stage.bend:165 *)
f_returned_tail_bare : (M.t_Expr) option -> int -> Base.text -> Base.text -> (Base.text) option =
fun v_value v_label v_witness v_tail ->
(match v_value with
| (Some ((M.ReturnExpr (v_found, v_body)))) ->
(Base.bool_pick ((Base.nat_is_eq (v_found) (v_label))) ((f_tail_call_bare ((f_bare (v_body))) (v_witness) (v_tail))) (None))
| _ ->
None)
and (* schema_stage.bend:172 *)
f_returned_tail : M.t_Expr -> int -> Base.text -> Base.text -> (Base.text) option =
fun v_value v_label v_witness v_tail ->
(f_returned_tail_bare ((f_bare (v_value))) (v_label) (v_witness) (v_tail))
and (* schema_stage.bend:175 *)
f_branch_bare : (M.t_Expr) option -> int -> Base.text -> Base.text -> (t_EqualCall) option =
fun v_value v_label v_witness v_head ->
(match v_value with
| (Some ((M.IfExpr (v_condition, v_consequent, v_alternative)))) ->
(Base.bool_pick ((Base.bool_and ((f_returned_bool (v_consequent) (v_label) (true))) ((f_unit (v_alternative))))) ((f_equality (v_condition) (v_witness) (v_head))) (None))
| _ ->
None)
and (* schema_stage.bend:182 *)
f_joined_parts : (t_EqualCall) option -> (Base.text) option -> Base.text -> (t_NodeShape) option =
fun v_equal v_member v_constructor ->
(match (v_equal, v_member) with
| ((Some ((EqualCall (v_function, v_witness_constructor)))), (Some (v_name))) ->
(Some ((NodeShape (v_constructor, v_name, v_function, v_witness_constructor))))
| (_, _) ->
None)
and (* schema_stage.bend:189 *)
f_node_sequence_bare : (M.t_Expr) option -> Base.text -> int -> Base.text -> Base.text -> Base.text -> (t_NodeShape) option =
fun v_value v_constructor v_label v_witness v_head v_tail ->
(match v_value with
| (Some ((M.SequenceExpr (v_first, v_next)))) ->
(f_joined_parts ((f_branch_bare ((f_bare (v_first))) (v_label) (v_witness) (v_head))) ((f_returned_tail (v_next) (v_label) (v_witness) (v_tail))) (v_constructor))
| _ ->
None)
and (* schema_stage.bend:196 *)
f_node_arm : (M.t_Expr) M.t_MatchArm -> int -> Base.text -> Base.text -> Base.text -> (t_NodeShape) option =
fun v_value v_label v_receiver v_temporary v_witness ->
(match v_value with
| (M.MatchArm (((M.ConstructorPattern (v_constructor, (Some ((M.ProductPattern (((M.BindingPattern (v_head)) :: ((M.BindingPattern (v_tail)) :: [])))))))) :: []), v_body)) ->
(Base.bool_pick ((f_distinct5 (v_receiver) (v_temporary) (v_witness) (v_head) (v_tail))) ((f_node_sequence_bare ((f_bare (v_body))) (v_constructor) (v_label) (v_witness) (v_head) (v_tail))) (None))
| _ ->
None)
and (* schema_stage.bend:203 *)
f_node_match_bare : (M.t_Expr) option -> Base.text -> int -> Base.text -> Base.text -> (t_NodeShape) option =
fun v_value v_temporary v_label v_receiver v_witness ->
(match v_value with
| (Some ((M.MatchExpr (((M.LocalExpr (v_found)) :: []), (v_arm :: []))))) ->
(Base.bool_pick ((M.f_name_equal (v_found) (v_temporary))) ((f_node_arm (v_arm) (v_label) (v_receiver) (v_temporary) (v_witness))) (None))
| _ ->
None)
and (* schema_stage.bend:210 *)
f_node_let_bare : (M.t_Expr) option -> Base.text -> int -> Base.text -> (t_NodeShape) option =
fun v_value v_receiver v_label v_witness ->
(match v_value with
| (Some ((M.LetExpr (v_temporary, v_subject, v_body)))) ->
(Base.bool_pick ((f_local (v_subject) (v_receiver))) ((f_node_match_bare ((f_bare (v_body))) (v_temporary) (v_label) (v_receiver) (v_witness))) (None))
| _ ->
None)
and (* schema_stage.bend:217 *)
f_node_block_bare : (M.t_Expr) option -> Base.text -> Base.text -> (t_NodeShape) option =
fun v_value v_receiver v_witness ->
(match v_value with
| (Some ((M.BlockExpr (v_label, v_body)))) ->
(f_node_let_bare ((f_bare (v_body))) (v_receiver) (v_label) (v_witness))
| _ ->
None)
and (* schema_stage.bend:224 *)
f_node_lambda_bare : (M.t_Expr) option -> Base.text -> (t_NodeShape) option =
fun v_value v_receiver ->
(match v_value with
| (Some ((M.LambdaExpr (v_identity, v_witness, None, None, v_body)))) ->
(f_node_block_bare ((f_bare (v_body))) (v_receiver) (v_witness))
| _ ->
None)
and (* schema_stage.bend:231 *)
f_node : M.t_Function -> (t_NodeShape) option =
fun v_function ->
(match v_function with
| (M.Function (v_name, v_exported, v_receiver, None, None, v_body)) ->
(f_node_lambda_bare ((f_bare (v_body))) (v_receiver))
| _ ->
None)
and (* schema_stage.bend:238 *)
f_terminal_lambda_bare : (M.t_Expr) option -> bool =
fun v_value ->
(match v_value with
| (Some ((M.LambdaExpr (v_identity, v_witness, None, None, v_body)))) ->
(f_boolean (v_body) (false))
| _ ->
false)
and (* schema_stage.bend:245 *)
f_terminal : M.t_Function -> bool =
fun v_function ->
(match v_function with
| (M.Function (v_name, v_exported, v_receiver, v_parameter_type, None, v_body)) ->
(f_terminal_lambda_bare ((f_bare (v_body))))
| _ ->
false)
and (* schema_stage.bend:252 *)
f_forwarded_call_bare : (M.t_Expr) option -> Base.text -> Base.text -> bool =
fun v_value v_left v_right ->
(match v_value with
| (Some ((M.AssociatedExpr (v_identity, M.BinaryDispatch, v_member, [], v_a, v_b)))) ->
(Base.bool_and ((M.f_name_equal (v_member) (s_0))) ((Base.bool_and ((f_local (v_a) (v_left))) ((f_local (v_b) (v_right))))))
| _ ->
false)
and (* schema_stage.bend:259 *)
f_forwarding_lambda_bare : (M.t_Expr) option -> Base.text -> bool =
fun v_value v_left ->
(match v_value with
| (Some ((M.LambdaExpr (v_identity, v_right, None, None, v_body)))) ->
(Base.bool_and ((f_distinct2 (v_left) (v_right))) ((f_forwarded_call_bare ((f_bare (v_body))) (v_left) (v_right))))
| _ ->
false)
and (* schema_stage.bend:266 *)
f_equality_forwarder : M.t_Function -> bool =
fun v_function ->
(match v_function with
| (M.Function (v_name, v_exported, v_left, None, None, v_body)) ->
(f_forwarding_lambda_bare ((f_bare (v_body))) (v_left))
| _ ->
false)
and (* schema_stage.bend:273 *)
f_type_same_bare : (M.t_Expr) option -> Base.text -> Base.text -> bool =
fun v_value v_left v_right ->
(match v_value with
| (Some ((M.AssociatedExpr (v_identity, M.BinaryDispatch, v_member, [], v_a, v_b)))) ->
(Base.bool_and ((M.f_name_equal (v_member) (s_1))) ((Base.bool_and ((f_local (v_a) (v_left))) ((f_local (v_b) (v_right))))))
| _ ->
false)
and (* schema_stage.bend:280 *)
f_type_eq_arm : (M.t_Expr) M.t_MatchArm -> Base.text -> Base.text -> (Base.text) option =
fun v_value v_outer_left v_outer_right ->
(match v_value with
| (M.MatchArm (((M.ConstructorPattern (v_left_constructor, (Some ((M.BindingPattern (v_left)))))) :: ((M.ConstructorPattern (v_right_constructor, (Some ((M.BindingPattern (v_right)))))) :: [])), v_body)) ->
(Base.bool_pick ((Base.bool_and ((f_distinct4 (v_outer_left) (v_outer_right) (v_left) (v_right))) ((Base.bool_and ((M.f_name_equal (v_left_constructor) (v_right_constructor))) ((f_type_same_bare ((f_bare (v_body))) (v_left) (v_right))))))) ((Some (v_left_constructor))) (None))
| _ ->
None)
and (* schema_stage.bend:287 *)
f_type_eq_match_bare : (M.t_Expr) option -> Base.text -> Base.text -> (Base.text) option =
fun v_value v_left v_right ->
(match v_value with
| (Some ((M.MatchExpr ((v_a :: (v_b :: [])), (v_arm :: []))))) ->
(Base.bool_pick ((Base.bool_and ((f_local (v_a) (v_left))) ((f_local (v_b) (v_right))))) ((f_type_eq_arm (v_arm) (v_left) (v_right))) (None))
| _ ->
None)
and (* schema_stage.bend:294 *)
f_type_eq_lambda_bare : (M.t_Expr) option -> Base.text -> (Base.text) option =
fun v_value v_left ->
(match v_value with
| (Some ((M.LambdaExpr (v_identity, v_right, None, None, v_body)))) ->
(f_type_eq_match_bare ((f_bare (v_body))) (v_left) (v_right))
| _ ->
None)
and (* schema_stage.bend:301 *)
f_type_equality : M.t_Function -> (Base.text) option =
fun v_function ->
(match v_function with
| (M.Function (v_name, v_exported, v_left, None, None, v_body)) ->
(f_type_eq_lambda_bare ((f_bare (v_body))) (v_left))
| _ ->
None)
and (* schema_stage.bend:308 *)
f_name : M.t_Function -> Base.text =
fun v_function ->
(let (M.Function (v_name, v_exported, v_parameter, v_p, v_r, v_body)) = v_function in
v_name)
and (* schema_stage.bend:312 *)
f_find_function_work : (M.t_Function) list -> Base.text -> (M.t_Function) option -> (M.t_Function) option =
fun v_functions v_wanted v_found ->
(match (v_functions, v_found) with
| (_, (Some (v_value))) ->
(Some (v_value))
| ([], None) ->
None
| ((v_head :: v_tail), None) ->
(f_find_function_work (v_tail) (v_wanted) ((Base.bool_pick ((M.f_name_equal ((f_name (v_head))) (v_wanted))) ((Some (v_head))) (None)))))
and (* schema_stage.bend:321 *)
f_find_function : (M.t_Function) list -> Base.text -> (M.t_Function) option =
fun v_functions v_wanted ->
(f_find_function_work (v_functions) (v_wanted) (None))
and (* schema_stage.bend:324 *)
f_certified_if_named : bool -> M.t_Function -> M.t_Function -> bool =
fun v_same v_function v_source ->
(match v_same with
| false ->
false
| true ->
(Compare.f_compare (1048576) ([(Compare.FunctionPair (v_function, v_source))]) (true)))
and (* schema_stage.bend:331 *)
f_certified_function_work : (M.t_CheckedFunction) list -> M.t_Function -> bool -> bool =
fun v_checked v_source v_found ->
(match (v_checked, v_found) with
| (_, true) ->
true
| ([], false) ->
false
| (((M.CheckedFunction (v_function, v_signature, v_effects)) :: v_tail), false) ->
(f_certified_function_work (v_tail) (v_source) ((f_certified_if_named ((M.f_name_equal ((f_name (v_function))) ((f_name (v_source))))) (v_function) (v_source)))))
and (* schema_stage.bend:340 *)
f_certified_function : (M.t_CheckedFunction) list -> M.t_Function -> bool =
fun v_checked v_source ->
(f_certified_function_work (v_checked) (v_source) (false))
and (* schema_stage.bend:343 *)
f_node_catalog : (M.t_DataType) option -> Base.text -> (M.t_DataType) option =
fun v_found v_constructor ->
(match v_found with
| (Some (v_value)) ->
(match v_value with
| (M.DataType (v_identity, 2, ((M.Constructor (v_name, (Some ((M.ProductTy (((M.ParameterTy (0)) :: ((M.ParameterTy (1)) :: [])))))), v_fields)) :: []))) ->
(Base.bool_pick ((M.f_name_equal (v_name) (v_constructor))) ((Some (v_value))) (None))
| _ ->
None)
| None ->
None)
and (* schema_stage.bend:354 *)
f_terminal_catalog : (M.t_DataType) option -> (M.t_DataType) option =
fun v_found ->
(match v_found with
| (Some (v_value)) ->
(match v_value with
| (M.DataType (v_identity, 0, ((M.Constructor (v_name, None, v_fields)) :: []))) ->
(Some (v_value))
| _ ->
None)
| None ->
None)
and (* schema_stage.bend:365 *)
f_witness_catalog : (M.t_DataType) option -> Base.text -> (M.t_DataType) option =
fun v_found v_constructor ->
(match v_found with
| (Some (v_value)) ->
(match v_value with
| (M.DataType (v_identity, 1, ((M.Constructor (v_name, (Some ((M.ParameterTy (0)))), [])) :: []))) ->
(Base.bool_pick ((M.f_name_equal (v_name) (v_constructor))) ((Some (v_value))) (None))
| _ ->
None)
| None ->
None)
and (* schema_stage.bend:376 *)
f_type_identity : M.t_DataType -> M.t_TypeId =
fun v_value ->
(let (M.DataType (v_identity, v_parameters, v_constructors)) = v_value in
v_identity)
and (* schema_stage.bend:380 *)
f_constructor_identity : TD.t_ConstructorDefinition -> M.t_TypeId =
fun v_value ->
(let (TD.ConstructorDefinition (v_identity, v_parameters, v_payload)) = v_value in
v_identity)
and (* schema_stage.bend:384 *)
f_nominal_prefix : M.t_TypeId -> Base.text -> Base.text =
fun v_identity v_entry ->
(let (M.TypeId (v_module_name, v_declaration)) = v_identity in
(Base.string_append (Base.bool_pick ((M.f_name_equal (v_module_name) (s_2))) (s_3) ((Base.bool_pick ((M.f_name_equal (v_module_name) (v_entry))) (s_4) ((Base.string_append s_5 (Base.string_append v_module_name s_6)))))) v_declaration))
and (* schema_stage.bend:388 *)
f_method_name : M.t_TypeId -> Base.text -> Base.text -> Base.text =
fun v_identity v_entry v_member ->
(Base.string_append (f_nominal_prefix (v_identity) (v_entry)) (Base.string_append s_7 v_member))
and (* schema_stage.bend:391 *)
f_same_name : M.t_Function -> Base.text -> bool =
fun v_left v_right ->
(M.f_name_equal ((f_name (v_left))) (v_right))
and (* schema_stage.bend:394 *)
f_found_function : (M.t_Function) option -> (M.t_CheckedFunction) list -> (M.t_Function) option =
fun v_found v_checked ->
(match v_found with
| None ->
None
| (Some (v_function)) ->
(Base.bool_pick ((f_certified_function (v_checked) (v_function))) ((Some (v_function))) (None)))
and (* schema_stage.bend:401 *)
f_terminal_from_catalog : (M.t_DataType) option -> M.t_Function -> M.t_TypeId -> Base.text -> Base.text -> (M.t_CheckedFunction) list -> (t_Terminal) option =
fun v_found v_source v_identity v_member v_entry v_checked ->
(match v_found with
| (Some (v_ty)) ->
(Base.bool_pick ((Base.bool_and ((f_terminal (v_source))) ((Base.bool_and ((M.f_name_equal ((f_name (v_source))) ((f_method_name (v_identity) (v_entry) (v_member))))) ((f_certified_function (v_checked) (v_source))))))) ((Some ((Terminal (v_source, v_ty))))) (None))
| None ->
None)
and (* schema_stage.bend:408 *)
f_terminal_source : M.t_Function -> Base.text -> Base.text -> (M.t_DataType) list -> (M.t_CheckedFunction) list -> (t_Terminal) option =
fun v_function v_member v_entry v_types v_checked ->
(match v_function with
| v_source ->
(match v_source with
| (M.Function (v_name, v_exported, v_receiver, (Some ((M.AppliedTy (v_identity, [])))), v_result, v_body)) ->
(f_terminal_from_catalog ((f_terminal_catalog ((TD.f_lookup (v_types) (v_identity))))) (v_source) (v_identity) (v_member) (v_entry) (v_checked))
| _ ->
None))
and (* schema_stage.bend:417 *)
f_find_terminal_work : (M.t_Function) list -> (t_Terminal) option -> Base.text -> Base.text -> (M.t_DataType) list -> (M.t_CheckedFunction) list -> (t_Terminal) option =
fun v_functions v_found v_member v_entry v_types v_checked ->
(match (v_functions, v_found) with
| (_, (Some (v_pair))) ->
(Some (v_pair))
| ([], None) ->
None
| ((v_head :: v_tail), None) ->
(f_find_terminal_work (v_tail) ((f_terminal_source (v_head) (v_member) (v_entry) (v_types) (v_checked))) (v_member) (v_entry) (v_types) (v_checked)))
and (* schema_stage.bend:426 *)
f_find_terminal : (M.t_Function) list -> Base.text -> Base.text -> (M.t_DataType) list -> (M.t_CheckedFunction) list -> (t_Terminal) option =
fun v_functions v_member v_entry v_types v_checked ->
(f_find_terminal_work (v_functions) (None) (v_member) (v_entry) (v_types) (v_checked))
and (* schema_stage.bend:429 *)
f_matched_type_equality_found : (Base.text) option -> M.t_Function -> Base.text -> (M.t_CheckedFunction) list -> (M.t_Function) option =
fun v_found v_function v_constructor v_checked ->
(match v_found with
| None ->
None
| (Some (v_name)) ->
(Base.bool_pick ((Base.bool_and ((M.f_name_equal (v_name) (v_constructor))) ((f_certified_function (v_checked) (v_function))))) ((Some (v_function))) (None)))
and (* schema_stage.bend:436 *)
f_matched_type_equality : (M.t_Function) option -> Base.text -> (M.t_CheckedFunction) list -> (M.t_Function) option =
fun v_found v_constructor v_checked ->
(match v_found with
| None ->
None
| (Some (v_function)) ->
(f_matched_type_equality_found ((f_type_equality (v_function))) (v_function) (v_constructor) (v_checked)))
and (* schema_stage.bend:443 *)
f_matched_forwarder : (M.t_Function) option -> (M.t_CheckedFunction) list -> (M.t_Function) option =
fun v_found v_checked ->
(match v_found with
| None ->
None
| (Some (v_function)) ->
(Base.bool_pick ((Base.bool_and ((f_equality_forwarder (v_function))) ((f_certified_function (v_checked) (v_function))))) ((Some (v_function))) (None)))
and (* schema_stage.bend:450 *)
f_data_has_field : M.t_DataType -> Base.text -> bool =
fun v_data v_member ->
(let (M.DataType (v_identity, v_parameters, v_constructors)) = v_data in
(Members.f_has_field (v_constructors) (v_member)))
and (* schema_stage.bend:454 *)
f_capture_valid : M.t_Function -> t_NodeShape -> M.t_DataType -> M.t_DataType -> M.t_Function -> M.t_DataType -> M.t_Function -> M.t_Function -> Base.text -> (M.t_CheckedFunction) list -> (t_Evidence) option =
fun v_node_source v_shape v_node_data v_witness_data v_terminal_source v_terminal_data v_equality v_type_equality v_entry v_checked ->
(let (NodeShape (v_constructor, v_member, v_equality_name, v_witness_constructor)) = v_shape in
(let v_node_identity = (f_type_identity (v_node_data)) in
(let v_terminal_identity = (f_type_identity (v_terminal_data)) in
(let v_valid = (Base.bool_and ((Base.bool_not ((f_data_has_field (v_node_data) (v_member))))) ((Base.bool_and ((Base.bool_not ((f_data_has_field (v_terminal_data) (v_member))))) ((Base.bool_and ((M.f_name_equal ((f_name (v_node_source))) ((f_method_name (v_node_identity) (v_entry) (v_member))))) ((Base.bool_and ((M.f_name_equal ((f_name (v_terminal_source))) ((f_method_name (v_terminal_identity) (v_entry) (v_member))))) ((Base.bool_and ((f_certified_function (v_checked) (v_node_source))) ((Base.bool_and ((f_certified_function (v_checked) (v_equality))) ((f_certified_function (v_checked) (v_type_equality)))))))))))))) in
(Base.bool_pick (v_valid) ((Some ((Evidence (v_node_source, v_terminal_source, v_equality, v_type_equality, v_node_data, v_terminal_data, v_witness_data, v_constructor, v_terminal_identity, v_node_identity, v_member))))) (None))))))
and (* schema_stage.bend:461 *)
f_capture_dependencies : M.t_Function -> t_NodeShape -> M.t_DataType -> M.t_DataType -> (t_Terminal) option -> (M.t_Function) option -> (M.t_Function) option -> Base.text -> (M.t_CheckedFunction) list -> (t_Evidence) option =
fun v_node_source v_shape v_node_data v_witness_data v_terminal v_equality v_type_equality v_entry v_checked ->
(match (v_terminal, v_equality, v_type_equality) with
| ((Some ((Terminal (v_end_source, v_end_data)))), (Some (v_equal_source)), (Some (v_type_source))) ->
(f_capture_valid (v_node_source) (v_shape) (v_node_data) (v_witness_data) (v_end_source) (v_end_data) (v_equal_source) (v_type_source) (v_entry) (v_checked))
| (_, _, _) ->
None)
and (* schema_stage.bend:468 *)
f_capture_witness_data : (M.t_DataType) option -> M.t_Function -> t_NodeShape -> M.t_DataType -> (M.t_Function) list -> (M.t_DataType) list -> (M.t_CheckedFunction) list -> Base.text -> (t_Evidence) option =
fun v_found v_node_source v_shape v_node_data v_functions v_types v_checked v_entry ->
(match v_found with
| None ->
None
| (Some (v_witness_data)) ->
(let v_type_eq_name = (f_method_name ((f_type_identity (v_witness_data))) (v_entry) (s_0)) in
(f_capture_dependencies (v_node_source) (v_shape) (v_node_data) (v_witness_data) ((f_find_terminal (v_functions) ((f_node_member (v_shape))) (v_entry) (v_types) (v_checked))) ((f_matched_forwarder ((f_find_function (v_functions) ((f_node_equality (v_shape))))) (v_checked))) ((f_matched_type_equality ((f_find_function (v_functions) (v_type_eq_name))) ((f_witness_constructor (v_shape))) (v_checked))) (v_entry) (v_checked))))
and (* schema_stage.bend:476 *)
f_capture_witness : M.t_Function -> t_NodeShape -> M.t_DataType -> (TD.t_ConstructorDefinition) option -> (M.t_Function) list -> (M.t_DataType) list -> (M.t_CheckedFunction) list -> Base.text -> (t_Evidence) option =
fun v_node_source v_shape v_node_data v_found v_functions v_types v_checked v_entry ->
(match v_found with
| None ->
None
| (Some (v_definition)) ->
(f_capture_witness_data ((f_witness_catalog ((TD.f_lookup (v_types) ((f_constructor_identity (v_definition))))) ((f_witness_constructor (v_shape))))) (v_node_source) (v_shape) (v_node_data) (v_functions) (v_types) (v_checked) (v_entry)))
and (* schema_stage.bend:483 *)
f_capture_node_data : (M.t_DataType) option -> M.t_Function -> t_NodeShape -> (M.t_Function) list -> (M.t_DataType) list -> (M.t_CheckedFunction) list -> Base.text -> (t_Evidence) option =
fun v_found v_node_source v_shape v_functions v_types v_checked v_entry ->
(match v_found with
| None ->
None
| (Some (v_node_data)) ->
(f_capture_witness (v_node_source) (v_shape) (v_node_data) ((TD.f_constructor (v_types) ((f_witness_constructor (v_shape))))) (v_functions) (v_types) (v_checked) (v_entry)))
and (* schema_stage.bend:490 *)
f_capture_node : M.t_Function -> t_NodeShape -> (TD.t_ConstructorDefinition) option -> (M.t_Function) list -> (M.t_DataType) list -> (M.t_CheckedFunction) list -> Base.text -> (t_Evidence) option =
fun v_node_source v_shape v_found v_functions v_types v_checked v_entry ->
(match v_found with
| None ->
None
| (Some (v_definition)) ->
(f_capture_node_data ((f_node_catalog ((TD.f_lookup (v_types) ((f_constructor_identity (v_definition))))) ((f_node_constructor (v_shape))))) (v_node_source) (v_shape) (v_functions) (v_types) (v_checked) (v_entry)))
and (* schema_stage.bend:497 *)
f_capture_shape : (t_NodeShape) option -> M.t_Function -> (M.t_Function) list -> (M.t_DataType) list -> (M.t_CheckedFunction) list -> Base.text -> (t_Evidence) option =
fun v_found v_source v_functions v_types v_checked v_entry ->
(match v_found with
| None ->
None
| (Some (v_shape)) ->
(f_capture_node (v_source) (v_shape) ((TD.f_constructor (v_types) ((f_node_constructor (v_shape))))) (v_functions) (v_types) (v_checked) (v_entry)))
and (* schema_stage.bend:504 *)
f_capture_one : M.t_Function -> (M.t_Function) list -> (M.t_DataType) list -> (M.t_CheckedFunction) list -> Base.text -> (t_Evidence) option =
fun v_source v_functions v_types v_checked v_entry ->
(f_capture_shape ((f_node (v_source))) (v_source) (v_functions) (v_types) (v_checked) (v_entry))
and (* schema_stage.bend:507 *)
f_captured : (t_Evidence) option -> (t_Evidence) list -> (t_Evidence) list =
fun v_found v_rest ->
(match v_found with
| None ->
v_rest
| (Some (v_proof)) ->
(v_proof :: v_rest))
and (* schema_stage.bend:514 *)
f_capture_functions : (M.t_Function) list -> (M.t_Function) list -> (M.t_DataType) list -> (M.t_CheckedFunction) list -> Base.text -> (t_Evidence) list =
fun v_pending v_functions v_types v_checked v_entry ->
(match v_pending with
| [] ->
[]
| (v_source :: v_tail) ->
(f_captured ((f_capture_one (v_source) (v_functions) (v_types) (v_checked) (v_entry))) ((f_capture_functions (v_tail) (v_functions) (v_types) (v_checked) (v_entry)))))
and (* schema_stage.bend:521 *)
f_capture_checked_catalog : bool -> (M.t_Function) list -> (M.t_DataType) list -> (M.t_CheckedFunction) list -> Base.text -> (t_Evidence) list =
fun v_valid v_functions v_types v_checked_functions v_entry ->
(match v_valid with
| false ->
[]
| true ->
(f_capture_functions (v_functions) (v_functions) (v_types) (v_checked_functions) (v_entry)))
and (* schema_stage.bend:528 *)
f_capture : (M.t_Function) list -> (M.t_DataType) list -> M.t_CheckedModule -> Base.text -> (t_Evidence) list =
fun v_functions v_types v_checked v_entry ->
(let (M.CheckedModule (v_constants, v_checked_functions, v_checked_types, v_operations)) = v_checked in
(f_capture_checked_catalog ((Compare.f_compare (1048576) ([(Compare.DataTypeListPair (v_types, v_checked_types))]) (true))) (v_functions) (v_types) (v_checked_functions) (v_entry)))
and (* schema_stage.bend:532 *)
f_node_id : t_Evidence -> M.t_TypeId =
fun v_proof ->
(let (Evidence (v_node_method, v_terminal_method, v_equality, v_type_equality, v_node_type, v_terminal_type, v_witness_type, v_node_constructor, v_terminal_identity, v_node_identity, v_member)) = v_proof in
v_node_identity)
and (* schema_stage.bend:536 *)
f_terminal_id : t_Evidence -> M.t_TypeId =
fun v_proof ->
(let (Evidence (v_node_method, v_terminal_method, v_equality, v_type_equality, v_node_type, v_terminal_type, v_witness_type, v_node_constructor, v_terminal_identity, v_node_identity, v_member)) = v_proof in
v_terminal_identity)
and (* schema_stage.bend:540 *)
f_proof_member : t_Evidence -> Base.text =
fun v_proof ->
(let (Evidence (v_node_method, v_terminal_method, v_equality, v_type_equality, v_node_type, v_terminal_type, v_witness_type, v_node_constructor, v_terminal_identity, v_node_identity, v_member)) = v_proof in
v_member)
and (* schema_stage.bend:544 *)
f_proof_type_id : t_Evidence -> M.t_TypeId =
fun v_proof ->
(let (Evidence (v_node_method, v_terminal_method, v_equality, v_type_equality, v_node_type, v_terminal_type, v_witness_type, v_node_constructor, v_terminal_identity, v_node_identity, v_member)) = v_proof in
(f_type_identity (v_witness_type)))
and (* schema_stage.bend:548 *)
f_node_method : t_Evidence -> Base.text =
fun v_proof ->
(let (Evidence (v_node_method, v_terminal_method, v_equality, v_type_equality, v_node_type, v_terminal_type, v_witness_type, v_node_constructor, v_terminal_identity, v_node_identity, v_member)) = v_proof in
(f_name (v_node_method)))
and (* schema_stage.bend:552 *)
f_terminal_method : t_Evidence -> Base.text =
fun v_proof ->
(let (Evidence (v_node_method, v_terminal_method, v_equality, v_type_equality, v_node_type, v_terminal_type, v_witness_type, v_node_constructor, v_terminal_identity, v_node_identity, v_member)) = v_proof in
(f_name (v_terminal_method)))
and (* schema_stage.bend:556 *)
f_type_method : t_Evidence -> Base.text =
fun v_proof ->
(let (Evidence (v_node_method, v_terminal_method, v_equality, v_type_equality, v_node_type, v_terminal_type, v_witness_type, v_node_constructor, v_terminal_identity, v_node_identity, v_member)) = v_proof in
(f_name (v_type_equality)))
and (* schema_stage.bend:560 *)
f_method_matches : M.t_Ty -> Base.text -> t_Evidence -> bool =
fun v_left v_selected v_proof ->
(match v_left with
| (M.AppliedTy (v_identity, v_arguments)) ->
(Base.bool_or ((Base.bool_and ((M.f_type_id_equal (v_identity) ((f_node_id (v_proof))))) ((M.f_name_equal (v_selected) ((f_node_method (v_proof))))))) ((Base.bool_and ((M.f_type_id_equal (v_identity) ((f_terminal_id (v_proof))))) ((M.f_name_equal (v_selected) ((f_terminal_method (v_proof))))))))
| _ ->
false)
and (* schema_stage.bend:567 *)
f_exact_function : (M.t_Function) option -> M.t_Function -> bool =
fun v_found v_source ->
(match v_found with
| None ->
false
| (Some (v_current)) ->
(Compare.f_compare (1048576) ([(Compare.FunctionPair (v_current, v_source))]) (true)))
and (* schema_stage.bend:574 *)
f_exact_type : (M.t_DataType) option -> M.t_DataType -> bool =
fun v_found v_source ->
(match v_found with
| None ->
false
| (Some (v_current)) ->
(Compare.f_same_type (v_current) (v_source)))
and (* schema_stage.bend:581 *)
f_exact_sources : t_Evidence -> (M.t_Function) list -> (M.t_DataType) list -> bool =
fun v_proof v_functions v_types ->
(let (Evidence (v_node_method, v_terminal_method, v_equality, v_type_equality, v_node_type, v_terminal_type, v_witness_type, v_node_constructor, v_terminal_identity, v_node_identity, v_member)) = v_proof in
(Base.bool_and ((f_exact_function ((f_find_function (v_functions) ((f_name (v_node_method))))) (v_node_method))) ((Base.bool_and ((f_exact_function ((f_find_function (v_functions) ((f_name (v_terminal_method))))) (v_terminal_method))) ((Base.bool_and ((f_exact_function ((f_find_function (v_functions) ((f_name (v_equality))))) (v_equality))) ((Base.bool_and ((f_exact_function ((f_find_function (v_functions) ((f_name (v_type_equality))))) (v_type_equality))) ((Base.bool_and ((f_exact_type ((TD.f_lookup (v_types) ((f_type_identity (v_node_type))))) (v_node_type))) ((Base.bool_and ((f_exact_type ((TD.f_lookup (v_types) ((f_type_identity (v_terminal_type))))) (v_terminal_type))) ((f_exact_type ((TD.f_lookup (v_types) ((f_type_identity (v_witness_type))))) (v_witness_type)))))))))))))))
and (* schema_stage.bend:591 *)
f_type_key : (M.t_Diagnostic, Base.text) Base.result_ -> (Base.text) option =
fun v_found ->
(match v_found with
| (Done (v_key)) ->
(Some (v_key))
| (Fail (v_diagnostic)) ->
None)
and (* schema_stage.bend:598 *)
f_key : M.t_Ty -> (Base.text) option =
fun v_ty ->
(f_type_key ((State.f_type_key (65536) ((State.TypeKey ((State.f_witness (65536) (v_ty))))))))
and (* schema_stage.bend:607 *)
f_decide_chain : int -> t_ChainWork -> (bool) option =
fun v_fuel v_work ->
(match (v_fuel, v_work) with
| (0, _) ->
None
| (__nat_1, (Walk ((M.AppliedTy (v_identity, [])), v_wanted, v_proof, v_answer))) when __nat_1 >= 1 ->
(let v_rest = (__nat_1 - 1) in
(Base.bool_pick ((M.f_type_id_equal (v_identity) ((f_terminal_id (v_proof))))) ((Some (v_answer))) (None)))
| (__nat_2, (Walk ((M.AppliedTy (v_identity, (v_head :: (v_tail :: [])))), v_wanted, v_proof, v_answer))) when __nat_2 >= 1 ->
(let v_rest = (__nat_2 - 1) in
(f_decide_chain (v_rest) ((OnNode (v_head, v_tail, v_wanted, v_proof, (M.f_type_id_equal (v_identity) ((f_node_id (v_proof)))), v_answer)))))
| (__nat_3, (OnNode (v_head, v_tail, v_wanted, v_proof, false, v_answer))) when __nat_3 >= 1 ->
(let v_rest = (__nat_3 - 1) in
None)
| (__nat_4, (OnNode (v_head, v_tail, v_wanted, v_proof, true, v_answer))) when __nat_4 >= 1 ->
(let v_rest = (__nat_4 - 1) in
(f_decide_chain (v_rest) ((ComparedHead ((f_key (v_head)), v_wanted, v_tail, v_proof, v_answer)))))
| (__nat_5, (ComparedHead (None, v_wanted, v_tail, v_proof, v_answer))) when __nat_5 >= 1 ->
(let v_rest = (__nat_5 - 1) in
None)
| (__nat_6, (ComparedHead ((Some (v_head)), v_wanted, v_tail, v_proof, v_answer))) when __nat_6 >= 1 ->
(let v_rest = (__nat_6 - 1) in
(f_decide_chain (v_rest) ((Choose ((M.f_name_equal (v_head) (v_wanted)), v_tail, v_wanted, v_proof, v_answer)))))
| (__nat_7, (Choose (v_same, v_tail, v_wanted, v_proof, v_answer))) when __nat_7 >= 1 ->
(let v_rest = (__nat_7 - 1) in
(f_decide_chain (v_rest) ((Walk (v_tail, v_wanted, v_proof, (Base.bool_or (v_same) (v_answer)))))))
| (_, _) ->
None)
and (* schema_stage.bend:630 *)
f_decide_witness : (Base.text) option -> M.t_Ty -> t_Evidence -> (bool) option =
fun v_found v_left v_proof ->
(match v_found with
| None ->
None
| (Some (v_wanted)) ->
(f_decide_chain (65536) ((Walk (v_left, v_wanted, v_proof, false)))))
and (* schema_stage.bend:637 *)
f_decide_checked : bool -> M.t_Ty -> M.t_Ty -> t_Evidence -> (bool) option =
fun v_valid v_left v_witness v_proof ->
(match v_valid with
| false ->
None
| true ->
(f_decide_witness ((f_key (v_witness))) (v_left) (v_proof)))
and (* schema_stage.bend:644 *)
f_decide_ready : bool -> M.t_Ty -> M.t_Ty -> t_Evidence -> (M.t_Function) list -> (M.t_DataType) list -> (bool) option =
fun v_ready v_left v_witness v_proof v_functions v_types ->
(match v_ready with
| false ->
None
| true ->
(f_decide_checked ((f_exact_sources (v_proof) (v_functions) (v_types))) (v_left) (v_witness) (v_proof)))
and (* schema_stage.bend:651 *)
f_decide_one : t_Evidence -> Base.text -> Base.text -> M.t_Ty -> M.t_Ty -> (M.t_Function) list -> (M.t_DataType) list -> (bool) option =
fun v_proof v_selected v_member v_left v_result v_functions v_types ->
(match v_result with
| (M.FunctionTy (v_witness, M.BoolTy, (M.EffectRow ([], M.ClosedRow)))) ->
(f_decide_ready ((Base.bool_and ((M.f_name_equal (v_member) ((f_proof_member (v_proof))))) ((f_method_matches (v_left) (v_selected) (v_proof))))) (v_left) (v_witness) (v_proof) (v_functions) (v_types))
| _ ->
None)
and (* schema_stage.bend:660 *)
f_eligible_one : t_Evidence -> Base.text -> M.t_Ty -> bool =
fun v_proof v_member v_left ->
(let (Evidence (v_node_method, v_terminal_method, v_equality, v_type_equality, v_node_type, v_terminal_type, v_witness_type, v_node_constructor, v_terminal_identity, v_node_identity, v_expected)) = v_proof in
(match v_left with
| (M.AppliedTy (v_identity, (v_head :: (v_tail :: [])))) ->
(Base.bool_and ((M.f_name_equal (v_member) (v_expected))) ((M.f_type_id_equal (v_identity) (v_node_identity))))
| (M.AppliedTy (v_identity, [])) ->
(Base.bool_and ((M.f_name_equal (v_member) (v_expected))) ((M.f_type_id_equal (v_identity) (v_terminal_identity))))
| _ ->
false))
and (* schema_stage.bend:670 *)
f_eligible_work : (t_Evidence) list -> Base.text -> M.t_Ty -> bool -> bool =
fun v_proofs v_member v_left v_found ->
(match (v_proofs, v_found) with
| (_, true) ->
true
| ([], false) ->
false
| ((v_head :: v_tail), false) ->
(f_eligible_work (v_tail) (v_member) (v_left) ((f_eligible_one (v_head) (v_member) (v_left)))))
and (* schema_stage.bend:679 *)
f_eligible : (t_Evidence) list -> Base.text -> M.t_Ty -> bool =
fun v_proofs v_member v_left ->
(f_eligible_work (v_proofs) (v_member) (v_left) (false))
and (* schema_stage.bend:686 *)
f_decide_search : int -> t_Search -> (bool) option =
fun v_fuel v_work ->
(match (v_fuel, v_work) with
| (0, _) ->
None
| (__nat_8, (Scan ([], v_selected, v_member, v_left, v_result, v_functions, v_types))) when __nat_8 >= 1 ->
(let v_rest = (__nat_8 - 1) in
None)
| (__nat_9, (Scan ((v_head :: v_tail), v_selected, v_member, v_left, v_result, v_functions, v_types))) when __nat_9 >= 1 ->
(let v_rest = (__nat_9 - 1) in
(f_decide_search (v_rest) ((Chosen ((f_decide_one (v_head) (v_selected) (v_member) (v_left) (v_result) (v_functions) (v_types)), v_tail, v_selected, v_member, v_left, v_result, v_functions, v_types)))))
| (__nat_10, (Chosen ((Some (v_answer)), v_remaining, v_selected, v_member, v_left, v_result, v_functions, v_types))) when __nat_10 >= 1 ->
(let v_rest = (__nat_10 - 1) in
(Some (v_answer)))
| (__nat_11, (Chosen (None, v_remaining, v_selected, v_member, v_left, v_result, v_functions, v_types))) when __nat_11 >= 1 ->
(let v_rest = (__nat_11 - 1) in
(f_decide_search (v_rest) ((Scan (v_remaining, v_selected, v_member, v_left, v_result, v_functions, v_types))))))
and (* schema_stage.bend:699 *)
f_decide : (t_Evidence) list -> Base.text -> Base.text -> M.t_Ty -> M.t_Ty -> (M.t_Function) list -> (M.t_DataType) list -> (bool) option =
fun v_proofs v_selected v_member v_left v_result v_functions v_types ->
(f_decide_search (65536) ((Scan (v_proofs, v_selected, v_member, v_left, v_result, v_functions, v_types))))
