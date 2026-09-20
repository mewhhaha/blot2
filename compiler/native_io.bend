import Base

type Frame is Type:
  Frame{words: Array<U32>, length: U32}

def receive() -> IO(Maybe<&1, Frame>):
  import "./native_io.c"

def send(words: List<&2, U32>) -> IO(Unit):
  import "./native_io.c"
