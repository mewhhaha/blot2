(* Native representations for the production compiler's Base operations.
   Strings contain Unicode scalar values, not UTF-8 bytes. F32 values retain
   their IEEE-754 bits, including signed zero. Maps retain Bend's Patricia
   layout because compiler/index.bend deliberately reads it directly. *)
type char32 = Chr of int32
type text = SNil | SCon of char32 * text
type cmp = LT | EQ | GT
type ('e, 'a) result_ = Fail of 'e | Done of 'a
type 'a map = MTip | MLeaf of text * 'a | MNode of int * 'a map * 'a map
type set = unit map
type 'a io = unit -> 'a

let cmp n = if n < 0 then LT else if n > 0 then GT else EQ
let unsigned x = Int64.logand (Int64.of_int32 x) 0xffff_ffffL
let u32_to_nat x = Int64.to_int (unsigned x)
let u32_from_nat = Int32.of_int
let u32_add = Int32.add
let u32_sub = Int32.sub
let u32_mul = Int32.mul
let u32_and = Int32.logand
let u32_or = Int32.logor
let u32_cmp a b = cmp (Int64.compare (unsigned a) (unsigned b))
let u32_is_eq = Int32.equal
let u32_is_ne a b = a <> b
let u32_is_lt a b = unsigned a < unsigned b
let u32_is_le a b = unsigned a <= unsigned b
let u32_is_gt a b = unsigned a > unsigned b
let u32_is_ge a b = unsigned a >= unsigned b
let u32_div a b = if b = 0l then 0l else Int64.to_int32 (Int64.div (unsigned a) (unsigned b))
let u32_mod a b = if b = 0l then a else Int64.to_int32 (Int64.rem (unsigned a) (unsigned b))
let u32_max a b = if u32_is_ge a b then a else b
let u32_shrn x n = if n >= 32 then 0l else Int32.shift_right_logical x n
let u32_shln x n = if n >= 32 then 0l else Int32.shift_left x n
let u32_shr x = Int32.shift_right_logical x 1

(* The reference native protocol uses 48-bit natural numbers. *)
let nat_mask = 0xffff_ffff_ffff
let nat_add a b = (a + b) land nat_mask
let nat_sub a b = if a < b then 0 else a - b
let nat_mul a b = (a * b) land nat_mask
let nat_div a b = if b = 0 then 0 else a / b
let nat_mod a b = if b = 0 then a else a mod b
let nat_cmp a b = cmp (Int.compare a b)
let nat_is_eq (a : int) b = a = b
let nat_is_ne (a : int) b = a <> b
let nat_is_lt (a : int) b = a < b
let nat_is_le (a : int) b = a <= b
let nat_is_gt (a : int) b = a > b
let nat_is_ge (a : int) b = a >= b
let nat_min = Int.min
let nat_max = Int.max
let bool_and a b = a && b
let bool_or a b = a || b
let bool_xor a b = a <> b
let bool_not = not
let bool_pick condition yes no = if condition then yes else no
let maybe_is_some = Option.is_some
let maybe_is_none = Option.is_none
let maybe_or a b = match a with Some _ -> a | None -> b
let char_is_eq (Chr a) (Chr b) = a = b
let char_to_u32 (Chr a) = a

let text_of_utf8 s =
  let n = String.length s in
  let get i = if i < n then Char.code s.[i] else invalid_arg "truncated UTF-8" in
  let continuation i =
    let c = get i in
    if c land 0xc0 <> 0x80 then invalid_arg "invalid UTF-8 continuation";
    c land 0x3f
  in
  let rec scan i acc =
    if i = n then List.fold_left (fun t c -> SCon (Chr (Int32.of_int c), t)) SNil acc
    else
      let a = get i in
      let code, size, minimum =
        if a < 0x80 then a, 1, 0
        else if a >= 0xc2 && a < 0xe0 then ((a land 31) lsl 6) lor continuation (i+1), 2, 0x80
        else if a >= 0xe0 && a < 0xf0 then ((a land 15) lsl 12) lor (continuation (i+1) lsl 6) lor continuation (i+2), 3, 0x800
        else if a >= 0xf0 && a < 0xf5 then ((a land 7) lsl 18) lor (continuation (i+1) lsl 12) lor (continuation (i+2) lsl 6) lor continuation (i+3), 4, 0x10000
        else invalid_arg "invalid UTF-8 leading byte"
      in
      if code < minimum || code > 0x10ffff || (code >= 0xd800 && code <= 0xdfff) then
        invalid_arg "invalid Unicode scalar";
      scan (i+size) (code::acc)
  in scan 0 []

