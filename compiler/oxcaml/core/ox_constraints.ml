(* Native semantic port of compiler/constraints.bend.

   Source SHA-256: dfb9f3893d837f0a3b4efbfa0adba5d96fdb6addeb52f96eb77ea1bbf4452397

   Ownership/type arguments are erased; value types are checked by OCaml.

   No Bend interpreter or generated C/JavaScript is linked. *)

open Base

module M = Ox_model

module T = Ox_types

module Index = Ox_index

module NatIndex = Ox_nat_index

module CoreCompare = Ox_core_compare

type t_UsePlan =
  | UsePlan of int * Base.text * M.t_Ty * (M.t_Predicate) list
and t_Evidence =
  | SelectedFunction of Base.text * M.t_Ty
  | SelectedField of M.t_TypeId * Base.text * Base.text * M.t_Ty
  | SelectedOperation of M.t_TypeId * M.t_Ty
  | RepresentedType of M.t_Ty
  | RepresentedEffect of M.t_EffectRow
and t_EvidenceAnswer =
  | EvidenceAnswer of M.t_Predicate * t_Evidence
and t_Transform =
  | Resolve of T.t_Substitutions
  | Rename of (int) NatIndex.t_Index * T.t_VariableKind
  | FreshParameters of (int) NatIndex.t_Index
  | RelocateFree of Base.text
  | ReplaceSource of Base.text * Base.text * int
  | ReplaceVariable of int * int
  | ReplaceParameter of int * M.t_Ty
and t_EntailShapes =
  | EntailShapes of M.t_Ty * M.t_Ty
and t_CanonicalBuckets =
  | CanonicalBuckets of (M.t_Predicate) list * ((M.t_Predicate) list) Base.map

let s_0 = Base.text_of_utf8 "unresolved_annotation"

let s_1 = Base.text_of_utf8 "constraint"

let s_2 = Base.text_of_utf8 "source type or row name reached a semantic predicate before annotation freshening"

let s_3 = Base.text_of_utf8 "c"

let s_4 = Base.text_of_utf8 "v"

let s_5 = Base.text_of_utf8 "p"

let s_6 = Base.text_of_utf8 "f"

let s_7 = Base.text_of_utf8 "_"

let s_8 = Base.text_of_utf8 "u"

let s_9 = Base.text_of_utf8 "i"

let s_10 = Base.text_of_utf8 "d"

let s_11 = Base.text_of_utf8 "b"

let s_12 = Base.text_of_utf8 "n"

let s_13 = Base.text_of_utf8 "F"

let s_14 = Base.text_of_utf8 ":"

let s_15 = Base.text_of_utf8 "P0"

let s_16 = Base.text_of_utf8 "P"

let s_17 = Base.text_of_utf8 "A0"

let s_18 = Base.text_of_utf8 "A"

let s_19 = Base.text_of_utf8 "R"

let s_20 = Base.text_of_utf8 "V"

let s_21 = Base.text_of_utf8 "S"

let s_22 = Base.text_of_utf8 "D"

let s_23 = Base.text_of_utf8 "E"

let s_24 = Base.text_of_utf8 "|"

let s_25 = Base.text_of_utf8 "U"

let s_26 = Base.text_of_utf8 "O"

let s_27 = Base.text_of_utf8 "T"

