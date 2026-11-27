import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { instantiateGuest } from "../../host/guest.ts";

const executable = Deno.args[0] ??
  new URL("../../compiler-goose/build/squidc-goose", import.meta.url).pathname;
const source = `
type Mode is data = $Play | $Edit
type Editor is data = $Editor {mode: Mode, counter: U32, nested: {mode: Mode}}
const set_mode = func (own access) => return do:
  access.editor[0].mode := $Edit
  return access
const toggle = func (own access) => return do:
  access.editor[0].mode := case self of
    $Play => $Edit
    $Edit => $Play
  return access
const increment = func (own access) => return do:
  access.editor[0].counter := self + 1
  return access
const nested = func (own access) => return do:
  access.inner.editor[0].nested.mode := $Edit
  return access
const number = func (mode: Mode): U32 => return case mode of
  $Play => 0
  $Edit => 1
io const run = func (count: U32): Array U32 => return do:
  let state = {editor: #[$Editor {mode: $Play, counter: 0, nested: {mode: $Play}}]}
  state := set_mode state
  for index in 0 .. count:
    state := toggle state
    state := increment state
  let done = nested {inner: state}
  return #[number done.inner.editor[0].mode, done.inner.editor[0].counter, number done.inner.editor[0].nested.mode, done.inner.editor[0].counter]
`;

{
  Deno.test(`generic indexed fields retain invariant element types and source proof equations`, async () => {
    const directory = await Deno.makeTempDir({ prefix: "squid-indexed-field-" });
    const entry = `${directory}/main.sq`;
    await Deno.writeTextFile(entry, source);
    await Deno.writeTextFile(
      `${directory}/tokens.sq`,
      await Deno.readTextFile(
        new URL("../../compiler-goose/tests/fixtures/scoped-opaque/tokens.sq", import.meta.url),
      ),
    );
    const compiler = await createZigProjectCompiler({
      executable,
      entry,
      prelude: new URL("../../std/prelude.sq", import.meta.url).pathname,
    });
    try {
      const result = await compiler.build();
      assert(
        result.success,
        !result.success ? JSON.stringify(result.diagnostics) : "",
      );
      for (const asynchronous of [false, true]) {
        const guest = await instantiateGuest(result.bytes, { asynchronous });
        const call = (name: string, value: number | null) =>
          asynchronous ? guest.callAsync(name, value) : guest.call(name, value);
        try {
          for (const count of [0, 1, 2, 7, 32, 129]) {
            assert.deepEqual(
              await call("run", count),
              Uint32Array.from([count % 2 === 0 ? 1 : 0, count, 1, count]),
            );
          }
        } finally {
          guest.dispose();
        }
      }
      for (
        const body of [
          `const invalid = func access => return do:
  access.editor[0].mode := 7
io const rejected = func (): U32 => return do:
  let editor: Array Editor = #[$Editor {mode: $Play, counter: 0, nested: {mode: $Play}}]
  invalid {editor}
  return 0
`,
          `const invalid = func access => return do:
  access.editor[0].counter := true
io const rejected = func (): U32 => return do:
  let editor: Array Editor = #[$Editor {mode: $Play, counter: 0, nested: {mode: $Play}}]
  invalid {editor}
  return 0
`,
        ]
      ) {
        const rejected = await compiler.build({
          sources: { [entry]: source + body },
        });
        assert(!rejected.success);
        assert.equal(rejected.diagnostics[0].code, "type_mismatch");
        assert.equal("bytes" in rejected, false);
      }
      const privateWrite = await compiler.build({
        sources: {
          [entry]: `import * as token from "./tokens"
${source}
const invalid = func access => return do:
  access.tokens[0].region := 99
io const rejected = func (): U32 => return do:
  let tokens = #[token.make () 1 2 3 4]
  invalid {tokens}
  return 0
`,
        },
      });
      assert(!privateWrite.success);
      assert.equal(privateWrite.diagnostics[0].code, "private_access");
      assert.equal("bytes" in privateWrite, false);
      const recovered = await compiler.build();
      assert(
        recovered.success,
        !recovered.success ? JSON.stringify(recovered.diagnostics) : "",
      );
      assert.deepEqual(recovered.bytes, result.bytes);
    } finally {
      await compiler.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}
