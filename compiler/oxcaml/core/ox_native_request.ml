(* Native semantic port of compiler/native_request.bend.

   Source SHA-256: 62da0ead06c5edf07c813c1c9a955cf3a72de916694c33d498e1ea3cd486bebc

   Ownership/type arguments are erased; value types are checked by OCaml.

   No Bend interpreter or generated C/JavaScript is linked. *)

open Base

module M = Ox_model

module Cst = Ox_cst

module Session = Ox_native_session

module NativeIO = Ox_native_io

module Response = Ox_native_response

module Output = Ox_native_output

type t_Operation =
  | Analyze
  | Compile
  | EmitWasm
and t_Request =
  | Request of t_Operation * int * int * Cst.t_Cst * Cst.t_Cst
  | OpenSession of Cst.t_Cst * int
  | SessionRequest of t_Operation * int * int * Cst.t_Cst
  | SessionPatch of t_Operation * int * int * (Session.t_Declaration) list
and t_Cursor =
  | Cursor of bytes * int * int * (Base.text) array * int32
and 'a t_Parsed =
  | Parsed of 'a * t_Cursor
and t_ScanFailure =
  | MissingWord of int * Base.text
  | Rejected of int * Base.text
and t_ScannedString =
  | CompleteString of Base.text * t_Cursor
  | TruncatedString of int
  | InvalidCharacter of int
and t_CharacterScan =
  | CharacterScan of t_Cursor * Base.text * bool
and t_Header =
  | Header of Base.text * Base.text * Base.text * int * int
and t_Parent =
  | Parent of Base.text * Base.text * Base.text * int * int * (Cst.t_Cst) list
and t_TreeWork =
  | ReadNode of (t_ScanFailure, (t_Header) t_Parsed) Base.result_ * (t_Parent) list
  | FinishNode of Cst.t_Cst * (t_Parent) list * t_Cursor

let s_0 = Base.text_of_utf8 "native_protocol"

let s_1 = Base.text_of_utf8 "word:"

let s_2 = Base.text_of_utf8 "truncated request while reading "

let s_3 = Base.text_of_utf8 "Nat high word exceeds 16 bits"

let s_4 = Base.text_of_utf8 " low word"

let s_5 = Base.text_of_utf8 " high word"

let s_6 = Base.text_of_utf8 "string contains an invalid Unicode scalar value"

let s_7 = Base.text_of_utf8 "CST string ID is outside the request dictionary"

let s_8 = Base.text_of_utf8 "CST child count"

let s_9 = Base.text_of_utf8 "CST offset low word"

let s_10 = Base.text_of_utf8 "CST offset high word"

let s_11 = Base.text_of_utf8 "CST text ID"

let s_12 = Base.text_of_utf8 "CST field ID"

let s_13 = Base.text_of_utf8 "CST kind ID"

let s_14 = Base.text_of_utf8 "CST traversal exceeded its request word-count bound"

let s_15 = Base.text_of_utf8 "trailing words after the request CST"

let s_16 = Base.text_of_utf8 "dictionary string length"

let s_17 = Base.text_of_utf8 "dictionary string character"

let s_18 = Base.text_of_utf8 "dictionary count exceeds remaining request words"

let s_19 = Base.text_of_utf8 "dictionary count"

let s_20 = Base.text_of_utf8 "frontend fuel"

let s_21 = Base.text_of_utf8 "const steps"

let s_22 = Base.text_of_utf8 "retained declaration identity"

let s_23 = Base.text_of_utf8 "unknown declaration tag; expected 0 retained or 1 replaced"

let s_24 = Base.text_of_utf8 "declaration tag"

let s_25 = Base.text_of_utf8 "declaration count"

let s_26 = Base.text_of_utf8 "prelude fuel"

let s_27 = Base.text_of_utf8 "unknown operation; expected 0..9"

let s_28 = Base.text_of_utf8 "protocol magic"

let s_29 = Base.text_of_utf8 "invalid protocol magic; expected BLOT"

let s_30 = Base.text_of_utf8 "protocol version"

let s_31 = Base.text_of_utf8 "unsupported native protocol version; expected "

let s_32 = Base.text_of_utf8 "operation"

