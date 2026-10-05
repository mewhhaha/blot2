import { rejects, throws } from "node:assert/strict";
import { instantiateGuest } from "../../compiler/guest.ts";
import {
  compileAndRun,
  equal,
} from "./compile_helpers.ts";
type Program = {
  name: string;
  source: string;
  expected: number;
  constantCall?: string;
  const_steps?: bigint;
  calls?: readonly (readonly [number, number])[];
};

// Reproduce source positions that previously made an inner do label equal a
// generated loop label. The frontend reserves offset zero for an empty prelude.
function collidingDo(
  prefix: string,
  slot: number,
  suffix: string,
  indentation = "    ",
): string {
  const oldLoopLabel = (prefix.indexOf("for ") + 1) * 16 + slot;
  const beforeDo = indentation + "//";
  const afterComment = "\n" + indentation + "let local = ";
  const padding = oldLoopLabel - 1 - prefix.length - beforeDo.length -
    afterComment.length;
  return prefix + beforeDo + "x".repeat(padding) + afterComment + "do:\n" +
    suffix;
}

const programs: readonly Program[] = [
  {
    name: "replies resume the computation and completion sees its result",
    source: `
type Validate is effect = { check: U32 -> U32 }
const checked = fn computation => do:
  for request in @requests computation:
    case request of
      effect Validate.check value =>
        yield @u32.add value 1
      complete value =>
        return value
const calculation = @computation (fn () => do:
  use first <- Validate.check 19
  use second <- Validate.check 21
  return @u32.add first second
)
entry const answer = fn () => checked calculation
`,
    expected: 42,
  },
  {
    name: "return cancels helper calls, later loop iterations and the suffix",
    source: `
type Validate is effect = { check: U32 -> U32 }
const helper = fn value => do:
  use reply <- Validate.check value
  if @u32.eq value 2:
    return @panic "helper continued after cancellation"
  return reply
const checked = fn computation => do:
  for request in @requests computation:
    case request of
      effect Validate.check value =>
        if @u32.eq value 2:
          return 42
        yield value
      complete value =>
        return value
const calculation = @computation (fn () => do:
  for index in 0 .. 4:
    use helper index
    if @u32.eq index 2:
      @panic "loop continued after cancellation"
  return @panic "computation suffix ran after cancellation"
)
entry const answer = fn () => checked calculation
`,
    expected: 42,
  },
  {
    name: "cancellation skips array allocation and generator construction",
    source: `
type Validate is effect = { check: U32 -> U32 }
const checked = fn computation => do:
  for request in @requests computation:
    case request of
      effect Validate.check value =>
        return 21
      complete value =>
        return value
const make_generator = fn () => do:
  use Validate.check 0
  return @panic "generator construction continued"
entry const answer = fn () => do:
  let count = checked (@computation (fn () =>
    @array.length (@array.generate (Validate.check 0) (@panic "generator evaluated"))
  ))
  let generator = checked (@computation (fn () =>
    @array.length (@array.generate 2 (make_generator ()))
  ))
  return @u32.add count generator
`,
    expected: 42,
  },
  {
    name: "cancelled demand forcing remains suspended for a later handler",
    source: `
type Validate is effect = { check: U32 -> U32 }
const keep = fn ~value => fn () => @force value
const checked = fn stop => fn computation => do:
  for request in @requests computation:
    case request of
      effect Validate.check value =>
        if @u32.eq stop 1:
          return 40
        yield 42
      complete value =>
        return value
entry const answer = fn () => do:
  let delayed = keep (Validate.check 0)
  let calculation = @computation (fn () => delayed ())
  let cancelled = checked 1 calculation
  let completed = checked 0 calculation
  return @u32.add cancelled completed
`,
    expected: 82,
  },
  {
    name:
      "first-class operation values keep their identity through helper calls",
    source: `
type Validate is effect = { check: U32 -> U32 }
const invoke = fn operation => operation 40
const selected = Validate.check
const checked = fn computation => do:
  for request in @requests computation:
    case request of
      effect Validate.check value =>
        yield @u32.add value 2
      complete value =>
        return value
entry const answer = fn () => checked (@computation (fn () => invoke selected))
`,
    expected: 42,
  },
  {
    name:
      "break cancels the computation and exposes successor state to the suffix",
    source: `
type Validate is effect = { check: U32 -> U32 }
const checked = fn computation => do:
  let count = 10
  for request in @requests computation:
    case request of
      effect Validate.check value =>
        count := @u32.add self 1
        if @u32.eq value 0:
          break
        yield value
      complete value =>
        return value
  return @u32.add count 30
const calculation = @computation (fn () => do:
  use Validate.check 40
  use Validate.check 0
  return @panic "break resumed the computation"
)
entry const answer = fn () => checked calculation
`,
    expected: 42,
  },
  {
    name: "successive replies and completion share the handler's carried state",
    source: `
type Validate is effect = { check: U32 -> U32 }
const checked = fn computation => do:
  let count = 0
  for request in @requests computation:
    case request of
      effect Validate.check value =>
        count := @u32.add self 1
        yield @u32.add value count
      complete value =>
        return @u32.add value count
const calculation = @computation (fn () => do:
  use first <- Validate.check 20
  use second <- Validate.check 20
  return @u32.add first second
)
entry const answer = fn () => checked calculation
`,
    expected: 45,
  },
  {
    name: "a completion clause can break and retain its final state update",
    source: `
type Validate is effect = { check: U32 -> U32 }
const checked = fn computation => do:
  let total = 1
  for request in @requests computation:
    case request of
      effect Validate.check value =>
        total := @u32.add self value
        yield value
      complete value =>
        total := @u32.add self value
        break
  return total
entry const answer = fn () => checked (@computation (fn () => do:
  use value <- Validate.check 20
  return @u32.add value 1
))
`,
    expected: 42,
  },
  {
    name:
      "reply, computation result and early handler result have independent types",
    source: `
type Validate is effect = { check: U32 -> U32 }
const checked = fn computation => do:
  for request in @requests computation:
    case request of
      effect Validate.check value =>
        if @u32.eq value 0:
          return 42.0
        yield value
      complete () =>
        return 41.0
const calculation = @computation (fn () => do:
  use Validate.check 0
  return ()
)
entry const answer = fn () => @f32.to_u32 (checked calculation)
`,
    expected: 42,
  },
  {
    name: "a lazy captured computation can be reused with fresh handler state",
    source: `
type Counter is effect = { next: Unit -> U32 }
const calculation = @computation (fn () => Counter.next ())
const count = fn computation => do:
  let current = 39
  for request in @requests computation:
    case request of
      effect Counter.next () =>
        current := @u32.add self 1
        yield current
      complete value =>
        return value
entry const answer = fn () => @u32.add (count calculation) (count calculation)
`,
    expected: 80,
  },
  {
    name: "operation identities distinguish clauses with identical signatures",
    source: `
type Inputs is effect = { left: Unit -> U32, right: Unit -> U32 }
const handled = fn computation => do:
  for request in @requests computation:
    case request of
      effect Inputs.left () =>
        yield 40
      effect Inputs.right () =>
        yield 2
      complete value =>
        return value
entry const answer = fn () => handled (@computation (fn () => do:
  use left <- Inputs.left ()
  use right <- Inputs.right ()
  return @u32.add left right
))
`,
    expected: 42,
  },
  {
    name:
      "effect clauses run outside the entire installation and can forward their operation",
    source: `
type Validate is effect = { check: U32 -> U32 }
const outer = @effect.provider Validate.check (fn value => @u32.add value 2)
const checked = fn computation => do:
  for request in @requests computation:
    case request of
      effect Validate.check value =>
        use reply <- Validate.check value
        yield reply
      complete value =>
        return value
entry const answer = fn () => do outer:
  return checked (@computation (fn () => Validate.check 40))
`,
    expected: 42,
  },
  {
    name: "unrelated computation effects reach the surrounding provider",
    source: `
type Validate is effect = { check: U32 -> U32 }
type Input is effect = { read: Unit -> U32 }
const checked = fn computation => do:
  for request in @requests computation:
    case request of
      effect Validate.check value =>
        yield value
      complete value =>
        return value
entry const answer = fn () => do (@effect.provider Input.read (fn () => 2)):
  return checked (@computation (fn () => do:
    use left <- Validate.check 40
    use right <- Input.read ()
    return @u32.add left right
  ))
`,
    expected: 42,
  },
  {
    name:
      "an outer cancellation unwinds an inner handler and its invoking clause",
    source: `
type Outer is effect = { check: U32 -> U32 }
type Inner is effect = { read: Unit -> U32 }
const inner = fn computation => do:
  for request in @requests computation:
    case request of
      effect Inner.read () =>
        use value <- Outer.check 0
        yield value
      complete value =>
        return value
const outer = fn computation => do:
  for request in @requests computation:
    case request of
      effect Outer.check value =>
        return 42
      complete value =>
        return value
entry const answer = fn () => outer (@computation (fn () => do:
  use inner (@computation (fn () => do:
    use Inner.read ()
    return @panic "inner computation continued"
  ))
  return @panic "outer computation continued"
))
`,
    expected: 42,
  },
  {
    name: "a nested plain do return stays local to that block",
    source: `
type Validate is effect = { check: U32 -> U32 }
const checked = fn computation => do:
  for request in @requests computation:
    case request of
      effect Validate.check value =>
        let local = do:
          return @u32.add value 1
        yield local
      complete value =>
        return @u32.add value 1
entry const answer = fn () => checked (@computation (fn () => Validate.check 40))
`,
    expected: 42,
  },
  {
    name: "break in an ordinary loop inside a clause exits that nearest loop",
    source: `
type Validate is effect = { check: U32 -> U32 }
const checked = fn computation => do:
  let count = 0
  for request in @requests computation:
    case request of
      effect Validate.check value =>
        for index in 0 .. 5:
          count := @u32.add self 1
          if @u32.eq index 1:
            break
        yield @u32.add value count
      complete value =>
        return value
entry const answer = fn () => checked (@computation (fn () => Validate.check 40))
`,
    expected: 42,
  },
  {
    name: "multiple carried locals survive conditional and nested loop updates",
    source: `
type Counter is effect = { next: U32 -> U32 }
const count = fn computation => do:
  let first = 0
  let second = 0
  for request in @requests computation:
    case request of
      effect Counter.next value =>
        if @u32.eq value 0:
          first := @u32.add self 1
        else:
          second := @u32.add self 10
        for index in 0 .. 2:
          first := @u32.add self 1
        yield @u32.add first second
      complete value =>
        return @u32.add (@u32.add first second) value
entry const answer = fn () => count (@computation (fn () => do:
  use Counter.next 0
  use value <- Counter.next 1
  return value
))
`,
    expected: 30,
  },
  {
    name:
      "nested do cannot intercept an ordinary loop break at colliding offsets",
    source: collidingDo(
      "entry const answer = fn () => do:\n  for index in 0 .. 1:\n",
      14,
      '      break\n    @panic "inner do intercepted the loop break"\n  return 42\n',
    ),
    expected: 42,
  },
  {
    name: "nested do cannot intercept a completion break at colliding offsets",
    source: collidingDo(
      `entry const answer = fn () => do:
  let result = 0
  for request in @requests (@computation (fn () => 42)):
    case request of
      complete value =>
        result := value
`,
      15,
      '          break\n        @panic "inner do intercepted the completion break"\n  return result\n',
      "        ",
    ),
    expected: 42,
  },
  {
    name: "unused operation clauses can handle a pure computation",
    source: `
type Validate is effect = { check: U32 -> U32 }
const checked = fn computation => do:
  for request in @requests computation:
    case request of
      effect Validate.check value =>
        yield value
      complete value =>
        return value
entry const answer = fn () => checked (@computation (fn () => 42))
`,
    expected: 42,
  },
  {
    name: "a request loop may contain only its completion clause",
    source: `
const finished = fn computation => do:
  for request in @requests computation:
    case request of
      complete value =>
        return value
entry const answer = fn () => finished (@computation (fn () => 42))
`,
    expected: 42,
  },
  {
    name:
      "grouping the entire request input preserves its request-loop meaning",
    source: `
type Validate is effect = { check: U32 -> U32 }
const checked = fn computation => do:
  for request in (@requests computation):
    case request of
      effect Validate.check value =>
        yield @u32.add value 2
      complete value =>
        return value
entry const answer = fn () => checked (@computation (fn () => Validate.check 40))
`,
    expected: 42,
  },
  {
    name:
      "explicit generic operation clauses retain their specialized identity",
    source: `
type Inspect a is effect = a -> a
const inspected = fn computation => do:
  for request in @requests computation:
    case request of
      effect (Inspect U32) value =>
        yield @u32.add value 2
      complete value =>
        return value
entry const answer = fn () => inspected (@computation (fn () => Inspect U32 40))
`,
    expected: 42,
  },
  {
    name:
      "many requests in a loop use bounded call stack and fresh carried state",
    source: `
type Counter is effect = { next: Unit -> U32 }
const count = fn computation => do:
  let current = 0
  for request in @requests computation:
    case request of
      effect Counter.next () =>
        current := @u32.add self 1
        yield current
      complete () =>
        return current
entry const answer = fn limit => count (@computation (fn () => do:
  for index in 0 .. limit:
    use Counter.next ()
  return ()
))
`,
    expected: 1000,
    constantCall: "answer 1000",
    const_steps: 200_000n,
    calls: [[100000, 100000], [0, 0], [100000, 100000]],
  },
];

