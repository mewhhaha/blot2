// Paired private canonical vs legacy Wasm runtime harness.
// Correctness preflight is mandatory; --verify-only produces no timing samples.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import os from 'node:os';

const argv = process.argv.slice(2);
function value(flag, fallback) { const i=argv.indexOf(flag); return i<0?fallback:argv[i+1]; }
function integer(flag, fallback, min, max) { const n=Number(value(flag, String(fallback)));if (!Number.isInteger(n)||n<min||n>max) throw Error(`${flag} out of range`);return n; }
const legacyPath=value('--legacy');const canonicalPath=value('--canonical');
if (!legacyPath || !canonicalPath) throw Error('required: --legacy FILE --canonical FILE');
const verifyOnly=argv.includes('--verify-only');
const rounds=integer('--rounds',31,1,10000), repeats=integer('--repeats',16,1,100000), warmup=integer('--warmup',8,0,10000);
const hash=(b)=>createHash('sha256').update(b).digest('hex');
function moduleInfo(path,kind) {
 const bytes=readFileSync(path); const module=new WebAssembly.Module(bytes);
 const imports=WebAssembly.Module.imports(module), exports=WebAssembly.Module.exports(module);
 assert.deepEqual(imports, [],`${kind} must not import host functions`);
 const instance=new WebAssembly.Instance(module);const e=instance.exports;
 assert.equal(typeof e.f,'function'); assert.equal(e.f.length,kind==='legacy'?1:2);
 const enter=e['blot:ownership_enter'],leave=e['blot:ownership_leave'],reset=e['blot:reset'];
 if (enter || leave) assert.equal(typeof enter,'function'),assert.equal(typeof leave,'function');
 const call=kind==='legacy' ? (!enter && !reset ? (x)=>e.f(x)>>>0 : (x)=>{
  if(enter)enter();if(reset)reset(0);let outcome=1;
  try {const r=e.f(x)>>>0;outcome=0;return r;} finally {if(leave)leave(outcome);if(reset)reset(0);}
 }) : (x)=>e.f(0,x)>>>0;
 return {call,description:{path,bytes:bytes.length,sha256:hash(bytes),imports,exports,arity:e.f.length,ownershipHooks:!!enter,resetHook:!!reset}};
}
const legacy=moduleInfo(legacyPath,'legacy'),canonical=moduleInfo(canonicalPath,'canonical');
const values=[0,1,2,7,17,255,256,511,1024,10000];let x=0x1234abcd;
for(let i=0;i<54;i++){x=(Math.imul(x,1664525)+1013904223)>>>0;values.push(x%1025);}
const witness=(n)=>n===0?17:(n-1)>>>0;
for(const n of values){const expected=witness(n);assert.equal(legacy.call(n),expected,`legacy x=${n}`);assert.equal(canonical.call(n),expected,`canonical x=${n}`);}
const result={scope:'One mathematically equivalent, finite scalar-loop workload; private canonical fixture only, not full K1 compiler or ABI parity.',
  node:process.version,v8:process.versions.v8,platform:process.platform,architecture:process.arch,cpu:os.cpus()[0]?.model,
  witnesses:values,expected:values.map(witness),legacy:legacy.description,canonical:canonical.description,
  verify_only:verifyOnly,rounds:verifyOnly?0:rounds,repeats:verifyOnly?0:repeats,warmup:verifyOnly?0:warmup,
  runtime_samples_ms:{legacy:[],canonical:[]},checksums:{legacy:[],canonical:[]},
  measurement:'Wasm instantiate/JIT warmup excluded; same Node/V8 process, paired alternating order. Each timed sample includes host call ABI and any legacy ownership hooks; both modules get identical ordered inputs. Warm filesystem / cold compile is not measured.'};
if (!verifyOnly) {
 const sumOne=values.reduce((a,n)=>(a+witness(n))>>>0,0); const expected=Math.imul(sumOne,repeats)>>>0;
 function batch(f) {let sum=0;for(let r=0;r<repeats;r++){for(const n of values){sum=(sum+f(n))>>>0;}}return sum;}
 for(let i=0;i<warmup;i++){const order=i%2?[canonical,legacy]:[legacy,canonical];for(const p of order)assert.equal(batch(p.call),expected);}
 for(let i=0;i<rounds;i++){
  for(const [name,p] of (i%2?[['canonical',canonical],['legacy',legacy]]:[['legacy',legacy],['canonical',canonical]])) {
   const start=process.hrtime.bigint(), checksum=batch(p.call), elapsed=process.hrtime.bigint()-start;
   assert.equal(checksum,expected,`${name} sample ${i} output changed`);result.runtime_samples_ms[name].push(Number(elapsed)/1e6);result.checksums[name].push(checksum);
  }
 }
}
console.log(JSON.stringify(result,null,2));
