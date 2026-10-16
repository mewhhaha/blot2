import { strict as assert } from "node:assert";
import { instantiateGuest } from "../../compiler/guest.ts";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url);
const producer = (captured = "35", increment = "1", valid = true) => {
  let chosen = "value";
  if (!valid) chosen = "42";
  return `
type Maybe a is data = #Some a | #None
type Render a is contract = { const show: a -> U32 }
impl Number : Render U32 = { const show = fn value => @u32.add value ${increment} }
impl Flag : Render Bool = { const show = fn value => if value then 7 else 9 }
const choose: forall [a] => a -> a = fn value => ${chosen}
const make: U32 -> (forall [a] => a -> a) = fn captured => fn item => do:
  let ignored = @u32.add captured 1
  return item
const trace: U32 -> (forall [a] => ((U32 -> U32 ! {Foreign}), a) -> a ! {Foreign}) = fn captured => fn pair => do:
  (@product.get pair 0) captured
  return @product.get pair 1
const show: forall [a] where { Render a } => a -> U32 = fn value => Render.show value
const wrap: forall [a] => a -> Maybe a = #Some
const apply: forall [a, row e] => ((a -> a ! {|e}), a) -> a ! {|e} = fn pair => (@product.get pair 0) (@product.get pair 1)
const packet = do:
  let cost = 35
  for index in 0..256:
    cost := @u32.add self 1
  return {choose, other: make ${captured}, traced: trace ${captured}, show, wrap, apply, cost}
`;
};
const consumer = (seed = "2") =>
  `import {packet, Some, None, Render} from "./producer"
entry const whole = fn () => packet.choose packet.cost
entry const fraction = fn () => packet.other 3.5
entry const shown = fn () => @u32.add (packet.show 35) (packet.show #True)
entry const wrapped = fn () => case packet.wrap packet.cost of
  #Some value => value
  #None => 0
entry const host = fn (callback: U32 -> U32 ! {Foreign}) => packet.apply (callback, packet.cost)
entry const captured = fn (callback: U32 -> U32 ! {Foreign}) => packet.traced (callback, 3.5)
entry const sibling = ${seed}
`;
async function execute(
  bytes: Uint8Array<ArrayBuffer>,
  captured: number,
  increment: number,
) {
  for (const asynchronous of [false, true]) {
    const guest = await instantiateGuest(bytes, { asynchronous });
    try {
      const calls: number[] = [];
      let callback: ReturnType<typeof guest.capability>;
      if (asynchronous) {
        callback = guest.capabilityAsync({
          parameter: "U32",
          result: "U32",
          call: async (value) => {
            calls.push(value);
            await Promise.resolve();
            return value + 7;
          },
        });
      } else {
        callback = guest.capability({
          parameter: "U32",
          result: "U32",
          call: (value) => {
            calls.push(value);
            return value + 7;
          },
        });
      }
      const call = async (
        name: string,
        value: Parameters<typeof guest.call>[1],
      ) => {
        if (asynchronous) return await guest.callAsync(name, value);
        return guest.call(name, value);
      };
      assert.equal(await call("whole", null), 291);
      assert.equal(await call("fraction", null), 3.5);
      assert.equal(await call("shown", null), 42 + increment);
      assert.equal(await call("wrapped", null), 291);
      assert.equal(await call("host", callback), 298);
      assert.equal(await call("captured", callback), 3.5);
      assert.deepEqual(calls, [291, captured]);
    } finally {
      guest.dispose();
    }
  }
}
Deno.test("constant forall fields execute constructor captured dictionary and Foreign carrier environments in both tiers", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-rank-source-" });
  const entry = `${directory}/main.blot`;
  const source = producer() + consumer().slice(consumer().indexOf("\n") + 1);
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
        const result = await compiler.build({ sources: { [entry]: source } });
        assert.ok(result.success, JSON.stringify(result));
        await execute(result.bytes, 35, 1);
      } finally {
        await compiler.dispose();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
const simpleProducer = (captured = "35", increment = "1", valid = true) => {
  let chosen = "value";
  if (!valid) chosen = "42";
  let cost = `@u32.add ${captured} ${increment}`;
  for (let i = 0; i < 80; i++) cost = `@u32.add 1 (${cost})`;
  return `const choose: forall [a] => a -> a = fn value => ${chosen}
const packet = {choose, cost:${cost}}
`;
};
const simpleConsumer = (seed = "2") =>
  `import {packet} from "./producer"
entry const whole = fn () => packet.choose packet.cost
entry const fraction = fn () => packet.choose 3.5
entry const sibling = ${seed}
`;
async function executeSimple(
  bytes: Uint8Array<ArrayBuffer>,
  captured: number,
  increment: number,
) {
  for (const asynchronous of [false, true]) {
    const guest = await instantiateGuest(bytes, { asynchronous });
    try {
      if (asynchronous) {
        assert.equal(
          await guest.callAsync("whole", null),
          captured + increment + 80,
        );
        assert.equal(await guest.callAsync("fraction", null), 3.5);
      } else {
        assert.equal(guest.call("whole", null), captured + increment + 80);
        assert.equal(guest.call("fraction", null), 3.5);
      }
    } finally {
      guest.dispose();
    }
  }
}
Deno.test("constant forall fields preserve exact source archive bytes retained edits and failed edit recovery", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-rank-constant-" });
  const entry = `${directory}/main.blot`;
  const library = `${directory}/producer.blot`;
  const dependencies = `${directory}/producer.blotdep`;
  try {
    await Deno.writeTextFile(entry, simpleConsumer());
    await Deno.writeTextFile(library, simpleProducer());
    const packed = await new Deno.Command(executable, {
      args: ["dependencies", entry, dependencies, "--prelude", "none"],
      stdout: "piped",
      stderr: "piped",
    }).output();
    assert.ok(
      packed.success,
      new TextDecoder().decode(packed.stdout) +
        new TextDecoder().decode(packed.stderr),
    );
    for (const codegenTier of ["development", "optimized"] as const) {
      const options = {
        executable,
        entry,
        prelude: null,
        cacheDirectory: false,
        codegenTier,
      } as const;
      const retained = await createZigProjectCompiler(options);
      const archived = await createZigProjectCompiler({
        ...options,
        dependencies,
      });
      let checkpoint: Uint8Array<ArrayBuffer> | undefined;
      let finalBytes: Uint8Array<ArrayBuffer> | undefined;
      try {
        const first = await retained.build();
        const frozen = await archived.build();
        assert.ok(first.success, JSON.stringify(first));
        assert.ok(frozen.success, JSON.stringify(frozen));
        assert.deepEqual(first.bytes, frozen.bytes);
        await executeSimple(frozen.bytes, 35, 1);
        for (const compiler of [retained, archived]) {
          const actual = await compiler.build({
            sources: { [entry]: simpleConsumer("3") },
          });
          assert.ok(actual.success, JSON.stringify(actual));
          const traffic = actual.stats.constantReceipts as Record<
            string,
            number
          >;
          assert.ok(traffic.reused > 0, JSON.stringify(traffic));
          await executeSimple(actual.bytes, 35, 1);
        }
        const revisions = [
          ["4", "35", "1", true],
          ["4", "36", "1", true],
          ["4", "36", "2", true],
          ["missing", "36", "2", true],
          ["5", "36", "2", false],
          ["5", "36", "2", true],
          ["2", "35", "1", true],
          ["3", "35", "1", true],
        ] as const;
        for (const [seed, captured, increment, valid] of revisions) {
          const sources = {
            [entry]: simpleConsumer(seed),
            [library]: simpleProducer(captured, increment, valid),
          };
          const fresh = await createZigProjectCompiler(options);
          try {
            const expected = await fresh.build({ sources });
            const actual = await retained.build({ sources });
            assert.equal(actual.success, expected.success);
            if (!actual.success || !expected.success) {
              assert.ok(seed === "missing" || !valid);
              assert.ok(!actual.success && !expected.success);
              assert.deepEqual(actual.diagnostics, expected.diagnostics);
              assert.deepEqual(await retained.exportCheckpoint(), checkpoint);
              continue;
            }
            assert.deepEqual(actual.bytes, expected.bytes);
            assert.equal(
              actual.stats.nativeWorkSteps,
              expected.stats.nativeWorkSteps,
            );
            await executeSimple(
              actual.bytes,
              Number(captured),
              Number(increment),
            );
            checkpoint = await retained.exportCheckpoint();
            finalBytes = actual.bytes;
          } finally {
            await fresh.dispose();
          }
        }
      } finally {
        await retained.dispose();
        await archived.dispose();
      }
      assert.ok(checkpoint && finalBytes);
      const restarted = await createZigProjectCompiler({
        ...options,
        checkpoint,
      });
      try {
        const actual = await restarted.build({
          sources: {
            [entry]: simpleConsumer("3"),
            [library]: simpleProducer(),
          },
        });
        assert.ok(actual.success, JSON.stringify(actual));
        assert.deepEqual(actual.bytes, finalBytes);
        await executeSimple(actual.bytes, 35, 1);
      } finally {
        await restarted.dispose();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
