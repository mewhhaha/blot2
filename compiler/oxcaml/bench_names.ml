(* Microbenchmark only: use bench_compare.ts for source-to-Wasm performance.
   Both paths use this build's character layout. The legacy path reproduces
   the original ownership-carrying comparison, not a separate compiler binary. *)
open Base
let[@inline never] legacy left right =
  Ox_model.f_name_equal_result
    (Ox_model.f_name_equal_walk left right left right true)
let[@inline never] current left right = Ox_model.f_name_equal left right
let measure label equal left right iterations =
  Gc.full_major ();
  let before = Gc.allocated_bytes () in
  let started = Unix.gettimeofday () in
  let checksum = ref 0 in
  for _ = 1 to iterations do
    if equal (Sys.opaque_identity left) (Sys.opaque_identity right) then incr checksum
  done;
  let elapsed = Unix.gettimeofday () -. started in
  let allocated = Gc.allocated_bytes () -. before in
  Printf.printf "%s: %.3f ms, %.3f allocated bytes/call, checksum=%d\n%!"
    label (elapsed *. 1000.) (allocated /. float_of_int iterations) !checksum
let () =
  let iterations = if Array.length Sys.argv = 1 then 1000000
    else if Array.length Sys.argv = 2 then int_of_string Sys.argv.(1)
    else invalid_arg "usage: bench_names [iterations]" in
  if iterations < 1 || iterations > 100000000 then invalid_arg "iterations must be in [1,100000000]";
  let left = text_of_utf8 "std/prelude::some.identifier" in
  let right = text_of_utf8 "std/prelude::some.identifier" in
  List.iter (fun (label, a, b) ->
    measure (label ^ "/legacy") legacy a b iterations;
    measure (label ^ "/native") current a b iterations)
    ["shared", left, left;
     "distinct-equal", left, right;
     "early-miss", left, text_of_utf8 "different";
     "shared-tail", SCon (Chr 97l, left), SCon (Chr 97l, left)];
  let n = min iterations 100000 in
  Gc.full_major ();
  let before = Gc.allocated_bytes () in
  let text = ref SNil in
  for i = 0 to n - 1 do
    text := SCon (Chr (Int32.of_int (Sys.opaque_identity i land 0xffff)), !text)
  done;
  let allocated = Gc.allocated_bytes () -. before in
  Printf.printf "text construction: %.3f allocated bytes/character, length=%d\n%!"
    (allocated /. float_of_int n) (string_length !text)
