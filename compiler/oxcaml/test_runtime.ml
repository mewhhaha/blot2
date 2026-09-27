open Base
let count = ref 0
let check name condition = incr count; if not condition then failwith name
let text = text_of_utf8
let () =
  List.iter (fun s -> check "UTF-8 round trip" (text_to_utf8 (text s) = s))
    [""; "ascii"; "\000"; "åλ😀"; "a\r\nb"; "\244\143\191\191"];
  List.iter (fun s -> check "UTF-8 rejection" (try ignore (text s); false with Invalid_argument _ -> true))
    ["\128"; "\192\128"; "\237\160\128"; "\244\144\128\128"; "\240\159"];
  check "Unicode length" (string_length (text "a😀λ") = 3);
  check "Unsigned compare" (u32_is_gt (-1l) Int32.max_int);
  check "Unsigned division" (u32_div (-1l) 3l = 1431655765l);
  check "Unsigned wrapping" (u32_add (-1l) 1l = 0l);
  check "Natural subtraction" (nat_sub 1 2 = 0);
  check "Natural division by zero" (nat_div 17 0 = 0 && nat_mod 17 0 = 17);
  check "Natural range" (nat_read (text "281474976710655") = Some nat_mask);
  check "Natural overflow" (nat_read (text "281474976710656") = None);
  check "F32 signed zero" (f32_neg 0l = Int32.min_int);
  check "F32 rounding" (f32_add 0x4b800000l 0x3f800000l = 0x4b800000l);
  List.iter (fun (s,expected) ->
    check ("Exact decimal " ^ s) (Ox_numeric_literal.f_read (text s) = Some expected))
    ["1.000000059604644775390625", 0x3f800000l;
     "1.000000059604644775390626", 0x3f800001l;
     "1.000000178813934326171875", 0x3f800002l;
     "0.0",0l; "1.40129846432481707092372958328991613128026194187651577175706828388979108268586060148663818836212158203125e-45",1l];
  let keys = [""; "a"; "aa"; "ab"; "b"; "😀"; "λ"; "\000"; "a\000b"] in
  let map = List.mapi (fun i k -> text k,i) keys |> List.fold_left (fun m (k,v) -> map_set m k v) MTip in
  List.iteri (fun i k -> check "Patricia/index compatibility" (Ox_index.f_find map (text k) = Some i)) keys;
  check "Patricia missing key" (Ox_index.f_find map (text "absent") = None);
  let replacement = map_set map (text "a") 99 in
  check "Persistent map update" (Ox_index.f_find replacement (text "a") = Some 99 && Ox_index.f_find map (text "a") = Some 1);
  check "Right-biased union" (Ox_index.f_find (map_union map replacement) (text "a") = Some 99);
  let prefix = String.make 4480 'x' in
  let long_keys = [prefix; prefix ^ "a"; prefix ^ "b"; prefix ^ "😀"; prefix ^ "λ"] in
  let long_map = List.mapi (fun i k -> text k,i) long_keys |>
    List.fold_left (fun m (k,v) -> map_set m k v) MTip in
  List.iteri (fun i key -> check "Long shared-prefix lookup"
    (Ox_index.f_find long_map (text key) = Some i)) long_keys;
  let rec validate_bits = function
    | MTip | MLeaf _ -> ()
    | MNode(pos,lo,hi) ->
      List.iter (fun (k,_) -> check "Patricia low branch" (not (key_bit k pos))) (map_bindings lo);
      List.iter (fun (k,_) -> check "Patricia high branch" (key_bit k pos)) (map_bindings hi);
      validate_bits lo; validate_bits hi
  in validate_bits long_map;
  let random = Random.State.make [|42|] in
  let map = ref MTip in
  let reference = Hashtbl.create 4096 in
  for i = 1 to 10000 do
    let key = string_of_int (Random.State.int random 4000) in
    map := map_set !map (text key) i;
    Hashtbl.replace reference key i
  done;
  Hashtbl.iter (fun k v -> check "Random Patricia lookup" (Ox_index.f_find !map (text k) = Some v)) reference;
  check "Stable sort" (list_sort (fun (a,_) (b,_) -> a <= b) [2,0;1,1;2,2;1,3] = [1,1;1,3;2,0;2,2]);
  Printf.printf "%d native runtime checks passed\n" !count
