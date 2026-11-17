"""Pick and convert a set of Gdev functions that take the world lent, closed
under their callers.

Usage: python3 scripts/integration/own_closure.py [--dry] [--seed FILE] [--max N] [--skip MODULE.FUNCTION]...
       python3 scripts/integration/own_closure.py --cases

A function that takes the world with `own` can only be called where the
caller owns the world. So a set is converted together: starting from the
functions that own-world functions call as a statement (or the names in
FILE, one `module.function` a line), every function a member is called from
joins the set, until each call of a member stands in a function that owns
the world or is a member. A function is left out, with everything that
needs it, when it cannot be converted mechanically: it returns a value (a
call of it is used as one), it is `lent`, it is passed as a value, or a
call of it gives a world captured by a closure.

Before the conversion (ownify.py) the calls it cannot rewrite in place are
given the shape it can: an arm `pattern => f access x` becomes a block, and
`break f access x` inside a block becomes the call and `break ()`.

It prints the set, what was left out and why, and what ownify could not
place; --dry stops before writing.
"""
import re,sys,os,glob,collections
sys.path.insert(0,os.path.dirname(os.path.abspath(__file__)))
import ownify
ROOT=ownify.ROOT; SRC=os.path.join(ROOT,'src')+os.sep
def rel(path): return os.path.relpath(path,ROOT)
def module(path): return rel(path)[:-5]
TOP=re.compile(r'^(lent )?(entry )?func ([\w.]+)(?: |$)')
def owns(head,name):
    return bool(re.search(r'\(own '+re.escape(name)+r'\)|\('+re.escape(name)+r': own ',head))
def has_param(head,name):
    h=ownify.header(head)
    if not h: return False
    return any(a==name or re.match(r'^\('+re.escape(name)+r': ',a) or a==f'(own {name})' for a in h[0])
def lambda_params(code):
    """Names bound by the last `func ... =>` on a line."""
    cut=code.rfind('func ')
    if cut<0: return set()
    text=code[cut+5:]; end=text.find('=>')
    if end<0: return set()
    names=set()
    for a in ownify.split_arrows(text[:end]):
        m=re.match(r'^\(?(?:own )?(\w+)',a)
        if m: names.add(m.group(1))
    return names
class Scan:
    """Per file: for each line its top-level function and the lambdas open there."""
    cache={}
    def __init__(self,f):
        self.f=f; L=f.lines; self.top=[-1]*len(L); self.stack=[()]*len(L)
        current=-1; nested=[]
        for k,l in enumerate(L):
            if l and not l.startswith(' ') and not l.startswith('//'):
                current=k if re.match(r'^(lent )?(entry )?(func|const) ',l) else -1; nested=[]
            st=l.split('//')[0].strip(); ind=ownify.indent(l)
            while nested and st and ind<=nested[-1][0]: nested.pop()
            self.top[k]=current; self.stack[k]=tuple(nested)
            code=st
            opened=code.count('(')+code.count('[')+code.count('{')-code.count(')')-code.count(']')-code.count('}')
            if st and re.search(r'\bfunc\b.*=>',code) and (opened>0 or re.search(r'(do:|\bof|=> return)$',code)) and not (k==current and TOP.match(l)):
                nested.append((ind,frozenset(lambda_params(code)),'(own ' in code[code.rfind('func '):] or bool(re.search(r'\.run \(func ',code))))
    @staticmethod
    def get(f):
        if f.path not in Scan.cache: Scan.cache[f.path]=Scan(f)
        return Scan.cache[f.path]
def names_for(f,target,fn):
    names=[a+'.'+fn for a,p in f.imports.items() if os.path.normpath(p)==target]
    if os.path.normpath(f.path)==target: names.append(fn)
    for l in f.lines:
        m=re.match(r'^import \{([^}]*)\} from "([^"]+)"',l)
        if m and os.path.normpath(ownify.resolve(f.path,m.group(2)))==target and fn in [x.strip() for x in m.group(1).split(',')]: names.append(fn)
    return names
FILES=None
def files():
    global FILES
    if FILES is None:
        FILES=[]
        for d in ownify.DIRS:
            for path in sorted(glob.glob(os.path.join(ROOT,d,'**','*.blot'),recursive=True)): FILES.append(ownify.File.get(path))
    return FILES
