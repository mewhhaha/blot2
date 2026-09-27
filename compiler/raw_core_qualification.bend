import Base
import ./model.bend as M
import ./closures.bend as Closures

# Raw core entrypoints do not run release evidence selection. Check this after
# ordinary type checking but before evaluating constants or emitting code.
# Budget only one expression body at a time; declaration count must not
# introduce a new limit on modules the ordinary checker already accepts.
def scan_body(fuel: Nat, pending: List<&2, M.Expr>) -> Result<&2, &2, M.Diagnostic, Unit>:
  match fuel pending:
    case _ Nil{}:
      Done{Unit{}}
    case 0n _:
      Fail{M.Diagnostic{"expression_complexity", "raw_core", "qualified core scan exceeded its work limit"}}
    case 1n+rest M.QualifiedExpr{offset, annotation, _ <> _, value} <> tail:
      Fail{M.Diagnostic{"unspecialized_qualified", "offset:" ++ Nat.show(offset), "raw core with a nonempty where clause requires evidence elaboration through the source compiler"}}
    case 1n+rest expression <> tail:
      scan_body(rest, List.reverse.go(&2, M.Expr, List.reverse(&2, M.Expr, Closures.children(expression)), tail))

def scan_constants(values: List<&2, M.Constant>) -> Result<&2, &2, M.Diagnostic, Unit>:
  match values:
    case Nil{}:
      Done{Unit{}}
    case M.Constant{name, exported, annotation, value} <> following:
      do Result<&2, &2, M.Diagnostic, Unit>:
        checked : Unit <- scan_body(1048576n, [value])
        scan_constants(following)

def scan_functions(values: List<&2, M.Function>) -> Result<&2, &2, M.Diagnostic, Unit>:
  match values:
    case Nil{}:
      Done{Unit{}}
    case M.Function{name, exported, parameter, p, r, body} <> following:
      do Result<&2, &2, M.Diagnostic, Unit>:
        checked : Unit <- scan_body(1048576n, [body])
        scan_functions(following)

def check(module: M.Module) -> Result<&2, &2, M.Diagnostic, Unit>:
  M.Module{constants, functions, data_types, operations} = module
  do Result<&2, &2, M.Diagnostic, Unit>:
    checked : Unit <- scan_constants(constants)
    scan_functions(functions)
