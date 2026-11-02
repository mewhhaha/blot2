#!/usr/bin/env python3
"""Static, byte-weighted Wasm census (stdlib only; never executes the guest).

python3 scripts/bench/wasm_size.py main.wasm --output report.json
Counts include each instruction's complete encoding and every body byte. Unknown
scalar/prefix encodings fail closed. Supports scalar, bulk-memory and SIMD emitted
by Blot; this is a size decoder, not a Wasm validator or execution cost model.
"""

import argparse
from collections import Counter, defaultdict
import hashlib
import json
from pathlib import Path
import time


class Reader:
    def __init__(self, data, start=0, end=None):
        self.data = data
        self.pos = start
        self.end = end
        if end is None:
            self.end = len(data)

    def byte(self):
        if self.pos >= self.end:
            raise ValueError(f"unexpected EOF at {self.pos:#x}")
        value = self.data[self.pos]
        self.pos += 1
        return value

    def skip(self, count):
        if count < 0 or self.pos + count > self.end:
            raise ValueError(f"truncated encoding at {self.pos:#x}")
        self.pos += count

    def leb(self, signed=False):
        value = shift = 0
        for _ in range(10):
            byte = self.byte()
            value |= (byte & 127) << shift
            shift += 7
            if byte < 128:
                if signed and byte & 64:
                    value -= 1 << shift
                return value
        raise ValueError(f"oversized LEB at {self.pos:#x}")

    def string(self):
        size = self.leb()
        start = self.pos
        self.skip(size)
        return self.data[start:self.pos].decode("utf-8", errors="replace")

    def value_type(self):
        value = self.byte()
        if value in (0x63, 0x64):
            self.leb(True)
        return f"0x{value:02x}"


BASE = {
    0x00: "unreachable", 0x01: "nop", 0x02: "block", 0x03: "loop",
    0x04: "if", 0x05: "else", 0x0b: "end", 0x0c: "br", 0x0d: "br_if",
    0x0e: "br_table", 0x0f: "return", 0x10: "call", 0x11: "call_indirect",
    0x12: "return_call", 0x13: "return_call_indirect", 0x14: "call_ref",
    0x15: "return_call_ref", 0x1a: "drop", 0x1b: "select", 0x1c: "select_t",
    0x20: "local.get", 0x21: "local.set", 0x22: "local.tee",
    0x23: "global.get", 0x24: "global.set", 0x25: "table.get", 0x26: "table.set",
    0x3f: "memory.size", 0x40: "memory.grow", 0x41: "i32.const",
    0x42: "i64.const", 0x43: "f32.const", 0x44: "f64.const",
    0xd0: "ref.null", 0xd1: "ref.is_null", 0xd2: "ref.func",
    0xd3: "ref.eq", 0xd4: "ref.as_non_null", 0xd5: "br_on_null", 0xd6: "br_on_non_null",
}
for code, name in enumerate("i32.load i64.load f32.load f64.load i32.load8_s i32.load8_u i32.load16_s i32.load16_u i64.load8_s i64.load8_u i64.load16_s i64.load16_u i64.load32_s i64.load32_u i32.store i64.store f32.store f64.store i32.store8 i32.store16 i64.store8 i64.store16 i64.store32".split(), 0x28):
    BASE[code] = name
