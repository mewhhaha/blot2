(* Native semantic port of compiler/globals.bend.

   Source SHA-256: 1ad00550741b05d01d7eb48dbccf0a6b85481b6ea39e99458794e726219e611f

   Ownership/type arguments are erased; value types are checked by OCaml.

   No Bend interpreter or generated C/JavaScript is linked. *)

open Base

module M = Ox_model

module I = Ox_infer

module T = Ox_types

module D = Ox_dependency

module Bindings = Ox_global_bindings

module Closures = Ox_closures

module C = Ox_constraints

type t_Declaration =
  | FunctionDeclaration of M.t_Function
  | ConstantDeclaration of M.t_Constant
and t_Environment =
  | Environment of (I.t_Binding) list * (I.t_Definition) list * I.t_State
and t_SccSite =
  | SccSite of (int) option * Base.text * (int) option
and t_SccNode =
  | SccNode of Base.text * (t_SccSite) list
and t_SccWork =
  | SccExpressions of (M.t_Expr) list * (int) option
and t_SccClosure =
  | SccClosure of Base.text * (M.t_Predicate) list

let s_0 = Base.text_of_utf8 "internal_error"

let s_1 = Base.text_of_utf8 "missing top-level declaration"

let s_2 = Base.text_of_utf8 "missing top-level type binding"

let s_3 = Base.text_of_utf8 "named function binding is not an arrow"

let s_4 = Base.text_of_utf8 "initializer_effect"

let s_5 = Base.text_of_utf8 "const_effect"

let s_6 = Base.text_of_utf8 "module"

let s_7 = Base.text_of_utf8 "expression_complexity"

let s_8 = Base.text_of_utf8 "inference"

let s_9 = Base.text_of_utf8 "recursive callable scan exceeded its work limit"

let s_10 = Base.text_of_utf8 "recursive predicate closure exceeded its work limit"

let s_11 = Base.text_of_utf8 "missing inferred SCC member"

