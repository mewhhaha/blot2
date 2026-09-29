(* Native semantic port of compiler/effect_families.bend.

   Source SHA-256: d12a7839cef3224a9d577a1d169736134f9dd3e56eb5866d47d8b0d30d763bdc

   Ownership/type arguments are erased; value types are checked by OCaml.

   No Bend interpreter or generated C/JavaScript is linked. *)

open Base

module M = Ox_model

module T = Ox_types

module State = Ox_state_specialize

module Closures = Ox_closures

module Mono = Ox_monomorph

module TypeData = Ox_type_data

type t_Work =
  | Expression of M.t_Expr
  | Expressions of (M.t_Expr) list * (M.t_Expr) list
and t_Rewritten =
  | Rewritten of (M.t_Expr) list * (M.t_Operation) list
and t_RewrittenFunctions =
  | RewrittenFunctions of (M.t_Function) list * (M.t_Operation) list
and t_RewrittenConstants =
  | RewrittenConstants of (M.t_Constant) list * (M.t_Operation) list

let s_0 = Base.text_of_utf8 "effect_instance"

let s_1 = Base.text_of_utf8 "<"

let s_2 = Base.text_of_utf8 ">"

let s_3 = Base.text_of_utf8 "effect type arguments must be concrete and have a supported closed type"

let s_4 = Base.text_of_utf8 "no declaration defines this effect operation"

let s_5 = Base.text_of_utf8 "effect operation has the wrong number of type arguments"

let s_6 = Base.text_of_utf8 "expected a parameterized effect declaration"

let s_7 = Base.text_of_utf8 "generated operation conflicts with an existing effect declaration"

let s_8 = Base.text_of_utf8 "internal_error"

let s_9 = Base.text_of_utf8 "effect"

let s_10 = Base.text_of_utf8 "expected a concrete effect operation"

let s_11 = Base.text_of_utf8 "effect specialization lost an expression"

let s_12 = Base.text_of_utf8 "duplicate_type"

let s_13 = Base.text_of_utf8 "duplicate nominal effect identity"

let s_14 = Base.text_of_utf8 "specialization_limit"

let s_15 = Base.text_of_utf8 "effect specialization exceeded its structural limit"

let s_16 = Base.text_of_utf8 "effect function list exceeds its structural limit"

let s_17 = Base.text_of_utf8 "effect constant list exceeds its structural limit"

let s_18 = Base.text_of_utf8 "effect instance list exceeds its structural limit"