for (const program of programs) {
  Deno.test(`request runtime: ${program.name}`, async () => {
    const source = program.source +
      `\nentry const expected = ${program.constantCall ?? "answer ()"}\n`;
    await compileAndRun(source, (guest) => {
      const abi = guest.abi.functions.find((fn) => fn.name === "answer");
      for (
        const [argument, expected] of program.calls ??
          [[0, program.expected], [0, program.expected]]
      ) {
        equal(
          guest.call("answer", abi?.parameter === "Unit" ? null : argument),
          expected,
        );
      }
      equal(guest.read("expected"), program.expected);
    });
  });
}

Deno.test("request runtime: F32 reply and carried scalar state", async () => {
  await compileAndRun(
    `type Float is effect = { ask: F32 -> F32 }
const checked = fn computation => do:
  let sum = 0.5
  for request in @requests computation:
    case request of
      effect Float.ask value =>
        sum := @f32.add self value
        yield @f32.add sum 1.0
      complete value =>
        return @f32.add sum value
entry const answer = fn (value: F32) => checked (@computation (fn () => Float.ask value))
entry const folded = answer 20.0
`,
    (guest) => {
      const abi = guest.abi.functions.find((fn) => fn.name === "answer");
      equal(guest.call("answer", abi?.parameter === "Unit" ? null : 20), 42);
      equal(guest.call("answer", abi?.parameter === "Unit" ? null : 0), 2);
      equal(guest.call("answer", abi?.parameter === "Unit" ? null : 20), 42);
      equal(guest.read("folded"), 42);
    },
  );
});

