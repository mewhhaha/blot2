import Base
import ./model.bend as M
import ./codegen_ir.bend as I
import ./wasm.bend as W
import ./groups.bend as G
import ./check_scheduler.bend as S
import ./native_cache_keys.bend as K
import ./native_response.bend as R

type Phase is Data:
  Codegen{}
  Inference{}

type Shape is Data:
  Tiny{}
  Uneven{}

type Options is Data:
  Options{phase: Phase, shape: Shape, grain: Nat, iterations: Nat}

type Bodies is Data:
  Bodies{core: M.Expr, runtime: I.Expr}

type Fixture is Data:
  Fixture{jobs: List<&2, W.CodegenJob>, tasks: List<&2, S.Task>}

def bind_bodies(previous: Bodies, +name: String, +value: U32) -> Bodies:
  Bodies{core, runtime} = previous
  Bodies{M.LetExpr{name, M.U32Expr{value}, core}, I.LetExpr{name, I.U32Expr{value}, runtime}}

def bodies(+depth: Nat, +value: U32) -> Bodies:
  match depth:
    case 0n:
      Bodies{M.U32Expr{value}, I.U32Expr{value}}
    case 1n+rest:
      bind_bodies(bodies(rest, value), "local_" ++ Nat.show(rest), value)

def body_depth(shape: Shape, index: Nat) -> Nat:
  match shape:
    case Tiny{}:
      0n
    case Uneven{}:
      Bool.pick(Nat, U32.is_eq(U32.and(U32.from_nat(index), 1), 0), 8n, 64n)

def fixture_entry(+index: Nat, body: Bodies, previous: Fixture) -> Fixture:
  Bodies{core, runtime} = body
  Fixture{jobs, tasks} = previous
  +name = "bench_" ++ Nat.show(index)
  +module = {M.Module{Nil{}, [M.Function{name, False{}, "value", Some{M.UnitTy{}}, Some{M.U32Ty{}}, core}], Nil{}, Nil{}} : M.Module}
  Fixture{W.CodegenJob{"fn:" ++ name, "value", runtime, Nil{}} <> jobs, S.Task{index, module, Nil{}, S.module_cost(module)} <> tasks}

def fixture_order(previous: Fixture) -> Fixture:
  Fixture{jobs, tasks} = previous
  Fixture{List.reverse(&2, W.CodegenJob, jobs), List.reverse(&2, S.Task, tasks)}

def fixture(remaining: Nat, +shape: Shape, +index: Nat, previous: Fixture) -> Fixture:
  match remaining:
    case 0n:
      fixture_order(previous)
    case 1n+rest:
      fixture(rest, shape, 1n+index, fixture_entry(index, bodies(body_depth(shape, index), U32.from_nat(index)), previous))

def same_fragment(left: W.Fragment, right: W.Fragment) -> Bool:
  match left right:
    case W.Bytes{a} W.Bytes{b}:
      K.same(a, b)
    case W.NamedCall{a} W.NamedCall{b}:
      M.name_equal(a, b)
    case W.Allocate{} W.Allocate{}:
      True{}
    case W.EntryIndex{a} W.EntryIndex{b}:
      M.name_equal(a, b)
    case W.ConstantReference{a} W.ConstantReference{b}:
      M.name_equal(a, b)
    case W.ConstructorIndex{a} W.ConstructorIndex{b}:
      M.name_equal(a, b)
    case W.OperationIndex{a} W.OperationIndex{b}:
      M.type_id_equal(a, b)
    case _ _:
      False{}

def same_fragments(left: List<&2, W.Fragment>, right: List<&2, W.Fragment>, valid: Bool) -> Bool:
  match left right valid:
    case _ _ False{}:
      False{}
    case Nil{} Nil{} True{}:
      True{}
    case a <> xs b <> ys True{}:
      same_fragments(xs, ys, same_fragment(a, b))
    case _ _ _:
      False{}

def same_entries(left: List<&2, W.EntryCode>, right: List<&2, W.EntryCode>, valid: Bool) -> Bool:
  match left right valid:
    case _ _ False{}:
      False{}
    case Nil{} Nil{} True{}:
      True{}
    case W.EntryCode{a, W.Code{af, al}} <> xs W.EntryCode{b, W.Code{bf, bl}} <> ys True{}:
      same_entries(xs, ys, Bool.and(M.name_equal(a, b), Bool.and(Nat.is_eq(al, bl), same_fragments(af, bf, True{}))))
    case _ _ _:
      False{}

