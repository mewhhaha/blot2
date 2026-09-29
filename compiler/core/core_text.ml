(* Immutable Unicode-word spans. Most compiler names occupy one packed block;
   cons is retained only as a cheap builder for source-level structural code.
   No span aliases mutable request bytes, and suffix hashes are computed without
   rescanning the suffix. Hash equality is never used as string equality. *)
type char32 = Chr of int [@@unboxed]
type t = { storage : storage; length : int; text_hash : int }
and storage = Empty | Link of char32 * t | Span of string * int
type node = SNil | SCon of char32 * t
let () = if Sys.word_size <> 64 then failwith "Blot core requires a 64-bit OCaml runtime"
let mix a b = ((a * 65599) lxor b) land max_int
let unmix hash code = ((hash lxor code) * 2243942834832601023) land max_int
let empty = { storage = Empty; length = 0; text_hash = 17 }
let word data offset = Int32.to_int (String.get_int32_le data offset) land 0xffffffff
let hash value = value.text_hash
let length value = value.length
let span data offset count hash =
  if count = 0 then empty else { storage = Span (data,offset); length = count; text_hash = hash }
let hash_range data offset count =
  let hash = ref 17 in
  for i=count-1 downto 0 do hash := mix !hash (word data (offset+4*i)) done;
  !hash
let owned data =
  let length=String.length data / 4 in
  if String.length data mod 4 <> 0 then invalid_arg "unaligned Unicode words";
  span data 0 length (hash_range data 0 length)
let of_words bytes offset count =
  if offset < 0 || count < 0 || offset > Bytes.length bytes / 4 ||
     count > Bytes.length bytes / 4 - offset then invalid_arg "Unicode word range";
  owned (Bytes.sub_string bytes (4*offset) (4*count))
let cons ((Chr code as head),tail) =
  if code < 0 || code > 0xffffffff then invalid_arg "character word exceeds U32";
  {storage=Link(head,tail); length=tail.length+1; text_hash=mix tail.text_hash code}
let make = function SNil -> empty | SCon(head,tail) -> cons(head,tail)
let view value = match value.storage with
 | Empty -> SNil
 | Link(head,tail) -> SCon(head,tail)
 | Span(data,offset) ->
   let code=word data offset in
   SCon(Chr code,span data (offset+4) (value.length-1) (unmix value.text_hash code))
let rec drop value count =
 if count <= 0 then value else if count >= value.length then empty else
 match value.storage with
 | Empty -> empty
 | Link(_,tail) -> drop tail (count-1)
 | Span(data,offset) ->
   let hash=ref value.text_hash in
   for i=0 to count-1 do hash:=unmix !hash (word data (offset+4*i)) done;
   span data (offset+4*count) (value.length-count) !hash
let rec at value index =
 if index < 0 || index >= value.length then invalid_arg "Unicode character index";
 match value.storage with
 | Empty -> assert false
 | Link(Chr code,tail) -> if index=0 then code else at tail (index-1)
 | Span(data,offset) -> word data (offset+4*index)
let iter f value =
 let rec go value = match value.storage with
 | Empty -> ()
 | Link(Chr code,tail) -> f code; go tail
 | Span(data,offset) -> for i=0 to value.length-1 do f (word data (offset+4*i)) done
 in go value
let bytes_for count =
 if count < 0 || count > Sys.max_string_length / 4 then invalid_arg "compiler string too large";
 Bytes.create (count * 4)
let copy_into bytes offset value =
 let rec go offset value = match value.storage with
 | Empty -> offset
 | Link(Chr code,tail) -> Bytes.set_int32_le bytes offset (Int32.of_int code); go (offset+4) tail
 | Span(data,start) -> Bytes.blit_string data start bytes offset (4*value.length); offset+4*value.length
 in go offset value
let append left right =
 if left.length=0 then right else if right.length=0 then left else
 let count=left.length+right.length in
 let bytes=bytes_for count in
 let pos=copy_into bytes 0 left in
 ignore(copy_into bytes pos right);
 owned (Bytes.unsafe_to_string bytes)
let reverse value =
 let bytes=bytes_for value.length and index=ref value.length in
 iter (fun code -> decr index; Bytes.set_int32_le bytes (4 * !index) (Int32.of_int code)) value;
 owned (Bytes.unsafe_to_string bytes)