Deno.test("request runtime: F32 helper cancellation retains independent U32 exit", async () => {
  await compileAndRun(
    `type Float is effect = { ask: F32 -> F32 }
const helper = fn value => @f32.add (Float.ask value) (@panic "cancelled F32 operand suffix ran")
const checked = fn computation => do:
  for request in @requests computation:
    case request of
      effect Float.ask value =>
        return @f32.to_u32 value
      complete value =>
        return @panic "cancelled F32 helper completed"
entry const answer = fn (value: F32) => checked (@computation (fn () => helper value))
entry const folded = answer 42.5
`,
    (guest) => {
      const abi = guest.abi.functions.find((fn) => fn.name === "answer");
      equal(guest.call("answer", abi?.parameter === "Unit" ? null : 42.5), 42);
      equal(guest.call("answer", abi?.parameter === "Unit" ? null : 11.25), 11);
      equal(guest.call("answer", abi?.parameter === "Unit" ? null : 42.5), 42);
      equal(guest.read("folded"), 42);
    },
  );
});

Deno.test("request runtime: mixed F32 and U32 carried state", async () => {
  await compileAndRun(
    `type Float is effect = { ask: F32 -> F32 }
const checked = fn computation => do:
  let sum = 0.5
  let count = 0
  for request in @requests computation:
    case request of
      effect Float.ask value =>
        sum := @f32.add self value
        count := @u32.add self 1
        yield @f32.add sum (@u32.to_f32 count)
      complete value =>
        return @f32.add (@f32.add sum value) (@u32.to_f32 count)
entry const answer = fn (value: F32) => checked (@computation (fn () => do:
  use Float.ask value
  return Float.ask value
))
entry const folded = answer 9.5
`,
    (guest) => {
      const abi = guest.abi.functions.find((fn) => fn.name === "answer");
      equal(guest.call("answer", abi?.parameter === "Unit" ? null : 9.5), 43);
      equal(guest.call("answer", abi?.parameter === "Unit" ? null : 0), 5);
      equal(guest.call("answer", abi?.parameter === "Unit" ? null : 9.5), 43);
      equal(guest.read("folded"), 43);
    },
  );
});

