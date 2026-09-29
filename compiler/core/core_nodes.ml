(* Identity uniqueness is independent of scheduling. Identities are internal,
   never serialized; content checks and original ordering determine outputs. *)
let enabled = ref true
let intern_bodies = ref false
let cache_enabled = ref true
let scope_enabled = ref true
let summary_enabled = ref true
let stats_enabled = ref false
let epoch = Atomic.make 0
let begin_request () = ignore (Atomic.fetch_and_add epoch 1)
let next_block = Atomic.make 0
let block_size = 1 lsl 16
let ids = Domain.DLS.new_key (fun () -> ref (0, 0))
let fresh_id () =
  let slot = Domain.DLS.get ids in
  let next, limit = !slot in
  if next < limit then (slot := next + 1, limit; next)
  else begin
    let first = Atomic.fetch_and_add next_block block_size in
    if first < 0 || first > max_int - block_size then failwith "semantic identity space exhausted";
    slot := first + 1, first + block_size;
    first
  end
let mix a b = ((a * 65599) lxor b) land max_int
let rec list_equal eq a b = a == b || match a, b with
  | [], [] -> true
  | x :: xs, y :: ys -> eq x y && list_equal eq xs ys
  | _ -> false
let list_hash hash xs = List.fold_left (fun h x -> mix h (hash x)) 19 xs
let option_equal eq a b = match a,b with
  | None,None -> true | Some a,Some b -> eq a b | _ -> false
let option_hash hash = function None -> 7 | Some a -> mix 11 (hash a)

(* Stats are off in timings. Only registration needs a mutex; each task updates
   its current domain's counters. Read after all domains have been joined. *)
let stats_mutex = Mutex.create ()
let all_counters = ref []
let counters = Domain.DLS.new_key (fun () ->
 let values=Hashtbl.create 32 in
 Mutex.lock stats_mutex; all_counters:=values :: !all_counters; Mutex.unlock stats_mutex;
 values)
let note name = if !stats_enabled then begin
 let values=Domain.DLS.get counters in
 Hashtbl.replace values name (1 + Option.value (Hashtbl.find_opt values name) ~default:0)
end
let add_count name amount = if !stats_enabled then begin
 let values=Domain.DLS.get counters in
 Hashtbl.replace values name (amount + Option.value (Hashtbl.find_opt values name) ~default:0)
end
let report () =
 let sum=Hashtbl.create 32 in
 List.iter (fun values -> Hashtbl.iter (fun key value -> Hashtbl.replace sum key (value + Option.value (Hashtbl.find_opt sum key) ~default:0)) values) !all_counters;
 let pairs=Hashtbl.fold (fun key value rest -> (key,value)::rest) sum [] |> List.sort compare in
 "{" ^ String.concat "," (List.map (fun (key,value) -> Printf.sprintf "%S:%d" key value) pairs) ^ "}"

module Cache (Key : Hashtbl.HashedType) = struct
 module H = Hashtbl.Make(Key)
 type 'a cache = { values : 'a H.t; hit : string; miss : string; mutable epoch:int }
 let create label = {values=H.create 256; hit=label^".hits"; miss=label^".computations"; epoch=(-1)}
 let memo cache key compute =
  let now=Atomic.get epoch in
  if cache.epoch <> now then (H.clear cache.values;cache.epoch<-now);
  if not !cache_enabled then (note cache.miss; compute ()) else
  match H.find cache.values key with
  | answer -> note cache.hit; answer
  | exception Not_found ->
    note cache.miss;
    let answer=compute () in
    if H.length cache.values >= 8192 then H.clear cache.values;
    H.replace cache.values key answer;
    answer
end

(* Indexes last one request; retained session values own their immutable nodes
   independently. An epoch changes only after the previous fork/join completes. *)
module Intern (Shape : Hashtbl.HashedType) = struct
 module H = Hashtbl.Make(Shape)
 type table = { values : Shape.t H.t; mutable epoch : int }
 let create size = { values=H.create size; epoch=(-1) }
 let merge table value =
  let now=Atomic.get epoch in
  if now <> table.epoch then (H.clear table.values; table.epoch <- now);
  note "nodes.requests";
  match H.find_opt table.values value with
  | Some previous -> note "nodes.reused"; previous
  | None -> note "nodes.created"; H.add table.values value value; value
end

(* Graph lists are immutable. A weak physical root identity avoids rebuilding a
   whole-program key at every group boundary. Clearing the index only loses hits;
   globally unique identities cannot alias a later or concurrent snapshot. *)
module Identity (Key : Hashtbl.HashedType) = struct
 module H = Ephemeron.K1.Make(Key)
 let create () = H.create 128
 let get table value = match H.find_opt table value with
 | Some identity -> identity
 | None ->
   if H.length table >= 8192 then H.clear table;
   let identity=fresh_id () in H.add table value identity; identity
end

(* Lookup a shallow constructor key before allocating a candidate node. This
   avoids allocating an entire duplicate type on the common interning hit. *)
module Table (Key : Hashtbl.HashedType) = struct
 module H = Hashtbl.Make(Key)
 type 'a t = { values:'a H.t; mutable epoch:int }
 let create size = {values=H.create size; epoch=(-1)}
 let current table =
  let now=Atomic.get epoch in
  if now<>table.epoch then (H.clear table.values; table.epoch<-now);
  table.values
end
