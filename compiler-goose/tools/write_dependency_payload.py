#!/usr/bin/env python3
"""Generate typed payload ownership (dependency_payload.goose) and O(1) payload
byte accounting (payload_bytes.goose) directly from the Goose payload structs.

Only slice runs and the small set of compound structs that transitively own a
slice get cloneValue/partitionInto code; flat slices clone via copy<T> (bulk
move_from) and partition in O(1) without per-element loops.
"""
from pathlib import Path
import re
from source_model import balanced, clean, split

ROOT = Path(__file__).resolve().parents[1] / 'src'

ROOT_TYPES = [
    'squid_check_core::Module',
    'squid_reuse_principal_interface::Interface',
    'squid_reuse_frozen_dependency::Module',
    'squid_reuse_frozen_dependency::FrozenDependency',
]

# Extra header-level slice pools retained by project/dependency drivers.
HEADER_RUNS = [
    ('header_module', 'squid_check_core::Module'),
    ('header_path', 'HeaderPath'),
    ('header_digest', 'HeaderDigest'),
    ('header_owner', 'Owner'),
    ('bool', 'bool'),
]

# Zig @sizeOf (padding included) for frozen payload accounting in payload_bytes.
ELEMENT_BYTES = {
    'u8': 1,
    'u32': 4,
    'squid_parse_ast::Span': 8,
    'squid_check_core::FieldName': 12,
    'squid_check_core::TypeTag': 28,
    'squid_check_core::RuntimeName': 8,
    'squid_check_core::DeclarationDependencies': 20,
    'squid_check_core::BindingRef': 8,
    'squid_check_core::DependencyMember': 5,
    'squid_check_core::ErasedDeclarationReference': 12,
    'squid_check_types::Node': 16,
    'squid_check_effects::Row': 20,
    'squid_check_types::Operation': 24,
    'squid_check_types::Obligation': 52,
    'squid_check_core::Node': 20,
    'squid_check_core::Binding': 112,
    'squid_check_core::Body': 96,
    'squid_check_core::Parameter': 20,
    'squid_check_core::CallInfo': 12,
    'squid_check_core::Merge': 16,
    'squid_check_core::List': 8,
    'squid_check_core::Obligation': 64,
    'squid_check_core::Nominal': 68,
    'squid_check_core::OperationName': 48,
    'squid_check_core::Constructor': 68,
    'squid_check_core::Projection': 32,
    'squid_check_core::ProjectionVariant': 8,
    'squid_check_core::Pattern': 28,
    'squid_check_core::PatternRow': 8,
    'squid_check_core::MatchArm': 24,
    'squid_check_core::MatchInfo': 20,
    'squid_check_core::UpdateInfo': 28,
    'squid_check_core::UpdateStep': 20,
    'squid_check_core::ClosureInfo': 48,
    'squid_check_core::Associated': 24,
    'squid_check_core::Contract': 72,
    'squid_reuse_principal_interface::ContractMember': 20,
    'squid_reuse_principal_interface::Implementation': 104,
    'squid_reuse_principal_interface::ImplementationMember': 20,
    'squid_reuse_principal_interface::MemberTemplate': 24,
    'squid_check_core::Primitive': 8,
    'squid_check_core::LoopInfo': 28,
    'squid_check_core::LoopCarry': 16,
    'squid_check_core::SparkInfo': 28,
    'squid_check_core::KernelDecl': 56,
    'squid_check_core::ProcessDecl': 52,
    'squid_check_core::OperationValue': 40,
    'squid_check_core::HandleEffects': 20,
    'squid_check_core::Diagnostic': 12,
    'squid_check_parameter_patterns::Node': 12,
    'squid_reuse_principal_interface::Binding': 88,
    'squid_reuse_principal_interface::Nominal': 88,
    'squid_reuse_principal_interface::Constructor': 72,
    'squid_reuse_principal_interface::EffectFamily': 56,
    'squid_reuse_principal_interface::EffectTemplate': 24,
    'squid_reuse_principal_interface::Associated': 20,
    'squid_reuse_principal_interface::Contract': 92,
}

