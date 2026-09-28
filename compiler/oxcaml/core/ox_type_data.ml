(* Native semantic port of compiler/type_data.bend.

   Source SHA-256: a3826ad4505bc50a105d3b5102683434f0977daac586271a59531ae8fa265be4

   Ownership/type arguments are erased; value types are checked by OCaml.

   No Bend interpreter or generated C/JavaScript is linked. *)

open Base

module M = Ox_model

module T = Ox_types

module Index = Ox_index

type t_ConstructorType =
  | ConstructorType of M.t_Ty * (M.t_Ty) option * int
and t_ConstructorDefinition =
  | ConstructorDefinition of M.t_TypeId * int * (M.t_Ty) option

let s_0 = Base.text_of_utf8 "unknown_constructor"

let s_1 = Base.text_of_utf8 "unknown constructor "

let s_2 = Base.text_of_utf8 "sealed_effect"

let s_3 = Base.text_of_utf8 "Foreign is a compiler effect label, not a callable or providable operation"

let s_4 = Base.text_of_utf8 "unknown_operation"

let s_5 = Base.text_of_utf8 "unknown effect operation"

let s_6 = Base.text_of_utf8 "the compiler-reserved Foreign effect cannot be declared as an operation"

let s_7 = Base.text_of_utf8 "invalid_annotation"

let s_8 = Base.text_of_utf8 "unknown_type"

let s_9 = Base.text_of_utf8 "unknown nominal data type"

let s_10 = Base.text_of_utf8 "wrong number of type arguments"

let s_11 = Base.text_of_utf8 "effect parameter index is outside its quantified scope"

let s_12 = Base.text_of_utf8 "effect inference variables are compiler-owned"

let s_13 = Base.text_of_utf8 "product_arity"

let s_14 = Base.text_of_utf8 "products require at least two elements; use Unit for an empty value"

let s_15 = Base.text_of_utf8 "products require at least two elements; a single value does not need a product"

let s_16 = Base.text_of_utf8 "free annotation names cannot escape into quantified type declarations"

let s_17 = Base.text_of_utf8 "inference variables are compiler-owned"

let s_18 = Base.text_of_utf8 "Never is an internal control-flow type"

let s_19 = Base.text_of_utf8 "type parameter index is outside its data declaration"

let s_20 = Base.text_of_utf8 "kind_mismatch"

let s_21 = Base.text_of_utf8 "data declaration parameters are value types, not effect rows"

let s_22 = Base.text_of_utf8 "record field names must be unique"

let s_23 = Base.text_of_utf8 "record fields require a payload"

let s_24 = Base.text_of_utf8 "record fields must match the constructor payload"

