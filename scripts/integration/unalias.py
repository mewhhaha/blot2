"""Turn stores through names for parts of the world into updates of the world.

Usage: python3 scripts/integration/unalias.py [--dry] FILE...   (paths under ../gdev)

In a function that takes the world with `own`, `let stacks: Array Stack =
access.salt.stacks` followed by `stacks[i] = value` writes through a name
that only borrows. This replaces each use of such a name by the path it
names and makes the stores updates: `access.salt.stacks[i] := value`. A
store written straight through `access` becomes an update too.

A name is left alone when it is used inside a lambda (an update cannot
rebind what a lambda captured), when it is rebound, or when another name
is bound from it. After a file is rewritten it is checked through
src/main.blot; a function that no longer checks is put back as it was and
reported. (tasks/MEMORY_MODEL.md, "Next: the systems".)
"""
import re,sys,os,subprocess,json
sys.path.insert(0,os.path.dirname(os.path.abspath(__file__)))
import ownify
ROOT=ownify.ROOT
COMPILER=os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)),'../../compiler-goose/build/blotc-goose-dev'))
def functions(lines):
    k=0
    while k<len(lines):
        if re.match(r'^(lent )?(entry )?func [\w.]+ ',lines[k]):
            j=k+1
            while j<len(lines) and (lines[j].startswith(' ') or lines[j]==''): j+=1
            while j>k+1 and lines[j-1]=='': j-=1
            yield k,j; k=j
        else: k+=1
def lambda_lines(body):
    """Indices of body lines that are inside a lambda that goes on over lines."""
    inside=set(); nested=[]
    for i,l in enumerate(body):
        st=l.split('//')[0].strip(); ind=ownify.indent(l)
        while nested and st and ind<=nested[-1]: nested.pop()
        if nested: inside.add(i)
        code=st
        opened=code.count('(')+code.count('[')+code.count('{')-code.count(')')-code.count(']')-code.count('}')
        if st and re.search(r'\bfunc\b.*=>',code) and (opened>0 or re.search(r'(do:|\bof|=> return)$',code)): nested.append(ind)
        elif st and re.search(r'\bfunc\b.*=>',code): inside.add(i)   # a lambda on one line
    return inside
STORE=re.compile(r'^(\s*)((?:[A-Za-z_]\w*)(?:\.\w+|\[[^=]*?\])+) = (.*)$')
def rewrite(body):
    """The body with its part names replaced, and how many stores became updates."""
    inside=lambda_lines(body)
    names={}
    for i,l in enumerate(body):
        m=re.match(r'^(\s+)let (\w+)(?:: [^=]+)? = (access(?:\.\w+)+)\s*$',l.split('//')[0].rstrip())
        if m and i not in inside: names[m.group(2)]=(i,m.group(3))
    text='\n'.join(body)
    drop=set(); use={}
    for name,(at,path) in names.items():
        ok=True
        for i,l in enumerate(body):
            if i==at: continue
            code=l.split('//')[0]
            if not re.search(r'(?<![\w.])'+name+r'(?![\w])',code): continue
            if i in inside: ok=False; break
            if re.match(r'^\s*'+name+r' :?= ',code) or re.match(r'^\s*let \w+(?:: [^=]+)? = '+name+r'\s*$',code.rstrip()): ok=False; break
            if re.match(r'^\s*let '+name+r'\b',code): ok=False; break     # shadowed
        if ok: use[name]=path; drop.add(at)
    out=[]; changed=0
    for i,l in enumerate(body):
        if i in drop: continue
        code=l; comment=''
        if '//' in l: code=l[:l.index('//')]; comment=l[l.index('//'):]
        if i not in inside:
            for name,path in use.items():
                code=re.sub(r'(?<![\w.])'+name+r'(?![\w])',path,code)
            # the intrinsic form needs a known type; the method waits for the record's
            code=re.sub(r'@storage\.(push|truncate) (access(?:\.\w+)+) ',r'\2.\1 ',code)
            m=STORE.match(code.rstrip())
            if m and m.group(2).startswith('access.') and '[' in m.group(2) or (m and m.group(2).startswith('access.') and m.group(2).count('.')>=2):
                code=f'{m.group(1)}{m.group(2)} := {m.group(3)}'; changed+=1
        out.append(code+comment)
    return out,changed,len(drop)
def check():
    out=subprocess.run([COMPILER,'migrate-stores','src/main.blot','--project','pen.json','--dry-run','--inference-budget','20000000'],cwd=ROOT,capture_output=True,text=True).stdout
    bad=[]
    for line in out.split('\n'):
        try: r=json.loads(line)
        except ValueError: continue
        if r.get('kind')=='diagnostic' and r['code'] not in ('dependency_failed','unknown_value'): bad.append((os.path.normpath(r['filename']),r['start'],r['code']))
        # migrate-stores reports an update it would turn back into a store this way
        if r.get('kind')=='store': bad.append((os.path.normpath(r['filename']),r['start'],'aliased_update'))
    return bad
def main():
    args=sys.argv[1:]; dry='--dry' in args
    if dry: args.remove('--dry')
    total=0; kept=0; back=0
    for rel in args:
        path=os.path.join(ROOT,rel); lines=open(path).read().split('\n'); original=list(lines)
        spans=[(k,j) for k,j in functions(lines) if re.search(r'\(own access\)|\(access: own ',lines[k])]
        edits=[]
        for k,j in reversed(spans):
            body,changed,dropped=rewrite(lines[k+1:j])
            if changed or dropped: edits.append([k,j,lines[k+1:j],body,changed]); lines[k+1:j]=body
        if not edits: continue
        if dry: total+=sum(e[4] for e in edits); continue
        open(path,'w').write('\n'.join(lines))
        bad=[b for b in check() if b[0]==os.path.normpath(path)]
        attempts=0
        while bad and attempts<len(edits)+1:
            # put back each function a diagnostic points into
            text='\n'.join(lines); offsets=[0]
            for l in lines: offsets.append(offsets[-1]+len(l.encode())+1)
            hit=set()
            for _,start,code in bad:
                row=max(i for i,o in enumerate(offsets) if o<=start)
                for k,j in functions(lines):
                    if k<=row<j: hit.add(lines[k])
            if not hit: break
            for k,j in list(functions(lines))[::-1]:
                if lines[k] in hit:
                    for e in edits:
                        if original[e[0]]==lines[k]:
                            lines[k+1:j]=e[2]; back+=1; print(f'  put back {rel}: {lines[k][:90]}  ({", ".join(sorted(set(c for _,_,c in bad)))})'); e[4]=0
            open(path,'w').write('\n'.join(lines))
            bad=[b for b in check() if b[0]==os.path.normpath(path)]; attempts+=1
        if bad:
            open(path,'w').write('\n'.join(original)); print(f'  {rel}: put back whole file ({bad[0][2]})'); continue
        total+=sum(e[4] for e in edits)
    print(f'{total} stores became updates; {back} functions put back')
if __name__=='__main__': main()
