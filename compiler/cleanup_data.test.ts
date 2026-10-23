import { strict as assert } from "node:assert";
import {
  copyData,
  type DataNode,
  readDataSchemas,
  validateDataRoots,
} from "./cleanup_data.ts";
const name = (text: string) => {
  const bytes = new TextEncoder().encode(text);
  return [bytes.length, ...bytes];
};
const leb = (n: number): number[] => {
  const result: number[] = [];
  do {
    let byte = n & 127;
    n >>>= 7;
    if (n !== 0) byte |= 128;
    result.push(byte);
  } while (n !== 0);
  return result;
};
function module(nodes: unknown[], text?: string): WebAssembly.Module {
  const data = new TextEncoder().encode(
    text ?? JSON.stringify({ version: 1, nodes }),
  );
  const payload = [...name("blot:cleanup_data"), ...data];
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
      0,
      ...leb(payload.length),
      ...payload,
    ]),
  );
}
function node(
  id: number,
  tag: DataNode["tag"],
  extra: Partial<DataNode> = {},
): DataNode {
  return {
    id,
    tag,
    floating: tag === "f32",
    reference: !["unit", "boolean", "u32", "f32"].includes(tag),
    child: 0,
    row_words: 0,
    leaf_words: 0,
    children: [],
    fields: [],
    variants: [],
    name: "",
    ...extra,
  };
}
const scalar = node(3, "u32"),
  array = node(7, "array", { child: 3 }),
  record = node(8, "record", {
    fields: [{ name: "items", child: 7 }, { name: "nonce", child: 3 }],
  });
Deno.test("cleanup data schemas reject missing edges false roles hidden features and unsupported cycles", () => {
  const valid = readDataSchemas(module([scalar, array, record]))!;
  validateDataRoots(valid, [8]);
  for (
    const nodes of [
      [],
      [scalar, scalar],
      [{ ...scalar, tag: "owning" }],
      [{ ...scalar, reference: true }],
      [{ ...scalar, feature: "usage" }],
      [{ ...array, child: 99 }],
      [scalar, {
        ...record,
        fields: [{ name: "same", child: 3 }, { name: "same", child: 3 }],
      }],
      [scalar, { ...array, row_words: 2 }],
      [node(7, "list", { child: 3, leaf_words: 0 }), scalar],
    ]
  ) {
    assert.throws(() => {
      const parsed = readDataSchemas(module(nodes));
      validateDataRoots(parsed, [8]);
    });
  }
  const cycle = readDataSchemas(module([node(7, "array", { child: 7 })]));
  assert.throws(() => validateDataRoots(cycle, [7]));
  assert.throws(() =>
    readDataSchemas(module([], '{"version":1,"version":1,"nodes":[]}'))
  );
  assert.throws(() => validateDataRoots(valid, [3]));
});
Deno.test("cleanup data copies retain no guest alias and enforce actual typed child slots", () => {
  const schemas = readDataSchemas(module([scalar, array, record]))!;
  const memory = new WebAssembly.Memory({ initial: 2 });
  const words = new DataView(memory.buffer);
  const object = 65600, values = 65700;
  const block = (pointer: number, requested: number, mask: number) => {
    words.setUint32(pointer - 28, requested, true);
    words.setUint32(pointer - 24, 4, true);
    words.setUint32(pointer - 16, 1, true);
    words.setUint32(pointer - 12, mask, true);
  };
  block(object, 8, 1);
  block(values, 12, 0);
  words.setUint32(object, values, true);
  words.setUint32(object + 4, 7, true);
  words.setUint32(values, 2, true);
  words.setUint32(values + 4, 1, true);
  words.setUint32(values + 8, 2, true);
  const copied = copyData(memory, schemas, 8, object) as {
    items: Uint32Array;
    nonce: number;
  };
  assert(Object.isFrozen(copied));
  assert.deepEqual(copied, { items: new Uint32Array([1, 2]), nonce: 7 });
  copied.items[0] = 99;
  assert.equal(words.getUint32(values + 4, true), 1);
  words.setUint32(object - 12, 0, true);
  assert.throws(() => copyData(memory, schemas, 8, object), /slot role/);
  words.setUint32(object - 12, 1, true);
  words.setUint32(values - 24, 20, true);
  assert.throws(() => copyData(memory, schemas, 8, object), /live typed block/);
  words.setUint32(values - 24, 4, true);
  words.setUint32(values, 0xffffffff, true);
  assert.throws(() => copyData(memory, schemas, 8, object), /copy limit/);
  words.setUint32(values, 2, true);
  words.setUint32(object, 0, true);
  assert.throws(() => copyData(memory, schemas, 8, object), /outside/);
});

