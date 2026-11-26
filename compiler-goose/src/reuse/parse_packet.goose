// A fork parses against the prelude's symbol prefix. Replay its new spellings
// in parser order, then relocate only symbol fields in the packed syntax.
namespace blot_reuse_parse_packet;
import std;
import binary;
import parse.ast;
import parse.lexer;
import parse.parser;
import parse.symbols;
import parse.token;
import support.bytes;
import support.error;
import support.native;

type Tree = blot_parse_ast::Tree;
type Pool = blot_parse_symbols::Pool;
type Writer = blot_bytes::Writer;
let ok = blot_error::Error.none;

// Compact fixed header: prefix (4) + count (4) + flags (1) + 11 table byte lengths (44) = 53 bytes.
let header_bytes: i64 = 53;

// Per-AST-tag relocation kind for tags 0..=102 (tag_entry_process_decl):
// 0 = none, 1 = node.a, 2 = node.b, 3 = node.c, 4 = node.a + node.b, 5 = node.a + extra[node.c + 1].
let reloc_kind: u8[103] = [
    0, 5, 5, 5, 4, 1, 1, 1, 1, 1,
    1, 1, 1, 0, 0, 4, 0, 0, 0, 1,
    1, 1, 0, 0, 1, 0, 0, 0, 1, 0,
    0, 1, 1, 0, 1, 0, 0, 0, 1, 1,
    1, 1, 0, 2, 0, 0, 0, 0, 1, 1,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 1, 0, 0, 0,
    1, 0, 1, 1, 1, 0, 0, 0, 0, 0,
    0, 1, 0, 0, 1, 3, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 1, 0, 2,
    0, 1, 1,
];

fn append_raw<T>(items: const T[:], packet: u8[>..<]&) {
    if items.len == 0 { return; }
    packet.append(bytes_of(items));
}

fn write_tree(tree: const Tree&, writer: Writer, packet: u8[>..<]&) -> bool {
    let b0 = bytes_of(tree.nodes.items).len;
    let b1 = bytes_of(tree.spans.items).len;
    let b2 = bytes_of(tree.extra.items).len;
    let b3 = bytes_of(tree.roots.items).len;
    let b4 = bytes_of(tree.runtime_names.items).len;
    let b5 = bytes_of(tree.constant_names.items).len;
    let b6 = bytes_of(tree.test_meta.items).len;
    let b7 = bytes_of(tree.declaration_traits.items).len;
    let b8 = bytes_of(tree.declaration_nodes.items).len;
    let b9 = bytes_of(tree.operator_origins.items).len;
    let b10 = bytes_of(tree.type_conversion_origins.items).len;
    if b0 > 0xffffffff || b1 > 0xffffffff || b2 > 0xffffffff || b3 > 0xffffffff ||
       b4 > 0xffffffff || b5 > 0xffffffff || b6 > 0xffffffff || b7 > 0xffffffff ||
       b8 > 0xffffffff || b9 > 0xffffffff || b10 > 0xffffffff { return false; }
    writer.write_u32(b0 as u32);
    writer.write_u32(b1 as u32);
    writer.write_u32(b2 as u32);
    writer.write_u32(b3 as u32);
    writer.write_u32(b4 as u32);
    writer.write_u32(b5 as u32);
    writer.write_u32(b6 as u32);
    writer.write_u32(b7 as u32);
    writer.write_u32(b8 as u32);
    writer.write_u32(b9 as u32);
    writer.write_u32(b10 as u32);
    append_raw(tree.nodes.items, packet);
    append_raw(tree.spans.items, packet);
    append_raw(tree.extra.items, packet);
    append_raw(tree.roots.items, packet);
    append_raw(tree.runtime_names.items, packet);
    append_raw(tree.constant_names.items, packet);
    append_raw(tree.test_meta.items, packet);
    append_raw(tree.declaration_traits.items, packet);
    append_raw(tree.declaration_nodes.items, packet);
    append_raw(tree.operator_origins.items, packet);
    append_raw(tree.type_conversion_origins.items, packet);
    return true;
}

