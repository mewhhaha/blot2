import Base
import ../../../compiler/index.bend as Index

type Payload is Data:
  Payload{name: String, values: List<&2, String>}

def same(found: Maybe<&2, Payload>, wanted: String) -> Bool:
  match found:
    case Some{Payload{name, first <> second <> Nil{}}}:
      Bool.and(String.eq(name, wanted), Bool.and(String.eq(first, "first"), String.eq(second, "second")))
    case _:
      False{}

def missing(found: Maybe<&2, Payload>) -> Bool:
  match found:
    case None{}:
      True{}
    case _:
      False{}

def fill(names: List<&2, String>, index: Map<&2, Payload>) -> Map<&2, Payload>:
  match names:
    case Nil{}:
      index
    case +name <> tail:
      fill(tail, Map.set(&2, Payload, index, name, Payload{name, ["first", "second"]}))

def verify(names: List<&2, String>, +index: Map<&2, Payload>) -> Bool:
  match names:
    case Nil{}:
      missing(Index.find(Payload, index, "not in the index"))
    case +name <> tail:
      Bool.and(same(Index.find(Payload, index, name), name), verify(tail, index))

def numbered(+count: Nat) -> List<&2, String>:
  match count:
    case 0n:
      ["", "a", "ab", "abc", "é", "é", "🦆", "🦆x", "日本語", SCon{Chr{2147483648}, SNil{}}, SCon{Chr{0}, SNil{}}]
    case 1n+rest:
      ("qualified/module/🦆/long/shared/prefix/" ++ Nat.show(rest)) <> numbered(rest)

def check() -> Bool:
  +names = numbered(512n)
  +snapshot = fill(names, MTip{})
  +changed = Map.set(&2, Payload, snapshot, "added", Payload{"added", ["first", "second"]})
  Bool.and(verify(names, snapshot), Bool.and(missing(Index.find(Payload, snapshot, "added")), Bool.and(verify(names, changed), same(Index.find(Payload, changed, "added"), "added"))))

def finish(ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.die(Unit, 1, "index snapshot or value ownership changed")

def main() -> IO(Unit):
  finish(check())
