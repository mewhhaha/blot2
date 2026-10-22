import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const library = `type State a is effect = {get: Unit -> a, set: a -> Unit}
const identity = fn value => value
const fields = fn (discarded: State a) => fn (retained: State b) => do:
  let dropped = fn () => do:
    let alias = discarded
    break alias.get ()
  let kept = fn () => do:
    let alias = retained
    break case (alias, 1) of
      (cell, number) => cell.get ()
  break {discarded: dropped, retained: kept}
const provider = fn unused => fn (state: State a) => fn implementation => @effect.provider state.get implementation
const state = fn unused => fn (state: State a) => fn initial => @effect.state state.get state.set initial
const computation = fn unused => fn action => @computation action
const select = fn value => value.retained
const select_pure: {discarded: a, retained: a} -> a = fn value => value.retained
const take_array = fn values => @array.get values 1
const take_second = fn (values: (a, b)) => @product.get values 1
const keep = fn unused => fn (state: State a) => {callbacks: #[(fn () => state.get ())]}
const aliases = fn unused => fn retained => do:
  let version = retained
  break {nested: #[version]}
opaque type Wrapper a = a
const wrap = fn unused => fn retained => #Wrapper retained
const unwrap = fn unused => fn wrapped => case wrapped of
  #Wrapper retained => retained
`;
const main =
  `import {State, identity, keep, aliases, wrap, unwrap, fields, select, select_pure, take_array, take_second, provider, state, computation} from "./values"
entry const answer = fn (host: U32 -> U32 ! {Foreign}) => @effect.scope (fn (older: State U32) => do:
  let bundle = @effect.scope (fn (younger: State F32) => do:
    let alias = fn () => older.get ()
    let version = identity alias
    let discarded = fn () => do:
      let ignored = younger
      break 1
    let retained = fn () => do:
      let ignored = older
      break 7
    break {provider: provider younger older (fn () => 11), state: state younger older 7, computation: computation younger (fn () => older.get ()), retained: keep younger older, nested: (version, #[version]), aliased: aliases younger version, wrapped: wrap younger version, selected: select (unwrap older (wrap younger (fields younger older))), array: take_array #[discarded, retained], product: take_second (discarded, retained), pure: select_pure {discarded: discarded, retained: retained}}
  )
  use provided <- do bundle.provider:
    break older.get ()
  use stored <- do bundle.state:
    break older.get ()
  let (cell, stored_value) = stored
  let resumed = do:
    for request in @requests bundle.computation:
      case request of
        effect older.get () =>
          yield 13
        complete value =>
          break value
  use handled <- do (@effect.state older.get older.set 7):
    use left <- (@array.get bundle.retained.callbacks 0) ()
    let (callback, callbacks) = bundle.nested
    use right <- callback ()
    use third <- (@array.get callbacks 0) ()
    use fourth <- (@array.get bundle.aliased.nested 0) ()
    use fifth <- (unwrap older bundle.wrapped) ()
    use sixth <- bundle.selected ()
    use seventh <- bundle.array ()
    use eighth <- bundle.product ()
    use ninth <- bundle.pure ()
    break host (@u32.add (@u32.add provided (@u32.add stored_value resumed)) (@u32.add ninth (@u32.add (@u32.add seventh eighth) (@u32.add sixth (@u32.add (@u32.add left right) (@u32.add third (@u32.add fourth fifth)))))))
  let (state, result) = handled
  break result
)
`;
for (const codegenTier of ["optimized", "development"] as const) {
  Deno.test(`value footprints preserve imported callable containers aliases and failed edits (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({ prefix: "blot-value-flow-" });
    const entry = `${directory}/main.blot`;
    const dependency = `${directory}/values.blot`;
    const archive = `${directory}/values.blotdep`;
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
            assert.equal(guest.call("answer", host), 96);
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
            assert.equal(await asynchronous.callAsync("answer", host), 96);
            const failure = asynchronous.capabilityAsync({
              parameter: "U32",
              result: "U32",
              call: () => Promise.reject(new Error("value flow")),
            });
            await assert.rejects(asynchronous.callAsync("answer", failure));
            assert.equal(await asynchronous.callAsync("answer", host), 96);
          } finally {
            asynchronous.dispose();
          }
          const checkpoint = await compiler.exportCheckpoint();
          if (dependencies === undefined) {
            const changed = await compiler.build({
              sources: {
                ...sources,
                [dependency]: library.replace(
                  "value.retained",
                  "value.discarded",
                ),
              },
            });
            assert(!changed.success, JSON.stringify(changed));
            assert(
              changed.diagnostics.some((item) =>
                item.code === "capability_escape"
              ),
            );
            assert.deepEqual(await compiler.exportCheckpoint(), checkpoint);
            const repaired = await compiler.build({ sources });
            assert(repaired.success, JSON.stringify(repaired));
          }
          const invalid = await compiler.build({
            sources: {
              ...sources,
              [entry]: main +
                `entry const bad = fn () => @effect.scope (fn (state: State U32) => do:
  let hidden = fn () => state.get ()
  break {nested: #[(hidden, 42)]}
)
`,
            },
          });
          assert(!invalid.success, JSON.stringify(invalid));
          assert(
            invalid.diagnostics.some((item) =>
              item.code === "capability_escape"
            ),
          );
          assert.deepEqual(await compiler.exportCheckpoint(), checkpoint);
          for (
            const result of [
              "provider 0 cell (fn () => 7)",
              "state 0 cell 7",
              "computation 0 (fn () => cell.get ())",
              "computation 0 (fn () => do:\n    let ignored = cell\n    break 7\n  )",
            ]
          ) {
            const escaped = await compiler.build({
              sources: {
                ...sources,
                [entry]: main +
                  `entry const escaped = fn () => @effect.scope (fn (cell: State U32) => ${result})\n`,
              },
            });
            assert(!escaped.success, JSON.stringify(escaped));
            assert(
              escaped.diagnostics.some((item) =>
                item.code === "capability_escape"
              ),
              JSON.stringify(escaped),
            );
            assert.deepEqual(await compiler.exportCheckpoint(), checkpoint);
          }
          const recovered = await compiler.build({ sources });
          assert(recovered.success, JSON.stringify(recovered));
          assert.deepEqual(recovered.bytes, built.bytes);
        } finally {
          await compiler.dispose();
        }
      }
    } finally {
      await Deno.remove(directory, { recursive: true });
    }
  });
}
