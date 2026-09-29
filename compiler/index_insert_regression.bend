import Base
import ./index.bend as Index

type Payload is Data:
  Payload{name: String, values: List<&2, Nat>}

def same_values(left: List<&2, Nat>, right: List<&2, Nat>) -> Bool:
  match left right:
    case Nil{} Nil{}: True{}
    case a <> xs b <> ys: Bool.and(Nat.is_eq(a, b), same_values(xs, ys))
    case _ _: False{}

def same_payload(left: Payload, right: Payload) -> Bool:
  Payload{a, xs} = left
  Payload{b, ys} = right
  Bool.and(String.eq(a, b), same_values(xs, ys))

def same_map(left: Map<&2, Payload>, right: Map<&2, Payload>) -> Bool:
  match left right:
    case MTip{} MTip{}: True{}
    case MLeaf{a, x} MLeaf{b, y}: Bool.and(String.eq(a, b), same_payload(x, y))
    case MNode{a, al, ar} MNode{b, bl, br}:
      Bool.and(Nat.is_eq(a, b), Bool.and(same_map(al, bl), same_map(ar, br)))
    case _ _: False{}

# Both old trees remain owned while insertion consumes another reference.
# Nested payloads exercise the actual native constructor-ownership boundary.
def work(keys: List<&2, String>, +left: Map<&2, Payload>, +right: Map<&2, Payload>, +value: Nat) -> Bool:
  match keys:
    case Nil{}: same_map(left, right)
    case +key <> tail:
      +payload = {Payload{key, [value, 1n+value]} : Payload}
      Bool.and(same_map(left, right), work(tail, Index.set(Payload, left, key, payload), Map.set(&2, Payload, right, key, payload), 1n+value))

def names(count: Nat) -> List<&2, String>:
  match count:
    case 0n: ["", "a", "aa", "ab", "é", "日本語", "🦆", "🦆x"]
    case 1n+ +remaining:
      ("qualified/module/path/namespace/qualified/module/path/namespace/" ++ Nat.show(remaining)) <> names(remaining)

def valid() -> Bool:
  +keys = names(128n)
  work(List.append(&2, String, keys, List.reverse(&2, String, keys)), MTip{}, MTip{}, 0n)

def finish(ok: Bool) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, "persistent symbol insertion differs from Base.Map")

def main() -> IO(Unit):
  finish(valid())
