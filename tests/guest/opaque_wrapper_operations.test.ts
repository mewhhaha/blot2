import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { instantiateGuest } from "../../host/guest.ts";

// Compare the exported machine body and signature, independently of private
// helper numbering and nominal custom metadata. These pure programs import no
// functions, so a Wasm function index directly selects its code/type entries.
function exportedFunction(bytes: Uint8Array<ArrayBuffer>, name: string) {
  const module = new WebAssembly.Module(bytes);
  assert.equal(WebAssembly.Module.imports(module).length, 0);
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

{
  for (const record of [false, true]) {
    Deno.test(`opaque ${record ? "generic record" : "reference"} wrappers share their arrays like plain aliases`, async () => {
      for (const opaque of [false, true]) {
        const source = `type Token${record ? " a" : ""}${
          opaque ? " is opaque" : ""
        } = ${record ? "{value: a}" : "Array U32"}
const make: ${record ? "a -> Token a" : "Array U32 -> Token"} = func value => return ${
          opaque ? "$Token " : ""
        }${record ? "{value}" : "value"}
const read: ${record ? "Token a -> a" : "Token -> Array U32"} = func ${
          opaque ? "($Token value)" : "value"
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
        await inspectBuild(source, async (bytes) => {
          const guest = await instantiateGuest(bytes);
          try {
            // The wrapper holds `original` itself, so it reads the write of 0
            // (tasks/LANGUAGE_COHERENCE.md A7).
            assert.equal(guest.call("run", 40), 2);
            assert.equal(guest.call("captured", 40), 2);
          } finally {
            guest.dispose();
          }
        });
      }
    });
  }

  Deno.test(`opaque payload bindings remove only irrefutable pattern control`, async () => {
    await inspectBuild(
      `type Token is opaque = U32
type Pair is opaque = (U32, U32)
entry const guarded = func (value: U32) => return do:
  let $Token 7 = $Token value else:
    break 99
  break 42
entry const pair = func (value: U32) => return do:
  let $Pair (left, right) = $Pair (value, 2)
  break @u32.add left right
`,
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
  Deno.test(`opaque ${type} round trips preserve exported machine operations`, async () => {
    const directory = await Deno.makeTempDir({ prefix: "blot-wrapper-ops-" });
    const entry = `${directory}/main.blot`;
    let plain: ReturnType<typeof exportedFunction> | undefined;
    try {
      for (const opaque of [false, true]) {
        const source = `type Token${opaque ? " is opaque" : ""} = ${type}
const make: ${type} -> Token = func value => return ${opaque ? "$Token " : ""}value
const read: Token -> ${type} = func ${
          opaque ? "($Token value)" : "value"
        } => return value
entry const run = func (value: ${type}) => return read (make value)
`;
        await Deno.writeTextFile(entry, source);
        const compiler = await createZigProjectCompiler({
          executable: Deno.args[0],
          entry,
          prelude: null,
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