Deno.test("cleanup packed list rows cannot read beyond the leaf logical extent", () => {
  const row = node(9, "product", { children: [3, 3] });
  const list = node(10, "list", { child: 9, row_words: 2, leaf_words: 244 });
  const schemas = readDataSchemas(module([scalar, row, list]))!;
  const memory = new WebAssembly.Memory({ initial: 2 });
  const view = new DataView(memory.buffer);
  const descriptor = 65600, leaf = 65700;
  const block = (pointer: number, bytes: number, mask: number) => {
    view.setUint32(pointer - 28, bytes, true);
    view.setUint32(pointer - 24, 4, true);
    view.setUint32(pointer - 16, 1, true);
    view.setUint32(pointer - 12, mask, true);
  };
  block(descriptor, 32, 2);
  view.setUint32(descriptor, 2, true);
  view.setUint32(descriptor + 4, leaf, true);
  view.setUint32(descriptor + 16, 2, true);
  view.setUint32(descriptor + 24, 244, true);
  block(leaf, 24, 0);
  view.setUint32(leaf + 8, 2, true);
  view.setUint32(leaf + 12, 2, true);
  view.setUint32(leaf + 16, 7, true);
  view.setUint32(leaf + 20, 9, true);
  assert.deepEqual(copyData(memory, schemas, 10, descriptor), [[7, 9]]);
  view.setUint32(leaf + 8, 1, true);
  assert.throws(
    () => copyData(memory, schemas, 10, descriptor),
    /leaf capacity/,
  );
});

Deno.test("cleanup copies packed nested nominal rows with their logical shape", () => {
  const floating = node(4, "f32");
  const pair = node(5, "record", {
    fields: [{ name: "x", child: 4 }, { name: "y", child: 4 }],
  });
  const vector = node(6, "nominal", {
    name: "Vector",
    variants: [{ tag: 7, child: 5 }],
  });
  const matrix = node(7, "product", { children: [6, 6] });
  const values = node(8, "array", { child: 7, row_words: 4 });
  const schemas = readDataSchemas(
    module([floating, pair, vector, matrix, values]),
  )!;
  validateDataRoots(schemas, [8]);
  const memory = new WebAssembly.Memory({ initial: 2 });
  const view = new DataView(memory.buffer);
  const address = 65600;
  view.setUint32(address - 28, 20, true);
  view.setUint32(address - 24, 4, true);
  view.setUint32(address - 16, 1, true);
  view.setUint32(address, 1, true);
  for (const [index, value] of [-0, 1.5, -7.25, Infinity].entries()) {
    view.setFloat32(address + 4 + index * 4, value, true);
  }
  const copied = copyData(memory, schemas, 8, address);
  assert.deepEqual(copied, [[{
    family: "Vector",
    tag: 7,
    value: { x: -0, y: 1.5 },
  }, { family: "Vector", tag: 7, value: { x: -7.25, y: Infinity } }]]);
  view.setFloat32(address + 4, 100, true);
  assert.deepEqual(copied, [[{
    family: "Vector",
    tag: 7,
    value: { x: -0, y: 1.5 },
  }, { family: "Vector", tag: 7, value: { x: -7.25, y: Infinity } }]]);
  for (
    const invalid of [
      { ...values, row_words: 3 },
      { ...values, child: 8 },
    ]
  ) {
    assert.throws(() =>
      readDataSchemas(module([floating, pair, vector, matrix, invalid]))
    );
  }
  assert.throws(() =>
    readDataSchemas(
      module([
        floating,
        pair,
        { ...vector, variants: [{ tag: 7, child: 5 }, { tag: 8, child: 5 }] },
        matrix,
        values,
      ]),
    )
  );
});

