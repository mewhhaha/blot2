#!/usr/bin/env python3
"""Independent bounded source/step/value differential; runs at O0 and O2."""
import json
import os
from pathlib import Path
import random
import shutil
import subprocess
import tempfile


def main():
    rng = random.Random(599510)
    ints = ['0', '1', '4294967295', '4294967295 + 1', '0 - 1', '3 * 4', '3 & 7', 'U32.wrapping_add(4294967295,1)']
    floats = ['0.0', '-0.0', '1.5', '0.0 / 0.0', '1.5 * 2.0', '2.0 + 3.0', '1.0 / 0.0']
    lines = ['import std; import static_product_parse; import static_product_verify; import static_product_eval; import static_fast_verify; import static_fast_eval; fn main(){var yes:i64=0;var no:i64=0;']
    for _ in range(500):
        width, count = rng.randrange(2, 6), rng.randrange(1, 7)
        types = [rng.choice([ints, floats]) for _ in range(width)]
        rows = [[rng.choice(types[j]) for j in range(width)] for _ in range(count)]
        source = 'static let sample = #[' + ','.join('(' + ','.join(row) + ')' for row in rows) + ']\n'
        lines.append('{let s=' + json.dumps(source) + ';var p=static_product_parse::parse(s);'
                     'if p.status==0 {yes+=1;assert(static_product_verify::verify(s,p.tree)==static_fast_verify::verify(s,p.tree));'
                     'let a=static_product_eval::evaluate(s,p.tree);let b,_=static_fast_eval::evaluate(s,p.tree);'
                     'assert(a.status==b.status && a.steps==b.steps && a.bytes==b.bytes && a.data[..]==b.data[..]);}else {no+=1;}}')
    lines.append('print(str("independent cached static differential: ",yes," accepted, ",no," rejected"));}')
    with tempfile.TemporaryDirectory(prefix='k1-static-fast-oracle-') as temp:
        root = Path(temp)
        shutil.copytree(Path(__file__).resolve().parent, root / 'k1')
        driver = root / 'k1' / 'static_fast_generated_driver.goose'
        driver.write_text('\n'.join(lines), encoding='utf-8')
        for level in ('-O0', '-O2'):
            subprocess.run([os.environ.get('GOOSE', 'goose'), '--debug', level, str(driver)], cwd=root, check=True)


if __name__ == '__main__':
    main()
