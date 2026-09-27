import Base
import ./model.bend as M
import ./infer.bend as I
import ./global_bindings.bend as B

def source() -> List<&2, I.Binding>:
  [I.Binding{"last", M.U32Ty{}, Nil{}, Nil{}}, I.Binding{"duplicate", M.VariableTy{7n}, [7n], Nil{}}, I.Binding{"unused", M.UnitTy{}, Nil{}, Nil{}}, I.Binding{"duplicate", M.BoolTy{}, Nil{}, Nil{}}, I.Binding{"first", M.F32Ty{}, Nil{}, Nil{}}]

def ordered(bindings: List<&2, I.Binding>) -> Bool:
  match bindings:
    case I.Binding{a, M.U32Ty{}, Nil{}, Nil{}} <> I.Binding{b, M.VariableTy{7n}, 7n <> Nil{}, Nil{}} <> I.Binding{c, M.BoolTy{}, Nil{}, Nil{}} <> I.Binding{d, M.F32Ty{}, Nil{}, Nil{}} <> Nil{}:
      Bool.and(M.name_equal(a, "last"), Bool.and(M.name_equal(b, "duplicate"), Bool.and(M.name_equal(c, "duplicate"), M.name_equal(d, "first"))))
    case _:
      False{}

def empty(bindings: List<&2, I.Binding>) -> Bool:
  match bindings:
    case Nil{}:
      True{}
    case _:
      False{}

def valid() -> Bool:
  +index = B.build(source(), 0n, MTip{})
  # Reverse query order and repeated queries still retain source order and both
  # definitions of the duplicate name. Shared index snapshots remain intact.
  Bool.and(ordered(B.referenced(index, ["first", "duplicate", "missing", "last", "duplicate"])), Bool.and(ordered(B.referenced(index, ["duplicate", "first", "last"])), empty(B.referenced(index, ["missing"]))))

def finish(valid: Bool) -> IO(Unit):
  match valid:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.die(Unit, 1, "ordered global binding index regression failed")

def main() -> IO(Unit):
  finish(valid())
