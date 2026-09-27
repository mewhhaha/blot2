import Base

# The frame type is pure so compiler proofs need not import foreign IO.
type Frame is Type:
  Frame{words: Array<U32>, length: U32}