def entry_result_same(result: Result<&2, &2, M.Diagnostic, List<&2, W.EntryCode>>, expected: List<&2, W.EntryCode>) -> Bool:
  match result:
    case Fail{error}:
      False{}
    case Done{entries}:
      same_entries(entries, expected, True{})

def source_functions(values: List<&2, M.CheckedFunction>, reversed: List<&2, M.Function>) -> List<&2, M.Function>:
  match values:
    case Nil{}:
      List.reverse(&2, M.Function, reversed)
    case M.CheckedFunction{function, signature, effects} <> tail:
      source_functions(tail, function <> reversed)

def outcome_key(outcome: S.Outcome) -> Result<&2, &2, M.Diagnostic, List<&2, U32>>:
  match outcome:
    case S.Outcome{position, Fail{error}}:
      Fail{error}
    case S.Outcome{position, Done{G.CheckedGroup{M.CheckedModule{Nil{}, +functions, Nil{}, Nil{}}, interfaces}}}:
      K.encode([K.Field{R.Natural{position}}, K.Functions{source_functions(functions, Nil{})}, K.Field{R.Functions{functions}}, K.Interfaces{interfaces}])
    case _:
      Fail{M.Diagnostic{"benchmark_fixture", "inference", "expected independent function-only modules"}}

def outcome_keys(outcomes: List<&2, S.Outcome>, reversed: List<&2, List<&2, U32>>) -> Result<&2, &2, M.Diagnostic, List<&2, List<&2, U32>>>:
  match outcomes:
    case Nil{}:
      Done{List.reverse(&2, List<&2, U32>, reversed)}
    case head <> tail:
      do Result<&2, &2, M.Diagnostic, List<&2, List<&2, U32>>>:
        key : List<&2, U32> <- outcome_key(head)
        outcome_keys(tail, key <> reversed)

def same_keys(left: List<&2, List<&2, U32>>, right: List<&2, List<&2, U32>>, valid: Bool) -> Bool:
  match left right valid:
    case _ _ False{}:
      False{}
    case Nil{} Nil{} True{}:
      True{}
    case a <> xs b <> ys True{}:
      same_keys(xs, ys, K.same(a, b))
    case _ _ _:
      False{}

def outcome_result_same(result: Result<&2, &2, M.Diagnostic, List<&2, List<&2, U32>>>, expected: List<&2, List<&2, U32>>) -> Bool:
  match result:
    case Fail{error}:
      False{}
    case Done{keys}:
      same_keys(keys, expected, True{})

def verified(valid: Bool) -> IO(Unit):
  match valid:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.die(Unit, 1, "parallel grain output differs from the complete ordered serial reference")

def required(-A: Data, result: Result<&2, &2, M.Diagnostic, A>) -> IO(A):
  match result:
    case Done{value}:
      IO.pure(A, value)
    case Fail{M.Diagnostic{code, subject, message}}:
      IO.die(A, 1, code ++ ": " ++ subject ++ ": " ++ message)

# IO.now is monotonic milliseconds in Bend 2.0.21. Each result is fully checked
# after its stop timestamp; fixture creation and reference compilation are untimed.
def time_codegen(iterations: Nat, +grain: Nat, +jobs: List<&2, W.CodegenJob>, +expected: List<&2, W.EntryCode>, elapsed: Nat) -> IO(Nat):
  match iterations:
    case 0n:
      IO.pure(Nat, elapsed)
    case 1n+rest:
      do IO<Nat>:
        start : Nat <- IO.now()
        compiled : Result<&2, &2, M.Diagnostic, List<&2, W.EntryCode>> = W.compile_entries_with_grain(grain, jobs)
        finish : Nat <- IO.now()
        verified(entry_result_same(compiled, expected))
        time_codegen(rest, grain, jobs, expected, Nat.add(elapsed, Nat.sub(finish, start)))

