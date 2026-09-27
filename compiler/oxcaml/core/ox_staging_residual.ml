(* Native semantic port of compiler/staging_residual.bend.

   Source SHA-256: 3e5ba1abd67e335460bd98acedbae2cad6ca1c7454c0ec102c47207ba5756a7a

   Ownership/type arguments are erased; value types are checked by OCaml.

   No Bend interpreter or generated C/JavaScript is linked. *)

open Base

module M = Ox_model

module T = Ox_types

module I = Ox_infer

module NatIndex = Ox_nat_index

module C = Ox_constraints

module Uses = Ox_use_plans

type t_Instantiated =
  | Instantiated of I.t_Inference * int
and t_Rewrite =
  | Alpha of (int) NatIndex.t_Index * (int) NatIndex.t_Index
  | Sequential of int * int
  | Identities of (int) NatIndex.t_Index
  | IdentityOffset of int
  | Resolution of T.t_Substitutions

let rec (* staging_residual.bend:24 *)
f_rewrite_type : M.t_Ty -> t_Rewrite -> (M.t_Diagnostic, M.t_Ty) Base.result_ =
fun v_ty v_rewrite ->
(match v_rewrite with
| (Alpha (v_mapping, v_identities)) ->
(T.f_rename_type (v_ty) (v_mapping))
| (Sequential (v_old, v_fresh)) ->
(T.f_replace (v_ty) (v_old) ((M.VariableTy (v_fresh))))
| (Identities (v_mapping)) ->
(Done (v_ty))
| (IdentityOffset (v_base)) ->
(Done (v_ty))
| (Resolution (v_substitutions)) ->
(T.f_resolve (v_substitutions) (v_ty)))
and (* staging_residual.bend:37 *)
f_rewrite_row : M.t_EffectRow -> t_Rewrite -> (M.t_Diagnostic, M.t_EffectRow) Base.result_ =
fun v_row v_rewrite ->
(match v_rewrite with
| (Alpha (v_mapping, v_identities)) ->
(Done ((T.f_rename_row (v_row) (v_mapping))))
| (Sequential (v_old, v_fresh)) ->
(T.f_rewrite_row (v_row) ((T.ReplaceVariable (v_old, (M.VariableTy (v_fresh))))))
| (Identities (v_mapping)) ->
(Done (v_row))
| (IdentityOffset (v_base)) ->
(Done (v_row))
| (Resolution (v_substitutions)) ->
(Done ((T.f_resolve_row (v_substitutions) (v_row)))))
and (* staging_residual.bend:50 *)
f_rewrite_invocation : (M.t_EffectRow) option -> t_Rewrite -> (M.t_Diagnostic, (M.t_EffectRow) option) Base.result_ =
fun v_invocation v_rewrite ->
(match v_invocation with
| None ->
(Done (None))
| (Some (v_row)) ->
(match (f_rewrite_row (v_row) (v_rewrite)) with
| Fail __error -> Fail __error
| Done v_next ->
(Done ((Some (v_next))))))
and (* staging_residual.bend:59 *)
f_invocation_free : (M.t_EffectRow) option -> (int) list =
fun v_invocation ->
(match v_invocation with
| None ->
[]
| (Some (v_row)) ->
(T.f_row_free (v_row)))
and (* staging_residual.bend:66 *)
f_rewrite_identity : int -> t_Rewrite -> int =
fun v_identity v_rewrite ->
(match v_rewrite with
| (Alpha (v_mapping, v_identities)) ->
(T.f_renamed_variable (v_identities) (v_identity))
| (Sequential (v_old, v_fresh)) ->
v_identity
| (Identities (v_mapping)) ->
(T.f_renamed_variable (v_mapping) (v_identity))
| (IdentityOffset (v_base)) ->
(Base.nat_add (v_base) (v_identity))
| (Resolution (v_substitutions)) ->
v_identity)
and (* staging_residual.bend:79 *)
f_rewrite_predicate : M.t_Predicate -> t_Rewrite -> (M.t_Diagnostic, M.t_Predicate) Base.result_ =
fun v_predicate v_rewrite ->
(match v_rewrite with
| (Alpha (v_mapping, v_identities)) ->
(C.f_rename (v_mapping) (v_predicate))
| (Sequential (v_old, v_fresh)) ->
(C.f_transform (v_predicate) ((C.ReplaceVariable (v_old, v_fresh))))
| (Identities (v_mapping)) ->
(Done (v_predicate))
| (IdentityOffset (v_base)) ->
(Done (v_predicate))
| (Resolution (v_substitutions)) ->
(C.f_resolve (v_substitutions) (v_predicate)))
and (* staging_residual.bend:92 *)
f_rewrite_predicates : (M.t_Predicate) list -> t_Rewrite -> (M.t_Diagnostic, (M.t_Predicate) list) Base.result_ =
fun v_predicates v_rewrite ->
(match v_predicates with
| [] ->
(Done ([]))
| (v_head :: v_tail) ->
(match (f_rewrite_predicate (v_head) (v_rewrite)) with
| Fail __error -> Fail __error
| Done v_first ->
(match (f_rewrite_predicates (v_tail) (v_rewrite)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done ((v_first :: v_rest))))))
and (* staging_residual.bend:102 *)
f_rewrite_uses : (C.t_UsePlan) list -> t_Rewrite -> (M.t_Diagnostic, (C.t_UsePlan) list) Base.result_ =
fun v_uses v_rewrite ->
(match v_uses with
| [] ->
(Done ([]))
| ((C.UsePlan (v_site, v_subject, v_ty, v_predicates)) :: v_tail) ->
(match (f_rewrite_type (v_ty) (v_rewrite)) with
| Fail __error -> Fail __error
| Done v_next_type ->
(match (f_rewrite_predicates (v_predicates) (v_rewrite)) with
| Fail __error -> Fail __error
| Done v_next_predicates ->
(match (f_rewrite_uses (v_tail) (v_rewrite)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done (((C.UsePlan ((f_rewrite_identity (v_site) (v_rewrite)), v_subject, v_next_type, v_next_predicates)) :: v_rest)))))))
and (* staging_residual.bend:113 *)
f_rewrite_reflections : (I.t_Reflection) list -> t_Rewrite -> (M.t_Diagnostic, (I.t_Reflection) list) Base.result_ =
fun v_reflections v_rewrite ->
(match v_reflections with
| [] ->
(Done ([]))
| ((I.Reflection (v_callee, v_subject, v_ty, v_predicates)) :: v_tail) ->
(match (f_rewrite_type (v_ty) (v_rewrite)) with
| Fail __error -> Fail __error
| Done v_next_type ->
(match (f_rewrite_predicates (v_predicates) (v_rewrite)) with
| Fail __error -> Fail __error
| Done v_next_predicates ->
(match (f_rewrite_reflections (v_tail) (v_rewrite)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done (((I.Reflection (v_callee, v_subject, v_next_type, v_next_predicates)) :: v_rest)))))))
and (* staging_residual.bend:124 *)
f_rewrite_types : (M.t_Ty) list -> t_Rewrite -> (M.t_Diagnostic, (M.t_Ty) list) Base.result_ =
fun v_values v_rewrite ->
(match v_values with
| [] ->
(Done ([]))
| (v_head :: v_tail) ->
(match (f_rewrite_type (v_head) (v_rewrite)) with
| Fail __error -> Fail __error
| Done v_first ->
(match (f_rewrite_types (v_tail) (v_rewrite)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done ((v_first :: v_rest))))))
and (* staging_residual.bend:134 *)
f_rewrite_coverage : I.t_Coverage -> t_Rewrite -> (M.t_Diagnostic, I.t_Coverage) Base.result_ =
fun v_value v_rewrite ->
(match v_value with
| (I.QualifiedBoundary (v_offset, v_declared, v_subject)) ->
(match (f_rewrite_predicates (v_declared) (v_rewrite)) with
| Fail __error -> Fail __error
| Done v_needs ->
(Done ((I.QualifiedBoundary (v_offset, v_needs, v_subject)))))
| (I.QualifiedNeed (v_site, v_predicate, v_subject)) ->
(match (f_rewrite_predicate (v_predicate) (v_rewrite)) with
| Fail __error -> Fail __error
| Done v_next ->
(Done ((I.QualifiedNeed ((f_rewrite_identity (v_site) (v_rewrite)), v_next, v_subject)))))
| (I.OperationNeed (v_identity, v_template, v_arguments, v_function_type, v_subject)) ->
(match (f_rewrite_types (v_arguments) (v_rewrite)) with
| Fail __error -> Fail __error
| Done v_args ->
(match (f_rewrite_type (v_function_type) (v_rewrite)) with
| Fail __error -> Fail __error
| Done v_function ->
(Done ((I.OperationNeed ((f_rewrite_identity (v_identity) (v_rewrite)), v_template, v_args, v_function, v_subject))))))
| (I.AssociatedNeed (v_identity, v_dispatch, v_member, v_templates, v_left, v_right, v_result, v_invocation, v_ambient, v_subject)) ->
(match (f_rewrite_type (v_left) (v_rewrite)) with
| Fail __error -> Fail __error
| Done v_l ->
(match (f_rewrite_type (v_right) (v_rewrite)) with
| Fail __error -> Fail __error
| Done v_r ->
(match (f_rewrite_type (v_result) (v_rewrite)) with
| Fail __error -> Fail __error
| Done v_value ->
(match (f_rewrite_invocation (v_invocation) (v_rewrite)) with
| Fail __error -> Fail __error
| Done v_selected ->
(match (f_rewrite_row (v_ambient) (v_rewrite)) with
| Fail __error -> Fail __error
| Done v_row ->
(Done ((I.AssociatedNeed ((f_rewrite_identity (v_identity) (v_rewrite)), v_dispatch, v_member, v_templates, v_l, v_r, v_value, v_selected, v_row, v_subject)))))))))
| (I.ValuePatternType (v_inferred_type, v_subject)) ->
(match (f_rewrite_type (v_inferred_type) (v_rewrite)) with
| Fail __error -> Fail __error
| Done v_ty ->
(Done ((I.ValuePatternType (v_ty, v_subject)))))
| (I.Coverage (v_inferred_types, v_patterns, v_subject)) ->
(match (f_rewrite_types (v_inferred_types) (v_rewrite)) with
| Fail __error -> Fail __error
| Done v_types ->
(Done ((I.Coverage (v_types, v_patterns, v_subject)))))
| (I.LetGeneralized (v_witness)) ->
(match (f_rewrite_type (v_witness) (v_rewrite)) with
| Fail __error -> Fail __error
| Done v_ty ->
(Done ((I.LetGeneralized (v_ty))))))
and (* staging_residual.bend:170 *)
f_rewrite_coverages : (I.t_Coverage) list -> t_Rewrite -> (M.t_Diagnostic, (I.t_Coverage) list) Base.result_ =
fun v_values v_rewrite ->
(match v_values with
| [] ->
(Done ([]))
| (v_head :: v_tail) ->
(match (f_rewrite_coverage (v_head) (v_rewrite)) with
| Fail __error -> Fail __error
| Done v_first ->
(match (f_rewrite_coverages (v_tail) (v_rewrite)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done ((v_first :: v_rest))))))
and (* staging_residual.bend:180 *)
f_rewrite_exits : (int) list -> t_Rewrite -> (int) list =
fun v_exits v_rewrite ->
(match v_exits with
| [] ->
[]
| (v_head :: v_tail) ->
((f_rewrite_identity (v_head) (v_rewrite)) :: (f_rewrite_exits (v_tail) (v_rewrite))))
and (* staging_residual.bend:187 *)
f_rewrite_inference : I.t_Inference -> t_Rewrite -> (M.t_Diagnostic, I.t_Inference) Base.result_ =
fun v_inference v_rewrite ->
(let (I.Inference (v_ty, v_coverage, v_exits, v_reflections, v_predicates, v_uses)) = v_inference in
(match (f_rewrite_type (v_ty) (v_rewrite)) with
| Fail __error -> Fail __error
| Done v_result ->
(match (f_rewrite_coverages (v_coverage) (v_rewrite)) with
| Fail __error -> Fail __error
| Done v_needs ->
(match (f_rewrite_predicates (v_predicates) (v_rewrite)) with
| Fail __error -> Fail __error
| Done v_next_predicates ->
(match (f_rewrite_uses (v_uses) (v_rewrite)) with
| Fail __error -> Fail __error
| Done v_next_uses ->
(match (f_rewrite_reflections (v_reflections) (v_rewrite)) with
| Fail __error -> Fail __error
| Done v_next_reflections ->
(Done ((I.Inference (v_result, v_needs, (f_rewrite_exits (v_exits) (v_rewrite)), v_next_reflections, v_next_predicates, v_next_uses))))))))))
and (* staging_residual.bend:200 *)
f_sequential : (int) list -> I.t_Inference -> int -> (int) NatIndex.t_Index -> (M.t_Diagnostic, t_Instantiated) Base.result_ =
fun v_variables v_inference v_next v_identities ->
(match v_variables with
| [] ->
(match (f_rewrite_inference (v_inference) ((Identities (v_identities)))) with
| Fail __error -> Fail __error
| Done v_remapped ->
(Done ((Instantiated (v_remapped, v_next)))))
| (v_old :: v_tail) ->
(match (f_rewrite_inference (v_inference) ((Sequential (v_old, v_next)))) with
| Fail __error -> Fail __error
| Done v_rewritten ->
(f_sequential (v_tail) (v_rewritten) ((Base.nat_add 1 v_next)) (v_identities))))
and (* staging_residual.bend:211 *)
f_instantiate_with_renaming : T.t_Renaming -> (int) list -> I.t_Inference -> int -> (int) NatIndex.t_Index -> (M.t_Diagnostic, t_Instantiated) Base.result_ =
fun v_renaming v_variables v_inference v_next v_identities ->
(match v_renaming with
| (T.Renaming (v_types, v_fresh_next, true)) ->
(match (f_rewrite_inference (v_inference) ((Alpha (v_types, v_identities)))) with
| Fail __error -> Fail __error
| Done v_rewritten ->
(Done ((Instantiated (v_rewritten, v_fresh_next)))))
| (T.Renaming (v_types, v_fresh_next, false)) ->
(f_sequential (v_variables) (v_inference) (v_next) (v_identities)))
and (* staging_residual.bend:220 *)
f_instantiate : I.t_Inference -> (int) list -> int -> (int) NatIndex.t_Index -> (M.t_Diagnostic, t_Instantiated) Base.result_ =
fun v_inference v_variables v_next v_identities ->
(f_instantiate_with_renaming ((T.f_renaming (v_variables) (v_next))) (v_variables) (v_inference) (v_next) (v_identities))
and (* staging_residual.bend:223 *)
f_resolve : I.t_Inference -> T.t_Substitutions -> (M.t_Diagnostic, I.t_Inference) Base.result_ =
fun v_inference v_substitutions ->
(f_rewrite_inference (v_inference) ((Resolution (v_substitutions))))
and (* staging_residual.bend:226 *)
f_offset_identities : I.t_Inference -> int -> (M.t_Diagnostic, I.t_Inference) Base.result_ =
fun v_inference v_base ->
(f_rewrite_inference (v_inference) ((IdentityOffset (v_base))))
and (* staging_residual.bend:229 *)
f_types_free : (M.t_Ty) list -> (M.t_Diagnostic, (int) list) Base.result_ =
fun v_values ->
(match v_values with
| [] ->
(Done ([]))
| (v_head :: v_tail) ->
(match (T.f_free (v_head)) with
| Fail __error -> Fail __error
| Done v_a ->
(match (f_types_free (v_tail)) with
| Fail __error -> Fail __error
| Done v_b ->
(Done ((T.f_union (v_a) (v_b)))))))
and (* staging_residual.bend:239 *)
f_coverage_free : I.t_Coverage -> (M.t_Diagnostic, (int) list) Base.result_ =
fun v_value ->
(match v_value with
| (I.QualifiedBoundary (v_offset, v_declared, v_subject)) ->
(C.f_free_list (v_declared))
| (I.QualifiedNeed (v_site, v_predicate, v_subject)) ->
(C.f_free (v_predicate))
| (I.OperationNeed (v_identity, v_template, v_arguments, v_function_type, v_subject)) ->
(match (f_types_free (v_arguments)) with
| Fail __error -> Fail __error
| Done v_a ->
(match (T.f_free (v_function_type)) with
| Fail __error -> Fail __error
| Done v_f ->
(Done ((T.f_union (v_a) (v_f))))))
| (I.AssociatedNeed (v_identity, v_dispatch, v_member, v_templates, v_left, v_right, v_result, v_invocation, v_ambient, v_subject)) ->
(match (T.f_free (v_left)) with
| Fail __error -> Fail __error
| Done v_a ->
(match (T.f_free (v_right)) with
| Fail __error -> Fail __error
| Done v_b ->
(match (T.f_free (v_result)) with
| Fail __error -> Fail __error
| Done v_c ->
(Done ((T.f_union ((f_invocation_free (v_invocation))) ((T.f_union ((T.f_row_free (v_ambient))) ((T.f_union (v_a) ((T.f_union (v_b) (v_c)))))))))))))
| (I.ValuePatternType (v_inferred_type, v_subject)) ->
(T.f_free (v_inferred_type))
| (I.Coverage (v_inferred_types, v_patterns, v_subject)) ->
(f_types_free (v_inferred_types))
| (I.LetGeneralized (v_witness)) ->
(T.f_free (v_witness)))
and (* staging_residual.bend:263 *)
f_coverages_free : (I.t_Coverage) list -> (M.t_Diagnostic, (int) list) Base.result_ =
fun v_values ->
(match v_values with
| [] ->
(Done ([]))
| (v_head :: v_tail) ->
(match (f_coverage_free (v_head)) with
| Fail __error -> Fail __error
| Done v_a ->
(match (f_coverages_free (v_tail)) with
| Fail __error -> Fail __error
| Done v_b ->
(Done ((T.f_union (v_a) (v_b)))))))
and (* staging_residual.bend:273 *)
f_reflections_free : (I.t_Reflection) list -> (M.t_Diagnostic, (int) list) Base.result_ =
fun v_reflections ->
(match v_reflections with
| [] ->
(Done ([]))
| ((I.Reflection (v_callee, v_subject, v_ty, v_predicates)) :: v_tail) ->
(match (T.f_free (v_ty)) with
| Fail __error -> Fail __error
| Done v_own_type ->
(match (C.f_free_list (v_predicates)) with
| Fail __error -> Fail __error
| Done v_own_predicates ->
(match (f_reflections_free (v_tail)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done ((T.f_union (v_own_type) ((T.f_union (v_own_predicates) (v_rest))))))))))
and (* staging_residual.bend:284 *)
f_free : I.t_Inference -> (M.t_Diagnostic, (int) list) Base.result_ =
fun v_inference ->
(let (I.Inference (v_ty, v_coverage, v_exits, v_reflections, v_predicates, v_uses)) = v_inference in
(match (T.f_free (v_ty)) with
| Fail __error -> Fail __error
| Done v_a ->
(match (f_coverages_free (v_coverage)) with
| Fail __error -> Fail __error
| Done v_b ->
(match (C.f_free_list (v_predicates)) with
| Fail __error -> Fail __error
| Done v_c ->
(match (Uses.f_free (v_uses)) with
| Fail __error -> Fail __error
| Done v_d ->
(match (f_reflections_free (v_reflections)) with
| Fail __error -> Fail __error
| Done v_e ->
(Done ((T.f_union (v_a) ((T.f_union (v_b) ((T.f_union (v_c) ((T.f_union (v_d) (v_e))))))))))))))))