let rec (* native_request.bend:35 *)
f_diagnostic : int -> Base.text -> M.t_Diagnostic =
fun v_offset v_message ->
(M.Diagnostic (s_0, (Base.string_append s_1 (Base.nat_show (v_offset))), v_message))
and (* native_request.bend:38 *)
f_scan_failure : t_ScanFailure -> M.t_Diagnostic =
fun v_failure ->
(match v_failure with
| (MissingWord (v_offset, v_label)) ->
(f_diagnostic (v_offset) ((Base.string_append s_2 v_label)))
| (Rejected (v_offset, v_message)) ->
(f_diagnostic (v_offset) (v_message)))
and (* native_request.bend:45 *)
f_word_read : (bytes * int32) -> int -> int -> (Base.text) array -> int32 -> (t_ScanFailure, (int32) t_Parsed) Base.result_ =
fun v_read v_offset v_remaining v_strings v_string_count ->
(let (v_words, v_value) = v_read in
(Done ((Parsed (v_value, (Cursor (v_words, v_offset, v_remaining, v_strings, v_string_count)))))))
and (* native_request.bend:49 *)
f_word : t_Cursor -> Base.text -> (t_ScanFailure, int32 t_Parsed) Base.result_ =
fun cursor label ->
  match cursor with
  | Cursor (_, offset, 0, _, _) -> Fail (MissingWord (offset, label))
  | Cursor (words, offset, remaining, strings, string_count) ->
    let value = Bytes.get_int32_le words (offset * 4) in
    Done (Parsed (value, Cursor (words, offset + 1, remaining - 1, strings, string_count)))
and (* native_request.bend:56 *)
f_natural_checked : bool -> int32 -> int32 -> t_Cursor -> int -> (t_ScanFailure, (int) t_Parsed) Base.result_ =
fun v_valid v_low v_high v_cursor v_offset ->
(match v_valid with
| false ->
(Fail ((Rejected (v_offset, s_3))))
| true ->
(Done ((Parsed ((Base.nat_add ((Base.u32_to_nat (v_low))) ((Base.nat_mul ((Base.u32_to_nat (v_high))) ((Base.nat_mul ((Base.u32_to_nat (0x00010000l))) ((Base.u32_to_nat (0x00010000l)))))))), v_cursor)))))
and (* native_request.bend:63 *)
f_natural_high : (t_ScanFailure, (int32) t_Parsed) Base.result_ -> int32 -> int -> (t_ScanFailure, (int) t_Parsed) Base.result_ =
fun v_parsed v_low v_offset ->
(match v_parsed with
| (Fail (v_error)) ->
(Fail (v_error))
| (Done ((Parsed (v_high, v_cursor)))) ->
(f_natural_checked ((Base.u32_is_le (v_high) (0x0000ffffl))) (v_low) (v_high) (v_cursor) (v_offset)))
and (* native_request.bend:70 *)
f_natural_low : (t_ScanFailure, (int32) t_Parsed) Base.result_ -> Base.text -> int -> (t_ScanFailure, (int) t_Parsed) Base.result_ =
fun v_parsed v_label v_offset ->
(match v_parsed with
| (Fail (v_error)) ->
(Fail (v_error))
| (Done ((Parsed (v_low, v_cursor)))) ->
(f_natural_high ((f_word (v_cursor) (v_label))) (v_low) (v_offset)))
and (* native_request.bend:77 *)
f_natural_words : t_Cursor -> Base.text -> Base.text -> (t_ScanFailure, (int) t_Parsed) Base.result_ =
fun v_cursor v_low_label v_high_label ->
(let (Cursor (v_words, v_offset, v_remaining, v_strings, v_string_count)) = v_cursor in
(f_natural_low ((f_word ((Cursor (v_words, v_offset, v_remaining, v_strings, v_string_count))) (v_low_label))) (v_high_label) ((Base.nat_add 1 v_offset))))
and (* native_request.bend:81 *)
f_natural : t_Cursor -> Base.text -> (t_ScanFailure, (int) t_Parsed) Base.result_ =
fun v_cursor v_label ->
(f_natural_words (v_cursor) ((Base.string_append v_label s_4)) ((Base.string_append v_label s_5)))
and (* native_request.bend:94 *)
f_character_read : (bytes * int32) -> int -> int -> Base.text -> (Base.text) array -> int32 -> t_CharacterScan =
fun v_read v_offset v_remaining v_reversed v_strings v_string_count ->
(let (v_words, v_code) = v_read in
(CharacterScan ((Cursor (v_words, v_offset, v_remaining, v_strings, v_string_count)), (SCon ((Base.char_of_u32 (v_code)), v_reversed)), (Base.bool_and ((Base.u32_is_le (v_code) (0x0010ffffl))) ((Base.bool_or ((Base.u32_is_lt (v_code) (0x0000d800l))) ((Base.u32_is_gt (v_code) (0x0000dfffl)))))))))
and (* native_request.bend:98 *)
f_scan_characters : int -> t_CharacterScan -> t_ScannedString =
fun v_count v_scan ->
(match (v_count, v_scan) with
| (_, (CharacterScan ((Cursor (v_words, v_offset, v_remaining, v_strings, v_string_count)), v_reversed, false))) ->
(InvalidCharacter ((Base.nat_sub (v_offset) (1))))
| (0, (CharacterScan (v_remaining, v_reversed, true))) ->
(CompleteString ((Base.string_reverse (v_reversed)), v_remaining))
| (__nat_2, (CharacterScan ((Cursor (v_words, v_offset, 0, v_strings, v_string_count)), v_reversed, true))) when __nat_2 >= 1 ->
(let v_rest = (__nat_2 - 1) in
(TruncatedString (v_offset)))
| (__nat_3, (CharacterScan ((Cursor (v_words, v_offset, __nat_4, v_strings, v_string_count)), v_reversed, true))) when __nat_3 >= 1 && __nat_4 >= 1 ->
(let v_rest = (__nat_3 - 1) in
(let v_remaining = (__nat_4 - 1) in
(f_scan_characters (v_rest) ((f_character_read ((v_words, Bytes.get_int32_le v_words (4 * v_offset))) ((Base.nat_add 1 v_offset)) (v_remaining) (v_reversed) (v_strings) (v_string_count)))))))
and (* native_request.bend:109 *)
(* Packed frame bytes are immutable after receive. Validate in source order
   before constructing text backwards, preserving first-invalid/truncated
   diagnostics without allocating a cursor and reversed string per character.
   No frame storage escapes into the published syntax or incremental session. *)
