(* A persistent integer-keyed scope index. Cache keys are exact list identities,
   not hashes of their first element. Each index owns its symbol witnesses. *)
module Make (Binding : sig
 type t
 val id : t -> int
 val name : t -> Base.text
end) = struct
 module Keys = Core_index
 module Cache = Ephemeron.K1.Make(struct
  type t = Binding.t list
  let equal a b = a == b
  let hash = function [] -> 0 | h :: _ -> Binding.id h
 end)
 let caches = Domain.DLS.new_key (fun () -> Cache.create 256)
 let index bindings =
  let cache = Domain.DLS.get caches in
  let rec missing pending suffix = match Cache.find_opt cache suffix with
   | Some known -> pending, known
   | None -> match suffix with
     | [] -> pending, Keys.empty
     | head :: tail -> missing ((suffix,head) :: pending) tail
  in
  let pending, initial = missing [] bindings in
  List.fold_left (fun indexed (key, head) ->
    let symbol = Core_symbols.intern (Binding.name head) in
    let next = Keys.add symbol.id (symbol,head) indexed in
    if Cache.length cache >= 16384 then Cache.clear cache;
    Cache.replace cache key next;
    next) initial pending
 let lookup bindings name =
  let rec short count remaining = match remaining with
   | [] -> None
   | head :: tail when count > 0 ->
     if Base.string_eq (Binding.name head) name then Some head else short (count-1) tail
   | _ ->
     Core_nodes.note "scope.indexed_lookups";
     let indexed=index bindings in
     let key=Core_symbols.intern name in
     Option.map snd (Keys.find key.id indexed)
  in short 8 bindings
end

(* A persistent filter for lexical environments. A summary is built once for a
   new prefix; an unchanged suffix reuses its summary. Only bindings proven to
   contribute no free variables are removed. Order and shadowed bindings remain
   intact, since generalization examines the whole environment, not lookup. *)
module Filter (Binding : sig
 type t
 val id : t -> int
 val keep : t -> bool
end) = struct
 module H=Ephemeron.K1.Make(struct
  type t=Binding.t list
  let equal a b=a==b
  let hash=function [] -> 0 | h::_ -> Binding.id h
 end)
 type summary={selected:Binding.t list; length:int; omitted:int}
 let tables=Domain.DLS.new_key(fun () -> H.create 256)
 let select bindings =
  if not !Core_nodes.summary_enabled then bindings else
  let table=Domain.DLS.get tables in
  let rec missing pending rest=match H.find_opt table rest with
  | Some summary -> pending,summary
  | None -> match rest with
    | [] -> pending,{selected=[];length=0;omitted=0}
    | head::tail -> missing ((rest,head)::pending) tail
  in
  let pending,initial=missing [] bindings in
  let summary=List.fold_left(fun suffix (key,head) ->
   let keep=Binding.keep head in
   let next={selected=(if keep then head::suffix.selected else suffix.selected);
    length=suffix.length+1;omitted=suffix.omitted+(if keep then 0 else 1)} in
   if H.length table>=16384 then H.clear table;
   H.replace table key next;next) initial pending in
  Core_nodes.add_count "generalization.bindings_omitted" summary.omitted;
  Core_nodes.add_count "generalization.bindings_retained" (summary.length-summary.omitted);
  summary.selected
end
