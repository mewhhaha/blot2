import {strict as assert} from 'node:assert';import {readFileSync} from 'node:fs';
for(let i=0;i<3;i++){const {instance}=await WebAssembly.instantiate(readFileSync(`joined_target_${i}.wasm`));for(const x of [0,1,2,6,7,100,0xffffffff]){const y=(x+3)>>>0;let expected=i===0?(x===0xffffffff?x:x+1):i===1?((x<2&&y<=1)?y:Math.imul(y,7)>>>0):(x<7?(x&15)>>>0:(x-1)>>>0);assert.equal(instance.exports.f(0,x)>>>0,expected>>>0);}}
console.log('decoded scalar targets execute as source expects');
for(let i=0;i<6;i++){const {instance}=await WebAssembly.instantiate(readFileSync(`jt_loop_${i}.wasm`));for(const x of [0,1,2,7,40]){const expected=i===0?(x?x-1:17):i===1?(x?x:17):i===2?x:i===3?(x?1:7):i===4?(x?x-1:4):(x?x-1:9);assert.equal(instance.exports.f(0,x)>>>0,expected);}}
console.log('decoded nested-loop targets execute as source expects');
for(let i=0;i<3;i++){const {instance}=await WebAssembly.instantiate(readFileSync(`jt_mixed_${i}.wasm`));for(const x of [0,1,2,7,30]){const expected=i===0?x*(x-1)/2:i===1?x*(x-1):x;assert.equal(instance.exports.f(0,x)>>>0,expected>>>0);}}
console.log('decoded mixed-loop targets execute as source expects');
const mutant=readFileSync('joined_valid_mutation.wasm');assert(WebAssembly.validate(mutant));const altered=await WebAssembly.instantiate(mutant);assert.equal(altered.instance.exports.f(0,7)>>>0,6);console.log('valid Wasm semantic mutation is rejected by the independent checker');
