import {
  deepStrictEqual as equal,
  ok,
  rejects,
  throws,
} from "node:assert/strict";
import { createSourceCompiler } from "./source.ts";
import { createNativeCompiler } from "./native.ts";
import { SourceError } from "./syntax.ts";

Deno.test("rebinding composes const builders and preserves previous closure captures", async () => {
  const source = `
data Builder = Builder U32
const append = fn amount => fn builder => case builder of
  Builder value => Builder (value * 10 + amount)
const built = do:
  let application = Builder 1
  application := append 2 self
  application := append 3 self
  return application
const composed = fn () => case built of
  Builder value => value
const captures = fn (value: U32) => do:
  let before = fn () => value
  value := self + 1
  let after = fn () => value
  value := value + self
  return before () * 100 + after () * 10 + value
const different_type = fn () => do:
  let value = 21
  value := U32.to_f32 self
  value := self * 2.0
  return value
const captured_self = fn () => do:
  let value = 20
  value := fn amount => self + amount
  return value 22
const nested = fn () => do:
  let self = 100
  let value = 1
  value := do:
    let inner = 2
    inner := self + 3
    return self + inner
  return self + value
const local_scope = fn () => do:
  let value = 1
  if True:
    value := self + 1
  return value
`;
  const reference = await createSourceCompiler();
  const native = await createNativeCompiler();
  try {
    const artifact = reference.compile(source);
    equal(await native.compile(source), artifact);
    const { instance } = await WebAssembly.instantiate(artifact.bytes);
    for (
      const [name, argument, expected] of [
        ["composed", undefined, 123],
        ["captures", 3, 348],
        ["different_type", undefined, 42],
        ["captured_self", undefined, 42],
        ["nested", undefined, 106],
        ["local_scope", undefined, 1],
      ] as const
    ) {
      equal(
        (instance.exports[name] as CallableFunction)(argument),
        expected,
        name,
      );
    }
  } finally {
    reference.dispose();
    await native.dispose();
  }
});

Deno.test("rebinding requires a local target and keeps self and effects scoped", async () => {
  const reference = await createSourceCompiler();
  const native = await createNativeCompiler();
  try {
    for (
      const [source, code] of [
        [
          "const run = fn () => do:\n  missing := 1\n  return 0",
          "unknown_rebinding",
        ],
        [
          "const value = 1\nconst run = fn () => do:\n  value := 2\n  return value",
          "unknown_rebinding",
        ],
        [
          "const run = fn () => do:\n  let value = 1\n  value := self + 1\n  return self",
          "unknown_value",
        ],
        [
          "effect Read : U32 -> U32\nconst run = fn (value: U32) => do:\n  value := Read self\n  return value",
          "let_effect",
        ],
      ]
    ) {
      const expected = (error: unknown) => {
        ok(error instanceof SourceError, String(error));
        equal(error.code, code);
        return true;
      };
      throws(() => reference.compile(source), expected);
      await rejects(native.compile(source), expected);
    }
  } finally {
    reference.dispose();
    await native.dispose();
  }
});
