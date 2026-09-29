(* Native semantic port of compiler/check_regions.bend.

   Source SHA-256: 8cb45bcc73bb178dc2b4d599c78e0ce63508105b2707ae975c9f3660e8acd32f

   Ownership/type arguments are erased; value types are checked by OCaml.

   No Bend interpreter or generated C/JavaScript is linked. *)

open Base

module M = Ox_model

module G = Ox_groups

module Chains = Ox_check_chain_plan

module Index = Ox_index

type t_Region =
  | Region of (Chains.t_Chain) list
and t_Link =
  | Root of int
  | Parent of Base.text
and t_Resolved =
  | Resolved of Base.text * int * (t_Link) Base.map
and t_RootedPlan =
  | RootedPlan of (Chains.t_Chain) list * (t_Region) list

let s_0 = Base.text_of_utf8 "internal_error"

let s_1 = Base.text_of_utf8 "check_regions"

let s_2 = Base.text_of_utf8 "region parent chain exceeds its chain count"

let s_3 = Base.text_of_utf8 "incremental plan omitted a required checked dependency"

let rec (* check_regions.bend:17 *)
f_root_key : t_Resolved -> Base.text =
fun v_root ->
(let (Resolved (v_key, v_rank, v_forest)) = v_root in
v_key)
and (* check_regions.bend:21 *)
f_root_rank : t_Resolved -> int =
fun v_root ->
(let (Resolved (v_key, v_rank, v_forest)) = v_root in
v_rank)
and (* check_regions.bend:25 *)
f_root_forest : t_Resolved -> (t_Link) Base.map =
fun v_root ->
(let (Resolved (v_key, v_rank, v_forest)) = v_root in
v_forest)
and (* check_regions.bend:29 *)
f_compressed : Base.text -> Base.text -> int -> (t_Link) Base.map -> bool -> t_Resolved =
fun v_key v_root v_rank v_forest v_same ->
(match v_same with
| true ->
(Resolved (v_root, v_rank, v_forest))
| false ->
(Resolved (v_root, v_rank, (Base.map_set (v_forest) (v_key) ((Parent (v_root)))))))
and (* check_regions.bend:36 *)
f_compress : Base.text -> Base.text -> t_Resolved -> t_Resolved =
fun v_key v_parent v_resolved ->
(let (Resolved (v_root, v_rank, v_forest)) = v_resolved in
(f_compressed (v_key) (v_root) (v_rank) (v_forest) ((M.f_name_equal (v_parent) (v_root)))))
and (* check_regions.bend:40 *)
f_resolve : int -> Base.text -> (t_Link) Base.map -> (t_Link) option -> (M.t_Diagnostic, t_Resolved) Base.result_ =
fun v_fuel v_key v_forest v_found ->
(match (v_fuel, v_found) with
| (_, None) ->
(Done ((Resolved (v_key, 0, v_forest))))
| (_, (Some ((Root (v_rank))))) ->
(Done ((Resolved (v_key, v_rank, v_forest))))
| (0, (Some ((Parent (v_parent))))) ->
(Fail ((M.Diagnostic (s_0, s_1, s_2))))
| (__nat_1, (Some ((Parent (v_parent))))) when __nat_1 >= 1 ->
(let v_rest = (__nat_1 - 1) in
(match (f_resolve (v_rest) (v_parent) (v_forest) ((Index.f_find (v_forest) (v_parent)))) with
| Fail __error -> Fail __error
| Done v_root ->
(Done ((f_compress (v_key) (v_parent) (v_root)))))))
and (* check_regions.bend:53 *)
f_join_roots : Base.text -> int -> Base.text -> int -> (t_Link) Base.map -> bool -> Base.cmp -> (t_Link) Base.map =
fun v_left v_left_rank v_right v_right_rank v_forest v_same v_order ->
(match (v_same, v_order) with
| (true, _) ->
v_forest
| (false, LT) ->
(Base.map_set (v_forest) (v_left) ((Parent (v_right))))
| (false, GT) ->
(Base.map_set (v_forest) (v_right) ((Parent (v_left))))
| (false, EQ) ->
(Base.map_set ((Base.map_set (v_forest) (v_right) ((Parent (v_left))))) (v_left) ((Root ((Base.nat_add 1 v_left_rank))))))
and (* check_regions.bend:66 *)
f_unite_distinct : int -> Base.text -> Base.text -> (t_Link) Base.map -> bool -> (M.t_Diagnostic, (t_Link) Base.map) Base.result_ =
fun v_fuel v_left v_right v_forest v_same ->
(match v_same with
| true ->
(Done (v_forest))
| false ->
(match (f_resolve (v_fuel) (v_left) (v_forest) ((Index.f_find (v_forest) (v_left)))) with
| Fail __error -> Fail __error
| Done v_a ->
(let v_next = (f_root_forest (v_a)) in
(match (f_resolve (v_fuel) (v_right) (v_next) ((Index.f_find (v_next) (v_right)))) with
| Fail __error -> Fail __error
| Done v_b ->
(Done ((f_join_roots ((f_root_key (v_a))) ((f_root_rank (v_a))) ((f_root_key (v_b))) ((f_root_rank (v_b))) ((f_root_forest (v_b))) ((M.f_name_equal ((f_root_key (v_a))) ((f_root_key (v_b))))) ((Base.nat_cmp ((f_root_rank (v_a))) ((f_root_rank (v_b))))))))))))
and (* check_regions.bend:77 *)
f_unite : int -> Base.text -> Base.text -> (t_Link) Base.map -> (M.t_Diagnostic, (t_Link) Base.map) Base.result_ =
fun v_fuel v_left v_right v_forest ->
(f_unite_distinct (v_fuel) (v_left) (v_right) (v_forest) ((M.f_name_equal (v_left) (v_right))))
and (* check_regions.bend:80 *)
f_job_owners : (Chains.t_Job) list -> int -> (int) Base.map -> (int) Base.map =
fun v_jobs v_head v_owners ->
(match v_jobs with
| [] ->
v_owners
| ((Chains.Job (v_position, (G.Job (v_members, v_dependencies, v_types)))) :: v_tail) ->
(f_job_owners (v_tail) (v_head) ((Chains.f_publish (v_members) (v_head) (v_owners)))))
and (* check_regions.bend:87 *)
f_chain_owners : (Chains.t_Chain) list -> (int) Base.map -> (int) Base.map =
fun v_chains v_owners ->
(match v_chains with
| [] ->
v_owners
| ((Chains.Chain (v_position, v_level, v_jobs)) :: v_tail) ->
(f_chain_owners (v_tail) ((f_job_owners (v_jobs) (v_position) (v_owners)))))
and (* check_regions.bend:94 *)
f_link_dependency : (int) option -> (int) option -> int -> Base.text -> Base.text -> (t_Link) Base.map -> (M.t_Diagnostic, (t_Link) Base.map) Base.result_ =
fun v_owner v_settled v_fuel v_head v_name v_forest ->
(match (v_owner, v_settled) with
| ((Some (v_position)), _) ->
(f_unite (v_fuel) (v_head) ((Base.nat_show (v_position))) (v_forest))
| (None, (Some (v_position))) ->
(Done (v_forest))
| (None, None) ->
(Fail ((M.Diagnostic (s_0, v_name, s_3)))))
and (* check_regions.bend:103 *)
f_dependencies : (Base.text) list -> int -> Base.text -> (int) Base.map -> (int) Base.map -> (t_Link) Base.map -> (M.t_Diagnostic, (t_Link) Base.map) Base.result_ =
fun v_names v_fuel v_head v_owners v_settled v_forest ->
(match v_names with
| [] ->
(Done (v_forest))
| (v_name :: v_tail) ->
(match (f_link_dependency ((Index.f_find (v_owners) (v_name))) ((Index.f_find (v_settled) (v_name))) (v_fuel) (v_head) (v_name) (v_forest)) with
| Fail __error -> Fail __error
| Done v_next ->
(f_dependencies (v_tail) (v_fuel) (v_head) (v_owners) (v_settled) (v_next))))
and (* check_regions.bend:112 *)
f_job_links : (Chains.t_Job) list -> int -> Base.text -> (int) Base.map -> (int) Base.map -> (t_Link) Base.map -> (M.t_Diagnostic, (t_Link) Base.map) Base.result_ =
fun v_jobs v_fuel v_head v_owners v_settled v_forest ->
(match v_jobs with
| [] ->
(Done (v_forest))
| ((Chains.Job (v_position, (G.Job (v_members, v_names, v_types)))) :: v_tail) ->
(match (f_dependencies (v_names) (v_fuel) (v_head) (v_owners) (v_settled) (v_forest)) with
| Fail __error -> Fail __error
| Done v_next ->
(f_job_links (v_tail) (v_fuel) (v_head) (v_owners) (v_settled) (v_next))))
and (* check_regions.bend:121 *)
f_chain_links : (Chains.t_Chain) list -> int -> (int) Base.map -> (int) Base.map -> (t_Link) Base.map -> (M.t_Diagnostic, (t_Link) Base.map) Base.result_ =
fun v_chains v_fuel v_owners v_settled v_forest ->
(match v_chains with
| [] ->
(Done (v_forest))
| ((Chains.Chain (v_position, v_level, v_jobs)) :: v_tail) ->
(match (f_job_links (v_jobs) (v_fuel) ((Base.nat_show (v_position))) (v_owners) (v_settled) (v_forest)) with
| Fail __error -> Fail __error
| Done v_next ->
(f_chain_links (v_tail) (v_fuel) (v_owners) (v_settled) (v_next))))
and (* check_regions.bend:130 *)
f_ordered_regions : ((Chains.t_Chain) list) list -> (t_Region) list =
fun v_groups ->
(match v_groups with
| [] ->
[]
| (v_chains :: v_tail) ->
((Region ((Base.list_reverse (v_chains)))) :: (f_ordered_regions (v_tail))))
and (* check_regions.bend:137 *)
f_collect : (Chains.t_Chain) list -> int -> (t_Link) Base.map -> ((Chains.t_Chain) list) Base.map -> (M.t_Diagnostic, (t_Region) list) Base.result_ =
fun v_chains v_fuel v_forest v_groups ->
(match v_chains with
| [] ->
(Done ((f_ordered_regions ((Base.map_values (v_groups))))))
| (v_chain :: v_tail) ->
(let v_key = (Base.nat_show ((Chains.f_chain_head (v_chain)))) in
(match (f_resolve (v_fuel) (v_key) (v_forest) ((Index.f_find (v_forest) (v_key)))) with
| Fail __error -> Fail __error
| Done v_resolved ->
(let v_root = (f_root_key (v_resolved)) in
(let v_members = (Index.f_get (v_groups) (v_root) ([])) in
(f_collect (v_tail) (v_fuel) ((f_root_forest (v_resolved))) ((Base.map_set (v_groups) (v_root) ((v_chain :: v_members))))))))))
and (* check_regions.bend:149 *)
f_partition_remaining : (Chains.t_Chain) list -> (int) Base.map -> (M.t_Diagnostic, (t_Region) list) Base.result_ =
fun v_chains v_settled ->
(let v_fuel = (Base.list_length (v_chains)) in
(match (f_chain_links (v_chains) (v_fuel) ((f_chain_owners (v_chains) ((Base.map_new ())))) (v_settled) ((Base.map_new ()))) with
| Fail __error -> Fail __error
| Done v_forest ->
(f_collect (v_chains) (v_fuel) (v_forest) ((Base.map_new ())))))
and (* check_regions.bend:155 *)
f_partition : (Chains.t_Chain) list -> (M.t_Diagnostic, (t_Region) list) Base.result_ =
fun v_chains ->
(f_partition_remaining (v_chains) ((Base.map_new ())))
and (* check_regions.bend:160 *)
f_plan_frontier : (Chains.t_Chain) list -> Chains.t_Frontier -> (M.t_Diagnostic, (t_Region) list) Base.result_ =
fun v_chains v_frontier ->
(match v_frontier with
| (Chains.Frontier (v_ready, [])) ->
(Done ([(Region (v_chains))]))
| (Chains.Frontier ((v_root :: []), v_pending)) ->
(Done ([(Region (v_chains))]))
| _ ->
(f_partition (v_chains)))
and (* check_regions.bend:169 *)
f_plan : (Chains.t_Chain) list -> (M.t_Diagnostic, (t_Region) list) Base.result_ =
fun v_chains ->
(f_plan_frontier (v_chains) ((Chains.f_next_frontier (v_chains))))
and (* check_regions.bend:175 *)
f_prefix : t_RootedPlan -> (Chains.t_Chain) list =
fun v_plan ->
(let (RootedPlan (v_chains, v_regions)) = v_plan in
v_chains)
and (* check_regions.bend:179 *)
f_branches : t_RootedPlan -> (t_Region) list =
fun v_plan ->
(let (RootedPlan (v_chains, v_regions)) = v_plan in
v_regions)
and (* check_regions.bend:186 *)
f_release_frontier : (Chains.t_Chain) list -> (Chains.t_Chain) list -> (t_Region) list -> Chains.t_Frontier -> (M.t_Diagnostic, t_RootedPlan) Base.result_ =
fun v_ready v_pending v_regions v_frontier ->
(match (v_regions, v_frontier) with
| (_, (Chains.Frontier (v_last, []))) ->
(Done ((RootedPlan ([], v_regions))))
| (((Region (v_chains)) :: []), _) ->
(match (f_partition_remaining (v_pending) ((f_chain_owners (v_ready) ((Base.map_new ()))))) with
| Fail __error -> Fail __error
| Done v_released ->
(Done ((RootedPlan (v_ready, v_released)))))
| (_, _) ->
(Done ((RootedPlan ([], v_regions)))))
and (* check_regions.bend:199 *)
f_rooted_frontier : (Chains.t_Chain) list -> Chains.t_Frontier -> (M.t_Diagnostic, t_RootedPlan) Base.result_ =
fun v_chains v_frontier ->
(match v_frontier with
| (Chains.Frontier ((v_root :: []), (v_head :: v_tail))) ->
(match (f_partition_remaining ((v_head :: v_tail)) ((f_chain_owners ([v_root]) ((Base.map_new ()))))) with
| Fail __error -> Fail __error
| Done v_regions ->
(Done ((RootedPlan ([v_root], v_regions)))))
| (Chains.Frontier ((v_first :: (v_second :: v_rest)), (v_head :: v_tail))) ->
(match (f_partition (v_chains)) with
| Fail __error -> Fail __error
| Done v_regions ->
(f_release_frontier ((v_first :: (v_second :: v_rest))) ((v_head :: v_tail)) (v_regions) ((Chains.f_next_frontier ((v_head :: v_tail))))))
| _ ->
(match (f_plan (v_chains)) with
| Fail __error -> Fail __error
| Done v_regions ->
(Done ((RootedPlan ([], v_regions))))))
and (* check_regions.bend:214 *)
f_rooted_plan : (Chains.t_Chain) list -> (M.t_Diagnostic, t_RootedPlan) Base.result_ =
fun v_chains ->
(f_rooted_frontier (v_chains) ((Chains.f_next_frontier (v_chains))))
