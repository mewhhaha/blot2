import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../compiler/zig_project_client.ts";
import { instantiateGuest } from "../compiler/guest.ts";
import { observeGuestAllocations } from "./bench/guest_heap_observer.ts";

import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

// Records exact executable-section differences as well as observable behavior.
// An executable_identical=false row is evidence to investigate, not erasure proof.
const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const executable = resolve(
  Deno.args[0] ?? root + "/zig-native/zig-out/bin/blotc",
);
const output = resolve(
  Deno.args[1] ?? root + "/build/bench/task053-wrapper-contexts",
);
await Deno.mkdir(dirname(output), { recursive: true });
await Deno.mkdir(output);
const hash = async (bytes: Uint8Array<ArrayBuffer>) =>
  [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))]
    .map((x) => x.toString(16).padStart(2, "0")).join("");
const inputPaths = {
  compiler_sha256: executable,
  harness_sha256: fileURLToPath(import.meta.url),
  observer_sha256: root + "/scripts/bench/guest_heap_observer.ts",
  client_sha256: root + "/compiler/zig_project_client.ts",
  guest_sha256: root + "/compiler/guest.ts",
};
const pins = Object.fromEntries(
  await Promise.all(
    Object.entries(inputPaths).map(async (
      [key, path],
    ) => [key, await hash(await Deno.readFile(path))]),
  ),
);
function sections(bytes: Uint8Array<ArrayBuffer>) {
  let cursor = 8;
  const result: Uint8Array<ArrayBuffer>[] = [];
  while (cursor < bytes.length) {
    const start = cursor, id = bytes[cursor++];
    let length = 0, shift = 0, byte: number;
    do {
      byte = bytes[cursor++];
      length += (byte & 127) * 2 ** shift;
      shift += 7;
      assert(shift <= 35);
    } while (byte & 128);
    cursor += length;
    assert(cursor <= bytes.length);
    if (id !== 0) result.push(bytes.slice(start, cursor));
  }
  assert.equal(cursor, bytes.length);
  return result;
}
function word(bytes: Uint8Array<ArrayBuffer>, state: { cursor: number }) {
  let result = 0, shift = 0, byte: number;
  do {
    byte = bytes[state.cursor++];
    result += (byte & 127) * 2 ** shift;
    shift += 7;
    assert(shift <= 35);
  } while (byte & 128);
  return result;
}
function machineBodies(bytes: Uint8Array<ArrayBuffer>) {
  const types: Uint8Array<ArrayBuffer>[] = [];
  const functions: number[] = [];
  const bodies: Uint8Array<ArrayBuffer>[] = [];
  const exports = new Map<string, number>();
  let cursor = 8;
  while (cursor < bytes.length) {
    const id = bytes[cursor++];
    const sizeState = { cursor };
    const size = word(bytes, sizeState);
    cursor = sizeState.cursor;
    const end = cursor + size;
    const state = { cursor };
    if (id === 1) {
      const count = word(bytes, state);
      for (let index = 0; index < count; index++) {
        const start = state.cursor;
        assert.equal(bytes[state.cursor++], 0x60);
        const parameters = word(bytes, state);
        state.cursor += parameters;
        const results = word(bytes, state);
        state.cursor += results;
        types.push(bytes.slice(start, state.cursor));
      }
    } else if (id === 3) {
      const count = word(bytes, state);
      for (let index = 0; index < count; index++) {
        functions.push(word(bytes, state));
      }
    } else if (id === 7) {
      const count = word(bytes, state);
      for (let index = 0; index < count; index++) {
        const length = word(bytes, state);
        const name = new TextDecoder().decode(
          bytes.slice(state.cursor, state.cursor + length),
        );
        state.cursor += length;
        const kind = bytes[state.cursor++];
        const target = word(bytes, state);
        if (kind === 0) exports.set(name, target);
      }
    } else if (id === 10) {
      const count = word(bytes, state);
      for (let index = 0; index < count; index++) {
        const length = word(bytes, state);
        bodies.push(bytes.slice(state.cursor, state.cursor + length));
        state.cursor += length;
      }
    }
    if (id === 1 || id === 3 || id === 7 || id === 10) {
      assert.equal(state.cursor, end);
    }
    cursor = end;
  }
  assert.equal(functions.length, bodies.length);
  const imported = WebAssembly.Module.imports(new WebAssembly.Module(bytes))
    .filter((entry) => entry.kind === "function").length;
  const hex = (value: Uint8Array<ArrayBuffer>) =>
    [...value].map((byte) => byte.toString(16).padStart(2, "0")).join("");
  const exported = Object.fromEntries(
    ["run", "captured", "identity", "trap", "effects"].map((name) => {
      const target = exports.get(name);
      assert(target !== undefined && target >= imported);
      const defined = target - imported;
      assert(defined < bodies.length && functions[defined] < types.length);
      return [name, {
        type: hex(types[functions[defined]]),
        body: hex(bodies[defined]),
      }];
    }),
  );
  return {
    exported,
    functions: bodies.map((body, index) => ({
      type: hex(types[functions[index]]),
      body: hex(body),
    })),
  };
}
const rows: unknown[] = [];
const cases = ["u32", "f32", "reference", "generic_record"] as const;
for (const shape of cases) {
  const scalar = shape === "u32" || shape === "f32";
  const type = shape === "f32" ? "F32" : "U32";
  const add = shape === "f32" ? "@f32.add" : "@u32.add";
  const generic = shape === "generic_record";
  const nominal = generic ? "Token a" : "Token";
  const input = scalar ? type : generic ? "a" : "Array U32";
  const representation = scalar ? type : generic ? "{value:a}" : "Array U32";
  const lib = (opaque: boolean, bonus: number) =>
    `${opaque ? "opaque " : ""}type ${nominal} = ${representation}
const make: ${input} -> ${nominal} = func value => return ${
      opaque ? "#Token " : ""
    }${generic ? "{value}" : "value"}
const read: ${nominal} -> ${input} = func ${
      opaque ? "(#Token value)" : "value"
    } => ${generic ? "value.value" : "value"}
const capture = func value => return do:
  let saved = make value
  break func () => return read saved
const bonus: ${type} = ${bonus}${shape === "f32" ? ".0" : ""}
`;
  const main = `import {make, read, capture, bonus} from "./library"
entry const run = func (value: ${type}) => return ${
    scalar ? `${add} (read (make value)) bonus` : `do:
  let original = #[value, 7]
  let alias = read (make original)
  original[0] := 0
  break @u32.add alias[0] bonus`
  }
entry const captured = func (value: ${type}) => return ${
    scalar ? `${add} ((capture value) ()) bonus` : `do:
  let original = #[value, 7]
  let saved = capture original
  original[0] := 0
  break @u32.add (saved ())[0] bonus`
  }
entry const identity = func (value: ${type}) => return ${
    scalar ? "read (make value)" : "(read (make #[value]))[0]"
  }
entry const trap = func (index: U32) => return @array.get ${
    scalar
      ? `#[read (make 42${shape === "f32" ? ".0" : ""})]`
      : "(read (make #[42]))"
  } index
