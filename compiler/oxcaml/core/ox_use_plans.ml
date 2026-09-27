(* Native semantic port of compiler/use_plans.bend.

   Source SHA-256: 81240a0f0c16968a720dbaeb1adb9b50669398fadbdb84f9985cd10376febe09

   Ownership/type arguments are erased; value types are checked by OCaml.

   No Bend interpreter or generated C/JavaScript is linked. *)

open Base

module M = Ox_model

module T = Ox_types

module C = Ox_constraints

let rec (* use_plans.bend:8 *)
f_transform : C.t_UsePlan -> C.t_Transform -> int -> (M.t_Diagnostic, C.t_UsePlan) Base.result_ =
fun v_plan v_change v_site ->
(let (C.UsePlan (v_old_site, v_subject, v_ty, v_predicates)) = v_plan in
(match (C.f_transform_type (v_ty) (v_change)) with
| Fail __error -> Fail __error
| Done v_changed_type ->
(match (C.f_transform_list (v_predicates) (v_change)) with
| Fail __error -> Fail __error
| Done v_changed_predicates ->
(Done ((C.UsePlan (v_site, v_subject, v_changed_type, v_changed_predicates)))))))
and (* use_plans.bend:15 *)
f_transform_types : (C.t_UsePlan) list -> C.t_Transform -> (M.t_Diagnostic, (C.t_UsePlan) list) Base.result_ =
fun v_plans v_change ->
(match v_plans with
| [] ->
(Done ([]))
| ((C.UsePlan (v_site, v_subject, v_ty, v_predicates)) :: v_tail) ->
(match (f_transform ((C.UsePlan (v_site, v_subject, v_ty, v_predicates))) (v_change) (v_site)) with
| Fail __error -> Fail __error
| Done v_first ->
(match (f_transform_types (v_tail) (v_change)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done ((v_first :: v_rest))))))
and (* use_plans.bend:25 *)
f_free : (C.t_UsePlan) list -> (M.t_Diagnostic, (int) list) Base.result_ =
fun v_plans ->
(match v_plans with
| [] ->
(Done ([]))
| ((C.UsePlan (v_site, v_subject, v_ty, v_predicates)) :: v_tail) ->
(match (T.f_free (v_ty)) with
| Fail __error -> Fail __error
| Done v_type_vars ->
(match (C.f_free_list (v_predicates)) with
| Fail __error -> Fail __error
| Done v_predicate_vars ->
(match (f_free (v_tail)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done ((T.f_union (v_type_vars) ((T.f_union (v_predicate_vars) (v_rest))))))))))
