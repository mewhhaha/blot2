import { strict as assert } from "node:assert";
import { instantiateScalarLiveGuest } from "../experiments/scalar_live_guest.ts";

Deno.test("scalar live patches redirect unchanged and recursive callers while retaining exported identities", async () => {
  const compiler = Deno.args[0] ?? "zig-native/zig-out/bin/blotc";
  const fixture = new URL(
    "../scalar-patch-fixture.json",
    new URL(compiler, `file://${Deno.cwd()}/`),
  );
  const values = JSON.parse(await Deno.readTextFile(fixture)) as Record<
    string,
    string
  >;
  const bytes = (name: string) =>
    Uint8Array.from(atob(values[name]), (char) => char.charCodeAt(0));
  const guest = await instantiateScalarLiveGuest(bytes("initial"));
  const answer = guest.exports.answer;
  const initialIdentity = guest.identity;
  assert.equal(answer(4), 10);
  assert(Object.is(guest.exports.floating(1), -0));
  assert.throws(() => guest.exports.divide(0), WebAssembly.RuntimeError);
  const first = bytes("first");
  assert(first.length < bytes("initial").length);
  const applying = guest.apply(first);
  first.fill(0); // Queued edits own their encoded input.
  await applying;
  assert.equal(guest.exports.answer, answer);
  assert.equal(answer(4), 22);
  assert.notEqual(guest.identity, initialIdentity);
  await assert.rejects(guest.apply(bytes("first")), /Stale patch base/);
  assert.equal(answer(4), 22);
  const second = bytes("second");
  const initialized = new Uint8Array(second.length + 3);
  initialized.set(second);
  initialized.set([6, 1, 0], second.length); // Even an empty global section is forbidden.
  await assert.rejects(guest.apply(initialized), /state or initialization/);
  assert.equal(answer(4), 22);
  const corrupt = new Uint8Array(second);
  corrupt[0] = 1;
  await assert.rejects(guest.apply(corrupt), WebAssembly.CompileError);
  assert.equal(answer(4), 22);
  await Promise.all([guest.apply(second), guest.apply(bytes("revert"))]);
  assert.equal(answer(4), 10);
  assert.equal(guest.identity, initialIdentity);
  assert(Object.is(guest.exports.floating(1), -0));
  assert.throws(() => guest.exports.divide(0), WebAssembly.RuntimeError);
});
