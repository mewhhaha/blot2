(* Native semantic port of compiler/array_reuse.bend.

   Source SHA-256: 791d556017d9cd8dcbcdf3ecb1fed2986873fb8155a56f25cbf3f3ec2445240b

   Ownership/type arguments are erased; value types are checked by OCaml.

   No Bend interpreter or generated C/JavaScript is linked. *)

open Base

module M = Ox_model

module I = Ox_codegen_ir

module Index = Ox_index

type t_Usage =
  | Usage of int * int
and t_Scan =
  | Scan of I.t_Expr * bool
  | ScanExpressions of (I.t_Expr) list
and t_Edited =
  | Edited of (I.t_Expr) list * bool * int
and t_Work =
  | Expression of I.t_Expr
  | Expressions of (I.t_Expr) list * (I.t_Expr) list

let s_0 = Base.text_of_utf8 "internal_error"

let s_1 = Base.text_of_utf8 "array ownership"

let s_2 = Base.text_of_utf8 "ownership traversal lost an expression child"

let s_3 = Base.text_of_utf8 "backend_limit"

let s_4 = Base.text_of_utf8 "ownership scan exceeded its structural limit"

let s_5 = Base.text_of_utf8 "ownership rewrite exceeded its structural limit"

let rec (* array_reuse.bend:8 *)
f_arm_bodies : ((I.t_Expr) M.t_MatchArm) list -> (I.t_Expr) list =
fun v_arms ->
(match v_arms with
| [] ->
[]
| ((M.MatchArm (v_patterns, v_body)) :: v_tail) ->
(v_body :: (f_arm_bodies (v_tail))))
and (* array_reuse.bend:15 *)
f_children : I.t_Expr -> (I.t_Expr) list =
fun v_expression ->
(match v_expression with
| (I.ConstructExpr (v_constructor, (Some (v_payload)))) ->
[v_payload]
| (I.ApplyExpr (v_callee, v_argument)) ->
[v_callee; v_argument]
| (I.CallExpr (v_key, v_argument)) ->
[v_argument]
| (I.ScalarExpr (v_operator, v_left, v_right)) ->
[v_left; v_right]
| (I.LetExpr (v_name, v_value, v_body)) ->
[v_value; v_body]
| (I.IfExpr (v_condition, v_consequent, v_alternative)) ->
[v_condition; v_consequent; v_alternative]
| (I.SequenceExpr (v_first, v_next)) ->
[v_first; v_next]
| (I.GuardExpr (v_pattern, v_value, v_alternative, v_body)) ->
[v_value; v_alternative; v_body]
| (I.BlockExpr (v_label, v_body)) ->
[v_body]
| (I.ReturnExpr (v_label, v_value)) ->
[v_value]
| (I.UnaryExpr (v_operator, v_value)) ->
[v_value]
| (I.ProviderExpr (v_identity, v_implementation)) ->
[v_implementation]
| (I.StateProviderExpr (v_read, v_write, v_initial)) ->
[v_initial]
| (I.HandleExpr (v_provider, v_body)) ->
[v_provider; v_body]
| (I.InvokeOperationExpr (v_identity, v_argument)) ->
[v_argument]
| (I.ProjectExpr (v_value, v_index)) ->
[v_value]
| (I.ForExpr (v_index, v_start, v_end, v_state, v_initial, v_body)) ->
[v_start; v_end; v_initial; v_body]
| (I.ForeverExpr (v_state, v_initial, v_body, v_compact)) ->
[v_initial; v_body]
| (I.ArrayGenerateExpr (v_count, v_generator)) ->
[v_count; v_generator]
| (I.ArrayFillExpr (v_count, v_value)) ->
[v_count; v_value]
| (I.ArrayGetExpr (v_array, v_index)) ->
[v_array; v_index]
| (I.ArraySetExpr (v_array, v_index, v_value)) ->
[v_array; v_index; v_value]
| (I.ArrayReuseExpr (v_array, v_index, v_value)) ->
[v_array; v_index; v_value]
| (I.ArrayLengthExpr (v_array)) ->
[v_array]
| (I.MatchExpr (v_values, v_arms)) ->
(Base.list_append (v_values) ((f_arm_bodies (v_arms))))
| (I.ArrayExpr (v_elements)) ->
v_elements
| (I.ProductExpr (v_elements)) ->
v_elements
| _ ->
[])
and (* array_reuse.bend:74 *)
f_invalid : unit -> M.t_Diagnostic =
fun () ->
(M.Diagnostic (s_0, s_1, s_2))
and (* array_reuse.bend:77 *)
f_one : (I.t_Expr) list -> (M.t_Diagnostic, I.t_Expr) Base.result_ =
fun v_expressions ->
(match v_expressions with
| (v_expression :: []) ->
(Done (v_expression))
| _ ->
(Fail ((f_invalid ()))))
and (* array_reuse.bend:84 *)
f_rebuild_arms : ((I.t_Expr) M.t_MatchArm) list -> (I.t_Expr) list -> (M.t_Diagnostic, ((I.t_Expr) M.t_MatchArm) list) Base.result_ =
fun v_arms v_bodies ->
(match (v_arms, v_bodies) with
| ([], []) ->
(Done ([]))
| (((M.MatchArm (v_patterns, v_body)) :: v_tail), (v_first :: v_rest)) ->
(match (f_rebuild_arms (v_tail) (v_rest)) with
| Fail __error -> Fail __error
| Done v_next ->
(Done (((M.MatchArm (v_patterns, v_first)) :: v_next))))
| (_, _) ->
(Fail ((f_invalid ()))))
and (* array_reuse.bend:95 *)
f_rebuild : I.t_Expr -> (I.t_Expr) list -> (M.t_Diagnostic, I.t_Expr) Base.result_ =
fun v_original v_children ->
(match (v_original, v_children) with
| ((I.ConstructExpr (v_constructor, (Some (v_payload)))), (v_payload_new :: [])) ->
(Done ((I.ConstructExpr (v_constructor, (Some (v_payload_new))))))
| ((I.ApplyExpr (v_callee, v_argument)), (v_callee_new :: (v_argument_new :: []))) ->
(Done ((I.ApplyExpr (v_callee_new, v_argument_new))))
| ((I.CallExpr (v_key, v_argument)), (v_argument_new :: [])) ->
(Done ((I.CallExpr (v_key, v_argument_new))))
| ((I.ScalarExpr (v_operator, v_left, v_right)), (v_left_new :: (v_right_new :: []))) ->
(Done ((I.ScalarExpr (v_operator, v_left_new, v_right_new))))
| ((I.LetExpr (v_name, v_value, v_body)), (v_value_new :: (v_body_new :: []))) ->
(Done ((I.LetExpr (v_name, v_value_new, v_body_new))))
| ((I.IfExpr (v_condition, v_consequent, v_alternative)), (v_condition_new :: (v_consequent_new :: (v_alternative_new :: [])))) ->
(Done ((I.IfExpr (v_condition_new, v_consequent_new, v_alternative_new))))
| ((I.SequenceExpr (v_first, v_next)), (v_first_new :: (v_next_new :: []))) ->
(Done ((I.SequenceExpr (v_first_new, v_next_new))))
| ((I.GuardExpr (v_pattern, v_value, v_alternative, v_body)), (v_value_new :: (v_alternative_new :: (v_body_new :: [])))) ->
(Done ((I.GuardExpr (v_pattern, v_value_new, v_alternative_new, v_body_new))))
| ((I.BlockExpr (v_label, v_body)), (v_body_new :: [])) ->
(Done ((I.BlockExpr (v_label, v_body_new))))
| ((I.ReturnExpr (v_label, v_value)), (v_value_new :: [])) ->
(Done ((I.ReturnExpr (v_label, v_value_new))))
| ((I.UnaryExpr (v_operator, v_value)), (v_value_new :: [])) ->
(Done ((I.UnaryExpr (v_operator, v_value_new))))
| ((I.ProviderExpr (v_identity, v_implementation)), (v_implementation_new :: [])) ->
(Done ((I.ProviderExpr (v_identity, v_implementation_new))))
| ((I.StateProviderExpr (v_read, v_write, v_initial)), (v_initial_new :: [])) ->
(Done ((I.StateProviderExpr (v_read, v_write, v_initial_new))))
| ((I.HandleExpr (v_provider, v_body)), (v_provider_new :: (v_body_new :: []))) ->
(Done ((I.HandleExpr (v_provider_new, v_body_new))))
| ((I.InvokeOperationExpr (v_identity, v_argument)), (v_argument_new :: [])) ->
(Done ((I.InvokeOperationExpr (v_identity, v_argument_new))))
| ((I.ProjectExpr (v_value, v_index)), (v_value_new :: [])) ->
(Done ((I.ProjectExpr (v_value_new, v_index))))
| ((I.ForExpr (v_index, v_start, v_end, v_state, v_initial, v_body)), (v_start_new :: (v_end_new :: (v_initial_new :: (v_body_new :: []))))) ->
(Done ((I.ForExpr (v_index, v_start_new, v_end_new, v_state, v_initial_new, v_body_new))))
| ((I.ForeverExpr (v_state, v_initial, v_body, v_compact)), (v_initial_new :: (v_body_new :: []))) ->
(Done ((I.ForeverExpr (v_state, v_initial_new, v_body_new, v_compact))))
| ((I.ArrayGenerateExpr (v_count, v_generator)), (v_count_new :: (v_generator_new :: []))) ->
(Done ((I.ArrayGenerateExpr (v_count_new, v_generator_new))))
| ((I.ArrayFillExpr (v_count, v_value)), (v_count_new :: (v_value_new :: []))) ->
(Done ((I.ArrayFillExpr (v_count_new, v_value_new))))
| ((I.ArrayGetExpr (v_array, v_index)), (v_array_new :: (v_index_new :: []))) ->
(Done ((I.ArrayGetExpr (v_array_new, v_index_new))))
| ((I.ArraySetExpr (v_array, v_index, v_value)), (v_array_new :: (v_index_new :: (v_value_new :: [])))) ->
(Done ((I.ArraySetExpr (v_array_new, v_index_new, v_value_new))))
| ((I.ArrayReuseExpr (v_array, v_index, v_value)), (v_array_new :: (v_index_new :: (v_value_new :: [])))) ->
(Done ((I.ArrayReuseExpr (v_array_new, v_index_new, v_value_new))))
| ((I.ArrayLengthExpr (v_array)), (v_array_new :: [])) ->
(Done ((I.ArrayLengthExpr (v_array_new))))
| ((I.MatchExpr (v_values, v_arms)), v_children) ->
(let v_count = (Base.list_length (v_values)) in
(match (f_rebuild_arms (v_arms) ((Base.list_drop (v_children) (v_count)))) with
| Fail __error -> Fail __error
| Done v_branches ->
(Done ((I.MatchExpr ((Base.list_take (v_children) (v_count)), v_branches))))))
| ((I.ArrayExpr (v_old)), v_elements) ->
(Done ((I.ArrayExpr (v_elements))))
| ((I.ProductExpr (v_old)), v_elements) ->
(Done ((I.ProductExpr (v_elements))))
| (v_original, []) ->
(Done (v_original))
| (_, _) ->
(Fail ((f_invalid ()))))
and (* array_reuse.bend:162 *)
f_reference_count : t_Usage -> Base.text -> bool -> int -> (t_Usage) Base.map -> (t_Usage) Base.map =
fun v_usage v_name v_borrowed v_position v_usages ->
(let (Usage (v_escapes, v_last)) = v_usage in
(Base.map_set (v_usages) (v_name) ((Usage ((Base.nat_add (v_escapes) ((Base.bool_pick (v_borrowed) (0) (1)))), v_position)))))
and (* array_reuse.bend:166 *)
f_reference : Base.text -> bool -> int -> (t_Usage) Base.map -> (t_Usage) Base.map =
fun v_name v_borrowed v_position v_usages ->
(f_reference_count ((Index.f_get (v_usages) (v_name) ((Usage (0, 0))))) (v_name) (v_borrowed) (v_position) (v_usages))
and (* array_reuse.bend:169 *)
f_captures : (Base.text) list -> int -> (t_Usage) Base.map -> (t_Usage) Base.map =
fun v_names v_position v_usages ->
(match v_names with
| [] ->
v_usages
| (v_name :: v_tail) ->
(f_captures (v_tail) (v_position) ((f_reference (v_name) (false) (v_position) (v_usages)))))
and (* array_reuse.bend:180 *)
f_scan : int -> (t_Scan) list -> (t_Usage) Base.map -> int -> (M.t_Diagnostic, (t_Usage) Base.map) Base.result_ =
fun v_fuel v_pending v_usages v_position ->
(match (v_fuel, v_pending) with
| (_, []) ->
(Done (v_usages))
| (0, _) ->
(Fail ((M.Diagnostic (s_3, s_1, s_4))))
| (__nat_1, ((Scan ((I.LocalExpr (v_name)), v_borrowed)) :: v_tail)) when __nat_1 >= 1 ->
(let v_rest = (__nat_1 - 1) in
(f_scan (v_rest) (v_tail) ((f_reference (v_name) (v_borrowed) (v_position) (v_usages))) ((Base.nat_add 1 v_position))))
| (__nat_2, ((Scan ((I.ClosureExpr (v_key, v_names)), v_borrowed)) :: v_tail)) when __nat_2 >= 1 ->
(let v_rest = (__nat_2 - 1) in
(f_scan (v_rest) (v_tail) ((f_captures (v_names) (v_position) (v_usages))) ((Base.nat_add 1 v_position))))
| (__nat_3, ((Scan ((I.ArrayGetExpr (v_array, v_index)), v_borrowed)) :: v_tail)) when __nat_3 >= 1 ->
(let v_rest = (__nat_3 - 1) in
(f_scan (v_rest) (((Scan (v_array, true)) :: ((Scan (v_index, false)) :: v_tail))) (v_usages) ((Base.nat_add 1 v_position))))
| (__nat_4, ((Scan ((I.ArrayLengthExpr (v_array)), v_borrowed)) :: v_tail)) when __nat_4 >= 1 ->
(let v_rest = (__nat_4 - 1) in
(f_scan (v_rest) (((Scan (v_array, true)) :: v_tail)) (v_usages) ((Base.nat_add 1 v_position))))
| (__nat_5, ((Scan (v_expression, v_borrowed)) :: v_tail)) when __nat_5 >= 1 ->
(let v_rest = (__nat_5 - 1) in
(f_scan (v_rest) (((ScanExpressions ((f_children (v_expression)))) :: v_tail)) (v_usages) ((Base.nat_add 1 v_position))))
| (__nat_6, ((ScanExpressions ([])) :: v_tail)) when __nat_6 >= 1 ->
(let v_rest = (__nat_6 - 1) in
(f_scan (v_rest) (v_tail) (v_usages) (v_position)))
| (__nat_7, ((ScanExpressions ((v_head :: v_following))) :: v_tail)) when __nat_7 >= 1 ->
(let v_rest = (__nat_7 - 1) in
(f_scan (v_rest) (((Scan (v_head, false)) :: ((ScanExpressions (v_following)) :: v_tail))) (v_usages) (v_position))))
and (* array_reuse.bend:201 *)
f_consumed : t_Usage -> int -> bool =
fun v_usage v_end ->
(let (Usage (v_escapes, v_last)) = v_usage in
(Base.bool_and ((Base.nat_is_eq (v_escapes) (1))) ((Base.nat_is_lt (v_last) (v_end)))))
and (* array_reuse.bend:205 *)
f_transferable : Base.text -> (bool) Base.map -> (t_Usage) Base.map -> int -> bool =
fun v_name v_owned v_usages v_end ->
(Base.bool_and ((Index.f_get (v_owned) (v_name) (false))) ((f_consumed ((Index.f_get (v_usages) (v_name) ((Usage (0, 0))))) (v_end))))
and (* array_reuse.bend:211 *)
f_expressions : t_Edited -> (I.t_Expr) list =
fun v_result ->
(let (Edited (v_expressions, v_owned, v_next)) = v_result in
v_expressions)
and (* array_reuse.bend:215 *)
f_owned : t_Edited -> bool =
fun v_result ->
(let (Edited (v_expressions, v_owned, v_next)) = v_result in
v_owned)
and (* array_reuse.bend:219 *)
f_next : t_Edited -> int =
fun v_result ->
(let (Edited (v_expressions, v_owned, v_next)) = v_result in
v_next)
and (* array_reuse.bend:223 *)
f_reusable : I.t_Expr -> bool -> (bool) Base.map -> (t_Usage) Base.map -> int -> bool =
fun v_original v_inferred v_ownership v_usages v_end ->
(match v_original with
| (I.LocalExpr (v_name)) ->
(f_transferable (v_name) (v_ownership) (v_usages) (v_end))
| _ ->
v_inferred)
and (* array_reuse.bend:230 *)
f_update : bool -> I.t_Expr -> I.t_Expr -> I.t_Expr -> I.t_Expr =
fun v_reuse v_array v_index v_value ->
(match v_reuse with
| true ->
(I.ArrayReuseExpr (v_array, v_index, v_value))
| false ->
(I.ArraySetExpr (v_array, v_index, v_value)))
and (* array_reuse.bend:237 *)
f_fresh : I.t_Expr -> (bool) Base.map -> (t_Usage) Base.map -> int -> bool =
fun v_expression v_ownership v_usages v_end ->
(match v_expression with
| (I.ArrayExpr (v_elements)) ->
true
| (I.ArrayFillExpr (v_count, v_value)) ->
true
| (I.ArrayGenerateExpr (v_count, v_generator)) ->
true
| (I.LocalExpr (v_name)) ->
(f_transferable (v_name) (v_ownership) (v_usages) (v_end))
| _ ->
false)
and (* array_reuse.bend:250 *)
f_branch_scope : I.t_Expr -> (bool) Base.map -> (bool) Base.map =
fun v_expression v_ownership ->
(match v_expression with
| (I.MatchExpr (v_values, v_arms)) ->
(Base.map_new ())
| (I.GuardExpr (v_pattern, v_value, v_alternative, v_body)) ->
(Base.map_new ())
| _ ->
v_ownership)
and (* array_reuse.bend:263 *)
f_rewrite : int -> t_Work -> (bool) Base.map -> (t_Usage) Base.map -> int -> (M.t_Diagnostic, t_Edited) Base.result_ =
fun v_fuel v_work v_ownership v_usages v_position ->
(match (v_fuel, v_work) with
| (0, _) ->
(Fail ((M.Diagnostic (s_3, s_1, s_5))))
| (__nat_8, (Expression ((I.LetExpr (v_name, v_value, v_body))))) when __nat_8 >= 1 ->
(let v_rest = (__nat_8 - 1) in
(match (f_rewrite (v_rest) ((Expression (v_value))) (v_ownership) (v_usages) ((Base.nat_add 1 v_position))) with
| Fail __error -> Fail __error
| Done v_v ->
(match (f_one ((f_expressions (v_v)))) with
| Fail __error -> Fail __error
| Done v_value ->
(match (f_rewrite (v_rest) ((Expression (v_body))) ((Base.map_set (v_ownership) (v_name) ((f_owned (v_v))))) (v_usages) ((f_next (v_v)))) with
| Fail __error -> Fail __error
| Done v_b ->
(match (f_one ((f_expressions (v_b)))) with
| Fail __error -> Fail __error
| Done v_body ->
(Done ((Edited ([(I.LetExpr (v_name, v_value, v_body))], (f_owned (v_b)), (f_next (v_b)))))))))))
| (__nat_9, (Expression ((I.ForExpr (v_index, v_start, v_end, v_state, v_initial, v_body))))) when __nat_9 >= 1 ->
(let v_rest = (__nat_9 - 1) in
(match (f_rewrite (v_rest) ((Expression (v_start))) (v_ownership) (v_usages) ((Base.nat_add 1 v_position))) with
| Fail __error -> Fail __error
| Done v_s ->
(match (f_one ((f_expressions (v_s)))) with
| Fail __error -> Fail __error
| Done v_start ->
(match (f_rewrite (v_rest) ((Expression (v_end))) (v_ownership) (v_usages) ((f_next (v_s)))) with
| Fail __error -> Fail __error
| Done v_e ->
(match (f_one ((f_expressions (v_e)))) with
| Fail __error -> Fail __error
| Done v_end ->
(match (f_rewrite (v_rest) ((Expression (v_initial))) (v_ownership) (v_usages) ((f_next (v_e)))) with
| Fail __error -> Fail __error
| Done v_i ->
(match (f_one ((f_expressions (v_i)))) with
| Fail __error -> Fail __error
| Done v_initial ->
(match (f_rewrite (v_rest) ((Expression (v_body))) ((Base.map_set ((Base.map_new ())) (v_state) ((f_owned (v_i))))) (v_usages) ((f_next (v_i)))) with
| Fail __error -> Fail __error
| Done v_b ->
(match (f_one ((f_expressions (v_b)))) with
| Fail __error -> Fail __error
| Done v_body ->
(Done ((Edited ([(I.ForExpr (v_index, v_start, v_end, v_state, v_initial, v_body))], (Base.bool_and ((f_owned (v_i))) ((f_owned (v_b)))), (f_next (v_b)))))))))))))))
| (__nat_10, (Expression ((I.ForeverExpr (v_state, v_initial, v_body, v_compact))))) when __nat_10 >= 1 ->
(let v_rest = (__nat_10 - 1) in
(match (f_rewrite (v_rest) ((Expression (v_initial))) (v_ownership) (v_usages) ((Base.nat_add 1 v_position))) with
| Fail __error -> Fail __error
| Done v_i ->
(match (f_one ((f_expressions (v_i)))) with
| Fail __error -> Fail __error
| Done v_prepared ->
(match (f_rewrite (v_rest) ((Expression (v_body))) ((Base.map_set ((Base.map_new ())) (v_state) (false))) (v_usages) ((f_next (v_i)))) with
| Fail __error -> Fail __error
| Done v_b ->
(match (f_one ((f_expressions (v_b)))) with
| Fail __error -> Fail __error
| Done v_rewritten ->
(Done ((Edited ([(I.ForeverExpr (v_state, v_prepared, v_rewritten, v_compact))], (Base.bool_and ((f_owned (v_i))) ((f_owned (v_b)))), (f_next (v_b)))))))))))
| (__nat_11, (Expression ((I.ArraySetExpr (v_array, v_index, v_value))))) when __nat_11 >= 1 ->
(let v_rest = (__nat_11 - 1) in
(match (f_rewrite (v_rest) ((Expression (v_array))) (v_ownership) (v_usages) ((Base.nat_add 1 v_position))) with
| Fail __error -> Fail __error
| Done v_a ->
(match (f_one ((f_expressions (v_a)))) with
| Fail __error -> Fail __error
| Done v_prepared_array ->
(match (f_rewrite (v_rest) ((Expression (v_index))) (v_ownership) (v_usages) ((f_next (v_a)))) with
| Fail __error -> Fail __error
| Done v_i ->
(match (f_one ((f_expressions (v_i)))) with
| Fail __error -> Fail __error
| Done v_index ->
(match (f_rewrite (v_rest) ((Expression (v_value))) (v_ownership) (v_usages) ((f_next (v_i)))) with
| Fail __error -> Fail __error
| Done v_v ->
(match (f_one ((f_expressions (v_v)))) with
| Fail __error -> Fail __error
| Done v_value ->
(Done ((Edited ([(f_update ((f_reusable (v_array) ((f_owned (v_a))) (v_ownership) (v_usages) ((f_next (v_v))))) (v_prepared_array) (v_index) (v_value))], true, (f_next (v_v)))))))))))))
| (__nat_12, (Expression ((I.SequenceExpr (v_first, v_following))))) when __nat_12 >= 1 ->
(let v_rest = (__nat_12 - 1) in
(match (f_rewrite (v_rest) ((Expression (v_first))) (v_ownership) (v_usages) ((Base.nat_add 1 v_position))) with
| Fail __error -> Fail __error
| Done v_a ->
(match (f_one ((f_expressions (v_a)))) with
| Fail __error -> Fail __error
| Done v_first ->
(match (f_rewrite (v_rest) ((Expression (v_following))) (v_ownership) (v_usages) ((f_next (v_a)))) with
| Fail __error -> Fail __error
| Done v_b ->
(match (f_one ((f_expressions (v_b)))) with
| Fail __error -> Fail __error
| Done v_following ->
(Done ((Edited ([(I.SequenceExpr (v_first, v_following))], (f_owned (v_b)), (f_next (v_b)))))))))))
| (__nat_13, (Expression (v_expression))) when __nat_13 >= 1 ->
(let v_rest = (__nat_13 - 1) in
(match (f_rewrite (v_rest) ((Expressions ((f_children (v_expression)), []))) ((f_branch_scope (v_expression) (v_ownership))) (v_usages) ((Base.nat_add 1 v_position))) with
| Fail __error -> Fail __error
| Done v_c ->
(match (f_rebuild (v_expression) ((f_expressions (v_c)))) with
| Fail __error -> Fail __error
| Done v_prepared ->
(Done ((Edited ([v_prepared], (f_fresh (v_prepared) (v_ownership) (v_usages) ((f_next (v_c)))), (f_next (v_c)))))))))
| (__nat_14, (Expressions ([], v_reversed))) when __nat_14 >= 1 ->
(let v_rest = (__nat_14 - 1) in
(Done ((Edited ((Base.list_reverse (v_reversed)), false, v_position)))))
| (__nat_15, (Expressions ((v_head :: v_tail), v_reversed))) when __nat_15 >= 1 ->
(let v_rest = (__nat_15 - 1) in
(match (f_rewrite (v_rest) ((Expression (v_head))) (v_ownership) (v_usages) (v_position)) with
| Fail __error -> Fail __error
| Done v_first ->
(match (f_one ((f_expressions (v_first)))) with
| Fail __error -> Fail __error
| Done v_value ->
(f_rewrite (v_rest) ((Expressions (v_tail, (v_value :: v_reversed)))) (v_ownership) (v_usages) ((f_next (v_first))))))))
and (* array_reuse.bend:323 *)
f_prepare : I.t_Expr -> (M.t_Diagnostic, I.t_Expr) Base.result_ =
fun v_expression ->
(match (f_scan (65536) ([(Scan (v_expression, false))]) ((Base.map_new ())) (0)) with
| Fail __error -> Fail __error
| Done v_usages ->
(match (f_rewrite (65536) ((Expression (v_expression))) ((Base.map_new ())) (v_usages) (0)) with
| Fail __error -> Fail __error
| Done v_result ->
(f_one ((f_expressions (v_result))))))
