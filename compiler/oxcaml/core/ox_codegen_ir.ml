(* Native semantic port of compiler/codegen_ir.bend.

   Source SHA-256: 555b0e70244574b740884a0106249d7ac4084cfb77c6d488b67d5c9767d77ae2

   Ownership/type arguments are erased; value types are checked by OCaml.

   No Bend interpreter or generated C/JavaScript is linked. *)

open Base

module M = Ox_model

module F = Ox_closures

module E = Ox_wasm_catalog

module Index = Ox_index

module Saturation = Ox_codegen_saturation

type t_Metadata =
  | Metadata of ((F.t_Lambda) option) Base.map * ((E.t_ConstructorSlot) option) Base.map * Base.set * ((Saturation.t_Definition) option) Base.map
and t_Expr =
  | UnitExpr
  | U32Expr of int32
  | BoolExpr of bool
  | LocalExpr of Base.text
  | ConstantExpr of Base.text
  | ClosureExpr of Base.text * (Base.text) list
  | ConstructExpr of Base.text * (t_Expr) option
  | ApplyExpr of t_Expr * t_Expr
  | CallExpr of Base.text * t_Expr
  | ScalarExpr of M.t_ScalarOp * t_Expr * t_Expr
  | LetExpr of Base.text * t_Expr * t_Expr
  | IfExpr of t_Expr * t_Expr * t_Expr
  | SequenceExpr of t_Expr * t_Expr
  | MatchExpr of (t_Expr) list * ((t_Expr) M.t_MatchArm) list
  | GuardExpr of M.t_Pattern * t_Expr * t_Expr * t_Expr
  | BlockExpr of int * t_Expr
  | ReturnExpr of int * t_Expr
  | F32Expr of int32
  | UnaryExpr of M.t_UnaryOp * t_Expr
  | ProviderExpr of M.t_TypeId * t_Expr
  | StateProviderExpr of M.t_TypeId * M.t_TypeId * t_Expr
  | HandleExpr of t_Expr * t_Expr
  | InvokeOperationExpr of M.t_TypeId * t_Expr
  | PanicExpr of Base.text
  | ProductExpr of (t_Expr) list
  | ProjectExpr of t_Expr * int
  | ArrayExpr of (t_Expr) list
  | ForExpr of Base.text * t_Expr * t_Expr * Base.text * t_Expr * t_Expr
  | ForeverExpr of Base.text * t_Expr * t_Expr * bool
  | ArrayGenerateExpr of t_Expr * t_Expr
  | ArrayFillExpr of t_Expr * t_Expr
  | ArrayGetExpr of t_Expr * t_Expr
  | ArraySetExpr of t_Expr * t_Expr * t_Expr
  | ArrayReuseExpr of t_Expr * t_Expr * t_Expr
  | ArrayLengthExpr of t_Expr
and t_Work =
  | ExpressionWork of M.t_Expr
  | ExpressionsWork of (M.t_Expr) list * (t_Expr) list

let s_0 = Base.text_of_utf8 "internal_error"

let s_1 = Base.text_of_utf8 "codegen"

let s_2 = Base.text_of_utf8 "runtime projection lost a checked expression child"

let s_3 = Base.text_of_utf8 "operation:"

let s_4 = Base.text_of_utf8 ":"

let s_5 = Base.text_of_utf8 "backend_const_only"

let s_6 = Base.text_of_utf8 "effect reflection"

let s_7 = Base.text_of_utf8 "effect descriptors and reflection are only available during constant evaluation"

let s_8 = Base.text_of_utf8 "runtime projection lost a checked lambda"

let s_9 = Base.text_of_utf8 "lambda:"

let s_10 = Base.text_of_utf8 "runtime projection lost a checked constructor"

let s_11 = Base.text_of_utf8 "constructor:"

let s_12 = Base.text_of_utf8 "fn:"

let s_13 = Base.text_of_utf8 "backend_limit"

let s_14 = Base.text_of_utf8 "runtime projection exceeded its structural depth limit"

