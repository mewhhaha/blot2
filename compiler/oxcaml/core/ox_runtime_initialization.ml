(* Native semantic port of compiler/runtime_initialization.bend.

   Source SHA-256: 8d814e7095248d4c974d21fe8aea2c00db0b5790623f65f350e973444f87c195

   Ownership/type arguments are erased; value types are checked by OCaml.

   No Bend interpreter or generated C/JavaScript is linked. *)

open Base

module M = Ox_model

module D = Ox_dependency

module Index = Ox_index

type t_Initializer =
  | Initializer of Base.text * M.t_Expr

let s_0 = Base.text_of_utf8 "initialization_cycle"

let s_1 = Base.text_of_utf8 "top-level let initializers form a dependency cycle"

let rec (* runtime_initialization.bend:9 *)
f_bindings : (M.t_CheckedConstant) list -> (t_Initializer) list =
fun v_constants ->
(match v_constants with
| [] ->
[]
| ((M.CheckedConstant ((M.Constant (v_name, v_exported, v_annotation, (M.RuntimeInitExpr (v_value)))), v_ty, v_variables)) :: v_tail) ->
((Initializer (v_name, v_value)) :: (f_bindings (v_tail)))
| (v_head :: v_tail) ->
(f_bindings (v_tail)))
and (* runtime_initialization.bend:18 *)
f_index : (t_Initializer) list -> (t_Initializer) Base.map -> (t_Initializer) Base.map =
fun v_initializers v_indexed ->
(match v_initializers with
| [] ->
v_indexed
| (v_initializer :: v_tail) ->
(let (Initializer (v_name, v_value)) = v_initializer in
(f_index (v_tail) ((Base.map_set (v_indexed) (v_name) (v_initializer))))))
and (* runtime_initialization.bend:26 *)
f_function_nodes : (M.t_CheckedFunction) list -> (M.t_Diagnostic, (D.t_Node) list) Base.result_ =
fun v_functions ->
(match v_functions with
| [] ->
(Done ([]))
| ((M.CheckedFunction (v_function, v_signature, v_effects)) :: v_tail) ->
(match (D.f_function_nodes ([v_function])) with
| Fail __error -> Fail __error
| Done v_nodes ->
(match (f_function_nodes (v_tail)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done ((Base.list_append (v_nodes) (v_rest)))))))
and (* runtime_initialization.bend:36 *)
f_constant_nodes : (M.t_CheckedConstant) list -> (M.t_Diagnostic, (D.t_Node) list) Base.result_ =
fun v_constants ->
(match v_constants with
| [] ->
(Done ([]))
| ((M.CheckedConstant (v_constant, v_ty, v_variables)) :: v_tail) ->
(match (D.f_constant_nodes ([v_constant])) with
| Fail __error -> Fail __error
| Done v_nodes ->
(match (f_constant_nodes (v_tail)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done ((Base.list_append (v_nodes) (v_rest)))))))
and (* runtime_initialization.bend:46 *)
f_prepend : (t_Initializer) option -> (t_Initializer) list -> (t_Initializer) list =
fun v_found v_rest ->
(match v_found with
| None ->
v_rest
| (Some (v_initializer)) ->
(v_initializer :: v_rest))
and (* runtime_initialization.bend:53 *)
f_members : (Base.text) list -> (t_Initializer) Base.map -> (t_Initializer) list =
fun v_names v_indexed ->
(match v_names with
| [] ->
[]
| (v_name :: v_tail) ->
(f_prepend ((Index.f_find (v_indexed) (v_name))) ((f_members (v_tail) (v_indexed)))))
and (* runtime_initialization.bend:60 *)
f_ordered_component : (t_Initializer) list -> bool -> (M.t_Diagnostic, (t_Initializer) list) Base.result_ =
fun v_initializers v_cyclic ->
(match (v_initializers, v_cyclic) with
| ([], _) ->
(Done ([]))
| (v_initializers, false) ->
(Done (v_initializers))
| (((Initializer (v_name, v_value)) :: v_tail), true) ->
(Fail ((M.Diagnostic (s_0, v_name, s_1)))))
and (* runtime_initialization.bend:69 *)
f_ordered : ((Base.text) list) list -> (t_Initializer) Base.map -> ((Base.text) list) Base.map -> (M.t_Diagnostic, (t_Initializer) list) Base.result_ =
fun v_components v_indexed v_edges ->
(match v_components with
| [] ->
(Done ([]))
| ([] :: v_tail) ->
(f_ordered (v_tail) (v_indexed) (v_edges))
| ((v_name :: v_following) :: v_tail) ->
(match (f_ordered_component ((f_members ((v_name :: v_following)) (v_indexed))) ((Base.bool_or ((Base.bool_not ((Base.list_is_empty (v_following))))) ((D.f_contains ((D.f_neighbors (v_edges) (v_name))) (v_name)))))) with
| Fail __error -> Fail __error
| Done v_head ->
(match (f_ordered (v_tail) (v_indexed) (v_edges)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done ((Base.list_append (v_head) (v_rest)))))))
and (* runtime_initialization.bend:81 *)
f_plan : (t_Initializer) list -> (M.t_CheckedConstant) list -> (M.t_CheckedFunction) list -> (M.t_Diagnostic, (t_Initializer) list) Base.result_ =
fun v_initializers v_constants v_functions ->
(match v_initializers with
| [] ->
(Done ([]))
| v_initializers ->
(match (f_function_nodes (v_functions)) with
| Fail __error -> Fail __error
| Done v_fn_nodes ->
(match (f_constant_nodes (v_constants)) with
| Fail __error -> Fail __error
| Done v_const_nodes ->
(let v_graph = (Base.list_append (v_fn_nodes) (v_const_nodes)) in
(match (D.f_components (v_graph)) with
| Fail __error -> Fail __error
| Done v_components ->
(f_ordered (v_components) ((f_index (v_initializers) (MTip))) ((D.f_adjacency (v_graph) (MTip)))))))))
