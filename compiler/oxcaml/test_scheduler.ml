(* Structured fork/join under saturation, uneven work, failures and reuse.
   Kept separate from the fixed compatibility tests. The test driver imposes a
   wall-clock timeout, so a missed wakeup cannot hang the whole test job. *)
let checks = ref 0
let check label condition = incr checks; if not condition then failwith label
let rec fold_count depth seed visited =
  if depth = 0 then (ignore (Atomic.fetch_and_add visited 1); seed)
  else
    let left, right = Native_parallel.two
      (fun () -> fold_count (depth-1) seed visited)
      (fun () -> fold_count (depth-1) (seed+1) visited)
    in left + right
let rec uneven count offset visited =
  if count <= 1 then (ignore (Atomic.fetch_and_add visited 1); offset)
  else
    let split = if count mod 2 = 0 then 1 else count / 2 in
    let left, right = Native_parallel.two
      (fun () -> uneven split offset visited)
      (fun () -> uneven (count-split) (offset+split) visited)
    in left + right
let () =
  Printexc.record_backtrace true;
  List.iter (fun workers ->
    Native_parallel.configure workers;
    Fun.protect (fun () ->
      check "bounded domain count" (Native_parallel.worker_count () <= workers);
      let visited = Atomic.make 0 in
      for _ = 1 to 12 do
        Atomic.set visited 0;
        check "saturated nested fork values" (fold_count 11 0 visited = 11264);
        check "saturated tasks run exactly once" (Atomic.get visited = 2048);
        Atomic.set visited 0;
        check "uneven nested fork values" (uneven 257 0 visited = 32896);
        check "uneven tasks run exactly once" (Atomic.get visited = 257)
      done;
      for _ = 1 to 30 do
        let active = Atomic.make 0 in
        let body message =
          ignore (Atomic.fetch_and_add active 1);
          Fun.protect (fun () ->
            let a,b = Native_parallel.two
              (fun () -> Unix.sleepf 0.0001; 1)
              (fun () -> Unix.sleepf 0.0001; 2) in
            assert (a+b=3);
            failwith message)
            ~finally:(fun () -> ignore (Atomic.fetch_and_add active (-1)))
        in
        let first = try
          ignore (Native_parallel.two (fun () -> body "left") (fun () -> body "right"));
          false
        with Failure message -> message = "left" in
        check "nested exception precedence" first;
        check "no child remains active after an exception" (Atomic.get active = 0);
        check "pool reusable after exception" (Native_parallel.two (fun () -> 20) (fun () -> 22) = (20,22))
      done;
      check "heterogeneous eight-way join" (Native_parallel.eight
        (fun () -> 1) (fun () -> "two") (fun () -> [3]) (fun () -> Some 4)
        (fun () -> true) (fun () -> ()) (fun () -> 7.) (fun () -> 8l)
        = (1,"two",[3],Some 4,true,(),7.,8l))
    ) ~finally:Native_parallel.shutdown;
    check "workers joined on shutdown" (Native_parallel.worker_count () = 1)
  ) [1;2;4;8];
  Printf.printf "%d scheduler stress checks passed\n" !checks