fn encodeWithScratch(source: const u8[:], seed: const Pool&, tokens: blot_parse_token::Token[>..<]&, comments: blot_parse_token::Token[>..<]&, diagnostics: blot_parse_lexer::Diagnostic[>..<]&, local: Pool&, tree: Tree&, packet: u8[>..<]&) -> bool {
    packet.clear();
    tokens.clear();
    comments.clear();
    diagnostics.clear();
    var lexed=blot_parse_lexer::init(tokens,comments,diagnostics);
    if blot_parse_lexer::lex(source,lexed)!=ok || diagnostics.len!=0 {return false;}

    // Reset worker symbol pool to exactly the seed prefix without re-allocating.
    local.bytes.resize(0);
    local.entries.resize(0);
    if seed.entries.len != 0 {
        local.bytes.append(seed.bytes.items);
        local.entries.append(seed.entries.items);
    }
    if seed.buckets.len == 0 {
        if local.buckets.len != 0 { blot_parse_symbols::zeroBuckets(local.buckets.items); }
    } else if local.buckets.len == seed.buckets.len {
        local.buckets.items.move_from(seed.buckets.items);
    } else {
        local.buckets.resize(0);
        local.buckets.append(seed.buckets.items);
    }
    if local.bytes.failure!=ok || local.entries.failure!=ok || local.buckets.failure!=ok {return false;}
    if blot_parse_ast::resetPooled(tree)!=ok {return false;}
    let parsed=blot_parse_parser::parse(source,tokens,local,tree);
    if parsed!=ok || tree.diagnostics.len!=0 {return false;}

    let writer=Writer{packet};
    writer.write_u32(seed.entries.len as u32);
    writer.write_u32((local.entries.len-seed.entries.len) as u32);
    var flags:u8=0;
    if tree.has_typed_staging {flags|=1;}
    writer.write_u8(flags);
    if !write_tree(tree,writer,packet) {return false;}
    for entry in local.entries.items[seed.entries.len..] {
        writer.write_u32(entry.len);
        writer.write_u64(entry.hash);
        writer.write(local.bytes.items[entry.offset..entry.offset+entry.len]);
    }
    return true;
}

fn encode(source: const u8[:], seed: const Pool&, packet: u8[>..<]&) -> bool {
    var tokens: blot_parse_token::Token[>..<]=[];
    var comments: blot_parse_token::Token[>..<]=[];
    var diagnostics: blot_parse_lexer::Diagnostic[>..<]=[];
    var local,error=blot_parse_symbols::initPooled();
    if error!=ok {return false;}
    var tree,tree_error=blot_parse_ast::initPooled();
    if tree_error!=ok {local.deinit();return false;}
    let result=encodeWithScratch(source,seed,tokens,comments,diagnostics,local,tree,packet);
    tree.deinit();
    local.deinit();
    return result;
}

fn read_table_mem<T,B>(packet: const u8[:], at:i64&, length:i64, table: B&, witness: T) -> bool {
    if length < 0 || length > packet.len - at { return false; }
    if length == 0 { table.items = default<T[:]>(); table.len = 0; return true; }
    var sample: T[1] = [witness];
    let elem_size = bytes_of(sample[..]).len;
    if elem_size <= 0 || length % elem_size != 0 { return false; }
    let count = length / elem_size;
    if table.ensureExact(count) != ok { return false; }
    let target = table.storage[..count];
    let dst = bytes_of(target);
    assert(dst.len == length);
    blot_native::copy_flat(dst[0], packet[at], length as u64);
    at += length;
    table.items = target;
    table.len = count;
    return true;
}

fn read_table_persist<T,B>(shared: u64, id: u32, kind: u32, at: i64&, total: i64, length: i64, table: B&, witness: T) -> bool {
    if length < 0 || length > total - at { return false; }
    if length == 0 { table.items = default<T[:]>(); table.len = 0; return true; }
    var sample: T[1] = [witness];
    let elem_size = bytes_of(sample[..]).len;
    if elem_size <= 0 || length % elem_size != 0 { return false; }
    let count = length / elem_size;
    if table.ensureExact(count) != ok { return false; }
    let target = table.storage[..count];
    let dst = bytes_of(target);
    assert(dst.len == length);
    if !blot_native::persist_read_at(shared, id, kind, at as u64, dst[0], length as u64) { return false; }
    at += length;
    table.items = target;
    table.len = count;
    return true;
}

fn relocate(prefix:u32, names:const u32[:], symbol: u32&) -> bool {
    if symbol<=prefix {return true;}
    let index=symbol-prefix-1;
    if index>=names.len {return false;}
    symbol=names[index];
    return symbol!=0;
}

