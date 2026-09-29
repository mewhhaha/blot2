#!/usr/bin/env python3
"""Translate Blot's retained pure semantic algorithms to native Zig functions.

This deliberately narrow migration tool rejects unrecognized syntax. It is not
an interpreter and never embeds or links the Bend runtime or generated C/JS.
"""
from __future__ import annotations
from port import *
import hashlib

# Native algorithms are valid only for these retained source definitions. A
# source edit deoptimizes its entire module rather than silently changing meaning.
NATIVE_MODULE_HASHES = {
    'effect_rows': 'ee075f75680328a1a74c7fb06ff3d7e28d4635f12774c289b7fc3effef6a7959',
    'types': 'f37bf621a0f4378fb982874116cb48404e5fea504c22332d33606b820701ddd7',
    'native_request': '62da0ead06c5edf07c813c1c9a955cf3a72de916694c33d498e1ea3cd486bebc',
    'native_response': 'ae77f19fd57a6cdb88c7e2d47faccc9b18c744cb31edf0c98f3332b5f48b948b',
    'native_io': 'f607001bd2b41d31a0314affbb058701f5633c1a4f04a570165ba4a070382fca',
    'native_session': 'c7f00a2b19a20b5cf5db61ed0345df9f0319f8ea9decf72f9cdaa48f51d6a1d2',

    'model': '051c3fb473823d7d8621a8c3ac11a859aba515b77833ef990116ba6e4215325a',
    'index': '58f680aebe3ec29797f93a11b8a5e60f5297fac8c8e3dbc2e842ca47d582e4f4',
    'nat_index': '5a8dc29f32904dc4fee7f0f9ced2e18075fd1e112b2b01be0c3bb2489e007b82',
    'cst': '1e07cd287f8501ccbdbf02a520787b76d87dc894f55932ab047ebe7b8d6d7c0e',
}
# Independent source algorithms are emitted as differential test oracles only.
# They are not fallback paths for any native entry point.
TYPE_IR_ORACLES = {
    'types.resolve_work_reference', 'types.rewrite', 'types.rename_work',
    'types.resolve_row_at', 'types.from_list',
}
def oracle_name(name):
    module, name = name.split('.', 1)
    return module + '.$oracle_' + name

NATIVE_FUNCTIONS = {
    'types.resolve': 'resolveType', 'types.first_type': 'firstType',
    'types.resolve_work': 'resolveTypes', 'types.resolve_row_at': 'resolveRowAt',
    'types.rewrite': 'rewriteTypes', 'types.rename_work': 'renameTypes',
    'types.substitution_count': 'substitutionCount',
    'types.contains': 'variableContains', 'types.put': 'variablePut',
    'types.wide_variables': 'variableWide', 'types.union': 'variableUnion',
    'types.difference': 'variableDifference',
    'native_request.decode': 'decode',
    'model.name_equal': 'nameEqual', 'model.type_id_equal': 'typeIdEqual',
    'index.find': 'stringFind', 'index.get': 'stringGet',
    'nat_index.find': 'natFind', 'nat_index.get': 'natGet', 'nat_index.set': 'natSet',
    'cst.children_of': 'childrenOf', 'cst.kind_of': 'kindOf',
    'cst.text_of': 'textOf', 'cst.offset_of': 'offsetOf',
    'cst.fields': 'fields', 'cst.fields_reversed': 'fieldsReversed',
    'cst.field_values': 'fieldValues',
}

def native_functions(mods):
    valid = {name for name, expected in NATIVE_MODULE_HASHES.items()
             if name in mods and hashlib.sha256(mods[name].path.read_bytes()).hexdigest() == expected}
    # String-index equality depends on model.name_equal as well as index itself.
    if 'model' not in valid:
        valid.discard('index')
        valid.discard('cst')
    if not {'model', 'nat_index', 'effect_rows'} <= valid:
        valid.discard('types')
    if not set(('model', 'cst', 'native_response', 'native_io', 'native_session')) <= valid:
        valid.discard('native_request')
    return {name: target for name, target in NATIVE_FUNCTIONS.items()
            if name.split('.', 1)[0] in valid}


BASE_CTORS = {'Nil':0,'Cons':2,'SNil':0,'SCon':2,'Chr':1,'Unit':0,
              'True':0,'False':0,'Some':1,'None':0,'Done':1,'Fail':1,
              'LT':0,'EQ':0,'GT':0,'Pair':2,'MTip':0,'MLeaf':2,'MNode':3,
              'U32':1,'F32':1}
