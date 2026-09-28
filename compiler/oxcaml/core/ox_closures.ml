(* Native semantic port of compiler/closures.bend.

   Source SHA-256: d123e133afa778f224cd1ed19a7f587995ee7f54b45c0fe5c2a87201d05521c5

   Ownership/type arguments are erased; value types are checked by OCaml.

   No Bend interpreter or generated C/JavaScript is linked. *)

open Base

module M = Ox_model

type t_Lambda =
  | Lambda of int * Base.text * M.t_Expr * (Base.text) list
and t_FreeWork =
  | ExpressionWork of M.t_Expr * (Base.text) list
  | ExpressionsWork of (M.t_Expr) list * (Base.text) list
  | PatternReferences of (M.t_Pattern) list * (Base.text) list
  | ArmsWork of ((M.t_Expr) M.t_MatchArm) list * (Base.text) list
and t_PatternWork =
  | PatternWork of M.t_Pattern
  | PatternsWork of (M.t_Pattern) list

let s_0 = Base.text_of_utf8 "backend_limit"

let s_1 = Base.text_of_utf8 "pattern"

let s_2 = Base.text_of_utf8 "pattern binding analysis exceeded its structural depth limit"

let s_3 = Base.text_of_utf8 "closure"

let s_4 = Base.text_of_utf8 "closure analysis exceeded its structural depth limit"

let s_5 = Base.text_of_utf8 "lambda collection exceeded its structural depth limit"

