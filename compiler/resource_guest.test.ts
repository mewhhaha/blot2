import { strict as assert } from "node:assert";
import { GuestError, instantiateGuest, readGuestAbi } from "./guest.ts";

function u32(value: number): number[] {
  const bytes: number[] = [];
  do {
    let byte = value & 127;
    value >>>= 7;
    if (value !== 0) byte |= 128;
    bytes.push(byte);
  } while (value !== 0);
  return bytes;
}
function name(value: string): number[] {
  const bytes = [...new TextEncoder().encode(value)];
  return [...u32(bytes.length), ...bytes];
}
function section(id: number, bytes: number[]): number[] {
  return [id, ...u32(bytes.length), ...bytes];
}
function fixture(change = "valid"): WebAssembly.Module {
  const imports = ["reserve", "register", "release"];
  if (change === "missing_import") imports.splice(1, 1);
  const hooks = ["blot:ownership_enter", "blot:ownership_leave"];
  if (change === "missing_hook") hooks.pop();
  const globals = ["roots", "leases", "retains", "releases", "destroyed"];
  let reserveType = 0;
  let adapterType = 4;
  if (change === "import_signature") reserveType = 5;
  if (change === "adapter_signature") adapterType = 3;
  let count = 1;
  if (change === "empty") count = 0;
  if (change === "excess") count = 4097;
  const types = [
    6,
    96,
    0,
    1,
    127,
    96,
    5,
    127,
    127,
    127,
    127,
    127,
    0,
    96,
    1,
    127,
    0,
    96,
    0,
    0,
    96,
    3,
    127,
    127,
    127,
    0,
    96,
    1,
    127,
    1,
    127,
  ];
  const imported = imports.flatMap((value) => {
    let type = 2;
    if (value === "reserve") type = reserveType;
    if (value === "register") type = 1;
    return [...name("blot:resource/1"), ...name(value), 0, type];
  });
  const exported = [
    ...hooks.flatMap((
      value,
      index,
    ) => [...name(value), 0, imports.length + index]),
    ...globals.flatMap((
      value,
      index,
    ) => [...name(`blot:rc_${value}`), 3, index]),
    ...["cleanup", "drop"].flatMap((
      value,
    ) => [...name(`blot:resource_${value}/0`), 0, imports.length + 2]),
  ];
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
      ...section(1, types),
      ...section(2, [imports.length, ...imported]),
      ...section(3, [3, 3, 2, adapterType]),
      ...section(6, [5, ...globals.flatMap(() => [127, 1, 65, 0, 11])]),
      ...section(7, [hooks.length + globals.length + 2, ...exported]),
      ...section(10, [3, 2, 0, 11, 2, 0, 11, 2, 0, 11]),
      ...section(0, [...name("blot:abi"), 4, ...u32(count), 0, 0]),
      ...section(0, [...name("blot:ownership"), 2, 2, 0]),
    ]),
  );
}
function invalid(error: unknown): boolean {
  return error instanceof GuestError && error.code === "invalid_abi";
}
Deno.test("resource ABI verifies journal imports and adapter signatures before invocation", async () => {
  const module = fixture();
  assert.equal(readGuestAbi(module).resourceAdapterCount, 1);
  const guest = await instantiateGuest(module);
  guest.dispose();
  for (
    const change of [
      "import_signature",
      "adapter_signature",
      "missing_import",
      "missing_hook",
      "empty",
      "excess",
    ]
  ) {
    await assert.rejects(() => instantiateGuest(fixture(change)), invalid);
  }
});

