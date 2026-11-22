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

fn write_tree(tree: const Tree&, packet: u8[>..<]&) {
    to_bytes(tree.nodes.items,packet);
    to_bytes(tree.spans.items,packet);
    to_bytes(tree.extra.items,packet);
    to_bytes(tree.roots.items,packet);
    to_bytes(tree.runtime_names.items,packet);
    to_bytes(tree.constant_names.items,packet);
    to_bytes(tree.declaration_traits.items,packet);
    to_bytes(tree.declaration_nodes.items,packet);
    to_bytes(tree.operator_origins.items,packet);
    to_bytes(tree.type_conversion_origins.items,packet);
}

fn encodeWithScratch(source: const u8[:], seed: const Pool&, tokens: blot_parse_token::Token[>..<]&, comments: blot_parse_token::Token[>..<]&, diagnostics: blot_parse_lexer::Diagnostic[>..<]&, local: Pool&, packet: u8[>..<]&) -> bool {
    packet.clear();
    tokens.clear();
    comments.clear();
    diagnostics.clear();
    var lexed=blot_parse_lexer::init(tokens,comments,diagnostics);
    if blot_parse_lexer::lex(source,lexed)!=ok || diagnostics.len!=0 {return false;}

    // Reset worker symbol pool to exactly the seed prefix without re-allocating.
    local.bytes.resize(0);
    local.entries.resize(0);
    local.bytes.append(seed.bytes.items);
    local.entries.append(seed.entries.items);
    if local.buckets.len==seed.buckets.len && seed.buckets.len!=0 {
        local.buckets.items.move_from(seed.buckets.items);
    } else {
        local.buckets.resize(0);
        local.buckets.append(seed.buckets.items);
    }
    if local.bytes.failure!=ok || local.entries.failure!=ok || local.buckets.failure!=ok {return false;}
    var tree,tree_error=blot_parse_ast::initPooled();
    if tree_error!=ok {return false;}
    let parsed=blot_parse_parser::parse(source,tokens,local,tree);
    if parsed!=ok || tree.diagnostics.len!=0 {tree.deinit();return false;}

    let writer=Writer{packet};
    writer.write_u32(seed.entries.len as u32);
    writer.write_u32((local.entries.len-seed.entries.len) as u32);
    var flags:u8=0;
    if tree.has_typed_staging {flags|=1;}
    writer.write_u8(flags);
    write_tree(tree,packet);
    for entry in local.entries.items[seed.entries.len..] {
        writer.write_u32(entry.len);
        writer.write(local.bytes.items[entry.offset..entry.offset+entry.len]);
    }
    tree.deinit();
    return true;
}

fn encode(source: const u8[:], seed: const Pool&, packet: u8[>..<]&) -> bool {
    var tokens: blot_parse_token::Token[>..<]=[];
    var comments: blot_parse_token::Token[>..<]=[];
    var diagnostics: blot_parse_lexer::Diagnostic[>..<]=[];
    var local,error=blot_parse_symbols::initPooled();
    if error!=ok {return false;}
    let result=encodeWithScratch(source,seed,tokens,comments,diagnostics,local,packet);
    local.deinit();
    return result;
}

// Goose's flat image starts with the byte length as ULEB. Verify the image
// and copy it into this tree's own pooled storage before releasing the packet.
fn read_table<T,B>(packet: const u8[:], at:i64&, table: B&, witness: T) -> bool {
    let start=at;
    var length:u64=0;
    var shift:u64=0;
    while true {
        if at>=packet.len || shift>=63 {return false;}
        let byte=packet[at]; at++;
        length|=((byte & 127) as u64)<<shift;
        if byte<128 {break;}
        shift+=7;
    }
    if length>(packet.len-at) as u64 {return false;}
    at+=length as i64;
    let values,valid=from_bytes<T[>..]>(packet[start..at]);
    if !valid || table.ensure(values.len)!=ok {return false;}
    let target=table.storage[..values.len];
    target.move_from(values[..]);
    table.items=target;
    table.len=values.len;
    return true;
}

fn read_table_u32<B>(packet: const u8[:], at:i64&, table: B&) -> bool {
    var length:u64=0;
    var shift:u64=0;
    while true {
        if at>=packet.len || shift>=63 {return false;}
        let byte=packet[at]; at++;
        length|=((byte & 127) as u64)<<shift;
        if byte<128 {break;}
        shift+=7;
    }
    if length>(packet.len-at) as u64 || (length & 3)!=0 {return false;}
    let count=(length>>2) as i64;
    if table.ensure(count)!=ok {return false;}
    let target=table.storage[..count];
    if count!=0 { blot_native::copy_u32(target[0],packet[at],count as u64); at+=length as i64; }
    table.items=target;
    table.len=count;
    return true;
}

fn read_tree(packet: const u8[:], at:i64&, tree: Tree&) -> bool {
    return read_table(packet,at,tree.nodes,default<blot_parse_ast::Node>()) &&
        read_table(packet,at,tree.spans,default<blot_parse_ast::Span>()) &&
        read_table_u32(packet,at,tree.extra) &&
        read_table_u32(packet,at,tree.roots) &&
        read_table(packet,at,tree.runtime_names,default<blot_parse_ast::RuntimeName>()) &&
        read_table(packet,at,tree.constant_names,default<blot_parse_ast::RuntimeName>()) &&
        read_table(packet,at,tree.declaration_traits,default<blot_parse_ast::DeclarationTraits>()) &&
        read_table(packet,at,tree.declaration_nodes,default<blot_parse_ast::DeclarationNodes>()) &&
        read_table(packet,at,tree.operator_origins,default<blot_parse_ast::OperatorOrigin>()) &&
        read_table(packet,at,tree.type_conversion_origins,default<blot_parse_ast::TypeConversionOrigin>()) &&
        tree.nodes.len!=0 && tree.nodes.len==tree.spans.len;
}

