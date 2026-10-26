const compiler = new URL('../build/blot', import.meta.url).pathname;
const root = new URL('../', import.meta.url).pathname;
function assert(ok: unknown, detail = 'assertion failed'): asserts ok {
  if (!ok) throw new Error(detail);
}
async function command(args: string[]) {
  return await new Deno.Command(compiler, { args, cwd: root, stdout: 'piped', stderr: 'piped' }).output();
}
async function compile(name: string, source: string) {
  const input = `build/host-${name}.blot`;
  const output = `build/host-${name}.wasm`;
  await Deno.writeTextFile(root + input, source);
  const result = await command(['build', input, '-o', output, '--language=k1']);
  assert(result.success, new TextDecoder().decode(result.stderr));
  const bytes = await Deno.readFile(root + output);
  assert(WebAssembly.validate(bytes), 'compiler emitted invalid Wasm');
  const { instance } = await WebAssembly.instantiate(bytes);
  return instance.exports;
}
Deno.test('source → checked Core → Wasm scalar boundary values', async () => {
  const exports = await compile('identity',
    'pub let identity: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => return x\n');
  const identity = exports.identity as CallableFunction;
  for (const value of [0, 1, 2147483647, 2147483648, 4294967295]) {
    assert((identity(value) >>> 0) === value);
  }
  assert(!('memory' in exports), 'scalar API must not expose raw memory');
});
Deno.test('F32 scalar ABI preserves negative zero', async () => {
  const exports = await compile('float',
    'pub let identity: F32 -> F32 ! {} resources {depth: 1, frame: 0} = fn x => return x\n');
  const identity = exports.identity as CallableFunction;
  assert(Object.is(identity(-0), -0));
  assert(Object.is(identity(0), 0));
  assert(identity(Infinity) === Infinity);
  assert(Number.isNaN(identity(NaN)));
});
Deno.test('failed and cancelled builds preserve published output', async () => {
  const path = root + 'build/transaction.wasm';
  const marker = new Uint8Array([1, 4, 9, 16]);
  await Deno.writeFile(path, marker);
  await Deno.writeTextFile(root + 'build/invalid.blot',
    'pub let bad: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => return x + 1\n');
  const invalid = await command(['build', 'build/invalid.blot', '-o', path]);
  assert(!invalid.success, 'unproved arithmetic must be rejected');
  assert((await Deno.readFile(path)).every((byte, i) => byte === marker[i]));
  await Deno.writeTextFile(root + 'build/cancel', 'cancel');
  const cancelled = await command(['build', 'examples/identity.blot', '-o', path, '--cancel-file=build/cancel']);
  assert(!cancelled.success && new TextDecoder().decode(cancelled.stderr).includes('k1_cancelled'));
  assert((await Deno.readFile(path)).every((byte, i) => byte === marker[i]));
});
Deno.test('edition and hostile artifact headers reject before admission', async () => {
  const mismatch = await command(['check', 'examples/identity.blot', '--language=legacy']);
  assert(!mismatch.success && new TextDecoder().decode(mismatch.stderr).includes('k1_edition_mismatch'));
  await Deno.writeFile(root + 'build/forged.bk1', new Uint8Array([0, 1, 2, 3, 255]));
  const forged = await command(['inspect', 'build/forged.bk1']);
  assert(!forged.success, 'truncated artifact was accepted');
});
Deno.test('package loader rejects symlink escape', async () => {
  await Deno.mkdir(root + 'build/package', { recursive: true });
  await Deno.writeTextFile(root + 'build/outside.blot', 'let outside = 1\n');
  try { await Deno.remove(root + 'build/package/escape.blot'); } catch (e) {
    if (!(e instanceof Deno.errors.NotFound)) throw e;
  }
  await Deno.symlink('../outside.blot', root + 'build/package/escape.blot');
  await Deno.writeTextFile(root + 'build/package/entry.blot',
    'import "./escape.blot" as escape\nlet inside = 1\n');
  const escaped = await command(['check', 'build/package/entry.blot', '--package-root=build/package']);
  assert(!escaped.success && new TextDecoder().decode(escaped.stderr).includes('k1_package_escape'));
});
Deno.test('portable Core roundtrip is independently admitted', async () => {
  const build = await command(['build', 'examples/identity.blot', '-o', 'build/roundtrip.wasm', '--emit-core=build/roundtrip.bk1']);
  assert(build.success, new TextDecoder().decode(build.stderr));
  const inspect = await command(['inspect', 'build/roundtrip.bk1']);
  assert(inspect.success, new TextDecoder().decode(inspect.stderr));
});
