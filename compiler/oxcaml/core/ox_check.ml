(* Native semantic port of compiler/check.bend.

   Source SHA-256: 9f674a1e39e5062fcf33be1325deebb52e7019c27a8563b008eff0395085a142

   Ownership/type arguments are erased; value types are checked by OCaml.

   No Bend interpreter or generated C/JavaScript is linked. *)

open Base

module M = Ox_model

module T = Ox_types

module C = Ox_constraints

module I = Ox_infer

module E = Ox_effects

module R = Ox_effect_rows

module G = Ox_globals

module D = Ox_dependency

module TD = Ox_type_data

module P = Ox_patterns

module Index = Ox_index

type t_IdentitySet = (Base.set) Base.map

let s_0 = Base.text_of_utf8 "duplicate_type"

let s_1 = Base.text_of_utf8 "duplicate nominal identity"

let s_2 = Base.text_of_utf8 "duplicate_name"

let s_3 = Base.text_of_utf8 "duplicate top-level definition"

let s_4 = Base.text_of_utf8 "data declarations need at least one constructor"

let s_5 = Base.text_of_utf8 "unspecialized_effect"

let s_6 = Base.text_of_utf8 "effect"

let s_7 = Base.text_of_utf8 "effect instances must be specialized before checking"

let s_8 = Base.text_of_utf8 "duplicate_lambda"

let s_9 = Base.text_of_utf8 "lambda identity must be unique within its module"

let s_10 = Base.text_of_utf8 "internal_error"

let s_11 = Base.text_of_utf8 "function does not have an arrow type"

let s_12 = Base.text_of_utf8 "missing inferred binding"

let s_13 = Base.text_of_utf8 "open_effect_descriptor"

let s_14 = Base.text_of_utf8 "effect reflection requires a closed function effect row"

let s_15 = Base.text_of_utf8 "invalid_effect_descriptor"

let s_16 = Base.text_of_utf8 "effect reflection requires a named function"

let s_17 = Base.text_of_utf8 "let_effect"

let s_18 = Base.text_of_utf8 "let requires a pure RHS; bind effectful computations with use name <- expression"

