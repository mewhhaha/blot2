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
    return ''.join(lines), count


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
        path.write_text(source)
    print(json.dumps(counts))


if __name__ == '__main__':
    main()
