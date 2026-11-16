"""Count the stores `place = value` left in Blot sources, by line shape.

Usage: python3 scripts/integration/count_stores.py DIR...

It is the progress count for removing `=` (tasks/MEMORY_MODEL.md). The
shape is a line that starts with a place and has ` = ` outside a
declaration, so it is approximate: a store split over lines counts once,
and a record field written on its own line can count by mistake.
"""
import re,glob,sys,collections
def stores(root):
    n=0; files=0; per=collections.Counter()
    for f in glob.glob(root+'/**/*.blot',recursive=True):
        if '/output/' in f or '/build/' in f: continue
        k=0
        for line in open(f,errors='replace'):
            s=line.split('//')[0]
            if re.match(r'^\s*(let|const|type|func|entry|infix|infixl|infixr|import|data|export|private|impl|case|if|for|return|break|use)\b',s): continue
            if re.match(r'^\s*[A-Za-z_(][^=!<>:]*[^=!<>:\s]\s=\s[^=>]',s) and '=>' not in s.split(' = ')[0]: k+=1
        if k: files+=1; per[f]=k
        n+=k
    return n,files,per
tot=0
for d in sys.argv[1:]:
    n,files,per=stores(d); tot+=n
    print(f'{d}: {n} stores in {files} files; largest: '+', '.join(f"{f.split('/')[-1]} {k}" for f,k in per.most_common(4)))
print('total',tot)
