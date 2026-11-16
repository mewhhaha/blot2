"""Count the stores `place = value` and the `lent` functions left in Blot
sources, by line shape.

Usage: python3 scripts/integration/count_stores.py DIR...

It is the progress count for removing `=` (tasks/MEMORY_MODEL.md). The
shape is a line that starts with a place and has ` = ` outside a
declaration, so it is approximate: a store split over lines counts once,
and a record field written on its own line can count by mistake. A `lent`
function is one that still returns or keeps what it was lent.
"""
import re,glob,sys,collections
def stores(root):
    n=0; files=0; lent=0; per=collections.Counter()
    for f in glob.glob(root+'/**/*.blot',recursive=True):
        if '/output/' in f or '/build/' in f: continue
        k=0
        for line in open(f,errors='replace'):
            s=line.split('//')[0]
            if s.startswith('lent '): lent+=1
            if re.match(r'^\s*(lent|let|const|type|func|entry|infix|infixl|infixr|import|data|export|private|impl|case|if|for|return|break|use)\b',s): continue
            if re.match(r'^\s*[A-Za-z_(][^=!<>:]*[^=!<>:\s]\s=\s[^=>]',s) and '=>' not in s.split(' = ')[0]: k+=1
        if k: files+=1; per[f]=k
        n+=k
    return n,files,per,lent
tot=0; marks=0
for d in sys.argv[1:]:
    n,files,per,lent=stores(d); tot+=n; marks+=lent
    print(f'{d}: {n} stores in {files} files, {lent} lent functions; largest: '+', '.join(f"{f.split('/')[-1]} {k}" for f,k in per.most_common(4)))
print('total',tot,'stores,',marks,'lent functions')
