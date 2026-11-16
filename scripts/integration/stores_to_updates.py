"""Turn each store `place = value` whose place is provably unique into `place := value`.

Usage: python3 scripts/integration/stores_to_updates.py PROJECT_DIR ENTRY... [--compiler EXE]

PROJECT_DIR has the pen.json; each ENTRY is checked from there with
BLOT_REPORT_STORES set, and the compiler reports those stores as `unchecked`
(tasks/MEMORY_MODEL.md, "Phase 2 is the default"). Files of std are left
alone. Afterwards run `blotc migrate-stores ENTRY --project pen.json --dry-run`
and look for `"kind":"store"`: a `:=` that became a loop carry can be
rejected, and that site goes back to `=` by hand.
"""
import sys,subprocess,json,os,re,collections
args=sys.argv[1:]
C=os.path.join(os.path.dirname(os.path.abspath(__file__)),'../../compiler-goose/build/blotc-goose')
if '--compiler' in args:
    at=args.index('--compiler'); C=os.path.abspath(args[at+1]); del args[at:at+2]
d=args[0]; entries=args[1:]
def report(entry):
    env=dict(os.environ); env['BLOT_REPORT_STORES']='1'
    out=subprocess.run([C,'migrate-stores',entry,'--project','pen.json','--dry-run','--inference-budget','20000000'],cwd=d,capture_output=True,text=True,env=env).stdout
    sites=set()
    for line in out.splitlines():
        try: r=json.loads(line)
        except ValueError: continue
        if r.get('kind')=='diagnostic' and r.get('code')=='unchecked' and r.get('stage')=='lower':
            sites.add((r['filename'],r['start']))
    return sites
def operator(src,start):
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
        elif b==b'=' and nesting==0:
            prev=src[at-1:at]; nxt=src[at+1:at+2]
            if prev not in b':=<>!' and nxt not in b'=>': return at
        at+=1
    return -1
total=0
sites=set()
for e in entries: sites|=report(e)
by=collections.defaultdict(list)
for f,s in sites:
    if '/std/' in f and '/blot2/' in f: continue
    by[f].append(s)
for f,starts in by.items():
    src=open(f,'rb').read()
    for s in sorted(set(starts),reverse=True):
        at=operator(src,s)
        if at<0: print('no operator',f,s); continue
        src=src[:at]+b':'+src[at:]; total+=1
    open(f,'wb').write(src)
print('rewritten',total,'in',len(by),'files')
