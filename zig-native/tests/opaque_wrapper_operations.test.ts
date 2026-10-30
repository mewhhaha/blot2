import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";
import { observeGuestAllocations } from "../../scripts/bench/guest_heap_observer.ts";

// Exported entry adapters can have identical bytes while calling different
// private implementations. Compare all function signatures and code too.
function functionSections(bytes: Uint8Array<ArrayBuffer>) {
  let cursor = 8;
  const parts: Uint8Array<ArrayBuffer>[] = [];
  while (cursor < bytes.length) {
    const start = cursor, section = bytes[cursor++];
    let length = 0, shift = 0, byte: number;
    do {
      assert(cursor < bytes.length && shift < 35);
      byte = bytes[cursor++];
      length += (byte & 127) * 2 ** shift;
      shift += 7;
    } while (byte & 128);
    cursor += length;
    assert(cursor <= bytes.length);
    if (section === 1 || section === 3 || section === 10) {
      parts.push(bytes.slice(start, cursor));
    }
  }
  assert.equal(cursor, bytes.length);
  return parts;
}

// Compare the exported machine body and signature, independently of private
// helper numbering and nominal custom metadata. These pure programs import no
// functions, so a Wasm function index directly selects its code/type entries.
function exportedFunction(bytes: Uint8Array<ArrayBuffer>, name: string) {
  const module = new WebAssembly.Module(bytes);
  assert.equal(WebAssembly.Module.imports(module).length, 0);
  assert(
    !WebAssembly.Module.exports(module).some((entry) =>
      entry.kind === "memory"
    ),
  );
  let at = 8;
  const read = () => {
    let value = 0, shift = 0, byte: number;
    do {
      assert(at < bytes.length && shift < 35);
      byte = bytes[at++];
      value += (byte & 127) * 2 ** shift;
      shift += 7;
    } while (byte & 128);
    return value;
  };
  const signatures: Uint8Array<ArrayBuffer>[] = [];
  const functions: number[] = [];
  const bodies: Uint8Array<ArrayBuffer>[] = [];
  let exported: number | undefined;
  while (at < bytes.length) {
    const section = bytes[at++], length = read(), end = at + length;
    assert(end <= bytes.length);
    assert.notEqual(
      section,
      5,
      "Scalar wrappers must not declare linear memory",
    );
    if (section === 1) {
      const count = read();
      for (let i = 0; i < count; i++) {
        const start = at;
        assert.equal(bytes[at++], 0x60);
        const parameters = read();
        at += parameters;
        const results = read();
        at += results;
        signatures.push(bytes.slice(start, at));
      }
    } else if (section === 3) {
      const count = read();
      for (let i = 0; i < count; i++) functions.push(read());
    } else if (section === 7) {
      const count = read();
      for (let i = 0; i < count; i++) {
        const length = read();
        const spelling = new TextDecoder().decode(bytes.slice(at, at + length));
        at += length;
        const kind = bytes[at++], index = read();
        if (kind === 0 && spelling === name) exported = index;
      }
    } else if (section === 10) {
      const count = read();
      for (let i = 0; i < count; i++) {
        const length = read();
        bodies.push(bytes.slice(at, at + length));
        at += length;
      }
    }
    assert(at <= end);
    at = end;
  }
  assert(exported !== undefined);
  assert(exported < functions.length && exported < bodies.length);
  return { signature: signatures[functions[exported]], body: bodies[exported] };
}

