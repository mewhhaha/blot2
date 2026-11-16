"""Count the functions of ../gdev/src that take the world and write through it.

Usage: python3 scripts/integration/world_writers.py

A function writes directly when its body has a store or a push by line
shape, and through a call when it passes `access` to one that does (calls
are matched by name through the module's imports, so it is approximate). The
list goes to build/scratch/gdev-writers.json. It sizes the systems layer of
tasks/MEMORY_MODEL.md.
"""
import re,glob,os,collections,json
root='/home/user/gdev/src'
defs={}   # (module, name) -> dict
mods={}
for f in sorted(glob.glob(root+'/**/*.blot',recursive=True)):
    mod=os.path.relpath(f,root)[:-5]
    s=open(f).read(); L=s.split('\n')
    imports={}
    for m in re.finditer(r'^import \* as (\w+) from "([^"]+)"',s,re.M):
        t=m.group(2)
        if t.startswith('game/'): imports[m.group(1)]=t[5:]
        elif t.startswith('.'): imports[m.group(1)]=os.path.normpath(os.path.join(os.path.dirname(mod),t))
    mods[mod]=imports
    i=0
    while i<len(L):
        m=re.match(r'^(lent )?(entry )?func ([\w.]+) (.*)$',L[i])
        if m:
            j=i+1
            while j<len(L) and (L[j].startswith((' ','\t')) or L[j]==''): j+=1
            head=L[i]; body='\n'.join(L[i:j])
            params=head.split('=>')[0]
            takes=bool(re.search(r'(\(own access\)|\(access: [^)]*\)|(?<![\w.])access(?![\w.]))',params))
            own=bool(re.search(r'\(own access\)|\(access: own ',params))
            defs[(mod,m.group(3))]={'file':f,'line':i+1,'takes':takes,'own':own,'body':body,'lent':bool(m.group(1))}
            i=j
        else: i+=1
def direct(body):
    for line in body.split('\n')[1:]:
        t=line.split('//')[0]
        if re.match(r'^\s*(lent|let|const|type|func|entry|infix|infixl|infixr|import|data|export|private|impl|case|if|for|return|break|use)\b',t): continue
        if re.match(r'^\s*[A-Za-z_(][^=!<>:]*[^=!<>:\s]\s=\s[^=>]',t) and '=>' not in t.split(' = ')[0]: return True
        if re.search(r'\.(push|truncate|pop)\b|@storage\.(push|truncate|pop)\b',t): return True
    return False
W=set(k for k,d in defs.items() if d['takes'] and direct(d['body']))
print('functions',len(defs),'take access',sum(d['takes'] for d in defs.values()),'direct writers',len(W))
changed=True
calls={}
for k,d in defs.items():
    mod=k[0]; c=set()
    for m in re.finditer(r'(?<![\w.$])(?:(\w+)\.)?(\w+)((?: [^\s()]+)*?) access(?![\w.])',d['body']):
        q,name=m.group(1),m.group(2)
        if q and q in mods[mod]: c.add((mods[mod][q],name))
        elif not q: c.add((mod,name))
    calls[k]=c
while changed:
    changed=False
    for k,d in defs.items():
        if k in W or not d['takes']: continue
        if any(c in W for c in calls[k]): W.add(k); changed=True
print('writers through calls too',len(W),'already own',sum(defs[k]['own'] for k in W))
bym=collections.Counter(k[0] for k in W)
print(len(bym),'modules;', bym.most_common(12))
json.dump(sorted([list(k) for k in W]),open('/home/user/blot2/build/scratch/gdev-writers.json','w'))
