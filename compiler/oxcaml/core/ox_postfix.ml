(* Native semantic port of compiler/postfix.bend.

   Source SHA-256: e30b0fbf4216a2801709dd36d481ee479bd2fa2891e2263afd559e63a5468e23

   Ownership/type arguments are erased; value types are checked by OCaml.

   No Bend interpreter or generated C/JavaScript is linked. *)

open Base

module C = Ox_cst

module M = Ox_model

type t_Parts =
  | Parts of C.t_Cst * (C.t_Cst) list
and t_Work =
  | Next of (C.t_Cst) list * C.t_Cst * (C.t_Cst) list
  | Step of Base.text * bool * C.t_Cst * (C.t_Cst) list * C.t_Cst * (C.t_Cst) list

let s_0 = Base.text_of_utf8 "atom"

let s_1 = Base.text_of_utf8 ""

let s_2 = Base.text_of_utf8 "call_expression"

let s_3 = Base.text_of_utf8 "arguments"

let s_4 = Base.text_of_utf8 "head"

let s_5 = Base.text_of_utf8 "index_arity"

let s_6 = Base.text_of_utf8 "indexing requires exactly one index; separate an array argument with a space"

let s_7 = Base.text_of_utf8 "internal_cst"

let s_8 = Base.text_of_utf8 "application"

let s_9 = Base.text_of_utf8 "application lost its head"

let s_10 = Base.text_of_utf8 "lower_limit"

let s_11 = Base.text_of_utf8 "postfix"

let s_12 = Base.text_of_utf8 "postfix chain exceeded its structural limit"

let s_13 = Base.text_of_utf8 "postfix_argument"

let s_14 = Base.text_of_utf8 "member_expression"

let s_15 = Base.text_of_utf8 "receiver"

let s_16 = Base.text_of_utf8 "name"

let s_17 = Base.text_of_utf8 "index_expression"

let s_18 = Base.text_of_utf8 "index"

let s_19 = Base.text_of_utf8 "elements"

