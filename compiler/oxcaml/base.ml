(* Native representations for the production compiler's Base operations.
   Strings contain Unicode scalar values, not UTF-8 bytes. F32 values retain
   their IEEE-754 bits, including signed zero. Maps retain Bend's Patricia
   layout because compiler/index.bend deliberately reads it directly. *)
(* Internal words remain distinct from Nat48 but occupy one immediate value.
   Every constructor below and every translated literal preserves [0,2^32-1].
   This backend requires a 64-bit process, as its Nat48 representation already did. *)
type word32 = W32 of int [@@unboxed]
type char32 = Chr of word32 [@@unboxed]
let () = if Sys.int_size <> 63 then failwith "Blot requires 63-bit native ints"
let[@zero_alloc strict] word_of_int value = W32 (value land 0xffff_ffff)
let word_of_int32 value = W32 (Int32.to_int value land 0xffff_ffff)
let word_to_int32 (W32 value) = Int32.of_int value
type text = SNil | SCon of char32 * text
type cmp = LT | EQ | GT
type ('e, 'a) result_ = Fail of 'e | Done of 'a
type 'a map = MTip | MLeaf of text * 'a | MNode of int * 'a map * 'a map
type set = unit map
type 'a io = unit -> 'a

let cmp n = if n < 0 then LT else if n > 0 then GT else EQ
let unsigned (W32 x) = Int64.of_int x
let[@zero_alloc strict] u32_to_nat (W32 x) = x
let[@zero_alloc strict] u32_from_nat x = word_of_int x
let[@zero_alloc strict] u32_add (W32 a) (W32 b) = word_of_int (a + b)
let[@zero_alloc strict] u32_sub (W32 a) (W32 b) = word_of_int (a - b)
let[@zero_alloc strict] u32_mul (W32 a) (W32 b) = word_of_int (a * b)
let[@zero_alloc strict] u32_and (W32 a) (W32 b) = W32 (a land b)
let[@zero_alloc strict] u32_or (W32 a) (W32 b) = W32 (a lor b)
let[@zero_alloc strict] u32_cmp (W32 a) (W32 b) = cmp (Int.compare a b)
let[@zero_alloc strict] u32_is_eq (W32 a) (W32 b) = a = b
let u32_is_ne (W32 a) (W32 b) = a <> b
let[@zero_alloc strict] u32_is_lt (W32 a) (W32 b) = a < b
let[@zero_alloc strict] u32_is_le (W32 a) (W32 b) = a <= b
let[@zero_alloc strict] u32_is_gt (W32 a) (W32 b) = a > b
let[@zero_alloc strict] u32_is_ge (W32 a) (W32 b) = a >= b
let[@zero_alloc strict] u32_div (W32 a) (W32 b) = W32 (if b = 0 then 0 else a / b)
let[@zero_alloc strict] u32_mod (W32 a) (W32 b) = W32 (if b = 0 then a else a mod b)
let u32_max a b = if u32_is_ge a b then a else b
let[@zero_alloc strict] u32_shrn (W32 x) n = if n >= 32 then W32 0 else W32 (x lsr n)
let[@zero_alloc strict] u32_shln (W32 x) n = if n >= 32 then W32 0 else word_of_int (x lsl n)
let[@zero_alloc strict] u32_shr (W32 x) = W32 (x lsr 1)

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
    if i = n then List.fold_left (fun t c -> SCon (Chr (W32 c), t)) SNil acc
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
(* TMC constructs only the output spine. OCaml 4.13 ignores this attribute,
   so keep its explicitly stack-safe reverse/append portability path. *)
let supports_tmc =
  let major, minor = Scanf.sscanf Sys.ocaml_version "%d.%d" (fun a b -> a,b) in
  major > 4 || (major = 4 && minor >= 14)
let[@tail_mod_cons] rec string_append_tmc left right =
  match left with SNil -> right | SCon(c,t) -> SCon(c,string_append_tmc t right)
let string_append_portable left right =
  let rec loop acc = function SNil -> acc | SCon(c,t) -> loop (SCon(c,acc)) t in
  loop right (string_reverse left)
let string_append = if supports_tmc then string_append_tmc else string_append_portable

let string_length text =
  let rec loop n = function SNil -> n | SCon(_,t) -> loop (n+1) t in loop 0 text
let rec string_drop text n =
  if n = 0 then text else match text with SNil -> SNil | SCon(_,t) -> string_drop t (n-1)
let rec string_compare a b =
  if a == b then 0 else match a,b with
  | SNil,SNil -> 0 | SNil,_ -> -1 | _,SNil -> 1
  | SCon(Chr a,at),SCon(Chr b,bt) ->
    let order = Int.compare (u32_to_nat a) (u32_to_nat b) in
    if order = 0 then string_compare at bt else order
