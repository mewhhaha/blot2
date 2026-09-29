let checks = ref 0
let check label condition = incr checks; if not condition then failwith label
let rec sum depth value =
  if depth = 0 then value else
    let left,right = Native_parallel.two
      (fun () -> sum (depth-1) value) (fun () -> sum (depth-1) (value+1)) in
    left + right
let () =
  let expected = Sys.argv.(1) in
  check "selected backend" (Native_parallel.backend =
    if expected = "domains" then "domains" else "serial-portability");
  List.iter (fun requested ->
    Native_parallel.configure requested;
    Fun.protect (fun () ->
      check "worker bound" (Native_parallel.worker_count () <= requested);
      check "nested fork/join" (sum 12 0 = 24576);
      check "heterogeneous jobs" (Native_parallel.four
        (fun () -> 42) (fun () -> "ok") (fun () -> true) (fun () -> [1;2]) =
        (42,"ok",true,[1;2]));
      for _ = 1 to 20 do
        let first_error = try
          ignore (Native_parallel.two (fun () -> failwith "left") (fun () -> failwith "right"));
          false
        with Failure text -> text = "left" in
        check "exception precedence" first_error;
        check "pool survives exception" (sum 7 1 = 576)
      done
    ) ~finally:Native_parallel.shutdown;
    check "shutdown" (Native_parallel.worker_count () = 1)
  ) [1;2;4;8];
  Printf.printf "%d fork/join checks passed (%s)\n" !checks Native_parallel.backend