let text_to_utf8 text =
  let buffer = Buffer.create 64 in
  let byte n = Buffer.add_char buffer (Char.chr n) in
  let rec loop = function
    | SNil -> Buffer.contents buffer
    | SCon (Chr c, tail) ->
      let c = u32_to_nat c in
      if c < 0x80 then byte c
      else if c < 0x800 then (byte (0xc0 lor (c lsr 6)); byte (0x80 lor (c land 63)))
      else if c < 0x10000 && (c < 0xd800 || c > 0xdfff) then
        (byte (0xe0 lor (c lsr 12)); byte (0x80 lor ((c lsr 6) land 63)); byte (0x80 lor (c land 63)))
      else if c >= 0x10000 && c <= 0x10ffff then
        (byte (0xf0 lor (c lsr 18)); byte (0x80 lor ((c lsr 12) land 63));
         byte (0x80 lor ((c lsr 6) land 63)); byte (0x80 lor (c land 63)))
      else invalid_arg "invalid Unicode scalar";
      loop tail
  in loop text

let string_reverse text =
  let rec loop acc = function SNil -> acc | SCon (c,t) -> loop (SCon(c,acc)) t in
  loop SNil text
let string_append left right =
  let rec loop acc = function SNil -> acc | SCon(c,t) -> loop (SCon(c,acc)) t in
  loop right (string_reverse left)
let string_length text =
  let rec loop n = function SNil -> n | SCon(_,t) -> loop (n+1) t in loop 0 text
let rec string_drop text n =
  if n = 0 then text else match text with SNil -> SNil | SCon(_,t) -> string_drop t (n-1)
let rec string_compare a b =
  if a == b then 0 else match a,b with
  | SNil,SNil -> 0 | SNil,_ -> -1 | _,SNil -> 1
  | SCon(Chr a,at),SCon(Chr b,bt) ->
    let order = Int64.compare (unsigned a) (unsigned b) in
    if order = 0 then string_compare at bt else order
let string_eq a b = string_compare a b = 0
let string_is_lt a b = string_compare a b < 0
let string_is_le a b = string_compare a b <= 0
let rec string_starts_with text prefix = match text,prefix with
  | _,SNil -> true | SNil,_ -> false
  | SCon(a,at),SCon(b,bt) -> char_is_eq a b && string_starts_with at bt
let string_split text delimiter =
  let rec loop text current parts = match text with
    | SNil -> List.rev (string_reverse current :: parts)
    | SCon(c,t) when char_is_eq c delimiter -> loop t SNil (string_reverse current :: parts)
    | SCon(c,t) -> loop t (SCon(c,current)) parts
  in loop text SNil []
let string_join parts delimiter =
  match parts with [] -> SNil | first::rest ->
    List.fold_left (fun acc part -> string_append (string_append acc delimiter) part) first rest
let nat_show n = text_of_utf8 (string_of_int n)
let u32_show n = text_of_utf8 (Int64.to_string (unsigned n))
let nat_read text =
  let rec loop n = function
    | SNil -> Some n
    | SCon(Chr c,t) when c >= 48l && c <= 57l ->
      let d = Int32.to_int c - 48 in
      if n > (nat_mask-d)/10 then None else loop (n*10+d) t
    | _ -> None
  in match text with SNil -> None | _ -> loop 0 text

let float = Int32.float_of_bits
let bits = Int32.bits_of_float
let f32_bits x = x
let f32_add a b = bits (float a +. float b)
let f32_sub a b = bits (float a -. float b)
let f32_mul a b = bits (float a *. float b)
let f32_div a b = bits (float a /. float b)
let f32_neg a = Int32.logxor a Int32.min_int
let f32_abs a = Int32.logand a Int32.max_int
let f32_sqrt a = bits (sqrt (float a))
let f32_floor a = bits (floor (float a))
let f32_ceil a = bits (ceil (float a))
let f32_trunc a = bits (Float.trunc (float a))
let f32_is_eq a b = float a = float b
let f32_is_ne a b = float a <> float b
let f32_is_lt a b = float a < float b
let f32_is_le a b = float a <= float b
let f32_is_gt a b = float a > float b
let f32_is_ge a b = float a >= float b
let f32_to_u32 a =
  let a = float a in
  if Float.is_nan a || a <= 0. then 0l
  else if a >= 4294967296. then Int32.minus_one
  else Int64.to_int32 (Int64.of_float a)
