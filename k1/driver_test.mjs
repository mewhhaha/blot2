// Decode and execute the private fixture; not a qualified K1 artifact.
import { strict as assert } from "node:assert";
import { readFileSync } from "node:fs";
const hex = readFileSync(process.argv[2], "utf8");
assert.match(hex, /^(?:[0-9a-f]{2})+\n$/);
const { instance } = await WebAssembly.instantiate(Buffer.from(hex.trim(), "hex"));
const name = process.argv[3] ?? "id";
const expected = Number(process.argv[4] ?? 42) >>> 0;
assert.equal(instance.exports[name](0, 42) >>> 0, expected);
console.log("private driver fixture passed");
