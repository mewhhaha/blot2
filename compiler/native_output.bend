import Base
import ./model.bend as M
import ./wasm.bend as W
import ./main.bend as Main
import ./native_response.bend as R
import ./inference_batch.bend as B

# Each block packs independently. Only its final word may contain padding;
# the native writer concatenates the exact byte lengths before padding the frame.
type Block is Data:
  Block{length: Nat, words: List<&2, U32>}

type Packed is Data:
  Packed{length: Nat, blocks: List<&2, Block>}

type Packet is Data:
  Packet{word_count: U32, header: List<&2, U32>, blocks: List<&2, Block>}

def finish_leaf(+count: Nat, word: U32, shift: U32, reversed: List<&2, U32>) -> Packed:
  match shift:
    case 0:
      Packed{count, [Block{count, List.reverse(&2, U32, reversed)}]}
    case _:
      Packed{count, [Block{count, List.reverse(&2, U32, word <> reversed)}]}

def pack_leaf(fuel: Nat, chunks: List<&2, List<&2, U32>>, bytes: List<&2, U32>, word: U32, shift: U32, count: Nat, reversed: List<&2, U32>, valid: Bool) -> Result<&2, &2, M.Diagnostic, Packed>:
  match fuel chunks bytes shift valid:
    case _ _ _ _ False{}:
      Fail{M.Diagnostic{"internal_error", "wasm", "Wasm emitter produced a value outside byte range"}}
    case _ Nil{} Nil{} _ True{}:
      Done{finish_leaf(count, word, shift, reversed)}
    case 0n _ _ _ True{}:
      Fail{R.protocol_error("response traversal exceeded its bound")}
    case 1n+rest head <> tail Nil{} _ True{}:
      pack_leaf(rest, tail, head, word, shift, count, reversed, True{})
    case 1n+rest pending +byte <> tail 24 True{}:
      pack_leaf(rest, pending, tail, 0, 0, 1n+count, U32.or(word, U32.shln(byte, 24n)) <> reversed, U32.is_le(byte, 255))
    case 1n+rest pending +byte <> tail +bits True{}:
      pack_leaf(rest, pending, tail, U32.or(word, U32.shln(byte, U32.to_nat(bits))), U32.add(bits, 8), 1n+count, reversed, U32.is_le(byte, 255))

def merge(left: Result<&2, &2, M.Diagnostic, Packed>, right: Result<&2, &2, M.Diagnostic, Packed>) -> Result<&2, &2, M.Diagnostic, Packed>:
  match left right:
    case Fail{error} _:
      Fail{error}
    case _ Fail{error}:
      Fail{error}
    case Done{Packed{a, xs}} Done{Packed{b, ys}}:
      Done{Packed{Nat.add(a, b), List.append(&2, Block, xs, ys)}}

# Group the outer chunk list once, avoiding a count and repeated bisections of
# every tiny fragment. Only coarse groups enter the planner.
def finish_groups(chunks: List<&2, List<&2, U32>>, cost: Nat, reversed: List<&2, B.Weighted<List<&2, List<&2, U32>>>>) -> List<&2, B.Weighted<List<&2, List<&2, U32>>>>:
  match chunks:
    case Nil{}:
      List.reverse(&2, B.Weighted<List<&2, List<&2, U32>>>, reversed)
    case head <> tail:
      List.reverse(&2, B.Weighted<List<&2, List<&2, U32>>>, B.Weighted{List.reverse(&2, List<&2, U32>, head <> tail), cost} <> reversed)

def group_chunks(chunks: List<&2, List<&2, U32>>, remaining: Nat, +grain: Nat, reversed_chunks: List<&2, List<&2, U32>>, reversed_groups: List<&2, B.Weighted<List<&2, List<&2, U32>>>>) -> List<&2, B.Weighted<List<&2, List<&2, U32>>>>:
  match chunks remaining:
    case Nil{} _:
      finish_groups(reversed_chunks, Nat.sub(grain, remaining), reversed_groups)
    case head <> tail 0n:
      group_chunks(tail, Nat.sub(grain, 1n), grain, [head], B.Weighted{List.reverse(&2, List<&2, U32>, reversed_chunks), grain} <> reversed_groups)
    case head <> tail 1n+rest:
      group_chunks(tail, rest, grain, head <> reversed_chunks, reversed_groups)

def pack_group(chunks: List<&2, List<&2, U32>>, context: Unit) -> Result<&2, &2, M.Diagnostic, Packed>:
  pack_leaf(M.max_nat(), chunks, Nil{}, 0, 0, 0n, Nil{}, True{})

def collect_groups(results: List<&2, Result<&2, &2, M.Diagnostic, Packed>>) -> Result<&2, &2, M.Diagnostic, Packed>:
  match results:
    case Nil{}:
      Done{Packed{0n, Nil{}}}
    case head <> tail:
      merge(head, collect_groups(tail))

