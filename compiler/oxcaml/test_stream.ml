(* Independent response byte oracle, including unaligned block/flush boundaries. *)
module O = Ox_native_output
module T = Ox_native_transport
let checks = ref 0
let check label condition = incr checks; if not condition then failwith label
let capture operation =
  let path = Filename.temp_file "blot-stream-" ".bin" in
  Fun.protect (fun () ->
    let channel = open_out_bin path in
    let outcome = try operation channel; Ok () with exn -> Error exn in
    close_out channel;
    let input = open_in_bin path in
    let bytes = really_input_string input (in_channel_length input) in
    close_in input;
    outcome, bytes
  ) ~finally:(fun () -> Sys.remove path)
let oracle count header blocks =
  let bytes = Bytes.make (4+4*count) '\000' in
  Bytes.set_int32_le bytes 0 (Int32.of_int count);
  let offset = ref 4 in
  let put word size =
    for i = 0 to size-1 do
      Bytes.set bytes !offset (Char.chr (Int32.to_int (Int32.logand (Int32.shift_right_logical word (i*8)) 255l)));
      incr offset
    done
  in
  List.iter (fun word -> put word 4) header;
  List.iter (fun (O.Block (size, words)) ->
    let left = ref size in
    List.iter (fun word -> let size = min 4 !left in put word size; left := !left - size) words
  ) blocks;
  Bytes.to_string bytes
let test header blocks =
  let total = 4*List.length header + List.fold_left (fun n (O.Block (size,_)) -> n+size) 0 blocks in
  let count = (total+3)/4 in
  let outcome, bytes = capture (fun out -> T.write_response out (Int32.of_int count) header blocks) in
  check "valid response accepted" (outcome = Ok ());
  check "stream equals complete-frame byte oracle" (bytes = oracle count header blocks)
let () =
  List.iter (fun length ->
    let header = List.init length (fun i -> Int32.mul (Int32.of_int i) 0x9e3779b9l) in
    for suffix = 0 to 7 do
      test header [O.Block (1,[Int32.minus_one]); O.Block (suffix,List.init ((suffix+3)/4) (fun _ -> 0x87654321l))]
    done;
    test header []
  ) [0;1;2;16381;16382;16383;16384;16385;32769];
  let random = Random.State.make [|2026; 0x535452|] in
  for _ = 1 to 500 do
    let header = List.init (Random.State.int random 6) (fun _ -> Int32.of_int (Random.State.bits random)) in
    let blocks = List.init (Random.State.int random 20) (fun _ ->
      let size = Random.State.int random 80 in
      O.Block (size,List.init ((size+3)/4) (fun _ -> Int32.logor Int32.min_int (Int32.of_int (Random.State.bits random))))) in
    test header blocks
  done;
  List.iter (fun (count,header,blocks,message) ->
    let outcome, bytes = capture (fun out -> T.write_response out count header blocks) in
    check "invalid plan rejected" (match outcome with Error (Failure actual) -> actual=message | _ -> false);
    check "invalid plan publishes no frame prefix" (bytes="")
  ) [0l,[1l],[],"native response length mismatch";
     2l,[],[],"native response has excess padding";
     2l,[],[O.Block(5,[1l])],"native block is truncated";
     1l,[],[O.Block(4,[1l;2l])],"native block has excess words";
     1l,[],[O.Block(-1,[])],"native block is truncated";
     0x01000001l,[],[],"native response exceeds 16M words"];
  Printf.printf "%d bounded-stream checks passed\n" !checks