def sites(mod,fn,position):
    """Each call of mod.fn: (file, line index, kind, argument name, name used)."""
    target=os.path.normpath(os.path.join(ROOT,mod+'.blot'))
    for f in files():
        names=names_for(f,target,fn)
        if not names: continue
        for k,l in enumerate(f.lines):
            code=l.split('//')[0]
            for nm in names:
                for m in re.finditer(r'(?<![\w.$])'+re.escape(nm)+r'(?![\w.])',code):
                    is_def=nm==fn and os.path.normpath(f.path)==target and TOP.match(l) and TOP.match(l).group(3)==fn and m.start()<len(TOP.match(l).group(0))+1
                    if is_def: continue
                    st=code.strip()
                    if st.startswith('import '): continue
                    after=code[m.end():]
                    if not ('.' in nm or re.match(r' +[\w(]',after)) or re.match(r' +(=|:=|\+|-|\*|/|<|>|!=|and\b|or\b|then\b|else\b|=>|->)',after):
                        # the function as a value: `module.f` alone, or the bare name
                        # in a record, an argument list or at the end of a line
                        if '.' in nm and not re.match(r' +[\w(]',after): yield f,k,'value',None,nm
                        elif '.' not in nm and re.match(r'\s*([,})\]]|$)',after) and not re.match(r'^\s*(let|for) ',code) and not re.search(r'[.]$',code[:m.start()]): yield f,k,'value',None,nm
                        continue
                    a=ownify.atoms(after)
                    arg=a[position] if len(a)>position else None
                    simple=bool(arg) and bool(re.fullmatch(r'[a-z_]\w*',arg))
                    body=st[4:] if st.startswith('use '+nm+' ') else st
                    if re.match(r'^\w+ := '+re.escape(nm)+r'\b',st): kind='rebound'
                    elif body.startswith(nm+' ') or body==nm: kind='stmt'
                    elif re.match(r'^(return|break) '+re.escape(nm)+r'\b',st): kind='tail'
                    elif TOP.match(l) and re.search(r'=> return '+re.escape(nm)+r'\b',code) and code.count('=>')==len(re.findall(r'=> return func ',code))+1: kind='tail'
                    elif re.search(r'=> '+re.escape(nm)+r'\b',code) and code[:m.start()].rstrip().endswith('=>') and 'func ' not in code[:m.start()]: kind='arm'
                    else: kind='value'
                    if kind!='value' and not simple: kind='value'
                    yield f,k,kind,arg,nm
def binder(f,k,arg):
    """Who binds `arg` at line k: ('top', line) | ('lambda', owns) | ('captured',) | ('none',)."""
    scan=Scan.get(f)
    stack=scan.stack[k]
    for ind,params,own in reversed(stack):
        if arg in params: return ('lambda',own)
    top=scan.top[k]
    if top<0: return ('none',)
    if stack: return ('captured',top)
    return ('top',top)
def candidates():
    """Functions of src that own-world functions call as a statement with the world."""
    out=collections.OrderedDict()
    for f in files():
        if not f.path.startswith(SRC): continue
        scan=Scan.get(f)
        for k,l in enumerate(f.lines):
            top=scan.top[k]
            if top<0 or top==k or not owns(f.lines[top],'access') or scan.stack[k]: continue
            st=l.split('//')[0].strip()
            m=re.match(r'^(?:use )?((?:\w+\.)?\w+) (.*)$',st)
            if not m or re.match(r'^(if|for|while|let|return|break|case|else|use \w+ <-)\b',st) or ' := ' in st.split('(')[0] or ' = ' in st: continue
            if 'access' not in ownify.atoms(m.group(2)): continue
            q,_,fn=m.group(1).rpartition('.')
            target=f.imports.get(q) if q else f.path
            if not target or not os.path.normpath(target).startswith(SRC) or not os.path.exists(target): continue
            g=ownify.File.get(target); d=g.find(fn)
            if d>=0 and not owns(g.lines[d],'access') and has_param(g.lines[d],'access'): out[(module(target),fn,'access')]=True
    return list(out)
def position_of(mod,fn,name):
    f=ownify.File.get(os.path.join(ROOT,mod+'.blot')); k=f.find(fn)
    if k<0: return None,'no definition'
    line=f.lines[k]
    if line.startswith('lent '): return None,'lent'
    h=ownify.header(line)
    if not h: return None,'header not understood'
    for at,a in enumerate(h[0]):
        if a==name or re.match(r'^\('+re.escape(name)+r': ',a) or a==f'(own {name})':
            if a!=f'(own {name})' and not re.match(r'^\('+re.escape(name)+r': own ',a) and not ownify.owned_param(a,name): return None,'parameter '+a
            return at,None
    return None,'no parameter '+name
