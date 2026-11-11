import subprocess, sys, collections, re
dump, binary = sys.argv[1], sys.argv[2]
stacks=[];maps=[];inm=False
for line in open(dump):
    if line.startswith('maps'): inm=True; continue
    if inm:
        p=line.split()
        if len(p)>=6:
            lo,hi=(int(x,16) for x in p[0].split('-')); maps.append((lo,hi,int(p[2],16),p[5]))
        continue
    if line.startswith('stack'):
        p=line.split(); stacks.append((int(p[1]),[int(x,16) for x in p[3:]]))
def loc(a):
    for lo,hi,off,path in maps:
        if lo<=a<hi: return path,a-lo+off
    return None,None
offs=sorted({loc(a)[1]-1 for _,fr in stacks for a in fr[:6] if (loc(a)[0] or '').endswith('/goose')})
out=subprocess.run(['llvm-symbolizer','--obj='+binary,'--functions=short','--demangle','--inlines']+[hex(x) for x in offs],capture_output=True,text=True).stdout.strip().split('\n\n')
chain={}
for o,block in zip(offs,out):
    ls=block.split('\n'); chain[o]=[(ls[i],ls[i+1].rsplit('/',1)[-1]) for i in range(0,len(ls)-1,2)]
skip=re.compile(r'^(std::|operator new|__gnu_cxx|_M_|allocate|emplace_back|push_back|resize|reserve|insert|operator\[\]|_M_realloc|construct|make_unique|_Hashtable|try_emplace|__)')
g=collections.Counter()
for w,fr in stacks:
    key=None
    for a in fr[:6]:
        p,o=loc(a)
        if not (p or '').endswith('/goose'): continue
        for fn,l in chain.get(o-1,[]):
            if not skip.match(fn): key=f'{fn}@{l}'; break
        if key: break
    g[key or '?']+=w
tot=sum(g.values())
for k,w in g.most_common(15): print(f'{w/2**20:8.0f} MiB {100*w/tot:5.1f}%  {k}')
