(* Native semantic port of compiler/infer.bend.

   Source SHA-256: b7dca6fef944f85bf6a642106d2cf0148d7471b316dc036043a12ae26cdc3577

   Ownership/type arguments are erased; value types are checked by OCaml.

   No Bend interpreter or generated C/JavaScript is linked. *)

open Base

module M = Ox_model

module T = Ox_types

module Index = Ox_index

module D = Ox_type_data

module R = Ox_effect_rows

module Graph = Ox_dependency

module TypedState = Ox_state_specialize

module C = Ox_constraints

type t_Binding =
  | Binding of Base.text * M.t_Ty * (int) list * (M.t_Predicate) list
and t_Label =
  | Label of int * M.t_Ty
and t_Context =
  | Context of (t_Binding) list * (t_Binding) list * (t_Label) list * (M.t_DataType) list * (M.t_Operation) list * Base.text * (Base.text) list * M.t_EffectRow
and t_Reflection =
  | Reflection of Base.text * Base.text * M.t_Ty * (M.t_Predicate) list
and t_Coverage =
  | OperationNeed of int * M.t_TypeId * (M.t_Ty) list * M.t_Ty * Base.text
  | AssociatedNeed of int * M.t_Dispatch * Base.text * (M.t_TypeId) list * M.t_Ty * M.t_Ty * M.t_Ty * (M.t_EffectRow) option * M.t_EffectRow * Base.text
  | ValuePatternType of M.t_Ty * Base.text
  | Coverage of (M.t_Ty) list * ((M.t_Pattern) list) list * Base.text
  | LetGeneralized of M.t_Ty
  | QualifiedNeed of int * M.t_Predicate * Base.text
  | QualifiedBoundary of int * (M.t_Predicate) list * Base.text
and t_Inference =
  | Inference of M.t_Ty * (t_Coverage) list * (int) list * (t_Reflection) list * (M.t_Predicate) list * (C.t_UsePlan) list
and t_State =
  | State of T.t_Substitutions * int * (M.t_Ty) Base.map
and t_Typing =
  | Typing of t_Inference * t_State
and t_Definition =
  | Definition of Base.text * t_Inference
and t_SchemeInstance =
  | SchemeInstance of M.t_Ty * (M.t_Predicate) list * int
and t_PatternTyping =
  | PatternTyping of (t_Binding) list * t_State * (t_Coverage) list
and t_SelectedInstantiation =
  | SelectedInstantiation of t_Typing * M.t_Ty
and t_Generalization =
  | Generalization of t_Binding * (int) list
and t_QualifiedAnnotation =
  | QualifiedAnnotation of M.t_Ty * (M.t_Predicate) list * t_State
and t_OperationArguments =
  | OperationArguments of (M.t_Ty) list * t_State
and t_PatternWork =
  | PatternValue of M.t_Pattern * M.t_Ty
  | PatternFields of (M.t_Pattern) list * (M.t_Ty) list
and t_Work =
  | Expression of M.t_Expr
  | MatchArms of ((M.t_Expr) M.t_MatchArm) list * (M.t_Ty) list
  | MatchValues of (M.t_Expr) list * (M.t_Ty) list * ((M.t_Expr) M.t_MatchArm) list * t_Inference
  | ProductValues of (M.t_Expr) list * (M.t_Ty) list * t_Inference
  | ArrayValues of (M.t_Expr) list * M.t_Ty * t_Inference
and t_Provider =
  | Provider of (M.t_TypeId) list * M.t_EffectRow * (M.t_Ty) option

let s_0 = Base.text_of_utf8 "resolved reference has the wrong definition kind: "

let s_1 = Base.text_of_utf8 "unknown_function"

let s_2 = Base.text_of_utf8 "unknown_name"

let s_3 = Base.text_of_utf8 "invalid_return"

let s_4 = Base.text_of_utf8 "return target is not an enclosing do block"

let s_5 = Base.text_of_utf8 "unknown value "

let s_6 = Base.text_of_utf8 ""

let s_7 = Base.text_of_utf8 ":"

let s_8 = Base.text_of_utf8 "internal_error"

let s_9 = Base.text_of_utf8 "annotation"

let s_10 = Base.text_of_utf8 "free annotation name traversal returned a concrete type"

let s_11 = Base.text_of_utf8 "source annotation name did not resolve to a variable"

let s_12 = Base.text_of_utf8 "free qualified name traversal returned a concrete type"

let s_13 = Base.text_of_utf8 "unknown_effect"

let s_14 = Base.text_of_utf8 "no declaration defines this generic effect operation"

let s_15 = Base.text_of_utf8 "generic operation requires a template declaration"

let s_16 = Base.text_of_utf8 "effect_arity"

let s_17 = Base.text_of_utf8 "generic operation predicate has the wrong type argument count"

let s_18 = Base.text_of_utf8 "operation predicate expected a generic template"

let s_19 = Base.text_of_utf8 "different_predicate"

let s_20 = Base.text_of_utf8 "predicate member or kind differs"

let s_21 = Base.text_of_utf8 "missing_predicate"

let s_22 = Base.text_of_utf8 "inferred requirement is absent from the explicit where clause"

let s_23 = Base.text_of_utf8 "explicit where clause has no matching requirement"

let s_24 = Base.text_of_utf8 "constructor_arity"

let s_25 = Base.text_of_utf8 "nullary constructor does not accept a payload"

let s_26 = Base.text_of_utf8 "constructor requires a payload"

let s_27 = Base.text_of_utf8 "duplicate_pattern_binding"

let s_28 = Base.text_of_utf8 "pattern row binds "

let s_29 = Base.text_of_utf8 " more than once"

let s_30 = Base.text_of_utf8 "qualified_pattern"

let s_31 = Base.text_of_utf8 "an open qualified value cannot be used as a pattern until its evidence is selected"

let s_32 = Base.text_of_utf8 "pattern_complexity"

let s_33 = Base.text_of_utf8 "pattern typing exceeds compiler traversal limit"

let s_34 = Base.text_of_utf8 "product pattern fields lost their inferred types"

let s_35 = Base.text_of_utf8 "guard_fallthrough"

let s_36 = Base.text_of_utf8 "let-else fallback must exit its enclosing do block"

let s_37 = Base.text_of_utf8 "pure evaluation cannot perform "

let s_38 = Base.text_of_utf8 "; sequence an operation with use inside a provider scope"

let s_39 = Base.text_of_utf8 "match_arity"

let s_40 = Base.text_of_utf8 "every pattern row must match the scrutinee count"

let s_41 = Base.text_of_utf8 "invalid_provider"

let s_42 = Base.text_of_utf8 "do requires a provider with a known nominal operation, got "

let s_43 = Base.text_of_utf8 "invalid_state_provider"

let s_44 = Base.text_of_utf8 "state read and write must be distinct operations"

let s_45 = Base.text_of_utf8 "product_index"

let s_46 = Base.text_of_utf8 "product projection index is outside its fixed arity"

let s_47 = Base.text_of_utf8 "unknown_product_shape"

let s_48 = Base.text_of_utf8 "projection requires a known product arity; annotate the parameter with a product type"

let s_49 = Base.text_of_utf8 "type_mismatch"

let s_50 = Base.text_of_utf8 "projection requires a product, got "

let s_51 = Base.text_of_utf8 "$operation"

let s_52 = Base.text_of_utf8 "$associated"

let s_53 = Base.text_of_utf8 "offset:"

let s_54 = Base.text_of_utf8 "expression_complexity"

let s_55 = Base.text_of_utf8 "expression nesting exceeds compiler traversal limit"

let s_56 = Base.text_of_utf8 "@type.same"

let s_57 = Base.text_of_utf8 "let_effect"

let s_58 = Base.text_of_utf8 "case requires at least one scrutinee"

let s_59 = Base.text_of_utf8 "unspecialized_effect"

let s_60 = Base.text_of_utf8 "effect"

let s_61 = Base.text_of_utf8 "effect instance reached inference before specialization"

