(* Native semantic port of compiler/groups.bend.

   Source SHA-256: 541cbfd75d4df0b8a9f9bb053da7f83889d13c4f82fcac515cca10355ad824fa

   Ownership/type arguments are erased; value types are checked by OCaml.

   No Bend interpreter or generated C/JavaScript is linked. *)

open Base

module M = Ox_model

module T = Ox_types

module TD = Ox_type_data

module I = Ox_infer

module G = Ox_globals

module Check = Ox_check

module D = Ox_dependency

module E = Ox_effects

module R = Ox_effect_rows

module Index = Ox_index

module C = Ox_constraints

type t_Job =
  | Job of (Base.text) list * (Base.text) list * (M.t_TypeId) list
and t_InterfaceKind =
  | FunctionInterface
  | ConstantInterface
and t_Interface =
  | Interface of Base.text * t_InterfaceKind * M.t_Ty * int * (M.t_Effect) list * (M.t_Predicate) list
and t_CheckedGroup =
  | CheckedGroup of M.t_CheckedModule * (t_Interface) list * (C.t_UsePlan) list
and t_Resolution =
  | Resolution of Base.text * int * M.t_Dispatch * Base.text * (M.t_TypeId) list * M.t_Ty * M.t_Ty * M.t_Ty * (M.t_EffectRow) option * M.t_EffectRow
and t_GroupNeeds =
  | GroupNeeds of int * (t_Resolution) list * (I.t_Binding) list * (int) list
and t_Resolving =
  | Resolving of t_CheckedGroup * (t_GroupNeeds) list
and t_Usage =
  | Usage of (M.t_TypeId) list
and t_UsageWork =
  | ExpressionUsage of M.t_Expr
  | ArmsUsage of ((M.t_Expr) M.t_MatchArm) list
  | PatternUsage of M.t_Pattern
  | PatternsUsage of (M.t_Pattern) list
  | TypeUsage of M.t_Ty
  | TypesUsage of (M.t_Ty) list
  | PredicateUsage of M.t_Predicate
  | PredicatesUsage of (M.t_Predicate) list
  | ExpressionsUsage of (M.t_Expr) list
  | CollectedExpressionsUsage of (M.t_Expr) list * (t_Usage) list
  | CollectedPatternsUsage of (M.t_Pattern) list * (t_Usage) list
  | CollectedTypesUsage of (M.t_Ty) list * (t_Usage) list
  | CollectedPredicatesUsage of (M.t_Predicate) list * (t_Usage) list
  | CollectedArmsUsage of ((M.t_Expr) M.t_MatchArm) list * (t_Usage) list
and t_DeclarationUsage =
  | DeclarationUsage of Base.text * t_Usage
and t_TypeDependencies =
  | TypeDependencies of M.t_TypeId * (M.t_TypeId) list
and t_Planning =
  | Planning of (D.t_Node) list * (t_DeclarationUsage) list * (t_TypeDependencies) list * (M.t_TypeId) list
and t_TypeSet = (M.t_TypeId) Base.map

let s_0 = Base.text_of_utf8 "invalid_interface"

let s_1 = Base.text_of_utf8 "dependency effect metadata differs from its function row"

let s_2 = Base.text_of_utf8 "dependencies require pure constant initializers or function interfaces"

let s_3 = Base.text_of_utf8 "qualified operation predicate has the wrong number of type arguments"

let s_4 = Base.text_of_utf8 "qualified operation predicate does not name a generic operation template"

let s_5 = Base.text_of_utf8 "a dependency interface cannot expose an unquantified inference variable"

let s_6 = Base.text_of_utf8 "internal_error"

let s_7 = Base.text_of_utf8 "checked interface is missing its qualified binding"

let s_8 = Base.text_of_utf8 "expression_complexity"

let s_9 = Base.text_of_utf8 "inference"

let s_10 = Base.text_of_utf8 "dependency metadata exceeded compiler traversal limit"

let s_11 = Base.text_of_utf8 "unspecialized_effect"

let s_12 = Base.text_of_utf8 "effect"

let s_13 = Base.text_of_utf8 "effect instances must be specialized before dependency analysis"

let s_14 = Base.text_of_utf8 ":"

