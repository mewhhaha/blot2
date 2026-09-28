(* Native semantic port of compiler/monomorph.bend.

   Source SHA-256: 4c740b7d7b05f9db40cf3fc7b1b0cbc717f58a5b1ac912e2c005689d0c49e917

   Ownership/type arguments are erased; value types are checked by OCaml.

   No Bend interpreter or generated C/JavaScript is linked. *)

open Base

module M = Ox_model

module F = Ox_closures

module D = Ox_dependency

module I = Ox_infer

module G = Ox_globals

module T = Ox_types

module C = Ox_constraints

module Rows = Ox_effect_rows

module Check = Ox_check

module Scheduler = Ox_check_scheduler

module Index = Ox_index

module State = Ox_state_specialize

module Batch = Ox_inference_batch

module Public = Ox_public_exports

module Members = Ox_members

module Core = Ox_checked_core

module Groups = Ox_groups

module TD = Ox_type_data

module Staging = Ox_staging_scheme

module Schema = Ox_schema_stage

module StateEvidence = Ox_state_run_evidence

module ScopedStateEvidence = Ox_state_scoped_evidence

module TypeEq = Ox_type_eq_evidence

module SelectedBindingEvidence = Ox_selected_binding_evidence

module Compare = Ox_core_compare

module Bindings = Ox_global_bindings

module ParallelInfer = Ox_parallel_infer

module Entries = Ox_entry_points

type t_Rename =
  | Rename of Base.text * Base.text
and t_LocalTemplate =
  | LocalTemplate of Base.text * M.t_Expr
and t_MemberEvidenceCertificate =
  | MemberEvidenceCertificate of Base.text * M.t_Ty
and t_MemberRowProof =
  | MemberRowProof of I.t_State * (t_MemberEvidenceCertificate) list
and t_Configuration =
  | Configuration of (M.t_Function) list * (Base.text) list * Base.text * (t_LocalTemplate) list * (Base.text) list * int * (M.t_Constant) list * (M.t_Operation) list * int * (Schema.t_Evidence) list
and t_Expansion =
  | Expansion of (M.t_Expr) list * (M.t_Function) list * (M.t_Constant) list * int
and t_BinaryCall =
  | BinaryCall of Base.text * (M.t_TypeId) list * M.t_Expr * M.t_Expr
and t_BinaryMember =
  | BinaryMember of Base.text * (M.t_TypeId) list
and t_ExpandWork =
  | Expression of M.t_Expr
  | Expressions of (M.t_Expr) list
  | Reference of Base.text * bool * (Base.text) option
  | Clone of M.t_Function
  | LocalValue of Base.text * (M.t_Expr) option
  | ConstantValue of Base.text * (M.t_Expr) option
  | ConstantReference of Base.text * (M.t_Constant) option * (Base.text) option
  | LetValue of Base.text * M.t_Expr * M.t_Expr * bool
  | Application of M.t_Expr * M.t_Expr * (t_BinaryCall) option
and t_ExpandedModule =
  | ExpandedModule of M.t_Module * int * (I.t_Binding) list * (Core.t_Certificate) list
and t_StagedSplit =
  | StagedSplit of (G.t_Declaration) list * (G.t_Declaration) option * (G.t_Declaration) list
and t_StagedWork =
  | StageDeclarations of (G.t_Declaration) list * G.t_Environment
  | StageSplit of t_StagedSplit * G.t_Environment
  | StageBarrier of (G.t_Declaration) option * (G.t_Declaration) list * G.t_Environment
and t_Choice =
  | FunctionChoice of Base.text * M.t_Ty
  | ReceiverChoice of Base.text * M.t_Ty
  | OperationChoice of M.t_TypeId * M.t_Ty
  | QualifiedChoice of (M.t_Predicate) list * (C.t_EvidenceAnswer) list
and t_Specialization =
  | Specialization of M.t_Module * G.t_Environment * (t_Choice) Base.map * int * (Core.t_Certificate) list
and t_FieldEvidence =
  | FieldEvidence of G.t_Environment * (Core.t_Certificate) list
and t_StateSource =
  | StateSource of M.t_TypeId * M.t_TypeId * (M.t_Operation) list
and t_SolveWork =
  | Needs of (I.t_Coverage) list
  | Operation of I.t_Coverage * (M.t_Ty) list * bool * bool * (I.t_Coverage) list
  | Need of I.t_Coverage * M.t_Ty * M.t_Ty * bool * bool * (I.t_Coverage) list
  | Qualified of M.t_Predicate * M.t_Predicate * int * Base.text * bool * bool * (I.t_Coverage) list
  | Selected of (t_Specialization) option * (I.t_Coverage) list
and t_PendingCache =
  | PendingCache of int * (I.t_Coverage) list
and t_FreshWork =
  | FreshWork of int * (I.t_Definition) list
and t_BoundaryCoverage =
  | BoundaryCoverage of (I.t_Coverage) list * int * bool
and t_BoundaryDefinitions =
  | BoundaryDefinitions of (I.t_Definition) list * int * bool
and t_BoundaryProgress =
  | BoundaryProgress of t_Specialization * bool
and t_BoundaryLoop =
  | CheckBoundaries of t_Specialization * bool
  | ContinueBoundaries of t_BoundaryProgress * bool
and t_SpecializationTask =
  | SpecializationTask of G.t_Declaration * int
and t_SpecializationContext =
  | SpecializationContext of t_Configuration * (I.t_Binding) list * (M.t_DataType) list * (M.t_Operation) list * (Staging.t_Scheme) list * (M.t_Diagnostic, int) Base.result_
and t_CachedTask =
  | CachedTask of int * Base.text * (Base.text) list * t_ExpandedModule
and t_Cache =
  | Cache of (int32) list * (t_CachedTask) list * ((int32) list) Base.map * (Core.t_Certificate) list
and t_Reusable =
  | Reusable of (t_CachedTask) list * ((int32) list) Base.map
and t_Prepared =
  | Prepared of M.t_Module * t_Cache * (Core.t_Certificate) list
and t_CachedExpansion =
  | CachedExpansion of t_ExpandedModule * (t_CachedTask) list
and t_TaskRun =
  | ReusedTask of t_CachedTask
  | NewTask of t_SpecializationTask * (Base.text) list
and t_SharedConstants =
  | SharedConstants of M.t_Module * (I.t_Binding) list * (Base.text) list * int * (Core.t_Certificate) list

let s_0 = Base.text_of_utf8 "internal_error"

let s_1 = Base.text_of_utf8 "monomorphization"

let s_2 = Base.text_of_utf8 "lost an expression during specialization"

let s_3 = Base.text_of_utf8 "unknown_function"

let s_4 = Base.text_of_utf8 "missing function during specialization"

let s_5 = Base.text_of_utf8 "$mono["

let s_6 = Base.text_of_utf8 "]"

let s_7 = Base.text_of_utf8 "expression children differ from their parent"

let s_8 = Base.text_of_utf8 "specialization_limit"

let s_9 = Base.text_of_utf8 "specialization exceeded its structural limit"

let s_10 = Base.text_of_utf8 "]."

let s_11 = Base.text_of_utf8 ""

let s_12 = Base.text_of_utf8 "staging"

let s_13 = Base.text_of_utf8 "staged inference traversal limit"

let s_14 = Base.text_of_utf8 "std/prelude"

let s_15 = Base.text_of_utf8 "$prelude."

let s_16 = Base.text_of_utf8 "$module["

let s_17 = Base.text_of_utf8 "$prelude.U32"

let s_18 = Base.text_of_utf8 "$prelude.F32"

let s_19 = Base.text_of_utf8 "$prelude.Bool"

let s_20 = Base.text_of_utf8 "$prelude.Unit"

let s_21 = Base.text_of_utf8 "$prelude.Array"

let s_22 = Base.text_of_utf8 "."

let s_23 = Base.text_of_utf8 "unknown_associated_type"

let s_24 = Base.text_of_utf8 "operand type is not yet known"

let s_25 = Base.text_of_utf8 "no named implementation"

let s_26 = Base.text_of_utf8 "missing_associated"

let s_27 = Base.text_of_utf8 "; right: "

let s_28 = Base.text_of_utf8 "; left: "

let s_29 = Base.text_of_utf8 "q"

let s_30 = Base.text_of_utf8 "selected field has no nominal owner"

let s_31 = Base.text_of_utf8 "qualified selection did not produce matching evidence"

let s_32 = Base.text_of_utf8 "ambiguous_qualified"

let s_33 = Base.text_of_utf8 "selected evidence still has unconstrained type or effect variables"

let s_34 = Base.text_of_utf8 "expected a representation predicate"

let s_35 = Base.text_of_utf8 "specialized reference is not a function"

let s_36 = Base.text_of_utf8 "no compatible "

let s_37 = Base.text_of_utf8 " for "

let s_38 = Base.text_of_utf8 " and "

let s_39 = Base.text_of_utf8 "selection expected an associated requirement"

let s_40 = Base.text_of_utf8 "missing_member"

let s_41 = Base.text_of_utf8 "no associated member "

let s_42 = Base.text_of_utf8 "ambiguous_associated"

let s_43 = Base.text_of_utf8 "member access requires an inferred receiver type"

let s_44 = Base.text_of_utf8 "member"

let s_45 = Base.text_of_utf8 "selection expected a receiver requirement"

let s_46 = Base.text_of_utf8 "$schema.receiver"

let s_47 = Base.text_of_utf8 "$schema.witness"

let s_48 = Base.text_of_utf8 "$schema["

let s_49 = Base.text_of_utf8 "$member["

let s_50 = Base.text_of_utf8 "field"

let s_51 = Base.text_of_utf8 "selection expected a field requirement"

let s_52 = Base.text_of_utf8 "$member.set["

let s_53 = Base.text_of_utf8 "ambiguous_member"

let s_54 = Base.text_of_utf8 "field and associated function share the name "

let s_55 = Base.text_of_utf8 "missing_field"

let s_56 = Base.text_of_utf8 "no writable field "

let s_57 = Base.text_of_utf8 " on "

let s_58 = Base.text_of_utf8 "selection expected a member requirement"

let s_59 = Base.text_of_utf8 "unknown_effect"

let s_60 = Base.text_of_utf8 "no declared effect operation matches this family member"

let s_61 = Base.text_of_utf8 "<"

let s_62 = Base.text_of_utf8 ">"

let s_63 = Base.text_of_utf8 "type_arity"

let s_64 = Base.text_of_utf8 "effect operation has the wrong number of type arguments"

let s_65 = Base.text_of_utf8 "generic effect requires a template declaration"

let s_66 = Base.text_of_utf8 "effect"

let s_67 = Base.text_of_utf8 "generic effect bridge expected a concrete operation"

let s_68 = Base.text_of_utf8 "effect_arity"

let s_69 = Base.text_of_utf8 "generic effect bridge received the wrong number of operation members"

let s_70 = Base.text_of_utf8 "$state["

let s_71 = Base.text_of_utf8 "state"

let s_72 = Base.text_of_utf8 "selection expected a typed state requirement"

let s_73 = Base.text_of_utf8 "selection expected a generic operation requirement"

let s_74 = Base.text_of_utf8 "$type.left"

let s_75 = Base.text_of_utf8 "$type.right"

let s_76 = Base.text_of_utf8 "$type["

let s_77 = Base.text_of_utf8 "].same"

let s_78 = Base.text_of_utf8 "@type.same"

let s_79 = Base.text_of_utf8 "selection expected a type comparison requirement"

let s_80 = Base.text_of_utf8 "selection expected a deferred requirement"

let s_81 = Base.text_of_utf8 "qualified"

let s_82 = Base.text_of_utf8 "selected binary implementation has no curried signature"

let s_83 = Base.text_of_utf8 "selected receiver implementation has no function signature"

let s_84 = Base.text_of_utf8 "qualified selector has no matching exact implementation"

let s_85 = Base.text_of_utf8 "no field "

let s_86 = Base.text_of_utf8 "ambiguous_effect"

let s_87 = Base.text_of_utf8 "cannot infer type arguments for "

let s_88 = Base.text_of_utf8 "; constrain its argument or result, or supply explicit type arguments"

let s_89 = Base.text_of_utf8 "cannot select "

let s_90 = Base.text_of_utf8 " until operand types can be inferred; annotate the exported parameter or call the generic function with concrete types"

let s_91 = Base.text_of_utf8 "cannot select this qualified requirement until its type and effect arguments are concrete"

let s_92 = Base.text_of_utf8 "invalid deferred constraint"

let s_93 = Base.text_of_utf8 "too many associated specializations"

let s_94 = Base.text_of_utf8 "$associated.left"

let s_95 = Base.text_of_utf8 "$associated.right"

let s_96 = Base.text_of_utf8 "unresolved associated call after specialization"

let s_97 = Base.text_of_utf8 "unresolved generic operation after specialization"

let s_98 = Base.text_of_utf8 "replacement exceeded its structural limit"

let s_99 = Base.text_of_utf8 "unexpected replacement work"

let s_100 = Base.text_of_utf8 "effect_mismatch"

let s_101 = Base.text_of_utf8 "qualified invocation effects differ from selected implementation"

let s_102 = Base.text_of_utf8 "qualified invocation effects remain open after selection"

let s_103 = Base.text_of_utf8 "selected implementation effects remain open"

let s_104 = Base.text_of_utf8 "associated"

let s_105 = Base.text_of_utf8 "ordinary call has no matching selected implementation"

let s_106 = Base.text_of_utf8 "associated qualifier has no selected function evidence"

let s_107 = Base.text_of_utf8 "update qualifier has no selected field evidence"

let s_108 = Base.text_of_utf8 "receiver qualifier has no selected member evidence"

let s_109 = Base.text_of_utf8 "qualified requirement has no selected evidence"

let s_110 = Base.text_of_utf8 "ordinary invocation retains an unresolved source effect row"

let s_111 = Base.text_of_utf8 "selected implementation retains an unresolved source effect row"

let s_112 = Base.text_of_utf8 "invocation effects differ from selected implementation"

let s_113 = Base.text_of_utf8 "Type"

let s_114 = Base.text_of_utf8 "eq"

let s_115 = Base.text_of_utf8 "selected source binding"

let s_116 = Base.text_of_utf8 "no scoped source scheme certificate"

let s_117 = Base.text_of_utf8 "qualified boundary identity space exhausted"

let s_118 = Base.text_of_utf8 "qualified boundary"

let s_119 = Base.text_of_utf8 "qualified boundary fixed point exceeded its limit"

let s_120 = Base.text_of_utf8 "type_complexity"

let s_121 = Base.text_of_utf8 "effects"

let s_122 = Base.text_of_utf8 "selected signature is too complex"

let s_123 = Base.text_of_utf8 "selected invocation"

let s_124 = Base.text_of_utf8 "selected member has no unqualified body signature for recheck"

let s_125 = Base.text_of_utf8 "selected member"

let s_126 = Base.text_of_utf8 "no generated body owns the selected effect row"

let s_127 = Base.text_of_utf8 "body recheck constrained a retained full signature"

let s_128 = Base.text_of_utf8 "checked binding and definition have different full signatures"

let s_129 = Base.text_of_utf8 "checked member lacks a unique unqualified original binding"

let s_130 = Base.text_of_utf8 "checked member identity is not unique"

let s_131 = Base.text_of_utf8 "selected row has an unverified generated binding"

let s_132 = Base.text_of_utf8 "module identity scan exceeded its limit"

let s_133 = Base.text_of_utf8 "@affected"

let s_134 = Base.text_of_utf8 "@schema.evidence"

let s_135 = Base.text_of_utf8 "specialization task outcome count mismatch"

let s_136 = Base.text_of_utf8 "$member"

let rec (* monomorph.bend:68 *)
f_expressions : t_Expansion -> (M.t_Expr) list =
fun v_value ->
(let (Expansion (v_expressions, v_functions, v_constants, v_next)) = v_value in
v_expressions)
and (* monomorph.bend:72 *)
f_functions : t_Expansion -> (M.t_Function) list =
fun v_value ->
(let (Expansion (v_expressions, v_functions, v_constants, v_next)) = v_value in
v_functions)
and (* monomorph.bend:76 *)
f_next : t_Expansion -> int =
fun v_value ->
(let (Expansion (v_expressions, v_functions, v_constants, v_next)) = v_value in
v_next)
and (* monomorph.bend:80 *)
f_emitted_constants : t_Expansion -> (M.t_Constant) list =
fun v_value ->
(let (Expansion (v_expressions, v_functions, v_constants, v_next)) = v_value in
v_constants)
and (* monomorph.bend:84 *)
f_one : (M.t_Expr) list -> (M.t_Diagnostic, M.t_Expr) Base.result_ =
fun v_values ->
(match v_values with
| (v_head :: []) ->
(Done (v_head))
| _ ->
(Fail ((M.Diagnostic (s_0, s_1, s_2)))))
and (* monomorph.bend:91 *)
f_renamed_work : (t_Rename) list -> Base.text -> (Base.text) option -> (Base.text) option =
fun v_names v_wanted v_found ->
(match (v_names, v_found) with
| (_, (Some (v_specialized))) ->
(Some (v_specialized))
| ([], None) ->
None
| (((Rename (v_original, v_specialized)) :: v_tail), None) ->
(f_renamed_work (v_tail) (v_wanted) ((Base.bool_pick ((M.f_name_equal (v_original) (v_wanted))) ((Some (v_specialized))) (None)))))
and (* monomorph.bend:100 *)
f_renamed : (t_Rename) list -> Base.text -> (Base.text) option =
fun v_names v_wanted ->
(f_renamed_work (v_names) (v_wanted) (None))
and (* monomorph.bend:103 *)
f_lookup_work : (M.t_Function) list -> Base.text -> (M.t_Function) option -> (M.t_Diagnostic, M.t_Function) Base.result_ =
fun v_functions v_wanted v_found ->
(match (v_functions, v_found) with
| (_, (Some (v_function))) ->
(Done (v_function))
| ([], None) ->
(Fail ((M.Diagnostic (s_3, v_wanted, s_4))))
| (((M.Function (v_name, v_exported, v_parameter, v_p, v_r, v_body)) :: v_tail), None) ->
(f_lookup_work (v_tail) (v_wanted) ((Base.bool_pick ((M.f_name_equal (v_name) (v_wanted))) ((Some ((M.Function (v_name, v_exported, v_parameter, v_p, v_r, v_body))))) (None)))))
and (* monomorph.bend:112 *)
f_lookup : (M.t_Function) list -> Base.text -> (M.t_Diagnostic, M.t_Function) Base.result_ =
fun v_functions v_wanted ->
(f_lookup_work (v_functions) (v_wanted) (None))
and (* monomorph.bend:115 *)
f_lookup_constant_work : (M.t_Constant) list -> Base.text -> (M.t_Constant) option -> (M.t_Constant) option =
fun v_constants v_wanted v_found ->
(match (v_constants, v_found) with
| (_, (Some (v_constant))) ->
(Some (v_constant))
| ([], None) ->
None
| (((M.Constant (v_name, v_exported, v_annotation, v_value)) :: v_tail), None) ->
(f_lookup_constant_work (v_tail) (v_wanted) ((Base.bool_pick ((M.f_name_equal (v_name) (v_wanted))) ((Some ((M.Constant (v_name, v_exported, v_annotation, v_value))))) (None)))))
and (* monomorph.bend:124 *)
f_lookup_constant : (M.t_Constant) list -> Base.text -> (M.t_Constant) option =
fun v_constants v_wanted ->
(f_lookup_constant_work (v_constants) (v_wanted) (None))
and (* monomorph.bend:127 *)
f_has_deferred : int -> (M.t_Expr) list -> bool =
fun v_fuel v_pending ->
(match (v_fuel, v_pending) with
| (_, []) ->
false
| (0, _) ->
true
| (__nat_1, ((M.AssociatedExpr (v_identity, v_dispatch, v_member, v_templates, v_left, v_right)) :: v_tail)) when __nat_1 >= 1 ->
(let v_rest = (__nat_1 - 1) in
true)
| (__nat_2, ((M.GenericOperationExpr (v_identity, v_template, v_arguments)) :: v_tail)) when __nat_2 >= 1 ->
(let v_rest = (__nat_2 - 1) in
true)
| (__nat_3, ((M.QualifiedExpr (v_offset, v_annotation, v_predicates, v_value)) :: v_tail)) when __nat_3 >= 1 ->
(let v_rest = (__nat_3 - 1) in
true)
| (__nat_4, (v_head :: v_tail)) when __nat_4 >= 1 ->
(let v_rest = (__nat_4 - 1) in
(f_has_deferred (v_rest) ((Base.list_reverse_go ((Base.list_reverse ((F.f_children (v_head))))) (v_tail))))))
and (* monomorph.bend:142 *)
f_seeds : (M.t_Function) list -> (Base.text) list =
fun v_functions ->
(match v_functions with
| [] ->
[]
| ((M.Function (v_name, v_exported, v_parameter, v_p, v_r, v_body)) :: v_tail) ->
(let v_rest = (f_seeds (v_tail)) in
(Base.bool_pick ((f_has_deferred (65536) ([v_body]))) ((v_name :: v_rest)) (v_rest))))
and (* monomorph.bend:150 *)
f_constant_seeds : (M.t_Constant) list -> (Base.text) list =
fun v_constants ->
(match v_constants with
| [] ->
[]
| ((M.Constant (v_name, v_exported, v_annotation, v_value)) :: v_tail) ->
(let v_rest = (f_constant_seeds (v_tail)) in
(Base.bool_pick ((f_has_deferred (65536) ([v_value]))) ((v_name :: v_rest)) (v_rest))))
and (* monomorph.bend:161 *)
f_closure_found : (M.t_Diagnostic, D.t_Reachability) Base.result_ -> (Base.text) list -> (Base.text) list =
fun v_found v_names ->
(match v_found with
| (Done (v_reached)) ->
(Base.list_reverse ((D.f_reached_members (v_reached))))
| (Fail (v_diagnostic)) ->
v_names)
and (* monomorph.bend:168 *)
f_template_closure : (D.t_Node) list -> (Base.text) list -> (Base.text) list =
fun v_nodes v_seeds ->
(let v_names = (D.f_node_names (v_nodes)) in
(f_closure_found ((D.f_reachable ((Base.nat_add 1 (Base.nat_add ((Base.list_length (v_names))) ((D.f_edge_count (v_nodes)))))) (v_seeds) ((D.f_transpose (v_nodes) ((Base.map_new ())))) ((Base.set_from_list (v_names))) ((Base.set_new ())) ([]))) (v_names)))
and (* monomorph.bend:172 *)
f_rebuild_arms : ((M.t_Expr) M.t_MatchArm) list -> (M.t_Expr) list -> ((M.t_Expr) M.t_MatchArm) list =
fun v_arms v_bodies ->
(match (v_arms, v_bodies) with
| (((M.MatchArm (v_patterns, v_old)) :: v_tail), (v_body :: v_remaining)) ->
((M.MatchArm (v_patterns, v_body)) :: (f_rebuild_arms (v_tail) (v_remaining)))
| (_, _) ->
[])
and (* monomorph.bend:180 *)
f_identity : int -> int -> int =
fun v_base v_original ->
(Base.nat_add (v_base) (v_original))
and (* monomorph.bend:183 *)
f_relocate_annotation : (M.t_Ty) option -> int -> (M.t_Diagnostic, (M.t_Ty) option) Base.result_ =
fun v_annotation v_base ->
(match (v_annotation, v_base) with
| (v_annotation, 0) ->
(Done (v_annotation))
| (None, _) ->
(Done (None))
| ((Some (v_ty)), _) ->
(match (T.f_rewrite (65536) ((T.OneType (v_ty))) ((T.RelocateFree ((Base.string_append s_5 (Base.string_append (Base.nat_show (v_base)) s_6)))))) with
| Fail __error -> Fail __error
| Done v_types ->
(match (T.f_first_type (v_types)) with
| Fail __error -> Fail __error
| Done v_relocated ->
(Done ((Some (v_relocated)))))))
and (* monomorph.bend:195 *)
f_relocate_arguments : (M.t_Ty) list -> int -> (M.t_Diagnostic, (M.t_Ty) list) Base.result_ =
fun v_arguments v_base ->
(match v_base with
| 0 ->
(Done (v_arguments))
| v_base ->
(T.f_rewrite (65536) ((T.ManyTypes (v_arguments))) ((T.RelocateFree ((Base.string_append s_5 (Base.string_append (Base.nat_show (v_base)) s_6)))))))
and (* monomorph.bend:202 *)
f_relocate_predicates : (M.t_Predicate) list -> int -> (M.t_Diagnostic, (M.t_Predicate) list) Base.result_ =
fun v_predicates v_base ->
(match v_base with
| 0 ->
(Done (v_predicates))
| v_base ->
(C.f_relocate_free (v_predicates) ((Base.string_append s_5 (Base.string_append (Base.nat_show (v_base)) s_6)))))
and (* monomorph.bend:209 *)
f_rebuild : M.t_Expr -> (M.t_Expr) list -> int -> (M.t_Diagnostic, M.t_Expr) Base.result_ =
fun v_original v_children v_base ->
(match (v_original, v_children) with
| ((M.ConstructExpr (v_constructor, (Some (v_payload)))), (v_a :: [])) ->
(Done ((M.ConstructExpr (v_constructor, (Some (v_a))))))
| ((M.ProductExpr (v_elements)), v_children) ->
(Done ((M.ProductExpr (v_children))))
| ((M.ArrayExpr (v_elements)), v_children) ->
(Done ((M.ArrayExpr (v_children))))
| ((M.ProjectExpr (v_value, v_index)), (v_a :: [])) ->
(Done ((M.ProjectExpr (v_a, v_index))))
| ((M.LambdaExpr (v_old, v_parameter, v_p, v_r, v_body)), (v_a :: [])) ->
(match (f_relocate_annotation (v_p) (v_base)) with
| Fail __error -> Fail __error
| Done v_parameter_type ->
(match (f_relocate_annotation (v_r) (v_base)) with
| Fail __error -> Fail __error
| Done v_result_type ->
(Done ((M.LambdaExpr ((f_identity (v_base) (v_old)), v_parameter, v_parameter_type, v_result_type, v_a))))))
| ((M.ApplyExpr (v_callee, v_argument)), (v_a :: (v_b :: []))) ->
(Done ((M.ApplyExpr (v_a, v_b))))
| ((M.TagExpr (v_offset, v_callee, v_argument)), (v_a :: (v_b :: []))) ->
(Done ((M.TagExpr (v_offset, v_a, v_b))))
| ((M.CallExpr (v_callee, v_argument)), (v_a :: [])) ->
(Done ((M.CallExpr (v_callee, v_a))))
| ((M.ScalarExpr (v_operator, v_left, v_right)), (v_a :: (v_b :: []))) ->
(Done ((M.ScalarExpr (v_operator, v_a, v_b))))
| ((M.GenericOperationExpr (v_old, v_template, v_arguments)), []) ->
(match (f_relocate_arguments (v_arguments) (v_base)) with
| Fail __error -> Fail __error
| Done v_relocated ->
(Done ((M.GenericOperationExpr ((f_identity (v_base) (v_old)), v_template, v_relocated)))))
| ((M.AssociatedExpr (v_old, v_dispatch, v_member, v_templates, v_left, v_right)), (v_a :: (v_b :: []))) ->
(Done ((M.AssociatedExpr ((f_identity (v_base) (v_old)), v_dispatch, v_member, v_templates, v_a, v_b))))
| ((M.UnaryExpr (v_operator, v_value)), (v_a :: [])) ->
(Done ((M.UnaryExpr (v_operator, v_a))))
| ((M.LetExpr (v_name, v_value, v_body)), (v_a :: (v_b :: []))) ->
(Done ((M.LetExpr (v_name, v_a, v_b))))
| ((M.UseExpr (v_name, v_value, v_body)), (v_a :: (v_b :: []))) ->
(Done ((M.UseExpr (v_name, v_a, v_b))))
| ((M.IfExpr (v_condition, v_consequent, v_alternative)), (v_a :: (v_b :: (v_c :: [])))) ->
(Done ((M.IfExpr (v_a, v_b, v_c))))
| ((M.SequenceExpr (v_first, v_next)), (v_a :: (v_b :: []))) ->
(Done ((M.SequenceExpr (v_a, v_b))))
| ((M.GuardExpr (v_pattern, v_value, v_alternative, v_body)), (v_a :: (v_b :: (v_c :: [])))) ->
(Done ((M.GuardExpr (v_pattern, v_a, v_b, v_c))))
| ((M.BlockExpr (v_label, v_body)), (v_a :: [])) ->
(Done ((M.BlockExpr ((f_identity (v_base) (v_label)), v_a))))
| ((M.ReturnExpr (v_label, v_value)), (v_a :: [])) ->
(Done ((M.ReturnExpr ((f_identity (v_base) (v_label)), v_a))))
| ((M.RuntimeInitExpr (v_value)), (v_a :: [])) ->
(Done ((M.RuntimeInitExpr (v_a))))
| ((M.SourceExpr (v_offset, v_annotation, v_value)), (v_a :: [])) ->
(match (f_relocate_annotation (v_annotation) (v_base)) with
| Fail __error -> Fail __error
| Done v_relocated ->
(Done ((M.SourceExpr (v_offset, v_relocated, v_a)))))
| ((M.QualifiedExpr (v_offset, v_annotation, v_predicates, v_value)), (v_a :: [])) ->
(match (f_relocate_arguments ([v_annotation]) (v_base)) with
| Fail __error -> Fail __error
| Done v_types ->
(match (T.f_first_type (v_types)) with
| Fail __error -> Fail __error
| Done v_relocated ->
(match (f_relocate_predicates (v_predicates) (v_base)) with
| Fail __error -> Fail __error
| Done v_requirements ->
(Done ((M.QualifiedExpr (v_offset, v_relocated, v_requirements, v_a)))))))
| ((M.InstantiationExpr (v_site, v_value)), (v_a :: [])) ->
(Done ((M.InstantiationExpr ((f_identity (v_base) (v_site)), v_a))))
| ((M.StateProviderExpr (v_read, v_write, v_initial)), (v_a :: [])) ->
(Done ((M.StateProviderExpr (v_read, v_write, v_a))))
| ((M.ProviderExpr (v_operation, v_implementation)), (v_a :: [])) ->
(Done ((M.ProviderExpr (v_operation, v_a))))
| ((M.HandleExpr (v_provider, v_body)), (v_a :: (v_b :: []))) ->
(Done ((M.HandleExpr (v_a, v_b))))
| ((M.EffectHasExpr (v_set, v_operation)), (v_a :: (v_b :: []))) ->
(Done ((M.EffectHasExpr (v_a, v_b))))
| ((M.EffectCountExpr (v_set)), (v_a :: [])) ->
(Done ((M.EffectCountExpr (v_a))))
| ((M.EffectSameExpr (v_left, v_right)), (v_a :: (v_b :: []))) ->
(Done ((M.EffectSameExpr (v_a, v_b))))
| ((M.ForExpr (v_index, v_start, v_end, v_state, v_initial, v_body)), (v_a :: (v_b :: (v_c :: (v_d :: []))))) ->
(Done ((M.ForExpr (v_index, v_a, v_b, v_state, v_c, v_d))))
| ((M.ForeverExpr (v_state, v_initial, v_body)), (v_a :: (v_b :: []))) ->
(Done ((M.ForeverExpr (v_state, v_a, v_b))))
| ((M.ArrayGenerateExpr (v_count, v_generator)), (v_a :: (v_b :: []))) ->
(Done ((M.ArrayGenerateExpr (v_a, v_b))))
| ((M.ArrayFillExpr (v_count, v_value)), (v_a :: (v_b :: []))) ->
(Done ((M.ArrayFillExpr (v_a, v_b))))
| ((M.ArrayGetExpr (v_array, v_index)), (v_a :: (v_b :: []))) ->
(Done ((M.ArrayGetExpr (v_a, v_b))))
| ((M.ArraySetExpr (v_array, v_index, v_value)), (v_a :: (v_b :: (v_c :: [])))) ->
(Done ((M.ArraySetExpr (v_a, v_b, v_c))))
| ((M.ArrayLengthExpr (v_array)), (v_a :: [])) ->
(Done ((M.ArrayLengthExpr (v_a))))
| ((M.MatchExpr (v_values, v_arms)), v_children) ->
(Done ((M.MatchExpr ((Base.list_take (v_children) ((Base.list_length (v_values)))), (f_rebuild_arms (v_arms) ((Base.list_drop (v_children) ((Base.list_length (v_values))))))))))
| (v_original, []) ->
(Done (v_original))
| (_, _) ->
(Fail ((M.Diagnostic (s_0, s_1, s_7)))))
and (* monomorph.bend:301 *)
f_local_template_work : (t_LocalTemplate) list -> Base.text -> (M.t_Expr) option -> (M.t_Expr) option =
fun v_locals v_wanted v_found ->
(match (v_locals, v_found) with
| (_, (Some (v_value))) ->
(Some (v_value))
| ([], None) ->
None
| (((LocalTemplate (v_name, v_value)) :: v_tail), None) ->
(f_local_template_work (v_tail) (v_wanted) ((Base.bool_pick ((M.f_name_equal (v_name) (v_wanted))) ((Some (v_value))) (None)))))
and (* monomorph.bend:310 *)
f_local_template : (t_LocalTemplate) list -> Base.text -> (M.t_Expr) option =
fun v_locals v_wanted ->
(f_local_template_work (v_locals) (v_wanted) (None))
and (* monomorph.bend:313 *)
f_template_value : int -> M.t_Expr -> bool =
fun v_fuel v_expression ->
(match (v_fuel, v_expression) with
| (0, _) ->
false
| (__nat_5, (M.SourceExpr (v_offset, v_annotation, v_value))) when __nat_5 >= 1 ->
(let v_rest = (__nat_5 - 1) in
(f_template_value (v_rest) (v_value)))
| (__nat_6, (M.QualifiedExpr (v_offset, v_annotation, v_predicates, v_value))) when __nat_6 >= 1 ->
(let v_rest = (__nat_6 - 1) in
(f_template_value (v_rest) (v_value)))
| (__nat_7, (M.InstantiationExpr (v_site, v_value))) when __nat_7 >= 1 ->
(let v_rest = (__nat_7 - 1) in
(f_template_value (v_rest) (v_value)))
| (_, (M.FunctionExpr (v_name))) ->
true
| (_, (M.ConstantExpr (v_name))) ->
true
| (_, (M.GenericOperationExpr (v_identity, v_template, v_arguments))) ->
true
| (_, (M.ConstructorRefExpr (v_constructor))) ->
true
| (_, (M.LambdaExpr (v_identity, v_parameter, v_p, v_r, v_body))) ->
true
| (_, _) ->
false)
and (* monomorph.bend:336 *)
f_bind_template : t_Configuration -> Base.text -> M.t_Expr -> t_Configuration =
fun v_configuration v_name v_value ->
(let (Configuration (v_originals, v_templates, v_entry, v_locals, v_affected, v_stride, v_constant_values, v_family_templates, v_step, v_schema)) = v_configuration in
(Configuration (v_originals, v_templates, v_entry, ((LocalTemplate (v_name, v_value)) :: v_locals), v_affected, v_stride, v_constant_values, v_family_templates, v_step, v_schema)))
and (* monomorph.bend:340 *)
f_unlocated : int -> M.t_Expr -> M.t_Expr =
fun v_fuel v_expression ->
(match (v_fuel, v_expression) with
| (__nat_8, (M.SourceExpr (v_offset, None, v_value))) when __nat_8 >= 1 ->
(let v_rest = (__nat_8 - 1) in
(f_unlocated (v_rest) (v_value)))
| (__nat_9, (M.InstantiationExpr (v_site, v_value))) when __nat_9 >= 1 ->
(let v_rest = (__nat_9 - 1) in
(f_unlocated (v_rest) (v_value)))
| (_, v_other) ->
v_other)
and (* monomorph.bend:349 *)
f_binary_operands : M.t_Expr -> M.t_Expr -> Base.text -> Base.text -> Base.text -> (M.t_TypeId) list -> (t_BinaryMember) option =
fun v_l v_r v_left v_right v_member v_templates ->
(match (v_l, v_r) with
| ((M.LocalExpr (v_a)), (M.LocalExpr (v_b))) ->
(Base.bool_pick ((Base.bool_and ((M.f_name_equal (v_a) (v_left))) ((M.f_name_equal (v_b) (v_right))))) ((Some ((BinaryMember (v_member, v_templates))))) (None))
| (_, _) ->
None)
and (* monomorph.bend:356 *)
f_binary_member : M.t_Expr -> Base.text -> Base.text -> (t_BinaryMember) option =
fun v_body v_left v_right ->
(match v_body with
| (M.AssociatedExpr (v_identity, M.BinaryDispatch, v_member, v_templates, v_l, v_r)) ->
(f_binary_operands ((f_unlocated (65536) (v_l))) ((f_unlocated (65536) (v_r))) (v_left) (v_right) (v_member) (v_templates))
| _ ->
None)
and (* monomorph.bend:363 *)
f_binary_lambda : M.t_Expr -> Base.text -> (t_BinaryMember) option =
fun v_body v_left ->
(match v_body with
| (M.LambdaExpr (v_identity, v_right, None, None, v_body)) ->
(f_binary_member ((f_unlocated (65536) (v_body))) (v_left) (v_right))
| _ ->
None)
and (* monomorph.bend:370 *)
f_binary_function : (M.t_Diagnostic, M.t_Function) Base.result_ -> (t_BinaryMember) option =
fun v_found ->
(match v_found with
| (Done ((M.Function (v_name, v_exported, v_left, None, None, v_body)))) ->
(f_binary_lambda ((f_unlocated (65536) (v_body))) (v_left))
| _ ->
None)
and (* monomorph.bend:377 *)
f_binary_result : (t_BinaryMember) option -> M.t_Expr -> M.t_Expr -> (t_BinaryCall) option =
fun v_member v_left v_right ->
(match v_member with
| (Some ((BinaryMember (v_name, v_templates)))) ->
(Some ((BinaryCall (v_name, v_templates, v_left, v_right))))
| None ->
None)
and (* monomorph.bend:384 *)
f_binary_target : M.t_Expr -> M.t_Expr -> M.t_Expr -> (M.t_Function) list -> (t_BinaryCall) option =
fun v_target v_left v_right v_originals ->
(match v_target with
| (M.FunctionExpr (v_name)) ->
(f_binary_result ((f_binary_function ((f_lookup (v_originals) (v_name))))) (v_left) (v_right))
| _ ->
None)
and (* monomorph.bend:391 *)
f_binary_call : M.t_Expr -> M.t_Expr -> (M.t_Function) list -> (t_BinaryCall) option =
fun v_callee v_right v_originals ->
(match v_callee with
| (M.ApplyExpr (v_target, v_left)) ->
(f_binary_target ((f_unlocated (65536) (v_target))) (v_left) (v_right) (v_originals))
| (M.CallExpr (v_name, v_left)) ->
(f_binary_target ((M.FunctionExpr (v_name))) (v_left) (v_right) (v_originals))
| _ ->
None)
and (* monomorph.bend:400 *)
f_expand : int -> t_ExpandWork -> t_Configuration -> (t_Rename) list -> int -> int -> (M.t_Diagnostic, t_Expansion) Base.result_ =
fun v_fuel v_work v_configuration v_stack v_base v_counter ->
(match (v_fuel, v_work) with
| (0, _) ->
(Fail ((M.Diagnostic (s_8, s_1, s_9))))
| (__nat_10, (Expression ((M.ConstantExpr (v_name))))) when __nat_10 >= 1 ->
(let v_rest = (__nat_10 - 1) in
(let (Configuration (v_originals, v_templates, v_entry, v_locals, v_affected, v_stride, v_constant_values, v_family_templates, v_step, v_schema)) = v_configuration in
(f_expand (v_rest) ((ConstantValue (v_name, (f_local_template (v_locals) (v_name))))) (v_configuration) (v_stack) (v_base) (v_counter))))
| (__nat_11, (ConstantValue (v_name, None))) when __nat_11 >= 1 ->
(let v_rest = (__nat_11 - 1) in
(let (Configuration (v_originals, v_templates, v_entry, v_locals, v_affected, v_stride, v_constant_values, v_family_templates, v_step, v_schema)) = v_configuration in
(f_expand (v_rest) ((ConstantReference (v_name, (f_lookup_constant (v_constant_values) (v_name)), (f_renamed (v_stack) (v_name))))) (v_configuration) (v_stack) (v_base) (v_counter))))
| (__nat_12, (ConstantReference (v_name, None, v_active))) when __nat_12 >= 1 ->
(let v_rest = (__nat_12 - 1) in
(Done ((Expansion ([(M.ConstantExpr (v_name))], [], [], v_counter)))))
| (__nat_13, (ConstantReference (v_name, (Some (v_original)), (Some (v_specialized))))) when __nat_13 >= 1 ->
(let v_rest = (__nat_13 - 1) in
(Done ((Expansion ([(M.ConstantExpr (v_specialized))], [], [], v_counter)))))
| (__nat_14, (ConstantReference (v_name, (Some ((M.Constant (v_declared, v_exported, v_annotation, v_value)))), None))) when __nat_14 >= 1 ->
(let v_rest = (__nat_14 - 1) in
(let (Configuration (v_originals, v_templates, v_entry, v_locals, v_affected, v_stride, v_constant_values, v_family_templates, v_step, v_schema)) = v_configuration in
(let v_specialized = (Base.string_append s_5 (Base.string_append (Base.nat_show (v_counter)) (Base.string_append s_10 v_name))) in
(match (f_expand (v_rest) ((Expression (v_value))) (v_configuration) (((Rename (v_name, v_specialized)) :: v_stack)) ((Base.nat_mul (v_counter) (v_stride))) ((Base.nat_add (v_counter) (v_step)))) with
| Fail __error -> Fail __error
| Done v_expanded ->
(match (f_one ((f_expressions (v_expanded)))) with
| Fail __error -> Fail __error
| Done v_expression ->
(match (f_relocate_annotation (v_annotation) ((Base.nat_mul (v_counter) (v_stride)))) with
| Fail __error -> Fail __error
| Done v_relocated ->
(Done ((Expansion ([(M.ConstantExpr (v_specialized))], (f_functions (v_expanded)), ((M.Constant (v_specialized, false, v_relocated, v_expression)) :: (f_emitted_constants (v_expanded))), (f_next (v_expanded))))))))))))
| (__nat_15, (ConstantValue (v_name, (Some (v_value))))) when __nat_15 >= 1 ->
(let v_rest = (__nat_15 - 1) in
(let (Configuration (v_originals, v_templates, v_entry, v_locals, v_affected, v_stride, v_constant_values, v_family_templates, v_step, v_schema)) = v_configuration in
(f_expand (v_rest) ((Expression (v_value))) (v_configuration) (v_stack) ((Base.nat_mul (v_counter) (v_stride))) ((Base.nat_add (v_counter) (v_step))))))
| (__nat_16, (Expression ((M.LocalExpr (v_name))))) when __nat_16 >= 1 ->
(let v_rest = (__nat_16 - 1) in
(let (Configuration (v_originals, v_templates, v_entry, v_locals, v_affected, v_stride, v_constant_values, v_family_templates, v_step, v_schema)) = v_configuration in
(f_expand (v_rest) ((LocalValue (v_name, (f_local_template (v_locals) (v_name))))) (v_configuration) (v_stack) (v_base) (v_counter))))
| (__nat_17, (LocalValue (v_name, None))) when __nat_17 >= 1 ->
(let v_rest = (__nat_17 - 1) in
(Done ((Expansion ([(M.LocalExpr (v_name))], [], [], v_counter)))))
| (__nat_18, (LocalValue (v_name, (Some (v_value))))) when __nat_18 >= 1 ->
(let v_rest = (__nat_18 - 1) in
(let (Configuration (v_originals, v_templates, v_entry, v_locals, v_affected, v_stride, v_constant_values, v_family_templates, v_step, v_schema)) = v_configuration in
(f_expand (v_rest) ((Expression (v_value))) (v_configuration) (v_stack) ((Base.nat_mul (v_counter) (v_stride))) ((Base.nat_add (v_counter) (v_step))))))
| (__nat_19, (Expression ((M.LetExpr (v_name, v_value, v_body))))) when __nat_19 >= 1 ->
(let v_rest = (__nat_19 - 1) in
(f_expand (v_rest) ((LetValue (v_name, v_value, v_body, (f_template_value (65536) (v_value))))) (v_configuration) (v_stack) (v_base) (v_counter)))
| (__nat_20, (LetValue (v_name, v_value, v_body, true))) when __nat_20 >= 1 ->
(let v_rest = (__nat_20 - 1) in
(f_expand (v_rest) ((Expression (v_body))) ((f_bind_template (v_configuration) (v_name) (v_value))) (v_stack) (v_base) (v_counter)))
| (__nat_21, (LetValue (v_name, v_value, v_body, false))) when __nat_21 >= 1 ->
(let v_rest = (__nat_21 - 1) in
(match (f_expand (v_rest) ((Expressions ([v_value; v_body]))) (v_configuration) (v_stack) (v_base) (v_counter)) with
| Fail __error -> Fail __error
| Done v_expanded ->
(match (f_rebuild ((M.LetExpr (v_name, v_value, v_body))) ((f_expressions (v_expanded))) (v_base)) with
| Fail __error -> Fail __error
| Done v_expression ->
(Done ((Expansion ([v_expression], (f_functions (v_expanded)), (f_emitted_constants (v_expanded)), (f_next (v_expanded)))))))))
| (__nat_22, (Expression ((M.FunctionExpr (v_name))))) when __nat_22 >= 1 ->
(let v_rest = (__nat_22 - 1) in
(let (Configuration (v_originals, v_templates, v_entry, v_locals, v_affected, v_stride, v_constant_values, v_family_templates, v_step, v_schema)) = v_configuration in
(f_expand (v_rest) ((Reference (v_name, (D.f_contains (v_templates) (v_name)), (f_renamed (v_stack) (v_name))))) (v_configuration) (v_stack) (v_base) (v_counter))))
| (__nat_23, (Reference (v_name, false, v_active))) when __nat_23 >= 1 ->
(let v_rest = (__nat_23 - 1) in
(Done ((Expansion ([(M.FunctionExpr (v_name))], [], [], v_counter)))))
| (__nat_24, (Reference (v_name, true, (Some (v_specialized))))) when __nat_24 >= 1 ->
(let v_rest = (__nat_24 - 1) in
(Done ((Expansion ([(M.FunctionExpr (v_specialized))], [], [], v_counter)))))
| (__nat_25, (Reference (v_name, true, None))) when __nat_25 >= 1 ->
(let v_rest = (__nat_25 - 1) in
(let (Configuration (v_originals, v_templates, v_entry, v_locals, v_affected, v_stride, v_constant_values, v_family_templates, v_step, v_schema)) = v_configuration in
(match (f_lookup (v_originals) (v_name)) with
| Fail __error -> Fail __error
| Done v_original ->
(f_expand (v_rest) ((Clone (v_original))) (v_configuration) (v_stack) (v_base) (v_counter)))))
| (__nat_26, (Clone ((M.Function (v_name, v_exported, v_parameter, v_p, v_r, v_body))))) when __nat_26 >= 1 ->
(let v_rest = (__nat_26 - 1) in
(let (Configuration (v_originals, v_templates, v_entry, v_locals, v_affected, v_stride, v_constant_values, v_family_templates, v_step, v_schema)) = v_configuration in
(let v_specialized = (Base.string_append s_5 (Base.string_append (Base.nat_show (v_counter)) (Base.string_append s_10 v_name))) in
(match (f_expand (v_rest) ((Expression (v_body))) (v_configuration) (((Rename (v_name, v_specialized)) :: v_stack)) ((Base.nat_mul (v_counter) (v_stride))) ((Base.nat_add (v_counter) (v_step)))) with
| Fail __error -> Fail __error
| Done v_expanded ->
(match (f_one ((f_expressions (v_expanded)))) with
| Fail __error -> Fail __error
| Done v_expression ->
(match (f_relocate_annotation (v_p) ((Base.nat_mul (v_counter) (v_stride)))) with
| Fail __error -> Fail __error
| Done v_parameter_type ->
(match (f_relocate_annotation (v_r) ((Base.nat_mul (v_counter) (v_stride)))) with
| Fail __error -> Fail __error
| Done v_result_type ->
(Done ((Expansion ([(M.FunctionExpr (v_specialized))], ((M.Function (v_specialized, false, v_parameter, v_parameter_type, v_result_type, v_expression)) :: (f_functions (v_expanded))), (f_emitted_constants (v_expanded)), (f_next (v_expanded)))))))))))))
| (__nat_27, (Expression ((M.ApplyExpr (v_callee, v_argument))))) when __nat_27 >= 1 ->
(let v_rest = (__nat_27 - 1) in
(let (Configuration (v_originals, v_templates, v_entry, v_locals, v_affected, v_stride, v_constant_values, v_family_templates, v_step, v_schema)) = v_configuration in
(f_expand (v_rest) ((Application (v_callee, v_argument, (f_binary_call ((f_unlocated (65536) (v_callee))) (v_argument) (v_originals))))) (v_configuration) (v_stack) (v_base) (v_counter))))
| (__nat_28, (Application (v_callee, v_argument, (Some ((BinaryCall (v_member, v_effect_templates, v_left, v_right))))))) when __nat_28 >= 1 ->
(let v_rest = (__nat_28 - 1) in
(let (Configuration (v_originals, v_templates, v_entry, v_locals, v_affected, v_stride, v_constant_values, v_family_templates, v_step, v_schema)) = v_configuration in
(match (f_expand (v_rest) ((Expressions ([v_left; v_right]))) (v_configuration) (v_stack) (v_base) ((Base.nat_add (v_counter) (v_step)))) with
| Fail __error -> Fail __error
| Done v_expanded ->
(match (f_rebuild ((M.AssociatedExpr ((Base.nat_mul (v_counter) (v_stride)), M.BinaryDispatch, v_member, v_effect_templates, M.UnitExpr, M.UnitExpr))) ((f_expressions (v_expanded))) (0)) with
| Fail __error -> Fail __error
| Done v_expression ->
(Done ((Expansion ([v_expression], (f_functions (v_expanded)), (f_emitted_constants (v_expanded)), (f_next (v_expanded))))))))))
| (__nat_29, (Application (v_callee, v_argument, None))) when __nat_29 >= 1 ->
(let v_rest = (__nat_29 - 1) in
(match (f_expand (v_rest) ((Expressions ([v_callee; v_argument]))) (v_configuration) (v_stack) (v_base) (v_counter)) with
| Fail __error -> Fail __error
| Done v_expanded ->
(match (f_rebuild ((M.ApplyExpr (v_callee, v_argument))) ((f_expressions (v_expanded))) (v_base)) with
| Fail __error -> Fail __error
| Done v_expression ->
(Done ((Expansion ([v_expression], (f_functions (v_expanded)), (f_emitted_constants (v_expanded)), (f_next (v_expanded)))))))))
| (__nat_30, (Expression ((M.CallExpr (v_callee, v_argument))))) when __nat_30 >= 1 ->
(let v_rest = (__nat_30 - 1) in
(f_expand (v_rest) ((Expression ((M.ApplyExpr ((M.FunctionExpr (v_callee)), v_argument))))) (v_configuration) (v_stack) (v_base) (v_counter)))
| (__nat_31, (Expression (v_expression))) when __nat_31 >= 1 ->
(let v_rest = (__nat_31 - 1) in
(match (f_expand (v_rest) ((Expressions ((F.f_children (v_expression))))) (v_configuration) (v_stack) (v_base) (v_counter)) with
| Fail __error -> Fail __error
| Done v_expanded ->
(match (f_rebuild (v_expression) ((f_expressions (v_expanded))) (v_base)) with
| Fail __error -> Fail __error
| Done v_rebuilt ->
(Done ((Expansion ([v_rebuilt], (f_functions (v_expanded)), (f_emitted_constants (v_expanded)), (f_next (v_expanded)))))))))
| (__nat_32, (Expressions ([]))) when __nat_32 >= 1 ->
(let v_rest = (__nat_32 - 1) in
(Done ((Expansion ([], [], [], v_counter)))))
| (__nat_33, (Expressions ((v_head :: v_tail)))) when __nat_33 >= 1 ->
(let v_rest = (__nat_33 - 1) in
(match (f_expand (v_rest) ((Expression (v_head))) (v_configuration) (v_stack) (v_base) (v_counter)) with
| Fail __error -> Fail __error
| Done v_first ->
(match (f_expand (v_rest) ((Expressions (v_tail))) (v_configuration) (v_stack) (v_base) ((f_next (v_first)))) with
| Fail __error -> Fail __error
| Done v_following ->
(Done ((Expansion ((Base.list_append ((f_expressions (v_first))) ((f_expressions (v_following)))), (Base.list_append ((f_functions (v_first))) ((f_functions (v_following)))), (Base.list_append ((f_emitted_constants (v_first))) ((f_emitted_constants (v_following)))), (f_next (v_following))))))))))
and (* monomorph.bend:495 *)
f_expand_root : bool -> bool -> M.t_Function -> t_Configuration -> int -> (M.t_Diagnostic, t_Expansion) Base.result_ =
fun v_root v_template v_function v_configuration v_counter ->
(match (v_root, v_template, v_function) with
| (false, true, v_function) ->
(Done ((Expansion ([], [], [], v_counter))))
| (false, false, v_function) ->
(Done ((Expansion ([], [v_function], [], v_counter))))
| (true, _, (M.Function (v_name, v_exported, v_parameter, v_p, v_r, v_body))) ->
(match (f_expand (65536) ((Expression (v_body))) (v_configuration) ([(Rename (v_name, v_name))]) (0) (v_counter)) with
| Fail __error -> Fail __error
| Done v_expanded ->
(match (f_one ((f_expressions (v_expanded)))) with
| Fail __error -> Fail __error
| Done v_expression ->
(Done ((Expansion ([], ((M.Function (v_name, v_exported, v_parameter, v_p, v_r, v_expression)) :: (f_functions (v_expanded))), (f_emitted_constants (v_expanded)), (f_next (v_expanded)))))))))
and (* monomorph.bend:507 *)
f_expand_roots : (M.t_Function) list -> t_Configuration -> int -> (M.t_Diagnostic, t_Expansion) Base.result_ =
fun v_pending v_configuration v_counter ->
(match v_pending with
| [] ->
(Done ((Expansion ([], [], [], v_counter))))
| (v_function :: v_tail) ->
(let (M.Function (v_name, v_exported, v_parameter, v_p, v_r, v_body)) = v_function in
(let (Configuration (v_originals, v_templates, v_entry, v_locals, v_affected, v_stride, v_constant_values, v_family_templates, v_step, v_schema)) = v_configuration in
(match (f_expand_root ((Base.bool_or ((Base.bool_and (v_exported) ((D.f_contains (v_templates) (v_name))))) ((Base.bool_and ((Base.bool_not ((D.f_contains (v_templates) (v_name))))) ((D.f_contains (v_affected) (v_name))))))) ((D.f_contains (v_templates) (v_name))) (v_function) (v_configuration) (v_counter)) with
| Fail __error -> Fail __error
| Done v_current ->
(match (f_expand_roots (v_tail) (v_configuration) ((f_next (v_current)))) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done ((Expansion ([], (Base.list_append ((f_functions (v_current))) ((f_functions (v_rest)))), (Base.list_append ((f_emitted_constants (v_current))) ((f_emitted_constants (v_rest)))), (f_next (v_rest)))))))))))
and (* monomorph.bend:519 *)
f_prepend_constant : M.t_Constant -> t_ExpandedModule -> (M.t_Diagnostic, t_ExpandedModule) Base.result_ =
fun v_constant v_expanded ->
(let (ExpandedModule ((M.Module (v_constants, v_functions, v_types, v_operations)), v_next, v_bindings, v_certificates)) = v_expanded in
(Done ((ExpandedModule ((M.Module ((v_constant :: v_constants), v_functions, v_types, v_operations)), v_next, v_bindings, v_certificates)))))
and (* monomorph.bend:523 *)
f_expand_constants : (M.t_Constant) list -> t_Configuration -> (M.t_Function) list -> (M.t_Constant) list -> (M.t_DataType) list -> (M.t_Operation) list -> int -> (M.t_Diagnostic, t_ExpandedModule) Base.result_ =
fun v_constants v_configuration v_emitted v_captured v_types v_operations v_counter ->
(match v_constants with
| [] ->
(Done ((ExpandedModule ((M.Module (v_captured, v_emitted, v_types, v_operations)), v_counter, [], []))))
| ((M.Constant (v_name, v_exported, v_annotation, v_value)) :: v_tail) ->
(match (f_expand (65536) ((Expression (v_value))) (v_configuration) ([]) (0) (v_counter)) with
| Fail __error -> Fail __error
| Done v_expanded ->
(match (f_one ((f_expressions (v_expanded)))) with
| Fail __error -> Fail __error
| Done v_expression ->
(match (f_expand_constants (v_tail) (v_configuration) ((Base.list_append (v_emitted) ((f_functions (v_expanded))))) ((Base.list_append (v_captured) ((f_emitted_constants (v_expanded))))) (v_types) (v_operations) ((f_next (v_expanded)))) with
| Fail __error -> Fail __error
| Done v_rest ->
(f_prepend_constant ((M.Constant (v_name, v_exported, v_annotation, v_expression))) (v_rest))))))
and (* monomorph.bend:534 *)
f_function_bindings : (M.t_CheckedFunction) list -> (I.t_Binding) list =
fun v_functions ->
(match v_functions with
| [] ->
[]
| ((M.CheckedFunction (v_function, (M.Signature (v_name, v_parameter, v_result, v_variables, v_row)), v_effects)) :: v_tail) ->
((I.Binding (v_name, (M.FunctionTy (v_parameter, v_result, v_row)), v_variables, [])) :: (f_function_bindings (v_tail))))
and (* monomorph.bend:541 *)
f_constant_bindings : (M.t_CheckedConstant) list -> (I.t_Binding) list =
fun v_constants ->
(match v_constants with
| [] ->
[]
| ((M.CheckedConstant ((M.Constant (v_name, v_exported, v_annotation, v_value)), v_ty, v_variables)) :: v_tail) ->
((I.Binding (v_name, v_ty, v_variables, [])) :: (f_constant_bindings (v_tail))))
and (* monomorph.bend:548 *)
f_shape_bindings : M.t_CheckedModule -> G.t_Environment =
fun v_checked ->
(let (M.CheckedModule (v_constants, v_functions, v_types, v_operations)) = v_checked in
(G.Environment ((Base.list_append ((f_function_bindings (v_functions))) ((f_constant_bindings (v_constants)))), [], (I.State ((T.f_empty ()), 0, MTip)))))
and (* monomorph.bend:552 *)
f_certificate_interfaces : (Core.t_Certificate) list -> (Groups.t_Interface) list =
fun v_certificates ->
(match v_certificates with
| [] ->
[]
| ((Core.Certificate (v_module, v_checked, v_imports)) :: v_tail) ->
(Base.list_append ((Groups.f_checked_interfaces (v_checked))) ((f_certificate_interfaces (v_tail)))))
and (* monomorph.bend:559 *)
f_has_planned_predicates : (C.t_UsePlan) list -> bool =
fun v_plans ->
(match v_plans with
| [] ->
false
| ((C.UsePlan (v_site, v_subject, v_ty, [])) :: v_tail) ->
(f_has_planned_predicates (v_tail))
| ((C.UsePlan (v_site, v_subject, v_ty, v_predicates)) :: v_tail) ->
true)
and (* monomorph.bend:568 *)
f_certificate_plan_roots : (Core.t_Certificate) list -> (Base.text) list =
fun v_certificates ->
(match v_certificates with
| [] ->
[]
| ((Core.Certificate (v_module, v_checked, v_imports)) :: v_tail) ->
(let v_rest = (f_certificate_plan_roots (v_tail)) in
(Base.bool_pick ((f_has_planned_predicates ((Groups.f_checked_uses (v_checked))))) ((Base.list_append ((Core.f_names (v_module))) (v_rest))) (v_rest))))
and (* monomorph.bend:576 *)
f_without_interface_bindings : (I.t_Binding) list -> (Base.text) list -> (I.t_Binding) list =
fun v_bindings v_names ->
(match v_bindings with
| [] ->
[]
| ((I.Binding (v_name, v_ty, v_variables, v_predicates)) :: v_tail) ->
(let v_rest = (f_without_interface_bindings (v_tail) (v_names)) in
(Base.bool_pick ((D.f_contains (v_names) (v_name))) (v_rest) (((I.Binding (v_name, v_ty, v_variables, v_predicates)) :: v_rest)))))
and (* monomorph.bend:584 *)
f_shape_initial : Scheduler.t_Initial -> M.t_Module -> (M.t_Diagnostic, G.t_Environment) Base.result_ =
fun v_initial v_module ->
(let (Scheduler.Initial (v_checked, v_certificates, v_needs)) = v_initial in
(let (M.Module (v_constants, v_functions, v_types, v_operations)) = v_module in
(let v_interfaces = (f_certificate_interfaces (v_certificates)) in
(let v_bare = (G.f_env_bindings ((f_shape_bindings (v_checked)))) in
(match (Groups.f_import_interfaces (v_interfaces) (v_operations) (v_types) (0)) with
| Fail __error -> Fail __error
| Done v_imported ->
(Done ((G.Environment ((Base.list_append ((G.f_env_bindings (v_imported))) ((f_without_interface_bindings (v_bare) ((Groups.f_interface_names (v_interfaces)))))), (G.f_env_definitions (v_imported)), (G.f_env_state (v_imported)))))))))))
and (* monomorph.bend:593 *)
f_resolved_bindings : (I.t_Binding) list -> T.t_Substitutions -> (M.t_Diagnostic, (I.t_Binding) list) Base.result_ =
fun v_bindings v_substitutions ->
(match v_bindings with
| [] ->
(Done ([]))
| ((I.Binding (v_name, v_ty, v_variables, v_predicates)) :: v_tail) ->
(match (T.f_resolve (v_substitutions) (v_ty)) with
| Fail __error -> Fail __error
| Done v_resolved ->
(match (C.f_resolve_list (v_substitutions) (v_predicates)) with
| Fail __error -> Fail __error
| Done v_requirements ->
(match (f_resolved_bindings (v_tail) (v_substitutions)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done (((I.Binding (v_name, v_resolved, v_variables, v_requirements)) :: v_rest)))))))
and (* monomorph.bend:604 *)
f_ordinary_bindings_indexed : (I.t_Binding) list -> Base.set -> (I.t_Binding) list =
fun v_bindings v_templates ->
(match v_bindings with
| [] ->
[]
| ((I.Binding (v_name, v_ty, v_variables, v_predicates)) :: v_tail) ->
(let v_rest = (f_ordinary_bindings_indexed (v_tail) (v_templates)) in
(Base.bool_pick ((Base.bool_not ((D.f_member (v_templates) (v_name))))) (((I.Binding (v_name, v_ty, v_variables, v_predicates)) :: v_rest)) (v_rest))))
and (* monomorph.bend:612 *)
f_ordinary_bindings : (I.t_Binding) list -> (Base.text) list -> (I.t_Binding) list =
fun v_bindings v_templates ->
(f_ordinary_bindings_indexed (v_bindings) ((G.f_reference_set (v_templates) ((Base.set_new ())))))
and (* monomorph.bend:615 *)
f_pending_functions : (M.t_Function) list -> (I.t_Binding) list -> (M.t_Function) list =
fun v_functions v_ordinary ->
(match v_functions with
| [] ->
[]
| ((M.Function (v_name, v_exported, v_parameter, v_p, v_r, v_body)) :: v_tail) ->
(let v_rest = (f_pending_functions (v_tail) (v_ordinary)) in
(Base.bool_pick ((Base.maybe_is_some ((I.f_lookup_binding (v_ordinary) (v_name))))) (v_rest) (((M.Function (v_name, v_exported, v_parameter, v_p, v_r, v_body)) :: v_rest)))))
and (* monomorph.bend:623 *)
f_pending_constants : (M.t_Constant) list -> (I.t_Binding) list -> (M.t_Constant) list =
fun v_constants v_ordinary ->
(match v_constants with
| [] ->
[]
| ((M.Constant (v_name, v_exported, v_annotation, v_value)) :: v_tail) ->
(let v_rest = (f_pending_constants (v_tail) (v_ordinary)) in
(Base.bool_pick ((Base.maybe_is_some ((I.f_lookup_binding (v_ordinary) (v_name))))) (v_rest) (((M.Constant (v_name, v_exported, v_annotation, v_value)) :: v_rest)))))
and (* monomorph.bend:631 *)
f_clone_origin : Base.text -> Base.text =
fun v_name ->
(match v_name with
| (SCon ((Chr (0x0000005d)), (SCon ((Chr (0x0000002e)), v_tail)))) ->
v_tail
| (SCon (v_character, v_tail)) ->
(f_clone_origin (v_tail))
| SNil ->
SNil)
and (* monomorph.bend:640 *)
f_original_name : Base.text -> Base.text =
fun v_name ->
(Base.bool_pick ((Base.string_starts_with (v_name) (s_5))) ((f_clone_origin (v_name))) (v_name))
and (* monomorph.bend:643 *)
f_shape_limit : (I.t_Binding) list -> int -> (M.t_Diagnostic, int) Base.result_ =
fun v_bindings v_next ->
(match v_bindings with
| [] ->
(Done (v_next))
| ((I.Binding (v_name, v_ty, v_variables, v_predicates)) :: v_tail) ->
(match (T.f_free (v_ty)) with
| Fail __error -> Fail __error
| Done v_free ->
(match (C.f_free_list (v_predicates)) with
| Fail __error -> Fail __error
| Done v_requirement_free ->
(f_shape_limit (v_tail) ((T.f_above ((T.f_union (v_free) (v_requirement_free))) (v_next)))))))
and (* monomorph.bend:653 *)
f_seed_bindings : (I.t_Binding) list -> (I.t_Binding) list -> I.t_State -> (M.t_Diagnostic, I.t_State) Base.result_ =
fun v_bindings v_shapes v_state ->
(match v_bindings with
| [] ->
(Done (v_state))
| ((I.Binding (v_name, v_ty, v_variables, v_predicates)) :: v_tail) ->
(match (I.f_instantiate_binding ((I.f_lookup_binding (v_shapes) ((f_original_name (v_name))))) (v_state) (v_name) (v_name)) with
| Fail __error -> Fail __error
| Done v_shape ->
(match (I.f_unify (v_ty) ((I.f_type_of (v_shape))) ((I.f_state_of (v_shape))) (v_name)) with
| Fail __error -> Fail __error
| Done v_next ->
(f_seed_bindings (v_tail) (v_shapes) (v_next)))))
and (* monomorph.bend:663 *)
f_infer_pending : (G.t_Declaration) list -> (I.t_Binding) list -> G.t_Environment -> (M.t_Operation) list -> (M.t_DataType) list -> (Base.text) list -> (M.t_Diagnostic, G.t_Environment) Base.result_ =
fun v_declarations v_shapes v_environment v_operations v_types v_names ->
(let (G.Environment (v_bindings, v_definitions, v_state)) = v_environment in
(let v_start = (I.f_next_of (v_state)) in
(let v_created = (G.f_initial_bindings (v_declarations) (v_start)) in
(match (f_seed_bindings (v_created) (v_shapes) ((I.f_with_next (v_state) ((G.f_initial_next (v_declarations) (v_start)))))) with
| Fail __error -> Fail __error
| Done v_seeded ->
(ParallelInfer.f_infer_component (v_declarations) ((G.Environment ((Base.list_append (v_created) (v_bindings)), v_definitions, v_seeded))) (v_operations) (v_types) (v_names))))))
and (* monomorph.bend:674 *)
f_staged_clone : (M.t_Diagnostic, t_Expansion) Base.result_ -> M.t_Function -> bool =
fun v_expanded v_clone ->
(match v_expanded with
| (Done ((Expansion (v_expressions, (v_expected :: []), [], v_next)))) ->
(Compare.f_compare (1048576) ([(Compare.FunctionPair (v_expected, v_clone))]) (true))
| _ ->
false)
and (* monomorph.bend:681 *)
f_exact_staged_clone : Staging.t_Candidate -> M.t_Function -> int -> bool =
fun v_candidate v_clone v_stride ->
(let v_source = (Staging.f_candidate_source (v_candidate)) in
(let v_name = (Staging.f_source_name (v_source)) in
(let v_configuration = (Configuration ([v_source], [v_name], s_11, [], [], v_stride, [], [], 1, [])) in
(f_staged_clone ((f_expand (65536) ((Clone (v_source))) (v_configuration) ([]) (0) ((Staging.f_candidate_counter (v_candidate))))) (v_clone)))))
and (* monomorph.bend:687 *)
f_staged_candidate : (Staging.t_Candidate) option -> M.t_Function -> int -> G.t_Environment -> (M.t_DataType) list -> (G.t_Environment) option =
fun v_found v_function v_stride v_environment v_types ->
(match v_found with
| None ->
None
| (Some (v_candidate)) ->
(Staging.f_replay (v_candidate) (v_function) (v_stride) (v_environment) (v_types) ((f_exact_staged_clone (v_candidate) (v_function) (v_stride)))))
and (* monomorph.bend:694 *)
f_staged_or_infer : (G.t_Environment) option -> G.t_Declaration -> G.t_Environment -> (M.t_Operation) list -> (M.t_DataType) list -> (Base.text) list -> (((Bindings.t_Entry) list) Base.map) option -> (M.t_Diagnostic, G.t_Environment) Base.result_ =
fun v_found v_declaration v_environment v_operations v_types v_functions v_index ->
(match v_found with
| (Some (v_value)) ->
(Done (v_value))
| None ->
(G.f_infer_declaration_prepared (v_declaration) (v_environment) (v_operations) (v_types) (v_functions) (v_index)))
and (* monomorph.bend:707 *)
f_has_staged_candidate : G.t_Declaration -> (Staging.t_Scheme) list -> bool =
fun v_declaration v_schemes ->
(match v_declaration with
| (G.FunctionDeclaration (v_function)) ->
(Base.maybe_is_some ((Staging.f_candidate (v_function) (v_schemes))))
| (G.ConstantDeclaration (v_constant)) ->
false)
and (* monomorph.bend:714 *)
f_split_staged_if : (G.t_Declaration) list -> bool -> G.t_Declaration -> (G.t_Declaration) list -> (Staging.t_Scheme) list -> t_StagedSplit =
fun v_remaining v_candidate v_head v_reversed v_schemes ->
(match (v_remaining, v_candidate) with
| (v_rest, true) ->
(StagedSplit ((Base.list_reverse (v_reversed)), (Some (v_head)), v_rest))
| ([], false) ->
(StagedSplit ((Base.list_reverse ((v_head :: v_reversed))), None, []))
| ((v_next :: v_rest), false) ->
(f_split_staged_if (v_rest) ((f_has_staged_candidate (v_next) (v_schemes))) (v_next) ((v_head :: v_reversed)) (v_schemes)))
and (* monomorph.bend:723 *)
f_split_staged : (G.t_Declaration) list -> (G.t_Declaration) list -> (Staging.t_Scheme) list -> t_StagedSplit =
fun v_remaining v_reversed v_schemes ->
(match v_remaining with
| [] ->
(StagedSplit ((Base.list_reverse (v_reversed)), None, []))
| (v_head :: v_tail) ->
(f_split_staged_if (v_tail) ((f_has_staged_candidate (v_head) (v_schemes))) (v_head) (v_reversed) (v_schemes)))
and (* monomorph.bend:730 *)
f_infer_staged_barrier : G.t_Declaration -> G.t_Environment -> (M.t_Operation) list -> (M.t_DataType) list -> (Base.text) list -> (Staging.t_Scheme) list -> int -> (((Bindings.t_Entry) list) Base.map) option -> (M.t_Diagnostic, G.t_Environment) Base.result_ =
fun v_declaration v_environment v_operations v_types v_functions v_schemes v_stride v_index ->
(match v_declaration with
| (G.FunctionDeclaration (v_function)) ->
(f_staged_or_infer ((f_staged_candidate ((Staging.f_candidate (v_function) (v_schemes))) (v_function) (v_stride) (v_environment) (v_types))) (v_declaration) (v_environment) (v_operations) (v_types) (v_functions) (v_index))
| (G.ConstantDeclaration (v_constant)) ->
(G.f_infer_declaration_prepared (v_declaration) (v_environment) (v_operations) (v_types) (v_functions) (v_index)))
and (* monomorph.bend:742 *)
f_infer_staged_work : int -> t_StagedWork -> (M.t_Operation) list -> (M.t_DataType) list -> (Base.text) list -> (Staging.t_Scheme) list -> int -> (Base.text) list -> (((Bindings.t_Entry) list) Base.map) option -> bool -> (M.t_Diagnostic, G.t_Environment) Base.result_ =
fun v_fuel v_work v_operations v_types v_functions v_schemes v_stride v_all_pending v_index v_catalog_closed ->
(match (v_fuel, v_work) with
| (0, _) ->
(Fail ((M.Diagnostic (s_0, s_12, s_13))))
| (__nat_34, (StageDeclarations (v_declarations, v_environment))) when __nat_34 >= 1 ->
(let v_rest = (__nat_34 - 1) in
(f_infer_staged_work (v_rest) ((StageSplit ((f_split_staged (v_declarations) ([]) (v_schemes)), v_environment))) (v_operations) (v_types) (v_functions) (v_schemes) (v_stride) (v_all_pending) (v_index) (v_catalog_closed)))
| (__nat_35, (StageSplit ((StagedSplit (v_ordinary, v_barrier, v_remaining)), v_environment))) when __nat_35 >= 1 ->
(let v_rest = (__nat_35 - 1) in
(match (ParallelInfer.f_infer_segment_prechecked (v_ordinary) (v_all_pending) (v_environment) (v_operations) (v_types) (v_functions) (v_index) (v_catalog_closed)) with
| Fail __error -> Fail __error
| Done v_next ->
(f_infer_staged_work (v_rest) ((StageBarrier (v_barrier, v_remaining, v_next))) (v_operations) (v_types) (v_functions) (v_schemes) (v_stride) (v_all_pending) (v_index) (v_catalog_closed))))
| (__nat_36, (StageBarrier (None, v_remaining, v_environment))) when __nat_36 >= 1 ->
(let v_rest = (__nat_36 - 1) in
(Done (v_environment)))
| (__nat_37, (StageBarrier ((Some (v_declaration)), v_remaining, v_environment))) when __nat_37 >= 1 ->
(let v_rest = (__nat_37 - 1) in
(match (f_infer_staged_barrier (v_declaration) (v_environment) (v_operations) (v_types) (v_functions) (v_schemes) (v_stride) (v_index)) with
| Fail __error -> Fail __error
| Done v_next ->
(f_infer_staged_work (v_rest) ((StageDeclarations (v_remaining, v_next))) (v_operations) (v_types) (v_functions) (v_schemes) (v_stride) (v_all_pending) (v_index) (v_catalog_closed)))))
and (* monomorph.bend:759 *)
f_staged_catalog_closed : (G.t_Declaration) list -> (M.t_Operation) list -> (M.t_DataType) list -> bool =
fun v_declarations v_operations v_types ->
(match v_declarations with
| [] ->
false
| [v_single] ->
false
| (v_a :: (v_b :: v_rest)) ->
(ParallelInfer.f_catalog_closed (v_operations) (v_types)))
and (* monomorph.bend:765 *)
f_infer_staged_unique : bool -> (G.t_Declaration) list -> (Base.text) list -> G.t_Environment -> (M.t_Operation) list -> (M.t_DataType) list -> (Base.text) list -> (Staging.t_Scheme) list -> int -> (((Bindings.t_Entry) list) Base.map) option -> (M.t_Diagnostic, G.t_Environment) Base.result_ =
fun v_unique v_declarations v_pending v_environment v_operations v_types v_functions v_schemes v_stride v_index ->
(match v_unique with
| false ->
(G.f_infer_component (v_pending) (v_declarations) (v_environment) (v_operations) (v_types) (v_functions))
| true ->
(f_infer_staged_work ((Base.nat_add 3 (Base.nat_mul (3) ((Base.list_length (v_declarations)))))) ((StageDeclarations (v_declarations, v_environment))) (v_operations) (v_types) (v_functions) (v_schemes) (v_stride) (v_pending) (v_index) ((f_staged_catalog_closed (v_declarations) (v_operations) (v_types)))))
and (* monomorph.bend:772 *)
f_infer_pending_staged : (G.t_Declaration) list -> (I.t_Binding) list -> G.t_Environment -> (M.t_Operation) list -> (M.t_DataType) list -> (Base.text) list -> (Staging.t_Scheme) list -> int -> (M.t_Diagnostic, G.t_Environment) Base.result_ =
fun v_declarations v_shapes v_environment v_operations v_types v_names v_schemes v_stride ->
(let (G.Environment (v_bindings, v_definitions, v_state)) = v_environment in
(let v_start = (I.f_next_of (v_state)) in
(let v_created = (G.f_initial_bindings (v_declarations) (v_start)) in
(match (f_seed_bindings (v_created) (v_shapes) ((I.f_with_next (v_state) ((G.f_initial_next (v_declarations) (v_start)))))) with
| Fail __error -> Fail __error
| Done v_seeded ->
(let v_prepared_environment = (G.Environment ((Base.list_append (v_created) (v_bindings)), v_definitions, v_seeded)) in
(let v_pending = (G.f_names (v_declarations)) in
(f_infer_staged_unique ((ParallelInfer.f_unique_names (v_pending) ((Base.set_new ())))) (v_declarations) (v_pending) (v_prepared_environment) (v_operations) (v_types) (v_names) (v_schemes) (v_stride) ((G.f_component_bindings (v_pending) ((G.f_env_bindings (v_prepared_environment))))))))))))
and (* monomorph.bend:782 *)
f_infer_pending_optional : (G.t_Declaration) list -> (I.t_Binding) list -> G.t_Environment -> (M.t_Operation) list -> (M.t_DataType) list -> (Base.text) list -> (Staging.t_Scheme) list -> int -> (M.t_Diagnostic, G.t_Environment) Base.result_ =
fun v_declarations v_shapes v_environment v_operations v_types v_names v_schemes v_stride ->
(match v_schemes with
| [] ->
(f_infer_pending (v_declarations) (v_shapes) (v_environment) (v_operations) (v_types) (v_names))
| (v_head :: v_tail) ->
(f_infer_pending_staged (v_declarations) (v_shapes) (v_environment) (v_operations) (v_types) (v_names) ((v_head :: v_tail)) (v_stride)))
and (* monomorph.bend:789 *)
f_nominal_prefix : M.t_TypeId -> Base.text -> Base.text =
fun v_identity v_entry ->
(let (M.TypeId (v_module_name, v_declaration)) = v_identity in
(Base.string_append (Base.bool_pick ((M.f_name_equal (v_module_name) (s_14))) (s_15) ((Base.bool_pick ((M.f_name_equal (v_module_name) (v_entry))) (s_11) ((Base.string_append s_16 (Base.string_append v_module_name s_10)))))) v_declaration))
and (* monomorph.bend:793 *)
f_owner : M.t_Ty -> Base.text -> (Base.text) option =
fun v_ty v_entry ->
(match v_ty with
| M.U32Ty ->
(Some (s_17))
| M.F32Ty ->
(Some (s_18))
| M.BoolTy ->
(Some (s_19))
| M.UnitTy ->
(Some (s_20))
| (M.AppliedTy (v_identity, v_arguments)) ->
(Some ((f_nominal_prefix (v_identity) (v_entry))))
| (M.ArrayTy (v_element)) ->
(Some (s_21))
| (M.VariableTy (v_index)) ->
None
| (M.ParameterTy (v_index)) ->
None
| _ ->
(Some (s_11)))
and (* monomorph.bend:814 *)
f_member_name : (Base.text) option -> Base.text -> (Base.text) option =
fun v_owner v_member ->
(match v_owner with
| None ->
None
| (Some (v_prefix)) ->
(Some ((Base.string_append v_prefix (Base.string_append s_22 v_member)))))
and (* monomorph.bend:822 *)
f_candidate_binding : (I.t_Binding) option -> Base.text -> M.t_Ty -> M.t_Ty -> I.t_State -> Base.text -> (M.t_Diagnostic, I.t_Typing) Base.result_ =
fun v_found v_name v_left v_right v_state v_subject ->
(match (I.f_instantiate_binding (v_found) (v_state) (v_name) (v_subject)) with
| Fail __error -> Fail __error
| Done v_fn ->
(let v_next = (I.f_next_of ((I.f_state_of (v_fn)))) in
(match (I.f_unify ((I.f_type_of (v_fn))) ((M.FunctionTy (v_left, (M.FunctionTy (v_right, (M.VariableTy (v_next)), (M.EffectRow ([], (M.RowVariable ((Base.nat_add 1 v_next))))))), (M.EffectRow ([], (M.RowVariable ((Base.nat_add 2 v_next)))))))) ((I.f_with_next ((I.f_state_of (v_fn))) ((Base.nat_add 3 v_next)))) (v_subject)) with
| Fail __error -> Fail __error
| Done v_s1 ->
(Done ((I.Typing ((I.f_pure ((M.VariableTy (v_next)))), v_s1)))))))
and (* monomorph.bend:829 *)
f_candidate : (Base.text) option -> (I.t_Binding) list -> M.t_Ty -> M.t_Ty -> I.t_State -> Base.text -> (M.t_Diagnostic, I.t_Typing) Base.result_ =
fun v_name v_bindings v_left v_right v_state v_subject ->
(match v_name with
| None ->
(Fail ((M.Diagnostic (s_23, v_subject, s_24))))
| (Some (v_name)) ->
(f_candidate_binding ((I.f_lookup_binding (v_bindings) (v_name))) (v_name) (v_left) (v_right) (v_state) (v_subject)))
and (* monomorph.bend:836 *)
f_candidate_error : (M.t_Diagnostic, I.t_Typing) Base.result_ -> Base.text =
fun v_candidate ->
(match v_candidate with
| (Done (v_value)) ->
s_25
| (Fail ((M.Diagnostic (v_code, v_subject, v_message)))) ->
v_message)
and (* monomorph.bend:843 *)
f_choose_right : (M.t_Diagnostic, I.t_Typing) Base.result_ -> (Base.text) option -> Base.text -> Base.text -> (M.t_Diagnostic, Base.text) Base.result_ =
fun v_right v_name v_subject v_description ->
(match (v_right, v_name) with
| ((Done (v_value)), (Some (v_name))) ->
(Done (v_name))
| (v_other, _) ->
(Fail ((M.Diagnostic (s_26, v_subject, (Base.string_append v_description (Base.string_append s_27 (f_candidate_error (v_other)))))))))
and (* monomorph.bend:850 *)
f_chosen : (M.t_Diagnostic, I.t_Typing) Base.result_ -> (Base.text) option -> (M.t_Diagnostic, I.t_Typing) Base.result_ -> (Base.text) option -> Base.text -> Base.text -> (M.t_Diagnostic, Base.text) Base.result_ =
fun v_left v_left_name v_right v_right_name v_subject v_description ->
(match (v_left, v_left_name) with
| ((Done (v_value)), (Some (v_name))) ->
(Done (v_name))
| (v_other, _) ->
(f_choose_right (v_right) (v_right_name) (v_subject) ((Base.string_append v_description (Base.string_append s_28 (f_candidate_error (v_other)))))))
and (* monomorph.bend:866 *)
f_choice : (t_Choice) Base.map -> int -> (t_Choice) option =
fun v_choices v_wanted ->
(Index.f_find (v_choices) ((Base.nat_show (v_wanted))))
and (* monomorph.bend:869 *)
f_qualified_key : int -> Base.text =
fun v_site ->
(Base.string_append s_29 (Base.nat_show (v_site)))
and (* monomorph.bend:872 *)
f_qualified_choice : (t_Choice) Base.map -> int -> (t_Choice) option =
fun v_choices v_site ->
(Index.f_find (v_choices) ((f_qualified_key (v_site))))
and (* monomorph.bend:875 *)
f_solved_predicates : (t_Choice) option -> (M.t_Predicate) list =
fun v_found ->
(match v_found with
| (Some ((QualifiedChoice (v_solved, v_answers)))) ->
v_solved
| _ ->
[])
and (* monomorph.bend:882 *)
f_qualified_solved_work : (M.t_Predicate) list -> M.t_Predicate -> bool =
fun v_solved v_wanted ->
(match v_solved with
| [] ->
false
| (v_head :: v_tail) ->
(Base.bool_or ((C.f_same_predicate (v_head) (v_wanted))) ((f_qualified_solved_work (v_tail) (v_wanted)))))
and (* monomorph.bend:889 *)
f_qualified_solved : (t_Choice) Base.map -> int -> M.t_Predicate -> bool =
fun v_choices v_site v_predicate ->
(f_qualified_solved_work ((f_solved_predicates ((f_qualified_choice (v_choices) (v_site))))) (v_predicate))
and (* monomorph.bend:892 *)
f_qualified_answers : (t_Choice) option -> (C.t_EvidenceAnswer) list =
fun v_found ->
(match v_found with
| (Some ((QualifiedChoice (v_solved, v_answers)))) ->
v_answers
| _ ->
[])
and (* monomorph.bend:899 *)
f_remember_answer : t_Specialization -> t_Specialization -> int -> M.t_Predicate -> C.t_EvidenceAnswer -> t_Specialization =
fun v_previous v_selected v_site v_original v_answer ->
(let (Specialization (v_original_module, v_original_environment, v_choices, v_original_next, v_original_certificates)) = v_previous in
(let (Specialization (v_module, v_environment, v_selected_choices, v_next, v_certificates)) = v_selected in
(let v_solved = (f_solved_predicates ((f_qualified_choice (v_choices) (v_site)))) in
(let v_answers = (f_qualified_answers ((f_qualified_choice (v_choices) (v_site)))) in
(Specialization (v_module, v_environment, (Base.map_set (v_choices) ((f_qualified_key (v_site))) ((QualifiedChoice ((v_original :: v_solved), (v_answer :: v_answers))))), v_next, v_certificates))))))
and (* monomorph.bend:910 *)
f_field_owner : M.t_Ty -> Base.text -> Base.text -> M.t_Ty -> (M.t_Diagnostic, C.t_Evidence) Base.result_ =
fun v_receiver v_member v_accessor v_signature ->
(match v_receiver with
| (M.AppliedTy (v_identity, v_arguments)) ->
(Done ((C.SelectedField (v_identity, v_member, v_accessor, v_signature))))
| _ ->
(Fail ((M.Diagnostic (s_0, v_member, s_30)))))
and (* monomorph.bend:917 *)
f_receiver_evidence : bool -> M.t_Ty -> Base.text -> Base.text -> M.t_Ty -> (M.t_Diagnostic, C.t_Evidence) Base.result_ =
fun v_field v_receiver v_member v_name v_signature ->
(match v_field with
| true ->
(f_field_owner (v_receiver) (v_member) (v_name) (v_signature))
| false ->
(Done ((C.SelectedFunction (v_name, v_signature)))))
and (* monomorph.bend:924 *)
f_qualified_evidence : M.t_Predicate -> (t_Choice) option -> (M.t_DataType) list -> (M.t_Diagnostic, C.t_Evidence) Base.result_ =
fun v_predicate v_found v_types ->
(match (v_predicate, v_found) with
| ((M.FieldPredicate (v_member, v_receiver, v_result)), (Some ((ReceiverChoice (v_name, v_signature))))) ->
(f_field_owner (v_receiver) (v_member) (v_name) (v_signature))
| ((M.UpdatePredicate (v_member, v_receiver, v_assigned, v_result, v_invocation)), (Some ((FunctionChoice (v_name, v_signature))))) ->
(f_field_owner (v_receiver) (v_member) (v_name) (v_signature))
| ((M.OperationPredicate (v_template, v_arguments, v_function_type)), (Some ((OperationChoice (v_identity, v_signature))))) ->
(Done ((C.SelectedOperation (v_identity, v_signature))))
| ((M.AssociatedPredicate (v_member, v_templates, v_left, v_right, v_result, v_invocation)), (Some ((FunctionChoice (v_name, v_signature))))) ->
(Done ((C.SelectedFunction (v_name, v_signature))))
| ((M.ReceiverPredicate (v_member, v_templates, v_receiver, v_argument, v_result, v_invocation)), (Some ((ReceiverChoice (v_name, v_signature))))) ->
(f_receiver_evidence ((Members.f_has_field ((Members.f_constructors (v_receiver) (v_types))) (v_member))) (v_receiver) (v_member) (v_name) (v_signature))
| (_, _) ->
(Fail ((M.Diagnostic (s_0, s_1, s_31)))))
and (* monomorph.bend:939 *)
f_evidence_signature : C.t_Evidence -> (M.t_Ty) option =
fun v_evidence ->
(match v_evidence with
| (C.SelectedFunction (v_name, v_signature)) ->
(Some (v_signature))
| (C.SelectedField (v_owner, v_member, v_accessor, v_signature)) ->
(Some (v_signature))
| (C.SelectedOperation (v_identity, v_signature)) ->
(Some (v_signature))
| _ ->
None)
and (* monomorph.bend:950 *)
f_require_closed_evidence : (int) list -> Base.text -> (M.t_Diagnostic, unit) Base.result_ =
fun v_free v_subject ->
(match v_free with
| [] ->
(Done (()))
| (v_head :: v_tail) ->
(Fail ((M.Diagnostic (s_32, v_subject, s_33)))))
and (* monomorph.bend:957 *)
f_validate_evidence_found : (M.t_Ty) option -> Base.text -> (M.t_Diagnostic, unit) Base.result_ =
fun v_found v_subject ->
(match v_found with
| None ->
(Done (()))
| (Some (v_signature)) ->
(match (T.f_free (v_signature)) with
| Fail __error -> Fail __error
| Done v_free ->
(f_require_closed_evidence (v_free) (v_subject))))
and (* monomorph.bend:966 *)
f_validate_evidence : C.t_Evidence -> Base.text -> (M.t_Diagnostic, unit) Base.result_ =
fun v_evidence v_subject ->
(f_validate_evidence_found ((f_evidence_signature (v_evidence))) (v_subject))
and (* monomorph.bend:969 *)
f_selected_qualified_answer : t_Specialization -> int -> M.t_Predicate -> (M.t_Diagnostic, C.t_EvidenceAnswer) Base.result_ =
fun v_selected v_site v_predicate ->
(let (Specialization ((M.Module (v_constants, v_functions, v_types, v_operations)), v_environment, v_choices, v_next, v_certificates)) = v_selected in
(match (C.f_resolve ((I.f_substitutions_of ((G.f_env_state (v_environment))))) (v_predicate)) with
| Fail __error -> Fail __error
| Done v_resolved ->
(match (f_qualified_evidence (v_resolved) ((f_choice (v_choices) (v_site))) (v_types)) with
| Fail __error -> Fail __error
| Done v_evidence ->
(Done ((C.EvidenceAnswer (v_resolved, v_evidence)))))))
and (* monomorph.bend:976 *)
f_identity_at_subject : (M.t_Diagnostic, Base.text) Base.result_ -> Base.text -> (M.t_Diagnostic, unit) Base.result_ =
fun v_found v_subject ->
(match v_found with
| (Done (v_key)) ->
(Done (()))
| (Fail ((M.Diagnostic (v_code, v_old_subject, v_message)))) ->
(Fail ((M.Diagnostic (v_code, v_subject, v_message)))))
and (* monomorph.bend:983 *)
f_direct_qualified_answer : M.t_Predicate -> Base.text -> (M.t_Diagnostic, C.t_EvidenceAnswer) Base.result_ =
fun v_predicate v_subject ->
(match v_predicate with
| (M.TypeRepPredicate (v_represented)) ->
(match (f_identity_at_subject ((State.f_type_key (65536) ((State.TypeKey (v_represented))))) (v_subject)) with
| Fail __error -> Fail __error
| Done v_valid ->
(Done ((C.EvidenceAnswer (v_predicate, (C.RepresentedType (v_represented)))))))
| (M.EffectRepPredicate (v_row)) ->
(match (f_identity_at_subject ((State.f_row_key (v_row))) (v_subject)) with
| Fail __error -> Fail __error
| Done v_valid ->
(Done ((C.EvidenceAnswer (v_predicate, (C.RepresentedEffect ((Rows.f_canonical (v_row)))))))))
| _ ->
(Fail ((M.Diagnostic (s_0, s_1, s_34)))))
and (* monomorph.bend:996 *)
f_selected_qualified : t_Specialization -> t_Specialization -> int -> M.t_Predicate -> (M.t_Diagnostic, t_Specialization) Base.result_ =
fun v_previous v_selected v_site v_original ->
(match (f_selected_qualified_answer (v_selected) (v_site) (v_original)) with
| Fail __error -> Fail __error
| Done v_answer ->
(Done ((f_remember_answer (v_previous) (v_selected) (v_site) (v_original) (v_answer)))))
and (* monomorph.bend:1001 *)
f_requirements_reversed : (I.t_Coverage) list -> (I.t_Coverage) list -> (I.t_Coverage) list =
fun v_constraints v_reversed ->
(match v_constraints with
| [] ->
(Base.list_reverse (v_reversed))
| ((I.OperationNeed (v_identity, v_template, v_arguments, v_function_type, v_subject)) :: v_tail) ->
(f_requirements_reversed (v_tail) (((I.OperationNeed (v_identity, v_template, v_arguments, v_function_type, v_subject)) :: v_reversed)))
| ((I.AssociatedNeed (v_identity, v_dispatch, v_member, v_templates, v_left, v_right, v_result, v_invocation, v_ambient, v_subject)) :: v_tail) ->
(f_requirements_reversed (v_tail) (((I.AssociatedNeed (v_identity, v_dispatch, v_member, v_templates, v_left, v_right, v_result, v_invocation, v_ambient, v_subject)) :: v_reversed)))
| ((I.QualifiedNeed (v_site, v_predicate, v_subject)) :: v_tail) ->
(f_requirements_reversed (v_tail) (((I.QualifiedNeed (v_site, v_predicate, v_subject)) :: v_reversed)))
| (v_head :: v_tail) ->
(f_requirements_reversed (v_tail) (v_reversed)))
and (* monomorph.bend:1014 *)
f_requirements : (I.t_Coverage) list -> (I.t_Coverage) list =
fun v_constraints ->
(f_requirements_reversed (v_constraints) ([]))
and (* monomorph.bend:1017 *)
f_definition_uses : (I.t_Definition) list -> (C.t_UsePlan) list =
fun v_definitions ->
(match v_definitions with
| [] ->
[]
| ((I.Definition (v_name, v_inference)) :: v_tail) ->
(Base.list_append ((I.f_inference_uses (v_inference))) ((f_definition_uses (v_tail)))))
and (* monomorph.bend:1024 *)
f_pending : G.t_Environment -> (I.t_Coverage) list =
fun v_environment ->
(f_requirements ((Base.list_append ((Check.f_coverage_constraints ((G.f_env_definitions (v_environment))))) ((I.f_execution_needs ((f_definition_uses ((G.f_env_definitions (v_environment))))))))))
and (* monomorph.bend:1027 *)
f_reference_name : M.t_Expr -> (M.t_Diagnostic, Base.text) Base.result_ =
fun v_expression ->
(match v_expression with
| (M.FunctionExpr (v_name)) ->
(Done (v_name))
| _ ->
(Fail ((M.Diagnostic (s_0, s_1, s_35)))))
and (* monomorph.bend:1034 *)
f_select_associated : I.t_Coverage -> M.t_Ty -> M.t_Ty -> t_Specialization -> t_Configuration -> (I.t_Binding) list -> (Staging.t_Scheme) list -> (M.t_Diagnostic, t_Specialization) Base.result_ =
fun v_need v_left v_right v_specialization v_configuration v_shapes v_schemes ->
(match (v_need, v_specialization) with
| ((I.AssociatedNeed (v_identity, v_dispatch, v_member, v_effect_templates, v_old_left, v_old_right, v_result, v_invocation, v_ambient, v_subject)), (Specialization ((M.Module (v_constants, v_original_functions, v_types, v_operations)), v_environment, v_choices, v_counter, v_certificates))) ->
(let (Configuration (v_originals, v_templates, v_entry, v_locals, v_affected, v_stride, v_constant_values, v_family_templates, v_step, v_schema)) = v_configuration in
(let v_state = (G.f_env_state (v_environment)) in
(let v_left_name = (f_member_name ((f_owner (v_left) (v_entry))) (v_member)) in
(let v_right_name = (f_member_name ((f_owner (v_right) (v_entry))) (v_member)) in
(match (f_chosen ((f_candidate (v_left_name) (v_shapes) (v_left) (v_right) (v_state) (v_subject))) (v_left_name) ((f_candidate (v_right_name) (v_shapes) (v_left) (v_right) (v_state) (v_subject))) (v_right_name) (v_subject) ((Base.string_append s_36 (Base.string_append v_member (Base.string_append s_37 (Base.string_append (M.f_type_show (v_left)) (Base.string_append s_38 (M.f_type_show (v_right))))))))) with
| Fail __error -> Fail __error
| Done v_selected ->
(match (f_expand (65536) ((Expression ((M.FunctionExpr (v_selected))))) (v_configuration) ([]) (0) (v_counter)) with
| Fail __error -> Fail __error
| Done v_expanded ->
(match (f_one ((f_expressions (v_expanded)))) with
| Fail __error -> Fail __error
| Done v_reference ->
(match (f_reference_name (v_reference)) with
| Fail __error -> Fail __error
| Done v_name ->
(let v_all_functions = (Base.list_append (v_original_functions) ((f_functions (v_expanded)))) in
(match (f_infer_pending_optional ((Base.list_append ((G.f_function_declarations ((f_functions (v_expanded))))) ((G.f_constant_declarations ((f_emitted_constants (v_expanded))))))) (v_shapes) (v_environment) (v_operations) (v_types) ((G.f_function_names ((G.f_function_declarations ((Base.list_append (v_originals) (v_all_functions))))))) (v_schemes) (v_stride)) with
| Fail __error -> Fail __error
| Done v_inferred ->
(match (I.f_instantiate_binding_selected ((I.f_lookup_binding ((G.f_env_bindings (v_inferred))) (v_name))) ((G.f_env_state (v_inferred))) (v_name) (v_subject)) with
| Fail __error -> Fail __error
| Done v_selected_instance ->
(let v_target = (I.f_selected_typing (v_selected_instance)) in
(match (I.f_unify ((I.f_type_of (v_target))) ((M.FunctionTy (v_left, (M.FunctionTy (v_right, v_result, v_ambient)), v_ambient))) ((I.f_state_of (v_target))) (v_subject)) with
| Fail __error -> Fail __error
| Done v_unified ->
(match (T.f_resolve ((I.f_substitutions_of (v_unified))) ((I.f_selected_exact (v_selected_instance)))) with
| Fail __error -> Fail __error
| Done v_signature ->
(Done ((Specialization ((M.Module ((Base.list_append (v_constants) ((f_emitted_constants (v_expanded)))), v_all_functions, v_types, v_operations)), (G.Environment ((G.f_env_bindings (v_inferred)), (G.f_env_definitions (v_inferred)), v_unified)), (Base.map_set (v_choices) ((Base.nat_show (v_identity))) ((FunctionChoice (v_name, v_signature)))), (f_next (v_expanded)), v_certificates))))))))))))))))))
| (_, _) ->
(Fail ((M.Diagnostic (s_0, s_1, s_39)))))
and (* monomorph.bend:1056 *)
f_required_method : (I.t_Binding) option -> Base.text -> Base.text -> (M.t_Diagnostic, Base.text) Base.result_ =
fun v_found v_name v_subject ->
(match v_found with
| (Some (v_binding)) ->
(Done (v_name))
| None ->
(Fail ((M.Diagnostic (s_40, v_subject, (Base.string_append s_41 v_name))))))
and (* monomorph.bend:1063 *)
f_receiver_method_name : (Base.text) option -> (I.t_Binding) list -> Base.text -> (M.t_Diagnostic, Base.text) Base.result_ =
fun v_name v_bindings v_subject ->
(match v_name with
| None ->
(Fail ((M.Diagnostic (s_42, v_subject, s_43))))
| (Some (v_name)) ->
(f_required_method ((I.f_lookup_binding (v_bindings) (v_name))) (v_name) (v_subject)))
and (* monomorph.bend:1070 *)
f_receiver_method : (Base.text) option -> Base.text -> (I.t_Binding) list -> Base.text -> (M.t_Diagnostic, Base.text) Base.result_ =
fun v_owner v_member v_bindings v_subject ->
(f_receiver_method_name ((f_member_name (v_owner) (v_member))) (v_bindings) (v_subject))
and (* monomorph.bend:1073 *)
f_receiver_signature : M.t_Dispatch -> M.t_Ty -> M.t_Ty -> M.t_Ty -> M.t_EffectRow -> M.t_Ty =
fun v_dispatch v_left v_right v_result v_ambient ->
(match v_dispatch with
| M.MemberDispatch ->
(M.FunctionTy (v_left, v_result, v_ambient))
| _ ->
(M.FunctionTy (v_left, (M.FunctionTy (v_right, v_result, v_ambient)), v_ambient)))
and (* monomorph.bend:1080 *)
f_receiver_choice : M.t_Dispatch -> Base.text -> M.t_Ty -> t_Choice =
fun v_dispatch v_name v_signature ->
(match v_dispatch with
| M.MemberDispatch ->
(ReceiverChoice (v_name, v_signature))
| _ ->
(FunctionChoice (v_name, v_signature)))
and (* monomorph.bend:1087 *)
f_infer_generated : M.t_Function -> G.t_Environment -> (M.t_Operation) list -> (M.t_DataType) list -> (Base.text) list -> (M.t_Diagnostic, G.t_Environment) Base.result_ =
fun v_function v_environment v_operations v_types v_names ->
(let (G.Environment (v_bindings, v_definitions, v_state)) = v_environment in
(let v_declarations = (G.f_function_declarations ([v_function])) in
(let v_start = (I.f_next_of (v_state)) in
(let v_created = (G.f_initial_bindings (v_declarations) (v_start)) in
(match (G.f_infer_component ((G.f_names (v_declarations))) (v_declarations) ((G.Environment ((Base.list_append (v_created) (v_bindings)), v_definitions, (I.f_with_next (v_state) ((G.f_initial_next (v_declarations) (v_start))))))) (v_operations) (v_types) (v_names)) with
| Fail __error -> Fail __error
| Done v_inferred ->
(match (D.f_function_nodes ([v_function])) with
| Fail __error -> Fail __error
| Done v_nodes ->
(G.f_generalize_component (v_inferred) ((G.f_names (v_declarations))) (v_operations) (v_types) (v_nodes))))))))
and (* monomorph.bend:1097 *)
f_select_method_original : I.t_Coverage -> M.t_Ty -> M.t_Ty -> t_Specialization -> t_Configuration -> (I.t_Binding) list -> (Staging.t_Scheme) list -> (M.t_Diagnostic, t_Specialization) Base.result_ =
fun v_need v_left v_right v_specialization v_configuration v_shapes v_schemes ->
(match (v_need, v_specialization) with
| ((I.AssociatedNeed (v_identity, v_dispatch, v_member, v_templates, v_old_left, v_old_right, v_result, v_invocation, v_ambient, v_subject)), (Specialization ((M.Module (v_constants, v_original_functions, v_types, v_operations)), v_environment, v_choices, v_counter, v_certificates))) ->
(let (Configuration (v_originals, v_templates, v_entry, v_locals, v_affected, v_stride, v_constant_values, v_family_templates, v_step, v_schema)) = v_configuration in
(match (f_receiver_method ((f_owner (v_left) (v_entry))) (v_member) (v_shapes) (v_subject)) with
| Fail __error -> Fail __error
| Done v_selected ->
(match (f_expand (65536) ((Expression ((M.FunctionExpr (v_selected))))) (v_configuration) ([]) (0) (v_counter)) with
| Fail __error -> Fail __error
| Done v_expanded ->
(match (f_one ((f_expressions (v_expanded)))) with
| Fail __error -> Fail __error
| Done v_reference ->
(match (f_reference_name (v_reference)) with
| Fail __error -> Fail __error
| Done v_name ->
(let v_all_functions = (Base.list_append (v_original_functions) ((f_functions (v_expanded)))) in
(match (f_infer_pending_optional ((Base.list_append ((G.f_function_declarations ((f_functions (v_expanded))))) ((G.f_constant_declarations ((f_emitted_constants (v_expanded))))))) (v_shapes) (v_environment) (v_operations) (v_types) ((G.f_function_names ((G.f_function_declarations ((Base.list_append (v_originals) (v_all_functions))))))) (v_schemes) (v_stride)) with
| Fail __error -> Fail __error
| Done v_inferred ->
(match (I.f_instantiate_binding_selected ((I.f_lookup_binding ((G.f_env_bindings (v_inferred))) (v_name))) ((G.f_env_state (v_inferred))) (v_name) (v_subject)) with
| Fail __error -> Fail __error
| Done v_selected_instance ->
(let v_target = (I.f_selected_typing (v_selected_instance)) in
(match (I.f_unify ((I.f_type_of (v_target))) ((f_receiver_signature (v_dispatch) (v_left) (v_right) (v_result) (v_ambient))) ((I.f_state_of (v_target))) (v_subject)) with
| Fail __error -> Fail __error
| Done v_unified ->
(match (T.f_resolve ((I.f_substitutions_of (v_unified))) ((I.f_selected_exact (v_selected_instance)))) with
| Fail __error -> Fail __error
| Done v_signature ->
(Done ((Specialization ((M.Module ((Base.list_append (v_constants) ((f_emitted_constants (v_expanded)))), v_all_functions, v_types, v_operations)), (G.Environment ((G.f_env_bindings (v_inferred)), (G.f_env_definitions (v_inferred)), v_unified)), (Base.map_set (v_choices) ((Base.nat_show (v_identity))) ((f_receiver_choice (v_dispatch) (v_name) (v_signature)))), (f_next (v_expanded)), v_certificates)))))))))))))))
| (_, _) ->
(Fail ((M.Diagnostic (s_0, s_44, s_45)))))
and (* monomorph.bend:1120 *)
f_schema_proofs : t_Configuration -> (Schema.t_Evidence) list =
fun v_configuration ->
(let (Configuration (v_functions, v_templates, v_entry, v_locals, v_affected, v_stride, v_constant_values, v_family_templates, v_step, v_schema)) = v_configuration in
v_schema)
and (* monomorph.bend:1124 *)
f_schema_answer_type : (M.t_Diagnostic, M.t_Ty) Base.result_ -> (Schema.t_Evidence) list -> Base.text -> Base.text -> M.t_Ty -> (M.t_Function) list -> (M.t_DataType) list -> (bool) option =
fun v_found v_proofs v_selected v_member v_left v_functions v_types ->
(match v_found with
| (Fail (v_diagnostic)) ->
None
| (Done (v_resolved)) ->
(Schema.f_decide (v_proofs) (v_selected) (v_member) (v_left) (v_resolved) (v_functions) (v_types)))
and (* monomorph.bend:1131 *)
f_schema_answer_method : (M.t_Diagnostic, Base.text) Base.result_ -> (Schema.t_Evidence) list -> Base.text -> M.t_Ty -> M.t_Ty -> G.t_Environment -> (M.t_Function) list -> (M.t_DataType) list -> (bool) option =
fun v_found v_proofs v_member v_left v_result v_environment v_functions v_types ->
(match v_found with
| (Fail (v_diagnostic)) ->
None
| (Done (v_selected)) ->
(f_schema_answer_type ((T.f_resolve ((I.f_substitutions_of ((G.f_env_state (v_environment))))) (v_result))) (v_proofs) (v_selected) (v_member) (v_left) (v_functions) (v_types)))
and (* monomorph.bend:1138 *)
f_schema_answer_ready : bool -> (Schema.t_Evidence) list -> Base.text -> M.t_Ty -> M.t_Ty -> t_Specialization -> t_Configuration -> (I.t_Binding) list -> Base.text -> (bool) option =
fun v_eligible v_proofs v_member v_left v_result v_specialization v_configuration v_shapes v_subject ->
(match v_eligible with
| false ->
None
| true ->
(let (Specialization ((M.Module (v_constants, v_functions, v_types, v_operations)), v_environment, v_choices, v_counter, v_certificates)) = v_specialization in
(let (Configuration (v_originals, v_templates, v_entry, v_locals, v_affected, v_stride, v_constant_values, v_family_templates, v_step, v_schema)) = v_configuration in
(f_schema_answer_method ((f_receiver_method ((f_owner (v_left) (v_entry))) (v_member) (v_shapes) (v_subject))) (v_proofs) (v_member) (v_left) (v_result) (v_environment) (v_originals) (v_types)))))
and (* monomorph.bend:1147 *)
f_schema_answer : (Schema.t_Evidence) list -> Base.text -> M.t_Ty -> M.t_Ty -> t_Specialization -> t_Configuration -> (I.t_Binding) list -> Base.text -> (bool) option =
fun v_proofs v_member v_left v_result v_specialization v_configuration v_shapes v_subject ->
(f_schema_answer_ready ((Schema.f_eligible (v_proofs) (v_member) (v_left))) (v_proofs) (v_member) (v_left) (v_result) (v_specialization) (v_configuration) (v_shapes) (v_subject))
and (* monomorph.bend:1150 *)
f_schema_space_counter : bool -> int -> int -> int -> bool =
fun v_within v_counter v_stride v_step ->
(match v_within with
| false ->
false
| true ->
(Base.bool_and ((Base.nat_is_le (v_counter) ((Base.nat_div ((Staging.f_max_nat48 ())) (v_stride))))) ((Base.nat_is_le (v_step) ((Base.nat_sub ((Staging.f_max_nat48 ())) (v_counter)))))))
and (* monomorph.bend:1157 *)
f_schema_space : int -> int -> int -> bool =
fun v_counter v_stride v_step ->
(match v_stride with
| 0 ->
false
| __nat_38 when __nat_38 >= 1 ->
(let v_remaining = (__nat_38 - 1) in
(f_schema_space_counter ((Base.nat_is_le (v_counter) ((Staging.f_max_nat48 ())))) (v_counter) (v_stride) (v_step))))
and (* monomorph.bend:1164 *)
f_schema_fresh_space : G.t_Environment -> bool =
fun v_environment ->
(Base.nat_is_le ((I.f_next_of ((G.f_env_state (v_environment))))) ((Base.nat_sub ((Staging.f_max_nat48 ())) (65536))))
and (* monomorph.bend:1169 *)
f_schema_outcome : (M.t_Diagnostic, t_Specialization) Base.result_ -> (t_Specialization) option =
fun v_value ->
(match v_value with
| (Done (v_selected)) ->
(Some (v_selected))
| (Fail (v_diagnostic)) ->
None)
and (* monomorph.bend:1176 *)
f_schema_name_free : (M.t_Diagnostic, M.t_Function) Base.result_ -> bool =
fun v_found ->
(match v_found with
| (Fail (v_diagnostic)) ->
true
| (Done (v_function)) ->
false)
and (* monomorph.bend:1183 *)
f_schema_generated : Base.text -> bool -> int -> M.t_Dispatch -> Base.text -> M.t_Ty -> M.t_Ty -> M.t_Ty -> M.t_EffectRow -> Base.text -> t_Specialization -> t_Configuration -> (M.t_Diagnostic, t_Specialization) Base.result_ =
fun v_name v_answer v_identity v_dispatch v_member v_left v_right v_result v_ambient v_subject v_specialization v_configuration ->
(let (Specialization ((M.Module (v_constants, v_functions, v_types, v_operations)), v_environment, v_choices, v_counter, v_certificates)) = v_specialization in
(let (Configuration (v_originals, v_templates, v_entry, v_locals, v_affected, v_stride, v_constant_values, v_family_templates, v_step, v_schema)) = v_configuration in
(let v_generated = (M.Function (v_name, false, s_46, None, None, (M.LambdaExpr ((Base.nat_mul (v_counter) (v_stride)), s_47, None, None, (M.BoolExpr (v_answer)))))) in
(let v_all_functions = (Base.list_append (v_functions) ([v_generated])) in
(match (f_infer_generated (v_generated) (v_environment) (v_operations) (v_types) ((G.f_function_names ((G.f_function_declarations ((Base.list_append (v_originals) (v_all_functions)))))))) with
| Fail __error -> Fail __error
| Done v_inferred ->
(match (I.f_instantiate_binding_selected ((I.f_lookup_binding ((G.f_env_bindings (v_inferred))) (v_name))) ((G.f_env_state (v_inferred))) (v_name) (v_subject)) with
| Fail __error -> Fail __error
| Done v_selected_instance ->
(let v_target = (I.f_selected_typing (v_selected_instance)) in
(match (I.f_unify ((I.f_type_of (v_target))) ((f_receiver_signature (v_dispatch) (v_left) (v_right) (v_result) (v_ambient))) ((I.f_state_of (v_target))) (v_subject)) with
| Fail __error -> Fail __error
| Done v_unified ->
(match (T.f_resolve ((I.f_substitutions_of (v_unified))) ((I.f_selected_exact (v_selected_instance)))) with
| Fail __error -> Fail __error
| Done v_signature ->
(Done ((Specialization ((M.Module (v_constants, v_all_functions, v_types, v_operations)), (G.Environment ((G.f_env_bindings (v_inferred)), (G.f_env_definitions (v_inferred)), v_unified)), (Base.map_set (v_choices) ((Base.nat_show (v_identity))) ((f_receiver_choice (v_dispatch) (v_name) (v_signature)))), (Base.nat_add (v_counter) (v_step)), v_certificates)))))))))))))
and (* monomorph.bend:1196 *)
f_schema_choice_space : bool -> Base.text -> bool -> int -> M.t_Dispatch -> Base.text -> M.t_Ty -> M.t_Ty -> M.t_Ty -> M.t_EffectRow -> Base.text -> t_Specialization -> t_Configuration -> (t_Specialization) option =
fun v_fits v_name v_answer v_identity v_dispatch v_member v_left v_right v_result v_ambient v_subject v_specialization v_configuration ->
(match v_fits with
| false ->
None
| true ->
(f_schema_outcome ((f_schema_generated (v_name) (v_answer) (v_identity) (v_dispatch) (v_member) (v_left) (v_right) (v_result) (v_ambient) (v_subject) (v_specialization) (v_configuration)))))
and (* monomorph.bend:1203 *)
f_schema_choice : (bool) option -> int -> M.t_Dispatch -> Base.text -> M.t_Ty -> M.t_Ty -> M.t_Ty -> M.t_EffectRow -> Base.text -> t_Specialization -> t_Configuration -> (t_Specialization) option =
fun v_found v_identity v_dispatch v_member v_left v_right v_result v_ambient v_subject v_specialization v_configuration ->
(match (v_found, v_specialization, v_configuration) with
| (None, _, _) ->
None
| ((Some (v_answer)), v_specialization, v_configuration) ->
(let (Specialization ((M.Module (v_constants, v_functions, v_types, v_operations)), v_environment, v_choices, v_counter, v_certificates)) = v_specialization in
(let (Configuration (v_originals, v_templates, v_entry, v_locals, v_affected, v_stride, v_constant_values, v_family_templates, v_step, v_schema)) = v_configuration in
(let v_name = (Base.string_append s_48 (Base.string_append (Base.nat_show (v_counter)) (Base.string_append s_10 v_member))) in
(f_schema_choice_space ((Base.bool_and ((f_schema_space (v_counter) (v_stride) (v_step))) ((Base.bool_and ((f_schema_fresh_space (v_environment))) ((Base.bool_and ((f_schema_name_free ((f_lookup (v_functions) (v_name))))) ((Base.bool_and ((f_schema_name_free ((f_lookup (v_originals) (v_name))))) ((Base.bool_and ((Base.bool_not ((Base.maybe_is_some ((f_lookup_constant (v_constants) (v_name))))))) ((Base.bool_not ((Base.maybe_is_some ((f_lookup_constant (v_constant_values) (v_name))))))))))))))))) (v_name) (v_answer) (v_identity) (v_dispatch) (v_member) (v_left) (v_right) (v_result) (v_ambient) (v_subject) (v_specialization) (v_configuration))))))
and (* monomorph.bend:1213 *)
f_schema_method : I.t_Coverage -> M.t_Ty -> M.t_Ty -> t_Specialization -> t_Configuration -> (I.t_Binding) list -> (t_Specialization) option =
fun v_need v_left v_right v_specialization v_configuration v_shapes ->
(match v_need with
| (I.AssociatedNeed (v_identity, M.MemberDispatch, v_member, [], v_old_left, v_old_right, v_result, v_invocation, v_ambient, v_subject)) ->
(f_schema_choice ((f_schema_answer ((f_schema_proofs (v_configuration))) (v_member) (v_left) (v_result) (v_specialization) (v_configuration) (v_shapes) (v_subject))) (v_identity) (M.MemberDispatch) (v_member) (v_left) (v_right) (v_result) (v_ambient) (v_subject) (v_specialization) (v_configuration))
| _ ->
None)
and (* monomorph.bend:1220 *)
f_select_method_staged : (t_Specialization) option -> I.t_Coverage -> M.t_Ty -> M.t_Ty -> t_Specialization -> t_Configuration -> (I.t_Binding) list -> (Staging.t_Scheme) list -> (M.t_Diagnostic, t_Specialization) Base.result_ =
fun v_found v_need v_left v_right v_specialization v_configuration v_shapes v_schemes ->
(match v_found with
| (Some (v_selected)) ->
(Done (v_selected))
| None ->
(f_select_method_original (v_need) (v_left) (v_right) (v_specialization) (v_configuration) (v_shapes) (v_schemes)))
and (* monomorph.bend:1227 *)
f_select_method : I.t_Coverage -> M.t_Ty -> M.t_Ty -> t_Specialization -> t_Configuration -> (I.t_Binding) list -> (Staging.t_Scheme) list -> (M.t_Diagnostic, t_Specialization) Base.result_ =
fun v_need v_left v_right v_specialization v_configuration v_shapes v_schemes ->
(f_select_method_staged ((f_schema_method (v_need) (v_left) (v_right) (v_specialization) (v_configuration) (v_shapes))) (v_need) (v_left) (v_right) (v_specialization) (v_configuration) (v_shapes) (v_schemes))
and (* monomorph.bend:1239 *)
f_field_environment : t_FieldEvidence -> G.t_Environment =
fun v_value ->
(let (FieldEvidence (v_environment, v_certificates)) = v_value in
v_environment)
and (* monomorph.bend:1243 *)
f_field_certificates : t_FieldEvidence -> (Core.t_Certificate) list =
fun v_value ->
(let (FieldEvidence (v_environment, v_certificates)) = v_value in
v_certificates)
and (* monomorph.bend:1247 *)
f_field_fallback : M.t_Function -> G.t_Environment -> (M.t_Operation) list -> (M.t_DataType) list -> (Base.text) list -> (M.t_Diagnostic, t_FieldEvidence) Base.result_ =
fun v_function v_environment v_operations v_types v_names ->
(match (f_infer_generated (v_function) (v_environment) (v_operations) (v_types) (v_names)) with
| Fail __error -> Fail __error
| Done v_inferred ->
(Done ((FieldEvidence (v_inferred, [])))))
and (* monomorph.bend:1252 *)
f_field_import : (M.t_Diagnostic, G.t_Environment) Base.result_ -> M.t_Function -> M.t_Module -> Groups.t_CheckedGroup -> G.t_Environment -> (M.t_Operation) list -> (M.t_DataType) list -> (Base.text) list -> (M.t_Diagnostic, t_FieldEvidence) Base.result_ =
fun v_imported v_function v_module v_checked v_environment v_operations v_types v_names ->
(match v_imported with
| (Fail (v_diagnostic)) ->
(f_field_fallback (v_function) (v_environment) (v_operations) (v_types) (v_names))
| (Done ((G.Environment (v_new_bindings, v_new_definitions, v_imported_state)))) ->
(let (G.Environment (v_bindings, v_definitions, v_state)) = v_environment in
(Done ((FieldEvidence ((G.Environment ((Base.list_append (v_new_bindings) (v_bindings)), (Base.list_append (v_new_definitions) (v_definitions)), (I.f_with_next (v_state) ((I.f_next_of (v_imported_state)))))), [(Core.Certificate (v_module, v_checked, []))]))))))
and (* monomorph.bend:1260 *)
f_field_checked : (M.t_Diagnostic, Groups.t_CheckedGroup) Base.result_ -> M.t_Function -> M.t_Module -> G.t_Environment -> (M.t_Operation) list -> (M.t_DataType) list -> (Base.text) list -> (M.t_Diagnostic, t_FieldEvidence) Base.result_ =
fun v_result v_function v_module v_environment v_operations v_types v_names ->
(match v_result with
| (Fail (v_diagnostic)) ->
(f_field_fallback (v_function) (v_environment) (v_operations) (v_types) (v_names))
| (Done ((Groups.CheckedGroup (v_checked_module, v_interfaces, v_uses)))) ->
(f_field_import ((Groups.f_import_interfaces (v_interfaces) (v_operations) (v_types) ((I.f_next_of ((G.f_env_state (v_environment))))))) (v_function) (v_module) ((Groups.CheckedGroup (v_checked_module, v_interfaces, v_uses))) (v_environment) (v_operations) (v_types) (v_names)))
and (* monomorph.bend:1267 *)
f_infer_field_owner : (M.t_DataType) option -> M.t_Function -> G.t_Environment -> (M.t_Operation) list -> (M.t_DataType) list -> (Base.text) list -> (M.t_Diagnostic, t_FieldEvidence) Base.result_ =
fun v_found v_function v_environment v_operations v_types v_names ->
(match v_found with
| None ->
(f_field_fallback (v_function) (v_environment) (v_operations) (v_types) (v_names))
| (Some (v_owner)) ->
(let v_module = (M.Module ([], [v_function], [v_owner], [])) in
(f_field_checked ((Groups.f_check_group_planned (v_module) ([]))) (v_function) (v_module) (v_environment) (v_operations) (v_types) (v_names))))
and (* monomorph.bend:1275 *)
f_infer_field : M.t_Function -> M.t_Ty -> G.t_Environment -> (M.t_Operation) list -> (M.t_DataType) list -> (Base.text) list -> (M.t_Diagnostic, t_FieldEvidence) Base.result_ =
fun v_function v_receiver v_environment v_operations v_types v_names ->
(match v_receiver with
| (M.AppliedTy (v_identity, v_arguments)) ->
(f_infer_field_owner ((TD.f_lookup (v_types) (v_identity))) (v_function) (v_environment) (v_operations) (v_types) (v_names))
| v_other ->
(f_field_fallback (v_function) (v_environment) (v_operations) (v_types) (v_names)))
and (* monomorph.bend:1282 *)
f_select_field_site : I.t_Coverage -> M.t_Ty -> M.t_Ty -> t_Specialization -> t_Configuration -> (M.t_Diagnostic, t_Specialization) Base.result_ =
fun v_need v_left v_right v_specialization v_configuration ->
(match (v_need, v_specialization) with
| ((I.AssociatedNeed (v_identity, v_dispatch, v_member, v_templates, v_old_left, v_old_right, v_result, v_invocation, v_ambient, v_subject)), (Specialization ((M.Module (v_constants, v_functions, v_types, v_operations)), v_environment, v_choices, v_counter, v_certificates))) ->
(let (Configuration (v_originals, v_templates, v_entry, v_locals, v_affected, v_stride, v_constant_values, v_family_templates, v_step, v_schema)) = v_configuration in
(let v_name = (Base.string_append s_49 (Base.string_append (Base.nat_show (v_counter)) s_6)) in
(match (Members.f_function ((Members.f_constructors (v_left) (v_types))) (v_dispatch) (v_member) (v_name) ((Base.nat_mul (v_counter) (v_stride)))) with
| Fail __error -> Fail __error
| Done v_generated ->
(let v_all_functions = (Base.list_append (v_functions) ([v_generated])) in
(match (f_infer_field (v_generated) (v_left) (v_environment) (v_operations) (v_types) ((G.f_function_names ((G.f_function_declarations ((Base.list_append (v_originals) (v_all_functions)))))))) with
| Fail __error -> Fail __error
| Done v_field ->
(let v_inferred = (f_field_environment (v_field)) in
(let v_new_certificates = (f_field_certificates (v_field)) in
(match (I.f_instantiate_binding_selected ((I.f_lookup_binding ((G.f_env_bindings (v_inferred))) (v_name))) ((G.f_env_state (v_inferred))) (v_name) (v_subject)) with
| Fail __error -> Fail __error
| Done v_selected_instance ->
(let v_target = (I.f_selected_typing (v_selected_instance)) in
(match (I.f_unify ((I.f_type_of (v_target))) ((f_receiver_signature (v_dispatch) (v_left) (v_right) (v_result) (v_ambient))) ((I.f_state_of (v_target))) (v_subject)) with
| Fail __error -> Fail __error
| Done v_unified ->
(match (T.f_resolve ((I.f_substitutions_of (v_unified))) ((I.f_selected_exact (v_selected_instance)))) with
| Fail __error -> Fail __error
| Done v_signature ->
(Done ((Specialization ((M.Module (v_constants, v_all_functions, v_types, v_operations)), (G.Environment ((G.f_env_bindings (v_inferred)), (G.f_env_definitions (v_inferred)), v_unified)), (Base.map_set (v_choices) ((Base.nat_show (v_identity))) ((f_receiver_choice (v_dispatch) (v_name) (v_signature)))), (Base.nat_add (v_counter) (v_step)), (Base.list_append (v_new_certificates) (v_certificates)))))))))))))))))
| (_, _) ->
(Fail ((M.Diagnostic (s_0, s_50, s_51)))))
and (* monomorph.bend:1304 *)
f_accessor_name : Base.text -> Base.text -> M.t_Dispatch -> Base.text =
fun v_owner v_member v_dispatch ->
(match v_dispatch with
| M.FieldUpdateDispatch ->
(Base.string_append s_52 (Base.string_append v_owner (Base.string_append s_10 v_member)))
| _ ->
(Base.string_append s_49 (Base.string_append v_owner (Base.string_append s_10 v_member))))
and (* monomorph.bend:1311 *)
f_accessor_owner : (Base.text) option -> Base.text =
fun v_found ->
(match v_found with
| (Some (v_prefix)) ->
v_prefix
| None ->
s_11)
and (* monomorph.bend:1318 *)
f_function_name : M.t_Function -> Base.text =
fun v_function ->
(let (M.Function (v_name, v_exported, v_parameter, v_p, v_r, v_body)) = v_function in
v_name)
and (* monomorph.bend:1322 *)
f_function_exists : (M.t_Diagnostic, M.t_Function) Base.result_ -> bool =
fun v_found ->
(match v_found with
| (Done (v_function)) ->
true
| (Fail (v_diagnostic)) ->
false)
and (* monomorph.bend:1329 *)
f_reuse_field : Base.text -> I.t_Coverage -> M.t_Ty -> M.t_Ty -> t_Specialization -> t_Configuration -> (M.t_Diagnostic, t_Specialization) Base.result_ =
fun v_name v_need v_left v_right v_specialization v_configuration ->
(match (v_need, v_specialization) with
| ((I.AssociatedNeed (v_identity, v_dispatch, v_member, v_templates, v_old_left, v_old_right, v_result, v_invocation, v_ambient, v_subject)), (Specialization (v_module, v_environment, v_choices, v_counter, v_certificates))) ->
(let (Configuration (v_originals, v_configured, v_entry, v_locals, v_affected, v_stride, v_constant_values, v_family_templates, v_step, v_schema)) = v_configuration in
(match (I.f_instantiate_binding_selected ((I.f_lookup_binding ((G.f_env_bindings (v_environment))) (v_name))) ((G.f_env_state (v_environment))) (v_name) (v_subject)) with
| Fail __error -> Fail __error
| Done v_selected_instance ->
(let v_target = (I.f_selected_typing (v_selected_instance)) in
(match (I.f_unify ((I.f_type_of (v_target))) ((f_receiver_signature (v_dispatch) (v_left) (v_right) (v_result) (v_ambient))) ((I.f_state_of (v_target))) (v_subject)) with
| Fail __error -> Fail __error
| Done v_unified ->
(match (T.f_resolve ((I.f_substitutions_of (v_unified))) ((I.f_selected_exact (v_selected_instance)))) with
| Fail __error -> Fail __error
| Done v_signature ->
(Done ((Specialization (v_module, (G.Environment ((G.f_env_bindings (v_environment)), (G.f_env_definitions (v_environment)), v_unified)), (Base.map_set (v_choices) ((Base.nat_show (v_identity))) ((f_receiver_choice (v_dispatch) (v_name) (v_signature)))), (Base.nat_add (v_counter) (v_step)), v_certificates)))))))))
| (_, _) ->
(Fail ((M.Diagnostic (s_0, s_50, s_51)))))
and (* monomorph.bend:1345 *)
f_shared_field_import : (M.t_Diagnostic, G.t_Environment) Base.result_ -> M.t_Module -> Groups.t_CheckedGroup -> G.t_Environment -> (t_FieldEvidence) option =
fun v_imported v_module v_checked v_environment ->
(match v_imported with
| (Fail (v_diagnostic)) ->
None
| (Done ((G.Environment (v_new_bindings, v_new_definitions, v_imported_state)))) ->
(let (G.Environment (v_bindings, v_definitions, v_state)) = v_environment in
(Some ((FieldEvidence ((G.Environment ((Base.list_append (v_new_bindings) (v_bindings)), (Base.list_append (v_new_definitions) (v_definitions)), (I.f_with_next (v_state) ((I.f_next_of (v_imported_state)))))), [(Core.Certificate (v_module, v_checked, []))]))))))
and (* monomorph.bend:1353 *)
f_shared_field_checked : (M.t_Diagnostic, Groups.t_CheckedGroup) Base.result_ -> M.t_Module -> G.t_Environment -> (M.t_Operation) list -> (M.t_DataType) list -> (t_FieldEvidence) option =
fun v_result v_module v_environment v_operations v_types ->
(match v_result with
| (Fail (v_diagnostic)) ->
None
| (Done ((Groups.CheckedGroup (v_checked_module, v_interfaces, v_uses)))) ->
(f_shared_field_import ((Groups.f_import_interfaces (v_interfaces) (v_operations) (v_types) ((I.f_next_of ((G.f_env_state (v_environment))))))) (v_module) ((Groups.CheckedGroup (v_checked_module, v_interfaces, v_uses))) (v_environment)))
and (* monomorph.bend:1360 *)
f_shared_field_owner : (M.t_DataType) option -> M.t_Function -> G.t_Environment -> (M.t_Operation) list -> (M.t_DataType) list -> (t_FieldEvidence) option =
fun v_found v_function v_environment v_operations v_types ->
(match v_found with
| None ->
None
| (Some (v_owner)) ->
(let v_module = (M.Module ([], [v_function], [v_owner], [])) in
(f_shared_field_checked ((Groups.f_check_group_planned (v_module) ([]))) (v_module) (v_environment) (v_operations) (v_types))))
and (* monomorph.bend:1368 *)
f_shared_field_evidence : M.t_Function -> M.t_Ty -> G.t_Environment -> (M.t_Operation) list -> (M.t_DataType) list -> (t_FieldEvidence) option =
fun v_function v_receiver v_environment v_operations v_types ->
(match v_receiver with
| (M.AppliedTy (v_identity, v_arguments)) ->
(f_shared_field_owner ((TD.f_lookup (v_types) (v_identity))) (v_function) (v_environment) (v_operations) (v_types))
| v_other ->
None)
and (* monomorph.bend:1375 *)
f_create_field : (t_FieldEvidence) option -> M.t_Function -> I.t_Coverage -> M.t_Ty -> M.t_Ty -> t_Specialization -> t_Configuration -> (M.t_Diagnostic, t_Specialization) Base.result_ =
fun v_found v_generated v_need v_left v_right v_specialization v_configuration ->
(match (v_found, v_need, v_specialization) with
| (None, v_need, v_specialization) ->
(f_select_field_site (v_need) (v_left) (v_right) (v_specialization) (v_configuration))
| ((Some (v_field)), (I.AssociatedNeed (v_identity, v_dispatch, v_member, v_templates, v_old_left, v_old_right, v_result, v_invocation, v_ambient, v_subject)), (Specialization ((M.Module (v_constants, v_functions, v_types, v_operations)), v_environment, v_choices, v_counter, v_certificates))) ->
(let (Configuration (v_originals, v_configured, v_entry, v_locals, v_affected, v_stride, v_constant_values, v_family_templates, v_step, v_schema)) = v_configuration in
(let v_name = (f_function_name (v_generated)) in
(let v_inferred = (f_field_environment (v_field)) in
(match (I.f_instantiate_binding_selected ((I.f_lookup_binding ((G.f_env_bindings (v_inferred))) (v_name))) ((G.f_env_state (v_inferred))) (v_name) (v_subject)) with
| Fail __error -> Fail __error
| Done v_selected_instance ->
(let v_target = (I.f_selected_typing (v_selected_instance)) in
(match (I.f_unify ((I.f_type_of (v_target))) ((f_receiver_signature (v_dispatch) (v_left) (v_right) (v_result) (v_ambient))) ((I.f_state_of (v_target))) (v_subject)) with
| Fail __error -> Fail __error
| Done v_unified ->
(match (T.f_resolve ((I.f_substitutions_of (v_unified))) ((I.f_selected_exact (v_selected_instance)))) with
| Fail __error -> Fail __error
| Done v_signature ->
(Done ((Specialization ((M.Module (v_constants, (Base.list_append (v_functions) ([v_generated])), v_types, v_operations)), (G.Environment ((G.f_env_bindings (v_inferred)), (G.f_env_definitions (v_inferred)), v_unified)), (Base.map_set (v_choices) ((Base.nat_show (v_identity))) ((f_receiver_choice (v_dispatch) (v_name) (v_signature)))), (Base.nat_add (v_counter) (v_step)), (Base.list_append ((f_field_certificates (v_field))) (v_certificates)))))))))))))
| (_, _, _) ->
(Fail ((M.Diagnostic (s_0, s_50, s_51)))))
and (* monomorph.bend:1392 *)
f_generate_field : Base.text -> I.t_Coverage -> M.t_Ty -> M.t_Ty -> t_Specialization -> t_Configuration -> (M.t_Diagnostic, t_Specialization) Base.result_ =
fun v_name v_need v_left v_right v_specialization v_configuration ->
(match (v_need, v_specialization) with
| ((I.AssociatedNeed (v_identity, v_dispatch, v_member, v_templates, v_old_left, v_old_right, v_result, v_invocation, v_ambient, v_subject)), (Specialization ((M.Module (v_constants, v_functions, v_types, v_operations)), v_environment, v_choices, v_counter, v_certificates))) ->
(let (Configuration (v_originals, v_configured, v_entry, v_locals, v_affected, v_stride, v_constant_values, v_family_templates, v_step, v_schema)) = v_configuration in
(match (Members.f_function ((Members.f_constructors (v_left) (v_types))) (v_dispatch) (v_member) (v_name) ((Base.nat_mul (v_counter) (v_stride)))) with
| Fail __error -> Fail __error
| Done v_generated ->
(f_create_field ((f_shared_field_evidence (v_generated) (v_left) (v_environment) (v_operations) (v_types))) (v_generated) (v_need) (v_left) (v_right) (v_specialization) (v_configuration))))
| (_, _) ->
(Fail ((M.Diagnostic (s_0, s_50, s_51)))))
and (* monomorph.bend:1402 *)
f_select_field_shared : bool -> Base.text -> I.t_Coverage -> M.t_Ty -> M.t_Ty -> t_Specialization -> t_Configuration -> (M.t_Diagnostic, t_Specialization) Base.result_ =
fun v_exists v_name v_need v_left v_right v_specialization v_configuration ->
(match v_exists with
| true ->
(f_reuse_field (v_name) (v_need) (v_left) (v_right) (v_specialization) (v_configuration))
| false ->
(f_generate_field (v_name) (v_need) (v_left) (v_right) (v_specialization) (v_configuration)))
and (* monomorph.bend:1409 *)
f_select_field : I.t_Coverage -> M.t_Ty -> M.t_Ty -> t_Specialization -> t_Configuration -> (M.t_Diagnostic, t_Specialization) Base.result_ =
fun v_need v_left v_right v_specialization v_configuration ->
(match (v_need, v_specialization, v_configuration) with
| ((I.AssociatedNeed (v_identity, v_dispatch, v_member, v_templates, v_old_left, v_old_right, v_result, v_invocation, v_ambient, v_subject)), (Specialization ((M.Module (v_constants, v_functions, v_types, v_operations)), v_environment, v_choices, v_counter, v_certificates)), (Configuration (v_originals, v_configured, v_entry, v_locals, v_affected, v_stride, v_constant_values, v_family_templates, v_step, v_schema))) ->
(let v_name = (f_accessor_name ((f_accessor_owner ((f_owner (v_left) (v_entry))))) (v_member) (v_dispatch)) in
(f_select_field_shared ((Base.bool_or ((f_function_exists ((f_lookup (v_originals) (v_name))))) ((f_function_exists ((f_lookup (v_functions) (v_name))))))) (v_name) (v_need) (v_left) (v_right) (v_specialization) (v_configuration)))
| (_, _, _) ->
(Fail ((M.Diagnostic (s_0, s_50, s_51)))))
and (* monomorph.bend:1417 *)
f_select_receiver_found : bool -> (M.t_Diagnostic, Base.text) Base.result_ -> M.t_Dispatch -> Base.text -> Base.text -> I.t_Coverage -> M.t_Ty -> M.t_Ty -> t_Specialization -> t_Configuration -> (I.t_Binding) list -> (Staging.t_Scheme) list -> (M.t_Diagnostic, t_Specialization) Base.result_ =
fun v_field v_method v_dispatch v_member v_subject v_need v_left v_right v_specialization v_configuration v_shapes v_schemes ->
(match (v_field, v_method, v_dispatch) with
| (true, (Done (v_name)), M.MemberDispatch) ->
(Fail ((M.Diagnostic (s_53, v_subject, (Base.string_append s_54 v_member)))))
| (true, _, _) ->
(f_select_field (v_need) (v_left) (v_right) (v_specialization) (v_configuration))
| (false, _, M.FieldUpdateDispatch) ->
(Fail ((M.Diagnostic (s_55, v_subject, (Base.string_append s_56 (Base.string_append v_member (Base.string_append s_57 (M.f_type_show (v_left)))))))))
| (false, _, _) ->
(f_select_method (v_need) (v_left) (v_right) (v_specialization) (v_configuration) (v_shapes) (v_schemes)))
and (* monomorph.bend:1428 *)
f_select_receiver : I.t_Coverage -> M.t_Ty -> M.t_Ty -> t_Specialization -> t_Configuration -> (I.t_Binding) list -> (Staging.t_Scheme) list -> (M.t_Diagnostic, t_Specialization) Base.result_ =
fun v_need v_left v_right v_specialization v_configuration v_shapes v_schemes ->
(match (v_need, v_specialization, v_configuration) with
| ((I.AssociatedNeed (v_identity, v_dispatch, v_member, __shadow_39, v_old_left, v_old_right, v_result, v_invocation, v_ambient, v_subject)), (Specialization ((M.Module (v_constants, v_functions, v_types, v_operations)), v_environment, v_choices, v_counter, v_certificates)), (Configuration (v_originals, __shadow_40, v_entry, v_locals, v_affected, v_stride, v_constant_values, v_family_templates, v_step, v_schema))) ->
(let v_templates = __shadow_39 in
(let v_templates = __shadow_40 in
(f_select_receiver_found ((Members.f_has_field ((Members.f_constructors (v_left) (v_types))) (v_member))) ((f_receiver_method ((f_owner (v_left) (v_entry))) (v_member) (v_shapes) (v_subject))) (v_dispatch) (v_member) (v_subject) (v_need) (v_left) (v_right) (v_specialization) (v_configuration) (v_shapes) (v_schemes))))
| (_, _, _) ->
(Fail ((M.Diagnostic (s_0, s_44, s_58)))))
and (* monomorph.bend:1435 *)
f_polymorphic : int -> (M.t_Ty) list -> bool =
fun v_fuel v_pending ->
(match (v_fuel, v_pending) with
| (_, []) ->
false
| (0, _) ->
true
| (__nat_41, ((M.VariableTy (v_index)) :: v_tail)) when __nat_41 >= 1 ->
(let v_rest = (__nat_41 - 1) in
true)
| (__nat_42, ((M.ParameterTy (v_index)) :: v_tail)) when __nat_42 >= 1 ->
(let v_rest = (__nat_42 - 1) in
true)
| (__nat_43, ((M.FunctionTy (v_parameter, v_result, v_row)) :: v_tail)) when __nat_43 >= 1 ->
(let v_rest = (__nat_43 - 1) in
(f_polymorphic (v_rest) ((v_parameter :: (v_result :: v_tail)))))
| (__nat_44, ((M.AppliedTy (v_identity, v_arguments)) :: v_tail)) when __nat_44 >= 1 ->
(let v_rest = (__nat_44 - 1) in
(f_polymorphic (v_rest) ((Base.list_append (v_arguments) (v_tail)))))
| (__nat_45, ((M.ProductTy (v_elements)) :: v_tail)) when __nat_45 >= 1 ->
(let v_rest = (__nat_45 - 1) in
(f_polymorphic (v_rest) ((Base.list_append (v_elements) (v_tail)))))
| (__nat_46, ((M.ArrayTy (v_element)) :: v_tail)) when __nat_46 >= 1 ->
(let v_rest = (__nat_46 - 1) in
(f_polymorphic (v_rest) ((v_element :: v_tail))))
| (__nat_47, (v_head :: v_tail)) when __nat_47 >= 1 ->
(let v_rest = (__nat_47 - 1) in
(f_polymorphic (v_rest) (v_tail))))
and (* monomorph.bend:1459 *)
f_state_source_read : t_StateSource -> M.t_TypeId =
fun v_source ->
(let (StateSource (v_read, v_write, v_operations)) = v_source in
v_read)
and (* monomorph.bend:1463 *)
f_state_source_write : t_StateSource -> M.t_TypeId =
fun v_source ->
(let (StateSource (v_read, v_write, v_operations)) = v_source in
v_write)
and (* monomorph.bend:1467 *)
f_state_source_operations : t_StateSource -> (M.t_Operation) list =
fun v_source ->
(let (StateSource (v_read, v_write, v_operations)) = v_source in
v_operations)
and (* monomorph.bend:1471 *)
f_family_declaration_work : (M.t_Operation) list -> M.t_TypeId -> (M.t_Operation) option -> (M.t_Diagnostic, M.t_Operation) Base.result_ =
fun v_declarations v_wanted v_found ->
(match (v_declarations, v_found) with
| (_, (Some (v_declaration))) ->
(Done (v_declaration))
| ([], None) ->
(Fail ((M.Diagnostic (s_59, (M.f_type_id_show (v_wanted)), s_60))))
| (((M.OperationTemplate (v_identity, v_parameters, v_parameter, v_result)) :: v_tail), None) ->
(f_family_declaration_work (v_tail) (v_wanted) ((Base.bool_pick ((M.f_type_id_equal (v_identity) (v_wanted))) ((Some ((M.OperationTemplate (v_identity, v_parameters, v_parameter, v_result))))) (None))))
| ((v_head :: v_tail), None) ->
(f_family_declaration_work (v_tail) (v_wanted) (None)))
and (* monomorph.bend:1482 *)
f_family_declaration : (M.t_Operation) list -> M.t_TypeId -> (M.t_Diagnostic, M.t_Operation) Base.result_ =
fun v_declarations v_wanted ->
(f_family_declaration_work (v_declarations) (v_wanted) (None))
and (* monomorph.bend:1485 *)
f_family_arguments_declared : M.t_Operation -> M.t_TypeId -> (M.t_Ty) list -> (M.t_Diagnostic, M.t_Operation) Base.result_ =
fun v_declared v_wanted v_arguments ->
(match v_declared with
| (M.OperationTemplate ((M.TypeId (v_module_name, v_declaration)), v_parameters, v_parameter, v_result)) ->
(match (Base.bool_pick ((Base.nat_is_eq (v_parameters) ((Base.list_length (v_arguments))))) ((Done (()))) ((Fail ((M.Diagnostic (s_63, (M.f_type_id_show (v_wanted)), s_64)))))) with
| Fail __error -> Fail __error
| Done v_valid ->
(match (State.f_type_key (65536) ((State.TypesKey (v_arguments)))) with
| Fail __error -> Fail __error
| Done v_key ->
(match (T.f_parameters (v_arguments) (0) (v_parameter)) with
| Fail __error -> Fail __error
| Done v_specialized_parameter ->
(match (T.f_parameters (v_arguments) (0) (v_result)) with
| Fail __error -> Fail __error
| Done v_specialized_result ->
(Done ((M.Operation ((M.TypeId (v_module_name, (Base.string_append v_declaration (Base.string_append s_61 (Base.string_append v_key s_62))))), v_specialized_parameter, v_specialized_result))))))))
| _ ->
(Fail ((M.Diagnostic (s_0, (M.f_type_id_show (v_wanted)), s_65)))))
and (* monomorph.bend:1497 *)
f_family_instance : M.t_TypeId -> M.t_Ty -> (M.t_Operation) list -> (M.t_Diagnostic, M.t_Operation) Base.result_ =
fun v_wanted v_ty v_declarations ->
(match (f_family_declaration (v_declarations) (v_wanted)) with
| Fail __error -> Fail __error
| Done v_declared ->
(f_family_arguments_declared (v_declared) (v_wanted) ([v_ty])))
and (* monomorph.bend:1502 *)
f_family_identity : M.t_Operation -> (M.t_Diagnostic, M.t_TypeId) Base.result_ =
fun v_operation ->
(match v_operation with
| (M.Operation (v_identity, v_parameter, v_result)) ->
(Done (v_identity))
| _ ->
(Fail ((M.Diagnostic (s_0, s_66, s_67)))))
and (* monomorph.bend:1509 *)
f_single_family_source : M.t_TypeId -> M.t_Ty -> (M.t_Operation) list -> (M.t_Operation) list -> (M.t_Diagnostic, t_StateSource) Base.result_ =
fun v_template v_ty v_declarations v_existing ->
(match (f_family_instance (v_template) (v_ty) (v_declarations)) with
| Fail __error -> Fail __error
| Done v_operation ->
(match (f_family_identity (v_operation)) with
| Fail __error -> Fail __error
| Done v_identity ->
(Done ((StateSource (v_identity, v_identity, (State.f_merge ([v_operation]) (v_existing))))))))
and (* monomorph.bend:1515 *)
f_family_source : State.t_Request -> (M.t_TypeId) list -> M.t_Ty -> (M.t_Operation) list -> (M.t_Operation) list -> (M.t_Diagnostic, t_StateSource) Base.result_ =
fun v_request v_requested v_ty v_declarations v_existing ->
(match (v_request, v_requested) with
| (State.Read, (v_read :: [])) ->
(f_single_family_source (v_read) (v_ty) (v_declarations) (v_existing))
| (State.Reader, (v_read :: [])) ->
(f_single_family_source (v_read) (v_ty) (v_declarations) (v_existing))
| (State.Write, (v_write :: [])) ->
(f_single_family_source (v_write) (v_ty) (v_declarations) (v_existing))
| (State.Writer, (v_write :: [])) ->
(f_single_family_source (v_write) (v_ty) (v_declarations) (v_existing))
| (State.Run, (v_read :: (v_write :: []))) ->
(match (f_family_instance (v_read) (v_ty) (v_declarations)) with
| Fail __error -> Fail __error
| Done v_reader ->
(match (f_family_instance (v_write) (v_ty) (v_declarations)) with
| Fail __error -> Fail __error
| Done v_writer ->
(match (f_family_identity (v_reader)) with
| Fail __error -> Fail __error
| Done v_read_identity ->
(match (f_family_identity (v_writer)) with
| Fail __error -> Fail __error
| Done v_write_identity ->
(Done ((StateSource (v_read_identity, v_write_identity, (State.f_merge ([v_reader; v_writer]) (v_existing))))))))))
| (_, _) ->
(Fail ((M.Diagnostic (s_68, s_66, s_69)))))
and (* monomorph.bend:1535 *)
f_state_source : State.t_Request -> (M.t_TypeId) list -> M.t_Ty -> (M.t_Operation) list -> (M.t_Operation) list -> (M.t_Diagnostic, t_StateSource) Base.result_ =
fun v_request v_requested v_ty v_declarations v_existing ->
(match v_requested with
| [] ->
(match (State.f_type_key (65536) ((State.TypeKey (v_ty)))) with
| Fail __error -> Fail __error
| Done v_key ->
(Done ((StateSource ((State.f_read_identity (v_key)), (State.f_write_identity (v_key)), (State.f_operations (v_key) (v_ty) (v_existing)))))))
| v_templates ->
(f_family_source (v_request) (v_templates) (v_ty) (v_declarations) (v_existing)))
and (* monomorph.bend:1544 *)
f_select_state : State.t_Request -> I.t_Coverage -> M.t_Ty -> M.t_Ty -> t_Specialization -> t_Configuration -> (M.t_Diagnostic, t_Specialization) Base.result_ =
fun v_request v_need v_left v_right v_specialization v_configuration ->
(match (v_need, v_specialization) with
| ((I.AssociatedNeed (v_identity, v_dispatch, v_member, v_effect_templates, v_old_left, v_old_right, v_result, v_invocation, v_ambient, v_subject)), (Specialization ((M.Module (v_constants, v_functions, v_types, v_operations)), v_environment, v_choices, v_counter, v_certificates))) ->
(let (Configuration (v_originals, v_templates, v_entry, v_locals, v_affected, v_stride, v_constant_values, v_family_templates, v_step, v_schema)) = v_configuration in
(let v_ty = (State.f_state_type (v_request) (v_left)) in
(let v_name = (Base.string_append s_70 (Base.string_append (Base.nat_show (v_counter)) s_6)) in
(match (f_state_source (v_request) (v_effect_templates) (v_ty) (v_family_templates) (v_operations)) with
| Fail __error -> Fail __error
| Done v_source ->
(let v_catalog = (f_state_source_operations (v_source)) in
(let v_generated = (State.f_function_for (v_request) ((f_state_source_read (v_source))) ((f_state_source_write (v_source))) (v_name) ((Base.nat_mul (v_counter) (v_stride)))) in
(let v_all_functions = (Base.list_append (v_functions) ([v_generated])) in
(match (f_infer_generated (v_generated) (v_environment) (v_catalog) (v_types) ((G.f_function_names ((G.f_function_declarations ((Base.list_append (v_originals) (v_all_functions)))))))) with
| Fail __error -> Fail __error
| Done v_inferred ->
(match (I.f_instantiate_binding_selected ((I.f_lookup_binding ((G.f_env_bindings (v_inferred))) (v_name))) ((G.f_env_state (v_inferred))) (v_name) (v_subject)) with
| Fail __error -> Fail __error
| Done v_selected_instance ->
(let v_target = (I.f_selected_typing (v_selected_instance)) in
(match (I.f_unify ((I.f_type_of (v_target))) ((M.FunctionTy (v_left, (M.FunctionTy (v_right, v_result, v_ambient)), v_ambient))) ((I.f_state_of (v_target))) (v_subject)) with
| Fail __error -> Fail __error
| Done v_unified ->
(match (T.f_resolve ((I.f_substitutions_of (v_unified))) ((I.f_selected_exact (v_selected_instance)))) with
| Fail __error -> Fail __error
| Done v_signature ->
(Done ((Specialization ((M.Module (v_constants, v_all_functions, v_types, v_catalog)), (G.Environment ((G.f_env_bindings (v_inferred)), (G.f_env_definitions (v_inferred)), v_unified)), (Base.map_set (v_choices) ((Base.nat_show (v_identity))) ((FunctionChoice (v_name, v_signature)))), (Base.nat_add (v_counter) (v_step)), v_certificates))))))))))))))))
| (_, _) ->
(Fail ((M.Diagnostic (s_0, s_71, s_72)))))
and (* monomorph.bend:1566 *)
f_exact_operation_type : M.t_Operation -> M.t_Ty =
fun v_operation ->
(match v_operation with
| (M.Operation (v_identity, v_parameter, v_result)) ->
(M.FunctionTy (v_parameter, v_result, (Rows.f_singleton (v_identity) (M.ClosedRow))))
| _ ->
M.NeverTy)
and (* monomorph.bend:1573 *)
f_select_operation : I.t_Coverage -> (M.t_Ty) list -> t_Specialization -> t_Configuration -> (M.t_Diagnostic, t_Specialization) Base.result_ =
fun v_need v_arguments v_specialization v_configuration ->
(match (v_need, v_specialization) with
| ((I.OperationNeed (v_identity, v_template, v_old_arguments, v_function_type, v_subject)), (Specialization ((M.Module (v_constants, v_functions, v_types, v_operations)), v_environment, v_choices, v_counter, v_certificates))) ->
(let (Configuration (v_originals, v_templates, v_entry, v_locals, v_affected, v_stride, v_constant_values, v_family_templates, v_step, v_schema)) = v_configuration in
(let v_state = (G.f_env_state (v_environment)) in
(match (f_family_declaration (v_family_templates) (v_template)) with
| Fail __error -> Fail __error
| Done v_declaration ->
(match (f_family_arguments_declared (v_declaration) (v_template) (v_arguments)) with
| Fail __error -> Fail __error
| Done v_operation ->
(match (f_family_identity (v_operation)) with
| Fail __error -> Fail __error
| Done v_concrete ->
(let v_selected_type = (I.f_operation_type (v_operation) ((I.f_next_of (v_state)))) in
(match (I.f_unify (v_function_type) (v_selected_type) ((I.f_with_next (v_state) ((Base.nat_add 1 (I.f_next_of (v_state)))))) (v_subject)) with
| Fail __error -> Fail __error
| Done v_unified ->
(match (T.f_resolve ((I.f_substitutions_of (v_unified))) ((f_exact_operation_type (v_operation)))) with
| Fail __error -> Fail __error
| Done v_signature ->
(Done ((Specialization ((M.Module (v_constants, v_functions, v_types, (State.f_merge ([v_operation]) (v_operations)))), (G.Environment ((G.f_env_bindings (v_environment)), (G.f_env_definitions (v_environment)), v_unified)), (Base.map_set (v_choices) ((Base.nat_show (v_identity))) ((OperationChoice (v_concrete, v_signature)))), v_counter, v_certificates))))))))))))
| (_, _) ->
(Fail ((M.Diagnostic (s_0, s_66, s_73)))))
and (* monomorph.bend:1589 *)
f_select_request : (State.t_Request) option -> I.t_Coverage -> M.t_Ty -> M.t_Ty -> t_Specialization -> t_Configuration -> (I.t_Binding) list -> (Staging.t_Scheme) list -> (M.t_Diagnostic, t_Specialization) Base.result_ =
fun v_request v_need v_left v_right v_specialization v_configuration v_shapes v_schemes ->
(match v_request with
| (Some (v_request)) ->
(f_select_state (v_request) (v_need) (v_left) (v_right) (v_specialization) (v_configuration))
| None ->
(f_select_associated (v_need) (v_left) (v_right) (v_specialization) (v_configuration) (v_shapes) (v_schemes)))
and (* monomorph.bend:1596 *)
f_select_type_same : I.t_Coverage -> M.t_Ty -> M.t_Ty -> t_Specialization -> t_Configuration -> (M.t_Diagnostic, t_Specialization) Base.result_ =
fun v_need v_left v_right v_specialization v_configuration ->
(match (v_need, v_specialization) with
| ((I.AssociatedNeed (v_identity, v_dispatch, v_member, v_effect_templates, v_old_left, v_old_right, v_result, v_invocation, v_ambient, v_subject)), (Specialization ((M.Module (v_constants, v_functions, v_types, v_operations)), v_environment, v_choices, v_counter, v_certificates))) ->
(let (Configuration (v_originals, v_templates, v_entry, v_locals, v_affected, v_stride, v_constant_values, v_family_templates, v_step, v_schema)) = v_configuration in
(let v_name = (Base.string_append s_76 (Base.string_append (Base.nat_show (v_counter)) s_77)) in
(match (State.f_type_key (65536) ((State.TypeKey ((State.f_witness (65536) (v_left)))))) with
| Fail __error -> Fail __error
| Done v_a ->
(match (State.f_type_key (65536) ((State.TypeKey ((State.f_witness (65536) (v_right)))))) with
| Fail __error -> Fail __error
| Done v_b ->
(let v_generated = (M.Function (v_name, false, s_74, None, None, (M.LambdaExpr ((Base.nat_mul (v_counter) (v_stride)), s_75, None, None, (M.BoolExpr ((M.f_name_equal (v_a) (v_b)))))))) in
(let v_all_functions = (Base.list_append (v_functions) ([v_generated])) in
(match (f_infer_generated (v_generated) (v_environment) (v_operations) (v_types) ((G.f_function_names ((G.f_function_declarations ((Base.list_append (v_originals) (v_all_functions)))))))) with
| Fail __error -> Fail __error
| Done v_inferred ->
(match (I.f_instantiate_binding_selected ((I.f_lookup_binding ((G.f_env_bindings (v_inferred))) (v_name))) ((G.f_env_state (v_inferred))) (v_name) (v_subject)) with
| Fail __error -> Fail __error
| Done v_selected_instance ->
(let v_target = (I.f_selected_typing (v_selected_instance)) in
(match (I.f_unify ((I.f_type_of (v_target))) ((M.FunctionTy (v_left, (M.FunctionTy (v_right, v_result, v_ambient)), v_ambient))) ((I.f_state_of (v_target))) (v_subject)) with
| Fail __error -> Fail __error
| Done v_unified ->
(match (T.f_resolve ((I.f_substitutions_of (v_unified))) ((I.f_selected_exact (v_selected_instance)))) with
| Fail __error -> Fail __error
| Done v_signature ->
(Done ((Specialization ((M.Module (v_constants, v_all_functions, v_types, v_operations)), (G.Environment ((G.f_env_bindings (v_inferred)), (G.f_env_definitions (v_inferred)), v_unified)), (Base.map_set (v_choices) ((Base.nat_show (v_identity))) ((FunctionChoice (v_name, v_signature)))), (Base.nat_add (v_counter) (v_step)), v_certificates)))))))))))))))
| (_, _) ->
(Fail ((M.Diagnostic (s_0, s_78, s_79)))))
and (* monomorph.bend:1615 *)
f_select_type_request : bool -> (State.t_Request) option -> I.t_Coverage -> M.t_Ty -> M.t_Ty -> t_Specialization -> t_Configuration -> (I.t_Binding) list -> (Staging.t_Scheme) list -> (M.t_Diagnostic, t_Specialization) Base.result_ =
fun v_same v_request v_need v_left v_right v_specialization v_configuration v_shapes v_schemes ->
(match v_same with
| true ->
(f_select_type_same (v_need) (v_left) (v_right) (v_specialization) (v_configuration))
| false ->
(f_select_request (v_request) (v_need) (v_left) (v_right) (v_specialization) (v_configuration) (v_shapes) (v_schemes)))
and (* monomorph.bend:1622 *)
f_select : I.t_Coverage -> M.t_Ty -> M.t_Ty -> t_Specialization -> t_Configuration -> (I.t_Binding) list -> (Staging.t_Scheme) list -> (M.t_Diagnostic, t_Specialization) Base.result_ =
fun v_need v_left v_right v_specialization v_configuration v_shapes v_schemes ->
(match v_need with
| (I.AssociatedNeed (v_identity, M.BinaryDispatch, v_member, v_effect_templates, v_old_left, v_old_right, v_result, v_invocation, v_ambient, v_subject)) ->
(f_select_type_request ((M.f_name_equal (v_member) (s_78))) ((State.f_request (v_member))) (v_need) (v_left) (v_right) (v_specialization) (v_configuration) (v_shapes) (v_schemes))
| (I.AssociatedNeed (v_identity, v_dispatch, v_member, v_templates, v_old_left, v_old_right, v_result, v_invocation, v_ambient, v_subject)) ->
(f_select_receiver (v_need) (v_left) (v_right) (v_specialization) (v_configuration) (v_shapes) (v_schemes))
| _ ->
(Fail ((M.Diagnostic (s_0, s_1, s_80)))))
and (* monomorph.bend:1634 *)
f_remaining_row_labels : Rows.t_Selection -> (M.t_TypeId) list =
fun v_selected ->
(let (Rows.Selection (v_found, v_remaining)) = v_selected in
v_remaining)
and (* monomorph.bend:1638 *)
f_max_row_labels : (M.t_TypeId) list -> (M.t_TypeId) list -> (M.t_TypeId) list =
fun v_outer v_inner ->
(match v_outer with
| [] ->
v_inner
| (v_head :: v_tail) ->
(v_head :: (f_max_row_labels (v_tail) ((f_remaining_row_labels ((Rows.f_select (v_inner) (v_head))))))))
and (* monomorph.bend:1645 *)
f_exact_binary_invocation : M.t_Ty -> (M.t_Diagnostic, (M.t_EffectRow) option) Base.result_ =
fun v_signature ->
(match v_signature with
| (M.FunctionTy (v_first, (M.FunctionTy (v_second, v_result, (M.EffectRow (v_inner, M.ClosedRow)))), (M.EffectRow (v_outer, M.ClosedRow)))) ->
(Done ((Some ((Rows.f_canonical ((M.EffectRow ((f_max_row_labels (v_outer) (v_inner)), M.ClosedRow))))))))
| (M.FunctionTy (v_first, (M.FunctionTy (v_second, v_result, v_inner)), v_outer)) ->
(Done (None))
| v_other ->
(Fail ((M.Diagnostic (s_0, s_81, s_82)))))
and (* monomorph.bend:1654 *)
f_exact_receiver_invocation : M.t_Ty -> (M.t_Diagnostic, (M.t_EffectRow) option) Base.result_ =
fun v_signature ->
(match v_signature with
| (M.FunctionTy (v_receiver, v_result, (M.EffectRow (v_operations, M.ClosedRow)))) ->
(Done ((Some ((Rows.f_canonical ((M.EffectRow (v_operations, M.ClosedRow))))))))
| (M.FunctionTy (v_receiver, v_result, v_row)) ->
(Done (None))
| v_other ->
(Fail ((M.Diagnostic (s_0, s_81, s_83)))))
and (* monomorph.bend:1666 *)
f_selected_binary_invocation : M.t_Ty -> (M.t_Diagnostic, (M.t_EffectRow) option) Base.result_ =
fun v_signature ->
(match v_signature with
| (M.FunctionTy (v_first, (M.FunctionTy (v_second, v_result, v_inner)), (M.EffectRow ([], M.ClosedRow)))) ->
(Done ((Some ((Rows.f_canonical (v_inner))))))
| (M.FunctionTy (v_first, (M.FunctionTy (v_second, v_result, (M.EffectRow ([], M.ClosedRow)))), v_outer)) ->
(Done ((Some ((Rows.f_canonical (v_outer))))))
| v_other ->
(f_exact_binary_invocation (v_other)))
and (* monomorph.bend:1675 *)
f_selected_receiver_invocation : M.t_Ty -> (M.t_Diagnostic, (M.t_EffectRow) option) Base.result_ =
fun v_signature ->
(match v_signature with
| (M.FunctionTy (v_receiver, v_result, v_row)) ->
(Done ((Some ((Rows.f_canonical (v_row))))))
| v_other ->
(f_exact_receiver_invocation (v_other)))
and (* monomorph.bend:1682 *)
f_selected_exact_invocation : (t_Choice) option -> bool -> (M.t_Diagnostic, (M.t_EffectRow) option) Base.result_ =
fun v_found v_binary ->
(match (v_found, v_binary) with
| ((Some ((FunctionChoice (v_name, v_signature)))), true) ->
(f_selected_binary_invocation (v_signature))
| ((Some ((ReceiverChoice (v_name, v_signature)))), true) ->
(f_selected_binary_invocation (v_signature))
| ((Some ((ReceiverChoice (v_name, v_signature)))), false) ->
(f_selected_receiver_invocation (v_signature))
| (_, _) ->
(Fail ((M.Diagnostic (s_0, s_81, s_84)))))
and (* monomorph.bend:1693 *)
f_unify_selected_invocation : (M.t_EffectRow) option -> M.t_EffectRow -> I.t_State -> Base.text -> (M.t_Diagnostic, I.t_State) Base.result_ =
fun v_found v_invocation v_state v_subject ->
(match v_found with
| (Some (v_exact)) ->
(I.f_unify_rows (v_invocation) (v_exact) (v_state) (v_subject))
| None ->
(Done (v_state)))
and (* monomorph.bend:1700 *)
f_constrain_selected_invocation : t_Specialization -> int -> M.t_EffectRow -> bool -> Base.text -> (M.t_Diagnostic, t_Specialization) Base.result_ =
fun v_selected v_site v_invocation v_binary v_subject ->
(let (Specialization (v_module, v_environment, v_choices, v_next, v_certificates)) = v_selected in
(match (f_selected_exact_invocation ((f_choice (v_choices) (v_site))) (v_binary)) with
| Fail __error -> Fail __error
| Done v_exact ->
(match (f_unify_selected_invocation (v_exact) (v_invocation) ((G.f_env_state (v_environment))) (v_subject)) with
| Fail __error -> Fail __error
| Done v_state ->
(Done ((Specialization (v_module, (G.Environment ((G.f_env_bindings (v_environment)), (G.f_env_definitions (v_environment)), v_state)), v_choices, v_next, v_certificates)))))))
and (* monomorph.bend:1707 *)
f_associated_binary : M.t_Dispatch -> bool =
fun v_dispatch ->
(match v_dispatch with
| M.MemberDispatch ->
false
| M.BinaryDispatch ->
true
| M.FieldUpdateDispatch ->
true)
and (* monomorph.bend:1716 *)
f_constrain_ordinary_invocation : (t_Specialization) option -> I.t_Coverage -> (M.t_Diagnostic, (t_Specialization) option) Base.result_ =
fun v_found v_need ->
(match (v_found, v_need) with
| ((Some (v_selected)), (I.AssociatedNeed (v_identity, v_dispatch, v_member, v_templates, v_left, v_right, v_result, (Some (v_invocation)), v_ambient, v_subject))) ->
(match (f_constrain_selected_invocation (v_selected) (v_identity) (v_invocation) ((f_associated_binary (v_dispatch))) (v_subject)) with
| Fail __error -> Fail __error
| Done v_constrained ->
(Done ((Some (v_constrained)))))
| (v_selected, v_other) ->
(Done (v_selected)))
and (* monomorph.bend:1725 *)
f_require_field : bool -> I.t_Coverage -> M.t_Ty -> M.t_Ty -> Base.text -> Base.text -> t_Specialization -> t_Configuration -> (I.t_Binding) list -> (Staging.t_Scheme) list -> (M.t_Diagnostic, t_Specialization) Base.result_ =
fun v_exists v_need v_receiver v_argument v_member v_subject v_specialization v_configuration v_shapes v_schemes ->
(match v_exists with
| true ->
(f_select_receiver (v_need) (v_receiver) (v_argument) (v_specialization) (v_configuration) (v_shapes) (v_schemes))
| false ->
(Fail ((M.Diagnostic (s_55, v_subject, (Base.string_append s_85 (Base.string_append v_member (Base.string_append s_57 (M.f_type_show (v_receiver))))))))))
and (* monomorph.bend:1732 *)
f_select_qualified : M.t_Predicate -> M.t_Predicate -> int -> Base.text -> t_Specialization -> t_Configuration -> (I.t_Binding) list -> (Staging.t_Scheme) list -> (M.t_Diagnostic, t_Specialization) Base.result_ =
fun v_original v_resolved v_site v_subject v_specialization v_configuration v_shapes v_schemes ->
(match v_resolved with
| (M.AssociatedPredicate (v_member, v_templates, v_left, v_right, v_result, v_invocation)) ->
(match (f_select ((I.AssociatedNeed (v_site, M.BinaryDispatch, v_member, v_templates, v_left, v_right, v_result, None, v_invocation, v_subject))) (v_left) (v_right) (v_specialization) (v_configuration) (v_shapes) (v_schemes)) with
| Fail __error -> Fail __error
| Done v_selected ->
(match (f_constrain_selected_invocation (v_selected) (v_site) (v_invocation) (true) (v_subject)) with
| Fail __error -> Fail __error
| Done v_constrained ->
(f_selected_qualified (v_specialization) (v_constrained) (v_site) (v_original))))
| (M.ReceiverPredicate (v_member, v_templates, v_receiver, v_argument, v_result, v_invocation)) ->
(match (f_select ((I.AssociatedNeed (v_site, M.MemberDispatch, v_member, v_templates, v_receiver, v_argument, v_result, None, v_invocation, v_subject))) (v_receiver) (v_argument) (v_specialization) (v_configuration) (v_shapes) (v_schemes)) with
| Fail __error -> Fail __error
| Done v_selected ->
(match (f_constrain_selected_invocation (v_selected) (v_site) (v_invocation) (false) (v_subject)) with
| Fail __error -> Fail __error
| Done v_constrained ->
(f_selected_qualified (v_specialization) (v_constrained) (v_site) (v_original))))
| (M.FieldPredicate (v_member, v_receiver, v_result)) ->
(let (Specialization ((M.Module (v_constants, v_functions, v_types, v_operations)), v_environment, v_choices, v_counter, v_certificates)) = v_specialization in
(match (f_require_field ((Members.f_has_field ((Members.f_constructors (v_receiver) (v_types))) (v_member))) ((I.AssociatedNeed (v_site, M.MemberDispatch, v_member, [], v_receiver, M.UnitTy, v_result, None, (M.EffectRow ([], M.ClosedRow)), v_subject))) (v_receiver) (M.UnitTy) (v_member) (v_subject) (v_specialization) (v_configuration) (v_shapes) (v_schemes)) with
| Fail __error -> Fail __error
| Done v_selected ->
(f_selected_qualified (v_specialization) (v_selected) (v_site) (v_original))))
| (M.UpdatePredicate (v_member, v_receiver, v_assigned, v_result, v_invocation)) ->
(match (f_select_receiver ((I.AssociatedNeed (v_site, M.FieldUpdateDispatch, v_member, [], v_receiver, v_assigned, v_result, None, v_invocation, v_subject))) (v_receiver) (v_assigned) (v_specialization) (v_configuration) (v_shapes) (v_schemes)) with
| Fail __error -> Fail __error
| Done v_selected ->
(match (f_constrain_selected_invocation (v_selected) (v_site) (v_invocation) (true) (v_subject)) with
| Fail __error -> Fail __error
| Done v_constrained ->
(f_selected_qualified (v_specialization) (v_constrained) (v_site) (v_original))))
| (M.OperationPredicate (v_template, v_arguments, v_function_type)) ->
(match (f_select_operation ((I.OperationNeed (v_site, v_template, v_arguments, v_function_type, v_subject))) (v_arguments) (v_specialization) (v_configuration)) with
| Fail __error -> Fail __error
| Done v_selected ->
(f_selected_qualified (v_specialization) (v_selected) (v_site) (v_original)))
| (M.TypeRepPredicate (v_represented)) ->
(match (f_direct_qualified_answer (v_resolved) (v_subject)) with
| Fail __error -> Fail __error
| Done v_answer ->
(Done ((f_remember_answer (v_specialization) (v_specialization) (v_site) (v_original) (v_answer)))))
| (M.EffectRepPredicate (v_row)) ->
(match (f_direct_qualified_answer (v_resolved) (v_subject)) with
| Fail __error -> Fail __error
| Done v_answer ->
(Done ((f_remember_answer (v_specialization) (v_specialization) (v_site) (v_original) (v_answer))))))
and (* monomorph.bend:1769 *)
f_state_request_ready : (State.t_Request) option -> M.t_Ty -> M.t_Ty -> Base.text -> bool =
fun v_request v_left v_right v_entry ->
(match v_request with
| (Some (v_request)) ->
(Base.bool_not ((f_polymorphic (65536) ([(State.f_state_type (v_request) (v_left))]))))
| None ->
(Base.bool_or ((Base.maybe_is_some ((f_owner (v_left) (v_entry))))) ((Base.maybe_is_some ((f_owner (v_right) (v_entry)))))))
and (* monomorph.bend:1776 *)
f_request_ready : M.t_Dispatch -> Base.text -> M.t_Ty -> M.t_Ty -> Base.text -> bool =
fun v_dispatch v_member v_left v_right v_entry ->
(match v_dispatch with
| M.BinaryDispatch ->
(Base.bool_pick ((M.f_name_equal (v_member) (s_78))) ((Base.bool_not ((f_polymorphic (65536) ([(State.f_witness (65536) (v_left)); (State.f_witness (65536) (v_right))]))))) ((f_state_request_ready ((State.f_request (v_member))) (v_left) (v_right) (v_entry))))
| _ ->
(Base.maybe_is_some ((f_owner (v_left) (v_entry)))))
and (* monomorph.bend:1785 *)
f_qualified_ready : M.t_Predicate -> Base.text -> (M.t_Diagnostic, bool) Base.result_ =
fun v_predicate v_entry ->
(match v_predicate with
| (M.AssociatedPredicate (v_member, v_templates, v_left, v_right, v_result, v_invocation)) ->
(Done ((f_request_ready (M.BinaryDispatch) (v_member) (v_left) (v_right) (v_entry))))
| (M.ReceiverPredicate (v_member, v_templates, v_receiver, v_argument, v_result, v_invocation)) ->
(Done ((f_request_ready (M.MemberDispatch) (v_member) (v_receiver) (v_argument) (v_entry))))
| (M.FieldPredicate (v_member, v_receiver, v_result)) ->
(Done ((f_request_ready (M.MemberDispatch) (v_member) (v_receiver) (M.UnitTy) (v_entry))))
| (M.UpdatePredicate (v_member, v_receiver, v_assigned, v_result, v_invocation)) ->
(Done ((f_request_ready (M.FieldUpdateDispatch) (v_member) (v_receiver) (v_assigned) (v_entry))))
| (M.OperationPredicate (v_template, v_arguments, v_function_type)) ->
(Done ((Base.bool_not ((f_polymorphic (65536) (v_arguments))))))
| (M.TypeRepPredicate (v_represented)) ->
(match (C.f_free ((M.TypeRepPredicate (v_represented)))) with
| Fail __error -> Fail __error
| Done v_free ->
(Done ((Base.list_is_empty (v_free)))))
| (M.EffectRepPredicate (v_row)) ->
(match (C.f_free ((M.EffectRepPredicate (v_row)))) with
| Fail __error -> Fail __error
| Done v_free ->
(Done ((Base.list_is_empty (v_free))))))
and (* monomorph.bend:1813 *)
f_available_selection : (M.t_Diagnostic, t_Specialization) Base.result_ -> bool -> (M.t_Diagnostic, (t_Specialization) option) Base.result_ =
fun v_attempt v_unresolved ->
(match v_attempt with
| (Done (v_selected)) ->
(Done ((Some (v_selected))))
| (Fail ((M.Diagnostic (v_code, v_subject, v_message)))) ->
(Base.bool_pick ((Base.bool_and (v_unresolved) ((M.f_name_equal (v_code) (s_26))))) ((Done (None))) ((Fail ((M.Diagnostic (v_code, v_subject, v_message)))))))
and (* monomorph.bend:1820 *)
f_unfinished : I.t_Coverage -> (M.t_Diagnostic, t_Specialization) Base.result_ =
fun v_need ->
(match v_need with
| (I.OperationNeed (v_identity, v_template, v_arguments, v_function_type, v_subject)) ->
(Fail ((M.Diagnostic (s_86, v_subject, (Base.string_append s_87 (Base.string_append (M.f_type_id_show (v_template)) s_88))))))
| (I.AssociatedNeed (v_identity, v_dispatch, v_member, v_templates, v_left, v_right, v_result, v_invocation, v_ambient, v_subject)) ->
(Fail ((M.Diagnostic (s_42, v_subject, (Base.string_append s_89 (Base.string_append v_member s_90))))))
| (I.QualifiedNeed (v_site, v_predicate, v_subject)) ->
(Fail ((M.Diagnostic (s_32, v_subject, s_91))))
| _ ->
(Fail ((M.Diagnostic (s_0, s_1, s_92)))))
and (* monomorph.bend:1831 *)
f_unresolved_need : I.t_Coverage -> (t_Choice) Base.map -> (I.t_Coverage) list -> (I.t_Coverage) list =
fun v_need v_choices v_rest ->
(match v_need with
| (I.OperationNeed (v_identity, v_template, v_arguments, v_function_type, v_subject)) ->
(Base.bool_pick ((Base.maybe_is_some ((f_choice (v_choices) (v_identity))))) (v_rest) (((I.OperationNeed (v_identity, v_template, v_arguments, v_function_type, v_subject)) :: v_rest)))
| (I.AssociatedNeed (v_identity, v_dispatch, v_member, v_templates, v_left, v_right, v_result, v_invocation, v_ambient, v_subject)) ->
(Base.bool_pick ((Base.maybe_is_some ((f_choice (v_choices) (v_identity))))) (v_rest) (((I.AssociatedNeed (v_identity, v_dispatch, v_member, v_templates, v_left, v_right, v_result, v_invocation, v_ambient, v_subject)) :: v_rest)))
| (I.QualifiedNeed (v_site, v_predicate, v_subject)) ->
(Base.bool_pick ((f_qualified_solved (v_choices) (v_site) (v_predicate))) (v_rest) (((I.QualifiedNeed (v_site, v_predicate, v_subject)) :: v_rest)))
| _ ->
v_rest)
and (* monomorph.bend:1842 *)
f_unresolved : (I.t_Coverage) list -> (t_Choice) Base.map -> (I.t_Coverage) list =
fun v_needs v_choices ->
(match v_needs with
| [] ->
[]
| (v_need :: v_tail) ->
(f_unresolved_need (v_need) (v_choices) ((f_unresolved (v_tail) (v_choices)))))
and (* monomorph.bend:1852 *)
f_unresolved_coverage_with_tail : (I.t_Coverage) list -> (t_Choice) Base.map -> (I.t_Coverage) list -> (I.t_Coverage) list =
fun v_needs v_choices v_rest ->
(match v_needs with
| [] ->
v_rest
| (v_need :: v_tail) ->
(f_unresolved_need (v_need) (v_choices) ((f_unresolved_coverage_with_tail (v_tail) (v_choices) (v_rest)))))
and (* monomorph.bend:1859 *)
f_unresolved_definitions : (I.t_Definition) list -> (t_Choice) Base.map -> (I.t_Coverage) list =
fun v_definitions v_choices ->
(match v_definitions with
| [] ->
[]
| ((I.Definition (v_name, (I.Inference (v_ty, v_coverage, v_exits, v_reflections, v_predicates, v_uses)))) :: v_tail) ->
(f_unresolved_coverage_with_tail ((Base.list_append (v_coverage) ((I.f_execution_needs (v_uses))))) (v_choices) ((f_unresolved_definitions (v_tail) (v_choices)))))
and (* monomorph.bend:1866 *)
f_specialization_pending : t_Specialization -> (I.t_Coverage) list =
fun v_specialization ->
(let (Specialization (v_module, v_environment, v_choices, v_next, v_certificates)) = v_specialization in
(f_unresolved_definitions ((G.f_env_definitions (v_environment))) (v_choices)))
and (* monomorph.bend:1873 *)
f_cached_needs : t_PendingCache -> (I.t_Coverage) list =
fun v_cache ->
(let (PendingCache (v_definition_count, v_needs)) = v_cache in
v_needs)
and (* monomorph.bend:1883 *)
f_append_fresh : ((I.t_Coverage) list) option -> (I.t_Coverage) list -> (t_Choice) Base.map -> ((I.t_Coverage) list) option =
fun v_found v_coverage v_choices ->
(match v_found with
| (Some (v_next)) ->
(Some ((f_unresolved_coverage_with_tail (v_coverage) (v_choices) (v_next))))
| None ->
None)
and (* monomorph.bend:1890 *)
f_fresh_unresolved : t_FreshWork -> (t_Choice) Base.map -> (I.t_Coverage) list -> ((I.t_Coverage) list) option =
fun v_work v_choices v_rest ->
(match v_work with
| (FreshWork (0, v_definitions)) ->
(Some (v_rest))
| (FreshWork (__nat_48, ((I.Definition (v_name, (I.Inference (v_ty, v_coverage, v_exits, v_reflections, v_predicates, v_uses)))) :: v_tail))) when __nat_48 >= 1 ->
(let v_remaining = (__nat_48 - 1) in
(f_append_fresh ((f_fresh_unresolved ((FreshWork (v_remaining, v_tail))) (v_choices) (v_rest))) ((Base.list_append (v_coverage) ((I.f_execution_needs (v_uses))))) (v_choices)))
| (FreshWork (__nat_49, [])) when __nat_49 >= 1 ->
(let v_remaining = (__nat_49 - 1) in
None))
and (* monomorph.bend:1899 *)
f_refresh_from_fresh : ((I.t_Coverage) list) option -> t_Specialization -> int -> t_PendingCache =
fun v_found v_selected v_count ->
(match v_found with
| (Some (v_next)) ->
(PendingCache (v_count, v_next))
| None ->
(PendingCache (v_count, (f_specialization_pending (v_selected)))))
and (* monomorph.bend:1906 *)
f_refresh_with_count : bool -> t_Specialization -> int -> int -> (I.t_Definition) list -> (I.t_Coverage) list -> (t_Choice) Base.map -> t_PendingCache =
fun v_valid v_selected v_count v_prior_count v_definitions v_prior_needs v_choices ->
(match v_valid with
| false ->
(PendingCache (v_count, (f_specialization_pending (v_selected))))
| true ->
(f_refresh_from_fresh ((f_fresh_unresolved ((FreshWork ((Base.nat_sub (v_count) (v_prior_count)), v_definitions))) (v_choices) ((f_unresolved (v_prior_needs) (v_choices))))) (v_selected) (v_count)))
and (* monomorph.bend:1913 *)
f_refresh_pending : t_Specialization -> t_PendingCache -> t_PendingCache =
fun v_selected v_cache ->
(let (Specialization (v_module, v_environment, v_choices, v_next, v_certificates)) = v_selected in
(let (PendingCache (v_prior_count, v_prior_needs)) = v_cache in
(let v_definitions = (G.f_env_definitions (v_environment)) in
(let v_current_count = (Base.list_length (v_definitions)) in
(f_refresh_with_count ((Base.nat_is_ge (v_current_count) (v_prior_count))) (v_selected) (v_current_count) (v_prior_count) (v_definitions) (v_prior_needs) (v_choices))))))
and (* monomorph.bend:1920 *)
f_solve_staged : int -> t_SolveWork -> t_Specialization -> t_Configuration -> (I.t_Binding) list -> t_PendingCache -> (Staging.t_Scheme) list -> (M.t_Diagnostic, t_Specialization) Base.result_ =
fun v_fuel v_work v_specialization v_configuration v_shapes v_cache v_schemes ->
(match (v_fuel, v_work) with
| (0, _) ->
(Fail ((M.Diagnostic (s_8, s_1, s_93))))
| (__nat_50, (Needs ([]))) when __nat_50 >= 1 ->
(let v_rest = (__nat_50 - 1) in
(Done (v_specialization)))
| (__nat_51, (Needs (((I.OperationNeed (v_identity, v_template, v_arguments, v_function_type, v_subject)) :: v_tail)))) when __nat_51 >= 1 ->
(let v_rest = (__nat_51 - 1) in
(let (Specialization (v_module, v_environment, v_choices, v_counter, v_certificates)) = v_specialization in
(match (T.f_resolve_work ((I.f_substitutions_of ((G.f_env_state (v_environment))))) (65536) ((T.ManyTypes (v_arguments)))) with
| Fail __error -> Fail __error
| Done v_resolved ->
(f_solve_staged (v_rest) ((Operation ((I.OperationNeed (v_identity, v_template, v_resolved, v_function_type, v_subject)), v_resolved, (Base.bool_not ((f_polymorphic (65536) (v_resolved)))), (Base.maybe_is_some ((f_choice (v_choices) (v_identity)))), v_tail))) (v_specialization) (v_configuration) (v_shapes) (v_cache) (v_schemes)))))
| (__nat_52, (Operation (v_need, v_arguments, v_ready, true, v_tail))) when __nat_52 >= 1 ->
(let v_rest = (__nat_52 - 1) in
(f_solve_staged (v_rest) ((Needs (v_tail))) (v_specialization) (v_configuration) (v_shapes) (v_cache) (v_schemes)))
| (__nat_53, (Operation (v_need, v_arguments, false, false, v_tail))) when __nat_53 >= 1 ->
(let v_rest = (__nat_53 - 1) in
(f_solve_staged (v_rest) ((Needs (v_tail))) (v_specialization) (v_configuration) (v_shapes) (v_cache) (v_schemes)))
| (__nat_54, (Operation (v_need, v_arguments, true, false, v_tail))) when __nat_54 >= 1 ->
(let v_rest = (__nat_54 - 1) in
(match (f_select_operation (v_need) (v_arguments) (v_specialization) (v_configuration)) with
| Fail __error -> Fail __error
| Done v_selected ->
(let v_updated = (f_refresh_pending (v_selected) (v_cache)) in
(f_solve_staged (v_rest) ((Needs ((f_cached_needs (v_updated))))) (v_selected) (v_configuration) (v_shapes) (v_updated) (v_schemes)))))
| (__nat_55, (Needs (((I.AssociatedNeed (v_identity, v_dispatch, v_member, v_effect_templates, v_left, v_right, v_result, v_invocation, v_ambient, v_subject)) :: v_tail)))) when __nat_55 >= 1 ->
(let v_rest = (__nat_55 - 1) in
(let (Specialization (v_module, v_environment, v_choices, v_counter, v_certificates)) = v_specialization in
(let (Configuration (v_originals, v_templates, v_entry, v_locals, v_affected, v_stride, v_constant_values, v_family_templates, v_step, v_schema)) = v_configuration in
(match (T.f_resolve ((I.f_substitutions_of ((G.f_env_state (v_environment))))) (v_left)) with
| Fail __error -> Fail __error
| Done v_l ->
(match (T.f_resolve ((I.f_substitutions_of ((G.f_env_state (v_environment))))) (v_right)) with
| Fail __error -> Fail __error
| Done v_r ->
(f_solve_staged (v_rest) ((Need ((I.AssociatedNeed (v_identity, v_dispatch, v_member, v_effect_templates, v_left, v_right, v_result, v_invocation, v_ambient, v_subject)), v_l, v_r, (f_request_ready (v_dispatch) (v_member) (v_l) (v_r) (v_entry)), (Base.maybe_is_some ((f_choice (v_choices) (v_identity)))), v_tail))) (v_specialization) (v_configuration) (v_shapes) (v_cache) (v_schemes)))))))
| (__nat_56, (Needs (((I.QualifiedNeed (v_site, v_predicate, v_subject)) :: v_tail)))) when __nat_56 >= 1 ->
(let v_rest = (__nat_56 - 1) in
(let (Specialization (v_module, v_environment, v_choices, v_counter, v_certificates)) = v_specialization in
(let (Configuration (v_originals, v_templates, v_entry, v_locals, v_affected, v_stride, v_constant_values, v_family_templates, v_step, v_schema)) = v_configuration in
(match (C.f_resolve ((I.f_substitutions_of ((G.f_env_state (v_environment))))) (v_predicate)) with
| Fail __error -> Fail __error
| Done v_resolved ->
(match (f_qualified_ready (v_resolved) (v_entry)) with
| Fail __error -> Fail __error
| Done v_ready ->
(f_solve_staged (v_rest) ((Qualified (v_predicate, v_resolved, v_site, v_subject, v_ready, (f_qualified_solved (v_choices) (v_site) (v_predicate)), v_tail))) (v_specialization) (v_configuration) (v_shapes) (v_cache) (v_schemes)))))))
| (__nat_57, (Needs ((v_head :: v_tail)))) when __nat_57 >= 1 ->
(let v_rest = (__nat_57 - 1) in
(f_solve_staged (v_rest) ((Needs (v_tail))) (v_specialization) (v_configuration) (v_shapes) (v_cache) (v_schemes)))
| (__nat_58, (Qualified (v_original, v_resolved, v_site, v_subject, v_ready, true, v_tail))) when __nat_58 >= 1 ->
(let v_rest = (__nat_58 - 1) in
(f_solve_staged (v_rest) ((Needs (v_tail))) (v_specialization) (v_configuration) (v_shapes) (v_cache) (v_schemes)))
| (__nat_59, (Qualified (v_original, v_resolved, v_site, v_subject, false, false, v_tail))) when __nat_59 >= 1 ->
(let v_rest = (__nat_59 - 1) in
(f_solve_staged (v_rest) ((Needs (v_tail))) (v_specialization) (v_configuration) (v_shapes) (v_cache) (v_schemes)))
| (__nat_60, (Qualified (v_original, v_resolved, v_site, v_subject, true, false, v_tail))) when __nat_60 >= 1 ->
(let v_rest = (__nat_60 - 1) in
(match (f_select_qualified (v_original) (v_resolved) (v_site) (v_subject) (v_specialization) (v_configuration) (v_shapes) (v_schemes)) with
| Fail __error -> Fail __error
| Done v_selected ->
(let v_updated = (f_refresh_pending (v_selected) (v_cache)) in
(f_solve_staged (v_rest) ((Needs ((f_cached_needs (v_updated))))) (v_selected) (v_configuration) (v_shapes) (v_updated) (v_schemes)))))
| (__nat_61, (Need (v_need, v_left, v_right, v_ready, true, v_tail))) when __nat_61 >= 1 ->
(let v_rest = (__nat_61 - 1) in
(f_solve_staged (v_rest) ((Needs (v_tail))) (v_specialization) (v_configuration) (v_shapes) (v_cache) (v_schemes)))
| (__nat_62, (Need (v_need, v_left, v_right, false, false, v_tail))) when __nat_62 >= 1 ->
(let v_rest = (__nat_62 - 1) in
(f_solve_staged (v_rest) ((Needs (v_tail))) (v_specialization) (v_configuration) (v_shapes) (v_cache) (v_schemes)))
| (__nat_63, (Need (v_need, v_left, v_right, true, false, v_tail))) when __nat_63 >= 1 ->
(let v_rest = (__nat_63 - 1) in
(match (f_available_selection ((f_select (v_need) (v_left) (v_right) (v_specialization) (v_configuration) (v_shapes) (v_schemes))) ((f_polymorphic (65536) ([v_left; v_right])))) with
| Fail __error -> Fail __error
| Done v_selected ->
(match (f_constrain_ordinary_invocation (v_selected) (v_need)) with
| Fail __error -> Fail __error
| Done v_constrained ->
(f_solve_staged (v_rest) ((Selected (v_constrained, v_tail))) (v_specialization) (v_configuration) (v_shapes) (v_cache) (v_schemes)))))
| (__nat_64, (Selected (None, v_tail))) when __nat_64 >= 1 ->
(let v_rest = (__nat_64 - 1) in
(f_solve_staged (v_rest) ((Needs (v_tail))) (v_specialization) (v_configuration) (v_shapes) (v_cache) (v_schemes)))
| (__nat_65, (Selected ((Some (v_selected)), v_tail))) when __nat_65 >= 1 ->
(let v_rest = (__nat_65 - 1) in
(let v_updated = (f_refresh_pending (v_selected) (v_cache)) in
(f_solve_staged (v_rest) ((Needs ((f_cached_needs (v_updated))))) (v_selected) (v_configuration) (v_shapes) (v_updated) (v_schemes)))))
and (* monomorph.bend:1979 *)
f_solve : int -> t_SolveWork -> t_Specialization -> t_Configuration -> (I.t_Binding) list -> t_PendingCache -> (M.t_Diagnostic, t_Specialization) Base.result_ =
fun v_fuel v_work v_specialization v_configuration v_shapes v_cache ->
(f_solve_staged (v_fuel) (v_work) (v_specialization) (v_configuration) (v_shapes) (v_cache) ([]))
and (* monomorph.bend:1982 *)
f_selected_call : (t_Choice) option -> Base.text -> M.t_Expr -> M.t_Expr -> (M.t_Diagnostic, M.t_Expr) Base.result_ =
fun v_found v_member v_left v_right ->
(match v_found with
| (Some ((ReceiverChoice (v_name, v_signature)))) ->
(Done ((M.ApplyExpr ((M.FunctionExpr (v_name)), v_left))))
| (Some ((FunctionChoice (v_name, v_signature)))) ->
(Done ((M.UseExpr (s_94, v_left, (M.UseExpr (s_95, v_right, (M.ApplyExpr ((M.ApplyExpr ((M.FunctionExpr (v_name)), (M.LocalExpr (s_94)))), (M.LocalExpr (s_95))))))))))
| _ ->
(Fail ((M.Diagnostic (s_0, v_member, s_96)))))
and (* monomorph.bend:1991 *)
f_selected_operation : (t_Choice) option -> M.t_TypeId -> (M.t_Diagnostic, M.t_Expr) Base.result_ =
fun v_found v_template ->
(match v_found with
| (Some ((OperationChoice (v_identity, v_signature)))) ->
(Done ((M.OperationExpr (v_identity))))
| _ ->
(Fail ((M.Diagnostic (s_0, (M.f_type_id_show (v_template)), s_97)))))
and (* monomorph.bend:1998 *)
f_replace_node : M.t_Expr -> (M.t_Expr) list -> (t_Choice) Base.map -> (M.t_Diagnostic, M.t_Expr) Base.result_ =
fun v_original v_children v_choices ->
(match (v_original, v_children) with
| ((M.QualifiedExpr (v_offset, v_annotation, v_predicates, v_value)), (v_a :: [])) ->
(Done (v_a))
| ((M.InstantiationExpr (v_site, v_value)), (v_a :: [])) ->
(Done (v_a))
| ((M.GenericOperationExpr (v_identity, v_template, v_arguments)), []) ->
(f_selected_operation ((f_choice (v_choices) (v_identity))) (v_template))
| ((M.AssociatedExpr (v_identity, v_dispatch, v_member, v_templates, v_left, v_right)), (v_l :: (v_r :: []))) ->
(f_selected_call ((f_choice (v_choices) (v_identity))) (v_member) (v_l) (v_r))
| (v_original, v_children) ->
(f_rebuild (v_original) (v_children) (0)))
and (* monomorph.bend:2011 *)
f_replace : int -> t_ExpandWork -> (t_Choice) Base.map -> (M.t_Diagnostic, (M.t_Expr) list) Base.result_ =
fun v_fuel v_work v_choices ->
(match (v_fuel, v_work) with
| (0, _) ->
(Fail ((M.Diagnostic (s_8, s_1, s_98))))
| (__nat_66, (Expression (v_expression))) when __nat_66 >= 1 ->
(let v_rest = (__nat_66 - 1) in
(match (f_replace (v_rest) ((Expressions ((F.f_children (v_expression))))) (v_choices)) with
| Fail __error -> Fail __error
| Done v_children ->
(match (f_replace_node (v_expression) (v_children) (v_choices)) with
| Fail __error -> Fail __error
| Done v_rebuilt ->
(Done ([v_rebuilt])))))
| (__nat_67, (Expressions ([]))) when __nat_67 >= 1 ->
(let v_rest = (__nat_67 - 1) in
(Done ([])))
| (__nat_68, (Expressions ((v_head :: v_tail)))) when __nat_68 >= 1 ->
(let v_rest = (__nat_68 - 1) in
(match (f_replace (v_rest) ((Expression (v_head))) (v_choices)) with
| Fail __error -> Fail __error
| Done v_value ->
(match (f_replace (v_rest) ((Expressions (v_tail))) (v_choices)) with
| Fail __error -> Fail __error
| Done v_following ->
(Done ((Base.list_append (v_value) (v_following)))))))
| (_, _) ->
(Fail ((M.Diagnostic (s_0, s_1, s_99)))))
and (* monomorph.bend:2030 *)
f_replace_functions : (M.t_Function) list -> (t_Choice) Base.map -> (M.t_Diagnostic, (M.t_Function) list) Base.result_ =
fun v_pending v_choices ->
(match v_pending with
| [] ->
(Done ([]))
| ((M.Function (v_name, v_exported, v_parameter, v_p, v_r, v_body)) :: v_tail) ->
(match (f_replace (65536) ((Expression (v_body))) (v_choices)) with
| Fail __error -> Fail __error
| Done v_expressions ->
(match (f_one (v_expressions)) with
| Fail __error -> Fail __error
| Done v_value ->
(match (f_replace_functions (v_tail) (v_choices)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done (((M.Function (v_name, v_exported, v_parameter, v_p, v_r, v_value)) :: v_rest)))))))
and (* monomorph.bend:2041 *)
f_replace_constants : (M.t_Constant) list -> (t_Choice) Base.map -> (M.t_Diagnostic, (M.t_Constant) list) Base.result_ =
fun v_pending v_choices ->
(match v_pending with
| [] ->
(Done ([]))
| ((M.Constant (v_name, v_exported, v_annotation, v_value)) :: v_tail) ->
(match (f_replace (65536) ((Expression (v_value))) (v_choices)) with
| Fail __error -> Fail __error
| Done v_expressions ->
(match (f_one (v_expressions)) with
| Fail __error -> Fail __error
| Done v_result ->
(match (f_replace_constants (v_tail) (v_choices)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done (((M.Constant (v_name, v_exported, v_annotation, v_result)) :: v_rest)))))))
and (* monomorph.bend:2052 *)
f_finish : t_Specialization -> (M.t_Diagnostic, M.t_Module) Base.result_ =
fun v_specialized ->
(let (Specialization ((M.Module (v_constants, v_functions, v_types, v_operations)), v_environment, v_choices, v_next, v_certificates)) = v_specialized in
(match (f_replace_constants (v_constants) (v_choices)) with
| Fail __error -> Fail __error
| Done v_cs ->
(match (f_replace_functions (v_functions) (v_choices)) with
| Fail __error -> Fail __error
| Done v_fs ->
(Done ((M.Module (v_cs, v_fs, v_types, v_operations)))))))
and (* monomorph.bend:2059 *)
f_required : M.t_Module -> bool =
fun v_module ->
(let (M.Module (v_constants, v_functions, v_types, v_operations)) = v_module in
(Base.bool_or ((Base.bool_not ((Base.list_is_empty ((f_seeds (v_functions))))))) ((Base.bool_not ((Base.list_is_empty ((f_constant_seeds (v_constants)))))))))
and (* monomorph.bend:2063 *)
f_finish_expansion : t_Specialization -> (M.t_Diagnostic, t_ExpandedModule) Base.result_ =
fun v_specialized ->
(let (Specialization (v_module, v_environment, v_choices, v_counter, v_certificates)) = v_specialized in
(let (M.Module (v_constants, v_functions, v_types, v_operations)) = v_module in
(let v_members = (G.f_names ((Base.list_append ((G.f_function_declarations (v_functions))) ((G.f_constant_declarations (v_constants)))))) in
(match (f_finish (v_specialized)) with
| Fail __error -> Fail __error
| Done v_prepared ->
(match (D.f_function_nodes (v_functions)) with
| Fail __error -> Fail __error
| Done v_function_nodes ->
(match (D.f_constant_nodes (v_constants)) with
| Fail __error -> Fail __error
| Done v_constant_nodes ->
(match (G.f_generalize_component (v_environment) (v_members) (v_operations) (v_types) ((Base.list_append (v_function_nodes) (v_constant_nodes)))) with
| Fail __error -> Fail __error
| Done v_generalized ->
(match (f_resolved_bindings ((G.f_referenced_bindings ((G.f_env_bindings (v_generalized))) (v_members))) ((I.f_substitutions_of ((G.f_env_state (v_generalized)))))) with
| Fail __error -> Fail __error
| Done v_bindings ->
(match (Public.f_select (v_prepared) (v_bindings) (Public.Resolved)) with
| Fail __error -> Fail __error
| Done v_selected ->
(match (Public.f_generated_bindings (v_selected) (v_bindings)) with
| Fail __error -> Fail __error
| Done v_interfaces ->
(Done ((ExpandedModule (v_selected, v_counter, v_interfaces, v_certificates))))))))))))))
and (* monomorph.bend:2077 *)
f_selected_reference : (t_Choice) option -> (Base.text) list -> (Base.text) list =
fun v_found v_tail ->
(match v_found with
| (Some ((FunctionChoice (v_name, v_signature)))) ->
(v_name :: v_tail)
| (Some ((ReceiverChoice (v_name, v_signature)))) ->
(v_name :: v_tail)
| _ ->
v_tail)
and (* monomorph.bend:2086 *)
f_answer_reference : C.t_EvidenceAnswer -> (Base.text) list -> (Base.text) list =
fun v_answer v_tail ->
(match v_answer with
| (C.EvidenceAnswer (v_predicate, (C.SelectedFunction (v_name, v_signature)))) ->
(v_name :: v_tail)
| (C.EvidenceAnswer (v_predicate, (C.SelectedField (v_owner, v_member, v_accessor, v_signature)))) ->
(v_accessor :: v_tail)
| _ ->
v_tail)
and (* monomorph.bend:2095 *)
f_qualified_reference_match : (M.t_Predicate) list -> (C.t_EvidenceAnswer) list -> M.t_Predicate -> (Base.text) list -> (Base.text) list =
fun v_solved v_answers v_wanted v_tail ->
(match (v_solved, v_answers) with
| ((v_head :: v_rest), (v_answer :: v_remaining)) ->
(Base.bool_pick ((C.f_same_predicate (v_head) (v_wanted))) ((f_answer_reference (v_answer) (v_tail))) ((f_qualified_reference_match (v_rest) (v_remaining) (v_wanted) (v_tail))))
| (_, _) ->
v_tail)
and (* monomorph.bend:2102 *)
f_qualified_reference : (t_Choice) option -> M.t_Predicate -> (Base.text) list -> (Base.text) list =
fun v_found v_wanted v_tail ->
(match v_found with
| (Some ((QualifiedChoice (v_solved, v_answers)))) ->
(f_qualified_reference_match (v_solved) (v_answers) (v_wanted) (v_tail))
| _ ->
v_tail)
and (* monomorph.bend:2109 *)
f_selected_references : (I.t_Coverage) list -> (t_Choice) Base.map -> (Base.text) list =
fun v_constraints v_choices ->
(match v_constraints with
| [] ->
[]
| ((I.AssociatedNeed (v_identity, v_dispatch, v_member, v_templates, v_left, v_right, v_result, v_invocation, v_ambient, v_subject)) :: v_tail) ->
(f_selected_reference ((f_choice (v_choices) (v_identity))) ((f_selected_references (v_tail) (v_choices))))
| ((I.QualifiedNeed (v_site, v_predicate, v_subject)) :: v_tail) ->
(f_qualified_reference ((f_qualified_choice (v_choices) (v_site))) (v_predicate) ((f_selected_references (v_tail) (v_choices))))
| (v_head :: v_tail) ->
(f_selected_references (v_tail) (v_choices)))
and (* monomorph.bend:2120 *)
f_selected_edges : (I.t_Definition) list -> (t_Choice) Base.map -> ((Base.text) list) Base.map -> ((Base.text) list) Base.map =
fun v_definitions v_choices v_edges ->
(match v_definitions with
| [] ->
v_edges
| ((I.Definition (v_name, (I.Inference (v_ty, v_coverage, v_exits, v_reflections, v_predicates, v_uses)))) :: v_tail) ->
(f_selected_edges (v_tail) (v_choices) ((Base.map_set (v_edges) (v_name) ((Base.list_append ((f_selected_references ((Base.list_append (v_coverage) ((I.f_execution_needs (v_uses))))) (v_choices))) ((D.f_neighbors (v_edges) (v_name)))))))))
and (* monomorph.bend:2127 *)
f_required_function_roots : (M.t_Function) list -> (Base.text) list -> (I.t_Binding) list -> T.t_Substitutions -> (M.t_Diagnostic, (Base.text) list) Base.result_ =
fun v_functions v_originals v_bindings v_substitutions ->
(match v_functions with
| [] ->
(Done ([]))
| ((M.Function (v_name, v_exported, v_parameter, v_p, v_r, v_body)) :: v_tail) ->
(match (G.f_binding_type ((I.f_lookup_binding (v_bindings) (v_name))) (v_name)) with
| Fail __error -> Fail __error
| Done v_ty ->
(match (T.f_resolve (v_substitutions) (v_ty)) with
| Fail __error -> Fail __error
| Done v_resolved ->
(match (f_required_function_roots (v_tail) (v_originals) (v_bindings) (v_substitutions)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done ((Base.bool_pick ((Base.bool_and ((D.f_contains (v_originals) (v_name))) ((Base.bool_not ((Base.bool_and (v_exported) ((f_polymorphic (65536) ([v_resolved]))))))))) ((v_name :: v_rest)) (v_rest))))))))
and (* monomorph.bend:2138 *)
f_required_constant_roots : (M.t_Constant) list -> (I.t_Binding) list -> T.t_Substitutions -> (M.t_Diagnostic, (Base.text) list) Base.result_ =
fun v_constants v_bindings v_substitutions ->
(match v_constants with
| [] ->
(Done ([]))
| ((M.Constant (v_name, v_exported, v_annotation, v_value)) :: v_tail) ->
(match (G.f_binding_type ((I.f_lookup_binding (v_bindings) (v_name))) (v_name)) with
| Fail __error -> Fail __error
| Done v_ty ->
(match (T.f_resolve (v_substitutions) (v_ty)) with
| Fail __error -> Fail __error
| Done v_resolved ->
(match (f_required_constant_roots (v_tail) (v_bindings) (v_substitutions)) with
| Fail __error -> Fail __error
| Done v_rest ->
(let v_generic_alias = (Base.bool_and (v_exported) ((Base.bool_and ((f_template_value (65536) (v_value))) ((f_polymorphic (65536) ([v_resolved])))))) in
(Done ((Base.bool_pick ((Base.bool_or ((Base.string_starts_with (v_name) (s_5))) (v_generic_alias))) (v_rest) ((v_name :: v_rest))))))))))
and (* monomorph.bend:2150 *)
f_reached_functions : (M.t_Function) list -> Base.set -> (M.t_Function) list =
fun v_functions v_needed ->
(match v_functions with
| [] ->
[]
| (v_function :: v_tail) ->
(let (M.Function (v_name, v_exported, v_parameter, v_p, v_r, v_body)) = v_function in
(let v_rest = (f_reached_functions (v_tail) (v_needed)) in
(Base.bool_pick ((D.f_member (v_needed) (v_name))) ((v_function :: v_rest)) (v_rest)))))
and (* monomorph.bend:2159 *)
f_reached_constants : (M.t_Constant) list -> Base.set -> (M.t_Constant) list =
fun v_constants v_needed ->
(match v_constants with
| [] ->
[]
| (v_constant :: v_tail) ->
(let (M.Constant (v_name, v_exported, v_annotation, v_value)) = v_constant in
(let v_rest = (f_reached_constants (v_tail) (v_needed)) in
(Base.bool_pick ((D.f_member (v_needed) (v_name))) ((v_constant :: v_rest)) (v_rest)))))
and (* monomorph.bend:2168 *)
f_reached_definitions : (I.t_Definition) list -> Base.set -> (I.t_Definition) list =
fun v_definitions v_needed ->
(match v_definitions with
| [] ->
[]
| ((I.Definition (v_name, v_inference)) :: v_tail) ->
(let v_rest = (f_reached_definitions (v_tail) (v_needed)) in
(Base.bool_pick ((D.f_member (v_needed) (v_name))) (((I.Definition (v_name, v_inference)) :: v_rest)) (v_rest))))
and (* monomorph.bend:2176 *)
f_require_solved : (I.t_Coverage) list -> t_Specialization -> (M.t_Diagnostic, t_Specialization) Base.result_ =
fun v_needs v_specialization ->
(match v_needs with
| [] ->
(Done (v_specialization))
| (v_head :: v_tail) ->
(f_unfinished (v_head)))
and (* monomorph.bend:2186 *)
f_resolve_evidence : C.t_Evidence -> T.t_Substitutions -> (M.t_Diagnostic, C.t_Evidence) Base.result_ =
fun v_evidence v_substitutions ->
(match v_evidence with
| (C.SelectedFunction (v_name, v_signature)) ->
(match (T.f_resolve (v_substitutions) (v_signature)) with
| Fail __error -> Fail __error
| Done v_resolved ->
(Done ((C.SelectedFunction (v_name, v_resolved)))))
| (C.SelectedField (v_owner, v_member, v_accessor, v_signature)) ->
(match (T.f_resolve (v_substitutions) (v_signature)) with
| Fail __error -> Fail __error
| Done v_resolved ->
(Done ((C.SelectedField (v_owner, v_member, v_accessor, v_resolved)))))
| (C.SelectedOperation (v_identity, v_signature)) ->
(match (T.f_resolve (v_substitutions) (v_signature)) with
| Fail __error -> Fail __error
| Done v_resolved ->
(Done ((C.SelectedOperation (v_identity, v_resolved)))))
| (C.RepresentedType (v_represented)) ->
(match (T.f_resolve (v_substitutions) (v_represented)) with
| Fail __error -> Fail __error
| Done v_resolved ->
(Done ((C.RepresentedType (v_resolved)))))
| (C.RepresentedEffect (v_row)) ->
(Done ((C.RepresentedEffect ((Rows.f_canonical ((T.f_resolve_row (v_substitutions) (v_row)))))))))
and (* monomorph.bend:2207 *)
f_compare_exact_invocation : M.t_EffectRow -> M.t_EffectRow -> Base.text -> (M.t_Diagnostic, unit) Base.result_ =
fun v_invocation v_exact v_subject ->
(match v_invocation with
| (M.EffectRow (v_operations, M.ClosedRow)) ->
(Base.bool_pick ((C.f_same_type_ids ((Rows.f_row_operations ((Rows.f_canonical ((M.EffectRow (v_operations, M.ClosedRow))))))) ((Rows.f_row_operations ((Rows.f_canonical (v_exact))))))) ((Done (()))) ((Fail ((M.Diagnostic (s_100, v_subject, s_101))))))
| v_other ->
(Fail ((M.Diagnostic (s_32, v_subject, s_102)))))
and (* monomorph.bend:2214 *)
f_compare_found_exact_invocation : M.t_EffectRow -> (M.t_EffectRow) option -> Base.text -> (M.t_Diagnostic, unit) Base.result_ =
fun v_invocation v_exact v_subject ->
(match v_exact with
| (Some (v_row)) ->
(f_compare_exact_invocation (v_invocation) (v_row) (v_subject))
| None ->
(Fail ((M.Diagnostic (s_32, v_subject, s_103)))))
and (* monomorph.bend:2221 *)
f_validate_exact_invocation : M.t_EffectRow -> (M.t_Diagnostic, (M.t_EffectRow) option) Base.result_ -> Base.text -> (M.t_Diagnostic, unit) Base.result_ =
fun v_invocation v_found v_subject ->
(match v_found with
| Fail __error -> Fail __error
| Done v_exact ->
(f_compare_found_exact_invocation (v_invocation) (v_exact) (v_subject)))
and (* monomorph.bend:2226 *)
f_resolved_selected_invocation : (t_Choice) option -> T.t_Substitutions -> bool -> (M.t_Diagnostic, (M.t_EffectRow) option) Base.result_ =
fun v_found v_substitutions v_binary ->
(match (v_found, v_binary) with
| ((Some ((FunctionChoice (v_name, v_signature)))), true) ->
(match (T.f_resolve (v_substitutions) (v_signature)) with
| Fail __error -> Fail __error
| Done v_ty ->
(f_selected_binary_invocation (v_ty)))
| ((Some ((ReceiverChoice (v_name, v_signature)))), true) ->
(match (T.f_resolve (v_substitutions) (v_signature)) with
| Fail __error -> Fail __error
| Done v_ty ->
(f_selected_binary_invocation (v_ty)))
| ((Some ((ReceiverChoice (v_name, v_signature)))), false) ->
(match (T.f_resolve (v_substitutions) (v_signature)) with
| Fail __error -> Fail __error
| Done v_ty ->
(f_selected_receiver_invocation (v_ty)))
| (_, _) ->
(Fail ((M.Diagnostic (s_0, s_104, s_105)))))
and (* monomorph.bend:2243 *)
f_validate_qualified_invocation : M.t_Predicate -> C.t_Evidence -> Base.text -> (M.t_Diagnostic, unit) Base.result_ =
fun v_predicate v_evidence v_subject ->
(match (v_predicate, v_evidence) with
| ((M.AssociatedPredicate (v_member, v_templates, v_left, v_right, v_result, v_invocation)), (C.SelectedFunction (v_name, v_signature))) ->
(f_validate_exact_invocation (v_invocation) ((f_exact_binary_invocation (v_signature))) (v_subject))
| ((M.UpdatePredicate (v_member, v_receiver, v_assigned, v_result, v_invocation)), (C.SelectedField (v_owner, v_field, v_accessor, v_signature))) ->
(f_validate_exact_invocation (v_invocation) ((f_exact_binary_invocation (v_signature))) (v_subject))
| ((M.ReceiverPredicate (v_member, v_templates, v_receiver, v_argument, v_result, v_invocation)), (C.SelectedFunction (v_name, v_signature))) ->
(f_validate_exact_invocation (v_invocation) ((f_exact_receiver_invocation (v_signature))) (v_subject))
| ((M.ReceiverPredicate (v_member, v_templates, v_receiver, v_argument, v_result, v_invocation)), (C.SelectedField (v_owner, v_field, v_accessor, v_signature))) ->
(f_validate_exact_invocation (v_invocation) ((f_exact_receiver_invocation (v_signature))) (v_subject))
| ((M.AssociatedPredicate (v_member, v_templates, v_left, v_right, v_result, v_invocation)), v_other) ->
(Fail ((M.Diagnostic (s_0, v_subject, s_106))))
| ((M.UpdatePredicate (v_member, v_receiver, v_assigned, v_result, v_invocation)), v_other) ->
(Fail ((M.Diagnostic (s_0, v_subject, s_107))))
| ((M.ReceiverPredicate (v_member, v_templates, v_receiver, v_argument, v_result, v_invocation)), v_other) ->
(Fail ((M.Diagnostic (s_0, v_subject, s_108))))
| (_, _) ->
(Done (())))
and (* monomorph.bend:2262 *)
f_finalize_answer : C.t_EvidenceAnswer -> T.t_Substitutions -> Base.text -> (M.t_Diagnostic, C.t_EvidenceAnswer) Base.result_ =
fun v_answer v_substitutions v_subject ->
(let (C.EvidenceAnswer (v_predicate, v_evidence)) = v_answer in
(match (C.f_resolve (v_substitutions) (v_predicate)) with
| Fail __error -> Fail __error
| Done v_resolved_predicate ->
(match (f_resolve_evidence (v_evidence) (v_substitutions)) with
| Fail __error -> Fail __error
| Done v_resolved_evidence ->
(match (f_validate_evidence (v_resolved_evidence) (v_subject)) with
| Fail __error -> Fail __error
| Done v_valid ->
(match (f_validate_qualified_invocation (v_resolved_predicate) (v_resolved_evidence) (v_subject)) with
| Fail __error -> Fail __error
| Done v_row_valid ->
(Done ((C.EvidenceAnswer (v_resolved_predicate, v_resolved_evidence)))))))))
and (* monomorph.bend:2271 *)
f_finalize_answers : (C.t_EvidenceAnswer) list -> T.t_Substitutions -> Base.text -> (M.t_Diagnostic, (C.t_EvidenceAnswer) list) Base.result_ =
fun v_answers v_substitutions v_subject ->
(match v_answers with
| [] ->
(Done ([]))
| (v_answer :: v_tail) ->
(match (f_finalize_answer (v_answer) (v_substitutions) (v_subject)) with
| Fail __error -> Fail __error
| Done v_first ->
(match (f_finalize_answers (v_tail) (v_substitutions) (v_subject)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done ((v_first :: v_rest))))))
and (* monomorph.bend:2281 *)
f_finalize_qualified_choice : (t_Choice) option -> T.t_Substitutions -> Base.text -> (M.t_Diagnostic, t_Choice) Base.result_ =
fun v_found v_substitutions v_subject ->
(match v_found with
| (Some ((QualifiedChoice (v_solved, v_answers)))) ->
(match (f_finalize_answers (v_answers) (v_substitutions) (v_subject)) with
| Fail __error -> Fail __error
| Done v_resolved ->
(Done ((QualifiedChoice (v_solved, v_resolved)))))
| _ ->
(Fail ((M.Diagnostic (s_0, v_subject, s_109)))))
and (* monomorph.bend:2293 *)
f_compare_ordinary_invocation : M.t_EffectRow -> (M.t_EffectRow) option -> Base.text -> (M.t_Diagnostic, unit) Base.result_ =
fun v_invocation v_found v_subject ->
(match (v_invocation, v_found) with
| ((M.EffectRow (v_operations, (M.FreeRow (v_scope, v_name)))), _) ->
(Fail ((M.Diagnostic (s_32, v_subject, s_110))))
| (_, (Some ((M.EffectRow (v_operations, (M.FreeRow (v_scope, v_name))))))) ->
(Fail ((M.Diagnostic (s_32, v_subject, s_111))))
| (_, (Some (v_exact))) ->
(Base.bool_pick ((C.f_same_predicate ((M.EffectRepPredicate ((Rows.f_canonical (v_invocation))))) ((M.EffectRepPredicate ((Rows.f_canonical (v_exact))))))) ((Done (()))) ((Fail ((M.Diagnostic (s_100, v_subject, s_112))))))
| (_, None) ->
(Fail ((M.Diagnostic (s_32, v_subject, s_103)))))
and (* monomorph.bend:2304 *)
f_validate_ordinary_invocation : M.t_EffectRow -> (M.t_Diagnostic, (M.t_EffectRow) option) Base.result_ -> Base.text -> (M.t_Diagnostic, unit) Base.result_ =
fun v_invocation v_found v_subject ->
(match v_found with
| Fail __error -> Fail __error
| Done v_row ->
(f_compare_ordinary_invocation (v_invocation) (v_row) (v_subject)))
and (* monomorph.bend:2309 *)
f_finalize_coverage : (I.t_Coverage) list -> T.t_Substitutions -> (t_Choice) Base.map -> (M.t_Diagnostic, (t_Choice) Base.map) Base.result_ =
fun v_needs v_substitutions v_choices ->
(match v_needs with
| [] ->
(Done (v_choices))
| ((I.AssociatedNeed (v_identity, v_dispatch, v_member, v_templates, v_left, v_right, v_result, (Some (v_invocation)), v_ambient, v_subject)) :: v_tail) ->
(match (f_validate_ordinary_invocation ((T.f_resolve_row (v_substitutions) (v_invocation))) ((f_resolved_selected_invocation ((f_choice (v_choices) (v_identity))) (v_substitutions) ((f_associated_binary (v_dispatch))))) (v_subject)) with
| Fail __error -> Fail __error
| Done v_valid ->
(f_finalize_coverage (v_tail) (v_substitutions) (v_choices)))
| ((I.QualifiedNeed (v_site, v_predicate, v_subject)) :: v_tail) ->
(match (f_finalize_qualified_choice ((f_qualified_choice (v_choices) (v_site))) (v_substitutions) (v_subject)) with
| Fail __error -> Fail __error
| Done v_selected ->
(f_finalize_coverage (v_tail) (v_substitutions) ((Base.map_set (v_choices) ((f_qualified_key (v_site))) (v_selected)))))
| (v_head :: v_tail) ->
(f_finalize_coverage (v_tail) (v_substitutions) (v_choices)))
and (* monomorph.bend:2324 *)
f_finalize_definitions : (I.t_Definition) list -> T.t_Substitutions -> (t_Choice) Base.map -> (M.t_Diagnostic, (t_Choice) Base.map) Base.result_ =
fun v_definitions v_substitutions v_choices ->
(match v_definitions with
| [] ->
(Done (v_choices))
| ((I.Definition (v_name, (I.Inference (v_ty, v_coverage, v_exits, v_reflections, v_predicates, v_uses)))) :: v_tail) ->
(match (f_finalize_coverage ((Base.list_append (v_coverage) ((I.f_execution_needs (v_uses))))) (v_substitutions) (v_choices)) with
| Fail __error -> Fail __error
| Done v_selected ->
(f_finalize_definitions (v_tail) (v_substitutions) (v_selected))))
and (* monomorph.bend:2336 *)
f_type_eq_selected_same : (t_Choice) option -> (C.t_Evidence) option =
fun v_found ->
(match v_found with
| (Some ((FunctionChoice (v_name, v_signature)))) ->
(Some ((C.SelectedFunction (v_name, v_signature))))
| _ ->
None)
and (* monomorph.bend:2343 *)
f_type_eq_same_resolved : (M.t_Diagnostic, C.t_Evidence) Base.result_ -> M.t_Predicate -> C.t_Evidence -> int -> M.t_Module -> (M.t_Ty) option =
fun v_found v_predicate v_outer v_site v_module ->
(match v_found with
| (Done (v_same)) ->
(TypeEq.f_certified_signature (v_predicate) (v_outer) (v_site) (v_same) (v_module))
| (Fail (v_diagnostic)) ->
None)
and (* monomorph.bend:2350 *)
f_type_eq_same_found : (C.t_Evidence) option -> M.t_Predicate -> C.t_Evidence -> int -> M.t_Module -> T.t_Substitutions -> (M.t_Ty) option =
fun v_found v_predicate v_outer v_site v_module v_substitutions ->
(match v_found with
| (Some (v_same)) ->
(f_type_eq_same_resolved ((f_resolve_evidence (v_same) (v_substitutions))) (v_predicate) (v_outer) (v_site) (v_module))
| None ->
None)
and (* monomorph.bend:2357 *)
f_type_eq_site_found : (int) option -> M.t_Predicate -> C.t_Evidence -> (t_Choice) Base.map -> M.t_Module -> T.t_Substitutions -> (M.t_Ty) option =
fun v_found v_predicate v_outer v_choices v_module v_substitutions ->
(match v_found with
| (Some (v_site)) ->
(f_type_eq_same_found ((f_type_eq_selected_same ((f_choice (v_choices) (v_site))))) (v_predicate) (v_outer) (v_site) (v_module) (v_substitutions))
| None ->
None)
and (* monomorph.bend:2364 *)
f_type_eq_input_type : M.t_Ty -> bool =
fun v_ty ->
(match v_ty with
| (M.AppliedTy (v_identity, (v_argument :: []))) ->
(M.f_type_id_equal (v_identity) ((M.TypeId (s_14, s_113))))
| _ ->
false)
and (* monomorph.bend:2371 *)
f_type_eq_input_signature : C.t_Evidence -> bool =
fun v_evidence ->
(match v_evidence with
| (C.SelectedFunction (v_name, (M.FunctionTy (v_left, (M.FunctionTy (v_right, M.BoolTy, v_inner)), v_outer)))) ->
(Base.bool_and ((f_type_eq_input_type (v_left))) ((f_type_eq_input_type (v_right))))
| _ ->
false)
and (* monomorph.bend:2378 *)
f_type_eq_input_ready : bool -> M.t_Predicate -> C.t_Evidence -> (t_Choice) Base.map -> M.t_Module -> T.t_Substitutions -> (M.t_Ty) option =
fun v_valid v_predicate v_outer v_choices v_module v_substitutions ->
(match v_valid with
| true ->
(f_type_eq_site_found ((TypeEq.f_clone_site (v_outer) (v_module))) (v_predicate) (v_outer) (v_choices) (v_module) (v_substitutions))
| false ->
None)
and (* monomorph.bend:2385 *)
f_type_eq_resolved : (M.t_Diagnostic, M.t_Predicate) Base.result_ -> (M.t_Diagnostic, C.t_Evidence) Base.result_ -> (t_Choice) Base.map -> M.t_Module -> T.t_Substitutions -> (M.t_Ty) option =
fun v_predicate v_evidence v_choices v_module v_substitutions ->
(match (v_predicate, v_evidence) with
| ((Done (v_resolved)), (Done (v_outer))) ->
(f_type_eq_input_ready ((f_type_eq_input_signature (v_outer))) (v_resolved) (v_outer) (v_choices) (v_module) (v_substitutions))
| (_, _) ->
None)
and (* monomorph.bend:2392 *)
f_type_eq_request : M.t_Predicate -> bool =
fun v_predicate ->
(match v_predicate with
| (M.AssociatedPredicate (v_member, [], v_left, v_right, v_result, v_invocation)) ->
(M.f_name_equal (v_member) (s_114))
| _ ->
false)
and (* monomorph.bend:2399 *)
f_certify_type_eq_request : bool -> M.t_Predicate -> C.t_Evidence -> T.t_Substitutions -> (t_Choice) Base.map -> M.t_Module -> (M.t_Ty) option =
fun v_valid v_predicate v_evidence v_substitutions v_choices v_module ->
(match v_valid with
| true ->
(f_type_eq_resolved ((C.f_resolve (v_substitutions) (v_predicate))) ((f_resolve_evidence (v_evidence) (v_substitutions))) (v_choices) (v_module) (v_substitutions))
| false ->
None)
and (* monomorph.bend:2406 *)
f_type_eq_choice_name : C.t_Evidence -> bool =
fun v_evidence ->
(match v_evidence with
| (C.SelectedFunction (v_name, v_signature)) ->
(TypeEq.f_source_clone (v_name))
| _ ->
false)
and (* monomorph.bend:2413 *)
f_certify_type_eq : M.t_Predicate -> C.t_Evidence -> T.t_Substitutions -> (t_Choice) Base.map -> M.t_Module -> (M.t_Ty) option =
fun v_predicate v_evidence v_substitutions v_choices v_module ->
(f_certify_type_eq_request ((Base.bool_and ((f_type_eq_request (v_predicate))) ((f_type_eq_choice_name (v_evidence))))) (v_predicate) (v_evidence) (v_substitutions) (v_choices) (v_module))
and (* monomorph.bend:2416 *)
f_with_type_eq_signature : (M.t_Ty) option -> C.t_Evidence -> C.t_Evidence =
fun v_found v_evidence ->
(match (v_found, v_evidence) with
| ((Some (v_signature)), (C.SelectedFunction (v_name, v_old))) ->
(C.SelectedFunction (v_name, v_signature))
| (_, v_other) ->
v_other)
and (* monomorph.bend:2423 *)
f_refresh_type_eq_answer : C.t_EvidenceAnswer -> T.t_Substitutions -> (t_Choice) Base.map -> M.t_Module -> C.t_EvidenceAnswer =
fun v_answer v_substitutions v_choices v_module ->
(let (C.EvidenceAnswer (v_predicate, v_evidence)) = v_answer in
(C.EvidenceAnswer (v_predicate, (f_with_type_eq_signature ((f_certify_type_eq (v_predicate) (v_evidence) (v_substitutions) (v_choices) (v_module))) (v_evidence)))))
and (* monomorph.bend:2427 *)
f_refresh_type_eq_answers : (C.t_EvidenceAnswer) list -> T.t_Substitutions -> (t_Choice) Base.map -> M.t_Module -> (C.t_EvidenceAnswer) list =
fun v_answers v_substitutions v_choices v_module ->
(match v_answers with
| [] ->
[]
| (v_head :: v_tail) ->
((f_refresh_type_eq_answer (v_head) (v_substitutions) (v_choices) (v_module)) :: (f_refresh_type_eq_answers (v_tail) (v_substitutions) (v_choices) (v_module))))
and (* monomorph.bend:2434 *)
f_refreshed_type_eq_function : (M.t_Ty) option -> Base.text -> M.t_Ty -> t_Choice =
fun v_found v_name v_signature ->
(match v_found with
| (Some (v_exact)) ->
(FunctionChoice (v_name, v_exact))
| None ->
(FunctionChoice (v_name, v_signature)))
and (* monomorph.bend:2441 *)
f_refresh_type_eq_function : (t_Choice) option -> M.t_Predicate -> T.t_Substitutions -> (t_Choice) Base.map -> M.t_Module -> (t_Choice) option =
fun v_found v_predicate v_substitutions v_choices v_module ->
(match v_found with
| (Some ((FunctionChoice (v_name, v_signature)))) ->
(Some ((f_refreshed_type_eq_function ((f_certify_type_eq (v_predicate) ((C.SelectedFunction (v_name, v_signature))) (v_substitutions) (v_choices) (v_module))) (v_name) (v_signature))))
| v_other ->
v_other)
and (* monomorph.bend:2448 *)
f_refresh_type_eq_qualified : (t_Choice) option -> T.t_Substitutions -> (t_Choice) Base.map -> M.t_Module -> (t_Choice) option =
fun v_found v_substitutions v_choices v_module ->
(match v_found with
| (Some ((QualifiedChoice (v_solved, v_answers)))) ->
(Some ((QualifiedChoice (v_solved, (f_refresh_type_eq_answers (v_answers) (v_substitutions) (v_choices) (v_module))))))
| v_other ->
v_other)
and (* monomorph.bend:2455 *)
f_store_type_eq_choice : (t_Choice) option -> Base.text -> (t_Choice) Base.map -> (t_Choice) Base.map =
fun v_found v_key v_choices ->
(match v_found with
| (Some (v_selected)) ->
(Base.map_set (v_choices) (v_key) (v_selected))
| None ->
v_choices)
and (* monomorph.bend:2462 *)
f_refresh_type_eq_need : I.t_Coverage -> T.t_Substitutions -> (t_Choice) Base.map -> M.t_Module -> (t_Choice) Base.map =
fun v_need v_substitutions v_choices v_module ->
(match v_need with
| (I.AssociatedNeed (v_site, M.BinaryDispatch, v_member, v_templates, v_left, v_right, v_result, (Some (v_invocation)), v_ambient, v_subject)) ->
(f_store_type_eq_choice ((f_refresh_type_eq_function ((f_choice (v_choices) (v_site))) ((M.AssociatedPredicate (v_member, v_templates, v_left, v_right, v_result, v_invocation))) (v_substitutions) (v_choices) (v_module))) ((Base.nat_show (v_site))) (v_choices))
| (I.QualifiedNeed (v_site, v_predicate, v_subject)) ->
(f_store_type_eq_choice ((f_refresh_type_eq_qualified ((f_qualified_choice (v_choices) (v_site))) (v_substitutions) (v_choices) (v_module))) ((f_qualified_key (v_site))) (v_choices))
| _ ->
v_choices)
and (* monomorph.bend:2471 *)
f_refresh_type_eq_needs : (I.t_Coverage) list -> T.t_Substitutions -> (t_Choice) Base.map -> M.t_Module -> (t_Choice) Base.map =
fun v_needs v_substitutions v_choices v_module ->
(match v_needs with
| [] ->
v_choices
| (v_head :: v_tail) ->
(f_refresh_type_eq_needs (v_tail) (v_substitutions) ((f_refresh_type_eq_need (v_head) (v_substitutions) (v_choices) (v_module))) (v_module)))
and (* monomorph.bend:2478 *)
f_refresh_type_eq_definitions : (I.t_Definition) list -> T.t_Substitutions -> (t_Choice) Base.map -> M.t_Module -> (t_Choice) Base.map =
fun v_definitions v_substitutions v_choices v_module ->
(match v_definitions with
| [] ->
v_choices
| ((I.Definition (v_name, (I.Inference (v_ty, v_coverage, v_exits, v_reflections, v_predicates, v_uses)))) :: v_tail) ->
(f_refresh_type_eq_definitions (v_tail) (v_substitutions) ((f_refresh_type_eq_needs ((Base.list_append (v_coverage) ((I.f_execution_needs (v_uses))))) (v_substitutions) (v_choices) (v_module))) (v_module)))
and (* monomorph.bend:2487 *)
f_type_eq_closed_invocation : M.t_Predicate -> bool =
fun v_predicate ->
(match v_predicate with
| (M.AssociatedPredicate (v_member, v_templates, v_left, v_right, v_result, (M.EffectRow ([], M.ClosedRow)))) ->
true
| _ ->
false)
and (* monomorph.bend:2494 *)
f_exact_type_eq_certificate : (M.t_Ty) option -> C.t_Evidence -> bool =
fun v_found v_evidence ->
(match (v_found, v_evidence) with
| ((Some (v_expected)), (C.SelectedFunction (v_name, v_actual))) ->
(Compare.f_same_ty (v_expected) (v_actual))
| (_, _) ->
false)
and (* monomorph.bend:2505 *)
f_scoped_variables : (I.t_Binding) option -> (int) list =
fun v_found ->
(match v_found with
| (Some ((I.Binding (v_name, v_ty, v_variables, v_predicates)))) ->
v_variables
| None ->
[])
and (* monomorph.bend:2512 *)
f_restore_scoped_diagnostic : (M.t_Diagnostic, C.t_EvidenceAnswer) Base.result_ -> M.t_Diagnostic -> (M.t_Diagnostic, C.t_EvidenceAnswer) Base.result_ =
fun v_found v_original ->
(match v_found with
| (Done (v_answer)) ->
(Done (v_answer))
| (Fail (v_diagnostic)) ->
(Fail (v_original)))
and (* monomorph.bend:2522 *)
f_scoped_binding_count : (I.t_Binding) list -> Base.text -> int =
fun v_bindings v_wanted ->
(match v_bindings with
| [] ->
0
| ((I.Binding (v_name, v_ty, v_variables, v_predicates)) :: v_tail) ->
(Base.nat_add ((Base.bool_pick ((M.f_name_equal (v_name) (v_wanted))) (1) (0))) ((f_scoped_binding_count (v_tail) (v_wanted)))))
and (* monomorph.bend:2529 *)
f_scoped_binding_resolved : (M.t_Diagnostic, M.t_Ty) Base.result_ -> Base.text -> (int) list -> C.t_Evidence -> (int) list -> bool =
fun v_found v_name v_variables v_evidence v_bound ->
(match v_found with
| (Done (v_ty)) ->
(SelectedBindingEvidence.f_certify ((I.Binding (v_name, v_ty, v_variables, []))) (v_evidence) (v_bound))
| (Fail (v_diagnostic)) ->
false)
and (* monomorph.bend:2536 *)
f_scoped_binding_found : (I.t_Binding) option -> C.t_Evidence -> (int) list -> T.t_Substitutions -> bool =
fun v_found v_evidence v_bound v_substitutions ->
(match v_found with
| (Some ((I.Binding (v_name, v_ty, v_variables, [])))) ->
(f_scoped_binding_resolved ((T.f_resolve (v_substitutions) (v_ty))) (v_name) (v_variables) (v_evidence) (v_bound))
| _ ->
false)
and (* monomorph.bend:2543 *)
f_scoped_binding_unique : bool -> (I.t_Binding) list -> Base.text -> C.t_Evidence -> (int) list -> T.t_Substitutions -> bool =
fun v_unique v_bindings v_name v_evidence v_bound v_substitutions ->
(match v_unique with
| true ->
(f_scoped_binding_found ((I.f_lookup_binding (v_bindings) (v_name))) (v_evidence) (v_bound) (v_substitutions))
| false ->
false)
and (* monomorph.bend:2550 *)
f_scoped_binding_certificate : C.t_Evidence -> (I.t_Binding) list -> (int) list -> T.t_Substitutions -> bool =
fun v_evidence v_bindings v_bound v_substitutions ->
(match v_evidence with
| (C.SelectedFunction (v_name, v_signature)) ->
(f_scoped_binding_unique ((Base.nat_is_eq ((f_scoped_binding_count (v_bindings) (v_name))) (1))) (v_bindings) (v_name) (v_evidence) (v_bound) (v_substitutions))
| _ ->
false)
and (* monomorph.bend:2557 *)
f_member_certificate_count : (t_MemberEvidenceCertificate) list -> Base.text -> int =
fun v_certified v_wanted ->
(match v_certified with
| [] ->
0
| ((MemberEvidenceCertificate (v_name, v_signature)) :: v_tail) ->
(Base.nat_add ((Base.bool_pick ((M.f_name_equal (v_name) (v_wanted))) (1) (0))) ((f_member_certificate_count (v_tail) (v_wanted)))))
and (* monomorph.bend:2564 *)
f_member_certificate_signature : (t_MemberEvidenceCertificate) list -> Base.text -> M.t_Ty -> bool =
fun v_certified v_name v_signature ->
(match v_certified with
| [] ->
false
| ((MemberEvidenceCertificate (v_found, v_exact)) :: v_tail) ->
(Base.bool_or ((Base.bool_and ((M.f_name_equal (v_found) (v_name))) ((Compare.f_same_ty (v_exact) (v_signature))))) ((f_member_certificate_signature (v_tail) (v_name) (v_signature)))))
and (* monomorph.bend:2571 *)
f_member_binding_resolved : (M.t_Diagnostic, M.t_Ty) Base.result_ -> M.t_Ty -> bool =
fun v_found v_signature ->
(match v_found with
| (Done (v_current)) ->
(Compare.f_same_ty (v_current) (v_signature))
| (Fail (v_diagnostic)) ->
false)
and (* monomorph.bend:2578 *)
f_member_binding_found : (I.t_Binding) option -> M.t_Ty -> T.t_Substitutions -> bool =
fun v_found v_signature v_substitutions ->
(match v_found with
| (Some ((I.Binding (v_name, v_ty, v_variables, v_predicates)))) ->
(f_member_binding_resolved ((T.f_resolve (v_substitutions) (v_ty))) (v_signature))
| None ->
false)
and (* monomorph.bend:2585 *)
f_member_signature_free : (M.t_Diagnostic, (int) list) Base.result_ -> (int) list -> bool =
fun v_found v_bound ->
(match v_found with
| (Done (v_free)) ->
(Base.list_is_empty ((T.f_difference (v_free) (v_bound))))
| (Fail (v_diagnostic)) ->
false)
and (* monomorph.bend:2595 *)
f_member_certificate_condition_present : C.t_Evidence -> (int) list -> (I.t_Binding) list -> T.t_Substitutions -> (t_MemberEvidenceCertificate) list -> bool =
fun v_evidence v_bound v_bindings v_substitutions v_certified ->
(match v_evidence with
| (C.SelectedFunction (v_name, v_signature)) ->
(Base.bool_and ((Base.bool_and ((Base.nat_is_eq ((f_member_certificate_count (v_certified) (v_name))) (1))) ((f_member_certificate_signature (v_certified) (v_name) (v_signature))))) ((Base.bool_and ((Base.bool_and ((Base.nat_is_eq ((f_scoped_binding_count (v_bindings) (v_name))) (1))) ((f_member_binding_found ((I.f_lookup_binding (v_bindings) (v_name))) (v_signature) (v_substitutions))))) ((Base.bool_and ((SelectedBindingEvidence.f_admissible_types (65536) ([v_signature]))) ((f_member_signature_free ((T.f_free (v_signature))) (v_bound))))))))
| _ ->
false)
and (* monomorph.bend:2610 *)
f_member_certificate_condition : C.t_Evidence -> (int) list -> (I.t_Binding) list -> T.t_Substitutions -> (t_MemberEvidenceCertificate) list -> bool =
fun v_evidence v_bound v_bindings v_substitutions v_certified ->
(match v_certified with
| [] ->
false
| (v_head :: v_tail) ->
(f_member_certificate_condition_present (v_evidence) (v_bound) (v_bindings) (v_substitutions) ((v_head :: v_tail))))
and (* monomorph.bend:2617 *)
f_scoped_binding_invocation : bool -> M.t_Predicate -> C.t_Evidence -> (M.t_Diagnostic, unit) Base.result_ =
fun v_valid v_predicate v_evidence ->
(match v_valid with
| true ->
(f_validate_qualified_invocation (v_predicate) (v_evidence) (s_115))
| false ->
(Fail ((M.Diagnostic (s_32, s_115, s_116)))))
and (* monomorph.bend:2624 *)
f_member_certificate_accept : M.t_Predicate -> C.t_Evidence -> (int) list -> (I.t_Binding) list -> T.t_Substitutions -> (t_MemberEvidenceCertificate) list -> (M.t_Diagnostic, unit) Base.result_ =
fun v_predicate v_evidence v_bound v_bindings v_substitutions v_certified ->
(f_scoped_binding_invocation ((f_member_certificate_condition (v_evidence) (v_bound) (v_bindings) (v_substitutions) (v_certified))) (v_predicate) (v_evidence))
and (* monomorph.bend:2627 *)
f_scoped_selected_certificate : bool -> M.t_Predicate -> C.t_Evidence -> (I.t_Binding) list -> (int) list -> T.t_Substitutions -> (t_MemberEvidenceCertificate) list -> (M.t_Diagnostic, unit) Base.result_ =
fun v_canonical v_predicate v_evidence v_bindings v_bound v_substitutions v_certified ->
(match v_canonical with
| true ->
(Done (()))
| false ->
(f_scoped_binding_invocation ((Base.bool_or ((f_scoped_binding_certificate (v_evidence) (v_bindings) (v_bound) (v_substitutions))) ((f_member_certificate_condition (v_evidence) (v_bound) (v_bindings) (v_substitutions) (v_certified))))) (v_predicate) (v_evidence)))
and (* monomorph.bend:2634 *)
f_prove_scoped_answer : C.t_EvidenceAnswer -> T.t_Substitutions -> (int) list -> M.t_Module -> (t_Choice) Base.map -> (I.t_Binding) list -> (t_MemberEvidenceCertificate) list -> (M.t_Diagnostic, C.t_EvidenceAnswer) Base.result_ =
fun v_answer v_substitutions v_bound v_module v_choices v_bindings v_certified ->
(let (C.EvidenceAnswer (v_predicate, v_evidence)) = v_answer in
(match (C.f_resolve (v_substitutions) (v_predicate)) with
| Fail __error -> Fail __error
| Done v_resolved_predicate ->
(match (f_resolve_evidence (v_evidence) (v_substitutions)) with
| Fail __error -> Fail __error
| Done v_resolved_evidence ->
(match (f_scoped_selected_certificate ((Base.bool_or ((Base.bool_or ((StateEvidence.f_certify_run (v_resolved_predicate) (v_resolved_evidence) (v_bound) (v_module))) ((ScopedStateEvidence.f_certify_scoped (v_resolved_predicate) (v_resolved_evidence) (v_bound) (v_module))))) ((Base.bool_and ((f_type_eq_closed_invocation (v_resolved_predicate))) ((f_exact_type_eq_certificate ((f_certify_type_eq (v_resolved_predicate) (v_resolved_evidence) (v_substitutions) (v_choices) (v_module))) (v_resolved_evidence))))))) (v_resolved_predicate) (v_resolved_evidence) (v_bindings) (v_bound) (v_substitutions) (v_certified)) with
| Fail __error -> Fail __error
| Done v_accepted ->
(Done ((C.EvidenceAnswer (v_resolved_predicate, v_resolved_evidence))))))))
and (* monomorph.bend:2642 *)
f_accept_scoped_answer : (M.t_Diagnostic, C.t_EvidenceAnswer) Base.result_ -> C.t_EvidenceAnswer -> T.t_Substitutions -> (int) list -> M.t_Module -> (t_Choice) Base.map -> (I.t_Binding) list -> (t_MemberEvidenceCertificate) list -> (M.t_Diagnostic, C.t_EvidenceAnswer) Base.result_ =
fun v_found v_answer v_substitutions v_bound v_module v_choices v_bindings v_certified ->
(match v_found with
| (Done (v_resolved)) ->
(Done (v_resolved))
| (Fail (v_diagnostic)) ->
(f_restore_scoped_diagnostic ((f_prove_scoped_answer (v_answer) (v_substitutions) (v_bound) (v_module) (v_choices) (v_bindings) (v_certified))) (v_diagnostic)))
and (* monomorph.bend:2649 *)
f_finalize_answers_scoped : (C.t_EvidenceAnswer) list -> T.t_Substitutions -> Base.text -> (int) list -> M.t_Module -> (t_Choice) Base.map -> (I.t_Binding) list -> (t_MemberEvidenceCertificate) list -> (M.t_Diagnostic, (C.t_EvidenceAnswer) list) Base.result_ =
fun v_answers v_substitutions v_subject v_bound v_module v_choices v_bindings v_certified ->
(match v_answers with
| [] ->
(Done ([]))
| (v_answer :: v_tail) ->
(match (f_accept_scoped_answer ((f_finalize_answer (v_answer) (v_substitutions) (v_subject))) (v_answer) (v_substitutions) (v_bound) (v_module) (v_choices) (v_bindings) (v_certified)) with
| Fail __error -> Fail __error
| Done v_first ->
(match (f_finalize_answers_scoped (v_tail) (v_substitutions) (v_subject) (v_bound) (v_module) (v_choices) (v_bindings) (v_certified)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done ((v_first :: v_rest))))))
and (* monomorph.bend:2659 *)
f_finalize_choice_scoped_certified : (t_Choice) option -> T.t_Substitutions -> Base.text -> (int) list -> M.t_Module -> (t_Choice) Base.map -> (I.t_Binding) list -> (t_MemberEvidenceCertificate) list -> (M.t_Diagnostic, t_Choice) Base.result_ =
fun v_found v_substitutions v_subject v_bound v_module v_choices v_bindings v_certified ->
(match v_found with
| (Some ((QualifiedChoice (v_solved, v_answers)))) ->
(match (f_finalize_answers_scoped (v_answers) (v_substitutions) (v_subject) (v_bound) (v_module) (v_choices) (v_bindings) (v_certified)) with
| Fail __error -> Fail __error
| Done v_resolved ->
(Done ((QualifiedChoice (v_solved, v_resolved)))))
| _ ->
(Fail ((M.Diagnostic (s_0, v_subject, s_109)))))
and (* monomorph.bend:2670 *)
f_finalize_choice_scoped : (t_Choice) option -> T.t_Substitutions -> Base.text -> (int) list -> M.t_Module -> (t_Choice) Base.map -> (I.t_Binding) list -> (M.t_Diagnostic, t_Choice) Base.result_ =
fun v_found v_substitutions v_subject v_bound v_module v_choices v_bindings ->
(f_finalize_choice_scoped_certified (v_found) (v_substitutions) (v_subject) (v_bound) (v_module) (v_choices) (v_bindings) ([]))
and (* monomorph.bend:2673 *)
f_finalize_coverage_scoped : (I.t_Coverage) list -> T.t_Substitutions -> (t_Choice) Base.map -> (int) list -> M.t_Module -> (I.t_Binding) list -> (t_MemberEvidenceCertificate) list -> (M.t_Diagnostic, (t_Choice) Base.map) Base.result_ =
fun v_needs v_substitutions v_choices v_bound v_module v_bindings v_certified ->
(match v_needs with
| [] ->
(Done (v_choices))
| ((I.QualifiedNeed (v_site, v_predicate, v_subject)) :: v_tail) ->
(match (f_finalize_choice_scoped_certified ((f_qualified_choice (v_choices) (v_site))) (v_substitutions) (v_subject) (v_bound) (v_module) (v_choices) (v_bindings) (v_certified)) with
| Fail __error -> Fail __error
| Done v_selected ->
(f_finalize_coverage_scoped (v_tail) (v_substitutions) ((Base.map_set (v_choices) ((f_qualified_key (v_site))) (v_selected))) (v_bound) (v_module) (v_bindings) (v_certified)))
| (v_head :: v_tail) ->
(match (f_finalize_coverage ([v_head]) (v_substitutions) (v_choices)) with
| Fail __error -> Fail __error
| Done v_selected ->
(f_finalize_coverage_scoped (v_tail) (v_substitutions) (v_selected) (v_bound) (v_module) (v_bindings) (v_certified))))
and (* monomorph.bend:2686 *)
f_finalize_definitions_scoped : (I.t_Definition) list -> T.t_Substitutions -> (t_Choice) Base.map -> (I.t_Binding) list -> M.t_Module -> (t_MemberEvidenceCertificate) list -> (M.t_Diagnostic, (t_Choice) Base.map) Base.result_ =
fun v_definitions v_substitutions v_choices v_bindings v_module v_certified ->
(match v_definitions with
| [] ->
(Done (v_choices))
| ((I.Definition (v_name, (I.Inference (v_ty, v_coverage, v_exits, v_reflections, v_predicates, v_uses)))) :: v_tail) ->
(match (f_finalize_coverage_scoped ((Base.list_append (v_coverage) ((I.f_execution_needs (v_uses))))) (v_substitutions) (v_choices) ((f_scoped_variables ((I.f_lookup_binding (v_bindings) (v_name))))) (v_module) (v_bindings) (v_certified)) with
| Fail __error -> Fail __error
| Done v_selected ->
(f_finalize_definitions_scoped (v_tail) (v_substitutions) (v_selected) (v_bindings) (v_module) (v_certified))))
and (* monomorph.bend:2695 *)
f_scoped_finalization : (M.t_Diagnostic, G.t_Environment) Base.result_ -> M.t_Module -> (t_Choice) Base.map -> M.t_Diagnostic -> (t_MemberEvidenceCertificate) list -> (M.t_Diagnostic, (t_Choice) Base.map) Base.result_ =
fun v_found v_module v_choices v_original v_certified ->
(match v_found with
| (Fail (v_diagnostic)) ->
(Fail (v_original))
| (Done (v_environment)) ->
(let (G.Environment (v_bindings, v_definitions, v_state)) = v_environment in
(f_finalize_definitions_scoped (v_definitions) ((I.f_substitutions_of (v_state))) (v_choices) (v_bindings) (v_module) (v_certified))))
and (* monomorph.bend:2703 *)
f_finalize_with_scope : (M.t_Diagnostic, (t_Choice) Base.map) Base.result_ -> M.t_Module -> G.t_Environment -> (t_Choice) Base.map -> (t_MemberEvidenceCertificate) list -> (M.t_Diagnostic, (t_Choice) Base.map) Base.result_ =
fun v_found v_module v_environment v_choices v_certified ->
(match v_found with
| (Done (v_answers)) ->
(Done (v_answers))
| (Fail (v_diagnostic)) ->
(let (M.Module (v_constants, v_functions, v_types, v_operations)) = v_module in
(let v_members = (G.f_names ((Base.list_append ((G.f_function_declarations (v_functions))) ((G.f_constant_declarations (v_constants)))))) in
(match (D.f_function_nodes (v_functions)) with
| Fail __error -> Fail __error
| Done v_function_nodes ->
(match (D.f_constant_nodes (v_constants)) with
| Fail __error -> Fail __error
| Done v_constant_nodes ->
(f_scoped_finalization ((G.f_generalize_component (v_environment) (v_members) (v_operations) (v_types) ((Base.list_append (v_function_nodes) (v_constant_nodes))))) (v_module) (v_choices) (v_diagnostic) (v_certified)))))))
and (* monomorph.bend:2715 *)
f_finalize_evidence_certified : M.t_Module -> G.t_Environment -> (t_Choice) Base.map -> (t_MemberEvidenceCertificate) list -> (M.t_Diagnostic, (t_Choice) Base.map) Base.result_ =
fun v_module v_environment v_choices v_certified ->
(f_finalize_with_scope ((f_finalize_definitions ((G.f_env_definitions (v_environment))) ((I.f_substitutions_of ((G.f_env_state (v_environment))))) (v_choices))) (v_module) (v_environment) (v_choices) (v_certified))
and (* monomorph.bend:2718 *)
f_finalize_evidence : M.t_Module -> G.t_Environment -> (t_Choice) Base.map -> (M.t_Diagnostic, (t_Choice) Base.map) Base.result_ =
fun v_module v_environment v_choices ->
(f_finalize_evidence_certified (v_module) (v_environment) (v_choices) ([]))
and (* monomorph.bend:2723 *)
f_reached_names : t_Specialization -> t_Configuration -> (M.t_Diagnostic, Base.set) Base.result_ =
fun v_specialized v_configuration ->
(let (Specialization ((M.Module (v_constants, v_functions, v_types, v_operations)), v_environment, v_choices, v_counter, v_certificates)) = v_specialized in
(let (Configuration (v_originals, v_templates, v_entry, v_locals, v_affected, v_stride, v_constant_values, v_family_templates, v_step, v_schema)) = v_configuration in
(let v_definitions = (G.f_env_definitions (v_environment)) in
(match (f_required_function_roots (v_functions) ((G.f_function_names ((G.f_function_declarations (v_originals))))) ((G.f_env_bindings (v_environment))) ((I.f_substitutions_of ((G.f_env_state (v_environment)))))) with
| Fail __error -> Fail __error
| Done v_function_roots ->
(match (f_required_constant_roots (v_constants) ((G.f_env_bindings (v_environment))) ((I.f_substitutions_of ((G.f_env_state (v_environment)))))) with
| Fail __error -> Fail __error
| Done v_constant_roots ->
(match (D.f_function_nodes (v_functions)) with
| Fail __error -> Fail __error
| Done v_fs ->
(match (D.f_constant_nodes (v_constants)) with
| Fail __error -> Fail __error
| Done v_cs ->
(let v_nodes = (Base.list_append (v_fs) (v_cs)) in
(let v_roots = (Base.list_append (v_function_roots) (v_constant_roots)) in
(let v_edges = (f_selected_edges (v_definitions) (v_choices) ((D.f_adjacency (v_nodes) (MTip)))) in
(let v_fuel = (Base.nat_add 1 (Base.nat_add ((Base.list_length (v_roots))) ((Base.nat_add ((D.f_edge_count (v_nodes))) ((Base.list_length ((f_pending (v_environment))))))))) in
(match (D.f_reachable (v_fuel) (v_roots) (v_edges) ((Base.set_from_list ((D.f_node_names (v_nodes))))) ((Base.set_new ())) ([])) with
| Fail __error -> Fail __error
| Done v_reached ->
(Done ((D.f_reached_seen (v_reached))))))))))))))))
and (* monomorph.bend:2741 *)
f_prune_generic_roots : t_Specialization -> t_Configuration -> (M.t_Diagnostic, t_Specialization) Base.result_ =
fun v_specialized v_configuration ->
(let (Specialization ((M.Module (v_constants, v_functions, v_types, v_operations)), v_environment, v_choices, v_counter, v_certificates)) = v_specialized in
(match (f_reached_names (v_specialized) (v_configuration)) with
| Fail __error -> Fail __error
| Done v_seen ->
(let v_definitions = (G.f_env_definitions (v_environment)) in
(let v_retained = (Specialization ((M.Module ((f_reached_constants (v_constants) (v_seen)), (f_reached_functions (v_functions) (v_seen)), v_types, v_operations)), (G.Environment ((G.f_env_bindings (v_environment)), (f_reached_definitions (v_definitions) (v_seen)), (G.f_env_state (v_environment)))), v_choices, v_counter, v_certificates)) in
(f_require_solved ((f_specialization_pending (v_retained))) (v_retained))))))
and (* monomorph.bend:2758 *)
f_boundary_coverage_values : t_BoundaryCoverage -> (I.t_Coverage) list =
fun v_value ->
(let (BoundaryCoverage (v_values, v_next, v_changed)) = v_value in
v_values)
and (* monomorph.bend:2762 *)
f_boundary_coverage_next : t_BoundaryCoverage -> int =
fun v_value ->
(let (BoundaryCoverage (v_values, v_next, v_changed)) = v_value in
v_next)
and (* monomorph.bend:2766 *)
f_boundary_coverage_changed : t_BoundaryCoverage -> bool =
fun v_value ->
(let (BoundaryCoverage (v_values, v_next, v_changed)) = v_value in
v_changed)
and (* monomorph.bend:2770 *)
f_boundary_definition_values : t_BoundaryDefinitions -> (I.t_Definition) list =
fun v_value ->
(let (BoundaryDefinitions (v_values, v_next, v_changed)) = v_value in
v_values)
and (* monomorph.bend:2774 *)
f_boundary_definition_next : t_BoundaryDefinitions -> int =
fun v_value ->
(let (BoundaryDefinitions (v_values, v_next, v_changed)) = v_value in
v_next)
and (* monomorph.bend:2778 *)
f_boundary_definition_changed : t_BoundaryDefinitions -> bool =
fun v_value ->
(let (BoundaryDefinitions (v_values, v_next, v_changed)) = v_value in
v_changed)
and (* monomorph.bend:2782 *)
f_boundary_needs : (M.t_Predicate) list -> int -> Base.text -> (I.t_Coverage) list =
fun v_predicates v_site v_subject ->
(match v_predicates with
| [] ->
[]
| (v_predicate :: v_tail) ->
((I.QualifiedNeed (v_site, v_predicate, v_subject)) :: (f_boundary_needs (v_tail) (v_site) (v_subject))))
and (* monomorph.bend:2789 *)
f_checked_boundary_site : bool -> int -> int -> Base.text -> (M.t_Diagnostic, int) Base.result_ =
fun v_allowed v_counter v_stride v_subject ->
(match v_allowed with
| true ->
(Done ((Base.nat_mul (v_counter) (v_stride))))
| false ->
(Fail ((M.Diagnostic (s_8, v_subject, s_117)))))
and (* monomorph.bend:2796 *)
f_boundary_site : int -> int -> int -> Base.text -> (M.t_Diagnostic, int) Base.result_ =
fun v_counter v_stride v_step v_subject ->
(f_checked_boundary_site ((Base.bool_and ((Base.nat_is_ge (v_counter) (1))) ((Base.bool_and ((Base.nat_is_ge (v_step) (1))) ((f_schema_space (v_counter) (v_stride) (v_step))))))) (v_counter) (v_stride) (v_subject))
and (* monomorph.bend:2799 *)
f_schedule_boundary_coverage : (I.t_Coverage) list -> int -> int -> int -> (M.t_Diagnostic, t_BoundaryCoverage) Base.result_ =
fun v_values v_counter v_stride v_step ->
(match v_values with
| [] ->
(Done ((BoundaryCoverage ([], v_counter, false))))
| ((I.QualifiedBoundary (v_offset, v_declared, v_subject)) :: v_tail) ->
(match (f_boundary_site (v_counter) (v_stride) (v_step) (v_subject)) with
| Fail __error -> Fail __error
| Done v_site ->
(let v_needs = (f_boundary_needs (v_declared) (v_site) (v_subject)) in
(match (f_schedule_boundary_coverage (v_tail) ((Base.nat_add (v_counter) (v_step))) (v_stride) (v_step)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done ((BoundaryCoverage ((Base.list_append (v_needs) ((f_boundary_coverage_values (v_rest)))), (f_boundary_coverage_next (v_rest)), true)))))))
| (v_head :: v_tail) ->
(match (f_schedule_boundary_coverage (v_tail) (v_counter) (v_stride) (v_step)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done ((BoundaryCoverage ((v_head :: (f_boundary_coverage_values (v_rest))), (f_boundary_coverage_next (v_rest)), (f_boundary_coverage_changed (v_rest))))))))
and (* monomorph.bend:2814 *)
f_schedule_if_reached : bool -> (I.t_Coverage) list -> int -> int -> int -> (M.t_Diagnostic, t_BoundaryCoverage) Base.result_ =
fun v_reached v_coverage v_counter v_stride v_step ->
(match v_reached with
| false ->
(Done ((BoundaryCoverage (v_coverage, v_counter, false))))
| true ->
(f_schedule_boundary_coverage (v_coverage) (v_counter) (v_stride) (v_step)))
and (* monomorph.bend:2821 *)
f_schedule_boundary_definitions : (I.t_Definition) list -> Base.set -> int -> int -> int -> (M.t_Diagnostic, t_BoundaryDefinitions) Base.result_ =
fun v_definitions v_reached v_counter v_stride v_step ->
(match v_definitions with
| [] ->
(Done ((BoundaryDefinitions ([], v_counter, false))))
| ((I.Definition (v_name, (I.Inference (v_ty, v_coverage, v_exits, v_reflections, v_predicates, v_uses)))) :: v_tail) ->
(match (f_schedule_if_reached ((D.f_member (v_reached) (v_name))) (v_coverage) (v_counter) (v_stride) (v_step)) with
| Fail __error -> Fail __error
| Done v_updated ->
(match (f_schedule_boundary_definitions (v_tail) (v_reached) ((f_boundary_coverage_next (v_updated))) (v_stride) (v_step)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done ((BoundaryDefinitions (((I.Definition (v_name, (I.Inference (v_ty, (f_boundary_coverage_values (v_updated)), v_exits, v_reflections, v_predicates, v_uses)))) :: (f_boundary_definition_values (v_rest))), (f_boundary_definition_next (v_rest)), (Base.bool_or ((f_boundary_coverage_changed (v_updated))) ((f_boundary_definition_changed (v_rest)))))))))))
and (* monomorph.bend:2831 *)
f_has_boundary : (I.t_Coverage) list -> bool =
fun v_coverage ->
(match v_coverage with
| [] ->
false
| ((I.QualifiedBoundary (v_offset, v_declared, v_subject)) :: v_tail) ->
true
| (v_head :: v_tail) ->
(f_has_boundary (v_tail)))
and (* monomorph.bend:2840 *)
f_has_boundary_definition : (I.t_Definition) list -> bool =
fun v_definitions ->
(match v_definitions with
| [] ->
false
| ((I.Definition (v_name, (I.Inference (v_ty, v_coverage, v_exits, v_reflections, v_predicates, v_uses)))) :: v_tail) ->
(Base.bool_or ((f_has_boundary (v_coverage))) ((f_has_boundary_definition (v_tail)))))
and (* monomorph.bend:2847 *)
f_solve_scheduled_boundaries : bool -> t_Specialization -> t_Configuration -> (I.t_Binding) list -> (Staging.t_Scheme) list -> (M.t_Diagnostic, t_BoundaryProgress) Base.result_ =
fun v_changed v_specialized v_configuration v_shapes v_schemes ->
(match v_changed with
| false ->
(Done ((BoundaryProgress (v_specialized, false))))
| true ->
(let (Specialization (v_module, v_environment, v_choices, v_counter, v_certificates)) = v_specialized in
(let v_initial = (f_specialization_pending (v_specialized)) in
(let v_count = (Base.list_length ((G.f_env_definitions (v_environment)))) in
(match (f_solve_staged (65536) ((Needs (v_initial))) (v_specialized) (v_configuration) (v_shapes) ((PendingCache (v_count, v_initial))) (v_schemes)) with
| Fail __error -> Fail __error
| Done v_solved ->
(Done ((BoundaryProgress (v_solved, true)))))))))
and (* monomorph.bend:2859 *)
f_schedule_present_boundaries_work : t_Specialization -> t_Configuration -> (I.t_Binding) list -> (Staging.t_Scheme) list -> (M.t_Diagnostic, t_BoundaryProgress) Base.result_ =
fun v_specialized v_configuration v_shapes v_schemes ->
(let (Specialization (v_module, v_environment, v_choices, v_counter, v_certificates)) = v_specialized in
(let (Configuration (v_originals, v_templates, v_entry, v_locals, v_affected, v_stride, v_constant_values, v_family_templates, v_step, v_schema)) = v_configuration in
(match (f_reached_names (v_specialized) (v_configuration)) with
| Fail __error -> Fail __error
| Done v_reached ->
(match (f_schedule_boundary_definitions ((G.f_env_definitions (v_environment))) (v_reached) (v_counter) (v_stride) (v_step)) with
| Fail __error -> Fail __error
| Done v_scheduled ->
(match (f_solve_scheduled_boundaries ((f_boundary_definition_changed (v_scheduled))) ((Specialization (v_module, (G.Environment ((G.f_env_bindings (v_environment)), (f_boundary_definition_values (v_scheduled)), (G.f_env_state (v_environment)))), v_choices, (f_boundary_definition_next (v_scheduled)), v_certificates))) (v_configuration) (v_shapes) (v_schemes)) with
| Fail __error -> Fail __error
| Done v_updated ->
(Done (v_updated)))))))
and (* monomorph.bend:2868 *)
f_schedule_if_present : bool -> t_Specialization -> t_Configuration -> (I.t_Binding) list -> (Staging.t_Scheme) list -> (M.t_Diagnostic, t_BoundaryProgress) Base.result_ =
fun v_present v_specialized v_configuration v_shapes v_schemes ->
(match v_present with
| false ->
(Done ((BoundaryProgress (v_specialized, false))))
| true ->
(f_schedule_present_boundaries_work (v_specialized) (v_configuration) (v_shapes) (v_schemes)))
and (* monomorph.bend:2875 *)
f_schedule_reached_boundaries : t_Specialization -> t_Configuration -> (I.t_Binding) list -> (Staging.t_Scheme) list -> (M.t_Diagnostic, t_BoundaryProgress) Base.result_ =
fun v_specialized v_configuration v_shapes v_schemes ->
(let (Specialization (v_module, v_environment, v_choices, v_counter, v_certificates)) = v_specialized in
(f_schedule_if_present ((f_has_boundary_definition ((G.f_env_definitions (v_environment))))) (v_specialized) (v_configuration) (v_shapes) (v_schemes)))
and (* monomorph.bend:2883 *)
f_schedule_boundaries : int -> t_BoundaryLoop -> t_Configuration -> (I.t_Binding) list -> (Staging.t_Scheme) list -> (M.t_Diagnostic, t_BoundaryProgress) Base.result_ =
fun v_fuel v_work v_configuration v_shapes v_schemes ->
(match (v_fuel, v_work) with
| (0, _) ->
(Fail ((M.Diagnostic (s_8, s_118, s_119))))
| (__nat_69, (CheckBoundaries (v_specialized, v_changed))) when __nat_69 >= 1 ->
(let v_rest = (__nat_69 - 1) in
(match (f_schedule_reached_boundaries (v_specialized) (v_configuration) (v_shapes) (v_schemes)) with
| Fail __error -> Fail __error
| Done v_progress ->
(f_schedule_boundaries (v_rest) ((ContinueBoundaries (v_progress, v_changed))) (v_configuration) (v_shapes) (v_schemes))))
| (__nat_70, (ContinueBoundaries ((BoundaryProgress (v_next, false)), v_changed))) when __nat_70 >= 1 ->
(let v_rest = (__nat_70 - 1) in
(Done ((BoundaryProgress (v_next, v_changed)))))
| (__nat_71, (ContinueBoundaries ((BoundaryProgress (v_next, true)), v_changed))) when __nat_71 >= 1 ->
(let v_rest = (__nat_71 - 1) in
(f_schedule_boundaries (v_rest) ((CheckBoundaries (v_next, true))) (v_configuration) (v_shapes) (v_schemes))))
and (* monomorph.bend:2900 *)
f_signature_rows_work : int -> (M.t_Ty) list -> (int) list -> (M.t_Diagnostic, (int) list) Base.result_ =
fun v_fuel v_pending v_found ->
(match (v_fuel, v_pending) with
| (0, _) ->
(Fail ((M.Diagnostic (s_120, s_121, s_122))))
| (__nat_72, []) when __nat_72 >= 1 ->
(let v_rest = (__nat_72 - 1) in
(Done (v_found)))
| (__nat_73, ((M.FunctionTy (v_parameter, v_result, v_effects)) :: v_tail)) when __nat_73 >= 1 ->
(let v_rest = (__nat_73 - 1) in
(f_signature_rows_work (v_rest) ((v_parameter :: (v_result :: v_tail))) ((T.f_union ((T.f_row_free (v_effects))) (v_found)))))
| (__nat_74, ((M.ProviderTy (v_identity, v_effects)) :: v_tail)) when __nat_74 >= 1 ->
(let v_rest = (__nat_74 - 1) in
(f_signature_rows_work (v_rest) (v_tail) ((T.f_union ((T.f_row_free (v_effects))) (v_found)))))
| (__nat_75, ((M.StateProviderTy (v_read, v_write, v_state)) :: v_tail)) when __nat_75 >= 1 ->
(let v_rest = (__nat_75 - 1) in
(f_signature_rows_work (v_rest) ((v_state :: v_tail)) (v_found)))
| (__nat_76, ((M.AppliedTy (v_identity, v_arguments)) :: v_tail)) when __nat_76 >= 1 ->
(let v_rest = (__nat_76 - 1) in
(f_signature_rows_work (v_rest) ((Base.list_append (v_arguments) (v_tail))) (v_found)))
| (__nat_77, ((M.ProductTy (v_elements)) :: v_tail)) when __nat_77 >= 1 ->
(let v_rest = (__nat_77 - 1) in
(f_signature_rows_work (v_rest) ((Base.list_append (v_elements) (v_tail))) (v_found)))
| (__nat_78, ((M.ArrayTy (v_element)) :: v_tail)) when __nat_78 >= 1 ->
(let v_rest = (__nat_78 - 1) in
(f_signature_rows_work (v_rest) ((v_element :: v_tail)) (v_found)))
| (__nat_79, (v_head :: v_tail)) when __nat_79 >= 1 ->
(let v_rest = (__nat_79 - 1) in
(f_signature_rows_work (v_rest) (v_tail) (v_found))))
and (* monomorph.bend:2921 *)
f_signature_rows : M.t_Ty -> (M.t_Diagnostic, (int) list) Base.result_ =
fun v_ty ->
(f_signature_rows_work (65536) ([v_ty]) ([]))
and (* monomorph.bend:2924 *)
f_selected_evidence_types : (C.t_EvidenceAnswer) list -> (M.t_Ty) list =
fun v_answers ->
(match v_answers with
| [] ->
[]
| ((C.EvidenceAnswer (v_predicate, (C.SelectedFunction (v_name, v_signature)))) :: v_tail) ->
(v_signature :: (f_selected_evidence_types (v_tail)))
| ((C.EvidenceAnswer (v_predicate, (C.SelectedField (v_owner, v_member, v_accessor, v_signature)))) :: v_tail) ->
(v_signature :: (f_selected_evidence_types (v_tail)))
| ((C.EvidenceAnswer (v_predicate, (C.SelectedOperation (v_identity, v_signature)))) :: v_tail) ->
(v_signature :: (f_selected_evidence_types (v_tail)))
| (v_head :: v_tail) ->
(f_selected_evidence_types (v_tail)))
and (* monomorph.bend:2937 *)
f_selected_choice_types : (t_Choice) option -> (M.t_Ty) list =
fun v_found ->
(match v_found with
| (Some ((FunctionChoice (v_name, v_signature)))) ->
[v_signature]
| (Some ((ReceiverChoice (v_name, v_signature)))) ->
[v_signature]
| (Some ((OperationChoice (v_identity, v_signature)))) ->
[v_signature]
| (Some ((QualifiedChoice (v_solved, v_answers)))) ->
(f_selected_evidence_types (v_answers))
| None ->
[])
and (* monomorph.bend:2950 *)
f_selected_need_types : (I.t_Coverage) list -> (t_Choice) Base.map -> (M.t_Ty) list =
fun v_needs v_choices ->
(match v_needs with
| [] ->
[]
| ((I.AssociatedNeed (v_identity, v_dispatch, v_member, v_templates, v_left, v_right, v_result, v_invocation, v_ambient, v_subject)) :: v_tail) ->
(Base.list_append ((f_selected_choice_types ((f_choice (v_choices) (v_identity))))) ((f_selected_need_types (v_tail) (v_choices))))
| ((I.QualifiedNeed (v_site, v_predicate, v_subject)) :: v_tail) ->
(Base.list_append ((f_selected_choice_types ((f_qualified_choice (v_choices) (v_site))))) ((f_selected_need_types (v_tail) (v_choices))))
| (v_head :: v_tail) ->
(f_selected_need_types (v_tail) (v_choices)))
and (* monomorph.bend:2961 *)
f_reached_selected_one : bool -> (I.t_Coverage) list -> (C.t_UsePlan) list -> (t_Choice) Base.map -> (M.t_Ty) list =
fun v_reached v_coverage v_uses v_choices ->
(match v_reached with
| false ->
[]
| true ->
(f_selected_need_types ((Base.list_append (v_coverage) ((I.f_execution_needs (v_uses))))) (v_choices)))
and (* monomorph.bend:2968 *)
f_reached_selected_types : (I.t_Definition) list -> Base.set -> (t_Choice) Base.map -> (M.t_Ty) list =
fun v_definitions v_reached v_choices ->
(match v_definitions with
| [] ->
[]
| ((I.Definition (v_name, (I.Inference (v_ty, v_coverage, v_exits, v_reflections, v_predicates, v_uses)))) :: v_tail) ->
(let v_rest = (f_reached_selected_types (v_tail) (v_reached) (v_choices)) in
(Base.list_append ((f_reached_selected_one ((D.f_member (v_reached) (v_name))) (v_coverage) (v_uses) (v_choices))) (v_rest))))
and (* monomorph.bend:2976 *)
f_resolved_signature_row_groups : (M.t_Ty) list -> T.t_Substitutions -> ((int) list) list -> (M.t_Diagnostic, ((int) list) list) Base.result_ =
fun v_types v_substitutions v_reversed ->
(match v_types with
| [] ->
(Done (v_reversed))
| (v_head :: v_tail) ->
(match (T.f_resolve (v_substitutions) (v_head)) with
| Fail __error -> Fail __error
| Done v_resolved ->
(match (f_signature_rows (v_resolved)) with
| Fail __error -> Fail __error
| Done v_first ->
(f_resolved_signature_row_groups (v_tail) (v_substitutions) ((v_first :: v_reversed))))))
and (* monomorph.bend:2986 *)
f_resolved_signature_row_union : ((int) list) list -> (int) list -> (int) list =
fun v_reversed v_accumulated ->
(match v_reversed with
| [] ->
v_accumulated
| (v_first :: v_tail) ->
(f_resolved_signature_row_union (v_tail) ((T.f_union (v_first) (v_accumulated)))))
and (* monomorph.bend:2993 *)
f_resolved_signature_rows : (M.t_Ty) list -> T.t_Substitutions -> (M.t_Diagnostic, (int) list) Base.result_ =
fun v_types v_substitutions ->
(match (f_resolved_signature_row_groups (v_types) (v_substitutions) ([])) with
| Fail __error -> Fail __error
| Done v_groups ->
(Done ((f_resolved_signature_row_union (v_groups) ([])))))
and (* monomorph.bend:2998 *)
f_reached_definition_names : (I.t_Definition) list -> Base.set -> (Base.text) list =
fun v_definitions v_reached ->
(match v_definitions with
| [] ->
[]
| ((I.Definition (v_name, v_inference)) :: v_tail) ->
(let v_rest = (f_reached_definition_names (v_tail) (v_reached)) in
(Base.bool_pick ((D.f_member (v_reached) (v_name))) ((v_name :: v_rest)) (v_rest))))
and (* monomorph.bend:3006 *)
f_scheme_quantifiers : (I.t_Binding) list -> (int) list =
fun v_bindings ->
(match v_bindings with
| [] ->
[]
| ((I.Binding (v_name, v_ty, v_variables, v_predicates)) :: v_tail) ->
(T.f_union (v_variables) ((f_scheme_quantifiers (v_tail)))))
and (* monomorph.bend:3013 *)
f_external_fixed_one : bool -> I.t_Binding -> T.t_Substitutions -> (M.t_Diagnostic, (int) list) Base.result_ =
fun v_owned v_binding v_substitutions ->
(match v_owned with
| true ->
(Done ([]))
| false ->
(I.f_binding_free ([v_binding]) (v_substitutions)))
and (* monomorph.bend:3020 *)
f_external_fixed_rows : (I.t_Binding) list -> (Base.text) list -> T.t_Substitutions -> (M.t_Diagnostic, (int) list) Base.result_ =
fun v_bindings v_owned v_substitutions ->
(match v_bindings with
| [] ->
(Done ([]))
| (v_binding :: v_tail) ->
(let (I.Binding (v_name, v_ty, v_variables, v_predicates)) = v_binding in
(match (f_external_fixed_one ((D.f_contains (v_owned) (v_name))) (v_binding) (v_substitutions)) with
| Fail __error -> Fail __error
| Done v_first ->
(match (f_external_fixed_rows (v_tail) (v_owned) (v_substitutions)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done ((T.f_union (v_first) (v_rest))))))))
and (* monomorph.bend:3031 *)
f_boundary_fixed_rows : (I.t_Coverage) list -> T.t_Substitutions -> (M.t_Diagnostic, (int) list) Base.result_ =
fun v_needs v_substitutions ->
(match v_needs with
| [] ->
(Done ([]))
| ((I.QualifiedNeed (v_site, v_predicate, v_subject)) :: v_tail) ->
(match (C.f_resolve (v_substitutions) (v_predicate)) with
| Fail __error -> Fail __error
| Done v_resolved ->
(match (C.f_free (v_resolved)) with
| Fail __error -> Fail __error
| Done v_first ->
(match (f_boundary_fixed_rows (v_tail) (v_substitutions)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done ((T.f_union (v_first) (v_rest)))))))
| ((I.QualifiedBoundary (v_offset, v_declared, v_subject)) :: v_tail) ->
(match (C.f_resolve_list (v_substitutions) (v_declared)) with
| Fail __error -> Fail __error
| Done v_resolved ->
(match (C.f_free_list (v_resolved)) with
| Fail __error -> Fail __error
| Done v_first ->
(match (f_boundary_fixed_rows (v_tail) (v_substitutions)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done ((T.f_union (v_first) (v_rest)))))))
| ((I.LetGeneralized (v_witness)) :: v_tail) ->
(match (T.f_resolve (v_substitutions) (v_witness)) with
| Fail __error -> Fail __error
| Done v_resolved ->
(match (T.f_free (v_resolved)) with
| Fail __error -> Fail __error
| Done v_first ->
(match (f_boundary_fixed_rows (v_tail) (v_substitutions)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done ((T.f_union (v_first) (v_rest)))))))
| (v_head :: v_tail) ->
(f_boundary_fixed_rows (v_tail) (v_substitutions)))
and (* monomorph.bend:3056 *)
f_visible_interface_type : M.t_Ty -> M.t_Ty =
fun v_ty ->
(match v_ty with
| (M.FunctionTy (v_parameter, v_result, v_effects)) ->
(M.ProductTy ([v_parameter; v_result]))
| v_other ->
v_other)
and (* monomorph.bend:3063 *)
f_reached_interface_one : bool -> M.t_Ty -> (I.t_Coverage) list -> T.t_Substitutions -> (M.t_Diagnostic, (int) list) Base.result_ =
fun v_reached v_ty v_coverage v_substitutions ->
(match v_reached with
| false ->
(Done ([]))
| true ->
(match (T.f_resolve (v_substitutions) (v_ty)) with
| Fail __error -> Fail __error
| Done v_resolved ->
(match (f_signature_rows ((f_visible_interface_type (v_resolved)))) with
| Fail __error -> Fail __error
| Done v_inputs ->
(match (f_boundary_fixed_rows (v_coverage) (v_substitutions)) with
| Fail __error -> Fail __error
| Done v_boundary ->
(Done ((T.f_union (v_inputs) (v_boundary))))))))
and (* monomorph.bend:3074 *)
f_reached_interface_rows : (I.t_Definition) list -> Base.set -> T.t_Substitutions -> (M.t_Diagnostic, (int) list) Base.result_ =
fun v_definitions v_reached v_substitutions ->
(match v_definitions with
| [] ->
(Done ([]))
| ((I.Definition (v_name, (I.Inference (v_ty, v_coverage, v_exits, v_reflections, v_predicates, v_uses)))) :: v_tail) ->
(match (f_reached_interface_one ((D.f_member (v_reached) (v_name))) (v_ty) (v_coverage) (v_substitutions)) with
| Fail __error -> Fail __error
| Done v_first ->
(match (f_reached_interface_rows (v_tail) (v_reached) (v_substitutions)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done ((T.f_union (v_first) (v_rest)))))))
and (* monomorph.bend:3084 *)
f_close_selected_one : bool -> int -> I.t_State -> (M.t_Diagnostic, I.t_State) Base.result_ =
fun v_protected v_index v_state ->
(match v_protected with
| true ->
(Done (v_state))
| false ->
(I.f_unify_rows ((Rows.f_variable_row (v_index))) ((M.f_empty_row ())) (v_state) (s_123)))
and (* monomorph.bend:3091 *)
f_close_selected_rows : (int) list -> (int) list -> I.t_State -> (M.t_Diagnostic, I.t_State) Base.result_ =
fun v_candidates v_fixed v_state ->
(match v_candidates with
| [] ->
(Done (v_state))
| (v_index :: v_tail) ->
(match (f_close_selected_one ((T.f_contains (v_fixed) (v_index))) (v_index) (v_state)) with
| Fail __error -> Fail __error
| Done v_next ->
(f_close_selected_rows (v_tail) (v_fixed) (v_next))))
and (* monomorph.bend:3100 *)
f_relink_qualified_evidence : M.t_Predicate -> C.t_Evidence -> I.t_State -> Base.text -> (M.t_Diagnostic, I.t_State) Base.result_ =
fun v_predicate v_evidence v_state v_subject ->
(match (v_predicate, v_evidence) with
| ((M.AssociatedPredicate (v_member, v_templates, v_left, v_right, v_result, v_invocation)), (C.SelectedFunction (v_name, v_signature))) ->
(match (T.f_resolve ((I.f_substitutions_of (v_state))) (v_signature)) with
| Fail __error -> Fail __error
| Done v_ty ->
(match (f_selected_binary_invocation (v_ty)) with
| Fail __error -> Fail __error
| Done v_row ->
(f_unify_selected_invocation (v_row) (v_invocation) (v_state) (v_subject))))
| ((M.UpdatePredicate (v_member, v_receiver, v_assigned, v_result, v_invocation)), (C.SelectedField (v_owner, v_field, v_accessor, v_signature))) ->
(match (T.f_resolve ((I.f_substitutions_of (v_state))) (v_signature)) with
| Fail __error -> Fail __error
| Done v_ty ->
(match (f_selected_binary_invocation (v_ty)) with
| Fail __error -> Fail __error
| Done v_row ->
(f_unify_selected_invocation (v_row) (v_invocation) (v_state) (v_subject))))
| ((M.ReceiverPredicate (v_member, v_templates, v_receiver, v_argument, v_result, v_invocation)), (C.SelectedFunction (v_name, v_signature))) ->
(match (T.f_resolve ((I.f_substitutions_of (v_state))) (v_signature)) with
| Fail __error -> Fail __error
| Done v_ty ->
(match (f_selected_receiver_invocation (v_ty)) with
| Fail __error -> Fail __error
| Done v_row ->
(f_unify_selected_invocation (v_row) (v_invocation) (v_state) (v_subject))))
| ((M.ReceiverPredicate (v_member, v_templates, v_receiver, v_argument, v_result, v_invocation)), (C.SelectedField (v_owner, v_field, v_accessor, v_signature))) ->
(match (T.f_resolve ((I.f_substitutions_of (v_state))) (v_signature)) with
| Fail __error -> Fail __error
| Done v_ty ->
(match (f_selected_receiver_invocation (v_ty)) with
| Fail __error -> Fail __error
| Done v_row ->
(f_unify_selected_invocation (v_row) (v_invocation) (v_state) (v_subject))))
| (_, _) ->
(Done (v_state)))
and (* monomorph.bend:3125 *)
f_relink_qualified_answers : (C.t_EvidenceAnswer) list -> I.t_State -> Base.text -> (M.t_Diagnostic, I.t_State) Base.result_ =
fun v_answers v_state v_subject ->
(match v_answers with
| [] ->
(Done (v_state))
| ((C.EvidenceAnswer (v_predicate, v_evidence)) :: v_tail) ->
(match (f_relink_qualified_evidence (v_predicate) (v_evidence) (v_state) (v_subject)) with
| Fail __error -> Fail __error
| Done v_next ->
(f_relink_qualified_answers (v_tail) (v_next) (v_subject))))
and (* monomorph.bend:3134 *)
f_relink_selected_needs : (I.t_Coverage) list -> (t_Choice) Base.map -> I.t_State -> (M.t_Diagnostic, I.t_State) Base.result_ =
fun v_needs v_choices v_state ->
(match v_needs with
| [] ->
(Done (v_state))
| ((I.AssociatedNeed (v_identity, v_dispatch, v_member, v_templates, v_left, v_right, v_result, (Some (v_invocation)), v_ambient, v_subject)) :: v_tail) ->
(match (f_resolved_selected_invocation ((f_choice (v_choices) (v_identity))) ((I.f_substitutions_of (v_state))) ((f_associated_binary (v_dispatch)))) with
| Fail __error -> Fail __error
| Done v_row ->
(match (f_unify_selected_invocation (v_row) (v_invocation) (v_state) (v_subject)) with
| Fail __error -> Fail __error
| Done v_next ->
(f_relink_selected_needs (v_tail) (v_choices) (v_next))))
| ((I.QualifiedNeed (v_site, v_predicate, v_subject)) :: v_tail) ->
(match (f_relink_qualified_answers ((f_qualified_answers ((f_qualified_choice (v_choices) (v_site))))) (v_state) (v_subject)) with
| Fail __error -> Fail __error
| Done v_next ->
(f_relink_selected_needs (v_tail) (v_choices) (v_next)))
| (v_head :: v_tail) ->
(f_relink_selected_needs (v_tail) (v_choices) (v_state)))
and (* monomorph.bend:3150 *)
f_relink_if_reached : bool -> (I.t_Coverage) list -> (t_Choice) Base.map -> I.t_State -> (M.t_Diagnostic, I.t_State) Base.result_ =
fun v_reached v_needs v_choices v_state ->
(match v_reached with
| false ->
(Done (v_state))
| true ->
(f_relink_selected_needs (v_needs) (v_choices) (v_state)))
and (* monomorph.bend:3157 *)
f_relink_reached_definitions : (I.t_Definition) list -> Base.set -> (t_Choice) Base.map -> I.t_State -> (M.t_Diagnostic, I.t_State) Base.result_ =
fun v_definitions v_reached v_choices v_state ->
(match v_definitions with
| [] ->
(Done (v_state))
| ((I.Definition (v_name, (I.Inference (v_ty, v_coverage, v_exits, v_reflections, v_predicates, v_uses)))) :: v_tail) ->
(match (f_relink_if_reached ((D.f_member (v_reached) (v_name))) ((Base.list_append (v_coverage) ((I.f_execution_needs (v_uses))))) (v_choices) (v_state)) with
| Fail __error -> Fail __error
| Done v_next ->
(f_relink_reached_definitions (v_tail) (v_reached) (v_choices) (v_next))))
and (* monomorph.bend:3170 *)
f_recheckable_member_ground : (M.t_Diagnostic, (int) list) Base.result_ -> int -> int -> int -> bool =
fun v_found v_inner v_outer v_index ->
(match v_found with
| (Done (v_free)) ->
(Base.bool_and ((Base.bool_not ((T.f_contains (v_free) (v_index))))) ((Base.bool_and ((Base.nat_is_eq (v_inner) (v_index))) ((Base.nat_is_eq (v_outer) (v_index))))))
| _ ->
false)
and (* monomorph.bend:3177 *)
f_recheckable_member_signature : M.t_Ty -> int -> bool =
fun v_ty v_index ->
(match v_ty with
| (M.FunctionTy (v_parameter, (M.FunctionTy (v_argument, v_result, (M.EffectRow ([], (M.RowVariable (v_inner)))))), (M.EffectRow ([], (M.RowVariable (v_outer)))))) ->
(f_recheckable_member_ground ((T.f_free ((M.ProductTy ([v_parameter; v_argument; v_result]))))) (v_inner) (v_outer) (v_index))
| _ ->
false)
and (* monomorph.bend:3186 *)
f_member_target_definition_work : (I.t_Definition) list -> bool -> (M.t_Ty) option -> Base.text -> (M.t_Ty) option =
fun v_definitions v_matched v_found v_name ->
(match (v_definitions, v_matched) with
| (_, true) ->
v_found
| ([], false) ->
None
| (((I.Definition (v_candidate, (I.Inference (v_ty, v_coverage, v_exits, v_reflections, v_predicates, v_uses)))) :: v_tail), false) ->
(f_member_target_definition_work (v_tail) ((M.f_name_equal (v_candidate) (v_name))) ((Some (v_ty))) (v_name)))
and (* monomorph.bend:3195 *)
f_member_target_definition : (I.t_Definition) list -> Base.text -> (M.t_Ty) option =
fun v_definitions v_name ->
(f_member_target_definition_work (v_definitions) (false) (None) (v_name))
and (* monomorph.bend:3198 *)
f_member_target_free : (M.t_Diagnostic, (int) list) Base.result_ -> int -> bool =
fun v_found v_index ->
(match v_found with
| (Done (v_free)) ->
(T.f_contains (v_free) (v_index))
| (Fail (v_diagnostic)) ->
false)
and (* monomorph.bend:3205 *)
f_member_target_resolved : (M.t_Diagnostic, M.t_Ty) Base.result_ -> int -> bool =
fun v_found v_index ->
(match v_found with
| (Done (v_resolved)) ->
(f_member_target_free ((T.f_free (v_resolved))) (v_index))
| (Fail (v_diagnostic)) ->
false)
and (* monomorph.bend:3212 *)
f_member_target_found : (M.t_Ty) option -> T.t_Substitutions -> int -> bool =
fun v_found v_substitutions v_index ->
(match v_found with
| (Some (v_ty)) ->
(f_member_target_resolved ((T.f_resolve (v_substitutions) (v_ty))) (v_index))
| None ->
false)
and (* monomorph.bend:3219 *)
f_member_target_affected : (I.t_Definition) list -> Base.text -> int -> T.t_Substitutions -> bool =
fun v_definitions v_name v_index v_substitutions ->
(f_member_target_found ((f_member_target_definition (v_definitions) (v_name))) (v_substitutions) (v_index))
and (* monomorph.bend:3222 *)
f_binding_row_free : (M.t_Diagnostic, (int) list) Base.result_ -> Base.text -> int -> (I.t_Definition) list -> T.t_Substitutions -> bool =
fun v_found v_name v_index v_definitions v_substitutions ->
(match v_found with
| (Fail (v_diagnostic)) ->
false
| (Done (v_free)) ->
(Base.bool_or ((Base.bool_not ((T.f_contains (v_free) (v_index))))) ((f_member_target_affected (v_definitions) (v_name) (v_index) (v_substitutions)))))
and (* monomorph.bend:3229 *)
f_binding_row_accounted : (M.t_Diagnostic, M.t_Ty) Base.result_ -> Base.text -> int -> (I.t_Definition) list -> T.t_Substitutions -> bool =
fun v_found v_name v_index v_definitions v_substitutions ->
(match v_found with
| (Fail (v_diagnostic)) ->
false
| (Done (v_ty)) ->
(f_binding_row_free ((T.f_free (v_ty))) (v_name) (v_index) (v_definitions) (v_substitutions)))
and (* monomorph.bend:3236 *)
f_member_binding_accounted : bool -> M.t_Ty -> Base.text -> int -> (I.t_Definition) list -> T.t_Substitutions -> bool -> bool =
fun v_owned v_ty v_name v_index v_definitions v_substitutions v_rest ->
(match v_owned with
| false ->
v_rest
| true ->
(Base.bool_and ((f_binding_row_accounted ((T.f_resolve (v_substitutions) (v_ty))) (v_name) (v_index) (v_definitions) (v_substitutions))) (v_rest)))
and (* monomorph.bend:3243 *)
f_all_member_bindings_accounted : (I.t_Binding) list -> (Base.text) list -> int -> (I.t_Definition) list -> T.t_Substitutions -> bool =
fun v_bindings v_owned v_index v_definitions v_substitutions ->
(match v_bindings with
| [] ->
true
| ((I.Binding (v_name, v_ty, v_variables, v_predicates)) :: v_tail) ->
(let v_rest = (f_all_member_bindings_accounted (v_tail) (v_owned) (v_index) (v_definitions) (v_substitutions)) in
(f_member_binding_accounted ((D.f_contains (v_owned) (v_name))) (v_ty) (v_name) (v_index) (v_definitions) (v_substitutions) (v_rest))))
and (* monomorph.bend:3251 *)
f_resolved_recheckable_member : (M.t_Diagnostic, M.t_Ty) Base.result_ -> Base.text -> int -> (Base.text) list -> (I.t_Definition) list -> T.t_Substitutions -> bool =
fun v_found v_name v_index v_owned v_definitions v_substitutions ->
(match v_found with
| (Done (v_ty)) ->
(Base.bool_and ((Base.bool_and ((D.f_contains (v_owned) (v_name))) ((f_member_target_affected (v_definitions) (v_name) (v_index) (v_substitutions))))) ((f_recheckable_member_signature (v_ty) (v_index))))
| (Fail (v_diagnostic)) ->
false)
and (* monomorph.bend:3258 *)
f_recheckable_member_answers_work : (C.t_EvidenceAnswer) list -> bool -> T.t_Substitutions -> int -> (Base.text) list -> (I.t_Definition) list -> bool =
fun v_answers v_matched v_substitutions v_index v_owned v_definitions ->
(match (v_answers, v_matched) with
| (_, true) ->
true
| ([], false) ->
false
| (((C.EvidenceAnswer ((M.ReceiverPredicate (v_member, v_templates, v_receiver, v_argument, v_result, v_invocation)), (C.SelectedFunction (v_name, v_signature)))) :: v_tail), false) ->
(let v_matching = (f_resolved_recheckable_member ((T.f_resolve (v_substitutions) (v_signature))) (v_name) (v_index) (v_owned) (v_definitions) (v_substitutions)) in
(f_recheckable_member_answers_work (v_tail) (v_matching) (v_substitutions) (v_index) (v_owned) (v_definitions)))
| ((v_head :: v_tail), false) ->
(f_recheckable_member_answers_work (v_tail) (false) (v_substitutions) (v_index) (v_owned) (v_definitions)))
and (* monomorph.bend:3270 *)
f_recheckable_member_answers : (C.t_EvidenceAnswer) list -> T.t_Substitutions -> int -> (Base.text) list -> (I.t_Definition) list -> bool =
fun v_answers v_substitutions v_index v_owned v_definitions ->
(f_recheckable_member_answers_work (v_answers) (false) (v_substitutions) (v_index) (v_owned) (v_definitions))
and (* monomorph.bend:3273 *)
f_recheckable_member_choices : (t_Choice) list -> T.t_Substitutions -> int -> (Base.text) list -> (I.t_Definition) list -> bool =
fun v_pending v_substitutions v_index v_owned v_definitions ->
(match v_pending with
| [] ->
false
| ((QualifiedChoice (v_solved, v_answers)) :: v_tail) ->
(Base.bool_or ((f_recheckable_member_answers (v_answers) (v_substitutions) (v_index) (v_owned) (v_definitions))) ((f_recheckable_member_choices (v_tail) (v_substitutions) (v_index) (v_owned) (v_definitions))))
| ((FunctionChoice (v_name, v_signature)) :: v_tail) ->
(let v_matching = (f_resolved_recheckable_member ((T.f_resolve (v_substitutions) (v_signature))) (v_name) (v_index) (v_owned) (v_definitions) (v_substitutions)) in
(Base.bool_or (v_matching) ((f_recheckable_member_choices (v_tail) (v_substitutions) (v_index) (v_owned) (v_definitions)))))
| (v_head :: v_tail) ->
(f_recheckable_member_choices (v_tail) (v_substitutions) (v_index) (v_owned) (v_definitions)))
and (* monomorph.bend:3285 *)
f_reached_input_one : bool -> M.t_Ty -> (I.t_Coverage) list -> T.t_Substitutions -> (M.t_Diagnostic, (int) list) Base.result_ =
fun v_reached v_ty v_coverage v_substitutions ->
(match v_reached with
| false ->
(Done ([]))
| true ->
(match (T.f_resolve (v_substitutions) (v_ty)) with
| Fail __error -> Fail __error
| Done v_resolved ->
(match (T.f_covariant_inputs (65536) ((T.OneType (v_resolved)))) with
| Fail __error -> Fail __error
| Done v_inputs ->
(match (f_boundary_fixed_rows (v_coverage) (v_substitutions)) with
| Fail __error -> Fail __error
| Done v_boundary ->
(Done ((T.f_union (v_inputs) (v_boundary))))))))
and (* monomorph.bend:3296 *)
f_reached_input_rows : (I.t_Definition) list -> Base.set -> T.t_Substitutions -> (M.t_Diagnostic, (int) list) Base.result_ =
fun v_definitions v_reached v_substitutions ->
(match v_definitions with
| [] ->
(Done ([]))
| ((I.Definition (v_name, (I.Inference (v_ty, v_coverage, v_exits, v_reflections, v_predicates, v_uses)))) :: v_tail) ->
(match (f_reached_input_one ((D.f_member (v_reached) (v_name))) (v_ty) (v_coverage) (v_substitutions)) with
| Fail __error -> Fail __error
| Done v_first ->
(match (f_reached_input_rows (v_tail) (v_reached) (v_substitutions)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done ((T.f_union (v_first) (v_rest)))))))
and (* monomorph.bend:3306 *)
f_rechecked_member_binding : (I.t_Binding) option -> (I.t_Binding) option -> M.t_Ty -> T.t_Substitutions -> I.t_State -> Base.text -> (M.t_Diagnostic, I.t_State) Base.result_ =
fun v_original v_fresh v_expected v_after v_state v_subject ->
(match (v_original, v_fresh) with
| ((Some ((I.Binding (v_name, v_ty, [], [])))), (Some ((I.Binding (v_fresh_name, v_inferred, v_variables, v_predicates))))) ->
(match (T.f_resolve (v_after) (v_ty)) with
| Fail __error -> Fail __error
| Done v_signature ->
(match (I.f_unify (v_inferred) (v_signature) (v_state) (v_subject)) with
| Fail __error -> Fail __error
| Done v_checked ->
(I.f_unify (v_inferred) (v_expected) (v_checked) (v_subject))))
| (_, _) ->
(Fail ((M.Diagnostic (s_32, v_subject, s_124)))))
and (* monomorph.bend:3316 *)
f_recheck_affected_one : bool -> M.t_Ty -> Base.text -> (I.t_Binding) list -> T.t_Substitutions -> (I.t_Binding) list -> I.t_State -> (M.t_Diagnostic, I.t_State) Base.result_ =
fun v_affected v_ty v_name v_original v_after v_fresh v_state ->
(match v_affected with
| false ->
(Done (v_state))
| true ->
(match (T.f_resolve (v_after) (v_ty)) with
| Fail __error -> Fail __error
| Done v_expected ->
(f_rechecked_member_binding ((I.f_lookup_binding (v_original) (v_name))) ((I.f_lookup_binding (v_fresh) (v_name))) (v_expected) (v_after) (v_state) (v_name))))
and (* monomorph.bend:3328 *)
f_recheck_affected_member : (I.t_Definition) list -> (Base.text) list -> int -> (I.t_Binding) list -> T.t_Substitutions -> T.t_Substitutions -> (I.t_Binding) list -> I.t_State -> bool -> (M.t_Diagnostic, I.t_State) Base.result_ =
fun v_definitions v_owned v_index v_original v_before v_after v_fresh v_state v_seen ->
(match v_definitions with
| [] ->
(match v_seen with
| true ->
(Done (v_state))
| false ->
(Fail ((M.Diagnostic (s_32, s_125, s_126)))))
| ((I.Definition (v_name, (I.Inference (v_ty, v_coverage, v_exits, v_reflections, v_predicates, v_uses)))) :: v_tail) ->
(match (T.f_resolve (v_before) (v_ty)) with
| Fail __error -> Fail __error
| Done v_resolved ->
(match (T.f_free (v_resolved)) with
| Fail __error -> Fail __error
| Done v_free ->
(let v_affected = (Base.bool_and ((D.f_contains (v_owned) (v_name))) ((T.f_contains (v_free) (v_index)))) in
(match (f_recheck_affected_one (v_affected) (v_ty) (v_name) (v_original) (v_after) (v_fresh) (v_state)) with
| Fail __error -> Fail __error
| Done v_next ->
(f_recheck_affected_member (v_tail) (v_owned) (v_index) (v_original) (v_before) (v_after) (v_fresh) (v_next) ((Base.bool_or (v_seen) (v_affected)))))))))
and (* monomorph.bend:3344 *)
f_member_definition_count_work : (I.t_Definition) list -> Base.text -> int -> int =
fun v_definitions v_wanted v_count ->
(match v_definitions with
| [] ->
v_count
| ((I.Definition (v_name, v_inference)) :: v_tail) ->
(f_member_definition_count_work (v_tail) (v_wanted) ((Base.nat_add ((Base.bool_pick ((M.f_name_equal (v_name) (v_wanted))) (1) (0))) (v_count)))))
and (* monomorph.bend:3351 *)
f_member_definition_count : (I.t_Definition) list -> Base.text -> int =
fun v_definitions v_wanted ->
(f_member_definition_count_work (v_definitions) (v_wanted) (0))
and (* monomorph.bend:3354 *)
f_member_preserved : (M.t_Diagnostic, M.t_Ty) Base.result_ -> M.t_Ty -> Base.text -> (M.t_Diagnostic, unit) Base.result_ =
fun v_found v_snapshot v_subject ->
(match v_found with
| (Fail (v_diagnostic)) ->
(Fail (v_diagnostic))
| (Done (v_resolved)) ->
(Base.bool_pick ((Compare.f_same_ty (v_snapshot) (v_resolved))) ((Done (()))) ((Fail ((M.Diagnostic (s_32, v_subject, s_127)))))))
and (* monomorph.bend:3361 *)
f_checked_member_certificate : (I.t_Binding) option -> Base.text -> M.t_Ty -> T.t_Substitutions -> T.t_Substitutions -> (M.t_Diagnostic, t_MemberEvidenceCertificate) Base.result_ =
fun v_found v_name v_definition v_after v_narrowed ->
(match v_found with
| (Some ((I.Binding (v_found_name, v_binding, [], [])))) ->
(match (T.f_resolve (v_after) (v_binding)) with
| Fail __error -> Fail __error
| Done v_signature ->
(match (T.f_resolve (v_after) (v_definition)) with
| Fail __error -> Fail __error
| Done v_expected ->
(match (f_member_preserved ((T.f_resolve (v_narrowed) (v_signature))) (v_signature) (v_name)) with
| Fail __error -> Fail __error
| Done v_binding_preserved ->
(match (f_member_preserved ((T.f_resolve (v_narrowed) (v_expected))) (v_expected) (v_name)) with
| Fail __error -> Fail __error
| Done v_definition_preserved ->
(let v_exact = (Base.bool_and ((M.f_name_equal (v_found_name) (v_name))) ((Compare.f_same_ty (v_signature) (v_expected)))) in
(match (Base.bool_pick (v_exact) ((Done (()))) ((Fail ((M.Diagnostic (s_32, v_name, s_128)))))) with
| Fail __error -> Fail __error
| Done v_valid ->
(Done ((MemberEvidenceCertificate (v_name, v_signature))))))))))
| _ ->
(Fail ((M.Diagnostic (s_32, v_name, s_129)))))
and (* monomorph.bend:3375 *)
f_member_affected_free : (M.t_Diagnostic, (int) list) Base.result_ -> bool -> int -> bool =
fun v_found v_owned v_index ->
(match v_found with
| (Done (v_free)) ->
(Base.bool_and (v_owned) ((T.f_contains (v_free) (v_index))))
| (Fail (v_diagnostic)) ->
false)
and (* monomorph.bend:3382 *)
f_member_affected_type : (M.t_Diagnostic, M.t_Ty) Base.result_ -> bool -> int -> bool =
fun v_found v_owned v_index ->
(match v_found with
| (Done (v_resolved)) ->
(f_member_affected_free ((T.f_free (v_resolved))) (v_owned) (v_index))
| (Fail (v_diagnostic)) ->
false)
and (* monomorph.bend:3389 *)
f_maybe_member_certificate : bool -> Base.text -> M.t_Ty -> (I.t_Definition) list -> (I.t_Binding) list -> T.t_Substitutions -> T.t_Substitutions -> (t_MemberEvidenceCertificate) list -> (M.t_Diagnostic, (t_MemberEvidenceCertificate) list) Base.result_ =
fun v_affected v_name v_ty v_definitions v_original v_after v_narrowed v_rest ->
(match v_affected with
| false ->
(Done (v_rest))
| true ->
(match (Base.bool_pick ((Base.bool_and ((Base.nat_is_eq ((f_member_definition_count (v_definitions) (v_name))) (1))) ((Base.nat_is_eq ((f_scoped_binding_count (v_original) (v_name))) (1))))) ((Done (()))) ((Fail ((M.Diagnostic (s_32, v_name, s_130)))))) with
| Fail __error -> Fail __error
| Done v_unique ->
(match (f_checked_member_certificate ((I.f_lookup_binding (v_original) (v_name))) (v_name) (v_ty) (v_after) (v_narrowed)) with
| Fail __error -> Fail __error
| Done v_first ->
(Done ((v_first :: v_rest))))))
and (* monomorph.bend:3399 *)
f_member_certificates_work : (I.t_Definition) list -> (I.t_Definition) list -> (Base.text) list -> int -> (I.t_Binding) list -> T.t_Substitutions -> T.t_Substitutions -> T.t_Substitutions -> (M.t_Diagnostic, (t_MemberEvidenceCertificate) list) Base.result_ =
fun v_pending v_all v_owned v_index v_original v_before v_after v_narrowed ->
(match v_pending with
| [] ->
(Done ([]))
| ((I.Definition (v_name, (I.Inference (v_ty, v_coverage, v_exits, v_reflections, v_predicates, v_uses)))) :: v_tail) ->
(match (f_member_certificates_work (v_tail) (v_all) (v_owned) (v_index) (v_original) (v_before) (v_after) (v_narrowed)) with
| Fail __error -> Fail __error
| Done v_rest ->
(let v_affected = (f_member_affected_type ((T.f_resolve (v_before) (v_ty))) ((D.f_contains (v_owned) (v_name))) (v_index)) in
(f_maybe_member_certificate (v_affected) (v_name) (v_ty) (v_all) (v_original) (v_after) (v_narrowed) (v_rest)))))
and (* monomorph.bend:3411 *)
f_member_trial_declarations : M.t_Module -> (G.t_Declaration) list =
fun v_prepared ->
(match v_prepared with
| (M.Module (v_constants, v_functions, v_types, v_operations)) ->
(Base.list_append ((G.f_function_declarations (v_functions))) ((G.f_constant_declarations (v_constants)))))
and (* monomorph.bend:3416 *)
f_member_trial_types : M.t_Module -> (M.t_DataType) list =
fun v_prepared ->
(match v_prepared with
| (M.Module (v_constants, v_functions, v_types, v_operations)) ->
v_types)
and (* monomorph.bend:3425 *)
f_prove_member_row : int -> M.t_Module -> G.t_Environment -> (t_Choice) Base.map -> int -> (Core.t_Certificate) list -> (Base.text) list -> (M.t_Diagnostic, t_MemberRowProof) Base.result_ =
fun v_index v_module v_environment v_choices v_counter v_certificates v_external_functions ->
(let (M.Module (v_constants, v_functions, v_types, v_operations)) = v_module in
(let v_owned = (G.f_names ((Base.list_append ((G.f_function_declarations (v_functions))) ((G.f_constant_declarations (v_constants)))))) in
(let v_before = (I.f_substitutions_of ((G.f_env_state (v_environment)))) in
(let v_outside = (f_without_interface_bindings ((G.f_env_bindings (v_environment))) (v_owned)) in
(let v_imported = (G.Environment (v_outside, [], (G.f_env_state (v_environment)))) in
(match (Base.bool_pick ((f_all_member_bindings_accounted ((G.f_env_bindings (v_environment))) (v_owned) (v_index) ((G.f_env_definitions (v_environment))) (v_before))) ((Done (()))) ((Fail ((M.Diagnostic (s_32, s_125, s_131)))))) with
| Fail __error -> Fail __error
| Done v_accounted ->
(match (I.f_unify_rows ((Rows.f_variable_row (v_index))) ((M.f_empty_row ())) ((G.f_env_state (v_environment))) (s_125)) with
| Fail __error -> Fail __error
| Done v_trial ->
(match (f_finish ((Specialization (v_module, v_environment, v_choices, v_counter, v_certificates)))) with
| Fail __error -> Fail __error
| Done v_prepared ->
(let v_declarations = (f_member_trial_declarations (v_prepared)) in
(match (Check.f_module_graph (v_prepared)) with
| Fail __error -> Fail __error
| Done v_graph ->
(match (G.f_infer_with (v_declarations) (v_graph) ((M.f_module_operations (v_prepared))) ((f_member_trial_types (v_prepared))) (v_imported) (v_external_functions)) with
| Fail __error -> Fail __error
| Done v_fresh ->
(match (f_recheck_affected_member ((G.f_env_definitions (v_environment))) (v_owned) (v_index) ((G.f_env_bindings (v_environment))) (v_before) ((I.f_substitutions_of (v_trial))) ((G.f_env_bindings (v_fresh))) ((G.f_env_state (v_fresh))) (false)) with
| Fail __error -> Fail __error
| Done v_narrowed ->
(match (Check.f_finish (v_prepared) ((G.Environment ((G.f_env_bindings (v_fresh)), (G.f_env_definitions (v_fresh)), v_narrowed)))) with
| Fail __error -> Fail __error
| Done v_checked ->
(match (f_member_certificates_work ((G.f_env_definitions (v_environment))) ((G.f_env_definitions (v_environment))) (v_owned) (v_index) ((G.f_env_bindings (v_environment))) (v_before) ((I.f_substitutions_of (v_trial))) ((I.f_substitutions_of (v_narrowed)))) with
| Fail __error -> Fail __error
| Done v_certified ->
(Done ((MemberRowProof (v_trial, v_certified))))))))))))))))))
and (* monomorph.bend:3443 *)
f_first_recheckable_member_work : (int) list -> bool -> (int) option -> (int) list -> (int) list -> (Base.text) list -> (t_Choice) list -> T.t_Substitutions -> (I.t_Definition) list -> (int) option =
fun v_candidates v_matched v_found v_fixed v_hard_fixed v_owned v_pending v_substitutions v_definitions ->
(match (v_candidates, v_matched) with
| (_, true) ->
v_found
| ([], false) ->
None
| ((v_index :: v_tail), false) ->
(let v_eligible = (Base.bool_and ((Base.bool_and ((T.f_contains (v_fixed) (v_index))) ((Base.bool_not ((T.f_contains (v_hard_fixed) (v_index))))))) ((f_recheckable_member_choices (v_pending) (v_substitutions) (v_index) (v_owned) (v_definitions)))) in
(f_first_recheckable_member_work (v_tail) (v_eligible) ((Some (v_index))) (v_fixed) (v_hard_fixed) (v_owned) (v_pending) (v_substitutions) (v_definitions))))
and (* monomorph.bend:3453 *)
f_first_recheckable_member : (int) list -> (int) list -> (int) list -> (Base.text) list -> (t_Choice) list -> T.t_Substitutions -> (I.t_Definition) list -> (int) option =
fun v_candidates v_fixed v_hard_fixed v_owned v_pending v_substitutions v_definitions ->
(f_first_recheckable_member_work (v_candidates) (false) (None) (v_fixed) (v_hard_fixed) (v_owned) (v_pending) (v_substitutions) (v_definitions))
and (* monomorph.bend:3456 *)
f_member_row_trial : (M.t_Diagnostic, t_MemberRowProof) Base.result_ -> I.t_State -> t_MemberRowProof =
fun v_found v_fallback ->
(match v_found with
| (Done (v_proven)) ->
v_proven
| (Fail (v_diagnostic)) ->
(MemberRowProof (v_fallback, [])))
and (* monomorph.bend:3463 *)
f_member_row_selected : (int) option -> M.t_Module -> G.t_Environment -> (t_Choice) Base.map -> int -> (Core.t_Certificate) list -> (Base.text) list -> I.t_State -> t_MemberRowProof =
fun v_found v_module v_environment v_choices v_counter v_certificates v_external_functions v_state ->
(match v_found with
| None ->
(MemberRowProof (v_state, []))
| (Some (v_index)) ->
(f_member_row_trial ((f_prove_member_row (v_index) (v_module) ((G.Environment ((G.f_env_bindings (v_environment)), (G.f_env_definitions (v_environment)), v_state))) (v_choices) (v_counter) (v_certificates) (v_external_functions))) (v_state)))
and (* monomorph.bend:3470 *)
f_prove_one_member_row : (int) list -> (int) list -> (int) list -> M.t_Module -> G.t_Environment -> (t_Choice) Base.map -> int -> (Core.t_Certificate) list -> (Base.text) list -> I.t_State -> t_MemberRowProof =
fun v_candidates v_fixed v_hard_fixed v_module v_environment v_choices v_counter v_certificates v_external_functions v_state ->
(let v_owned = (G.f_names ((f_member_trial_declarations (v_module)))) in
(let v_definitions = (G.f_env_definitions (v_environment)) in
(let v_pending = (Base.map_values (v_choices)) in
(let v_substitutions = (I.f_substitutions_of (v_state)) in
(f_member_row_selected ((f_first_recheckable_member (v_candidates) (v_fixed) (v_hard_fixed) (v_owned) (v_pending) (v_substitutions) (v_definitions))) (v_module) (v_environment) (v_choices) (v_counter) (v_certificates) (v_external_functions) (v_state))))))
and (* monomorph.bend:3477 *)
f_protected_selected_rows : (int) list -> (int) list -> (int) list =
fun v_candidates v_fixed ->
(match v_candidates with
| [] ->
[]
| (v_index :: v_tail) ->
(let v_rest = (f_protected_selected_rows (v_tail) (v_fixed)) in
(Base.bool_pick ((T.f_contains (v_fixed) (v_index))) ((v_index :: v_rest)) (v_rest))))
and (* monomorph.bend:3485 *)
f_prove_protected_member_rows_pending : (int) list -> (int) list -> Base.set -> M.t_Module -> G.t_Environment -> (t_Choice) Base.map -> int -> (Core.t_Certificate) list -> (Base.text) list -> I.t_State -> (M.t_Diagnostic, t_MemberRowProof) Base.result_ =
fun v_pending v_fixed v_reached v_module v_environment v_choices v_counter v_certificates v_external_functions v_state ->
(match v_pending with
| [] ->
(Done ((MemberRowProof (v_state, []))))
| v_pending ->
(let v_definitions = (G.f_env_definitions (v_environment)) in
(let v_bindings = (G.f_env_bindings (v_environment)) in
(let v_substitutions = (I.f_substitutions_of (v_state)) in
(let v_owned = (G.f_names ((f_member_trial_declarations (v_module)))) in
(match (f_reached_input_rows (v_definitions) (v_reached) (v_substitutions)) with
| Fail __error -> Fail __error
| Done v_inputs ->
(match (f_external_fixed_rows (v_bindings) (v_owned) (v_substitutions)) with
| Fail __error -> Fail __error
| Done v_external ->
(let v_hard_fixed = (T.f_union ((f_scheme_quantifiers (v_bindings))) ((T.f_union (v_inputs) (v_external)))) in
(Done ((f_prove_one_member_row (v_pending) (v_fixed) (v_hard_fixed) (v_module) (v_environment) (v_choices) (v_counter) (v_certificates) (v_external_functions) (v_state))))))))))))
and (* monomorph.bend:3500 *)
f_prove_protected_member_rows : (int) list -> (int) list -> Base.set -> M.t_Module -> G.t_Environment -> (t_Choice) Base.map -> int -> (Core.t_Certificate) list -> (Base.text) list -> I.t_State -> (M.t_Diagnostic, t_MemberRowProof) Base.result_ =
fun v_candidates v_fixed v_reached v_module v_environment v_choices v_counter v_certificates v_external_functions v_state ->
(f_prove_protected_member_rows_pending ((f_protected_selected_rows (v_candidates) (v_fixed))) (v_fixed) (v_reached) (v_module) (v_environment) (v_choices) (v_counter) (v_certificates) (v_external_functions) (v_state))
and (* monomorph.bend:3503 *)
f_member_proof_state : t_MemberRowProof -> I.t_State =
fun v_proof ->
(match v_proof with
| (MemberRowProof (v_state, v_certified)) ->
v_state)
and (* monomorph.bend:3508 *)
f_member_proof_certified : t_MemberRowProof -> (t_MemberEvidenceCertificate) list =
fun v_proof ->
(match v_proof with
| (MemberRowProof (v_state, v_certified)) ->
v_certified)
and (* monomorph.bend:3513 *)
f_finalize_with_selected_rows : (int) list -> Base.set -> M.t_Module -> G.t_Environment -> (t_Choice) Base.map -> int -> (Core.t_Certificate) list -> (Base.text) list -> (M.t_Diagnostic, t_Specialization) Base.result_ =
fun v_candidates v_reached v_module v_environment v_choices v_counter v_certificates v_external_functions ->
(match v_candidates with
| [] ->
(let v_definitions = (G.f_env_definitions (v_environment)) in
(let v_bindings = (G.f_env_bindings (v_environment)) in
(let v_substitutions = (I.f_substitutions_of ((G.f_env_state (v_environment)))) in
(match (f_relink_reached_definitions (v_definitions) (v_reached) (v_choices) ((G.f_env_state (v_environment)))) with
| Fail __error -> Fail __error
| Done v_linked ->
(match (f_finalize_evidence_certified (v_module) ((G.Environment (v_bindings, v_definitions, v_linked))) (v_choices) ([])) with
| Fail __error -> Fail __error
| Done v_answers ->
(Done ((Specialization (v_module, (G.Environment (v_bindings, v_definitions, v_linked)), v_answers, v_counter, v_certificates)))))))))
| v_pending_rows ->
(let v_definitions = (G.f_env_definitions (v_environment)) in
(let v_bindings = (G.f_env_bindings (v_environment)) in
(let v_substitutions = (I.f_substitutions_of ((G.f_env_state (v_environment)))) in
(match (f_reached_interface_rows (v_definitions) (v_reached) (v_substitutions)) with
| Fail __error -> Fail __error
| Done v_interfaces ->
(match (f_external_fixed_rows (v_bindings) ((f_reached_definition_names (v_definitions) (v_reached))) (v_substitutions)) with
| Fail __error -> Fail __error
| Done v_external ->
(let v_fixed = (T.f_union ((f_scheme_quantifiers (v_bindings))) ((T.f_union (v_interfaces) (v_external)))) in
(match (f_close_selected_rows (v_pending_rows) (v_fixed) ((G.f_env_state (v_environment)))) with
| Fail __error -> Fail __error
| Done v_closed ->
(match (f_prove_protected_member_rows (v_pending_rows) (v_fixed) (v_reached) (v_module) (v_environment) (v_choices) (v_counter) (v_certificates) (v_external_functions) (v_closed)) with
| Fail __error -> Fail __error
| Done v_proof ->
(match (f_relink_reached_definitions (v_definitions) (v_reached) (v_choices) ((f_member_proof_state (v_proof)))) with
| Fail __error -> Fail __error
| Done v_linked ->
(match (f_finalize_evidence_certified (v_module) ((G.Environment (v_bindings, v_definitions, v_linked))) (v_choices) ((f_member_proof_certified (v_proof)))) with
| Fail __error -> Fail __error
| Done v_answers ->
(Done ((Specialization (v_module, (G.Environment (v_bindings, v_definitions, v_linked)), v_answers, v_counter, v_certificates)))))))))))))))
and (* monomorph.bend:3537 *)
f_finalize_specialization : t_Specialization -> t_Configuration -> (M.t_Diagnostic, t_Specialization) Base.result_ =
fun v_specialized v_configuration ->
(let (Specialization (v_module, v_environment, v_choices, v_counter, v_certificates)) = v_specialized in
(let (Configuration (v_originals, v_templates, v_entry, v_locals, v_affected, v_stride, v_constant_values, v_family_templates, v_step, v_schema)) = v_configuration in
(let v_external_functions = (G.f_function_names ((G.f_function_declarations (v_originals)))) in
(let v_refreshed = (f_refresh_type_eq_definitions ((G.f_env_definitions (v_environment))) ((I.f_substitutions_of ((G.f_env_state (v_environment))))) (v_choices) (v_module)) in
(match (f_reached_names ((Specialization (v_module, v_environment, v_refreshed, v_counter, v_certificates))) (v_configuration)) with
| Fail __error -> Fail __error
| Done v_reached ->
(match (f_resolved_signature_rows ((f_reached_selected_types ((G.f_env_definitions (v_environment))) (v_reached) (v_refreshed))) ((I.f_substitutions_of ((G.f_env_state (v_environment)))))) with
| Fail __error -> Fail __error
| Done v_candidates ->
(f_finalize_with_selected_rows (v_candidates) (v_reached) (v_module) (v_environment) (v_refreshed) (v_counter) (v_certificates) (v_external_functions))))))))
and (* monomorph.bend:3547 *)
f_finish_boundary_progress : (I.t_Coverage) list -> t_BoundaryProgress -> t_Configuration -> (M.t_Diagnostic, t_Specialization) Base.result_ =
fun v_needs v_progress v_configuration ->
(match (v_needs, v_progress) with
| ([], (BoundaryProgress (v_updated, false))) ->
(f_finalize_specialization (v_updated) (v_configuration))
| (_, (BoundaryProgress (v_updated, v_changed))) ->
(match (f_prune_generic_roots (v_updated) (v_configuration)) with
| Fail __error -> Fail __error
| Done v_retained ->
(f_finalize_specialization (v_retained) (v_configuration))))
and (* monomorph.bend:3556 *)
f_finish_requirements : (I.t_Coverage) list -> t_Specialization -> t_Configuration -> (I.t_Binding) list -> (Staging.t_Scheme) list -> (M.t_Diagnostic, t_Specialization) Base.result_ =
fun v_needs v_specialized v_configuration v_shapes v_schemes ->
(match (f_schedule_boundaries (65536) ((CheckBoundaries (v_specialized, false))) (v_configuration) (v_shapes) (v_schemes)) with
| Fail __error -> Fail __error
| Done v_progress ->
(f_finish_boundary_progress (v_needs) (v_progress) (v_configuration)))
and (* monomorph.bend:3561 *)
f_infer_required_at : t_ExpandedModule -> t_Configuration -> (I.t_Binding) list -> bool -> (M.t_Diagnostic, int) Base.result_ -> (M.t_Diagnostic, t_ExpandedModule) Base.result_ =
fun v_expanded v_configuration v_shapes v_isolated v_limit ->
(let (ExpandedModule ((M.Module (v_constants, v_functions, v_types, v_operations)), v_counter, v_bindings, v_certificates)) = v_expanded in
(let (Configuration (v_originals, v_templates, v_entry, v_locals, v_affected, v_stride, v_constant_values, v_family_templates, v_step, v_schema)) = v_configuration in
(let v_owned = (Base.list_append ((G.f_function_declarations (v_functions))) ((G.f_constant_declarations (v_constants)))) in
(let v_ordinary = (f_ordinary_bindings (v_shapes) ((Base.bool_pick (v_isolated) ((G.f_names (v_owned))) (v_affected)))) in
(let v_declarations = (Base.list_append ((G.f_function_declarations ((f_pending_functions (v_functions) (v_ordinary))))) ((G.f_constant_declarations ((f_pending_constants (v_constants) (v_ordinary)))))) in
(match v_limit with
| Fail __error -> Fail __error
| Done v_start ->
(match (f_infer_pending (v_declarations) (v_shapes) ((G.Environment (v_ordinary, [], (I.State ((T.f_empty ()), v_start, MTip))))) (v_operations) (v_types) ((G.f_function_names ((G.f_function_declarations ((Base.list_append (v_originals) (v_functions)))))))) with
| Fail __error -> Fail __error
| Done v_inferred ->
(let v_initial_needs = (f_pending (v_inferred)) in
(let v_initial_count = (Base.list_length ((G.f_env_definitions (v_inferred)))) in
(match (f_solve (65536) ((Needs (v_initial_needs))) ((Specialization ((M.Module (v_constants, v_functions, v_types, v_operations)), v_inferred, (Base.map_new ()), v_counter, v_certificates))) (v_configuration) (v_shapes) ((PendingCache (v_initial_count, v_initial_needs)))) with
| Fail __error -> Fail __error
| Done v_solved ->
(match (f_finish_requirements ((f_specialization_pending (v_solved))) (v_solved) (v_configuration) (v_shapes) ([])) with
| Fail __error -> Fail __error
| Done v_specialized ->
(f_finish_expansion (v_specialized)))))))))))))
and (* monomorph.bend:3576 *)
f_infer_required : t_ExpandedModule -> t_Configuration -> (I.t_Binding) list -> bool -> (M.t_Diagnostic, t_ExpandedModule) Base.result_ =
fun v_expanded v_configuration v_shapes v_isolated ->
(f_infer_required_at (v_expanded) (v_configuration) (v_shapes) (v_isolated) ((f_shape_limit (v_shapes) (0))))
and (* monomorph.bend:3579 *)
f_infer_present : bool -> t_ExpandedModule -> t_Configuration -> (I.t_Binding) list -> bool -> (M.t_Diagnostic, t_ExpandedModule) Base.result_ =
fun v_present v_expanded v_configuration v_shapes v_isolated ->
(match v_present with
| false ->
(Done (v_expanded))
| true ->
(f_infer_required (v_expanded) (v_configuration) (v_shapes) (v_isolated)))
and (* monomorph.bend:3586 *)
f_infer_expansion : t_ExpandedModule -> t_Configuration -> (I.t_Binding) list -> bool -> (M.t_Diagnostic, t_ExpandedModule) Base.result_ =
fun v_expanded v_configuration v_shapes v_isolated ->
(let (ExpandedModule (v_module, v_counter, v_bindings, v_certificates)) = v_expanded in
(f_infer_present ((f_required (v_module))) (v_expanded) (v_configuration) (v_shapes) (v_isolated)))
and (* monomorph.bend:3590 *)
f_infer_required_staged_at : t_ExpandedModule -> t_Configuration -> (I.t_Binding) list -> bool -> (Staging.t_Scheme) list -> (M.t_Diagnostic, int) Base.result_ -> (M.t_Diagnostic, t_ExpandedModule) Base.result_ =
fun v_expanded v_configuration v_shapes v_isolated v_schemes v_limit ->
(let (ExpandedModule ((M.Module (v_constants, v_functions, v_types, v_operations)), v_counter, v_bindings, v_certificates)) = v_expanded in
(let (Configuration (v_originals, v_templates, v_entry, v_locals, v_affected, v_stride, v_constant_values, v_family_templates, v_step, v_schema)) = v_configuration in
(let v_owned = (Base.list_append ((G.f_function_declarations (v_functions))) ((G.f_constant_declarations (v_constants)))) in
(let v_ordinary = (f_ordinary_bindings (v_shapes) ((Base.bool_pick (v_isolated) ((G.f_names (v_owned))) (v_affected)))) in
(let v_declarations = (Base.list_append ((G.f_function_declarations ((f_pending_functions (v_functions) (v_ordinary))))) ((G.f_constant_declarations ((f_pending_constants (v_constants) (v_ordinary)))))) in
(match v_limit with
| Fail __error -> Fail __error
| Done v_start ->
(match (f_infer_pending_staged (v_declarations) (v_shapes) ((G.Environment (v_ordinary, [], (I.State ((T.f_empty ()), v_start, MTip))))) (v_operations) (v_types) ((G.f_function_names ((G.f_function_declarations ((Base.list_append (v_originals) (v_functions))))))) (v_schemes) (v_stride)) with
| Fail __error -> Fail __error
| Done v_inferred ->
(let v_initial_needs = (f_pending (v_inferred)) in
(let v_initial_count = (Base.list_length ((G.f_env_definitions (v_inferred)))) in
(match (f_solve_staged (65536) ((Needs (v_initial_needs))) ((Specialization ((M.Module (v_constants, v_functions, v_types, v_operations)), v_inferred, (Base.map_new ()), v_counter, v_certificates))) (v_configuration) (v_shapes) ((PendingCache (v_initial_count, v_initial_needs))) (v_schemes)) with
| Fail __error -> Fail __error
| Done v_solved ->
(match (f_finish_requirements ((f_specialization_pending (v_solved))) (v_solved) (v_configuration) (v_shapes) (v_schemes)) with
| Fail __error -> Fail __error
| Done v_specialized ->
(f_finish_expansion (v_specialized)))))))))))))
and (* monomorph.bend:3605 *)
f_infer_required_staged : t_ExpandedModule -> t_Configuration -> (I.t_Binding) list -> bool -> (Staging.t_Scheme) list -> (M.t_Diagnostic, t_ExpandedModule) Base.result_ =
fun v_expanded v_configuration v_shapes v_isolated v_schemes ->
(f_infer_required_staged_at (v_expanded) (v_configuration) (v_shapes) (v_isolated) (v_schemes) ((f_shape_limit (v_shapes) (0))))
and (* monomorph.bend:3608 *)
f_infer_required_optional : t_ExpandedModule -> t_Configuration -> (I.t_Binding) list -> bool -> (Staging.t_Scheme) list -> (M.t_Diagnostic, t_ExpandedModule) Base.result_ =
fun v_expanded v_configuration v_shapes v_isolated v_schemes ->
(match v_schemes with
| [] ->
(f_infer_required (v_expanded) (v_configuration) (v_shapes) (v_isolated))
| (v_head :: v_tail) ->
(f_infer_required_staged (v_expanded) (v_configuration) (v_shapes) (v_isolated) ((v_head :: v_tail))))
and (* monomorph.bend:3615 *)
f_infer_present_staged : bool -> t_ExpandedModule -> t_Configuration -> (I.t_Binding) list -> bool -> (Staging.t_Scheme) list -> (M.t_Diagnostic, t_ExpandedModule) Base.result_ =
fun v_present v_expanded v_configuration v_shapes v_isolated v_schemes ->
(match v_present with
| false ->
(Done (v_expanded))
| true ->
(f_infer_required_staged (v_expanded) (v_configuration) (v_shapes) (v_isolated) (v_schemes)))
and (* monomorph.bend:3622 *)
f_infer_expansion_staged : t_ExpandedModule -> t_Configuration -> (I.t_Binding) list -> bool -> (Staging.t_Scheme) list -> (M.t_Diagnostic, t_ExpandedModule) Base.result_ =
fun v_expanded v_configuration v_shapes v_isolated v_schemes ->
(let (ExpandedModule (v_module, v_counter, v_bindings, v_certificates)) = v_expanded in
(match v_schemes with
| [] ->
(f_infer_expansion (v_expanded) (v_configuration) (v_shapes) (v_isolated))
| (v_head :: v_tail) ->
(f_infer_present_staged ((f_required (v_module))) (v_expanded) (v_configuration) (v_shapes) (v_isolated) ((v_head :: v_tail)))))
and (* monomorph.bend:3631 *)
f_has_predicates : (M.t_Predicate) list -> bool =
fun v_predicates ->
(match v_predicates with
| [] ->
false
| (v_head :: v_tail) ->
true)
and (* monomorph.bend:3638 *)
f_infer_present_at : bool -> t_ExpandedModule -> t_Configuration -> (I.t_Binding) list -> bool -> (Staging.t_Scheme) list -> (M.t_Diagnostic, int) Base.result_ -> (M.t_Diagnostic, t_ExpandedModule) Base.result_ =
fun v_present v_expanded v_configuration v_shapes v_isolated v_schemes v_limit ->
(match (v_present, v_schemes) with
| (false, _) ->
(Done (v_expanded))
| (true, []) ->
(f_infer_required_at (v_expanded) (v_configuration) (v_shapes) (v_isolated) (v_limit))
| (true, (v_head :: v_tail)) ->
(f_infer_required_staged_at (v_expanded) (v_configuration) (v_shapes) (v_isolated) ((v_head :: v_tail)) (v_limit)))
and (* monomorph.bend:3647 *)
f_infer_expansion_at : t_ExpandedModule -> t_Configuration -> (I.t_Binding) list -> bool -> (Staging.t_Scheme) list -> (M.t_Diagnostic, int) Base.result_ -> (M.t_Diagnostic, t_ExpandedModule) Base.result_ =
fun v_expanded v_configuration v_shapes v_isolated v_schemes v_limit ->
(let (ExpandedModule (v_module, v_counter, v_bindings, v_certificates)) = v_expanded in
(f_infer_present_at ((f_required (v_module))) (v_expanded) (v_configuration) (v_shapes) (v_isolated) (v_schemes) (v_limit)))
and (* monomorph.bend:3651 *)
f_generic_template_selected : bool -> Base.text -> M.t_Ty -> (M.t_Predicate) list -> (Base.text) list -> (Base.text) list =
fun v_selected v_name v_ty v_predicates v_rest ->
(match v_selected with
| false ->
v_rest
| true ->
(Base.bool_pick ((Base.bool_or ((f_polymorphic (65536) ([v_ty]))) ((f_has_predicates (v_predicates))))) ((v_name :: v_rest)) (v_rest)))
and (* monomorph.bend:3658 *)
f_generic_templates_in : (I.t_Binding) list -> Base.set -> (Base.text) list =
fun v_bindings v_affected ->
(match v_bindings with
| [] ->
[]
| ((I.Binding (v_name, v_ty, v_variables, v_predicates)) :: v_tail) ->
(f_generic_template_selected ((D.f_member (v_affected) (v_name))) (v_name) (v_ty) (v_predicates) ((f_generic_templates_in (v_tail) (v_affected)))))
and (* monomorph.bend:3665 *)
f_generic_templates : (I.t_Binding) list -> (Base.text) list -> (Base.text) list =
fun v_bindings v_affected ->
(f_generic_templates_in (v_bindings) ((Base.set_from_list (v_affected))))
and (* monomorph.bend:3668 *)
f_constant_annotation : (M.t_Ty) option -> M.t_Expr -> M.t_Expr =
fun v_annotation v_value ->
(match (v_annotation, v_value) with
| (None, v_value) ->
v_value
| ((Some (v_ty)), (M.SourceExpr (v_offset, v_previous, v_value))) ->
(M.SourceExpr (v_offset, (Some (v_ty)), v_value))
| ((Some (v_ty)), v_value) ->
(M.SourceExpr (0, (Some (v_ty)), v_value)))
and (* monomorph.bend:3677 *)
f_constant_template_selected : bool -> Base.text -> (M.t_Ty) option -> M.t_Expr -> (t_LocalTemplate) list -> (t_LocalTemplate) list =
fun v_selected v_name v_annotation v_value v_rest ->
(match v_selected with
| false ->
v_rest
| true ->
(Base.bool_pick ((f_template_value (65536) (v_value))) (((LocalTemplate (v_name, (f_constant_annotation (v_annotation) (v_value)))) :: v_rest)) (v_rest)))
and (* monomorph.bend:3684 *)
f_constant_templates_in : (M.t_Constant) list -> Base.set -> (t_LocalTemplate) list =
fun v_constants v_affected ->
(match v_constants with
| [] ->
[]
| ((M.Constant (v_name, v_exported, v_annotation, v_value)) :: v_tail) ->
(f_constant_template_selected ((D.f_member (v_affected) (v_name))) (v_name) (v_annotation) (v_value) ((f_constant_templates_in (v_tail) (v_affected)))))
and (* monomorph.bend:3691 *)
f_constant_templates : (M.t_Constant) list -> (Base.text) list -> (t_LocalTemplate) list =
fun v_constants v_affected ->
(f_constant_templates_in (v_constants) ((Base.set_from_list (v_affected))))
and (* monomorph.bend:3694 *)
f_retained_constants : (M.t_Constant) list -> (t_LocalTemplate) list -> (M.t_Constant) list =
fun v_constants v_templates ->
(match v_constants with
| [] ->
[]
| ((M.Constant (v_name, v_exported, v_annotation, v_value)) :: v_tail) ->
(let v_rest = (f_retained_constants (v_tail) (v_templates)) in
(Base.bool_pick ((Base.bool_and ((Base.bool_not (v_exported))) ((Base.maybe_is_some ((f_local_template (v_templates) (v_name))))))) (v_rest) (((M.Constant (v_name, v_exported, v_annotation, v_value)) :: v_rest)))))
and (* monomorph.bend:3702 *)
f_polymorphic_callable : int -> (M.t_Ty) list -> bool =
fun v_fuel v_pending ->
(match (v_fuel, v_pending) with
| (_, []) ->
false
| (0, _) ->
false
| (__nat_80, ((M.FunctionTy (v_parameter, v_result, v_row)) :: v_tail)) when __nat_80 >= 1 ->
(let v_rest = (__nat_80 - 1) in
(Base.bool_or ((f_polymorphic (65536) ([v_parameter; v_result]))) ((f_polymorphic_callable (v_rest) (v_tail)))))
| (__nat_81, ((M.AppliedTy (v_identity, v_arguments)) :: v_tail)) when __nat_81 >= 1 ->
(let v_rest = (__nat_81 - 1) in
(f_polymorphic_callable (v_rest) ((Base.list_append (v_arguments) (v_tail)))))
| (__nat_82, ((M.ProductTy (v_elements)) :: v_tail)) when __nat_82 >= 1 ->
(let v_rest = (__nat_82 - 1) in
(f_polymorphic_callable (v_rest) ((Base.list_append (v_elements) (v_tail)))))
| (__nat_83, ((M.ArrayTy (v_element)) :: v_tail)) when __nat_83 >= 1 ->
(let v_rest = (__nat_83 - 1) in
(f_polymorphic_callable (v_rest) ((v_element :: v_tail))))
| (__nat_84, (v_head :: v_tail)) when __nat_84 >= 1 ->
(let v_rest = (__nat_84 - 1) in
(f_polymorphic_callable (v_rest) (v_tail))))
and (* monomorph.bend:3719 *)
f_constant_callable : (I.t_Binding) option -> bool =
fun v_found ->
(match v_found with
| (Some ((I.Binding (v_name, v_ty, v_variables, v_predicates)))) ->
(Base.bool_or ((f_polymorphic_callable (65536) ([v_ty]))) ((f_has_predicates (v_predicates))))
| None ->
false)
and (* monomorph.bend:3726 *)
f_specialized_constant_callable : bool -> M.t_Constant -> (M.t_Constant) list -> (M.t_Constant) list =
fun v_callable v_constant v_rest ->
(match v_callable with
| false ->
v_rest
| true ->
(let (M.Constant (v_name, v_exported, v_annotation, v_value)) = v_constant in
(Base.bool_pick ((f_template_value (65536) (v_value))) (v_rest) ((v_constant :: v_rest)))))
and (* monomorph.bend:3734 *)
f_specialized_constant_selected : bool -> M.t_Constant -> (I.t_Binding) list -> (M.t_Constant) list -> (M.t_Constant) list =
fun v_selected v_constant v_shapes v_rest ->
(match v_selected with
| false ->
v_rest
| true ->
(let (M.Constant (v_name, v_exported, v_annotation, v_value)) = v_constant in
(f_specialized_constant_callable ((f_constant_callable ((I.f_lookup_binding (v_shapes) (v_name))))) (v_constant) (v_rest))))
and (* monomorph.bend:3742 *)
f_specialized_constants_in : (M.t_Constant) list -> Base.set -> (I.t_Binding) list -> (M.t_Constant) list =
fun v_constants v_templates v_shapes ->
(match v_constants with
| [] ->
[]
| ((M.Constant (v_name, v_exported, v_annotation, (M.RuntimeInitExpr (v_value)))) :: v_tail) ->
(f_specialized_constants_in (v_tail) (v_templates) (v_shapes))
| ((M.Constant (v_name, v_exported, v_annotation, v_value)) :: v_tail) ->
(let v_constant = (M.Constant (v_name, v_exported, v_annotation, v_value)) in
(f_specialized_constant_selected ((D.f_member (v_templates) (v_name))) (v_constant) (v_shapes) ((f_specialized_constants_in (v_tail) (v_templates) (v_shapes))))))
and (* monomorph.bend:3752 *)
f_specialized_constants : (M.t_Constant) list -> (Base.text) list -> (I.t_Binding) list -> (M.t_Constant) list =
fun v_constants v_templates v_shapes ->
(f_specialized_constants_in (v_constants) ((Base.set_from_list (v_templates))) (v_shapes))
and (* monomorph.bend:3755 *)
f_retained_specializations : (M.t_Constant) list -> (M.t_Constant) list -> (M.t_Constant) list =
fun v_constants v_templates ->
(match v_constants with
| [] ->
[]
| (v_constant :: v_tail) ->
(let (M.Constant (v_name, v_exported, v_annotation, v_value)) = v_constant in
(let v_rest = (f_retained_specializations (v_tail) (v_templates)) in
(Base.bool_pick ((Base.bool_and ((Base.bool_not (v_exported))) ((Base.maybe_is_some ((f_lookup_constant (v_templates) (v_name))))))) (v_rest) ((v_constant :: v_rest))))))
and (* monomorph.bend:3764 *)
f_expression_identity : M.t_Expr -> int =
fun v_expression ->
(match v_expression with
| (M.TagExpr (v_offset, v_callee, v_argument)) ->
v_offset
| (M.SourceExpr (v_offset, v_annotation, v_value)) ->
v_offset
| (M.LambdaExpr (v_identity, v_parameter, v_p, v_r, v_body)) ->
v_identity
| (M.BlockExpr (v_label, v_body)) ->
v_label
| (M.ReturnExpr (v_label, v_value)) ->
v_label
| (M.AssociatedExpr (v_identity, v_dispatch, v_member, v_templates, v_left, v_right)) ->
v_identity
| (M.GenericOperationExpr (v_identity, v_template, v_arguments)) ->
v_identity
| (M.InstantiationExpr (v_site, v_value)) ->
v_site
| _ ->
0)
and (* monomorph.bend:3785 *)
f_identity_limit : int -> (M.t_Expr) list -> int -> (M.t_Diagnostic, int) Base.result_ =
fun v_fuel v_pending v_maximum ->
(match (v_fuel, v_pending) with
| (_, []) ->
(Done ((Base.nat_add 1 v_maximum)))
| (0, _) ->
(Fail ((M.Diagnostic (s_8, s_1, s_132))))
| (__nat_85, (v_head :: v_tail)) when __nat_85 >= 1 ->
(let v_rest = (__nat_85 - 1) in
(let v_found = (f_expression_identity (v_head)) in
(f_identity_limit (v_rest) ((Base.list_reverse_go ((Base.list_reverse ((F.f_children (v_head))))) (v_tail))) ((Base.bool_pick ((Base.nat_is_gt (v_found) (v_maximum))) (v_found) (v_maximum)))))))
and (* monomorph.bend:3795 *)
f_module_expressions : (M.t_Function) list -> (M.t_Constant) list -> (M.t_Expr) list =
fun v_functions v_constants ->
(match (v_functions, v_constants) with
| (((M.Function (v_name, v_exported, v_parameter, v_p, v_r, v_body)) :: v_tail), v_constants) ->
(v_body :: (f_module_expressions (v_tail) (v_constants)))
| ([], ((M.Constant (v_name, v_exported, v_annotation, v_value)) :: v_tail)) ->
(v_value :: (f_module_expressions ([]) (v_tail)))
| ([], []) ->
[])
and (* monomorph.bend:3804 *)
f_known_constant : (I.t_Binding) option -> bool =
fun v_binding ->
(match v_binding with
| (Some ((I.Binding (v_name, v_ty, v_variables, v_predicates)))) ->
(Base.bool_and ((Base.bool_not ((f_polymorphic (65536) ([v_ty]))))) ((Base.bool_not ((f_has_predicates (v_predicates))))))
| None ->
false)
and (* monomorph.bend:3813 *)
f_independent_constants : (M.t_Constant) list -> (Base.text) list -> (I.t_Binding) list -> bool =
fun v_constants v_affected v_shapes ->
(match v_constants with
| [] ->
true
| ((M.Constant (v_name, v_exported, v_annotation, v_value)) :: v_tail) ->
(Base.bool_and ((Base.bool_or ((Base.bool_not ((D.f_contains (v_affected) (v_name))))) ((f_known_constant ((I.f_lookup_binding (v_shapes) (v_name))))))) ((f_independent_constants (v_tail) (v_affected) (v_shapes)))))
and (* monomorph.bend:3820 *)
f_expanded_module : t_ExpandedModule -> M.t_Module =
fun v_expanded ->
(let (ExpandedModule (v_module, v_counter, v_bindings, v_certificates)) = v_expanded in
v_module)
and (* monomorph.bend:3824 *)
f_expanded_next : t_ExpandedModule -> int =
fun v_expanded ->
(let (ExpandedModule (v_module, v_counter, v_bindings, v_certificates)) = v_expanded in
v_counter)
and (* monomorph.bend:3828 *)
f_expanded_certificates : t_ExpandedModule -> (Core.t_Certificate) list =
fun v_expanded ->
(let (ExpandedModule (v_module, v_counter, v_bindings, v_certificates)) = v_expanded in
v_certificates)
and (* monomorph.bend:3832 *)
f_combine_expansions : t_ExpandedModule -> t_ExpandedModule -> t_ExpandedModule =
fun v_first v_rest ->
(let (ExpandedModule ((M.Module (v_a_constants, v_a_functions, v_types, v_operations)), v_counter, v_first_bindings, v_first_certificates)) = v_first in
(let (ExpandedModule ((M.Module (v_b_constants, v_b_functions, v_b_types, v_b_operations)), v_next, v_next_bindings, v_next_certificates)) = v_rest in
(ExpandedModule ((M.Module ((Base.list_append (v_a_constants) (v_b_constants)), (Base.list_append (v_a_functions) (v_b_functions)), v_types, (State.f_merge (v_b_operations) (v_operations)))), (Base.bool_pick ((Base.nat_is_ge (v_counter) (v_next))) (v_counter) (v_next)), (Base.list_append (v_first_bindings) (v_next_bindings)), (Base.list_append (v_first_certificates) (v_next_certificates))))))
and (* monomorph.bend:3837 *)
f_expand_declaration : G.t_Declaration -> t_Configuration -> (M.t_DataType) list -> (M.t_Operation) list -> int -> (M.t_Diagnostic, t_ExpandedModule) Base.result_ =
fun v_declaration v_configuration v_types v_operations v_counter ->
(match v_declaration with
| (G.FunctionDeclaration (v_function)) ->
(let (M.Function (v_name, v_exported, v_parameter, v_p, v_r, v_body)) = v_function in
(let (Configuration (v_originals, v_templates, v_entry, v_locals, v_affected, v_stride, v_constant_values, v_family_templates, v_step, v_schema)) = v_configuration in
(match (f_expand_root ((Base.bool_or ((Base.bool_and (v_exported) ((D.f_contains (v_templates) (v_name))))) ((Base.bool_and ((Base.bool_not ((D.f_contains (v_templates) (v_name))))) ((D.f_contains (v_affected) (v_name))))))) ((D.f_contains (v_templates) (v_name))) (v_function) (v_configuration) (v_counter)) with
| Fail __error -> Fail __error
| Done v_expanded ->
(Done ((ExpandedModule ((M.Module ((f_emitted_constants (v_expanded)), (f_functions (v_expanded)), v_types, v_operations)), (f_next (v_expanded)), [], [])))))))
| (G.ConstantDeclaration ((M.Constant (v_name, v_exported, v_annotation, v_value)))) ->
(match (f_expand (65536) ((Expression (v_value))) (v_configuration) ([]) (0) (v_counter)) with
| Fail __error -> Fail __error
| Done v_expanded ->
(match (f_one ((f_expressions (v_expanded)))) with
| Fail __error -> Fail __error
| Done v_expression ->
(Done ((ExpandedModule ((M.Module (((M.Constant (v_name, v_exported, v_annotation, v_expression)) :: (f_emitted_constants (v_expanded))), (f_functions (v_expanded)), v_types, v_operations)), (f_next (v_expanded)), [], [])))))))
and (* monomorph.bend:3869 *)
f_empty_cache : unit -> t_Cache =
fun () ->
(Cache ([], [], (Base.map_new ()), []))
and (* monomorph.bend:3882 *)
f_prepared_module : t_Prepared -> M.t_Module =
fun v_prepared ->
(let (Prepared (v_module, v_cache, v_certificates)) = v_prepared in
v_module)
and (* monomorph.bend:3886 *)
f_prepared_cache : t_Prepared -> t_Cache =
fun v_prepared ->
(let (Prepared (v_module, v_cache, v_certificates)) = v_prepared in
v_cache)
and (* monomorph.bend:3890 *)
f_source_certificates : (t_Cache) option -> (Core.t_Certificate) list =
fun v_previous ->
(match v_previous with
| None ->
[]
| (Some ((Cache (v_context, v_tasks, v_sources, v_certificates)))) ->
v_certificates)
and (* monomorph.bend:3899 *)
f_with_source_certificates : t_Prepared -> (Core.t_Certificate) list -> t_Prepared =
fun v_prepared v_certificates ->
(let (Prepared (v_module, (Cache (v_context, v_tasks, v_sources, v_old)), v_final_certificates)) = v_prepared in
(Prepared (v_module, (Cache (v_context, v_tasks, v_sources, (Core.f_ready_certificates (v_certificates)))), v_final_certificates)))
and (* monomorph.bend:3903 *)
f_prepared_certificates : t_Prepared -> (Core.t_Certificate) list =
fun v_prepared ->
(let (Prepared (v_module, v_cache, v_certificates)) = v_prepared in
v_certificates)
and (* monomorph.bend:3907 *)
f_same_words_go : (int32) list -> (int32) list -> bool -> bool =
fun v_left v_right v_equal ->
(match (v_left, v_right, v_equal) with
| (_, _, false) ->
false
| ([], [], true) ->
true
| ((v_a :: v_rest_a), (v_b :: v_rest_b), true) ->
(f_same_words_go (v_rest_a) (v_rest_b) ((Base.u32_is_eq (v_a) (v_b))))
| (_, _, _) ->
false)
and (* monomorph.bend:3918 *)
f_same_words : (int32) list -> (int32) list -> bool =
fun v_left v_right ->
(f_same_words_go (v_left) (v_right) (true))
and (* monomorph.bend:3921 *)
f_task_index : (t_CachedTask) list -> (t_CachedTask) Base.map -> (t_CachedTask) Base.map =
fun v_tasks v_index ->
(match v_tasks with
| [] ->
v_index
| ((CachedTask (v_at, v_name, v_dependencies, v_result)) :: v_tail) ->
(f_task_index (v_tail) ((Base.map_set (v_index) ((Base.nat_show (v_at))) ((CachedTask (v_at, v_name, v_dependencies, v_result)))))))
and (* monomorph.bend:3928 *)
f_reusable_match : bool -> (t_CachedTask) list -> ((int32) list) Base.map -> t_Reusable =
fun v_equal v_tasks v_sources ->
(match v_equal with
| true ->
(Reusable (v_tasks, v_sources))
| false ->
(Reusable ([], (Base.map_new ()))))
and (* monomorph.bend:3935 *)
f_cache_for_context : (t_Cache) option -> (int32) list -> t_Reusable =
fun v_previous v_context ->
(match v_previous with
| None ->
(Reusable ([], (Base.map_new ())))
| (Some ((Cache (v_prior, v_tasks, v_sources, v_certificates)))) ->
(f_reusable_match ((f_same_words (v_prior) (v_context))) (v_tasks) (v_sources)))
and (* monomorph.bend:3942 *)
f_shape_variables : (int) list -> (M.t_Function) list =
fun v_variables ->
(match v_variables with
| [] ->
[]
| (v_head :: v_tail) ->
((M.Function ((Base.nat_show (v_head)), false, s_11, None, None, M.UnitExpr)) :: (f_shape_variables (v_tail))))
and (* monomorph.bend:3949 *)
f_shape_key_body : M.t_Ty -> (M.t_Predicate) list -> M.t_Expr =
fun v_ty v_predicates ->
(match v_predicates with
| [] ->
M.UnitExpr
| v_predicates ->
(M.QualifiedExpr (0, v_ty, v_predicates, M.UnitExpr)))
and (* monomorph.bend:3956 *)
f_shape_functions : (I.t_Binding) list -> (M.t_Function) list =
fun v_shapes ->
(match v_shapes with
| [] ->
[]
| ((I.Binding (v_name, v_ty, v_variables, v_predicates)) :: v_tail) ->
((M.Function (v_name, false, (Base.nat_show ((Base.list_length (v_variables)))), (Some (v_ty)), None, (f_shape_key_body (v_ty) (v_predicates)))) :: (Base.list_append ((f_shape_variables (v_variables))) ((f_shape_functions (v_tail))))))
and (* monomorph.bend:3963 *)
f_marker_functions : (Base.text) list -> (M.t_Function) list =
fun v_names ->
(match v_names with
| [] ->
[]
| (v_name :: v_tail) ->
((M.Function (v_name, false, s_11, None, None, M.UnitExpr)) :: (f_marker_functions (v_tail))))
and (* monomorph.bend:3970 *)
f_local_constants : (t_LocalTemplate) list -> (M.t_Constant) list =
fun v_locals ->
(match v_locals with
| [] ->
[]
| ((LocalTemplate (v_name, v_value)) :: v_tail) ->
((M.Constant (v_name, false, None, v_value)) :: (f_local_constants (v_tail))))
and (* monomorph.bend:3977 *)
f_unplanned_functions : (M.t_Function) list -> (Base.text) list -> (M.t_Function) list =
fun v_functions v_planned ->
(match v_functions with
| [] ->
[]
| (v_function :: v_tail) ->
(let (M.Function (v_name, v_exported, v_parameter, v_input, v_output, v_body)) = v_function in
(let v_rest = (f_unplanned_functions (v_tail) (v_planned)) in
(Base.bool_pick ((D.f_contains (v_planned) (v_name))) (v_rest) ((v_function :: v_rest))))))
and (* monomorph.bend:3989 *)
f_schema_source_functions : (Schema.t_Evidence) list -> (M.t_Function) list =
fun v_proofs ->
(match v_proofs with
| [] ->
[]
| ((Schema.Evidence (v_node_method, v_terminal_method, v_equality, v_type_equality, v_node_type, v_terminal_type, v_witness_type, v_node_constructor, v_terminal_identity, v_node_identity, v_member)) :: v_tail) ->
(v_node_method :: (v_terminal_method :: (v_equality :: (v_type_equality :: (f_schema_source_functions (v_tail)))))))
and (* monomorph.bend:3996 *)
f_context_module : t_SpecializationContext -> (D.t_Node) list -> M.t_Module =
fun v_context v_nodes ->
(let (SpecializationContext ((Configuration (v_originals, v_templates, v_entry, v_locals, v_affected, v_stride, v_constants, v_family_templates, v_step, v_schema)), v_shapes, v_types, v_operations, v_schemes, v_limit)) = v_context in
(let v_metadata = [(M.Function (v_entry, false, (Base.nat_show (v_stride)), None, None, M.UnitExpr)); (M.Function ((Base.nat_show (v_step)), false, (Base.nat_show ((Base.list_length (v_templates)))), None, None, M.UnitExpr)); (M.Function ((Base.nat_show ((Base.list_length (v_locals)))), false, (Base.nat_show ((Base.list_length (v_operations)))), None, None, M.UnitExpr)); (M.Function ((Base.nat_show ((Base.list_length (v_shapes)))), false, s_11, None, None, M.UnitExpr)); (M.Function (s_134, false, (Base.nat_show ((Base.list_length (v_schema)))), None, None, M.UnitExpr))] in
(let v_marked = (Base.list_append (v_metadata) ((Base.list_append ((f_marker_functions (v_templates))) (((M.Function (s_133, false, (Base.nat_show ((Base.list_length (v_affected)))), None, None, M.UnitExpr)) :: (Base.list_append ((f_marker_functions (v_affected))) ((f_shape_functions (v_shapes))))))))) in
(M.Module ((Base.list_append ((f_local_constants (v_locals))) (v_constants)), (Base.list_append (v_marked) ((Base.list_append ((f_unplanned_functions (v_originals) ((D.f_node_names (v_nodes))))) ((f_schema_source_functions (v_schema)))))), v_types, (Base.list_append (v_operations) (v_family_templates)))))))
and (* monomorph.bend:4004 *)
f_function_source_keys : (M.t_Module -> (M.t_Diagnostic, (int32) list) Base.result_) -> (M.t_Function) list -> ((int32) list) Base.map -> (M.t_Diagnostic, ((int32) list) Base.map) Base.result_ =
fun v_key v_functions v_acc ->
(match v_functions with
| [] ->
(Done (v_acc))
| (v_function :: v_rest) ->
(let (M.Function (v_name, v_exported, v_parameter, v_input, v_output, v_body)) = v_function in
(match (v_key ((M.Module ([], [v_function], [], [])))) with
| Fail __error -> Fail __error
| Done v_words ->
(f_function_source_keys (v_key) (v_rest) ((Base.map_set (v_acc) (v_name) (v_words)))))))
and (* monomorph.bend:4014 *)
f_constant_source_keys : (M.t_Module -> (M.t_Diagnostic, (int32) list) Base.result_) -> (M.t_Constant) list -> ((int32) list) Base.map -> (M.t_Diagnostic, ((int32) list) Base.map) Base.result_ =
fun v_key v_constants v_acc ->
(match v_constants with
| [] ->
(Done (v_acc))
| (v_constant :: v_rest) ->
(let (M.Constant (v_name, v_exported, v_annotation, v_value)) = v_constant in
(match (v_key ((M.Module ([v_constant], [], [], [])))) with
| Fail __error -> Fail __error
| Done v_words ->
(f_constant_source_keys (v_key) (v_rest) ((Base.map_set (v_acc) (v_name) (v_words)))))))
and (* monomorph.bend:4024 *)
f_source_keys : (M.t_Module -> (M.t_Diagnostic, (int32) list) Base.result_) -> (M.t_Function) list -> (M.t_Constant) list -> (M.t_Diagnostic, ((int32) list) Base.map) Base.result_ =
fun v_key v_functions v_constants ->
(match (f_function_source_keys (v_key) (v_functions) ((Base.map_new ()))) with
| Fail __error -> Fail __error
| Done v_functions_keyed ->
(f_constant_source_keys (v_key) (v_constants) (v_functions_keyed)))
and (* monomorph.bend:4029 *)
f_with_step : t_Configuration -> int -> t_Configuration =
fun v_configuration v_step ->
(let (Configuration (v_originals, v_templates, v_entry, v_locals, v_affected, v_stride, v_constant_values, v_family_templates, v_previous, v_schema)) = v_configuration in
(Configuration (v_originals, v_templates, v_entry, v_locals, v_affected, v_stride, v_constant_values, v_family_templates, v_step, v_schema)))
and (* monomorph.bend:4033 *)
f_declaration_cost : G.t_Declaration -> int =
fun v_declaration ->
(match v_declaration with
| (G.FunctionDeclaration ((M.Function (v_name, v_exported, v_parameter, v_p, v_r, v_body)))) ->
(Scheduler.f_expression_cost (4096) ([(Scheduler.ExpressionCost (v_body))]) (1))
| (G.ConstantDeclaration ((M.Constant (v_name, v_exported, v_annotation, v_value)))) ->
(Scheduler.f_expression_cost (4096) ([(Scheduler.ExpressionCost (v_value))]) (1)))
and (* monomorph.bend:4040 *)
f_specialization_tasks : (G.t_Declaration) list -> int -> ((t_SpecializationTask) Batch.t_Weighted) list =
fun v_declarations v_first ->
(match v_declarations with
| [] ->
[]
| (v_head :: v_tail) ->
((Batch.Weighted ((SpecializationTask (v_head, v_first)), (f_declaration_cost (v_head)))) :: (f_specialization_tasks (v_tail) ((Base.nat_add 1 v_first)))))
and (* monomorph.bend:4047 *)
f_specialize_task : t_SpecializationTask -> t_SpecializationContext -> (M.t_Diagnostic, t_ExpandedModule) Base.result_ =
fun v_task v_context ->
(let (SpecializationTask (v_declaration, v_first)) = v_task in
(let (SpecializationContext (v_configuration, v_shapes, v_types, v_operations, v_schemes, v_limit)) = v_context in
(match (f_expand_declaration (v_declaration) (v_configuration) (v_types) (v_operations) (v_first)) with
| Fail __error -> Fail __error
| Done v_expanded ->
(f_infer_expansion_at (v_expanded) (v_configuration) (v_shapes) (true) (v_schemes) (v_limit)))))
and (* monomorph.bend:4054 *)
f_run_task : t_TaskRun -> t_SpecializationContext -> (M.t_Diagnostic, t_ExpandedModule) Base.result_ =
fun v_task v_context ->
(match v_task with
| (ReusedTask ((CachedTask (v_position, v_name, v_dependencies, v_result)))) ->
(Done (v_result))
| (NewTask (v_pending, v_dependencies)) ->
(f_specialize_task (v_pending) (v_context)))
and (* monomorph.bend:4061 *)
f_reuse_match : bool -> t_CachedTask -> t_SpecializationTask -> t_TaskRun =
fun v_equal v_entry v_task ->
(match v_equal with
| true ->
(ReusedTask (v_entry))
| false ->
(NewTask (v_task, [])))
and (* monomorph.bend:4068 *)
f_same_source : ((int32) list) option -> ((int32) list) option -> bool =
fun v_old v_current ->
(match (v_old, v_current) with
| ((Some (v_prior)), (Some (v_now))) ->
(f_same_words (v_prior) (v_now))
| (_, _) ->
false)
and (* monomorph.bend:4075 *)
f_same_dependencies : (Base.text) list -> ((int32) list) Base.map -> ((int32) list) Base.map -> bool -> bool =
fun v_names v_old v_current v_equal ->
(match (v_names, v_equal) with
| (_, false) ->
false
| ([], true) ->
true
| ((v_name :: v_rest), true) ->
(f_same_dependencies (v_rest) (v_old) (v_current) ((f_same_source ((Index.f_find (v_old) (v_name))) ((Index.f_find (v_current) (v_name)))))))
and (* monomorph.bend:4084 *)
f_reuse_task : (t_CachedTask) option -> G.t_Declaration -> int -> ((int32) list) Base.map -> ((int32) list) Base.map -> t_TaskRun =
fun v_candidate v_declaration v_position v_old v_current ->
(match v_candidate with
| None ->
(NewTask ((SpecializationTask (v_declaration, v_position)), []))
| (Some (v_entry)) ->
(let (CachedTask (v_at, v_name, v_dependencies, v_result)) = v_entry in
(let v_root = (G.f_declaration_name (v_declaration)) in
(f_reuse_match ((Base.bool_and ((M.f_name_equal (v_name) (v_root))) ((f_same_dependencies ((v_root :: v_dependencies)) (v_old) (v_current) (true))))) (v_entry) ((SpecializationTask (v_declaration, v_position)))))))
and (* monomorph.bend:4093 *)
f_cached_tasks : (G.t_Declaration) list -> (t_CachedTask) Base.map -> ((int32) list) Base.map -> ((int32) list) Base.map -> int -> ((t_TaskRun) Batch.t_Weighted) list =
fun v_declarations v_previous v_old v_current v_position ->
(match v_declarations with
| [] ->
[]
| (v_declaration :: v_tail) ->
(let v_run = (f_reuse_task ((Index.f_find (v_previous) ((Base.nat_show (v_position))))) (v_declaration) (v_position) (v_old) (v_current)) in
(let v_cost = (f_declaration_cost (v_declaration)) in
((Batch.Weighted (v_run, v_cost)) :: (f_cached_tasks (v_tail) (v_previous) (v_old) (v_current) ((Base.nat_add 1 v_position)))))))
and (* monomorph.bend:4102 *)
f_expanded_function_roots : (M.t_Function) list -> (Base.text) list =
fun v_functions ->
(match v_functions with
| [] ->
[]
| ((M.Function (v_name, v_exported, v_parameter, v_p, v_r, v_body)) :: v_tail) ->
((f_original_name (v_name)) :: (f_expanded_function_roots (v_tail))))
and (* monomorph.bend:4109 *)
f_task_dependencies : G.t_Declaration -> t_ExpandedModule -> (D.t_Node) list -> (M.t_Diagnostic, (Base.text) list) Base.result_ =
fun v_declaration v_expanded v_nodes ->
(let (ExpandedModule ((M.Module (v_constants, v_functions, v_types, v_operations)), v_next, v_bindings, v_certificates)) = v_expanded in
(let v_roots = ((G.f_declaration_name (v_declaration)) :: (f_expanded_function_roots (v_functions))) in
(match (D.f_reachable ((Base.nat_add ((Base.list_length (v_roots))) ((Base.nat_add ((D.f_edge_count (v_nodes))) (1))))) (v_roots) ((D.f_adjacency (v_nodes) (MTip))) ((Base.set_from_list ((D.f_node_names (v_nodes))))) ((Base.set_new ())) ([])) with
| Fail __error -> Fail __error
| Done v_reached ->
(Done ((D.f_reached_members (v_reached)))))))
and (* monomorph.bend:4116 *)
f_dependent_entry : (M.t_Diagnostic, (Base.text) list) Base.result_ -> G.t_Declaration -> int -> t_ExpandedModule -> (t_CachedTask) option =
fun v_dependencies v_declaration v_position v_expanded ->
(match v_dependencies with
| (Fail (v_diagnostic)) ->
None
| (Done (v_names)) ->
(Some ((CachedTask (v_position, (G.f_declaration_name (v_declaration)), v_names, v_expanded)))))
and (* monomorph.bend:4123 *)
f_task_entry : t_TaskRun -> t_ExpandedModule -> (D.t_Node) list -> (t_CachedTask) option =
fun v_run v_expanded v_nodes ->
(match v_run with
| (ReusedTask (v_entry)) ->
(Some (v_entry))
| (NewTask ((SpecializationTask (v_declaration, v_position)), v_unused)) ->
(f_dependent_entry ((f_task_dependencies (v_declaration) (v_expanded) (v_nodes))) (v_declaration) (v_position) (v_expanded)))
and (* monomorph.bend:4130 *)
f_append_entry : (t_CachedTask) option -> (t_CachedTask) list -> (t_CachedTask) list =
fun v_entry v_rest ->
(match v_entry with
| None ->
v_rest
| (Some (v_value)) ->
(v_value :: v_rest))
and (* monomorph.bend:4137 *)
f_combine_cached : t_ExpandedModule -> t_CachedExpansion -> t_TaskRun -> (D.t_Node) list -> t_CachedExpansion =
fun v_first v_next v_run v_nodes ->
(let (CachedExpansion (v_remaining, v_entries)) = v_next in
(CachedExpansion ((f_combine_expansions (v_first) (v_remaining)), (f_append_entry ((f_task_entry (v_run) (v_first) (v_nodes))) (v_entries)))))
and (* monomorph.bend:4141 *)
f_collect_cached : ((t_TaskRun) Batch.t_Weighted) list -> ((M.t_Diagnostic, t_ExpandedModule) Base.result_) list -> (D.t_Node) list -> (M.t_DataType) list -> (M.t_Operation) list -> int -> (M.t_Diagnostic, t_CachedExpansion) Base.result_ =
fun v_runs v_outcomes v_nodes v_types v_operations v_counter ->
(match (v_runs, v_outcomes) with
| ([], []) ->
(Done ((CachedExpansion ((ExpandedModule ((M.Module ([], [], v_types, v_operations)), v_counter, [], [])), []))))
| (((Batch.Weighted (v_run, v_cost)) :: v_following), (v_outcome :: v_tail)) ->
(match v_outcome with
| Fail __error -> Fail __error
| Done v_first ->
(match (f_collect_cached (v_following) (v_tail) (v_nodes) (v_types) (v_operations) (v_counter)) with
| Fail __error -> Fail __error
| Done v_next ->
(Done ((f_combine_cached (v_first) (v_next) (v_run) (v_nodes))))))
| (_, _) ->
(Fail ((M.Diagnostic (s_0, s_1, s_135)))))
and (* monomorph.bend:4156 *)
f_kept_accessor : bool -> M.t_Function -> (M.t_Function) list -> (M.t_Function) list =
fun v_duplicate v_function v_reversed ->
(match v_duplicate with
| true ->
v_reversed
| false ->
(v_function :: v_reversed))
and (* monomorph.bend:4163 *)
f_distinct_accessors_work : (M.t_Function) list -> Base.set -> (M.t_Function) list -> (M.t_Function) list =
fun v_functions v_seen v_reversed ->
(match v_functions with
| [] ->
(Base.list_reverse (v_reversed))
| (v_function :: v_tail) ->
(let (M.Function (v_name, v_exported, v_parameter, v_p, v_r, v_body)) = v_function in
(f_distinct_accessors_work (v_tail) ((Base.set_add (v_seen) (v_name))) ((f_kept_accessor ((Base.bool_and ((Base.string_starts_with (v_name) (s_136))) ((D.f_member (v_seen) (v_name))))) (v_function) (v_reversed))))))
and (* monomorph.bend:4171 *)
f_distinct_accessors : (M.t_Function) list -> (M.t_Function) list =
fun v_functions ->
(f_distinct_accessors_work (v_functions) ((Base.set_new ())) ([]))
and (* monomorph.bend:4174 *)
f_distinct_expansion : t_ExpandedModule -> t_ExpandedModule =
fun v_expanded ->
(let (ExpandedModule ((M.Module (v_constants, v_functions, v_types, v_operations)), v_next, v_bindings, v_certificates)) = v_expanded in
(ExpandedModule ((M.Module (v_constants, (f_distinct_accessors (v_functions)), v_types, v_operations)), v_next, v_bindings, v_certificates)))
and (* monomorph.bend:4178 *)
f_distinct_cached : t_CachedExpansion -> t_CachedExpansion =
fun v_compiled ->
(let (CachedExpansion (v_value, v_tasks)) = v_compiled in
(CachedExpansion ((f_distinct_expansion (v_value)), v_tasks)))
and (* monomorph.bend:4182 *)
f_specialize_declarations_cached : (G.t_Declaration) list -> t_Configuration -> (I.t_Binding) list -> (M.t_DataType) list -> (M.t_Operation) list -> int -> (D.t_Node) list -> (t_CachedTask) list -> ((int32) list) Base.map -> ((int32) list) Base.map -> (M.t_Diagnostic, t_CachedExpansion) Base.result_ =
fun v_declarations v_configuration v_shapes v_types v_operations v_counter v_nodes v_previous v_old v_current ->
(let v_width = (Base.nat_max (1) ((Base.list_length (v_declarations)))) in
(let v_stepped = (f_with_step (v_configuration) (v_width)) in
(let v_runs = (f_cached_tasks (v_declarations) ((f_task_index (v_previous) ((Base.map_new ())))) (v_old) (v_current) (v_counter)) in
(let v_context = (SpecializationContext (v_stepped, v_shapes, v_types, v_operations, [], (f_shape_limit (v_shapes) (0)))) in
(let v_outcomes = (Batch.f_execute (f_run_task) ((Batch.f_plan (v_runs) (2048))) (v_context)) in
(match (f_collect_cached (v_runs) (v_outcomes) (v_nodes) (v_types) (v_operations) (v_counter)) with
| Fail __error -> Fail __error
| Done v_collected ->
(Done ((f_distinct_cached (v_collected))))))))))
and (* monomorph.bend:4192 *)
f_collect_specializations : ((M.t_Diagnostic, t_ExpandedModule) Base.result_) list -> (M.t_DataType) list -> (M.t_Operation) list -> int -> (M.t_Diagnostic, t_ExpandedModule) Base.result_ =
fun v_outcomes v_types v_operations v_counter ->
(match v_outcomes with
| [] ->
(Done ((ExpandedModule ((M.Module ([], [], v_types, v_operations)), v_counter, [], []))))
| (v_head :: v_tail) ->
(match v_head with
| Fail __error -> Fail __error
| Done v_first ->
(match (f_collect_specializations (v_tail) (v_types) (v_operations) (v_counter)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done ((f_combine_expansions (v_first) (v_rest)))))))
and (* monomorph.bend:4204 *)
f_specialize_declarations : (G.t_Declaration) list -> t_Configuration -> (I.t_Binding) list -> (M.t_DataType) list -> (M.t_Operation) list -> int -> (Staging.t_Scheme) list -> (M.t_Diagnostic, t_ExpandedModule) Base.result_ =
fun v_declarations v_configuration v_shapes v_types v_operations v_counter v_schemes ->
(let v_width = (Base.nat_max (1) ((Base.list_length (v_declarations)))) in
(let v_tasks = (f_specialization_tasks (v_declarations) (v_counter)) in
(let v_context = (SpecializationContext ((f_with_step (v_configuration) (v_width)), v_shapes, v_types, v_operations, v_schemes, (f_shape_limit (v_shapes) (0)))) in
(let v_outcomes = (Batch.f_execute (f_specialize_task) ((Batch.f_plan (v_tasks) (2048))) (v_context)) in
(match (f_collect_specializations (v_outcomes) (v_types) (v_operations) (v_counter)) with
| Fail __error -> Fail __error
| Done v_collected ->
(Done ((f_distinct_expansion (v_collected)))))))))
and (* monomorph.bend:4213 *)
f_stale_interfaces : (M.t_Function) list -> (Base.text) list -> (I.t_Binding) Base.map -> (I.t_Binding) Base.map -> (M.t_Function) list =
fun v_functions v_affected v_computed v_shapes ->
(match v_functions with
| [] ->
[]
| (v_function :: v_tail) ->
(let (M.Function (v_name, v_exported, v_parameter, v_input, v_output, v_body)) = v_function in
(let v_rest = (f_stale_interfaces (v_tail) (v_affected) (v_computed) (v_shapes)) in
(Base.bool_pick ((Base.bool_or ((D.f_contains (v_affected) (v_name))) ((Base.bool_and ((Base.bool_not ((Base.maybe_is_some ((Index.f_find (v_shapes) (v_name))))))) ((Base.bool_not ((Base.maybe_is_some ((Index.f_find (v_computed) (v_name))))))))))) ((v_function :: v_rest)) (v_rest)))))
and (* monomorph.bend:4222 *)
f_stale_constants : (M.t_Constant) list -> (Base.text) list -> (I.t_Binding) Base.map -> (I.t_Binding) Base.map -> (M.t_Constant) list =
fun v_constants v_affected v_computed v_shapes ->
(match v_constants with
| [] ->
[]
| (v_constant :: v_tail) ->
(let (M.Constant (v_name, v_exported, v_annotation, v_value)) = v_constant in
(let v_rest = (f_stale_constants (v_tail) (v_affected) (v_computed) (v_shapes)) in
(Base.bool_pick ((Base.bool_or ((D.f_contains (v_affected) (v_name))) ((Base.bool_and ((Base.bool_not ((Base.maybe_is_some ((Index.f_find (v_shapes) (v_name))))))) ((Base.bool_not ((Base.maybe_is_some ((Index.f_find (v_computed) (v_name))))))))))) ((v_constant :: v_rest)) (v_rest)))))
and (* monomorph.bend:4231 *)
f_uncomputed_bindings : (I.t_Binding) list -> (I.t_Binding) Base.map -> (I.t_Binding) list =
fun v_shapes v_computed ->
(match v_shapes with
| [] ->
[]
| ((I.Binding (v_name, v_ty, v_variables, v_predicates)) :: v_tail) ->
(let v_rest = (f_uncomputed_bindings (v_tail) (v_computed)) in
(Base.bool_pick ((Base.maybe_is_some ((Index.f_find (v_computed) (v_name))))) (v_rest) (((I.Binding (v_name, v_ty, v_variables, v_predicates)) :: v_rest)))))
and (* monomorph.bend:4239 *)
f_refreshed_exports : t_ExpandedModule -> M.t_Module -> (I.t_Binding) list -> (M.t_Diagnostic, M.t_Module) Base.result_ =
fun v_refreshed v_module v_bindings ->
(let (ExpandedModule (v_refreshed_module, v_next, v_interfaces, v_certificates)) = v_refreshed in
(Public.f_select (v_module) ((Base.list_append (v_bindings) (v_interfaces))) (Public.Resolved)))
and (* monomorph.bend:4246 *)
f_refresh_interfaces : (M.t_Function) list -> (M.t_Constant) list -> M.t_Module -> (I.t_Binding) list -> t_Configuration -> (I.t_Binding) list -> int -> (M.t_Diagnostic, M.t_Module) Base.result_ =
fun v_pending_functions v_pending_constants v_module v_bindings v_configuration v_shapes v_counter ->
(match (v_pending_functions, v_pending_constants) with
| ([], []) ->
(Public.f_select (v_module) ((Base.list_append (v_shapes) (v_bindings))) (Public.Resolved))
| (v_fs, v_cs) ->
(let (M.Module (v_constants, v_functions, v_types, v_operations)) = v_module in
(let (Configuration (v_originals, v_templates, v_entry, v_locals, v_affected, v_stride, v_constant_values, v_family_templates, v_step, v_schema)) = v_configuration in
(let v_scope = (Configuration ((Base.list_append (v_originals) (v_functions)), v_templates, v_entry, v_locals, v_affected, v_stride, v_constant_values, v_family_templates, v_step, v_schema)) in
(let v_completed = (f_ordinary_bindings (v_bindings) ((G.f_names ((Base.list_append ((G.f_function_declarations (v_fs))) ((G.f_constant_declarations (v_cs)))))))) in
(let v_known = (Base.list_append (v_completed) ((f_uncomputed_bindings (v_shapes) ((Public.f_binding_index (v_completed) (MTip)))))) in
(match (f_infer_required ((ExpandedModule ((M.Module (v_cs, v_fs, v_types, v_operations)), v_counter, [], []))) (v_scope) (v_known) (true)) with
| Fail __error -> Fail __error
| Done v_checked ->
(f_refreshed_exports (v_checked) ((M.Module (v_constants, v_functions, v_types, v_operations))) ((Base.list_append (v_shapes) (v_bindings)))))))))))
and (* monomorph.bend:4260 *)
f_public_expansion : t_ExpandedModule -> (I.t_Binding) list -> t_Configuration -> (M.t_Diagnostic, M.t_Module) Base.result_ =
fun v_expanded v_shapes v_configuration ->
(let (ExpandedModule (v_module, v_counter, v_bindings, v_certificates)) = v_expanded in
(let (M.Module (v_constants, v_functions, v_types, v_operations)) = v_module in
(let (Configuration (v_originals, v_templates, v_entry, v_locals, v_affected, v_stride, v_constant_values, v_family_templates, v_step, v_schema)) = v_configuration in
(let v_computed = (Public.f_binding_index (v_bindings) (MTip)) in
(let v_known = (Public.f_binding_index (v_shapes) (MTip)) in
(f_refresh_interfaces ((f_stale_interfaces (v_functions) (v_affected) (v_computed) (v_known))) ((f_stale_constants (v_constants) (v_affected) (v_computed) (v_known))) (v_module) (v_bindings) (v_configuration) (v_shapes) (v_counter)))))))
and (* monomorph.bend:4268 *)
f_specialize : bool -> (M.t_Function) list -> (M.t_Constant) list -> (M.t_DataType) list -> (M.t_Operation) list -> t_Configuration -> (I.t_Binding) list -> int -> (M.t_Diagnostic, M.t_Module) Base.result_ =
fun v_independent v_originals v_constants v_types v_operations v_configuration v_shapes v_counter ->
(match v_independent with
| true ->
(match (f_specialize_declarations ((Base.list_append ((G.f_function_declarations (v_originals))) ((G.f_constant_declarations (v_constants))))) (v_configuration) (v_shapes) (v_types) (v_operations) (v_counter) ([])) with
| Fail __error -> Fail __error
| Done v_compiled ->
(f_public_expansion (v_compiled) (v_shapes) (v_configuration)))
| false ->
(match (f_expand_roots (v_originals) (v_configuration) (v_counter)) with
| Fail __error -> Fail __error
| Done v_roots ->
(match (f_expand_constants (v_constants) (v_configuration) ((f_functions (v_roots))) ((f_emitted_constants (v_roots))) (v_types) (v_operations) ((f_next (v_roots)))) with
| Fail __error -> Fail __error
| Done v_expanded ->
(match (f_infer_expansion (v_expanded) (v_configuration) (v_shapes) (false)) with
| Fail __error -> Fail __error
| Done v_compiled ->
(f_public_expansion (v_compiled) (v_shapes) (v_configuration))))))
and (* monomorph.bend:4284 *)
f_unshared_names : (Base.text) list -> (Base.text) list -> (Base.text) list =
fun v_pending v_shared ->
(match v_pending with
| [] ->
[]
| (v_head :: v_tail) ->
(let v_rest = (f_unshared_names (v_tail) (v_shared)) in
(Base.bool_pick ((D.f_contains (v_shared) (v_head))) (v_rest) ((v_head :: v_rest)))))
and (* monomorph.bend:4292 *)
f_append_constant : (M.t_Constant) option -> (M.t_Constant) list -> (M.t_Constant) list =
fun v_found v_rest ->
(match v_found with
| None ->
v_rest
| (Some (v_constant)) ->
(v_constant :: v_rest))
and (* monomorph.bend:4299 *)
f_named_constants : (Base.text) list -> (M.t_Constant) list -> (M.t_Constant) list =
fun v_names v_constants ->
(match v_names with
| [] ->
[]
| (v_head :: v_tail) ->
(f_append_constant ((f_lookup_constant (v_constants) (v_head))) ((f_named_constants (v_tail) (v_constants)))))
and (* monomorph.bend:4306 *)
f_ordered_constants : ((Base.text) list) list -> (M.t_Constant) list -> (M.t_Constant) list =
fun v_groups v_constants ->
(match v_groups with
| [] ->
[]
| (v_head :: v_tail) ->
(Base.list_append ((f_named_constants (v_head) (v_constants))) ((f_ordered_constants (v_tail) (v_constants)))))
and (* monomorph.bend:4313 *)
f_unreplaced_constants : (M.t_Constant) list -> (M.t_Constant) list -> (M.t_Constant) list =
fun v_constants v_replacements ->
(match v_constants with
| [] ->
[]
| (v_constant :: v_tail) ->
(let (M.Constant (v_name, v_exported, v_annotation, v_value)) = v_constant in
(let v_rest = (f_unreplaced_constants (v_tail) (v_replacements)) in
(Base.bool_pick ((Base.maybe_is_some ((f_lookup_constant (v_replacements) (v_name))))) (v_rest) ((v_constant :: v_rest))))))
and (* monomorph.bend:4322 *)
f_deferred_constant : bool -> M.t_Diagnostic -> t_SharedConstants -> (M.t_Diagnostic, t_SharedConstants) Base.result_ =
fun v_ambiguous v_error v_previous ->
(match v_ambiguous with
| true ->
(Done (v_previous))
| false ->
(Fail (v_error)))
and (* monomorph.bend:4329 *)
f_accept_constant : (M.t_Diagnostic, t_ExpandedModule) Base.result_ -> Base.text -> t_SharedConstants -> (M.t_Diagnostic, t_SharedConstants) Base.result_ =
fun v_compiled v_name v_previous ->
(match (v_compiled, v_previous) with
| ((Fail (v_error)), v_previous) ->
(let (M.Diagnostic (v_code, v_subject, v_message)) = v_error in
(f_deferred_constant ((Base.bool_or ((M.f_name_equal (v_code) (s_42))) ((M.f_name_equal (v_code) (s_86))))) (v_error) (v_previous)))
| ((Done ((ExpandedModule ((M.Module (v_compiled_constants, v_compiled_functions, v_compiled_types, v_compiled_operations)), v_counter, v_bindings, v_certificates)))), (SharedConstants ((M.Module (v_constants, v_functions, v_types, v_operations)), v_shapes, v_shared, v_next, v_prior_certificates))) ->
(let v_module = (M.Module ((Base.list_append ((f_unreplaced_constants (v_constants) (v_compiled_constants))) (v_compiled_constants)), (Base.list_append (v_functions) (v_compiled_functions)), v_types, (State.f_merge (v_compiled_operations) (v_operations)))) in
(let v_members = (G.f_names ((Base.list_append ((G.f_function_declarations (v_compiled_functions))) ((G.f_constant_declarations (v_compiled_constants)))))) in
(Done ((SharedConstants (v_module, (Base.list_append (v_bindings) ((f_ordinary_bindings (v_shapes) (v_members)))), (v_name :: v_shared), v_counter, (Base.list_append (v_prior_certificates) (v_certificates)))))))))
and (* monomorph.bend:4342 *)
f_share_constant : M.t_Constant -> t_SharedConstants -> (Base.text) list -> Base.text -> int -> (M.t_Operation) list -> (Staging.t_Scheme) list -> (Schema.t_Evidence) list -> (M.t_Diagnostic, t_SharedConstants) Base.result_ =
fun v_constant v_previous v_templates v_entry v_stride v_family_templates v_schemes v_schema ->
(let (M.Constant (v_name, v_exported, v_annotation, v_value)) = v_constant in
(let (SharedConstants ((M.Module (v_constants, v_functions, v_types, v_operations)), v_shapes, v_shared, v_counter, v_certificates)) = v_previous in
(let v_affected = (f_unshared_names (v_templates) (v_shared)) in
(let v_aliases = (f_constant_templates (v_constants) (v_affected)) in
(let v_generic = (f_generic_templates (v_shapes) (v_affected)) in
(let v_configuration = (Configuration (v_functions, v_generic, v_entry, v_aliases, v_affected, v_stride, (f_specialized_constants (v_constants) (v_generic) (v_shapes)), v_family_templates, 1, v_schema)) in
(match (f_expand_declaration ((G.ConstantDeclaration (v_constant))) (v_configuration) (v_types) (v_operations) (v_counter)) with
| Fail __error -> Fail __error
| Done v_expanded ->
(f_accept_constant ((f_infer_required_optional (v_expanded) (v_configuration) (v_shapes) (true) (v_schemes))) (v_name) (v_previous)))))))))
and (* monomorph.bend:4353 *)
f_share_constants : (M.t_Constant) list -> t_SharedConstants -> (Base.text) list -> Base.text -> int -> (M.t_Operation) list -> (Staging.t_Scheme) list -> (Schema.t_Evidence) list -> (M.t_Diagnostic, t_SharedConstants) Base.result_ =
fun v_constants v_previous v_templates v_entry v_stride v_family_templates v_schemes v_schema ->
(match v_constants with
| [] ->
(Done (v_previous))
| (v_head :: v_tail) ->
(match (f_share_constant (v_head) (v_previous) (v_templates) (v_entry) (v_stride) (v_family_templates) (v_schemes) (v_schema)) with
| Fail __error -> Fail __error
| Done v_next ->
(f_share_constants (v_tail) (v_next) (v_templates) (v_entry) (v_stride) (v_family_templates) (v_schemes) (v_schema))))
and (* monomorph.bend:4362 *)
f_prepare_shared : (Base.text) list -> t_SharedConstants -> Base.text -> int -> (M.t_Operation) list -> (M.t_Diagnostic, M.t_Module) Base.result_ =
fun v_templates v_prepared v_entry v_stride v_family_templates ->
(let (SharedConstants ((M.Module (v_constants, v_functions, v_types, v_operations)), v_shapes, v_shared, v_counter, v_certificates)) = v_prepared in
(let v_affected = (f_unshared_names (v_templates) (v_shared)) in
(let v_aliases = (f_constant_templates (v_constants) (v_affected)) in
(let v_generic = (f_generic_templates (v_shapes) (v_affected)) in
(let v_constant_values = (f_specialized_constants (v_constants) (v_generic) (v_shapes)) in
(let v_configuration = (Configuration (v_functions, v_generic, v_entry, v_aliases, v_affected, v_stride, v_constant_values, v_family_templates, 1, [])) in
(let v_retained = (f_retained_specializations ((f_retained_constants (v_constants) (v_aliases))) (v_constant_values)) in
(f_specialize ((f_independent_constants (v_retained) (v_affected) (v_shapes))) (v_functions) (v_retained) (v_types) (v_operations) (v_configuration) (v_shapes) (v_counter)))))))))
and (* monomorph.bend:4372 *)
f_prepare_templates : (Base.text) list -> M.t_Module -> (I.t_Binding) list -> Base.text -> (M.t_Operation) list -> (M.t_Diagnostic, M.t_Module) Base.result_ =
fun v_templates v_module v_shapes v_entry v_family_templates ->
(match v_templates with
| [] ->
(Public.f_select (v_module) (v_shapes) (Public.Resolved))
| (v_head :: v_tail) ->
(let (M.Module (v_constants, v_original_functions, v_types, v_operations)) = v_module in
(match (f_identity_limit ((Base.u32_to_nat (0x00100000l))) ((f_module_expressions (v_original_functions) (v_constants))) (0)) with
| Fail __error -> Fail __error
| Done v_stride ->
(let v_generic = (f_generic_templates (v_shapes) ((v_head :: v_tail))) in
(let v_candidates = (f_specialized_constants (v_constants) (v_generic) (v_shapes)) in
(match (Check.f_module_graph (v_module)) with
| Fail __error -> Fail __error
| Done v_nodes ->
(match (D.f_components (v_nodes)) with
| Fail __error -> Fail __error
| Done v_groups ->
(match (f_share_constants ((f_ordered_constants (v_groups) (v_candidates))) ((SharedConstants (v_module, v_shapes, [], 1, []))) ((v_head :: v_tail)) (v_entry) (v_stride) (v_family_templates) ([]) ([])) with
| Fail __error -> Fail __error
| Done v_shared ->
(f_prepare_shared ((v_head :: v_tail)) (v_shared) (v_entry) (v_stride) (v_family_templates))))))))))
and (* monomorph.bend:4387 *)
f_concrete_module : M.t_Module -> M.t_Module =
fun v_module ->
(let (M.Module (v_constants, v_functions, v_types, v_operations)) = v_module in
(M.Module (v_constants, v_functions, v_types, (State.f_concrete (v_operations)))))
and (* monomorph.bend:4391 *)
f_module_templates : M.t_Module -> (D.t_Node) list -> Scheduler.t_Initial -> (Base.text) list =
fun v_module v_nodes v_initial ->
(let (M.Module (v_constants, v_functions, v_types, v_operations)) = v_module in
(f_template_closure (v_nodes) ((Base.list_append ((f_certificate_plan_roots ((Scheduler.f_initial_certificates (v_initial))))) ((Base.list_append ((f_seeds (v_functions))) ((f_constant_seeds (v_constants)))))))))
and (* monomorph.bend:4395 *)
f_prepare_shaped : M.t_Module -> Base.text -> (M.t_Operation) list -> (D.t_Node) list -> Scheduler.t_Initial -> (M.t_Diagnostic, M.t_Module) Base.result_ =
fun v_module v_entry v_family_templates v_nodes v_initial ->
(match (f_shape_initial (v_initial) (v_module)) with
| Fail __error -> Fail __error
| Done v_shape ->
(match (f_resolved_bindings ((G.f_env_bindings (v_shape))) ((I.f_substitutions_of ((G.f_env_state (v_shape)))))) with
| Fail __error -> Fail __error
| Done v_shapes ->
(match (Public.f_select (v_module) (v_shapes) (Public.Candidates)) with
| Fail __error -> Fail __error
| Done v_selected ->
(match (f_prepare_templates ((f_module_templates (v_module) (v_nodes) (v_initial))) (v_selected) (v_shapes) (v_entry) (v_family_templates)) with
| Fail __error -> Fail __error
| Done v_prepared ->
(Done ((f_concrete_module (v_prepared))))))))
and (* monomorph.bend:4405 *)
f_prepare : M.t_Module -> Base.text -> (M.t_Operation) list -> (M.t_Diagnostic, M.t_Module) Base.result_ =
fun v_module v_entry v_family_templates ->
(match (Scheduler.f_check_module_evidenced (v_module)) with
| Fail __error -> Fail __error
| Done v_initial ->
(match (Entries.f_prune_initial (v_module) (v_initial) (v_entry)) with
| Fail __error -> Fail __error
| Done v_pruned ->
(match (Check.f_module_graph ((Entries.f_pruned_module (v_pruned)))) with
| Fail __error -> Fail __error
| Done v_nodes ->
(f_prepare_shaped ((Entries.f_pruned_module (v_pruned))) (v_entry) (v_family_templates) (v_nodes) ((Entries.f_pruned_initial (v_pruned)))))))
and (* monomorph.bend:4413 *)
f_prepare_checked : M.t_Module -> Base.text -> (M.t_Operation) list -> Scheduler.t_Initial -> (M.t_Diagnostic, M.t_Module) Base.result_ =
fun v_module v_entry v_family_templates v_initial ->
(match (Check.f_module_graph (v_module)) with
| Fail __error -> Fail __error
| Done v_nodes ->
(f_prepare_shaped (v_module) (v_entry) (v_family_templates) (v_nodes) (v_initial)))
and (* monomorph.bend:4421 *)
f_specialize_deferred : bool -> (M.t_Function) list -> (M.t_Constant) list -> (M.t_DataType) list -> (M.t_Operation) list -> t_Configuration -> (I.t_Binding) list -> int -> (Staging.t_Scheme) list -> (M.t_Diagnostic, t_ExpandedModule) Base.result_ =
fun v_independent v_originals v_constants v_types v_operations v_configuration v_shapes v_counter v_schemes ->
(match v_independent with
| true ->
(match (f_specialize_declarations ((Base.list_append ((G.f_function_declarations (v_originals))) ((G.f_constant_declarations (v_constants))))) (v_configuration) (v_shapes) (v_types) (v_operations) (v_counter) (v_schemes)) with
| Fail __error -> Fail __error
| Done v_compiled ->
(Done (v_compiled)))
| false ->
(match (f_expand_roots (v_originals) (v_configuration) (v_counter)) with
| Fail __error -> Fail __error
| Done v_roots ->
(match (f_expand_constants (v_constants) (v_configuration) ((f_functions (v_roots))) ((f_emitted_constants (v_roots))) (v_types) (v_operations) ((f_next (v_roots)))) with
| Fail __error -> Fail __error
| Done v_expanded ->
(match (f_infer_expansion_staged (v_expanded) (v_configuration) (v_shapes) (false) (v_schemes)) with
| Fail __error -> Fail __error
| Done v_compiled ->
(Done (v_compiled))))))
and (* monomorph.bend:4435 *)
f_with_expanded_certificates : t_ExpandedModule -> (Core.t_Certificate) list -> t_ExpandedModule =
fun v_expanded v_prior ->
(let (ExpandedModule (v_module, v_counter, v_bindings, v_certificates)) = v_expanded in
(ExpandedModule (v_module, v_counter, v_bindings, (Base.list_append (v_prior) (v_certificates)))))
and (* monomorph.bend:4439 *)
f_prepare_shared_deferred : (Base.text) list -> t_SharedConstants -> Base.text -> int -> (M.t_Operation) list -> (Staging.t_Scheme) list -> (Schema.t_Evidence) list -> (M.t_Diagnostic, t_ExpandedModule) Base.result_ =
fun v_templates v_prepared v_entry v_stride v_family_templates v_schemes v_schema ->
(let (SharedConstants ((M.Module (v_constants, v_functions, v_types, v_operations)), v_shapes, v_shared, v_counter, v_certificates)) = v_prepared in
(let v_affected = (f_unshared_names (v_templates) (v_shared)) in
(let v_aliases = (f_constant_templates (v_constants) (v_affected)) in
(let v_generic = (f_generic_templates (v_shapes) (v_affected)) in
(let v_constant_values = (f_specialized_constants (v_constants) (v_generic) (v_shapes)) in
(let v_configuration = (Configuration (v_functions, v_generic, v_entry, v_aliases, v_affected, v_stride, v_constant_values, v_family_templates, 1, v_schema)) in
(let v_retained = (f_retained_specializations ((f_retained_constants (v_constants) (v_aliases))) (v_constant_values)) in
(match (f_specialize_deferred ((f_independent_constants (v_retained) (v_affected) (v_shapes))) (v_functions) (v_retained) (v_types) (v_operations) (v_configuration) (v_shapes) (v_counter) (v_schemes)) with
| Fail __error -> Fail __error
| Done v_expanded ->
(Done ((f_with_expanded_certificates (v_expanded) (v_certificates))))))))))))
and (* monomorph.bend:4451 *)
f_prepare_templates_deferred : (Base.text) list -> M.t_Module -> (I.t_Binding) list -> Base.text -> (M.t_Operation) list -> M.t_CheckedModule -> (M.t_Diagnostic, t_ExpandedModule) Base.result_ =
fun v_templates v_module v_shapes v_entry v_family_templates v_checked ->
(match v_templates with
| [] ->
(Done ((ExpandedModule (v_module, 0, [], []))))
| (v_head :: v_tail) ->
(let (M.Module (v_constants, v_original_functions, v_types, v_operations)) = v_module in
(let v_schemes = (Staging.f_capture_closed ((ParallelInfer.f_data_types_closed (v_types))) (v_original_functions) (v_operations) (v_types)) in
(let v_schema = (Schema.f_capture (v_original_functions) (v_types) (v_checked) (v_entry)) in
(match (f_identity_limit ((Base.u32_to_nat (0x00100000l))) ((f_module_expressions (v_original_functions) (v_constants))) (0)) with
| Fail __error -> Fail __error
| Done v_stride ->
(let v_generic = (f_generic_templates (v_shapes) ((v_head :: v_tail))) in
(let v_candidates = (f_specialized_constants (v_constants) (v_generic) (v_shapes)) in
(match (Check.f_module_graph (v_module)) with
| Fail __error -> Fail __error
| Done v_nodes ->
(match (D.f_components (v_nodes)) with
| Fail __error -> Fail __error
| Done v_groups ->
(match (f_share_constants ((f_ordered_constants (v_groups) (v_candidates))) ((SharedConstants (v_module, v_shapes, [], 1, []))) ((v_head :: v_tail)) (v_entry) (v_stride) (v_family_templates) (v_schemes) (v_schema)) with
| Fail __error -> Fail __error
| Done v_shared ->
(f_prepare_shared_deferred ((v_head :: v_tail)) (v_shared) (v_entry) (v_stride) (v_family_templates) (v_schemes) (v_schema))))))))))))
and (* monomorph.bend:4469 *)
f_prepare_initial_templates : (Base.text) list -> M.t_Module -> Base.text -> (M.t_Operation) list -> Scheduler.t_Initial -> (M.t_Diagnostic, Core.t_Prepared) Base.result_ =
fun v_templates v_module v_entry v_family_templates v_initial ->
(match v_templates with
| [] ->
(Done ((Core.Prepared ((f_concrete_module (v_module)), (Core.f_ready_certificates ((Scheduler.f_initial_certificates (v_initial))))))))
| (v_head :: v_tail) ->
(let (Scheduler.Initial (v_checked, v_certificates, v_needs)) = v_initial in
(match (f_shape_initial (v_initial) (v_module)) with
| Fail __error -> Fail __error
| Done v_shape ->
(match (f_resolved_bindings ((G.f_env_bindings (v_shape))) ((I.f_substitutions_of ((G.f_env_state (v_shape)))))) with
| Fail __error -> Fail __error
| Done v_shapes ->
(match (Public.f_select (v_module) (v_shapes) (Public.Candidates)) with
| Fail __error -> Fail __error
| Done v_selected ->
(match (f_prepare_templates_deferred ((v_head :: v_tail)) (v_selected) (v_shapes) (v_entry) (v_family_templates) (v_checked)) with
| Fail __error -> Fail __error
| Done v_prepared ->
(Done ((Core.Prepared ((f_concrete_module ((f_expanded_module (v_prepared)))), (Base.list_append ((Core.f_ready_certificates (v_certificates))) ((f_expanded_certificates (v_prepared))))))))))))))
and (* monomorph.bend:4485 *)
f_prepare_deferred_initial : M.t_Module -> Base.text -> (M.t_Operation) list -> Scheduler.t_Initial -> (M.t_Diagnostic, Core.t_Prepared) Base.result_ =
fun v_module v_entry v_family_templates v_initial ->
(match (Check.f_module_graph (v_module)) with
| Fail __error -> Fail __error
| Done v_nodes ->
(f_prepare_initial_templates ((f_module_templates (v_module) (v_nodes) (v_initial))) (v_module) (v_entry) (v_family_templates) (v_initial)))
and (* monomorph.bend:4493 *)
f_prepare_deferred_core : M.t_Module -> Base.text -> (M.t_Operation) list -> (M.t_Diagnostic, Core.t_Prepared) Base.result_ =
fun v_module v_entry v_family_templates ->
(match (Scheduler.f_check_module_evidenced (v_module)) with
| Fail __error -> Fail __error
| Done v_initial ->
(match (Entries.f_prune_initial (v_module) (v_initial) (v_entry)) with
| Fail __error -> Fail __error
| Done v_pruned ->
(f_prepare_deferred_initial ((Entries.f_pruned_module (v_pruned))) (v_entry) (v_family_templates) ((Entries.f_pruned_initial (v_pruned))))))
and (* monomorph.bend:4499 *)
f_finish_cached : t_CachedExpansion -> (int32) list -> ((int32) list) Base.map -> (I.t_Binding) list -> t_Configuration -> (M.t_Diagnostic, t_Prepared) Base.result_ =
fun v_compiled v_context_key v_sources v_shapes v_configuration ->
(let (CachedExpansion (v_expansion, v_tasks)) = v_compiled in
(let (ExpandedModule (v_expanded, v_next, v_bindings, v_certificates)) = v_expansion in
(match (f_public_expansion (v_expansion) (v_shapes) (v_configuration)) with
| Fail __error -> Fail __error
| Done v_module ->
(Done ((Prepared (v_module, (Cache (v_context_key, v_tasks, v_sources, [])), v_certificates)))))))
and (* monomorph.bend:4506 *)
f_cached_sources : (M.t_Diagnostic, ((int32) list) Base.map) Base.result_ -> (int32) list -> (M.t_Function) list -> (M.t_Constant) list -> (M.t_DataType) list -> (M.t_Operation) list -> t_Configuration -> (I.t_Binding) list -> int -> (D.t_Node) list -> t_Reusable -> (M.t_Diagnostic, t_Prepared) Base.result_ =
fun v_probe v_context_key v_originals v_retained v_types v_operations v_configuration v_shapes v_counter v_nodes v_reusable ->
(match v_probe with
| (Fail (v_diagnostic)) ->
(match (f_specialize (true) (v_originals) (v_retained) (v_types) (v_operations) (v_configuration) (v_shapes) (v_counter)) with
| Fail __error -> Fail __error
| Done v_module ->
(Done ((Prepared (v_module, (f_empty_cache ()), [])))))
| (Done (v_current)) ->
(let (Reusable (v_old_tasks, v_old_sources)) = v_reusable in
(let v_declarations = (Base.list_append ((G.f_function_declarations (v_originals))) ((G.f_constant_declarations (v_retained)))) in
(match (f_specialize_declarations_cached (v_declarations) (v_configuration) (v_shapes) (v_types) (v_operations) (v_counter) (v_nodes) (v_old_tasks) (v_old_sources) (v_current)) with
| Fail __error -> Fail __error
| Done v_compiled ->
(f_finish_cached (v_compiled) (v_context_key) (v_current) (v_shapes) (v_configuration))))))
and (* monomorph.bend:4519 *)
f_cached_context : (M.t_Module -> (M.t_Diagnostic, (int32) list) Base.result_) -> (M.t_Diagnostic, (int32) list) Base.result_ -> (M.t_Function) list -> (M.t_Constant) list -> (M.t_Constant) list -> (M.t_DataType) list -> (M.t_Operation) list -> t_Configuration -> (I.t_Binding) list -> int -> (D.t_Node) list -> (t_Cache) option -> (M.t_Diagnostic, t_Prepared) Base.result_ =
fun v_key v_probe v_originals v_source_constants v_retained v_types v_operations v_configuration v_shapes v_counter v_nodes v_previous ->
(match v_probe with
| (Fail (v_diagnostic)) ->
(match (f_specialize (true) (v_originals) (v_retained) (v_types) (v_operations) (v_configuration) (v_shapes) (v_counter)) with
| Fail __error -> Fail __error
| Done v_module ->
(Done ((Prepared (v_module, (f_empty_cache ()), [])))))
| (Done (v_context_key)) ->
(f_cached_sources ((f_source_keys (v_key) (v_originals) (v_source_constants))) (v_context_key) (v_originals) (v_retained) (v_types) (v_operations) (v_configuration) (v_shapes) (v_counter) (v_nodes) ((f_cache_for_context (v_previous) (v_context_key)))))
and (* monomorph.bend:4528 *)
f_cached_specialize : (M.t_Module -> (M.t_Diagnostic, (int32) list) Base.result_) -> bool -> (M.t_Function) list -> (M.t_Constant) list -> (M.t_Constant) list -> (M.t_DataType) list -> (M.t_Operation) list -> t_Configuration -> (I.t_Binding) list -> int -> (D.t_Node) list -> (t_Cache) option -> (M.t_Diagnostic, t_Prepared) Base.result_ =
fun v_key v_independent v_originals v_source_constants v_retained v_types v_operations v_configuration v_shapes v_counter v_nodes v_previous ->
(match v_independent with
| false ->
(match (f_specialize (false) (v_originals) (v_retained) (v_types) (v_operations) (v_configuration) (v_shapes) (v_counter)) with
| Fail __error -> Fail __error
| Done v_module ->
(Done ((Prepared (v_module, (f_empty_cache ()), [])))))
| true ->
(let v_declarations = (Base.list_append ((G.f_function_declarations (v_originals))) ((G.f_constant_declarations (v_retained)))) in
(let v_context = (SpecializationContext ((f_with_step (v_configuration) ((Base.nat_max (1) ((Base.list_length (v_declarations)))))), v_shapes, v_types, v_operations, [], (Done (0)))) in
(f_cached_context (v_key) ((v_key ((f_context_module (v_context) (v_nodes))))) (v_originals) (v_source_constants) (v_retained) (v_types) (v_operations) (v_configuration) (v_shapes) (v_counter) (v_nodes) (v_previous)))))
and (* monomorph.bend:4539 *)
f_with_prepared_certificates : t_Prepared -> (Core.t_Certificate) list -> t_Prepared =
fun v_prepared v_prior ->
(let (Prepared (v_module, v_cache, v_certificates)) = v_prepared in
(Prepared (v_module, v_cache, (Base.list_append (v_prior) (v_certificates)))))
and (* monomorph.bend:4543 *)
f_prepare_shared_cached : (M.t_Module -> (M.t_Diagnostic, (int32) list) Base.result_) -> (Base.text) list -> t_SharedConstants -> Base.text -> int -> (M.t_Operation) list -> (Schema.t_Evidence) list -> (D.t_Node) list -> (t_Cache) option -> (M.t_Diagnostic, t_Prepared) Base.result_ =
fun v_key v_templates v_prepared v_entry v_stride v_family_templates v_schema v_nodes v_previous ->
(let (SharedConstants ((M.Module (v_constants, v_functions, v_types, v_operations)), v_shapes, v_shared, v_counter, v_certificates)) = v_prepared in
(let v_affected = (f_unshared_names (v_templates) (v_shared)) in
(let v_aliases = (f_constant_templates (v_constants) (v_affected)) in
(let v_generic = (f_generic_templates (v_shapes) (v_affected)) in
(let v_constant_values = (f_specialized_constants (v_constants) (v_generic) (v_shapes)) in
(let v_configuration = (Configuration (v_functions, v_generic, v_entry, v_aliases, v_affected, v_stride, v_constant_values, v_family_templates, 1, v_schema)) in
(let v_retained = (f_retained_specializations ((f_retained_constants (v_constants) (v_aliases))) (v_constant_values)) in
(match (f_cached_specialize (v_key) ((f_independent_constants (v_retained) (v_affected) (v_shapes))) (v_functions) (v_constants) (v_retained) (v_types) (v_operations) (v_configuration) (v_shapes) (v_counter) (v_nodes) (v_previous)) with
| Fail __error -> Fail __error
| Done v_result ->
(Done ((f_with_prepared_certificates (v_result) (v_certificates))))))))))))
and (* monomorph.bend:4555 *)
f_prepare_templates_cached : (M.t_Module -> (M.t_Diagnostic, (int32) list) Base.result_) -> (Base.text) list -> M.t_Module -> (I.t_Binding) list -> Base.text -> (M.t_Operation) list -> (D.t_Node) list -> (t_Cache) option -> M.t_CheckedModule -> (M.t_Diagnostic, t_Prepared) Base.result_ =
fun v_key v_templates v_module v_shapes v_entry v_family_templates v_nodes v_previous v_checked ->
(match v_templates with
| [] ->
(match (Public.f_select (v_module) (v_shapes) (Public.Resolved)) with
| Fail __error -> Fail __error
| Done v_selected ->
(Done ((Prepared (v_selected, (f_empty_cache ()), [])))))
| (v_head :: v_tail) ->
(let (M.Module (v_constants, v_original_functions, v_types, v_operations)) = v_module in
(let v_schema = (Schema.f_capture (v_original_functions) (v_types) (v_checked) (v_entry)) in
(match (f_identity_limit ((Base.u32_to_nat (0x00100000l))) ((f_module_expressions (v_original_functions) (v_constants))) (0)) with
| Fail __error -> Fail __error
| Done v_stride ->
(let v_generic = (f_generic_templates (v_shapes) ((v_head :: v_tail))) in
(let v_candidates = (f_specialized_constants (v_constants) (v_generic) (v_shapes)) in
(match (D.f_components (v_nodes)) with
| Fail __error -> Fail __error
| Done v_groups ->
(match (f_share_constants ((f_ordered_constants (v_groups) (v_candidates))) ((SharedConstants (v_module, v_shapes, [], 1, []))) ((v_head :: v_tail)) (v_entry) (v_stride) (v_family_templates) ([]) (v_schema)) with
| Fail __error -> Fail __error
| Done v_shared ->
(f_prepare_shared_cached (v_key) ((v_head :: v_tail)) (v_shared) (v_entry) (v_stride) (v_family_templates) (v_schema) (v_nodes) (v_previous))))))))))
and (* monomorph.bend:4574 *)
f_concrete_prepared : t_Prepared -> t_Prepared =
fun v_prepared ->
(let (Prepared (v_expanded, v_cache, v_certificates)) = v_prepared in
(Prepared ((f_concrete_module (v_expanded)), v_cache, v_certificates)))
and (* monomorph.bend:4578 *)
f_prepare_cached_nodes : (M.t_Module -> (M.t_Diagnostic, (int32) list) Base.result_) -> M.t_Module -> Base.text -> (M.t_Operation) list -> (D.t_Node) list -> (t_Cache) option -> Scheduler.t_Initial -> (M.t_Diagnostic, t_Prepared) Base.result_ =
fun v_key v_module v_entry v_family_templates v_nodes v_previous v_initial ->
(let (Scheduler.Initial (v_checked, v_certificates, v_needs)) = v_initial in
(match (f_shape_initial (v_initial) (v_module)) with
| Fail __error -> Fail __error
| Done v_shape ->
(match (f_resolved_bindings ((G.f_env_bindings (v_shape))) ((I.f_substitutions_of ((G.f_env_state (v_shape)))))) with
| Fail __error -> Fail __error
| Done v_shapes ->
(match (Public.f_select (v_module) (v_shapes) (Public.Candidates)) with
| Fail __error -> Fail __error
| Done v_selected ->
(match (f_prepare_templates_cached (v_key) ((f_module_templates (v_module) (v_nodes) (v_initial))) (v_selected) (v_shapes) (v_entry) (v_family_templates) (v_nodes) (v_previous) (v_checked)) with
| Fail __error -> Fail __error
| Done v_prepared ->
(Done ((f_with_prepared_certificates ((f_concrete_prepared (v_prepared))) ((Core.f_ready_certificates (v_certificates)))))))))))
and (* monomorph.bend:4587 *)
f_prepare_cached_evidenced : (M.t_Module -> (M.t_Diagnostic, (int32) list) Base.result_) -> M.t_Module -> Base.text -> (M.t_Operation) list -> (t_Cache) option -> (M.t_Diagnostic, t_Prepared) Base.result_ =
fun v_key v_module v_entry v_family_templates v_previous ->
(match (Scheduler.f_check_module_resolving (v_module) ((f_source_certificates (v_previous)))) with
| Fail __error -> Fail __error
| Done v_initial ->
(match (Entries.f_prune_initial (v_module) (v_initial) (v_entry)) with
| Fail __error -> Fail __error
| Done v_pruned ->
(match (Check.f_module_graph ((Entries.f_pruned_module (v_pruned)))) with
| Fail __error -> Fail __error
| Done v_nodes ->
(match (f_prepare_cached_nodes (v_key) ((Entries.f_pruned_module (v_pruned))) (v_entry) (v_family_templates) (v_nodes) (v_previous) ((Entries.f_pruned_initial (v_pruned)))) with
| Fail __error -> Fail __error
| Done v_prepared ->
(Done ((f_with_source_certificates (v_prepared) ((Scheduler.f_initial_certificates (v_initial))))))))))
and (* monomorph.bend:4598 *)
f_prepare_cached_initial : (M.t_Module -> (M.t_Diagnostic, (int32) list) Base.result_) -> M.t_Module -> Base.text -> (M.t_Operation) list -> (t_Cache) option -> Scheduler.t_Initial -> (M.t_Diagnostic, t_Prepared) Base.result_ =
fun v_key v_module v_entry v_family_templates v_previous v_initial ->
(match (Check.f_module_graph (v_module)) with
| Fail __error -> Fail __error
| Done v_nodes ->
(f_prepare_cached_nodes (v_key) (v_module) (v_entry) (v_family_templates) (v_nodes) (v_previous) (v_initial)))
