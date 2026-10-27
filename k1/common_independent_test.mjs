import{strict as assert}from'node:assert';import{readFileSync}from'node:fs';
for(let i=0;i<4;i++){const bytes=readFileSync(`common-independent-${i}.wasm`);assert(WebAssembly.validate(bytes));const f=(await WebAssembly.instantiate(bytes)).instance.exports.f;for(const x of i<2?[0,1]:[0,1,5,6,0xfffffffe,0xffffffff]){const expected=i===0?x:i===1?(x?0xffffffff:9):i===2?Number(x<6):(x===0xffffffff?x:x+1);assert.equal(f(0,x)>>>0,expected>>>0);}}
console.log('independent typed common-Core signature and boundary execution passed');
