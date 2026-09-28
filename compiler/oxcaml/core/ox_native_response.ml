(* Native semantic port of compiler/native_response.bend.

   Source SHA-256: 1c4d41e08fcd0f98db0a8f2bbfb523a939df6410fabe4b399daebf28520d4f24

   Ownership/type arguments are erased; value types are checked by OCaml.

   No Bend interpreter or generated C/JavaScript is linked. *)

open Base

module M = Ox_model

module Const = Ox_const_eval

module Main = Ox_main

type t_Work =
  | Word of Base.word32
  | Natural of int
  | Length of int
  | CheckedLength of bool * int
  | Text of Base.text
  | Characters of Base.text
  | Identity of M.t_TypeId
  | Identities of (M.t_TypeId) list
  | IdentityEntries of (M.t_TypeId) list
  | Row of M.t_EffectRow
  | RowTail of M.t_RowTail
  | Operation of M.t_Operation
  | Operations of (M.t_Operation) list
  | OperationEntries of (M.t_Operation) list
  | Predicate of M.t_Predicate
  | Predicates of (M.t_Predicate) list
  | PredicateEntries of (M.t_Predicate) list
  | Effect of M.t_Effect
  | Effects of (M.t_Effect) list
  | EffectEntries of (M.t_Effect) list
  | TypeValue of M.t_Ty
  | Types of (M.t_Ty) list
  | TypeEntries of (M.t_Ty) list
  | OptionalType of (M.t_Ty) option
  | Pattern of M.t_Pattern
  | Patterns of (M.t_Pattern) list
  | PatternEntries of (M.t_Pattern) list
  | OptionalPattern of (M.t_Pattern) option
  | Operator of M.t_ScalarOp
  | UnaryOperator of M.t_UnaryOp
  | Expression of M.t_Expr
  | Expressions of (M.t_Expr) list
  | ExpressionEntries of (M.t_Expr) list
  | OptionalExpression of (M.t_Expr) option
  | Arms of ((M.t_Expr) M.t_MatchArm) list
  | ArmEntries of ((M.t_Expr) M.t_MatchArm) list
  | Value of Const.t_Value
  | Values of (Const.t_Value) list
  | ValueEntries of (Const.t_Value) list
  | OptionalValue of (Const.t_Value) option
  | Bindings of ((Const.t_Value) Const.t_Binding) list
  | BindingEntries of ((Const.t_Value) Const.t_Binding) list
  | Naturals of (int) list
  | NaturalEntries of (int) list
  | Strings of (Base.text) list
  | StringEntries of (Base.text) list
  | Functions of (M.t_CheckedFunction) list
  | FunctionEntries of (M.t_CheckedFunction) list
  | Analysis of Main.t_Analysis
  | Bytes of (Base.word32) list
  | ByteLength of int
  | ByteWords of (Base.word32) list
  | CheckedBytes of bool * Base.word32 * (Base.word32) list
  | Diagnostic of M.t_Diagnostic

let s_0 = Base.text_of_utf8 "native_protocol"

let s_1 = Base.text_of_utf8 "native_response"

let s_2 = Base.text_of_utf8 "response traversal exceeded its bound"

let s_3 = Base.text_of_utf8 "response exceeds 16M words"

let s_4 = Base.text_of_utf8 "response collection exceeds 16M words"

let s_5 = Base.text_of_utf8 "unspecialized effect operation reached response encoding"

let s_6 = Base.text_of_utf8 "unspecialized effect expression reached response encoding"

let s_7 = Base.text_of_utf8 "internal_error"

let s_8 = Base.text_of_utf8 "const"

let s_9 = Base.text_of_utf8 "A checked constant leaked a block return"

let s_10 = Base.text_of_utf8 "state"

let s_11 = Base.text_of_utf8 "a state reader escaped its resolver"

let s_12 = Base.text_of_utf8 "a state writer escaped its resolver"

let s_13 = Base.text_of_utf8 "A checked constant leaked internal pattern bindings"

let s_14 = Base.text_of_utf8 "A checked constant leaked internal match values"

let s_15 = Base.text_of_utf8 "wasm"

let s_16 = Base.text_of_utf8 "Wasm emitter produced a value outside byte range"

