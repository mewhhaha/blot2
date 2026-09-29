(* Each worker retains content-canonical symbol witnesses weakly. Persistent
   scope indexes own their witnesses, so a live index cannot lose its IDs when
   request caches are cleared. Symbols are never serialized. *)
type t = { id : int; text : Base.text }
module W = Weak.Make(struct
  type nonrec t = t
  let equal a b = Base.string_eq a.text b.text
  let hash value = Base.text_hash value.text
end)
let tables = Domain.DLS.new_key (fun () -> W.create 256)
let intern text =
  let table = Domain.DLS.get tables in
  let key = { id = 0; text } in
  match W.find_opt table key with
  | Some previous -> previous
  | None ->
    let symbol = { id = Core_nodes.fresh_id (); text } in
    W.add table symbol;
    symbol
