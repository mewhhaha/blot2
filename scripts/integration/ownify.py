"""Make functions of ../gdev take the world with `own` and hand it back.

Usage: python3 scripts/integration/ownify.py [--dry] MODULE.FUNCTION...
       python3 scripts/integration/ownify.py [--dry] --from-file LIST

MODULE is a path under ../gdev without `.sq` (`src/world/salt`). For each
function it rewrites the parameter named `access` to `(own access)`, makes
every way out of the body return `access`, and turns each call that stands
as a statement, anywhere under ../gdev, into `X := call` where `X` is the
name given for that parameter. It is for functions that have no result
(tasks/MEMORY_MODEL.md, "Next: the systems"); it prints what it could not
rewrite: calls inside an expression, calls that give something other than
a name, and definitions it does not understand.
"""
import re,sys,os,glob
ROOT=os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)),'../../../gdev'))
INK=os.path.normpath(os.path.join(ROOT,'../ink/lib'))
DIRS=['src','tests','test_support','devtools','performance']
def indent(l): return len(l)-len(l.lstrip(' '))
def atoms(text):
    out=[];i=0;n=len(text)
    while i<n:
        if text[i].isspace(): i+=1; continue
        j=i
        if text[i] in '([{':
            depth=0
            while j<n:
                if text[j] in '([{': depth+=1
                elif text[j] in ')]}':
                    depth-=1
                    if depth==0: j+=1; break
                j+=1
            while j<n and text[j] in '.[':
                if text[j]=='[':
                    d=0
                    while j<n:
                        if text[j]=='[': d+=1
                        elif text[j]==']':
                            d-=1
                            if d==0: j+=1; break
                        j+=1
                else:
                    j+=1
                    while j<n and (text[j].isalnum() or text[j]=='_'): j+=1
        else:
            depth=0
            while j<n and (not text[j].isspace() or depth>0):
                if text[j] in '([{': depth+=1
                elif text[j] in ')]}':
                    if depth==0: break
                    depth-=1
                j+=1
        if j==i: j=i+1
        out.append(text[i:j]); i=j
    return out
class File:
    cache={}
    def __init__(self,path):
        self.path=path; self.lines=open(path).read().split('\n'); self.dirty=False
        self.imports={}
        for l in self.lines:
            m=re.match(r'^import \* as (\w+) from "([^"]+)"',l)
            if m: self.imports[m.group(1)]=resolve(path,m.group(2))
    @staticmethod
    def get(path):
        path=os.path.normpath(path)
        if path not in File.cache: File.cache[path]=File(path)
        return File.cache[path]
    def find(self,fn):
        for k,l in enumerate(self.lines):
            if re.match(r'^(lent )?(entry )?func '+re.escape(fn)+r'(?![\w.])',l): return k
        return -1
    def end(self,k):
        j=k+1
        while j<len(self.lines) and (self.lines[j].startswith(' ') or self.lines[j]==''): j+=1
        while j>k+1 and self.lines[j-1]=='': j-=1
        return j
def resolve(path,target):
    if target.startswith('game/'): return os.path.join(ROOT,'src',target[5:]+'.sq')
    if target.startswith('test/'): return os.path.join(ROOT,'tests',target[5:]+'.sq')
    if target.startswith('ink/'): return os.path.join(INK,target[4:]+'.sq')
    if target.startswith('.'): return os.path.normpath(os.path.join(os.path.dirname(path),target))+'.sq'
    return target
def header(line):
    """The parameter atoms of a definition line and where its body starts."""
    m=re.match(r'^((?:lent )?(?:entry )?func [\w.]+) (.*)$',line)
    rest=m.group(2)
    # a chain `a => return func b => return func c => return do:` is one list
    parts=[]; pos=0; text=rest
    while True:
        cut=text.find('=>',pos)
        if cut<0: return None
        params=text[pos:cut]
        for a in split_arrows(params): parts.append(a)
        after=text[cut+2:].lstrip()
        if after.startswith('return func '):
            pos=cut+2+(len(text[cut+2:])-len(after))+len('return func ')
            continue
        return parts, m.group(1), cut+2+len(m.group(1))+1
def split_arrows(text):
    out=[]; depth=0; cur=''
    i=0
    while i<len(text):
        c=text[i]
        if c in '([{': depth+=1
        elif c in ')]}': depth-=1
        if depth==0 and text.startswith('->',i): out.append(cur.strip()); cur=''; i+=2; continue
        cur+=c; i+=1
    if cur.strip(): out.append(cur.strip())
    return out
