import Base
import ./model.bend as M
import ./dependency.bend as D
import ./closures.bend as F
import ./index.bend as Index
import ./infer.bend as I
import ./groups.bend as G
import ./checked_core.bend as Core
import ./check_scheduler.bend as Scheduler
import ./inference_batch.bend as Batch
import ./constraints.bend as Constraints

# Entry declarations (`entry const` / `entry let` in the entry module) are the
# host's entrypoints. Lowering marks them with the `exported` flag; nothing
# else sets it. They are the module's only Wasm exports and the only roots of
# dead-code elimination: once every declaration has passed the initial check,
# declarations the entries cannot reach are dropped before specialization, so
# they are never specialized, finally checked, const-evaluated, initialized or
# emitted. `entry` never affects Blot-level visibility.

type Entry is Data:
  Entry{name: String, runtime: Bool}

def runtime_value(value: M.Expr) -> Bool:
  match value:
    case M.RuntimeInitExpr{initial}:
      True{}
    case _:
      False{}

def function_entries(functions: List<&2, M.Function>) -> List<&2, Entry>:
  match functions:
    case Nil{}:
      Nil{}
    case M.Function{name, True{}, parameter, p, r, body} <> tail:
      Entry{name, runtime_value(body)} <> function_entries(tail)
    case head <> tail:
      function_entries(tail)

def constant_entries(constants: List<&2, M.Constant>) -> List<&2, Entry>:
  match constants:
    case Nil{}:
      Nil{}
    case M.Constant{name, True{}, annotation, value} <> tail:
      Entry{name, runtime_value(value)} <> constant_entries(tail)
    case head <> tail:
      constant_entries(tail)

# The lowered module's entry declarations, before export selection narrows
# the flags of entries whose types do not fit the guest ABI.
def entries(module: M.Module) -> List<&2, Entry>:
  M.Module{constants, functions, types, operations} = module
  List.append(&2, Entry, function_entries(functions), constant_entries(constants))

# ---------------------------------------------------------------------------
# Reachability
# ---------------------------------------------------------------------------

# One walk per declaration collects the declarations it names (the lowered
# dependency graph, including value-pattern pins and reflection) and the
# members of its deferred dispatch sites.
type Found is Data:
  Found{names: List<&2, String>, members: List<&2, String>}

# Children become their own work items instead of being appended to a
# sibling list, so a wide array, tuple or match stays one flat queue.
type ScanWork is Data:
  ScanExpressions{values: List<&2, M.Expr>}
  ScanPatterns{values: List<&2, M.Pattern>}
  ScanArms{values: List<&2, M.MatchArm<M.Expr>>}

