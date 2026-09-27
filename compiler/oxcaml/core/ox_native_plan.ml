(* Native semantic port of compiler/native_plan.bend.

   Source SHA-256: 22e1ba26f2cc60a08fd4ab64a1d5fdb5f8dde87bef799b8adc690e34e8a7b060

   Ownership/type arguments are erased; value types are checked by OCaml.

   No Bend interpreter or generated C/JavaScript is linked. *)

open Base

module M = Ox_model

module D = Ox_dependency

module Check = Ox_check

module Scheduler = Ox_check_scheduler

module G = Ox_groups

module Globals = Ox_globals

type t_Nominals =
  | Nominals of (M.t_Diagnostic, (G.t_DeclarationUsage) list) Base.result_ * (M.t_Diagnostic, (G.t_DeclarationUsage) list) Base.result_
and t_Scanned =
  | Scanned of (M.t_Diagnostic, (D.t_Node) list) Base.result_ * (M.t_Diagnostic, (D.t_Node) list) Base.result_ * (int) Base.map
and t_ScannedGraph =
  | ScannedGraph of (M.t_Diagnostic, (D.t_Node) list) Base.result_ * (M.t_Diagnostic, (D.t_Node) list) Base.result_

let rec (* native_plan.bend:12 *)
f_nominal_scan : M.t_Module -> (M.t_TypeId) Base.map -> t_Nominals =
fun v_module v_constructors ->
(let (M.Module (v_constants, v_functions, v_types, v_operations)) = v_module in
(Nominals ((G.f_declaration_usages ((Globals.f_function_declarations (v_functions))) (v_constructors)), (G.f_declaration_usages ((Globals.f_constant_declarations (v_constants))) (v_constructors)))))
and (* native_plan.bend:16 *)
f_append_usages : (M.t_Diagnostic, (G.t_DeclarationUsage) list) Base.result_ -> (M.t_Diagnostic, (G.t_DeclarationUsage) list) Base.result_ -> (M.t_Diagnostic, (G.t_DeclarationUsage) list) Base.result_ =
fun v_left v_right ->
(match v_left with
| Fail __error -> Fail __error
| Done v_a ->
(match v_right with
| Fail __error -> Fail __error
| Done v_b ->
(Done ((Base.list_append (v_a) (v_b))))))
and (* native_plan.bend:22 *)
f_merge_nominals : t_Nominals -> t_Nominals -> t_Nominals =
fun v_left v_right ->
(let (Nominals (v_functions, v_constants)) = v_left in
(let (Nominals (v_fs, v_cs)) = v_right in
(Nominals ((f_append_usages (v_functions) (v_fs)), (f_append_usages (v_constants) (v_cs))))))
and (* native_plan.bend:27 *)
f_nominal_usages : t_Nominals -> (M.t_Diagnostic, (G.t_DeclarationUsage) list) Base.result_ =
fun v_scanned ->
(let (Nominals (v_functions, v_constants)) = v_scanned in
(f_append_usages (v_functions) (v_constants)))
and (* native_plan.bend:39 *)
f_function_costs : (M.t_Function) list -> (int) Base.map -> (int) Base.map =
fun v_functions v_costs ->
(match v_functions with
| [] ->
v_costs
| ((M.Function (v_name, v_exported, v_parameter, v_p, v_r, v_body)) :: v_tail) ->
(let v_cost = (Scheduler.f_module_cost ((M.Module ([], [(M.Function (v_name, v_exported, v_parameter, v_p, v_r, v_body))], [], [])))) in
(f_function_costs (v_tail) ((Base.map_set (v_costs) (v_name) (v_cost))))))
and (* native_plan.bend:47 *)
f_constant_costs : (M.t_Constant) list -> (int) Base.map -> (int) Base.map =
fun v_constants v_costs ->
(match v_constants with
| [] ->
v_costs
| ((M.Constant (v_name, v_exported, v_annotation, v_value)) :: v_tail) ->
(let v_cost = (Scheduler.f_module_cost ((M.Module ([(M.Constant (v_name, v_exported, v_annotation, v_value))], [], [], [])))) in
(f_constant_costs (v_tail) ((Base.map_set (v_costs) (v_name) (v_cost))))))
and (* native_plan.bend:55 *)
f_scan : M.t_Module -> t_Scanned =
fun v_module ->
(let (M.Module (v_constants, v_functions, v_types, v_operations)) = v_module in
(Scanned ((D.f_function_nodes (v_functions)), (D.f_constant_nodes (v_constants)), (f_function_costs (v_functions) ((f_constant_costs (v_constants) ((Base.map_new ()))))))))
and (* native_plan.bend:59 *)
f_append_nodes : (M.t_Diagnostic, (D.t_Node) list) Base.result_ -> (M.t_Diagnostic, (D.t_Node) list) Base.result_ -> (M.t_Diagnostic, (D.t_Node) list) Base.result_ =
fun v_left v_right ->
(match v_left with
| Fail __error -> Fail __error
| Done v_a ->
(match v_right with
| Fail __error -> Fail __error
| Done v_b ->
(Done ((Base.list_append (v_a) (v_b))))))
and (* native_plan.bend:65 *)
f_merge : t_Scanned -> t_ScannedGraph -> t_ScannedGraph =
fun v_left v_right ->
(let (Scanned (v_functions, v_constants, v_costs)) = v_left in
(let (ScannedGraph (v_fs, v_cs)) = v_right in
(ScannedGraph ((f_append_nodes (v_functions) (v_fs)), (f_append_nodes (v_constants) (v_cs))))))
and (* native_plan.bend:70 *)
f_combine : (t_Scanned) list -> t_ScannedGraph =
fun v_scans ->
(match v_scans with
| [] ->
(ScannedGraph ((Done ([])), (Done ([]))))
| (v_head :: v_tail) ->
(f_merge (v_head) ((f_combine (v_tail)))))
and (* native_plan.bend:77 *)
f_scanned_graph : t_ScannedGraph -> (M.t_Diagnostic, (D.t_Node) list) Base.result_ =
fun v_scanned ->
(let (ScannedGraph (v_functions, v_constants)) = v_scanned in
(match (f_append_nodes (v_functions) (v_constants)) with
| Fail __error -> Fail __error
| Done v_nodes ->
(match (Check.f_unique_lambdas ((Check.f_lambda_ids (v_nodes)))) with
| Fail __error -> Fail __error
| Done v_unique ->
(Done (v_nodes)))))
and (* native_plan.bend:84 *)
f_graph : M.t_Module -> (t_Scanned) list -> (M.t_Diagnostic, (D.t_Node) list) Base.result_ =
fun v_module v_scans ->
(match (Check.f_validate_module (v_module)) with
| Fail __error -> Fail __error
| Done v_valid ->
(f_scanned_graph ((f_combine (v_scans)))))
and (* native_plan.bend:89 *)
f_collect_costs : (t_Scanned) list -> (int) Base.map -> (int) Base.map =
fun v_scans v_found ->
(match v_scans with
| [] ->
v_found
| ((Scanned (v_functions, v_constants, v_costs)) :: v_tail) ->
(f_collect_costs (v_tail) ((Base.map_union (v_found) (v_costs)))))
