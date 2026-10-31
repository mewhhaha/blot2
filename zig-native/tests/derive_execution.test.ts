import { strict as assert } from "node:assert";
import { dataShapes, deriveCodec, deriveEqualityAndDebug, type DeriveSchema } from "../../compiler/derive.ts";
import { decodeText } from "../../compiler/text.ts";
import { deriveFile } from "../../scripts/derive.ts";
import { compileAndRun } from "./compile_helpers.ts";

Deno.test("opt-in derivation executes equality, debug formatting and strict versioned codecs", async () => {
  const declarations = `
type Ticket is data = $Ticket { number: U32, active: Bool } | $Empty
type Box a is data = $Box { values: Array a } | $Missing
type Positive is data = $Positive U32
type Envelope is data = $Envelope { value: Positive }
`;
  const shapes = await dataShapes(declarations);
  assert.deepEqual(shapes.map((shape) => shape.name), [
    "Ticket",
    "Box",
    "Positive",
    "Envelope",
  ]);
  const schemas: DeriveSchema[] = [
    {
      version: 1,
      variants: {
        Ticket: { tag: 8, fields: { number: 20, active: 10 } },
        Empty: { tag: 4, fields: {} },
      },
    },
    {
      version: 7,
      variants: {
        Box: { tag: 2, fields: { values: 90 } },
        Missing: { tag: 3, fields: {} },
      },
    },
    {
      version: 3,
      variants: {
        Envelope: { tag: 12, fields: { value: 5 } },
      },
    },
  ];
  const derived = [shapes[0], shapes[1], shapes[3]].map((shape, index) =>
    deriveEqualityAndDebug(shape) + deriveCodec(shape, schemas[index])
  ).join("\n");
  await compileAndRun(
    `
import * as _derive_eq from "std/equality"
import * as _derive_text from "std/text"
import * as _derive_codec from "std/codec"
${declarations}
const Positive.eq = func left => return func right => return case left, right of
  $Positive a, $Positive b => a == b
impl PositiveEquality : _derive_eq.Eq Positive = {
  const eq = func left => return func right => return Positive.eq left right,
}
impl PositiveFormat : _derive_text.Format Positive = {
  const format = func ($Positive value) => return _derive_text.from_u32 value,
}
impl PositiveCodec : _derive_codec.Codec Positive = {
  const encode = func ($Positive value) => return #[value],
  const decode = func words => return if words.length == 1 and words[0] > 0 then $Some ($Positive words[0]) else $Nothing,
}
${derived}
entry const equal = func () => return
  ($Box { values: #[42, 7] }) ==
  ($Box { values: #[42, 7] })
entry const unequal = func () => return $Ticket { number: 42, active: true } == $Empty
entry const nested_equal = func () => return
  ($Box { values: #[$Ticket { number: 42, active: true }] }) ==
  ($Box { values: #[$Ticket { number: 42, active: true }] })
entry const bool_equal = func () => return true == true
entry const debug = func () => return _derive_text.format ($Box { values: #[42, 7] })
entry const nested_debug = func () => return _derive_text.format ($Box { values: #[$Ticket { number: 42, active: true }] })
entry const encode_record = func () => return _derive_codec.encode ($Ticket { number: 42, active: true })
entry const roundtrip = func () => return do:
  let original = $Box { values: #[42, 7] }
  let encoded = _derive_codec.encode original
  let decoded: Maybe (Box U32) = _derive_codec.Codec.decode encoded
  break case decoded of
    $Some value => if value == original then 1 else 0
    $Nothing => 0
entry const nested_roundtrip = func () => return do:
  let original = $Box { values: #[$Ticket { number: 42, active: true }, $Empty] }
  let encoded = _derive_codec.encode original
  let decoded: Maybe (Box Ticket) = _derive_codec.Codec.decode encoded
  break case decoded of
    $Some value => if value == original then 1 else 0
    $Nothing => 0
entry const decode_record = func (words: Array U32) : U32 => return do:
  let decoded: Maybe Ticket = _derive_codec.Codec.decode words
  break case decoded of
    $Some ($Ticket { number: value, active: flag }) => if flag then value else 0
    _ => 0
entry const decode_envelope = func (words: Array U32) : U32 => return do:
  let decoded: Maybe Envelope = _derive_codec.Codec.decode words
  break case decoded of
    $Some ($Envelope { value: $Positive number }) => number
    _ => 0
`,
    (guest) => {
      assert.equal(guest.call("equal", null), true);
      assert.equal(guest.call("unequal", null), false);
      assert.equal(guest.call("nested_equal", null), true);
      assert.equal(guest.call("bool_equal", null), true);
      assert.equal(guest.call("roundtrip", null), 1);
      assert.equal(guest.call("nested_roundtrip", null), 1);
      assert.equal(
        decodeText(guest.call("debug", null) as Uint32Array),
        "Box(values=[42, 7])",
      );
      assert.equal(
        decodeText(guest.call("nested_debug", null) as Uint32Array),
        "Box(values=[Ticket(number=42, active=true)])",
      );
      const encoded = guest.call("encode_record", null) as Uint32Array;
      assert.deepEqual(encoded, Uint32Array.of(1, 8, 2, 10, 1, 1, 20, 1, 42));
      assert.equal(guest.call("decode_record", encoded), 42);
      assert.equal(
        guest.call("decode_envelope", Uint32Array.of(3, 12, 1, 5, 1, 7)),
        7,
      );
      assert.equal(
        guest.call("decode_envelope", Uint32Array.of(3, 12, 1, 5, 1, 0)),
        0,
      );
      for (
        const bad of [
          Uint32Array.of(2, 8, 2, 10, 1, 1, 20, 1, 42),
          Uint32Array.of(1, 8, 2, 20, 1, 42, 10, 1, 1),
          Uint32Array.of(1, 8, 2, 10, 1, 2, 20, 1, 42),
          Uint32Array.of(1, 8, 2, 10, 1, 1, 20, 2, 42),
          Uint32Array.of(...encoded, 99),
        ]
      ) assert.equal(guest.call("decode_record", bad), 0);
    },
    { stdRoot: new URL("../../std/", import.meta.url).pathname },
  );
});