def scan_work(fuel: Nat, pending: List<&2, ScanWork>, names: List<&2, String>, members: List<&2, String>) -> Result<&2, &2, M.Diagnostic, Found>:
  match fuel pending:
    case _ Nil{}:
      Done{Found{names, members}}
    case 0n _:
      Fail{M.Diagnostic{"expression_complexity", "entry", "entry reachability exceeded its traversal limit"}}
    case 1n+rest ScanExpressions{Nil{}} <> tail:
      scan_work(rest, tail, names, members)
    case 1n+rest ScanExpressions{M.ConstantExpr{name} <> values} <> tail:
      scan_work(rest, ScanExpressions{values} <> tail, name <> names, members)
    case 1n+rest ScanExpressions{M.FunctionExpr{name} <> values} <> tail:
      scan_work(rest, ScanExpressions{values} <> tail, name <> names, members)
    case 1n+rest ScanExpressions{M.FunctionEffectsExpr{callee} <> values} <> tail:
      scan_work(rest, ScanExpressions{values} <> tail, callee <> names, members)
    case 1n+rest ScanExpressions{M.CallExpr{callee, argument} <> values} <> tail:
      scan_work(rest, ScanExpressions{argument <> values} <> tail, callee <> names, members)
    case 1n+rest ScanExpressions{M.AssociatedExpr{identity, dispatch, member, templates, left, right} <> values} <> tail:
      scan_work(rest, ScanExpressions{left <> right <> values} <> tail, names, member <> members)
    case 1n+rest ScanExpressions{M.QualifiedExpr{offset, annotation, predicates, value} <> values} <> tail:
      # Deliberately extra declared predicates remain caller obligations even
      # when no body expression performs that selection.
      scan_work(rest, ScanExpressions{value <> values} <> tail, names, List.reverse.go(&2, String, List.reverse(&2, String, Constraints.predicate_members(predicates)), members))
    case 1n+rest ScanExpressions{M.MatchExpr{scrutinees, arms} <> values} <> tail:
      scan_work(rest, ScanExpressions{scrutinees} <> ScanArms{arms} <> ScanExpressions{values} <> tail, names, members)
    case 1n+rest ScanExpressions{M.GuardExpr{pattern, value, alternative, body} <> values} <> tail:
      scan_work(rest, ScanPatterns{[pattern]} <> ScanExpressions{value <> alternative <> body <> values} <> tail, names, members)
    case 1n+rest ScanExpressions{expression <> values} <> tail:
      scan_work(rest, ScanExpressions{F.children(expression)} <> ScanExpressions{values} <> tail, names, members)
    case 1n+rest ScanArms{Nil{}} <> tail:
      scan_work(rest, tail, names, members)
    case 1n+rest ScanArms{M.MatchArm{patterns, body} <> arms} <> tail:
      scan_work(rest, ScanPatterns{patterns} <> ScanExpressions{[body]} <> ScanArms{arms} <> tail, names, members)
    case 1n+rest ScanPatterns{Nil{}} <> tail:
      scan_work(rest, tail, names, members)
    case 1n+rest ScanPatterns{M.ValuePattern{M.ConstantReference{name}} <> patterns} <> tail:
      scan_work(rest, ScanPatterns{patterns} <> tail, name <> names, members)
    case 1n+rest ScanPatterns{M.ConstructorPattern{constructor, Some{payload}} <> patterns} <> tail:
      scan_work(rest, ScanPatterns{payload <> patterns} <> tail, names, members)
    case 1n+rest ScanPatterns{M.ProductPattern{elements} <> patterns} <> tail:
      scan_work(rest, ScanPatterns{elements} <> ScanPatterns{patterns} <> tail, names, members)
    case 1n+rest ScanPatterns{pattern <> patterns} <> tail:
      scan_work(rest, ScanPatterns{patterns} <> tail, names, members)

def scan_limit() -> Nat:
  U32.to_nat(16777216)

def scan(body: M.Expr) -> Result<&2, &2, M.Diagnostic, Found>:
  scan_work(scan_limit(), [ScanExpressions{[body]}], Nil{}, Nil{})

type Declaration is Data:
  Declaration{name: String, root: Bool, body: M.Expr}

type Declared is Data:
  Declared{name: String, root: Bool, found: Found}

def scan_declaration(declaration: Declaration, context: Unit) -> Result<&2, &2, M.Diagnostic, Declared>:
  Declaration{name, root, body} = declaration
  do Result<&2, &2, M.Diagnostic, Declared>:
    found : Found <- scan(body)
    return Declared{name, root, found}

def function_declarations(functions: List<&2, M.Function>, rest: List<&2, Batch.Weighted<Declaration>>) -> List<&2, Batch.Weighted<Declaration>>:
  match functions:
    case Nil{}:
      rest
    case M.Function{name, exported, parameter, p, r, body} <> tail:
      Batch.Weighted{Declaration{name, exported, body}, 1n} <> function_declarations(tail, rest)

def constant_declarations(constants: List<&2, M.Constant>) -> List<&2, Batch.Weighted<Declaration>>:
  match constants:
    case Nil{}:
      Nil{}
    case M.Constant{name, exported, annotation, value} <> tail:
      Batch.Weighted{Declaration{name, exported, value}, 1n} <> constant_declarations(tail)

# Declarations are scanned in parallel, 64 to a leaf; results keep source order.
def scan_grain() -> Nat:
  64n

type Graph is Data:
  Graph{names: List<&2, String>, roots: List<&2, String>, nodes: List<&2, Declared>}

def add_declared(declared: Declared, rest: Graph) -> Graph:
  Declared{+name, +root, found} = declared
  Graph{names, +roots, nodes} = rest
  Graph{name <> names, Bool.pick(List<&2, String>, root, name <> roots, roots), Declared{name, root, found} <> nodes}