NUMERIC = """i32.eqz i32.eq i32.ne i32.lt_s i32.lt_u i32.gt_s i32.gt_u i32.le_s i32.le_u i32.ge_s i32.ge_u
i64.eqz i64.eq i64.ne i64.lt_s i64.lt_u i64.gt_s i64.gt_u i64.le_s i64.le_u i64.ge_s i64.ge_u
f32.eq f32.ne f32.lt f32.gt f32.le f32.ge f64.eq f64.ne f64.lt f64.gt f64.le f64.ge
i32.clz i32.ctz i32.popcnt i32.add i32.sub i32.mul i32.div_s i32.div_u i32.rem_s i32.rem_u i32.and i32.or i32.xor i32.shl i32.shr_s i32.shr_u i32.rotl i32.rotr
i64.clz i64.ctz i64.popcnt i64.add i64.sub i64.mul i64.div_s i64.div_u i64.rem_s i64.rem_u i64.and i64.or i64.xor i64.shl i64.shr_s i64.shr_u i64.rotl i64.rotr
f32.abs f32.neg f32.ceil f32.floor f32.trunc f32.nearest f32.sqrt f32.add f32.sub f32.mul f32.div f32.min f32.max f32.copysign
f64.abs f64.neg f64.ceil f64.floor f64.trunc f64.nearest f64.sqrt f64.add f64.sub f64.mul f64.div f64.min f64.max f64.copysign
i32.wrap_i64 i32.trunc_f32_s i32.trunc_f32_u i32.trunc_f64_s i32.trunc_f64_u i64.extend_i32_s i64.extend_i32_u i64.trunc_f32_s i64.trunc_f32_u i64.trunc_f64_s i64.trunc_f64_u
f32.convert_i32_s f32.convert_i32_u f32.convert_i64_s f32.convert_i64_u f32.demote_f64 f64.convert_i32_s f64.convert_i32_u f64.convert_i64_s f64.convert_i64_u f64.promote_f32
i32.reinterpret_f32 i64.reinterpret_f64 f32.reinterpret_i32 f64.reinterpret_i64 i32.extend8_s i32.extend16_s i64.extend8_s i64.extend16_s i64.extend32_s"""
BASE.update(enumerate(NUMERIC.split(), 0x45))
BULK = dict(enumerate("i32.trunc_sat_f32_s i32.trunc_sat_f32_u i32.trunc_sat_f64_s i32.trunc_sat_f64_u i64.trunc_sat_f32_s i64.trunc_sat_f32_u i64.trunc_sat_f64_s i64.trunc_sat_f64_u memory.init data.drop memory.copy memory.fill table.init elem.drop table.copy table.grow table.size table.fill".split()))
SIMD = {
    0x00: "v128.load", 0x0b: "v128.store", 0x0c: "v128.const", 0x0d: "i8x16.shuffle",
    0x11: "i32x4.splat", 0x13: "f32x4.splat", 0x1b: "i32x4.extract_lane", 0x1c: "i32x4.replace_lane",
    0x1f: "f32x4.extract_lane", 0x20: "f32x4.replace_lane", 0x37: "i32x4.eq", 0x38: "i32x4.ne",
    0x3a: "i32x4.lt_u", 0x3c: "i32x4.gt_u", 0x3e: "i32x4.le_u", 0x40: "i32x4.ge_u",
    0x41: "f32x4.eq", 0x42: "f32x4.ne", 0x43: "f32x4.lt", 0x44: "f32x4.gt", 0x45: "f32x4.le", 0x46: "f32x4.ge",
    0x4d: "v128.not", 0x4e: "v128.and", 0x4f: "v128.andnot", 0x50: "v128.or", 0x51: "v128.xor", 0x52: "v128.bitselect", 0x53: "v128.any_true",
    0x67: "f32x4.ceil", 0x68: "f32x4.floor", 0x69: "f32x4.trunc", 0xa3: "i32x4.all_true",
    0xab: "i32x4.shl", 0xac: "i32x4.shr_s", 0xad: "i32x4.shr_u", 0xae: "i32x4.add", 0xb1: "i32x4.sub", 0xb5: "i32x4.mul", 0xb7: "i32x4.min_u", 0xb9: "i32x4.max_u",
    0xe0: "f32x4.abs", 0xe1: "f32x4.neg", 0xe3: "f32x4.sqrt", 0xe4: "f32x4.add", 0xe5: "f32x4.sub", 0xe6: "f32x4.mul", 0xe7: "f32x4.div", 0xea: "f32x4.pmin", 0xeb: "f32x4.pmax",
    0xf8: "i32x4.trunc_sat_f32x4_s", 0xf9: "i32x4.trunc_sat_f32x4_u", 0xfa: "f32x4.convert_i32x4_s", 0xfb: "f32x4.convert_i32x4_u",
    0x105: "f32x4.relaxed_madd", 0x106: "f32x4.relaxed_nmadd",
}
SIMD.update(enumerate("v128.load8x8_s v128.load8x8_u v128.load16x4_s v128.load16x4_u v128.load32x2_s v128.load32x2_u v128.load8_splat v128.load16_splat v128.load32_splat v128.load64_splat".split(), 1))
SIMD.update(enumerate("v128.load8_lane v128.load16_lane v128.load32_lane v128.load64_lane v128.store8_lane v128.store16_lane v128.store32_lane v128.store64_lane v128.load32_zero v128.load64_zero".split(), 0x54))


