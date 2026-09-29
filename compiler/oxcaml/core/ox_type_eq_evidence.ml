(* Native semantic port of compiler/type_eq_evidence.bend.

   Source SHA-256: 208924d7a7f92f8e082cd563b46fb0ec02f241f15db208d0d6489bd23ed37462

   Ownership/type arguments are erased; value types are checked by OCaml.

   No Bend interpreter or generated C/JavaScript is linked. *)

open Base

module M = Ox_model

module C = Ox_constraints

module Compare = Ox_core_compare

module State = Ox_state_specialize

module Staging = Ox_staging_scheme

module T = Ox_types

type t_Located =
  | Missing
  | One of M.t_Function
  | Duplicate
and t_TypeCatalog =
  | TypeAbsent
  | TypeUnique of bool
  | TypeDuplicate

let s_0 = Base.text_of_utf8 "$prelude.Type"

let s_1 = Base.text_of_utf8 "@type.same"

let s_2 = Base.text_of_utf8 "$prelude.Type.eq"

let s_3 = Base.text_of_utf8 "std/prelude"

let s_4 = Base.text_of_utf8 "Type"

let s_5 = Base.text_of_utf8 "$type.left"

let s_6 = Base.text_of_utf8 "$type.right"

let s_7 = Base.text_of_utf8 "eq"

