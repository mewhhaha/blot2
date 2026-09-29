(* Native semantic port of compiler/const_eval.bend.

   Source SHA-256: af72451ecfb8ec752882f86c02436638ae581d6ffacabf4641cc281a43f60660

   Ownership/type arguments are erased; value types are checked by OCaml.

   No Bend interpreter or generated C/JavaScript is linked. *)

open Base

module M = Ox_model

module F = Ox_closures

type 'v t_Binding =
  | Binding of Base.text * 'v
and 'v t_Provider =
  | Provider of M.t_TypeId * 'v
and t_Value =
  | UnitValue
  | U32Value of int32
  | BoolValue of bool
  | FunctionValue of Base.text
  | ConstructorFunctionValue of Base.text
  | DataValue of Base.text * (t_Value) option
  | ClosureValue of int * Base.text * M.t_Expr * ((t_Value) t_Binding) list
  | ReturnValue of int * t_Value
  | F32Value of int32
  | OperationValue of M.t_TypeId
  | ProviderValue of M.t_TypeId * t_Value
  | StateProviderValue of M.t_TypeId * M.t_TypeId * t_Value
  | StateReadValue of int
  | StateWriteValue of int
  | EffectDescriptorValue of M.t_TypeId
  | EffectSetValue of (M.t_TypeId) list
  | MatchValuesValue of (t_Value) list
  | PatternBindingsValue of (((t_Value) t_Binding) list) option
  | ProductValue of (t_Value) list
  | ArrayValue of (t_Value) list
and t_StateCell =
  | StateCell of int * t_Value
and t_Budget =
  | Budget of int * (t_StateCell) list
and t_Evaluation =
  | Evaluation of t_Value * t_Budget
and t_Context =
  | Context of (M.t_Constant) list * (M.t_Function) list * ((t_Value) t_Binding) list * (M.t_DataType) list * ((t_Value) t_Provider) list * (M.t_CheckedFunction) list
and t_Constants =
  | Constants of ((t_Value) t_Binding) list * int
and t_ScopedExpr =
  | ScopedExpr of M.t_Expr * t_Context
and t_Application =
  | BodyApplication of t_ScopedExpr
  | ValueApplication of t_Value
  | OperationApplication of M.t_TypeId * t_Value
  | StateReadApplication of int
  | StateWriteApplication of int * t_Value
and t_PatternWork =
  | PatternValue of M.t_Pattern * t_Value
  | ProductPatterns of (M.t_Pattern) list * (t_Value) list
  | ConstructorPayload of bool * M.t_Pattern * t_Value
and t_PatternProgress =
  | PatternPending of (t_PatternWork) list * ((t_Value) t_Binding) list
  | PatternRejected
and t_EvaluationWork =
  | HandleValue of t_Value * M.t_Expr
  | Expression of M.t_Expr
  | ForBounds of Base.text * t_Value * t_Value * Base.text * t_Value * M.t_Expr
  | ForIterations of Base.text * int32 * Base.text * t_Value * M.t_Expr
  | ForeverIterations of Base.text * t_Value * M.t_Expr
  | GenerateElements of t_Value * int32 * (t_Value) list
  | CollectValues
  | MatchArms of ((M.t_Expr) M.t_MatchArm) list * (t_Value) list
  | MatchSelected of t_Value * M.t_Expr * ((M.t_Expr) M.t_MatchArm) list * (t_Value) list
  | MatchPatterns of int * (M.t_Diagnostic, t_PatternProgress) Base.result_

let s_0 = Base.text_of_utf8 "internal_error"

let s_1 = Base.text_of_utf8 "const evaluator lost a checked local"

let s_2 = Base.text_of_utf8 "const evaluator lost a checked constant"

let s_3 = Base.text_of_utf8 "const evaluator lost a checked function"

let s_4 = Base.text_of_utf8 "const"

let s_5 = Base.text_of_utf8 "checked handler received a non-provider value"

let s_6 = Base.text_of_utf8 "const_runtime_dependency"

let s_7 = Base.text_of_utf8 "a const initializer cannot read a top-level let function"

let s_8 = Base.text_of_utf8 "checked scalar operation received values of the wrong type"

let s_9 = Base.text_of_utf8 "checked unary operation received a value of the wrong type"

let s_10 = Base.text_of_utf8 "checked condition received a non-Bool value"

let s_11 = Base.text_of_utf8 "const evaluator lost a checked constructor"

let s_12 = Base.text_of_utf8 "checked application received a non-function value"

let s_13 = Base.text_of_utf8 "const_effect"

let s_14 = Base.text_of_utf8 "compile-time operation has no enclosing provider"

let s_15 = Base.text_of_utf8 "open_effect_row"

let s_16 = Base.text_of_utf8 "effect descriptors require a closed function effect row"

let s_17 = Base.text_of_utf8 "const evaluator lost checked function effect metadata"

let s_18 = Base.text_of_utf8 "checked effect membership received values of the wrong type"

let s_19 = Base.text_of_utf8 "checked effect count received a non-set value"

let s_20 = Base.text_of_utf8 "checked effect equality received non-descriptor values"

let s_21 = Base.text_of_utf8 "state"

let s_22 = Base.text_of_utf8 "state operation escaped its resolver scope"

let s_23 = Base.text_of_utf8 "resolver scopes completed out of order"

let s_24 = Base.text_of_utf8 "resolver lost its state before completion"

let s_25 = Base.text_of_utf8 "const evaluator failed to resolve an operation application"

let s_26 = Base.text_of_utf8 "product_arity"

let s_27 = Base.text_of_utf8 "a product pattern requires at least two elements"

let s_28 = Base.text_of_utf8 "pattern_complexity"

let s_29 = Base.text_of_utf8 "constant pattern matching exceeds compiler traversal limit"

let s_30 = Base.text_of_utf8 "const evaluator lost an expression collection tail"

let s_31 = Base.text_of_utf8 "const evaluator lost collected product elements"

let s_32 = Base.text_of_utf8 "product_index"

let s_33 = Base.text_of_utf8 "product projection index is outside the element range"

let s_34 = Base.text_of_utf8 "type_mismatch"

let s_35 = Base.text_of_utf8 "product projection requires a product value"

let s_36 = Base.text_of_utf8 "const evaluator lost collected array elements"

let s_37 = Base.text_of_utf8 "const_budget"

let s_38 = Base.text_of_utf8 "compile-time evaluation exhausted its step budget while filling an array"

let s_39 = Base.text_of_utf8 "backend_limit"

let s_40 = Base.text_of_utf8 "array"

let s_41 = Base.text_of_utf8 "array length exceeds the 16 MiB bootstrap arena"

let s_42 = Base.text_of_utf8 "array fill requires a U32 count"

let s_43 = Base.text_of_utf8 "array generation requires a U32 count"

let s_44 = Base.text_of_utf8 "array_bounds"

let s_45 = Base.text_of_utf8 "array index is outside the element range"

let s_46 = Base.text_of_utf8 "array indexing requires an array and a U32 index"

let s_47 = Base.text_of_utf8 "compile-time evaluation exhausted its step budget while copying an array"

let s_48 = Base.text_of_utf8 "array update requires an array and a U32 index"

let s_49 = Base.text_of_utf8 "array_size"

let s_50 = Base.text_of_utf8 "array length exceeds the U32 index range"

let s_51 = Base.text_of_utf8 "array length requires an array value"

let s_52 = Base.text_of_utf8 "a checked return escaped its function or constant"

let s_53 = Base.text_of_utf8 "internal pattern bindings escaped their evaluator scope"

let s_54 = Base.text_of_utf8 "internal match values escaped their evaluator scope"

let s_55 = Base.text_of_utf8 "const evaluator lost collected match values"

let s_56 = Base.text_of_utf8 "const evaluator lost pattern bindings"

let s_57 = Base.text_of_utf8 "value_pattern_type"

let s_58 = Base.text_of_utf8 "value patterns require U32 or Bool"

let s_59 = Base.text_of_utf8 "offset:"

let s_60 = Base.text_of_utf8 "compile-time evaluation exhausted its step budget"

let s_61 = Base.text_of_utf8 "compile-time evaluation exhausted its scope depth"

let s_62 = Base.text_of_utf8 "for"

let s_63 = Base.text_of_utf8 "checked loop lost its U32 bounds"

let s_64 = Base.text_of_utf8 "compile-time evaluation exhausted its step budget in a loop"

let s_65 = Base.text_of_utf8 "for ever"

let s_66 = Base.text_of_utf8 "compile-time evaluation exhausted its step budget in an unbounded loop"

let s_67 = Base.text_of_utf8 "compile-time evaluation exhausted its structural depth in an unbounded loop"

let s_68 = Base.text_of_utf8 "compile-time evaluation exhausted its step budget while generating an array"

let s_69 = Base.text_of_utf8 "checked match has no matching arm"

let s_70 = Base.text_of_utf8 "let"

let s_71 = Base.text_of_utf8 "a const initializer cannot read a top-level let value initialized at module startup"

let s_72 = Base.text_of_utf8 "const_panic"

let s_73 = Base.text_of_utf8 "unspecialized_effect"

let s_74 = Base.text_of_utf8 "effect instance reached evaluation before specialization"

let s_75 = Base.text_of_utf8 "products require at least two elements; Unit is a distinct value"

let s_76 = Base.text_of_utf8 "unresolved_associated"

let s_77 = Base.text_of_utf8 "associated call reached evaluation before specialization"

let s_78 = Base.text_of_utf8 "generic effect operation reached evaluation before specialization"

