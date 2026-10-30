import { strict as assert } from "node:assert";
import { compileAndRun } from "./reduction_helpers.ts";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const stdRoot = new URL("../../std", import.meta.url).pathname;
const source = `
import * as iter from "std/iter"
entry const run = func count => return iter.fold_left add 0
  (iter.take count (iter.map (func value => return value + 1) (iter.range 0 count)))
entry const effects = func (host: U32 -> U32 ! {Foreign}) => return
  iter.fold_left (func total => return func value => return host (total + value)) 0 (iter.range 0 8)
entry const references = func count => return do:
  let initial = #[8192]
  let answer = iter.fold_left (func total => return func value => return #[total[0] + value]) initial (iter.range 0 count)
  break #[initial[0], answer[0]]
`;

Deno.test("private table projection keeps scalar folds reference publication and suspended effect order", async () => {
  await compileAndRun(source, async (_, bytes) => {
    for (const asynchronous of [false, true]) {
      const guest = await instantiateGuest(bytes, { asynchronous });
      try {
        for (const count of [0, 1, 63, 244, 4096]) {
          let answer;
          let references;
          if (asynchronous) {
            answer = await guest.callAsync("run", count);
            references = await guest.callAsync("references", count);
          } else {
            answer = guest.call("run", count);
            references = guest.call("references", count);
          }
          assert.equal(answer, count * (count + 1) / 2);
          assert.deepEqual(
            references,
            Uint32Array.of(8192, 8192 + count * (count - 1) / 2),
          );
        }
        let reject = false;
        let trace: number[] = [];
        const call = (value: number) => {
          trace.push(value);
          if (reject && trace.length === 4) throw new Error("projection host");
          return value;
        };
        let capability;
        if (asynchronous) {
          capability = guest.capabilityAsync({
            parameter: "U32",
            result: "U32",
            call: async (value: number) => {
              await Promise.resolve();
              return call(value);
            },
          });
        } else {
          capability = guest.capability({
            parameter: "U32",
            result: "U32",
            call,
          });
        }
        for (let repetition = 0; repetition < 3; repetition++) {
          trace = [];
          if (asynchronous) {
            assert.equal(await guest.callAsync("effects", capability), 28);
          } else assert.equal(guest.call("effects", capability), 28);
          assert.deepEqual(trace, [0, 1, 3, 6, 10, 15, 21, 28]);
          trace = [];
          reject = true;
          if (asynchronous) {
            await assert.rejects(guest.callAsync("effects", capability));
          } else assert.throws(() => guest.call("effects", capability));
          assert.deepEqual(trace, [0, 1, 3, 6]);
          reject = false;
        }
      } finally {
        guest.dispose();
      }
    }
  }, { stdRoot });
});

Deno.test("table projection consumes exact changed source bodies in retained and portable replay", async () => {
  const directory = await Deno.makeTempDir({
    prefix: "blot-table-projection-",
  });
  const entry = `${directory}/main.blot`;
  const helper = `${directory}/reduce.blot`;
  const program =
    `import * as iter from "std/iter"\nimport * as reduce from "./reduce"\nentry const run = func count => return iter.fold_left reduce.add 0 (iter.range 0 count)\n`;
  try {
    for (const codegenTier of ["optimized", "development"] as const) {
      const options = {
        executable: Deno.args[0],
        entry,
        codegenTier,
        prelude: new URL("../../std/prelude.blot", import.meta.url).pathname,
        stdRoot,
        cacheDirectory: false as const,
      };
      const retained = await createZigProjectCompiler(options);
      let checkpoint;
      try {
        for (const offset of [0, 0, 1, 0]) {
          const sources = {
            [entry]: program,
            [helper]:
              `const add = func (left: U32) => return func (right: U32) => return left + right + ${offset}\n`,
          };
          const built = await retained.build({ sources });
          const fresh = await createZigProjectCompiler(options);
          try {
            const ordinary = await fresh.build({ sources });
            assert(built.success && ordinary.success);
            assert.deepEqual(built.bytes, ordinary.bytes);
            const guest = await instantiateGuest(built.bytes);
            try {
              assert.equal(guest.call("run", 63), 1953 + offset * 63);
            } finally {
              guest.dispose();
            }
          } finally {
            await fresh.dispose();
          }
        }
        checkpoint = await retained.exportCheckpoint();
      } finally {
        await retained.dispose();
      }
      const resumed = await createZigProjectCompiler({
        ...options,
        checkpoint,
      });
      const fresh = await createZigProjectCompiler(options);
      try {
        const sources = {
          [entry]: program,
          [helper]:
            "const add = func (left: U32) => return func (right: U32) => return left + right + 1\n",
        };
        const built = await resumed.build({ sources });
        const ordinary = await fresh.build({ sources });
        assert(built.success && ordinary.success);
        assert.deepEqual(built.bytes, ordinary.bytes);
        if (codegenTier === "optimized") {
          const optimization = built.stats.runtimeOptimization as Record<
            string,
            number
          >;
          assert(optimization.reused > 0, JSON.stringify(optimization));
        }
      } finally {
        await resumed.dispose();
        await fresh.dispose();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
