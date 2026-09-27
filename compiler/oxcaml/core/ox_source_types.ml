(* Native semantic port of compiler/source_types.bend.

   Source SHA-256: 75d39d661722b09825650a86ec63ee18b54d65765d394a10b71054ac1be6d624

   Ownership/type arguments are erased; value types are checked by OCaml.

   No Bend interpreter or generated C/JavaScript is linked. *)

open Base

module M = Ox_model

module C = Ox_cst

module Index = Ox_index

module A = Ox_source_arguments

type t_Header =
  | Header of Base.text * M.t_TypeId * (A.t_Pattern) list
and t_VariableKind =
  | TypeKind
  | RowKind
and t_Variable =
  | Variable of Base.text * M.t_Ty * t_VariableKind
and t_NodeKind =
  | Expression
  | Application
  | Wrapper
  | Group
  | ArrayNode
  | RecordNode
  | FieldNode
  | InfixNode
  | PrefixNode
  | Name
and t_Work =
  | Node of t_NodeKind * C.t_Cst
  | Nodes of (C.t_Cst) list
  | Field of C.t_Cst * (C.t_Cst) list
  | Infix of C.t_Cst * (C.t_Cst) list
  | Prefix of C.t_Cst * (C.t_Cst) list
and t_RowLabel =
  | RowLabel of Base.text * (C.t_Cst) list * C.t_Cst
and t_Split =
  | Split of (A.t_Value) list * (A.t_Value) list
and t_VariableScan =
  | VariableScan of (C.t_Cst) list * bool

let s_0 = Base.text_of_utf8 "type_expression"

let s_1 = Base.text_of_utf8 "effect_signature"

let s_2 = Base.text_of_utf8 "type_application"

let s_3 = Base.text_of_utf8 "application"

let s_4 = Base.text_of_utf8 "effect_signature_application"

let s_5 = Base.text_of_utf8 "type_atom"

let s_6 = Base.text_of_utf8 "atom"

let s_7 = Base.text_of_utf8 "expression"

let s_8 = Base.text_of_utf8 "effect_signature_atom"

let s_9 = Base.text_of_utf8 "type_group"

let s_10 = Base.text_of_utf8 "group"

let s_11 = Base.text_of_utf8 "type_array"

let s_12 = Base.text_of_utf8 "array"

let s_13 = Base.text_of_utf8 "type_record"

let s_14 = Base.text_of_utf8 "record_values"

let s_15 = Base.text_of_utf8 "type_field"

let s_16 = Base.text_of_utf8 "record_value"

let s_17 = Base.text_of_utf8 "infix_expression"

let s_18 = Base.text_of_utf8 "prefix_expression"

let s_19 = Base.text_of_utf8 "internal_cst"

let s_20 = Base.text_of_utf8 "parser"

let s_21 = Base.text_of_utf8 "expected one type value"

let s_22 = Base.text_of_utf8 "Array"

let s_23 = Base.text_of_utf8 "empty function type"

let s_24 = Base.text_of_utf8 "->"

let s_25 = Base.text_of_utf8 "type_argument"

let s_26 = Base.text_of_utf8 "effect application exceeds the source-tree limit"

let s_27 = Base.text_of_utf8 "head"

let s_28 = Base.text_of_utf8 "arguments"

let s_29 = Base.text_of_utf8 "value"

let s_30 = Base.text_of_utf8 "results"

let s_31 = Base.text_of_utf8 "effects"

let s_32 = Base.text_of_utf8 "unknown_effect"

let s_33 = Base.text_of_utf8 "effect rows require a declared operation or family application"

let s_34 = Base.text_of_utf8 "labels"

let s_35 = Base.text_of_utf8 "effect row lost its type arguments"

let s_36 = Base.text_of_utf8 "tail"

let s_37 = Base.text_of_utf8 "effect_instance"

let s_38 = Base.text_of_utf8 "unsupported_polymorphic_effect_label"

let s_39 = Base.text_of_utf8 "open rows currently require concrete effect operation labels"

let s_40 = Base.text_of_utf8 "invalid_effect_annotation"

let s_41 = Base.text_of_utf8 "effect row tail has no row-variable binding"

let s_42 = Base.text_of_utf8 "effect row has more than one tail"

let s_43 = Base.text_of_utf8 "expected one effect row"

let s_44 = Base.text_of_utf8 "an effect row annotates a function arrow, not a value type"

let s_45 = Base.text_of_utf8 "type source tree exhausted its node-count bound"

let s_46 = Base.text_of_utf8 "elements"

let s_47 = Base.text_of_utf8 "fields"

let s_48 = Base.text_of_utf8 "name"

let s_49 = Base.text_of_utf8 "tails"

let s_50 = Base.text_of_utf8 "operator"

let s_51 = Base.text_of_utf8 "type arguments cannot contain value operators"

let s_52 = Base.text_of_utf8 ""

let s_53 = Base.text_of_utf8 "invalid type annotation field"

let s_54 = Base.text_of_utf8 "annotation_kind_mismatch"

let s_55 = Base.text_of_utf8 "one annotation name cannot be both a type and an effect-row variable"

let s_56 = Base.text_of_utf8 "operation"

let s_57 = Base.text_of_utf8 "kind"

let s_58 = Base.text_of_utf8 "invalid row tail field"

let s_59 = Base.text_of_utf8 "annotation scope exceeds the source-tree limit"

let s_60 = Base.text_of_utf8 "effect_row"

let s_61 = Base.text_of_utf8 "constraint_predicate"

