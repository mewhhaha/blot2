"""Replace names for parts of the world by their paths, in any block.

Usage: python3 scripts/integration/paths_for_parts.py FILE...   (paths under ../gdev)

A block that binds `let NAME: T = WORLD.FIELD` and goes on to read or write
through NAME, while it also hands WORLD to an `own` parameter, keeps WORLD
lent for as long as NAME is read. This replaces each use of NAME in the
block by `WORLD.FIELD` and drops the binding, unless NAME is bound again in
the block or a lambda in it binds WORLD itself. Stores stay stores; the
compiler decides later which can be updates. unalias.py does the same in
functions that take the world with `own`, with a check after each file;
this one covers test lambdas and leaves the checking to the caller.

Do not use it where a name gives a growable field its type: pushes and
slices through `WORLD.FIELD.rows` do not type check when WORLD has no
written type. Bind the name again after the hand-over instead.
"""
import re,sys,os
sys.path.insert(0,os.path.dirname(os.path.abspath(__file__)))
import ownify
ROOT=ownify.ROOT
def indent(l): return len(l)-len(l.lstrip(' '))
def replace(line,name,path):
    """Each use of `name` in `line` as a value: not a field after a single
    dot, not a record key (`name: value` stays a key), and a shorthand
    field (`{name}`) becomes `name: path`."""
    out=''; at=0
    for m in re.finditer(r'\b'+re.escape(name)+r'\b',line):
        s,e=m.start(),m.end()
        before=line[:s]
        if re.search(r'[\w$]$',before) or (before.endswith('.') and not before.endswith('..')): continue
        after=line[e:]
        if re.match(r'\s*:(?!=)',after): continue
        shorthand=re.search(r'[{,]\s*$',before) and re.match(r'\s*[,}]',after)
        out+=line[at:s]+(f'{name}: {path}' if shorthand else path); at=e
    return out+line[at:]
def rewrite(lines):
    changed=0; k=0
    while k<len(lines):
        m=re.match(r'^(\s+)let (\w+): [\w.]+(?: [\w.]+)* = (access|world|original|framed)\.(\w+)\s*$',lines[k])
        if not m: k+=1; continue
        ind=len(m.group(1)); name,world,field=m.group(2),m.group(3),m.group(4)
        j=k+1
        while j<len(lines) and (not lines[j].strip() or indent(lines[j])>=ind): j+=1
        block=lines[k+1:j]
        text='\n'.join(block)
        if re.search(r'\blet '+name+r'\b|\b'+name+r' :=|\bfunc\b[^=]*\b'+world+r'\b[^=]*=>|\(own '+world+r'\)',text) and not re.search(r'\b'+world+r' :=',text) is None:
            pass
        if re.search(r'\blet '+name+r'\b|^\s*'+name+r' :=',text,re.M) or re.search(r'\bfunc\b[^\n]*?\b'+world+r'\b[^\n]*?=>',text):
            k+=1; continue
        new=[replace(l,name,world+'.'+field) for l in block]
        lines[k:j]=new; changed+=1
    return changed
if __name__=='__main__':
    total=0
    for rel in sys.argv[1:]:
        path=os.path.join(ROOT,rel); lines=open(path).read().split('\n')
        n=rewrite(lines)
        if n: open(path,'w').write('\n'.join(lines)); print(f'{rel}: {n} names')
        total+=n
    print(f'{total} names replaced by paths')
