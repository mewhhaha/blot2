"""Turn every store the compiler can prove unique into an update, and check.

Usage: python3 scripts/integration/harvest_stores.py PROJECT_DIR ENTRY... [--compiler EXE] [--jobs N]

For each ENTRY (checked from PROJECT_DIR with its pen.json) the compiler
reports the stores whose place is provably the function's own
(BLOT_REPORT_STORES); each becomes `place := value`. Then the entries are
checked again: an update the compiler would turn back into a store
(`"kind":"store"`, an `aliased_update`) goes back to `=`, until none is
left. Files of std are left alone. It prints how many stores became
updates and any entry that has a diagnostic afterwards.
"""
import sys,subprocess,json,os,collections
from concurrent.futures import ThreadPoolExecutor
args=sys.argv[1:]
C=os.path.join(os.path.dirname(os.path.abspath(__file__)),'../../compiler-goose/build/blotc-goose-dev')
jobs=4
if '--compiler' in args:
    at=args.index('--compiler'); C=os.path.abspath(args[at+1]); del args[at:at+2]
if '--jobs' in args:
    at=args.index('--jobs'); jobs=int(args[at+1]); del args[at:at+2]
d=args[0]; entries=args[1:]
def run(entry,report):
    env=dict(os.environ)
    if report: env['BLOT_REPORT_STORES']='1'
    out=subprocess.run([C,'migrate-stores',entry,'--project','pen.json','--dry-run','--inference-budget','20000000'],cwd=d,capture_output=True,text=True,env=env).stdout
    provable=set(); aliased=set(); errors=set()
    for line in out.splitlines():
        try: r=json.loads(line)
        except ValueError: continue
        if r.get('kind')=='store': aliased.add((r['filename'],r['start']))
        elif r.get('kind')=='diagnostic' and r.get('code')=='unchecked' and r.get('stage')=='lower': provable.add((r['filename'],r['start']))
        elif r.get('kind')=='diagnostic' and r.get('code') not in ('dependency_failed','unknown_value','unchecked'): errors.add((entry,r.get('code')))
    return provable,aliased,errors
def sweep(report):
    provable=set(); aliased=set(); errors=set()
    with ThreadPoolExecutor(jobs) as pool:
        for p,a,e in pool.map(lambda entry: run(entry,report),entries): provable|=p; aliased|=a; errors|=e
    return provable,aliased,errors
def operator(src,start,want):
    """Offset of the statement's `=` (want b'=') or of the `:` of its `:=` (want b':=')."""
    nesting=0; at=start
    while at+1<len(src):
        b=src[at:at+1]
        if b in b'([{': nesting+=1
        elif b in b')]}':
            if nesting>0: nesting-=1
        elif b==b'"':
            at+=1
            while at<len(src) and src[at:at+1]!=b'"':
                if src[at:at+1]==b'\\': at+=1
                at+=1
        elif b==b'\n':
            if nesting==0: return -1
        elif nesting==0 and want==b':=' and src[at:at+2]==b':=': return at
        elif nesting==0 and want==b'=' and b==b'=':
            prev=src[at-1:at]; nxt=src[at+1:at+2]
            if prev not in b':=<>!' and nxt not in b'=>': return at
        at+=1
    return -1
before,_,errors_before=sweep(False)[0],None,None
provable,_,_=sweep(True)
by=collections.defaultdict(set)
for f,s in provable:
    if '/std/' in f and '/blot2/' in f: continue
    by[f].add(s)
made=0
for f,starts in by.items():
    src=open(f,'rb').read()
    for s in sorted(starts,reverse=True):
        at=operator(src,s,b'=')
        if at<0: continue
        src=src[:at]+b':'+src[at:]; made+=1
    open(f,'wb').write(src)
back=0
for attempt in range(6):
    _,aliased,errors=sweep(False)
    if not aliased: break
    again=collections.defaultdict(set)
    for f,s in aliased: again[f].add(s)
    for f,starts in again.items():
        src=open(f,'rb').read()
        for s in sorted(starts,reverse=True):
            at=operator(src,s,b':=')
            if at<0: continue
            src=src[:at]+src[at+1:]; back+=1
        open(f,'wb').write(src)
print(f'{made-back} stores became updates ({made} tried, {back} put back)')
for entry,code in sorted(errors): print('  diagnostic after:',entry,code)
