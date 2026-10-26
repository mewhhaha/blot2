import { readFileSync } from "node:fs";
import assert from "node:assert/strict";
const bytes = Buffer.from(readFileSync(process.argv[2], "utf8").trim(), "hex");
const { instance } = await WebAssembly.instantiate(bytes);
const fn = instance.exports.f;
for (const value of [0, 1, 0x7fffffff, 0x80000000, 0xffffffff]) {
  let expected;
  if (process.argv[3] === "and") expected = (value & 0x80000000) >>> 0;
  else if (process.argv[3] === "lt") expected = Number(0x80000000 < value);
  else throw Error("unknown case");
  assert.equal(fn(0, value) >>> 0, expected);
}
console.log("typed scalar driver fixture passed");
