import { deepStrictEqual as equal, ok, throws } from "node:assert/strict";
import { instantiateGuest } from "./guest.ts";
import { createNativeCompiler } from "./native.ts";
import { createSourceCompiler } from "./source.ts";
import { SourceError } from "./syntax.ts";

Deno.test("warm 8192-field tuple patterns compile through checked source with native and JS parity", async () => {
  const compiler = await createSourceCompiler({ prelude: "none" });
  const native = await createNativeCompiler({ prelude: "none", threads: 1 });
  try {
    for (const fields of [128, 8192]) {
      const source = `export fn answer () => case (${
        Array(fields).fill("0").join(", ")
      }) of
  (${Array(fields).fill("_").join(", ")}) => 42
`;
      const artifact = compiler.compile(source);
      equal(await native.compile(source), artifact);
      const { instance } = await WebAssembly.instantiate(artifact.bytes);
      const answer = instance.exports.answer;
      ok(typeof answer === "function");
      equal(answer(), 42);
    }
  } finally {
    compiler.dispose();
    await native.dispose();
  }
});

Deno.test("source tuple destructuring works in nested and grouped let patterns", async () => {
  const compiler = await createSourceCompiler();
  try {
    const artifact = compiler.compile(`
export fn answer () => do:
  let (first, (second, third)) = (40, (1, 1))
  let (grouped) = first
  let () = ()
  return grouped + second + third
fn pair_sum pair => case pair of
  (left, right) => left + right
export const expected = pair_sum (40, 2)
`);
    const { instance } = await WebAssembly.instantiate(artifact.bytes);
    equal((instance.exports.answer as CallableFunction)(), 42);
    equal((instance.exports.expected as WebAssembly.Global).value, 42);
  } finally {
    compiler.dispose();
  }
});

Deno.test("source tuple patterns compose with constructors and correlated case columns", async () => {
  const compiler = await createSourceCompiler();
  try {
    const artifact = compiler.compile(`
fn sum candidate => case candidate of
  Some (left, (right, True)) => left + right
  Some (_, (_, False)) => 0
  Nothing => 0
fn correlated pair => fn flag => case pair, flag of
  (True, True), True => 1
  (_, _), _ => 42
export const expected = sum (Some (40, (2, True)))
export fn answer () => correlated (True, False) True
`);
    const { instance } = await WebAssembly.instantiate(artifact.bytes);
    equal((instance.exports.expected as WebAssembly.Global).value, 42);
    equal((instance.exports.answer as CallableFunction)(), 42);
  } finally {
    compiler.dispose();
  }
});

Deno.test("tuple let-else and if-let bind only the successful scope", async () => {
  const compiler = await createSourceCompiler();
  try {
    const artifact = compiler.compile(`
fn guard pair => do:
  let value = 7
  let (Some value, True) = pair else:
    return value
  return value
fn conditional pair => do:
  let value = 7
  if let (Some value, True) = pair:
    return value
  return value
export fn accepted () => guard (Some 42, True)
export fn rejected () => guard (Some 42, False)
export fn matched () => conditional (Some 42, True)
export fn unmatched () => conditional (Some 42, False)
`);
    const { instance } = await WebAssembly.instantiate(artifact.bytes);
    for (const name of ["accepted", "matched"]) {
      equal((instance.exports[name] as CallableFunction)(), 42);
    }
    for (const name of ["rejected", "unmatched"]) {
      equal((instance.exports[name] as CallableFunction)(), 7);
    }
  } finally {
    compiler.dispose();
  }
});

Deno.test("tuple matching evaluates an effectful scrutinee once", async () => {
  const compiler = await createSourceCompiler();
  try {
    const artifact = compiler.compile(`
effect Next: Unit -> U32
fn pair () => do:
  use value <- Next ()
  return (value, 2)
export fn answer (read: Unit -> U32 ! {Foreign}) => do (@effect.provider Next read):
  return case pair () of
    (left, right) => left + right
`);
    const guest = await instantiateGuest(artifact.bytes);
    try {
      let calls = 0;
      const read = guest.capability({
        parameter: "Unit",
        result: "U32",
        call: () => {
          calls++;
          return 40;
        },
      });
      equal(guest.call("answer", read), 42);
      equal(calls, 1);
    } finally {
      guest.dispose();
    }
  } finally {
    compiler.dispose();
  }
});

