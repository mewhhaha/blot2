import Base
import ./native_io.bend as NativeIO
import ./native_output.bend as Output

# Foreign transport stays outside the pure compiler/proof import closure.
def receive() -> IO(Maybe<&1, NativeIO.Frame>):
  import "./native_io.c"

def send(word_count: U32, header: List<&2, U32>, blocks: List<&2, Output.Block>) -> IO(Unit):
  import "./native_io.c"
