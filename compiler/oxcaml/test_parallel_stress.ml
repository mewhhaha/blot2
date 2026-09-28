(* Exact-once execution, idle wakeups, bounded saturation and joined failures. *)
let checks = ref 0
let check label condition = incr checks; if not condition then failwith label
let () =
  List.iter (fun requested ->
    Native_parallel.configure requested;
    Fun.protect (fun () ->
      let count = 8192 in
      let seen = Array.init count (fun _ -> Atomic.make 0) in
      let rec visit start length =
        if length = 1 then begin Atomic.incr seen.(start); start end
        else
          let half = length/2 in
          let a,b = Native_parallel.two (fun () -> visit start half)
            (fun () -> visit (start+half) (length-half)) in a+b
      in
      check "nested result" (visit 0 count = count*(count-1)/2);
      Array.iter (fun cell -> check "each leaf runs exactly once" (Atomic.get cell=1)) seen;
      for i = 1 to 300 do
        if i mod 10 = 0 then Unix.sleepf 0.0001;
        let a,b = Native_parallel.two (fun () -> i) (fun () -> i+1) in
        check "idle wake and result publication" (b=a+1)
      done;
      if Native_parallel.worker_count () > 1 then begin
        for i = 1 to 100 do
          let joined = Atomic.make false in
          let first = try
            ignore (Native_parallel.two
              (fun () -> failwith "first")
              (fun () -> if i mod 2=0 then Unix.sleepf 0.0001;
                Atomic.set joined true; failwith "second")); false
            with Failure text -> text="first" in
          check "deterministic first error" first;
          check "exception joins child" (Atomic.get joined)
        done;
        (* Repeat after failures to catch stranded jobs and poisoned queues. *)
        check "pool recovers after joined failures" (visit 0 count = count*(count-1)/2);
        Array.iter (fun cell -> check "no duplicate/lost jobs on recovery" (Atomic.get cell=2)) seen
      end;
      let weak = Weak.create 1 in
      let[@inline never] submit () =
        let payload = Bytes.make 1000000 'x' in
        Weak.set weak 0 (Some payload);
        ignore (Native_parallel.two (fun () -> ())
          (fun () -> ignore (Sys.opaque_identity (Bytes.get payload 0))))
      in
      submit ();
      let rec collect attempts =
        Gc.full_major ();
        if Weak.check weak 0 && attempts > 0 then (Unix.sleepf 0.001; collect (attempts-1))
      in collect 50;
      check "completed queue slots do not retain captures" (not (Weak.check weak 0))
    ) ~finally:Native_parallel.shutdown;
    check "teardown releases workers" (Native_parallel.worker_count ()=1)
  ) [1;2;4;8];
  Printf.printf "%d concurrency stress checks passed\n" !checks
