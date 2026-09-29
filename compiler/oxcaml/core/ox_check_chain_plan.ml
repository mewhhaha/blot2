(* Native semantic port of compiler/check_chain_plan.bend.

   Source SHA-256: 1ba2d6132508a5a109f14b457fed318407559cf3b343633dbfc5b4cd9e95a5c1

   Ownership/type arguments are erased; value types are checked by OCaml.

   No Bend interpreter or generated C/JavaScript is linked. *)

open Base

module M = Ox_model

module G = Ox_groups

module Index = Ox_index

type t_Job =
  | Job of int * G.t_Job
and t_Chain =
  | Chain of int * int * (t_Job) list
and t_Consumer =
  | Only of int
  | Several
and t_Parent =
  | NoParent
  | OneParent of int
  | SeveralParents
and t_Linked =
  | Linked of int * G.t_Job * t_Parent
and t_Relations =
  | Relations of t_Parent * (t_Consumer) Base.map
and t_Topology =
  | Topology of (t_Linked) list * (t_Consumer) Base.map
and t_Frontier =
  | Frontier of (t_Chain) list * (t_Chain) list

let s_0 = Base.text_of_utf8 "internal_error"

let s_1 = Base.text_of_utf8 "incremental plan omitted a required checked dependency"

let s_2 = Base.text_of_utf8 "dependency chain"

let s_3 = Base.text_of_utf8 "chain head"