let rec (* groups.bend:29 *)
f_checked_interfaces : t_CheckedGroup -> (t_Interface) list =
fun v_group ->
(let (CheckedGroup (v_checked, v_interfaces, v_uses)) = v_group in
v_interfaces)
and (* groups.bend:33 *)
f_checked_uses : t_CheckedGroup -> (C.t_UsePlan) list =
fun v_group ->
(let (CheckedGroup (v_checked, v_interfaces, v_uses)) = v_group in
v_uses)
and (* groups.bend:37 *)
f_interface_names : (t_Interface) list -> (Base.text) list =
fun v_interfaces ->
(match v_interfaces with
| [] ->
[]
| ((Interface (v_name, v_kind, v_template, v_parameters, v_effects, v_predicates)) :: v_tail) ->
(v_name :: (f_interface_names (v_tail))))
and (* groups.bend:44 *)
f_interface_functions : (t_Interface) list -> (Base.text) list =
fun v_interfaces ->
(match v_interfaces with
| [] ->
[]
| ((Interface (v_name, FunctionInterface, v_template, v_parameters, v_effects, v_predicates)) :: v_tail) ->
(v_name :: (f_interface_functions (v_tail)))
| (v_head :: v_tail) ->
(f_interface_functions (v_tail)))
and (* groups.bend:53 *)
f_indices_accumulated : int -> int -> (int) list -> (int) list =
fun v_count v_start v_reversed ->
(match v_count with
| 0 ->
(Base.list_reverse (v_reversed))
| __nat_1 when __nat_1 >= 1 ->
(let v_rest = (__nat_1 - 1) in
(f_indices_accumulated (v_rest) ((Base.nat_add 1 v_start)) ((v_start :: v_reversed)))))
and (* groups.bend:60 *)
f_indices : int -> int -> (int) list =
fun v_count v_start ->
(f_indices_accumulated (v_count) (v_start) ([]))
and (* groups.bend:63 *)
f_same_effects : (M.t_Effect) list -> (M.t_Effect) list -> bool =
fun v_left v_right ->
(match (v_left, v_right) with
| ([], []) ->
true
| ((v_a :: v_left), (v_b :: v_right)) ->
(Base.bool_and ((E.f_effect_equal (v_a) (v_b))) ((f_same_effects (v_left) (v_right))))
| (_, _) ->
false)
and (* groups.bend:72 *)
f_valid_interface_effects : bool -> Base.text -> (M.t_Diagnostic, unit) Base.result_ =
fun v_consistent v_subject ->
(match v_consistent with
| true ->
(Done (()))
| false ->
(Fail ((M.Diagnostic (s_0, v_subject, s_1)))))
and (* groups.bend:79 *)
f_valid_interface_kind : t_InterfaceKind -> M.t_Ty -> int -> (M.t_Effect) list -> Base.text -> (M.t_Diagnostic, unit) Base.result_ =
fun v_kind v_template v_parameters v_effects v_subject ->
(match (v_kind, v_template, v_effects) with
| (FunctionInterface, (M.FunctionTy (v_parameter, v_result, v_row)), v_metadata) ->
(f_valid_interface_effects ((f_same_effects ((E.f_canonical (v_metadata))) ((R.f_metadata ((R.f_operation_set (v_row))))))) (v_subject))
| (ConstantInterface, _, []) ->
(Done (()))
| (_, _, _) ->
(Fail ((M.Diagnostic (s_0, v_subject, s_2)))))
and (* groups.bend:88 *)
f_validate_predicate_templates : (M.t_TypeId) list -> (M.t_Operation) list -> (M.t_Diagnostic, unit) Base.result_ =
fun v_templates v_operations ->
(match v_templates with
| [] ->
(Done (()))
| (v_head :: v_tail) ->
(match (I.f_operation_template (v_operations) (v_head)) with
| Fail __error -> Fail __error
| Done v_declared ->
(f_validate_predicate_templates (v_tail) (v_operations))))
and (* groups.bend:97 *)
f_validate_operation_arity : M.t_Operation -> int -> Base.text -> (M.t_Diagnostic, unit) Base.result_ =
fun v_declared v_count v_subject ->
(match v_declared with
| (M.OperationTemplate (v_identity, v_parameters, v_parameter, v_result)) ->
(Base.bool_pick ((Base.nat_is_eq (v_parameters) (v_count))) ((Done (()))) ((Fail ((M.Diagnostic (s_0, v_subject, s_3))))))
| _ ->
(Fail ((M.Diagnostic (s_0, v_subject, s_4)))))
and (* groups.bend:104 *)
f_validate_predicate_arity : M.t_Predicate -> (M.t_Operation) list -> Base.text -> (M.t_Diagnostic, unit) Base.result_ =
fun v_predicate v_operations v_subject ->
(match v_predicate with
| (M.OperationPredicate (v_template, v_arguments, v_function_type)) ->
(match (I.f_operation_template (v_operations) (v_template)) with
| Fail __error -> Fail __error
| Done v_declared ->
(f_validate_operation_arity (v_declared) ((Base.list_length (v_arguments))) (v_subject)))
| _ ->
(Done (())))
and (* groups.bend:113 *)
f_validate_predicates : (M.t_Predicate) list -> int -> (M.t_Operation) list -> (M.t_DataType) list -> Base.text -> (M.t_Diagnostic, unit) Base.result_ =
fun v_predicates v_parameters v_operations v_types v_subject ->
(match v_predicates with
| [] ->
(Done (()))
| (v_head :: v_tail) ->
(match (TD.f_validate_template ((C.f_shape_type (v_head))) ((Some (v_parameters))) (v_operations) (v_types) (v_subject)) with
| Fail __error -> Fail __error
| Done v_valid ->
(match (C.f_free (v_head)) with
| Fail __error -> Fail __error
| Done v_source_names ->
(match (f_validate_predicate_templates ((C.f_predicate_templates ([v_head]))) (v_operations)) with
| Fail __error -> Fail __error
| Done v_known ->
(match (f_validate_predicate_arity (v_head) (v_operations) (v_subject)) with
| Fail __error -> Fail __error
| Done v_arity ->
(f_validate_predicates (v_tail) (v_parameters) (v_operations) (v_types) (v_subject)))))))
and (* groups.bend:125 *)
f_predicate_shapes_accumulated : (M.t_Predicate) list -> (M.t_Ty) list -> (M.t_Ty) list =
fun v_predicates v_reversed ->
(match v_predicates with
| [] ->
(Base.list_reverse (v_reversed))
| (v_head :: v_tail) ->
(f_predicate_shapes_accumulated (v_tail) (((C.f_shape_type (v_head)) :: v_reversed))))
and (* groups.bend:132 *)
f_predicate_shapes : (M.t_Predicate) list -> (M.t_Ty) list =
fun v_predicates ->
(f_predicate_shapes_accumulated (v_predicates) ([]))
and (* groups.bend:139 *)
f_scheme_kind_groups : int -> (M.t_Ty) list -> (T.t_ParameterKinds) list -> (M.t_Diagnostic, (T.t_ParameterKinds) list) Base.result_ =
fun v_fuel v_pending v_reversed ->
(match (v_fuel, v_pending) with
| (0, _) ->
(Fail ((T.f_complexity ())))
| (__nat_2, []) when __nat_2 >= 1 ->
(let v_rest = (__nat_2 - 1) in
(Done (v_reversed)))
| (__nat_3, (v_head :: v_tail)) when __nat_3 >= 1 ->
(let v_rest = (__nat_3 - 1) in
(match (T.f_parameter_kinds (v_rest) ((T.OneType (v_head)))) with
| Fail __error -> Fail __error
| Done v_first ->
(f_scheme_kind_groups (v_rest) (v_tail) ((v_first :: v_reversed))))))
and (* groups.bend:150 *)
f_scheme_kind_merge : (T.t_ParameterKinds) list -> T.t_ParameterKinds -> T.t_ParameterKinds =
fun v_reversed v_merged ->
(match v_reversed with
| [] ->
v_merged
| (v_head :: v_tail) ->
(f_scheme_kind_merge (v_tail) ((T.f_merge_kinds (v_head) (v_merged)))))
and (* groups.bend:157 *)
f_scheme_kinds : int -> (M.t_Ty) list -> (M.t_Diagnostic, T.t_ParameterKinds) Base.result_ =
fun v_fuel v_pending ->
(match (f_scheme_kind_groups (v_fuel) (v_pending) ([])) with
| Fail __error -> Fail __error
| Done v_reversed ->
(Done ((f_scheme_kind_merge (v_reversed) ((T.ParameterKinds ([], [])))))))
and (* groups.bend:165 *)
f_validate_scheme_kinds : M.t_Ty -> (M.t_Predicate) list -> Base.text -> (M.t_Diagnostic, unit) Base.result_ =
fun v_template v_predicates v_subject ->
(match (f_scheme_kinds ((Base.u32_to_nat (0x00010000l))) ((v_template :: (f_predicate_shapes (v_predicates))))) with
| Fail __error -> Fail __error
| Done v_kinds ->
(T.f_kind_check (v_kinds) (v_subject)))
and (* groups.bend:170 *)
f_import_interfaces : (t_Interface) list -> (M.t_Operation) list -> (M.t_DataType) list -> int -> (M.t_Diagnostic, G.t_Environment) Base.result_ =
fun v_interfaces v_operations v_types v_start ->
(match v_interfaces with
| [] ->
(Done ((G.Environment ([], [], (I.State ((T.f_empty ()), v_start, MTip))))))
| ((Interface (v_name, v_kind, v_template, v_parameters, v_effects, v_predicates)) :: v_tail) ->
(match (TD.f_validate_template (v_template) ((Some (v_parameters))) (v_operations) (v_types) (v_name)) with
| Fail __error -> Fail __error
| Done v_valid ->
(match (C.f_free ((M.TypeRepPredicate (v_template)))) with
| Fail __error -> Fail __error
| Done v_source_names ->
(match (f_valid_interface_kind (v_kind) (v_template) (v_parameters) (v_effects) (v_name)) with
| Fail __error -> Fail __error
| Done v_compatible ->
(match (f_validate_predicates (v_predicates) (v_parameters) (v_operations) (v_types) (v_name)) with
| Fail __error -> Fail __error
| Done v_valid_needs ->
(match (f_validate_scheme_kinds (v_template) (v_predicates) (v_name)) with
| Fail __error -> Fail __error
| Done v_kinds ->
(let v_arguments = (TD.f_fresh_arguments (v_parameters) (v_start)) in
(match (T.f_parameters (v_arguments) (0) (v_template)) with
| Fail __error -> Fail __error
| Done v_ty ->
(match (C.f_instantiate_parameters (v_arguments) (v_predicates) (0)) with
| Fail __error -> Fail __error
| Done v_needs ->
(match (f_import_interfaces (v_tail) (v_operations) (v_types) ((Base.nat_add (v_start) (v_parameters)))) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done ((G.Environment (((I.Binding (v_name, v_ty, (f_indices (v_parameters) (v_start)), v_needs)) :: (G.f_env_bindings (v_rest))), ((I.Definition (v_name, (I.f_pure (v_ty)))) :: (G.f_env_definitions (v_rest))), (G.f_env_state (v_rest))))))))))))))))
and (* groups.bend:187 *)
f_template_type_sequential : (int) list -> int -> M.t_Ty -> (M.t_Diagnostic, M.t_Ty) Base.result_ =
fun v_variables v_index v_ty ->
(match v_variables with
| [] ->
(Done (v_ty))
| (v_head :: v_tail) ->
(match (T.f_replace (v_ty) (v_head) ((M.ParameterTy (v_index)))) with
| Fail __error -> Fail __error
| Done v_replaced ->
(f_template_type_sequential (v_tail) ((Base.nat_add 1 v_index)) (v_replaced))))
and (* groups.bend:196 *)
f_template_type : (int) list -> int -> M.t_Ty -> (M.t_Diagnostic, M.t_Ty) Base.result_ =
fun v_variables v_index v_ty ->
(match v_variables with
| [] ->
(Done (v_ty))
| (v_head :: []) ->
(T.f_replace (v_ty) (v_head) ((M.ParameterTy (v_index))))
| (v_head :: v_tail) ->
(T.f_parameterize_type (v_ty) ((T.f_parameter_mapping ((v_head :: v_tail)) (v_index)))))
and (* groups.bend:205 *)
f_canonical_work : int -> T.t_TypeWork -> (M.t_Diagnostic, (M.t_Ty) list) Base.result_ =
fun v_fuel v_work ->
(match (v_fuel, v_work) with
| (0, _) ->
(Fail ((T.f_complexity ())))
| (__nat_4, (T.OneType ((M.FunctionTy (v_parameter, v_result, v_effects))))) when __nat_4 >= 1 ->
(let v_rest = (__nat_4 - 1) in
(match (f_canonical_work (v_rest) ((T.OneType (v_parameter)))) with
| Fail __error -> Fail __error
| Done v_ps ->
(match (f_canonical_work (v_rest) ((T.OneType (v_result)))) with
| Fail __error -> Fail __error
| Done v_rs ->
(match (T.f_first_type (v_ps)) with
| Fail __error -> Fail __error
| Done v_p ->
(match (T.f_first_type (v_rs)) with
| Fail __error -> Fail __error
| Done v_r ->
(Done ([(M.FunctionTy (v_p, v_r, (R.f_canonical (v_effects))))])))))))
| (__nat_5, (T.OneType ((M.StateProviderTy (v_read, v_write, v_state))))) when __nat_5 >= 1 ->
(let v_rest = (__nat_5 - 1) in
(match (f_canonical_work (v_rest) ((T.OneType (v_state)))) with
| Fail __error -> Fail __error
| Done v_values ->
(match (T.f_first_type (v_values)) with
| Fail __error -> Fail __error
| Done v_value ->
(Done ([(M.StateProviderTy (v_read, v_write, v_value))])))))
| (__nat_6, (T.OneType ((M.ProviderTy (v_identity, v_effects))))) when __nat_6 >= 1 ->
(let v_rest = (__nat_6 - 1) in
(Done ([(M.ProviderTy (v_identity, (R.f_canonical (v_effects))))])))
| (__nat_7, (T.OneType ((M.AppliedTy (v_identity, v_arguments))))) when __nat_7 >= 1 ->
(let v_rest = (__nat_7 - 1) in
(match (f_canonical_work (v_rest) ((T.ManyTypes (v_arguments)))) with
| Fail __error -> Fail __error
| Done v_values ->
(Done ([(M.AppliedTy (v_identity, v_values))]))))
| (__nat_8, (T.OneType ((M.ProductTy (v_elements))))) when __nat_8 >= 1 ->
(let v_rest = (__nat_8 - 1) in
(match (f_canonical_work (v_rest) ((T.ManyTypes (v_elements)))) with
| Fail __error -> Fail __error
| Done v_values ->
(Done ([(M.ProductTy (v_values))]))))
| (__nat_9, (T.OneType ((M.ArrayTy (v_element))))) when __nat_9 >= 1 ->
(let v_rest = (__nat_9 - 1) in
(match (f_canonical_work (v_rest) ((T.OneType (v_element)))) with
| Fail __error -> Fail __error
| Done v_values ->
(match (T.f_first_type (v_values)) with
| Fail __error -> Fail __error
| Done v_value ->
(Done ([(M.ArrayTy (v_value))])))))
| (__nat_10, (T.OneType (v_other))) when __nat_10 >= 1 ->
(let v_rest = (__nat_10 - 1) in
(Done ([v_other])))
| (__nat_11, (T.ManyTypes ([]))) when __nat_11 >= 1 ->
(let v_rest = (__nat_11 - 1) in
(Done ([])))
| (__nat_12, (T.ManyTypes ((v_head :: v_tail)))) when __nat_12 >= 1 ->
(let v_rest = (__nat_12 - 1) in
(match (f_canonical_work (v_rest) ((T.OneType (v_head)))) with
| Fail __error -> Fail __error
| Done v_hs ->
(match (T.f_first_type (v_hs)) with
| Fail __error -> Fail __error
| Done v_h ->
(match (f_canonical_work (v_rest) ((T.ManyTypes (v_tail)))) with
| Fail __error -> Fail __error
| Done v_ts ->
(Done ((v_h :: v_ts))))))))
and (* groups.bend:249 *)
f_interface_variable_count : (int) list -> int -> int =
fun v_variables v_count ->
(match v_variables with
| [] ->
v_count
| (v_head :: v_tail) ->
(f_interface_variable_count (v_tail) ((Base.nat_add (v_count) (1)))))
and (* groups.bend:256 *)
f_closed_interface : (int) list -> (int) list -> Base.text -> t_InterfaceKind -> M.t_Ty -> (M.t_Effect) list -> (M.t_Predicate) list -> (M.t_Diagnostic, (t_Interface) list) Base.result_ =
fun v_open v_variables v_name v_kind v_ty v_effects v_predicates ->
(match v_open with
| [] ->
(match (f_template_type (v_variables) (0) (v_ty)) with
| Fail __error -> Fail __error
| Done v_template ->
(match (C.f_parameterize_list ((T.f_parameter_mapping (v_variables) (0))) (v_predicates)) with
| Fail __error -> Fail __error
| Done v_needs ->
(Done ([(Interface (v_name, v_kind, v_template, (f_interface_variable_count (v_variables) (0)), (E.f_canonical (v_effects)), v_needs))]))))
| (v_head :: v_tail) ->
(Fail ((M.Diagnostic (s_0, v_name, s_5)))))
and (* groups.bend:266 *)
f_export_interface : Base.text -> t_InterfaceKind -> M.t_Ty -> (int) list -> (M.t_Effect) list -> (M.t_Predicate) list -> (M.t_Diagnostic, (t_Interface) list) Base.result_ =
fun v_name v_kind v_ty v_variables v_effects v_predicates ->
(match (f_canonical_work ((Base.nat_mul (256) (256))) ((T.OneType (v_ty)))) with
| Fail __error -> Fail __error
| Done v_normalized ->
(match (T.f_first_type (v_normalized)) with
| Fail __error -> Fail __error
| Done v_canonical ->
(match (T.f_free (v_canonical)) with
| Fail __error -> Fail __error
| Done v_type_free ->
(let v_needs = (C.f_canonical_predicates (v_predicates) ([])) in
(match (C.f_free_list (v_needs)) with
| Fail __error -> Fail __error
| Done v_predicate_free ->
(let v_free = (T.f_union (v_type_free) (v_predicate_free)) in
(f_closed_interface ((T.f_difference (v_free) (v_variables))) (v_free) (v_name) (v_kind) (v_canonical) (v_effects) (v_needs))))))))
and (* groups.bend:276 *)
f_binding_predicates_found : (I.t_Binding) option -> T.t_Substitutions -> Base.text -> (M.t_Diagnostic, (M.t_Predicate) list) Base.result_ =
fun v_found v_substitutions v_name ->
(match v_found with
| None ->
(Fail ((M.Diagnostic (s_6, v_name, s_7))))
| (Some ((I.Binding (v_found, v_ty, v_variables, v_predicates)))) ->
(C.f_resolve_list (v_substitutions) (v_predicates)))
and (* groups.bend:283 *)
f_binding_predicates : (I.t_Binding) list -> Base.text -> T.t_Substitutions -> (M.t_Diagnostic, (M.t_Predicate) list) Base.result_ =
fun v_bindings v_name v_substitutions ->
(f_binding_predicates_found ((I.f_lookup_binding (v_bindings) (v_name))) (v_substitutions) (v_name))
and (* groups.bend:286 *)
f_function_interfaces : (M.t_CheckedFunction) list -> (I.t_Binding) list -> T.t_Substitutions -> (M.t_Diagnostic, (t_Interface) list) Base.result_ =
fun v_functions v_bindings v_substitutions ->
(match v_functions with
| [] ->
(Done ([]))
| ((M.CheckedFunction (v_function, (M.Signature (v_name, v_parameter, v_result, v_variables, v_row)), v_effects)) :: v_tail) ->
(match (f_binding_predicates (v_bindings) (v_name) (v_substitutions)) with
| Fail __error -> Fail __error
| Done v_predicates ->
(match (f_export_interface (v_name) (FunctionInterface) ((M.FunctionTy (v_parameter, v_result, v_row))) (v_variables) (v_effects) (v_predicates)) with
| Fail __error -> Fail __error
| Done v_head ->
(match (f_function_interfaces (v_tail) (v_bindings) (v_substitutions)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done ((Base.list_append (v_head) (v_rest))))))))
and (* groups.bend:297 *)
f_constant_interfaces : (M.t_CheckedConstant) list -> (I.t_Binding) list -> T.t_Substitutions -> (M.t_Diagnostic, (t_Interface) list) Base.result_ =
fun v_constants v_bindings v_substitutions ->
(match v_constants with
| [] ->
(Done ([]))
| ((M.CheckedConstant ((M.Constant (v_name, v_exported, v_annotation, v_value)), v_ty, v_variables)) :: v_tail) ->
(match (f_binding_predicates (v_bindings) (v_name) (v_substitutions)) with
| Fail __error -> Fail __error
| Done v_predicates ->
(match (f_export_interface (v_name) (ConstantInterface) (v_ty) (v_variables) ([]) (v_predicates)) with
| Fail __error -> Fail __error
| Done v_head ->
(match (f_constant_interfaces (v_tail) (v_bindings) (v_substitutions)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done ((Base.list_append (v_head) (v_rest))))))))
and (* groups.bend:308 *)
f_checked_function_names : (M.t_CheckedFunction) list -> (Base.text) list =
fun v_functions ->
(match v_functions with
| [] ->
[]
| ((M.CheckedFunction ((M.Function (v_name, v_exported, v_parameter, v_p, v_r, v_body)), v_signature, v_effects)) :: v_tail) ->
(v_name :: (f_checked_function_names (v_tail))))
and (* groups.bend:315 *)
f_checked_constant_names : (M.t_CheckedConstant) list -> (Base.text) list =
fun v_constants ->
(match v_constants with
| [] ->
[]
| ((M.CheckedConstant ((M.Constant (v_name, v_exported, v_annotation, v_value)), v_ty, v_variables)) :: v_tail) ->
(v_name :: (f_checked_constant_names (v_tail))))
and (* groups.bend:322 *)
f_append_own_uses : bool -> I.t_Inference -> (C.t_UsePlan) list -> T.t_Substitutions -> (M.t_Diagnostic, (C.t_UsePlan) list) Base.result_ =
fun v_owned v_inference v_rest v_substitutions ->
(match v_owned with
| false ->
(Done (v_rest))
| true ->
(match (C.f_resolve_uses ((I.f_inference_uses (v_inference))) (v_substitutions)) with
| Fail __error -> Fail __error
| Done v_current ->
(Done ((Base.list_append (v_current) (v_rest))))))
and (* groups.bend:331 *)
f_own_uses : (I.t_Definition) list -> (Base.text) list -> T.t_Substitutions -> (M.t_Diagnostic, (C.t_UsePlan) list) Base.result_ =
fun v_definitions v_names v_substitutions ->
(match v_definitions with
| [] ->
(Done ([]))
| ((I.Definition (v_name, v_inference)) :: v_tail) ->
(match (f_own_uses (v_tail) (v_names) (v_substitutions)) with
| Fail __error -> Fail __error
| Done v_rest ->
(f_append_own_uses ((D.f_contains (v_names) (v_name))) (v_inference) (v_rest) (v_substitutions))))
and (* groups.bend:340 *)
f_checked_group : M.t_CheckedModule -> G.t_Environment -> (M.t_Diagnostic, t_CheckedGroup) Base.result_ =
fun v_checked v_environment ->
(let (M.CheckedModule (v_constants, v_functions, v_types, v_operations)) = v_checked in
(let v_bindings = (G.f_env_bindings (v_environment)) in
(let v_substitutions = (I.f_substitutions_of ((G.f_env_state (v_environment)))) in
(match (f_function_interfaces (v_functions) (v_bindings) (v_substitutions)) with
| Fail __error -> Fail __error
| Done v_fns ->
(match (f_constant_interfaces (v_constants) (v_bindings) (v_substitutions)) with
| Fail __error -> Fail __error
| Done v_consts ->
(match (f_own_uses ((G.f_env_definitions (v_environment))) ((Base.list_append ((f_checked_function_names (v_functions))) ((f_checked_constant_names (v_constants))))) (v_substitutions)) with
| Fail __error -> Fail __error
| Done v_uses ->
(Done ((CheckedGroup (v_checked, (Base.list_append (v_fns) (v_consts)), v_uses))))))))))
and (* groups.bend:367 *)
f_resolving_group : t_Resolving -> t_CheckedGroup =
fun v_value ->
(let (Resolving (v_group, v_needs)) = v_value in
v_group)
and (* groups.bend:373 *)
f_closed_types : int -> (M.t_Ty) list -> bool =
fun v_fuel v_pending ->
(match (v_fuel, v_pending) with
| (_, []) ->
true
| (0, _) ->
false
| (__nat_13, ((M.VariableTy (v_index)) :: v_tail)) when __nat_13 >= 1 ->
(let v_rest = (__nat_13 - 1) in
false)
| (__nat_14, ((M.ParameterTy (v_index)) :: v_tail)) when __nat_14 >= 1 ->
(let v_rest = (__nat_14 - 1) in
false)
| (__nat_15, ((M.FreeTy (v_scope, v_name)) :: v_tail)) when __nat_15 >= 1 ->
(let v_rest = (__nat_15 - 1) in
false)
| (__nat_16, ((M.FunctionTy (v_parameter, v_result, (M.EffectRow (v_operations, M.ClosedRow)))) :: v_tail)) when __nat_16 >= 1 ->
(let v_rest = (__nat_16 - 1) in
(f_closed_types (v_rest) ((v_parameter :: (v_result :: v_tail)))))
| (__nat_17, ((M.FunctionTy (v_parameter, v_result, v_row)) :: v_tail)) when __nat_17 >= 1 ->
(let v_rest = (__nat_17 - 1) in
false)
| (__nat_18, ((M.ProviderTy (v_identity, (M.EffectRow (v_operations, M.ClosedRow)))) :: v_tail)) when __nat_18 >= 1 ->
(let v_rest = (__nat_18 - 1) in
(f_closed_types (v_rest) (v_tail)))
| (__nat_19, ((M.ProviderTy (v_identity, v_row)) :: v_tail)) when __nat_19 >= 1 ->
(let v_rest = (__nat_19 - 1) in
false)
| (__nat_20, ((M.StateProviderTy (v_read, v_write, v_state)) :: v_tail)) when __nat_20 >= 1 ->
(let v_rest = (__nat_20 - 1) in
(f_closed_types (v_rest) ((v_state :: v_tail))))
| (__nat_21, ((M.AppliedTy (v_identity, v_arguments)) :: v_tail)) when __nat_21 >= 1 ->
(let v_rest = (__nat_21 - 1) in
(f_closed_types (v_rest) ((Base.list_append (v_arguments) (v_tail)))))
| (__nat_22, ((M.ProductTy (v_elements)) :: v_tail)) when __nat_22 >= 1 ->
(let v_rest = (__nat_22 - 1) in
(f_closed_types (v_rest) ((Base.list_append (v_elements) (v_tail)))))
| (__nat_23, ((M.ArrayTy (v_element)) :: v_tail)) when __nat_23 >= 1 ->
(let v_rest = (__nat_23 - 1) in
(f_closed_types (v_rest) ((v_element :: v_tail))))
| (__nat_24, (v_head :: v_tail)) when __nat_24 >= 1 ->
(let v_rest = (__nat_24 - 1) in
(f_closed_types (v_rest) (v_tail))))
and (* groups.bend:404 *)
f_resolved_invocation : (M.t_EffectRow) option -> T.t_Substitutions -> (M.t_EffectRow) option =
fun v_invocation v_substitutions ->
(match v_invocation with
| None ->
None
| (Some (v_row)) ->
(Some ((T.f_resolve_row (v_substitutions) (v_row)))))
and (* groups.bend:411 *)
f_resolved_need : (M.t_Diagnostic, M.t_Ty) Base.result_ -> (M.t_Diagnostic, M.t_Ty) Base.result_ -> (M.t_Diagnostic, M.t_Ty) Base.result_ -> Base.text -> int -> M.t_Dispatch -> Base.text -> (M.t_TypeId) list -> (M.t_EffectRow) option -> M.t_EffectRow -> (t_Resolution) list -> (t_Resolution) list =
fun v_left v_right v_result v_declaration v_identity v_dispatch v_member v_templates v_invocation v_ambient v_rest ->
(match (v_left, v_right, v_result) with
| ((Done (v_l)), (Done (v_r)), (Done (v_value))) ->
((Resolution (v_declaration, v_identity, v_dispatch, v_member, v_templates, v_l, v_r, v_value, v_invocation, v_ambient)) :: v_rest)
| (_, _, _) ->
v_rest)
and (* groups.bend:418 *)
f_coverage_needs : (I.t_Coverage) list -> Base.text -> T.t_Substitutions -> (t_Resolution) list -> (t_Resolution) list =
fun v_coverage v_declaration v_substitutions v_reversed ->
(match v_coverage with
| [] ->
(Base.list_reverse (v_reversed))
| ((I.AssociatedNeed (v_identity, v_dispatch, v_member, v_templates, v_left, v_right, v_result, v_invocation, v_ambient, v_subject)) :: v_tail) ->
(f_coverage_needs (v_tail) (v_declaration) (v_substitutions) ((f_resolved_need ((T.f_resolve (v_substitutions) (v_left))) ((T.f_resolve (v_substitutions) (v_right))) ((T.f_resolve (v_substitutions) (v_result))) (v_declaration) (v_identity) (v_dispatch) (v_member) (v_templates) ((f_resolved_invocation (v_invocation) (v_substitutions))) ((T.f_resolve_row (v_substitutions) (v_ambient))) (v_reversed))))
| (v_head :: v_tail) ->
(f_coverage_needs (v_tail) (v_declaration) (v_substitutions) (v_reversed)))
and (* groups.bend:427 *)
f_definition_needs : (I.t_Definition) list -> T.t_Substitutions -> (t_Resolution) list =
fun v_definitions v_substitutions ->
(match v_definitions with
| [] ->
[]
| ((I.Definition (v_name, (I.Inference (v_ty, v_coverage, v_exits, v_reflections, v_predicates, v_uses)))) :: v_tail) ->
(Base.list_append ((f_coverage_needs (v_coverage) (v_name) (v_substitutions) ([]))) ((f_definition_needs (v_tail) (v_substitutions)))))
and (* groups.bend:434 *)
f_member_resolved : Base.text -> (M.t_Diagnostic, M.t_Ty) Base.result_ -> (M.t_Diagnostic, (M.t_Predicate) list) Base.result_ -> (I.t_Binding) list -> (I.t_Binding) list =
fun v_name v_resolved v_predicates v_rest ->
(match (v_resolved, v_predicates) with
| ((Done (v_ty)), (Done (v_resolved_predicates))) ->
((I.Binding (v_name, v_ty, [], v_resolved_predicates)) :: v_rest)
| (_, _) ->
v_rest)
and (* groups.bend:441 *)
f_member_binding : bool -> Base.text -> M.t_Ty -> (M.t_Predicate) list -> T.t_Substitutions -> (I.t_Binding) list -> (I.t_Binding) list =
fun v_member v_name v_ty v_predicates v_substitutions v_rest ->
(match v_member with
| false ->
v_rest
| true ->
(f_member_resolved (v_name) ((T.f_resolve (v_substitutions) (v_ty))) ((C.f_resolve_list (v_substitutions) (v_predicates))) (v_rest)))
and (* groups.bend:450 *)
f_member_bindings : (I.t_Definition) list -> Base.set -> T.t_Substitutions -> (I.t_Binding) list =
fun v_definitions v_members v_substitutions ->
(match v_definitions with
| [] ->
[]
| ((I.Definition (v_name, (I.Inference (v_ty, v_coverage, v_exits, v_reflections, v_predicates, v_uses)))) :: v_tail) ->
(let v_rest = (f_member_bindings (v_tail) (v_members) (v_substitutions)) in
(f_member_binding ((D.f_member (v_members) (v_name))) (v_name) (v_ty) (v_predicates) (v_substitutions) (v_rest))))
and (* groups.bend:461 *)
f_witness_variables : (M.t_Diagnostic, (int) list) Base.result_ -> (int) list -> (M.t_Diagnostic, (int) list) Base.result_ =
fun v_free v_found ->
(match v_free with
| Fail __error -> Fail __error
| Done v_variables ->
(Done ((T.f_union (v_variables) (v_found)))))
and (* groups.bend:466 *)
f_coverage_generalized : (I.t_Coverage) list -> T.t_Substitutions -> (int) list -> (M.t_Diagnostic, (int) list) Base.result_ =
fun v_coverage v_substitutions v_found ->
(match v_coverage with
| [] ->
(Done (v_found))
| ((I.LetGeneralized (v_witness)) :: v_tail) ->
(match (T.f_resolve (v_substitutions) (v_witness)) with
| Fail __error -> Fail __error
| Done v_resolved ->
(match (f_witness_variables ((T.f_free (v_resolved))) (v_found)) with
| Fail __error -> Fail __error
| Done v_variables ->
(f_coverage_generalized (v_tail) (v_substitutions) (v_variables))))
| (v_head :: v_tail) ->
(f_coverage_generalized (v_tail) (v_substitutions) (v_found)))
and (* groups.bend:478 *)
f_definition_generalized : (I.t_Definition) list -> T.t_Substitutions -> (int) list -> (M.t_Diagnostic, (int) list) Base.result_ =
fun v_definitions v_substitutions v_found ->
(match v_definitions with
| [] ->
(Done (v_found))
| ((I.Definition (v_name, (I.Inference (v_ty, v_coverage, v_exits, v_reflections, v_predicates, v_uses)))) :: v_tail) ->
(match (f_coverage_generalized (v_coverage) (v_substitutions) (v_found)) with
| Fail __error -> Fail __error
| Done v_variables ->
(f_definition_generalized (v_tail) (v_substitutions) (v_variables))))
and (* groups.bend:487 *)
f_group_needs : (t_Resolution) list -> int -> (I.t_Binding) list -> (M.t_Diagnostic, (int) list) Base.result_ -> (t_GroupNeeds) list =
fun v_needs v_next v_members v_generalized ->
(match (v_needs, v_generalized) with
| ([], _) ->
[]
| (_, (Fail (v_diagnostic))) ->
[]
| ((v_head :: v_tail), (Done (v_variables))) ->
[(GroupNeeds (v_next, (v_head :: v_tail), v_members, v_variables))])
and (* groups.bend:496 *)
f_environment_needs : bool -> G.t_Environment -> (Base.text) list -> (t_GroupNeeds) list =
fun v_collect v_environment v_names ->
(match v_collect with
| false ->
[]
| true ->
(let (G.Environment (v_bindings, v_definitions, v_state)) = v_environment in
(let v_substitutions = (I.f_substitutions_of (v_state)) in
(f_group_needs ((f_definition_needs (v_definitions) (v_substitutions))) ((I.f_next_of (v_state))) ((f_member_bindings (v_definitions) ((Base.set_from_list (v_names))) (v_substitutions))) ((f_definition_generalized (v_definitions) (v_substitutions) ([])))))))
and (* groups.bend:505 *)
f_check_group_resolving_graph : M.t_Module -> (t_Interface) list -> (M.t_Diagnostic, (D.t_Node) list) Base.result_ -> bool -> (M.t_Diagnostic, t_Resolving) Base.result_ =
fun v_module v_dependencies v_graph_result v_collect ->
(let (M.Module (v_constants, v_functions, v_types, v_operations)) = v_module in
(let v_declarations = (Base.list_append ((G.f_function_declarations (v_functions))) ((G.f_constant_declarations (v_constants)))) in
(match v_graph_result with
| Fail __error -> Fail __error
| Done v_graph ->
(match (Check.f_unique_names ((Base.list_append ((f_interface_names (v_dependencies))) ((Base.list_append ((G.f_names (v_declarations))) ((Check.f_all_constructor_names (v_types)))))))) with
| Fail __error -> Fail __error
| Done v_unique ->
(match (f_import_interfaces (v_dependencies) (v_operations) (v_types) (0)) with
| Fail __error -> Fail __error
| Done v_imported ->
(match (G.f_infer_with (v_declarations) (v_graph) (v_operations) (v_types) (v_imported) ((f_interface_functions (v_dependencies)))) with
| Fail __error -> Fail __error
| Done v_environment ->
(match (Check.f_finish (v_module) (v_environment)) with
| Fail __error -> Fail __error
| Done v_checked ->
(match (f_checked_group (v_checked) (v_environment)) with
| Fail __error -> Fail __error
| Done v_group ->
(Done ((Resolving (v_group, (f_environment_needs (v_collect) (v_environment) ((G.f_names (v_declarations))))))))))))))))
and (* groups.bend:517 *)
f_check_group_graph : M.t_Module -> (t_Interface) list -> (M.t_Diagnostic, (D.t_Node) list) Base.result_ -> (M.t_Diagnostic, t_CheckedGroup) Base.result_ =
fun v_module v_dependencies v_graph_result ->
(match (f_check_group_resolving_graph (v_module) (v_dependencies) (v_graph_result) (false)) with
| Fail __error -> Fail __error
| Done v_resolved ->
(Done ((f_resolving_group (v_resolved)))))
and (* groups.bend:522 *)
f_check_group : M.t_Module -> (t_Interface) list -> (M.t_Diagnostic, t_CheckedGroup) Base.result_ =
fun v_module v_dependencies ->
(f_check_group_graph (v_module) (v_dependencies) ((Check.f_module_graph (v_module))))
and (* groups.bend:527 *)
f_check_group_planned : M.t_Module -> (t_Interface) list -> (M.t_Diagnostic, t_CheckedGroup) Base.result_ =
fun v_module v_dependencies ->
(f_check_group_graph (v_module) (v_dependencies) ((Check.f_module_graph_validated (v_module))))
and (* groups.bend:531 *)
f_check_group_resolving : M.t_Module -> (t_Interface) list -> (M.t_Diagnostic, t_Resolving) Base.result_ =
fun v_module v_dependencies ->
(f_check_group_resolving_graph (v_module) (v_dependencies) ((Check.f_module_graph (v_module))) (true))
and (* groups.bend:534 *)
f_check_group_resolving_planned : M.t_Module -> (t_Interface) list -> (M.t_Diagnostic, t_Resolving) Base.result_ =
fun v_module v_dependencies ->
(f_check_group_resolving_graph (v_module) (v_dependencies) ((Check.f_module_graph_validated (v_module))) (true))
and (* groups.bend:556 *)
f_contains_type : (M.t_TypeId) list -> M.t_TypeId -> bool =
fun v_identities v_identity ->
(match v_identities with
| [] ->
false
| (v_head :: v_tail) ->
(Base.bool_or ((M.f_type_id_equal (v_head) (v_identity))) ((f_contains_type (v_tail) (v_identity)))))
and (* groups.bend:563 *)
f_put_type_if : bool -> (M.t_TypeId) list -> M.t_TypeId -> (M.t_TypeId) list =
fun v_present v_identities v_identity ->
(match v_present with
| true ->
v_identities
| false ->
(v_identity :: v_identities))
and (* groups.bend:570 *)
f_union_types : (M.t_TypeId) list -> (M.t_TypeId) list -> (M.t_TypeId) list =
fun v_left v_right ->
(match v_left with
| [] ->
v_right
| (v_head :: v_tail) ->
(f_union_types (v_tail) ((f_put_type_if ((f_contains_type (v_right) (v_head))) (v_right) (v_head)))))
and (* groups.bend:577 *)
f_combine_usage : t_Usage -> t_Usage -> t_Usage =
fun v_left v_right ->
(let (Usage (v_lt)) = v_left in
(let (Usage (v_rt)) = v_right in
(Usage ((f_union_types (v_lt) (v_rt))))))
and (* groups.bend:582 *)
f_constructor_usage : (M.t_TypeId) option -> t_Usage =
fun v_found ->
(match v_found with
| None ->
(Usage ([]))
| (Some (v_identity)) ->
(Usage ([v_identity])))
and (* groups.bend:589 *)
f_constructor_index_entries : (M.t_Constructor) list -> M.t_TypeId -> (M.t_TypeId) Base.map -> (M.t_TypeId) Base.map =
fun v_constructors v_identity v_index ->
(match v_constructors with
| [] ->
v_index
| ((M.Constructor (v_name, v_payload, v_fields)) :: v_tail) ->
(f_constructor_index_entries (v_tail) (v_identity) ((Base.map_set (v_index) (v_name) (v_identity)))))
and (* groups.bend:596 *)
f_constructor_index : (M.t_DataType) list -> (M.t_TypeId) Base.map -> (M.t_TypeId) Base.map =
fun v_types v_index ->
(match v_types with
| [] ->
v_index
| ((M.DataType (v_identity, v_parameters, v_constructors)) :: v_tail) ->
(f_constructor_index (v_tail) ((f_constructor_index_entries (v_constructors) (v_identity) (v_index)))))
and (* groups.bend:603 *)
f_optional_type : (M.t_Ty) option -> M.t_Ty =
fun v_ty ->
(match v_ty with
| None ->
M.UnitTy
| (Some (v_value)) ->
v_value)
and (* groups.bend:610 *)
f_optional_pattern : (M.t_Pattern) option -> M.t_Pattern =
fun v_pattern ->
(match v_pattern with
| None ->
M.WildcardPattern
| (Some (v_value)) ->
v_value)
and (* groups.bend:617 *)
f_collected_usage : (t_Usage) list -> t_Usage -> t_Usage =
fun v_reversed v_result ->
(match v_reversed with
| [] ->
v_result
| (v_head :: v_tail) ->
(f_collected_usage (v_tail) ((f_combine_usage (v_head) (v_result)))))
and (* groups.bend:624 *)
f_row_identities : (M.t_EffectRow) list -> (M.t_TypeId) list =
fun v_rows ->
(match v_rows with
| [] ->
[]
| ((M.EffectRow (v_operations, v_tail)) :: v_rest) ->
(Base.list_append (v_operations) ((f_row_identities (v_rest)))))
and (* groups.bend:633 *)
f_effect_row_usage : M.t_EffectRow -> t_Usage =
fun v_row ->
(let (M.EffectRow (v_operations, v_tail)) = v_row in
(Usage (v_operations)))
and (* groups.bend:637 *)
f_usage : int -> t_UsageWork -> (M.t_TypeId) Base.map -> (M.t_Diagnostic, t_Usage) Base.result_ =
fun v_fuel v_work v_types ->
(match (v_fuel, v_work) with
| (0, _) ->
(Fail ((M.Diagnostic (s_8, s_9, s_10))))
| (__nat_25, (CollectedExpressionsUsage ((v_head :: v_tail), v_reversed))) when __nat_25 >= 1 ->
(let v_rest = (__nat_25 - 1) in
(match (f_usage (v_rest) ((ExpressionUsage (v_head))) (v_types)) with
| Fail __error -> Fail __error
| Done v_found ->
(f_usage (v_rest) ((CollectedExpressionsUsage (v_tail, (v_found :: v_reversed)))) (v_types))))
| (__nat_26, (CollectedPatternsUsage ((v_head :: v_tail), v_reversed))) when __nat_26 >= 1 ->
(let v_rest = (__nat_26 - 1) in
(match (f_usage (v_rest) ((PatternUsage (v_head))) (v_types)) with
| Fail __error -> Fail __error
| Done v_found ->
(f_usage (v_rest) ((CollectedPatternsUsage (v_tail, (v_found :: v_reversed)))) (v_types))))
| (__nat_27, (CollectedTypesUsage ((v_head :: v_tail), v_reversed))) when __nat_27 >= 1 ->
(let v_rest = (__nat_27 - 1) in
(match (f_usage (v_rest) ((TypeUsage (v_head))) (v_types)) with
| Fail __error -> Fail __error
| Done v_found ->
(f_usage (v_rest) ((CollectedTypesUsage (v_tail, (v_found :: v_reversed)))) (v_types))))
| (__nat_28, (CollectedPredicatesUsage ((v_head :: v_tail), v_reversed))) when __nat_28 >= 1 ->
(let v_rest = (__nat_28 - 1) in
(match (f_usage (v_rest) ((PredicateUsage (v_head))) (v_types)) with
| Fail __error -> Fail __error
| Done v_found ->
(f_usage (v_rest) ((CollectedPredicatesUsage (v_tail, (v_found :: v_reversed)))) (v_types))))
| (__nat_29, (CollectedArmsUsage (((M.MatchArm (v_patterns, v_body)) :: v_tail), v_reversed))) when __nat_29 >= 1 ->
(let v_rest = (__nat_29 - 1) in
(match (f_usage (v_rest) ((PatternsUsage (v_patterns))) (v_types)) with
| Fail __error -> Fail __error
| Done v_found_patterns ->
(match (f_usage (v_rest) ((ExpressionUsage (v_body))) (v_types)) with
| Fail __error -> Fail __error
| Done v_found_body ->
(f_usage (v_rest) ((CollectedArmsUsage (v_tail, (v_found_body :: (v_found_patterns :: v_reversed))))) (v_types)))))
| (__nat_30, (CollectedExpressionsUsage ([], v_reversed))) when __nat_30 >= 1 ->
(let v_rest = (__nat_30 - 1) in
(Done ((f_collected_usage (v_reversed) ((Usage ([])))))))
| (__nat_31, (CollectedPatternsUsage ([], v_reversed))) when __nat_31 >= 1 ->
(let v_rest = (__nat_31 - 1) in
(Done ((f_collected_usage (v_reversed) ((Usage ([])))))))
| (__nat_32, (CollectedTypesUsage ([], v_reversed))) when __nat_32 >= 1 ->
(let v_rest = (__nat_32 - 1) in
(Done ((f_collected_usage (v_reversed) ((Usage ([])))))))
| (__nat_33, (CollectedPredicatesUsage ([], v_reversed))) when __nat_33 >= 1 ->
(let v_rest = (__nat_33 - 1) in
(Done ((f_collected_usage (v_reversed) ((Usage ([])))))))
| (__nat_34, (CollectedArmsUsage ([], v_reversed))) when __nat_34 >= 1 ->
(let v_rest = (__nat_34 - 1) in
(Done ((f_collected_usage (v_reversed) ((Usage ([])))))))
| (__nat_35, (ExpressionUsage ((M.ConstructorRefExpr (v_constructor))))) when __nat_35 >= 1 ->
(let v_rest = (__nat_35 - 1) in
(Done ((f_constructor_usage ((Index.f_find (v_types) (v_constructor)))))))
| (__nat_36, (ExpressionUsage ((M.ConstructExpr (v_constructor, v_payload))))) when __nat_36 >= 1 ->
(let v_rest = (__nat_36 - 1) in
(match (f_usage (v_rest) ((ExpressionUsage ((D.f_payload_expression (v_payload))))) (v_types)) with
| Fail __error -> Fail __error
| Done v_nested ->
(Done ((f_combine_usage ((f_constructor_usage ((Index.f_find (v_types) (v_constructor))))) (v_nested))))))
| (__nat_37, (ExpressionUsage ((M.ProductExpr (v_elements))))) when __nat_37 >= 1 ->
(let v_rest = (__nat_37 - 1) in
(f_usage (v_rest) ((ExpressionsUsage (v_elements))) (v_types)))
| (__nat_38, (ExpressionUsage ((M.ProjectExpr (v_value, v_index))))) when __nat_38 >= 1 ->
(let v_rest = (__nat_38 - 1) in
(f_usage (v_rest) ((ExpressionUsage (v_value))) (v_types)))
| (__nat_39, (ExpressionUsage ((M.ArrayExpr (v_elements))))) when __nat_39 >= 1 ->
(let v_rest = (__nat_39 - 1) in
(f_usage (v_rest) ((ExpressionsUsage (v_elements))) (v_types)))
| (__nat_40, (ExpressionUsage ((M.ForExpr (v_index, v_start, v_end, v_state, v_initial, v_body))))) when __nat_40 >= 1 ->
(let v_rest = (__nat_40 - 1) in
(f_usage (v_rest) ((ExpressionsUsage ([v_start; v_end; v_initial; v_body]))) (v_types)))
| (__nat_41, (ExpressionUsage ((M.ForeverExpr (v_state, v_initial, v_body))))) when __nat_41 >= 1 ->
(let v_rest = (__nat_41 - 1) in
(f_usage (v_rest) ((ExpressionsUsage ([v_initial; v_body]))) (v_types)))
| (__nat_42, (ExpressionUsage ((M.ArrayGenerateExpr (v_count, v_generator))))) when __nat_42 >= 1 ->
(let v_rest = (__nat_42 - 1) in
(f_usage (v_rest) ((ExpressionsUsage ([v_count; v_generator]))) (v_types)))
| (__nat_43, (ExpressionUsage ((M.ArrayFillExpr (v_count, v_value))))) when __nat_43 >= 1 ->
(let v_rest = (__nat_43 - 1) in
(f_usage (v_rest) ((ExpressionsUsage ([v_count; v_value]))) (v_types)))
| (__nat_44, (ExpressionUsage ((M.ArrayGetExpr (v_array, v_index))))) when __nat_44 >= 1 ->
(let v_rest = (__nat_44 - 1) in
(f_usage (v_rest) ((ExpressionsUsage ([v_array; v_index]))) (v_types)))
| (__nat_45, (ExpressionUsage ((M.ArraySetExpr (v_array, v_index, v_value))))) when __nat_45 >= 1 ->
(let v_rest = (__nat_45 - 1) in
(f_usage (v_rest) ((ExpressionsUsage ([v_array; v_index; v_value]))) (v_types)))
| (__nat_46, (ExpressionUsage ((M.AssociatedExpr (v_identity, v_dispatch, v_member, v_templates, v_left, v_right))))) when __nat_46 >= 1 ->
(let v_rest = (__nat_46 - 1) in
(f_usage (v_rest) ((ExpressionsUsage ([v_left; v_right]))) (v_types)))
| (__nat_47, (ExpressionUsage ((M.GenericOperationExpr (v_identity, v_template, v_arguments))))) when __nat_47 >= 1 ->
(let v_rest = (__nat_47 - 1) in
(f_usage (v_rest) ((TypesUsage (v_arguments))) (v_types)))
| (__nat_48, (ExpressionUsage ((M.ArrayLengthExpr (v_array))))) when __nat_48 >= 1 ->
(let v_rest = (__nat_48 - 1) in
(f_usage (v_rest) ((ExpressionUsage (v_array))) (v_types)))
| (__nat_49, (ExpressionUsage ((M.LambdaExpr (v_identity, v_parameter, v_p, v_r, v_body))))) when __nat_49 >= 1 ->
(let v_rest = (__nat_49 - 1) in
(match (f_usage (v_rest) ((TypesUsage ([(f_optional_type (v_p)); (f_optional_type (v_r))]))) (v_types)) with
| Fail __error -> Fail __error
| Done v_annotations ->
(match (f_usage (v_rest) ((ExpressionUsage (v_body))) (v_types)) with
| Fail __error -> Fail __error
| Done v_nested ->
(Done ((f_combine_usage (v_annotations) (v_nested)))))))
| (__nat_50, (ExpressionUsage ((M.ApplyExpr (v_callee, v_argument))))) when __nat_50 >= 1 ->
(let v_rest = (__nat_50 - 1) in
(match (f_usage (v_rest) ((ExpressionUsage (v_callee))) (v_types)) with
| Fail __error -> Fail __error
| Done v_a ->
(match (f_usage (v_rest) ((ExpressionUsage (v_argument))) (v_types)) with
| Fail __error -> Fail __error
| Done v_b ->
(Done ((f_combine_usage (v_a) (v_b)))))))
| (__nat_51, (ExpressionUsage ((M.CallExpr (v_callee, v_argument))))) when __nat_51 >= 1 ->
(let v_rest = (__nat_51 - 1) in
(f_usage (v_rest) ((ExpressionUsage (v_argument))) (v_types)))
| (__nat_52, (ExpressionUsage ((M.StateProviderExpr (v_read, v_write, v_initial))))) when __nat_52 >= 1 ->
(let v_rest = (__nat_52 - 1) in
(f_usage (v_rest) ((ExpressionUsage (v_initial))) (v_types)))
| (__nat_53, (ExpressionUsage ((M.ProviderExpr (v_identity, v_implementation))))) when __nat_53 >= 1 ->
(let v_rest = (__nat_53 - 1) in
(f_usage (v_rest) ((ExpressionUsage (v_implementation))) (v_types)))
| (__nat_54, (ExpressionUsage ((M.HandleExpr (v_provider, v_body))))) when __nat_54 >= 1 ->
(let v_rest = (__nat_54 - 1) in
(f_usage (v_rest) ((ExpressionsUsage ([v_provider; v_body]))) (v_types)))
| (__nat_55, (ExpressionUsage ((M.EffectHasExpr (v_set, v_operation))))) when __nat_55 >= 1 ->
(let v_rest = (__nat_55 - 1) in
(f_usage (v_rest) ((ExpressionsUsage ([v_set; v_operation]))) (v_types)))
| (__nat_56, (ExpressionUsage ((M.EffectCountExpr (v_set))))) when __nat_56 >= 1 ->
(let v_rest = (__nat_56 - 1) in
(f_usage (v_rest) ((ExpressionUsage (v_set))) (v_types)))
| (__nat_57, (ExpressionUsage ((M.EffectSameExpr (v_left, v_right))))) when __nat_57 >= 1 ->
(let v_rest = (__nat_57 - 1) in
(f_usage (v_rest) ((ExpressionsUsage ([v_left; v_right]))) (v_types)))
| (__nat_58, (ExpressionUsage ((M.ScalarExpr (v_operator, v_left, v_right))))) when __nat_58 >= 1 ->
(let v_rest = (__nat_58 - 1) in
(match (f_usage (v_rest) ((ExpressionUsage (v_left))) (v_types)) with
| Fail __error -> Fail __error
| Done v_a ->
(match (f_usage (v_rest) ((ExpressionUsage (v_right))) (v_types)) with
| Fail __error -> Fail __error
| Done v_b ->
(Done ((f_combine_usage (v_a) (v_b)))))))
| (__nat_59, (ExpressionUsage ((M.UnaryExpr (v_operator, v_value))))) when __nat_59 >= 1 ->
(let v_rest = (__nat_59 - 1) in
(f_usage (v_rest) ((ExpressionUsage (v_value))) (v_types)))
| (__nat_60, (ExpressionUsage ((M.LetExpr (v_name, v_value, v_body))))) when __nat_60 >= 1 ->
(let v_rest = (__nat_60 - 1) in
(match (f_usage (v_rest) ((ExpressionUsage (v_value))) (v_types)) with
| Fail __error -> Fail __error
| Done v_a ->
(match (f_usage (v_rest) ((ExpressionUsage (v_body))) (v_types)) with
| Fail __error -> Fail __error
| Done v_b ->
(Done ((f_combine_usage (v_a) (v_b)))))))
| (__nat_61, (ExpressionUsage ((M.UseExpr (v_name, v_value, v_body))))) when __nat_61 >= 1 ->
(let v_rest = (__nat_61 - 1) in
(match (f_usage (v_rest) ((ExpressionUsage (v_value))) (v_types)) with
| Fail __error -> Fail __error
| Done v_a ->
(match (f_usage (v_rest) ((ExpressionUsage (v_body))) (v_types)) with
| Fail __error -> Fail __error
| Done v_b ->
(Done ((f_combine_usage (v_a) (v_b)))))))
| (__nat_62, (ExpressionUsage ((M.SequenceExpr (v_first, v_next))))) when __nat_62 >= 1 ->
(let v_rest = (__nat_62 - 1) in
(match (f_usage (v_rest) ((ExpressionUsage (v_first))) (v_types)) with
| Fail __error -> Fail __error
| Done v_a ->
(match (f_usage (v_rest) ((ExpressionUsage (v_next))) (v_types)) with
| Fail __error -> Fail __error
| Done v_b ->
(Done ((f_combine_usage (v_a) (v_b)))))))
| (__nat_63, (ExpressionUsage ((M.IfExpr (v_condition, v_consequent, v_alternative))))) when __nat_63 >= 1 ->
(let v_rest = (__nat_63 - 1) in
(match (f_usage (v_rest) ((ExpressionUsage (v_condition))) (v_types)) with
| Fail __error -> Fail __error
| Done v_a ->
(match (f_usage (v_rest) ((ExpressionUsage (v_consequent))) (v_types)) with
| Fail __error -> Fail __error
| Done v_b ->
(match (f_usage (v_rest) ((ExpressionUsage (v_alternative))) (v_types)) with
| Fail __error -> Fail __error
| Done v_c ->
(Done ((f_combine_usage (v_a) ((f_combine_usage (v_b) (v_c))))))))))
| (__nat_64, (ExpressionUsage ((M.MatchExpr (v_values, v_arms))))) when __nat_64 >= 1 ->
(let v_rest = (__nat_64 - 1) in
(match (f_usage (v_rest) ((ExpressionsUsage (v_values))) (v_types)) with
| Fail __error -> Fail __error
| Done v_a ->
(match (f_usage (v_rest) ((ArmsUsage (v_arms))) (v_types)) with
| Fail __error -> Fail __error
| Done v_b ->
(Done ((f_combine_usage (v_a) (v_b)))))))
| (__nat_65, (ExpressionUsage ((M.GuardExpr (v_pattern, v_value, v_alternative, v_body))))) when __nat_65 >= 1 ->
(let v_rest = (__nat_65 - 1) in
(match (f_usage (v_rest) ((PatternUsage (v_pattern))) (v_types)) with
| Fail __error -> Fail __error
| Done v_p ->
(match (f_usage (v_rest) ((ExpressionUsage (v_value))) (v_types)) with
| Fail __error -> Fail __error
| Done v_a ->
(match (f_usage (v_rest) ((ExpressionUsage (v_alternative))) (v_types)) with
| Fail __error -> Fail __error
| Done v_b ->
(match (f_usage (v_rest) ((ExpressionUsage (v_body))) (v_types)) with
| Fail __error -> Fail __error
| Done v_c ->
(Done ((f_combine_usage (v_p) ((f_combine_usage (v_a) ((f_combine_usage (v_b) (v_c)))))))))))))
| (__nat_66, (ExpressionUsage ((M.BlockExpr (v_label, v_body))))) when __nat_66 >= 1 ->
(let v_rest = (__nat_66 - 1) in
(f_usage (v_rest) ((ExpressionUsage (v_body))) (v_types)))
| (__nat_67, (ExpressionUsage ((M.ReturnExpr (v_label, v_value))))) when __nat_67 >= 1 ->
(let v_rest = (__nat_67 - 1) in
(f_usage (v_rest) ((ExpressionUsage (v_value))) (v_types)))
| (__nat_68, (ExpressionUsage ((M.RuntimeInitExpr (v_value))))) when __nat_68 >= 1 ->
(let v_rest = (__nat_68 - 1) in
(f_usage (v_rest) ((ExpressionUsage (v_value))) (v_types)))
| (__nat_69, (ExpressionUsage ((M.SourceExpr (v_offset, v_annotation, v_value))))) when __nat_69 >= 1 ->
(let v_rest = (__nat_69 - 1) in
(match (f_usage (v_rest) ((TypeUsage ((f_optional_type (v_annotation))))) (v_types)) with
| Fail __error -> Fail __error
| Done v_a ->
(match (f_usage (v_rest) ((ExpressionUsage (v_value))) (v_types)) with
| Fail __error -> Fail __error
| Done v_b ->
(Done ((f_combine_usage (v_a) (v_b)))))))
| (__nat_70, (ExpressionUsage ((M.QualifiedExpr (v_offset, v_annotation, v_predicates, v_value))))) when __nat_70 >= 1 ->
(let v_rest = (__nat_70 - 1) in
(match (f_usage (v_rest) ((TypeUsage (v_annotation))) (v_types)) with
| Fail __error -> Fail __error
| Done v_a ->
(match (f_usage (v_rest) ((PredicatesUsage (v_predicates))) (v_types)) with
| Fail __error -> Fail __error
| Done v_b ->
(match (f_usage (v_rest) ((ExpressionUsage (v_value))) (v_types)) with
| Fail __error -> Fail __error
| Done v_c ->
(Done ((f_combine_usage (v_a) ((f_combine_usage (v_b) (v_c))))))))))
| (__nat_71, (ExpressionUsage ((M.InstantiationExpr (v_site, v_value))))) when __nat_71 >= 1 ->
(let v_rest = (__nat_71 - 1) in
(f_usage (v_rest) ((ExpressionUsage (v_value))) (v_types)))
| (__nat_72, (ExpressionUsage ((M.TagExpr (v_offset, v_callee, v_argument))))) when __nat_72 >= 1 ->
(let v_rest = (__nat_72 - 1) in
(match (f_usage (v_rest) ((ExpressionUsage (v_callee))) (v_types)) with
| Fail __error -> Fail __error
| Done v_a ->
(match (f_usage (v_rest) ((ExpressionUsage (v_argument))) (v_types)) with
| Fail __error -> Fail __error
| Done v_b ->
(Done ((f_combine_usage (v_a) (v_b)))))))
| (__nat_73, (ArmsUsage (((M.MatchArm (v_patterns, v_body)) :: v_tail)))) when __nat_73 >= 1 ->
(let v_rest = (__nat_73 - 1) in
(match (f_usage (v_rest) ((PatternsUsage (v_patterns))) (v_types)) with
| Fail __error -> Fail __error
| Done v_found_patterns ->
(match (f_usage (v_rest) ((ExpressionUsage (v_body))) (v_types)) with
| Fail __error -> Fail __error
| Done v_found_body ->
(f_usage (v_rest) ((CollectedArmsUsage (v_tail, [v_found_body; v_found_patterns]))) (v_types)))))
| (__nat_74, (PatternsUsage ((v_head :: v_tail)))) when __nat_74 >= 1 ->
(let v_rest = (__nat_74 - 1) in
(match (f_usage (v_rest) ((PatternUsage (v_head))) (v_types)) with
| Fail __error -> Fail __error
| Done v_found ->
(f_usage (v_rest) ((CollectedPatternsUsage (v_tail, [v_found]))) (v_types))))
| (__nat_75, (PatternUsage ((M.ConstructorPattern (v_constructor, v_payload))))) when __nat_75 >= 1 ->
(let v_rest = (__nat_75 - 1) in
(match (f_usage (v_rest) ((PatternUsage ((f_optional_pattern (v_payload))))) (v_types)) with
| Fail __error -> Fail __error
| Done v_nested ->
(Done ((f_combine_usage ((f_constructor_usage ((Index.f_find (v_types) (v_constructor))))) (v_nested))))))
| (__nat_76, (PatternUsage ((M.ProductPattern (v_elements))))) when __nat_76 >= 1 ->
(let v_rest = (__nat_76 - 1) in
(f_usage (v_rest) ((PatternsUsage (v_elements))) (v_types)))
| (__nat_77, (TypeUsage ((M.AppliedTy (v_identity, v_arguments))))) when __nat_77 >= 1 ->
(let v_rest = (__nat_77 - 1) in
(match (f_usage (v_rest) ((TypesUsage (v_arguments))) (v_types)) with
| Fail __error -> Fail __error
| Done v_nested ->
(Done ((f_combine_usage ((Usage ([v_identity]))) (v_nested))))))
| (__nat_78, (TypeUsage ((M.ProductTy (v_elements))))) when __nat_78 >= 1 ->
(let v_rest = (__nat_78 - 1) in
(f_usage (v_rest) ((TypesUsage (v_elements))) (v_types)))
| (__nat_79, (TypeUsage ((M.StateProviderTy (v_read, v_write, v_state))))) when __nat_79 >= 1 ->
(let v_rest = (__nat_79 - 1) in
(f_usage (v_rest) ((TypeUsage (v_state))) (v_types)))
| (__nat_80, (TypeUsage ((M.ArrayTy (v_element))))) when __nat_80 >= 1 ->
(let v_rest = (__nat_80 - 1) in
(f_usage (v_rest) ((TypeUsage (v_element))) (v_types)))
| (__nat_81, (TypeUsage ((M.FunctionTy (v_parameter, v_result, v_effects))))) when __nat_81 >= 1 ->
(let v_rest = (__nat_81 - 1) in
(match (f_usage (v_rest) ((TypeUsage (v_parameter))) (v_types)) with
| Fail __error -> Fail __error
| Done v_a ->
(match (f_usage (v_rest) ((TypeUsage (v_result))) (v_types)) with
| Fail __error -> Fail __error
| Done v_b ->
(Done ((f_combine_usage ((f_effect_row_usage (v_effects))) ((f_combine_usage (v_a) (v_b)))))))))
| (__nat_82, (TypeUsage ((M.ProviderTy (v_identity, (M.EffectRow (v_operations, v_tail))))))) when __nat_82 >= 1 ->
(let v_rest = (__nat_82 - 1) in
(Done ((Usage ((v_identity :: v_operations))))))
| (__nat_83, (PredicateUsage (v_predicate))) when __nat_83 >= 1 ->
(let v_rest = (__nat_83 - 1) in
(match (f_usage (v_rest) ((TypesUsage ((C.f_predicate_types (v_predicate))))) (v_types)) with
| Fail __error -> Fail __error
| Done v_from_types ->
(Done ((f_combine_usage ((Usage ((Base.list_append ((C.f_predicate_templates ([v_predicate]))) ((f_row_identities ((C.f_predicate_rows (v_predicate))))))))) (v_from_types))))))
| (__nat_84, (PredicatesUsage ((v_head :: v_tail)))) when __nat_84 >= 1 ->
(let v_rest = (__nat_84 - 1) in
(match (f_usage (v_rest) ((PredicateUsage (v_head))) (v_types)) with
| Fail __error -> Fail __error
| Done v_found ->
(f_usage (v_rest) ((CollectedPredicatesUsage (v_tail, [v_found]))) (v_types))))
| (__nat_85, (TypesUsage ((v_head :: v_tail)))) when __nat_85 >= 1 ->
(let v_rest = (__nat_85 - 1) in
(match (f_usage (v_rest) ((TypeUsage (v_head))) (v_types)) with
| Fail __error -> Fail __error
| Done v_found ->
(f_usage (v_rest) ((CollectedTypesUsage (v_tail, [v_found]))) (v_types))))
| (__nat_86, (ExpressionsUsage ((v_head :: v_tail)))) when __nat_86 >= 1 ->
(let v_rest = (__nat_86 - 1) in
(match (f_usage (v_rest) ((ExpressionUsage (v_head))) (v_types)) with
| Fail __error -> Fail __error
| Done v_found ->
(f_usage (v_rest) ((CollectedExpressionsUsage (v_tail, [v_found]))) (v_types))))
| (__nat_87, _) when __nat_87 >= 1 ->
(let v_rest = (__nat_87 - 1) in
(Done ((Usage ([]))))))
and (* groups.bend:844 *)
f_declaration_usage : G.t_Declaration -> (M.t_TypeId) Base.map -> (M.t_Diagnostic, t_DeclarationUsage) Base.result_ =
fun v_declaration v_types ->
(match v_declaration with
| (G.FunctionDeclaration ((M.Function (v_name, v_exported, v_parameter, v_p, v_r, v_body)))) ->
(match (f_usage ((Base.nat_mul (256) (256))) ((TypesUsage ([(f_optional_type (v_p)); (f_optional_type (v_r))]))) (v_types)) with
| Fail __error -> Fail __error
| Done v_annotations ->
(match (f_usage ((Base.nat_mul (256) (256))) ((ExpressionUsage (v_body))) (v_types)) with
| Fail __error -> Fail __error
| Done v_nested ->
(Done ((DeclarationUsage (v_name, (f_combine_usage (v_annotations) (v_nested))))))))
| (G.ConstantDeclaration ((M.Constant (v_name, v_exported, v_annotation, v_value)))) ->
(match (f_usage ((Base.nat_mul (256) (256))) ((TypeUsage ((f_optional_type (v_annotation))))) (v_types)) with
| Fail __error -> Fail __error
| Done v_annotations ->
(match (f_usage ((Base.nat_mul (256) (256))) ((ExpressionUsage (v_value))) (v_types)) with
| Fail __error -> Fail __error
| Done v_nested ->
(Done ((DeclarationUsage (v_name, (f_combine_usage (v_annotations) (v_nested)))))))))
and (* groups.bend:857 *)
f_declaration_usages : (G.t_Declaration) list -> (M.t_TypeId) Base.map -> (M.t_Diagnostic, (t_DeclarationUsage) list) Base.result_ =
fun v_declarations v_types ->
(match v_declarations with
| [] ->
(Done ([]))
| (v_head :: v_tail) ->
(match (f_declaration_usage (v_head) (v_types)) with
| Fail __error -> Fail __error
| Done v_found ->
(match (f_declaration_usages (v_tail) (v_types)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done ((v_found :: v_rest))))))
and (* groups.bend:870 *)
f_usage_types : t_Usage -> (M.t_TypeId) list =
fun v_found ->
(let (Usage (v_nominals)) = v_found in
v_nominals)
and (* groups.bend:874 *)
f_operation_types : (M.t_Operation) list -> (M.t_TypeId) Base.map -> (M.t_Diagnostic, (M.t_TypeId) list) Base.result_ =
fun v_operations v_types ->
(match v_operations with
| [] ->
(Done ([]))
| ((M.Operation (v_identity, v_parameter, v_result)) :: v_tail) ->
(match (f_usage ((Base.nat_mul (256) (256))) ((TypesUsage ([v_parameter; v_result]))) (v_types)) with
| Fail __error -> Fail __error
| Done v_found ->
(match (f_operation_types (v_tail) (v_types)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done ((f_union_types ((f_usage_types (v_found))) (v_rest))))))
| ((M.OperationTemplate (v_identity, v_parameters, v_parameter, v_result)) :: v_tail) ->
(match (f_usage ((Base.nat_mul (256) (256))) ((TypesUsage ([v_parameter; v_result]))) (v_types)) with
| Fail __error -> Fail __error
| Done v_found ->
(match (f_operation_types (v_tail) (v_types)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done ((f_union_types ((f_usage_types (v_found))) (v_rest))))))
| (v_head :: v_tail) ->
(Fail ((M.Diagnostic (s_11, s_12, s_13)))))
and (* groups.bend:892 *)
f_shared_operation_types : (t_DeclarationUsage) list -> (M.t_TypeId) list -> (t_DeclarationUsage) list =
fun v_usages v_required ->
(match v_usages with
| [] ->
[]
| ((DeclarationUsage (v_name, (Usage (v_nominals)))) :: v_tail) ->
((DeclarationUsage (v_name, (Usage ((f_union_types (v_required) (v_nominals)))))) :: (f_shared_operation_types (v_tail) (v_required))))
and (* groups.bend:899 *)
f_constructor_types : (M.t_Constructor) list -> (M.t_TypeId) Base.map -> (M.t_Diagnostic, (M.t_TypeId) list) Base.result_ =
fun v_constructors v_types ->
(match v_constructors with
| [] ->
(Done ([]))
| ((M.Constructor (v_name, v_payload, v_fields)) :: v_tail) ->
(match (f_usage ((Base.nat_mul (256) (256))) ((TypeUsage ((f_optional_type (v_payload))))) (v_types)) with
| Fail __error -> Fail __error
| Done v_found ->
(match (f_constructor_types (v_tail) (v_types)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done ((f_union_types ((f_usage_types (v_found))) (v_rest)))))))
and (* groups.bend:909 *)
f_type_dependencies : (M.t_DataType) list -> (M.t_TypeId) Base.map -> (M.t_Diagnostic, (t_TypeDependencies) list) Base.result_ =
fun v_pending v_types ->
(match v_pending with
| [] ->
(Done ([]))
| ((M.DataType (v_identity, v_parameters, v_constructors)) :: v_tail) ->
(match (f_constructor_types (v_constructors) (v_types)) with
| Fail __error -> Fail __error
| Done v_refs ->
(match (f_type_dependencies (v_tail) (v_types)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done (((TypeDependencies (v_identity, v_refs)) :: v_rest))))))
and (* groups.bend:921 *)
f_external_references : (Base.text) list -> Base.set -> Base.set -> Base.set -> Base.set =
fun v_references v_known v_members v_found ->
(match v_references with
| [] ->
v_found
| (v_head :: v_tail) ->
(f_external_references (v_tail) (v_known) (v_members) ((D.f_mark ((Base.bool_and ((D.f_member (v_known) (v_head))) ((Base.bool_not ((D.f_member (v_members) (v_head))))))) (v_found) (v_head)))))
and (* groups.bend:928 *)
f_job_dependencies : (Base.text) list -> ((Base.text) list) Base.map -> Base.set -> Base.set -> Base.set -> (Base.text) list =
fun v_members v_edges v_known v_owned v_found ->
(match v_members with
| [] ->
(Base.set_to_list (v_found))
| (v_head :: v_tail) ->
(f_job_dependencies (v_tail) (v_edges) (v_known) (v_owned) ((f_external_references ((D.f_neighbors (v_edges) (v_head))) (v_known) (v_owned) (v_found)))))
and (* groups.bend:937 *)
f_type_key : M.t_TypeId -> Base.text =
fun v_identity ->
(let (M.TypeId (v_module_name, v_declaration)) = v_identity in
(Base.string_append (Base.nat_show ((Base.string_length (v_module_name)))) (Base.string_append s_14 (Base.string_append v_module_name v_declaration))))
and (* groups.bend:944 *)
f_type_set : (M.t_TypeId) list -> t_TypeSet -> t_TypeSet =
fun v_identities v_found ->
(match v_identities with
| [] ->
v_found
| (v_head :: v_tail) ->
(f_type_set (v_tail) ((Base.map_set (v_found) ((f_type_key (v_head))) (v_head)))))
and (* groups.bend:951 *)
f_type_set_excluding_found : (M.t_TypeId) option -> M.t_TypeId -> Base.text -> t_TypeSet -> t_TypeSet =
fun v_present v_head v_key v_found ->
(match v_present with
| (Some (v_value)) ->
v_found
| None ->
(Base.map_set (v_found) (v_key) (v_head)))
and (* groups.bend:958 *)
f_type_set_excluding : (M.t_TypeId) list -> t_TypeSet -> t_TypeSet -> t_TypeSet =
fun v_identities v_excluded v_found ->
(match v_identities with
| [] ->
v_found
| (v_head :: v_tail) ->
(let v_key = (f_type_key (v_head)) in
(f_type_set_excluding (v_tail) (v_excluded) ((f_type_set_excluding_found ((Index.f_find (v_excluded) (v_key))) (v_head) (v_key) (v_found))))))
and (* groups.bend:966 *)
f_type_keys : (M.t_TypeId) list -> (Base.text) list =
fun v_identities ->
(match v_identities with
| [] ->
[]
| (v_head :: v_tail) ->
((f_type_key (v_head)) :: (f_type_keys (v_tail))))
and (* groups.bend:973 *)
f_type_identity_le : M.t_TypeId -> M.t_TypeId -> bool =
fun v_left v_right ->
(R.f_operation_le (v_left) (v_right))
and (* groups.bend:976 *)
f_type_seed : (t_TypeSet) Base.map -> Base.text -> t_TypeSet =
fun v_seeds v_name ->
(Index.f_get (v_seeds) (v_name) ((Base.map_new ())))
and (* groups.bend:979 *)
f_combine_seeds : (Base.text) list -> (t_TypeSet) Base.map -> t_TypeSet -> t_TypeSet =
fun v_names v_seeds v_found ->
(match v_names with
| [] ->
v_found
| (v_head :: v_tail) ->
(f_combine_seeds (v_tail) (v_seeds) ((Base.map_union (v_found) ((f_type_seed (v_seeds) (v_head)))))))
and (* groups.bend:986 *)
f_publish_summary : (Base.text) list -> t_TypeSet -> (t_TypeSet) Base.map -> (t_TypeSet) Base.map =
fun v_names v_summary v_summaries ->
(match v_names with
| [] ->
v_summaries
| (v_head :: v_tail) ->
(f_publish_summary (v_tail) (v_summary) ((Base.map_set (v_summaries) (v_head) (v_summary)))))
and (* groups.bend:993 *)
f_usage_seeds : (t_DeclarationUsage) list -> t_TypeSet -> (t_TypeSet) Base.map -> (t_TypeSet) Base.map =
fun v_usages v_shared v_seeds ->
(match v_usages with
| [] ->
v_seeds
| ((DeclarationUsage (v_name, (Usage (v_nominals)))) :: v_tail) ->
(f_usage_seeds (v_tail) (v_shared) ((Base.map_set (v_seeds) (v_name) ((f_type_set_excluding (v_nominals) (v_shared) ((Base.map_new ()))))))))
and (* groups.bend:1000 *)
f_nominal_nodes : (t_TypeDependencies) list -> (D.t_Node) list =
fun v_types ->
(match v_types with
| [] ->
[]
| ((TypeDependencies (v_identity, [])) :: v_tail) ->
(f_nominal_nodes (v_tail))
| ((TypeDependencies (v_identity, v_references)) :: v_tail) ->
((D.Node ((f_type_key (v_identity)), (f_type_keys (v_references)), [])) :: (f_nominal_nodes (v_tail))))
and (* groups.bend:1010 *)
f_nominal_seeds : (t_TypeDependencies) list -> (t_TypeSet) Base.map -> (t_TypeSet) Base.map =
fun v_types v_seeds ->
(match v_types with
| [] ->
v_seeds
| ((TypeDependencies (v_identity, [])) :: v_tail) ->
(f_nominal_seeds (v_tail) (v_seeds))
| ((TypeDependencies (v_identity, v_references)) :: v_tail) ->
(f_nominal_seeds (v_tail) ((Base.map_set (v_seeds) ((f_type_key (v_identity))) ((f_type_set ((v_identity :: v_references)) ((Base.map_new ()))))))))
and (* groups.bend:1020 *)
f_nominal_summaries : ((Base.text) list) list -> ((Base.text) list) Base.map -> (t_TypeSet) Base.map -> Base.set -> (t_TypeSet) Base.map -> (t_TypeSet) Base.map =
fun v_components v_edges v_seeds v_known v_summaries ->
(match v_components with
| [] ->
v_summaries
| (v_members :: v_tail) ->
(let v_dependencies = (f_job_dependencies (v_members) (v_edges) (v_known) ((Base.set_from_list (v_members))) ((Base.set_new ()))) in
(let v_own = (f_combine_seeds (v_members) (v_seeds) ((Base.map_new ()))) in
(let v_summary = (f_combine_seeds (v_dependencies) (v_summaries) (v_own)) in
(f_nominal_summaries (v_tail) (v_edges) (v_seeds) (v_known) ((f_publish_summary (v_members) (v_summary) (v_summaries))))))))
and (* groups.bend:1030 *)
f_close_nominals : (M.t_TypeId) list -> (t_TypeSet) Base.map -> t_TypeSet -> t_TypeSet =
fun v_identities v_summaries v_found ->
(match v_identities with
| [] ->
v_found
| (v_head :: v_tail) ->
(f_close_nominals (v_tail) (v_summaries) ((Base.map_union (v_found) ((f_type_seed (v_summaries) ((f_type_key (v_head)))))))))
and (* groups.bend:1041 *)
f_merge_required : (M.t_TypeId) list -> (M.t_TypeId) list -> (M.t_TypeId) list =
fun v_common v_specific ->
(match (v_common, v_specific) with
| ([], v_other) ->
v_other
| (v_other, []) ->
v_other
| ((v_left :: v_left_rest), (v_right :: v_right_rest)) ->
(let v_xs = (v_left :: v_left_rest) in
(let v_ys = (v_right :: v_right_rest) in
(Base.list_merge_go (f_type_identity_le) ((Base.nat_add ((Base.list_length (v_xs))) ((Base.list_length (v_ys))))) (([], v_xs, v_ys))))))
and (* groups.bend:1052 *)
f_required_for_summary : t_TypeSet -> t_TypeSet -> (M.t_TypeId) list -> (M.t_TypeId) list =
fun v_summary v_shared v_common ->
(match (v_summary, v_shared) with
| (MTip, _) ->
v_common
| (v_other, MTip) ->
(Base.list_sort (f_type_identity_le) ((Base.map_values (v_other))))
| (v_other, v_available) ->
(let v_specific = (f_type_set_excluding ((Base.map_values (v_other))) (v_available) ((Base.map_new ()))) in
(f_merge_required (v_common) ((Base.list_sort (f_type_identity_le) ((Base.map_values (v_specific))))))))
and (* groups.bend:1062 *)
f_make_jobs : ((Base.text) list) list -> ((Base.text) list) Base.map -> Base.set -> (t_TypeSet) Base.map -> (t_TypeSet) Base.map -> t_TypeSet -> (M.t_TypeId) list -> (t_TypeSet) Base.map -> (t_Job) list =
fun v_components v_edges v_known v_seeds v_nominals v_shared v_common v_summaries ->
(match v_components with
| [] ->
[]
| (v_members :: v_tail) ->
(let v_dependencies = (f_job_dependencies (v_members) (v_edges) (v_known) ((Base.set_from_list (v_members))) ((Base.set_new ()))) in
(let v_own = (f_combine_seeds (v_members) (v_seeds) ((Base.map_new ()))) in
(let v_closed = (f_close_nominals ((Base.map_values (v_own))) (v_nominals) (v_own)) in
(let v_summary = (f_combine_seeds (v_dependencies) (v_summaries) (v_closed)) in
(let v_required = (f_required_for_summary (v_summary) (v_shared) (v_common)) in
((Job (v_members, v_dependencies, v_required)) :: (f_make_jobs (v_tail) (v_edges) (v_known) (v_seeds) (v_nominals) (v_shared) (v_common) ((f_publish_summary (v_members) (v_summary) (v_summaries)))))))))))
and (* groups.bend:1077 *)
f_planning_nodes : (D.t_Node) list -> (D.t_Node) list =
fun v_nodes ->
(match v_nodes with
| [] ->
[]
| ((D.Node (v_name, v_references, v_lambdas)) :: v_tail) ->
((D.Node (v_name, (Base.set_to_list ((Base.set_from_list (v_references)))), [])) :: (f_planning_nodes (v_tail))))
and (* groups.bend:1085 *)
f_planning_usages : (t_DeclarationUsage) list -> (t_DeclarationUsage) list =
fun v_usages ->
(match v_usages with
| [] ->
[]
| ((DeclarationUsage (v_name, (Usage (v_nominals)))) :: v_tail) ->
((DeclarationUsage (v_name, (Usage ((Base.list_sort (f_type_identity_le) (v_nominals)))))) :: (f_planning_usages (v_tail))))
and (* groups.bend:1094 *)
f_planning_types : (t_TypeDependencies) list -> (t_TypeDependencies) list =
fun v_types ->
(match v_types with
| [] ->
[]
| ((TypeDependencies (v_identity, v_references)) :: v_tail) ->
((TypeDependencies (v_identity, (Base.list_sort (f_type_identity_le) (v_references)))) :: (f_planning_types (v_tail))))
and (* groups.bend:1104 *)
f_prepare_plan_usages : M.t_Module -> (M.t_Diagnostic, (D.t_Node) list) Base.result_ -> (M.t_Diagnostic, (t_DeclarationUsage) list) Base.result_ -> (M.t_Diagnostic, t_Planning) Base.result_ =
fun v_module v_graph v_scanned ->
(let (M.Module (v_constants, v_functions, v_types, v_operations)) = v_module in
(match v_graph with
| Fail __error -> Fail __error
| Done v_nodes ->
(let v_constructors = (f_constructor_index (v_types) ((Base.map_new ()))) in
(match v_scanned with
| Fail __error -> Fail __error
| Done v_usages ->
(match (f_operation_types (v_operations) (v_constructors)) with
| Fail __error -> Fail __error
| Done v_required ->
(match (f_type_dependencies (v_types) (v_constructors)) with
| Fail __error -> Fail __error
| Done v_nominal_graph ->
(Done ((Planning ((f_planning_nodes (v_nodes)), (f_planning_usages (v_usages)), (f_planning_types (v_nominal_graph)), (Base.list_sort (f_type_identity_le) (v_required))))))))))))
and (* groups.bend:1114 *)
f_prepare_plan_graph : M.t_Module -> (M.t_Diagnostic, (D.t_Node) list) Base.result_ -> (M.t_Diagnostic, t_Planning) Base.result_ =
fun v_module v_graph ->
(let (M.Module (v_constants, v_functions, v_types, v_operations)) = v_module in
(let v_declarations = (Base.list_append ((G.f_function_declarations (v_functions))) ((G.f_constant_declarations (v_constants)))) in
(match v_graph with
| Fail __error -> Fail __error
| Done v_nodes ->
(let v_constructors = (f_constructor_index (v_types) ((Base.map_new ()))) in
(match (f_declaration_usages (v_declarations) (v_constructors)) with
| Fail __error -> Fail __error
| Done v_usages ->
(match (f_operation_types (v_operations) (v_constructors)) with
| Fail __error -> Fail __error
| Done v_required ->
(match (f_type_dependencies (v_types) (v_constructors)) with
| Fail __error -> Fail __error
| Done v_nominal_graph ->
(Done ((Planning ((f_planning_nodes (v_nodes)), (f_planning_usages (v_usages)), (f_planning_types (v_nominal_graph)), (Base.list_sort (f_type_identity_le) (v_required)))))))))))))
and (* groups.bend:1125 *)
f_prepare_plan : M.t_Module -> (M.t_Diagnostic, t_Planning) Base.result_ =
fun v_module ->
(f_prepare_plan_graph (v_module) ((Check.f_module_graph (v_module))))
and (* groups.bend:1128 *)
f_substantial_graph : (D.t_Node) list -> int -> bool =
fun v_nodes v_required ->
(match (v_nodes, v_required) with
| (_, 0) ->
true
| ([], _) ->
false
| ((v_head :: v_tail), __nat_88) when __nat_88 >= 1 ->
(let v_rest = (__nat_88 - 1) in
(f_substantial_graph (v_tail) (v_rest))))
and (* groups.bend:1137 *)
f_component_pair : (D.t_Node) list -> (D.t_Node) list -> bool -> ((M.t_Diagnostic, ((Base.text) list) list) Base.result_ * (M.t_Diagnostic, ((Base.text) list) list) Base.result_) =
fun v_nodes v_nominals v_parallel ->
(match v_parallel with
| false ->
((D.f_components (v_nodes)), (D.f_components (v_nominals)))
| true ->
(let (v_values, v_types) = Native_parallel.two (fun () -> (D.f_components (v_nodes))) (fun () -> (D.f_components (v_nominals))) in
(v_values, v_types)))
and (* groups.bend:1145 *)
f_finish_components : ((M.t_Diagnostic, ((Base.text) list) list) Base.result_ * (M.t_Diagnostic, ((Base.text) list) list) Base.result_) -> (D.t_Node) list -> (t_DeclarationUsage) list -> (t_TypeDependencies) list -> (D.t_Node) list -> (M.t_TypeId) list -> (M.t_Diagnostic, (t_Job) list) Base.result_ =
fun v_pair v_nodes v_usages v_nominal_graph v_nominal_graph_nodes v_shared_operation_types ->
(let (v_value_components, v_type_components) = v_pair in
(match v_value_components with
| Fail __error -> Fail __error
| Done v_components ->
(match v_type_components with
| Fail __error -> Fail __error
| Done v_nominal_components ->
(let v_closures = (f_nominal_summaries (v_nominal_components) ((D.f_adjacency (v_nominal_graph_nodes) ((Base.map_new ())))) ((f_nominal_seeds (v_nominal_graph) ((Base.map_new ())))) ((Base.set_from_list ((D.f_node_names (v_nominal_graph_nodes))))) ((Base.map_new ()))) in
(let v_shared = (f_close_nominals (v_shared_operation_types) (v_closures) ((f_type_set (v_shared_operation_types) ((Base.map_new ()))))) in
(let v_common = (Base.list_sort (f_type_identity_le) ((Base.map_values (v_shared)))) in
(Done ((f_make_jobs (v_components) ((D.f_adjacency (v_nodes) ((Base.map_new ())))) ((Base.set_from_list ((D.f_node_names (v_nodes))))) ((f_usage_seeds (v_usages) (v_shared) ((Base.map_new ())))) (v_closures) (v_shared) (v_common) ((Base.map_new ())))))))))))
and (* groups.bend:1155 *)
f_finish_plan : t_Planning -> (M.t_Diagnostic, (t_Job) list) Base.result_ =
fun v_planning ->
(let (Planning (v_nodes, v_usages, v_nominal_graph, v_shared_operation_types)) = v_planning in
(let v_nominal_graph_nodes = (f_nominal_nodes (v_nominal_graph)) in
(let v_pair = (f_component_pair (v_nodes) (v_nominal_graph_nodes) ((Base.bool_and ((f_substantial_graph (v_nodes) (32))) ((f_substantial_graph (v_nominal_graph_nodes) (32)))))) in
(f_finish_components (v_pair) (v_nodes) (v_usages) (v_nominal_graph) (v_nominal_graph_nodes) (v_shared_operation_types)))))
and (* groups.bend:1161 *)
f_plan : M.t_Module -> (M.t_Diagnostic, (t_Job) list) Base.result_ =
fun v_module ->
(match (f_prepare_plan (v_module)) with
| Fail __error -> Fail __error
| Done v_prepared ->
(f_finish_plan (v_prepared)))
and (* groups.bend:1166 *)
f_select_functions : (M.t_Function) list -> (Base.text) list -> (M.t_Function) list =
fun v_functions v_members ->
(match v_functions with
| [] ->
[]
| ((M.Function (v_name, v_exported, v_parameter, v_p, v_r, v_body)) :: v_tail) ->
(let v_rest = (f_select_functions (v_tail) (v_members)) in
(Base.bool_pick ((D.f_contains (v_members) (v_name))) (((M.Function (v_name, v_exported, v_parameter, v_p, v_r, v_body)) :: v_rest)) (v_rest))))
and (* groups.bend:1174 *)
f_select_constants : (M.t_Constant) list -> (Base.text) list -> (M.t_Constant) list =
fun v_constants v_members ->
(match v_constants with
| [] ->
[]
| ((M.Constant (v_name, v_exported, v_annotation, v_value)) :: v_tail) ->
(let v_rest = (f_select_constants (v_tail) (v_members)) in
(Base.bool_pick ((D.f_contains (v_members) (v_name))) (((M.Constant (v_name, v_exported, v_annotation, v_value)) :: v_rest)) (v_rest))))
and (* groups.bend:1182 *)
f_select_types : (M.t_DataType) list -> (M.t_TypeId) list -> (M.t_DataType) list =
fun v_types v_required ->
(match v_types with
| [] ->
[]
| ((M.DataType (v_identity, v_parameters, v_constructors)) :: v_tail) ->
(let v_rest = (f_select_types (v_tail) (v_required)) in
(Base.bool_pick ((f_contains_type (v_required) (v_identity))) (((M.DataType (v_identity, v_parameters, v_constructors)) :: v_rest)) (v_rest))))
and (* groups.bend:1192 *)
f_job_module : M.t_Module -> t_Job -> (M.t_Diagnostic, M.t_Module) Base.result_ =
fun v_module v_job ->
(let (M.Module (v_constants, v_functions, v_types, v_operations)) = v_module in
(let (Job (v_members, v_dependencies, v_required)) = v_job in
(Done ((M.Module ((f_select_constants (v_constants) (v_members)), (f_select_functions (v_functions) (v_members)), (f_select_types (v_types) (v_required)), v_operations))))))
