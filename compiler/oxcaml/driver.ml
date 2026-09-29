let () =
  let threads = ref 1 in
  let inherit_priority = ref false in
  Arg.parse [
    "--threads", Arg.Set_int threads, "N Worker count (1..64; bounded by available CPUs)";
    "--inherit-priority", Arg.Set inherit_priority, "Inherit process priority"
  ] (fun arg -> raise (Arg.Bad ("unexpected argument: " ^ arg))) "blotc [--threads N]";
  if !threads < 1 || !threads > 64 then (prerr_endline "threads must be in [1,64]"; exit 2);
  Native_runtime.configure !inherit_priority;
  Printexc.record_backtrace true;
  try
    Native_parallel.configure !threads;
    Fun.protect (fun () -> Ox_native_main.f_main () ())
      ~finally:Native_parallel.shutdown
  with
  | End_of_file -> prerr_endline "native protocol: truncated frame"; exit 1
  | exn -> prerr_endline (Printexc.to_string exn); Printexc.print_backtrace stderr; exit 1
