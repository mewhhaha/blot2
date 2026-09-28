(* Bounded structured fork/join with worker-local deques and atomic completion.
   The owner uses LIFO order; thieves take the oldest work. No task or request
   survives its join. The only shared mutable locations are protected by a
   deque/event mutex or are Atomic.t. This is a legacy Domain boundary, not a
   claim that the compiler's whole call graph is mode-checked for race freedom.

   configure/shutdown belong to the single transport owner and cannot overlap
   an outstanding root call. Compiler jobs operate on immutable data. *)
[@@@alert "-unsafe_multidomain-do_not_spawn_domains"]
type job = unit -> unit
let no_job () = ()
type deque = {
  lock : Mutex.t;
  slots : job array;
  mutable front : int;
  mutable length : int;
}
type pool = {
  queues : deque array;
  event_lock : Mutex.t;
  changed : Condition.t;
  sleepers : int Atomic.t;
  stopping : bool Atomic.t;
  mutable workers : unit Domain.t list;
}
type context = { pool : pool; index : int; mutable victim : int }
let context = Domain.DLS.new_key (fun () -> None)
let active : pool option ref = ref None
let backend = "domains"

let capture f =
  try Ok (f ()) with exn -> Error (exn, Printexc.get_raw_backtrace ())
let unwrap = function
  | Ok value -> value
  | Error (exn, trace) -> Printexc.raise_with_backtrace exn trace

let push queue job =
  Mutex.lock queue.lock;
  let room = queue.length < Array.length queue.slots in
  if room then begin
    queue.slots.((queue.front + queue.length) mod Array.length queue.slots) <- job;
    queue.length <- queue.length + 1
  end;
  Mutex.unlock queue.lock;
  room
let pop queue ~steal =
  Mutex.lock queue.lock;
  let found = queue.length > 0 in
  let job = if not found then no_job else begin
    let position = if steal then queue.front
      else (queue.front + queue.length - 1) mod Array.length queue.slots in
    let job = queue.slots.(position) in
    (* Clear immediately: a completed closure must not retain its request. *)
    queue.slots.(position) <- no_job;
    queue.length <- queue.length - 1;
    if steal then queue.front <- (queue.front + 1) mod Array.length queue.slots;
    job
  end in
  Mutex.unlock queue.lock;
  if found then Some job else None
let take ctx =
  match pop ctx.pool.queues.(ctx.index) ~steal:false with
  | Some _ as job -> job
  | None ->
    let count = Array.length ctx.pool.queues in
    let rec steal remaining =
      if remaining = 0 then None else begin
        let victim = ctx.victim in
        ctx.victim <- (victim + 1) mod count;
        if victim = ctx.index then steal (remaining - 1)
        else match pop ctx.pool.queues.(victim) ~steal:true with
          | Some _ as job -> job
          | None -> steal (remaining - 1)
      end
    in steal count

let wake pool =
  if Atomic.get pool.sleepers > 0 then begin
    Mutex.lock pool.event_lock;
    Condition.broadcast pool.changed;
    Mutex.unlock pool.event_lock
  end
let park pool check =
  Mutex.lock pool.event_lock;
  Atomic.incr pool.sleepers;
  Fun.protect (fun () ->
    (* Register as a sleeper before rechecking. A concurrent publisher either
       becomes visible to check or takes event_lock after Condition.wait. *)
    match check () with
    | Some _ as ready -> ready
    | None -> Condition.wait pool.changed pool.event_lock; None)
    ~finally:(fun () -> Atomic.decr pool.sleepers; Mutex.unlock pool.event_lock)

type work = Stop | Work of job
let rec worker ctx () =
  let next () = match take ctx with
    | Some job -> Some (Work job)
    | None when Atomic.get ctx.pool.stopping -> Some Stop
    | None -> None
  in
  let work = match next () with Some _ as work -> work | None -> park ctx.pool next in
  match work with
  | Some Stop -> ()
  | Some (Work job) -> job (); worker ctx ()
  | None -> worker ctx ()

let shutdown () = match !active with
  | None -> ()
  | Some pool ->
    Atomic.set pool.stopping true;
    wake pool;
    List.iter Domain.join pool.workers;
    Domain.DLS.set context None;
    active := None
let configure requested =
  if requested < 1 || requested > 64 then invalid_arg "worker count must be in [1,64]";
  if !active <> None then invalid_arg "worker pool already initialized";
  let count = min requested (Domain.recommended_domain_count ()) in
  if count > 1 then begin
    (* Four slots per domain gives the same 4*N global queue bound as before. *)
    let queues = Array.init count (fun _ -> {lock=Mutex.create ();
      slots=Array.make 4 no_job; front=0; length=0}) in
    let pool = { queues; event_lock=Mutex.create (); changed=Condition.create ();
      sleepers=Atomic.make 0; stopping=Atomic.make false; workers=[] } in
    active := Some pool;
    Domain.DLS.set context (Some {pool; index=0; victim=1});
    try
      for index = 1 to count - 1 do
        let domain = Domain.spawn (fun () ->
          let ctx = {pool; index; victim=(index+1) mod count} in
          Domain.DLS.set context (Some ctx);
          worker ctx ()) in
        pool.workers <- domain :: pool.workers
      done
    with exn -> shutdown (); raise exn
  end
let worker_count () = match !active with None -> 1 | Some pool -> Array.length pool.queues

type 'a awaiting = Ready of 'a | Help of job
let two left right = match !active with
  | None -> let a = left () in let b = right () in a,b
  | Some pool ->
    if Atomic.get pool.stopping then invalid_arg "worker pool is stopping";
    let ctx = match Domain.DLS.get context with
      | Some ctx when ctx.pool == pool -> ctx
      | _ -> invalid_arg "fork/join called outside its owning domain pool"
    in
    let result = Atomic.make None in
    let work () =
      let outcome = capture right in
      Atomic.set result (Some outcome);
      wake pool
    in
    if not (push pool.queues.(ctx.index) work) then
      (let a = left () in let b = right () in a,b)
    else begin
      wake pool;
      let a = capture left in
      let check () = match Atomic.get result with
        | Some result -> Some (Ready result)
        | None -> match take ctx with None -> None | Some job -> Some (Help job)
      in
      let rec await () =
        (* Most completed joins avoid every mutex and condition variable. *)
        match Atomic.get result with
        | Some result -> result
        | None ->
          let action = match check () with Some _ as x -> x | None -> park pool check in
          match action with
          | Some (Ready result) -> result
          | Some (Help job) -> job (); await ()
          | None -> await ()
      in
      let b = await () in
      (* Finish both children before exposing the first source-order error. *)
      let a = unwrap a in
      let b = unwrap b in
      a,b
    end
let four a b c d =
  let (a,b),(c,d) = two (fun () -> two a b) (fun () -> two c d) in a,b,c,d
let eight a b c d e f g h =
  let (a,b,c,d),(e,f,g,h) = two (fun () -> four a b c d) (fun () -> four e f g h) in
  a,b,c,d,e,f,g,h
