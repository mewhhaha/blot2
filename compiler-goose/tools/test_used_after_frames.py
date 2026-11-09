#!/usr/bin/env python3
"""Source-extracted UsedAfter frame-skip laws; never builds a compiler."""
import argparse,json
from pathlib import Path
from test_checker_tools import block,command,digest,source_root
ROOT=Path(__file__).resolve().parents[2]
def main():
 p=argparse.ArgumentParser(description=__doc__)
 p.add_argument('--source',type=Path,required=True);p.add_argument('--baseline-source',type=Path,required=True)
 p.add_argument('--output',type=Path,required=True);p.add_argument('--cxx',default='/usr/bin/clang++')
 a=p.parse_args();a.source=source_root(a.source);a.baseline_source=source_root(a.baseline_source)
 a.output=a.output.resolve();a.output.mkdir(parents=True,exist_ok=True)
 src=a.source/'src';old=a.baseline_source/'src'
 prefix=''.join('#include "'+str(src/n)+'"\n' for n in ('includes.h','utils.h','direct_input_trace.h','small_vector.h','flat_map.h','lexer_cache.h','lexer.h','ast.h','clone.h'))
 prefix+='using namespace goose;\n';(a.output/'used-after-prefix.h').write_text(prefix)
 expr=(src/'typecheck_exprs.h').read_text();flow=(src/'typecheck_flow.h').read_text();methods='';bindings={}
 baseline_used=block((old/'typecheck_exprs.h').read_text(),'inline bool TypeCheck::UsedAfter(')
 candidate_used=block(expr,'inline bool TypeCheck::UsedAfter(')
 assert candidate_used.replace('        if (!NamesFrame(fi, vframe)) continue;\n','') == baseline_used
 assert digest(src/'ast.h') == digest(old/'ast.h') and digest(src/'clone.h') == digest(old/'clone.h')
 for text,head in ((flow,'inline int TypeCheck::FrameOfScope('),(flow,'inline bool TypeCheck::NamesFrame('),(flow,'inline int TypeCheck::FindBreakScope('),(expr,'inline bool TypeCheck::MentionsName('),(expr,'inline bool TypeCheck::EscapingContinue(')):
  value=block(text,head)
  baseline_text=(old/('typecheck_flow.h' if text is flow else 'typecheck_exprs.h')).read_text()
  assert value==block(baseline_text,head)
  bindings[head]=__import__('hashlib').sha256(value.encode()).hexdigest()
  value=value.replace('TypeCheck::','')
  if 'NamesFrame(' in head:value=value.replace('{','{\n++frame_queries;',1)
  if 'MentionsName(' in head:value=value.replace('bool MentionsName(', 'bool WalkMentionsName(',1)
  methods+=value+'\n'
 for path,name in ((old,'RawUsedAfter'),(src,'UsedAfter')):
  value=block((path/'typecheck_exprs.h').read_text(),'inline bool TypeCheck::UsedAfter(')
  methods+=value.replace('TypeCheck::UsedAfter',name)+'\n'
 (a.output/'used-after-methods.h').write_text(methods)
 report={'scope':'Actual AST/Children, UsedAfter, MentionsName, EscapingContinue, FrameOfScope, NamesFrame and FindBreakScope. Minimal projected frame/scope context; controlled Depth and LaterOperands inputs.', 'source_files':{str(root):{name:digest(root/name) for name in ('ast.h','clone.h','typecheck_exprs.h','typecheck_flow.h')} for root in (src,old)},'methods_sha256':digest(a.output/'used-after-methods.h'),'bindings':bindings,'fixture_sha256':digest(ROOT/'compiler-goose/tests/checker_tools/used_after_frames.cpp'),'runs':{}}
 for mode,flags in (('debug',[]),('release',['-DNDEBUG'])):
  binary=a.output/mode
  built=command(a,'compile-'+mode,[a.cxx,'-std=gnu++20','-O2',*flags,'-I'+str(a.output),ROOT/'compiler-goose/tests/checker_tools/used_after_frames.cpp','-o',binary],30)
  run=command(a,mode,[binary],30);report['runs'][mode]={'compile':built,'run':run,'binary_sha256':digest(binary)}
 (a.output/'receipt.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({k:v['run']['stdout'].strip() for k,v in report['runs'].items()}))
if __name__=='__main__':main()