Deno.test("request runtime: captured callable carried state", async () => {
  await compileAndRun(
    `
type Validate is effect = { check: U32 -> U32 }
const checked = fn computation => do:
  let choose = fn value => @u32.add value 1
  for request in @requests computation:
    case request of
      effect Validate.check value =>
        choose := fn argument => @u32.add value argument
        yield choose 2
      complete value =>
        return @u32.add value (choose 0)
entry const answer = fn () => checked (@computation (fn () => Validate.check 40))
`,
    (guest) => {
      const abi = guest.abi.functions.find((fn) => fn.name === "answer");
      equal(guest.call("answer", abi?.parameter === "Unit" ? null : 0), 82);
      equal(guest.call("answer", abi?.parameter === "Unit" ? null : 0), 82);
    },
  );
});

Deno.test("request runtime: payload shadow carried elsewhere", async () => {
  await compileAndRun(
    `
type Counter is effect = { first: U32 -> U32, next: Unit -> U32 }
entry const answer = fn () => do:
  let count = 40
  for request in @requests (@computation (fn () => do:
    use Counter.first 5
    use Counter.next ()
    return ()
  )):
    case request of
      effect Counter.first count =>
        count := @u32.add self 1
        yield count
      effect Counter.next () =>
        count := @u32.add self 1
        yield count
      complete () =>
        return count
`,
    (guest) => {
      const abi = guest.abi.functions.find((fn) => fn.name === "answer");
      equal(guest.call("answer", abi?.parameter === "Unit" ? null : 0), 7);
    },
  );
});

Deno.test("request runtime: local shadow after outer update", async () => {
  await compileAndRun(
    `
type Tick is effect = Unit -> U32
entry const answer = fn () => do:
  let count = 40
  for request in @requests (@computation (fn () => do:
    use Tick ()
    return ()
  )):
    case request of
      effect Tick () =>
        count := @u32.add self 1
        let count = 2
        yield 1
      complete () =>
        return count
`,
    (guest) => {
      const abi = guest.abi.functions.find((fn) => fn.name === "answer");
      equal(guest.call("answer", abi?.parameter === "Unit" ? null : 0), 2);
    },
  );
});

Deno.test("request runtime: payload shadows every update", async () => {
  await compileAndRun(
    `
type Tick is effect = U32 -> U32
entry const answer = fn () => do:
  let count = 42
  for request in @requests (@computation (fn () => do:
    use Tick 5
    return ()
  )):
    case request of
      effect Tick count =>
        count := @u32.add self 1
        yield count
      complete () =>
        break
  return count
`,
    (guest) => {
      const abi = guest.abi.functions.find((fn) => fn.name === "answer");
      equal(guest.call("answer", abi?.parameter === "Unit" ? null : 0), 42);
    },
  );
});