f_scan_string : int -> t_Cursor -> Base.text -> bool -> t_ScannedString =
fun count cursor reversed valid ->
  let Cursor (words, offset, remaining, strings, string_count) = cursor in
  if not valid then InvalidCharacter (max 0 (offset - 1))
  else begin
    let available = min count remaining in
    let rec validate index =
      if index = available then
        if count > remaining then TruncatedString (offset + available)
        else begin
          let value = ref SNil in
          for i = count - 1 downto 0 do
            value := SCon (Base.char_of_u32 (Bytes.get_int32_le words ((offset + i) * 4)), !value)
          done;
          let value = match reversed with
            | SNil -> !value
            | _ -> Base.string_append (Base.string_reverse reversed) !value
          in
          CompleteString (value,
            Cursor (words, offset + count, remaining - count, strings, string_count))
        end
      else
        let code = Base.u32_to_nat (Bytes.get_int32_le words ((offset + index) * 4)) in
        if code > 0x10ffff || (code >= 0xd800 && code <= 0xdfff)
        then InvalidCharacter (offset + index)
        else validate (index + 1)
    in
    validate 0
  end
and (* native_request.bend:112 *)
f_scanned_string : t_ScannedString -> Base.text -> (t_ScanFailure, (Base.text) t_Parsed) Base.result_ =
fun v_scanned v_label ->
(match v_scanned with
| (CompleteString (v_value, v_cursor)) ->
(Done ((Parsed (v_value, v_cursor))))
| (TruncatedString (v_offset)) ->
(Fail ((MissingWord (v_offset, v_label))))
| (InvalidCharacter (v_offset)) ->
(Fail ((Rejected (v_offset, s_6)))))
and (* native_request.bend:121 *)
f_field_length : (t_ScanFailure, (int32) t_Parsed) Base.result_ -> Base.text -> (t_ScanFailure, (Base.text) t_Parsed) Base.result_ =
fun v_parsed v_character_label ->
(match v_parsed with
| (Fail (v_error)) ->
(Fail (v_error))
| (Done ((Parsed (v_count, v_cursor)))) ->
(f_scanned_string ((f_scan_string ((Base.u32_to_nat (v_count))) (v_cursor) (SNil) (true))) (v_character_label)))
and (* native_request.bend:128 *)
f_scan_field : t_Cursor -> Base.text -> Base.text -> (t_ScanFailure, (Base.text) t_Parsed) Base.result_ =
fun v_cursor v_length_label v_character_label ->
(f_field_length ((f_word (v_cursor) (v_length_label))) (v_character_label))
and (* native_request.bend:131 *)
f_string_read : ((Base.text) array * Base.text) -> bytes -> int -> int -> int32 -> (t_ScanFailure, (Base.text) t_Parsed) Base.result_ =
fun v_read v_words v_offset v_remaining v_string_count ->
(let (v_strings, v_value) = v_read in
(Done ((Parsed (v_value, (Cursor (v_words, v_offset, v_remaining, v_strings, v_string_count)))))))
and (* native_request.bend:135 *)
f_string_checked : bool -> int32 -> t_Cursor -> (t_ScanFailure, (Base.text) t_Parsed) Base.result_ =
fun v_valid v_identity v_cursor ->
(match (v_valid, v_cursor) with
| (false, (Cursor (v_words, v_offset, v_remaining, v_strings, v_string_count))) ->
(Fail ((Rejected ((Base.nat_sub (v_offset) (1)), s_7))))
| (true, (Cursor (v_words, v_offset, v_remaining, v_strings, v_string_count))) ->
(f_string_read ((Base.array_get (v_strings) (v_identity))) (v_words) (v_offset) (v_remaining) (v_string_count)))
and (* native_request.bend:142 *)
f_string_identity : (t_ScanFailure, (int32) t_Parsed) Base.result_ -> (t_ScanFailure, (Base.text) t_Parsed) Base.result_ =
fun v_parsed ->
(match v_parsed with
| (Fail (v_error)) ->
(Fail (v_error))
| (Done ((Parsed (v_identity, (Cursor (v_words, v_offset, v_remaining, v_strings, v_string_count)))))) ->
(f_string_checked ((Base.u32_is_lt (v_identity) (v_string_count))) (v_identity) ((Cursor (v_words, v_offset, v_remaining, v_strings, v_string_count)))))
and (* native_request.bend:149 *)
f_string_reference : t_Cursor -> Base.text -> (t_ScanFailure, (Base.text) t_Parsed) Base.result_ =
fun v_cursor v_label ->
(f_string_identity ((f_word (v_cursor) (v_label))))
and (* native_request.bend:155 *)
f_header_children : (t_ScanFailure, (int32) t_Parsed) Base.result_ -> Base.text -> Base.text -> Base.text -> int -> (t_ScanFailure, (t_Header) t_Parsed) Base.result_ =
fun v_parsed v_kind v_field v_text v_offset ->
(match v_parsed with
| (Fail (v_error)) ->
(Fail (v_error))
| (Done ((Parsed (v_children, v_cursor)))) ->
(Done ((Parsed ((Header (v_kind, v_field, v_text, v_offset, (Base.u32_to_nat (v_children)))), v_cursor)))))
and (* native_request.bend:162 *)
f_header_offset : (t_ScanFailure, (int) t_Parsed) Base.result_ -> Base.text -> Base.text -> Base.text -> (t_ScanFailure, (t_Header) t_Parsed) Base.result_ =
fun v_parsed v_kind v_field v_text ->
(match v_parsed with
| (Fail (v_error)) ->
(Fail (v_error))
| (Done ((Parsed (v_offset, v_cursor)))) ->
(f_header_children ((f_word (v_cursor) (s_8))) (v_kind) (v_field) (v_text) (v_offset)))
and (* native_request.bend:169 *)
f_header_text : (t_ScanFailure, (Base.text) t_Parsed) Base.result_ -> Base.text -> Base.text -> (t_ScanFailure, (t_Header) t_Parsed) Base.result_ =
fun v_parsed v_kind v_field ->
(match v_parsed with
| (Fail (v_error)) ->
(Fail (v_error))
| (Done ((Parsed (v_text, v_cursor)))) ->
(f_header_offset ((f_natural_words (v_cursor) (s_9) (s_10))) (v_kind) (v_field) (v_text)))
and (* native_request.bend:176 *)
f_header_field : (t_ScanFailure, (Base.text) t_Parsed) Base.result_ -> Base.text -> (t_ScanFailure, (t_Header) t_Parsed) Base.result_ =
fun v_parsed v_kind ->
(match v_parsed with
| (Fail (v_error)) ->
(Fail (v_error))
| (Done ((Parsed (v_field, v_cursor)))) ->
(f_header_text ((f_string_reference (v_cursor) (s_11))) (v_kind) (v_field)))
and (* native_request.bend:183 *)
f_header_kind : (t_ScanFailure, (Base.text) t_Parsed) Base.result_ -> (t_ScanFailure, (t_Header) t_Parsed) Base.result_ =
fun v_parsed ->
(match v_parsed with
| (Fail (v_error)) ->
(Fail (v_error))
| (Done ((Parsed (v_kind, v_cursor)))) ->
(f_header_field ((f_string_reference (v_cursor) (s_12))) (v_kind)))
and (* native_request.bend:190 *)
f_scan_header : t_Cursor -> (t_ScanFailure, (t_Header) t_Parsed) Base.result_ =
fun v_cursor ->
(f_header_kind ((f_string_reference (v_cursor) (s_13))))
and (* native_request.bend:200 *)
f_begin_node : t_Header -> (t_Parent) list -> t_Cursor -> t_TreeWork =
fun v_header v_parents v_cursor ->
(match v_header with
| (Header (v_kind, v_field, v_text, v_offset, 0)) ->
(FinishNode ((Cst.Cst (v_kind, v_field, v_text, v_offset, [])), v_parents, v_cursor))
| (Header (v_kind, v_field, v_text, v_offset, __nat_5)) when __nat_5 >= 1 ->
(let v_remaining = (__nat_5 - 1) in
(ReadNode ((f_scan_header (v_cursor)), ((Parent (v_kind, v_field, v_text, v_offset, v_remaining, [])) :: v_parents)))))
and (* native_request.bend:208 *)
f_scan_tree : int -> t_TreeWork -> (t_ScanFailure, (Cst.t_Cst) t_Parsed) Base.result_ =
fun v_fuel v_work ->
(match (v_fuel, v_work) with
| (_, (FinishNode (v_node, [], v_cursor))) ->
(Done ((Parsed (v_node, v_cursor))))
| (_, (ReadNode ((Fail (v_error)), v_parents))) ->
(Fail (v_error))
| (0, (ReadNode ((Done ((Parsed (v_header, (Cursor (v_words, v_position, v_remaining, v_strings, v_string_count)))))), v_parents))) ->
(Fail ((Rejected (v_position, s_14))))
| (0, (FinishNode (v_node, v_parents, (Cursor (v_words, v_position, v_remaining, v_strings, v_string_count))))) ->
(Fail ((Rejected (v_position, s_14))))
| (__nat_6, (ReadNode ((Done ((Parsed (v_header, v_cursor)))), v_parents))) when __nat_6 >= 1 ->
(let v_rest = (__nat_6 - 1) in
(f_scan_tree (v_rest) ((f_begin_node (v_header) (v_parents) (v_cursor)))))
| (__nat_7, (FinishNode (v_node, ((Parent (v_kind, v_field, v_text, v_offset, 0, v_reversed)) :: v_parents), v_cursor))) when __nat_7 >= 1 ->
(let v_rest = (__nat_7 - 1) in
(f_scan_tree (v_rest) ((FinishNode ((Cst.Cst (v_kind, v_field, v_text, v_offset, (Base.list_reverse ((v_node :: v_reversed))))), v_parents, v_cursor)))))
| (__nat_8, (FinishNode (v_node, ((Parent (v_kind, v_field, v_text, v_offset, __nat_9, v_reversed)) :: v_parents), v_cursor))) when __nat_8 >= 1 && __nat_9 >= 1 ->
(let v_rest = (__nat_8 - 1) in
(let v_remaining = (__nat_9 - 1) in
(f_scan_tree (v_rest) ((ReadNode ((f_scan_header (v_cursor)), ((Parent (v_kind, v_field, v_text, v_offset, v_remaining, (v_node :: v_reversed))) :: v_parents))))))))
and (* native_request.bend:225 *)
f_tree : int -> t_Cursor -> (t_ScanFailure, (Cst.t_Cst) t_Parsed) Base.result_ =
fun v_fuel v_cursor ->
(f_scan_tree (v_fuel) ((ReadNode ((f_scan_header (v_cursor)), []))))
and (* native_request.bend:228 *)
f_end : t_Cursor -> (t_ScanFailure, unit) Base.result_ =
fun v_cursor ->
(match v_cursor with
| (Cursor (v_words, v_offset, 0, v_strings, v_string_count)) ->
(Done (()))
| (Cursor (v_words, v_offset, __nat_10, v_strings, v_string_count)) when __nat_10 >= 1 ->
(let v_remaining = (__nat_10 - 1) in
(Fail ((Rejected (v_offset, s_15))))))
and (* native_request.bend:235 *)
f_bind : 'a 'b. (t_ScanFailure, ('a) t_Parsed) Base.result_ -> ('a -> (t_Cursor -> (t_ScanFailure, 'b) Base.result_)) -> (t_ScanFailure, 'b) Base.result_ =
fun v_parsed v_next ->
(match v_parsed with
| (Fail (v_error)) ->
(Fail (v_error))
| (Done ((Parsed (v_value, v_cursor)))) ->
(v_next (v_value) (v_cursor)))
and (* native_request.bend:242 *)
f_dictionary_depth : int -> int32 -> int -> int =
fun v_fuel v_count v_depth ->
(match (v_fuel, v_count) with
| (_, 0x00000000l) ->
v_depth
| (_, 0x00000001l) ->
v_depth
| (0, _) ->
v_depth
| (__nat_11, v_more) when __nat_11 >= 1 ->
(let v_rest = (__nat_11 - 1) in
(f_dictionary_depth (v_rest) ((Base.u32_shr ((Base.u32_add (v_more) (0x00000001l))))) ((Base.nat_add 1 v_depth)))))
and (* native_request.bend:253 *)
f_dictionary_store : int32 -> Base.text -> t_Cursor -> t_Cursor =
fun v_index v_value v_cursor ->
(let (Cursor (v_words, v_offset, v_remaining, v_strings, v_string_count)) = v_cursor in
(Cursor (v_words, v_offset, v_remaining, (Base.array_set (v_strings) (v_index) (v_value)), v_string_count)))
and (* native_request.bend:257 *)
f_dictionary_entries : int -> int32 -> t_Cursor -> (t_ScanFailure, (unit) t_Parsed) Base.result_ =
fun v_count v_index v_cursor ->
(match v_count with
| 0 ->
(Done ((Parsed ((), v_cursor))))
| __nat_12 when __nat_12 >= 1 ->
(let v_rest = (__nat_12 - 1) in
(f_bind ((f_scan_field (v_cursor) (s_16) (s_17))) ((fun v_value ->
(fun v_cursor ->
(f_dictionary_entries (v_rest) ((Base.u32_add (v_index) (0x00000001l))) ((f_dictionary_store (v_index) (v_value) (v_cursor))))))))))
and (* native_request.bend:265 *)
f_dictionary_checked : bool -> int32 -> t_Cursor -> (t_ScanFailure, (unit) t_Parsed) Base.result_ =
fun v_valid v_count v_cursor ->
(match (v_valid, v_cursor) with
| (false, (Cursor (v_words, v_offset, v_remaining, v_strings, v_string_count))) ->
(Fail ((Rejected ((Base.nat_sub (v_offset) (1)), s_18))))
| (true, (Cursor (v_words, v_offset, v_remaining, v_strings, v_string_count))) ->
(f_dictionary_entries ((Base.u32_to_nat (v_count))) (0x00000000l) ((Cursor (v_words, v_offset, v_remaining, (Base.array_new ((f_dictionary_depth (32) (v_count) (0))) (SNil)), v_count)))))
and (* native_request.bend:272 *)
f_dictionary_count : (t_ScanFailure, (int32) t_Parsed) Base.result_ -> (t_ScanFailure, (unit) t_Parsed) Base.result_ =
fun v_parsed ->
(match v_parsed with
| (Fail (v_error)) ->
(Fail (v_error))
| (Done ((Parsed (v_count, (Cursor (v_words, v_offset, v_remaining, v_strings, v_string_count)))))) ->
(f_dictionary_checked ((Base.nat_is_le ((Base.u32_to_nat (v_count))) (v_remaining))) (v_count) ((Cursor (v_words, v_offset, v_remaining, v_strings, v_string_count)))))
and (* native_request.bend:279 *)
f_dictionary : t_Cursor -> (t_ScanFailure, (unit) t_Parsed) Base.result_ =
fun v_cursor ->
(f_dictionary_count ((f_word (v_cursor) (s_19))))
and (* native_request.bend:282 *)
f_finish : (t_ScanFailure, unit) Base.result_ -> t_Request -> (t_ScanFailure, t_Request) Base.result_ =
fun v_complete v_request ->
(match v_complete with
| (Fail (v_error)) ->
(Fail (v_error))
| (Done (v_unit)) ->
(Done (v_request)))
and (* native_request.bend:289 *)
f_stateless : t_Operation -> int -> t_Cursor -> (t_ScanFailure, t_Request) Base.result_ =
fun v_selected v_bound v_cursor ->
(f_bind ((f_natural (v_cursor) (s_20))) ((fun v_fuel ->
(fun v_cursor ->
(f_bind ((f_natural (v_cursor) (s_21))) ((fun v_steps ->
(fun v_cursor ->
(f_bind ((f_dictionary (v_cursor))) ((fun v_unit ->
(fun v_cursor ->
(f_bind ((f_tree (v_bound) (v_cursor))) ((fun v_root ->
(fun v_cursor ->
(f_bind ((f_tree (v_bound) (v_cursor))) ((fun v_prelude ->
(fun v_cursor ->
(f_finish ((f_end (v_cursor))) ((Request (v_selected, v_fuel, v_steps, v_root, v_prelude))))))))))))))))))))))))
and (* native_request.bend:297 *)
f_cached : t_Operation -> int -> t_Cursor -> (t_ScanFailure, t_Request) Base.result_ =
fun v_selected v_bound v_cursor ->
(f_bind ((f_natural (v_cursor) (s_20))) ((fun v_fuel ->
(fun v_cursor ->
(f_bind ((f_natural (v_cursor) (s_21))) ((fun v_steps ->
(fun v_cursor ->
(f_bind ((f_dictionary (v_cursor))) ((fun v_unit ->
(fun v_cursor ->
(f_bind ((f_tree (v_bound) (v_cursor))) ((fun v_root ->
(fun v_cursor ->
(f_finish ((f_end (v_cursor))) ((SessionRequest (v_selected, v_fuel, v_steps, v_root))))))))))))))))))))
and (* native_request.bend:304 *)
f_declaration : int32 -> int -> t_Cursor -> int -> (t_ScanFailure, (Session.t_Declaration) t_Parsed) Base.result_ =
fun v_tag v_bound v_cursor v_offset ->
(match v_tag with
| 0x00000000l ->
(f_bind ((f_natural (v_cursor) (s_22))) ((fun v_identity ->
(fun v_cursor ->
(Done ((Parsed ((Session.Retained (v_identity)), v_cursor))))))))
| 0x00000001l ->
(f_bind ((f_tree (v_bound) (v_cursor))) ((fun v_node ->
(fun v_cursor ->
(Done ((Parsed ((Session.Replaced (v_node)), v_cursor))))))))
| v_other ->
(Fail ((Rejected (v_offset, s_23)))))
and (* native_request.bend:313 *)
f_declarations : int -> int -> t_Cursor -> (Session.t_Declaration) list -> (t_ScanFailure, ((Session.t_Declaration) list) t_Parsed) Base.result_ =
fun v_count v_bound v_cursor v_reversed ->
(match v_count with
| 0 ->
(Done ((Parsed ((Base.list_reverse (v_reversed)), v_cursor))))
| __nat_13 when __nat_13 >= 1 ->
(let v_rest = (__nat_13 - 1) in
(let (Cursor (v_words, v_offset, v_remaining, v_strings, v_string_count)) = v_cursor in
(f_bind ((f_word ((Cursor (v_words, v_offset, v_remaining, v_strings, v_string_count))) (s_24))) ((fun v_tag ->
(fun v_cursor ->
(f_bind ((f_declaration (v_tag) (v_bound) (v_cursor) (v_offset))) ((fun v_value ->
(fun v_cursor ->
(f_declarations (v_rest) (v_bound) (v_cursor) ((v_value :: v_reversed))))))))))))))
and (* native_request.bend:323 *)
f_patch : t_Operation -> int -> t_Cursor -> (t_ScanFailure, t_Request) Base.result_ =
fun v_selected v_bound v_cursor ->
(f_bind ((f_natural (v_cursor) (s_20))) ((fun v_fuel ->
(fun v_cursor ->
(f_bind ((f_natural (v_cursor) (s_21))) ((fun v_steps ->
(fun v_cursor ->
(f_bind ((f_dictionary (v_cursor))) ((fun v_unit ->
(fun v_cursor ->
(f_bind ((f_word (v_cursor) (s_25))) ((fun v_count ->
(fun v_cursor ->
(f_bind ((f_declarations ((Base.u32_to_nat (v_count))) (v_bound) (v_cursor) ([]))) ((fun v_values ->
(fun v_cursor ->
(f_finish ((f_end (v_cursor))) ((SessionPatch (v_selected, v_fuel, v_steps, v_values))))))))))))))))))))))))
and (* native_request.bend:331 *)
f_body : int32 -> int -> t_Cursor -> (t_ScanFailure, t_Request) Base.result_ =
fun v_opcode v_bound v_cursor ->
(match v_opcode with
| 0x00000000l ->
(f_stateless (Analyze) (v_bound) (v_cursor))
| 0x00000001l ->
(f_stateless (Compile) (v_bound) (v_cursor))
| 0x00000002l ->
(f_bind ((f_natural (v_cursor) (s_26))) ((fun v_fuel ->
(fun v_cursor ->
(f_bind ((f_dictionary (v_cursor))) ((fun v_unit ->
(fun v_cursor ->
(f_bind ((f_tree (v_bound) (v_cursor))) ((fun v_prelude ->
(fun v_cursor ->
(f_finish ((f_end (v_cursor))) ((OpenSession (v_prelude, v_fuel))))))))))))))))
| 0x00000003l ->
(f_cached (Analyze) (v_bound) (v_cursor))
| 0x00000004l ->
(f_cached (Compile) (v_bound) (v_cursor))
| 0x00000005l ->
(f_patch (Analyze) (v_bound) (v_cursor))
| 0x00000006l ->
(f_patch (Compile) (v_bound) (v_cursor))
| 0x00000007l ->
(f_stateless (EmitWasm) (v_bound) (v_cursor))
| 0x00000008l ->
(f_cached (EmitWasm) (v_bound) (v_cursor))
| 0x00000009l ->
(f_patch (EmitWasm) (v_bound) (v_cursor))
| v_other ->
(Fail ((Rejected (2, s_27)))))
and (* native_request.bend:361 *)
f_mode : t_Operation -> Session.t_Mode =
fun v_operation ->
(match v_operation with
| Analyze ->
Session.AnalyzeMode
| Compile ->
Session.CompileMode
| EmitWasm ->
Session.CompileMode)
and (* native_request.bend:370 *)
f_contents : t_Operation -> Output.t_Contents =
fun v_operation ->
(match v_operation with
| Analyze ->
Output.FullArtifact
| Compile ->
Output.FullArtifact
| EmitWasm ->
Output.WasmOnly)
and (* native_request.bend:379 *)
f_expected_word : bool -> t_Cursor -> int -> Base.text -> (t_ScanFailure, (unit) t_Parsed) Base.result_ =
fun v_valid v_cursor v_offset v_message ->
(match v_valid with
| false ->
(Fail ((Rejected (v_offset, v_message))))
| true ->
(Done ((Parsed ((), v_cursor)))))
and (* native_request.bend:386 *)
f_expect : (t_ScanFailure, (int32) t_Parsed) Base.result_ -> int32 -> int -> Base.text -> (t_ScanFailure, (unit) t_Parsed) Base.result_ =
fun v_parsed v_expected v_offset v_message ->
(match v_parsed with
| (Fail (v_error)) ->
(Fail (v_error))
| (Done ((Parsed (v_value, v_cursor)))) ->
(f_expected_word ((Base.u32_is_eq (v_value) (v_expected))) (v_cursor) (v_offset) (v_message)))
and (* native_request.bend:393 *)
f_decode_frame : NativeIO.t_Frame -> (t_ScanFailure, t_Request) Base.result_ =
fun v_frame ->
(let (NativeIO.Frame (v_words, v_length)) = v_frame in
(let v_bound = (Base.u32_to_nat (v_length)) in
(f_bind ((f_expect ((f_word ((Cursor (v_words, 0, v_bound, (Stdlib.Array.make 1 SNil), 0x00000000l))) (s_28))) (0x424c4f54l) (0) (s_29))) ((fun v_unit ->
(fun v_cursor ->
(f_bind ((f_expect ((f_word (v_cursor) (s_30))) ((Response.f_version ())) (1) ((Base.string_append s_31 (Base.u32_show ((Response.f_version ()))))))) ((fun v_unit ->
(fun v_cursor ->
(f_bind ((f_word (v_cursor) (s_32))) ((fun v_opcode ->
(fun v_cursor ->
(f_body (v_opcode) (v_bound) (v_cursor))))))))))))))))
and (* native_request.bend:400 *)
f_decoded : (t_ScanFailure, t_Request) Base.result_ -> (M.t_Diagnostic, t_Request) Base.result_ =
fun v_result ->
(match v_result with
| (Fail (v_error)) ->
(Fail ((f_scan_failure (v_error))))
| (Done (v_request)) ->
(Done (v_request)))
and (* native_request.bend:407 *)
f_decode : NativeIO.t_Frame -> (M.t_Diagnostic, t_Request) Base.result_ =
fun v_frame ->
(f_decoded ((f_decode_frame (v_frame))))
