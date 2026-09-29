#!/usr/bin/env python3
"""Compile and execute native unit gates using the built semantic modules."""
from pathlib import Path
import os
import subprocess
import shutil
from build import HERE, FLAGS, run

compiler = shutil.which(os.environ.get('OCAMLOPT', 'ocamlopt'))
if not compiler:
    raise SystemExit('ocamlopt is required')
output = HERE / '_build'
sources = [p.name for p in output.glob('*.ml') if not p.name.startswith('test_')]
order = run([str(Path(compiler).with_name('ocamldep')), '-sort', *sources], output, True).split()
objects = [str(Path(name).with_suffix('.cmx')) for name in order if name != 'driver.ml']
for name, arguments in [('test_storage', []), ('test_levels', []), ('test_graph_verify', []), ('test_parallel', ['domains']), ('test_domains', [])]:
    shutil.copyfile(HERE / (name + '.ml'), output / (name + '.ml'))
    run([compiler, *FLAGS, '-c', name + '.ml'], output)
    run([compiler, *FLAGS, '-o', name, 'unix.cmxa', 'threads.cmxa',
         'runtime_stubs.o', *objects, name + '.cmx'], output)
    subprocess.run([str(output / name), *arguments], check=True, timeout=90)