fn relocate(prefix:u32, names:const u32[:], symbol: u32&) -> bool {
    if symbol<=prefix {return true;}
    let index=symbol-prefix-1;
    if index>=names.len {return false;}
    symbol=names[index];
    return symbol!=0;
}
fn relocate_tree(tree: Tree&, prefix:u32, names:const u32[:]) -> bool {
    for &node in tree.nodes.items {
        match node.tag {
            // The second metadata word is the modifier, namespace or unpacked name.
            blot_parse_ast::tag_value_decl, blot_parse_ast::tag_import_decl,
            blot_parse_ast::tag_export_decl, blot_parse_ast::tag_package_unpack => {
                let slot=node.c as i64+1;
                if slot>=tree.extra.len || !relocate(prefix,names,tree.extra.items[slot]) {return false;}
                if node.tag!=blot_parse_ast::tag_package_unpack && !relocate(prefix,names,node.a) {return false;}
            },
            blot_parse_ast::tag_import_binding, blot_parse_ast::tag_fixity_decl, blot_parse_ast::tag_constraint => {
                if !relocate(prefix,names,node.a) || !relocate(prefix,names,node.b) {return false;}
            },
            blot_parse_ast::tag_field_access, blot_parse_ast::tag_comptime_project => {if !relocate(prefix,names,node.b) {return false;}},
            blot_parse_ast::tag_type_usage => {if !relocate(prefix,names,node.c) {return false;}},
            blot_parse_ast::tag_data_decl, blot_parse_ast::tag_type_alias_decl, blot_parse_ast::tag_contract_decl,
            blot_parse_ast::tag_contract_type_member, blot_parse_ast::tag_contract_value_member,
            blot_parse_ast::tag_implementation_decl, blot_parse_ast::tag_effect_decl, blot_parse_ast::tag_effect_type_decl,
            blot_parse_ast::tag_effect_operation, blot_parse_ast::tag_name, blot_parse_ast::tag_intrinsic,
            blot_parse_ast::tag_string, blot_parse_ast::tag_parameter, blot_parse_ast::tag_unary,
            blot_parse_ast::tag_binary, blot_parse_ast::tag_operator_tail, blot_parse_ast::tag_record,
            blot_parse_ast::tag_field, blot_parse_ast::tag_selector, blot_parse_ast::tag_constructor_ref,
            blot_parse_ast::tag_use_stmt, blot_parse_ast::tag_iterator_bind, blot_parse_ast::tag_pattern_name,
            blot_parse_ast::tag_pattern_constructor, blot_parse_ast::tag_pattern_field, blot_parse_ast::tag_pattern_value,
            blot_parse_ast::tag_type_name, blot_parse_ast::tag_type_field, blot_parse_ast::tag_type_binder,
            blot_parse_ast::tag_quantified_binder, blot_parse_ast::tag_comptime_for,
            blot_parse_ast::tag_entry_kernel_decl, blot_parse_ast::tag_entry_process_decl => {if !relocate(prefix,names,node.a) {return false;}},
            _ => {if node.tag>blot_parse_ast::tag_entry_process_decl {return false;}},
        }
    }
    for &origin in tree.operator_origins.items {if !relocate(prefix,names,origin.member) {return false;}}
    return true;
}
fn read_names(packet: const u8[:], at:i64, count:u32, symbols: Pool&, names:u32[>..<]&) -> bool {
    if count>(packet.len-at)/4 {return false;}
    var check=at;
    for index in 0..count {
        if packet.len-check<4 {return false;}
        let length=blot_bytes::get_u32(packet,check);
        check+=4;
        if length>packet.len-check {return false;}
        check+=length;
    }
    if check!=packet.len {return false;}
    var pos=at;
    for index in 0..count {
        let length=blot_bytes::get_u32(packet,pos); pos+=4;
        let symbol,error=symbols.intern(packet[pos..pos+length]);
        if error!=ok {return false;}
        names.push(symbol);
        pos+=length;
    }
    return true;
}

fn decode(packet: const u8[:], symbols: Pool&, tree: Tree&,recorded:blot_parse_parser::ScratchIdBuffer?=null) -> bool {
    if packet.len<9 {return false;}
    let prefix=blot_bytes::get_u32(packet,0);
    let count=blot_bytes::get_u32(packet,4);
    let flags=packet[8];
    if flags>3 || prefix>symbols.entries.len {return false;}
    var parsed,error=blot_parse_ast::initPooled();
    if error!=ok {return false;}
    var at:i64=9;
    var names:u32[>..<]=[];
    if !read_tree(packet,at,parsed) || !read_names(packet,at,count,symbols,names) || !relocate_tree(parsed,prefix,names) {
        parsed.deinit();
        return false;
    }
    if recorded {recorded.append(names[..]);}
    parsed.has_typed_staging=(flags&1)!=0;
    tree.deinit();
    tree=blot_parse_ast::canonical(parsed);
    return true;
}
