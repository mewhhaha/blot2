#!/usr/bin/env python3
"""One-shot, fail-closed mechanical migration of Blot's pure Bend core to Zig.

The generated Zig is a standalone implementation; neither its build nor its
runtime invokes Bend. This tool records the original algorithms during the
migration and is not a general purpose Bend compiler.
"""
from __future__ import annotations
from dataclasses import dataclass, field
from pathlib import Path
import ast, json, re, sys
from itertools import takewhile

@dataclass(frozen=True)
class Token:
    text: str
    line: int
    col: int

TOKEN = re.compile(r'''(?:"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|(?:0x[0-9a-fA-F_]+|[0-9][0-9_]*(?:\.[0-9_]+)?(?:[eE][+-]?[0-9_]+)?)[nf]?|[A-Za-z_][A-Za-z_0-9]*(?:\.[A-Za-z_][A-Za-z_0-9]*)*|=>|->|<-|<>|\+\+|==|!=|<=|>=|[^\s])''')

def lex(text: str) -> list[Token]:
    result = []
    for n, line in enumerate(text.splitlines(), 1):
        for m in TOKEN.finditer(line):
            if m.group() == '#': break
            result.append(Token(m.group(), n, m.start()))
    result.append(Token('<eof>', len(text.splitlines()) + 1, 0))
    return result

@dataclass
class Node:
    kind: str
    value: object = None
    children: list = field(default_factory=list)
    line: int = 0

@dataclass
class Function:
    module: str
    name: str
    params: list[str]
    body: Node
    line: int

@dataclass
class Module:
    name: str
    path: Path
    imports: dict[str, str]
    types: set[str]
    ctors: dict[str, list[str]]
    functions: list[Function]

class ParseError(Exception): pass

