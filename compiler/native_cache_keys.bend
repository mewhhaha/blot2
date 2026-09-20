import Base
import ./model.bend as M
import ./cst.bend as C
import ./lower.bend as L
import ./source_types.bend as T
import ./operators.bend as O
import ./groups.bend as G
import ./dependency.bend as D
import ./codegen_ir.bend as I
import ./wasm.bend as W
import ./native_response.bend as R

# Exact, length-delimited keys: no hash collision can admit stale compiler work.
# The response encoder's Result is used directly; its public diagnostic fallback
# is a wire convenience, never a valid cache key.
type Work is Data:
  Field{value: R.Work}
  OperationGlobal{identity: M.TypeId}
  RecordConstructorGlobal{fields: List<&2, String>}
  Globals{values: List<&2, L.Global>}
  Headers{values: List<&2, T.Header>}
  Fixities{values: List<&2, O.Fixity>}
  Locals{values: List<&2, L.Local>}
  OptionalNatural{value: Maybe<&2, Nat>}
  Functions{values: List<&2, M.Function>}
  Constants{values: List<&2, M.Constant>}
  DataTypes{values: List<&2, M.DataType>}
  Constructors{values: List<&2, M.Constructor>}
  Identities{values: List<&2, M.TypeId>}
  DependencyNodes{values: List<&2, D.Node>}
  Usages{values: List<&2, G.DeclarationUsage>}
  TypeDependencies{values: List<&2, G.TypeDependencies>}
  Interfaces{values: List<&2, G.Interface>}
  Runtime{value: I.Expr}
  Runtimes{values: List<&2, I.Expr>}
  OptionalRuntime{value: Maybe<&2, I.Expr>}
  RuntimeArms{values: List<&2, M.MatchArm<I.Expr>>}

def flag(value: Bool) -> Work:
  Field{R.Word{R.bool_word(value)}}

def global_kind(value: L.GlobalKind) -> Work:
  match value:
    case L.ConstantName{}:
      Field{R.Word{0}}
    case L.FunctionName{}:
      Field{R.Word{1}}
    case L.ConstructorName{}:
      Field{R.Word{2}}
    case L.OperationName{identity}:
      OperationGlobal{identity}
    case L.RecordConstructorName{fields}:
      RecordConstructorGlobal{fields}

def association(value: O.Associativity) -> Work:
  match value:
    case O.Left{}:
      Field{R.Word{0}}
    case O.Right{}:
      Field{R.Word{1}}
    case O.NonAssociative{}:
      Field{R.Word{2}}

def interface_kind(value: G.InterfaceKind) -> Work:
  match value:
    case G.FunctionInterface{}:
      Field{R.Word{0}}
    case G.ConstantInterface{}:
      Field{R.Word{1}}

