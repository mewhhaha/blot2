import assert from 'node:assert/strict';import {readFileSync} from 'node:fs';
function ule(n){const a=[];do{let x=n&127;n=Math.floor(n/128);a.push(n?x|128:x);}while(n);return a;}
function instrument(input){const b=Uint8Array.from(input);let p=8;const read=()=>{let n=0,k=0;for(;;){const x=b[p++];n+=(x&127)*2**k;if(!(x&128))return n;k+=7;}};while(p<b.length){const start=p,id=b[p++],n=read(),payload=p,end=p+n;if(id===7){assert.equal(b[payload],1);const data=[2,...b.slice(payload+1,end),6,...Buffer.from('memory'),2,0];return Uint8Array.from([...b.slice(0,start),7,...ule(data.length),...data,...b.slice(end)]);}p=end;}throw Error('missing export');}
const b=instrument(readFileSync(process.argv[2]));assert(WebAssembly.validate(b));const e=(await WebAssembly.instantiate(b)).instance.exports,d=new DataView(e.memory.buffer),m=new Uint8Array(e.memory.buffer);
const depths=[0,1,123,124,125,127,128,129,0xfffffffe,0xffffffff],frames=[0,1,1048563,1048564,1048565,1048575,1048576,1048577,0xfffffffe,0xffffffff];
for(const depth of depths)for(const frame of frames)for(const value of [0,1,0xffffffff]){
 d.setUint32(0,depth,true);d.setUint32(4,frame,true);m[8720]=71;m[1057295]=83;m[8191]=91;
 const expected=depth>128||depth+4>128?2n<<32n:frame>1048576||frame+12>1048576?3n<<32n:BigInt(value);
 assert.equal(e.invoke(value),expected,`${depth},${frame},${value}`);assert.equal(d.getUint32(0,true),depth);assert.equal(d.getUint32(4,true),frame);assert.equal(m[8720],71);assert.equal(m[1057295],83);assert.equal(m[8191],91);
}
console.log('independent 300 depth/frame/input combinations match and restore sentinels');