def owned_param(atom,name):
    if atom==name: return f'(own {name})'
    m=re.match(r'^\('+name+r': (?!own )(.*)\)$',atom)
    if m: return f'({name}: own {m.group(1)})'
    return None
def convert(mod,fn,name='access',dry=False,report=print):
    f=File.get(os.path.join(ROOT,mod+'.sq'))
    k=f.find(fn)
    if k<0: report(f'DEF? {mod}.{fn}: no definition'); return None
    line=f.lines[k]
    if line.startswith('lent '): report(f'DEF? {mod}.{fn}: lent'); return None
    h=header(line)
    if not h: report(f'DEF? {mod}.{fn}: header'); return None
    params,prefix,_=h
    position=-1
    for at,a in enumerate(params):
        if a==name or re.match(r'^\('+name+r': ',a) or a==f'(own {name})': position=at
    if position<0: report(f'DEF? {mod}.{fn}: no parameter {name}'); return None
    if params[position]==f'(own {name})' or re.match(r'^\('+name+r': own ',params[position]): return position   # already
    new=owned_param(params[position],name)
    if not new: report(f'DEF? {mod}.{fn}: parameter {params[position]}'); return None
    # replace the parameter text in the line (first occurrence as an atom)
    at=re.search(r'(?<![\w.(])'+re.escape(params[position])+r'(?![\w.])',line[len(prefix):])
    if not at: report(f'DEF? {mod}.{fn}: cannot place parameter'); return None
    start=len(prefix)+at.start()
    line=line[:start]+new+line[start+len(params[position]):]
    # it returns the world now, whatever it said it returned
    if re.search(r'\) *: *Unit ! ',line): report(f'DEF? {mod}.{fn}: result with effects'); return None
    line=re.sub(r'(\)) *: *Unit => return',r'\1 => return',line)
    j=f.end(k)
    body=f.lines[k+1:j]
    out=[]
    if line.rstrip().endswith('=> return do:'):
        base=2
        for l in body:
            if l.strip(): base=indent(l); break
        nested=[]; loops=[]; blocks=[]; i=0; last_top=None
        while i<len(body):
            l=body[i]; st=l.strip(); ind=indent(l)
            while nested and st and ind<=nested[-1]: nested.pop()
            while loops and st and ind<=loops[-1]: loops.pop()
            if st and re.match(r'^(for|while|loop)\b.*:$',st.split('//')[0].rstrip()): loops.append(ind)
            # `break value` in the body's own block ends it like `return`; in
            # a block further in (`=> do:`, `else:` of a let) it ends that one
            while blocks and st and ind<=blocks[-1]: blocks.pop()
            # (a bare `break` leaves a loop; one with a value ends the block)
            if not nested and not blocks and re.match(r'^break\b',st) and (st!='break' or not loops): st='return'+st[5:]; l=' '*ind+st
            if st and not nested and ind==base: last_top=st
            if not nested and re.match(r'^return\b',st):
                expr=st[6:].strip()
                if expr in ('()',''): out.append(' '*ind+'return '+name); i+=1; continue
                if expr.startswith('@panic') or expr==name: out.append(l); i+=1; continue
                # a `case` whose arms end with `break` stays an expression
                if re.match(r'^case\b',expr): expr='let _ = '+expr
                out.append(' '*ind+expr); i+=1
                while i<len(body) and (not body[i].strip() or indent(body[i])>ind): out.append(body[i]); i+=1
                out.append(' '*ind+'return '+name)
                if ind==base: last_top='return '+name
                continue
            out.append(l)
            code=st.split('//')[0].rstrip()
            # a lambda whose body goes on below: its parenthesis is still
            # open, or the line ends where a body starts
            opened=code.count('(')+code.count('[')+code.count('{')-code.count(')')-code.count(']')-code.count('}')
            if st and re.search(r'\bfunc\b.*=>',code) and (opened>0 or re.search(r'(do:|\bof|=> return)$',code)): nested.append(ind)
            elif code.endswith('do:'): blocks.append(ind)
            i+=1
        if not (last_top or '').startswith('return'):
            out.append(' '*base+'return '+name)
    else:
        # `=> return EXPR`, maybe over several lines
        cut=line.rfind('=> return')
        expr=line[cut+len('=> return'):].strip()
        line=line[:cut]+'=> return do:'
        if expr.startswith('@panic'): report(f'DEF? {mod}.{fn}: one-line panic'); return None
        if expr:
            out.append('  '+expr)
            for l in body: out.append(('  '+l) if l.strip() else l)
        else:
            # the expression starts on the next line, already indented
            for l in body: out.append(l)
        out.append('  return '+name)
    if not dry:
        f.lines[k:j]=[line]+out; f.dirty=True
    return position