async function inspectBuild(
  source: string,
  codegenTier: "development" | "optimized",
  inspect: (bytes: Uint8Array<ArrayBuffer>) => void | Promise<void>,
) {
  const directory = await Deno.makeTempDir({ prefix: "blot-wrapper-heap-" });
  const entry = `${directory}/main.blot`;
  try {
    await Deno.writeTextFile(entry, source);
    const compiler = await createZigProjectCompiler({
      executable: Deno.args[0],
      entry,
      prelude: null,
      cacheDirectory: false,
      codegenTier,
    });
    try {
      const built = await compiler.build();
      assert(built.success, JSON.stringify(built));
      await inspect(built.bytes);
    } finally {
      await compiler.dispose();
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
}

for (const codegenTier of ["development", "optimized"] as const) {
  for (const record of [false, true]) {
    Deno.test(`opaque ${record ? "generic record" : "reference"} wrappers preserve allocation and ownership traffic (${codegenTier})`, async () => {
      let plain: ReturnType<typeof observeGuestAllocations> | undefined;
      let plainFunctions: ReturnType<typeof functionSections> | undefined;
      for (const opaque of [false, true]) {
        const source = `${opaque ? "opaque " : ""}type Token${
          record ? " a" : ""
        } = ${record ? "{value: a}" : "Array U32"}
const make: ${record ? "a -> Token a" : "Array U32 -> Token"} = func value => return ${
          opaque ? "#Token " : ""
        }${record ? "{value}" : "value"}
const read: ${record ? "Token a -> a" : "Token -> Array U32"} = func ${
          opaque ? "(#Token value)" : "value"
        } => return ${record ? "value.value" : "value"}
const capture = func value => return do:
  let saved = make value
  break func () => return read saved
entry const run = func (value: U32) => return do:
  let original = #[value, 7]
  let alias = read (make original)
  original[0] := 0
  break @u32.add alias[0] 2
entry const captured = func (value: U32) => return do:
  let original = #[value, 7]
  let saved = capture original
  original[0] := 0
  break @u32.add (saved ())[0] 2
`;
        await inspectBuild(source, codegenTier, async (bytes) => {
          const functions = functionSections(bytes);
          if (opaque) assert.deepEqual(functions, plainFunctions);
          else plainFunctions = functions;
          const guest = await instantiateGuest(bytes);
          try {
            assert.equal(guest.call("run", 40), 42);
            assert.equal(guest.call("captured", 40), 42);
          } finally {
            guest.dispose();
          }
          const traffic = observeGuestAllocations(bytes, [
            ["run", 40, 42],
            ["captured", 40, 42],
          ]);
          assert(traffic.rounded_allocation_bytes > 0);
          if (opaque) assert.deepEqual(traffic, plain);
          else plain = traffic;
        });
      }
    });
  }

  Deno.test(`opaque payload bindings remove only irrefutable pattern control (${codegenTier})`, async () => {
    await inspectBuild(
      `opaque type Token = U32
opaque type Pair = (U32, U32)
entry const guarded = func (value: U32) => return do:
  let #Token 7 = #Token value else:
    break 99
  break 42
entry const pair = func (value: U32) => return do:
  let #Pair (left, right) = #Pair (value, 2)
  break @u32.add left right
`,
      codegenTier,
      async (bytes) => {
        const guest = await instantiateGuest(bytes);
        try {
          assert.equal(guest.call("guarded", 7), 42);
          assert.equal(guest.call("guarded", 8), 99);
          assert.equal(guest.call("guarded", 0xffffffff), 99);
          assert.equal(guest.call("pair", 40), 42);
        } finally {
          guest.dispose();
        }
      },
    );
  });
}

for (const type of ["U32", "F32"]) {
  for (const codegenTier of ["development", "optimized"] as const) {
    Deno.test(`opaque ${type} round trips preserve exported machine operations (${codegenTier})`, async () => {
      const directory = await Deno.makeTempDir({ prefix: "blot-wrapper-ops-" });
      const entry = `${directory}/main.blot`;
      let plain: ReturnType<typeof exportedFunction> | undefined;
      try {
        for (const opaque of [false, true]) {
          const source = `${opaque ? "opaque " : ""}type Token = ${type}
const make: ${type} -> Token = func value => return ${opaque ? "#Token " : ""}value
const read: Token -> ${type} = func ${
            opaque ? "(#Token value)" : "value"
          } => return value
entry const run = func (value: ${type}) => return read (make value)
`;
          await Deno.writeTextFile(entry, source);
          const compiler = await createZigProjectCompiler({
            executable: Deno.args[0],
            entry,
            prelude: null,
            cacheDirectory: false,
            codegenTier,
          });
          try {
            const built = await compiler.build();
            assert(built.success, JSON.stringify(built));
            const guest = await instantiateGuest(built.bytes);
            try {
              for (
                const value of type === "F32"
                  ? [-0, NaN, Infinity, -Infinity, 42.5]
                  : [0, 42, 0xffffffff]
              ) {
                assert.equal(guest.call("run", value), value);
              }
              if (type === "F32") {
                const word = new DataView(new ArrayBuffer(4));
                for (
                  const bits of [
                    0,
                    0x80000000,
                    0x7f800000,
                    0xff800000,
                    0x7fc00001,
                    0xffc12345,
                  ]
                ) {
                  word.setUint32(0, bits, true);
                  const value = word.getFloat32(0, true);
                  word.setFloat32(0, value, true);
                  assert.equal(
                    word.getUint32(0, true),
                    bits,
                    "Host bit control",
                  );
                  word.setFloat32(0, guest.call("run", value) as number, true);
                  assert.equal(word.getUint32(0, true), bits);
                }
              }
              const machine = exportedFunction(built.bytes, "run");
              if (opaque) assert.deepEqual(machine, plain);
              else plain = machine;
            } finally {
              guest.dispose();
            }
          } finally {
            await compiler.dispose();
          }
        }
      } finally {
        await Deno.remove(directory, { recursive: true });
      }
    });
  }
}