let rec (* check.bend:17 *)
f_identity_members : t_IdentitySet -> Base.text -> Base.set =
fun v_index v_module_name ->
(Index.f_get (v_index) (v_module_name) ((Base.set_new ())))
and (* check.bend:20 *)
f_identity_present : t_IdentitySet -> M.t_TypeId -> bool =
fun v_index v_identity ->
(let (M.TypeId (v_module_name, v_declaration)) = v_identity in
(D.f_member ((f_identity_members (v_index) (v_module_name))) (v_declaration)))
and (* check.bend:24 *)
f_identity_add : t_IdentitySet -> M.t_TypeId -> t_IdentitySet =
fun v_index v_identity ->
(let (M.TypeId (v_module_name, v_declaration)) = v_identity in
(Base.map_set (v_index) (v_module_name) ((Base.set_add ((f_identity_members (v_index) (v_module_name))) (v_declaration)))))
and (* check.bend:28 *)
f_identity_mark : bool -> t_IdentitySet -> M.t_TypeId -> t_IdentitySet =
fun v_present v_index v_identity ->
(match v_present with
| false ->
v_index
| true ->
(f_identity_add (v_index) (v_identity)))
and (* check.bend:35 *)
f_repeated_identities : (M.t_TypeId) list -> t_IdentitySet -> t_IdentitySet -> t_IdentitySet =
fun v_identities v_seen v_repeated ->
(match v_identities with
| [] ->
v_repeated
| (v_head :: v_tail) ->
(f_repeated_identities (v_tail) ((f_identity_add (v_seen) (v_head))) ((f_identity_mark ((f_identity_present (v_seen) (v_head))) (v_repeated) (v_head)))))
and (* check.bend:43 *)
f_require_unique_identity : bool -> M.t_TypeId -> (M.t_Diagnostic, unit) Base.result_ =
fun v_repeated v_identity ->
(match v_repeated with
| false ->
(Done (()))
| true ->
(Fail ((M.Diagnostic (s_0, (M.f_type_id_show (v_identity)), s_1)))))
and (* check.bend:50 *)
f_unique_identities : (M.t_TypeId) list -> t_IdentitySet -> (M.t_Diagnostic, unit) Base.result_ =
fun v_identities v_repeated ->
(match v_identities with
| [] ->
(Done (()))
| (v_head :: v_tail) ->
(match (f_require_unique_identity ((f_identity_present (v_repeated) (v_head))) (v_head)) with
| Fail __error -> Fail __error
| Done v_unique ->
(f_unique_identities (v_tail) (v_repeated))))
and (* check.bend:60 *)
f_name_present : (Base.text) list -> Base.text -> bool =
fun v_names v_name ->
(match v_names with
| [] ->
false
| (v_head :: v_tail) ->
(E.f_or_else ((M.f_name_equal (v_head) (v_name))) ((fun _ ->
(f_name_present (v_tail) (v_name))))))
and (* check.bend:68 *)
f_repeated_names : (Base.text) list -> Base.set -> Base.set -> Base.set =
fun v_names v_seen v_repeated ->
(match v_names with
| [] ->
v_repeated
| (v_head :: v_tail) ->
(f_repeated_names (v_tail) ((Base.set_add (v_seen) (v_head))) ((D.f_mark ((D.f_member (v_seen) (v_head))) (v_repeated) (v_head)))))
and (* check.bend:75 *)
f_require_unique_name : bool -> Base.text -> Base.text -> Base.text -> (M.t_Diagnostic, unit) Base.result_ =
fun v_repeated v_name v_code v_message ->
(match v_repeated with
| false ->
(Done (()))
| true ->
(Fail ((M.Diagnostic (v_code, v_name, v_message)))))
and (* check.bend:84 *)
f_unique_names_indexed : (Base.text) list -> Base.set -> Base.text -> Base.text -> (M.t_Diagnostic, unit) Base.result_ =
fun v_names v_repeated v_code v_message ->
(match v_names with
| [] ->
(Done (()))
| (v_head :: v_tail) ->
(match (f_require_unique_name ((D.f_member (v_repeated) (v_head))) (v_head) (v_code) (v_message)) with
| Fail __error -> Fail __error
| Done v_unique ->
(f_unique_names_indexed (v_tail) (v_repeated) (v_code) (v_message))))
and (* check.bend:93 *)
f_unique_names : (Base.text) list -> (M.t_Diagnostic, unit) Base.result_ =
fun v_names ->
(f_unique_names_indexed (v_names) ((f_repeated_names (v_names) ((Base.set_new ())) ((Base.set_new ())))) (s_2) (s_3))
and (* check.bend:97 *)
f_constructor_names : (M.t_Constructor) list -> (Base.text) list =
fun v_constructors ->
(match v_constructors with
| [] ->
[]
| ((M.Constructor (v_name, v_payload, v_fields)) :: v_tail) ->
(v_name :: (f_constructor_names (v_tail))))
and (* check.bend:104 *)
f_all_constructor_names : (M.t_DataType) list -> (Base.text) list =
fun v_types ->
(match v_types with
| [] ->
[]
| ((M.DataType (v_identity, v_parameters, v_constructors)) :: v_tail) ->
(Base.list_append ((f_constructor_names (v_constructors))) ((f_all_constructor_names (v_tail)))))
and (* check.bend:112 *)
f_type_identities : (M.t_DataType) list -> (M.t_TypeId) list =
fun v_types ->
(match v_types with
| [] ->
[]
| ((M.DataType (v_identity, v_parameters, v_constructors)) :: v_tail) ->
(v_identity :: (f_type_identities (v_tail))))
and (* check.bend:119 *)
f_operation_identities : (M.t_Operation) list -> (M.t_TypeId) list =
fun v_operations ->
(match v_operations with
| [] ->
[]
| ((M.Operation (v_identity, v_parameter, v_result)) :: v_tail) ->
(v_identity :: (f_operation_identities (v_tail)))
| (v_head :: v_tail) ->
(f_operation_identities (v_tail)))
and (* check.bend:128 *)
f_validate_types_indexed : (M.t_DataType) list -> (M.t_DataType) list -> (M.t_Operation) list -> t_IdentitySet -> (M.t_Diagnostic, unit) Base.result_ =
fun v_pending v_types v_operations v_repeated ->
(match v_pending with
| [] ->
(Done (()))
| ((M.DataType (v_identity, v_parameters, v_constructors)) :: v_tail) ->
(match (f_require_unique_identity ((f_identity_present (v_repeated) (v_identity))) (v_identity)) with
| Fail __error -> Fail __error
| Done v_unique ->
(match (TD.f_require ((Base.bool_not ((Base.list_is_empty (v_constructors))))) ((M.f_type_id_show (v_identity))) (s_4)) with
| Fail __error -> Fail __error
| Done v_inhabited ->
(match (TD.f_validate_constructors (v_constructors) (v_parameters) (v_operations) (v_types)) with
| Fail __error -> Fail __error
| Done v_valid ->
(f_validate_types_indexed (v_tail) (v_types) (v_operations) (v_repeated))))))
and (* check.bend:139 *)
f_validate_types : (M.t_DataType) list -> (M.t_DataType) list -> (M.t_Operation) list -> (M.t_Diagnostic, unit) Base.result_ =
fun v_pending v_types v_operations ->
(let v_repeated = (f_repeated_identities ((f_type_identities (v_pending))) ((Base.map_new ())) ((Base.map_new ()))) in
(f_validate_types_indexed (v_pending) (v_types) (v_operations) (v_repeated)))
and (* check.bend:143 *)
f_validate_operations_indexed : (M.t_Operation) list -> (M.t_Operation) list -> (M.t_DataType) list -> t_IdentitySet -> (M.t_Diagnostic, unit) Base.result_ =
fun v_pending v_operations v_types v_repeated ->
(match v_pending with
| [] ->
(Done (()))
| ((M.Operation (v_identity, v_parameter, v_result)) :: v_tail) ->
(match (TD.f_valid_operation_identity (v_identity)) with
| Fail __error -> Fail __error
| Done v_allowed ->
(match (f_require_unique_identity ((f_identity_present (v_repeated) (v_identity))) (v_identity)) with
| Fail __error -> Fail __error
| Done v_unique ->
(match (TD.f_validate_template (v_parameter) (None) (v_operations) (v_types) ((M.f_type_id_show (v_identity)))) with
| Fail __error -> Fail __error
| Done v_p ->
(match (TD.f_validate_template (v_result) (None) (v_operations) (v_types) ((M.f_type_id_show (v_identity)))) with
| Fail __error -> Fail __error
| Done v_r ->
(f_validate_operations_indexed (v_tail) (v_operations) (v_types) (v_repeated))))))
| ((M.OperationTemplate (v_identity, v_parameters, v_parameter, v_result)) :: v_tail) ->
(match (TD.f_valid_operation_identity (v_identity)) with
| Fail __error -> Fail __error
| Done v_allowed ->
(match (TD.f_validate_template (v_parameter) ((Some (v_parameters))) (v_operations) (v_types) ((M.f_type_id_show (v_identity)))) with
| Fail __error -> Fail __error
| Done v_p ->
(match (TD.f_validate_template (v_result) ((Some (v_parameters))) (v_operations) (v_types) ((M.f_type_id_show (v_identity)))) with
| Fail __error -> Fail __error
| Done v_r ->
(f_validate_operations_indexed (v_tail) (v_operations) (v_types) (v_repeated)))))
| (v_head :: v_tail) ->
(Fail ((M.Diagnostic (s_5, s_6, s_7)))))
and (* check.bend:163 *)
f_validate_operations : (M.t_Operation) list -> (M.t_DataType) list -> (M.t_Diagnostic, unit) Base.result_ =
fun v_operations v_types ->
(let v_repeated = (f_repeated_identities ((f_operation_identities (v_operations))) ((Base.map_new ())) ((Base.map_new ()))) in
(f_validate_operations_indexed (v_operations) (v_operations) (v_types) (v_repeated)))
and (* check.bend:167 *)
f_lambda_ids : (D.t_Node) list -> (int) list =
fun v_nodes ->
(match v_nodes with
| [] ->
[]
| ((D.Node (v_name, v_references, v_lambdas)) :: v_tail) ->
(Base.list_append (v_lambdas) ((f_lambda_ids (v_tail)))))
and (* check.bend:174 *)
f_lambda_names : (int) list -> (Base.text) list =
fun v_identities ->
(match v_identities with
| [] ->
[]
| (v_head :: v_tail) ->
((Base.nat_show (v_head)) :: (f_lambda_names (v_tail))))
and (* check.bend:181 *)
f_unique_lambdas : (int) list -> (M.t_Diagnostic, unit) Base.result_ =
fun v_identities ->
(let v_names = (f_lambda_names (v_identities)) in
(f_unique_names_indexed (v_names) ((f_repeated_names (v_names) ((Base.set_new ())) ((Base.set_new ())))) (s_8) (s_9)))
and (* check.bend:186 *)
f_validate_module : M.t_Module -> (M.t_Diagnostic, unit) Base.result_ =
fun v_module ->
(let (M.Module (v_constants, v_functions, v_types, v_operations)) = v_module in
(let v_declarations = (Base.list_append ((G.f_function_declarations (v_functions))) ((G.f_constant_declarations (v_constants)))) in
(match (f_validate_types (v_types) (v_types) (v_operations)) with
| Fail __error -> Fail __error
| Done v_valid_types ->
(match (f_validate_operations (v_operations) (v_types)) with
| Fail __error -> Fail __error
| Done v_valid_operations ->
(f_unique_names ((Base.list_append ((G.f_names (v_declarations))) ((f_all_constructor_names (v_types))))))))))
and (* check.bend:197 *)
f_module_graph_validated : M.t_Module -> (M.t_Diagnostic, (D.t_Node) list) Base.result_ =
fun v_module ->
(let (M.Module (v_constants, v_functions, v_types, v_operations)) = v_module in
(match (D.f_function_nodes (v_functions)) with
| Fail __error -> Fail __error
| Done v_fns ->
(match (D.f_constant_nodes (v_constants)) with
| Fail __error -> Fail __error
| Done v_consts ->
(let v_graph = (Base.list_append (v_fns) (v_consts)) in
(match (f_unique_lambdas ((f_lambda_ids (v_graph)))) with
| Fail __error -> Fail __error
| Done v_lambdas ->
(Done (v_graph)))))))
and (* check.bend:206 *)
f_module_graph : M.t_Module -> (M.t_Diagnostic, (D.t_Node) list) Base.result_ =
fun v_module ->
(match (f_validate_module (v_module)) with
| Fail __error -> Fail __error
| Done v_valid ->
(f_module_graph_validated (v_module)))
and (* check.bend:211 *)
f_checked_signature : M.t_Ty -> Base.text -> (int) list -> (M.t_Diagnostic, M.t_Signature) Base.result_ =
fun v_ty v_name v_variables ->
(match v_ty with
| (M.FunctionTy (v_parameter, v_result, v_effects)) ->
(Done ((M.Signature (v_name, v_parameter, v_result, v_variables, (R.f_canonical (v_effects))))))
| v_other ->
(Fail ((M.Diagnostic (s_10, v_name, s_11)))))
and (* check.bend:218 *)
f_resolve_binding : (I.t_Binding) option -> T.t_Substitutions -> Base.text -> (M.t_Diagnostic, I.t_Binding) Base.result_ =
fun v_found v_substitutions v_subject ->
(match v_found with
| None ->
(Fail ((M.Diagnostic (s_10, v_subject, s_12))))
| (Some ((I.Binding (v_name, v_ty, v_variables, v_predicates)))) ->
(match (T.f_resolve (v_substitutions) (v_ty)) with
| Fail __error -> Fail __error
| Done v_resolved ->
(match (C.f_resolve_list (v_substitutions) (v_predicates)) with
| Fail __error -> Fail __error
| Done v_needs ->
(Done ((I.Binding (v_name, v_resolved, v_variables, v_needs)))))))
and (* check.bend:228 *)
f_binding_signature : I.t_Binding -> (M.t_Diagnostic, M.t_Signature) Base.result_ =
fun v_binding ->
(let (I.Binding (v_name, v_ty, v_variables, v_predicates)) = v_binding in
(f_checked_signature (v_ty) (v_name) (v_variables)))
and (* check.bend:232 *)
f_signature_effects : M.t_Signature -> (M.t_Effect) list =
fun v_signature ->
(let (M.Signature (v_name, v_parameter, v_result, v_variables, v_effects)) = v_signature in
(R.f_metadata ((R.f_operation_set (v_effects)))))
and (* check.bend:236 *)
f_function_results : (M.t_Function) list -> (I.t_Binding) list -> T.t_Substitutions -> (M.t_Diagnostic, (M.t_CheckedFunction) list) Base.result_ =
fun v_functions v_bindings v_substitutions ->
(match v_functions with
| [] ->
(Done ([]))
| ((M.Function (v_name, v_exported, v_parameter, v_p, v_r, v_body)) :: v_tail) ->
(match (f_resolve_binding ((I.f_lookup_binding (v_bindings) (v_name))) (v_substitutions) (v_name)) with
| Fail __error -> Fail __error
| Done v_binding ->
(match (f_binding_signature (v_binding)) with
| Fail __error -> Fail __error
| Done v_signature ->
(match (f_function_results (v_tail) (v_bindings) (v_substitutions)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done (((M.CheckedFunction ((M.Function (v_name, v_exported, v_parameter, v_p, v_r, v_body)), v_signature, (f_signature_effects (v_signature)))) :: v_rest)))))))
and (* check.bend:247 *)
f_checked_constant : M.t_Constant -> I.t_Binding -> M.t_CheckedConstant =
fun v_constant v_binding ->
(let (I.Binding (v_name, v_ty, v_variables, v_predicates)) = v_binding in
(M.CheckedConstant (v_constant, v_ty, v_variables)))
and (* check.bend:251 *)
f_constant_results : (M.t_Constant) list -> (I.t_Binding) list -> T.t_Substitutions -> (M.t_Diagnostic, (M.t_CheckedConstant) list) Base.result_ =
fun v_constants v_bindings v_substitutions ->
(match v_constants with
| [] ->
(Done ([]))
| ((M.Constant (v_name, v_exported, v_annotation, v_value)) :: v_tail) ->
(match (f_resolve_binding ((I.f_lookup_binding (v_bindings) (v_name))) (v_substitutions) (v_name)) with
| Fail __error -> Fail __error
| Done v_binding ->
(match (f_constant_results (v_tail) (v_bindings) (v_substitutions)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done (((f_checked_constant ((M.Constant (v_name, v_exported, v_annotation, v_value))) (v_binding)) :: v_rest))))))
and (* check.bend:261 *)
f_coverage_constraints : (I.t_Definition) list -> (I.t_Coverage) list =
fun v_definitions ->
(match v_definitions with
| [] ->
[]
| ((I.Definition (v_name, (I.Inference (v_ty, v_coverage, v_exits, v_reflections, v_predicates, v_uses)))) :: v_tail) ->
(Base.list_append (v_coverage) ((f_coverage_constraints (v_tail)))))
and (* check.bend:268 *)
f_reflection_constraints : (I.t_Definition) list -> (I.t_Reflection) list =
fun v_definitions ->
(match v_definitions with
| [] ->
[]
| ((I.Definition (v_name, (I.Inference (v_ty, v_coverage, v_exits, v_reflections, v_predicates, v_uses)))) :: v_tail) ->
(Base.list_append (v_reflections) ((f_reflection_constraints (v_tail)))))
and (* check.bend:275 *)
f_reflected_type : M.t_Ty -> Base.text -> (M.t_Diagnostic, unit) Base.result_ =
fun v_ty v_subject ->
(match v_ty with
| (M.FunctionTy (v_parameter, v_result, (M.EffectRow (v_operations, M.ClosedRow)))) ->
(Done (()))
| (M.FunctionTy (v_parameter, v_result, v_effects)) ->
(Fail ((M.Diagnostic (s_13, v_subject, s_14))))
| v_other ->
(Fail ((M.Diagnostic (s_15, v_subject, s_16)))))
and (* check.bend:284 *)
f_reflected_binding : I.t_Binding -> Base.text -> (M.t_Diagnostic, unit) Base.result_ =
fun v_binding v_subject ->
(let (I.Binding (v_name, v_ty, v_variables, v_predicates)) = v_binding in
(f_reflected_type (v_ty) (v_subject)))
and (* check.bend:288 *)
f_check_reflections : (I.t_Reflection) list -> (I.t_Binding) list -> T.t_Substitutions -> (M.t_Diagnostic, unit) Base.result_ =
fun v_reflections v_bindings v_substitutions ->
(match v_reflections with
| [] ->
(Done (()))
| ((I.Reflection (v_callee, v_subject, v_instantiated_type, v_predicates)) :: v_tail) ->
(match (T.f_resolve (v_substitutions) (v_instantiated_type)) with
| Fail __error -> Fail __error
| Done v_resolved ->
(match (f_reflected_type (v_resolved) (v_subject)) with
| Fail __error -> Fail __error
| Done v_closed ->
(f_check_reflections (v_tail) (v_bindings) (v_substitutions)))))
and (* check.bend:298 *)
f_require_let_pure : (M.t_Effect) list -> Base.text -> (M.t_Diagnostic, unit) Base.result_ =
fun v_effects v_subject ->
(match v_effects with
| [] ->
(Done (()))
| ((M.OperationEffect (v_identity)) :: v_tail) ->
(Fail ((M.Diagnostic (s_17, v_subject, s_18)))))
and (* check.bend:305 *)
f_finish : M.t_Module -> G.t_Environment -> (M.t_Diagnostic, M.t_CheckedModule) Base.result_ =
fun v_module v_environment ->
(let (M.Module (v_constants, v_functions, v_types, v_operations)) = v_module in
(let v_definitions = (G.f_env_definitions (v_environment)) in
(let v_bindings = (G.f_env_bindings (v_environment)) in
(let v_substitutions = (I.f_substitutions_of ((G.f_env_state (v_environment)))) in
(match (P.f_check ((f_coverage_constraints (v_definitions))) (v_substitutions) (v_types)) with
| Fail __error -> Fail __error
| Done v_coverage ->
(match (f_check_reflections ((f_reflection_constraints (v_definitions))) (v_bindings) (v_substitutions)) with
| Fail __error -> Fail __error
| Done v_reflection ->
(match (f_function_results (v_functions) (v_bindings) (v_substitutions)) with
| Fail __error -> Fail __error
| Done v_checked_fns ->
(match (f_constant_results (v_constants) (v_bindings) (v_substitutions)) with
| Fail __error -> Fail __error
| Done v_checked_consts ->
(Done ((M.CheckedModule (v_checked_consts, v_checked_fns, v_types, v_operations))))))))))))
and (* check.bend:317 *)
f_check_module : M.t_Module -> (M.t_Diagnostic, M.t_CheckedModule) Base.result_ =
fun v_module ->
(let (M.Module (v_constants, v_functions, v_types, v_operations)) = v_module in
(let v_declarations = (Base.list_append ((G.f_function_declarations (v_functions))) ((G.f_constant_declarations (v_constants)))) in
(match (f_module_graph (v_module)) with
| Fail __error -> Fail __error
| Done v_graph ->
(match (G.f_infer (v_declarations) (v_graph) (v_operations) (v_types)) with
| Fail __error -> Fail __error
| Done v_environment ->
(f_finish (v_module) (v_environment))))))