Deno.test("structured cleanup independently links the actual schema and payload import types", async () => {
  const { instantiateGuest, GuestError } = await import("./guest.ts");
  const section = (
    id: number,
    payload: number[],
  ) => [id, ...leb(payload.length), ...payload];
  const runBody = (schemaType: number): number[] => {
    if (schemaType === 125) return [4, 0, 65, 42, 11];
    return [11, 0, 32, 0, 65, 3, 65, 128, 8, 16, 0, 11];
  };
  const make = (schemaType: number) =>
    new WebAssembly.Module(
      new Uint8Array([
        0,
        97,
        115,
        109,
        1,
        0,
        0,
        0,
        ...section(1, [
          5,
          96,
          3,
          111,
          schemaType,
          127,
          1,
          127,
          96,
          1,
          111,
          1,
          127,
          96,
          0,
          0,
          96,
          1,
          127,
          0,
          96,
          1,
          127,
          1,
          127,
        ]),
        ...section(2, [
          1,
          ...name("blot:cleanup_data/1"),
          ...name("call_data_unit"),
          0,
          0,
        ]),
        ...section(3, [5, 1, 2, 3, 4, 4]),
        ...section(5, [1, 0, 1]),
        ...section(6, [2, 127, 0, 65, 0, 11, 127, 0, 65, 0, 11]),
        ...section(7, [
          12,
          ...name("blot:rc_leases"),
          3,
          0,
          ...name("blot:rc_retains"),
          3,
          0,
          ...name("blot:rc_releases"),
          3,
          0,
          ...name("blot:rc_destroyed"),
          3,
          0,
          ...name("run"),
          0,
          1,
          ...name("blot:ownership_enter"),
          0,
          2,
          ...name("blot:ownership_leave"),
          0,
          3,
          ...name("blot:allocate"),
          0,
          4,
          ...name("blot:reset"),
          0,
          5,
          ...name("blot:rc_roots"),
          3,
          0,
          ...name("blot:rc_host_refs"),
          3,
          1,
          ...name("blot:memory"),
          2,
          0,
        ]),
        ...section(10, [
          5,
          ...runBody(schemaType),
          2,
          0,
          11,
          2,
          0,
          11,
          5,
          0,
          65,
          128,
          8,
          11,
          4,
          0,
          65,
          0,
          11,
        ]),
        ...section(0, [
          ...name("blot:abi"),
          7,
          0,
          0,
          1,
          ...name("run"),
          11,
          8,
          1,
          0,
        ]),
        ...section(0, [...name("blot:ownership"), 2, 2, 0]),
        ...section(0, [
          ...name("blot:cleanup_data"),
          ...new TextEncoder().encode(
            JSON.stringify({ version: 1, nodes: [scalar, array, record] }),
          ),
        ]),
      ]),
    );
  const valid = await instantiateGuest(make(127));
  let stepsReads = 0;
  let callsReads = 0;
  valid.cleanupCapability({
    parameter: "U32",
    result: "Unit",
    get maxSteps() {
      stepsReads++;
      if (stepsReads === 1) return 16;
      return Infinity;
    },
    get maxCalls() {
      callsReads++;
      if (callsReads === 1) return 1;
      return Infinity;
    },
    call: () => null,
  });
  assert.equal(stepsReads, 1);
  assert.equal(callsReads, 1);
  const capability = valid.cleanupDataCapability({
    type: valid.cleanupDataType("run"),
    maxSteps: 16,
    maxCalls: 1,
    call: () => null,
  });
  assert.throws(
    () => valid.call("run", capability),
    (error: unknown) =>
      error instanceof GuestError && error.code === "capability_signature",
  );
  valid.dispose();
  await assert.rejects(
    () => instantiateGuest(make(125)),
    (error: unknown) =>
      error instanceof GuestError && error.code === "invalid_abi",
  );
});
