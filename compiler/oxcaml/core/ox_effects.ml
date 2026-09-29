(* Native semantic port of compiler/effects.bend.

   Source SHA-256: 979c9ce2fbc4a54644c12e0aee335dec76b47d022570dbb2415b6abc26be8be3

   Ownership/type arguments are erased; value types are checked by OCaml.

   No Bend interpreter or generated C/JavaScript is linked. *)

open Base

module M = Ox_model

let rec (* effects.bend:4 *)
f_effect_equal : M.t_Effect -> M.t_Effect -> bool =
fun v_left v_right ->
(let (M.OperationEffect (v_a)) = v_left in
(let (M.OperationEffect (v_b)) = v_right in
(M.f_type_id_equal (v_a) (v_b))))
and (* effects.bend:9 *)
f_or_else : bool -> (unit -> bool) -> bool =
fun v_found v_next ->
(match v_found with
| true ->
true
| false ->
(v_next (())))
and (* effects.bend:16 *)
f_contains : (M.t_Effect) list -> M.t_Effect -> bool =
fun v_effects v_effect ->
(match v_effects with
| [] ->
false
| (v_head :: v_tail) ->
(f_or_else ((f_effect_equal (v_head) (v_effect))) ((fun _ ->
(f_contains (v_tail) (v_effect))))))
and (* effects.bend:23 *)
f_put_if : bool -> (M.t_Effect) list -> M.t_Effect -> (M.t_Effect) list =
fun v_present v_effects v_effect ->
(match v_present with
| true ->
v_effects
| false ->
(v_effect :: v_effects))
and (* effects.bend:30 *)
f_put : (M.t_Effect) list -> M.t_Effect -> (M.t_Effect) list =
fun v_effects v_effect ->
(f_put_if ((f_contains (v_effects) (v_effect))) (v_effects) (v_effect))
and (* effects.bend:33 *)
f_effect_le : M.t_Effect -> M.t_Effect -> bool =
fun v_left v_right ->
(let (M.OperationEffect ((M.TypeId (v_lm, v_ln)))) = v_left in
(let (M.OperationEffect ((M.TypeId (v_rm, v_rn)))) = v_right in
(Base.bool_or ((Base.string_is_lt (v_lm) (v_rm))) ((Base.bool_and ((M.f_name_equal (v_lm) (v_rm))) ((Base.string_is_le (v_ln) (v_rn))))))))
and (* effects.bend:38 *)
f_repeated : (M.t_Effect) option -> M.t_Effect -> bool =
fun v_previous v_effect ->
(match v_previous with
| None ->
false
| (Some (v_last)) ->
(f_effect_equal (v_last) (v_effect)))
and (* effects.bend:45 *)
f_deduplicate : (M.t_Effect) list -> (M.t_Effect) option -> (M.t_Effect) list -> (M.t_Effect) list =
fun v_sorted v_previous v_reversed ->
(match v_sorted with
| [] ->
(Base.list_reverse (v_reversed))
| (v_head :: v_tail) ->
(f_deduplicate (v_tail) ((Some (v_head))) ((f_put_if ((f_repeated (v_previous) (v_head))) (v_reversed) (v_head)))))
and (* effects.bend:54 *)
f_canonical : (M.t_Effect) list -> (M.t_Effect) list =
fun v_effects ->
(f_deduplicate ((Base.list_sort (f_effect_le) (v_effects))) (None) ([]))
and (* effects.bend:57 *)
f_union : (M.t_Effect) list -> (M.t_Effect) list -> (M.t_Effect) list =
fun v_left v_right ->
(f_canonical ((Base.list_append (v_left) (v_right))))
