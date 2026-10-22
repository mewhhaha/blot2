import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const library = `type State a is effect = {get: Unit -> a, set: a -> Unit}
type Application is data = #Application {reset: Unit -> U32}
const reset_scoped = fn application => fn () => do:
  let #Application {reset} = application
  break reset ()
const choose = fn flag => fn (left: State a) => fn (right: State a) => if flag then left else right
const forward = fn flag => fn (left: State a) => fn (right: State a) => choose flag left right
const staged = fn (left: State a) => fn (middle: State a) => do:
  let first = if #True then left else middle
  break fn () => {first: first, second: if #False then left else middle}
const partial = fn (left: State a) => fn (middle: State a) => fn () => {first: left, second: if #False then left else middle}
const twice = fn (left: State a) => fn (right: State a) => fn () => {first: if #True then left else right, second: if #False then left else right}
const returned_forward = fn (left: State a) => fn (right: State a) => staged left right
const bury_input = fn value => do:
  let kept = [value]
  break #True
const input_identity = fn value => value
const input_first = fn (pair: (a, b)) => @product.get pair 0
const input_box = fn value => {cell: value}
const input_project = fn value => value.cell
const invoke_input = fn value => fn callback => callback value
const call = fn callback => callback ()
const call_second = fn unused => fn callback => callback ()
const wide16 = fn unused0 => fn unused1 => fn unused2 => fn unused3 => fn unused4 => fn unused5 => fn unused6 => fn unused7 => fn unused8 => fn unused9 => fn unused10 => fn unused11 => fn unused12 => fn unused13 => fn unused14 => fn callback => callback ()
const wide = fn unused0 => fn unused1 => fn unused2 => fn unused3 => fn unused4 => fn unused5 => fn unused6 => fn unused7 => fn unused8 => fn unused9 => fn unused10 => fn unused11 => fn unused12 => fn unused13 => fn unused14 => fn unused15 => fn callback => callback ()
const freeze = fn value => fn () => value
const bundle = fn flag => fn (left: State a) => fn (right: State a) => fn initial => do:
  let selected = forward flag left right
  break {cell: selected, read: fn () => selected.get (), provider: @effect.state selected.get selected.set initial}
`;
const main =
  `import {State, choose, forward, freeze, bundle, staged, returned_forward, Application, reset_scoped, call, call_second, partial, wide, wide16, twice, invoke_input, bury_input, input_identity, input_first, input_box, input_project} from "./generation"
entry const pattern_capture = fn () => reset_scoped (#Application {reset: fn () => 42}) ()
entry const answer = fn (host: U32 -> U32 ! {Foreign}) => @effect.scope (fn (left: State U32) => @effect.scope (fn (right: State U32) => do:
  let first = bundle #True left right 7
  let second = bundle #False left right 100
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
entry const aliases = fn () => @effect.scope (fn (left: State U32) => @effect.scope (fn (right: State U32) => do:
  let selected = choose #True left right
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
entry const returned = fn () => @effect.scope (fn (left: State U32) => @effect.scope (fn (right: State U32) => do:
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
entry const higher_order = fn () => @effect.scope (fn (left: State U32) => @effect.scope (fn (right: State U32) => do:
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
entry const projected_callback = fn () => @effect.scope (fn (left: State U32) => @effect.scope (fn (right: State U32) => do:
  let maker = returned_forward left right
  let container = {nested: {maker: maker, ordinary: fn () => 42}, unused: 99}
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
entry const product_callback = fn () => @effect.scope (fn (left: State U32) => @effect.scope (fn (right: State U32) => do:
  let maker = returned_forward left right
  let container = (maker, fn () => 42)
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
entry const capture_only_invocation = fn () => @effect.scope (fn (left: State U32) => @effect.scope (fn (right: State U32) => do:
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
entry const higher_order_twice = fn () => @effect.scope (fn (left: State U32) => @effect.scope (fn (right: State U32) => do:
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
entry const higher_order_partial = fn () => @effect.scope (fn (left: State U32) => @effect.scope (fn (right: State U32) => do:
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
entry const higher_order_inline = fn () => @effect.scope (fn (left: State U32) => @effect.scope (fn (right: State U32) => do:
  let maker = fn () => {first: left, second: if #False then left else right}
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
entry const higher_order_multi = fn () => @effect.scope (fn (left: State U32) => @effect.scope (fn (right: State U32) => do:
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
entry const typed_input = fn () => @effect.scope (fn (left: State U32) => @effect.scope (fn (right: State U32) => do:
  let selected = invoke_input left (fn (unused: State U32) => if #True then left else right)
  let alias = invoke_input selected input_identity
  use handled <- do (@effect.state selected.get selected.set 42):
    break invoke_input alias (fn (actual: State U32) => actual.get ())
  let (state, value) = handled
  break value
))
entry const typed_input_named = fn () => @effect.scope (fn (older: State U32) => do:
  let selected = @effect.scope (fn (younger: State U32) => invoke_input (older, younger) input_first)
  let wrapped = invoke_input selected input_box
  let alias = invoke_input wrapped input_project
  use handled <- do (@effect.state alias.get alias.set 44):
    break alias.get ()
  let (answer, final) = handled
  break answer
)
entry const typed_input_inline = fn () => @effect.scope (fn (left: State U32) => do:
  use handled <- do (@effect.state left.get left.set 43):
    break invoke_input left (fn (actual: State U32) => if #True then actual.get () else 0)
  let (state, value) = handled
  break value
)
entry const ordinary_wide = fn () => wide16 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 (fn () => 42)
entry const discarded_generation = fn flag => @effect.scope (fn (left: State U32) => @effect.scope (fn (right: State U32) => do:
  let later = fn () => if flag then left else right
  break 42
))
entry const nested = fn () => @effect.scope (fn (left: State U32) => @effect.scope (fn (right: State U32) => do:
  let selected = choose #False left (do:
    break choose #True left right
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
              "do:\n  let mixed = #[choose #True left right, choose #True left right]\n  break 1",
              "do:\n  let maker = returned_forward left right\n  let mixed = #[maker (), maker ()]\n  break 1",
              "do:\n  let maker = returned_forward left right\n  let mixed = #[call maker, call maker]\n  break 1",
              "do:\n  let maker = returned_forward left right\n  let mixed = #[call_second 0 maker, call_second 0 maker]\n  break 1",
              "@effect.scope (fn (younger: State U32) => call (fn () => choose #True left younger))",
              "do:\n  let maker = fn () => if #True then left else right\n  let mixed = #[call maker, call maker]\n  break 1",
              "do:\n  let maker = returned_forward left right\n  let mixed = #[wide 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 maker, wide 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 maker]\n  break 1",
              "invoke_input left bury_input",
              "@effect.scope (fn (younger: State U32) => invoke_input (younger, left) input_first)",
              "invoke_input left (fn actual => [actual])",
              "invoke_input left (fn actual => {cell: actual})",
              "invoke_input left (fn (actual: State U32) => @effect.state actual.get actual.set 0)",
              "invoke_input left (fn (actual: State U32) => fn () => actual.get ())",
              "invoke_input left (fn (actual: State U32) => if bury_input actual then 0 else 0)",
              "invoke_input left (fn (actual: State U32) => do:\n  let retained = fn () => actual.get ()\n  break 0)",
              "invoke_input left (fn (actual: State U32) => (fn () => actual.get ()) ())",
              "invoke_input left (fn (actual: State U32) => do (@effect.provider actual.get (fn () => actual.get ())):\n  break actual.get ())",
              "@effect.scope (fn (younger: State U32) => invoke_input left (fn (unused: State U32) => if #True then left else younger))",
              "@effect.scope (fn (younger: State U32) => forward #True left younger)",
              "@effect.scope (fn (younger: State U32) => bundle #False left younger 7)",
            ]
          ) {
            const invalid = await compiler.build({
              sources: {
                ...sources,
                [entry]: main +
                  `entry const bad = fn () => @effect.scope (fn (left: State U32) => @effect.scope (fn (right: State U32) => ${body}))\n`,
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
                "entry const too_wide = fn () => wide 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 (fn () => 42)\n",
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