fn relocate_tree(tree: Tree&, prefix:u32, names:const u32[:]) -> bool {
    let nlen = names.len;
    for &node in tree.nodes.items {
        let tag = node.tag;
        if tag > blot_parse_ast::tag_entry_process_decl { return false; }
        let kind = reloc_kind[tag];
        if kind == 0 { continue; }
        if kind == 1 {
            let sym = node.a;
            if sym > prefix {
                let index = sym - prefix - 1;
                if index >= nlen { return false; }
                let mapped = names[index];
                if mapped == 0 { return false; }
                node.a = mapped;
            }
            continue;
        }
        if kind == 5 {
            let slot = node.c as i64 + 1;
            if slot >= tree.extra.len || !relocate(prefix, names, tree.extra.items[slot]) { return false; }
            if !relocate(prefix, names, node.a) { return false; }
            continue;
        }
        if kind == 4 {
            if !relocate(prefix, names, node.a) || !relocate(prefix, names, node.b) { return false; }
            continue;
        }
        if kind == 2 {
            if !relocate(prefix, names, node.b) { return false; }
            continue;
        }
        if !relocate(prefix, names, node.c) { return false; }
    }
    for &meta in tree.test_meta.items {if !relocate(prefix,names,meta.display_name) {return false;}}
    for &origin in tree.operator_origins.items {if !relocate(prefix,names,origin.member) {return false;}}
    return true;
}

fn read_names_into(tail: const u8[:], count: u32, symbols: Pool&, out: u32[:]) -> bool {
    if (count as i64) * 12 > tail.len { return false; }
    var check: i64 = 0;
    for index in 0..count {
        if tail.len - check < 12 { return false; }
        let length = blot_bytes::get_u32(tail, check) as i64;
        check += 12;
        if length > tail.len - check { return false; }
        check += length;
    }
    if check != tail.len { return false; }
    var pos: i64 = 0;
    for index in 0..count {
        let length = blot_bytes::get_u32(tail, pos) as i64;
        let hash = blot_bytes::get_u64(tail, pos + 4);
        pos += 12;
        let symbol, error = symbols.intern_hashed(tail[pos..pos + length], hash);
        if error != ok { return false; }
        out[index] = symbol;
        pos += length;
    }
    return true;
}

fn decode(packet: const u8[:], symbols: Pool&, tree: Tree&, recorded: blot_parse_parser::ScratchIdBuffer?=null) -> bool {
    if packet.len < header_bytes { return false; }
    let prefix = blot_bytes::get_u32(packet, 0);
    let count = blot_bytes::get_u32(packet, 4);
    let flags = packet[8];
    if flags > 3 || prefix > symbols.entries.len { return false; }
    var lens: i64[11] = [0; 11];
    for i in 0..11 { lens[i] = blot_bytes::get_u32(packet, 9 + i * 4) as i64; }
    var parsed, error = blot_parse_ast::initPooledEmpty();
    if error != ok { return false; }
    var at: i64 = header_bytes;
    let tables_ok =
        read_table_mem(packet, at, lens[0], parsed.nodes, default<blot_parse_ast::Node>()) &&
        read_table_mem(packet, at, lens[1], parsed.spans, default<blot_parse_ast::Span>()) &&
        read_table_mem(packet, at, lens[2], parsed.extra, 0 as u32) &&
        read_table_mem(packet, at, lens[3], parsed.roots, 0 as u32) &&
        read_table_mem(packet, at, lens[4], parsed.runtime_names, default<blot_parse_ast::RuntimeName>()) &&
        read_table_mem(packet, at, lens[5], parsed.constant_names, default<blot_parse_ast::RuntimeName>()) &&
        read_table_mem(packet, at, lens[6], parsed.test_meta, default<blot_parse_ast::TestMeta>()) &&
        read_table_mem(packet, at, lens[7], parsed.declaration_traits, default<blot_parse_ast::DeclarationTraits>()) &&
        read_table_mem(packet, at, lens[8], parsed.declaration_nodes, default<blot_parse_ast::DeclarationNodes>()) &&
        read_table_mem(packet, at, lens[9], parsed.operator_origins, default<blot_parse_ast::OperatorOrigin>()) &&
        read_table_mem(packet, at, lens[10], parsed.type_conversion_origins, default<blot_parse_ast::TypeConversionOrigin>()) &&
        parsed.nodes.len != 0 && parsed.nodes.len == parsed.spans.len;
    if !tables_ok { parsed.deinit(); return false; }
    let tail = packet[at..];
    var small_names: u32[256] = [0; 256];
    var heap_names: u32[>..<] = [];
    var names_ok = false;
    var reloc_ok = false;
    if count <= 256 {
        let slice = small_names[..count];
        names_ok = read_names_into(tail, count, symbols, slice);
        if names_ok {
            reloc_ok = relocate_tree(parsed, prefix, slice);
            if reloc_ok && recorded { recorded.append(slice); }
        }
    } else {
        heap_names.resize(count as i64, 0);
        names_ok = read_names_into(tail, count, symbols, heap_names[..]);
        if names_ok {
            reloc_ok = relocate_tree(parsed, prefix, heap_names[..]);
            if reloc_ok && recorded { recorded.append(heap_names[..]); }
        }
    }
    if !names_ok || !reloc_ok { parsed.deinit(); return false; }
    parsed.has_typed_staging = (flags & 1) != 0;
    tree.deinit();
    tree = blot_parse_ast::canonical(parsed);
    return true;
}

