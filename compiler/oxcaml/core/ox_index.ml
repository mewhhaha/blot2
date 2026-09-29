(* Native semantic port of compiler/index.bend.

   Source SHA-256: 5646363ee5335784c1e7849a80c14ee677e324f2165f3de172361872c872fda8

   Ownership/type arguments are erased; value types are checked by OCaml.

   No Bend interpreter or generated C/JavaScript is linked. *)

open Base

module M = Ox_model

let rec (* index.bend:5 *)
f_character_bit : Base.char32 -> int -> bool =
fun v_character v_offset ->
(match (v_character, v_offset) with
| ((Chr (__char_v_value)), 0) ->
let v_value = Int32.of_int __char_v_value in
true
| ((Chr (__char_v_value)), __nat_1) when __nat_1 >= 1 ->
let v_value = Int32.of_int __char_v_value in
(let v_bit = (__nat_1 - 1) in
(Base.u32_is_ne ((Base.u32_and ((Base.u32_shrn (v_value) ((Base.nat_sub (31) (v_bit))))) (0x00000001l))) (0x00000000l))))
and (* index.bend:12 *)
f_string_bit : Base.text -> int -> int -> bool =
fun v_name v_character v_offset ->
(match (v_name, v_character) with
| (SNil, _) ->
false
| ((SCon (v_head, v_tail)), 0) ->
(f_character_bit (v_head) (v_offset))
| ((SCon (v_head, v_tail)), __nat_2) when __nat_2 >= 1 ->
(let v_rest = (__nat_2 - 1) in
(f_string_bit (v_tail) (v_rest) (v_offset))))
and (* index.bend:21 *)
f_selected : 'v. bool -> (unit -> ('v) option) -> (unit -> ('v) option) -> ('v) option =
fun v_high v_right v_left ->
(match v_high with
| true ->
(v_right (()))
| false ->
(v_left (())))
and (* index.bend:30 *)
f_found_value : 'v. bool -> 'v -> ('v) option =
fun v_equal v_value ->
(match v_equal with
| false ->
None
| true ->
(Some (v_value)))
and (* index.bend:41 *)
f_find_loop : 'v. int -> ('v) Base.map -> Base.text -> Base.text -> int -> ('v) option =
fun v_fuel v_index v_name v_remaining v_cursor ->
(match (v_fuel, v_index) with
| (0, _) ->
None
| (__nat_3, MTip) when __nat_3 >= 1 ->
(let v_rest = (__nat_3 - 1) in
None)
| (__nat_4, (MLeaf (v_key, v_value))) when __nat_4 >= 1 ->
(let v_rest = (__nat_4 - 1) in
(f_found_value ((M.f_name_equal (v_key) (v_name))) (v_value)))
| (__nat_5, (MNode (v_position, v_left, v_right))) when __nat_5 >= 1 ->
(let v_rest = (__nat_5 - 1) in
(let v_character = (Base.nat_div (v_position) (33)) in
(let v_suffix = (Base.string_drop (v_remaining) ((Base.nat_sub (v_character) (v_cursor)))) in
(let v_next = (Base.bool_pick ((f_string_bit (v_suffix) (0) ((Base.nat_mod (v_position) (33))))) (v_right) (v_left)) in
(f_find_loop (v_rest) (v_next) (v_name) (v_suffix) (v_character)))))))
and (* index.bend:55 *)
f_find_work : 'v. ('v) Base.map -> Base.text -> Base.text -> int -> ('v) option =
fun v_index v_name v_remaining v_cursor ->
(f_find_loop ((M.f_max_nat ())) (v_index) (v_name) (v_remaining) (v_cursor))
and (* index.bend:58 *)
f_find : 'v. ('v) Base.map -> Base.text -> ('v) option =
fun v_index v_name ->
(f_find_work (v_index) (v_name) (v_name) (0))
and (* index.bend:61 *)
f_fallback : 'v. ('v) option -> 'v -> 'v =
fun v_found v_otherwise ->
(match v_found with
| None ->
v_otherwise
| (Some (v_value)) ->
v_value)
and (* index.bend:68 *)
f_get : 'v. ('v) Base.map -> Base.text -> 'v -> 'v =
fun v_index v_name v_otherwise ->
(f_fallback ((f_find (v_index) (v_name))) (v_otherwise))