entry const effects = func (host: ${type} -> ${type} ! {Foreign}) => return do:
  use first <- host 40${shape === "f32" ? ".0" : ""}
  let wrapped = make ${scalar ? "first" : "#[first]"}
  use second <- host ${scalar ? "(read wrapped)" : "(read wrapped)[0]"}
  break second
`;
  for (const tier of ["development", "optimized"] as const) {
    const machine = new Map<string, Uint8Array<ArrayBuffer>[]>();
    const exportedMachines = new Map<
      string,
      ReturnType<typeof machineBodies>
    >();
    const allocations = new Map<
      string,
      ReturnType<typeof observeGuestAllocations>
    >();
    for (const opaque of [false, true]) {
      const dir = `${output}/${shape}-${tier}-${opaque ? "opaque" : "plain"}`;
      await Deno.mkdir(dir);
      const entry = dir + "/main.blot", library = dir + "/library.blot";
      await Deno.writeTextFile(entry, main);
      await Deno.writeTextFile(library, lib(opaque, 2));
      const dependencies = dir + "/dependencies.blotdep";
      const packed = await new Deno.Command(executable, {
        args: ["dependencies", entry, dependencies, "--prelude", "none"],
        stdout: "piped",
        stderr: "piped",
      }).output();
      assert(
        packed.success,
        new TextDecoder().decode(packed.stdout) +
          new TextDecoder().decode(packed.stderr),
      );
      const options = {
        executable,
        entry,
        prelude: null,
        cacheDirectory: false as const,
        codegenTier: tier,
      };
      for (const archived of [false, true]) {
        const compiler = await createZigProjectCompiler({
          ...options,
          dependencies: archived ? dependencies : undefined,
        });
        try {
          for (
            const [phase, bonus] of [["initial", 2], ["edit", 3], [
              "revert",
              2,
            ]] as const
          ) {
            const sources = { [library]: lib(opaque, bonus) };
            const built = await compiler.build({ sources });
            assert(built.success, JSON.stringify(built));
            const fresh = await createZigProjectCompiler(options);
            try {
              const control = await fresh.build({ sources });
              assert(control.success, JSON.stringify(control));
              assert.deepEqual(built.bytes, control.bytes);
            } finally {
              await fresh.dispose();
            }
            const key = `${archived}-${phase}`;
            const executableSections = sections(built.bytes);
            if (!opaque) machine.set(key, executableSections);
            const exact = !opaque ||
              JSON.stringify(
                  await Promise.all(executableSections.map(hash)),
                ) ===
                JSON.stringify(await Promise.all(machine.get(key)!.map(hash)));
            const exported = machineBodies(built.bytes);
            if (!opaque) exportedMachines.set(key, exported);
            const exportedMachineIdentical = !opaque ||
              JSON.stringify(exported.exported) ===
                JSON.stringify(exportedMachines.get(key)!.exported);
            assert(exportedMachineIdentical);
            const functionBodiesIdentical = !opaque ||
              JSON.stringify(exported.functions) ===
                JSON.stringify(exportedMachines.get(key)!.functions);
            assert(
              functionBodiesIdentical,
              `${shape}/${tier}/${key}: private function bodies differ`,
            );
            const rawEffects: number[] = [];
            const traffic = observeGuestAllocations(
              built.bytes,
              [
                ["run", 40, 40 + bonus],
                ["captured", 40, 40 + bonus],
                ["identity", 40, 40],
                ["trap", 2, "trap"],
                ["effects", 123, 42],
              ],
              {
                host: (module, name, args) => {
                  assert.equal(module, "blot:host/1");
                  assert.equal(
                    name,
                    `call_${type.toLowerCase()}_${type.toLowerCase()}`,
                  );
                  assert.equal(args.length, 2);
                  assert.equal(args[0], 123);
                  rawEffects.push(args[1]);
                  return args[1] + 1;
                },
              },
            );
            assert.deepEqual(
              rawEffects,
              Array.from({ length: 208 }, (_, index) => 40 + index % 2),
            );
            if (!opaque) allocations.set(key, traffic);
            const allocationIdentical = !opaque ||
              JSON.stringify(traffic) === JSON.stringify(allocations.get(key));
            assert(allocationIdentical);
            const guest = await instantiateGuest(built.bytes);
            let memory: number;
            try {
              for (const name of ["run", "captured"]) {
                for (const value of [0, 40, 1000]) {
                  assert.equal(guest.call(name, value), value + bonus);
                }
              }
              for (
                const value of shape === "f32"
                  ? [-0, NaN, Infinity, -Infinity]
                  : [0, 0xffffffff]
              ) assert.equal(guest.call("identity", value), value);
              assert.throws(() => guest.call("trap", 2));
              assert.equal(guest.call("run", 40), 40 + bonus);
              const seen: number[] = [];
              const host = guest.capability({
                parameter: type,
                result: type,
                call: (value: number) => {
                  seen.push(value);
                  return value + 1;
                },
              });
              assert.equal(guest.call("effects", host), 42);
              assert.deepEqual(seen, [40, 41]);
              const warm = guest.memoryBytes();
              for (let n = 0; n < 100; n++) {
                assert.equal(guest.call("run", 40), 40 + bonus);
                assert.equal(guest.call("captured", 40), 40 + bonus);
              }
              memory = guest.memoryBytes();
              assert.equal(memory, warm);
            } finally {
              guest.dispose();
            }
            const checkpoint = await compiler.exportCheckpoint();
            const restarted = await createZigProjectCompiler({
              ...options,
              checkpoint,
            });
            try {
              const restored = await restarted.build({ sources });
              assert(restored.success, JSON.stringify(restored));
              assert.deepEqual(restored.bytes, built.bytes);
            } finally {
              await restarted.dispose();
            }
            const row = {
              shape,
              tier,
              opaque,
              archived,
              phase,
              executable_identical: exact,
              exported_machine_identical: exportedMachineIdentical,
              function_bodies_identical: functionBodiesIdentical,
              allocation_identical: allocationIdentical,
              guest_visible_memory_bytes: memory,
              allocation_traffic: traffic,
              wasm_sha256: await hash(built.bytes),
              section_hashes: await Promise.all(executableSections.map(hash)),
              stats: built.stats,
            };
            rows.push(row);
            console.log(
              JSON.stringify({
                shape,
                tier,
                opaque,
                archived,
                phase,
                executable_identical: exact,
                exported_machine_identical: exportedMachineIdentical,
                function_bodies_identical: functionBodiesIdentical,
                allocation_identical: allocationIdentical,
                guest_visible_memory_bytes: memory,
                allocation_traffic: traffic,
              }),
            );
            await Deno.writeFile(
              `${dir}/${archived}-${phase}.wasm`,
              built.bytes,
            );
          }
        } finally {
          await compiler.dispose();
        }
      }
    }
  }
}
for (const [key, path] of Object.entries(inputPaths)) {
  assert.equal(await hash(await Deno.readFile(path)), pins[key]);
}
await Deno.writeTextFile(
  output + "/results.json",
  JSON.stringify(
    {
      ...pins,
      rows,
    },
    null,
    2,
  ) + "\n",
);
