import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
const bytes = await readFile("closure_fixture.wasm");
assert.equal(WebAssembly.validate(bytes), true);
const module = await WebAssembly.compile(bytes);
assert.deepEqual(WebAssembly.Module.imports(module), []);
const instance = new WebAssembly.Instance(module);
for (const cap of [0,1,3]) assert.equal(instance.exports.run(0xffffffff, 0x12345678, cap), -1n);
for (const capture of [0,1,0x80000000,0xffffffff,0xdeadbeef]) {
  for (const arg of [0,1,0x12345678,0x80000000,0xffffffff]) {
    assert.equal(instance.exports.run(capture,arg,4), BigInt((capture & arg) >>> 0));
    assert.equal(instance.exports.run(capture,arg,0xffffffff), BigInt((capture & arg) >>> 0));
  }
}
// Patch only a scratch copy to expose its fixed memory. This debug module is
// deliberately outside the original structural allowlist.
let pos=8, chunks=[bytes.subarray(0,8)];
while(pos<bytes.length){ const id=bytes[pos++], n=bytes[pos++]; const part=bytes.subarray(pos,pos+n); pos+=n;
  if(id===7){const replacement=Buffer.from([2,3,114,117,110,0,1,6,109,101,109,111,114,121,2,0]);chunks.push(Buffer.from([7,replacement.length]),replacement)}
  else chunks.push(Buffer.from([id,n]),part);
}
const debug=new WebAssembly.Instance(new WebAssembly.Module(Buffer.concat(chunks)));
const memory=new Uint8Array(debug.exports.memory.buffer);memory.set([11,22,33,44],1024);
assert.equal(debug.exports.run(0xffffffff,1,3),-1n);
assert.deepEqual(Array.from(memory.subarray(1024,1028)),[11,22,33,44]);
assert.equal(debug.exports.run(0x12345678,0xffffffff,4),0x12345678n);
assert.deepEqual(Array.from(memory.subarray(1024,1028)),[0x78,0x56,0x34,0x12]);
assert.equal(debug.exports.memory.buffer.byteLength,65536);
console.log("private captured closure and indirect call executed");
