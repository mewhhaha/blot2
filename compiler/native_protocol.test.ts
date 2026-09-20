import { deepStrictEqual as equal, ok, throws } from "node:assert/strict";
import { CompilerError } from "./diagnostics.ts";
import { NativeProcess } from "./native_process.ts";
import {
  decodeNativeResponse,
  encodeNativeRequest,
  NativeProtocolError,
  nativeProtocolMagic,
  nativeProtocolMaxWords,
  nativeProtocolVersion,
  type NativeRequest,
} from "./native_protocol.ts";
import type { Cst, CstList } from "./syntax.ts";

const emptyModule: Cst = {
  $: "Cst",
  kind: "module",
  field: "",
  text: "",
  offset: 0n,
  children: { $: "Nil" },
};
const tinyRequest: NativeRequest = {
  operation: "analyze",
  root: emptyModule,
  prelude: emptyModule,
  fuel: 1n,
  const_steps: 7n,
};

function words(values: readonly number[]): Uint8Array<ArrayBuffer> {
  const payload = new Uint8Array(values.length * 4);
  const view = new DataView(payload.buffer);
  values.forEach((value, index) => view.setUint32(index * 4, value, true));
  return payload;
}

function replaceWord(payload: Uint8Array, index: number, value: number) {
  const changed = payload.slice();
  new DataView(changed.buffer).setUint32(index * 4, value, true);
  return changed;
}

async function withNative(work: (process: NativeProcess) => Promise<void>) {
  const process = await NativeProcess.start({ threads: 1 });
  let timer: ReturnType<typeof setTimeout> | undefined;
  const running = work(process);
  try {
    await Promise.race([
      running,
      new Promise<never>((_, reject) => {
        timer = setTimeout(
          () => reject(new Error("Native protocol test timed out")),
          15_000,
        );
      }),
    ]);
  } finally {
    clearTimeout(timer);
    await process.dispose();
    await Promise.allSettled([running]);
  }
}

async function acceptsTinyRequest(process: NativeProcess) {
  const response = decodeNativeResponse(
    await process.request(encodeNativeRequest(tinyRequest)),
  );
  equal(response, {
    operation: "analyze",
    analysis: {
      functions: [],
      constants: [],
      world: { registrations: [], systems: [], batches: [] },
      remaining_steps: 7n,
    },
  });
}

async function rejectsPayload(
  process: NativeProcess,
  payload: Uint8Array<ArrayBuffer>,
) {
  const response = await process.request(payload);
  throws(
    () => decodeNativeResponse(response),
    (error) => {
      ok(error instanceof CompilerError);
      equal(error.code, "native_protocol");
      ok(/^word:\d+$/.test(error.subject), error.subject);
      ok(error.detail.length > 0, "protocol diagnostics explain the failure");
      return true;
    },
  );
  await acceptsTinyRequest(process);
}

Deno.test("native decoder rejects every truncated request prefix and recovers", async () => {
  const payload = encodeNativeRequest(tinyRequest);
  await withNative(async (process) => {
    for (let count = 0; count < payload.length / 4; count++) {
      await rejectsPayload(process, payload.slice(0, count * 4));
    }
  });
});

Deno.test("native decoder rejects invalid headers, scalars, counts and trailing words", async () => {
  const payload = encodeNativeRequest(tinyRequest);
  // Header is seven words; this root has a six-scalar kind and empty field/text.
  const rootOffsetHigh = 17;
  const rootChildren = 18;
  const mutations = [
    { index: 0, value: 0 },
    { index: 1, value: 2 },
    { index: 2, value: 3 },
    { index: 4, value: 65536 },
    { index: 6, value: 65536 },
    { index: rootOffsetHigh, value: 65536 },
    { index: 8, value: 0xD800 },
    { index: 8, value: 0xDFFF },
    { index: 8, value: 0x110000 },
    { index: 7, value: 0xFFFFFFFF },
    { index: rootChildren, value: 0xFFFFFFFF },
  ];
  await withNative(async (process) => {
    for (const { index, value } of mutations) {
      await rejectsPayload(process, replaceWord(payload, index, value));
    }
    const trailing = new Uint8Array(payload.length + 4);
    trailing.set(payload);
    await rejectsPayload(process, trailing);
  });
});

Deno.test("native decoder preserves maximum Nat values and valid Unicode scalars", async () => {
  const max = 0xFFFFFFFFFFFFn;
  await withNative(async (process) => {
    const response = decodeNativeResponse(
      await process.request(encodeNativeRequest({
        ...tinyRequest,
        fuel: max,
        const_steps: max,
        root: { ...emptyModule, text: "\0雪🙂\u{10FFFF}", offset: max },
      })),
    );
    ok(response.operation === "analyze");
    equal(response.analysis.remaining_steps, max);
    await acceptsTinyRequest(process);
  });
});