# A 946-node dispatcher used a 50 KiB frame in Debug. Split well before
# that point so ordinary nested expressions do not exhaust the main stack.
MATCH_OUTLINE_NODES = 128

BASE_TYPES = set('Nat U32 F32 Char String Bool Cmp Unit Data Type List Maybe Result Map Set Array IO'.split())
# Keep the primitive surface explicit: an unknown function must stop generation.
PRIMITIVES = set('''Array.get Array.new Array.set Bool.and Bool.not Bool.or Bool.pick Bool.xor
Char.is_eq Char.to_u32 F32.abs F32.add F32.bits F32.ceil F32.div F32.floor F32.is_eq
F32.is_ge F32.is_gt F32.is_le F32.is_lt F32.is_ne F32.mul F32.neg F32.read F32.sqrt
F32.sub F32.to_u32 F32.trunc List.append List.drop List.is_empty List.length
List.merge.go List.replicate List.reverse List.reverse.go List.sort List.take Map.new
Map.set Map.union Map.values Maybe.is_none Maybe.is_some Maybe.or Nat.add Nat.cmp
Nat.div Nat.is_eq Nat.is_ge Nat.is_gt Nat.is_le Nat.is_lt Nat.is_ne Nat.max Nat.min
Nat.mod Nat.mul Nat.read Nat.show Nat.sub Set.add Set.from_list Set.new Set.size
Set.to_list String.drop String.is_le String.is_lt String.join String.length
String.reverse String.split String.starts_with U32.add U32.and U32.cmp U32.div
U32.from_nat U32.is_eq U32.is_ge U32.is_gt U32.is_le U32.is_lt U32.is_ne U32.mod
Map.diff.chr Maybe.map U32.xor U32.mul U32.or U32.shln U32.show U32.shr U32.shrn U32.sub U32.to_f32 U32.to_nat'''.split())

def ident(s): return re.sub(r'[^a-zA-Z0-9_]','_',s)
def quote(s):
    # Zig accepts UTF-8 source, but not JSON's \uXXXX escapes.
    return json.dumps(s, ensure_ascii=False).replace('\\b','\\x08').replace('\\f','\\x0c')

def walk(n):
    yield n
    for c in n.children: yield from walk(c)
    if n.kind=='match':
        for pats,b in n.value:
            for p in pats: yield from walk(p)
            yield from walk(b)

def bound(p):
    if p.kind=='id': return set() if p.value=='_' else {p.value}
    if p.kind in ('ctor','tuple','list','binary'):
        return set().union(*(bound(c) for c in p.children))
    return set()

def free(n, names=frozenset()):
    if n.kind=='id': return {n.value} - names
    if n.kind=='lambda': return free(n.children[0],names|{n.value})
    if n.kind=='block':
        found=set(); scope=set(names)
        for s in n.children:
            if s.kind=='bind':
                found |= free(s.children[1],scope);scope |= bound(s.children[0])
            elif s.kind=='parallel_bind':
                count=s.value
                for rhs in s.children[count:]: found |= free(rhs,scope)
                for lhs in s.children[:count]: scope |= bound(lhs)
            else: found |= free(s,scope)
        return found
    if n.kind=='match':
        found=set().union(*(free(c,names) for c in n.children))
        for pats,b in n.value:found |= free(b,set(names).union(*(bound(p) for p in pats)))
        return found
    return set().union(*(free(c,names) for c in n.children))

