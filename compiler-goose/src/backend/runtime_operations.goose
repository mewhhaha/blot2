namespace blot_backend_runtime_operations;
import std;
import dictionary;
import .runtime_ir;
import .runtime_identity;
import .wasm;
import .optimizer_buffers;
import eval.type_evidence;
import check.effect_evidence;
import reuse.artifact_emitter;
import support.option;
import support.error;

type Id = u32;
let max_key_bytes: i64 = 1048576;
struct Entry { key: blot_backend_runtime_ir::Range, foreign: bool = false, runtime: u32 = 0, next: Id = 0 }
struct Location { word: bool = false, function: u32 = 0, index: u32 = 0 }
struct Relocation { operation: Id, location: Location }
struct Encoder { view: blot_eval_type_evidence::View, identity: blot_support::Option<blot_backend_runtime_identity::View>, bytes: u8[>..<]& }
fn raw(encoder: Encoder&, bytes: const u8[:]) -> blot_error::Error {
    if encoder.bytes.len > max_key_bytes || bytes.len > max_key_bytes - encoder.bytes.len { return blot_error::Error.module_too_large; }
    encoder.bytes.append(bytes); return blot_error::Error.none;
}
fn word(encoder: Encoder&, value: u32) -> blot_error::Error {
    let bytes: u8[4] = [(value >> 24) as! u8, (value >> 16) as! u8, (value >> 8) as! u8, value as! u8]; return raw(encoder, bytes);
}
fn count(encoder: Encoder&, value: i64) -> blot_error::Error { if value > 4294967295 { return blot_error::Error.module_too_large; } return word(encoder, value as u32); }
fn owner(encoder: Encoder&, unit: u32) -> blot_error::Error {
    if encoder.identity.present {
        if unit == 0 || unit == 4294967295 { let error = raw(encoder, [0]); if error != blot_error::Error.none { return error; } return word(encoder, unit); }
        let path = blot_backend_runtime_identity::owner(encoder.identity.value, unit); if !path.present { return blot_error::Error.invalid_operation; }
        var error = raw(encoder, [1]); if error != blot_error::Error.none { return error; }
        error = count(encoder, path.value.len); if error != blot_error::Error.none { return error; } return raw(encoder, path.value);
    }
    return word(encoder, unit);
}
recursive fn operation(encoder: Encoder&, label: blot_check_effect_evidence::Label, depth: i64) -> blot_error::Error {
    if depth >= 1024 || label == 0 || label >= encoder.view.effects.operations.len { return blot_error::Error.invalid_operation; }
    let operation = encoder.view.effects.operation(label);
    if operation.identity.decl == 0 || operation.arguments.start > encoder.view.effects.arguments.len || operation.arguments.len > encoder.view.effects.arguments.len - operation.arguments.start { return blot_error::Error.invalid_operation; }
    let arguments = encoder.view.effects.operationArguments(label);
    if operation.identity.unit == 0 && operation.identity.decl == 1 && arguments.len != 0 { return blot_error::Error.invalid_operation; }
    var error = owner(encoder, operation.identity.unit); if error != blot_error::Error.none { return error; }
    error = word(encoder, operation.identity.decl); if error != blot_error::Error.none { return error; }
    error = count(encoder, arguments.len); if error != blot_error::Error.none { return error; }
    for argument in arguments { error = ty(encoder, argument, depth + 1); if error != blot_error::Error.none { return error; } }
    return blot_error::Error.none;
}
fn lessBytes(left: const u8[:], right: const u8[:]) -> bool {
    var length = left.len; if right.len < length { length = right.len; }
    for index in 0..length { if left[index] != right[index] { return left[index] < right[index]; } } return left.len < right.len;
}
recursive fn row(encoder: Encoder&, id: u32, depth: i64) -> blot_error::Error {
    if depth >= 1024 || id >= encoder.view.effects.rows.len { return blot_error::Error.invalid_operation; }
    let span = encoder.view.effects.rows[id]; if span.start > encoder.view.effects.labels.len || span.len > encoder.view.effects.labels.len - span.start { return blot_error::Error.invalid_operation; }
    var keys: blot_backend_runtime_ir::Range[>..<] = []; var bytes: u8[>..<] = [];
    for label in encoder.view.effects.rowLabels(id) {
        var child_bytes: u8[>..<] = []; let child = Encoder { view: encoder.view, identity: encoder.identity, bytes: child_bytes , ..};
        let error = operation(child, label, depth + 1); if error != blot_error::Error.none { return error; }
        keys.push(blot_backend_runtime_ir::Range { start: bytes.len, len: child_bytes.len , ..}); bytes.append(child_bytes);
    }
    // Exact multiset order keeps duplicate operations.
    let key_count = keys.len;
    for index in 1..key_count { let key = keys[index]; var next = index; while next > 0 { let previous = keys[next - 1]; if !lessBytes(bytes[key.start..key.start + key.len], bytes[previous.start..previous.start + previous.len]) { break; } keys[next] = previous; next--; } keys[next] = key; }
    var error = count(encoder, keys.len); if error != blot_error::Error.none { return error; }
    for key in keys { error = count(encoder, key.len); if error != blot_error::Error.none { return error; } error = raw(encoder, bytes[key.start..key.start + key.len]); if error != blot_error::Error.none { return error; } }
    return blot_error::Error.none;
}
struct Field { name: const u8[:], ty: u32 }
recursive fn ty(encoder: Encoder&, id: u32, depth: i64) -> blot_error::Error {
    if depth >= 1024 || id == 0 || id >= encoder.view.nodes.len { return blot_error::Error.invalid_operation; }
    let node = encoder.view.node(id); var error = raw(encoder, [blot_eval_type_evidence::tagCode(node.tag)]); if error != blot_error::Error.none { return error; }
    if node.tag == blot_eval_type_evidence::Tag.projection || node.tag == blot_eval_type_evidence::Tag.scoped || node.tag == blot_eval_type_evidence::Tag.forall || node.tag == blot_eval_type_evidence::Tag.existential || node.tag == blot_eval_type_evidence::Tag.bound || node.tag == blot_eval_type_evidence::Tag.usage || node.tag == blot_eval_type_evidence::Tag.absent { return blot_error::Error.invalid_operation; }
    if node.tag == blot_eval_type_evidence::Tag.unit || node.tag == blot_eval_type_evidence::Tag.boolean || node.tag == blot_eval_type_evidence::Tag.unsigned32 || node.tag == blot_eval_type_evidence::Tag.floating32 || node.tag == blot_eval_type_evidence::Tag.never || node.tag == blot_eval_type_evidence::Tag.erased_proof { return blot_error::Error.none; }
    if node.tag == blot_eval_type_evidence::Tag.function || node.tag == blot_eval_type_evidence::Tag.provider {
        error = ty(encoder, node.a, depth + 1); if error != blot_error::Error.none { return error; }
        if node.tag == blot_eval_type_evidence::Tag.function { error = ty(encoder, node.b, depth + 1); if error != blot_error::Error.none { return error; } }
        return row(encoder, node.c, depth + 1);
    }
    if node.tag == blot_eval_type_evidence::Tag.array || node.tag == blot_eval_type_evidence::Tag.list || node.tag == blot_eval_type_evidence::Tag.cursor || node.tag == blot_eval_type_evidence::Tag.resolver { return ty(encoder, node.a, depth + 1); }
    if node.tag == blot_eval_type_evidence::Tag.state_provider {
        for child in [node.a, node.b, node.c] { error = ty(encoder, child, depth + 1); if error != blot_error::Error.none { return error; } } return blot_error::Error.none;
    }
    if node.tag == blot_eval_type_evidence::Tag.type_constructor || node.tag == blot_eval_type_evidence::Tag.nominal {
        error = owner(encoder, node.a); if error != blot_error::Error.none { return error; } error = word(encoder, node.b); if error != blot_error::Error.none { return error; }
        if node.tag == blot_eval_type_evidence::Tag.type_constructor { return blot_error::Error.none; }
        if node.c >= encoder.view.extra.len { return blot_error::Error.invalid_operation; } let length = encoder.view.extra[node.c];
        if length > encoder.view.extra.len - node.c - 1 { return blot_error::Error.invalid_operation; }
        error = count(encoder, length); if error != blot_error::Error.none { return error; }
        for child in encoder.view.children(id) { error = ty(encoder, child, depth + 1); if error != blot_error::Error.none { return error; } } return blot_error::Error.none;
    }
    if node.tag == blot_eval_type_evidence::Tag.product {
        if node.a > encoder.view.extra.len || node.b > encoder.view.extra.len - node.a { return blot_error::Error.invalid_operation; }
        error = count(encoder, node.b); if error != blot_error::Error.none { return error; }
        for child in encoder.view.children(id) { error = ty(encoder, child, depth + 1); if error != blot_error::Error.none { return error; } } return blot_error::Error.none;
    }
    if node.tag != blot_eval_type_evidence::Tag.record { return blot_error::Error.invalid_operation; }
    if node.a > encoder.view.extra.len || node.b > (encoder.view.extra.len - node.a) / 2 { return blot_error::Error.invalid_operation; }
    let fields = encoder.view.children(id);
    if encoder.identity.present {
        var ordered: Field[>..<] = [];
        for index in 0..node.b { let name = blot_backend_runtime_identity::symbol(encoder.identity.value, fields[index * 2]); if !name.present { return blot_error::Error.invalid_operation; } ordered.push(Field { name: name.value, ty: fields[index * 2 + 1] , ..}); }
        let length = ordered.len;
        for index in 1..length { let field = ordered[index]; var next = index; while next > 0 && lessBytes(field.name, ordered[next - 1].name) { ordered[next] = ordered[next - 1]; next--; } ordered[next] = field; }
        error = count(encoder, ordered.len); if error != blot_error::Error.none { return error; }
        for field, index in ordered {
            if field.name.len == 0 || (index != 0 && blot_backend_runtime_identity::equalBytes(ordered[index - 1].name, field.name)) { return blot_error::Error.invalid_operation; }
            error = count(encoder, field.name.len); if error != blot_error::Error.none { return error; } error = raw(encoder, field.name); if error != blot_error::Error.none { return error; } error = ty(encoder, field.ty, depth + 1); if error != blot_error::Error.none { return error; }
        }
        return blot_error::Error.none;
    }
    var prior: u32 = 0; error = count(encoder, node.b); if error != blot_error::Error.none { return error; }
    for index in 0..node.b { let name = fields[index * 2]; if name <= prior { return blot_error::Error.invalid_operation; } prior = name; error = word(encoder, name); if error != blot_error::Error.none { return error; } error = ty(encoder, fields[index * 2 + 1], depth + 1); if error != blot_error::Error.none { return error; } }
    return blot_error::Error.none;
}
struct Store {
    identity: blot_support::Option<blot_backend_runtime_identity::View>, entries: Entry[>..<]&, key_bytes: blot_backend_optimizer_buffers::Bytes&, keys: dictionary<u64, Id>&,
    relocations: Relocation[>..<]&, finalized: bool = false, artifacts: blot_reuse_artifact_emitter::Recorder&? = null,
}
fn init(entries: Entry[>..<]&, key_bytes: blot_backend_optimizer_buffers::Bytes&, keys: dictionary<u64, Id>&, relocations: Relocation[>..<]&) -> Store { Store { entries: entries, key_bytes: key_bytes, keys: keys, relocations: relocations } }
fn initProject(entries: Entry[>..<]&, key_bytes: blot_backend_optimizer_buffers::Bytes&, keys: dictionary<u64, Id>&, relocations: Relocation[>..<]&, names: blot_backend_runtime_identity::View) -> Store { var store = init(entries, key_bytes, keys, relocations); store.identity = blot_support::some(names); return store; }
fn key(store: Store&, entry: Entry) -> const u8[:] { store.key_bytes.items[entry.key.start..entry.key.start + entry.key.len] }
fn intern(store: Store&, view: blot_eval_type_evidence::View, label: blot_check_effect_evidence::Label) -> Id, blot_error::Error {
    if store.finalized { return 0, blot_error::Error.invalid_operation; }
    var bytes: u8[>..<] = []; let encoder = Encoder { view: view, identity: store.identity, bytes: bytes , ..};
    var domain: u8 = 'S'; if store.identity.present { domain = 'P'; }
    var error = raw(encoder, [1, domain]); if error != blot_error::Error.none { return 0, error; }
    error = operation(encoder, label, 0); if error != blot_error::Error.none { return 0, error; }
    let identity = view.effects.operation(label).identity; return internSymbol(store, bytes, identity.unit == 0 && identity.decl == 1);
}
fn internSymbol(store: Store&, bytes: const u8[:], foreign: bool) -> Id, blot_error::Error {
    var domain: u8 = 'S'; if store.identity.present { domain = 'P'; }
    if store.finalized || bytes.len < 2 || bytes[0] != 1 || bytes[1] != domain { return 0, blot_error::Error.invalid_operation; }
    let fingerprint = ::hash(bytes); var candidate: Id = 0; block { let found = store.keys.get(fingerprint); if found { candidate = found; } }
    while candidate != 0 {
        let entry = store.entries[candidate - 1];
        if blot_backend_runtime_identity::equalBytes(key(store, entry), bytes) {
            if entry.foreign != foreign { return 0, blot_error::Error.invalid_operation; }
            if store.artifacts { let error = blot_reuse_artifact_emitter::recordDemand(store.artifacts, blot_reuse_artifact_emitter::ResourceKind.operation, candidate, true); if error != blot_error::Error.none { return 0, error; } }
            return candidate, blot_error::Error.none;
        }
        candidate = entry.next;
    }
    if store.entries.len >= 4294967293 { return 0, blot_error::Error.module_too_large; }
    let id = (store.entries.len + 1) as Id;
    if store.artifacts {
        var error = blot_reuse_artifact_emitter::operationSymbol(store.artifacts, id, bytes, foreign); if error != blot_error::Error.none { return 0, error; }
        error = blot_reuse_artifact_emitter::recordDemand(store.artifacts, blot_reuse_artifact_emitter::ResourceKind.operation, id, false); if error != blot_error::Error.none { return 0, error; }
    }
    let range = blot_backend_runtime_ir::Range { start: store.key_bytes.len, len: bytes.len , ..}; let appended=store.key_bytes.append(bytes);if appended!=blot_error::Error.none {return 0,appended;}
    var previous: Id = 0; block { let found = store.keys.get(fingerprint); if found { previous = found; } }
    store.entries.push(Entry { key: range, foreign: foreign, next: previous , ..}); store.keys.insert(fingerprint, id); return id, blot_error::Error.none;
}
fn emit(store: Store&, module: blot_backend_wasm::Module&, function: u32, operation: Id) -> blot_error::Error {
    if store.finalized || operation == 0 || operation > store.entries.len || function >= module.functions.len { return blot_error::Error.invalid_operation; }
    let index = module.functions[function].instructions.len; if index > 4294967295 { return blot_error::Error.module_too_large; }
    let error = blot_backend_wasm::emitReference(module, function, blot_backend_runtime_ir::instruction(blot_backend_runtime_ir::OP_i32_const, operation), blot_reuse_artifact_emitter::Role.operation); if error != blot_error::Error.none { return error; }
    module.instructions[module.functions[function].instructions.start + index].operand = 0;
    store.relocations.push(Relocation { operation: operation, location: Location { function: function, index: index as u32 , ..} , ..}); return blot_error::Error.none;
}
fn dataWord(store: Store&, module: blot_backend_wasm::Module&, address: u32, operation: Id) -> blot_error::Error {
    if store.finalized || operation == 0 || operation > store.entries.len || address % 4 != 0 || address > module.data.len || 4 > module.data.len - address { return blot_error::Error.invalid_operation; }
    let error = blot_backend_wasm::dataReference(module, address, blot_reuse_artifact_emitter::Operand { role: blot_reuse_artifact_emitter::Role.operation, value: operation , ..}); if error != blot_error::Error.none { return error; }
    store.relocations.push(Relocation { operation: operation, location: Location { word: true, index: address , ..} , ..}); return blot_error::Error.none;
}
fn finish(store: Store&, module: blot_backend_wasm::Module&) -> blot_error::Error {
    if store.finalized { return blot_error::Error.invalid_operation; }
    var ordered: Id[>..<] = []; for index in 0..store.entries.len { ordered.push(index as Id); }
    let count = ordered.len;
    for index in 1..count { let value = ordered[index]; var next = index; while next > 0 && lessBytes(key(store, store.entries[value]), key(store, store.entries[ordered[next - 1]])) { ordered[next] = ordered[next - 1]; next--; } ordered[next] = value; }
    var sites = dictionary<u64, bool> {};
    for relocation in store.relocations {
        if relocation.operation == 0 || relocation.operation > store.entries.len { return blot_error::Error.invalid_operation; }
        let location = relocation.location; var function = location.function; if location.word { function = 4294967295; }
        let site = (function as u64 << 32) | location.index; if sites.contains(site) { return blot_error::Error.invalid_operation; } sites.insert(site, true);
        if location.word {
            let address = location.index; if address % 4 != 0 || address > module.data.len || 4 > module.data.len - address || blot_backend_wasm::readDataWord(module, address) != 0 { return blot_error::Error.invalid_operation; }
        } else {
            if location.function >= module.functions.len { return blot_error::Error.invalid_operation; }
            let code = module.functions[location.function].instructions; if location.index >= code.len { return blot_error::Error.invalid_operation; }
            let inst = module.instructions[code.start + location.index]; if inst.op != blot_backend_runtime_ir::OP_i32_const || inst.operand != 0 { return blot_error::Error.invalid_operation; }
        }
    }
    var next: u32 = 2;
    for index in ordered { if store.entries[index].foreign { store.entries[index].runtime = 1; } else { store.entries[index].runtime = next; next++; } }
    for relocation in store.relocations { let id = store.entries[relocation.operation - 1].runtime; let location = relocation.location; if location.word { blot_backend_wasm::writeDataWord(module, location.index, id); } else { module.instructions[module.functions[location.function].instructions.start + location.index].operand = id; } }
    store.finalized = true; return blot_error::Error.none;
}
fn projectKey(store: Store&, operation: Id) -> blot_support::Option<const u8[:]> { if !store.identity.present || operation == 0 || operation > store.entries.len { return blot_support::none<const u8[:]>(); } return blot_support::some(key(store, store.entries[operation - 1])); }
fn runtimeId(store: Store&, operation: Id) -> blot_support::Option<u32> { if !store.finalized || operation == 0 || operation > store.entries.len { return blot_support::none<u32>(); } return blot_support::some(store.entries[operation - 1].runtime); }
fn deinit(store: Store&) { store.entries.clear(); store.key_bytes.clear(); store.keys.clear(); store.relocations.clear(); store.finalized = false; }
