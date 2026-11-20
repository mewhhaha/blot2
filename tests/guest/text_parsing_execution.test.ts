import { strict as assert } from "node:assert";
import { encodeText } from "../../host/text.ts";
import { compileAndRun } from "./compile_helpers.ts";

Deno.test("text parses unsigned decimals and iterates borrowed words and lines", async () => {
  await compileAndRun(
    `
import * as text from "std/text"

entry func parse (source: Text): Array U32 => return case text.parse_u32 source of
  $Some value => #[value]
  $Nothing => #[]

entry func whitespace (value: U32): Bool => return text.is_whitespace value

func encode_tokens tokens: Array U32 => do:
  let result: GrowArray U32 = #[]
  for token in tokens:
    result.push token.length
    for ch in token:
      result.push ch
  return @storage.freeze result

entry func words (source: Text): Array U32 => return
  encode_tokens (text.split_whitespace source)

entry func lines (source: Text): Array U32 => return
  encode_tokens (text.lines source)

entry func numbers (source: Text): Array U32 => do:
  let result: GrowArray U32 = #[]
  for token in text.split_whitespace source:
    let $Some value = text.parse_u32 token else:
      return #[]
    result.push value
  return @storage.freeze result

entry func independent (source: Text): Array U32 => do:
  let cursor = text.split_whitespace source
  let $Some (first, rest) = cursor.next else:
    return #[]
  let $Some (second, _) = rest.next else:
    return #[]
  let $Some (again, _) = cursor.next else:
    return #[]
  return #[first[0], second[0], again[0]]
`,
    (guest) => {
      const run = (entry: string, value: string): number[] =>
        Array.from(guest.call(entry, encodeText(value)) as Uint32Array);

      for (
        const [value, expected] of [
          ["0", [0]],
          ["00042", [42]],
          ["4294967295", [4294967295]],
          ["0".repeat(128) + "4294967295", [4294967295]],
          ["", []],
          ["4294967296", []],
          ["99999999999999999999", []],
          ["-1", []],
          ["+1", []],
          [" 1", []],
          ["1\t", []],
          ["1a2", []],
          ["1.0", []],
          ["١٢٣", []],
          ["４２", []],
        ] as const
      ) {
        assert.deepEqual(run("parse", value), expected, value);
      }

      const spaces = [
        9, 10, 11, 12, 13, 0x20, 0x85, 0xA0, 0x1680, 0x2000, 0x2001,
        0x2002, 0x2003, 0x2004, 0x2005, 0x2006, 0x2007, 0x2008, 0x2009,
        0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000,
      ];
      for (const cp of spaces) {
        assert.equal(guest.call("whitespace", cp), true, cp.toString(16));
      }
      for (
        const cp of [
          0, 8, 14, 0x1F, 0x21, 0x84, 0x86, 0x9F, 0xA1, 0x180E,
          0x1FFF, 0x200B, 0x2027, 0x202A, 0x2060, 0xFEFF, 0x10FFFF,
        ]
      ) {
        assert.equal(guest.call("whitespace", cp), false, cp.toString(16));
      }
      const tokens = (...parts: string[]) =>
        parts.flatMap((part) => [encodeText(part).length, ...encodeText(part)]);
      const spaced = String.fromCodePoint(...spaces);
      assert.deepEqual(run("words", ""), []);
      assert.deepEqual(run("words", spaced), []);
      assert.deepEqual(run("words", "  hi\t世界🙂  "), tokens("hi", "世界🙂"));
      assert.deepEqual(run("words", `x${spaced}y`), tokens("x", "y"));
      assert.deepEqual(run("words", "a\u200Bb"), tokens("a\u200Bb"));
      assert.deepEqual(run("words", "a" + " ".repeat(1024) + "b"), tokens("a", "b"));
      assert.deepEqual(run("independent", "x y"), [120, 121, 120]);
      assert.deepEqual(run("numbers", " 1\t0\r\n4294967295 "), [1, 0, 4294967295]);
      assert.deepEqual(run("numbers", "1 invalid 2"), []);
      assert.deepEqual(run("numbers", "1 4294967296"), []);

      for (
        const [source, expected] of [
          ["", []],
          ["\n", [""]],
          ["\r\n", [""]],
          ["\n\n", ["", ""]],
          ["x", ["x"]],
          ["x\n", ["x"]],
          ["x\r\n", ["x"]],
          ["x\n\n", ["x", ""]],
          ["x\r\ny\n\n世界🙂", ["x", "y", "", "世界🙂"]],
          ["x\r", ["x\r"]],
          ["x\u2028y", ["x\u2028y"]],
        ] as const
      ) {
        assert.deepEqual(run("lines", source), tokens(...expected), source);
      }
    },
    { stdRoot: new URL("../../std/", import.meta.url).pathname },
  );
});