// Decode directly from the shared persist_queue arena into the tree's pooled
// tables, copying only the 53-byte header and small symbol tail through scratch.
fn decodeFromPersist(shared: u64, id: u32, kind: u32, total_size: i64, symbols: Pool&, tree: Tree&, tail_scratch: u8[>..<]&, recorded: blot_parse_parser::ScratchIdBuffer?=null) -> bool {
    if total_size < header_bytes { return false; }
    var hdr: u8[53] = [0; 53];
    if !blot_native::persist_read_at(shared, id, kind, 0, hdr[0], header_bytes as u64) { return false; }
    let prefix = blot_bytes::get_u32(hdr[..], 0);
    let count = blot_bytes::get_u32(hdr[..], 4);
    let flags = hdr[8];
    if flags > 3 || prefix > symbols.entries.len { return false; }
    var lens: i64[11] = [0; 11];
    var table_total: i64 = 0;
    for i in 0..11 {
        let l = blot_bytes::get_u32(hdr[..], 9 + i * 4) as i64;
        lens[i] = l;
        table_total += l;
    }
    if header_bytes + table_total > total_size { return false; }
    var parsed, error = blot_parse_ast::initPooledEmpty();
    if error != ok { return false; }
    var at: i64 = header_bytes;
    let tables_ok =
        read_table_persist(shared, id, kind, at, total_size, lens[0], parsed.nodes, default<blot_parse_ast::Node>()) &&
        read_table_persist(shared, id, kind, at, total_size, lens[1], parsed.spans, default<blot_parse_ast::Span>()) &&
        read_table_persist(shared, id, kind, at, total_size, lens[2], parsed.extra, 0 as u32) &&
        read_table_persist(shared, id, kind, at, total_size, lens[3], parsed.roots, 0 as u32) &&
        read_table_persist(shared, id, kind, at, total_size, lens[4], parsed.runtime_names, default<blot_parse_ast::RuntimeName>()) &&
        read_table_persist(shared, id, kind, at, total_size, lens[5], parsed.constant_names, default<blot_parse_ast::RuntimeName>()) &&
        read_table_persist(shared, id, kind, at, total_size, lens[6], parsed.test_meta, default<blot_parse_ast::TestMeta>()) &&
        read_table_persist(shared, id, kind, at, total_size, lens[7], parsed.declaration_traits, default<blot_parse_ast::DeclarationTraits>()) &&
        read_table_persist(shared, id, kind, at, total_size, lens[8], parsed.declaration_nodes, default<blot_parse_ast::DeclarationNodes>()) &&
        read_table_persist(shared, id, kind, at, total_size, lens[9], parsed.operator_origins, default<blot_parse_ast::OperatorOrigin>()) &&
        read_table_persist(shared, id, kind, at, total_size, lens[10], parsed.type_conversion_origins, default<blot_parse_ast::TypeConversionOrigin>()) &&
        parsed.nodes.len != 0 && parsed.nodes.len == parsed.spans.len;
    if !tables_ok { parsed.deinit(); return false; }
    let tail_len = total_size - at;
    if count == 0 {
        if tail_len != 0 { parsed.deinit(); return false; }
        parsed.has_typed_staging = (flags & 1) != 0;
        tree.deinit();
        tree = blot_parse_ast::canonical(parsed);
        return true;
    }
    if tail_len > tail_scratch.len { tail_scratch.resize(tail_len, 0); }
    if tail_len != 0 && !blot_native::persist_read_at(shared, id, kind, at as u64, tail_scratch[0], tail_len as u64) {
        parsed.deinit();
        return false;
    }
    let tail = tail_scratch[..tail_len];
    var small_names: u32[256] = [0; 256];
    var heap_names: u32[>..<] = [];
    var names_ok = false;
    var reloc_ok = false;
    if count <= 256 {
        let slice = small_names[..count];
        names_ok = read_names_into(tail, count, symbols, slice);
        if names_ok {
            reloc_ok = relocate_tree(parsed, prefix, slice);
            if reloc_ok && recorded { recorded.append(slice); }
        }
    } else {
        heap_names.resize(count as i64, 0);
        names_ok = read_names_into(tail, count, symbols, heap_names[..]);
        if names_ok {
            reloc_ok = relocate_tree(parsed, prefix, heap_names[..]);
            if reloc_ok && recorded { recorded.append(heap_names[..]); }
        }
    }
    if !names_ok || !reloc_ok { parsed.deinit(); return false; }
    parsed.has_typed_staging = (flags & 1) != 0;
    tree.deinit();
    tree = blot_parse_ast::canonical(parsed);
    return true;
}
