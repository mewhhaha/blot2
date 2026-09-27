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
    if count > max_words then failwith "native frame exceeds 16M words";
    let bytes = Bytes.create (count * 4) in
    read_exact bytes 0 (Bytes.length bytes);
    let rec capacity n = if n >= count then n else capacity (n*2) in
    let words = Array.make (capacity 1) 0l in
    for i = 0 to count - 1 do words.(i) <- Bytes.get_int32_le bytes (i*4) done;
    Some (Ox_native_io.Frame(words, Int32.of_int count))
let f_send word_count header blocks () =
  let count = u32_to_nat word_count in
  if count > max_words then failwith "native response exceeds 16M words";
  let total = count * 4 in
  let output = Bytes.make (4 + total) '\000' in
  Bytes.set_int32_le output 0 word_count;
  let position = ref 4 in
  let add_word word size =
    if size < 0 || size > 4 || !position + size > Bytes.length output then
      failwith "native response length mismatch";
    for i = 0 to size - 1 do
      Bytes.set output (!position+i) (Char.chr (Int32.to_int (Int32.logand (Int32.shift_right_logical word (i*8)) 255l)))
    done;
    position := !position + size
  in
  List.iter (fun w -> add_word w 4) header;
  List.iter (fun (Ox_native_output.Block(length,words)) ->
    let remaining = ref length in
    List.iter (fun w ->
      if !remaining <= 0 then failwith "native block has excess words";
      let size = min 4 !remaining in add_word w size; remaining := !remaining - size
    ) words;
    if !remaining <> 0 then failwith "native block is truncated"
  ) blocks;
  if Bytes.length output - !position > 3 then failwith "native response has excess padding";
  output_bytes stdout output;
  flush stdout
