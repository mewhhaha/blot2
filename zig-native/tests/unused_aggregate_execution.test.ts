import {
  compileAndRun,
  compileExpectedFailure,
  equal,
} from "./compile_helpers.ts";
for (const asynchronous of [false, true]) {
  Deno.test(`unused aggregate original (${asynchronous ? "JSPI" : "sync"})`, async () => {
    await compileAndRun(
      `
data Maybe a = #Some a | #Nothing
const identity = fn value => value
const empty = #Nothing
const nested = #Some (#Some 42)
const reference = identity
const constructor = #Some
const closure = (fn captured => fn value => @u32.add captured value) 2
entry const answer = fn () => closure 40
entry const probe = fn () => do:
  let kept = (empty, nested, reference, constructor)
  return 0
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
      `data Count value = #Count value
const witness = fn () -> Count U32 => @panic "witness ran"
const identity = fn value => value
const keep = fn ~value => fn () => @force value
const mark = fn (digit: U32) => do:
  use previous <- @state.get witness
  let #Count old = previous
  use @state.set (#Count (@u32.add (@u32.mul old 10) digit))
  return @u32.to_f32 digit
entry const answer = fn () => do:
  let (#Count count, _) = @state.run (#Count 0) (fn () => do:
    let delayed = keep (mark 7)
    use ignored <- (identity, (mark 1, #[mark 2, mark 3], #[mark 4, mark 5, mark 6], delayed (), @array.fill 2 (mark 8), fn () => @panic "unused body ran"))
    return ()
  )
  return count
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
      `data Box = #Box (U32, U32)
entry const capture = fn () => do:
  let kept = (40, 2)
  let use_it = fn () => @u32.add (@product.get kept 0) (@product.get kept 1)
  return use_it ()
entry const carry = fn () => do:
  let kept = (40, 2)
  for index in 0..2:
    kept := (@u32.add (@product.get kept 0) 1, 0)
  return @product.get kept 0
entry const merged = fn (flag: Bool) => do:
  let kept = (0, 0)
  if flag:
    kept := (40, 2)
  else:
    kept := (20, 22)
  return @u32.add (@product.get kept 0) (@product.get kept 1)
entry const value_pattern = fn () => do:
  let needle = 41
  let unused = (0, 0)
  return case 41 of
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
      `data Count value = #Count value
type Stop is effect = { read: Unit -> U32 }
const witness = fn () -> Count U32 => @panic "witness ran"
const identity = fn value => value
const mark = fn (digit: U32) => do:
  use previous <- @state.get witness
  let #Count old = previous
  use @state.set (#Count (@u32.add (@u32.mul old 10) digit))
  return digit
const handled = fn computation => do:
  for request in @requests computation:
    case request of
      effect Stop.read () =>
        return 40
      complete value =>
        return value
entry const answer = fn () => do:
  let (#Count count, value) = @state.run (#Count 0) (fn () => handled (@computation (fn () => do:
    use ignored <- (identity, (mark 1, Stop.read (), mark 2))
    return 0
  )))
  return @u32.add count value
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
      `const identity = fn value => value
entry const answer = fn (length: U32) => do:
  let ignored = (identity, @array.generate length (fn (index: U32) -> U32 => @panic "callback ran"))
  return 42
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
      `const identity = fn value => value
entry const answer = fn (value: U32) => do:
  let ignored = (identity, (fn input => @panic "runtime operand") value, @u32.div 1 0)
  return 0
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
    `data Maybe a = #Some a | #Nothing
const identity = fn value => value
const bad = @panic "constant operand"
entry const answer = fn () => do:
  let ignored = (identity, bad)
  return 0
`,
    "const_panic",
  );
});
Deno.test("unused aggregate retains initializer-panic", async () => {
  await compileExpectedFailure(
    `const identity = fn value => value
const failing = do:
  let ignored = (1, 2)
  return @panic "constant initializer ran"
entry const answer = fn () => do:
  let ignored = (identity, failing)
  return 0
`,
    "const_panic",
  );
});
Deno.test("unused aggregate retains explicit-qualifier", async () => {
  await compileExpectedFailure(
    `entry const answer = fn () => do:
  let ignored: (U32, U32) where { associated "missing" Bool Bool Bool } = (40, 2)
  return 0
`,
    "missing_associated",
  );
});
Deno.test("unused aggregate retains deferred-body proof rejection", async () => {
  await compileExpectedFailure(
    `const identity = fn value => value
const missing = fn value => value.no_such_member
entry const answer = fn () => do:
  let unused = (missing, identity, fn input => input.no_such_member)
  return 42
entry const folded = answer ()
`,
    "constant_expression",
  );
});
Deno.test("unused aggregate retains deferred-anonymous proof rejection", async () => {
  await compileExpectedFailure(
    `const identity = fn value => value
entry const answer = fn () => do:
  let unused = (identity, fn value => value.no_such_member)
  return 42
`,
    "constant_expression",
  );
});
Deno.test("unused aggregate retains deferred-alias proof rejection", async () => {
  await compileExpectedFailure(
    `const identity = fn value => value
const missing = fn value => value.no_such_member
const packed = (identity, missing)
entry const answer = fn () => do:
  let unused = (identity, packed)
  return 42
`,
    "unresolved_type",
  );
});
