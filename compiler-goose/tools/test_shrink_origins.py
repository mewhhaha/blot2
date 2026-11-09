#!/usr/bin/env python3
"""Check diagnostic-only leaf shrink witnesses through ordinary and live replay."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import build_goose_checker as builder
import test_checker_tools as checker
ROOT=Path(__file__).resolve().parents[2]
TESTS=ROOT/'compiler-goose/tests/checker_tools'
def main():
    p=argparse.ArgumentParser(description=__doc__)
    for name in ('goose','baseline','source','baseline-source'):p.add_argument('--'+name,type=Path,required=True)
    p.add_argument('--stdlib',type=Path,default=ROOT.parent/'goose-to-wasm/build/source/stdlib')
    p.add_argument('--output',type=Path,default=ROOT/'build/goose-port/shrink-origins/controls')
    a=p.parse_args();a.output=a.output.resolve();a.output.mkdir(parents=True,exist_ok=True)
    env=dict(os.environ)
    for key in ('GOOSE_SHRINK_ORIGINS','GOOSE_DIAGNOSTIC_ROOTS','GOOSE_CHECKER_TRACE','GOOSE_CHECKER_PROFILE'):env.pop(key,None)
    def run(name,binary,mode,fixture,extra=(),selected=None,expected=0):
        e=dict(env)
        if selected:e['GOOSE_SHRINK_ORIGINS']=selected
        command=[str(binary.resolve()),mode,str(fixture),'--stdlib',str(a.stdlib),*map(str,extra)]
        result=subprocess.run(command,capture_output=True,text=True,timeout=10,env=e)
        (a.output/(name+'.stdout')).write_text(result.stdout);(a.output/(name+'.stderr')).write_text(result.stderr)
        assert result.returncode==expected,(command,result.returncode,result.stdout,result.stderr)
        return result
    invalid=TESTS/'shrink_origins_invalid.goose';valid=TESTS/'shrink_origins_valid.goose'
    old=run('invalid-baseline',a.baseline,'check',invalid,('--diagnostics','json'),expected=1)
    new=run('invalid-default',a.goose,'check',invalid,('--diagnostics','json'),expected=1)
    baseline=json.loads(old.stdout);assert json.loads(new.stdout)==baseline
    diagnosed=run('invalid-origin',a.goose,'check',invalid,('--diagnostics','json'),selected='outer',expected=1)
    rows=json.loads(diagnosed.stdout);assert len(rows)==1 and rows[0]['message']==baseline[0]['message']
    assert rows[0]['line']==5 and rows[0]['col']==baseline[0]['col']
    note=rows[0]['related'][0]
    assert note['line']==2 and note['file']==str(invalid) and 'leaf' in note['message'] and 'original shrink witness' in note['message']
    assert rows[0]['related'][1:]==baseline[0]['related']
    filtered=run('invalid-filtered',a.goose,'check',invalid,('--diagnostics','json'),selected='unrelated',expected=1)
    assert json.loads(filtered.stdout)==baseline
    cfile=a.output/'same-path.c';hashes=[]
    for label,binary,selected in [('baseline',a.baseline,None),('default',a.goose,None),('origin',a.goose,'*')]:
        run('valid-emit-'+label,binary,'--standalone',valid,('-o',cfile),selected)
        hashes.append(checker.digest(cfile))
    assert len(set(hashes))==1
    old=run('valid-baseline',a.baseline,'run',valid)
    new=run('valid-origin',a.goose,'run',valid,selected='*')
    assert old.stdout==new.stdout
    base=checker.source_root(a.baseline_source);source=checker.source_root(a.source)
    head='inline bool TypeCheck::SameRecord('
    assert checker.block((base/'src/typecheck_calls.h').read_text(),head)==checker.block((source/'src/typecheck_calls.h').read_text(),head)
    receipt={'candidate_sha256':checker.digest(a.goose),'baseline_sha256':checker.digest(a.baseline),
        'source108_sha256':builder.checked_source(source,None),'baseline_source108_sha256':builder.checked_source(base,None),
        'invalid_primary_unchanged':True,'leaf_note':note,'filter_mismatch_unchanged':True,
        'default_diagnostics_unchanged':True,'same_path_C_sha256':hashes[0],'valid_runtime_unchanged':True,
        'SameRecord_byte_identical':True,'fixture_sha256':{str(f.relative_to(ROOT)):checker.digest(f) for f in (invalid,valid,Path(__file__).resolve())}}
    (a.output/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
    print(json.dumps({'passed':True,'receipt':str(a.output/'receipt.json'),'leaf_note':note}))
if __name__=='__main__':main()
