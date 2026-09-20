import { deepStrictEqual as equal, ok, throws } from "node:assert/strict";
import { CompilerError } from "./diagnostics.ts";
import { NativeProcess } from "./native_process.ts";
import {
  decodeNativeResponse,
  decodeNativeSessionResponse,
  encodeNativeRequest,
  encodeNativeSessionRequest,
  NativeProtocolError,
  nativeProtocolMagic,
  nativeProtocolMaxWords,
  nativeProtocolVersion,
  type NativeRequest,
  type NativeResponse,
} from "./native_protocol.ts";
import type { Cst, CstList } from "./syntax.ts";
import { bendList } from "./bend_list.ts";

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

async function withNative(
  work: (process: NativeProcess) => Promise<void>,
  threads = 1,
) {
  const process = await NativeProcess.start({ threads });
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
  const payloads = [
    encodeNativeRequest(tinyRequest),
    encodeNativeRequest({ ...tinyRequest, operation: "compile" }),
    encodeNativeSessionRequest({
      operation: "open",
      prelude: emptyModule,
      fuel: 1n,
    }),
    ...(["analyze", "compile"] as const).flatMap((operation) => [
      encodeNativeSessionRequest({ ...tinyRequest, operation }),
      encodeNativeSessionRequest({
        operation,
        fuel: 1n,
        const_steps: 7n,
        declarations: [
          { kind: "replaced", node: emptyModule },
          { kind: "retained", identity: 0xFFFFFFFFFFFFn },
          { kind: "replaced", node: { ...emptyModule, text: "雪🙂" } },
        ],
      }),
    ]),
  ];
  await withNative(async (process) => {
    for (const payload of payloads) {
      for (let count = 0; count < payload.length / 4; count++) {
        await rejectsPayload(process, payload.slice(0, count * 4));
      }
    }
  });
});

Deno.test("native request headers preserve exact validation order and Nat offsets", async () => {
  const header = [nativeProtocolMagic, nativeProtocolVersion, 0];
  const cases = [
    [[0], 0, "invalid protocol magic; expected BLOT"],
    [
      [nativeProtocolMagic, 0],
      1,
      "unsupported native protocol version; expected 7",
    ],
    [
      [nativeProtocolMagic, nativeProtocolVersion, 10],
      2,
      "unknown operation; expected 0..6",
    ],
    [[...header], 3, "truncated request while reading frontend fuel low word"],
    [
      [...header, 0],
      4,
      "truncated request while reading frontend fuel high word",
    ],
    [[...header, 0, 65536], 4, "Nat high word exceeds 16 bits"],
    [
      [...header, 0, 0],
      5,
      "truncated request while reading const steps low word",
    ],
    [
      [...header, 0, 0, 0],
      6,
      "truncated request while reading const steps high word",
    ],
    [[...header, 0, 0, 0, 65536], 6, "Nat high word exceeds 16 bits"],
    [
      [nativeProtocolMagic, nativeProtocolVersion, 2, 0],
      4,
      "truncated request while reading prelude fuel high word",
    ],
    [
      [nativeProtocolMagic, nativeProtocolVersion, 5, 0, 0, 0, 0, 0, 1, 0, 0],
      11,
      "truncated request while reading retained declaration identity high word",
    ],
    [
      [nativeProtocolMagic, nativeProtocolVersion, 6, 0, 0, 0, 0, 0, 1, 2],
      9,
      "unknown declaration tag; expected 0 retained or 1 replaced",
    ],
  ] as const;
  await withNative(async (process) => {
    for (const [payload, offset, detail] of cases) {
      const response = await process.request(words(payload));
      throws(() => decodeNativeResponse(response), (error) => {
        ok(error instanceof CompilerError);
        equal(error.code, "native_protocol");
        equal(error.subject, `word:${offset}`);
        equal(error.detail, detail);
        return true;
      });
      await acceptsTinyRequest(process);
    }
  });
});