def collect_graph(scanned: List<&2, Result<&2, &2, M.Diagnostic, Declared>>) -> Result<&2, &2, M.Diagnostic, Graph>:
  match scanned:
    case Nil{}:
      Done{Graph{Nil{}, Nil{}, Nil{}}}
    case Fail{diagnostic} <> tail:
      Fail{diagnostic}
    case Done{declared} <> tail:
      do Result<&2, &2, M.Diagnostic, Graph>:
        rest : Graph <- collect_graph(tail)
        return add_declared(declared, rest)

# Associated implementations are named `<owner>.<member>`, where the owner is
# the operand's nominal prefix (Mono.owner/Mono.nominal_prefix, see the
# entry_owner_prefix_matches_specialization law). Before specialization a
# deferred site's operand types are open, so a reachable `member` site keeps
# every declared implementation of that member reachable.
def owner_prefix(identity: M.TypeId, +entry: String) -> String:
  M.TypeId{+module_name, declaration} = identity
  Bool.pick(String, M.name_equal(module_name, "std/prelude"), "$prelude.", Bool.pick(String, M.name_equal(module_name, entry), "", "$module[" ++ module_name ++ "].")) ++ declaration

def type_owners(types: List<&2, M.DataType>, +entry: String, owners: Set()) -> Set():
  match types:
    case Nil{}:
      owners
    case M.DataType{identity, parameters, constructors} <> tail:
      type_owners(tail, entry, Set.add(owners, owner_prefix(identity, entry)))

def builtin_owners() -> Set():
  Set.from_list(["$prelude.U32", "$prelude.F32", "$prelude.Bool", "$prelude.Unit", "$prelude.Array"])

type Split is Data:
  Split{owner: String, member: String}

def split_reversed(reversed: List<&2, String>) -> Maybe<&2, Split>:
  match reversed:
    case member <> first <> rest:
      Some{Split{String.join(List.reverse(&2, String, first <> rest), "."), member}}
    case _:
      None{}

# "$module[a.b].Owner.member" splits at its last dot; joining the other
# segments restores the owner exactly, whatever dots a module name contains.
def split_member(name: String) -> Maybe<&2, Split>:
  split_reversed(List.reverse(&2, String, String.split(name, '.')))

def add_implementation(split: Maybe<&2, Split>, +name: String, +owners: Set(), +index: Map<&2, List<&2, String>>) -> Map<&2, List<&2, String>>:
  match split:
    case None{}:
      index
    case Some{Split{owner, +member}}:
      Bool.pick(Map<&2, List<&2, String>>, D.member(owners, owner), Index.set(List<&2, String>, index, member, name <> Index.get(List<&2, String>, index, member, Nil{})), index)

def implementations(names: List<&2, String>, +owners: Set(), index: Map<&2, List<&2, String>>) -> Map<&2, List<&2, String>>:
  match names:
    case Nil{}:
      index
    case +name <> tail:
      implementations(tail, owners, add_implementation(split_member(name), name, owners, index))

def member_edges(members: List<&2, String>, +index: Map<&2, List<&2, String>>, edges: List<&2, String>) -> List<&2, String>:
  match members:
    case Nil{}:
      edges
    case member <> tail:
      member_edges(tail, index, List.append(&2, String, Index.get(List<&2, String>, index, member, Nil{}), edges))

def adjacency(nodes: List<&2, Declared>, +index: Map<&2, List<&2, String>>, edges: Map<&2, List<&2, String>>) -> Map<&2, List<&2, String>>:
  match nodes:
    case Nil{}:
      edges
    case Declared{name, root, Found{names, members}} <> tail:
      adjacency(tail, index, Index.set(List<&2, String>, edges, name, member_edges(Set.to_list(Set.from_list(members)), index, names)))

def edge_count(nodes: List<&2, Declared>, total: Nat) -> Nat:
  match nodes:
    case Nil{}:
      total
    case Declared{name, root, Found{names, members}} <> tail:
      edge_count(tail, Nat.add(total, Nat.add(List.length(&2, String, names), List.length(&2, String, members))))

def reach(graph: Graph, owners: Set()) -> Result<&2, &2, M.Diagnostic, Set()>:
  Graph{+names, roots, +nodes} = graph
  +index = implementations(names, owners, Map.new(&2, List<&2, String>))
  +edges = adjacency(nodes, index, Map.new(&2, List<&2, String>))
  # Each name enters the pending list once per incoming edge; one declaration's
  # member edges name each declaration at most once.
  +count = List.length(&2, String, names)
  +fuel = {1n+Nat.add(Nat.add(Nat.mul(count, 2n), edge_count(nodes, 0n)), Nat.mul(count, count)) : Nat}
  do Result<&2, &2, M.Diagnostic, Set()>:
    reached : D.Reachability <- D.reachable(fuel, roots, edges, Set.from_list(names), Set.new(), Nil{})
    return D.reached_seen(reached)

