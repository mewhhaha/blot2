import {
  compileAndRun,
  compileExpectedFailure,
  equal,
} from "./compile_helpers.ts";
for (const asynchronous of [false, true]) {
  Deno.test(`unused aggregate original (${asynchronous ? "JSPI" : "sync"})`, async () => {
    await compileAndRun(
      `
type Maybe a is data = $Some a | $Nothing
const identity = func value => return value
const empty = $Nothing
const nested = $Some ($Some 42)
const reference = identity
const constructor = $Some
const closure = (func captured => return func value => return @u32.add captured value) 2
entry const answer = func () => return closure 40
entry const probe = func () => return do:
  let kept = (empty, nested, reference, constructor)
  break 0
`,
      async (guest) => {
        const invoke = async (name: string, value: number | boolean | null) =>
          asynchronous
            ? await guest.callAsync(name, value)
            : guest.call(name, value);
        equal(await invoke("answer", null), 42);
        equal(await invoke("probe", null), 0);
      },
      { asynchronous },
    );
  });
}
for (const asynchronous of [false, true]) {
  Deno.test(`unused aggregate eager-order (${asynchronous ? "JSPI" : "sync"})`, async () => {
    await compileAndRun(
      `type Count value is data = $Count value
const witness = func () : Count U32 => return @panic "witness ran"
const identity = func value => return value
const keep = func ~value => return func () => return @demand value
const mark = func (digit: U32) => return do:
  use previous <- @state.get witness
  let $Count old = previous
  use @state.set ($Count (@u32.add (@u32.mul old 10) digit))
  break @u32.to_f32 digit
entry const answer = func () => return do:
  let ($Count count, _) = @state.run ($Count 0) (func () => return do:
    let delayed = keep (mark 7)
    use ignored <- (identity, (mark 1, #[mark 2, mark 3], #[mark 4, mark 5, mark 6], delayed (), @array.fill 2 (mark 8), func () => return @panic "unused body ran"))
    break ()
  )
  break count
entry const folded = answer ()
`,
      async (guest) => {
        const invoke = async (name: string, value: number | boolean | null) =>
          asynchronous
            ? await guest.callAsync(name, value)
            : guest.call(name, value);
        equal(guest.read("folded"), 12345678);
        for (let i = 0; i < 100; i++) {
          equal(
            asynchronous
              ? await guest.callAsync("answer", null)
              : await invoke("answer", null),
            12345678,
          );
        }
      },
      { asynchronous },
    );
  });
}
for (const asynchronous of [false, true]) {
  Deno.test(`unused aggregate implicit-uses (${asynchronous ? "JSPI" : "sync"})`, async () => {
    await compileAndRun(
      `type Box is data = $Box (U32, U32)
entry const capture = func () => return do:
  let kept = (40, 2)
  let use_it = func () => return @u32.add (@product.get kept 0) (@product.get kept 1)
  break use_it ()
entry const carry = func () => return do:
  let kept = (40, 2)
  for index in 0..2:
    kept := (@u32.add (@product.get kept 0) 1, 0)
  break @product.get kept 0
entry const merged = func (flag: Bool) => return do:
  let kept = (0, 0)
  if flag:
    kept := (40, 2)
  else:
    kept := (20, 22)
  break @u32.add (@product.get kept 0) (@product.get kept 1)
entry const value_pattern = func () => return do:
  let needle = 41
  let unused = (0, 0)
  break case 41 of
    needle => 42
    _ => 0
`,
      async (guest) => {
        const invoke = async (name: string, value: number | boolean | null) =>
          asynchronous
            ? await guest.callAsync(name, value)
            : guest.call(name, value);
        for (let i = 0; i < 100; i++) {
          equal(await invoke("capture", null), 42);
          equal(await invoke("carry", null), 42);
          equal(await invoke("merged", false), 42);
          equal(await invoke("merged", true), 42);
          equal(await invoke("value_pattern", null), 42);
        }
      },
      { asynchronous },
    );
  });
}
for (const asynchronous of [false, true]) {
  Deno.test(`unused aggregate requests-abort (${asynchronous ? "JSPI" : "sync"})`, async () => {
    await compileAndRun(
      `type Count value is data = $Count value
type Stop is effect = { read: Unit -> U32 }
const witness = func () : Count U32 => return @panic "witness ran"
const identity = func value => return value
const mark = func (digit: U32) => return do:
  use previous <- @state.get witness
  let $Count old = previous
  use @state.set ($Count (@u32.add (@u32.mul old 10) digit))
  break digit
const handled = func computation => return do:
  for request in @requests computation:
    case request of
      effect Stop.read () =>
        break 40
      complete value =>
        break value
entry const answer = func () => return do:
  let ($Count count, value) = @state.run ($Count 0) (func () => return handled (@computation (func () => return do:
    use ignored <- (identity, (mark 1, Stop.read (), mark 2))
    break 0
  )))
  break @u32.add count value
entry const folded = answer ()
`,
      async (guest) => {
        const invoke = async (name: string, value: number | boolean | null) =>
          asynchronous
            ? await guest.callAsync(name, value)
            : guest.call(name, value);
        equal(guest.read("folded"), 41);
        for (let i = 0; i < 100; i++) {
          equal(
            asynchronous
              ? await guest.callAsync("answer", null)
              : await invoke("answer", null),
            41,
          );
        }
      },
      { asynchronous },
    );
  });
}
for (const asynchronous of [false, true]) {
  Deno.test(`unused aggregate generate-panic (${asynchronous ? "JSPI" : "sync"})`, async () => {
    await compileAndRun(
      `const identity = func value => return value
entry const answer = func (length: U32) => return do:
  let ignored = (identity, @array.generate length (func (index: U32) : U32 => return @panic "callback ran"))
  break 42
`,
      async (guest) => {
        const invoke = async (name: string, value: number | boolean | null) =>
          asynchronous
            ? await guest.callAsync(name, value)
            : guest.call(name, value);
        equal(await invoke("answer", 0), 42);
        let trapped = false;
        try {
          await invoke("answer", 1);
        } catch (error) {
          trapped = error instanceof WebAssembly.RuntimeError;
        }
        equal(trapped, true);
        equal(await invoke("answer", 0), 42);
      },
      { asynchronous },
    );
  });
}
for (const asynchronous of [false, true]) {
  Deno.test(`unused aggregate runtime-panic (${asynchronous ? "JSPI" : "sync"})`, async () => {
    await compileAndRun(
      `const identity = func value => return value
entry const answer = func (value: U32) => return do:
  let ignored = (identity, (func input => return @panic "runtime operand") value, @u32.div 1 0)
  break 0
`,
      async (guest) => {
        const invoke = async (name: string, value: number | boolean | null) =>
          asynchronous
            ? await guest.callAsync(name, value)
            : guest.call(name, value);
        let trapped = false;
        try {
          await invoke("answer", 1);
        } catch (error) {
          trapped = error instanceof WebAssembly.RuntimeError;
        }
        equal(trapped, true);
      },
      { asynchronous },
    );
  });
}
Deno.test("unused aggregate retains panic-order", async () => {
  await compileExpectedFailure(
    `type Maybe a is data = $Some a | $Nothing
const identity = func value => return value
const bad = @panic "constant operand"
entry const answer = func () => return do:
  let ignored = (identity, bad)
  break 0
`,
    "const_panic",
  );
});
Deno.test("unused aggregate retains initializer-panic", async () => {
  await compileExpectedFailure(
    `const identity = func value => return value
const failing = do:
  let ignored = (1, 2)
  break @panic "constant initializer ran"
entry const answer = func () => return do:
  let ignored = (identity, failing)
  break 0
`,
    "const_panic",
  );
});
Deno.test("unused aggregate retains explicit-qualifier", async () => {
  await compileExpectedFailure(
    `entry const answer = func () => return do:
  let ignored: (U32, U32) where { associated "missing" Bool Bool Bool } = (40, 2)
  break 0
`,
    "missing_associated",
  );
});
Deno.test("unused aggregate retains deferred-body proof rejection", async () => {
  await compileExpectedFailure(
    `const identity = func value => return value
const missing = func value => return value.no_such_member
entry const answer = func () => return do:
  let unused = (missing, identity, func input => return input.no_such_member)
  break 42
entry const folded = answer ()
`,
    "constant_expression",
  );
});
Deno.test("unused aggregate retains deferred-anonymous proof rejection", async () => {
  await compileExpectedFailure(
    `const identity = func value => return value
entry const answer = func () => return do:
  let unused = (identity, func value => return value.no_such_member)
  break 42
`,
    "constant_expression",
  );
});
Deno.test("unused aggregate retains deferred-alias proof rejection", async () => {
  await compileExpectedFailure(
    `const identity = func value => return value
const missing = func value => return value.no_such_member
const packed = (identity, missing)
entry const answer = func () => return do:
  let unused = (identity, packed)
  break 42
`,
    "unresolved_type",
  );
});
