import { instantiateGuest } from "../../host/guest.ts";
import {
  compileAndRun,
  compileExpectedFailure,
  equal,
} from "./compile_helpers.ts";

const executable = Deno.args[0] ??
  new URL("../../compiler-goose/build/squidc-goose", import.meta.url).pathname;
const prelude = new URL("../../std/prelude.sq", import.meta.url).pathname;

Deno.test("standard operators come from prelude and legacy infix declarations stay rejected", async () => {
  await compileExpectedFailure(
    "io const answer = 20 >< 22\n",
    "unknown_operator",
    undefined,
    { prelude: "none" },
  );
  await compileExpectedFailure(
    "infixl 60 (+) = add\nio const answer = 20 + 22\n",
    "GPU_FRONTEND_SYNTAX_ERROR",
    undefined,
    { prelude: "none" },
  );
  await compileExpectedFailure(
    "io const answer = func () => return 20 + 22\n",
    "unknown_operator",
    undefined,
    { prelude: "none" },
  );
  await compileExpectedFailure(
    "func inc x => x\nio const answer = func () => return 40 |> inc\n",
    "unknown_operator",
    undefined,
    { prelude: "none" },
  );
  await compileAndRun(
    `func (+) (a: U32) -> (b: U32): U32 => @u32.add a b
func (|>) value -> f => @pipe value f
func inc (x: U32): U32 => x + 2
io const answer = func (): U32 => 40 |> inc
io const logic = func (): Bool => true and (not false)
`,
    (guest) => {
      equal(guest.call("answer", null), 42);
      equal(guest.call("logic", null), true);
    },
    { prelude: "none" },
  );
});

Deno.test("lexical precedence and associativity govern custom and prelude operators", async () => {
  await compileExpectedFailure(
    "io const bad = func () => 1 == 1 == true\n",
    "operator_associativity",
  );
  await compileExpectedFailure(
    "func id x => x\nio const bad = func () => 1 |> id <| 2\n",
    "operator_associativity",
  );
  await compileAndRun(
    `func (++) (a: U32) -> (b: U32): U32 => a * 10 + b
func (*+) (a: U32) -> (b: U32): U32 => a * b + 1
func (**) (base: U32) -> (exp: U32): U32 =>
  let acc = 1
  for _ in 0..exp:
    acc := self * base
  return acc
func inc (x: U32): U32 => x + 1
func dbl (x: U32): U32 => x * 2
func as_u32 (b: Bool): U32 => if b then 1 else 0
io const prec_test = func (): U32 => 1 ++ 2 *+ 3
io const pow_right = func (): U32 => 2 ** 3 ** 2
io const mul_pow = func (): U32 => 3 * 2 ** 3
io const pipe_left = func (): U32 => 5 |> inc |> dbl
io const pipe_right = func (): U32 => dbl <| inc <| 5
io const not_pipe = func (): U32 => not false |> as_u32
io const not_cmp = func (): Bool => not 1 == 2
`,
    (guest) => {
      equal(guest.call("prec_test", null), 17);
      equal(guest.call("pow_right", null), 512);
      equal(guest.call("mul_pow", null), 24);
      equal(guest.call("pipe_left", null), 12);
      equal(guest.call("pipe_right", null), 12);
      equal(guest.call("not_pipe", null), 1);
      equal(guest.call("not_cmp", null), true);
    },
  );
});

Deno.test("operators work as first-class values, closures, and support local shadowing", async () => {
  await compileAndRun(
    `func fold (f: U32 -> U32 -> U32) -> (init: U32) -> (xs: #[U32]): U32 =>
  let acc = init
  for x in xs:
    acc := f self x
  return acc
func make_op (k: U32): U32 -> U32 -> U32 => func a -> b => a * k + b
const (><) = make_op 10
io const hof_sum = func (): U32 => fold (+) 0 #[10, 20, 12]
io const partial_op = func (): U32 =>
  let add10 = (+) 10
  return add10 32
io const ignore_named_add = func (): U32 =>
  let add = func left -> right => @u32.sub left right
  return 20 + 22
io const local_shadow = func (): U32 =>
  let (+) = func (a: U32) -> (b: U32): U32 => @u32.mul a b
  return 6 + 7
io const closure_op = func (): U32 => 4 >< 2
`,
    (guest) => {
      equal(guest.call("hof_sum", null), 42);
      equal(guest.call("partial_op", null), 42);
      equal(guest.call("ignore_named_add", null), 42);
      equal(guest.call("local_shadow", null), 42);
      equal(guest.call("closure_op", null), 42);
    },
  );
});

