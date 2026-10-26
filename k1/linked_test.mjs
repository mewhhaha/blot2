import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
for(const [name,expected] of [['linked_before.wasm', x=>x], ['linked_after.wasm', ()=>7],
  ['linked_mask.wasm', x=>x&255], ['linked_max.wasm', ()=>0xffffffff]]) {
 const bytes=readFileSync(name);assert(WebAssembly.validate(bytes));
 const module=await WebAssembly.compile(bytes);assert.deepEqual(WebAssembly.Module.imports(module),[]);
 assert.deepEqual(WebAssembly.Module.exports(module),[{name:'caller',kind:'function'}]);
 const f=new WebAssembly.Instance(module).exports.caller;
 for(const x of [0,1,42,0x7fffffff,0x80000000,0xffffffff]) assert.equal(f(0,x)>>>0,expected(x)>>>0);
}
console.log('private imported scalar call Wasm execution passed');
