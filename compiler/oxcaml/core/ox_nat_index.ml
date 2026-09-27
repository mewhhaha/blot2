(* Native semantic port of compiler/nat_index.bend.

   Source SHA-256: 3b72ca5cc0af07b00f1ed5c056a126f396095a04bf0d4f74ea588eb8063d0d6c

   Ownership/type arguments are erased; value types are checked by OCaml.

   No Bend interpreter or generated C/JavaScript is linked. *)

open Base

type 'v t_Index =
  | Empty
  | Leaf of int * 'v
  | Branch of int * int * ('v) t_Index * ('v) t_Index
and t_Difference =
  | Halve of int * int * int
  | Decide of int * int * int * bool
and 'v t_Insert =
  | Enter of ('v) t_Index * int * 'v
  | CompareLeaf of int * 'v * int * 'v * bool
  | CompareBranch of int * int * ('v) t_Index * ('v) t_Index * int * 'v * bool
  | ChooseBranch of int * int * ('v) t_Index * ('v) t_Index * int * 'v * bool

let rec (* nat_index.bend:11 *)
f_new : 'v. unit -> ('v) t_Index =
fun () ->
Empty
and (* nat_index.bend:20 *)
f_difference : int -> t_Difference -> int =
fun v_fuel v_work ->
(match (v_fuel, v_work) with
| (0, _) ->
0
| (__nat_1, (Halve (v_left, v_right, v_mask))) when __nat_1 >= 1 ->
(let v_rest = (__nat_1 - 1) in
(let v_a = (Base.nat_div (v_left) (2)) in
(let v_b = (Base.nat_div (v_right) (2)) in
(f_difference (v_rest) ((Decide (v_a, v_b, v_mask, (Base.nat_is_eq (v_a) (v_b)))))))))
| (__nat_2, (Decide (v_left, v_right, v_mask, true))) when __nat_2 >= 1 ->
(let v_rest = (__nat_2 - 1) in
v_mask)
| (__nat_3, (Decide (v_left, v_right, v_mask, false))) when __nat_3 >= 1 ->
(let v_rest = (__nat_3 - 1) in
(f_difference (v_rest) ((Halve (v_left, v_right, (Base.nat_mul (v_mask) (2))))))))
and (* nat_index.bend:35 *)
f_prefix : int -> int -> int =
fun v_key v_mask ->
(Base.nat_div ((Base.nat_div (v_key) (v_mask))) (2))
and (* nat_index.bend:38 *)
f_same_prefix : int -> int -> int -> bool =
fun v_key v_sample v_mask ->
(Base.nat_is_eq ((f_prefix (v_key) (v_mask))) ((f_prefix (v_sample) (v_mask))))
and (* nat_index.bend:41 *)
f_high_bit : int -> int -> bool =
fun v_key v_mask ->
(Base.nat_is_ne ((Base.nat_mod ((Base.nat_div (v_key) (v_mask))) (2))) (0))
and (* nat_index.bend:44 *)
f_linked : 'v. bool -> int -> int -> ('v) t_Index -> ('v) t_Index -> ('v) t_Index =
fun v_high v_sample v_mask v_a v_b ->
(match v_high with
| false ->
(Branch (v_sample, v_mask, v_a, v_b))
| true ->
(Branch (v_sample, v_mask, v_b, v_a)))
and (* nat_index.bend:51 *)
f_link : 'v. int -> ('v) t_Index -> int -> ('v) t_Index -> ('v) t_Index =
fun v_key v_value v_other_key v_other ->
(let v_mask = (f_difference (96) ((Halve (v_key, v_other_key, 1)))) in
(f_linked ((f_high_bit (v_key) (v_mask))) (v_key) (v_mask) (v_value) (v_other)))
and (* nat_index.bend:61 *)
f_insert : 'v. int -> ('v) t_Insert -> ('v) t_Index =
fun v_fuel v_work ->
(match (v_fuel, v_work) with
| (0, _) ->
Empty
| (__nat_4, (Enter (Empty, v_key, v_value))) when __nat_4 >= 1 ->
(let v_rest = (__nat_4 - 1) in
(Leaf (v_key, v_value)))
| (__nat_5, (Enter ((Leaf (v_old_key, v_old_value)), v_key, v_value))) when __nat_5 >= 1 ->
(let v_rest = (__nat_5 - 1) in
(f_insert (v_rest) ((CompareLeaf (v_old_key, v_old_value, v_key, v_value, (Base.nat_is_eq (v_old_key) (v_key)))))))
| (__nat_6, (CompareLeaf (v_old_key, v_old_value, v_key, v_value, true))) when __nat_6 >= 1 ->
(let v_rest = (__nat_6 - 1) in
(Leaf (v_key, v_value)))
| (__nat_7, (CompareLeaf (v_old_key, v_old_value, v_key, v_value, false))) when __nat_7 >= 1 ->
(let v_rest = (__nat_7 - 1) in
(f_link (v_key) ((Leaf (v_key, v_value))) (v_old_key) ((Leaf (v_old_key, v_old_value)))))
| (__nat_8, (Enter ((Branch (v_sample, v_mask, v_low, v_high)), v_key, v_value))) when __nat_8 >= 1 ->
(let v_rest = (__nat_8 - 1) in
(f_insert (v_rest) ((CompareBranch (v_sample, v_mask, v_low, v_high, v_key, v_value, (f_same_prefix (v_key) (v_sample) (v_mask)))))))
| (__nat_9, (CompareBranch (v_sample, v_mask, v_low, v_high, v_key, v_value, false))) when __nat_9 >= 1 ->
(let v_rest = (__nat_9 - 1) in
(f_link (v_key) ((Leaf (v_key, v_value))) (v_sample) ((Branch (v_sample, v_mask, v_low, v_high)))))
| (__nat_10, (CompareBranch (v_sample, v_mask, v_low, v_high, v_key, v_value, true))) when __nat_10 >= 1 ->
(let v_rest = (__nat_10 - 1) in
(f_insert (v_rest) ((ChooseBranch (v_sample, v_mask, v_low, v_high, v_key, v_value, (f_high_bit (v_key) (v_mask)))))))
| (__nat_11, (ChooseBranch (v_sample, v_mask, v_low, v_high, v_key, v_value, false))) when __nat_11 >= 1 ->
(let v_rest = (__nat_11 - 1) in
(Branch (v_sample, v_mask, (f_insert (v_rest) ((Enter (v_low, v_key, v_value)))), v_high)))
| (__nat_12, (ChooseBranch (v_sample, v_mask, v_low, v_high, v_key, v_value, true))) when __nat_12 >= 1 ->
(let v_rest = (__nat_12 - 1) in
(Branch (v_sample, v_mask, v_low, (f_insert (v_rest) ((Enter (v_high, v_key, v_value))))))))
and (* nat_index.bend:86 *)
f_set : 'v. ('v) t_Index -> int -> 'v -> ('v) t_Index =
fun v_index v_key v_value ->
(f_insert (160) ((Enter (v_index, v_key, v_value))))
and (* nat_index.bend:89 *)
f_choose : 'v. bool -> (unit -> ('v) option) -> (unit -> ('v) option) -> ('v) option =
fun v_upper v_right v_left ->
(match v_upper with
| true ->
(v_right (()))
| false ->
(v_left (())))
and (* nat_index.bend:96 *)
f_within : 'v. bool -> (unit -> ('v) option) -> ('v) option =
fun v_same v_found ->
(match v_same with
| true ->
(v_found (()))
| false ->
None)
and (* nat_index.bend:103 *)
f_find : 'v. ('v) t_Index -> int -> ('v) option =
fun v_index v_key ->
(match v_index with
| Empty ->
None
| (Leaf (v_found, v_value)) ->
(Base.bool_pick ((Base.nat_is_eq (v_found) (v_key))) ((Some (v_value))) (None))
| (Branch (v_sample, v_mask, v_low, v_high)) ->
(f_within ((f_same_prefix (v_key) (v_sample) (v_mask))) ((fun v_unit ->
(f_choose ((f_high_bit (v_key) (v_mask))) ((fun v_unit ->
(f_find (v_high) (v_key)))) ((fun v_unit ->
(f_find (v_low) (v_key)))))))))
and (* nat_index.bend:112 *)
f_fallback : 'v. ('v) option -> 'v -> 'v =
fun v_found v_otherwise ->
(match v_found with
| None ->
v_otherwise
| (Some (v_value)) ->
v_value)
and (* nat_index.bend:119 *)
f_get : 'v. ('v) t_Index -> int -> 'v -> 'v =
fun v_index v_key v_otherwise ->
(f_fallback ((f_find (v_index) (v_key))) (v_otherwise))
