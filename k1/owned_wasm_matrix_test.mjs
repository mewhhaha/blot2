import assert from 'node:assert/strict';import{readFileSync}from'node:fs';
let count=0;for(let consumer of [0,1,2,3])for(let flag of [0,1])for(let n of [0,1,3840,3841,4294962944,4294962945,4294967295])for(let value of [0,1,4294967295])for(let abort of [false,true]){
 const b=readFileSync(`owned-matrix-${count++}.wasm`);assert(WebAssembly.validate(b));const mod=new WebAssembly.Module(b);assert.deepEqual(WebAssembly.Module.imports(mod),[]);assert.deepEqual(WebAssembly.Module.exports(mod).map(x=>x.name),['invoke']);const e=new WebAssembly.Instance(mod).exports;
 const want=n>3840?(3n<<32n)|BigInt(n>4294962944?1:3):abort?2n<<32n:BigInt(value);
 assert.equal(e.invoke(),want);assert.equal(e.invoke(),want);
}console.log(`actual private Wasm owned lifecycle/status parity across ${count} cases`);