Deno.test("custom @type.call operators dispatch traits and associated methods, and own operators move storage", async () => {
  await compileAndRun(
    `func (++) left -> right => @type.call "concat" left right
type Combine a is trait = { combine: a -> a -> a }
type Box is data = $Box U32
const Box.Combine: Combine Box = { combine: func ($Box a) -> ($Box b) => $Box (a + b) }
func (<+>) left -> right => @type.call "combine" left right
func combine3 (x: a): a where { Combine a } => x <+> x <+> x
func (<<+) (xs: own #[U32]) -> (x: U32): #[U32] => xs.push x
type Tick is effect = U32 -> Unit
func check_eq (x: a) -> (y: a): Unit ! { Tick } where { Combine a } =>
  use Tick 1
  return ()

io const arr_cat = func (): U32 =>
  let out = #[10, 20] ++ #[12]
  return out[0] + out[1] + out[2]
io const trait_op = func (): U32 =>
  let $Box v = combine3 ($Box 14)
  return v
io const own_op = func (): U32 =>
  let buf: #[U32] = #[]
  buf := self <<+ 10 <<+ 32
  return buf[0] + buf[1]
io const effectful_arg_op = func (): U32 =>
  let count = 0
  handler on_tick: Tick => func (n: U32) =>
    count := self + n
    return ()
  let _ = (func (): Unit ! { Tick } =>
    use check_eq ($Box (40 + 2)) (($Box 20) <+> ($Box 22))
    return ()
  ).handle on_tick
    .run ()
  return count
`,
    (guest) => {
      equal(guest.call("arr_cat", null), 42);
      equal(guest.call("trait_op", null), 42);
      equal(guest.call("own_op", null), 42);
      equal(guest.call("effectful_arg_op", null), 1);
    },
  );
});

Deno.test("custom operators support cross-module import, alias, re-export, and qualified lookup", async () => {
  const dir = await Deno.makeTempDir({
    dir: new URL("../../build", import.meta.url).pathname,
    prefix: "squid-custom-ops-",
  });
  try {
    await Deno.writeTextFile(
      `${dir}/ops.sq`,
      `func (++) (a: U32) -> (b: U32): U32 => a * 10 + b
func (+~) (a: U32) -> (b: U32): U32 => a + b + 1
func (<+>) left -> right => @type.call "concat" left right
`,
    );
    await Deno.writeTextFile(
      `${dir}/reexport.sq`,
      `export { (++), (<+>) } from "./ops"\n`,
    );
    await Deno.writeTextFile(
      `${dir}/main.sq`,
      `import { (++), (<+>) } from "./reexport"
import { (+~) as (+|) } from "./ops"
import * as ops from "./ops"
io const a = func (): U32 => 4 ++ 2
io const b = func (): U32 => 20 +| 21
io const c = func (): U32 => ops.(++) 4 2
io const d = func (): U32 =>
  let out = #[10, 20] <+> #[12]
  return out[0] + out[1] + out[2]
`,
    );
    const output = `${dir}/program.wasm`;
    const result = await new Deno.Command(executable, {
      args: ["build", `${dir}/main.sq`, output, "--prelude", prelude],
      stdout: "piped",
      stderr: "piped",
    }).output();
    const stdout = new TextDecoder().decode(result.stdout);
    const stderr = new TextDecoder().decode(result.stderr);
    if (!result.success) throw new Error(`${stdout}\n${stderr}`);
    const bytes = await Deno.readFile(output);
    const guest = await instantiateGuest(bytes);
    try {
      equal(guest.call("a", null), 42);
      equal(guest.call("b", null), 42);
      equal(guest.call("c", null), 42);
      equal(guest.call("d", null), 42);
    } finally {
      guest.dispose();
    }
  } finally {
    await Deno.remove(dir, { recursive: true });
  }
});

