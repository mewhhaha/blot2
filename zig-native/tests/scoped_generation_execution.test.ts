import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const library = `type State a is effect = {get: Unit -> a, set: a -> Unit}
type Application is data = $Application {reset: Unit -> U32}
const reset_scoped = func application => return func () => return do:
  let $Application {reset} = application
  break reset ()
const choose = func flag => return func (left: State a) => return func (right: State a) => return if flag then left else right
const forward = func flag => return func (left: State a) => return func (right: State a) => return choose flag left right
const staged = func (left: State a) => return func (middle: State a) => return do:
  let first = if true then left else middle
  break func () => return {first: first, second: if false then left else middle}
const partial = func (left: State a) => return func (middle: State a) => return func () => return {first: left, second: if false then left else middle}
const twice = func (left: State a) => return func (right: State a) => return func () => return {first: if true then left else right, second: if false then left else right}
const returned_forward = func (left: State a) => return func (right: State a) => return staged left right
const bury_input = func value => return do:
  let kept = [value]
  break true
const input_identity = func value => return value
const input_first = func (pair: (a, b)) => return @product.get pair 0
const input_box = func value => return {cell: value}
const input_project = func value => return value.cell
const invoke_input = func value => return func callback => return callback value
const call = func callback => return callback ()
const call_second = func unused => return func callback => return callback ()
const wide16 = func unused0 => return func unused1 => return func unused2 => return func unused3 => return func unused4 => return func unused5 => return func unused6 => return func unused7 => return func unused8 => return func unused9 => return func unused10 => return func unused11 => return func unused12 => return func unused13 => return func unused14 => return func callback => return callback ()
const wide = func unused0 => return func unused1 => return func unused2 => return func unused3 => return func unused4 => return func unused5 => return func unused6 => return func unused7 => return func unused8 => return func unused9 => return func unused10 => return func unused11 => return func unused12 => return func unused13 => return func unused14 => return func unused15 => return func callback => return callback ()
const freeze = func value => return func () => return value
const bundle = func flag => return func (left: State a) => return func (right: State a) => return func initial => return do:
  let selected = forward flag left right
  break {cell: selected, read: func () => return selected.get (), provider: @effect.state selected.get selected.set initial}
`;
const main =
  `import {State, choose, forward, freeze, bundle, staged, returned_forward, Application, reset_scoped, call, call_second, partial, wide, wide16, twice, invoke_input, bury_input, input_identity, input_first, input_box, input_project} from "./generation"
entry const pattern_capture = func () => return reset_scoped ($Application {reset: func () => return 42}) ()
entry const answer = func (host: U32 -> U32 ! {Foreign}) => return @effect.scope (func (left: State U32) => return @effect.scope (func (right: State U32) => return do:
  let first = bundle true left right 7
  let second = bundle false left right 100
  let capture = freeze first.cell
  let alias = capture ()
  use a <- do first.provider:
    use b <- do second.provider:
      use x <- alias.get ()
      use y <- first.read ()
      use z <- second.read ()
      break host (@u32.add x (@u32.add y z))
    let (state, value) = b
    break value
  let (state, value) = a
  break value
))
entry const aliases = func () => return @effect.scope (func (left: State U32) => return @effect.scope (func (right: State U32) => return do:
  let selected = choose true left right
  use outer <- do (@effect.state left.get left.set 1):
    use inner <- do (@effect.state right.get right.set 2):
      use picked <- do (@effect.state selected.get selected.set 7):
        use a <- selected.get ()
        use b <- left.get ()
        break @u32.add a b
      let (state, value) = picked
      break value
    let (state, value) = inner
    break value
  let (state, value) = outer
  break value
))
entry const returned = func () => return @effect.scope (func (left: State U32) => return @effect.scope (func (right: State U32) => return do:
  let maker = returned_forward left right
  let selected = maker ()
  use handled <- do (@effect.state selected.first.get selected.first.set 9):
    use inner <- do (@effect.state selected.second.get selected.second.set 11):
      use first <- selected.first.get ()
      use second <- selected.second.get ()
      break @u32.add first second
    let (state, value) = inner
    break value
  let (state, value) = handled
  break value
))
entry const higher_order = func () => return @effect.scope (func (left: State U32) => return @effect.scope (func (right: State U32) => return do:
  let maker = returned_forward left right
  let selected = call maker
  use handled <- do (@effect.state selected.first.get selected.first.set 9):
    use inner <- do (@effect.state selected.second.get selected.second.set 11):
      use first <- selected.first.get ()
      use second <- selected.second.get ()
      break @u32.add first second
    let (state, value) = inner
    break value
  let (state, value) = handled
  break value
))
entry const projected_callback = func () => return @effect.scope (func (left: State U32) => return @effect.scope (func (right: State U32) => return do:
  let maker = returned_forward left right
  let container = {nested: {maker: maker, ordinary: func () => return 42}, unused: 99}
  let alias = container
  let selected = call alias.nested.maker
  use handled <- do (@effect.state selected.first.get selected.first.set 9):
    use inner <- do (@effect.state selected.second.get selected.second.set 11):
      use first <- selected.first.get ()
      use second <- selected.second.get ()
      break @u32.add first second
    let (state, value) = inner
    break value
  let (state, value) = handled
  break value
))
entry const product_callback = func () => return @effect.scope (func (left: State U32) => return @effect.scope (func (right: State U32) => return do:
  let maker = returned_forward left right
  let container = (maker, func () => return 42)
  let alias = container
  let selected = call (@product.get alias 0)
  use handled <- do (@effect.state selected.first.get selected.first.set 9):
    use inner <- do (@effect.state selected.second.get selected.second.set 11):
      use first <- selected.first.get ()
      use second <- selected.second.get ()
      break @u32.add first second
    let (state, value) = inner
    break value
  let (state, value) = handled
  break value
))
entry const capture_only_invocation = func () => return @effect.scope (func (left: State U32) => return @effect.scope (func (right: State U32) => return do:
  let maker = returned_forward left right
  let produced = call maker
  let saved = freeze produced
  let selected = call saved
  use handled <- do (@effect.state selected.first.get selected.first.set 9):
    use inner <- do (@effect.state selected.second.get selected.second.set 11):
      use first <- selected.first.get ()
      use second <- selected.second.get ()
      break @u32.add first second
    let (state, value) = inner
    break value
  let (state, value) = handled
  break value
))
entry const higher_order_twice = func () => return @effect.scope (func (left: State U32) => return @effect.scope (func (right: State U32) => return do:
  let maker = twice left right
  let selected = call maker
  use handled <- do (@effect.state selected.first.get selected.first.set 9):
    use inner <- do (@effect.state selected.second.get selected.second.set 11):
      use first <- selected.first.get ()
      use second <- selected.second.get ()
      break @u32.add first second
    let (state, value) = inner
    break value
  let (state, value) = handled
  break value
))
entry const higher_order_partial = func () => return @effect.scope (func (left: State U32) => return @effect.scope (func (right: State U32) => return do:
  let maker = partial left right
  let selected = call maker
  use handled <- do (@effect.state selected.first.get selected.first.set 9):
    use inner <- do (@effect.state selected.second.get selected.second.set 11):
      use first <- selected.first.get ()
      use second <- selected.second.get ()
      break @u32.add first second
    let (state, value) = inner
    break value
  let (state, value) = handled
  break value
))
entry const higher_order_inline = func () => return @effect.scope (func (left: State U32) => return @effect.scope (func (right: State U32) => return do:
  let maker = func () => return {first: left, second: if false then left else right}
  let selected = call maker
  use handled <- do (@effect.state selected.first.get selected.first.set 9):
    use inner <- do (@effect.state selected.second.get selected.second.set 11):
      use first <- selected.first.get ()
      use second <- selected.second.get ()
      break @u32.add first second
    let (state, value) = inner
    break value
  let (state, value) = handled
  break value
))
entry const higher_order_multi = func () => return @effect.scope (func (left: State U32) => return @effect.scope (func (right: State U32) => return do:
  let maker = returned_forward left right
  let selected = call_second 0 maker
  use handled <- do (@effect.state selected.first.get selected.first.set 9):
    use inner <- do (@effect.state selected.second.get selected.second.set 11):
      use first <- selected.first.get ()
      use second <- selected.second.get ()
      break @u32.add first second
    let (state, value) = inner
    break value
  let (state, value) = handled
  break value
))
entry const typed_input = func () => return @effect.scope (func (left: State U32) => return @effect.scope (func (right: State U32) => return do:
  let selected = invoke_input left (func (unused: State U32) => return if true then left else right)
  let alias = invoke_input selected input_identity
  use handled <- do (@effect.state selected.get selected.set 42):
    break invoke_input alias (func (actual: State U32) => return actual.get ())
  let (state, value) = handled
  break value
))
entry const typed_input_named = func () => return @effect.scope (func (older: State U32) => return do:
  let selected = @effect.scope (func (younger: State U32) => return invoke_input (older, younger) input_first)
  let wrapped = invoke_input selected input_box
  let alias = invoke_input wrapped input_project
  use handled <- do (@effect.state alias.get alias.set 44):
    break alias.get ()
  let (answer, final) = handled
  break answer
)
entry const typed_input_inline = func () => return @effect.scope (func (left: State U32) => return do:
  use handled <- do (@effect.state left.get left.set 43):
    break invoke_input left (func (actual: State U32) => return if true then actual.get () else 0)
  let (state, value) = handled
  break value
)
entry const ordinary_wide = func () => return wide16 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 (func () => return 42)
entry const discarded_generation = func flag => return @effect.scope (func (left: State U32) => return @effect.scope (func (right: State U32) => return do:
  let later = func () => return if flag then left else right
  break 42
))
entry const nested = func () => return @effect.scope (func (left: State U32) => return @effect.scope (func (right: State U32) => return do:
  let selected = choose false left (do:
    break choose true left right
  )
  use handled <- do (@effect.state selected.get selected.set 9):
    break selected.get ()
  let (state, value) = handled
  break value
))
`;
for (const codegenTier of ["optimized", "development"] as const) {
  Deno.test(`invocation generations preserve provider records captured versions and retained recovery (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({ prefix: "blot-generation-" });
    const entry = `${directory}/main.blot`;
    const dependency = `${directory}/generation.blot`;
    const archive = `${directory}/generation.blotdep`;
    try {
      await Deno.writeTextFile(entry, main);
      await Deno.writeTextFile(dependency, library);
      const packed = await new Deno.Command(executable, {
        args: ["dependencies", entry, archive, "--prelude", "none"],
        stdout: "piped",
        stderr: "piped",
      }).output();
      assert(
        packed.success,
        new TextDecoder().decode(packed.stdout) +
          new TextDecoder().decode(packed.stderr),
      );
      for (const dependencies of [undefined, archive]) {
        const compiler = await createZigProjectCompiler({
          executable,
          entry,
          prelude: null,
          dependencies,
          codegenTier,
          cacheDirectory: false,
        });
        try {
          const sources = { [entry]: main, [dependency]: library };
          const built = await compiler.build({ sources });
          assert(built.success, JSON.stringify(built));
          const guest = await instantiateGuest(built.bytes);
          try {
            const host = guest.capability({
              parameter: "U32",
              result: "U32",
              call: (value) => Number(value) + 2,
            });
            assert.equal(guest.call("answer", host), 116);
            assert.equal(guest.call("aliases", null), 14);
            assert.equal(guest.call("nested", null), 9);
            assert.equal(guest.call("returned", null), 20);
            assert.equal(guest.call("higher_order", null), 20);
            assert.equal(guest.call("capture_only_invocation", null), 20);
            assert.equal(guest.call("projected_callback", null), 20);
            assert.equal(guest.call("product_callback", null), 20);
            assert.equal(guest.call("higher_order_twice", null), 20);
            assert.equal(guest.call("higher_order_partial", null), 20);
            assert.equal(guest.call("higher_order_inline", null), 20);
            assert.equal(guest.call("higher_order_multi", null), 20);
            assert.equal(guest.call("pattern_capture", null), 42);
            assert.equal(guest.call("ordinary_wide", null), 42);
            assert.equal(guest.call("typed_input", null), 42);
            assert.equal(guest.call("typed_input_inline", null), 43);
            assert.equal(guest.call("typed_input_named", null), 44);
            assert.equal(guest.call("discarded_generation", true), 42);
            assert.equal(guest.call("discarded_generation", false), 42);
          } finally {
            guest.dispose();
          }
          const asynchronous = await instantiateGuest(built.bytes, {
            asynchronous: true,
          });
          try {
            const host = asynchronous.capabilityAsync({
              parameter: "U32",
              result: "U32",
              call: async (value) => {
                await Promise.resolve();
                return Number(value) + 2;
              },
            });
            assert.equal(await asynchronous.callAsync("answer", host), 116);
            const failure = asynchronous.capabilityAsync({
              parameter: "U32",
              result: "U32",
              call: () => Promise.reject(new Error("generation")),
            });
            await assert.rejects(asynchronous.callAsync("answer", failure));
            assert.equal(await asynchronous.callAsync("answer", host), 116);
          } finally {
            asynchronous.dispose();
          }
          if (dependencies === undefined) {
            const changed = await compiler.build({
              sources: {
                ...sources,
                [dependency]: library.replace(
                  "if flag then left else right",
                  "if flag then right else left",
                ),
              },
            });
            assert(changed.success, JSON.stringify(changed));
            const edited = await instantiateGuest(changed.bytes);
            try {
              assert.equal(edited.call("aliases", null), 8);
            } finally {
              edited.dispose();
            }
            const reverted = await compiler.build({ sources });
            assert(reverted.success, JSON.stringify(reverted));
            assert.deepEqual(reverted.bytes, built.bytes);
          }
          const checkpoint = await compiler.exportCheckpoint();
          const restored = await createZigProjectCompiler({
            executable,
            entry,
            prelude: null,
            dependencies,
            codegenTier,
            cacheDirectory: false,
            checkpoint,
          });
          try {
            const rebuilt = await restored.build({ sources });
            assert(rebuilt.success, JSON.stringify(rebuilt));
            assert.deepEqual(rebuilt.bytes, built.bytes);
          } finally {
            await restored.close();
          }

          for (
            const body of [
              "do:\n  let mixed = #[choose true left right, choose true left right]\n  break 1",
              "do:\n  let maker = returned_forward left right\n  let mixed = #[maker (), maker ()]\n  break 1",
              "do:\n  let maker = returned_forward left right\n  let mixed = #[call maker, call maker]\n  break 1",
              "do:\n  let maker = returned_forward left right\n  let mixed = #[call_second 0 maker, call_second 0 maker]\n  break 1",
              "@effect.scope (func (younger: State U32) => return call (func () => return choose true left younger))",
              "do:\n  let maker = func () => return if true then left else right\n  let mixed = #[call maker, call maker]\n  break 1",
              "do:\n  let maker = returned_forward left right\n  let mixed = #[wide 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 maker, wide 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 maker]\n  break 1",
              "invoke_input left bury_input",
              "@effect.scope (func (younger: State U32) => return invoke_input (younger, left) input_first)",
              "invoke_input left (func actual => return [actual])",
              "invoke_input left (func actual => return {cell: actual})",
              "invoke_input left (func (actual: State U32) => return @effect.state actual.get actual.set 0)",
              "invoke_input left (func (actual: State U32) => return func () => return actual.get ())",
              "invoke_input left (func (actual: State U32) => return if bury_input actual then 0 else 0)",
              "invoke_input left (func (actual: State U32) => return do:\n  let retained = func () => return actual.get ()\n  break 0)",
              "invoke_input left (func (actual: State U32) => return (func () => return actual.get ()) ())",
              "invoke_input left (func (actual: State U32) => return do (@effect.provider actual.get (func () => return actual.get ())):\n  break actual.get ())",
              "@effect.scope (func (younger: State U32) => return invoke_input left (func (unused: State U32) => return if true then left else younger))",
              "@effect.scope (func (younger: State U32) => return forward true left younger)",
              "@effect.scope (func (younger: State U32) => return bundle false left younger 7)",
            ]
          ) {
            const invalid = await compiler.build({
              sources: {
                ...sources,
                [entry]: main +
                  `entry const bad = func () => return @effect.scope (func (left: State U32) => return @effect.scope (func (right: State U32) => return ${body}))\n`,
              },
            });
            assert(
              !invalid.success,
              body,
            );
            assert(
              invalid.diagnostics.some((item) =>
                item.code === "type_mismatch" ||
                item.code === "capability_escape"
              ),
              JSON.stringify(invalid),
            );
            assert.deepEqual(await compiler.exportCheckpoint(), checkpoint);
          }
          const ordinaryWide = await compiler.build({
            sources: {
              ...sources,
              [entry]: main +
                "entry const too_wide = func () => return wide 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 (func () => return 42)\n",
            },
          });
          assert(!ordinaryWide.success);
          assert(
            ordinaryWide.diagnostics.some((item) => item.code === "complexity"),
            JSON.stringify(ordinaryWide),
          );
          assert.deepEqual(await compiler.exportCheckpoint(), checkpoint);
          const recovered = await compiler.build({ sources });
          assert(recovered.success, JSON.stringify(recovered));
        } finally {
          await compiler.close();
        }
      }
    } finally {
      await Deno.remove(directory, { recursive: true });
    }
  });
}