def close(seed,limit,skip=()):
    members=collections.OrderedDict((s,True) for s in seed); out={}
    for item in skip:
        mod,_,fn=item.rpartition('.'); out[(mod,fn,'access')]='skipped by hand'; members[(mod,fn,'access')]=True
    changed=True
    while changed:
        changed=False
        for key in list(members):
            if key in out: continue
            mod,fn,name=key
            position,why=position_of(mod,fn,name)
            if position is None: out[key]=why; changed=True; continue
            for f,k,kind,arg,nm in sites(mod,fn,position):
                where=f'{rel(f.path)}:{k+1}'
                if kind=='rebound': continue
                if kind=='value':
                    # a test that reads a result decides nothing about src's own callers,
                    # but a result that is read means the function returns one
                    out[key]=f'used as a value at {where}'; changed=True; break
                who=binder(f,k,arg)
                if who[0]=='lambda':
                    if who[1] or not f.path.startswith(SRC): continue
                    out[key]=f'given a lambda\'s parameter at {where}'; changed=True; break
                if who[0]=='captured':
                    if not f.path.startswith(SRC): continue
                    out[key]=f'given a captured world at {where}'; changed=True; break
                if who[0]=='none': out[key]=f'called outside a function at {where}'; changed=True; break
                head=f.lines[who[1]]
                if owns(head,arg): continue
                t=TOP.match(head)
                if not t or not has_param(head,arg):
                    if not f.path.startswith(SRC): continue
                    out[key]=f'{arg} is not a parameter at {where}'; changed=True; break
                caller=(module(f.path),t.group(3),arg)
                if caller in out: out[key]=f'needs {caller[0]}.{caller[1]} ({out[caller][:60]})'; changed=True; break
                if caller not in members:
                    if len(members)>=limit: out[key]=f'needs {caller[0]}.{caller[1]} (over the limit)'; changed=True; break
                    members[caller]=True; changed=True
    return [k for k in members if k not in out],out
def reshape(chosen):
    """Arms and inner breaks that call a member: give them a statement to rewrite."""
    count=0
    member={(m,f) for m,f,_ in chosen}
    for key in chosen:
        mod,fn,name=key
        position,_=position_of(mod,fn,name)
        again=True
        while again:
            again=False
            for f,k,kind,arg,nm in sites(mod,fn,position):
                l=f.lines[k]; code=l.split('//')[0].rstrip(); ind=ownify.indent(l)
                scan=Scan.get(f); top=scan.top[k]
                if top<0: continue
                if kind=='arm':
                    cut=code.find('=> '+nm)
                    f.lines[k:k+1]=[code[:cut]+'=> do:',' '*(ind+2)+code[cut+3:]]
                elif kind=='tail' and code.strip().startswith('break ') and inner(f,k,top):
                    f.lines[k:k+1]=[' '*ind+code.strip()[6:],' '*ind+'break ()']
                else: continue
                f.dirty=True; count+=1; Scan.cache.pop(f.path,None); again=True; break
    return count
def statement_cases():
    """`let _ = case ...` whose arms rebind the world is a statement: an
    expression's arms would leave the rebinding behind."""
    count=0; Scan.cache.clear()
    for f in files():
        scan=Scan.get(f)
        for k,l in enumerate(f.lines):
            m=re.match(r'^(\s+)let _ = (case\b.*)$',l)
            if not m: continue
            top=scan.top[k]
            if top<0: continue
            head=f.lines[top]
            names=[a for a in ('access','framed','world') if owns(head,a)]
            ind=len(m.group(1)); j=k+1; rebinds=False
            while j<len(f.lines) and (not f.lines[j].strip() or ownify.indent(f.lines[j])>ind):
                if any(re.match(r'^\s+'+n+r' := ',f.lines[j]) for n in names): rebinds=True
                j+=1
            if rebinds: f.lines[k]=m.group(1)+m.group(2); f.dirty=True; count+=1
    return count