let rec (* postfix.bend:8 *)
f_labelled : C.t_Cst -> Base.text -> C.t_Cst =
fun v_node v_field ->
(let (C.Cst (v_kind, v_previous, v_text, v_offset, v_children)) = v_node in
(C.Cst (v_kind, v_field, v_text, v_offset, v_children)))
and (* postfix.bend:12 *)
f_atom : C.t_Cst -> C.t_Cst =
fun v_node ->
(C.Cst (s_0, s_1, s_1, (C.f_offset_of (v_node)), [v_node]))
and (* postfix.bend:15 *)
f_ordinary : C.t_Cst -> C.t_Cst =
fun v_node ->
(match v_node with
| (C.Cst ((SCon (Chr (Base.W32 0x70), (SCon (Chr (Base.W32 0x6f), (SCon (Chr (Base.W32 0x73), (SCon (Chr (Base.W32 0x74), (SCon (Chr (Base.W32 0x66), (SCon (Chr (Base.W32 0x69), (SCon (Chr (Base.W32 0x78), (SCon (Chr (Base.W32 0x5f), (SCon (Chr (Base.W32 0x61), (SCon (Chr (Base.W32 0x72), (SCon (Chr (Base.W32 0x67), (SCon (Chr (Base.W32 0x75), (SCon (Chr (Base.W32 0x6d), (SCon (Chr (Base.W32 0x65), (SCon (Chr (Base.W32 0x6e), (SCon (Chr (Base.W32 0x74), SNil)))))))))))))))))))))))))))))))), v_field, v_text, v_offset, v_children)) ->
(C.Cst (s_0, v_field, v_text, v_offset, v_children))
| v_node ->
v_node)
and (* postfix.bend:22 *)
f_unwrapped : C.t_Cst -> C.t_Cst =
fun v_node ->
(match v_node with
| (C.Cst ((SCon (Chr (Base.W32 0x61), (SCon (Chr (Base.W32 0x74), (SCon (Chr (Base.W32 0x6f), (SCon (Chr (Base.W32 0x6d), SNil)))))))), v_field, v_text, v_offset, (v_child :: []))) ->
v_child
| v_node ->
v_node)
and (* postfix.bend:29 *)
f_call : C.t_Cst -> C.t_Cst -> C.t_Cst =
fun v_current v_argument ->
(match v_current with
| (C.Cst ((SCon (Chr (Base.W32 0x61), (SCon (Chr (Base.W32 0x74), (SCon (Chr (Base.W32 0x6f), (SCon (Chr (Base.W32 0x6d), SNil)))))))), v_field, v_text, v_offset, ((C.Cst ((SCon (Chr (Base.W32 0x63), (SCon (Chr (Base.W32 0x61), (SCon (Chr (Base.W32 0x6c), (SCon (Chr (Base.W32 0x6c), (SCon (Chr (Base.W32 0x5f), (SCon (Chr (Base.W32 0x65), (SCon (Chr (Base.W32 0x78), (SCon (Chr (Base.W32 0x70), (SCon (Chr (Base.W32 0x72), (SCon (Chr (Base.W32 0x65), (SCon (Chr (Base.W32 0x73), (SCon (Chr (Base.W32 0x73), (SCon (Chr (Base.W32 0x69), (SCon (Chr (Base.W32 0x6f), (SCon (Chr (Base.W32 0x6e), SNil)))))))))))))))))))))))))))))), v_f, v_t, v_o, v_children)) :: []))) ->
(f_atom ((C.Cst (s_2, s_1, s_1, v_offset, (Base.list_append (v_children) ([(f_labelled (v_argument) (s_3))]))))))
| v_current ->
(f_atom ((C.Cst (s_2, s_1, s_1, (C.f_offset_of (v_current)), [(f_labelled (v_current) (s_4)); (f_labelled (v_argument) (s_3))])))))
and (* postfix.bend:36 *)
f_index_argument : (C.t_Cst) list -> C.t_Cst -> (M.t_Diagnostic, C.t_Cst) Base.result_ =
fun v_elements v_node ->
(match v_elements with
| (v_index :: []) ->
(Done (v_index))
| _ ->
(Fail ((C.f_diagnostic (v_node) (s_5) (s_6)))))
and (* postfix.bend:43 *)
f_finished : (C.t_Cst) list -> (M.t_Diagnostic, t_Parts) Base.result_ =
fun v_nodes ->
(match v_nodes with
| (v_head :: v_tail) ->
(Done ((Parts (v_head, v_tail))))
| [] ->
(Fail ((M.Diagnostic (s_7, s_8, s_9)))))
and (* postfix.bend:54 *)
f_collect : int -> t_Work -> (M.t_Diagnostic, t_Parts) Base.result_ =
fun v_fuel v_work ->
(match (v_fuel, v_work) with
| (0, _) ->
(Fail ((M.Diagnostic (s_10, s_11, s_12))))
| (__nat_1, (Next ([], v_current, v_reversed))) when __nat_1 >= 1 ->
(let v_rest = (__nat_1 - 1) in
(f_finished ((Base.list_reverse ((v_current :: v_reversed))))))
| (__nat_2, (Next ((v_next :: v_tail), v_current, v_reversed))) when __nat_2 >= 1 ->
(let v_rest = (__nat_2 - 1) in
(f_collect (v_rest) ((Step ((C.f_kind_of ((f_unwrapped ((f_ordinary (v_next)))))), (M.f_name_equal ((C.f_kind_of (v_next))) (s_13)), (f_ordinary (v_next)), v_tail, v_current, v_reversed)))))
| (__nat_3, (Step ((SCon (Chr (Base.W32 0x6d), (SCon (Chr (Base.W32 0x65), (SCon (Chr (Base.W32 0x6d), (SCon (Chr (Base.W32 0x62), (SCon (Chr (Base.W32 0x65), (SCon (Chr (Base.W32 0x72), (SCon (Chr (Base.W32 0x5f), (SCon (Chr (Base.W32 0x61), (SCon (Chr (Base.W32 0x63), (SCon (Chr (Base.W32 0x63), (SCon (Chr (Base.W32 0x65), (SCon (Chr (Base.W32 0x73), (SCon (Chr (Base.W32 0x73), SNil)))))))))))))))))))))))))), v_adjacent, v_next, v_tail, v_current, v_reversed))) when __nat_3 >= 1 ->
(let v_rest = (__nat_3 - 1) in
(match (C.f_one ((C.f_field_values (v_next) (s_16)))) with
| Fail __error -> Fail __error
| Done v_name ->
(f_collect (v_rest) ((Next (v_tail, (f_atom ((C.Cst (s_14, s_1, s_1, (C.f_offset_of (v_current)), [(f_labelled (v_current) (s_15)); (f_labelled (v_name) (s_16))])))), v_reversed))))))
| (__nat_4, (Step ((SCon (Chr (Base.W32 0x61), (SCon (Chr (Base.W32 0x72), (SCon (Chr (Base.W32 0x72), (SCon (Chr (Base.W32 0x61), (SCon (Chr (Base.W32 0x79), SNil)))))))))), true, v_next, v_tail, v_current, v_reversed))) when __nat_4 >= 1 ->
(let v_rest = (__nat_4 - 1) in
(match (f_index_argument ((C.f_field_values ((f_unwrapped (v_next))) (s_19))) (v_next)) with
| Fail __error -> Fail __error
| Done v_index ->
(f_collect (v_rest) ((Next (v_tail, (f_atom ((C.Cst (s_17, s_1, s_1, (C.f_offset_of (v_current)), [(f_labelled (v_current) (s_15)); (f_labelled (v_index) (s_18))])))), v_reversed))))))
| (__nat_5, (Step ((SCon (Chr (Base.W32 0x67), (SCon (Chr (Base.W32 0x72), (SCon (Chr (Base.W32 0x6f), (SCon (Chr (Base.W32 0x75), (SCon (Chr (Base.W32 0x70), SNil)))))))))), true, v_next, v_tail, v_current, v_reversed))) when __nat_5 >= 1 ->
(let v_rest = (__nat_5 - 1) in
(f_collect (v_rest) ((Next (v_tail, (f_call (v_current) (v_next)), v_reversed)))))
| (__nat_6, (Step (v_kind, v_adjacent, v_next, v_tail, v_current, v_reversed))) when __nat_6 >= 1 ->
(let v_rest = (__nat_6 - 1) in
(f_collect (v_rest) ((Next (v_tail, v_next, (v_current :: v_reversed)))))))
and (* postfix.bend:75 *)
f_application : C.t_Cst -> (M.t_Diagnostic, t_Parts) Base.result_ =
fun v_node ->
(match v_node with
| (C.Cst ((SCon (Chr (Base.W32 0x63), (SCon (Chr (Base.W32 0x61), (SCon (Chr (Base.W32 0x6c), (SCon (Chr (Base.W32 0x6c), (SCon (Chr (Base.W32 0x5f), (SCon (Chr (Base.W32 0x65), (SCon (Chr (Base.W32 0x78), (SCon (Chr (Base.W32 0x70), (SCon (Chr (Base.W32 0x72), (SCon (Chr (Base.W32 0x65), (SCon (Chr (Base.W32 0x73), (SCon (Chr (Base.W32 0x73), (SCon (Chr (Base.W32 0x69), (SCon (Chr (Base.W32 0x6f), (SCon (Chr (Base.W32 0x6e), SNil)))))))))))))))))))))))))))))), v_field, v_text, v_offset, v_children)) ->
(match (C.f_one ((C.f_field_values (v_node) (s_4)))) with
| Fail __error -> Fail __error
| Done v_head ->
(Done ((Parts (v_head, (C.f_field_values (v_node) (s_3)))))))
| v_node ->
(match (C.f_one ((C.f_field_values (v_node) (s_4)))) with
| Fail __error -> Fail __error
| Done v_head ->
(f_collect (65536) ((Next ((C.f_field_values (v_node) (s_3)), v_head, []))))))
and (* postfix.bend:86 *)
f_head : t_Parts -> C.t_Cst =
fun v_parts ->
(let (Parts (v_head, v_arguments)) = v_parts in
v_head)
and (* postfix.bend:90 *)
f_arguments : t_Parts -> (C.t_Cst) list =
fun v_parts ->
(let (Parts (v_head, v_arguments)) = v_parts in
v_arguments)
