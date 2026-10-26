import { Blot } from '../host/blot.ts';
function assert(ok: unknown, message = 'host bridge assertion failed'): asserts ok {
  if (!ok) throw new Error(message);
}
const root = new URL('../', import.meta.url).pathname;
async function sourceBridge(): Promise<Uint8Array<ArrayBuffer>> {
  const build = await new Deno.Command(root + 'build/blot', {
    cwd: root,
    args: ['build', 'examples/bridge_identity.blot', '-o', 'build/host-bridge.wasm', '--bridge-config=examples/bridge_identity.json'],
    stdout: 'piped', stderr: 'piped',
  }).output();
  assert(build.success, new TextDecoder().decode(build.stderr));
  return await Deno.readFile(root + 'build/host-bridge.wasm');
}
Deno.test('source generic array bridge returns copies and statuses', async () => {
  const host = await Blot.load(await sourceBridge());
  assert(host.exports.join() === 'copy_identity');
  const input = new Uint32Array([0, 1, 2147483648, 4294967295]);
  const result = host.invoke('copy_identity', { src: input });
  assert(result.status === 'Ok' && Array.isArray(result.items) && result.items.join() === input.join());
  input.fill(9);
  const second = host.invoke('copy_identity', { src: [7] });
  assert(second.status === 'Ok' && Array.isArray(second.items) && second.items.join() === '7');
  assert(result.items.join() === '0,1,2147483648,4294967295', 'previous result aliases Wasm or caller memory');
  const small = host.invoke('copy_identity', { src: [1, 2, 3] }, 19);
  assert(small.status === 'OutputTooSmall' && small.requiredBytes === 20);
  const empty = host.invoke('copy_identity', { src: [] });
  assert(empty.status === 'Ok' && empty.items.length === 0);
  assert(host.invoke('copy_identity', { src: [-1] }).status === 'InvalidInput');
  assert(host.invoke('copy_identity', { src: Array(1025).fill(1) }).status === 'InvalidInput');
  assert(host.invoke('unknown', {}).status === 'InvalidInput');
  let nested = '';
  const reentry = host.invoke('copy_identity', { get src() {
    nested = host.invoke('copy_identity', { src: [] }).status;
    return [5];
  } });
  assert(nested === 'Busy' && reentry.status === 'Ok');
  assert(!host.poisoned && !('memory' in host) && !('instance' in host));
});
function leb(n: number): number[] {
  const out: number[] = [];
  do { const byte = n & 127; n >>>= 7; out.push(byte | (n ? 128 : 0)); } while (n);
  return out;
}
function section(id: number, bytes: number[]): number[] { return [id, ...leb(bytes.length), ...bytes]; }
function name(value: string): number[] { const bytes = [...new TextEncoder().encode(value)]; return [...leb(bytes.length), ...bytes]; }
Deno.test('unexpected trap permanently poisons private instance', async () => {
  const original = await WebAssembly.compile(await sourceBridge());
  const manifest = new Uint8Array(WebAssembly.Module.customSections(original, 'blot.k1.manifest')[0]);
  const parsed = JSON.parse(new TextDecoder().decode(manifest));
  // A deliberately corrupt guest, independent of the source compiler: one
  // exported bridge function traps. The host must never reuse its instance.
  const binary = new Uint8Array([
    0, 97, 115, 109, 1, 0, 0, 0,
    ...section(1, [1, 96, 3, 127, 127, 127, 1, 127]),
    ...section(3, [1, 0]),
    ...section(5, [1, 1, ...leb(parsed.memory.pages), ...leb(parsed.memory.pages)]),
    ...section(7, [2, ...name('memory'), 2, 0, ...name('blot_call'), 0, 0]),
    ...section(10, [1, 3, 0, 0, 11]),
    ...section(0, [...name('blot.k1.manifest'), ...manifest]),
  ]);
  const host = await Blot.load(binary);
  assert(host.invoke('copy_identity', { src: [] }).status === 'Poisoned');
  assert(host.poisoned);
  assert(host.invoke('copy_identity', { src: [] }).status === 'Poisoned');
});
Deno.test('zero-size arrays cross host bridge as compact logical counts', async () => {
  const build = await new Deno.Command(root + 'build/blot', {
    cwd: root,
    args: ['build', 'examples/bridge_identity.blot', '-o', 'build/host-unit.wasm', '--bridge-config=examples/bridge_unit.json'],
    stdout: 'piped', stderr: 'piped',
  }).output();
  assert(build.success, new TextDecoder().decode(build.stderr));
  const host = await Blot.load(await Deno.readFile(root + 'build/host-unit.wasm'));
  const result = host.invoke('copy_identity', { src: { length: 4294967295 } }, 8);
  assert(result.status === 'Ok' && !Array.isArray(result.items) && result.items.length === 4294967295);
});
