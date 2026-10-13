import { strict as assert } from "node:assert";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const fixture = new URL(
  "../shared-rc-fixture.wasm",
  new URL(executable, `file://${Deno.cwd()}/`),
);

Deno.test("scope activation journal revokes retained identity before teardown on success and failure", async () => {
  for (const outcome of [0, 1]) {
    const instance = new WebAssembly.Instance(
      new WebAssembly.Module(await Deno.readFile(fixture)),
    );
    const exports = instance.exports;
    const call = (name: string, ...args: number[]) =>
      Number((exports[name] as CallableFunction)(...args)) >>> 0;
    const count = (name: string) =>
      Number((exports[`blot:rc_${name}`] as WebAssembly.Global).value);
    const memory = exports["blot:memory"] as WebAssembly.Memory;
    const word = (address: number) =>
      new DataView(memory.buffer).getUint32(address, true);
    call("root_enter");
    const owner = call("allocate_typed", 4, 0);
    call("store_word", owner, owner, 1);
    call("root_authority", owner);
    // A separately retained alias cannot prolong authority or let its address
    // be recycled while it still names the old scope's identity.
    call("retain", owner);
    call("release_lease", owner);
    assert.equal(word(owner), 1);
    const second = call("allocate_typed", 4, 0);
    assert.notEqual(second, owner);
    call("release_lease", second);
    call("root_leave", outcome);
    assert.equal(word(owner), 0);
    assert.equal(Number((exports.roots as WebAssembly.Global).value), 0);
    assert.equal(count("leases"), 0);
    const destroyed = count("destroyed");
    call("root_leave", 2);
    assert.equal(word(owner), 0);
    call("release", owner);
    assert.equal(count("destroyed"), destroyed + 1);
  }
});
