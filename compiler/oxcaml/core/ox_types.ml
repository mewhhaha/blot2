(* Native semantic port of compiler/types.bend.

   Source SHA-256: 4785517cdfbca37e193248a5fd91912ec03ca9abde00ee1f78ef8b6ae88bc739

   Ownership/type arguments are erased; value types are checked by OCaml.

   No Bend interpreter or generated C/JavaScript is linked. *)

open Base

module M = Ox_model

module R = Ox_effect_rows

module NatIndex = Ox_nat_index

type t_Equation =
  | Equation of M.t_Ty * M.t_Ty * Base.text
  | RowEquation of M.t_EffectRow * M.t_EffectRow * Base.text
and t_Substitution =
  | Substitution of int * M.t_Ty
  | RowSubstitution of int * M.t_EffectRow
and 'v t_Version =
  | Version of int * 'v
and t_Substitutions =
  | Substitutions of (t_Substitution) list * (((M.t_Ty) t_Version) list) NatIndex.t_Index * (((M.t_EffectRow) t_Version) list) NatIndex.t_Index * int
and t_TypeWork =
  | OneType of M.t_Ty
  | ManyTypes of (M.t_Ty) list
and t_Replacement =
  | ReplaceVariable of int * M.t_Ty
  | ReplaceParameter of int * M.t_Ty
  | FreshParameters of (int) NatIndex.t_Index
  | ReplaceFree of Base.text * Base.text * M.t_Ty
  | RelocateFree of Base.text
and t_Renaming =
  | Renaming of (int) NatIndex.t_Index * int * bool
and t_VariableKind =
  | FreshVariables
  | SchemeParameters
and t_FlatFrame =
  | AfterFunctionParameter of M.t_Ty * M.t_EffectRow * int * int * int
  | AfterFunctionResult of M.t_Ty * M.t_EffectRow * int
  | AfterStateProvider of M.t_TypeId * M.t_TypeId
  | AfterProviderArguments of M.t_TypeId
  | AfterProductElements
  | AfterArrayElement
  | AfterManyHead of (M.t_Ty) list * (M.t_Ty) list * int * int * int
and t_FlatValue =
  | FlatOne of M.t_Ty
  | FlatMany of (M.t_Ty) list
and t_FlatControl =
  | FlatVisit of int * int * bool * int * t_TypeWork * (M.t_Ty) list * (t_FlatFrame) list
  | FlatReturn of t_FlatValue * (t_FlatFrame) list
and t_VariableUnion =
  | SmallUnion of (int) list * int
  | IndexedUnion of (int) list * (unit) NatIndex.t_Index
and t_Opened =
  | Opened of M.t_Ty * int
and t_OpenedTypes =
  | OpenedTypes of (M.t_Ty) list * int
and t_ParameterKinds =
  | ParameterKinds of (int) list * (int) list
and t_Unification =
  | Unification of (t_Equation) list * t_Substitutions
and t_Solution =
  | Solution of t_Substitutions * int

let s_0 = Base.text_of_utf8 "type_complexity"

let s_1 = Base.text_of_utf8 "inference"

let s_2 = Base.text_of_utf8 "type traversal exceeded the 65536-node nesting/width limit"

let s_3 = Base.text_of_utf8 "internal_error"

let s_4 = Base.text_of_utf8 "type rewrite did not produce exactly one type"

let s_5 = Base.text_of_utf8 "kind_mismatch"

let s_6 = Base.text_of_utf8 "an effect row variable cannot be replaced by a value type"

let s_7 = Base.text_of_utf8 "substitution"

let s_8 = Base.text_of_utf8 "indexed substitution exceeded its chronological bound"

let s_9 = Base.text_of_utf8 "a quantified index is used as both a value type and an effect row"

let s_10 = Base.text_of_utf8 "infinite_type"

let s_11 = Base.text_of_utf8 "occurs check failed: ?"

let s_12 = Base.text_of_utf8 " occurs in "

let s_13 = Base.text_of_utf8 "type_arity"

let s_14 = Base.text_of_utf8 "type constructor argument counts differ"

let s_15 = Base.text_of_utf8 "type_mismatch"

let s_16 = Base.text_of_utf8 "cannot unify "

let s_17 = Base.text_of_utf8 " with "

let s_18 = Base.text_of_utf8 "product_arity"

let s_19 = Base.text_of_utf8 "cannot unify products with different element counts"

