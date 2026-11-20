import { ProcessHost } from "../../host/processes.ts";
import { compileAndRun, equal } from "./compile_helpers.ts";

const source = await Deno.readTextFile(
  new URL("../../benchmarks/language/process_replay.blot", import.meta.url),
);

Deno.test("one-thread process admissions, refusals and deliveries replay at their application tick", async () => {
  await compileAndRun(source, async (guest, bytes) => {
    const host = new ProcessHost(
      await WebAssembly.compile(bytes),
      [
        { name: "planner", initWork: 1, stepWork: 1 },
      ],
      2,
      1,
    );
    const admissions: { packet: Uint32Array; outcome: number }[] = [];
    const start = guest.capability({
      parameter: "Array U32",
      result: "U32",
      call: (packet) => {
        const outcome = host.admit(packet);
        admissions.push({ packet, outcome });
        return outcome;
      },
    });
    const tick: { values: number[]; world: number }[] = [];
    let world = 1000;
    function apply(...values: number[]) {
      world = guest.call(
        "apply_tick",
        Uint32Array.of(world, ...values),
      ) as number;
      tick.push({ values, world });
    }
    try {
      equal(guest.call("local", 4), 4);
      equal(guest.call("local", 5), 0);
      const [a, b, refused] = guest.call("live", start) as Uint32Array;
      equal(a !== 0 && b !== 0 && a !== b, true);
      equal(refused, 0);
      equal(host.send(a, 99), "starting");
      apply(...[a, b, refused], 0);
      equal(await host.advance(2), 2);
      equal(host.status(a), "ready");
      equal(host.status(b), "ready");
      const first = host.send(a, 1);
      const second = host.send(b, 7);
      equal(host.send(a, 99), "full");
      equal(await host.advance(2), 2);
      equal(host.send(a, 99), "full"); // A settled reply still occupies the slot.
      const ack1 = host.poll(a);
      const ack2 = host.poll(b);
      if (ack1?.status !== "done" || ack2?.status !== "done") {
        throw Error("Expected both accepted replies");
      }
      equal(ack1.ticket, first);
      equal(ack2.ticket, second);
      equal(ack1.value, 11);
      equal(ack2.value, 107);
      apply(0, ack2.value, ack1.value); // Preserve application order, not worker order.
      equal(await host.advance(2), 0);
      const woke = host.send(a, 2);
      equal(await host.advance(1), 1);
      const ack3 = host.poll(a);
      if (ack3?.status !== "done") {
        throw Error("A command must wake an idle process");
      }
      equal(ack3.ticket, woke);
      equal(ack3.value, 13);
      apply(ack3.value);
    } finally {
      host.restore();
    }

    let accepted = 0;
    const replay = guest.capability({
      parameter: "Array U32",
      result: "U32",
      call: (packet) => {
        const recorded = admissions[accepted++];
        equal(String(packet), String(recorded.packet));
        return recorded.outcome;
      },
    });
    equal(
      String(guest.call("live", replay)),
      tick[0].values.slice(0, 3).join(","),
    );
    equal(accepted, admissions.length);
    let replayWorld = 1000;
    for (const frame of tick) {
      replayWorld = guest.call(
        "apply_tick",
        Uint32Array.of(replayWorld, ...frame.values),
      ) as number;
      equal(replayWorld, frame.world);
    }
  });
});
