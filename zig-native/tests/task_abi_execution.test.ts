import { strict as assert } from "node:assert";
import {
  GuestError,
  instantiateGuest,
  readGuestAbi,
} from "../../compiler/guest.ts";
import { compileAndRun } from "./compile_helpers.ts";

function uleb(value: number): Uint8Array {
  const bytes: number[] = [];
  do {
    let next = value & 127;
    value >>>= 7;
    if (value !== 0) next |= 128;
    bytes.push(next);
  } while (value !== 0);
  return new Uint8Array(bytes);
}
function concat(parts: readonly Uint8Array[]): Uint8Array<ArrayBuffer> {
  const result = new Uint8Array(
    parts.reduce((length, part) => length + part.length, 0),
  );
  let position = 0;
  for (const part of parts) {
    result.set(part, position);
    position += part.length;
  }
  return result;
}
function number(bytes: Uint8Array, cursor: { position: number }): number {
  let result = 0;
  let shift = 0;
  for (;;) {
    const byte = bytes[cursor.position++];
    result |= (byte & 127) << shift;
    if ((byte & 128) === 0) return result >>> 0;
    shift += 7;
  }
}
function sections(
  bytes: Uint8Array,
  rewrite: (id: number, bytes: Uint8Array) => readonly Uint8Array[],
): Uint8Array<ArrayBuffer> {
  const output = [bytes.subarray(0, 8)];
  const cursor = { position: 8 };
  while (cursor.position < bytes.length) {
    const id = bytes[cursor.position++];
    const size = number(bytes, cursor);
    const start = cursor.position;
    cursor.position += size;
    for (const payload of rewrite(id, bytes.subarray(start, start + size))) {
      output.push(new Uint8Array([id]), uleb(payload.length), payload);
    }
  }
  return concat(output);
}
function feature(
  bytes: Uint8Array,
  rewrite: (payload: Uint8Array) => readonly Uint8Array[],
): Uint8Array<ArrayBuffer> {
  return sections(bytes, (id, payload) => {
    if (id !== 0) return [payload];
    const cursor = { position: 0 };
    const length = number(payload, cursor);
    const name = new TextDecoder().decode(
      payload.subarray(cursor.position, cursor.position + length),
    );
    if (name !== "blot:tasks") return [payload];
    cursor.position += length;
    const prefix = payload.subarray(0, cursor.position);
    return rewrite(payload.subarray(cursor.position)).map((replacement) =>
      concat([prefix, replacement])
    );
  });
}
function wrongStartSignature(bytes: Uint8Array): Uint8Array<ArrayBuffer> {
  return sections(bytes, (id, payload) => {
    if (id !== 7) return [payload];
    const cursor = { position: 0 };
    const count = number(payload, cursor);
    const exports: {
      name: string;
      prefix: Uint8Array;
      kind: number;
      index: number;
    }[] = [];
    for (let index = 0; index < count; index++) {
      const start = cursor.position;
      const length = number(payload, cursor);
      const name = new TextDecoder().decode(
        payload.subarray(cursor.position, cursor.position + length),
      );
      cursor.position += length;
      const prefix = payload.subarray(start, cursor.position);
      const kind = payload[cursor.position++];
      exports.push({ name, prefix, kind, index: number(payload, cursor) });
    }
    const retain = exports.find((entry) => entry.name === "blot:task_retain")!;
    const parts = [uleb(count)];
    for (const entry of exports) {
      if (entry.name === "blot:task_start/0") entry.index = retain.index;
      parts.push(entry.prefix, new Uint8Array([entry.kind]), uleb(entry.index));
    }
    return [concat(parts)];
  });
}
Deno.test("task ABI rejects missing duplicate stale versions counts and forged adapter contracts", async () => {
  await compileAndRun(
    `entry const answer = func (value: U32) => return @task.scope (func group => return @task.join (@task.spawn group (func () => return value)))`,
    async (guest, bytes) => {
      assert.equal(guest.call("answer", 42), 42);
      const abi = readGuestAbi(new WebAssembly.Module(bytes));
      assert.equal(abi.taskDescriptorCount, 1);
      for (
        const changed of [
          feature(bytes, () => []),
          feature(bytes, (payload) => [payload, payload]),
          feature(bytes, (payload) => {
            const stale = payload.slice();
            stale[0] = 1;
            return [stale];
          }),
          feature(bytes, () => [new Uint8Array([2, 0])]),
          feature(bytes, () => [concat([new Uint8Array([2]), uleb(4097)])]),
          feature(bytes, () => [new Uint8Array([2, 1, 1])]),
        ]
      ) {
        assert.throws(
          () => readGuestAbi(new WebAssembly.Module(changed)),
          (cause) =>
            cause instanceof GuestError && cause.code === "invalid_abi",
        );
      }
      await assert.rejects(
        instantiateGuest(wrongStartSignature(bytes)),
        (cause) => cause instanceof GuestError && cause.code === "invalid_abi",
      );
    },
    { prelude: "none" },
  );
});
