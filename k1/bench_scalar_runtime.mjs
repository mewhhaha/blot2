// Diagnostic scalar witness only; not a general compiler/runtime comparison.
import { readFile, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import os from 'node:os';
const [oldPath, newPath, outPath, iterationsText='2000000', samplesText='31', warmupText='8'] = process.argv.slice(2);
if (!oldPath || !newPath || !outPath) throw Error('usage: node paired-runtime.mjs OLD.wasm NEW.wasm OUT.json [iterations samples warmups]');
const iterations=Number(iterationsText), samples=Number(samplesText), warmups=Number(warmupText);
if (![iterations,samples,warmups].every(Number.isSafeInteger) || iterations <= 0 || samples <= 0 || warmups < 0) throw Error('invalid count');
const sha = b => createHash('sha256').update(b).digest('hex');
const oldBytes=await readFile(oldPath), newBytes=await readFile(newPath);
const oldModule=await WebAssembly.compile(oldBytes), newModule=await WebAssembly.compile(newBytes);
if(WebAssembly.Module.imports(oldModule).length || WebAssembly.Module.imports(newModule).length) throw Error('unexpected imports');
const oldFn=(new WebAssembly.Instance(oldModule)).exports.f, newFn=(new WebAssembly.Instance(newModule)).exports.f;
if(typeof oldFn !== 'function' || typeof newFn !== 'function' || oldFn.length !== 1 || newFn.length !== 1) throw Error('unexpected ABI');
let seed=0x92d68ca2;
for(let i=0;i<2000;i++){ seed^=seed<<13; seed^=seed>>>17; seed^=seed<<5;const x=seed>>>0;if((oldFn(x)>>>0)!==x || (newFn(x)>>>0)!==x)throw Error(`identity mismatch ${x}`); }
function batch(f,n){let acc=0;for(let i=0;i<n;i++){const x=(Math.imul(i,2654435761)+17)>>>0;acc=(acc+(f(x)>>>0))>>>0;}return acc;}
for(let i=0;i<warmups;i++){batch(oldFn,iterations);batch(newFn,iterations);}
const rows=[];
for(let i=0;i<samples;i++){
 const order=i%2===0? [['old',oldFn],['new',newFn]] : [['new',newFn],['old',oldFn]];
 const sample={};
 for(const [name,fn] of order){const begin=process.hrtime.bigint();const checksum=batch(fn,iterations);const ns=Number(process.hrtime.bigint()-begin);sample[name]={ns,checksum};}
 if(sample.old.checksum!==sample.new.checksum)throw Error('checksum mismatch'); rows.push(sample);
}
function stats(name){const values=rows.map(r=>r[name].ns/iterations).sort((a,b)=>a-b);return {median_ns_per_js_to_wasm_call:values[Math.floor(values.length/2)],p10:values[Math.floor((values.length-1)*0.1)],p90:values[Math.floor((values.length-1)*0.9)],raw_ns_per_call:values};}
const report={scope:'single scalar identity; direct JS-to-Wasm calls; test-only thin K1 worker; not K1 qualification or workload throughput',caveat:'Time includes JS loop, input generation, call boundary and engine/JIT effects; identical Wasm bodies do not imply identical compiled machine code.',runtime:process.version,v8:process.versions.v8,platform:os.platform(),arch:os.arch(),cpu:os.cpus()[0]?.model,iterations,samples,warmups,sha256:{old:sha(oldBytes),candidate:sha(newBytes)},results:{legacy:stats('old'),k1_thin:stats('new')},pairs:rows};
await writeFile(outPath,JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify({scope:report.scope,caveat:report.caveat,results:{legacy:report.results.legacy.median_ns_per_js_to_wasm_call,k1_thin:report.results.k1_thin.median_ns_per_js_to_wasm_call},checksum:rows[0].old.checksum}));
