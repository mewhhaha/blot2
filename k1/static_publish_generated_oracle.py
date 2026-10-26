#!/usr/bin/env python3
"""Independent private static-publication oracle; not a K1 ABI test."""
import json
import os
from pathlib import Path
import random
import shutil
import subprocess
import tempfile


def main():
    rng = random.Random(535717)
    cases = []
    for _ in range(100):
        width, count = rng.randrange(2, 9), rng.randrange(1, 10)
        rows = [[rng.choice([0, 1, 4294967295, 4294967294, rng.randrange(2**32)])
                 for _ in range(width)] for _ in range(count)]
        source = 'static let data = #[' + ','.join('(' + ','.join(map(str, row)) + ')' for row in rows) + ']\n'
        cases.append((source, rows))
    with tempfile.TemporaryDirectory(prefix='k1-static-publish-oracle-') as tmp:
        root = Path(tmp)
        shutil.copytree(Path(__file__).resolve().parent, root / 'k1')
        lines = ['import os; import static_publish_build; import static_publish_verify; import static_publish_wasm; import static_publish_target; fn main(){']
        for i, (source, _) in enumerate(cases):
            lines.append('{let s=' + json.dumps(source) + ';var p=static_publish_build::build(s);'
                'assert(p.status==0 && static_publish_verify::verify(s,p.image));'
                'let b=static_publish_wasm::emit(s,p.image);assert(b.len>0 && static_publish_target::verify(s,p.image,b) && write_file('
                + json.dumps(f'case-{i}.wasm') + ',b));}')
        lines.append('print("generated static images verified and emitted");}')
        test = root / 'k1' / 'static_publish_generated_driver.goose'
        test.write_text('\n'.join(lines), encoding='utf-8')
        (root / 'expected.json').write_text(json.dumps([rows for _, rows in cases]), encoding='utf-8')
        (root / 'oracle.mjs').write_text('''import {readFileSync} from 'node:fs';import {strict as assert} from 'node:assert';import {openVerifiedFixture} from './k1/static_publish_host.mjs';const e=JSON.parse(readFileSync(process.argv[2]));for(let i=0;i<e.length;i++){const b=readFileSync(`case-${i}.wasm`);assert(WebAssembly.validate(b));const a=openVerifiedFixture(b),other=openVerifiedFixture(b);assert.equal(a.length,e[i].length);assert.equal(a.width,e[i][0].length);for(let row=0;row<a.length;row++){const idx=a.index(row);for(let col=0;col<a.width;col++)assert.equal(a.read(idx,col),e[i][row][col]);assert.throws(()=>other.read(idx,0),TypeError);}assert.throws(()=>a.index(a.length),RangeError);}console.log(`independent static publication: ${e.length} arrays`);''', encoding='utf-8')
        for opt in ('-O0', '-O2'):
            out = root / opt[1:]
            out.mkdir()
            subprocess.run([os.environ.get('GOOSE', 'goose'), '--debug', opt, str(test)], cwd=out, check=True)
            subprocess.run(['node', str(root / 'oracle.mjs'), str(root / 'expected.json')], cwd=out, check=True)


if __name__ == '__main__':
    main()
