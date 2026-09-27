(* Native semantic port of compiler/dependency.bend.

   Source SHA-256: 5be5fa6d976e8ed9c54f6c12ccb299a9d0f76b1addaac74497ad7a25cf06f34a

   Ownership/type arguments are erased; value types are checked by OCaml.

   No Bend interpreter or generated C/JavaScript is linked. *)

open Base

module M = Ox_model

module Index = Ox_index

module NatIndex = Ox_nat_index

type t_Node =
  | Node of Base.text * (Base.text) list * (int) list
and t_Work =
  | Expression of M.t_Expr
  | Arms of ((M.t_Expr) M.t_MatchArm) list
  | Expressions of (M.t_Expr) list
  | Patterns of (M.t_Pattern) list
and t_References =
  | References of (Base.text) list * (int) list
and t_PendingReference =
  | PendingReference of int * t_Work
and t_ReferenceStep =
  | ReferenceStep of (t_PendingReference) list * t_References
and t_Visit =
  | Enter of Base.text
  | Leave of Base.text
and t_Reachability =
  | Reachability of Base.set * (Base.text) list
and t_CompactCatalog =
  | CompactCatalog of (int) Base.map * (Base.text) NatIndex.t_Index
and t_CompactGraph =
  | CompactGraph of (int) list * ((int) list) NatIndex.t_Index * ((int) list) NatIndex.t_Index * int
and t_CompactVisit =
  | CompactEnter of int
  | CompactLeave of int
and t_CompactReachability =
  | CompactReachability of (unit) NatIndex.t_Index * (int) list

let s_0 = Base.text_of_utf8 "expression_complexity"

let s_1 = Base.text_of_utf8 "inference"

let s_2 = Base.text_of_utf8 "expression nesting exceeds compiler traversal limit"

let s_3 = Base.text_of_utf8 "expression traversal exceeds compiler work limit"

let s_4 = Base.text_of_utf8 "internal_error"

let s_5 = Base.text_of_utf8 "dependency DFS exceeded its node/edge bound"

let s_6 = Base.text_of_utf8 "dependency component exceeded its node/edge bound"

let s_7 = Base.text_of_utf8 ""