let rec (* native_response.bend:6 *)
f_version : unit -> Base.word32 =
fun () ->
(Base.W32 0xd)
and (* native_response.bend:67 *)
f_protocol_error : Base.text -> M.t_Diagnostic =
fun v_message ->
(M.Diagnostic (s_0, s_1, v_message))
and (* native_response.bend:70 *)
f_bool_word : bool -> Base.word32 =
fun v_value ->
(match v_value with
| false ->
(Base.W32 0x0)
| true ->
(Base.W32 0x1))
and (* native_response.bend:77 *)
f_pack : Base.word32 -> Base.word32 -> Base.word32 -> Base.word32 -> Base.word32 =
fun v_a v_b v_c v_d ->
(Base.u32_or ((Base.u32_or (v_a) ((Base.u32_shln (v_b) (8))))) ((Base.u32_or ((Base.u32_shln (v_c) (16))) ((Base.u32_shln (v_d) (24))))))
and (* native_response.bend:80 *)
f_valid_bytes : Base.word32 -> Base.word32 -> Base.word32 -> Base.word32 -> bool =
fun v_a v_b v_c v_d ->
(Base.bool_and ((Base.bool_and ((Base.u32_is_le (v_a) ((Base.W32 0xff)))) ((Base.u32_is_le (v_b) ((Base.W32 0xff)))))) ((Base.bool_and ((Base.u32_is_le (v_c) ((Base.W32 0xff)))) ((Base.u32_is_le (v_d) ((Base.W32 0xff)))))))
and (* native_response.bend:86 *)
f_encode_work : int -> (t_Work) list -> int -> (Base.word32) list -> (M.t_Diagnostic, (Base.word32) list) Base.result_ =
fun v_fuel v_pending v_remaining v_reversed ->
(match (v_fuel, v_pending, v_remaining) with
| (_, [], _) ->
(Done ((Base.list_reverse (v_reversed))))
| (0, _, _) ->
(Fail ((f_protocol_error (s_2))))
| (__nat_1, ((Word (v_value)) :: v_tail), 0) when __nat_1 >= 1 ->
(let v_rest = (__nat_1 - 1) in
(Fail ((f_protocol_error (s_3)))))
| (__nat_2, ((Word (v_value)) :: v_tail), __nat_3) when __nat_2 >= 1 && __nat_3 >= 1 ->
(let v_rest = (__nat_2 - 1) in
(let v_room = (__nat_3 - 1) in
(f_encode_work (v_rest) (v_tail) (v_room) ((v_value :: v_reversed)))))
| (__nat_4, ((Natural (v_value)) :: v_tail), v_room) when __nat_4 >= 1 ->
(let v_rest = (__nat_4 - 1) in
(f_encode_work (v_rest) (((Word ((Base.u32_from_nat (v_value)))) :: ((Word ((Base.u32_from_nat ((Base.nat_div (v_value) ((Base.nat_mul ((Base.u32_to_nat ((Base.W32 0x10000)))) ((Base.u32_to_nat ((Base.W32 0x10000))))))))))) :: v_tail))) (v_room) (v_reversed)))
| (__nat_5, ((Length (v_value)) :: v_tail), v_room) when __nat_5 >= 1 ->
(let v_rest = (__nat_5 - 1) in
(f_encode_work (v_rest) (((CheckedLength ((Base.nat_is_le (v_value) ((Base.u32_to_nat ((Base.W32 0x1000000))))), v_value)) :: v_tail)) (v_room) (v_reversed)))
| (__nat_6, ((CheckedLength (false, v_value)) :: v_tail), v_room) when __nat_6 >= 1 ->
(let v_rest = (__nat_6 - 1) in
(Fail ((f_protocol_error (s_4)))))
| (__nat_7, ((CheckedLength (true, v_value)) :: v_tail), v_room) when __nat_7 >= 1 ->
(let v_rest = (__nat_7 - 1) in
(f_encode_work (v_rest) (((Word ((Base.u32_from_nat (v_value)))) :: v_tail)) (v_room) (v_reversed)))
| (__nat_8, ((Text (v_value)) :: v_tail), v_room) when __nat_8 >= 1 ->
(let v_rest = (__nat_8 - 1) in
(f_encode_work (v_rest) (((Length ((Base.string_length (v_value)))) :: ((Characters (v_value)) :: v_tail))) (v_room) (v_reversed)))
| (__nat_9, ((Characters (SNil)) :: v_tail), v_room) when __nat_9 >= 1 ->
(let v_rest = (__nat_9 - 1) in
(f_encode_work (v_rest) (v_tail) (v_room) (v_reversed)))
| (__nat_10, ((Characters ((SCon (v_character, v_following)))) :: v_tail), v_room) when __nat_10 >= 1 ->
(let v_rest = (__nat_10 - 1) in
(f_encode_work (v_rest) (((Word ((Base.char_to_u32 (v_character)))) :: ((Characters (v_following)) :: v_tail))) (v_room) (v_reversed)))
| (__nat_11, ((Identity ((M.TypeId (v_module_name, v_declaration)))) :: v_tail), v_room) when __nat_11 >= 1 ->
(let v_rest = (__nat_11 - 1) in
(f_encode_work (v_rest) (((Text (v_module_name)) :: ((Text (v_declaration)) :: v_tail))) (v_room) (v_reversed)))
| (__nat_12, ((Identities (v_values)) :: v_tail), v_room) when __nat_12 >= 1 ->
(let v_rest = (__nat_12 - 1) in
(f_encode_work (v_rest) (((Length ((Base.list_length (v_values)))) :: ((IdentityEntries (v_values)) :: v_tail))) (v_room) (v_reversed)))
| (__nat_13, ((IdentityEntries ([])) :: v_tail), v_room) when __nat_13 >= 1 ->
(let v_rest = (__nat_13 - 1) in
(f_encode_work (v_rest) (v_tail) (v_room) (v_reversed)))
| (__nat_14, ((IdentityEntries ((v_head :: v_following))) :: v_tail), v_room) when __nat_14 >= 1 ->
(let v_rest = (__nat_14 - 1) in
(f_encode_work (v_rest) (((Identity (v_head)) :: ((IdentityEntries (v_following)) :: v_tail))) (v_room) (v_reversed)))
| (__nat_15, ((Row ((M.EffectRow (v_operations, v_tail_value)))) :: v_tail), v_room) when __nat_15 >= 1 ->
(let v_rest = (__nat_15 - 1) in
(f_encode_work (v_rest) (((Identities (v_operations)) :: ((RowTail (v_tail_value)) :: v_tail))) (v_room) (v_reversed)))
| (__nat_16, ((RowTail (M.ClosedRow)) :: v_tail), v_room) when __nat_16 >= 1 ->
(let v_rest = (__nat_16 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x0))) :: v_tail)) (v_room) (v_reversed)))
| (__nat_17, ((RowTail ((M.RowVariable (v_index)))) :: v_tail), v_room) when __nat_17 >= 1 ->
(let v_rest = (__nat_17 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x1))) :: ((Natural (v_index)) :: v_tail))) (v_room) (v_reversed)))
| (__nat_18, ((RowTail ((M.RowParameter (v_index)))) :: v_tail), v_room) when __nat_18 >= 1 ->
(let v_rest = (__nat_18 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x2))) :: ((Natural (v_index)) :: v_tail))) (v_room) (v_reversed)))
| (__nat_19, ((RowTail ((M.FreeRow (v_scope, v_name)))) :: v_tail), v_room) when __nat_19 >= 1 ->
(let v_rest = (__nat_19 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x3))) :: ((Text (v_scope)) :: ((Text (v_name)) :: v_tail)))) (v_room) (v_reversed)))
| (__nat_20, ((Operation ((M.Operation (v_identity, v_parameter, v_result)))) :: v_tail), v_room) when __nat_20 >= 1 ->
(let v_rest = (__nat_20 - 1) in
(f_encode_work (v_rest) (((Identity (v_identity)) :: ((TypeValue (v_parameter)) :: ((TypeValue (v_result)) :: v_tail)))) (v_room) (v_reversed)))
| (__nat_21, ((Operation (v_other)) :: v_tail), v_room) when __nat_21 >= 1 ->
(let v_rest = (__nat_21 - 1) in
(Fail ((f_protocol_error (s_5)))))
| (__nat_22, ((Operations (v_values)) :: v_tail), v_room) when __nat_22 >= 1 ->
(let v_rest = (__nat_22 - 1) in
(f_encode_work (v_rest) (((Length ((Base.list_length (v_values)))) :: ((OperationEntries (v_values)) :: v_tail))) (v_room) (v_reversed)))
| (__nat_23, ((OperationEntries ([])) :: v_tail), v_room) when __nat_23 >= 1 ->
(let v_rest = (__nat_23 - 1) in
(f_encode_work (v_rest) (v_tail) (v_room) (v_reversed)))
| (__nat_24, ((OperationEntries ((v_head :: v_following))) :: v_tail), v_room) when __nat_24 >= 1 ->
(let v_rest = (__nat_24 - 1) in
(f_encode_work (v_rest) (((Operation (v_head)) :: ((OperationEntries (v_following)) :: v_tail))) (v_room) (v_reversed)))
| (__nat_25, ((Effect ((M.OperationEffect (v_identity)))) :: v_tail), v_room) when __nat_25 >= 1 ->
(let v_rest = (__nat_25 - 1) in
(f_encode_work (v_rest) (((Identity (v_identity)) :: v_tail)) (v_room) (v_reversed)))
| (__nat_26, ((Effects (v_values)) :: v_tail), v_room) when __nat_26 >= 1 ->
(let v_rest = (__nat_26 - 1) in
(f_encode_work (v_rest) (((Length ((Base.list_length (v_values)))) :: ((EffectEntries (v_values)) :: v_tail))) (v_room) (v_reversed)))
| (__nat_27, ((EffectEntries ([])) :: v_tail), v_room) when __nat_27 >= 1 ->
(let v_rest = (__nat_27 - 1) in
(f_encode_work (v_rest) (v_tail) (v_room) (v_reversed)))
| (__nat_28, ((EffectEntries ((v_head :: v_following))) :: v_tail), v_room) when __nat_28 >= 1 ->
(let v_rest = (__nat_28 - 1) in
(f_encode_work (v_rest) (((Effect (v_head)) :: ((EffectEntries (v_following)) :: v_tail))) (v_room) (v_reversed)))
| (__nat_29, ((TypeValue (M.UnitTy)) :: v_tail), v_room) when __nat_29 >= 1 ->
(let v_rest = (__nat_29 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x0))) :: v_tail)) (v_room) (v_reversed)))
| (__nat_30, ((TypeValue (M.U32Ty)) :: v_tail), v_room) when __nat_30 >= 1 ->
(let v_rest = (__nat_30 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x1))) :: v_tail)) (v_room) (v_reversed)))
| (__nat_31, ((TypeValue (M.BoolTy)) :: v_tail), v_room) when __nat_31 >= 1 ->
(let v_rest = (__nat_31 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x2))) :: v_tail)) (v_room) (v_reversed)))
| (__nat_32, ((TypeValue ((M.AppliedTy (v_identity, v_arguments)))) :: v_tail), v_room) when __nat_32 >= 1 ->
(let v_rest = (__nat_32 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x3))) :: ((Identity (v_identity)) :: ((Types (v_arguments)) :: v_tail)))) (v_room) (v_reversed)))
| (__nat_33, ((TypeValue ((M.FunctionTy (v_parameter, v_result, v_effects)))) :: v_tail), v_room) when __nat_33 >= 1 ->
(let v_rest = (__nat_33 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x4))) :: ((TypeValue (v_parameter)) :: ((TypeValue (v_result)) :: ((Row (v_effects)) :: v_tail))))) (v_room) (v_reversed)))
| (__nat_34, ((TypeValue ((M.FreeTy (v_scope, v_name)))) :: v_tail), v_room) when __nat_34 >= 1 ->
(let v_rest = (__nat_34 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0xf))) :: ((Text (v_scope)) :: ((Text (v_name)) :: v_tail)))) (v_room) (v_reversed)))
| (__nat_35, ((TypeValue ((M.ParameterTy (v_index)))) :: v_tail), v_room) when __nat_35 >= 1 ->
(let v_rest = (__nat_35 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x5))) :: ((Natural (v_index)) :: v_tail))) (v_room) (v_reversed)))
| (__nat_36, ((TypeValue ((M.VariableTy (v_index)))) :: v_tail), v_room) when __nat_36 >= 1 ->
(let v_rest = (__nat_36 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x6))) :: ((Natural (v_index)) :: v_tail))) (v_room) (v_reversed)))
| (__nat_37, ((TypeValue (M.NeverTy)) :: v_tail), v_room) when __nat_37 >= 1 ->
(let v_rest = (__nat_37 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x7))) :: v_tail)) (v_room) (v_reversed)))
| (__nat_38, ((TypeValue (M.F32Ty)) :: v_tail), v_room) when __nat_38 >= 1 ->
(let v_rest = (__nat_38 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x8))) :: v_tail)) (v_room) (v_reversed)))
| (__nat_39, ((TypeValue ((M.StateProviderTy (v_read, v_write, v_state)))) :: v_tail), v_room) when __nat_39 >= 1 ->
(let v_rest = (__nat_39 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0xe))) :: ((Identity (v_read)) :: ((Identity (v_write)) :: ((TypeValue (v_state)) :: v_tail))))) (v_room) (v_reversed)))
| (__nat_40, ((TypeValue ((M.ProviderTy (v_identity, v_effects)))) :: v_tail), v_room) when __nat_40 >= 1 ->
(let v_rest = (__nat_40 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x9))) :: ((Identity (v_identity)) :: ((Row (v_effects)) :: v_tail)))) (v_room) (v_reversed)))
| (__nat_41, ((TypeValue (M.EffectDescriptorTy)) :: v_tail), v_room) when __nat_41 >= 1 ->
(let v_rest = (__nat_41 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0xa))) :: v_tail)) (v_room) (v_reversed)))
| (__nat_42, ((TypeValue (M.EffectSetTy)) :: v_tail), v_room) when __nat_42 >= 1 ->
(let v_rest = (__nat_42 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0xb))) :: v_tail)) (v_room) (v_reversed)))
| (__nat_43, ((TypeValue ((M.ProductTy (v_elements)))) :: v_tail), v_room) when __nat_43 >= 1 ->
(let v_rest = (__nat_43 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0xc))) :: ((Types (v_elements)) :: v_tail))) (v_room) (v_reversed)))
| (__nat_44, ((TypeValue ((M.ArrayTy (v_element)))) :: v_tail), v_room) when __nat_44 >= 1 ->
(let v_rest = (__nat_44 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0xd))) :: ((TypeValue (v_element)) :: v_tail))) (v_room) (v_reversed)))
| (__nat_45, ((Types (v_values)) :: v_tail), v_room) when __nat_45 >= 1 ->
(let v_rest = (__nat_45 - 1) in
(f_encode_work (v_rest) (((Length ((Base.list_length (v_values)))) :: ((TypeEntries (v_values)) :: v_tail))) (v_room) (v_reversed)))
| (__nat_46, ((TypeEntries ([])) :: v_tail), v_room) when __nat_46 >= 1 ->
(let v_rest = (__nat_46 - 1) in
(f_encode_work (v_rest) (v_tail) (v_room) (v_reversed)))
| (__nat_47, ((TypeEntries ((v_head :: v_following))) :: v_tail), v_room) when __nat_47 >= 1 ->
(let v_rest = (__nat_47 - 1) in
(f_encode_work (v_rest) (((TypeValue (v_head)) :: ((TypeEntries (v_following)) :: v_tail))) (v_room) (v_reversed)))
| (__nat_48, ((OptionalType (None)) :: v_tail), v_room) when __nat_48 >= 1 ->
(let v_rest = (__nat_48 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x0))) :: v_tail)) (v_room) (v_reversed)))
| (__nat_49, ((OptionalType ((Some (v_value)))) :: v_tail), v_room) when __nat_49 >= 1 ->
(let v_rest = (__nat_49 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x1))) :: ((TypeValue (v_value)) :: v_tail))) (v_room) (v_reversed)))
| (__nat_50, ((Predicates (v_values)) :: v_tail), v_room) when __nat_50 >= 1 ->
(let v_rest = (__nat_50 - 1) in
(f_encode_work (v_rest) (((Length ((Base.list_length (v_values)))) :: ((PredicateEntries (v_values)) :: v_tail))) (v_room) (v_reversed)))
| (__nat_51, ((PredicateEntries ([])) :: v_tail), v_room) when __nat_51 >= 1 ->
(let v_rest = (__nat_51 - 1) in
(f_encode_work (v_rest) (v_tail) (v_room) (v_reversed)))
| (__nat_52, ((PredicateEntries ((v_head :: v_following))) :: v_tail), v_room) when __nat_52 >= 1 ->
(let v_rest = (__nat_52 - 1) in
(f_encode_work (v_rest) (((Predicate (v_head)) :: ((PredicateEntries (v_following)) :: v_tail))) (v_room) (v_reversed)))
| (__nat_53, ((Predicate ((M.AssociatedPredicate (v_member, v_templates, v_left, v_right, v_result, v_invocation)))) :: v_tail), v_room) when __nat_53 >= 1 ->
(let v_rest = (__nat_53 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x0))) :: ((Text (v_member)) :: ((Identities (v_templates)) :: ((TypeValue (v_left)) :: ((TypeValue (v_right)) :: ((TypeValue (v_result)) :: ((Row (v_invocation)) :: v_tail)))))))) (v_room) (v_reversed)))
| (__nat_54, ((Predicate ((M.ReceiverPredicate (v_member, v_templates, v_receiver, v_argument, v_result, v_invocation)))) :: v_tail), v_room) when __nat_54 >= 1 ->
(let v_rest = (__nat_54 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x1))) :: ((Text (v_member)) :: ((Identities (v_templates)) :: ((TypeValue (v_receiver)) :: ((TypeValue (v_argument)) :: ((TypeValue (v_result)) :: ((Row (v_invocation)) :: v_tail)))))))) (v_room) (v_reversed)))
| (__nat_55, ((Predicate ((M.FieldPredicate (v_member, v_receiver, v_result)))) :: v_tail), v_room) when __nat_55 >= 1 ->
(let v_rest = (__nat_55 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x2))) :: ((Text (v_member)) :: ((TypeValue (v_receiver)) :: ((TypeValue (v_result)) :: v_tail))))) (v_room) (v_reversed)))
| (__nat_56, ((Predicate ((M.UpdatePredicate (v_member, v_receiver, v_assigned, v_result, v_invocation)))) :: v_tail), v_room) when __nat_56 >= 1 ->
(let v_rest = (__nat_56 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x3))) :: ((Text (v_member)) :: ((TypeValue (v_receiver)) :: ((TypeValue (v_assigned)) :: ((TypeValue (v_result)) :: ((Row (v_invocation)) :: v_tail))))))) (v_room) (v_reversed)))
| (__nat_57, ((Predicate ((M.OperationPredicate (v_template, v_arguments, v_function_type)))) :: v_tail), v_room) when __nat_57 >= 1 ->
(let v_rest = (__nat_57 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x4))) :: ((Identity (v_template)) :: ((Types (v_arguments)) :: ((TypeValue (v_function_type)) :: v_tail))))) (v_room) (v_reversed)))
| (__nat_58, ((Predicate ((M.TypeRepPredicate (v_represented)))) :: v_tail), v_room) when __nat_58 >= 1 ->
(let v_rest = (__nat_58 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x5))) :: ((TypeValue (v_represented)) :: v_tail))) (v_room) (v_reversed)))
| (__nat_59, ((Predicate ((M.EffectRepPredicate (v_row)))) :: v_tail), v_room) when __nat_59 >= 1 ->
(let v_rest = (__nat_59 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x6))) :: ((Row (v_row)) :: v_tail))) (v_room) (v_reversed)))
| (__nat_60, ((Patterns (v_values)) :: v_tail), v_room) when __nat_60 >= 1 ->
(let v_rest = (__nat_60 - 1) in
(f_encode_work (v_rest) (((Length ((Base.list_length (v_values)))) :: ((PatternEntries (v_values)) :: v_tail))) (v_room) (v_reversed)))
| (__nat_61, ((PatternEntries ((v_head :: v_following))) :: v_tail), v_room) when __nat_61 >= 1 ->
(let v_rest = (__nat_61 - 1) in
(f_encode_work (v_rest) (((Pattern (v_head)) :: ((PatternEntries (v_following)) :: v_tail))) (v_room) (v_reversed)))
| (__nat_62, ((PatternEntries ([])) :: v_tail), v_room) when __nat_62 >= 1 ->
(let v_rest = (__nat_62 - 1) in
(f_encode_work (v_rest) (v_tail) (v_room) (v_reversed)))
| (__nat_63, ((Pattern (M.WildcardPattern)) :: v_tail), v_room) when __nat_63 >= 1 ->
(let v_rest = (__nat_63 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x0))) :: v_tail)) (v_room) (v_reversed)))
| (__nat_64, ((Pattern ((M.BindingPattern (v_name)))) :: v_tail), v_room) when __nat_64 >= 1 ->
(let v_rest = (__nat_64 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x1))) :: ((Text (v_name)) :: v_tail))) (v_room) (v_reversed)))
| (__nat_65, ((Pattern (M.UnitPattern)) :: v_tail), v_room) when __nat_65 >= 1 ->
(let v_rest = (__nat_65 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x2))) :: v_tail)) (v_room) (v_reversed)))
| (__nat_66, ((Pattern ((M.U32Pattern (v_value)))) :: v_tail), v_room) when __nat_66 >= 1 ->
(let v_rest = (__nat_66 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x3))) :: ((Word (v_value)) :: v_tail))) (v_room) (v_reversed)))
| (__nat_67, ((Pattern ((M.BoolPattern (v_value)))) :: v_tail), v_room) when __nat_67 >= 1 ->
(let v_rest = (__nat_67 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x4))) :: ((Word ((f_bool_word (v_value)))) :: v_tail))) (v_room) (v_reversed)))
| (__nat_68, ((Pattern ((M.ConstructorPattern (v_constructor, v_payload)))) :: v_tail), v_room) when __nat_68 >= 1 ->
(let v_rest = (__nat_68 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x5))) :: ((Text (v_constructor)) :: ((OptionalPattern (v_payload)) :: v_tail)))) (v_room) (v_reversed)))
| (__nat_69, ((Pattern ((M.ProductPattern (v_elements)))) :: v_tail), v_room) when __nat_69 >= 1 ->
(let v_rest = (__nat_69 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x6))) :: ((Patterns (v_elements)) :: v_tail))) (v_room) (v_reversed)))
| (__nat_70, ((Pattern ((M.ValuePattern ((M.LocalReference (v_name)))))) :: v_tail), v_room) when __nat_70 >= 1 ->
(let v_rest = (__nat_70 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x7))) :: ((Word ((Base.W32 0x0))) :: ((Text (v_name)) :: v_tail)))) (v_room) (v_reversed)))
| (__nat_71, ((Pattern ((M.ValuePattern ((M.ConstantReference (v_name)))))) :: v_tail), v_room) when __nat_71 >= 1 ->
(let v_rest = (__nat_71 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x7))) :: ((Word ((Base.W32 0x1))) :: ((Text (v_name)) :: v_tail)))) (v_room) (v_reversed)))
| (__nat_72, ((OptionalPattern (None)) :: v_tail), v_room) when __nat_72 >= 1 ->
(let v_rest = (__nat_72 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x0))) :: v_tail)) (v_room) (v_reversed)))
| (__nat_73, ((OptionalPattern ((Some (v_value)))) :: v_tail), v_room) when __nat_73 >= 1 ->
(let v_rest = (__nat_73 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x1))) :: ((Pattern (v_value)) :: v_tail))) (v_room) (v_reversed)))
| (__nat_74, ((Operator (M.Add)) :: v_tail), v_room) when __nat_74 >= 1 ->
(let v_rest = (__nat_74 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x0))) :: v_tail)) (v_room) (v_reversed)))
| (__nat_75, ((Operator (M.Subtract)) :: v_tail), v_room) when __nat_75 >= 1 ->
(let v_rest = (__nat_75 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x1))) :: v_tail)) (v_room) (v_reversed)))
| (__nat_76, ((Operator (M.Multiply)) :: v_tail), v_room) when __nat_76 >= 1 ->
(let v_rest = (__nat_76 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x2))) :: v_tail)) (v_room) (v_reversed)))
| (__nat_77, ((Operator (M.Equal)) :: v_tail), v_room) when __nat_77 >= 1 ->
(let v_rest = (__nat_77 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x3))) :: v_tail)) (v_room) (v_reversed)))
| (__nat_78, ((Operator (M.LessThan)) :: v_tail), v_room) when __nat_78 >= 1 ->
(let v_rest = (__nat_78 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x4))) :: v_tail)) (v_room) (v_reversed)))
| (__nat_79, ((Operator (M.F32Add)) :: v_tail), v_room) when __nat_79 >= 1 ->
(let v_rest = (__nat_79 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x5))) :: v_tail)) (v_room) (v_reversed)))
| (__nat_80, ((Operator (M.F32Subtract)) :: v_tail), v_room) when __nat_80 >= 1 ->
(let v_rest = (__nat_80 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x6))) :: v_tail)) (v_room) (v_reversed)))
| (__nat_81, ((Operator (M.F32Multiply)) :: v_tail), v_room) when __nat_81 >= 1 ->
(let v_rest = (__nat_81 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x7))) :: v_tail)) (v_room) (v_reversed)))
| (__nat_82, ((Operator (M.F32Divide)) :: v_tail), v_room) when __nat_82 >= 1 ->
(let v_rest = (__nat_82 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x8))) :: v_tail)) (v_room) (v_reversed)))
| (__nat_83, ((Operator (M.F32Equal)) :: v_tail), v_room) when __nat_83 >= 1 ->
(let v_rest = (__nat_83 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x9))) :: v_tail)) (v_room) (v_reversed)))
| (__nat_84, ((Operator (M.F32NotEqual)) :: v_tail), v_room) when __nat_84 >= 1 ->
(let v_rest = (__nat_84 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0xa))) :: v_tail)) (v_room) (v_reversed)))
| (__nat_85, ((Operator (M.F32LessThan)) :: v_tail), v_room) when __nat_85 >= 1 ->
(let v_rest = (__nat_85 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0xb))) :: v_tail)) (v_room) (v_reversed)))
| (__nat_86, ((Operator (M.F32LessEqual)) :: v_tail), v_room) when __nat_86 >= 1 ->
(let v_rest = (__nat_86 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0xc))) :: v_tail)) (v_room) (v_reversed)))
| (__nat_87, ((Operator (M.F32GreaterThan)) :: v_tail), v_room) when __nat_87 >= 1 ->
(let v_rest = (__nat_87 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0xd))) :: v_tail)) (v_room) (v_reversed)))
| (__nat_88, ((Operator (M.F32GreaterEqual)) :: v_tail), v_room) when __nat_88 >= 1 ->
(let v_rest = (__nat_88 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0xe))) :: v_tail)) (v_room) (v_reversed)))
| (__nat_89, ((UnaryOperator (M.F32Negate)) :: v_tail), v_room) when __nat_89 >= 1 ->
(let v_rest = (__nat_89 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x0))) :: v_tail)) (v_room) (v_reversed)))
| (__nat_90, ((UnaryOperator (M.F32Absolute)) :: v_tail), v_room) when __nat_90 >= 1 ->
(let v_rest = (__nat_90 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x1))) :: v_tail)) (v_room) (v_reversed)))
| (__nat_91, ((UnaryOperator (M.F32SquareRoot)) :: v_tail), v_room) when __nat_91 >= 1 ->
(let v_rest = (__nat_91 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x2))) :: v_tail)) (v_room) (v_reversed)))
| (__nat_92, ((UnaryOperator (M.F32Floor)) :: v_tail), v_room) when __nat_92 >= 1 ->
(let v_rest = (__nat_92 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x3))) :: v_tail)) (v_room) (v_reversed)))
| (__nat_93, ((UnaryOperator (M.F32Ceiling)) :: v_tail), v_room) when __nat_93 >= 1 ->
(let v_rest = (__nat_93 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x4))) :: v_tail)) (v_room) (v_reversed)))
| (__nat_94, ((UnaryOperator (M.F32Truncate)) :: v_tail), v_room) when __nat_94 >= 1 ->
(let v_rest = (__nat_94 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x5))) :: v_tail)) (v_room) (v_reversed)))
| (__nat_95, ((UnaryOperator (M.U32ToF32)) :: v_tail), v_room) when __nat_95 >= 1 ->
(let v_rest = (__nat_95 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x6))) :: v_tail)) (v_room) (v_reversed)))
| (__nat_96, ((UnaryOperator (M.F32ToU32)) :: v_tail), v_room) when __nat_96 >= 1 ->
(let v_rest = (__nat_96 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x7))) :: v_tail)) (v_room) (v_reversed)))
| (__nat_97, ((Expression (M.UnitExpr)) :: v_tail), v_room) when __nat_97 >= 1 ->
(let v_rest = (__nat_97 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x0))) :: v_tail)) (v_room) (v_reversed)))
| (__nat_98, ((Expression ((M.U32Expr (v_value)))) :: v_tail), v_room) when __nat_98 >= 1 ->
(let v_rest = (__nat_98 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x1))) :: ((Word (v_value)) :: v_tail))) (v_room) (v_reversed)))
| (__nat_99, ((Expression ((M.BoolExpr (v_value)))) :: v_tail), v_room) when __nat_99 >= 1 ->
(let v_rest = (__nat_99 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x2))) :: ((Word ((f_bool_word (v_value)))) :: v_tail))) (v_room) (v_reversed)))
| (__nat_100, ((Expression ((M.LocalExpr (v_name)))) :: v_tail), v_room) when __nat_100 >= 1 ->
(let v_rest = (__nat_100 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x3))) :: ((Text (v_name)) :: v_tail))) (v_room) (v_reversed)))
| (__nat_101, ((Expression ((M.ConstantExpr (v_name)))) :: v_tail), v_room) when __nat_101 >= 1 ->
(let v_rest = (__nat_101 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x4))) :: ((Text (v_name)) :: v_tail))) (v_room) (v_reversed)))
| (__nat_102, ((Expression ((M.FunctionExpr (v_name)))) :: v_tail), v_room) when __nat_102 >= 1 ->
(let v_rest = (__nat_102 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x5))) :: ((Text (v_name)) :: v_tail))) (v_room) (v_reversed)))
| (__nat_103, ((Expression ((M.ConstructorRefExpr (v_constructor)))) :: v_tail), v_room) when __nat_103 >= 1 ->
(let v_rest = (__nat_103 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x6))) :: ((Text (v_constructor)) :: v_tail))) (v_room) (v_reversed)))
| (__nat_104, ((Expression ((M.ConstructExpr (v_constructor, v_payload)))) :: v_tail), v_room) when __nat_104 >= 1 ->
(let v_rest = (__nat_104 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x7))) :: ((Text (v_constructor)) :: ((OptionalExpression (v_payload)) :: v_tail)))) (v_room) (v_reversed)))
| (__nat_105, ((Expression ((M.LambdaExpr (v_identity, v_parameter, v_parameter_type, v_result_type, v_body)))) :: v_tail), v_room) when __nat_105 >= 1 ->
(let v_rest = (__nat_105 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x8))) :: ((Natural (v_identity)) :: ((Text (v_parameter)) :: ((OptionalType (v_parameter_type)) :: ((OptionalType (v_result_type)) :: ((Expression (v_body)) :: v_tail))))))) (v_room) (v_reversed)))
| (__nat_106, ((Expression ((M.ApplyExpr (v_callee, v_argument)))) :: v_tail), v_room) when __nat_106 >= 1 ->
(let v_rest = (__nat_106 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x9))) :: ((Expression (v_callee)) :: ((Expression (v_argument)) :: v_tail)))) (v_room) (v_reversed)))
| (__nat_107, ((Expression ((M.TagExpr (v_offset, v_callee, v_argument)))) :: v_tail), v_room) when __nat_107 >= 1 ->
(let v_rest = (__nat_107 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x2d))) :: ((Natural (v_offset)) :: ((Expression (v_callee)) :: ((Expression (v_argument)) :: v_tail))))) (v_room) (v_reversed)))
| (__nat_108, ((Expression ((M.CallExpr (v_callee, v_argument)))) :: v_tail), v_room) when __nat_108 >= 1 ->
(let v_rest = (__nat_108 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0xa))) :: ((Text (v_callee)) :: ((Expression (v_argument)) :: v_tail)))) (v_room) (v_reversed)))
| (__nat_109, ((Expression ((M.ScalarExpr (v_operator, v_left, v_right)))) :: v_tail), v_room) when __nat_109 >= 1 ->
(let v_rest = (__nat_109 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0xb))) :: ((Operator (v_operator)) :: ((Expression (v_left)) :: ((Expression (v_right)) :: v_tail))))) (v_room) (v_reversed)))
| (__nat_110, ((Expression ((M.LetExpr (v_name, v_value, v_body)))) :: v_tail), v_room) when __nat_110 >= 1 ->
(let v_rest = (__nat_110 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0xc))) :: ((Text (v_name)) :: ((Expression (v_value)) :: ((Expression (v_body)) :: v_tail))))) (v_room) (v_reversed)))
| (__nat_111, ((Expression ((M.UseExpr (v_name, v_value, v_body)))) :: v_tail), v_room) when __nat_111 >= 1 ->
(let v_rest = (__nat_111 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0xd))) :: ((Text (v_name)) :: ((Expression (v_value)) :: ((Expression (v_body)) :: v_tail))))) (v_room) (v_reversed)))
| (__nat_112, ((Expression ((M.IfExpr (v_condition, v_consequent, v_alternative)))) :: v_tail), v_room) when __nat_112 >= 1 ->
(let v_rest = (__nat_112 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0xe))) :: ((Expression (v_condition)) :: ((Expression (v_consequent)) :: ((Expression (v_alternative)) :: v_tail))))) (v_room) (v_reversed)))
| (__nat_113, ((Expression ((M.SequenceExpr (v_first, v_next)))) :: v_tail), v_room) when __nat_113 >= 1 ->
(let v_rest = (__nat_113 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0xf))) :: ((Expression (v_first)) :: ((Expression (v_next)) :: v_tail)))) (v_room) (v_reversed)))
| (__nat_114, ((Expression ((M.MatchExpr (v_values, v_arms)))) :: v_tail), v_room) when __nat_114 >= 1 ->
(let v_rest = (__nat_114 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x10))) :: ((Expressions (v_values)) :: ((Arms (v_arms)) :: v_tail)))) (v_room) (v_reversed)))
| (__nat_115, ((Expression ((M.GuardExpr (v_pattern, v_value, v_alternative, v_body)))) :: v_tail), v_room) when __nat_115 >= 1 ->
(let v_rest = (__nat_115 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x11))) :: ((Pattern (v_pattern)) :: ((Expression (v_value)) :: ((Expression (v_alternative)) :: ((Expression (v_body)) :: v_tail)))))) (v_room) (v_reversed)))
| (__nat_116, ((Expression ((M.BlockExpr (v_label, v_body)))) :: v_tail), v_room) when __nat_116 >= 1 ->
(let v_rest = (__nat_116 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x12))) :: ((Natural (v_label)) :: ((Expression (v_body)) :: v_tail)))) (v_room) (v_reversed)))
| (__nat_117, ((Expression ((M.ReturnExpr (v_label, v_value)))) :: v_tail), v_room) when __nat_117 >= 1 ->
(let v_rest = (__nat_117 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x13))) :: ((Natural (v_label)) :: ((Expression (v_value)) :: v_tail)))) (v_room) (v_reversed)))
| (__nat_118, ((Expression ((M.RuntimeInitExpr (v_value)))) :: v_tail), v_room) when __nat_118 >= 1 ->
(let v_rest = (__nat_118 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x2c))) :: ((Expression (v_value)) :: v_tail))) (v_room) (v_reversed)))
| (__nat_119, ((Expression ((M.SourceExpr (v_offset, v_annotation, v_value)))) :: v_tail), v_room) when __nat_119 >= 1 ->
(let v_rest = (__nat_119 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x14))) :: ((Natural (v_offset)) :: ((OptionalType (v_annotation)) :: ((Expression (v_value)) :: v_tail))))) (v_room) (v_reversed)))
| (__nat_120, ((Expression ((M.QualifiedExpr (v_offset, v_annotation, v_predicates, v_value)))) :: v_tail), v_room) when __nat_120 >= 1 ->
(let v_rest = (__nat_120 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x2f))) :: ((Natural (v_offset)) :: ((TypeValue (v_annotation)) :: ((Predicates (v_predicates)) :: ((Expression (v_value)) :: v_tail)))))) (v_room) (v_reversed)))
| (__nat_121, ((Expression ((M.InstantiationExpr (v_site, v_value)))) :: v_tail), v_room) when __nat_121 >= 1 ->
(let v_rest = (__nat_121 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x30))) :: ((Natural (v_site)) :: ((Expression (v_value)) :: v_tail)))) (v_room) (v_reversed)))
| (__nat_122, ((Expression ((M.F32Expr (v_value)))) :: v_tail), v_room) when __nat_122 >= 1 ->
(let v_rest = (__nat_122 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x15))) :: ((Word ((Base.f32_bits (v_value)))) :: v_tail))) (v_room) (v_reversed)))
| (__nat_123, ((Expression ((M.UnaryExpr (v_operator, v_value)))) :: v_tail), v_room) when __nat_123 >= 1 ->
(let v_rest = (__nat_123 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x16))) :: ((UnaryOperator (v_operator)) :: ((Expression (v_value)) :: v_tail)))) (v_room) (v_reversed)))
| (__nat_124, ((Expression ((M.PanicExpr (v_message)))) :: v_tail), v_room) when __nat_124 >= 1 ->
(let v_rest = (__nat_124 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x17))) :: ((Text (v_message)) :: v_tail))) (v_room) (v_reversed)))
| (__nat_125, ((Expression ((M.OperationExpr (v_identity)))) :: v_tail), v_room) when __nat_125 >= 1 ->
(let v_rest = (__nat_125 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x18))) :: ((Identity (v_identity)) :: v_tail))) (v_room) (v_reversed)))
| (__nat_126, ((Expression ((M.SpecializeOperationExpr (v_template, v_arguments, v_body)))) :: v_tail), v_room) when __nat_126 >= 1 ->
(let v_rest = (__nat_126 - 1) in
(Fail ((f_protocol_error (s_6)))))
| (__nat_127, ((Expression ((M.StateProviderExpr (v_read, v_write, v_initial)))) :: v_tail), v_room) when __nat_127 >= 1 ->
(let v_rest = (__nat_127 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x2a))) :: ((Identity (v_read)) :: ((Identity (v_write)) :: ((Expression (v_initial)) :: v_tail))))) (v_room) (v_reversed)))
| (__nat_128, ((Expression ((M.ProviderExpr (v_identity, v_implementation)))) :: v_tail), v_room) when __nat_128 >= 1 ->
(let v_rest = (__nat_128 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x19))) :: ((Identity (v_identity)) :: ((Expression (v_implementation)) :: v_tail)))) (v_room) (v_reversed)))
| (__nat_129, ((Expression ((M.HandleExpr (v_provider, v_body)))) :: v_tail), v_room) when __nat_129 >= 1 ->
(let v_rest = (__nat_129 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x1a))) :: ((Expression (v_provider)) :: ((Expression (v_body)) :: v_tail)))) (v_room) (v_reversed)))
| (__nat_130, ((Expression ((M.OperationDescriptorExpr (v_identity)))) :: v_tail), v_room) when __nat_130 >= 1 ->
(let v_rest = (__nat_130 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x1b))) :: ((Identity (v_identity)) :: v_tail))) (v_room) (v_reversed)))
| (__nat_131, ((Expression ((M.FunctionEffectsExpr (v_callee)))) :: v_tail), v_room) when __nat_131 >= 1 ->
(let v_rest = (__nat_131 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x1c))) :: ((Text (v_callee)) :: v_tail))) (v_room) (v_reversed)))
| (__nat_132, ((Expression ((M.EffectHasExpr (v_set, v_operation)))) :: v_tail), v_room) when __nat_132 >= 1 ->
(let v_rest = (__nat_132 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x1d))) :: ((Expression (v_set)) :: ((Expression (v_operation)) :: v_tail)))) (v_room) (v_reversed)))
| (__nat_133, ((Expression ((M.EffectCountExpr (v_set)))) :: v_tail), v_room) when __nat_133 >= 1 ->
(let v_rest = (__nat_133 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x1e))) :: ((Expression (v_set)) :: v_tail))) (v_room) (v_reversed)))
| (__nat_134, ((Expression ((M.EffectSameExpr (v_left, v_right)))) :: v_tail), v_room) when __nat_134 >= 1 ->
(let v_rest = (__nat_134 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x1f))) :: ((Expression (v_left)) :: ((Expression (v_right)) :: v_tail)))) (v_room) (v_reversed)))
| (__nat_135, ((Expression ((M.ProductExpr (v_elements)))) :: v_tail), v_room) when __nat_135 >= 1 ->
(let v_rest = (__nat_135 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x20))) :: ((Expressions (v_elements)) :: v_tail))) (v_room) (v_reversed)))
| (__nat_136, ((Expression ((M.ProjectExpr (v_value, v_index)))) :: v_tail), v_room) when __nat_136 >= 1 ->
(let v_rest = (__nat_136 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x21))) :: ((Expression (v_value)) :: ((Natural (v_index)) :: v_tail)))) (v_room) (v_reversed)))
| (__nat_137, ((Expression ((M.ArrayExpr (v_elements)))) :: v_tail), v_room) when __nat_137 >= 1 ->
(let v_rest = (__nat_137 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x22))) :: ((Expressions (v_elements)) :: v_tail))) (v_room) (v_reversed)))
| (__nat_138, ((Expression ((M.ForExpr (v_index, v_start, v_end, v_state, v_initial, v_body)))) :: v_tail), v_room) when __nat_138 >= 1 ->
(let v_rest = (__nat_138 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x29))) :: ((Text (v_index)) :: ((Expression (v_start)) :: ((Expression (v_end)) :: ((Text (v_state)) :: ((Expression (v_initial)) :: ((Expression (v_body)) :: v_tail)))))))) (v_room) (v_reversed)))
| (__nat_139, ((Expression ((M.ForeverExpr (v_state, v_initial, v_body)))) :: v_tail), v_room) when __nat_139 >= 1 ->
(let v_rest = (__nat_139 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x2e))) :: ((Text (v_state)) :: ((Expression (v_initial)) :: ((Expression (v_body)) :: v_tail))))) (v_room) (v_reversed)))
| (__nat_140, ((Expression ((M.ArrayGenerateExpr (v_count, v_generator)))) :: v_tail), v_room) when __nat_140 >= 1 ->
(let v_rest = (__nat_140 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x27))) :: ((Expression (v_count)) :: ((Expression (v_generator)) :: v_tail)))) (v_room) (v_reversed)))
| (__nat_141, ((Expression ((M.ArrayFillExpr (v_count, v_value)))) :: v_tail), v_room) when __nat_141 >= 1 ->
(let v_rest = (__nat_141 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x26))) :: ((Expression (v_count)) :: ((Expression (v_value)) :: v_tail)))) (v_room) (v_reversed)))
| (__nat_142, ((Expression ((M.ArrayGetExpr (v_array, v_index)))) :: v_tail), v_room) when __nat_142 >= 1 ->
(let v_rest = (__nat_142 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x23))) :: ((Expression (v_array)) :: ((Expression (v_index)) :: v_tail)))) (v_room) (v_reversed)))
| (__nat_143, ((Expression ((M.ArraySetExpr (v_array, v_index, v_value)))) :: v_tail), v_room) when __nat_143 >= 1 ->
(let v_rest = (__nat_143 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x24))) :: ((Expression (v_array)) :: ((Expression (v_index)) :: ((Expression (v_value)) :: v_tail))))) (v_room) (v_reversed)))
| (__nat_144, ((Expression ((M.AssociatedExpr (v_identity, v_dispatch, v_member, v_templates, v_left, v_right)))) :: v_tail), v_room) when __nat_144 >= 1 ->
(let v_rest = (__nat_144 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x28))) :: ((Natural (v_identity)) :: ((Text (v_member)) :: ((Expression (v_left)) :: ((Expression (v_right)) :: v_tail)))))) (v_room) (v_reversed)))
| (__nat_145, ((Expression ((M.GenericOperationExpr (v_identity, v_template, v_arguments)))) :: v_tail), v_room) when __nat_145 >= 1 ->
(let v_rest = (__nat_145 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x2b))) :: ((Natural (v_identity)) :: ((Identity (v_template)) :: ((Types (v_arguments)) :: v_tail))))) (v_room) (v_reversed)))
| (__nat_146, ((Expression ((M.ArrayLengthExpr (v_array)))) :: v_tail), v_room) when __nat_146 >= 1 ->
(let v_rest = (__nat_146 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x25))) :: ((Expression (v_array)) :: v_tail))) (v_room) (v_reversed)))
| (__nat_147, ((Expressions (v_values)) :: v_tail), v_room) when __nat_147 >= 1 ->
(let v_rest = (__nat_147 - 1) in
(f_encode_work (v_rest) (((Length ((Base.list_length (v_values)))) :: ((ExpressionEntries (v_values)) :: v_tail))) (v_room) (v_reversed)))
| (__nat_148, ((ExpressionEntries ([])) :: v_tail), v_room) when __nat_148 >= 1 ->
(let v_rest = (__nat_148 - 1) in
(f_encode_work (v_rest) (v_tail) (v_room) (v_reversed)))
| (__nat_149, ((ExpressionEntries ((v_head :: v_following))) :: v_tail), v_room) when __nat_149 >= 1 ->
(let v_rest = (__nat_149 - 1) in
(f_encode_work (v_rest) (((Expression (v_head)) :: ((ExpressionEntries (v_following)) :: v_tail))) (v_room) (v_reversed)))
| (__nat_150, ((OptionalExpression (None)) :: v_tail), v_room) when __nat_150 >= 1 ->
(let v_rest = (__nat_150 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x0))) :: v_tail)) (v_room) (v_reversed)))
| (__nat_151, ((OptionalExpression ((Some (v_value)))) :: v_tail), v_room) when __nat_151 >= 1 ->
(let v_rest = (__nat_151 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x1))) :: ((Expression (v_value)) :: v_tail))) (v_room) (v_reversed)))
| (__nat_152, ((Arms (v_values)) :: v_tail), v_room) when __nat_152 >= 1 ->
(let v_rest = (__nat_152 - 1) in
(f_encode_work (v_rest) (((Length ((Base.list_length (v_values)))) :: ((ArmEntries (v_values)) :: v_tail))) (v_room) (v_reversed)))
| (__nat_153, ((ArmEntries ([])) :: v_tail), v_room) when __nat_153 >= 1 ->
(let v_rest = (__nat_153 - 1) in
(f_encode_work (v_rest) (v_tail) (v_room) (v_reversed)))
| (__nat_154, ((ArmEntries (((M.MatchArm (v_patterns, v_body)) :: v_following))) :: v_tail), v_room) when __nat_154 >= 1 ->
(let v_rest = (__nat_154 - 1) in
(f_encode_work (v_rest) (((Patterns (v_patterns)) :: ((Expression (v_body)) :: ((ArmEntries (v_following)) :: v_tail)))) (v_room) (v_reversed)))
| (__nat_155, ((Value (Const.UnitValue)) :: v_tail), v_room) when __nat_155 >= 1 ->
(let v_rest = (__nat_155 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x0))) :: v_tail)) (v_room) (v_reversed)))
| (__nat_156, ((Value ((Const.U32Value (v_value)))) :: v_tail), v_room) when __nat_156 >= 1 ->
(let v_rest = (__nat_156 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x1))) :: ((Word (v_value)) :: v_tail))) (v_room) (v_reversed)))
| (__nat_157, ((Value ((Const.BoolValue (v_value)))) :: v_tail), v_room) when __nat_157 >= 1 ->
(let v_rest = (__nat_157 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x2))) :: ((Word ((f_bool_word (v_value)))) :: v_tail))) (v_room) (v_reversed)))
| (__nat_158, ((Value ((Const.FunctionValue (v_name)))) :: v_tail), v_room) when __nat_158 >= 1 ->
(let v_rest = (__nat_158 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x3))) :: ((Text (v_name)) :: v_tail))) (v_room) (v_reversed)))
| (__nat_159, ((Value ((Const.ConstructorFunctionValue (v_constructor)))) :: v_tail), v_room) when __nat_159 >= 1 ->
(let v_rest = (__nat_159 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x4))) :: ((Text (v_constructor)) :: v_tail))) (v_room) (v_reversed)))
| (__nat_160, ((Value ((Const.DataValue (v_constructor, v_payload)))) :: v_tail), v_room) when __nat_160 >= 1 ->
(let v_rest = (__nat_160 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x5))) :: ((Text (v_constructor)) :: ((OptionalValue (v_payload)) :: v_tail)))) (v_room) (v_reversed)))
| (__nat_161, ((Value ((Const.ClosureValue (v_identity, v_parameter, v_body, v_environment)))) :: v_tail), v_room) when __nat_161 >= 1 ->
(let v_rest = (__nat_161 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x6))) :: ((Natural (v_identity)) :: ((Text (v_parameter)) :: ((Expression (v_body)) :: ((Bindings (v_environment)) :: v_tail)))))) (v_room) (v_reversed)))
| (__nat_162, ((Value ((Const.ReturnValue (v_label, v_value)))) :: v_tail), v_room) when __nat_162 >= 1 ->
(let v_rest = (__nat_162 - 1) in
(Fail ((M.Diagnostic (s_7, s_8, s_9)))))
| (__nat_163, ((Value ((Const.F32Value (v_value)))) :: v_tail), v_room) when __nat_163 >= 1 ->
(let v_rest = (__nat_163 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x7))) :: ((Word ((Base.f32_bits (v_value)))) :: v_tail))) (v_room) (v_reversed)))
| (__nat_164, ((Value ((Const.OperationValue (v_identity)))) :: v_tail), v_room) when __nat_164 >= 1 ->
(let v_rest = (__nat_164 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x8))) :: ((Identity (v_identity)) :: v_tail))) (v_room) (v_reversed)))
| (__nat_165, ((Value ((Const.StateProviderValue (v_read, v_write, v_initial)))) :: v_tail), v_room) when __nat_165 >= 1 ->
(let v_rest = (__nat_165 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0xe))) :: ((Identity (v_read)) :: ((Identity (v_write)) :: ((Value (v_initial)) :: v_tail))))) (v_room) (v_reversed)))
| (__nat_166, ((Value ((Const.StateReadValue (v_slot)))) :: v_tail), v_room) when __nat_166 >= 1 ->
(let v_rest = (__nat_166 - 1) in
(Fail ((M.Diagnostic (s_7, s_10, s_11)))))
| (__nat_167, ((Value ((Const.StateWriteValue (v_slot)))) :: v_tail), v_room) when __nat_167 >= 1 ->
(let v_rest = (__nat_167 - 1) in
(Fail ((M.Diagnostic (s_7, s_10, s_12)))))
| (__nat_168, ((Value ((Const.ProviderValue (v_identity, v_implementation)))) :: v_tail), v_room) when __nat_168 >= 1 ->
(let v_rest = (__nat_168 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x9))) :: ((Identity (v_identity)) :: ((Value (v_implementation)) :: v_tail)))) (v_room) (v_reversed)))
| (__nat_169, ((Value ((Const.EffectDescriptorValue (v_identity)))) :: v_tail), v_room) when __nat_169 >= 1 ->
(let v_rest = (__nat_169 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0xa))) :: ((Identity (v_identity)) :: v_tail))) (v_room) (v_reversed)))
| (__nat_170, ((Value ((Const.EffectSetValue (v_identities)))) :: v_tail), v_room) when __nat_170 >= 1 ->
(let v_rest = (__nat_170 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0xb))) :: ((Identities (v_identities)) :: v_tail))) (v_room) (v_reversed)))
| (__nat_171, ((Value ((Const.ProductValue (v_elements)))) :: v_tail), v_room) when __nat_171 >= 1 ->
(let v_rest = (__nat_171 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0xc))) :: ((Values (v_elements)) :: v_tail))) (v_room) (v_reversed)))
| (__nat_172, ((Value ((Const.ArrayValue (v_elements)))) :: v_tail), v_room) when __nat_172 >= 1 ->
(let v_rest = (__nat_172 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0xd))) :: ((Values (v_elements)) :: v_tail))) (v_room) (v_reversed)))
| (__nat_173, ((Values (v_values)) :: v_tail), v_room) when __nat_173 >= 1 ->
(let v_rest = (__nat_173 - 1) in
(f_encode_work (v_rest) (((Length ((Base.list_length (v_values)))) :: ((ValueEntries (v_values)) :: v_tail))) (v_room) (v_reversed)))
| (__nat_174, ((ValueEntries ([])) :: v_tail), v_room) when __nat_174 >= 1 ->
(let v_rest = (__nat_174 - 1) in
(f_encode_work (v_rest) (v_tail) (v_room) (v_reversed)))
| (__nat_175, ((ValueEntries ((v_head :: v_following))) :: v_tail), v_room) when __nat_175 >= 1 ->
(let v_rest = (__nat_175 - 1) in
(f_encode_work (v_rest) (((Value (v_head)) :: ((ValueEntries (v_following)) :: v_tail))) (v_room) (v_reversed)))
| (__nat_176, ((Value ((Const.PatternBindingsValue (v_bindings)))) :: v_tail), v_room) when __nat_176 >= 1 ->
(let v_rest = (__nat_176 - 1) in
(Fail ((M.Diagnostic (s_7, s_8, s_13)))))
| (__nat_177, ((Value ((Const.MatchValuesValue (v_values)))) :: v_tail), v_room) when __nat_177 >= 1 ->
(let v_rest = (__nat_177 - 1) in
(Fail ((M.Diagnostic (s_7, s_8, s_14)))))
| (__nat_178, ((OptionalValue (None)) :: v_tail), v_room) when __nat_178 >= 1 ->
(let v_rest = (__nat_178 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x0))) :: v_tail)) (v_room) (v_reversed)))
| (__nat_179, ((OptionalValue ((Some (v_value)))) :: v_tail), v_room) when __nat_179 >= 1 ->
(let v_rest = (__nat_179 - 1) in
(f_encode_work (v_rest) (((Word ((Base.W32 0x1))) :: ((Value (v_value)) :: v_tail))) (v_room) (v_reversed)))
| (__nat_180, ((Bindings (v_values)) :: v_tail), v_room) when __nat_180 >= 1 ->
(let v_rest = (__nat_180 - 1) in
(f_encode_work (v_rest) (((Length ((Base.list_length (v_values)))) :: ((BindingEntries (v_values)) :: v_tail))) (v_room) (v_reversed)))
| (__nat_181, ((BindingEntries ([])) :: v_tail), v_room) when __nat_181 >= 1 ->
(let v_rest = (__nat_181 - 1) in
(f_encode_work (v_rest) (v_tail) (v_room) (v_reversed)))
| (__nat_182, ((BindingEntries (((Const.Binding (v_name, v_value)) :: v_following))) :: v_tail), v_room) when __nat_182 >= 1 ->
(let v_rest = (__nat_182 - 1) in
(f_encode_work (v_rest) (((Text (v_name)) :: ((Value (v_value)) :: ((BindingEntries (v_following)) :: v_tail)))) (v_room) (v_reversed)))
| (__nat_183, ((Naturals (v_values)) :: v_tail), v_room) when __nat_183 >= 1 ->
(let v_rest = (__nat_183 - 1) in
(f_encode_work (v_rest) (((Length ((Base.list_length (v_values)))) :: ((NaturalEntries (v_values)) :: v_tail))) (v_room) (v_reversed)))
| (__nat_184, ((NaturalEntries ([])) :: v_tail), v_room) when __nat_184 >= 1 ->
(let v_rest = (__nat_184 - 1) in
(f_encode_work (v_rest) (v_tail) (v_room) (v_reversed)))
| (__nat_185, ((NaturalEntries ((v_head :: v_following))) :: v_tail), v_room) when __nat_185 >= 1 ->
(let v_rest = (__nat_185 - 1) in
(f_encode_work (v_rest) (((Natural (v_head)) :: ((NaturalEntries (v_following)) :: v_tail))) (v_room) (v_reversed)))
| (__nat_186, ((Strings (v_values)) :: v_tail), v_room) when __nat_186 >= 1 ->
(let v_rest = (__nat_186 - 1) in
(f_encode_work (v_rest) (((Length ((Base.list_length (v_values)))) :: ((StringEntries (v_values)) :: v_tail))) (v_room) (v_reversed)))
| (__nat_187, ((StringEntries ([])) :: v_tail), v_room) when __nat_187 >= 1 ->
(let v_rest = (__nat_187 - 1) in
(f_encode_work (v_rest) (v_tail) (v_room) (v_reversed)))
| (__nat_188, ((StringEntries ((v_head :: v_following))) :: v_tail), v_room) when __nat_188 >= 1 ->
(let v_rest = (__nat_188 - 1) in
(f_encode_work (v_rest) (((Text (v_head)) :: ((StringEntries (v_following)) :: v_tail))) (v_room) (v_reversed)))
| (__nat_189, ((Functions (v_values)) :: v_tail), v_room) when __nat_189 >= 1 ->
(let v_rest = (__nat_189 - 1) in
(f_encode_work (v_rest) (((Length ((Base.list_length (v_values)))) :: ((FunctionEntries (v_values)) :: v_tail))) (v_room) (v_reversed)))
| (__nat_190, ((FunctionEntries ([])) :: v_tail), v_room) when __nat_190 >= 1 ->
(let v_rest = (__nat_190 - 1) in
(f_encode_work (v_rest) (v_tail) (v_room) (v_reversed)))
| (__nat_191, ((FunctionEntries (((M.CheckedFunction (v_function, (M.Signature (v_name, v_parameter, v_result, v_variables, v_row)), v_effects)) :: v_following))) :: v_tail), v_room) when __nat_191 >= 1 ->
(let v_rest = (__nat_191 - 1) in
(f_encode_work (v_rest) (((Text (v_name)) :: ((TypeValue (v_parameter)) :: ((TypeValue (v_result)) :: ((Naturals (v_variables)) :: ((Effects (v_effects)) :: ((Row (v_row)) :: ((FunctionEntries (v_following)) :: v_tail)))))))) (v_room) (v_reversed)))
| (__nat_192, ((Analysis ((Main.Analysis ((M.CheckedModule (v_checked_constants, v_functions, v_types, v_operations)), v_constants, v_remaining_steps)))) :: v_tail), v_room) when __nat_192 >= 1 ->
(let v_rest = (__nat_192 - 1) in
(f_encode_work (v_rest) (((Functions (v_functions)) :: ((Bindings (v_constants)) :: ((Natural (v_remaining_steps)) :: v_tail)))) (v_room) (v_reversed)))
| (__nat_193, ((Bytes (v_values)) :: v_tail), v_room) when __nat_193 >= 1 ->
(let v_rest = (__nat_193 - 1) in
(f_encode_work (v_rest) (((ByteLength ((Base.list_length (v_values)))) :: ((ByteWords (v_values)) :: v_tail))) (v_room) (v_reversed)))
| (__nat_194, ((ByteLength (v_value)) :: v_tail), v_room) when __nat_194 >= 1 ->
(let v_rest = (__nat_194 - 1) in
(f_encode_work (v_rest) (((CheckedLength ((Base.nat_is_le (v_value) ((Base.u32_to_nat ((Base.W32 0x4000000))))), v_value)) :: v_tail)) (v_room) (v_reversed)))
| (__nat_195, ((ByteWords ([])) :: v_tail), v_room) when __nat_195 >= 1 ->
(let v_rest = (__nat_195 - 1) in
(f_encode_work (v_rest) (v_tail) (v_room) (v_reversed)))
| (__nat_196, ((ByteWords ((v_a :: []))) :: v_tail), v_room) when __nat_196 >= 1 ->
(let v_rest = (__nat_196 - 1) in
(f_encode_work (v_rest) (((CheckedBytes ((f_valid_bytes (v_a) ((Base.W32 0x0)) ((Base.W32 0x0)) ((Base.W32 0x0))), v_a, [])) :: v_tail)) (v_room) (v_reversed)))
| (__nat_197, ((ByteWords ((v_a :: (v_b :: [])))) :: v_tail), v_room) when __nat_197 >= 1 ->
(let v_rest = (__nat_197 - 1) in
(f_encode_work (v_rest) (((CheckedBytes ((f_valid_bytes (v_a) (v_b) ((Base.W32 0x0)) ((Base.W32 0x0))), (f_pack (v_a) (v_b) ((Base.W32 0x0)) ((Base.W32 0x0))), [])) :: v_tail)) (v_room) (v_reversed)))
| (__nat_198, ((ByteWords ((v_a :: (v_b :: (v_c :: []))))) :: v_tail), v_room) when __nat_198 >= 1 ->
(let v_rest = (__nat_198 - 1) in
(f_encode_work (v_rest) (((CheckedBytes ((f_valid_bytes (v_a) (v_b) (v_c) ((Base.W32 0x0))), (f_pack (v_a) (v_b) (v_c) ((Base.W32 0x0))), [])) :: v_tail)) (v_room) (v_reversed)))
| (__nat_199, ((ByteWords ((v_a :: (v_b :: (v_c :: (v_d :: v_following)))))) :: v_tail), v_room) when __nat_199 >= 1 ->
(let v_rest = (__nat_199 - 1) in
(f_encode_work (v_rest) (((CheckedBytes ((f_valid_bytes (v_a) (v_b) (v_c) (v_d)), (f_pack (v_a) (v_b) (v_c) (v_d)), v_following)) :: v_tail)) (v_room) (v_reversed)))
| (__nat_200, ((CheckedBytes (false, v_word, v_following)) :: v_tail), v_room) when __nat_200 >= 1 ->
(let v_rest = (__nat_200 - 1) in
(Fail ((M.Diagnostic (s_7, s_15, s_16)))))
| (__nat_201, ((CheckedBytes (true, v_word, v_following)) :: v_tail), v_room) when __nat_201 >= 1 ->
(let v_rest = (__nat_201 - 1) in
(f_encode_work (v_rest) (((Word (v_word)) :: ((ByteWords (v_following)) :: v_tail))) (v_room) (v_reversed)))
| (__nat_202, ((Diagnostic ((M.Diagnostic (v_code, v_subject, v_message)))) :: v_tail), v_room) when __nat_202 >= 1 ->
(let v_rest = (__nat_202 - 1) in
(f_encode_work (v_rest) (((Text (v_code)) :: ((Text (v_subject)) :: ((Text (v_message)) :: v_tail)))) (v_room) (v_reversed))))
and (* native_response.bend:495 *)
f_character_words : Base.text -> (Base.word32) list -> (Base.word32) list =
fun v_value v_tail ->
(match v_value with
| SNil ->
v_tail
| (SCon (v_character, v_following)) ->
((Base.char_to_u32 (v_character)) :: (f_character_words (v_following) (v_tail))))
and (* native_response.bend:502 *)
f_text_words : Base.text -> (Base.word32) list -> (Base.word32) list =
fun v_value v_tail ->
((Base.u32_from_nat ((Base.string_length (v_value)))) :: (f_character_words (v_value) (v_tail)))
and (* native_response.bend:507 *)
f_finish : (M.t_Diagnostic, (Base.word32) list) Base.result_ -> (Base.word32) list =
fun v_result ->
(match v_result with
| (Done (v_words)) ->
v_words
| (Fail ((M.Diagnostic (v_code, v_subject, v_message)))) ->
((Base.W32 0x424c4f54) :: ((f_version ()) :: ((Base.W32 0x0) :: (f_text_words (v_code) ((f_text_words (v_subject) ((f_text_words (v_message) ([]))))))))))
and (* native_response.bend:514 *)
f_encode : Base.word32 -> (t_Work) list -> (Base.word32) list =
fun v_kind v_fields ->
(f_finish ((f_encode_work ((M.f_max_nat ())) (((Word ((Base.W32 0x424c4f54))) :: ((Word ((f_version ()))) :: ((Word (v_kind)) :: v_fields)))) ((Base.u32_to_nat ((Base.W32 0x1000000)))) ([]))))
and (* native_response.bend:517 *)
f_encode_diagnostic : M.t_Diagnostic -> (Base.word32) list =
fun v_diagnostic ->
(f_encode ((Base.W32 0x0)) ([(Diagnostic (v_diagnostic))]))
and (* native_response.bend:520 *)
f_encode_analysis : (M.t_Diagnostic, Main.t_Analysis) Base.result_ -> (Base.word32) list =
fun v_result ->
(match v_result with
| (Fail (v_diagnostic)) ->
(f_encode_diagnostic (v_diagnostic))
| (Done (v_analysis)) ->
(f_encode ((Base.W32 0x1)) ([(Analysis (v_analysis))])))
and (* native_response.bend:527 *)
f_encode_artifact : (M.t_Diagnostic, Main.t_Artifact) Base.result_ -> (Base.word32) list =
fun v_result ->
(match v_result with
| (Fail (v_diagnostic)) ->
(f_encode_diagnostic (v_diagnostic))
| (Done ((Main.Artifact (v_analysis, v_bytes)))) ->
(f_encode ((Base.W32 0x2)) ([(Analysis (v_analysis)); (Bytes (v_bytes))])))
