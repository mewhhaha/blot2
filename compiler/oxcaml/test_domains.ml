(* This test requires real concurrent domains: neither serial evaluation nor
   a nonpersistent thread-count placeholder can satisfy the barrier. *)
let () =
  Native_parallel.configure 2;
  Fun.protect (fun () ->
    if Native_parallel.worker_count () < 2 then
      print_endline "Concurrent-domain barrier skipped: only one CPU is available"
    else begin
      let lock = Mutex.create () in
      let ready = Condition.create () in
      let arrived = ref 0 in
      let rendezvous () =
        Mutex.lock lock;
        incr arrived;
        Condition.broadcast ready;
        while !arrived < 2 do Condition.wait ready lock done;
        Mutex.unlock lock;
        Domain.self ()
      in
      let left,right = Native_parallel.two rendezvous rendezvous in
      assert (left <> right);
      let completed = Atomic.make false in
      (try ignore (Native_parallel.two
         (fun () -> failwith "first")
         (fun () -> Unix.sleepf 0.01; Atomic.set completed true));
         assert false
       with Failure text -> assert (text = "first"));
      assert (Atomic.get completed);
      assert (Native_parallel.worker_count () = 2);
      print_endline "Concurrent-domain barrier, exception join, and persistent-worker checks passed"
    end
  ) ~finally:Native_parallel.shutdown
