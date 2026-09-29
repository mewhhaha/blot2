(* Native semantic port of compiler/global_bindings.bend.

   Source SHA-256: bb72e3f9cf1d348d6fb30c027f37ff44f3814d1ee4fb7b50431be0ce71079fe6

   Ownership/type arguments are erased; value types are checked by OCaml.

   No Bend interpreter or generated C/JavaScript is linked. *)

open Base

module I = Ox_infer

module Index = Ox_index

type t_Entry =
  | Entry of int * I.t_Binding
and t_Selection =
  | Selection of (t_Entry) list * Base.set

let rec (* global_bindings.bend:14 *)
f_build : (I.t_Binding) list -> int -> ((t_Entry) list) Base.map -> ((t_Entry) list) Base.map =
fun v_bindings v_position v_index ->
(match v_bindings with
| [] ->
v_index
| (v_binding :: v_tail) ->
(let (I.Binding (v_name, v_ty, v_variables, v_predicates)) = v_binding in
(let v_known = v_index in
(let v_prior = (Index.f_get (v_known) (v_name) ([])) in
(f_build (v_tail) ((Base.nat_add 1 v_position)) ((Base.map_set (v_known) (v_name) (((Entry (v_position, v_binding)) :: v_prior)))))))))
and (* global_bindings.bend:24 *)
f_choose : bool -> (unit -> (t_Entry) list) -> (unit -> (t_Entry) list) -> (t_Entry) list =
fun v_before v_first v_later ->
(match v_before with
| true ->
(v_first (()))
| false ->
(v_later (())))
and (* global_bindings.bend:31 *)
f_insert : (t_Entry) list -> t_Entry -> (t_Entry) list =
fun v_entries v_item ->
(match v_entries with
| [] ->
(v_item :: [])
| (v_head :: v_tail) ->
(let (Entry (v_position, v_binding)) = v_head in
(let (Entry (v_target, v_item_binding)) = v_item in
(f_choose ((Base.nat_is_lt (v_target) (v_position))) ((fun v_unit ->
(v_item :: (v_head :: v_tail)))) ((fun v_unit ->
(v_head :: (f_insert (v_tail) (v_item)))))))))
and (* global_bindings.bend:40 *)
f_add : (t_Entry) list -> (t_Entry) list -> (t_Entry) list =
fun v_entries v_selected ->
(match v_entries with
| [] ->
v_selected
| (v_head :: v_tail) ->
(f_add (v_tail) ((f_insert (v_selected) (v_head)))))
and (* global_bindings.bend:47 *)
f_present : (unit) option -> bool =
fun v_found ->
(match v_found with
| None ->
false
| (Some (v_value)) ->
true)
and (* global_bindings.bend:54 *)
f_select_name : bool -> Base.text -> ((t_Entry) list) Base.map -> t_Selection -> t_Selection =
fun v_found v_name v_index v_selection ->
(match v_found with
| true ->
v_selection
| false ->
(let (Selection (v_entries, v_seen)) = v_selection in
(let v_key = v_name in
(Selection ((f_add ((Index.f_get (v_index) (v_key) ([]))) (v_entries)), (Base.set_add (v_seen) (v_key)))))))
and (* global_bindings.bend:63 *)
f_select : (Base.text) list -> ((t_Entry) list) Base.map -> t_Selection -> t_Selection =
fun v_names v_index v_selection ->
(match v_names with
| [] ->
v_selection
| (v_name :: v_tail) ->
(let (Selection (v_entries, v_seen)) = v_selection in
(f_select (v_tail) (v_index) ((f_select_name ((f_present ((Index.f_find (v_seen) (v_name))))) (v_name) (v_index) ((Selection (v_entries, v_seen))))))))
and (* global_bindings.bend:71 *)
f_bindings : (t_Entry) list -> (I.t_Binding) list =
fun v_entries ->
(match v_entries with
| [] ->
[]
| ((Entry (v_position, v_binding)) :: v_tail) ->
(v_binding :: (f_bindings (v_tail))))
and (* global_bindings.bend:78 *)
f_selected : t_Selection -> (I.t_Binding) list =
fun v_selection ->
(let (Selection (v_entries, v_seen)) = v_selection in
(f_bindings (v_entries)))
and (* global_bindings.bend:82 *)
f_referenced : ((t_Entry) list) Base.map -> (Base.text) list -> (I.t_Binding) list =
fun v_index v_names ->
(f_selected ((f_select (v_names) (v_index) ((Selection ([], (Base.set_new ())))))))
