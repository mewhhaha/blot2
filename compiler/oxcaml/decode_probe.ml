(* Test/measurement driver shared by baseline and candidate. Not linked into blotc.
   Compares the complete canonical decode, not only whether decoding succeeds. *)
open Base
module R = Ox_native_request
module C = Ox_cst
module S = Ox_native_session
let canonical decoded =
  let out = Buffer.create 128 in
  let number n = Buffer.add_string out (string_of_int n); Buffer.add_char out ';' in
  let text t = let s = text_to_utf8 t in number (String.length s); Buffer.add_string out s in
  let nodes root =
    let rec loop = function
      | [] -> ()
      | [] :: rest -> loop rest
      | (C.Cst (kind,field,value,offset,children) :: siblings) :: rest ->
        text kind; text field; text value; number offset; number (List.length children);
        loop (children :: siblings :: rest)
    in loop [[root]]
  in
  let operation = function R.Analyze -> number 0 | R.Compile -> number 1 | R.EmitWasm -> number 7 in
  (match decoded with
  | Fail (Ox_model.Diagnostic (code,subject,detail)) ->
    number 0; text code; text subject; text detail
  | Done request ->
    number 1;
    match request with
    | R.Request (op,fuel,steps,root,prelude) ->
      number 0; operation op; number fuel; number steps; nodes root; nodes prelude
    | R.OpenSession (prelude,fuel) -> number 1; number fuel; nodes prelude
    | R.SessionRequest (op,fuel,steps,root) ->
      number 2; operation op; number fuel; number steps; nodes root
    | R.SessionPatch (op,fuel,steps,decls) ->
      number 3; operation op; number fuel; number steps; number (List.length decls);
      List.iter (function S.Retained id -> number 0; number id
        | S.Replaced node -> number 1; nodes node) decls);
  Buffer.contents out
let () =
  try
    let rec serve () =
      let before = Gc.allocated_bytes () in
      match Ox_native_transport.f_receive () () with
      | None -> ()
      | Some frame ->
        let decoded = R.f_decode frame in
        let allocated = Gc.allocated_bytes () -. before in
        let bytes = canonical decoded in
        Printf.printf "%d %.0f\n" (String.length bytes) allocated;
        output_string stdout bytes;
        flush stdout;
        serve ()
    in serve ()
  with exn -> prerr_endline (Printexc.to_string exn); exit 1
