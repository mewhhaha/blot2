#!/usr/bin/env python3
"""One-time, fail-closed migration of the compiler's pure Bend subset to OCaml.

This is not a Bend runtime or a Blot compiler frontend. It translates the checked
source algorithms into ordinary typed OCaml declarations, lets, matches and
calls. The native executable does not invoke this script or Bend. Unsupported
syntax is an error, never silently dropped. Source locations and a SHA-256
manifest make the migration auditable.
"""
from __future__ import annotations
import dataclasses as dc
import hashlib
import json
from pathlib import Path
import re
from typing import Any

@dc.dataclass(frozen=True)
class Token:
    text: str
    line: int
    column: int

@dc.dataclass
class Node:
    kind: str
    value: Any = None
    items: list[Any] = dc.field(default_factory=list)
    line: int = 0

@dc.dataclass
class Parameter:
    name: str
    type: Node
    erased: bool = False

@dc.dataclass
class Function:
    name: str
    parameters: list[Parameter]
    result: Node
    body: Node
    line: int

@dc.dataclass
class DataType:
    name: str
    parameters: list[str]
    constructors: list[tuple[str, list[tuple[str, Node]]]]
    line: int

@dc.dataclass
class Module:
    name: str
    imports: dict[str, str]
    types: list[DataType]
    functions: list[Function]
    digest: str

TOKEN = re.compile(r'''(?P<space>[ \t\r]+)|(?P<newline>\n)|(?P<comment>\#[^\n]*)|(?P<string>"(?:\\.|[^"\\])*")|(?P<char>'(?:\\.|[^'\\])*')|(?P<float>\d+\.\d+(?:[eE][+-]?\d+)?)|(?P<number>0[xX][0-9a-fA-F]+|\d+n?)|(?P<name>[A-Za-z_][A-Za-z_0-9]*(?:\.[A-Za-z_][A-Za-z_0-9]*)*)|(?P<operator><-|->|=>|<>|\+\+|[(){}\[\],:<>=+&~.*\-/])''')

def tokenize(source: str) -> list[Token]:
    tokens = []
    position = 0
    line = 1
    start = 0
    while position < len(source):
        m = TOKEN.match(source, position)
        if m is None:
            raise ValueError(f"unsupported character at {line}:{position-start+1}: {source[position:position+50]!r}")
        k = m.lastgroup
        text = m.group()
        if k not in ('space', 'comment'):
            tokens.append(Token(text, line, position-start))
        if k == 'newline':
            line += 1
            start = m.end()
        position = m.end()
    tokens.append(Token('<EOF>', line, 0))
    return tokens

