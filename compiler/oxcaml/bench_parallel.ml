let[@inline never] leaf iterations seed =
  let value = ref seed in
  for _ = 1 to iterations do value := (!value*1664525+1013904223) land 0xffff done;
  !value
let rec tree depth iterations skew seed =
  if depth=0 then leaf (if skew && seed land 15=0 then iterations*16 else iterations) seed
  else let a,b = Native_parallel.two
    (fun () -> tree (depth-1) iterations skew (seed*2))
    (fun () -> tree (depth-1) iterations skew (seed*2+1)) in a+b
let rec serial depth iterations skew seed =
  if depth=0 then leaf (if skew && seed land 15=0 then iterations*16 else iterations) seed
  else serial (depth-1) iterations skew (seed*2) + serial (depth-1) iterations skew (seed*2+1)
let () =
  let usage () =
    prerr_endline "Usage: bench_parallel <workers:1..64> <depth:0..20> <leaf-iterations:0..1000000> <skew:true|false>";
    exit 2
  in
  if Array.length Sys.argv <> 5 then usage ();
  let workers, depth, iterations, skew =
    try int_of_string Sys.argv.(1), int_of_string Sys.argv.(2),
      int_of_string Sys.argv.(3), bool_of_string Sys.argv.(4)
    with Failure _ | Invalid_argument _ -> usage ()
  in
  if workers < 1 || workers > 64 || depth < 0 || depth > 20 ||
     iterations < 0 || iterations > 1000000 then usage ();
  Native_parallel.configure workers;
  Fun.protect (fun () ->
    let expected = serial depth iterations skew 1 in
    for _=1 to 2 do assert (tree depth iterations skew 1=expected) done;
    let start = Unix.gettimeofday () in
    let result = tree depth iterations skew 1 in
    let elapsed = Unix.gettimeofday () -. start in
    assert(result=expected);
    Printf.printf "%d %.9f %d\n" (Native_parallel.worker_count ()) elapsed result
  ) ~finally:Native_parallel.shutdown
