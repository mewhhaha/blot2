(* Native semantic port of compiler/cst.bend.

   Source SHA-256: 1e07cd287f8501ccbdbf02a520787b76d87dc894f55932ab047ebe7b8d6d7c0e

   Ownership/type arguments are erased; value types are checked by OCaml.

   No Bend interpreter or generated C/JavaScript is linked. *)

open Base

module M = Ox_model

module Numeric = Ox_numeric_literal

type t_Cst =
  | Cst of Base.text * Base.text * Base.text * int * (t_Cst) list

let s_0 = Base.text_of_utf8 "offset:"

let s_1 = Base.text_of_utf8 "internal_cst"

let s_2 = Base.text_of_utf8 "parser"

let s_3 = Base.text_of_utf8 "expected exactly one Baba field value"

let s_4 = Base.text_of_utf8 ""

let s_5 = Base.text_of_utf8 "qualified_name"

let s_6 = Base.text_of_utf8 "U32"

let s_7 = Base.text_of_utf8 "F32"

let s_8 = Base.text_of_utf8 "Bool"

let s_9 = Base.text_of_utf8 "Unit"

let s_10 = Base.text_of_utf8 "EffectDescriptor"

let s_11 = Base.text_of_utf8 "EffectSet"

let s_12 = Base.text_of_utf8 "unsupported_type"

let s_13 = Base.text_of_utf8 "unknown or unsupported type: "

let s_14 = Base.text_of_utf8 "text_literal"

let s_15 = Base.text_of_utf8 "unsupported string escape; use escaped quote, backslash, n, r, or t"

let s_16 = Base.text_of_utf8 "unterminated string literal"

let s_17 = Base.text_of_utf8 "expected a quoted string literal"

let s_18 = Base.text_of_utf8 "float_range"

let s_19 = Base.text_of_utf8 "floating-point literal exceeds finite F32 range"

let s_20 = Base.text_of_utf8 "float_literal"

let s_21 = Base.text_of_utf8 "invalid F32 literal"

let s_22 = Base.text_of_utf8 "integer_range"

let s_23 = Base.text_of_utf8 "integer literal exceeds U32 (4294967295)"

let s_24 = Base.text_of_utf8 "0x"

let s_25 = Base.text_of_utf8 "0X"

