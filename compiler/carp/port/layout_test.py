#!/usr/bin/env python3
"""Compile synthetic scope/closure fixtures through the real generator and Carp.

The expected results are evaluated independently as JavaScript before native
compilation. Fixtures use a temporary semantic lock, never the production lock.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

PORT = Path(__file__).resolve().parent


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sanitize', action='store_true')
    args = parser.parse_args()
    carp = shutil.which(os.environ.get('CARP', 'carp'))
    cc = shutil.which(os.environ.get('CC', 'clang'))
    node = shutil.which(os.environ.get('NODE', 'node'))
    if not all([carp, cc, node]):
        parser.error('pinned Carp, a C compiler and Node are required')
    branches = '\n'.join(
        f'if (n === {i}) {{ const a = {i}; const b = a + 1; const c = b + 1; return c; }}'
        for i in range(128))
    source = '''
function choose(n) { BRANCHES return 1000; }
function capture(n) {
  let f = (v) => v;
  { const x = n; f = (v) => x + v; }
  { const x = 900; const y = x + 1; if (y < 0) return y; }
  return f(2);
}
function shadow(n) {
  const x = n;
  let f = (y) => x + y;
  { const x = 100; const y = x + 1; if (y < 0) return y; }
  return f(3);
}
function loop(n) {
  let f = (x) => x;
  let count = 0;
  for (;;) {
    if (n === 0) return f(count);
    { const x = n; f = (v) => x + v; }
    { const y = 999; count = count + 1; }
    n = n - 1;
    continue;
  }
}
function selected(n) {
  const record = {$: "Some", value: n};
  if (record.$ === "Some" && "None" !== record["$"]) return record.value;
  return -100;
}
function $initial$() { return 42; }
function $protocol_version$() { return 13; }
function $exchange$(n, a, b) {
  return choose(n) + capture(n) + shadow(n) + loop(a) + selected(b);
}
'''.replace('BRANCHES', branches)
    with tempfile.TemporaryDirectory(prefix='carp-layout-test-') as tmp:
        root = Path(tmp); port = root/'port'; generated = root/'generated'
        (port/'vendor').mkdir(parents=True)
        for name in ['generate.cjs', 'loops.cjs', 'runtime.c', 'runtime.h', 'scheduler.inc', 'vendor/acorn.cjs']:
            shutil.copy2(PORT/name, port/name)
        lock = json.loads((PORT/'reference.lock.json').read_text())
        lock['semanticSha256'] = hashlib.sha256(source.encode()).hexdigest()
        lock['sourceCommit'] = 'synthetic-layout-test'
        (port/'reference.lock.json').write_text(json.dumps(lock))
        input_path = root/'fixture.mjs'; input_path.write_text(source)
        subprocess.run([node, str(port/'generate.cjs'), str(input_path), str(generated)],
                       check=True, stdout=subprocess.DEVNULL)
        tables = (generated/'tables.c').read_text()
        slots = [int(n) for n in re.findall(r'\{port\d+, (\d+),', tables)]
        if not slots or max(slots) > 16:
            raise AssertionError(f'mutually exclusive branches reserve too many slots: {slots}')
        code = '\n'.join(p.read_text() for p in generated.glob('unit*.carp'))
        if '(v-local-field ' not in code or '(v-local-tag ' not in code:
            raise AssertionError('borrowed local operations were not exercised')
        oracle = root/'oracle.mjs'
        oracle.write_text(source+'\nconsole.log(JSON.stringify(Array.from({length:256},(_,n)=>$exchange$(n,n%17,n%11))));\n')
        expected = json.loads(subprocess.check_output([node, str(oracle)], text=True))
        flags = ['-std=c11', '-Wall', '-Wextra', '-Werror', '-Wno-unused-parameter',
                 '-ffp-contract=off', '-pthread', '-I'+str(generated), '-I'+str(port)]
        flags += (['-O1', '-g', '-fsanitize=address,undefined', '-fno-sanitize-recover=all']
                  if args.sanitize else ['-O2'])
        objects = []
        for index, unit in enumerate(sorted(generated.glob('unit*.carp'))):
            work = root/f'unit{index}'; work.mkdir()
            subprocess.run([carp, '--no-core', '--no-profile', '--generate-only',
                '--eval-postload', '(Project.config "output-directory" '+json.dumps(str(work))+')',
                '-b', str(unit)], cwd=root, check=True, stdout=subprocess.DEVNULL)
            obj = work/'unit.o'
            subprocess.run([cc, *flags, '-Dcarp_init_globals=fixture_init_'+str(index),
                            '-c', str(work/'main.c'), '-o', str(obj)], check=True)
            objects.append(str(obj))
        harness = root/'harness.c'
        harness.write_text('#define BP_NO_MAIN\n#include "runtime.c"\n#include <assert.h>\n'
            +'static const double expected[] = {'+','.join(map(str, expected))+'};\n'
            +'int main(void) { bp_pool_start(4);'
            +'for (size_t i=0;i<256;i++) {'
            +'Long result=bp_call3(BP_EXCHANGE,bp_num((double)i),bp_num((double)(i%17)),bp_num((double)(i%11)));'
            +'assert(bp_number(result)==expected[i]);bp_drop(result);}'
            +'bp_pool_stop();bp_destroy();return 0;}\n')
        binary = root/'layout-test'
        subprocess.run([cc, *flags, str(harness), str(generated/'tables.c'), *objects,
                        '-lm', '-o', str(binary)], check=True)
        subprocess.run([str(binary)], check=True)
    print(f'Layout: 256 native/oracle cases passed; largest frame {max(slots)} slots; sanitize={args.sanitize}.')

if __name__ == '__main__':main()
