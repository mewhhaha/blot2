(* Native semantic port of compiler/entry_points.bend.

   Source SHA-256: 0c0a9aa9565b33013f16b8f13239f580e8d7723e8fc4581a5b015a8ffe7c158f

   Ownership/type arguments are erased; value types are checked by OCaml.

   No Bend interpreter or generated C/JavaScript is linked. *)

open Base

module M = Ox_model

module D = Ox_dependency

module F = Ox_closures

module Index = Ox_index

module I = Ox_infer

module G = Ox_groups

module Core = Ox_checked_core

module Scheduler = Ox_check_scheduler

module Batch = Ox_inference_batch

module Constraints = Ox_constraints

type t_Entry =
  | Entry of Base.text * bool
and t_Found =
  | Found of (Base.text) list * (Base.text) list
and t_ScanWork =
  | ScanExpressions of (M.t_Expr) list
  | ScanPatterns of (M.t_Pattern) list
  | ScanArms of ((M.t_Expr) M.t_MatchArm) list
and t_Declaration =
  | Declaration of Base.text * bool * M.t_Expr
and t_Declared =
  | Declared of Base.text * bool * t_Found
and t_Graph =
  | Graph of (Base.text) list * (Base.text) list * (t_Declared) list
and t_Split =
  | Split of Base.text * Base.text
and t_Pruned =
  | Pruned of M.t_Module * Scheduler.t_Initial

let s_0 = Base.text_of_utf8 "expression_complexity"

let s_1 = Base.text_of_utf8 "entry"

let s_2 = Base.text_of_utf8 "entry reachability exceeded its traversal limit"

let s_3 = Base.text_of_utf8 "std/prelude"

let s_4 = Base.text_of_utf8 "$prelude."

let s_5 = Base.text_of_utf8 ""

let s_6 = Base.text_of_utf8 "$module["

let s_7 = Base.text_of_utf8 "]."

let s_8 = Base.text_of_utf8 "$prelude.U32"

let s_9 = Base.text_of_utf8 "$prelude.F32"

let s_10 = Base.text_of_utf8 "$prelude.Bool"

let s_11 = Base.text_of_utf8 "$prelude.Unit"

let s_12 = Base.text_of_utf8 "$prelude.Array"

let s_13 = Base.text_of_utf8 "."

let s_14 = Base.text_of_utf8 "$public:"

let s_15 = Base.text_of_utf8 "entry functions take Unit, U32, F32, Bool, Array U32 or Array F32 (or one scalar/numeric-array callback with exactly ! {Foreign}), return one of those types and handle every other effect; entry values are Unit, U32, F32 or Bool"

let s_16 = Base.text_of_utf8 "entry_type"

let s_17 = Base.text_of_utf8 "entry `"

let s_18 = Base.text_of_utf8 "` has a generic type "

let s_19 = Base.text_of_utf8 ", so it cannot be a Wasm export: "

let s_20 = Base.text_of_utf8 "` has type "

let s_21 = Base.text_of_utf8 ", which does not fit the guest ABI: "

let s_22 = Base.text_of_utf8 "entry_let_type"

let s_23 = Base.text_of_utf8 "entry let `"

let s_24 = Base.text_of_utf8 "` initializes a runtime value of type "

let s_25 = Base.text_of_utf8 "; the guest ABI exports runtime-initialized values only as Unit, U32, F32 or Bool globals or as functions that fit it: "

let s_26 = Base.text_of_utf8 "` has a generic type, so it cannot be a Wasm export: "

let s_27 = Base.text_of_utf8 "no_entry"

let s_28 = Base.text_of_utf8 "a build needs at least one `entry const` or `entry let` declaration in the entry module; entries are the Wasm exports and the roots of dead-code elimination"

