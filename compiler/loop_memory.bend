import Base
import ./model.bend as M

# A loop may recycle its temporary arena only when its function cannot update
# an enclosing language effect provider. Foreign capabilities exchange scalar
# arrays through the guest ABI and cannot retain pointers into the guest heap.
def foreign_only(operations: List<&2, M.TypeId>) -> Bool:
  match operations:
    case Nil{}:
      True{}
    case head <> tail:
      Bool.and(M.is_foreign(head), foreign_only(tail))

def isolated(effects: M.EffectRow) -> Bool:
  match effects:
    case M.EffectRow{operations, M.ClosedRow{}}:
      foreign_only(operations)
    case _:
      False{}

def add_if(safe: Bool, key: String, +entries: Set()) -> Set():
  Bool.pick(Set(), safe, Set.add(entries, key), entries)

# Follow curried function values using their checked result types. Unrecognized
# expression shapes are deliberately left unoptimized.
def lambda_entries(fuel: Nat, expression: M.Expr, ty: M.Ty, entries: Set()) -> Set():
  match fuel expression ty:
    case 0n _ _:
      entries
    case 1n+rest M.SourceExpr{offset, annotation, value} ty:
      lambda_entries(rest, value, ty, entries)
    case 1n+rest M.RuntimeInitExpr{value} ty:
      lambda_entries(rest, value, ty, entries)
    case 1n+rest M.LetExpr{name, value, body} ty:
      lambda_entries(rest, body, ty, entries)
    case 1n+rest M.UseExpr{name, value, body} ty:
      lambda_entries(rest, body, ty, entries)
    case 1n+rest M.LambdaExpr{identity, parameter, p, r, body} M.FunctionTy{input, result, effects}:
      lambda_entries(rest, body, result, add_if(isolated(effects), "lambda:" ++ Nat.show(identity), entries))
    case _ _ _:
      entries

def constants(values: List<&2, M.CheckedConstant>, entries: Set()) -> Set():
  match values:
    case Nil{}:
      entries
    case M.CheckedConstant{M.Constant{name, exported, annotation, value}, ty, variables} <> tail:
      constants(tail, lambda_entries(16384n, value, ty, entries))

def functions(values: List<&2, M.CheckedFunction>, entries: Set()) -> Set():
  match values:
    case Nil{}:
      entries
    case M.CheckedFunction{M.Function{name, exported, parameter, p, r, body}, M.Signature{declared, input, result, variables, effects}, used} <> tail:
      functions(tail, lambda_entries(16384n, body, result, add_if(isolated(effects), "fn:" ++ name, entries)))

def eligible(constants_checked: List<&2, M.CheckedConstant>, functions_checked: List<&2, M.CheckedFunction>) -> Set():
  functions(functions_checked, constants(constants_checked, Set.new()))
