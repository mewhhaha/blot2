(* Native transient construction: ordered semantic oracles and allocation guards. *)
open Base
let checks = ref 0
let check label condition = incr checks; if not condition then failwith label
let measure f =
  Gc.full_major ();
  let before = Gc.allocated_bytes () in
  let result = f () in
  let allocated = Gc.allocated_bytes () -. before in
  Sys.opaque_identity result, allocated
let rec text_of_words = function
  | [] -> SNil | x::xs -> SCon(Chr x,text_of_words xs)
let[@inline never] rec lookup n map key total =
  if n = 0 then total else
  lookup (n-1) map key (total + Ox_index.f_get map (Sys.opaque_identity key) (-1))
let () =
  List.iter (fun fuel ->
    check "bounded merge preserves its accumulator and suffix order"
      (list_merge_go (<=) fuel ([9;8],[1;3],[2;4]) =
       (if fuel=0 then [8;9;1;3;2;4] else if fuel=1 then [8;9;1;3;2;4] else [8;9;1;2;3;4]))) [0;1;2];
  List.iter (fun raw ->
    for offset = 0 to 100 do
      let expected = offset = 0 || Base.u32_is_ne
        (Base.u32_and (Base.u32_shrn raw (max 0 (32 - offset))) (Base.W32 0x1)) (Base.W32 0x0) in
      check "character bits preserve unsigned and oversized offsets"
        (Ox_index.f_character_bit (Chr raw) offset = expected)
    done) [(Base.W32 0x0); (Base.W32 0x1); (Base.W32 0x2); (Base.W32 0x7fff_ffff); (Base.W32 0x8000_0000); (Base.W32 0xffff_ffff); (Base.W32 0x10ffff)];
  let random = Random.State.make [|0x424c4f54; 31|] in
  for trial = 0 to 499 do
    let raw n = List.init n (fun _ -> Base.word_of_int32 (Random.State.int32 random Stdlib.Int32.max_int)) in
    let left = text_of_words (raw (Random.State.int random 50)) in
    let right = text_of_words (raw (Random.State.int random 50)) in
    let expected = string_append_portable left right in
    check "append preserves raw scalar order" (string_eq (string_append left right) expected);
    check "append shares immutable suffix" (string_drop (string_append left right) (string_length left) == right);
    let xs = List.init (Random.State.int random 50) (fun _ -> Random.State.int random 100) in
    check "list append" (list_append xs [1;2;3] = List.rev_append (List.rev xs) [1;2;3]);
    let parts = List.init (Random.State.int random 12) (fun _ -> text_of_words (raw (Random.State.int random 15))) in
    let delimiter = text_of_words [(Base.W32 0x0); (Base.W32 0xffff_ffff); (Base.W32 0x10ffff)] in
    let expected = match parts with [] -> SNil | first::rest ->
      List.fold_left (fun acc part -> string_append_portable (string_append_portable acc delimiter) part) first rest in
    check "join raw scalar order" (string_eq (string_join parts delimiter) expected)
  done;
  List.iter (fun parts ->
    let texts = List.map text_of_utf8 parts in
    check "join Unicode/NUL/empty parts" (text_to_utf8 (string_join texts (text_of_utf8 "\000λ")) = String.concat "\000λ" parts))
    [[]; [""]; [""; ""]; ["a"; ""; "😀"; "å"; "e\204\129"]];
  let keys = Array.init 2000 (fun i -> text_of_utf8 (Printf.sprintf "prefix/λ/%04d/😀" i)) in
  let map = ref MTip in
  for i = 0 to 5999 do
    let key = keys.(Random.State.int random (Array.length keys)) in
    let before = !map in
    let old = map_find before key in
    map := map_set !map key i;
    check "retained map is immutable" (map_find before key = old);
    check "direct default lookup" (Ox_index.f_get !map key (-1) = i);
    if i mod 100 = 0 then begin
      let bindings = map_bindings !map in
      check "fold values order" (map_values !map = List.map snd bindings);
      for fuel = 0 to 4 do
        check "bounded lookup preserves fuel" (Ox_index.f_get_loop fuel !map key key 0 (-1) =
          Option.value (Ox_index.f_find_loop fuel !map key key 0) ~default:(-1))
      done
    end
  done;
  let left = !map in
  let right = List.fold_left (fun acc i -> map_set acc keys.(i) (-i)) MTip (List.init 1000 Fun.id) in
  let expected = List.fold_left (fun acc (key,value) -> map_set acc key value) left (map_bindings right) in
  check "union is ordered, persistent, right-biased" (map_bindings (map_union left right) = map_bindings expected);
  Array.iter (fun key -> check "lookup matches oracle" (Ox_index.f_get left key (-1) = Option.value (map_find left key) ~default:(-1))) keys;
  check "absent lookup uses default" (Ox_index.f_get left (text_of_utf8 "missing") (-99) = -99);
  let set = set_from_list (Array.to_list keys @ [keys.(0); keys.(0)]) in
  check "set size" (set_size set = Array.length keys);
  check "set order" (set_to_list set = List.map fst (map_bindings set));
  let huge = text_of_utf8 (String.make 500000 'x') in
  let suffix = text_of_utf8 "tail😀" in
  let appended, string_bytes = measure (fun () -> string_append huge suffix) in
  check "deep append stack safety" (string_length appended = 500005);
  check "deep append shares suffix" (string_drop appended 500000 == suffix);
  let xs = List.init 500000 Fun.id in
  let joined, list_bytes = measure (fun () -> list_append xs [42]) in
  check "deep list append stack safety" (List.length joined = 500001);
  check "deep list append ordering" (List.hd joined = 0 && List.hd (list_drop joined 500000) = 42);
  if supports_tmc then begin
    check "text append builds one output spine" (string_bytes < 25. *. 500000.);
    check "list append builds one output spine" (list_bytes < 25. *. 500000.)
  end;
  let hit = map_set left keys.(0) 7 in
  let total, lookup_bytes = measure (fun () -> lookup 100000 hit keys.(0) 0) in
  check "repeated lookup result" (total = 700000);
  Printf.printf "lookup allocated %.0f bytes\n%!" lookup_bytes;
  check "lookup avoids transient option allocation" (lookup_bytes < 4096.);
  let bindings = map_bindings left in
  let values, value_bytes = measure (fun () -> map_values left) in
  let old_values, old_value_bytes = measure (fun () -> List.map snd (map_bindings left)) in
  check "map values allocation oracle" (values = old_values && values = List.map snd bindings);
  check "map values eliminate materialized bindings" (value_bytes < old_value_bytes *. 0.8);
  let count, size_bytes = measure (fun () -> set_size set) in
  let old_count, old_size_bytes = measure (fun () -> List.length (map_bindings set)) in
  check "set size allocation oracle" (count = old_count);
  check "set size does not construct bindings" (size_bytes < old_size_bytes *. 0.4);
  Printf.printf "%d native builder/index checks passed\n" !checks;
  Printf.printf "allocation bytes: text_append=%.0f list_append=%.0f lookup_100000=%.0f map_values=%.0f (oracle=%.0f) set_size=%.0f (oracle=%.0f)\n"
    string_bytes list_bytes lookup_bytes value_bytes old_value_bytes size_bytes old_size_bytes