let rec (* closures.bend:17 *)
f_contains : (Base.text) list -> Base.text -> bool =
fun v_names v_name ->
(match v_names with
| [] ->
false
| (v_head :: v_tail) ->
(Base.bool_or ((M.f_name_equal (v_head) (v_name))) ((f_contains (v_tail) (v_name)))))
and (* closures.bend:24 *)
f_union : (Base.text) list -> (Base.text) list -> (Base.text) list =
fun v_left v_right ->
(match v_left with
| [] ->
v_right
| (v_head :: v_tail) ->
(let v_rest = (f_union (v_tail) (v_right)) in
(Base.bool_pick ((f_contains (v_rest) (v_head))) (v_rest) ((v_head :: v_rest)))))
and (* closures.bend:32 *)
f_pattern_names_work : int -> t_PatternWork -> (Base.text) list -> (M.t_Diagnostic, (Base.text) list) Base.result_ =
fun v_fuel v_work v_reversed ->
(match (v_fuel, v_work) with
| (0, _) ->
(Fail ((M.Diagnostic (s_0, s_1, s_2))))
| (__nat_1, (PatternWork ((M.BindingPattern (v_name))))) when __nat_1 >= 1 ->
(let v_rest = (__nat_1 - 1) in
(Done ((v_name :: v_reversed))))
| (__nat_2, (PatternWork ((M.ConstructorPattern (v_constructor, (Some (v_payload))))))) when __nat_2 >= 1 ->
(let v_rest = (__nat_2 - 1) in
(f_pattern_names_work (v_rest) ((PatternWork (v_payload))) (v_reversed)))
| (__nat_3, (PatternWork ((M.ProductPattern (v_elements))))) when __nat_3 >= 1 ->
(let v_rest = (__nat_3 - 1) in
(f_pattern_names_work (v_rest) ((PatternsWork (v_elements))) (v_reversed)))
| (__nat_4, (PatternWork (v_pattern))) when __nat_4 >= 1 ->
(let v_rest = (__nat_4 - 1) in
(Done (v_reversed)))
| (__nat_5, (PatternsWork ([]))) when __nat_5 >= 1 ->
(let v_rest = (__nat_5 - 1) in
(Done (v_reversed)))
| (__nat_6, (PatternsWork ((v_head :: v_tail)))) when __nat_6 >= 1 ->
(let v_rest = (__nat_6 - 1) in
(match (f_pattern_names_work (v_rest) ((PatternWork (v_head))) (v_reversed)) with
| Fail __error -> Fail __error
| Done v_collected ->
(f_pattern_names_work (v_rest) ((PatternsWork (v_tail))) (v_collected)))))
and (* closures.bend:51 *)
f_row_names : (M.t_Pattern) list -> (M.t_Diagnostic, (Base.text) list) Base.result_ =
fun v_patterns ->
(match (f_pattern_names_work ((Base.u32_to_nat ((Base.W32 0x4000)))) ((PatternsWork (v_patterns))) ([])) with
| Fail __error -> Fail __error
| Done v_reversed ->
(Done ((Base.list_reverse (v_reversed)))))
and (* closures.bend:56 *)
f_pattern_names : M.t_Pattern -> (M.t_Diagnostic, (Base.text) list) Base.result_ =
fun v_pattern ->
(f_row_names ([v_pattern]))
and (* closures.bend:59 *)
f_arm_expressions : ((M.t_Expr) M.t_MatchArm) list -> (M.t_Expr) list =
fun v_arms ->
(match v_arms with
| [] ->
[]
| ((M.MatchArm (v_patterns, v_body)) :: v_tail) ->
(v_body :: (f_arm_expressions (v_tail))))
and (* closures.bend:66 *)
f_children : M.t_Expr -> (M.t_Expr) list =
fun v_expression ->
(match v_expression with
| (M.ConstructExpr (v_constructor, (Some (v_payload)))) ->
[v_payload]
| (M.ProductExpr (v_elements)) ->
v_elements
| (M.ProjectExpr (v_value, v_index)) ->
[v_value]
| (M.ArrayExpr (v_elements)) ->
v_elements
| (M.ForExpr (v_index, v_start, v_end, v_state, v_initial, v_body)) ->
[v_start; v_end; v_initial; v_body]
| (M.ForeverExpr (v_state, v_initial, v_body)) ->
[v_initial; v_body]
| (M.ArrayGenerateExpr (v_count, v_generator)) ->
[v_count; v_generator]
| (M.ArrayFillExpr (v_count, v_value)) ->
[v_count; v_value]
| (M.ArrayGetExpr (v_array, v_index)) ->
[v_array; v_index]
| (M.ArraySetExpr (v_array, v_index, v_value)) ->
[v_array; v_index; v_value]
| (M.ArrayLengthExpr (v_array)) ->
[v_array]
| (M.LambdaExpr (v_identity, v_parameter, v_parameter_type, v_result_type, v_body)) ->
[v_body]
| (M.ApplyExpr (v_callee, v_argument)) ->
[v_callee; v_argument]
| (M.TagExpr (v_offset, v_callee, v_argument)) ->
[v_callee; v_argument]
| (M.CallExpr (v_callee, v_argument)) ->
[v_argument]
| (M.AssociatedExpr (v_identity, v_dispatch, v_member, v_templates, v_left, v_right)) ->
[v_left; v_right]
| (M.ScalarExpr (v_operator, v_left, v_right)) ->
[v_left; v_right]
| (M.UnaryExpr (v_operator, v_value)) ->
[v_value]
| (M.LetExpr (v_name, v_value, v_body)) ->
[v_value; v_body]
| (M.UseExpr (v_name, v_value, v_body)) ->
[v_value; v_body]
| (M.IfExpr (v_condition, v_consequent, v_alternative)) ->
[v_condition; v_consequent; v_alternative]
| (M.SequenceExpr (v_first, v_next)) ->
[v_first; v_next]
| (M.MatchExpr (v_values, v_arms)) ->
(Base.list_append (v_values) ((f_arm_expressions (v_arms))))
| (M.GuardExpr (v_pattern, v_value, v_alternative, v_body)) ->
[v_value; v_alternative; v_body]
| (M.BlockExpr (v_label, v_body)) ->
[v_body]
| (M.ReturnExpr (v_label, v_value)) ->
[v_value]
| (M.RuntimeInitExpr (v_value)) ->
[v_value]
| (M.SourceExpr (v_offset, v_annotation, v_value)) ->
[v_value]
| (M.QualifiedExpr (v_offset, v_annotation, v_predicates, v_value)) ->
[v_value]
| (M.InstantiationExpr (v_site, v_value)) ->
[v_value]
| (M.SpecializeOperationExpr (v_template, v_arguments, v_body)) ->
[v_body]
| (M.StateProviderExpr (v_read, v_write, v_initial)) ->
[v_initial]
| (M.ProviderExpr (v_identity, v_implementation)) ->
[v_implementation]
| (M.HandleExpr (v_provider, v_body)) ->
[v_provider; v_body]
| (M.EffectHasExpr (v_set, v_operation)) ->
[v_set; v_operation]
| (M.EffectCountExpr (v_set)) ->
[v_set]
| (M.EffectSameExpr (v_left, v_right)) ->
[v_left; v_right]
| _ ->
[])
and (* closures.bend:145 *)
f_free : int -> t_FreeWork -> (M.t_Diagnostic, (Base.text) list) Base.result_ =
fun v_fuel v_work ->
(match v_fuel with
| 0 ->
(Fail ((M.Diagnostic (s_0, s_3, s_4))))
| __nat_7 when __nat_7 >= 1 ->
(let v_rest = (__nat_7 - 1) in
(match v_work with
| (ExpressionWork ((M.LocalExpr (v_name)), v_bound)) ->
(Done ((Base.bool_pick ((f_contains (v_bound) (v_name))) ([]) ([v_name]))))
| (ExpressionWork ((M.LambdaExpr (v_identity, v_parameter, v_parameter_type, v_result_type, v_body)), v_bound)) ->
(f_free (v_rest) ((ExpressionWork (v_body, (v_parameter :: v_bound)))))
| (ExpressionWork ((M.LetExpr (v_name, v_value, v_body)), v_bound)) ->
(match (f_free (v_rest) ((ExpressionWork (v_value, v_bound)))) with
| Fail __error -> Fail __error
| Done v_a ->
(match (f_free (v_rest) ((ExpressionWork (v_body, (v_name :: v_bound))))) with
| Fail __error -> Fail __error
| Done v_b ->
(Done ((f_union (v_a) (v_b))))))
| (ExpressionWork ((M.ForExpr (v_index, v_start, v_end, v_state, v_initial, v_body)), v_bound)) ->
(match (f_free (v_rest) ((ExpressionsWork ([v_start; v_end; v_initial], v_bound)))) with
| Fail __error -> Fail __error
| Done v_a ->
(match (f_free (v_rest) ((ExpressionWork (v_body, (v_index :: (v_state :: v_bound)))))) with
| Fail __error -> Fail __error
| Done v_b ->
(Done ((f_union (v_a) (v_b))))))
| (ExpressionWork ((M.ForeverExpr (v_state, v_initial, v_body)), v_bound)) ->
(match (f_free (v_rest) ((ExpressionWork (v_initial, v_bound)))) with
| Fail __error -> Fail __error
| Done v_a ->
(match (f_free (v_rest) ((ExpressionWork (v_body, (v_state :: v_bound))))) with
| Fail __error -> Fail __error
| Done v_b ->
(Done ((f_union (v_a) (v_b))))))
| (ExpressionWork ((M.UseExpr (v_name, v_value, v_body)), v_bound)) ->
(match (f_free (v_rest) ((ExpressionWork (v_value, v_bound)))) with
| Fail __error -> Fail __error
| Done v_a ->
(match (f_free (v_rest) ((ExpressionWork (v_body, (v_name :: v_bound))))) with
| Fail __error -> Fail __error
| Done v_b ->
(Done ((f_union (v_a) (v_b))))))
| (ExpressionWork ((M.MatchExpr (v_values, v_arms)), v_bound)) ->
(match (f_free (v_rest) ((ExpressionsWork (v_values, v_bound)))) with
| Fail __error -> Fail __error
| Done v_a ->
(match (f_free (v_rest) ((ArmsWork (v_arms, v_bound)))) with
| Fail __error -> Fail __error
| Done v_b ->
(Done ((f_union (v_a) (v_b))))))
| (ExpressionWork ((M.GuardExpr (v_pattern, v_value, v_alternative, v_body)), v_bound)) ->
(match (f_free (v_rest) ((PatternReferences ([v_pattern], v_bound)))) with
| Fail __error -> Fail __error
| Done v_refs ->
(match (f_free (v_rest) ((ExpressionsWork ([v_value; v_alternative], v_bound)))) with
| Fail __error -> Fail __error
| Done v_a ->
(match (f_pattern_names (v_pattern)) with
| Fail __error -> Fail __error
| Done v_names ->
(match (f_free (v_rest) ((ExpressionWork (v_body, (Base.list_append (v_names) (v_bound)))))) with
| Fail __error -> Fail __error
| Done v_b ->
(Done ((f_union (v_refs) ((f_union (v_a) (v_b))))))))))
| (ExpressionWork (v_expression, v_bound)) ->
(f_free (v_rest) ((ExpressionsWork ((f_children (v_expression)), v_bound))))
| (ExpressionsWork ([], v_bound)) ->
(Done ([]))
| (ExpressionsWork ((v_head :: v_tail), v_bound)) ->
(match (f_free (v_rest) ((ExpressionWork (v_head, v_bound)))) with
| Fail __error -> Fail __error
| Done v_a ->
(match (f_free (v_rest) ((ExpressionsWork (v_tail, v_bound)))) with
| Fail __error -> Fail __error
| Done v_b ->
(Done ((f_union (v_a) (v_b))))))
| (PatternReferences ([], v_bound)) ->
(Done ([]))
| (PatternReferences (((M.ValuePattern (v_reference)) :: v_tail), v_bound)) ->
(match (f_free (v_rest) ((ExpressionWork ((M.f_reference_expr (v_reference)), v_bound)))) with
| Fail __error -> Fail __error
| Done v_a ->
(match (f_free (v_rest) ((PatternReferences (v_tail, v_bound)))) with
| Fail __error -> Fail __error
| Done v_b ->
(Done ((f_union (v_a) (v_b))))))
| (PatternReferences (((M.ConstructorPattern (v_name, (Some (v_payload)))) :: v_tail), v_bound)) ->
(f_free (v_rest) ((PatternReferences ((v_payload :: v_tail), v_bound))))
| (PatternReferences (((M.ProductPattern (v_elements)) :: v_tail), v_bound)) ->
(f_free (v_rest) ((PatternReferences ((Base.list_append (v_elements) (v_tail)), v_bound))))
| (PatternReferences ((v_pattern :: v_tail), v_bound)) ->
(f_free (v_rest) ((PatternReferences (v_tail, v_bound))))
| (ArmsWork ([], v_bound)) ->
(Done ([]))
| (ArmsWork (((M.MatchArm (v_patterns, v_body)) :: v_tail), v_bound)) ->
(match (f_free (v_rest) ((PatternReferences (v_patterns, v_bound)))) with
| Fail __error -> Fail __error
| Done v_refs ->
(match (f_row_names (v_patterns)) with
| Fail __error -> Fail __error
| Done v_names ->
(match (f_free (v_rest) ((ExpressionWork (v_body, (Base.list_append (v_names) (v_bound)))))) with
| Fail __error -> Fail __error
| Done v_a ->
(match (f_free (v_rest) ((ArmsWork (v_tail, v_bound)))) with
| Fail __error -> Fail __error
| Done v_b ->
(Done ((f_union (v_refs) ((f_union (v_a) (v_b)))))))))))))
and (* closures.bend:219 *)
f_lambda : M.t_Expr -> (M.t_Diagnostic, (t_Lambda) list) Base.result_ =
fun v_expression ->
(match v_expression with
| (M.LambdaExpr (v_identity, v_parameter, v_parameter_type, v_result_type, v_body)) ->
(match (f_free ((Base.u32_to_nat ((Base.W32 0x1000)))) ((ExpressionWork (v_body, [v_parameter])))) with
| Fail __error -> Fail __error
| Done v_captures ->
(Done ([(Lambda (v_identity, v_parameter, v_body, v_captures))])))
| _ ->
(Done ([])))
and (* closures.bend:228 *)
f_collect : int -> (M.t_Expr) list -> (M.t_Diagnostic, (t_Lambda) list) Base.result_ =
fun v_fuel v_expressions ->
(match v_fuel with
| 0 ->
(Fail ((M.Diagnostic (s_0, s_3, s_5))))
| __nat_8 when __nat_8 >= 1 ->
(let v_rest = (__nat_8 - 1) in
(match v_expressions with
| [] ->
(Done ([]))
| (v_head :: v_tail) ->
(match (f_lambda (v_head)) with
| Fail __error -> Fail __error
| Done v_own ->
(match (f_collect (v_rest) ((f_children (v_head)))) with
| Fail __error -> Fail __error
| Done v_nested ->
(match (f_collect (v_rest) (v_tail)) with
| Fail __error -> Fail __error
| Done v_siblings ->
(Done ((Base.list_append (v_own) ((Base.list_append (v_nested) (v_siblings))))))))))))
and (* closures.bend:243 *)
f_function_expressions : (M.t_CheckedFunction) list -> (M.t_Expr) list =
fun v_functions ->
(match v_functions with
| [] ->
[]
| ((M.CheckedFunction ((M.Function (v_name, v_exported, v_parameter, v_parameter_type, v_result_type, v_body)), v_signature, v_effects)) :: v_tail) ->
(v_body :: (f_function_expressions (v_tail))))
and (* closures.bend:250 *)
f_constant_expressions : (M.t_CheckedConstant) list -> (M.t_Expr) list =
fun v_constants ->
(match v_constants with
| [] ->
[]
| ((M.CheckedConstant ((M.Constant (v_name, v_exported, v_annotation, v_value)), v_inferred_type, v_variables)) :: v_tail) ->
(v_value :: (f_constant_expressions (v_tail))))
