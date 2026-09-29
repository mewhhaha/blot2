(* Native semantic port of compiler/raw_core_qualification.bend.

   Source SHA-256: 8392ee0497067a630a0e457af27deeea1392ec148ed4ecf35dc2ba47585299d8

   Ownership/type arguments are erased; value types are checked by OCaml.

   No Bend interpreter or generated C/JavaScript is linked. *)

open Base

module M = Ox_model

module Closures = Ox_closures

let s_0 = Base.text_of_utf8 "expression_complexity"

let s_1 = Base.text_of_utf8 "raw_core"

let s_2 = Base.text_of_utf8 "qualified core scan exceeded its work limit"

let s_3 = Base.text_of_utf8 "unspecialized_qualified"

let s_4 = Base.text_of_utf8 "offset:"

let s_5 = Base.text_of_utf8 "raw core with a nonempty where clause requires evidence elaboration through the source compiler"

let rec (* raw_core_qualification.bend:9 *)
f_scan_body : int -> (M.t_Expr) list -> (M.t_Diagnostic, unit) Base.result_ =
fun v_fuel v_pending ->
(match (v_fuel, v_pending) with
| (_, []) ->
(Done (()))
| (0, _) ->
(Fail ((M.Diagnostic (s_0, s_1, s_2))))
| (__nat_1, ((M.QualifiedExpr (v_offset, v_annotation, (_ :: _), v_value)) :: v_tail)) when __nat_1 >= 1 ->
(let v_rest = (__nat_1 - 1) in
(Fail ((M.Diagnostic (s_3, (Base.string_append s_4 (Base.nat_show (v_offset))), s_5)))))
| (__nat_2, (v_expression :: v_tail)) when __nat_2 >= 1 ->
(let v_rest = (__nat_2 - 1) in
(f_scan_body (v_rest) ((Base.list_reverse_go ((Base.list_reverse ((Closures.f_children (v_expression))))) (v_tail))))))
and (* raw_core_qualification.bend:20 *)
f_scan_constants : (M.t_Constant) list -> (M.t_Diagnostic, unit) Base.result_ =
fun v_values ->
(match v_values with
| [] ->
(Done (()))
| ((M.Constant (v_name, v_exported, v_annotation, v_value)) :: v_following) ->
(match (f_scan_body (1048576) ([v_value])) with
| Fail __error -> Fail __error
| Done v_checked ->
(f_scan_constants (v_following))))
and (* raw_core_qualification.bend:29 *)
f_scan_functions : (M.t_Function) list -> (M.t_Diagnostic, unit) Base.result_ =
fun v_values ->
(match v_values with
| [] ->
(Done (()))
| ((M.Function (v_name, v_exported, v_parameter, v_p, v_r, v_body)) :: v_following) ->
(match (f_scan_body (1048576) ([v_body])) with
| Fail __error -> Fail __error
| Done v_checked ->
(f_scan_functions (v_following))))
and (* raw_core_qualification.bend:38 *)
f_check : M.t_Module -> (M.t_Diagnostic, unit) Base.result_ =
fun v_module ->
(let (M.Module (v_constants, v_functions, v_data_types, v_operations)) = v_module in
(match (f_scan_constants (v_constants)) with
| Fail __error -> Fail __error
| Done v_checked ->
(f_scan_functions (v_functions))))