def flatten(fuel: Nat, pending: List<&2, Work>, reversed: List<&2, R.Work>) -> Result<&2, &2, M.Diagnostic, List<&2, R.Work>>:
  match fuel pending:
    case _ Nil{}:
      Done{List.reverse(&2, R.Work, reversed)}
    case 0n _:
      Fail{M.Diagnostic{"cache_key_complexity", "native_session", "cache key traversal exceeded its bound"}}
    case 1n+rest Field{value} <> tail:
      flatten(rest, tail, value <> reversed)
    case 1n+rest OperationGlobal{identity} <> tail:
      flatten(rest, Field{R.Word{3}} <> Field{R.Identity{identity}} <> tail, reversed)
    case 1n+rest RecordConstructorGlobal{fields} <> tail:
      flatten(rest, Field{R.Word{4}} <> Field{R.Strings{fields}} <> tail, reversed)
    case 1n+rest Globals{Nil{}} <> tail:
      flatten(rest, Field{R.Word{0}} <> tail, reversed)
    case 1n+rest Globals{L.Global{source, core, kind} <> following} <> tail:
      flatten(rest, Field{R.Word{1}} <> Field{R.Text{source}} <> Field{R.Text{core}} <> global_kind(kind) <> Globals{following} <> tail, reversed)
    case 1n+rest Headers{Nil{}} <> tail:
      flatten(rest, Field{R.Word{0}} <> tail, reversed)
    case 1n+rest Headers{T.Header{source, identity, arity} <> following} <> tail:
      flatten(rest, Field{R.Word{1}} <> Field{R.Text{source}} <> Field{R.Identity{identity}} <> Field{R.Natural{arity}} <> Headers{following} <> tail, reversed)
    case 1n+rest Fixities{Nil{}} <> tail:
      flatten(rest, Field{R.Word{0}} <> tail, reversed)
    case 1n+rest Fixities{O.Fixity{name, named, precedence, associativity, target} <> following} <> tail:
      flatten(rest, Field{R.Word{1}} <> Field{R.Text{name}} <> flag(named) <> Field{R.Word{precedence}} <> association(associativity) <> Field{R.Expression{target}} <> Fixities{following} <> tail, reversed)
    case 1n+rest Locals{Nil{}} <> tail:
      flatten(rest, Field{R.Word{0}} <> tail, reversed)
    case 1n+rest Locals{L.Local{source, core} <> following} <> tail:
      flatten(rest, Field{R.Word{1}} <> Field{R.Text{source}} <> Field{R.Text{core}} <> Locals{following} <> tail, reversed)
    case 1n+rest OptionalNatural{None{}} <> tail:
      flatten(rest, Field{R.Word{0}} <> tail, reversed)
    case 1n+rest OptionalNatural{Some{value}} <> tail:
      flatten(rest, Field{R.Word{1}} <> Field{R.Natural{value}} <> tail, reversed)
    case 1n+rest Functions{Nil{}} <> tail:
      flatten(rest, Field{R.Word{0}} <> tail, reversed)
    case 1n+rest Functions{M.Function{name, exported, parameter, p, r, body} <> following} <> tail:
      flatten(rest, Field{R.Word{1}} <> Field{R.Text{name}} <> flag(exported) <> Field{R.Text{parameter}} <> Field{R.OptionalType{p}} <> Field{R.OptionalType{r}} <> Field{R.Expression{body}} <> Functions{following} <> tail, reversed)
    case 1n+rest Constants{Nil{}} <> tail:
      flatten(rest, Field{R.Word{0}} <> tail, reversed)
    case 1n+rest Constants{M.Constant{name, exported, annotation, value} <> following} <> tail:
      flatten(rest, Field{R.Word{1}} <> Field{R.Text{name}} <> flag(exported) <> Field{R.OptionalType{annotation}} <> Field{R.Expression{value}} <> Constants{following} <> tail, reversed)
    case 1n+rest DataTypes{Nil{}} <> tail:
      flatten(rest, Field{R.Word{0}} <> tail, reversed)
    case 1n+rest DataTypes{M.DataType{identity, parameters, constructors} <> following} <> tail:
      flatten(rest, Field{R.Word{1}} <> Field{R.Identity{identity}} <> Field{R.Natural{parameters}} <> Constructors{constructors} <> DataTypes{following} <> tail, reversed)
    case 1n+rest Constructors{Nil{}} <> tail:
      flatten(rest, Field{R.Word{0}} <> tail, reversed)
    case 1n+rest Constructors{M.Constructor{name, payload} <> following} <> tail:
      flatten(rest, Field{R.Word{1}} <> Field{R.Text{name}} <> Field{R.OptionalType{payload}} <> Constructors{following} <> tail, reversed)
    case 1n+rest Identities{Nil{}} <> tail:
      flatten(rest, Field{R.Word{0}} <> tail, reversed)
    case 1n+rest Identities{head <> following} <> tail:
      flatten(rest, Field{R.Word{1}} <> Field{R.Identity{head}} <> Identities{following} <> tail, reversed)
    case 1n+rest DependencyNodes{Nil{}} <> tail:
      flatten(rest, Field{R.Word{0}} <> tail, reversed)
    case 1n+rest DependencyNodes{D.Node{name, references, lambdas} <> following} <> tail:
      flatten(rest, Field{R.Word{1}} <> Field{R.Text{name}} <> Field{R.Strings{references}} <> Field{R.Naturals{lambdas}} <> DependencyNodes{following} <> tail, reversed)
    case 1n+rest Usages{Nil{}} <> tail:
      flatten(rest, Field{R.Word{0}} <> tail, reversed)
    case 1n+rest Usages{G.DeclarationUsage{name, G.Usage{nominals}} <> following} <> tail:
      flatten(rest, Field{R.Word{1}} <> Field{R.Text{name}} <> Identities{nominals} <> Usages{following} <> tail, reversed)
    case 1n+rest TypeDependencies{Nil{}} <> tail:
      flatten(rest, Field{R.Word{0}} <> tail, reversed)
    case 1n+rest TypeDependencies{G.TypeDependencies{identity, references} <> following} <> tail:
      flatten(rest, Field{R.Word{1}} <> Field{R.Identity{identity}} <> Identities{references} <> TypeDependencies{following} <> tail, reversed)
    case 1n+rest Interfaces{Nil{}} <> tail:
      flatten(rest, Field{R.Word{0}} <> tail, reversed)
    case 1n+rest Interfaces{G.Interface{name, kind, template, parameters, effects} <> following} <> tail:
      flatten(rest, Field{R.Word{1}} <> Field{R.Text{name}} <> interface_kind(kind) <> Field{R.TypeValue{template}} <> Field{R.Natural{parameters}} <> Field{R.Effects{effects}} <> Interfaces{following} <> tail, reversed)
    case 1n+rest Runtime{I.UnitExpr{}} <> tail:
      flatten(rest, Field{R.Word{0}} <> tail, reversed)
    case 1n+rest Runtime{I.U32Expr{value}} <> tail:
      flatten(rest, Field{R.Word{1}} <> Field{R.Word{value}} <> tail, reversed)
    case 1n+rest Runtime{I.BoolExpr{value}} <> tail:
      flatten(rest, Field{R.Word{2}} <> flag(value) <> tail, reversed)
    case 1n+rest Runtime{I.LocalExpr{name}} <> tail:
      flatten(rest, Field{R.Word{3}} <> Field{R.Text{name}} <> tail, reversed)
    case 1n+rest Runtime{I.ConstantExpr{name}} <> tail:
      flatten(rest, Field{R.Word{4}} <> Field{R.Text{name}} <> tail, reversed)
    case 1n+rest Runtime{I.ClosureExpr{key, captures}} <> tail:
      flatten(rest, Field{R.Word{5}} <> Field{R.Text{key}} <> Field{R.Strings{captures}} <> tail, reversed)
    case 1n+rest Runtime{I.ConstructExpr{constructor, payload}} <> tail:
      flatten(rest, Field{R.Word{6}} <> Field{R.Text{constructor}} <> OptionalRuntime{payload} <> tail, reversed)
    case 1n+rest Runtime{I.ApplyExpr{callee, argument}} <> tail:
      flatten(rest, Field{R.Word{7}} <> Runtime{callee} <> Runtime{argument} <> tail, reversed)
    case 1n+rest Runtime{I.CallExpr{key, argument}} <> tail:
      flatten(rest, Field{R.Word{8}} <> Field{R.Text{key}} <> Runtime{argument} <> tail, reversed)
    case 1n+rest Runtime{I.ScalarExpr{operator, left, right}} <> tail:
      flatten(rest, Field{R.Word{9}} <> Field{R.Operator{operator}} <> Runtime{left} <> Runtime{right} <> tail, reversed)
    case 1n+rest Runtime{I.LetExpr{name, value, body}} <> tail:
      flatten(rest, Field{R.Word{10}} <> Field{R.Text{name}} <> Runtime{value} <> Runtime{body} <> tail, reversed)
    case 1n+rest Runtime{I.IfExpr{condition, consequent, alternative}} <> tail:
      flatten(rest, Field{R.Word{11}} <> Runtime{condition} <> Runtime{consequent} <> Runtime{alternative} <> tail, reversed)
    case 1n+rest Runtime{I.SequenceExpr{first, next}} <> tail:
      flatten(rest, Field{R.Word{12}} <> Runtime{first} <> Runtime{next} <> tail, reversed)
    case 1n+rest Runtime{I.MatchExpr{values, arms}} <> tail:
      flatten(rest, Field{R.Word{13}} <> Runtimes{values} <> RuntimeArms{arms} <> tail, reversed)
    case 1n+rest Runtime{I.GuardExpr{pattern, value, alternative, body}} <> tail:
      flatten(rest, Field{R.Word{14}} <> Field{R.Pattern{pattern}} <> Runtime{value} <> Runtime{alternative} <> Runtime{body} <> tail, reversed)
    case 1n+rest Runtime{I.BlockExpr{label, body}} <> tail:
      flatten(rest, Field{R.Word{15}} <> Field{R.Natural{label}} <> Runtime{body} <> tail, reversed)
    case 1n+rest Runtime{I.ReturnExpr{label, value}} <> tail:
      flatten(rest, Field{R.Word{16}} <> Field{R.Natural{label}} <> Runtime{value} <> tail, reversed)
    case 1n+rest Runtime{I.F32Expr{value}} <> tail:
      flatten(rest, Field{R.Word{17}} <> Field{R.Word{F32.bits(value)}} <> tail, reversed)
    case 1n+rest Runtime{I.UnaryExpr{operator, value}} <> tail:
      flatten(rest, Field{R.Word{18}} <> Field{R.UnaryOperator{operator}} <> Runtime{value} <> tail, reversed)
    case 1n+rest Runtime{I.ProviderExpr{identity, implementation}} <> tail:
      flatten(rest, Field{R.Word{19}} <> Field{R.Identity{identity}} <> Runtime{implementation} <> tail, reversed)
    case 1n+rest Runtime{I.HandleExpr{provider, body}} <> tail:
      flatten(rest, Field{R.Word{20}} <> Runtime{provider} <> Runtime{body} <> tail, reversed)
    case 1n+rest Runtime{I.InvokeOperationExpr{identity, argument}} <> tail:
      flatten(rest, Field{R.Word{21}} <> Field{R.Identity{identity}} <> Runtime{argument} <> tail, reversed)
    case 1n+rest Runtime{I.PanicExpr{message}} <> tail:
      flatten(rest, Field{R.Word{22}} <> Field{R.Text{message}} <> tail, reversed)
    case 1n+rest Runtime{I.ProductExpr{elements}} <> tail:
      flatten(rest, Field{R.Word{23}} <> Runtimes{elements} <> tail, reversed)
    case 1n+rest Runtime{I.ProjectExpr{value, index}} <> tail:
      flatten(rest, Field{R.Word{24}} <> Runtime{value} <> Field{R.Natural{index}} <> tail, reversed)
    case 1n+rest Runtime{I.ArrayExpr{elements}} <> tail:
      flatten(rest, Field{R.Word{25}} <> Runtimes{elements} <> tail, reversed)
    case 1n+rest Runtime{I.ArrayGetExpr{array, index}} <> tail:
      flatten(rest, Field{R.Word{26}} <> Runtime{array} <> Runtime{index} <> tail, reversed)
    case 1n+rest Runtime{I.ArraySetExpr{array, index, value}} <> tail:
      flatten(rest, Field{R.Word{27}} <> Runtime{array} <> Runtime{index} <> Runtime{value} <> tail, reversed)
    case 1n+rest Runtime{I.ArrayLengthExpr{array}} <> tail:
      flatten(rest, Field{R.Word{28}} <> Runtime{array} <> tail, reversed)
    case 1n+rest Runtimes{Nil{}} <> tail:
      flatten(rest, Field{R.Word{0}} <> tail, reversed)
    case 1n+rest Runtimes{head <> following} <> tail:
      flatten(rest, Field{R.Word{1}} <> Runtime{head} <> Runtimes{following} <> tail, reversed)
    case 1n+rest OptionalRuntime{None{}} <> tail:
      flatten(rest, Field{R.Word{0}} <> tail, reversed)
    case 1n+rest OptionalRuntime{Some{value}} <> tail:
      flatten(rest, Field{R.Word{1}} <> Runtime{value} <> tail, reversed)
    case 1n+rest RuntimeArms{Nil{}} <> tail:
      flatten(rest, Field{R.Word{0}} <> tail, reversed)
    case 1n+rest RuntimeArms{M.MatchArm{patterns, body} <> following} <> tail:
      flatten(rest, Field{R.Word{1}} <> Field{R.Patterns{patterns}} <> Runtime{body} <> RuntimeArms{following} <> tail, reversed)