class Generator:
    def __init__(self, root):
        self.root=root;self.mods=load(root);self.native=native_functions(self.mods)
        self.functions={f'{m.name}.{f.name}':f for m in self.mods.values() for f in m.functions}
        self.functions.update({oracle_name(n): f for n, f in list(self.functions.items())})
        self.types={f'{m.name}.{t}' for m in self.mods.values() for t in m.types}
        self.ctors={f'{m.name}.{c}':len(fields) for m in self.mods.values() for c,fields in m.ctors.items()}|BASE_CTORS
        self.ids={};self.todo=[];self.output=[];self.lambdas=0;self.forks=0;self.arms=0;self.primitives=set()
        self.temp=0;self.indent=0;self.lines=[];self.current='';self.mod=None
        self.primitive_arities={};self.primitive_wrappers={}
        for mod in self.mods.values():
            self.mod=mod
            for f in mod.functions:
                for node in walk(f.body):
                    if node.kind=='call' and node.children[0].kind=='id':
                        name=self.resolve(node.children[0].value)
                        if name in PRIMITIVES:self.primitive_arities[name]=len(node.children)-1
    def resolve(self,name):
        mod=self.mod
        first,sep,rest=name.partition('.')
        if first in mod.imports and sep:
            result=mod.imports[first]+'.'+rest
        elif f'{mod.name}.{name}' in self.functions|self.ctors or f'{mod.name}.{name}' in self.types:
            result=f'{mod.name}.{name}'
        else:
            result=name
        if '.$oracle_' in self.current and result in self.functions:
            return oracle_name(result)
        return result
    def synthetic_name(self, name):
        prefix = '$oracle_' if '.$oracle_' in self.current else '$'
        return f'{self.mod.name}.{prefix}{name}'
    def request(self,name):
        if name not in self.ids:
            self.ids[name]=len(self.ids);self.todo.append(name)
        return self.ids[name]
    def line(self,s):self.lines.append('    '*self.indent+s)
    def tmp(self,prefix='v'):
        self.temp+=1;return f'{prefix}{self.temp}'
    def save(self,expr):
        name=self.tmp();self.line(f'const {name}: V = {expr};');self.line(f'r.ignore({name});');return name
    def construct(self,name,values):
        if name not in self.ctors:raise ParseError(f'{self.current}: unknown constructor {name}')
        if self.ctors[name]!=len(values):raise ParseError(f'{self.current}: constructor arity {name}: {len(values)} != {self.ctors[name]}')
        return self.save(f'ctx.node(.{ident(name)}, &.{{{", ".join(values)}}})')
    def tuple(self,children):
        if len(children)<2: raise ParseError('tuple arity')
        result=children[-1]
        for child in reversed(children[:-1]):result=self.construct('Pair',[child,result])
        return result
    def value(self,n,env):
        k=n.kind
        if k=='id':
            if n.value in env:return env[n.value]
            name=self.resolve(n.value)
            if name in self.functions:return self.save(f'ctx.closure({self.request(name)}, &.{{}})')
            if name in PRIMITIVES:
                if name not in self.primitive_wrappers:
                    params=[f'arg{i}' for i in range(self.primitive_arities[name])]
                    wrapper=self.synthetic_name(f'primitive_{ident(name)}')
                    self.functions[wrapper]=Function(self.mod.name,wrapper.split('.',1)[1],params,Node('call',children=[Node('id',name),*[Node('id',p) for p in params]]),n.line)
                    self.primitive_wrappers[name]=wrapper
                return self.save(f'ctx.closure({self.request(self.primitive_wrappers[name])}, &.{{}})')
            if name in self.types or name in BASE_TYPES:return 'r.erased'
            raise ParseError(f'{self.current}:{n.line}: unbound identifier {n.value} ({name})')
        if k=='type':return 'r.erased'
        if k=='number':
            s=n.value.replace('_','')
            if s.endswith('n'):return f'r.nat({s[:-1]})'
            if '.' in s or 'e' in s.lower() and not s.startswith('0x') or s.endswith('f') and not s.startswith('0x'):
                return f'r.float({s[:-1] if s.endswith("f") else s})'
            return f'r.word({s})'
        if k=='negative':return self.save(f'r.float(-r.toFloat({self.value(n.children[0],env)}))')
        if k=='char':return f'r.character({ord(n.value)})'
        if k=='string':return f'r.literal({quote(n.value)})'
        if k=='ctor':return self.construct(self.resolve(n.value),[self.value(c,env) for c in n.children])
        if k=='tuple':return self.tuple([self.value(c,env) for c in n.children])
        if k=='list':
            values=[self.value(c,env) for c in n.children];result='r.empty(.Nil)'
            for v in reversed(values):result=self.construct('Cons',[v,result])
            return result
        if k=='binary':
            a,b=[self.value(c,env) for c in n.children]
            if n.value=='<>':return self.construct('Cons',[a,b])
            if n.value=='++':return self.save(f'ctx.concat({a}, {b})')
            op={'+':'add','-':'sub','*':'mul','/':'div'}.get(n.value)
            if op:return self.save(f'r.numeric(.{op}, {a}, {b})')
        if k=='array_repeat':
            a,b=[self.value(c,env) for c in n.children]
            return self.save(f'ctx.arrayRepeat({a}, r.toNat({b}))')
        if k=='lambda':
            captures=sorted(free(n.children[0],{n.value}) & env.keys())
            self.lambdas+=1;name=self.synthetic_name(f'lambda{self.lambdas}')
            self.functions[name]=Function(self.mod.name,name.split('.',1)[1],[*captures,n.value],n.children[0],n.line)
            return self.save(f'ctx.closure({self.request(name)}, &.{{{", ".join(env[c] for c in captures)}}})')
        if k=='call':return self.call(n,env,False)
        if k in ('block','do','match','return'):
            name=self.tmp();label=self.tmp('b');self.line(f'const {name}: V = {label}: {{');self.indent+=1
            self.emit(n,env.copy(),label,None)
            self.indent-=1;self.line('};');self.line(f'r.ignore({name});');return name
        raise ParseError(f'{self.current}:{n.line}: unsupported value {k}')
    def call(self,n,env,tail):
        callee=n.children[0]
        name=self.resolve(callee.value) if callee.kind=='id' and callee.value not in env else None
        if name in self.types or name in BASE_TYPES:
            if n.children[1:]:raise ParseError(f'{self.current}:{n.line}: unexpected runtime type application {name}')
            return 'r.erased'
        indirect=self.value(callee,env) if name is None else None
        args=[self.value(c,env) for c in n.children[1:]];values=', '.join(args)
        if name in self.functions:
            if len(args)!=len(self.functions[name].params):
                raise ParseError(f'{self.current}:{n.line}: arity {name} got {len(args)}, need {len(self.functions[name].params)}')
            if name in self.native:
                expr=f'native.{self.native[name]}(ctx, &.{{{values}}})'
                if tail:expr='r.done('+expr+')'
            else:
                method='next' if tail else 'call';expr=f'ctx.{method}({self.request(name)}, &.{{{values}}})'
        elif name in PRIMITIVES:
            self.primitives.add(name);expr=f'ctx.primitive(.{ident(name)}, &.{{{values}}})'
            if tail:expr='r.done('+expr+')'
        elif indirect is not None:
            method='nextClosure' if tail else 'invoke';expr=f'ctx.{method}({indirect}, &.{{{values}}})'
        else:raise ParseError(f'{self.current}:{n.line}: unknown call {name}')
        if tail:self.line(f'return {expr};');return ''
        return self.save(expr)
    def pattern(self,p,v,conditions,bindings):
        if p.kind=='id':
            if p.value!='_':bindings.append((p.value,v))
        elif p.kind in ('ctor','tuple','list','binary'):
            if p.kind=='ctor':name=self.resolve(p.value);children=p.children
            elif p.kind=='tuple':
                children=[p.children[0], p.children[1] if len(p.children)==2 else Node('tuple',children=p.children[1:])];name='Pair'
            elif p.kind=='list':
                if not p.children:children=[];name='Nil'
                else:children=[p.children[0],Node('list',children=p.children[1:])];name='Cons'
            elif p.value=='<>':name='Cons';children=p.children
            elif p.value=='+' and p.children[0].kind=='number':
                size=p.children[0].value
                if not size.endswith('n'):raise ParseError('only Nat successor patterns are supported')
                amount=int(size[:-1]);conditions.append(f'r.toNat({v}) >= {amount}')
                self.pattern(p.children[1],f'r.nat(r.toNat({v}) - {amount})',conditions,bindings);return
            else:raise ParseError('unsupported pattern binary '+str(p.value))
            if name not in self.ctors or len(children)!=self.ctors[name]:raise ParseError(f'{self.current}:{p.line}: pattern arity {name}')
            conditions.append(f'r.tag({v}) == .{ident(name)}')
            for i,c in enumerate(children):self.pattern(c,f'r.field({v}, {i})',conditions,bindings)
        elif p.kind=='number':conditions.append(f'{v} == {self.value(p,{})}')
        elif p.kind=='char':conditions.append(f'{v} == r.character({ord(p.value)})')
        elif p.kind=='string':conditions.append(f'r.stringEqual({v}, r.literal({quote(p.value)}))')
        else:raise ParseError(f'{self.current}:{p.line}: unsupported pattern {p.kind}')
    def bind(self,p,value,env,assertions=True):
        conditions=[];bindings=[];self.pattern(p,value,conditions,bindings)
        if conditions and assertions:self.line(f'r.assert({" and ".join(conditions)});')
        for name,v in bindings:env[name]=self.save(v)
    def finish(self,v,target):
        if target is None:self.line('return r.done('+v+');')
        else:self.line(f'break :{target} {v};')
    def emit(self,n,env,target,monad):
        k=n.kind
        if k=='block':
            for i,s in enumerate(n.children):
                if s.kind=='bind':
                    p,rhs=s.children;value=self.value(rhs,env)
                    if s.value=='<-':
                        failure={'Result':'Fail','Maybe':'None'}.get(monad)
                        if failure is None:raise ParseError(f'{self.current}:{s.line}: bind outside Result/Maybe: {monad}')
                        self.line(f'if (r.tag({value}) == .{failure}) {{');self.indent+=1;self.finish(value,target);self.indent-=1;self.line('}')
                        value=self.save(f'r.field({value}, 0)')
                    self.bind(p,value,env)
                    if i==len(n.children)-1:raise ParseError('final binding has no expression')
                elif s.kind=='parallel_bind':
                    count=s.value
                    # All RHSs capture the same pre-binding scope. Only pure
                    # semantic batches use parallel bindings in the retained
                    # compiler; request decoding and Array mutation are serial.
                    thunks=[]
                    for rhs in s.children[count:]:
                        captures=sorted(free(rhs) & env.keys())
                        self.forks+=1;name=self.synthetic_name(f'fork{self.forks}')
                        self.functions[name]=Function(self.mod.name,name.split('.',1)[1],captures,rhs,rhs.line)
                        thunks.append(self.save(f'ctx.closure({self.request(name)}, &.{{{", ".join(env[c] for c in captures)}}})'))
                    result=self.tmp('parallel')
                    self.line(f'const {result} = ctx.parallel({count}, .{{{", ".join(thunks)}}});')
                    for index,p in enumerate(s.children[:count]):self.bind(p,f'{result}[{index}]',env)
                elif i==len(n.children)-1:self.emit(s,env,target,monad)
                else:self.value(s,env)
            return
        if k=='do':
            if n.value not in ('Result','Maybe'):raise ParseError(f'{self.current}:{n.line}: unknown monad {n.value}')
            self.emit(n.children[0],env,target,n.value);return
        if k=='match':
            values=[self.value(c,env) for c in n.children]
            exhaustive=False
            # Keep Debug stack frames proportional to the selected match arm,
            # not the sum of every arm in a large semantic dispatcher. This
            # also prevents giant LLVM optimization units. The dispatcher
            # returns through the trampoline before the arm starts executing.
            outline=target is None and sum(1 for _ in walk(n)) >= MATCH_OUTLINE_NODES
            for pats,body in n.value:
                if len(pats)==1 and pats[0].kind=='id' and pats[0].value=='_': pats=pats*len(values)
                if len(pats)!=len(values):raise ParseError(f'{self.current}:{n.line}: match arity {len(pats)} != {len(values)}')
                conditions=[];bindings=[]
                for p,v in zip(pats,values):self.pattern(p,v,conditions,bindings)
                if exhaustive:break # Bend's checker already rejected overlapping impossible paths.
                self.line(f'if ({" and ".join(conditions) if conditions else "true"}) {{');self.indent+=1
                scope=env.copy()
                for name,v in bindings:scope[name]=self.save(v)
                if outline:
                    captures=sorted(free(body) & scope.keys())
                    self.arms+=1;name=self.synthetic_name(f'arm{self.arms}')
                    wrapper=Node('do',monad,[body],body.line) if monad else body
                    self.functions[name]=Function(self.mod.name,name.split('.',1)[1],captures,wrapper,body.line)
                    self.line(f'return ctx.next({self.request(name)}, &.{{{", ".join(scope[c] for c in captures)}}});')
                else:self.emit(body,scope,target,monad)
                self.indent-=1;self.line('}')
                if not conditions:exhaustive=True
            if not exhaustive:self.line(f'@panic({quote("non-exhaustive semantic match: "+self.current+":"+str(n.line))});')
            return
        if k=='return':
            value=self.value(n.children[0],env)
            success={'Result':'Done','Maybe':'Some'}.get(monad)
            if success:value=self.construct(success,[value])
            self.finish(value,target);return
        if k=='call' and target is None:
            # Types are erased, so a final type expression is handled normally.
            name=self.resolve(n.children[0].value) if n.children[0].kind=='id' and n.children[0].value not in env else None
            if name not in self.types and name not in BASE_TYPES:self.call(n,env,True);return
        self.finish(self.value(n,env),target)
    def protocol_version(self):
        version = self.functions['native_response.version'].body
        if (version.kind != 'block' or len(version.children) != 1 or
                version.children[0].kind != 'number' or
                not version.children[0].value.isdecimal()):
            raise ParseError('native_response.version must be one U32 literal')
        protocol_version = int(version.children[0].value)
        if not 0 <= protocol_version <= 0xffffffff:
            raise ParseError('native protocol version is outside U32')
        return protocol_version
    def run(self):
        protocol_version = self.protocol_version()
        roots=['native_main.respond','native_request.decode']
        for name in sorted(TYPE_IR_ORACLES):self.request(oracle_name(name))
        for name in roots:self.request(name)
        cursor=0
        while cursor<len(self.todo):
            name=self.todo[cursor];cursor+=1;f=self.functions[name];self.current=name;self.mod=self.mods[f.module]
            self.lines=[];self.indent=0;self.temp=0
            if len(f.params)>64:raise ParseError(f'{name}: arity exceeds native trampoline capacity')
            self.line(f'// {f.module}.bend:{f.line} {f.name}')
            self.line(f'fn fun_{self.ids[name]}(ctx: *r.Context, args: []const V) r.Step {{');self.indent=1
            self.line('@setEvalBranchQuota(100000);');self.line('r.ignoreContext(ctx);');self.line(f'r.assert(args.len == {len(f.params)});')
            env={p:self.save(f'args[{i}]') for i,p in enumerate(f.params)}
            if name in self.native:
                self.line(f'return r.done(native.{self.native[name]}(ctx, args));')
            else:
                self.emit(f.body,env,None,None)
            self.indent=0;self.line('}')
            self.output.append('\n'.join(self.lines))
        directory=self.root/'zig/src/generated';directory.mkdir(parents=True,exist_ok=True)
        (directory/'protocol.zig').write_text(f'// From native_response.version; do not hand-edit.\npub const version: u32 = {protocol_version};\n')
        header='// Generated by zig/tools/generate.py. Do not hand-edit.\nconst r = @import("../runtime.zig");\nconst V = r.Value;\nconst native = @import("../semantic.zig");\n'
        table='\npub const table = [_]*const fn (*r.Context, []const V) r.Step {\n'+''.join(f'    &fun_{i}, // {name}\n' for name,i in self.ids.items())+'};\n'
        table+='pub const arities = [_]u8{'+','.join(str(len(self.functions[n].params)) for n in self.ids)+'};\n'
        table+='pub const names = [_][]const u8{'+','.join(quote(n) for n in self.ids)+'};\n'
        for root in roots:table+=f'pub const {ident(root)}: u32 = {self.ids[root]};\n'
        for name in sorted(TYPE_IR_ORACLES):table+=f'pub const oracle_{ident(name)}: u32 = {self.ids[oracle_name(name)]};\n'
        (directory/'functions.zig').write_text(header+'\n\n'.join(self.output)+table)
        (directory/'tags.zig').write_text('// Generated constructor identities; source module identity is preserved.\npub const Tag = enum(u16) {\n'+''.join(f'    {ident(n)},\n' for n in sorted(self.ctors))+'};\n')
        (directory/'primitives.zig').write_text('// Explicit native primitive surface.\npub const Primitive = enum {\n'+''.join(f'    {ident(n)},\n' for n in sorted(PRIMITIVES))+'};\n')
        manifest={m.name:hashlib.sha256(m.path.read_bytes()).hexdigest() for m in sorted(self.mods.values(),key=lambda m:m.name)}
        (directory/'manifest.json').write_text(json.dumps({'protocol_version':protocol_version,'native_functions':sorted(self.native),'sources':manifest,'functions':len(self.ids),'max_arity':max(len(self.functions[n].params) for n in self.ids),'closures':self.lambdas,'parallel_tasks':self.forks,'outlined_arms':self.arms,'constructors':len(self.ctors)},indent=2)+'\n')
        print(f'Generated {len(self.ids)} native Zig functions ({self.lambdas} closures, {self.forks} parallel tasks, {self.arms} outlined arms), {len(self.ctors)} constructors, {len(self.primitives)} primitives.')

if __name__=='__main__':
    try:Generator(Path(__file__).resolve().parents[2]).run()
    except ParseError as e:print(e,file=sys.stderr);sys.exit(1)