Deno.test("native decoder rejects invalid headers, scalars, counts and trailing words", async () => {
  const payload = encodeNativeRequest(tinyRequest);
  // Seven header words, a dictionary count, "module", and the empty string.
  const rootOffsetHigh = 20;
  const rootChildren = 21;
  const mutations = [
    { index: 0, value: 0 },
    { index: 1, value: nativeProtocolVersion + 1 },
    { index: 2, value: 10 },
    { index: 4, value: 65536 },
    { index: 6, value: 65536 },
    { index: rootOffsetHigh, value: 65536 },
    { index: 9, value: 0xD800 },
    { index: 9, value: 0xDFFF },
    { index: 9, value: 0x110000 },
    { index: 7, value: 0xFFFFFFFF },
    { index: 8, value: 0xFFFFFFFF },
    { index: 16, value: 2 },
    { index: 17, value: 2 },
    { index: 18, value: 0xFFFFFFFF },
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

for (const threads of [1, 2, 4, 8]) {
  Deno.test(`native ${threads}-thread string decoder preserves scalar offsets and recovers`, async () => {
    const text = "\0雪🙂\u{10FFFF}".repeat(512);
    const payload = encodeNativeRequest({
      ...tinyRequest,
      root: { ...emptyModule, text },
    });
    // Header, dictionary count, "module", empty string, and text length.
    const first = 17;
    await withNative(async (process) => {
      for (const offset of [0, 1023, 2047]) {
        const response = await process.request(
          replaceWord(payload, first + offset, 0xD800),
        );
        throws(() => decodeNativeResponse(response), (error) => {
          ok(error instanceof CompilerError);
          equal(error.code, "native_protocol");
          equal(error.subject, `word:${first + offset}`);
          return true;
        });
        const valid = decodeNativeResponse(await process.request(payload));
        ok(valid.operation === "analyze");
        equal(valid.analysis.remaining_steps, 7n);
      }
    }, threads);
  });
}

Deno.test("declaration patches encode compact ordered references with exact Nat identities", () => {
  for (
    const [operation, opcode] of [
      ["analyze", 5],
      ["compile", 6],
    ] as const
  ) {
    equal(
      encodeNativeSessionRequest({
        operation,
        fuel: 1n,
        const_steps: 7n,
        declarations: [{ kind: "retained", identity: 0xFFFFFFFFFFFFn }],
      }),
      words([
        nativeProtocolMagic,
        nativeProtocolVersion,
        opcode,
        1,
        0,
        7,
        0,
        0,
        1,
        0,
        0xFFFFFFFF,
        65535,
      ]),
    );
  }
  for (const identity of [-1n, 0x1000000000000n]) {
    throws(
      () =>
        encodeNativeSessionRequest({
          operation: "compile",
          fuel: 1n,
          const_steps: 0n,
          declarations: [{ kind: "retained", identity }],
        }),
      /Retained declaration identity must be a Nat/,
    );
  }
});

Deno.test("native decoder rejects truncated and malformed declaration patches and recovers", async () => {
  const payload = encodeNativeSessionRequest({
    operation: "compile",
    fuel: 1n,
    const_steps: 7n,
    declarations: [
      { kind: "retained", identity: 0xFFFFFFFFFFFFn },
      {
        kind: "replaced",
        node: { ...emptyModule, field: "declarations", text: "雪🙂" },
      },
    ],
  });
  const view = new DataView(payload.buffer);
  let body = 8;
  for (let index = 0; index < view.getUint32(7 * 4, true); index++) {
    body += 1 + view.getUint32(body * 4, true);
  }
  await withNative(async (process) => {
    for (let count = 0; count < payload.length / 4; count++) {
      await rejectsPayload(process, payload.slice(0, count * 4));
    }
    for (
      const [index, value] of [
        [body, 0],
        [body, 0xFFFFFFFF],
        [body + 1, 2],
        [body + 3, 65536],
        [body + 4, 2],
      ]
    ) {
      await rejectsPayload(process, replaceWord(payload, index, value));
    }
    const trailing = new Uint8Array(payload.length + 4);
    trailing.set(payload);
    await rejectsPayload(process, trailing);
  });
});

const prefix = (
  kind: number,
) => [nativeProtocolMagic, nativeProtocolVersion, kind];
const emptyAnalysis = [0, 0, 0, 0];
const string = (
  value: string,
) => [
  Array.from(value).length,
  ...Array.from(value, (character) => character.codePointAt(0)!),
];

Deno.test("request dictionaries intern Unicode across trees, patches and buffer growth", () => {
  const text = "\0雪🙂\u{10FFFF}".repeat(512);
  const node: Cst = {
    ...emptyModule,
    kind: text,
    field: text,
    text,
    offset: 0xFFFFFFFFFFFFn,
  };
  const encodedNode = [
    0,
    0,
    0,
    0xFFFFFFFF,
    65535,
    0,
  ];
  const expected = words([
    nativeProtocolMagic,
    nativeProtocolVersion,
    1,
    0xFFFFFFFF,
    65535,
    7,
    0,
    1,
    ...string(text),
    ...encodedNode,
    ...encodedNode,
  ]);
  equal(
    encodeNativeRequest({
      operation: "compile",
      root: node,
      prelude: node,
      fuel: 0xFFFFFFFFFFFFn,
      const_steps: 7n,
    }),
    expected,
  );
  const declarations = [{ kind: "replaced" as const, node }, {
    kind: "retained" as const,
    identity: 42n,
  }, { kind: "replaced" as const, node }];
  equal(
    encodeNativeSessionRequest({
      operation: "compile",
      declarations,
      fuel: 1n,
      const_steps: 7n,
    }),
    words([
      nativeProtocolMagic,
      nativeProtocolVersion,
      6,
      1,
      0,
      7,
      0,
      1,
      ...string(text),
      3,
      1,
      ...encodedNode,
      0,
      42,
      0,
      1,
      ...encodedNode,
    ]),
  );
  equal(
    encodeNativeRequest(tinyRequest),
    words([
      nativeProtocolMagic,
      nativeProtocolVersion,
      0,
      1,
      0,
      7,
      0,
      2,
      ...string("module"),
      ...string(""),
      0,
      1,
      1,
      0,
      0,
      0,
      0,
      1,
      1,
      0,
      0,
      0,
    ]),
  );
});

Deno.test("dictionary compression preserves frame limits for unique strings", () => {
  const kind = "k".repeat(8192);
  const child = { ...emptyModule, kind };
  const compact = encodeNativeRequest({
    ...tinyRequest,
    root: { ...emptyModule, children: bendList(Array(2048).fill(child)) },
  });
  ok(compact.length < 100_000);
  const children = Array.from({ length: 2048 }, (_, index) => ({
    ...child,
    kind: `${index}:${kind}`,
  }));
  throws(
    () =>
      encodeNativeRequest({
        ...tinyRequest,
        root: { ...emptyModule, children: bendList(children) },
      }),
    /Native request exceeds 16M words/,
  );
});

Deno.test("protocol seven has only generic analyze/compile session operations", () => {
  equal(nativeProtocolVersion, 7);
  const opcode = (payload: Uint8Array) =>
    new DataView(payload.buffer, payload.byteOffset, payload.byteLength)
      .getUint32(8, true);
  equal(opcode(encodeNativeRequest(tinyRequest)), 0);
  equal(
    opcode(encodeNativeRequest({ ...tinyRequest, operation: "compile" })),
    1,
  );
  equal(
    opcode(encodeNativeSessionRequest({
      operation: "open",
      prelude: emptyModule,
      fuel: 1n,
    })),
    2,
  );
  for (
    const [operation, full, patch] of [["analyze", 3, 5], [
      "compile",
      4,
      6,
    ]] as const
  ) {
    equal(
      opcode(encodeNativeSessionRequest({
        operation,
        root: emptyModule,
        fuel: 1n,
        const_steps: 7n,
      })),
      full,
    );
    equal(
      opcode(encodeNativeSessionRequest({
        operation,
        declarations: [],
        fuel: 1n,
        const_steps: 7n,
      })),
      patch,
    );
  }
  equal(decodeNativeSessionResponse(words(prefix(3))), { operation: "open" });
  const cached = decodeNativeSessionResponse(words([
    ...prefix(4),
    ...Array<number>(16).fill(0),
    1,
    ...emptyAnalysis,
  ]));
  ok("result" in cached && cached.result.operation === "analyze");
  equal(cached.result.analysis, {
    functions: [],
    constants: [],
    remaining_steps: 0n,
  });
  for (const kind of [5, 6, 999]) {
    throws(
      () => decodeNativeSessionResponse(words(prefix(kind))),
      NativeProtocolError,
    );
  }
});

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
    [nativeProtocolMagic, nativeProtocolVersion + 1, ...valid.slice(2)],
    [...prefix(4)],
    [...valid, 0],
    [...valid.slice(0, -1), 65536],
    [...prefix(0), 1, 0xD800],
    [...prefix(0), 1, 0x110000],
    [...prefix(0), nativeProtocolMaxWords + 1],
    [...prefix(1), nativeProtocolMaxWords + 1],
    // Unknown type/Boolean/row tags and a malformed nominal effect identity.
    [...prefix(1), 1, ...string("f"), 999],
    [...prefix(1), 0, 1, ...string("c"), 2, 2],
    [...prefix(1), 1, ...string("f"), 0, 0, 0, 0, 0, 3],
    [...prefix(1), 1, ...string("f"), 0, 0, 0, 1, 1, 0xD800],
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

Deno.test("response decoder preserves nested tuple patterns inside closure bodies", () => {
  const pattern = [
    6,
    2, // ProductPattern with two fields.
    1,
    ...string("first"),
    5,
    ...string("Wrapped"),
    1,
    6,
    2,
    4,
    1,
    0, // Wrapped (True, _).
  ];
  const encoded = [
    ...prefix(1),
    0, // No function signatures.
    1,
    ...string("saved"),
    6,
    7,
    0,
    ...string("pair"), // ClosureValue identity and parameter.
    16,
    1,
    3,
    ...string("pair"), // MatchExpr, one LocalExpr scrutinee.
    1,
    1,
    ...pattern, // One arm, one tuple pattern.
    3,
    ...string("first"), // Arm body.
    0, // No closure captures.
    19,
    0, // Remaining const steps.
  ];
  const expected: NativeResponse = {
    operation: "analyze",
    analysis: {
      functions: [],
      constants: [{
        name: "saved",
        value: {
          $: "ClosureValue",
          identity: 7n,
          parameter: "pair",
          body: {
            $: "MatchExpr",
            values: [{ $: "LocalExpr", name: "pair" }],
            arms: [{
              patterns: [{
                $: "ProductPattern",
                elements: [{ $: "BindingPattern", name: "first" }, {
                  $: "ConstructorPattern",
                  constructor: "Wrapped",
                  payload: {
                    $: "ProductPattern",
                    elements: [
                      { $: "BoolPattern", value: true },
                      { $: "WildcardPattern" },
                    ],
                  },
                }],
              }],
              body: { $: "LocalExpr", name: "first" },
            }],
          },
          environment: [],
        },
      }],
      remaining_steps: 19n,
    },
  };
  equal(decodeNativeResponse(words(encoded)), expected);
  for (let length = 3; length < encoded.length; length++) {
    throws(
      () => decodeNativeResponse(words(encoded.slice(0, length))),
      NativeProtocolError,
    );
  }
  throws(
    () => decodeNativeResponse(words([...encoded, 0])),
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
