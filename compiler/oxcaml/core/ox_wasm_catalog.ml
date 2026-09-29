(* Native semantic port of compiler/wasm_catalog.bend.

   Source SHA-256: eb9cc2a470ffeef18b11d30192a0cd1216a21d2ed0bef0a1a77d59abeb1924a2

   Ownership/type arguments are erased; value types are checked by OCaml.

   No Bend interpreter or generated C/JavaScript is linked. *)

open Base

module M = Ox_model

module Index = Ox_index

type t_ConstructorSlot =
  | ConstructorSlot of Base.text * int * bool
and t_TypeCatalog =
  | TypeCatalog of (t_ConstructorSlot) list * ((t_ConstructorSlot) option) Base.map

let rec (* wasm_catalog.bend:11 *)
f_datatype_slots : (M.t_Constructor) list -> int -> (t_ConstructorSlot) list =
fun v_variants v_index ->
(match v_variants with
| [] ->
[]
| ((M.Constructor (v_name, None, v_fields)) :: v_tail) ->
(let v_tag = v_index in
((ConstructorSlot (v_name, v_tag, false)) :: (f_datatype_slots (v_tail) ((Base.nat_add 1 v_tag)))))
| ((M.Constructor (v_name, (Some (v_payload)), v_fields)) :: v_tail) ->
(let v_tag = v_index in
((ConstructorSlot (v_name, v_tag, true)) :: (f_datatype_slots (v_tail) ((Base.nat_add 1 v_tag))))))
and (* wasm_catalog.bend:22 *)
f_constructor_slots : (M.t_DataType) list -> int -> (t_ConstructorSlot) list =
fun v_types v_index ->
(match v_types with
| [] ->
[]
| ((M.DataType (v_identity, v_parameters, v_variants)) :: v_tail) ->
(let v_start = v_index in
(Base.list_append ((f_datatype_slots (v_variants) (v_start))) ((f_constructor_slots (v_tail) ((Base.nat_add (v_start) ((Base.list_length (v_variants))))))))))
and (* wasm_catalog.bend:30 *)
f_constructor_index_go : (t_ConstructorSlot) list -> ((t_ConstructorSlot) option) Base.map -> ((t_ConstructorSlot) option) Base.map =
fun v_slots v_indexed ->
(match v_slots with
| [] ->
v_indexed
| ((ConstructorSlot (v_name, v_tag, v_payload)) :: v_tail) ->
(f_constructor_index_go (v_tail) ((Base.map_set (v_indexed) (v_name) ((Some ((ConstructorSlot (v_name, v_tag, v_payload)))))))))
and (* wasm_catalog.bend:37 *)
f_type_catalog : (M.t_DataType) list -> t_TypeCatalog =
fun v_types ->
(let v_variants = (f_constructor_slots (v_types) (0)) in
(TypeCatalog (v_variants, (f_constructor_index_go ((Base.list_reverse (v_variants))) ((Base.map_new ()))))))
and (* wasm_catalog.bend:41 *)
f_catalog_variants : t_TypeCatalog -> (t_ConstructorSlot) list =
fun v_catalog ->
(let (TypeCatalog (v_variants, v_constructors)) = v_catalog in
v_variants)
and (* wasm_catalog.bend:45 *)
f_catalog_constructors : t_TypeCatalog -> ((t_ConstructorSlot) option) Base.map =
fun v_catalog ->
(let (TypeCatalog (v_variants, v_constructors)) = v_catalog in
v_constructors)
and (* wasm_catalog.bend:49 *)
f_constructor_get : ((t_ConstructorSlot) option) Base.map -> Base.text -> (t_ConstructorSlot) option =
fun v_indexed v_name ->
(Index.f_get (v_indexed) (v_name) (None))
