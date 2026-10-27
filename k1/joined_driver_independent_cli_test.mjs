import {spawnSync} from 'node:child_process';
import {writeFileSync,mkdtempSync,rmSync} from 'node:fs';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import assert from 'node:assert/strict';
const dir=mkdtempSync(join(tmpdir(),'joined-audit-'));
try {
 const bad=join(dir,'bad.blot');writeFileSync(bad,Buffer.from([0,255,128,10]));
 const huge=join(dir,'huge.blot');writeFileSync(huge,Buffer.alloc(16777217,32));
 for(const exe of process.argv.slice(2)){
  for(const args of [['check'],['build'],['check',bad,'--trace'],['build',bad,'--trace'],['joined-fixture',bad],['joined-fixture',bad,'--trace'],['joined-fixture',huge],['joined-fixture'],['joined-fixture',bad,'--invalid']]){
    const r=spawnSync(exe,args,{encoding:'utf8'});assert.notEqual(r.status,0,JSON.stringify(args));assert.equal(r.stdout,'',JSON.stringify(args));
  }
 }
 console.log('independent driver rejection/no-stdout controls passed');
} finally {rmSync(dir,{recursive:true,force:true});}
