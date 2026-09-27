(* Native semantic port of compiler/source_arguments.bend.

   Source SHA-256: 020e0b3c67615f31ff51f59756272efdb84b0f47ddb9128047542cae8153751c

   Ownership/type arguments are erased; value types are checked by OCaml.

   No Bend interpreter or generated C/JavaScript is linked. *)

open Base

module M = Ox_model

module C = Ox_cst

type t_Pattern =
  | Binding of Base.text
  | TuplePattern of (t_Pattern) list
  | ArrayPattern of (t_Pattern) list
  | RecordPattern of (Base.text) list * (t_Pattern) list
and t_Value =
  | Concrete of M.t_Ty
  | TupleValue of (t_Value) list
  | ArrayValue of (t_Value) list
  | RecordValue of (Base.text) list * (t_Value) list
  | ConstructorValue of M.t_TypeId * (t_Pattern) list * (M.t_Ty) list
  | ArrayConstructorValue
and t_TypeWork =
  | ValueType of t_Value
  | ValueTypes of (t_Value) list
and t_MatchWork =
  | Argument of t_Pattern * t_Value
  | Arguments of (t_Pattern) list * (t_Value) list
  | Fields of (Base.text) list * (t_Pattern) list * (Base.text) list * (t_Value) list
and t_PatternKind =
  | BinderNode
  | WrapperNode
  | ExpressionNode
  | ApplicationNode
  | TupleNode
  | ArrayNode
  | RecordNode
  | FieldNode
and t_PatternWork =
  | PatternNode of t_PatternKind * C.t_Cst
  | PatternNodes of (C.t_Cst) list
  | PatternField of C.t_Cst * (C.t_Cst) list
  | PatternApplication of C.t_Cst * (C.t_Cst) list

let s_0 = Base.text_of_utf8 "internal_cst"

let s_1 = Base.text_of_utf8 "parser"

let s_2 = Base.text_of_utf8 "expected one type"

let s_3 = Base.text_of_utf8 "type_argument"

let s_4 = Base.text_of_utf8 "type argument exceeds the source-tree limit"

let s_5 = Base.text_of_utf8 "type_arity"

let s_6 = Base.text_of_utf8 "partially applied type constructor requires another argument"

let s_7 = Base.text_of_utf8 "Array requires one element type"

let s_8 = Base.text_of_utf8 "expected a type; structural arguments must match a constructor parameter"

let s_9 = Base.text_of_utf8 "missing type argument field: "

let s_10 = Base.text_of_utf8 "type parameter pattern exceeds the source-tree limit"

let s_11 = Base.text_of_utf8 "record type argument has the wrong fields"

let s_12 = Base.text_of_utf8 "type argument does not match its parameter pattern"

let s_13 = Base.text_of_utf8 "type argument has the wrong number of elements"

let s_14 = Base.text_of_utf8 "type record lost a field pattern"

let s_15 = Base.text_of_utf8 "type does not accept another argument; currying must be explicit in its declaration"

let s_16 = Base.text_of_utf8 "wrong number of type arguments"

let s_17 = Base.text_of_utf8 "type_atom"

let s_18 = Base.text_of_utf8 "type_expression"

let s_19 = Base.text_of_utf8 "type_application"

let s_20 = Base.text_of_utf8 "type_group"

let s_21 = Base.text_of_utf8 "type_array"

let s_22 = Base.text_of_utf8 "type_record"

let s_23 = Base.text_of_utf8 "type_field"

let s_24 = Base.text_of_utf8 "rest"

let s_25 = Base.text_of_utf8 "type_parameter"

let s_26 = Base.text_of_utf8 "a type parameter pattern binds lowercase names"

let s_27 = Base.text_of_utf8 "name"

let s_28 = Base.text_of_utf8 "duplicate_type_field"

let s_29 = Base.text_of_utf8 "duplicate type argument field: "

let s_30 = Base.text_of_utf8 "type"

let s_31 = Base.text_of_utf8 "results"

let s_32 = Base.text_of_utf8 "effects"

let s_33 = Base.text_of_utf8 "arguments"

let s_34 = Base.text_of_utf8 "head"

let s_35 = Base.text_of_utf8 "a type parameter is one binding or a structural pattern"

let s_36 = Base.text_of_utf8 "value"

let s_37 = Base.text_of_utf8 "elements"

