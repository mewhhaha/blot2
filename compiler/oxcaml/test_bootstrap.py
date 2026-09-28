#!/usr/bin/env python3
"""Ensure migration reproduction cannot erase native optimizations."""
from pathlib import Path
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parent / 'bootstrap'))
from port import write_checked_outputs

with tempfile.TemporaryDirectory() as directory:
    target = Path(directory) / 'core'
    outputs = {'a.ml': 'let a = 1\n', 'b.ml': 'let b = 2\n'}
    write_checked_outputs(target, outputs)
    assert all((target / name).read_text() == text for name, text in outputs.items())
    write_checked_outputs(target, outputs)
    (target / 'b.ml').write_text('let b = 3 (* native optimization *)\n')
    try:
        write_checked_outputs(target, {'new.ml': 'new', **outputs})
        raise AssertionError('native overwrite was accepted')
    except FileExistsError as error:
        assert '--output' in str(error)
    assert not (target / 'new.ml').exists(), 'failed migration wrote a partial batch'
    assert (target / 'b.ml').read_text() == 'let b = 3 (* native optimization *)\n'
print('3 migration overwrite-safety checks passed')