const prefix = (
  kind: number,
) => [nativeProtocolMagic, nativeProtocolVersion, kind];
const emptyAnalysis = [0, 0, 0, 0, 0, 0, 0];
const string = (
  value: string,
) => [
  Array.from(value).length,
  ...Array.from(value, (character) => character.codePointAt(0)!),
];

Deno.test("response decoder rejects malformed framing, tags, Unicode, Nat and counts", () => {
  const valid = [...prefix(1), ...emptyAnalysis];
  for (let count = 0; count < valid.length; count++) {
    throws(
      () => decodeNativeResponse(words(valid.slice(0, count))),
      NativeProtocolError,
    );
  }
  const malformed = [
    [0, ...valid.slice(1)],
    [nativeProtocolMagic, 2, ...valid.slice(2)],
    [...prefix(4)],
    [...valid, 0],
    [...valid.slice(0, -1), 65536],
    [...prefix(0), 1, 0xD800],
    [...prefix(0), 1, 0x110000],
    [...prefix(0), nativeProtocolMaxWords + 1],
    [...prefix(1), nativeProtocolMaxWords + 1],
    // Unknown parameter type, Boolean value, effect access, and storage tags.
    [...prefix(1), 1, ...string("f"), 999],
    [...prefix(1), 0, 1, ...string("c"), 2, 2],
    [...prefix(1), 1, ...string("f"), 0, 0, 0, 1, 3],
    [...prefix(1), 0, 0, 1, ...string(""), ...string(""), 2],
    // A claimed multi-gigabyte byte vector must fail before allocating it.
    [...prefix(2), ...emptyAnalysis, 0xFFFFFFFF, 0],
  ];
  for (const payload of malformed) {
    throws(() => decodeNativeResponse(words(payload)), NativeProtocolError);
  }
  throws(() => decodeNativeResponse(Uint8Array.of(0)), NativeProtocolError);
  // Exercise the declared-size guard without allocating a 64 MiB payload.
  const oversized = new Uint8Array();
  Object.defineProperty(oversized, "byteLength", {
    value: (nativeProtocolMaxWords + 1) * 4,
  });
  throws(
    () => decodeNativeResponse(oversized),
    /Native response exceeds 16M words/,
  );
});

Deno.test("response decoder enforces packed byte padding and exact diagnostic consumption", () => {
  for (let length = 0; length <= 5; length++) {
    const bytes = Array.from({ length }, (_, index) => index + 1);
    const packed: number[] = [];
    for (let index = 0; index < bytes.length; index += 4) {
      packed.push(
        (bytes[index] ?? 0) | (bytes[index + 1] ?? 0) << 8 |
          (bytes[index + 2] ?? 0) << 16 | (bytes[index + 3] ?? 0) << 24,
      );
    }
    const encoded = [...prefix(2), ...emptyAnalysis, length, ...packed];
    const result = decodeNativeResponse(words(encoded));
    ok(result.operation === "compile");
    equal(result.artifact.bytes, Uint8Array.from(bytes));
    if (length % 4) {
      encoded[encoded.length - 1] |= 1 << ((length % 4) * 8);
      throws(
        () => decodeNativeResponse(words(encoded)),
        /padding must be zero/,
      );
    }
  }
  const diagnostic = [
    ...prefix(0),
    ...string("native_protocol"),
    ...string("word:7"),
    ...string("bad 雪🙂\0"),
  ];
  throws(() => decodeNativeResponse(words(diagnostic)), (error) => {
    ok(error instanceof CompilerError);
    equal({ code: error.code, subject: error.subject, detail: error.detail }, {
      code: "native_protocol",
      subject: "word:7",
      detail: "bad 雪🙂\0",
    });
    return true;
  });
  throws(
    () => decodeNativeResponse(words([...diagnostic, 0])),
    NativeProtocolError,
  );
});

Deno.test("request encoder rejects out-of-range Nat, invalid Unicode and cyclic CSTs", () => {
  for (const fuel of [-1n, 0x1000000000000n]) {
    throws(
      () => encodeNativeRequest({ ...tinyRequest, fuel }),
      NativeProtocolError,
    );
  }
  throws(() =>
    encodeNativeRequest({
      ...tinyRequest,
      root: { ...emptyModule, text: "\uD800" },
    }), NativeProtocolError);
  const cyclic: Omit<Cst, "children"> & { children: CstList } = {
    ...emptyModule,
  };
  cyclic.children = { $: "Con", head: cyclic, tail: { $: "Nil" } };
  throws(
    () => encodeNativeRequest({ ...tinyRequest, root: cyclic }),
    /Cyclic CST tree/,
  );
  const children: { $: "Con"; head: Cst; tail: CstList } = {
    $: "Con",
    head: emptyModule,
    tail: { $: "Nil" },
  };
  children.tail = children;
  throws(() =>
    encodeNativeRequest({
      ...tinyRequest,
      root: { ...emptyModule, children },
    }), /Cyclic CST child list/);
});
