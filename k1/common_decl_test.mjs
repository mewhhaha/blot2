import{strict as assert}from'node:assert';import{readFileSync}from'node:fs';
for(let i=0;i<8;i++){const bytes=readFileSync(`common-decl-${i}.wasm`);assert(WebAssembly.validate(bytes));const f=(await WebAssembly.instantiate(bytes)).instance.exports.f;for(const x of i<4?[0,1,98,99,0xfffffffe,0xffffffff]:[0,1]){const e=i<2?(x===0xffffffff?x:x+1):i<4?Number(x<99):i<6?(x?7:42):x;assert.equal(f(0,x)>>>0,e>>>0,`case ${i}, argument ${x}`);}}
console.log('private common declaration signature and boundary execution passed');