let rec (* type_data.bend:12 *)
f_lookup_work : (M.t_DataType) list -> M.t_TypeId -> (M.t_DataType) option -> (M.t_DataType) option =
fun v_types v_identity v_found ->
(match (v_types, v_found) with
| (_, (Some (v_declaration))) ->
(Some (v_declaration))
| ([], None) ->
None
| (((M.DataType (v_declared, v_parameters, v_constructors)) :: v_tail), None) ->
(f_lookup_work (v_tail) (v_identity) ((Base.bool_pick ((M.f_type_id_equal (v_declared) (v_identity))) ((Some ((M.DataType (v_declared, v_parameters, v_constructors))))) (None)))))
and (* type_data.bend:21 *)
f_lookup : (M.t_DataType) list -> M.t_TypeId -> (M.t_DataType) option =
fun v_types v_identity ->
(f_lookup_work (v_types) (v_identity) (None))
and (* type_data.bend:24 *)
f_constructor_in_work : (M.t_Constructor) list -> Base.text -> M.t_TypeId -> int -> (t_ConstructorDefinition) option -> (t_ConstructorDefinition) option =
fun v_constructors v_name v_identity v_parameters v_found ->
(match (v_constructors, v_found) with
| (_, (Some (v_declaration))) ->
(Some (v_declaration))
| ([], None) ->
None
| (((M.Constructor (v_declared, v_payload, v_fields)) :: v_tail), None) ->
(f_constructor_in_work (v_tail) (v_name) (v_identity) (v_parameters) ((Base.bool_pick ((M.f_name_equal (v_declared) (v_name))) ((Some ((ConstructorDefinition (v_identity, v_parameters, v_payload))))) (None)))))
and (* type_data.bend:33 *)
f_constructor_in : (M.t_Constructor) list -> Base.text -> M.t_TypeId -> int -> (t_ConstructorDefinition) option =
fun v_constructors v_name v_identity v_parameters ->
(f_constructor_in_work (v_constructors) (v_name) (v_identity) (v_parameters) (None))
and (* type_data.bend:36 *)
f_constructor_work : (M.t_DataType) list -> Base.text -> (t_ConstructorDefinition) option -> (t_ConstructorDefinition) option =
fun v_types v_name v_found ->
(match (v_types, v_found) with
| (_, (Some (v_declaration))) ->
(Some (v_declaration))
| ([], None) ->
None
| (((M.DataType (v_identity, v_parameters, v_constructors)) :: v_tail), None) ->
(f_constructor_work (v_tail) (v_name) ((f_constructor_in (v_constructors) (v_name) (v_identity) (v_parameters)))))
and (* type_data.bend:45 *)
f_constructor : (M.t_DataType) list -> Base.text -> (t_ConstructorDefinition) option =
fun v_types v_name ->
(f_constructor_work (v_types) (v_name) (None))
and (* type_data.bend:48 *)
f_fresh_arguments_accumulated : int -> int -> (M.t_Ty) list -> (M.t_Ty) list =
fun v_count v_start v_reversed ->
(match v_count with
| 0 ->
(Base.list_reverse (v_reversed))
| __nat_1 when __nat_1 >= 1 ->
(let v_rest = (__nat_1 - 1) in
(f_fresh_arguments_accumulated (v_rest) ((Base.nat_add 1 v_start)) (((M.VariableTy (v_start)) :: v_reversed)))))
and (* type_data.bend:55 *)
f_fresh_arguments : int -> int -> (M.t_Ty) list =
fun v_count v_start ->
(f_fresh_arguments_accumulated (v_count) (v_start) ([]))
and (* type_data.bend:58 *)
f_instance_payload : (M.t_Ty) option -> (M.t_Ty) list -> (M.t_Diagnostic, (M.t_Ty) option) Base.result_ =
fun v_payload v_arguments ->
(match v_payload with
| None ->
(Done (None))
| (Some (v_ty)) ->
(match (T.f_parameters (v_arguments) (0) (v_ty)) with
| Fail __error -> Fail __error
| Done v_value ->
(Done ((Some (v_value))))))
and (* type_data.bend:67 *)
f_instantiate : (t_ConstructorDefinition) option -> Base.text -> int -> Base.text -> (M.t_Diagnostic, t_ConstructorType) Base.result_ =
fun v_found v_name v_start v_subject ->
(match v_found with
| None ->
(Fail ((M.Diagnostic (s_0, v_subject, (Base.string_append s_1 v_name)))))
| (Some ((ConstructorDefinition (v_identity, v_count, v_payload)))) ->
(let v_arguments = (f_fresh_arguments (v_count) (v_start)) in
(match (f_instance_payload (v_payload) (v_arguments)) with
| Fail __error -> Fail __error
| Done v_value ->
(Done ((ConstructorType ((M.AppliedTy (v_identity, v_arguments)), v_value, (Base.nat_add (v_start) (v_count)))))))))
and (* type_data.bend:77 *)
f_operation_work : (M.t_Operation) list -> M.t_TypeId -> (M.t_Operation) option -> (M.t_Operation) option =
fun v_operations v_identity v_found ->
(match (v_operations, v_found) with
| (_, (Some (v_declaration))) ->
(Some (v_declaration))
| ([], None) ->
None
| (((M.Operation (v_declared, v_parameter, v_result)) :: v_tail), None) ->
(f_operation_work (v_tail) (v_identity) ((Base.bool_pick ((M.f_type_id_equal (v_declared) (v_identity))) ((Some ((M.Operation (v_declared, v_parameter, v_result))))) (None))))
| ((v_head :: v_tail), None) ->
(f_operation_work (v_tail) (v_identity) (None)))
and (* type_data.bend:88 *)
f_operation : (M.t_Operation) list -> M.t_TypeId -> (M.t_Operation) option =
fun v_operations v_identity ->
(f_operation_work (v_operations) (v_identity) (None))
and (* type_data.bend:91 *)
f_require_unsealed_operation : bool -> (M.t_Operation) option -> M.t_TypeId -> (M.t_Diagnostic, M.t_Operation) Base.result_ =
fun v_sealed v_found v_identity ->
(match v_sealed with
| true ->
(Fail ((M.Diagnostic (s_2, (M.f_type_id_show (v_identity)), s_3))))
| false ->
(match v_found with
| (Some (v_declaration)) ->
(Done (v_declaration))
| None ->
(Fail ((M.Diagnostic (s_4, (M.f_type_id_show (v_identity)), s_5))))))
and (* type_data.bend:102 *)
f_require_operation : (M.t_Operation) option -> M.t_TypeId -> (M.t_Diagnostic, M.t_Operation) Base.result_ =
fun v_found v_identity ->
(f_require_unsealed_operation ((M.f_is_foreign (v_identity))) (v_found) (v_identity))
and (* type_data.bend:105 *)
f_require_effect_label : bool -> (M.t_Operation) option -> M.t_TypeId -> (M.t_Diagnostic, unit) Base.result_ =
fun v_sealed v_found v_identity ->
(match v_sealed with
| true ->
(Done (()))
| false ->
(match (f_require_operation (v_found) (v_identity)) with
| Fail __error -> Fail __error
| Done v_declared ->
(Done (()))))
and (* type_data.bend:114 *)
f_valid_effect_label : (M.t_Operation) list -> M.t_TypeId -> (M.t_Diagnostic, unit) Base.result_ =
fun v_operations v_identity ->
(f_require_effect_label ((M.f_is_foreign (v_identity))) ((f_operation (v_operations) (v_identity))) (v_identity))
and (* type_data.bend:117 *)
f_unsealed_declaration : bool -> M.t_TypeId -> (M.t_Diagnostic, unit) Base.result_ =
fun v_sealed v_identity ->
(match v_sealed with
| false ->
(Done (()))
| true ->
(Fail ((M.Diagnostic (s_2, (M.f_type_id_show (v_identity)), s_6)))))
and (* type_data.bend:124 *)
f_valid_operation_identity : M.t_TypeId -> (M.t_Diagnostic, unit) Base.result_ =
fun v_identity ->
(f_unsealed_declaration ((M.f_is_foreign (v_identity))) (v_identity))
and (* type_data.bend:127 *)
f_valid_parameter : (int) option -> int -> bool =
fun v_parameters v_index ->
(match v_parameters with
| None ->
false
| (Some (v_count)) ->
(Base.nat_is_lt (v_index) (v_count)))
and (* type_data.bend:134 *)
f_require : bool -> Base.text -> Base.text -> (M.t_Diagnostic, unit) Base.result_ =
fun v_valid v_subject v_message ->
(match v_valid with
| true ->
(Done (()))
| false ->
(Fail ((M.Diagnostic (s_7, v_subject, v_message)))))
and (* type_data.bend:141 *)
f_valid_arity : (M.t_DataType) option -> int -> Base.text -> (M.t_Diagnostic, unit) Base.result_ =
fun v_found v_count v_subject ->
(match v_found with
| None ->
(Fail ((M.Diagnostic (s_8, v_subject, s_9))))
| (Some ((M.DataType (v_identity, v_arity, v_constructors)))) ->
(f_require ((Base.nat_is_eq (v_arity) (v_count))) (v_subject) (s_10)))
and (* type_data.bend:148 *)
f_valid_row_tail : M.t_RowTail -> (int) option -> Base.text -> (M.t_Diagnostic, unit) Base.result_ =
fun v_tail v_parameters v_subject ->
(match v_tail with
| M.ClosedRow ->
(Done (()))
| (M.RowParameter (v_index)) ->
(f_require ((f_valid_parameter (v_parameters) (v_index))) (v_subject) (s_11))
| (M.RowVariable (v_index)) ->
(Fail ((M.Diagnostic (s_7, v_subject, s_12))))
| (M.FreeRow (v_scope, v_name)) ->
(Done (())))
and (* type_data.bend:159 *)
f_valid_row_operations : (M.t_TypeId) list -> (M.t_Operation) list -> (M.t_Diagnostic, unit) Base.result_ =
fun v_identities v_operations ->
(match v_identities with
| [] ->
(Done (()))
| (v_identity :: v_tail) ->
(match (f_valid_effect_label (v_operations) (v_identity)) with
| Fail __error -> Fail __error
| Done v_known ->
(f_valid_row_operations (v_tail) (v_operations))))
and (* type_data.bend:168 *)
f_validate_row : M.t_EffectRow -> (int) option -> (M.t_Operation) list -> Base.text -> (M.t_Diagnostic, unit) Base.result_ =
fun v_row v_parameters v_operations v_subject ->
(let (M.EffectRow (v_identities, v_tail)) = v_row in
(match (f_valid_row_tail (v_tail) (v_parameters) (v_subject)) with
| Fail __error -> Fail __error
| Done v_valid ->
(f_valid_row_operations (v_identities) (v_operations))))
and (* type_data.bend:174 *)
f_require_product_arity : int -> Base.text -> (M.t_Diagnostic, unit) Base.result_ =
fun v_count v_subject ->
(match v_count with
| 0 ->
(Fail ((M.Diagnostic (s_13, v_subject, s_14))))
| 1 ->
(Fail ((M.Diagnostic (s_13, v_subject, s_15))))
| __nat_2 when __nat_2 >= 2 ->
(let v_rest = (__nat_2 - 2) in
(Done (()))))
and (* type_data.bend:183 *)
f_free_annotation : (int) option -> Base.text -> (M.t_Diagnostic, unit) Base.result_ =
fun v_parameters v_subject ->
(match v_parameters with
| None ->
(Done (()))
| (Some (v_count)) ->
(Fail ((M.Diagnostic (s_7, v_subject, s_16)))))
and (* type_data.bend:190 *)
f_validate_work : int -> T.t_TypeWork -> (int) option -> (M.t_Operation) list -> (M.t_DataType) list -> Base.text -> (M.t_Diagnostic, unit) Base.result_ =
fun v_fuel v_work v_parameters v_operations v_types v_subject ->
(match (v_fuel, v_work) with
| (0, _) ->
(Fail ((T.f_complexity ())))
| (__nat_3, (T.OneType ((M.VariableTy (v_index))))) when __nat_3 >= 1 ->
(let v_rest = (__nat_3 - 1) in
(Fail ((M.Diagnostic (s_7, v_subject, s_17)))))
| (__nat_4, (T.OneType (M.NeverTy))) when __nat_4 >= 1 ->
(let v_rest = (__nat_4 - 1) in
(Fail ((M.Diagnostic (s_7, v_subject, s_18)))))
| (__nat_5, (T.OneType ((M.FreeTy (v_scope, v_name))))) when __nat_5 >= 1 ->
(let v_rest = (__nat_5 - 1) in
(f_free_annotation (v_parameters) (v_subject)))
| (__nat_6, (T.OneType ((M.ParameterTy (v_index))))) when __nat_6 >= 1 ->
(let v_rest = (__nat_6 - 1) in
(f_require ((f_valid_parameter (v_parameters) (v_index))) (v_subject) (s_19)))
| (__nat_7, (T.OneType ((M.AppliedTy (v_identity, v_arguments))))) when __nat_7 >= 1 ->
(let v_rest = (__nat_7 - 1) in
(match (f_valid_arity ((f_lookup (v_types) (v_identity))) ((Base.list_length (v_arguments))) (v_subject)) with
| Fail __error -> Fail __error
| Done v_arity ->
(f_validate_work (v_rest) ((T.ManyTypes (v_arguments))) (v_parameters) (v_operations) (v_types) (v_subject))))
| (__nat_8, (T.OneType ((M.ProductTy (v_elements))))) when __nat_8 >= 1 ->
(let v_rest = (__nat_8 - 1) in
(match (f_require_product_arity ((Base.list_length (v_elements))) (v_subject)) with
| Fail __error -> Fail __error
| Done v_arity ->
(f_validate_work (v_rest) ((T.ManyTypes (v_elements))) (v_parameters) (v_operations) (v_types) (v_subject))))
| (__nat_9, (T.OneType ((M.ArrayTy (v_element))))) when __nat_9 >= 1 ->
(let v_rest = (__nat_9 - 1) in
(f_validate_work (v_rest) ((T.OneType (v_element))) (v_parameters) (v_operations) (v_types) (v_subject)))
| (__nat_10, (T.OneType ((M.FunctionTy (v_parameter, v_result, v_effects))))) when __nat_10 >= 1 ->
(let v_rest = (__nat_10 - 1) in
(match (f_validate_row (v_effects) (v_parameters) (v_operations) (v_subject)) with
| Fail __error -> Fail __error
| Done v_row ->
(match (f_validate_work (v_rest) ((T.OneType (v_parameter))) (v_parameters) (v_operations) (v_types) (v_subject)) with
| Fail __error -> Fail __error
| Done v_p ->
(f_validate_work (v_rest) ((T.OneType (v_result))) (v_parameters) (v_operations) (v_types) (v_subject)))))
| (__nat_11, (T.OneType ((M.StateProviderTy (v_read, v_write, v_state))))) when __nat_11 >= 1 ->
(let v_rest = (__nat_11 - 1) in
(match (f_require_operation ((f_operation (v_operations) (v_read))) (v_read)) with
| Fail __error -> Fail __error
| Done v_reader ->
(match (f_require_operation ((f_operation (v_operations) (v_write))) (v_write)) with
| Fail __error -> Fail __error
| Done v_writer ->
(f_validate_work (v_rest) ((T.OneType (v_state))) (v_parameters) (v_operations) (v_types) (v_subject)))))
| (__nat_12, (T.OneType ((M.ProviderTy (v_identity, v_effects))))) when __nat_12 >= 1 ->
(let v_rest = (__nat_12 - 1) in
(match (f_require_operation ((f_operation (v_operations) (v_identity))) (v_identity)) with
| Fail __error -> Fail __error
| Done v_known ->
(f_validate_row (v_effects) (v_parameters) (v_operations) (v_subject))))
| (__nat_13, (T.OneType (v_scalar))) when __nat_13 >= 1 ->
(let v_rest = (__nat_13 - 1) in
(Done (())))
| (__nat_14, (T.ManyTypes ([]))) when __nat_14 >= 1 ->
(let v_rest = (__nat_14 - 1) in
(Done (())))
| (__nat_15, (T.ManyTypes ((v_head :: v_tail)))) when __nat_15 >= 1 ->
(let v_rest = (__nat_15 - 1) in
(match (f_validate_work (v_rest) ((T.OneType (v_head))) (v_parameters) (v_operations) (v_types) (v_subject)) with
| Fail __error -> Fail __error
| Done v_h ->
(f_validate_work (v_rest) ((T.ManyTypes (v_tail))) (v_parameters) (v_operations) (v_types) (v_subject)))))
and (* type_data.bend:235 *)
f_validate_template : M.t_Ty -> (int) option -> (M.t_Operation) list -> (M.t_DataType) list -> Base.text -> (M.t_Diagnostic, unit) Base.result_ =
fun v_ty v_parameters v_operations v_types v_subject ->
(match (f_validate_work ((Base.u32_to_nat ((Base.W32 0x10000)))) ((T.OneType (v_ty))) (v_parameters) (v_operations) (v_types) (v_subject)) with
| Fail __error -> Fail __error
| Done v_valid ->
(match (T.f_parameter_kinds ((Base.u32_to_nat ((Base.W32 0x10000)))) ((T.OneType (v_ty)))) with
| Fail __error -> Fail __error
| Done v_kinds ->
(T.f_kind_check (v_kinds) (v_subject))))
and (* type_data.bend:241 *)
f_annotation : (M.t_Ty) option -> (M.t_Operation) list -> (M.t_DataType) list -> Base.text -> (M.t_Diagnostic, unit) Base.result_ =
fun v_value v_operations v_types v_subject ->
(match v_value with
| None ->
(Done (()))
| (Some (v_ty)) ->
(f_validate_template (v_ty) (None) (v_operations) (v_types) (v_subject)))
and (* type_data.bend:248 *)
f_datatype_parameter_kinds : T.t_ParameterKinds -> Base.text -> (M.t_Diagnostic, unit) Base.result_ =
fun v_kinds v_subject ->
(match v_kinds with
| (T.ParameterKinds (v_types, [])) ->
(Done (()))
| (T.ParameterKinds (v_types, (v_head :: v_tail))) ->
(Fail ((M.Diagnostic (s_20, v_subject, s_21)))))
and (* type_data.bend:255 *)
f_field_shape : (Base.text) list -> (M.t_Ty) option -> bool =
fun v_fields v_payload ->
(match (v_fields, v_payload) with
| ([], _) ->
true
| ((v_name :: []), (Some (v_ty))) ->
true
| (v_fields, (Some ((M.ProductTy (v_elements))))) ->
(Base.nat_is_eq ((Base.list_length (v_fields))) ((Base.list_length (v_elements))))
| (_, _) ->
false)
and (* type_data.bend:266 *)
f_unique_fields : (Base.text) list -> Base.text -> Base.set -> (M.t_Diagnostic, unit) Base.result_ =
fun v_fields v_subject v_seen ->
(match v_fields with
| [] ->
(Done (()))
| (v_head :: v_tail) ->
(match (f_require ((Base.bool_not ((Base.maybe_is_some ((Index.f_find (v_seen) (v_head))))))) (v_subject) (s_22)) with
| Fail __error -> Fail __error
| Done v_valid ->
(f_unique_fields (v_tail) (v_subject) ((Base.set_add (v_seen) (v_head))))))
and (* type_data.bend:275 *)
f_validate_constructors : (M.t_Constructor) list -> int -> (M.t_Operation) list -> (M.t_DataType) list -> (M.t_Diagnostic, unit) Base.result_ =
fun v_constructors v_parameters v_operations v_types ->
(match v_constructors with
| [] ->
(Done (()))
| ((M.Constructor (v_name, None, v_fields)) :: v_tail) ->
(match (f_require ((f_field_shape (v_fields) (None))) (v_name) (s_23)) with
| Fail __error -> Fail __error
| Done v_valid ->
(f_validate_constructors (v_tail) (v_parameters) (v_operations) (v_types)))
| ((M.Constructor (v_name, (Some (v_payload)), v_fields)) :: v_tail) ->
(match (f_require ((f_field_shape (v_fields) ((Some (v_payload))))) (v_name) (s_24)) with
| Fail __error -> Fail __error
| Done v_shape ->
(match (f_unique_fields (v_fields) (v_name) ((Base.set_new ()))) with
| Fail __error -> Fail __error
| Done v_unique ->
(match (f_validate_work ((Base.u32_to_nat ((Base.W32 0x10000)))) ((T.OneType (v_payload))) ((Some (v_parameters))) (v_operations) (v_types) (v_name)) with
| Fail __error -> Fail __error
| Done v_valid ->
(match (T.f_parameter_kinds ((Base.u32_to_nat ((Base.W32 0x10000)))) ((T.OneType (v_payload)))) with
| Fail __error -> Fail __error
| Done v_kinds ->
(match (f_datatype_parameter_kinds (v_kinds) (v_name)) with
| Fail __error -> Fail __error
| Done v_values ->
(f_validate_constructors (v_tail) (v_parameters) (v_operations) (v_types))))))))
