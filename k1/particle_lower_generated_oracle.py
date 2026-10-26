#!/usr/bin/env python3
"""Generated independent F32 oracle for the private particle lowering slice.

This tests the fixed fixture and its trusted runtime assumptions, not the
general K1 ABI or complete floating-point NaN payload qualification.
"""
import ast
import json
import os
from pathlib import Path
import random
import re
import subprocess
import tempfile


def main():
    source_dir = Path(__file__).resolve().parent
    rng = random.Random(731143)
    leaves = ['x', 'y', 'vx', 'vy', 'dt']

    def expression(depth):
        if depth == 0 or rng.random() < .3:
            return rng.choice(leaves)
        a, b = expression(depth - 1), expression(depth - 1)
        result = a + ' ' + rng.choice(['+', '*']) + ' ' + b
        return '(' + result + ')' if rng.random() < .55 else result

    def reference(source):
        # Python's independently parsed expression tree determines the JS
        # operation order; round every arithmetic step to f32.
        def compile_node(node):
            if isinstance(node, ast.Name):
                assert node.id in leaves
                return node.id
            assert isinstance(node, ast.BinOp) and isinstance(node.op, (ast.Add, ast.Mult))
            op = '+' if isinstance(node.op, ast.Add) else '*'
            return 'f(' + compile_node(node.left) + op + compile_node(node.right) + ')'
        return compile_node(ast.parse(source, mode='eval').body)

    def k1(source):
        return re.sub(r'\b(x|y|vx|vy)\b', lambda m: 'source[i].' + m[0], source)

    pairs = [(expression(4), expression(4)) for _ in range(90)]
    goose_preamble = (source_dir / 'particle_lower_test.goose').read_text(encoding='utf-8').split('fn cloned')[0]
    js_preamble = (source_dir / 'particle_lower_test.mjs').read_text(encoding='utf-8').split('const formulas=')[0]

    with tempfile.TemporaryDirectory(prefix='k1-particle-generated-') as tmp:
        root = Path(tmp)
        directory = root / 'k1'
        directory.mkdir()
        for path in source_dir.glob('*.goose'):
            (directory / path.name).symlink_to(path.resolve())
        generated = directory / 'generated_particle_oracle.goose'
        lines = [goose_preamble, 'fn main() {',
                 'let ctx=particle_source_core::Context {owner:1,input:2,input_version:3,input_region:4,input_domain:5,length:6,dt:7,dt_version:8,builder:9,builder_version:10,output_region:11,capacity:12,index:13,next_builder:14,next_version:15,result:16,result_version:17,result_domain:18};']
        for i, (a, b) in enumerate(pairs):
            lines.append('{ let text=source(' + json.dumps(k1(a)) + ',' + json.dumps(k1(b)) + '); '
                         'var p,status=particle_lower_parse::parse(text,ctx);'
                         'assert(status==0 && particle_lower_verify::verify(p,text,ctx));'
                         'let bytes=particle_lower_wasm::emit(p,text,ctx);'
                         'assert(bytes.len>0 && particle_lower_target::verify(p,text,ctx,bytes) && '
                         'write_file(' + json.dumps(f'audit-{i}.wasm') + ',bytes)); }')
        lines.append('print("generated particle expression modules passed");}')
        generated.write_text('\n'.join(lines), encoding='utf-8')
        formulas = ',\n'.join('[(x,y,vx,vy,dt)=>' + reference(a) +
                              ',(x,y,vx,vy,dt)=>' + reference(b) + ']'
                              for a, b in pairs)
        oracle = root / 'oracle.mjs'
        oracle.write_text(js_preamble + '\nconst formulas = [\n' + formulas + '];\n' + '''
const rows=[[1,-2,3.5,-4.25],[-0,0,-0,0],[Infinity,-Infinity,0,-0],
 [1,2,Infinity,-Infinity],[1.0000001192092896,-1,-1.0000001192092896,1.0000001192092896],
 [1e-35,1e30,-1e-20,-1e25]];
for(let i=0;i<formulas.length;i++) {
  numerical(`audit-${i}.wasm`,rows,0.03125,...formulas[i]);
  numerical(`audit-${i}.wasm`,rows,-0,...formulas[i]);
}
console.log(`independent particle F32 oracle: ${formulas.length} expression pairs`);
''', encoding='utf-8')
        goose = os.environ.get('GOOSE', 'goose')
        for level in (0, 2):
            subprocess.run([goose, '--debug', f'-O{level}', str(generated)], cwd=root, check=True)
            subprocess.run(['node', str(oracle)], cwd=root, check=True)


if __name__ == '__main__':
    main()