def encode_limited(fuel: Nat, pending: List<&2, Work>, room: Nat) -> Result<&2, &2, M.Diagnostic, List<&2, U32>>:
  do Result<&2, &2, M.Diagnostic, List<&2, U32>>:
    fields : List<&2, R.Work> <- flatten(fuel, pending, Nil{})
    R.encode_work(Nat.read.max(), fields, room, Nil{})

def encode(pending: List<&2, Work>) -> Result<&2, &2, M.Diagnostic, List<&2, U32>>:
  encode_limited(Nat.read.max(), pending, U32.to_nat(16777216))

def same_go(left: List<&2, U32>, right: List<&2, U32>, equal: Bool) -> Bool:
  match left right equal:
    case _ _ False{}:
      False{}
    case Nil{} Nil{} True{}:
      True{}
    case a <> xs b <> ys True{}:
      same_go(xs, ys, U32.is_eq(a, b))
    case _ _ _:
      False{}

def same(left: List<&2, U32>, right: List<&2, U32>) -> Bool:
  same_go(left, right, True{})

# Retain source trees directly: encoding every unchanged CST into words was
# more expensive than the compiler work it avoided. Equality remains exact.
type CstComparison is Data:
  NodePair{left: C.Cst, right: C.Cst}
  ChildrenPair{left: List<&2, C.Cst>, right: List<&2, C.Cst>}