# Unwired Module slices are kept out of wire/frozen byte totals to match Zig accounting.
PAYLOAD_BYTES_SKIP = {
    ('squid_check_core::Module', 'declaration_dependencies'),
    ('squid_check_core::Module', 'dependency_references'),
    ('squid_check_core::Module', 'dependency_members'),
    ('squid_check_core::Module', 'erased_declaration_references'),
}

PRIMS = {'bool', 'u8', 'u16', 'u32', 'u64', 'i8', 'i16', 'i32', 'i64', 'f32', 'f64'}


def parse_declarations():
    decls = {}
    paths = {}
    for path in sorted(ROOT.rglob('*.goose')):
        if path.name.startswith('_') or (path.parent == ROOT and 'probe' in path.stem):
            continue
        source = clean(path.read_text())
        ns_match = re.search(r'\bnamespace\s+(\w+)\s*;', source)
        if not ns_match:
            continue
        ns = ns_match[1]
        module_path = path.relative_to(ROOT).with_suffix('').as_posix().replace('/', '.')
        paths.setdefault(ns, module_path)
        if ns == 'squid_' + module_path.replace('.', '_'):
            paths[ns] = module_path
        for m in re.finditer(r'\b(struct|enum|type)\s+(\w+)\s*(<[^>{}]+>)?\s*(\{|=)', source):
            kind, name, params, tok = m.groups()
            key = ns + '::' + name
            if tok == '=':
                if kind == 'type':
                    decls[key] = ('alias', [], source[m.end():source.find(';', m.end())].strip(), ns)
            else:
                end = balanced(source, m.end() - 1)
                body = source[m.end():end]
                data = []
                if kind == 'struct':
                    for part in split(body):
                        fm = re.match(r'^(\w+)\s*:\s*(.*)$', part, re.S)
                        if fm:
                            data.append((fm[1], split(fm[2], '=')[0].strip()))
                else:
                    for part in split(body):
                        vm = re.fullmatch(r'(\w+)\s*(?:\{(.*)\})?', part, re.S)
                        if vm:
                            fs = []
                            for field in split(vm[2] or ''):
                                fm = re.match(r'^(\w+)\s*:\s*(.*)$', field, re.S)
                                if fm:
                                    fs.append((fm[1], split(fm[2], '=')[0].strip()))
                            data.append((vm[1], fs))
                decls[key] = (kind, split((params or '<>')[1:-1]), data, ns)
    return decls, paths


def ident(ty: str) -> str:
    return ty.replace('::', '__')