def returns_for_breaks():
    """In a function that owns the world and ends `case ... of` then `return
    access`, an arm that rebinds the world cannot also leave early with
    `break`. Leaving the arm there is leaving the function, so each `break`
    in the arms becomes a `return`: `access := f access x` then `break ()`
    is `return f access x`, `break ()` is `return access`, and `break call`
    is the call and `return access`."""
    count=0; Scan.cache.clear()
    for f in files():
        k=0
        while k<len(f.lines):
            head=f.lines[k]; t=TOP.match(head)
            if not t or not head.rstrip().endswith('=> return do:'): k+=1; continue
            names=[a for a in ('access','framed','world') if owns(head,a)]
            j=f.end(k)
            if not names or j-k<3: k=j; continue
            name=names[0]; body=range(k+1,j)
            base=next((ownify.indent(f.lines[i]) for i in body if f.lines[i].strip()),2)
            last=max(i for i in body if f.lines[i].strip())
            if f.lines[last].strip()!='return '+name: k=j; continue
            # the statement before the last return, at the body's own indent
            start=last-1
            while start>k and (not f.lines[start].strip() or ownify.indent(f.lines[start])>base): start-=1
            if not re.match(r'^\s*case\b.* of$',f.lines[start].split('//')[0].rstrip()) or ownify.indent(f.lines[start])!=base: k=j; continue
            lines=f.lines[start+1:last]
            if not any(re.match(r'^\s+'+name+r' := ',l) for l in lines) or not any(re.match(r'^\s+break\b',l) for l in lines): k=j; continue
            out=[]; nested=[]; i=0; changed=0
            while i<len(lines):
                l=lines[i]; st=l.split('//')[0].strip(); ind=ownify.indent(l)
                while nested and st and ind<=nested[-1]: nested.pop()
                code=st
                opened=code.count('(')+code.count('[')+code.count('{')-code.count(')')-code.count(']')-code.count('}')
                if nested: out.append(l); i+=1; continue
                if st and re.search(r'\bfunc\b.*=>',code) and (opened>0 or re.search(r'(do:|\bof|=> return)$',code)): nested.append(ind)
                m=re.match(r'^'+name+r' := (.*)$',st)
                nxt=lines[i+1].split('//')[0].strip() if i+1<len(lines) else ''
                if m and nxt=='break ()' and ownify.indent(lines[i+1])==ind and opened==0:
                    out.append(' '*ind+'return '+m.group(1)); i+=2; changed+=1; continue
                if st=='break ()': out.append(' '*ind+'return '+name); i+=1; changed+=1; continue
                m=re.match(r'^break (.+)$',st)
                if m and opened==0:
                    out.append(' '*ind+m.group(1)); out.append(' '*ind+'return '+name); i+=1; changed+=1; continue
                out.append(l); i+=1
            if changed:
                f.lines[start+1:last]=out; f.dirty=True; count+=changed
                j=f.end(k)
            k=j
    return count
def inner(f,k,top):
    """Whether line k is inside a block of its function, not in its own block."""
    base=None
    for l in f.lines[top+1:k+1]:
        if l.strip(): base=ownify.indent(l); break
    return base is not None and ownify.indent(f.lines[k])>base
if __name__=='__main__':
    args=sys.argv[1:]; dry='--dry' in args
    if dry: args.remove('--dry')
    limit=10**6
    if '--max' in args: at=args.index('--max'); limit=int(args[at+1]); del args[at:at+2]
    if '--seed' in args:
        at=args.index('--seed'); seed=[]
        for item in open(args[at+1]).read().split():
            mod,_,fn=item.rpartition('.'); seed.append((mod,fn,'access'))
    else: seed=candidates()
    if '--cases' in args:
        print(statement_cases(),'cases made statements'); ownify.save()
        print(returns_for_breaks(),'breaks made returns'); ownify.save(); sys.exit(0)
    skip=[]
    while '--skip' in args:
        at=args.index('--skip'); skip.append(args[at+1]); del args[at:at+2]
    chosen,out=close(seed,limit,skip)
    print(f'{len(seed)} seeds, {len(chosen)} to convert, {len(out)} left out')
    for (mod,fn,name),why in out.items(): print(f'  out {mod}.{fn}: {why}')
    for mod,fn,name in chosen: print(f'  own {mod}.{fn}'+('' if name=='access' else f' ({name})'))
    if dry: sys.exit(0)
    shaped=reshape(chosen)
    done=0; placed=0; notes=[]
    for mod,fn,name in chosen:
        position=ownify.convert(mod,fn,name=name,report=notes.append)
        if position is None: continue
        done+=1
    for mod,fn,name in chosen:
        position,_=position_of(mod,fn,name)
        if position is not None: placed+=ownify.call_sites(mod,fn,position,report=notes.append)
    cases=statement_cases()
    ownify.save()
    breaks=returns_for_breaks()
    ownify.save()
    print(f'{shaped} calls reshaped, {done} definitions, {placed} calls rewritten, {cases} cases made statements, {breaks} breaks made returns')
    for note in sorted(set(notes)): print('  '+note)
