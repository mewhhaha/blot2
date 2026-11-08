import { strict as assert } from "node:assert";
import { deriveSource } from "../../host/derive_cli.ts";
import { createFrontend } from "../../host/syntax.ts";

Deno.test("derive renderer emits named module functions and value implementation members", async () => {
  const source = await deriveSource("type Box a is data = $Box {value: a}\n", {
    types: {
      Box: { version: 1, variants: { Box: { tag: 0, fields: { value: 0 } } } },
    },
  });
  assert.ok(source.includes("func Box.eq left -> right =>"));
  assert.ok(
    source.includes(
      "func _derive_box_encode (value: (Box a)): Array U32 where",
    ),
  );
  assert.ok(source.includes("const eq = func left"));
  const frontend = await createFrontend();
  try {
    frontend.parse(source);
  } finally {
    frontend.dispose();
  }
});
