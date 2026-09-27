(* Native semantic port of compiler/dispatch_resolution.bend.

   Source SHA-256: 88106a46c2ec73f5f599c7500681ca34bb23ffe164f7a219fe62c2e9f8985c74

   Ownership/type arguments are erased; value types are checked by OCaml.

   No Bend interpreter or generated C/JavaScript is linked. *)

open Base

module M = Ox_model

module T = Ox_types

module I = Ox_infer

module C = Ox_constraints

module G = Ox_globals

module Groups = Ox_groups

module Scheduler = Ox_check_scheduler

module Core = Ox_checked_core

module F = Ox_closures

module Index = Ox_index

module Members = Ox_members

module TD = Ox_type_data

module State = Ox_state_specialize

module Schema = Ox_schema_stage

module Mono = Ox_monomorph

module Batch = Ox_inference_batch

module Public = Ox_public_exports

module D = Ox_dependency

module Compare = Ox_core_compare

module Entries = Ox_entry_points

type t_InlineWork =
  | Inline of M.t_Expr
  | InlineMany of (M.t_Expr) list * (M.t_Expr) list
  | InlineApply of int * (int) option * M.t_Expr * M.t_Expr * (Mono.t_BinaryCall) option
and t_DispatchScan =
  | DispatchScan of int * Base.set * bool
and t_Accessor =
  | Accessor of Base.text * M.t_Function * Core.t_Certificate * I.t_Binding
and t_AccessorRequest =
  | AccessorRequest of Base.text * M.t_DataType * M.t_Dispatch * Base.text * int
and t_Requests =
  | Requests of Base.set * (t_AccessorRequest) list * int
and t_MemberUse =
  | MemberUse of M.t_Dispatch * Base.text
and t_Uses =
  | Uses of Base.set * (t_MemberUse) list
and t_SolveContext =
  | SolveContext of (I.t_Binding) Base.map * (t_Accessor) Base.map * (M.t_DataType) list * Base.text * (Schema.t_Evidence) list
and t_Plan =
  | Planned of Base.text * Base.text * Mono.t_Choice
and t_Attempt =
  | Selected of t_Plan * I.t_State
  | Waiting
  | Dropped
and t_Linked =
  | Linked of I.t_State * M.t_Ty
and t_Solving =
  | Solving of I.t_State * (t_Plan) list * (Groups.t_Resolution) list * bool
and t_Solved =
  | Solved of (t_Plan) list * bool
and t_Generated =
  | Generated of Base.set * (M.t_Function) list * (Core.t_Certificate) list
and t_RewriteWork =
  | RewriteOne of M.t_Expr
  | RewriteMany of (M.t_Expr) list * (M.t_Expr) list
and t_RewriteTask =
  | RewriteTask of G.t_Declaration * (((Mono.t_Choice) option) Base.map) option
and t_Rewrite =
  | Rewrite of M.t_Module * (Core.t_Certificate) list * int * (t_Accessor) Base.map * bool * bool
and t_Resolved =
  | Resolved of M.t_Module * Scheduler.t_Initial * (Core.t_Certificate) list
  | Fallback of (Core.t_Certificate) list
  | OriginalFailure of M.t_Diagnostic
  | NoResolution
and t_RoundWork =
  | CheckRound of M.t_Module * (Core.t_Certificate) list * Scheduler.t_Initial * int * ((Schema.t_Evidence) list) option * (t_Accessor) Base.map * int * (Core.t_Certificate) list
  | CheckedRound of M.t_Module * Scheduler.t_InitialAttempt * int * ((Schema.t_Evidence) list) option * (t_Accessor) Base.map * int * (Core.t_Certificate) list
  | RewrittenRound of Scheduler.t_Initial * t_Rewrite * (Schema.t_Evidence) list * int * (Core.t_Certificate) list

let s_0 = Base.text_of_utf8 "specialization_limit"

let s_1 = Base.text_of_utf8 "dispatch"

let s_2 = Base.text_of_utf8 "operator inlining exceeded its structural limit"

let s_3 = Base.text_of_utf8 "d"

let s_4 = Base.text_of_utf8 "u"

let s_5 = Base.text_of_utf8 "b"

let s_6 = Base.text_of_utf8 "m"

let s_7 = Base.text_of_utf8 "@type.same"

let s_8 = Base.text_of_utf8 "unknown_associated_type"

let s_9 = Base.text_of_utf8 "operand type is not yet known"

let s_10 = Base.text_of_utf8 "ambiguous_qualified"

let s_11 = Base.text_of_utf8 "selected implementation effects remain open"

let s_12 = Base.text_of_utf8 ""

let s_13 = Base.text_of_utf8 "dispatch rewriting exceeded its structural limit"

