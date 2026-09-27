(* Native semantic port of compiler/inference_batch.bend.

   Source SHA-256: b44645829783b3ffcc4b32261eaea5421c324a008f3d0beb762afe0f6b0f2776

   Ownership/type arguments are erased; value types are checked by OCaml.

   No Bend interpreter or generated C/JavaScript is linked. *)

open Base

type 'v t_Weighted =
  | Weighted of 'v * int
and 'v t_Partition =
  | Partition of (('v) t_Weighted) list * (('v) t_Weighted) list * int * int
and 'v t_Batch =
  | Sequential of (('v) t_Weighted) list
  | Parallel of ('v) t_Batch * ('v) t_Batch

let rec (* inference_batch.bend:13 *)
f_total_cost : 'v. (('v) t_Weighted) list -> int -> int =
fun v_tasks v_total ->
(match v_tasks with
| [] ->
v_total
| ((Weighted (v_value, v_cost)) :: v_tail) ->
(f_total_cost (v_tail) ((Base.nat_add (v_total) (v_cost)))))
and (* inference_batch.bend:20 *)
f_cut_before : 'v. (('v) t_Weighted) list -> int -> int -> bool =
fun v_tasks v_left_cost v_target ->
(match v_tasks with
| [] ->
true
| ((Weighted (v_value, v_cost)) :: v_tail) ->
(let v_after = (Base.nat_add (v_left_cost) (v_cost)) in
(Base.bool_and ((Base.nat_is_gt (v_left_cost) (0))) ((Base.bool_or ((Base.nat_is_ge (v_left_cost) (v_target))) ((Base.bool_and ((Base.nat_is_ge (v_after) (v_target))) ((Base.nat_is_le ((Base.nat_sub (v_target) (v_left_cost))) ((Base.nat_sub (v_after) (v_target))))))))))))
and (* inference_batch.bend:28 *)
f_partition : 'v. (('v) t_Weighted) list -> (('v) t_Weighted) list -> int -> int -> int -> bool -> ('v) t_Partition =
fun v_tasks v_reversed v_left_cost v_total v_target v_reached ->
(match (v_tasks, v_reached) with
| ([], _) ->
(Partition ((Base.list_reverse (v_reversed)), [], v_left_cost, 0))
| (v_remaining, true) ->
(Partition ((Base.list_reverse (v_reversed)), v_remaining, v_left_cost, (Base.nat_sub (v_total) (v_left_cost))))
| (((Weighted (v_value, v_cost)) :: v_tail), false) ->
(let v_next = (Base.nat_add (v_left_cost) (v_cost)) in
(f_partition (v_tail) (((Weighted (v_value, v_cost)) :: v_reversed)) (v_next) (v_total) (v_target) ((f_cut_before (v_tail) (v_next) (v_target))))))
and (* inference_batch.bend:38 *)
f_forkable : 'v. ('v) t_Partition -> int -> bool =
fun v_parts v_grain ->
(let (Partition (v_left, v_right, v_left_cost, v_right_cost)) = v_parts in
(Base.bool_and ((Base.nat_is_gt (v_left_cost) (0))) ((Base.bool_and ((Base.nat_is_gt (v_right_cost) (0))) ((Base.bool_and ((Base.nat_is_ge (v_left_cost) (v_grain))) ((Base.nat_is_ge (v_right_cost) (v_grain)))))))))
and (* inference_batch.bend:42 *)
f_batches : 'v. int -> ('v) t_Partition -> int -> bool -> ('v) t_Batch =
fun v_fuel v_parts v_grain v_parallel ->
(match (v_fuel, v_parts, v_parallel) with
| (__nat_1, (Partition (v_left, v_right, v_left_cost, v_right_cost)), true) when __nat_1 >= 1 ->
(let v_rest = (__nat_1 - 1) in
(let v_left_parts = (f_partition (v_left) ([]) (0) (v_left_cost) ((Base.nat_div (v_left_cost) (2))) (false)) in
(let v_right_parts = (f_partition (v_right) ([]) (0) (v_right_cost) ((Base.nat_div (v_right_cost) (2))) (false)) in
(let v_a = (f_batches (v_rest) (v_left_parts) (v_grain) ((f_forkable (v_left_parts) (v_grain)))) in
(let v_b = (f_batches (v_rest) (v_right_parts) (v_grain) ((f_forkable (v_right_parts) (v_grain)))) in
(Parallel (v_a, v_b)))))))
| (_, (Partition (v_left, v_right, v_left_cost, v_right_cost)), _) ->
(Sequential ((Base.list_reverse_go ((Base.list_reverse (v_left))) (v_right)))))
and (* inference_batch.bend:53 *)
f_plan : 'v. (('v) t_Weighted) list -> int -> ('v) t_Batch =
fun v_tasks v_grain ->
(let v_total = (f_total_cost (v_tasks) (0)) in
(let v_parts = (f_partition (v_tasks) ([]) (0) (v_total) ((Base.nat_div (v_total) (2))) (false)) in
(f_batches ((Base.list_length (v_tasks))) (v_parts) (v_grain) ((f_forkable (v_parts) (v_grain))))))
and (* inference_batch.bend:58 *)
f_run_leaf : 'c 'r 'v. ('v -> ('c -> 'r)) -> (('v) t_Weighted) list -> 'c -> ('r) list -> ('r) list =
fun v_run v_tasks v_context v_reversed ->
(match v_tasks with
| [] ->
(Base.list_reverse (v_reversed))
| ((Weighted (v_value, v_cost)) :: v_tail) ->
(f_run_leaf (v_run) (v_tail) (v_context) (((v_run (v_value) (v_context)) :: v_reversed))))
and (* inference_batch.bend:65 *)
f_join : 'r. ('r) list -> ('r) list -> ('r) list =
fun v_left v_right ->
(Base.list_reverse_go ((Base.list_reverse (v_left))) (v_right))
and (* inference_batch.bend:68 *)
f_execute : 'c 'r 'v. ('v -> ('c -> 'r)) -> ('v) t_Batch -> 'c -> ('r) list =
fun v_run v_batch v_context ->
(match v_batch with
| (Sequential (v_tasks)) ->
(f_run_leaf (v_run) (v_tasks) (v_context) ([]))
| (Parallel ((Parallel ((Parallel (v_a, v_b)), (Parallel (v_c, v_d)))), (Parallel ((Parallel (v_e, v_f)), (Parallel (v_g, v_h)))))) ->
(let v_ra = (f_execute (v_run) (v_a) (v_context)) in
(let v_rb = (f_execute (v_run) (v_b) (v_context)) in
(let v_rc = (f_execute (v_run) (v_c) (v_context)) in
(let v_rd = (f_execute (v_run) (v_d) (v_context)) in
(let v_re = (f_execute (v_run) (v_e) (v_context)) in
(let v_rf = (f_execute (v_run) (v_f) (v_context)) in
(let v_rg = (f_execute (v_run) (v_g) (v_context)) in
(let v_rh = (f_execute (v_run) (v_h) (v_context)) in
(f_join ((f_join ((f_join (v_ra) (v_rb))) ((f_join (v_rc) (v_rd))))) ((f_join ((f_join (v_re) (v_rf))) ((f_join (v_rg) (v_rh))))))))))))))
| (Parallel ((Parallel (v_a, v_b)), (Parallel (v_c, v_d)))) ->
(let v_ra = (f_execute (v_run) (v_a) (v_context)) in
(let v_rb = (f_execute (v_run) (v_b) (v_context)) in
(let v_rc = (f_execute (v_run) (v_c) (v_context)) in
(let v_rd = (f_execute (v_run) (v_d) (v_context)) in
(f_join ((f_join (v_ra) (v_rb))) ((f_join (v_rc) (v_rd))))))))
| (Parallel (v_left, v_right)) ->
(let v_a = (f_execute (v_run) (v_left) (v_context)) in
(let v_b = (f_execute (v_run) (v_right) (v_context)) in
(f_join (v_a) (v_b)))))
