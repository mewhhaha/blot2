import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import {
  type DataValue,
  GuestError,
  type GuestOwner,
  instantiateGuest,
} from "../../compiler/guest.ts";
const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const library = `type Tree a is data = #Leaf a | #Branch (Tree a, Tree a)
opaque type Secret = {items: Array U32, nonce: U32}
const record = func (drop: cleanup ((unique {items: Array U32, nonce: U32}) -> Unit ! {Foreign})) => return @resource.scope (func () => return {nonce: 7, items: #[1, 2]}) drop (func loan => return 42)
const product = func (drop: cleanup ((unique (U32, Array F32)) -> Unit ! {Foreign})) => return @resource.scope (func () => return (7, #[1.5, 2.5])) drop (func loan => return 42)
const listed = func (drop: cleanup ((unique (List U32)) -> Unit ! {Foreign})) => return @resource.scope (func () => return [1, 2, 3]) drop (func loan => return 42)
const rows = func (drop: cleanup ((unique (Array (U32, F32))) -> Unit ! {Foreign})) => return @resource.scope (func () => return #[(7, 1.5), (9, 2.5)]) drop (func loan => return 42)
const row_list = func (drop: cleanup ((unique (List (U32, F32))) -> Unit ! {Foreign})) => return @resource.scope (func () => return [(7, 1.5), (9, 2.5)]) drop (func loan => return 42)
type Vector is data = #Vector {x: F32, y: F32}
type Matrix is data = #Matrix {a: Vector, b: Vector}
const matrix = #Matrix {a: #Vector {x: 1.5, y: 2.5}, b: #Vector {x: 3.5, y: 4.5}}
const matrix_rows = func (drop: cleanup ((unique (Array Matrix)) -> Unit ! {Foreign})) => return @resource.scope (func () => return #[matrix, matrix]) drop (func loan => return 42)
const matrix_list = func (drop: cleanup ((unique (List Matrix)) -> Unit ! {Foreign})) => return @resource.scope (func () => return [matrix, matrix]) drop (func loan => return 42)
const tree = func (drop: cleanup ((unique (Tree U32)) -> Unit ! {Foreign})) => return @resource.scope (func () => return #Branch (#Leaf 7, #Leaf 9)) drop (func loan => return 42)
const opaque_data = func (drop: cleanup ((unique Secret) -> Unit ! {Foreign})) => return @resource.scope (func () => return #Secret {items: #[1, 2], nonce: 7}) drop (func loan => return 42)
const make = func (drop: cleanup ((unique {items: Array U32, nonce: U32}) -> Unit ! {Foreign})) => return @resource.acquire (func () => return {nonce: 7, items: #[1, 2]}) drop
const release = func (owner: unique {items: Array U32, nonce: U32}) => return @resource.release owner
`;
const more =
  `const long_list = func (drop: cleanup ((unique (List U32)) -> Unit ! {Foreign})) => return @resource.scope (func () => return [${
    Array.from({ length: 500 }, (_, index) => index).join(", ")
  }]) drop (func loan => return 42)\n` +
  `const nested_list = func (drop: cleanup ((unique (List (Array U32))) -> Unit ! {Foreign})) => return @resource.scope (func () => return [#[1, 2], #[3, 4]]) drop (func loan => return 42)\n`;
const completeLibrary = library + more;
const names = [
  "long_list",
  "nested_list",
  "record",
  "product",
  "listed",
  "rows",
  "row_list",
  "matrix_rows",
  "matrix_list",
  "tree",
  "opaque_data",
  "make",
  "release",
];
const source = `import {${names.join(", ")}} from "./cleanup"\n` +
  names.map((name) =>
    `entry const ${name}_entry = func argument => return ${name} argument\n`
  ).join("");
const errorCode = (code: string) => (error: unknown) =>
  error instanceof GuestError && error.code === code;