Deno.test("derivation rejects unsupported fields and unstable schema maps", async () => {
  const [shape] = await dataShapes(
    "type Holder is data = $Holder { callback: U32 -> U32 }\n",
  );
  assert.throws(
    () => deriveEqualityAndDebug(shape),
    /Holder\.Holder\.callback: function field has no structural Eq, Format, || Codec/,
  );
  const [ticket] = await dataShapes(
    "type Ticket is data = $Ticket { first: U32, second: U32 } | $Empty\n",
  );
  assert.throws(
    () =>
      deriveCodec(ticket, {
        version: 1,
        variants: {
          Ticket: { tag: 1, fields: { first: 7, second: 7 } },
          Empty: { tag: 2, fields: {} },
        },
      }),
    /Ticket\.Ticket: duplicate field ID 7/,
  );
});

Deno.test("explicit schema migration preserves field IDs across source reordering", async () => {
  const source = "type Ticket is data = $Ticket { active: Bool, number: U32 } | $Empty\n";
  const [ticket] = await dataShapes(source);
  const schema: DeriveSchema = {
    version: 2,
    variants: {
      Ticket: { tag: 8, fields: { active: 10, number: 20 } },
      Empty: { tag: 4, fields: {} },
    },
  };
  await compileAndRun(
    `
import * as _derive_eq from "std/equality"
import * as _derive_text from "std/text"
import * as _derive_codec from "std/codec"
${source}
${deriveEqualityAndDebug(ticket)}
${deriveCodec(ticket, schema)}
entry const encode_v2 = func () => return _derive_codec.encode ($Ticket { active: true, number: 42 })
entry const decode_v2 = func (words: Array U32) : U32 => return do:
  let decoded: Maybe Ticket = _derive_codec.Codec.decode words
  break case decoded of
    $Some ($Ticket { active: true, number: number }) => number
    _ => 0
// The application owns migration from its published version 1 layout.
entry const migrate_v1 = func (words: Array U32) : Array U32 => return do:
  if words.length != 9 or words[0] != 1 or words[1] != 8 or words[2] != 2:
    return #[]
  if words[3] != 10 or words[4] != 1 or words[5] > 1:
    return #[]
  if words[6] != 20 or words[7] != 1:
    return #[]
  break _derive_codec.encode ($Ticket { active: words[5] == 1, number: words[8] })
`,
    (guest) => {
      const v1 = Uint32Array.of(1, 8, 2, 10, 1, 1, 20, 1, 42);
      const v2 = Uint32Array.of(2, 8, 2, 10, 1, 1, 20, 1, 42);
      assert.deepEqual(guest.call("encode_v2", null), v2);
      assert.equal(guest.call("decode_v2", v1), 0);
      assert.deepEqual(guest.call("migrate_v1", v1), v2);
      assert.equal(guest.call("decode_v2", guest.call("migrate_v1", v1)), 42);
      assert.deepEqual(
        guest.call("migrate_v1", Uint32Array.of(1, 8, 2, 10, 1, 2, 20, 1, 42)),
        new Uint32Array(),
      );
    },
    { stdRoot: new URL("../../std/", import.meta.url).pathname },
  );
});