class Parser:
    def __init__(self, source: str, name: str):
        self.source, self.name = source, name
        self.tokens = tokenize(source)
        self.i = 0

    def peek(self) -> Token:
        return self.tokens[self.i]

    def text(self) -> str:
        return self.peek().text

    def take(self, wanted: str | None = None) -> Token:
        token = self.peek()
        if wanted is not None and token.text != wanted:
            self.error(f"expected {wanted!r}, found {token.text!r}")
        self.i += 1
        return token

    def accept(self, value: str) -> bool:
        if self.text() == value:
            self.i += 1
            return True
        return False

    def nl(self):
        while self.accept('\n'):
            pass

    def error(self, message: str):
        t = self.peek()
        raise ValueError(f"{self.name}.bend:{t.line}:{t.column+1}: {message}; near {' '.join(x.text for x in self.tokens[self.i:self.i+12])!r}")

    def namespec(self) -> str:
        self.nl()
        while self.text() in ('+', '-', '~'):
            self.take()
        t = self.take()
        if not re.fullmatch(r'[A-Za-z_][A-Za-z_0-9]*(?:\.[A-Za-z_][A-Za-z_0-9]*)*', t.text):
            self.error(f"expected identifier, got {t.text!r}")
        return t.text

    def type(self, minimum: int = 0) -> Node:
        self.nl()
        while self.text() in ('+', '-', '~'):
            self.take()
        token = self.take()
        if token.text == '&':
            left = Node('multiplicity', self.take().text, line=token.line)
        elif token.text == '(':
            left = self.type()
            self.take(')')
        elif re.fullmatch(r'[A-Za-z_][\w.]*', token.text):
            left = Node('type', token.text, line=token.line)
            if self.text() in ('<', '('):
                close = '>' if self.take().text == '<' else ')'
                args = []
                self.nl()
                if self.text() != close:
                    while True:
                        args.append(self.type())
                        self.nl()
                        if not self.accept(','):
                            break
                self.take(close)
                left.items = args
        else:
            self.error(f"invalid type starting {token.text!r}")
        while True:
            op = self.text()
            prec = {'->': 1, '&': 2}.get(op, -1)
            if prec < minimum:
                break
            self.take()
            right = self.type(prec if op == '->' else prec + 1)
            if op == '&' and left.kind == 'product':
                left.items.append(right)
            else:
                left = Node('arrow' if op == '->' else 'product', items=[left, right], line=token.line)
        return left

    def expressions(self, close: str) -> list[Node]:
        result = []
        self.nl()
        if self.accept(close):
            return result
        while True:
            result.append(self.expression())
            self.nl()
            if self.accept(close):
                return result
            self.take(',')
            self.nl()
            if self.accept(close):
                return result

    def expression(self, minimum: int = 0, pattern: bool = False) -> Node:
        self.nl()
        while self.text() in ('+', '~'):
            self.take()
        token = self.take()
        value = token.text
        if value == 'match':
            values = []
            while self.text() != ':':
                values.append(self.expression())
            self.take(':'); self.nl()
            arms = []
            indent = self.peek().column
            while self.text() == 'case' and self.peek().column == indent:
                self.take()
                patterns = []
                while self.text() != ':':
                    patterns.append(self.expression(pattern=True))
                if len(patterns) != len(values):
                    self.error(f"match has {len(values)} inputs and {len(patterns)} patterns")
                self.take(':')
                body = self.sequence()
                arms.append((patterns, body))
                self.nl()
            if not arms:
                self.error('match without cases')
            return Node('match', items=[values, arms], line=token.line)
        if value == 'do':
            monad = self.type()
            self.take(':')
            return Node('do', monad, [self.sequence(monad)], token.line)
        if value == 'return':
            return Node('return', items=[self.expression()], line=token.line)
        if value == 'import':
            return Node('foreign', self.take().text, line=token.line)
        if value == '(':
            self.nl()
            if self.accept(')'):
                left = Node('tuple', items=[], line=token.line)
            else:
                first = self.expression(pattern=pattern)
                if self.accept(':'):
                    annotation = self.type()
                    self.take(')')
                    left = Node('annotate', annotation, [first], token.line)
                else:
                    items = [first]
                    self.nl()
                    while self.accept(','):
                        items.append(self.expression(pattern=pattern)); self.nl()
                    self.take(')')
                    left = items[0] if len(items) == 1 else Node('tuple', items=items, line=token.line)
        elif value == '[':
            self.nl()
            if self.accept(']'):
                left = Node('list', items=[], line=token.line)
            else:
                first = self.expression(pattern=pattern)
                if self.accept(':'):
                    annotation = self.type(); self.take('*')
                    count = self.expression(); self.take(']')
                    left = Node('array_repeat', annotation, [first, count], token.line)
                else:
                    items = [first]; self.nl()
                    while self.accept(','):
                        items.append(self.expression(pattern=pattern)); self.nl()
                    self.take(']')
                    left = Node('list', items=items, line=token.line)
        elif value == '{':
            left = self.expression()
            self.take(':')
            annotation = self.type()
            self.take('}')
            left = Node('annotate', annotation, [left], token.line)
        elif value == '&':
            left = Node('multiplicity', self.take().text, line=token.line)
        elif value == '-':
            left = Node('negate', items=[self.expression(40, pattern)], line=token.line)
        elif value.startswith('"'):
            left = Node('string', json.loads(value), line=token.line)
        elif value.startswith("'"):
            import ast
            ch = ast.literal_eval(value)
            if len(ch) != 1:
                self.error('character literal must have one code point')
            left = Node('char', ord(ch), line=token.line)
        elif re.fullmatch(r'\d+n', value):
            left = Node('nat', int(value[:-1]), line=token.line)
        elif re.fullmatch(r'\d+\.\d+(?:[eE][+-]?\d+)?', value):
            left = Node('float', value, line=token.line)
        elif re.fullmatch(r'(?:0[xX][\da-fA-F]+|\d+)', value):
            left = Node('u32', int(value, 0) if value.lower().startswith('0x') else int(value), line=token.line)
        elif re.fullmatch(r'[A-Za-z_][\w.]*', value):
            left = Node('name', value, line=token.line)
            if self.text() == '<':
                self.take()
                args = []
                while True:
                    args.append(self.type())
                    if not self.accept(','):
                        break
                self.take('>')
                left = Node('type', value, args, token.line)
        else:
            self.error(f"invalid expression starting {value!r}")
        while True:
            if self.text() == '(':
                self.take()
                left = Node('call', items=[left, self.expressions(')')], line=token.line)
                continue
            if self.text() == '{':
                self.take()
                if left.kind not in ('name', 'type'):
                    self.error('constructor must have a name')
                left = Node('constructor', left.value, self.expressions('}'), token.line)
                continue
            op = self.text()
            if pattern and op == '+' and left.kind != 'nat':
                break
            if op == '=>' and minimum <= 0:
                if left.kind != 'name':
                    self.error('lambda binder must be a name')
                self.take()
                left = Node('lambda', left.value, [self.expression()], token.line)
                continue
            prec = {'<>': 10, '++': 20, '+': 30}.get(op, -1)
            if prec < minimum:
                break
            self.take()
            right = self.expression(prec if op in ('<>', '++') or (pattern and op == '+') else prec + 1, pattern)
            left = Node('binary', op, [left, right], token.line)
        return left

    def sequence(self, monad: Node | None = None) -> Node:
        self.nl()
        indent = self.peek().column
        first = self.expression()
        if first.kind == 'name' and self.peek().line == first.line and self.text() not in (':', '=', '<-', '\n', ')', '}', ']', '<EOF>'):
            patterns = [first]
            while self.text() != '=':
                patterns.append(self.expression(pattern=True))
            self.take('=')
            values = [self.expression() for _ in patterns]
            self.nl()
            return Node('parallel_let', items=[patterns, values, self.sequence(monad)], line=first.line)
        annotation = None
        if self.accept(':'):
            annotation = self.type()
        if self.text() in ('=', '<-'):
            op = self.take().text
            rhs = self.expression()
            self.nl()
            if self.peek().column < indent or self.text() in (')', '}', ']', '<EOF>'):
                self.error('binding without a following expression')
            rest = self.sequence(monad)
            return Node('bind' if op == '<-' else 'let', annotation, [first, rhs, rest], first.line)
        if annotation is not None:
            self.error('annotation without a binding')
        if self.text() == '\n':
            saved = self.i
            self.nl()
            if monad is not None and self.peek().column == indent and self.text() not in ('case', 'def', 'type', 'import', '<EOF>'):
                return Node('bind', items=[Node('name', '_'), first, self.sequence(monad)], line=first.line)
            self.i = saved
        return first

    def module(self) -> Module:
        imports, types, functions = {}, [], []
        self.nl()
        while self.text() != '<EOF>':
            token = self.take()
            if token.text == 'import':
                parts = []
                while self.text() not in ('\n', '<EOF>'):
                    parts.append(self.take().text)
                if parts == ['Base']:
                    pass
                elif 'as' in parts:
                    p = parts.index('as')
                    path = ''.join(parts[:p])
                    imports[parts[p+1]] = Path(path).stem
                else:
                    self.error(f'unsupported import {parts}')
            elif token.text == 'type':
                name = self.namespec()
                params = []
                if self.accept('<') or self.accept('<-'):
                    while True:
                        params.append(self.namespec())
                        self.take(':'); self.type()
                        if not self.accept(','):
                            break
                    self.take('>')
                self.take('is')
                kind = self.take().text
                if kind not in ('Data', 'Type'):
                    self.error(f'unsupported data kind {kind}')
                self.take(':'); self.nl()
                ctors = []
                while self.peek().column > 0 and self.text() != '<EOF>':
                    ctor = self.namespec()
                    self.take('{')
                    fields = []
                    if not self.accept('}'):
                        while True:
                            field = self.namespec()
                            self.take(':')
                            fields.append((field, self.type()))
                            self.nl()
                            if self.accept('}'):
                                break
                            self.take(',')
                    ctors.append((ctor, fields)); self.nl()
                types.append(DataType(name, params, ctors, token.line))
            elif token.text == 'def':
                name = self.namespec()
                self.take('(')
                params = []
                if not self.accept(')'):
                    while True:
                        param = self.namespec()
                        self.take(':')
                        ty = self.type()
                        params.append(Parameter(param, ty, ty.kind == 'type' and ty.value in ('Data', 'Type')))
                        self.nl()
                        if self.accept(')'):
                            break
                        self.take(',')
                self.take('->'); result = self.type(); self.take(':')
                body = self.sequence()
                functions.append(Function(name, params, result, body, token.line))
            else:
                self.error(f'unsupported top-level item {token.text!r}')
            self.nl()
            if self.peek().column != 0:
                self.error('unconsumed function body')
        return Module(self.name, imports, types, functions, hashlib.sha256(self.source.encode()).hexdigest())


def load_modules(root: Path, entry: str) -> list[Module]:
    ordered = []
    seen = set()
    active = set()
    def visit(name):
        if name in seen:
            return
        if name in active:
            raise ValueError(f'cyclic module import at {name}')
        active.add(name)
        path = root / (name + '.bend')
        mod = Parser(path.read_text(), name).module()
        for dep in mod.imports.values():
            visit(dep)
        active.remove(name); seen.add(name); ordered.append(mod)
    visit(entry)
    return ordered


