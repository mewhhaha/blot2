(* Native semantic port of compiler/codegen_saturation.bend.

   Source SHA-256: 3fad643d72f4b8c4980f26e6c5fe2d508b4a284cb44305b63f073f259f5c8b50

   Ownership/type arguments are erased; value types are checked by OCaml.

   No Bend interpreter or generated C/JavaScript is linked. *)

open Base

module M = Ox_model

module F = Ox_closures

module Mono = Ox_monomorph

module Index = Ox_index

type t_Definition =
  | Definition of Base.text * (Base.text) list * M.t_Expr
and t_Application =
  | Application of M.t_Expr * (M.t_Expr) list
and t_Candidate =
  | Candidate of t_Definition * (M.t_Expr) list
and t_Edited =
  | Edited of (M.t_Expr) list * int * int
and t_Work =
  | Expression of M.t_Expr
  | Expressions of (M.t_Expr) list * (M.t_Expr) list
  | Attempt of M.t_Expr * (t_Candidate) option
  | Expand of M.t_Expr * t_Candidate * int * bool

let s_0 = Base.text_of_utf8 "fn:"

let s_1 = Base.text_of_utf8 "lambda:"

let s_2 = Base.text_of_utf8 "internal_error"

let s_3 = Base.text_of_utf8 "saturated call"

let s_4 = Base.text_of_utf8 "saturation traversal lost an expression child"

let s_5 = Base.text_of_utf8 "$codegen.saturated["

let s_6 = Base.text_of_utf8 "].arg["

let s_7 = Base.text_of_utf8 "]"

let s_8 = Base.text_of_utf8 "backend_limit"

let s_9 = Base.text_of_utf8 "saturation traversal exceeded its structural limit"