let rec (* entry_points.bend:24 *)
f_runtime_value : M.t_Expr -> bool =
fun v_value ->
(match v_value with
| (M.RuntimeInitExpr (v_initial)) ->
true
| _ ->
false)
and (* entry_points.bend:31 *)
f_function_entries : (M.t_Function) list -> (t_Entry) list =
fun v_functions ->
(match v_functions with
| [] ->
[]
| ((M.Function (v_name, true, v_parameter, v_p, v_r, v_body)) :: v_tail) ->
((Entry (v_name, (f_runtime_value (v_body)))) :: (f_function_entries (v_tail)))
| (v_head :: v_tail) ->
(f_function_entries (v_tail)))
and (* entry_points.bend:40 *)
f_constant_entries : (M.t_Constant) list -> (t_Entry) list =
fun v_constants ->
(match v_constants with
| [] ->
[]
| ((M.Constant (v_name, true, v_annotation, v_value)) :: v_tail) ->
((Entry (v_name, (f_runtime_value (v_value)))) :: (f_constant_entries (v_tail)))
| (v_head :: v_tail) ->
(f_constant_entries (v_tail)))
and (* entry_points.bend:51 *)
f_entries : M.t_Module -> (t_Entry) list =
fun v_module ->
(let (M.Module (v_constants, v_functions, v_types, v_operations)) = v_module in
(Base.list_append ((f_function_entries (v_functions))) ((f_constant_entries (v_constants)))))
and (* entry_points.bend:72 *)
f_scan_work : int -> (t_ScanWork) list -> (Base.text) list -> (Base.text) list -> (M.t_Diagnostic, t_Found) Base.result_ =
fun v_fuel v_pending v_names v_members ->
(match (v_fuel, v_pending) with
| (_, []) ->
(Done ((Found (v_names, v_members))))
| (0, _) ->
(Fail ((M.Diagnostic (s_0, s_1, s_2))))
| (__nat_1, ((ScanExpressions ([])) :: v_tail)) when __nat_1 >= 1 ->
(let v_rest = (__nat_1 - 1) in
(f_scan_work (v_rest) (v_tail) (v_names) (v_members)))
| (__nat_2, ((ScanExpressions (((M.ConstantExpr (v_name)) :: v_values))) :: v_tail)) when __nat_2 >= 1 ->
(let v_rest = (__nat_2 - 1) in
(f_scan_work (v_rest) (((ScanExpressions (v_values)) :: v_tail)) ((v_name :: v_names)) (v_members)))
| (__nat_3, ((ScanExpressions (((M.FunctionExpr (v_name)) :: v_values))) :: v_tail)) when __nat_3 >= 1 ->
(let v_rest = (__nat_3 - 1) in
(f_scan_work (v_rest) (((ScanExpressions (v_values)) :: v_tail)) ((v_name :: v_names)) (v_members)))
| (__nat_4, ((ScanExpressions (((M.FunctionEffectsExpr (v_callee)) :: v_values))) :: v_tail)) when __nat_4 >= 1 ->
(let v_rest = (__nat_4 - 1) in
(f_scan_work (v_rest) (((ScanExpressions (v_values)) :: v_tail)) ((v_callee :: v_names)) (v_members)))
| (__nat_5, ((ScanExpressions (((M.CallExpr (v_callee, v_argument)) :: v_values))) :: v_tail)) when __nat_5 >= 1 ->
(let v_rest = (__nat_5 - 1) in
(f_scan_work (v_rest) (((ScanExpressions ((v_argument :: v_values))) :: v_tail)) ((v_callee :: v_names)) (v_members)))
| (__nat_6, ((ScanExpressions (((M.AssociatedExpr (v_identity, v_dispatch, v_member, v_templates, v_left, v_right)) :: v_values))) :: v_tail)) when __nat_6 >= 1 ->
(let v_rest = (__nat_6 - 1) in
(f_scan_work (v_rest) (((ScanExpressions ((v_left :: (v_right :: v_values)))) :: v_tail)) (v_names) ((v_member :: v_members))))
| (__nat_7, ((ScanExpressions (((M.QualifiedExpr (v_offset, v_annotation, v_predicates, v_value)) :: v_values))) :: v_tail)) when __nat_7 >= 1 ->
(let v_rest = (__nat_7 - 1) in
(f_scan_work (v_rest) (((ScanExpressions ((v_value :: v_values))) :: v_tail)) (v_names) ((Base.list_reverse_go ((Base.list_reverse ((Constraints.f_predicate_members (v_predicates))))) (v_members)))))
| (__nat_8, ((ScanExpressions (((M.MatchExpr (v_scrutinees, v_arms)) :: v_values))) :: v_tail)) when __nat_8 >= 1 ->
(let v_rest = (__nat_8 - 1) in
(f_scan_work (v_rest) (((ScanExpressions (v_scrutinees)) :: ((ScanArms (v_arms)) :: ((ScanExpressions (v_values)) :: v_tail)))) (v_names) (v_members)))
| (__nat_9, ((ScanExpressions (((M.GuardExpr (v_pattern, v_value, v_alternative, v_body)) :: v_values))) :: v_tail)) when __nat_9 >= 1 ->
(let v_rest = (__nat_9 - 1) in
(f_scan_work (v_rest) (((ScanPatterns ([v_pattern])) :: ((ScanExpressions ((v_value :: (v_alternative :: (v_body :: v_values))))) :: v_tail))) (v_names) (v_members)))
| (__nat_10, ((ScanExpressions ((v_expression :: v_values))) :: v_tail)) when __nat_10 >= 1 ->
(let v_rest = (__nat_10 - 1) in
(f_scan_work (v_rest) (((ScanExpressions ((F.f_children (v_expression)))) :: ((ScanExpressions (v_values)) :: v_tail))) (v_names) (v_members)))
| (__nat_11, ((ScanArms ([])) :: v_tail)) when __nat_11 >= 1 ->
(let v_rest = (__nat_11 - 1) in
(f_scan_work (v_rest) (v_tail) (v_names) (v_members)))
| (__nat_12, ((ScanArms (((M.MatchArm (v_patterns, v_body)) :: v_arms))) :: v_tail)) when __nat_12 >= 1 ->
(let v_rest = (__nat_12 - 1) in
(f_scan_work (v_rest) (((ScanPatterns (v_patterns)) :: ((ScanExpressions ([v_body])) :: ((ScanArms (v_arms)) :: v_tail)))) (v_names) (v_members)))
| (__nat_13, ((ScanPatterns ([])) :: v_tail)) when __nat_13 >= 1 ->
(let v_rest = (__nat_13 - 1) in
(f_scan_work (v_rest) (v_tail) (v_names) (v_members)))
| (__nat_14, ((ScanPatterns (((M.ValuePattern ((M.ConstantReference (v_name)))) :: v_patterns))) :: v_tail)) when __nat_14 >= 1 ->
(let v_rest = (__nat_14 - 1) in
(f_scan_work (v_rest) (((ScanPatterns (v_patterns)) :: v_tail)) ((v_name :: v_names)) (v_members)))
| (__nat_15, ((ScanPatterns (((M.ConstructorPattern (v_constructor, (Some (v_payload)))) :: v_patterns))) :: v_tail)) when __nat_15 >= 1 ->
(let v_rest = (__nat_15 - 1) in
(f_scan_work (v_rest) (((ScanPatterns ((v_payload :: v_patterns))) :: v_tail)) (v_names) (v_members)))
| (__nat_16, ((ScanPatterns (((M.ProductPattern (v_elements)) :: v_patterns))) :: v_tail)) when __nat_16 >= 1 ->
(let v_rest = (__nat_16 - 1) in
(f_scan_work (v_rest) (((ScanPatterns (v_elements)) :: ((ScanPatterns (v_patterns)) :: v_tail))) (v_names) (v_members)))
| (__nat_17, ((ScanPatterns ((v_pattern :: v_patterns))) :: v_tail)) when __nat_17 >= 1 ->
(let v_rest = (__nat_17 - 1) in
(f_scan_work (v_rest) (((ScanPatterns (v_patterns)) :: v_tail)) (v_names) (v_members))))
and (* entry_points.bend:115 *)
f_scan_limit : unit -> int =
fun () ->
(Base.u32_to_nat (0x01000000l))
and (* entry_points.bend:118 *)
f_scan : M.t_Expr -> (M.t_Diagnostic, t_Found) Base.result_ =
fun v_body ->
(f_scan_work ((f_scan_limit ())) ([(ScanExpressions ([v_body]))]) ([]) ([]))
and (* entry_points.bend:127 *)
f_scan_declaration : t_Declaration -> unit -> (M.t_Diagnostic, t_Declared) Base.result_ =
fun v_declaration v_context ->
(let (Declaration (v_name, v_root, v_body)) = v_declaration in
(match (f_scan (v_body)) with
| Fail __error -> Fail __error
| Done v_found ->
(Done ((Declared (v_name, v_root, v_found))))))
and (* entry_points.bend:133 *)
f_function_declarations : (M.t_Function) list -> ((t_Declaration) Batch.t_Weighted) list -> ((t_Declaration) Batch.t_Weighted) list =
fun v_functions v_rest ->
(match v_functions with
| [] ->
v_rest
| ((M.Function (v_name, v_exported, v_parameter, v_p, v_r, v_body)) :: v_tail) ->
((Batch.Weighted ((Declaration (v_name, v_exported, v_body)), 1)) :: (f_function_declarations (v_tail) (v_rest))))
and (* entry_points.bend:140 *)
f_constant_declarations : (M.t_Constant) list -> ((t_Declaration) Batch.t_Weighted) list =
fun v_constants ->
(match v_constants with
| [] ->
[]
| ((M.Constant (v_name, v_exported, v_annotation, v_value)) :: v_tail) ->
((Batch.Weighted ((Declaration (v_name, v_exported, v_value)), 1)) :: (f_constant_declarations (v_tail))))
and (* entry_points.bend:148 *)
f_scan_grain : unit -> int =
fun () ->
64
and (* entry_points.bend:154 *)
f_add_declared : t_Declared -> t_Graph -> t_Graph =
fun v_declared v_rest ->
(let (Declared (v_name, v_root, v_found)) = v_declared in
(let (Graph (v_names, v_roots, v_nodes)) = v_rest in
(Graph ((v_name :: v_names), (Base.bool_pick (v_root) ((v_name :: v_roots)) (v_roots)), ((Declared (v_name, v_root, v_found)) :: v_nodes)))))
and (* entry_points.bend:159 *)
f_collect_graph : ((M.t_Diagnostic, t_Declared) Base.result_) list -> (M.t_Diagnostic, t_Graph) Base.result_ =
fun v_scanned ->
(match v_scanned with
| [] ->
(Done ((Graph ([], [], []))))
| ((Fail (v_diagnostic)) :: v_tail) ->
(Fail (v_diagnostic))
| ((Done (v_declared)) :: v_tail) ->
(match (f_collect_graph (v_tail)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done ((f_add_declared (v_declared) (v_rest))))))
and (* entry_points.bend:175 *)
f_owner_prefix : M.t_TypeId -> Base.text -> Base.text =
fun v_identity v_entry ->
(let (M.TypeId (v_module_name, v_declaration)) = v_identity in
(Base.string_append (Base.bool_pick ((M.f_name_equal (v_module_name) (s_3))) (s_4) ((Base.bool_pick ((M.f_name_equal (v_module_name) (v_entry))) (s_5) ((Base.string_append s_6 (Base.string_append v_module_name s_7)))))) v_declaration))
and (* entry_points.bend:179 *)
f_type_owners : (M.t_DataType) list -> Base.text -> Base.set -> Base.set =
fun v_types v_entry v_owners ->
(match v_types with
| [] ->
v_owners
| ((M.DataType (v_identity, v_parameters, v_constructors)) :: v_tail) ->
(f_type_owners (v_tail) (v_entry) ((Base.set_add (v_owners) ((f_owner_prefix (v_identity) (v_entry)))))))
and (* entry_points.bend:186 *)
f_builtin_owners : unit -> Base.set =
fun () ->
(Base.set_from_list ([s_8; s_9; s_10; s_11; s_12]))
and (* entry_points.bend:192 *)
f_split_reversed : (Base.text) list -> (t_Split) option =
fun v_reversed ->
(match v_reversed with
| (v_member :: (v_first :: v_rest)) ->
(Some ((Split ((Base.string_join ((Base.list_reverse ((v_first :: v_rest)))) (s_13)), v_member))))
| _ ->
None)
and (* entry_points.bend:201 *)
f_split_member : Base.text -> (t_Split) option =
fun v_name ->
(f_split_reversed ((Base.list_reverse ((Base.string_split (v_name) ((Chr 0x0000002e)))))))
and (* entry_points.bend:204 *)
f_add_implementation : (t_Split) option -> Base.text -> Base.set -> ((Base.text) list) Base.map -> ((Base.text) list) Base.map =
fun v_split v_name v_owners v_index ->
(match v_split with
| None ->
v_index
| (Some ((Split (v_owner, v_member)))) ->
(Base.bool_pick ((D.f_member (v_owners) (v_owner))) ((Base.map_set (v_index) (v_member) ((v_name :: (Index.f_get (v_index) (v_member) ([])))))) (v_index)))
and (* entry_points.bend:211 *)
f_implementations : (Base.text) list -> Base.set -> ((Base.text) list) Base.map -> ((Base.text) list) Base.map =
fun v_names v_owners v_index ->
(match v_names with
| [] ->
v_index
| (v_name :: v_tail) ->
(f_implementations (v_tail) (v_owners) ((f_add_implementation ((f_split_member (v_name))) (v_name) (v_owners) (v_index)))))
and (* entry_points.bend:218 *)
f_member_edges : (Base.text) list -> ((Base.text) list) Base.map -> (Base.text) list -> (Base.text) list =
fun v_members v_index v_edges ->
(match v_members with
| [] ->
v_edges
| (v_member :: v_tail) ->
(f_member_edges (v_tail) (v_index) ((Base.list_append ((Index.f_get (v_index) (v_member) ([]))) (v_edges)))))
and (* entry_points.bend:225 *)
f_adjacency : (t_Declared) list -> ((Base.text) list) Base.map -> ((Base.text) list) Base.map -> ((Base.text) list) Base.map =
fun v_nodes v_index v_edges ->
(match v_nodes with
| [] ->
v_edges
| ((Declared (v_name, v_root, (Found (v_names, v_members)))) :: v_tail) ->
(f_adjacency (v_tail) (v_index) ((Base.map_set (v_edges) (v_name) ((f_member_edges ((Base.set_to_list ((Base.set_from_list (v_members))))) (v_index) (v_names)))))))
and (* entry_points.bend:232 *)
f_edge_count : (t_Declared) list -> int -> int =
fun v_nodes v_total ->
(match v_nodes with
| [] ->
v_total
| ((Declared (v_name, v_root, (Found (v_names, v_members)))) :: v_tail) ->
(f_edge_count (v_tail) ((Base.nat_add (v_total) ((Base.nat_add ((Base.list_length (v_names))) ((Base.list_length (v_members)))))))))
and (* entry_points.bend:239 *)
f_reach : t_Graph -> Base.set -> (M.t_Diagnostic, Base.set) Base.result_ =
fun v_graph v_owners ->
(let (Graph (v_names, v_roots, v_nodes)) = v_graph in
(let v_index = (f_implementations (v_names) (v_owners) ((Base.map_new ()))) in
(let v_edges = (f_adjacency (v_nodes) (v_index) ((Base.map_new ()))) in
(let v_count = (Base.list_length (v_names)) in
(let v_fuel = (Base.nat_add 1 (Base.nat_add ((Base.nat_add ((Base.nat_mul (v_count) (2))) ((f_edge_count (v_nodes) (0))))) ((Base.nat_mul (v_count) (v_count))))) in
(match (D.f_reachable (v_fuel) (v_roots) (v_edges) ((Base.set_from_list (v_names))) ((Base.set_new ())) ([])) with
| Fail __error -> Fail __error
| Done v_reached ->
(Done ((D.f_reached_seen (v_reached))))))))))
and (* entry_points.bend:253 *)
f_reachable : M.t_Module -> Base.text -> (M.t_Diagnostic, Base.set) Base.result_ =
fun v_module v_entry ->
(let (M.Module (v_constants, v_functions, v_types, v_operations)) = v_module in
(let v_tasks = (f_function_declarations (v_functions) ((f_constant_declarations (v_constants)))) in
(let v_scanned = (Batch.f_execute (f_scan_declaration) ((Batch.f_plan (v_tasks) ((f_scan_grain ())))) (())) in
(match (f_collect_graph (v_scanned)) with
| Fail __error -> Fail __error
| Done v_graph ->
(f_reach (v_graph) ((f_type_owners (v_types) (v_entry) ((f_builtin_owners ())))))))))
and (* entry_points.bend:261 *)
f_keep_functions : (M.t_Function) list -> Base.set -> (M.t_Function) list =
fun v_functions v_seen ->
(match v_functions with
| [] ->
[]
| (v_function :: v_tail) ->
(let (M.Function (v_name, v_exported, v_parameter, v_p, v_r, v_body)) = v_function in
(let v_rest = (f_keep_functions (v_tail) (v_seen)) in
(Base.bool_pick ((D.f_member (v_seen) (v_name))) ((v_function :: v_rest)) (v_rest)))))
and (* entry_points.bend:270 *)
f_keep_constants : (M.t_Constant) list -> Base.set -> (M.t_Constant) list =
fun v_constants v_seen ->
(match v_constants with
| [] ->
[]
| (v_constant :: v_tail) ->
(let (M.Constant (v_name, v_exported, v_annotation, v_value)) = v_constant in
(let v_rest = (f_keep_constants (v_tail) (v_seen)) in
(Base.bool_pick ((D.f_member (v_seen) (v_name))) ((v_constant :: v_rest)) (v_rest)))))
and (* entry_points.bend:279 *)
f_keep_module : M.t_Module -> Base.set -> M.t_Module =
fun v_module v_seen ->
(let (M.Module (v_constants, v_functions, v_types, v_operations)) = v_module in
(M.Module ((f_keep_constants (v_constants) (v_seen)), (f_keep_functions (v_functions) (v_seen)), v_types, v_operations)))
and (* entry_points.bend:283 *)
f_keep_checked_functions : (M.t_CheckedFunction) list -> Base.set -> (M.t_CheckedFunction) list =
fun v_functions v_seen ->
(match v_functions with
| [] ->
[]
| (v_checked :: v_tail) ->
(let (M.CheckedFunction ((M.Function (v_name, v_exported, v_parameter, v_p, v_r, v_body)), v_signature, v_effects)) = v_checked in
(let v_rest = (f_keep_checked_functions (v_tail) (v_seen)) in
(Base.bool_pick ((D.f_member (v_seen) (v_name))) ((v_checked :: v_rest)) (v_rest)))))
and (* entry_points.bend:292 *)
f_keep_checked_constants : (M.t_CheckedConstant) list -> Base.set -> (M.t_CheckedConstant) list =
fun v_constants v_seen ->
(match v_constants with
| [] ->
[]
| (v_checked :: v_tail) ->
(let (M.CheckedConstant ((M.Constant (v_name, v_exported, v_annotation, v_value)), v_ty, v_variables)) = v_checked in
(let v_rest = (f_keep_checked_constants (v_tail) (v_seen)) in
(Base.bool_pick ((D.f_member (v_seen) (v_name))) ((v_checked :: v_rest)) (v_rest)))))
and (* entry_points.bend:301 *)
f_keep_checked : M.t_CheckedModule -> Base.set -> M.t_CheckedModule =
fun v_checked v_seen ->
(let (M.CheckedModule (v_constants, v_functions, v_types, v_operations)) = v_checked in
(M.CheckedModule ((f_keep_checked_constants (v_constants) (v_seen)), (f_keep_checked_functions (v_functions) (v_seen)), v_types, v_operations)))
and (* entry_points.bend:305 *)
f_group_reached : (I.t_Binding) list -> Base.set -> bool =
fun v_members v_seen ->
(match v_members with
| [] ->
true
| ((I.Binding (v_name, v_ty, v_variables, v_predicates)) :: v_tail) ->
(D.f_member (v_seen) (v_name)))
and (* entry_points.bend:313 *)
f_keep_needs : (G.t_GroupNeeds) list -> Base.set -> (G.t_GroupNeeds) list =
fun v_needs v_seen ->
(match v_needs with
| [] ->
[]
| (v_group :: v_tail) ->
(let (G.GroupNeeds (v_next, v_requirements, v_members, v_generalized)) = v_group in
(let v_rest = (f_keep_needs (v_tail) (v_seen)) in
(Base.bool_pick ((f_group_reached (v_members) (v_seen))) ((v_group :: v_rest)) (v_rest)))))
and (* entry_points.bend:322 *)
f_module_reached : M.t_Module -> Base.set -> bool =
fun v_module v_seen ->
(match v_module with
| (M.Module (((M.Constant (v_name, v_exported, v_annotation, v_value)) :: v_constants), v_functions, v_types, v_operations)) ->
(D.f_member (v_seen) (v_name))
| (M.Module ([], ((M.Function (v_name, v_exported, v_parameter, v_p, v_r, v_body)) :: v_functions), v_types, v_operations)) ->
(D.f_member (v_seen) (v_name))
| _ ->
true)
and (* entry_points.bend:331 *)
f_keep_certificates : (Core.t_Certificate) list -> Base.set -> (Core.t_Certificate) list =
fun v_certificates v_seen ->
(match v_certificates with
| [] ->
[]
| (v_certificate :: v_tail) ->
(let (Core.Certificate (v_module, v_checked, v_imports)) = v_certificate in
(let v_rest = (f_keep_certificates (v_tail) (v_seen)) in
(Base.bool_pick ((f_module_reached (v_module) (v_seen))) ((v_certificate :: v_rest)) (v_rest)))))
and (* entry_points.bend:340 *)
f_keep_initial : Scheduler.t_Initial -> Base.set -> Scheduler.t_Initial =
fun v_initial v_seen ->
(let (Scheduler.Initial (v_checked, v_certificates, v_needs)) = v_initial in
(Scheduler.Initial ((f_keep_checked (v_checked) (v_seen)), (f_keep_certificates (v_certificates) (v_seen)), (f_keep_needs (v_needs) (v_seen)))))
and (* entry_points.bend:347 *)
f_pruned_module : t_Pruned -> M.t_Module =
fun v_pruned ->
(let (Pruned (v_module, v_initial)) = v_pruned in
v_module)
and (* entry_points.bend:351 *)
f_pruned_initial : t_Pruned -> Scheduler.t_Initial =
fun v_pruned ->
(let (Pruned (v_module, v_initial)) = v_pruned in
v_initial)
and (* entry_points.bend:357 *)
f_prune_initial : M.t_Module -> Scheduler.t_Initial -> Base.text -> (M.t_Diagnostic, t_Pruned) Base.result_ =
fun v_module v_initial v_entry ->
(match (f_reachable (v_module) (v_entry)) with
| Fail __error -> Fail __error
| Done v_seen ->
(Done ((Pruned ((f_keep_module (v_module) (v_seen)), (f_keep_initial (v_initial) (v_seen)))))))
and (* entry_points.bend:362 *)
f_prune_checked : M.t_Module -> M.t_CheckedModule -> Base.text -> (M.t_Diagnostic, t_Pruned) Base.result_ =
fun v_module v_checked v_entry ->
(f_prune_initial (v_module) ((Scheduler.Initial (v_checked, [], []))) (v_entry))
and (* entry_points.bend:369 *)
f_strip_public : Base.text -> Base.text =
fun v_name ->
(Base.bool_pick ((Base.string_starts_with (v_name) (s_14))) ((Base.string_drop (v_name) (8))) (v_name))
and (* entry_points.bend:372 *)
f_exported_functions : (M.t_CheckedFunction) list -> Base.set -> Base.set =
fun v_functions v_names ->
(match v_functions with
| [] ->
v_names
| ((M.CheckedFunction ((M.Function (v_name, true, v_parameter, v_p, v_r, v_body)), v_signature, v_effects)) :: v_tail) ->
(f_exported_functions (v_tail) ((Base.set_add (v_names) ((f_strip_public (v_name))))))
| (v_head :: v_tail) ->
(f_exported_functions (v_tail) (v_names)))
and (* entry_points.bend:381 *)
f_exported_constants : (M.t_CheckedConstant) list -> Base.set -> Base.set =
fun v_constants v_names ->
(match v_constants with
| [] ->
v_names
| ((M.CheckedConstant ((M.Constant (v_name, true, v_annotation, v_value)), v_ty, v_variables)) :: v_tail) ->
(f_exported_constants (v_tail) ((Base.set_add (v_names) (v_name))))
| (v_head :: v_tail) ->
(f_exported_constants (v_tail) (v_names)))
and (* entry_points.bend:390 *)
f_function_types : (M.t_CheckedFunction) list -> (M.t_Ty) Base.map -> (M.t_Ty) Base.map =
fun v_functions v_types ->
(match v_functions with
| [] ->
v_types
| ((M.CheckedFunction (v_function, (M.Signature (v_name, v_parameter, v_result, v_variables, v_row)), v_effects)) :: v_tail) ->
(f_function_types (v_tail) ((Base.map_set (v_types) (v_name) ((M.FunctionTy (v_parameter, v_result, v_row)))))))
and (* entry_points.bend:397 *)
f_constant_types : (M.t_CheckedConstant) list -> (M.t_Ty) Base.map -> (M.t_Ty) Base.map =
fun v_constants v_types ->
(match v_constants with
| [] ->
v_types
| ((M.CheckedConstant ((M.Constant (v_name, v_exported, v_annotation, v_value)), v_ty, v_variables)) :: v_tail) ->
(f_constant_types (v_tail) ((Base.map_set (v_types) (v_name) (v_ty)))))
and (* entry_points.bend:404 *)
f_abi_rule : unit -> Base.text =
fun () ->
s_15
and (* entry_points.bend:407 *)
f_open_row : M.t_EffectRow -> bool =
fun v_row ->
(match v_row with
| (M.EffectRow (v_operations, M.ClosedRow)) ->
false
| _ ->
true)
and (* entry_points.bend:416 *)
f_generic_types : int -> (M.t_Ty) list -> bool =
fun v_fuel v_pending ->
(match (v_fuel, v_pending) with
| (_, []) ->
false
| (0, _) ->
true
| (__nat_18, ((M.ParameterTy (v_index)) :: v_tail)) when __nat_18 >= 1 ->
(let v_rest = (__nat_18 - 1) in
true)
| (__nat_19, ((M.VariableTy (v_index)) :: v_tail)) when __nat_19 >= 1 ->
(let v_rest = (__nat_19 - 1) in
true)
| (__nat_20, ((M.FunctionTy (v_parameter, v_result, v_effects)) :: v_tail)) when __nat_20 >= 1 ->
(let v_rest = (__nat_20 - 1) in
(Base.bool_or ((f_open_row (v_effects))) ((f_generic_types (v_rest) ((v_parameter :: (v_result :: v_tail)))))))
| (__nat_21, ((M.AppliedTy (v_identity, v_arguments)) :: v_tail)) when __nat_21 >= 1 ->
(let v_rest = (__nat_21 - 1) in
(f_generic_types (v_rest) ((Base.list_append (v_arguments) (v_tail)))))
| (__nat_22, ((M.ProductTy (v_elements)) :: v_tail)) when __nat_22 >= 1 ->
(let v_rest = (__nat_22 - 1) in
(f_generic_types (v_rest) ((Base.list_append (v_elements) (v_tail)))))
| (__nat_23, ((M.ArrayTy (v_element)) :: v_tail)) when __nat_23 >= 1 ->
(let v_rest = (__nat_23 - 1) in
(f_generic_types (v_rest) ((v_element :: v_tail))))
| (__nat_24, ((M.StateProviderTy (v_read, v_write, v_state)) :: v_tail)) when __nat_24 >= 1 ->
(let v_rest = (__nat_24 - 1) in
(f_generic_types (v_rest) ((v_state :: v_tail))))
| (__nat_25, (v_other :: v_tail)) when __nat_25 >= 1 ->
(let v_rest = (__nat_25 - 1) in
(f_generic_types (v_rest) (v_tail))))
and (* entry_points.bend:439 *)
f_entry_type_failure : bool -> Base.text -> M.t_Ty -> M.t_Diagnostic =
fun v_generic v_name v_ty ->
(match v_generic with
| true ->
(M.Diagnostic (s_16, v_name, (Base.string_append s_17 (Base.string_append v_name (Base.string_append s_18 (Base.string_append (M.f_type_show (v_ty)) (Base.string_append s_19 (f_abi_rule ()))))))))
| false ->
(M.Diagnostic (s_16, v_name, (Base.string_append s_17 (Base.string_append v_name (Base.string_append s_20 (Base.string_append (M.f_type_show (v_ty)) (Base.string_append s_21 (f_abi_rule ())))))))))
and (* entry_points.bend:446 *)
f_entry_failure : bool -> Base.text -> (M.t_Ty) option -> M.t_Diagnostic =
fun v_runtime v_name v_found ->
(match (v_runtime, v_found) with
| (false, (Some (v_ty))) ->
(f_entry_type_failure ((f_generic_types (4096) ([v_ty]))) (v_name) (v_ty))
| (true, (Some (v_ty))) ->
(M.Diagnostic (s_22, v_name, (Base.string_append s_23 (Base.string_append v_name (Base.string_append s_24 (Base.string_append (M.f_type_show (v_ty)) (Base.string_append s_25 (f_abi_rule ()))))))))
| (_, None) ->
(M.Diagnostic (s_16, v_name, (Base.string_append s_17 (Base.string_append v_name (Base.string_append s_26 (f_abi_rule ())))))))
and (* entry_points.bend:455 *)
f_verify_entry : bool -> bool -> Base.text -> (M.t_Ty) option -> (M.t_Diagnostic, unit) Base.result_ =
fun v_exported v_runtime v_name v_found ->
(match v_exported with
| true ->
(Done (()))
| false ->
(Fail ((f_entry_failure (v_runtime) (v_name) (v_found)))))
and (* entry_points.bend:462 *)
f_verify_entries : (t_Entry) list -> Base.set -> (M.t_Ty) Base.map -> (M.t_Diagnostic, unit) Base.result_ =
fun v_entries v_exported v_types ->
(match v_entries with
| [] ->
(Done (()))
| ((Entry (v_name, v_runtime)) :: v_tail) ->
(match (f_verify_entry ((D.f_member (v_exported) (v_name))) (v_runtime) (v_name) ((Index.f_find (v_types) (v_name)))) with
| Fail __error -> Fail __error
| Done v_valid ->
(f_verify_entries (v_tail) (v_exported) (v_types))))
and (* entry_points.bend:473 *)
f_verify : (t_Entry) list -> M.t_CheckedModule -> (M.t_Diagnostic, unit) Base.result_ =
fun v_entries v_checked ->
(let (M.CheckedModule (v_constants, v_functions, v_types, v_operations)) = v_checked in
(f_verify_entries (v_entries) ((f_exported_constants (v_constants) ((f_exported_functions (v_functions) ((Base.set_new ())))))) ((f_constant_types (v_constants) ((f_function_types (v_functions) ((Base.map_new ()))))))))
and (* entry_points.bend:477 *)
f_has_exports : (M.t_CheckedFunction) list -> (M.t_CheckedConstant) list -> bool =
fun v_functions v_constants ->
(Base.bool_not ((Base.nat_is_eq ((Base.set_size ((f_exported_constants (v_constants) ((f_exported_functions (v_functions) ((Base.set_new ())))))))) (0))))
and (* entry_points.bend:480 *)
f_require_exports_found : bool -> (M.t_Diagnostic, unit) Base.result_ =
fun v_found ->
(match v_found with
| true ->
(Done (()))
| false ->
(Fail ((M.Diagnostic (s_27, s_1, s_28)))))
and (* entry_points.bend:489 *)
f_require_exports : M.t_CheckedModule -> (M.t_Diagnostic, unit) Base.result_ =
fun v_checked ->
(let (M.CheckedModule (v_constants, v_functions, v_types, v_operations)) = v_checked in
(f_require_exports_found ((f_has_exports (v_functions) (v_constants)))))
