(* Byte encoding is independent of the compiler's term representation. *)
let byte output value =
  if value < 0 || value > 255 then invalid_arg "Wasm byte outside [0,255]";
  Buffer.add_char output (Char.chr value)

let u32 output value =
  let rec loop value =
    let low = Int32.to_int (Int32.logand value 0x7fl) in
    let rest = Int32.shift_right_logical value 7 in
    byte output (if rest = 0l then low else low lor 0x80);
    if rest <> 0l then loop rest
  in
  loop value

let i32 output value =
  let rec loop value =
    let low = Int32.to_int (Int32.logand value 0x7fl) in
    let rest = Int32.shift_right value 7 in
    let done_ =
      (rest = 0l && low land 0x40 = 0) ||
      (rest = -1l && low land 0x40 <> 0)
    in
    byte output (if done_ then low else low lor 0x80);
    if not done_ then loop rest
  in
  loop value

let length output value =
  if value < 0 || Int64.of_int value > 0xffff_ffffL then
    invalid_arg "Wasm length exceeds u32";
  u32 output (Int32.of_int value)

let string output value =
  length output (String.length value);
  Buffer.add_string output value

let section output id contents =
  byte output id;
  length output (Buffer.length contents);
  Buffer.add_buffer output contents

let encode writer value =
  let output = Buffer.create 16 in
  writer output value;
  Buffer.contents output
