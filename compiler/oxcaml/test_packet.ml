(* Validate complete packet accounting before output, and bound output scratch. *)
open Base
module O = Ox_native_output
let checks = ref 0
let check label value = incr checks; if not value then failwith label
let expected count header blocks =
  let bytes = Bytes.make (4 + 4 * count) '\000' in
  Bytes.set_int32_le bytes 0 (Stdlib.Int32.of_int count);
  let at = ref 4 in
  let word value length = for i = 0 to length - 1 do
    Bytes.set bytes !at (Char.chr ((Base.u32_to_nat value lsr (8*i)) land 255)); incr at
  done in
  List.iter (fun w -> word w 4) header;
  List.iter (fun (O.Block(length,words)) ->
    let remaining = ref length in
    List.iter (fun w -> let n = min 4 !remaining in word w n; remaining := !remaining - n) words) blocks;
  bytes
let verify header blocks =
  let used = List.length header * 4 + List.fold_left (fun n (O.Block(length,_)) -> n+length) 0 blocks in
  let count = (used + 3) / 4 in
  let out = Buffer.create 64 in
  let writes = ref 0 in
  Ox_native_transport.write_packet (fun bytes offset length ->
    incr writes;
    check "bounded output chunk" (length > 0 && length <= 65536);
    Buffer.add_subbytes out bytes offset length) (Base.word_of_int count) header blocks;
  check "exact little-endian packet and zero padding" (Buffer.contents out = Bytes.to_string (expected count header blocks));
  check "one or more writes" (!writes > 0)
let () =
  verify [] [];
  verify [(Base.W32 0x424c4f54);(Base.W32 0xd)] [];
  for a = 0 to 12 do for b = 0 to 12 do
    let block n = O.Block(n,List.init ((n+3)/4) (fun i -> Base.word_of_int (i lxor 0x8f123456))) in
    verify [(Base.W32 0xffff_ffff); (Base.W32 0x8000_0000)] [block a; block b; O.Block(0,[])]
  done done;
  List.iter (fun n ->
    let words = List.init ((n+3)/4) (fun i -> Base.word_of_int (i lxor 0x80abcdef)) in
    verify [(Base.W32 0x1);(Base.W32 0x2)] [O.Block(1,[(Base.W32 0xff)]); O.Block(n,words); O.Block(7,[(Base.W32 0x2a);(Base.W32 0xffff_ffff)])])
    [65525;65526;65527;65528;65529;65530;65531;65532;65533;65534;65535;65536;65537;131077];
  List.iter (fun (count,header,blocks,message) ->
    let called = ref false in
    let caught = try
      Ox_native_transport.write_packet (fun _ _ _ -> called := true) count header blocks; false
    with Failure actual -> actual = message in
    check "malformed packet error" caught;
    check "malformed packet publishes no prefix" (not !called))
    [(Base.W32 0x0),[(Base.W32 0x1)],[],"native response length mismatch";
     (Base.W32 0x1),[],[O.Block(0,[(Base.W32 0x1)])],"native block has excess words";
     (Base.W32 0x1),[],[O.Block(4,[])],"native block is truncated";
     (Base.W32 0x1),[],[],"native response has excess padding";
     (Base.W32 0x1000001),[],[],"native response exceeds 16M words";
     (Base.W32 0x1),[],[O.Block(-1,[])],"native block is truncated";
     (Base.W32 0x1),[],[O.Block(1,[(Base.W32 0x1);(Base.W32 0x2)])],"native block has excess words"];
  let count = 300000 in
  let words = List.init count (fun i -> Base.word_of_int i) in
  let packet = [O.Block(count*4,words)] in
  let emitted = ref 0 in
  Gc.full_major ();
  let before = Gc.allocated_bytes () in
  Ox_native_transport.write_packet (fun _ _ n -> emitted := !emitted+n) (Base.word_of_int count) [] packet;
  let allocated = Gc.allocated_bytes () -. before in
  check "large packet size" (!emitted = 1200004);
  check "large packet has bounded scratch, not a full response copy" (allocated < 70000.);
  Printf.printf "%d bounded packet checks passed; 1200004 output bytes, %.0f allocated bytes\n" !checks allocated