def main():
    decls, paths = parse_declarations()

    def qualify(t, ns, subs=None):
        subs = subs or {}
        return re.sub(
            r'(?<![\w:])\b\w+\b(?!::)',
            lambda m: subs.get(m[0], ns + '::' + m[0] if ns + '::' + m[0] in decls else m[0]),
            t,
        )

    def resolve(t, ns):
        t = re.sub(r'\s+', ' ', qualify(t, ns)).strip()
        t = re.sub(r'^const\s+', '', t)
        m = re.fullmatch(r'(.+)\[(:|\d+)\]', t)
        if m:
            return resolve(m[1], ns) + '[' + m[2] + ']'
        if t.startswith('squid_support::Option<') and t.endswith('>'):
            inner = t[len('squid_support::Option<'):-1]
            return 'squid_support::Option<' + resolve(inner, ns) + '>'
        m = re.fullmatch(r'(\w+::\w+)(?:<(.*)>)?', t, re.S)
        if m and m[1] in decls:
            k, ps, data, owner = decls[m[1]]
            if k == 'alias':
                return resolve(qualify(data, owner, dict(zip(ps, split(m[2] or '')))), owner)
        return t

    has_slice_memo = {}
    slice_elems = []
    slice_seen = set()
    compounds = []
    compound_seen = set()

    def record_slice(elem):
        if elem not in slice_seen:
            slice_seen.add(elem)
            slice_elems.append(elem)

    def analyze(t, ns):
        t = resolve(t, ns)
        if t in has_slice_memo:
            return has_slice_memo[t]
        if t in PRIMS:
            has_slice_memo[t] = False
            return False
        m = re.fullmatch(r'(.+)\[(:|\d+)\]', t)
        if m:
            inner = resolve(m[1], ns)
            if m[2] == ':':
                record_slice(inner)
                analyze(inner, ns)
                has_slice_memo[t] = True
                return True
            inner_has = analyze(inner, ns)
            assert not inner_has, f'Array of slice-owning elements unsupported: {t}'
            has_slice_memo[t] = False
            return False
        if t.startswith('squid_support::Option<'):
            inner = resolve(t[len('squid_support::Option<'):-1], ns)
            inner_has = analyze(inner, ns)
            assert not inner_has, f'Option of slice-owning value unsupported: {t}'
            has_slice_memo[t] = False
            return False
        m = re.fullmatch(r'(\w+::\w+)', t)
        assert m and m[1] in decls, f'Unknown payload type: {t}'
        kind, params, data, owner = decls[m[1]]
        assert not params, f'Generic payload type unsupported: {t}'
        if kind == 'enum':
            for _, fs in data:
                for _, ft in fs:
                    assert not analyze(ft, owner), f'Enum variant owns slice: {t}'
            has_slice_memo[t] = False
            return False
        assert kind == 'struct', f'Unexpected kind {kind} for {t}'
        scalar_fields = []
        owned_fields = []
        has_owner_id = False
        for fname, raw_ft in data:
            if fname == 'owner_id':
                has_owner_id = True
                continue
            ft = resolve(raw_ft, owner)
            if analyze(ft, owner):
                owned_fields.append((fname, ft))
            else:
                scalar_fields.append(fname)
        is_compound = bool(owned_fields)
        has_slice_memo[t] = is_compound
        if is_compound and t not in compound_seen:
            compound_seen.add(t)
            compounds.append((t, scalar_fields, owned_fields, has_owner_id))
        return is_compound

    record_slice('u32')
    for root in ROOT_TYPES:
        analyze(root, 'squid_reuse_dependency_payload')

    nested_slices = [t for t in slice_elems if has_slice_memo.get(t, False)]

    imports = {'support.error', 'support.native', 'support.option'}
    for ty in [t for _, t in HEADER_RUNS] + slice_elems + [t for t, _, _, _ in compounds]:
        for ns in re.findall(r'\b(squid_\w+)::', ty):
            if ns in paths:
                imports.add(paths[ns])

    all_runs = list(HEADER_RUNS) + [(ident(t), t) for t in slice_elems]

    lines = [
        '// Generated by tools/write_dependency_payload.py.',
        '// Exact typed ownership for unpublished dependency/Core/principal payloads.',
        '// All immutable views name registered runs; no const cast or host pointer image.',
        'namespace squid_reuse_dependency_payload;',
    ]
    lines += [f'import {m};' for m in sorted(imports)]
    lines += [
        '',
        'type Error=squid_error::Error;',
        'struct Owner {lease:u32=0,generation:u64=0}',
        'struct Owned<T> {value:T,owner:Owner=Owner{..}}',
        'type HeaderPath=const u8[:];',
        'type HeaderDigest=u8[32];',
        'struct Mark {owner:u32,generation:u64,head:u32}',
        '',
        'enum Run {',
    ]
    for tag, ty in all_runs:
        lines.append(f' run_{tag} {{values:{ty}[:]}},')
    lines[-1] = lines[-1].rstrip(',')
    lines += [
        '}',
        'struct Link {value:Run,next:u32=0}',
        'struct Lease {head:u32=0,generation:u64=0,live:bool=false,references:u64=1}',
        'reusable var links:Link[>..]=[];',
        'reusable var leases:Lease[>..]=[];',
    ]
    for tag, ty in all_runs:
        lines.append(f'reusable[] var pool_{tag}:{ty}[>..]=[];')

    lines += [
        '',
        'fn valid(self_:const Owner&)->bool {return self_.lease!=0&&self_.lease-1<leases.len&&leases[self_.lease-1].live&&leases[self_.lease-1].generation==self_.generation;}',
        'fn unique(self_:const Owner&)->bool {return valid(self_)&&leases[self_.lease-1].references==1;}',
        'fn init()->Owner,Error {if leases.len>=0xffffffff {return Owner{..},squid_error::Error.out_of_memory;}let generation=squid_native::fresh_owner_id();let at=leases.alloc_index(Lease{generation:generation,live:true,..});return Owner{(at+1) as u32,generation,..},squid_error::Error.none;}',
        'fn retain(self_:Owner)->Owner,Error {if !valid(self_) {return Owner{..},squid_error::Error.invalid_artifact;}let at=self_.lease-1;if leases[at].references==0xffffffffffffffff {return Owner{..},squid_error::Error.dependency_limit;}leases[at].references+=1;return self_,squid_error::Error.none;}',
        'fn release(self_:Owner&) {self_.deinit();}',
        'fn remember(self_:Owner&,value:Run)->Error {assert(unique(self_));if links.len>=0xffffffff {return squid_error::Error.out_of_memory;}let head=leases[self_.lease-1].head;let at=links.alloc_index(Link{value,head,..});leases[self_.lease-1].head=(at+1) as u32;return squid_error::Error.none;}',
        'fn freeRun(value:Run) {',
        ' match value {',
    ]
    for tag, _ in all_runs:
        lines.append(f'  run_{tag} run=>{{pool_{tag}.free_slice(run.values);}},')
    lines += [
        ' }',
        '}',
        'fn deinit(self_:Owner&) {',
        ' if self_.lease==0 {return;}assert(valid(self_));let owner=self_.lease-1;assert(leases[owner].references!=0);leases[owner].references-=1;',
        ' if leases[owner].references!=0 {self_=Owner{..};return;}',
        ' var next=leases[owner].head;while next!=0 {let at=next-1;let link=links[at];next=link.next;freeRun(link.value);links.free(at);}',
        ' leases[owner].live=false;self_=Owner{..};leases.free(owner);',
        '}',
        'fn deinit<T>(self_:Owned<T>&) {self_.owner.deinit();self_.value=default<T>();}',
        'fn adopt(self_:Owner&,source:Owner&)->Error {',
        ' assert(valid(self_)&&valid(source));if !unique(self_)||!unique(source)||self_.lease==source.lease {return squid_error::Error.invalid_artifact;}',
        ' let at=source.lease-1;let head=leases[at].head;if head!=0 {var tail=head;while links[tail-1].next!=0 {tail=links[tail-1].next;}links[tail-1].next=leases[self_.lease-1].head;leases[self_.lease-1].head=head;}',
        ' leases[at].live=false;source=Owner{..};leases.free(at);return squid_error::Error.none;',
        '}',
        'fn mark(self_:const Owner&)->Mark {assert(unique(self_));return Mark{self_.lease,self_.generation,leases[self_.lease-1].head,..};}',
        'fn rollback(self_:Owner&,mark:Mark) {',
        ' assert(unique(self_)&&self_.lease==mark.owner&&self_.generation==mark.generation);',
        ' var check=leases[self_.lease-1].head;while check!=mark.head {assert(check!=0);check=links[check-1].next;}',
        ' while leases[self_.lease-1].head!=mark.head {let head=leases[self_.lease-1].head;let link=links[head-1];leases[self_.lease-1].head=link.next;freeRun(link.value);links.free(head-1);}',
        '}',
        'fn transferLink(self_:Owner&,destination:Owner&,previous:u32,current:u32,next:u32) {',
        ' if previous==0 {leases[self_.lease-1].head=next;}else {links[previous-1].next=next;}',
        ' links[current-1].next=leases[destination.lease-1].head;leases[destination.lease-1].head=current;',
        '}',
        'fn alloc<T>(self_:Owner&,length:i64)->T[:],Error {return allocate(self_,default<T>(),length);}',
        'fn copy<T>(self_:Owner&,values:const T[:])->T[:],Error {let result,error=squid_reuse_dependency_payload::alloc<T>(self_,values.len);if error!=squid_error::Error.none {return default<T[:]>(),error;}if values.len!=0 {result.move_from(values);}return result,squid_error::Error.none;}',
        '',
    ]

    slice_set = set(slice_elems)
    header_tags = {tag for tag, _ in HEADER_RUNS}
    for tag, ty in all_runs:
        abort_msg = (
            'private header view must name this unique journal'
            if tag in header_tags
            else "mutable payload view must name this private owner's exact live run"
        )
        lines.append(
            f'fn allocate(self_:Owner&,sample:{ty},length:i64)->{ty}[:],Error {{'
            f'assert(unique(self_));if length<0 {{return default<{ty}[:]>(),squid_error::Error.invalid_artifact;}}'
            f'if length==0 {{return default<{ty}[:]>(),squid_error::Error.none;}}'
            f'let run=pool_{tag}.alloc_slice(length);let error=remember(self_,Run.run_{tag}{{run,..}});'
            f'if error!=squid_error::Error.none {{pool_{tag}.free_slice(run);return default<{ty}[:]>(),error;}}'
            f'return run,squid_error::Error.none;}}'
        )
        lines.append(
            f'fn mutable(self_:const Owner&,values:const {ty}[:])->{ty}[:] {{'
            f'assert(unique(self_));if values.len==0 {{return default<{ty}[:]>();}}'
            f'var next=leases[self_.lease-1].head;while next!=0 {{let link=links[next-1];next=link.next;'
            f'match link.value {{run_{tag} run=>{{if squid_support::same_slice_identity(run.values,values) {{return pool_{tag}.realloc_slice(run.values,run.values.len);}}}},_=>{{}}}}}}'
            f'abort("{abort_msg}");}}'
        )
        if tag not in header_tags and ty in slice_set:
            lines.append(
                f'fn detach(self_:Owner&,destination:Owner&,values:const {ty}[:]) {{'
                f'assert(unique(self_)&&unique(destination)&&self_.lease!=destination.lease);if values.len==0 {{return;}}'
                f'var next=leases[destination.lease-1].head;while next!=0 {{let link=links[next-1];next=link.next;'
                f'match link.value {{run_{tag} run=>{{if squid_support::same_slice_identity(run.values,values) {{return;}}}},_=>{{}}}}}}'
                f'var previous:u32=0;next=leases[self_.lease-1].head;while next!=0 {{let current=next;let link=links[current-1];next=link.next;'
                f'match link.value {{run_{tag} run=>{{if squid_support::same_slice_identity(run.values,values) {{transferLink(self_,destination,previous,current,next);return;}}}},_=>{{}}}}previous=current;}}'
                f'abort("partitioned payload view must name this private owner\'s exact live run");}}'
            )

    lines.append('')
    for ty in nested_slices:
        lines.append(
            f'fn cloneNested(self_:Owner&,values:const {ty}[:])->{ty}[:],Error {{'
            f'let result,error=alloc<{ty}>(self_,values.len);if error!=squid_error::Error.none {{return default<{ty}[:]>(),error;}}'
            f'for value,index in values {{let copied,error=cloneValue(self_,value);if error!=squid_error::Error.none {{return default<{ty}[:]>(),error;}}result[index]=copied;}}'
            f'return result,squid_error::Error.none;}}'
        )

    lines.append('')
    for ty, scalar_fields, owned_fields, has_owner_id in compounds:
        lines.append(f'fn cloneValue(self_:Owner&,value:{ty})->{ty},Error {{')
        lines.append(f' var result=default<{ty}>();')
        for fname in scalar_fields:
            lines.append(f' result.{fname}=value.{fname};')
        for fname, ft in owned_fields:
            if ft.endswith('[:]'):
                elem = ft[:-3]
                if elem in nested_slices:
                    lines.append(f' {{let copied,error=cloneNested(self_,value.{fname});if error!=squid_error::Error.none {{return result,error;}}result.{fname}=copied;}}')
                else:
                    lines.append(f' {{let copied,error=copy<{elem}>(self_,value.{fname});if error!=squid_error::Error.none {{return result,error;}}result.{fname}=copied;}}')
            else:
                lines.append(f' {{let copied,error=cloneValue(self_,value.{fname});if error!=squid_error::Error.none {{return result,error;}}result.{fname}=copied;}}')
        if has_owner_id:
            lines.append(' result.owner_id=squid_native::fresh_owner_id();')
        lines.append(' return result,squid_error::Error.none;')
        lines.append('}')

    lines.append('')
    for root in ROOT_TYPES:
        lines.append(
            f'fn clone(value:const {root}&)->Owned<{root}>,Error {{'
            f'var owner,error=init();if error!=squid_error::Error.none {{return default<Owned<{root}>>(),error;}}'
            f'let result,error=cloneValue(owner,value);if error!=squid_error::Error.none {{owner.deinit();return default<Owned<{root}>>(),error;}}'
            f'return Owned<{root}>{{result,owner,..}},squid_error::Error.none;}}'
        )

    lines.append('')
    for ty, _, owned_fields, _ in compounds:
        lines.append(f'fn partitionInto(self_:Owner&,destination:Owner&,value:{ty}) {{')
        for fname, ft in owned_fields:
            if ft.endswith('[:]'):
                elem = ft[:-3]
                lines.append(f' self_.detach(destination,value.{fname});')
                if elem in nested_slices:
                    lines.append(f' for item in value.{fname} {{partitionInto(self_,destination,item);}}')
            else:
                lines.append(f' partitionInto(self_,destination,value.{fname});')
        lines.append('}')

    (ROOT / 'reuse/dependency_payload.goose').write_text('\n'.join(lines) + '\n')

    # Generate O(1) payload_bytes.goose for Core Module and Principal Interface.
    bytes_targets = []
    bytes_seen = set()

    def collect_bytes_compounds(ty):
        if ty in bytes_seen:
            return
        bytes_seen.add(ty)
        for cty, _, owned_fields, _ in compounds:
            if cty == ty:
                for fname, ft in owned_fields:
                    if (ty, fname) in PAYLOAD_BYTES_SKIP:
                        continue
                    if not ft.endswith('[:]'):
                        collect_bytes_compounds(ft)
                bytes_targets.append((cty, owned_fields))
                return
        raise AssertionError(f'Missing compound for payload_bytes: {ty}')

    collect_bytes_compounds('squid_check_core::Module')
    collect_bytes_compounds('squid_reuse_principal_interface::Interface')

    bytes_imports = set()
    for ty, _ in bytes_targets:
        for ns in re.findall(r'\b(squid_\w+)::', ty):
            if ns in paths:
                bytes_imports.add(paths[ns])

    blines = [
        '// Generated by tools/write_dependency_payload.py.',
        '// O(1) storage accounting of a frozen payload matching Zig @sizeOf per slice.',
        'namespace squid_reuse_payload_bytes;',
    ]
    blines += [f'import {m};' for m in sorted(bytes_imports)]
    for ty, owned_fields in bytes_targets:
        terms = []
        for fname, ft in owned_fields:
            if (ty, fname) in PAYLOAD_BYTES_SKIP:
                continue
            if ft.endswith('[:]'):
                elem = ft[:-3]
                assert elem not in nested_slices, f'Nested slice in payload_bytes unsupported: {ty}.{fname}'
                assert elem in ELEMENT_BYTES, f'Missing ELEMENT_BYTES entry for {elem}'
                size = ELEMENT_BYTES[elem]
                terms.append(f'value.{fname}.len' if size == 1 else f'value.{fname}.len*{size}')
            else:
                terms.append(f'bytes(value.{fname})')
        expr = '+'.join(terms) if terms else '0'
        blines.append(f'fn bytes(value:const {ty}&)->i64 {{return {expr};}}')

    (ROOT / 'reuse/payload_bytes.goose').write_text('\n'.join(blines) + '\n')
    print(f'Wrote dependency_payload.goose ({len(lines)} lines, {len(all_runs)} runs, {len(compounds)} compounds) and payload_bytes.goose ({len(blines)} lines)')


if __name__ == '__main__':
    main()
