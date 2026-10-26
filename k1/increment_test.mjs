import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
const wasm=await readFile("increment_fixture.wasm");
assert.equal(WebAssembly.validate(wasm),true);
const module=await WebAssembly.compile(wasm);
assert.deepEqual(WebAssembly.Module.imports(module),[]);
const fn=new WebAssembly.Instance(module).exports.run;
for(const x of [0,1,2,0x7fffffff,0x80000000,0xfffffffd,0xfffffffe,0xffffffff]) {
  assert.equal(fn(0,x)>>>0, x===0xffffffff ? x : x+1);
}
let state=0x123489ab;
for(let i=0;i<100000;i++){
  state^=state<<13;state^=state>>>17;state^=state<<5;const x=state>>>0;
  assert.equal(fn(0,x)>>>0, x===0xffffffff ? x : x+1);
}
console.log("guarded successor Wasm execution passed");