function ownerFixture(change: string): WebAssembly.Module {
  const i32 = (value: number): number[] => {
    const bytes = u32(value);
    if ((bytes[bytes.length - 1] & 64) !== 0) {
      bytes[bytes.length - 1] |= 128;
      bytes.push(0);
    }
    return [65, ...bytes];
  };
  const store = (
    address: number,
    value: number,
  ): number[] => [...i32(address), ...i32(value), 54, 2, 0];
  const type = (parameters: number, result: boolean): number[] => {
    const bytes = [96, parameters, ...Array(parameters).fill(127), 0];
    if (result) bytes.splice(bytes.length - 1, 1, 1, 127);
    return bytes;
  };
  const signatures = [
    type(0, true),
    type(5, false),
    type(1, false),
    type(0, false),
    type(3, false),
    type(6, false),
    type(1, true),
  ];
  const imports = [
    ["blot:resource/1", "reserve", 0],
    ["blot:resource/1", "register", 1],
    ["blot:resource/1", "release", 2],
    ["blot:resource/2", "register_owned", 5],
    ["blot:resource/2", "retire", 2],
    ["blot:resource/2", "drain", 3],
  ] as const;
  const counters = ["roots", "leases", "retains", "releases", "destroyed"];
  let address = 64;
  let requested = 8;
  let flags = 4;
  let strong = 1;
  let token = 0;
  let layout = 0;
  let adapter = 0;
  if (change === "alignment") address = 65;
  if (change === "header_bounds") address = 28;
  if (change === "payload_bounds") address = 65532;
  if (change === "uncounted") flags = 0;
  if (change === "dead") flags = 20;
  if (change === "shaped") flags = 1028;
  if (change === "registered") flags = 2052;
  if (change === "size") requested = 4;
  if (change === "strong") strong = 0;
  if (change === "token") token = 7;
  if (change === "scalar_shape") layout = 1;
  if (change === "reference_shape") adapter = 2;
  const run = [
    1,
    1,
    127,
    ...store(36, requested),
    ...store(40, flags),
    ...store(48, strong),
    ...store(52, layout),
    ...store(64, 9),
    ...store(68, token),
    16,
    0,
    33,
    1,
    32,
    1,
    ...i32(adapter),
    ...i32(9),
    ...i32(0),
    ...i32(0),
    ...i32(address),
    16,
    3,
  ];
  if (change === "weak_token") run.push(...store(68, 7));
  if (change === "weak_dead") run.push(...store(40, 2068));
  if (change === "weak_size") run.push(...store(36, 4));
  // A second publication must fail without taking/replacing the first record.
  if (change === "duplicate") {
    run.push(
      32,
      1,
      ...i32(0),
      ...i32(9),
      ...i32(0),
      ...i32(0),
      ...i32(64),
      16,
      3,
    );
  }
  run.push(...i32(9), 11);
  const bodies = [
    [0, 11],
    [0, 11],
    [0, 35, 4, ...i32(1), 106, 36, 4, 11],
    [0, 35, 3, ...i32(1), 106, 36, 3, 11],
    [0, ...i32(64), 11],
    [0, 11],
    run,
  ];
  const exports = [
    [...name("blot:ownership_enter"), 0, 6],
    [...name("blot:ownership_leave"), 0, 7],
    [...name("blot:allocate"), 0, 10],
    [...name("blot:reset"), 0, 11],
    [...name("run"), 0, 12],
    [...name("blot:memory"), 2, 0],
    ...counters.map((value, index) => [...name(`blot:rc_${value}`), 3, index]),
    ...[0, 1, 2].flatMap((index) => [
      [...name(`blot:resource_cleanup/${index}`), 0, 8],
      [...name(`blot:resource_drop/${index}`), 0, 9],
    ]),
    [...name("attempts"), 3, 4],
    [...name("drops"), 3, 3],
  ];
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
      ...section(1, [signatures.length, ...signatures.flat()]),
      ...section(2, [
        imports.length,
        ...imports.flatMap((
          [module, value, id],
        ) => [...name(module), ...name(value), 0, id]),
      ]),
      ...section(3, [bodies.length, 3, 2, 4, 4, 6, 3, 6]),
      ...section(5, [1, 0, 1]),
      ...section(6, [5, ...counters.flatMap(() => [127, 1, 65, 0, 11])]),
      ...section(7, [exports.length, ...exports.flat()]),
      ...section(10, [
        bodies.length,
        ...bodies.flatMap((body) => [
          ...u32(body.length),
          ...body,
        ]),
      ]),
      ...section(0, [
        ...name("blot:abi"),
        5,
        3,
        1,
        ...name("run"),
        0,
        1,
        2,
        ...name("attempts"),
        1,
        ...name("drops"),
        1,
      ]),
      ...section(0, [...name("blot:ownership"), 2, 2, 0]),
    ]),
  );
}

Deno.test("resource transfer validates live box identity before journal mutation and commits exactly once", async () => {
  for (
    const change of [
      "valid",
      "alignment",
      "header_bounds",
      "payload_bounds",
      "uncounted",
      "dead",
      "shaped",
      "registered",
      "size",
      "strong",
      "token",
      "scalar_shape",
      "reference_shape",
      "weak_token",
      "weak_dead",
      "weak_size",
      "duplicate",
    ]
  ) {
    const guest = await instantiateGuest(ownerFixture(change));
    try {
      if (change === "valid") {
        assert.equal(guest.call("run", null), 9);
        assert.equal(guest.read("attempts"), 1);
        assert.equal(guest.read("drops"), 1);
      } else {
        assert.throws(() => guest.call("run", null), invalid, change);
        let attempts = 0;
        let drops = 0;
        if (change.startsWith("weak_")) drops = 1;
        if (change === "duplicate") {
          attempts = 1;
          drops = 1;
        }
        assert.equal(guest.read("attempts"), attempts, change);
        assert.equal(guest.read("drops"), drops, change);
      }
    } finally {
      guest.dispose();
    }
  }
});

Deno.test("resource publication allocation failure attempts cleanup once and leaves no phantom owner", async () => {
  const guest = await instantiateGuest(ownerFixture("valid"));
  const original = globalThis.Uint32Array;
  const failure = new Error("host view allocation failed");
  try {
    globalThis.Uint32Array = new Proxy(original, {
      construct() {
        throw failure;
      },
    });
    assert.throws(() => guest.call("run", null), (cause) => cause === failure);
    globalThis.Uint32Array = original;
    assert.equal(guest.read("attempts"), 1);
    assert.equal(guest.read("drops"), 1);
    assert.equal(guest.call("run", null), 9);
    assert.equal(guest.read("attempts"), 2);
    assert.equal(guest.read("drops"), 2);
  } finally {
    globalThis.Uint32Array = original;
    guest.dispose();
  }
});
