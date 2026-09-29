(* A five-bit radix directory replaces binary Patricia paths in the hot native
   substitution/scope indexes. Updating copies only the path; prior versions
   remain valid for failed inference, speculative branches, and other workers. *)
type 'a t = Empty | Leaf of int * 'a | Branch of int * 'a t array
let empty = Empty
let check key = if key < 0 then invalid_arg "Core_index: negative key"
let slot key depth = (key lsr (depth * 5)) land 31
let popcount value =
  let value = value - ((value lsr 1) land 0x55555555) in
  let value = (value land 0x33333333) + ((value lsr 2) land 0x33333333) in
  let value = (value + (value lsr 4)) land 0x0f0f0f0f in
  ((value * 0x01010101) lsr 24) land 255
let position bitmap bit = popcount (bitmap land (bit - 1))
let find key tree =
  check key;
  let rec walk depth = function
   | Empty -> None
   | Leaf (found,value) -> if key=found then Some value else None
   | Branch (bitmap,children) ->
     let bit = 1 lsl slot key depth in
     if bitmap land bit = 0 then None else walk (depth+1) children.(position bitmap bit)
  in walk 0 tree
let add key value tree =
  check key;
  let leaf = Leaf (key,value) in
  let rec split depth old old_key =
    if depth > 12 then failwith "Core_index: distinct key exhausted its bits";
    let a=slot old_key depth and b=slot key depth in
    if a=b then Branch (1 lsl a,[|split (depth+1) old old_key|])
    else Branch ((1 lsl a) lor (1 lsl b),if a<b then [|old;leaf|] else [|leaf;old|])
  in
  let rec insert depth = function
   | Empty -> leaf
   | Leaf (found,_) as old -> if key=found then leaf else split depth old found
   | Branch (bitmap,children) ->
     let bit=1 lsl slot key depth in
     let index=position bitmap bit in
     if bitmap land bit <> 0 then begin
       let copy=Array.copy children in
       copy.(index) <- insert (depth+1) copy.(index);
       Branch (bitmap,copy)
     end else begin
       let copy=Array.make (Array.length children+1) leaf in
       Array.blit children 0 copy 0 index;
       Array.blit children index copy (index+1) (Array.length children-index);
       Branch (bitmap lor bit,copy)
     end
  in insert 0 tree
let bindings tree =
 let rec visit pending out = match pending with
  | [] -> List.sort (fun (a,_) (b,_) -> Int.compare a b) out
  | Empty :: rest -> visit rest out
  | Leaf (key,value) :: rest -> visit rest ((key,value)::out)
  | Branch (_,children) :: rest -> visit (Array.fold_right (fun child tail -> child::tail) children rest) out
 in visit [tree] []