def time_inference(iterations: Nat, +grain: Nat, +tasks: List<&2, S.Task>, +expected: List<&2, List<&2, U32>>, elapsed: Nat) -> IO(Nat):
  match iterations:
    case 0n:
      IO.pure(Nat, elapsed)
    case 1n+rest:
      do IO<Nat>:
        start : Nat <- IO.now()
        checked : List<&2, S.Outcome> = S.check_batch_with_grain(tasks, grain)
        finish : Nat <- IO.now()
        verified(outcome_result_same(outcome_keys(checked, Nil{}), expected))
        time_inference(rest, grain, tasks, expected, Nat.add(elapsed, Nat.sub(finish, start)))

def measure(phase: Phase, grain: Nat, iterations: Nat, prepared: Fixture) -> IO(Nat):
  match phase prepared:
    case Codegen{} Fixture{+jobs, tasks}:
      do IO<Nat>:
        expected : List<&2, W.EntryCode> <- required(List<&2, W.EntryCode>, W.compile_entries_with_grain(Nat.read.max(), jobs))
        time_codegen(iterations, grain, jobs, expected, 0n)
    case Inference{} Fixture{jobs, +tasks}:
      do IO<Nat>:
        expected : List<&2, List<&2, U32>> <- required(List<&2, List<&2, U32>>, outcome_keys(S.check_batch_with_grain(tasks, Nat.read.max()), Nil{}))
        time_inference(iterations, grain, tasks, expected, 0n)

def phase_name(phase: Phase) -> String:
  match phase:
    case Codegen{}:
      "codegen"
    case Inference{}:
      "check"

def shape_name(shape: Shape) -> String:
  match shape:
    case Tiny{}:
      "tiny"
    case Uneven{}:
      "uneven"

def report(options: Options, elapsed: Nat) -> IO(Unit):
  Options{phase, shape, grain, iterations} = options
  IO.print("{\"phase\":\"" ++ phase_name(phase) ++ "\",\"shape\":\"" ++ shape_name(shape) ++ "\",\"grain\":" ++ Nat.show(grain) ++ ",\"iterations\":" ++ Nat.show(iterations) ++ ",\"elapsed_ms\":" ++ Nat.show(elapsed) ++ ",\"verified\":true}")

def run(+options: Options) -> IO(Unit):
  Options{phase, shape, grain, iterations} = options
  do IO<Unit>:
    elapsed : Nat <- measure(phase, grain, iterations, fixture(64n, shape, 0n, Fixture{Nil{}, Nil{}}))
    report(options, elapsed)

def phase_option(codegen: Bool, inference: Bool) -> Maybe<&2, Phase>:
  match codegen inference:
    case True{} _:
      Some{Codegen{}}
    case False{} True{}:
      Some{Inference{}}
    case _ _:
      None{}

def shape_option(tiny: Bool, uneven: Bool) -> Maybe<&2, Shape>:
  match tiny uneven:
    case True{} _:
      Some{Tiny{}}
    case False{} True{}:
      Some{Uneven{}}
    case _ _:
      None{}

def grain_option(serial: Bool, text: String) -> Maybe<&2, Nat>:
  match serial:
    case True{}:
      Some{Nat.read.max()}
    case False{}:
      Nat.read(text)

def parsed_options(phase: Maybe<&2, Phase>, shape: Maybe<&2, Shape>, grain: Maybe<&2, Nat>, iterations: Maybe<&2, Nat>) -> IO(Unit):
  match phase shape grain iterations:
    case Some{p} Some{s} Some{g} Some{1n+rest}:
      run(Options{p, s, g, 1n+rest})
    case _ _ _ _:
      IO.die(Unit, 2, "usage: parallel-grain-bench [--threads N] -- codegen|check tiny|uneven serial|GRAIN ITERATIONS (>0)")

def arguments(args: List<String>) -> IO(Unit):
  match args:
    case +phase <> +shape <> +grain <> iterations <> Nil{}:
      parsed_options(phase_option(M.name_equal(phase, "codegen"), M.name_equal(phase, "check")), shape_option(M.name_equal(shape, "tiny"), M.name_equal(shape, "uneven")), grain_option(M.name_equal(grain, "serial"), grain), Nat.read(iterations))
    case _:
      parsed_options(None{}, None{}, None{}, None{})

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)