let rec (* dispatch_resolution.bend:46 *)
f_forwarder_entry : (Mono.t_BinaryMember) option -> Base.text -> (Mono.t_BinaryMember) Base.map -> (Mono.t_BinaryMember) Base.map =
fun v_found v_name v_index ->
(match v_found with
| None ->
v_index
| (Some (v_member)) ->
(Base.map_set (v_index) (v_name) (v_member)))
and (* dispatch_resolution.bend:53 *)
f_forwarder_index : (M.t_Function) list -> (Mono.t_BinaryMember) Base.map -> (Mono.t_BinaryMember) Base.map =
fun v_functions v_index ->
(match v_functions with
| [] ->
v_index
| (v_function :: v_tail) ->
(let (M.Function (v_name, v_exported, v_parameter, v_p, v_r, v_body)) = v_function in
(f_forwarder_index (v_tail) ((f_forwarder_entry ((Mono.f_binary_function ((Done (v_function))))) (v_name) (v_index))))))
and (* dispatch_resolution.bend:61 *)
f_forwarder_target : M.t_Expr -> M.t_Expr -> M.t_Expr -> (Mono.t_BinaryMember) Base.map -> (Mono.t_BinaryCall) option =
fun v_target v_left v_right v_forwarders ->
(match v_target with
| (M.FunctionExpr (v_name)) ->
(Mono.f_binary_result ((Index.f_find (v_forwarders) (v_name))) (v_left) (v_right))
| _ ->
None)
and (* dispatch_resolution.bend:68 *)
f_forwarder_call : M.t_Expr -> M.t_Expr -> (Mono.t_BinaryMember) Base.map -> (Mono.t_BinaryCall) option =
fun v_callee v_right v_forwarders ->
(match v_callee with
| (M.ApplyExpr (v_target, v_left)) ->
(f_forwarder_target ((Mono.f_unlocated (65536) (v_target))) (v_left) (v_right) (v_forwarders))
| (M.CallExpr (v_name, v_left)) ->
(f_forwarder_target ((M.FunctionExpr (v_name))) (v_left) (v_right) (v_forwarders))
| _ ->
None)
and (* dispatch_resolution.bend:77 *)
f_inline_location : int -> (int) option -> M.t_Expr -> M.t_Expr =
fun v_offset v_site v_value ->
(match v_site with
| None ->
(M.SourceExpr (v_offset, None, v_value))
| (Some (v_identity)) ->
(M.SourceExpr (v_offset, None, (M.InstantiationExpr (v_identity, v_value)))))
and (* dispatch_resolution.bend:89 *)
f_inline_work : int -> t_InlineWork -> (Mono.t_BinaryMember) Base.map -> (M.t_Diagnostic, (M.t_Expr) list) Base.result_ =
fun v_fuel v_work v_forwarders ->
(match (v_fuel, v_work) with
| (0, _) ->
(Fail ((M.Diagnostic (s_0, s_1, s_2))))
| (__nat_1, (Inline ((M.SourceExpr (v_offset, None, (M.ApplyExpr (v_callee, v_argument))))))) when __nat_1 >= 1 ->
(let v_rest = (__nat_1 - 1) in
(f_inline_work (v_rest) ((InlineApply (v_offset, None, v_callee, v_argument, (f_forwarder_call ((Mono.f_unlocated (65536) (v_callee))) (v_argument) (v_forwarders))))) (v_forwarders)))
| (__nat_2, (Inline ((M.SourceExpr (v_offset, None, (M.InstantiationExpr (v_site, (M.ApplyExpr (v_callee, v_argument))))))))) when __nat_2 >= 1 ->
(let v_rest = (__nat_2 - 1) in
(f_inline_work (v_rest) ((InlineApply (v_offset, (Some (v_site)), v_callee, v_argument, (f_forwarder_call ((Mono.f_unlocated (65536) (v_callee))) (v_argument) (v_forwarders))))) (v_forwarders)))
| (__nat_3, (InlineApply (v_offset, v_site, v_callee, v_argument, (Some ((Mono.BinaryCall (v_member, v_templates, v_left, v_right))))))) when __nat_3 >= 1 ->
(let v_rest = (__nat_3 - 1) in
(match (f_inline_work (v_rest) ((InlineMany ([v_left; v_right], []))) (v_forwarders)) with
| Fail __error -> Fail __error
| Done v_operands ->
(match (Mono.f_rebuild ((M.AssociatedExpr (v_offset, M.BinaryDispatch, v_member, v_templates, M.UnitExpr, M.UnitExpr))) (v_operands) (0)) with
| Fail __error -> Fail __error
| Done v_call ->
(Done ([(f_inline_location (v_offset) (v_site) (v_call))])))))
| (__nat_4, (InlineApply (v_offset, v_site, v_callee, v_argument, None))) when __nat_4 >= 1 ->
(let v_rest = (__nat_4 - 1) in
(match (f_inline_work (v_rest) ((InlineMany ([v_callee; v_argument], []))) (v_forwarders)) with
| Fail __error -> Fail __error
| Done v_parts ->
(match (Mono.f_rebuild ((M.ApplyExpr (M.UnitExpr, M.UnitExpr))) (v_parts) (0)) with
| Fail __error -> Fail __error
| Done v_apply ->
(Done ([(f_inline_location (v_offset) (v_site) (v_apply))])))))
| (__nat_5, (Inline (v_expression))) when __nat_5 >= 1 ->
(let v_rest = (__nat_5 - 1) in
(match (f_inline_work (v_rest) ((InlineMany ((F.f_children (v_expression)), []))) (v_forwarders)) with
| Fail __error -> Fail __error
| Done v_children ->
(match (Mono.f_rebuild (v_expression) (v_children) (0)) with
| Fail __error -> Fail __error
| Done v_rebuilt ->
(Done ([v_rebuilt])))))
| (__nat_6, (InlineMany ([], v_reversed))) when __nat_6 >= 1 ->
(let v_rest = (__nat_6 - 1) in
(Done ((Base.list_reverse (v_reversed)))))
| (__nat_7, (InlineMany ((v_head :: v_tail), v_reversed))) when __nat_7 >= 1 ->
(let v_rest = (__nat_7 - 1) in
(match (f_inline_work (v_rest) ((Inline (v_head))) (v_forwarders)) with
| Fail __error -> Fail __error
| Done v_first ->
(f_inline_work (v_rest) ((InlineMany (v_tail, (Base.list_reverse_go (v_first) (v_reversed))))) (v_forwarders)))))
and (* dispatch_resolution.bend:120 *)
f_inlined_body : (M.t_Diagnostic, (M.t_Expr) list) Base.result_ -> M.t_Expr -> M.t_Expr =
fun v_result v_original ->
(match v_result with
| (Done ((v_expression :: []))) ->
v_expression
| _ ->
v_original)
and (* dispatch_resolution.bend:127 *)
f_inline_body : M.t_Expr -> (Mono.t_BinaryMember) Base.map -> M.t_Expr =
fun v_body v_forwarders ->
(f_inlined_body ((f_inline_work (65536) ((Inline (v_body))) (v_forwarders))) (v_body))
and (* dispatch_resolution.bend:132 *)
f_inline_function_if : bool -> M.t_Function -> (Mono.t_BinaryMember) Base.map -> M.t_Function =
fun v_node v_function v_forwarders ->
(match v_node with
| true ->
v_function
| false ->
(let (M.Function (v_name, v_exported, v_parameter, v_p, v_r, v_body)) = v_function in
(M.Function (v_name, v_exported, v_parameter, v_p, v_r, (f_inline_body (v_body) (v_forwarders))))))
and (* dispatch_resolution.bend:140 *)
f_inline_declaration : G.t_Declaration -> (Mono.t_BinaryMember) Base.map -> G.t_Declaration =
fun v_declaration v_forwarders ->
(match v_declaration with
| (G.FunctionDeclaration (v_function)) ->
(G.FunctionDeclaration ((f_inline_function_if ((Base.maybe_is_some ((Schema.f_node (v_function))))) (v_function) (v_forwarders))))
| (G.ConstantDeclaration ((M.Constant (v_name, v_exported, v_annotation, v_value)))) ->
(G.ConstantDeclaration ((M.Constant (v_name, v_exported, v_annotation, (f_inline_body (v_value) (v_forwarders)))))))
and (* dispatch_resolution.bend:147 *)
f_weighted_declarations : (G.t_Declaration) list -> ((G.t_Declaration) Batch.t_Weighted) list =
fun v_declarations ->
(match v_declarations with
| [] ->
[]
| (v_declaration :: v_tail) ->
((Batch.Weighted (v_declaration, (Mono.f_declaration_cost (v_declaration)))) :: (f_weighted_declarations (v_tail))))
and (* dispatch_resolution.bend:154 *)
f_declaration_functions : (G.t_Declaration) list -> (M.t_Function) list =
fun v_declarations ->
(match v_declarations with
| [] ->
[]
| ((G.FunctionDeclaration (v_function)) :: v_tail) ->
(v_function :: (f_declaration_functions (v_tail)))
| ((G.ConstantDeclaration (v_constant)) :: v_tail) ->
(f_declaration_functions (v_tail)))
and (* dispatch_resolution.bend:163 *)
f_declaration_constants : (G.t_Declaration) list -> (M.t_Constant) list =
fun v_declarations ->
(match v_declarations with
| [] ->
[]
| ((G.FunctionDeclaration (v_function)) :: v_tail) ->
(f_declaration_constants (v_tail))
| ((G.ConstantDeclaration (v_constant)) :: v_tail) ->
(v_constant :: (f_declaration_constants (v_tail))))
and (* dispatch_resolution.bend:172 *)
f_inline_module : M.t_Module -> M.t_Module =
fun v_module ->
(let (M.Module (v_constants, v_functions, v_types, v_operations)) = v_module in
(let v_known = (f_forwarder_index (v_functions) ((Base.map_new ()))) in
(let v_declarations = (Base.list_append ((G.f_function_declarations (v_functions))) ((G.f_constant_declarations (v_constants)))) in
(let v_inlined = (Batch.f_execute (f_inline_declaration) ((Batch.f_plan ((f_weighted_declarations (v_declarations))) (2048))) (v_known)) in
(M.Module ((f_declaration_constants (v_inlined)), (f_declaration_functions (v_inlined)), v_types, v_operations))))))
and (* dispatch_resolution.bend:188 *)
f_scan_identity : t_DispatchScan -> int -> int -> t_DispatchScan =
fun v_scan v_identity v_associated ->
(let (DispatchScan (v_count, v_seen, v_unique)) = v_scan in
(let v_key = (Base.string_append s_3 (Base.nat_show (v_identity))) in
(DispatchScan ((Base.nat_add (v_count) (v_associated)), (Base.set_add (v_seen) (v_key)), (Base.bool_and (v_unique) ((Base.bool_not ((D.f_member (v_seen) (v_key))))))))))
and (* dispatch_resolution.bend:193 *)
f_scan_use_site : t_DispatchScan -> int -> t_DispatchScan =
fun v_scan v_site ->
(let (DispatchScan (v_count, v_seen, v_unique)) = v_scan in
(let v_key = (Base.string_append s_4 (Base.nat_show (v_site))) in
(DispatchScan (v_count, (Base.set_add (v_seen) (v_key)), (Base.bool_and (v_unique) ((Base.bool_not ((D.f_member (v_seen) (v_key))))))))))
and (* dispatch_resolution.bend:198 *)
f_scan_limit : t_DispatchScan -> t_DispatchScan =
fun v_scan ->
(let (DispatchScan (v_count, v_seen, v_unique)) = v_scan in
(DispatchScan (v_count, v_seen, false)))
and (* dispatch_resolution.bend:202 *)
f_dispatch_scan : int -> (M.t_Expr) list -> t_DispatchScan -> t_DispatchScan =
fun v_fuel v_pending v_scan ->
(match (v_fuel, v_pending) with
| (_, []) ->
v_scan
| (0, _) ->
(f_scan_limit (v_scan))
| (__nat_8, ((M.AssociatedExpr (v_identity, v_dispatch, v_member, v_templates, v_left, v_right)) :: v_tail)) when __nat_8 >= 1 ->
(let v_rest = (__nat_8 - 1) in
(f_dispatch_scan (v_rest) ((v_left :: (v_right :: v_tail))) ((f_scan_identity (v_scan) (v_identity) (1)))))
| (__nat_9, ((M.GenericOperationExpr (v_identity, v_template, v_arguments)) :: v_tail)) when __nat_9 >= 1 ->
(let v_rest = (__nat_9 - 1) in
(f_dispatch_scan (v_rest) (v_tail) ((f_scan_identity (v_scan) (v_identity) (0)))))
| (__nat_10, ((M.InstantiationExpr (v_site, v_value)) :: v_tail)) when __nat_10 >= 1 ->
(let v_rest = (__nat_10 - 1) in
(f_dispatch_scan (v_rest) ((v_value :: v_tail)) ((f_scan_use_site (v_scan) (v_site)))))
| (__nat_11, (v_head :: v_tail)) when __nat_11 >= 1 ->
(let v_rest = (__nat_11 - 1) in
(f_dispatch_scan (v_rest) ((Base.list_reverse_go ((Base.list_reverse ((F.f_children (v_head))))) (v_tail))) (v_scan))))
and (* dispatch_resolution.bend:217 *)
f_scan_bodies : (M.t_Expr) list -> t_DispatchScan -> t_DispatchScan =
fun v_bodies v_scan ->
(match v_bodies with
| [] ->
v_scan
| (v_body :: v_tail) ->
(f_scan_bodies (v_tail) ((f_dispatch_scan (1048576) ([v_body]) (v_scan)))))
and (* dispatch_resolution.bend:224 *)
f_scan_module : M.t_Module -> t_DispatchScan =
fun v_module ->
(let (M.Module (v_constants, v_functions, v_types, v_operations)) = v_module in
(f_scan_bodies ((Mono.f_module_expressions (v_functions) (v_constants))) ((DispatchScan (0, (Base.set_new ()), true)))))
and (* dispatch_resolution.bend:244 *)
f_dispatch_tag : M.t_Dispatch -> Base.text =
fun v_dispatch ->
(match v_dispatch with
| M.BinaryDispatch ->
s_5
| M.MemberDispatch ->
s_6
| M.FieldUpdateDispatch ->
s_4)
and (* dispatch_resolution.bend:253 *)
f_choice_key : int -> M.t_Dispatch -> Base.text =
fun v_identity v_dispatch ->
(Base.string_append (Base.nat_show (v_identity)) (f_dispatch_tag (v_dispatch)))
and (* dispatch_resolution.bend:256 *)
f_data_identity : M.t_DataType -> M.t_TypeId =
fun v_data ->
(let (M.DataType (v_identity, v_parameters, v_constructors)) = v_data in
v_identity)
and (* dispatch_resolution.bend:260 *)
f_data_constructors : M.t_DataType -> (M.t_Constructor) list =
fun v_data ->
(let (M.DataType (v_identity, v_parameters, v_constructors)) = v_data in
v_constructors)
and (* dispatch_resolution.bend:264 *)
f_request_if : bool -> Base.text -> M.t_DataType -> M.t_Dispatch -> Base.text -> t_Requests -> t_Requests =
fun v_fresh v_name v_owner v_dispatch v_member v_requests ->
(match v_fresh with
| false ->
v_requests
| true ->
(let (Requests (v_seen, v_reversed, v_next)) = v_requests in
(Requests ((Base.set_add (v_seen) (v_name)), ((AccessorRequest (v_name, v_owner, v_dispatch, v_member, v_next)) :: v_reversed), (Base.nat_add 1 v_next)))))
and (* dispatch_resolution.bend:272 *)
f_seen_request : t_Requests -> Base.text -> bool =
fun v_requests v_name ->
(let (Requests (v_seen, v_reversed, v_next)) = v_requests in
(D.f_member (v_seen) (v_name)))
and (* dispatch_resolution.bend:276 *)
f_owner_request : bool -> M.t_DataType -> M.t_Dispatch -> Base.text -> Base.set -> (t_Accessor) Base.map -> Base.text -> t_Requests -> t_Requests =
fun v_has v_owner v_dispatch v_member v_known v_cache v_entry v_requests ->
(match v_has with
| false ->
v_requests
| true ->
(let v_name = (Mono.f_accessor_name ((Mono.f_nominal_prefix ((f_data_identity (v_owner))) (v_entry))) (v_member) (v_dispatch)) in
(f_request_if ((Base.bool_and ((Base.bool_not ((D.f_member (v_known) (v_name))))) ((Base.bool_and ((Base.bool_not ((Base.maybe_is_some ((Index.f_find (v_cache) (v_name))))))) ((Base.bool_not ((f_seen_request (v_requests) (v_name))))))))) (v_name) (v_owner) (v_dispatch) (v_member) (v_requests))))
and (* dispatch_resolution.bend:284 *)
f_type_requests : (M.t_DataType) list -> M.t_Dispatch -> Base.text -> Base.set -> (t_Accessor) Base.map -> Base.text -> t_Requests -> t_Requests =
fun v_types v_dispatch v_member v_known v_cache v_entry v_requests ->
(match v_types with
| [] ->
v_requests
| (v_owner :: v_tail) ->
(f_type_requests (v_tail) (v_dispatch) (v_member) (v_known) (v_cache) (v_entry) ((f_owner_request ((Members.f_has_field ((f_data_constructors (v_owner))) (v_member))) (v_owner) (v_dispatch) (v_member) (v_known) (v_cache) (v_entry) (v_requests)))))
and (* dispatch_resolution.bend:298 *)
f_use_if : bool -> Base.text -> M.t_Dispatch -> Base.text -> t_Uses -> t_Uses =
fun v_fresh v_key v_dispatch v_member v_uses ->
(match v_fresh with
| false ->
v_uses
| true ->
(let (Uses (v_seen, v_reversed)) = v_uses in
(Uses ((Base.set_add (v_seen) (v_key)), ((MemberUse (v_dispatch, v_member)) :: v_reversed)))))
and (* dispatch_resolution.bend:306 *)
f_need_uses : (Groups.t_Resolution) list -> t_Uses -> t_Uses =
fun v_needs v_uses ->
(match v_needs with
| [] ->
v_uses
| ((Groups.Resolution (v_declaration, v_identity, M.BinaryDispatch, v_member, v_templates, v_left, v_right, v_result, v_invocation, v_ambient)) :: v_tail) ->
(f_need_uses (v_tail) (v_uses))
| ((Groups.Resolution (v_declaration, v_identity, v_dispatch, v_member, v_templates, v_left, v_right, v_result, v_invocation, v_ambient)) :: v_tail) ->
(let (Uses (v_seen, v_reversed)) = v_uses in
(let v_key = (Base.string_append (f_dispatch_tag (v_dispatch)) v_member) in
(f_need_uses (v_tail) ((f_use_if ((Base.bool_not ((D.f_member (v_seen) (v_key))))) (v_key) (v_dispatch) (v_member) (v_uses)))))))
and (* dispatch_resolution.bend:317 *)
f_group_uses : (Groups.t_GroupNeeds) list -> t_Uses -> t_Uses =
fun v_groups v_uses ->
(match v_groups with
| [] ->
v_uses
| ((Groups.GroupNeeds (v_next, v_needs, v_members, v_generalized)) :: v_tail) ->
(f_group_uses (v_tail) ((f_need_uses (v_needs) (v_uses)))))
and (* dispatch_resolution.bend:324 *)
f_use_requests : (t_MemberUse) list -> (M.t_DataType) list -> Base.set -> (t_Accessor) Base.map -> Base.text -> t_Requests -> t_Requests =
fun v_uses v_types v_known v_cache v_entry v_requests ->
(match v_uses with
| [] ->
v_requests
| ((MemberUse (v_dispatch, v_member)) :: v_tail) ->
(f_use_requests (v_tail) (v_types) (v_known) (v_cache) (v_entry) ((f_type_requests (v_types) (v_dispatch) (v_member) (v_known) (v_cache) (v_entry) (v_requests)))))
and (* dispatch_resolution.bend:331 *)
f_uses_list : t_Uses -> (t_MemberUse) list =
fun v_uses ->
(let (Uses (v_seen, v_reversed)) = v_uses in
(Base.list_reverse (v_reversed)))
and (* dispatch_resolution.bend:335 *)
f_group_requests : (Groups.t_GroupNeeds) list -> (M.t_DataType) list -> Base.set -> (t_Accessor) Base.map -> Base.text -> t_Requests -> t_Requests =
fun v_groups v_types v_known v_cache v_entry v_requests ->
(f_use_requests ((f_uses_list ((f_group_uses (v_groups) ((Uses ((Base.set_new ()), []))))))) (v_types) (v_known) (v_cache) (v_entry) (v_requests))
and (* dispatch_resolution.bend:338 *)
f_request_list : t_Requests -> (t_AccessorRequest) list =
fun v_requests ->
(let (Requests (v_seen, v_reversed, v_next)) = v_requests in
(Base.list_reverse (v_reversed)))
and (* dispatch_resolution.bend:342 *)
f_request_next : t_Requests -> int =
fun v_requests ->
(let (Requests (v_seen, v_reversed, v_next)) = v_requests in
v_next)
and (* dispatch_resolution.bend:346 *)
f_accessor_binding : Groups.t_CheckedGroup -> Base.text -> (I.t_Binding) option =
fun v_checked v_name ->
(let (Groups.CheckedGroup ((M.CheckedModule (v_constants, v_functions, v_types, v_operations)), v_interfaces, v_uses)) = v_checked in
(I.f_lookup_binding ((Mono.f_function_bindings (v_functions))) (v_name)))
and (* dispatch_resolution.bend:350 *)
f_accessor_found : (I.t_Binding) option -> Base.text -> M.t_Function -> M.t_Module -> Groups.t_CheckedGroup -> (t_Accessor) option =
fun v_binding v_name v_function v_module v_checked ->
(match v_binding with
| None ->
None
| (Some (v_value)) ->
(Some ((Accessor (v_name, v_function, (Core.Certificate (v_module, v_checked, [])), v_value)))))
and (* dispatch_resolution.bend:357 *)
f_accessor_checked : (M.t_Diagnostic, Groups.t_CheckedGroup) Base.result_ -> Base.text -> M.t_Function -> M.t_Module -> (t_Accessor) option =
fun v_result v_name v_function v_module ->
(match v_result with
| (Fail (v_diagnostic)) ->
None
| (Done (v_checked)) ->
(f_accessor_found ((f_accessor_binding (v_checked) (v_name))) (v_name) (v_function) (v_module) (v_checked)))
and (* dispatch_resolution.bend:364 *)
f_accessor_generated : (M.t_Diagnostic, M.t_Function) Base.result_ -> Base.text -> M.t_DataType -> (t_Accessor) option =
fun v_generated v_name v_owner ->
(match v_generated with
| (Fail (v_diagnostic)) ->
None
| (Done (v_function)) ->
(let v_module = (M.Module ([], [v_function], [v_owner], [])) in
(f_accessor_checked ((Groups.f_check_group_planned (v_module) ([]))) (v_name) (v_function) (v_module))))
and (* dispatch_resolution.bend:374 *)
f_build_accessor_in : t_AccessorRequest -> (t_Accessor) option =
fun v_request ->
(let (AccessorRequest (v_name, v_owner, v_dispatch, v_member, v_identity)) = v_request in
(f_accessor_generated ((Members.f_function ((f_data_constructors (v_owner))) (v_dispatch) (v_member) (v_name) (v_identity))) (v_name) (v_owner)))
and (* dispatch_resolution.bend:378 *)
f_build_accessor : t_AccessorRequest -> unit -> (t_Accessor) option =
fun v_request v_context ->
(f_build_accessor_in (v_request))
and (* dispatch_resolution.bend:381 *)
f_weighted_requests : (t_AccessorRequest) list -> ((t_AccessorRequest) Batch.t_Weighted) list =
fun v_requests ->
(match v_requests with
| [] ->
[]
| (v_request :: v_tail) ->
((Batch.Weighted (v_request, 64)) :: (f_weighted_requests (v_tail))))
and (* dispatch_resolution.bend:388 *)
f_cache_accessors : ((t_Accessor) option) list -> (t_Accessor) Base.map -> (t_Accessor) Base.map =
fun v_accessors v_cache ->
(match v_accessors with
| [] ->
v_cache
| (None :: v_tail) ->
(f_cache_accessors (v_tail) (v_cache))
| ((Some ((Accessor (v_name, v_function, v_certificate, v_binding)))) :: v_tail) ->
(f_cache_accessors (v_tail) ((Base.map_set (v_cache) (v_name) ((Accessor (v_name, v_function, v_certificate, v_binding)))))))
and (* dispatch_resolution.bend:415 *)
f_plain_member : Base.text -> bool =
fun v_member ->
(Base.bool_and ((Base.bool_not ((M.f_name_equal (v_member) (s_7))))) ((Base.bool_not ((Base.maybe_is_some ((State.f_request (v_member))))))))
and (* dispatch_resolution.bend:420 *)
f_receiver_known : M.t_Ty -> bool =
fun v_ty ->
(match v_ty with
| (M.VariableTy (v_index)) ->
false
| (M.ParameterTy (v_index)) ->
false
| (M.FreeTy (v_scope, v_name)) ->
false
| _ ->
true)
and (* dispatch_resolution.bend:431 *)
f_scratch : int -> I.t_State =
fun v_next ->
(I.State ((T.f_empty ()), v_next, MTip))
and (* dispatch_resolution.bend:434 *)
f_candidate_indexed : (Base.text) option -> (I.t_Binding) Base.map -> M.t_Ty -> M.t_Ty -> I.t_State -> (M.t_Diagnostic, I.t_Typing) Base.result_ =
fun v_name v_bindings v_left v_right v_state ->
(match v_name with
| None ->
(Fail ((M.Diagnostic (s_8, s_1, s_9))))
| (Some (v_name)) ->
(Mono.f_candidate_binding ((Index.f_find (v_bindings) (v_name))) (v_name) (v_left) (v_right) (v_state) (s_1)))
and (* dispatch_resolution.bend:447 *)
f_selected_invocation : M.t_Ty -> M.t_Dispatch -> (M.t_Diagnostic, (M.t_EffectRow) option) Base.result_ =
fun v_signature v_dispatch ->
(match v_dispatch with
| M.BinaryDispatch ->
(Mono.f_selected_binary_invocation (v_signature))
| M.FieldUpdateDispatch ->
(Mono.f_selected_binary_invocation (v_signature))
| M.MemberDispatch ->
(Mono.f_selected_receiver_invocation (v_signature)))
and (* dispatch_resolution.bend:456 *)
f_linked_found : (M.t_EffectRow) option -> M.t_EffectRow -> I.t_State -> (M.t_Diagnostic, I.t_State) Base.result_ =
fun v_found v_row v_state ->
(match v_found with
| (Some (v_selected)) ->
(I.f_unify_rows (v_row) (v_selected) (v_state) (s_1))
| None ->
(Fail ((M.Diagnostic (s_10, s_1, s_11)))))
and (* dispatch_resolution.bend:463 *)
f_linked_row : (M.t_EffectRow) option -> M.t_Ty -> M.t_Dispatch -> I.t_State -> (M.t_Diagnostic, I.t_State) Base.result_ =
fun v_invocation v_exact v_dispatch v_state ->
(match v_invocation with
| None ->
(Done (v_state))
| (Some (v_row)) ->
(match (f_selected_invocation (v_exact) (v_dispatch)) with
| Fail __error -> Fail __error
| Done v_found ->
(f_linked_found (v_found) (v_row) (v_state))))
and (* dispatch_resolution.bend:472 *)
f_planned_signature : (M.t_EffectRow) option -> M.t_Ty -> M.t_Ty -> M.t_Ty =
fun v_invocation v_exact v_requested ->
(match v_invocation with
| (Some (v_row)) ->
v_exact
| None ->
v_requested)
and (* dispatch_resolution.bend:479 *)
f_unified : (I.t_Binding) option -> Base.text -> M.t_Ty -> (M.t_EffectRow) option -> M.t_Dispatch -> I.t_State -> (M.t_Diagnostic, t_Linked) Base.result_ =
fun v_found v_name v_signature v_invocation v_dispatch v_state ->
(match (I.f_instantiate_binding_selected (v_found) (v_state) (v_name) (s_1)) with
| Fail __error -> Fail __error
| Done v_instance ->
(let v_target = (I.f_selected_typing (v_instance)) in
(match (I.f_unify ((I.f_type_of (v_target))) (v_signature) ((I.f_state_of (v_target))) (s_1)) with
| Fail __error -> Fail __error
| Done v_checked ->
(match (T.f_resolve ((I.f_substitutions_of (v_checked))) ((I.f_selected_exact (v_instance)))) with
| Fail __error -> Fail __error
| Done v_exact ->
(match (f_linked_row (v_invocation) (v_exact) (v_dispatch) (v_checked)) with
| Fail __error -> Fail __error
| Done v_linked ->
(match (T.f_resolve ((I.f_substitutions_of (v_linked))) (v_exact)) with
| Fail __error -> Fail __error
| Done v_resolved ->
(Done ((Linked (v_linked, (f_planned_signature (v_invocation) (v_resolved) (v_signature))))))))))))
and (* dispatch_resolution.bend:489 *)
f_selected_binary : (M.t_Diagnostic, t_Linked) Base.result_ -> Base.text -> Base.text -> Base.text -> t_Attempt =
fun v_result v_declaration v_key v_name ->
(match v_result with
| (Done ((Linked (v_state, v_signature)))) ->
(Selected ((Planned (v_declaration, v_key, (Mono.FunctionChoice (v_name, v_signature)))), v_state))
| (Fail (v_diagnostic)) ->
Dropped)
and (* dispatch_resolution.bend:496 *)
f_selected_receiver : (M.t_Diagnostic, t_Linked) Base.result_ -> Base.text -> Base.text -> Base.text -> M.t_Dispatch -> t_Attempt =
fun v_result v_declaration v_key v_name v_dispatch ->
(match v_result with
| (Done ((Linked (v_state, v_signature)))) ->
(Selected ((Planned (v_declaration, v_key, (Mono.f_receiver_choice (v_dispatch) (v_name) (v_signature)))), v_state))
| (Fail (v_diagnostic)) ->
Dropped)
and (* dispatch_resolution.bend:503 *)
f_binary_chosen : (M.t_Diagnostic, Base.text) Base.result_ -> Base.text -> int -> M.t_Ty -> M.t_Ty -> M.t_Ty -> (M.t_EffectRow) option -> M.t_EffectRow -> I.t_State -> (I.t_Binding) Base.map -> t_Attempt =
fun v_selected v_declaration v_identity v_left v_right v_result v_invocation v_ambient v_state v_bindings ->
(match v_selected with
| (Fail (v_diagnostic)) ->
Dropped
| (Done (v_name)) ->
(f_selected_binary ((f_unified ((Index.f_find (v_bindings) (v_name))) (v_name) ((M.FunctionTy (v_left, (M.FunctionTy (v_right, v_result, v_ambient)), v_ambient))) (v_invocation) (M.BinaryDispatch) (v_state))) (v_declaration) ((f_choice_key (v_identity) (M.BinaryDispatch))) (v_name)))
and (* dispatch_resolution.bend:510 *)
f_attempt_binary : bool -> bool -> Base.text -> int -> Base.text -> M.t_Ty -> M.t_Ty -> M.t_Ty -> (M.t_EffectRow) option -> M.t_EffectRow -> I.t_State -> t_SolveContext -> t_Attempt =
fun v_plain v_closed v_declaration v_identity v_member v_left v_right v_result v_invocation v_ambient v_state v_context ->
(match (v_plain, v_closed) with
| (false, _) ->
Dropped
| (true, false) ->
Waiting
| (true, true) ->
(let (SolveContext (v_bindings, v_accessors, v_types, v_entry, v_proofs)) = v_context in
(let v_left_name = (Mono.f_member_name ((Mono.f_owner (v_left) (v_entry))) (v_member)) in
(let v_right_name = (Mono.f_member_name ((Mono.f_owner (v_right) (v_entry))) (v_member)) in
(f_binary_chosen ((Mono.f_chosen ((f_candidate_indexed (v_left_name) (v_bindings) (v_left) (v_right) (v_state))) (v_left_name) ((f_candidate_indexed (v_right_name) (v_bindings) (v_left) (v_right) (v_state))) (v_right_name) (s_1) (v_member))) (v_declaration) (v_identity) (v_left) (v_right) (v_result) (v_invocation) (v_ambient) (v_state) (v_bindings))))))
and (* dispatch_resolution.bend:522 *)
f_method_found : (Base.text) option -> (I.t_Binding) Base.map -> (Base.text) option =
fun v_name v_bindings ->
(match v_name with
| None ->
None
| (Some (v_name)) ->
(Base.bool_pick ((Base.maybe_is_some ((Index.f_find (v_bindings) (v_name))))) ((Some (v_name))) (None)))
and (* dispatch_resolution.bend:529 *)
f_cached_binding : (t_Accessor) option -> (I.t_Binding) Base.map -> Base.text -> (I.t_Binding) option =
fun v_found v_bindings v_name ->
(match v_found with
| (Some ((Accessor (v_accessor, v_function, v_certificate, v_binding)))) ->
(Some (v_binding))
| None ->
(Index.f_find (v_bindings) (v_name)))
and (* dispatch_resolution.bend:540 *)
f_receiver_attempt : bool -> (Base.text) option -> bool -> M.t_Dispatch -> Base.text -> int -> Base.text -> M.t_Ty -> M.t_Ty -> M.t_Ty -> (M.t_EffectRow) option -> M.t_EffectRow -> I.t_State -> (I.t_Binding) Base.map -> (t_Accessor) Base.map -> Base.text -> t_Attempt =
fun v_field v_method v_schema v_dispatch v_declaration v_identity v_member v_left v_right v_result v_invocation v_ambient v_state v_bindings v_accessors v_entry ->
(match (v_field, v_method, v_schema, v_dispatch) with
| (true, (Some (v_name)), _, M.MemberDispatch) ->
Dropped
| (true, _, _, v_dispatch) ->
(let v_name = (Mono.f_accessor_name ((Mono.f_accessor_owner ((Mono.f_owner (v_left) (v_entry))))) (v_member) (v_dispatch)) in
(f_selected_receiver ((f_unified ((f_cached_binding ((Index.f_find (v_accessors) (v_name))) (v_bindings) (v_name))) (v_name) ((Mono.f_receiver_signature (v_dispatch) (v_left) (v_right) (v_result) (v_ambient))) (v_invocation) (v_dispatch) (v_state))) (v_declaration) ((f_choice_key (v_identity) (v_dispatch))) (v_name) (v_dispatch)))
| (false, (Some (v_name)), false, M.MemberDispatch) ->
(f_selected_receiver ((f_unified ((Index.f_find (v_bindings) (v_name))) (v_name) ((Mono.f_receiver_signature (M.MemberDispatch) (v_left) (v_right) (v_result) (v_ambient))) (v_invocation) (M.MemberDispatch) (v_state))) (v_declaration) ((f_choice_key (v_identity) (M.MemberDispatch))) (v_name) (M.MemberDispatch))
| (_, _, _, _) ->
Dropped)
and (* dispatch_resolution.bend:552 *)
f_attempt_receiver : bool -> M.t_Dispatch -> Base.text -> int -> Base.text -> M.t_Ty -> M.t_Ty -> M.t_Ty -> (M.t_EffectRow) option -> M.t_EffectRow -> I.t_State -> t_SolveContext -> t_Attempt =
fun v_known v_dispatch v_declaration v_identity v_member v_left v_right v_result v_invocation v_ambient v_state v_context ->
(match v_known with
| false ->
Waiting
| true ->
(let (SolveContext (v_bindings, v_accessors, v_types, v_entry, v_proofs)) = v_context in
(f_receiver_attempt ((Members.f_has_field ((Members.f_constructors (v_left) (v_types))) (v_member))) ((f_method_found ((Mono.f_member_name ((Mono.f_owner (v_left) (v_entry))) (v_member))) (v_bindings))) ((Schema.f_eligible (v_proofs) (v_member) (v_left))) (v_dispatch) (v_declaration) (v_identity) (v_member) (v_left) (v_right) (v_result) (v_invocation) (v_ambient) (v_state) (v_bindings) (v_accessors) (v_entry))))
and (* dispatch_resolution.bend:560 *)
f_attempt_dispatch : M.t_Dispatch -> (M.t_TypeId) list -> Base.text -> int -> Base.text -> M.t_Ty -> M.t_Ty -> M.t_Ty -> (M.t_EffectRow) option -> M.t_EffectRow -> I.t_State -> t_SolveContext -> t_Attempt =
fun v_dispatch v_templates v_declaration v_identity v_member v_left v_right v_result v_invocation v_ambient v_state v_context ->
(match (v_dispatch, v_templates) with
| (M.BinaryDispatch, []) ->
(f_attempt_binary ((f_plain_member (v_member))) ((Groups.f_closed_types (65536) ([v_left; v_right]))) (v_declaration) (v_identity) (v_member) (v_left) (v_right) (v_result) (v_invocation) (v_ambient) (v_state) (v_context))
| (M.BinaryDispatch, _) ->
Dropped
| (v_receiver, _) ->
(f_attempt_receiver ((f_receiver_known (v_left))) (v_receiver) (v_declaration) (v_identity) (v_member) (v_left) (v_right) (v_result) (v_invocation) (v_ambient) (v_state) (v_context)))
and (* dispatch_resolution.bend:569 *)
f_attempt_resolved : (M.t_Diagnostic, M.t_Ty) Base.result_ -> (M.t_Diagnostic, M.t_Ty) Base.result_ -> (M.t_Diagnostic, M.t_Ty) Base.result_ -> (M.t_EffectRow) option -> M.t_EffectRow -> M.t_Dispatch -> (M.t_TypeId) list -> Base.text -> int -> Base.text -> I.t_State -> t_SolveContext -> t_Attempt =
fun v_left v_right v_result v_invocation v_ambient v_dispatch v_templates v_declaration v_identity v_member v_state v_context ->
(match (v_left, v_right, v_result) with
| ((Done (v_l)), (Done (v_r)), (Done (v_value))) ->
(f_attempt_dispatch (v_dispatch) (v_templates) (v_declaration) (v_identity) (v_member) (v_l) (v_r) (v_value) (v_invocation) (v_ambient) (v_state) (v_context))
| (_, _, _) ->
Dropped)
and (* dispatch_resolution.bend:579 *)
f_solving_state : t_Solving -> I.t_State =
fun v_solving ->
(let (Solving (v_state, v_plans, v_waiting, v_progress)) = v_solving in
v_state)
and (* dispatch_resolution.bend:583 *)
f_settle : t_Attempt -> Groups.t_Resolution -> t_Solving -> t_Solving =
fun v_attempt v_need v_solving ->
(match v_attempt with
| (Selected (v_plan, v_state)) ->
(let (Solving (v_previous, v_plans, v_waiting, v_progress)) = v_solving in
(Solving (v_state, (v_plan :: v_plans), v_waiting, true)))
| Waiting ->
(let (Solving (v_state, v_plans, v_waiting, v_progress)) = v_solving in
(Solving (v_state, v_plans, (v_need :: v_waiting), v_progress)))
| Dropped ->
v_solving)
and (* dispatch_resolution.bend:597 *)
f_solve_need : Groups.t_Resolution -> t_Solving -> t_SolveContext -> t_Solving =
fun v_need v_solving v_context ->
(match v_need with
| (Groups.Resolution (v_declaration, v_identity, v_dispatch, v_member, v_templates, v_left, v_right, v_result, v_invocation, v_ambient)) ->
(let v_state = (f_solving_state (v_solving)) in
(let v_substitutions = (I.f_substitutions_of (v_state)) in
(f_settle ((f_attempt_resolved ((T.f_resolve (v_substitutions) (v_left))) ((T.f_resolve (v_substitutions) (v_right))) ((T.f_resolve (v_substitutions) (v_result))) ((Groups.f_resolved_invocation (v_invocation) (v_substitutions))) ((T.f_resolve_row (v_substitutions) (v_ambient))) (v_dispatch) (v_templates) (v_declaration) (v_identity) (v_member) (v_state) (v_context))) ((Groups.Resolution (v_declaration, v_identity, v_dispatch, v_member, v_templates, v_left, v_right, v_result, v_invocation, v_ambient))) (v_solving)))))
and (* dispatch_resolution.bend:604 *)
f_solve_pass : (Groups.t_Resolution) list -> t_Solving -> t_SolveContext -> t_Solving =
fun v_needs v_solving v_context ->
(match v_needs with
| [] ->
v_solving
| (v_need :: v_tail) ->
(f_solve_pass (v_tail) ((f_solve_need (v_need) (v_solving) (v_context))) (v_context)))
and (* dispatch_resolution.bend:613 *)
f_solve_work : int -> t_Solving -> t_SolveContext -> t_Solving =
fun v_fuel v_solving v_context ->
(match (v_fuel, v_solving) with
| (0, _) ->
v_solving
| (__nat_12, (Solving (v_state, v_plans, v_waiting, false))) when __nat_12 >= 1 ->
(let v_rest = (__nat_12 - 1) in
(Solving (v_state, v_plans, v_waiting, false)))
| (__nat_13, (Solving (v_state, v_plans, v_waiting, true))) when __nat_13 >= 1 ->
(let v_rest = (__nat_13 - 1) in
(f_solve_work (v_rest) ((f_solve_pass ((Base.list_reverse (v_waiting))) ((Solving (v_state, v_plans, [], false))) (v_context))) (v_context))))
and (* dispatch_resolution.bend:630 *)
f_member_unchanged : (M.t_Diagnostic, M.t_Ty) Base.result_ -> M.t_Ty -> bool =
fun v_resolved v_original ->
(match v_resolved with
| (Fail (v_diagnostic)) ->
false
| (Done (v_ty)) ->
(Compare.f_same_ty (v_ty) (v_original)))
and (* dispatch_resolution.bend:639 *)
f_same_predicates_work : (M.t_Predicate) list -> (M.t_Predicate) list -> bool -> bool =
fun v_left v_right v_equal ->
(match (v_left, v_right, v_equal) with
| (_, _, false) ->
false
| ([], [], true) ->
true
| ((v_a :: v_as), (v_b :: v_bs), true) ->
(f_same_predicates_work (v_as) (v_bs) ((C.f_same_predicate (v_a) (v_b))))
| (_, _, _) ->
false)
and (* dispatch_resolution.bend:650 *)
f_same_predicates : (M.t_Predicate) list -> (M.t_Predicate) list -> bool =
fun v_left v_right ->
(f_same_predicates_work (v_left) (v_right) (true))
and (* dispatch_resolution.bend:653 *)
f_predicates_unchanged : (M.t_Diagnostic, (M.t_Predicate) list) Base.result_ -> (M.t_Predicate) list -> bool =
fun v_resolved v_original ->
(match v_resolved with
| (Fail (v_diagnostic)) ->
false
| (Done (v_predicates)) ->
(f_same_predicates (v_predicates) (v_original)))
and (* dispatch_resolution.bend:660 *)
f_unchanged_members : (I.t_Binding) list -> T.t_Substitutions -> bool =
fun v_members v_substitutions ->
(match v_members with
| [] ->
true
| ((I.Binding (v_name, v_ty, v_variables, v_predicates)) :: v_tail) ->
(Base.bool_and ((Base.bool_and ((f_member_unchanged ((T.f_resolve (v_substitutions) (v_ty))) (v_ty))) ((f_predicates_unchanged ((C.f_resolve_list (v_substitutions) (v_predicates))) (v_predicates))))) ((f_unchanged_members (v_tail) (v_substitutions)))))
and (* dispatch_resolution.bend:667 *)
f_disjoint : (int) list -> (int) list -> bool =
fun v_variables v_generalized ->
(match v_variables with
| [] ->
true
| (v_head :: v_tail) ->
(Base.bool_and ((Base.bool_not ((T.f_contains (v_generalized) (v_head))))) ((f_disjoint (v_tail) (v_generalized)))))
and (* dispatch_resolution.bend:674 *)
f_free_untouched : (M.t_Diagnostic, (int) list) Base.result_ -> (int) list -> bool =
fun v_free v_generalized ->
(match v_free with
| (Fail (v_diagnostic)) ->
false
| (Done (v_variables)) ->
(f_disjoint (v_variables) (v_generalized)))
and (* dispatch_resolution.bend:681 *)
f_type_untouched : (M.t_Diagnostic, M.t_Ty) Base.result_ -> (int) list -> bool =
fun v_resolved v_generalized ->
(match v_resolved with
| (Fail (v_diagnostic)) ->
false
| (Done (v_ty)) ->
(f_free_untouched ((T.f_free (v_ty))) (v_generalized)))
and (* dispatch_resolution.bend:694 *)
f_binding_untouched : bool -> bool -> bool -> bool =
fun v_generalized_variable v_group_variable v_replacement ->
(match (v_generalized_variable, v_group_variable) with
| (true, _) ->
false
| (false, true) ->
v_replacement
| (false, false) ->
true)
and (* dispatch_resolution.bend:703 *)
f_history_untouched : (T.t_Substitution) list -> T.t_Substitutions -> (int) list -> int -> bool =
fun v_history v_substitutions v_generalized v_next ->
(match v_history with
| [] ->
true
| ((T.Substitution (v_variable, v_replacement)) :: v_tail) ->
(Base.bool_and ((f_binding_untouched ((T.f_contains (v_generalized) (v_variable))) ((Base.nat_is_lt (v_variable) (v_next))) ((f_type_untouched ((T.f_resolve (v_substitutions) (v_replacement))) (v_generalized))))) ((f_history_untouched (v_tail) (v_substitutions) (v_generalized) (v_next))))
| ((T.RowSubstitution (v_variable, v_replacement)) :: v_tail) ->
(Base.bool_and ((f_binding_untouched ((T.f_contains (v_generalized) (v_variable))) ((Base.nat_is_lt (v_variable) (v_next))) ((f_disjoint ((T.f_row_free ((T.f_resolve_row (v_substitutions) (v_replacement))))) (v_generalized))))) ((f_history_untouched (v_tail) (v_substitutions) (v_generalized) (v_next)))))
and (* dispatch_resolution.bend:712 *)
f_schemes_untouched : T.t_Substitutions -> (int) list -> int -> bool =
fun v_substitutions v_generalized v_next ->
(match v_generalized with
| [] ->
true
| (v_head :: v_tail) ->
(f_history_untouched ((T.f_substitution_history (v_substitutions))) (v_substitutions) ((v_head :: v_tail)) (v_next)))
and (* dispatch_resolution.bend:721 *)
f_stable_group : bool -> bool -> bool -> bool =
fun v_unplanned v_untouched v_unchanged ->
(match (v_unplanned, v_untouched) with
| (true, _) ->
true
| (false, false) ->
false
| (false, true) ->
v_unchanged)
and (* dispatch_resolution.bend:730 *)
f_solved_group : t_Solving -> (I.t_Binding) list -> (int) list -> int -> t_Solved =
fun v_solving v_members v_generalized v_next ->
(let (Solving (v_state, v_plans, v_waiting, v_progress)) = v_solving in
(let v_substitutions = (I.f_substitutions_of (v_state)) in
(Solved ((Base.list_reverse (v_plans)), (f_stable_group ((Base.list_is_empty (v_plans))) ((f_schemes_untouched (v_substitutions) (v_generalized) (v_next))) ((f_unchanged_members (v_members) (v_substitutions))))))))
and (* dispatch_resolution.bend:735 *)
f_solve_group_in : Groups.t_GroupNeeds -> t_SolveContext -> t_Solved =
fun v_group v_context ->
(let (Groups.GroupNeeds (v_next, v_needs, v_members, v_generalized)) = v_group in
(f_solved_group ((f_solve_work ((Base.nat_add 2 (Base.list_length (v_needs)))) ((Solving ((f_scratch (v_next)), [], (Base.list_reverse (v_needs)), true))) (v_context))) (v_members) (v_generalized) (v_next)))
and (* dispatch_resolution.bend:739 *)
f_solve_group : Groups.t_GroupNeeds -> t_SolveContext -> t_Solved =
fun v_group v_context ->
(f_solve_group_in (v_group) (v_context))
and (* dispatch_resolution.bend:742 *)
f_weighted_groups : (Groups.t_GroupNeeds) list -> ((Groups.t_GroupNeeds) Batch.t_Weighted) list =
fun v_groups ->
(match v_groups with
| [] ->
[]
| ((Groups.GroupNeeds (v_next, v_needs, v_members, v_generalized)) :: v_tail) ->
((Batch.Weighted ((Groups.GroupNeeds (v_next, v_needs, v_members, v_generalized)), (Base.list_length (v_needs)))) :: (f_weighted_groups (v_tail))))
and (* dispatch_resolution.bend:749 *)
f_flatten_plans : (t_Solved) list -> (t_Plan) list =
fun v_groups ->
(match v_groups with
| [] ->
[]
| ((Solved (v_plans, v_stable)) :: v_tail) ->
(Base.list_append (v_plans) ((f_flatten_plans (v_tail)))))
and (* dispatch_resolution.bend:756 *)
f_all_stable : (t_Solved) list -> bool =
fun v_groups ->
(match v_groups with
| [] ->
true
| ((Solved (v_plans, v_stable)) :: v_tail) ->
(Base.bool_and (v_stable) ((f_all_stable (v_tail)))))
and (* dispatch_resolution.bend:767 *)
f_planned_names : (t_Plan) list -> Base.set -> Base.set =
fun v_plans v_seen ->
(match v_plans with
| [] ->
v_seen
| ((Planned (v_declaration, v_key, v_choice)) :: v_tail) ->
(f_planned_names (v_tail) ((Base.set_add (v_seen) (v_declaration)))))
and (* dispatch_resolution.bend:774 *)
f_any_planned_name : (Base.text) list -> Base.set -> bool =
fun v_names v_planned ->
(match v_names with
| [] ->
false
| (v_name :: v_tail) ->
(Base.bool_or ((D.f_member (v_planned) (v_name))) ((f_any_planned_name (v_tail) (v_planned)))))
and (* dispatch_resolution.bend:781 *)
f_predicated_rewrite : (Core.t_Certificate) list -> Base.set -> bool =
fun v_certificates v_planned ->
(match v_certificates with
| [] ->
false
| ((Core.Certificate (v_module, (Groups.CheckedGroup (v_checked, v_interfaces, v_uses)), v_imports)) :: v_tail) ->
(Base.bool_or ((Base.bool_and ((Core.f_pending_uses (v_uses))) ((f_any_planned_name ((Core.f_names (v_module))) (v_planned))))) ((f_predicated_rewrite (v_tail) (v_planned)))))
and (* dispatch_resolution.bend:788 *)
f_stable_with_uses : bool -> (t_Plan) list -> (Core.t_Certificate) list -> bool =
fun v_stable v_plans v_certificates ->
(match (v_stable, v_plans) with
| (false, _) ->
false
| (true, []) ->
true
| (true, v_plans) ->
(Base.bool_not ((f_predicated_rewrite (v_certificates) ((f_planned_names (v_plans) ((Base.set_new ()))))))))
and (* dispatch_resolution.bend:797 *)
f_chosen_name : Mono.t_Choice -> Base.text =
fun v_choice ->
(match v_choice with
| (Mono.FunctionChoice (v_name, v_signature)) ->
v_name
| (Mono.ReceiverChoice (v_name, v_signature)) ->
v_name
| (Mono.OperationChoice (v_identity, v_signature)) ->
s_12
| (Mono.QualifiedChoice (v_solved, v_answers)) ->
s_12)
and (* dispatch_resolution.bend:811 *)
f_generated_accessor : (t_Accessor) option -> t_Generated -> t_Generated =
fun v_found v_generated ->
(match v_found with
| None ->
v_generated
| (Some ((Accessor (v_name, v_function, v_certificate, v_binding)))) ->
(let (Generated (v_seen, v_functions, v_certificates)) = v_generated in
(Generated ((Base.set_add (v_seen) (v_name)), (v_function :: v_functions), (v_certificate :: v_certificates)))))
and (* dispatch_resolution.bend:819 *)
f_generated_name : Base.text -> Base.set -> (t_Accessor) Base.map -> t_Generated -> t_Generated =
fun v_name v_known v_cache v_generated ->
(let (Generated (v_seen, v_functions, v_certificates)) = v_generated in
(let v_fresh = (Base.bool_and ((Base.bool_not ((D.f_member (v_known) (v_name))))) ((Base.bool_not ((D.f_member (v_seen) (v_name)))))) in
(f_generated_accessor ((Base.bool_pick (v_fresh) ((Index.f_find (v_cache) (v_name))) (None))) ((Generated (v_seen, v_functions, v_certificates))))))
and (* dispatch_resolution.bend:825 *)
f_generated_accessors : (t_Plan) list -> Base.set -> (t_Accessor) Base.map -> t_Generated -> t_Generated =
fun v_plans v_known v_cache v_generated ->
(match v_plans with
| [] ->
v_generated
| ((Planned (v_declaration, v_key, v_choice)) :: v_tail) ->
(f_generated_accessors (v_tail) (v_known) (v_cache) ((f_generated_name ((f_chosen_name (v_choice))) (v_known) (v_cache) (v_generated)))))
and (* dispatch_resolution.bend:836 *)
f_choice_entry : bool -> Mono.t_Choice -> (Mono.t_Choice) option =
fun v_present v_choice ->
(match v_present with
| true ->
None
| false ->
(Some (v_choice)))
and (* dispatch_resolution.bend:844 *)
f_add_choice : (((Mono.t_Choice) option) Base.map) Base.map -> Base.text -> Base.text -> Mono.t_Choice -> (((Mono.t_Choice) option) Base.map) Base.map =
fun v_choices v_declaration v_key v_choice ->
(let v_current = (Index.f_get (v_choices) (v_declaration) ((Base.map_new ()))) in
(Base.map_set (v_choices) (v_declaration) ((Base.map_set (v_current) (v_key) ((f_choice_entry ((Base.maybe_is_some ((Index.f_find (v_current) (v_key))))) (v_choice)))))))
and (* dispatch_resolution.bend:848 *)
f_declaration_choices : (t_Plan) list -> (((Mono.t_Choice) option) Base.map) Base.map -> (((Mono.t_Choice) option) Base.map) Base.map =
fun v_plans v_choices ->
(match v_plans with
| [] ->
v_choices
| ((Planned (v_declaration, v_key, v_choice)) :: v_tail) ->
(f_declaration_choices (v_tail) ((f_add_choice (v_choices) (v_declaration) (v_key) (v_choice))))
| (v_head :: v_tail) ->
(f_declaration_choices (v_tail) (v_choices)))
and (* dispatch_resolution.bend:857 *)
f_resolved_call : ((Mono.t_Choice) option) option -> int -> M.t_Dispatch -> Base.text -> (M.t_TypeId) list -> M.t_Expr -> M.t_Expr -> (M.t_Diagnostic, M.t_Expr) Base.result_ =
fun v_found v_identity v_dispatch v_member v_templates v_left v_right ->
(match v_found with
| (Some ((Some (v_choice)))) ->
(Mono.f_selected_call ((Some (v_choice))) (v_member) (v_left) (v_right))
| _ ->
(Done ((M.AssociatedExpr (v_identity, v_dispatch, v_member, v_templates, v_left, v_right)))))
and (* dispatch_resolution.bend:864 *)
f_rewrite_node : M.t_Expr -> (M.t_Expr) list -> ((Mono.t_Choice) option) Base.map -> (M.t_Diagnostic, M.t_Expr) Base.result_ =
fun v_original v_children v_choices ->
(match (v_original, v_children) with
| ((M.AssociatedExpr (v_identity, v_dispatch, v_member, v_templates, v_left, v_right)), (v_l :: (v_r :: []))) ->
(f_resolved_call ((Index.f_find (v_choices) ((f_choice_key (v_identity) (v_dispatch))))) (v_identity) (v_dispatch) (v_member) (v_templates) (v_l) (v_r))
| (v_original, v_children) ->
(Mono.f_rebuild (v_original) (v_children) (0)))
and (* dispatch_resolution.bend:875 *)
f_rewrite_work : int -> t_RewriteWork -> ((Mono.t_Choice) option) Base.map -> (M.t_Diagnostic, (M.t_Expr) list) Base.result_ =
fun v_fuel v_work v_choices ->
(match (v_fuel, v_work) with
| (0, _) ->
(Fail ((M.Diagnostic (s_0, s_1, s_13))))
| (__nat_14, (RewriteOne (v_expression))) when __nat_14 >= 1 ->
(let v_rest = (__nat_14 - 1) in
(match (f_rewrite_work (v_rest) ((RewriteMany ((F.f_children (v_expression)), []))) (v_choices)) with
| Fail __error -> Fail __error
| Done v_children ->
(match (f_rewrite_node (v_expression) (v_children) (v_choices)) with
| Fail __error -> Fail __error
| Done v_rebuilt ->
(Done ([v_rebuilt])))))
| (__nat_15, (RewriteMany ([], v_reversed))) when __nat_15 >= 1 ->
(let v_rest = (__nat_15 - 1) in
(Done ((Base.list_reverse (v_reversed)))))
| (__nat_16, (RewriteMany ((v_head :: v_tail), v_reversed))) when __nat_16 >= 1 ->
(let v_rest = (__nat_16 - 1) in
(match (f_rewrite_work (v_rest) ((RewriteOne (v_head))) (v_choices)) with
| Fail __error -> Fail __error
| Done v_first ->
(f_rewrite_work (v_rest) ((RewriteMany (v_tail, (Base.list_reverse_go (v_first) (v_reversed))))) (v_choices)))))
and (* dispatch_resolution.bend:891 *)
f_rewritten_body : (M.t_Diagnostic, (M.t_Expr) list) Base.result_ -> M.t_Expr -> M.t_Expr =
fun v_result v_original ->
(match v_result with
| (Done ((v_expression :: []))) ->
v_expression
| _ ->
v_original)
and (* dispatch_resolution.bend:898 *)
f_rewrite_body : M.t_Expr -> ((Mono.t_Choice) option) Base.map -> M.t_Expr =
fun v_body v_choices ->
(f_rewritten_body ((f_rewrite_work (65536) ((RewriteOne (v_body))) (v_choices))) (v_body))
and (* dispatch_resolution.bend:904 *)
f_rewrite_declaration : t_RewriteTask -> unit -> G.t_Declaration =
fun v_task v_context ->
(match v_task with
| (RewriteTask (v_declaration, None)) ->
v_declaration
| (RewriteTask ((G.FunctionDeclaration ((M.Function (v_name, v_exported, v_parameter, v_p, v_r, v_body)))), (Some (v_choices)))) ->
(G.FunctionDeclaration ((M.Function (v_name, v_exported, v_parameter, v_p, v_r, (f_rewrite_body (v_body) (v_choices))))))
| (RewriteTask ((G.ConstantDeclaration ((M.Constant (v_name, v_exported, v_annotation, v_value)))), (Some (v_choices)))) ->
(G.ConstantDeclaration ((M.Constant (v_name, v_exported, v_annotation, (f_rewrite_body (v_value) (v_choices)))))))
and (* dispatch_resolution.bend:913 *)
f_rewrite_cost : (((Mono.t_Choice) option) Base.map) option -> G.t_Declaration -> int =
fun v_found v_declaration ->
(match v_found with
| None ->
1
| (Some (v_choices)) ->
(Mono.f_declaration_cost (v_declaration)))
and (* dispatch_resolution.bend:920 *)
f_rewrite_tasks : (G.t_Declaration) list -> (((Mono.t_Choice) option) Base.map) Base.map -> ((t_RewriteTask) Batch.t_Weighted) list =
fun v_declarations v_choices ->
(match v_declarations with
| [] ->
[]
| (v_declaration :: v_tail) ->
(let v_found = (Index.f_find (v_choices) ((G.f_declaration_name (v_declaration)))) in
((Batch.Weighted ((RewriteTask (v_declaration, v_found)), (f_rewrite_cost (v_found) (v_declaration)))) :: (f_rewrite_tasks (v_tail) (v_choices)))))
and (* dispatch_resolution.bend:928 *)
f_function_names : (M.t_Function) list -> Base.set -> Base.set =
fun v_functions v_names ->
(match v_functions with
| [] ->
v_names
| ((M.Function (v_name, v_exported, v_parameter, v_p, v_r, v_body)) :: v_tail) ->
(f_function_names (v_tail) ((Base.set_add (v_names) (v_name)))))
and (* dispatch_resolution.bend:935 *)
f_planned_count : (t_Plan) list -> int -> int =
fun v_plans v_count ->
(match v_plans with
| [] ->
v_count
| ((Planned (v_declaration, v_key, v_choice)) :: v_tail) ->
(f_planned_count (v_tail) ((Base.nat_add 1 v_count))))
and (* dispatch_resolution.bend:945 *)
f_rewritten_module : (G.t_Declaration) list -> t_Generated -> (M.t_DataType) list -> (M.t_Operation) list -> int -> (t_Accessor) Base.map -> bool -> bool -> t_Rewrite =
fun v_rewritten v_generated v_types v_operations v_next v_cache v_changed v_stable ->
(let (Generated (v_seen, v_added, v_certificates)) = v_generated in
(Rewrite ((M.Module ((f_declaration_constants (v_rewritten)), (Base.list_append ((f_declaration_functions (v_rewritten))) ((Base.list_reverse (v_added)))), v_types, v_operations)), (Base.list_reverse (v_certificates)), v_next, v_cache, v_changed, v_stable)))
and (* dispatch_resolution.bend:949 *)
f_rewrite_planned : (t_Plan) list -> M.t_Module -> Base.set -> (t_Accessor) Base.map -> int -> bool -> t_Rewrite =
fun v_plans v_module v_known v_cache v_next v_stable ->
(let (M.Module (v_constants, v_functions, v_types, v_operations)) = v_module in
(let v_declarations = (Base.list_append ((G.f_function_declarations (v_functions))) ((G.f_constant_declarations (v_constants)))) in
(let v_rewritten = (Batch.f_execute (f_rewrite_declaration) ((Batch.f_plan ((f_rewrite_tasks (v_declarations) ((f_declaration_choices (v_plans) ((Base.map_new ())))))) (2048))) (())) in
(f_rewritten_module (v_rewritten) ((f_generated_accessors (v_plans) (v_known) (v_cache) ((Generated ((Base.set_new ()), [], []))))) (v_types) (v_operations) (v_next) (v_cache) ((Base.nat_is_gt ((f_planned_count (v_plans) (0))) (0))) (v_stable)))))
and (* dispatch_resolution.bend:955 *)
f_rewrite_round : M.t_Module -> Scheduler.t_Initial -> Base.text -> int -> (Schema.t_Evidence) list -> (t_Accessor) Base.map -> t_Rewrite =
fun v_module v_initial v_entry v_next v_proofs v_cache ->
(let (M.Module (v_constants, v_functions, v_types, v_operations)) = v_module in
(let (Scheduler.Initial (v_checked, v_certificates, v_needs)) = v_initial in
(let v_known = (f_function_names (v_functions) ((Base.set_new ()))) in
(let v_requests = (f_group_requests (v_needs) (v_types) (v_known) (v_cache) (v_entry) ((Requests ((Base.set_new ()), [], v_next)))) in
(let v_built = (Batch.f_execute (f_build_accessor) ((Batch.f_plan ((f_weighted_requests ((f_request_list (v_requests))))) (128))) (())) in
(let v_accessors = (f_cache_accessors (v_built) (v_cache)) in
(let v_bindings = (Public.f_binding_index ((G.f_env_bindings ((Mono.f_shape_bindings (v_checked))))) (MTip)) in
(let v_solved = (Batch.f_execute (f_solve_group) ((Batch.f_plan ((f_weighted_groups (v_needs))) (256))) ((SolveContext (v_bindings, v_accessors, v_types, v_entry, v_proofs)))) in
(let v_plans = (f_flatten_plans (v_solved)) in
(f_rewrite_planned (v_plans) (v_module) (v_known) (v_accessors) ((f_request_next (v_requests))) ((f_stable_with_uses ((f_all_stable (v_solved))) (v_plans) (v_certificates)))))))))))))
and (* dispatch_resolution.bend:984 *)
f_captured_proofs : ((Schema.t_Evidence) list) option -> M.t_Module -> Scheduler.t_Initial -> Base.text -> (Schema.t_Evidence) list =
fun v_found v_module v_initial v_entry ->
(match v_found with
| (Some (v_proofs)) ->
v_proofs
| None ->
(let (M.Module (v_constants, v_functions, v_types, v_operations)) = v_module in
(Schema.f_capture (v_functions) (v_types) ((Scheduler.f_initial_checked (v_initial))) (v_entry))))
and (* dispatch_resolution.bend:992 *)
f_certificate_functions : (Core.t_Certificate) list -> (M.t_CheckedFunction) list =
fun v_certificates ->
(match v_certificates with
| [] ->
[]
| ((Core.Certificate (v_module, (Groups.CheckedGroup ((M.CheckedModule (v_constants, v_functions, v_types, v_operations)), v_interfaces, v_uses)), v_imports)) :: v_tail) ->
(Base.list_append (v_functions) ((f_certificate_functions (v_tail)))))
and (* dispatch_resolution.bend:1003 *)
f_extended_initial : Scheduler.t_Initial -> (Core.t_Certificate) list -> Scheduler.t_Initial =
fun v_initial v_certificates ->
(let (Scheduler.Initial ((M.CheckedModule (v_constants, v_functions, v_types, v_operations)), v_existing, v_needs)) = v_initial in
(Scheduler.Initial ((M.CheckedModule (v_constants, (Base.list_append (v_functions) ((f_certificate_functions (v_certificates)))), v_types, v_operations)), (Base.list_append (v_certificates) (v_existing)), v_needs)))
and (* dispatch_resolution.bend:1007 *)
f_round_budget : unit -> int =
fun () ->
32
and (* dispatch_resolution.bend:1010 *)
f_rounds : int -> t_RoundWork -> Base.text -> t_Resolved =
fun v_fuel v_work v_entry ->
(match (v_fuel, v_work) with
| (0, (CheckRound (v_module, v_certificates, v_previous, v_next, v_proofs, v_cache, v_budget, v_source_certificates))) ->
(Fallback (v_source_certificates))
| (0, (CheckedRound (v_module, v_checked, v_next, v_proofs, v_cache, v_budget, v_source_certificates))) ->
(Fallback (v_source_certificates))
| (0, (RewrittenRound (v_initial, v_rewrite, v_proofs, v_budget, v_source_certificates))) ->
(Fallback (v_source_certificates))
| (__nat_17, (CheckRound (v_module, v_certificates, v_previous, v_next, v_proofs, v_cache, v_budget, v_source_certificates))) when __nat_17 >= 1 ->
(let v_rest = (__nat_17 - 1) in
(f_rounds (v_rest) ((CheckedRound (v_module, (Scheduler.f_check_module_resolving_reusing (v_module) (v_certificates) (v_previous)), v_next, v_proofs, v_cache, v_budget, v_source_certificates))) (v_entry)))
| (__nat_18, (CheckedRound (v_module, (Scheduler.FailedInitial (v_diagnostic, v_certificates, v_inferred, v_retained)), v_next, v_proofs, v_cache, v_budget, v_source_certificates))) when __nat_18 >= 1 ->
(let v_rest = (__nat_18 - 1) in
(Fallback ((Base.list_append (v_source_certificates) (v_certificates)))))
| (__nat_19, (CheckedRound (v_module, (Scheduler.CheckedInitial (v_initial, v_inferred, v_retained)), v_next, v_proofs, v_cache, 0, v_source_certificates))) when __nat_19 >= 1 ->
(let v_rest = (__nat_19 - 1) in
(Resolved (v_module, v_initial, v_source_certificates)))
| (__nat_20, (CheckedRound (v_module, (Scheduler.CheckedInitial (v_initial, v_inferred, v_retained)), v_next, v_proofs, v_cache, __nat_21, v_source_certificates))) when __nat_20 >= 1 && __nat_21 >= 1 ->
(let v_rest = (__nat_20 - 1) in
(let v_budget = (__nat_21 - 1) in
(let v_evidence = (f_captured_proofs (v_proofs) (v_module) (v_initial) (v_entry)) in
(f_rounds (v_rest) ((RewrittenRound (v_initial, (f_rewrite_round (v_module) (v_initial) (v_entry) (v_next) (v_evidence) (v_cache)), v_evidence, v_budget, v_source_certificates))) (v_entry)))))
| (__nat_22, (RewrittenRound (v_initial, (Rewrite (v_module, v_certificates, v_next, v_cache, false, v_stable)), v_proofs, v_budget, v_source_certificates))) when __nat_22 >= 1 ->
(let v_rest = (__nat_22 - 1) in
(Resolved (v_module, v_initial, v_source_certificates)))
| (__nat_23, (RewrittenRound (v_initial, (Rewrite (v_module, v_certificates, v_next, v_cache, true, true)), v_proofs, v_budget, v_source_certificates))) when __nat_23 >= 1 ->
(let v_rest = (__nat_23 - 1) in
(Resolved (v_module, (f_extended_initial (v_initial) (v_certificates)), v_source_certificates)))
| (__nat_24, (RewrittenRound (v_initial, (Rewrite (v_module, v_certificates, v_next, v_cache, true, false)), v_proofs, v_budget, v_source_certificates))) when __nat_24 >= 1 ->
(let v_rest = (__nat_24 - 1) in
(f_rounds (v_rest) ((CheckRound (v_module, (Base.list_append (v_certificates) ((Scheduler.f_initial_certificates (v_initial)))), v_initial, v_next, (Some (v_proofs)), v_cache, v_budget, v_source_certificates))) (v_entry))))
and (* dispatch_resolution.bend:1037 *)
f_pruned_round : (M.t_Diagnostic, Entries.t_Pruned) Base.result_ -> int -> Base.text -> (Core.t_Certificate) list -> t_Resolved =
fun v_pruned v_next v_entry v_source_certificates ->
(match v_pruned with
| (Fail (v_diagnostic)) ->
(Fallback (v_source_certificates))
| (Done ((Entries.Pruned (v_module, v_initial)))) ->
(f_rounds ((Base.nat_mul (3) ((Base.nat_add 2 (f_round_budget ()))))) ((CheckedRound (v_module, (Scheduler.CheckedInitial (v_initial, 0, 0)), v_next, None, (Base.map_new ()), (f_round_budget ()), v_source_certificates))) (v_entry)))
and (* dispatch_resolution.bend:1044 *)
f_module_identity_limit : M.t_Module -> (M.t_Diagnostic, int) Base.result_ =
fun v_module ->
(let (M.Module (v_constants, v_functions, v_types, v_operations)) = v_module in
(Mono.f_identity_limit (1048576) ((Mono.f_module_expressions (v_functions) (v_constants))) (0)))
and (* dispatch_resolution.bend:1051 *)
f_source_fallback : t_Resolved -> M.t_Module -> Scheduler.t_Initial -> (Core.t_Certificate) list -> t_Resolved =
fun v_found v_module v_initial v_source_certificates ->
(match v_found with
| (Fallback (v_certificates)) ->
(Resolved (v_module, v_initial, v_source_certificates))
| v_other ->
v_other)
and (* dispatch_resolution.bend:1058 *)
f_transformed_round : Scheduler.t_InitialAttempt -> M.t_Module -> int -> Base.text -> (Core.t_Certificate) list -> t_Resolved =
fun v_checked v_module v_next v_entry v_source_certificates ->
(match v_checked with
| (Scheduler.FailedInitial (v_diagnostic, v_certificates, v_inferred, v_retained)) ->
(Fallback ((Base.list_append (v_source_certificates) (v_certificates))))
| (Scheduler.CheckedInitial (v_initial, v_inferred, v_retained)) ->
(f_pruned_round ((Entries.f_prune_initial (v_module) (v_initial) (v_entry))) (v_next) (v_entry) (v_source_certificates)))
and (* dispatch_resolution.bend:1067 *)
f_resolved_changed : bool -> M.t_Module -> M.t_Module -> Scheduler.t_Initial -> int -> Base.text -> (Core.t_Certificate) list -> t_Resolved =
fun v_same v_module v_inlined v_initial v_next v_entry v_source_certificates ->
(match v_same with
| true ->
(f_rounds ((Base.nat_mul (3) ((Base.nat_add 2 (f_round_budget ()))))) ((CheckedRound (v_module, (Scheduler.CheckedInitial (v_initial, 0, 0)), v_next, None, (Base.map_new ()), (f_round_budget ()), v_source_certificates))) (v_entry))
| false ->
(f_transformed_round ((Scheduler.f_check_module_resolving_reusing (v_inlined) ((Scheduler.f_initial_certificates (v_initial))) (v_initial))) (v_inlined) (v_next) (v_entry) (v_source_certificates)))
and (* dispatch_resolution.bend:1076 *)
f_resolve_limited : (M.t_Diagnostic, int) Base.result_ -> M.t_Module -> M.t_Module -> Scheduler.t_Initial -> Base.text -> (Core.t_Certificate) list -> t_Resolved =
fun v_limit v_module v_inlined v_initial v_entry v_source_certificates ->
(match v_limit with
| (Fail (v_diagnostic)) ->
(Resolved (v_module, v_initial, v_source_certificates))
| (Done (v_next)) ->
(f_source_fallback ((f_resolved_changed ((Compare.f_same_module (v_module) (v_inlined))) (v_module) (v_inlined) (v_initial) (v_next) (v_entry) (v_source_certificates))) (v_module) (v_initial) (v_source_certificates)))
and (* dispatch_resolution.bend:1083 *)
f_resolve_scanned : t_DispatchScan -> M.t_Module -> M.t_Module -> Scheduler.t_Initial -> M.t_Module -> Base.text -> (Core.t_Certificate) list -> t_Resolved =
fun v_scan v_module v_inlined v_initial v_original v_entry v_source_certificates ->
(match v_scan with
| (DispatchScan (0, v_seen, v_unique)) ->
(Resolved (v_module, v_initial, v_source_certificates))
| (DispatchScan (v_count, v_seen, false)) ->
(Resolved (v_module, v_initial, v_source_certificates))
| (DispatchScan (v_count, v_seen, true)) ->
(f_resolve_limited ((f_module_identity_limit (v_original))) (v_module) (v_inlined) (v_initial) (v_entry) (v_source_certificates)))
and (* dispatch_resolution.bend:1094 *)
f_source_pruned : (M.t_Diagnostic, Entries.t_Pruned) Base.result_ -> M.t_Module -> Base.text -> (Core.t_Certificate) list -> t_Resolved =
fun v_pruned v_original v_entry v_source_certificates ->
(match v_pruned with
| (Fail (v_diagnostic)) ->
(OriginalFailure (v_diagnostic))
| (Done ((Entries.Pruned (v_module, v_initial)))) ->
(let v_inlined = (f_inline_module (v_module)) in
(f_resolve_scanned ((f_scan_module (v_inlined))) (v_module) (v_inlined) (v_initial) (v_original) (v_entry) (v_source_certificates))))
and (* dispatch_resolution.bend:1102 *)
f_source_checked : Scheduler.t_InitialAttempt -> M.t_Module -> Base.text -> t_Resolved =
fun v_checked v_module v_entry ->
(match v_checked with
| (Scheduler.FailedInitial (v_diagnostic, v_certificates, v_inferred, v_retained)) ->
(OriginalFailure (v_diagnostic))
| (Scheduler.CheckedInitial (v_initial, v_inferred, v_retained)) ->
(f_source_pruned ((Entries.f_prune_initial (v_module) (v_initial) (v_entry))) (v_module) (v_entry) ((Scheduler.f_initial_certificates (v_initial)))))
and (* dispatch_resolution.bend:1109 *)
f_resolve : M.t_Module -> Base.text -> (Core.t_Certificate) list -> t_Resolved =
fun v_module v_entry v_certificates ->
(f_source_checked ((Scheduler.f_check_module_resolving_attempt (v_module) (v_certificates))) (v_module) (v_entry))
and (* dispatch_resolution.bend:1116 *)
f_original_initial : M.t_Module -> (Core.t_Certificate) list -> (M.t_Diagnostic, Scheduler.t_Initial) Base.result_ =
fun v_module v_certificates ->
(Scheduler.f_check_module_resolving (v_module) (v_certificates))
and (* dispatch_resolution.bend:1119 *)
f_fallback_pruned : M.t_Module -> Base.text -> (Core.t_Certificate) list -> (M.t_Diagnostic, Entries.t_Pruned) Base.result_ =
fun v_module v_entry v_certificates ->
(match (f_original_initial (v_module) (v_certificates)) with
| Fail __error -> Fail __error
| Done v_initial ->
(Entries.f_prune_initial (v_module) (v_initial) (v_entry)))
and (* dispatch_resolution.bend:1124 *)
f_prepare_resolved : t_Resolved -> M.t_Module -> Base.text -> (M.t_Operation) list -> (M.t_Diagnostic, M.t_Module) Base.result_ =
fun v_found v_module v_entry v_family_templates ->
(match v_found with
| NoResolution ->
(Mono.f_prepare (v_module) (v_entry) (v_family_templates))
| (OriginalFailure (v_diagnostic)) ->
(Fail (v_diagnostic))
| (Fallback (v_certificates)) ->
(match (f_fallback_pruned (v_module) (v_entry) (v_certificates)) with
| Fail __error -> Fail __error
| Done v_pruned ->
(Mono.f_prepare_checked ((Entries.f_pruned_module (v_pruned))) (v_entry) (v_family_templates) ((Entries.f_pruned_initial (v_pruned)))))
| (Resolved (v_resolved, v_initial, v_source_certificates)) ->
(Mono.f_prepare_checked (v_resolved) (v_entry) (v_family_templates) (v_initial)))
and (* dispatch_resolution.bend:1137 *)
f_prepare : M.t_Module -> Base.text -> (M.t_Operation) list -> (M.t_Diagnostic, M.t_Module) Base.result_ =
fun v_module v_entry v_family_templates ->
(f_prepare_resolved ((f_resolve (v_module) (v_entry) ([]))) (v_module) (v_entry) (v_family_templates))
and (* dispatch_resolution.bend:1140 *)
f_prepare_deferred_resolved : t_Resolved -> M.t_Module -> Base.text -> (M.t_Operation) list -> (M.t_Diagnostic, Core.t_Prepared) Base.result_ =
fun v_found v_module v_entry v_family_templates ->
(match v_found with
| NoResolution ->
(Mono.f_prepare_deferred_core (v_module) (v_entry) (v_family_templates))
| (OriginalFailure (v_diagnostic)) ->
(Fail (v_diagnostic))
| (Fallback (v_certificates)) ->
(match (f_fallback_pruned (v_module) (v_entry) (v_certificates)) with
| Fail __error -> Fail __error
| Done v_pruned ->
(Mono.f_prepare_deferred_initial ((Entries.f_pruned_module (v_pruned))) (v_entry) (v_family_templates) ((Entries.f_pruned_initial (v_pruned)))))
| (Resolved (v_resolved, v_initial, v_source_certificates)) ->
(Mono.f_prepare_deferred_initial (v_resolved) (v_entry) (v_family_templates) (v_initial)))
and (* dispatch_resolution.bend:1153 *)
f_prepare_deferred_core : M.t_Module -> Base.text -> (M.t_Operation) list -> (M.t_Diagnostic, Core.t_Prepared) Base.result_ =
fun v_module v_entry v_family_templates ->
(f_prepare_deferred_resolved ((f_resolve (v_module) (v_entry) ([]))) (v_module) (v_entry) (v_family_templates))
and (* dispatch_resolution.bend:1156 *)
f_prepare_deferred : M.t_Module -> Base.text -> (M.t_Operation) list -> (M.t_Diagnostic, M.t_Module) Base.result_ =
fun v_module v_entry v_family_templates ->
(match (f_prepare_deferred_core (v_module) (v_entry) (v_family_templates)) with
| Fail __error -> Fail __error
| Done v_prepared ->
(Done ((Core.f_prepared_module (v_prepared)))))
and (* dispatch_resolution.bend:1161 *)
f_cached_source : (M.t_Module -> (M.t_Diagnostic, (int32) list) Base.result_) -> M.t_Module -> Base.text -> (M.t_Operation) list -> (Mono.t_Cache) option -> (Core.t_Certificate) list -> (M.t_Diagnostic, Mono.t_Prepared) Base.result_ =
fun v_key v_module v_entry v_family_templates v_previous v_certificates ->
(match (f_original_initial (v_module) (v_certificates)) with
| Fail __error -> Fail __error
| Done v_initial ->
(match (Entries.f_prune_initial (v_module) (v_initial) (v_entry)) with
| Fail __error -> Fail __error
| Done v_pruned ->
(match (Mono.f_prepare_cached_initial (v_key) ((Entries.f_pruned_module (v_pruned))) (v_entry) (v_family_templates) (v_previous) ((Entries.f_pruned_initial (v_pruned)))) with
| Fail __error -> Fail __error
| Done v_prepared ->
(Done ((Mono.f_with_source_certificates (v_prepared) ((Scheduler.f_initial_certificates (v_initial)))))))))
and (* dispatch_resolution.bend:1168 *)
f_prepare_cached_resolved : (M.t_Module -> (M.t_Diagnostic, (int32) list) Base.result_) -> t_Resolved -> M.t_Module -> Base.text -> (M.t_Operation) list -> (Mono.t_Cache) option -> (M.t_Diagnostic, Mono.t_Prepared) Base.result_ =
fun v_key v_found v_module v_entry v_family_templates v_previous ->
(match v_found with
| NoResolution ->
(Mono.f_prepare_cached_evidenced (v_key) (v_module) (v_entry) (v_family_templates) (v_previous))
| (OriginalFailure (v_diagnostic)) ->
(Fail (v_diagnostic))
| (Fallback (v_certificates)) ->
(f_cached_source (v_key) (v_module) (v_entry) (v_family_templates) (v_previous) (v_certificates))
| (Resolved (v_resolved, v_initial, v_source_certificates)) ->
(match (Mono.f_prepare_cached_initial (v_key) (v_resolved) (v_entry) (v_family_templates) (v_previous) (v_initial)) with
| Fail __error -> Fail __error
| Done v_prepared ->
(Done ((Mono.f_with_source_certificates (v_prepared) (v_source_certificates))))))
and (* dispatch_resolution.bend:1181 *)
f_prepare_cached_evidenced : (M.t_Module -> (M.t_Diagnostic, (int32) list) Base.result_) -> M.t_Module -> Base.text -> (M.t_Operation) list -> (Mono.t_Cache) option -> (M.t_Diagnostic, Mono.t_Prepared) Base.result_ =
fun v_key v_module v_entry v_family_templates v_previous ->
(f_prepare_cached_resolved (v_key) ((f_resolve (v_module) (v_entry) ((Mono.f_source_certificates (v_previous))))) (v_module) (v_entry) (v_family_templates) (v_previous))
