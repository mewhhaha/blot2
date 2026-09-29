(* Native representations for the production compiler's Base operations.
   Strings contain Unicode scalar values, not UTF-8 bytes. F32 values retain
   their IEEE-754 bits, including signed zero. Maps retain Bend's Patricia
   layout because compiler/index.bend deliberately reads it directly. *)
(* Nat48 already requires a 64-bit runtime. Characters likewise fit in one
   immediate machine word, including raw U32 bit patterns below validation. *)
type char32 = Core_text.char32 = Chr of int [@@unboxed]
type text = Core_text.t
type text_node = Core_text.node = SNil | SCon of char32 * text
let text_nil = Core_text.empty
let text_cons = Core_text.cons
let make_Text = Core_text.make
let text_node = Core_text.view
let text_of_words = Core_text.of_words
type cmp = LT | EQ | GT
type ('e, 'a) result_ = Fail of 'e | Done of 'a
type 'a map = MTip | MLeaf of text * 'a | MNode of int * 'a map * 'a map
type set = unit map
type 'a io = unit -> 'a

let cmp n = if n < 0 then LT else if n > 0 then GT else EQ
let unsigned x = Int64.logand (Int64.of_int32 x) 0xffff_ffffL
let[@zero_alloc strict] u32_to_nat x = Int32.to_int x land 0xffff_ffff
let u32_from_nat = Int32.of_int
let u32_add = Int32.add
let u32_sub = Int32.sub
let u32_mul = Int32.mul
let u32_and = Int32.logand
let u32_or = Int32.logor
let[@zero_alloc strict] u32_cmp a b = cmp (Int.compare (u32_to_nat a) (u32_to_nat b))
let u32_is_eq = Int32.equal
let u32_is_ne a b = a <> b
let[@zero_alloc strict] u32_is_lt a b = u32_to_nat a < u32_to_nat b
let[@zero_alloc strict] u32_is_le a b = u32_to_nat a <= u32_to_nat b
let[@zero_alloc strict] u32_is_gt a b = u32_to_nat a > u32_to_nat b
let[@zero_alloc strict] u32_is_ge a b = u32_to_nat a >= u32_to_nat b
let u32_div a b = if b = 0l then 0l else Int32.of_int (u32_to_nat a / u32_to_nat b)
let u32_mod a b = if b = 0l then a else Int32.of_int (u32_to_nat a mod u32_to_nat b)
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
let char_to_u32 (Chr a) = Int32.of_int a
let[@zero_alloc strict] char_of_u32 a = Chr (u32_to_nat a)

let text_of_utf8 = Core_text.of_utf8
let text_to_utf8 = Core_text.to_utf8
let string_reverse = Core_text.reverse
let use_tail_mod_cons = true
let string_append = Core_text.append
let string_append_tmc = string_append
let string_length = Core_text.length
let string_drop = Core_text.drop
let string_compare = Core_text.compare
let string_eq = Core_text.equal
let string_is_lt a b = string_compare a b < 0
let string_is_le a b = string_compare a b <= 0
let string_starts_with = Core_text.starts_with
let string_split = Core_text.split
let string_join = Core_text.join
let nat_show n = text_of_utf8 (string_of_int n)
let u32_show n = text_of_utf8 (string_of_int (u32_to_nat n))
let nat_read text =
  let rec loop n value = match (text_node value) with
    | SNil -> Some n
    | SCon(Chr c,t) when c >= 48 && c <= 57 ->
      let d = c - 48 in
      if n > (nat_mask-d)/10 then None else loop (n*10+d) t
    | _ -> None
  in if (Core_text.length text) = 0 then None else loop 0 text

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
let u32_to_f32 a = bits (float_of_int (u32_to_nat a))
let f32_read text = Option.map bits (float_of_string_opt (text_to_utf8 text))

let list_length = List.length
let list_is_empty = function [] -> true | _ -> false
let list_reverse = List.rev
let list_reverse_go = List.rev_append
let list_append xs ys =
  if use_tail_mod_cons then List.append xs ys
  else List.rev_append (List.rev xs) ys
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
  if pos / 33 >= Core_text.length key then false
  else let c = Core_text.at key (pos / 33) in
    let offset = pos mod 33 in
    offset = 0 || (c lsr (32-offset)) land 1 <> 0
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
    (* Scan the common prefix once. Repeated key_bit probes start from the
       head of a code-point list and made long identifiers quadratic. *)
    let rec differing offset left right = match (text_node left), (text_node right) with
      | SNil, SCon _ | SCon _, SNil -> offset
      | SCon (Chr a, at), SCon (Chr b, bt) ->
        if a = b then differing (offset + 33) at bt
        else
          let xor = a lxor b in
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
let map_values m =
  let rec loop work acc = match work with
    | [] -> List.rev acc
    | MTip :: rest -> loop rest acc
    | MLeaf (_, value) :: rest -> loop rest (value :: acc)
    | MNode (_, lo, hi) :: rest -> loop (lo :: hi :: rest) acc
  in loop [m] []
let map_union left right =
  (* Same low-before-high traversal and right bias, without temporary pairs. *)
  let rec loop work acc = match work with
    | [] -> acc
    | MTip :: rest -> loop rest acc
    | MLeaf (key, value) :: rest -> loop rest (map_set acc key value)
    | MNode (_, lo, hi) :: rest -> loop (lo :: hi :: rest) acc
  in loop [right] left
let set_new () = MTip
let set_add set key = map_set set key ()
let set_from_list keys = List.fold_left set_add MTip keys
let set_to_list set =
  let rec loop work acc = match work with
    | [] -> List.rev acc
    | MTip :: rest -> loop rest acc
    | MLeaf (key, _) :: rest -> loop rest (key :: acc)
    | MNode (_, lo, hi) :: rest -> loop (lo :: hi :: rest) acc
  in loop [set] []
let set_size set =
  let rec loop work count = match work with
    | [] -> count
    | MTip :: rest -> loop rest count
    | MLeaf _ :: rest -> loop rest (count + 1)
    | MNode (_, lo, hi) :: rest -> loop (lo :: hi :: rest) count
  in loop [set] 0

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

(* Position of the first different character bit, including the presence bit. *)
let map_diff_chr x =
  let x = u32_to_nat x in
  let rec scan bit = if bit < 0 then 33 else
    if x land (1 lsl bit) <> 0 then 32 - bit else scan (bit - 1) in
  scan 31

let u32_xor = Int32.logxor

let maybe_map f value = Option.map f value

let text_hash = Core_text.hash

let word_buffer_get buffer index = buffer, Bytes.get_int32_le buffer (4 * u32_to_nat index)
