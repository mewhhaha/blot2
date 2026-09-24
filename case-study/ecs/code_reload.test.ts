import { deepStrictEqual as equal, ok } from "node:assert/strict";
import { GuestRuntime } from "../../compiler/guest_runtime.ts";
import type { TypeId } from "../../compiler/host.ts";
import { createBackgroundCompiler } from "./background_compiler.ts";
import {
  createCodeReload,
  type LiveWorld,
  type ReloadEvent,
} from "./code_reload.ts";

const clock: TypeId = {
  $: "TypeId",
  module_name: "main",
  declaration: "Clock",
};
const source = (amount: number, initial = 10) =>
  `#[resource]
data Clock = Clock U32
const tick = fn () => do:
  use wrapped <- @ecs.get Clock
  let Clock value = wrapped
  use @ecs.set (Clock (value + ${amount}))
  return ()
const start = fn () => do:
  use @ecs.set (Clock ${initial})
  return ()
const event = fn () => ()
const update = fn () => do:
  use @ecs.run tick
  return ()
const render = fn () => ()
`;

Deno.test("reload transfers the latest live state; errors and bad first frames publish nothing", async () => {
  const compiler = createBackgroundCompiler();
  const events: ReloadEvent[] = [];
  let reload: ReturnType<typeof createCodeReload> | undefined;
  try {
    const { artifact } = await compiler.compile(source(1));
    const runtime = await GuestRuntime.create(artifact);
    let current: LiveWorld = {
      artifact,
      runtime,
      world: runtime.start().world,
    };
    reload = createCodeReload({
      current: () => current,
      compile: compiler.compile,
      report: (event) => events.push(event),
    });
    reload.request(source(10));
    for (let frame = 0; frame < 5; frame++) {
      current = {
        ...current,
        world: current.runtime.update(current.world, {}).world,
      };
    }
    await reload.idle();
    const old = current;
    const published = reload.publish(
      current,
      (candidate) => ({
        ...candidate,
        world: candidate.runtime.update(candidate.world, {}).world,
      }),
    );
    ok(published);
    current = published;
    equal(current.runtime.readResource(current.world, clock), 25);
    equal(old.runtime.readResource(old.world, clock), 15);
    equal(events.at(-1)?.kind, "published");

    for (
      const bad of [
        "const broken = fn () => missing\n",
        source(10).replaceAll("U32", "F32").replace(
          "value + 10",
          "F32.add value 10.0",
        ).replace("Clock 10)", "Clock 10.0)"),
        source(10).replaceAll("Clock", "DifferentClock"),
      ]
    ) {
      reload.request(bad);
      await reload.idle();
      equal(reload.publish(current, (candidate) => candidate), undefined);
      equal(events.at(-1)?.kind, "failed");
      equal(current.runtime.readResource(current.world, clock), 25);
    }
    reload.request(source(100));
    await reload.idle();
    equal(
      reload.publish(current, (candidate) => {
        candidate.runtime.update(candidate.world, {});
        throw new Error("invalid first render");
      }),
      undefined,
    );
    equal(current.runtime.readResource(current.world, clock), 25);
    ok(events.at(-1)?.kind === "failed");
    reload.request(source(2));
    await reload.idle();
    const recovered = reload.publish(current, (candidate) => candidate);
    ok(recovered);
    current = recovered;
    equal(
      current.runtime.readResource(
        current.runtime.update(current.world, {}).world,
        clock,
      ),
      27,
    );
  } finally {
    await Promise.all([reload?.close(), compiler.close()]);
  }
});

Deno.test("rapid edits coalesce and stale candidates cannot publish", async () => {
  const compiler = createBackgroundCompiler();
  let reload: ReturnType<typeof createCodeReload> | undefined;
  try {
    const { artifact } = await compiler.compile(source(1, 0));
    const runtime = await GuestRuntime.create(artifact);
    const current: LiveWorld = {
      artifact,
      runtime,
      world: runtime.start().world,
    };
    const gate = Promise.withResolvers<void>();
    const requests: string[] = [];
    reload = createCodeReload({
      current: () => current,
      compile: async (text, filename) => {
        requests.push(text);
        if (requests.length === 1) await gate.promise;
        return await compiler.compile(text, filename);
      },
      report() {},
    });
    reload.request(source(2));
    reload.request(source(3));
    reload.request(source(4));
    gate.resolve();
    await reload.idle();
    equal(requests, [source(2), source(4)]);
    // A new edit invalidates even an already-prepared candidate immediately.
    reload.request(source(5));
    equal(reload.publish(current, (candidate) => candidate), undefined);
    await reload.idle();
    const published = reload.publish(
      current,
      (candidate) => ({
        ...candidate,
        world: candidate.runtime.update(candidate.world, {}).world,
      }),
    );
    ok(published);
    equal(published.runtime.readResource(published.world, clock), 5);
  } finally {
    await Promise.all([reload?.close(), compiler.close()]);
  }
});
