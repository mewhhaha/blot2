import {
  deepStrictEqual as equal,
  ok,
  rejects,
  throws,
} from "node:assert/strict";
import { runInNewContext } from "node:vm";
import {
  type Guest,
  GuestError,
  instantiateGuest,
  readGuestAbi,
  type ScalarType,
  type ScalarValue,
} from "./guest.ts";
import { compile } from "./test_compile.ts";

const source = `
effect Number.advance: U32 -> U32
const tick = fn value => do:
  use next <- Number.advance value
  return next
entry const main = fn (advance: U32 -> U32 ! {Foreign}) => do (@effect.provider Number.advance advance):
  use next <- tick 41
  return next
entry const pure = fn () => 7
entry const count = 12
`;

function compiled(text = source) {
  return compile(text);
}

function errorCode(code: GuestError["code"]) {
  return (error: unknown) => {
    ok(error instanceof GuestError, String(error));
    equal(error.code, code, error.message);
    return true;
  };
}

function advance(guest: Guest, call = (value: number) => value + 1) {
  return guest.capability({ parameter: "U32", result: "U32", call });
}

Deno.test("explicit capabilities implement source effects, with no domain imports", async () => {
  const artifact = await compiled();
  const module = new WebAssembly.Module(artifact.bytes);
  equal(WebAssembly.Module.imports(module), [
    { module: "blot:host/1", name: "call_u32_u32", kind: "function" },
  ]);
  const guest = await instantiateGuest(module);
  try {
    equal(guest.call("main", advance(guest)), 42);
    equal(guest.call("pure", null), 7);
    equal(guest.read("count"), 12);
    equal(guest.abi, {
      version: 2,
      functions: [
        {
          name: "main",
          parameter: { kind: "callback", parameter: "U32", result: "U32" },
          result: "U32",
        },
        { name: "pure", parameter: "Unit", result: "U32" },
      ],
      constants: [{ name: "count", type: "U32" }],
    });
    ok(Object.isFrozen(guest.abi));
    ok(Object.isFrozen(guest.abi.functions[0].parameter));
  } finally {
    guest.dispose();
  }
});

Deno.test("all sixteen scalar callback signatures use checked canonical values", async () => {
  const types = ["Unit", "U32", "Bool", "F32"] as const;
  const literals: Record<ScalarType, string> = {
    Unit: "()",
    U32: "4_294_967_295",
    Bool: "#True",
    F32: "(-0.0)",
  };
  const arguments_: Record<ScalarType, ScalarValue> = {
    Unit: null,
    U32: 0xFFFFFFFF,
    Bool: true,
    F32: -0,
  };
  const results: Record<ScalarType, ScalarValue> = {
    Unit: null,
    U32: 0xFFFFFFFF,
    Bool: false,
    F32: 1.1,
  };
  const definitions = types.flatMap((parameter) =>
    types.map((result) =>
      `entry const invoke_${parameter.toLowerCase()}_${result.toLowerCase()} = fn (io: ${parameter} -> ${result} ! {Foreign}) => do:
  use result <- io ${literals[parameter]}
  return result`
    )
  ).join("\n");
  const guest = await instantiateGuest((await compiled(definitions)).bytes);
  try {
    for (const parameter of types) {
      for (const result of types) {
        let calls = 0;
        const capability = guest.capability({
          parameter,
          result,
          call(value) {
            calls++;
            equal(value, arguments_[parameter]);
            return results[result];
          },
        });
        equal(
          guest.call(
            `invoke_${parameter.toLowerCase()}_${result.toLowerCase()}`,
            capability,
          ),
          result === "F32" ? Math.fround(1.1) : results[result],
        );
        equal(calls, 1);
      }
    }
  } finally {
    guest.dispose();
  }
});

Deno.test("capabilities cannot be missing, forged, mis-typed, or reused across instances", async () => {
  const { bytes } = await compiled();
  const guest = await instantiateGuest(bytes);
  const replacement = await instantiateGuest(bytes);
  try {
    const capability = advance(guest);
    for (
      const invalid of [undefined, null, 0, "main", (x: number) => x, {
        ...capability,
      }]
    ) {
      throws(
        () => guest.call("main", invalid),
        errorCode("invalid_capability"),
      );
    }
    const wrong = guest.capability({
      parameter: "Bool",
      result: "U32",
      call: () => 1,
    });
    throws(() => guest.call("main", wrong), errorCode("capability_signature"));
    throws(
      () => replacement.call("main", capability),
      errorCode("foreign_capability"),
    );
    equal(guest.call("main", capability), 42);
    guest.dispose();
    throws(
      () => replacement.call("main", capability),
      errorCode("stale_capability"),
    );
    throws(() => guest.call("pure", null), errorCode("disposed_guest"));
    throws(() => advance(guest), errorCode("disposed_guest"));
    equal(
      replacement.call("main", advance(replacement, (value) => value + 2)),
      43,
    );
  } finally {
    guest.dispose();
    replacement.dispose();
  }
});

