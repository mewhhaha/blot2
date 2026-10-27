import assert from 'node:assert/strict';import {readFileSync} from 'node:fs';
for(let i=0;i<2;i++){
 let bytes=readFileSync(`scalar-host-${i}.wasm`);assert(WebAssembly.validate(bytes));let {instance}=await WebAssembly.instantiate(bytes);assert.deepEqual(Object.keys(instance.exports),['invoke']);let f=instance.exports.invoke;
 for(let depth of [2,3,128]){assert.equal(f(0,depth),i===0?42n:0n);assert.equal(f(1,depth),i===0?11n:4294967295n);}
 for(let invalid of [2,3,127,0xffffffff])for(let depth of [0,2,129])assert.equal(f(invalid,depth),1n<<32n);
 for(let depth of [0,1,129,0xffffffff])for(let value of [0,1])assert.equal(f(value,depth),2n<<32n);
}
console.log('private Bool host policy, invalid-input priority and depth preflight passed');
