(* Native semantic port of compiler/native_output.bend.

   Source SHA-256: e906759d38fb9344ac485a36bfca3d3b99801b8e03a76cc540fa0909a8bbbba8

   Ownership/type arguments are erased; value types are checked by OCaml.

   No Bend interpreter or generated C/JavaScript is linked. *)

open Base

module M = Ox_model

module W = Ox_wasm

module Main = Ox_main

module R = Ox_native_response

module B = Ox_inference_batch

type t_Block =
  | Block of int * (int32) list
and t_Packed =
  | Packed of int * (t_Block) list
and t_Packet =
  | Packet of int32 * (int32) list * (t_Block) list
and t_Contents =
  | FullArtifact
  | WasmOnly

let s_0 = Base.text_of_utf8 "internal_error"

let s_1 = Base.text_of_utf8 "wasm"

let s_2 = Base.text_of_utf8 "Wasm emitter produced a value outside byte range"

let s_3 = Base.text_of_utf8 "response traversal exceeded its bound"

let s_4 = Base.text_of_utf8 "Wasm byte plan length differs from its chunks"

let s_5 = Base.text_of_utf8 "response exceeds 16M words"

let rec (* native_output.bend:19 *)
f_finish_leaf : int -> int32 -> int32 -> (int32) list -> t_Packed =
fun v_count v_word v_shift v_reversed ->
(match v_shift with
| 0x00000000l ->
(Packed (v_count, [(Block (v_count, (Base.list_reverse (v_reversed))))]))
| _ ->
(Packed (v_count, [(Block (v_count, (Base.list_reverse ((v_word :: v_reversed)))))])))
and (* native_output.bend:26 *)
f_pack_leaf : int -> ((int32) list) list -> (int32) list -> int32 -> int32 -> int -> (int32) list -> bool -> (M.t_Diagnostic, t_Packed) Base.result_ =
fun v_fuel v_chunks v_bytes v_word v_shift v_count v_reversed v_valid ->
(match (v_fuel, v_chunks, v_bytes, v_shift, v_valid) with
| (_, _, _, _, false) ->
(Fail ((M.Diagnostic (s_0, s_1, s_2))))
| (_, [], [], _, true) ->
(Done ((f_finish_leaf (v_count) (v_word) (v_shift) (v_reversed))))
| (0, _, _, _, true) ->
(Fail ((R.f_protocol_error (s_3))))
| (__nat_1, (v_head :: v_tail), [], _, true) when __nat_1 >= 1 ->
(let v_rest = (__nat_1 - 1) in
(f_pack_leaf (v_rest) (v_tail) (v_head) (v_word) (v_shift) (v_count) (v_reversed) (true)))
| (__nat_2, v_pending, (v_byte :: v_tail), 0x00000018l, true) when __nat_2 >= 1 ->
(let v_rest = (__nat_2 - 1) in
(f_pack_leaf (v_rest) (v_pending) (v_tail) (0x00000000l) (0x00000000l) ((Base.nat_add 1 v_count)) (((Base.u32_or (v_word) ((Base.u32_shln (v_byte) (24)))) :: v_reversed)) ((Base.u32_is_le (v_byte) (0x000000ffl)))))
| (__nat_3, v_pending, (v_byte :: v_tail), v_bits, true) when __nat_3 >= 1 ->
(let v_rest = (__nat_3 - 1) in
(f_pack_leaf (v_rest) (v_pending) (v_tail) ((Base.u32_or (v_word) ((Base.u32_shln (v_byte) ((Base.u32_to_nat (v_bits))))))) ((Base.u32_add (v_bits) (0x00000008l))) ((Base.nat_add 1 v_count)) (v_reversed) ((Base.u32_is_le (v_byte) (0x000000ffl))))))
and (* native_output.bend:41 *)
f_merge : (M.t_Diagnostic, t_Packed) Base.result_ -> (M.t_Diagnostic, t_Packed) Base.result_ -> (M.t_Diagnostic, t_Packed) Base.result_ =
fun v_left v_right ->
(match (v_left, v_right) with
| ((Fail (v_error)), _) ->
(Fail (v_error))
| (_, (Fail (v_error))) ->
(Fail (v_error))
| ((Done ((Packed (v_a, v_xs)))), (Done ((Packed (v_b, v_ys))))) ->
(Done ((Packed ((Base.nat_add (v_a) (v_b)), (Base.list_append (v_xs) (v_ys)))))))
and (* native_output.bend:52 *)
f_finish_groups : ((int32) list) list -> int -> ((((int32) list) list) B.t_Weighted) list -> ((((int32) list) list) B.t_Weighted) list =
fun v_chunks v_cost v_reversed ->
(match v_chunks with
| [] ->
(Base.list_reverse (v_reversed))
| (v_head :: v_tail) ->
(Base.list_reverse (((B.Weighted ((Base.list_reverse ((v_head :: v_tail))), v_cost)) :: v_reversed))))
and (* native_output.bend:59 *)
f_group_chunks : ((int32) list) list -> int -> int -> ((int32) list) list -> ((((int32) list) list) B.t_Weighted) list -> ((((int32) list) list) B.t_Weighted) list =
fun v_chunks v_remaining v_grain v_reversed_chunks v_reversed_groups ->
(match (v_chunks, v_remaining) with
| ([], _) ->
(f_finish_groups (v_reversed_chunks) ((Base.nat_sub (v_grain) (v_remaining))) (v_reversed_groups))
| ((v_head :: v_tail), 0) ->
(f_group_chunks (v_tail) ((Base.nat_sub (v_grain) (1))) (v_grain) ([v_head]) (((B.Weighted ((Base.list_reverse (v_reversed_chunks)), v_grain)) :: v_reversed_groups)))
| ((v_head :: v_tail), __nat_4) when __nat_4 >= 1 ->
(let v_rest = (__nat_4 - 1) in
(f_group_chunks (v_tail) (v_rest) (v_grain) ((v_head :: v_reversed_chunks)) (v_reversed_groups))))
and (* native_output.bend:68 *)
f_pack_group : ((int32) list) list -> unit -> (M.t_Diagnostic, t_Packed) Base.result_ =
fun v_chunks v_context ->
(f_pack_leaf ((M.f_max_nat ())) (v_chunks) ([]) (0x00000000l) (0x00000000l) (0) ([]) (true))
and (* native_output.bend:71 *)
f_collect_groups : ((M.t_Diagnostic, t_Packed) Base.result_) list -> (M.t_Diagnostic, t_Packed) Base.result_ =
fun v_results ->
(match v_results with
| [] ->
(Done ((Packed (0, []))))
| (v_head :: v_tail) ->
(f_merge (v_head) ((f_collect_groups (v_tail)))))
and (* native_output.bend:78 *)
f_pack_chunks : ((int32) list) list -> int -> (M.t_Diagnostic, t_Packed) Base.result_ =
fun v_chunks v_grain ->
(let v_minimum = (Base.nat_max (1) (v_grain)) in
(let v_tasks = (f_group_chunks (v_chunks) (v_minimum) (v_minimum) ([]) ([])) in
(f_collect_groups ((B.f_execute (f_pack_group) ((B.f_plan (v_tasks) (v_minimum))) (()))))))
and (* native_output.bend:83 *)
f_matching_length : bool -> (M.t_Diagnostic, unit) Base.result_ =
fun v_same ->
(match v_same with
| false ->
(Fail ((M.Diagnostic (s_0, s_1, s_4))))
| true ->
(Done (())))
and (* native_output.bend:90 *)
f_room : bool -> (M.t_Diagnostic, unit) Base.result_ =
fun v_fits ->
(match v_fits with
| false ->
(Fail ((R.f_protocol_error (s_5))))
| true ->
(Done (())))
and (* native_output.bend:97 *)
f_checked_packet : (int32) list -> int -> t_Packed -> int -> (M.t_Diagnostic, t_Packet) Base.result_ =
fun v_header v_expected v_packed v_maximum ->
(let (Packed (v_length, v_blocks)) = v_packed in
(let v_words = (Base.nat_add ((Base.list_length (v_header))) ((Base.nat_div ((Base.nat_add (v_length) (3))) (4)))) in
(match (f_matching_length ((Base.nat_is_eq (v_expected) (v_length)))) with
| Fail __error -> Fail __error
| Done v_matched ->
(match (f_room ((Base.nat_is_le (v_words) (v_maximum)))) with
| Fail __error -> Fail __error
| Done v_bounded ->
(Done ((Packet ((Base.u32_from_nat (v_words)), v_header, v_blocks))))))))
and (* native_output.bend:105 *)
f_oversized : (M.t_Diagnostic, (int32) list) Base.result_ -> (M.t_Diagnostic, t_Packet) Base.result_ =
fun v_result ->
(match v_result with
| (Fail (v_error)) ->
(Fail (v_error))
| (Done (v_words)) ->
(Fail ((M.Diagnostic (s_0, s_1, s_4)))))
and (* native_output.bend:112 *)
f_encode_payload : (int32) list -> int -> ((int32) list) list -> int -> int -> int -> bool -> (M.t_Diagnostic, t_Packet) Base.result_ =
fun v_header v_length v_chunks v_maximum v_remaining v_grain v_fits ->
(match v_fits with
| false ->
(f_oversized ((R.f_encode_work ((M.f_max_nat ())) ([(R.ByteWords ((W.f_join (v_chunks))))]) (v_remaining) ([]))))
| true ->
(match (f_pack_chunks (v_chunks) (v_grain)) with
| Fail __error -> Fail __error
| Done v_packed ->
(f_checked_packet (v_header) (v_length) (v_packed) (v_maximum))))
and (* native_output.bend:123 *)
f_encode_plan : (R.t_Work) list -> W.t_BytePlan -> int -> int -> (M.t_Diagnostic, t_Packet) Base.result_ =
fun v_fields v_plan v_maximum v_grain ->
(let (W.BytePlan (v_length, v_chunks)) = v_plan in
(match (R.f_encode_work ((M.f_max_nat ())) ((Base.list_append (v_fields) ([(R.ByteLength (v_length))]))) (v_maximum) ([])) with
| Fail __error -> Fail __error
| Done v_header ->
(let v_remaining = (Base.nat_sub (v_maximum) ((Base.list_length (v_header)))) in
(f_encode_payload (v_header) (v_length) (v_chunks) (v_maximum) (v_remaining) (v_grain) ((Base.nat_is_le ((Base.nat_div ((Base.nat_add (v_length) (3))) (4))) (v_remaining)))))))
and (* native_output.bend:130 *)
f_words : (int32) list -> t_Packet =
fun v_header ->
(Packet ((Base.u32_from_nat ((Base.list_length (v_header)))), v_header, []))
and (* native_output.bend:133 *)
f_finish : (M.t_Diagnostic, t_Packet) Base.result_ -> t_Packet =
fun v_result ->
(match v_result with
| (Fail (v_diagnostic)) ->
(f_words ((R.f_encode_diagnostic (v_diagnostic))))
| (Done (v_packet)) ->
v_packet)
and (* native_output.bend:147 *)
f_artifact_fields : t_Contents -> Main.t_Analysis -> (R.t_Work) list =
fun v_contents v_analysis ->
(match v_contents with
| FullArtifact ->
[(R.Word (0x00000002l)); (R.Analysis (v_analysis))]
| WasmOnly ->
[(R.Word (0x00000005l))])
and (* native_output.bend:154 *)
f_encode_artifact : t_Contents -> (M.t_Diagnostic, Main.t_PlannedArtifact) Base.result_ -> t_Packet =
fun v_contents v_result ->
(match v_result with
| (Fail (v_diagnostic)) ->
(f_words ((R.f_encode_diagnostic (v_diagnostic))))
| (Done ((Main.PlannedArtifact (v_analysis, v_plan)))) ->
(f_finish ((f_encode_plan (((R.Word (0x424c4f54l)) :: ((R.Word ((R.f_version ()))) :: (f_artifact_fields (v_contents) (v_analysis))))) (v_plan) ((Base.u32_to_nat (0x01000000l))) (2048)))))