Deno.test("callback bindings snapshot definitions and repeated calls get fresh scopes", async () => {
  const guest = await instantiateGuest((await compiled()).bytes);
  try {
    const definition = {
      parameter: "U32" as ScalarType,
      result: "U32" as ScalarType,
      call: () => 42,
    };
    const capability = guest.capability(definition);
    definition.parameter = "Bool";
    definition.result = "Bool";
    definition.call = () => 9;
    equal(guest.call("main", capability), 42);
    equal(guest.call("main", advance(guest, () => 43)), 43);
    equal(guest.call("main", capability), 42);
  } finally {
    guest.dispose();
  }
});

Deno.test("host exceptions and invalid callback results fail without poisoning subsequent calls", async () => {
  const guest = await instantiateGuest((await compiled()).bytes);
  try {
    const cause = new Error("device disconnected");
    let calls = 0;
    const flaky = advance(guest, () => {
      calls++;
      if (calls === 2) throw cause;
      return 42;
    });
    equal(guest.call("main", flaky), 42);
    throws(() => guest.call("main", flaky), (error) => {
      ok(error instanceof GuestError);
      equal(error.code, "host_exception");
      equal(error.cause, cause);
      ok(error.message.includes("main"));
      return true;
    });
    equal(guest.call("main", flaky), 42);
    const object = {
      valueOf() {
        throw new Error("must not coerce");
      },
    };
    for (
      const invalid of [
        -1,
        0x100000000,
        0.5,
        NaN,
        Infinity,
        true,
        "42",
        object,
        undefined,
      ]
    ) {
      const bad = advance(guest, () => invalid as number);
      throws(() => guest.call("main", bad), errorCode("host_result"));
      equal(guest.call("main", flaky), 42);
    }
  } finally {
    guest.dispose();
  }
});

Deno.test("async callback results are rejected, including already-rejected Promises", async () => {
  const guest = await instantiateGuest((await compiled()).bytes);
  try {
    for (
      const call of [
        () => Promise.resolve(42),
        () => Promise.reject(new Error("async failure")),
        () =>
          runInNewContext('Promise.reject(new Error("cross-realm failure"))'),
        () => {
          const promise = Promise.reject(new Error("overridden catch"));
          promise.catch = () => {
            throw new Error("must not call overridden catch");
          };
          return promise;
        },
        () => ({
          then() {
            throw new Error("must not await");
          },
        }),
      ]
    ) {
      const capability = advance(
        guest,
        call as unknown as (value: number) => number,
      );
      throws(
        () => guest.call("main", capability),
        errorCode("async_host_call"),
      );
      equal(guest.call("main", advance(guest)), 42);
    }
    await new Promise((resolve) => setTimeout(resolve, 0));
  } finally {
    guest.dispose();
  }
});

Deno.test("same-instance reentry and disposal are rejected while another guest can be called", async () => {
  const { bytes } = await compiled();
  const guest = await instantiateGuest(bytes);
  const other = await instantiateGuest(bytes);
  try {
    const capability = advance(guest, () => {
      throws(() => guest.call("pure", null), errorCode("reentrant_call"));
      throws(() => guest.dispose(), errorCode("reentrant_call"));
      return other.call("main", advance(other)) as number;
    });
    equal(guest.call("main", capability), 42);
    equal(guest.call("pure", null), 7);
  } finally {
    guest.dispose();
    other.dispose();
  }
});

Deno.test("scalar-only guests remain import-free and validate arguments and constants", async () => {
  const { bytes } = await compiled(`
entry const integer = fn (value: U32) => value
entry const boolean = fn (value: Bool) => value
entry const float = fn (value: F32) => value
entry const unit = fn () => ()
entry const flag = #True
entry const maximum = 4_294_967_295
entry const fraction = 1.25
entry const nothing = ()
`);
  equal(WebAssembly.Module.imports(new WebAssembly.Module(bytes)), []);
  const guest = await instantiateGuest(bytes);
  try {
    equal(guest.call("integer", 0xFFFFFFFF), 0xFFFFFFFF);
    equal(guest.call("boolean", false), false);
    equal(guest.call("float", 1.1), Math.fround(1.1));
    equal(guest.call("float", -0), -0);
    equal(guest.call("float", Infinity), Infinity);
    ok(Number.isNaN(guest.call("float", NaN)));
    equal(guest.call("unit", null), null);
    equal(guest.read("flag"), true);
    equal(guest.read("maximum"), 0xFFFFFFFF);
    equal(guest.read("fraction"), 1.25);
    equal(guest.read("nothing"), null);
    for (
      const [name, value] of [
        ["integer", -1],
        ["boolean", 1],
        ["float", "1.0"],
        ["unit", 0],
      ]
    ) {
      throws(
        () => guest.call(name as string, value),
        errorCode("invalid_argument"),
      );
    }
    throws(() => guest.call("missing", null), errorCode("unknown_export"));
    throws(() => guest.read("integer"), errorCode("unknown_export"));
  } finally {
    guest.dispose();
  }
});

