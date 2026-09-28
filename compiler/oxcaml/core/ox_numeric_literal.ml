(* Native semantic port of compiler/numeric_literal.bend.

   Source SHA-256: 894a50a0858fc3c258e3dbb5ac44419ae725da5cc1d472282848ca89cfb26a8e

   Ownership/type arguments are erased; value types are checked by OCaml.

   No Bend interpreter or generated C/JavaScript is linked. *)

open Base

type t_Decimal =
  | DecimalZero
  | Decimal of Base.text * int * int
and t_Exponent =
  | Exponent of int * int

let rec (* numeric_literal.bend:14 *)
f_leading_zeroes : Base.text -> Base.text =
fun v_digits ->
(match v_digits with
| (SCon ((Chr ((Base.W32 0x30))), v_tail)) ->
(f_leading_zeroes (v_tail))
| v_other ->
v_other)
and (* numeric_literal.bend:21 *)
f_decimal : Base.text -> int -> t_Exponent -> t_Decimal =
fun v_digits v_fractional v_exponent ->
(match (v_digits, v_exponent) with
| (SNil, _) ->
DecimalZero
| (v_digits, (Exponent (v_positive, v_negative))) ->
(Decimal (v_digits, (Base.nat_add ((Base.nat_sub ((Base.string_length (v_digits))) (1))) (v_positive)), (Base.nat_add (v_fractional) (v_negative)))))
and (* numeric_literal.bend:28 *)
f_exponent_digits : Base.text -> int -> int -> (int) option =
fun v_chars v_value v_limit ->
(match v_chars with
| SNil ->
(Some (v_value))
| (SCon ((Chr (v_code)), v_tail)) ->
(match (Base.bool_pick ((Base.bool_and ((Base.u32_is_ge (v_code) ((Base.W32 0x30)))) ((Base.u32_is_le (v_code) ((Base.W32 0x39)))))) ((Some (()))) (None)) with
| None -> None
| Some v_valid ->
(f_exponent_digits (v_tail) ((Base.nat_min (v_limit) ((Base.nat_add ((Base.nat_mul (v_value) (10))) ((Base.u32_to_nat ((Base.u32_sub (v_code) ((Base.W32 0x30)))))))))) (v_limit))))
and (* numeric_literal.bend:37 *)
f_exponent : Base.text -> int -> (t_Exponent) option =
fun v_chars v_limit ->
(match v_chars with
| SNil ->
None
| (SCon ((Chr ((Base.W32 0x2d))), v_tail)) ->
(match (f_exponent_digits (v_tail) (0) (v_limit)) with
| None -> None
| Some v_value ->
(Some ((Exponent (0, v_value)))))
| (SCon ((Chr ((Base.W32 0x2b))), v_tail)) ->
(match (f_exponent_digits (v_tail) (0) (v_limit)) with
| None -> None
| Some v_value ->
(Some ((Exponent (v_value, 0)))))
| v_chars ->
(match (f_exponent_digits (v_chars) (0) (v_limit)) with
| None -> None
| Some v_value ->
(Some ((Exponent (v_value, 0))))))
and (* numeric_literal.bend:54 *)
f_significand : Base.text -> Base.text -> int -> bool -> int -> (t_Decimal) option =
fun v_chars v_reversed v_fractional v_point v_limit ->
(match v_chars with
| SNil ->
(Some ((f_decimal ((f_leading_zeroes ((Base.string_reverse (v_reversed))))) (v_fractional) ((Exponent (0, 0))))))
| (SCon ((Chr ((Base.W32 0x2e))), v_tail)) ->
(f_significand (v_tail) (v_reversed) (v_fractional) (true) (v_limit))
| (SCon ((Chr ((Base.W32 0x65))), v_tail)) ->
(match (f_exponent (v_tail) (v_limit)) with
| None -> None
| Some v_scale ->
(Some ((f_decimal ((f_leading_zeroes ((Base.string_reverse (v_reversed))))) (v_fractional) (v_scale)))))
| (SCon ((Chr ((Base.W32 0x45))), v_tail)) ->
(match (f_exponent (v_tail) (v_limit)) with
| None -> None
| Some v_scale ->
(Some ((f_decimal ((f_leading_zeroes ((Base.string_reverse (v_reversed))))) (v_fractional) (v_scale)))))
| (SCon ((Chr (v_code)), v_tail)) ->
(let v_number = v_code in
(match (Base.bool_pick ((Base.bool_and ((Base.u32_is_ge (v_number) ((Base.W32 0x30)))) ((Base.u32_is_le (v_number) ((Base.W32 0x39)))))) ((Some (()))) (None)) with
| None -> None
| Some v_valid ->
(f_significand (v_tail) ((SCon ((Chr (v_number)), v_reversed))) ((Base.nat_add (v_fractional) ((Base.bool_pick (v_point) (1) (0))))) (v_point) (v_limit)))))
and (* numeric_literal.bend:74 *)
f_multiply_digits : Base.text -> Base.word32 -> Base.word32 -> Base.text -> Base.text =
fun v_reversed v_factor v_carry v_result ->
(match (v_reversed, v_carry) with
| (SNil, (Base.W32 0x0)) ->
v_result
| (SNil, v_other) ->
(Base.string_append (Base.u32_show (v_other)) v_result)
| ((SCon ((Chr (v_code)), v_tail)), v_carry) ->
(let v_value = (Base.u32_add ((Base.u32_mul ((Base.u32_sub (v_code) ((Base.W32 0x30)))) (v_factor))) (v_carry)) in
(f_multiply_digits (v_tail) (v_factor) ((Base.u32_div (v_value) ((Base.W32 0xa)))) ((SCon ((Chr ((Base.u32_add ((Base.W32 0x30)) ((Base.u32_mod (v_value) ((Base.W32 0xa))))))), v_result))))))
and (* numeric_literal.bend:84 *)
f_multiply_power : int -> Base.word32 -> Base.text -> Base.text =
fun v_power v_factor v_digits ->
(match v_power with
| 0 ->
v_digits
| __nat_1 when __nat_1 >= 1 ->
(let v_rest = (__nat_1 - 1) in
(f_multiply_power (v_rest) (v_factor) ((f_multiply_digits ((Base.string_reverse (v_digits))) (v_factor) ((Base.W32 0x0)) (SNil))))))
and (* numeric_literal.bend:91 *)
f_midpoint : Base.word32 -> t_Decimal =
fun v_lower ->
(let v_biased = (Base.u32_shrn (v_lower) (23)) in
(let v_mantissa = (Base.u32_and (v_lower) ((Base.W32 0x7fffff))) in
(let v_coefficient = (Base.u32_add ((Base.u32_mul ((Base.bool_pick ((Base.u32_is_eq (v_biased) ((Base.W32 0x0)))) (v_mantissa) ((Base.u32_add (v_mantissa) ((Base.W32 0x800000)))))) ((Base.W32 0x2)))) ((Base.W32 0x1))) in
(let v_power = (Base.u32_to_nat ((Base.bool_pick ((Base.u32_is_eq (v_biased) ((Base.W32 0x0)))) ((Base.W32 0x1)) (v_biased)))) in
(let v_negative = (Base.nat_sub (151) (v_power)) in
(let v_digits = (f_multiply_power (v_negative) ((Base.W32 0x5)) ((f_multiply_power ((Base.nat_sub (v_power) (151))) ((Base.W32 0x2)) ((Base.u32_show (v_coefficient)))))) in
(Decimal (v_digits, (Base.nat_sub ((Base.string_length (v_digits))) (1)), v_negative))))))))
and (* numeric_literal.bend:100 *)
f_compare_digits : Base.text -> Base.text -> Base.cmp -> Base.cmp =
fun v_left v_right v_order ->
(match (v_left, v_right, v_order) with
| (_, _, LT) ->
LT
| (_, _, GT) ->
GT
| (SNil, SNil, EQ) ->
EQ
| (SNil, (SCon ((Chr (v_head)), v_tail)), EQ) ->
(f_compare_digits (SNil) (v_tail) ((Base.u32_cmp ((Base.W32 0x30)) (v_head))))
| ((SCon ((Chr (v_head)), v_tail)), SNil, EQ) ->
(f_compare_digits (v_tail) (SNil) ((Base.u32_cmp (v_head) ((Base.W32 0x30)))))
| ((SCon ((Chr (v_a)), v_at)), (SCon ((Chr (v_b)), v_bt)), EQ) ->
(f_compare_digits (v_at) (v_bt) ((Base.u32_cmp (v_a) (v_b)))))
and (* numeric_literal.bend:115 *)
f_compare : t_Decimal -> t_Decimal -> Base.cmp =
fun v_left v_right ->
(match (v_left, v_right) with
| (DecimalZero, DecimalZero) ->
EQ
| (DecimalZero, _) ->
LT
| (_, DecimalZero) ->
GT
| ((Decimal (v_a, v_ap, v_an)), (Decimal (v_b, v_bp, v_bn))) ->
(f_compare_digits (v_a) (v_b) ((Base.nat_cmp ((Base.nat_add (v_ap) (v_bn))) ((Base.nat_add (v_bp) (v_an)))))))
and (* numeric_literal.bend:126 *)
f_upper_choice : Base.cmp -> Base.word32 -> Base.word32 =
fun v_order v_bits ->
(match v_order with
| LT ->
v_bits
| EQ ->
(Base.bool_pick ((Base.u32_is_eq ((Base.u32_and (v_bits) ((Base.W32 0x1)))) ((Base.W32 0x0)))) (v_bits) ((Base.u32_add (v_bits) ((Base.W32 0x1)))))
| GT ->
(Base.u32_add (v_bits) ((Base.W32 0x1))))
and (* numeric_literal.bend:135 *)
f_upper : Base.word32 -> t_Decimal -> Base.word32 =
fun v_bits v_exact ->
(match v_bits with
| (Base.W32 0x7f800000) ->
(Base.W32 0x7f800000)
| v_bits ->
(f_upper_choice ((f_compare (v_exact) ((f_midpoint (v_bits))))) (v_bits)))
and (* numeric_literal.bend:142 *)
f_lower_choice : Base.cmp -> Base.word32 -> t_Decimal -> Base.word32 =
fun v_order v_bits v_exact ->
(match v_order with
| LT ->
(Base.u32_sub (v_bits) ((Base.W32 0x1)))
| EQ ->
(Base.bool_pick ((Base.u32_is_eq ((Base.u32_and (v_bits) ((Base.W32 0x1)))) ((Base.W32 0x0)))) (v_bits) ((Base.u32_sub (v_bits) ((Base.W32 0x1)))))
| GT ->
(f_upper (v_bits) (v_exact)))
and (* numeric_literal.bend:151 *)
f_rounded : Base.word32 -> t_Decimal -> Base.word32 =
fun v_bits v_exact ->
(match (v_bits, v_exact) with
| (_, DecimalZero) ->
(Base.W32 0x0)
| ((Base.W32 0x0), v_exact) ->
(f_upper ((Base.W32 0x0)) (v_exact))
| (v_bits, v_exact) ->
(f_lower_choice ((f_compare (v_exact) ((f_midpoint ((Base.u32_sub (v_bits) ((Base.W32 0x1)))))))) (v_bits) (v_exact)))
and (* numeric_literal.bend:160 *)
f_from_bits : Base.word32 -> Base.word32 =
fun v_value ->
(let v_bits = v_value in
v_bits)
and (* numeric_literal.bend:164 *)
f_candidate : (Base.word32) option -> Base.text -> (Base.word32) option =
fun v_parsed v_text ->
(match v_parsed with
| None ->
None
| (Some (v_value)) ->
(let v_bits = (Base.f32_bits (v_value)) in
(match (Base.bool_pick ((Base.u32_is_le (v_bits) ((Base.W32 0x7f800000)))) ((Some (()))) (None)) with
| None -> None
| Some v_valid ->
(match (f_significand (v_text) (SNil) (0) (false) ((Base.nat_add ((Base.string_length (v_text))) (400)))) with
| None -> None
| Some v_exact ->
(Some ((f_from_bits ((f_rounded (v_bits) (v_exact))))))))))
and (* numeric_literal.bend:175 *)
f_read : Base.text -> (Base.word32) option =
fun v_text ->
(f_candidate ((Base.f32_read (v_text))) (v_text))