Deno.test("request runtime: completion payload shadow", async () => {
  await compileAndRun(
    `
type Tick is effect = Unit -> U32
entry const answer = fn () => do:
  let count = 40
  for request in @requests (@computation (fn () => Tick ())):
    case request of
      effect Tick () =>
        count := @u32.add self 1
        yield 2
      complete count =>
        count := @u32.add self 1
        break
  return count
`,
    (guest) => {
      const abi = guest.abi.functions.find((fn) => fn.name === "answer");
      equal(guest.call("answer", abi?.parameter === "Unit" ? null : 0), 3);
    },
  );
});

Deno.test("request runtime: monadic block surrounds a plain request runner", async () => {
  await compileAndRun(
    `type Validate is effect = { check: U32 -> U32 }
type Box value is data = #Box value
const Box.pure = fn value => #Box value
const Box.bind = fn candidate => fn next => case candidate of
  #Box value => next value
const checked = fn computation => do (@do.monad Box):
  let selected = do:
    for request in @requests computation:
      case request of
        effect Validate.check value =>
          if @u32.eq value 0:
            return 42.0
          yield value
        complete () =>
          return 41.0
  return selected
entry const answer = fn (index: U32) => do:
  let #Box value = checked (@computation (fn () => do:
    use Validate.check index
    return ()
  ))
  return @f32.to_u32 value
entry const folded = answer 0
`,
    (guest) => {
      const abi = guest.abi.functions.find((fn) => fn.name === "answer");
      equal(guest.call("answer", abi?.parameter === "Unit" ? null : 0), 42);
      equal(guest.call("answer", abi?.parameter === "Unit" ? null : 1), 41);
      equal(guest.call("answer", abi?.parameter === "Unit" ? null : 0), 42);
      equal(guest.read("folded"), 42);
    },
  );
});

Deno.test("request runtime: one retained action specializes independently at U32 and F32 consumers", async () => {
  await compileAndRun(
    'type Tick is effect = { read: Unit -> U32 }\nconst make = fn action => @computation action\nconst whole = fn computation => do:\n  for request in @requests computation:\n    case request of\n      effect Tick.read () =>\n        return 20\n      complete value =>\n        return value\nconst floating = fn computation => do:\n  for request in @requests computation:\n    case request of\n      effect Tick.read () =>\n        return 22.5\n      complete value =>\n        return value\nentry const answer = fn () => do:\n  let value = 41\n  let computation = make (fn () => do:\n    use Tick.read ()\n    return @panic "cancelled generic computation continued"\n  )\n  let alias = computation\n  value := 99\n  let left = whole computation\n  let right = floating alias\n  return @f32.add (@u32.to_f32 left) right\nentry const folded = answer ()\n',
    (guest) => {
      for (let iteration = 0; iteration < 100; iteration++) {
        equal(guest.call("answer", null), 42.5);
      }
      equal(guest.read("folded"), 42.5);
    },
  );
});

Deno.test("request runtime: wrapped action specializes independently at U32 and F32 consumers", async () => {
  await compileAndRun(
    'type Tick is effect = { read: Unit -> U32 }\nconst make = fn action => @computation (fn () => action ())\nconst whole = fn computation => do:\n  for request in @requests computation:\n    case request of\n      effect Tick.read () =>\n        return 20\n      complete value =>\n        return value\nconst floating = fn computation => do:\n  for request in @requests computation:\n    case request of\n      effect Tick.read () =>\n        return 22.5\n      complete value =>\n        return value\nentry const answer = fn () => do:\n  let value = 41\n  let computation = make (fn () => do:\n    use Tick.read ()\n    return @panic "cancelled generic computation continued"\n  )\n  let alias = computation\n  value := 99\n  let left = whole computation\n  let right = floating alias\n  return @f32.add (@u32.to_f32 left) right\nentry const folded = answer ()\n',
    (guest) => {
      for (let iteration = 0; iteration < 100; iteration++) {
        equal(guest.call("answer", null), 42.5);
      }
      equal(guest.read("folded"), 42.5);
    },
  );
});

Deno.test("request runtime: factory capture snapshots survive later rebinding and another closure", async () => {
  await compileAndRun(
    "type Tick is effect = { read: U32 -> U32 }\nconst make = fn action => @computation action\nconst handled = fn computation => do:\n  for request in @requests computation:\n    case request of\n      effect Tick.read value =>\n        yield value\n      complete value =>\n        return value\nentry const answer = fn () => do:\n  let value = 41\n  let computation = make (fn () => Tick.read value)\n  value := 99\n  let read = fn () => handled computation\n  return @u32.add (read ()) 1\nentry const folded = answer ()\n",
    (guest) => {
      for (let iteration = 0; iteration < 100; iteration++) {
        equal(guest.call("answer", null), 42);
      }
      equal(guest.read("folded"), 42);
    },
  );
});

