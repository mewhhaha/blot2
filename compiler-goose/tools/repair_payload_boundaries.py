"""Regenerate narrow payload boundaries without replacing later source repairs.

The original payload authoring scripts were not retained. Enum declarations and
the evolved payload modules are the inputs for these bounded, idempotent passes.
Wire field order, ownership journals and packed-size expressions stay intact.
"""
from pathlib import Path
import json
import re
from source_model import balanced, clean, split

ROOT = Path(__file__).resolve().parents[1] / 'src'


def repair_payload_identity(source):
    return re.subn(r'\brun\.values\s*\.==\s*values\b',
                   'blot_support::same_slice_identity(run.values,values)', source)


# A shallow Named copy may only publish proof-header leaves already registered
# to this exact unique owner. Recover their globally rooted canonical runs;
# copying them again would duplicate the preceding proof-header snapshot.
PROOF_HEADER_RECEIPT = """// Proof headers already copied into this owner retain their exact registered runs.
fn canonicalProofHeader(self_:const Owner&,value:blot_check_numeric_proof_headers::Owned)->blot_check_numeric_proof_headers::Owned {
 return blot_check_numeric_proof_headers::Owned{arity:value.arity,value_slots:self_.mutable(value.value_slots),proof_slots:self_.mutable(value.proof_slots),values:self_.mutable(value.values),operands:self_.mutable(value.operands),requirements:self_.mutable(value.requirements),result:value.result};
}
fn copyElement<T>(self_:Owner&,value:T)->T {return value;}
fn copyElement(self_:Owner&,value:blot_check_numeric_proof_headers::Named)->blot_check_numeric_proof_headers::Named {return blot_check_numeric_proof_headers::Named{value.binding,self_.canonicalProofHeader(value.header)};}

"""

def repair_payload_copy_receipt(source):
    if PROOF_HEADER_RECEIPT in source:
        return source,0
    if 'fn canonicalProofHeader(' in source:
        raise ValueError('proof header receipt diverged; review before regeneration')
    source=source.replace('for value,index in values {result[index]=value;}return result,blot_error::Error.none;', 'for value,index in values {result[index]=copyElement(self_,value);}return result,blot_error::Error.none;',1)
    return source+'\n'+PROOF_HEADER_RECEIPT,1


def enum_shapes():
    shapes = {}
    for path in ROOT.rglob('*.goose'):
        source = clean(path.read_text())
        namespace = re.search(r'\bnamespace\s+(\w+)\s*;', source)
        if namespace is None:
            continue
        for match in re.finditer(r'\benum\s+(\w+)\s*\{', source):
            opening = match.end() - 1
            variants = {}
            for field in split(source[opening + 1:balanced(source, opening)]):
                field = field.strip()
                name = re.match(r'(\w+)', field)
                if name:
                    variants[name[1]] = '{' in field
            shapes[namespace[1] + '::' + match[1]] = variants
    return shapes


def repair_payload_bytes(source):
    shapes = enum_shapes()
    count = 0
    result = []
    for line in source.splitlines(keepends=True):
        match = re.match(r'fn bytes\(value:([^&]+)\)->i64 \{match value \{', line)
        if match and match[1] in shapes:
            variants = shapes[match[1]]
            def arm(found):
                nonlocal count
                if variants.get(found[1], True):
                    return found[0]
                count += 1
                return found[1] + '=>'
            line = re.sub(r'\b(\w+) payload=>', arm, line)
        result.append(line)
    return ''.join(result), count


def repair_codec_const_options(source):
    # Procedure names retain the native ?[]const wire domain. Only its Goose
    # Option argument is invariant; decoding still allocates a mutable run.
    count = 0
    lines = []
    for line in source.splitlines(keepends=True):
        if re.match(r'fn (?:describe|write|read|release)____const_', line):
            match = re.search(r'blot_support::Option<(?!const )([^<>]+\[:\])>', line)
            if match:
                child = match[1]
                line = line.replace('blot_support::Option<' + child + '>',
                                    'blot_support::Option<const ' + child + '>')
                line = line.replace('blot_support::none<' + child + '>',
                                    'blot_support::none<const ' + child + '>')
                line = line.replace('blot_support::some(value)',
                                    'blot_support::some<const ' + child + '>(value)')
                count += 1
        lines.append(line)
    source=''.join(lines)
    # Schema samples use the callee's invariant Option type too. Existing
    # evolved bodies stay intact; only the now-readonly sample headers change.
    samples=dict(re.findall(r'fn (describe_\w+)\(hasher:[^,]+,value:([^\n]+?)\) \{',source))
    def sample(match):
        nonlocal count
        wanted=samples.get(match[1])
        old=match[2]
        if wanted and wanted.startswith('blot_support::Option<const ') and old==wanted.replace('<const ','<',1):
            count+=1
            return match[1]+'(hasher,default<'+wanted+'>())'
        return match[0]
    source=re.sub(r'\b(describe_\w+)\(hasher,default<([^;{}]+)>\(\)\)',sample,source)
    # Keep the decoded value's owned field roots across an invariant Option.
    # The wire flag, native child schema and rollback order are unchanged.
    typed = []
    for line in source.splitlines(keepends=True):
        result = re.match(r'fn read_\w+<O>\(reader:Decoder<O>&,level:i64\)->(blot_support::Option<.+>),Error \{', line)
        if result:
            line, changed = re.subn(r'return blot_support::some(?:<[^;\n]+>)?\(value\),blot_error::Error.none;',
                                   lambda match: 'return ' + result[1] + '{true,value},blot_error::Error.none;', line)
            count += changed
        typed.append(line)
    return ''.join(typed),count


def main():
    counts = {}
    for name, repair in [
        ('dependency_payload', repair_payload_identity),
        ('dependency_format_owners', repair_payload_identity),
        ('payload_bytes', repair_payload_bytes),
        ('dependency_format_codecs', repair_codec_const_options),
    ]:
        path = ROOT / 'reuse' / (name + '.goose')
        source, counts[name] = repair(path.read_text())
        if name == 'dependency_payload':
            source,extra = repair_payload_copy_receipt(source)
            counts[name] += extra
        path.write_text(source)
    print(json.dumps(counts))


if __name__ == '__main__':
    main()