# The declarations the entries reach. Data types and operations carry no code
# and are always kept.
def reachable(module: M.Module, +entry: String) -> Result<&2, &2, M.Diagnostic, Set()>:
  M.Module{constants, functions, +types, operations} = module
  +tasks = function_declarations(functions, constant_declarations(constants))
  scanned = Batch.execute(~Declaration, ~Unit, ~Result<&2, &2, M.Diagnostic, Declared>, ~scan_declaration, Batch.plan(Declaration, tasks, scan_grain()), Unit{})
  do Result<&2, &2, M.Diagnostic, Set()>:
    graph : Graph <- collect_graph(scanned)
    reach(graph, type_owners(types, entry, builtin_owners()))

def keep_functions(functions: List<&2, M.Function>, +seen: Set()) -> List<&2, M.Function>:
  match functions:
    case Nil{}:
      Nil{}
    case +function <> tail:
      M.Function{name, exported, parameter, p, r, body} = function
      +rest = keep_functions(tail, seen)
      Bool.pick(List<&2, M.Function>, D.member(seen, name), function <> rest, rest)

def keep_constants(constants: List<&2, M.Constant>, +seen: Set()) -> List<&2, M.Constant>:
  match constants:
    case Nil{}:
      Nil{}
    case +constant <> tail:
      M.Constant{name, exported, annotation, value} = constant
      +rest = keep_constants(tail, seen)
      Bool.pick(List<&2, M.Constant>, D.member(seen, name), constant <> rest, rest)

def keep_module(module: M.Module, +seen: Set()) -> M.Module:
  M.Module{constants, functions, types, operations} = module
  M.Module{keep_constants(constants, seen), keep_functions(functions, seen), types, operations}

def keep_checked_functions(functions: List<&2, M.CheckedFunction>, +seen: Set()) -> List<&2, M.CheckedFunction>:
  match functions:
    case Nil{}:
      Nil{}
    case +checked <> tail:
      M.CheckedFunction{M.Function{name, exported, parameter, p, r, body}, signature, effects} = checked
      +rest = keep_checked_functions(tail, seen)
      Bool.pick(List<&2, M.CheckedFunction>, D.member(seen, name), checked <> rest, rest)

def keep_checked_constants(constants: List<&2, M.CheckedConstant>, +seen: Set()) -> List<&2, M.CheckedConstant>:
  match constants:
    case Nil{}:
      Nil{}
    case +checked <> tail:
      M.CheckedConstant{M.Constant{name, exported, annotation, value}, ty, variables} = checked
      +rest = keep_checked_constants(tail, seen)
      Bool.pick(List<&2, M.CheckedConstant>, D.member(seen, name), checked <> rest, rest)

def keep_checked(checked: M.CheckedModule, +seen: Set()) -> M.CheckedModule:
  M.CheckedModule{constants, functions, types, operations} = checked
  M.CheckedModule{keep_checked_constants(constants, seen), keep_checked_functions(functions, seen), types, operations}

def group_reached(members: List<&2, I.Binding>, +seen: Set()) -> Bool:
  match members:
    case Nil{}:
      True{}
    case I.Binding{name, ty, variables, predicates} <> tail:
      D.member(seen, name)

# A group is a strongly connected component: its members are reached together.
def keep_needs(needs: List<&2, G.GroupNeeds>, +seen: Set()) -> List<&2, G.GroupNeeds>:
  match needs:
    case Nil{}:
      Nil{}
    case +group <> tail:
      G.GroupNeeds{next, requirements, +members, generalized} = group
      +rest = keep_needs(tail, seen)
      Bool.pick(List<&2, G.GroupNeeds>, group_reached(members, seen), group <> rest, rest)

def module_reached(module: M.Module, +seen: Set()) -> Bool:
  match module:
    case M.Module{M.Constant{name, exported, annotation, value} <> constants, functions, types, operations}:
      D.member(seen, name)
    case M.Module{Nil{}, M.Function{name, exported, parameter, p, r, body} <> functions, types, operations}:
      D.member(seen, name)
    case _:
      True{}