def instruction(r):
    start = r.pos
    code = r.byte()
    operand = None
    if code == 0xfc:
        sub = r.leb()
        if sub not in BULK:
            raise ValueError(f"unknown bulk opcode {sub:#x} at {start:#x}")
        name = BULK[sub]
        count = 0
        if sub in (8, 10, 12, 14):
            count = 2
        elif sub >= 9:
            count = 1
        for _ in range(count):
            r.leb()
    elif code == 0xfd:
        sub = r.leb()
        # All non-immediate SIMD operations use prefix + u32 subopcode.
        # Accept the fixed SIMD range, including relaxed SIMD; reserved codes
        # are not validated here (as with type/index validity).
        if sub > 0x113:
            raise ValueError(f"unknown SIMD opcode {sub:#x} at {start:#x}")
        name = SIMD.get(sub, f"simd.0x{sub:x}")
        if sub <= 0x0b or sub in (0x5c, 0x5d):
            r.leb()
            r.leb()
        elif sub in (0x0c, 0x0d):
            r.skip(16)
        elif 0x15 <= sub <= 0x22:
            r.skip(1)
        elif 0x54 <= sub <= 0x5b:
            r.leb()
            r.leb()
            r.skip(1)
    else:
        if code not in BASE:
            raise ValueError(f"unknown opcode {code:#x} at {start:#x}")
        name = BASE[code]
        if code in (2, 3, 4, 0x41, 0x42, 0xd0):
            operand = r.leb(True)
        elif code in (0x11, 0x13):
            operand = r.leb()
            r.leb()
        elif code == 0x0e:
            for _ in range(r.leb() + 1):
                r.leb()
        elif code == 0x1c:
            for _ in range(r.leb()):
                r.value_type()
        elif 0x28 <= code <= 0x3e:
            r.leb()
            operand = r.leb()
        elif code == 0x43:
            r.skip(4)
        elif code == 0x44:
            r.skip(8)
        elif code in (0x0c, 0x0d, 0x10, 0x12, 0x14, 0x15, 0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x3f, 0x40, 0xd2, 0xd5, 0xd6):
            operand = r.leb()
    return name, r.pos - start, operand


def category(name):
    if name.startswith("global."):
        return "globals"
    if name.startswith("local."):
        return "locals"
    if ".load" in name:
        return "loads"
    if ".store" in name:
        return "stores"
    if "call" in name:
        return "calls"
    if name.endswith(".const"):
        return "constants"
    if name in ("block", "loop", "if", "else", "end", "br", "br_if", "br_table", "return", "unreachable", "nop", "drop", "select", "select_t"):
        return "control"
    if name.startswith(("memory.", "table.", "ref.")):
        return "memory_table_reference"
    return "arithmetic_simd"


def ranked(counts, sizes):
    return [dict(name=k, count=counts[k], bytes=v) for k, v in sorted(sizes.items(), key=lambda item: (-item[1], str(item[0])))]