let rec compare left right =
 if left == right then 0 else
 match left.storage,right.storage with
 | Empty,Empty -> 0 | Empty,_ -> -1 | _,Empty -> 1
 | Span(a,ao),Span(b,bo) ->
   let limit=min left.length right.length in
   let rec scan i =
    if i=limit then Int.compare left.length right.length
    else let order=Int.compare (word a (ao+4*i)) (word b (bo+4*i)) in
    if order=0 then scan (i+1) else order
   in scan 0
 | _ ->
   let order=Int.compare (at left 0) (at right 0) in
   if order=0 then compare (drop left 1) (drop right 1) else order
let equal left right =
 left == right || (left.length=right.length && left.text_hash=right.text_hash &&
 match left.storage,right.storage with
 | Span(a,0),Span(b,0) when String.length a=4*left.length && String.length b=4*right.length -> String.equal a b
 | _ -> compare left right=0)
let starts_with text prefix =
 let rec go a b = match view b with
 | SNil -> true
 | SCon(Chr code,tail) -> a.length>0 && at a 0=code && go (drop a 1) tail
 in prefix.length <= text.length && go text prefix
let flatten value = match value.storage with
 | Span(data,0) when String.length data=4*value.length -> data
 | _ -> let bytes=bytes_for value.length in ignore(copy_into bytes 0 value); Bytes.unsafe_to_string bytes
let split value (Chr delimiter) =
 let data=flatten value in
 let part first last = span data (first*4) (last-first) (hash_range data (first*4) (last-first)) in
 let rec go first next parts =
  if next=value.length then List.rev (part first next :: parts)
  else if word data (4*next)=delimiter then go (next+1) (next+1) (part first next :: parts)
  else go first (next+1) parts
 in go 0 0 []
let join parts delimiter =
 let size=List.fold_left (fun acc value ->
   if acc > Sys.max_string_length/4-value.length then invalid_arg "compiler string too large";
   acc+value.length) 0 parts in
 let separators=max 0 (List.length parts-1) in
 if separators>0 && delimiter.length > (Sys.max_string_length/4-size)/separators then invalid_arg "compiler string too large";
 let bytes=bytes_for (size+separators*delimiter.length) in
 let rec go offset = function
 | [] -> () | [last] -> ignore(copy_into bytes offset last)
 | head :: tail -> go (copy_into bytes (copy_into bytes offset head) delimiter) tail
 in go 0 parts; owned (Bytes.unsafe_to_string bytes)
let of_utf8 s =
 let n=String.length s in
 let buffer=Buffer.create n in
 let get i = if i<n then Char.code s.[i] else invalid_arg "truncated UTF-8" in
 let continuation i = let c=get i in
  if c land 0xc0 <> 0x80 then invalid_arg "invalid UTF-8 continuation";
  c land 63
 in
 let rec scan i = if i<n then begin
  let a=get i in
  let code,size,minimum =
   if a<0x80 then a,1,0
   else if a>=0xc2 && a<0xe0 then ((a land 31) lsl 6) lor continuation(i+1),2,0x80
   else if a>=0xe0 && a<0xf0 then ((a land 15) lsl 12) lor (continuation(i+1) lsl 6) lor continuation(i+2),3,0x800
   else if a>=0xf0 && a<0xf5 then ((a land 7) lsl 18) lor (continuation(i+1) lsl 12) lor (continuation(i+2) lsl 6) lor continuation(i+3),4,0x10000
   else invalid_arg "invalid UTF-8 leading byte"
  in
  if code<minimum || code>0x10ffff || (code>=0xd800 && code<=0xdfff) then invalid_arg "invalid Unicode scalar";
  for j=0 to 3 do Buffer.add_char buffer (Char.chr ((code lsr (8*j)) land 255)) done;
  scan(i+size)
 end in scan 0; owned(Buffer.contents buffer)
let to_utf8 text =
 let buffer=Buffer.create text.length in
 let byte n=Buffer.add_char buffer (Char.chr n) in
 iter (fun c ->
  if c<0x80 then byte c
  else if c<0x800 then (byte(0xc0 lor(c lsr 6)); byte(0x80 lor(c land 63)))
  else if c<0x10000 && (c<0xd800 || c>0xdfff) then
   (byte(0xe0 lor(c lsr 12)); byte(0x80 lor((c lsr 6) land 63)); byte(0x80 lor(c land 63)))
  else if c>=0x10000 && c<=0x10ffff then
   (byte(0xf0 lor(c lsr 18)); byte(0x80 lor((c lsr 12) land 63)); byte(0x80 lor((c lsr 6) land 63)); byte(0x80 lor(c land 63)))
  else invalid_arg "invalid Unicode scalar") text;
 Buffer.contents buffer
