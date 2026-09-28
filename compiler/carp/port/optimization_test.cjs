#!/usr/bin/env node
/** Compare the selected representation rewrite with the independently retained
 * pinned semantic definition. Includes malformed UTF-16 as a stronger property
 * than source identifiers require; nothing normalizes text or truncates at NUL. */
"use strict";
const fs = require("node:fs"), crypto = require("node:crypto"), assert = require("node:assert/strict");
const { parse } = require("./vendor/acorn.cjs");
const lock = require("./reference.lock.json"), loops = require("./loops.cjs");
if (process.argv.length !== 3) throw Error("usage: node optimization_test.cjs reference.mjs");
const source = fs.readFileSync(process.argv[2], "utf8");
assert.equal(crypto.createHash("sha256").update(source).digest("hex"), lock.semanticSha256);
const ast = parse(source, { ecmaVersion: 2022, sourceType: "module" });
const needed = new Set(["$$$$047model$name_equal$", "$$$$047model$name_equal_walk$", "$$$$047model$name_equal_result$", "$Char$is_eq$"]);
const definitions = ast.body.filter(n => n.type === "FunctionDeclaration" && needed.has(n.id.name));
assert.equal(definitions.length, needed.size);
const reference = new Function(definitions.map(n => source.slice(n.start, n.end)).join("\n") + "\nreturn $$$$047model$name_equal$;")();
const replacement = new Function(loops["$$$$047model$name_equal$"] + "\nreturn $$$$047model$name_equal$;")();
let seed = 0x63707274, checks = 0;
function random() { seed ^= seed << 13; seed ^= seed >>> 17; seed ^= seed << 5; return seed >>> 0; }
function verify(a, b) { assert.equal(replacement(a, b), reference(a, b)); checks++; }
const values = ["", "a", "abc", "ab", "a\0b", "a\0c", "é", "e\u0301", "雪🙂", "雪😀", "\ud800", "\udfff", "\ud800\udfff", "\udfff\ud800", "a".repeat(1000)];
for (const a of values) for (const b of values) verify(a, b);
for (let i = 0; i < 3000; i++) {
  let a = "", b = "";
  const n = random() % 80;
  for (let k = 0; k < n; k++) a += String.fromCharCode(random() & 65535);
  const m = random() % 80;
  for (let k = 0; k < m; k++) b += String.fromCharCode(random() & 65535);
  verify(a, a); verify(a, b); verify(a, a + "\0"); verify(a, a.slice(0, -1));
  verify(a + "🙂", a + "😀");
}
console.log(`Name-equality rewrite: ${checks} independently compared cases passed.`);