def analyze(path, top):
    started = time.monotonic()
    data = path.read_bytes()
    if data[:8] != b"\0asm\x01\0\0\0":
        raise ValueError("expected Wasm binary version 1")
    r = Reader(data, 8)
    sections = []
    while r.pos < r.end:
        start = r.pos
        ident = r.byte()
        size = r.leb()
        payload = r.pos
        r.skip(size)
        section = dict(id=ident, offset=start, payload_offset=payload, payload_bytes=size, bytes=r.pos-start)
        if ident == 0:
            section["name"] = Reader(data, payload, r.pos).string()
        sections.append(section)
    bodies = []
    counts, sizes, cat_count, cat_size = Counter(), Counter(), Counter(), Counter()
    global_count, global_size, call_count = Counter(), Counter(), Counter()
    pair_count, pair_size = Counter(), Counter()
    index_width_count, index_width_size = Counter(), Counter()
    duplicate = defaultdict(list)
    exports, names = {}, {}
    imports = 0
    global_types = Counter()
    global_initializers = 0
    body_prefix_bytes = 0
    for section in sections:
        s = Reader(data, section["payload_offset"], section["payload_offset"] + section["payload_bytes"])
        if section["id"] == 2:
            for _ in range(s.leb()):
                s.string()
                s.string()
                kind = s.byte()
                if kind == 0:
                    s.leb()
                    imports += 1
                elif kind in (1, 2):
                    if kind == 1:
                        s.value_type()
                    flags = s.leb()
                    s.leb()
                    if flags & 1:
                        s.leb()
                elif kind == 3:
                    s.value_type()
                    s.byte()
                elif kind == 4:
                    s.byte()
                    s.leb()
                else:
                    raise ValueError(f"unknown import kind {kind}")
        elif section["id"] == 6:
            for _ in range(s.leb()):
                value_type = s.value_type()
                mutable = s.byte()
                global_types[f"{value_type}:mutable={mutable}"] += 1
                start = s.pos
                while instruction(s)[0] != "end":
                    pass
                global_initializers += s.pos - start
        elif section["id"] == 7:
            for _ in range(s.leb()):
                name = s.string()
                kind = s.byte()
                index = s.leb()
                if kind == 0:
                    exports[index] = name
        elif section["id"] == 0 and section.get("name") == "name":
            s.string()
            while s.pos < s.end:
                sub = s.byte()
                size = s.leb()
                end = s.pos + size
                if sub == 1:
                    for _ in range(s.leb()):
                        index = s.leb()
                        names[index] = s.string()
                s.pos = end
        elif section["id"] == 10:
            for ordinal in range(s.leb()):
                prefix = s.pos
                size = s.leb()
                start = s.pos
                end = start + size
                if end > s.end:
                    raise ValueError("body exceeds code section")
                body_prefix_bytes += start - prefix
                b = Reader(data, start, end)
                local_types = Counter()
                for _ in range(b.leb()):
                    count = b.leb()
                    local_types[b.value_type()] += count
                local_bytes = b.pos - start
                bc, bs, cc, cs = Counter(), Counter(), Counter(), Counter()
                pc, ps = Counter(), Counter()
                previous = None
                while b.pos < b.end:
                    name, length, operand = instruction(b)
                    cat = category(name)
                    bc[name] += 1
                    bs[name] += length
                    cc[cat] += 1
                    cs[cat] += length
                    if cat in ("globals", "locals"):
                        # These operations have one opcode byte and one index.
                        key = f"{cat}:index_bytes={length-1}"
                        index_width_count[key] += 1
                        index_width_size[key] += length
                    if previous:
                        previous_name, previous_length, previous_operand = previous
                        key = None
                        if previous_name == "i32.const" and previous_operand == 0 and name == "global.set":
                            key = "i32.const 0 -> global.set"
                        elif (previous_name, name) in (("global.get", "global.set"), ("global.get", "local.set"), ("local.get", "local.set"), ("local.get", "global.set")):
                            key = f"{previous_name} -> {name}"
                        if key:
                            pc[key] += 1
                            ps[key] += previous_length + length
                    previous = (name, length, operand)
                    if cat == "globals":
                        global_count[(name, operand)] += 1
                        global_size[(name, operand)] += length
                    if name == "call":
                        call_count[operand] += 1
                if data[end-1] != 0x0b:
                    raise ValueError(f"body {ordinal} lacks final end")
                counts.update(bc)
                sizes.update(bs)
                cat_count.update(cc)
                cat_size.update(cs)
                pair_count.update(pc)
                pair_size.update(ps)
                index = imports + ordinal
                digest = hashlib.sha256(data[start:end]).hexdigest()
                duplicate[digest].append(index)
                bodies.append(dict(index=index, defined_index=ordinal, offset=start, body_bytes=size,
                                   local_declaration_bytes=local_bytes, local_count=sum(local_types.values()),
                                   local_types=dict(local_types), instruction_bytes=sum(bs.values()),
                                   instruction_count=sum(bc.values()), categories=dict(cs),
                                   global_get_count=bc["global.get"], global_set_count=bc["global.set"],
                                   global_get_bytes=bs["global.get"], global_set_bytes=bs["global.set"],
                                   call_count=bc["call"], adjacent_patterns=ranked(pc, ps), sha256=digest))
                s.pos = end
        else:
            continue
        if s.pos != s.end:
            raise ValueError(f"unconsumed section {section['id']}: {s.end-s.pos} bytes")
    for body in bodies:
        body["name"] = names.get(body["index"], exports.get(body["index"]))
    by_index = {b["index"]: b for b in bodies}
    duplicates = []
    for digest, indices in duplicate.items():
        if len(indices) > 1:
            size = by_index[indices[0]]["body_bytes"]
            duplicates.append(dict(sha256=digest, count=len(indices), body_bytes=size,
                                   redundant_body_bytes=size*(len(indices)-1), indices=indices))
    duplicates.sort(key=lambda item: -item["redundant_body_bytes"])
    total_body = sum(b["body_bytes"] for b in bodies)
    total_locals = sum(b["local_declaration_bytes"] for b in bodies)
    code = next(s for s in sections if s["id"] == 10)
    accounted = total_body + body_prefix_bytes
    # Remaining code payload is exactly its function-count prefix.
    assert code["payload_bytes"] - accounted <= 5
    assert total_body == total_locals + sum(sizes.values())
    return dict(format=1, path=str(path), wasm_bytes=len(data), wasm_sha256=hashlib.sha256(data).hexdigest(),
                elapsed_seconds=time.monotonic()-started, sections=sections, imported_functions=imports,
                functions=len(bodies), total_body_bytes=total_body, body_size_prefix_bytes=body_prefix_bytes,
                local_declaration_bytes=total_locals, declared_locals=sum(b["local_count"] for b in bodies),
                instruction_bytes=sum(sizes.values()), instruction_count=sum(counts.values()),
                categories=ranked(cat_count, cat_size), opcodes=ranked(counts, sizes),
                index_widths=ranked(index_width_count, index_width_size),
                adjacent_patterns=ranked(pair_count, pair_size),
                adjacent_pattern_note="Static adjacent encodings; overlapping patterns are possible and do not prove removability.",
                global_types=dict(global_types), global_initializer_bytes=global_initializers,
                unique_globals_accessed=len({index for _, index in global_count}),
                global_access_index_widths={width: sum(count for (name, index), count in global_count.items() if max(1, (index.bit_length()+6)//7) == width) for width in range(1, 6)},
                top_global_accesses=[dict(opcode=name, index=index, count=global_count[(name, index)], bytes=size) for (name, index), size in global_size.most_common(top)],
                top_callees=[dict(index=index, name=names.get(index, exports.get(index)), count=count, body_bytes=by_index.get(index, {}).get("body_bytes")) for index, count in call_count.most_common(top)],
                top_bodies=sorted(bodies, key=lambda body: -body["body_bytes"])[:top],
                top_local_bodies=sorted(bodies, key=lambda body: -body["local_count"])[:top],
                top_global_traffic_bodies=sorted(bodies, key=lambda body: -body["categories"].get("globals", 0))[:top],
                exact_duplicates=dict(groups=len(duplicates), redundant_bodies=sum(g["count"]-1 for g in duplicates),
                                      redundant_body_bytes=sum(g["redundant_body_bytes"] for g in duplicates), top=duplicates[:top]),
                body_size_buckets={str(bound): dict(count=sum(b["body_bytes"] >= bound for b in bodies), bytes=sum(b["body_bytes"] for b in bodies if b["body_bytes"] >= bound)) for bound in (100, 1000, 10000, 100000, 1000000)},
                all_bodies=bodies)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("wasm", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--functions", type=Path, help="optional full function census (summary stays small)")
    parser.add_argument("--top", type=int, default=30)
    args = parser.parse_args()
    result = analyze(args.wasm, args.top)
    bodies = result.pop("all_bodies")
    if args.functions:
        args.functions.parent.mkdir(parents=True, exist_ok=True)
        args.functions.write_text(json.dumps(bodies, separators=(",", ":")) + "\n")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({key: result[key] for key in ("wasm_bytes", "wasm_sha256", "functions", "instruction_bytes", "elapsed_seconds")}))


if __name__ == "__main__":
    main()