let rec (* const_eval.bend:79 *)
f_lookup_local_work : ((t_Value) t_Binding) list -> Base.text -> (t_Value) option -> (M.t_Diagnostic, t_Value) Base.result_ =
fun v_locals v_name v_found ->
(match (v_locals, v_found) with
| (_, (Some (v_value))) ->
(Done (v_value))
| ([], None) ->
(Fail ((M.Diagnostic (s_0, v_name, s_1))))
| (((Binding (v_declared, v_value)) :: v_tail), None) ->
(f_lookup_local_work (v_tail) (v_name) ((Base.bool_pick ((M.f_name_equal (v_declared) (v_name))) ((Some (v_value))) (None)))))
and (* const_eval.bend:88 *)
f_lookup_local : ((t_Value) t_Binding) list -> Base.text -> (M.t_Diagnostic, t_Value) Base.result_ =
fun v_locals v_name ->
(f_lookup_local_work (v_locals) (v_name) (None))
and (* const_eval.bend:93 *)
f_capture_environment : (Base.text) list -> ((t_Value) t_Binding) list -> (M.t_Diagnostic, ((t_Value) t_Binding) list) Base.result_ =
fun v_names v_locals ->
(match v_names with
| [] ->
(Done ([]))
| (v_name :: v_tail) ->
(match (f_lookup_local (v_locals) (v_name)) with
| Fail __error -> Fail __error
| Done v_value ->
(match (f_capture_environment (v_tail) (v_locals)) with
| Fail __error -> Fail __error
| Done v_captured ->
(Done (((Binding (v_name, v_value)) :: v_captured))))))
and (* const_eval.bend:103 *)
f_lookup_constant_work : (M.t_Constant) list -> Base.text -> (M.t_Expr) option -> (M.t_Diagnostic, M.t_Expr) Base.result_ =
fun v_constants v_name v_found ->
(match (v_constants, v_found) with
| (_, (Some (v_value))) ->
(Done (v_value))
| ([], None) ->
(Fail ((M.Diagnostic (s_0, v_name, s_2))))
| (((M.Constant (v_declared, v_exported, v_annotation, v_value)) :: v_tail), None) ->
(f_lookup_constant_work (v_tail) (v_name) ((Base.bool_pick ((M.f_name_equal (v_declared) (v_name))) ((Some (v_value))) (None)))))
and (* const_eval.bend:112 *)
f_lookup_constant : (M.t_Constant) list -> Base.text -> (M.t_Diagnostic, M.t_Expr) Base.result_ =
fun v_constants v_name ->
(f_lookup_constant_work (v_constants) (v_name) (None))
and (* const_eval.bend:115 *)
f_lookup_function_work : (M.t_Function) list -> Base.text -> (M.t_Function) option -> (M.t_Diagnostic, M.t_Function) Base.result_ =
fun v_functions v_name v_found ->
(match (v_functions, v_found) with
| (_, (Some (v_value))) ->
(Done (v_value))
| ([], None) ->
(Fail ((M.Diagnostic (s_0, v_name, s_3))))
| (((M.Function (v_declared, v_exported, v_parameter, v_parameter_type, v_result_type, v_body)) :: v_tail), None) ->
(f_lookup_function_work (v_tail) (v_name) ((Base.bool_pick ((M.f_name_equal (v_declared) (v_name))) ((Some ((M.Function (v_declared, v_exported, v_parameter, v_parameter_type, v_result_type, v_body))))) (None)))))
and (* const_eval.bend:124 *)
f_lookup_function : (M.t_Function) list -> Base.text -> (M.t_Diagnostic, M.t_Function) Base.result_ =
fun v_functions v_name ->
(f_lookup_function_work (v_functions) (v_name) (None))
and (* const_eval.bend:127 *)
f_eval_value : t_Evaluation -> t_Value =
fun v_evaluation ->
(let (Evaluation (v_value, v_remaining)) = v_evaluation in
v_value)
and (* const_eval.bend:131 *)
f_eval_remaining : t_Evaluation -> int =
fun v_evaluation ->
(let (Evaluation (v_value, (Budget (v_remaining, v_cells)))) = v_evaluation in
v_remaining)
and (* const_eval.bend:135 *)
f_spend_budget : t_Budget -> t_Budget =
fun v_budget ->
(let (Budget (v_remaining, v_cells)) = v_budget in
(Budget ((Base.nat_sub (v_remaining) (1)), v_cells)))
and (* const_eval.bend:139 *)
f_eval_budget : t_Evaluation -> t_Budget =
fun v_evaluation ->
(let (Evaluation (v_value, v_budget)) = v_evaluation in
v_budget)
and (* const_eval.bend:143 *)
f_context_locals : t_Context -> ((t_Value) t_Binding) list =
fun v_context ->
(let (Context (v_constants, v_functions, v_locals, v_data_types, v_providers, v_checked_functions)) = v_context in
v_locals)
and (* const_eval.bend:147 *)
f_context_constants : t_Context -> (M.t_Constant) list =
fun v_context ->
(let (Context (v_constants, v_functions, v_locals, v_data_types, v_providers, v_checked_functions)) = v_context in
v_constants)
and (* const_eval.bend:151 *)
f_context_functions : t_Context -> (M.t_Function) list =
fun v_context ->
(let (Context (v_constants, v_functions, v_locals, v_data_types, v_providers, v_checked_functions)) = v_context in
v_functions)
and (* const_eval.bend:155 *)
f_context_data_types : t_Context -> (M.t_DataType) list =
fun v_context ->
(let (Context (v_constants, v_functions, v_locals, v_data_types, v_providers, v_checked_functions)) = v_context in
v_data_types)
and (* const_eval.bend:159 *)
f_context_providers : t_Context -> ((t_Value) t_Provider) list =
fun v_context ->
(let (Context (v_constants, v_functions, v_locals, v_data_types, v_providers, v_checked_functions)) = v_context in
v_providers)
and (* const_eval.bend:163 *)
f_context_checked_functions : t_Context -> (M.t_CheckedFunction) list =
fun v_context ->
(let (Context (v_constants, v_functions, v_locals, v_data_types, v_providers, v_checked_functions)) = v_context in
v_checked_functions)
and (* const_eval.bend:167 *)
f_without_locals : t_Context -> t_Context =
fun v_context ->
(let (Context (v_constants, v_functions, v_locals, v_data_types, v_providers, v_checked_functions)) = v_context in
(Context (v_constants, v_functions, [], v_data_types, v_providers, v_checked_functions)))
and (* const_eval.bend:171 *)
f_with_locals : t_Context -> ((t_Value) t_Binding) list -> t_Context =
fun v_context v_locals ->
(let (Context (v_constants, v_functions, v_previous, v_data_types, v_providers, v_checked_functions)) = v_context in
(Context (v_constants, v_functions, v_locals, v_data_types, v_providers, v_checked_functions)))
and (* const_eval.bend:175 *)
f_with_local : t_Context -> Base.text -> t_Value -> t_Context =
fun v_context v_name v_value ->
(let (Context (v_constants, v_functions, v_locals, v_data_types, v_providers, v_checked_functions)) = v_context in
(Context (v_constants, v_functions, ((Binding (v_name, v_value)) :: v_locals), v_data_types, v_providers, v_checked_functions)))
and (* const_eval.bend:179 *)
f_with_bindings : t_Context -> ((t_Value) t_Binding) list -> t_Context =
fun v_context v_bindings ->
(let (Context (v_constants, v_functions, v_locals, v_data_types, v_providers, v_checked_functions)) = v_context in
(Context (v_constants, v_functions, (Base.list_append (v_bindings) (v_locals)), v_data_types, v_providers, v_checked_functions)))
and (* const_eval.bend:183 *)
f_with_providers : t_Context -> ((t_Value) t_Provider) list -> t_Context =
fun v_context v_providers ->
(let (Context (v_constants, v_functions, v_locals, v_data_types, v_previous, v_checked_functions)) = v_context in
(Context (v_constants, v_functions, v_locals, v_data_types, v_providers, v_checked_functions)))
and (* const_eval.bend:187 *)
f_with_provider : t_Value -> t_Context -> (M.t_Diagnostic, t_Context) Base.result_ =
fun v_value v_context ->
(match v_value with
| (ProviderValue (v_identity, v_implementation)) ->
(let (Context (v_constants, v_functions, v_locals, v_data_types, v_providers, v_checked_functions)) = v_context in
(Done ((Context (v_constants, v_functions, v_locals, v_data_types, ((Provider (v_identity, v_implementation)) :: v_providers), v_checked_functions)))))
| _ ->
(Fail ((M.Diagnostic (s_0, s_4, s_5)))))
and (* const_eval.bend:195 *)
f_function_body : M.t_Function -> M.t_Expr =
fun v_function ->
(let (M.Function (v_name, v_exported, v_parameter, v_param_ty, v_result_ty, v_body)) = v_function in
v_body)
and (* const_eval.bend:199 *)
f_function_value_allowed : M.t_Expr -> Base.text -> t_Budget -> (M.t_Diagnostic, t_Evaluation) Base.result_ =
fun v_body v_name v_remaining ->
(match v_body with
| (M.RuntimeInitExpr (v_value)) ->
(Fail ((M.Diagnostic (s_6, v_name, s_7))))
| _ ->
(Done ((Evaluation ((FunctionValue (v_name)), v_remaining)))))
and (* const_eval.bend:206 *)
f_function_context : M.t_Function -> t_Value -> t_Context -> t_Context =
fun v_function v_argument v_context ->
(let (M.Function (v_name, v_exported, v_parameter, v_param_ty, v_result_ty, v_body)) = v_function in
(f_with_local ((f_without_locals (v_context))) (v_parameter) (v_argument)))
and (* const_eval.bend:210 *)
f_scalar : M.t_ScalarOp -> t_Value -> t_Value -> t_Budget -> (M.t_Diagnostic, t_Evaluation) Base.result_ =
fun v_operator v_left v_right v_remaining ->
(match (v_operator, v_left, v_right) with
| (M.Add, (U32Value (v_a)), (U32Value (v_b))) ->
(Done ((Evaluation ((U32Value ((Base.u32_add (v_a) (v_b)))), v_remaining))))
| (M.Subtract, (U32Value (v_a)), (U32Value (v_b))) ->
(Done ((Evaluation ((U32Value ((Base.u32_sub (v_a) (v_b)))), v_remaining))))
| (M.Multiply, (U32Value (v_a)), (U32Value (v_b))) ->
(Done ((Evaluation ((U32Value ((Base.u32_mul (v_a) (v_b)))), v_remaining))))
| (M.Equal, (U32Value (v_a)), (U32Value (v_b))) ->
(Done ((Evaluation ((BoolValue ((Base.u32_is_eq (v_a) (v_b)))), v_remaining))))
| (M.LessThan, (U32Value (v_a)), (U32Value (v_b))) ->
(Done ((Evaluation ((BoolValue ((Base.u32_is_lt (v_a) (v_b)))), v_remaining))))
| (M.F32Add, (F32Value (v_a)), (F32Value (v_b))) ->
(Done ((Evaluation ((F32Value ((Base.f32_add (v_a) (v_b)))), v_remaining))))
| (M.F32Subtract, (F32Value (v_a)), (F32Value (v_b))) ->
(Done ((Evaluation ((F32Value ((Base.f32_sub (v_a) (v_b)))), v_remaining))))
| (M.F32Multiply, (F32Value (v_a)), (F32Value (v_b))) ->
(Done ((Evaluation ((F32Value ((Base.f32_mul (v_a) (v_b)))), v_remaining))))
| (M.F32Divide, (F32Value (v_a)), (F32Value (v_b))) ->
(Done ((Evaluation ((F32Value ((Base.f32_div (v_a) (v_b)))), v_remaining))))
| (M.F32Equal, (F32Value (v_a)), (F32Value (v_b))) ->
(Done ((Evaluation ((BoolValue ((Base.f32_is_eq (v_a) (v_b)))), v_remaining))))
| (M.F32NotEqual, (F32Value (v_a)), (F32Value (v_b))) ->
(Done ((Evaluation ((BoolValue ((Base.f32_is_ne (v_a) (v_b)))), v_remaining))))
| (M.F32LessThan, (F32Value (v_a)), (F32Value (v_b))) ->
(Done ((Evaluation ((BoolValue ((Base.f32_is_lt (v_a) (v_b)))), v_remaining))))
| (M.F32LessEqual, (F32Value (v_a)), (F32Value (v_b))) ->
(Done ((Evaluation ((BoolValue ((Base.f32_is_le (v_a) (v_b)))), v_remaining))))
| (M.F32GreaterThan, (F32Value (v_a)), (F32Value (v_b))) ->
(Done ((Evaluation ((BoolValue ((Base.f32_is_gt (v_a) (v_b)))), v_remaining))))
| (M.F32GreaterEqual, (F32Value (v_a)), (F32Value (v_b))) ->
(Done ((Evaluation ((BoolValue ((Base.f32_is_ge (v_a) (v_b)))), v_remaining))))
| (_, _, _) ->
(Fail ((M.Diagnostic (s_0, s_4, s_8)))))
and (* const_eval.bend:247 *)
f_f32_to_u32_saturating : int32 -> int32 =
fun v_value ->
(Base.bool_pick ((Base.f32_is_ge (v_value) (0x4f800000l))) (0xffffffffl) ((Base.f32_to_u32 (v_value))))
and (* const_eval.bend:250 *)
f_unary : M.t_UnaryOp -> t_Value -> t_Budget -> (M.t_Diagnostic, t_Evaluation) Base.result_ =
fun v_operator v_value v_remaining ->
(match (v_operator, v_value) with
| (M.F32Negate, (F32Value (v_number))) ->
(Done ((Evaluation ((F32Value ((Base.f32_neg (v_number)))), v_remaining))))
| (M.F32Absolute, (F32Value (v_number))) ->
(Done ((Evaluation ((F32Value ((Base.f32_abs (v_number)))), v_remaining))))
| (M.F32SquareRoot, (F32Value (v_number))) ->
(Done ((Evaluation ((F32Value ((Base.f32_sqrt (v_number)))), v_remaining))))
| (M.F32Floor, (F32Value (v_number))) ->
(Done ((Evaluation ((F32Value ((Base.f32_floor (v_number)))), v_remaining))))
| (M.F32Ceiling, (F32Value (v_number))) ->
(Done ((Evaluation ((F32Value ((Base.f32_ceil (v_number)))), v_remaining))))
| (M.F32Truncate, (F32Value (v_number))) ->
(Done ((Evaluation ((F32Value ((Base.f32_trunc (v_number)))), v_remaining))))
| (M.U32ToF32, (U32Value (v_number))) ->
(Done ((Evaluation ((F32Value ((Base.u32_to_f32 (v_number)))), v_remaining))))
| (M.F32ToU32, (F32Value (v_number))) ->
(Done ((Evaluation ((U32Value ((f_f32_to_u32_saturating (v_number)))), v_remaining))))
| (_, _) ->
(Fail ((M.Diagnostic (s_0, s_4, s_9)))))
and (* const_eval.bend:271 *)
f_branch : t_Value -> M.t_Expr -> M.t_Expr -> (M.t_Diagnostic, M.t_Expr) Base.result_ =
fun v_condition v_consequent v_alternative ->
(match v_condition with
| (BoolValue (v_test)) ->
(Done ((Base.bool_pick (v_test) (v_consequent) (v_alternative))))
| _ ->
(Fail ((M.Diagnostic (s_0, s_4, s_10)))))
and (* const_eval.bend:278 *)
f_constructor_in : (M.t_Constructor) list -> Base.text -> (M.t_Constructor) option =
fun v_constructors v_name ->
(match v_constructors with
| [] ->
None
| ((M.Constructor (v_found, v_payload, v_fields)) :: v_tail) ->
(Base.bool_pick ((M.f_name_equal (v_found) (v_name))) ((Some ((M.Constructor (v_found, v_payload, v_fields))))) ((f_constructor_in (v_tail) (v_name)))))
and (* const_eval.bend:285 *)
f_lookup_constructor : (M.t_DataType) list -> Base.text -> (M.t_Constructor) option =
fun v_data_types v_name ->
(match v_data_types with
| [] ->
None
| ((M.DataType (v_identity, v_parameters, v_constructors)) :: v_tail) ->
(Base.maybe_or ((f_constructor_in (v_constructors) (v_name))) ((f_lookup_constructor (v_tail) (v_name)))))
and (* const_eval.bend:292 *)
f_constructor_value : (M.t_Constructor) option -> Base.text -> (M.t_Diagnostic, t_Value) Base.result_ =
fun v_constructor v_name ->
(match v_constructor with
| None ->
(Fail ((M.Diagnostic (s_0, v_name, s_11))))
| (Some ((M.Constructor (v_found, None, v_fields)))) ->
(Done ((DataValue (v_found, None))))
| (Some ((M.Constructor (v_found, (Some (v_payload)), v_fields)))) ->
(Done ((ConstructorFunctionValue (v_found)))))
and (* const_eval.bend:301 *)
f_application : t_Value -> t_Value -> t_Context -> (M.t_Diagnostic, t_Application) Base.result_ =
fun v_callee v_argument v_context ->
(match v_callee with
| (FunctionValue (v_name)) ->
(match (f_lookup_function ((f_context_functions (v_context))) (v_name)) with
| Fail __error -> Fail __error
| Done v_function ->
(Done ((BodyApplication ((ScopedExpr ((f_function_body (v_function)), (f_function_context (v_function) (v_argument) (v_context)))))))))
| (ClosureValue (v_identity, v_parameter, v_body, v_environment)) ->
(Done ((BodyApplication ((ScopedExpr (v_body, (f_with_local ((f_with_locals (v_context) (v_environment))) (v_parameter) (v_argument))))))))
| (ConstructorFunctionValue (v_constructor)) ->
(Done ((ValueApplication ((DataValue (v_constructor, (Some (v_argument))))))))
| (OperationValue (v_identity)) ->
(Done ((OperationApplication (v_identity, v_argument))))
| (StateReadValue (v_slot)) ->
(Done ((StateReadApplication (v_slot))))
| (StateWriteValue (v_slot)) ->
(Done ((StateWriteApplication (v_slot, v_argument))))
| _ ->
(Fail ((M.Diagnostic (s_0, s_4, s_12)))))
and (* const_eval.bend:320 *)
f_provider_application : bool -> M.t_TypeId -> t_Value -> t_Value -> t_Context -> (M.t_Diagnostic, t_Application) Base.result_ =
fun v_matches v_identity v_implementation v_argument v_context ->
(match v_matches with
| true ->
(f_application (v_implementation) (v_argument) (v_context))
| false ->
(Done ((OperationApplication (v_identity, v_argument)))))
and (* const_eval.bend:330 *)
f_resolve_application : ((t_Value) t_Provider) list -> t_Application -> t_Context -> (M.t_Diagnostic, t_Application) Base.result_ =
fun v_providers v_call v_context ->
(match (v_providers, v_call) with
| (_, (BodyApplication (v_scope))) ->
(Done ((BodyApplication (v_scope))))
| (_, (ValueApplication (v_value))) ->
(Done ((ValueApplication (v_value))))
| (_, (StateReadApplication (v_slot))) ->
(Done ((StateReadApplication (v_slot))))
| (_, (StateWriteApplication (v_slot, v_value))) ->
(Done ((StateWriteApplication (v_slot, v_value))))
| ([], (OperationApplication (v_identity, v_argument))) ->
(Fail ((M.Diagnostic (s_13, (M.f_type_id_show (v_identity)), s_14))))
| (((Provider (v_found, v_implementation)) :: v_tail), (OperationApplication (v_identity, v_argument))) ->
(let v_scope = (f_with_providers (v_context) (v_tail)) in
(match (f_provider_application ((M.f_type_id_equal (v_found) (v_identity))) (v_identity) (v_implementation) (v_argument) (v_scope)) with
| Fail __error -> Fail __error
| Done v_next ->
(f_resolve_application (v_tail) (v_next) (v_scope)))))
and (* const_eval.bend:348 *)
f_operation_contains : (M.t_TypeId) list -> M.t_TypeId -> bool =
fun v_operations v_identity ->
(match v_operations with
| [] ->
false
| (v_found :: v_tail) ->
(Base.bool_or ((M.f_type_id_equal (v_found) (v_identity))) ((f_operation_contains (v_tail) (v_identity)))))
and (* const_eval.bend:355 *)
f_unique_operations : (M.t_TypeId) list -> (M.t_TypeId) list -> (M.t_TypeId) list =
fun v_operations v_reversed ->
(match v_operations with
| [] ->
(Base.list_reverse (v_reversed))
| (v_identity :: v_tail) ->
(f_unique_operations (v_tail) ((Base.bool_pick ((f_operation_contains (v_reversed) (v_identity))) (v_reversed) ((v_identity :: v_reversed))))))
and (* const_eval.bend:362 *)
f_describe_row : M.t_EffectRow -> Base.text -> (M.t_Diagnostic, t_Value) Base.result_ =
fun v_row v_name ->
(match v_row with
| (M.EffectRow (v_operations, M.ClosedRow)) ->
(Done ((EffectSetValue ((f_unique_operations (v_operations) ([]))))))
| _ ->
(Fail ((M.Diagnostic (s_15, v_name, s_16)))))
and (* const_eval.bend:369 *)
f_describe_function : bool -> M.t_Signature -> Base.text -> (unit -> (M.t_Diagnostic, t_Value) Base.result_) -> (M.t_Diagnostic, t_Value) Base.result_ =
fun v_found v_signature v_name v_fallback ->
(match v_found with
| false ->
(v_fallback (()))
| true ->
(let (M.Signature (v_function_name, v_parameter, v_result, v_variables, v_row)) = v_signature in
(f_describe_row (v_row) (v_name))))
and (* const_eval.bend:377 *)
f_function_effects : (M.t_CheckedFunction) list -> Base.text -> (M.t_Diagnostic, t_Value) Base.result_ =
fun v_functions v_name ->
(match v_functions with
| [] ->
(Fail ((M.Diagnostic (s_0, v_name, s_17))))
| ((M.CheckedFunction ((M.Function (v_found, v_exported, v_parameter, v_parameter_type, v_result_type, v_body)), v_signature, v_effects)) :: v_tail) ->
(f_describe_function ((M.f_name_equal (v_found) (v_name))) (v_signature) (v_name) ((fun v_ignored ->
(f_function_effects (v_tail) (v_name))))))
and (* const_eval.bend:384 *)
f_effect_has : t_Value -> t_Value -> t_Budget -> (M.t_Diagnostic, t_Evaluation) Base.result_ =
fun v_set v_operation v_remaining ->
(match (v_set, v_operation) with
| ((EffectSetValue (v_operations)), (EffectDescriptorValue (v_identity))) ->
(Done ((Evaluation ((BoolValue ((f_operation_contains (v_operations) (v_identity)))), v_remaining))))
| (_, _) ->
(Fail ((M.Diagnostic (s_0, s_4, s_18)))))
and (* const_eval.bend:391 *)
f_effect_count : t_Value -> t_Budget -> (M.t_Diagnostic, t_Evaluation) Base.result_ =
fun v_set v_remaining ->
(match v_set with
| (EffectSetValue (v_operations)) ->
(Done ((Evaluation ((U32Value ((Base.u32_from_nat ((Base.list_length (v_operations)))))), v_remaining))))
| _ ->
(Fail ((M.Diagnostic (s_0, s_4, s_19)))))
and (* const_eval.bend:398 *)
f_effect_same : t_Value -> t_Value -> t_Budget -> (M.t_Diagnostic, t_Evaluation) Base.result_ =
fun v_left v_right v_remaining ->
(match (v_left, v_right) with
| ((EffectDescriptorValue (v_a)), (EffectDescriptorValue (v_b))) ->
(Done ((Evaluation ((BoolValue ((M.f_type_id_equal (v_a) (v_b)))), v_remaining))))
| (_, _) ->
(Fail ((M.Diagnostic (s_0, s_4, s_20)))))
and (* const_eval.bend:408 *)
f_continue_value : t_Evaluation -> (t_Value -> (t_Budget -> (M.t_Diagnostic, t_Evaluation) Base.result_)) -> (M.t_Diagnostic, t_Evaluation) Base.result_ =
fun v_evaluation v_continuation ->
(match v_evaluation with
| (Evaluation ((ReturnValue (v_label, v_value)), v_remaining)) ->
(Done ((Evaluation ((ReturnValue (v_label, v_value)), v_remaining))))
| (Evaluation (v_value, v_remaining)) ->
(v_continuation (v_value) (v_remaining)))
and (* const_eval.bend:415 *)
f_state_cell : (t_StateCell) list -> int -> (M.t_Diagnostic, t_Value) Base.result_ =
fun v_cells v_wanted ->
(match v_cells with
| [] ->
(Fail ((M.Diagnostic (s_0, s_21, s_22))))
| ((StateCell (v_slot, v_value)) :: v_tail) ->
(Base.bool_pick ((Base.nat_is_eq (v_slot) (v_wanted))) ((Done (v_value))) ((f_state_cell (v_tail) (v_wanted)))))
and (* const_eval.bend:422 *)
f_replace_state : (t_StateCell) list -> int -> t_Value -> (M.t_Diagnostic, (t_StateCell) list) Base.result_ =
fun v_cells v_wanted v_replacement ->
(match v_cells with
| [] ->
(Fail ((M.Diagnostic (s_0, s_21, s_22))))
| ((StateCell (v_slot, v_value)) :: v_tail) ->
(Base.bool_pick ((Base.nat_is_eq (v_slot) (v_wanted))) ((Done (((StateCell (v_slot, v_replacement)) :: v_tail)))) ((match (f_replace_state (v_tail) (v_wanted) (v_replacement)) with
| Fail __error -> Fail __error
| Done v_next ->
(Done (((StateCell (v_slot, v_value)) :: v_next)))))))
and (* const_eval.bend:432 *)
f_read_state : int -> t_Budget -> (M.t_Diagnostic, t_Evaluation) Base.result_ =
fun v_slot v_budget ->
(let (Budget (v_remaining, v_cells)) = v_budget in
(match (f_state_cell (v_cells) (v_slot)) with
| Fail __error -> Fail __error
| Done v_value ->
(Done ((Evaluation (v_value, v_budget))))))
and (* const_eval.bend:438 *)
f_write_state : int -> t_Value -> t_Budget -> (M.t_Diagnostic, t_Evaluation) Base.result_ =
fun v_slot v_value v_budget ->
(let (Budget (v_remaining, v_cells)) = v_budget in
(match (f_replace_state (v_cells) (v_slot) (v_value)) with
| Fail __error -> Fail __error
| Done v_next ->
(Done ((Evaluation (UnitValue, (Budget (v_remaining, v_next))))))))
and (* const_eval.bend:444 *)
f_state_scope : M.t_TypeId -> M.t_TypeId -> int -> t_Context -> t_Context =
fun v_read v_write v_slot v_context ->
(let (Context (v_constants, v_functions, v_locals, v_data_types, v_providers, v_checked_functions)) = v_context in
(Context (v_constants, v_functions, v_locals, v_data_types, ((Provider (v_read, (StateReadValue (v_slot)))) :: ((Provider (v_write, (StateWriteValue (v_slot)))) :: v_providers)), v_checked_functions)))
and (* const_eval.bend:448 *)
f_state_result : t_Value -> t_Value -> t_Value =
fun v_state v_result ->
(match v_result with
| (ReturnValue (v_label, v_value)) ->
(ReturnValue (v_label, v_value))
| v_value ->
(ProductValue ([v_state; v_value])))
and (* const_eval.bend:455 *)
f_finish_state_scope : t_Evaluation -> int -> (M.t_Diagnostic, t_Evaluation) Base.result_ =
fun v_evaluation v_wanted ->
(match v_evaluation with
| (Evaluation (v_result, (Budget (v_remaining, ((StateCell (v_slot, v_state)) :: v_cells))))) ->
(Base.bool_pick ((Base.nat_is_eq (v_slot) (v_wanted))) ((Done ((Evaluation ((f_state_result (v_state) (v_result)), (Budget (v_remaining, v_cells))))))) ((Fail ((M.Diagnostic (s_0, s_21, s_23))))))
| _ ->
(Fail ((M.Diagnostic (s_0, s_21, s_24)))))
and (* const_eval.bend:462 *)
f_complete_application : t_Application -> t_Budget -> (M.t_Expr -> (t_Context -> (t_Budget -> (M.t_Diagnostic, t_Evaluation) Base.result_))) -> (M.t_Diagnostic, t_Evaluation) Base.result_ =
fun v_application v_remaining v_continuation ->
(match v_application with
| (ValueApplication (v_value)) ->
(Done ((Evaluation (v_value, v_remaining))))
| (BodyApplication ((ScopedExpr (v_expression, v_context)))) ->
(v_continuation (v_expression) (v_context) (v_remaining))
| (OperationApplication (v_identity, v_argument)) ->
(Fail ((M.Diagnostic (s_0, (M.f_type_id_show (v_identity)), s_25))))
| (StateReadApplication (v_slot)) ->
(f_read_state (v_slot) (v_remaining))
| (StateWriteApplication (v_slot, v_value)) ->
(f_write_state (v_slot) (v_value) (v_remaining)))
and (* const_eval.bend:475 *)
f_complete_scope : t_ScopedExpr -> t_Budget -> (M.t_Expr -> (t_Context -> (t_Budget -> (M.t_Diagnostic, t_Evaluation) Base.result_))) -> (M.t_Diagnostic, t_Evaluation) Base.result_ =
fun v_scope v_remaining v_continuation ->
(let (ScopedExpr (v_expression, v_context)) = v_scope in
(v_continuation (v_expression) (v_context) (v_remaining)))
and (* const_eval.bend:479 *)
f_pattern_step : t_PatternWork -> (t_PatternWork) list -> ((t_Value) t_Binding) list -> (M.t_Diagnostic, t_PatternProgress) Base.result_ =
fun v_work v_pending v_reversed ->
(match v_work with
| (PatternValue (M.WildcardPattern, v_value)) ->
(Done ((PatternPending (v_pending, v_reversed))))
| (PatternValue ((M.BindingPattern (v_name)), v_value)) ->
(Done ((PatternPending (v_pending, ((Binding (v_name, v_value)) :: v_reversed)))))
| (PatternValue (M.UnitPattern, UnitValue)) ->
(Done ((PatternPending (v_pending, v_reversed))))
| (PatternValue ((M.U32Pattern (v_expected)), (U32Value (v_actual)))) ->
(Done ((Base.bool_pick ((Base.u32_is_eq (v_expected) (v_actual))) ((PatternPending (v_pending, v_reversed))) (PatternRejected))))
| (PatternValue ((M.BoolPattern (v_expected)), (BoolValue (v_actual)))) ->
(Done ((Base.bool_pick ((Base.bool_not ((Base.bool_xor (v_expected) (v_actual))))) ((PatternPending (v_pending, v_reversed))) (PatternRejected))))
| (PatternValue ((M.ConstructorPattern (v_constructor, None)), (DataValue (v_found, None)))) ->
(Done ((Base.bool_pick ((M.f_name_equal (v_constructor) (v_found))) ((PatternPending (v_pending, v_reversed))) (PatternRejected))))
| (PatternValue ((M.ConstructorPattern (v_constructor, (Some (v_nested)))), (DataValue (v_found, (Some (v_payload)))))) ->
(Done ((PatternPending (((ConstructorPayload ((M.f_name_equal (v_constructor) (v_found)), v_nested, v_payload)) :: v_pending), v_reversed))))
| (PatternValue ((M.ProductPattern ((v_first :: (v_second :: v_tail)))), (ProductValue (v_elements)))) ->
(Done ((PatternPending (((ProductPatterns ((v_first :: (v_second :: v_tail)), v_elements)) :: v_pending), v_reversed))))
| (PatternValue ((M.ProductPattern ([])), v_value)) ->
(Fail ((M.Diagnostic (s_26, s_4, s_27))))
| (PatternValue ((M.ProductPattern ((v_head :: []))), v_value)) ->
(Fail ((M.Diagnostic (s_26, s_4, s_27))))
| (PatternValue (v_pattern, v_value)) ->
(Done (PatternRejected))
| (ConstructorPayload (false, v_pattern, v_value)) ->
(Done (PatternRejected))
| (ConstructorPayload (true, v_pattern, v_value)) ->
(Done ((PatternPending (((PatternValue (v_pattern, v_value)) :: v_pending), v_reversed))))
| (ProductPatterns ([], [])) ->
(Done ((PatternPending (v_pending, v_reversed))))
| (ProductPatterns ((v_head :: v_tail), (v_value :: v_rest))) ->
(Done ((PatternPending (((PatternValue (v_head, v_value)) :: ((ProductPatterns (v_tail, v_rest)) :: v_pending)), v_reversed))))
| (ProductPatterns (v_patterns, v_values)) ->
(Done (PatternRejected)))
and (* const_eval.bend:516 *)
f_match_pattern_queue : int -> (M.t_Diagnostic, t_PatternProgress) Base.result_ -> (M.t_Diagnostic, (((t_Value) t_Binding) list) option) Base.result_ =
fun v_fuel v_progress ->
(match (v_fuel, v_progress) with
| (_, (Fail (v_error))) ->
(Fail (v_error))
| (_, (Done (PatternRejected))) ->
(Done (None))
| (_, (Done ((PatternPending ([], v_reversed))))) ->
(Done ((Some ((Base.list_reverse (v_reversed))))))
| (0, (Done ((PatternPending (v_pending, v_reversed))))) ->
(Fail ((M.Diagnostic (s_28, s_4, s_29))))
| (__nat_1, (Done ((PatternPending ((v_work :: v_pending), v_reversed))))) when __nat_1 >= 1 ->
(let v_remaining = (__nat_1 - 1) in
(f_match_pattern_queue (v_remaining) ((f_pattern_step (v_work) (v_pending) (v_reversed))))))
and (* const_eval.bend:529 *)
f_match_pattern_work : int -> t_PatternWork -> (M.t_Diagnostic, (((t_Value) t_Binding) list) option) Base.result_ =
fun v_fuel v_work ->
(f_match_pattern_queue (v_fuel) ((Done ((PatternPending ([v_work], []))))))
and (* const_eval.bend:532 *)
f_match_pattern : M.t_Pattern -> t_Value -> (M.t_Diagnostic, (((t_Value) t_Binding) list) option) Base.result_ =
fun v_pattern v_value ->
(f_match_pattern_work ((Base.u32_to_nat (0x00010000l))) ((PatternValue (v_pattern, v_value))))
and (* const_eval.bend:535 *)
f_prepend_collected_value : t_Value -> t_Value -> t_Budget -> (M.t_Diagnostic, t_Evaluation) Base.result_ =
fun v_value v_collected v_remaining ->
(match v_collected with
| (MatchValuesValue (v_values)) ->
(Done ((Evaluation ((MatchValuesValue ((v_value :: v_values))), v_remaining))))
| _ ->
(Fail ((M.Diagnostic (s_0, s_4, s_30)))))
and (* const_eval.bend:542 *)
f_product_value : t_Value -> t_Budget -> (M.t_Diagnostic, t_Evaluation) Base.result_ =
fun v_collected v_remaining ->
(match v_collected with
| (MatchValuesValue (v_elements)) ->
(Done ((Evaluation ((ProductValue (v_elements)), v_remaining))))
| _ ->
(Fail ((M.Diagnostic (s_0, s_4, s_31)))))
and (* const_eval.bend:549 *)
f_project_elements : (t_Value) list -> int -> t_Budget -> (M.t_Diagnostic, t_Evaluation) Base.result_ =
fun v_elements v_index v_remaining ->
(match (v_elements, v_index) with
| ([], _) ->
(Fail ((M.Diagnostic (s_32, s_4, s_33))))
| ((v_head :: v_tail), 0) ->
(Done ((Evaluation (v_head, v_remaining))))
| ((v_head :: v_tail), __nat_2) when __nat_2 >= 1 ->
(let v_rest = (__nat_2 - 1) in
(f_project_elements (v_tail) (v_rest) (v_remaining))))
and (* const_eval.bend:558 *)
f_project : t_Value -> int -> t_Budget -> (M.t_Diagnostic, t_Evaluation) Base.result_ =
fun v_value v_index v_remaining ->
(match v_value with
| (ProductValue (v_elements)) ->
(f_project_elements (v_elements) (v_index) (v_remaining))
| _ ->
(Fail ((M.Diagnostic (s_34, s_4, s_35)))))
and (* const_eval.bend:565 *)
f_array_value : t_Value -> t_Budget -> (M.t_Diagnostic, t_Evaluation) Base.result_ =
fun v_collected v_remaining ->
(match v_collected with
| (MatchValuesValue (v_elements)) ->
(Done ((Evaluation ((ArrayValue (v_elements)), v_remaining))))
| _ ->
(Fail ((M.Diagnostic (s_0, s_4, s_36)))))
and (* const_eval.bend:574 *)
f_array_fill_elements : int -> t_Value -> (t_Value) list -> t_Budget -> (M.t_Diagnostic, t_Evaluation) Base.result_ =
fun v_count v_value v_elements v_steps ->
(match (v_count, v_steps) with
| (0, _) ->
(Done ((Evaluation ((ArrayValue (v_elements)), v_steps))))
| (__nat_3, (Budget (0, v_cells))) when __nat_3 >= 1 ->
(let v_rest = (__nat_3 - 1) in
(Fail ((M.Diagnostic (s_37, s_4, s_38)))))
| (__nat_4, (Budget (__nat_5, v_cells))) when __nat_4 >= 1 && __nat_5 >= 1 ->
(let v_rest = (__nat_4 - 1) in
(let v_remaining = (__nat_5 - 1) in
(let v_remaining = (Budget (v_remaining, v_cells)) in
(f_array_fill_elements (v_rest) (v_value) ((v_value :: v_elements)) (v_remaining))))))
and (* const_eval.bend:584 *)
f_array_fill_checked : bool -> int32 -> t_Value -> t_Budget -> (M.t_Diagnostic, t_Evaluation) Base.result_ =
fun v_allowed v_count v_value v_remaining ->
(match v_allowed with
| false ->
(Fail ((M.Diagnostic (s_39, s_40, s_41))))
| true ->
(f_array_fill_elements ((Base.u32_to_nat (v_count))) (v_value) ([]) (v_remaining)))
and (* const_eval.bend:591 *)
f_array_fill : t_Value -> t_Value -> t_Budget -> (M.t_Diagnostic, t_Evaluation) Base.result_ =
fun v_count v_value v_remaining ->
(match v_count with
| (U32Value (v_length)) ->
(f_array_fill_checked ((Base.u32_is_lt (v_length) (0x00400000l))) (v_length) (v_value) (v_remaining))
| _ ->
(Fail ((M.Diagnostic (s_34, s_4, s_42)))))
and (* const_eval.bend:598 *)
f_array_generate_count_checked : bool -> int32 -> (M.t_Diagnostic, int) Base.result_ =
fun v_allowed v_count ->
(match v_allowed with
| false ->
(Fail ((M.Diagnostic (s_39, s_40, s_41))))
| true ->
(Done ((Base.u32_to_nat (v_count)))))
and (* const_eval.bend:605 *)
f_array_generate_count : t_Value -> (M.t_Diagnostic, int) Base.result_ =
fun v_count ->
(match v_count with
| (U32Value (v_length)) ->
(f_array_generate_count_checked ((Base.u32_is_lt (v_length) (0x00400000l))) (v_length))
| _ ->
(Fail ((M.Diagnostic (s_34, s_4, s_43)))))
and (* const_eval.bend:612 *)
f_array_bounds : unit -> M.t_Diagnostic =
fun () ->
(M.Diagnostic (s_44, s_4, s_45))
and (* const_eval.bend:615 *)
f_array_get_elements : (t_Value) list -> int -> t_Budget -> (M.t_Diagnostic, t_Evaluation) Base.result_ =
fun v_elements v_index v_remaining ->
(match (v_elements, v_index) with
| ([], _) ->
(Fail ((f_array_bounds ())))
| ((v_head :: v_tail), 0) ->
(Done ((Evaluation (v_head, v_remaining))))
| ((v_head :: v_tail), __nat_6) when __nat_6 >= 1 ->
(let v_rest = (__nat_6 - 1) in
(f_array_get_elements (v_tail) (v_rest) (v_remaining))))
and (* const_eval.bend:624 *)
f_array_get : t_Value -> t_Value -> t_Budget -> (M.t_Diagnostic, t_Evaluation) Base.result_ =
fun v_array v_index v_remaining ->
(match (v_array, v_index) with
| ((ArrayValue (v_elements)), (U32Value (v_offset))) ->
(f_array_get_elements (v_elements) ((Base.u32_to_nat (v_offset))) (v_remaining))
| (_, _) ->
(Fail ((M.Diagnostic (s_34, s_4, s_46)))))
and (* const_eval.bend:633 *)
f_array_copy : (t_Value) list -> int -> t_Value -> int -> (t_Value) list -> t_Budget -> (M.t_Diagnostic, t_Evaluation) Base.result_ =
fun v_elements v_index v_replacement v_offset v_reversed v_steps ->
(match (v_elements, v_steps) with
| ([], _) ->
(Done ((Evaluation ((ArrayValue ((Base.list_reverse (v_reversed)))), v_steps))))
| ((v_head :: v_tail), (Budget (0, v_cells))) ->
(Fail ((M.Diagnostic (s_37, s_4, s_47))))
| ((v_head :: v_tail), (Budget (__nat_7, v_cells))) when __nat_7 >= 1 ->
(let v_remaining = (__nat_7 - 1) in
(let v_remaining = (Budget (v_remaining, v_cells)) in
(f_array_copy (v_tail) (v_index) (v_replacement) ((Base.nat_add 1 v_offset)) (((Base.bool_pick ((Base.nat_is_eq (v_index) (v_offset))) (v_replacement) (v_head)) :: v_reversed)) (v_remaining)))))
and (* const_eval.bend:643 *)
f_array_set_checked : bool -> (t_Value) list -> int -> t_Value -> t_Budget -> (M.t_Diagnostic, t_Evaluation) Base.result_ =
fun v_valid v_elements v_index v_replacement v_steps ->
(match v_valid with
| false ->
(Fail ((f_array_bounds ())))
| true ->
(f_array_copy (v_elements) (v_index) (v_replacement) (0) ([]) (v_steps)))
and (* const_eval.bend:650 *)
f_array_set : t_Value -> t_Value -> t_Value -> t_Budget -> (M.t_Diagnostic, t_Evaluation) Base.result_ =
fun v_array v_index v_replacement v_remaining ->
(match (v_array, v_index) with
| ((ArrayValue (v_elements)), (U32Value (v_offset))) ->
(let v_index = (Base.u32_to_nat (v_offset)) in
(f_array_set_checked ((Base.nat_is_lt (v_index) ((Base.list_length (v_elements))))) (v_elements) (v_index) (v_replacement) (v_remaining)))
| (_, _) ->
(Fail ((M.Diagnostic (s_34, s_4, s_48)))))
and (* const_eval.bend:658 *)
f_array_length_checked : bool -> int -> t_Budget -> (M.t_Diagnostic, t_Evaluation) Base.result_ =
fun v_valid v_count v_remaining ->
(match v_valid with
| false ->
(Fail ((M.Diagnostic (s_49, s_4, s_50))))
| true ->
(Done ((Evaluation ((U32Value ((Base.u32_from_nat (v_count)))), v_remaining)))))
and (* const_eval.bend:665 *)
f_array_length : t_Value -> t_Budget -> (M.t_Diagnostic, t_Evaluation) Base.result_ =
fun v_array v_remaining ->
(match v_array with
| (ArrayValue (v_elements)) ->
(let v_count = (Base.list_length (v_elements)) in
(f_array_length_checked ((Base.nat_is_le (v_count) ((Base.u32_to_nat (0xffffffffl))))) (v_count) (v_remaining)))
| _ ->
(Fail ((M.Diagnostic (s_34, s_4, s_51)))))
and (* const_eval.bend:673 *)
f_guard_scope : (((t_Value) t_Binding) list) option -> M.t_Expr -> M.t_Expr -> t_Context -> t_ScopedExpr =
fun v_bindings v_body v_alternative v_context ->
(match v_bindings with
| (Some (v_locals)) ->
(ScopedExpr (v_body, (f_with_bindings (v_context) (v_locals))))
| None ->
(ScopedExpr (v_alternative, v_context)))
and (* const_eval.bend:680 *)
f_complete_block : t_Evaluation -> int -> t_Evaluation =
fun v_evaluation v_label ->
(match v_evaluation with
| (Evaluation ((ReturnValue (v_target, v_value)), v_remaining)) ->
(Base.bool_pick ((Base.nat_is_eq (v_target) (v_label))) ((Evaluation (v_value, v_remaining))) ((Evaluation ((ReturnValue (v_target, v_value)), v_remaining))))
| (Evaluation (v_value, v_remaining)) ->
(Evaluation (v_value, v_remaining)))
and (* const_eval.bend:687 *)
f_complete_definition : t_Evaluation -> (M.t_Diagnostic, t_Evaluation) Base.result_ =
fun v_evaluation ->
(match v_evaluation with
| (Evaluation ((ReturnValue (v_label, v_value)), v_remaining)) ->
(Fail ((M.Diagnostic (s_0, s_4, s_52))))
| (Evaluation ((PatternBindingsValue (v_bindings)), v_remaining)) ->
(Fail ((M.Diagnostic (s_0, s_4, s_53))))
| (Evaluation ((MatchValuesValue (v_values)), v_remaining)) ->
(Fail ((M.Diagnostic (s_0, s_4, s_54))))
| (Evaluation (v_value, v_remaining)) ->
(Done ((Evaluation (v_value, v_remaining)))))
and (* const_eval.bend:698 *)
f_collected_match_values : t_Value -> (M.t_Diagnostic, (t_Value) list) Base.result_ =
fun v_collected ->
(match v_collected with
| (MatchValuesValue (v_values)) ->
(Done (v_values))
| _ ->
(Fail ((M.Diagnostic (s_0, s_4, s_55)))))
and (* const_eval.bend:705 *)
f_collected_pattern_bindings : t_Value -> (M.t_Diagnostic, (((t_Value) t_Binding) list) option) Base.result_ =
fun v_collected ->
(match v_collected with
| (PatternBindingsValue (v_bindings)) ->
(Done (v_bindings))
| _ ->
(Fail ((M.Diagnostic (s_0, s_4, s_56)))))
and (* const_eval.bend:712 *)
f_value_pattern : t_Value -> (M.t_Diagnostic, M.t_Pattern) Base.result_ =
fun v_value ->
(match v_value with
| (U32Value (v_number)) ->
(Done ((M.U32Pattern (v_number))))
| (BoolValue (v_boolean)) ->
(Done ((M.BoolPattern (v_boolean))))
| _ ->
(Fail ((M.Diagnostic (s_57, s_4, s_58)))))
and (* const_eval.bend:724 *)
f_tag_evaluation : (M.t_Diagnostic, t_Evaluation) Base.result_ -> int -> (M.t_Diagnostic, t_Evaluation) Base.result_ =
fun v_result v_offset ->
(match v_result with
| (Done (v_value)) ->
(Done (v_value))
| (Fail ((M.Diagnostic (v_code, v_subject, v_message)))) ->
(Fail ((M.Diagnostic (v_code, (Base.string_append s_59 (Base.nat_show (v_offset))), v_message)))))
and (* const_eval.bend:731 *)
f_tag_application : (M.t_Diagnostic, t_Application) Base.result_ -> int -> (M.t_Diagnostic, t_Application) Base.result_ =
fun v_result v_offset ->
(match v_result with
| (Done (v_value)) ->
(Done (v_value))
| (Fail ((M.Diagnostic (v_code, v_subject, v_message)))) ->
(Fail ((M.Diagnostic (v_code, (Base.string_append s_59 (Base.nat_show (v_offset))), v_message)))))
and (* const_eval.bend:738 *)
f_budget_diagnostic : M.t_Expr -> M.t_Diagnostic =
fun v_expression ->
(match v_expression with
| (M.TagExpr (v_offset, v_callee, v_argument)) ->
(M.Diagnostic (s_37, (Base.string_append s_59 (Base.nat_show (v_offset))), s_60))
| (M.QualifiedExpr (v_offset, v_annotation, v_predicates, v_value)) ->
(f_budget_diagnostic (v_value))
| (M.InstantiationExpr (v_site, v_value)) ->
(f_budget_diagnostic (v_value))
| _ ->
(M.Diagnostic (s_37, s_4, s_60)))
and (* const_eval.bend:749 *)
f_evaluate_work : int -> int -> (M.t_Expr) list -> t_Budget -> t_EvaluationWork -> t_Context -> (M.t_Diagnostic, t_Evaluation) Base.result_ =
fun v_depth v_matching_fuel v_pending v_steps v_work v_context ->
(match (v_depth, v_matching_fuel, v_pending, v_steps, v_work) with
| (_, __nat_8, _, (Budget (v_remaining, v_cells)), (HandleValue ((StateProviderValue (v_read, v_write, v_initial)), v_body))) when __nat_8 >= 1 ->
(let v_scope_rest = (__nat_8 - 1) in
(let v_slot = (Base.list_length (v_cells)) in
(match (f_evaluate_work (v_depth) (v_scope_rest) ([]) ((Budget (v_remaining, ((StateCell (v_slot, v_initial)) :: v_cells)))) ((Expression (v_body))) ((f_state_scope (v_read) (v_write) (v_slot) (v_context)))) with
| Fail __error -> Fail __error
| Done v_result ->
(f_finish_state_scope (v_result) (v_slot)))))
| (_, __nat_9, _, _, (HandleValue (v_provider, v_body))) when __nat_9 >= 1 ->
(let v_scope_rest = (__nat_9 - 1) in
(match (f_with_provider (v_provider) (v_context)) with
| Fail __error -> Fail __error
| Done v_scope ->
(f_evaluate_work (v_depth) (v_scope_rest) ([]) (v_steps) ((Expression (v_body))) (v_scope))))
| (_, 0, _, _, (HandleValue (v_provider, v_body))) ->
(Fail ((M.Diagnostic (s_37, s_21, s_61))))
| (__nat_10, _, _, _, (ForBounds (v_index, (U32Value (v_start)), (U32Value (v_end)), v_state, v_initial, v_body))) when __nat_10 >= 1 ->
(let v_limit = (__nat_10 - 1) in
(f_evaluate_work (v_limit) ((Base.bool_pick ((Base.u32_is_lt (v_start) (v_end))) ((Base.nat_sub ((Base.u32_to_nat (v_end))) ((Base.u32_to_nat (v_start))))) (0))) ([]) (v_steps) ((ForIterations (v_index, v_start, v_state, v_initial, v_body))) (v_context)))
| (_, _, _, _, (ForBounds (v_index, v_start, v_end, v_state, v_initial, v_body))) ->
(Fail ((M.Diagnostic (s_0, s_62, s_63))))
| (_, 0, _, _, (ForIterations (v_index, v_current, v_state, v_value, v_body))) ->
(Done ((Evaluation (v_value, v_steps))))
| (_, __nat_11, _, (Budget (0, v_cells)), (ForIterations (v_index, v_current, v_state, v_value, v_body))) when __nat_11 >= 1 ->
(let v_rest = (__nat_11 - 1) in
(Fail ((M.Diagnostic (s_37, s_62, s_64)))))
| (_, __nat_12, _, (Budget (__nat_13, v_cells)), (ForIterations (v_index, v_current, v_state, v_value, v_body))) when __nat_12 >= 1 && __nat_13 >= 1 ->
(let v_rest = (__nat_12 - 1) in
(let v_remaining = (__nat_13 - 1) in
(let v_remaining = (Budget (v_remaining, v_cells)) in
(match (f_evaluate_work (v_depth) (v_rest) ([]) (v_remaining) ((Expression (v_body))) ((f_with_local ((f_with_local (v_context) (v_index) ((U32Value (v_current))))) (v_state) (v_value)))) with
| Fail __error -> Fail __error
| Done v_checked ->
(f_continue_value (v_checked) ((fun v_successor ->
(fun v_next_steps ->
(f_evaluate_work (v_depth) (v_rest) ([]) (v_next_steps) ((ForIterations (v_index, (Base.u32_add v_current 0x00000001l), v_state, v_successor, v_body))) (v_context))))))))))
| (_, _, _, (Budget (0, v_cells)), (ForeverIterations (v_state, v_value, v_body))) ->
(Fail ((M.Diagnostic (s_37, s_65, s_66))))
| (__nat_14, _, _, (Budget (__nat_15, v_cells)), (ForeverIterations (v_state, v_value, v_body))) when __nat_14 >= 1 && __nat_15 >= 1 ->
(let v_limit = (__nat_14 - 1) in
(let v_remaining = (__nat_15 - 1) in
(let v_remaining = (Budget (v_remaining, v_cells)) in
(match (f_evaluate_work (v_limit) (v_matching_fuel) ([]) (v_remaining) ((Expression (v_body))) ((f_with_local (v_context) (v_state) (v_value)))) with
| Fail __error -> Fail __error
| Done v_checked ->
(f_continue_value (v_checked) ((fun v_successor ->
(fun v_next_steps ->
(f_evaluate_work (v_limit) (v_matching_fuel) ([]) (v_next_steps) ((ForeverIterations (v_state, v_successor, v_body))) (v_context))))))))))
| (0, _, _, _, (ForeverIterations (v_state, v_value, v_body))) ->
(Fail ((M.Diagnostic (s_37, s_65, s_67))))
| (_, 0, _, _, (GenerateElements (v_generator, v_index, v_reversed))) ->
(Done ((Evaluation ((ArrayValue ((Base.list_reverse (v_reversed)))), v_steps))))
| (_, __nat_16, _, (Budget (0, v_cells)), (GenerateElements (v_generator, v_index, v_reversed))) when __nat_16 >= 1 ->
(let v_rest = (__nat_16 - 1) in
(Fail ((M.Diagnostic (s_37, s_4, s_68)))))
| (_, __nat_17, _, (Budget (__nat_18, v_cells)), (GenerateElements (v_generator, v_index, v_reversed))) when __nat_17 >= 1 && __nat_18 >= 1 ->
(let v_rest = (__nat_17 - 1) in
(let v_remaining = (__nat_18 - 1) in
(let v_remaining = (Budget (v_remaining, v_cells)) in
(match (f_application (v_generator) ((U32Value (v_index))) (v_context)) with
| Fail __error -> Fail __error
| Done v_call ->
(match (f_resolve_application ((f_context_providers (v_context))) (v_call) (v_context)) with
| Fail __error -> Fail __error
| Done v_resolved ->
(match (f_complete_application (v_resolved) (v_remaining) ((fun v_body ->
(fun v_scope ->
(fun v_body_steps ->
(match (f_evaluate_work (v_depth) (v_rest) ([]) (v_body_steps) ((Expression (v_body))) (v_scope)) with
| Fail __error -> Fail __error
| Done v_result ->
(f_complete_definition (v_result)))))))) with
| Fail __error -> Fail __error
| Done v_generated ->
(f_continue_value (v_generated) ((fun v_element ->
(fun v_next_steps ->
(f_evaluate_work (v_depth) (v_rest) ([]) (v_next_steps) ((GenerateElements (v_generator, (Base.u32_add v_index 0x00000001l), (v_element :: v_reversed)))) (v_context))))))))))))
| (_, _, _, _, (MatchPatterns (v_fuel, (Fail (v_error))))) ->
(Fail (v_error))
| (_, _, _, _, (MatchPatterns (v_fuel, (Done (PatternRejected))))) ->
(Done ((Evaluation ((PatternBindingsValue (None)), v_steps))))
| (_, _, _, _, (MatchPatterns (v_fuel, (Done ((PatternPending ([], v_reversed))))))) ->
(Done ((Evaluation ((PatternBindingsValue ((Some ((Base.list_reverse (v_reversed)))))), v_steps))))
| (_, _, _, _, (MatchPatterns (0, (Done ((PatternPending (v_pending_patterns, v_reversed))))))) ->
(Fail ((M.Diagnostic (s_28, s_4, s_29))))
| (_, __nat_19, _, _, (MatchPatterns (__nat_20, (Done ((PatternPending (((PatternValue ((M.ValuePattern (v_reference)), v_actual)) :: v_remaining_patterns), v_reversed))))))) when __nat_19 >= 1 && __nat_20 >= 1 ->
(let v_matching_rest = (__nat_19 - 1) in
(let v_fuel = (__nat_20 - 1) in
(match (f_evaluate_work (v_depth) (v_matching_rest) ([]) (v_steps) ((Expression ((M.f_reference_expr (v_reference))))) (v_context)) with
| Fail __error -> Fail __error
| Done v_expected ->
(match (f_value_pattern ((f_eval_value (v_expected)))) with
| Fail __error -> Fail __error
| Done v_literal ->
(f_evaluate_work (v_depth) (v_matching_rest) ([]) ((f_eval_budget (v_expected))) ((MatchPatterns (v_fuel, (f_pattern_step ((PatternValue (v_literal, v_actual))) (v_remaining_patterns) (v_reversed))))) (v_context))))))
| (_, __nat_21, _, _, (MatchPatterns (__nat_22, (Done ((PatternPending ((v_head :: v_remaining_patterns), v_reversed))))))) when __nat_21 >= 1 && __nat_22 >= 1 ->
(let v_matching_rest = (__nat_21 - 1) in
(let v_fuel = (__nat_22 - 1) in
(f_evaluate_work (v_depth) (v_matching_rest) ([]) (v_steps) ((MatchPatterns (v_fuel, (f_pattern_step (v_head) (v_remaining_patterns) (v_reversed))))) (v_context))))
| (_, _, _, _, (MatchArms ([], v_values))) ->
(Fail ((M.Diagnostic (s_0, s_4, s_69))))
| (_, __nat_23, _, _, (MatchArms (((M.MatchArm (v_patterns, v_body)) :: v_tail), v_values))) when __nat_23 >= 1 ->
(let v_matching_rest = (__nat_23 - 1) in
(match (f_evaluate_work (v_depth) (v_matching_rest) ([]) (v_steps) ((MatchPatterns ((Base.u32_to_nat (0x00010000l)), (Done ((PatternPending ([(ProductPatterns (v_patterns, v_values))], []))))))) (v_context)) with
| Fail __error -> Fail __error
| Done v_matched ->
(f_evaluate_work (v_depth) (v_matching_rest) ([]) ((f_eval_budget (v_matched))) ((MatchSelected ((f_eval_value (v_matched)), v_body, v_tail, v_values))) (v_context))))
| (_, __nat_24, _, _, (MatchSelected ((PatternBindingsValue ((Some (v_locals)))), v_body, v_arms, v_values))) when __nat_24 >= 1 ->
(let v_matching_rest = (__nat_24 - 1) in
(f_evaluate_work (v_depth) (v_matching_rest) ([]) (v_steps) ((Expression (v_body))) ((f_with_bindings (v_context) (v_locals)))))
| (_, __nat_25, _, _, (MatchSelected ((PatternBindingsValue (None)), v_body, v_arms, v_values))) when __nat_25 >= 1 ->
(let v_matching_rest = (__nat_25 - 1) in
(f_evaluate_work (v_depth) (v_matching_rest) ([]) (v_steps) ((MatchArms (v_arms, v_values))) (v_context)))
| (_, 0, _, _, (MatchPatterns (v_fuel, v_progress))) ->
(Fail ((M.Diagnostic (s_28, s_4, s_29))))
| (_, 0, _, _, (MatchArms (v_arms, v_values))) ->
(Fail ((M.Diagnostic (s_28, s_4, s_29))))
| (_, 0, _, _, (MatchSelected (v_bindings, v_body, v_arms, v_values))) ->
(Fail ((M.Diagnostic (s_28, s_4, s_29))))
| (_, _, _, _, (MatchSelected (v_other, v_body, v_arms, v_values))) ->
(Fail ((M.Diagnostic (s_0, s_4, s_56))))
| (_, _, [], _, CollectValues) ->
(Done ((Evaluation ((MatchValuesValue ([])), v_steps))))
| (_, _, (v_head :: v_tail), _, CollectValues) ->
(match (f_evaluate_work (v_depth) (v_matching_fuel) (v_tail) (v_steps) ((Expression (v_head))) (v_context)) with
| Fail __error -> Fail __error
| Done v_checked ->
(f_continue_value (v_checked) ((fun v_value ->
(fun v_next_steps ->
(match (f_evaluate_work (v_depth) (v_matching_fuel) (v_tail) (v_next_steps) (CollectValues) (v_context)) with
| Fail __error -> Fail __error
| Done v_collected ->
(f_continue_value (v_collected) ((fun v_values ->
(fun v_remaining ->
(f_prepend_collected_value (v_value) (v_values) (v_remaining))))))))))))
| (0, _, _, _, (Expression (v_expression))) ->
(Fail ((f_budget_diagnostic (v_expression))))
| (_, _, _, (Budget (0, v_cells)), (Expression (v_expression))) ->
(Fail ((f_budget_diagnostic (v_expression))))
| (_, _, _, _, (Expression ((M.QualifiedExpr (v_offset, v_annotation, v_predicates, v_value))))) ->
(f_evaluate_work (v_depth) (v_matching_fuel) (v_pending) (v_steps) ((Expression (v_value))) (v_context))
| (_, _, _, _, (Expression ((M.InstantiationExpr (v_site, v_value))))) ->
(f_evaluate_work (v_depth) (v_matching_fuel) (v_pending) (v_steps) ((Expression (v_value))) (v_context))
| (__nat_26, _, _, (Budget (__nat_27, v_cells)), (Expression (v_expression))) when __nat_26 >= 1 && __nat_27 >= 1 ->
(let v_limit = (__nat_26 - 1) in
(let v_remaining = (__nat_27 - 1) in
(match v_expression with
| (M.RuntimeInitExpr (v_value)) ->
(Fail ((M.Diagnostic (s_6, s_70, s_71))))
| M.UnitExpr ->
(Done ((Evaluation (UnitValue, (f_spend_budget (v_steps))))))
| (M.U32Expr (v_value)) ->
(Done ((Evaluation ((U32Value (v_value)), (f_spend_budget (v_steps))))))
| (M.F32Expr (v_value)) ->
(Done ((Evaluation ((F32Value (v_value)), (f_spend_budget (v_steps))))))
| (M.BoolExpr (v_value)) ->
(Done ((Evaluation ((BoolValue (v_value)), (f_spend_budget (v_steps))))))
| (M.PanicExpr (v_message)) ->
(Fail ((M.Diagnostic (s_72, s_4, v_message))))
| (M.LocalExpr (v_name)) ->
(match (f_lookup_local ((f_context_locals (v_context))) (v_name)) with
| Fail __error -> Fail __error
| Done v_value ->
(Done ((Evaluation (v_value, (f_spend_budget (v_steps)))))))
| (M.ConstantExpr (v_name)) ->
(match (f_lookup_constant ((f_context_constants (v_context))) (v_name)) with
| Fail __error -> Fail __error
| Done v_value ->
(f_evaluate_work (v_limit) ((Base.u32_to_nat (0x00010000l))) ([]) ((f_spend_budget (v_steps))) ((Expression (v_value))) ((f_without_locals (v_context)))))
| (M.FunctionExpr (v_name)) ->
(match (f_lookup_function ((f_context_functions (v_context))) (v_name)) with
| Fail __error -> Fail __error
| Done v_function ->
(f_function_value_allowed ((f_function_body (v_function))) (v_name) ((f_spend_budget (v_steps)))))
| (M.OperationExpr (v_identity)) ->
(Done ((Evaluation ((OperationValue (v_identity)), (f_spend_budget (v_steps))))))
| (M.SpecializeOperationExpr (v_template, v_arguments, v_body)) ->
(Fail ((M.Diagnostic (s_73, s_4, s_74))))
| (M.OperationDescriptorExpr (v_identity)) ->
(Done ((Evaluation ((EffectDescriptorValue (v_identity)), (f_spend_budget (v_steps))))))
| (M.FunctionEffectsExpr (v_callee)) ->
(match (f_function_effects ((f_context_checked_functions (v_context))) (v_callee)) with
| Fail __error -> Fail __error
| Done v_value ->
(Done ((Evaluation (v_value, (f_spend_budget (v_steps)))))))
| (M.ConstructorRefExpr (v_constructor)) ->
(match (f_constructor_value ((f_lookup_constructor ((f_context_data_types (v_context))) (v_constructor))) (v_constructor)) with
| Fail __error -> Fail __error
| Done v_value ->
(Done ((Evaluation (v_value, (f_spend_budget (v_steps)))))))
| (M.ConstructExpr (v_constructor, None)) ->
(Done ((Evaluation ((DataValue (v_constructor, None)), (f_spend_budget (v_steps))))))
| (M.ConstructExpr (v_constructor, (Some (v_payload)))) ->
(match (f_evaluate_work (v_limit) ((Base.u32_to_nat (0x00010000l))) ([]) ((f_spend_budget (v_steps))) ((Expression (v_payload))) (v_context)) with
| Fail __error -> Fail __error
| Done v_checked ->
(f_continue_value (v_checked) ((fun v_value ->
(fun v_next_steps ->
(Done ((Evaluation ((DataValue (v_constructor, (Some (v_value)))), v_next_steps)))))))))
| (M.ProductExpr ((v_first :: (v_second :: v_tail)))) ->
(match (f_evaluate_work (v_limit) ((Base.u32_to_nat (0x00010000l))) ((v_first :: (v_second :: v_tail))) ((f_spend_budget (v_steps))) (CollectValues) (v_context)) with
| Fail __error -> Fail __error
| Done v_checked ->
(f_continue_value (v_checked) ((fun v_collected ->
(fun v_next_steps ->
(f_product_value (v_collected) (v_next_steps)))))))
| (M.ProductExpr (v_elements)) ->
(Fail ((M.Diagnostic (s_26, s_4, s_75))))
| (M.ProjectExpr (v_value, v_index)) ->
(match (f_evaluate_work (v_limit) ((Base.u32_to_nat (0x00010000l))) ([]) ((f_spend_budget (v_steps))) ((Expression (v_value))) (v_context)) with
| Fail __error -> Fail __error
| Done v_checked ->
(f_continue_value (v_checked) ((fun v_product ->
(fun v_next_steps ->
(f_project (v_product) (v_index) (v_next_steps)))))))
| (M.ArrayExpr (v_elements)) ->
(match (f_evaluate_work (v_limit) ((Base.u32_to_nat (0x00010000l))) (v_elements) ((f_spend_budget (v_steps))) (CollectValues) (v_context)) with
| Fail __error -> Fail __error
| Done v_checked ->
(f_continue_value (v_checked) ((fun v_collected ->
(fun v_next_steps ->
(f_array_value (v_collected) (v_next_steps)))))))
| (M.ForExpr (v_index, v_start, v_end, v_state, v_initial, v_body)) ->
(match (f_evaluate_work (v_limit) ((Base.u32_to_nat (0x00010000l))) ([]) ((f_spend_budget (v_steps))) ((Expression (v_start))) (v_context)) with
| Fail __error -> Fail __error
| Done v_checked ->
(f_continue_value (v_checked) ((fun v_first ->
(fun v_end_steps ->
(match (f_evaluate_work (v_limit) ((Base.u32_to_nat (0x00010000l))) ([]) (v_end_steps) ((Expression (v_end))) (v_context)) with
| Fail __error -> Fail __error
| Done v_bounded ->
(f_continue_value (v_bounded) ((fun v_last ->
(fun v_initial_steps ->
(match (f_evaluate_work (v_limit) ((Base.u32_to_nat (0x00010000l))) ([]) (v_initial_steps) ((Expression (v_initial))) (v_context)) with
| Fail __error -> Fail __error
| Done v_prepared ->
(f_continue_value (v_prepared) ((fun v_value ->
(fun v_next_steps ->
(f_evaluate_work (v_limit) ((Base.u32_to_nat (0x00010000l))) ([]) (v_next_steps) ((ForBounds (v_index, v_first, v_last, v_state, v_value, v_body))) (v_context)))))))))))))))))
| (M.ForeverExpr (v_state, v_initial, v_body)) ->
(match (f_evaluate_work (v_limit) ((Base.u32_to_nat (0x00010000l))) ([]) ((f_spend_budget (v_steps))) ((Expression (v_initial))) (v_context)) with
| Fail __error -> Fail __error
| Done v_prepared ->
(f_continue_value (v_prepared) ((fun v_value ->
(fun v_next_steps ->
(f_evaluate_work (v_limit) ((Base.u32_to_nat (0x00010000l))) ([]) (v_next_steps) ((ForeverIterations (v_state, v_value, v_body))) (v_context)))))))
| (M.ArrayGenerateExpr (v_count, v_generator)) ->
(match (f_evaluate_work (v_limit) ((Base.u32_to_nat (0x00010000l))) ([]) ((f_spend_budget (v_steps))) ((Expression (v_count))) (v_context)) with
| Fail __error -> Fail __error
| Done v_checked ->
(f_continue_value (v_checked) ((fun v_length ->
(fun v_generator_steps ->
(match (f_evaluate_work (v_limit) ((Base.u32_to_nat (0x00010000l))) ([]) (v_generator_steps) ((Expression (v_generator))) (v_context)) with
| Fail __error -> Fail __error
| Done v_prepared ->
(f_continue_value (v_prepared) ((fun v_function ->
(fun v_next_steps ->
(match (f_array_generate_count (v_length)) with
| Fail __error -> Fail __error
| Done v_count ->
(f_evaluate_work (v_limit) (v_count) ([]) (v_next_steps) ((GenerateElements (v_function, 0x00000000l, []))) (v_context)))))))))))))
| (M.ArrayFillExpr (v_count, v_value)) ->
(match (f_evaluate_work (v_limit) ((Base.u32_to_nat (0x00010000l))) ([]) ((f_spend_budget (v_steps))) ((Expression (v_count))) (v_context)) with
| Fail __error -> Fail __error
| Done v_checked ->
(f_continue_value (v_checked) ((fun v_length ->
(fun v_value_steps ->
(match (f_evaluate_work (v_limit) ((Base.u32_to_nat (0x00010000l))) ([]) (v_value_steps) ((Expression (v_value))) (v_context)) with
| Fail __error -> Fail __error
| Done v_filled ->
(f_continue_value (v_filled) ((fun v_element ->
(fun v_next_steps ->
(f_array_fill (v_length) (v_element) (v_next_steps))))))))))))
| (M.ArrayGetExpr (v_array, v_index)) ->
(match (f_evaluate_work (v_limit) ((Base.u32_to_nat (0x00010000l))) ([]) ((f_spend_budget (v_steps))) ((Expression (v_array))) (v_context)) with
| Fail __error -> Fail __error
| Done v_checked ->
(f_continue_value (v_checked) ((fun v_value ->
(fun v_index_steps ->
(match (f_evaluate_work (v_limit) ((Base.u32_to_nat (0x00010000l))) ([]) (v_index_steps) ((Expression (v_index))) (v_context)) with
| Fail __error -> Fail __error
| Done v_indexed ->
(f_continue_value (v_indexed) ((fun v_offset ->
(fun v_next_steps ->
(f_array_get (v_value) (v_offset) (v_next_steps))))))))))))
| (M.ArraySetExpr (v_array, v_index, v_value)) ->
(match (f_evaluate_work (v_limit) ((Base.u32_to_nat (0x00010000l))) ([]) ((f_spend_budget (v_steps))) ((Expression (v_array))) (v_context)) with
| Fail __error -> Fail __error
| Done v_checked ->
(f_continue_value (v_checked) ((fun v_original ->
(fun v_index_steps ->
(match (f_evaluate_work (v_limit) ((Base.u32_to_nat (0x00010000l))) ([]) (v_index_steps) ((Expression (v_index))) (v_context)) with
| Fail __error -> Fail __error
| Done v_indexed ->
(f_continue_value (v_indexed) ((fun v_offset ->
(fun v_value_steps ->
(match (f_evaluate_work (v_limit) ((Base.u32_to_nat (0x00010000l))) ([]) (v_value_steps) ((Expression (v_value))) (v_context)) with
| Fail __error -> Fail __error
| Done v_changed ->
(f_continue_value (v_changed) ((fun v_replacement ->
(fun v_next_steps ->
(f_array_set (v_original) (v_offset) (v_replacement) (v_next_steps)))))))))))))))))
| (M.AssociatedExpr (v_identity, v_dispatch, v_member, v_templates, v_left, v_right)) ->
(Fail ((M.Diagnostic (s_76, s_4, s_77))))
| (M.GenericOperationExpr (v_identity, v_template, v_arguments)) ->
(Fail ((M.Diagnostic (s_73, (M.f_type_id_show (v_template)), s_78))))
| (M.ArrayLengthExpr (v_array)) ->
(match (f_evaluate_work (v_limit) ((Base.u32_to_nat (0x00010000l))) ([]) ((f_spend_budget (v_steps))) ((Expression (v_array))) (v_context)) with
| Fail __error -> Fail __error
| Done v_checked ->
(f_continue_value (v_checked) ((fun v_value ->
(fun v_next_steps ->
(f_array_length (v_value) (v_next_steps)))))))
| (M.LambdaExpr (v_identity, v_parameter, v_parameter_type, v_result_type, v_body)) ->
(match (F.f_free (4096) ((F.ExpressionWork (v_body, [v_parameter])))) with
| Fail __error -> Fail __error
| Done v_names ->
(match (f_capture_environment (v_names) ((f_context_locals (v_context)))) with
| Fail __error -> Fail __error
| Done v_environment ->
(Done ((Evaluation ((ClosureValue (v_identity, v_parameter, v_body, v_environment)), (f_spend_budget (v_steps))))))))
| (M.StateProviderExpr (v_read, v_write, v_initial)) ->
(match (f_evaluate_work (v_limit) ((Base.u32_to_nat (0x00010000l))) ([]) ((f_spend_budget (v_steps))) ((Expression (v_initial))) (v_context)) with
| Fail __error -> Fail __error
| Done v_checked ->
(f_continue_value (v_checked) ((fun v_value ->
(fun v_next_steps ->
(Done ((Evaluation ((StateProviderValue (v_read, v_write, v_value)), v_next_steps)))))))))
| (M.ProviderExpr (v_identity, v_implementation)) ->
(match (f_evaluate_work (v_limit) ((Base.u32_to_nat (0x00010000l))) ([]) ((f_spend_budget (v_steps))) ((Expression (v_implementation))) (v_context)) with
| Fail __error -> Fail __error
| Done v_checked ->
(f_continue_value (v_checked) ((fun v_value ->
(fun v_next_steps ->
(Done ((Evaluation ((ProviderValue (v_identity, v_value)), v_next_steps)))))))))
| (M.HandleExpr (v_provider, v_body)) ->
(match (f_evaluate_work (v_limit) ((Base.u32_to_nat (0x00010000l))) ([]) ((f_spend_budget (v_steps))) ((Expression (v_provider))) (v_context)) with
| Fail __error -> Fail __error
| Done v_checked ->
(f_continue_value (v_checked) ((fun v_value ->
(fun v_next_steps ->
(f_evaluate_work (v_limit) ((Base.u32_to_nat (0x00010000l))) ([]) (v_next_steps) ((HandleValue (v_value, v_body))) (v_context)))))))
| (M.ApplyExpr (v_callee, v_argument)) ->
(match (f_evaluate_work (v_limit) ((Base.u32_to_nat (0x00010000l))) ([]) ((f_spend_budget (v_steps))) ((Expression (v_callee))) (v_context)) with
| Fail __error -> Fail __error
| Done v_checked ->
(f_continue_value (v_checked) ((fun v_function ->
(fun v_argument_steps ->
(match (f_evaluate_work (v_limit) ((Base.u32_to_nat (0x00010000l))) ([]) (v_argument_steps) ((Expression (v_argument))) (v_context)) with
| Fail __error -> Fail __error
| Done v_applied ->
(f_continue_value (v_applied) ((fun v_value ->
(fun v_call_steps ->
(match (f_application (v_function) (v_value) (v_context)) with
| Fail __error -> Fail __error
| Done v_call ->
(match (f_resolve_application ((f_context_providers (v_context))) (v_call) (v_context)) with
| Fail __error -> Fail __error
| Done v_resolved ->
(f_complete_application (v_resolved) (v_call_steps) ((fun v_body ->
(fun v_scope ->
(fun v_body_steps ->
(match (f_evaluate_work (v_limit) ((Base.u32_to_nat (0x00010000l))) ([]) (v_body_steps) ((Expression (v_body))) (v_scope)) with
| Fail __error -> Fail __error
| Done v_result ->
(f_complete_definition (v_result))))))))))))))))))))
| (M.CallExpr (v_callee, v_argument)) ->
(match (f_evaluate_work (v_limit) ((Base.u32_to_nat (0x00010000l))) ([]) ((f_spend_budget (v_steps))) ((Expression (v_argument))) (v_context)) with
| Fail __error -> Fail __error
| Done v_checked ->
(f_continue_value (v_checked) ((fun v_value ->
(fun v_next_steps ->
(match (f_lookup_function ((f_context_functions (v_context))) (v_callee)) with
| Fail __error -> Fail __error
| Done v_function ->
(match (f_evaluate_work (v_limit) ((Base.u32_to_nat (0x00010000l))) ([]) (v_next_steps) ((Expression ((f_function_body (v_function))))) ((f_function_context (v_function) (v_value) (v_context)))) with
| Fail __error -> Fail __error
| Done v_result ->
(f_complete_definition (v_result)))))))))
| (M.ScalarExpr (v_operator, v_left, v_right)) ->
(match (f_evaluate_work (v_limit) ((Base.u32_to_nat (0x00010000l))) ([]) ((f_spend_budget (v_steps))) ((Expression (v_left))) (v_context)) with
| Fail __error -> Fail __error
| Done v_checked ->
(f_continue_value (v_checked) ((fun v_left_value ->
(fun v_right_steps ->
(match (f_evaluate_work (v_limit) ((Base.u32_to_nat (0x00010000l))) ([]) (v_right_steps) ((Expression (v_right))) (v_context)) with
| Fail __error -> Fail __error
| Done v_right_result ->
(f_continue_value (v_right_result) ((fun v_right_value ->
(fun v_next_steps ->
(f_scalar (v_operator) (v_left_value) (v_right_value) (v_next_steps))))))))))))
| (M.UnaryExpr (v_operator, v_value)) ->
(match (f_evaluate_work (v_limit) ((Base.u32_to_nat (0x00010000l))) ([]) ((f_spend_budget (v_steps))) ((Expression (v_value))) (v_context)) with
| Fail __error -> Fail __error
| Done v_checked ->
(f_continue_value (v_checked) ((fun v_result ->
(fun v_next_steps ->
(f_unary (v_operator) (v_result) (v_next_steps)))))))
| (M.EffectHasExpr (v_set, v_operation)) ->
(match (f_evaluate_work (v_limit) ((Base.u32_to_nat (0x00010000l))) ([]) ((f_spend_budget (v_steps))) ((Expression (v_set))) (v_context)) with
| Fail __error -> Fail __error
| Done v_checked ->
(f_continue_value (v_checked) ((fun v_selected ->
(fun v_operation_steps ->
(match (f_evaluate_work (v_limit) ((Base.u32_to_nat (0x00010000l))) ([]) (v_operation_steps) ((Expression (v_operation))) (v_context)) with
| Fail __error -> Fail __error
| Done v_inspected ->
(f_continue_value (v_inspected) ((fun v_descriptor ->
(fun v_next_steps ->
(f_effect_has (v_selected) (v_descriptor) (v_next_steps))))))))))))
| (M.EffectCountExpr (v_set)) ->
(match (f_evaluate_work (v_limit) ((Base.u32_to_nat (0x00010000l))) ([]) ((f_spend_budget (v_steps))) ((Expression (v_set))) (v_context)) with
| Fail __error -> Fail __error
| Done v_checked ->
(f_continue_value (v_checked) ((fun v_selected ->
(fun v_next_steps ->
(f_effect_count (v_selected) (v_next_steps)))))))
| (M.EffectSameExpr (v_left, v_right)) ->
(match (f_evaluate_work (v_limit) ((Base.u32_to_nat (0x00010000l))) ([]) ((f_spend_budget (v_steps))) ((Expression (v_left))) (v_context)) with
| Fail __error -> Fail __error
| Done v_checked ->
(f_continue_value (v_checked) ((fun v_a ->
(fun v_right_steps ->
(match (f_evaluate_work (v_limit) ((Base.u32_to_nat (0x00010000l))) ([]) (v_right_steps) ((Expression (v_right))) (v_context)) with
| Fail __error -> Fail __error
| Done v_inspected ->
(f_continue_value (v_inspected) ((fun v_b ->
(fun v_next_steps ->
(f_effect_same (v_a) (v_b) (v_next_steps))))))))))))
| (M.LetExpr (v_name, v_value, v_body)) ->
(match (f_evaluate_work (v_limit) ((Base.u32_to_nat (0x00010000l))) ([]) ((f_spend_budget (v_steps))) ((Expression (v_value))) (v_context)) with
| Fail __error -> Fail __error
| Done v_bound ->
(f_continue_value (v_bound) ((fun v_value ->
(fun v_next_steps ->
(f_evaluate_work (v_limit) ((Base.u32_to_nat (0x00010000l))) ([]) (v_next_steps) ((Expression (v_body))) ((f_with_local (v_context) (v_name) (v_value)))))))))
| (M.UseExpr (v_name, v_value, v_body)) ->
(match (f_evaluate_work (v_limit) ((Base.u32_to_nat (0x00010000l))) ([]) ((f_spend_budget (v_steps))) ((Expression (v_value))) (v_context)) with
| Fail __error -> Fail __error
| Done v_bound ->
(f_continue_value (v_bound) ((fun v_value ->
(fun v_next_steps ->
(f_evaluate_work (v_limit) ((Base.u32_to_nat (0x00010000l))) ([]) (v_next_steps) ((Expression (v_body))) ((f_with_local (v_context) (v_name) (v_value)))))))))
| (M.IfExpr (v_condition, v_consequent, v_alternative)) ->
(match (f_evaluate_work (v_limit) ((Base.u32_to_nat (0x00010000l))) ([]) ((f_spend_budget (v_steps))) ((Expression (v_condition))) (v_context)) with
| Fail __error -> Fail __error
| Done v_test ->
(f_continue_value (v_test) ((fun v_value ->
(fun v_next_steps ->
(match (f_branch (v_value) (v_consequent) (v_alternative)) with
| Fail __error -> Fail __error
| Done v_chosen ->
(f_evaluate_work (v_limit) ((Base.u32_to_nat (0x00010000l))) ([]) (v_next_steps) ((Expression (v_chosen))) (v_context))))))))
| (M.SequenceExpr (v_first, v_next)) ->
(match (f_evaluate_work (v_limit) ((Base.u32_to_nat (0x00010000l))) ([]) ((f_spend_budget (v_steps))) ((Expression (v_first))) (v_context)) with
| Fail __error -> Fail __error
| Done v_checked ->
(f_continue_value (v_checked) ((fun v_ignored ->
(fun v_next_steps ->
(f_evaluate_work (v_limit) ((Base.u32_to_nat (0x00010000l))) ([]) (v_next_steps) ((Expression (v_next))) (v_context)))))))
| (M.MatchExpr (v_values, v_arms)) ->
(match (f_evaluate_work (v_limit) ((Base.u32_to_nat (0x00010000l))) (v_values) ((f_spend_budget (v_steps))) (CollectValues) (v_context)) with
| Fail __error -> Fail __error
| Done v_checked ->
(f_continue_value (v_checked) ((fun v_collected ->
(fun v_next_steps ->
(match (f_collected_match_values (v_collected)) with
| Fail __error -> Fail __error
| Done v_scrutinees ->
(f_evaluate_work (v_limit) ((Base.u32_to_nat (0x00010000l))) ([]) (v_next_steps) ((MatchArms (v_arms, v_scrutinees))) (v_context))))))))
| (M.GuardExpr (v_pattern, v_value, v_alternative, v_body)) ->
(match (f_evaluate_work (v_limit) ((Base.u32_to_nat (0x00010000l))) ([]) ((f_spend_budget (v_steps))) ((Expression (v_value))) (v_context)) with
| Fail __error -> Fail __error
| Done v_checked ->
(f_continue_value (v_checked) ((fun v_value ->
(fun v_next_steps ->
(match (f_evaluate_work (v_limit) ((Base.u32_to_nat (0x00010000l))) ([]) (v_next_steps) ((MatchPatterns ((Base.u32_to_nat (0x00010000l)), (Done ((PatternPending ([(PatternValue (v_pattern, v_value))], []))))))) (v_context)) with
| Fail __error -> Fail __error
| Done v_matched ->
(match (f_collected_pattern_bindings ((f_eval_value (v_matched)))) with
| Fail __error -> Fail __error
| Done v_bindings ->
(f_complete_scope ((f_guard_scope (v_bindings) (v_body) (v_alternative) (v_context))) ((f_eval_budget (v_matched))) ((fun v_selected_body ->
(fun v_scope_context ->
(fun v_body_steps ->
(f_evaluate_work (v_limit) ((Base.u32_to_nat (0x00010000l))) ([]) (v_body_steps) ((Expression (v_selected_body))) (v_scope_context))))))))))))))
| (M.BlockExpr (v_label, v_body)) ->
(match (f_evaluate_work (v_limit) ((Base.u32_to_nat (0x00010000l))) ([]) ((f_spend_budget (v_steps))) ((Expression (v_body))) (v_context)) with
| Fail __error -> Fail __error
| Done v_checked ->
(Done ((f_complete_block (v_checked) (v_label)))))
| (M.ReturnExpr (v_label, v_value)) ->
(match (f_evaluate_work (v_limit) ((Base.u32_to_nat (0x00010000l))) ([]) ((f_spend_budget (v_steps))) ((Expression (v_value))) (v_context)) with
| Fail __error -> Fail __error
| Done v_checked ->
(f_continue_value (v_checked) ((fun v_value ->
(fun v_next_steps ->
(Done ((Evaluation ((ReturnValue (v_label, v_value)), v_next_steps)))))))))
| (M.TagExpr (v_offset, v_callee, v_argument)) ->
(match (f_tag_evaluation ((f_evaluate_work (v_limit) ((Base.u32_to_nat (0x00010000l))) ([]) ((f_spend_budget (v_steps))) ((Expression (v_callee))) (v_context))) (v_offset)) with
| Fail __error -> Fail __error
| Done v_checked ->
(f_continue_value (v_checked) ((fun v_function ->
(fun v_argument_steps ->
(match (f_evaluate_work (v_limit) ((Base.u32_to_nat (0x00010000l))) ([]) (v_argument_steps) ((Expression (v_argument))) (v_context)) with
| Fail __error -> Fail __error
| Done v_applied ->
(f_continue_value (v_applied) ((fun v_value ->
(fun v_call_steps ->
(match (f_tag_application ((f_application (v_function) (v_value) (v_context))) (v_offset)) with
| Fail __error -> Fail __error
| Done v_call ->
(match (f_tag_application ((f_resolve_application ((f_context_providers (v_context))) (v_call) (v_context))) (v_offset)) with
| Fail __error -> Fail __error
| Done v_resolved ->
(f_tag_evaluation ((f_complete_application (v_resolved) (v_call_steps) ((fun v_body ->
(fun v_scope ->
(fun v_body_steps ->
(match (f_evaluate_work (v_limit) ((Base.u32_to_nat (0x00010000l))) ([]) (v_body_steps) ((Expression (v_body))) (v_scope)) with
| Fail __error -> Fail __error
| Done v_result ->
(f_complete_definition (v_result))))))))) (v_offset))))))))))))))
| (M.SourceExpr (v_offset, v_annotation, v_value)) ->
(f_evaluate_work (v_limit) ((Base.u32_to_nat (0x00010000l))) ([]) ((f_spend_budget (v_steps))) ((Expression (v_value))) (v_context))))))
and (* const_eval.bend:1102 *)
f_evaluate : int -> int -> M.t_Expr -> t_Context -> (M.t_Diagnostic, t_Evaluation) Base.result_ =
fun v_depth v_steps v_expression v_context ->
(match (v_depth, v_steps) with
| (0, _) ->
(Fail ((f_budget_diagnostic (v_expression))))
| (_, 0) ->
(Fail ((f_budget_diagnostic (v_expression))))
| (__nat_28, __nat_29) when __nat_28 >= 1 && __nat_29 >= 1 ->
(let v_remaining_depth = (__nat_28 - 1) in
(let v_remaining_steps = (__nat_29 - 1) in
(f_evaluate_work ((Base.nat_add 1 v_remaining_depth)) ((Base.u32_to_nat (0x00010000l))) ([]) ((Budget ((Base.nat_add 1 v_remaining_steps), []))) ((Expression (v_expression))) (v_context)))))
and (* const_eval.bend:1112 *)
f_prepend_constant : Base.text -> t_Value -> t_Constants -> t_Constants =
fun v_name v_value v_constants ->
(let (Constants (v_bindings, v_remaining)) = v_constants in
(Constants (((Binding (v_name, v_value)) :: v_bindings), v_remaining)))
and (* const_eval.bend:1116 *)
f_evaluate_constants : (M.t_CheckedConstant) list -> int -> t_Context -> (M.t_Diagnostic, t_Constants) Base.result_ =
fun v_constants v_steps v_context ->
(match v_constants with
| [] ->
(Done ((Constants ([], v_steps))))
| ((M.CheckedConstant ((M.Constant (v_name, v_exported, v_annotation, (M.RuntimeInitExpr (v_value)))), v_ty, v_variables)) :: v_tail) ->
(f_evaluate_constants (v_tail) (v_steps) (v_context))
| ((M.CheckedConstant ((M.Constant (v_name, v_exported, v_annotation, v_value)), v_ty, v_variables)) :: v_tail) ->
(let v_budget = v_steps in
(match (f_evaluate (v_budget) (v_budget) (v_value) (v_context)) with
| Fail __error -> Fail __error
| Done v_checked ->
(match (f_complete_definition (v_checked)) with
| Fail __error -> Fail __error
| Done v_head ->
(match (f_evaluate_constants (v_tail) ((f_eval_remaining (v_head))) (v_context)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done ((f_prepend_constant (v_name) ((f_eval_value (v_head))) (v_rest)))))))))
