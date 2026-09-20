import Base
import ./model.bend as M
import ./main.bend as Compiler
import ./native_request.bend as Request
import ./native_response.bend as Response
import ./native_io.bend as NativeIO

def respond(request: Result<&2, &2, M.Diagnostic, Request.Request>) -> List<&2, U32>:
  match request:
    case Fail{diagnostic}:
      Response.encode_diagnostic(diagnostic)
    case Done{Request.Request{Request.Analyze{}, fuel, steps, root, prelude}}:
      Response.encode_analysis(Compiler.analyze_source(root, prelude, fuel, steps))
    case Done{Request.Request{Request.Compile{}, fuel, steps, root, prelude}}:
      Response.encode_artifact(Compiler.compile_source(root, prelude, fuel, steps))
    case Done{Request.Request{Request.CompileEcs{}, fuel, steps, root, prelude}}:
      Response.encode_ecs_artifact(Compiler.compile_ecs_source(root, prelude, fuel, steps))

# A malformed complete payload is recoverable; framing failures are fatal in
# NativeIO because the next request boundary can no longer be trusted.
def serve(fuel: Nat, incoming: Maybe<&2, List<&2, U32>>) -> IO(Unit):
  match fuel incoming:
    case _ None{}:
      IO.pure(Unit, Unit{})
    case 0n Some{words}:
      IO.die(Unit, 1, "native compiler request limit exhausted")
    case 1n+remaining Some{words}:
      do IO<Unit>:
        NativeIO.send(respond(Request.decode(words)))
        next : Maybe<&2, List<&2, U32>> <- NativeIO.receive()
        serve(remaining, next)

def main() -> IO(Unit):
  do IO<Unit>:
    # Handshake lets the parent measure process startup separately from work.
    NativeIO.send([1112297300, 1])
    first : Maybe<&2, List<&2, U32>> <- NativeIO.receive()
    serve(Nat.read.max(), first)
