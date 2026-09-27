// Deterministic generated inputs exercise encoding, arithmetic and input limits.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { instantiateGuest } from '../guest.ts';
const binary = process.env.BLOT_CARP ?? 'generated/carp/blotc-carp';
const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'blot-carp-stress-'));
const input = path.join(directory, 'source.blot');
const output = path.join(directory, 'module.wasm');
function run(source, command = 'build') {
  fs.writeFileSync(input, source);
  fs.rmSync(output, { force: true });
  const result = spawnSync(binary, [command, input, ...(command === 'build' ? [output] : [])], {
    encoding: 'utf8', timeout: 15000,
  });
  if (result.error) throw result.error;
  return result;
}
function rejects(source, diagnostic) {
  const result = run(source);
  assert.equal(result.status, 1, result.stderr);
  assert(result.stderr.includes(diagnostic), result.stderr);
  assert(!fs.existsSync(output));
}
let checks = 0;
try {
  let seed = 0x6a09e667;
  function random() { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed; }
  const operations = [
    ['+', (a, b) => (a + b) >>> 0],
    ['-', (a, b) => (a - b) >>> 0],
    ['*', (a, b) => Math.imul(a, b) >>> 0],
    ['<', (a, b) => a < b],
    ['>=', (a, b) => a >= b],
    ['==', (a, b) => a === b],
  ];
  const values = [0, 1, 63, 64, 127, 128, 8191, 8192, 2147483647, 2147483648, 4294967295];
  for (let i = 0; i < 100; i++) values.push(random());
  for (let i = 0; i < values.length; i++) {
    const a = values[i], b = values[(i + 1) % values.length];
    const [operator, evaluate] = operations[i % operations.length];
    const source = `entry const c = ${a} ${operator} ${b}\nentry const f = fn (x: U32) => x ${operator} ${b}\n`;
    const result = run(source);
    assert.equal(result.status, 0, result.stderr);
    const guest = await instantiateGuest(fs.readFileSync(output));
    try {
      assert.equal(guest.read('c'), evaluate(a, b));
      assert.equal(guest.call('f', a), evaluate(a, b));
      checks += 2;
    } finally { guest.dispose(); }
  }
  rejects('entry const x = 1\0entry const y = 2\n', 'NUL');
  rejects('entry const x: U32 = fn () => 42\n', 'type_mismatch');
  rejects('entry const x = ' + '('.repeat(300) + '1' + ')'.repeat(300) + '\n', 'resource_limit');
  const nested = Array.from({ length: 300 }, (_, i) => ' '.repeat((i + 1) * 2) + 'if True:').join('\n');
  rejects('entry const x = fn () => do:\n' + nested + '\n' + ' '.repeat(602) + 'return ()\n', 'resource_limit');
  rejects('//' + 'x'.repeat(16 * 1024 * 1024), 'source limit');
  checks += 5;
  const library = run('const library_value = 1\n', 'check');
  assert.equal(library.status, 0, library.stderr);
  assert(!fs.existsSync(output)); checks++;
  const exact = '//'.padEnd(16 * 1024 * 1024, ' ');
  const exactResult = run(exact, 'check');
  assert.equal(exactResult.status, 0, exactResult.stderr); checks++;
  // A destination directory must not be replaced, nor leave a temporary file.
  fs.writeFileSync(input, 'entry const answer = 42\n');
  const destination = path.join(directory, 'existing-directory');
  fs.mkdirSync(destination);
  const failure = spawnSync(binary, ['build', input, destination], { encoding: 'utf8', timeout: 15000 });
  assert.equal(failure.status, 1, failure.stderr);
  assert(fs.statSync(destination).isDirectory());
  assert(!fs.readdirSync(directory).some(name => name.includes('.tmp.'))); checks++;
  console.log(`PASS: ${checks} generated arithmetic, encoding, limit and IO checks`);
} finally { fs.rmSync(directory, { recursive: true, force: true }); }
