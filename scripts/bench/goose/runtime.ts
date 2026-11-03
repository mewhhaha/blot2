// One Node/V8 process per sample; preparation and warmup remain in the guest.
import { readFileSync } from "node:fs";
import { isAbsolute } from "node:path";
import { pathToFileURL } from "node:url";
import { strict as assert } from "node:assert";
import { instantiateGuest } from "../../../compiler/guest.ts";

type Input = Readonly<{
  parameters: readonly number[];
  iterations: number;
  warmups: number;
  expected: number;
  revision: number;
}>;

function u32(value: unknown, name: string): asserts value is number {
  assert(
    typeof value === "number" && Number.isInteger(value) && value >= 0 &&
      value <= 0xFFFFFFFF,
    `${name} must be a U32`,
  );
}

function parseInput(text: string): Input {
  const input = JSON.parse(text);
  assert(input !== null && typeof input === "object", "invalid runtime input");
  assert(
    Array.isArray(input.parameters) && input.parameters.length >= 1 &&
      input.parameters.length <= 2,
  );
  for (const value of input.parameters) {
    u32(value, "parameter");
    assert(value > 0);
  }
  u32(input.iterations, "iterations");
  u32(input.warmups, "warmups");
  u32(input.expected, "expected");
  u32(input.revision, "revision");
  assert(input.parameters[0] > 0 && input.iterations > 0);
  Object.freeze(input.parameters);
  return Object.freeze(input);
}

function nanoseconds(value: bigint): number {
  assert(
    value > 0n && value <= BigInt(Number.MAX_SAFE_INTEGER),
    "invalid clock",
  );
  return Number(value);
}

async function blot(bytes: Uint8Array<ArrayBuffer>, input: Input) {
  const start = process.hrtime.bigint();
  const guest = await instantiateGuest(bytes);
  const compileInstantiate = process.hrtime.bigint() - start;
  try {
    assert.equal(guest.abi.version, 8);
    const calls: number[] = [];
    let started: bigint | undefined;
    let finished: bigint | undefined;
    const host = guest.capability({
      parameter: "Array U32",
      result: "Array U32",
      call: (packet) => {
        assert.equal(packet.length, 1);
        const command = packet[0];
        assert.equal(command, calls.length, "expected input/start/stop order");
        calls.push(command);
        if (command === 0) {
          return new Uint32Array([
            ...input.parameters,
            input.iterations,
            input.warmups,
          ]);
        }
        if (command === 1) {
          // Includes the start reply and stop request packet ABI halves.
          // Goose instead crosses two scalar bench_clock imports.
          started = process.hrtime.bigint();
          return new Uint32Array([0]);
        }
        assert.equal(command, 2);
        finished = process.hrtime.bigint();
        return new Uint32Array([0]);
      },
    });
    const entryStart = process.hrtime.bigint();
    const checksum = guest.call("benchmark", host);
    const entryNs = process.hrtime.bigint() - entryStart;
    assert.deepEqual(calls, [0, 1, 2]);
    assert(started !== undefined && finished !== undefined, "missing clock");
    assert.equal(checksum, input.expected, "checksum mismatch");
    const revision = guest.call("revision", null);
    assert.equal(revision, input.revision, "revision mismatch");
    return {
      checksum,
      elapsed_ns: nanoseconds(finished - started),
      compile_instantiate_ns: nanoseconds(compileInstantiate),
      entry_ns: nanoseconds(entryNs),
      revision,
      abi: guest.abi.version,
      memory_pages: guest.memoryBytes() / 65536,
    };
  } finally {
    guest.dispose();
  }
}

async function goose(
  bytes: Uint8Array<ArrayBuffer>,
  input: Input,
  runner: string,
) {
  assert(isAbsolute(runner), "--goose-runner requires an absolute path");
  const { runModule } = await import(pathToFileURL(runner).href);
  const stdin =
    [...input.parameters, input.iterations, input.warmups].join(" ") +
    "\n";
  const result = await runModule(bytes, stdin);
  assert.equal(result.stderr, "", "Goose runtime error");
  assert.equal(result.exitCode, input.revision, "revision exit mismatch");
  const lines = result.stdout.toString("utf8").split("\n");
  assert.equal(lines.pop(), "", "missing trailing newline");
  assert.equal(lines.length, 2, "expected checksum and nanoseconds");
  assert(lines.every((line: string) => /^[0-9]+$/.test(line)));
  const checksum = Number(lines[0]);
  assert.equal(checksum, input.expected, "checksum mismatch");
  return {
    checksum,
    elapsed_ns: nanoseconds(BigInt(lines[1])),
    compile_instantiate_ns: nanoseconds(
      BigInt(result.timing.compile_instantiate_ns),
    ),
    entry_ns: nanoseconds(BigInt(result.timing.start_function_ns)),
    revision: input.revision,
    guest_exit_code: result.exitCode,
    abi: "goose-scalar",
  };
}

const [backend, artifact, json, ...options] = process.argv.slice(2);
assert(backend === "blot" || backend === "goose", "backend must be blot/goose");
assert(artifact && json, "usage: runtime.ts backend artifact input-json");
const input = parseInput(json);
const bytes = readFileSync(artifact);
let record;
if (backend === "blot") {
  assert.equal(options.length, 0, "unexpected Blot runtime options");
  record = await blot(bytes, input);
} else {
  assert(options.length === 2 && options[0] === "--goose-runner");
  record = await goose(bytes, input, options[1]);
}
process.stdout.write(
  JSON.stringify({
    ...record,
    engine: "V8",
    node: process.version,
    v8: process.versions.v8,
  }) + "\n",
);
