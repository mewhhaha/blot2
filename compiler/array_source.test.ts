import { deepStrictEqual as equal, ok, throws } from "node:assert/strict";
import { createNativeCompiler } from "./native.ts";
import { createSourceCompiler } from "./source.ts";
import { loadSourceProject } from "./source_project.ts";
import { SourceError } from "./syntax.ts";

Deno.test("source arrays and std/array execute through native module compilation", async () => {
  const source = await loadSourceProject(
    new URL("../examples/arrays.blot", import.meta.url),
    {
      imports: { "std/": new URL("../std/", import.meta.url) },
    },
  );
  const js = await createSourceCompiler();
  const native = await createNativeCompiler();
  try {
    const expected = js.compile(source);
    const actual = await native.compile(source);
    equal(actual, expected);
    const { instance } = await WebAssembly.instantiate(actual.bytes);
    const call = (name: string, value = 0) =>
      (instance.exports[name] as CallableFunction)(value);
    equal((instance.exports.expected as WebAssembly.Global).value, 42);
    for (const name of ["answer", "unchanged", "nested"]) equal(call(name), 42);
    equal(call("checked", 0), 10);
    equal(call("checked", 2), 12);
    equal(call("checked", 3), 0);
    equal(call("checked", 0xffffffff), 0);
  } finally {
    js.dispose();
    await native.dispose();
  }
});

Deno.test("source array literals handle multiline layout, nesting, early return, and polymorphic empties", async () => {
  const compiler = await createSourceCompiler();
  try {
    const artifact = compiler.compile(`
const empty = []
entry const numbers = fn (values: Array U32) => @array.length values
const truths = fn (values: Array Bool) => @array.length values
entry const count = numbers empty + truths empty
entry const answer = fn () => do:
  let values = [
    [1, 2],
    [40, 42],
  ]
  return @array.get (@array.get values 1) 1
entry const returned = fn () => do:
  let values = [do:
    return 42]
  return @array.get values 0
`);
    const { instance } = await WebAssembly.instantiate(artifact.bytes);
    equal((instance.exports.count as WebAssembly.Global).value, 0);
    equal((instance.exports.answer as CallableFunction)(), 42);
    equal((instance.exports.returned as CallableFunction)(), 42);
  } finally {
    compiler.dispose();
  }
});

Deno.test("source arrays diagnose element, index, annotation, arity and const bounds failures", async () => {
  const compiler = await createSourceCompiler({ prelude: "none" });
  try {
    for (
      const [source, code] of [
        ["const values = [1, True]\n", "type_mismatch"],
        ["const invalid = fn () => @array.get [1] False\n", "type_mismatch"],
        ["const invalid = fn () => @array.set [1] 0 True\n", "type_mismatch"],
        ["const values: Array = []\n", "type_arity"],
        ["const values: Array U32 Bool = []\n", "type_arity"],
        [
          "const value = @array.get [] 0\nentry const probe = fn () => do:\n  let kept = value\n  return 0\n",
          "array_bounds",
        ],
        ["const invalid = fn () => @array.length [] []\n", "call_arity"],
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

Deno.test("std/array folds preserve effects and predicates stop before unused elements", async () => {
  const library = await Deno.readTextFile(
    new URL("../std/array.blot", import.meta.url),
  );
  const main = `import * as array from "./array"
effect Visit : U32 -> U32
const visit = @effect.provider Visit (fn value => value + 1)
const add_visit = fn total => fn value => do:
  use next <- Visit value
  return total + next
entry const accepts = fn value => do:
  if value == 99:
    use @panic "unvisited predicate element"
  return value == 42
entry const folded = fn () => do visit:
  return array.fold_left add_visit 0 [20, 20]
entry const found = fn () => array.any accepts [42, 99]
entry const rejected = fn () => array.all accepts [0, 99]
entry const vacuous = fn () => array.all accepts []
entry const absent = fn () => array.any accepts []
entry const unchanged = fn () => do:
  let original = [2]
  let changed = Maybe.unwrap_or [] $ array.set 0 40 original
  return array.at 0 original + array.at 0 changed
`;
  const project = await loadSourceProject(
    new URL("file:///array-tests/main.blot"),
    {
      readSource: (url) =>
        Promise.resolve(url.pathname.endsWith("/main.blot") ? main : library),
    },
  );
  const compiler = await createSourceCompiler();
  try {
    const artifact = compiler.compile(project);
    const { instance } = await WebAssembly.instantiate(artifact.bytes);
    const call = (name: string) =>
      (instance.exports[name] as CallableFunction)();
    equal(call("folded"), 42);
    equal(call("found"), 1);
    equal(call("rejected"), 0);
    equal(call("vacuous"), 1);
    equal(call("absent"), 0);
    equal(call("unchanged"), 42);
  } finally {
    compiler.dispose();
  }
});
