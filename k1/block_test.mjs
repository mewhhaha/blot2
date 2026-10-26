// Execute a private fixture; it is not a qualified K1 artifact.
import { strict as assert } from "node:assert";
import { readFileSync } from "node:fs";
const bytes = Buffer.from(readFileSync(process.argv[2], "utf8").trim(), "hex");
const { instance } = await WebAssembly.instantiate(bytes);
const expected = process.argv[3];
if (expected === "identity") {
  assert.equal(instance.exports.id(0, 0), 0);
  assert.equal(instance.exports.id(0, -1), -1);
} else {
  assert.equal(instance.exports.id(0, 0), 42);
  assert.equal(instance.exports.id(0, -1), 42);
}