def pack_chunks(chunks: List<&2, List<&2, U32>>, grain: Nat) -> Result<&2, &2, M.Diagnostic, Packed>:
  +minimum = Nat.max(1n, grain)
  tasks = group_chunks(chunks, minimum, minimum, Nil{}, Nil{})
  collect_groups(B.execute(~List<&2, List<&2, U32>>, ~Unit, ~Result<&2, &2, M.Diagnostic, Packed>, ~pack_group, B.plan(List<&2, List<&2, U32>>, tasks, minimum), Unit{}))

def matching_length(same: Bool) -> Result<&2, &2, M.Diagnostic, Unit>:
  match same:
    case False{}:
      Fail{M.Diagnostic{"internal_error", "wasm", "Wasm byte plan length differs from its chunks"}}
    case True{}:
      Done{Unit{}}

def room(fits: Bool) -> Result<&2, &2, M.Diagnostic, Unit>:
  match fits:
    case False{}:
      Fail{R.protocol_error("response exceeds 16M words")}
    case True{}:
      Done{Unit{}}

def checked_packet(+header: List<&2, U32>, expected: Nat, packed: Packed, maximum: Nat) -> Result<&2, &2, M.Diagnostic, Packet>:
  Packed{+length, blocks} = packed
  +words = Nat.add(List.length(&2, U32, header), Nat.div(Nat.add(length, 3n), 4n))
  do Result<&2, &2, M.Diagnostic, Packet>:
    matched : Unit <- matching_length(Nat.is_eq(expected, length))
    bounded : Unit <- room(Nat.is_le(words, maximum))
    return Packet{U32.from_nat(words), header, blocks}

def oversized(result: Result<&2, &2, M.Diagnostic, List<&2, U32>>) -> Result<&2, &2, M.Diagnostic, Packet>:
  match result:
    case Fail{error}:
      Fail{error}
    case Done{words}:
      Fail{M.Diagnostic{"internal_error", "wasm", "Wasm byte plan length differs from its chunks"}}

def encode_payload(header: List<&2, U32>, length: Nat, chunks: List<&2, List<&2, U32>>, maximum: Nat, remaining: Nat, grain: Nat, fits: Bool) -> Result<&2, &2, M.Diagnostic, Packet>:
  match fits:
    case False{}:
      # Only this exceptional path flattens. Preserve the original competition
      # between an invalid byte and exhaustion of the response word allowance.
      oversized(R.encode_work(M.max_nat(), [R.ByteWords{W.join(chunks)}], remaining, Nil{}))
    case True{}:
      do Result<&2, &2, M.Diagnostic, Packet>:
        packed : Packed <- pack_chunks(chunks, grain)
        checked_packet(header, length, packed, maximum)

def encode_plan(fields: List<&2, R.Work>, plan: W.BytePlan, +maximum: Nat, grain: Nat) -> Result<&2, &2, M.Diagnostic, Packet>:
  W.BytePlan{+length, chunks} = plan
  do Result<&2, &2, M.Diagnostic, Packet>:
    +header : List<&2, U32> <- R.encode_work(M.max_nat(), List.append(&2, R.Work, fields, [R.ByteLength{length}]), maximum, Nil{})
    +remaining : Nat = Nat.sub(maximum, List.length(&2, U32, header))
    encode_payload(header, length, chunks, maximum, remaining, grain, Nat.is_le(Nat.div(Nat.add(length, 3n), 4n), remaining))

def words(+header: List<&2, U32>) -> Packet:
  Packet{U32.from_nat(List.length(&2, U32, header)), header, Nil{}}

def finish(result: Result<&2, &2, M.Diagnostic, Packet>) -> Packet:
  match result:
    case Fail{diagnostic}:
      words(R.encode_diagnostic(diagnostic))
    case Done{packet}:
      packet

# What a compiled reply carries beside its Wasm bytes. A Wasm-only reply
# (response kind 5) drops the analysis without encoding it: guests read their
# ABI from the module's blot:abi section.
type Contents is Data:
  FullArtifact{}
  WasmOnly{}

def artifact_fields(contents: Contents, analysis: Main.Analysis) -> List<&2, R.Work>:
  match contents:
    case FullArtifact{}:
      [R.Word{2}, R.Analysis{analysis}]
    case WasmOnly{}:
      [R.Word{5}]

def encode_artifact(contents: Contents, result: Result<&2, &2, M.Diagnostic, Main.PlannedArtifact>) -> Packet:
  match result:
    case Fail{diagnostic}:
      words(R.encode_diagnostic(diagnostic))
    case Done{Main.PlannedArtifact{analysis, plan}}:
      finish(encode_plan(R.Word{1112297300} <> R.Word{R.version()} <> artifact_fields(contents, analysis), plan, U32.to_nat(16777216), 2048n))
