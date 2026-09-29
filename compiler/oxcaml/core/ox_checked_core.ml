(* Native semantic port of compiler/checked_core.bend.

   Source SHA-256: 446bef1547bc1068ee14a7e3455d95a0b4c65fbad321bdf0397fff7d8c4bd59d

   Ownership/type arguments are erased; value types are checked by OCaml.

   No Bend interpreter or generated C/JavaScript is linked. *)

open Base

module M = Ox_model

module Groups = Ox_groups

module Index = Ox_index

module Compare = Ox_core_compare

module Globals = Ox_globals

module Closures = Ox_closures

module C = Ox_constraints

type t_Certificate =
  | Certificate of M.t_Module * Groups.t_CheckedGroup * (Groups.t_Interface) list
and t_Prepared =
  | Prepared of M.t_Module * (t_Certificate) list

let rec (* checked_core.bend:19 *)
f_prepared_module : t_Prepared -> M.t_Module =
fun v_prepared ->
(let (Prepared (v_module, v_certificates)) = v_prepared in
v_module)
and (* checked_core.bend:23 *)
f_prepared_certificates : t_Prepared -> (t_Certificate) list =
fun v_prepared ->
(let (Prepared (v_module, v_certificates)) = v_prepared in
v_certificates)
and (* checked_core.bend:27 *)
f_deferred : int -> (M.t_Expr) list -> bool =
fun v_fuel v_pending ->
(match (v_fuel, v_pending) with
| (_, []) ->
false
| (0, _) ->
true
| (__nat_1, ((M.AssociatedExpr (v_identity, v_dispatch, v_member, v_templates, v_left, v_right)) :: v_tail)) when __nat_1 >= 1 ->
(let v_rest = (__nat_1 - 1) in
true)
| (__nat_2, ((M.GenericOperationExpr (v_identity, v_template, v_arguments)) :: v_tail)) when __nat_2 >= 1 ->
(let v_rest = (__nat_2 - 1) in
true)
| (__nat_3, ((M.SpecializeOperationExpr (v_template, v_arguments, v_body)) :: v_tail)) when __nat_3 >= 1 ->
(let v_rest = (__nat_3 - 1) in
true)
| (__nat_4, ((M.QualifiedExpr (v_offset, v_annotation, v_predicates, v_body)) :: v_tail)) when __nat_4 >= 1 ->
(let v_rest = (__nat_4 - 1) in
true)
| (__nat_5, (v_head :: v_tail)) when __nat_5 >= 1 ->
(let v_rest = (__nat_5 - 1) in
(f_deferred (v_rest) ((Base.list_reverse_go ((Base.list_reverse ((Closures.f_children (v_head))))) (v_tail))))))
and (* checked_core.bend:44 *)
f_deferred_functions : (M.t_Function) list -> bool =
fun v_functions ->
(match v_functions with
| [] ->
false
| ((M.Function (v_name, v_exported, v_parameter, v_p, v_r, v_body)) :: v_tail) ->
(Base.bool_or ((f_deferred (65536) ([v_body]))) ((f_deferred_functions (v_tail)))))
and (* checked_core.bend:51 *)
f_deferred_constants : (M.t_Constant) list -> bool =
fun v_constants ->
(match v_constants with
| [] ->
false
| ((M.Constant (v_name, v_exported, v_annotation, v_value)) :: v_tail) ->
(Base.bool_or ((f_deferred (65536) ([v_value]))) ((f_deferred_constants (v_tail)))))
and (* checked_core.bend:58 *)
f_source_ready : M.t_Module -> bool =
fun v_module ->
(let (M.Module (v_constants, v_functions, v_types, v_operations)) = v_module in
(Base.bool_not ((Base.bool_or ((f_deferred_functions (v_functions))) ((f_deferred_constants (v_constants)))))))
and (* checked_core.bend:62 *)
f_pending_uses : (C.t_UsePlan) list -> bool =
fun v_plans ->
(match v_plans with
| [] ->
false
| ((C.UsePlan (v_site, v_subject, v_ty, v_predicates)) :: v_tail) ->
(Base.bool_or ((Base.bool_not ((Base.list_is_empty (v_predicates))))) ((f_pending_uses (v_tail)))))
and (* checked_core.bend:69 *)
f_pending_interfaces : (Groups.t_Interface) list -> bool =
fun v_interfaces ->
(match v_interfaces with
| [] ->
false
| ((Groups.Interface (v_name, v_kind, v_template, v_parameters, v_effects, v_predicates)) :: v_tail) ->
(Base.bool_or ((Base.bool_not ((Base.list_is_empty (v_predicates))))) ((f_pending_interfaces (v_tail)))))
and (* checked_core.bend:76 *)
f_ready_group : Groups.t_CheckedGroup -> bool =
fun v_group ->
(let (Groups.CheckedGroup (v_checked, v_interfaces, v_uses)) = v_group in
(Base.bool_not ((Base.bool_or ((f_pending_uses (v_uses))) ((f_pending_interfaces (v_interfaces)))))))
and (* checked_core.bend:81 *)
f_ready_certificates : (t_Certificate) list -> (t_Certificate) list =
fun v_certificates ->
(match v_certificates with
| [] ->
[]
| (v_certificate :: v_tail) ->
(let (Certificate (v_module, v_checked, v_imports)) = v_certificate in
(let v_rest = (f_ready_certificates (v_tail)) in
(Base.bool_pick ((Base.bool_and ((f_source_ready (v_module))) ((f_ready_group (v_checked))))) ((v_certificate :: v_rest)) (v_rest)))))
and (* checked_core.bend:90 *)
f_type_identity : M.t_DataType -> M.t_TypeId =
fun v_ty ->
(let (M.DataType (v_identity, v_parameters, v_constructors)) = v_ty in
v_identity)
and (* checked_core.bend:94 *)
f_find_type : M.t_TypeId -> (M.t_DataType) list -> (M.t_DataType) option =
fun v_identity v_types ->
(match v_types with
| [] ->
None
| ((M.DataType (v_found, v_parameters, v_constructors)) :: v_tail) ->
(Base.bool_pick ((M.f_type_id_equal (v_identity) (v_found))) ((Some ((M.DataType (v_found, v_parameters, v_constructors))))) ((f_find_type (v_identity) (v_tail)))))
and (* checked_core.bend:101 *)
f_matches_type : M.t_DataType -> (M.t_DataType) option -> bool =
fun v_ty v_found ->
(match v_found with
| None ->
false
| (Some (v_candidate)) ->
(Compare.f_same_type (v_ty) (v_candidate)))
and (* checked_core.bend:108 *)
f_same_types : (M.t_DataType) list -> (M.t_DataType) list -> bool =
fun v_wanted v_available ->
(match v_wanted with
| [] ->
true
| (v_ty :: v_tail) ->
(Base.bool_and ((f_matches_type (v_ty) ((f_find_type ((f_type_identity (v_ty))) (v_available))))) ((f_same_types (v_tail) (v_available)))))
and (* checked_core.bend:115 *)
f_operation_identity : M.t_Operation -> M.t_TypeId =
fun v_operation ->
(match v_operation with
| (M.Operation (v_identity, v_parameter, v_result)) ->
v_identity
| (M.OperationTemplate (v_identity, v_parameters, v_parameter, v_result)) ->
v_identity
| (M.OperationInstance (v_template, v_arguments)) ->
v_template)
and (* checked_core.bend:128 *)
f_first_type_index : (M.t_DataType) list -> (M.t_DataType) Base.map -> (M.t_DataType) Base.map =
fun v_types v_indexed ->
(match v_types with
| [] ->
v_indexed
| (v_head :: v_tail) ->
(Base.map_set ((f_first_type_index (v_tail) (v_indexed))) ((Groups.f_type_key ((f_type_identity (v_head))))) (v_head)))
and (* checked_core.bend:135 *)
f_first_operation_index : (M.t_Operation) list -> (M.t_Operation) Base.map -> (M.t_Operation) Base.map =
fun v_operations v_indexed ->
(match v_operations with
| [] ->
v_indexed
| (v_head :: v_tail) ->
(Base.map_set ((f_first_operation_index (v_tail) (v_indexed))) ((Groups.f_type_key ((f_operation_identity (v_head))))) (v_head)))
and (* checked_core.bend:142 *)
f_find_operation : M.t_TypeId -> (M.t_Operation) list -> (M.t_Operation) option =
fun v_identity v_operations ->
(match v_operations with
| [] ->
None
| (v_head :: v_tail) ->
(Base.bool_pick ((M.f_type_id_equal (v_identity) ((f_operation_identity (v_head))))) ((Some (v_head))) ((f_find_operation (v_identity) (v_tail)))))
and (* checked_core.bend:149 *)
f_matches_operation : M.t_Operation -> (M.t_Operation) option -> bool =
fun v_operation v_found ->
(match v_found with
| None ->
false
| (Some (v_candidate)) ->
(Compare.f_same_operation (v_operation) (v_candidate)))
and (* checked_core.bend:156 *)
f_same_operations : (M.t_Operation) list -> (M.t_Operation) list -> bool =
fun v_required v_available ->
(match v_required with
| [] ->
true
| ((M.OperationTemplate (v_identity, v_parameters, v_parameter, v_result)) :: v_tail) ->
(f_same_operations (v_tail) (v_available))
| ((M.OperationInstance (v_template, v_arguments)) :: v_tail) ->
(f_same_operations (v_tail) (v_available))
| (v_operation :: v_tail) ->
(Base.bool_and ((f_matches_operation (v_operation) ((f_find_operation ((f_operation_identity (v_operation))) (v_available))))) ((f_same_operations (v_tail) (v_available)))))
and (* checked_core.bend:167 *)
f_valid_catalog : t_Certificate -> (M.t_DataType) list -> (M.t_Operation) list -> bool =
fun v_certificate v_types v_operations ->
(let (Certificate ((M.Module (v_constants, v_functions, v_original_types, v_original_operations)), v_checked, v_imports)) = v_certificate in
(Base.bool_and ((f_same_types (v_original_types) (v_types))) ((f_same_operations (v_original_operations) (v_operations)))))
and (* checked_core.bend:171 *)
f_indexed_types : (M.t_DataType) list -> (M.t_DataType) Base.map -> bool =
fun v_wanted v_available ->
(match v_wanted with
| [] ->
true
| (v_ty :: v_tail) ->
(Base.bool_and ((f_matches_type (v_ty) ((Index.f_find (v_available) ((Groups.f_type_key ((f_type_identity (v_ty))))))))) ((f_indexed_types (v_tail) (v_available)))))
and (* checked_core.bend:178 *)
f_indexed_operations : (M.t_Operation) list -> (M.t_Operation) Base.map -> bool =
fun v_required v_available ->
(match v_required with
| [] ->
true
| ((M.OperationTemplate (v_identity, v_parameters, v_parameter, v_result)) :: v_tail) ->
(f_indexed_operations (v_tail) (v_available))
| ((M.OperationInstance (v_template, v_arguments)) :: v_tail) ->
(f_indexed_operations (v_tail) (v_available))
| (v_operation :: v_tail) ->
(Base.bool_and ((f_matches_operation (v_operation) ((Index.f_find (v_available) ((Groups.f_type_key ((f_operation_identity (v_operation))))))))) ((f_indexed_operations (v_tail) (v_available)))))
and (* checked_core.bend:189 *)
f_valid_indexed_catalog : t_Certificate -> (M.t_DataType) Base.map -> (M.t_Operation) Base.map -> bool =
fun v_certificate v_types v_operations ->
(let (Certificate ((M.Module (v_constants, v_functions, v_original_types, v_original_operations)), v_checked, v_imports)) = v_certificate in
(Base.bool_and ((f_indexed_types (v_original_types) (v_types))) ((f_indexed_operations (v_original_operations) (v_operations)))))
and (* checked_core.bend:193 *)
f_indexed_catalog_certificates : (t_Certificate) list -> (M.t_DataType) Base.map -> (M.t_Operation) Base.map -> (t_Certificate) list =
fun v_certificates v_types v_operations ->
(match v_certificates with
| [] ->
[]
| (v_certificate :: v_tail) ->
(let v_rest = (f_indexed_catalog_certificates (v_tail) (v_types) (v_operations)) in
(Base.bool_pick ((f_valid_indexed_catalog (v_certificate) (v_types) (v_operations))) ((v_certificate :: v_rest)) (v_rest))))
and (* checked_core.bend:201 *)
f_catalog_certificates : (t_Certificate) list -> (M.t_DataType) list -> (M.t_Operation) list -> (t_Certificate) list =
fun v_certificates v_types v_operations ->
(match v_certificates with
| [] ->
[]
| (v_certificate :: v_tail) ->
(let v_rest = (f_catalog_certificates (v_tail) (v_types) (v_operations)) in
(Base.bool_pick ((f_valid_catalog (v_certificate) (v_types) (v_operations))) ((v_certificate :: v_rest)) (v_rest))))
and (* checked_core.bend:209 *)
f_names : M.t_Module -> (Base.text) list =
fun v_module ->
(let (M.Module (v_constants, v_functions, v_types, v_operations)) = v_module in
(Globals.f_names ((Base.list_append ((Globals.f_function_declarations (v_functions))) ((Globals.f_constant_declarations (v_constants)))))))
and (* checked_core.bend:213 *)
f_insert : t_Certificate -> ((t_Certificate) list) Base.map -> Base.text -> ((t_Certificate) list) option -> ((t_Certificate) list) Base.map =
fun v_certificate v_indexed v_name v_previous ->
(match v_previous with
| None ->
(Base.map_set (v_indexed) (v_name) ([v_certificate]))
| (Some (v_old)) ->
(Base.map_set (v_indexed) (v_name) ((v_certificate :: v_old))))
and (* checked_core.bend:220 *)
f_add_names : (Base.text) list -> t_Certificate -> ((t_Certificate) list) Base.map -> ((t_Certificate) list) Base.map =
fun v_members v_certificate v_indexed ->
(match v_members with
| [] ->
v_indexed
| (v_name :: v_tail) ->
(f_add_names (v_tail) (v_certificate) ((f_insert (v_certificate) (v_indexed) (v_name) ((Index.f_find (v_indexed) (v_name)))))))
and (* checked_core.bend:227 *)
f_index : (t_Certificate) list -> ((t_Certificate) list) Base.map =
fun v_certificates ->
(match v_certificates with
| [] ->
(Base.map_new ())
| ((Certificate (v_module, v_checked, v_imports)) :: v_tail) ->
(f_add_names ((f_names (v_module))) ((Certificate (v_module, v_checked, v_imports))) ((f_index (v_tail)))))
and (* checked_core.bend:234 *)
f_index_for_nonempty : M.t_Module -> (t_Certificate) list -> ((t_Certificate) list) Base.map =
fun v_final_module v_certificates ->
(let (M.Module (v_constants, v_functions, v_types, v_operations)) = v_final_module in
(let v_available_types = (f_first_type_index (v_types) ((Base.map_new ()))) in
(let v_available_operations = (f_first_operation_index (v_operations) ((Base.map_new ()))) in
(f_index ((f_indexed_catalog_certificates (v_certificates) (v_available_types) (v_available_operations)))))))
and (* checked_core.bend:240 *)
f_index_for : M.t_Module -> (t_Certificate) list -> ((t_Certificate) list) Base.map =
fun v_final_module v_certificates ->
(match v_certificates with
| [] ->
(Base.map_new ())
| (v_head :: v_tail) ->
(f_index_for_nonempty (v_final_module) ((v_head :: v_tail))))
and (* checked_core.bend:247 *)
f_same_kind : Groups.t_InterfaceKind -> Groups.t_InterfaceKind -> bool =
fun v_left v_right ->
(match (v_left, v_right) with
| (Groups.FunctionInterface, Groups.FunctionInterface) ->
true
| (Groups.ConstantInterface, Groups.ConstantInterface) ->
true
| (_, _) ->
false)
and (* checked_core.bend:256 *)
f_same_predicates_work : (M.t_Predicate) list -> (M.t_Predicate) list -> bool -> bool =
fun v_left v_right v_equal ->
(match (v_left, v_right, v_equal) with
| (_, _, false) ->
false
| ([], [], true) ->
true
| ((v_a :: v_rest), (v_b :: v_following), true) ->
(f_same_predicates_work (v_rest) (v_following) ((C.f_same_predicate (v_a) (v_b))))
| (_, _, _) ->
false)
and (* checked_core.bend:267 *)
f_same_predicates : (M.t_Predicate) list -> (M.t_Predicate) list -> bool =
fun v_left v_right ->
(f_same_predicates_work (v_left) (v_right) (true))
and (* checked_core.bend:270 *)
f_same_interface : Groups.t_Interface -> Groups.t_Interface -> bool =
fun v_left v_right ->
(let (Groups.Interface (v_a_name, v_a_kind, v_a_type, v_a_parameters, v_a_effects, v_a_predicates)) = v_left in
(let (Groups.Interface (v_b_name, v_b_kind, v_b_type, v_b_parameters, v_b_effects, v_b_predicates)) = v_right in
(Base.bool_and ((M.f_name_equal (v_a_name) (v_b_name))) ((Base.bool_and ((f_same_kind (v_a_kind) (v_b_kind))) ((Base.bool_and ((Base.nat_is_eq (v_a_parameters) (v_b_parameters))) ((Base.bool_and ((Groups.f_same_effects (v_a_effects) (v_b_effects))) ((Base.bool_and ((Compare.f_same_ty (v_a_type) (v_b_type))) ((f_same_predicates (v_a_predicates) (v_b_predicates))))))))))))))
and (* checked_core.bend:275 *)
f_same_imports : (Groups.t_Interface) list -> (Groups.t_Interface) list -> bool =
fun v_left v_right ->
(match (v_left, v_right) with
| ([], []) ->
true
| ((v_a :: v_rest), (v_b :: v_following)) ->
(Base.bool_and ((f_same_interface (v_a) (v_b))) ((f_same_imports (v_rest) (v_following))))
| (_, _) ->
false)
and (* checked_core.bend:284 *)
f_same_declarations : M.t_Module -> M.t_Module -> bool =
fun v_left v_right ->
(let (M.Module (v_a_constants, v_a_functions, v_a_types, v_a_operations)) = v_left in
(let (M.Module (v_b_constants, v_b_functions, v_b_types, v_b_operations)) = v_right in
(Compare.f_same_module ((M.Module (v_a_constants, v_a_functions, [], []))) ((M.Module (v_b_constants, v_b_functions, [], []))))))
and (* checked_core.bend:289 *)
f_matching_certificate : t_Certificate -> M.t_Module -> (Groups.t_Interface) list -> (Groups.t_CheckedGroup) option =
fun v_certificate v_subset v_imports ->
(let (Certificate (v_old_module, (Groups.CheckedGroup ((M.CheckedModule (v_old_constants, v_old_functions, v_old_types, v_old_operations)), v_interfaces, v_uses)), v_old_imports)) = v_certificate in
(let (M.Module (v_constants, v_functions, v_types, v_operations)) = v_subset in
(let v_valid = (Base.bool_and ((f_same_declarations (v_old_module) (v_subset))) ((f_same_imports (v_old_imports) (v_imports)))) in
(Base.bool_pick (v_valid) ((Some ((Groups.CheckedGroup ((M.CheckedModule (v_old_constants, v_old_functions, v_types, v_operations)), v_interfaces, v_uses))))) (None)))))
and (* checked_core.bend:295 *)
f_candidates_work : (t_Certificate) list -> M.t_Module -> (Groups.t_Interface) list -> (Groups.t_CheckedGroup) option -> (Groups.t_CheckedGroup) option =
fun v_available v_subset v_imports v_found ->
(match (v_available, v_found) with
| (_, (Some (v_group))) ->
(Some (v_group))
| ([], None) ->
None
| ((v_certificate :: v_tail), None) ->
(f_candidates_work (v_tail) (v_subset) (v_imports) ((f_matching_certificate (v_certificate) (v_subset) (v_imports)))))
and (* checked_core.bend:304 *)
f_candidates : (t_Certificate) list -> M.t_Module -> (Groups.t_Interface) list -> (Groups.t_CheckedGroup) option =
fun v_available v_subset v_imports ->
(f_candidates_work (v_available) (v_subset) (v_imports) (None))
and (* checked_core.bend:307 *)
f_available_candidates : ((t_Certificate) list) option -> M.t_Module -> (Groups.t_Interface) list -> (Groups.t_CheckedGroup) option =
fun v_found v_subset v_imports ->
(match v_found with
| None ->
None
| (Some (v_available)) ->
(f_candidates (v_available) (v_subset) (v_imports)))
and (* checked_core.bend:314 *)
f_lookup : ((t_Certificate) list) Base.map -> Groups.t_Job -> M.t_Module -> (Groups.t_Interface) list -> (Groups.t_CheckedGroup) option =
fun v_indexed v_job v_subset v_imports ->
(let (Groups.Job (v_members, v_dependencies, v_types)) = v_job in
(match v_members with
| [] ->
None
| (v_name :: v_tail) ->
(f_available_candidates ((Index.f_find (v_indexed) (v_name))) (v_subset) (v_imports))))
