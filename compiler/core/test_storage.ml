let checks = ref 0
let check label value = incr checks; if not value then failwith label
let invalid thunk = try thunk (); false with Invalid_argument _ -> true
let list_text words = List.fold_right (fun value tail -> Core_text.cons (Core_text.Chr value, tail)) words Core_text.empty
let () =
  Random.init 73481;
  List.iter (fun text ->
    let value = Core_text.of_utf8 text in
    check "UTF-8 round trip" (Core_text.to_utf8 value = text);
    let words = ref [] in Core_text.iter (fun c -> words := c :: !words) value;
    let linked = list_text (List.rev !words) in
    check "packed/link equality" (Core_text.equal value linked);
    for i=0 to Core_text.length value do
      let a=Core_text.drop value i and b=Core_text.drop linked i in
      check "suffix hashes" (Core_text.hash a=Core_text.hash b);
      check "suffix equality" (Core_text.equal a b)
    done;
    check "double reverse" (Core_text.equal value (Core_text.reverse (Core_text.reverse value)))
  ) ["";"x";"Å界😀";"a\000b";String.make 8192 'a'];
  List.iter (fun text -> check "invalid Unicode" (invalid (fun () -> ignore(Core_text.of_utf8 text))))
    ["\xc0\xaf";"\xed\xa0\x80";"\xf4\x90\x80\x80";"\xf0\x9f";"\x80"];
  for _=1 to 400 do
    let length=Random.int 90 in
    let words=List.init length (fun _ -> Random.bits () land 0xffffffff) in
    let linked=list_text words in
    let bytes=Bytes.of_string (Core_text.flatten linked) in
    let packed=Core_text.of_words bytes 0 length in
    Bytes.fill bytes 0 (Bytes.length bytes) '\000';
    check "owned input" (Core_text.equal linked packed);
    let other=list_text [0;0xffffffff;65] in
    check "append" (Core_text.equal (Core_text.append packed other) (list_text (words @ [0;0xffffffff;65])));
    for i=0 to length do
      check "random suffix" (Core_text.equal (Core_text.drop packed i) (Core_text.drop linked i))
    done
  done;
  let module Oracle=Map.Make(Int) in
  let current=ref Core_index.empty and expected=ref Oracle.empty in
  let snapshots=ref [] in
  let high=[0;31;32;1023;1024;1 lsl 31;1 lsl 47;max_int] in
  for i=0 to 9999 do
    let key=if i<List.length high then List.nth high i else Random.int 5000 in
    current:=Core_index.add key i !current;expected:=Oracle.add key i !expected;
    if i mod 250=0 then snapshots:=(!current,!expected)::!snapshots;
    check "index present" (Core_index.find key !current=Oracle.find_opt key !expected);
    let probe=Random.int 8192 in
    check "index absent" (Core_index.find probe !current=Oracle.find_opt probe !expected)
  done;
  List.iter (fun (tree,oracle) -> check "persistent snapshot" (Core_index.bindings tree=Oracle.bindings oracle)) !snapshots;
  check "negative key rejected" (invalid(fun () -> ignore(Core_index.add (-1) 0 !current)));
  let symbol=Core_symbols.intern (Base.text_of_utf8 "persisted") in
  for _=1 to 3 do Core_nodes.begin_request (); Gc.full_major () done;
  check "live symbol witness" (symbol.id=(Core_symbols.intern (list_text [112;101;114;115;105;115;116;101;100])).id);
  let module C=Core_nodes.Cache(struct type t=int let hash x=x let equal=(=) end) in
  let cache=C.create "storage-test" and calls=ref 0 in
  let value () = incr calls; !calls in
  check "memo first" (C.memo cache 1 value=1);
  check "memo exact key" (C.memo cache 1 value=1 && !calls=1);
  Core_nodes.begin_request ();
  check "memo revision boundary" (C.memo cache 1 value=2);
  let module M=Sem_model in
  let a=M.make_ArrayTy (M.make_U32Ty ()) and b=M.make_ArrayTy (M.make_U32Ty ()) in
  check "canonical type" (M.id_Ty a=M.id_Ty b);
  check "ground type flags" (M.type_flags a=0);
  let variable=M.make_VariableTy 7 in
  check "open type flags" (M.type_flags (M.make_ArrayTy variable)<>0);
  let row=M.make_EffectRow [] (M.make_RowVariable 3) in
  check "open row flags" (M.type_flags (M.make_FunctionTy a b row)<>0);
  Printf.printf "%d native storage checks passed\n" !checks
