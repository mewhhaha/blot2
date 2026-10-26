import assert from 'node:assert/strict';import {readFileSync} from 'node:fs';
const mod = new WebAssembly.Module(readFileSync('bridge-fixture.wasm'));
for(let held=1; held<=3; held++) for(let cap of [0,12]) {
 const e=new WebAssembly.Instance(mod).exports, u=new Uint32Array(e.memory.buffer), d=new DataView(e.memory.buffer);
 for(let i=0;i<held;i++){let o=4+i*8;u[o]=4096+i*4096;u[o+1]=32;u[o+2]=4096;u[o+3]=0;u[o+4]=7;u[o+5]=1;} u[36]=(1<<held)-1;
 const preserved=Array.from(u.slice(4,4+held*8));
 d.setUint32(32768,0x4b310001,true);d.setUint32(32772,17,true);d.setUint32(32780,16,true);
 d.setUint32(32800,5,true);d.setUint32(32804,1,true);d.setUint32(32808,12,true);d.setUint32(32812,7,true);
 const status=e.invoke(17,48,cap);assert.equal(status,cap?0:2);assert.deepEqual(Array.from(u.slice(4,4+held*8)),preserved);assert.equal(u[36],(1<<held)-1);assert.equal(u[64],0);
}
console.log('existing live-owner restoration tests passed');
