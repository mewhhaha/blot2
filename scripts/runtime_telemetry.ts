/** Instrumented attribution only. Use uninstrumented artifacts for timing. */
import { Blot } from '../host/blot.ts';
const root = new URL('../', import.meta.url).pathname;
const option = (name: string, fallback: string) => Deno.args.find(arg => arg.startsWith(`--${name}=`))?.slice(name.length + 3) ?? fallback;
const compiler = option('compiler', 'build/blot');
const output = option('output', 'build/runtime-telemetry.json');
const wasmPath = 'build/runtime-telemetry-particles.wasm';
const command = [compiler, 'build', 'examples/particles.blot', '--opt=off', '--telemetry', '--bridge-config=examples/particles.json', '-o', wasmPath];
const process = await new Deno.Command(root + compiler, { cwd: root, args: command.slice(1), stdout: 'piped', stderr: 'piped' }).output();
if (!process.success) throw new Error(new TextDecoder().decode(process.stderr));
const bytes = await Deno.readFile(root + wasmPath), module = await WebAssembly.compile(bytes);
const manifest = JSON.parse(new TextDecoder().decode(WebAssembly.Module.customSections(module, 'blot.k1.manifest')[0]));
const samples: unknown[] = [];
for (const count of [0, 1, 1024]) {
  const guest = await Blot.load(bytes);
  const source = Array.from({ length: count }, (_, i) => ({ x: i, y: -i, vx: 2, vy: -3 }));
  const result = guest.invoke('project', { source, dt: 0.5 });
  if (result.status !== 'Ok' || !Array.isArray(result.items) || result.items.length !== count) throw new Error('particle execution failed');
  result.items.forEach((item, i) => { const row = item as { x: number; y: number }; if (row.x !== i + 1 || row.y !== -i - 1.5) throw new Error('incorrect particle result'); });
  const counters = guest.telemetry();
  if (!counters || counters.loop_iterations !== BigInt(count) || counters.backing_live_bytes !== 0n || counters.source_calls !== 1n) throw new Error('invalid telemetry');
  samples.push({ count, status: result.status, counters });
}
async function sha256(path: string) {
  const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', await Deno.readFile(root + path)));
  return Array.from(digest, value => value.toString(16).padStart(2, '0')).join('');
}
const report = {
  format: 'K1-RUNTIME-TELEMETRY-1', mode: 'instrumented attribution; no timing samples', command,
  compiler_sha256: await sha256(compiler), source_sha256: await sha256('examples/particles.blot'), wasm_sha256: await sha256(wasmPath),
  abi_hash: manifest.abi_hash, geometry_hash: manifest.geometry_hash, samples,
};
await Deno.writeTextFile(root + output, JSON.stringify(report, (_, value) => typeof value === 'bigint' ? value.toString() : value, 2) + '\n');
console.log(output);
