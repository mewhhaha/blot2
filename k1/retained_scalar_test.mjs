import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
for (const [file, expected] of [["retained_scalar_before.wasm", x => x], ["retained_scalar_after.wasm", () => 7]]) {
    const bytes = await readFile(file);
    assert.equal(WebAssembly.validate(bytes), true);
    const module = await WebAssembly.compile(bytes);
    assert.deepEqual(WebAssembly.Module.imports(module), []);
    const answer = new WebAssembly.Instance(module).exports.answer;
    for (const x of [0, 1, 7, 42, 0x7fffffff, 0x80000000, 0xffffffff]) {
        assert.equal(answer(0, x) >>> 0, expected(x) >>> 0);
    }
}
console.log("private retained scalar Wasm revision witnesses passed");