let s_62 = Base.text_of_utf8 "IDENT"

let rec (* source_types.bend:36 *)
f_classify : Base.text -> t_NodeKind =
fun v_kind ->
(Base.bool_pick ((Base.bool_or ((M.f_name_equal (v_kind) (s_0))) ((M.f_name_equal (v_kind) (s_1))))) (Expression) ((Base.bool_pick ((Base.bool_or ((M.f_name_equal (v_kind) (s_2))) ((Base.bool_or ((M.f_name_equal (v_kind) (s_3))) ((M.f_name_equal (v_kind) (s_4))))))) (Application) ((Base.bool_pick ((Base.bool_or ((M.f_name_equal (v_kind) (s_5))) ((Base.bool_or ((M.f_name_equal (v_kind) (s_6))) ((Base.bool_or ((M.f_name_equal (v_kind) (s_7))) ((M.f_name_equal (v_kind) (s_8))))))))) (Wrapper) ((Base.bool_pick ((Base.bool_or ((M.f_name_equal (v_kind) (s_9))) ((M.f_name_equal (v_kind) (s_10))))) (Group) ((Base.bool_pick ((Base.bool_or ((M.f_name_equal (v_kind) (s_11))) ((M.f_name_equal (v_kind) (s_12))))) (ArrayNode) ((Base.bool_pick ((Base.bool_or ((M.f_name_equal (v_kind) (s_13))) ((M.f_name_equal (v_kind) (s_14))))) (RecordNode) ((Base.bool_pick ((Base.bool_or ((M.f_name_equal (v_kind) (s_15))) ((M.f_name_equal (v_kind) (s_16))))) (FieldNode) ((Base.bool_pick ((M.f_name_equal (v_kind) (s_17))) (InfixNode) ((Base.bool_pick ((M.f_name_equal (v_kind) (s_18))) (PrefixNode) (Name))))))))))))))))))
and (* source_types.bend:47 *)
f_visit : C.t_Cst -> t_Work =
fun v_node ->
(Node ((f_classify ((C.f_kind_of (v_node)))), v_node))
and (* source_types.bend:50 *)
f_one : (M.t_Ty) list -> (M.t_Diagnostic, M.t_Ty) Base.result_ =
fun v_types ->
(A.f_one (v_types))
and (* source_types.bend:53 *)
f_one_value : (A.t_Value) list -> (M.t_Diagnostic, A.t_Value) Base.result_ =
fun v_values ->
(match v_values with
| (v_value :: []) ->
(Done (v_value))
| _ ->
(Fail ((M.Diagnostic (s_19, s_20, s_21)))))
and (* source_types.bend:60 *)
f_grouped : (A.t_Value) list -> A.t_Value =
fun v_values ->
(match v_values with
| (v_value :: []) ->
v_value
| v_values ->
(A.TupleValue (v_values)))
and (* source_types.bend:67 *)
f_lookup_variable : (t_Variable) list -> Base.text -> (M.t_Ty) option =
fun v_variables v_name ->
(match v_variables with
| [] ->
None
| ((Variable (v_source, v_value, TypeKind)) :: v_rest) ->
(Base.bool_pick ((M.f_name_equal (v_source) (v_name))) ((Some (v_value))) ((f_lookup_variable (v_rest) (v_name))))
| ((Variable (v_source, v_value, RowKind)) :: v_rest) ->
(f_lookup_variable (v_rest) (v_name)))
and (* source_types.bend:76 *)
f_lookup_row : (t_Variable) list -> Base.text -> (M.t_RowTail) option =
fun v_variables v_name ->
(match v_variables with
| [] ->
None
| ((Variable (v_source, (M.FreeTy (v_scope, v_variable)), RowKind)) :: v_rest) ->
(Base.bool_pick ((M.f_name_equal (v_source) (v_name))) ((Some ((M.FreeRow (v_scope, v_variable))))) ((f_lookup_row (v_rest) (v_name))))
| (v_head :: v_rest) ->
(f_lookup_row (v_rest) (v_name)))
and (* source_types.bend:85 *)
f_lookup_header : (t_Header) Base.map -> Base.text -> (t_Header) option =
fun v_headers v_name ->
(Index.f_find (v_headers) (v_name))
and (* source_types.bend:88 *)
f_builtin : bool -> C.t_Cst -> (M.t_Diagnostic, A.t_Value) Base.result_ =
fun v_array v_node ->
(match v_array with
| true ->
(Done (A.ArrayConstructorValue))
| false ->
(match (C.f_scalar_type (v_node)) with
| Fail __error -> Fail __error
| Done v_ty ->
(Done ((A.Concrete (v_ty))))))
and (* source_types.bend:97 *)
f_named : (t_Header) option -> (M.t_Ty) option -> C.t_Cst -> (M.t_Diagnostic, A.t_Value) Base.result_ =
fun v_found v_variable v_node ->
(match (v_found, v_variable) with
| ((Some ((Header (v_source, v_identity, v_parameters)))), (Some ((M.FreeTy (v_scope, v_name))))) ->
(Done ((A.f_constructor (v_parameters) (v_identity) ([]))))
| (_, (Some (v_ty))) ->
(Done ((A.Concrete (v_ty))))
| ((Some ((Header (v_source, v_identity, v_parameters)))), None) ->
(Done ((A.f_constructor (v_parameters) (v_identity) ([]))))
| (None, None) ->
(f_builtin ((M.f_name_equal ((C.f_type_name (v_node))) (s_22))) (v_node)))
and (* source_types.bend:108 *)
f_arrow : (M.t_Ty) list -> (M.t_Diagnostic, M.t_Ty) Base.result_ =
fun v_types ->
(match v_types with
| [] ->
(Fail ((M.Diagnostic (s_19, s_20, s_23))))
| (v_head :: []) ->
(Done (v_head))
| (v_head :: (v_next :: v_tail)) ->
(match (f_arrow ((v_next :: v_tail))) with
| Fail __error -> Fail __error
| Done v_result ->
(Done ((M.FunctionTy (v_head, v_result, (M.f_empty_row ())))))))
and (* source_types.bend:119 *)
f_without_arrows : (C.t_Cst) list -> (C.t_Cst) list =
fun v_nodes ->
(match v_nodes with
| [] ->
[]
| (v_head :: v_tail) ->
(let v_rest = (f_without_arrows (v_tail)) in
(Base.bool_pick ((M.f_name_equal ((C.f_kind_of (v_head))) (s_24))) (v_rest) ((v_head :: v_rest)))))
and (* source_types.bend:132 *)
f_row_label : int -> t_Work -> (C.t_Cst) list -> C.t_Cst -> (M.t_Diagnostic, t_RowLabel) Base.result_ =
fun v_fuel v_work v_arguments v_original ->
(match (v_fuel, v_work) with
| (0, _) ->
(Fail ((C.f_diagnostic (v_original) (s_25) (s_26))))
| (__nat_1, (Node (Application, v_node))) when __nat_1 >= 1 ->
(let v_rest = (__nat_1 - 1) in
(f_row_label (v_rest) ((Nodes ((C.f_field_values (v_node) (s_27))))) ((Base.list_append ((C.f_field_values (v_node) (s_28))) (v_arguments))) (v_original)))
| (__nat_2, (Node (Wrapper, v_node))) when __nat_2 >= 1 ->
(let v_rest = (__nat_2 - 1) in
(f_row_label (v_rest) ((Nodes ((C.f_children_of (v_node))))) (v_arguments) (v_original)))
| (__nat_3, (Node (Group, v_node))) when __nat_3 >= 1 ->
(let v_rest = (__nat_3 - 1) in
(f_row_label (v_rest) ((Nodes ((C.f_field_values (v_node) (s_29))))) (v_arguments) (v_original)))
| (__nat_4, (Node (Expression, v_node))) when __nat_4 >= 1 ->
(let v_rest = (__nat_4 - 1) in
(let v_children = (Base.bool_pick ((Base.bool_and ((Base.list_is_empty ((C.f_field_values (v_node) (s_30))))) ((Base.list_is_empty ((C.f_field_values (v_node) (s_31))))))) ((C.f_field_values (v_node) (s_27))) ([])) in
(f_row_label (v_rest) ((Nodes (v_children))) (v_arguments) (v_original))))
| (__nat_5, (Nodes ((v_node :: [])))) when __nat_5 >= 1 ->
(let v_rest = (__nat_5 - 1) in
(f_row_label (v_rest) ((f_visit (v_node))) (v_arguments) (v_original)))
| (__nat_6, (Node (Name, v_node))) when __nat_6 >= 1 ->
(let v_rest = (__nat_6 - 1) in
(Done ((RowLabel ((C.f_type_name (v_node)), v_arguments, v_original)))))
| (_, _) ->
(Fail ((C.f_diagnostic (v_original) (s_32) (s_33)))))
and (* source_types.bend:152 *)
f_row_applications : (C.t_Cst) list -> int -> (M.t_Diagnostic, (t_RowLabel) list) Base.result_ =
fun v_nodes v_fuel ->
(match v_nodes with
| [] ->
(Done ([]))
| (v_node :: v_tail) ->
(match (f_row_label (v_fuel) ((f_visit (v_node))) ([]) (v_node)) with
| Fail __error -> Fail __error
| Done v_label ->
(match (f_row_applications (v_tail) (v_fuel)) with
| Fail __error -> Fail __error
| Done v_following ->
(Done ((v_label :: v_following))))))
and (* source_types.bend:162 *)
f_row_nodes : (C.t_Cst) list -> (C.t_Cst) list =
fun v_nodes ->
(match v_nodes with
| [] ->
[]
| (v_node :: v_tail) ->
(Base.list_append ((C.f_field_values (v_node) (s_34))) ((f_row_nodes (v_tail)))))
and (* source_types.bend:169 *)
f_row_argument_nodes : (t_RowLabel) list -> (C.t_Cst) list =
fun v_nodes ->
(match v_nodes with
| [] ->
[]
| ((RowLabel (v_name, v_arguments, v_node)) :: v_tail) ->
(Base.list_append (v_arguments) ((f_row_argument_nodes (v_tail)))))
and (* source_types.bend:179 *)
f_split_arguments : t_Split -> (A.t_Value) list =
fun v_value ->
(let (Split (v_arguments, v_following)) = v_value in
v_arguments)
and (* source_types.bend:183 *)
f_split_following : t_Split -> (A.t_Value) list =
fun v_value ->
(let (Split (v_arguments, v_following)) = v_value in
v_following)
and (* source_types.bend:187 *)
f_split : int -> (A.t_Value) list -> (M.t_Diagnostic, t_Split) Base.result_ =
fun v_count v_values ->
(match (v_count, v_values) with
| (0, v_values) ->
(Done ((Split ([], v_values))))
| (__nat_7, (v_head :: v_tail)) when __nat_7 >= 1 ->
(let v_rest = (__nat_7 - 1) in
(match (f_split (v_rest) (v_tail)) with
| Fail __error -> Fail __error
| Done v_parts ->
(Done ((Split ((v_head :: (f_split_arguments (v_parts))), (f_split_following (v_parts))))))))
| (_, _) ->
(Fail ((M.Diagnostic (s_19, s_20, s_35)))))
and (* source_types.bend:198 *)
f_row_labels : 'scope. ('scope -> (Base.text -> ((A.t_Value) list -> (C.t_Cst -> (M.t_Diagnostic, (M.t_TypeId) list) Base.result_)))) -> (t_RowLabel) list -> (A.t_Value) list -> 'scope -> (M.t_Diagnostic, (M.t_TypeId) list) Base.result_ =
fun v_resolve_effect v_nodes v_values v_scope ->
(match v_nodes with
| [] ->
(Done ([]))
| ((RowLabel (v_name, v_arguments, v_node)) :: v_tail) ->
(match (f_split ((Base.list_length (v_arguments))) (v_values)) with
| Fail __error -> Fail __error
| Done v_parts ->
(match (v_resolve_effect (v_scope) (v_name) ((f_split_arguments (v_parts))) (v_node)) with
| Fail __error -> Fail __error
| Done v_identities ->
(match (f_row_labels (v_resolve_effect) (v_tail) ((f_split_following (v_parts))) (v_scope)) with
| Fail __error -> Fail __error
| Done v_remaining ->
(Done ((Base.list_append (v_identities) (v_remaining))))))))
and (* source_types.bend:209 *)
f_row_has_tail : (C.t_Cst) list -> bool =
fun v_nodes ->
(match v_nodes with
| [] ->
false
| (v_node :: v_tail) ->
(Base.bool_or ((C.f_present ((C.f_field_values (v_node) (s_36))))) ((f_row_has_tail (v_tail)))))
and (* source_types.bend:216 *)
f_checked_row_labels : (M.t_Diagnostic, (M.t_TypeId) list) Base.result_ -> (C.t_Cst) list -> (M.t_Diagnostic, (M.t_TypeId) list) Base.result_ =
fun v_found v_rows ->
(match (v_found, v_rows) with
| ((Done (v_labels)), _) ->
(Done (v_labels))
| ((Fail ((M.Diagnostic (v_code, v_subject, v_message)))), (v_row :: v_tail)) ->
(Base.bool_pick ((Base.bool_and ((M.f_name_equal (v_code) (s_37))) ((f_row_has_tail ((v_row :: v_tail)))))) ((Fail ((C.f_diagnostic (v_row) (s_38) (s_39))))) ((Fail ((M.Diagnostic (v_code, v_subject, v_message))))))
| ((Fail (v_error)), []) ->
(Fail (v_error)))
and (* source_types.bend:225 *)
f_row_tail_found : (M.t_RowTail) option -> C.t_Cst -> (M.t_Diagnostic, M.t_RowTail) Base.result_ =
fun v_found v_name ->
(match v_found with
| (Some (v_row)) ->
(Done (v_row))
| None ->
(Fail ((C.f_diagnostic (v_name) (s_40) (s_41)))))
and (* source_types.bend:232 *)
f_row_tail_names : (C.t_Cst) list -> (t_Variable) list -> C.t_Cst -> (M.t_Diagnostic, M.t_RowTail) Base.result_ =
fun v_nodes v_variables v_node ->
(match v_nodes with
| [] ->
(Done (M.ClosedRow))
| (v_name :: []) ->
(f_row_tail_found ((f_lookup_row (v_variables) ((C.f_text_of (v_name))))) (v_name))
| _ ->
(Fail ((C.f_diagnostic (v_node) (s_40) (s_42)))))
and (* source_types.bend:241 *)
f_row_tail : (C.t_Cst) list -> (t_Variable) list -> (M.t_Diagnostic, M.t_RowTail) Base.result_ =
fun v_nodes v_variables ->
(match v_nodes with
| [] ->
(Done (M.ClosedRow))
| (v_node :: []) ->
(f_row_tail_names ((C.f_field_values (v_node) (s_36))) (v_variables) (v_node))
| _ ->
(Fail ((M.Diagnostic (s_19, s_20, s_43)))))
and (* source_types.bend:250 *)
f_with_row : (C.t_Cst) list -> M.t_Ty -> (M.t_TypeId) list -> (t_Variable) list -> C.t_Cst -> (M.t_Diagnostic, M.t_Ty) Base.result_ =
fun v_nodes v_ty v_labels v_variables v_node ->
(match (v_nodes, v_ty) with
| ([], v_ty) ->
(Done (v_ty))
| (_, (M.FunctionTy (v_parameter, v_result, v_previous))) ->
(match (f_row_tail (v_nodes) (v_variables)) with
| Fail __error -> Fail __error
| Done v_tail ->
(Done ((M.FunctionTy (v_parameter, v_result, (M.EffectRow (v_labels, v_tail)))))))
| (_, _) ->
(Fail ((C.f_diagnostic (v_node) (s_40) (s_44)))))
and (* source_types.bend:261 *)
f_expression_value : (A.t_Value) list -> (C.t_Cst) list -> (M.t_TypeId) list -> (t_Variable) list -> C.t_Cst -> (M.t_Diagnostic, (A.t_Value) list) Base.result_ =
fun v_values v_effects v_labels v_variables v_node ->
(match (v_values, v_effects) with
| ((v_value :: []), []) ->
(Done ([v_value]))
| (v_values, _) ->
(match (A.f_types (65536) ((A.ValueTypes (v_values))) (v_node)) with
| Fail __error -> Fail __error
| Done v_types ->
(match (f_arrow (v_types)) with
| Fail __error -> Fail __error
| Done v_ty ->
(match (f_with_row (v_effects) (v_ty) (v_labels) (v_variables) (v_node)) with
| Fail __error -> Fail __error
| Done v_annotated ->
(Done ([(A.Concrete (v_annotated))]))))))
and (* source_types.bend:272 *)
f_evaluate : 'scope. ('scope -> (Base.text -> ((A.t_Value) list -> (C.t_Cst -> (M.t_Diagnostic, (M.t_TypeId) list) Base.result_)))) -> int -> t_Work -> (t_Header) Base.map -> (t_Variable) list -> 'scope -> (M.t_Diagnostic, (A.t_Value) list) Base.result_ =
fun v_resolve_effect v_fuel v_work v_headers v_variables v_scope ->
(match (v_fuel, v_work) with
| (0, _) ->
(Fail ((M.Diagnostic (s_25, s_20, s_45))))
| (__nat_8, (Nodes ([]))) when __nat_8 >= 1 ->
(let v_remaining = (__nat_8 - 1) in
(Done ([])))
| (__nat_9, (Nodes ((v_head :: v_tail)))) when __nat_9 >= 1 ->
(let v_remaining = (__nat_9 - 1) in
(match (f_evaluate (v_resolve_effect) (v_remaining) ((f_visit (v_head))) (v_headers) (v_variables) (v_scope)) with
| Fail __error -> Fail __error
| Done v_first ->
(match (f_evaluate (v_resolve_effect) (v_remaining) ((Nodes (v_tail))) (v_headers) (v_variables) (v_scope)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done ((Base.list_append (v_first) (v_rest)))))))
| (__nat_10, (Node (Expression, v_node))) when __nat_10 >= 1 ->
(let v_remaining = (__nat_10 - 1) in
(match (f_evaluate (v_resolve_effect) (v_remaining) ((Nodes ((Base.list_append ((C.f_field_values (v_node) (s_27))) ((f_without_arrows ((C.f_field_values (v_node) (s_30))))))))) (v_headers) (v_variables) (v_scope)) with
| Fail __error -> Fail __error
| Done v_values ->
(match (Done ((C.f_field_values (v_node) (s_31)))) with
| Fail __error -> Fail __error
| Done v_effects ->
(match (f_row_applications ((f_row_nodes (v_effects))) (v_remaining)) with
| Fail __error -> Fail __error
| Done v_labels ->
(match (f_evaluate (v_resolve_effect) (v_remaining) ((Nodes ((f_row_argument_nodes (v_labels))))) (v_headers) (v_variables) (v_scope)) with
| Fail __error -> Fail __error
| Done v_arguments ->
(match (f_checked_row_labels ((f_row_labels (v_resolve_effect) (v_labels) (v_arguments) (v_scope))) (v_effects)) with
| Fail __error -> Fail __error
| Done v_identities ->
(f_expression_value (v_values) (v_effects) (v_identities) (v_variables) (v_node))))))))
| (__nat_11, (Node (Application, v_node))) when __nat_11 >= 1 ->
(let v_remaining = (__nat_11 - 1) in
(match (C.f_one ((C.f_field_values (v_node) (s_27)))) with
| Fail __error -> Fail __error
| Done v_head ->
(match (f_evaluate (v_resolve_effect) (v_remaining) ((f_visit (v_head))) (v_headers) (v_variables) (v_scope)) with
| Fail __error -> Fail __error
| Done v_values ->
(match (f_one_value (v_values)) with
| Fail __error -> Fail __error
| Done v_callee ->
(match (f_evaluate (v_resolve_effect) (v_remaining) ((Nodes ((C.f_field_values (v_node) (s_28))))) (v_headers) (v_variables) (v_scope)) with
| Fail __error -> Fail __error
| Done v_arguments ->
(match (A.f_apply (v_arguments) (v_callee) (v_node)) with
| Fail __error -> Fail __error
| Done v_value ->
(Done ([v_value]))))))))
| (__nat_12, (Node (Wrapper, v_node))) when __nat_12 >= 1 ->
(let v_remaining = (__nat_12 - 1) in
(match (C.f_one ((C.f_children_of (v_node)))) with
| Fail __error -> Fail __error
| Done v_child ->
(f_evaluate (v_resolve_effect) (v_remaining) ((f_visit (v_child))) (v_headers) (v_variables) (v_scope))))
| (__nat_13, (Node (Group, v_node))) when __nat_13 >= 1 ->
(let v_remaining = (__nat_13 - 1) in
(match (f_evaluate (v_resolve_effect) (v_remaining) ((Nodes ((C.f_field_values (v_node) (s_29))))) (v_headers) (v_variables) (v_scope)) with
| Fail __error -> Fail __error
| Done v_elements ->
(Done ([(f_grouped (v_elements))]))))
| (__nat_14, (Node (ArrayNode, v_node))) when __nat_14 >= 1 ->
(let v_remaining = (__nat_14 - 1) in
(match (f_evaluate (v_resolve_effect) (v_remaining) ((Nodes ((C.f_field_values (v_node) (s_46))))) (v_headers) (v_variables) (v_scope)) with
| Fail __error -> Fail __error
| Done v_elements ->
(Done ([(A.ArrayValue (v_elements))]))))
| (__nat_15, (Node (RecordNode, v_node))) when __nat_15 >= 1 ->
(let v_remaining = (__nat_15 - 1) in
(match (Done ((C.f_field_values (v_node) (s_47)))) with
| Fail __error -> Fail __error
| Done v_fields ->
(match (A.f_field_names (v_fields)) with
| Fail __error -> Fail __error
| Done v_names ->
(match (A.f_unique (v_names) (v_node)) with
| Fail __error -> Fail __error
| Done v_valid ->
(match (f_evaluate (v_resolve_effect) (v_remaining) ((Nodes (v_fields))) (v_headers) (v_variables) (v_scope)) with
| Fail __error -> Fail __error
| Done v_values ->
(Done ([(A.RecordValue (v_names, v_values))])))))))
| (__nat_16, (Node (FieldNode, v_node))) when __nat_16 >= 1 ->
(let v_remaining = (__nat_16 - 1) in
(f_evaluate (v_resolve_effect) (v_remaining) ((Field (v_node, (C.f_field_values (v_node) (s_29))))) (v_headers) (v_variables) (v_scope)))
| (__nat_17, (Field (v_node, []))) when __nat_17 >= 1 ->
(let v_remaining = (__nat_17 - 1) in
(f_evaluate (v_resolve_effect) (v_remaining) ((Nodes ((C.f_field_values (v_node) (s_48))))) (v_headers) (v_variables) (v_scope)))
| (__nat_18, (Field (v_node, v_values))) when __nat_18 >= 1 ->
(let v_remaining = (__nat_18 - 1) in
(f_evaluate (v_resolve_effect) (v_remaining) ((Nodes (v_values))) (v_headers) (v_variables) (v_scope)))
| (__nat_19, (Node (InfixNode, v_node))) when __nat_19 >= 1 ->
(let v_remaining = (__nat_19 - 1) in
(f_evaluate (v_resolve_effect) (v_remaining) ((Infix (v_node, (C.f_field_values (v_node) (s_49))))) (v_headers) (v_variables) (v_scope)))
| (__nat_20, (Infix (v_node, []))) when __nat_20 >= 1 ->
(let v_remaining = (__nat_20 - 1) in
(f_evaluate (v_resolve_effect) (v_remaining) ((Nodes ((C.f_field_values (v_node) (s_27))))) (v_headers) (v_variables) (v_scope)))
| (__nat_21, (Node (PrefixNode, v_node))) when __nat_21 >= 1 ->
(let v_remaining = (__nat_21 - 1) in
(f_evaluate (v_resolve_effect) (v_remaining) ((Prefix (v_node, (C.f_field_values (v_node) (s_50))))) (v_headers) (v_variables) (v_scope)))
| (__nat_22, (Prefix (v_node, []))) when __nat_22 >= 1 ->
(let v_remaining = (__nat_22 - 1) in
(f_evaluate (v_resolve_effect) (v_remaining) ((Nodes ((C.f_field_values (v_node) (s_29))))) (v_headers) (v_variables) (v_scope)))
| (__nat_23, (Node (Name, v_node))) when __nat_23 >= 1 ->
(let v_remaining = (__nat_23 - 1) in
(match (f_named ((f_lookup_header (v_headers) ((C.f_type_name (v_node))))) ((f_lookup_variable (v_variables) ((C.f_type_name (v_node))))) (v_node)) with
| Fail __error -> Fail __error
| Done v_value ->
(Done ([v_value]))))
| (_, (Infix (v_node, v_tails))) ->
(Fail ((C.f_diagnostic (v_node) (s_25) (s_51))))
| (_, (Prefix (v_node, v_operators))) ->
(Fail ((C.f_diagnostic (v_node) (s_25) (s_51)))))
and (* source_types.bend:341 *)
f_row : 'scope. ('scope -> (Base.text -> ((A.t_Value) list -> (C.t_Cst -> (M.t_Diagnostic, (M.t_TypeId) list) Base.result_)))) -> C.t_Cst -> int -> (t_Header) Base.map -> (t_Variable) list -> 'scope -> (M.t_Diagnostic, M.t_EffectRow) Base.result_ =
fun v_resolve_effect v_node v_fuel v_headers v_variables v_scope ->
(match (f_row_applications ((C.f_field_values (v_node) (s_34))) (v_fuel)) with
| Fail __error -> Fail __error
| Done v_applications ->
(match (f_evaluate (v_resolve_effect) (v_fuel) ((Nodes ((f_row_argument_nodes (v_applications))))) (v_headers) (v_variables) (v_scope)) with
| Fail __error -> Fail __error
| Done v_arguments ->
(match (f_checked_row_labels ((f_row_labels (v_resolve_effect) (v_applications) (v_arguments) (v_scope))) ([v_node])) with
| Fail __error -> Fail __error
| Done v_labels ->
(match (f_row_tail ([v_node]) (v_variables)) with
| Fail __error -> Fail __error
| Done v_tail ->
(Done ((M.EffectRow (v_labels, v_tail))))))))
and (* source_types.bend:349 *)
f_origin : t_Work -> C.t_Cst =
fun v_work ->
(match v_work with
| (Node (v_kind, v_node)) ->
v_node
| (Nodes ((v_head :: v_tail))) ->
v_head
| (Nodes ([])) ->
(C.Cst (s_52, s_52, s_52, 0, []))
| (Field (v_node, v_values)) ->
v_node
| (Infix (v_node, v_tails)) ->
v_node
| (Prefix (v_node, v_operators)) ->
v_node)
and (* source_types.bend:364 *)
f_lower : 'scope. ('scope -> (Base.text -> ((A.t_Value) list -> (C.t_Cst -> (M.t_Diagnostic, (M.t_TypeId) list) Base.result_)))) -> int -> t_Work -> (t_Header) Base.map -> (t_Variable) list -> 'scope -> (M.t_Diagnostic, (M.t_Ty) list) Base.result_ =
fun v_resolve_effect v_fuel v_work v_headers v_variables v_scope ->
(match (f_evaluate (v_resolve_effect) (v_fuel) (v_work) (v_headers) (v_variables) (v_scope)) with
| Fail __error -> Fail __error
| Done v_values ->
(A.f_types (v_fuel) ((A.ValueTypes (v_values))) ((f_origin (v_work)))))
and (* source_types.bend:369 *)
f_annotation : 'scope. ('scope -> (Base.text -> ((A.t_Value) list -> (C.t_Cst -> (M.t_Diagnostic, (M.t_TypeId) list) Base.result_)))) -> (C.t_Cst) list -> int -> (t_Header) Base.map -> (t_Variable) list -> 'scope -> (M.t_Diagnostic, (M.t_Ty) option) Base.result_ =
fun v_resolve_effect v_nodes v_fuel v_headers v_variables v_scope ->
(match v_nodes with
| [] ->
(Done (None))
| (v_node :: []) ->
(match (f_lower (v_resolve_effect) (v_fuel) ((f_visit (v_node))) (v_headers) (v_variables) (v_scope)) with
| Fail __error -> Fail __error
| Done v_types ->
(match (f_one (v_types)) with
| Fail __error -> Fail __error
| Done v_ty ->
(Done ((Some (v_ty))))))
| (v_marker :: (v_node :: [])) ->
(match (f_lower (v_resolve_effect) (v_fuel) ((f_visit (v_node))) (v_headers) (v_variables) (v_scope)) with
| Fail __error -> Fail __error
| Done v_types ->
(match (f_one (v_types)) with
| Fail __error -> Fail __error
| Done v_ty ->
(Done ((Some (v_ty))))))
| _ ->
(Fail ((M.Diagnostic (s_19, s_20, s_53)))))
and (* source_types.bend:389 *)
f_variable_kind : t_Variable -> t_VariableKind =
fun v_variable ->
(let (Variable (v_source, v_value, v_kind)) = v_variable in
v_kind)
and (* source_types.bend:393 *)
f_found_variable : (t_Variable) list -> Base.text -> (t_Variable) option =
fun v_variables v_name ->
(match v_variables with
| [] ->
None
| ((Variable (v_source, v_value, v_kind)) :: v_rest) ->
(Base.bool_pick ((M.f_name_equal (v_source) (v_name))) ((Some ((Variable (v_source, v_value, v_kind))))) ((f_found_variable (v_rest) (v_name)))))
and (* source_types.bend:400 *)
f_same_kind : t_VariableKind -> t_VariableKind -> bool =
fun v_left v_right ->
(match (v_left, v_right) with
| (TypeKind, TypeKind) ->
true
| (RowKind, RowKind) ->
true
| (_, _) ->
false)
and (* source_types.bend:409 *)
f_add_variable_found : (t_Variable) option -> t_VariableKind -> C.t_Cst -> Base.text -> (t_Variable) list -> (M.t_Diagnostic, (t_Variable) list) Base.result_ =
fun v_found v_kind v_node v_scope v_variables ->
(match v_found with
| None ->
(let v_name = (C.f_text_of (v_node)) in
(Done (((Variable (v_name, (M.FreeTy (v_scope, v_name)), v_kind)) :: v_variables))))
| (Some (v_previous)) ->
(Base.bool_pick ((f_same_kind ((f_variable_kind (v_previous))) (v_kind))) ((Done (v_variables))) ((Fail ((C.f_diagnostic (v_node) (s_54) (s_55)))))))
and (* source_types.bend:417 *)
f_add_variable : t_VariableKind -> C.t_Cst -> Base.text -> (t_Variable) list -> (M.t_Diagnostic, (t_Variable) list) Base.result_ =
fun v_kind v_node v_scope v_variables ->
(f_add_variable_found ((f_found_variable (v_variables) ((C.f_text_of (v_node))))) (v_kind) (v_node) (v_scope) (v_variables))
and (* source_types.bend:420 *)
f_scan_row_arguments : (C.t_Cst) list -> (C.t_Cst) list =
fun v_nodes ->
(match v_nodes with
| [] ->
[]
| (v_node :: v_tail) ->
(Base.list_append ((C.f_field_values (v_node) (s_28))) ((f_scan_row_arguments (v_tail)))))
and (* source_types.bend:427 *)
f_predicate_arguments_kind : (C.t_Cst) list -> (C.t_Cst) list -> (C.t_Cst) list =
fun v_kinds v_arguments ->
(match (v_kinds, v_arguments) with
| ((v_kind :: []), (v_first :: v_rest)) ->
(Base.bool_pick ((M.f_name_equal ((C.f_text_of (v_kind))) (s_56))) (v_rest) (v_arguments))
| (_, _) ->
v_arguments)
and (* source_types.bend:434 *)
f_predicate_arguments : C.t_Cst -> (C.t_Cst) list =
fun v_node ->
(f_predicate_arguments_kind ((C.f_field_values (v_node) (s_57))) ((C.f_field_values (v_node) (s_28))))
and (* source_types.bend:437 *)
f_scan_type_name : bool -> C.t_Cst -> Base.text -> (t_Variable) list -> (M.t_Diagnostic, (t_Variable) list) Base.result_ =
fun v_found v_node v_scope v_variables ->
(match v_found with
| true ->
(f_add_variable (TypeKind) (v_node) (v_scope) (v_variables))
| false ->
(Done (v_variables)))
and (* source_types.bend:446 *)
f_scan_row_tail : (C.t_Cst) list -> (t_Variable) list -> Base.text -> (M.t_Diagnostic, (t_Variable) list) Base.result_ =
fun v_nodes v_variables v_scope ->
(match v_nodes with
| [] ->
(Done (v_variables))
| (v_node :: []) ->
(f_add_variable (RowKind) (v_node) (v_scope) (v_variables))
| _ ->
(Fail ((M.Diagnostic (s_19, s_20, s_58)))))
and (* source_types.bend:455 *)
f_scan_variables : int -> (t_VariableScan) list -> (t_Variable) list -> Base.text -> (M.t_Diagnostic, (t_Variable) list) Base.result_ =
fun v_fuel v_pending v_variables v_scope ->
(match (v_fuel, v_pending) with
| (0, _) ->
(Fail ((M.Diagnostic (s_25, s_20, s_59))))
| (__nat_24, []) when __nat_24 >= 1 ->
(let v_rest = (__nat_24 - 1) in
(Done (v_variables)))
| (__nat_25, ((VariableScan ([], v_annotation)) :: v_tail)) when __nat_25 >= 1 ->
(let v_rest = (__nat_25 - 1) in
(f_scan_variables (v_rest) (v_tail) (v_variables) (v_scope)))
| (__nat_26, ((VariableScan (((C.Cst ((SCon (Chr 0x00000065l, (SCon (Chr 0x00000066l, (SCon (Chr 0x00000066l, (SCon (Chr 0x00000065l, (SCon (Chr 0x00000063l, (SCon (Chr 0x00000074l, (SCon (Chr 0x0000005fl, (SCon (Chr 0x00000072l, (SCon (Chr 0x0000006fl, (SCon (Chr 0x00000077l, SNil)))))))))))))))))))), v_field, v_text, v_offset, v_children)) :: v_siblings), v_annotation)) :: v_tail)) when __nat_26 >= 1 ->
(let v_rest = (__nat_26 - 1) in
(let v_node = (C.Cst (s_60, v_field, v_text, v_offset, v_children)) in
(let v_arguments = (f_scan_row_arguments ((C.f_field_values (v_node) (s_34)))) in
(match (f_scan_row_tail ((C.f_field_values (v_node) (s_36))) (v_variables) (v_scope)) with
| Fail __error -> Fail __error
| Done v_next ->
(f_scan_variables (v_rest) (((VariableScan (v_arguments, true)) :: ((VariableScan (v_siblings, v_annotation)) :: v_tail))) (v_next) (v_scope))))))
| (__nat_27, ((VariableScan (((C.Cst ((SCon (Chr 0x00000063l, (SCon (Chr 0x0000006fl, (SCon (Chr 0x0000006el, (SCon (Chr 0x00000073l, (SCon (Chr 0x00000074l, (SCon (Chr 0x00000072l, (SCon (Chr 0x00000061l, (SCon (Chr 0x00000069l, (SCon (Chr 0x0000006el, (SCon (Chr 0x00000074l, (SCon (Chr 0x0000005fl, (SCon (Chr 0x00000070l, (SCon (Chr 0x00000072l, (SCon (Chr 0x00000065l, (SCon (Chr 0x00000064l, (SCon (Chr 0x00000069l, (SCon (Chr 0x00000063l, (SCon (Chr 0x00000061l, (SCon (Chr 0x00000074l, (SCon (Chr 0x00000065l, SNil)))))))))))))))))))))))))))))))))))))))), v_field, v_text, v_offset, v_children)) :: v_siblings), v_annotation)) :: v_tail)) when __nat_27 >= 1 ->
(let v_rest = (__nat_27 - 1) in
(let v_node = (C.Cst (s_61, v_field, v_text, v_offset, v_children)) in
(let v_arguments = (f_predicate_arguments (v_node)) in
(f_scan_variables (v_rest) (((VariableScan (v_arguments, true)) :: ((VariableScan ((C.f_field_values (v_node) (s_31)), false)) :: ((VariableScan (v_siblings, v_annotation)) :: v_tail)))) (v_variables) (v_scope)))))
| (__nat_28, ((VariableScan ((v_node :: v_siblings), v_annotation)) :: v_tail)) when __nat_28 >= 1 ->
(let v_rest = (__nat_28 - 1) in
(let v_kind = (C.f_kind_of (v_node)) in
(let v_nested = (Base.bool_or (v_annotation) ((M.f_name_equal (v_kind) (s_0)))) in
(match (f_scan_type_name ((Base.bool_and (v_nested) ((M.f_name_equal (v_kind) (s_62))))) (v_node) (v_scope) (v_variables)) with
| Fail __error -> Fail __error
| Done v_next ->
(f_scan_variables (v_rest) (((VariableScan ((C.f_children_of (v_node)), v_nested)) :: ((VariableScan (v_siblings, v_annotation)) :: v_tail))) (v_next) (v_scope)))))))
and (* source_types.bend:480 *)
f_free_variables : C.t_Cst -> Base.text -> (M.t_Diagnostic, (t_Variable) list) Base.result_ =
fun v_node v_scope ->
(f_scan_variables (1048576) ([(VariableScan ([v_node], false))]) ([]) (v_scope))