let rec (* effect_families.bend:22 *)
f_instance_error : M.t_TypeId -> Base.text -> M.t_Diagnostic =
fun v_identity v_message ->
(M.Diagnostic (s_0, (M.f_type_id_show (v_identity)), v_message))
and (* effect_families.bend:26 *)
f_keyed_identity : (M.t_Diagnostic, Base.text) Base.result_ -> M.t_TypeId -> (M.t_Diagnostic, M.t_TypeId) Base.result_ =
fun v_found v_template ->
(match (v_found, v_template) with
| ((Done (v_key)), (M.TypeId (v_module_name, v_declaration))) ->
(Done ((M.TypeId (v_module_name, (Base.string_append v_declaration (Base.string_append s_1 (Base.string_append v_key s_2)))))))
| ((Fail (v_error)), v_template) ->
(Fail ((f_instance_error (v_template) (s_3)))))
and (* effect_families.bend:33 *)
f_identity : M.t_TypeId -> (M.t_Ty) list -> (M.t_Diagnostic, M.t_TypeId) Base.result_ =
fun v_template v_arguments ->
(f_keyed_identity ((State.f_type_key (65536) ((State.TypesKey (v_arguments))))) (v_template))
and (* effect_families.bend:36 *)
f_template : (M.t_Operation) list -> M.t_TypeId -> (M.t_Diagnostic, M.t_Operation) Base.result_ =
fun v_operations v_wanted ->
(match v_operations with
| [] ->
(Fail ((f_instance_error (v_wanted) (s_4))))
| ((M.OperationTemplate (v_identity, v_parameters, v_parameter, v_result)) :: v_tail) ->
(Base.bool_pick ((M.f_type_id_equal (v_identity) (v_wanted))) ((Done ((M.OperationTemplate (v_identity, v_parameters, v_parameter, v_result))))) ((f_template (v_tail) (v_wanted))))
| (v_head :: v_tail) ->
(f_template (v_tail) (v_wanted)))
and (* effect_families.bend:45 *)
f_concrete : (M.t_Operation) list -> (M.t_Operation) list =
fun v_operations ->
(match v_operations with
| [] ->
[]
| ((M.Operation (v_identity, v_parameter, v_result)) :: v_tail) ->
((M.Operation (v_identity, v_parameter, v_result)) :: (f_concrete (v_tail)))
| (v_head :: v_tail) ->
(f_concrete (v_tail)))
and (* effect_families.bend:54 *)
f_templates : (M.t_Operation) list -> (M.t_Operation) list =
fun v_operations ->
(match v_operations with
| [] ->
[]
| (v_operation :: v_tail) ->
(match v_operation with
| (M.OperationTemplate (v_identity, v_parameters, v_parameter, v_result)) ->
(v_operation :: (f_templates (v_tail)))
| _ ->
(f_templates (v_tail))))
and (* effect_families.bend:65 *)
f_contains : (M.t_Operation) list -> M.t_TypeId -> bool =
fun v_operations v_wanted ->
(match v_operations with
| [] ->
false
| ((M.Operation (v_identity, v_parameter, v_result)) :: v_tail) ->
(Base.bool_or ((M.f_type_id_equal (v_identity) (v_wanted))) ((f_contains (v_tail) (v_wanted))))
| (v_head :: v_tail) ->
(f_contains (v_tail) (v_wanted)))
and (* effect_families.bend:74 *)
f_instantiate_checked : bool -> M.t_TypeId -> M.t_Ty -> M.t_Ty -> (M.t_Ty) list -> (M.t_Diagnostic, M.t_Operation) Base.result_ =
fun v_correct_arity v_declared_identity v_parameter v_result v_arguments ->
(match v_correct_arity with
| false ->
(Fail ((f_instance_error (v_declared_identity) (s_5))))
| true ->
(match (f_identity (v_declared_identity) (v_arguments)) with
| Fail __error -> Fail __error
| Done v_specialized ->
(match (T.f_parameters (v_arguments) (0) (v_parameter)) with
| Fail __error -> Fail __error
| Done v_parameter_type ->
(match (T.f_parameters (v_arguments) (0) (v_result)) with
| Fail __error -> Fail __error
| Done v_result_type ->
(Done ((M.Operation (v_specialized, v_parameter_type, v_result_type))))))))
and (* effect_families.bend:85 *)
f_instantiate_declaration : M.t_Operation -> M.t_TypeId -> (M.t_Ty) list -> (M.t_Diagnostic, M.t_Operation) Base.result_ =
fun v_declaration v_template_identity v_arguments ->
(match v_declaration with
| (M.OperationTemplate (v_declared_identity, v_parameters, v_parameter, v_result)) ->
(f_instantiate_checked ((Base.nat_is_eq (v_parameters) ((Base.list_length (v_arguments))))) (v_declared_identity) (v_parameter) (v_result) (v_arguments))
| _ ->
(Fail ((f_instance_error (v_template_identity) (s_6)))))
and (* effect_families.bend:92 *)
f_instantiate : (M.t_Operation) list -> M.t_TypeId -> (M.t_Ty) list -> (M.t_Diagnostic, M.t_Operation) Base.result_ =
fun v_declarations v_template_identity v_arguments ->
(match (f_template (v_declarations) (v_template_identity)) with
| Fail __error -> Fail __error
| Done v_declaration ->
(f_instantiate_declaration (v_declaration) (v_template_identity) (v_arguments)))
and (* effect_families.bend:97 *)
f_add_instance : M.t_Operation -> (M.t_Operation) list -> (M.t_Operation) list -> (M.t_Diagnostic, (M.t_Operation) list) Base.result_ =
fun v_operation v_declared v_instances ->
(match v_operation with
| (M.Operation (v_identity, v_parameter, v_result)) ->
(Base.bool_pick ((f_contains (v_declared) (v_identity))) ((Fail ((f_instance_error (v_identity) (s_7))))) ((Done ((Base.bool_pick ((f_contains (v_instances) (v_identity))) (v_instances) ((v_operation :: v_instances)))))))
| _ ->
(Fail ((M.Diagnostic (s_8, s_9, s_10)))))
and (* effect_families.bend:104 *)
f_one : (M.t_Expr) list -> (M.t_Diagnostic, M.t_Expr) Base.result_ =
fun v_expressions ->
(match v_expressions with
| (v_expression :: []) ->
(Done (v_expression))
| _ ->
(Fail ((M.Diagnostic (s_8, s_9, s_11)))))
and (* effect_families.bend:111 *)
f_rebuilt : M.t_Expr -> t_Rewritten -> (M.t_Diagnostic, t_Rewritten) Base.result_ =
fun v_original v_rewritten ->
(match v_rewritten with
| (Rewritten (v_children, v_instances)) ->
(match (Mono.f_rebuild (v_original) (v_children) (0)) with
| Fail __error -> Fail __error
| Done v_value ->
(Done ((Rewritten ([v_value], v_instances))))))
and (* effect_families.bend:118 *)
f_instances_of : t_Rewritten -> (M.t_Operation) list =
fun v_rewritten ->
(match v_rewritten with
| (Rewritten (v_expressions, v_instances)) ->
v_instances)
and (* effect_families.bend:123 *)
f_expression_of : t_Rewritten -> (M.t_Diagnostic, M.t_Expr) Base.result_ =
fun v_rewritten ->
(match v_rewritten with
| (Rewritten (v_expressions, v_instances)) ->
(f_one (v_expressions)))
and (* effect_families.bend:128 *)
f_function_instances : t_RewrittenFunctions -> (M.t_Operation) list =
fun v_rewritten ->
(match v_rewritten with
| (RewrittenFunctions (v_functions, v_instances)) ->
v_instances)
and (* effect_families.bend:133 *)
f_prepend_function : M.t_Function -> t_RewrittenFunctions -> t_RewrittenFunctions =
fun v_function v_rewritten ->
(match v_rewritten with
| (RewrittenFunctions (v_functions, v_instances)) ->
(RewrittenFunctions ((v_function :: v_functions), v_instances)))
and (* effect_families.bend:138 *)
f_prepend_constant : M.t_Constant -> t_RewrittenConstants -> t_RewrittenConstants =
fun v_constant v_rewritten ->
(match v_rewritten with
| (RewrittenConstants (v_constants, v_instances)) ->
(RewrittenConstants ((v_constant :: v_constants), v_instances)))
and (* effect_families.bend:143 *)
f_template_present : (M.t_Operation) list -> M.t_TypeId -> bool =
fun v_operations v_wanted ->
(match v_operations with
| [] ->
false
| ((M.OperationTemplate (v_identity, v_parameters, v_parameter, v_result)) :: v_tail) ->
(Base.bool_or ((M.f_type_id_equal (v_identity) (v_wanted))) ((f_template_present (v_tail) (v_wanted))))
| (v_head :: v_tail) ->
(f_template_present (v_tail) (v_wanted)))
and (* effect_families.bend:152 *)
f_unique_template : bool -> M.t_TypeId -> (M.t_Diagnostic, unit) Base.result_ =
fun v_duplicate v_identity ->
(match v_duplicate with
| false ->
(Done (()))
| true ->
(Fail ((M.Diagnostic (s_12, (M.f_type_id_show (v_identity)), s_13)))))
and (* effect_families.bend:159 *)
f_rewrite : int -> t_Work -> (M.t_Operation) list -> (M.t_Operation) list -> (M.t_Operation) list -> (M.t_Diagnostic, t_Rewritten) Base.result_ =
fun v_fuel v_work v_declarations v_declared v_instances ->
(match (v_fuel, v_work) with
| (0, _) ->
(Fail ((M.Diagnostic (s_14, s_9, s_15))))
| (__nat_1, (Expression ((M.SpecializeOperationExpr (v_template_identity, v_arguments, v_body))))) when __nat_1 >= 1 ->
(let v_rest = (__nat_1 - 1) in
(match (f_instantiate (v_declarations) (v_template_identity) (v_arguments)) with
| Fail __error -> Fail __error
| Done v_operation ->
(match (f_add_instance (v_operation) (v_declared) (v_instances)) with
| Fail __error -> Fail __error
| Done v_next ->
(f_rewrite (v_rest) ((Expression (v_body))) (v_declarations) (v_declared) (v_next)))))
| (__nat_2, (Expression (v_original))) when __nat_2 >= 1 ->
(let v_rest = (__nat_2 - 1) in
(match (f_rewrite (v_rest) ((Expressions ((Closures.f_children (v_original)), []))) (v_declarations) (v_declared) (v_instances)) with
| Fail __error -> Fail __error
| Done v_rewritten ->
(f_rebuilt (v_original) (v_rewritten))))
| (__nat_3, (Expressions ([], v_reversed))) when __nat_3 >= 1 ->
(let v_rest = (__nat_3 - 1) in
(Done ((Rewritten ((Base.list_reverse (v_reversed)), v_instances)))))
| (__nat_4, (Expressions ((v_head :: v_tail), v_reversed))) when __nat_4 >= 1 ->
(let v_rest = (__nat_4 - 1) in
(match (f_rewrite (v_rest) ((Expression (v_head))) (v_declarations) (v_declared) (v_instances)) with
| Fail __error -> Fail __error
| Done v_first ->
(match (f_expression_of (v_first)) with
| Fail __error -> Fail __error
| Done v_value ->
(f_rewrite (v_rest) ((Expressions (v_tail, (v_value :: v_reversed)))) (v_declarations) (v_declared) ((f_instances_of (v_first))))))))
and (* effect_families.bend:180 *)
f_rewrite_functions : int -> (M.t_Function) list -> (M.t_Operation) list -> (M.t_Operation) list -> (M.t_Operation) list -> (M.t_Diagnostic, t_RewrittenFunctions) Base.result_ =
fun v_fuel v_functions v_declarations v_declared v_instances ->
(match (v_fuel, v_functions) with
| (0, _) ->
(Fail ((M.Diagnostic (s_14, s_9, s_16))))
| (__nat_5, []) when __nat_5 >= 1 ->
(let v_rest = (__nat_5 - 1) in
(Done ((RewrittenFunctions ([], v_instances)))))
| (__nat_6, ((M.Function (v_name, v_exported, v_parameter, v_parameter_type, v_result_type, v_body)) :: v_tail)) when __nat_6 >= 1 ->
(let v_rest = (__nat_6 - 1) in
(match (f_rewrite (65536) ((Expression (v_body))) (v_declarations) (v_declared) (v_instances)) with
| Fail __error -> Fail __error
| Done v_rewritten ->
(match (f_expression_of (v_rewritten)) with
| Fail __error -> Fail __error
| Done v_value ->
(match (f_rewrite_functions (v_rest) (v_tail) (v_declarations) (v_declared) ((f_instances_of (v_rewritten)))) with
| Fail __error -> Fail __error
| Done v_remaining ->
(Done ((f_prepend_function ((M.Function (v_name, v_exported, v_parameter, v_parameter_type, v_result_type, v_value))) (v_remaining)))))))))
and (* effect_families.bend:193 *)
f_rewrite_constants : int -> (M.t_Constant) list -> (M.t_Operation) list -> (M.t_Operation) list -> (M.t_Operation) list -> (M.t_Diagnostic, t_RewrittenConstants) Base.result_ =
fun v_fuel v_constants v_declarations v_declared v_instances ->
(match (v_fuel, v_constants) with
| (0, _) ->
(Fail ((M.Diagnostic (s_14, s_9, s_17))))
| (__nat_7, []) when __nat_7 >= 1 ->
(let v_rest = (__nat_7 - 1) in
(Done ((RewrittenConstants ([], v_instances)))))
| (__nat_8, ((M.Constant (v_name, v_exported, v_annotation, v_value)) :: v_tail)) when __nat_8 >= 1 ->
(let v_rest = (__nat_8 - 1) in
(match (f_rewrite (65536) ((Expression (v_value))) (v_declarations) (v_declared) (v_instances)) with
| Fail __error -> Fail __error
| Done v_rewritten ->
(match (f_expression_of (v_rewritten)) with
| Fail __error -> Fail __error
| Done v_specialized ->
(match (f_rewrite_constants (v_rest) (v_tail) (v_declarations) (v_declared) ((f_instances_of (v_rewritten)))) with
| Fail __error -> Fail __error
| Done v_remaining ->
(Done ((f_prepend_constant ((M.Constant (v_name, v_exported, v_annotation, v_specialized))) (v_remaining)))))))))
and (* effect_families.bend:206 *)
f_validate_templates : (M.t_Operation) list -> (M.t_Operation) list -> (M.t_DataType) list -> (M.t_Diagnostic, unit) Base.result_ =
fun v_operations v_declared v_types ->
(match v_operations with
| [] ->
(Done (()))
| ((M.OperationTemplate (v_identity, v_parameters, v_parameter, v_result)) :: v_tail) ->
(let v_subject = (M.f_type_id_show (v_identity)) in
(match (f_unique_template ((Base.bool_or ((f_template_present (v_tail) (v_identity))) ((f_contains (v_declared) (v_identity))))) (v_identity)) with
| Fail __error -> Fail __error
| Done v_unique ->
(match (TypeData.f_valid_operation_identity (v_identity)) with
| Fail __error -> Fail __error
| Done v_valid_identity ->
(match (TypeData.f_validate_template (v_parameter) ((Some (v_parameters))) (v_declared) (v_types) (v_subject)) with
| Fail __error -> Fail __error
| Done v_valid_parameter ->
(match (TypeData.f_validate_template (v_result) ((Some (v_parameters))) (v_declared) (v_types) (v_subject)) with
| Fail __error -> Fail __error
| Done v_valid_result ->
(f_validate_templates (v_tail) (v_declared) (v_types)))))))
| (v_head :: v_tail) ->
(f_validate_templates (v_tail) (v_declared) (v_types)))
and (* effect_families.bend:221 *)
f_collect_instances : int -> (M.t_Operation) list -> (M.t_Operation) list -> (M.t_Operation) list -> (M.t_Operation) list -> (M.t_Diagnostic, (M.t_Operation) list) Base.result_ =
fun v_fuel v_operations v_declarations v_declared v_instances ->
(match (v_fuel, v_operations) with
| (0, _) ->
(Fail ((M.Diagnostic (s_14, s_9, s_18))))
| (__nat_9, []) when __nat_9 >= 1 ->
(let v_rest = (__nat_9 - 1) in
(Done (v_instances)))
| (__nat_10, ((M.OperationInstance (v_template_identity, v_arguments)) :: v_tail)) when __nat_10 >= 1 ->
(let v_rest = (__nat_10 - 1) in
(match (f_instantiate (v_declarations) (v_template_identity) (v_arguments)) with
| Fail __error -> Fail __error
| Done v_operation ->
(match (f_add_instance (v_operation) (v_declared) (v_instances)) with
| Fail __error -> Fail __error
| Done v_next ->
(f_collect_instances (v_rest) (v_tail) (v_declarations) (v_declared) (v_next)))))
| (__nat_11, (v_head :: v_tail)) when __nat_11 >= 1 ->
(let v_rest = (__nat_11 - 1) in
(f_collect_instances (v_rest) (v_tail) (v_declarations) (v_declared) (v_instances))))
and (* effect_families.bend:235 *)
f_has_family : (M.t_Operation) list -> bool =
fun v_operations ->
(match v_operations with
| [] ->
false
| ((M.OperationTemplate (v_identity, v_parameters, v_parameter, v_result)) :: v_tail) ->
true
| ((M.OperationInstance (v_template, v_arguments)) :: v_tail) ->
true
| (v_head :: v_tail) ->
(f_has_family (v_tail)))
and (* effect_families.bend:246 *)
f_has_marker : int -> (M.t_Expr) list -> bool =
fun v_fuel v_pending ->
(match (v_fuel, v_pending) with
| (_, []) ->
false
| (0, _) ->
true
| (__nat_12, ((M.SpecializeOperationExpr (v_template, v_arguments, v_body)) :: v_tail)) when __nat_12 >= 1 ->
(let v_rest = (__nat_12 - 1) in
true)
| (__nat_13, (v_head :: v_tail)) when __nat_13 >= 1 ->
(let v_rest = (__nat_13 - 1) in
(f_has_marker (v_rest) ((Base.list_reverse_go ((Base.list_reverse ((Closures.f_children (v_head))))) (v_tail))))))
and (* effect_families.bend:257 *)
f_function_markers : (M.t_Function) list -> bool =
fun v_functions ->
(match v_functions with
| [] ->
false
| ((M.Function (v_name, v_exported, v_parameter, v_parameter_type, v_result_type, v_body)) :: v_tail) ->
(Base.bool_or ((f_has_marker (65536) ([v_body]))) ((f_function_markers (v_tail)))))
and (* effect_families.bend:264 *)
f_constant_markers : (M.t_Constant) list -> bool =
fun v_constants ->
(match v_constants with
| [] ->
false
| ((M.Constant (v_name, v_exported, v_annotation, v_value)) :: v_tail) ->
(Base.bool_or ((f_has_marker (65536) ([v_value]))) ((f_constant_markers (v_tail)))))
and (* effect_families.bend:271 *)
f_body_markers : bool -> (M.t_Function) list -> (M.t_Constant) list -> bool =
fun v_family v_functions v_constants ->
(match v_family with
| true ->
true
| false ->
(Base.bool_or ((f_function_markers (v_functions))) ((f_constant_markers (v_constants)))))
and (* effect_families.bend:278 *)
f_required : M.t_Module -> bool =
fun v_module ->
(let (M.Module (v_constants, v_functions, v_types, v_operations)) = v_module in
(f_body_markers ((f_has_family (v_operations))) (v_functions) (v_constants)))
and (* effect_families.bend:282 *)
f_finish : M.t_Module -> t_RewrittenFunctions -> t_RewrittenConstants -> (M.t_Operation) list -> M.t_Module =
fun v_module v_functions v_constants v_declared ->
(match (v_module, v_functions, v_constants) with
| ((M.Module (v_old_constants, v_old_functions, v_types, v_operations)), (RewrittenFunctions (v_specialized_functions, v_earlier)), (RewrittenConstants (v_specialized_constants, v_instances))) ->
(M.Module (v_specialized_constants, v_specialized_functions, v_types, (Base.list_append ((f_templates (v_operations))) ((Base.list_append (v_declared) ((Base.list_reverse (v_instances)))))))))
and (* effect_families.bend:287 *)
f_prepare_full : M.t_Module -> (M.t_Diagnostic, M.t_Module) Base.result_ =
fun v_module ->
(let (M.Module (v_constants, v_functions, v_data_types, v_declarations)) = v_module in
(let v_declared = (f_concrete (v_declarations)) in
(match (f_collect_instances (65536) (v_declarations) (v_declarations) (v_declared) ([])) with
| Fail __error -> Fail __error
| Done v_registered ->
(match (f_validate_templates (v_declarations) ((Base.list_append (v_declared) (v_registered))) (v_data_types)) with
| Fail __error -> Fail __error
| Done v_valid ->
(match (f_rewrite_functions (65536) (v_functions) (v_declarations) (v_declared) (v_registered)) with
| Fail __error -> Fail __error
| Done v_rewritten_functions ->
(match (f_rewrite_constants (65536) (v_constants) (v_declarations) (v_declared) ((f_function_instances (v_rewritten_functions)))) with
| Fail __error -> Fail __error
| Done v_rewritten_constants ->
(Done ((f_finish ((M.Module (v_constants, v_functions, v_data_types, v_declarations))) (v_rewritten_functions) (v_rewritten_constants) (v_declared))))))))))
and (* effect_families.bend:297 *)
f_prepare_if : bool -> M.t_Module -> (M.t_Diagnostic, M.t_Module) Base.result_ =
fun v_needed v_module ->
(match v_needed with
| false ->
(Done (v_module))
| true ->
(f_prepare_full (v_module)))
and (* effect_families.bend:304 *)
f_prepare : M.t_Module -> (M.t_Diagnostic, M.t_Module) Base.result_ =
fun v_module ->
(f_prepare_if ((f_required (v_module))) (v_module))