Deno.test("request runtime: effectful action factory runs exactly once across repeated handlers", async () => {
  await compileAndRun(
    'data Count value = #Count value\ntype Tick is effect = { read: Unit -> U32 }\nconst witness = fn () -> Count U32 => @panic "type witness executed"\nconst counted = fn action => do:\n  use previous <- @state.get witness\n  let #Count old = previous\n  use @state.set (#Count (@u32.add old 1))\n  return @computation action\nconst handled = fn computation => do:\n  for request in @requests computation:\n    case request of\n      effect Tick.read () =>\n        yield 20\n      complete value =>\n        return value\nentry const answer = fn () => do:\n  let (#Count count, value) = @state.run (#Count 0) (fn () => do:\n    use computation <- counted (fn () => Tick.read ())\n    let first = handled computation\n    let second = handled computation\n    return @u32.add first second\n  )\n  return @u32.add count value\nentry const folded = answer ()\n',
    (guest) => {
      for (let iteration = 0; iteration < 100; iteration++) {
        equal(guest.call("answer", null), 41);
      }
      equal(guest.read("folded"), 41);
    },
  );
});

Deno.test("request runtime: effectful factory creates its own unconstrained action once", async () => {
  await compileAndRun(
    'data Count value = #Count value\ntype Tick is effect = { read: Unit -> U32 }\nconst witness = fn () -> Count U32 => @panic "type witness executed"\nconst make = fn () => do:\n  use previous <- @state.get witness\n  let #Count old = previous\n  use @state.set (#Count (@u32.add old 1))\n  return @computation (fn () => do:\n    use Tick.read ()\n    return @panic "cancelled unconstrained computation continued"\n  )\nconst handled = fn computation => do:\n  for request in @requests computation:\n    case request of\n      effect Tick.read () =>\n        return 42.5\n      complete value =>\n        return value\nentry const answer = fn () => do:\n  let (#Count count, value) = @state.run (#Count 0) (fn () => do:\n    use computation <- make ()\n    let first = handled computation\n    let second = handled computation\n    return @f32.add first second\n  )\n  return @f32.add (@u32.to_f32 count) value\nentry const folded = answer ()\n',
    (guest) => {
      for (let iteration = 0; iteration < 100; iteration++) {
        equal(guest.call("answer", null), 86);
      }
      equal(guest.read("folded"), 86);
    },
  );
});

Deno.test("request runtime: pure factory wraps a retained action without fixing its result ABI", async () => {
  await compileAndRun(
    'type Tick is effect = { read: Unit -> U32 }\nconst make = fn action => @computation (fn () => action ())\nconst handled = fn computation => do:\n  for request in @requests computation:\n    case request of\n      effect Tick.read () =>\n        return 42.5\n      complete value =>\n        return value\nentry const answer = fn () => do:\n  let computation = make (fn () => do:\n    use Tick.read ()\n    return @panic "cancelled generic computation continued"\n  )\n  return handled computation\n',
    (guest) => {
      for (let iteration = 0; iteration < 100; iteration++) {
        equal(guest.call("answer", null), 42.5);
      }
    },
  );
});

Deno.test("request runtime: factory body executes its statements before returning a retained action", async () => {
  await compileAndRun(
    'type Tick is effect = { read: Unit -> U32 }\nconst make = fn action => do:\n  let token = @u32.add 1 1\n  return @computation action\nconst handled = fn computation => do:\n  for request in @requests computation:\n    case request of\n      effect Tick.read () =>\n        return 42.5\n      complete value =>\n        return value\nentry const answer = fn () => do:\n  let computation = make (fn () => do:\n    use Tick.read ()\n    return @panic "cancelled generic computation continued"\n  )\n  return handled computation\n',
    (guest) => {
      for (let iteration = 0; iteration < 100; iteration++) {
        equal(guest.call("answer", null), 42.5);
      }
    },
  );
});

Deno.test("request runtime: nested factory calls preserve local action and computation aliases", async () => {
  await compileAndRun(
    'type Tick is effect = { read: Unit -> U32 }\nconst build = fn action => do:\n  let wrapped = fn () => action ()\n  let value = @computation wrapped\n  return value\nconst make = fn action => build action\nconst handled = fn computation => do:\n  for request in @requests computation:\n    case request of\n      effect Tick.read () =>\n        return 42.5\n      complete value =>\n        return value\nentry const answer = fn () => do:\n  let computation = make (fn () => do:\n    use Tick.read ()\n    return @panic "cancelled generic computation continued"\n  )\n  return handled computation\nentry const folded = answer ()\n',
    (guest) => {
      for (let iteration = 0; iteration < 100; iteration++) {
        equal(guest.call("answer", null), 42.5);
      }
      equal(guest.read("folded"), 42.5);
    },
  );
});