let rec (* constraints.bend:26 *)
f_predicate_types : M.t_Predicate -> (M.t_Ty) list =
fun v_predicate ->
(match v_predicate with
| (M.AssociatedPredicate (v_member, v_templates, v_left, v_right, v_result, v_invocation)) ->
[v_left; v_right; v_result]
| (M.ReceiverPredicate (v_member, v_templates, v_receiver, v_argument, v_result, v_invocation)) ->
[v_receiver; v_argument; v_result]
| (M.FieldPredicate (v_member, v_receiver, v_result)) ->
[v_receiver; v_result]
| (M.UpdatePredicate (v_member, v_receiver, v_assigned, v_result, v_invocation)) ->
[v_receiver; v_assigned; v_result]
| (M.OperationPredicate (v_template, v_arguments, v_function_type)) ->
(v_function_type :: v_arguments)
| (M.TypeRepPredicate (v_represented)) ->
[v_represented]
| (M.EffectRepPredicate (v_row)) ->
[])
and (* constraints.bend:43 *)
f_predicate_rows : M.t_Predicate -> (M.t_EffectRow) list =
fun v_predicate ->
(match v_predicate with
| (M.AssociatedPredicate (v_member, v_templates, v_left, v_right, v_result, v_invocation)) ->
[v_invocation]
| (M.ReceiverPredicate (v_member, v_templates, v_receiver, v_argument, v_result, v_invocation)) ->
[v_invocation]
| (M.UpdatePredicate (v_member, v_receiver, v_assigned, v_result, v_invocation)) ->
[v_invocation]
| (M.EffectRepPredicate (v_row)) ->
[v_row]
| _ ->
[])
and (* constraints.bend:56 *)
f_rows_free : (M.t_EffectRow) list -> (int) list =
fun v_rows ->
(match v_rows with
| [] ->
[]
| (v_row :: v_tail) ->
(T.f_union ((T.f_row_free (v_row))) ((f_rows_free (v_tail)))))
and (* constraints.bend:63 *)
f_unresolved_rows : (M.t_EffectRow) list -> bool =
fun v_rows ->
(match v_rows with
| [] ->
false
| ((M.EffectRow (v_operations, (M.FreeRow (v_scope, v_name)))) :: v_tail) ->
true
| (v_head :: v_tail) ->
(f_unresolved_rows (v_tail)))
and (* constraints.bend:72 *)
f_require_resolved_source : (M.t_Ty) list -> bool -> (M.t_Diagnostic, unit) Base.result_ =
fun v_names v_open_row ->
(match (v_names, v_open_row) with
| ([], false) ->
(Done (()))
| (_, _) ->
(Fail ((M.Diagnostic (s_0, s_1, s_2)))))
and (* constraints.bend:79 *)
f_free : M.t_Predicate -> (M.t_Diagnostic, (int) list) Base.result_ =
fun v_predicate ->
(match (T.f_annotation_names (65536) ((T.ManyTypes ((f_predicate_types (v_predicate)))))) with
| Fail __error -> Fail __error
| Done v_source_names ->
(match (f_require_resolved_source (v_source_names) ((f_unresolved_rows ((f_predicate_rows (v_predicate)))))) with
| Fail __error -> Fail __error
| Done v_source ->
(match (T.f_free ((M.ProductTy ((f_predicate_types (v_predicate)))))) with
| Fail __error -> Fail __error
| Done v_types ->
(Done ((T.f_union (v_types) ((f_rows_free ((f_predicate_rows (v_predicate)))))))))))
and (* constraints.bend:89 *)
f_free_list_groups : (M.t_Predicate) list -> ((int) list) list -> (M.t_Diagnostic, ((int) list) list) Base.result_ =
fun v_predicates v_reversed ->
(match v_predicates with
| [] ->
(Done (v_reversed))
| (v_head :: v_tail) ->
(match (f_free (v_head)) with
| Fail __error -> Fail __error
| Done v_own ->
(f_free_list_groups (v_tail) ((v_own :: v_reversed)))))
and (* constraints.bend:98 *)
f_free_list_union_indexed : ((int) list) list -> T.t_VariableUnion -> T.t_VariableUnion =
fun v_reversed v_accumulated ->
(match v_reversed with
| [] ->
v_accumulated
| (v_own :: v_tail) ->
(f_free_list_union_indexed (v_tail) ((T.f_union_into (v_own) (v_accumulated)))))
and (* constraints.bend:108 *)
f_free_list_union : ((int) list) list -> (int) list -> (int) list =
fun v_reversed v_accumulated ->
(match v_reversed with
| [] ->
v_accumulated
| (v_own :: v_tail) ->
(T.f_union_values ((f_free_list_union_indexed ((v_own :: v_tail)) ((T.f_union_seed (v_accumulated)))))))
and (* constraints.bend:115 *)
f_free_list : (M.t_Predicate) list -> (M.t_Diagnostic, (int) list) Base.result_ =
fun v_predicates ->
(match (f_free_list_groups (v_predicates) ([])) with
| Fail __error -> Fail __error
| Done v_groups ->
(Done ((f_free_list_union (v_groups) ([])))))
and (* constraints.bend:129 *)
f_transform_type : M.t_Ty -> t_Transform -> (M.t_Diagnostic, M.t_Ty) Base.result_ =
fun v_ty v_transform ->
(match v_transform with
| (Resolve (v_substitutions)) ->
(T.f_resolve (v_substitutions) (v_ty))
| (Rename (v_mapping, v_kind)) ->
(match (T.f_rename_work (65536) ((T.OneType (v_ty))) (v_mapping) (v_kind)) with
| Fail __error -> Fail __error
| Done v_types ->
(T.f_first_type (v_types)))
| (FreshParameters (v_mapping)) ->
(match (T.f_rewrite (65536) ((T.OneType (v_ty))) ((T.FreshParameters (v_mapping)))) with
| Fail __error -> Fail __error
| Done v_types ->
(T.f_first_type (v_types)))
| (RelocateFree (v_suffix)) ->
(match (T.f_rewrite (65536) ((T.OneType (v_ty))) ((T.RelocateFree (v_suffix)))) with
| Fail __error -> Fail __error
| Done v_types ->
(T.f_first_type (v_types)))
| (ReplaceSource (v_scope, v_name, v_variable)) ->
(match (T.f_rewrite (65536) ((T.OneType (v_ty))) ((T.ReplaceFree (v_scope, v_name, (M.VariableTy (v_variable)))))) with
| Fail __error -> Fail __error
| Done v_types ->
(T.f_first_type (v_types)))
| (ReplaceVariable (v_index, v_variable)) ->
(T.f_replace (v_ty) (v_index) ((M.VariableTy (v_variable))))
| (ReplaceParameter (v_index, v_value)) ->
(match (T.f_rewrite (65536) ((T.OneType (v_ty))) ((T.ReplaceParameter (v_index, v_value)))) with
| Fail __error -> Fail __error
| Done v_types ->
(T.f_first_type (v_types))))
and (* constraints.bend:156 *)
f_transform_row : M.t_EffectRow -> t_Transform -> (M.t_Diagnostic, M.t_EffectRow) Base.result_ =
fun v_row v_transform ->
(match v_transform with
| (Resolve (v_substitutions)) ->
(Done ((T.f_resolve_row (v_substitutions) (v_row))))
| (Rename (v_mapping, v_kind)) ->
(Done ((T.f_rename_row_kind (v_row) (v_mapping) (v_kind))))
| (FreshParameters (v_mapping)) ->
(T.f_rewrite_row (v_row) ((T.FreshParameters (v_mapping))))
| (RelocateFree (v_suffix)) ->
(T.f_rewrite_row (v_row) ((T.RelocateFree (v_suffix))))
| (ReplaceSource (v_scope, v_name, v_variable)) ->
(T.f_rewrite_row (v_row) ((T.ReplaceFree (v_scope, v_name, (M.VariableTy (v_variable))))))
| (ReplaceVariable (v_index, v_variable)) ->
(T.f_rewrite_row (v_row) ((T.ReplaceVariable (v_index, (M.VariableTy (v_variable))))))
| (ReplaceParameter (v_index, v_value)) ->
(T.f_rewrite_row (v_row) ((T.ReplaceParameter (v_index, v_value)))))
and (* constraints.bend:173 *)
f_transform_types : (M.t_Ty) list -> t_Transform -> (M.t_Diagnostic, (M.t_Ty) list) Base.result_ =
fun v_types v_transform ->
(match v_types with
| [] ->
(Done ([]))
| (v_head :: v_tail) ->
(match (f_transform_type (v_head) (v_transform)) with
| Fail __error -> Fail __error
| Done v_next ->
(match (f_transform_types (v_tail) (v_transform)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done ((v_next :: v_rest))))))
and (* constraints.bend:183 *)
f_transform : M.t_Predicate -> t_Transform -> (M.t_Diagnostic, M.t_Predicate) Base.result_ =
fun v_predicate v_change ->
(match v_predicate with
| (M.AssociatedPredicate (v_member, v_templates, v_left, v_right, v_result, v_row)) ->
(match (f_transform_type (v_left) (v_change)) with
| Fail __error -> Fail __error
| Done v_l ->
(match (f_transform_type (v_right) (v_change)) with
| Fail __error -> Fail __error
| Done v_r ->
(match (f_transform_type (v_result) (v_change)) with
| Fail __error -> Fail __error
| Done v_out ->
(match (f_transform_row (v_row) (v_change)) with
| Fail __error -> Fail __error
| Done v_changed ->
(Done ((M.AssociatedPredicate (v_member, v_templates, v_l, v_r, v_out, v_changed))))))))
| (M.ReceiverPredicate (v_member, v_templates, v_receiver, v_argument, v_result, v_row)) ->
(match (f_transform_type (v_receiver) (v_change)) with
| Fail __error -> Fail __error
| Done v_recv ->
(match (f_transform_type (v_argument) (v_change)) with
| Fail __error -> Fail __error
| Done v_arg ->
(match (f_transform_type (v_result) (v_change)) with
| Fail __error -> Fail __error
| Done v_out ->
(match (f_transform_row (v_row) (v_change)) with
| Fail __error -> Fail __error
| Done v_changed ->
(Done ((M.ReceiverPredicate (v_member, v_templates, v_recv, v_arg, v_out, v_changed))))))))
| (M.FieldPredicate (v_member, v_receiver, v_result)) ->
(match (f_transform_type (v_receiver) (v_change)) with
| Fail __error -> Fail __error
| Done v_recv ->
(match (f_transform_type (v_result) (v_change)) with
| Fail __error -> Fail __error
| Done v_out ->
(Done ((M.FieldPredicate (v_member, v_recv, v_out))))))
| (M.UpdatePredicate (v_member, v_receiver, v_assigned, v_result, v_row)) ->
(match (f_transform_type (v_receiver) (v_change)) with
| Fail __error -> Fail __error
| Done v_recv ->
(match (f_transform_type (v_assigned) (v_change)) with
| Fail __error -> Fail __error
| Done v_value ->
(match (f_transform_type (v_result) (v_change)) with
| Fail __error -> Fail __error
| Done v_out ->
(match (f_transform_row (v_row) (v_change)) with
| Fail __error -> Fail __error
| Done v_changed ->
(Done ((M.UpdatePredicate (v_member, v_recv, v_value, v_out, v_changed))))))))
| (M.OperationPredicate (v_template, v_arguments, v_function_type)) ->
(match (f_transform_types (v_arguments) (v_change)) with
| Fail __error -> Fail __error
| Done v_args ->
(match (f_transform_type (v_function_type) (v_change)) with
| Fail __error -> Fail __error
| Done v_ty ->
(Done ((M.OperationPredicate (v_template, v_args, v_ty))))))
| (M.TypeRepPredicate (v_represented)) ->
(match (f_transform_type (v_represented) (v_change)) with
| Fail __error -> Fail __error
| Done v_ty ->
(Done ((M.TypeRepPredicate (v_ty)))))
| (M.EffectRepPredicate (v_row)) ->
(match (f_transform_row (v_row) (v_change)) with
| Fail __error -> Fail __error
| Done v_changed ->
(Done ((M.EffectRepPredicate (v_changed))))))
and (* constraints.bend:228 *)
f_transform_list_work : (M.t_Predicate) list -> t_Transform -> (M.t_Predicate) list -> (M.t_Diagnostic, (M.t_Predicate) list) Base.result_ =
fun v_predicates v_change v_reversed ->
(match v_predicates with
| [] ->
(Done ((Base.list_reverse (v_reversed))))
| (v_head :: v_tail) ->
(match (f_transform (v_head) (v_change)) with
| Fail __error -> Fail __error
| Done v_first ->
(f_transform_list_work (v_tail) (v_change) ((v_first :: v_reversed)))))
and (* constraints.bend:237 *)
f_transform_list : (M.t_Predicate) list -> t_Transform -> (M.t_Diagnostic, (M.t_Predicate) list) Base.result_ =
fun v_predicates v_change ->
(f_transform_list_work (v_predicates) (v_change) ([]))
and (* constraints.bend:240 *)
f_resolve : T.t_Substitutions -> M.t_Predicate -> (M.t_Diagnostic, M.t_Predicate) Base.result_ =
fun v_substitutions v_predicate ->
(f_transform (v_predicate) ((Resolve (v_substitutions))))
and (* constraints.bend:243 *)
f_resolve_list : T.t_Substitutions -> (M.t_Predicate) list -> (M.t_Diagnostic, (M.t_Predicate) list) Base.result_ =
fun v_substitutions v_predicates ->
(f_transform_list (v_predicates) ((Resolve (v_substitutions))))
and (* constraints.bend:246 *)
f_resolve_use : t_UsePlan -> T.t_Substitutions -> (M.t_Diagnostic, t_UsePlan) Base.result_ =
fun v_plan v_substitutions ->
(let (UsePlan (v_site, v_subject, v_ty, v_predicates)) = v_plan in
(match (T.f_resolve (v_substitutions) (v_ty)) with
| Fail __error -> Fail __error
| Done v_resolved ->
(match (f_resolve_list (v_substitutions) (v_predicates)) with
| Fail __error -> Fail __error
| Done v_needs ->
(Done ((UsePlan (v_site, v_subject, v_resolved, v_needs)))))))
and (* constraints.bend:253 *)
f_resolve_uses : (t_UsePlan) list -> T.t_Substitutions -> (M.t_Diagnostic, (t_UsePlan) list) Base.result_ =
fun v_plans v_substitutions ->
(match v_plans with
| [] ->
(Done ([]))
| (v_head :: v_tail) ->
(match (f_resolve_use (v_head) (v_substitutions)) with
| Fail __error -> Fail __error
| Done v_plan ->
(match (f_resolve_uses (v_tail) (v_substitutions)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done ((v_plan :: v_rest))))))
and (* constraints.bend:263 *)
f_rename : (int) NatIndex.t_Index -> M.t_Predicate -> (M.t_Diagnostic, M.t_Predicate) Base.result_ =
fun v_mapping v_predicate ->
(f_transform (v_predicate) ((Rename (v_mapping, T.FreshVariables))))
and (* constraints.bend:266 *)
f_rename_list : (int) NatIndex.t_Index -> (M.t_Predicate) list -> (M.t_Diagnostic, (M.t_Predicate) list) Base.result_ =
fun v_mapping v_predicates ->
(f_transform_list (v_predicates) ((Rename (v_mapping, T.FreshVariables))))
and (* constraints.bend:269 *)
f_parameterize : (int) NatIndex.t_Index -> M.t_Predicate -> (M.t_Diagnostic, M.t_Predicate) Base.result_ =
fun v_mapping v_predicate ->
(f_transform (v_predicate) ((Rename (v_mapping, T.SchemeParameters))))
and (* constraints.bend:272 *)
f_parameterize_list : (int) NatIndex.t_Index -> (M.t_Predicate) list -> (M.t_Diagnostic, (M.t_Predicate) list) Base.result_ =
fun v_mapping v_predicates ->
(f_transform_list (v_predicates) ((Rename (v_mapping, T.SchemeParameters))))
and (* constraints.bend:275 *)
f_relocate_free : (M.t_Predicate) list -> Base.text -> (M.t_Diagnostic, (M.t_Predicate) list) Base.result_ =
fun v_predicates v_suffix ->
(f_transform_list (v_predicates) ((RelocateFree (v_suffix))))
and (* constraints.bend:278 *)
f_replace_source : (M.t_Predicate) list -> Base.text -> Base.text -> int -> (M.t_Diagnostic, (M.t_Predicate) list) Base.result_ =
fun v_predicates v_scope v_name v_variable ->
(f_transform_list (v_predicates) ((ReplaceSource (v_scope, v_name, v_variable))))
and (* constraints.bend:281 *)
f_replace_variable : (M.t_Predicate) list -> int -> int -> (M.t_Diagnostic, (M.t_Predicate) list) Base.result_ =
fun v_predicates v_index v_variable ->
(f_transform_list (v_predicates) ((ReplaceVariable (v_index, v_variable))))
and (* constraints.bend:284 *)
f_instantiate_parameters_sequential : (M.t_Ty) list -> (M.t_Predicate) list -> int -> (M.t_Diagnostic, (M.t_Predicate) list) Base.result_ =
fun v_arguments v_predicates v_index ->
(match v_arguments with
| [] ->
(Done (v_predicates))
| (v_head :: v_tail) ->
(match (f_transform_list (v_predicates) ((ReplaceParameter (v_index, v_head)))) with
| Fail __error -> Fail __error
| Done v_changed ->
(f_instantiate_parameters_sequential (v_tail) (v_changed) ((Base.nat_add 1 v_index)))))
and (* constraints.bend:298 *)
f_fresh_parameter_mapping : (M.t_Ty) list -> int -> (int) NatIndex.t_Index -> ((int) NatIndex.t_Index) option =
fun v_arguments v_index v_mapping ->
(match v_arguments with
| [] ->
(Some (v_mapping))
| ((M.VariableTy (v_variable)) :: v_tail) ->
(f_fresh_parameter_mapping (v_tail) ((Base.nat_add 1 v_index)) ((NatIndex.f_set (v_mapping) (v_index) (v_variable))))
| (v_other :: v_tail) ->
None)
and (* constraints.bend:307 *)
f_instantiate_parameters_selected : ((int) NatIndex.t_Index) option -> (M.t_Ty) list -> (M.t_Predicate) list -> int -> (M.t_Diagnostic, (M.t_Predicate) list) Base.result_ =
fun v_found v_arguments v_predicates v_index ->
(match v_found with
| (Some (v_mapping)) ->
(f_transform_list (v_predicates) ((FreshParameters (v_mapping))))
| None ->
(f_instantiate_parameters_sequential (v_arguments) (v_predicates) (v_index)))
and (* constraints.bend:314 *)
f_instantiate_parameters : (M.t_Ty) list -> (M.t_Predicate) list -> int -> (M.t_Diagnostic, (M.t_Predicate) list) Base.result_ =
fun v_arguments v_predicates v_index ->
(match v_arguments with
| [] ->
(Done (v_predicates))
| (v_head :: v_tail) ->
(f_instantiate_parameters_selected ((f_fresh_parameter_mapping ((v_head :: v_tail)) (v_index) ((NatIndex.f_new ())))) ((v_head :: v_tail)) (v_predicates) (v_index)))
and (* constraints.bend:321 *)
f_row_annotation_names : (M.t_EffectRow) list -> (M.t_Ty) list =
fun v_rows ->
(match v_rows with
| [] ->
[]
| (v_head :: v_tail) ->
(Base.list_append ((T.f_annotation_row_names (v_head))) ((f_row_annotation_names (v_tail)))))
and (* constraints.bend:328 *)
f_annotation_names : (M.t_Predicate) list -> (M.t_Diagnostic, (M.t_Ty) list) Base.result_ =
fun v_predicates ->
(match v_predicates with
| [] ->
(Done ([]))
| (v_head :: v_tail) ->
(match (T.f_annotation_names (65536) ((T.ManyTypes ((f_predicate_types (v_head)))))) with
| Fail __error -> Fail __error
| Done v_types ->
(match (f_annotation_names (v_tail)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done ((Base.list_append (v_types) ((Base.list_append ((f_row_annotation_names ((f_predicate_rows (v_head))))) (v_rest)))))))))
and (* constraints.bend:338 *)
f_predicate_members : (M.t_Predicate) list -> (Base.text) list =
fun v_predicates ->
(match v_predicates with
| [] ->
[]
| ((M.AssociatedPredicate (v_member, v_templates, v_left, v_right, v_result, v_row)) :: v_tail) ->
(v_member :: (f_predicate_members (v_tail)))
| ((M.ReceiverPredicate (v_member, v_templates, v_receiver, v_argument, v_result, v_row)) :: v_tail) ->
(v_member :: (f_predicate_members (v_tail)))
| ((M.FieldPredicate (v_member, v_receiver, v_result)) :: v_tail) ->
(v_member :: (f_predicate_members (v_tail)))
| ((M.UpdatePredicate (v_member, v_receiver, v_assigned, v_result, v_row)) :: v_tail) ->
(v_member :: (f_predicate_members (v_tail)))
| (v_head :: v_tail) ->
(f_predicate_members (v_tail)))
and (* constraints.bend:353 *)
f_predicate_templates : (M.t_Predicate) list -> (M.t_TypeId) list =
fun v_predicates ->
(match v_predicates with
| [] ->
[]
| ((M.AssociatedPredicate (v_member, v_templates, v_left, v_right, v_result, v_row)) :: v_tail) ->
(Base.list_append (v_templates) ((f_predicate_templates (v_tail))))
| ((M.ReceiverPredicate (v_member, v_templates, v_receiver, v_argument, v_result, v_row)) :: v_tail) ->
(Base.list_append (v_templates) ((f_predicate_templates (v_tail))))
| ((M.OperationPredicate (v_template, v_arguments, v_function_type)) :: v_tail) ->
(v_template :: (f_predicate_templates (v_tail)))
| (v_head :: v_tail) ->
(f_predicate_templates (v_tail)))
and (* constraints.bend:366 *)
f_same_predicate : M.t_Predicate -> M.t_Predicate -> bool =
fun v_left v_right ->
(CoreCompare.f_same_predicate (v_left) (v_right))
and (* constraints.bend:369 *)
f_same_type_ids : (M.t_TypeId) list -> (M.t_TypeId) list -> bool =
fun v_left v_right ->
(match (v_left, v_right) with
| ([], []) ->
true
| ((v_a :: v_left_tail), (v_b :: v_right_tail)) ->
(Base.bool_and ((M.f_type_id_equal (v_a) (v_b))) ((f_same_type_ids (v_left_tail) (v_right_tail))))
| (_, _) ->
false)
and (* constraints.bend:378 *)
f_same_head : M.t_Predicate -> M.t_Predicate -> bool =
fun v_left v_right ->
(match (v_left, v_right) with
| ((M.AssociatedPredicate (v_lm, v_lt, v_a, v_b, v_c, v_lr)), (M.AssociatedPredicate (v_rm, v_rt, v_d, v_e, v_f, v_rr))) ->
(Base.bool_and ((M.f_name_equal (v_lm) (v_rm))) ((f_same_type_ids (v_lt) (v_rt))))
| ((M.ReceiverPredicate (v_lm, v_lt, v_a, v_b, v_c, v_lr)), (M.ReceiverPredicate (v_rm, v_rt, v_d, v_e, v_f, v_rr))) ->
(Base.bool_and ((M.f_name_equal (v_lm) (v_rm))) ((f_same_type_ids (v_lt) (v_rt))))
| ((M.ReceiverPredicate (v_lm, [], v_a, M.UnitTy, v_c, v_lr)), (M.FieldPredicate (v_rm, v_d, v_e))) ->
(M.f_name_equal (v_lm) (v_rm))
| ((M.FieldPredicate (v_lm, v_a, v_b)), (M.FieldPredicate (v_rm, v_c, v_d))) ->
(M.f_name_equal (v_lm) (v_rm))
| ((M.UpdatePredicate (v_lm, v_a, v_b, v_c, v_lr)), (M.UpdatePredicate (v_rm, v_d, v_e, v_f, v_rr))) ->
(M.f_name_equal (v_lm) (v_rm))
| ((M.OperationPredicate (v_lt, v_a, v_b)), (M.OperationPredicate (v_rt, v_c, v_d))) ->
(M.f_type_id_equal (v_lt) (v_rt))
| ((M.TypeRepPredicate (v_a)), (M.TypeRepPredicate (v_b))) ->
true
| ((M.EffectRepPredicate (v_a)), (M.EffectRepPredicate (v_b))) ->
true
| (_, _) ->
false)
and (* constraints.bend:399 *)
f_row_shapes : (M.t_EffectRow) list -> (M.t_Ty) list =
fun v_rows ->
(match v_rows with
| [] ->
[]
| (v_row :: v_tail) ->
((M.FunctionTy (M.UnitTy, M.UnitTy, v_row)) :: (f_row_shapes (v_tail))))
and (* constraints.bend:406 *)
f_shape_parts : (M.t_Ty) list -> M.t_Ty =
fun v_parts ->
(match v_parts with
| [] ->
M.UnitTy
| (v_single :: []) ->
v_single
| v_multiple ->
(M.ProductTy (v_multiple)))
and (* constraints.bend:415 *)
f_shape_type : M.t_Predicate -> M.t_Ty =
fun v_predicate ->
(f_shape_parts ((Base.list_append ((f_predicate_types (v_predicate))) ((f_row_shapes ((f_predicate_rows (v_predicate))))))))
and (* constraints.bend:421 *)
f_entail_shapes : M.t_Predicate -> M.t_Predicate -> t_EntailShapes =
fun v_required v_declared ->
(match (v_required, v_declared) with
| ((M.ReceiverPredicate (v_member, [], v_receiver, M.UnitTy, v_result, v_row)), (M.FieldPredicate (v_field, v_owner, v_value))) ->
(EntailShapes ((M.ProductTy ([v_receiver; v_result])), (M.ProductTy ([v_owner; v_value]))))
| (v_left, v_right) ->
(EntailShapes ((f_shape_type (v_left)), (f_shape_type (v_right)))))
and (* constraints.bend:428 *)
f_contains_work : (M.t_Predicate) list -> bool -> M.t_Predicate -> bool =
fun v_predicates v_matched v_wanted ->
(match (v_predicates, v_matched) with
| (_, true) ->
true
| ([], false) ->
false
| ((v_head :: v_tail), false) ->
(f_contains_work (v_tail) ((f_same_predicate (v_head) (v_wanted))) (v_wanted)))
and (* constraints.bend:437 *)
f_contains : (M.t_Predicate) list -> M.t_Predicate -> bool =
fun v_predicates v_wanted ->
(f_contains_work (v_predicates) (false) (v_wanted))
and (* constraints.bend:440 *)
f_contains_head_work : (M.t_Predicate) list -> bool -> M.t_Predicate -> bool =
fun v_predicates v_matched v_wanted ->
(match (v_predicates, v_matched) with
| (_, true) ->
true
| ([], false) ->
false
| ((v_head :: v_tail), false) ->
(f_contains_head_work (v_tail) ((f_same_head (v_wanted) (v_head))) (v_wanted)))
and (* constraints.bend:449 *)
f_contains_head : (M.t_Predicate) list -> M.t_Predicate -> bool =
fun v_predicates v_wanted ->
(f_contains_head_work (v_predicates) (false) (v_wanted))
and (* constraints.bend:455 *)
f_row_tail_bucket : M.t_EffectRow -> Base.text =
fun v_row ->
(match v_row with
| (M.EffectRow (v_labels, M.ClosedRow)) ->
s_3
| (M.EffectRow (v_labels, (M.RowVariable (v_index)))) ->
(Base.string_append s_4 (Base.nat_show (v_index)))
| (M.EffectRow (v_labels, (M.RowParameter (v_index)))) ->
(Base.string_append s_5 (Base.nat_show (v_index)))
| (M.EffectRow (v_labels, (M.FreeRow (v_scope, v_name)))) ->
s_6)
and (* constraints.bend:466 *)
f_type_bucket : int -> M.t_Ty -> Base.text =
fun v_depth v_ty ->
(match (v_depth, v_ty) with
| (0, _) ->
s_7
| (__nat_1, M.UnitTy) when __nat_1 >= 1 ->
(let v_rest = (__nat_1 - 1) in
s_8)
| (__nat_2, M.U32Ty) when __nat_2 >= 1 ->
(let v_rest = (__nat_2 - 1) in
s_9)
| (__nat_3, M.F32Ty) when __nat_3 >= 1 ->
(let v_rest = (__nat_3 - 1) in
s_10)
| (__nat_4, M.BoolTy) when __nat_4 >= 1 ->
(let v_rest = (__nat_4 - 1) in
s_11)
| (__nat_5, M.NeverTy) when __nat_5 >= 1 ->
(let v_rest = (__nat_5 - 1) in
s_12)
| (__nat_6, (M.VariableTy (v_index))) when __nat_6 >= 1 ->
(let v_rest = (__nat_6 - 1) in
(Base.string_append s_4 (Base.nat_show (v_index))))
| (__nat_7, (M.ParameterTy (v_index))) when __nat_7 >= 1 ->
(let v_rest = (__nat_7 - 1) in
(Base.string_append s_5 (Base.nat_show (v_index))))
| (__nat_8, (M.FreeTy (v_scope, v_name))) when __nat_8 >= 1 ->
(let v_rest = (__nat_8 - 1) in
s_6)
| (__nat_9, (M.FunctionTy (v_parameter, v_result, v_effects))) when __nat_9 >= 1 ->
(let v_rest = (__nat_9 - 1) in
(Base.string_append s_13 (Base.string_append (f_type_bucket (v_rest) (v_parameter)) (Base.string_append s_14 (Base.string_append (f_type_bucket (v_rest) (v_result)) (Base.string_append s_14 (f_row_tail_bucket (v_effects))))))))
| (__nat_10, (M.ProductTy ([]))) when __nat_10 >= 1 ->
(let v_rest = (__nat_10 - 1) in
s_15)
| (__nat_11, (M.ProductTy ((v_head :: v_tail)))) when __nat_11 >= 1 ->
(let v_rest = (__nat_11 - 1) in
(Base.string_append s_16 (f_type_bucket (v_rest) (v_head))))
| (__nat_12, (M.AppliedTy (v_identity, []))) when __nat_12 >= 1 ->
(let v_rest = (__nat_12 - 1) in
s_17)
| (__nat_13, (M.AppliedTy (v_identity, (v_head :: v_tail)))) when __nat_13 >= 1 ->
(let v_rest = (__nat_13 - 1) in
(Base.string_append s_18 (f_type_bucket (v_rest) (v_head))))
| (__nat_14, (M.ArrayTy (v_element))) when __nat_14 >= 1 ->
(let v_rest = (__nat_14 - 1) in
(Base.string_append s_19 (f_type_bucket (v_rest) (v_element))))
| (__nat_15, (M.ProviderTy (v_identity, v_effects))) when __nat_15 >= 1 ->
(let v_rest = (__nat_15 - 1) in
(Base.string_append s_20 (f_row_tail_bucket (v_effects))))
| (__nat_16, (M.StateProviderTy (v_read, v_write, v_state))) when __nat_16 >= 1 ->
(let v_rest = (__nat_16 - 1) in
(Base.string_append s_21 (f_type_bucket (v_rest) (v_state))))
| (__nat_17, M.EffectDescriptorTy) when __nat_17 >= 1 ->
(let v_rest = (__nat_17 - 1) in
s_22)
| (__nat_18, M.EffectSetTy) when __nat_18 >= 1 ->
(let v_rest = (__nat_18 - 1) in
s_23))
and (* constraints.bend:507 *)
f_predicate_bucket : M.t_Predicate -> Base.text =
fun v_predicate ->
(match v_predicate with
| (M.AssociatedPredicate (v_member, v_templates, v_left, v_right, v_result, v_invocation)) ->
(Base.string_append s_18 (Base.string_append v_member (Base.string_append s_24 (Base.string_append (f_type_bucket (3) (v_left)) (Base.string_append s_24 (Base.string_append (f_type_bucket (3) (v_right)) (Base.string_append s_24 (Base.string_append (f_type_bucket (3) (v_result)) (Base.string_append s_24 (f_row_tail_bucket (v_invocation)))))))))))
| (M.ReceiverPredicate (v_member, v_templates, v_receiver, v_argument, v_result, v_invocation)) ->
(Base.string_append s_19 (Base.string_append v_member (Base.string_append s_24 (Base.string_append (f_type_bucket (3) (v_receiver)) (Base.string_append s_24 (Base.string_append (f_type_bucket (3) (v_argument)) (Base.string_append s_24 (Base.string_append (f_type_bucket (3) (v_result)) (Base.string_append s_24 (f_row_tail_bucket (v_invocation)))))))))))
| (M.FieldPredicate (v_member, v_receiver, v_result)) ->
(Base.string_append s_13 (Base.string_append v_member (Base.string_append s_24 (Base.string_append (f_type_bucket (3) (v_receiver)) (Base.string_append s_24 (f_type_bucket (3) (v_result)))))))
| (M.UpdatePredicate (v_member, v_receiver, v_assigned, v_result, v_invocation)) ->
(Base.string_append s_25 (Base.string_append v_member (Base.string_append s_24 (Base.string_append (f_type_bucket (3) (v_receiver)) (Base.string_append s_24 (Base.string_append (f_type_bucket (3) (v_assigned)) (Base.string_append s_24 (Base.string_append (f_type_bucket (3) (v_result)) (Base.string_append s_24 (f_row_tail_bucket (v_invocation)))))))))))
| (M.OperationPredicate ((M.TypeId (v_module_name, v_declaration)), v_arguments, v_function_type)) ->
(Base.string_append s_26 (Base.string_append v_module_name (Base.string_append s_24 (Base.string_append v_declaration (Base.string_append s_24 (f_type_bucket (3) (v_function_type)))))))
| (M.TypeRepPredicate (v_represented)) ->
(Base.string_append s_27 (f_type_bucket (3) (v_represented)))
| (M.EffectRepPredicate (v_row)) ->
(Base.string_append s_23 (f_row_tail_bucket (v_row))))
and (* constraints.bend:524 *)
f_bucket_values : ((M.t_Predicate) list) option -> (M.t_Predicate) list =
fun v_found ->
(match v_found with
| None ->
[]
| (Some (v_values)) ->
v_values)
and (* constraints.bend:531 *)
f_bucket_seed : (M.t_Predicate) list -> ((M.t_Predicate) list) Base.map -> ((M.t_Predicate) list) Base.map =
fun v_seen v_buckets ->
(match v_seen with
| [] ->
v_buckets
| (v_head :: v_tail) ->
(let v_key = (f_predicate_bucket (v_head)) in
(let v_values = (f_bucket_values ((Index.f_find (v_buckets) (v_key)))) in
(f_bucket_seed (v_tail) ((Base.map_set (v_buckets) (v_key) ((v_head :: v_values))))))))
and (* constraints.bend:543 *)
f_canonical_next : bool -> M.t_Predicate -> (M.t_Predicate) list -> ((M.t_Predicate) list) Base.map -> Base.text -> (M.t_Predicate) list -> t_CanonicalBuckets =
fun v_present v_head v_seen v_buckets v_key v_values ->
(match v_present with
| true ->
(CanonicalBuckets (v_seen, v_buckets))
| false ->
(CanonicalBuckets ((v_head :: v_seen), (Base.map_set (v_buckets) (v_key) ((v_head :: v_values))))))
and (* constraints.bend:550 *)
f_canonical_indexed : (M.t_Predicate) list -> t_CanonicalBuckets -> (M.t_Predicate) list =
fun v_pending v_state ->
(match (v_pending, v_state) with
| ([], (CanonicalBuckets (v_seen, v_buckets))) ->
(Base.list_reverse (v_seen))
| ((v_head :: v_tail), (CanonicalBuckets (v_seen, v_buckets))) ->
(let v_key = (f_predicate_bucket (v_head)) in
(let v_values = (f_bucket_values ((Index.f_find (v_buckets) (v_key)))) in
(let v_next = (f_canonical_next ((f_contains (v_values) (v_head))) (v_head) (v_seen) (v_buckets) (v_key) (v_values)) in
(f_canonical_indexed (v_tail) (v_next))))))
and (* constraints.bend:560 *)
f_canonical_predicates : (M.t_Predicate) list -> (M.t_Predicate) list -> (M.t_Predicate) list =
fun v_pending v_seen ->
(f_canonical_indexed (v_pending) ((CanonicalBuckets (v_seen, (f_bucket_seed (v_seen) ((Base.map_new ())))))))
and (* constraints.bend:563 *)
f_remove_one_work : (M.t_Predicate) list -> bool -> (M.t_Predicate) list -> M.t_Predicate -> (M.t_Predicate) list =
fun v_predicates v_matched v_reversed v_wanted ->
(match (v_predicates, v_matched, v_reversed) with
| (v_remaining, true, (v_removed :: v_prefix)) ->
(Base.list_reverse_go (v_prefix) (v_remaining))
| (v_remaining, true, []) ->
v_remaining
| ([], false, v_kept) ->
(Base.list_reverse (v_kept))
| ((v_head :: v_tail), false, v_kept) ->
(f_remove_one_work (v_tail) ((f_same_predicate (v_head) (v_wanted))) ((v_head :: v_kept)) (v_wanted)))
and (* constraints.bend:574 *)
f_remove_one : (M.t_Predicate) list -> M.t_Predicate -> (M.t_Predicate) list =
fun v_predicates v_wanted ->
(f_remove_one_work (v_predicates) (false) ([]) (v_wanted))
and (* constraints.bend:577 *)
f_remove_all : (M.t_Predicate) list -> (M.t_Predicate) list -> (M.t_Predicate) list =
fun v_consumed v_predicates ->
(match v_consumed with
| [] ->
v_predicates
| (v_head :: v_tail) ->
(f_remove_all (v_tail) ((f_remove_one (v_predicates) (v_head)))))
and (* constraints.bend:584 *)
f_unplanned : (t_UsePlan) list -> (M.t_Predicate) list -> (M.t_Predicate) list =
fun v_plans v_predicates ->
(match v_plans with
| [] ->
v_predicates
| ((UsePlan (v_site, v_subject, v_ty, v_owned)) :: v_tail) ->
(f_unplanned (v_tail) ((f_remove_all (v_owned) (v_predicates)))))
and (* constraints.bend:591 *)
f_owned : M.t_Predicate -> (int) list -> (int) list -> (M.t_Diagnostic, bool) Base.result_ =
fun v_predicate v_quantified v_environment_free ->
(match (f_free (v_predicate)) with
| Fail __error -> Fail __error
| Done v_vars ->
(Done ((Base.list_is_empty ((T.f_difference (v_vars) ((T.f_union (v_quantified) (v_environment_free)))))))))
