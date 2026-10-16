import { strict as assert } from "node:assert";
import { GuestError, instantiateGuest, readGuestAbi } from "./guest.ts";

function name(value: string): number[] {
  const bytes = new TextEncoder().encode(value);
  return [bytes.length, ...bytes];
}
function section(id: number, bytes: number[]): number[] {
  return [id, bytes.length, ...bytes];
}
function usage(bytes: number[]): number[] {
  return section(0, [...name("blot:multiplicity"), ...bytes]);
}
function module(...extra: number[][]): WebAssembly.Module {
  return new WebAssembly.Module(
    new Uint8Array([
      0,
      97,
      115,
      109,
      1,
      0,
      0,
      0,
      ...section(1, [1, 96, 1, 127, 1, 127]),
      ...section(3, [1, 0]),
      ...section(7, [1, ...name("f"), 0, 0]),
      ...section(10, [1, 4, 0, 32, 0, 11]),
      ...section(0, [...name("blot:abi"), 2, 1, ...name("f"), 1, 1, 0]),
      ...extra.flat(),
    ]),
  );
}
const invalid = (error: unknown) =>
  error instanceof GuestError && error.code === "invalid_abi";
Deno.test("guest multiplicity metadata is canonical and binds only exact declared functions", async () => {
  assert.equal(readGuestAbi(module()).functions[0].multiplicity, undefined);
  const once = usage([1, 1, ...name("f"), 1]);
  assert.equal(readGuestAbi(module(once)).functions[0].multiplicity, "once");
  for (
    const extra of [
      [usage([])],
      [usage([2, 1, ...name("f"), 1])],
      [usage([129, 0, 1, ...name("f"), 1])],
      [usage([1, 0])],
      [usage([1, 2, ...name("f"), 1, ...name("f"), 1])],
      [usage([1, 1, ...name("unknown"), 1])],
      [usage([1, 1, ...name("f"), 0])],
      [usage([1, 1, ...name("f"), 2])],
      [usage([1, 1, ...name("f"), 1, 0])],
      [once, once],
    ]
  ) {
    const forged = module(...extra);
    assert.throws(() => readGuestAbi(forged), invalid);
    await assert.rejects(() => instantiateGuest(forged), invalid);
  }
  const guest = await instantiateGuest(module(once));
  try {
    assert.throws(
      () => guest.call("f", -1),
      (error: unknown) =>
        error instanceof GuestError && error.code === "invalid_argument",
    );
    assert.equal(guest.call("f", 42), 42);
    assert.throws(
      () => guest.call("f", 9),
      (error: unknown) =>
        error instanceof GuestError && error.code === "once_reused",
    );
  } finally {
    guest.dispose();
  }
});
