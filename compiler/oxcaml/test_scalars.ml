(* Independent boxed-Int32/Int64 oracles for the immediate representation.
   Never implement an oracle by calling the candidate arithmetic. *)
open Base
let checks = ref 0
let check label condition = incr checks; if not condition then failwith label
let unsigned x = Int64.logand (Int64.of_int32 x) 0xffff_ffffL
let compare_bits label actual expected =
  check label (word_to_int32 actual = expected);
  check "word payload remains in U32" (let W32 x = actual in x >= 0 && x <= 0xffff_ffff)
let check_pair a b =
  let x = unsigned a and y = unsigned b in
  let na = word_of_int32 a and nb = word_of_int32 b in
  check "U32 to Nat" (Int64.of_int (u32_to_nat na) = x);
  check "unsigned lt" (u32_is_lt na nb = (x < y));
  check "unsigned le" (u32_is_le na nb = (x <= y));
  check "unsigned gt" (u32_is_gt na nb = (x > y));
  check "unsigned ge" (u32_is_ge na nb = (x >= y));
  check "unsigned cmp" (u32_cmp na nb = cmp (Int64.compare x y));
  compare_bits "wrap add" (u32_add na nb) (Int32.add a b);
  compare_bits "wrap sub" (u32_sub na nb) (Int32.sub a b);
  compare_bits "wrap mul" (u32_mul na nb) (Int32.mul a b);
  compare_bits "and" (u32_and na nb) (Int32.logand a b);
  compare_bits "or" (u32_or na nb) (Int32.logor a b);
  compare_bits "unsigned div including zero" (u32_div na nb) (if y=0L then 0l else Int64.to_int32 (Int64.div x y));
  compare_bits "unsigned mod including zero" (u32_mod na nb) (if y=0L then a else Int64.to_int32 (Int64.rem x y));
  for shift=0 to 40 do
    compare_bits "logical shift" (u32_shrn na shift) (if shift>=32 then 0l else Int32.shift_right_logical a shift);
    compare_bits "left shift" (u32_shln na shift) (if shift>=32 then 0l else Int32.shift_left a shift)
  done;
  compare_bits "F32 identity bits" (f32_bits na) a;
  compare_bits "F32 sign bit" (f32_neg na) (Int32.logxor a Int32.min_int);
  compare_bits "F32 abs bits" (f32_abs na) (Int32.logand a Int32.max_int);
  (* Test exact bit transport for all inputs, including NaN payloads, without
     assuming that hardware arithmetic preserves a NaN payload canonically. *)
  check "F32 raw roundtrip" (word_to_int32 (word_of_int32 a) = a);
  let fa = Int32.float_of_bits a and fb = Int32.float_of_bits b in
  check "F32 equality including NaNs" (f32_is_eq na nb = (fa = fb));
  check "F32 inequality including NaNs" (f32_is_ne na nb = (fa <> fb));
  check "F32 ordering including NaNs" (f32_is_lt na nb = (fa < fb));
  let converted = if Float.is_nan fa || fa <= 0. then 0l
    else if fa >= 4294967296. then Int32.minus_one
    else Int64.to_int32 (Int64.of_float fa) in
  compare_bits "F32 saturating conversion including NaNs" (f32_to_u32 na) converted;
  if not (Float.is_nan fa || Float.is_nan fb) then begin
    let operation label candidate oracle =
      let expected = Int32.bits_of_float (oracle fa fb) in
      let actual = word_to_int32 (candidate na nb) in
      check label (if Float.is_nan (Int32.float_of_bits expected)
        then Float.is_nan (Int32.float_of_bits actual) else actual = expected)
    in
    operation "F32 add" f32_add (+.); operation "F32 sub" f32_sub (-.);
    operation "F32 mul" f32_mul ( *. ); operation "F32 div" f32_div (/.);
    check "F32 compare" (f32_is_lt na nb = (fa < fb));
    let expected = if fa <= 0. then 0l else if fa >= 4294967296. then Int32.minus_one else Int64.to_int32 (Int64.of_float fa) in
    compare_bits "F32 saturating U32" (f32_to_u32 na) expected
  end;
  compare_bits "U32 to F32" (u32_to_f32 na) (Int32.bits_of_float (Int64.to_float x))
let[@inline never] rec arithmetic n a b =
  if n=0 then a else arithmetic (n-1) (u32_add (u32_mul a b) b) b
let () =
  let boundaries=[0l;1l;2l;31l;32l;127l;128l;255l;256l;65535l;65536l;0x10ffffl;Int32.max_int;Int32.min_int;Int32.minus_one;0x7f800000l;0xff800000l;0x7fc12345l;0xffc12345l;0x80000000l] in
  List.iter (fun a -> List.iter (check_pair a) boundaries) boundaries;
  let rng=Random.State.make [|0x32;0x424c4f54|] in
  let value () = Int32.logor (Int32.of_int (Random.State.bits rng)) (Int32.shift_left (Int32.of_int (Random.State.int rng 4)) 30) in
  for _=1 to 10000 do check_pair (value ()) (value ()) done;
  List.iter (fun n -> compare_bits "Nat conversion masks low word" (word_of_int n) (Int32.of_int n))
    [0;1;-1;min_int;max_int;0xffff_ffff;0x1_0000_0000;0xffff_ffff_ffff];
  let a=W32 0xffff_ffff and b=W32 0x8765_4321 in
  Gc.full_major (); let before=Gc.allocated_bytes () in
  let result=Sys.opaque_identity (arithmetic 100000 a b) in
  let allocated=Gc.allocated_bytes () -. before in
  ignore (Sys.opaque_identity result);
  check "U32 arithmetic does not allocate per operation" (allocated < 4096.);
  Printf.printf "%d native word/scalar checks passed; arithmetic allocated %.0f bytes\n" !checks allocated
