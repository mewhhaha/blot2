// Decode real emitted workers, and inject test-only traps after each argument
// evaluation. These fixtures still depend on trusted owner/loan preconditions.
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
function read(b,p) { let x=0,s=0,q;do {assert(p.i<b.length);q=b[p.i++];x+=(q&127)*2**s;s+=7;assert(s<=35);}while(q&128);return x; }
function leb(n) {const a=[];do {let x=n%128;n=Math.floor(n/128);a.push(x|(n?128:0));}while(n);return Buffer.from(a);}
const simple=new Set([0x00,0x05,0x0b,0x0f,0x45,0x46,0x47,0x49,0x4b,0x4f,0x6a,0x6b,0x6c,0x71,0x72,0x73,0x74,0x76,0x92,0x94]);
function inspectAndInject(bytes,worker,xlocal,ylocal,which) {
 let p={i:8},codeStart=-1,codeEnd=-1,codePayload=-1;
 while(p.i<bytes.length) {const start=p.i,id=bytes[p.i++],len=read(bytes,p),end=p.i+len;assert(end<=bytes.length);if(id===10){codeStart=start;codePayload=p.i;codeEnd=end;break;}p.i=end;}
 assert(codeStart>=0);p.i=codePayload;const count=read(bytes,p),prefix=p.i;let bodyStart,bodyEnd,bodyLenStart;
 for(let i=0;i<count;i++){const start=p.i,n=read(bytes,p),end=p.i+n;assert(end<=codeEnd);if(i===worker){bodyLenStart=start;bodyStart=p.i;bodyEnd=end;break;}p.i=end;}
 assert(bodyStart!==undefined);p.i=bodyStart;const groups=read(bytes,p);for(let i=0;i<groups;i++){read(bytes,p);assert([0x7f,0x7d].includes(bytes[p.i++]));}
 let depth=0,inLoop=false,loopDepth=0,sites=[],events=[];
 while(p.i<bodyEnd) {
  const op=bytes[p.i++];
  if(op===0x0b){if(inLoop&&depth===loopDepth)inLoop=false;if(depth>0)depth--;continue;}
  if([0x02,0x03,0x04].includes(op)){assert([0x40,0x7f].includes(bytes[p.i++]));depth++;if(op===0x03){assert(!inLoop);inLoop=true;loopDepth=depth;}continue;}
  if([0x28,0x36,0x2a,0x38].includes(op)){read(bytes,p);const off=read(bytes,p);if(inLoop){if(op===0x2a)events.push('load');else if(op===0x38)events.push(`store${off}`);else if(op===0x36)events.push(`length${off}`);else assert.fail('unexpected load');}continue;}
  if([0x0c,0x0d,0x10,0x20,0x21,0x41].includes(op)){const v=read(bytes,p);if(inLoop&&op===0x21&&(v===xlocal||v===ylocal)){events.push(`set${v}`);sites.push(p.i);}continue;}
  if(simple.has(op)){if(inLoop&&(op===0x92||op===0x94))events.push('arithmetic');continue;}
  assert.fail(`unexpected instruction ${op.toString(16)}`);
 }
 assert.deepEqual(events.filter(x=>x.startsWith('set')), [`set${xlocal}`,`set${ylocal}`]);
 const first=events.indexOf(`set${xlocal}`),second=events.indexOf(`set${ylocal}`),store=events.indexOf('store0');
 assert(first>=0&&first<second&&second<store);assert.deepEqual(events.filter(x=>x.startsWith('store')||x.startsWith('length')),['store0','store4','length12']);
 assert(!events.slice(store).some(x=>x==='load'||x==='arithmetic'));
 assert.equal(sites.length,2);
 const body=Buffer.concat([bytes.subarray(bodyStart,sites[which]),Buffer.from([0]),bytes.subarray(sites[which],bodyEnd)]);
 const payload=Buffer.concat([bytes.subarray(codePayload,bodyLenStart),leb(body.length),body,bytes.subarray(bodyEnd,codeEnd)]);
 return Buffer.concat([bytes.subarray(0,codeStart),Buffer.from([10]),leb(payload.length),payload,bytes.subarray(codeEnd)]);
}
for(const [name,index,x,y,guest] of [['particle-guest.wasm',7,15,16,true],['particle-source.wasm',10,7,8,false],...['a','b','c','d'].map(n=>[`particle-lower-${n}.wasm`,10,7,8,false])]) {
 const original=readFileSync(name);assert(WebAssembly.validate(original));
 for(let point=0;point<2;point++) {
  const mutant=inspectAndInject(original,index,x,y,point);assert(WebAssembly.validate(mutant));
  const e=new WebAssembly.Instance(new WebAssembly.Module(mutant)).exports;
  assert.equal(e.reserve(32),1);assert.equal(e.reserve(32),2);assert.equal(e.input_alloc(1,1,2),0);
  const w=new Uint32Array(e.memory.buffer),view=new DataView(e.memory.buffer),input=w[66],out=w[12];
  for(let i=0;i<8;i++)view.setFloat32(input+i*4,i+1,true);assert.equal(e.input_freeze(1,1),2);
  if(!guest){assert.equal(e.builder_alloc(2,1,2),0);assert.equal(w[86],out);}
  new Uint8Array(e.memory.buffer,out,16).fill(0xa5);const before=Buffer.from(new Uint8Array(e.memory.buffer,out,16));
  assert.throws(()=>guest?e.project(1,1,2,1,2,0.5):e.project(1,1,2,1,0.5),WebAssembly.RuntimeError);
  assert.deepEqual(Buffer.from(new Uint8Array(e.memory.buffer,out,16)),before,`${name} argument ${point} wrote output`);
  assert.equal(w[87],0,`${name} published incomplete row`);
 }
}
console.log('particle argument-order instruction and injected-trap witnesses passed');