let rec (* cst.bend:9 *)
f_children_of : t_Cst -> (t_Cst) list =
fun v_node ->
(let (Cst (v_kind, v_field, v_text, v_offset, v_children)) = v_node in
v_children)
and (* cst.bend:13 *)
f_kind_of : t_Cst -> Base.text =
fun v_node ->
(let (Cst (v_kind, v_field, v_text, v_offset, v_children)) = v_node in
v_kind)
and (* cst.bend:17 *)
f_text_of : t_Cst -> Base.text =
fun v_node ->
(let (Cst (v_kind, v_field, v_text, v_offset, v_children)) = v_node in
v_text)
and (* cst.bend:21 *)
f_offset_of : t_Cst -> int =
fun v_node ->
(let (Cst (v_kind, v_field, v_text, v_offset, v_children)) = v_node in
v_offset)
and (* cst.bend:25 *)
f_diagnostic : t_Cst -> Base.text -> Base.text -> M.t_Diagnostic =
fun v_node v_code v_message ->
(M.Diagnostic (v_code, (Base.string_append s_0 (Base.nat_show ((f_offset_of (v_node))))), v_message))
and (* cst.bend:28 *)
f_fields_reversed : (t_Cst) list -> Base.text -> (t_Cst) list -> (t_Cst) list =
fun v_nodes v_label v_reversed ->
(match v_nodes with
| [] ->
(Base.list_reverse (v_reversed))
| ((Cst (v_kind, v_field, v_text, v_offset, v_children)) :: v_tail) ->
(let v_next = (Base.bool_pick ((M.f_name_equal (v_field) (v_label))) (((Cst (v_kind, v_field, v_text, v_offset, v_children)) :: v_reversed)) (v_reversed)) in
(f_fields_reversed (v_tail) (v_label) (v_next))))
and (* cst.bend:36 *)
f_fields : (t_Cst) list -> Base.text -> (t_Cst) list =
fun v_nodes v_label ->
(f_fields_reversed (v_nodes) (v_label) ([]))
and (* cst.bend:39 *)
f_field_values : t_Cst -> Base.text -> (t_Cst) list =
fun v_node v_label ->
(f_fields ((f_children_of (v_node))) (v_label))
and (* cst.bend:42 *)
f_one : (t_Cst) list -> (M.t_Diagnostic, t_Cst) Base.result_ =
fun v_nodes ->
(match v_nodes with
| (v_node :: []) ->
(Done (v_node))
| _ ->
(Fail ((M.Diagnostic (s_1, s_2, s_3)))))
and (* cst.bend:49 *)
f_texts : (t_Cst) list -> Base.text =
fun v_nodes ->
(match v_nodes with
| [] ->
s_4
| (v_head :: v_tail) ->
(Base.string_append (f_text_of (v_head)) (f_texts (v_tail))))
and (* cst.bend:56 *)
f_name_of : t_Cst -> Base.text =
fun v_node ->
(f_texts ((f_children_of (v_node))))
and (* cst.bend:59 *)
f_present : (t_Cst) list -> bool =
fun v_nodes ->
(match v_nodes with
| [] ->
false
| (v_head :: v_tail) ->
true)
and (* cst.bend:66 *)
f_type_name : t_Cst -> Base.text =
fun v_node ->
(Base.bool_pick ((M.f_name_equal ((f_kind_of (v_node))) (s_5))) ((f_name_of (v_node))) ((f_text_of (v_node))))
and (* cst.bend:69 *)
f_scalar_type : t_Cst -> (M.t_Diagnostic, M.t_Ty) Base.result_ =
fun v_node ->
(let v_name = (f_type_name (v_node)) in
(Base.bool_pick ((M.f_name_equal (v_name) (s_6))) ((Done (M.U32Ty))) ((Base.bool_pick ((M.f_name_equal (v_name) (s_7))) ((Done (M.F32Ty))) ((Base.bool_pick ((M.f_name_equal (v_name) (s_8))) ((Done (M.BoolTy))) ((Base.bool_pick ((M.f_name_equal (v_name) (s_9))) ((Done (M.UnitTy))) ((Base.bool_pick ((M.f_name_equal (v_name) (s_10))) ((Done (M.EffectDescriptorTy))) ((Base.bool_pick ((M.f_name_equal (v_name) (s_11))) ((Done (M.EffectSetTy))) ((Fail ((f_diagnostic (v_node) (s_12) ((Base.string_append s_13 v_name))))))))))))))))))
and (* cst.bend:79 *)
f_literal_character : int32 -> t_Cst -> (M.t_Diagnostic, Base.char32) Base.result_ =
fun v_code v_node ->
(match v_code with
| 0x00000022l ->
(Done ((Base.char_of_u32 (0x00000022l))))
| 0x0000005cl ->
(Done ((Base.char_of_u32 (0x0000005cl))))
| 0x0000006el ->
(Done ((Base.char_of_u32 (0x0000000al))))
| 0x00000072l ->
(Done ((Base.char_of_u32 (0x0000000dl))))
| 0x00000074l ->
(Done ((Base.char_of_u32 (0x00000009l))))
| _ ->
(Fail ((f_diagnostic (v_node) (s_14) (s_15)))))
and (* cst.bend:94 *)
f_literal_body : Base.text -> t_Cst -> (M.t_Diagnostic, Base.text) Base.result_ =
fun v_chars v_node ->
(match v_chars with
| (SCon ((Chr (0x00000022)), SNil)) ->
(Done (SNil))
| (SCon ((Chr (0x0000005c)), (SCon ((Chr (__char_v_code)), v_tail)))) ->
let v_code = Int32.of_int __char_v_code in
(match (f_literal_character (v_code) (v_node)) with
| Fail __error -> Fail __error
| Done v_character ->
(match (f_literal_body (v_tail) (v_node)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done ((SCon (v_character, v_rest))))))
| (SCon (v_character, v_tail)) ->
(match (f_literal_body (v_tail) (v_node)) with
| Fail __error -> Fail __error
| Done v_rest ->
(Done ((SCon (v_character, v_rest)))))
| SNil ->
(Fail ((f_diagnostic (v_node) (s_14) (s_16)))))
and (* cst.bend:110 *)
f_literal_text : Base.text -> t_Cst -> (M.t_Diagnostic, Base.text) Base.result_ =
fun v_chars v_node ->
(match v_chars with
| (SCon ((Chr (0x00000022)), v_tail)) ->
(f_literal_body (v_tail) (v_node))
| _ ->
(Fail ((f_diagnostic (v_node) (s_14) (s_17)))))
and (* cst.bend:117 *)
f_literal : t_Cst -> (M.t_Diagnostic, Base.text) Base.result_ =
fun v_node ->
(f_literal_text ((f_text_of (v_node))) (v_node))
and (* cst.bend:120 *)
f_float_characters : Base.text -> Base.text =
fun v_text ->
(match v_text with
| SNil ->
SNil
| (SCon ((Chr (0x0000005f)), v_tail)) ->
(f_float_characters (v_tail))
| (SCon (v_character, v_tail)) ->
(SCon (v_character, (f_float_characters (v_tail)))))
and (* cst.bend:129 *)
f_float_finite : bool -> int32 -> t_Cst -> (M.t_Diagnostic, int32) Base.result_ =
fun v_valid v_value v_node ->
(match v_valid with
| true ->
(Done (v_value))
| false ->
(Fail ((f_diagnostic (v_node) (s_18) (s_19)))))
and (* cst.bend:136 *)
f_float_value : (int32) option -> t_Cst -> (M.t_Diagnostic, int32) Base.result_ =
fun v_parsed v_node ->
(match v_parsed with
| (Some (v_value)) ->
(f_float_finite ((Base.u32_is_ne ((Base.u32_and ((Base.f32_bits (v_value))) (0x7f800000l))) (0x7f800000l))) (v_value) (v_node))
| None ->
(Fail ((f_diagnostic (v_node) (s_20) (s_21)))))
and (* cst.bend:143 *)
f_float : t_Cst -> (M.t_Diagnostic, int32) Base.result_ =
fun v_node ->
(f_float_value ((Numeric.f_read ((f_float_characters ((f_text_of (v_node))))))) (v_node))
and (* cst.bend:146 *)
f_digit : int32 -> int32 =
fun v_code ->
(Base.bool_pick ((Base.u32_is_le (v_code) (0x00000039l))) ((Base.u32_sub (v_code) (0x00000030l))) ((Base.bool_pick ((Base.u32_is_le (v_code) (0x00000046l))) ((Base.u32_sub (v_code) (0x00000037l))) ((Base.u32_sub (v_code) (0x00000057l))))))
and (* cst.bend:150 *)
f_accumulate : bool -> int32 -> int32 -> int32 -> t_Cst -> (M.t_Diagnostic, int32) Base.result_ =
fun v_valid v_number v_number_digit v_radix v_node ->
(match v_valid with
| true ->
(Done ((Base.u32_add ((Base.u32_mul (v_number) (v_radix))) (v_number_digit))))
| false ->
(Fail ((f_diagnostic (v_node) (s_22) (s_23)))))
and (* cst.bend:157 *)
f_integer_digits : Base.text -> int32 -> int32 -> t_Cst -> (M.t_Diagnostic, int32) Base.result_ =
fun v_chars v_number v_radix v_node ->
(match v_chars with
| SNil ->
(Done (v_number))
| (SCon ((Chr (0x0000005f)), v_tail)) ->
(f_integer_digits (v_tail) (v_number) (v_radix) (v_node))
| (SCon ((Chr (__char_v_code)), v_tail)) ->
let v_code = Int32.of_int __char_v_code in
(let v_d = (f_digit (v_code)) in
(let v_n = v_number in
(match (f_accumulate ((Base.u32_is_le (v_n) ((Base.u32_div ((Base.u32_sub (0xffffffffl) (v_d))) (v_radix))))) (v_n) (v_d) (v_radix) (v_node)) with
| Fail __error -> Fail __error
| Done v_next ->
(f_integer_digits (v_tail) (v_next) (v_radix) (v_node))))))
and (* cst.bend:170 *)
f_integer : t_Cst -> (M.t_Diagnostic, int32) Base.result_ =
fun v_node ->
(let v_value = (f_text_of (v_node)) in
(let v_hex = (Base.bool_or ((Base.string_starts_with (v_value) (s_24))) ((Base.string_starts_with (v_value) (s_25)))) in
(f_integer_digits ((Base.bool_pick (v_hex) ((Base.string_drop (v_value) (2))) (v_value))) (0x00000000l) ((Base.bool_pick (v_hex) (0x00000010l) (0x0000000al))) (v_node))))
