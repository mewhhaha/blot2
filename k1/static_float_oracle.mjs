import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const b=readFileSync('static-f32-oracle.bin');assert.equal(b.length,10000*24);
const v=new DataView(new ArrayBuffer(4));
function number(bits){v.setUint32(0,bits,true);return v.getFloat32(0,true);}
function bits(x){if(Number.isNaN(x))return 0x7fc00000;v.setFloat32(0,Math.fround(x),true);return v.getUint32(0,true);}
for(let off=0;off<b.length;off+=24){
 const a=number(b.readUInt32LE(off)),c=number(b.readUInt32LE(off+4));
 const expect=[bits(a+c),bits(a-c),bits(a*c),bits(a/c)];
 for(let j=0;j<4;j++)assert.equal(b.readUInt32LE(off+8+j*4),expect[j],`row ${off/24} op ${j}`);
}
console.log('private static F32 differential passed');