class Parser:
    def __init__(self, path: Path):
        self.path = path
        self.tokens = lex(path.read_text())
        self.i = 0
        self.pattern_mode = False
        self.mod = Module(path.stem, path, {}, set(), {}, [])

    def peek(self, n=0): return self.tokens[min(self.i+n, len(self.tokens)-1)]
    def pop(self):
        t = self.peek(); self.i += 1; return t
    def eat(self, text):
        if self.peek().text == text: self.pop(); return True
        return False
    def expect(self, text):
        if not self.eat(text): self.fail(f'expected {text!r}, found {self.peek().text!r}')
    def fail(self, message):
        t=self.peek()
        raise ParseError(f'{self.path}:{t.line}:{t.col+1}: {message}; near {" ".join(x.text for x in self.tokens[max(0,self.i-4):self.i+10])}')

    def skip_type(self, stops):
        depth=[]
        while self.peek().text!='<eof>':
            t=self.peek().text
            if not depth and t in stops: return
            if t in ('(', '[', '{', '<', '<-'): depth.append({'(':')','[':']','{':'}','<':'>','<-':'>'}[t])
            elif depth and t==depth[-1]: depth.pop()
            self.pop()
        self.fail('unterminated type')

    def parse(self):
        while self.peek().text!='<eof>':
            t=self.pop()
            if t.col!=0: self.fail('unexpected indentation at module scope')
            if t.text=='import':
                words=[]
                while self.peek().line==t.line: words.append(self.pop().text)
                raw=''.join(words)
                if raw!='Base':
                    # Lexical tokenization retains the path pieces, including '.bend'.
                    if 'as' not in words: self.fail('imports require an alias')
                    ix=words.index('as'); filename=''.join(words[:ix]); alias=words[ix+1]
                    self.mod.imports[alias]=Path(filename).stem
            elif t.text=='type':
                name=self.pop().text; self.mod.types.add(name)
                self.skip_type({':'})
                self.expect(':')
                while self.peek().col>0 and self.peek().text!='<eof>':
                    tag=self.pop().text
                    if not re.fullmatch(r'\w+',tag): self.fail('expected constructor name')
                    self.expect('{'); fields=[]
                    while not self.eat('}'):
                        self.eat('+'); self.eat('-'); self.eat('~')
                        fields.append(self.pop().text)
                        self.expect(':'); self.skip_type({',','}'})
                        if self.peek().text!='}': self.expect(',')
                    if tag in self.mod.ctors: self.fail('duplicate constructor')
                    self.mod.ctors[tag]=fields
            elif t.text=='def':
                name=self.pop().text; self.expect('('); params=[]
                while not self.eat(')'):
                    self.eat('+'); self.eat('-'); self.eat('~')
                    param=self.pop().text
                    if not re.fullmatch(r'\w+',param): self.fail('bad parameter')
                    params.append(param); self.expect(':'); self.skip_type({',',')'})
                    if self.peek().text!=')': self.expect(',')
                self.expect('->'); self.skip_type({':'})
                self.expect(':'); body=self.block()
                self.mod.functions.append(Function(self.mod.name,name,params,body,t.line))
            else: self.fail('unsupported module declaration '+t.text)
        return self.mod

    def block(self):
        begin=self.peek(); indent=begin.col; statements=[]
        if indent==0: self.fail('expected indented body')
        while self.peek().text not in ('<eof>',')',']','}',',') and self.peek().col>=indent:
            start=self.i
            if self.eat('return'):
                statements.append(Node('return',children=[self.expr()],line=begin.line))
            elif self.peek().text=='import':
                # Foreign transport is implemented in Zig, never copied or executed.
                self.pop(); statements.append(Node('foreign',self.pop().text,line=begin.line))
            else:
                self.pattern_mode=any(t.text in ('=', '<-') for t in takewhile(lambda t: t.line==self.peek().line, self.tokens[self.i:]))
                lhs=self.expr()
                lhs_group=[lhs]
                while self.peek().line == self.tokens[self.i-1].line and self.peek().text not in ('=', '<-', ':', ')', ']', '}', ',', '<eof>'):
                    lhs_group.append(self.expr())
                self.pattern_mode=False
                if self.eat(':'):
                    self.skip_type({'=','<-'})
                if self.peek().text in ('=','<-'):
                    mode=self.pop().text
                    rhs_group=[self.expr() for _ in lhs_group]
                    if len(lhs_group)==1:
                        statements.append(Node('bind',mode,[lhs,rhs_group[0]],lhs.line))
                    else:
                        if mode!='=': self.fail('parallel monadic bind')
                        statements.append(Node('parallel_bind',len(lhs_group),lhs_group+rhs_group,lhs.line))
                else:
                    if len(lhs_group)!=1: self.fail('multiple expressions without a binding')
                    statements.append(lhs)
            if self.i==start: self.fail('parser made no progress')
            # Statements are separated by a physical line. A enclosing delimiter
            # on the last statement's line belongs to its caller, not this suite.
            if self.peek().line==self.tokens[self.i-1].line: break
        if not statements: self.fail('empty body')
        return Node('block',children=statements,line=begin.line)

    def expr(self, minimum=0):
        t=self.pop(); s=t.text
        if s in ('+','-','~'):
            left=self.expr(90)
            if s=='-' and left.kind=='number': left=Node('negative',children=[left],line=t.line)
        elif s=='&':
            self.pop(); left=Node('type',line=t.line)
        elif s=='match':
            values=[]
            while self.peek().text!=':': values.append(self.expr())
            self.expect(':'); branches=[]
            branch_indent=self.peek().col
            while self.peek().text=='case' and self.peek().col==branch_indent:
                self.pop(); patterns=[]
                self.pattern_mode=True
                while self.peek().text!=':': patterns.append(self.expr())
                self.pattern_mode=False
                self.expect(':'); branches.append((patterns,self.block()))
            if not branches: self.fail('empty match')
            left=Node('match',branches,values,t.line)
        elif s=='do':
            monad=self.peek().text; self.skip_type({':'})
            self.expect(':'); left=Node('do',monad,[self.block()],t.line)
        elif s=='{':
            left=self.expr(); self.expect(':'); self.skip_type({'}'}); self.expect('}')
        elif s=='(':
            if self.eat(')'): left=Node('ctor','Unit',[],t.line)
            else:
                left=self.expr()
                if self.eat(','):
                    fields=[left]
                    while self.peek().text!=')':
                        fields.append(self.expr())
                        if not self.eat(','): break
                    left=Node('tuple',children=fields,line=t.line)
                if self.eat(':'): self.skip_type({')'})
                self.expect(')')
        elif s=='[':
            children=[]
            while not self.eat(']'):
                children.append(self.expr())
                if self.eat(':'):
                    self.skip_type({'*'}); self.expect('*'); size=self.expr(); self.expect(']')
                    left=Node('array_repeat',children=[children[0],size],line=t.line)
                    break
                if self.peek().text!=']': self.expect(',')
            else:
                left=Node('list',children=children,line=t.line)
        elif s.startswith('"'): left=Node('string',ast.literal_eval(s),line=t.line)
        elif s.startswith("'"): left=Node('char',ast.literal_eval(s),line=t.line)
        elif s[0].isdigit(): left=Node('number',s,line=t.line)
        elif re.fullmatch(r'[A-Za-z_][\w.]*',s): left=Node('id',s,line=t.line)
        else: self.fail('unexpected expression token '+s)

        while True:
            op=self.peek()
            # Newline '+' starts an explicitly duplicated binding, not addition.
            if op.line>self.tokens[self.i-1].line: break
            if op.text=='<' and left.kind=='id':
                self.pop(); self.skip_type({'>'}); self.expect('>')
                left=Node('type',line=t.line)
                continue
            if op.text=='{' and left.kind=='id':
                self.pop(); children=[]
                while not self.eat('}'):
                    children.append(self.expr())
                    if self.peek().text!='}': self.expect(',')
                left=Node('ctor',left.value,children,t.line); continue
            if op.text=='(' and minimum<=100:
                self.pop(); args=[]
                while not self.eat(')'):
                    args.append(self.expr())
                    if self.peek().text!=')': self.expect(',')
                left=Node('call',children=[left,*args],line=t.line); continue
            if op.text=='=>':
                if minimum>1: break
                if left.kind!='id': self.fail('lambda must bind one name')
                self.pop(); left=Node('lambda',left.value,[self.expr()],t.line); continue
            if self.pattern_mode and op.text=='+' and left.kind!='number': break
            precedence={'<>':10,'++':20,'+':30,'-':30,'*':40,'/':40}.get(op.text)
            if precedence is None or precedence<minimum: break
            self.pop(); right=self.expr(precedence if op.text in ('<>','++') or self.pattern_mode and op.text=='+' else precedence+1)
            left=Node('binary',op.text,[left,right],t.line)
        return left


def load(root: Path):
    pending=['native_main']; modules={}
    while pending:
        name=pending.pop()
        if name in modules: continue
        mod=Parser(root/'compiler'/f'{name}.bend').parse()
        modules[name]=mod
        pending.extend(x for x in mod.imports.values() if x not in modules)
    return modules

if __name__=='__main__':
    root=Path(__file__).resolve().parents[2]
    try:
        modules=load(root)
    except ParseError as e:
        print(e,file=sys.stderr); sys.exit(1)
    print(f'Parsed {len(modules)} modules, {sum(len(m.functions) for m in modules.values())} functions, {sum(len(m.ctors) for m in modules.values())} constructors.')