let rec (* types.bend:6 *)
f_variable_contains_work : (int) list -> int -> bool -> bool =
fun v_variables v_variable v_found ->
(match (v_variables, v_found) with
| (_, true) ->
true
| ([], false) ->
false
| ((v_head :: v_tail), false) ->
(f_variable_contains_work (v_tail) (v_variable) ((Base.nat_is_eq (v_head) (v_variable)))))
and (* types.bend:29 *)
f_empty : unit -> t_Substitutions =
fun () ->
(Substitutions ([], (NatIndex.f_new ()), (NatIndex.f_new ()), 0))
and (* types.bend:32 *)
f_substitution_count : t_Substitutions -> int =
fun v_substitutions ->
(let (Substitutions (v_history, v_values, v_rows, v_count)) = v_substitutions in
v_count)
and (* types.bend:36 *)
f_substitution_history : t_Substitutions -> (t_Substitution) list =
fun v_substitutions ->
(let (Substitutions (v_history, v_values, v_rows, v_count)) = v_substitutions in
v_history)
and (* types.bend:40 *)
f_append_substitution : t_Substitutions -> t_Substitution -> t_Substitutions =
fun v_substitutions v_substitution ->
(let (Substitutions (v_history, v_values, v_rows, v_count)) = v_substitutions in
(match v_substitution with
| (Substitution (v_variable, v_replacement)) ->
(let v_versions = (NatIndex.f_get (v_values) (v_variable) ([])) in
(Substitutions (((Substitution (v_variable, v_replacement)) :: v_history), (NatIndex.f_set (v_values) (v_variable) (((Version (v_count, v_replacement)) :: v_versions))), v_rows, (Base.nat_add 1 v_count))))
| (RowSubstitution (v_variable, v_replacement)) ->
(let v_versions = (NatIndex.f_get (v_rows) (v_variable) ([])) in
(Substitutions (((RowSubstitution (v_variable, v_replacement)) :: v_history), v_values, (NatIndex.f_set (v_rows) (v_variable) (((Version (v_count, v_replacement)) :: v_versions))), (Base.nat_add 1 v_count))))))
and (* types.bend:50 *)
f_append_substitutions : (t_Substitution) list -> t_Substitutions -> t_Substitutions =
fun v_pending v_previous ->
(match v_pending with
| [] ->
v_previous
| (v_head :: v_tail) ->
(f_append_substitutions (v_tail) ((f_append_substitution (v_previous) (v_head)))))
and (* types.bend:57 *)
f_from_list : (t_Substitution) list -> t_Substitutions =
fun v_substitutions ->
(f_append_substitutions (v_substitutions) ((f_empty ())))
and (* types.bend:62 *)
f_version : 'v. (('v) t_Version) list -> int -> (('v) t_Version) option -> (('v) t_Version) option =
fun v_versions v_cursor v_found ->
(match v_versions with
| [] ->
v_found
| ((Version (v_position, v_replacement)) :: v_tail) ->
(f_version (v_tail) (v_cursor) ((Base.bool_pick ((Base.nat_is_ge (v_position) (v_cursor))) ((Some ((Version (v_position, v_replacement))))) (v_found)))))
and (* types.bend:70 *)
f_value_version : t_Substitutions -> int -> int -> ((M.t_Ty) t_Version) option =
fun v_substitutions v_variable v_cursor ->
(let (Substitutions (v_history, v_values, v_rows, v_count)) = v_substitutions in
(f_version ((NatIndex.f_get (v_values) (v_variable) ([]))) (v_cursor) (None)))
and (* types.bend:74 *)
f_row_version : t_Substitutions -> int -> int -> ((M.t_EffectRow) t_Version) option =
fun v_substitutions v_variable v_cursor ->
(let (Substitutions (v_history, v_values, v_rows, v_count)) = v_substitutions in
(f_version ((NatIndex.f_get (v_rows) (v_variable) ([]))) (v_cursor) (None)))
and (* types.bend:89 *)
f_complexity : unit -> M.t_Diagnostic =
fun () ->
(M.Diagnostic (s_0, s_1, s_2))
and (* types.bend:92 *)
f_first_type : (M.t_Ty) list -> (M.t_Diagnostic, M.t_Ty) Base.result_ =
fun v_types ->
(match v_types with
| (v_head :: []) ->
(Done (v_head))
| _ ->
(Fail ((M.Diagnostic (s_3, s_1, s_4)))))
and (* types.bend:99 *)
f_fresh_parameter_leaf_found : (int) option -> int -> M.t_Ty =
fun v_found v_index ->
(match v_found with
| (Some (v_variable)) ->
(M.VariableTy (v_variable))
| None ->
(M.ParameterTy (v_index)))
and (* types.bend:106 *)
f_fresh_parameter_leaf : int -> (int) NatIndex.t_Index -> M.t_Ty =
fun v_index v_mapping ->
(f_fresh_parameter_leaf_found ((NatIndex.f_find (v_mapping) (v_index))) (v_index))
and (* types.bend:109 *)
f_replace_leaf : M.t_Ty -> t_Replacement -> M.t_Ty =
fun v_ty v_replacement ->
(match (v_ty, v_replacement) with
| ((M.VariableTy (v_found)), (ReplaceVariable (v_index, v_value))) ->
(Base.bool_pick ((Base.nat_is_eq (v_found) (v_index))) (v_value) ((M.VariableTy (v_found))))
| ((M.ParameterTy (v_found)), (ReplaceParameter (v_index, v_value))) ->
(Base.bool_pick ((Base.nat_is_eq (v_found) (v_index))) (v_value) ((M.ParameterTy (v_found))))
| ((M.ParameterTy (v_found)), (FreshParameters (v_mapping))) ->
(f_fresh_parameter_leaf (v_found) (v_mapping))
| ((M.FreeTy (v_scope, v_name)), (ReplaceFree (v_wanted_scope, v_wanted_name, v_value))) ->
(Base.bool_pick ((Base.bool_and ((M.f_name_equal (v_scope) (v_wanted_scope))) ((M.f_name_equal (v_name) (v_wanted_name))))) (v_value) ((M.FreeTy (v_scope, v_name))))
| ((M.FreeTy (v_scope, v_name)), (RelocateFree (v_suffix))) ->
(M.FreeTy ((Base.string_append v_scope v_suffix), v_name))
| (v_other, _) ->
v_other)
and (* types.bend:124 *)
f_replacement_tail : M.t_Ty -> (M.t_Diagnostic, M.t_RowTail) Base.result_ =
fun v_value ->
(match v_value with
| (M.VariableTy (v_index)) ->
(Done ((M.RowVariable (v_index))))
| (M.ParameterTy (v_index)) ->
(Done ((M.RowParameter (v_index))))
| _ ->
(Fail ((M.Diagnostic (s_5, s_1, s_6)))))
and (* types.bend:133 *)
f_rewrite_tail_match : bool -> M.t_RowTail -> M.t_Ty -> (M.t_Diagnostic, M.t_RowTail) Base.result_ =
fun v_same v_original v_value ->
(match v_same with
| false ->
(Done (v_original))
| true ->
(f_replacement_tail (v_value)))
and (* types.bend:140 *)
f_fresh_parameter_tail_found : (int) option -> int -> (M.t_Diagnostic, M.t_RowTail) Base.result_ =
fun v_found v_index ->
(match v_found with
| (Some (v_variable)) ->
(Done ((M.RowVariable (v_variable))))
| None ->
(Done ((M.RowParameter (v_index)))))
and (* types.bend:147 *)
f_fresh_parameter_tail : int -> (int) NatIndex.t_Index -> (M.t_Diagnostic, M.t_RowTail) Base.result_ =
fun v_index v_mapping ->
(f_fresh_parameter_tail_found ((NatIndex.f_find (v_mapping) (v_index))) (v_index))
and (* types.bend:150 *)
f_rewrite_tail : M.t_RowTail -> t_Replacement -> (M.t_Diagnostic, M.t_RowTail) Base.result_ =
fun v_tail v_replacement ->
(match (v_tail, v_replacement) with
| ((M.RowVariable (v_found)), (ReplaceVariable (v_index, v_value))) ->
(f_rewrite_tail_match ((Base.nat_is_eq (v_found) (v_index))) ((M.RowVariable (v_found))) (v_value))
| ((M.RowParameter (v_found)), (ReplaceParameter (v_index, v_value))) ->
(f_rewrite_tail_match ((Base.nat_is_eq (v_found) (v_index))) ((M.RowParameter (v_found))) (v_value))
| ((M.RowParameter (v_found)), (FreshParameters (v_mapping))) ->
(f_fresh_parameter_tail (v_found) (v_mapping))
| ((M.FreeRow (v_scope, v_name)), (ReplaceFree (v_wanted_scope, v_wanted_name, v_value))) ->
(f_rewrite_tail_match ((Base.bool_and ((M.f_name_equal (v_scope) (v_wanted_scope))) ((M.f_name_equal (v_name) (v_wanted_name))))) ((M.FreeRow (v_scope, v_name))) (v_value))
| ((M.FreeRow (v_scope, v_name)), (RelocateFree (v_suffix))) ->
(Done ((M.FreeRow ((Base.string_append v_scope v_suffix), v_name))))
| (v_original, _) ->
(Done (v_original)))
and (* types.bend:165 *)
f_rewrite_row : M.t_EffectRow -> t_Replacement -> (M.t_Diagnostic, M.t_EffectRow) Base.result_ =
fun v_row v_replacement ->
(let (M.EffectRow (v_operations, v_tail)) = v_row in
(match (f_rewrite_tail (v_tail) (v_replacement)) with
| Fail __error -> Fail __error
| Done v_rewritten ->
(Done ((M.EffectRow (v_operations, v_rewritten))))))
and (* types.bend:171 *)
f_rewrite : int -> t_TypeWork -> t_Replacement -> (M.t_Diagnostic, (M.t_Ty) list) Base.result_ =
fun v_fuel v_work v_replacement ->
(match (v_fuel, v_work) with
| (0, _) ->
(Fail ((f_complexity ())))
| (__nat_1, (OneType ((M.FunctionTy (v_parameter, v_result, v_effects))))) when __nat_1 >= 1 ->
(let v_rest = (__nat_1 - 1) in
(match (f_rewrite (v_rest) ((OneType (v_parameter))) (v_replacement)) with
| Fail __error -> Fail __error
| Done v_ps ->
(match (f_rewrite (v_rest) ((OneType (v_result))) (v_replacement)) with
| Fail __error -> Fail __error
| Done v_rs ->
(match (f_first_type (v_ps)) with
| Fail __error -> Fail __error
| Done v_p ->
(match (f_first_type (v_rs)) with
| Fail __error -> Fail __error
| Done v_r ->
(match (f_rewrite_row (v_effects) (v_replacement)) with
| Fail __error -> Fail __error
| Done v_row ->
(Done ([(M.FunctionTy (v_p, v_r, v_row))]))))))))
| (__nat_2, (OneType ((M.StateProviderTy (v_read, v_write, v_state))))) when __nat_2 >= 1 ->
(let v_rest = (__nat_2 - 1) in
(match (f_rewrite (v_rest) ((OneType (v_state))) (v_replacement)) with
| Fail __error -> Fail __error
| Done v_values ->
(match (f_first_type (v_values)) with
| Fail __error -> Fail __error
| Done v_value ->
(Done ([(M.StateProviderTy (v_read, v_write, v_value))])))))
| (__nat_3, (OneType ((M.ProviderTy (v_identity, v_effects))))) when __nat_3 >= 1 ->
(let v_rest = (__nat_3 - 1) in
(match (f_rewrite_row (v_effects) (v_replacement)) with
| Fail __error -> Fail __error
| Done v_row ->
(Done ([(M.ProviderTy (v_identity, v_row))]))))
| (__nat_4, (OneType ((M.AppliedTy (v_identity, v_arguments))))) when __nat_4 >= 1 ->
(let v_rest = (__nat_4 - 1) in
(match (f_rewrite (v_rest) ((ManyTypes (v_arguments))) (v_replacement)) with
| Fail __error -> Fail __error
| Done v_xs ->
(Done ([(M.AppliedTy (v_identity, v_xs))]))))
| (__nat_5, (OneType ((M.ProductTy (v_elements))))) when __nat_5 >= 1 ->
(let v_rest = (__nat_5 - 1) in
(match (f_rewrite (v_rest) ((ManyTypes (v_elements))) (v_replacement)) with
| Fail __error -> Fail __error
| Done v_xs ->
(Done ([(M.ProductTy (v_xs))]))))
| (__nat_6, (OneType ((M.ArrayTy (v_element))))) when __nat_6 >= 1 ->
(let v_rest = (__nat_6 - 1) in
(match (f_rewrite (v_rest) ((OneType (v_element))) (v_replacement)) with
| Fail __error -> Fail __error
| Done v_xs ->
(match (f_first_type (v_xs)) with
| Fail __error -> Fail __error
| Done v_value ->
(Done ([(M.ArrayTy (v_value))])))))
| (__nat_7, (OneType (v_other))) when __nat_7 >= 1 ->
(let v_rest = (__nat_7 - 1) in
(Done ([(f_replace_leaf (v_other) (v_replacement))])))
| (__nat_8, (ManyTypes ([]))) when __nat_8 >= 1 ->
(let v_rest = (__nat_8 - 1) in
(Done ([])))
| (__nat_9, (ManyTypes ((v_head :: v_tail)))) when __nat_9 >= 1 ->
(let v_rest = (__nat_9 - 1) in
(match (f_rewrite (v_rest) ((OneType (v_head))) (v_replacement)) with
| Fail __error -> Fail __error
| Done v_hs ->
(match (f_first_type (v_hs)) with
| Fail __error -> Fail __error
| Done v_h ->
(match (f_rewrite (v_rest) ((ManyTypes (v_tail))) (v_replacement)) with
| Fail __error -> Fail __error
| Done v_ts ->
(Done ((v_h :: v_ts))))))))
and (* types.bend:216 *)
f_replace : M.t_Ty -> int -> M.t_Ty -> (M.t_Diagnostic, M.t_Ty) Base.result_ =
fun v_ty v_variable v_replacement ->
(match (f_rewrite ((Base.nat_mul (256) (256))) ((OneType (v_ty))) ((ReplaceVariable (v_variable, v_replacement)))) with
| Fail __error -> Fail __error
| Done v_xs ->
(f_first_type (v_xs)))
and (* types.bend:228 *)
f_renaming_work : (int) list -> int -> int -> (int) NatIndex.t_Index -> bool -> t_Renaming =
fun v_variables v_start v_next v_mapping v_simultaneous ->
(match v_variables with
| [] ->
(Renaming (v_mapping, v_next, v_simultaneous))
| (v_head :: v_tail) ->
(let v_unused = (Base.maybe_is_none ((NatIndex.f_find (v_mapping) (v_head)))) in
(let v_safe = (Base.bool_and (v_simultaneous) ((Base.bool_and ((Base.nat_is_lt (v_head) (v_start))) (v_unused)))) in
(f_renaming_work (v_tail) (v_start) ((Base.nat_add 1 v_next)) ((NatIndex.f_set (v_mapping) (v_head) (v_next))) (v_safe)))))
and (* types.bend:237 *)
f_renaming : (int) list -> int -> t_Renaming =
fun v_variables v_next ->
(f_renaming_work (v_variables) (v_next) (v_next) ((NatIndex.f_new ())) (true))
and (* types.bend:240 *)
f_renamed_next : t_Renaming -> int =
fun v_value ->
(let (Renaming (v_mapping, v_next, v_simultaneous)) = v_value in
v_next)
and (* types.bend:244 *)
f_renaming_is_simultaneous : t_Renaming -> bool =
fun v_value ->
(let (Renaming (v_mapping, v_next, v_simultaneous)) = v_value in
v_simultaneous)
and (* types.bend:248 *)
f_renamed_variable : (int) NatIndex.t_Index -> int -> int =
fun v_mapping v_original ->
(NatIndex.f_get (v_mapping) (v_original) (v_original))
and (* types.bend:255 *)
f_renamed_type_found : (int) option -> int -> t_VariableKind -> M.t_Ty =
fun v_found v_index v_kind ->
(match (v_found, v_kind) with
| (None, _) ->
(M.VariableTy (v_index))
| ((Some (v_fresh)), FreshVariables) ->
(M.VariableTy (v_fresh))
| ((Some (v_parameter)), SchemeParameters) ->
(M.ParameterTy (v_parameter)))
and (* types.bend:264 *)
f_renamed_type : int -> (int) NatIndex.t_Index -> t_VariableKind -> M.t_Ty =
fun v_index v_mapping v_kind ->
(f_renamed_type_found ((NatIndex.f_find (v_mapping) (v_index))) (v_index) (v_kind))
and (* types.bend:267 *)
f_renamed_tail_found : (int) option -> int -> t_VariableKind -> M.t_RowTail =
fun v_found v_index v_kind ->
(match (v_found, v_kind) with
| (None, _) ->
(M.RowVariable (v_index))
| ((Some (v_fresh)), FreshVariables) ->
(M.RowVariable (v_fresh))
| ((Some (v_parameter)), SchemeParameters) ->
(M.RowParameter (v_parameter)))
and (* types.bend:276 *)
f_rename_tail_kind : M.t_RowTail -> (int) NatIndex.t_Index -> t_VariableKind -> M.t_RowTail =
fun v_tail v_mapping v_kind ->
(match v_tail with
| (M.RowVariable (v_index)) ->
(f_renamed_tail_found ((NatIndex.f_find (v_mapping) (v_index))) (v_index) (v_kind))
| v_other ->
v_other)
and (* types.bend:283 *)
f_rename_tail : M.t_RowTail -> (int) NatIndex.t_Index -> M.t_RowTail =
fun v_tail v_mapping ->
(f_rename_tail_kind (v_tail) (v_mapping) (FreshVariables))
and (* types.bend:286 *)
f_rename_row_kind : M.t_EffectRow -> (int) NatIndex.t_Index -> t_VariableKind -> M.t_EffectRow =
fun v_row v_mapping v_kind ->
(let (M.EffectRow (v_operations, v_tail)) = v_row in
(M.EffectRow (v_operations, (f_rename_tail_kind (v_tail) (v_mapping) (v_kind)))))
and (* types.bend:290 *)
f_rename_row : M.t_EffectRow -> (int) NatIndex.t_Index -> M.t_EffectRow =
fun v_row v_mapping ->
(f_rename_row_kind (v_row) (v_mapping) (FreshVariables))
and (* types.bend:295 *)
f_rename_work : int -> t_TypeWork -> (int) NatIndex.t_Index -> t_VariableKind -> (M.t_Diagnostic, (M.t_Ty) list) Base.result_ =
fun v_fuel v_work v_mapping v_kind ->
(match (v_fuel, v_work) with
| (0, _) ->
(Fail ((f_complexity ())))
| (__nat_10, (OneType ((M.VariableTy (v_index))))) when __nat_10 >= 1 ->
(let v_rest = (__nat_10 - 1) in
(Done ([(f_renamed_type (v_index) (v_mapping) (v_kind))])))
| (__nat_11, (OneType ((M.FunctionTy (v_parameter, v_result, v_effects))))) when __nat_11 >= 1 ->
(let v_rest = (__nat_11 - 1) in
(match (f_rename_work (v_rest) ((OneType (v_parameter))) (v_mapping) (v_kind)) with
| Fail __error -> Fail __error
| Done v_ps ->
(match (f_rename_work (v_rest) ((OneType (v_result))) (v_mapping) (v_kind)) with
| Fail __error -> Fail __error
| Done v_rs ->
(match (f_first_type (v_ps)) with
| Fail __error -> Fail __error
| Done v_p ->
(match (f_first_type (v_rs)) with
| Fail __error -> Fail __error
| Done v_r ->
(Done ([(M.FunctionTy (v_p, v_r, (f_rename_row_kind (v_effects) (v_mapping) (v_kind))))])))))))
| (__nat_12, (OneType ((M.StateProviderTy (v_read, v_write, v_state))))) when __nat_12 >= 1 ->
(let v_rest = (__nat_12 - 1) in
(match (f_rename_work (v_rest) ((OneType (v_state))) (v_mapping) (v_kind)) with
| Fail __error -> Fail __error
| Done v_values ->
(match (f_first_type (v_values)) with
| Fail __error -> Fail __error
| Done v_value ->
(Done ([(M.StateProviderTy (v_read, v_write, v_value))])))))
| (__nat_13, (OneType ((M.ProviderTy (v_identity, v_effects))))) when __nat_13 >= 1 ->
(let v_rest = (__nat_13 - 1) in
(Done ([(M.ProviderTy (v_identity, (f_rename_row_kind (v_effects) (v_mapping) (v_kind))))])))
| (__nat_14, (OneType ((M.AppliedTy (v_identity, v_arguments))))) when __nat_14 >= 1 ->
(let v_rest = (__nat_14 - 1) in
(match (f_rename_work (v_rest) ((ManyTypes (v_arguments))) (v_mapping) (v_kind)) with
| Fail __error -> Fail __error
| Done v_xs ->
(Done ([(M.AppliedTy (v_identity, v_xs))]))))
| (__nat_15, (OneType ((M.ProductTy (v_elements))))) when __nat_15 >= 1 ->
(let v_rest = (__nat_15 - 1) in
(match (f_rename_work (v_rest) ((ManyTypes (v_elements))) (v_mapping) (v_kind)) with
| Fail __error -> Fail __error
| Done v_xs ->
(Done ([(M.ProductTy (v_xs))]))))
| (__nat_16, (OneType ((M.ArrayTy (v_element))))) when __nat_16 >= 1 ->
(let v_rest = (__nat_16 - 1) in
(match (f_rename_work (v_rest) ((OneType (v_element))) (v_mapping) (v_kind)) with
| Fail __error -> Fail __error
| Done v_xs ->
(match (f_first_type (v_xs)) with
| Fail __error -> Fail __error
| Done v_value ->
(Done ([(M.ArrayTy (v_value))])))))
| (__nat_17, (OneType (v_other))) when __nat_17 >= 1 ->
(let v_rest = (__nat_17 - 1) in
(Done ([v_other])))
| (__nat_18, (ManyTypes ([]))) when __nat_18 >= 1 ->
(let v_rest = (__nat_18 - 1) in
(Done ([])))
| (__nat_19, (ManyTypes ((v_head :: v_tail)))) when __nat_19 >= 1 ->
(let v_rest = (__nat_19 - 1) in
(match (f_rename_work (v_rest) ((OneType (v_head))) (v_mapping) (v_kind)) with
| Fail __error -> Fail __error
| Done v_hs ->
(match (f_first_type (v_hs)) with
| Fail __error -> Fail __error
| Done v_h ->
(match (f_rename_work (v_rest) ((ManyTypes (v_tail))) (v_mapping) (v_kind)) with
| Fail __error -> Fail __error
| Done v_ts ->
(Done ((v_h :: v_ts))))))))
and (* types.bend:339 *)
f_rename_type : M.t_Ty -> (int) NatIndex.t_Index -> (M.t_Diagnostic, M.t_Ty) Base.result_ =
fun v_ty v_mapping ->
(match (f_rename_work ((Base.nat_mul (256) (256))) ((OneType (v_ty))) (v_mapping) (FreshVariables)) with
| Fail __error -> Fail __error
| Done v_xs ->
(f_first_type (v_xs)))
and (* types.bend:346 *)
f_parameter_mapping_next : (int) option -> int -> int -> (int) NatIndex.t_Index -> (int) NatIndex.t_Index =
fun v_found v_head v_index v_mapping ->
(match v_found with
| (Some (v_previous)) ->
v_mapping
| None ->
(NatIndex.f_set (v_mapping) (v_head) (v_index)))
and (* types.bend:353 *)
f_parameter_mapping_work : (int) list -> int -> (int) NatIndex.t_Index -> (int) NatIndex.t_Index =
fun v_variables v_index v_mapping ->
(match v_variables with
| [] ->
v_mapping
| (v_head :: v_tail) ->
(f_parameter_mapping_work (v_tail) ((Base.nat_add 1 v_index)) ((f_parameter_mapping_next ((NatIndex.f_find (v_mapping) (v_head))) (v_head) (v_index) (v_mapping)))))
and (* types.bend:360 *)
f_parameter_mapping : (int) list -> int -> (int) NatIndex.t_Index =
fun v_variables v_index ->
(f_parameter_mapping_work (v_variables) (v_index) ((NatIndex.f_new ())))
and (* types.bend:363 *)
f_parameterize_type : M.t_Ty -> (int) NatIndex.t_Index -> (M.t_Diagnostic, M.t_Ty) Base.result_ =
fun v_ty v_mapping ->
(match (f_rename_work ((Base.nat_mul (256) (256))) ((OneType (v_ty))) (v_mapping) (SchemeParameters)) with
| Fail __error -> Fail __error
| Done v_xs ->
(f_first_type (v_xs)))
and (* types.bend:368 *)
f_parameters : (M.t_Ty) list -> int -> M.t_Ty -> (M.t_Diagnostic, M.t_Ty) Base.result_ =
fun v_arguments v_index v_ty ->
(match v_arguments with
| [] ->
(Done (v_ty))
| (v_head :: v_tail) ->
(match (f_rewrite ((Base.nat_mul (256) (256))) ((OneType (v_ty))) ((ReplaceParameter (v_index, v_head)))) with
| Fail __error -> Fail __error
| Done v_xs ->
(match (f_first_type (v_xs)) with
| Fail __error -> Fail __error
| Done v_next ->
(f_parameters (v_tail) ((Base.nat_add 1 v_index)) (v_next)))))
and (* types.bend:380 *)
f_resolve_row_next : ((M.t_EffectRow) t_Version) option -> M.t_EffectRow -> (int -> (M.t_EffectRow -> M.t_EffectRow)) -> M.t_EffectRow =
fun v_found v_row v_next ->
(match v_found with
| None ->
v_row
| (Some ((Version (v_position, v_replacement)))) ->
(v_next ((Base.nat_add 1 v_position)) ((R.f_prepend ((R.f_row_operations (v_row))) (v_replacement)))))
and (* types.bend:387 *)
f_resolve_row_work : t_Substitutions -> int -> int -> M.t_EffectRow -> M.t_EffectRow =
fun v_substitutions v_links v_cursor v_row ->
(match (v_links, v_row) with
| (__nat_20, (M.EffectRow (v_labels, (M.RowVariable (v_index))))) when __nat_20 >= 1 ->
(let v_remaining = (__nat_20 - 1) in
(f_resolve_row_next ((f_row_version (v_substitutions) (v_index) (v_cursor))) ((M.EffectRow (v_labels, (M.RowVariable (v_index))))) ((fun v_position ->
(fun v_replacement ->
(f_resolve_row_work (v_substitutions) (v_remaining) (v_position) (v_replacement)))))))
| (_, v_row) ->
v_row)
and (* types.bend:394 *)
f_resolve_row_at : t_Substitutions -> M.t_EffectRow -> int -> M.t_EffectRow =
fun v_substitutions v_row v_cursor ->
(f_resolve_row_work (v_substitutions) ((f_substitution_count (v_substitutions))) (v_cursor) (v_row))
and (* types.bend:397 *)
f_resolve_row : t_Substitutions -> M.t_EffectRow -> M.t_EffectRow =
fun v_substitutions v_row ->
(f_resolve_row_at (v_substitutions) (v_row) (0))
and (* types.bend:400 *)
f_resolve_variable : ((M.t_Ty) t_Version) option -> int -> (int -> (M.t_Ty -> (M.t_Diagnostic, (M.t_Ty) list) Base.result_)) -> (M.t_Diagnostic, (M.t_Ty) list) Base.result_ =
fun v_found v_index v_next ->
(match v_found with
| None ->
(Done ([(M.VariableTy (v_index))]))
| (Some ((Version (v_position, v_replacement)))) ->
(v_next ((Base.nat_add 1 v_position)) (v_replacement)))
and (* types.bend:407 *)
f_resolve_accumulated : int -> int -> bool -> t_Substitutions -> int -> t_TypeWork -> (M.t_Ty) list -> (M.t_Diagnostic, (M.t_Ty) list) Base.result_ =
fun v_fuel v_links v_exhausted v_substitutions v_cursor v_work v_reversed ->
(match (v_fuel, v_links, v_exhausted, v_work) with
| (_, _, true, (OneType (v_ty))) ->
(Done ([v_ty]))
| (_, _, true, (ManyTypes (v_types))) ->
(Done ((Base.list_append ((Base.list_reverse (v_reversed))) (v_types))))
| (0, _, false, _) ->
(Fail ((f_complexity ())))
| (__nat_21, 0, false, (OneType ((M.VariableTy (v_index))))) when __nat_21 >= 1 ->
(let v_rest = (__nat_21 - 1) in
(Fail ((M.Diagnostic (s_3, s_7, s_8)))))
| (__nat_22, __nat_23, false, (OneType ((M.VariableTy (v_index))))) when __nat_22 >= 1 && __nat_23 >= 1 ->
(let v_rest = (__nat_22 - 1) in
(let v_remaining = (__nat_23 - 1) in
(f_resolve_variable ((f_value_version (v_substitutions) (v_index) (v_cursor))) (v_index) ((fun v_position ->
(fun v_replacement ->
(f_resolve_accumulated ((Base.nat_add 1 v_rest)) (v_remaining) ((Base.nat_is_ge (v_position) ((f_substitution_count (v_substitutions))))) (v_substitutions) (v_position) ((OneType (v_replacement))) ([]))))))))
| (__nat_24, _, false, (OneType ((M.FunctionTy (v_parameter, v_result, v_effects))))) when __nat_24 >= 1 ->
(let v_rest = (__nat_24 - 1) in
(match (f_resolve_accumulated (v_rest) (v_links) (false) (v_substitutions) (v_cursor) ((OneType (v_parameter))) ([])) with
| Fail __error -> Fail __error
| Done v_ps ->
(match (f_resolve_accumulated (v_rest) (v_links) (false) (v_substitutions) (v_cursor) ((OneType (v_result))) ([])) with
| Fail __error -> Fail __error
| Done v_rs ->
(match (f_first_type (v_ps)) with
| Fail __error -> Fail __error
| Done v_p ->
(match (f_first_type (v_rs)) with
| Fail __error -> Fail __error
| Done v_r ->
(Done ([(M.FunctionTy (v_p, v_r, (f_resolve_row_at (v_substitutions) (v_effects) (v_cursor))))])))))))
| (__nat_25, _, false, (OneType ((M.StateProviderTy (v_read, v_write, v_state))))) when __nat_25 >= 1 ->
(let v_rest = (__nat_25 - 1) in
(match (f_resolve_accumulated (v_rest) (v_links) (false) (v_substitutions) (v_cursor) ((OneType (v_state))) ([])) with
| Fail __error -> Fail __error
| Done v_values ->
(match (f_first_type (v_values)) with
| Fail __error -> Fail __error
| Done v_value ->
(Done ([(M.StateProviderTy (v_read, v_write, v_value))])))))
| (__nat_26, _, false, (OneType ((M.ProviderTy (v_identity, v_effects))))) when __nat_26 >= 1 ->
(let v_rest = (__nat_26 - 1) in
(Done ([(M.ProviderTy (v_identity, (f_resolve_row_at (v_substitutions) (v_effects) (v_cursor))))])))
| (__nat_27, _, false, (OneType ((M.AppliedTy (v_identity, v_arguments))))) when __nat_27 >= 1 ->
(let v_rest = (__nat_27 - 1) in
(match (f_resolve_accumulated (v_rest) (v_links) (false) (v_substitutions) (v_cursor) ((ManyTypes (v_arguments))) ([])) with
| Fail __error -> Fail __error
| Done v_xs ->
(Done ([(M.AppliedTy (v_identity, v_xs))]))))
| (__nat_28, _, false, (OneType ((M.ProductTy (v_elements))))) when __nat_28 >= 1 ->
(let v_rest = (__nat_28 - 1) in
(match (f_resolve_accumulated (v_rest) (v_links) (false) (v_substitutions) (v_cursor) ((ManyTypes (v_elements))) ([])) with
| Fail __error -> Fail __error
| Done v_xs ->
(Done ([(M.ProductTy (v_xs))]))))
| (__nat_29, _, false, (OneType ((M.ArrayTy (v_element))))) when __nat_29 >= 1 ->
(let v_rest = (__nat_29 - 1) in
(match (f_resolve_accumulated (v_rest) (v_links) (false) (v_substitutions) (v_cursor) ((OneType (v_element))) ([])) with
| Fail __error -> Fail __error
| Done v_xs ->
(match (f_first_type (v_xs)) with
| Fail __error -> Fail __error
| Done v_value ->
(Done ([(M.ArrayTy (v_value))])))))
| (__nat_30, _, false, (OneType (v_other))) when __nat_30 >= 1 ->
(let v_rest = (__nat_30 - 1) in
(Done ([v_other])))
| (__nat_31, _, false, (ManyTypes ([]))) when __nat_31 >= 1 ->
(let v_rest = (__nat_31 - 1) in
(Done ((Base.list_reverse (v_reversed)))))
| (__nat_32, _, false, (ManyTypes ((v_head :: v_tail)))) when __nat_32 >= 1 ->
(let v_rest = (__nat_32 - 1) in
(match (f_resolve_accumulated (v_rest) (v_links) (false) (v_substitutions) (v_cursor) ((OneType (v_head))) ([])) with
| Fail __error -> Fail __error
| Done v_hs ->
(match (f_first_type (v_hs)) with
| Fail __error -> Fail __error
| Done v_h ->
(f_resolve_accumulated (v_rest) (v_links) (false) (v_substitutions) (v_cursor) ((ManyTypes (v_tail))) ((v_h :: v_reversed)))))))
and (* types.bend:457 *)
f_resolve_work_reference : t_Substitutions -> int -> t_TypeWork -> (M.t_Diagnostic, (M.t_Ty) list) Base.result_ =
fun v_substitutions v_fuel v_work ->
(f_resolve_accumulated (v_fuel) ((f_substitution_count (v_substitutions))) ((Base.nat_is_eq ((f_substitution_count (v_substitutions))) (0))) (v_substitutions) (0) (v_work) ([]))
and (* types.bend:477 *)
f_malformed_flat : unit -> M.t_Diagnostic =
fun () ->
(M.Diagnostic (s_3, s_1, s_4))
and (* types.bend:480 *)
f_flat_variable : ((M.t_Ty) t_Version) option -> int -> int -> int -> t_Substitutions -> (t_FlatFrame) list -> t_FlatControl =
fun v_found v_index v_fuel v_remaining v_substitutions v_frames ->
(match v_found with
| None ->
(FlatReturn ((FlatOne ((M.VariableTy (v_index)))), v_frames))
| (Some ((Version (v_position, v_replacement)))) ->
(let v_next_cursor = (Base.nat_add 1 v_position) in
(FlatVisit (v_fuel, v_remaining, (Base.nat_is_ge (v_next_cursor) ((f_substitution_count (v_substitutions)))), v_next_cursor, (OneType (v_replacement)), [], v_frames))))
and (* types.bend:488 *)
f_flat_function : int -> int -> int -> M.t_Ty -> M.t_Ty -> M.t_EffectRow -> (t_FlatFrame) list -> t_FlatControl =
fun v_fuel v_links v_cursor v_parameter v_result v_effects v_frames ->
(FlatVisit (v_fuel, v_links, false, v_cursor, (OneType (v_parameter)), [], ((AfterFunctionParameter (v_result, v_effects, v_fuel, v_links, v_cursor)) :: v_frames)))
and (* types.bend:491 *)
f_flat_many : int -> int -> int -> M.t_Ty -> (M.t_Ty) list -> (M.t_Ty) list -> (t_FlatFrame) list -> t_FlatControl =
fun v_fuel v_links v_cursor v_head v_tail v_reversed v_frames ->
(FlatVisit (v_fuel, v_links, false, v_cursor, (OneType (v_head)), [], ((AfterManyHead (v_tail, v_reversed, v_fuel, v_links, v_cursor)) :: v_frames)))
and (* types.bend:494 *)
f_flat_step : int -> t_Substitutions -> t_FlatControl -> ((M.t_Diagnostic, (M.t_Ty) list) Base.result_) option =
fun v_steps v_substitutions v_control ->
(match (v_steps, v_control) with
| (0, _) ->
None
| (__nat_33, (FlatReturn ((FlatOne (v_value)), []))) when __nat_33 >= 1 ->
(let v_rest = (__nat_33 - 1) in
(Some ((Done ([v_value])))))
| (__nat_34, (FlatReturn ((FlatMany (v_values)), []))) when __nat_34 >= 1 ->
(let v_rest = (__nat_34 - 1) in
(Some ((Done (v_values)))))
| (__nat_35, (FlatReturn ((FlatOne (v_parameter)), ((AfterFunctionParameter (v_result, v_effects, v_fuel, v_links, v_cursor)) :: v_frames)))) when __nat_35 >= 1 ->
(let v_rest = (__nat_35 - 1) in
(f_flat_step (v_rest) (v_substitutions) ((FlatVisit (v_fuel, v_links, false, v_cursor, (OneType (v_result)), [], ((AfterFunctionResult (v_parameter, v_effects, v_cursor)) :: v_frames))))))
| (__nat_36, (FlatReturn ((FlatOne (v_result)), ((AfterFunctionResult (v_parameter, v_effects, v_cursor)) :: v_frames)))) when __nat_36 >= 1 ->
(let v_rest = (__nat_36 - 1) in
(f_flat_step (v_rest) (v_substitutions) ((FlatReturn ((FlatOne ((M.FunctionTy (v_parameter, v_result, (f_resolve_row_at (v_substitutions) (v_effects) (v_cursor)))))), v_frames)))))
| (__nat_37, (FlatReturn ((FlatOne (v_state)), ((AfterStateProvider (v_read, v_write)) :: v_frames)))) when __nat_37 >= 1 ->
(let v_rest = (__nat_37 - 1) in
(f_flat_step (v_rest) (v_substitutions) ((FlatReturn ((FlatOne ((M.StateProviderTy (v_read, v_write, v_state)))), v_frames)))))
| (__nat_38, (FlatReturn ((FlatMany (v_arguments)), ((AfterProviderArguments (v_identity)) :: v_frames)))) when __nat_38 >= 1 ->
(let v_rest = (__nat_38 - 1) in
(f_flat_step (v_rest) (v_substitutions) ((FlatReturn ((FlatOne ((M.AppliedTy (v_identity, v_arguments)))), v_frames)))))
| (__nat_39, (FlatReturn ((FlatMany (v_elements)), (AfterProductElements :: v_frames)))) when __nat_39 >= 1 ->
(let v_rest = (__nat_39 - 1) in
(f_flat_step (v_rest) (v_substitutions) ((FlatReturn ((FlatOne ((M.ProductTy (v_elements)))), v_frames)))))
| (__nat_40, (FlatReturn ((FlatOne (v_element)), (AfterArrayElement :: v_frames)))) when __nat_40 >= 1 ->
(let v_rest = (__nat_40 - 1) in
(f_flat_step (v_rest) (v_substitutions) ((FlatReturn ((FlatOne ((M.ArrayTy (v_element)))), v_frames)))))
| (__nat_41, (FlatReturn ((FlatOne (v_head)), ((AfterManyHead (v_tail, v_reversed, v_fuel, v_links, v_cursor)) :: v_frames)))) when __nat_41 >= 1 ->
(let v_rest = (__nat_41 - 1) in
(f_flat_step (v_rest) (v_substitutions) ((FlatVisit (v_fuel, v_links, false, v_cursor, (ManyTypes (v_tail)), (v_head :: v_reversed), v_frames)))))
| (__nat_42, (FlatReturn (v_value, v_frames))) when __nat_42 >= 1 ->
(let v_rest = (__nat_42 - 1) in
(Some ((Fail ((f_malformed_flat ()))))))
| (__nat_43, (FlatVisit (v_fuel, v_links, true, v_cursor, (OneType (v_ty)), v_reversed, v_frames))) when __nat_43 >= 1 ->
(let v_rest = (__nat_43 - 1) in
(f_flat_step (v_rest) (v_substitutions) ((FlatReturn ((FlatOne (v_ty)), v_frames)))))
| (__nat_44, (FlatVisit (v_fuel, v_links, true, v_cursor, (ManyTypes (v_types)), v_reversed, v_frames))) when __nat_44 >= 1 ->
(let v_rest = (__nat_44 - 1) in
(f_flat_step (v_rest) (v_substitutions) ((FlatReturn ((FlatMany ((Base.list_append ((Base.list_reverse (v_reversed))) (v_types)))), v_frames)))))
| (__nat_45, (FlatVisit (0, v_links, false, v_cursor, v_work, v_reversed, v_frames))) when __nat_45 >= 1 ->
(let v_rest = (__nat_45 - 1) in
(Some ((Fail ((f_complexity ()))))))
| (__nat_46, (FlatVisit (__nat_47, 0, false, v_cursor, (OneType ((M.VariableTy (v_index)))), v_reversed, v_frames))) when __nat_46 >= 1 && __nat_47 >= 1 ->
(let v_rest = (__nat_46 - 1) in
(let v_fuel = (__nat_47 - 1) in
(Some ((Fail ((M.Diagnostic (s_3, s_7, s_8))))))))
| (__nat_48, (FlatVisit (__nat_49, __nat_50, false, v_cursor, (OneType ((M.VariableTy (v_index)))), v_reversed, v_frames))) when __nat_48 >= 1 && __nat_49 >= 1 && __nat_50 >= 1 ->
(let v_rest = (__nat_48 - 1) in
(let v_fuel = (__nat_49 - 1) in
(let v_links = (__nat_50 - 1) in
(f_flat_step (v_rest) (v_substitutions) ((f_flat_variable ((f_value_version (v_substitutions) (v_index) (v_cursor))) (v_index) ((Base.nat_add 1 v_fuel)) (v_links) (v_substitutions) (v_frames)))))))
| (__nat_51, (FlatVisit (__nat_52, v_links, false, v_cursor, (OneType ((M.FunctionTy (v_parameter, v_result, v_effects)))), v_reversed, v_frames))) when __nat_51 >= 1 && __nat_52 >= 1 ->
(let v_rest = (__nat_51 - 1) in
(let v_fuel = (__nat_52 - 1) in
(f_flat_step (v_rest) (v_substitutions) ((f_flat_function (v_fuel) (v_links) (v_cursor) (v_parameter) (v_result) (v_effects) (v_frames))))))
| (__nat_53, (FlatVisit (__nat_54, v_links, false, v_cursor, (OneType ((M.StateProviderTy (v_read, v_write, v_state)))), v_reversed, v_frames))) when __nat_53 >= 1 && __nat_54 >= 1 ->
(let v_rest = (__nat_53 - 1) in
(let v_fuel = (__nat_54 - 1) in
(f_flat_step (v_rest) (v_substitutions) ((FlatVisit (v_fuel, v_links, false, v_cursor, (OneType (v_state)), [], ((AfterStateProvider (v_read, v_write)) :: v_frames)))))))
| (__nat_55, (FlatVisit (__nat_56, v_links, false, v_cursor, (OneType ((M.ProviderTy (v_identity, v_effects)))), v_reversed, v_frames))) when __nat_55 >= 1 && __nat_56 >= 1 ->
(let v_rest = (__nat_55 - 1) in
(let v_fuel = (__nat_56 - 1) in
(f_flat_step (v_rest) (v_substitutions) ((FlatReturn ((FlatOne ((M.ProviderTy (v_identity, (f_resolve_row_at (v_substitutions) (v_effects) (v_cursor)))))), v_frames))))))
| (__nat_57, (FlatVisit (__nat_58, v_links, false, v_cursor, (OneType ((M.AppliedTy (v_identity, v_arguments)))), v_reversed, v_frames))) when __nat_57 >= 1 && __nat_58 >= 1 ->
(let v_rest = (__nat_57 - 1) in
(let v_fuel = (__nat_58 - 1) in
(f_flat_step (v_rest) (v_substitutions) ((FlatVisit (v_fuel, v_links, false, v_cursor, (ManyTypes (v_arguments)), [], ((AfterProviderArguments (v_identity)) :: v_frames)))))))
| (__nat_59, (FlatVisit (__nat_60, v_links, false, v_cursor, (OneType ((M.ProductTy (v_elements)))), v_reversed, v_frames))) when __nat_59 >= 1 && __nat_60 >= 1 ->
(let v_rest = (__nat_59 - 1) in
(let v_fuel = (__nat_60 - 1) in
(f_flat_step (v_rest) (v_substitutions) ((FlatVisit (v_fuel, v_links, false, v_cursor, (ManyTypes (v_elements)), [], (AfterProductElements :: v_frames)))))))
| (__nat_61, (FlatVisit (__nat_62, v_links, false, v_cursor, (OneType ((M.ArrayTy (v_element)))), v_reversed, v_frames))) when __nat_61 >= 1 && __nat_62 >= 1 ->
(let v_rest = (__nat_61 - 1) in
(let v_fuel = (__nat_62 - 1) in
(f_flat_step (v_rest) (v_substitutions) ((FlatVisit (v_fuel, v_links, false, v_cursor, (OneType (v_element)), [], (AfterArrayElement :: v_frames)))))))
| (__nat_63, (FlatVisit (__nat_64, v_links, false, v_cursor, (OneType (v_other)), v_reversed, v_frames))) when __nat_63 >= 1 && __nat_64 >= 1 ->
(let v_rest = (__nat_63 - 1) in
(let v_fuel = (__nat_64 - 1) in
(f_flat_step (v_rest) (v_substitutions) ((FlatReturn ((FlatOne (v_other)), v_frames))))))
| (__nat_65, (FlatVisit (__nat_66, v_links, false, v_cursor, (ManyTypes ([])), v_reversed, v_frames))) when __nat_65 >= 1 && __nat_66 >= 1 ->
(let v_rest = (__nat_65 - 1) in
(let v_fuel = (__nat_66 - 1) in
(f_flat_step (v_rest) (v_substitutions) ((FlatReturn ((FlatMany ((Base.list_reverse (v_reversed)))), v_frames))))))
| (__nat_67, (FlatVisit (__nat_68, v_links, false, v_cursor, (ManyTypes ((v_head :: v_tail))), v_reversed, v_frames))) when __nat_67 >= 1 && __nat_68 >= 1 ->
(let v_rest = (__nat_67 - 1) in
(let v_fuel = (__nat_68 - 1) in
(f_flat_step (v_rest) (v_substitutions) ((f_flat_many (v_fuel) (v_links) (v_cursor) (v_head) (v_tail) (v_reversed) (v_frames)))))))
and (* types.bend:547 *)
f_flat_result : ((M.t_Diagnostic, (M.t_Ty) list) Base.result_) option -> t_Substitutions -> int -> t_TypeWork -> (M.t_Diagnostic, (M.t_Ty) list) Base.result_ =
fun v_found v_substitutions v_fuel v_work ->
(match v_found with
| (Some (v_result)) ->
v_result
| None ->
(f_resolve_work_reference (v_substitutions) (v_fuel) (v_work)))
and (* types.bend:554 *)
f_resolve_work_flat : t_Substitutions -> int -> t_TypeWork -> (M.t_Diagnostic, (M.t_Ty) list) Base.result_ =
fun v_substitutions v_fuel v_work ->
(let v_links = (f_substitution_count (v_substitutions)) in
(f_flat_result ((f_flat_step (1048576) (v_substitutions) ((FlatVisit (v_fuel, v_links, (Base.nat_is_eq (v_links) (0)), 0, v_work, [], []))))) (v_substitutions) (v_fuel) (v_work)))
and (* types.bend:558 *)
f_resolve_work : t_Substitutions -> int -> t_TypeWork -> (M.t_Diagnostic, (M.t_Ty) list) Base.result_ =
fun v_substitutions v_fuel v_work ->
(f_resolve_work_flat (v_substitutions) (v_fuel) (v_work))
and (* types.bend:561 *)
f_resolve : t_Substitutions -> M.t_Ty -> (M.t_Diagnostic, M.t_Ty) Base.result_ =
fun v_substitutions v_ty ->
(match (f_resolve_work (v_substitutions) ((Base.nat_mul (256) (256))) ((OneType (v_ty)))) with
| Fail __error -> Fail __error
| Done v_xs ->
(f_first_type (v_xs)))
and (* types.bend:566 *)
f_contains : (int) list -> int -> bool =
fun v_variables v_variable ->
(f_variable_contains_work (v_variables) (v_variable) (false))
and (* types.bend:569 *)
f_put : (int) list -> int -> (int) list =
fun v_variables v_variable ->
(Base.bool_pick ((f_contains (v_variables) (v_variable))) (v_variables) ((v_variable :: v_variables)))
and (* types.bend:578 *)
f_index_variables : (int) list -> (unit) NatIndex.t_Index -> (unit) NatIndex.t_Index =
fun v_variables v_index ->
(match v_variables with
| [] ->
v_index
| (v_head :: v_tail) ->
(f_index_variables (v_tail) ((NatIndex.f_set (v_index) (v_head) (())))))
and (* types.bend:587 *)
f_union_seed_count_work : (int) list -> int -> int =
fun v_variables v_count ->
(match (v_variables, v_count) with
| (_, 256) ->
256
| ([], v_current) ->
v_current
| ((v_head :: v_tail), v_current) ->
(f_union_seed_count_work (v_tail) ((Base.nat_add 1 v_current))))
and (* types.bend:596 *)
f_union_small_grown : (int) list -> int -> t_VariableUnion =
fun v_values v_count ->
(match v_count with
| 256 ->
(IndexedUnion (v_values, (f_index_variables (v_values) ((NatIndex.f_new ())))))
| v_small ->
(SmallUnion (v_values, v_small)))
and (* types.bend:603 *)
f_union_seed : (int) list -> t_VariableUnion =
fun v_values ->
(f_union_small_grown (v_values) ((f_union_seed_count_work (v_values) (0))))
and (* types.bend:606 *)
f_union_insert_small_found : bool -> (int) list -> int -> int -> t_VariableUnion =
fun v_found v_values v_count v_variable ->
(match v_found with
| true ->
(SmallUnion (v_values, v_count))
| false ->
(f_union_small_grown ((v_variable :: v_values)) ((Base.nat_add 1 v_count))))
and (* types.bend:613 *)
f_union_insert_small : (int) list -> int -> int -> t_VariableUnion =
fun v_values v_count v_variable ->
(f_union_insert_small_found ((f_contains (v_values) (v_variable))) (v_values) (v_count) (v_variable))
and (* types.bend:616 *)
f_union_insert_found : (unit) option -> (int) list -> (unit) NatIndex.t_Index -> int -> t_VariableUnion =
fun v_found v_values v_seen v_variable ->
(match v_found with
| (Some (v_present)) ->
(IndexedUnion (v_values, v_seen))
| None ->
(IndexedUnion ((v_variable :: v_values), (NatIndex.f_set (v_seen) (v_variable) (())))))
and (* types.bend:623 *)
f_union_insert : t_VariableUnion -> int -> t_VariableUnion =
fun v_state v_variable ->
(match v_state with
| (SmallUnion (v_values, v_count)) ->
(f_union_insert_small (v_values) (v_count) (v_variable))
| (IndexedUnion (v_values, v_seen)) ->
(f_union_insert_found ((NatIndex.f_find (v_seen) (v_variable))) (v_values) (v_seen) (v_variable)))
and (* types.bend:630 *)
f_union_into : (int) list -> t_VariableUnion -> t_VariableUnion =
fun v_left v_state ->
(match v_left with
| [] ->
v_state
| (v_head :: v_tail) ->
(f_union_into (v_tail) ((f_union_insert (v_state) (v_head)))))
and (* types.bend:637 *)
f_union_values : t_VariableUnion -> (int) list =
fun v_state ->
(match v_state with
| (SmallUnion (v_values, v_count)) ->
v_values
| (IndexedUnion (v_values, v_seen)) ->
v_values)
and (* types.bend:646 *)
f_wide_variables_work : (int) list -> int -> bool =
fun v_variables v_remaining ->
(match (v_variables, v_remaining) with
| (_, 0) ->
true
| ([], __nat_69) when __nat_69 >= 1 ->
(let v_rest = (__nat_69 - 1) in
false)
| ((v_head :: v_tail), __nat_70) when __nat_70 >= 1 ->
(let v_rest = (__nat_70 - 1) in
(f_wide_variables_work (v_tail) (v_rest))))
and (* types.bend:655 *)
f_wide_variables : (int) list -> bool =
fun v_variables ->
(f_wide_variables_work (v_variables) (16))
and (* types.bend:658 *)
f_union_small : (int) list -> (int) list -> (int) list =
fun v_left v_right ->
(match v_left with
| [] ->
v_right
| (v_head :: v_tail) ->
(f_union_small (v_tail) ((f_put (v_right) (v_head)))))
and (* types.bend:665 *)
f_union_select : (int) list -> (int) list -> bool -> (int) list =
fun v_left v_right v_indexed ->
(match v_indexed with
| false ->
(f_union_small (v_left) (v_right))
| true ->
(f_union_values ((f_union_into (v_left) ((f_union_seed (v_right)))))))
and (* types.bend:672 *)
f_union_nonempty : (int) list -> (int) list -> (int) list =
fun v_left v_right ->
(f_union_select (v_left) (v_right) ((f_wide_variables (v_left))))
and (* types.bend:675 *)
f_union : (int) list -> (int) list -> (int) list =
fun v_left v_right ->
(match v_left with
| [] ->
v_right
| (v_head :: v_tail) ->
(f_union_nonempty ((v_head :: v_tail)) (v_right)))
and (* types.bend:684 *)
f_difference_work : (int) list -> (int) list -> (int) list -> (int) list =
fun v_variables v_excluded v_reversed ->
(match v_variables with
| [] ->
(Base.list_reverse (v_reversed))
| (v_head :: v_tail) ->
(f_difference_work (v_tail) (v_excluded) ((Base.bool_pick ((f_contains (v_excluded) (v_head))) (v_reversed) ((v_head :: v_reversed))))))
and (* types.bend:691 *)
f_difference_indexed_found : (unit) option -> int -> (int) list -> (int) list =
fun v_found v_head v_reversed ->
(match v_found with
| (Some (v_present)) ->
v_reversed
| None ->
(v_head :: v_reversed))
and (* types.bend:698 *)
f_difference_indexed_work : (int) list -> (unit) NatIndex.t_Index -> (int) list -> (int) list =
fun v_variables v_excluded v_reversed ->
(match v_variables with
| [] ->
(Base.list_reverse (v_reversed))
| (v_head :: v_tail) ->
(f_difference_indexed_work (v_tail) (v_excluded) ((f_difference_indexed_found ((NatIndex.f_find (v_excluded) (v_head))) (v_head) (v_reversed)))))
and (* types.bend:705 *)
f_difference_select : (int) list -> (int) list -> bool -> (int) list =
fun v_variables v_excluded v_indexed ->
(match v_indexed with
| false ->
(f_difference_work (v_variables) (v_excluded) ([]))
| true ->
(f_difference_indexed_work (v_variables) ((f_index_variables (v_excluded) ((NatIndex.f_new ())))) ([])))
and (* types.bend:712 *)
f_difference : (int) list -> (int) list -> (int) list =
fun v_variables v_excluded ->
(f_difference_select (v_variables) (v_excluded) ((Base.bool_and ((f_wide_variables (v_variables))) ((f_wide_variables (v_excluded))))))
and (* types.bend:715 *)
f_row_free : M.t_EffectRow -> (int) list =
fun v_row ->
(match v_row with
| (M.EffectRow (v_operations, (M.RowVariable (v_index)))) ->
[v_index]
| _ ->
[])
and (* types.bend:722 *)
f_free_work : int -> t_TypeWork -> (M.t_Diagnostic, (int) list) Base.result_ =
fun v_fuel v_work ->
(match (v_fuel, v_work) with
| (0, _) ->
(Fail ((f_complexity ())))
| (__nat_71, (OneType ((M.VariableTy (v_index))))) when __nat_71 >= 1 ->
(let v_rest = (__nat_71 - 1) in
(Done ([v_index])))
| (__nat_72, (OneType ((M.FunctionTy (v_parameter, v_result, v_effects))))) when __nat_72 >= 1 ->
(let v_rest = (__nat_72 - 1) in
(match (f_free_work (v_rest) ((OneType (v_parameter)))) with
| Fail __error -> Fail __error
| Done v_p ->
(match (f_free_work (v_rest) ((OneType (v_result)))) with
| Fail __error -> Fail __error
| Done v_r ->
(Done ((f_union ((f_row_free (v_effects))) ((f_union (v_p) (v_r)))))))))
| (__nat_73, (OneType ((M.StateProviderTy (v_read, v_write, v_state))))) when __nat_73 >= 1 ->
(let v_rest = (__nat_73 - 1) in
(f_free_work (v_rest) ((OneType (v_state)))))
| (__nat_74, (OneType ((M.ProviderTy (v_identity, v_effects))))) when __nat_74 >= 1 ->
(let v_rest = (__nat_74 - 1) in
(Done ((f_row_free (v_effects)))))
| (__nat_75, (OneType ((M.AppliedTy (v_identity, v_arguments))))) when __nat_75 >= 1 ->
(let v_rest = (__nat_75 - 1) in
(f_free_work (v_rest) ((ManyTypes (v_arguments)))))
| (__nat_76, (OneType ((M.ProductTy (v_elements))))) when __nat_76 >= 1 ->
(let v_rest = (__nat_76 - 1) in
(f_free_work (v_rest) ((ManyTypes (v_elements)))))
| (__nat_77, (OneType ((M.ArrayTy (v_element))))) when __nat_77 >= 1 ->
(let v_rest = (__nat_77 - 1) in
(f_free_work (v_rest) ((OneType (v_element)))))
| (__nat_78, (OneType (v_other))) when __nat_78 >= 1 ->
(let v_rest = (__nat_78 - 1) in
(Done ([])))
| (__nat_79, (ManyTypes ([]))) when __nat_79 >= 1 ->
(let v_rest = (__nat_79 - 1) in
(Done ([])))
| (__nat_80, (ManyTypes ((v_head :: v_tail)))) when __nat_80 >= 1 ->
(let v_rest = (__nat_80 - 1) in
(match (f_free_work (v_rest) ((OneType (v_head)))) with
| Fail __error -> Fail __error
| Done v_h ->
(match (f_free_work (v_rest) ((ManyTypes (v_tail)))) with
| Fail __error -> Fail __error
| Done v_t ->
(Done ((f_union (v_h) (v_t))))))))
and (* types.bend:753 *)
f_free : M.t_Ty -> (M.t_Diagnostic, (int) list) Base.result_ =
fun v_ty ->
(f_free_work ((Base.nat_mul (256) (256))) ((OneType (v_ty))))
and (* types.bend:756 *)
f_close_tail : (int) list -> (int) list -> M.t_EffectRow -> M.t_EffectRow =
fun v_generalized v_connected v_row ->
(match v_row with
| (M.EffectRow (v_labels, (M.RowVariable (v_index)))) ->
(let v_tail = (M.RowVariable (v_index)) in
(M.EffectRow (v_labels, (Base.bool_pick ((Base.bool_and ((f_contains (v_generalized) (v_index))) ((Base.bool_not ((f_contains (v_connected) (v_index))))))) (M.ClosedRow) (v_tail)))))
| v_other ->
v_other)
and (* types.bend:766 *)
f_covariant_inputs : int -> t_TypeWork -> (M.t_Diagnostic, (int) list) Base.result_ =
fun v_fuel v_work ->
(match (v_fuel, v_work) with
| (0, _) ->
(Fail ((f_complexity ())))
| (__nat_81, (OneType ((M.FunctionTy (v_parameter, v_result, v_effects))))) when __nat_81 >= 1 ->
(let v_rest = (__nat_81 - 1) in
(match (f_free (v_parameter)) with
| Fail __error -> Fail __error
| Done v_inputs ->
(match (f_covariant_inputs (v_rest) ((OneType (v_result)))) with
| Fail __error -> Fail __error
| Done v_nested ->
(Done ((f_union (v_inputs) (v_nested)))))))
| (__nat_82, (OneType ((M.AppliedTy (v_identity, v_arguments))))) when __nat_82 >= 1 ->
(let v_rest = (__nat_82 - 1) in
(f_free_work (v_rest) ((ManyTypes (v_arguments)))))
| (__nat_83, (OneType ((M.ProductTy (v_elements))))) when __nat_83 >= 1 ->
(let v_rest = (__nat_83 - 1) in
(f_covariant_inputs (v_rest) ((ManyTypes (v_elements)))))
| (__nat_84, (OneType ((M.ArrayTy (v_element))))) when __nat_84 >= 1 ->
(let v_rest = (__nat_84 - 1) in
(f_covariant_inputs (v_rest) ((OneType (v_element)))))
| (__nat_85, (ManyTypes ((v_head :: v_tail)))) when __nat_85 >= 1 ->
(let v_rest = (__nat_85 - 1) in
(match (f_covariant_inputs (v_rest) ((OneType (v_head)))) with
| Fail __error -> Fail __error
| Done v_h ->
(match (f_covariant_inputs (v_rest) ((ManyTypes (v_tail)))) with
| Fail __error -> Fail __error
| Done v_t ->
(Done ((f_union (v_h) (v_t)))))))
| (__nat_86, _) when __nat_86 >= 1 ->
(let v_rest = (__nat_86 - 1) in
(Done ([]))))
and (* types.bend:791 *)
f_close_covariant_work : int -> t_TypeWork -> (int) list -> (int) list -> (M.t_Diagnostic, (M.t_Ty) list) Base.result_ =
fun v_fuel v_work v_generalized v_protected ->
(match (v_fuel, v_work) with
| (0, _) ->
(Fail ((f_complexity ())))
| (__nat_87, (OneType ((M.FunctionTy (v_parameter, v_result, v_effects))))) when __nat_87 >= 1 ->
(let v_rest = (__nat_87 - 1) in
(match (f_free (v_parameter)) with
| Fail __error -> Fail __error
| Done v_parameter_free ->
(match (f_free (v_result)) with
| Fail __error -> Fail __error
| Done v_result_free ->
(let v_row = (f_close_tail (v_generalized) ((f_union (v_protected) ((f_union (v_parameter_free) (v_result_free))))) (v_effects)) in
(match (f_close_covariant_work (v_rest) ((OneType (v_result))) (v_generalized) ((f_union (v_protected) ((f_union (v_parameter_free) ((f_row_free (v_row)))))))) with
| Fail __error -> Fail __error
| Done v_closed ->
(match (f_first_type (v_closed)) with
| Fail __error -> Fail __error
| Done v_result ->
(Done ([(M.FunctionTy (v_parameter, v_result, v_row))]))))))))
| (__nat_88, (OneType ((M.ProviderTy (v_identity, v_effects))))) when __nat_88 >= 1 ->
(let v_rest = (__nat_88 - 1) in
(Done ([(M.ProviderTy (v_identity, (f_close_tail (v_generalized) (v_protected) (v_effects))))])))
| (__nat_89, (OneType ((M.ProductTy (v_elements))))) when __nat_89 >= 1 ->
(let v_rest = (__nat_89 - 1) in
(match (f_covariant_inputs (v_rest) ((ManyTypes (v_elements)))) with
| Fail __error -> Fail __error
| Done v_connected ->
(match (f_close_covariant_work (v_rest) ((ManyTypes (v_elements))) (v_generalized) ((f_union (v_protected) (v_connected)))) with
| Fail __error -> Fail __error
| Done v_closed ->
(Done ([(M.ProductTy (v_closed))])))))
| (__nat_90, (OneType ((M.ArrayTy (v_element))))) when __nat_90 >= 1 ->
(let v_rest = (__nat_90 - 1) in
(match (f_close_covariant_work (v_rest) ((OneType (v_element))) (v_generalized) (v_protected)) with
| Fail __error -> Fail __error
| Done v_closed ->
(match (f_first_type (v_closed)) with
| Fail __error -> Fail __error
| Done v_value ->
(Done ([(M.ArrayTy (v_value))])))))
| (__nat_91, (OneType (v_other))) when __nat_91 >= 1 ->
(let v_rest = (__nat_91 - 1) in
(Done ([v_other])))
| (__nat_92, (ManyTypes ([]))) when __nat_92 >= 1 ->
(let v_rest = (__nat_92 - 1) in
(Done ([])))
| (__nat_93, (ManyTypes ((v_head :: v_tail)))) when __nat_93 >= 1 ->
(let v_rest = (__nat_93 - 1) in
(match (f_close_covariant_work (v_rest) ((OneType (v_head))) (v_generalized) (v_protected)) with
| Fail __error -> Fail __error
| Done v_hs ->
(match (f_first_type (v_hs)) with
| Fail __error -> Fail __error
| Done v_h ->
(match (f_close_covariant_work (v_rest) ((ManyTypes (v_tail))) (v_generalized) (v_protected)) with
| Fail __error -> Fail __error
| Done v_ts ->
(Done ((v_h :: v_ts))))))))
and (* types.bend:826 *)
f_close_covariant : M.t_Ty -> (int) list -> (int) list -> (M.t_Diagnostic, M.t_Ty) Base.result_ =
fun v_ty v_generalized v_protected ->
(match (f_close_covariant_work ((Base.u32_to_nat ((Base.W32 0x10000)))) ((OneType (v_ty))) (v_generalized) (v_protected)) with
| Fail __error -> Fail __error
| Done v_closed ->
(f_first_type (v_closed)))
and (* types.bend:831 *)
f_close_generalized : M.t_Ty -> (int) list -> (M.t_Diagnostic, M.t_Ty) Base.result_ =
fun v_ty v_generalized ->
(f_close_covariant (v_ty) (v_generalized) ([]))
and (* types.bend:837 *)
f_opened_type : t_Opened -> M.t_Ty =
fun v_opened ->
(let (Opened (v_ty, v_next)) = v_opened in
v_ty)
and (* types.bend:841 *)
f_opened_next : t_Opened -> int =
fun v_opened ->
(let (Opened (v_ty, v_next)) = v_opened in
v_next)
and (* types.bend:845 *)
f_open_function : M.t_EffectRow -> M.t_Ty -> t_Opened -> t_Opened =
fun v_row v_parameter v_opened ->
(match v_row with
| (M.EffectRow (v_labels, M.ClosedRow)) ->
(let (Opened (v_result, v_next)) = v_opened in
(Opened ((M.FunctionTy (v_parameter, v_result, (M.EffectRow (v_labels, (M.RowVariable (v_next)))))), (Base.nat_add 1 v_next))))
| v_effects ->
(let (Opened (v_result, v_next)) = v_opened in
(Opened ((M.FunctionTy (v_parameter, v_result, v_effects)), v_next))))
and (* types.bend:857 *)
f_opened_types : t_OpenedTypes -> (M.t_Ty) list =
fun v_value ->
(let (OpenedTypes (v_types, v_next)) = v_value in
v_types)
and (* types.bend:861 *)
f_opened_types_next : t_OpenedTypes -> int =
fun v_value ->
(let (OpenedTypes (v_types, v_next)) = v_value in
v_next)
and (* types.bend:865 *)
f_open_covariant_work : int -> t_TypeWork -> int -> (M.t_Diagnostic, t_OpenedTypes) Base.result_ =
fun v_fuel v_work v_next ->
(match (v_fuel, v_work) with
| (0, _) ->
(Fail ((f_complexity ())))
| (__nat_94, (OneType ((M.FunctionTy (v_parameter, v_result, v_effects))))) when __nat_94 >= 1 ->
(let v_rest = (__nat_94 - 1) in
(match (f_open_covariant_work (v_rest) ((OneType (v_result))) (v_next)) with
| Fail __error -> Fail __error
| Done v_nested ->
(match (f_first_type ((f_opened_types (v_nested)))) with
| Fail __error -> Fail __error
| Done v_result ->
(let v_opened = (f_open_function (v_effects) (v_parameter) ((Opened (v_result, (f_opened_types_next (v_nested)))))) in
(Done ((OpenedTypes ([(f_opened_type (v_opened))], (f_opened_next (v_opened))))))))))
| (__nat_95, (OneType ((M.ProviderTy (v_identity, (M.EffectRow (v_labels, M.ClosedRow))))))) when __nat_95 >= 1 ->
(let v_rest = (__nat_95 - 1) in
(Done ((OpenedTypes ([(M.ProviderTy (v_identity, (M.EffectRow (v_labels, (M.RowVariable (v_next))))))], (Base.nat_add 1 v_next))))))
| (__nat_96, (OneType ((M.ProductTy (v_elements))))) when __nat_96 >= 1 ->
(let v_rest = (__nat_96 - 1) in
(match (f_open_covariant_work (v_rest) ((ManyTypes (v_elements))) (v_next)) with
| Fail __error -> Fail __error
| Done v_nested ->
(Done ((OpenedTypes ([(M.ProductTy ((f_opened_types (v_nested))))], (f_opened_types_next (v_nested))))))))
| (__nat_97, (OneType ((M.ArrayTy (v_element))))) when __nat_97 >= 1 ->
(let v_rest = (__nat_97 - 1) in
(match (f_open_covariant_work (v_rest) ((OneType (v_element))) (v_next)) with
| Fail __error -> Fail __error
| Done v_nested ->
(match (f_first_type ((f_opened_types (v_nested)))) with
| Fail __error -> Fail __error
| Done v_value ->
(Done ((OpenedTypes ([(M.ArrayTy (v_value))], (f_opened_types_next (v_nested)))))))))
| (__nat_98, (OneType (v_other))) when __nat_98 >= 1 ->
(let v_rest = (__nat_98 - 1) in
(Done ((OpenedTypes ([v_other], v_next)))))
| (__nat_99, (ManyTypes ([]))) when __nat_99 >= 1 ->
(let v_rest = (__nat_99 - 1) in
(Done ((OpenedTypes ([], v_next)))))
| (__nat_100, (ManyTypes ((v_head :: v_tail)))) when __nat_100 >= 1 ->
(let v_rest = (__nat_100 - 1) in
(match (f_open_covariant_work (v_rest) ((OneType (v_head))) (v_next)) with
| Fail __error -> Fail __error
| Done v_hs ->
(match (f_first_type ((f_opened_types (v_hs)))) with
| Fail __error -> Fail __error
| Done v_h ->
(match (f_open_covariant_work (v_rest) ((ManyTypes (v_tail))) ((f_opened_types_next (v_hs)))) with
| Fail __error -> Fail __error
| Done v_ts ->
(Done ((OpenedTypes ((v_h :: (f_opened_types (v_ts))), (f_opened_types_next (v_ts)))))))))))
and (* types.bend:897 *)
f_open_covariant : M.t_Ty -> int -> (M.t_Diagnostic, t_Opened) Base.result_ =
fun v_ty v_next ->
(match (f_open_covariant_work ((Base.u32_to_nat ((Base.W32 0x10000)))) ((OneType (v_ty))) (v_next)) with
| Fail __error -> Fail __error
| Done v_opened ->
(match (f_first_type ((f_opened_types (v_opened)))) with
| Fail __error -> Fail __error
| Done v_value ->
(Done ((Opened (v_value, (f_opened_types_next (v_opened))))))))
and (* types.bend:906 *)
f_merge_kinds : t_ParameterKinds -> t_ParameterKinds -> t_ParameterKinds =
fun v_left v_right ->
(let (ParameterKinds (v_lt, v_lr)) = v_left in
(let (ParameterKinds (v_rt, v_rr)) = v_right in
(ParameterKinds ((f_union (v_lt) (v_rt)), (f_union (v_lr) (v_rr))))))
and (* types.bend:911 *)
f_row_parameter_kinds : M.t_EffectRow -> t_ParameterKinds =
fun v_row ->
(match v_row with
| (M.EffectRow (v_labels, (M.RowParameter (v_index)))) ->
(ParameterKinds ([], [v_index]))
| _ ->
(ParameterKinds ([], [])))
and (* types.bend:918 *)
f_parameter_kinds : int -> t_TypeWork -> (M.t_Diagnostic, t_ParameterKinds) Base.result_ =
fun v_fuel v_work ->
(match (v_fuel, v_work) with
| (0, _) ->
(Fail ((f_complexity ())))
| (__nat_101, (OneType ((M.ParameterTy (v_index))))) when __nat_101 >= 1 ->
(let v_rest = (__nat_101 - 1) in
(Done ((ParameterKinds ([v_index], [])))))
| (__nat_102, (OneType ((M.FunctionTy (v_parameter, v_result, v_effects))))) when __nat_102 >= 1 ->
(let v_rest = (__nat_102 - 1) in
(match (f_parameter_kinds (v_rest) ((ManyTypes ([v_parameter; v_result])))) with
| Fail __error -> Fail __error
| Done v_nested ->
(Done ((f_merge_kinds ((f_row_parameter_kinds (v_effects))) (v_nested))))))
| (__nat_103, (OneType ((M.StateProviderTy (v_read, v_write, v_state))))) when __nat_103 >= 1 ->
(let v_rest = (__nat_103 - 1) in
(f_parameter_kinds (v_rest) ((OneType (v_state)))))
| (__nat_104, (OneType ((M.ProviderTy (v_identity, v_effects))))) when __nat_104 >= 1 ->
(let v_rest = (__nat_104 - 1) in
(Done ((f_row_parameter_kinds (v_effects)))))
| (__nat_105, (OneType ((M.AppliedTy (v_identity, v_arguments))))) when __nat_105 >= 1 ->
(let v_rest = (__nat_105 - 1) in
(f_parameter_kinds (v_rest) ((ManyTypes (v_arguments)))))
| (__nat_106, (OneType ((M.ProductTy (v_elements))))) when __nat_106 >= 1 ->
(let v_rest = (__nat_106 - 1) in
(f_parameter_kinds (v_rest) ((ManyTypes (v_elements)))))
| (__nat_107, (OneType ((M.ArrayTy (v_element))))) when __nat_107 >= 1 ->
(let v_rest = (__nat_107 - 1) in
(f_parameter_kinds (v_rest) ((OneType (v_element)))))
| (__nat_108, (ManyTypes ((v_head :: v_tail)))) when __nat_108 >= 1 ->
(let v_rest = (__nat_108 - 1) in
(match (f_parameter_kinds (v_rest) ((OneType (v_head)))) with
| Fail __error -> Fail __error
| Done v_first ->
(match (f_parameter_kinds (v_rest) ((ManyTypes (v_tail)))) with
| Fail __error -> Fail __error
| Done v_remaining ->
(Done ((f_merge_kinds (v_first) (v_remaining)))))))
| (__nat_109, _) when __nat_109 >= 1 ->
(let v_rest = (__nat_109 - 1) in
(Done ((ParameterKinds ([], []))))))
and (* types.bend:946 *)
f_disjoint_work : (int) list -> (int) list -> bool -> bool =
fun v_variables v_excluded v_clear ->
(match (v_variables, v_clear) with
| (_, false) ->
false
| ([], true) ->
true
| ((v_head :: v_tail), true) ->
(f_disjoint_work (v_tail) (v_excluded) ((Base.bool_not ((f_contains (v_excluded) (v_head)))))))
and (* types.bend:955 *)
f_disjoint : (int) list -> (int) list -> bool =
fun v_variables v_excluded ->
(f_disjoint_work (v_variables) (v_excluded) (true))
and (* types.bend:958 *)
f_kind_check : t_ParameterKinds -> Base.text -> (M.t_Diagnostic, unit) Base.result_ =
fun v_kinds v_subject ->
(let (ParameterKinds (v_types, v_rows)) = v_kinds in
(Base.bool_pick ((f_disjoint (v_types) (v_rows))) ((Done (()))) ((Fail ((M.Diagnostic (s_5, v_subject, s_9)))))))
and (* types.bend:962 *)
f_variable_binding : bool -> int -> M.t_Ty -> t_Substitutions -> Base.text -> (M.t_Diagnostic, t_Substitutions) Base.result_ =
fun v_recursive v_variable v_replacement v_substitutions v_subject ->
(match v_recursive with
| true ->
(Fail ((M.Diagnostic (s_10, v_subject, (Base.string_append s_11 (Base.string_append (Base.nat_show (v_variable)) (Base.string_append s_12 (M.f_type_show (v_replacement)))))))))
| false ->
(Done ((f_append_substitution (v_substitutions) ((Substitution (v_variable, v_replacement)))))))
and (* types.bend:969 *)
f_bind : int -> M.t_Ty -> t_Substitutions -> Base.text -> (M.t_Diagnostic, t_Substitutions) Base.result_ =
fun v_variable v_replacement v_substitutions v_subject ->
(match (f_free (v_replacement)) with
| Fail __error -> Fail __error
| Done v_variables ->
(f_variable_binding ((f_contains (v_variables) (v_variable))) (v_variable) (v_replacement) (v_substitutions) (v_subject)))
and (* types.bend:974 *)
f_pair_arguments_accumulated : (M.t_Ty) list -> (M.t_Ty) list -> Base.text -> (t_Equation) list -> (M.t_Diagnostic, (t_Equation) list) Base.result_ =
fun v_left v_right v_subject v_reversed ->
(match (v_left, v_right) with
| ([], []) ->
(Done ((Base.list_reverse (v_reversed))))
| ((v_a :: v_aa), (v_b :: v_bb)) ->
(f_pair_arguments_accumulated (v_aa) (v_bb) (v_subject) (((Equation (v_a, v_b, v_subject)) :: v_reversed)))
| (_, _) ->
(Fail ((M.Diagnostic (s_13, v_subject, s_14)))))
and (* types.bend:983 *)
f_pair_arguments : (M.t_Ty) list -> (M.t_Ty) list -> Base.text -> (M.t_Diagnostic, (t_Equation) list) Base.result_ =
fun v_left v_right v_subject ->
(f_pair_arguments_accumulated (v_left) (v_right) (v_subject) ([]))
and (* types.bend:989 *)
f_pending_equations : t_Unification -> (t_Equation) list =
fun v_result ->
(let (Unification (v_equations, v_substitutions)) = v_result in
v_equations)
and (* types.bend:993 *)
f_substitutions_of : t_Unification -> t_Substitutions =
fun v_result ->
(let (Unification (v_equations, v_substitutions)) = v_result in
v_substitutions)
and (* types.bend:997 *)
f_mismatch : M.t_Ty -> M.t_Ty -> Base.text -> M.t_Diagnostic =
fun v_left v_right v_subject ->
(M.Diagnostic (s_15, v_subject, (Base.string_append s_16 (Base.string_append (M.f_type_show (v_left)) (Base.string_append s_17 (M.f_type_show (v_right)))))))
and (* types.bend:1000 *)
f_same_variable : bool -> int -> int -> t_Substitutions -> Base.text -> (M.t_Diagnostic, t_Unification) Base.result_ =
fun v_same v_left v_right v_substitutions v_subject ->
(match v_same with
| true ->
(Done ((Unification ([], v_substitutions))))
| false ->
(match (f_bind (v_left) ((M.VariableTy (v_right))) (v_substitutions) (v_subject)) with
| Fail __error -> Fail __error
| Done v_next ->
(Done ((Unification ([], v_next))))))
and (* types.bend:1009 *)
f_nominal : bool -> M.t_TypeId -> M.t_TypeId -> (M.t_Ty) list -> (M.t_Ty) list -> t_Substitutions -> Base.text -> (M.t_Diagnostic, t_Unification) Base.result_ =
fun v_same v_left v_right v_a v_b v_substitutions v_subject ->
(match v_same with
| false ->
(Fail ((f_mismatch ((M.AppliedTy (v_left, v_a))) ((M.AppliedTy (v_right, v_b))) (v_subject))))
| true ->
(match (f_pair_arguments (v_a) (v_b) (v_subject)) with
| Fail __error -> Fail __error
| Done v_equations ->
(Done ((Unification (v_equations, v_substitutions))))))
and (* types.bend:1018 *)
f_providers : bool -> M.t_TypeId -> M.t_TypeId -> M.t_EffectRow -> M.t_EffectRow -> t_Substitutions -> Base.text -> (M.t_Diagnostic, t_Unification) Base.result_ =
fun v_same v_left v_right v_a v_b v_substitutions v_subject ->
(match v_same with
| false ->
(Fail ((f_mismatch ((M.ProviderTy (v_left, v_a))) ((M.ProviderTy (v_right, v_b))) (v_subject))))
| true ->
(Done ((Unification ([(RowEquation (v_a, v_b, v_subject))], v_substitutions)))))
and (* types.bend:1025 *)
f_products : bool -> (M.t_Ty) list -> (M.t_Ty) list -> t_Substitutions -> Base.text -> (M.t_Diagnostic, t_Unification) Base.result_ =
fun v_same_arity v_left v_right v_substitutions v_subject ->
(match v_same_arity with
| false ->
(Fail ((M.Diagnostic (s_18, v_subject, s_19))))
| true ->
(match (f_pair_arguments (v_left) (v_right) (v_subject)) with
| Fail __error -> Fail __error
| Done v_equations ->
(Done ((Unification (v_equations, v_substitutions))))))
and (* types.bend:1034 *)
f_unify_one : M.t_Ty -> M.t_Ty -> t_Substitutions -> Base.text -> (M.t_Diagnostic, t_Unification) Base.result_ =
fun v_left v_right v_substitutions v_subject ->
(match (v_left, v_right) with
| (M.NeverTy, _) ->
(Done ((Unification ([], v_substitutions))))
| (_, M.NeverTy) ->
(Done ((Unification ([], v_substitutions))))
| (M.UnitTy, M.UnitTy) ->
(Done ((Unification ([], v_substitutions))))
| (M.U32Ty, M.U32Ty) ->
(Done ((Unification ([], v_substitutions))))
| (M.F32Ty, M.F32Ty) ->
(Done ((Unification ([], v_substitutions))))
| (M.BoolTy, M.BoolTy) ->
(Done ((Unification ([], v_substitutions))))
| (M.EffectDescriptorTy, M.EffectDescriptorTy) ->
(Done ((Unification ([], v_substitutions))))
| (M.EffectSetTy, M.EffectSetTy) ->
(Done ((Unification ([], v_substitutions))))
| ((M.VariableTy (v_a)), (M.VariableTy (v_b))) ->
(f_same_variable ((Base.nat_is_eq (v_a) (v_b))) (v_a) (v_b) (v_substitutions) (v_subject))
| ((M.VariableTy (v_index)), v_other) ->
(match (f_bind (v_index) (v_other) (v_substitutions) (v_subject)) with
| Fail __error -> Fail __error
| Done v_next ->
(Done ((Unification ([], v_next)))))
| (v_other, (M.VariableTy (v_index))) ->
(match (f_bind (v_index) (v_other) (v_substitutions) (v_subject)) with
| Fail __error -> Fail __error
| Done v_next ->
(Done ((Unification ([], v_next)))))
| ((M.FunctionTy (v_ap, v_ar, v_ae)), (M.FunctionTy (v_bp, v_br, v_be))) ->
(Done ((Unification ([(Equation (v_ap, v_bp, v_subject)); (Equation (v_ar, v_br, v_subject)); (RowEquation (v_ae, v_be, v_subject))], v_substitutions))))
| ((M.StateProviderTy (v_ar, v_aw, v_a)), (M.StateProviderTy (v_br, v_bw, v_b))) ->
(Base.bool_pick ((Base.bool_and ((M.f_type_id_equal (v_ar) (v_br))) ((M.f_type_id_equal (v_aw) (v_bw))))) ((Done ((Unification ([(Equation (v_a, v_b, v_subject))], v_substitutions))))) ((Fail ((f_mismatch ((M.StateProviderTy (v_ar, v_aw, v_a))) ((M.StateProviderTy (v_br, v_bw, v_b))) (v_subject))))))
| ((M.ProviderTy (v_a, v_ae)), (M.ProviderTy (v_b, v_be))) ->
(f_providers ((M.f_type_id_equal (v_a) (v_b))) (v_a) (v_b) (v_ae) (v_be) (v_substitutions) (v_subject))
| ((M.AppliedTy (v_a, v_aa)), (M.AppliedTy (v_b, v_bb))) ->
(f_nominal ((M.f_type_id_equal (v_a) (v_b))) (v_a) (v_b) (v_aa) (v_bb) (v_substitutions) (v_subject))
| ((M.ProductTy (v_a)), (M.ProductTy (v_b))) ->
(f_products ((Base.nat_is_eq ((Base.list_length (v_a))) ((Base.list_length (v_b))))) (v_a) (v_b) (v_substitutions) (v_subject))
| ((M.ArrayTy (v_a)), (M.ArrayTy (v_b))) ->
(Done ((Unification ([(Equation (v_a, v_b, v_subject))], v_substitutions))))
| (v_a, v_b) ->
(Fail ((f_mismatch (v_a) (v_b) (v_subject)))))
and (* types.bend:1080 *)
f_solution_substitutions : t_Solution -> t_Substitutions =
fun v_solution ->
(let (Solution (v_substitutions, v_next)) = v_solution in
v_substitutions)
and (* types.bend:1084 *)
f_solution_next : t_Solution -> int =
fun v_solution ->
(let (Solution (v_substitutions, v_next)) = v_solution in
v_next)
and (* types.bend:1088 *)
f_row_substitutions : (R.t_Binding) list -> (t_Substitution) list =
fun v_bindings ->
(match v_bindings with
| [] ->
[]
| ((R.Binding (v_variable, v_replacement)) :: v_tail) ->
((RowSubstitution (v_variable, v_replacement)) :: (f_row_substitutions (v_tail))))
and (* types.bend:1095 *)
f_row_solution : R.t_Solution -> t_Substitutions -> t_Solution =
fun v_solution v_previous ->
(let (R.Solution (v_bindings, v_next)) = v_solution in
(Solution ((f_append_substitutions ((f_row_substitutions (v_bindings))) (v_previous)), v_next)))
and (* types.bend:1099 *)
f_solve_work : int -> (t_Equation) list -> t_Substitutions -> int -> (M.t_Diagnostic, t_Solution) Base.result_ =
fun v_fuel v_equations v_substitutions v_next ->
(match (v_fuel, v_equations) with
| (_, []) ->
(Done ((Solution (v_substitutions, v_next))))
| (0, _) ->
(Fail ((f_complexity ())))
| (__nat_110, ((Equation (v_left, v_right, v_subject)) :: v_tail)) when __nat_110 >= 1 ->
(let v_rest = (__nat_110 - 1) in
(match (f_resolve (v_substitutions) (v_left)) with
| Fail __error -> Fail __error
| Done v_a ->
(match (f_resolve (v_substitutions) (v_right)) with
| Fail __error -> Fail __error
| Done v_b ->
(match (f_unify_one (v_a) (v_b) (v_substitutions) (v_subject)) with
| Fail __error -> Fail __error
| Done v_result ->
(f_solve_work (v_rest) ((Base.list_reverse_go ((Base.list_reverse ((f_pending_equations (v_result))))) (v_tail))) ((f_substitutions_of (v_result))) (v_next))))))
| (__nat_111, ((RowEquation (v_left, v_right, v_subject)) :: v_tail)) when __nat_111 >= 1 ->
(let v_rest = (__nat_111 - 1) in
(match (R.f_unify ((f_resolve_row (v_substitutions) (v_left))) ((f_resolve_row (v_substitutions) (v_right))) ([]) (v_next) (v_subject)) with
| Fail __error -> Fail __error
| Done v_rows ->
(let v_solved = (f_row_solution (v_rows) (v_substitutions)) in
(f_solve_work (v_rest) (v_tail) ((f_solution_substitutions (v_solved))) ((f_solution_next (v_solved))))))))
and (* types.bend:1117 *)
f_equations_free : (t_Equation) list -> (M.t_Diagnostic, (int) list) Base.result_ =
fun v_equations ->
(match v_equations with
| [] ->
(Done ([]))
| ((Equation (v_left, v_right, v_subject)) :: v_tail) ->
(match (f_free_work ((Base.u32_to_nat ((Base.W32 0x10000)))) ((ManyTypes ([v_left; v_right])))) with
| Fail __error -> Fail __error
| Done v_first ->
(match (f_equations_free (v_tail)) with
| Fail __error -> Fail __error
| Done v_remaining ->
(Done ((f_union (v_first) (v_remaining))))))
| ((RowEquation (v_left, v_right, v_subject)) :: v_tail) ->
(match (f_equations_free (v_tail)) with
| Fail __error -> Fail __error
| Done v_remaining ->
(Done ((f_union ((f_row_free (v_left))) ((f_union ((f_row_free (v_right))) (v_remaining))))))))
and (* types.bend:1131 *)
f_substitutions_free : (t_Substitution) list -> (M.t_Diagnostic, (int) list) Base.result_ =
fun v_substitutions ->
(match v_substitutions with
| [] ->
(Done ([]))
| ((Substitution (v_variable, v_replacement)) :: v_tail) ->
(match (f_free (v_replacement)) with
| Fail __error -> Fail __error
| Done v_first ->
(match (f_substitutions_free (v_tail)) with
| Fail __error -> Fail __error
| Done v_remaining ->
(Done ((v_variable :: (f_union (v_first) (v_remaining)))))))
| ((RowSubstitution (v_variable, v_replacement)) :: v_tail) ->
(match (f_substitutions_free (v_tail)) with
| Fail __error -> Fail __error
| Done v_remaining ->
(Done ((v_variable :: (f_union ((f_row_free (v_replacement))) (v_remaining)))))))
and (* types.bend:1145 *)
f_above : (int) list -> int -> int =
fun v_variables v_next ->
(match v_variables with
| [] ->
v_next
| (v_head :: v_tail) ->
(let v_candidate = (Base.nat_add 1 v_head) in
(f_above (v_tail) ((Base.bool_pick ((Base.nat_is_lt (v_next) (v_candidate))) (v_candidate) (v_next))))))
and (* types.bend:1153 *)
f_solve : (t_Equation) list -> t_Substitutions -> (M.t_Diagnostic, t_Substitutions) Base.result_ =
fun v_equations v_substitutions ->
(let v_pending = v_equations in
(let v_previous = v_substitutions in
(match (f_equations_free (v_pending)) with
| Fail __error -> Fail __error
| Done v_first ->
(match (f_substitutions_free ((f_substitution_history (v_previous)))) with
| Fail __error -> Fail __error
| Done v_second ->
(match (f_solve_work ((Base.u32_to_nat ((Base.W32 0x10000)))) (v_pending) (v_previous) ((f_above (v_first) ((f_above (v_second) (0)))))) with
| Fail __error -> Fail __error
| Done v_solved ->
(Done ((f_solution_substitutions (v_solved)))))))))
and (* types.bend:1162 *)
f_unify_at : M.t_Ty -> M.t_Ty -> t_Substitutions -> int -> Base.text -> (M.t_Diagnostic, t_Solution) Base.result_ =
fun v_left v_right v_substitutions v_next v_subject ->
(f_solve_work ((Base.u32_to_nat ((Base.W32 0x10000)))) ([(Equation (v_left, v_right, v_subject))]) (v_substitutions) (v_next))
and (* types.bend:1165 *)
f_unify_rows_at : M.t_EffectRow -> M.t_EffectRow -> t_Substitutions -> int -> Base.text -> (M.t_Diagnostic, t_Solution) Base.result_ =
fun v_left v_right v_substitutions v_next v_subject ->
(f_solve_work ((Base.u32_to_nat ((Base.W32 0x10000)))) ([(RowEquation (v_left, v_right, v_subject))]) (v_substitutions) (v_next))
and (* types.bend:1168 *)
f_unify : M.t_Ty -> M.t_Ty -> t_Substitutions -> Base.text -> (M.t_Diagnostic, t_Substitutions) Base.result_ =
fun v_left v_right v_substitutions v_subject ->
(f_solve ([(Equation (v_left, v_right, v_subject))]) (v_substitutions))
and (* types.bend:1171 *)
f_scalar : M.t_Ty -> bool =
fun v_ty ->
(match v_ty with
| M.UnitTy ->
true
| M.U32Ty ->
true
| M.F32Ty ->
true
| M.BoolTy ->
true
| _ ->
false)
and (* types.bend:1186 *)
f_annotation_row_names : M.t_EffectRow -> (M.t_Ty) list =
fun v_row ->
(match v_row with
| (M.EffectRow (v_operations, (M.FreeRow (v_scope, v_name)))) ->
[(M.FreeTy (v_scope, v_name))]
| _ ->
[])
and (* types.bend:1193 *)
f_annotation_names : int -> t_TypeWork -> (M.t_Diagnostic, (M.t_Ty) list) Base.result_ =
fun v_fuel v_work ->
(match (v_fuel, v_work) with
| (0, _) ->
(Fail ((f_complexity ())))
| (__nat_112, (OneType ((M.FreeTy (v_scope, v_name))))) when __nat_112 >= 1 ->
(let v_rest = (__nat_112 - 1) in
(Done ([(M.FreeTy (v_scope, v_name))])))
| (__nat_113, (OneType ((M.FunctionTy (v_parameter, v_result, v_row))))) when __nat_113 >= 1 ->
(let v_rest = (__nat_113 - 1) in
(match (f_annotation_names (v_rest) ((ManyTypes ([v_parameter; v_result])))) with
| Fail __error -> Fail __error
| Done v_nested ->
(Done ((Base.list_append (v_nested) ((f_annotation_row_names (v_row))))))))
| (__nat_114, (OneType ((M.ProviderTy (v_identity, v_row))))) when __nat_114 >= 1 ->
(let v_rest = (__nat_114 - 1) in
(Done ((f_annotation_row_names (v_row)))))
| (__nat_115, (OneType ((M.AppliedTy (v_identity, v_arguments))))) when __nat_115 >= 1 ->
(let v_rest = (__nat_115 - 1) in
(f_annotation_names (v_rest) ((ManyTypes (v_arguments)))))
| (__nat_116, (OneType ((M.ProductTy (v_elements))))) when __nat_116 >= 1 ->
(let v_rest = (__nat_116 - 1) in
(f_annotation_names (v_rest) ((ManyTypes (v_elements)))))
| (__nat_117, (OneType ((M.ArrayTy (v_element))))) when __nat_117 >= 1 ->
(let v_rest = (__nat_117 - 1) in
(f_annotation_names (v_rest) ((OneType (v_element)))))
| (__nat_118, (OneType ((M.StateProviderTy (v_read, v_write, v_state))))) when __nat_118 >= 1 ->
(let v_rest = (__nat_118 - 1) in
(f_annotation_names (v_rest) ((OneType (v_state)))))
| (__nat_119, (ManyTypes ((v_head :: v_tail)))) when __nat_119 >= 1 ->
(let v_rest = (__nat_119 - 1) in
(match (f_annotation_names (v_rest) ((OneType (v_head)))) with
| Fail __error -> Fail __error
| Done v_first ->
(match (f_annotation_names (v_rest) ((ManyTypes (v_tail)))) with
| Fail __error -> Fail __error
| Done v_following ->
(Done ((Base.list_append (v_first) (v_following)))))))
| (__nat_120, _) when __nat_120 >= 1 ->
(let v_rest = (__nat_120 - 1) in
(Done ([]))))
