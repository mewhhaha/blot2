let () =
  let threads = ref 1 in
  let inherit_priority = ref false in
  let graph_report_dir = ref None in
  let graph_stderr = ref false in
  Arg.parse [
    "--threads", Arg.Set_int threads, "N Worker count (1..64; bounded by available CPUs)";
    "--type-graph-stderr", Arg.Set graph_stderr, "Also print a type-graph summary when writing reports";
    "--type-graph-report-dir", Arg.String(fun path -> graph_report_dir := Some path), "DIR Save verification counters before each response and at shutdown";
    "--verify-type-graph", Arg.Set Core_graph_verify.enabled, "Compare normalized constraints against the experimental type graph";
    "--inherit-priority", Arg.Set inherit_priority, "Inherit process priority"
  ] (fun arg -> raise (Arg.Bad ("unexpected argument: " ^ arg))) "blotc [--threads N]";
  if !threads < 1 || !threads > 64 then (prerr_endline "threads must be in [1,64]"; exit 2);
  if (!graph_report_dir<>None || !graph_stderr) && not !Core_graph_verify.enabled then
    (prerr_endline "type-graph report directory requires --verify-type-graph";exit 2);
  let report_file = match !graph_report_dir with
    | None -> None
    | Some directory ->
      let path,channel=Filename.open_temp_file ~temp_dir:directory "graph-" ".json" in
      close_out channel;Some path
  in
  let save_graph () = match report_file with
    | None -> ()
    | Some path ->
      let temporary,channel=Filename.open_temp_file ~temp_dir:(Filename.dirname path) "writing-graph-" ".tmp" in
      (try
        Fun.protect (fun()->Printf.fprintf channel "{\"pid\":%d,\"graph\":%s}\n"
          (Unix.getpid()) (Core_graph_verify.report ())) ~finally:(fun()->close_out channel);
        Sys.rename temporary path
       with error -> (try Sys.remove temporary with Sys_error _ -> ());raise error)
  in
  Core_graph_verify.publish := save_graph;
  save_graph ();
  let report_graph () = if !Core_graph_verify.enabled then begin
    save_graph ();
    if !graph_stderr || !graph_report_dir=None then
      prerr_endline ("CORE_TYPE_GRAPH " ^ Core_graph_verify.report ())
  end in
  Native_runtime.configure !inherit_priority;
  Printexc.record_backtrace true;
  try
    Native_parallel.configure !threads;
    Fun.protect (fun () -> Sem_native_main.f_main () ())
      ~finally:(fun () ->
        Fun.protect Native_parallel.shutdown ~finally:report_graph)
  with
  | End_of_file -> prerr_endline "native protocol: truncated frame"; exit 1
  | exn -> prerr_endline (Printexc.to_string exn); Printexc.print_backtrace stderr; exit 1