let u32_to_f32 a = bits (Int64.to_float (unsigned a))
let f32_read text = Option.map bits (float_of_string_opt (text_to_utf8 text))

let list_length = List.length
let list_is_empty = function [] -> true | _ -> false
let list_reverse = List.rev
let list_reverse_go = List.rev_append
let list_append xs ys = List.rev_append (List.rev xs) ys
let rec list_drop xs n = if n = 0 then xs else match xs with [] -> [] | _::t -> list_drop t (n-1)
let list_take xs n =
  let rec loop xs n acc = match xs with
    | _ when n = 0 -> List.rev acc
    | [] -> List.rev acc | h::t -> loop t (n-1) (h::acc)
  in loop xs n []
let list_replicate n x = List.init n (fun _ -> x)
let rec list_merge_go le fuel (acc,xs,ys) =
  if fuel = 0 then List.rev_append acc (list_append xs ys)
  else match xs,ys with
    | [],_ -> List.rev_append acc ys | _,[] -> List.rev_append acc xs
    | x::xt,y::yt -> if le x y then list_merge_go le (fuel-1) (x::acc,xt,ys)
                    else list_merge_go le (fuel-1) (y::acc,xs,yt)
let list_merge le xs ys = list_merge_go le (List.length xs + List.length ys) ([],xs,ys)
let list_sort le xs = List.stable_sort (fun a b -> if le a b then if le b a then 0 else -1 else 1) xs

let key_bit key pos =
  match string_drop key (pos / 33) with
  | SNil -> false
  | SCon(Chr c,_) -> let offset = pos mod 33 in
    offset = 0 || Int32.logand (Int32.shift_right_logical c (32-offset)) 1l <> 0l
let rec map_find m key = match m with
  | MTip -> None
  | MLeaf(k,v) -> if string_eq k key then Some v else None
  | MNode(pos,lo,hi) -> map_find (if key_bit key pos then hi else lo) key
let map_new () = MTip
let map_get default m key = m, Option.value (map_find m key) ~default
let map_set m key value =
  let leaf = MLeaf(key,value) in
  let rec seek = function
    | MTip -> None | MLeaf(k,_) -> Some k
    | MNode(p,lo,hi) -> seek (if key_bit key p then hi else lo)
  in
  let rec replace = function
    | MTip | MLeaf _ -> leaf
    | MNode(p,lo,hi) -> if key_bit key p then MNode(p,lo,replace hi) else MNode(p,replace lo,hi)
  in
  match seek m with
  | None -> leaf
  | Some old when string_eq old key -> replace m
  | Some old ->
    let rec differing pos = if key_bit key pos <> key_bit old pos then pos else differing (pos+1) in
    let pos = differing 0 in
    let splice node = if key_bit key pos then MNode(pos,node,leaf) else MNode(pos,leaf,node) in
    let rec insert = function
      | MNode(p,lo,hi) when p < pos ->
        if key_bit key p then MNode(p,lo,insert hi) else MNode(p,insert lo,hi)
      | node -> splice node
    in insert m
let map_bindings m =
  let rec loop work acc = match work with
    | [] -> List.rev acc
    | MTip::rest -> loop rest acc
    | MLeaf(k,v)::rest -> loop rest ((k,v)::acc)
    | MNode(_,lo,hi)::rest -> loop (lo::hi::rest) acc
  in loop [m] []
let map_values m = List.map snd (map_bindings m)
let map_union left right = List.fold_left (fun acc (k,v) -> map_set acc k v) left (map_bindings right)
let set_new () = MTip
let set_add set key = map_set set key ()
let set_from_list keys = List.fold_left set_add MTip keys
let set_to_list set = List.map fst (map_bindings set)
let set_size set = List.length (map_bindings set)

(* Arrays here belong solely to the linear request decoder. No compiler value
   or published incremental cache contains one of these mutable buffers. *)
let array_new depth value =
  if depth < 0 || depth > 24 then invalid_arg "array depth exceeds protocol limit";
  Array.make (1 lsl depth) value
let array_get array index = array, array.(u32_to_nat index land (Array.length array - 1))
let array_set array index value = array.(u32_to_nat index land (Array.length array - 1)) <- value; array

let io_pure value () = value
let io_bind computation continuation () = continuation (computation ()) ()
let io_die code message () = prerr_endline (text_to_utf8 message); exit (u32_to_nat code)
let io_print message () = print_string (text_to_utf8 message); flush stdout
let io_args () () = Array.to_list Sys.argv |> List.map text_of_utf8
let io_now () () = int_of_float (Sys.time () *. 1000000000.)
