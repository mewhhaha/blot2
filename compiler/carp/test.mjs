import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { instantiateGuest } from '../guest.ts';
import { accepted, rejected } from './cases.mjs';

const binary = process.env.BLOT_CARP ?? 'generated/carp/blotc-carp';
const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'blot-carp-test-'));
let checks = 0;
function compile(source, extra = []) {
  const input = path.join(temp, 'input.blot');
  const output = path.join(temp, 'output.wasm');
  fs.writeFileSync(input, source);
  fs.rmSync(output, { force: true });
  const result = spawnSync(binary, ['build', input, output, ...extra], {encoding:'utf8', timeout:15000});
  if (result.error) throw result.error;
  return {...result, output, input};
}
try {
  for (const item of accepted) {
    const result = compile(item.source);
    assert.equal(result.status, 0, `${item.name}: ${result.stderr}`);
    const bytes = fs.readFileSync(result.output);
    assert(WebAssembly.validate(bytes), `${item.name}: invalid Wasm`);
    const module = new WebAssembly.Module(bytes);
    assert.deepEqual(WebAssembly.Module.imports(module), [], `${item.name}: unexpected runtime dependency`);
    const guest = await instantiateGuest(bytes);
    try {
      for (const [name,value] of Object.entries(item.read ?? {})) {assert.equal(guest.read(name),value,`${item.name}: ${name}`); checks++;}
      for (const [name,argument,value] of item.calls ?? []) {assert.equal(guest.call(name,argument),value,`${item.name}: ${name}`); checks++;}
      if (item.exports) assert.deepEqual(WebAssembly.Module.exports(module).map(x=>x.name).sort(), [...item.exports].sort());
    } finally {guest.dispose();}
    const again = compile(item.source);
    assert.equal(again.status,0,again.stderr);
    assert.deepEqual(fs.readFileSync(again.output),bytes,`${item.name}: nondeterministic output`);
    console.log(`ok: ${item.name}`);
  }
  for (const [name,source,diagnostic] of rejected) {
    const result = compile(source);
    assert.equal(result.status,1,`${name}: expected rejection, got ${result.status}: ${result.stderr}`);
    assert(result.stderr.includes(diagnostic),`${name}: expected ${diagnostic}, got ${result.stderr}`);
    assert(!fs.existsSync(result.output),`${name}: wrote an artifact on failure`);
    checks++;
    console.log(`ok: rejects ${name}`);
  }
  const fuel = compile('entry const answer = 1 + 2\n',['--const-steps','0']);
  assert.equal(fuel.status,1); assert(fuel.stderr.includes('const_steps')); checks++;
  const preserve = compile('entry const answer = 42\n');
  const old = fs.readFileSync(preserve.output);
  fs.writeFileSync(preserve.input,'entry const answer = missing\n');
  const failure = spawnSync(binary,['build',preserve.input,preserve.output],{encoding:'utf8'});
  assert.equal(failure.status,1); assert.deepEqual(fs.readFileSync(preserve.output),old); checks++;
  console.log(`PASS: ${accepted.length} execution programs, ${rejected.length} rejection programs, ${checks} value/error checks; deterministic Wasm and artifact preservation`);
} finally {fs.rmSync(temp,{recursive:true,force:true});}