let s_38 = Base.text_of_utf8 "fields"

let s_39 = Base.text_of_utf8 "parameters"

let rec (* source_arguments.bend:25 *)
f_one : (M.t_Ty) list -> (M.t_Diagnostic, M.t_Ty) Base.result_ =
fun v_types ->
(match v_types with
| (v_ty :: []) ->
(Done (v_ty))
| _ ->
(Fail ((M.Diagnostic (s_0, s_1, s_2)))))
and (* source_arguments.bend:32 *)
f_product : (M.t_Ty) list -> M.t_Ty =
fun v_elements ->
(match v_elements with
| [] ->
M.UnitTy
| (v_first :: []) ->
v_first
| v_elements ->
(M.ProductTy (v_elements)))
and (* source_arguments.bend:41 *)
f_types : int -> t_TypeWork -> C.t_Cst -> (M.t_Diagnostic, (M.t_Ty) list) Base.result_ =
fun v_fuel v_work v_node ->
(match (v_fuel, v_work) with
| (0, _) ->
(Fail ((C.f_diagnostic (v_node) (s_3) (s_4))))
| (__nat_1, (ValueType ((Concrete (v_ty))))) when __nat_1 >= 1 ->
(let v_rest = (__nat_1 - 1) in
(Done ([v_ty])))
| (__nat_2, (ValueType ((TupleValue (v_elements))))) when __nat_2 >= 1 ->
(let v_rest = (__nat_2 - 1) in
(match (f_types (v_rest) ((ValueTypes (v_elements))) (v_node)) with
| Fail __error -> Fail __error
| Done v_fields ->
(Done ([(f_product (v_fields))]))))
| (__nat_3, (ValueType ((ConstructorValue (v_identity, v_parameters, v_bound))))) when __nat_3 >= 1 ->
(let v_rest = (__nat_3 - 1) in
(Fail ((C.f_diagnostic (v_node) (s_5) (s_6)))))
| (__nat_4, (ValueType (ArrayConstructorValue))) when __nat_4 >= 1 ->
(let v_rest = (__nat_4 - 1) in
(Fail ((C.f_diagnostic (v_node) (s_5) (s_7)))))
| (__nat_5, (ValueType (v_value))) when __nat_5 >= 1 ->
(let v_rest = (__nat_5 - 1) in
(Fail ((C.f_diagnostic (v_node) (s_3) (s_8)))))
| (__nat_6, (ValueTypes ([]))) when __nat_6 >= 1 ->
(let v_rest = (__nat_6 - 1) in
(Done ([])))
| (__nat_7, (ValueTypes ((v_head :: v_tail)))) when __nat_7 >= 1 ->
(let v_rest = (__nat_7 - 1) in
(match (f_types (v_rest) ((ValueType (v_head))) (v_node)) with
| Fail __error -> Fail __error
| Done v_first ->
(match (f_types (v_rest) ((ValueTypes (v_tail))) (v_node)) with
| Fail __error -> Fail __error
| Done v_following ->
(Done ((Base.list_append (v_first) (v_following))))))))
and (* source_arguments.bend:65 *)
f_as_type : t_Value -> C.t_Cst -> (M.t_Diagnostic, M.t_Ty) Base.result_ =
fun v_value v_node ->
(match (f_types (65536) ((ValueType (v_value))) (v_node)) with
| Fail __error -> Fail __error
| Done v_values ->
(f_one (v_values)))
and (* source_arguments.bend:70 *)
f_field : (Base.text) list -> (t_Value) list -> Base.text -> C.t_Cst -> (M.t_Diagnostic, t_Value) Base.result_ =
fun v_names v_values v_wanted v_node ->
(match (v_names, v_values) with
| ((v_name :: v_tail), (v_value :: v_rest)) ->
(Base.bool_pick ((M.f_name_equal (v_name) (v_wanted))) ((Done (v_value))) ((f_field (v_tail) (v_rest) (v_wanted) (v_node))))
| (_, _) ->
(Fail ((C.f_diagnostic (v_node) (s_3) ((Base.string_append s_9 v_wanted))))))
and (* source_arguments.bend:82 *)
f_match_argument : int -> t_MatchWork -> C.t_Cst -> (M.t_Diagnostic, (M.t_Ty) list) Base.result_ =
fun v_fuel v_work v_node ->
(match (v_fuel, v_work) with
| (0, _) ->
(Fail ((C.f_diagnostic (v_node) (s_3) (s_10))))
| (__nat_8, (Argument ((Binding (v_source)), v_value))) when __nat_8 >= 1 ->
(let v_rest = (__nat_8 - 1) in
(match (f_as_type (v_value) (v_node)) with
| Fail __error -> Fail __error
| Done v_ty ->
(Done ([v_ty]))))
| (__nat_9, (Argument ((TuplePattern (v_patterns)), (TupleValue (v_values))))) when __nat_9 >= 1 ->
(let v_rest = (__nat_9 - 1) in
(f_match_argument (v_rest) ((Arguments (v_patterns, v_values))) (v_node)))
| (__nat_10, (Argument ((ArrayPattern (v_patterns)), (ArrayValue (v_values))))) when __nat_10 >= 1 ->
(let v_rest = (__nat_10 - 1) in
(f_match_argument (v_rest) ((Arguments (v_patterns, v_values))) (v_node)))
| (__nat_11, (Argument ((RecordPattern (v_names, v_patterns)), (RecordValue (v_actual_names, v_values))))) when __nat_11 >= 1 ->
(let v_rest = (__nat_11 - 1) in
(match (Base.bool_pick ((Base.nat_is_eq ((Base.list_length (v_names))) ((Base.list_length (v_actual_names))))) ((Done (()))) ((Fail ((C.f_diagnostic (v_node) (s_3) (s_11)))))) with
| Fail __error -> Fail __error
| Done v_valid ->
(f_match_argument (v_rest) ((Fields (v_names, v_patterns, v_actual_names, v_values))) (v_node))))
| (__nat_12, (Argument (v_pattern, v_value))) when __nat_12 >= 1 ->
(let v_rest = (__nat_12 - 1) in
(Fail ((C.f_diagnostic (v_node) (s_3) (s_12)))))
| (__nat_13, (Arguments ([], []))) when __nat_13 >= 1 ->
(let v_rest = (__nat_13 - 1) in
(Done ([])))
| (__nat_14, (Arguments ((v_pattern :: v_patterns), (v_value :: v_values)))) when __nat_14 >= 1 ->
(let v_rest = (__nat_14 - 1) in
(match (f_match_argument (v_rest) ((Argument (v_pattern, v_value))) (v_node)) with
| Fail __error -> Fail __error
| Done v_first ->
(match (f_match_argument (v_rest) ((Arguments (v_patterns, v_values))) (v_node)) with
| Fail __error -> Fail __error
| Done v_following ->
(Done ((Base.list_append (v_first) (v_following)))))))
| (__nat_15, (Arguments (v_patterns, v_values))) when __nat_15 >= 1 ->
(let v_rest = (__nat_15 - 1) in
(Fail ((C.f_diagnostic (v_node) (s_3) (s_13)))))
| (__nat_16, (Fields ([], [], v_actual_names, v_values))) when __nat_16 >= 1 ->
(let v_rest = (__nat_16 - 1) in
(Done ([])))
| (__nat_17, (Fields ((v_name :: v_names), (v_pattern :: v_patterns), v_actual_names, v_values))) when __nat_17 >= 1 ->
(let v_rest = (__nat_17 - 1) in
(match (f_field (v_actual_names) (v_values) (v_name) (v_node)) with
| Fail __error -> Fail __error
| Done v_value ->
(match (f_match_argument (v_rest) ((Argument (v_pattern, v_value))) (v_node)) with
| Fail __error -> Fail __error
| Done v_first ->
(match (f_match_argument (v_rest) ((Fields (v_names, v_patterns, v_actual_names, v_values))) (v_node)) with
| Fail __error -> Fail __error
| Done v_following ->
(Done ((Base.list_append (v_first) (v_following))))))))
| (__nat_18, (Fields (v_names, v_patterns, v_actual_names, v_values))) when __nat_18 >= 1 ->
(let v_rest = (__nat_18 - 1) in
(Fail ((C.f_diagnostic (v_node) (s_0) (s_14))))))
and (* source_arguments.bend:120 *)
f_constructor : (t_Pattern) list -> M.t_TypeId -> (M.t_Ty) list -> t_Value =
fun v_parameters v_identity v_bound ->
(match v_parameters with
| [] ->
(Concrete ((M.AppliedTy (v_identity, v_bound))))
| v_parameters ->
(ConstructorValue (v_identity, v_parameters, v_bound)))
and (* source_arguments.bend:127 *)
f_apply_one : t_Value -> t_Value -> C.t_Cst -> (M.t_Diagnostic, t_Value) Base.result_ =
fun v_callee v_argument v_node ->
(match v_callee with
| (ConstructorValue (v_identity, (v_pattern :: v_rest), v_bound)) ->
(match (f_match_argument (65536) ((Argument (v_pattern, v_argument))) (v_node)) with
| Fail __error -> Fail __error
| Done v_arguments ->
(Done ((f_constructor (v_rest) (v_identity) ((Base.list_append (v_bound) (v_arguments)))))))
| ArrayConstructorValue ->
(match (f_as_type (v_argument) (v_node)) with
| Fail __error -> Fail __error
| Done v_ty ->
(Done ((Concrete ((M.ArrayTy (v_ty)))))))
| _ ->
(Fail ((C.f_diagnostic (v_node) (s_5) (s_15)))))
and (* source_arguments.bend:140 *)
f_apply : (t_Value) list -> t_Value -> C.t_Cst -> (M.t_Diagnostic, t_Value) Base.result_ =
fun v_arguments v_callee v_node ->
(match v_arguments with
| [] ->
(Done (v_callee))
| (v_head :: v_tail) ->
(match (f_apply_one (v_callee) (v_head) (v_node)) with
| Fail __error -> Fail __error
| Done v_next ->
(f_apply (v_tail) (v_next) (v_node))))
and (* source_arguments.bend:149 *)
f_bind : (t_Pattern) list -> (t_Value) list -> C.t_Cst -> (M.t_Diagnostic, (M.t_Ty) list) Base.result_ =
fun v_parameters v_values v_node ->
(match (v_parameters, v_values) with
| ([], []) ->
(Done ([]))
| ((v_pattern :: v_rest), (v_value :: v_tail)) ->
(match (f_match_argument (65536) ((Argument (v_pattern, v_value))) (v_node)) with
| Fail __error -> Fail __error
| Done v_first ->
(match (f_bind (v_rest) (v_tail) (v_node)) with
| Fail __error -> Fail __error
| Done v_following ->
(Done ((Base.list_append (v_first) (v_following))))))
| (_, _) ->
(Fail ((C.f_diagnostic (v_node) (s_5) (s_16)))))
and (* source_arguments.bend:177 *)
f_pattern_kind : Base.text -> t_PatternKind =
fun v_kind ->
(Base.bool_pick ((M.f_name_equal (v_kind) (s_17))) (WrapperNode) ((Base.bool_pick ((M.f_name_equal (v_kind) (s_18))) (ExpressionNode) ((Base.bool_pick ((M.f_name_equal (v_kind) (s_19))) (ApplicationNode) ((Base.bool_pick ((M.f_name_equal (v_kind) (s_20))) (TupleNode) ((Base.bool_pick ((M.f_name_equal (v_kind) (s_21))) (ArrayNode) ((Base.bool_pick ((M.f_name_equal (v_kind) (s_22))) (RecordNode) ((Base.bool_pick ((M.f_name_equal (v_kind) (s_23))) (FieldNode) (BinderNode))))))))))))))
and (* source_arguments.bend:186 *)
f_lowercase_name : Base.text -> bool =
fun v_name ->
(match v_name with
| (SCon ((Chr (v_initial)), v_tail)) ->
(Base.bool_or ((Base.u32_is_eq (v_initial) (0x0000005fl))) ((Base.bool_and ((Base.u32_is_ge (v_initial) (0x00000061l))) ((Base.u32_is_le (v_initial) (0x0000007al))))))
| SNil ->
false)
and (* source_arguments.bend:193 *)
f_binding_pattern : C.t_Cst -> (M.t_Diagnostic, (t_Pattern) list) Base.result_ =
fun v_node ->
(let v_name = (C.f_type_name (v_node)) in
(Base.bool_pick ((Base.bool_and ((f_lowercase_name (v_name))) ((Base.list_is_empty ((C.f_field_values (v_node) (s_24))))))) ((Done ([(Binding (v_name))]))) ((Fail ((C.f_diagnostic (v_node) (s_25) (s_26)))))))
and (* source_arguments.bend:197 *)
f_field_names : (C.t_Cst) list -> (M.t_Diagnostic, (Base.text) list) Base.result_ =
fun v_nodes ->
(match v_nodes with
| [] ->
(Done ([]))
| (v_node :: v_tail) ->
(match (C.f_one ((C.f_field_values (v_node) (s_27)))) with
| Fail __error -> Fail __error
| Done v_name ->
(match (f_field_names (v_tail)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done (((C.f_type_name (v_name)) :: v_rest))))))
and (* source_arguments.bend:207 *)
f_contains : (Base.text) list -> Base.text -> bool =
fun v_names v_wanted ->
(match v_names with
| [] ->
false
| (v_name :: v_tail) ->
(Base.bool_or ((M.f_name_equal (v_name) (v_wanted))) ((f_contains (v_tail) (v_wanted)))))
and (* source_arguments.bend:214 *)
f_unique : (Base.text) list -> C.t_Cst -> (M.t_Diagnostic, unit) Base.result_ =
fun v_names v_node ->
(match v_names with
| [] ->
(Done (()))
| (v_name :: v_tail) ->
(match (Base.bool_pick ((f_contains (v_tail) (v_name))) ((Fail ((C.f_diagnostic (v_node) (s_28) ((Base.string_append s_29 v_name)))))) ((Done (())))) with
| Fail __error -> Fail __error
| Done v_valid ->
(f_unique (v_tail) (v_node))))
and (* source_arguments.bend:223 *)
f_tuple_pattern : (t_Pattern) list -> t_Pattern =
fun v_patterns ->
(match v_patterns with
| (v_head :: []) ->
v_head
| v_patterns ->
(TuplePattern (v_patterns)))
and (* source_arguments.bend:230 *)
f_parse_patterns : int -> t_PatternWork -> (M.t_Diagnostic, (t_Pattern) list) Base.result_ =
fun v_fuel v_work ->
(match (v_fuel, v_work) with
| (0, _) ->
(Fail ((M.Diagnostic (s_3, s_30, s_10))))
| (__nat_19, (PatternNodes ([]))) when __nat_19 >= 1 ->
(let v_rest = (__nat_19 - 1) in
(Done ([])))
| (__nat_20, (PatternNodes ((v_head :: v_tail)))) when __nat_20 >= 1 ->
(let v_rest = (__nat_20 - 1) in
(match (f_parse_patterns (v_rest) ((PatternNode ((f_pattern_kind ((C.f_kind_of (v_head)))), v_head)))) with
| Fail __error -> Fail __error
| Done v_first ->
(match (f_parse_patterns (v_rest) ((PatternNodes (v_tail)))) with
| Fail __error -> Fail __error
| Done v_following ->
(Done ((Base.list_append (v_first) (v_following)))))))
| (__nat_21, (PatternNode (BinderNode, v_node))) when __nat_21 >= 1 ->
(let v_rest = (__nat_21 - 1) in
(f_binding_pattern (v_node)))
| (__nat_22, (PatternNode (WrapperNode, v_node))) when __nat_22 >= 1 ->
(let v_rest = (__nat_22 - 1) in
(match (C.f_one ((C.f_children_of (v_node)))) with
| Fail __error -> Fail __error
| Done v_child ->
(f_parse_patterns (v_rest) ((PatternNode ((f_pattern_kind ((C.f_kind_of (v_child)))), v_child))))))
| (__nat_23, (PatternNode (ExpressionNode, v_node))) when __nat_23 >= 1 ->
(let v_rest = (__nat_23 - 1) in
(f_parse_patterns (v_rest) ((PatternApplication (v_node, (Base.list_append ((C.f_field_values (v_node) (s_31))) ((C.f_field_values (v_node) (s_32)))))))))
| (__nat_24, (PatternNode (ApplicationNode, v_node))) when __nat_24 >= 1 ->
(let v_rest = (__nat_24 - 1) in
(f_parse_patterns (v_rest) ((PatternApplication (v_node, (C.f_field_values (v_node) (s_33)))))))
| (__nat_25, (PatternApplication (v_node, []))) when __nat_25 >= 1 ->
(let v_rest = (__nat_25 - 1) in
(f_parse_patterns (v_rest) ((PatternNodes ((C.f_field_values (v_node) (s_34)))))))
| (__nat_26, (PatternApplication (v_node, v_extra))) when __nat_26 >= 1 ->
(let v_rest = (__nat_26 - 1) in
(Fail ((C.f_diagnostic (v_node) (s_25) (s_35)))))
| (__nat_27, (PatternNode (TupleNode, v_node))) when __nat_27 >= 1 ->
(let v_rest = (__nat_27 - 1) in
(match (f_parse_patterns (v_rest) ((PatternNodes ((C.f_field_values (v_node) (s_36)))))) with
| Fail __error -> Fail __error
| Done v_elements ->
(Done ([(f_tuple_pattern (v_elements))]))))
| (__nat_28, (PatternNode (ArrayNode, v_node))) when __nat_28 >= 1 ->
(let v_rest = (__nat_28 - 1) in
(match (f_parse_patterns (v_rest) ((PatternNodes ((C.f_field_values (v_node) (s_37)))))) with
| Fail __error -> Fail __error
| Done v_elements ->
(Done ([(ArrayPattern (v_elements))]))))
| (__nat_29, (PatternNode (RecordNode, v_node))) when __nat_29 >= 1 ->
(let v_rest = (__nat_29 - 1) in
(match (Done ((C.f_field_values (v_node) (s_38)))) with
| Fail __error -> Fail __error
| Done v_fields ->
(match (f_field_names (v_fields)) with
| Fail __error -> Fail __error
| Done v_names ->
(match (f_unique (v_names) (v_node)) with
| Fail __error -> Fail __error
| Done v_valid ->
(match (f_parse_patterns (v_rest) ((PatternNodes (v_fields)))) with
| Fail __error -> Fail __error
| Done v_patterns ->
(Done ([(RecordPattern (v_names, v_patterns))])))))))
| (__nat_30, (PatternNode (FieldNode, v_node))) when __nat_30 >= 1 ->
(let v_rest = (__nat_30 - 1) in
(f_parse_patterns (v_rest) ((PatternField (v_node, (C.f_field_values (v_node) (s_36)))))))
| (__nat_31, (PatternField (v_node, []))) when __nat_31 >= 1 ->
(let v_rest = (__nat_31 - 1) in
(match (C.f_one ((C.f_field_values (v_node) (s_27)))) with
| Fail __error -> Fail __error
| Done v_name ->
(Done ([(Binding ((C.f_type_name (v_name))))]))))
| (__nat_32, (PatternField (v_node, v_values))) when __nat_32 >= 1 ->
(let v_rest = (__nat_32 - 1) in
(f_parse_patterns (v_rest) ((PatternNodes (v_values))))))
and (* source_arguments.bend:279 *)
f_binding_names : int -> (t_Pattern) list -> (M.t_Diagnostic, (Base.text) list) Base.result_ =
fun v_fuel v_patterns ->
(match (v_fuel, v_patterns) with
| (0, _) ->
(Fail ((M.Diagnostic (s_3, s_30, s_10))))
| (__nat_33, []) when __nat_33 >= 1 ->
(let v_rest = (__nat_33 - 1) in
(Done ([])))
| (__nat_34, ((Binding (v_name)) :: v_tail)) when __nat_34 >= 1 ->
(let v_rest = (__nat_34 - 1) in
(match (f_binding_names (v_rest) (v_tail)) with
| Fail __error -> Fail __error
| Done v_names ->
(Done ((v_name :: v_names)))))
| (__nat_35, ((TuplePattern (v_elements)) :: v_tail)) when __nat_35 >= 1 ->
(let v_rest = (__nat_35 - 1) in
(f_binding_names (v_rest) ((Base.list_append (v_elements) (v_tail)))))
| (__nat_36, ((ArrayPattern (v_elements)) :: v_tail)) when __nat_36 >= 1 ->
(let v_rest = (__nat_36 - 1) in
(f_binding_names (v_rest) ((Base.list_append (v_elements) (v_tail)))))
| (__nat_37, ((RecordPattern (v_names, v_fields)) :: v_tail)) when __nat_37 >= 1 ->
(let v_rest = (__nat_37 - 1) in
(f_binding_names (v_rest) ((Base.list_append (v_fields) (v_tail))))))
and (* source_arguments.bend:296 *)
f_parameters : C.t_Cst -> (M.t_Diagnostic, (t_Pattern) list) Base.result_ =
fun v_node ->
(f_parse_patterns (65536) ((PatternNodes ((C.f_field_values (v_node) (s_39))))))
