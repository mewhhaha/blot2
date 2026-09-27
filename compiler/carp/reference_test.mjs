// The reference is an oracle only in tests. The Carp executable never calls it.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { instantiateGuest } from '../guest.ts';
import { createSourceCompiler } from '../source.ts';
import { accepted } from './cases.mjs';

const compiler = await createSourceCompiler();
const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'blot-carp-parity-'));
const binary = process.env.BLOT_CARP ?? 'generated/carp/blotc-carp';
const failures = [];
let values = 0;
try {
  for (const item of accepted) {
    let reference;
    let replacement;
    try {
      const original = await compiler.compile(item.source, { analysis: false });
      assert(WebAssembly.validate(original.bytes), `${item.name}: invalid reference Wasm`);
      const input = path.join(directory, 'input.blot');
      const output = path.join(directory, 'output.wasm');
      fs.writeFileSync(input, item.source);
      fs.rmSync(output, { force: true });
      const result = spawnSync(binary, ['build', input, output], {
        encoding: 'utf8', timeout: 15000,
      });
      if (result.error) throw result.error;
      assert.equal(result.status, 0, result.stderr);
      const bytes = fs.readFileSync(output);
      assert(WebAssembly.validate(bytes));
      reference = await instantiateGuest(original.bytes);
      replacement = await instantiateGuest(bytes);
      for (const [name, expected] of Object.entries(item.read ?? {})) {
        const before = reference.read(name);
        const after = replacement.read(name);
        assert.equal(before, expected, `${item.name}: reference constant ${name}`);
        assert.equal(after, before, `${item.name}: constant parity ${name}`);
        values++;
      }
      for (const [name, argument, expected] of item.calls ?? []) {
        const before = reference.call(name, argument);
        const after = replacement.call(name, argument);
        assert.equal(before, expected, `${item.name}: reference call ${name}`);
        assert.equal(after, before, `${item.name}: call parity ${name}`);
        values++;
      }
      console.log(`parity: ${item.name}`);
    } catch (error) {
      console.error(`FAIL: ${item.name}: ${error.stack ?? error}`);
      failures.push(item.name);
    } finally {
      reference?.dispose();
      replacement?.dispose();
    }
  }
} finally {
  compiler.dispose();
  fs.rmSync(directory, { recursive: true, force: true });
}
assert.deepEqual(failures, [], 'Differential corpus failed; do not declare parity');
console.log(`PASS: ${accepted.length} shared source programs, ${values} differential values; scalar milestone only`);