let rec (* infer.bend:58 *)
f_inferred_type : t_Inference -> M.t_Ty =
fun v_inference ->
(let (Inference (v_ty, v_coverage, v_exits, v_reflections, v_predicates, v_uses)) = v_inference in
v_ty)
and (* infer.bend:62 *)
f_inference_coverage : t_Inference -> (t_Coverage) list =
fun v_inference ->
(let (Inference (v_ty, v_coverage, v_exits, v_reflections, v_predicates, v_uses)) = v_inference in
v_coverage)
and (* infer.bend:66 *)
f_inference_predicates : t_Inference -> (M.t_Predicate) list =
fun v_inference ->
(let (Inference (v_ty, v_coverage, v_exits, v_reflections, v_predicates, v_uses)) = v_inference in
v_predicates)
and (* infer.bend:70 *)
f_inference_uses : t_Inference -> (C.t_UsePlan) list =
fun v_inference ->
(let (Inference (v_ty, v_coverage, v_exits, v_reflections, v_predicates, v_uses)) = v_inference in
v_uses)
and (* infer.bend:74 *)
f_with_predicate : t_Inference -> M.t_Predicate -> t_Inference =
fun v_inference v_predicate ->
(let (Inference (v_ty, v_coverage, v_exits, v_reflections, v_predicates, v_uses)) = v_inference in
(Inference (v_ty, v_coverage, v_exits, v_reflections, (v_predicate :: v_predicates), v_uses)))
and (* infer.bend:78 *)
f_with_use : t_Inference -> int -> Base.text -> t_Inference =
fun v_inference v_site v_subject ->
(let (Inference (v_ty, v_coverage, v_exits, v_reflections, v_predicates, v_uses)) = v_inference in
(Inference (v_ty, v_coverage, v_exits, v_reflections, v_predicates, ((C.UsePlan (v_site, v_subject, v_ty, (C.f_unplanned (v_uses) (v_predicates)))) :: v_uses))))
and (* infer.bend:82 *)
f_without_residual : t_Inference -> t_Inference =
fun v_inference ->
(let (Inference (v_ty, v_coverage, v_exits, v_reflections, v_predicates, v_uses)) = v_inference in
(Inference (v_ty, v_coverage, v_exits, v_reflections, [], v_uses)))
and (* infer.bend:86 *)
f_plan_needs_reversed : (M.t_Predicate) list -> int -> Base.text -> (t_Coverage) list -> (t_Coverage) list =
fun v_predicates v_site v_subject v_reversed ->
(match v_predicates with
| [] ->
v_reversed
| (v_head :: v_tail) ->
(f_plan_needs_reversed (v_tail) (v_site) (v_subject) (((QualifiedNeed (v_site, v_head, v_subject)) :: v_reversed))))
and (* infer.bend:93 *)
f_plan_needs : C.t_UsePlan -> (t_Coverage) list =
fun v_plan ->
(let (C.UsePlan (v_site, v_subject, v_ty, v_predicates)) = v_plan in
(Base.list_reverse ((f_plan_needs_reversed (v_predicates) (v_site) (v_subject) ([])))))
and (* infer.bend:97 *)
f_execution_needs_reversed : (C.t_UsePlan) list -> (t_Coverage) list -> (t_Coverage) list =
fun v_uses v_reversed ->
(match v_uses with
| [] ->
(Base.list_reverse (v_reversed))
| ((C.UsePlan (v_site, v_subject, v_ty, v_predicates)) :: v_tail) ->
(f_execution_needs_reversed (v_tail) ((f_plan_needs_reversed (v_predicates) (v_site) (v_subject) (v_reversed)))))
and (* infer.bend:104 *)
f_execution_needs : (C.t_UsePlan) list -> (t_Coverage) list =
fun v_uses ->
(f_execution_needs_reversed (v_uses) ([]))
and (* infer.bend:107 *)
f_inference_of : t_Typing -> t_Inference =
fun v_typing ->
(let (Typing (v_inference, v_state)) = v_typing in
v_inference)
and (* infer.bend:111 *)
f_state_of : t_Typing -> t_State =
fun v_typing ->
(let (Typing (v_inference, v_state)) = v_typing in
v_state)
and (* infer.bend:115 *)
f_type_of : t_Typing -> M.t_Ty =
fun v_typing ->
(f_inferred_type ((f_inference_of (v_typing))))
and (* infer.bend:118 *)
f_next_of : t_State -> int =
fun v_state ->
(let (State (v_substitutions, v_next, v_annotations)) = v_state in
v_next)
and (* infer.bend:122 *)
f_substitutions_of : t_State -> T.t_Substitutions =
fun v_state ->
(let (State (v_substitutions, v_next, v_annotations)) = v_state in
v_substitutions)
and (* infer.bend:126 *)
f_with_next : t_State -> int -> t_State =
fun v_state v_next ->
(let (State (v_substitutions, v_previous, v_annotations)) = v_state in
(State (v_substitutions, v_next, v_annotations)))
and (* infer.bend:130 *)
f_pure : M.t_Ty -> t_Inference =
fun v_ty ->
(Inference (v_ty, [], [], [], [], []))
and (* infer.bend:135 *)
f_append_predicates : (M.t_Predicate) list -> (M.t_Predicate) list -> (M.t_Predicate) list =
fun v_left v_right ->
(Base.list_reverse_go ((Base.list_reverse (v_left))) (v_right))
and (* infer.bend:138 *)
f_join : t_Inference -> t_Inference -> M.t_Ty -> t_Inference =
fun v_left v_right v_ty ->
(let (Inference (v_lt, v_lc, v_lx, v_lr, v_lp, v_lu)) = v_left in
(let (Inference (v_rt, v_rc, v_rx, v_rr, v_rp, v_ru)) = v_right in
(Inference (v_ty, (Base.list_append (v_lc) (v_rc)), (T.f_union (v_lx) (v_rx)), (Base.list_append (v_lr) (v_rr)), (f_append_predicates (v_lp) (v_rp)), (Base.list_append (v_lu) (v_ru))))))
and (* infer.bend:143 *)
f_reachable_exits : M.t_Ty -> (int) list -> (int) list -> (int) list =
fun v_ty v_left v_right ->
(match v_ty with
| M.NeverTy ->
v_left
| _ ->
(T.f_union (v_left) (v_right)))
and (* infer.bend:150 *)
f_sequence : t_Inference -> t_Inference -> M.t_Ty -> t_Inference =
fun v_left v_right v_ty ->
(let (Inference (v_lt, v_lc, v_lx, v_lr, v_lp, v_lu)) = v_left in
(let (Inference (v_rt, v_rc, v_rx, v_rr, v_rp, v_ru)) = v_right in
(Inference (v_ty, (Base.list_append (v_lc) (v_rc)), (f_reachable_exits (v_lt) (v_lx) (v_rx)), (Base.list_append (v_lr) (v_rr)), (f_append_predicates (v_lp) (v_rp)), (Base.list_append (v_lu) (v_ru))))))
and (* infer.bend:155 *)
f_lambda_value : t_Inference -> M.t_Ty -> M.t_Ty -> M.t_EffectRow -> t_Inference =
fun v_inference v_parameter v_result v_effects ->
(let (Inference (v_ty, v_coverage, v_exits, v_reflections, v_predicates, v_uses)) = v_inference in
(Inference ((M.FunctionTy (v_parameter, v_result, v_effects)), v_coverage, [], v_reflections, v_predicates, v_uses)))
and (* infer.bend:159 *)
f_add_coverage : t_Inference -> (M.t_Ty) list -> ((M.t_Pattern) list) list -> Base.text -> t_Inference =
fun v_inference v_types v_patterns v_subject ->
(let (Inference (v_result, v_coverage, v_exits, v_reflections, v_predicates, v_uses)) = v_inference in
(Inference (v_result, ((Coverage (v_types, v_patterns, v_subject)) :: v_coverage), v_exits, v_reflections, v_predicates, v_uses)))
and (* infer.bend:163 *)
f_block_result : bool -> M.t_Ty -> M.t_Ty -> M.t_Ty =
fun v_caught v_body v_result ->
(match v_caught with
| true ->
v_result
| false ->
v_body)
and (* infer.bend:170 *)
f_block_value : t_Inference -> int -> M.t_Ty -> t_Inference =
fun v_inference v_label v_result ->
(let (Inference (v_ty, v_coverage, v_exits, v_reflections, v_predicates, v_uses)) = v_inference in
(Inference ((f_block_result ((T.f_contains (v_exits) (v_label))) (v_ty) (v_result)), v_coverage, (T.f_difference (v_exits) ([v_label])), v_reflections, v_predicates, v_uses)))
and (* infer.bend:174 *)
f_return_value : t_Inference -> int -> t_Inference =
fun v_inference v_label ->
(let (Inference (v_ty, v_coverage, v_exits, v_reflections, v_predicates, v_uses)) = v_inference in
(Inference (M.NeverTy, v_coverage, (f_reachable_exits (v_ty) (v_exits) ([v_label])), v_reflections, v_predicates, v_uses)))
and (* infer.bend:178 *)
f_flow : M.t_Ty -> M.t_Ty -> M.t_Ty =
fun v_first v_next ->
(match v_first with
| M.NeverTy ->
M.NeverTy
| _ ->
v_next)
and (* infer.bend:185 *)
f_branch_type : M.t_Ty -> M.t_Ty -> M.t_Ty =
fun v_left v_right ->
(match v_left with
| M.NeverTy ->
v_right
| v_other ->
v_other)
and (* infer.bend:192 *)
f_solved_state : T.t_Solution -> (M.t_Ty) Base.map -> t_State =
fun v_solution v_annotations ->
(let (T.Solution (v_substitutions, v_next)) = v_solution in
(State (v_substitutions, v_next, v_annotations)))
and (* infer.bend:196 *)
f_unify : M.t_Ty -> M.t_Ty -> t_State -> Base.text -> (M.t_Diagnostic, t_State) Base.result_ =
fun v_left v_right v_state v_subject ->
(let (State (v_substitutions, v_next, v_annotations)) = v_state in
(match (T.f_unify_at (v_left) (v_right) (v_substitutions) (v_next) (v_subject)) with
| Fail __error -> Fail __error
| Done v_solved ->
(Done ((f_solved_state (v_solved) (v_annotations))))))
and (* infer.bend:202 *)
f_unify_rows : M.t_EffectRow -> M.t_EffectRow -> t_State -> Base.text -> (M.t_Diagnostic, t_State) Base.result_ =
fun v_left v_right v_state v_subject ->
(let (State (v_substitutions, v_next, v_annotations)) = v_state in
(match (T.f_unify_rows_at (v_left) (v_right) (v_substitutions) (v_next) (v_subject)) with
| Fail __error -> Fail __error
| Done v_solved ->
(Done ((f_solved_state (v_solved) (v_annotations))))))
and (* infer.bend:208 *)
f_context_subject : t_Context -> Base.text =
fun v_context ->
(let (Context (v_globals, v_locals, v_labels, v_types, v_operations, v_subject, v_functions, v_ambient)) = v_context in
v_subject)
and (* infer.bend:212 *)
f_context_types : t_Context -> (M.t_DataType) list =
fun v_context ->
(let (Context (v_globals, v_locals, v_labels, v_types, v_operations, v_subject, v_functions, v_ambient)) = v_context in
v_types)
and (* infer.bend:216 *)
f_context_operations : t_Context -> (M.t_Operation) list =
fun v_context ->
(let (Context (v_globals, v_locals, v_labels, v_types, v_operations, v_subject, v_functions, v_ambient)) = v_context in
v_operations)
and (* infer.bend:220 *)
f_context_row : t_Context -> M.t_EffectRow =
fun v_context ->
(let (Context (v_globals, v_locals, v_labels, v_types, v_operations, v_subject, v_functions, v_ambient)) = v_context in
v_ambient)
and (* infer.bend:224 *)
f_with_row : t_Context -> M.t_EffectRow -> t_Context =
fun v_context v_ambient ->
(let (Context (v_globals, v_locals, v_labels, v_types, v_operations, v_subject, v_functions, v_previous)) = v_context in
(Context (v_globals, v_locals, v_labels, v_types, v_operations, v_subject, v_functions, v_ambient)))
and (* infer.bend:228 *)
f_at_subject : t_Context -> Base.text -> t_Context =
fun v_context v_subject ->
(let (Context (v_globals, v_locals, v_labels, v_types, v_operations, v_previous, v_functions, v_ambient)) = v_context in
(Context (v_globals, v_locals, v_labels, v_types, v_operations, v_subject, v_functions, v_ambient)))
and (* infer.bend:232 *)
f_extend : t_Context -> (t_Binding) list -> t_Context =
fun v_context v_bindings ->
(let (Context (v_globals, v_locals, v_labels, v_types, v_operations, v_subject, v_functions, v_ambient)) = v_context in
(Context (v_globals, (Base.list_append (v_bindings) (v_locals)), v_labels, v_types, v_operations, v_subject, v_functions, v_ambient)))
and (* infer.bend:236 *)
f_in_lambda : t_Context -> Base.text -> M.t_Ty -> M.t_EffectRow -> t_Context =
fun v_context v_name v_ty v_ambient ->
(let (Context (v_globals, v_locals, v_labels, v_types, v_operations, v_subject, v_functions, v_previous)) = v_context in
(Context (v_globals, ((Binding (v_name, v_ty, [], [])) :: v_locals), [], v_types, v_operations, v_subject, v_functions, v_ambient)))
and (* infer.bend:240 *)
f_in_block : t_Context -> int -> M.t_Ty -> t_Context =
fun v_context v_label v_ty ->
(let (Context (v_globals, v_locals, v_labels, v_types, v_operations, v_subject, v_functions, v_ambient)) = v_context in
(Context (v_globals, v_locals, ((Label (v_label, v_ty)) :: v_labels), v_types, v_operations, v_subject, v_functions, v_ambient)))
and (* infer.bend:244 *)
f_lookup_binding_work : (t_Binding) list -> Base.text -> (t_Binding) option -> (t_Binding) option =
fun v_bindings v_name v_found ->
(match (v_bindings, v_found) with
| (_, (Some (v_binding))) ->
(Some (v_binding))
| ([], None) ->
None
| (((Binding (v_declared, v_ty, v_variables, v_predicates)) :: v_tail), None) ->
(f_lookup_binding_work (v_tail) (v_name) ((Base.bool_pick ((M.f_name_equal (v_declared) (v_name))) ((Some ((Binding (v_declared, v_ty, v_variables, v_predicates))))) (None)))))
and (* infer.bend:253 *)
f_lookup_binding : (t_Binding) list -> Base.text -> (t_Binding) option =
fun v_bindings v_name ->
(f_lookup_binding_work (v_bindings) (v_name) (None))
and (* infer.bend:256 *)
f_lookup_global : t_Context -> Base.text -> (t_Binding) option =
fun v_context v_name ->
(let (Context (v_globals, v_locals, v_labels, v_types, v_operations, v_subject, v_functions, v_ambient)) = v_context in
(f_lookup_binding (v_globals) (v_name)))
and (* infer.bend:260 *)
f_lookup_local : t_Context -> Base.text -> (t_Binding) option =
fun v_context v_name ->
(let (Context (v_globals, v_locals, v_labels, v_types, v_operations, v_subject, v_functions, v_ambient)) = v_context in
(f_lookup_binding (v_locals) (v_name)))
and (* infer.bend:264 *)
f_valid_global_kind : t_Context -> Base.text -> bool -> (M.t_Diagnostic, unit) Base.result_ =
fun v_context v_name v_function ->
(let (Context (v_globals, v_locals, v_labels, v_types, v_operations, v_subject, v_functions, v_ambient)) = v_context in
(let v_found = (Graph.f_contains (v_functions) (v_name)) in
(let v_expected = v_function in
(let v_code = (Base.bool_pick (v_expected) (s_1) (s_2)) in
(Base.bool_pick ((Base.bool_not ((Base.bool_xor (v_found) (v_expected))))) ((Done (()))) ((Fail ((M.Diagnostic (v_code, v_subject, (Base.string_append s_0 v_name)))))))))))
and (* infer.bend:271 *)
f_lookup_label : (t_Label) list -> int -> Base.text -> (M.t_Diagnostic, M.t_Ty) Base.result_ =
fun v_labels v_identity v_subject ->
(match v_labels with
| [] ->
(Fail ((M.Diagnostic (s_3, v_subject, s_4))))
| ((Label (v_found, v_ty)) :: v_tail) ->
(Base.bool_pick ((Base.nat_is_eq (v_found) (v_identity))) ((Done (v_ty))) ((f_lookup_label (v_tail) (v_identity) (v_subject)))))
and (* infer.bend:278 *)
f_return_type : t_Context -> int -> (M.t_Diagnostic, M.t_Ty) Base.result_ =
fun v_context v_identity ->
(let (Context (v_globals, v_locals, v_labels, v_types, v_operations, v_subject, v_functions, v_ambient)) = v_context in
(f_lookup_label (v_labels) (v_identity) (v_subject)))
and (* infer.bend:282 *)
f_instance_sequential : (int) list -> M.t_Ty -> (M.t_Predicate) list -> int -> (M.t_Diagnostic, t_SchemeInstance) Base.result_ =
fun v_variables v_ty v_predicates v_next ->
(match v_variables with
| [] ->
(Done ((SchemeInstance (v_ty, v_predicates, v_next))))
| (v_head :: v_tail) ->
(match (T.f_replace (v_ty) (v_head) ((M.VariableTy (v_next)))) with
| Fail __error -> Fail __error
| Done v_replaced ->
(match (C.f_replace_variable (v_predicates) (v_head) (v_next)) with
| Fail __error -> Fail __error
| Done v_needs ->
(f_instance_sequential (v_tail) (v_replaced) (v_needs) ((Base.nat_add 1 v_next))))))
and (* infer.bend:292 *)
f_instance_mapped : T.t_Renaming -> (int) list -> M.t_Ty -> (M.t_Predicate) list -> int -> (M.t_Diagnostic, t_SchemeInstance) Base.result_ =
fun v_renaming v_binders v_ty v_predicates v_next ->
(match v_renaming with
| (T.Renaming (v_mapping, v_fresh_next, true)) ->
(match (T.f_rename_type (v_ty) (v_mapping)) with
| Fail __error -> Fail __error
| Done v_renamed ->
(match (C.f_rename_list (v_mapping) (v_predicates)) with
| Fail __error -> Fail __error
| Done v_needs ->
(Done ((SchemeInstance (v_renamed, v_needs, v_fresh_next))))))
| (T.Renaming (v_mapping, v_fresh_next, false)) ->
(f_instance_sequential (v_binders) (v_ty) (v_predicates) (v_next)))
and (* infer.bend:302 *)
f_instance_qualified : (int) list -> M.t_Ty -> (M.t_Predicate) list -> int -> (M.t_Diagnostic, t_SchemeInstance) Base.result_ =
fun v_variables v_ty v_predicates v_next ->
(match v_variables with
| [] ->
(Done ((SchemeInstance (v_ty, v_predicates, v_next))))
| (v_head :: []) ->
(match (T.f_replace (v_ty) (v_head) ((M.VariableTy (v_next)))) with
| Fail __error -> Fail __error
| Done v_renamed ->
(match (C.f_replace_variable (v_predicates) (v_head) (v_next)) with
| Fail __error -> Fail __error
| Done v_needs ->
(Done ((SchemeInstance (v_renamed, v_needs, (Base.nat_add 1 v_next)))))))
| (v_head :: v_tail) ->
(let v_binders = (v_head :: v_tail) in
(f_instance_mapped ((T.f_renaming (v_binders) (v_next))) (v_binders) (v_ty) (v_predicates) (v_next))))
and (* infer.bend:315 *)
f_instance : (int) list -> M.t_Ty -> int -> (M.t_Diagnostic, t_SchemeInstance) Base.result_ =
fun v_variables v_ty v_next ->
(f_instance_qualified (v_variables) (v_ty) ([]) (v_next))
and (* infer.bend:318 *)
f_instance_typing : t_SchemeInstance -> T.t_Substitutions -> (M.t_Ty) Base.map -> (M.t_Diagnostic, t_Typing) Base.result_ =
fun v_value v_substitutions v_annotations ->
(let (SchemeInstance (v_ty, v_predicates, v_next)) = v_value in
(match (T.f_open_covariant (v_ty) (v_next)) with
| Fail __error -> Fail __error
| Done v_opened ->
(Done ((Typing ((Inference ((T.f_opened_type (v_opened)), [], [], [], v_predicates, [])), (State (v_substitutions, (T.f_opened_next (v_opened)), v_annotations))))))))
and (* infer.bend:330 *)
f_selected_typing : t_SelectedInstantiation -> t_Typing =
fun v_value ->
(let (SelectedInstantiation (v_typing, v_exact)) = v_value in
v_typing)
and (* infer.bend:334 *)
f_selected_exact : t_SelectedInstantiation -> M.t_Ty =
fun v_value ->
(let (SelectedInstantiation (v_typing, v_exact)) = v_value in
v_exact)
and (* infer.bend:338 *)
f_selected_instance : t_SchemeInstance -> T.t_Substitutions -> (M.t_Ty) Base.map -> (M.t_Diagnostic, t_SelectedInstantiation) Base.result_ =
fun v_value v_substitutions v_annotations ->
(let (SchemeInstance (v_inferred_type, v_needs, v_fresh_next)) = v_value in
(match (T.f_open_covariant (v_inferred_type) (v_fresh_next)) with
| Fail __error -> Fail __error
| Done v_opened ->
(Done ((SelectedInstantiation ((Typing ((Inference ((T.f_opened_type (v_opened)), [], [], [], v_needs, [])), (State (v_substitutions, (T.f_opened_next (v_opened)), v_annotations)))), v_inferred_type))))))
and (* infer.bend:344 *)
f_instantiate_binding_selected : (t_Binding) option -> t_State -> Base.text -> Base.text -> (M.t_Diagnostic, t_SelectedInstantiation) Base.result_ =
fun v_found v_state v_name v_subject ->
(match v_found with
| None ->
(Fail ((M.Diagnostic (s_2, v_subject, (Base.string_append s_5 v_name)))))
| (Some ((Binding (v_binding_name, v_ty, v_variables, v_predicates)))) ->
(let (State (v_substitutions, v_next, v_annotations)) = v_state in
(match (T.f_resolve (v_substitutions) (v_ty)) with
| Fail __error -> Fail __error
| Done v_resolved ->
(match (C.f_resolve_list (v_substitutions) (v_predicates)) with
| Fail __error -> Fail __error
| Done v_needs ->
(match (f_instance_qualified (v_variables) (v_resolved) (v_needs) (v_next)) with
| Fail __error -> Fail __error
| Done v_instantiated ->
(f_selected_instance (v_instantiated) (v_substitutions) (v_annotations)))))))
and (* infer.bend:356 *)
f_instantiate_binding : (t_Binding) option -> t_State -> Base.text -> Base.text -> (M.t_Diagnostic, t_Typing) Base.result_ =
fun v_found v_state v_name v_subject ->
(match v_found with
| None ->
(Fail ((M.Diagnostic (s_2, v_subject, (Base.string_append s_5 v_name)))))
| (Some ((Binding (v_binding_name, v_ty, v_variables, v_predicates)))) ->
(let (State (v_substitutions, v_next, v_annotations)) = v_state in
(match (T.f_resolve (v_substitutions) (v_ty)) with
| Fail __error -> Fail __error
| Done v_resolved ->
(match (C.f_resolve_list (v_substitutions) (v_predicates)) with
| Fail __error -> Fail __error
| Done v_needs ->
(match (f_instance_qualified (v_variables) (v_resolved) (v_needs) (v_next)) with
| Fail __error -> Fail __error
| Done v_instantiated ->
(f_instance_typing (v_instantiated) (v_substitutions) (v_annotations)))))))
and (* infer.bend:368 *)
f_associated_witness_shape : M.t_Ty -> M.t_Ty -> t_State -> Base.text -> (M.t_Diagnostic, t_State) Base.result_ =
fun v_witness v_result v_state v_subject ->
(match v_witness with
| (M.VariableTy (v_index)) ->
(Done (v_state))
| (M.ParameterTy (v_index)) ->
(Done (v_state))
| v_other ->
(f_unify (v_result) (v_other) (v_state) (v_subject)))
and (* infer.bend:379 *)
f_associated_shape : bool -> (TypedState.t_Request) option -> M.t_Ty -> M.t_Ty -> M.t_Ty -> t_State -> Base.text -> (M.t_Diagnostic, t_State) Base.result_ =
fun v_same v_request v_left v_right v_result v_state v_subject ->
(match (v_same, v_request) with
| (_, (Some (TypedState.Write))) ->
(f_unify (v_result) (M.UnitTy) (v_state) (v_subject))
| (true, _) ->
(f_unify (v_result) (M.BoolTy) (v_state) (v_subject))
| (_, (Some (TypedState.Run))) ->
(let v_body_result = (M.VariableTy ((f_next_of (v_state)))) in
(let v_body_row = (R.f_variable_row ((Base.nat_add 1 (f_next_of (v_state))))) in
(match (f_unify (v_right) ((M.FunctionTy (M.UnitTy, v_body_result, v_body_row))) ((f_with_next (v_state) ((Base.nat_add 2 (f_next_of (v_state)))))) (v_subject)) with
| Fail __error -> Fail __error
| Done v_callback ->
(f_unify (v_result) ((M.ProductTy ([v_left; v_body_result]))) (v_callback) (v_subject)))))
| (_, (Some (TypedState.Reader))) ->
(let v_implementation = (M.VariableTy ((f_next_of (v_state)))) in
(let v_body_row = (R.f_variable_row ((Base.nat_add 1 (f_next_of (v_state))))) in
(f_unify (v_right) ((M.ProductTy ([v_implementation; (M.FunctionTy (M.UnitTy, v_result, v_body_row))]))) ((f_with_next (v_state) ((Base.nat_add 2 (f_next_of (v_state)))))) (v_subject))))
| (_, (Some (TypedState.Writer))) ->
(let v_implementation = (M.VariableTy ((f_next_of (v_state)))) in
(let v_body_row = (R.f_variable_row ((Base.nat_add 1 (f_next_of (v_state))))) in
(f_unify (v_right) ((M.ProductTy ([v_implementation; (M.FunctionTy (M.UnitTy, v_result, v_body_row))]))) ((f_with_next (v_state) ((Base.nat_add 2 (f_next_of (v_state)))))) (v_subject))))
| (_, (Some (TypedState.Read))) ->
(match (T.f_resolve ((f_substitutions_of (v_state))) (v_left)) with
| Fail __error -> Fail __error
| Done v_witnessed ->
(f_associated_witness_shape ((TypedState.f_witness (65536) (v_witnessed))) (v_result) (v_state) (v_subject)))
| (_, _) ->
(Done (v_state)))
and (* infer.bend:406 *)
f_binding_free : (t_Binding) list -> T.t_Substitutions -> (M.t_Diagnostic, (int) list) Base.result_ =
fun v_bindings v_substitutions ->
(match v_bindings with
| [] ->
(Done ([]))
| ((Binding (v_name, v_ty, v_variables, v_predicates)) :: v_tail) ->
(match (T.f_resolve (v_substitutions) (v_ty)) with
| Fail __error -> Fail __error
| Done v_resolved ->
(match (T.f_free (v_resolved)) with
| Fail __error -> Fail __error
| Done v_free ->
(match (C.f_resolve_list (v_substitutions) (v_predicates)) with
| Fail __error -> Fail __error
| Done v_resolved_predicates ->
(match (C.f_free_list (v_resolved_predicates)) with
| Fail __error -> Fail __error
| Done v_predicate_free ->
(match (f_binding_free (v_tail) (v_substitutions)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done ((T.f_union ((T.f_difference ((T.f_union (v_free) (v_predicate_free))) (v_variables))) (v_rest))))))))))
and (* infer.bend:419 *)
f_label_bindings : (t_Label) list -> (t_Binding) list =
fun v_labels ->
(match v_labels with
| [] ->
[]
| ((Label (v_identity, v_result)) :: v_tail) ->
((Binding (s_6, v_result, [], [])) :: (f_label_bindings (v_tail))))
and (* infer.bend:426 *)
f_environment_bindings : t_Context -> (t_Binding) list =
fun v_context ->
(let (Context (v_globals, v_locals, v_labels, v_types, v_operations, v_subject, v_functions, v_ambient)) = v_context in
(Base.list_append (v_globals) ((Base.list_append (v_locals) ((f_label_bindings (v_labels)))))))
and (* infer.bend:430 *)
f_annotation_bindings : (M.t_Ty) list -> (t_Binding) list =
fun v_types ->
(match v_types with
| [] ->
[]
| (v_ty :: v_rest) ->
((Binding (s_6, v_ty, [], [])) :: (f_annotation_bindings (v_rest))))
and (* infer.bend:437 *)
f_annotation_types : t_State -> (M.t_Ty) list =
fun v_state ->
(let (State (v_substitutions, v_next, v_annotations)) = v_state in
(Base.map_values (v_annotations)))
and (* infer.bend:441 *)
f_clear_annotations : t_State -> t_State =
fun v_state ->
(let (State (v_substitutions, v_next, v_annotations)) = v_state in
(State (v_substitutions, v_next, MTip)))
and (* infer.bend:448 *)
f_restore_annotations : t_State -> t_State -> t_State =
fun v_state v_prior ->
(let (State (v_substitutions, v_next, v_current)) = v_state in
(let (State (v_old_substitutions, v_old_next, v_annotations)) = v_prior in
(State (v_substitutions, v_next, v_annotations))))
and (* infer.bend:456 *)
f_local_annotation_state : M.t_Expr -> t_State -> t_State -> t_State =
fun v_value v_state v_prior ->
(match v_value with
| (M.SourceExpr (v_offset, (Some (v_annotation)), v_body)) ->
(f_restore_annotations (v_state) (v_prior))
| (M.SourceExpr (v_offset, None, (M.QualifiedExpr (v_qualified_offset, v_annotation, v_predicates, v_body)))) ->
(f_restore_annotations (v_state) (v_prior))
| v_other ->
v_state)
and (* infer.bend:470 *)
f_generalization_binding : t_Generalization -> t_Binding =
fun v_generalized ->
(let (Generalization (v_binding, v_variables)) = v_generalized in
v_binding)
and (* infer.bend:474 *)
f_generalization_variables : t_Generalization -> (int) list =
fun v_generalized ->
(let (Generalization (v_binding, v_variables)) = v_generalized in
v_variables)
and (* infer.bend:478 *)
f_generalization_qualified_excluding : M.t_Ty -> (M.t_Predicate) list -> t_Context -> t_State -> Base.text -> (int) list -> (M.t_Diagnostic, t_Generalization) Base.result_ =
fun v_ty v_predicates v_context v_state v_name v_blocked ->
(match (T.f_resolve ((f_substitutions_of (v_state))) (v_ty)) with
| Fail __error -> Fail __error
| Done v_resolved ->
(match (C.f_resolve_list ((f_substitutions_of (v_state))) (v_predicates)) with
| Fail __error -> Fail __error
| Done v_resolved_needs ->
(let v_needs = (C.f_canonical_predicates (v_resolved_needs) ([])) in
(match (T.f_free (v_resolved)) with
| Fail __error -> Fail __error
| Done v_type_free ->
(match (C.f_free_list (v_needs)) with
| Fail __error -> Fail __error
| Done v_predicate_free ->
(match (f_binding_free ((Base.list_append ((f_environment_bindings (v_context))) ((f_annotation_bindings ((f_annotation_types (v_state))))))) ((f_substitutions_of (v_state)))) with
| Fail __error -> Fail __error
| Done v_excluded ->
(let v_variables = (T.f_difference ((T.f_union (v_type_free) (v_predicate_free))) ((T.f_union (v_blocked) ((T.f_union (v_excluded) ((T.f_row_free ((T.f_resolve_row ((f_substitutions_of (v_state))) ((f_context_row (v_context)))))))))))) in
(match (T.f_close_covariant (v_resolved) (v_variables) (v_predicate_free)) with
| Fail __error -> Fail __error
| Done v_closed ->
(match (T.f_free (v_closed)) with
| Fail __error -> Fail __error
| Done v_remaining ->
(Done ((Generalization ((Binding (v_name, v_closed, (T.f_difference (v_variables) ((T.f_difference (v_variables) ((T.f_union (v_remaining) (v_predicate_free)))))), v_needs)), v_variables)))))))))))))
and (* infer.bend:491 *)
f_generalization_qualified : M.t_Ty -> (M.t_Predicate) list -> t_Context -> t_State -> Base.text -> (M.t_Diagnostic, t_Generalization) Base.result_ =
fun v_ty v_predicates v_context v_state v_name ->
(f_generalization_qualified_excluding (v_ty) (v_predicates) (v_context) (v_state) (v_name) ([]))
and (* infer.bend:494 *)
f_generalization : M.t_Ty -> t_Context -> t_State -> Base.text -> (M.t_Diagnostic, t_Generalization) Base.result_ =
fun v_ty v_context v_state v_name ->
(f_generalization_qualified (v_ty) ([]) (v_context) (v_state) (v_name))
and (* infer.bend:497 *)
f_generalize : M.t_Ty -> t_Context -> t_State -> Base.text -> (M.t_Diagnostic, t_Binding) Base.result_ =
fun v_ty v_context v_state v_name ->
(match (f_generalization (v_ty) (v_context) (v_state) (v_name)) with
| Fail __error -> Fail __error
| Done v_generalized ->
(Done ((f_generalization_binding (v_generalized)))))
and (* infer.bend:502 *)
f_generalize_qualified : M.t_Ty -> (M.t_Predicate) list -> t_Context -> t_State -> Base.text -> (M.t_Diagnostic, t_Binding) Base.result_ =
fun v_ty v_predicates v_context v_state v_name ->
(match (f_generalization_qualified (v_ty) (v_predicates) (v_context) (v_state) (v_name)) with
| Fail __error -> Fail __error
| Done v_generalized ->
(Done ((f_generalization_binding (v_generalized)))))
and (* infer.bend:509 *)
f_invocation_free : (M.t_EffectRow) option -> T.t_Substitutions -> (int) list =
fun v_invocation v_substitutions ->
(match v_invocation with
| None ->
[]
| (Some (v_row)) ->
(T.f_row_free ((T.f_resolve_row (v_substitutions) (v_row)))))
and (* infer.bend:516 *)
f_need_invocation : (M.t_EffectRow) option -> M.t_EffectRow -> M.t_EffectRow =
fun v_invocation v_ambient ->
(match v_invocation with
| (Some (v_row)) ->
v_row
| None ->
v_ambient)
and (* infer.bend:523 *)
f_associated_free : (t_Coverage) list -> T.t_Substitutions -> (M.t_Diagnostic, (int) list) Base.result_ =
fun v_coverage v_substitutions ->
(match v_coverage with
| [] ->
(Done ([]))
| ((AssociatedNeed (v_identity, v_dispatch, v_member, v_templates, v_left, v_right, v_result, v_invocation, v_ambient, v_subject)) :: v_tail) ->
(match (T.f_resolve_work (v_substitutions) ((Base.u32_to_nat (0x00010000l))) ((T.ManyTypes ([v_left; v_right; v_result])))) with
| Fail __error -> Fail __error
| Done v_resolved ->
(match (T.f_free ((M.ProductTy (v_resolved)))) with
| Fail __error -> Fail __error
| Done v_free ->
(match (f_associated_free (v_tail) (v_substitutions)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done ((T.f_union ((f_invocation_free (v_invocation) (v_substitutions))) ((T.f_union ((T.f_row_free ((T.f_resolve_row (v_substitutions) (v_ambient))))) ((T.f_union (v_free) (v_rest)))))))))))
| (v_head :: v_tail) ->
(f_associated_free (v_tail) (v_substitutions)))
and (* infer.bend:536 *)
f_generalized_witness : (int) list -> (M.t_Ty) list =
fun v_variables ->
(match v_variables with
| [] ->
[]
| (v_variable :: v_tail) ->
((M.FunctionTy ((M.VariableTy (v_variable)), M.UnitTy, (R.f_variable_row (v_variable)))) :: (f_generalized_witness (v_tail))))
and (* infer.bend:543 *)
f_generalized_evidence : (int) list -> (t_Coverage) list =
fun v_variables ->
(match v_variables with
| [] ->
[]
| (v_head :: v_tail) ->
[(LetGeneralized ((M.ProductTy ((f_generalized_witness ((v_head :: v_tail)))))))])
and (* infer.bend:550 *)
f_mentioned_generalized : (int) list -> (M.t_Diagnostic, (int) list) Base.result_ -> (M.t_Diagnostic, (t_Coverage) list) Base.result_ =
fun v_variables v_mentioned ->
(match v_mentioned with
| Fail __error -> Fail __error
| Done v_free ->
(Done ((f_generalized_evidence ((T.f_difference (v_variables) ((T.f_difference (v_variables) (v_free)))))))))
and (* infer.bend:557 *)
f_let_generalized : (int) list -> (t_Coverage) list -> T.t_Substitutions -> (M.t_Diagnostic, (t_Coverage) list) Base.result_ =
fun v_variables v_coverage v_substitutions ->
(match v_variables with
| [] ->
(Done ([]))
| (v_head :: v_tail) ->
(f_mentioned_generalized ((v_head :: v_tail)) ((f_associated_free (v_coverage) (v_substitutions)))))
and (* infer.bend:564 *)
f_annotation_variable : (M.t_Ty) option -> Base.text -> t_State -> t_Typing =
fun v_found v_key v_state ->
(match v_found with
| (Some (v_ty)) ->
(Typing ((f_pure (v_ty)), v_state))
| None ->
(let (State (v_substitutions, v_next, v_annotations)) = v_state in
(Typing ((f_pure ((M.VariableTy (v_next)))), (State (v_substitutions, (Base.nat_add 1 v_next), (Base.map_set (v_annotations) (v_key) ((M.VariableTy (v_next))))))))))
and (* infer.bend:572 *)
f_annotation_instance : (M.t_Ty) list -> M.t_Ty -> t_State -> (M.t_Diagnostic, t_Typing) Base.result_ =
fun v_parameters v_ty v_state ->
(match v_parameters with
| [] ->
(Done ((Typing ((f_pure (v_ty)), v_state))))
| ((M.FreeTy (v_scope, v_name)) :: v_rest) ->
(let (State (v_substitutions, v_next, v_annotations)) = v_state in
(let v_key = (Base.string_append (Base.nat_show ((Base.string_length (v_scope)))) (Base.string_append s_7 (Base.string_append v_scope v_name))) in
(let v_variable = (f_annotation_variable ((Index.f_find (v_annotations) (v_key))) (v_key) (v_state)) in
(match (T.f_rewrite (65536) ((T.OneType (v_ty))) ((T.ReplaceFree (v_scope, v_name, (f_type_of (v_variable)))))) with
| Fail __error -> Fail __error
| Done v_types ->
(match (T.f_first_type (v_types)) with
| Fail __error -> Fail __error
| Done v_replaced ->
(f_annotation_instance (v_rest) (v_replaced) ((f_state_of (v_variable)))))))))
| (v_other :: v_rest) ->
(Fail ((M.Diagnostic (s_8, s_9, s_10)))))
and (* infer.bend:591 *)
f_qualified_type : t_QualifiedAnnotation -> M.t_Ty =
fun v_value ->
(let (QualifiedAnnotation (v_ty, v_predicates, v_state)) = v_value in
v_ty)
and (* infer.bend:595 *)
f_qualified_predicates : t_QualifiedAnnotation -> (M.t_Predicate) list =
fun v_value ->
(let (QualifiedAnnotation (v_ty, v_predicates, v_state)) = v_value in
v_predicates)
and (* infer.bend:599 *)
f_qualified_state : t_QualifiedAnnotation -> t_State =
fun v_value ->
(let (QualifiedAnnotation (v_ty, v_predicates, v_state)) = v_value in
v_state)
and (* infer.bend:603 *)
f_qualified_inference : t_Inference -> int -> M.t_Ty -> (M.t_Predicate) list -> Base.text -> t_Inference =
fun v_value v_offset v_declared_type v_declared v_subject ->
(let (Inference (v_ty, v_coverage, v_exits, v_reflections, v_inferred, v_uses)) = v_value in
(Inference (v_declared_type, (Base.list_append (v_coverage) ([(QualifiedBoundary (v_offset, v_declared, v_subject))])), v_exits, v_reflections, (C.f_canonical_predicates (v_declared) ([])), v_uses)))
and (* infer.bend:607 *)
f_source_variable_index : M.t_Ty -> (M.t_Diagnostic, int) Base.result_ =
fun v_ty ->
(match v_ty with
| (M.VariableTy (v_index)) ->
(Done (v_index))
| _ ->
(Fail ((M.Diagnostic (s_8, s_9, s_11)))))
and (* infer.bend:614 *)
f_qualified_annotation_instance : (M.t_Ty) list -> M.t_Ty -> (M.t_Predicate) list -> t_State -> (M.t_Diagnostic, t_QualifiedAnnotation) Base.result_ =
fun v_parameters v_ty v_predicates v_state ->
(match v_parameters with
| [] ->
(Done ((QualifiedAnnotation (v_ty, v_predicates, v_state))))
| ((M.FreeTy (v_scope, v_name)) :: v_rest) ->
(let (State (v_substitutions, v_next, v_annotations)) = v_state in
(let v_key = (Base.string_append (Base.nat_show ((Base.string_length (v_scope)))) (Base.string_append s_7 (Base.string_append v_scope v_name))) in
(let v_variable = (f_annotation_variable ((Index.f_find (v_annotations) (v_key))) (v_key) (v_state)) in
(match (T.f_rewrite (65536) ((T.OneType (v_ty))) ((T.ReplaceFree (v_scope, v_name, (f_type_of (v_variable)))))) with
| Fail __error -> Fail __error
| Done v_types ->
(match (T.f_first_type (v_types)) with
| Fail __error -> Fail __error
| Done v_changed ->
(match (f_source_variable_index ((f_type_of (v_variable)))) with
| Fail __error -> Fail __error
| Done v_index ->
(match (C.f_replace_source (v_predicates) (v_scope) (v_name) (v_index)) with
| Fail __error -> Fail __error
| Done v_needs ->
(f_qualified_annotation_instance (v_rest) (v_changed) (v_needs) ((f_state_of (v_variable)))))))))))
| (v_other :: v_rest) ->
(Fail ((M.Diagnostic (s_8, s_9, s_12)))))
and (* infer.bend:631 *)
f_validate_qualified_predicates : (M.t_Predicate) list -> t_Context -> (M.t_Diagnostic, unit) Base.result_ =
fun v_predicates v_context ->
(match v_predicates with
| [] ->
(Done (()))
| (v_head :: v_tail) ->
(match (D.f_annotation ((Some ((C.f_shape_type (v_head))))) ((f_context_operations (v_context))) ((f_context_types (v_context))) ((f_context_subject (v_context)))) with
| Fail __error -> Fail __error
| Done v_valid ->
(f_validate_qualified_predicates (v_tail) (v_context))))
and (* infer.bend:640 *)
f_qualified_annotation : M.t_Ty -> (M.t_Predicate) list -> t_State -> t_Context -> (M.t_Diagnostic, t_QualifiedAnnotation) Base.result_ =
fun v_annotation v_predicates v_state v_context ->
(match (D.f_annotation ((Some (v_annotation))) ((f_context_operations (v_context))) ((f_context_types (v_context))) ((f_context_subject (v_context)))) with
| Fail __error -> Fail __error
| Done v_valid ->
(match (f_validate_qualified_predicates (v_predicates) (v_context)) with
| Fail __error -> Fail __error
| Done v_valid_needs ->
(match (T.f_annotation_names (65536) ((T.OneType (v_annotation)))) with
| Fail __error -> Fail __error
| Done v_types ->
(match (C.f_annotation_names (v_predicates)) with
| Fail __error -> Fail __error
| Done v_names ->
(f_qualified_annotation_instance ((Base.list_append (v_types) (v_names))) (v_annotation) (v_predicates) (v_state))))))
and (* infer.bend:648 *)
f_annotation : (M.t_Ty) option -> M.t_Ty -> t_State -> t_Context -> (M.t_Diagnostic, t_State) Base.result_ =
fun v_annotation v_ty v_state v_context ->
(match v_annotation with
| None ->
(Done (v_state))
| (Some (v_expected)) ->
(let (Context (v_globals, v_locals, v_labels, v_types, v_operations, v_subject, v_functions, v_ambient)) = v_context in
(match (D.f_annotation ((Some (v_expected))) (v_operations) (v_types) (v_subject)) with
| Fail __error -> Fail __error
| Done v_valid ->
(match (T.f_annotation_names (65536) ((T.OneType (v_expected)))) with
| Fail __error -> Fail __error
| Done v_parameters ->
(match (f_annotation_instance (v_parameters) (v_expected) (v_state)) with
| Fail __error -> Fail __error
| Done v_instantiated ->
(f_unify ((f_type_of (v_instantiated))) (v_ty) ((f_state_of (v_instantiated))) (v_subject)))))))
and (* infer.bend:660 *)
f_operation_template : (M.t_Operation) list -> M.t_TypeId -> (M.t_Diagnostic, M.t_Operation) Base.result_ =
fun v_operations v_wanted ->
(match v_operations with
| [] ->
(Fail ((M.Diagnostic (s_13, (M.f_type_id_show (v_wanted)), s_14))))
| ((M.OperationTemplate (v_identity, v_parameters, v_parameter, v_result)) :: v_tail) ->
(Base.bool_pick ((M.f_type_id_equal (v_identity) (v_wanted))) ((Done ((M.OperationTemplate (v_identity, v_parameters, v_parameter, v_result))))) ((f_operation_template (v_tail) (v_wanted))))
| (v_head :: v_tail) ->
(f_operation_template (v_tail) (v_wanted)))
and (* infer.bend:669 *)
f_fresh_operation_arguments : int -> int -> (M.t_Ty) list =
fun v_count v_next ->
(match v_count with
| 0 ->
[]
| __nat_1 when __nat_1 >= 1 ->
(let v_rest = (__nat_1 - 1) in
((M.VariableTy (v_next)) :: (f_fresh_operation_arguments (v_rest) ((Base.nat_add 1 v_next))))))
and (* infer.bend:679 *)
f_instantiate_operation_arguments : (M.t_Ty) list -> t_State -> t_Context -> (M.t_Ty) list -> (M.t_Diagnostic, t_OperationArguments) Base.result_ =
fun v_arguments v_state v_context v_reversed ->
(match v_arguments with
| [] ->
(Done ((OperationArguments ((Base.list_reverse (v_reversed)), v_state))))
| (v_argument :: v_tail) ->
(match (D.f_annotation ((Some (v_argument))) ((f_context_operations (v_context))) ((f_context_types (v_context))) ((f_context_subject (v_context)))) with
| Fail __error -> Fail __error
| Done v_valid ->
(match (T.f_annotation_names (65536) ((T.OneType (v_argument)))) with
| Fail __error -> Fail __error
| Done v_parameters ->
(match (f_annotation_instance (v_parameters) (v_argument) (v_state)) with
| Fail __error -> Fail __error
| Done v_instantiated ->
(f_instantiate_operation_arguments (v_tail) ((f_state_of (v_instantiated))) (v_context) (((f_type_of (v_instantiated)) :: v_reversed)))))))
and (* infer.bend:690 *)
f_operation_arguments : (M.t_Ty) list -> int -> t_State -> t_Context -> (M.t_Diagnostic, t_OperationArguments) Base.result_ =
fun v_arguments v_count v_state v_context ->
(match v_arguments with
| [] ->
(let v_start = (f_next_of (v_state)) in
(Done ((OperationArguments ((f_fresh_operation_arguments (v_count) (v_start)), (f_with_next (v_state) ((Base.nat_add (v_start) (v_count)))))))))
| v_arguments ->
(f_instantiate_operation_arguments (v_arguments) (v_state) (v_context) ([])))
and (* infer.bend:698 *)
f_generic_operation_signature : int -> M.t_TypeId -> M.t_Ty -> M.t_Ty -> t_OperationArguments -> t_Context -> (M.t_Diagnostic, t_Typing) Base.result_ =
fun v_identity v_template v_parameter v_result v_arguments v_context ->
(let (OperationArguments (v_types, v_state)) = v_arguments in
(match (T.f_parameters (v_types) (0) (v_parameter)) with
| Fail __error -> Fail __error
| Done v_p ->
(match (T.f_parameters (v_types) (0) (v_result)) with
| Fail __error -> Fail __error
| Done v_r ->
(let v_signature = (M.FunctionTy (v_p, v_r, (R.f_variable_row ((f_next_of (v_state)))))) in
(Done ((Typing ((Inference (v_signature, [(OperationNeed (v_identity, v_template, v_types, v_signature, (f_context_subject (v_context))))], [], [], [(M.OperationPredicate (v_template, v_types, v_signature))], [])), (f_with_next (v_state) ((Base.nat_add 1 (f_next_of (v_state)))))))))))))
and (* infer.bend:706 *)
f_associated_predicate : M.t_Dispatch -> Base.text -> (M.t_TypeId) list -> M.t_Ty -> M.t_Ty -> M.t_Ty -> M.t_EffectRow -> M.t_Predicate =
fun v_dispatch v_member v_templates v_left v_right v_result v_ambient ->
(match v_dispatch with
| M.BinaryDispatch ->
(M.AssociatedPredicate (v_member, v_templates, v_left, v_right, v_result, v_ambient))
| M.MemberDispatch ->
(M.ReceiverPredicate (v_member, v_templates, v_left, v_right, v_result, v_ambient))
| M.FieldUpdateDispatch ->
(M.UpdatePredicate (v_member, v_left, v_right, v_result, v_ambient)))
and (* infer.bend:715 *)
f_generic_operation : int -> M.t_TypeId -> M.t_Operation -> (M.t_Ty) list -> t_State -> t_Context -> (M.t_Diagnostic, t_Typing) Base.result_ =
fun v_identity v_template v_declared v_arguments v_state v_context ->
(match v_declared with
| (M.OperationTemplate (v_declared_identity, v_parameters, v_parameter, v_result)) ->
(match (f_operation_arguments (v_arguments) (v_parameters) (v_state) (v_context)) with
| Fail __error -> Fail __error
| Done v_instantiated ->
(f_generic_operation_signature (v_identity) (v_template) (v_parameter) (v_result) (v_instantiated) (v_context)))
| _ ->
(Fail ((M.Diagnostic (s_8, (M.f_type_id_show (v_template)), s_15)))))
and (* infer.bend:724 *)
f_predicate_arity : bool -> Base.text -> (M.t_Diagnostic, unit) Base.result_ =
fun v_valid v_subject ->
(Base.bool_pick (v_valid) ((Done (()))) ((Fail ((M.Diagnostic (s_16, v_subject, s_17))))))
and (* infer.bend:727 *)
f_constrain_declared_operation : M.t_Operation -> (M.t_Ty) list -> M.t_Ty -> t_State -> t_Context -> (M.t_Diagnostic, t_State) Base.result_ =
fun v_declared v_arguments v_function_type v_state v_context ->
(match v_declared with
| (M.OperationTemplate (v_identity, v_parameters, v_parameter, v_result)) ->
(match (f_predicate_arity ((Base.nat_is_eq (v_parameters) ((Base.list_length (v_arguments))))) ((f_context_subject (v_context)))) with
| Fail __error -> Fail __error
| Done v_arity ->
(match (T.f_parameters (v_arguments) (0) (v_parameter)) with
| Fail __error -> Fail __error
| Done v_p ->
(match (T.f_parameters (v_arguments) (0) (v_result)) with
| Fail __error -> Fail __error
| Done v_r ->
(f_unify (v_function_type) ((M.FunctionTy (v_p, v_r, (R.f_variable_row ((f_next_of (v_state))))))) ((f_with_next (v_state) ((Base.nat_add 1 (f_next_of (v_state)))))) ((f_context_subject (v_context)))))))
| _ ->
(Fail ((M.Diagnostic (s_8, (f_context_subject (v_context)), s_18)))))
and (* infer.bend:738 *)
f_constrain_predicate : M.t_Predicate -> t_State -> t_Context -> (M.t_Diagnostic, t_State) Base.result_ =
fun v_predicate v_state v_context ->
(match v_predicate with
| (M.OperationPredicate (v_template, v_arguments, v_function_type)) ->
(match (f_operation_template ((f_context_operations (v_context))) (v_template)) with
| Fail __error -> Fail __error
| Done v_declared ->
(f_constrain_declared_operation (v_declared) (v_arguments) (v_function_type) (v_state) (v_context)))
| v_other ->
(Done (v_state)))
and (* infer.bend:747 *)
f_constrain_predicates : (M.t_Predicate) list -> t_State -> t_Context -> (M.t_Diagnostic, t_State) Base.result_ =
fun v_predicates v_state v_context ->
(match v_predicates with
| [] ->
(Done (v_state))
| (v_head :: v_tail) ->
(match (f_constrain_predicate (v_head) (v_state) (v_context)) with
| Fail __error -> Fail __error
| Done v_next ->
(f_constrain_predicates (v_tail) (v_next) (v_context))))
and (* infer.bend:756 *)
f_unify_entail_shapes : C.t_EntailShapes -> t_State -> Base.text -> (M.t_Diagnostic, t_State) Base.result_ =
fun v_shapes v_state v_subject ->
(let (C.EntailShapes (v_left, v_right)) = v_shapes in
(f_unify (v_left) (v_right) (v_state) (v_subject)))
and (* infer.bend:760 *)
f_candidate_attempt : bool -> M.t_Predicate -> M.t_Predicate -> t_State -> Base.text -> (M.t_Diagnostic, t_State) Base.result_ =
fun v_compatible v_wanted v_candidate v_state v_subject ->
(match v_compatible with
| false ->
(Fail ((M.Diagnostic (s_19, v_subject, s_20))))
| true ->
(f_unify_entail_shapes ((C.f_entail_shapes (v_wanted) (v_candidate))) (v_state) (v_subject)))
and (* infer.bend:767 *)
f_entail_work : (M.t_Predicate) list -> (M.t_Diagnostic, t_State) Base.result_ -> M.t_Predicate -> t_State -> Base.text -> (M.t_Diagnostic, t_State) Base.result_ =
fun v_declared v_attempt v_wanted v_state v_subject ->
(match (v_declared, v_attempt) with
| (_, (Done (v_next))) ->
(Done (v_next))
| ([], (Fail (v_diagnostic))) ->
(Fail ((M.Diagnostic (s_21, v_subject, s_22))))
| ((v_candidate :: v_tail), (Fail (v_diagnostic))) ->
(f_entail_work (v_tail) ((f_candidate_attempt ((C.f_same_head (v_wanted) (v_candidate))) (v_wanted) (v_candidate) (v_state) (v_subject))) (v_wanted) (v_state) (v_subject)))
and (* infer.bend:776 *)
f_entail_one : M.t_Predicate -> (M.t_Predicate) list -> t_State -> Base.text -> (M.t_Diagnostic, t_State) Base.result_ =
fun v_wanted v_declared v_state v_subject ->
(f_entail_work (v_declared) ((Fail ((M.Diagnostic (s_21, v_subject, s_23))))) (v_wanted) (v_state) (v_subject))
and (* infer.bend:779 *)
f_entailment_value_free : M.t_Predicate -> (int) list -> (M.t_Diagnostic, (int) list) Base.result_ =
fun v_predicate v_checked ->
(match v_predicate with
| (M.AssociatedPredicate (v_member, v_templates, v_left, v_right, v_result, v_invocation)) ->
(T.f_free ((M.ProductTy ([v_left; v_right; v_result]))))
| (M.ReceiverPredicate (v_member, v_templates, v_receiver, v_argument, v_result, v_invocation)) ->
(T.f_free ((M.ProductTy ([v_receiver; v_argument; v_result]))))
| (M.UpdatePredicate (v_member, v_receiver, v_assigned, v_result, v_invocation)) ->
(T.f_free ((M.ProductTy ([v_receiver; v_assigned; v_result]))))
| v_other ->
(Done (v_checked)))
and (* infer.bend:790 *)
f_entailment_free : M.t_Predicate -> (M.t_Diagnostic, (int) list) Base.result_ =
fun v_predicate ->
(match (C.f_free (v_predicate)) with
| Fail __error -> Fail __error
| Done v_checked ->
(f_entailment_value_free (v_predicate) (v_checked)))
and (* infer.bend:795 *)
f_require_open_entailment : bool -> M.t_Predicate -> (M.t_Predicate) list -> t_State -> Base.text -> (M.t_Diagnostic, t_State) Base.result_ =
fun v_closed v_required v_declared v_state v_subject ->
(match v_closed with
| true ->
(Done (v_state))
| false ->
(f_entail_one (v_required) (v_declared) (v_state) (v_subject)))
and (* infer.bend:802 *)
f_coverage_subject : M.t_Predicate -> (t_Coverage) list -> Base.text -> Base.text =
fun v_required v_coverage v_fallback ->
(match v_coverage with
| [] ->
v_fallback
| ((AssociatedNeed (v_identity, v_dispatch, v_member, v_templates, v_left, v_right, v_result, v_invocation, v_ambient, v_subject)) :: v_tail) ->
(Base.bool_pick ((C.f_same_head (v_required) ((f_associated_predicate (v_dispatch) (v_member) (v_templates) (v_left) (v_right) (v_result) ((f_need_invocation (v_invocation) (v_ambient))))))) (v_subject) ((f_coverage_subject (v_required) (v_tail) (v_fallback))))
| ((OperationNeed (v_identity, v_template, v_arguments, v_function_type, v_subject)) :: v_tail) ->
(Base.bool_pick ((C.f_same_head (v_required) ((M.OperationPredicate (v_template, v_arguments, v_function_type))))) (v_subject) ((f_coverage_subject (v_required) (v_tail) (v_fallback))))
| (v_head :: v_tail) ->
(f_coverage_subject (v_required) (v_tail) (v_fallback)))
and (* infer.bend:813 *)
f_use_subject : M.t_Predicate -> (C.t_UsePlan) list -> Base.text -> Base.text =
fun v_required v_plans v_fallback ->
(match v_plans with
| [] ->
v_fallback
| ((C.UsePlan (v_site, v_subject, v_ty, v_predicates)) :: v_tail) ->
(Base.bool_pick ((C.f_contains_head (v_predicates) (v_required))) (v_subject) ((f_use_subject (v_required) (v_tail) (v_fallback)))))
and (* infer.bend:820 *)
f_entail_all : (M.t_Predicate) list -> (t_Coverage) list -> (C.t_UsePlan) list -> (M.t_Predicate) list -> t_State -> Base.text -> (M.t_Diagnostic, t_State) Base.result_ =
fun v_inferred v_coverage v_uses v_declared v_state v_subject ->
(match v_inferred with
| [] ->
(Done (v_state))
| (v_head :: v_tail) ->
(match (C.f_resolve ((f_substitutions_of (v_state))) (v_head)) with
| Fail __error -> Fail __error
| Done v_resolved ->
(match (f_entailment_free (v_resolved)) with
| Fail __error -> Fail __error
| Done v_free ->
(let v_origin = (f_coverage_subject (v_resolved) (v_coverage) ((f_use_subject (v_resolved) (v_uses) (v_subject)))) in
(match (f_require_open_entailment ((Base.list_is_empty (v_free))) (v_resolved) (v_declared) (v_state) (v_origin)) with
| Fail __error -> Fail __error
| Done v_next ->
(f_entail_all (v_tail) (v_coverage) (v_uses) (v_declared) (v_next) (v_subject)))))))
and (* infer.bend:832 *)
f_constructor_instance : Base.text -> t_Context -> t_State -> (M.t_Diagnostic, D.t_ConstructorType) Base.result_ =
fun v_name v_context v_state ->
(let v_constructor_name = v_name in
(D.f_instantiate ((D.f_constructor ((f_context_types (v_context))) (v_constructor_name))) (v_constructor_name) ((f_next_of (v_state))) ((f_context_subject (v_context)))))
and (* infer.bend:836 *)
f_constructor_type : D.t_ConstructorType -> M.t_Ty =
fun v_value ->
(match v_value with
| (D.ConstructorType (v_result, None, v_next)) ->
v_result
| (D.ConstructorType (v_result, (Some (v_payload)), v_next)) ->
(M.FunctionTy (v_payload, v_result, (R.f_variable_row (v_next)))))
and (* infer.bend:843 *)
f_constructor_result : D.t_ConstructorType -> M.t_Ty =
fun v_value ->
(let (D.ConstructorType (v_result, v_payload, v_next)) = v_value in
v_result)
and (* infer.bend:847 *)
f_constructor_payload : D.t_ConstructorType -> (M.t_Ty) option =
fun v_value ->
(let (D.ConstructorType (v_result, v_payload, v_next)) = v_value in
v_payload)
and (* infer.bend:851 *)
f_constructor_state : D.t_ConstructorType -> t_State -> t_State =
fun v_value v_state ->
(let (D.ConstructorType (v_result, v_payload, v_next)) = v_value in
(f_with_next (v_state) ((Base.nat_add 1 v_next))))
and (* infer.bend:855 *)
f_payload_type : (M.t_Ty) option -> Base.text -> (M.t_Diagnostic, M.t_Ty) Base.result_ =
fun v_payload v_subject ->
(match v_payload with
| None ->
(Fail ((M.Diagnostic (s_24, v_subject, s_25))))
| (Some (v_ty)) ->
(Done (v_ty)))
and (* infer.bend:862 *)
f_no_payload : (M.t_Ty) option -> Base.text -> (M.t_Diagnostic, unit) Base.result_ =
fun v_payload v_subject ->
(match v_payload with
| None ->
(Done (()))
| (Some (v_ty)) ->
(Fail ((M.Diagnostic (s_24, v_subject, s_26)))))
and (* infer.bend:869 *)
f_pattern_state : t_PatternTyping -> t_State =
fun v_typing ->
(let (PatternTyping (v_bindings, v_state, v_constraints)) = v_typing in
v_state)
and (* infer.bend:873 *)
f_pattern_bindings : t_PatternTyping -> (t_Binding) list =
fun v_typing ->
(let (PatternTyping (v_bindings, v_state, v_constraints)) = v_typing in
v_bindings)
and (* infer.bend:877 *)
f_pattern_constraints : t_PatternTyping -> (t_Coverage) list =
fun v_typing ->
(let (PatternTyping (v_bindings, v_state, v_constraints)) = v_typing in
v_constraints)
and (* infer.bend:881 *)
f_with_pattern_constraints : t_Inference -> (t_Coverage) list -> t_Inference =
fun v_inference v_constraints ->
(let (Inference (v_ty, v_coverage, v_exits, v_reflections, v_predicates, v_uses)) = v_inference in
(Inference (v_ty, (Base.list_append (v_constraints) (v_coverage)), v_exits, v_reflections, v_predicates, v_uses)))
and (* infer.bend:885 *)
f_require_new_binding : (t_Binding) option -> Base.text -> Base.text -> (M.t_Diagnostic, unit) Base.result_ =
fun v_found v_subject v_name ->
(match v_found with
| None ->
(Done (()))
| (Some (v_binding)) ->
(Fail ((M.Diagnostic (s_27, v_subject, (Base.string_append s_28 (Base.string_append v_name s_29)))))))
and (* infer.bend:896 *)
f_pattern_requirements_closed : (M.t_Predicate) list -> t_State -> Base.text -> (M.t_Diagnostic, unit) Base.result_ =
fun v_predicates v_state v_subject ->
(match v_predicates with
| [] ->
(Done (()))
| (v_head :: v_tail) ->
(match (C.f_resolve ((f_substitutions_of (v_state))) (v_head)) with
| Fail __error -> Fail __error
| Done v_resolved ->
(match (C.f_free (v_resolved)) with
| Fail __error -> Fail __error
| Done v_free ->
(match (Base.bool_pick ((Base.list_is_empty (v_free))) ((Done (()))) ((Fail ((M.Diagnostic (s_30, v_subject, s_31)))))) with
| Fail __error -> Fail __error
| Done v_closed ->
(f_pattern_requirements_closed (v_tail) (v_state) (v_subject))))))
and (* infer.bend:907 *)
f_pattern_reference_ready_for : (M.t_Predicate) list -> t_Typing -> Base.text -> (M.t_Diagnostic, t_Typing) Base.result_ =
fun v_predicates v_value v_subject ->
(match (f_pattern_requirements_closed (v_predicates) ((f_state_of (v_value))) (v_subject)) with
| Fail __error -> Fail __error
| Done v_ready ->
(Done (v_value)))
and (* infer.bend:912 *)
f_pattern_reference_ready : t_Typing -> Base.text -> (M.t_Diagnostic, t_Typing) Base.result_ =
fun v_value v_subject ->
(f_pattern_reference_ready_for ((f_inference_predicates ((f_inference_of (v_value))))) (v_value) (v_subject))
and (* infer.bend:915 *)
f_value_reference_type : M.t_ValueReference -> t_Context -> t_State -> (M.t_Diagnostic, t_Typing) Base.result_ =
fun v_reference v_context v_state ->
(match v_reference with
| (M.LocalReference (v_name)) ->
(match (f_instantiate_binding ((f_lookup_local (v_context) (v_name))) (v_state) (v_name) ((f_context_subject (v_context)))) with
| Fail __error -> Fail __error
| Done v_value ->
(f_pattern_reference_ready (v_value) ((f_context_subject (v_context)))))
| (M.ConstantReference (v_name)) ->
(match (f_valid_global_kind (v_context) (v_name) (false)) with
| Fail __error -> Fail __error
| Done v_valid ->
(match (f_instantiate_binding ((f_lookup_global (v_context) (v_name))) (v_state) (v_name) ((f_context_subject (v_context)))) with
| Fail __error -> Fail __error
| Done v_value ->
(f_pattern_reference_ready (v_value) ((f_context_subject (v_context)))))))
and (* infer.bend:927 *)
f_infer_pattern_work : int -> (t_PatternWork) list -> t_Context -> t_State -> (t_Binding) list -> (t_Coverage) list -> (M.t_Diagnostic, t_PatternTyping) Base.result_ =
fun v_fuel v_pending v_context v_state v_bindings v_constraints ->
(match (v_fuel, v_pending) with
| (_, []) ->
(Done ((PatternTyping (v_bindings, v_state, v_constraints))))
| (0, _) ->
(Fail ((M.Diagnostic (s_32, (f_context_subject (v_context)), s_33))))
| (__nat_2, ((PatternValue (M.WildcardPattern, v_expected)) :: v_tail)) when __nat_2 >= 1 ->
(let v_rest = (__nat_2 - 1) in
(f_infer_pattern_work (v_rest) (v_tail) (v_context) (v_state) (v_bindings) (v_constraints)))
| (__nat_3, ((PatternValue ((M.BindingPattern (v_name)), v_expected)) :: v_tail)) when __nat_3 >= 1 ->
(let v_rest = (__nat_3 - 1) in
(match (f_require_new_binding ((f_lookup_binding (v_bindings) (v_name))) ((f_context_subject (v_context))) (v_name)) with
| Fail __error -> Fail __error
| Done v_fresh ->
(f_infer_pattern_work (v_rest) (v_tail) (v_context) (v_state) (((Binding (v_name, v_expected, [], [])) :: v_bindings)) (v_constraints))))
| (__nat_4, ((PatternValue ((M.ValuePattern (v_reference)), v_expected)) :: v_tail)) when __nat_4 >= 1 ->
(let v_rest = (__nat_4 - 1) in
(match (f_value_reference_type (v_reference) (v_context) (v_state)) with
| Fail __error -> Fail __error
| Done v_value ->
(match (f_unify (v_expected) ((f_type_of (v_value))) ((f_state_of (v_value))) ((f_context_subject (v_context)))) with
| Fail __error -> Fail __error
| Done v_next ->
(f_infer_pattern_work (v_rest) (v_tail) (v_context) (v_next) (v_bindings) (((ValuePatternType (v_expected, (f_context_subject (v_context)))) :: v_constraints))))))
| (__nat_5, ((PatternValue (M.UnitPattern, v_expected)) :: v_tail)) when __nat_5 >= 1 ->
(let v_rest = (__nat_5 - 1) in
(match (f_unify (v_expected) (M.UnitTy) (v_state) ((f_context_subject (v_context)))) with
| Fail __error -> Fail __error
| Done v_next ->
(f_infer_pattern_work (v_rest) (v_tail) (v_context) (v_next) (v_bindings) (v_constraints))))
| (__nat_6, ((PatternValue ((M.U32Pattern (v_value)), v_expected)) :: v_tail)) when __nat_6 >= 1 ->
(let v_rest = (__nat_6 - 1) in
(match (f_unify (v_expected) (M.U32Ty) (v_state) ((f_context_subject (v_context)))) with
| Fail __error -> Fail __error
| Done v_next ->
(f_infer_pattern_work (v_rest) (v_tail) (v_context) (v_next) (v_bindings) (v_constraints))))
| (__nat_7, ((PatternValue ((M.BoolPattern (v_value)), v_expected)) :: v_tail)) when __nat_7 >= 1 ->
(let v_rest = (__nat_7 - 1) in
(match (f_unify (v_expected) (M.BoolTy) (v_state) ((f_context_subject (v_context)))) with
| Fail __error -> Fail __error
| Done v_next ->
(f_infer_pattern_work (v_rest) (v_tail) (v_context) (v_next) (v_bindings) (v_constraints))))
| (__nat_8, ((PatternValue ((M.ConstructorPattern (v_name, None)), v_expected)) :: v_tail)) when __nat_8 >= 1 ->
(let v_rest = (__nat_8 - 1) in
(match (f_constructor_instance (v_name) (v_context) (v_state)) with
| Fail __error -> Fail __error
| Done v_ctor ->
(match (f_no_payload ((f_constructor_payload (v_ctor))) ((f_context_subject (v_context)))) with
| Fail __error -> Fail __error
| Done v_arity ->
(match (f_unify (v_expected) ((f_constructor_result (v_ctor))) ((f_constructor_state (v_ctor) (v_state))) ((f_context_subject (v_context)))) with
| Fail __error -> Fail __error
| Done v_next ->
(f_infer_pattern_work (v_rest) (v_tail) (v_context) (v_next) (v_bindings) (v_constraints))))))
| (__nat_9, ((PatternValue ((M.ConstructorPattern (v_name, (Some (v_payload)))), v_expected)) :: v_tail)) when __nat_9 >= 1 ->
(let v_rest = (__nat_9 - 1) in
(match (f_constructor_instance (v_name) (v_context) (v_state)) with
| Fail __error -> Fail __error
| Done v_ctor ->
(match (f_payload_type ((f_constructor_payload (v_ctor))) ((f_context_subject (v_context)))) with
| Fail __error -> Fail __error
| Done v_ty ->
(match (f_unify (v_expected) ((f_constructor_result (v_ctor))) ((f_constructor_state (v_ctor) (v_state))) ((f_context_subject (v_context)))) with
| Fail __error -> Fail __error
| Done v_next ->
(f_infer_pattern_work (v_rest) (((PatternValue (v_payload, v_ty)) :: v_tail)) (v_context) (v_next) (v_bindings) (v_constraints))))))
| (__nat_10, ((PatternValue ((M.ProductPattern (v_elements)), v_expected)) :: v_tail)) when __nat_10 >= 1 ->
(let v_rest = (__nat_10 - 1) in
(let v_count = (Base.list_length (v_elements)) in
(let v_fields = (D.f_fresh_arguments (v_count) ((f_next_of (v_state)))) in
(match (D.f_require_product_arity (v_count) ((f_context_subject (v_context)))) with
| Fail __error -> Fail __error
| Done v_arity ->
(match (f_unify (v_expected) ((M.ProductTy (v_fields))) ((f_with_next (v_state) ((Base.nat_add ((f_next_of (v_state))) (v_count))))) ((f_context_subject (v_context)))) with
| Fail __error -> Fail __error
| Done v_next ->
(f_infer_pattern_work (v_rest) (((PatternFields (v_elements, v_fields)) :: v_tail)) (v_context) (v_next) (v_bindings) (v_constraints)))))))
| (__nat_11, ((PatternFields ([], [])) :: v_tail)) when __nat_11 >= 1 ->
(let v_rest = (__nat_11 - 1) in
(f_infer_pattern_work (v_rest) (v_tail) (v_context) (v_state) (v_bindings) (v_constraints)))
| (__nat_12, ((PatternFields ((v_pattern :: v_following), (v_ty :: v_remaining))) :: v_tail)) when __nat_12 >= 1 ->
(let v_rest = (__nat_12 - 1) in
(f_infer_pattern_work (v_rest) (((PatternValue (v_pattern, v_ty)) :: ((PatternFields (v_following, v_remaining)) :: v_tail))) (v_context) (v_state) (v_bindings) (v_constraints)))
| (__nat_13, ((PatternFields (v_patterns, v_expected)) :: v_tail)) when __nat_13 >= 1 ->
(let v_rest = (__nat_13 - 1) in
(Fail ((M.Diagnostic (s_8, (f_context_subject (v_context)), s_34))))))
and (* infer.bend:982 *)
f_infer_pattern : M.t_Pattern -> M.t_Ty -> t_Context -> t_State -> (M.t_Diagnostic, t_PatternTyping) Base.result_ =
fun v_value v_expected v_context v_state ->
(f_infer_pattern_work ((Base.u32_to_nat (0x00010000l))) ([(PatternValue (v_value, v_expected))]) (v_context) (v_state) ([]) ([]))
and (* infer.bend:992 *)
f_arm_patterns : ((M.t_Expr) M.t_MatchArm) list -> ((M.t_Pattern) list) list =
fun v_arms ->
(match v_arms with
| [] ->
[]
| ((M.MatchArm (v_patterns, v_body)) :: v_tail) ->
(v_patterns :: (f_arm_patterns (v_tail))))
and (* infer.bend:999 *)
f_guard_exits : M.t_Ty -> Base.text -> (M.t_Diagnostic, unit) Base.result_ =
fun v_ty v_subject ->
(match v_ty with
| M.NeverTy ->
(Done (()))
| v_other ->
(Fail ((M.Diagnostic (s_35, v_subject, s_36)))))
and (* infer.bend:1006 *)
f_pure_row : M.t_EffectRow -> t_State -> Base.text -> Base.text -> (M.t_Diagnostic, t_State) Base.result_ =
fun v_row v_state v_subject v_code ->
(match v_row with
| (M.EffectRow ([], v_tail)) ->
(f_unify_rows ((M.EffectRow ([], v_tail))) ((M.f_empty_row ())) (v_state) (v_subject))
| (M.EffectRow ((v_head :: v_tail), v_rest)) ->
(Fail ((M.Diagnostic (v_code, v_subject, (Base.string_append s_37 (Base.string_append (M.f_type_id_show (v_head)) s_38)))))))
and (* infer.bend:1013 *)
f_require_pure : M.t_EffectRow -> t_State -> Base.text -> Base.text -> (M.t_Diagnostic, t_State) Base.result_ =
fun v_row v_state v_subject v_code ->
(f_pure_row ((T.f_resolve_row ((f_substitutions_of (v_state))) (v_row))) (v_state) (v_subject) (v_code))
and (* infer.bend:1016 *)
f_merge_pattern_bindings : (t_Binding) list -> (t_Binding) list -> Base.text -> (M.t_Diagnostic, (t_Binding) list) Base.result_ =
fun v_pending v_bindings v_subject ->
(match v_pending with
| [] ->
(Done (v_bindings))
| ((Binding (v_name, v_ty, v_variables, v_predicates)) :: v_tail) ->
(match (f_require_new_binding ((f_lookup_binding (v_bindings) (v_name))) (v_subject) (v_name)) with
| Fail __error -> Fail __error
| Done v_fresh ->
(f_merge_pattern_bindings (v_tail) (((Binding (v_name, v_ty, v_variables, v_predicates)) :: v_bindings)) (v_subject))))
and (* infer.bend:1025 *)
f_infer_patterns : (M.t_Pattern) list -> (M.t_Ty) list -> t_Context -> t_State -> (t_Binding) list -> (t_Coverage) list -> (M.t_Diagnostic, t_PatternTyping) Base.result_ =
fun v_patterns v_expected v_context v_state v_bindings v_constraints ->
(match (v_patterns, v_expected) with
| ([], []) ->
(Done ((PatternTyping (v_bindings, v_state, v_constraints))))
| ((v_pattern :: v_tail), (v_ty :: v_remaining)) ->
(match (f_infer_pattern (v_pattern) (v_ty) (v_context) (v_state)) with
| Fail __error -> Fail __error
| Done v_first ->
(match (f_merge_pattern_bindings ((f_pattern_bindings (v_first))) (v_bindings) ((f_context_subject (v_context)))) with
| Fail __error -> Fail __error
| Done v_merged ->
(f_infer_patterns (v_tail) (v_remaining) (v_context) ((f_pattern_state (v_first))) (v_merged) ((Base.list_append ((f_pattern_constraints (v_first))) (v_constraints))))))
| (_, _) ->
(Fail ((M.Diagnostic (s_39, (f_context_subject (v_context)), s_40)))))
and (* infer.bend:1037 *)
f_operation_type : M.t_Operation -> int -> M.t_Ty =
fun v_declaration v_next ->
(match v_declaration with
| (M.Operation (v_identity, v_parameter, v_result)) ->
(M.FunctionTy (v_parameter, v_result, (R.f_singleton (v_identity) ((M.RowVariable (v_next))))))
| _ ->
M.NeverTy)
and (* infer.bend:1044 *)
f_operation_parameter : M.t_Operation -> M.t_Ty =
fun v_declaration ->
(match v_declaration with
| (M.Operation (v_identity, v_parameter, v_result)) ->
v_parameter
| _ ->
M.NeverTy)
and (* infer.bend:1051 *)
f_operation_result : M.t_Operation -> M.t_Ty =
fun v_declaration ->
(match v_declaration with
| (M.Operation (v_identity, v_parameter, v_result)) ->
v_result
| _ ->
M.NeverTy)
and (* infer.bend:1061 *)
f_require_provider : M.t_Ty -> Base.text -> (M.t_Diagnostic, t_Provider) Base.result_ =
fun v_ty v_subject ->
(match v_ty with
| (M.ProviderTy (v_identity, v_effects)) ->
(Done ((Provider ([v_identity], v_effects, None))))
| (M.StateProviderTy (v_read, v_write, v_state)) ->
(Done ((Provider ([v_read; v_write], (M.f_empty_row ()), (Some (v_state))))))
| v_other ->
(Fail ((M.Diagnostic (s_41, v_subject, (Base.string_append s_42 (M.f_type_show (v_other))))))))
and (* infer.bend:1070 *)
f_prepare_provider : t_Provider -> t_Context -> t_State -> (M.t_Diagnostic, t_State) Base.result_ =
fun v_provider v_context v_state ->
(match v_provider with
| (Provider (v_identities, v_effects, None)) ->
(f_unify_rows (v_effects) ((f_context_row (v_context))) (v_state) ((f_context_subject (v_context))))
| (Provider (v_identities, v_effects, (Some (v_ty)))) ->
(Done (v_state)))
and (* infer.bend:1077 *)
f_handled_context : t_Context -> t_Provider -> t_Context =
fun v_context v_provider ->
(let (Provider (v_identities, v_effects, v_state)) = v_provider in
(f_with_row (v_context) ((R.f_prepend (v_identities) ((f_context_row (v_context)))))))
and (* infer.bend:1081 *)
f_handled_result : t_Provider -> M.t_Ty -> M.t_Ty =
fun v_provider v_result ->
(match v_provider with
| (Provider (v_identities, v_effects, None)) ->
v_result
| (Provider (v_identities, v_effects, (Some (v_state)))) ->
(M.ProductTy ([v_state; v_result])))
and (* infer.bend:1088 *)
f_state_operations_distinct : M.t_TypeId -> M.t_TypeId -> Base.text -> (M.t_Diagnostic, unit) Base.result_ =
fun v_read v_write v_subject ->
(Base.bool_pick ((M.f_type_id_equal (v_read) (v_write))) ((Fail ((M.Diagnostic (s_43, v_subject, s_44))))) ((Done (()))))
and (* infer.bend:1091 *)
f_product_element : (M.t_Ty) list -> int -> Base.text -> (M.t_Diagnostic, M.t_Ty) Base.result_ =
fun v_elements v_index v_subject ->
(match (v_elements, v_index) with
| ((v_head :: v_tail), 0) ->
(Done (v_head))
| ((v_head :: v_tail), __nat_14) when __nat_14 >= 1 ->
(let v_rest = (__nat_14 - 1) in
(f_product_element (v_tail) (v_rest) (v_subject)))
| ([], _) ->
(Fail ((M.Diagnostic (s_45, v_subject, s_46)))))
and (* infer.bend:1100 *)
f_project_type : M.t_Ty -> int -> Base.text -> (M.t_Diagnostic, M.t_Ty) Base.result_ =
fun v_ty v_index v_subject ->
(match v_ty with
| (M.ProductTy (v_elements)) ->
(f_product_element (v_elements) (v_index) (v_subject))
| M.NeverTy ->
(Done (M.NeverTy))
| (M.VariableTy (v_variable)) ->
(Fail ((M.Diagnostic (s_47, v_subject, s_48))))
| v_other ->
(Fail ((M.Diagnostic (s_49, v_subject, (Base.string_append s_50 (M.f_type_show (v_other))))))))
and (* infer.bend:1113 *)
f_deferred_bindings : (t_Coverage) list -> (t_Binding) list =
fun v_constraints ->
(match v_constraints with
| [] ->
[]
| ((OperationNeed (v_identity, v_template, v_arguments, v_function_type, v_subject)) :: v_tail) ->
((Binding (s_51, (M.ProductTy ((v_function_type :: v_arguments))), [], [])) :: (f_deferred_bindings (v_tail)))
| ((AssociatedNeed (v_identity, v_dispatch, v_member, v_templates, v_left, v_right, v_result, v_invocation, v_ambient, v_subject)) :: v_tail) ->
((Binding (s_52, (M.ProductTy ([v_left; v_right; v_result])), [], [])) :: (f_deferred_bindings (v_tail)))
| (v_head :: v_tail) ->
(f_deferred_bindings (v_tail)))
and (* infer.bend:1124 *)
f_let_context : t_Inference -> t_Context -> t_Context =
fun v_inference v_context ->
(match v_inference with
| (Inference ((M.FunctionTy (v_parameter, v_result, v_row)), v_coverage, v_exits, v_reflections, v_predicates, v_uses)) ->
v_context
| (Inference (v_ty, v_coverage, v_exits, v_reflections, v_predicates, v_uses)) ->
(f_extend (v_context) ((f_deferred_bindings (v_coverage)))))
and (* infer.bend:1133 *)
f_template_value : int -> M.t_Expr -> bool =
fun v_fuel v_expression ->
(match (v_fuel, v_expression) with
| (0, _) ->
false
| (__nat_15, (M.SourceExpr (v_offset, v_annotation, v_value))) when __nat_15 >= 1 ->
(let v_rest = (__nat_15 - 1) in
(f_template_value (v_rest) (v_value)))
| (__nat_16, (M.QualifiedExpr (v_offset, v_annotation, v_predicates, v_value))) when __nat_16 >= 1 ->
(let v_rest = (__nat_16 - 1) in
(f_template_value (v_rest) (v_value)))
| (__nat_17, (M.InstantiationExpr (v_site, v_value))) when __nat_17 >= 1 ->
(let v_rest = (__nat_17 - 1) in
(f_template_value (v_rest) (v_value)))
| (_, (M.FunctionExpr (v_name))) ->
true
| (_, (M.ConstantExpr (v_name))) ->
true
| (_, (M.ConstructorRefExpr (v_constructor))) ->
true
| (_, (M.GenericOperationExpr (v_identity, v_template, v_arguments))) ->
true
| (_, (M.LambdaExpr (v_identity, v_parameter, v_p, v_r, v_body))) ->
true
| (_, _) ->
false)
and (* infer.bend:1156 *)
f_computed_predicate_variables : bool -> (M.t_Predicate) list -> t_State -> (M.t_Diagnostic, (int) list) Base.result_ =
fun v_template v_predicates v_state ->
(match v_template with
| true ->
(Done ([]))
| false ->
(match (C.f_resolve_list ((f_substitutions_of (v_state))) (v_predicates)) with
| Fail __error -> Fail __error
| Done v_resolved ->
(C.f_free_list (v_resolved))))
and (* infer.bend:1165 *)
f_tag_coverage : (t_Coverage) list -> Base.text -> (t_Coverage) list =
fun v_needs v_subject ->
(match v_needs with
| [] ->
[]
| ((OperationNeed (v_identity, v_template, v_arguments, v_function_type, v_old_subject)) :: v_tail) ->
((OperationNeed (v_identity, v_template, v_arguments, v_function_type, v_subject)) :: (f_tag_coverage (v_tail) (v_subject)))
| ((AssociatedNeed (v_identity, v_dispatch, v_member, v_templates, v_left, v_right, v_result, v_invocation, v_ambient, v_old_subject)) :: v_tail) ->
((AssociatedNeed (v_identity, v_dispatch, v_member, v_templates, v_left, v_right, v_result, v_invocation, v_ambient, v_subject)) :: (f_tag_coverage (v_tail) (v_subject)))
| ((QualifiedNeed (v_site, v_predicate, v_old_subject)) :: v_tail) ->
((QualifiedNeed (v_site, v_predicate, v_subject)) :: (f_tag_coverage (v_tail) (v_subject)))
| ((QualifiedBoundary (v_offset, v_declared, v_old_subject)) :: v_tail) ->
((QualifiedBoundary (v_offset, v_declared, v_subject)) :: (f_tag_coverage (v_tail) (v_subject)))
| ((ValuePatternType (v_inferred_type, v_old_subject)) :: v_tail) ->
((ValuePatternType (v_inferred_type, v_subject)) :: (f_tag_coverage (v_tail) (v_subject)))
| ((Coverage (v_inferred_types, v_patterns, v_old_subject)) :: v_tail) ->
((Coverage (v_inferred_types, v_patterns, v_subject)) :: (f_tag_coverage (v_tail) (v_subject)))
| (v_head :: v_tail) ->
(v_head :: (f_tag_coverage (v_tail) (v_subject))))
and (* infer.bend:1184 *)
f_tag_uses : (C.t_UsePlan) list -> Base.text -> (C.t_UsePlan) list =
fun v_plans v_subject ->
(match v_plans with
| [] ->
[]
| ((C.UsePlan (v_site, v_old_subject, v_ty, v_predicates)) :: v_tail) ->
((C.UsePlan (v_site, v_subject, v_ty, v_predicates)) :: (f_tag_uses (v_tail) (v_subject))))
and (* infer.bend:1191 *)
f_tag_reflections : (t_Reflection) list -> Base.text -> (t_Reflection) list =
fun v_reflections v_subject ->
(match v_reflections with
| [] ->
[]
| ((Reflection (v_callee, v_old_subject, v_ty, v_predicates)) :: v_tail) ->
((Reflection (v_callee, v_subject, v_ty, v_predicates)) :: (f_tag_reflections (v_tail) (v_subject))))
and (* infer.bend:1198 *)
f_tag_typing : (M.t_Diagnostic, t_Typing) Base.result_ -> int -> (M.t_Diagnostic, t_Typing) Base.result_ =
fun v_result v_offset ->
(match v_result with
| (Done ((Typing ((Inference (v_ty, v_coverage, v_exits, v_reflections, v_predicates, v_uses)), v_state)))) ->
(let v_subject = (Base.string_append s_53 (Base.nat_show (v_offset))) in
(Done ((Typing ((Inference (v_ty, (f_tag_coverage (v_coverage) (v_subject)), v_exits, (f_tag_reflections (v_reflections) (v_subject)), v_predicates, (f_tag_uses (v_uses) (v_subject)))), v_state)))))
| (Fail ((M.Diagnostic (v_code, v_subject, v_message)))) ->
(Fail ((M.Diagnostic (v_code, (Base.string_append s_53 (Base.nat_show (v_offset))), v_message)))))
and (* infer.bend:1206 *)
f_expr_work : int -> t_Work -> t_Context -> t_State -> (M.t_Diagnostic, t_Typing) Base.result_ =
fun v_fuel v_work v_context v_state ->
(match (v_fuel, v_work) with
| (0, _) ->
(Fail ((M.Diagnostic (s_54, (f_context_subject (v_context)), s_55))))
| (__nat_18, (Expression (M.UnitExpr))) when __nat_18 >= 1 ->
(let v_rest = (__nat_18 - 1) in
(Done ((Typing ((f_pure (M.UnitTy)), v_state)))))
| (__nat_19, (Expression ((M.U32Expr (v_value))))) when __nat_19 >= 1 ->
(let v_rest = (__nat_19 - 1) in
(Done ((Typing ((f_pure (M.U32Ty)), v_state)))))
| (__nat_20, (Expression ((M.F32Expr (v_value))))) when __nat_20 >= 1 ->
(let v_rest = (__nat_20 - 1) in
(Done ((Typing ((f_pure (M.F32Ty)), v_state)))))
| (__nat_21, (Expression ((M.BoolExpr (v_value))))) when __nat_21 >= 1 ->
(let v_rest = (__nat_21 - 1) in
(Done ((Typing ((f_pure (M.BoolTy)), v_state)))))
| (__nat_22, (Expression ((M.PanicExpr (v_message))))) when __nat_22 >= 1 ->
(let v_rest = (__nat_22 - 1) in
(Done ((Typing ((f_pure (M.NeverTy)), v_state)))))
| (__nat_23, (Expression ((M.ProductExpr (v_elements))))) when __nat_23 >= 1 ->
(let v_rest = (__nat_23 - 1) in
(match (D.f_require_product_arity ((Base.list_length (v_elements))) ((f_context_subject (v_context)))) with
| Fail __error -> Fail __error
| Done v_arity ->
(f_expr_work (v_rest) ((ProductValues (v_elements, [], (f_pure (M.UnitTy))))) (v_context) (v_state))))
| (__nat_24, (Expression ((M.ProjectExpr (v_value, v_index))))) when __nat_24 >= 1 ->
(let v_rest = (__nat_24 - 1) in
(match (f_expr_work (v_rest) ((Expression (v_value))) (v_context) (v_state)) with
| Fail __error -> Fail __error
| Done v_v ->
(match (T.f_resolve ((f_substitutions_of ((f_state_of (v_v))))) ((f_type_of (v_v)))) with
| Fail __error -> Fail __error
| Done v_resolved ->
(match (f_project_type (v_resolved) (v_index) ((f_context_subject (v_context)))) with
| Fail __error -> Fail __error
| Done v_result ->
(Done ((Typing ((f_join ((f_inference_of (v_v))) ((f_pure (M.UnitTy))) (v_result)), (f_state_of (v_v))))))))))
| (__nat_25, (Expression ((M.ArrayExpr (v_elements))))) when __nat_25 >= 1 ->
(let v_rest = (__nat_25 - 1) in
(f_expr_work (v_rest) ((ArrayValues (v_elements, (M.VariableTy ((f_next_of (v_state)))), (f_pure (M.UnitTy))))) (v_context) ((f_with_next (v_state) ((Base.nat_add 1 (f_next_of (v_state))))))))
| (__nat_26, (Expression ((M.ForExpr (v_index, v_start, v_end, v_carried, v_initial, v_body))))) when __nat_26 >= 1 ->
(let v_rest = (__nat_26 - 1) in
(match (f_expr_work (v_rest) ((Expression (v_start))) (v_context) (v_state)) with
| Fail __error -> Fail __error
| Done v_a ->
(match (f_unify ((f_type_of (v_a))) (M.U32Ty) ((f_state_of (v_a))) ((f_context_subject (v_context)))) with
| Fail __error -> Fail __error
| Done v_s1 ->
(match (f_expr_work (v_rest) ((Expression (v_end))) (v_context) (v_s1)) with
| Fail __error -> Fail __error
| Done v_b ->
(match (f_unify ((f_type_of (v_b))) (M.U32Ty) ((f_state_of (v_b))) ((f_context_subject (v_context)))) with
| Fail __error -> Fail __error
| Done v_s2 ->
(match (f_expr_work (v_rest) ((Expression (v_initial))) (v_context) (v_s2)) with
| Fail __error -> Fail __error
| Done v_v ->
(match (f_expr_work (v_rest) ((Expression (v_body))) ((f_extend (v_context) ([(Binding (v_index, M.U32Ty, [], [])); (Binding (v_carried, (f_type_of (v_v)), [], []))]))) ((f_state_of (v_v)))) with
| Fail __error -> Fail __error
| Done v_loop ->
(match (f_unify ((f_type_of (v_loop))) ((f_type_of (v_v))) ((f_state_of (v_loop))) ((f_context_subject (v_context)))) with
| Fail __error -> Fail __error
| Done v_next ->
(let v_result = (f_flow ((f_type_of (v_a))) ((f_flow ((f_type_of (v_b))) ((f_type_of (v_v)))))) in
(Done ((Typing ((f_sequence ((f_inference_of (v_a))) ((f_sequence ((f_inference_of (v_b))) ((f_sequence ((f_inference_of (v_v))) ((f_inference_of (v_loop))) (v_result))) (v_result))) (v_result)), v_next)))))))))))))
| (__nat_27, (Expression ((M.ForeverExpr (v_carried, v_initial, v_body))))) when __nat_27 >= 1 ->
(let v_rest = (__nat_27 - 1) in
(match (f_expr_work (v_rest) ((Expression (v_initial))) (v_context) (v_state)) with
| Fail __error -> Fail __error
| Done v_v ->
(match (f_expr_work (v_rest) ((Expression (v_body))) ((f_extend (v_context) ([(Binding (v_carried, (f_type_of (v_v)), [], []))]))) ((f_state_of (v_v)))) with
| Fail __error -> Fail __error
| Done v_loop ->
(match (f_unify ((f_type_of (v_loop))) ((f_type_of (v_v))) ((f_state_of (v_loop))) ((f_context_subject (v_context)))) with
| Fail __error -> Fail __error
| Done v_next ->
(let v_result = M.NeverTy in
(Done ((Typing ((f_sequence ((f_inference_of (v_v))) ((f_inference_of (v_loop))) (v_result)), v_next)))))))))
| (__nat_28, (Expression ((M.ArrayGenerateExpr (v_count, v_generator))))) when __nat_28 >= 1 ->
(let v_rest = (__nat_28 - 1) in
(match (f_expr_work (v_rest) ((Expression (v_count))) (v_context) (v_state)) with
| Fail __error -> Fail __error
| Done v_c ->
(match (f_expr_work (v_rest) ((Expression (v_generator))) (v_context) ((f_state_of (v_c)))) with
| Fail __error -> Fail __error
| Done v_g ->
(let v_element = (M.VariableTy ((f_next_of ((f_state_of (v_g)))))) in
(match (f_unify ((f_type_of (v_c))) (M.U32Ty) ((f_with_next ((f_state_of (v_g))) ((Base.nat_add 1 (f_next_of ((f_state_of (v_g)))))))) ((f_context_subject (v_context)))) with
| Fail __error -> Fail __error
| Done v_s1 ->
(match (f_unify ((f_type_of (v_g))) ((M.FunctionTy (M.U32Ty, v_element, (M.EffectRow ([], M.ClosedRow))))) (v_s1) ((f_context_subject (v_context)))) with
| Fail __error -> Fail __error
| Done v_next ->
(let v_result = (f_flow ((f_type_of (v_c))) ((f_flow ((f_type_of (v_g))) ((M.ArrayTy (v_element)))))) in
(Done ((Typing ((f_sequence ((f_inference_of (v_c))) ((f_inference_of (v_g))) (v_result)), v_next)))))))))))
| (__nat_29, (Expression ((M.ArrayFillExpr (v_count, v_value))))) when __nat_29 >= 1 ->
(let v_rest = (__nat_29 - 1) in
(match (f_expr_work (v_rest) ((Expression (v_count))) (v_context) (v_state)) with
| Fail __error -> Fail __error
| Done v_c ->
(match (f_expr_work (v_rest) ((Expression (v_value))) (v_context) ((f_state_of (v_c)))) with
| Fail __error -> Fail __error
| Done v_v ->
(match (f_unify ((f_type_of (v_c))) (M.U32Ty) ((f_state_of (v_v))) ((f_context_subject (v_context)))) with
| Fail __error -> Fail __error
| Done v_next ->
(let v_result = (f_flow ((f_type_of (v_c))) ((f_flow ((f_type_of (v_v))) ((M.ArrayTy ((f_type_of (v_v)))))))) in
(Done ((Typing ((f_sequence ((f_inference_of (v_c))) ((f_inference_of (v_v))) (v_result)), v_next)))))))))
| (__nat_30, (Expression ((M.ArrayGetExpr (v_array, v_index))))) when __nat_30 >= 1 ->
(let v_rest = (__nat_30 - 1) in
(match (f_expr_work (v_rest) ((Expression (v_array))) (v_context) (v_state)) with
| Fail __error -> Fail __error
| Done v_a ->
(match (f_expr_work (v_rest) ((Expression (v_index))) (v_context) ((f_state_of (v_a)))) with
| Fail __error -> Fail __error
| Done v_i ->
(let v_element = (M.VariableTy ((f_next_of ((f_state_of (v_i)))))) in
(match (f_unify ((f_type_of (v_a))) ((M.ArrayTy (v_element))) ((f_with_next ((f_state_of (v_i))) ((Base.nat_add 1 (f_next_of ((f_state_of (v_i)))))))) ((f_context_subject (v_context)))) with
| Fail __error -> Fail __error
| Done v_s1 ->
(match (f_unify ((f_type_of (v_i))) (M.U32Ty) (v_s1) ((f_context_subject (v_context)))) with
| Fail __error -> Fail __error
| Done v_s2 ->
(Done ((Typing ((f_sequence ((f_inference_of (v_a))) ((f_inference_of (v_i))) ((f_flow ((f_type_of (v_a))) ((f_flow ((f_type_of (v_i))) (v_element)))))), v_s2))))))))))
| (__nat_31, (Expression ((M.ArraySetExpr (v_array, v_index, v_value))))) when __nat_31 >= 1 ->
(let v_rest = (__nat_31 - 1) in
(match (f_expr_work (v_rest) ((Expression (v_array))) (v_context) (v_state)) with
| Fail __error -> Fail __error
| Done v_a ->
(match (f_expr_work (v_rest) ((Expression (v_index))) (v_context) ((f_state_of (v_a)))) with
| Fail __error -> Fail __error
| Done v_i ->
(match (f_expr_work (v_rest) ((Expression (v_value))) (v_context) ((f_state_of (v_i)))) with
| Fail __error -> Fail __error
| Done v_v ->
(let v_element = (M.VariableTy ((f_next_of ((f_state_of (v_v)))))) in
(match (f_unify ((f_type_of (v_a))) ((M.ArrayTy (v_element))) ((f_with_next ((f_state_of (v_v))) ((Base.nat_add 1 (f_next_of ((f_state_of (v_v)))))))) ((f_context_subject (v_context)))) with
| Fail __error -> Fail __error
| Done v_s1 ->
(match (f_unify ((f_type_of (v_i))) (M.U32Ty) (v_s1) ((f_context_subject (v_context)))) with
| Fail __error -> Fail __error
| Done v_s2 ->
(match (f_unify ((f_type_of (v_v))) (v_element) (v_s2) ((f_context_subject (v_context)))) with
| Fail __error -> Fail __error
| Done v_s3 ->
(let v_result = (f_flow ((f_type_of (v_a))) ((f_flow ((f_type_of (v_i))) ((f_flow ((f_type_of (v_v))) ((M.ArrayTy (v_element)))))))) in
(Done ((Typing ((f_sequence ((f_inference_of (v_a))) ((f_sequence ((f_inference_of (v_i))) ((f_inference_of (v_v))) (v_result))) (v_result)), v_s3)))))))))))))
| (__nat_32, (Expression ((M.ArrayLengthExpr (v_array))))) when __nat_32 >= 1 ->
(let v_rest = (__nat_32 - 1) in
(match (f_expr_work (v_rest) ((Expression (v_array))) (v_context) (v_state)) with
| Fail __error -> Fail __error
| Done v_a ->
(let v_element = (M.VariableTy ((f_next_of ((f_state_of (v_a)))))) in
(match (f_unify ((f_type_of (v_a))) ((M.ArrayTy (v_element))) ((f_with_next ((f_state_of (v_a))) ((Base.nat_add 1 (f_next_of ((f_state_of (v_a)))))))) ((f_context_subject (v_context)))) with
| Fail __error -> Fail __error
| Done v_next ->
(Done ((Typing ((f_join ((f_inference_of (v_a))) ((f_pure (M.UnitTy))) ((f_flow ((f_type_of (v_a))) (M.U32Ty)))), v_next))))))))
| (__nat_33, (Expression ((M.LocalExpr (v_name))))) when __nat_33 >= 1 ->
(let v_rest = (__nat_33 - 1) in
(match (f_instantiate_binding ((f_lookup_local (v_context) (v_name))) (v_state) (v_name) ((f_context_subject (v_context)))) with
| Fail __error -> Fail __error
| Done v_found ->
(Done (v_found))))
| (__nat_34, (Expression ((M.ConstantExpr (v_name))))) when __nat_34 >= 1 ->
(let v_rest = (__nat_34 - 1) in
(match (f_valid_global_kind (v_context) (v_name) (false)) with
| Fail __error -> Fail __error
| Done v_valid ->
(match (f_instantiate_binding ((f_lookup_global (v_context) (v_name))) (v_state) (v_name) ((f_context_subject (v_context)))) with
| Fail __error -> Fail __error
| Done v_found ->
(Done (v_found)))))
| (__nat_35, (Expression ((M.FunctionExpr (v_name))))) when __nat_35 >= 1 ->
(let v_rest = (__nat_35 - 1) in
(match (f_valid_global_kind (v_context) (v_name) (true)) with
| Fail __error -> Fail __error
| Done v_valid ->
(f_instantiate_binding ((f_lookup_global (v_context) (v_name))) (v_state) (v_name) ((f_context_subject (v_context))))))
| (__nat_36, (Expression ((M.ConstructorRefExpr (v_name))))) when __nat_36 >= 1 ->
(let v_rest = (__nat_36 - 1) in
(match (f_constructor_instance (v_name) (v_context) (v_state)) with
| Fail __error -> Fail __error
| Done v_ctor ->
(Done ((Typing ((f_pure ((f_constructor_type (v_ctor)))), (f_constructor_state (v_ctor) (v_state))))))))
| (__nat_37, (Expression ((M.ConstructExpr (v_name, None))))) when __nat_37 >= 1 ->
(let v_rest = (__nat_37 - 1) in
(match (f_constructor_instance (v_name) (v_context) (v_state)) with
| Fail __error -> Fail __error
| Done v_ctor ->
(match (f_no_payload ((f_constructor_payload (v_ctor))) ((f_context_subject (v_context)))) with
| Fail __error -> Fail __error
| Done v_arity ->
(Done ((Typing ((f_pure ((f_constructor_result (v_ctor)))), (f_constructor_state (v_ctor) (v_state)))))))))
| (__nat_38, (Expression ((M.ConstructExpr (v_name, (Some (v_payload))))))) when __nat_38 >= 1 ->
(let v_rest = (__nat_38 - 1) in
(match (f_constructor_instance (v_name) (v_context) (v_state)) with
| Fail __error -> Fail __error
| Done v_ctor ->
(match (f_payload_type ((f_constructor_payload (v_ctor))) ((f_context_subject (v_context)))) with
| Fail __error -> Fail __error
| Done v_expected ->
(match (f_expr_work (v_rest) ((Expression (v_payload))) (v_context) ((f_constructor_state (v_ctor) (v_state)))) with
| Fail __error -> Fail __error
| Done v_value ->
(match (f_unify ((f_type_of (v_value))) (v_expected) ((f_state_of (v_value))) ((f_context_subject (v_context)))) with
| Fail __error -> Fail __error
| Done v_next ->
(Done ((Typing ((f_join ((f_inference_of (v_value))) ((f_pure (M.UnitTy))) ((f_flow ((f_type_of (v_value))) ((f_constructor_result (v_ctor)))))), v_next)))))))))
| (__nat_39, (Expression ((M.LambdaExpr (v_identity, v_parameter, v_p, v_r, v_body))))) when __nat_39 >= 1 ->
(let v_rest = (__nat_39 - 1) in
(let v_parameter_ty = (M.VariableTy ((f_next_of (v_state)))) in
(let v_result_ty = (M.VariableTy ((Base.nat_add 1 (f_next_of (v_state))))) in
(let v_row = (R.f_variable_row ((Base.nat_add 2 (f_next_of (v_state))))) in
(match (f_annotation (v_p) (v_parameter_ty) ((f_with_next (v_state) ((Base.nat_add 3 (f_next_of (v_state)))))) (v_context)) with
| Fail __error -> Fail __error
| Done v_s1 ->
(match (f_annotation (v_r) (v_result_ty) (v_s1) (v_context)) with
| Fail __error -> Fail __error
| Done v_s2 ->
(match (f_expr_work (v_rest) ((Expression (v_body))) ((f_in_lambda (v_context) (v_parameter) (v_parameter_ty) (v_row))) (v_s2)) with
| Fail __error -> Fail __error
| Done v_value ->
(match (f_unify ((f_type_of (v_value))) (v_result_ty) ((f_state_of (v_value))) ((f_context_subject (v_context)))) with
| Fail __error -> Fail __error
| Done v_next ->
(Done ((Typing ((f_lambda_value ((f_inference_of (v_value))) (v_parameter_ty) (v_result_ty) (v_row)), v_next))))))))))))
| (__nat_40, (Expression ((M.ApplyExpr (v_callee, v_argument))))) when __nat_40 >= 1 ->
(let v_rest = (__nat_40 - 1) in
(match (f_expr_work (v_rest) ((Expression (v_callee))) (v_context) (v_state)) with
| Fail __error -> Fail __error
| Done v_fn ->
(match (f_expr_work (v_rest) ((Expression (v_argument))) (v_context) ((f_state_of (v_fn)))) with
| Fail __error -> Fail __error
| Done v_arg ->
(let v_result = (M.VariableTy ((f_next_of ((f_state_of (v_arg)))))) in
(match (f_unify ((f_type_of (v_fn))) ((M.FunctionTy ((f_type_of (v_arg)), v_result, (f_context_row (v_context))))) ((f_with_next ((f_state_of (v_arg))) ((Base.nat_add 1 (f_next_of ((f_state_of (v_arg)))))))) ((f_context_subject (v_context)))) with
| Fail __error -> Fail __error
| Done v_next ->
(Done ((Typing ((f_sequence ((f_inference_of (v_fn))) ((f_inference_of (v_arg))) ((f_flow ((f_type_of (v_fn))) ((f_flow ((f_type_of (v_arg))) (v_result)))))), v_next)))))))))
| (__nat_41, (Expression ((M.TagExpr (v_offset, v_callee, v_argument))))) when __nat_41 >= 1 ->
(let v_rest = (__nat_41 - 1) in
(let v_at = (f_at_subject (v_context) ((Base.string_append s_53 (Base.nat_show (v_offset))))) in
(match (f_tag_typing ((f_expr_work (v_rest) ((Expression (v_callee))) (v_at) (v_state))) (v_offset)) with
| Fail __error -> Fail __error
| Done v_fn ->
(match (f_expr_work (v_rest) ((Expression (v_argument))) (v_context) ((f_state_of (v_fn)))) with
| Fail __error -> Fail __error
| Done v_arg ->
(let v_result = (M.VariableTy ((f_next_of ((f_state_of (v_arg)))))) in
(match (f_unify ((f_type_of (v_fn))) ((M.FunctionTy ((f_type_of (v_arg)), v_result, (f_context_row (v_context))))) ((f_with_next ((f_state_of (v_arg))) ((Base.nat_add 1 (f_next_of ((f_state_of (v_arg)))))))) ((f_context_subject (v_at)))) with
| Fail __error -> Fail __error
| Done v_next ->
(Done ((Typing ((f_sequence ((f_inference_of (v_fn))) ((f_inference_of (v_arg))) ((f_flow ((f_type_of (v_fn))) ((f_flow ((f_type_of (v_arg))) (v_result)))))), v_next))))))))))
| (__nat_42, (Expression ((M.CallExpr (v_callee, v_argument))))) when __nat_42 >= 1 ->
(let v_rest = (__nat_42 - 1) in
(match (f_valid_global_kind (v_context) (v_callee) (true)) with
| Fail __error -> Fail __error
| Done v_valid ->
(match (f_instantiate_binding ((f_lookup_global (v_context) (v_callee))) (v_state) (v_callee) ((f_context_subject (v_context)))) with
| Fail __error -> Fail __error
| Done v_fn ->
(match (f_expr_work (v_rest) ((Expression (v_argument))) (v_context) ((f_state_of (v_fn)))) with
| Fail __error -> Fail __error
| Done v_arg ->
(let v_result = (M.VariableTy ((f_next_of ((f_state_of (v_arg)))))) in
(match (f_unify ((f_type_of (v_fn))) ((M.FunctionTy ((f_type_of (v_arg)), v_result, (f_context_row (v_context))))) ((f_with_next ((f_state_of (v_arg))) ((Base.nat_add 1 (f_next_of ((f_state_of (v_arg)))))))) ((f_context_subject (v_context)))) with
| Fail __error -> Fail __error
| Done v_next ->
(Done ((Typing ((f_join ((f_inference_of (v_fn))) ((f_inference_of (v_arg))) ((f_flow ((f_type_of (v_arg))) (v_result)))), v_next))))))))))
| (__nat_43, (Expression ((M.AssociatedExpr (v_identity, v_dispatch, v_member, v_templates, v_left, v_right))))) when __nat_43 >= 1 ->
(let v_rest = (__nat_43 - 1) in
(match (f_expr_work (v_rest) ((Expression (v_left))) (v_context) (v_state)) with
| Fail __error -> Fail __error
| Done v_l ->
(match (f_expr_work (v_rest) ((Expression (v_right))) (v_context) ((f_state_of (v_l)))) with
| Fail __error -> Fail __error
| Done v_r ->
(let v_result = (M.VariableTy ((f_next_of ((f_state_of (v_r)))))) in
(let v_joined = (f_sequence ((f_inference_of (v_l))) ((f_inference_of (v_r))) ((f_flow ((f_type_of (v_l))) ((f_flow ((f_type_of (v_r))) (v_result)))))) in
(match (f_associated_shape ((M.f_name_equal (v_member) (s_56))) ((TypedState.f_request (v_member))) ((f_type_of (v_l))) ((f_type_of (v_r))) (v_result) ((f_with_next ((f_state_of (v_r))) ((Base.nat_add 1 (f_next_of ((f_state_of (v_r)))))))) ((f_context_subject (v_context)))) with
| Fail __error -> Fail __error
| Done v_shaped ->
(let v_invocation = (R.f_variable_row ((f_next_of (v_shaped)))) in
(let v_need = (f_associated_predicate (v_dispatch) (v_member) (v_templates) ((f_type_of (v_l))) ((f_type_of (v_r))) (v_result) (v_invocation)) in
(Done ((Typing ((f_with_predicate ((f_with_pattern_constraints (v_joined) ([(AssociatedNeed (v_identity, v_dispatch, v_member, v_templates, (f_type_of (v_l)), (f_type_of (v_r)), v_result, (Some (v_invocation)), (f_context_row (v_context)), (f_context_subject (v_context))))]))) (v_need)), (f_with_next (v_shaped) ((Base.nat_add 1 (f_next_of (v_shaped)))))))))))))))))
| (__nat_44, (Expression ((M.ScalarExpr (v_operator, v_left, v_right))))) when __nat_44 >= 1 ->
(let v_rest = (__nat_44 - 1) in
(match (f_expr_work (v_rest) ((Expression (v_left))) (v_context) (v_state)) with
| Fail __error -> Fail __error
| Done v_l ->
(match (f_expr_work (v_rest) ((Expression (v_right))) (v_context) ((f_state_of (v_l)))) with
| Fail __error -> Fail __error
| Done v_r ->
(match (f_unify ((f_type_of (v_l))) ((M.f_scalar_parameter (v_operator))) ((f_state_of (v_r))) ((f_context_subject (v_context)))) with
| Fail __error -> Fail __error
| Done v_s1 ->
(match (f_unify ((f_type_of (v_r))) ((M.f_scalar_parameter (v_operator))) (v_s1) ((f_context_subject (v_context)))) with
| Fail __error -> Fail __error
| Done v_s2 ->
(Done ((Typing ((f_sequence ((f_inference_of (v_l))) ((f_inference_of (v_r))) ((f_flow ((f_type_of (v_l))) ((f_flow ((f_type_of (v_r))) ((M.f_scalar_result (v_operator)))))))), v_s2)))))))))
| (__nat_45, (Expression ((M.UnaryExpr (v_operator, v_value))))) when __nat_45 >= 1 ->
(let v_rest = (__nat_45 - 1) in
(match (f_expr_work (v_rest) ((Expression (v_value))) (v_context) (v_state)) with
| Fail __error -> Fail __error
| Done v_v ->
(match (f_unify ((f_type_of (v_v))) ((M.f_unary_parameter (v_operator))) ((f_state_of (v_v))) ((f_context_subject (v_context)))) with
| Fail __error -> Fail __error
| Done v_next ->
(Done ((Typing ((f_join ((f_inference_of (v_v))) ((f_pure (M.UnitTy))) ((f_flow ((f_type_of (v_v))) ((M.f_unary_result (v_operator)))))), v_next)))))))
| (__nat_46, (Expression ((M.LetExpr (v_name, v_value, v_body))))) when __nat_46 >= 1 ->
(let v_rest = (__nat_46 - 1) in
(let v_row = (R.f_variable_row ((f_next_of (v_state)))) in
(match (f_expr_work (v_rest) ((Expression (v_value))) ((f_with_row (v_context) (v_row))) ((f_with_next (v_state) ((Base.nat_add 1 (f_next_of (v_state))))))) with
| Fail __error -> Fail __error
| Done v_v ->
(match (f_require_pure (v_row) ((f_state_of (v_v))) ((f_context_subject (v_context))) (s_57)) with
| Fail __error -> Fail __error
| Done v_pure_state ->
(let v_local_state = (f_local_annotation_state (v_value) (v_pure_state) (v_state)) in
(match (f_computed_predicate_variables ((f_template_value (65536) (v_value))) ((f_inference_predicates ((f_inference_of (v_v))))) (v_local_state)) with
| Fail __error -> Fail __error
| Done v_blocked ->
(match (f_generalization_qualified_excluding ((f_type_of (v_v))) ((f_inference_predicates ((f_inference_of (v_v))))) ((f_let_context ((f_inference_of (v_v))) (v_context))) (v_local_state) (v_name) (v_blocked)) with
| Fail __error -> Fail __error
| Done v_generalized ->
(match (f_let_generalized ((f_generalization_variables (v_generalized))) ((f_inference_coverage ((f_inference_of (v_v))))) ((f_substitutions_of (v_local_state)))) with
| Fail __error -> Fail __error
| Done v_evidence ->
(match (f_expr_work (v_rest) ((Expression (v_body))) ((f_extend (v_context) ([(f_generalization_binding (v_generalized))]))) (v_local_state)) with
| Fail __error -> Fail __error
| Done v_b ->
(Done ((Typing ((f_with_pattern_constraints ((f_sequence ((f_without_residual ((f_inference_of (v_v))))) ((f_inference_of (v_b))) ((f_flow ((f_type_of (v_v))) ((f_type_of (v_b))))))) (v_evidence)), (f_state_of (v_b)))))))))))))))
| (__nat_47, (Expression ((M.UseExpr (v_name, v_value, v_body))))) when __nat_47 >= 1 ->
(let v_rest = (__nat_47 - 1) in
(match (f_expr_work (v_rest) ((Expression (v_value))) (v_context) (v_state)) with
| Fail __error -> Fail __error
| Done v_v ->
(match (f_expr_work (v_rest) ((Expression (v_body))) ((f_extend (v_context) ([(Binding (v_name, (f_type_of (v_v)), [], []))]))) ((f_state_of (v_v)))) with
| Fail __error -> Fail __error
| Done v_b ->
(Done ((Typing ((f_sequence ((f_inference_of (v_v))) ((f_inference_of (v_b))) ((f_flow ((f_type_of (v_v))) ((f_type_of (v_b)))))), (f_state_of (v_b)))))))))
| (__nat_48, (Expression ((M.InstantiationExpr (v_site, v_value))))) when __nat_48 >= 1 ->
(let v_rest = (__nat_48 - 1) in
(match (f_expr_work (v_rest) ((Expression (v_value))) (v_context) (v_state)) with
| Fail __error -> Fail __error
| Done v_v ->
(Done ((Typing ((f_with_use ((f_inference_of (v_v))) (v_site) ((f_context_subject (v_context)))), (f_state_of (v_v))))))))
| (__nat_49, (Expression ((M.IfExpr (v_condition, v_consequent, v_alternative))))) when __nat_49 >= 1 ->
(let v_rest = (__nat_49 - 1) in
(match (f_expr_work (v_rest) ((Expression (v_condition))) (v_context) (v_state)) with
| Fail __error -> Fail __error
| Done v_c ->
(match (f_unify ((f_type_of (v_c))) (M.BoolTy) ((f_state_of (v_c))) ((f_context_subject (v_context)))) with
| Fail __error -> Fail __error
| Done v_s1 ->
(match (f_expr_work (v_rest) ((Expression (v_consequent))) (v_context) (v_s1)) with
| Fail __error -> Fail __error
| Done v_y ->
(match (f_expr_work (v_rest) ((Expression (v_alternative))) (v_context) ((f_state_of (v_y)))) with
| Fail __error -> Fail __error
| Done v_n ->
(match (f_unify ((f_type_of (v_y))) ((f_type_of (v_n))) ((f_state_of (v_n))) ((f_context_subject (v_context)))) with
| Fail __error -> Fail __error
| Done v_s2 ->
(let v_result = (f_flow ((f_type_of (v_c))) ((f_branch_type ((f_type_of (v_y))) ((f_type_of (v_n)))))) in
(Done ((Typing ((f_sequence ((f_inference_of (v_c))) ((f_join ((f_inference_of (v_y))) ((f_inference_of (v_n))) (v_result))) (v_result)), v_s2)))))))))))
| (__nat_50, (Expression ((M.SequenceExpr (v_first, v_next))))) when __nat_50 >= 1 ->
(let v_rest = (__nat_50 - 1) in
(match (f_expr_work (v_rest) ((Expression (v_first))) (v_context) (v_state)) with
| Fail __error -> Fail __error
| Done v_a ->
(match (f_expr_work (v_rest) ((Expression (v_next))) (v_context) ((f_state_of (v_a)))) with
| Fail __error -> Fail __error
| Done v_b ->
(Done ((Typing ((f_sequence ((f_inference_of (v_a))) ((f_inference_of (v_b))) ((f_flow ((f_type_of (v_a))) ((f_type_of (v_b)))))), (f_state_of (v_b)))))))))
| (__nat_51, (Expression ((M.MatchExpr ([], v_arms))))) when __nat_51 >= 1 ->
(let v_rest = (__nat_51 - 1) in
(Fail ((M.Diagnostic (s_39, (f_context_subject (v_context)), s_58)))))
| (__nat_52, (Expression ((M.MatchExpr (v_values, v_arms))))) when __nat_52 >= 1 ->
(let v_rest = (__nat_52 - 1) in
(f_expr_work (v_rest) ((MatchValues (v_values, [], v_arms, (f_pure (M.UnitTy))))) (v_context) (v_state)))
| (__nat_53, (Expression ((M.GuardExpr (v_pat, v_value, v_alternative, v_body))))) when __nat_53 >= 1 ->
(let v_rest = (__nat_53 - 1) in
(let v_row = (R.f_variable_row ((f_next_of (v_state)))) in
(match (f_expr_work (v_rest) ((Expression (v_value))) ((f_with_row (v_context) (v_row))) ((f_with_next (v_state) ((Base.nat_add 1 (f_next_of (v_state))))))) with
| Fail __error -> Fail __error
| Done v_v ->
(match (f_require_pure (v_row) ((f_state_of (v_v))) ((f_context_subject (v_context))) (s_57)) with
| Fail __error -> Fail __error
| Done v_pure_state ->
(match (f_infer_pattern (v_pat) ((f_type_of (v_v))) (v_context) ((f_restore_annotations (v_pure_state) (v_state)))) with
| Fail __error -> Fail __error
| Done v_bindings ->
(match (f_expr_work (v_rest) ((Expression (v_alternative))) (v_context) ((f_pattern_state (v_bindings)))) with
| Fail __error -> Fail __error
| Done v_a ->
(match (f_guard_exits ((f_type_of (v_a))) ((f_context_subject (v_context)))) with
| Fail __error -> Fail __error
| Done v_exit ->
(match (f_expr_work (v_rest) ((Expression (v_body))) ((f_extend (v_context) ((f_pattern_bindings (v_bindings))))) ((f_state_of (v_a)))) with
| Fail __error -> Fail __error
| Done v_b ->
(let v_result = (f_flow ((f_type_of (v_v))) ((f_type_of (v_b)))) in
(Done ((Typing ((f_with_pattern_constraints ((f_sequence ((f_inference_of (v_v))) ((f_join ((f_inference_of (v_a))) ((f_inference_of (v_b))) (v_result))) (v_result))) ((f_pattern_constraints (v_bindings)))), (f_state_of (v_b)))))))))))))))
| (__nat_54, (Expression ((M.BlockExpr (v_label, v_body))))) when __nat_54 >= 1 ->
(let v_rest = (__nat_54 - 1) in
(let v_result = (M.VariableTy ((f_next_of (v_state)))) in
(match (f_expr_work (v_rest) ((Expression (v_body))) ((f_in_block (v_context) (v_label) (v_result))) ((f_with_next (v_state) ((Base.nat_add 1 (f_next_of (v_state))))))) with
| Fail __error -> Fail __error
| Done v_b ->
(match (f_unify ((f_type_of (v_b))) (v_result) ((f_state_of (v_b))) ((f_context_subject (v_context)))) with
| Fail __error -> Fail __error
| Done v_next ->
(Done ((Typing ((f_block_value ((f_inference_of (v_b))) (v_label) (v_result)), v_next))))))))
| (__nat_55, (Expression ((M.ReturnExpr (v_label, v_value))))) when __nat_55 >= 1 ->
(let v_rest = (__nat_55 - 1) in
(match (f_return_type (v_context) (v_label)) with
| Fail __error -> Fail __error
| Done v_target ->
(match (f_expr_work (v_rest) ((Expression (v_value))) (v_context) (v_state)) with
| Fail __error -> Fail __error
| Done v_v ->
(match (f_unify ((f_type_of (v_v))) (v_target) ((f_state_of (v_v))) ((f_context_subject (v_context)))) with
| Fail __error -> Fail __error
| Done v_next ->
(Done ((Typing ((f_return_value ((f_inference_of (v_v))) (v_label)), v_next))))))))
| (__nat_56, (Expression ((M.RuntimeInitExpr (v_value))))) when __nat_56 >= 1 ->
(let v_rest = (__nat_56 - 1) in
(f_expr_work (v_rest) ((Expression (v_value))) (v_context) (v_state)))
| (__nat_57, (Expression ((M.SourceExpr (v_offset, v_ann, v_value))))) when __nat_57 >= 1 ->
(let v_rest = (__nat_57 - 1) in
(let v_at = (f_at_subject (v_context) ((Base.string_append s_53 (Base.nat_show (v_offset))))) in
(match (f_expr_work (v_rest) ((Expression (v_value))) (v_at) (v_state)) with
| Fail __error -> Fail __error
| Done v_v ->
(match (f_annotation (v_ann) ((f_type_of (v_v))) ((f_state_of (v_v))) (v_at)) with
| Fail __error -> Fail __error
| Done v_next ->
(Done ((Typing ((f_inference_of (v_v)), v_next))))))))
| (__nat_58, (Expression ((M.QualifiedExpr (v_offset, v_annotation_type, v_predicates, v_value))))) when __nat_58 >= 1 ->
(let v_rest = (__nat_58 - 1) in
(let v_at = (f_at_subject (v_context) ((Base.string_append s_53 (Base.nat_show (v_offset))))) in
(match (f_qualified_annotation (v_annotation_type) (v_predicates) (v_state) (v_at)) with
| Fail __error -> Fail __error
| Done v_prepared ->
(let v_declared_type = (f_qualified_type (v_prepared)) in
(let v_declared = (f_qualified_predicates (v_prepared)) in
(let v_annotated_state = (f_qualified_state (v_prepared)) in
(match (f_constrain_predicates (v_declared) (v_annotated_state) (v_at)) with
| Fail __error -> Fail __error
| Done v_shaped ->
(match (f_expr_work (v_rest) ((Expression (v_value))) (v_at) (v_shaped)) with
| Fail __error -> Fail __error
| Done v_v ->
(match (f_unify ((f_type_of (v_v))) (v_declared_type) ((f_state_of (v_v))) ((f_context_subject (v_at)))) with
| Fail __error -> Fail __error
| Done v_unified ->
(match (f_entail_all ((f_inference_predicates ((f_inference_of (v_v))))) ((f_inference_coverage ((f_inference_of (v_v))))) ((f_inference_uses ((f_inference_of (v_v))))) (v_declared) (v_unified) ((f_context_subject (v_at)))) with
| Fail __error -> Fail __error
| Done v_entailed ->
(match (T.f_open_covariant (v_declared_type) ((f_next_of (v_entailed)))) with
| Fail __error -> Fail __error
| Done v_opened ->
(Done ((Typing ((f_qualified_inference ((f_inference_of (v_v))) (v_offset) ((T.f_opened_type (v_opened))) (v_declared) ((f_context_subject (v_at)))), (f_with_next (v_entailed) ((T.f_opened_next (v_opened)))))))))))))))))))
| (__nat_59, (Expression ((M.GenericOperationExpr (v_identity, v_template, v_arguments))))) when __nat_59 >= 1 ->
(let v_rest = (__nat_59 - 1) in
(match (f_operation_template ((f_context_operations (v_context))) (v_template)) with
| Fail __error -> Fail __error
| Done v_declared ->
(f_generic_operation (v_identity) (v_template) (v_declared) (v_arguments) (v_state) (v_context))))
| (__nat_60, (Expression ((M.OperationExpr (v_identity))))) when __nat_60 >= 1 ->
(let v_rest = (__nat_60 - 1) in
(match (D.f_require_operation ((D.f_operation ((f_context_operations (v_context))) (v_identity))) (v_identity)) with
| Fail __error -> Fail __error
| Done v_declared ->
(Done ((Typing ((f_pure ((f_operation_type (v_declared) ((f_next_of (v_state)))))), (f_with_next (v_state) ((Base.nat_add 1 (f_next_of (v_state)))))))))))
| (__nat_61, (Expression ((M.SpecializeOperationExpr (v_template, v_arguments, v_body))))) when __nat_61 >= 1 ->
(let v_rest = (__nat_61 - 1) in
(Fail ((M.Diagnostic (s_59, s_60, s_61)))))
| (__nat_62, (Expression ((M.StateProviderExpr (v_read, v_write, v_initial))))) when __nat_62 >= 1 ->
(let v_rest = (__nat_62 - 1) in
(match (f_state_operations_distinct (v_read) (v_write) ((f_context_subject (v_context)))) with
| Fail __error -> Fail __error
| Done v_distinct ->
(match (D.f_require_operation ((D.f_operation ((f_context_operations (v_context))) (v_read))) (v_read)) with
| Fail __error -> Fail __error
| Done v_reader ->
(match (D.f_require_operation ((D.f_operation ((f_context_operations (v_context))) (v_write))) (v_write)) with
| Fail __error -> Fail __error
| Done v_writer ->
(match (f_expr_work (v_rest) ((Expression (v_initial))) (v_context) (v_state)) with
| Fail __error -> Fail __error
| Done v_value ->
(match (f_unify ((f_operation_parameter (v_reader))) (M.UnitTy) ((f_state_of (v_value))) ((f_context_subject (v_context)))) with
| Fail __error -> Fail __error
| Done v_s1 ->
(match (f_unify ((f_operation_result (v_writer))) (M.UnitTy) (v_s1) ((f_context_subject (v_context)))) with
| Fail __error -> Fail __error
| Done v_s2 ->
(match (f_unify ((f_operation_result (v_reader))) ((f_operation_parameter (v_writer))) (v_s2) ((f_context_subject (v_context)))) with
| Fail __error -> Fail __error
| Done v_s3 ->
(match (f_unify ((f_type_of (v_value))) ((f_operation_result (v_reader))) (v_s3) ((f_context_subject (v_context)))) with
| Fail __error -> Fail __error
| Done v_s4 ->
(Done ((Typing ((f_join ((f_inference_of (v_value))) ((f_pure (M.UnitTy))) ((f_flow ((f_type_of (v_value))) ((M.StateProviderTy (v_read, v_write, (f_operation_result (v_reader)))))))), v_s4)))))))))))))
| (__nat_63, (Expression ((M.ProviderExpr (v_identity, v_implementation))))) when __nat_63 >= 1 ->
(let v_rest = (__nat_63 - 1) in
(match (D.f_require_operation ((D.f_operation ((f_context_operations (v_context))) (v_identity))) (v_identity)) with
| Fail __error -> Fail __error
| Done v_declared ->
(match (f_expr_work (v_rest) ((Expression (v_implementation))) (v_context) (v_state)) with
| Fail __error -> Fail __error
| Done v_handler ->
(let v_row = (R.f_variable_row ((f_next_of ((f_state_of (v_handler)))))) in
(match (f_unify ((f_type_of (v_handler))) ((M.FunctionTy ((f_operation_parameter (v_declared)), (f_operation_result (v_declared)), v_row))) ((f_with_next ((f_state_of (v_handler))) ((Base.nat_add 1 (f_next_of ((f_state_of (v_handler)))))))) ((f_context_subject (v_context)))) with
| Fail __error -> Fail __error
| Done v_next ->
(Done ((Typing ((f_join ((f_inference_of (v_handler))) ((f_pure (M.UnitTy))) ((f_flow ((f_type_of (v_handler))) ((M.ProviderTy (v_identity, v_row)))))), v_next)))))))))
| (__nat_64, (Expression ((M.HandleExpr (v_provider, v_body))))) when __nat_64 >= 1 ->
(let v_rest = (__nat_64 - 1) in
(match (f_expr_work (v_rest) ((Expression (v_provider))) (v_context) (v_state)) with
| Fail __error -> Fail __error
| Done v_p ->
(match (T.f_resolve ((f_substitutions_of ((f_state_of (v_p))))) ((f_type_of (v_p)))) with
| Fail __error -> Fail __error
| Done v_resolved ->
(match (f_require_provider (v_resolved) ((f_context_subject (v_context)))) with
| Fail __error -> Fail __error
| Done v_supplied ->
(match (f_prepare_provider (v_supplied) (v_context) ((f_state_of (v_p)))) with
| Fail __error -> Fail __error
| Done v_prepared ->
(match (f_expr_work (v_rest) ((Expression (v_body))) ((f_handled_context (v_context) (v_supplied))) (v_prepared)) with
| Fail __error -> Fail __error
| Done v_b ->
(Done ((Typing ((f_sequence ((f_inference_of (v_p))) ((f_inference_of (v_b))) ((f_flow ((f_type_of (v_p))) ((f_handled_result (v_supplied) ((f_type_of (v_b)))))))), (f_state_of (v_b))))))))))))
| (__nat_65, (Expression ((M.OperationDescriptorExpr (v_identity))))) when __nat_65 >= 1 ->
(let v_rest = (__nat_65 - 1) in
(match (D.f_valid_effect_label ((f_context_operations (v_context))) (v_identity)) with
| Fail __error -> Fail __error
| Done v_known ->
(Done ((Typing ((f_pure (M.EffectDescriptorTy)), v_state))))))
| (__nat_66, (Expression ((M.FunctionEffectsExpr (v_callee))))) when __nat_66 >= 1 ->
(let v_rest = (__nat_66 - 1) in
(match (f_valid_global_kind (v_context) (v_callee) (true)) with
| Fail __error -> Fail __error
| Done v_known ->
(match (f_instantiate_binding_selected ((f_lookup_global (v_context) (v_callee))) (v_state) (v_callee) ((f_context_subject (v_context)))) with
| Fail __error -> Fail __error
| Done v_selected ->
(let v_scheme = (f_selected_typing (v_selected)) in
(Done ((Typing ((Inference (M.EffectSetTy, [], [], [(Reflection (v_callee, (f_context_subject (v_context)), (f_selected_exact (v_selected)), (f_inference_predicates ((f_inference_of (v_scheme))))))], [], [])), (f_state_of (v_scheme))))))))))
| (__nat_67, (Expression ((M.EffectHasExpr (v_set, v_operation))))) when __nat_67 >= 1 ->
(let v_rest = (__nat_67 - 1) in
(match (f_expr_work (v_rest) ((Expression (v_set))) (v_context) (v_state)) with
| Fail __error -> Fail __error
| Done v_a ->
(match (f_expr_work (v_rest) ((Expression (v_operation))) (v_context) ((f_state_of (v_a)))) with
| Fail __error -> Fail __error
| Done v_b ->
(match (f_unify ((f_type_of (v_a))) (M.EffectSetTy) ((f_state_of (v_b))) ((f_context_subject (v_context)))) with
| Fail __error -> Fail __error
| Done v_s1 ->
(match (f_unify ((f_type_of (v_b))) (M.EffectDescriptorTy) (v_s1) ((f_context_subject (v_context)))) with
| Fail __error -> Fail __error
| Done v_s2 ->
(Done ((Typing ((f_sequence ((f_inference_of (v_a))) ((f_inference_of (v_b))) ((f_flow ((f_type_of (v_a))) ((f_flow ((f_type_of (v_b))) (M.BoolTy)))))), v_s2)))))))))
| (__nat_68, (Expression ((M.EffectCountExpr (v_set))))) when __nat_68 >= 1 ->
(let v_rest = (__nat_68 - 1) in
(match (f_expr_work (v_rest) ((Expression (v_set))) (v_context) (v_state)) with
| Fail __error -> Fail __error
| Done v_a ->
(match (f_unify ((f_type_of (v_a))) (M.EffectSetTy) ((f_state_of (v_a))) ((f_context_subject (v_context)))) with
| Fail __error -> Fail __error
| Done v_next ->
(Done ((Typing ((f_join ((f_inference_of (v_a))) ((f_pure (M.UnitTy))) ((f_flow ((f_type_of (v_a))) (M.U32Ty)))), v_next)))))))
| (__nat_69, (Expression ((M.EffectSameExpr (v_left, v_right))))) when __nat_69 >= 1 ->
(let v_rest = (__nat_69 - 1) in
(match (f_expr_work (v_rest) ((Expression (v_left))) (v_context) (v_state)) with
| Fail __error -> Fail __error
| Done v_a ->
(match (f_expr_work (v_rest) ((Expression (v_right))) (v_context) ((f_state_of (v_a)))) with
| Fail __error -> Fail __error
| Done v_b ->
(match (f_unify ((f_type_of (v_a))) (M.EffectDescriptorTy) ((f_state_of (v_b))) ((f_context_subject (v_context)))) with
| Fail __error -> Fail __error
| Done v_s1 ->
(match (f_unify ((f_type_of (v_b))) (M.EffectDescriptorTy) (v_s1) ((f_context_subject (v_context)))) with
| Fail __error -> Fail __error
| Done v_s2 ->
(Done ((Typing ((f_sequence ((f_inference_of (v_a))) ((f_inference_of (v_b))) ((f_flow ((f_type_of (v_a))) ((f_flow ((f_type_of (v_b))) (M.BoolTy)))))), v_s2)))))))))
| (__nat_70, (MatchValues ((v_head :: v_tail), v_types, v_arms, v_accumulated))) when __nat_70 >= 1 ->
(let v_rest = (__nat_70 - 1) in
(match (f_expr_work (v_rest) ((Expression (v_head))) (v_context) (v_state)) with
| Fail __error -> Fail __error
| Done v_value ->
(f_expr_work (v_rest) ((MatchValues (v_tail, ((f_type_of (v_value)) :: v_types), v_arms, (f_sequence (v_accumulated) ((f_inference_of (v_value))) ((f_flow ((f_inferred_type (v_accumulated))) ((f_type_of (v_value))))))))) (v_context) ((f_state_of (v_value))))))
| (__nat_71, (ProductValues ((v_head :: v_tail), v_types, v_accumulated))) when __nat_71 >= 1 ->
(let v_rest = (__nat_71 - 1) in
(match (f_expr_work (v_rest) ((Expression (v_head))) (v_context) (v_state)) with
| Fail __error -> Fail __error
| Done v_value ->
(f_expr_work (v_rest) ((ProductValues (v_tail, ((f_type_of (v_value)) :: v_types), (f_sequence (v_accumulated) ((f_inference_of (v_value))) ((f_flow ((f_inferred_type (v_accumulated))) ((f_type_of (v_value))))))))) (v_context) ((f_state_of (v_value))))))
| (__nat_72, (ProductValues ([], v_types, v_accumulated))) when __nat_72 >= 1 ->
(let v_rest = (__nat_72 - 1) in
(Done ((Typing ((f_join (v_accumulated) ((f_pure (M.UnitTy))) ((f_flow ((f_inferred_type (v_accumulated))) ((M.ProductTy ((Base.list_reverse (v_types)))))))), v_state)))))
| (__nat_73, (ArrayValues ((v_head :: v_tail), v_element, v_accumulated))) when __nat_73 >= 1 ->
(let v_rest = (__nat_73 - 1) in
(match (f_expr_work (v_rest) ((Expression (v_head))) (v_context) (v_state)) with
| Fail __error -> Fail __error
| Done v_value ->
(match (f_unify ((f_type_of (v_value))) (v_element) ((f_state_of (v_value))) ((f_context_subject (v_context)))) with
| Fail __error -> Fail __error
| Done v_next ->
(f_expr_work (v_rest) ((ArrayValues (v_tail, v_element, (f_sequence (v_accumulated) ((f_inference_of (v_value))) ((f_flow ((f_inferred_type (v_accumulated))) ((f_type_of (v_value))))))))) (v_context) (v_next)))))
| (__nat_74, (ArrayValues ([], v_element, v_accumulated))) when __nat_74 >= 1 ->
(let v_rest = (__nat_74 - 1) in
(Done ((Typing ((f_join (v_accumulated) ((f_pure (M.UnitTy))) ((f_flow ((f_inferred_type (v_accumulated))) ((M.ArrayTy (v_element)))))), v_state)))))
| (__nat_75, (MatchValues ([], v_types, v_arms, v_accumulated))) when __nat_75 >= 1 ->
(let v_rest = (__nat_75 - 1) in
(let v_scrutinees = (Base.list_reverse (v_types)) in
(match (f_expr_work (v_rest) ((MatchArms (v_arms, v_scrutinees))) (v_context) (v_state)) with
| Fail __error -> Fail __error
| Done v_a ->
(Done ((Typing ((f_add_coverage ((f_sequence (v_accumulated) ((f_inference_of (v_a))) ((f_flow ((f_inferred_type (v_accumulated))) ((f_type_of (v_a))))))) (v_scrutinees) ((f_arm_patterns (v_arms))) ((f_context_subject (v_context)))), (f_state_of (v_a)))))))))
| (__nat_76, (MatchArms ([], v_scrutinees))) when __nat_76 >= 1 ->
(let v_rest = (__nat_76 - 1) in
(Done ((Typing ((f_pure (M.NeverTy)), v_state)))))
| (__nat_77, (MatchArms (((M.MatchArm (v_patterns, v_body)) :: v_tail), v_scrutinees))) when __nat_77 >= 1 ->
(let v_rest = (__nat_77 - 1) in
(match (f_infer_patterns (v_patterns) (v_scrutinees) (v_context) (v_state) ([]) ([])) with
| Fail __error -> Fail __error
| Done v_bindings ->
(match (f_expr_work (v_rest) ((Expression (v_body))) ((f_extend (v_context) ((f_pattern_bindings (v_bindings))))) ((f_pattern_state (v_bindings)))) with
| Fail __error -> Fail __error
| Done v_b ->
(match (f_expr_work (v_rest) ((MatchArms (v_tail, v_scrutinees))) (v_context) ((f_state_of (v_b)))) with
| Fail __error -> Fail __error
| Done v_t ->
(match (f_unify ((f_type_of (v_b))) ((f_type_of (v_t))) ((f_state_of (v_t))) ((f_context_subject (v_context)))) with
| Fail __error -> Fail __error
| Done v_next ->
(Done ((Typing ((f_with_pattern_constraints ((f_join ((f_inference_of (v_b))) ((f_inference_of (v_t))) ((f_branch_type ((f_type_of (v_b))) ((f_type_of (v_t))))))) ((f_pattern_constraints (v_bindings)))), v_next))))))))))
and (* infer.bend:1559 *)
f_expr : M.t_Expr -> t_Context -> t_State -> (M.t_Diagnostic, t_Typing) Base.result_ =
fun v_expression v_context v_state ->
(f_expr_work ((Base.nat_mul (256) (256))) ((Expression (v_expression))) (v_context) (v_state))