Deno.test("backtick infix functions support simple, qualified, closure, own, and precedence rules", async () => {
  await compileExpectedFailure(
    "func f (a: U32) -> (b: U32): U32 => a + b\nio const bad = func (): U32 => 1 `f 2\n",
    "GPU_FRONTEND_SYNTAX_ERROR",
  );
  await compileExpectedFailure(
    "io const bad = func (): U32 => 1 `` 2\n",
    "GPU_FRONTEND_SYNTAX_ERROR",
  );
  await compileAndRun(
    `func blend (a: U32) -> (b: U32): U32 => a * 10 + b
func sub_u (a: U32) -> (b: U32): U32 => a - b
func inc (x: U32): U32 => x + 1
func (**) (base: U32) -> (exp: U32): U32 =>
  let acc = 1
  for _ in 0..exp:
    acc := self * base
  return acc
func push_in (xs: own #[U32]) -> (x: U32): #[U32] => xs.push x
func eq_u (a: U32) -> (b: U32): Bool => a == b
func apply_fn (x: U32) -> (f: U32 -> U32): U32 => f x

io const basic = func (): U32 => 4 \`blend\` 2
io const left_assoc = func (): U32 => 10 \`sub_u\` 3 \`sub_u\` 2
io const prec_over_mul = func (): U32 => 2 * 1 \`blend\` 5 + 1
io const prec_over_pow = func (): U32 => 2 ** 1 \`U32.add\` 2
io const looser_than_app = func (): U32 => inc 3 \`blend\` inc 1
io const type_qual = func (): U32 => 40 \`U32.add\` 2 \`U32.bit_or\` 0
io const type_qual_f32 = func (): F32 => 50.0 \`F32.min\` 42.0 \`F32.max\` 10.0
io const local_closure = func (): U32 =>
  let k = 10
  let comb = func (a: U32) -> (b: U32): U32 => a * k + b
  return 4 \`comb\` 2
io const own_backtick = func (): U32 =>
  let xs: #[U32] = #[10]
  xs := self \`push_in\` 32
  return xs[0] + xs[1]
io const not_backtick = func (): Bool => not 1 \`eq_u\` 2 and true
io const rhs_lambda = func (): U32 => 21 \`apply_fn\` func x => x * 2
io const in_array = func (): U32 =>
  let xs = #[1 \`blend\` 2, 3 \`blend\` 0]
  return xs[0] + xs[1]
`,
    (guest) => {
      equal(guest.call("basic", null), 42);
      equal(guest.call("left_assoc", null), 5);
      equal(guest.call("prec_over_mul", null), 31);
      equal(guest.call("prec_over_pow", null), 8);
      equal(guest.call("looser_than_app", null), 42);
      equal(guest.call("type_qual", null), 42);
      equal(guest.call("type_qual_f32", null), 42);
      equal(guest.call("local_closure", null), 42);
      equal(guest.call("own_backtick", null), 42);
      equal(guest.call("not_backtick", null), true);
      equal(guest.call("rhs_lambda", null), 42);
      equal(guest.call("in_array", null), 42);
    },
  );
  const dir = await Deno.makeTempDir({
    dir: new URL("../../build", import.meta.url).pathname,
    prefix: "squid-backtick-mod-",
  });
  try {
    await Deno.writeTextFile(
      `${dir}/ops.sq`,
      `func combine (a: U32) -> (b: U32): U32 => a * 10 + b\n`,
    );
    await Deno.writeTextFile(
      `${dir}/main.sq`,
      `import * as ops from "./ops"
io const answer = func (): U32 => 4 \`ops.combine\` 2
`,
    );
    const output = `${dir}/program.wasm`;
    const result = await new Deno.Command(executable, {
      args: ["build", `${dir}/main.sq`, output, "--prelude", prelude],
      stdout: "piped",
      stderr: "piped",
    }).output();
    const stdout = new TextDecoder().decode(result.stdout);
    const stderr = new TextDecoder().decode(result.stderr);
    if (!result.success) throw new Error(`${stdout}\n${stderr}`);
    const bytes = await Deno.readFile(output);
    const guest = await instantiateGuest(bytes);
    try {
      equal(guest.call("answer", null), 42);
    } finally {
      guest.dispose();
    }
  } finally {
    await Deno.remove(dir, { recursive: true });
  }
});