let rec (* dependency.bend:18 *)
f_names_of : t_References -> (Base.text) list =
fun v_refs ->
(let (References (v_names, v_lambdas)) = v_refs in
v_names)
and (* dependency.bend:22 *)
f_lambdas_of : t_References -> (int) list =
fun v_refs ->
(let (References (v_names, v_lambdas)) = v_refs in
v_lambdas)
and (* dependency.bend:26 *)
f_reference_name : Base.text -> t_References -> t_References =
fun v_name v_reversed ->
(let (References (v_names, v_lambdas)) = v_reversed in
(References ((v_name :: v_names), v_lambdas)))
and (* dependency.bend:30 *)
f_reference_lambda : int -> t_References -> t_References =
fun v_identity v_reversed ->
(let (References (v_names, v_lambdas)) = v_reversed in
(References (v_names, (v_identity :: v_lambdas))))
and (* dependency.bend:34 *)
f_reference_order : t_References -> t_References =
fun v_reversed ->
(let (References (v_names, v_lambdas)) = v_reversed in
(References ((Base.list_reverse (v_names)), (Base.list_reverse (v_lambdas)))))
and (* dependency.bend:38 *)
f_payload_expression : (M.t_Expr) option -> M.t_Expr =
fun v_payload ->
(match v_payload with
| None ->
M.UnitExpr
| (Some (v_value)) ->
v_value)
and (* dependency.bend:53 *)
f_reference_step : int -> t_Work -> (t_PendingReference) list -> t_References -> (M.t_Diagnostic, t_ReferenceStep) Base.result_ =
fun v_fuel v_work v_pending v_reversed ->
(match (v_fuel, v_work) with
| (0, _) ->
(Fail ((M.Diagnostic (s_0, s_1, s_2))))
| (__nat_1, (Expression ((M.ConstantExpr (v_name))))) when __nat_1 >= 1 ->
(let v_rest = (__nat_1 - 1) in
(Done ((ReferenceStep (v_pending, (f_reference_name (v_name) (v_reversed)))))))
| (__nat_2, (Expression ((M.FunctionExpr (v_name))))) when __nat_2 >= 1 ->
(let v_rest = (__nat_2 - 1) in
(Done ((ReferenceStep (v_pending, (f_reference_name (v_name) (v_reversed)))))))
| (__nat_3, (Expression ((M.FunctionEffectsExpr (v_callee))))) when __nat_3 >= 1 ->
(let v_rest = (__nat_3 - 1) in
(Done ((ReferenceStep (v_pending, (f_reference_name (v_callee) (v_reversed)))))))
| (__nat_4, (Expression ((M.CallExpr (v_callee, v_argument))))) when __nat_4 >= 1 ->
(let v_rest = (__nat_4 - 1) in
(Done ((ReferenceStep (((PendingReference (v_rest, (Expression (v_argument)))) :: v_pending), (f_reference_name (v_callee) (v_reversed)))))))
| (__nat_5, (Expression ((M.LambdaExpr (v_identity, v_parameter, v_p, v_r, v_body))))) when __nat_5 >= 1 ->
(let v_rest = (__nat_5 - 1) in
(Done ((ReferenceStep (((PendingReference (v_rest, (Expression (v_body)))) :: v_pending), (f_reference_lambda (v_identity) (v_reversed)))))))
| (__nat_6, (Expression ((M.ApplyExpr (v_callee, v_argument))))) when __nat_6 >= 1 ->
(let v_rest = (__nat_6 - 1) in
(Done ((ReferenceStep (((PendingReference (v_rest, (Expression (v_callee)))) :: ((PendingReference (v_rest, (Expression (v_argument)))) :: v_pending)), v_reversed)))))
| (__nat_7, (Expression ((M.TagExpr (v_offset, v_callee, v_argument))))) when __nat_7 >= 1 ->
(let v_rest = (__nat_7 - 1) in
(Done ((ReferenceStep (((PendingReference (v_rest, (Expression (v_callee)))) :: ((PendingReference (v_rest, (Expression (v_argument)))) :: v_pending)), v_reversed)))))
| (__nat_8, (Expression ((M.AssociatedExpr (v_identity, v_dispatch, v_member, v_templates, v_left, v_right))))) when __nat_8 >= 1 ->
(let v_rest = (__nat_8 - 1) in
(Done ((ReferenceStep (((PendingReference (v_rest, (Expression (v_left)))) :: ((PendingReference (v_rest, (Expression (v_right)))) :: v_pending)), v_reversed)))))
| (__nat_9, (Expression ((M.ScalarExpr (v_operator, v_left, v_right))))) when __nat_9 >= 1 ->
(let v_rest = (__nat_9 - 1) in
(Done ((ReferenceStep (((PendingReference (v_rest, (Expression (v_left)))) :: ((PendingReference (v_rest, (Expression (v_right)))) :: v_pending)), v_reversed)))))
| (__nat_10, (Expression ((M.UnaryExpr (v_operator, v_value))))) when __nat_10 >= 1 ->
(let v_rest = (__nat_10 - 1) in
(Done ((ReferenceStep (((PendingReference (v_rest, (Expression (v_value)))) :: v_pending), v_reversed)))))
| (__nat_11, (Expression ((M.LetExpr (v_name, v_value, v_body))))) when __nat_11 >= 1 ->
(let v_rest = (__nat_11 - 1) in
(Done ((ReferenceStep (((PendingReference (v_rest, (Expression (v_value)))) :: ((PendingReference (v_rest, (Expression (v_body)))) :: v_pending)), v_reversed)))))
| (__nat_12, (Expression ((M.UseExpr (v_name, v_value, v_body))))) when __nat_12 >= 1 ->
(let v_rest = (__nat_12 - 1) in
(Done ((ReferenceStep (((PendingReference (v_rest, (Expression (v_value)))) :: ((PendingReference (v_rest, (Expression (v_body)))) :: v_pending)), v_reversed)))))
| (__nat_13, (Expression ((M.IfExpr (v_condition, v_consequent, v_alternative))))) when __nat_13 >= 1 ->
(let v_rest = (__nat_13 - 1) in
(Done ((ReferenceStep (((PendingReference (v_rest, (Expression (v_condition)))) :: ((PendingReference (v_rest, (Expression (v_consequent)))) :: ((PendingReference (v_rest, (Expression (v_alternative)))) :: v_pending))), v_reversed)))))
| (__nat_14, (Expression ((M.SequenceExpr (v_first, v_next))))) when __nat_14 >= 1 ->
(let v_rest = (__nat_14 - 1) in
(Done ((ReferenceStep (((PendingReference (v_rest, (Expression (v_first)))) :: ((PendingReference (v_rest, (Expression (v_next)))) :: v_pending)), v_reversed)))))
| (__nat_15, (Expression ((M.MatchExpr (v_values, v_arms))))) when __nat_15 >= 1 ->
(let v_rest = (__nat_15 - 1) in
(Done ((ReferenceStep (((PendingReference (v_rest, (Expressions (v_values)))) :: ((PendingReference (v_rest, (Arms (v_arms)))) :: v_pending)), v_reversed)))))
| (__nat_16, (Expression ((M.GuardExpr (v_pattern, v_value, v_alternative, v_body))))) when __nat_16 >= 1 ->
(let v_rest = (__nat_16 - 1) in
(Done ((ReferenceStep (((PendingReference (v_rest, (Patterns ([v_pattern])))) :: ((PendingReference (v_rest, (Expression (v_value)))) :: ((PendingReference (v_rest, (Expression (v_alternative)))) :: ((PendingReference (v_rest, (Expression (v_body)))) :: v_pending)))), v_reversed)))))
| (__nat_17, (Expression ((M.ConstructExpr (v_constructor, v_payload))))) when __nat_17 >= 1 ->
(let v_rest = (__nat_17 - 1) in
(Done ((ReferenceStep (((PendingReference (v_rest, (Expression ((f_payload_expression (v_payload)))))) :: v_pending), v_reversed)))))
| (__nat_18, (Expression ((M.ProductExpr (v_elements))))) when __nat_18 >= 1 ->
(let v_rest = (__nat_18 - 1) in
(Done ((ReferenceStep (((PendingReference (v_rest, (Expressions (v_elements)))) :: v_pending), v_reversed)))))
| (__nat_19, (Expression ((M.ProjectExpr (v_value, v_index))))) when __nat_19 >= 1 ->
(let v_rest = (__nat_19 - 1) in
(Done ((ReferenceStep (((PendingReference (v_rest, (Expression (v_value)))) :: v_pending), v_reversed)))))
| (__nat_20, (Expression ((M.ArrayExpr (v_elements))))) when __nat_20 >= 1 ->
(let v_rest = (__nat_20 - 1) in
(Done ((ReferenceStep (((PendingReference (v_rest, (Expressions (v_elements)))) :: v_pending), v_reversed)))))
| (__nat_21, (Expression ((M.ForExpr (v_index, v_start, v_end, v_state, v_initial, v_body))))) when __nat_21 >= 1 ->
(let v_rest = (__nat_21 - 1) in
(Done ((ReferenceStep (((PendingReference (v_rest, (Expressions ([v_start; v_end; v_initial; v_body])))) :: v_pending), v_reversed)))))
| (__nat_22, (Expression ((M.ForeverExpr (v_state, v_initial, v_body))))) when __nat_22 >= 1 ->
(let v_rest = (__nat_22 - 1) in
(Done ((ReferenceStep (((PendingReference (v_rest, (Expressions ([v_initial; v_body])))) :: v_pending), v_reversed)))))
| (__nat_23, (Expression ((M.ArrayGenerateExpr (v_count, v_generator))))) when __nat_23 >= 1 ->
(let v_rest = (__nat_23 - 1) in
(Done ((ReferenceStep (((PendingReference (v_rest, (Expressions ([v_count; v_generator])))) :: v_pending), v_reversed)))))
| (__nat_24, (Expression ((M.ArrayFillExpr (v_count, v_value))))) when __nat_24 >= 1 ->
(let v_rest = (__nat_24 - 1) in
(Done ((ReferenceStep (((PendingReference (v_rest, (Expressions ([v_count; v_value])))) :: v_pending), v_reversed)))))
| (__nat_25, (Expression ((M.ArrayGetExpr (v_array, v_index))))) when __nat_25 >= 1 ->
(let v_rest = (__nat_25 - 1) in
(Done ((ReferenceStep (((PendingReference (v_rest, (Expressions ([v_array; v_index])))) :: v_pending), v_reversed)))))
| (__nat_26, (Expression ((M.ArraySetExpr (v_array, v_index, v_value))))) when __nat_26 >= 1 ->
(let v_rest = (__nat_26 - 1) in
(Done ((ReferenceStep (((PendingReference (v_rest, (Expressions ([v_array; v_index; v_value])))) :: v_pending), v_reversed)))))
| (__nat_27, (Expression ((M.ArrayLengthExpr (v_array))))) when __nat_27 >= 1 ->
(let v_rest = (__nat_27 - 1) in
(Done ((ReferenceStep (((PendingReference (v_rest, (Expression (v_array)))) :: v_pending), v_reversed)))))
| (__nat_28, (Expression ((M.BlockExpr (v_label, v_body))))) when __nat_28 >= 1 ->
(let v_rest = (__nat_28 - 1) in
(Done ((ReferenceStep (((PendingReference (v_rest, (Expression (v_body)))) :: v_pending), v_reversed)))))
| (__nat_29, (Expression ((M.ReturnExpr (v_label, v_value))))) when __nat_29 >= 1 ->
(let v_rest = (__nat_29 - 1) in
(Done ((ReferenceStep (((PendingReference (v_rest, (Expression (v_value)))) :: v_pending), v_reversed)))))
| (__nat_30, (Expression ((M.RuntimeInitExpr (v_value))))) when __nat_30 >= 1 ->
(let v_rest = (__nat_30 - 1) in
(Done ((ReferenceStep (((PendingReference (v_rest, (Expression (v_value)))) :: v_pending), v_reversed)))))
| (__nat_31, (Expression ((M.SourceExpr (v_offset, v_annotation, v_value))))) when __nat_31 >= 1 ->
(let v_rest = (__nat_31 - 1) in
(Done ((ReferenceStep (((PendingReference (v_rest, (Expression (v_value)))) :: v_pending), v_reversed)))))
| (__nat_32, (Expression ((M.QualifiedExpr (v_offset, v_annotation, v_predicates, v_value))))) when __nat_32 >= 1 ->
(let v_rest = (__nat_32 - 1) in
(Done ((ReferenceStep (((PendingReference (v_rest, (Expression (v_value)))) :: v_pending), v_reversed)))))
| (__nat_33, (Expression ((M.InstantiationExpr (v_site, v_value))))) when __nat_33 >= 1 ->
(let v_rest = (__nat_33 - 1) in
(Done ((ReferenceStep (((PendingReference (v_rest, (Expression (v_value)))) :: v_pending), v_reversed)))))
| (__nat_34, (Expression ((M.StateProviderExpr (v_read, v_write, v_initial))))) when __nat_34 >= 1 ->
(let v_rest = (__nat_34 - 1) in
(Done ((ReferenceStep (((PendingReference (v_rest, (Expression (v_initial)))) :: v_pending), v_reversed)))))
| (__nat_35, (Expression ((M.ProviderExpr (v_identity, v_implementation))))) when __nat_35 >= 1 ->
(let v_rest = (__nat_35 - 1) in
(Done ((ReferenceStep (((PendingReference (v_rest, (Expression (v_implementation)))) :: v_pending), v_reversed)))))
| (__nat_36, (Expression ((M.HandleExpr (v_provider, v_body))))) when __nat_36 >= 1 ->
(let v_rest = (__nat_36 - 1) in
(Done ((ReferenceStep (((PendingReference (v_rest, (Expression (v_provider)))) :: ((PendingReference (v_rest, (Expression (v_body)))) :: v_pending)), v_reversed)))))
| (__nat_37, (Expression ((M.EffectHasExpr (v_set, v_operation))))) when __nat_37 >= 1 ->
(let v_rest = (__nat_37 - 1) in
(Done ((ReferenceStep (((PendingReference (v_rest, (Expression (v_set)))) :: ((PendingReference (v_rest, (Expression (v_operation)))) :: v_pending)), v_reversed)))))
| (__nat_38, (Expression ((M.EffectCountExpr (v_set))))) when __nat_38 >= 1 ->
(let v_rest = (__nat_38 - 1) in
(Done ((ReferenceStep (((PendingReference (v_rest, (Expression (v_set)))) :: v_pending), v_reversed)))))
| (__nat_39, (Expression ((M.EffectSameExpr (v_left, v_right))))) when __nat_39 >= 1 ->
(let v_rest = (__nat_39 - 1) in
(Done ((ReferenceStep (((PendingReference (v_rest, (Expression (v_left)))) :: ((PendingReference (v_rest, (Expression (v_right)))) :: v_pending)), v_reversed)))))
| (__nat_40, (Expression (M.UnitExpr))) when __nat_40 >= 1 ->
(let v_rest = (__nat_40 - 1) in
(Done ((ReferenceStep (v_pending, v_reversed)))))
| (__nat_41, (Expression ((M.U32Expr (v_value))))) when __nat_41 >= 1 ->
(let v_rest = (__nat_41 - 1) in
(Done ((ReferenceStep (v_pending, v_reversed)))))
| (__nat_42, (Expression ((M.F32Expr (v_value))))) when __nat_42 >= 1 ->
(let v_rest = (__nat_42 - 1) in
(Done ((ReferenceStep (v_pending, v_reversed)))))
| (__nat_43, (Expression ((M.BoolExpr (v_value))))) when __nat_43 >= 1 ->
(let v_rest = (__nat_43 - 1) in
(Done ((ReferenceStep (v_pending, v_reversed)))))
| (__nat_44, (Expression ((M.LocalExpr (v_name))))) when __nat_44 >= 1 ->
(let v_rest = (__nat_44 - 1) in
(Done ((ReferenceStep (v_pending, v_reversed)))))
| (__nat_45, (Expression ((M.ConstructorRefExpr (v_name))))) when __nat_45 >= 1 ->
(let v_rest = (__nat_45 - 1) in
(Done ((ReferenceStep (v_pending, v_reversed)))))
| (__nat_46, (Expression ((M.GenericOperationExpr (v_identity, v_template, v_arguments))))) when __nat_46 >= 1 ->
(let v_rest = (__nat_46 - 1) in
(Done ((ReferenceStep (v_pending, v_reversed)))))
| (__nat_47, (Expression ((M.OperationExpr (v_identity))))) when __nat_47 >= 1 ->
(let v_rest = (__nat_47 - 1) in
(Done ((ReferenceStep (v_pending, v_reversed)))))
| (__nat_48, (Expression ((M.SpecializeOperationExpr (v_template, v_arguments, v_body))))) when __nat_48 >= 1 ->
(let v_rest = (__nat_48 - 1) in
(Done ((ReferenceStep (((PendingReference (v_rest, (Expression (v_body)))) :: v_pending), v_reversed)))))
| (__nat_49, (Expression ((M.OperationDescriptorExpr (v_identity))))) when __nat_49 >= 1 ->
(let v_rest = (__nat_49 - 1) in
(Done ((ReferenceStep (v_pending, v_reversed)))))
| (__nat_50, (Expression ((M.PanicExpr (v_message))))) when __nat_50 >= 1 ->
(let v_rest = (__nat_50 - 1) in
(Done ((ReferenceStep (v_pending, v_reversed)))))
| (__nat_51, (Arms ([]))) when __nat_51 >= 1 ->
(let v_rest = (__nat_51 - 1) in
(Done ((ReferenceStep (v_pending, v_reversed)))))
| (__nat_52, (Arms (((M.MatchArm (v_patterns, v_body)) :: v_tail)))) when __nat_52 >= 1 ->
(let v_rest = (__nat_52 - 1) in
(Done ((ReferenceStep (((PendingReference (v_rest, (Patterns (v_patterns)))) :: ((PendingReference (v_rest, (Expression (v_body)))) :: ((PendingReference (v_rest, (Arms (v_tail)))) :: v_pending))), v_reversed)))))
| (__nat_53, (Patterns ([]))) when __nat_53 >= 1 ->
(let v_rest = (__nat_53 - 1) in
(Done ((ReferenceStep (v_pending, v_reversed)))))
| (__nat_54, (Patterns (((M.ValuePattern (v_reference)) :: v_tail)))) when __nat_54 >= 1 ->
(let v_rest = (__nat_54 - 1) in
(Done ((ReferenceStep (((PendingReference (v_rest, (Expression ((M.f_reference_expr (v_reference)))))) :: ((PendingReference (v_rest, (Patterns (v_tail)))) :: v_pending)), v_reversed)))))
| (__nat_55, (Patterns (((M.ConstructorPattern (v_name, (Some (v_payload)))) :: v_tail)))) when __nat_55 >= 1 ->
(let v_rest = (__nat_55 - 1) in
(Done ((ReferenceStep (((PendingReference (v_rest, (Patterns ((v_payload :: v_tail))))) :: v_pending), v_reversed)))))
| (__nat_56, (Patterns (((M.ProductPattern (v_elements)) :: v_tail)))) when __nat_56 >= 1 ->
(let v_rest = (__nat_56 - 1) in
(Done ((ReferenceStep (((PendingReference (v_rest, (Patterns (v_elements)))) :: ((PendingReference (v_rest, (Patterns (v_tail)))) :: v_pending)), v_reversed)))))
| (__nat_57, (Patterns ((v_pattern :: v_tail)))) when __nat_57 >= 1 ->
(let v_rest = (__nat_57 - 1) in
(Done ((ReferenceStep (((PendingReference (v_rest, (Patterns (v_tail)))) :: v_pending), v_reversed)))))
| (__nat_58, (Expressions ([]))) when __nat_58 >= 1 ->
(let v_rest = (__nat_58 - 1) in
(Done ((ReferenceStep (v_pending, v_reversed)))))
| (__nat_59, (Expressions ((v_head :: v_tail)))) when __nat_59 >= 1 ->
(let v_rest = (__nat_59 - 1) in
(Done ((ReferenceStep (((PendingReference (v_rest, (Expression (v_head)))) :: ((PendingReference (v_rest, (Expressions (v_tail)))) :: v_pending)), v_reversed))))))
and (* dependency.bend:176 *)
f_references_walk : int -> (M.t_Diagnostic, t_ReferenceStep) Base.result_ -> (M.t_Diagnostic, t_References) Base.result_ =
fun v_fuel v_step ->
(match (v_fuel, v_step) with
| (_, (Fail (v_error))) ->
(Fail (v_error))
| (_, (Done ((ReferenceStep ([], v_reversed))))) ->
(Done (v_reversed))
| (0, _) ->
(Fail ((M.Diagnostic (s_0, s_1, s_3))))
| (__nat_60, (Done ((ReferenceStep (((PendingReference (v_depth, v_work)) :: v_tail), v_reversed))))) when __nat_60 >= 1 ->
(let v_rest = (__nat_60 - 1) in
(f_references_walk (v_rest) ((f_reference_step (v_depth) (v_work) (v_tail) (v_reversed))))))
and (* dependency.bend:187 *)
f_references_go : int -> t_Work -> t_References -> (M.t_Diagnostic, t_References) Base.result_ =
fun v_fuel v_work v_reversed ->
(f_references_walk ((M.f_max_nat ())) ((Done ((ReferenceStep ([(PendingReference (v_fuel, v_work))], v_reversed))))))
and (* dependency.bend:190 *)
f_references : int -> t_Work -> (M.t_Diagnostic, t_References) Base.result_ =
fun v_fuel v_work ->
(match (f_references_go (v_fuel) (v_work) ((References ([], [])))) with
| Fail __error -> Fail __error
| Done v_reversed ->
(Done ((f_reference_order (v_reversed)))))
and (* dependency.bend:195 *)
f_function_nodes : (M.t_Function) list -> (M.t_Diagnostic, (t_Node) list) Base.result_ =
fun v_functions ->
(match v_functions with
| [] ->
(Done ([]))
| ((M.Function (v_name, v_exported, v_parameter, v_p, v_r, v_body)) :: v_tail) ->
(match (f_references ((Base.nat_mul (256) (256))) ((Expression (v_body)))) with
| Fail __error -> Fail __error
| Done v_refs ->
(match (f_function_nodes (v_tail)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done (((Node (v_name, (f_names_of (v_refs)), (f_lambdas_of (v_refs)))) :: v_rest))))))
and (* dependency.bend:205 *)
f_constant_nodes : (M.t_Constant) list -> (M.t_Diagnostic, (t_Node) list) Base.result_ =
fun v_constants ->
(match v_constants with
| [] ->
(Done ([]))
| ((M.Constant (v_name, v_exported, v_annotation, v_value)) :: v_tail) ->
(match (f_references ((Base.nat_mul (256) (256))) ((Expression (v_value)))) with
| Fail __error -> Fail __error
| Done v_refs ->
(match (f_constant_nodes (v_tail)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done (((Node (v_name, (f_names_of (v_refs)), (f_lambdas_of (v_refs)))) :: v_rest))))))
and (* dependency.bend:215 *)
f_contains_step : bool -> (unit -> bool) -> bool =
fun v_equal v_remaining ->
(match v_equal with
| true ->
true
| false ->
(v_remaining (())))
and (* dependency.bend:222 *)
f_contains_work : (Base.text) list -> Base.text -> bool -> bool =
fun v_names v_name v_found ->
(match (v_names, v_found) with
| (_, true) ->
true
| ([], false) ->
false
| ((v_head :: v_tail), false) ->
(f_contains_work (v_tail) (v_name) ((M.f_name_equal (v_head) (v_name)))))
and (* dependency.bend:231 *)
f_contains : (Base.text) list -> Base.text -> bool =
fun v_names v_name ->
(f_contains_work (v_names) (v_name) (false))
and (* dependency.bend:234 *)
f_lookup : (t_Node) list -> Base.text -> (Base.text) list =
fun v_nodes v_name ->
(match v_nodes with
| [] ->
[]
| ((Node (v_found, v_refs, v_lambdas)) :: v_tail) ->
(Base.bool_pick ((M.f_name_equal (v_found) (v_name))) (v_refs) ((f_lookup (v_tail) (v_name)))))
and (* dependency.bend:241 *)
f_edge_count : (t_Node) list -> int =
fun v_nodes ->
(match v_nodes with
| [] ->
0
| ((Node (v_name, v_refs, v_lambdas)) :: v_tail) ->
(Base.nat_add ((Base.list_length (v_refs))) ((f_edge_count (v_tail)))))
and (* dependency.bend:248 *)
f_next_work : bool -> (Base.text) list -> (Base.text) list -> (Base.text) list =
fun v_visited v_dependencies v_pending ->
(match v_visited with
| true ->
v_pending
| false ->
(Base.list_append (v_dependencies) (v_pending)))
and (* dependency.bend:255 *)
f_node_names : (t_Node) list -> (Base.text) list =
fun v_nodes ->
(match v_nodes with
| [] ->
[]
| ((Node (v_name, v_refs, v_lambdas)) :: v_tail) ->
(v_name :: (f_node_names (v_tail))))
and (* dependency.bend:262 *)
f_adjacency : (t_Node) list -> ((Base.text) list) Base.map -> ((Base.text) list) Base.map =
fun v_nodes v_edges ->
(match v_nodes with
| [] ->
v_edges
| ((Node (v_name, v_refs, v_lambdas)) :: v_tail) ->
(f_adjacency (v_tail) ((Base.map_set (v_edges) (v_name) (v_refs)))))
and (* dependency.bend:269 *)
f_neighbors : ((Base.text) list) Base.map -> Base.text -> (Base.text) list =
fun v_edges v_name ->
(Index.f_get (v_edges) (v_name) ([]))
and (* dependency.bend:272 *)
f_transpose_edges : (Base.text) list -> Base.text -> ((Base.text) list) Base.map -> ((Base.text) list) Base.map =
fun v_refs v_name v_edges ->
(match v_refs with
| [] ->
v_edges
| (v_head :: v_tail) ->
(f_transpose_edges (v_tail) (v_name) ((Base.map_set (v_edges) (v_head) ((v_name :: (f_neighbors (v_edges) (v_head))))))))
and (* dependency.bend:279 *)
f_transpose : (t_Node) list -> ((Base.text) list) Base.map -> ((Base.text) list) Base.map =
fun v_nodes v_edges ->
(match v_nodes with
| [] ->
v_edges
| ((Node (v_name, v_refs, v_lambdas)) :: v_tail) ->
(f_transpose (v_tail) ((f_transpose_edges (v_refs) (v_name) (v_edges)))))
and (* dependency.bend:286 *)
f_member : Base.set -> Base.text -> bool =
fun v_names v_name ->
(Base.maybe_is_some ((Index.f_find (v_names) (v_name))))
and (* dependency.bend:289 *)
f_mark : bool -> Base.set -> Base.text -> Base.set =
fun v_fresh v_seen v_name ->
(match v_fresh with
| false ->
v_seen
| true ->
(Base.set_add (v_seen) (v_name)))
and (* dependency.bend:300 *)
f_enter_events : (Base.text) list -> (t_Visit) list -> (t_Visit) list =
fun v_names v_tail ->
(match v_names with
| [] ->
v_tail
| (v_head :: v_rest) ->
((Enter (v_head)) :: (f_enter_events (v_rest) (v_tail))))
and (* dependency.bend:307 *)
f_visit_events : bool -> Base.text -> (Base.text) list -> (t_Visit) list -> (t_Visit) list =
fun v_fresh v_name v_refs v_tail ->
(match v_fresh with
| false ->
v_tail
| true ->
(f_enter_events (v_refs) (((Leave (v_name)) :: v_tail))))
and (* dependency.bend:316 *)
f_unseen_known : bool -> Base.set -> Base.text -> bool =
fun v_already_seen v_known v_name ->
(match v_already_seen with
| true ->
false
| false ->
(f_member (v_known) (v_name)))
and (* dependency.bend:323 *)
f_fresh_name : Base.text -> Base.set -> Base.set -> bool =
fun v_name v_known v_seen ->
(f_unseen_known ((f_member (v_seen) (v_name))) (v_known) (v_name))
and (* dependency.bend:326 *)
f_visit_events_edges : bool -> Base.text -> ((Base.text) list) Base.map -> (t_Visit) list -> (t_Visit) list =
fun v_fresh v_name v_edges v_tail ->
(match v_fresh with
| false ->
v_tail
| true ->
(f_enter_events ((f_neighbors (v_edges) (v_name))) (((Leave (v_name)) :: v_tail))))
and (* dependency.bend:333 *)
f_finish_order : int -> (t_Visit) list -> ((Base.text) list) Base.map -> Base.set -> Base.set -> (Base.text) list -> (M.t_Diagnostic, (Base.text) list) Base.result_ =
fun v_fuel v_pending v_edges v_known v_seen v_order ->
(match (v_fuel, v_pending) with
| (_, []) ->
(Done (v_order))
| (0, _) ->
(Fail ((M.Diagnostic (s_4, s_1, s_5))))
| (__nat_61, ((Enter (v_name)) :: v_tail)) when __nat_61 >= 1 ->
(let v_rest = (__nat_61 - 1) in
(let v_fresh = (f_fresh_name (v_name) (v_known) (v_seen)) in
(f_finish_order (v_rest) ((f_visit_events_edges (v_fresh) (v_name) (v_edges) (v_tail))) (v_edges) (v_known) ((f_mark (v_fresh) (v_seen) (v_name))) (v_order))))
| (__nat_62, ((Leave (v_name)) :: v_tail)) when __nat_62 >= 1 ->
(let v_rest = (__nat_62 - 1) in
(f_finish_order (v_rest) (v_tail) (v_edges) (v_known) (v_seen) ((v_name :: v_order)))))
and (* dependency.bend:348 *)
f_reached_seen : t_Reachability -> Base.set =
fun v_result ->
(let (Reachability (v_seen, v_members)) = v_result in
v_seen)
and (* dependency.bend:352 *)
f_reached_members : t_Reachability -> (Base.text) list =
fun v_result ->
(let (Reachability (v_seen, v_members)) = v_result in
v_members)
and (* dependency.bend:356 *)
f_next_work_edges : bool -> ((Base.text) list) Base.map -> Base.text -> (Base.text) list -> (Base.text) list =
fun v_fresh v_edges v_name v_pending ->
(match v_fresh with
| false ->
v_pending
| true ->
(Base.list_append ((f_neighbors (v_edges) (v_name))) (v_pending)))
and (* dependency.bend:363 *)
f_reachable : int -> (Base.text) list -> ((Base.text) list) Base.map -> Base.set -> Base.set -> (Base.text) list -> (M.t_Diagnostic, t_Reachability) Base.result_ =
fun v_fuel v_pending v_edges v_known v_seen v_members ->
(match (v_fuel, v_pending) with
| (_, []) ->
(Done ((Reachability (v_seen, v_members))))
| (0, _) ->
(Fail ((M.Diagnostic (s_4, s_1, s_6))))
| (__nat_63, (v_head :: v_tail)) when __nat_63 >= 1 ->
(let v_rest = (__nat_63 - 1) in
(let v_fresh = (f_fresh_name (v_head) (v_known) (v_seen)) in
(f_reachable (v_rest) ((f_next_work_edges (v_fresh) (v_edges) (v_head) (v_tail))) (v_edges) (v_known) ((f_mark (v_fresh) (v_seen) (v_head))) ((Base.bool_pick (v_fresh) ((v_head :: v_members)) (v_members)))))))
and (* dependency.bend:373 *)
f_prepend_component : (Base.text) list -> ((Base.text) list) list -> ((Base.text) list) list =
fun v_members v_rest ->
(match v_members with
| [] ->
v_rest
| (v_head :: v_tail) ->
((v_head :: v_tail) :: v_rest))
and (* dependency.bend:380 *)
f_collect_components : (Base.text) list -> ((Base.text) list) Base.map -> Base.set -> Base.set -> int -> (M.t_Diagnostic, ((Base.text) list) list) Base.result_ =
fun v_order v_edges v_known v_seen v_fuel ->
(match v_order with
| [] ->
(Done ([]))
| (v_head :: v_tail) ->
(match (f_reachable (v_fuel) ([v_head]) (v_edges) (v_known) (v_seen) ([])) with
| Fail __error -> Fail __error
| Done v_reached ->
(match (f_collect_components (v_tail) (v_edges) (v_known) ((f_reached_seen (v_reached))) (v_fuel)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done ((f_prepend_component ((f_reached_members (v_reached))) (v_rest)))))))
and (* dependency.bend:397 *)
f_compact_catalog : (t_Node) list -> int -> t_CompactCatalog -> t_CompactCatalog =
fun v_nodes v_next v_known ->
(match v_nodes with
| [] ->
v_known
| ((Node (v_name, v_references, v_lambdas)) :: v_tail) ->
(let (CompactCatalog (v_ids, v_names)) = v_known in
(f_compact_catalog (v_tail) ((Base.nat_add 1 v_next)) ((CompactCatalog ((Base.map_set (v_ids) (v_name) (v_next)), (NatIndex.f_set (v_names) (v_next) (v_name))))))))
and (* dependency.bend:405 *)
f_compact_numbered_reference : (int) option -> (int) list -> (int) list =
fun v_found v_rest ->
(match v_found with
| None ->
v_rest
| (Some (v_identity)) ->
(v_identity :: v_rest))
and (* dependency.bend:410 *)
f_compact_numbered_references : (Base.text) list -> (int) Base.map -> (int) list =
fun v_names v_ids ->
(match v_names with
| [] ->
[]
| (v_name :: v_tail) ->
(f_compact_numbered_reference ((Index.f_find (v_ids) (v_name))) ((f_compact_numbered_references (v_tail) (v_ids)))))
and (* dependency.bend:416 *)
f_compact_reverse_edges : (int) list -> int -> ((int) list) NatIndex.t_Index -> ((int) list) NatIndex.t_Index =
fun v_references v_identity v_reversed ->
(match v_references with
| [] ->
v_reversed
| (v_head :: v_tail) ->
(f_compact_reverse_edges (v_tail) (v_identity) ((NatIndex.f_set (v_reversed) (v_head) ((v_identity :: (NatIndex.f_get (v_reversed) (v_head) ([]))))))))
and (* dependency.bend:425 *)
f_compact_graph : (t_Node) list -> (int) Base.map -> ((int) list) NatIndex.t_Index -> ((int) list) NatIndex.t_Index -> int -> (int) list -> t_CompactGraph =
fun v_nodes v_ids v_forward v_reverse v_fuel v_order ->
(match v_nodes with
| [] ->
(CompactGraph ((Base.list_reverse (v_order)), v_forward, v_reverse, v_fuel))
| ((Node (v_name, v_references, v_lambdas)) :: v_tail) ->
(let v_identity = (Index.f_get (v_ids) (v_name) (0)) in
(let v_targets = (f_compact_numbered_references (v_references) (v_ids)) in
(f_compact_graph (v_tail) (v_ids) ((NatIndex.f_set (v_forward) (v_identity) (v_targets))) ((f_compact_reverse_edges (v_targets) (v_identity) (v_reverse))) ((Base.nat_add ((Base.nat_add 2 v_fuel)) ((Base.list_length (v_references))))) ((v_identity :: v_order))))))
and (* dependency.bend:438 *)
f_compact_enter : (int) list -> (t_CompactVisit) list -> (t_CompactVisit) list =
fun v_names v_pending ->
(match v_names with
| [] ->
v_pending
| (v_head :: v_tail) ->
((CompactEnter (v_head)) :: (f_compact_enter (v_tail) (v_pending))))
and (* dependency.bend:443 *)
f_compact_fresh : (unit) NatIndex.t_Index -> int -> bool =
fun v_seen v_identity ->
(Base.bool_not ((Base.maybe_is_some ((NatIndex.f_find (v_seen) (v_identity))))))
and (* dependency.bend:446 *)
f_compact_mark : bool -> (unit) NatIndex.t_Index -> int -> (unit) NatIndex.t_Index =
fun v_fresh v_seen v_identity ->
(match v_fresh with
| false ->
v_seen
| true ->
(NatIndex.f_set (v_seen) (v_identity) (())))
and (* dependency.bend:451 *)
f_compact_events : bool -> int -> ((int) list) NatIndex.t_Index -> (t_CompactVisit) list -> (t_CompactVisit) list =
fun v_fresh v_identity v_edges v_tail ->
(match v_fresh with
| false ->
v_tail
| true ->
(f_compact_enter ((NatIndex.f_get (v_edges) (v_identity) ([]))) (((CompactLeave (v_identity)) :: v_tail))))
and (* dependency.bend:456 *)
f_compact_finish : int -> (t_CompactVisit) list -> ((int) list) NatIndex.t_Index -> (unit) NatIndex.t_Index -> (int) list -> (M.t_Diagnostic, (int) list) Base.result_ =
fun v_fuel v_pending v_edges v_seen v_order ->
(match (v_fuel, v_pending) with
| (_, []) ->
(Done (v_order))
| (0, _) ->
(Fail ((M.Diagnostic (s_4, s_1, s_5))))
| (__nat_64, ((CompactEnter (v_identity)) :: v_tail)) when __nat_64 >= 1 ->
(let v_rest = (__nat_64 - 1) in
(let v_unseen = (f_compact_fresh (v_seen) (v_identity)) in
(f_compact_finish (v_rest) ((f_compact_events (v_unseen) (v_identity) (v_edges) (v_tail))) (v_edges) ((f_compact_mark (v_unseen) (v_seen) (v_identity))) (v_order))))
| (__nat_65, ((CompactLeave (v_identity)) :: v_tail)) when __nat_65 >= 1 ->
(let v_rest = (__nat_65 - 1) in
(f_compact_finish (v_rest) (v_tail) (v_edges) (v_seen) ((v_identity :: v_order)))))
and (* dependency.bend:470 *)
f_compact_reached_seen : t_CompactReachability -> (unit) NatIndex.t_Index =
fun v_found ->
(let (CompactReachability (v_seen, v_members)) = v_found in
v_seen)
and (* dependency.bend:474 *)
f_compact_reached_members : t_CompactReachability -> (int) list =
fun v_found ->
(let (CompactReachability (v_seen, v_members)) = v_found in
v_members)
and (* dependency.bend:478 *)
f_compact_pending : bool -> ((int) list) NatIndex.t_Index -> int -> (int) list -> (int) list =
fun v_fresh v_edges v_identity v_tail ->
(match v_fresh with
| false ->
v_tail
| true ->
(Base.list_append ((NatIndex.f_get (v_edges) (v_identity) ([]))) (v_tail)))
and (* dependency.bend:483 *)
f_compact_reach : int -> (int) list -> ((int) list) NatIndex.t_Index -> (unit) NatIndex.t_Index -> (int) list -> (M.t_Diagnostic, t_CompactReachability) Base.result_ =
fun v_fuel v_work v_edges v_seen v_members ->
(match (v_fuel, v_work) with
| (_, []) ->
(Done ((CompactReachability (v_seen, v_members))))
| (0, _) ->
(Fail ((M.Diagnostic (s_4, s_1, s_6))))
| (__nat_66, (v_identity :: v_tail)) when __nat_66 >= 1 ->
(let v_rest = (__nat_66 - 1) in
(let v_unseen = (f_compact_fresh (v_seen) (v_identity)) in
(f_compact_reach (v_rest) ((f_compact_pending (v_unseen) (v_edges) (v_identity) (v_tail))) (v_edges) ((f_compact_mark (v_unseen) (v_seen) (v_identity))) ((Base.bool_pick (v_unseen) ((v_identity :: v_members)) (v_members)))))))
and (* dependency.bend:492 *)
f_compact_names : (int) list -> (Base.text) NatIndex.t_Index -> (Base.text) list =
fun v_members v_catalog ->
(match v_members with
| [] ->
[]
| (v_identity :: v_tail) ->
((NatIndex.f_get (v_catalog) (v_identity) (s_7)) :: (f_compact_names (v_tail) (v_catalog))))
and (* dependency.bend:498 *)
f_compact_prepend : (int) list -> ((Base.text) list) list -> (Base.text) NatIndex.t_Index -> ((Base.text) list) list =
fun v_members v_rest v_catalog ->
(match v_members with
| [] ->
v_rest
| (v_head :: v_tail) ->
((f_compact_names ((v_head :: v_tail)) (v_catalog)) :: v_rest))
and (* dependency.bend:503 *)
f_compact_collect : (int) list -> ((int) list) NatIndex.t_Index -> (unit) NatIndex.t_Index -> int -> (Base.text) NatIndex.t_Index -> (M.t_Diagnostic, ((Base.text) list) list) Base.result_ =
fun v_order v_edges v_seen v_fuel v_catalog ->
(match v_order with
| [] ->
(Done ([]))
| (v_head :: v_tail) ->
(match (f_compact_reach (v_fuel) ([v_head]) (v_edges) (v_seen) ([])) with
| Fail __error -> Fail __error
| Done v_reached ->
(match (f_compact_collect (v_tail) (v_edges) ((f_compact_reached_seen (v_reached))) (v_fuel) (v_catalog)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done ((f_compact_prepend ((f_compact_reached_members (v_reached))) (v_rest) (v_catalog)))))))
and (* dependency.bend:512 *)
f_compact_components_graph : t_CompactGraph -> (Base.text) NatIndex.t_Index -> (M.t_Diagnostic, ((Base.text) list) list) Base.result_ =
fun v_graph v_catalog ->
(let (CompactGraph (v_order, v_forward, v_reverse, v_fuel)) = v_graph in
(match (f_compact_finish (v_fuel) ((f_compact_enter (v_order) ([]))) (v_reverse) (NatIndex.Empty) ([])) with
| Fail __error -> Fail __error
| Done v_finished ->
(f_compact_collect (v_finished) (v_forward) (NatIndex.Empty) (v_fuel) (v_catalog))))
and (* dependency.bend:518 *)
f_compact_components_catalog : (t_Node) list -> t_CompactCatalog -> (M.t_Diagnostic, ((Base.text) list) list) Base.result_ =
fun v_nodes v_known ->
(let (CompactCatalog (v_ids, v_names)) = v_known in
(f_compact_components_graph ((f_compact_graph (v_nodes) (v_ids) (NatIndex.Empty) (NatIndex.Empty) (1) ([]))) (v_names)))
and (* dependency.bend:522 *)
f_components : (t_Node) list -> (M.t_Diagnostic, ((Base.text) list) list) Base.result_ =
fun v_nodes ->
(match v_nodes with
| [] ->
(Done ([]))
| ((Node (v_name, v_references, v_lambdas)) :: []) ->
(Done ([(v_name :: [])]))
| (v_head :: v_tail) ->
(f_compact_components_catalog (v_nodes) ((f_compact_catalog ((v_head :: v_tail)) (0) ((CompactCatalog (MTip, NatIndex.Empty)))))))