def compare_cst(fuel: Nat, pending: List<&2, CstComparison>, equal: Bool) -> Bool:
  match fuel pending equal:
    case _ _ False{}:
      False{}
    case _ Nil{} True{}:
      True{}
    case 0n _ _:
      False{}
    case 1n+rest NodePair{C.Cst{ak, af, at, ao, ac}, C.Cst{bk, bf, bt, bo, bc}} <> tail True{}:
      compare_cst(rest, ChildrenPair{ac, bc} <> tail, Bool.and(Bool.and(M.name_equal(ak, bk), M.name_equal(af, bf)), Bool.and(M.name_equal(at, bt), Nat.is_eq(ao, bo))))
    case 1n+rest ChildrenPair{Nil{}, Nil{}} <> tail True{}:
      compare_cst(rest, tail, True{})
    case 1n+rest ChildrenPair{a <> xs, b <> ys} <> tail True{}:
      compare_cst(rest, NodePair{a, b} <> ChildrenPair{xs, ys} <> tail, True{})
    case _ _ _:
      False{}

def same_cst(left: C.Cst, right: C.Cst) -> Bool:
  compare_cst(Nat.read.max(), [NodePair{left, right}], True{})

def scope(context: L.Context) -> Result<&2, &2, M.Diagnostic, List<&2, U32>>:
  L.Context{globals, headers, fixities, locals, return_label} = context
  encode([Globals{Map.values(&2, L.Global, globals)}, Headers{Map.values(&2, T.Header, headers)}, Fixities{fixities}, Locals{locals}, OptionalNatural{return_label}])

def module(module: M.Module) -> Result<&2, &2, M.Diagnostic, List<&2, U32>>:
  M.Module{constants, functions, types, operations} = module
  encode([Constants{constants}, Functions{functions}, DataTypes{types}, Field{R.Operations{operations}}])

def planning(plan: G.Planning) -> Result<&2, &2, M.Diagnostic, List<&2, U32>>:
  G.Planning{nodes, usages, types} = plan
  encode([DependencyNodes{nodes}, Usages{usages}, TypeDependencies{types}])

def interfaces(values: List<&2, G.Interface>) -> Result<&2, &2, M.Diagnostic, List<&2, U32>>:
  encode([Interfaces{values}])

def entry(job: W.CodegenJob) -> Result<&2, &2, M.Diagnostic, List<&2, U32>>:
  W.CodegenJob{key, parameter, body, captures} = job
  encode([Field{R.Text{key}}, Field{R.Text{parameter}}, Runtime{body}, Field{R.Strings{captures}}])