let rec (* codegen_ir.bend:11 *)
f_lambda_index_go : (F.t_Lambda) list -> ((F.t_Lambda) option) Base.map -> ((F.t_Lambda) option) Base.map =
fun v_lambdas v_indexed ->
(match v_lambdas with
| [] ->
v_indexed
| ((F.Lambda (v_identity, v_parameter, v_body, v_captures)) :: v_tail) ->
(f_lambda_index_go (v_tail) ((Base.map_set (v_indexed) ((Base.nat_show (v_identity))) ((Some ((F.Lambda (v_identity, v_parameter, v_body, v_captures)))))))))
and (* codegen_ir.bend:18 *)
f_metadata : (F.t_Lambda) list -> ((E.t_ConstructorSlot) option) Base.map -> t_Metadata =
fun v_lambdas v_constructors ->
(Metadata ((f_lambda_index_go ((Base.list_reverse (v_lambdas))) ((Base.map_new ()))), v_constructors, (Base.set_new ()), (Saturation.f_empty ())))
and (* codegen_ir.bend:21 *)
f_metadata_lambdas : t_Metadata -> ((F.t_Lambda) option) Base.map =
fun v_projection ->
(let (Metadata (v_lambdas, v_constructors, v_safe_loops, v_functions)) = v_projection in
v_lambdas)
and (* codegen_ir.bend:25 *)
f_metadata_constructors : t_Metadata -> ((E.t_ConstructorSlot) option) Base.map =
fun v_projection ->
(let (Metadata (v_lambdas, v_constructors, v_safe_loops, v_functions)) = v_projection in
v_constructors)
and (* codegen_ir.bend:29 *)
f_with_safe_loops : t_Metadata -> Base.set -> t_Metadata =
fun v_projection v_entries ->
(let (Metadata (v_lambdas, v_constructors, v_previous, v_functions)) = v_projection in
(Metadata (v_lambdas, v_constructors, v_entries, v_functions)))
and (* codegen_ir.bend:33 *)
f_with_functions : t_Metadata -> (M.t_CheckedFunction) list -> t_Metadata =
fun v_projection v_checked ->
(let (Metadata (v_lambdas, v_constructors, v_safe_loops, v_previous)) = v_projection in
(Metadata (v_lambdas, v_constructors, v_safe_loops, (Saturation.f_definitions (v_checked) ((Saturation.f_empty ()))))))
and (* codegen_ir.bend:37 *)
f_metadata_functions : t_Metadata -> ((Saturation.t_Definition) option) Base.map =
fun v_projection ->
(let (Metadata (v_lambdas, v_constructors, v_safe_loops, v_functions)) = v_projection in
v_functions)
and (* codegen_ir.bend:41 *)
f_safe_loop_entry : t_Metadata -> Base.text -> bool =
fun v_projection v_key ->
(let (Metadata (v_lambdas, v_constructors, v_safe_loops, v_functions)) = v_projection in
(Base.maybe_is_some ((Index.f_find (v_safe_loops) (v_key)))))
and (* codegen_ir.bend:45 *)
f_lambda_get : ((F.t_Lambda) option) Base.map -> int -> (F.t_Lambda) option =
fun v_indexed v_identity ->
(Index.f_get (v_indexed) ((Base.nat_show (v_identity))) (None))
and (* codegen_ir.bend:91 *)
f_invalid : unit -> M.t_Diagnostic =
fun () ->
(M.Diagnostic (s_0, s_1, s_2))
and (* codegen_ir.bend:94 *)
f_operation_key : M.t_TypeId -> Base.text =
fun v_identity ->
(let (M.TypeId (v_module_name, v_declaration)) = v_identity in
(Base.string_append s_3 (Base.string_append (Base.nat_show ((Base.string_length (v_module_name)))) (Base.string_append s_4 (Base.string_append v_module_name v_declaration)))))
and (* codegen_ir.bend:98 *)
f_const_only : unit -> M.t_Diagnostic =
fun () ->
(M.Diagnostic (s_5, s_6, s_7))
and (* codegen_ir.bend:101 *)
f_one : (t_Expr) list -> (M.t_Diagnostic, t_Expr) Base.result_ =
fun v_expressions ->
(match v_expressions with
| (v_expression :: []) ->
(Done (v_expression))
| _ ->
(Fail ((f_invalid ()))))
and (* codegen_ir.bend:108 *)
f_closure_reference : (F.t_Lambda) option -> int -> (M.t_Diagnostic, t_Expr) Base.result_ =
fun v_found v_wanted ->
(match v_found with
| None ->
(Fail ((M.Diagnostic (s_0, (Base.nat_show (v_wanted)), s_8))))
| (Some ((F.Lambda (v_identity, v_parameter, v_body, v_captures)))) ->
(Done ((ClosureExpr ((Base.string_append s_9 (Base.nat_show (v_wanted))), v_captures)))))
and (* codegen_ir.bend:115 *)
f_constructor_reference : (E.t_ConstructorSlot) option -> Base.text -> (M.t_Diagnostic, t_Expr) Base.result_ =
fun v_found v_wanted ->
(match v_found with
| None ->
(Fail ((M.Diagnostic (s_0, v_wanted, s_10))))
| (Some ((E.ConstructorSlot (v_name, v_tag, false)))) ->
(Done ((ConstructExpr (v_wanted, None))))
| (Some ((E.ConstructorSlot (v_name, v_tag, true)))) ->
(Done ((ClosureExpr ((Base.string_append s_11 v_wanted), [])))))
and (* codegen_ir.bend:124 *)
f_rebuild_arms : ((M.t_Expr) M.t_MatchArm) list -> (t_Expr) list -> (M.t_Diagnostic, ((t_Expr) M.t_MatchArm) list) Base.result_ =
fun v_arms v_bodies ->
(match (v_arms, v_bodies) with
| ([], []) ->
(Done ([]))
| (((M.MatchArm (v_patterns, v_body)) :: v_tail), (v_head :: v_rest)) ->
(match (f_rebuild_arms (v_tail) (v_rest)) with
| Fail __error -> Fail __error
| Done v_remaining ->
(Done (((M.MatchArm (v_patterns, v_head)) :: v_remaining))))
| (_, _) ->
(Fail ((f_invalid ()))))
and (* codegen_ir.bend:135 *)
f_rebuild : M.t_Expr -> (t_Expr) list -> (M.t_Diagnostic, t_Expr) Base.result_ =
fun v_original v_children ->
(match (v_original, v_children) with
| (M.UnitExpr, []) ->
(Done (UnitExpr))
| ((M.U32Expr (v_value)), []) ->
(Done ((U32Expr (v_value))))
| ((M.F32Expr (v_value)), []) ->
(Done ((F32Expr (v_value))))
| ((M.BoolExpr (v_value)), []) ->
(Done ((BoolExpr (v_value))))
| ((M.LocalExpr (v_name)), []) ->
(Done ((LocalExpr (v_name))))
| ((M.ConstantExpr (v_name)), []) ->
(Done ((ConstantExpr (v_name))))
| ((M.FunctionExpr (v_name)), []) ->
(Done ((ClosureExpr ((Base.string_append s_12 v_name), []))))
| ((M.OperationExpr (v_identity)), []) ->
(Done ((ClosureExpr ((f_operation_key (v_identity)), []))))
| ((M.StateProviderExpr (v_read, v_write, v_initial)), (v_value :: [])) ->
(Done ((StateProviderExpr (v_read, v_write, v_value))))
| ((M.ProviderExpr (v_identity, v_implementation)), (v_value :: [])) ->
(Done ((ProviderExpr (v_identity, v_value))))
| ((M.HandleExpr (v_provider, v_body)), (v_p :: (v_b :: []))) ->
(Done ((HandleExpr (v_p, v_b))))
| ((M.PanicExpr (v_message)), []) ->
(Done ((PanicExpr (v_message))))
| ((M.ProductExpr (v_elements)), v_children) ->
(Done ((ProductExpr (v_children))))
| ((M.ProjectExpr (v_value, v_index)), (v_child :: [])) ->
(Done ((ProjectExpr (v_child, v_index))))
| ((M.ArrayExpr (v_elements)), v_children) ->
(Done ((ArrayExpr (v_children))))
| ((M.ForExpr (v_index, v_start, v_end, v_state, v_initial, v_body)), (v_a :: (v_b :: (v_c :: (v_d :: []))))) ->
(Done ((ForExpr (v_index, v_a, v_b, v_state, v_c, v_d))))
| ((M.ForeverExpr (v_state, v_initial, v_body)), (v_a :: (v_b :: []))) ->
(Done ((ForeverExpr (v_state, v_a, v_b, false))))
| ((M.ArrayGenerateExpr (v_count, v_generator)), (v_c :: (v_v :: []))) ->
(Done ((ArrayGenerateExpr (v_c, v_v))))
| ((M.ArrayFillExpr (v_count, v_value)), (v_c :: (v_v :: []))) ->
(Done ((ArrayFillExpr (v_c, v_v))))
| ((M.ArrayGetExpr (v_array, v_index)), (v_a :: (v_i :: []))) ->
(Done ((ArrayGetExpr (v_a, v_i))))
| ((M.ArraySetExpr (v_array, v_index, v_value)), (v_a :: (v_i :: (v_v :: [])))) ->
(Done ((ArraySetExpr (v_a, v_i, v_v))))
| ((M.ArrayLengthExpr (v_array)), (v_child :: [])) ->
(Done ((ArrayLengthExpr (v_child))))
| ((M.OperationDescriptorExpr (v_identity)), _) ->
(Fail ((f_const_only ())))
| ((M.FunctionEffectsExpr (v_callee)), _) ->
(Fail ((f_const_only ())))
| ((M.EffectHasExpr (v_set, v_operation)), _) ->
(Fail ((f_const_only ())))
| ((M.EffectCountExpr (v_set)), _) ->
(Fail ((f_const_only ())))
| ((M.EffectSameExpr (v_left, v_right)), _) ->
(Fail ((f_const_only ())))
| ((M.ConstructExpr (v_constructor, None)), []) ->
(Done ((ConstructExpr (v_constructor, None))))
| ((M.ConstructExpr (v_constructor, (Some (v_payload)))), (v_child :: [])) ->
(Done ((ConstructExpr (v_constructor, (Some (v_child))))))
| ((M.ApplyExpr (v_callee, v_argument)), (v_function :: (v_value :: []))) ->
(Done ((ApplyExpr (v_function, v_value))))
| ((M.CallExpr (v_callee, v_argument)), (v_value :: [])) ->
(Done ((CallExpr ((Base.string_append s_12 v_callee), v_value))))
| ((M.ScalarExpr (v_operator, v_left, v_right)), (v_a :: (v_b :: []))) ->
(Done ((ScalarExpr (v_operator, v_a, v_b))))
| ((M.UnaryExpr (v_operator, v_value)), (v_child :: [])) ->
(Done ((UnaryExpr (v_operator, v_child))))
| ((M.LetExpr (v_name, v_value, v_body)), (v_v :: (v_b :: []))) ->
(Done ((LetExpr (v_name, v_v, v_b))))
| ((M.UseExpr (v_name, v_value, v_body)), (v_v :: (v_b :: []))) ->
(Done ((LetExpr (v_name, v_v, v_b))))
| ((M.IfExpr (v_condition, v_consequent, v_alternative)), (v_c :: (v_y :: (v_n :: [])))) ->
(Done ((IfExpr (v_c, v_y, v_n))))
| ((M.SequenceExpr (v_first, v_next)), (v_a :: (v_b :: []))) ->
(Done ((SequenceExpr (v_a, v_b))))
| ((M.MatchExpr (v_values, v_arms)), v_children) ->
(let v_count = (Base.list_length (v_values)) in
(match (f_rebuild_arms (v_arms) ((Base.list_drop (v_children) (v_count)))) with
| Fail __error -> Fail __error
| Done v_branches ->
(Done ((MatchExpr ((Base.list_take (v_children) (v_count)), v_branches))))))
| ((M.GuardExpr (v_pattern, v_value, v_alternative, v_body)), (v_v :: (v_a :: (v_b :: [])))) ->
(Done ((GuardExpr (v_pattern, v_v, v_a, v_b))))
| ((M.BlockExpr (v_label, v_body)), (v_b :: [])) ->
(Done ((BlockExpr (v_label, v_b))))
| ((M.ReturnExpr (v_label, v_value)), (v_v :: [])) ->
(Done ((ReturnExpr (v_label, v_v))))
| (_, _) ->
(Fail ((f_invalid ()))))
and (* codegen_ir.bend:228 *)
f_flat_annotation : int -> M.t_Expr -> bool =
fun v_fuel v_expression ->
(match (v_fuel, v_expression) with
| (0, _) ->
false
| (__nat_1, (M.SourceExpr (v_offset, (Some ((M.ArrayTy (M.F32Ty)))), v_value))) when __nat_1 >= 1 ->
(let v_rest = (__nat_1 - 1) in
true)
| (__nat_2, (M.SourceExpr (v_offset, (Some ((M.ArrayTy (M.U32Ty)))), v_value))) when __nat_2 >= 1 ->
(let v_rest = (__nat_2 - 1) in
true)
| (__nat_3, (M.SourceExpr (v_offset, v_annotation, v_value))) when __nat_3 >= 1 ->
(let v_rest = (__nat_3 - 1) in
(f_flat_annotation (v_rest) (v_value)))
| (__nat_4, (M.QualifiedExpr (v_offset, v_annotation, v_predicates, v_value))) when __nat_4 >= 1 ->
(let v_rest = (__nat_4 - 1) in
(f_flat_annotation (v_rest) (v_value)))
| (__nat_5, (M.InstantiationExpr (v_site, v_value))) when __nat_5 >= 1 ->
(let v_rest = (__nat_5 - 1) in
(f_flat_annotation (v_rest) (v_value)))
| (_, _) ->
false)
and (* codegen_ir.bend:245 *)
f_flat_carry : int -> M.t_Expr -> Base.set -> bool =
fun v_fuel v_expression v_arrays ->
(match (v_fuel, v_expression) with
| (0, _) ->
false
| (__nat_6, (M.LocalExpr (v_name))) when __nat_6 >= 1 ->
(let v_rest = (__nat_6 - 1) in
(Base.maybe_is_some ((Index.f_find (v_arrays) (v_name)))))
| (__nat_7, (M.SourceExpr (v_offset, v_annotation, v_value))) when __nat_7 >= 1 ->
(let v_rest = (__nat_7 - 1) in
(f_flat_carry (v_rest) (v_value) (v_arrays)))
| (__nat_8, (M.QualifiedExpr (v_offset, v_annotation, v_predicates, v_value))) when __nat_8 >= 1 ->
(let v_rest = (__nat_8 - 1) in
(f_flat_carry (v_rest) (v_value) (v_arrays)))
| (__nat_9, (M.InstantiationExpr (v_site, v_value))) when __nat_9 >= 1 ->
(let v_rest = (__nat_9 - 1) in
(f_flat_carry (v_rest) (v_value) (v_arrays)))
| (_, _) ->
false)
and (* codegen_ir.bend:260 *)
f_provider_free : M.t_Expr -> bool =
fun v_expression ->
(match v_expression with
| (M.HandleExpr (v_provider, v_body)) ->
false
| _ ->
true)
and (* codegen_ir.bend:267 *)
f_lower : int -> t_Work -> t_Metadata -> Base.set -> bool -> (M.t_Diagnostic, (t_Expr) list) Base.result_ =
fun v_fuel v_work v_projection v_arrays v_isolated ->
(match (v_fuel, v_work) with
| (0, _) ->
(Fail ((M.Diagnostic (s_13, s_1, s_14))))
| (__nat_10, (ExpressionWork ((M.RuntimeInitExpr (v_value))))) when __nat_10 >= 1 ->
(let v_rest = (__nat_10 - 1) in
(f_lower (v_rest) ((ExpressionWork (v_value))) (v_projection) (v_arrays) (v_isolated)))
| (__nat_11, (ExpressionWork ((M.SourceExpr (v_offset, v_annotation, v_value))))) when __nat_11 >= 1 ->
(let v_rest = (__nat_11 - 1) in
(f_lower (v_rest) ((ExpressionWork (v_value))) (v_projection) (v_arrays) (v_isolated)))
| (__nat_12, (ExpressionWork ((M.QualifiedExpr (v_offset, v_annotation, v_predicates, v_value))))) when __nat_12 >= 1 ->
(let v_rest = (__nat_12 - 1) in
(f_lower (v_rest) ((ExpressionWork (v_value))) (v_projection) (v_arrays) (v_isolated)))
| (__nat_13, (ExpressionWork ((M.InstantiationExpr (v_site, v_value))))) when __nat_13 >= 1 ->
(let v_rest = (__nat_13 - 1) in
(f_lower (v_rest) ((ExpressionWork (v_value))) (v_projection) (v_arrays) (v_isolated)))
| (__nat_14, (ExpressionWork ((M.TagExpr (v_offset, v_callee, v_argument))))) when __nat_14 >= 1 ->
(let v_rest = (__nat_14 - 1) in
(f_lower (v_rest) ((ExpressionWork ((M.ApplyExpr (v_callee, v_argument))))) (v_projection) (v_arrays) (v_isolated)))
| (__nat_15, (ExpressionWork ((M.LambdaExpr (v_identity, v_parameter, v_parameter_type, v_result_type, v_body))))) when __nat_15 >= 1 ->
(let v_rest = (__nat_15 - 1) in
(match (f_closure_reference ((f_lambda_get ((f_metadata_lambdas (v_projection))) (v_identity))) (v_identity)) with
| Fail __error -> Fail __error
| Done v_reference ->
(Done ([v_reference]))))
| (__nat_16, (ExpressionWork ((M.ConstructorRefExpr (v_constructor))))) when __nat_16 >= 1 ->
(let v_rest = (__nat_16 - 1) in
(match (f_constructor_reference ((E.f_constructor_get ((f_metadata_constructors (v_projection))) (v_constructor))) (v_constructor)) with
| Fail __error -> Fail __error
| Done v_reference ->
(Done ([v_reference]))))
| (__nat_17, (ExpressionWork ((M.LetExpr (v_name, v_value, v_body))))) when __nat_17 >= 1 ->
(let v_rest = (__nat_17 - 1) in
(let v_nested = (Base.bool_pick ((f_flat_annotation (16384) (v_value))) ((Base.set_add (v_arrays) (v_name))) (v_arrays)) in
(match (f_lower (v_rest) ((ExpressionWork (v_value))) (v_projection) (v_arrays) (v_isolated)) with
| Fail __error -> Fail __error
| Done v_values ->
(match (f_one (v_values)) with
| Fail __error -> Fail __error
| Done v_v ->
(match (f_lower (v_rest) ((ExpressionWork (v_body))) (v_projection) (v_nested) (v_isolated)) with
| Fail __error -> Fail __error
| Done v_bodies ->
(match (f_one (v_bodies)) with
| Fail __error -> Fail __error
| Done v_b ->
(Done ([(LetExpr (v_name, v_v, v_b))]))))))))
| (__nat_18, (ExpressionWork ((M.ForeverExpr (v_state, v_initial, v_body))))) when __nat_18 >= 1 ->
(let v_rest = (__nat_18 - 1) in
(let v_compact = v_isolated in
(match (f_lower (v_rest) ((ExpressionWork (v_initial))) (v_projection) (v_arrays) (v_isolated)) with
| Fail __error -> Fail __error
| Done v_values ->
(match (f_one (v_values)) with
| Fail __error -> Fail __error
| Done v_v ->
(match (f_lower (v_rest) ((ExpressionWork (v_body))) (v_projection) (v_arrays) (v_isolated)) with
| Fail __error -> Fail __error
| Done v_bodies ->
(match (f_one (v_bodies)) with
| Fail __error -> Fail __error
| Done v_b ->
(Done ([(ForeverExpr (v_state, v_v, v_b, v_compact))]))))))))
| (__nat_19, (ExpressionWork (v_expression))) when __nat_19 >= 1 ->
(let v_rest = (__nat_19 - 1) in
(let v_safe = (Base.bool_and (v_isolated) ((f_provider_free (v_expression)))) in
(match (f_lower (v_rest) ((ExpressionsWork ((F.f_children (v_expression)), []))) (v_projection) (v_arrays) (v_safe)) with
| Fail __error -> Fail __error
| Done v_children ->
(match (f_rebuild (v_expression) (v_children)) with
| Fail __error -> Fail __error
| Done v_prepared ->
(Done ([v_prepared]))))))
| (__nat_20, (ExpressionsWork ([], v_reversed))) when __nat_20 >= 1 ->
(let v_rest = (__nat_20 - 1) in
(Done ((Base.list_reverse (v_reversed)))))
| (__nat_21, (ExpressionsWork ((v_head :: v_tail), v_reversed))) when __nat_21 >= 1 ->
(let v_rest = (__nat_21 - 1) in
(match (f_lower (v_rest) ((ExpressionWork (v_head))) (v_projection) (v_arrays) (v_isolated)) with
| Fail __error -> Fail __error
| Done v_first ->
(match (f_one (v_first)) with
| Fail __error -> Fail __error
| Done v_prepared ->
(f_lower (v_rest) ((ExpressionsWork (v_tail, (v_prepared :: v_reversed)))) (v_projection) (v_arrays) (v_isolated))))))
and (* codegen_ir.bend:320 *)
f_prepare_scoped : M.t_Expr -> t_Metadata -> bool -> (M.t_Diagnostic, t_Expr) Base.result_ =
fun v_expression v_projection v_isolated ->
(match (Saturation.f_prepare (v_expression) ((f_metadata_functions (v_projection)))) with
| Fail __error -> Fail __error
| Done v_expanded ->
(match (f_lower ((Base.u32_to_nat (0x00004000l))) ((ExpressionWork (v_expanded))) (v_projection) ((Base.set_new ())) (v_isolated)) with
| Fail __error -> Fail __error
| Done v_result ->
(f_one (v_result))))
and (* codegen_ir.bend:326 *)
f_prepare : M.t_Expr -> t_Metadata -> (M.t_Diagnostic, t_Expr) Base.result_ =
fun v_expression v_projection ->
(f_prepare_scoped (v_expression) (v_projection) (false))
