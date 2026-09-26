import Base
import ./model.bend as M
import ./cst.bend as Cst
import ./main.bend as Compiler
import ./native_request.bend as Request
import ./native_response.bend as Response
import ./native_output.bend as Output
import ./native_io.bend as NativeIO
import ./native_session.bend as Session

type Reply is Data:
  Reply{state: Maybe<&2, Session.State>, packet: Output.Packet}

def state_of(reply: Reply) -> Maybe<&2, Session.State>:
  Reply{state, packet} = reply
  state

def packet_of(reply: Reply) -> Output.Packet:
  Reply{state, packet} = reply
  packet

def opened(previous: Maybe<&2, Session.State>, result: Result<&2, &2, M.Diagnostic, Session.State>) -> Reply:
  match result:
    case Fail{diagnostic}:
      Reply{previous, Output.words(Response.encode_diagnostic(diagnostic))}
    case Done{state}:
      Reply{Some{state}, Output.words(Response.encode(3, Nil{}))}

def stat_fields(stats: Session.Stats, fields: List<&2, Response.Work>) -> List<&2, Response.Work>:
  Session.Stats{lowered, declarations_reused, checked, groups_reused, evaluated, constants_reused, compiled, entries_reused} = stats
  Response.Word{1112297300} <> Response.Word{Response.version()} <> Response.Word{4} <> Response.Natural{lowered} <> Response.Natural{declarations_reused} <> Response.Natural{checked} <> Response.Natural{groups_reused} <> Response.Natural{evaluated} <> Response.Natural{constants_reused} <> Response.Natural{compiled} <> Response.Natural{entries_reused} <> fields

# Even a response-size failure must not publish the candidate cache state.
def encoded(previous: Maybe<&2, Session.State>, state: Session.State, result: Result<&2, &2, M.Diagnostic, Output.Packet>) -> Reply:
  match result:
    case Fail{diagnostic}:
      Reply{previous, Output.words(Response.encode_diagnostic(diagnostic))}
    case Done{packet}:
      Reply{Some{state}, packet}

def encode_analysis(fields: List<&2, Response.Work>) -> Result<&2, &2, M.Diagnostic, Output.Packet>:
  do Result<&2, &2, M.Diagnostic, Output.Packet>:
    words : List<&2, U32> <- Response.encode_work(M.max_nat(), fields, U32.to_nat(16777216), Nil{})
    return Output.words(words)

def completed(previous: Maybe<&2, Session.State>, contents: Output.Contents, result: Result<&2, &2, M.Diagnostic, Session.Completion>) -> Reply:
  match result:
    case Fail{diagnostic}:
      Reply{previous, Output.words(Response.encode_diagnostic(diagnostic))}
    case Done{Session.Completion{state, Session.Analyzed{analysis}, stats}}:
      encoded(previous, state, encode_analysis(stat_fields(stats, [Response.Word{1}, Response.Analysis{analysis}])))
    case Done{Session.Completion{state, Session.Compiled{Compiler.PlannedArtifact{analysis, plan}}, stats}}:
      encoded(previous, state, Output.encode_plan(stat_fields(stats, Output.artifact_fields(contents, analysis)), plan, U32.to_nat(16777216), 2048n))

def cached(previous: Maybe<&2, Session.State>, +operation: Request.Operation, root: Cst.Cst, fuel: Nat, steps: Nat) -> Reply:
  match previous:
    case None{}:
      Reply{None{}, Output.words(Response.encode_diagnostic(M.Diagnostic{"native_session", "session", "open a session before updating it"}))}
    case Some{+state}:
      completed(Some{state}, Request.contents(operation), Session.update(state, Request.mode(operation), root, fuel, steps))

def patched(previous: Maybe<&2, Session.State>, +operation: Request.Operation, declarations: List<&2, Session.Declaration>, fuel: Nat, steps: Nat) -> Reply:
  match previous:
    case None{}:
      Reply{None{}, Output.words(Response.encode_diagnostic(M.Diagnostic{"native_session", "session", "open a session before updating it"}))}
    case Some{+state}:
      completed(Some{state}, Request.contents(operation), Session.update_patch(state, Request.mode(operation), declarations, fuel, steps))

def respond(state: Maybe<&2, Session.State>, request: Result<&2, &2, M.Diagnostic, Request.Request>) -> Reply:
  match request:
    case Fail{diagnostic}:
      Reply{state, Output.words(Response.encode_diagnostic(diagnostic))}
    case Done{Request.Request{Request.Analyze{}, fuel, steps, root, prelude}}:
      Reply{state, Output.words(Response.encode_analysis(Compiler.analyze_source(root, prelude, fuel, steps)))}
    case Done{Request.Request{Request.Compile{}, fuel, steps, root, prelude}}:
      Reply{state, Output.encode_artifact(Output.FullArtifact{}, Compiler.compile_source_plan(root, prelude, fuel, steps))}
    case Done{Request.Request{Request.EmitWasm{}, fuel, steps, root, prelude}}:
      Reply{state, Output.encode_artifact(Output.WasmOnly{}, Compiler.compile_source_plan(root, prelude, fuel, steps))}
    case Done{Request.OpenSession{prelude, fuel}}:
      opened(state, Session.open(prelude, fuel))
    case Done{Request.SessionRequest{operation, fuel, steps, root}}:
      cached(state, operation, root, fuel, steps)
    case Done{Request.SessionPatch{operation, fuel, steps, declarations}}:
      patched(state, operation, declarations, fuel, steps)

def send_packet(packet: Output.Packet) -> IO(Unit):
  Output.Packet{word_count, header, blocks} = packet
  NativeIO.send(word_count, header, blocks)

# A malformed complete payload is recoverable; framing failures are fatal in
# NativeIO because the next request boundary can no longer be trusted.
def serve(fuel: Nat, state: Maybe<&2, Session.State>, incoming: Maybe<&1, NativeIO.Frame>) -> IO(Unit):
  match fuel incoming:
    case _ None{}:
      IO.pure(Unit, Unit{})
    case 0n Some{frame}:
      IO.die(Unit, 1, "native compiler request limit exhausted")
    case 1n+remaining Some{frame}:
      +reply = respond(state, Request.decode(frame))
      next_state = state_of(reply)
      packet = packet_of(reply)
      do IO<Unit>:
        send_packet(packet)
        next : Maybe<&1, NativeIO.Frame> <- NativeIO.receive()
        serve(remaining, next_state, next)

def main() -> IO(Unit):
  do IO<Unit>:
    # Handshake lets the parent measure process startup separately from work.
    NativeIO.send(2, [1112297300, Response.version()], Nil{})
    first : Maybe<&1, NativeIO.Frame> <- NativeIO.receive()
    serve(M.max_nat(), None{}, first)