let rec (* globals.bend:17 *)
f_function_declarations : (M.t_Function) list -> (t_Declaration) list =
fun v_functions ->
(match v_functions with
| [] ->
[]
| (v_head :: v_tail) ->
((FunctionDeclaration (v_head)) :: (f_function_declarations (v_tail))))
and (* globals.bend:24 *)
f_constant_declarations : (M.t_Constant) list -> (t_Declaration) list =
fun v_constants ->
(match v_constants with
| [] ->
[]
| (v_head :: v_tail) ->
((ConstantDeclaration (v_head)) :: (f_constant_declarations (v_tail))))
and (* globals.bend:31 *)
f_declaration_name : t_Declaration -> Base.text =
fun v_declaration ->
(match v_declaration with
| (FunctionDeclaration ((M.Function (v_name, v_exported, v_parameter, v_p, v_r, v_body)))) ->
v_name
| (ConstantDeclaration ((M.Constant (v_name, v_exported, v_annotation, v_value)))) ->
v_name)
and (* globals.bend:38 *)
f_names : (t_Declaration) list -> (Base.text) list =
fun v_declarations ->
(match v_declarations with
| [] ->
[]
| (v_head :: v_tail) ->
((f_declaration_name (v_head)) :: (f_names (v_tail))))
and (* globals.bend:45 *)
f_function_names : (t_Declaration) list -> (Base.text) list =
fun v_declarations ->
(match v_declarations with
| [] ->
[]
| ((FunctionDeclaration ((M.Function (v_name, v_exported, v_parameter, v_p, v_r, v_body)))) :: v_tail) ->
(v_name :: (f_function_names (v_tail)))
| ((ConstantDeclaration (v_value)) :: v_tail) ->
(f_function_names (v_tail)))
and (* globals.bend:54 *)
f_lookup_work : (t_Declaration) list -> Base.text -> (t_Declaration) option -> (M.t_Diagnostic, t_Declaration) Base.result_ =
fun v_declarations v_name v_found ->
(match (v_declarations, v_found) with
| (_, (Some (v_value))) ->
(Done (v_value))
| ([], None) ->
(Fail ((M.Diagnostic (s_0, v_name, s_1))))
| ((v_head :: v_tail), None) ->
(f_lookup_work (v_tail) (v_name) ((Base.bool_pick ((M.f_name_equal ((f_declaration_name (v_head))) (v_name))) ((Some (v_head))) (None)))))
and (* globals.bend:63 *)
f_lookup : (t_Declaration) list -> Base.text -> (M.t_Diagnostic, t_Declaration) Base.result_ =
fun v_declarations v_name ->
(f_lookup_work (v_declarations) (v_name) (None))
and (* globals.bend:66 *)
f_initial_bindings : (t_Declaration) list -> int -> (I.t_Binding) list =
fun v_declarations v_index ->
(match v_declarations with
| [] ->
[]
| ((FunctionDeclaration ((M.Function (v_name, v_exported, v_parameter, v_p, v_r, v_body)))) :: v_tail) ->
((I.Binding (v_name, (M.FunctionTy ((M.VariableTy (v_index)), (M.VariableTy ((Base.nat_add 1 v_index))), (M.EffectRow ([], (M.RowVariable ((Base.nat_add 2 v_index))))))), [], [])) :: (f_initial_bindings (v_tail) ((Base.nat_add 3 v_index))))
| ((ConstantDeclaration ((M.Constant (v_name, v_exported, v_annotation, v_value)))) :: v_tail) ->
((I.Binding (v_name, (M.VariableTy (v_index)), [], [])) :: (f_initial_bindings (v_tail) ((Base.nat_add 1 v_index)))))
and (* globals.bend:75 *)
f_initial_next : (t_Declaration) list -> int -> int =
fun v_declarations v_index ->
(match v_declarations with
| [] ->
v_index
| ((FunctionDeclaration (v_value)) :: v_tail) ->
(f_initial_next (v_tail) ((Base.nat_add 3 v_index)))
| ((ConstantDeclaration (v_value)) :: v_tail) ->
(f_initial_next (v_tail) ((Base.nat_add 1 v_index))))
and (* globals.bend:84 *)
f_env_bindings : t_Environment -> (I.t_Binding) list =
fun v_environment ->
(let (Environment (v_bindings, v_definitions, v_state)) = v_environment in
v_bindings)
and (* globals.bend:88 *)
f_env_definitions : t_Environment -> (I.t_Definition) list =
fun v_environment ->
(let (Environment (v_bindings, v_definitions, v_state)) = v_environment in
v_definitions)
and (* globals.bend:92 *)
f_env_state : t_Environment -> I.t_State =
fun v_environment ->
(let (Environment (v_bindings, v_definitions, v_state)) = v_environment in
v_state)
and (* globals.bend:96 *)
f_binding_type : (I.t_Binding) option -> Base.text -> (M.t_Diagnostic, M.t_Ty) Base.result_ =
fun v_found v_subject ->
(match v_found with
| None ->
(Fail ((M.Diagnostic (s_0, v_subject, s_2))))
| (Some ((I.Binding (v_name, v_ty, v_variables, v_predicates)))) ->
(Done (v_ty)))
and (* globals.bend:103 *)
f_function_parameter : M.t_Ty -> Base.text -> (M.t_Diagnostic, M.t_Ty) Base.result_ =
fun v_ty v_subject ->
(match v_ty with
| (M.FunctionTy (v_parameter, v_result, v_effects)) ->
(Done (v_parameter))
| v_other ->
(Fail ((M.Diagnostic (s_0, v_subject, s_3)))))
and (* globals.bend:110 *)
f_function_result : M.t_Ty -> Base.text -> (M.t_Diagnostic, M.t_Ty) Base.result_ =
fun v_ty v_subject ->
(match v_ty with
| (M.FunctionTy (v_parameter, v_result, v_effects)) ->
(Done (v_result))
| v_other ->
(Fail ((M.Diagnostic (s_0, v_subject, s_3)))))
and (* globals.bend:117 *)
f_function_effects : M.t_Ty -> Base.text -> (M.t_Diagnostic, M.t_EffectRow) Base.result_ =
fun v_ty v_subject ->
(match v_ty with
| (M.FunctionTy (v_parameter, v_result, v_effects)) ->
(Done (v_effects))
| v_other ->
(Fail ((M.Diagnostic (s_0, v_subject, s_3)))))
and (* globals.bend:124 *)
f_definition_inference : I.t_Inference -> M.t_Ty -> I.t_Inference =
fun v_value v_ty ->
(let (I.Inference (v_old, v_coverage, v_exits, v_reflections, v_predicates, v_uses)) = v_value in
(I.Inference (v_ty, v_coverage, v_exits, v_reflections, v_predicates, v_uses)))
and (* globals.bend:128 *)
f_reference_set : (Base.text) list -> Base.set -> Base.set =
fun v_names v_found ->
(match v_names with
| [] ->
v_found
| (v_head :: v_tail) ->
(f_reference_set (v_tail) ((Base.set_add (v_found) (v_head)))))
and (* globals.bend:135 *)
f_referenced_bindings_indexed : (I.t_Binding) list -> Base.set -> (I.t_Binding) list =
fun v_bindings v_names ->
(match v_bindings with
| [] ->
[]
| (v_binding :: v_tail) ->
(let (I.Binding (v_name, v_ty, v_variables, v_predicates)) = v_binding in
(let v_rest = (f_referenced_bindings_indexed (v_tail) (v_names)) in
(Base.bool_pick ((D.f_member (v_names) (v_name))) ((v_binding :: v_rest)) (v_rest)))))
and (* globals.bend:144 *)
f_referenced_bindings : (I.t_Binding) list -> (Base.text) list -> (I.t_Binding) list =
fun v_bindings v_names ->
(f_referenced_bindings_indexed (v_bindings) ((f_reference_set (v_names) ((Base.set_new ())))))
and (* globals.bend:150 *)
f_declaration_bindings : Base.text -> M.t_Expr -> (I.t_Binding) list -> (M.t_Diagnostic, (I.t_Binding) list) Base.result_ =
fun v_name v_body v_bindings ->
(match (D.f_references ((Base.nat_mul (256) (256))) ((D.Expression (v_body)))) with
| Fail __error -> Fail __error
| Done v_references ->
(Done ((f_referenced_bindings (v_bindings) ((v_name :: (D.f_names_of (v_references))))))))
and (* globals.bend:155 *)
f_reference_bindings_prepared : (((Bindings.t_Entry) list) Base.map) option -> (I.t_Binding) list -> (Base.text) list -> (I.t_Binding) list =
fun v_index v_bindings v_names ->
(match v_index with
| None ->
(f_referenced_bindings (v_bindings) (v_names))
| (Some (v_known)) ->
(Bindings.f_referenced (v_known) (v_names)))
and (* globals.bend:162 *)
f_declaration_bindings_prepared : Base.text -> M.t_Expr -> (I.t_Binding) list -> (((Bindings.t_Entry) list) Base.map) option -> (M.t_Diagnostic, (I.t_Binding) list) Base.result_ =
fun v_name v_body v_bindings v_index ->
(match (D.f_references ((Base.nat_mul (256) (256))) ((D.Expression (v_body)))) with
| Fail __error -> Fail __error
| Done v_references ->
(Done ((f_reference_bindings_prepared (v_index) (v_bindings) ((v_name :: (D.f_names_of (v_references))))))))
and (* globals.bend:167 *)
f_initializer_effect_code : M.t_Expr -> Base.text =
fun v_value ->
(match v_value with
| (M.RuntimeInitExpr (v_expression)) ->
s_4
| _ ->
s_5)
and (* globals.bend:174 *)
f_infer_declaration_prepared : t_Declaration -> t_Environment -> (M.t_Operation) list -> (M.t_DataType) list -> (Base.text) list -> (((Bindings.t_Entry) list) Base.map) option -> (M.t_Diagnostic, t_Environment) Base.result_ =
fun v_declaration v_environment v_operations v_types v_functions v_index ->
(match v_declaration with
| (FunctionDeclaration ((M.Function (v_name, v_exported, v_parameter, v_p, v_r, v_body)))) ->
(let v_bindings = (f_env_bindings (v_environment)) in
(match (f_binding_type ((I.f_lookup_binding (v_bindings) (v_name))) (v_name)) with
| Fail __error -> Fail __error
| Done v_ty ->
(match (f_function_parameter (v_ty) (v_name)) with
| Fail __error -> Fail __error
| Done v_param ->
(match (f_function_result (v_ty) (v_name)) with
| Fail __error -> Fail __error
| Done v_result ->
(match (f_function_effects (v_ty) (v_name)) with
| Fail __error -> Fail __error
| Done v_ambient ->
(match (f_declaration_bindings_prepared (v_name) (v_body) (v_bindings) (v_index)) with
| Fail __error -> Fail __error
| Done v_visible ->
(let v_context = (I.Context (v_visible, [], [], v_types, v_operations, v_name, v_functions, v_ambient)) in
(match (I.f_annotation (v_p) (v_param) ((f_env_state (v_environment))) (v_context)) with
| Fail __error -> Fail __error
| Done v_s1 ->
(match (I.f_annotation (v_r) (v_result) (v_s1) (v_context)) with
| Fail __error -> Fail __error
| Done v_s2 ->
(match (I.f_expr (v_body) ((I.f_extend (v_context) ([(I.Binding (v_parameter, v_param, [], []))]))) (v_s2)) with
| Fail __error -> Fail __error
| Done v_value ->
(match (I.f_unify ((I.f_type_of (v_value))) (v_result) ((I.f_state_of (v_value))) (v_name)) with
| Fail __error -> Fail __error
| Done v_state ->
(Done ((Environment (v_bindings, ((I.Definition (v_name, (f_definition_inference ((I.f_inference_of (v_value))) (v_ty)))) :: (f_env_definitions (v_environment))), (I.f_clear_annotations (v_state)))))))))))))))))
| (ConstantDeclaration ((M.Constant (v_name, v_exported, v_ann, v_value)))) ->
(let v_bindings = (f_env_bindings (v_environment)) in
(let v_ambient = (M.EffectRow ([], (M.RowVariable ((I.f_next_of ((f_env_state (v_environment)))))))) in
(match (f_declaration_bindings_prepared (v_name) (v_value) (v_bindings) (v_index)) with
| Fail __error -> Fail __error
| Done v_visible ->
(let v_context = (I.Context (v_visible, [], [], v_types, v_operations, v_name, v_functions, v_ambient)) in
(match (f_binding_type ((I.f_lookup_binding (v_bindings) (v_name))) (v_name)) with
| Fail __error -> Fail __error
| Done v_ty ->
(match (I.f_annotation (v_ann) (v_ty) ((I.f_with_next ((f_env_state (v_environment))) ((Base.nat_add 1 (I.f_next_of ((f_env_state (v_environment)))))))) (v_context)) with
| Fail __error -> Fail __error
| Done v_s1 ->
(let v_effect_code = (f_initializer_effect_code (v_value)) in
(match (I.f_expr (v_value) (v_context) (v_s1)) with
| Fail __error -> Fail __error
| Done v_value ->
(match (I.f_unify ((I.f_type_of (v_value))) (v_ty) ((I.f_state_of (v_value))) (v_name)) with
| Fail __error -> Fail __error
| Done v_unified ->
(match (I.f_require_pure (v_ambient) (v_unified) (v_name) (v_effect_code)) with
| Fail __error -> Fail __error
| Done v_state ->
(Done ((Environment (v_bindings, ((I.Definition (v_name, (f_definition_inference ((I.f_inference_of (v_value))) (v_ty)))) :: (f_env_definitions (v_environment))), (I.f_clear_annotations (v_state)))))))))))))))))
and (* globals.bend:204 *)
f_infer_declaration : t_Declaration -> t_Environment -> (M.t_Operation) list -> (M.t_DataType) list -> (Base.text) list -> (M.t_Diagnostic, t_Environment) Base.result_ =
fun v_declaration v_environment v_operations v_types v_functions ->
(f_infer_declaration_prepared (v_declaration) (v_environment) (v_operations) (v_types) (v_functions) (None))
and (* globals.bend:207 *)
f_component_bindings : (Base.text) list -> (I.t_Binding) list -> (((Bindings.t_Entry) list) Base.map) option =
fun v_names v_bindings ->
(match v_names with
| (v_a :: (v_b :: (v_c :: (v_d :: v_rest)))) ->
(Some ((Bindings.f_build (v_bindings) (0) (MTip))))
| _ ->
None)
and (* globals.bend:214 *)
f_infer_component_prepared : (Base.text) list -> (t_Declaration) list -> t_Environment -> (M.t_Operation) list -> (M.t_DataType) list -> (Base.text) list -> (((Bindings.t_Entry) list) Base.map) option -> (M.t_Diagnostic, t_Environment) Base.result_ =
fun v_names v_declarations v_environment v_operations v_types v_functions v_index ->
(match v_names with
| [] ->
(Done (v_environment))
| (v_head :: v_tail) ->
(match (f_lookup (v_declarations) (v_head)) with
| Fail __error -> Fail __error
| Done v_declaration ->
(match (f_infer_declaration_prepared (v_declaration) (v_environment) (v_operations) (v_types) (v_functions) (v_index)) with
| Fail __error -> Fail __error
| Done v_next ->
(f_infer_component_prepared (v_tail) (v_declarations) (v_next) (v_operations) (v_types) (v_functions) (v_index)))))
and (* globals.bend:224 *)
f_infer_component : (Base.text) list -> (t_Declaration) list -> t_Environment -> (M.t_Operation) list -> (M.t_DataType) list -> (Base.text) list -> (M.t_Diagnostic, t_Environment) Base.result_ =
fun v_names v_declarations v_environment v_operations v_types v_functions ->
(f_infer_component_prepared (v_names) (v_declarations) (v_environment) (v_operations) (v_types) (v_functions) ((f_component_bindings (v_names) ((f_env_bindings (v_environment))))))
and (* globals.bend:227 *)
f_outside_indexed : (I.t_Binding) list -> Base.set -> Base.set -> (I.t_Binding) list =
fun v_bindings v_members v_references ->
(match v_bindings with
| [] ->
[]
| ((I.Binding (v_name, v_ty, v_variables, v_predicates)) :: v_tail) ->
(let v_rest = (f_outside_indexed (v_tail) (v_members) (v_references)) in
(Base.bool_pick ((Base.bool_and ((D.f_member (v_references) (v_name))) ((Base.bool_not ((D.f_member (v_members) (v_name))))))) (((I.Binding (v_name, v_ty, v_variables, v_predicates)) :: v_rest)) (v_rest))))
and (* globals.bend:235 *)
f_outside : (I.t_Binding) list -> (Base.text) list -> (Base.text) list -> (I.t_Binding) list =
fun v_bindings v_members v_references ->
(f_outside_indexed (v_bindings) ((f_reference_set (v_members) ((Base.set_new ())))) ((f_reference_set (v_references) ((Base.set_new ())))))
and (* globals.bend:238 *)
f_external_names : (Base.text) list -> (D.t_Node) list -> (Base.text) list =
fun v_members v_nodes ->
(match v_members with
| [] ->
[]
| (v_head :: v_tail) ->
(Base.list_append ((D.f_lookup (v_nodes) (v_head))) ((f_external_names (v_tail) (v_nodes)))))
and (* globals.bend:245 *)
f_definition_predicates : (I.t_Definition) list -> Base.text -> (M.t_Predicate) list =
fun v_definitions v_wanted ->
(match v_definitions with
| [] ->
[]
| ((I.Definition (v_name, v_inference)) :: v_tail) ->
(Base.bool_pick ((M.f_name_equal (v_name) (v_wanted))) ((I.f_inference_predicates (v_inference))) ((f_definition_predicates (v_tail) (v_wanted)))))
and (* globals.bend:252 *)
f_generalize_member : bool -> I.t_Binding -> (I.t_Definition) list -> I.t_Context -> I.t_State -> (M.t_Diagnostic, I.t_Binding) Base.result_ =
fun v_member v_binding v_definitions v_context v_state ->
(match v_member with
| false ->
(Done (v_binding))
| true ->
(let (I.Binding (v_name, v_ty, v_variables, v_predicates)) = v_binding in
(I.f_generalize_qualified (v_ty) ((f_definition_predicates (v_definitions) (v_name))) (v_context) (v_state) (v_name))))
and (* globals.bend:260 *)
f_generalize_bindings_indexed : (I.t_Binding) list -> Base.set -> (I.t_Definition) list -> I.t_Context -> I.t_State -> (M.t_Diagnostic, (I.t_Binding) list) Base.result_ =
fun v_bindings v_members v_definitions v_context v_state ->
(match v_bindings with
| [] ->
(Done ([]))
| ((I.Binding (v_name, v_ty, v_variables, v_predicates)) :: v_tail) ->
(match (f_generalize_member ((D.f_member (v_members) (v_name))) ((I.Binding (v_name, v_ty, v_variables, v_predicates))) (v_definitions) (v_context) (v_state)) with
| Fail __error -> Fail __error
| Done v_head ->
(match (f_generalize_bindings_indexed (v_tail) (v_members) (v_definitions) (v_context) (v_state)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done ((v_head :: v_rest))))))
and (* globals.bend:270 *)
f_generalize_bindings : (I.t_Binding) list -> (Base.text) list -> I.t_Context -> I.t_State -> (M.t_Diagnostic, (I.t_Binding) list) Base.result_ =
fun v_bindings v_members v_context v_state ->
(f_generalize_bindings_indexed (v_bindings) ((f_reference_set (v_members) ((Base.set_new ())))) ([]) (v_context) (v_state))
and (* globals.bend:273 *)
f_generalize_component : t_Environment -> (Base.text) list -> (M.t_Operation) list -> (M.t_DataType) list -> (D.t_Node) list -> (M.t_Diagnostic, t_Environment) Base.result_ =
fun v_environment v_members v_operations v_types v_nodes ->
(let (Environment (v_bindings, v_definitions, v_state)) = v_environment in
(let v_member_names = (f_reference_set (v_members) ((Base.set_new ()))) in
(let v_referenced_names = (f_reference_set ((f_external_names (v_members) (v_nodes))) ((Base.set_new ()))) in
(let v_context = (I.Context ((f_outside_indexed (v_bindings) (v_member_names) (v_referenced_names)), [], [], v_types, v_operations, s_6, [], (M.f_empty_row ()))) in
(match (f_generalize_bindings_indexed (v_bindings) (v_member_names) (v_definitions) (v_context) (v_state)) with
| Fail __error -> Fail __error
| Done v_next ->
(Done ((Environment (v_next, v_definitions, v_state)))))))))
and (* globals.bend:298 *)
f_scc_scan : int -> (t_SccWork) list -> (t_SccSite) list -> (M.t_Diagnostic, (t_SccSite) list) Base.result_ =
fun v_fuel v_pending v_reversed ->
(match (v_fuel, v_pending) with
| (_, []) ->
(Done ((Base.list_reverse (v_reversed))))
| (0, _) ->
(Fail ((M.Diagnostic (s_7, s_8, s_9))))
| (__nat_1, ((SccExpressions ([], v_boundary)) :: v_tail)) when __nat_1 >= 1 ->
(let v_rest = (__nat_1 - 1) in
(f_scc_scan (v_rest) (v_tail) (v_reversed)))
| (__nat_2, ((SccExpressions (((M.QualifiedExpr (v_offset, v_annotation, v_predicates, v_value)) :: v_values), v_boundary)) :: v_tail)) when __nat_2 >= 1 ->
(let v_rest = (__nat_2 - 1) in
(f_scc_scan (v_rest) (((SccExpressions ([v_value], (Some (v_offset)))) :: ((SccExpressions (v_values, v_boundary)) :: v_tail))) (v_reversed)))
| (__nat_3, ((SccExpressions (((M.InstantiationExpr (v_site, (M.FunctionExpr (v_name)))) :: v_values), v_boundary)) :: v_tail)) when __nat_3 >= 1 ->
(let v_rest = (__nat_3 - 1) in
(f_scc_scan (v_rest) (((SccExpressions (v_values, v_boundary)) :: v_tail)) (((SccSite ((Some (v_site)), v_name, v_boundary)) :: v_reversed))))
| (__nat_4, ((SccExpressions (((M.InstantiationExpr (v_site, (M.ConstantExpr (v_name)))) :: v_values), v_boundary)) :: v_tail)) when __nat_4 >= 1 ->
(let v_rest = (__nat_4 - 1) in
(f_scc_scan (v_rest) (((SccExpressions (v_values, v_boundary)) :: v_tail)) (((SccSite ((Some (v_site)), v_name, v_boundary)) :: v_reversed))))
| (__nat_5, ((SccExpressions (((M.InstantiationExpr (v_site, (M.CallExpr (v_name, v_argument)))) :: v_values), v_boundary)) :: v_tail)) when __nat_5 >= 1 ->
(let v_rest = (__nat_5 - 1) in
(f_scc_scan (v_rest) (((SccExpressions ([v_argument], v_boundary)) :: ((SccExpressions (v_values, v_boundary)) :: v_tail))) (((SccSite ((Some (v_site)), v_name, v_boundary)) :: v_reversed))))
| (__nat_6, ((SccExpressions (((M.FunctionExpr (v_name)) :: v_values), v_boundary)) :: v_tail)) when __nat_6 >= 1 ->
(let v_rest = (__nat_6 - 1) in
(f_scc_scan (v_rest) (((SccExpressions (v_values, v_boundary)) :: v_tail)) (((SccSite (None, v_name, v_boundary)) :: v_reversed))))
| (__nat_7, ((SccExpressions (((M.ConstantExpr (v_name)) :: v_values), v_boundary)) :: v_tail)) when __nat_7 >= 1 ->
(let v_rest = (__nat_7 - 1) in
(f_scc_scan (v_rest) (((SccExpressions (v_values, v_boundary)) :: v_tail)) (((SccSite (None, v_name, v_boundary)) :: v_reversed))))
| (__nat_8, ((SccExpressions (((M.CallExpr (v_name, v_argument)) :: v_values), v_boundary)) :: v_tail)) when __nat_8 >= 1 ->
(let v_rest = (__nat_8 - 1) in
(f_scc_scan (v_rest) (((SccExpressions ([v_argument], v_boundary)) :: ((SccExpressions (v_values, v_boundary)) :: v_tail))) (((SccSite (None, v_name, v_boundary)) :: v_reversed))))
| (__nat_9, ((SccExpressions ((v_expression :: v_values), v_boundary)) :: v_tail)) when __nat_9 >= 1 ->
(let v_rest = (__nat_9 - 1) in
(f_scc_scan (v_rest) (((SccExpressions ((Closures.f_children (v_expression)), v_boundary)) :: ((SccExpressions (v_values, v_boundary)) :: v_tail))) (v_reversed))))
and (* globals.bend:323 *)
f_scc_sites : M.t_Expr -> (M.t_Diagnostic, (t_SccSite) list) Base.result_ =
fun v_value ->
(f_scc_scan ((Base.nat_mul (256) (256))) ([(SccExpressions ([v_value], None))]) ([]))
and (* globals.bend:326 *)
f_scc_declaration_sites : t_Declaration -> (M.t_Diagnostic, (t_SccSite) list) Base.result_ =
fun v_declaration ->
(match v_declaration with
| (FunctionDeclaration ((M.Function (v_name, v_exported, v_parameter, v_p, v_r, v_body)))) ->
(f_scc_sites (v_body))
| (ConstantDeclaration ((M.Constant (v_name, v_exported, v_annotation, v_value)))) ->
(f_scc_sites (v_value)))
and (* globals.bend:333 *)
f_scc_nodes : (Base.text) list -> (t_Declaration) list -> (M.t_Diagnostic, (t_SccNode) list) Base.result_ =
fun v_members v_declarations ->
(match v_members with
| [] ->
(Done ([]))
| (v_name :: v_tail) ->
(match (f_lookup (v_declarations) (v_name)) with
| Fail __error -> Fail __error
| Done v_declaration ->
(match (f_scc_declaration_sites (v_declaration)) with
| Fail __error -> Fail __error
| Done v_sites ->
(match (f_scc_nodes (v_tail) (v_declarations)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done (((SccNode (v_name, v_sites)) :: v_rest)))))))
and (* globals.bend:344 *)
f_scc_node_sites : (t_SccNode) list -> Base.text -> (t_SccSite) list =
fun v_nodes v_wanted ->
(match v_nodes with
| [] ->
[]
| ((SccNode (v_name, v_sites)) :: v_tail) ->
(Base.bool_pick ((M.f_name_equal (v_name) (v_wanted))) (v_sites) ((f_scc_node_sites (v_tail) (v_wanted)))))
and (* globals.bend:351 *)
f_scc_peers : (t_SccSite) list -> Base.set -> (Base.text) list =
fun v_sites v_members ->
(match v_sites with
| [] ->
[]
| ((SccSite (v_site, v_callee, v_boundary)) :: v_tail) ->
(let v_rest = (f_scc_peers (v_tail) (v_members)) in
(Base.bool_pick ((D.f_member (v_members) (v_callee))) ((v_callee :: v_rest)) (v_rest))))
and (* globals.bend:359 *)
f_scc_seen : (Base.text) list -> Base.set -> bool =
fun v_pending v_visited ->
(match v_pending with
| [] ->
false
| (v_name :: v_tail) ->
(D.f_member (v_visited) (v_name)))
and (* globals.bend:366 *)
f_scc_closure_walk : int -> (Base.text) list -> Base.set -> (t_SccNode) list -> (I.t_Definition) list -> T.t_Substitutions -> Base.set -> (M.t_Predicate) list -> bool -> (M.t_Diagnostic, (M.t_Predicate) list) Base.result_ =
fun v_fuel v_pending v_members v_nodes v_definitions v_substitutions v_visited v_gathered v_seen ->
(match (v_fuel, v_pending, v_seen) with
| (_, [], _) ->
(Done ((C.f_canonical_predicates ((Base.list_reverse (v_gathered))) ([]))))
| (0, _, _) ->
(Fail ((M.Diagnostic (s_7, s_8, s_10))))
| (__nat_10, (v_name :: v_tail), true) when __nat_10 >= 1 ->
(let v_rest = (__nat_10 - 1) in
(f_scc_closure_walk (v_rest) (v_tail) (v_members) (v_nodes) (v_definitions) (v_substitutions) (v_visited) (v_gathered) ((f_scc_seen (v_tail) (v_visited)))))
| (__nat_11, (v_name :: v_tail), false) when __nat_11 >= 1 ->
(let v_rest = (__nat_11 - 1) in
(let v_peers = (f_scc_peers ((f_scc_node_sites (v_nodes) (v_name))) (v_members)) in
(let v_queued = (Base.list_reverse_go ((Base.list_reverse (v_peers))) (v_tail)) in
(let v_next_visited = (Base.set_add (v_visited) (v_name)) in
(match (C.f_resolve_list (v_substitutions) ((f_definition_predicates (v_definitions) (v_name)))) with
| Fail __error -> Fail __error
| Done v_own ->
(f_scc_closure_walk (v_rest) (v_queued) (v_members) (v_nodes) (v_definitions) (v_substitutions) (v_next_visited) ((Base.list_reverse_go (v_own) (v_gathered))) ((f_scc_seen (v_queued) (v_next_visited))))))))))
and (* globals.bend:385 *)
f_scc_closures : (Base.text) list -> Base.set -> (t_SccNode) list -> (I.t_Definition) list -> T.t_Substitutions -> (M.t_Diagnostic, (t_SccClosure) list) Base.result_ =
fun v_members v_member_set v_nodes v_definitions v_substitutions ->
(match v_members with
| [] ->
(Done ([]))
| (v_name :: v_tail) ->
(match (f_scc_closure_walk ((Base.nat_mul (256) (256))) ([v_name]) (v_member_set) (v_nodes) (v_definitions) (v_substitutions) ((Base.set_new ())) ([]) (false)) with
| Fail __error -> Fail __error
| Done v_own ->
(match (f_scc_closures (v_tail) (v_member_set) (v_nodes) (v_definitions) (v_substitutions)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done (((SccClosure (v_name, v_own)) :: v_rest))))))
and (* globals.bend:395 *)
f_scc_predicates : (t_SccClosure) list -> Base.text -> (M.t_Predicate) list =
fun v_closures v_name ->
(match v_closures with
| [] ->
[]
| ((SccClosure (v_found, v_predicates)) :: v_tail) ->
(Base.bool_pick ((M.f_name_equal (v_found) (v_name))) (v_predicates) ((f_scc_predicates (v_tail) (v_name)))))
and (* globals.bend:402 *)
f_scc_site_callee : (t_SccSite) list -> int -> (Base.text) option =
fun v_sites v_site ->
(match v_sites with
| [] ->
None
| ((SccSite (None, v_callee, v_boundary)) :: v_tail) ->
(f_scc_site_callee (v_tail) (v_site))
| ((SccSite ((Some (v_identity)), v_callee, v_boundary)) :: v_tail) ->
(Base.bool_pick ((Base.nat_is_eq (v_identity) (v_site))) ((Some (v_callee))) ((f_scc_site_callee (v_tail) (v_site)))))
and (* globals.bend:411 *)
f_scc_same_boundary : (int) option -> int -> bool =
fun v_found v_wanted ->
(match v_found with
| None ->
false
| (Some (v_offset)) ->
(Base.nat_is_eq (v_offset) (v_wanted)))
and (* globals.bend:418 *)
f_scc_boundary_predicates : (t_SccSite) list -> int -> Base.set -> (t_SccClosure) list -> (M.t_Predicate) list =
fun v_sites v_offset v_members v_closures ->
(match v_sites with
| [] ->
[]
| ((SccSite (v_site, v_callee, v_boundary)) :: v_tail) ->
(let v_rest = (f_scc_boundary_predicates (v_tail) (v_offset) (v_members) (v_closures)) in
(Base.bool_pick ((Base.bool_and ((f_scc_same_boundary (v_boundary) (v_offset))) ((D.f_member (v_members) (v_callee))))) ((Base.list_append ((f_scc_predicates (v_closures) (v_callee))) (v_rest))) (v_rest))))
and (* globals.bend:426 *)
f_scc_site_in_boundary : (t_SccSite) list -> int -> int -> bool =
fun v_sites v_site v_offset ->
(match v_sites with
| [] ->
false
| ((SccSite (None, v_callee, v_boundary)) :: v_tail) ->
(f_scc_site_in_boundary (v_tail) (v_site) (v_offset))
| ((SccSite ((Some (v_identity)), v_callee, v_boundary)) :: v_tail) ->
(Base.bool_or ((Base.bool_and ((Base.nat_is_eq (v_identity) (v_site))) ((f_scc_same_boundary (v_boundary) (v_offset))))) ((f_scc_site_in_boundary (v_tail) (v_site) (v_offset)))))
and (* globals.bend:435 *)
f_scc_boundary_plans : (C.t_UsePlan) list -> (t_SccSite) list -> int -> (C.t_UsePlan) list =
fun v_plans v_sites v_offset ->
(match v_plans with
| [] ->
[]
| ((C.UsePlan (v_site, v_subject, v_ty, v_predicates)) :: v_tail) ->
(let v_rest = (f_scc_boundary_plans (v_tail) (v_sites) (v_offset)) in
(Base.bool_pick ((f_scc_site_in_boundary (v_sites) (v_site) (v_offset))) (((C.UsePlan (v_site, v_subject, v_ty, v_predicates)) :: v_rest)) (v_rest))))
and (* globals.bend:443 *)
f_scc_plan_for : (Base.text) option -> C.t_UsePlan -> (t_SccClosure) list -> C.t_UsePlan =
fun v_found v_plan v_closures ->
(match (v_found, v_plan) with
| (None, v_plan) ->
v_plan
| ((Some (v_callee)), (C.UsePlan (v_site, v_subject, v_ty, v_predicates))) ->
(C.UsePlan (v_site, v_subject, v_ty, (C.f_canonical_predicates ((Base.list_append (v_predicates) ((f_scc_predicates (v_closures) (v_callee))))) ([])))))
and (* globals.bend:450 *)
f_scc_plans : (C.t_UsePlan) list -> (t_SccSite) list -> (t_SccClosure) list -> (C.t_UsePlan) list =
fun v_plans v_sites v_closures ->
(match v_plans with
| [] ->
[]
| ((C.UsePlan (v_site, v_subject, v_ty, v_predicates)) :: v_tail) ->
((f_scc_plan_for ((f_scc_site_callee (v_sites) (v_site))) ((C.UsePlan (v_site, v_subject, v_ty, v_predicates))) (v_closures)) :: (f_scc_plans (v_tail) (v_sites) (v_closures))))
and (* globals.bend:460 *)
f_scc_check_boundaries : (I.t_Coverage) list -> (t_SccSite) list -> (C.t_UsePlan) list -> Base.set -> (t_SccClosure) list -> I.t_State -> (M.t_Diagnostic, I.t_State) Base.result_ =
fun v_coverage v_sites v_plans v_members v_closures v_state ->
(match v_coverage with
| [] ->
(Done (v_state))
| ((I.QualifiedBoundary (v_offset, v_declared, v_subject)) :: v_tail) ->
(match (I.f_entail_all ((f_scc_boundary_predicates (v_sites) (v_offset) (v_members) (v_closures))) ([]) ((f_scc_boundary_plans (v_plans) (v_sites) (v_offset))) (v_declared) (v_state) (v_subject)) with
| Fail __error -> Fail __error
| Done v_next ->
(f_scc_check_boundaries (v_tail) (v_sites) (v_plans) (v_members) (v_closures) (v_next)))
| (v_head :: v_tail) ->
(f_scc_check_boundaries (v_tail) (v_sites) (v_plans) (v_members) (v_closures) (v_state)))
and (* globals.bend:471 *)
f_scc_definition : (I.t_Definition) list -> Base.text -> (M.t_Diagnostic, I.t_Inference) Base.result_ =
fun v_definitions v_wanted ->
(match v_definitions with
| [] ->
(Fail ((M.Diagnostic (s_0, v_wanted, s_11))))
| ((I.Definition (v_name, v_inference)) :: v_tail) ->
(Base.bool_pick ((M.f_name_equal (v_name) (v_wanted))) ((Done (v_inference))) ((f_scc_definition (v_tail) (v_wanted)))))
and (* globals.bend:478 *)
f_scc_validate : (Base.text) list -> (I.t_Definition) list -> (t_SccNode) list -> (t_SccClosure) list -> Base.set -> I.t_State -> (M.t_Diagnostic, I.t_State) Base.result_ =
fun v_members v_definitions v_nodes v_closures v_member_set v_state ->
(match v_members with
| [] ->
(Done (v_state))
| (v_name :: v_tail) ->
(match (f_scc_definition (v_definitions) (v_name)) with
| Fail __error -> Fail __error
| Done v_inference ->
(let v_sites = (f_scc_node_sites (v_nodes) (v_name)) in
(let v_plans = (f_scc_plans ((I.f_inference_uses (v_inference))) (v_sites) (v_closures)) in
(match (f_scc_check_boundaries ((I.f_inference_coverage (v_inference))) (v_sites) (v_plans) (v_member_set) (v_closures) (v_state)) with
| Fail __error -> Fail __error
| Done v_next ->
(f_scc_validate (v_tail) (v_definitions) (v_nodes) (v_closures) (v_member_set) (v_next)))))))
and (* globals.bend:490 *)
f_scc_update_definition : bool -> Base.text -> I.t_Inference -> (t_SccSite) list -> (t_SccClosure) list -> I.t_Definition =
fun v_included v_name v_inference v_sites v_closures ->
(match v_included with
| false ->
(I.Definition (v_name, v_inference))
| true ->
(let (I.Inference (v_ty, v_coverage, v_exits, v_reflections, v_predicates, v_uses)) = v_inference in
(let v_closure = (f_scc_predicates (v_closures) (v_name)) in
(let v_plans = (f_scc_plans (v_uses) (v_sites) (v_closures)) in
(I.Definition (v_name, (I.Inference (v_ty, v_coverage, v_exits, v_reflections, v_closure, v_plans))))))))
and (* globals.bend:500 *)
f_scc_update_definitions : (I.t_Definition) list -> Base.set -> (t_SccNode) list -> (t_SccClosure) list -> (I.t_Definition) list =
fun v_definitions v_members v_nodes v_closures ->
(match v_definitions with
| [] ->
[]
| ((I.Definition (v_name, v_inference)) :: v_tail) ->
(let v_rest = (f_scc_update_definitions (v_tail) (v_members) (v_nodes) (v_closures)) in
((f_scc_update_definition ((D.f_member (v_members) (v_name))) (v_name) (v_inference) ((f_scc_node_sites (v_nodes) (v_name))) (v_closures)) :: v_rest)))
and (* globals.bend:508 *)
f_scc_needed : (Base.text) list -> (D.t_Node) list -> bool =
fun v_members v_nodes ->
(match v_members with
| [] ->
false
| (v_name :: []) ->
(D.f_contains ((D.f_lookup (v_nodes) (v_name))) (v_name))
| _ ->
true)
and (* globals.bend:517 *)
f_close_component : bool -> t_Environment -> (Base.text) list -> (t_Declaration) list -> (M.t_Diagnostic, t_Environment) Base.result_ =
fun v_needed v_environment v_members v_declarations ->
(match v_needed with
| false ->
(Done (v_environment))
| true ->
(let (Environment (v_bindings, v_definitions, v_state)) = v_environment in
(match (f_scc_nodes (v_members) (v_declarations)) with
| Fail __error -> Fail __error
| Done v_nodes ->
(let v_member_set = (f_reference_set (v_members) ((Base.set_new ()))) in
(match (f_scc_closures (v_members) (v_member_set) (v_nodes) (v_definitions) ((I.f_substitutions_of (v_state)))) with
| Fail __error -> Fail __error
| Done v_closures ->
(match (f_scc_validate (v_members) (v_definitions) (v_nodes) (v_closures) (v_member_set) (v_state)) with
| Fail __error -> Fail __error
| Done v_checked ->
(Done ((Environment (v_bindings, (f_scc_update_definitions (v_definitions) (v_member_set) (v_nodes) (v_closures)), v_checked))))))))))
and (* globals.bend:530 *)
f_infer_groups : ((Base.text) list) list -> (D.t_Node) list -> (t_Declaration) list -> t_Environment -> (M.t_Operation) list -> (M.t_DataType) list -> (Base.text) list -> (M.t_Diagnostic, t_Environment) Base.result_ =
fun v_groups v_nodes v_declarations v_environment v_operations v_types v_functions ->
(match v_groups with
| [] ->
(Done (v_environment))
| (v_members :: v_tail) ->
(match (f_infer_component (v_members) (v_declarations) (v_environment) (v_operations) (v_types) (v_functions)) with
| Fail __error -> Fail __error
| Done v_inferred ->
(match (f_close_component ((f_scc_needed (v_members) (v_nodes))) (v_inferred) (v_members) (v_declarations)) with
| Fail __error -> Fail __error
| Done v_closed ->
(match (f_generalize_component (v_closed) (v_members) (v_operations) (v_types) (v_nodes)) with
| Fail __error -> Fail __error
| Done v_generalized ->
(f_infer_groups (v_tail) (v_nodes) (v_declarations) (v_generalized) (v_operations) (v_types) (v_functions))))))
and (* globals.bend:541 *)
f_infer_with : (t_Declaration) list -> (D.t_Node) list -> (M.t_Operation) list -> (M.t_DataType) list -> t_Environment -> (Base.text) list -> (M.t_Diagnostic, t_Environment) Base.result_ =
fun v_declarations v_nodes v_operations v_types v_imported v_imported_functions ->
(let (Environment (v_external_bindings, v_external_definitions, (I.State (v_substitutions, v_start, v_annotations)))) = v_imported in
(let v_decls = v_declarations in
(let v_created = (f_initial_bindings (v_decls) (v_start)) in
(let v_next = (f_initial_next (v_decls) (v_start)) in
(let v_bindings = (Base.list_append (v_created) (v_external_bindings)) in
(match (D.f_components (v_nodes)) with
| Fail __error -> Fail __error
| Done v_groups ->
(f_infer_groups (v_groups) (v_nodes) (v_decls) ((Environment (v_bindings, v_external_definitions, (I.State (v_substitutions, v_next, v_annotations))))) (v_operations) (v_types) ((Base.list_append ((f_function_names (v_decls))) (v_imported_functions))))))))))
and (* globals.bend:551 *)
f_infer : (t_Declaration) list -> (D.t_Node) list -> (M.t_Operation) list -> (M.t_DataType) list -> (M.t_Diagnostic, t_Environment) Base.result_ =
fun v_declarations v_nodes v_operations v_types ->
(f_infer_with (v_declarations) (v_nodes) (v_operations) (v_types) ((Environment ([], [], (I.State ((T.f_empty ()), 0, MTip))))) ([]))
