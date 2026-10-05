import assert from "node:assert/strict";
import { GuestError, instantiateGuest } from "../../compiler/guest.ts";
import {
  cases,
  foreignArithmeticSource,
  foreignSource,
} from "./adjacent_call_cases.ts";

const compiler = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
async function compile(
  source: string,
  run: (bytes: Uint8Array<ArrayBuffer>) => Promise<void>,
) {
  const dir = await Deno.makeTempDir({
    dir: new URL("../../build", import.meta.url).pathname,
    prefix: "adjacent-call-",
  });
  try {
    const input = `${dir}/source.blot`, output = `${dir}/source.wasm`;
    await Deno.writeTextFile(input, source);
    const result = await new Deno.Command(compiler, {
      args: [
        "build",
        input,
        output,
        "--prelude",
        new URL("../../std/prelude.blot", import.meta.url).pathname,
      ],
      stdout: "piped",
      stderr: "piped",
    }).output();
    const records = new TextDecoder().decode(result.stdout).trim().split("\n")
      .filter(Boolean).map((line) => JSON.parse(line));
    assert.equal(
      records.find((r) => r.kind === "compilation").memory.live_bytes,
      0,
    );
    assert.equal(result.success, true, JSON.stringify(records));
    const bytes = await Deno.readFile(output);
    assert(WebAssembly.validate(bytes));
    await run(bytes);
  } finally {
    await Deno.remove(dir, { recursive: true });
  }
}

Deno.test("adjacent parenthesized calls preserve result projections, indexes and spaced argument controls", async () => {
  for (const item of cases) {
    if (!item.valid) continue;
    await compile(item.source, async (bytes) => {
      const guest = await instantiateGuest(bytes);
      try {
        if ("reads" in item) {
          for (const [name, expected] of item.reads) {
            assert.deepEqual(guest.read(name), expected);
          }
        }
        if ("calls" in item) {
          for (const [name, input, expected] of item.calls) {
            assert.deepEqual(guest.call(name, input), expected);
          }
        }
      } finally {
        guest.dispose();
      }
    });
  }
});

Deno.test("adjacent parenthesized calls still reject tuple, extra, Unit and scalar arguments", async () => {
  for (const item of cases) {
    if (item.valid) continue;
    const dir = await Deno.makeTempDir({
      dir: new URL("../../build", import.meta.url).pathname,
      prefix: "adjacent-call-negative-",
    });
    try {
      await Deno.writeTextFile(`${dir}/source.blot`, item.source);
      const result = await new Deno.Command(compiler, {
        args: [
          "build",
          `${dir}/source.blot`,
          `${dir}/source.wasm`,
          "--prelude",
          new URL("../../std/prelude.blot", import.meta.url).pathname,
        ],
        stdout: "piped",
        stderr: "piped",
      }).output();
      const records = new TextDecoder().decode(result.stdout).trim().split("\n")
        .filter(Boolean).map((line) => JSON.parse(line));
      assert.equal(result.success, false);
      assert.equal(
        records.find((r) => r.kind === "diagnostic").code,
        item.name === "bad_spaced_member" ? "missing_member" : "type_mismatch",
      );
      assert.equal(
        records.find((r) => r.kind === "compilation").memory.live_bytes,
        0,
      );
      await assert.rejects(
        () => Deno.stat(`${dir}/source.wasm`),
        Deno.errors.NotFound,
      );
    } finally {
      await Deno.remove(dir, { recursive: true });
    }
  }
});

const foreignCases = [
  { source: foreignArithmeticSource, trace: [5, 3, 1, 2], constant: 38 },
  { source: foreignSource, trace: [1, 2], constant: 40 },
];
Deno.test("adjacent call receivers and arguments invoke Foreign callbacks in source order and recover from failure", async () => {
  for (const item of foreignCases) {
    await compile(item.source, async (bytes) => {
      const guest = await instantiateGuest(bytes);
      try {
        for (const mode of ["identity", "constant"] as const) {
          const trace: number[] = [];
          const cap = guest.capability({
            parameter: "U32",
            result: "U32",
            call: (value) => {
              trace.push(value);
              return mode === "identity" ? value : 1;
            },
          });
          assert.equal(
            guest.call("run", cap),
            mode === "identity" ? 42 : item.constant,
          );
          assert.deepEqual(trace, item.trace);
        }
        const cause = new Error("receiver failed");
        const trace: number[] = [];
        const failing = guest.capability({
          parameter: "U32",
          result: "U32",
          call: (value) => {
            trace.push(value);
            if (value === 1) throw cause;
            return value;
          },
        });
        assert.throws(
          () => guest.call("run", failing),
          (e: unknown) =>
            e instanceof GuestError && e.code === "host_exception" &&
            e.cause === cause,
        );
        assert.deepEqual(trace, item.trace.slice(0, item.trace.indexOf(1) + 1));
        const good = guest.capability({
          parameter: "U32",
          result: "U32",
          call: (value) => value,
        });
        assert.equal(guest.call("run", good), 42);
      } finally {
        guest.dispose();
      }
    });
  }
});

const jspi = WebAssembly as unknown as {
  Suspending?: unknown;
  promising?: unknown;
};
Deno.test({
  name:
    "adjacent call receivers and arguments retain Foreign order through JSPI suspension and rejection",
  ignore: typeof jspi.Suspending !== "function" ||
    typeof jspi.promising !== "function",
  fn: async () => {
    for (const item of foreignCases) {
      await compile(item.source, async (bytes) => {
        const guest = await instantiateGuest(bytes, { asynchronous: true });
        try {
          const trace: number[] = [];
          const cap = guest.capabilityAsync({
            parameter: "U32",
            result: "U32",
            call: async (value) => {
              trace.push(value);
              await Promise.resolve();
              return value;
            },
          });
          assert.equal(await guest.callAsync("run", cap), 42);
          assert.deepEqual(trace, item.trace);
          const cause = new Error("receiver rejected");
          const failed: number[] = [];
          const failing = guest.capabilityAsync({
            parameter: "U32",
            result: "U32",
            call: (value) => {
              failed.push(value);
              return value === 1
                ? Promise.reject(cause)
                : Promise.resolve(value);
            },
          });
          await assert.rejects(
            () => guest.callAsync("run", failing),
            (e: unknown) =>
              e instanceof GuestError && e.code === "host_exception" &&
              e.cause === cause,
          );
          assert.deepEqual(
            failed,
            item.trace.slice(0, item.trace.indexOf(1) + 1),
          );
          const good = guest.capabilityAsync({
            parameter: "U32",
            result: "U32",
            call: (value) => Promise.resolve(value),
          });
          assert.equal(await guest.callAsync("run", good), 42);
        } finally {
          guest.dispose();
        }
      });
    }
  },
});
