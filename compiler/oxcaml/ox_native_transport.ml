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
    let count = u32_to_nat (Bytes.get_int32_le prefix 0) in
    if count > max_words then failwith "native protocol: frame exceeds 16777216 words";
    let bytes = Bytes.create (count * 4) in
    read_exact bytes 0 (Bytes.length bytes);
    (* Decode on demand from the compact frame; do not allocate a rounded-up
       pointer array and one boxed Int32 per input word. *)
    Some (Ox_native_io.Frame(bytes, Int32.of_int count))
(* Validate the complete scatter/gather plan before publishing its prefix.
   Invalid plans must not leave a partial frame on the protocol stream. *)
let validate_response word_count header blocks =
  let count = u32_to_nat word_count in
  if count > max_words then failwith "native response exceeds 16M words";
  let total = count * 4 in
  let written = ref 0 in
  let reserve size =
    if size < 0 || size > 4 || !written + size > total then
      failwith "native response length mismatch";
    written := !written + size
  in
  List.iter (fun _ -> reserve 4) header;
  List.iter (fun (Ox_native_output.Block (length, words)) ->
    let remaining = ref length in
    List.iter (fun _ ->
      if !remaining <= 0 then failwith "native block has excess words";
      let size = min 4 !remaining in
      reserve size;
      remaining := !remaining - size
    ) words;
    if !remaining <> 0 then failwith "native block is truncated"
  ) blocks;
  let padding = total - !written in
  if padding > 3 then failwith "native response has excess padding";
  padding

let write_response channel word_count header blocks =
  let padding = validate_response word_count header blocks in
  (* The buffer is private to one response. Never retain a peak-sized response
     buffer across requests, and never expose partially initialized storage. *)
  let buffer = Bytes.create (min 65536 (4 + 4 * u32_to_nat word_count)) in
  let position = ref 0 in
  let flush_buffer () =
    output channel buffer 0 !position;
    position := 0
  in
  let add_word word size =
    if !position + size > Bytes.length buffer then flush_buffer ();
    if size = 4 then Bytes.set_int32_le buffer !position word
    else
      for i = 0 to size - 1 do
        Bytes.set buffer (!position+i)
          (Char.chr (Int32.to_int (Int32.logand (Int32.shift_right_logical word (i*8)) 255l)))
      done;
    position := !position + size
  in
  add_word word_count 4;
  List.iter (fun word -> add_word word 4) header;
  List.iter (fun (Ox_native_output.Block (length, words)) ->
    let remaining = ref length in
    List.iter (fun word ->
      let size = min 4 !remaining in
      add_word word size;
      remaining := !remaining - size
    ) words
  ) blocks;
  add_word 0l padding;
  flush_buffer ();
  flush channel

let f_send word_count header blocks () =
  write_response stdout word_count header blocks
