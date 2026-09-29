import Base
import ./index.bend as Index
import ./model.bend as M
import ./dependency.bend as D
import ./check.bend as Check
import ./check_scheduler.bend as Scheduler
import ./groups.bend as G
import ./globals.bend as Globals

type Nominals is Data:
  Nominals{functions: Result<&2, &2, M.Diagnostic, List<&2, G.DeclarationUsage>>, constants: Result<&2, &2, M.Diagnostic, List<&2, G.DeclarationUsage>>}

def nominal_scan(module: M.Module, +constructors: Map<&2, M.TypeId>) -> Nominals:
  M.Module{constants, functions, types, operations} = module
  Nominals{G.declaration_usages(Globals.function_declarations(functions), constructors), G.declaration_usages(Globals.constant_declarations(constants), constructors)}

def append_usages(left: Result<&2, &2, M.Diagnostic, List<&2, G.DeclarationUsage>>, right: Result<&2, &2, M.Diagnostic, List<&2, G.DeclarationUsage>>) -> Result<&2, &2, M.Diagnostic, List<&2, G.DeclarationUsage>>:
  do Result<&2, &2, M.Diagnostic, List<&2, G.DeclarationUsage>>:
    a : List<&2, G.DeclarationUsage> <- left
    b : List<&2, G.DeclarationUsage> <- right
    return List.append(&2, G.DeclarationUsage, a, b)

def merge_nominals(left: Nominals, right: Nominals) -> Nominals:
  Nominals{functions, constants} = left
  Nominals{fs, cs} = right
  Nominals{append_usages(functions, fs), append_usages(constants, cs)}

def nominal_usages(scanned: Nominals) -> Result<&2, &2, M.Diagnostic, List<&2, G.DeclarationUsage>>:
  Nominals{functions, constants} = scanned
  append_usages(functions, constants)

# Scans depend only on lowered bodies. Keep failures as values so global
# validation and function-before-constant diagnostics retain their precedence.
type Scanned is Data:
  Scanned{functions: Result<&2, &2, M.Diagnostic, List<&2, D.Node>>, constants: Result<&2, &2, M.Diagnostic, List<&2, D.Node>>, costs: Map<&2, Nat>}

type ScannedGraph is Data:
  ScannedGraph{functions: Result<&2, &2, M.Diagnostic, List<&2, D.Node>>, constants: Result<&2, &2, M.Diagnostic, List<&2, D.Node>>}

def function_costs(functions: List<&2, M.Function>, costs: Map<&2, Nat>) -> Map<&2, Nat>:
  match functions:
    case Nil{}:
      costs
    case M.Function{+name, exported, parameter, p, r, body} <> tail:
      cost = Scheduler.module_cost(M.Module{Nil{}, [M.Function{name, exported, parameter, p, r, body}], Nil{}, Nil{}})
      function_costs(tail, Index.set(Nat, costs, name, cost))

def constant_costs(constants: List<&2, M.Constant>, costs: Map<&2, Nat>) -> Map<&2, Nat>:
  match constants:
    case Nil{}:
      costs
    case M.Constant{+name, exported, annotation, value} <> tail:
      cost = Scheduler.module_cost(M.Module{[M.Constant{name, exported, annotation, value}], Nil{}, Nil{}, Nil{}})
      constant_costs(tail, Index.set(Nat, costs, name, cost))

def scan(module: M.Module) -> Scanned:
  M.Module{+constants, +functions, types, operations} = module
  Scanned{D.function_nodes(functions), D.constant_nodes(constants), function_costs(functions, constant_costs(constants, Map.new(&2, Nat)))}

def append_nodes(left: Result<&2, &2, M.Diagnostic, List<&2, D.Node>>, right: Result<&2, &2, M.Diagnostic, List<&2, D.Node>>) -> Result<&2, &2, M.Diagnostic, List<&2, D.Node>>:
  do Result<&2, &2, M.Diagnostic, List<&2, D.Node>>:
    a : List<&2, D.Node> <- left
    b : List<&2, D.Node> <- right
    return List.append(&2, D.Node, a, b)

def merge(left: Scanned, right: ScannedGraph) -> ScannedGraph:
  Scanned{functions, constants, costs} = left
  ScannedGraph{fs, cs} = right
  ScannedGraph{append_nodes(functions, fs), append_nodes(constants, cs)}

def combine(scans: List<&2, Scanned>) -> ScannedGraph:
  match scans:
    case Nil{}:
      ScannedGraph{Done{Nil{}}, Done{Nil{}}}
    case head <> tail:
      merge(head, combine(tail))

def scanned_graph(scanned: ScannedGraph) -> Result<&2, &2, M.Diagnostic, List<&2, D.Node>>:
  ScannedGraph{functions, constants} = scanned
  do Result<&2, &2, M.Diagnostic, List<&2, D.Node>>:
    +nodes : List<&2, D.Node> <- append_nodes(functions, constants)
    unique : Unit <- Check.unique_lambdas(Check.lambda_ids(nodes))
    return nodes

def graph(module: M.Module, scans: List<&2, Scanned>) -> Result<&2, &2, M.Diagnostic, List<&2, D.Node>>:
  do Result<&2, &2, M.Diagnostic, List<&2, D.Node>>:
    valid : Unit <- Check.validate_module(module)
    scanned_graph(combine(scans))

def collect_costs(scans: List<&2, Scanned>, found: Map<&2, Nat>) -> Map<&2, Nat>:
  match scans:
    case Nil{}:
      found
    case Scanned{functions, constants, costs} <> tail:
      collect_costs(tail, Map.union(&2, Nat, found, costs))
