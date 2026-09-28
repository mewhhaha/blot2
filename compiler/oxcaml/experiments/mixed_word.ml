type char32 = Chr of int32# [@@unboxed]
type text = SNil | SCon of char32 * text
external unbox : int32 -> int32# = "%unbox_int32"
external box : int32# -> int32 = "%box_int32"
let[@inline always] make c t = SCon (Chr (unbox c), t)
let code = function Chr c -> box c
let () =
  let x = make (Sys.opaque_identity 0x80000000l) SNil in
  let y = make (Sys.opaque_identity 0x80000000l) SNil in
  (try Printf.printf "generic comparison result: %b\n" (x = y)
   with Invalid_argument message -> Printf.printf "generic comparison rejected: %s\n" message);
  let before = Gc.allocated_bytes () in
  let value = ref SNil in
  for i = 0 to 99999 do value := make (Int32.of_int (Sys.opaque_identity i)) !value done;
  let allocated = Gc.allocated_bytes () -. before in
  ignore (Sys.opaque_identity !value);
  Printf.printf "unboxed text construction: %.0f bytes for 100000 characters\n" allocated
