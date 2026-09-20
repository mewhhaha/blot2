import Base

def receive() -> IO(Maybe<&2, List<&2, U32>>):
  import "./native_io.c"

def send(words: List<&2, U32>) -> IO(Unit):
  import "./native_io.c"
