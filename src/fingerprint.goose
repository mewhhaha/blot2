import .model;
import .hash;
import .loader;
import .canonical;

fn append_digest(b: CoreBuilder, bytes: const u8[:]) -> Span {
    let digest = k1hash::blake3(bytes); let span = Span { start: b.bytes.len as u32, count: 32 };
    for word in digest.words { for i in 4 { b.bytes.push((word >> (8 * i)) as! u8); } } return span;
}
// Symbolic static graphs survive table relocation. First-visit numbering
// preserves shared-object identity without embedding a producer arena ID.
fn canonical_static(c: Core, object: u32, out: u8[>..]&) -> bool {
    var seen: u32[>..] = []; var visits: u32 = 0;
    fn put(word: u32) {
        visits++; if visits > LIMIT_VISITS || out.len + 4 > LIMIT_ARTIFACT { return false from canonical_static; }
        for byte in 4 { out.push((word >> (8 * byte)) as! u8); }
    }
    fn bytes(value: const u8[:]) {
        put(value.len as u32); if out.len + value.len > LIMIT_ARTIFACT { return false from canonical_static; } out.append(value);
    }
    fn producer(id: u32) {
        if !id_ok(id, c.definitions.len) { return false from canonical_static; }
        let d = c.definitions[id]; let m = c.modules[d.module]; let o = c.origins[d.origin];
        bytes(name_bytes(c, m.path));
        let name = name_bytes(c, d.name);
        // Synthetic pattern names carry a diagnostic source offset. The exact
        // declaration text below identifies the pattern without that origin.
        bytes(if d.kind == DEF_STATIC && starts_with(name, "<pattern:") { "<pattern>" } else { name }); put(d.kind);
        bytes(c.bytes[m.source.start + o.start..m.source.start + o.end]);
    }
    fn origin_owner(origin: Origin) -> u32 {
        if !id_ok(origin.module, c.modules.len) { return false from canonical_static; }
        let declarations = c.modules[origin.module].declarations;
        for i in declarations.count {
            let id = c.refs[declarations.start + i]; let def = c.definitions[id];
            visits++; if visits > LIMIT_VISITS { return false from canonical_static; }
            if !id_ok(def.origin, c.origins.len) { continue; } let p = c.origins[def.origin];
            if p.module == origin.module && p.start <= origin.start && p.end >= origin.end { return id; }
        }
        return false from canonical_static;
    }
    fn function(id: u32) {
        if !id_ok(id, c.functions.len) { return false from canonical_static; }
        let f = c.functions[id]; let origin = c.origins[f.origin];
        let owner = if f.producer != 0 { f.producer } else { origin_owner(origin) }; producer(owner);
        let parent = c.origins[c.definitions[owner].origin];
        if origin.start < parent.start || origin.end > parent.end { return false from canonical_static; }
        put(origin.start - parent.start); put(origin.end - parent.start);
        if !canonical_interface(c, f.type_id, out) { return false from canonical_static; }
    }
    recursive fn visit(id: u32, depth: u32) {
        if !id_ok(id, c.static_objects.len) || depth > 64 { return false from canonical_static; }
        for prior, i in seen { visits++; if visits > LIMIT_VISITS { return false from canonical_static; } if prior == id { put(0); put(i as u32 + 1); return; } }
        seen.push(id); put(1); put(seen.len as u32);
        let row = c.static_objects[id]; producer(row.producer); put(row.kind); put(row.count);
        if !canonical_interface(c, row.type_id, out) { return false from canonical_static; }
        bytes(c.bytes[row.bytes.start..row.bytes.start + row.bytes.count]); put(row.relocations.count);
        for i in row.relocations.count {
            let r = c.static_relocations[c.refs[row.relocations.start + i]]; put(r.offset); put(r.kind);
            if r.kind == STATIC_ADDRESS { put(r.addend); visit(r.target, depth + 1); }
            else if r.kind == STATIC_FUNCTION { put(r.addend); function(r.target); }
            else if r.kind == STATIC_DICTIONARY { put(r.addend); if !canonical_interface(c, r.target, out) { return false from canonical_static; } }
            else if r.kind == STATIC_CLOSURE {
                if !id_ok(r.target, c.ops.len) { return false from canonical_static; }
                let op = c.ops[r.target]; function(op.imm0);
                let origin = c.origins[op.origin]; let owner = origin_owner(origin);
                producer(owner); let parent = c.origins[c.definitions[owner].origin];
                put(origin.start - parent.start); put(origin.end - parent.start);
                put(if r.addend == 0 { 0 } else { 1 }); if r.addend != 0 { visit(r.addend, depth + 1); }
            } else { return false from canonical_static; }
        }
    }
    visit(object, 0); return true;
}
fn fingerprint_interfaces(b: CoreBuilder, diags: Diagnostic[>..]&) -> bool {
    for row, i in b.interfaces {
        if i == 0 { continue; }
        var bytes: u8[>..] = [];
        if !canonical_interface(core_view(b), row.type_id, bytes) { return loader_error(diags, 4016, 0); }
        b.interfaces[i].digest = append_digest(b, bytes);
    }
    for row, i in b.dependencies {
        if i == 0 { continue; }
        var canonical: u8[>..] = [];
        canonical.append(ABI_HASH); canonical.push(row.query_kind as! u8);
        canonical.append(b.bytes[row.identity.start..row.identity.start + row.identity.count]);
        canonical.push(if row.present { 1 } else { 0 });
        if row.present {
            if !id_ok(row.producer, b.definitions.len) { return loader_error(diags, 4016, 0); }
            let def = b.definitions[row.producer];
            if !canonical_interface(core_view(b), def.type_id, canonical) { return loader_error(diags, 4016, def.origin); }
            if row.kind == DEP_BODY {
                let origin = b.origins[def.origin]; let module_row = b.modules[def.module];
                canonical.append(b.bytes[module_row.source.start + origin.start..module_row.source.start + origin.end]);
            }
            if row.kind == DEP_STATIC {
                if !id_ok(def.value, b.values.len) { return loader_error(diags, 4016, def.origin); }
                let op = b.ops[b.values[def.value].op];
                if op.tag != OP_STATIC || !id_ok(op.imm0, b.static_objects.len) { return loader_error(diags, 4016, def.origin); }
                if !canonical_static(core_view(b), op.imm0, canonical) { return loader_error(diags, 4016, def.origin); }
            }
        }
        b.dependencies[i].digest = append_digest(b, canonical);
    }
    for row, i in b.receipts {
        if i == 0 || !id_ok(row.producer, b.definitions.len) { continue; }
        let def = b.definitions[row.producer];
        if !id_ok(def.origin, b.origins.len) { continue; }
        let origin = b.origins[def.origin]; let module_row = b.modules[origin.module];
        let source = b.bytes[module_row.source.start + origin.start..module_row.source.start + origin.end];
        b.receipts[i].source_digest = append_digest(b, source);
        var semantic: u8[>..] = []; semantic.append(ABI_HASH);
        for byte in 4 { semantic.push((SEM_POLICY >> (8 * byte)) as! u8); }
        semantic.append(source);
        for j in row.dependencies.count {
            let dependency = b.dependencies[b.refs[row.dependencies.start + j]];
            semantic.append(b.bytes[dependency.digest.start..dependency.digest.start + dependency.digest.count]);
        }
        b.receipts[i].semantic_digest = append_digest(b, semantic);
    }
    return true;
}
fn canonical_schemas(b: CoreBuilder, diags: Diagnostic[>..]&) -> bool {
    for layout, i in b.layouts {
        if i == 0 { continue; }
        var canonical: u8[>..] = [];
        if !canonical_interface(core_view(b), layout.type_id, canonical) { return loader_error(diags, 4016, 0); }
        for word in [layout.size, layout.align, layout.flags, layout.abi] {
            for byte in 4 { canonical.push((word >> (8 * byte)) as! u8); }
        }
        var id: u32 = 0;
        for schema, si in b.schemas {
            if si == 0 || schema.bytes.count != canonical.len { continue; }
            if b.bytes[schema.bytes.start..schema.bytes.start + schema.bytes.count] == canonical { id = si as u32; break; }
        }
        if id == 0 {
            let bytes = Span { start: b.bytes.len as u32, count: canonical.len as u32 }; b.bytes.append(canonical);
            let digest = append_digest(b, canonical); id = b.schemas.len as u32;
            b.schemas.push(Schema { bytes: bytes, digest: digest });
        }
        b.layouts[i].schema = id;
    }
    return true;
}