def keep_certificates(certificates: List<&2, Core.Certificate>, +seen: Set()) -> List<&2, Core.Certificate>:
  match certificates:
    case Nil{}:
      Nil{}
    case +certificate <> tail:
      Core.Certificate{module, checked, imports} = certificate
      +rest = keep_certificates(tail, seen)
      Bool.pick(List<&2, Core.Certificate>, module_reached(module, seen), certificate <> rest, rest)

def keep_initial(initial: Scheduler.Initial, +seen: Set()) -> Scheduler.Initial:
  Scheduler.Initial{checked, certificates, needs} = initial
  Scheduler.Initial{keep_checked(checked, seen), keep_certificates(certificates, seen), keep_needs(needs, seen)}

type Pruned is Data:
  Pruned{module: M.Module, initial: Scheduler.Initial}

def pruned_module(pruned: Pruned) -> M.Module:
  Pruned{module, initial} = pruned
  module

def pruned_initial(pruned: Pruned) -> Scheduler.Initial:
  Pruned{module, initial} = pruned
  initial

# Dead-code elimination right after the initial check, which every
# declaration has passed: the rest of the pipeline sees only reachable code.
def prune_initial(+module: M.Module, initial: Scheduler.Initial, +entry: String) -> Result<&2, &2, M.Diagnostic, Pruned>:
  do Result<&2, &2, M.Diagnostic, Pruned>:
    +seen : Set() <- reachable(module, entry)
    return Pruned{keep_module(module, seen), keep_initial(initial, seen)}

def prune_checked(+module: M.Module, checked: M.CheckedModule, +entry: String) -> Result<&2, &2, M.Diagnostic, Pruned>:
  prune_initial(module, Scheduler.Initial{checked, Nil{}, Nil{}}, entry)

# ---------------------------------------------------------------------------
# Entry diagnostics
# ---------------------------------------------------------------------------

def strip_public(+name: String) -> String:
  Bool.pick(String, String.starts_with(name, "$public:"), String.drop(name, 8n), name)

def exported_functions(functions: List<&2, M.CheckedFunction>, names: Set()) -> Set():
  match functions:
    case Nil{}:
      names
    case M.CheckedFunction{M.Function{name, True{}, parameter, p, r, body}, signature, effects} <> tail:
      exported_functions(tail, Set.add(names, strip_public(name)))
    case head <> tail:
      exported_functions(tail, names)

def exported_constants(constants: List<&2, M.CheckedConstant>, names: Set()) -> Set():
  match constants:
    case Nil{}:
      names
    case M.CheckedConstant{M.Constant{name, True{}, annotation, value}, ty, variables} <> tail:
      exported_constants(tail, Set.add(names, name))
    case head <> tail:
      exported_constants(tail, names)

def function_types(functions: List<&2, M.CheckedFunction>, types: Map<&2, M.Ty>) -> Map<&2, M.Ty>:
  match functions:
    case Nil{}:
      types
    case M.CheckedFunction{function, M.Signature{name, parameter, result, variables, row}, effects} <> tail:
      function_types(tail, Index.set(M.Ty, types, name, M.FunctionTy{parameter, result, row}))

def constant_types(constants: List<&2, M.CheckedConstant>, types: Map<&2, M.Ty>) -> Map<&2, M.Ty>:
  match constants:
    case Nil{}:
      types
    case M.CheckedConstant{M.Constant{name, exported, annotation, value}, ty, variables} <> tail:
      constant_types(tail, Index.set(M.Ty, types, name, ty))

def abi_rule() -> String:
  "entry functions take Unit, U32, F32, Bool, Array U32 or Array F32 (or one scalar/numeric-array callback with exactly ! {Foreign}), return one of those types and handle every other effect; entry values are Unit, U32, F32 or Bool"

def open_row(row: M.EffectRow) -> Bool:
  match row:
    case M.EffectRow{operations, M.ClosedRow{}}:
      False{}
    case _:
      True{}

