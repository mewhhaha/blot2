namespace blot_backend_machine_code_sharing;
import dictionary;
import .wasm;
import .runtime_function_key;
import support.error;

let absent: u32 = 4294967295;
struct Index { canonical: u32[>..<]&, indexes: u32[>..<]&, unique: i64 = 0 }
fn emits(index: Index&, id: i64) -> bool { index.canonical.len == 0 || index.canonical[id] == id }
fn function(index: Index&, id: u32) -> u32 { if index.indexes.len == 0 { return id; } return index.indexes[id]; }
fn init(canonical: u32[>..<]&, indexes: u32[>..<]&, module: blot_backend_wasm::Module&, enabled: bool) -> Index, blot_error::Error {
    var prepared: blot_backend_wasm::Prepared[>..<] = []; for item in module.functions { prepared.push(blot_backend_wasm::Prepared {..}); }
    return initPrepared(canonical, indexes, module, prepared, enabled);
}
fn initPrepared(canonical: u32[>..<]&, indexes: u32[>..<]&, module: blot_backend_wasm::Module&, prepared: const blot_backend_wasm::Prepared[:], enabled: bool) -> Index, blot_error::Error {
    let count = module.functions.len; canonical.clear(); indexes.clear(); var result = Index { canonical: canonical, indexes: indexes, unique: count , ..};
    if count > 4294967295 - module.imports.len { return result, blot_error::Error.module_too_large; }
    if !enabled { return result, blot_error::Error.none; }
    result.unique = 0; var next: u32[>..<] = []; var public: bool[>..<] = [];
    for id in 0..count { canonical.push(0); indexes.push(0); next.push(absent); public.push(false); }
    for item in module.exports { if !item.global && item.index < count { public[item.index] = true; } }
    if module.public_arena { public[module.arena.value.allocate] = true; public[module.arena.value.reset] = true; }
    var buckets = dictionary<u64, u32> {};
    for id in 0..count {
        let body = blot_backend_wasm::preparedView(module, prepared, id); var fingerprint: u64 = 0; var candidate = absent;
        if !public[id] {
            fingerprint = blot_backend_runtime_function_key::hash(module, body);
            let found = buckets.get(fingerprint); if found { candidate = found; }
        }
        while candidate != absent {
            if blot_backend_runtime_function_key::equal(module, blot_backend_wasm::preparedView(module, prepared, candidate), module, body) { break; }
            candidate = next[candidate];
        }
        if candidate != absent { canonical[id] = candidate; indexes[id] = indexes[candidate]; continue; }
        canonical[id] = id as u32; indexes[id] = result.unique as u32; result.unique++;
        if !public[id] { let found = buckets.get(fingerprint); if found { next[id] = found; } buckets.insert(fingerprint, id as u32); }
    }
    return result, blot_error::Error.none;
}
