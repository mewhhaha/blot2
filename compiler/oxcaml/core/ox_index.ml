(* Native index operations, initially ported from compiler/index.bend.

   Bit tests and direct default lookups are hand-maintained, allocation-checked
   native paths. The option-returning helpers remain semantic test oracles.

   Source SHA-256: 5646363ee5335784c1e7849a80c14ee677e324f2165f3de172361872c872fda8

   Ownership/type arguments are erased; value types are checked by OCaml.

   No Bend interpreter or generated C/JavaScript is linked. *)

open Base

module M = Ox_model

(* Positions are scalar bits, not byte offsets. Nat's saturating subtraction
   means offsets above 32 retain the low-bit behavior of the reference. *)
let[@zero_alloc strict] rec f_character_bit : Base.char32 -> int -> bool =
fun (Chr value) offset ->
  offset = 0 || ((Base.u32_to_nat value lsr max 0 (32 - offset)) land 1 <> 0)
and[@zero_alloc strict] (* index.bend:12 *)
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
and[@zero_alloc strict] (* Native lookup returning a default directly, without a transient Some.
       Preserve the original traversal budget and first matching leaf. *)
f_get_loop : 'v. int -> 'v Base.map -> Base.text -> Base.text -> int -> 'v -> 'v =
fun fuel index name remaining cursor otherwise ->
  if fuel = 0 then otherwise else match index with
  | MTip -> otherwise
  | MLeaf(key,value) -> if M.f_name_equal key name then value else otherwise
  | MNode(position,left,right) ->
    let character = Base.nat_div position 33 in
    let suffix = Base.string_drop remaining (Base.nat_sub character cursor) in
    let next = if f_string_bit suffix 0 (Base.nat_mod position 33) then right else left in
    f_get_loop (fuel-1) next name suffix character otherwise
and[@zero_alloc strict] f_get : 'v. 'v Base.map -> Base.text -> 'v -> 'v =
fun index name otherwise -> f_get_loop (M.f_max_nat ()) index name name 0 otherwise