let rec (* type_eq_evidence.bend:20 *)
f_locate_work : (M.t_Function) list -> Base.text -> t_Located -> t_Located =
fun v_functions v_wanted v_found ->
(match (v_functions, v_found) with
| ([], v_result) ->
v_result
| (((M.Function (v_name, v_exported, v_parameter, v_p, v_r, v_body)) :: v_tail), Missing) ->
(f_locate_work (v_tail) (v_wanted) ((Base.bool_pick ((M.f_name_equal (v_name) (v_wanted))) ((One ((M.Function (v_name, v_exported, v_parameter, v_p, v_r, v_body))))) (Missing))))
| (((M.Function (v_name, v_exported, v_parameter, v_p, v_r, v_body)) :: v_tail), (One (v_previous))) ->
(f_locate_work (v_tail) (v_wanted) ((Base.bool_pick ((M.f_name_equal (v_name) (v_wanted))) (Duplicate) ((One (v_previous))))))
| ((v_head :: v_tail), Duplicate) ->
(f_locate_work (v_tail) (v_wanted) (Duplicate)))
and (* type_eq_evidence.bend:31 *)
f_located : t_Located -> (M.t_Function) option =
fun v_found ->
(match v_found with
| (One (v_function)) ->
(Some (v_function))
| _ ->
None)
and (* type_eq_evidence.bend:38 *)
f_locate : (M.t_Function) list -> Base.text -> (M.t_Function) option =
fun v_functions v_name ->
(f_located ((f_locate_work (v_functions) (v_name) (Missing))))
and (* type_eq_evidence.bend:41 *)
f_local_name : M.t_Expr -> (Base.text) option =
fun v_value ->
(match v_value with
| (M.SourceExpr (v_offset, None, (M.InstantiationExpr (v_site, (M.LocalExpr (v_name)))))) ->
(Some (v_name))
| _ ->
None)
and (* type_eq_evidence.bend:48 *)
f_local_is_found : (Base.text) option -> Base.text -> bool =
fun v_found v_wanted ->
(match v_found with
| (Some (v_name)) ->
(M.f_name_equal (v_name) (v_wanted))
| None ->
false)
and (* type_eq_evidence.bend:55 *)
f_local_is : M.t_Expr -> Base.text -> bool =
fun v_value v_wanted ->
(f_local_is_found ((f_local_name (v_value))) (v_wanted))
and (* type_eq_evidence.bend:58 *)
f_arm_site : (M.t_Expr) M.t_MatchArm -> (int) option =
fun v_arm ->
(match v_arm with
| (M.MatchArm ([(M.ConstructorPattern (v_first, (Some ((M.BindingPattern (v_a)))))); (M.ConstructorPattern (v_second, (Some ((M.BindingPattern (v_b))))))], (M.SourceExpr (v_offset, None, (M.AssociatedExpr (v_site, M.BinaryDispatch, v_member, [], v_l, v_r)))))) ->
(Base.bool_pick ((Base.bool_and ((M.f_name_equal (v_first) (s_0))) ((Base.bool_and ((M.f_name_equal (v_second) (s_0))) ((Base.bool_and ((M.f_name_equal (v_member) (s_1))) ((Base.bool_and ((Base.bool_not ((M.f_name_equal (v_a) (v_b))))) ((Base.bool_and ((f_local_is (v_l) (v_a))) ((f_local_is (v_r) (v_b))))))))))))) ((Some (v_site))) (None))
| _ ->
None)
and (* type_eq_evidence.bend:65 *)
f_match_if : bool -> (M.t_Expr) M.t_MatchArm -> (int) option =
fun v_valid v_arm ->
(match v_valid with
| true ->
(f_arm_site (v_arm))
| false ->
None)
and (* type_eq_evidence.bend:72 *)
f_match_locals : (Base.text) option -> (Base.text) option -> (M.t_Expr) M.t_MatchArm -> Base.text -> Base.text -> (int) option =
fun v_a v_b v_arm v_left v_right ->
(match (v_a, v_b) with
| ((Some (v_found_left)), (Some (v_found_right))) ->
(f_match_if ((Base.bool_and ((M.f_name_equal (v_found_left) (v_left))) ((Base.bool_and ((M.f_name_equal (v_found_right) (v_right))) ((Base.bool_not ((M.f_name_equal (v_left) (v_right))))))))) (v_arm))
| (_, _) ->
None)
and (* type_eq_evidence.bend:79 *)
f_match_site : M.t_Expr -> Base.text -> Base.text -> (int) option =
fun v_value v_left v_right ->
(match v_value with
| (M.SourceExpr (v_offset, None, (M.MatchExpr ([v_a; v_b], [v_arm])))) ->
(f_match_locals ((f_local_name (v_a))) ((f_local_name (v_b))) (v_arm) (v_left) (v_right))
| _ ->
None)
and (* type_eq_evidence.bend:86 *)
f_source_clone_parsed : (Staging.t_CloneName) option -> bool =
fun v_parsed ->
(match v_parsed with
| (Some ((Staging.CloneName (v_counter, v_source)))) ->
(M.f_name_equal (v_source) (s_2))
| _ ->
false)
and (* type_eq_evidence.bend:93 *)
f_source_clone : Base.text -> bool =
fun v_name ->
(f_source_clone_parsed ((Staging.f_clone_name (v_name))))
and (* type_eq_evidence.bend:96 *)
f_canonical_if : bool -> M.t_Expr -> Base.text -> Base.text -> (int) option =
fun v_source v_body v_left v_right ->
(match v_source with
| true ->
(f_match_site (v_body) (v_left) (v_right))
| false ->
None)
and (* type_eq_evidence.bend:103 *)
f_canonical_site : M.t_Function -> (int) option =
fun v_function ->
(match v_function with
| (M.Function (v_name, false, v_left, None, None, (M.SourceExpr (v_offset, None, (M.LambdaExpr (v_identity, v_right, None, None, v_body)))))) ->
(f_canonical_if ((f_source_clone (v_name))) (v_body) (v_left) (v_right))
| _ ->
None)
and (* type_eq_evidence.bend:110 *)
f_clone_site_found : (M.t_Function) option -> (int) option =
fun v_found ->
(match v_found with
| (Some (v_function)) ->
(f_canonical_site (v_function))
| None ->
None)
and (* type_eq_evidence.bend:117 *)
f_clone_site : C.t_Evidence -> M.t_Module -> (int) option =
fun v_evidence v_module ->
(match (v_evidence, v_module) with
| ((C.SelectedFunction (v_name, v_signature)), (M.Module (v_constants, v_functions, v_types, v_operations))) ->
(f_clone_site_found ((f_locate (v_functions) (v_name))))
| (_, _) ->
None)
and (* type_eq_evidence.bend:124 *)
f_type_argument : M.t_Ty -> (M.t_Ty) option =
fun v_ty ->
(match v_ty with
| (M.AppliedTy (v_identity, [v_argument])) ->
(Base.bool_pick ((M.f_type_id_equal (v_identity) ((M.TypeId (s_3, s_4))))) ((Some (v_argument))) (None))
| _ ->
None)
and (* type_eq_evidence.bend:136 *)
f_exact_type_record : M.t_TypeId -> int -> bool -> (M.t_Ty) option -> (Base.text) list -> bool =
fun v_identity v_parameters v_sole v_payload v_fields ->
(match (v_payload, v_fields) with
| ((Some ((M.ParameterTy (0)))), []) ->
(Base.bool_and (v_sole) ((Base.bool_and ((M.f_type_id_equal (v_identity) ((M.TypeId (s_3, s_4))))) ((Base.nat_is_eq (v_parameters) (1))))))
| (_, _) ->
false)
and (* type_eq_evidence.bend:143 *)
f_catalog_record : bool -> bool -> t_TypeCatalog -> t_TypeCatalog =
fun v_named v_valid v_current ->
(match (v_named, v_current) with
| (false, v_previous) ->
v_previous
| (true, TypeAbsent) ->
(TypeUnique (v_valid))
| (true, _) ->
TypeDuplicate)
and (* type_eq_evidence.bend:152 *)
f_catalog_constructors : (M.t_Constructor) list -> M.t_TypeId -> int -> bool -> t_TypeCatalog -> t_TypeCatalog =
fun v_constructors v_identity v_parameters v_sole v_current ->
(match v_constructors with
| [] ->
v_current
| ((M.Constructor (v_name, v_payload, v_fields)) :: v_tail) ->
(f_catalog_constructors (v_tail) (v_identity) (v_parameters) (v_sole) ((f_catalog_record ((M.f_name_equal (v_name) (s_0))) ((f_exact_type_record (v_identity) (v_parameters) (v_sole) (v_payload) (v_fields))) (v_current)))))
and (* type_eq_evidence.bend:159 *)
f_catalog_types : (M.t_DataType) list -> t_TypeCatalog -> t_TypeCatalog =
fun v_types v_current ->
(match v_types with
| [] ->
v_current
| ((M.DataType (v_identity, v_parameters, v_constructors)) :: v_tail) ->
(f_catalog_types (v_tail) ((f_catalog_constructors (v_constructors) (v_identity) (v_parameters) ((Base.nat_is_eq ((Base.list_length (v_constructors))) (1))) (v_current)))))
and (* type_eq_evidence.bend:166 *)
f_type_owner_count : (M.t_DataType) list -> int =
fun v_types ->
(match v_types with
| [] ->
0
| ((M.DataType (v_identity, v_parameters, v_constructors)) :: v_tail) ->
(Base.nat_add ((Base.bool_pick ((M.f_type_id_equal (v_identity) ((M.TypeId (s_3, s_4))))) (1) (0))) ((f_type_owner_count (v_tail)))))
and (* type_eq_evidence.bend:173 *)
f_exact_type_catalog : t_TypeCatalog -> bool =
fun v_found ->
(match v_found with
| (TypeUnique (true)) ->
true
| _ ->
false)
and (* type_eq_evidence.bend:180 *)
f_exact_type_constructor : (M.t_DataType) list -> bool =
fun v_types ->
(Base.bool_and ((Base.nat_is_eq ((f_type_owner_count (v_types))) (1))) ((f_exact_type_catalog ((f_catalog_types (v_types) (TypeAbsent))))))
and (* type_eq_evidence.bend:183 *)
f_key_equal_results : (M.t_Diagnostic, Base.text) Base.result_ -> (M.t_Diagnostic, Base.text) Base.result_ -> (bool) option =
fun v_a_key v_b_key ->
(match (v_a_key, v_b_key) with
| ((Done (v_a)), (Done (v_b))) ->
(Some ((M.f_name_equal (v_a) (v_b))))
| (_, _) ->
None)
and (* type_eq_evidence.bend:190 *)
f_key_equal : M.t_Ty -> M.t_Ty -> (bool) option =
fun v_left v_right ->
(f_key_equal_results ((State.f_type_key (65536) ((State.TypeKey ((State.f_witness (65536) (v_left))))))) ((State.f_type_key (65536) ((State.TypeKey ((State.f_witness (65536) (v_right))))))))
and (* type_eq_evidence.bend:193 *)
f_generated_bool : M.t_Function -> bool -> bool =
fun v_function v_expected ->
(match v_function with
| (M.Function (v_name, false, v_first, None, None, (M.LambdaExpr (v_identity, v_second, None, None, (M.BoolExpr (v_actual)))))) ->
(Base.bool_and ((M.f_name_equal (v_first) (s_5))) ((Base.bool_and ((M.f_name_equal (v_second) (s_6))) ((Base.bool_not ((Base.bool_xor (v_expected) (v_actual))))))))
| _ ->
false)
and (* type_eq_evidence.bend:200 *)
f_same_selected_found : (M.t_Function) option -> M.t_Ty -> M.t_Ty -> M.t_Ty -> M.t_Ty -> bool -> bool =
fun v_found v_a v_b v_left v_right v_expected ->
(match v_found with
| (Some (v_function)) ->
(Base.bool_and ((Compare.f_same_ty (v_a) (v_left))) ((Base.bool_and ((Compare.f_same_ty (v_b) (v_right))) ((f_generated_bool (v_function) (v_expected))))))
| None ->
false)
and (* type_eq_evidence.bend:207 *)
f_same_selected : C.t_Evidence -> (M.t_Function) list -> M.t_Ty -> M.t_Ty -> bool -> bool =
fun v_same v_functions v_left v_right v_expected ->
(match v_same with
| (C.SelectedFunction (v_name, (M.FunctionTy (v_a, (M.FunctionTy (v_b, M.BoolTy, v_inner)), v_outer)))) ->
(f_same_selected_found ((f_locate (v_functions) (v_name))) (v_a) (v_b) (v_left) (v_right) (v_expected))
| _ ->
false)
and (* type_eq_evidence.bend:214 *)
f_certify_payloads_found : (bool) option -> M.t_Ty -> M.t_Ty -> C.t_Evidence -> (M.t_Function) list -> bool =
fun v_expected v_left v_right v_same v_functions ->
(match v_expected with
| (Some (v_answer)) ->
(f_same_selected (v_same) (v_functions) (v_left) (v_right) (v_answer))
| None ->
false)
and (* type_eq_evidence.bend:221 *)
f_certify_payloads : M.t_Ty -> M.t_Ty -> C.t_Evidence -> (M.t_Function) list -> bool =
fun v_left v_right v_same v_functions ->
(f_certify_payloads_found ((f_key_equal (v_left) (v_right))) (v_left) (v_right) (v_same) (v_functions))
and (* type_eq_evidence.bend:224 *)
f_disjoint_claim : (M.t_Diagnostic, (int) list) Base.result_ -> (M.t_Diagnostic, (int) list) Base.result_ -> int -> bool =
fun v_left v_right v_index ->
(match (v_left, v_right) with
| ((Done (v_a)), (Done (v_b))) ->
(Base.bool_and ((Base.bool_not ((T.f_contains (v_a) (v_index))))) ((Base.bool_not ((T.f_contains (v_b) (v_index))))))
| (_, _) ->
false)
and (* type_eq_evidence.bend:231 *)
f_pure_claim : M.t_EffectRow -> M.t_Ty -> M.t_Ty -> bool =
fun v_row v_left v_right ->
(match v_row with
| (M.EffectRow ([], M.ClosedRow)) ->
true
| (M.EffectRow ([], (M.RowVariable (v_index)))) ->
(f_disjoint_claim ((T.f_free (v_left))) ((T.f_free (v_right))) (v_index))
| _ ->
false)
and (* type_eq_evidence.bend:240 *)
f_certified_found : (M.t_Ty) option -> (M.t_Ty) option -> (int) option -> Base.text -> int -> M.t_EffectRow -> (M.t_DataType) list -> (M.t_Function) list -> M.t_Ty -> M.t_Ty -> M.t_Ty -> M.t_Ty -> C.t_Evidence -> (M.t_Ty) option =
fun v_a v_b v_site v_member v_wanted v_invocation v_types v_functions v_left v_right v_selected_left v_selected_right v_same ->
(match (v_a, v_b, v_site) with
| ((Some (v_payload_left)), (Some (v_payload_right)), (Some (v_found))) ->
(let v_valid = (Base.bool_and ((f_pure_claim (v_invocation) (v_left) (v_right))) ((Base.bool_and ((M.f_name_equal (v_member) (s_7))) ((Base.bool_and ((Base.nat_is_eq (v_found) (v_wanted))) ((Base.bool_and ((f_exact_type_constructor (v_types))) ((Base.bool_and ((Compare.f_same_ty (v_left) (v_selected_left))) ((Base.bool_and ((Compare.f_same_ty (v_right) (v_selected_right))) ((f_certify_payloads (v_payload_left) (v_payload_right) (v_same) (v_functions)))))))))))))) in
(Base.bool_pick (v_valid) ((Some ((M.FunctionTy (v_left, (M.FunctionTy (v_right, M.BoolTy, (M.f_empty_row ()))), (M.f_empty_row ())))))) (None)))
| (_, _, _) ->
None)
and (* type_eq_evidence.bend:248 *)
f_certified_signature : M.t_Predicate -> C.t_Evidence -> int -> C.t_Evidence -> M.t_Module -> (M.t_Ty) option =
fun v_predicate v_outer v_same_site v_same v_module ->
(match (v_predicate, v_outer, v_module) with
| ((M.AssociatedPredicate (v_member, [], v_left, v_right, M.BoolTy, v_invocation)), (C.SelectedFunction (v_name, (M.FunctionTy (v_selected_left, (M.FunctionTy (v_selected_right, M.BoolTy, v_inner)), v_outer_row)))), (M.Module (v_constants, v_functions, v_types, v_operations))) ->
(f_certified_found ((f_type_argument (v_left))) ((f_type_argument (v_right))) ((f_clone_site ((C.SelectedFunction (v_name, (M.FunctionTy (v_selected_left, (M.FunctionTy (v_selected_right, M.BoolTy, v_inner)), v_outer_row))))) ((M.Module (v_constants, v_functions, v_types, v_operations))))) (v_member) (v_same_site) (v_invocation) (v_types) (v_functions) (v_left) (v_right) (v_selected_left) (v_selected_right) (v_same))
| (_, _, _) ->
None)
