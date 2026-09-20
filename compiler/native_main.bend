import Base
import ./model.bend as M
import ./cst.bend as Cst
import ./main.bend as Compiler
import ./native_request.bend as Request
import ./native_response.bend as Response
import ./native_io.bend as NativeIO
import ./native_session.bend as Session

type Reply is Data:
  Reply{state: Maybe<&2, Session.State>, words: List<&2, U32>}

def state_of(reply: Reply) -> Maybe<&2, Session.State>:
  Reply{state, words} = reply
  state

def words_of(reply: Reply) -> List<&2, U32>:
  Reply{state, words} = reply
  words

def mode(operation: Request.Operation) -> Session.Mode:
  match operation:
    case Request.Analyze{}:
      Session.AnalyzeMode{}
    case Request.Compile{}:
      Session.CompileMode{}

def opened(previous: Maybe<&2, Session.State>, result: Result<&2, &2, M.Diagnostic, Session.State>) -> Reply:
  match result:
    case Fail{diagnostic}:
      Reply{previous, Response.encode_diagnostic(diagnostic)}
    case Done{state}:
      Reply{Some{state}, Response.encode(3, Nil{})}

def output_fields(output: Session.Output) -> List<&2, Response.Work>:
  match output:
    case Session.Analyzed{analysis}:
      [Response.Word{1}, Response.Analysis{analysis}]
    case Session.Compiled{Compiler.Artifact{analysis, bytes}}:
      [Response.Word{2}, Response.Analysis{analysis}, Response.Bytes{bytes}]

def stat_fields(stats: Session.Stats, output: Session.Output) -> List<&2, Response.Work>:
  Session.Stats{lowered, declarations_reused, checked, groups_reused, evaluated, constants_reused, compiled, entries_reused} = stats
  Response.Natural{lowered} <> Response.Natural{declarations_reused} <> Response.Natural{checked} <> Response.Natural{groups_reused} <> Response.Natural{evaluated} <> Response.Natural{constants_reused} <> Response.Natural{compiled} <> Response.Natural{entries_reused} <> output_fields(output)

# Even a response-size failure must not publish the candidate cache state.
def encoded(previous: Maybe<&2, Session.State>, state: Session.State, result: Result<&2, &2, M.Diagnostic, List<&2, U32>>) -> Reply:
  match result:
    case Fail{diagnostic}:
      Reply{previous, Response.encode_diagnostic(diagnostic)}
    case Done{words}:
      Reply{Some{state}, words}

def completed(previous: Maybe<&2, Session.State>, result: Result<&2, &2, M.Diagnostic, Session.Completion>) -> Reply:
  match result:
    case Fail{diagnostic}:
      Reply{previous, Response.encode_diagnostic(diagnostic)}
    case Done{Session.Completion{state, output, stats}}:
      fields = {Response.Word{1112297300} <> Response.Word{6} <> Response.Word{4} <> stat_fields(stats, output) : List<&2, Response.Work>}
      encoded(previous, state, Response.encode_work(Nat.read.max(), fields, U32.to_nat(16777216), Nil{}))

def cached(previous: Maybe<&2, Session.State>, operation: Request.Operation, root: Cst.Cst, fuel: Nat, steps: Nat) -> Reply:
  match previous:
    case None{}:
      Reply{None{}, Response.encode_diagnostic(M.Diagnostic{"native_session", "session", "open a session before updating it"})}
    case Some{+state}:
      completed(Some{state}, Session.update(state, mode(operation), root, fuel, steps))

def patched(previous: Maybe<&2, Session.State>, operation: Request.Operation, declarations: List<&2, Session.Declaration>, fuel: Nat, steps: Nat) -> Reply:
  match previous:
    case None{}:
      Reply{None{}, Response.encode_diagnostic(M.Diagnostic{"native_session", "session", "open a session before updating it"})}
    case Some{+state}:
      completed(Some{state}, Session.update_patch(state, mode(operation), declarations, fuel, steps))

def respond(state: Maybe<&2, Session.State>, request: Result<&2, &2, M.Diagnostic, Request.Request>) -> Reply:
  match request:
    case Fail{diagnostic}:
      Reply{state, Response.encode_diagnostic(diagnostic)}
    case Done{Request.Request{Request.Analyze{}, fuel, steps, root, prelude}}:
      Reply{state, Response.encode_analysis(Compiler.analyze_source(root, prelude, fuel, steps))}
    case Done{Request.Request{Request.Compile{}, fuel, steps, root, prelude}}:
      Reply{state, Response.encode_artifact(Compiler.compile_source(root, prelude, fuel, steps))}
    case Done{Request.OpenSession{prelude, fuel}}:
      opened(state, Session.open(prelude, fuel))
    case Done{Request.SessionRequest{operation, fuel, steps, root}}:
      cached(state, operation, root, fuel, steps)
    case Done{Request.SessionPatch{operation, fuel, steps, declarations}}:
      patched(state, operation, declarations, fuel, steps)

# A malformed complete payload is recoverable; framing failures are fatal in
# NativeIO because the next request boundary can no longer be trusted.
def serve(fuel: Nat, state: Maybe<&2, Session.State>, incoming: Maybe<&2, List<&2, U32>>) -> IO(Unit):
  match fuel incoming:
    case _ None{}:
      IO.pure(Unit, Unit{})
    case 0n Some{words}:
      IO.die(Unit, 1, "native compiler request limit exhausted")
    case 1n+remaining Some{words}:
      +reply = respond(state, Request.decode(words))
      next_state = state_of(reply)
      response = words_of(reply)
      do IO<Unit>:
        NativeIO.send(response)
        next : Maybe<&2, List<&2, U32>> <- NativeIO.receive()
        serve(remaining, next_state, next)

def main() -> IO(Unit):
  do IO<Unit>:
    # Handshake lets the parent measure process startup separately from work.
    NativeIO.send([1112297300, 6])
    first : Maybe<&2, List<&2, U32>> <- NativeIO.receive()
    serve(Nat.read.max(), None{}, first)