(* Equality needs neither unsigned ordering nor an ownership-carrying result.
   Shared immutable tails can stop immediately. The strict OxCaml check keeps
   this hot operation non-allocating; stock OCaml ignores the check attribute. *)
let[@zero_alloc strict] rec string_eq left right =
  left == right || match left, right with
  | SCon (Chr a, at), SCon (Chr b, bt) ->
    u32_is_eq a b && string_eq at bt
  | _ -> false
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
  (* Copy every nonfinal part once, rather than repeatedly copying the growing
     prefix. Keep raw scalar text, including non-Unicode values used internally. *)
  match List.rev parts with
  | [] -> SNil
  | last :: rest -> List.fold_left
      (fun acc part -> string_append part (string_append delimiter acc)) last rest

let nat_show n = text_of_utf8 (string_of_int n)
let u32_show n = text_of_utf8 (Int64.to_string (unsigned n))
let nat_read text =
  let rec loop n = function
    | SNil -> Some n
    | SCon(Chr c,t) when u32_to_nat c >= 48 && u32_to_nat c <= 57 ->
      let d = u32_to_nat c - 48 in
      if n > (nat_mask-d)/10 then None else loop (n*10+d) t
    | _ -> None
  in match text with SNil -> None | _ -> loop 0 text

let float word = Int32.float_of_bits (word_to_int32 word)
let bits value = word_of_int32 (Int32.bits_of_float value)
let f32_bits x = x
let f32_add a b = bits (float a +. float b)
let f32_sub a b = bits (float a -. float b)
let f32_mul a b = bits (float a *. float b)
let f32_div a b = bits (float a /. float b)
let[@zero_alloc strict] f32_neg (W32 a) = W32 (a lxor 0x8000_0000)
let[@zero_alloc strict] f32_abs (W32 a) = W32 (a land 0x7fff_ffff)
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
  if Float.is_nan a || a <= 0. then W32 0
  else if a >= 4294967296. then W32 0xffff_ffff
  else W32 (int_of_float a)
let u32_to_f32 (W32 a) = bits (float_of_int a)
let f32_read text = Option.map bits (float_of_string_opt (text_to_utf8 text))

let list_length = List.length
let list_is_empty = function [] -> true | _ -> false
let list_reverse = List.rev
let list_reverse_go = List.rev_append
let[@tail_mod_cons] rec list_append_tmc xs ys =
  match xs with [] -> ys | x::rest -> x :: list_append_tmc rest ys
let list_append_portable xs ys = List.rev_append (List.rev xs) ys
let list_append = if supports_tmc then list_append_tmc else list_append_portable
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
    offset = 0 || (u32_to_nat c lsr (32-offset)) land 1 <> 0
let rec map_find m key = match m with
  | MTip -> None
  | MLeaf(k,v) -> if string_eq k key then Some v else None
  | MNode(pos,lo,hi) -> map_find (if key_bit key pos then hi else lo) key
let map_new () = MTip
let rec map_find_or default map key = match map with
  | MTip -> default
  | MLeaf(k,value) -> if string_eq k key then value else default
  | MNode(pos,left,right) -> map_find_or default (if key_bit key pos then right else left) key
let map_get default m key = m, map_find_or default m key
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
    (* Scan the common prefix once. Repeated key_bit probes start from the
       head of a code-point list and made long identifiers quadratic. *)
    let rec differing offset left right = match left, right with
      | SNil, SCon _ | SCon _, SNil -> offset
      | SCon (Chr a, at), SCon (Chr b, bt) ->
        if a = b then differing (offset + 33) at bt
        else
          let xor = u32_to_nat a lxor u32_to_nat b in
          let rec leading bit =
            if xor land (1 lsl (31-bit)) <> 0
            then bit else leading (bit+1)
          in offset + 1 + leading 0
      | SNil, SNil -> assert false (* Equal keys were handled above. *)
    in
    let pos = differing 0 key old in
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
(* Ordered traversal without materializing (key,value) tuples and two extra
   lists. Persistent inputs stay immutable and right-biased union is unchanged. *)
let map_fold f initial tree =
  let rec visit tree pending acc = match tree with
    | MTip -> next pending acc
    | MLeaf(key,value) -> next pending (f acc key value)
    | MNode(_,left,right) -> visit left (right::pending) acc
  and next pending acc = match pending with
    | [] -> acc | tree::rest -> visit tree rest acc
  in visit tree [] initial
let map_values m = List.rev (map_fold (fun values _ value -> value::values) [] m)
let map_union left right = map_fold (fun acc key value -> map_set acc key value) left right
let set_new () = MTip
let set_add set key = map_set set key ()
let set_from_list keys = List.fold_left set_add MTip keys
let set_to_list set = List.rev (map_fold (fun keys key _ -> key::keys) [] set)
let set_size set = map_fold (fun count _ _ -> count+1) 0 set

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
