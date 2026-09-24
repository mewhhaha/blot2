import Base
import ./model.bend as M

def prefix(count: Nat, acc: String) -> String:
  match count:
    case 0n:
      acc
    case 1n+rest:
      prefix(rest, "abcdefgh" ++ acc)

def valid() -> Bool:
  +shared = {"shared" ++ "-name" : String}
  +suffix = {"suffix" ++ "-tail" : String}
  +long = {prefix(600n, "") : String}
  Bool.and(M.name_equal("", ""),
    Bool.and(Bool.not(M.name_equal("", "a")),
    Bool.and(M.name_equal("shared" ++ "-name", "shared" ++ "-name"),
    Bool.and(M.name_equal(shared, shared),
    Bool.and(Bool.not(M.name_equal("a" ++ suffix, "b" ++ suffix)),
    Bool.and(M.name_equal("é", "é"),
    Bool.and(Bool.not(M.name_equal("é", "é")),
    Bool.and(Bool.not(M.name_equal("𐐀", "𐐁")),
    Bool.and(M.name_equal(long, long),
      Bool.not(M.name_equal(long ++ "x", long ++ "y")))))))))))

def finish(ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.die(Unit, 1, "native String comparison regression failed")

def main() -> IO(Unit):
  finish(valid())
