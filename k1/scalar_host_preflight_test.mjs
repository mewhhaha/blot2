import assert from 'node:assert/strict';import {readFileSync} from 'node:fs';
const b=Uint8Array.from(readFileSync('scalar-host-0.wasm'));let at=8,code;
function leb(){let n=0,k=0;for(;;){let x=b[at++];n+=(x&127)*2**k;if(!(x&128))return n;k+=7;}}
while(at<b.length){let id=b[at++],n=leb(),end=at+n;if(id===10){code=at;break;}at=end;}
assert(code!==undefined);at=code;assert.equal(leb(),2);let size=leb(),body=at;assert(size>2);assert.equal(b[body],0);assert.equal(b[body+1],0x20);b[body+1]=0;assert(WebAssembly.validate(b));
const {instance}=await WebAssembly.instantiate(b);const invoke=instance.exports.invoke;
assert.equal(invoke(2,2),1n<<32n);assert.equal(invoke(1,0),2n<<32n);assert.throws(()=>invoke(1,2),WebAssembly.RuntimeError);
console.log('test-only trap in source proves invalid Bool and failed depth preflight do not call source');
