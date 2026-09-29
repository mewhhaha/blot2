(* Native semantic port of compiler/catalog_versions.bend.

   Source SHA-256: 5f427c85de93399d9f47be249378b6b993e9b6be54d80c797dea36aca61f5c19

   Ownership/type arguments are erased; value types are checked by OCaml.

   No Bend interpreter or generated C/JavaScript is linked. *)

open Base

module M = Ox_model

module K = Ox_native_cache_keys

module R = Ox_native_response

module Index = Ox_index

type t_TypeVersion =
  | TypeVersion of (int32) list * int
and t_TypeVersions =
  | TypeVersions of ((t_TypeVersion) Base.map) Base.map * int
and t_Revision =
  | Revision of (int32) list * (int) list * ((t_TypeVersion) Base.map) Base.map * int
and t_Prepared =
  | Prepared of t_Revision * bool

let s_0 = Base.text_of_utf8 "internal_error"

let s_1 = Base.text_of_utf8 "planned group type is absent from validated catalog"

let rec (* catalog_versions.bend:28 *)
f_entry : ((t_TypeVersion) Base.map) Base.map -> M.t_TypeId -> (t_TypeVersion) option =
fun v_index v_identity ->
(let (M.TypeId (v_module_name, v_declaration)) = v_identity in
(let v_nested = (Index.f_get (v_index) (v_module_name) ((Base.map_new ()))) in
(Index.f_find (v_nested) (v_declaration))))
and (* catalog_versions.bend:33 *)
f_put : ((t_TypeVersion) Base.map) Base.map -> M.t_TypeId -> t_TypeVersion -> ((t_TypeVersion) Base.map) Base.map =
fun v_index v_identity v_value ->
(let (M.TypeId (v_module_name, v_declaration)) = v_identity in
(let v_nested = (Index.f_get (v_index) (v_module_name) ((Base.map_new ()))) in
(Base.map_set (v_index) (v_module_name) ((Base.map_set (v_nested) (v_declaration) (v_value))))))
and (* catalog_versions.bend:38 *)
f_select_same : bool -> (int32) list -> int -> int -> (t_TypeVersion * int) =
fun v_same v_words v_token v_next ->
(match v_same with
| true ->
((TypeVersion (v_words, v_token)), v_next)
| false ->
((TypeVersion (v_words, v_next)), (Base.nat_add 1 v_next)))
and (* catalog_versions.bend:45 *)
f_select : (t_TypeVersion) option -> (int32) list -> int -> (t_TypeVersion * int) =
fun v_found v_words v_next ->
(match v_found with
| (Some ((TypeVersion (v_prior, v_token)))) ->
(f_select_same ((K.f_same (v_prior) (v_words))) (v_words) (v_token) (v_next))
| None ->
((TypeVersion (v_words, v_next)), (Base.nat_add 1 v_next)))
and (* catalog_versions.bend:52 *)
f_previous_types : (t_Revision) option -> ((t_TypeVersion) Base.map) Base.map =
fun v_previous ->
(match v_previous with
| None ->
(Base.map_new ())
| (Some ((Revision (v_operations, v_ordered_types, v_types, v_next)))) ->
v_types)
and (* catalog_versions.bend:59 *)
f_previous_next : (t_Revision) option -> int =
fun v_previous ->
(match v_previous with
| None ->
1
| (Some ((Revision (v_operations, v_ordered_types, v_types, v_next)))) ->
v_next)
and (* catalog_versions.bend:66 *)
f_insert_selected : (t_TypeVersion * int) -> ((t_TypeVersion) Base.map) Base.map -> M.t_TypeId -> t_TypeVersions =
fun v_selection v_entries v_identity ->
(let (v_selected, v_following) = v_selection in
(TypeVersions ((f_put (v_entries) (v_identity) (v_selected)), v_following)))
and (* catalog_versions.bend:70 *)
f_types_go : (M.t_DataType) list -> ((t_TypeVersion) Base.map) Base.map -> t_TypeVersions -> (M.t_Diagnostic, t_TypeVersions) Base.result_ =
fun v_pending v_previous v_result ->
(match v_pending with
| [] ->
(Done (v_result))
| (v_declaration :: v_tail) ->
(let (M.DataType (v_identity, v_parameters, v_constructors)) = v_declaration in
(let (TypeVersions (v_entries, v_next)) = v_result in
(match (K.f_encode ([(K.DataTypes ([v_declaration]))])) with
| Fail __error -> Fail __error
| Done v_words ->
(f_types_go (v_tail) (v_previous) ((f_insert_selected ((f_select ((f_entry (v_previous) (v_identity))) (v_words) (v_next))) (v_entries) (v_identity))))))))
and (* catalog_versions.bend:81 *)
f_operations_match : (t_Revision) option -> (int32) list -> bool =
fun v_previous v_current ->
(match v_previous with
| None ->
false
| (Some ((Revision (v_operations, v_ordered_types, v_types, v_next)))) ->
(K.f_same (v_operations) (v_current)))
and (* catalog_versions.bend:88 *)
f_make_prepared : t_TypeVersions -> (t_Revision) option -> (int32) list -> (int) list -> t_Prepared =
fun v_versions v_previous v_operation_words v_ordered_types ->
(let (TypeVersions (v_entries, v_next)) = v_versions in
(Prepared ((Revision (v_operation_words, v_ordered_types, v_entries, v_next)), (f_operations_match (v_previous) (v_operation_words)))))
and (* catalog_versions.bend:92 *)
f_version_entries : t_TypeVersions -> ((t_TypeVersion) Base.map) Base.map =
fun v_value ->
(let (TypeVersions (v_entries, v_next)) = v_value in
v_entries)
and (* catalog_versions.bend:96 *)
f_token : (t_TypeVersion) option -> M.t_TypeId -> (M.t_Diagnostic, int) Base.result_ =
fun v_found v_identity ->
(match v_found with
| (Some ((TypeVersion (v_words, v_value)))) ->
(Done (v_value))
| None ->
(Fail ((M.Diagnostic (s_0, (M.f_type_id_show (v_identity)), s_1)))))
and (* catalog_versions.bend:103 *)
f_tokens : (M.t_DataType) list -> ((t_TypeVersion) Base.map) Base.map -> (M.t_Diagnostic, (int) list) Base.result_ =
fun v_pending v_versions ->
(match v_pending with
| [] ->
(Done ([]))
| ((M.DataType (v_identity, v_parameters, v_constructors)) :: v_tail) ->
(match (f_token ((f_entry (v_versions) (v_identity))) (v_identity)) with
| Fail __error -> Fail __error
| Done v_head ->
(match (f_tokens (v_tail) (v_versions)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done ((v_head :: v_rest))))))
and (* catalog_versions.bend:113 *)
f_prepare : (M.t_DataType) list -> (M.t_Operation) list -> (t_Revision) option -> (M.t_Diagnostic, t_Prepared) Base.result_ =
fun v_types v_operations v_previous ->
(match (K.f_operations (v_operations)) with
| Fail __error -> Fail __error
| Done v_operation_words ->
(match (f_types_go (v_types) ((f_previous_types (v_previous))) ((TypeVersions ((Base.map_new ()), (f_previous_next (v_previous)))))) with
| Fail __error -> Fail __error
| Done v_versions ->
(match (f_tokens (v_types) ((f_version_entries (v_versions)))) with
| Fail __error -> Fail __error
| Done v_ordered ->
(Done ((f_make_prepared (v_versions) (v_previous) (v_operation_words) (v_ordered)))))))
and (* catalog_versions.bend:120 *)
f_prepared_revision : t_Prepared -> t_Revision =
fun v_prepared ->
(let (Prepared (v_revision, v_same_operations)) = v_prepared in
v_revision)
and (* catalog_versions.bend:124 *)
f_prepared_same_operations : t_Prepared -> bool =
fun v_prepared ->
(let (Prepared (v_revision, v_same_operations)) = v_prepared in
v_same_operations)
and (* catalog_versions.bend:128 *)
f_group_key : M.t_Module -> t_Revision -> (M.t_Diagnostic, (int32) list) Base.result_ =
fun v_module v_revision ->
(let (M.Module (v_constants, v_functions, v_types, v_operations)) = v_module in
(let (Revision (v_operation_words, v_ordered_types, v_versions, v_next)) = v_revision in
(match (f_tokens (v_types) (v_versions)) with
| Fail __error -> Fail __error
| Done v_selected ->
(K.f_encode ([(K.Constants (v_constants)); (K.Functions (v_functions)); (K.Field ((R.Naturals (v_selected))))])))))
and (* catalog_versions.bend:137 *)
f_encoded_same : (M.t_Diagnostic, (int32) list) Base.result_ -> (int32) list -> bool =
fun v_result v_expected ->
(match v_result with
| (Fail (v_diagnostic)) ->
false
| (Done (v_words)) ->
(K.f_same (v_words) (v_expected)))
and (* catalog_versions.bend:144 *)
f_original_type_words_if : bool -> M.t_DataType -> (int32) list -> bool =
fun v_same v_declaration v_words ->
(match v_same with
| false ->
false
| true ->
(f_encoded_same ((K.f_encode ([(K.DataTypes ([v_declaration]))]))) (v_words)))
and (* catalog_versions.bend:151 *)
f_original_type_matches : (t_TypeVersion) option -> M.t_DataType -> int -> bool =
fun v_found v_declaration v_expected ->
(match v_found with
| None ->
false
| (Some ((TypeVersion (v_words, v_token)))) ->
(f_original_type_words_if ((Base.nat_is_eq (v_token) (v_expected))) (v_declaration) (v_words)))
and (* catalog_versions.bend:158 *)
f_original_types_match : (M.t_DataType) list -> (int) list -> ((t_TypeVersion) Base.map) Base.map -> bool -> bool =
fun v_pending v_ordered v_versions v_matching ->
(match (v_pending, v_ordered, v_matching) with
| (_, _, false) ->
false
| ([], [], true) ->
true
| (((M.DataType (v_identity, v_parameters, v_constructors)) :: v_tail), (v_expected :: v_rest), true) ->
(let v_declaration = (M.DataType (v_identity, v_parameters, v_constructors)) in
(f_original_types_match (v_tail) (v_rest) (v_versions) ((f_original_type_matches ((f_entry (v_versions) (v_identity))) (v_declaration) (v_expected)))))
| (_, _, _) ->
false)
and (* catalog_versions.bend:170 *)
f_original_operations_match : (M.t_Diagnostic, (int32) list) Base.result_ -> (int32) list -> (M.t_DataType) list -> (int) list -> ((t_TypeVersion) Base.map) Base.map -> bool =
fun v_result v_current v_types v_ordered v_versions ->
(f_original_types_match (v_types) (v_ordered) (v_versions) ((f_encoded_same (v_result) (v_current))))
and (* catalog_versions.bend:173 *)
f_original_matches : M.t_Module -> t_Revision -> bool =
fun v_module v_revision ->
(let (M.Module (v_constants, v_functions, v_types, v_operations)) = v_module in
(let (Revision (v_operation_words, v_ordered_types, v_versions, v_next)) = v_revision in
(f_original_operations_match ((K.f_operations (v_operations))) (v_operation_words) (v_types) (v_ordered_types) (v_versions))))