let rec (* codegen_saturation.bend:30 *)
f_empty : unit -> ((t_Definition) option) Base.map =
fun () ->
(Base.map_new ())
and (* codegen_saturation.bend:33 *)
f_definition : int -> Base.text -> M.t_Expr -> (Base.text) list -> (t_Definition) option =
fun v_fuel v_key v_expression v_reversed ->
(match (v_fuel, v_expression) with
| (0, _) ->
None
| (__nat_1, (M.SourceExpr (v_offset, v_annotation, v_body))) when __nat_1 >= 1 ->
(let v_rest = (__nat_1 - 1) in
(f_definition (v_rest) (v_key) (v_body) (v_reversed)))
| (__nat_2, (M.LambdaExpr (v_identity, v_parameter, v_p, v_r, v_body))) when __nat_2 >= 1 ->
(let v_rest = (__nat_2 - 1) in
(f_definition (v_rest) (v_key) (v_body) ((v_parameter :: v_reversed))))
| (_, v_body) ->
(Some ((Definition (v_key, (Base.list_reverse (v_reversed)), v_body)))))
and (* codegen_saturation.bend:44 *)
f_definitions : (M.t_CheckedFunction) list -> ((t_Definition) option) Base.map -> ((t_Definition) option) Base.map =
fun v_functions v_indexed ->
(match v_functions with
| [] ->
v_indexed
| ((M.CheckedFunction ((M.Function (v_name, v_exported, v_parameter, v_p, v_r, v_body)), v_signature, v_effects)) :: v_tail) ->
(f_definitions (v_tail) ((Base.map_set (v_indexed) (v_name) ((f_definition (256) ((Base.string_append s_0 v_name)) (v_body) ([v_parameter])))))))
and (* codegen_saturation.bend:51 *)
f_application : int -> M.t_Expr -> (M.t_Expr) list -> t_Application =
fun v_fuel v_expression v_arguments ->
(match (v_fuel, v_expression) with
| (__nat_3, (M.SourceExpr (v_offset, v_annotation, v_body))) when __nat_3 >= 1 ->
(let v_rest = (__nat_3 - 1) in
(f_application (v_rest) (v_body) (v_arguments)))
| (__nat_4, (M.InstantiationExpr (v_site, v_value))) when __nat_4 >= 1 ->
(let v_rest = (__nat_4 - 1) in
(f_application (v_rest) (v_value) (v_arguments)))
| (__nat_5, (M.ApplyExpr (v_callee, v_argument))) when __nat_5 >= 1 ->
(let v_rest = (__nat_5 - 1) in
(f_application (v_rest) (v_callee) ((v_argument :: v_arguments))))
| (__nat_6, (M.CallExpr (v_name, v_argument))) when __nat_6 >= 1 ->
(let v_rest = (__nat_6 - 1) in
(Application ((M.FunctionExpr (v_name)), (v_argument :: v_arguments))))
| (_, v_head) ->
(Application (v_head, v_arguments)))
and (* codegen_saturation.bend:64 *)
f_resolved : M.t_Expr -> ((t_Definition) option) Base.map -> (t_Definition) option =
fun v_head v_known ->
(match v_head with
| (M.FunctionExpr (v_name)) ->
(Index.f_get (v_known) (v_name) (None))
| (M.LambdaExpr (v_identity, v_parameter, v_p, v_r, v_body)) ->
(f_definition (256) ((Base.string_append s_1 (Base.nat_show (v_identity)))) (v_body) ([v_parameter]))
| _ ->
None)
and (* codegen_saturation.bend:73 *)
f_arity_match : (t_Definition) option -> (M.t_Expr) list -> (t_Candidate) option =
fun v_found v_arguments ->
(match v_found with
| None ->
None
| (Some ((Definition (v_key, v_parameters, v_body)))) ->
(let v_count = (Base.list_length (v_parameters)) in
(Base.bool_pick ((Base.bool_and ((Base.nat_is_ge (v_count) (2))) ((Base.nat_is_eq (v_count) ((Base.list_length (v_arguments))))))) ((Some ((Candidate ((Definition (v_key, v_parameters, v_body)), v_arguments))))) (None))))
and (* codegen_saturation.bend:81 *)
f_candidate : t_Application -> ((t_Definition) option) Base.map -> (t_Candidate) option =
fun v_chain v_known ->
(let (Application (v_head, v_arguments)) = v_chain in
(f_arity_match ((f_resolved (v_head) (v_known))) (v_arguments)))
and (* codegen_saturation.bend:89 *)
f_body_cost : int -> (M.t_Expr) list -> int -> int =
fun v_fuel v_pending v_count ->
(match (v_fuel, v_pending) with
| (_, []) ->
v_count
| (0, _) ->
97
| (__nat_7, ((M.SourceExpr (v_offset, v_annotation, v_body)) :: v_tail)) when __nat_7 >= 1 ->
(let v_rest = (__nat_7 - 1) in
(f_body_cost (v_rest) ((v_body :: v_tail)) (v_count)))
| (__nat_8, ((M.ForeverExpr (v_state, v_initial, v_body)) :: v_tail)) when __nat_8 >= 1 ->
(let v_rest = (__nat_8 - 1) in
97)
| (__nat_9, ((M.ForExpr (v_index, v_start, v_end, v_state, v_initial, v_body)) :: v_tail)) when __nat_9 >= 1 ->
(let v_rest = (__nat_9 - 1) in
97)
| (__nat_10, ((M.LambdaExpr (v_identity, v_parameter, v_p, v_r, v_body)) :: v_tail)) when __nat_10 >= 1 ->
(let v_rest = (__nat_10 - 1) in
(f_body_cost (v_rest) (v_tail) ((Base.nat_add 1 v_count))))
| (__nat_11, (v_head :: v_tail)) when __nat_11 >= 1 ->
(let v_rest = (__nat_11 - 1) in
(f_body_cost (v_rest) ((Base.list_append ((F.f_children (v_head))) (v_tail))) ((Base.nat_add 1 v_count)))))
and (* codegen_saturation.bend:106 *)
f_eligible : t_Candidate -> int -> int -> Base.set -> bool =
fun v_item v_cost v_budget v_active ->
(let (Candidate ((Definition (v_key, v_parameters, v_body)), v_arguments)) = v_item in
(Base.bool_and ((Base.nat_is_le (v_cost) (96))) ((Base.bool_and ((Base.nat_is_le (v_cost) (v_budget))) ((Base.bool_not ((Base.maybe_is_some ((Index.f_find (v_active) (v_key)))))))))))
and (* codegen_saturation.bend:110 *)
f_candidate_cost : t_Candidate -> int =
fun v_item ->
(let (Candidate ((Definition (v_key, v_parameters, v_body)), v_arguments)) = v_item in
(Base.nat_add ((f_body_cost (256) ([v_body]) (0))) ((Base.nat_mul (3) ((Base.list_length (v_parameters)))))))
and (* codegen_saturation.bend:115 *)
f_expressions : t_Edited -> (M.t_Expr) list =
fun v_edited ->
(let (Edited (v_values, v_budget, v_serial)) = v_edited in
v_values)
and (* codegen_saturation.bend:119 *)
f_remaining : t_Edited -> int =
fun v_edited ->
(let (Edited (v_values, v_budget, v_serial)) = v_edited in
v_budget)
and (* codegen_saturation.bend:123 *)
f_next_serial : t_Edited -> int =
fun v_edited ->
(let (Edited (v_values, v_budget, v_serial)) = v_edited in
v_serial)
and (* codegen_saturation.bend:127 *)
f_one : (M.t_Expr) list -> (M.t_Diagnostic, M.t_Expr) Base.result_ =
fun v_values ->
(match v_values with
| (v_value :: []) ->
(Done (v_value))
| _ ->
(Fail ((M.Diagnostic (s_2, s_3, s_4)))))
and (* codegen_saturation.bend:134 *)
f_temporary : int -> int -> Base.text =
fun v_serial v_index ->
(Base.string_append s_5 (Base.string_append (Base.nat_show (v_serial)) (Base.string_append s_6 (Base.string_append (Base.nat_show (v_index)) s_7))))
and (* codegen_saturation.bend:137 *)
f_bind_parameters : (Base.text) list -> int -> int -> M.t_Expr -> M.t_Expr =
fun v_parameters v_serial v_index v_body ->
(match v_parameters with
| [] ->
v_body
| (v_parameter :: v_tail) ->
(M.LetExpr (v_parameter, (M.LocalExpr ((f_temporary (v_serial) (v_index)))), (f_bind_parameters (v_tail) (v_serial) ((Base.nat_add 1 v_index)) (v_body)))))
and (* codegen_saturation.bend:144 *)
f_bind_arguments : (M.t_Expr) list -> int -> int -> M.t_Expr -> M.t_Expr =
fun v_arguments v_serial v_index v_body ->
(match v_arguments with
| [] ->
v_body
| (v_argument :: v_tail) ->
(M.LetExpr ((f_temporary (v_serial) (v_index)), v_argument, (f_bind_arguments (v_tail) (v_serial) ((Base.nat_add 1 v_index)) (v_body)))))
and (* codegen_saturation.bend:154 *)
f_direct_head : int -> M.t_Expr -> M.t_Expr -> M.t_Expr =
fun v_fuel v_head v_argument ->
(match (v_fuel, v_head) with
| (__nat_12, (M.SourceExpr (v_offset, v_annotation, v_body))) when __nat_12 >= 1 ->
(let v_rest = (__nat_12 - 1) in
(f_direct_head (v_rest) (v_body) (v_argument)))
| (_, (M.FunctionExpr (v_name))) ->
(M.CallExpr (v_name, v_argument))
| (_, v_value) ->
(M.ApplyExpr (v_value, v_argument)))
and (* codegen_saturation.bend:163 *)
f_direct : M.t_Expr -> M.t_Expr =
fun v_expression ->
(match v_expression with
| (M.ApplyExpr (v_head, v_argument)) ->
(f_direct_head (256) (v_head) (v_argument))
| v_other ->
v_other)
and (* codegen_saturation.bend:170 *)
f_rewrite : int -> t_Work -> ((t_Definition) option) Base.map -> Base.set -> int -> int -> (M.t_Diagnostic, t_Edited) Base.result_ =
fun v_fuel v_work v_known v_active v_budget v_serial ->
(match (v_fuel, v_work) with
| (0, _) ->
(Fail ((M.Diagnostic (s_8, s_3, s_9))))
| (__nat_13, (Expression ((M.SourceExpr (v_offset, v_annotation, v_value))))) when __nat_13 >= 1 ->
(let v_rest = (__nat_13 - 1) in
(match (f_rewrite (v_rest) ((Expression (v_value))) (v_known) (v_active) (v_budget) (v_serial)) with
| Fail __error -> Fail __error
| Done v_child ->
(match (f_one ((f_expressions (v_child)))) with
| Fail __error -> Fail __error
| Done v_prepared ->
(Done ((Edited ([(M.SourceExpr (v_offset, v_annotation, v_prepared))], (f_remaining (v_child)), (f_next_serial (v_child)))))))))
| (__nat_14, (Expression ((M.LambdaExpr (v_identity, v_parameter, v_p, v_r, v_body))))) when __nat_14 >= 1 ->
(let v_rest = (__nat_14 - 1) in
(Done ((Edited ([(M.LambdaExpr (v_identity, v_parameter, v_p, v_r, v_body))], v_budget, v_serial)))))
| (__nat_15, (Expression (v_expression))) when __nat_15 >= 1 ->
(let v_rest = (__nat_15 - 1) in
(f_rewrite (v_rest) ((Attempt (v_expression, (f_candidate ((f_application (256) (v_expression) ([]))) (v_known))))) (v_known) (v_active) (v_budget) (v_serial)))
| (__nat_16, (Attempt (v_original, (Some (v_item))))) when __nat_16 >= 1 ->
(let v_rest = (__nat_16 - 1) in
(let v_cost = (f_candidate_cost (v_item)) in
(f_rewrite (v_rest) ((Expand (v_original, v_item, v_cost, (f_eligible (v_item) (v_cost) (v_budget) (v_active))))) (v_known) (v_active) (v_budget) (v_serial))))
| (__nat_17, (Expand (v_original, (Candidate ((Definition (v_key, v_parameters, v_body)), v_arguments)), v_cost, true))) when __nat_17 >= 1 ->
(let v_rest = (__nat_17 - 1) in
(match (f_rewrite (v_rest) ((Expressions (v_arguments, []))) (v_known) (v_active) ((Base.nat_sub (v_budget) (v_cost))) (v_serial)) with
| Fail __error -> Fail __error
| Done v_values ->
(let v_call_serial = (f_next_serial (v_values)) in
(match (f_rewrite (v_rest) ((Expression (v_body))) (v_known) ((Base.set_add (v_active) (v_key))) ((f_remaining (v_values))) ((Base.nat_add 1 v_call_serial))) with
| Fail __error -> Fail __error
| Done v_expanded ->
(match (f_one ((f_expressions (v_expanded)))) with
| Fail __error -> Fail __error
| Done v_final ->
(Done ((Edited ([(f_bind_arguments ((f_expressions (v_values))) (v_call_serial) (0) ((f_bind_parameters (v_parameters) (v_call_serial) (0) (v_final))))], (f_remaining (v_expanded)), (f_next_serial (v_expanded)))))))))))
| (__nat_18, (Expand (v_original, v_candidate, v_cost, false))) when __nat_18 >= 1 ->
(let v_rest = (__nat_18 - 1) in
(f_rewrite (v_rest) ((Attempt (v_original, None))) (v_known) (v_active) (v_budget) (v_serial)))
| (__nat_19, (Attempt (v_original, None))) when __nat_19 >= 1 ->
(let v_rest = (__nat_19 - 1) in
(match (f_rewrite (v_rest) ((Expressions ((F.f_children (v_original)), []))) (v_known) (v_active) (v_budget) (v_serial)) with
| Fail __error -> Fail __error
| Done v_children ->
(match (Mono.f_rebuild (v_original) ((f_expressions (v_children))) (0)) with
| Fail __error -> Fail __error
| Done v_rebuilt ->
(Done ((Edited ([(f_direct (v_rebuilt))], (f_remaining (v_children)), (f_next_serial (v_children)))))))))
| (__nat_20, (Expressions ([], v_reversed))) when __nat_20 >= 1 ->
(let v_rest = (__nat_20 - 1) in
(Done ((Edited ((Base.list_reverse (v_reversed)), v_budget, v_serial)))))
| (__nat_21, (Expressions ((v_head :: v_tail), v_reversed))) when __nat_21 >= 1 ->
(let v_rest = (__nat_21 - 1) in
(match (f_rewrite (v_rest) ((Expression (v_head))) (v_known) (v_active) (v_budget) (v_serial)) with
| Fail __error -> Fail __error
| Done v_first ->
(match (f_one ((f_expressions (v_first)))) with
| Fail __error -> Fail __error
| Done v_prepared ->
(f_rewrite (v_rest) ((Expressions (v_tail, (v_prepared :: v_reversed)))) (v_known) (v_active) ((f_remaining (v_first))) ((f_next_serial (v_first))))))))
and (* codegen_saturation.bend:210 *)
f_prepare : M.t_Expr -> ((t_Definition) option) Base.map -> (M.t_Diagnostic, M.t_Expr) Base.result_ =
fun v_expression v_known ->
(match (f_rewrite (65536) ((Expression (v_expression))) (v_known) ((Base.set_new ())) (2048) (0)) with
| Fail __error -> Fail __error
| Done v_result ->
(f_one ((f_expressions (v_result)))))
