import { strict as assert } from "node:assert";
import { instantiateGuest } from "../../host/guest.ts";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import {
  compileAndRun,
  compileExpectedFailure,
  equal,
} from "./compile_helpers.ts";

const executable = Deno.args[0] ??
  new URL("../../compiler/zig-out/bin/blotc", import.meta.url);

Deno.test("named functions execute curried calls and partial applications alongside ordinary function values", async () => {
  await compileAndRun(
    `func add (left: U32) -> (right: U32) : U32 => return @u32.add left right
const plus_two = add 2
const identity = func value => return value
entry func apply (value: U32) : U32 => return identity (plus_two value)
entry func answer () : U32 => return add 20 22
`,
    (guest) => {
      equal(guest.call("answer", null), 42);
      for (const value of [0, 1, 40, 100]) {
        equal(guest.call("apply", value), value + 2);
      }
    },
    { prelude: "none" },
  );
});

Deno.test("named forward references and direct and mutual recursion execute their base cases", async () => {
  await compileAndRun(
    `entry func forward (value: U32) : U32 => return later value
func sum (value: U32) : U32 => return if @u32.eq value 0 then 0 else @u32.add value (sum (@u32.sub value 1))
func even (value: U32) : Bool => return if @u32.eq value 0 then true else odd (@u32.sub value 1)
func odd (value: U32) : Bool => return if @u32.eq value 0 then false else even (@u32.sub value 1)
func later (value: U32) : U32 => return sum value
entry func parity (value: U32) : Bool => return even value
`,
    (guest) => {
      for (const value of [0, 1, 2, 6, 12]) {
        equal(guest.call("forward", value), value * (value + 1) / 2);
        equal(guest.call("parity", value), value % 2 === 0);
      }
    },
    { prelude: "none" },
  );
});

Deno.test("a tag decorates the whole named function without flattening its parameter", async () => {
  await compileAndRun(
    `const decorate = func function => return func (value: U32) => return @u32.add (function value) 1
@[decorate]
entry func increment (value: U32) : U32 => return value
`,
    (guest) => {
      for (const value of [0, 1, 41, 100]) {
        equal(guest.call("increment", value), value + 1);
      }
    },
    { prelude: "none" },
  );
});

Deno.test("named function tags reject changed dispatch parameters and written results", async () => {
  for (
    const wrapper of [
      "func f => return 42",
      "func f => return func () => return 42",
      "func f => return func (x: U32) => return true",
    ]
  ) {
    await compileExpectedFailure(
      `const replace = ${wrapper}\n@[replace]\nentry func identity (x: U32): U32 => return x\n`,
      "type_mismatch",
      undefined,
      { prelude: "none" },
    );
  }
});

Deno.test("project imports expose public named functions while private helpers stay private through failed edits", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-named-functions-" });
  const entry = `${directory}/main.blot`;
  const accepted = `import { increment as renamed } from "./library"
import * as library from "./library"
entry func answer (value: U32) : U32 => return @u32.add (renamed value) (library.increment value)
`;
  try {
    await Deno.writeTextFile(
      `${directory}/library.blot`,
      `private func hidden (value: U32) : U32 => return @u32.add value 2
func increment (value: U32) : U32 => return hidden value
`,
    );
    await Deno.writeTextFile(entry, accepted);
    const project = await createZigProjectCompiler({
      executable,
      entry,
      prelude: null,
      cacheDirectory: false,
      startupTimeoutMs: 5000,
    });
    try {
      const first = await project.build({ signal: AbortSignal.timeout(5000) });
      assert(first.success, JSON.stringify(first));
      const guest = await instantiateGuest(first.bytes);
      try {
        for (const value of [0, 1, 40]) {
          equal(guest.call("answer", value), (value + 2) * 2);
        }
      } finally {
        guest.dispose();
      }
      for (
        const [source, code] of [
          [
            'import { hidden } from "./library"\nentry func answer () : U32 => return hidden 40\n',
            "unknown_export",
          ],
          [
            'import * as library from "./library"\nentry func answer () : U32 => return library.hidden 40\n',
            "unknown_value",
          ],
          [
            'export { hidden } from "./library"\nentry func answer () : U32 => return 42\n',
            "unknown_export",
          ],
        ] as const
      ) {
        const rejected = await project.build({
          sources: { [entry]: source },
          signal: AbortSignal.timeout(5000),
        });
        assert(!rejected.success, "private named function escaped its module");
        assert(
          rejected.diagnostics.some((diagnostic) => diagnostic.code === code),
          JSON.stringify(rejected.diagnostics),
        );
      }
      const restored = await project.build({
        sources: { [entry]: accepted },
        signal: AbortSignal.timeout(5000),
      });
      assert(restored.success, JSON.stringify(restored));
      const restoredGuest = await instantiateGuest(restored.bytes);
      try {
        equal(restoredGuest.call("answer", 40), 84);
      } finally {
        restoredGuest.dispose();
      }
    } finally {
      await project.dispose();
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("qualified named functions and explicit declaration predicates preserve const controls and effects", async () => {
  for (const declaration of [
    "const eq: a -> a -> Bool where { Eq a } = func left -> right => return Eq.eq left right",
    "func eq (left: a) -> (right: a): Bool where { Eq a } => return Eq.eq left right",
  ]) {
    await compileAndRun(
      `type Eq a is contract = { const eq: a -> a -> Bool }
impl Unsigned: Eq U32 = { const eq = func left -> right => return @u32.eq left right }
type Box is data = $Box U32
func Box.from (value: U32): Box => return $Box value
const Box.zero = $Box 0
func from (value: U32): Box => return @type.result "from" value
func unbox (box: Box): U32 => return case box of
  $Box value => value
${declaration}
type Trace is effect = { trace: U32 -> Unit }
func traced (value: U32): U32 ! {Trace} => return do:
  Trace.trace value
  break value
entry func equal (value: U32): Bool => return eq value 42
entry func answer (): U32 => return @u32.add (unbox (from 42)) (unbox Box.zero)
const provider = @effect.provider Trace.trace (func value => return ())
entry func effectful (value: U32): U32 => return do provider:
  break traced value
`,
      (guest) => {
        equal(guest.call("answer", null), 42);
        equal(guest.call("equal", 42), true);
        equal(guest.call("equal", 41), false);
        equal(guest.call("effectful", 42), 42);
      },
      { prelude: "none" },
    );
  }
  await compileExpectedFailure(
    "func invalid (value: a): a where {} => return value.field\n",
    "missing_predicate",
    undefined,
    { prelude: "none" },
  );
});