Deno.test("request runtime: retained Foreign F32 factory captures unwind nested owners and recover after host failure", async () => {
  await compileAndRun(
    'type Outer is effect = { check: F32 -> F32 }\ntype Inner is effect = { read: Unit -> F32 }\nconst make = fn action => @computation action\nconst inner = fn selected => fn computation => do:\n  for request in @requests computation:\n    case request of\n      effect Inner.read () =>\n        use value <- Outer.check selected\n        yield value\n      complete value =>\n        return value\nconst outer = fn computation => do:\n  for request in @requests computation:\n    case request of\n      effect Outer.check value =>\n        return @f32.add value 1.0\n      complete value =>\n        return value\nconst invoke = fn action => fn value => action value\nconst retain = fn action => fn value => invoke action value\nconst calculation = make (fn () => Outer.check 41.5)\nconst calculation_alias = calculation\nentry const constant_alias = fn () => outer calculation_alias\nentry const folded = constant_alias ()\nentry const answer = fn (host: F32 -> F32 ! {Foreign}) => do:\n  let callback = retain host\n  let computation = make (fn () => do:\n    use selected <- callback 40.5\n    use inner selected (make (fn () => do:\n      use Inner.read ()\n      return @panic "inner suffix executed after outer cancellation"\n    ))\n    return @panic "outer suffix executed after nested cancellation"\n  )\n  return outer computation\nentry const pure = fn () => 7\n',
    async (synchronousGuest, bytes) => {
      const modes = [false];
      if (
        typeof (WebAssembly as unknown as { Suspending?: unknown })
            .Suspending === "function" &&
        typeof (WebAssembly as unknown as { promising?: unknown }).promising ===
          "function"
      ) modes.push(true);
      for (const asynchronous of modes) {
        const guest = asynchronous
          ? await instantiateGuest(bytes, { asynchronous: true })
          : synchronousGuest;
        let calls = 0;
        const call = (value: number) => {
          equal(value, 40.5);
          calls++;
          return 41.5;
        };
        const host = asynchronous
          ? guest.capabilityAsync({
            parameter: "F32",
            result: "F32",
            call: async (value) => {
              await Promise.resolve();
              return call(value);
            },
          })
          : guest.capability({ parameter: "F32", result: "F32", call });
        const cause = new Error("request callback failure");
        const fail = () => {
          throw cause;
        };
        const failing = asynchronous
          ? guest.capabilityAsync({
            parameter: "F32",
            result: "F32",
            call: async () => fail(),
          })
          : guest.capability({ parameter: "F32", result: "F32", call: fail });
        const wrong = guest.capability({
          parameter: "U32",
          result: "F32",
          call: () => {
            throw new Error("wrong callback invoked");
          },
        });
        try {
          for (let iteration = 0; iteration < 100; iteration++) {
            equal(
              asynchronous
                ? await guest.callAsync("answer", host)
                : guest.call("answer", host),
              42.5,
            );
            equal(
              asynchronous
                ? await guest.callAsync("constant_alias", null)
                : guest.call("constant_alias", null),
              42.5,
            );
            equal(
              asynchronous
                ? await guest.callAsync("pure", null)
                : guest.call("pure", null),
              7,
            );
            if (asynchronous) {
              await rejects(
                guest.callAsync("answer", failing),
                (error) => (error as { cause?: unknown }).cause === cause,
              );
            } else {throws(() =>
                guest.call("answer", failing), (error) =>
                (error as { cause?: unknown }).cause === cause);}
            if (asynchronous) await rejects(guest.callAsync("answer", wrong));
            else throws(() => guest.call("answer", wrong));
            equal(
              asynchronous
                ? await guest.callAsync("answer", host)
                : guest.call("answer", host),
              42.5,
            );
          }
          equal(calls, 200);
          equal(guest.read("folded"), 42.5);
        } finally {
          if (asynchronous) guest.dispose();
        }
      }
    },
  );
});

Deno.test("request runtime: local retained factory selects the checked F32 action result", async () => {
  await compileAndRun(
    'type Tick is effect = { read: Unit -> U32 }\nconst handled = fn computation => do:\n  for request in @requests computation:\n    case request of\n      effect Tick.read () =>\n        return 42.5\n      complete value =>\n        return value\nentry const answer = fn () => do:\n  let make = fn action => @computation (fn () => action ())\n  let computation = make (fn () => do:\n    use Tick.read ()\n    return @panic "cancelled generic computation continued"\n  )\n  return handled computation\n',
    (guest) => {
      for (let iteration = 0; iteration < 100; iteration++) {
        equal(guest.call("answer", null), 42.5);
      }
    },
  );
});

Deno.test("request runtime: effectful local action factory executes once before repeated handlers", async () => {
  await compileAndRun(
    'data Count value = #Count value\ntype Tick is effect = { read: Unit -> U32 }\nconst witness = fn () -> Count U32 => @panic "type witness executed"\nconst handled = fn computation => do:\n  for request in @requests computation:\n    case request of\n      effect Tick.read () =>\n        return 42.5\n      complete value =>\n        return value\nentry const answer = fn () => do:\n  let (#Count count, value) = @state.run (#Count 0) (fn () => do:\n    let make = fn () => do:\n      use previous <- @state.get witness\n      let #Count old = previous\n      use @state.set (#Count (@u32.add old 1))\n      return @computation (fn () => do:\n        use Tick.read ()\n        return @panic "cancelled unconstrained computation continued"\n      )\n    use computation <- make ()\n    let first = handled computation\n    let second = handled computation\n    return @f32.add first second\n  )\n  return @f32.add (@u32.to_f32 count) value\nentry const folded = answer ()\n',
    (guest) => {
      for (let iteration = 0; iteration < 100; iteration++) {
        equal(guest.call("answer", null), 86);
      }
      equal(guest.read("folded"), 86);
    },
  );
});

