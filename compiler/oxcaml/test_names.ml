(* Native identity equality: semantic oracle, sharing, stack and heap regressions. *)
open Base
let checks = ref 0
let check label condition = incr checks; if not condition then failwith label
let text = text_of_utf8
let legacy left right =
  Ox_model.f_name_equal_result
    (Ox_model.f_name_equal_walk left right left right true)
let verify left right expected =
  check "legacy equality oracle" (legacy left right = expected);
  check "Base equality" (string_eq left right = expected);
  check "model equality" (Ox_model.f_name_equal left right = expected)
let[@inline never] rec repeat n left right total =
  if n = 0 then total else
    let same = Ox_model.f_name_equal (Sys.opaque_identity left) (Sys.opaque_identity right) in
    repeat (n - 1) left right (if same then total + 1 else total)
let () =
  let names = [""; "a"; "ab"; "abc"; "b"; "\000"; "a\000b";
    "std/prelude::a"; "$module[x].a"; "åλ😀"; "åλ😁"; "é"; "e\204\129"] in
  List.iter (fun a -> List.iter (fun b -> verify (text a) (text b) (a = b)) names) names;
  let suffix = text (String.make 8192 'x' ^ "😀") in
  verify suffix suffix true;
  verify (SCon (Chr (Base.W32 0x61), suffix)) (SCon (Chr (Base.W32 0x61), suffix)) true;
  verify (SCon (Chr (Base.W32 0x61), suffix)) (SCon (Chr (Base.W32 0x62), suffix)) false;
  verify suffix (SCon (Chr (Base.W32 0x61), suffix)) false;
  (* Even values constructed below the validating protocol retain exact bits. *)
  List.iter (fun x -> List.iter (fun y ->
    verify (SCon (Chr x, SNil)) (SCon (Chr y, SNil)) (Base.u32_is_eq x y))
    [(Base.W32 0x0); (Base.W32 0x10ffff); (Base.W32 0x7fff_ffff); (Base.W32 0x8000_0000); (Base.W32 0xffff_ffff)])
    [(Base.W32 0x0); (Base.W32 0x10ffff); (Base.W32 0x7fff_ffff); (Base.W32 0x8000_0000); (Base.W32 0xffff_ffff)];
  let prefix = String.make 200000 'p' in
  verify (text prefix) (text prefix) true;
  verify (text (prefix ^ "a")) (text (prefix ^ "b")) false;
  let random = Random.State.make [|0x424c4f54; 1|] in
  for i = 0 to 1999 do
    let a = String.init (Random.State.int random 80) (fun _ -> Char.chr (32 + Random.State.int random 95)) in
    let b = if i mod 3 = 0 then a else a ^ string_of_int i in
    verify (text a) (text b) (a = b)
  done;
  List.iter (fun (am, an, bm, bn, expected) ->
    check "nominal identity keeps module and name"
      (Ox_model.f_type_id_equal (Ox_model.TypeId (text am, text an))
        (Ox_model.TypeId (text bm, text bn)) = expected))
    ["m", "n", "m", "n", true; "m", "n", "other", "n", false;
     "m", "n", "m", "other", false; "a::b", "c", "a", "b::c", false;
     "", "😀", "", "😀", true; "å", "λ", "a", "λ", false];
  let a = text "std/prelude::some.identifier" in
  let b = text "std/prelude::some.identifier" in
  List.iter (fun (left, right, expected) ->
    Gc.full_major ();
    let before = Gc.allocated_bytes () in
    let total = repeat 100000 left right 0 in
    let allocated = Gc.allocated_bytes () -. before in
    check "comparison result" (total = expected);
    (* Allow fixed counter overhead, not even one allocation per comparison. *)
    check "no per-comparison heap allocation" (allocated < 4096.))
    [a, a, 100000; a, b, 100000; a, text "other", 0];
  Gc.full_major ();
  let n = 100000 in
  let before = Gc.allocated_bytes () in
  let constructed = ref SNil in
  for i = 0 to n - 1 do
    constructed := SCon (Chr (Base.word_of_int (Sys.opaque_identity i land 0xffff)), !constructed)
  done;
  let allocated = Gc.allocated_bytes () -. before in
  check "constructed text length" (string_length !constructed = n);
  check "no redundant character wrapper" (allocated < 25. *. float_of_int n);
  Printf.printf "%d native name equality checks passed\n" !checks
