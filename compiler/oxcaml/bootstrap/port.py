#!/usr/bin/env python3
"""Reproduce the initial typed OCaml semantic port. Not used by the executable."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
from syntax import Node, Function, Module, load_modules

BASE_TYPES = {
    'Unit': 'unit', 'Bool': 'bool', 'Nat': 'int', 'U32': 'int32',
    'F32': 'int32', 'Char': 'Base.char32', 'String': 'Base.text',
    'Cmp': 'Base.cmp', 'Set': 'Base.set',
}
BASE_FUNCTIONS = {
    name: name.lower().replace('.', '_') for name in '''
Array.get Array.new Array.set
Char.is_eq Char.to_u32
Bool.and Bool.not Bool.or Bool.pick Bool.xor
F32.abs F32.add F32.bits F32.ceil F32.div F32.floor F32.is_eq F32.is_ge F32.is_gt F32.is_le F32.is_lt F32.is_ne F32.mul F32.neg F32.read F32.sqrt F32.sub F32.to_u32 F32.trunc
IO.args IO.die IO.now IO.print IO.pure
List.append List.drop List.is_empty List.length List.merge List.merge.go List.replicate List.reverse List.reverse.go List.sort List.take
Map.get Map.new Map.set Map.union Map.values
Maybe.is_none Maybe.is_some Maybe.or
Nat.add Nat.cmp Nat.div Nat.is_eq Nat.is_ge Nat.is_gt Nat.is_le Nat.is_lt Nat.is_ne Nat.max Nat.min Nat.mod Nat.mul Nat.read Nat.show Nat.sub
Set.add Set.from_list Set.new Set.size Set.to_list
String.append String.drop String.eq String.is_le String.is_lt String.join String.length String.reverse String.split String.starts_with
U32.add U32.and U32.cmp U32.div U32.from_nat U32.is_eq U32.is_ge U32.is_gt U32.is_le U32.is_lt U32.is_ne U32.max U32.mod U32.mul U32.or U32.shln U32.show U32.shr U32.shrn U32.sub U32.to_f32 U32.to_nat
'''.split()
}
BASE_ZERO_ARITY = {'Map.new', 'Set.new', 'IO.args', 'IO.now', 'U32.max'}
BASE_CTORS = {'Unit': '()', 'True': 'true', 'False': 'false', 'Nil': '[]', 'None': 'None'}

def ml_string(value: str) -> str:
    result = ['"']
    for ch in value.encode('utf-8'):
        if ch == 34:
            result.append('\\"')
        elif ch == 92:
            result.append('\\\\')
        elif 32 <= ch < 127:
            result.append(chr(ch))
        else:
            result.append(f'\\{ch:03d}')
    return ''.join(result) + '"'

def ml_var(name: str) -> str:
    return '_' if name == '_' else 'v_' + name

class Emitter:
    def __init__(self, module: Module, modules: dict[str, Module]):
        self.module = module
        self.modules = modules
        self.functions = {f.name: f for f in module.functions}
        self.aliases = {f.name for f in module.functions if f.result.kind == 'type' and f.result.value in ('Data', 'Type')}
        self.type_names = {t.name for t in module.types} | self.aliases
        self.strings: dict[str, str] = {}
        self.unique = 0

    def fresh(self, prefix='tmp') -> str:
        self.unique += 1
        return f'__{prefix}_{self.unique}'

    def type(self, ty: Node, variables: set[str] | None = None) -> str:
        variables = variables or set()
        if ty.kind == 'arrow':
            return '(' + self.type(ty.items[0], variables) + ' -> ' + self.type(ty.items[1], variables) + ')'
        if ty.kind == 'product':
            return '(' + ' * '.join(self.type(t, variables) for t in ty.items) + ')'
        if ty.kind == 'call' and ty.items[0].kind == 'name':
            ty = Node('type', ty.items[0].value, ty.items[1], ty.line)
        if ty.kind not in ('type', 'name'):
            raise ValueError(f'{self.module.name}:{ty.line}: unsupported type node {ty.kind}')
        name = ty.value
        if name in variables:
            return "'" + name.lower()
        args = [self.type(t, variables) for t in ty.items if t.kind != 'multiplicity']
        if name in BASE_TYPES:
            if args:
                raise ValueError(f'unexpected type args to {name}')
            return BASE_TYPES[name]
        builtin = {'List': 'list', 'Maybe': 'option', 'Result': 'Base.result_', 'Map': 'Base.map', 'Array': 'array', 'IO': 'Base.io'}.get(name)
        if builtin:
            target = builtin
        elif '.' in name:
            prefix, tail = name.split('.', 1)
            if prefix not in self.module.imports:
                raise ValueError(f'{self.module.name}: unknown type qualifier {name}')
            target = prefix + '.t_' + tail
        elif name in self.type_names:
            target = 't_' + name
        else:
            raise ValueError(f'{self.module.name}:{ty.line}: unknown type {name}')
        if not args:
            return target
        if len(args) == 1:
            return '(' + args[0] + ') ' + target
        return '(' + ', '.join(args) + ') ' + target

    def is_type_value(self, expr: Node, type_variables: set[str]) -> bool:
        if expr.kind in ('type', 'multiplicity'):
            return True
        if expr.kind == 'name':
            if expr.value in type_variables or expr.value in BASE_TYPES or expr.value in self.type_names:
                return True
            if '.' in expr.value:
                alias, name = expr.value.split('.', 1)
                if alias in self.module.imports:
                    mod = self.modules[self.module.imports[alias]]
                    return any(t.name == name for t in mod.types) or any(f.name == name and f.result.value in ('Data', 'Type') for f in mod.functions)
        if expr.kind == 'call' and expr.items[0].kind == 'name':
            target = expr.items[0].value
            return target == 'Set' or target in self.aliases
        return False

    def function(self, name: str, scope: set[str]) -> tuple[str, Function | None, bool]:
        if name in scope:
            return ml_var(name), None, False
        if name in BASE_FUNCTIONS:
            return 'Base.' + BASE_FUNCTIONS[name], None, True
        if '.' in name:
            prefix, tail = name.split('.', 1)
            if prefix in self.module.imports:
                mod = self.modules[self.module.imports[prefix]]
                found = next((f for f in mod.functions if f.name == tail), None)
                if found is None:
                    raise ValueError(f'{self.module.name}: unknown imported function {name}')
                return prefix + '.f_' + tail, found, False
        elif name in self.functions:
            return 'f_' + name, self.functions[name], False
        raise ValueError(f'{self.module.name}: unresolved value {name}')

    def constructor(self, name: str, values: list[str]) -> str:
        if name in BASE_CTORS:
            if values:
                raise ValueError(f'{name} has unexpected fields')
            return BASE_CTORS[name]
        if name in ('U32', 'F32'):
            if len(values) != 1:
                raise ValueError('scalar wrapper arity')
            return values[0]
        if name == 'Con':
            return '(' + values[0] + ' :: ' + values[1] + ')'
        if name == 'Tuple':
            return '(' + ', '.join(values) + ')'
        if not values:
            return name
        if len(values) == 1:
            return '(' + name + ' (' + values[0] + '))'
        return '(' + name + ' (' + ', '.join(values) + '))'

    def pattern(self, node: Node) -> tuple[str, list[str], list[tuple[str, str]], set[str]]:
        guards, bindings, names = [], [], set()
        from collections import Counter
        counts = Counter()
        def count_names(n):
            if n.kind == 'name' and n.value != '_': counts[n.value] += 1
            for child in n.items:
                if isinstance(child, Node): count_names(child)
        count_names(node)
        def go(n):
            k = n.kind
            if k == 'name':
                if n.value != '_':
                    names.add(n.value)
                    if counts[n.value] > 1:
                        fresh = self.fresh('shadow')
                        bindings.append((ml_var(n.value), fresh))
                        return fresh
                return ml_var(n.value)
            if k == 'nat': return str(n.value)
            if k == 'u32': return f'0x{n.value:08x}l'
            if k == 'char': return f'(Chr 0x{n.value:08x}l)'
            if k == 'string':
                tail = 'SNil'
                for c in reversed(n.value):
                    tail = f'(SCon (Chr 0x{ord(c):08x}l, {tail}))'
                return tail
            if k == 'constructor': return self.constructor(n.value, [go(x) for x in n.items])
            if k == 'tuple': return '(' + ', '.join(go(x) for x in n.items) + ')'
            if k == 'list': return '[' + '; '.join(go(x) for x in n.items) + ']'
            if k == 'annotate': return go(n.items[0])
            if k == 'binary' and n.value == '<>': return '(' + go(n.items[0]) + ' :: ' + go(n.items[1]) + ')'
            if k == 'binary' and n.value == '+':
                count = 0
                tail = n
                while tail.kind == 'binary' and tail.value == '+' and tail.items[0].kind == 'nat':
                    count += tail.items[0].value
                    tail = tail.items[1]
                if tail.kind == 'nat': return str(count + tail.value)
                if tail.kind != 'name':
                    raise ValueError(f'{self.module.name}:{n.line}: unsupported Nat pattern')
                fresh = self.fresh('nat')
                guards.append(f'{fresh} >= {count}')
                if tail.value != '_':
                    names.add(tail.value)
                    bindings.append((ml_var(tail.value), f'({fresh} - {count})'))
                return fresh
            raise ValueError(f'{self.module.name}:{n.line}: unsupported pattern {k}')
        return go(node), guards, bindings, names

    @staticmethod
    def lets(bindings: list[tuple[str, str]], body: str) -> str:
        for name, value in reversed(bindings):
            body = f'(let {name} = {value} in\n{body})'
        return body

    def expression(self, n: Node, scope: set[str], variables: set[str], monad: str | None = None) -> str:
        exp = lambda x: self.expression(x, scope, variables, monad)
        k = n.kind
        if k == 'nat': return str(n.value)
        if k == 'u32':
            if not 0 <= n.value <= 0xffffffff:
                raise ValueError('U32 literal out of range')
            return f'0x{n.value:08x}l'
        if k == 'float':
            import struct
            bits = struct.unpack('<I', struct.pack('<f', float(n.value)))[0]
            return f'0x{bits:08x}l'
        if k == 'char': return f'(Chr 0x{n.value:08x}l)'
        if k == 'string':
            if n.value not in self.strings:
                self.strings[n.value] = 's_' + str(len(self.strings))
            return self.strings[n.value]
        if k == 'name':
            return self.function(n.value, scope)[0]
        if k == 'constructor': return self.constructor(n.value, [exp(x) for x in n.items])
        if k == 'tuple': return '(' + ', '.join(exp(x) for x in n.items) + ')'
        if k == 'list': return '[' + '; '.join(exp(x) for x in n.items) + ']'
        if k == 'array_repeat': return f'(Stdlib.Array.make {exp(n.items[1])} {exp(n.items[0])})'
        if k == 'annotate': return exp(n.items[0])
        if k == 'negate': return '(Base.f32_neg ' + exp(n.items[0]) + ')'
        if k == 'binary':
            a, b = n.items
            if n.value == '<>': return '(' + exp(a) + ' :: ' + exp(b) + ')'
            if n.value == '++': return '(Base.string_append ' + exp(a) + ' ' + exp(b) + ')'
            if n.value == '+':
                primitive = 'nat_add' if a.kind == 'nat' or b.kind == 'nat' else 'u32_add'
                return f'(Base.{primitive} {exp(a)} {exp(b)})'
            raise ValueError('unknown binary expression')
        if k == 'call':
            callee, args = n.items
            decl = None
            builtin = False
            if callee.kind == 'name':
                target, decl, builtin = self.function(callee.value, scope)
            else:
                target = exp(callee)
            if decl is not None:
                if len(args) > len(decl.parameters):
                    raise ValueError(f'{self.module.name}:{n.line}: too many arguments for {callee.value}')
                kept = [a for a, p in zip(args, decl.parameters) if not p.erased]
                # A generic-only declaration still denotes a computation, not a shared value.
                zero_call = len(args) == len(decl.parameters) and not any(not p.erased for p in decl.parameters)
            elif builtin:
                kept = [a for a in args if not self.is_type_value(a, variables)]
                zero_call = callee.value in BASE_ZERO_ARITY and not kept
            else:
                kept = args
                zero_call = not kept
            if kept:
                return '(' + target + ' ' + ' '.join('(' + exp(a) + ')' for a in kept) + ')'
            return '(' + target + ' ())' if zero_call else target
        if k == 'lambda':
            return '(fun ' + ml_var(n.value) + ' ->\n' + self.expression(n.items[0], scope | {n.value}, variables, monad) + ')'
        if k == 'do':
            if n.value.value not in ('Result', 'Maybe', 'IO'):
                raise ValueError('unsupported monad ' + n.value.value)
            return self.expression(n.items[0], scope, variables, n.value.value)
        if k == 'return':
            ctor = {'Result': 'Done', 'Maybe': 'Some', 'IO': 'Base.io_pure'}.get(monad)
            if ctor is None:
                raise ValueError(f'{self.module.name}:{n.line}: return outside do')
            return '(' + ctor + ' (' + exp(n.items[0]) + '))'
        if k in ('let', 'bind'):
            pat, rhs, rest = n.items
            p, guards, bindings, names = self.pattern(pat)
            body = self.expression(rest, scope | names, variables, monad)
            body = self.lets(bindings, body)
            value = exp(rhs)
            if k == 'let':
                if guards:
                    return f'(match {value} with\n| {p} when {" && ".join(guards)} -> {body}\n| _ -> failwith "invalid Nat destructuring")'
                return f'(let {p} = {value} in\n{body})'
            if monad == 'Result':
                if guards: raise ValueError('guarded result binding')
                return f'(match {value} with\n| Fail __error -> Fail __error\n| Done {p} ->\n{body})'
            if monad == 'Maybe':
                if guards: raise ValueError('guarded option binding')
                return f'(match {value} with\n| None -> None\n| Some {p} ->\n{body})'
            if monad == 'IO':
                return f'(Base.io_bind {value} (fun {p} ->\n{body}))'
            raise ValueError(f'{self.module.name}:{n.line}: bind outside do')
        if k == 'parallel_let':
            patterns, values, rest = n.items
            out, names = [], set()
            for p, value in zip(patterns, values):
                pattern, guards, bindings, bound = self.pattern(p)
                if guards or bindings: raise ValueError('guarded parallel binding')
                out.append((pattern, exp(value))); names |= bound
            return self.lets(out, self.expression(rest, scope | names, variables, monad))
        if k == 'match':
            values, arms = n.items
            scrutinee = exp(values[0]) if len(values) == 1 else '(' + ', '.join(exp(v) for v in values) + ')'
            lines = ['(match ' + scrutinee + ' with']
            for patterns, body in arms:
                whole = patterns[0] if len(patterns) == 1 else Node('tuple', items=patterns)
                pat, guards, bindings, names = self.pattern(whole)
                guard = ' when ' + ' && '.join(guards) if guards else ''
                result = self.lets(bindings, self.expression(body, scope | names, variables, monad))
                lines.append('| ' + pat + guard + ' ->\n' + result)
            return '\n'.join(lines) + ')'
        if k == 'foreign':
            raise ValueError('foreign functions require a reviewed native transport implementation')
        raise ValueError(f'{self.module.name}:{n.line}: unhandled expression {k}')

    def emit(self) -> str:
        header = [f'(* Native semantic port of compiler/{self.module.name}.bend.',
                  f'   Source SHA-256: {self.module.digest}',
                  '   Ownership/type arguments are erased; value types are checked by OCaml.',
                  '   No Bend interpreter or generated C/JavaScript is linked. *)',
                  'open Base']
        for alias, name in self.module.imports.items():
            header.append(f'module {alias} = Ox_{name}')
        types = []
        for t in self.module.types:
            variables = set(t.parameters)
            args = ["'" + v.lower() for v in t.parameters]
            prefix = '' if not args else (args[0] + ' ' if len(args) == 1 else '(' + ', '.join(args) + ') ')
            parts = [prefix + 't_' + t.name + ' =']
            for name, fields in t.constructors:
                payload = ' of ' + ' * '.join(self.type(ty, variables) for _, ty in fields) if fields else ''
                parts.append('  | ' + name + payload)
            types.append('\n'.join(parts))
        for name in sorted(self.aliases):
            f = self.functions[name]
            if f.parameters:
                raise ValueError('parameterized type aliases need explicit support')
            types.append('t_' + name + ' = ' + self.type(f.body))
        if types:
            header.append('type ' + '\nand '.join(types))
        declarations = []
        for f in self.module.functions:
            if f.name in self.aliases: continue
            parameters = [p for p in f.parameters if not p.erased]
            variables = {p.name for p in f.parameters if p.erased}
            scope = {p.name for p in parameters}
            arg_types = [self.type(p.type, variables) for p in parameters] or ['unit']
            signature = ' -> '.join(arg_types + [self.type(f.result, variables)])
            quant = ' '.join("'" + v.lower() for v in sorted(variables)) + '. ' if variables else ''
            body = self.expression(f.body, scope, variables)
            arguments = ' '.join(ml_var(p.name) for p in parameters) or '()'
            declarations.append(f'(* {self.module.name}.bend:{f.line} *)\nf_{f.name} : {quant}{signature} =\nfun {arguments} ->\n{body}')
        for value, name in self.strings.items():
            header.append(f'let {name} = Base.text_of_utf8 {ml_string(value)}')
        if declarations:
            header.append('let rec ' + '\nand '.join(declarations))
        return '\n\n'.join(header) + '\n'


def emit_modules(modules: list[Module], output: Path):
    output.mkdir(parents=True, exist_ok=True)
    lookup = {m.name: m for m in modules}
    manifest = []
    for module in modules:
        name = 'ox_' + module.name + '.ml'
        if module.name == 'native_transport':
            # This module's two FFI declarations are replaced by reviewed OCaml IO.
            continue
        text = Emitter(module, lookup).emit()
        (output / name).write_text(text)
        manifest.append({'module': module.name, 'source_sha256': module.digest, 'ocaml_sha256': hashlib.sha256(text.encode()).hexdigest(), 'functions': len(module.functions), 'types': len(module.types)})
    (output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    (output / 'modules.txt').write_text('\n'.join('ox_' + m.name for m in modules) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--entry', default='native_main')
    parser.add_argument('--output', type=Path, default=Path(__file__).resolve().parents[1] / 'core')
    parser.add_argument('--parse-only', action='store_true')
    args = parser.parse_args()
    modules = load_modules(args.source, args.entry)
    print(f'Parsed {len(modules)} modules, {sum(len(m.functions) for m in modules)} functions, {sum(len(m.types) for m in modules)} algebraic types')
    if not args.parse_only:
        emit_modules(modules, args.output)

if __name__ == '__main__':
    main()
