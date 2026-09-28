(* Native semantic port of compiler/runtime_reachable.bend.

   Source SHA-256: 97d11fee7c13d4a4acbb6ca51734faf57ad084dcf19dfee664cf410b453c9fed

   Ownership/type arguments are erased; value types are checked by OCaml.

   No Bend interpreter or generated C/JavaScript is linked. *)

open Base

module M = Ox_model

module C = Ox_const_eval

module F = Ox_closures

module I = Ox_codegen_ir

module Index = Ox_index

module Init = Ox_runtime_initialization

type t_Catalog =
  | Catalog of ((M.t_CheckedFunction) option) Base.map * ((C.t_Value) option) Base.map * (Init.t_Initializer) Base.map
and t_State =
  | State of (bool) Base.map * (bool) Base.map * (F.t_Lambda) list * Base.set * Base.set
and t_Work =
  | FunctionWork of Base.text
  | ConstantWork of Base.text
  | ExpressionWork of M.t_Expr
  | ExpressionsWork of (M.t_Expr) list
  | PatternWork of (M.t_Pattern) list
  | PatternArms of ((M.t_Expr) M.t_MatchArm) list
  | ValueWork of C.t_Value
  | ValuesWork of (C.t_Value) list
and t_Step =
  | Step of (t_Work) list * t_State
and t_Runtime =
  | Runtime of M.t_CheckedModule * ((C.t_Value) C.t_Binding) list * (F.t_Lambda) list * Base.set * Base.set

let s_0 = Base.text_of_utf8 "internal_error"

let s_1 = Base.text_of_utf8 "runtime reachability lost a checked function"

let s_2 = Base.text_of_utf8 "fn:"

let s_3 = Base.text_of_utf8 "const:"

let s_4 = Base.text_of_utf8 "runtime reachability lost a checked value"

let s_5 = Base.text_of_utf8 "backend_limit"

let s_6 = Base.text_of_utf8 "reachability"

let s_7 = Base.text_of_utf8 "runtime reachability exceeded its traversal limit"

let s_8 = Base.text_of_utf8 "constant"

let s_9 = Base.text_of_utf8 "runtime reachability received an unhandled return"

let s_10 = Base.text_of_utf8 "runtime reachability received internal pattern bindings"

let s_11 = Base.text_of_utf8 "runtime reachability received a match scrutinee collection"

