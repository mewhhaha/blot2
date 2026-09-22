import Base
import ./native_output.bend as Output

type Frame is Type:
  Frame{words: Array<U32>, length: U32}

def receive() -> IO(Maybe<&1, Frame>):
  import "./native_io.c"

def send(word_count: U32, header: List<&2, U32>, blocks: List<&2, Output.Block>) -> IO(Unit):
  import "./native_io.c"
