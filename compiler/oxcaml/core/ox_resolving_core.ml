(* Native semantic port of compiler/resolving_core.bend.

   Source SHA-256: 30b25483b68a725bc0c6a3de55a7c2d556e0592bbe208285e13d9537ebfd1571

   Ownership/type arguments are erased; value types are checked by OCaml.

   No Bend interpreter or generated C/JavaScript is linked. *)

open Base

module M = Ox_model

module I = Ox_infer

module G = Ox_groups

module Core = Ox_checked_core

module Compare = Ox_core_compare

module D = Ox_dependency

module Index = Ox_index

type t_Witness =
  | Witness of Core.t_Certificate * (G.t_GroupNeeds) list
and t_Pairing =
  | Unclaimed
  | Claimed of G.t_GroupNeeds
  | Invalid

let rec (* resolving_core.bend:21 *)
f_member_names : (I.t_Binding) list -> (Base.text) list =
fun v_members ->
(match v_members with
| [] ->
[]
| ((I.Binding (v_name, v_ty, v_variables, v_predicates)) :: v_tail) ->
(v_name :: (f_member_names (v_tail))))
and (* resolving_core.bend:28 *)
f_need_names : (G.t_Resolution) list -> (Base.text) list =
fun v_needs ->
(match v_needs with
| [] ->
[]
| ((G.Resolution (v_declaration, v_identity, v_dispatch, v_member, v_templates, v_left, v_right, v_result, v_invocation, v_ambient)) :: v_tail) ->
(v_declaration :: (f_need_names (v_tail))))
and (* resolving_core.bend:35 *)
f_contains_all : (Base.text) list -> (Base.text) list -> bool =
fun v_names v_available ->
(match v_names with
| [] ->
true
| (v_head :: v_tail) ->
(Base.bool_and ((D.f_contains (v_available) (v_head))) ((f_contains_all (v_tail) (v_available)))))
and (* resolving_core.bend:42 *)
f_overlaps : (Base.text) list -> (Base.text) list -> bool =
fun v_names v_available ->
(match v_names with
| [] ->
false
| (v_head :: v_tail) ->
(Base.bool_or ((D.f_contains (v_available) (v_head))) ((f_overlaps (v_tail) (v_available)))))
and (* resolving_core.bend:49 *)
f_pair_claim : bool -> bool -> G.t_GroupNeeds -> t_Pairing -> t_Pairing =
fun v_overlap v_exact v_need v_prior ->
(match (v_overlap, v_exact, v_prior) with
| (false, _, v_prior) ->
v_prior
| (true, true, Unclaimed) ->
(Claimed (v_need))
| (true, _, _) ->
Invalid)
and (* resolving_core.bend:58 *)
f_pair_needs : (G.t_GroupNeeds) list -> (Base.text) list -> t_Pairing -> t_Pairing =
fun v_needs v_names v_prior ->
(match v_needs with
| [] ->
v_prior
| (v_need :: v_tail) ->
(let (G.GroupNeeds (v_next, v_requests, v_members, v_generalized)) = v_need in
(let v_claimed = (f_member_names (v_members)) in
(let v_requested = (f_need_names (v_requests)) in
(let v_overlap = (Base.bool_or ((f_overlaps (v_claimed) (v_names))) ((f_overlaps (v_requested) (v_names)))) in
(let v_exact = (Base.bool_and ((f_contains_all (v_names) (v_claimed))) ((Base.bool_and ((f_contains_all (v_claimed) (v_names))) ((f_contains_all (v_requested) (v_names)))))) in
(f_pair_needs (v_tail) (v_names) ((f_pair_claim (v_overlap) (v_exact) (v_need) (v_prior))))))))))
and (* resolving_core.bend:70 *)
f_paired : t_Pairing -> Core.t_Certificate -> (t_Witness) option =
fun v_pairing v_certificate ->
(match v_pairing with
| Invalid ->
None
| Unclaimed ->
(Some ((Witness (v_certificate, []))))
| (Claimed (v_need)) ->
(Some ((Witness (v_certificate, [v_need])))))
and (* resolving_core.bend:79 *)
f_pair : Core.t_Certificate -> (G.t_GroupNeeds) list -> (t_Witness) option =
fun v_certificate v_needs ->
(let (Core.Certificate (v_module, v_checked, v_imports)) = v_certificate in
(f_paired ((f_pair_needs (v_needs) ((Core.f_names (v_module))) (Unclaimed))) (v_certificate)))
and (* resolving_core.bend:83 *)
f_add_names : (Base.text) list -> t_Witness -> ((t_Witness) list) Base.map -> ((t_Witness) list) Base.map =
fun v_names v_witness v_indexed ->
(match v_names with
| [] ->
v_indexed
| (v_name :: v_tail) ->
(let v_previous = (Index.f_get (v_indexed) (v_name) ([])) in
(f_add_names (v_tail) (v_witness) ((Base.map_set (v_indexed) (v_name) ((v_witness :: v_previous)))))))
and (* resolving_core.bend:91 *)
f_add : (t_Witness) option -> ((t_Witness) list) Base.map -> ((t_Witness) list) Base.map =
fun v_found v_indexed ->
(match v_found with
| None ->
v_indexed
| (Some (v_witness)) ->
(let (Witness ((Core.Certificate (v_module, v_checked, v_imports)), v_needs)) = v_witness in
(f_add_names ((Core.f_names (v_module))) (v_witness) (v_indexed))))
and (* resolving_core.bend:101 *)
f_add_need : (Base.text) list -> G.t_GroupNeeds -> ((G.t_GroupNeeds) list) Base.map -> ((G.t_GroupNeeds) list) Base.map =
fun v_names v_need v_indexed ->
(match v_names with
| [] ->
v_indexed
| (v_name :: v_tail) ->
(let v_previous = (Index.f_get (v_indexed) (v_name) ([])) in
(f_add_need (v_tail) (v_need) ((Base.map_set (v_indexed) (v_name) ((v_need :: v_previous)))))))
and (* resolving_core.bend:109 *)
f_need_index : (G.t_GroupNeeds) list -> ((G.t_GroupNeeds) list) Base.map -> ((G.t_GroupNeeds) list) Base.map =
fun v_needs v_indexed ->
(match v_needs with
| [] ->
v_indexed
| (v_need :: v_tail) ->
(let (G.GroupNeeds (v_next, v_requests, v_members, v_generalized)) = v_need in
(let v_names = (Base.set_to_list ((Base.set_from_list ((Base.list_append ((f_member_names (v_members))) ((f_need_names (v_requests)))))))) in
(f_need_index (v_tail) ((f_add_need (v_names) (v_need) (v_indexed)))))))
and (* resolving_core.bend:121 *)
f_for_members : (Base.text) list -> ((G.t_GroupNeeds) list) Base.map -> (G.t_GroupNeeds) list -> (G.t_GroupNeeds) list =
fun v_names v_indexed v_all ->
(match v_names with
| (v_name :: []) ->
(Index.f_get (v_indexed) (v_name) ([]))
| _ ->
v_all)
and (* resolving_core.bend:128 *)
f_index_certificates : (Core.t_Certificate) list -> (G.t_GroupNeeds) list -> ((G.t_GroupNeeds) list) Base.map -> ((t_Witness) list) Base.map -> ((t_Witness) list) Base.map =
fun v_certificates v_needs v_by_name v_indexed ->
(match v_certificates with
| [] ->
v_indexed
| (v_certificate :: v_tail) ->
(let (Core.Certificate (v_module, v_checked, v_imports)) = v_certificate in
(let v_relevant = (f_for_members ((Core.f_names (v_module))) (v_by_name) (v_needs)) in
(f_index_certificates (v_tail) (v_needs) (v_by_name) ((f_add ((f_pair (v_certificate) (v_relevant))) (v_indexed)))))))
and (* resolving_core.bend:137 *)
f_index : (Core.t_Certificate) list -> (G.t_GroupNeeds) list -> ((t_Witness) list) Base.map -> ((t_Witness) list) Base.map =
fun v_certificates v_needs v_indexed ->
(f_index_certificates (v_certificates) (v_needs) ((f_need_index (v_needs) ((Base.map_new ())))) (v_indexed))
and (* resolving_core.bend:140 *)
f_matches : t_Witness -> M.t_Module -> (G.t_Interface) list -> (G.t_Resolving) option =
fun v_witness v_subset v_imports ->
(let (Witness ((Core.Certificate (v_original, v_checked, v_dependencies)), v_needs)) = v_witness in
(Base.bool_pick ((Base.bool_and ((Compare.f_same_module (v_original) (v_subset))) ((Core.f_same_imports (v_dependencies) (v_imports))))) ((Some ((G.Resolving (v_checked, v_needs))))) (None)))
and (* resolving_core.bend:146 *)
f_candidates : (t_Witness) list -> M.t_Module -> (G.t_Interface) list -> (G.t_Resolving) option -> (G.t_Resolving) option =
fun v_values v_subset v_imports v_found ->
(match (v_values, v_found) with
| (_, (Some (v_resolved))) ->
(Some (v_resolved))
| ([], None) ->
None
| ((v_head :: v_tail), None) ->
(f_candidates (v_tail) (v_subset) (v_imports) ((f_matches (v_head) (v_subset) (v_imports)))))
and (* resolving_core.bend:155 *)
f_lookup : ((t_Witness) list) Base.map -> G.t_Job -> M.t_Module -> (G.t_Interface) list -> (G.t_Resolving) option =
fun v_indexed v_job v_subset v_imports ->
(let (G.Job (v_members, v_dependencies, v_types)) = v_job in
(match v_members with
| [] ->
None
| (v_name :: v_tail) ->
(f_candidates ((Index.f_get (v_indexed) (v_name) ([]))) (v_subset) (v_imports) (None))))