let rec (* runtime_reachable.bend:31 *)
f_function_index : (M.t_CheckedFunction) list -> ((M.t_CheckedFunction) option) Base.map -> ((M.t_CheckedFunction) option) Base.map =
fun v_functions v_indexed ->
(match v_functions with
| [] ->
v_indexed
| ((M.CheckedFunction ((M.Function (v_name, v_exported, v_parameter, v_parameter_type, v_result_type, v_body)), v_signature, v_effects)) :: v_tail) ->
(f_function_index (v_tail) ((Base.map_set (v_indexed) (v_name) ((Some ((M.CheckedFunction ((M.Function (v_name, v_exported, v_parameter, v_parameter_type, v_result_type, v_body)), v_signature, v_effects)))))))))
and (* runtime_reachable.bend:38 *)
f_constant_index : ((C.t_Value) C.t_Binding) list -> ((C.t_Value) option) Base.map -> ((C.t_Value) option) Base.map =
fun v_constants v_indexed ->
(match v_constants with
| [] ->
v_indexed
| ((C.Binding (v_name, v_value)) :: v_tail) ->
(f_constant_index (v_tail) ((Base.map_set (v_indexed) (v_name) ((Some (v_value)))))))
and (* runtime_reachable.bend:45 *)
f_seen : t_State -> Base.text -> bool =
fun v_state v_name ->
(let (State (v_visited, v_lambda_ids, v_lambdas, v_constructors, v_operations)) = v_state in
(Index.f_get (v_visited) (v_name) (false)))
and (* runtime_reachable.bend:49 *)
f_mark : t_State -> Base.text -> t_State =
fun v_state v_name ->
(let (State (v_visited, v_lambda_ids, v_lambdas, v_constructors, v_operations)) = v_state in
(State ((Base.map_set (v_visited) (v_name) (true)), v_lambda_ids, v_lambdas, v_constructors, v_operations)))
and (* runtime_reachable.bend:53 *)
f_lambda_seen : t_State -> int -> bool =
fun v_state v_identity ->
(let (State (v_visited, v_lambda_ids, v_lambdas, v_constructors, v_operations)) = v_state in
(Index.f_get (v_lambda_ids) ((Base.nat_show (v_identity))) (false)))
and (* runtime_reachable.bend:57 *)
f_add_lambda : t_State -> F.t_Lambda -> t_State =
fun v_state v_lambda ->
(let (State (v_visited, v_lambda_ids, v_lambdas, v_constructors, v_operations)) = v_state in
(let (F.Lambda (v_identity, v_parameter, v_body, v_captures)) = v_lambda in
(State (v_visited, (Base.map_set (v_lambda_ids) ((Base.nat_show (v_identity))) (true)), ((F.Lambda (v_identity, v_parameter, v_body, v_captures)) :: v_lambdas), v_constructors, v_operations))))
and (* runtime_reachable.bend:62 *)
f_use_constructor : t_State -> Base.text -> t_State =
fun v_state v_name ->
(let (State (v_visited, v_lambda_ids, v_lambdas, v_constructors, v_operations)) = v_state in
(State (v_visited, v_lambda_ids, v_lambdas, (Base.set_add (v_constructors) (v_name)), v_operations)))
and (* runtime_reachable.bend:66 *)
f_use_operation : t_State -> M.t_TypeId -> t_State =
fun v_state v_identity ->
(let (State (v_visited, v_lambda_ids, v_lambdas, v_constructors, v_operations)) = v_state in
(State (v_visited, v_lambda_ids, v_lambdas, v_constructors, (Base.set_add (v_operations) ((I.f_operation_key (v_identity)))))))
and (* runtime_reachable.bend:70 *)
f_function_value : t_Catalog -> Base.text -> (M.t_CheckedFunction) option =
fun v_catalog v_name ->
(let (Catalog (v_functions, v_constants, v_initializers)) = v_catalog in
(Index.f_get (v_functions) (v_name) (None)))
and (* runtime_reachable.bend:74 *)
f_constant_value : t_Catalog -> Base.text -> (C.t_Value) option =
fun v_catalog v_name ->
(let (Catalog (v_functions, v_constants, v_initializers)) = v_catalog in
(Index.f_get (v_constants) (v_name) (None)))
and (* runtime_reachable.bend:78 *)
f_visit_function : bool -> (M.t_CheckedFunction) option -> Base.text -> t_State -> (M.t_Diagnostic, t_Step) Base.result_ =
fun v_visited v_found v_name v_state ->
(match (v_visited, v_found) with
| (true, _) ->
(Done ((Step ([], v_state))))
| (false, None) ->
(Fail ((M.Diagnostic (s_0, v_name, s_1))))
| (false, (Some ((M.CheckedFunction ((M.Function (v_found_name, v_exported, v_parameter, v_parameter_type, v_result_type, v_body)), v_signature, v_effects))))) ->
(Done ((Step ([(ExpressionWork (v_body))], (f_mark (v_state) ((Base.string_append s_2 v_name))))))))
and (* runtime_reachable.bend:87 *)
f_visit_constant : bool -> (C.t_Value) option -> (Init.t_Initializer) option -> Base.text -> t_State -> (M.t_Diagnostic, t_Step) Base.result_ =
fun v_visited v_found v_initializer v_name v_state ->
(match (v_visited, v_found, v_initializer) with
| (true, _, _) ->
(Done ((Step ([], v_state))))
| (false, (Some (v_value)), _) ->
(Done ((Step ([(ValueWork (v_value))], (f_mark (v_state) ((Base.string_append s_3 v_name)))))))
| (false, None, (Some ((Init.Initializer (v_declared, v_value))))) ->
(Done ((Step ([(ExpressionWork (v_value))], (f_mark (v_state) ((Base.string_append s_3 v_name)))))))
| (false, None, None) ->
(Fail ((M.Diagnostic (s_0, v_name, s_4)))))
and (* runtime_reachable.bend:98 *)
f_initializer_value : t_Catalog -> Base.text -> (Init.t_Initializer) option =
fun v_catalog v_name ->
(let (Catalog (v_functions, v_constants, v_initializers)) = v_catalog in
(Index.f_find (v_initializers) (v_name)))
and (* runtime_reachable.bend:102 *)
f_captured_values : (Base.text) list -> ((C.t_Value) C.t_Binding) list -> (M.t_Diagnostic, (C.t_Value) list) Base.result_ =
fun v_names v_environment ->
(match v_names with
| [] ->
(Done ([]))
| (v_head :: v_tail) ->
(match (C.f_lookup_local (v_environment) (v_head)) with
| Fail __error -> Fail __error
| Done v_first ->
(match (f_captured_values (v_tail) (v_environment)) with
| Fail __error -> Fail __error
| Done v_remaining ->
(Done ((v_first :: v_remaining))))))
and (* runtime_reachable.bend:112 *)
f_closure_captures : (((C.t_Value) C.t_Binding) list) option -> (Base.text) list -> (M.t_Diagnostic, (C.t_Value) list) Base.result_ =
fun v_environment v_captures ->
(match v_environment with
| None ->
(Done ([]))
| (Some (v_bindings)) ->
(f_captured_values (v_captures) (v_bindings)))
and (* runtime_reachable.bend:119 *)
f_visit_lambda : bool -> int -> Base.text -> M.t_Expr -> (((C.t_Value) C.t_Binding) list) option -> t_State -> (M.t_Diagnostic, t_Step) Base.result_ =
fun v_visited v_identity v_parameter v_body v_environment v_state ->
(match v_visited with
| true ->
(match (F.f_free ((Base.u32_to_nat ((Base.W32 0x1000)))) ((F.ExpressionWork (v_body, [v_parameter])))) with
| Fail __error -> Fail __error
| Done v_captures ->
(match (f_closure_captures (v_environment) (v_captures)) with
| Fail __error -> Fail __error
| Done v_values ->
(Done ((Step ([(ValuesWork (v_values))], v_state))))))
| false ->
(match (F.f_free ((Base.u32_to_nat ((Base.W32 0x1000)))) ((F.ExpressionWork (v_body, [v_parameter])))) with
| Fail __error -> Fail __error
| Done v_captures ->
(match (f_closure_captures (v_environment) (v_captures)) with
| Fail __error -> Fail __error
| Done v_values ->
(Done ((Step ([(ExpressionWork (v_body)); (ValuesWork (v_values))], (f_add_lambda (v_state) ((F.Lambda (v_identity, v_parameter, v_body, v_captures)))))))))))
and (* runtime_reachable.bend:133 *)
f_expanded_step : (M.t_Diagnostic, t_Step) Base.result_ -> (t_Work) list -> (M.t_Diagnostic, t_Step) Base.result_ =
fun v_result v_pending ->
(match v_result with
| (Fail (v_error)) ->
(Fail (v_error))
| (Done ((Step (v_next, v_state)))) ->
(Done ((Step ((Base.list_append (v_next) (v_pending)), v_state)))))
and (* runtime_reachable.bend:143 *)
f_walk_steps : int -> (M.t_Diagnostic, t_Step) Base.result_ -> t_Catalog -> (M.t_Diagnostic, t_State) Base.result_ =
fun v_fuel v_step v_catalog ->
(match (v_fuel, v_step) with
| (_, (Fail (v_error))) ->
(Fail (v_error))
| (_, (Done ((Step ([], v_state))))) ->
(Done (v_state))
| (0, _) ->
(Fail ((M.Diagnostic (s_5, s_6, s_7))))
| (__nat_1, (Done ((Step (((FunctionWork (v_name)) :: v_pending), v_state))))) when __nat_1 >= 1 ->
(let v_rest = (__nat_1 - 1) in
(f_walk_steps (v_rest) ((f_expanded_step ((f_visit_function ((f_seen (v_state) ((Base.string_append s_2 v_name)))) ((f_function_value (v_catalog) (v_name))) (v_name) (v_state))) (v_pending))) (v_catalog)))
| (__nat_2, (Done ((Step (((ConstantWork (v_name)) :: v_pending), v_state))))) when __nat_2 >= 1 ->
(let v_rest = (__nat_2 - 1) in
(f_walk_steps (v_rest) ((f_expanded_step ((f_visit_constant ((f_seen (v_state) ((Base.string_append s_3 v_name)))) ((f_constant_value (v_catalog) (v_name))) ((f_initializer_value (v_catalog) (v_name))) (v_name) (v_state))) (v_pending))) (v_catalog)))
| (__nat_3, (Done ((Step (((ExpressionWork ((M.FunctionExpr (v_name)))) :: v_pending), v_state))))) when __nat_3 >= 1 ->
(let v_rest = (__nat_3 - 1) in
(f_walk_steps (v_rest) ((Done ((Step (((FunctionWork (v_name)) :: v_pending), v_state))))) (v_catalog)))
| (__nat_4, (Done ((Step (((ExpressionWork ((M.CallExpr (v_callee, v_argument)))) :: v_pending), v_state))))) when __nat_4 >= 1 ->
(let v_rest = (__nat_4 - 1) in
(f_walk_steps (v_rest) ((Done ((Step (((FunctionWork (v_callee)) :: ((ExpressionWork (v_argument)) :: v_pending)), v_state))))) (v_catalog)))
| (__nat_5, (Done ((Step (((ExpressionWork ((M.ConstantExpr (v_name)))) :: v_pending), v_state))))) when __nat_5 >= 1 ->
(let v_rest = (__nat_5 - 1) in
(f_walk_steps (v_rest) ((Done ((Step (((ConstantWork (v_name)) :: v_pending), v_state))))) (v_catalog)))
| (__nat_6, (Done ((Step (((ExpressionWork ((M.ConstructorRefExpr (v_name)))) :: v_pending), v_state))))) when __nat_6 >= 1 ->
(let v_rest = (__nat_6 - 1) in
(f_walk_steps (v_rest) ((Done ((Step (v_pending, (f_use_constructor (v_state) (v_name))))))) (v_catalog)))
| (__nat_7, (Done ((Step (((ExpressionWork ((M.OperationExpr (v_identity)))) :: v_pending), v_state))))) when __nat_7 >= 1 ->
(let v_rest = (__nat_7 - 1) in
(f_walk_steps (v_rest) ((Done ((Step (v_pending, (f_use_operation (v_state) (v_identity))))))) (v_catalog)))
| (__nat_8, (Done ((Step (((ExpressionWork ((M.ProviderExpr (v_identity, v_implementation)))) :: v_pending), v_state))))) when __nat_8 >= 1 ->
(let v_rest = (__nat_8 - 1) in
(f_walk_steps (v_rest) ((Done ((Step (((ExpressionWork (v_implementation)) :: v_pending), (f_use_operation (v_state) (v_identity))))))) (v_catalog)))
| (__nat_9, (Done ((Step (((ExpressionWork ((M.StateProviderExpr (v_read, v_write, v_initial)))) :: v_pending), v_state))))) when __nat_9 >= 1 ->
(let v_rest = (__nat_9 - 1) in
(f_walk_steps (v_rest) ((Done ((Step (((ExpressionWork (v_initial)) :: v_pending), (f_use_operation ((f_use_operation (v_state) (v_read))) (v_write))))))) (v_catalog)))
| (__nat_10, (Done ((Step (((ExpressionWork ((M.LambdaExpr (v_identity, v_parameter, v_parameter_type, v_result_type, v_body)))) :: v_pending), v_state))))) when __nat_10 >= 1 ->
(let v_rest = (__nat_10 - 1) in
(f_walk_steps (v_rest) ((f_expanded_step ((f_visit_lambda ((f_lambda_seen (v_state) (v_identity))) (v_identity) (v_parameter) (v_body) (None) (v_state))) (v_pending))) (v_catalog)))
| (__nat_11, (Done ((Step (((ExpressionWork ((M.OperationDescriptorExpr (v_identity)))) :: v_pending), v_state))))) when __nat_11 >= 1 ->
(let v_rest = (__nat_11 - 1) in
(Fail ((I.f_const_only ()))))
| (__nat_12, (Done ((Step (((ExpressionWork ((M.FunctionEffectsExpr (v_callee)))) :: v_pending), v_state))))) when __nat_12 >= 1 ->
(let v_rest = (__nat_12 - 1) in
(Fail ((I.f_const_only ()))))
| (__nat_13, (Done ((Step (((ExpressionWork ((M.EffectHasExpr (v_set, v_operation)))) :: v_pending), v_state))))) when __nat_13 >= 1 ->
(let v_rest = (__nat_13 - 1) in
(Fail ((I.f_const_only ()))))
| (__nat_14, (Done ((Step (((ExpressionWork ((M.EffectCountExpr (v_set)))) :: v_pending), v_state))))) when __nat_14 >= 1 ->
(let v_rest = (__nat_14 - 1) in
(Fail ((I.f_const_only ()))))
| (__nat_15, (Done ((Step (((ExpressionWork ((M.EffectSameExpr (v_left, v_right)))) :: v_pending), v_state))))) when __nat_15 >= 1 ->
(let v_rest = (__nat_15 - 1) in
(Fail ((I.f_const_only ()))))
| (__nat_16, (Done ((Step (((ExpressionWork ((M.MatchExpr (v_values, v_arms)))) :: v_pending), v_state))))) when __nat_16 >= 1 ->
(let v_rest = (__nat_16 - 1) in
(f_walk_steps (v_rest) ((Done ((Step (((PatternArms (v_arms)) :: ((ExpressionsWork ((F.f_children ((M.MatchExpr (v_values, v_arms)))))) :: v_pending)), v_state))))) (v_catalog)))
| (__nat_17, (Done ((Step (((ExpressionWork ((M.GuardExpr (v_pattern, v_value, v_alternative, v_body)))) :: v_pending), v_state))))) when __nat_17 >= 1 ->
(let v_rest = (__nat_17 - 1) in
(f_walk_steps (v_rest) ((Done ((Step (((PatternWork ([v_pattern])) :: ((ExpressionsWork ([v_value; v_alternative; v_body])) :: v_pending)), v_state))))) (v_catalog)))
| (__nat_18, (Done ((Step (((PatternArms ([])) :: v_pending), v_state))))) when __nat_18 >= 1 ->
(let v_rest = (__nat_18 - 1) in
(f_walk_steps (v_rest) ((Done ((Step (v_pending, v_state))))) (v_catalog)))
| (__nat_19, (Done ((Step (((PatternArms (((M.MatchArm (v_patterns, v_body)) :: v_tail))) :: v_pending), v_state))))) when __nat_19 >= 1 ->
(let v_rest = (__nat_19 - 1) in
(f_walk_steps (v_rest) ((Done ((Step (((PatternWork (v_patterns)) :: ((PatternArms (v_tail)) :: v_pending)), v_state))))) (v_catalog)))
| (__nat_20, (Done ((Step (((PatternWork ([])) :: v_pending), v_state))))) when __nat_20 >= 1 ->
(let v_rest = (__nat_20 - 1) in
(f_walk_steps (v_rest) ((Done ((Step (v_pending, v_state))))) (v_catalog)))
| (__nat_21, (Done ((Step (((PatternWork (((M.ValuePattern (v_reference)) :: v_tail))) :: v_pending), v_state))))) when __nat_21 >= 1 ->
(let v_rest = (__nat_21 - 1) in
(f_walk_steps (v_rest) ((Done ((Step (((ExpressionWork ((M.f_reference_expr (v_reference)))) :: ((PatternWork (v_tail)) :: v_pending)), v_state))))) (v_catalog)))
| (__nat_22, (Done ((Step (((PatternWork (((M.ConstructorPattern (v_name, (Some (v_payload)))) :: v_tail))) :: v_pending), v_state))))) when __nat_22 >= 1 ->
(let v_rest = (__nat_22 - 1) in
(f_walk_steps (v_rest) ((Done ((Step (((PatternWork ((v_payload :: v_tail))) :: v_pending), v_state))))) (v_catalog)))
| (__nat_23, (Done ((Step (((PatternWork (((M.ProductPattern (v_elements)) :: v_tail))) :: v_pending), v_state))))) when __nat_23 >= 1 ->
(let v_rest = (__nat_23 - 1) in
(f_walk_steps (v_rest) ((Done ((Step (((PatternWork (v_elements)) :: ((PatternWork (v_tail)) :: v_pending)), v_state))))) (v_catalog)))
| (__nat_24, (Done ((Step (((PatternWork ((v_pattern :: v_tail))) :: v_pending), v_state))))) when __nat_24 >= 1 ->
(let v_rest = (__nat_24 - 1) in
(f_walk_steps (v_rest) ((Done ((Step (((PatternWork (v_tail)) :: v_pending), v_state))))) (v_catalog)))
| (__nat_25, (Done ((Step (((ExpressionWork (v_expression)) :: v_pending), v_state))))) when __nat_25 >= 1 ->
(let v_rest = (__nat_25 - 1) in
(f_walk_steps (v_rest) ((Done ((Step (((ExpressionsWork ((F.f_children (v_expression)))) :: v_pending), v_state))))) (v_catalog)))
| (__nat_26, (Done ((Step (((ExpressionsWork ([])) :: v_pending), v_state))))) when __nat_26 >= 1 ->
(let v_rest = (__nat_26 - 1) in
(f_walk_steps (v_rest) ((Done ((Step (v_pending, v_state))))) (v_catalog)))
| (__nat_27, (Done ((Step (((ExpressionsWork ((v_head :: v_tail))) :: v_pending), v_state))))) when __nat_27 >= 1 ->
(let v_rest = (__nat_27 - 1) in
(f_walk_steps (v_rest) ((Done ((Step (((ExpressionWork (v_head)) :: ((ExpressionsWork (v_tail)) :: v_pending)), v_state))))) (v_catalog)))
| (__nat_28, (Done ((Step (((ValueWork ((C.FunctionValue (v_name)))) :: v_pending), v_state))))) when __nat_28 >= 1 ->
(let v_rest = (__nat_28 - 1) in
(f_walk_steps (v_rest) ((Done ((Step (((FunctionWork (v_name)) :: v_pending), v_state))))) (v_catalog)))
| (__nat_29, (Done ((Step (((ValueWork ((C.ConstructorFunctionValue (v_name)))) :: v_pending), v_state))))) when __nat_29 >= 1 ->
(let v_rest = (__nat_29 - 1) in
(f_walk_steps (v_rest) ((Done ((Step (v_pending, (f_use_constructor (v_state) (v_name))))))) (v_catalog)))
| (__nat_30, (Done ((Step (((ValueWork ((C.OperationValue (v_identity)))) :: v_pending), v_state))))) when __nat_30 >= 1 ->
(let v_rest = (__nat_30 - 1) in
(f_walk_steps (v_rest) ((Done ((Step (v_pending, (f_use_operation (v_state) (v_identity))))))) (v_catalog)))
| (__nat_31, (Done ((Step (((ValueWork ((C.ClosureValue (v_identity, v_parameter, v_body, v_environment)))) :: v_pending), v_state))))) when __nat_31 >= 1 ->
(let v_rest = (__nat_31 - 1) in
(f_walk_steps (v_rest) ((f_expanded_step ((f_visit_lambda ((f_lambda_seen (v_state) (v_identity))) (v_identity) (v_parameter) (v_body) ((Some (v_environment))) (v_state))) (v_pending))) (v_catalog)))
| (__nat_32, (Done ((Step (((ValueWork ((C.DataValue (v_constructor, (Some (v_payload)))))) :: v_pending), v_state))))) when __nat_32 >= 1 ->
(let v_rest = (__nat_32 - 1) in
(f_walk_steps (v_rest) ((Done ((Step (((ValueWork (v_payload)) :: v_pending), v_state))))) (v_catalog)))
| (__nat_33, (Done ((Step (((ValueWork ((C.ProductValue (v_elements)))) :: v_pending), v_state))))) when __nat_33 >= 1 ->
(let v_rest = (__nat_33 - 1) in
(f_walk_steps (v_rest) ((Done ((Step (((ValuesWork (v_elements)) :: v_pending), v_state))))) (v_catalog)))
| (__nat_34, (Done ((Step (((ValueWork ((C.ArrayValue (v_elements)))) :: v_pending), v_state))))) when __nat_34 >= 1 ->
(let v_rest = (__nat_34 - 1) in
(f_walk_steps (v_rest) ((Done ((Step (((ValuesWork (v_elements)) :: v_pending), v_state))))) (v_catalog)))
| (__nat_35, (Done ((Step (((ValueWork ((C.StateProviderValue (v_read, v_write, v_initial)))) :: v_pending), v_state))))) when __nat_35 >= 1 ->
(let v_rest = (__nat_35 - 1) in
(f_walk_steps (v_rest) ((Done ((Step (((ValueWork (v_initial)) :: v_pending), (f_use_operation ((f_use_operation (v_state) (v_read))) (v_write))))))) (v_catalog)))
| (__nat_36, (Done ((Step (((ValueWork ((C.ProviderValue (v_identity, v_implementation)))) :: v_pending), v_state))))) when __nat_36 >= 1 ->
(let v_rest = (__nat_36 - 1) in
(f_walk_steps (v_rest) ((Done ((Step (((ValueWork (v_implementation)) :: v_pending), (f_use_operation (v_state) (v_identity))))))) (v_catalog)))
| (__nat_37, (Done ((Step (((ValueWork ((C.EffectDescriptorValue (v_identity)))) :: v_pending), v_state))))) when __nat_37 >= 1 ->
(let v_rest = (__nat_37 - 1) in
(Fail ((I.f_const_only ()))))
| (__nat_38, (Done ((Step (((ValueWork ((C.EffectSetValue (v_operations)))) :: v_pending), v_state))))) when __nat_38 >= 1 ->
(let v_rest = (__nat_38 - 1) in
(Fail ((I.f_const_only ()))))
| (__nat_39, (Done ((Step (((ValueWork ((C.ReturnValue (v_label, v_value)))) :: v_pending), v_state))))) when __nat_39 >= 1 ->
(let v_rest = (__nat_39 - 1) in
(Fail ((M.Diagnostic (s_0, s_8, s_9)))))
| (__nat_40, (Done ((Step (((ValueWork ((C.PatternBindingsValue (v_bindings)))) :: v_pending), v_state))))) when __nat_40 >= 1 ->
(let v_rest = (__nat_40 - 1) in
(Fail ((M.Diagnostic (s_0, s_8, s_10)))))
| (__nat_41, (Done ((Step (((ValueWork ((C.MatchValuesValue (v_values)))) :: v_pending), v_state))))) when __nat_41 >= 1 ->
(let v_rest = (__nat_41 - 1) in
(Fail ((M.Diagnostic (s_0, s_8, s_11)))))
| (__nat_42, (Done ((Step (((ValueWork (v_value)) :: v_pending), v_state))))) when __nat_42 >= 1 ->
(let v_rest = (__nat_42 - 1) in
(f_walk_steps (v_rest) ((Done ((Step (v_pending, v_state))))) (v_catalog)))
| (__nat_43, (Done ((Step (((ValuesWork ([])) :: v_pending), v_state))))) when __nat_43 >= 1 ->
(let v_rest = (__nat_43 - 1) in
(f_walk_steps (v_rest) ((Done ((Step (v_pending, v_state))))) (v_catalog)))
| (__nat_44, (Done ((Step (((ValuesWork ((v_head :: v_tail))) :: v_pending), v_state))))) when __nat_44 >= 1 ->
(let v_rest = (__nat_44 - 1) in
(f_walk_steps (v_rest) ((Done ((Step (((ValueWork (v_head)) :: ((ValuesWork (v_tail)) :: v_pending)), v_state))))) (v_catalog))))
and (* runtime_reachable.bend:240 *)
f_walk : int -> (t_Work) list -> t_Catalog -> t_State -> (M.t_Diagnostic, t_State) Base.result_ =
fun v_fuel v_pending v_catalog v_state ->
(f_walk_steps (v_fuel) ((Done ((Step (v_pending, v_state))))) (v_catalog))
and (* runtime_reachable.bend:243 *)
f_function_roots : (M.t_CheckedFunction) list -> (t_Work) list =
fun v_functions ->
(match v_functions with
| [] ->
[]
| ((M.CheckedFunction ((M.Function (v_name, true, v_parameter, v_parameter_type, v_result_type, v_body)), v_signature, v_effects)) :: v_tail) ->
((FunctionWork (v_name)) :: (f_function_roots (v_tail)))
| (v_head :: v_tail) ->
(f_function_roots (v_tail)))
and (* runtime_reachable.bend:252 *)
f_constant_roots : (M.t_CheckedConstant) list -> (t_Work) list =
fun v_constants ->
(match v_constants with
| [] ->
[]
| ((M.CheckedConstant ((M.Constant (v_name, v_exported, v_annotation, (M.RuntimeInitExpr (v_value)))), v_ty, v_variables)) :: v_tail) ->
((ConstantWork (v_name)) :: (f_constant_roots (v_tail)))
| ((M.CheckedConstant ((M.Constant (v_name, true, v_annotation, v_value)), v_ty, v_variables)) :: v_tail) ->
((ConstantWork (v_name)) :: (f_constant_roots (v_tail)))
| (v_head :: v_tail) ->
(f_constant_roots (v_tail)))
and (* runtime_reachable.bend:263 *)
f_keep_functions : (M.t_CheckedFunction) list -> t_State -> (M.t_CheckedFunction) list =
fun v_functions v_state ->
(match v_functions with
| [] ->
[]
| ((M.CheckedFunction ((M.Function (v_name, v_exported, v_parameter, v_parameter_type, v_result_type, v_body)), v_signature, v_effects)) :: v_tail) ->
(let v_remaining = (f_keep_functions (v_tail) (v_state)) in
(Base.bool_pick ((f_seen (v_state) ((Base.string_append s_2 v_name)))) (((M.CheckedFunction ((M.Function (v_name, v_exported, v_parameter, v_parameter_type, v_result_type, v_body)), v_signature, v_effects)) :: v_remaining)) (v_remaining))))
and (* runtime_reachable.bend:271 *)
f_keep_constants : (M.t_CheckedConstant) list -> t_State -> (M.t_CheckedConstant) list =
fun v_constants v_state ->
(match v_constants with
| [] ->
[]
| ((M.CheckedConstant ((M.Constant (v_name, v_exported, v_annotation, v_value)), v_ty, v_variables)) :: v_tail) ->
(let v_remaining = (f_keep_constants (v_tail) (v_state)) in
(Base.bool_pick ((f_seen (v_state) ((Base.string_append s_3 v_name)))) (((M.CheckedConstant ((M.Constant (v_name, v_exported, v_annotation, v_value)), v_ty, v_variables)) :: v_remaining)) (v_remaining))))
and (* runtime_reachable.bend:279 *)
f_keep_bindings : ((C.t_Value) C.t_Binding) list -> t_State -> ((C.t_Value) C.t_Binding) list =
fun v_constants v_state ->
(match v_constants with
| [] ->
[]
| ((C.Binding (v_name, v_value)) :: v_tail) ->
(let v_remaining = (f_keep_bindings (v_tail) (v_state)) in
(Base.bool_pick ((f_seen (v_state) ((Base.string_append s_3 v_name)))) (((C.Binding (v_name, v_value)) :: v_remaining)) (v_remaining))))
and (* runtime_reachable.bend:287 *)
f_reached_lambdas : t_State -> (F.t_Lambda) list =
fun v_state ->
(let (State (v_visited, v_lambda_ids, v_lambdas, v_constructors, v_operations)) = v_state in
(Base.list_reverse (v_lambdas)))
and (* runtime_reachable.bend:291 *)
f_used_constructors : t_State -> Base.set =
fun v_state ->
(let (State (v_visited, v_lambda_ids, v_lambdas, v_constructors, v_operations)) = v_state in
v_constructors)
and (* runtime_reachable.bend:295 *)
f_used_operations : t_State -> Base.set =
fun v_state ->
(let (State (v_visited, v_lambda_ids, v_lambdas, v_constructors, v_operations)) = v_state in
v_operations)
and (* runtime_reachable.bend:299 *)
f_prepare : M.t_CheckedModule -> ((C.t_Value) C.t_Binding) list -> (M.t_Diagnostic, t_Runtime) Base.result_ =
fun v_checked v_bindings ->
(let (M.CheckedModule (v_constants, v_functions, v_types, v_operations)) = v_checked in
(let v_catalog = (Catalog ((f_function_index (v_functions) ((Base.map_new ()))), (f_constant_index (v_bindings) ((Base.map_new ()))), (Init.f_index ((Init.f_bindings (v_constants))) (MTip)))) in
(match (f_walk ((Base.u32_to_nat ((Base.W32 0x100000)))) ((Base.list_append ((f_function_roots (v_functions))) ((f_constant_roots (v_constants))))) (v_catalog) ((State ((Base.map_new ()), (Base.map_new ()), [], (Base.set_new ()), (Base.set_new ()))))) with
| Fail __error -> Fail __error
| Done v_state ->
(Done ((Runtime ((M.CheckedModule ((f_keep_constants (v_constants) (v_state)), (f_keep_functions (v_functions) (v_state)), v_types, v_operations)), (f_keep_bindings (v_bindings) (v_state)), (f_reached_lambdas (v_state)), (f_used_constructors (v_state)), (f_used_operations (v_state)))))))))
