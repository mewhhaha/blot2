(* A bounded, persistent fork/join pool for this standalone executable.
   It exclusively owns its domains: do not combine it with Multicore or another
   domain pool. The requested count is capped at Domain.recommended_domain_count.

   This compatibility boundary uses OCaml's legacy Domain API. Every queue,
   completion, and stop-flag access is under [lock]; the compiler jobs passed to
   it operate on immutable values. We do not claim mode-checked race freedom.
   Jobs waiting on children help execute queued work, preventing nested-fork
   starvation. All children finish before an exception reaches the caller. *)
[@@@alert "-unsafe_multidomain-do_not_spawn_domains"]

type pool = {
  lock : Mutex.t;
  changed : Condition.t;
  jobs : (unit -> unit) Queue.t;
  limit : int;
  mutable stopping : bool;
  mutable workers : unit Domain.t list;
}

let active : pool option ref = ref None
let backend = "domains"
let capture f =
  try Ok (f ()) with exn -> Error (exn, Printexc.get_raw_backtrace ())
let unwrap = function
  | Ok value -> value
  | Error (exn, trace) -> Printexc.raise_with_backtrace exn trace

let run_locked pool f =
  Mutex.lock pool.lock;
  Fun.protect f ~finally:(fun () -> Mutex.unlock pool.lock)

let rec worker pool () =
  let next = run_locked pool (fun () ->
    while Queue.is_empty pool.jobs && not pool.stopping do
      Condition.wait pool.changed pool.lock
    done;
    if Queue.is_empty pool.jobs then None else Some (Queue.pop pool.jobs))
  in match next with None -> () | Some work -> work (); worker pool ()

let shutdown () = match !active with
  | None -> ()
  | Some pool ->
    run_locked pool (fun () -> pool.stopping <- true; Condition.broadcast pool.changed);
    List.iter Domain.join pool.workers;
    active := None

let configure requested =
  if requested < 1 || requested > 64 then invalid_arg "worker count must be in [1,64]";
  if !active <> None then invalid_arg "worker pool already initialized";
  let count = min requested (Domain.recommended_domain_count ()) in
  if count > 1 then begin
    let pool = { lock = Mutex.create (); changed = Condition.create ();
      jobs = Queue.create (); limit = 4 * count; stopping = false; workers = [] } in
    active := Some pool;
    try
      for _ = 2 to count do
        let domain = Domain.spawn (worker pool) in
        pool.workers <- domain :: pool.workers
      done
    with exn -> shutdown (); raise exn
  end

let worker_count () = match !active with None -> 1 | Some p -> List.length p.workers + 1

let two left right = match !active with
  | None -> let a = left () in let b = right () in a, b
  | Some pool ->
    let result = ref None in
    let work () =
      let outcome = capture right in
      run_locked pool (fun () -> result := Some outcome; Condition.broadcast pool.changed)
    in
    let queued = run_locked pool (fun () ->
      if pool.stopping then invalid_arg "worker pool is stopping";
      if Queue.length pool.jobs >= pool.limit then false
      else (Queue.push work pool.jobs; Condition.broadcast pool.changed; true))
    in
    if not queued then (let a = left () in let b = right () in a,b)
    else begin
      let a = capture left in
      let rec await () =
        Mutex.lock pool.lock;
        match !result with
        | Some value -> Mutex.unlock pool.lock; value
        | None when not (Queue.is_empty pool.jobs) ->
          let job = Queue.pop pool.jobs in
          Mutex.unlock pool.lock;
          job ();
          await ()
        | None ->
          Condition.wait pool.changed pool.lock;
          Mutex.unlock pool.lock;
          await ()
      in
      let b = await () in
      (* Explicit left-to-right unwrap preserves deterministic error precedence. *)
      let a = unwrap a in
      let b = unwrap b in
      a, b
    end

let four a b c d =
  let (a,b),(c,d) = two (fun () -> two a b) (fun () -> two c d) in
  a,b,c,d
let eight a b c d e f g h =
  let (a,b,c,d),(e,f,g,h) = two (fun () -> four a b c d) (fun () -> four e f g h) in
  a,b,c,d,e,f,g,h
