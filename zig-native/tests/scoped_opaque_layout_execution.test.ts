import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest, readGuestAbi } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const fixture = new URL("../fixtures/scoped-opaque/", import.meta.url);

async function execute(bytes: Uint8Array<ArrayBuffer>, asynchronous: boolean) {
  assert.equal(readGuestAbi(new WebAssembly.Module(bytes)).version, 8);
  const guest = await instantiateGuest(bytes, { asynchronous });
  const call = (name: string, value: number | Uint32Array<ArrayBuffer>) =>
    asynchronous ? guest.callAsync(name, value) : guest.call(name, value);
  try {
    for (let iteration = 0; iteration < 8; iteration++) {
      for (
        const values of [
          [1, 12, 13, 14, 15],
          [1, 0, 0xFFFFFFFF, 0x80000000, 0xFFFFFFFF],
          [0, 12, 13, 14, 15],
          [],
        ]
      ) {
        const actual = await call("roundtrip", Uint32Array.from(values));
        assert(actual instanceof Uint32Array);
        assert.deepEqual(
          [...actual],
          values.length === 5 && values[0] !== 0
            ? values.slice(1)
            : [0, 0, 0, 0],
        );
      }
      for (const value of [0, -0, 2.5, -7.25, Infinity, NaN]) {
        assert(Object.is(await call("floating", value), Math.fround(value)));
      }
      for (const value of [0, 42, 0x80000000, 0xFFFFFFFF]) {
        assert.equal(await call("records", value), (value * 2) >>> 0);
        assert.equal(await call("owned", value), value);
      }
    }
  } finally {
    guest.dispose();
  }
}

for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`scoped opaque variant layouts preserve private identity and representation edits (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({ prefix: "blot-scoped-opaque-" });
    const entry = `${directory}/main.blot`;
    const tokens = `${directory}/tokens.blot`;
    const original = await Deno.readTextFile(new URL("tokens.blot", fixture));
    const main = await Deno.readTextFile(new URL("main.blot", fixture));
    const changed = original.replace(
      "{ kind: kind, region:",
      "{ padding: U32, kind: kind, region:",
    ).replace("$Handle {kind, region", "$Handle {padding: 91, kind, region");
    assert.notEqual(changed, original);
    await Deno.writeTextFile(entry, main);
    await Deno.writeTextFile(tokens, original);
    await Deno.writeTextFile(
      `${directory}/facade.blot`,
      await Deno.readTextFile(new URL("facade.blot", fixture)),
    );
    const options = {
      executable,
      entry,
      prelude: null,
      codegenTier,
      cacheDirectory: false as const,
    };
    const compiler = await createZigProjectCompiler(options);
    try {
      let successful: Uint8Array<ArrayBuffer> | undefined;
      for (const source of [original, changed, original]) {
        const sources = { [tokens]: source };
        const result = await compiler.build({ sources });
        assert(result.success, JSON.stringify(result));
        const fresh = await createZigProjectCompiler(options);
        try {
          const expected = await fresh.build({ sources });
          assert(expected.success, JSON.stringify(expected));
          assert.deepEqual(result.bytes, expected.bytes);
        } finally {
          await fresh.dispose();
        }
        for (const asynchronous of [false, true]) {
          await execute(result.bytes, asynchronous);
        }
        successful = result.bytes;
      }

      const rejections = [
        [
          "entry const invalid = func () => return (token.make () 1 2 3 4).region\n",
          "private_access",
        ],
        [
          "entry const invalid = func () => return $token.Handle {kind: (), region: 1, origin: 2, slot: 3, generation: 4}\n",
          "private_access",
        ],
        ...["View U32", "Unit -> U32", "unique U32", "a"].map((argument) => [
          `entry const invalid = func () => return do:
  let absent: Maybe (token.Handle (${argument})) = $Nothing
  return case absent of
    $Some value => 1
    $Nothing => 0
`,
          "storage_unsupported",
        ]),
        [
          `const leak = func () => return do:
  let wrapped = token.wrap #[42]
  let $Some kept = if true then $Some wrapped else $Nothing else:
    return @panic "impossible"
  let values = token.unwrap kept
  return &values[0..1]
entry const invalid = func () => return (leak ())[0]
`,
          "storage_escape",
        ],
      ];
      for (const [body, code] of rejections) {
        const rejected = await compiler.build({
          sources: { [entry]: `${main}\n${body}` },
        });
        assert(!rejected.success, code);
        assert.equal(rejected.diagnostics[0].code, code);
        assert.equal("bytes" in rejected, false);
      }
      const recovered = await compiler.build();
      assert(recovered.success, JSON.stringify(recovered));
      assert.deepEqual(recovered.bytes, successful);
      await execute(recovered.bytes, false);
    } finally {
      await compiler.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}