let rec (* check_chain_plan.bend:30 *)
f_required : 'v. ('v) option -> Base.text -> (M.t_Diagnostic, 'v) Base.result_ =
fun v_found v_name ->
(match v_found with
| (Some (v_value)) ->
(Done (v_value))
| None ->
(Fail ((M.Diagnostic (s_0, v_name, s_1)))))
and (* check_chain_plan.bend:37 *)
f_publish : (Base.text) list -> int -> (int) Base.map -> (int) Base.map =
fun v_names v_value v_indexed ->
(match v_names with
| [] ->
v_indexed
| (v_name :: v_tail) ->
(f_publish (v_tail) (v_value) ((Base.map_set (v_indexed) (v_name) (v_value)))))
and (* check_chain_plan.bend:44 *)
f_parent_with : t_Parent -> int -> t_Parent =
fun v_previous v_position ->
(match v_previous with
| NoParent ->
(OneParent (v_position))
| (OneParent (v_prior)) ->
(Base.bool_pick ((Base.nat_is_eq (v_prior) (v_position))) ((OneParent (v_position))) (SeveralParents))
| SeveralParents ->
SeveralParents)
and (* check_chain_plan.bend:53 *)
f_consumer_with : (t_Consumer) option -> int -> t_Consumer =
fun v_previous v_position ->
(match v_previous with
| None ->
(Only (v_position))
| (Some ((Only (v_prior)))) ->
(Base.bool_pick ((Base.nat_is_eq (v_prior) (v_position))) ((Only (v_position))) (Several))
| (Some (Several)) ->
Several)
and (* check_chain_plan.bend:62 *)
f_dependencies : (Base.text) list -> int -> (int) Base.map -> t_Relations -> (M.t_Diagnostic, t_Relations) Base.result_ =
fun v_names v_position v_owners v_relations ->
(match v_names with
| [] ->
(Done (v_relations))
| (v_name :: v_tail) ->
(let (Relations (v_parent, v_consumers)) = v_relations in
(match (f_required ((Index.f_find (v_owners) (v_name))) (v_name)) with
| Fail __error -> Fail __error
| Done v_owner ->
(let v_key = (Base.nat_show (v_owner)) in
(let v_consumer = (f_consumer_with ((Index.f_find (v_consumers) (v_key))) (v_position)) in
(f_dependencies (v_tail) (v_position) (v_owners) ((Relations ((f_parent_with (v_parent) (v_owner)), (Base.map_set (v_consumers) (v_key) (v_consumer)))))))))))
and (* check_chain_plan.bend:74 *)
f_relation_parent : t_Relations -> t_Parent =
fun v_related ->
(let (Relations (v_parent, v_consumers)) = v_related in
v_parent)
and (* check_chain_plan.bend:78 *)
f_relation_consumers : t_Relations -> (t_Consumer) Base.map =
fun v_related ->
(let (Relations (v_parent, v_consumers)) = v_related in
v_consumers)
and (* check_chain_plan.bend:82 *)
f_topology : (G.t_Job) list -> int -> (int) Base.map -> (t_Consumer) Base.map -> (t_Linked) list -> (M.t_Diagnostic, t_Topology) Base.result_ =
fun v_jobs v_position v_owners v_consumers v_reversed ->
(match v_jobs with
| [] ->
(Done ((Topology ((Base.list_reverse (v_reversed)), v_consumers))))
| (v_job :: v_tail) ->
(let (G.Job (v_members, v_names, v_types)) = v_job in
(match (f_dependencies (v_names) (v_position) (v_owners) ((Relations (NoParent, v_consumers)))) with
| Fail __error -> Fail __error
| Done v_related ->
(f_topology (v_tail) ((Base.nat_add 1 v_position)) ((f_publish (v_members) (v_position) (v_owners))) ((f_relation_consumers (v_related))) (((Linked (v_position, v_job, (f_relation_parent (v_related)))) :: v_reversed))))))
and (* check_chain_plan.bend:92 *)
f_sole_consumer : (t_Consumer) option -> int -> bool =
fun v_found v_position ->
(match v_found with
| (Some ((Only (v_expected)))) ->
(Base.nat_is_eq (v_expected) (v_position))
| _ ->
false)
and (* check_chain_plan.bend:99 *)
f_continuation : t_Parent -> int -> (t_Consumer) Base.map -> (int) option =
fun v_parent v_position v_consumers ->
(match v_parent with
| (OneParent (v_owner)) ->
(Base.bool_pick ((f_sole_consumer ((Index.f_find (v_consumers) ((Base.nat_show (v_owner))))) (v_position))) ((Some (v_owner))) (None))
| _ ->
None)
and (* check_chain_plan.bend:106 *)
f_highest_level : (Base.text) list -> (int) Base.map -> int -> (M.t_Diagnostic, int) Base.result_ =
fun v_names v_levels v_maximum ->
(match v_names with
| [] ->
(Done (v_maximum))
| (v_name :: v_tail) ->
(match (f_required ((Index.f_find (v_levels) (v_name))) (v_name)) with
| Fail __error -> Fail __error
| Done v_level ->
(f_highest_level (v_tail) (v_levels) ((Base.nat_max (v_maximum) ((Base.nat_add 1 v_level)))))))
and (* check_chain_plan.bend:115 *)
f_append_job : t_Chain -> int -> G.t_Job -> t_Chain =
fun v_previous v_position v_job ->
(let (Chain (v_first, v_level, v_jobs)) = v_previous in
(Chain (v_first, v_level, ((Job (v_position, v_job)) :: v_jobs))))
and (* check_chain_plan.bend:119 *)
f_next_chain : (int) option -> int -> G.t_Job -> (int) Base.map -> (t_Chain) Base.map -> (int) Base.map -> (M.t_Diagnostic, t_Chain) Base.result_ =
fun v_parent v_position v_job v_heads v_chains v_levels ->
(match v_parent with
| (Some (v_owner)) ->
(match (f_required ((Index.f_find (v_heads) ((Base.nat_show (v_owner))))) (s_3)) with
| Fail __error -> Fail __error
| Done v_head ->
(match (f_required ((Index.f_find (v_chains) ((Base.nat_show (v_head))))) (s_2)) with
| Fail __error -> Fail __error
| Done v_previous ->
(Done ((f_append_job (v_previous) (v_position) (v_job))))))
| None ->
(let (G.Job (v_members, v_names, v_types)) = v_job in
(match (f_highest_level (v_names) (v_levels) (0)) with
| Fail __error -> Fail __error
| Done v_level ->
(Done ((Chain (v_position, v_level, [(Job (v_position, v_job))])))))))
and (* check_chain_plan.bend:132 *)
f_chain_le : t_Chain -> t_Chain -> bool =
fun v_left v_right ->
(let (Chain (v_a, v_x, v_first)) = v_left in
(let (Chain (v_b, v_y, v_second)) = v_right in
(Base.bool_or ((Base.nat_is_lt (v_x) (v_y))) ((Base.bool_and ((Base.nat_is_eq (v_x) (v_y))) ((Base.nat_is_le (v_a) (v_b))))))))
and (* check_chain_plan.bend:137 *)
f_ordered_jobs : (t_Chain) list -> (t_Chain) list =
fun v_chains ->
(match v_chains with
| [] ->
[]
| ((Chain (v_position, v_level, v_jobs)) :: v_tail) ->
((Chain (v_position, v_level, (Base.list_reverse (v_jobs)))) :: (f_ordered_jobs (v_tail))))
and (* check_chain_plan.bend:146 *)
f_chain_head : t_Chain -> int =
fun v_chain ->
(let (Chain (v_position, v_level, v_jobs)) = v_chain in
v_position)
and (* check_chain_plan.bend:150 *)
f_chain_level : t_Chain -> int =
fun v_chain ->
(let (Chain (v_position, v_level, v_jobs)) = v_chain in
v_level)
and (* check_chain_plan.bend:154 *)
f_build : (t_Linked) list -> (t_Consumer) Base.map -> (int) Base.map -> (t_Chain) Base.map -> (int) Base.map -> (M.t_Diagnostic, (t_Chain) list) Base.result_ =
fun v_jobs v_consumers v_heads v_chains v_levels ->
(match v_jobs with
| [] ->
(Done ((Base.list_sort (f_chain_le) ((f_ordered_jobs ((Base.map_values (v_chains))))))))
| ((Linked (v_position, v_job, v_parent)) :: v_tail) ->
(let (G.Job (v_members, v_names, v_types)) = v_job in
(match (f_next_chain ((f_continuation (v_parent) (v_position) (v_consumers))) (v_position) (v_job) (v_heads) (v_chains) (v_levels)) with
| Fail __error -> Fail __error
| Done v_chain ->
(let v_head = (f_chain_head (v_chain)) in
(f_build (v_tail) (v_consumers) ((Base.map_set (v_heads) ((Base.nat_show (v_position))) (v_head))) ((Base.map_set (v_chains) ((Base.nat_show (v_head))) (v_chain))) ((f_publish (v_members) ((f_chain_level (v_chain))) (v_levels))))))))
and (* check_chain_plan.bend:165 *)
f_build_topology : t_Topology -> (M.t_Diagnostic, (t_Chain) list) Base.result_ =
fun v_linked_plan ->
(let (Topology (v_linked, v_consumers)) = v_linked_plan in
(f_build (v_linked) (v_consumers) ((Base.map_new ())) ((Base.map_new ())) ((Base.map_new ()))))
and (* check_chain_plan.bend:169 *)
f_plan : (G.t_Job) list -> (M.t_Diagnostic, (t_Chain) list) Base.result_ =
fun v_jobs ->
(match (f_topology (v_jobs) (0) ((Base.map_new ())) ((Base.map_new ())) ([])) with
| Fail __error -> Fail __error
| Done v_linked_plan ->
(f_build_topology (v_linked_plan)))
and (* check_chain_plan.bend:177 *)
f_same_level : (t_Chain) list -> int -> bool =
fun v_chains v_level ->
(match v_chains with
| [] ->
false
| ((Chain (v_position, v_next, v_jobs)) :: v_tail) ->
(Base.nat_is_eq (v_level) (v_next)))
and (* check_chain_plan.bend:184 *)
f_take_frontier : (t_Chain) list -> int -> (t_Chain) list -> bool -> t_Frontier =
fun v_chains v_level v_reversed v_same ->
(match (v_chains, v_same) with
| (v_remaining, false) ->
(Frontier ((Base.list_reverse (v_reversed)), v_remaining))
| ([], true) ->
(Frontier ((Base.list_reverse (v_reversed)), []))
| ((v_chain :: v_tail), true) ->
(f_take_frontier (v_tail) (v_level) ((v_chain :: v_reversed)) ((f_same_level (v_tail) (v_level)))))
and (* check_chain_plan.bend:193 *)
f_next_frontier : (t_Chain) list -> t_Frontier =
fun v_chains ->
(match v_chains with
| [] ->
(Frontier ([], []))
| ((Chain (v_position, v_level, v_jobs)) :: v_tail) ->
(f_take_frontier (((Chain (v_position, v_level, v_jobs)) :: v_tail)) (v_level) ([]) (true)))