Deno.test("request runtime: local factory snapshots its capture before later rebinding", async () => {
  await compileAndRun(
    "type Tick is effect = { read: U32 -> U32 }\nconst handled = fn computation => do:\n  for request in @requests computation:\n    case request of\n      effect Tick.read value =>\n        yield value\n      complete value =>\n        return value\nentry const answer = fn () => do:\n  let value = 41\n  let make = fn action => @computation (fn () => do:\n    use action ()\n    return value\n  )\n  value := 99\n  let computation = make (fn () => Tick.read 0)\n  value := 199\n  let read = fn () => handled computation\n  return @u32.add (read ()) 1\nentry const folded = answer ()\n",
    (guest) => {
      for (let iteration = 0; iteration < 100; iteration++) {
        equal(guest.call("answer", null), 42);
      }
      equal(guest.read("folded"), 42);
    },
  );
});

Deno.test("request runtime: local factory retains exact F32 action signature when its result is discarded", async () => {
  await compileAndRun(
    "type Tick is effect = { read: U32 -> F32 }\nconst handled = fn computation => do:\n  for request in @requests computation:\n    case request of\n      effect Tick.read value =>\n        yield @u32.to_f32 value\n      complete value =>\n        return value\nentry const answer = fn () => do:\n  let value = 41\n  let make = fn action => @computation (fn () => do:\n    use action ()\n    return value\n  )\n  value := 99\n  let computation = make (fn () => Tick.read 0)\n  value := 199\n  let read = fn () => handled computation\n  return @u32.add (read ()) 1\nentry const folded = answer ()\n",
    (guest) => {
      for (let iteration = 0; iteration < 100; iteration++) {
        equal(guest.call("answer", null), 42);
      }
      equal(guest.read("folded"), 42);
    },
  );
});

Deno.test("request runtime: nested captured local factories retain source certificates", async () => {
  await compileAndRun(
    'type Tick is effect = { read: Unit -> U32 }\nconst handled = fn computation => do:\n  for request in @requests computation:\n    case request of\n      effect Tick.read () =>\n        return 42.5\n      complete value =>\n        return value\nconst create = fn action => do:\n  let factory = fn callback => @computation (fn () => callback ())\n  return @computation (fn () => do:\n    let computation = factory action\n    return handled computation\n  )\nentry const answer = fn () => handled (create (fn () => do:\n  use Tick.read ()\n  return @panic "cancelled action continued"\n))\nentry const folded = answer ()\n',
    (guest) => {
      for (let iteration = 0; iteration < 100; iteration++) {
        equal(guest.call("answer", null), 42.5);
      }
      equal(guest.read("folded"), 42.5);
    },
  );
});

Deno.test("request runtime: factory-created demanded action retains source row and memo state", async () => {
  await compileAndRun(
    "type Tick is effect = { read: Unit -> F32 }\nconst keep = fn ~value => fn () => @force value\nconst handled = fn computation => do:\n  for request in @requests computation:\n    case request of\n      effect Tick.read () =>\n        yield 42.5\n      complete value =>\n        return value\nconst create = fn action => do:\n  let delayed = keep (action ())\n  return @computation (fn () => delayed ())\nentry const answer = fn () => do:\n  let computation = create (fn () => Tick.read ())\n  return handled computation\nentry const folded = answer ()\n",
    (guest) => {
      for (let iteration = 0; iteration < 100; iteration++) {
        equal(guest.call("answer", null), 42.5);
      }
      equal(guest.read("folded"), 42.5);
    },
  );
});

Deno.test("request runtime: local factory bindings in distinct State scopes preserve nominal instances", async () => {
  await compileAndRun(
    'data Cell value = #Cell value\nconst witness32 = fn ignored -> Cell U32 => @panic "witness called"\nconst witnessf = fn ignored -> Cell F32 => @panic "witness called"\nconst handled = fn computation => do:\n  for request in @requests computation:\n    case request of\n      complete value =>\n        return value\nentry const answer = fn () => do:\n  let (#Cell state32, #Cell value32) = @state.run (#Cell 40) (fn () => do:\n    let make = fn (witness: Unit -> Cell U32) => @computation (fn () => @state.get witness)\n    let computation = make witness32\n    return handled computation\n  )\n  let (#Cell statef, #Cell valuef) = @state.run (#Cell 2.5) (fn () => do:\n    let make = fn (witness: Unit -> Cell F32) => @computation (fn () => @state.get witness)\n    let computation = make witnessf\n    return handled computation\n  )\n  return @f32.add (@u32.to_f32 value32) valuef\nentry const folded = answer ()\n',
    (guest) => {
      for (let iteration = 0; iteration < 100; iteration++) {
        equal(guest.call("answer", null), 42.5);
      }
      equal(guest.read("folded"), 42.5);
    },
  );
});