function leb(value: number): number[] {
  const bytes: number[] = [];
  do {
    const low = value & 127;
    value >>>= 7;
    bytes.push(low | (value === 0 ? 0 : 128));
  } while (value !== 0);
  return bytes;
}
function name(value: string): number[] {
  const bytes = [...new TextEncoder().encode(value)];
  return [...leb(bytes.length), ...bytes];
}
function section(id: number, bytes: number[]): number[] {
  return [id, ...leb(bytes.length), ...bytes];
}
function wasm(...sections: number[][]): WebAssembly.Module {
  return new WebAssembly.Module(
    new Uint8Array([0, 97, 115, 109, 1, 0, 0, 0, ...sections.flat()]),
  );
}
function manifest(bytes: number[]): number[] {
  return section(0, [...name("blot:abi"), ...bytes]);
}

Deno.test("ABI decoder rejects ambiguous, malformed, and unsupported manifests", async () => {
  equal(readGuestAbi(wasm(manifest([2, 0, 0]))), {
    version: 2,
    functions: [],
    constants: [],
  });
  for (
    const module of [
      wasm(),
      wasm(manifest([2, 0, 0]), manifest([2, 0, 0])),
      ...[
        [],
        [1, 0, 0],
        [2, 0],
        [2, 0, 0, 0],
        [130, 0, 0, 0],
        [255, 255, 255, 255, 16],
        [2, 1, 255, 255, 255, 255, 15],
        [2, 1, 1, 255, 0, 0, 0],
        [2, 1, ...name("f"), 9, 0, 0],
        [2, 1, ...name("f"), 4, 4, 0, 0, 0],
        [2, 2, ...name("f"), 0, 0, ...name("f"), 0, 0, 0],
        [2, 1, ...name("f"), 0, 0, 1, ...name("f"), 0],
        [2, 1, ...name("missing"), 0, 0, 0],
      ].map((bytes) => wasm(manifest(bytes))),
    ]
  ) {
    throws(() => readGuestAbi(module), errorCode("invalid_abi"));
    await rejects(() => instantiateGuest(module), errorCode("invalid_abi"));
  }
});

Deno.test("ABI refuses any ambient or domain-specific import", () => {
  const module = wasm(
    section(1, [1, 96, 0, 0]),
    section(2, [1, ...name("window"), ...name("title"), 0, 0]),
    manifest([2, 0, 0]),
  );
  throws(() => readGuestAbi(module), errorCode("invalid_abi"));
});

Deno.test("even a Wasm module retaining a previous invocation reference cannot reuse it", async () => {
  const instructions = [
    0,
    35,
    0,
    209,
    4,
    64,
    32,
    0,
    36,
    0,
    11,
    35,
    0,
    65,
    41,
    16,
    0,
    11,
  ];
  const module = wasm(
    section(1, [2, 96, 2, 111, 127, 1, 127, 96, 1, 111, 1, 127]),
    section(2, [1, ...name("blot:host/1"), ...name("call_u32_u32"), 0, 0]),
    section(3, [1, 1]),
    section(6, [1, 111, 1, 208, 111, 11]),
    section(7, [1, ...name("main"), 0, 1]),
    section(10, [1, ...leb(instructions.length), ...instructions]),
    manifest([2, 1, ...name("main"), 4, 1, 1, 1, 0]),
  );
  const guest = await instantiateGuest(module);
  try {
    let calls = 0;
    const capability = advance(guest, (value) => {
      calls++;
      return value + 1;
    });
    equal(guest.call("main", capability), 42);
    throws(() => guest.call("main", capability), errorCode("stale_capability"));
    equal(calls, 1);
  } finally {
    guest.dispose();
  }
});

Deno.test("array ABI rejects malformed guest pointers and length headers", async () => {
  const module = wasm(
    section(1, [1, 96, 1, 127, 1, 127]),
    section(3, [3, 0, 0, 0]),
    section(5, [1, 1, 1, ...leb(256)]),
    section(7, [
      4,
      ...name("array"),
      0,
      0,
      ...name("blot:allocate"),
      0,
      1,
      ...name("blot:reset"),
      0,
      2,
      ...name("blot:memory"),
      2,
      0,
    ]),
    section(10, [3, 4, 0, 32, 0, 11, 4, 0, 65, 4, 11, 4, 0, 65, 4, 11]),
    section(11, [1, 0, 65, 4, 11, 4, 255, 255, 255, 255]),
    manifest([2, 1, ...name("array"), 1, 5, 0]),
  );
  const guest = await instantiateGuest(module);
  try {
    for (const pointer of [0, 1, 4, 65536, 0xffffffff]) {
      throws(() => guest.call("array", pointer), errorCode("invalid_abi"));
    }
    equal(guest.call("array", 8), new Uint32Array());
  } finally {
    guest.dispose();
  }
});