Deno.test("record patterns support zero, one, reordered, omitted, and nested fields", async () => {
  const compiler = await createSourceCompiler();
  try {
    const artifact = compiler.compile(`
data Empty = Empty {}
data One a = One { value: a }
data Many a = Many { first: U32, payload: a, ignored: Bool }
fn unpack candidate => case candidate of
  Many { payload: Some (One { value: (left, right) }), first } => first + left + right
  Many { payload: Nothing } => 0
export fn answer () => do:
  let Empty {} = Empty {}
  let One {} = One { value: True }
  return unpack (Many { ignored: False, payload: Some (One { value: (20, 20) }), first: 2 })
`);
    const { instance } = await WebAssembly.instantiate(artifact.bytes);
    equal((instance.exports.answer as CallableFunction)(), 42);
  } finally {
    compiler.dispose();
  }
});

Deno.test("record guards use declaration order and keep fallback bindings untouched", async () => {
  const compiler = await createSourceCompiler();
  try {
    const artifact = compiler.compile(`
data Pair = Pair { value: Maybe U32, enabled: Bool }
fn guarded pair => do:
  let value = 7
  let Pair { enabled: True, value: Some value } = pair else:
    return value
  return value
export fn accepted () => guarded (Pair { enabled: True, value: Some 42 })
export fn rejected () => guarded (Pair { value: Some 42, enabled: False })
`);
    const { instance } = await WebAssembly.instantiate(artifact.bytes);
    equal((instance.exports.accepted as CallableFunction)(), 42);
    equal((instance.exports.rejected as CallableFunction)(), 7);
  } finally {
    compiler.dispose();
  }
});

Deno.test("tuple patterns reject duplicate bindings, incomplete rows, arity mismatch and leaking scope", async () => {
  const compiler = await createSourceCompiler();
  try {
    for (
      const [source, code] of [
        [
          "fn invalid value => case value of\n  (same, same) => 0\n",
          "duplicate_pattern_binding",
        ],
        [
          "fn invalid value => case value of\n  (same, Some (same, _)) => 0\n",
          "duplicate_pattern_binding",
        ],
        [
          "fn invalid value => do:\n  let (True, selected) = value\n  return selected\n",
          "non_exhaustive_match",
        ],
        [
          "fn invalid value => case value of\n  (True, True) => 1\n  (False, False) => 0\n",
          "non_exhaustive_match",
        ],
        [
          "fn invalid () => do:\n  let (first, second, third) = (1, 2)\n  return first\n",
          "product_arity",
        ],
        [
          "fn invalid value => do:\n  if let (first, second) = value:\n    let ignored = first\n  return second\n",
          "unknown_value",
        ],
      ]
    ) {
      throws(() => compiler.compile(source), (error) => {
        ok(error instanceof SourceError, String(error));
        equal(error.code, code, error.message);
        return true;
      });
    }
  } finally {
    compiler.dispose();
  }
});

Deno.test("record patterns reject unknown fields, duplicates and positional constructor misuse", async () => {
  const compiler = await createSourceCompiler();
  try {
    for (
      const [source, code] of [
        [
          "data Pair = Pair { x: U32, y: U32 }\nfn invalid value => case value of\n  Pair { missing } => 0\n",
          "unknown_record_field",
        ],
        [
          "data Pair = Pair { x: U32, y: U32 }\nfn invalid value => case value of\n  Pair { x, x } => 0\n",
          "duplicate_record_field",
        ],
        [
          "data Pair = Pair { x: U32, y: U32 }\nfn invalid value => case value of\n  Pair { x: same, y: same } => 0\n",
          "duplicate_pattern_binding",
        ],
        [
          "data Pair = Pair U32\nfn invalid value => case value of\n  Pair {} => 0\n",
          "record_constructor",
        ],
      ]
    ) {
      throws(() => compiler.compile(source), (error) => {
        ok(error instanceof SourceError, String(error));
        equal(error.code, code, error.message);
        return true;
      });
    }
  } finally {
    compiler.dispose();
  }
});
