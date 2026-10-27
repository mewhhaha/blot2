import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
for (const [name,id,size,flags,values] of [
 ['unit',1,0,7,[0]],['u32',2,4,3,[0,1,0xffffffff]],
 ['f32',3,4,3,[0,0x80000000,0x3f800000,0x7fc12345]],['bool',4,4,3,[0,1]]]) {
 const image=await readFile(`abi-${name}.wasm`),mod=new WebAssembly.Module(image);
 assert.deepEqual(WebAssembly.Module.imports(mod),[]);
 const instance=new WebAssembly.Instance(mod),m=new Uint8Array(instance.exports.memory.buffer),d=new DataView(m.buffer);
 for(const bits of values){m.fill(0xaa,2044,2056);d.setUint32(256,size,true);d.setUint32(260,size?4:1,true);d.setUint32(264,flags,true);d.setUint32(268,id,true);d.setUint32(1024,bits,true);instance.exports.identity(0,size?2048:0,256,size?1024:0);if(size)assert.equal(d.getUint32(2048,true),bits);assert.equal(d.getUint32(2044,true),0xaaaaaaaa);assert.equal(d.getUint32(2048+size,true),0xaaaaaaaa);}
}
console.log('fixed generic target copies exact Unit/U32/F32/Bool representations');
