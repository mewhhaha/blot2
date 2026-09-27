(* Native semantic port of compiler/native_main.bend.

   Source SHA-256: d99b38ae280c078bf2d05ec0e0e5f0158d3a38480bb74ad6e5068e49d41b8e10

   Ownership/type arguments are erased; value types are checked by OCaml.

   No Bend interpreter or generated C/JavaScript is linked. *)

open Base

module M = Ox_model

module Cst = Ox_cst

module Compiler = Ox_main

module Request = Ox_native_request

module Response = Ox_native_response

module Output = Ox_native_output

module NativeIO = Ox_native_io

module Transport = Ox_native_transport

module Session = Ox_native_session

type t_Reply =
  | Reply of (Session.t_State) option * Output.t_Packet

let s_0 = Base.text_of_utf8 "native_session"

let s_1 = Base.text_of_utf8 "session"

let s_2 = Base.text_of_utf8 "open a session before updating it"

let s_3 = Base.text_of_utf8 "native compiler request limit exhausted"

let rec (* native_main.bend:15 *)
f_state_of : t_Reply -> (Session.t_State) option =
fun v_reply ->
(let (Reply (v_state, v_packet)) = v_reply in
v_state)
and (* native_main.bend:19 *)
f_packet_of : t_Reply -> Output.t_Packet =
fun v_reply ->
(let (Reply (v_state, v_packet)) = v_reply in
v_packet)
and (* native_main.bend:23 *)
f_opened : (Session.t_State) option -> (M.t_Diagnostic, Session.t_State) Base.result_ -> t_Reply =
fun v_previous v_result ->
(match v_result with
| (Fail (v_diagnostic)) ->
(Reply (v_previous, (Output.f_words ((Response.f_encode_diagnostic (v_diagnostic))))))
| (Done (v_state)) ->
(Reply ((Some (v_state)), (Output.f_words ((Response.f_encode (0x00000003l) ([])))))))
and (* native_main.bend:30 *)
f_stat_fields : Session.t_Stats -> (Response.t_Work) list -> (Response.t_Work) list =
fun v_stats v_fields ->
(let (Session.Stats (v_lowered, v_declarations_reused, v_checked, v_groups_reused, v_evaluated, v_constants_reused, v_compiled, v_entries_reused)) = v_stats in
((Response.Word (0x424c4f54l)) :: ((Response.Word ((Response.f_version ()))) :: ((Response.Word (0x00000004l)) :: ((Response.Natural (v_lowered)) :: ((Response.Natural (v_declarations_reused)) :: ((Response.Natural (v_checked)) :: ((Response.Natural (v_groups_reused)) :: ((Response.Natural (v_evaluated)) :: ((Response.Natural (v_constants_reused)) :: ((Response.Natural (v_compiled)) :: ((Response.Natural (v_entries_reused)) :: v_fields))))))))))))
and (* native_main.bend:35 *)
f_encoded : (Session.t_State) option -> Session.t_State -> (M.t_Diagnostic, Output.t_Packet) Base.result_ -> t_Reply =
fun v_previous v_state v_result ->
(match v_result with
| (Fail (v_diagnostic)) ->
(Reply (v_previous, (Output.f_words ((Response.f_encode_diagnostic (v_diagnostic))))))
| (Done (v_packet)) ->
(Reply ((Some (v_state)), v_packet)))
and (* native_main.bend:42 *)
f_encode_analysis : (Response.t_Work) list -> (M.t_Diagnostic, Output.t_Packet) Base.result_ =
fun v_fields ->
(match (Response.f_encode_work ((M.f_max_nat ())) (v_fields) ((Base.u32_to_nat (0x01000000l))) ([])) with
| Fail __error -> Fail __error
| Done v_words ->
(Done ((Output.f_words (v_words)))))
and (* native_main.bend:47 *)
f_completed : (Session.t_State) option -> Output.t_Contents -> (M.t_Diagnostic, Session.t_Completion) Base.result_ -> t_Reply =
fun v_previous v_contents v_result ->
(match v_result with
| (Fail (v_diagnostic)) ->
(Reply (v_previous, (Output.f_words ((Response.f_encode_diagnostic (v_diagnostic))))))
| (Done ((Session.Completion (v_state, (Session.Analyzed (v_analysis)), v_stats)))) ->
(f_encoded (v_previous) (v_state) ((f_encode_analysis ((f_stat_fields (v_stats) ([(Response.Word (0x00000001l)); (Response.Analysis (v_analysis))]))))))
| (Done ((Session.Completion (v_state, (Session.Compiled ((Compiler.PlannedArtifact (v_analysis, v_plan)))), v_stats)))) ->
(f_encoded (v_previous) (v_state) ((Output.f_encode_plan ((f_stat_fields (v_stats) ((Output.f_artifact_fields (v_contents) (v_analysis))))) (v_plan) ((Base.u32_to_nat (0x01000000l))) (2048)))))
and (* native_main.bend:56 *)
f_cached : (Session.t_State) option -> Request.t_Operation -> Cst.t_Cst -> int -> int -> t_Reply =
fun v_previous v_operation v_root v_fuel v_steps ->
(match v_previous with
| None ->
(Reply (None, (Output.f_words ((Response.f_encode_diagnostic ((M.Diagnostic (s_0, s_1, s_2))))))))
| (Some (v_state)) ->
(f_completed ((Some (v_state))) ((Request.f_contents (v_operation))) ((Session.f_update (v_state) ((Request.f_mode (v_operation))) (v_root) (v_fuel) (v_steps)))))
and (* native_main.bend:63 *)
f_patched : (Session.t_State) option -> Request.t_Operation -> (Session.t_Declaration) list -> int -> int -> t_Reply =
fun v_previous v_operation v_declarations v_fuel v_steps ->
(match v_previous with
| None ->
(Reply (None, (Output.f_words ((Response.f_encode_diagnostic ((M.Diagnostic (s_0, s_1, s_2))))))))
| (Some (v_state)) ->
(f_completed ((Some (v_state))) ((Request.f_contents (v_operation))) ((Session.f_update_patch (v_state) ((Request.f_mode (v_operation))) (v_declarations) (v_fuel) (v_steps)))))
and (* native_main.bend:70 *)
f_respond : (Session.t_State) option -> (M.t_Diagnostic, Request.t_Request) Base.result_ -> t_Reply =
fun v_state v_request ->
(match v_request with
| (Fail (v_diagnostic)) ->
(Reply (v_state, (Output.f_words ((Response.f_encode_diagnostic (v_diagnostic))))))
| (Done ((Request.Request (Request.Analyze, v_fuel, v_steps, v_root, v_prelude)))) ->
(Reply (v_state, (Output.f_words ((Response.f_encode_analysis ((Compiler.f_analyze_source (v_root) (v_prelude) (v_fuel) (v_steps))))))))
| (Done ((Request.Request (Request.Compile, v_fuel, v_steps, v_root, v_prelude)))) ->
(Reply (v_state, (Output.f_encode_artifact (Output.FullArtifact) ((Compiler.f_compile_source_plan (v_root) (v_prelude) (v_fuel) (v_steps))))))
| (Done ((Request.Request (Request.EmitWasm, v_fuel, v_steps, v_root, v_prelude)))) ->
(Reply (v_state, (Output.f_encode_artifact (Output.WasmOnly) ((Compiler.f_compile_source_plan (v_root) (v_prelude) (v_fuel) (v_steps))))))
| (Done ((Request.OpenSession (v_prelude, v_fuel)))) ->
(f_opened (v_state) ((Session.f_open (v_prelude) (v_fuel))))
| (Done ((Request.SessionRequest (v_operation, v_fuel, v_steps, v_root)))) ->
(f_cached (v_state) (v_operation) (v_root) (v_fuel) (v_steps))
| (Done ((Request.SessionPatch (v_operation, v_fuel, v_steps, v_declarations)))) ->
(f_patched (v_state) (v_operation) (v_declarations) (v_fuel) (v_steps)))
and (* native_main.bend:87 *)
f_send_packet : Output.t_Packet -> (unit) Base.io =
fun v_packet ->
(let (Output.Packet (v_word_count, v_header, v_blocks)) = v_packet in
(Transport.f_send (v_word_count) (v_header) (v_blocks)))
and (* native_main.bend:93 *)
f_serve : int -> (Session.t_State) option -> (NativeIO.t_Frame) option -> (unit) Base.io =
fun v_fuel v_state v_incoming ->
(match (v_fuel, v_incoming) with
| (_, None) ->
(Base.io_pure (()))
| (0, (Some (v_frame))) ->
(Base.io_die (0x00000001l) (s_3))
| (__nat_1, (Some (v_frame))) when __nat_1 >= 1 ->
(let v_remaining = (__nat_1 - 1) in
(let v_reply = (f_respond (v_state) ((Request.f_decode (v_frame)))) in
(let v_next_state = (f_state_of (v_reply)) in
(let v_packet = (f_packet_of (v_reply)) in
(Base.io_bind (f_send_packet (v_packet)) (fun _ ->
(Base.io_bind (Transport.f_receive ()) (fun v_next ->
(f_serve (v_remaining) (v_next_state) (v_next)))))))))))
and (* native_main.bend:108 *)
f_main : unit -> (unit) Base.io =
fun () ->
(Base.io_bind (Transport.f_send (0x00000002l) ([0x424c4f54l; (Response.f_version ())]) ([])) (fun _ ->
(Base.io_bind (Transport.f_receive ()) (fun v_first ->
(f_serve ((M.f_max_nat ())) (None) (v_first))))))
