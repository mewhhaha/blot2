import assert from 'node:assert/strict';
import {mkdtempSync,writeFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
const exe=process.argv[2];assert(exe,'expected path to private driver');const dir=mkdtempSync(join(tmpdir(),'joined-driver-'));
const head='pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n';
const inputs=[head+'  if x < 4294967295:\n    return x + 1\n  return x\n',head+'  let out = for i in 0..x carry (a=17) do:\n    next (i)\n  return out\n',head+'  let out = for i in 0..x carry (a=0) do:\n    next (U32.wrapping_add(a,1))\n  return out\n'];
try {for(let i=0;i<inputs.length;i++){const path=join(dir,`source${i}.blot`);writeFileSync(path,inputs[i]);const r=spawnSync(exe,['joined-fixture',path,'--trace'],{encoding:'utf8'});assert.equal(r.status,0,r.stderr);assert.match(r.stdout,/^[0-9a-f]+\n$/);assert.match(r.stderr,/original source and checked scalar\/loop body validated/);const bytes=Buffer.from(r.stdout.trim(),'hex');assert(WebAssembly.validate(bytes));const {instance}=await WebAssembly.instantiate(bytes);for(const x of [0,1,2,7,100])assert.equal(instance.exports.f(0,x)>>>0,(i===0?x+1:i===1?(x===0?17:x-1):x)>>>0);if(i===0)assert.equal(instance.exports.f(0,-1)>>>0,0xffffffff);}
 const invalid=[head+'  return x + 1\n',head+'  return missing\n',head+'  return x\nlet another: U32 -> U32 = fn x => return x\n',inputs[0].replace('! {}','! {read r}'),inputs[0].replace('depth: 1','depth: 0')];
 for(let i=0;i<invalid.length;i++){const path=join(dir,`bad${i}.blot`);writeFileSync(path,invalid[i]);const r=spawnSync(exe,['joined-fixture',path],{encoding:'utf8'});assert.notEqual(r.status,0);assert.equal(r.stdout,'');assert.match(r.stderr,/source error/);}
 for(const command of ['check','build']){const path=join(dir,'source0.blot');const r=spawnSync(exe,[command,path],{encoding:'utf8'});assert.notEqual(r.status,0);assert.equal(r.stdout,'');assert.match(r.stderr,/not qualified for public compilation/);}
 const missing=spawnSync(exe,['joined-fixture',join(dir,'missing')],{encoding:'utf8'});assert.notEqual(missing.status,0);assert.equal(missing.stdout,'');assert.match(missing.stderr,/cannot read source/);
 console.log('joined private driver source admission, execution and public-gate controls passed');
}finally{rmSync(dir,{recursive:true,force:true});}
