(* Native semantic port of compiler/effect_rows.bend.

   Source SHA-256: ee075f75680328a1a74c7fb06ff3d7e28d4635f12774c289b7fc3effef6a7959

   Ownership/type arguments are erased; value types are checked by OCaml.

   No Bend interpreter or generated C/JavaScript is linked. *)

open Base

module M = Ox_model

type t_Binding =
  | Binding of int * M.t_EffectRow
and t_Solution =
  | Solution of (t_Binding) list * int
and t_Selection =
  | Selection of bool * (M.t_TypeId) list
and t_Extraction =
  | Extraction of M.t_EffectRow * t_Solution * (int) option

let s_0 = Base.text_of_utf8 "infinite_effect"

let s_1 = Base.text_of_utf8 "effect row occurs check failed"

let s_2 = Base.text_of_utf8 "effect_mismatch"

let s_3 = Base.text_of_utf8 "cannot unify effect rows"

let s_4 = Base.text_of_utf8 " and"

let s_5 = Base.text_of_utf8 "type_complexity"

let s_6 = Base.text_of_utf8 "effect row unification exceeded its structural limit"

let rec (* effect_rows.bend:16 *)
f_extraction_row : t_Extraction -> M.t_EffectRow =
fun v_extracted ->
(let (Extraction (v_remaining, v_solution, v_expanded)) = v_extracted in
v_remaining)
and (* effect_rows.bend:20 *)
f_extraction_solution : t_Extraction -> t_Solution =
fun v_extracted ->
(let (Extraction (v_remaining, v_solution, v_expanded)) = v_extracted in
v_solution)
and (* effect_rows.bend:24 *)
f_extraction_expanded : t_Extraction -> (int) option =
fun v_extracted ->
(let (Extraction (v_remaining, v_solution, v_expanded)) = v_extracted in
v_expanded)
and (* effect_rows.bend:28 *)
f_solution_bindings : t_Solution -> (t_Binding) list =
fun v_solution ->
(let (Solution (v_bindings, v_next)) = v_solution in
v_bindings)
and (* effect_rows.bend:32 *)
f_variable_row : int -> M.t_EffectRow =
fun v_index ->
(M.EffectRow ([], (M.RowVariable (v_index))))
and (* effect_rows.bend:35 *)
f_singleton : M.t_TypeId -> M.t_RowTail -> M.t_EffectRow =
fun v_identity v_tail ->
(M.EffectRow ([v_identity], v_tail))
and (* effect_rows.bend:38 *)
f_row_tail : M.t_EffectRow -> M.t_RowTail =
fun v_row ->
(let (M.EffectRow (v_operations, v_rest)) = v_row in
v_rest)
and (* effect_rows.bend:42 *)
f_row_operations : M.t_EffectRow -> (M.t_TypeId) list =
fun v_row ->
(let (M.EffectRow (v_labels, v_rest)) = v_row in
v_labels)
and (* effect_rows.bend:46 *)
f_prepend : (M.t_TypeId) list -> M.t_EffectRow -> M.t_EffectRow =
fun v_labels v_row ->
(let (M.EffectRow (v_remaining, v_rest)) = v_row in
(M.EffectRow ((Base.list_append (v_labels) (v_remaining)), v_rest)))
and (* effect_rows.bend:50 *)
f_same_variable : M.t_RowTail -> int -> bool =
fun v_rest v_index ->
(match v_rest with
| (M.RowVariable (v_found)) ->
(Base.nat_is_eq (v_found) (v_index))
| _ ->
false)
and (* effect_rows.bend:57 *)
f_replaced : bool -> M.t_EffectRow -> (M.t_TypeId) list -> M.t_EffectRow -> M.t_EffectRow =
fun v_found v_row v_labels v_replacement ->
(match v_found with
| false ->
v_row
| true ->
(f_prepend (v_labels) (v_replacement)))
and (* effect_rows.bend:64 *)
f_replace : M.t_EffectRow -> int -> M.t_EffectRow -> M.t_EffectRow =
fun v_row v_index v_replacement ->
(let (M.EffectRow (v_labels, v_rest)) = v_row in
(f_replaced ((f_same_variable (v_rest) (v_index))) (v_row) (v_labels) (v_replacement)))
and (* effect_rows.bend:68 *)
f_resolve : (t_Binding) list -> M.t_EffectRow -> M.t_EffectRow =
fun v_bindings v_row ->
(match v_bindings with
| [] ->
v_row
| ((Binding (v_variable, v_replacement)) :: v_rest) ->
(f_resolve (v_rest) ((f_replace (v_row) (v_variable) (v_replacement)))))
and (* effect_rows.bend:75 *)
f_infinite : Base.text -> M.t_Diagnostic =
fun v_subject ->
(M.Diagnostic (s_0, v_subject, s_1))
and (* effect_rows.bend:78 *)
f_mismatch : M.t_EffectRow -> M.t_EffectRow -> Base.text -> M.t_Diagnostic =
fun v_left v_right v_subject ->
(M.Diagnostic (s_2, v_subject, (Base.string_append s_3 (Base.string_append (M.f_row_show (v_left)) (Base.string_append s_4 (M.f_row_show (v_right)))))))
and (* effect_rows.bend:81 *)
f_bind_checked : bool -> int -> M.t_EffectRow -> t_Solution -> Base.text -> (M.t_Diagnostic, t_Solution) Base.result_ =
fun v_recursive v_index v_row v_solution v_subject ->
(match v_recursive with
| true ->
(Fail ((f_infinite (v_subject))))
| false ->
(let (Solution (v_bindings, v_next)) = v_solution in
(Done ((Solution ((Base.list_append (v_bindings) ([(Binding (v_index, v_row))])), v_next))))))
and (* effect_rows.bend:89 *)
f_bind : int -> M.t_EffectRow -> t_Solution -> Base.text -> (M.t_Diagnostic, t_Solution) Base.result_ =
fun v_index v_row v_solution v_subject ->
(f_bind_checked ((f_same_variable ((f_row_tail (v_row))) (v_index))) (v_index) (v_row) (v_solution) (v_subject))
and (* effect_rows.bend:92 *)
f_selected : bool -> M.t_TypeId -> (M.t_TypeId) list -> t_Selection -> t_Selection =
fun v_found v_head v_remaining v_result ->
(match v_found with
| true ->
(Selection (true, v_remaining))
| false ->
(let (Selection (v_present, v_tail)) = v_result in
(Selection (v_present, (v_head :: v_tail)))))
and (* effect_rows.bend:100 *)
f_select : (M.t_TypeId) list -> M.t_TypeId -> t_Selection =
fun v_labels v_identity ->
(match v_labels with
| [] ->
(Selection (false, []))
| (v_head :: v_rest) ->
(f_selected ((M.f_type_id_equal (v_head) (v_identity))) (v_head) (v_rest) ((f_select (v_rest) (v_identity)))))
and (* effect_rows.bend:107 *)
f_extract_tail : M.t_RowTail -> (M.t_TypeId) list -> M.t_TypeId -> t_Solution -> Base.text -> (M.t_Diagnostic, t_Extraction) Base.result_ =
fun v_rest v_labels v_identity v_solution v_subject ->
(match v_rest with
| (M.RowVariable (v_index)) ->
(let (Solution (v_bindings, v_next)) = v_solution in
(let v_row = (f_singleton (v_identity) ((M.RowVariable (v_next)))) in
(Done ((Extraction ((M.EffectRow (v_labels, (M.RowVariable (v_next)))), (Solution ((Base.list_append (v_bindings) ([(Binding (v_index, v_row))])), (Base.nat_add 1 v_next))), (Some (v_index))))))))
| v_other ->
(Fail ((f_mismatch ((M.EffectRow (v_labels, v_other))) ((f_singleton (v_identity) (M.ClosedRow))) (v_subject)))))
and (* effect_rows.bend:116 *)
f_extract_selected : t_Selection -> M.t_RowTail -> M.t_TypeId -> t_Solution -> Base.text -> (M.t_Diagnostic, t_Extraction) Base.result_ =
fun v_selected v_rest v_identity v_solution v_subject ->
(match v_selected with
| (Selection (true, v_remaining)) ->
(Done ((Extraction ((M.EffectRow (v_remaining, v_rest)), v_solution, None))))
| (Selection (false, v_remaining)) ->
(f_extract_tail (v_rest) (v_remaining) (v_identity) (v_solution) (v_subject)))
and (* effect_rows.bend:123 *)
f_extract : M.t_EffectRow -> M.t_TypeId -> t_Solution -> Base.text -> (M.t_Diagnostic, t_Extraction) Base.result_ =
fun v_row v_identity v_solution v_subject ->
(let (M.EffectRow (v_labels, v_rest)) = v_row in
(f_extract_selected ((f_select (v_labels) (v_identity))) (v_rest) (v_identity) (v_solution) (v_subject)))
and (* effect_rows.bend:127 *)
f_safe_expansion : M.t_RowTail -> (int) option -> Base.text -> (M.t_Diagnostic, unit) Base.result_ =
fun v_rest v_expanded v_subject ->
(match (v_rest, v_expanded) with
| ((M.RowVariable (v_left)), (Some (v_right))) ->
(Base.bool_pick ((Base.nat_is_eq (v_left) (v_right))) ((Fail ((f_infinite (v_subject))))) ((Done (()))))
| (_, _) ->
(Done (())))
and (* effect_rows.bend:134 *)
f_unify_tails : M.t_RowTail -> M.t_RowTail -> t_Solution -> Base.text -> (M.t_Diagnostic, t_Solution) Base.result_ =
fun v_left v_right v_solution v_subject ->
(match (v_left, v_right) with
| (M.ClosedRow, M.ClosedRow) ->
(Done (v_solution))
| ((M.RowVariable (v_a)), (M.RowVariable (v_b))) ->
(Base.bool_pick ((Base.nat_is_eq (v_a) (v_b))) ((Done (v_solution))) ((f_bind (v_a) ((f_variable_row (v_b))) (v_solution) (v_subject))))
| ((M.RowVariable (v_index)), v_other) ->
(f_bind (v_index) ((M.EffectRow ([], v_other))) (v_solution) (v_subject))
| (v_other, (M.RowVariable (v_index))) ->
(f_bind (v_index) ((M.EffectRow ([], v_other))) (v_solution) (v_subject))
| ((M.RowParameter (v_a)), (M.RowParameter (v_b))) ->
(Base.bool_pick ((Base.nat_is_eq (v_a) (v_b))) ((Done (v_solution))) ((Fail ((f_mismatch ((M.EffectRow ([], (M.RowParameter (v_a))))) ((M.EffectRow ([], (M.RowParameter (v_b))))) (v_subject))))))
| (v_a, v_b) ->
(Fail ((f_mismatch ((M.EffectRow ([], v_a))) ((M.EffectRow ([], v_b))) (v_subject)))))
and (* effect_rows.bend:149 *)
f_unify_work : int -> M.t_EffectRow -> M.t_EffectRow -> t_Solution -> Base.text -> (M.t_Diagnostic, t_Solution) Base.result_ =
fun v_fuel v_left v_right v_solution v_subject ->
(match (v_fuel, v_left, v_right) with
| (0, _, _) ->
(Fail ((M.Diagnostic (s_5, v_subject, s_6))))
| (__nat_1, (M.EffectRow ([], v_a)), (M.EffectRow ([], v_b))) when __nat_1 >= 1 ->
(let v_rest = (__nat_1 - 1) in
(f_unify_tails (v_a) (v_b) (v_solution) (v_subject)))
| (__nat_2, (M.EffectRow ([], (M.RowVariable (v_index)))), v_other) when __nat_2 >= 1 ->
(let v_rest = (__nat_2 - 1) in
(f_bind (v_index) (v_other) (v_solution) (v_subject)))
| (__nat_3, v_other, (M.EffectRow ([], (M.RowVariable (v_index))))) when __nat_3 >= 1 ->
(let v_rest = (__nat_3 - 1) in
(f_bind (v_index) (v_other) (v_solution) (v_subject)))
| (__nat_4, (M.EffectRow ((v_identity :: v_labels), v_a)), v_other) when __nat_4 >= 1 ->
(let v_rest = (__nat_4 - 1) in
(match (f_extract (v_other) (v_identity) (v_solution) (v_subject)) with
| Fail __error -> Fail __error
| Done v_extracted ->
(let v_next = (f_extraction_solution (v_extracted)) in
(let v_bindings = (f_solution_bindings (v_next)) in
(match (f_safe_expansion (v_a) ((f_extraction_expanded (v_extracted))) (v_subject)) with
| Fail __error -> Fail __error
| Done v_valid ->
(f_unify_work (v_rest) ((f_resolve (v_bindings) ((M.EffectRow (v_labels, v_a))))) ((f_resolve (v_bindings) ((f_extraction_row (v_extracted))))) (v_next) (v_subject)))))))
| (__nat_5, v_a, v_b) when __nat_5 >= 1 ->
(let v_rest = (__nat_5 - 1) in
(Fail ((f_mismatch (v_a) (v_b) (v_subject))))))
and (* effect_rows.bend:169 *)
f_unify : M.t_EffectRow -> M.t_EffectRow -> (t_Binding) list -> int -> Base.text -> (M.t_Diagnostic, t_Solution) Base.result_ =
fun v_left v_right v_bindings v_next v_subject ->
(f_unify_work ((Base.u32_to_nat ((Base.W32 0x10000)))) ((f_resolve (v_bindings) (v_left))) ((f_resolve (v_bindings) (v_right))) ((Solution (v_bindings, v_next))) (v_subject))
and (* effect_rows.bend:172 *)
f_operation_le : M.t_TypeId -> M.t_TypeId -> bool =
fun v_left v_right ->
(let (M.TypeId (v_lm, v_ln)) = v_left in
(let (M.TypeId (v_rm, v_rn)) = v_right in
(Base.bool_or ((Base.string_is_lt (v_lm) (v_rm))) ((Base.bool_and ((M.f_name_equal (v_lm) (v_rm))) ((Base.string_is_le (v_ln) (v_rn))))))))
and (* effect_rows.bend:177 *)
f_canonical : M.t_EffectRow -> M.t_EffectRow =
fun v_row ->
(let (M.EffectRow (v_labels, v_rest)) = v_row in
(M.EffectRow ((Base.list_sort (f_operation_le) (v_labels)), v_rest)))
and (* effect_rows.bend:181 *)
f_distinct_sorted : (M.t_TypeId) list -> (M.t_TypeId) option -> (M.t_TypeId) list =
fun v_labels v_previous ->
(match (v_labels, v_previous) with
| ([], _) ->
[]
| ((v_head :: v_rest), None) ->
(v_head :: (f_distinct_sorted (v_rest) ((Some (v_head)))))
| ((v_head :: v_rest), (Some (v_last))) ->
(let v_remaining = (f_distinct_sorted (v_rest) ((Some (v_head)))) in
(Base.bool_pick ((M.f_type_id_equal (v_head) (v_last))) (v_remaining) ((v_head :: v_remaining)))))
and (* effect_rows.bend:191 *)
f_operation_set : M.t_EffectRow -> (M.t_TypeId) list =
fun v_row ->
(f_distinct_sorted ((f_row_operations ((f_canonical (v_row))))) (None))
and (* effect_rows.bend:194 *)
f_metadata : (M.t_TypeId) list -> (M.t_Effect) list =
fun v_operations ->
(match v_operations with
| [] ->
[]
| (v_identity :: v_rest) ->
((M.OperationEffect (v_identity)) :: (f_metadata (v_rest))))
