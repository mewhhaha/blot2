(* Version-13 framed transport. Framing errors are fatal; complete malformed
   payloads go to the normal decoder and preserve the live session on failure. *)
open Base
let max_words = 16777216
let read_exact bytes offset length = really_input stdin bytes offset length
let f_receive () () =
  match input_char stdin with
  | exception End_of_file -> None
  | first ->
    let prefix = Bytes.create 4 in
    Bytes.set prefix 0 first;
    read_exact prefix 1 3;
    let count = Int32.to_int (Bytes.get_int32_le prefix 0) land 0xffff_ffff in
    if count > max_words then failwith "native protocol: frame exceeds 16777216 words";
    let bytes = Bytes.create (count * 4) in
    read_exact bytes 0 (Bytes.length bytes);
    Some (Ox_native_io.Frame(bytes, Base.W32 count))
(* Validate the complete packet before publishing its prefix. Output is then
   streamed through a bounded scratch buffer instead of a response-sized copy.
   Packet lists are immutable; the buffer belongs solely to this call. *)
let write_packet write word_count header blocks =
  let count = u32_to_nat word_count in
  if count > max_words then failwith "native response exceeds 16M words";
  let total = count * 4 in
  let position = ref 0 in
  let advance size =
    if size < 0 || size > 4 || !position + size > total then
      failwith "native response length mismatch";
    position := !position + size
  in
  List.iter (fun _ -> advance 4) header;
  List.iter (fun (Ox_native_output.Block(length, words)) ->
    let remaining = ref length in
    List.iter (fun _ ->
      if !remaining <= 0 then failwith "native block has excess words";
      let size = min 4 !remaining in
      advance size;
      remaining := !remaining - size) words;
    if !remaining <> 0 then failwith "native block is truncated") blocks;
  let padding = total - !position in
  if padding > 3 then failwith "native response has excess padding";
  let buffer = Bytes.create (min 65536 (4 + total)) in
  let used = ref 0 in
  let flush () = if !used > 0 then (write buffer 0 !used; used := 0) in
  let byte value =
    if !used = Bytes.length buffer then flush ();
    Bytes.set buffer !used value;
    incr used
  in
  let word value size =
    if size = 4 then begin
      if !used + 4 > Bytes.length buffer then flush ();
      Bytes.set_int32_le buffer !used (Base.word_to_int32 value);
      used := !used + 4
    end else
      for offset = 0 to size - 1 do
        byte (Char.chr ((Base.u32_to_nat value lsr (offset * 8)) land 255))
      done
  in
  word word_count 4;
  List.iter (fun value -> word value 4) header;
  List.iter (fun (Ox_native_output.Block(length, words)) ->
    let remaining = ref length in
    List.iter (fun value ->
      let size = min 4 !remaining in
      word value size;
      remaining := !remaining - size) words) blocks;
  for _ = 1 to padding do byte '\000' done;
  flush ()
let f_send word_count header blocks () =
  write_packet (output stdout) word_count header blocks;
  flush stdout