# A type that still mentions a type or row variable is generic: no caller
# instantiates an entry, so it can never fit the guest ABI.
def generic_types(fuel: Nat, pending: List<&2, M.Ty>) -> Bool:
  match fuel pending:
    case _ Nil{}:
      False{}
    case 0n _:
      True{}
    case 1n+rest M.ParameterTy{index} <> tail:
      True{}
    case 1n+rest M.VariableTy{index} <> tail:
      True{}
    case 1n+rest M.FunctionTy{parameter, result, effects} <> tail:
      Bool.or(open_row(effects), generic_types(rest, parameter <> result <> tail))
    case 1n+rest M.AppliedTy{identity, arguments} <> tail:
      generic_types(rest, List.append(&2, M.Ty, arguments, tail))
    case 1n+rest M.ProductTy{elements} <> tail:
      generic_types(rest, List.append(&2, M.Ty, elements, tail))
    case 1n+rest M.ArrayTy{element} <> tail:
      generic_types(rest, element <> tail)
    case 1n+rest M.StateProviderTy{read, write, state} <> tail:
      generic_types(rest, state <> tail)
    case 1n+rest other <> tail:
      generic_types(rest, tail)

def entry_type_failure(generic: Bool, +name: String, +ty: M.Ty) -> M.Diagnostic:
  match generic:
    case True{}:
      M.Diagnostic{"entry_type", name, "entry `" ++ name ++ "` has a generic type " ++ M.type_show(ty) ++ ", so it cannot be a Wasm export: " ++ abi_rule()}
    case False{}:
      M.Diagnostic{"entry_type", name, "entry `" ++ name ++ "` has type " ++ M.type_show(ty) ++ ", which does not fit the guest ABI: " ++ abi_rule()}

def entry_failure(runtime: Bool, +name: String, found: Maybe<&2, M.Ty>) -> M.Diagnostic:
  match runtime found:
    case False{} Some{+ty}:
      entry_type_failure(generic_types(4096n, [ty]), name, ty)
    case True{} Some{ty}:
      M.Diagnostic{"entry_let_type", name, "entry let `" ++ name ++ "` initializes a runtime value of type " ++ M.type_show(ty) ++ "; the guest ABI exports runtime-initialized values only as Unit, U32, F32 or Bool globals or as functions that fit it: " ++ abi_rule()}
    case _ None{}:
      M.Diagnostic{"entry_type", name, "entry `" ++ name ++ "` has a generic type, so it cannot be a Wasm export: " ++ abi_rule()}

def verify_entry(exported: Bool, runtime: Bool, name: String, found: Maybe<&2, M.Ty>) -> Result<&2, &2, M.Diagnostic, Unit>:
  match exported:
    case True{}:
      Done{Unit{}}
    case False{}:
      Fail{entry_failure(runtime, name, found)}

def verify_entries(entries: List<&2, Entry>, +exported: Set(), +types: Map<&2, M.Ty>) -> Result<&2, &2, M.Diagnostic, Unit>:
  match entries:
    case Nil{}:
      Done{Unit{}}
    case Entry{+name, runtime} <> tail:
      do Result<&2, &2, M.Diagnostic, Unit>:
        valid : Unit <- verify_entry(D.member(exported, name), runtime, name, Index.find(M.Ty, types, name))
        verify_entries(tail, exported, types)

# Every entry must be exported by the final checked module: export selection
# keeps an entry only when its final type fits the guest ABI.
def verify(entries: List<&2, Entry>, checked: M.CheckedModule) -> Result<&2, &2, M.Diagnostic, Unit>:
  M.CheckedModule{+constants, +functions, types, operations} = checked
  verify_entries(entries, exported_constants(constants, exported_functions(functions, Set.new())), constant_types(constants, function_types(functions, Map.new(&2, M.Ty))))

def has_exports(functions: List<&2, M.CheckedFunction>, constants: List<&2, M.CheckedConstant>) -> Bool:
  Bool.not(Nat.is_eq(Set.size(exported_constants(constants, exported_functions(functions, Set.new()))), 0n))

def require_exports_found(found: Bool) -> Result<&2, &2, M.Diagnostic, Unit>:
  match found:
    case True{}:
      Done{Unit{}}
    case False{}:
      Fail{M.Diagnostic{"no_entry", "entry", "a build needs at least one `entry const` or `entry let` declaration in the entry module; entries are the Wasm exports and the roots of dead-code elimination"}}

# A Wasm build without entrypoints has nothing to export or keep. Analysis
# alone may have no entries: it still checks every declaration.
def require_exports(checked: M.CheckedModule) -> Result<&2, &2, M.Diagnostic, Unit>:
  M.CheckedModule{constants, functions, types, operations} = checked
  require_exports_found(has_exports(functions, constants))