for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`closed data cleanup descriptors preserve exact source and persistent lifetimes (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir();
    const entry = `${directory}/main.blot`,
      dependency = `${directory}/cleanup.blot`,
      archive = `${directory}/cleanup.blotdep`;
    await Deno.writeTextFile(entry, source);
    await Deno.writeTextFile(dependency, completeLibrary);
    try {
      const packed = await new Deno.Command(executable, {
        args: ["dependencies", entry, archive, "--prelude", "none"],
        stdout: "piped",
        stderr: "piped",
      }).output();
      assert(packed.success, new TextDecoder().decode(packed.stderr));
      let original: Uint8Array<ArrayBuffer> | undefined;
      for (const dependencies of [undefined, archive]) {
        const options = {
          executable,
          entry,
          prelude: null,
          cacheDirectory: false as const,
          codegenTier,
          dependencies,
        };
        const compiler = await createZigProjectCompiler(options);
        let restarted: typeof compiler | undefined;
        try {
          const first = await compiler.build({
            sources: { [entry]: source, [dependency]: completeLibrary },
          });
          assert(first.success, JSON.stringify(first));
          if (original) assert.deepEqual(first.bytes, original);
          else original = first.bytes;
          for (const asynchronous of [false, true]) {
            const guest = await instantiateGuest(first.bytes, { asynchronous });
            const invoke = async (name: string, argument: unknown) => {
              if (asynchronous) {
                return await guest.callAsync(`${name}_entry`, argument);
              }
              return guest.call(`${name}_entry`, argument);
            };
            try {
              assert.equal(guest.abi.version, 7);
              const values = new Map<string, DataValue[]>();
              const descriptors = new Map(
                names.filter((name) => name !== "release").map(
                  (name) => [
                    name,
                    guest.cleanupDataCapability({
                      type: guest.cleanupDataType(`${name}_entry`),
                      maxSteps: 256,
                      maxCalls: 2,
                      call(value) {
                        let trace = values.get(name);
                        if (!trace) {
                          trace = [];
                          values.set(name, trace);
                        }
                        trace.push(value);
                        return null;
                      },
                    }),
                  ],
                ),
              );
              for (
                const name of [
                  "long_list",
                  "nested_list",
                  "record",
                  "product",
                  "listed",
                  "rows",
                  "row_list",
                  "matrix_rows",
                  "matrix_list",
                  "tree",
                  "opaque_data",
                ]
              ) assert.equal(await invoke(name, descriptors.get(name)), 42);
              assert.deepEqual(values.get("record"), [{
                items: new Uint32Array([1, 2]),
                nonce: 7,
              }]);
              assert.deepEqual(values.get("product"), [[
                7,
                new Float32Array([1.5, 2.5]),
              ]]);
              assert.deepEqual(values.get("listed"), [[1, 2, 3]]);
              assert.deepEqual(values.get("long_list"), [
                Array.from({ length: 500 }, (_, index) => index),
              ]);
              assert.deepEqual(values.get("nested_list"), [[
                new Uint32Array([1, 2]),
                new Uint32Array([3, 4]),
              ]]);
              assert.deepEqual(values.get("rows"), [[[7, 1.5], [9, 2.5]]]);
              assert.deepEqual(values.get("row_list"), values.get("rows"));
              const matrix = {
                family: "Matrix",
                tag: 0,
                value: {
                  a: { family: "Vector", tag: 0, value: { x: 1.5, y: 2.5 } },
                  b: { family: "Vector", tag: 0, value: { x: 3.5, y: 4.5 } },
                },
              };
              assert.deepEqual(values.get("matrix_rows"), [[matrix, matrix]]);
              assert.deepEqual(
                values.get("matrix_list"),
                values.get("matrix_rows"),
              );
              assert.deepEqual(values.get("tree"), [{
                family: "Tree",
                tag: 1,
                value: [{ family: "Tree", tag: 0, value: 7 }, {
                  family: "Tree",
                  tag: 0,
                  value: 9,
                }],
              }]);
              assert.deepEqual(values.get("opaque_data"), [{
                kind: "opaque",
                type: "Secret",
              }]);
              const copied = values.get("record")![0] as {
                items: Uint32Array;
                nonce: number;
              };
              assert(Object.isFrozen(copied));
              copied.items[0] = 99;
              await invoke("record", descriptors.get("record"));
              assert.equal(
                (values.get("record")![1] as typeof copied).items[0],
                1,
              );
              const owner = await invoke(
                "make",
                descriptors.get("make"),
              ) as GuestOwner;
              assert.equal(values.get("make"), undefined);
              assert.equal(await invoke("release", owner), null);
              assert.deepEqual(values.get("make"), [{
                items: new Uint32Array([1, 2]),
                nonce: 7,
              }]);
              await assert.rejects(
                () => invoke("product", descriptors.get("record")),
                errorCode("capability_signature"),
              );
              const ordinary = guest.cleanupCapability({
                parameter: "U32",
                result: "Unit",
                maxSteps: 32,
                maxCalls: 1,
                call: () => null,
              });
              await assert.rejects(
                () => invoke("record", ordinary),
                errorCode("capability_signature"),
              );
              assert.throws(
                () =>
                  guest.cleanupDataCapability({
                    type: { name: "record" } as never,
                    maxSteps: 32,
                    maxCalls: 1,
                    call: () => null,
                  }),
                errorCode("invalid_capability"),
              );
              const failing = guest.cleanupDataCapability({
                type: guest.cleanupDataType("make_entry"),
                maxSteps: 32,
                maxCalls: 1,
                call: () => {
                  throw new Error("late structured cleanup");
                },
              });
              const doomed = await invoke("make", failing) as GuestOwner;
              assert.throws(
                () => guest.releaseOwner(doomed),
                errorCode("host_exception"),
              );
              assert.throws(
                () => guest.releaseOwner(doomed),
                errorCode("use_after_move"),
              );
              const promise = guest.cleanupDataCapability({
                type: guest.cleanupDataType("record_entry"),
                maxSteps: 32,
                maxCalls: 1,
                call: (() => Promise.resolve(null)) as unknown as () => null,
              });
              await assert.rejects(
                () => invoke("record", promise),
                errorCode("async_host_call"),
              );
              await invoke("record", descriptors.get("record"));
              const warmed = guest.memoryBytes();
              for (let index = 0; index < 128; index++) {
                const retained = await invoke(
                  "make",
                  descriptors.get("make"),
                ) as GuestOwner;
                guest.releaseOwner(retained);
                await invoke("tree", descriptors.get("tree"));
              }
              assert.equal(guest.memoryBytes(), warmed);
              const before = values.get("make")!.length;
              await invoke("make", descriptors.get("make"));
              guest.dispose();
              assert.equal(values.get("make")!.length, before + 1);
            } finally {
              guest.dispose();
            }
          }
          const checkpoint = await compiler.exportCheckpoint();
          const failed = await compiler.build({
            sources: {
              [dependency]: completeLibrary.replaceAll(
                "cleanup ((unique",
                "((unique",
              ),
            },
          });
          assert(!failed.success);
          const recovered = await compiler.build({
            sources: { [dependency]: completeLibrary },
          });
          assert(recovered.success);
          assert.deepEqual(recovered.bytes, first.bytes);
          assert.deepEqual(await compiler.exportCheckpoint(), checkpoint);
          restarted = await createZigProjectCompiler({
            ...options,
            checkpoint,
          });
          const restored = await restarted.build({
            sources: { [entry]: source, [dependency]: completeLibrary },
          });
          assert(restored.success);
          assert.deepEqual(restored.bytes, first.bytes);
        } finally {
          await compiler.dispose();
          await restarted?.dispose();
        }
      }
    } finally {
      await Deno.remove(directory, { recursive: true });
    }
  });
}

Deno.test("scoped structured cleanup needs no persistent owner ABI", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`;
  const scoped =
    `entry const answer = func (drop: cleanup ((unique {items: Array U32, nonce: U32}) -> Unit ! {Foreign})) => return @resource.scope (func () => return {nonce: 7, items: #[1, 2]}) drop (func loan => return 42)\n` +
    `entry const abandoned = func (drop: cleanup ((unique {items: Array U32, nonce: U32}) -> Unit ! {Foreign})) => return do:
  use owner <- @resource.acquire (func () => return {nonce: 7, items: #[1, 2]}) drop
  let transfer: once (Unit -> unique {items: Array U32, nonce: U32}) = func () => return owner
  break 42
`;
  try {
    for (const codegenTier of ["development", "optimized"] as const) {
      const compiler = await createZigProjectCompiler({
        executable,
        entry,
        prelude: null,
        cacheDirectory: false,
        codegenTier,
      });
      try {
        const built = await compiler.build({ sources: { [entry]: scoped } });
        assert(built.success, JSON.stringify(built));
        for (const asynchronous of [false, true]) {
          const guest = await instantiateGuest(built.bytes, { asynchronous });
          try {
            assert.equal(guest.abi.version, 7);
            assert.equal(guest.abi.publicOwners, false);
            const values: DataValue[] = [];
            const drop = guest.cleanupDataCapability({
              type: guest.cleanupDataType("answer"),
              maxSteps: 32,
              maxCalls: 1,
              call: (value) => {
                values.push(value);
                return null;
              },
            });
            if (asynchronous) {
              assert.equal(await guest.callAsync("answer", drop), 42);
            } else assert.equal(guest.call("answer", drop), 42);
            assert.deepEqual(values, [{
              items: new Uint32Array([1, 2]),
              nonce: 7,
            }]);
            if (asynchronous) {
              assert.equal(await guest.callAsync("abandoned", drop), 42);
            } else assert.equal(guest.call("abandoned", drop), 42);
            assert.equal(values.length, 2);
            assert.deepEqual(values[1], {
              items: new Uint32Array([1, 2]),
              nonce: 7,
            });
          } finally {
            guest.dispose();
          }
        }
      } finally {
        await compiler.dispose();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
