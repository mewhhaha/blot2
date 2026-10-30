import { strict as assert } from "node:assert";
import { createFrontend } from "./syntax.ts";
import { formatSource } from "./format.ts";

Deno.test("storage types share array literals and preserve reference and range syntax", async () => {
  const source = `const fixed: Array U32 = #[42]
const grow: GrowArray U32 = #[42]
const resize: ResizeArray U32 = #[]
const read = func (item: &U32) => return @storage.load item
const slice = func (items: &[U32]) => return @storage.read items 0
const follow = func (item: ^U32) => return @storage.load item
entry const answer = func () => return do:
  let items: GrowArray U32 = #[42]
  let first: &U32 = &items[0]
  let view: &[U32] = &items[0..1]
  let link: ^U32 = ^items[0]
  break @storage.load first
`;
  const frontend = await createFrontend();
  try {
    frontend.parse(source);
    const formatted = await formatSource(source);
    assert.equal(await formatSource(formatted), formatted);
    assert(formatted.includes("&U32"));
    assert(formatted.includes("&[U32]"));
    assert(formatted.includes("^U32"));
    frontend.parse(formatted);
  } finally {
    frontend.dispose();
  }
});
