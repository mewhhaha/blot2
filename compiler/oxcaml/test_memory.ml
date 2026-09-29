(* Representation and traversal checks independent of source regression tests. *)
open Base
module R = Ox_native_request
let checks = ref 0
let check label condition = incr checks; if not condition then failwith label
let measured f =
  Gc.full_major ();
  let before = Gc.allocated_bytes () in
  let value = f () in
  let allocated = Gc.allocated_bytes () -. before in
  value, allocated
let words values =
  let bytes = Bytes.create (4 * List.length values) in
  List.iteri (fun i value -> Bytes.set_int32_le bytes (4*i) value) values;
  bytes
let cursor bytes offset remaining = R.Cursor (bytes, offset, remaining, [||], 0l)
let scanner bytes offset remaining count reversed valid =
  let state = cursor bytes offset remaining in
  let reference = R.f_scan_characters count (R.CharacterScan (state, reversed, valid)) in
  let actual = R.f_scan_string count state reversed valid in
  check "packed scanner matches allocation-heavy oracle" (actual = reference)
let () =
  let random = Random.State.make [|0x424c4f54; 2026; 9; 28|] in
  for _ = 1 to 5000 do
    let bits = Int32.logor (Int32.of_int (Random.State.bits random))
      (if Random.State.bool random then Int32.min_int else 0l) in
    check "immediate character retains U32 bits" (char_to_u32 (char_of_u32 bits) = bits);
    check "unsigned immediate conversion" (u32_to_nat bits = Int64.to_int (unsigned bits))
  done;
  let edges = [|0l; 1l; 31l; 0x7fffffffl; 0x80000000l; 0xfffffffel; 0xffffffffl|] in
  let arithmetic a b =
    let x = unsigned a and y = unsigned b in
    check "U32 comparison matches unsigned Int64 oracle" (u32_cmp a b = cmp (Int64.compare x y));
    check "U32 ordering matches unsigned Int64 oracle"
      (u32_is_lt a b = (x < y) && u32_is_le a b = (x <= y)
       && u32_is_gt a b = (x > y) && u32_is_ge a b = (x >= y));
    check "U32 division matches unsigned Int64 oracle"
      (u32_div a b = if b = 0l then 0l else Int64.to_int32 (Int64.div x y));
    check "U32 remainder matches unsigned Int64 oracle"
      (u32_mod a b = if b = 0l then a else Int64.to_int32 (Int64.rem x y));
    check "U32 float rounding unchanged" (u32_to_f32 a = Int32.bits_of_float (Int64.to_float x))
  in
  Array.iter (fun a -> Array.iter (arithmetic a) edges) edges;
  for _ = 1 to 5000 do
    let random_word () = Int32.logor (Int32.of_int (Random.State.bits random))
      (if Random.State.bool random then Int32.min_int else 0l) in
    arithmetic (random_word ()) (random_word ())
  done;
  List.iter (fun value -> check "raw character edge bits"
    (char_to_u32 (char_of_u32 value) = value))
    [0l; 0x10ffffl; Int32.max_int; Int32.min_int; Int32.minus_one];
  let alphabet = [|0l;97l;0x3bbl;0x1f600l;0x10ffffl;0xd800l;0xdfffl;0x110000l;Int32.minus_one|] in
  for _ = 1 to 2000 do
    let size = Random.State.int random 48 in
    let values = List.init size (fun _ -> alphabet.(Random.State.int random (Array.length alphabet))) in
    let bytes = words (77l :: values) in
    let count = Random.State.int random (size + 3) in
    let prefix = if Random.State.bool random then SNil else text_of_utf8 "prefix😀" |> string_reverse in
    scanner bytes 1 size count prefix true;
    scanner bytes 1 size count prefix false
  done;
  List.iter (fun size ->
    let bytes = words (List.init size (fun i -> Int32.of_int (if i mod 3 = 0 then 0x1f600 else 97))) in
    scanner bytes 0 size size SNil true;
    scanner bytes 0 size (size+1) SNil true;
    if size > 0 then begin
      Bytes.set_int32_le bytes ((size-1)*4) 0xd800l;
      scanner bytes 0 size (size+1) SNil true
    end
  ) [0;1;2;257;65536];
  let bytes = words [97l;0x1f600l] in
  (match R.f_scan_string 2 (cursor bytes 0 2) SNil true with
  | R.CompleteString (value, _) ->
    Bytes.fill bytes 0 (Bytes.length bytes) '\000';
    check "published text does not retain mutable frame storage" (text_to_utf8 value = "a😀")
  | _ -> failwith "valid string rejected");
  let n = 200000 in
  let left = List.init n Fun.id and right = [n;n+1] in
  let appended, list_bytes = measured (fun () -> list_append (Sys.opaque_identity left) right) in
  check "append order and immutable tail" (List.length appended = n+2 && list_drop appended n == right);
  if use_tail_mod_cons then check "one list spine, no reverse copy" (list_bytes < 25. *. float_of_int n);
  let text = text_of_utf8 (String.make n 'x') and suffix = text_of_utf8 "λ" in
  let joined, text_bytes = measured (fun () -> string_append (Sys.opaque_identity text) suffix) in
  check "text append order and immutable tail" (string_length joined = n+1 && string_drop joined n == suffix);
  if use_tail_mod_cons then check "one text spine, no reverse copy" (text_bytes < 25. *. float_of_int n);
  let parts = List.init 1000 (fun i -> string_of_int i) in
  let joined = string_join (List.map text_of_utf8 parts) (text_of_utf8 "λ") in
  check "linear join order" (text_to_utf8 joined = String.concat "λ" parts);
  List.iter (fun parts ->
    check "join edge cases" (text_to_utf8 (string_join (List.map text_of_utf8 parts) (text_of_utf8 ":")) = String.concat ":" parts)
  ) [[];[""];["a"];["";""];["a";"";"c"]];
  let keys = List.init 1000 (fun i -> text_of_utf8 ("prefixλ" ^ string_of_int i)) in
  let map = List.mapi (fun i key -> key,i) keys |> List.fold_left (fun m (k,v) -> map_set m k v) MTip in
  check "value traversal order" (map_values map = List.map snd (map_bindings map));
  let set = set_from_list keys in
  check "set traversal order" (set_to_list set = List.map fst (map_bindings set));
  check "set count" (set_size set = List.length (map_bindings set));
  let other = List.mapi (fun i key -> key,-i) keys |> List.fold_left (fun m (k,v) -> if v mod 2 = 0 then map_set m k v else m) MTip in
  let reference = List.fold_left (fun m (k,v) -> map_set m k v) map (map_bindings other) in
  check "streamed union preserves right bias" (map_bindings (map_union map other) = map_bindings reference);
  check "union keeps input snapshots" (map_values map = List.map snd (map_bindings map));
  let data = words (List.init n (fun _ -> 97l)) in
  let _, old_bytes = measured (fun () -> R.f_scan_characters n (R.CharacterScan (cursor data 0 n, SNil, true))) in
  let decoded, scan_bytes = measured (fun () -> R.f_scan_string n (cursor data 0 n) SNil true) in
  check "scanner removes per-character cursor allocation" (scan_bytes < old_bytes *. 0.6);
  if use_tail_mod_cons then
    check "scanner allocates only result text" (scan_bytes < 25. *. float_of_int n);
  (match decoded with R.CompleteString (value,_) -> check "large decoded length" (string_length value=n) | _ -> failwith "large scan");
  Printf.printf "scanner: legacy=%.3f packed=%.3f allocated bytes/character\n" (old_bytes /. float_of_int n) (scan_bytes /. float_of_int n);
  Printf.printf "append: list=%.3f text=%.3f allocated bytes/element (tmc=%b)\n" (list_bytes /. float_of_int n) (text_bytes /. float_of_int n) use_tail_mod_cons;
  Printf.printf "%d native memory checks passed\n" !checks
