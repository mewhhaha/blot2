(* Native semantic port of compiler/main.bend.

   Source SHA-256: 97744ce9fdb86b7d422650fe81a8a6243ded4f07cb1598864d35d3d014606b80

   Ownership/type arguments are erased; value types are checked by OCaml.

   No Bend interpreter or generated C/JavaScript is linked. *)

open Base

module M = Ox_model

module Check = Ox_check

module CheckScheduler = Ox_check_scheduler

module Const = Ox_const_eval

module Wasm = Ox_wasm

module SourceModules = Ox_source_modules

module Groups = Ox_groups

module Cst = Ox_cst

module Public = Ox_public_exports

module Core = Ox_checked_core

module Entries = Ox_entry_points

module RawQualification = Ox_raw_core_qualification

type t_Analysis =
  | Analysis of M.t_CheckedModule * ((Const.t_Value) Const.t_Binding) list * int
and t_Artifact =
  | Artifact of t_Analysis * (int32) list
and t_PlannedArtifact =
  | PlannedArtifact of t_Analysis * Wasm.t_BytePlan

let s_0 = Base.text_of_utf8 "source_project"

let rec (* main.bend:24 *)
f_checked_functions : M.t_CheckedModule -> (M.t_CheckedFunction) list =
fun v_checked ->
(let (M.CheckedModule (v_constants, v_functions, v_data_types, v_operations)) = v_checked in
v_functions)
and (* main.bend:28 *)
f_checked_constants : M.t_CheckedModule -> (M.t_CheckedConstant) list =
fun v_checked ->
(let (M.CheckedModule (v_constants, v_functions, v_data_types, v_operations)) = v_checked in
v_constants)
and (* main.bend:32 *)
f_const_context : M.t_Module -> M.t_CheckedModule -> Const.t_Context =
fun v_module v_checked ->
(let (M.Module (v_constants, v_functions, v_data_types, v_operations)) = v_module in
(Const.Context (v_constants, v_functions, [], v_data_types, [], (f_checked_functions (v_checked)))))
and (* main.bend:36 *)
f_finish_analysis : M.t_CheckedModule -> Const.t_Constants -> t_Analysis =
fun v_checked v_constants ->
(let (Const.Constants (v_bindings, v_remaining)) = v_constants in
(Analysis (v_checked, v_bindings, v_remaining)))
and (* main.bend:40 *)
f_analyze : M.t_Module -> int -> (M.t_Diagnostic, t_Analysis) Base.result_ =
fun v_module v_steps ->
(match (CheckScheduler.f_check_module (v_module)) with
| Fail __error -> Fail __error
| Done v_checked ->
(match (RawQualification.f_check (v_module)) with
| Fail __error -> Fail __error
| Done v_qualified ->
(match (Const.f_evaluate_constants ((f_checked_constants (v_checked))) (v_steps) ((f_const_context (v_module) (v_checked)))) with
| Fail __error -> Fail __error
| Done v_constants ->
(Done ((f_finish_analysis (v_checked) (v_constants)))))))
and (* main.bend:47 *)
f_analysis_checked : t_Analysis -> M.t_CheckedModule =
fun v_analysis ->
(let (Analysis (v_checked, v_constants, v_remaining_steps)) = v_analysis in
v_checked)
and (* main.bend:51 *)
f_analysis_constants : t_Analysis -> ((Const.t_Value) Const.t_Binding) list =
fun v_analysis ->
(let (Analysis (v_checked, v_constants, v_remaining_steps)) = v_analysis in
v_constants)
and (* main.bend:55 *)
f_compile_plan : M.t_Module -> int -> (M.t_Diagnostic, t_PlannedArtifact) Base.result_ =
fun v_module v_steps ->
(match (f_analyze (v_module) (v_steps)) with
| Fail __error -> Fail __error
| Done v_analysis ->
(match (Wasm.f_emit_plan ((f_analysis_checked (v_analysis))) ((f_analysis_constants (v_analysis)))) with
| Fail __error -> Fail __error
| Done v_bytes ->
(Done ((PlannedArtifact (v_analysis, v_bytes))))))
and (* main.bend:61 *)
f_flatten_artifact : t_PlannedArtifact -> t_Artifact =
fun v_artifact ->
(let (PlannedArtifact (v_analysis, v_bytes)) = v_artifact in
(Artifact (v_analysis, (Wasm.f_plan_finish (v_bytes)))))
and (* main.bend:65 *)
f_compile : M.t_Module -> int -> (M.t_Diagnostic, t_Artifact) Base.result_ =
fun v_module v_steps ->
(match (f_compile_plan (v_module) (v_steps)) with
| Fail __error -> Fail __error
| Done v_artifact ->
(Done ((f_flatten_artifact (v_artifact)))))
and (* main.bend:75 *)
f_analyze_source : Cst.t_Cst -> Cst.t_Cst -> int -> int -> (M.t_Diagnostic, t_Analysis) Base.result_ =
fun v_root v_prelude v_fuel v_steps ->
(match (SourceModules.f_source_module_core ((M.f_name_equal ((Cst.f_kind_of (v_root))) (s_0))) (v_root) (v_prelude) (v_fuel)) with
| Fail __error -> Fail __error
| Done v_sourced ->
(let v_prepared = (SourceModules.f_sourced_prepared (v_sourced)) in
(match (CheckScheduler.f_check_module_core ((Core.f_prepared_module (v_prepared))) ((Core.f_prepared_certificates (v_prepared)))) with
| Fail __error -> Fail __error
| Done v_inferred ->
(let v_checked = (Public.f_select_checked (v_inferred)) in
(match (Entries.f_verify ((SourceModules.f_sourced_entries (v_sourced))) (v_checked)) with
| Fail __error -> Fail __error
| Done v_valid ->
(let v_raw = (Public.f_unchecked_module (v_checked)) in
(match (Const.f_evaluate_constants ((f_checked_constants (v_checked))) (v_steps) ((f_const_context (v_raw) (v_checked)))) with
| Fail __error -> Fail __error
| Done v_constants ->
(Done ((f_finish_analysis (v_checked) (v_constants)))))))))))
and (* main.bend:86 *)
f_compile_source : Cst.t_Cst -> Cst.t_Cst -> int -> int -> (M.t_Diagnostic, t_Artifact) Base.result_ =
fun v_root v_prelude v_fuel v_steps ->
(match (f_analyze_source (v_root) (v_prelude) (v_fuel) (v_steps)) with
| Fail __error -> Fail __error
| Done v_analysis ->
(match (Entries.f_require_exports ((f_analysis_checked (v_analysis)))) with
| Fail __error -> Fail __error
| Done v_exports ->
(match (Wasm.f_emit_plan ((f_analysis_checked (v_analysis))) ((f_analysis_constants (v_analysis)))) with
| Fail __error -> Fail __error
| Done v_bytes ->
(Done ((f_flatten_artifact ((PlannedArtifact (v_analysis, v_bytes)))))))))
and (* main.bend:93 *)
f_compile_source_plan : Cst.t_Cst -> Cst.t_Cst -> int -> int -> (M.t_Diagnostic, t_PlannedArtifact) Base.result_ =
fun v_root v_prelude v_fuel v_steps ->
(match (f_analyze_source (v_root) (v_prelude) (v_fuel) (v_steps)) with
| Fail __error -> Fail __error
| Done v_analysis ->
(match (Entries.f_require_exports ((f_analysis_checked (v_analysis)))) with
| Fail __error -> Fail __error
| Done v_exports ->
(match (Wasm.f_emit_plan ((f_analysis_checked (v_analysis))) ((f_analysis_constants (v_analysis)))) with
| Fail __error -> Fail __error
| Done v_bytes ->
(Done ((PlannedArtifact (v_analysis, v_bytes)))))))