def call_sites(mod,fn,position,dry=False,report=print):
    target=os.path.normpath(os.path.join(ROOT,mod+'.sq'))
    changed=0
    for d in DIRS:
        for path in glob.glob(os.path.join(ROOT,d,'**','*.sq'),recursive=True):
            f=File.get(path)
            names=[a+'.'+fn for a,p in f.imports.items() if os.path.normpath(p)==target]
            if os.path.normpath(path)==target: names.append(fn)
            for l in f.lines:
                m=re.match(r'^import \{([^}]*)\} from "([^"]+)"',l)
                if m and os.path.normpath(resolve(path,m.group(2)))==target and fn in [x.strip() for x in m.group(1).split(',')]: names.append(fn)
            if not names: continue
            for k,l in enumerate(f.lines):
                code=l.split('//')[0]
                # the expression a definition returns, written on the next line, is no statement
                if k>0 and f.lines[k-1].rstrip().endswith('=> return'): continue
                for nm in names:
                    for m in re.finditer(r'(?<![\w.$])'+re.escape(nm)+r'(?![\w.])',code):
                        if nm==fn and os.path.normpath(path)==target and re.match(r'^(lent )?(entry )?func ',l): continue
                        st=code.strip(); rel=os.path.relpath(path,ROOT)
                        if re.match(r'^\w+ := '+re.escape(nm)+r'\b',st): continue
                        # `use f args` runs `f args` for what it does
                        used=st.startswith('use '+nm+' ')
                        if used: st=st[4:]
                        if not st.startswith(nm+' ') and st!=nm:
                            # a bare name is a call only when arguments follow it
                            if '.' in nm or re.match(r' +[\w(]',code[m.end():]) and not re.match(r' +(=|:=|\+|-|\*|/|<|>|!=|and\b|or\b|then\b|else\b)',code[m.end():]): report(f'CALL? {rel}:{k+1}: {st[:120]}')
                            continue
                        a=atoms(st[len(nm):])
                        if len(a)<=position or not re.fullmatch(r'[a-z_]\w*',a[position]):
                            report(f'CALL? {rel}:{k+1}: {st[:120]}'); continue
                        if not dry:
                            rest=l[indent(l):]
                            if used: rest=rest[4:]
                            f.lines[k]=l[:indent(l)]+a[position]+' := '+rest; f.dirty=True
                        changed+=1
    return changed
def save():
    for f in File.cache.values():
        if f.dirty: open(f.path,'w').write('\n'.join(f.lines)); f.dirty=False
if __name__=='__main__':
    args=sys.argv[1:]; dry='--dry' in args
    if dry: args.remove('--dry')
    if args and args[0]=='--from-file': args=open(args[1]).read().split()
    done=0; sites=0
    for item in args:
        mod,_,fn=item.rpartition('.')
        position=convert(mod,fn,dry=dry)
        if position is None: continue
        done+=1; sites+=call_sites(mod,fn,position,dry=dry)
    # A converted body may call a function converted earlier as a statement
    # now (the tail `return f access` it had became `f access`): rebind those.
    quiet=lambda text: None
    for path in glob.glob(os.path.join(ROOT,'src','**','*.sq'),recursive=True):
        f=File.get(path); mod=os.path.relpath(path,ROOT)[:-3]
        for k,l in enumerate(list(f.lines)):
            m=re.match(r'^(?:entry )?func ([\w.]+) ',l)
            if not m or not re.search(r'\(own access\)|\(access: own ',l): continue
            h=header(l)
            if not h: continue
            for at,a in enumerate(h[0]):
                if a=='(own access)' or re.match(r'^\(access: own ',a): sites+=call_sites(mod,m.group(1),at,dry=dry,report=quiet)
    save()
    print(f'{done} definitions, {sites} calls rewritten')
