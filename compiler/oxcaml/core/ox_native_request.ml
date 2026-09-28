(* Native version-13 decoder. The cursor and dictionary are private to one
   request; only immutable CSTs escape. No per-word ownership/result wrappers
   and no array of boxed U32 values are needed on this linear boundary.

   Validation order and word offsets match compiler/native_request.bend.
   In particular a bad scalar before EOF wins over a later truncation. *)
open Base
module M = Ox_model
module Cst = Ox_cst
module Session = Ox_native_session
module NativeIO = Ox_native_io
module Response = Ox_native_response
module Output = Ox_native_output

type t_Operation = Analyze | Compile | EmitWasm
type t_Request =
  | Request of t_Operation * int * int * Cst.t_Cst * Cst.t_Cst
  | OpenSession of Cst.t_Cst * int
  | SessionRequest of t_Operation * int * int * Cst.t_Cst
  | SessionPatch of t_Operation * int * int * Session.t_Declaration list

type cursor = {
  bytes : bytes;
  bound : int;
  mutable position : int;
  mutable strings : Base.text array;
}
exception Scan_failure of int * string
let reject offset message = raise_notrace (Scan_failure (offset, message))
let missing offset label = reject offset ("truncated request while reading " ^ label)

(* This compiler already requires native 63-bit ints for its Nat48 domain. *)
let[@inline always] unsigned_word bytes index =
  Int32.to_int (Bytes.get_int32_le bytes (index * 4)) land 0xffff_ffff
let word cursor label =
  let position = cursor.position in
  if position = cursor.bound then missing position label;
  let value = unsigned_word cursor.bytes position in
  cursor.position <- position + 1;
  value
let natural_words cursor low_label high_label =
  let low = word cursor low_label in
  let position = cursor.position in
  let high = word cursor high_label in
  if high > 0xffff then reject position "Nat high word exceeds 16 bits";
  low lor (high lsl 32)
let natural cursor label =
  natural_words cursor (label ^ " low word") (label ^ " high word")

let dictionary cursor =
  let count = word cursor "dictionary count" in
  if count > cursor.bound - cursor.position then
    reject (cursor.position - 1) "dictionary count exceeds remaining request words";
  let strings = Array.make count SNil in
  for index = 0 to count - 1 do
    let length = word cursor "dictionary string length" in
    let start = cursor.position in
    (* Validate forward before building backward. Do not reject a short frame
       until its available prefix has been checked for invalid characters. *)
    let available = min length (cursor.bound - start) in
    for offset = start to start + available - 1 do
      let code = unsigned_word cursor.bytes offset in
      if code > 0x10ffff || (code >= 0xd800 && code <= 0xdfff) then
        reject offset "string contains an invalid Unicode scalar value"
    done;
    if available <> length then missing cursor.bound "dictionary string character";
    let value = ref SNil in
    for offset = start + length - 1 downto start do
      value := SCon (Chr (Bytes.get_int32_le cursor.bytes (offset * 4)), !value)
    done;
    strings.(index) <- !value;
    cursor.position <- start + length
  done;
  cursor.strings <- strings

let string_reference cursor label =
  let identity = word cursor label in
  if identity >= Array.length cursor.strings then
    reject (cursor.position - 1) "CST string ID is outside the request dictionary";
  cursor.strings.(identity)

type parent = {
  kind : Base.text;
  field : Base.text;
  text : Base.text;
  offset : int;
  remaining : int;
  reversed : Cst.t_Cst list;
}

let tree cursor =
  let exhausted () = reject cursor.position
    "CST traversal exceeded its request word-count bound" in
  (* Both loops are tail calls: adversarial nesting never uses the OCaml stack.
     Explicit lets preserve the protocol's left-to-right validation order. *)
  let rec read fuel parents =
    let kind = string_reference cursor "CST kind ID" in
    let field = string_reference cursor "CST field ID" in
    let text = string_reference cursor "CST text ID" in
    let offset = natural_words cursor "CST offset low word" "CST offset high word" in
    let children = word cursor "CST child count" in
    if fuel = 0 then exhausted ();
    if children = 0 then finish (fuel - 1) (Cst.Cst (kind,field,text,offset,[])) parents
    else read (fuel - 1)
      ({kind; field; text; offset; remaining = children - 1; reversed = []} :: parents)
  and finish fuel node = function
    | [] -> node
    | parent :: rest ->
      if fuel = 0 then exhausted ();
      let children = node :: parent.reversed in
      if parent.remaining = 0 then
        finish (fuel - 1)
          (Cst.Cst (parent.kind,parent.field,parent.text,parent.offset,List.rev children)) rest
      else read (fuel - 1)
        ({parent with remaining = parent.remaining - 1; reversed = children} :: rest)
  in read cursor.bound []

let declarations cursor =
  let count = word cursor "declaration count" in
  let rec loop remaining reversed =
    if remaining = 0 then List.rev reversed else
      let position = cursor.position in
      let tag = word cursor "declaration tag" in
      let declaration = match tag with
        | 0 -> let identity = natural cursor "retained declaration identity" in
          Session.Retained identity
        | 1 -> let node = tree cursor in Session.Replaced node
        | _ -> reject position "unknown declaration tag; expected 0 retained or 1 replaced"
      in loop (remaining - 1) (declaration :: reversed)
  in loop count []

let operation = function
  | 0 | 3 | 5 -> Analyze
  | 1 | 4 | 6 -> Compile
  | 7 | 8 | 9 -> EmitWasm
  | _ -> assert false
let f_mode = function Analyze -> Session.AnalyzeMode | Compile | EmitWasm -> Session.CompileMode
let f_contents = function Analyze | Compile -> Output.FullArtifact | EmitWasm -> Output.WasmOnly

let f_decode (NativeIO.Frame (bytes, length)) =
  let bound = Base.u32_to_nat length in
  (* Frames are created only by the bounded transport. Still reject inconsistent
     internal frames explicitly instead of relying on a bounds exception. *)
  if bound > 16777216 || Bytes.length bytes <> bound * 4 then
    invalid_arg "native frame length mismatch";
  let cursor = {bytes; bound; position = 0; strings = [||]} in
  try
    if word cursor "protocol magic" <> 0x424c4f54 then
      reject 0 "invalid protocol magic; expected BLOT";
    let version = Base.u32_to_nat (Response.f_version ()) in
    if word cursor "protocol version" <> version then
      reject 1 ("unsupported native protocol version; expected " ^ string_of_int version);
    let opcode = word cursor "operation" in
    if opcode > 9 then reject 2 "unknown operation; expected 0..9";
    let request =
      if opcode = 2 then begin
        let fuel = natural cursor "prelude fuel" in
        dictionary cursor;
        let prelude = tree cursor in
        OpenSession (prelude, fuel)
      end else begin
        let fuel = natural cursor "frontend fuel" in
        let steps = natural cursor "const steps" in
        dictionary cursor;
        let selected = operation opcode in
        match opcode with
        | 0 | 1 | 7 ->
          let root = tree cursor in
          let prelude = tree cursor in
          Request (selected, fuel, steps, root, prelude)
        | 3 | 4 | 8 ->
          let root = tree cursor in SessionRequest (selected, fuel, steps, root)
        | _ ->
          let values = declarations cursor in SessionPatch (selected, fuel, steps, values)
      end
    in
    if cursor.position <> bound then
      reject cursor.position "trailing words after the request CST";
    Done request
  with Scan_failure (offset, message) ->
    Fail (M.Diagnostic (Base.text_of_utf8 "native_protocol",
      Base.text_of_utf8 ("word:" ^ string_of_int offset), Base.text_of_utf8 message))