Deno.test("derive command validates source and generated module before publishing", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-derive-" });
  try {
    const source = `${directory}/model.blot`;
    const output = `${directory}/model_derived.blot`;
    const schema = `${directory}/schema.json`;
    await Deno.writeTextFile(
      source,
      "type Ticket is data = $Ticket { number: U32 } | $Empty\n",
    );
    await Deno.writeTextFile(
      schema,
      JSON.stringify({
        types: {
          Ticket: {
            version: 1,
            variants: {
              Ticket: { tag: 4, fields: { number: 9 } },
              Empty: { tag: 5, fields: {} },
            },
          },
        },
      }),
    );
    const compiler = Deno.args[0] ??
      new URL("../zig-out/bin/blotc", import.meta.url).pathname;
    const stdRoot = new URL("../../std/", import.meta.url).pathname;
    await deriveFile({
      source,
      output,
      schema,
      compiler,
      stdRoot,
      prelude: `${stdRoot}/prelude.blot`,
    });
    const generated = await Deno.readTextFile(output);
    assert.match(generated, /TicketDerivedCodec/);
    assert.match(generated, /TicketDerivedEquality/);
    assert.match(generated, /TicketDerivedFormat/);
    await Deno.writeTextFile(
      schema,
      JSON.stringify({
        types: {
          Ticket: {
            operations: ["codec"],
            version: 1,
            variants: {
              Ticket: { tag: 4, fields: { number: 9 } },
              Empty: { tag: 5, fields: {} },
            },
          },
        },
      }),
    );
    const codecOutput = `${directory}/model_codec.blot`;
    await deriveFile({
      source,
      output: codecOutput,
      schema,
      compiler,
      stdRoot,
      prelude: `${stdRoot}/prelude.blot`,
    });
    const codecOnly = await Deno.readTextFile(codecOutput);
    assert.match(codecOnly, /TicketDerivedCodec/);
    assert.doesNotMatch(codecOnly, /DerivedEquality|DerivedFormat|std\/text/);
    await compileAndRun(
      codecOnly +
        "entry const words = func () => return _derive_codec.encode ($Ticket { number: 42 })\n",
      (guest) =>
        assert.deepEqual(
          guest.call("words", null),
          Uint32Array.of(1, 4, 1, 9, 1, 42),
        ),
      { stdRoot },
    );
    const floatSource = `${directory}/float.blot`;
    const floatOutput = `${directory}/float_derived.blot`;
    await Deno.writeTextFile(
      floatSource,
      "type Coordinate is data = $Coordinate { x: F32 }\n",
    );
    await Deno.writeTextFile(
      schema,
      JSON.stringify({ types: { Coordinate: { operations: ["equality"] } } }),
    );
    await deriveFile({
      source: floatSource,
      output: floatOutput,
      schema,
      compiler,
      stdRoot,
      prelude: `${stdRoot}/prelude.blot`,
    });
    const equalityOnly = await Deno.readTextFile(floatOutput);
    assert.match(equalityOnly, /CoordinateDerivedEquality/);
    assert.doesNotMatch(
      equalityOnly,
      /DerivedFormat|DerivedCodec|std\/text|std\/codec/,
    );
    await compileAndRun(
      equalityOnly +
        "entry const same = func () => return ($Coordinate { x: 1.5 }) == ($Coordinate { x: 1.5 })\n",
      (guest) => assert.equal(guest.call("same", null), true),
      { stdRoot },
    );
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("scalar and product payload derivation preserve generic values", async () => {
  const source = `
type Token is data = $Token U32
type Pair [a, b] is data = $Pair (a, b) | $Missing
`;
  const [token, pair] = await dataShapes(source);
  const generated = deriveEqualityAndDebug(token) + deriveCodec(token, {
    version: 1,
    variants: { Token: { tag: 1, fields: { "0": 6 } } },
  }) + deriveEqualityAndDebug(pair) + deriveCodec(pair, {
    version: 2,
    variants: {
      Pair: { tag: 4, fields: { "0": 10, "1": 20 } },
      Missing: { tag: 5, fields: {} },
    },
  });
  await compileAndRun(
    `
import * as _derive_eq from "std/equality"
import * as _derive_text from "std/text"
import * as _derive_codec from "std/codec"
${source}
${generated}
entry const run = func () => return do:
  let original = $Pair ($Token 42, true)
  let words = _derive_codec.encode original
  let decoded: Maybe (Pair [Token, Bool]) = _derive_codec.Codec.decode words
  break case decoded of
    $Some value => if value == original then 1 else 0
    $Nothing => 0
`,
    (guest) => assert.equal(guest.call("run", null), 1),
    { stdRoot: new URL("../../std/", import.meta.url).pathname },
  );
});

Deno.test("scalar codec emission preserves strict words and rejects malformed framing", async () => {
  const declarations = "type Fixed is data = $Fixed { number: U32, enabled: Bool }\n";
  const [shape] = await dataShapes(declarations);
  const schema = { version: 2, variants: { Fixed: { tag: 9, fields: { number: 20, enabled: 10 } } } };
  const options = {
    scalars: {
      U32: { encode: "unsigned_word", decode: "unsigned_value" },
      Bool: { encode: "boolean_word", decode: "boolean_value" },
    },
  };
  const generated = deriveCodec(shape, schema, options);
  assert.throws(
    () => deriveCodec(shape, schema, { scalars: { U32: { encode: "bad call", decode: "read" } } }),
    /Invalid scalar/,
  );
  await compileAndRun(
    `
import * as _derive_codec from "std/codec"
${declarations}
const unsigned_word = func (value: U32) => return value
const unsigned_value = func (word: U32) => return $Some word
const boolean_word = func value => return if value then 1 else 0
const boolean_value = func (word: U32) => return if word <= 1 then $Some (word == 1) else $Nothing
${generated}
entry const encode = func () => return _derive_codec.encode ($Fixed { number: 4294967295, enabled: true })
entry const decode = func (words: Array U32) => return do:
  let value: Maybe Fixed = _derive_codec.Codec.decode words
  return case value of
    $Some ($Fixed { number, enabled }) => if enabled then number else 0
    $Nothing => 0
`,
    (guest) => {
      const expected = Uint32Array.of(2, 9, 2, 10, 1, 1, 20, 1, 0xffffffff);
      assert.deepEqual(guest.call("encode", null), expected);
      assert.equal(guest.call("decode", expected), 0xffffffff);
      for (let end = 0; end < expected.length; end++) assert.equal(guest.call("decode", expected.slice(0, end)), 0);
      for (const [offset, word] of [[0, 1], [1, 0], [2, 1], [3, 20], [4, 2], [5, 2], [6, 10], [7, 0]]) {
        const malformed = expected.slice();
        malformed[offset] = word;
        assert.equal(guest.call("decode", malformed), 0);
      }
      assert.equal(guest.call("decode", Uint32Array.of(...expected, 0)), 0);
    },
    { stdRoot: new URL("../../std/", import.meta.url).pathname },
  );
});
